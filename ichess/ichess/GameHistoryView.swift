//
//  GameHistoryView.swift
//  ichess
//
//  对局记录列表：日期、模式、结果、对手等级、步数、准确率；点按进入复盘，左滑 / 长按删除。
//

import SwiftUI

extension GameEndReason {
    var title: String {
        switch self {
        case .checkmate: String(localized: "Checkmate", bundle: .localized)
        case .resignation: String(localized: "Resigned", bundle: .localized)
        case .stalemate: String(localized: "Stalemate", bundle: .localized)
        case .repetition: String(localized: "Threefold repetition", bundle: .localized)
        case .fiftyMoves: String(localized: "Fifty-move rule", bundle: .localized)
        case .insufficientMaterial: String(localized: "Insufficient material", bundle: .localized)
        case .agreement: String(localized: "By agreement", bundle: .localized)
        case .abandoned: String(localized: "Left unfinished", bundle: .localized)
        }
    }
}

extension GameRecord {
    var resultTitle: String {
        switch result {
        case .win?: String(localized: "Win", bundle: .localized)
        case .loss?: String(localized: "Loss", bundle: .localized)
        case .draw?: String(localized: "Draw", bundle: .localized)
        case nil: String(localized: "Unfinished", bundle: .localized)
        }
    }

    /// 「胜 · 将死」。
    var resultHeadline: String { "\(resultTitle) · \(reason.title)" }

    /// 玩家走了几步。
    var playerMoveCount: Int { (moves.count + 1) / 2 }
}

struct GameHistoryView: View {
    @ObservedObject private var archive = GameArchive.shared
    @ObservedObject private var analyzer = PostGameAnalyzer.shared
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        let palette = theme.palette
        NavigationStack {
            Group {
                if archive.records.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Finished games show up here so you can review them.")
                    }
                } else {
                    List {
                        ForEach(archive.records) { record in
                            NavigationLink(value: record.id) {
                                row(record, palette: palette)
                            }
                            .listRowBackground(palette.cardFill)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    archive.delete(record.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    archive.delete(record.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(palette.canvas.ignoresSafeArea())
            .navigationTitle(Text("Game history"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: String.self) { id in
                ReviewView(recordID: id)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    private func row(_ record: GameRecord, palette: BoardPalette) -> some View {
        let report = GameAnalysis.report(startEval: record.startEval, moves: record.moves)
        let date = record.date.formatted(.dateTime.month().day().hour().minute().locale(locale))
        let level = record.difficulty.title
        let moves = String(localized: "\(record.playerMoveCount) moves", bundle: .localized)
        return HStack(spacing: 12) {
            Image(systemName: record.symbol)
                .font(.title3)
                .foregroundStyle(record.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: record.resultHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    if let delta = record.ratingDelta, delta != 0 {
                        Text(verbatim: delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(delta > 0 ? palette.gain : palette.loss)
                    }
                }
                Text(verbatim: "\(date) · \(record.mode.title) · \(level) · \(moves)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if report.isComplete, let accuracy = report.accuracy {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "\(Int(accuracy.rounded()))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                    Text("Accuracy")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
            } else if analyzer.isAnalyzing(record.id) {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

extension GameRecord {
    var symbol: String {
        switch result {
        case .win?: "trophy.fill"
        case .loss?: "flag.fill"
        case .draw?: "equal.circle.fill"
        case nil: "pause.circle.fill"
        }
    }

    var accent: Color {
        switch result {
        case .win?: Color(red: 88 / 255, green: 204 / 255, blue: 2 / 255)
        case .loss?: Color(red: 1, green: 0.45, blue: 0.32)
        case .draw?: Color(red: 90 / 255, green: 160 / 255, blue: 190 / 255)
        case nil: Color.gray
        }
    }
}
