//
//  ReviewView.swift
//  ichess
//
//  复盘：只读棋盘 + 着法列表 + 胜率曲线 + 每步点评。练习局、对战局、没下完的对局都能看。
//  窄屏（iPhone）：棋盘、控制条、着法条固定在上方，其余内容在下方滚动；宽屏（iPad / Mac）：左棋盘右内容。
//

import ChessKit
import SwiftUI

/// 整页顶栏：左上角返回按钮 + 居中标题。复盘 / 对局记录都占满整个窗口，不用弹层。
struct PageHeader: View {
    let title: LocalizedStringKey
    let onBack: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        let palette = theme.palette
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            HStack {
                Button(action: onBack) {
                    Label("Go back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.chipFill)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.chipText)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ReviewView: View {
    let recordID: String
    var initialPly: Int?
    let onBack: () -> Void

    @ObservedObject private var archive = GameArchive.shared
    @ObservedObject private var analyzer = PostGameAnalyzer.shared
    @EnvironmentObject private var theme: ThemeStore
    @State private var ply = 0
    @State private var didSetup = false
    /// 正在分步演示的引擎变例（复盘棋盘显示它）；换一步就收起。
    @State private var demo: LineDemo?

    var body: some View {
        let palette = theme.palette
        VStack(spacing: 0) {
            PageHeader(title: "Review", onBack: onBack)
            Group {
                if let record = archive.record(recordID) {
                    content(record, palette: palette)
                } else {
                    ContentUnavailableView("This game is no longer available.", systemImage: "tray")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.canvas.ignoresSafeArea())
        .onAppear(perform: setup)
        .onChange(of: ply) { _, _ in demo = nil }
    }

    private func setup() {
        guard !didSetup, let record = archive.record(recordID) else { return }
        didSetup = true
        if let initialPly {
            ply = min(max(0, initialPly), record.moves.count)
        } else {
            // 默认停在最大的失误上，没有就停在终局。
            let report = GameAnalysis.report(startEval: record.startEval, moves: record.moves)
            ply = report.keyMoment.map { $0.index + 1 } ?? record.moves.count
        }
        // 没分析完的接着分析（后台优先级，不影响正在进行的对局）。
        analyzer.enqueue(recordID)
    }

    // MARK: - 布局

    private func content(_ record: GameRecord, palette: BoardPalette) -> some View {
        let report = GameAnalysis.report(startEval: record.startEval, moves: record.moves)
        let current = min(ply, record.moves.count)
        return GeometryReader { geo in
            if geo.size.width >= 700 {
                // 宽屏：左列棋盘 + 控制条 + 着法列表，右列各种卡片，两列各自滚动；棋盘随窗口放大。
                let pad: CGFloat = 16
                let controlsHeight: CGFloat = 48
                let listMin: CGFloat = geo.size.height > 640 ? 150 : 90
                let side = max(160, min(geo.size.width * 0.55 - pad, geo.size.height - pad * 2 - controlsHeight - listMin))
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 12) {
                        board(record, ply: current, side: side)
                        controls(record, palette: palette)
                        moveList(record, report, palette: palette)
                    }
                    .frame(width: side)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            summary(record, report, palette: palette)
                            detail(record, report, ply: current, palette: palette)
                            graph(record, report, palette: palette)
                            keyMistakes(report, palette: palette)
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(pad)
            } else {
                let side = max(200, min(geo.size.width - 32, geo.size.height * 0.45))
                VStack(spacing: 10) {
                    board(record, ply: current, side: side)
                    controls(record, palette: palette)
                        .padding(.horizontal, 16)
                    moveStrip(record, report, palette: palette)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            summary(record, report, palette: palette)
                            detail(record, report, ply: current, palette: palette)
                            graph(record, report, palette: palette)
                            keyMistakes(report, palette: palette)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - 棋盘与控制

    private func board(_ record: GameRecord, ply: Int, side: CGFloat) -> some View {
        if let demo {
            return StaticBoardView(
                position: demo.board.position,
                lastMove: demo.lastStep.map { ($0.from, $0.to) },
                checkedKing: ReviewSupport.checkedKing(in: demo.board.position, san: demo.lastStep?.san),
                arrows: demo.arrow.map { [$0] } ?? [],
                accent: theme.palette.demo
            )
            .frame(width: side, height: side)
        }
        let position = Position(fen: record.fen(atPly: ply)) ?? Position.standard
        let move = ply > 0 ? record.moves[ply - 1] : nil
        var lastMove: (Square, Square)?
        if let move, !move.from.isEmpty { lastMove = (Square(move.from), Square(move.to)) }
        var arrows: [BoardArrow] = []
        if ply > 0, let better = ReviewSupport.feedback(record: record, index: ply - 1)?.better,
           ReviewSupport.feedback(record: record, index: ply - 1)?.verdict.isProblem == true {
            arrows = [BoardArrow(from: better.from, to: better.to, style: .better)]
        }
        return StaticBoardView(
            position: position,
            lastMove: lastMove,
            checkedKing: ReviewSupport.checkedKing(in: position, san: move?.san),
            arrows: arrows
        )
        .frame(width: side, height: side)
    }

    /// 演示中的控制条：⏮ ◀ ▶（主按钮）退出。
    private func demoControls(_ line: LineDemo, palette: BoardPalette) -> some View {
        HStack(spacing: 10) {
            navButton("backward.end.fill", label: "Start of line", disabled: !line.canBack, palette: palette) { demo?.start() }
            navButton("chevron.left", label: "Previous step", disabled: !line.canBack, palette: palette) { demo?.back() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button {
                demo?.next()
            } label: {
                Image(systemName: line.canNext ? "play.fill" : "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(.white)
                    .background(palette.demo)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(Text("Next"))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!line.canNext)
            .opacity(line.canNext ? 1 : 0.4)
            navButton("xmark", label: "Exit", disabled: false, palette: palette) { demo = nil }
        }
    }

    private func controls(_ record: GameRecord, palette: BoardPalette) -> some View {
        let last = record.moves.count
        if let demo { return AnyView(demoControls(demo, palette: palette)) }
        return AnyView(HStack(spacing: 10) {
            navButton("backward.end.fill", label: "First move", disabled: ply == 0, palette: palette) { ply = 0 }
            navButton("chevron.left", label: "Previous move", disabled: ply == 0, palette: palette) { ply -= 1 }
                .keyboardShortcut(.leftArrow, modifiers: [])
            navButton("chevron.right", label: "Next move", disabled: ply >= last, palette: palette) { ply += 1 }
                .keyboardShortcut(.rightArrow, modifiers: [])
            navButton("forward.end.fill", label: "Last move", disabled: ply >= last, palette: palette) { ply = last }
        })
    }

    private func navButton(
        _ symbol: String, label: LocalizedStringKey, disabled: Bool, palette: BoardPalette, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(palette.chipFill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(Text(label))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.primaryText)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    // MARK: - 着法列表

    private func chip(_ record: GameRecord, _ report: GameAnalysis.Report, index: Int, palette: BoardPalette) -> some View {
        let selected = ply == index + 1
        let verdict = report.verdicts[index]
        return Button {
            ply = index + 1
        } label: {
            HStack(spacing: 3) {
                Text(verbatim: ReviewSupport.san(of: record.moves[index]))
                    .font(.subheadline.weight(selected ? .bold : .regular))
                    .lineLimit(1)
                if let verdict {
                    Image(systemName: verdict.symbol)
                        .font(.caption2)
                        .foregroundStyle(palette.verdict(verdict))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? palette.chartLine.opacity(0.25) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.primaryText)
    }

    private func numberLabel(_ number: Int, palette: BoardPalette) -> some View {
        Text(verbatim: "\(number).")
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.secondaryText)
    }

    /// 窄屏：一条横向滚动的着法条，选中的步自动滚到中间。
    private func moveStrip(_ record: GameRecord, _ report: GameAnalysis.Report, palette: BoardPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(0..<(record.moves.count + 1) / 2, id: \.self) { row in
                        HStack(spacing: 0) {
                            numberLabel(row + 1, palette: palette)
                            chip(record, report, index: row * 2, palette: palette).id(row * 2 + 1)
                            if row * 2 + 1 < record.moves.count {
                                chip(record, report, index: row * 2 + 1, palette: palette).id(row * 2 + 2)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 36)
            .onChange(of: ply) { _, new in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(ply, anchor: .center) }
        }
    }

    /// 宽屏：完整的竖排着法列表，占满左列剩下的高度，自己滚动，选中的步自动滚进视野。
    private func moveList(_ record: GameRecord, _ report: GameAnalysis.Report, palette: BoardPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<(record.moves.count + 1) / 2, id: \.self) { row in
                        HStack(spacing: 4) {
                            numberLabel(row + 1, palette: palette).frame(width: 34, alignment: .trailing)
                            chip(record, report, index: row * 2, palette: palette).frame(maxWidth: .infinity, alignment: .leading)
                            if row * 2 + 1 < record.moves.count {
                                chip(record, report, index: row * 2 + 1, palette: palette).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer(minLength: 0).frame(maxWidth: .infinity)
                            }
                        }
                        .id(row)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: ply) { _, new in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(max(0, new - 1) / 2, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(max(0, ply - 1) / 2, anchor: .center) }
        }
    }

    // MARK: - 内容卡片

    private func card<Content: View>(_ palette: BoardPalette, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func summary(_ record: GameRecord, _ report: GameAnalysis.Report, palette: BoardPalette) -> some View {
        let pending = analyzer.progress[record.id]
        card(palette) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: record.resultHeadline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                if report.isComplete, report.analyzedPlayerMoves > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Accuracy")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                        Text(verbatim: "\(Int((report.accuracy ?? 0).rounded()))%")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        ForEach([MoveVerdict.best, .good, .inaccuracy, .mistake, .blunder], id: \.self) { verdict in
                            HStack(spacing: 2) {
                                Image(systemName: verdict.symbol)
                                    .foregroundStyle(palette.verdict(verdict))
                                Text(verbatim: "\(report.count(verdict))")
                                    .foregroundStyle(palette.primaryText)
                            }
                            .font(.footnote.weight(.semibold).monospacedDigit())
                        }
                    }
                } else if let pending {
                    ProgressView(value: pending.fraction)
                    Text("Analyzing the game… \(pending.done)/\(pending.total)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                } else if analyzer.failed.contains(record.id) {
                    Text("Analysis unavailable right now.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private func detail(_ record: GameRecord, _ report: GameAnalysis.Report, ply: Int, palette: BoardPalette) -> some View {
        card(palette) {
            VStack(alignment: .leading, spacing: 4) {
                if let demo {
                    Label("Demo \(demo.index)/\(demo.count)", systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.demo)
                    DemoCaptionsView(demo: demo, palette: palette)
                        .font(.footnote)
                } else if ply == 0 {
                    Text("Starting position")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                } else {
                    let index = ply - 1
                    let label = ReviewSupport.moveLabel(index: index, san: ReviewSupport.san(of: record.moves[index]))
                    if GameAnalysis.isPlayerMove(index) {
                        playerMoveDetail(record, index: index, label: label, palette: palette)
                    } else {
                        Text("Computer’s move \(label)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryText)
                        if let before = report.winPercents[index], let after = report.winPercents[ply] {
                            Text(winText(before, after))
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
                if demo == nil, let text = ReviewSupport.evalText(record.evals[ply], ply: ply) {
                    Text("Evaluation: \(text)")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .frame(minHeight: 84, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func playerMoveDetail(_ record: GameRecord, index: Int, label: String, palette: BoardPalette) -> some View {
        if let feedback = ReviewSupport.feedback(record: record, index: index) {
            Label(feedback.headline, systemImage: feedback.verdict.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.verdict(feedback.verdict))
            if let line = feedback.winLine {
                Text(line).font(.footnote).foregroundStyle(palette.secondaryText)
            }
            if let text = feedback.detail {
                Text(text).font(.footnote).foregroundStyle(palette.primaryText)
            }
            let line = ReviewSupport.engineLine(record: record, index: index)
            if line.count > 1 || feedback.verdict.isProblem, !line.isEmpty {
                Text("Engine line: \(line.joined(separator: " → "))")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                if let lineDemo = ReviewSupport.engineDemo(record: record, index: index) {
                    Button {
                        demo = lineDemo
                    } label: {
                        Label("Show line", systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.demo.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.demo)
                }
            }
        } else {
            Text("Your move \(label)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.primaryText)
            if analyzer.isAnalyzing(record.id) {
                Label("Analyzing…", systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("Not analyzed yet.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private func winText(_ before: Double, _ after: Double) -> String {
        let a = "\(Int(before.rounded()))%"
        let b = "\(Int(after.rounded()))%"
        return String(localized: "Win chances: \(a) → \(b)", bundle: .localized)
    }

    private func graph(_ record: GameRecord, _ report: GameAnalysis.Report, palette: BoardPalette) -> some View {
        var marks: [Int: MoveVerdict] = [:]
        for (index, verdict) in report.verdicts.enumerated() {
            if let verdict, verdict.isProblem { marks[index + 1] = verdict }
        }
        return card(palette) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your win chances")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                WinChanceChart(values: report.winPercents, selected: ply, onSelect: { ply = $0 }, marks: marks)
                    .frame(height: 120)
            }
        }
    }

    @ViewBuilder
    private func keyMistakes(_ report: GameAnalysis.Report, palette: BoardPalette) -> some View {
        if !report.keyMistakes.isEmpty {
            card(palette) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key mistakes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    ForEach(report.keyMistakes.prefix(3), id: \.index) { moment in
                        Button {
                            ply = moment.index + 1
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: moment.verdict.symbol)
                                    .foregroundStyle(palette.verdict(moment.verdict))
                                Text(verbatim: keyLabel(moment))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                Text(verbatim: "−\(Int(moment.drop.rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(palette.verdict(moment.verdict))
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func keyLabel(_ moment: GameAnalysis.KeyMoment) -> String {
        guard let record = archive.record(recordID), record.moves.indices.contains(moment.index) else { return "" }
        return ReviewSupport.moveLabel(index: moment.index, san: ReviewSupport.san(of: record.moves[moment.index]))
            + " · " + moment.verdict.title
    }
}
