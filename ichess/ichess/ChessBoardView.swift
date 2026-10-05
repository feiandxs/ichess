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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                if theme.showsCoordinates {
                    BoardCoordinatesView(squareSize: square, palette: palette)
                }

                // 箭头画在棋子之上、飞行动画之下。
                // 对手的动画播完再出现应对 / 上一步箭头。
                ForEach(game.arrows.filter { flight == nil || ($0.style != .reply && $0.style != .opponent) }) { arrow in
                    BoardArrowView(arrow: arrow, squareSize: square, palette: palette)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if game.isTrying {
                    // 试走中整盘淡淡染色，一眼能和真实对局区分。
                    palette.sandbox.opacity(0.08)
                        .allowsHitTesting(false)
                }

                if let flight {
                    if let captured = flight.captured {
                        PieceSprite(piece: captured, facing: captured.square, squareSize: square)
                            .position(center(of: captured.square, squareSize: square))
                            .opacity(1 - captureFade)
                            .scaleEffect(1 - 0.35 * captureFade)
                            .allowsHitTesting(false)
                    }

                    PieceSprite(piece: flight.piece, facing: flight.from, squareSize: square)
                        .scaleEffect(reduceMotion ? 1 : flightScale)
                        .opacity(reduceMotion ? flightProgress : 1)
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
                    .strokeBorder(
                        game.isTrying ? palette.sandbox : palette.boardBorder,
                        lineWidth: game.isTrying ? 4 : 1.5
                    )
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!game.isEngineThinking)
            .animation(.easeOut(duration: 0.2), value: game.arrows)
            .onChange(of: game.shownPlayed?.id) { _, _ in
                if game.shouldAnimateLastMove {
                    startFlight()
                } else {
                    flight = nil
                    flightProgress = 1
                    game.opponentMoveAnimating = false
                }
            }
        }
        .confirmationDialog("Promote Pawn", isPresented: promotionPresented, titleVisibility: .visible) {
            Button("Queen") { game.completePromotion(to: .queen) }
            Button("Rook") { game.completePromotion(to: .rook) }
            Button("Bishop") { game.completePromotion(to: .bishop) }
            Button("Knight") { game.completePromotion(to: .knight) }
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

    /// 被吃的子在飞行后半段才淡出，先让人看清是谁被吃。
    private var captureFade: CGFloat {
        min(1, max(0, (flightProgress - 0.5) / 0.4))
    }

    private func startFlight() {
        guard let played = game.shownPlayed else {
            flight = nil
            flightProgress = 1
            game.opponentMoveAnimating = false
            return
        }
        // 对手的子按设置的速度慢慢走；玩家自己的子保持利落。减弱动态时只做淡入。
        let opponent = played.piece.color != game.playerColor
        let duration = reduceMotion ? 0.25 : (opponent ? theme.moveSpeed.opponentDuration : 0.3)
        flight = played
        flightProgress = 0
        withAnimation(.easeInOut(duration: duration)) {
            flightProgress = 1
        } completion: {
            if flight?.id == played.id {
                flight = nil
                game.opponentMoveAnimating = false
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
        if reduceMotion { return center(of: flight.to, squareSize: squareSize) }
        let from = center(of: flight.from, squareSize: squareSize)
        let to = center(of: flight.to, squareSize: squareSize)
        return TravelPath.point(t: flightProgress, from: from, to: to, knight: flight.isKnight)
    }

    private func squareCell(row: Int, col: Int, size: CGFloat, palette: BoardPalette) -> some View {
        let square = Square.at(row: row, col: col)
        let isLight = (row + col) % 2 == 0
        let piece = game.piece(at: square)
        let isSelected = game.selected == square
        let isLast = game.shownLastMove?.0 == square || game.shownLastMove?.1 == square
        let isHint = game.hintSquares.contains(square)
        let inCheck = isKingInCheck(on: square, piece: piece)
        let isTarget = game.legalTargets.contains(square)
        let isRisky = game.riskyTargets[square] != nil
        let isEndangered = game.dangers.contains { $0.square == square }
        let hideMover = flight?.to == square
        let hideCaptured = flight?.captured?.square == square && flightProgress < 1

        return ZStack {
            (isLight ? palette.lightSquare : palette.darkSquare)
            if isLast { palette.lastMove }
            if isHint { palette.hint }
            if isSelected { palette.selected }
            if inCheck { palette.check }

            if isEndangered {
                RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                    .strokeBorder(palette.danger, lineWidth: max(2, size * 0.05))
                    .padding(size * 0.04)
            }

            if let piece, !hideMover, !hideCaptured {
                PieceSprite(piece: piece, facing: piece.square, squareSize: size)
            }

            if isEndangered {
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .background(palette.danger, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(size * 0.03)
            }

            if isTarget {
                let fill = isRisky ? palette.danger : palette.targetFill
                if piece != nil {
                    Circle()
                        .stroke(fill, lineWidth: 3)
                        .padding(size * 0.08)
                } else if isRisky {
                    Image(systemName: "xmark")
                        .font(.system(size: size * 0.18, weight: .bold))
                        .foregroundStyle(fill)
                } else {
                    Circle()
                        .fill(fill)
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
        if case let .check(color) = game.shownBoard.state { return piece?.color == color }
        if case let .checkmate(color) = game.shownBoard.state { return piece?.color == color }
        return false
    }
}

/// 棋盘边缘坐标：左列格子左上角是数字，底行格子右下角是字母（玩家执白，a1 在左下）。
/// 画在所有格子之上，不拦截点击。
struct BoardCoordinatesView: View {
    let squareSize: CGFloat
    let palette: BoardPalette

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<8, id: \.self) { row in
                label("\(8 - row)", onLight: row % 2 == 0, alignment: .topLeading)
                    .offset(y: CGFloat(row) * squareSize)
            }
            ForEach(0..<8, id: \.self) { col in
                label(String(UnicodeScalar(UInt8(97 + col))), onLight: (7 + col) % 2 == 0, alignment: .bottomTrailing)
                    .offset(x: CGFloat(col) * squareSize, y: 7 * squareSize)
            }
        }
        .frame(width: squareSize * 8, height: squareSize * 8, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 底色取格子本色：空格上看不出来，压在大棋子上时仍能托住字。
    private func label(_ text: String, onLight: Bool, alignment: Alignment) -> some View {
        let inset = squareSize * 0.11
        return Text(verbatim: text)
            .font(.system(size: max(9, squareSize * 0.17), weight: .bold, design: .rounded))
            .foregroundStyle(palette.coordinate(onLight: onLight))
            .padding(.horizontal, squareSize * 0.025)
            .background(
                (onLight ? palette.lightSquare : palette.darkSquare).opacity(0.85),
                in: RoundedRectangle(cornerRadius: squareSize * 0.05, style: .continuous)
            )
            .padding(inset)
            .frame(width: squareSize, height: squareSize, alignment: alignment)
    }
}

/// 从一格画到另一格的箭头；马步（1×2）走折线，其余走直线。
struct BoardArrowView: View {
    let arrow: BoardArrow
    let squareSize: CGFloat
    let palette: BoardPalette

    var body: some View {
        let color = palette.arrow(arrow.style)
        let from = center(arrow.from)
        let to = center(arrow.to)
        let width = squareSize * 0.15
        let headLength = squareSize * 0.38
        let headWidth = squareSize * 0.40
        let points = route(from: from, to: to)
        let last = points[points.count - 1]
        let before = points[points.count - 2]
        let angle = atan2(last.y - before.y, last.x - before.x)
        // 箭身在箭头根部收住，避免圆头从尖端戳出来。
        let base = CGPoint(x: last.x - cos(angle) * headLength * 0.85, y: last.y - sin(angle) * headLength * 0.85)

        ZStack {
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst().dropLast() { path.addLine(to: point) }
                path.addLine(to: base)
            }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            Path { path in
                let left = CGPoint(
                    x: last.x - cos(angle) * headLength + cos(angle + .pi / 2) * headWidth / 2,
                    y: last.y - sin(angle) * headLength + sin(angle + .pi / 2) * headWidth / 2
                )
                let right = CGPoint(
                    x: last.x - cos(angle) * headLength - cos(angle + .pi / 2) * headWidth / 2,
                    y: last.y - sin(angle) * headLength - sin(angle + .pi / 2) * headWidth / 2
                )
                path.move(to: last)
                path.addLine(to: left)
                path.addLine(to: right)
                path.closeSubpath()
            }
            .fill(color)
        }
        .opacity(arrow.style == .opponent ? 0.5 : 0.88)
    }

    private func center(_ square: Square) -> CGPoint {
        CGPoint(x: (CGFloat(square.col) + 0.5) * squareSize, y: (CGFloat(square.row) + 0.5) * squareSize)
    }

    private func route(from: CGPoint, to: CGPoint) -> [CGPoint] {
        let dc = abs(arrow.to.col - arrow.from.col)
        let dr = abs(arrow.to.row - arrow.from.row)
        guard (dc == 1 && dr == 2) || (dc == 2 && dr == 1) else { return [from, to] }
        // 先沿较长的一边走，再拐弯，和棋子的飞行路线一致。
        let corner = dr > dc ? CGPoint(x: from.x, y: to.y) : CGPoint(x: to.x, y: from.y)
        return [from, corner, to]
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
        let centered = set.isCentered
        let ratio = set.isSculpt ? kind.heightRatio : 0.92
        // Square 100x100 art already includes its own margin; scale the frame so
        // the tallest piece fills roughly the same height as Nook Flat.
        let height = set.isSquareArt ? squareSize * 0.98 : squareSize * 0.90 * ratio
        let flip = kind == .knight && facing.file == .g
        Group {
            if let image = pieceSets.image(side: piece.color.side, kind: kind) {
                image
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(height: height)
        .scaleEffect(x: flip ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(set.isSculpt ? 0.35 : 0.18), radius: set.isSculpt ? 3 : 1, y: 1)
        .padding(.bottom, centered ? 0 : squareSize * 0.03)
        .frame(width: squareSize, height: squareSize, alignment: centered ? .center : .bottom)
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
