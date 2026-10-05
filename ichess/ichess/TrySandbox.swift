//
//  TrySandbox.swift
//  ichess
//
//  试走沙盒的数据、棋盘箭头、引擎分析缓存。沙盒完全独立于真实对局。
//

import ChessKit

/// 沙盒里的一步（玩家试走，或对方引擎的应对）。
struct SandboxPly {
    let board: Board
    let played: PlayedMove
    let san: String
    let isReply: Bool
    var note: SandboxNote?
}

struct SandboxState {
    /// 进入试走时的真实局面。
    let root: Board
    var plies: [SandboxPly] = []

    var board: Board { plies.last?.board ?? root }
    var lastNote: SandboxNote? { plies.last?.note }
    /// 玩家试走的第一步，「这步就走它」只提交这一步。
    var firstMove: PlayedMove? { plies.first(where: { !$0.isReply })?.played }
}

/// 棋盘上的箭头：更好的走法、提示、试走里对方的应对。
struct BoardArrow: Equatable, Identifiable {
    enum Style { case better, hint, reply, opponent, threat }

    let from: Square
    let to: Square
    let style: Style

    var id: String { "\(style)-\(from.notation)-\(to.notation)" }
}

/// 按局面 FEN 缓存引擎分析，并合并同一局面正在进行的搜索。
/// 走后点评、提示都从这里取，避免对同一局面重复占用引擎。
@MainActor
final class AnalysisCache {
    /// 点评 / 提示用的搜索时长（毫秒），要短，和对手走子共用同一个引擎。
    static let movetime = 500

    private var results: [String: EngineAnalysis] = [:]
    private var inflight: [String: Task<EngineAnalysis, Error>] = [:]

    func peek(_ fen: String) -> EngineAnalysis? { results[fen] }

    func analysis(fen: String, background: Bool = false) async throws -> EngineAnalysis {
        if let cached = results[fen] { return cached }
        let task: Task<EngineAnalysis, Error>
        if let running = inflight[fen] {
            task = running
        } else {
            task = Task { try await StockfishHintEngine.shared.analyze(fen: fen, movetime: Self.movetime, background: background) }
            inflight[fen] = task
        }
        do {
            let result = try await task.value
            if inflight[fen] == task { inflight[fen] = nil }
            if results.count > 64 { results.removeAll() }
            results[fen] = result
            return result
        } catch {
            if inflight[fen] == task { inflight[fen] = nil }
            throw error
        }
    }

    /// 悔棋 / 重开等局面作废时，停掉还在跑的搜索。
    func cancelAll() {
        inflight.values.forEach { $0.cancel() }
        inflight = [:]
    }
}
