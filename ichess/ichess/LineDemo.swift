//
//  LineDemo.swift
//  ichess
//
//  分步演示一条变例：根局面 + 逐步的局面（点一下走一步），以及每一步的白话说明。
//  纯逻辑，不碰引擎和界面；说明从每步存下的数据 + MoveWhy 在走前局面上的分析生成。
//

import ChessKit
import Foundation

struct LineDemo {
    /// 说话的人（玩家）：这一方的走法说「你」，另一方说「对方」。
    let viewer: Piece.Color
    let steps: [CandidateStep]
    /// boards[0] 是起点，boards[i] 是走完第 i 步后的局面。
    let boards: [Board]
    /// 每步的走子信息（飞行动画用，id 固定）。
    let played: [PlayedMove]
    /// 起点局面的回合数和走子方，用来给每步编号。
    let rootNumber: Int
    let rootSide: Piece.Color
    /// 走完整条线后玩家的胜率（0...100），不知道为 nil。
    let winEnd: Double?
    /// 已经走了几步（0 = 起点）。
    private(set) var index = 0

    /// 在 root 上依次走 steps；走不通、或局面和存下的对不上就停在那里。没有一步可演示为 nil。
    init?(root: Board, steps: [CandidateStep], viewer: Piece.Color, winEnd: Double? = nil) {
        var boards = [root]
        var played: [PlayedMove] = []
        var kept: [CandidateStep] = []
        for step in steps {
            guard let applied = MoveExplainer.apply(uci: step.uci, on: boards[boards.count - 1]),
                  applied.board.position.fen == step.fen else { break }
            boards.append(applied.board)
            played.append(PlayedMove(from: applied.played))
            kept.append(step)
        }
        guard !kept.isEmpty else { return nil }
        self.viewer = viewer
        self.steps = kept
        self.boards = boards
        self.played = played
        self.winEnd = winEnd
        rootSide = root.position.sideToMove
        rootNumber = root.position.fen.split(separator: " ").last.flatMap { Int($0) } ?? 1
    }

    var count: Int { steps.count }
    var board: Board { boards[index] }
    var canNext: Bool { index < count }
    var canBack: Bool { index > 0 }
    var isAtEnd: Bool { index == count }
    /// 刚走的那步（起点为 nil）。
    var lastPlayed: PlayedMove? { index > 0 ? played[index - 1] : nil }
    var lastStep: CandidateStep? { index > 0 ? steps[index - 1] : nil }

    /// 刚走的那步画一支箭头。
    var arrow: BoardArrow? {
        lastStep.map { BoardArrow(from: $0.from, to: $0.to, style: .demo) }
    }

    @discardableResult
    mutating func next() -> Bool {
        guard canNext else { return false }
        index += 1
        return true
    }

    @discardableResult
    mutating func back() -> Bool {
        guard canBack else { return false }
        index -= 1
        return true
    }

    mutating func start() { index = 0 }

    /// 第 position 步（1...count）的编号：白方「12. 」，黑方「12… 」。
    func number(ofStep position: Int) -> Int {
        let k = position - 1
        return rootNumber + (rootSide == .white ? k / 2 : (k + 1) / 2)
    }
}

enum DemoCaption {
    private static func name(_ kind: Piece.Kind) -> String { kind.localizedName.lowercased() }

    // MARK: - 每一步

    /// 第 position 步（1...count）的说明，如「1. 你：马吃 e5 的兵（Nxe5），赢一个兵」。
    static func ply(_ demo: LineDemo, at position: Int) -> String {
        guard (1...demo.count).contains(position) else { return "" }
        let step = demo.steps[position - 1]
        let number = demo.number(ofStep: position)
        let prefix = step.color == .white ? "\(number). " : "\(number)… "
        let who = step.color == demo.viewer
            ? String(localized: "You", bundle: .localized)
            : String(localized: "Opponent", bundle: .localized)
        var what = action(step)
        let previous = position > 1 ? demo.steps[position - 2] : nil
        for clause in clauses(step, before: demo.boards[position - 1], previous: previous) {
            what = String(localized: "\(what), \(clause)", bundle: .localized)
        }
        return String(localized: "\(prefix)\(who): \(what)", bundle: .localized)
    }

    /// 走了什么：吃子、升变、易位、普通一步。
    static func action(_ step: CandidateStep) -> String {
        let piece = step.piece.localizedName
        let square = step.to.notation
        let san = step.san
        if san.hasPrefix("O-O") {
            return String(localized: "Castles (\(san))", bundle: .localized)
        }
        if let promoted = promotion(in: san) {
            return String(localized: "Pawn promotes to a \(name(promoted)) on \(square) (\(san))", bundle: .localized)
        }
        if let captured = step.captured {
            return String(localized: "\(piece) takes the \(name(captured)) on \(square) (\(san))", bundle: .localized)
        }
        return String(localized: "\(piece) to \(square) (\(san))", bundle: .localized)
    }

    private static func promotion(in san: String) -> Piece.Kind? {
        guard let equals = san.firstIndex(of: "="), let letter = san[san.index(after: equals)...].first else { return nil }
        switch letter {
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        default: return nil
        }
    }

    /// 这步做成的事：将军 / 杀棋，再加上最重要的一件（最多两条）。
    static func clauses(_ step: CandidateStep, before: Board, previous: CandidateStep? = nil) -> [String] {
        if step.san.hasSuffix("#") { return [String(localized: "checkmate!", bundle: .localized)] }
        var result: [String] = []
        if step.givesCheck { result.append(String(localized: "check", bundle: .localized)) }
        // 吃回刚被吃的那一格：说「吃回来」，不再说赢子；易位本身就说明了。
        if step.captured != nil, let previous, previous.captured != nil, previous.to == step.to {
            return result + [String(localized: "takes it back", bundle: .localized)]
        }
        if step.san.hasPrefix("O-O") { return result }
        for motif in MoveWhy.motifs(board: before, uci: step.uci) {
            if let text = clause(for: motif) {
                result.append(text)
                break
            }
        }
        return result
    }

    private static func clause(for motif: MoveMotif) -> String? {
        switch motif {
        case let .winsPiece(victim, _):
            return String(localized: "wins a \(name(victim.kind))", bundle: .localized)
        case .trade:
            return String(localized: "an even trade", bundle: .localized)
        case let .tactic(tactic):
            switch tactic.motif {
            case let .fork(_, targets) where targets.count >= 2:
                return String(localized: "attacks the \(name(targets[0].kind)) and the \(name(targets[1].kind)) at once", bundle: .localized)
            case let .pin(pinned, _, _):
                return String(localized: "pins the \(name(pinned.kind)) on \(pinned.square.notation)", bundle: .localized)
            case let .skewer(front, behind, _):
                return String(localized: "attacks the \(name(front.kind)) on \(front.square.notation), with the \(name(behind.kind)) behind it", bundle: .localized)
            default:
                return nil
            }
        case let .threatensToWin(victim):
            return String(localized: "threatens the \(name(victim.kind)) on \(victim.square.notation)", bundle: .localized)
        case .threatensMate:
            return String(localized: "threatens checkmate next move", bundle: .localized)
        case .stopsMate:
            return String(localized: "stops the checkmate threat", bundle: .localized)
        case .escapesCheck:
            return String(localized: "gets out of check", bundle: .localized)
        case let .escapes(kind):
            return String(localized: "moves the \(name(kind)) to safety", bundle: .localized)
        case let .savesPiece(target):
            return String(localized: "protects the \(name(target.kind)) on \(target.square.notation)", bundle: .localized)
        case .removesThreat:
            return String(localized: "deals with the threat", bundle: .localized)
        case let .develops(kind):
            return String(localized: "develops the \(name(kind))", bundle: .localized)
        case .takesCenter:
            return String(localized: "stakes a claim in the center", bundle: .localized)
        case .controlsCenter:
            return String(localized: "controls the center", bundle: .localized)
        case .checkmate, .check, .promotes, .castles, .solid:
            return nil
        }
    }

    // MARK: - 开头与总结

    static func intro(_ demo: LineDemo) -> String {
        let san = demo.steps[0].san
        return String(localized: "Showing \(san) and what could follow, one move at a time (\(demo.count) in all). Tap Next to play each move.", bundle: .localized)
    }

    /// 走完整条线后的小结：杀棋，或子力变化 + 胜率。
    static func summary(_ demo: LineDemo) -> String {
        if let last = demo.steps.last, last.san.hasSuffix("#") {
            return last.color == demo.viewer
                ? String(localized: "This line ends with you checkmating your opponent.", bundle: .localized)
                : String(localized: "This line ends with your opponent checkmating you.", bundle: .localized)
        }
        let material = materialText(demo)
        guard let win = demo.winEnd else {
            return String(localized: "End of the line: \(material)", bundle: .localized)
        }
        let pct = "\(Int(win.rounded()))%"
        return String(localized: "End of the line: \(material), win chances about \(pct)", bundle: .localized)
    }

    /// 玩家吃到的子减去被吃掉的子（同种互相抵消）：玩家多出的 / 对方多出的。
    static func materialBalance(_ demo: LineDemo) -> (mine: [Piece.Kind], theirs: [Piece.Kind]) {
        var mine = demo.steps.filter { $0.color == demo.viewer }.compactMap(\.captured)
        var theirs = demo.steps.filter { $0.color != demo.viewer }.compactMap(\.captured)
        for kind in mine {
            if let at = theirs.firstIndex(of: kind), let mineAt = mine.firstIndex(of: kind) {
                theirs.remove(at: at)
                mine.remove(at: mineAt)
            }
        }
        return (mine, theirs)
    }

    private static func materialText(_ demo: LineDemo) -> String {
        let (mine, theirs) = materialBalance(demo)
        if mine.isEmpty, theirs.isEmpty { return String(localized: "material is even", bundle: .localized) }
        let points = mine.reduce(0) { $0 + ThreatAnalyzer.value($1) } - theirs.reduce(0) { $0 + ThreatAnalyzer.value($1) }
        // 一方多一两个不同的子时直接说是什么，其余说分数。
        if theirs.isEmpty, let text = upText(mine, you: true) { return text }
        if mine.isEmpty, let text = upText(theirs, you: false) { return text }
        if points == 0 { return String(localized: "material is even", bundle: .localized) }
        return points > 0
            ? String(localized: "you are up \(points) points of material", bundle: .localized)
            : String(localized: "your opponent is up \(-points) points of material", bundle: .localized)
    }

    private static func upText(_ kinds: [Piece.Kind], you: Bool) -> String? {
        guard kinds.count <= 2, Set(kinds).count == kinds.count else { return nil }
        if kinds.count == 1 {
            let a = name(kinds[0])
            return you
                ? String(localized: "you are up a \(a)", bundle: .localized)
                : String(localized: "your opponent is up a \(a)", bundle: .localized)
        }
        let a = name(kinds[0]), b = name(kinds[1])
        return you
            ? String(localized: "you are up a \(a) and a \(b)", bundle: .localized)
            : String(localized: "your opponent is up a \(a) and a \(b)", bundle: .localized)
    }
}
