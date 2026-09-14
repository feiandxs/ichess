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
                .environmentObject(pieceSets)
                .environmentObject(game)
                .environmentObject(theme)
                .onAppear { game.resumeIfNeeded() }
        }
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
