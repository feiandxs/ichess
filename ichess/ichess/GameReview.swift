//
//  GameReview.swift
//  ichess
//
//  复盘和赛后总结共用的取数逻辑：把存档里的评估变成每步的点评。
//

import ChessKit
import Foundation

enum ReviewSupport {
    /// 「14. Nf3」/「14… Nf6」。
    static func moveLabel(index: Int, san: String) -> String {
        "\(index / 2 + 1)\(GameAnalysis.isPlayerMove(index) ? "." : "…") \(san)"
    }

    static func san(of move: MoveRecord) -> String {
        move.san ?? (move.from.isEmpty ? "…" : move.from + move.to)
    }

    /// 玩家第 index 步（着法下标）的点评；没分析、不是玩家的步为 nil。
    static func feedback(record: GameRecord, index: Int) -> MoveFeedback? {
        guard record.moves.indices.contains(index), GameAnalysis.isPlayerMove(index) else { return nil }
        let evals = record.evals
        let move = record.moves[index]
        guard let verdict = GameAnalysis.verdict(evals: evals, moves: record.moves, index: index) else { return nil }
        let number = index / 2 + 1
        let san = san(of: move)
        if let before = evals[index]?.analysis, let after = evals[index + 1]?.analysis,
           !move.from.isEmpty, let position = Position(fen: record.fen(atPly: index)),
           let full = MoveExplainer.feedback(
               boardBefore: Board(position: position),
               from: Square(move.from), to: Square(move.to), promotion: move.promotion,
               before: before, after: after, san: san, moveNumber: number
           ) {
            return full
        }
        // 终局（将死 / 和棋）局面没有搜索结果，只有评级和胜率。
        return MoveFeedback(
            verdict: verdict, reason: nil, better: nil, moveNumber: number, san: san,
            winBefore: GameAnalysis.playerWinPercent(evals[index], ply: index),
            winAfter: GameAnalysis.playerWinPercent(evals[index + 1], ply: index + 1)
        )
    }

    /// 引擎在这步之前的局面里推荐的后续变例（SAN，最多 5 步）。
    static func engineLine(record: GameRecord, index: Int) -> [String] {
        guard record.moves.indices.contains(index),
              let pv = record.evals[index]?.pv, !pv.isEmpty,
              let position = Position(fen: record.fen(atPly: index)) else { return [] }
        return MoveExplainer.sanLine(pv: pv, from: Board(position: position), limit: 5)
    }

    /// 演示用：这步之前的局面里引擎推荐的变例（逐步），和走完整条线后玩家的胜率。没有变例为 nil。
    static func engineDemo(record: GameRecord, index: Int) -> LineDemo? {
        guard record.moves.indices.contains(index), GameAnalysis.isPlayerMove(index),
              let pv = record.evals[index]?.pv, !pv.isEmpty,
              let position = Position(fen: record.fen(atPly: index)) else { return nil }
        let board = Board(position: position)
        return LineDemo(
            root: board, steps: CandidateSet.steps(pv: pv, from: board, limit: 6), viewer: .white,
            winEnd: GameAnalysis.playerWinPercent(record.evals[index], ply: index)
        )
    }

    /// 刚走完 san 这一步后，被将军 / 将死的一方的王所在格。
    static func checkedKing(in position: Position, san: String?) -> Square? {
        guard let san, san.hasSuffix("+") || san.hasSuffix("#") else { return nil }
        return position.pieces.first { $0.kind == .king && $0.color == position.sideToMove }?.square
    }

    /// 玩家视角的评分文字，如「略好 (+0.3)」。
    static func evalText(_ eval: PositionEval?, ply: Int) -> String? {
        guard let score = eval?.score else { return nil }
        let player = ply % 2 == 0 ? score : score.flipped
        return "\(MoveExplainer.evalName(player)) (\(MoveExplainer.evalNumber(player)))"
    }
}
