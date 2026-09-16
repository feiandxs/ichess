import ChessKitEngine
import Foundation

actor StockfishHintEngine {
    static let shared = StockfishHintEngine()

    private var engine: Engine?
    private var isSearching = false

    func bestMove(fen: String) async throws -> String {
        guard !isSearching else { throw HintError.unavailable }
        isSearching = true
        defer { isSearching = false }

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
        case .missingNetwork: "缺少提示引擎资源，请重新安装完整版本。"
        case .unavailable: "暂时无法获取提示，请稍后再试。"
        }
    }
}
