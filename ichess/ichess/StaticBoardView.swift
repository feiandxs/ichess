//
//  StaticBoardView.swift
//  ichess
//
//  只读棋盘：显示一个给定局面，可带上一步高亮、被将军的王、箭头。复盘用，不依赖 ChessGameStore。
//

import ChessKit
import SwiftUI

struct StaticBoardView: View {
    @EnvironmentObject private var theme: ThemeStore

    let position: Position
    var lastMove: (Square, Square)?
    var checkedKing: Square?
    var arrows: [BoardArrow] = []

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
                                cell(row: row, col: col, size: square, palette: palette)
                            }
                        }
                    }
                }
                if theme.showsCoordinates {
                    BoardCoordinatesView(squareSize: square, palette: palette)
                }
                ForEach(arrows) { arrow in
                    BoardArrowView(arrow: arrow, squareSize: square, palette: palette)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: square * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: square * 0.22, style: .continuous)
                    .strokeBorder(palette.boardBorder, lineWidth: 1.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func cell(row: Int, col: Int, size: CGFloat, palette: BoardPalette) -> some View {
        let square = Square.at(row: row, col: col)
        let isLight = (row + col) % 2 == 0
        let isLast = lastMove?.0 == square || lastMove?.1 == square
        return ZStack {
            (isLight ? palette.lightSquare : palette.darkSquare)
            if isLast { palette.lastMove }
            if checkedKing == square { palette.check }
            if let piece = position.piece(at: square) {
                PieceSprite(piece: piece, facing: piece.square, squareSize: size)
            }
        }
        .frame(width: size, height: size)
    }
}
