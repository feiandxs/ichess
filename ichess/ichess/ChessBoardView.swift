//
//  ChessBoardView.swift
//  ichess
//

import ChessKit
import SwiftUI

enum PieceKind: String {
    case pawn, knight, bishop, rook, queen, king

    var heightRatio: CGFloat {
        switch self {
        case .pawn: 0.68
        case .rook: 0.80
        case .knight: 0.86
        case .bishop: 0.88
        case .queen: 0.95
        case .king: 1.00
        }
    }
}

enum SideColor {
    case white, black

    var assetPrefix: String {
        self == .white ? "white" : "black"
    }
}

struct ChessBoardView: View {
    @EnvironmentObject private var pieceSets: PieceSetStore
    @EnvironmentObject private var game: ChessGameStore
    @EnvironmentObject private var theme: ThemeStore

    @State private var flight: PlayedMove?
    @State private var flightProgress: CGFloat = 1

    var body: some View {
        let palette = theme.palette
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let square = side / 8

            ZStack {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        GridRow {
                            ForEach(0..<8, id: \.self) { col in
                                squareCell(row: row, col: col, size: square, palette: palette)
                            }
                        }
                    }
                }

                if let flight {
                    if let captured = flight.captured {
                        PieceSprite(piece: captured, facing: captured.square, squareSize: square)
                            .position(center(of: captured.square, squareSize: square))
                            .opacity(1 - flightProgress)
                            .scaleEffect(1 - 0.35 * flightProgress)
                            .allowsHitTesting(false)
                    }

                    PieceSprite(piece: flight.piece, facing: flight.from, squareSize: square)
                        .scaleEffect(flightScale)
                        .position(flightPosition(squareSize: square))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        .zIndex(2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: square * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: square * 0.22, style: .continuous)
                    .strokeBorder(palette.boardBorder, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!game.isEngineThinking)
            .onChange(of: game.lastPlayed?.id) { _, _ in
                if game.shouldAnimateLastMove {
                    startFlight()
                } else {
                    flight = nil
                    flightProgress = 1
                }
            }
        }
        .confirmationDialog("升变成", isPresented: promotionPresented, titleVisibility: .visible) {
            Button("后") { game.completePromotion(to: .queen) }
            Button("车") { game.completePromotion(to: .rook) }
            Button("象") { game.completePromotion(to: .bishop) }
            Button("马") { game.completePromotion(to: .knight) }
        }
    }

    private var promotionPresented: Binding<Bool> {
        Binding(
            get: { game.pendingPromotion != nil },
            set: { if !$0, game.pendingPromotion != nil { game.completePromotion(to: .queen) } }
        )
    }

    private var flightScale: CGFloat {
        let t = flightProgress
        if t < 0.16 { return 1 + 0.22 * (t / 0.16) }
        if t > 0.84 { return 1.22 - 0.22 * ((t - 0.84) / 0.16) }
        return 1.22
    }

    private func startFlight() {
        guard let played = game.lastPlayed else {
            flight = nil
            flightProgress = 1
            return
        }
        flight = played
        flightProgress = 0
        withAnimation(.easeInOut(duration: 0.34)) {
            flightProgress = 1
        } completion: {
            if flight?.id == played.id {
                flight = nil
            }
        }
    }

    private func center(of square: Square, squareSize: CGFloat) -> CGPoint {
        CGPoint(
            x: (CGFloat(square.col) + 0.5) * squareSize,
            y: (CGFloat(square.row) + 0.5) * squareSize
        )
    }

    private func flightPosition(squareSize: CGFloat) -> CGPoint {
        guard let flight else { return .zero }
        let from = center(of: flight.from, squareSize: squareSize)
        let to = center(of: flight.to, squareSize: squareSize)
        return TravelPath.point(t: flightProgress, from: from, to: to, knight: flight.isKnight)
    }

    private func squareCell(row: Int, col: Int, size: CGFloat, palette: BoardPalette) -> some View {
        let square = Square.at(row: row, col: col)
        let isLight = (row + col) % 2 == 0
        let piece = game.piece(at: square)
        let isSelected = game.selected == square
        let isLast = game.lastMove?.0 == square || game.lastMove?.1 == square
        let isHint = game.hint?.0 == square || game.hint?.1 == square
        let inCheck = isKingInCheck(on: square, piece: piece)
        let isTarget = game.legalTargets.contains(square)
        let hideMover = flight?.to == square
        let hideCaptured = flight?.captured?.square == square && flightProgress < 1

        return ZStack {
            (isLight ? palette.lightSquare : palette.darkSquare)
            if isLast { palette.lastMove }
            if isHint { palette.hint }
            if isSelected { palette.selected }
            if inCheck { palette.check }

            if let piece, !hideMover, !hideCaptured {
                PieceSprite(piece: piece, facing: piece.square, squareSize: size)
            }

            if isTarget {
                if piece != nil {
                    Circle()
                        .stroke(palette.targetFill, lineWidth: 3)
                        .padding(size * 0.08)
                } else {
                    Circle()
                        .fill(palette.targetFill)
                        .frame(width: size * 0.22, height: size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { game.tap(square) }
    }

    private func isKingInCheck(on square: Square, piece: Piece?) -> Bool {
        guard piece?.kind == .king else { return false }
        if case let .check(color) = game.board.state { return piece?.color == color }
        if case let .checkmate(color) = game.board.state { return piece?.color == color }
        return false
    }
}

struct PieceSprite: View {
    @EnvironmentObject private var pieceSets: PieceSetStore
    let piece: Piece
    let facing: Square
    let squareSize: CGFloat

    var body: some View {
        let set = pieceSets.selected
        let kind = piece.kind.assetKind
        let ratio = set.isSculpt ? kind.heightRatio : 0.92
        let height = squareSize * 0.90 * ratio
        let flip = kind == .knight && facing.file == .g
        Group {
            if let ui = pieceSets.image(side: piece.color.side, kind: kind) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(height: height)
        .scaleEffect(x: flip ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(set.isSculpt ? 0.35 : 0.18), radius: set.isSculpt ? 3 : 1, y: 1)
        .padding(.bottom, squareSize * 0.03)
        .frame(width: squareSize, height: squareSize, alignment: .bottom)
    }
}

enum TravelPath {
    static func point(t: CGFloat, from: CGPoint, to: CGPoint, knight: Bool) -> CGPoint {
        let clamped = min(1, max(0, t))
        if knight {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let corner = abs(dx) > abs(dy)
                ? CGPoint(x: to.x, y: from.y)
                : CGPoint(x: from.x, y: to.y)
            if clamped < 0.55 {
                return lerp(from, corner, clamped / 0.55)
            }
            return lerp(corner, to, (clamped - 0.55) / 0.45)
        }
        return lerp(from, to, clamped)
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

#Preview {
    ChessBoardView()
        .padding(24)
        .background(BoardPalette(isDark: true).canvas)
        .environmentObject(PieceSetStore())
        .environmentObject(ChessGameStore())
        .environmentObject(ThemeStore())
}
