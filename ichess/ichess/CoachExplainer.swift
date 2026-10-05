//
//  CoachExplainer.swift
//  ichess
//
//  教练的解释引擎：把 TacticsDetector 的事实按重要性排序，再说成新手能看懂的短句（棋子名 + 格子）。
//  纯逻辑，不碰引擎和界面；分级提示、分步演示都可以复用 findings / text。
//

import ChessKit
import Foundation

/// 一条按重要性排好序的发现。
struct CoachFinding: Equatable {
    enum Tier: Int, Comparable {
        case positional, tactic, material, critical

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let tactic: Tactic
    /// 越大越重要：杀棋 > 要丢子 > 玩家的战术机会 > 开局 / 局面方面的话。
    let priority: Int

    var side: Piece.Color { tactic.side }
    var motif: CoachMotif { tactic.motif }

    var tier: Tier {
        switch priority {
        case 800...: .critical
        case 500..<800: .material
        case 300..<500: .tactic
        default: .positional
        }
    }

    /// 被攻击、会丢的那个子（丢子类发现才有）；安全标记已经说了同一件事时用来去重。
    var victim: CoachTarget? {
        switch motif {
        case let .hanging(victim, _), let .lesserAttacker(victim, _), let .outnumbered(victim, _): victim
        default: nil
        }
    }
}

enum CoachExplainer {
    /// 太深的杀棋新手看不出来，不提。
    static let maxMateDepth = 4

    // MARK: - 发现与排序

    /// - position: 局面；viewer：站在哪一方说话（玩家）。
    /// - analysis: 对这个局面的搜索（走子方视角）；只用来补充杀棋信息，可以没有。
    static func findings(position: Position, viewer: Piece.Color, analysis: EngineAnalysis? = nil) -> [CoachFinding] {
        let enemy = viewer.opposite
        let viewerToMove = position.sideToMove == viewer
        let board = Board(position: position)
        let inCheck = !TacticsDetector.checkers(of: viewer, in: position).isEmpty
        var tactics: [Tactic] = []

        if inCheck {
            tactics.append(Tactic(side: enemy, motif: .check(attackers: TacticsDetector.checkers(of: viewer, in: position))))
        }

        // 杀棋：一步杀用规则查（含对方空着一步的威胁），2 步以上用引擎评分。
        var matesInOne: Set<Piece.Color> = []
        for side in [viewer, enemy] {
            if let mover = TacticsDetector.board(for: side, from: board), TacticsDetector.hasMateInOne(mover) {
                matesInOne.insert(side)
                tactics.append(Tactic(side: side, motif: .mateInOne))
            }
        }
        if let score = analysis?.score, case let .mate(n) = score, n != 0 {
            let doer = n > 0 ? position.sideToMove : position.sideToMove.opposite
            let moves = abs(n)
            if moves == 1 {
                if !matesInOne.contains(doer) { tactics.append(Tactic(side: doer, motif: .mateInOne)) }
            } else if moves <= maxMateDepth {
                tactics.append(Tactic(side: doer, motif: .mate(in: moves)))
            }
        }

        // 对方对我方的威胁一直算；我方的机会只在轮到我且没被将军时才有意义。
        tactics += TacticsDetector.staticTactics(by: enemy, in: position)
        let canAct = viewerToMove && !inCheck
        if canAct {
            tactics += TacticsDetector.staticTactics(by: viewer, in: position)
            if let chance = TacticsDetector.forkChance(by: viewer, board: board) { tactics.append(chance) }
        }
        if !inCheck, let theirs = TacticsDetector.board(for: enemy, from: board),
           let chance = TacticsDetector.forkChance(by: enemy, board: theirs) {
            tactics.append(chance)
        }

        tactics += TacticsDetector.openingRemarks(for: viewer, in: position)
        return tactics.enumerated()
            .map { (index: $0.offset, finding: CoachFinding(tactic: $0.element, priority: priority(of: $0.element, viewer: viewer))) }
            .sorted { $0.finding.priority != $1.finding.priority ? $0.finding.priority > $1.finding.priority : $0.index < $1.index }
            .map(\.finding)
    }

    /// 同一个 tier 里再按这个排；数值只在内部比较用。
    static func priority(of tactic: Tactic, viewer: Piece.Color) -> Int {
        let against = tactic.side != viewer
        func value(_ target: CoachTarget) -> Int { ThreatAnalyzer.value(target.kind) }
        switch tactic.motif {
        case .mateInOne:
            return against ? 1000 : 900
        case let .mate(n):
            return (against ? 990 : 890) - n
        case .check:
            return 850
        case let .hanging(victim, _):
            return (against ? 600 : 400) + value(victim)
        case let .lesserAttacker(victim, _):
            return (against ? 580 : 390) + value(victim)
        case let .outnumbered(victim, _):
            return (against ? 560 : 380) + value(victim)
        case let .fork(_, targets):
            let second = targets.count > 1 ? value(targets[1]) : 0
            let hitsKing = targets.contains { $0.kind == .king }
            return against ? (hitsKing ? 680 : 620) + second : (hitsKing ? 460 : 440) + second
        case .forkChance:
            return against ? 350 : 380
        case let .pin(_, behind, _):
            return (against ? 340 : 360) - (behind.kind == .king ? 0 : 10)
        case .skewer:
            return against ? 560 : 410
        case let .opening(remark):
            switch remark {
            case .earlyQueen: return 130
            case .castle: return 125
            case .develop: return 120
            case .center: return 110
            }
        }
    }

    /// 最该提醒的一条；skipping 返回 true 的发现不考虑（比如安全标记已经说过的）。
    static func keyPoint(
        position: Position,
        viewer: Piece.Color,
        analysis: EngineAnalysis? = nil,
        skipping: (CoachFinding) -> Bool = { _ in false }
    ) -> CoachFinding? {
        findings(position: position, viewer: viewer, analysis: analysis).first { !skipping($0) }
    }

    // MARK: - 说成人话

    private static func name(_ kind: Piece.Kind) -> String { kind.localizedName.lowercased() }

    /// 一句话。viewer 是玩家：side == viewer 说“你的……”，否则说“对方的……”。
    /// 只点出目标 / 威胁，不报出该走哪一步。
    static func text(for finding: CoachFinding, viewer: Piece.Color) -> String {
        let mine = finding.side == viewer
        switch finding.motif {
        case .mateInOne:
            return mine
                ? String(localized: "You can checkmate in one move. Look for it!", bundle: .localized)
                : String(localized: "Your opponent threatens to checkmate you next move!", bundle: .localized)
        case let .mate(n):
            return mine
                ? String(localized: "You have a forced checkmate within \(n) moves. Look for it!", bundle: .localized)
                : String(localized: "Your opponent could checkmate you within \(n) moves.", bundle: .localized)
        case let .check(attackers):
            guard let first = attackers.first else { return "" }
            return String(localized: "Your opponent’s \(name(first.kind)) on \(first.square.notation) is giving check. Capture it, block it, or move your king.", bundle: .localized)
        case let .hanging(victim, attacker):
            return mine
                ? String(localized: "Your opponent’s \(name(victim.kind)) on \(victim.square.notation) has no defender. Can you capture it?", bundle: .localized)
                : String(localized: "Your opponent’s \(name(attacker.kind)) on \(attacker.square.notation) attacks your undefended \(name(victim.kind)) on \(victim.square.notation).", bundle: .localized)
        case let .lesserAttacker(victim, attacker):
            return mine
                ? String(localized: "Your \(name(attacker.kind)) on \(attacker.square.notation) attacks your opponent’s more valuable \(name(victim.kind)) on \(victim.square.notation). Can you win it?", bundle: .localized)
                : String(localized: "Your opponent’s \(name(attacker.kind)) on \(attacker.square.notation) attacks your \(name(victim.kind)) on \(victim.square.notation), which is worth more.", bundle: .localized)
        case let .outnumbered(victim, _):
            return mine
                ? String(localized: "Your opponent’s \(name(victim.kind)) on \(victim.square.notation) is attacked more times than it is defended. Can you win it?", bundle: .localized)
                : String(localized: "Your \(name(victim.kind)) on \(victim.square.notation) is attacked more times than it is defended.", bundle: .localized)
        case let .fork(attacker, targets):
            guard targets.count >= 2 else { return "" }
            let a = targets[0], b = targets[1]
            return mine
                ? String(localized: "Your \(name(attacker.kind)) on \(attacker.square.notation) attacks both your opponent’s \(name(a.kind)) on \(a.square.notation) and \(name(b.kind)) on \(b.square.notation).", bundle: .localized)
                : String(localized: "Your opponent’s \(name(attacker.kind)) on \(attacker.square.notation) attacks both your \(name(a.kind)) on \(a.square.notation) and \(name(b.kind)) on \(b.square.notation).", bundle: .localized)
        case let .forkChance(kind, targets):
            guard targets.count >= 2 else { return "" }
            return mine
                ? String(localized: "Look for a move where your \(name(kind)) attacks your opponent’s \(name(targets[0])) and \(name(targets[1])) at once.", bundle: .localized)
                : String(localized: "Watch out: your opponent’s \(name(kind)) could attack your \(name(targets[0])) and \(name(targets[1])) at once.", bundle: .localized)
        case let .pin(pinned, behind, by):
            if behind.kind == .king {
                return mine
                    ? String(localized: "Your opponent’s \(name(pinned.kind)) on \(pinned.square.notation) is pinned to their king by your \(name(by.kind)) on \(by.square.notation).", bundle: .localized)
                    : String(localized: "Your \(name(pinned.kind)) on \(pinned.square.notation) is pinned to your king by your opponent’s \(name(by.kind)) on \(by.square.notation).", bundle: .localized)
            }
            return mine
                ? String(localized: "Your \(name(by.kind)) on \(by.square.notation) pins your opponent’s \(name(pinned.kind)) on \(pinned.square.notation) to their \(name(behind.kind)) on \(behind.square.notation).", bundle: .localized)
                : String(localized: "Your \(name(pinned.kind)) on \(pinned.square.notation) is pinned by your opponent’s \(name(by.kind)) on \(by.square.notation). If it moves, your \(name(behind.kind)) on \(behind.square.notation) is attacked.", bundle: .localized)
        case let .skewer(front, behind, by):
            return mine
                ? String(localized: "Your \(name(by.kind)) on \(by.square.notation) attacks your opponent’s \(name(front.kind)) on \(front.square.notation), with their \(name(behind.kind)) on \(behind.square.notation) behind it.", bundle: .localized)
                : String(localized: "Your opponent’s \(name(by.kind)) on \(by.square.notation) attacks your \(name(front.kind)) on \(front.square.notation), with your \(name(behind.kind)) on \(behind.square.notation) behind it.", bundle: .localized)
        case let .opening(remark):
            switch remark {
            case .earlyQueen:
                return String(localized: "Try not to bring your queen out too early. Develop your knights and bishops first.", bundle: .localized)
            case .castle:
                return String(localized: "Consider castling to keep your king safe.", bundle: .localized)
            case let .develop(count):
                return String(localized: "\(count) of your knights or bishops are still at home. Try developing them.", bundle: .localized)
            case .center:
                let (a, b) = finding.side == .white ? ("e4", "d4") : ("e5", "d5")
                return String(localized: "Fight for the center with a pawn on \(a) or \(b).", bundle: .localized)
            }
        }
    }

    // MARK: - 对方想干什么

    static func nullMove(_ board: Board) -> Board? { TacticsDetector.nullMove(board) }

    /// 玩家正被将军时，威胁就是将军本身。
    static func checkThreat(in position: Position, viewer: Piece.Color) -> OpponentThreat? {
        guard let checker = TacticsDetector.checkers(of: viewer, in: position).first,
              let king = TacticsDetector.king(of: viewer, in: position) else { return nil }
        return OpponentThreat(from: checker.square, to: king.square, san: "", kind: .inCheck(attacker: checker), followUp: nil, mateIn: nil)
    }

    /// 对方（空着后轮到它）的最佳着法的解释。
    /// - board: 空着之后、对方走子的棋盘；analysis：对它的搜索（对方视角）。
    static func threat(board: Board, analysis: EngineAnalysis, viewer: Piece.Color) -> OpponentThreat? {
        guard let applied = MoveExplainer.apply(uci: analysis.bestMove, on: board) else { return nil }
        let note = MoveExplainer.replyNote(
            boardBeforeReply: board, reply: applied, analysis: analysis, evalBefore: nil, player: viewer
        )
        let move = applied.final
        var kind = OpponentThreat.Kind.plan
        var followUp: CoachFinding?
        if move.checkState == .checkmate {
            kind = .mate
        } else if case let .capture(victim, attacker) = note.kind {
            let undefended = ThreatAnalyzer.attackers(of: move.end, by: viewer, in: Occupancy(board.position)).isEmpty
            kind = .capture(
                victim: victim, attacker: attacker,
                defense: undefended ? .undefended : (note.winsMaterial ? .losesMaterial : (note.canRecapture ? .canRecapture : .even))
            )
        } else if move.checkState == .check {
            kind = .check(piece: move.piece.kind)
        } else {
            // 安静的一步：看它之后新出现的、对玩家的战术威胁。
            let before = findings(position: board.position, viewer: viewer).map(\.tactic)
            followUp = findings(position: applied.board.position, viewer: viewer)
                .first { $0.side != viewer && $0.tier >= .tactic && !before.contains($0.tactic) }
        }
        var mateIn: Int?
        if move.checkState != .checkmate, case let .mate(n) = analysis.score, n >= 2 { mateIn = n }
        return OpponentThreat(from: move.start, to: move.end, san: move.san, kind: kind, followUp: followUp, mateIn: mateIn)
    }
}

/// 「对方想干什么」的结果：对方最佳着法（红箭头）+ 一句解释。
struct OpponentThreat: Equatable {
    enum Defense: Equatable {
        case undefended, losesMaterial, canRecapture, even
    }

    enum Kind: Equatable {
        case inCheck(attacker: CoachTarget)
        case mate
        case capture(victim: Piece.Kind, attacker: Piece.Kind, defense: Defense)
        case check(piece: Piece.Kind)
        case plan
    }

    let from: Square
    let to: Square
    let san: String
    let kind: Kind
    /// 安静的一步之后对玩家的新威胁。
    let followUp: CoachFinding?
    /// 对方几步内能将死（至少 2 步）。
    let mateIn: Int?

    var text: String {
        func name(_ kind: Piece.Kind) -> String { kind.localizedName.lowercased() }
        var parts: [String] = []
        switch kind {
        case let .inCheck(attacker):
            return String(localized: "Your opponent’s \(name(attacker.kind)) on \(attacker.square.notation) is giving check. Deal with the check first.", bundle: .localized)
        case .mate:
            return String(localized: "Your opponent threatens checkmate with \(san)!", bundle: .localized)
        case let .capture(victim, attacker, defense):
            let v = name(victim), a = name(attacker)
            switch defense {
            case .undefended:
                parts.append(String(localized: "Your opponent wants to capture your \(v) with a \(a) (\(san)). It has no defender.", bundle: .localized))
            case .losesMaterial:
                parts.append(String(localized: "Your opponent wants to capture your \(v) with a \(a) (\(san)). You would lose material.", bundle: .localized))
            case .canRecapture:
                parts.append(String(localized: "Your opponent wants to capture your \(v) with a \(a) (\(san)), but you can capture back.", bundle: .localized))
            case .even:
                parts.append(String(localized: "Your opponent wants to capture your \(v) with a \(a) (\(san)).", bundle: .localized))
            }
        case let .check(piece):
            parts.append(String(localized: "Your opponent wants to give check with a \(name(piece)) (\(san)).", bundle: .localized))
        case .plan:
            if let followUp {
                parts.append(String(localized: "Your opponent would like to play \(san).", bundle: .localized))
                parts.append(CoachExplainer.text(for: followUp, viewer: followUp.side.opposite))
            } else {
                parts.append(String(localized: "No immediate threat. Your opponent would probably play \(san).", bundle: .localized))
            }
        }
        if let mateIn {
            parts.append(String(localized: "Your opponent could checkmate you within \(mateIn) moves.", bundle: .localized))
        }
        return parts.joined(separator: " ")
    }
}
