//
//  GameOverOverlay.swift
//  ichess
//
//  对局结束的总结卡：任何结果（胜 / 负 / 和 / 认输）都有。卡片立刻出现，
//  赛后分析（准确率、各评级数量、关键时刻）算出来后再填进去。
//

import SwiftUI

struct GameOverOverlay: View {
    let outcome: GameOutcome
    let rating: Int
    let delta: Int
    let streakLine: String
    /// 练习局不计分，不显示积分。
    var countsForRating = true
    /// 这一局的存档；没走过棋的对局没有存档，也就没有统计和复盘。
    let archiveID: String?
    let palette: BoardPalette
    let onReview: () -> Void
    let onRematch: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var archive = GameArchive.shared
    @ObservedObject private var analyzer = PostGameAnalyzer.shared
    @State private var appear = false

    private var record: GameRecord? { archiveID.flatMap { archive.record($0) } }

    var body: some View {
        ZStack {
            palette.canvas.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            ViewThatFits(in: .vertical) {
                card
                ScrollView(showsIndicators: false) { card }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 340)
            .scaleEffect(appear ? 1 : 0.86)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.72)) {
                appear = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 12) {
            ZStack {
                if outcome.isWin {
                    sparkles
                }
                Image(systemName: outcome.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(outcome.accent)
                    .scaleEffect(appear ? 1 : 0.4)
                    .rotationEffect(.degrees(appear && outcome.isWin ? 0 : -12))
            }
            .frame(height: 64)

            Text(outcome.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.primaryText)

            Text(outcome.subtitle)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)

            if countsForRating {
                ratingBlock
            }

            if let record, !record.moves.isEmpty {
                statsBlock(record)
            }

            HStack(spacing: 10) {
                if record != nil {
                    Button(action: onReview) {
                        Text("Review")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(outcome.accent)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(outcome.accent, lineWidth: 1.5)
                            }
                    }
                }
                Button(action: onRematch) {
                    Text("Play Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(outcome.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Button("View Board", action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(22)
        .background(palette.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.12), radius: 24, y: 10)
    }

    private var ratingBlock: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("\(rating - delta)")
                    .foregroundStyle(palette.secondaryText)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.secondaryText)
                Text("\(rating)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                if delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(delta > 0 ? outcome.accent : Color.orange)
                }
            }
            Text(streakLine)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: - 赛后分析

    @ViewBuilder
    private func statsBlock(_ record: GameRecord) -> some View {
        let report = GameAnalysis.report(startEval: record.startEval, moves: record.moves)
        let pending = analyzer.progress[record.id]
        VStack(spacing: 10) {
            Divider().overlay(palette.secondaryText.opacity(0.25))
            if report.isComplete, report.analyzedPlayerMoves > 0 {
                accuracyRow(report)
                countsRow(report)
                keyMomentRow(record, report)
            } else if let pending {
                VStack(spacing: 6) {
                    ProgressView(value: pending.fraction)
                        .tint(outcome.accent)
                    Text("Analyzing the game… \(pending.done)/\(pending.total)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            } else if analyzer.failed.contains(record.id) {
                Text("Analysis unavailable right now.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .animation(.easeOut(duration: 0.25), value: report.isComplete)
    }

    private func accuracyRow(_ report: GameAnalysis.Report) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Accuracy")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Spacer()
            Text(verbatim: "\(Int((report.accuracy ?? 0).rounded()))%")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(palette.primaryText)
        }
    }

    private func countsRow(_ report: GameAnalysis.Report) -> some View {
        HStack(spacing: 4) {
            ForEach([MoveVerdict.best, .good, .inaccuracy, .mistake, .blunder], id: \.self) { verdict in
                VStack(spacing: 2) {
                    Image(systemName: verdict.symbol)
                        .font(.subheadline)
                        .foregroundStyle(palette.verdict(verdict))
                    Text(verbatim: "\(report.count(verdict))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                    Text(verdict.shortTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func keyMomentRow(_ record: GameRecord, _ report: GameAnalysis.Report) -> some View {
        if let moment = report.keyMoment, let feedback = ReviewSupport.feedback(record: record, index: moment.index) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Key moment")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Label(feedback.headline, systemImage: feedback.verdict.symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(palette.verdict(feedback.verdict))
                    .lineLimit(2)
                if let line = feedback.winLine {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                if let detail = feedback.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No big mistakes. Nicely played!")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var sparkles: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                sparkle(x: -38, y: -18, size: 12, phase: t * 2.1)
                sparkle(x: 36, y: -22, size: 10, phase: t * 1.7 + 1)
                sparkle(x: -8, y: -36, size: 8, phase: t * 2.4 + 0.4)
                sparkle(x: 18, y: 28, size: 9, phase: t * 1.9 + 0.8)
            }
        }
    }

    private func sparkle(x: CGFloat, y: CGFloat, size: CGFloat, phase: Double) -> some View {
        let pulse = 0.65 + 0.35 * sin(phase)
        return Image(systemName: "sparkle")
            .font(.system(size: size))
            .foregroundStyle(outcome.accent.opacity(0.9))
            .offset(x: x, y: y)
            .scaleEffect(pulse)
            .opacity(pulse)
    }
}

enum GameOutcome {
    case win
    case loss
    case resigned
    case draw(String)

    var isWin: Bool {
        if case .win = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .win: String(localized: "You Won", bundle: .localized)
        case .loss: String(localized: "Checkmate", bundle: .localized)
        case .resigned: String(localized: "You Resigned", bundle: .localized)
        case .draw: String(localized: "Draw", bundle: .localized)
        }
    }

    var subtitle: String {
        switch self {
        case .win: String(localized: "Well played!", bundle: .localized)
        case .loss, .resigned: String(localized: "Keep practicing. Try another game!", bundle: .localized)
        case .draw(let reason): reason
        }
    }

    var symbol: String {
        switch self {
        case .win: "trophy.fill"
        case .loss, .resigned: "flag.fill"
        case .draw: "equal.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .win: Color(red: 88 / 255, green: 204 / 255, blue: 2 / 255)
        case .loss, .resigned: Color(red: 1, green: 0.45, blue: 0.32)
        case .draw: Color(red: 90 / 255, green: 160 / 255, blue: 190 / 255)
        }
    }
}
