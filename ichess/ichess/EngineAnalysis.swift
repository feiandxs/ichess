//
//  EngineAnalysis.swift
//  ichess
//

import ChessKit
import ChessKitEngine

/// 从 `info` 响应里累积最深的主线（multipv 1）评分与变例，MultiPV 时同时收齐各条候选线。
///
/// ChessKitEngine 给每条响应各开一个 Task 转发，到达顺序不保证：上一次搜索的 info
/// 可能迟到并混进这一次（曾把起始局面评成 +4.8，使 1.e4 被判大漏着）。
/// 传入 fen 后，变例在该局面上走不通的 info 一律丢弃。
nonisolated struct EngineAnalysisBuilder {
    private var accumulator: EngineLineAccumulator

    init(fen: String? = nil) {
        accumulator = EngineLineAccumulator(fen: fen)
    }

    private(set) var score: EngineScore?
    private(set) var pv: [String] = []
    private(set) var depth = 0

    mutating func add(_ info: EngineResponse.Info) {
        // 上下界（lowerbound / upperbound）是搜索中途的不精确值，跳过。
        guard let raw = info.score,
              raw.lowerbound != true, raw.upperbound != true,
              let line = info.pv, !line.isEmpty else { return }
        let parsed: EngineScore
        if let mate = raw.mate {
            parsed = .mate(mate)
        } else if let cp = raw.cp {
            parsed = .centipawns(Int(cp.rounded()))
        } else {
            return
        }
        let index = info.multipv ?? 1
        let newDepth = info.depth ?? 0
        guard accumulator.add(multipv: index, depth: newDepth, score: parsed, pv: line) else { return }
        // 主线（multipv 1）给单线结果；其余只进候选线。
        if index == 1 {
            score = parsed
            pv = line
            depth = newDepth
        }
    }

    func build(bestMove: String) -> EngineAnalysis {
        EngineAnalysis(
            bestMove: bestMove, score: score, pv: pv.isEmpty ? [bestMove] : pv, depth: depth,
            lines: accumulator.lines
        )
    }
}
