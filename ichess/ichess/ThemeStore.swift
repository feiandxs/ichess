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
            isDark = true
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

    var targetFill: Color {
        isDark ? Color.black.opacity(0.28) : Color.black.opacity(0.22)
    }
}
