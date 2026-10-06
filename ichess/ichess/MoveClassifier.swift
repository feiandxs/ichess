//
//  MoveClassifier.swift
//  ichess
//
//  走后点评的评级：比较走棋前后的引擎评分，按胜率下降幅度分级。纯逻辑，不依赖引擎和界面。
//

import Foundation

nonisolated enum MoveVerdict: String, Equatable, Sendable {
    case best, good, inaccuracy, mistake, blunder

    /// 不够精确及以上，需要给出原因和更好的走法。
    var isProblem: Bool {
        switch self {
        case .best, .good: false
        case .inaccuracy, .mistake, .blunder: true
        }
    }
}

nonisolated enum MoveClassifier {
    /// 胜率下降（百分点）达到这些值就算对应等级。
    /// 初学者友好：丢一个兵约 9（不够精确），丢一个子约 24（大漏着）。
    static let inaccuracyDrop = 7.0
    static let mistakeDrop = 13.0
    static let blunderDrop = 20.0
    /// 下降不超过这个值，视为和最佳着法一样好。
    static let bestTolerance = 1.0

    /// 评分换成走子方的胜率（0...100），Lichess 公式。杀棋直接 100 / 0。
    static func winPercent(_ score: EngineScore) -> Double {
        switch score {
        case let .centipawns(cp):
            let clamped = Double(min(1000, max(-1000, cp)))
            return 50 + 50 * (2 / (1 + exp(-0.00368208 * clamped)) - 1)
        case let .mate(n):
            return n > 0 ? 100 : 0
        }
    }

    /// 走子方这步棋造成的胜率下降。
    /// - before: 走之前的评分，走子方视角。
    /// - afterOpponentView: 走之后对局面的评分，引擎给的是下一个走子方（对手）视角，这里翻转回来。
    static func winPercentDrop(before: EngineScore, afterOpponentView: EngineScore) -> Double {
        winPercent(before) - winPercent(afterOpponentView.flipped)
    }

    static func classify(before: EngineScore, afterOpponentView: EngineScore, playedBest: Bool) -> MoveVerdict {
        let drop = winPercentDrop(before: before, afterOpponentView: afterOpponentView)
        var verdict: MoveVerdict
        if drop >= blunderDrop {
            verdict = .blunder
        } else if drop >= mistakeDrop {
            verdict = .mistake
        } else if drop >= inaccuracyDrop {
            verdict = .inaccuracy
        } else if playedBest || drop <= bestTolerance {
            verdict = .best
        } else {
            verdict = .good
        }
        // 有强制杀棋却没走出来：胜率还很高也至少提醒一下。
        if case let .mate(n) = before, n > 0, !isMateForMover(afterOpponentView.flipped), !playedBest,
           verdict == .best || verdict == .good {
            verdict = .inaccuracy
        }
        return verdict
    }

    private static func isMateForMover(_ score: EngineScore) -> Bool {
        if case let .mate(n) = score { return n > 0 }
        return false
    }
}
