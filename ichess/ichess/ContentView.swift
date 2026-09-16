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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.statusText)
                            .font(.headline)
                            .foregroundStyle(palette.primaryText)
                        HStack(spacing: 8) {
                            Text("练习积分 \(game.ratingLine)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text(game.streakLine)
                            if !game.recentLine.isEmpty {
                                Text(game.recentLine)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    toolbarButton(
                        theme.isDark ? "浅色" : "深色",
                        systemImage: theme.isDark ? "sun.max.fill" : "moon.fill",
                        palette: palette
                    ) {
                        theme.toggle()
                    }
                    toolbarButton("棋子", systemImage: "checkerboard.rectangle", palette: palette) {
                        showPieceSets = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                HStack(spacing: 6) {
                    toolbarButton("悔棋", systemImage: "arrow.uturn.backward", palette: palette) {
                        game.undo()
                    }
                    .disabled(!game.canUndo)

                    toolbarButton("重开", systemImage: "arrow.counterclockwise", palette: palette) {
                        game.restart()
                    }

                    toolbarButton(game.isHintThinking ? "分析" : "提示", systemImage: "lightbulb", palette: palette) {
                        game.showHint()
                    }
                    .disabled(!game.canHint)

                    toolbarButton("认输", systemImage: "flag", palette: palette) {
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
                        Label("难度：\(game.activeDifficulty.title)", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    if game.selectedDifficulty != game.activeDifficulty {
                        Text("下盘：\(game.selectedDifficulty.title)")
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
        .alert("电脑暂时无法走棋", isPresented: Binding(
            get: { game.engineError != nil },
            set: { if !$0 { game.engineError = nil } }
        )) {
            Button("重试") { game.resumeIfNeeded() }
            Button("取消", role: .cancel) { game.engineError = nil }
        } message: {
            Text(game.engineError ?? "")
        }
        .alert("提示暂不可用", isPresented: Binding(
            get: { game.hintError != nil },
            set: { if !$0 { game.hintError = nil } }
        )) {
            Button("好") { game.hintError = nil }
        } message: {
            Text(game.hintError ?? "")
        }
        .alert("确认认输？", isPresented: $showResignConfirmation) {
            Button("继续下棋", role: .cancel) { }
            Button("认输", role: .destructive) { game.resign() }
        } message: {
            Text("本局将记为负局，并按现有规则结算积分。")
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
        _ title: String,
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
