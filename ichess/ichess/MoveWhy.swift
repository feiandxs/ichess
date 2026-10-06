//
//  MoveWhy.swift
//  ichess
//
//  「为什么走这步」：对比走前 / 走后的局面，找出这步棋做成了什么（吃子、捉双、保子、出子……）。
//  分级提示的三句话（想法 / 哪个子 / 答案）都从同一份 motif 说出来。纯逻辑，不碰引擎和界面。
//

import ChessKit
import Foundation

/// 一步棋做成的一件事（站在走子的玩家一方说话）。
enum MoveMotif: Equatable {
    case checkmate
    /// 挡住了对方的一步杀。
    case stopsMate
    case escapesCheck
    /// 吃到子且净赚；free：吃完这个子没人能吃回来。
    case winsPiece(victim: CoachTarget, free: Bool)
    /// 等价换子。
    case trade(victim: Piece.Kind, attacker: Piece.Kind)
    case promotes(Piece.Kind)
    /// 走完后造成捉双 / 牵制 / 串打。
    case tactic(Tactic)
    /// 走完后新出现的威胁：下一步能净赚这个子。
    case threatensToWin(victim: CoachTarget)
    case threatensMate
    case check
    /// 走的子本来要被白吃，现在安全了。
    case escapes(Piece.Kind)
    /// 别的子本来要被白吃，这步保住了。
    case savesPiece(CoachTarget)
    /// 化解了对方的捉双 / 牵制 / 串打。
    case removesThreat
    case castles
    case develops(Piece.Kind)
    case takesCenter
    case controlsCenter
    /// 没有明显的战术，只是稳健。
    case solid

    /// 越大越重要，排序用。
    var rank: Int {
        switch self {
        case .checkmate: 1000
        case .stopsMate: 900
        case .promotes: 820
        case let .winsPiece(_, free): free ? 800 : 780
        case let .tactic(tactic):
            switch tactic.motif {
            case .pin: 640
            case .skewer: 650
            default: 700
            }
        case .escapesCheck: 620
        case .escapes: 600
        case .savesPiece: 590
        case .threatensMate: 585
        case .threatensToWin: 560
        case .check: 400
        case .trade: 350
        case .removesThreat: 340
        case .castles: 300
        case .develops: 200
        case .takesCenter: 190
        case .controlsCenter: 180
        case .solid: 0
        }
    }
}

enum MoveWhy {
    // MARK: - 找出这步棋做成了什么

    /// 在 board（轮到玩家走）上走 uci 之后，这步棋做成的事，最重要的在前；至少有一项。
    static func motifs(board: Board, uci: String) -> [MoveMotif] {
        guard let applied = MoveExplainer.apply(uci: uci, on: board) else { return [] }
        let mover = board.position.sideToMove
        let enemy = mover.opposite
        let move = applied.final
        let after = applied.board
        if move.checkState == .checkmate { return [.checkmate] }

        var found: [MoveMotif] = []
        let beforePosition = board.position
        let afterOcc = Occupancy(after.position)

        if !TacticsDetector.checkers(of: mover, in: beforePosition).isEmpty { found.append(.escapesCheck) }

        if case let .capture(victim) = move.result {
            // 吃完之后对方还能不能净赚回来（交换全部算进去）。
            let lost = ThreatAnalyzer.exchangeGain(on: move.end, by: enemy, in: afterOcc)
            let net = ThreatAnalyzer.value(victim.kind) - lost
            if net >= 1 {
                let free = ThreatAnalyzer.attackers(of: move.end, by: enemy, in: afterOcc).isEmpty
                found.append(.winsPiece(victim: CoachTarget(kind: victim.kind, square: move.end), free: free))
            } else if net == 0 {
                found.append(.trade(victim: victim.kind, attacker: move.piece.kind))
            }
        }
        if let promoted = move.promotedPiece { found.append(.promotes(promoted.kind)) }
        if case .castle = move.result { found.append(.castles) }
        if move.checkState == .check { found.append(.check) }

        // 走完后我方新出现的战术：捉双 / 牵制 / 串打 / 能净赚的子。
        let oldMine = TacticsDetector.staticTactics(by: mover, in: beforePosition)
        let newMine = TacticsDetector.staticTactics(by: mover, in: after.position).filter { !oldMine.contains($0) }
        // 已经捉双 / 牵制 / 串打了，就不再单说「威胁吃子」。
        var threatened = newMine.contains { tactic in
            switch tactic.motif {
            case .fork, .pin, .skewer: true
            default: false
            }
        }
        for tactic in newMine {
            switch tactic.motif {
            case .fork, .pin, .skewer:
                found.append(.tactic(tactic))
            case let .hanging(victim, _), let .lesserAttacker(victim, _), let .outnumbered(victim, _):
                // 只说最大的那个威胁。
                if !threatened { found.append(.threatensToWin(victim: victim)) }
                threatened = true
            default:
                break
            }
        }
        if let nullBoard = TacticsDetector.nullMove(after), TacticsDetector.hasMateInOne(nullBoard) {
            found.append(.threatensMate)
        }

        // 防守：走的子脱险、别的子被保住、对方的杀棋 / 捉双被化解。
        let dangersBefore = ThreatAnalyzer.dangers(for: mover, in: beforePosition)
        let dangersAfter = ThreatAnalyzer.dangers(for: mover, in: after.position)
        if dangersBefore.contains(where: { $0.square == move.start }),
           !dangersAfter.contains(where: { $0.square == move.end }) {
            found.append(.escapes(move.piece.kind))
        } else if let saved = dangersBefore.first(where: { old in
            old.square != move.start
                && (dangersAfter.first { $0.square == old.square }?.loss ?? 0) < old.loss
        }) {
            found.append(.savesPiece(CoachTarget(kind: saved.kind, square: saved.square)))
        }
        let theirsBefore = CoachExplainer.findings(position: beforePosition, viewer: mover).filter { $0.side == enemy }
        let theirsAfter = CoachExplainer.findings(position: after.position, viewer: mover).filter { $0.side == enemy }.map(\.tactic)
        if theirsBefore.contains(where: { $0.motif == .mateInOne }), !theirsAfter.contains(where: { $0.motif == .mateInOne }) {
            found.append(.stopsMate)
        } else if theirsBefore.contains(where: { finding in
            switch finding.motif {
            case .fork, .pin, .skewer, .mate: !theirsAfter.contains(finding.tactic)
            default: false
            }
        }) {
            found.append(.removesThreat)
        }

        // 开局方面：出子、占中心。
        let homeRank = mover == .white ? 1 : 8
        if [.knight, .bishop].contains(move.piece.kind), move.start.rank.value == homeRank, move.end.rank.value != homeRank {
            found.append(.develops(move.piece.kind))
        }
        let center = ["d4", "e4", "d5", "e5"].map { Square($0) }
        if move.piece.kind == .pawn, center.contains(move.end), !center.contains(move.start) {
            found.append(.takesCenter)
        } else if [.knight, .bishop].contains(move.piece.kind), let piece = after.position.piece(at: move.end),
                  TacticsDetector.attackedSquares(by: piece, in: Occupancy(after.position)).filter({ center.contains($0) }).count >= 2 {
            found.append(.controlsCenter)
        }

        if found.isEmpty { return [.solid] }
        // 稳定排序：同分保持发现顺序。
        return found.enumerated()
            .sorted { $0.element.rank != $1.element.rank ? $0.element.rank > $1.element.rank : $0.offset < $1.offset }
            .map(\.element)
    }

    // MARK: - 说成人话

    private static func name(_ kind: Piece.Kind) -> String { kind.localizedName.lowercased() }

    /// 一句话：这步棋做成了什么（「它……」）。
    static func text(for motif: MoveMotif, mover: Piece.Color) -> String {
        switch motif {
        case .checkmate:
            return String(localized: "It checkmates your opponent!", bundle: .localized)
        case .stopsMate:
            return String(localized: "It stops your opponent’s checkmate threat.", bundle: .localized)
        case .escapesCheck:
            return String(localized: "It gets your king out of check.", bundle: .localized)
        case let .winsPiece(victim, free):
            return free
                ? String(localized: "It wins your opponent’s undefended \(name(victim.kind)) on \(victim.square.notation).", bundle: .localized)
                : String(localized: "It captures your opponent’s \(name(victim.kind)) on \(victim.square.notation) and comes out ahead.", bundle: .localized)
        case let .trade(victim, attacker):
            return String(localized: "It trades your \(name(attacker)) for your opponent’s \(name(victim)).", bundle: .localized)
        case let .promotes(kind):
            return String(localized: "It promotes your pawn to a \(name(kind)).", bundle: .localized)
        case let .tactic(tactic):
            return CoachExplainer.text(for: CoachFinding(tactic: tactic, priority: 0), viewer: mover)
        case let .threatensToWin(victim):
            return String(localized: "It threatens to win your opponent’s \(name(victim.kind)) on \(victim.square.notation).", bundle: .localized)
        case .threatensMate:
            return String(localized: "It threatens checkmate next move.", bundle: .localized)
        case .check:
            return String(localized: "It gives check.", bundle: .localized)
        case let .escapes(kind):
            return String(localized: "It moves your attacked \(name(kind)) to safety.", bundle: .localized)
        case let .savesPiece(target):
            return String(localized: "It saves your \(name(target.kind)) on \(target.square.notation) from being captured.", bundle: .localized)
        case .removesThreat:
            return String(localized: "It deals with your opponent’s threat.", bundle: .localized)
        case .castles:
            return String(localized: "It castles, which tucks your king away safely and brings a rook into play.", bundle: .localized)
        case let .develops(kind):
            return String(localized: "It develops your \(name(kind)) into the game.", bundle: .localized)
        case .takesCenter:
            return String(localized: "It stakes a claim in the center.", bundle: .localized)
        case .controlsCenter:
            return String(localized: "It helps you control the center.", bundle: .localized)
        case .solid:
            return String(localized: "It keeps your position solid and gives you the best chances.", bundle: .localized)
        }
    }

    /// 最多两句，最重要的在前。
    static func sentences(_ motifs: [MoveMotif], mover: Piece.Color, limit: Int = 2) -> String {
        motifs.prefix(limit).map { text(for: $0, mover: mover) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 等级 1 的大方向：不说哪个子、哪一格。
    static func plan(for motif: MoveMotif) -> String {
        switch motif {
        case .checkmate:
            String(localized: "You can checkmate your opponent this move. Look at every check!", bundle: .localized)
        case .stopsMate:
            String(localized: "Your opponent threatens checkmate. Stop it first!", bundle: .localized)
        case .escapesCheck:
            String(localized: "Your king is in check. Get out of check first.", bundle: .localized)
        case let .winsPiece(_, free):
            free
                ? String(localized: "One of your opponent’s pieces can be captured for free. Look for it!", bundle: .localized)
                : String(localized: "You can win material with a smart capture.", bundle: .localized)
        case .trade:
            String(localized: "Trading pieces is a good idea here.", bundle: .localized)
        case .promotes:
            String(localized: "Your pawn can promote. Go for it!", bundle: .localized)
        case let .tactic(tactic):
            switch tactic.motif {
            case .pin: String(localized: "Look for a way to pin one of your opponent’s pieces.", bundle: .localized)
            case .skewer: String(localized: "Look for a long-range attack that hits two pieces in a line.", bundle: .localized)
            default: String(localized: "Look for a move that attacks two pieces at once.", bundle: .localized)
            }
        case .threatensToWin:
            String(localized: "Look for a move that threatens one of your opponent’s pieces.", bundle: .localized)
        case .threatensMate:
            String(localized: "Look for a move that threatens checkmate.", bundle: .localized)
        case .check:
            String(localized: "A check can help you here.", bundle: .localized)
        case .escapes, .savesPiece:
            String(localized: "One of your pieces is in danger. Save it first.", bundle: .localized)
        case .removesThreat:
            String(localized: "Your opponent has a threat. Deal with it first.", bundle: .localized)
        case .castles:
            String(localized: "Think about getting your king to safety.", bundle: .localized)
        case .develops:
            String(localized: "Bring another knight or bishop into the game.", bundle: .localized)
        case .takesCenter, .controlsCenter:
            String(localized: "Think about the center of the board.", bundle: .localized)
        case .solid:
            String(localized: "Nothing urgent here. Improve the position of your pieces.", bundle: .localized)
        }
    }

    /// 等级 2：为什么是这个子。
    static func pieceReason(for motif: MoveMotif, piece: CoachTarget) -> String {
        let k = name(piece.kind), s = piece.square.notation
        switch motif {
        case .checkmate:
            return String(localized: "Your \(k) on \(s) can deliver checkmate.", bundle: .localized)
        case .stopsMate:
            return String(localized: "Your \(k) on \(s) can stop the checkmate.", bundle: .localized)
        case .escapesCheck:
            return String(localized: "Your \(k) on \(s) can get you out of check.", bundle: .localized)
        case .winsPiece, .trade:
            return String(localized: "Your \(k) on \(s) can make a good capture.", bundle: .localized)
        case .promotes:
            return String(localized: "Your pawn on \(s) is ready to promote.", bundle: .localized)
        case .tactic:
            return String(localized: "Your \(k) on \(s) can create a strong attack.", bundle: .localized)
        case .threatensToWin:
            return String(localized: "Your \(k) on \(s) can start an attack.", bundle: .localized)
        case .threatensMate:
            return String(localized: "Your \(k) on \(s) can threaten checkmate.", bundle: .localized)
        case .check:
            return String(localized: "Your \(k) on \(s) can give check.", bundle: .localized)
        case .escapes:
            return String(localized: "Your \(k) on \(s) is in danger. Move it to safety.", bundle: .localized)
        case .savesPiece:
            return String(localized: "Your \(k) on \(s) can protect your attacked piece.", bundle: .localized)
        case .removesThreat:
            return String(localized: "Your \(k) on \(s) can deal with your opponent’s threat.", bundle: .localized)
        case .castles:
            return String(localized: "Your king on \(s) should move to safety.", bundle: .localized)
        case .develops:
            return String(localized: "Your \(k) on \(s) hasn’t joined the game yet.", bundle: .localized)
        case .takesCenter:
            return String(localized: "Your \(k) on \(s) can claim space in the center.", bundle: .localized)
        case .controlsCenter:
            return String(localized: "Your \(k) on \(s) can reach a strong central square.", bundle: .localized)
        case .solid:
            return String(localized: "Your \(k) on \(s) can make the most useful move.", bundle: .localized)
        }
    }
}

/// 一次提示的三级内容：想法 / 哪个子 / 答案。位置和棋子用结构数据存，文字随语言现说。
struct HintExplanation: Equatable {
    let mover: Piece.Color
    /// 最佳着法做成的事，最重要的在前。
    let motifs: [MoveMotif]
    /// 要动的子（起点）。
    let piece: CoachTarget
    /// 局面里最该留意的一条（威胁 / 机会），没有为 nil。
    let focus: CoachFinding?

    /// 等级 1：只说方向，不点出着法。教练区没在说重点时就说最该留意的那条；已经在说了，就只补大方向，不重复。
    func ideaText(keyPointShown: Bool) -> String {
        let plan = MoveWhy.plan(for: motifs.first ?? .solid)
        guard !keyPointShown, let focus, focus.tier >= .tactic else { return plan }
        return CoachExplainer.text(for: focus, viewer: mover)
    }

    /// 等级 2：为什么是这个子。
    var pieceText: String { MoveWhy.pieceReason(for: motifs.first ?? .solid, piece: piece) }

    /// 等级 3：走完做成了什么。
    var answerText: String { MoveWhy.sentences(motifs, mover: mover) }

    static func make(board: Board, uci: String, analysis: EngineAnalysis?) -> HintExplanation? {
        guard let applied = MoveExplainer.apply(uci: uci, on: board) else { return nil }
        let mover = board.position.sideToMove
        let focus = CoachExplainer.findings(position: board.position, viewer: mover, analysis: analysis).first
        return HintExplanation(
            mover: mover,
            motifs: MoveWhy.motifs(board: board, uci: uci),
            piece: CoachTarget(kind: applied.final.piece.kind, square: applied.final.start),
            focus: focus
        )
    }
}
