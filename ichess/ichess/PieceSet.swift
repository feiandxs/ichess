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
    /// How the artwork sits on a square. nil: bottom-aligned (default),
    /// "centered": centred 64x72 art (Nook Flat), "square": centred 100x100 art.
    var layout: String? = nil

    var isCentered: Bool { layout == "centered" || layout == "square" }
    var isSquareArt: Bool { layout == "square" }

    var localizedName: String {
        switch name {
        case "Soft Geometry": String(localized: "Soft Geometry", bundle: .localized)
        case "Crisp Facets": String(localized: "Crisp Facets", bundle: .localized)
        case "Bold Blocks": String(localized: "Bold Blocks", bundle: .localized)
        case "Monoline": String(localized: "Monoline", bundle: .localized)
        case "Badge Discs": String(localized: "Badge Discs", bundle: .localized)
        default: name
        }
    }

    var isSculpt: Bool { style == "sculpt" }

    var localizedSource: String {
        switch source {
        case "自绘": String(localized: "Original artwork", bundle: .localized)
        case "自绘 SVG": String(localized: "Original SVG artwork", bundle: .localized)
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

    private static func bundledCatalog(named name: String) -> Catalog? {
        let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "PieceSets")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }

    private static func loadCatalog() -> Catalog {
        if var catalog = bundledCatalog(named: "catalog"), !catalog.sets.isEmpty {
            // 可选的本地目录（不入库），其中的款式追加到内置目录之后
            if let local = bundledCatalog(named: "catalog.local") {
                let known = Set(catalog.sets.map(\.id))
                catalog.sets += local.sets.filter { !known.contains($0.id) }
            }
            return catalog
        }
        return Catalog(
            defaultID: "nook_flat",
            sets: [PieceSet(id: "nook_flat", name: "Nook Flat", source: "自绘 SVG", style: "icon", layout: "centered")]
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
