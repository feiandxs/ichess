import ChessKitEngine
import Foundation

actor StockfishHintEngine {
    static let shared = StockfishHintEngine()

    private var engine: Engine?
    private var isSearching = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// 后台请求（赛后分析、胜率）只在没有前台请求排队时才轮到。
    private var backgroundWaiting: [CheckedContinuation<Void, Never>] = []
    /// 正在搜索的请求；取消时只停自己的搜索。
    private var activeToken: UUID?
    private var goSent = false
    private var cancelRequested = false

    func bestMove(fen: String, elo: Int? = nil) async throws -> String {
        try await analyze(fen: fen, elo: elo).bestMove
    }

    /// 搜索一个局面，返回最佳着法、评分（走子方视角）和主变例。
    /// 请求会排队串行执行；调用方被取消时会给引擎发 `stop`，并抛出 CancellationError，
    /// 旧搜索的 bestmove 一定在本次请求内读完，不会漏到下一个请求里。
    /// background 为 true 时让位给所有前台请求（对手走子、提示、点评）。
    /// multipv > 1 时结果的 lines 带各条候选线；MultiPV 每次搜索都显式设置，不会漏到别的请求里。
    func analyze(fen: String, elo: Int? = nil, movetime: Int = 1000, multipv: Int = 1, background: Bool = false) async throws -> EngineAnalysis {
        let token = UUID()
        return try await withTaskCancellationHandler {
            if isSearching {
                await withCheckedContinuation { continuation in
                    if background {
                        backgroundWaiting.append(continuation)
                    } else {
                        waiting.append(continuation)
                    }
                }
            }
            isSearching = true
            activeToken = token
            goSent = false
            cancelRequested = false
            defer {
                activeToken = nil
                if !waiting.isEmpty {
                    waiting.removeFirst().resume()
                } else if !backgroundWaiting.isEmpty {
                    backgroundWaiting.removeFirst().resume()
                } else {
                    isSearching = false
                }
            }
            try Task.checkCancellation()
            // 用非结构化 Task 读响应流：调用方被取消不能连带取消流的迭代，否则流会被终止。
            let analysis = try await Task { try await self.search(fen: fen, elo: elo, movetime: movetime, multipv: multipv) }.value
            try Task.checkCancellation()
            return analysis
        } onCancel: {
            Task { await self.cancelSearch(token) }
        }
    }

    private func cancelSearch(_ token: UUID) async {
        guard activeToken == token else { return }
        cancelRequested = true
        if goSent, let engine {
            await engine.send(command: .stop)
        }
    }

    private func search(fen: String, elo: Int?, movetime: Int, multipv: Int) async throws -> EngineAnalysis {
        let engine = try await prepareEngine()
        guard let stream = await engine.responseStream else { throw HintError.unavailable }
        if cancelRequested { throw CancellationError() }
        // 同步屏障：Engine 把每条响应各开一个 Task 转发，顺序不保证，
        // 上一次搜索迟到的 info / bestmove 会混进这次的流里。先等 readyok，把它们冲掉。
        await engine.send(command: .isready)
        for await response in stream {
            if case .readyok = response { break }
        }
        if cancelRequested { throw CancellationError() }
        await engine.send(command: .setoption(id: "UCI_LimitStrength", value: elo == nil ? "false" : "true"))
        if let elo {
            await engine.send(command: .setoption(id: "UCI_Elo", value: String(elo)))
        }
        // ChessKitEngine 只在启动时设一次 MultiPV；这里每次搜索都重设，单线搜索就是 1。
        await engine.send(command: .setoption(id: "MultiPV", value: String(max(1, multipv))))
        await engine.send(command: .position(.fen(fen)))
        if cancelRequested { throw CancellationError() }
        await engine.send(command: .go(depth: 15, movetime: movetime))
        goSent = true
        // go 发出期间收到的取消，这里补发 stop。
        if cancelRequested { await engine.send(command: .stop) }

        // 响应乱序，旧搜索的 info 仍可能漏进来：builder 会校验变例在本局面上合法。
        var builder = EngineAnalysisBuilder(fen: fen)
        for await response in stream {
            switch response {
            case let .info(info):
                builder.add(info)
            case let .bestmove(move, _):
                return builder.build(bestMove: move)
            default:
                break
            }
        }
        throw HintError.unavailable
    }

    private func prepareEngine() async throws -> Engine {
        if let engine { return engine }
        var networks: [(option: String, path: String)] = []
        for (option, name) in [("EvalFile", "nn-1111cefa1111"), ("EvalFileSmall", "nn-37f18f62d772")] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "nnue") else {
                throw HintError.missingNetwork
            }
            networks.append((option, url.path(percentEncoded: false)))
        }
        let engine = Engine(type: .stockfish)
        await engine.start(coreCount: 1)
        guard let stream = await engine.responseStream else { throw HintError.unavailable }
        for await response in stream {
            if case .readyok = response { break }
        }
        // ChessKitEngine 用 URL.path() 传网络路径，"Nook Chess.app" 中的空格会被编码成 %20，
        // Stockfish 找不到文件后在 go 时直接 exit()。这里用未编码路径覆盖一次。
        for network in networks {
            await engine.send(command: .setoption(id: network.option, value: network.path))
        }
        self.engine = engine
        return engine
    }
}

enum HintError: LocalizedError {
    case missingNetwork
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingNetwork: String(localized: "Chess engine files are missing. Please reinstall the full app.", bundle: .localized)
        case .unavailable: String(localized: "The chess engine is unavailable. Please try again.", bundle: .localized)
        }
    }
}
