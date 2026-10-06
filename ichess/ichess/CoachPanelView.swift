//
//  CoachPanelView.swift
//  ichess
//
//  练习模式下棋盘下方的教练区：试走开关与控制、走后点评、分级提示、对方的威胁、重点提醒、安全提示。
//  各区域高度固定（控制行 / 说明区 / 重点提醒 / 底部行），内容变化时棋盘不会跳动。
//

import ChessKit
import SwiftUI

struct CoachPanelView: View {
    @EnvironmentObject private var game: ChessGameStore
    @EnvironmentObject private var theme: ThemeStore
    /// 说明区固定留 5 行，随动态字体缩放。
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 16.5
    @ScaledMetric(relativeTo: .footnote) private var footerHeight: CGFloat = 32
    /// 重点提醒固定留 2 行。
    @ScaledMetric(relativeTo: .footnote) private var keyPointHeight: CGFloat = 33
    @State private var showInfo = false

    /// 候选列表的高度 = 说明区 + （开着重点提醒时）重点提醒区 + 中间的间距。
    private var candidateZoneHeight: CGFloat {
        lineHeight * 5 + (game.showsKeyPoints ? 8 + keyPointHeight : 0)
    }

    var body: some View {
        let palette = theme.palette
        VStack(alignment: .leading, spacing: 8) {
            if let demo = game.demo {
                demoControlRow(demo, palette: palette)
                // 演示占住说明区 + 重点提醒的位置，总高度不变，棋盘不会跳。
                demoMessage(demo, palette: palette)
                    .frame(maxWidth: .infinity, minHeight: candidateZoneHeight, maxHeight: candidateZoneHeight, alignment: .topLeading)
            } else {
                controlRow(palette: palette)
                if game.candidatesVisible {
                    // 候选列表占住说明区 + 重点提醒的位置，总高度不变，棋盘不会跳。
                    candidatePanel(palette: palette)
                        .frame(maxWidth: .infinity, minHeight: candidateZoneHeight, maxHeight: candidateZoneHeight, alignment: .topLeading)
                } else {
                    message(palette: palette)
                        .frame(maxWidth: .infinity, minHeight: lineHeight * 5, maxHeight: lineHeight * 5, alignment: .topLeading)
                    keyPointRow(palette: palette)
                }
            }
            footer(palette: palette)
                .frame(maxWidth: .infinity, minHeight: footerHeight, maxHeight: footerHeight, alignment: .leading)
            if game.showsWinChances {
                // 趋势图固定高度，开关之外内容变化不会让棋盘跳动。
                Divider().overlay(palette.secondaryText.opacity(0.2))
                WinTrendRow()
            }
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(game.isDemoing ? palette.demo.opacity(0.12) : (game.isTrying ? palette.sandbox.opacity(0.12) : palette.chipFill))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    (game.isDemoing ? palette.demo : palette.sandbox).opacity(game.isTrying || game.isDemoing ? 0.9 : 0),
                    lineWidth: 1.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: game.isTrying)
        .animation(.easeOut(duration: 0.15), value: game.isDemoing)
        .sheet(isPresented: $showInfo) {
            VerdictInfoView()
        }
    }

    // MARK: - 控制行

    private func controlRow(palette: BoardPalette) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { game.isTrying }, set: { game.setTrying($0) })) {
                Label("Try moves", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(game.isTrying ? palette.sandbox : palette.primaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .toggleStyle(.switch)
            .tint(palette.sandbox)
            .fixedSize()
            .disabled(!game.isTrying && !game.canTry)

            Spacer(minLength: 4)

            ViewThatFits(in: .horizontal) {
                trailingControls(threat: .full, compare: .full, iconOnly: false, palette: palette)
                trailingControls(threat: .short, compare: .short, iconOnly: false, palette: palette)
                trailingControls(threat: .short, compare: .icon, iconOnly: false, palette: palette)
                trailingControls(threat: .icon, compare: .icon, iconOnly: false, palette: palette)
                trailingControls(threat: .icon, compare: .icon, iconOnly: true, palette: palette)
            }
        }
        .frame(minHeight: footerHeight)
    }

    /// 「对方想干什么」+「候选走法」+（试走时的 退一步 / 重新试，平时的评级说明）。窄屏逐级缩成图标。
    private func trailingControls(threat: ThreatLabel, compare: ThreatLabel, iconOnly: Bool, palette: BoardPalette) -> some View {
        HStack(spacing: 6) {
            threatButton(label: threat, palette: palette)
            compareButton(label: compare, palette: palette)
            if game.isTrying {
                sandboxButtons(iconOnly: iconOnly, palette: palette)
            } else {
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityLabel(Text("How moves are rated"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private enum ThreatLabel { case full, short, icon }

    private func threatButton(label: ThreatLabel, palette: BoardPalette) -> some View {
        let active = game.threat != nil || game.isThreatThinking
        return Button {
            game.showThreat()
        } label: {
            Group {
                switch label {
                case .full:
                    Label("What’s my opponent threatening?", systemImage: "eye")
                        .labelStyle(.titleAndIcon)
                case .short:
                    Label("Their threat", systemImage: "eye")
                        .labelStyle(.titleAndIcon)
                case .icon:
                    Image(systemName: "eye").accessibilityLabel(Text("What’s my opponent threatening?"))
                }
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(active ? palette.danger.opacity(0.18) : palette.chipFill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? palette.danger : palette.chipText)
        .disabled(!game.canShowThreat && !active)
        .opacity(game.canShowThreat || active ? 1 : 0.4)
    }

    private func compareButton(label: ThreatLabel, palette: BoardPalette) -> some View {
        let active = game.candidatesVisible
        let tint = palette.arrow(.hint)
        return Button {
            game.toggleCandidates()
        } label: {
            Group {
                switch label {
                case .full:
                    Label("Compare moves", systemImage: "list.number")
                        .labelStyle(.titleAndIcon)
                case .short:
                    Label("Compare", systemImage: "list.number")
                        .labelStyle(.titleAndIcon)
                case .icon:
                    Image(systemName: "list.number").accessibilityLabel(Text("Compare moves"))
                }
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(active ? tint.opacity(0.22) : palette.chipFill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? palette.primaryText : palette.chipText)
        .disabled(!game.canCompare && !active)
        .opacity(game.canCompare || active ? 1 : 0.4)
    }

    private func sandboxButtons(iconOnly: Bool, palette: BoardPalette) -> some View {
        HStack(spacing: 6) {
            smallButton("Back", systemImage: "arrow.uturn.backward", iconOnly: iconOnly, palette: palette) {
                game.sandboxBack()
            }
            .disabled(!game.canSandboxBack)
            smallButton("Reset", systemImage: "arrow.counterclockwise", iconOnly: iconOnly, palette: palette) {
                game.sandboxReset()
            }
            .disabled(!game.canSandboxBack)
        }
    }

    private func smallButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        iconOnly: Bool,
        palette: BoardPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    Image(systemName: systemImage).accessibilityLabel(Text(title))
                } else {
                    Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
                }
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(palette.chipFill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.chipText)
    }

    // MARK: - 说明区

    @ViewBuilder
    private func message(palette: BoardPalette) -> some View {
        if game.isTrying {
            sandboxMessage(palette: palette)
        } else {
            realMessage(palette: palette)
        }
    }

    @ViewBuilder
    private func sandboxMessage(palette: BoardPalette) -> some View {
        if game.isSandboxThinking || game.opponentMoveAnimating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Your opponent is replying…")
                    .foregroundStyle(palette.secondaryText)
            }
        } else if let error = game.sandboxError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger)
        } else if let message = threatMessage(palette: palette) {
            message
        } else if let error = game.hintError {
            Label(error, systemImage: "lightbulb.slash")
                .foregroundStyle(palette.danger)
        } else if game.isHintThinking {
            Label("Thinking", systemImage: "lightbulb")
                .foregroundStyle(palette.secondaryText)
        } else if game.hintLevel > 0 {
            hintMessage(palette: palette)
        } else if let note = game.sandbox?.lastNote {
            VStack(alignment: .leading, spacing: 3) {
                // 标题和补充说明接在一起，窄屏自动折行。
                Text(Self.joined(headline: note.headline, detail: note.detail, palette: palette))
                    .lineLimit(3)
                if let line = note.evalLine {
                    Text(line)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text("Try a move to see how your opponent could answer. Nothing here changes your real game.")
                .foregroundStyle(palette.secondaryText)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func realMessage(palette: BoardPalette) -> some View {
        if let error = game.hintError {
            Label(error, systemImage: "lightbulb.slash")
                .foregroundStyle(palette.danger)
        } else if let message = threatMessage(palette: palette) {
            message
        } else if game.isHintThinking {
            Label("Thinking", systemImage: "lightbulb")
                .foregroundStyle(palette.secondaryText)
        } else if game.hintLevel > 0 {
            hintMessage(palette: palette)
        } else if game.showsFeedback, let feedback = game.feedback {
            feedbackMessage(feedback, palette: palette)
        } else if game.showsFeedback, game.isFeedbackPending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reviewing your move…")
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    /// 「对方想干什么」的搜索中 / 结果 / 出错；都没有返回 nil。
    private func threatMessage(palette: BoardPalette) -> AnyView? {
        if game.isThreatThinking {
            return AnyView(HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking what your opponent wants…")
                    .foregroundStyle(palette.secondaryText)
            })
        }
        if let threat = game.threat {
            return AnyView(VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Label("Your opponent’s threat", systemImage: "eye")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.danger)
                    Spacer(minLength: 0)
                    if game.canDemoThreat {
                        demoChip(palette: palette) { game.startThreatDemo() }
                    }
                }
                Text(threat.text)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.9)
            })
        }
        if let error = game.threatError {
            return AnyView(Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger))
        }
        return nil
    }

    private static func joined(headline: String, detail: String?, palette: BoardPalette) -> AttributedString {
        var head = AttributedString(headline)
        head.font = .footnote.weight(.semibold)
        head.foregroundColor = palette.primaryText
        guard let detail else { return head }
        var tail = AttributedString(" " + detail)
        tail.foregroundColor = palette.secondaryText
        return head + tail
    }

    private func hintMessage(palette: BoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let explanation = game.hintExplanation {
                switch game.hintLevel {
                case 1:
                    Label("What to think about", systemImage: "lightbulb.fill")
                        .fontWeight(.semibold)
                    Text(explanation.ideaText(keyPointShown: game.keyPointVisible && game.keyPoint != nil))
                        .lineLimit(4)
                        .minimumScaleFactor(0.9)
                case 2:
                    Label("Try moving the marked piece", systemImage: "lightbulb.fill")
                        .fontWeight(.semibold)
                    Text(explanation.pieceText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                default:
                    if let san = game.hintSAN {
                        HStack(spacing: 6) {
                            Label(String(localized: "Suggested move: \(san)", bundle: .localized), systemImage: "lightbulb.fill")
                                .fontWeight(.semibold)
                            Spacer(minLength: 0)
                            if game.canDemoHint {
                                demoChip(palette: palette) { game.startHintDemo() }
                            }
                        }
                    }
                    Text(explanation.answerText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    if let line = answerFooter() {
                        Text(line)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .foregroundStyle(palette.primaryText)
    }

    /// 「胜率 · 只有这一步」：走完这步的胜率；候选算好了再补上和其他走法的比较。
    private func answerFooter() -> String? {
        var parts: [String] = []
        // 候选算好后用它的数字，和列表一致。
        let matched = game.hint.flatMap { hint in
            game.candidates?.candidates.first { $0.from == hint.0 && $0.to == hint.1 }?.winPercent
        }
        if let win = matched ?? game.hintWin {
            let pct = "\(Int(win.rounded()))%"
            parts.append(String(localized: "Win chances after this move: \(pct)", bundle: .localized))
        }
        if let set = game.candidates {
            switch set.verdict {
            case .onlyMove: parts.append(String(localized: "Only move", bundle: .localized))
            case .severalGood: parts.append(String(localized: "Several good moves", bundle: .localized))
            case .bestAhead: break
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - 走法演示

    /// 「演示」小按钮：高度和一行字一样，不撑高说明区。
    private func demoChip(
        _ title: LocalizedStringKey = "Show line", systemImage: String = "play.fill",
        palette: BoardPalette, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: lineHeight)
                .background(palette.demo.opacity(0.18))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.demo)
    }

    private func demoControlRow(_ demo: LineDemo, palette: BoardPalette) -> some View {
        HStack(spacing: 8) {
            Label("Demo \(demo.index)/\(demo.count)", systemImage: "play.rectangle.fill")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.demo)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Button {
                game.exitDemo()
            } label: {
                Label("Exit", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.chipFill)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.chipText)
            .keyboardShortcut(.cancelAction)
        }
        .frame(minHeight: footerHeight)
    }

    /// 当前这步的说明（醒目）+ 上一步（变淡，放得下才显示）；走到头再加一句总结。
    private func demoMessage(_ demo: LineDemo, palette: BoardPalette) -> some View {
        ViewThatFits(in: .vertical) {
            DemoCaptionsView(demo: demo, showsPrevious: true, palette: palette)
            DemoCaptionsView(demo: demo, showsPrevious: false, palette: palette)
        }
    }

    /// ⏮ ◀ ▶：▶ 是主按钮，占剩下的宽度。
    private func demoFooter(_ demo: LineDemo, palette: BoardPalette) -> some View {
        let nextTitle: LocalizedStringKey = demo.isAtEnd ? "End of line" : "Next"
        return HStack(spacing: 6) {
            demoNavButton("backward.end.fill", label: "Start of line", disabled: !demo.canBack, palette: palette) {
                game.demoStart()
            }
            demoNavButton("chevron.left", label: "Previous step", disabled: !demo.canBack, palette: palette) {
                game.demoBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            Button {
                game.demoNext()
            } label: {
                Label(nextTitle, systemImage: demo.isAtEnd ? "checkmark" : "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(palette.demo)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!demo.canNext)
            .opacity(demo.canNext ? 1 : 0.55)
        }
    }

    private func demoNavButton(
        _ symbol: String, label: LocalizedStringKey, disabled: Bool, palette: BoardPalette, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .background(palette.chipFill)
                .clipShape(Capsule())
                .accessibilityLabel(Text(label))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.chipText)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    // MARK: - 候选走法

    private func candidatePanel(palette: BoardPalette) -> some View {
        let compact = !game.showsKeyPoints
        return VStack(alignment: .leading, spacing: 2) {
            if let set = game.candidates {
                HStack(spacing: 6) {
                    Image(systemName: "list.number")
                        .foregroundStyle(palette.arrow(.hint))
                    Text(verdictTitle(set.verdict))
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if game.canDemoCandidate {
                        demoChip(palette: palette) { game.startCandidateDemo() }
                    }
                }
                ForEach(Array(set.candidates.enumerated()), id: \.element.id) { index, move in
                    candidateRow(move, index: index, mover: set.mover, compact: compact, palette: palette)
                }
                candidateLine(set, palette: palette)
            } else if let error = game.hintError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.danger)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Comparing the best moves…")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private func verdictTitle(_ verdict: CandidateVerdict) -> String {
        switch verdict {
        case .onlyMove: String(localized: "This is the only good move.", bundle: .localized)
        case .severalGood: String(localized: "Several good moves. Pick the one you like.", bundle: .localized)
        case .bestAhead: String(localized: "One move is a bit better than the rest.", bundle: .localized)
        }
    }

    private func candidateRow(_ move: CandidateMove, index: Int, mover: Piece.Color, compact: Bool, palette: BoardPalette) -> some View {
        let selected = game.selectedCandidate == index
        let tint = palette.verdict(move.label.verdict)
        let reason = move.reason(mover: mover)
        return Button {
            game.selectCandidate(index)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(verbatim: move.san)
                        .fontWeight(.bold)
                        .foregroundStyle(palette.primaryText)
                    Text(verbatim: "\(Int(move.winPercent.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(palette.primaryText)
                    if move.winDrop >= 1 {
                        Text(verbatim: "(−\(Int(move.winDrop.rounded())))")
                            .monospacedDigit()
                            .foregroundStyle(palette.secondaryText)
                    }
                    Text(move.label.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    if compact {
                        Text(verbatim: reason)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                if !compact {
                    Text(verbatim: reason)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .background(selected ? palette.arrow(.hint).opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 选中那步的变例；没选时提示可以点。
    @ViewBuilder
    private func candidateLine(_ set: CandidateSet, palette: BoardPalette) -> some View {
        Group {
            if let index = game.selectedCandidate, set.candidates.indices.contains(index) {
                let line = set.candidates[index].line.prefix(6).map(\.san).joined(separator: " → ")
                Text(String(localized: "Line: \(line)", bundle: .localized))
            } else {
                Text("Tap a move to see it on the board.")
            }
        }
        .font(.caption2)
        .foregroundStyle(palette.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func feedbackMessage(_ feedback: MoveFeedback, palette: BoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // 标题写明评的是你的第几步、哪一步，不会和对手的应对混淆。
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(feedback.headline, systemImage: feedback.verdict.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.verdict(feedback.verdict))
                    .lineLimit(2)
                Spacer(minLength: 0)
                // 对手应对之后，回到走之前的局面看看更好的走法。
                if game.canLookBack {
                    demoChip("Look back", systemImage: "arrow.counterclockwise", palette: palette) { game.startFeedbackDemo() }
                }
            }
            if let line = feedback.winLine {
                Text(line)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if let detail = feedback.detail {
                Text(detail)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - 重点提醒

    /// 打开时固定占两行：没有内容 / 对手还在走子时留空，棋盘不会跳。
    @ViewBuilder
    private func keyPointRow(palette: BoardPalette) -> some View {
        if game.showsKeyPoints {
            HStack(alignment: .top, spacing: 6) {
                if game.keyPointVisible {
                    if let point = game.keyPoint, let text = game.keyPointText {
                        Image(systemName: "scope")
                            .foregroundStyle(keyPointTint(point, palette: palette))
                        Text(text)
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    } else {
                        Image(systemName: "scope")
                            .foregroundStyle(palette.secondaryText)
                        Text("Nothing urgent stands out right now.")
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: keyPointHeight, maxHeight: keyPointHeight, alignment: .topLeading)
        }
    }

    /// 威胁（红）、机会（绿）、局面方面的话（灰）。
    private func keyPointTint(_ point: CoachFinding, palette: BoardPalette) -> Color {
        if point.tier == .positional { return palette.secondaryText }
        return point.side == game.playerColor ? palette.gain : palette.danger
    }

    // MARK: - 暂停时的三个选择

    private func pauseButtons(palette: BoardPalette) -> some View {
        HStack(spacing: 6) {
            pauseButton("Take back", systemImage: "arrow.uturn.backward", prominent: true, palette: palette) {
                game.takeBack()
            }
            pauseButton("Show me", systemImage: "play.fill", prominent: false, palette: palette) {
                game.startFeedbackDemo()
            }
            .disabled(!game.canDemoFeedback)
            .opacity(game.canDemoFeedback ? 1 : 0.4)
            pauseButton("Continue", systemImage: "forward.end.fill", prominent: false, palette: palette) {
                game.continueAfterPause()
            }
        }
    }

    private func pauseButton(
        _ title: LocalizedStringKey, systemImage: String, prominent: Bool, palette: BoardPalette, action: @escaping () -> Void
    ) -> some View {
        let tint = palette.arrow(.better)
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(prominent ? Color.white : palette.chipText)
                .background(prominent ? tint : palette.chipFill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部行

    @ViewBuilder
    private func footer(palette: BoardPalette) -> some View {
        if let demo = game.demo {
            demoFooter(demo, palette: palette)
        } else if game.isTrying {
            Button {
                game.playSandboxMove()
            } label: {
                Label("Play this move", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(palette.sandbox)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!game.canPlaySandboxMove)
            .opacity(game.canPlaySandboxMove ? 1 : 0.4)
        } else if game.isPausedOnMistake {
            pauseButtons(palette: palette)
        } else if let note = game.safetyNote {
            Label(note, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.danger)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }
}
