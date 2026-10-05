//
//  VerdictInfoView.swift
//  ichess
//
//  「？」说明页：走后点评是怎么算出来的。数字直接取自 MoveClassifier，不会和实际阈值不一致。
//

import SwiftUI

struct VerdictInfoView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let palette = theme.palette
        let seconds = String(format: "%.1f", Double(AnalysisCache.movetime) / 1000)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step("1", String(localized: "After you move, Stockfish evaluates the position before and after your move, about \(seconds) seconds each.", bundle: .localized))
                    step("2", String(localized: "Each evaluation becomes your win chances (0–100%) using Lichess’s published formula.", bundle: .localized))
                    step("3", String(localized: "The rating depends on how far your win chances dropped: Inaccuracy from \(Int(MoveClassifier.inaccuracyDrop)) points, Mistake from \(Int(MoveClassifier.mistakeDrop)), Blunder from \(Int(MoveClassifier.blunderDrop)). Within \(Int(MoveClassifier.bestTolerance)) point of the best move counts as Best.", bundle: .localized))
                    step("4", String(localized: "Lichess uses 5 / 10 / 15 points (10 / 20 / 30 on its −100…100 scale). These are a little more lenient, because the search is short and this app is for learners.", bundle: .localized))
                    step("5", String(localized: "A rating is always about your move, never the computer’s. Evaluations are estimates and can change with deeper search.", bundle: .localized))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.canvas)
            .navigationTitle(Text("How moves are rated"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private func step(_ number: String, _ text: String) -> some View {
        let palette = theme.palette
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: number)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(palette.chartLine, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
