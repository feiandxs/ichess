import Foundation

nonisolated enum Difficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case novice, beginner, practiced, advanced, expert, master

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novice: String(localized: "Newcomer")
        case .beginner: String(localized: "Beginner")
        case .practiced: String(localized: "Intermediate")
        case .advanced: String(localized: "Advanced")
        case .expert: String(localized: "Expert")
        case .master: String(localized: "Master Challenge")
        }
    }

    var detail: String {
        switch self {
        case .novice: String(localized: "Learn the rules at a relaxed pace")
        case .beginner: String(localized: "Practice captures and protecting pieces")
        case .practiced: String(localized: "Spot tactics and anticipate replies")
        case .advanced: String(localized: "A stronger challenge for regular players")
        case .expert: String(localized: "For experienced players")
        case .master: String(localized: "Take on a powerful opponent")
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
