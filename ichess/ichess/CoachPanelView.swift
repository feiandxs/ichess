//
//  CoachPanelView.swift
//  ichess
//
//  练习模式下棋盘下方的教练区：试走开关与控制、走后点评、分级提示、安全提示。
//  三块区域高度固定（控制行 / 说明区 / 底部行），内容变化时棋盘不会跳动。
//

import SwiftUI

struct CoachPanelView: View {
    @EnvironmentObject private var game: ChessGameStore
    @EnvironmentObject private var theme: ThemeStore
    /// 说明区固定留 5 行，随动态字体缩放。
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 16.5
    @ScaledMetric(relativeTo: .footnote) private var footerHeight: CGFloat = 32
    @State private var showInfo = false

    var body: some View {
        let palette = theme.palette
        VStack(alignment: .leading, spacing: 8) {
            controlRow(palette: palette)
            message(palette: palette)
                .frame(maxWidth: .infinity, minHeight: lineHeight * 5, maxHeight: lineHeight * 5, alignment: .topLeading)
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
        .background(game.isTrying ? palette.sandbox.opacity(0.12) : palette.chipFill)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.sandbox.opacity(game.isTrying ? 0.9 : 0), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: game.isTrying)
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

            if game.isTrying {
                ViewThatFits(in: .horizontal) {
                    sandboxButtons(iconOnly: false, palette: palette)
                    sandboxButtons(iconOnly: true, palette: palette)
                }
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
        .frame(minHeight: footerHeight)
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
            switch game.hintLevel {
            case 1:
                Label("Try moving this piece", systemImage: "lightbulb.fill")
            case 2:
                Label("Try moving it to the marked square", systemImage: "lightbulb.fill")
            default:
                if let san = game.hintSAN {
                    Label(String(localized: "Suggested move: \(san)", bundle: .localized), systemImage: "lightbulb.fill")
                        .fontWeight(.semibold)
                }
                if game.hintLine.count > 1 {
                    Text(String(localized: "Likely continuation: \(game.hintLine.dropFirst().joined(separator: " → "))", bundle: .localized))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(palette.primaryText)
    }

    private func feedbackMessage(_ feedback: MoveFeedback, palette: BoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // 标题写明评的是你的第几步、哪一步，不会和对手的应对混淆。
            Label(feedback.headline, systemImage: feedback.verdict.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.verdict(feedback.verdict))
                .lineLimit(2)
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

    // MARK: - 底部行

    @ViewBuilder
    private func footer(palette: BoardPalette) -> some View {
        if game.isTrying {
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
