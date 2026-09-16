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
    @Published private(set) var hasResigned = false
    @Published private(set) var isHintThinking = false
    @Published var hintError: String?
    @Published var engineError: String?
    @Published private(set) var selectedDifficulty: Difficulty = .beginner
    @Published private(set) var activeDifficulty: Difficulty = .beginner
    @Published private(set) var hasChosenDifficulty = false

    private static let difficultyKey = "nookchess.difficulty"

    let playerColor: Piece.Color = .white
    /// Restored games should not replay the last move animation.
    private(set) var shouldAnimateLastMove = false
    private var history: [Board] = []
    private var engineTask: Task<Void, Never>?
    private var hasRatedThisGame = false
    private var positionRevision = 0

    var lastMove: (Square, Square)? {
        lastPlayed.map { ($0.from, $0.to) }
    }

    var sideToMove: Piece.Color { board.position.sideToMove }
    var legalTargets: Set<Square> {
        guard let selected, !isEngineThinking else { return [] }
        return Set(board.legalMoves(forPieceAt: selected))
    }

    var canUndo: Bool { !hasResigned && !history.isEmpty }
    var canHint: Bool {
        hasChosenDifficulty && !isHintThinking && !isEngineThinking && !isGameOver && pendingPromotion == nil && sideToMove == playerColor
    }

    var isGameOver: Bool {
        outcome != nil
    }

    var outcome: GameOutcome? {
        if hasResigned { return .resigned }
        switch board.state {
        case .checkmate(let color):
            return color == playerColor ? .loss : .win
        case .draw(let reason):
            let text: String
            switch reason {
            case .stalemate: text = String(localized: "Stalemate")
            case .repetition: text = String(localized: "Threefold repetition")
            case .fiftyMoves: text = String(localized: "Fifty-move rule")
            case .insufficientMaterial: text = String(localized: "Insufficient material")
            case .agreement: text = String(localized: "By agreement")
            }
            return .draw(text)
        default:
            return nil
        }
    }

    var pendingPromotion: Move? {
        if hasResigned { return nil }
        if case let .promotion(move) = board.state { return move }
        return nil
    }

    var ratingLine: String {
        if lastRatingDelta > 0 { return "\(rating)  +\(lastRatingDelta)" }
        if lastRatingDelta < 0 { return "\(rating)  \(lastRatingDelta)" }
        return "\(rating)"
    }

    var streakLine: String {
        if winStreak > 0 { return String(localized: "Win streak: \(winStreak)") }
        if lossStreak > 0 { return String(localized: "Loss streak: \(lossStreak)") }
        return String(localized: "Practicing")
    }

    var recentLine: String {
        recentResults.suffix(8).map(\.mark).joined(separator: " ")
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.difficultyKey),
           let difficulty = Difficulty(rawValue: raw) {
            selectedDifficulty = difficulty
            activeDifficulty = difficulty
            hasChosenDifficulty = true
        }
        let stats = Strength.load()
        rating = stats.rating
        winStreak = stats.winStreak
        lossStreak = stats.lossStreak
        lastRatingDelta = stats.lastDelta
        recentResults = stats.recent
        restore()
    }

    func selectDifficulty(_ difficulty: Difficulty) {
        selectedDifficulty = difficulty
        hasChosenDifficulty = true
        UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        if history.isEmpty && board.position.fen == Board().position.fen && !isGameOver {
            activeDifficulty = difficulty
        }
        persist()
        requestEngineMoveIfNeeded()
    }

    var statusText: String {
        if hasResigned { return String(localized: "You resigned · You lost") }
        if isEngineThinking { return String(localized: "Computer is thinking") }
        switch board.state {
        case .active:
            return sideToMove == playerColor ? String(localized: "Your turn") : String(localized: "Computer’s turn")
        case .check(let color):
            return color == playerColor ? String(localized: "You are in check") : String(localized: "Computer is in check")
        case .checkmate(let color):
            return color == playerColor ? String(localized: "Checkmate · You lost") : String(localized: "Checkmate · You won")
        case .draw(let reason):
            switch reason {
            case .stalemate: return String(localized: "Draw · Stalemate")
            case .repetition: return String(localized: "Draw · Threefold repetition")
            case .fiftyMoves: return String(localized: "Draw · Fifty-move rule")
            case .insufficientMaterial: return String(localized: "Draw · Insufficient material")
            case .agreement: return String(localized: "Draw")
            }
        case .promotion:
            return String(localized: "Choose a promotion")
        }
    }

    func piece(at square: Square) -> Piece? {
        board.position.piece(at: square)
    }

    func tap(_ square: Square) {
        guard hasChosenDifficulty else { return }
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
        positionRevision += 1
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
        let revision = positionRevision
        isHintThinking = true
        hint = nil
        hintError = nil
        Task {
            defer { isHintThinking = false }
            do {
                let lan = try await StockfishHintEngine.shared.bestMove(fen: snapshot.position.fen)
                guard positionRevision == revision else { return }
                guard let move = EngineLANParser.parse(move: lan, for: playerColor, in: snapshot.position),
                      snapshot.legalMoves(forPieceAt: move.start).contains(move.end) else {
                    throw HintError.unavailable
                }
                hint = (move.start, move.end)
                selected = nil
            } catch {
                if positionRevision == revision { hintError = error.localizedDescription }
            }
        }
    }

    func undo() {
        guard canUndo else { return }
        positionRevision += 1
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

    func resign() {
        guard !isGameOver else { return }
        positionRevision += 1
        cancelEngine()
        selected = nil
        hint = nil
        hasResigned = true
        finishGameIfNeeded()
    }

    func restart() {
        positionRevision += 1
        cancelEngine()
        hasResigned = false
        activeDifficulty = selectedDifficulty
        engineError = nil
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
        positionRevision += 1
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
        guard hasChosenDifficulty, !isEngineThinking else { return }
        guard !isGameOver, pendingPromotion == nil, sideToMove != playerColor else { return }
        isEngineThinking = true
        selected = nil
        hint = nil
        let snapshot = board
        let difficulty = activeDifficulty
        engineError = nil
        engineTask = Task { [weak self] in
            do {
                let move = try await Task.detached(priority: .userInitiated) { () async throws -> EngineMove? in
                    if let elo = difficulty.engineElo {
                        let lan = try await StockfishHintEngine.shared.bestMove(fen: snapshot.position.fen, elo: elo)
                        guard let parsed = EngineLANParser.parse(move: lan, for: snapshot.position.sideToMove, in: snapshot.position),
                              snapshot.legalMoves(forPieceAt: parsed.start).contains(parsed.end) else {
                            throw HintError.unavailable
                        }
                        return EngineMove(from: parsed.start, to: parsed.end, promotion: parsed.promotedPiece?.kind)
                    }
                    return SimpleChessEngine.chooseMove(
                        on: snapshot,
                        depth: difficulty == .novice ? 1 : 2,
                        noiseWindow: difficulty == .novice ? 90 : 35
                    )
                }.value
                try await Task.sleep(for: .milliseconds(420))
                guard let self, !Task.isCancelled else { return }
                self.applyEngineMove(move)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isEngineThinking = false
                self.engineError = error.localizedDescription
            }
        }
    }

    private func applyEngineMove(_ move: EngineMove?) {
        isEngineThinking = false
        guard let move, !isGameOver, sideToMove != playerColor else { return }
        var next = board
        guard let played = next.move(pieceAt: move.from, to: move.to) else { return }
        positionRevision += 1
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
            hasRatedThisGame: hasRatedThisGame,
            hasResigned: hasResigned,
            difficulty: activeDifficulty
        )
        SavedGame.save(snapshot)
    }

    private func restore() {
        guard let saved = SavedGame.load() else { return }
        guard let position = Position(fen: saved.fen) else { return }
        board = Board(position: position)
        activeDifficulty = saved.difficulty ?? .novice
        hasResigned = saved.hasResigned ?? false
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
        switch outcome {
        case .win:
            result = .win
        case .loss, .resigned:
            result = .loss
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
    var hasResigned: Bool?
    var difficulty: Difficulty?

    private static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = folder.appendingPathComponent("nookchess", isDirectory: true)
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
        case .win: String(localized: "W")
        case .loss: String(localized: "L")
        case .draw: String(localized: "D")
        }
    }
}

enum Strength {
    static let defaultRating = 600
    static let minRating = 400
    static let maxRating = 1800

    private static let ratingKey = "nookchess.rating"
    private static let winKey = "nookchess.winStreak"
    private static let lossKey = "nookchess.lossStreak"
    private static let deltaKey = "nookchess.lastRatingDelta"
    private static let recentKey = "nookchess.recentResults"

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
