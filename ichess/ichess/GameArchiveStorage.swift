//
//  GameArchiveStorage.swift
//  ichess
//

import Foundation

/// 文件读写，不依赖界面，方便单独测试。
nonisolated struct GameArchiveStorage {
    let directory: URL

    static var defaultDirectory: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("nookchess/games", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func url(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    /// 读出所有存档，最新的在前；损坏的文件跳过。
    func load() -> [GameRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(GameRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func save(_ record: GameRecord) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(record) else { return }
        try? data.write(to: url(for: record.id), options: .atomic)
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
