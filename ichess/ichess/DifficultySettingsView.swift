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
                    Text(game.hasChosenDifficulty ? String(localized: "Current game: \(game.activeDifficulty.title)", bundle: .localized) : String(localized: "Not sure? Start with Beginner.", bundle: .localized))
                } footer: {
                    Text("Choose before your first move to apply immediately. Changes during a game apply next game. Difficulty does not change the points you earn in Battle.")
                }
            }
            .navigationTitle(game.hasChosenDifficulty ? String(localized: "Choose Difficulty", bundle: .localized) : String(localized: "Choose Your Level", bundle: .localized))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if game.hasChosenDifficulty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
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
