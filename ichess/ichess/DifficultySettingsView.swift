import SwiftUI

struct DifficultySettingsView: View {
    @EnvironmentObject private var game: ChessGameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Difficulty.allCases) { difficulty in
                        Button {
                            game.selectDifficulty(difficulty)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(difficulty.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(difficulty.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if difficulty == game.selectedDifficulty {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(game.hasChosenDifficulty ? "当前对局：\(game.activeDifficulty.title)" : "不确定选哪档？可以先选入门。")
                } footer: {
                    Text("开局前选择立即生效；对局中修改从下一盘生效。难度不会改变你的练习积分。")
                }
            }
            .navigationTitle(game.hasChosenDifficulty ? "选择难度" : "选择你的水平")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if game.hasChosenDifficulty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(!game.hasChosenDifficulty)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}
