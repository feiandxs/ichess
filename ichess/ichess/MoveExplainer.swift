//
//  MoveExplainer.swift
//  ichess
//
//  把引擎结果翻译成新手能看懂的话：走后点评的原因、试走时对方应对的解释、提示的后续变例。
//  只依赖 ChessKit 和纯数据类型，不碰引擎，方便单独测试。
//

import ChessKit
import Foundation

struct BetterMove: Equatable {
    let from: Square
    let to: Square
    let san: String
}

enum FeedbackReason: Equatable {
    case missedMate
    case allowsMate
    case losesPiece(Piece.Kind)
    case opponentCanCapture(Piece.Kind)
    case missedCapture(Piece.Kind)

    var text: String {
        switch self {
        case .missedMate:
            String(localized: "You missed a checkmate.", bundle: .localized)
        case .allowsMate:
            String(localized: "This lets your opponent checkmate you.", bundle: .localized)
        case let .losesPiece(kind):
            String(localized: "This move loses your \(kind.localizedName.lowercased()).", bundle: .localized)
        case let .opponentCanCapture(kind):
            String(localized: "Your opponent can capture your \(kind.localizedName.lowercased()).", bundle: .localized)
        case let .missedCapture(kind):
            String(localized: "You missed a chance to capture a \(kind.localizedName.lowercased()).", bundle: .localized)
        }
    }
}

/// 玩家一步棋的点评。
struct MoveFeedback: Equatable {
    let verdict: MoveVerdict
    let reason: FeedbackReason?
    /// 引擎认为更好的走法；走的就是最佳着法时为 nil。
    let better: BetterMove?
    /// 被点评的这步棋（玩家的步）：第几回合、SAN。
    var moveNumber = 0
    var san = ""
    /// 这步棋前后玩家的胜率（0...100）。
    var winBefore: Double?
    var winAfter: Double?

    /// 「你的第 1 步 e4：最佳」，明确点评的是哪一步、谁走的。
    var headline: String {
        guard moveNumber > 0, !san.isEmpty else { return verdict.title }
        return String(localized: "Your move \(moveNumber). \(san): \(verdict.title)", bundle: .localized)
    }

    /// 「胜率 52% → 30%」，用大白话说清这步棋让局面变好还是变差。
    var winLine: String? {
        guard let winBefore, let winAfter else { return nil }
        let before = "\(Int(winBefore.rounded()))%"
        let after = "\(Int(winAfter.rounded()))%"
        return String(localized: "Win chances: \(before) → \(after)", bundle: .localized)
    }

    /// 原因 + 更好的走法，一行说明；没有可说的为 nil。
    var detail: String? {
        var parts: [String] = []
        if let reason { parts.append(reason.text) }
        if let better { parts.append(String(localized: "Better: \(better.san)", bundle: .localized)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension MoveVerdict {
    var title: String {
        switch self {
        case .best: String(localized: "Best move", bundle: .localized)
        case .good: String(localized: "Good move", bundle: .localized)
        case .inaccuracy: String(localized: "Inaccuracy", bundle: .localized)
        case .mistake: String(localized: "Mistake", bundle: .localized)
        case .blunder: String(localized: "Blunder", bundle: .localized)
        }
    }
}

extension MoveVerdict {
    /// 统计行里用的短名称。
    var shortTitle: String {
        switch self {
        case .best: String(localized: "Best", bundle: .localized)
        case .good: String(localized: "Good", bundle: .localized)
        case .inaccuracy: String(localized: "Inaccuracy", bundle: .localized)
        case .mistake: String(localized: "Mistake", bundle: .localized)
        case .blunder: String(localized: "Blunder", bundle: .localized)
        }
    }

    var symbol: String {
        switch self {
        case .best: "star.fill"
        case .good: "checkmark.circle.fill"
        case .inaccuracy: "exclamationmark.circle.fill"
        case .mistake: "exclamationmark.triangle.fill"
        case .blunder: "xmark.octagon.fill"
        }
    }
}

/// 试走里对方应对的解释素材。
struct ReplyNote: Equatable {
    enum Kind: Equatable {
        case capture(victim: Piece.Kind, attacker: Piece.Kind)
        case plain
    }

    let san: String
    let kind: Kind
    let checkState: Move.CheckState
    /// 被吃的子本来就没有足够保护，吃了就是净赚。
    let winsMaterial: Bool
    /// 吃完后我方还能吃回去。
    let canRecapture: Bool
    /// 对方（含这一步）几步内能将死我方；只在还没将死、至少 2 步时有值。
    let mateIn: Int?
    /// 这一步试走前 / 对方应对后的局面评分，玩家视角。
    let evalBefore: EngineScore?
    let evalAfter: EngineScore?

    var headline: String {
        if checkState == .checkmate {
            return String(localized: "Your opponent will checkmate you (\(san))", bundle: .localized)
        }
        switch kind {
        case let .capture(victim, attacker):
            return String(localized: "Your opponent will capture your \(victim.localizedName.lowercased()) with a \(attacker.localizedName.lowercased()) (\(san))", bundle: .localized)
        case .plain:
            if checkState == .check {
                return String(localized: "Your opponent will give check (\(san))", bundle: .localized)
            }
            return String(localized: "Your opponent will play \(san)", bundle: .localized)
        }
    }

    var detail: String? {
        if checkState == .checkmate { return nil }
        var parts: [String] = []
        if case .capture = kind {
            if checkState == .check { parts.append(String(localized: "It also gives check.", bundle: .localized)) }
            if winsMaterial {
                parts.append(String(localized: "You’d come out behind in material.", bundle: .localized))
            } else if canRecapture {
                parts.append(String(localized: "But you can capture back.", bundle: .localized))
            }
        }
        if let mateIn {
            parts.append(String(localized: "Your opponent could checkmate you within \(mateIn) moves.", bundle: .localized))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

enum SandboxNote: Equatable {
    case reply(ReplyNote)
    case checkmatesOpponent
    case draw

    var headline: String {
        switch self {
        case let .reply(note): note.headline
        case .checkmatesOpponent: String(localized: "This checkmates your opponent!", bundle: .localized)
        case .draw: String(localized: "This move ends the game in a draw.", bundle: .localized)
        }
    }

    var detail: String? {
        if case let .reply(note) = self { return note.detail }
        return nil
    }

    var evalLine: String? {
        guard case let .reply(note) = self else { return nil }
        return MoveExplainer.evalLine(before: note.evalBefore, after: note.evalAfter)
    }
}

enum MoveExplainer {
    struct Applied {
        let board: Board
        /// 走完后的着法（升变前，棋盘动画用）。
        let played: Move
        /// 含升变选择的最终着法，SAN 用这个。
        let final: Move
    }

    /// 在 board 上走一步 UCI 着法；不合法返回 nil。升变默认升后，除非 UCI 带了升变字母。
    static func apply(uci: String, on board: Board) -> Applied? {
        let side = board.position.sideToMove
        guard let parsed = EngineLANParser.parse(move: uci, for: side, in: board.position),
              board.legalMoves(forPieceAt: parsed.start).contains(parsed.end) else { return nil }
        var next = board
        guard let played = next.move(pieceAt: parsed.start, to: parsed.end) else { return nil }
        var final = played
        if case let .promotion(pending) = next.state {
            final = next.completePromotion(of: pending, to: parsed.promotedPiece?.kind ?? .queen)
        }
        return Applied(board: next, played: played, final: final)
    }

    /// 主变例转成 SAN 列表（最多 limit 步）；遇到走不通的着法就截止。
    static func sanLine(pv: [String], from board: Board, limit: Int) -> [String] {
        var current = board
        var result: [String] = []
        for uci in pv.prefix(limit) {
            guard let applied = apply(uci: uci, on: current) else { break }
            result.append(applied.final.san)
            current = applied.board
        }
        return result
    }

    // MARK: - 走后点评

    /// - boardBefore: 玩家走棋前的局面。
    /// - before: 走之前对该局面的搜索（玩家视角）；after: 走之后对新局面的搜索（对手视角）。
    static func feedback(
        boardBefore: Board,
        from: Square,
        to: Square,
        promotion: String?,
        before: EngineAnalysis,
        after: EngineAnalysis,
        san: String = "",
        moveNumber: Int = 0
    ) -> MoveFeedback? {
        guard let scoreBefore = before.score, let scoreAfter = after.score else { return nil }
        let playedUCI = from.notation + to.notation + (promotion ?? "")
        let playedBest = playedUCI == before.bestMove
        let verdict = MoveClassifier.classify(before: scoreBefore, afterOpponentView: scoreAfter, playedBest: playedBest)
        let winBefore = MoveClassifier.winPercent(scoreBefore)
        let winAfter = MoveClassifier.winPercent(scoreAfter.flipped)
        guard verdict.isProblem else {
            return MoveFeedback(
                verdict: verdict, reason: nil, better: nil,
                moveNumber: moveNumber, san: san, winBefore: winBefore, winAfter: winAfter
            )
        }

        let bestApplied = apply(uci: before.bestMove, on: boardBefore)
        let better = playedBest ? nil : bestApplied.map {
            BetterMove(from: $0.played.start, to: $0.played.end, san: $0.final.san)
        }
        let reason = reason(
            boardBefore: boardBefore, from: from, to: to, playedUCI: playedUCI,
            bestApplied: playedBest ? nil : bestApplied,
            scoreBefore: scoreBefore, scoreAfter: scoreAfter, after: after
        )
        return MoveFeedback(
            verdict: verdict, reason: reason, better: better,
            moveNumber: moveNumber, san: san, winBefore: winBefore, winAfter: winAfter
        )
    }

    private static func reason(
        boardBefore: Board,
        from: Square,
        to: Square,
        playedUCI: String,
        bestApplied: Applied?,
        scoreBefore: EngineScore,
        scoreAfter: EngineScore,
        after: EngineAnalysis
    ) -> FeedbackReason? {
        if case let .mate(n) = scoreAfter, n > 0 { return .allowsMate }
        if case let .mate(n) = scoreBefore, n > 0 { return .missedMate }
        if let risk = ThreatAnalyzer.risk(of: boardBefore, from: from, to: to) {
            return .losesPiece(risk.danger.kind)
        }
        let mover = boardBefore.position.sideToMove
        // 对方最佳应对如果是吃掉我方一个子，就直接点明。
        if let applied = apply(uci: playedUCI, on: boardBefore),
           let replyUCI = after.pv.first,
           let reply = apply(uci: replyUCI, on: applied.board),
           case let .capture(piece) = reply.final.result,
           piece.color == mover, ThreatAnalyzer.value(piece.kind) >= 3 {
            return .opponentCanCapture(piece.kind)
        }
        if let bestApplied, case let .capture(piece) = bestApplied.final.result,
           piece.color != mover, ThreatAnalyzer.value(piece.kind) >= 3 {
            return .missedCapture(piece.kind)
        }
        return nil
    }

    // MARK: - 试走

    /// 玩家试走一步后，对方引擎应对（analysis 是对方视角的搜索）的解释。
    /// - boardBeforeReply: 玩家试走之后、对方应对之前的局面。
    static func replyNote(
        boardBeforeReply: Board,
        reply: Applied,
        analysis: EngineAnalysis,
        evalBefore: EngineScore?,
        player: Piece.Color
    ) -> ReplyNote {
        var kind = ReplyNote.Kind.plain
        var winsMaterial = false
        var canRecapture = false
        if case let .capture(victim) = reply.final.result {
            kind = .capture(victim: victim.kind, attacker: reply.final.piece.kind)
            let hanging = ThreatAnalyzer.dangers(for: player, in: boardBeforeReply.position)
            winsMaterial = hanging.contains { $0.square == reply.final.end }
            canRecapture = !ThreatAnalyzer.attackers(
                of: reply.final.end, by: player, in: Occupancy(reply.board.position)
            ).isEmpty
        }
        var mateIn: Int?
        if reply.final.checkState != .checkmate, case let .mate(n) = analysis.score, n >= 2 {
            mateIn = n
        }
        return ReplyNote(
            san: reply.final.san,
            kind: kind,
            checkState: reply.final.checkState,
            winsMaterial: winsMaterial,
            canRecapture: canRecapture,
            mateIn: mateIn,
            evalBefore: evalBefore,
            evalAfter: analysis.score?.flipped
        )
    }

    // MARK: - 评分文字（玩家视角）

    static func evalName(_ score: EngineScore) -> String {
        switch score {
        case let .mate(n):
            return n > 0
                ? String(localized: "Forced mate for you", bundle: .localized)
                : String(localized: "You may get mated", bundle: .localized)
        case let .centipawns(cp):
            switch cp {
            case 600...: return String(localized: "Winning", bundle: .localized)
            case 250..<600: return String(localized: "Clearly better", bundle: .localized)
            case 80..<250: return String(localized: "Slightly better", bundle: .localized)
            case -79..<80: return String(localized: "Equal", bundle: .localized)
            case -249 ..< -79: return String(localized: "Slightly worse", bundle: .localized)
            case -599 ..< -249: return String(localized: "Clearly worse", bundle: .localized)
            default: return String(localized: "Losing", bundle: .localized)
            }
        }
    }

    /// 带符号的兵值，如 +0.3、-2.1、#3。
    static func evalNumber(_ score: EngineScore) -> String {
        switch score {
        case let .mate(n): n > 0 ? "#\(n)" : "-#\(abs(n))"
        case let .centipawns(cp): String(format: "%+.1f", Double(cp) / 100)
        }
    }

    static func evalLine(before: EngineScore?, after: EngineScore?) -> String? {
        guard let after else { return nil }
        let now = "\(evalName(after)) (\(evalNumber(after)))"
        if let before {
            return String(localized: "Evaluation: \(evalName(before)) → \(now)", bundle: .localized)
        }
        return String(localized: "Evaluation: \(now)", bundle: .localized)
    }
}
