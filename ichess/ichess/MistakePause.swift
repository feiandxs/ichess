//
//  MistakePause.swift
//  ichess
//
//  练习模式「失误时暂停」的纯逻辑：按评级决定对手是否等玩家、不够精确时留多久、撤回重走撤哪步、幽灵棋子的动画节奏。
//

import Foundation

nonisolated enum MistakePause {
    enum Action: Equatable {
        /// 照常：对手马上走。
        case none
        /// 不够精确：不阻塞，对手的回应至少等到点评出现后这么多毫秒。
        case delay(milliseconds: Int)
        /// 失误 / 大漏着：对手一直等，直到玩家选择。
        case pause
    }

    /// 不够精确时，让「更好的走法」箭头至少留在棋盘上的时间（从点评出现起算）。
    static let inaccuracyDelayMilliseconds = 3000
    /// 对手走子前固定的停顿（毫秒），和原有行为一致。
    static let baseReplyPauseMilliseconds = 420

    /// 开关关闭、对战模式、没有更好的走法可展示时一律照常。
    static func action(verdict: MoveVerdict, mode: GameMode, enabled: Bool, hasBetterMove: Bool) -> Action {
        guard enabled, mode.allowsAids, hasBetterMove else { return .none }
        switch verdict {
        case .best, .good: return .none
        case .inaccuracy: return .delay(milliseconds: inaccuracyDelayMilliseconds)
        case .mistake, .blunder: return .pause
        }
    }

    /// 对手回应前还要等多久（毫秒）：点评已出现 elapsed 秒，至少保留原来的固定停顿。
    static func replyWait(delayMilliseconds: Int, elapsed: TimeInterval) -> Int {
        let remaining = delayMilliseconds - Int((max(0, elapsed) * 1000).rounded())
        return max(baseReplyPauseMilliseconds, remaining)
    }

    /// 撤回重走：暂停时对手还没走，只撤玩家的最后一步。
    static func afterTakeBack(_ moves: [MoveRecord]) -> [MoveRecord] {
        Array(moves.dropLast())
    }
}

/// 幽灵棋子沿「更好的走法」来回滑动的节奏：滑过去、停一下、回来、再停一下，循环。
nonisolated enum GhostMotion {
    static let slide = 1.0
    static let holdAtEnd = 0.5
    static let slideBack = 0.7
    static let holdAtStart = 0.4
    static var cycle: Double { slide + holdAtEnd + slideBack + holdAtStart }

    /// time 秒（从开始起算）时的进度：0 在起点，1 在终点。
    static func progress(at time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: cycle)
        let phase = t < 0 ? t + cycle : t
        if phase < slide { return ease(phase / slide) }
        if phase < slide + holdAtEnd { return 1 }
        if phase < slide + holdAtEnd + slideBack { return 1 - ease((phase - slide - holdAtEnd) / slideBack) }
        return 0
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
