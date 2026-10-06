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

    /// 棋盘边缘的坐标标注（a–h、1–8）。
    @Published var showsCoordinates: Bool {
        didSet { UserDefaults.standard.set(showsCoordinates, forKey: Self.coordinatesKey) }
    }

    /// 坐标画在棋盘外的边槽里，还是棋盘内的角落。
    @Published var coordinatePlacement: CoordinatePlacement {
        didSet { UserDefaults.standard.set(coordinatePlacement.rawValue, forKey: Self.placementKey) }
    }

    /// 对手走子动画的速度；自己走的子始终保持利落。
    @Published var moveSpeed: MoveSpeed {
        didSet { UserDefaults.standard.set(moveSpeed.rawValue, forKey: Self.moveSpeedKey) }
    }

    /// 棋盘外边槽占整个棋盘区域边长的比例；不显示坐标或放在棋盘内时为 0。
    var gutterRatio: CGFloat {
        showsCoordinates && coordinatePlacement == .outside ? BoardGutter.ratio : 0
    }

    var palette: BoardPalette { BoardPalette(isDark: isDark) }

    private static let key = "boardIsDark"
    private static let coordinatesKey = "boardShowsCoordinates"
    private static let placementKey = "nookchess.coordinatePlacement"
    private static let moveSpeedKey = "nookchess.moveSpeed"

    init() {
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            isDark = false
        } else {
            isDark = UserDefaults.standard.bool(forKey: Self.key)
        }
        moveSpeed = UserDefaults.standard.string(forKey: Self.moveSpeedKey).flatMap(MoveSpeed.init(rawValue:)) ?? .normal
        showsCoordinates = UserDefaults.standard.object(forKey: Self.coordinatesKey) as? Bool ?? true
        coordinatePlacement = UserDefaults.standard.string(forKey: Self.placementKey).flatMap(CoordinatePlacement.init(rawValue:)) ?? .outside
    }

    func toggle() {
        isDark.toggle()
    }
}

enum CoordinatePlacement: String, CaseIterable, Identifiable {
    case outside, inside

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .outside: "Outside board"
        case .inside: "Inside board"
        }
    }
}

enum MoveSpeed: String, CaseIterable, Identifiable {
    case fast, normal, slow

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .slow: "Slow"
        }
    }

    /// 对手走一步的飞行时长（秒）。
    var opponentDuration: Double {
        switch self {
        case .fast: 0.34
        case .normal: 0.75
        case .slow: 1.2
        }
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

    /// 坐标标注：浅格上用深色、深格上用浅色，低调但看得清。
    func coordinate(onLight: Bool) -> Color {
        if isDark {
            return onLight ? Color(red: 142 / 255, green: 166 / 255, blue: 178 / 255) : Color(red: 120 / 255, green: 146 / 255, blue: 158 / 255)
        }
        return onLight ? Color(red: 112 / 255, green: 140 / 255, blue: 154 / 255) : Color(red: 244 / 255, green: 248 / 255, blue: 250 / 255)
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

    /// 走法演示的强调色：边框、染色、标签、箭头。
    var demo: Color {
        isDark ? Color(red: 0.30, green: 0.80, blue: 0.78) : Color(red: 0.03, green: 0.52, blue: 0.58)
    }

    /// 棋盘箭头：更好的走法（蓝）、提示（琥珀）、对方的应对 / 威胁（红）、对手上一步（绿）。
    func arrow(_ style: BoardArrow.Style) -> Color {
        switch style {
        case .better:
            isDark ? Color(red: 0.36, green: 0.68, blue: 1.0) : Color(red: 0.12, green: 0.50, blue: 0.92)
        case .hint:
            isDark ? Color(red: 1.0, green: 0.72, blue: 0.20) : Color(red: 0.95, green: 0.58, blue: 0.05)
        case .reply, .threat:
            danger
        case .demo:
            demo
        case .opponent:
            isDark ? Color(red: 0.50, green: 0.88, blue: 0.38) : Color(red: 0.20, green: 0.62, blue: 0.12)
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
