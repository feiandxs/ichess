//
//  GameRecord.swift
//  ichess
//
//  存档用的纯数据：局面评估、一盘棋的完整记录。不依赖界面和引擎，方便单独测试。
//

import Foundation

nonisolated enum GameResult: String, Codable, Sendable {
    case win, loss, draw
}

/// 一个局面的引擎评估（可存盘）。评分视角见 `EngineScore`：当前走子方。
nonisolated struct PositionEval: Codable, Equatable, Sendable {
    var cp: Int?
    var mate: Int?
    /// 引擎推荐的着法（UCI）。
    var best: String?
    /// 主变例（UCI），只留前几步。
    var pv: [String]?
    var depth: Int?

    var score: EngineScore? {
        if let mate { return .mate(mate) }
        if let cp { return .centipawns(cp) }
        return nil
    }

    init(score: EngineScore?, best: String? = nil, pv: [String]? = nil, depth: Int? = nil) {
        switch score {
        case let .centipawns(value)?: cp = value
        case let .mate(value)?: mate = value
        case nil: break
        }
        self.best = best
        self.pv = pv
        self.depth = depth
    }

    init(_ analysis: EngineAnalysis) {
        self.init(
            score: analysis.score,
            best: analysis.bestMove,
            pv: Array(analysis.pv.prefix(6)),
            depth: analysis.depth
        )
    }

    /// 还原成引擎结果，供 MoveExplainer 复用；缺评分或最佳着法时为 nil。
    var analysis: EngineAnalysis? {
        guard let score, let best, !best.isEmpty else { return nil }
        return EngineAnalysis(bestMove: best, score: score, pv: pv ?? [best], depth: depth ?? 0)
    }

    /// 走子方已被将死的终局：引擎无法搜索，直接给定。
    static let checkmated = PositionEval(score: .mate(-1))
    /// 无子可动 / 子力不足的和棋终局。
    static let drawn = PositionEval(score: .centipawns(0))
}

nonisolated enum GameEndReason: String, Codable, Sendable {
    case checkmate, resignation, stalemate, repetition, fiftyMoves, insufficientMaterial, agreement
    /// 没下完就被「新对局」放弃。
    case abandoned

    /// 终局局面（走子方无法被搜索）的固定评估；其余原因为 nil，交给引擎。
    var terminalEval: PositionEval? {
        switch self {
        case .checkmate: .checkmated
        case .stalemate, .insufficientMaterial: .drawn
        default: nil
        }
    }
}

/// 归档的一盘棋。玩家始终执白；moves[i].fen 是第 i+1 步之后的局面。
nonisolated struct GameRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var date: Date
    var mode: GameMode
    var difficulty: Difficulty
    /// nil 表示没下完（放弃的对局）。
    var result: GameResult?
    var reason: GameEndReason
    /// 仅对战局；练习局为 nil。
    var ratingDelta: Int?
    var ratingAfter: Int?
    /// 初始局面的评估。
    var startEval: PositionEval?
    var moves: [MoveRecord]

    var isFinished: Bool { result != nil }

    /// 每个局面（0 = 初始局面，i = 第 i 步之后）的评估，数量为 moves.count + 1。
    var evals: [PositionEval?] { GameAnalysis.evals(startEval: startEval, moves: moves) }

    /// 局面 ply 的 FEN。
    func fen(atPly ply: Int) -> String {
        ply == 0 ? GameRecord.startFEN : moves[ply - 1].fen
    }

    mutating func setEval(_ eval: PositionEval, atPly ply: Int) {
        if ply == 0 {
            startEval = eval
        } else if moves.indices.contains(ply - 1) {
            moves[ply - 1].eval = eval
        }
    }

    /// 终局局面补上固定评估（将死 / 无子可动 / 子力不足），不必再让引擎分析。
    mutating func fillTerminalEval() {
        guard isFinished, let eval = reason.terminalEval, !moves.isEmpty, moves[moves.count - 1].eval == nil else { return }
        moves[moves.count - 1].eval = eval
    }

    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}
