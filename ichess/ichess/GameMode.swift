import Foundation

/// 练习：可悔棋、提示、安全标记，不计分。对战：没有任何辅助，计入积分与连胜。
nonisolated enum GameMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case practice, battle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: String(localized: "Practice", bundle: .localized)
        case .battle: String(localized: "Battle", bundle: .localized)
        }
    }

    var allowsAids: Bool { self == .practice }
    var countsForRating: Bool { self == .battle }
}
