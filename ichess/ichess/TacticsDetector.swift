//
//  TacticsDetector.swift
//  ichess
//
//  纯规则的战术识别（不调用引擎）：丢子、捉双、牵制、串打、杀棋、开局原则。
//  只返回结构化事实（Tactic），措辞和排序在 CoachExplainer。基于 ThreatAnalyzer 的静态交换（SEE）；
//  和 ThreatAnalyzer 一样不考虑牵制中的子不能动、吃过路兵，面向新手的提醒足够。
//

import ChessKit

/// 一个子：种类 + 所在格。
struct CoachTarget: Equatable {
    let kind: Piece.Kind
    let square: Square
}

enum OpeningRemark: Equatable {
    case earlyQueen
    case castle
    case develop(count: Int)
    case center
}

enum CoachMotif: Equatable {
    /// 没人保护的子被攻击。
    case hanging(victim: CoachTarget, attacker: CoachTarget)
    /// 被价值更低的子攻击（有保护，换子也亏）。
    case lesserAttacker(victim: CoachTarget, attacker: CoachTarget)
    /// 攻击的子比保护的多。
    case outnumbered(victim: CoachTarget, attacker: CoachTarget)
    /// 一个子同时攻击两个值得吃的目标（含将军）。
    case fork(attacker: CoachTarget, targets: [CoachTarget])
    /// 走一步就能捉双；不指出具体走法，只说哪种子、哪两个目标。
    case forkChance(kind: Piece.Kind, targets: [Piece.Kind])
    /// 牵制：pinned 动了，身后的 behind 就暴露（behind 是王时为绝对牵制）。
    case pin(pinned: CoachTarget, behind: CoachTarget, by: CoachTarget)
    /// 串打：前面的 front 价值更高，躲开后 behind 被吃。
    case skewer(front: CoachTarget, behind: CoachTarget, by: CoachTarget)
    /// 正在将军（side 是将军的一方）。
    case check(attackers: [CoachTarget])
    case mateInOne
    case mate(in: Int)
    case opening(OpeningRemark)
}

/// side：做这件事的一方（攻击者 / 受益者）。
struct Tactic: Equatable {
    let side: Piece.Color
    let motif: CoachMotif
}

enum TacticsDetector {
    // MARK: - 几何

    private static let knightSteps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    static func square(file: Int, rank: Int) -> Square {
        Square(rawValue: (rank - 1) * 8 + file - 1)!
    }

    static func directions(for kind: Piece.Kind) -> [(Int, Int)] {
        switch kind {
        case .rook: orthogonal
        case .bishop: diagonal
        case .queen: orthogonal + diagonal
        default: []
        }
    }

    /// 这个子当前攻击的所有格子（含被挡住前的第一个子所在格，不管颜色）。
    static func attackedSquares(by piece: Piece, in occ: Occupancy) -> [Square] {
        let file = piece.square.file.number
        let rank = piece.square.rank.value
        var result: [Square] = []
        func add(_ df: Int, _ dr: Int) {
            let f = file + df, r = rank + dr
            guard (1...8).contains(f), (1...8).contains(r) else { return }
            result.append(square(file: f, rank: r))
        }
        switch piece.kind {
        case .pawn:
            let dr = piece.color == .white ? 1 : -1
            add(-1, dr)
            add(1, dr)
        case .knight:
            for (df, dr) in knightSteps { add(df, dr) }
        case .king:
            for (df, dr) in orthogonal + diagonal { add(df, dr) }
        case .bishop, .rook, .queen:
            for (df, dr) in directions(for: piece.kind) {
                var f = file + df, r = rank + dr
                while (1...8).contains(f), (1...8).contains(r) {
                    result.append(square(file: f, rank: r))
                    if occ[f, r] != nil { break }
                    f += df
                    r += dr
                }
            }
        }
        return result
    }

    static func king(of color: Piece.Color, in position: Position) -> Piece? {
        position.pieces.first { $0.color == color && $0.kind == .king }
    }

    /// color 一方的王正被谁将军。
    static func checkers(of color: Piece.Color, in position: Position) -> [CoachTarget] {
        guard let king = king(of: color, in: position) else { return [] }
        return ThreatAnalyzer.attackers(of: king.square, by: color.opposite, in: Occupancy(position))
            .map { CoachTarget(kind: $0.kind, square: $0.square) }
    }

    // MARK: - 空着

    /// 让对方再走一步（空着）：翻转走子方，用来问“对方想干什么”。
    /// 当前走子方正被将军时空着不合法，返回 nil。
    static func nullMove(_ board: Board) -> Board? {
        let position = board.position
        guard checkers(of: position.sideToMove, in: position).isEmpty else { return nil }
        var fields = position.fen.split(separator: " ").map(String.init)
        guard fields.count >= 4 else { return nil }
        fields[1] = position.sideToMove == .white ? "b" : "w"
        fields[3] = "-"
        guard let flipped = Position(fen: fields.joined(separator: " ")) else { return nil }
        return Board(position: flipped)
    }

    /// 让 side 走子的棋盘：本来就轮到它就是原棋盘，否则尝试空着。
    static func board(for side: Piece.Color, from board: Board) -> Board? {
        board.position.sideToMove == side ? board : nullMove(board)
    }

    // MARK: - 杀棋

    /// 轮到走子的一方有没有一步杀。
    static func hasMateInOne(_ board: Board) -> Bool {
        let side = board.position.sideToMove
        for piece in board.position.pieces where piece.color == side {
            for end in board.legalMoves(forPieceAt: piece.square) {
                var next = board
                guard next.move(pieceAt: piece.square, to: end) != nil else { continue }
                if case let .promotion(pending) = next.state {
                    _ = next.completePromotion(of: pending, to: .queen)
                }
                if case .checkmate = next.state { return true }
            }
        }
        return false
    }

    // MARK: - 丢子

    /// side 一方能净赚吃掉的对方的子，按价值从大到小。
    static func materialThreats(by side: Piece.Color, in occ: Occupancy, position: Position) -> [Tactic] {
        let enemy = side.opposite
        var result: [(Int, Tactic)] = []
        for victim in position.pieces where victim.color == enemy && victim.kind != .king {
            guard ThreatAnalyzer.exchangeGain(on: victim.square, by: side, in: occ) > 0,
                  let cheapest = ThreatAnalyzer.attackers(of: victim.square, by: side, in: occ)
                      .min(by: { ThreatAnalyzer.value($0.kind) < ThreatAnalyzer.value($1.kind) }) else { continue }
            let target = CoachTarget(kind: victim.kind, square: victim.square)
            let attacker = CoachTarget(kind: cheapest.kind, square: cheapest.square)
            let motif: CoachMotif
            if ThreatAnalyzer.attackers(of: victim.square, by: enemy, in: occ).isEmpty {
                motif = .hanging(victim: target, attacker: attacker)
            } else if ThreatAnalyzer.value(cheapest.kind) < ThreatAnalyzer.value(victim.kind) {
                motif = .lesserAttacker(victim: target, attacker: attacker)
            } else {
                motif = .outnumbered(victim: target, attacker: attacker)
            }
            result.append((ThreatAnalyzer.value(victim.kind), Tactic(side: side, motif: motif)))
        }
        return result.sorted { $0.0 > $1.0 }.map(\.1)
    }

    // MARK: - 捉双

    /// piece 现在攻击的“值得吃”的目标：王，或价值 ≥ 3 且比它值钱 / 没人保护的子。按价值从大到小。
    static func forkTargets(of piece: Piece, in occ: Occupancy) -> [CoachTarget] {
        let enemy = piece.color.opposite
        var found: [CoachTarget] = []
        for target in attackedSquares(by: piece, in: occ) {
            guard let victim = occ[target], victim.color == enemy else { continue }
            let value = ThreatAnalyzer.value(victim.kind)
            let worthy = victim.kind == .king
                || (value >= 3 && (value > ThreatAnalyzer.value(piece.kind)
                    || ThreatAnalyzer.attackers(of: target, by: enemy, in: occ).isEmpty))
            if worthy { found.append(CoachTarget(kind: victim.kind, square: victim.square)) }
        }
        return found.sorted { ThreatAnalyzer.value($0.kind) > ThreatAnalyzer.value($1.kind) }
    }

    /// 至少两个目标、第二个目标不低于一个轻子，且这个子自己不会被白吃。
    private static func isFork(_ targets: [CoachTarget], piece: Piece, in occ: Occupancy) -> Bool {
        guard piece.kind != .king, targets.count >= 2,
              ThreatAnalyzer.value(targets[1].kind) >= 3 else { return false }
        return ThreatAnalyzer.exchangeGain(on: piece.square, by: piece.color.opposite, in: occ) == 0
    }

    /// 棋盘上已经存在的捉双。
    static func forks(by side: Piece.Color, in occ: Occupancy, position: Position) -> [Tactic] {
        position.pieces.filter { $0.color == side }.compactMap { piece in
            let targets = forkTargets(of: piece, in: occ)
            guard isFork(targets, piece: piece, in: occ) else { return nil }
            return Tactic(side: side, motif: .fork(attacker: CoachTarget(kind: piece.kind, square: piece.square), targets: targets))
        }
    }

    /// 轮到 side 走子的棋盘上，有没有一步能造成捉双。只返回最好的一个（王 > 第二目标价值 > 目标数）。
    static func forkChance(by side: Piece.Color, board: Board) -> Tactic? {
        guard board.position.sideToMove == side else { return nil }
        let occ = Occupancy(board.position)
        var best: (key: [Int], kind: Piece.Kind, targets: [Piece.Kind])?
        for piece in board.position.pieces where piece.color == side && piece.kind != .king {
            // 已经在捉双的子不算“机会”。
            if forkTargets(of: piece, in: occ).count >= 2 { continue }
            for end in board.legalMoves(forPieceAt: piece.square) {
                if piece.kind == .pawn, end.rank.value == 1 || end.rank.value == 8 { continue }
                var moved = occ
                moved[piece.square] = nil
                moved[end] = Piece(piece.kind, color: side, square: end)
                guard let landed = moved[end] else { continue }
                let targets = forkTargets(of: landed, in: moved)
                guard isFork(targets, piece: landed, in: moved) else { continue }
                let key = [targets[0].kind == .king ? 1 : 0, ThreatAnalyzer.value(targets[1].kind), targets.count]
                if best == nil || best!.key.lexicographicallyPrecedes(key) {
                    best = (key, piece.kind, targets.map(\.kind))
                }
            }
        }
        return best.map { Tactic(side: side, motif: .forkChance(kind: $0.kind, targets: Array($0.targets.prefix(2)))) }
    }

    // MARK: - 牵制与串打

    static func lines(by side: Piece.Color, in occ: Occupancy, position: Position) -> [Tactic] {
        let enemy = side.opposite
        var result: [Tactic] = []
        for slider in position.pieces where slider.color == side && [.bishop, .rook, .queen].contains(slider.kind) {
            // 自己会被白吃的子，牵制 / 串打都不成立。
            guard ThreatAnalyzer.exchangeGain(on: slider.square, by: enemy, in: occ) == 0 else { continue }
            let by = CoachTarget(kind: slider.kind, square: slider.square)
            for (df, dr) in directions(for: slider.kind) {
                var f = slider.square.file.number + df, r = slider.square.rank.value + dr
                var first: Piece?
                var second: Piece?
                while (1...8).contains(f), (1...8).contains(r) {
                    if let piece = occ[f, r] {
                        if first == nil { first = piece } else { second = piece; break }
                        if piece.color != enemy { break }
                    }
                    f += df
                    r += dr
                }
                guard let front = first, let behind = second, front.color == enemy, behind.color == enemy else { continue }
                let vf = ThreatAnalyzer.value(front.kind), vb = ThreatAnalyzer.value(behind.kind)
                let frontT = CoachTarget(kind: front.kind, square: front.square)
                let behindT = CoachTarget(kind: behind.kind, square: behind.square)
                if behind.kind == .king, front.kind != .pawn {
                    result.append(Tactic(side: side, motif: .pin(pinned: frontT, behind: behindT, by: by)))
                } else if front.kind == .king || (vf > vb && vb >= 3) {
                    // 躲开之后要吃得到：身后的子没人保护，或比我这个子更值钱。
                    let defended = !ThreatAnalyzer.attackers(of: behind.square, by: enemy, in: occ).isEmpty
                    if behind.kind != .pawn, behind.kind != .king, vb >= 3, !defended || ThreatAnalyzer.value(slider.kind) < vb {
                        result.append(Tactic(side: side, motif: .skewer(front: frontT, behind: behindT, by: by)))
                    }
                } else if front.kind != .pawn, vb > vf, vb >= 5 {
                    result.append(Tactic(side: side, motif: .pin(pinned: frontT, behind: behindT, by: by)))
                }
            }
        }
        return result
    }

    /// 棋盘上已存在的静态战术：丢子、捉双、牵制 / 串打。
    static func staticTactics(by side: Piece.Color, in position: Position) -> [Tactic] {
        let occ = Occupancy(position)
        return materialThreats(by: side, in: occ, position: position)
            + forks(by: side, in: occ, position: position)
            + lines(by: side, in: occ, position: position)
    }

    // MARK: - 开局原则

    /// 只说 color 自己的事，前 10 回合内；至少走过两步才开始提醒（起始局面和 1.e4 e5 之后不提）。
    static func openingRemarks(for color: Piece.Color, in position: Position) -> [Tactic] {
        let fullmoves = position.clock.fullmoves
        guard (3...10).contains(fullmoves) else { return [] }
        let rank = color == .white ? 1 : 8
        let home = ["b", "g", "c", "f"].map { Square("\($0)\(rank)") }
        let undeveloped = home.filter { square in
            guard let piece = position.piece(at: square) else { return false }
            return piece.color == color && (piece.kind == .knight || piece.kind == .bishop)
        }.count
        var remarks: [OpeningRemark] = []

        if let queen = position.pieces.first(where: { $0.color == color && $0.kind == .queen }),
           queen.square != Square("d\(rank)"), fullmoves <= 6, undeveloped >= 2 {
            remarks.append(.earlyQueen)
        }
        let rights = position.fen.split(separator: " ").dropFirst(2).first.map(String.init) ?? "-"
        let letters = color == .white ? "KQ" : "kq"
        if let king = king(of: color, in: position), king.square == Square("e\(rank)"),
           rights.contains(where: { letters.contains($0) }), fullmoves >= 5 {
            remarks.append(.castle)
        }
        // 越往后越该出子：第 3 回合要 4 个都没动才提，第 5 回合起剩 2 个就提。
        if undeveloped >= max(2, 7 - fullmoves) { remarks.append(.develop(count: undeveloped)) }
        let centerFiles = ["d", "e"], centerRanks = [4, 5]
        let hasCenterPawn = position.pieces.contains { piece in
            piece.color == color && piece.kind == .pawn
                && centerFiles.contains(piece.square.file.rawValue) && centerRanks.contains(piece.square.rank.value)
        }
        if !hasCenterPawn, fullmoves <= 6 { remarks.append(.center) }
        return remarks.map { Tactic(side: color, motif: .opening($0)) }
    }
}
