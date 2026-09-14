//
//  ChessGameStore.swift
//  ichess
//

import ChessKit
import Combine
import SwiftUI

struct PlayedMove: Equatable, Identifiable {
    let id: UUID
    let from: Square
    let to: Square
    let piece: Piece
    let captured: Piece?

    var isKnight: Bool { piece.kind == .knight }
}

@MainActor
final class ChessGameStore: ObservableObject {
    @Published private(set) var board = Board()
    @Published var selected: Square?
    @Published private(set) var lastPlayed: PlayedMove?
    @Published private(set) var hint: (Square, Square)?
    @Published private(set) var isEngineThinking = false
    @Published private(set) var rating = Strength.defaultRating
    @Published private(set) var winStreak = 0
    @Published private(set) var lossStreak = 0
    @Published private(set) var lastRatingDelta = 0
    @Published private(set) var recentResults: [GameResult] = []

    let playerColor: Piece.Color = .white
    /// Restored games should not replay the last move animation.
    private(set) var shouldAnimateLastMove = false
    private var history: [Board] = []
    private var engineTask: Task<Void, Never>?
    private var hasRatedThisGame = false

    var lastMove: (Square, Square)? {
        lastPlayed.map { ($0.from, $0.to) }
    }

    var sideToMove: Piece.Color { board.position.sideToMove }
    var legalTargets: Set<Square> {
        guard let selected, !isEngineThinking else { return [] }
        return Set(board.legalMoves(forPieceAt: selected))
    }

    var canUndo: Bool { !history.isEmpty }
    var canHint: Bool {
        !isEngineThinking && !isGameOver && pendingPromotion == nil && sideToMove == playerColor
    }

    var isGameOver: Bool {
        outcome != nil
    }

    var outcome: GameOutcome? {
        switch board.state {
        case .checkmate(let color):
            return color == playerColor ? .loss : .win
        case .draw(let reason):
            let text: String
            switch reason {
            case .stalemate: text = "无子可动"
            case .repetition: text = "三次重复"
            case .fiftyMoves: text = "五十步规则"
            case .insufficientMaterial: text = "子力不足"
            case .agreement: text = "双方同意"
            }
            return .draw(text)
        default:
            return nil
        }
    }

    var pendingPromotion: Move? {
        if case let .promotion(move) = board.state { return move }
        return nil
    }

    var ratingLine: String {
        if lastRatingDelta > 0 { return "\(rating)  +\(lastRatingDelta)" }
        if lastRatingDelta < 0 { return "\(rating)  \(lastRatingDelta)" }
        return "\(rating)"
    }

    var streakLine: String {
        if winStreak > 0 { return "连胜 \(winStreak)" }
        if lossStreak > 0 { return "连败 \(lossStreak)" }
        return "超级新手"
    }

    var recentLine: String {
        recentResults.suffix(8).map(\.mark).joined(separator: " ")
    }

    init() {
        let stats = Strength.load()
        rating = stats.rating
        winStreak = stats.winStreak
        lossStreak = stats.lossStreak
        lastRatingDelta = stats.lastDelta
        recentResults = stats.recent
        restore()
    }

    var statusText: String {
        if isEngineThinking { return "对方思考中" }
        switch board.state {
        case .active:
            return sideToMove == playerColor ? "轮到你了" : "对方走"
        case .check(let color):
            return color == playerColor ? "你被将军" : "对方被将军"
        case .checkmate(let color):
            return color == playerColor ? "将死 · 你输了" : "将死 · 你赢了"
        case .draw(let reason):
            switch reason {
            case .stalemate: return "和棋 · 无子可动"
            case .repetition: return "和棋 · 三次重复"
            case .fiftyMoves: return "和棋 · 五十步"
            case .insufficientMaterial: return "和棋 · 子力不足"
            case .agreement: return "和棋"
            }
        case .promotion:
            return "选择升变"
        }
    }

    func piece(at square: Square) -> Piece? {
        board.position.piece(at: square)
    }

    func tap(_ square: Square) {
        if pendingPromotion != nil || isGameOver || isEngineThinking { return }
        guard sideToMove == playerColor else { return }
        hint = nil

        if let selected, legalTargets.contains(square) {
            play(from: selected, to: square)
            return
        }

        if let piece = piece(at: square), piece.color == playerColor {
            self.selected = self.selected == square ? nil : square
            return
        }

        selected = nil
    }

    func completePromotion(to kind: Piece.Kind) {
        guard let move = pendingPromotion else { return }
        var next = board
        next.completePromotion(of: move, to: kind)
        board = next
        selected = nil
        persist()
        finishGameIfNeeded()
        requestEngineMoveIfNeeded()
    }

    func showHint() {
        guard canHint else { return }
        let snapshot = board
        let strength = Strength.snapshot(rating)
        if let move = SimpleChessEngine.chooseMove(on: snapshot, depth: strength.depth, noiseWindow: 0) {
            hint = (move.from, move.to)
            selected = nil
        }
    }

    func undo() {
        cancelEngine()
        hint = nil
        guard !history.isEmpty else { return }
        if sideToMove == playerColor, history.count >= 2 {
            history.removeLast()
            board = history.removeLast()
        } else if let previous = history.popLast() {
            board = previous
        }
        selected = nil
        lastPlayed = nil
        persist()
    }

    func restart() {
        cancelEngine()
        board = Board()
        history = []
        selected = nil
        lastPlayed = nil
        hint = nil
        isEngineThinking = false
        hasRatedThisGame = false
        persist()
    }

    func resumeIfNeeded() {
        requestEngineMoveIfNeeded()
    }

    func persistNow() {
        persist()
    }

    private func play(from start: Square, to end: Square) {
        var next = board
        guard let played = next.move(pieceAt: start, to: end) else { return }
        history.append(board)
        board = next
        selected = nil
        shouldAnimateLastMove = true
        lastPlayed = PlayedMove(from: played)
        persist()
        finishGameIfNeeded()
        if pendingPromotion == nil {
            requestEngineMoveIfNeeded()
        }
    }

    private func requestEngineMoveIfNeeded() {
        guard !isEngineThinking else { return }
        guard !isGameOver, pendingPromotion == nil, sideToMove != playerColor else { return }
        isEngineThinking = true
        selected = nil
        hint = nil
        let snapshot = board
        let strength = Strength.snapshot(rating)
        engineTask = Task { [weak self] in
            async let chosen = Task.detached(priority: .userInitiated) {
                SimpleChessEngine.chooseMove(on: snapshot, depth: strength.depth, noiseWindow: strength.noiseWindow)
            }.value
            try? await Task.sleep(for: .milliseconds(420))
            let move = await chosen
            guard let self, !Task.isCancelled else { return }
            self.applyEngineMove(move)
        }
    }

    private func applyEngineMove(_ move: EngineMove?) {
        isEngineThinking = false
        guard let move, !isGameOver, sideToMove != playerColor else { return }
        var next = board
        guard let played = next.move(pieceAt: move.from, to: move.to) else { return }
        if case let .promotion(pending) = next.state {
            next.completePromotion(of: pending, to: move.promotion ?? .queen)
        }
        history.append(board)
        board = next
        shouldAnimateLastMove = true
        lastPlayed = PlayedMove(from: played)
        persist()
        finishGameIfNeeded()
    }

    private func persist() {
        let snapshot = SavedGame(
            fen: board.position.fen,
            history: history.map(\.position.fen),
            lastFrom: lastPlayed.map { $0.from.notation },
            lastTo: lastPlayed.map { $0.to.notation },
            hasRatedThisGame: hasRatedThisGame
        )
        SavedGame.save(snapshot)
    }

    private func restore() {
        guard let saved = SavedGame.load() else { return }
        guard let position = Position(fen: saved.fen) else { return }
        board = Board(position: position)
        history = saved.history.compactMap { fen in
            guard let pos = Position(fen: fen) else { return nil }
            return Board(position: pos)
        }
        if let from = saved.lastFrom, let to = saved.lastTo,
           let piece = board.position.piece(at: Square(to)) {
            shouldAnimateLastMove = false
            lastPlayed = PlayedMove(
                id: UUID(),
                from: Square(from),
                to: Square(to),
                piece: piece,
                captured: nil
            )
        }
        hasRatedThisGame = saved.hasRatedThisGame ?? false
        finishGameIfNeeded()
    }

    private func finishGameIfNeeded() {
        guard isGameOver, !hasRatedThisGame else { return }
        hasRatedThisGame = true
        let result: GameResult
        switch board.state {
        case .checkmate(let color):
            result = color == playerColor ? .loss : .win
        case .draw:
            result = .draw
        default:
            return
        }
        apply(result)
        persist()
    }

    private func apply(_ result: GameResult) {
        recentResults.append(result)
        if recentResults.count > 12 {
            recentResults.removeFirst(recentResults.count - 12)
        }
        switch result {
        case .win:
            winStreak += 1
            lossStreak = 0
            lastRatingDelta = min(28, 8 + (winStreak - 1) * 4)
        case .loss:
            lossStreak += 1
            winStreak = 0
            lastRatingDelta = lossStreak >= 3 ? -(8 + (lossStreak - 3) * 4) : 0
        case .draw:
            winStreak = 0
            lastRatingDelta = 0
        }
        rating = min(Strength.maxRating, max(Strength.minRating, rating + lastRatingDelta))
        Strength.save(
            rating: rating,
            winStreak: winStreak,
            lossStreak: lossStreak,
            lastDelta: lastRatingDelta,
            recent: recentResults
        )
    }

    private func cancelEngine() {
        engineTask?.cancel()
        engineTask = nil
        isEngineThinking = false
    }
}

extension PlayedMove {
    init(from move: Move) {
        var captured: Piece?
        if case let .capture(piece) = move.result {
            captured = piece
        }
        self.init(
            id: UUID(),
            from: move.start,
            to: move.end,
            piece: move.promotedPiece ?? move.piece,
            captured: captured
        )
    }
}

private struct SavedGame: Codable {
    var fen: String
    var history: [String]
    var lastFrom: String?
    var lastTo: String?
    var hasRatedThisGame: Bool?

    private static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = folder.appendingPathComponent("ichess", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("saved-game.json")
    }

    static func load() -> SavedGame? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedGame.self, from: data)
    }

    static func save(_ game: SavedGame) {
        guard let data = try? JSONEncoder().encode(game) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension Square {
    static func at(row: Int, col: Int) -> Square {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        return Square("\(files[col])\(8 - row)")
    }

    var notation: String { "\(file.rawValue)\(rank.value)" }
    var row: Int { 8 - rank.value }
    var col: Int { file.number - 1 }
}

extension Piece.Kind {
    var assetKind: PieceKind {
        switch self {
        case .pawn: .pawn
        case .knight: .knight
        case .bishop: .bishop
        case .rook: .rook
        case .queen: .queen
        case .king: .king
        }
    }
}

extension Piece.Color {
    var side: SideColor { self == .white ? .white : .black }
}

enum GameResult: String, Codable {
    case win, loss, draw

    var mark: String {
        switch self {
        case .win: "胜"
        case .loss: "负"
        case .draw: "和"
        }
    }
}

enum Strength {
    static let defaultRating = 600
    static let minRating = 400
    static let maxRating = 1800

    struct Snapshot {
        var depth: Int
        var noiseWindow: Int
    }

    static func snapshot(_ rating: Int) -> Snapshot {
        let depth: Int
        switch rating {
        case ..<650: depth = 1
        case ..<950: depth = 2
        case ..<1250: depth = 3
        default: depth = 4
        }
        let noise: Int
        switch rating {
        case ..<650: noise = 90
        case ..<800: noise = 55
        case ..<1000: noise = 35
        case ..<1200: noise = 18
        default: noise = 0
        }
        return Snapshot(depth: depth, noiseWindow: noise)
    }

    private static let ratingKey = "ichess.rating"
    private static let winKey = "ichess.winStreak"
    private static let lossKey = "ichess.lossStreak"
    private static let deltaKey = "ichess.lastRatingDelta"
    private static let recentKey = "ichess.recentResults"

    struct Stats {
        var rating: Int
        var winStreak: Int
        var lossStreak: Int
        var lastDelta: Int
        var recent: [GameResult]
    }

    static func load() -> Stats {
        let defaults = UserDefaults.standard
        let rating = defaults.object(forKey: ratingKey) == nil
            ? defaultRating
            : defaults.integer(forKey: ratingKey)
        var recent: [GameResult] = []
        if let data = defaults.data(forKey: recentKey) {
            recent = (try? JSONDecoder().decode([GameResult].self, from: data)) ?? []
        }
        return Stats(
            rating: rating,
            winStreak: defaults.integer(forKey: winKey),
            lossStreak: defaults.integer(forKey: lossKey),
            lastDelta: defaults.integer(forKey: deltaKey),
            recent: recent
        )
    }

    static func save(
        rating: Int,
        winStreak: Int,
        lossStreak: Int,
        lastDelta: Int,
        recent: [GameResult]
    ) {
        let defaults = UserDefaults.standard
        defaults.set(rating, forKey: ratingKey)
        defaults.set(winStreak, forKey: winKey)
        defaults.set(lossStreak, forKey: lossKey)
        defaults.set(lastDelta, forKey: deltaKey)
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: recentKey)
        }
    }
}
