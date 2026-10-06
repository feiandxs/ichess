//
//  MoveRecord.swift
//  ichess
//

import ChessKit

/// 一步棋的记录；fen 是走完这一步后的局面。
nonisolated struct MoveRecord: Codable, Equatable, Sendable {
    var from: String
    var to: String
    /// 升变后的棋子，小写 UCI 字母（q r b n）。
    var promotion: String?
    var san: String?
    var fen: String
    /// 引擎对走完这一步后的局面的评估（走子方为对手视角）；还没分析为 nil，旧存档也没有。
    var eval: PositionEval?

    init(from: String, to: String, promotion: String? = nil, san: String? = nil, fen: String, eval: PositionEval? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.san = san
        self.fen = fen
        self.eval = eval
    }

    init(move: Move, fen: String) {
        self.init(
            from: move.start.notation,
            to: move.end.notation,
            promotion: move.promotedPiece.map { $0.kind.rawValue.lowercased() },
            san: move.san,
            fen: fen
        )
    }

    /// UCI 写法，如 e2e4、e7e8q；旧存档里还原失败的记录为空串。
    var uci: String { from + to + (promotion ?? "") }
}
