//
//  SimpleChessEngine.swift
//  ichess
//
//  Lightweight search opponent. Stockfish can replace this later.
//

import ChessKit

struct EngineMove: Sendable {
    let from: Square
    let to: Square
    let promotion: Piece.Kind?
}

enum SimpleChessEngine {
    /// Beginner-friendly: shallow search plus a bit of noise among near-best moves.
    static func chooseMove(on board: Board, depth: Int = 2, noiseWindow: Int = 40) -> EngineMove? {
        let side = board.position.sideToMove
        let moves = allMoves(on: board)
        guard !moves.isEmpty else { return nil }

        var scored: [(EngineMove, Int)] = []
        scored.reserveCapacity(moves.count)
        for move in moves {
            var child = apply(move, to: board)
            let score = -negamax(board: &child, depth: max(1, depth) - 1, alpha: -30_000, beta: 30_000, side: side.opposite)
            scored.append((move, score))
        }
        scored.sort { $0.1 > $1.1 }
        if noiseWindow <= 0 { return scored[0].0 }
        let best = scored[0].1
        let near = scored.filter { best - $0.1 <= noiseWindow }
        return near.randomElement()?.0 ?? scored[0].0
    }

    private static func negamax(board: inout Board, depth: Int, alpha: Int, beta: Int, side: Piece.Color) -> Int {
        switch board.state {
        case .checkmate(let color):
            return color == side ? -20_000 - depth : 20_000 + depth
        case .draw:
            return 0
        default:
            break
        }
        if depth == 0 { return evaluate(board, side: side) }

        var alpha = alpha
        let moves = allMoves(on: board)
        if moves.isEmpty { return evaluate(board, side: side) }

        var best = -30_000
        for move in moves {
            var child = apply(move, to: board)
            let score = -negamax(board: &child, depth: depth - 1, alpha: -beta, beta: -alpha, side: side.opposite)
            best = max(best, score)
            alpha = max(alpha, score)
            if alpha >= beta { break }
        }
        return best
    }

    private static func allMoves(on board: Board) -> [EngineMove] {
        let side = board.position.sideToMove
        var result: [EngineMove] = []
        for piece in board.position.pieces where piece.color == side {
            for dest in board.legalMoves(forPieceAt: piece.square) {
                let isPromo = piece.kind == .pawn && (dest.rank.value == 8 || dest.rank.value == 1)
                if isPromo {
                    result.append(EngineMove(from: piece.square, to: dest, promotion: .queen))
                } else {
                    result.append(EngineMove(from: piece.square, to: dest, promotion: nil))
                }
            }
        }
        return result
    }

    private static func apply(_ move: EngineMove, to board: Board) -> Board {
        var next = board
        _ = next.move(pieceAt: move.from, to: move.to)
        if case let .promotion(pending) = next.state {
            next.completePromotion(of: pending, to: move.promotion ?? .queen)
        }
        return next
    }

    private static func evaluate(_ board: Board, side: Piece.Color) -> Int {
        var total = 0
        for piece in board.position.pieces {
            let value = material(piece.kind) + pst(piece)
            total += piece.color == side ? value : -value
        }
        return total
    }

    private static func material(_ kind: Piece.Kind) -> Int {
        switch kind {
        case .pawn: 100
        case .knight: 320
        case .bishop: 330
        case .rook: 500
        case .queen: 900
        case .king: 0
        }
    }

    private static func pst(_ piece: Piece) -> Int {
        let file = piece.square.file.number - 1
        let rank = piece.square.rank.value
        // Tables are stored a8→h1 (rank 8 first), matching common PST layouts.
        let idx = piece.color == .white
            ? (8 - rank) * 8 + file
            : (rank - 1) * 8 + file
        switch piece.kind {
        case .pawn: return pawnPST[idx]
        case .knight: return knightPST[idx]
        case .bishop: return bishopPST[idx]
        case .rook: return rookPST[idx]
        case .queen: return queenPST[idx]
        case .king: return kingPST[idx]
        }
    }
}

private let pawnPST: [Int] = [
    0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
    5,  5, 10, 25, 25, 10,  5,  5,
    0,  0,  0, 20, 20,  0,  0,  0,
    5, -5,-10,  0,  0,-10, -5,  5,
    5, 10, 10,-20,-20, 10, 10,  5,
    0,  0,  0,  0,  0,  0,  0,  0,
]
private let knightPST: [Int] = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50,
]
private let bishopPST: [Int] = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20,
]
private let rookPST: [Int] = [
    0,  0,  0,  0,  0,  0,  0,  0,
    5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    0,  0,  0,  5,  5,  0,  0,  0,
]
private let queenPST: [Int] = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20,
]
private let kingPST: [Int] = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20,
]
