//
//  LanguageStore.swift
//  ichess
//

import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// 语言名用各自的语言显示，切错了也能认出来。
    var displayName: String {
        switch self {
        case .system: String(localized: "Follow System", bundle: .localized)
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    /// 实际使用的 lproj 名称。
    var resolvedCode: String {
        self == .system ? (Bundle.main.preferredLocalizations.first ?? "en") : rawValue
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            Bundle.localized = Self.bundle(for: language)
        }
    }

    /// 给 SwiftUI 的 Text / Label 等按 key 取文案用。
    var locale: Locale { Locale(identifier: language.resolvedCode) }

    private static let key = "nookchess.language"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:))
        language = saved ?? .system
        Bundle.localized = Self.bundle(for: language)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

extension Bundle {
    /// 代码里 String(localized:) 统一从这里取，跟随应用内语言设置。
    nonisolated(unsafe) static var localized: Bundle = .main
}
