//
//  EngineAnalysis.swift
//  ichess
//

import ChessKit
import ChessKitEngine

/// 从 `info` 响应里累积最深的主线（multipv 1）评分与变例。
///
/// ChessKitEngine 给每条响应各开一个 Task 转发，到达顺序不保证：上一次搜索的 info
/// 可能迟到并混进这一次（曾把起始局面评成 +4.8，使 1.e4 被判大漏着）。
/// 传入 fen 后，变例在该局面上走不通的 info 一律丢弃。
nonisolated struct EngineAnalysisBuilder {
    private let root: Board?

    init(fen: String? = nil) {
        root = fen.flatMap { Position(fen: $0) }.map { Board(position: $0) }
    }

    /// pv 的前几步在 fen 局面上依次合法；没有 fen 时不校验。
    private func isLegalLine(_ pv: [String]) -> Bool {
        guard var board = root else { return true }
        for uci in pv.prefix(6) {
            guard let parsed = EngineLANParser.parse(move: uci, for: board.position.sideToMove, in: board.position),
                  board.legalMoves(forPieceAt: parsed.start).contains(parsed.end),
                  board.move(pieceAt: parsed.start, to: parsed.end) != nil else { return false }
            if case let .promotion(pending) = board.state {
                _ = board.completePromotion(of: pending, to: parsed.promotedPiece?.kind ?? .queen)
            }
        }
        return true
    }

    private(set) var score: EngineScore?
    private(set) var pv: [String] = []
    private(set) var depth = 0

    mutating func add(_ info: EngineResponse.Info) {
        // 只取主线；上下界（lowerbound / upperbound）是搜索中途的不精确值，跳过。
        guard (info.multipv ?? 1) == 1,
              let raw = info.score,
              raw.lowerbound != true, raw.upperbound != true,
              let line = info.pv, !line.isEmpty,
              isLegalLine(line) else { return }
        let newDepth = info.depth ?? 0
        guard newDepth >= depth else { return }
        if let mate = raw.mate {
            score = .mate(mate)
        } else if let cp = raw.cp {
            score = .centipawns(Int(cp.rounded()))
        } else {
            return
        }
        pv = line
        depth = newDepth
    }

    func build(bestMove: String) -> EngineAnalysis {
        EngineAnalysis(bestMove: bestMove, score: score, pv: pv.isEmpty ? [bestMove] : pv, depth: depth)
    }
}
