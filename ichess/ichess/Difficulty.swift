import Foundation

nonisolated enum Difficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case novice, beginner, practiced, advanced, expert, master

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novice: "新手"
        case .beginner: "入门"
        case .practiced: "熟练"
        case .advanced: "进阶"
        case .expert: "高手"
        case .master: "大师挑战"
        }
    }

    var detail: String {
        switch self {
        case .novice: "刚学会规则，轻松练习"
        case .beginner: "会基本吃子、保护棋子"
        case .practiced: "能发现常见战术，考虑对方反击"
        case .advanced: "经常下棋，想要更强的挑战"
        case .expert: "有较丰富的对局经验"
        case .master: "挑战高强度电脑对手"
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
