//
//  GameOverOverlay.swift
//  ichess
//

import SwiftUI

struct GameOverOverlay: View {
    let outcome: GameOutcome
    let rating: Int
    let delta: Int
    let streakLine: String
    let palette: BoardPalette
    let onRematch: () -> Void
    let onDismiss: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            palette.canvas.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) {
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

                Button(action: onRematch) {
                    Text("再来一盘")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(outcome.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 4)

                Button("看看棋盘", action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(palette.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.12), radius: 24, y: 10)
            .scaleEffect(appear ? 1 : 0.86)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.72)) {
                appear = true
            }
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
        case .win: "你赢了"
        case .loss: "将死了"
        case .resigned: "你认输了"
        case .draw: "和棋"
        }
    }

    var subtitle: String {
        switch self {
        case .win: "这局下得漂亮"
        case .loss, .resigned: "再试一盘就熟了"
        case .draw(let reason): reason
        }
    }

    var symbol: String {
        switch self {
        case .win: "trophy.fill"
        case .loss, .resigned: "flag.fill"
        case .draw: "handshake.fill"
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
