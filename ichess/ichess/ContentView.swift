//
//  ContentView.swift
//  ichess
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var pieceSets: PieceSetStore
    @EnvironmentObject private var game: ChessGameStore
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var language: LanguageStore
    @State private var showPieceSets = false
    @State private var showGameOver = false
    @State private var showResignConfirmation = false
    @State private var showDifficulty = false
    /// 整页覆盖主界面的页面：对局记录 / 复盘（不用弹层，随窗口大小铺满）。
    @State private var page: AppPage?

    var body: some View {
        let palette = theme.palette
        ZStack {
            palette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                // 窄屏（iPhone 竖屏）一行放不下时，模式切换换到第二行。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        statusText(palette: palette)
                        Spacer(minLength: 8)
                        modePicker.frame(width: 170)
                        settingsMenu(palette: palette)
                    }
                    VStack(spacing: 8) {
                        HStack {
                            statusText(palette: palette)
                            Spacer(minLength: 8)
                            settingsMenu(palette: palette)
                        }
                        modePicker
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    if game.activeMode.countsForRating {
                        Text("Points \(game.ratingLine)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(game.streakLine)
                        if !game.recentLine.isEmpty {
                            Text(game.recentLine)
                        }
                    } else {
                        Text("Practice games don’t count toward points")
                    }
                    Spacer(minLength: 4)
                    if game.selectedMode != game.activeMode {
                        Text("Next: \(game.selectedMode.title)")
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                HStack(spacing: 6) {
                    toolbarButton("New", systemImage: "arrow.counterclockwise", palette: palette) {
                        game.restart()
                    }

                    if game.activeMode.allowsAids {
                        toolbarButton(hintTitle, systemImage: "lightbulb", palette: palette) {
                            game.showHint()
                        }
                        .disabled(!game.canHint)

                        toolbarButton("Undo", systemImage: "arrow.uturn.backward", palette: palette) {
                            game.undo()
                        }
                        .disabled(!game.canUndo)
                    }

                    toolbarButton("Resign", systemImage: "flag", palette: palette) {
                        showResignConfirmation = true
                    }
                    .disabled(game.isGameOver)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

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
                .padding(.vertical, 8)

                // 开了「显示胜率」时棋盘旁带一条胜率条：宽屏竖放在右侧，窄屏横放在棋盘下方。
                BoardBarLayout(gutterRatio: theme.gutterRatio) {
                    ChessBoardView()
                    if game.showsWinChances {
                        WinBarView(value: game.winLatest?.value, isCurrent: game.winLatest?.isCurrent ?? true)
                    }
                }
                .padding(.horizontal, 16)

                if game.activeMode.allowsAids {
                    CoachPanelView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                } else if game.showsWinChances {
                    // 对战没有教练区，只放一个紧凑的胜率面板。
                    WinChancePanel()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
            }

            .padding(.bottom, 8)

            if showGameOver, let outcome = game.outcome {
                GameOverOverlay(
                    outcome: outcome,
                    rating: game.rating,
                    delta: game.lastRatingDelta,
                    streakLine: game.streakLine,
                    countsForRating: game.activeMode.countsForRating,
                    archiveID: game.archiveID,
                    palette: palette,
                    onReview: {
                        guard let id = game.archiveID else { return }
                        withAnimation(.easeOut(duration: 0.2)) { showGameOver = false }
                        show(.review(ReviewTarget(id: id), fromHistory: false))
                    },
                    onRematch: {
                        withAnimation(.easeOut(duration: 0.2)) { showGameOver = false }
                        game.restart()
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) { showGameOver = false }
                    }
                )
            }

            pageOverlay(palette: palette)
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
        .alert("Resign this game?", isPresented: $showResignConfirmation) {
            Button("Keep Playing", role: .cancel) { }
            Button("Resign", role: .destructive) { game.resign() }
        } message: {
            if game.activeMode.countsForRating {
                Text("This game will count as a loss and your points will be updated.")
            } else {
                Text("This is a practice game, so your points won’t change.")
            }
        }
        .onAppear {
            showDifficulty = !game.hasChosenDifficulty
            if game.isGameOver { showGameOver = true }
            #if DEBUG
            openDebugSheets()
            #endif
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
                .environment(\.locale, language.locale)
        }
        #if DEBUG
        .onAppear {
            // 仅调试：`-nookchess.debugSheet pieces` 启动即打开棋子库，方便截图。
            if UserDefaults.standard.string(forKey: "nookchess.debugSheet") == "pieces" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showPieceSets = true }
            }
        }
        #endif
        .sheet(isPresented: $showDifficulty) {
            DifficultySettingsView()
                .environment(\.locale, language.locale)
        }
    }

    private func show(_ new: AppPage?) {
        // 打开整页时先收起演示，避免演示的方向键 / Esc 和复盘页抢。
        if new != nil { game.exitDemo() }
        withAnimation(.easeOut(duration: 0.2)) { page = new }
    }

    @ViewBuilder
    private func pageOverlay(palette: BoardPalette) -> some View {
        switch page {
        case .history:
            GameHistoryView(
                onOpen: { show(.review(ReviewTarget(id: $0), fromHistory: true)) },
                onBack: { show(nil) }
            )
            .background(palette.canvas.ignoresSafeArea())
            .transition(.opacity)
        case let .review(target, fromHistory):
            ReviewView(
                recordID: target.id,
                initialPly: target.ply,
                // 从对局记录点进来的，返回时回到列表。
                onBack: { show(fromHistory ? .history : nil) }
            )
            .id(target.id)
            .background(palette.canvas.ignoresSafeArea())
            .transition(.opacity)
        case nil:
            EmptyView()
        }
    }

    #if DEBUG
    /// 仅调试：截图用，预置界面直接打开对局记录 / 复盘。
    private func openDebugSheets() {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "nookchess.debugPreset") {
        case "history":
            page = .history
        case "review", "review-history":
            let ply = defaults.string(forKey: "nookchess.debugPly").flatMap(Int.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                page = .review(ReviewTarget(id: "debug-loss", ply: ply), fromHistory: defaults.string(forKey: "nookchess.debugPreset") == "review-history")
            }
        default:
            break
        }
    }
    #endif

    private func statusText(palette: BoardPalette) -> some View {
        Text(game.statusText)
            .font(.headline)
            .foregroundStyle(palette.primaryText)
            .fixedSize()
    }

    /// 按钮上显示下一级提示：Hint → Hint 2/3 → Hint 3/3。
    private var hintTitle: LocalizedStringKey {
        if game.isHintThinking { return "Thinking" }
        if game.hintLevel == 0 { return "Hint" }
        return "Hint \(min(3, game.hintLevel + 1))/3"
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { game.selectedMode },
            set: { game.selectMode($0) }
        )) {
            ForEach(GameMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func settingsMenu(palette: BoardPalette) -> some View {
        Menu {
            Button {
                theme.toggle()
            } label: {
                Label(
                    theme.isDark ? "Light" : "Dark",
                    systemImage: theme.isDark ? "sun.max.fill" : "moon.fill"
                )
            }
            Button {
                showPieceSets = true
            } label: {
                Label("Pieces", systemImage: "checkerboard.rectangle")
            }
            Button {
                show(.history)
            } label: {
                Label("Game history", systemImage: "clock.arrow.circlepath")
            }
            Toggle(isOn: $game.showsWinChances) {
                Label("Show win chances", systemImage: "chart.line.uptrend.xyaxis")
            }
            Menu {
                Picker("Move animation speed", selection: $theme.moveSpeed) {
                    ForEach(MoveSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Move animation speed", systemImage: "speedometer")
            }
            Toggle(isOn: $theme.showsCoordinates) {
                Label("Show coordinates", systemImage: "textformat.abc")
            }
            Menu {
                Picker("Coordinate position", selection: $theme.coordinatePlacement) {
                    ForEach(CoordinatePlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Coordinate position", systemImage: "square.grid.3x3.topleft.filled")
            }
            .disabled(!theme.showsCoordinates)
            Menu {
                Picker("Language", selection: $language.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Language", systemImage: "globe")
            }
            Section("Practice aids") {
                Toggle("Mark pieces that can be captured for free", isOn: $game.showsSafety)
                Toggle("Mark risky squares for the selected piece", isOn: $game.showsRiskyMoves)
                Toggle("Review each move after you play", isOn: $game.showsFeedback)
                Toggle("Auto key-point reminders", isOn: $game.showsKeyPoints)
                Toggle("Pause on mistakes", isOn: $game.pausesOnMistakes)
            }
            .disabled(!game.activeMode.allowsAids)
        } label: {
            chipLabel("Settings", systemImage: "gearshape", iconOnly: true, palette: palette)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(palette.chipText)
        .fixedSize()
    }

    private func toolbarButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        iconOnly: Bool = false,
        palette: BoardPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            chipLabel(title, systemImage: systemImage, iconOnly: iconOnly, palette: palette)
        }
        // macOS 默认按钮样式会在胶囊外再加一层灰底。
        .buttonStyle(.plain)
        .foregroundStyle(palette.chipText)
    }

    @ViewBuilder
    private func chipLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        iconOnly: Bool = false,
        palette: BoardPalette
    ) -> some View {
        Group {
            if iconOnly {
                Image(systemName: systemImage)
                    .accessibilityLabel(Text(title))
            } else {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.chipFill)
        .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
        .environmentObject(PieceSetStore())
        .environmentObject(ChessGameStore())
        .environmentObject(ThemeStore())
        .environmentObject(LanguageStore())
}

struct ReviewTarget: Identifiable, Equatable {
    let id: String
    var ply: Int?
}

enum AppPage: Equatable {
    case history
    case review(ReviewTarget, fromHistory: Bool)
}
