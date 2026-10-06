//
//  GameArchive.swift
//  ichess
//
//  对局存档：每盘棋一个 JSON 文件，放在 Application Support/nookchess/games/，最多保留最近 200 盘。
//

import Combine
import Foundation

@MainActor
final class GameArchive: ObservableObject {
    static let shared = GameArchive()
    static let limit = 200

    /// 最新的在前。
    @Published private(set) var records: [GameRecord] = []
    private let storage: GameArchiveStorage

    init(storage: GameArchiveStorage = GameArchiveStorage(directory: GameArchiveStorage.defaultDirectory)) {
        self.storage = storage
        records = storage.load()
    }

    func record(_ id: String) -> GameRecord? {
        records.first { $0.id == id }
    }

    func add(_ record: GameRecord) {
        var record = record
        record.fillTerminalEval()
        storage.save(record)
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        // 超出上限的最旧存档删掉。
        while records.count > Self.limit, let oldest = records.popLast() {
            storage.delete(id: oldest.id)
            PostGameAnalyzer.shared.forget(oldest.id)
        }
    }

    /// 分析出一个局面的评估后写回存档。
    func setEval(_ eval: PositionEval, atPly ply: Int, in id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].setEval(eval, atPly: ply)
        storage.save(records[index])
    }

    func delete(_ id: String) {
        storage.delete(id: id)
        records.removeAll { $0.id == id }
        PostGameAnalyzer.shared.forget(id)
    }
}
