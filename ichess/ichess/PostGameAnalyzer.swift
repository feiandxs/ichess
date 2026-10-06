//
//  PostGameAnalyzer.swift
//  ichess
//
//  赛后分析：给存档里还没有评估的局面补上引擎评估（满力、每个局面约 300ms）。
//  所有请求走后台优先级：对手走子、提示、点评永远先于它，所以不会拖慢或干扰正在进行的对局。
//  结果每算完一个局面就写回存档，中途退出下次启动或打开复盘时接着算。
//

import Combine
import Foundation

@MainActor
final class PostGameAnalyzer: ObservableObject {
    static let shared = PostGameAnalyzer()
    static let movetime = 300

    struct Progress: Equatable {
        var done: Int
        var total: Int
        var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
    }

    /// 正在排队或分析中的存档 id → 进度。
    @Published private(set) var progress: [String: Progress] = [:]
    /// 引擎出错、放弃分析的存档，不再自动重试（重新打开复盘时可再试）。
    @Published private(set) var failed: Set<String> = []

    private var queue: [String] = []
    private var runner: Task<Void, Never>?
    private var currentID: String?

    func isAnalyzing(_ id: String) -> Bool { progress[id] != nil }

    /// 排队分析；已在队列里则忽略。
    func enqueue(_ id: String) {
        guard let record = GameArchive.shared.record(id) else { return }
        let missing = analyzable(record)
        guard !missing.isEmpty, !queue.contains(id) else { return }
        failed.remove(id)
        progress[id] = Progress(done: record.moves.count + 1 - missing.count, total: record.moves.count + 1)
        queue.append(id)
        startRunnerIfNeeded()
    }

    /// 启动时接着算没算完的已结束对局（最近的 10 盘）；放弃的对局只在打开复盘时才算。
    func resumePending() {
        for record in GameArchive.shared.records.prefix(10) where record.isFinished && !failed.contains(record.id) {
            enqueue(record.id)
        }
    }

    /// 存档被删除时调用。
    func forget(_ id: String) {
        queue.removeAll { $0 == id }
        progress[id] = nil
        failed.remove(id)
        if currentID == id {
            runner?.cancel()
        }
    }

    private func analyzable(_ record: GameRecord) -> [Int] {
        var copy = record
        copy.fillTerminalEval()
        return GameAnalysis.missingPlies(copy.evals)
    }

    private func startRunnerIfNeeded() {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while let id = queue.first {
            currentID = id
            await analyze(id)
            if queue.first == id { queue.removeFirst() }
            progress[id] = nil
            currentID = nil
            if Task.isCancelled && !queue.isEmpty {
                // 被取消的是已删除的那一盘，后面的继续。
                runner = Task { [weak self] in await self?.drain() }
                return
            }
        }
        runner = nil
    }

    private func analyze(_ id: String) async {
        guard let record = GameArchive.shared.record(id) else { return }
        let total = record.moves.count + 1
        let missing = analyzable(record)
        var done = total - missing.count
        for ply in missing {
            guard !Task.isCancelled, let current = GameArchive.shared.record(id), ply <= current.moves.count else { return }
            do {
                let result = try await StockfishHintEngine.shared.analyze(
                    fen: current.fen(atPly: ply),
                    movetime: Self.movetime,
                    background: true
                )
                GameArchive.shared.setEval(PositionEval(result), atPly: ply, in: id)
            } catch is CancellationError {
                return
            } catch {
                failed.insert(id)
                return
            }
            done += 1
            progress[id] = Progress(done: done, total: total)
        }
    }
}
