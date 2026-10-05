//
//  GameAnalysis.swift
//  ichess
//
//  整盘棋的评估统计：胜率曲线、每步评级、准确率、关键失误。纯逻辑，不依赖引擎和界面。
//  玩家始终执白：着法下标（从 0 起）为偶数的是玩家的步，局面下标（0 = 初始）为偶数时轮到白方。
//

import Foundation

nonisolated enum GameAnalysis {
    /// 每个局面的评估：初始局面 + 每步之后。
    static func evals(startEval: PositionEval?, moves: [MoveRecord]) -> [PositionEval?] {
        [startEval] + moves.map(\.eval)
    }

    static func isPlayerMove(_ index: Int) -> Bool { index % 2 == 0 }

    /// 局面 ply 的评估换成玩家（白方）的胜率 0...100；没有评分时为 nil。
    static func playerWinPercent(_ eval: PositionEval?, ply: Int) -> Double? {
        guard let score = eval?.score else { return nil }
        let mover = MoveClassifier.winPercent(score)
        return ply % 2 == 0 ? mover : 100 - mover
    }

    static func winSeries(_ evals: [PositionEval?]) -> [Double?] {
        evals.enumerated().map { playerWinPercent($1, ply: $0) }
    }

    /// 缺评估的局面下标。
    static func missingPlies(_ evals: [PositionEval?]) -> [Int] {
        evals.indices.filter { evals[$0] == nil }
    }

    /// 走子方这一步（下标 index）造成的胜率下降，不小于 0；前后局面缺评分时为 nil。
    static func drop(evals: [PositionEval?], index: Int) -> Double? {
        guard evals.indices.contains(index + 1),
              let before = evals[index]?.score, let after = evals[index + 1]?.score else { return nil }
        return max(0, MoveClassifier.winPercentDrop(before: before, afterOpponentView: after))
    }

    static func verdict(evals: [PositionEval?], moves: [MoveRecord], index: Int) -> MoveVerdict? {
        guard moves.indices.contains(index), evals.indices.contains(index + 1),
              let before = evals[index], let beforeScore = before.score,
              let afterScore = evals[index + 1]?.score else { return nil }
        let playedBest = !moves[index].uci.isEmpty && moves[index].uci == before.best
        return MoveClassifier.classify(before: beforeScore, afterOpponentView: afterScore, playedBest: playedBest)
    }

    // MARK: - 准确率

    /// Lichess 单步准确率：由胜率下降（百分点）换算，限制在 0...100。
    static func moveAccuracy(drop: Double) -> Double {
        let value = 103.1668 * exp(-0.04354 * max(0, drop)) - 3.1669
        return min(100, max(0, value))
    }

    /// 整局准确率 = 算术平均与调和平均的均值（Lichess 的做法，但不加波动权重）。
    /// 调和平均对个别大漏着更敏感：单步按 1 兜底，避免 0 分把结果拉到 0。
    static func combinedAccuracy(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let arithmetic = values.reduce(0, +) / Double(values.count)
        let harmonic = Double(values.count) / values.reduce(0) { $0 + 1 / max($1, 1) }
        return (arithmetic + harmonic) / 2
    }

    // MARK: - 报告

    struct KeyMoment: Equatable, Sendable {
        /// 着法下标。
        let index: Int
        /// 胜率下降（百分点）。
        let drop: Double
        let verdict: MoveVerdict
    }

    struct Report: Equatable, Sendable {
        /// 玩家胜率，每个局面一项。
        var winPercents: [Double?]
        /// 每步评级，只给玩家的步；对手的步和未分析的为 nil。
        var verdicts: [MoveVerdict?]
        /// 每步（双方）的胜率下降。
        var drops: [Double?]
        var accuracy: Double?
        var counts: [MoveVerdict: Int]
        var analyzedPlayerMoves: Int
        var playerMoves: Int
        /// 所有局面都有评估。
        var isComplete: Bool
        /// 玩家的步中下降达到「不够精确」的，按下降从大到小。
        var keyMistakes: [KeyMoment]

        /// 最大的一次失误。
        var keyMoment: KeyMoment? { keyMistakes.first }

        func count(_ verdict: MoveVerdict) -> Int { counts[verdict] ?? 0 }
    }

    static func report(startEval: PositionEval?, moves: [MoveRecord]) -> Report {
        let evals = evals(startEval: startEval, moves: moves)
        var verdicts: [MoveVerdict?] = []
        var drops: [Double?] = []
        var accuracies: [Double] = []
        var counts: [MoveVerdict: Int] = [:]
        var mistakes: [KeyMoment] = []
        for index in moves.indices {
            let drop = drop(evals: evals, index: index)
            drops.append(drop)
            guard isPlayerMove(index) else {
                verdicts.append(nil)
                continue
            }
            let verdict = verdict(evals: evals, moves: moves, index: index)
            verdicts.append(verdict)
            guard let drop, let verdict else { continue }
            accuracies.append(moveAccuracy(drop: drop))
            counts[verdict, default: 0] += 1
            if drop >= MoveClassifier.inaccuracyDrop {
                mistakes.append(KeyMoment(index: index, drop: drop, verdict: verdict))
            }
        }
        // 同样的下降，靠前的排前面。
        mistakes.sort { $0.drop != $1.drop ? $0.drop > $1.drop : $0.index < $1.index }
        return Report(
            winPercents: winSeries(evals),
            verdicts: verdicts,
            drops: drops,
            accuracy: combinedAccuracy(accuracies),
            counts: counts,
            analyzedPlayerMoves: accuracies.count,
            playerMoves: (moves.count + 1) / 2,
            isComplete: missingPlies(evals).isEmpty,
            keyMistakes: mistakes
        )
    }

    // MARK: - 实时胜率

    /// 最新的玩家胜率，以及相对上一个有值的局面的变化（百分点）。
    static func latestWin(_ series: [Double?]) -> (value: Double, delta: Double?, isCurrent: Bool)? {
        guard let last = series.lastIndex(where: { $0 != nil }), let value = series[last] else { return nil }
        let previous = series[..<last].last(where: { $0 != nil }) ?? nil
        return (value, previous.map { value - $0 }, last == series.count - 1)
    }
}
