import ChessKitEngine
import Foundation

actor StockfishHintEngine {
    static let shared = StockfishHintEngine()

    private var engine: Engine?
    private var isSearching = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func bestMove(fen: String, elo: Int? = nil) async throws -> String {
        if isSearching {
            await withCheckedContinuation { waiting.append($0) }
        }
        isSearching = true
        defer {
            if waiting.isEmpty {
                isSearching = false
            } else {
                waiting.removeFirst().resume()
            }
        }

        let engine: Engine
        if let existing = self.engine {
            engine = existing
        } else {
            for name in ["nn-1111cefa1111", "nn-37f18f62d772"] {
                guard Bundle.main.url(forResource: name, withExtension: "nnue") != nil else {
                    throw HintError.missingNetwork
                }
            }
            engine = Engine(type: .stockfish)
            await engine.start(coreCount: 1)
            guard let stream = await engine.responseStream else { throw HintError.unavailable }
            for await response in stream {
                if case .readyok = response { break }
            }
            self.engine = engine
        }

        guard let stream = await engine.responseStream else { throw HintError.unavailable }
        await engine.send(command: .setoption(id: "UCI_LimitStrength", value: elo == nil ? "false" : "true"))
        if let elo {
            await engine.send(command: .setoption(id: "UCI_Elo", value: String(elo)))
        }
        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: .go(depth: 15, movetime: 1000))
        for await response in stream {
            if case let .bestmove(move, _) = response {
                return move
            }
        }
        throw HintError.unavailable
    }
}

enum HintError: LocalizedError {
    case missingNetwork
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingNetwork: String(localized: "Chess engine files are missing. Please reinstall the full app.")
        case .unavailable: String(localized: "The chess engine is unavailable. Please try again.")
        }
    }
}
