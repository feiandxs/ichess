//
//  PieceSet.swift
//  ichess
//

import Combine
import SwiftUI
import UIKit

struct PieceSet: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let source: String
    let style: String

    var isSculpt: Bool { style == "sculpt" }
}

@MainActor
final class PieceSetStore: ObservableObject {
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.key) }
    }

    let sets: [PieceSet]
    let defaultID: String

    var selected: PieceSet {
        sets.first { $0.id == selectedID } ?? sets.first { $0.id == defaultID } ?? sets[0]
    }

    private static let key = "pieceSetID"

    init() {
        let catalog = Self.loadCatalog()
        sets = catalog.sets
        defaultID = catalog.defaultID
        let saved = UserDefaults.standard.string(forKey: Self.key)
        if let saved, catalog.sets.contains(where: { $0.id == saved }) {
            selectedID = saved
        } else {
            selectedID = catalog.defaultID
        }
    }

    func image(side: SideColor, kind: PieceKind) -> UIImage? {
        PieceImageCache.shared.image(setID: selectedID, name: "\(side.assetPrefix)_\(kind.rawValue)")
    }

    private struct Catalog: Codable {
        var defaultID: String
        var sets: [PieceSet]
    }

    private static func loadCatalog() -> Catalog {
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "PieceSets")
            ?? Bundle.main.url(forResource: "catalog", withExtension: "json")
        if let url, let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
           !catalog.sets.isEmpty {
            return catalog
        }
        return Catalog(
            defaultID: "neo",
            sets: [PieceSet(id: "neo", name: "Neo", source: "Chess.com", style: "icon")]
        )
    }
}

enum PieceImageCache {
    static let shared = Cache()

    final class Cache {
        private var images: [String: UIImage] = [:]
        private let lock = NSLock()

        func image(setID: String, name: String) -> UIImage? {
            let key = "\(setID)/\(name)"
            lock.lock()
            if let cached = images[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let url = Bundle.main.url(forResource: "\(setID)__\(name)", withExtension: "png", subdirectory: "PieceSets")
                ?? Bundle.main.url(forResource: "\(setID)__\(name)", withExtension: "png")
            guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }

            lock.lock()
            images[key] = image
            lock.unlock()
            return image
        }
    }
}
