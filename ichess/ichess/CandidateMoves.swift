//
//  CandidateMoves.swift
//  ichess
//
//  前三名候选走法的对比：引擎的 MultiPV 结果 → 每步的 SAN、走后胜率、相对最佳的评价、一句话原因，
//  以及逐步的变例（每一步的走法、SAN 和走完的局面），后面的分步演示可以直接拿去播放。
//  纯逻辑，不碰引擎和界面。
//

import ChessKit
import Foundation

/// 变例里的一步：走法、SAN、走完的局面（演示时逐步推进用）。
struct CandidateStep: Equatable {
    let uci: String
    let san: String
    let from: Square
    let to: Square
    let color: Piece.Color
    let piece: Piece.Kind
    let captured: Piece.Kind?
    let givesCheck: Bool
    /// 走完这一步的局面。
    let fen: String
}

enum CandidateLabel: Equatable {
    case best, alsoGood, weaker

    var title: String {
        switch self {
        case .best: String(localized: "Best", bundle: .localized)
        case .alsoGood: String(localized: "Also fine", bundle: .localized)
        case .weaker: String(localized: "Weaker", bundle: .localized)
        }
    }

    /// 配色借用走后点评的评级颜色。
    var verdict: MoveVerdict {
        switch self {
        case .best: .best
        case .alsoGood: .good
        case .weaker: .mistake
        }
    }
}

/// 前几名走法拉开多少：只有一步好 / 好几步都行 / 第一名略好。
enum CandidateVerdict: Equatable {
    case onlyMove, severalGood, bestAhead
}

struct CandidateMove: Equatable, Identifiable {
    /// 1 = 最佳。
    let rank: Int
    let uci: String
    let san: String
    let from: Square
    let to: Square
    /// 玩家视角的评分和走完这步的胜率（0...100）。
    let score: EngineScore
    let winPercent: Double
    /// 比最佳少多少胜率（百分点，最佳为 0）。
    let winDrop: Double
    let label: CandidateLabel
    /// 这步做成的事，最重要的在前。
    let motifs: [MoveMotif]
    /// 走了会亏子时的说明（较差的步才用来当理由）。
    let drawback: FeedbackReason?
    /// 引擎变例，一步一步。
    let line: [CandidateStep]

    var id: String { uci }

    /// 一行理由：较差的走法优先说它的毛病，其余说它做成了什么。
    func reason(mover: Piece.Color) -> String {
        if label == .weaker, let drawback { return drawback.text }
        return MoveWhy.text(for: motifs.first ?? .solid, mover: mover)
    }
}

struct CandidateSet: Equatable {
    /// 候选所在的局面（走子的是玩家）。
    let fen: String
    let mover: Piece.Color
    let candidates: [CandidateMove]
    let verdict: CandidateVerdict

    /// 第一名比第二名好这么多（胜率百分点）以上，就是「只有这一步」。
    static let onlyMoveGap = 10.0
    /// 第二名只差这么点以内，就是「好几步都行」。
    static let severalGoodGap = 3.0
    /// 比最佳少这么多以内算「也不错」，再差就是「较差」；和走后点评的「不够精确」同一条线。
    static let alsoGoodGap = MoveClassifier.inaccuracyDrop

    static func label(rank: Int, drop: Double) -> CandidateLabel {
        if rank == 1 { return .best }
        return drop < alsoGoodGap ? .alsoGood : .weaker
    }

    /// 按胜率差分类；只有一步合法棋也算「只有这一步」。
    static func verdict(winPercents: [Double]) -> CandidateVerdict {
        guard winPercents.count >= 2 else { return .onlyMove }
        let gap = winPercents[0] - winPercents[1]
        if gap >= onlyMoveGap { return .onlyMove }
        if gap <= severalGoodGap { return .severalGood }
        return .bestAhead
    }

    /// 按走后胜率从高到低排；preferred（提示给的着法）和最高的差在「好几步都行」以内时放第一，
    /// 这样提示的箭头和列表的第一名一致。
    static func ordered(lines: [EngineLine], preferred: String?) -> [EngineLine] {
        var sorted = lines.enumerated()
            .sorted {
                let a = MoveClassifier.winPercent($0.element.score), b = MoveClassifier.winPercent($1.element.score)
                return a != b ? a > b : $0.offset < $1.offset
            }
            .map(\.element)
        if let preferred, let index = sorted.firstIndex(where: { $0.pv.first == preferred }), index > 0,
           MoveClassifier.winPercent(sorted[0].score) - MoveClassifier.winPercent(sorted[index].score) <= severalGoodGap {
            sorted.insert(sorted.remove(at: index), at: 0)
        }
        return sorted
    }

    /// 变例一步步走出来；遇到走不通的就停。
    static func steps(pv: [String], from board: Board, limit: Int = 8) -> [CandidateStep] {
        var current = board
        var result: [CandidateStep] = []
        for uci in pv.prefix(limit) {
            guard let applied = MoveExplainer.apply(uci: uci, on: current) else { break }
            let move = applied.final
            var captured: Piece.Kind?
            if case let .capture(piece) = move.result { captured = piece.kind }
            result.append(CandidateStep(
                uci: uci, san: move.san, from: move.start, to: move.end,
                color: move.piece.color, piece: move.piece.kind, captured: captured,
                givesCheck: move.checkState != .none, fen: applied.board.position.fen
            ))
            current = applied.board
        }
        return result
    }

    static func make(board: Board, lines: [EngineLine], preferred: String? = nil) -> CandidateSet? {
        let mover = board.position.sideToMove
        let ranked = ordered(lines: lines, preferred: preferred)
        guard let top = ranked.first else { return nil }
        let topWin = MoveClassifier.winPercent(top.score)
        var result: [CandidateMove] = []
        for (index, line) in ranked.prefix(3).enumerated() {
            guard let uci = line.pv.first, let applied = MoveExplainer.apply(uci: uci, on: board) else { continue }
            let win = MoveClassifier.winPercent(line.score)
            let drop = max(0, topWin - win)
            let rank = index + 1
            let risk = ThreatAnalyzer.risk(of: board, from: applied.played.start, to: applied.played.end)
            result.append(CandidateMove(
                rank: rank, uci: uci, san: applied.final.san,
                from: applied.played.start, to: applied.played.end,
                score: line.score, winPercent: win, winDrop: drop,
                label: label(rank: rank, drop: drop),
                motifs: MoveWhy.motifs(board: board, uci: uci),
                drawback: risk.map { .losesPiece($0.danger.kind) },
                line: steps(pv: line.pv, from: board)
            ))
        }
        guard !result.isEmpty else { return nil }
        return CandidateSet(
            fen: board.position.fen, mover: mover, candidates: result,
            verdict: verdict(winPercents: result.map(\.winPercent))
        )
    }
}
