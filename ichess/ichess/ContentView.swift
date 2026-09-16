//
//  ContentView.swift
//  ichess
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var pieceSets: PieceSetStore
    @EnvironmentObject private var game: ChessGameStore
    @EnvironmentObject private var theme: ThemeStore
    @State private var showPieceSets = false
    @State private var showGameOver = false
    @State private var showResignConfirmation = false
    @State private var showDifficulty = false

    var body: some View {
        let palette = theme.palette
        ZStack {
            palette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(game.statusText)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    toolbarButton(
                        theme.isDark ? "Light" : "Dark",
                        systemImage: theme.isDark ? "sun.max.fill" : "moon.fill",
                        palette: palette
                    ) {
                        theme.toggle()
                    }
                    toolbarButton("Pieces", systemImage: "checkerboard.rectangle", palette: palette) {
                        showPieceSets = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Text("Points \(game.ratingLine)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(game.streakLine)
                    if !game.recentLine.isEmpty {
                        Text(game.recentLine)
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 20)
                .padding(.top, 2)

                HStack(spacing: 6) {
                    toolbarButton("Undo", systemImage: "arrow.uturn.backward", palette: palette) {
                        game.undo()
                    }
                    .disabled(!game.canUndo)

                    toolbarButton("New", systemImage: "arrow.counterclockwise", palette: palette) {
                        game.restart()
                    }

                    toolbarButton(game.isHintThinking ? "Thinking" : "Hint", systemImage: "lightbulb", palette: palette) {
                        game.showHint()
                    }
                    .disabled(!game.canHint)

                    toolbarButton("Resign", systemImage: "flag", palette: palette) {
                        showResignConfirmation = true
                    }
                    .disabled(game.isGameOver)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)

                HStack {
                    Button {
                        showDifficulty = true
                    } label: {
                        Label("Level: \(game.activeDifficulty.title)", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    if game.selectedDifficulty != game.activeDifficulty {
                        Text("Next: \(game.selectedDifficulty.title)")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                }
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                ChessBoardView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            if showGameOver, let outcome = game.outcome {
                GameOverOverlay(
                    outcome: outcome,
                    rating: game.rating,
                    delta: game.lastRatingDelta,
                    streakLine: game.streakLine,
                    palette: palette,
                    onRematch: {
                        withAnimation(.easeOut(duration: 0.2)) { showGameOver = false }
                        game.restart()
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) { showGameOver = false }
                    }
                )
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .alert("Computer Move Unavailable", isPresented: Binding(
            get: { game.engineError != nil },
            set: { if !$0 { game.engineError = nil } }
        )) {
            Button("Retry") { game.resumeIfNeeded() }
            Button("Cancel", role: .cancel) { game.engineError = nil }
        } message: {
            Text(game.engineError ?? "")
        }
        .alert("Hint Unavailable", isPresented: Binding(
            get: { game.hintError != nil },
            set: { if !$0 { game.hintError = nil } }
        )) {
            Button("OK") { game.hintError = nil }
        } message: {
            Text(game.hintError ?? "")
        }
        .alert("Resign this game?", isPresented: $showResignConfirmation) {
            Button("Keep Playing", role: .cancel) { }
            Button("Resign", role: .destructive) { game.resign() }
        } message: {
            Text("This game will count as a loss and your practice points will be updated.")
        }
        .onAppear {
            showDifficulty = !game.hasChosenDifficulty
            if game.isGameOver { showGameOver = true }
        }
        .onChange(of: game.isGameOver) { _, over in
            if over {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
                        showGameOver = true
                    }
                }
            } else {
                showGameOver = false
            }
        }
        .sheet(isPresented: $showPieceSets) {
            PieceSetSettingsView()
        }
        .sheet(isPresented: $showDifficulty) {
            DifficultySettingsView()
        }
    }

    private func toolbarButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        palette: BoardPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.chipFill)
                .clipShape(Capsule())
        }
        .foregroundStyle(palette.chipText)
    }
}

#Preview {
    ContentView()
        .environmentObject(PieceSetStore())
        .environmentObject(ChessGameStore())
        .environmentObject(ThemeStore())
}
