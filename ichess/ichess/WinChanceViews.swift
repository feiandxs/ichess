//
//  WinChanceViews.swift
//  ichess
//
//  胜率相关的共用视图：曲线图（实时趋势 / 复盘）、胜率条、棋盘 + 胜率条的布局、棋盘下方的趋势面板。
//  数值都是「玩家（白方）的胜率 0...100」，由 GameAnalysis 从引擎评分换算。
//

import Charts
import SwiftUI

/// 玩家胜率曲线。full：复盘用，带坐标轴，可点按 / 拖动选择；compact：实时趋势，只有线。
struct WinChanceChart: View {
    @EnvironmentObject private var theme: ThemeStore

    let values: [Double?]
    var selected: Int?
    /// 不为 nil 时可点按 / 拖动选择某个局面。
    var onSelect: ((Int) -> Void)?
    /// 局面下标 → 评级，只给有问题的步标点。
    var marks: [Int: MoveVerdict] = [:]
    var compact = false

    private struct Point: Identifiable {
        let ply: Int
        let value: Double
        var id: Int { ply }
    }

    private var points: [Point] {
        values.enumerated().compactMap { ply, value in value.map { Point(ply: ply, value: $0) } }
    }

    var body: some View {
        let palette = theme.palette
        let maxPly = max(values.count - 1, compact ? 8 : 1)
        Chart {
            RuleMark(y: .value("Even", 50))
                .foregroundStyle(palette.secondaryText.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(points) { point in
                AreaMark(x: .value("Move", point.ply), yStart: .value("Even", 50), yEnd: .value("Win", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.chartLine.opacity(0.22))
                LineMark(x: .value("Move", point.ply), y: .value("Win", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.chartLine)
                    .lineStyle(StrokeStyle(lineWidth: compact ? 2 : 2.5, lineCap: .round, lineJoin: .round))
            }
            if compact, let last = points.last {
                PointMark(x: .value("Move", last.ply), y: .value("Win", last.value))
                    .symbolSize(40)
                    .foregroundStyle(palette.chartLine)
            }
            ForEach(points.filter { marks[$0.ply] != nil }) { point in
                if let verdict = marks[point.ply] {
                    PointMark(x: .value("Move", point.ply), y: .value("Win", point.value))
                        .symbolSize(50)
                        .foregroundStyle(palette.verdict(verdict))
                }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(palette.primaryText.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                if let point = points.first(where: { $0.ply == selected }) {
                    PointMark(x: .value("Move", point.ply), y: .value("Win", point.value))
                        .symbolSize(90)
                        .foregroundStyle(palette.primaryText)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: 0...maxPly)
        .chartYAxis {
            if compact {
                AxisMarks(values: [Double]()) { _ in }
            } else {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(palette.secondaryText.opacity(0.15))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: "\(Int(number))%").font(.caption2).foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartOverlay { proxy in
            if let onSelect {
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { drag in
                                guard let frame = proxy.plotFrame else { return }
                                let x = drag.location.x - geo[frame].origin.x
                                if let ply: Double = proxy.value(atX: x) {
                                    onSelect(min(max(0, Int(ply.rounded())), max(values.count - 1, 0)))
                                }
                            }
                        )
                }
            }
        }
    }
}

/// 胜率条：白色一侧是玩家（白方）、深色一侧是对手，各标出百分数。
/// 高大于宽时竖放（白在下），否则横放（白在左）。
struct WinBarView: View {
    @EnvironmentObject private var theme: ThemeStore

    /// 玩家胜率；还没有评估时为 nil。
    let value: Double?
    /// false：当前局面还在计算，显示的是上一个局面的值，调暗。
    var isCurrent = true

    var body: some View {
        let palette = theme.palette
        GeometryReader { geo in
            let vertical = geo.size.height > geo.size.width
            let white = (value ?? 50) / 100
            let length = vertical ? geo.size.height : geo.size.width
            let whiteLength = length * white
            let blackLength = length - whiteLength
            Group {
                if vertical {
                    VStack(spacing: 0) {
                        segment(palette.winBarBlack, text: label(100 - (value ?? 50)), textColor: .white, length: blackLength, vertical: true, alignment: .top)
                        segment(palette.winBarWhite, text: label(value ?? 50), textColor: .black, length: whiteLength, vertical: true, alignment: .bottom)
                    }
                } else {
                    HStack(spacing: 0) {
                        segment(palette.winBarWhite, text: label(value ?? 50), textColor: .black, length: whiteLength, vertical: false, alignment: .leading)
                        segment(palette.winBarBlack, text: label(100 - (value ?? 50)), textColor: .white, length: blackLength, vertical: false, alignment: .trailing)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.boardBorder, lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.4), value: value)
        }
        .opacity(isCurrent ? 1 : 0.55)
        .animation(.easeOut(duration: 0.2), value: isCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Win chances"))
        .accessibilityValue(Text(verbatim: value.map { "\(Int($0.rounded()))%" } ?? "–"))
    }

    private func label(_ percent: Double) -> String {
        value == nil ? "" : "\(Int(percent.rounded()))"
    }

    private func segment(_ fill: Color, text: String, textColor: Color, length: CGFloat, vertical: Bool, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            fill
            // 太窄放不下数字就不显示。
            if length >= (vertical ? 18 : 30), !text.isEmpty {
                Text(verbatim: vertical ? text : text + "%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .padding(vertical ? .vertical : .horizontal, 4)
            }
        }
        .frame(width: vertical ? nil : length, height: vertical ? length : nil)
    }
}

/// 棋盘 + 胜率条：棋盘右侧有富余宽度就竖放（iPad、Mac、横屏），否则横放在棋盘正下方。
/// 棋盘始终是正方形，高度不够时一起缩小；没有胜率条时就是普通的方形棋盘。
struct BoardBarLayout: Layout {
    var thickness: CGFloat = 22
    var gap: CGFloat = 6

    private func plan(_ proposal: ProposedViewSize, hasBar: Bool) -> (side: CGFloat, vertical: Bool) {
        let width = proposal.width ?? 360
        let height = proposal.height ?? width
        guard hasBar else { return (max(0, min(width, height)), false) }
        if width - height >= thickness + gap {
            return (max(0, min(height, width - thickness - gap)), true)
        }
        return (max(0, min(width, height - thickness - gap)), false)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = plan(proposal, hasBar: subviews.count > 1)
        guard subviews.count > 1 else { return CGSize(width: p.side, height: p.side) }
        return p.vertical
            ? CGSize(width: p.side + gap + thickness, height: p.side)
            : CGSize(width: p.side, height: p.side + gap + thickness)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(ProposedViewSize(width: bounds.width, height: bounds.height), hasBar: subviews.count > 1)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: p.side, height: p.side))
        guard subviews.count > 1 else { return }
        if p.vertical {
            subviews[1].place(
                at: CGPoint(x: bounds.minX + p.side + gap, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: thickness, height: p.side)
            )
        } else {
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + p.side + gap), anchor: .topLeading,
                proposal: ProposedViewSize(width: p.side, height: thickness)
            )
        }
    }
}

/// 棋盘下方的胜率趋势：当前胜率、最近一步带来的变化，和一条小曲线。高度固定。
struct WinTrendRow: View {
    @EnvironmentObject private var game: ChessGameStore
    @EnvironmentObject private var theme: ThemeStore
    static let rowHeight: CGFloat = 52

    var body: some View {
        let palette = theme.palette
        let latest = game.winLatest
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your win chances")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: latest.map { "\(Int($0.value.rounded()))%" } ?? "–")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                        .opacity(latest?.isCurrent == false ? 0.5 : 1)
                    if let delta = latest?.delta, latest?.isCurrent == true {
                        let rounded = Int(delta.rounded())
                        Text(verbatim: rounded > 0 ? "+\(rounded)%" : "\(rounded)%")
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(rounded > 0 ? palette.gain : (rounded < 0 ? palette.loss : palette.secondaryText))
                    } else if latest?.isCurrent == false {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
            .frame(minWidth: 96, alignment: .leading)
            WinChanceChart(values: game.winSeries, compact: true)
        }
        .frame(height: Self.rowHeight)
    }
}

/// 对战局（没有教练区）里单独显示的紧凑胜率面板。
struct WinChancePanel: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        WinTrendRow()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.palette.chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
