//
//  PieceSetSettingsView.swift
//  ichess
//

import SwiftUI

struct PieceSetSettingsView: View {
    @EnvironmentObject private var store: PieceSetStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.sets) { set in
                Button {
                    store.selectedID = set.id
                } label: {
                    HStack(spacing: 12) {
                        preview(set)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.name)
                                .foregroundStyle(.primary)
                                .font(.body.weight(.semibold))
                            Text(set.localizedSource)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if set.id == store.selectedID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(red: 88 / 255, green: 204 / 255, blue: 2 / 255))
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Pieces")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
        #endif
    }

    private func preview(_ set: PieceSet) -> some View {
        HStack(spacing: 2) {
            ForEach([PieceKind.pawn, .knight, .bishop, .rook, .queen, .king], id: \.rawValue) { kind in
                if let image = PieceImageCache.shared.image(setID: set.id, name: "white_\(kind.rawValue)") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 28)
                }
            }
        }
        .padding(6)
        .background(theme.palette.darkSquare)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
