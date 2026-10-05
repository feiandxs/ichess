//
//  ThemeStore.swift
//  ichess
//

import Combine
import SwiftUI

@MainActor
final class ThemeStore: ObservableObject {
    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: Self.key) }
    }

    var palette: BoardPalette { BoardPalette(isDark: isDark) }

    private static let key = "boardIsDark"

    init() {
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            isDark = false
        } else {
            isDark = UserDefaults.standard.bool(forKey: Self.key)
        }
    }

    func toggle() {
        isDark.toggle()
    }
}

struct BoardPalette {
    let isDark: Bool

    var canvas: Color {
        isDark
            ? Color(red: 20 / 255, green: 31 / 255, blue: 37 / 255)
            : Color(red: 236 / 255, green: 241 / 255, blue: 244 / 255)
    }

    var lightSquare: Color {
        isDark
            ? Color(red: 35 / 255, green: 52 / 255, blue: 59 / 255)
            : Color(red: 232 / 255, green: 238 / 255, blue: 242 / 255)
    }

    var boardBorder: Color {
        darkSquare
    }

    var darkSquare: Color {
        isDark
            ? Color(red: 22 / 255, green: 35 / 255, blue: 43 / 255)
            : Color(red: 176 / 255, green: 196 / 255, blue: 206 / 255)
    }

    var lastMove: Color {
        Color(red: 88 / 255, green: 204 / 255, blue: 2 / 255).opacity(isDark ? 0.28 : 0.38)
    }

    var selected: Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    var check: Color { Color.red.opacity(isDark ? 0.32 : 0.28) }

    var hint: Color {
        Color(red: 1, green: 0.78, blue: 0.15).opacity(isDark ? 0.42 : 0.50)
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.92) : Color(red: 22 / 255, green: 32 / 255, blue: 38 / 255)
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.40)
    }

    var chipFill: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var chipText: Color { primaryText }

    var cardFill: Color {
        isDark
            ? Color(red: 28 / 255, green: 42 / 255, blue: 48 / 255)
            : Color.white
    }

    var danger: Color {
        isDark ? Color(red: 1, green: 0.42, blue: 0.38) : Color(red: 0.86, green: 0.20, blue: 0.16)
    }

    var targetFill: Color {
        isDark ? Color.black.opacity(0.28) : Color.black.opacity(0.22)
    }

    /// 试走沙盒的强调色：边框、染色、标签。
    var sandbox: Color {
        isDark ? Color(red: 0.68, green: 0.58, blue: 1.0) : Color(red: 0.45, green: 0.30, blue: 0.85)
    }

    /// 棋盘箭头：更好的走法（蓝）、提示（琥珀）、对方的应对（红）。
    func arrow(_ style: BoardArrow.Style) -> Color {
        switch style {
        case .better:
            isDark ? Color(red: 0.36, green: 0.68, blue: 1.0) : Color(red: 0.12, green: 0.50, blue: 0.92)
        case .hint:
            isDark ? Color(red: 1.0, green: 0.72, blue: 0.20) : Color(red: 0.95, green: 0.58, blue: 0.05)
        case .reply:
            danger
        }
    }

    /// 走后点评各等级的颜色。
    func verdict(_ verdict: MoveVerdict) -> Color {
        switch verdict {
        case .best, .good:
            isDark ? Color(red: 0.45, green: 0.85, blue: 0.40) : Color(red: 0.16, green: 0.58, blue: 0.20)
        case .inaccuracy:
            isDark ? Color(red: 1.0, green: 0.80, blue: 0.30) : Color(red: 0.72, green: 0.48, blue: 0.0)
        case .mistake:
            isDark ? Color(red: 1.0, green: 0.62, blue: 0.28) : Color(red: 0.86, green: 0.40, blue: 0.04)
        case .blunder:
            danger
        }
    }

    /// 胜率条：玩家（白）一侧与对手（黑）一侧。
    var winBarWhite: Color {
        isDark ? Color(red: 0.93, green: 0.95, blue: 0.96) : Color.white
    }

    var winBarBlack: Color {
        isDark ? Color(red: 0.06, green: 0.09, blue: 0.11) : Color(red: 0.22, green: 0.27, blue: 0.31)
    }

    /// 胜率曲线的线条与填充。
    var chartLine: Color { arrow(.better) }

    /// 积极 / 消极的变化（胜率上升、下降）。
    var gain: Color { verdict(.best) }
    var loss: Color { verdict(.mistake) }
}
