//
//  ThreatAnalyzer.swift
//  ichess
//

import ChessKit

/// 纯规则的丢子判断（不调用引擎）：用静态交换（SEE）估算对方吃某个子能净赚多少。
/// 不考虑牵制、吃过路兵和将军，面向新手的“这个子会不会白丢”提示足够。
enum ThreatAnalyzer {
    struct Danger: Equatable {
        let square: Square
        let kind: Piece.Kind
        /// 对方吃这个子的净收益（兵 = 1）。
        let loss: Int
    }

    struct MoveRisk: Equatable {
        /// 走完后会丢掉的子（可能是走动的子本身，也可能是因此失去保护的其他子）。
        let danger: Danger
        /// 扣除这步吃到的子之后的净亏损。
        let netLoss: Int
    }

    /// `color` 一方当前会被对方净赚吃掉的子，按损失从大到小排列。王不计入。
    static func dangers(for color: Piece.Color, in position: Position) -> [Danger] {
        let occupancy = Occupancy(position)
        return position.pieces
            .filter { $0.color == color && $0.kind != .king }
            .compactMap { piece in
                let loss = exchangeGain(on: piece.square, by: color.opposite, in: occupancy)
                return loss > 0 ? Danger(square: piece.square, kind: piece.kind, loss: loss) : nil
            }
            .sorted { $0.loss > $1.loss }
    }

    /// 从 `start` 走到 `end` 是否会让走子方净亏子。返回最严重的一处；不亏返回 nil。
    static func risk(of board: Board, from start: Square, to end: Square) -> MoveRisk? {
        guard let mover = board.position.piece(at: start) else { return nil }
        let captured = board.position.piece(at: end).map { value($0.kind) } ?? 0
        let before = Dictionary(
            dangers(for: mover.color, in: board.position).map { ($0.square, $0.loss) },
            uniquingKeysWith: max
        )

        var next = board
        guard next.move(pieceAt: start, to: end) != nil else { return nil }
        if case let .promotion(pending) = next.state {
            next.completePromotion(of: pending, to: .queen)
        }
        // 走完就将死对方时不算风险。
        if case .checkmate = next.state { return nil }

        // 原本就挂着、这步也没让它更糟的子不重复算在这步头上。
        let worst = dangers(for: mover.color, in: next.position).first { danger in
            danger.square == end || danger.loss > (before[danger.square] ?? 0)
        }
        guard let worst, worst.loss > captured else { return nil }
        return MoveRisk(danger: worst, netLoss: worst.loss - captured)
    }

    static func value(_ kind: Piece.Kind) -> Int {
        switch kind {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        // 足够大，让“王吃进有保护的格子”在交换中永远不划算。
        case .king: 100
        }
    }

    // MARK: - Static exchange

    /// `attacker` 一方从吃掉 `target` 上的子开始、双方轮流用最小价值的子互吃，最终能净赚多少。
    /// 每一步都可以选择不吃，所以结果不小于 0。
    static func exchangeGain(on target: Square, by attacker: Piece.Color, in occupancy: Occupancy) -> Int {
        var board = occupancy
        guard var victim = board[target] else { return 0 }
        var side = attacker
        var gains: [Int] = []
        while let capturer = cheapestAttacker(of: target, by: side, in: board) {
            gains.append(value(victim.kind))
            if victim.kind == .king { break }
            board[capturer.square] = nil
            victim = capturer
            board[target] = capturer
            side = side.opposite
        }
        return gains.reversed().reduce(0) { max(0, $1 - $0) }
    }

    private static func cheapestAttacker(of target: Square, by color: Piece.Color, in board: Occupancy) -> Piece? {
        attackers(of: target, by: color, in: board).min { value($0.kind) < value($1.kind) }
    }

    static func attackers(of target: Square, by color: Piece.Color, in board: Occupancy) -> [Piece] {
        let file = target.file.number
        let rank = target.rank.value
        var result: [Piece] = []

        func add(_ df: Int, _ dr: Int, kinds: Set<Piece.Kind>) {
            if let piece = board[file + df, rank + dr], piece.color == color, kinds.contains(piece.kind) {
                result.append(piece)
            }
        }

        // 白兵从下方斜吃上来，黑兵从上方斜吃下来。
        let pawnRank = color == .white ? -1 : 1
        add(-1, pawnRank, kinds: [.pawn])
        add(1, pawnRank, kinds: [.pawn])

        for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)] {
            add(df, dr, kinds: [.knight])
        }
        for df in -1...1 {
            for dr in -1...1 where df != 0 || dr != 0 {
                add(df, dr, kinds: [.king])
            }
        }

        let rays: [((Int, Int), Set<Piece.Kind>)] = [
            ((1, 0), [.rook, .queen]), ((-1, 0), [.rook, .queen]),
            ((0, 1), [.rook, .queen]), ((0, -1), [.rook, .queen]),
            ((1, 1), [.bishop, .queen]), ((1, -1), [.bishop, .queen]),
            ((-1, 1), [.bishop, .queen]), ((-1, -1), [.bishop, .queen]),
        ]
        for ((df, dr), kinds) in rays {
            var f = file + df
            var r = rank + dr
            while (1...8).contains(f), (1...8).contains(r) {
                if let piece = board[f, r] {
                    if piece.color == color, kinds.contains(piece.kind) { result.append(piece) }
                    break
                }
                f += df
                r += dr
            }
        }
        return result
    }
}

/// 按格子索引的棋子表，交换计算中可直接增删。
struct Occupancy {
    private var squares: [Piece?] = Array(repeating: nil, count: 64)

    init(_ position: Position) {
        for piece in position.pieces {
            squares[piece.square.rawValue] = piece
        }
    }

    subscript(square: Square) -> Piece? {
        get { squares[square.rawValue] }
        set {
            var piece = newValue
            piece?.square = square
            squares[square.rawValue] = piece
        }
    }

    /// file / rank 均为 1...8，越界返回 nil。
    subscript(file: Int, rank: Int) -> Piece? {
        guard (1...8).contains(file), (1...8).contains(rank) else { return nil }
        return squares[(rank - 1) * 8 + file - 1]
    }
}
