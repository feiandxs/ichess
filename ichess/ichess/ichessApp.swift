//
//  ichessApp.swift
//  ichess
//

import SwiftUI

@main
struct ichessApp: App {
    @StateObject private var pieceSets = PieceSetStore()
    @StateObject private var game = ChessGameStore()
    @StateObject private var theme = ThemeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 560)
                #endif
                .environmentObject(pieceSets)
                .environmentObject(game)
                .environmentObject(theme)
                .onAppear { game.resumeIfNeeded() }
        }
        #if os(macOS)
        .defaultSize(width: 640, height: 760)
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                game.persistNow()
            }
            if phase == .active {
                game.resumeIfNeeded()
            }
        }
    }
}
