//
//  EngineScore.swift
//  ichess
//
//  引擎结果的纯数据类型（不依赖引擎库，方便单独测试）。
//

/// 引擎评分，始终以「当前走子方」为视角（UCI 约定），不是白方视角。
nonisolated enum EngineScore: Sendable, Equatable {
    /// 百分兵值；正数表示走子方占优。
    case centipawns(Int)
    /// 杀棋步数；正数表示走子方 N 步内将死对方，负数表示走子方会被将死。
    case mate(Int)

    /// 换成对手视角。
    var flipped: EngineScore {
        switch self {
        case let .centipawns(cp): .centipawns(-cp)
        case let .mate(n): .mate(-n)
        }
    }
}

/// 一次搜索的结果。
nonisolated struct EngineAnalysis: Sendable, Equatable {
    /// 引擎最终选的着法（UCI/LAN，如 e2e4、e7e8q）。
    let bestMove: String
    /// 评分，视角见 `EngineScore`；引擎没给出时为 nil。
    let score: EngineScore?
    /// 主变例（UCI 着法列表，第一步通常就是 bestMove）。
    /// 限制棋力（UCI_LimitStrength）时 bestMove 可能与 pv 第一步不同，此时评分对应的是 pv。
    let pv: [String]
    let depth: Int
}
