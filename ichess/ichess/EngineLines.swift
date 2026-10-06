//
//  EngineLines.swift
//  ichess
//
//  MultiPV 搜索的 info 累积：每个 multipv 序号只留最深、且在本局面上合法的变例。
//  纯逻辑（只依赖 ChessKit），方便单独测试；EngineAnalysisBuilder 把解析好的字段交给它。
//

import ChessKit

nonisolated struct EngineLineAccumulator {
    private let root: Board?
    private var best: [Int: EngineLine] = [:]

    init(fen: String? = nil) {
        root = fen.flatMap { Position(fen: $0) }.map { Board(position: $0) }
    }

    /// pv 的前几步在根局面上依次合法；没有 fen 时不校验。
    /// 旧搜索迟到的 info 变例在新局面上走不通，靠这个丢掉。
    func isLegal(_ pv: [String]) -> Bool {
        guard var board = root else { return true }
        for uci in pv.prefix(6) {
            guard let parsed = EngineLANParser.parse(move: uci, for: board.position.sideToMove, in: board.position),
                  board.position.piece(at: parsed.start)?.color == board.position.sideToMove,
                  board.legalMoves(forPieceAt: parsed.start).contains(parsed.end),
                  board.move(pieceAt: parsed.start, to: parsed.end) != nil else { return false }
            if case let .promotion(pending) = board.state {
                _ = board.completePromotion(of: pending, to: parsed.promotedPiece?.kind ?? .queen)
            }
        }
        return true
    }

    /// 收下返回 true；变例不合法，或比这个序号已有的更浅，丢弃返回 false。
    @discardableResult
    mutating func add(multipv: Int, depth: Int, score: EngineScore, pv: [String]) -> Bool {
        guard multipv >= 1, !pv.isEmpty, isLegal(pv) else { return false }
        if let old = best[multipv], depth < old.depth { return false }
        best[multipv] = EngineLine(multipv: multipv, score: score, pv: pv, depth: depth)
        return true
    }

    /// 按序号排好的各条线；首着重复的（旧信息混进来）只留序号靠前的。
    var lines: [EngineLine] {
        var seen: Set<String> = []
        return best.values.sorted { $0.multipv < $1.multipv }.filter { line in
            guard let first = line.pv.first else { return false }
            return seen.insert(first).inserted
        }
    }
}
