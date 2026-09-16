//
//  PieceSet.swift
//  ichess
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct PieceSet: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let source: String
    let style: String

    var isSculpt: Bool { style == "sculpt" }

    var localizedSource: String {
        switch source {
        case "自绘": String(localized: "Original artwork")
        case "自绘 SVG": String(localized: "Original SVG artwork")
        default: source
        }
    }
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

    func image(side: SideColor, kind: PieceKind) -> Image? {
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
        private var images: [String: Image] = [:]
        private let lock = NSLock()

        func image(setID: String, name: String) -> Image? {
            let key = "\(setID)/\(name)"
            lock.lock()
            if let cached = images[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let url = Bundle.main.url(forResource: "\(setID)__\(name)", withExtension: "png", subdirectory: "PieceSets")
                ?? Bundle.main.url(forResource: "\(setID)__\(name)", withExtension: "png")
            guard let url else { return nil }
            #if canImport(UIKit)
            guard let nativeImage = UIImage(contentsOfFile: url.path) else { return nil }
            let image = Image(uiImage: nativeImage)
            #else
            guard let nativeImage = NSImage(contentsOf: url) else { return nil }
            let image = Image(nsImage: nativeImage)
            #endif

            lock.lock()
            images[key] = image
            lock.unlock()
            return image
        }
    }
}
