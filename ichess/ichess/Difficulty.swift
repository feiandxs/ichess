import Foundation

nonisolated enum Difficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case novice, beginner, practiced, advanced, expert, master

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novice: String(localized: "Newcomer", bundle: .localized)
        case .beginner: String(localized: "Beginner", bundle: .localized)
        case .practiced: String(localized: "Intermediate", bundle: .localized)
        case .advanced: String(localized: "Advanced", bundle: .localized)
        case .expert: String(localized: "Expert", bundle: .localized)
        case .master: String(localized: "Master Challenge", bundle: .localized)
        }
    }

    var detail: String {
        switch self {
        case .novice: String(localized: "Learn the rules at a relaxed pace", bundle: .localized)
        case .beginner: String(localized: "Practice captures and protecting pieces", bundle: .localized)
        case .practiced: String(localized: "Spot tactics and anticipate replies", bundle: .localized)
        case .advanced: String(localized: "A stronger challenge for regular players", bundle: .localized)
        case .expert: String(localized: "For experienced players", bundle: .localized)
        case .master: String(localized: "Take on a powerful opponent", bundle: .localized)
        }
    }

    var engineElo: Int? {
        switch self {
        case .novice, .beginner: nil
        case .practiced: 1400
        case .advanced: 1800
        case .expert: 2200
        case .master: 2600
        }
    }
}
