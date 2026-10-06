//
//  ChessGameStore.swift
//  ichess
//

import ChessKit
import Combine
import SwiftUI

struct PlayedMove: Equatable, Identifiable {
    let id: UUID
    let from: Square
    let to: Square
    let piece: Piece
    let captured: Piece?

    var isKnight: Bool { piece.kind == .knight }
}

@MainActor
final class ChessGameStore: ObservableObject {
    @Published private(set) var board = Board() {
        didSet {
            clearHint()
            refreshSafety()
            invalidateThreat()
            refreshKeyPoint()
        }
    }
    @Published var selected: Square? {
        didSet { refreshSafety() }
    }
    @Published private(set) var lastPlayed: PlayedMove?
    /// 引擎推荐的走法；分级提示按 hintLevel 逐步揭示。
    @Published private(set) var hint: (Square, Square)?
    @Published private(set) var hintSAN: String?
    /// 推荐走法起的主变例（SAN，含第一步）。
    @Published private(set) var hintLine: [String] = []
    /// 0 未提示；1 说想法；2 标出要动的子并说为什么；3 画出箭头、说清原因和胜率。
    @Published private(set) var hintLevel = 0
    /// 提示三级的内容（想法 / 哪个子 / 答案），文字随语言现说。
    @Published private(set) var hintExplanation: HintExplanation?
    /// 走完提示这步后玩家的胜率（0...100）。
    @Published private(set) var hintWin: Double?
    /// 前三名候选走法；只在当前局面有效，局面一变就清除。
    @Published private(set) var candidates: CandidateSet?
    @Published private(set) var isCandidatesThinking = false
    /// 候选列表正在显示（替换说明区）。
    @Published private(set) var candidatesVisible = false
    /// 点中的候选（箭头和变例跟着它）。
    @Published private(set) var selectedCandidate: Int?
    @Published private(set) var isEngineThinking = false
    @Published private(set) var rating = Strength.defaultRating
    @Published private(set) var winStreak = 0
    @Published private(set) var lossStreak = 0
    @Published private(set) var lastRatingDelta = 0
    @Published private(set) var recentResults: [GameResult] = []
    @Published private(set) var hasResigned = false
    @Published private(set) var isHintThinking = false
    @Published var hintError: String?
    @Published var engineError: String?
    @Published private(set) var selectedDifficulty: Difficulty = .beginner
    @Published private(set) var activeDifficulty: Difficulty = .beginner
    @Published private(set) var hasChosenDifficulty = false
    /// 面板里选的模式；对局中切换要等下一局才生效。
    @Published private(set) var selectedMode: GameMode = .practice
    /// 当前这一局实际的模式。
    @Published private(set) var activeMode: GameMode = .practice {
        didSet {
            if !activeMode.allowsAids {
                exitSandbox()
                cancelFeedback()
                invalidateThreat()
                clearHint()
            }
            refreshSafety()
            refreshKeyPoint()
        }
    }
    /// 标出会被白吃的子。
    @Published var showsSafety: Bool {
        didSet {
            UserDefaults.standard.set(showsSafety, forKey: Self.safetyKey)
            refreshSafety()
            refreshKeyPoint()
        }
    }
    /// 轮到玩家时自动在教练区给一条重点提醒（练习模式），默认开启。
    @Published var showsKeyPoints: Bool {
        didSet {
            UserDefaults.standard.set(showsKeyPoints, forKey: Self.keyPointsKey)
            refreshKeyPoint()
        }
    }
    /// 选中棋子时标出危险落点，默认关闭。
    @Published var showsRiskyMoves: Bool {
        didSet {
            UserDefaults.standard.set(showsRiskyMoves, forKey: Self.riskyMovesKey)
            refreshSafety()
        }
    }
    /// 每步棋后给出点评（练习模式），默认开启。
    @Published var showsFeedback: Bool {
        didSet {
            UserDefaults.standard.set(showsFeedback, forKey: Self.feedbackKey)
            if showsFeedback {
                precomputeAnalysisIfNeeded()
            } else {
                cancelFeedback()
            }
        }
    }
    /// 显示实时胜率（棋盘旁的胜率条 + 趋势图），练习 / 对战都可以开；和练习辅助互相独立。
    @Published var showsWinChances: Bool {
        didSet {
            UserDefaults.standard.set(showsWinChances, forKey: Self.winChancesKey)
            if showsWinChances {
                ensureWinChances()
            } else {
                winTask?.cancel()
                winTask = nil
            }
        }
    }
    /// 评估有更新就 +1，驱动胜率条 / 趋势图刷新（moves 本身不是 @Published）。
    @Published private(set) var evalRevision = 0
    /// 最近一步玩家走法的点评；下一步、悔棋、重开时清除。
    @Published private(set) var feedback: MoveFeedback?
    /// 玩家刚走完、点评还在计算。
    @Published private(set) var isFeedbackPending = false
    /// 点评生成时的步数；对手应对之后棋盘变了，「更好的走法」箭头就不再画。
    private var feedbackPly = 0
    /// 试走沙盒；非 nil 表示正在试走，棋盘显示的是沙盒局面。
    @Published private(set) var sandbox: SandboxState? {
        didSet {
            clearHint()
            refreshSafety()
            invalidateThreat()
            refreshKeyPoint()
        }
    }
    @Published private(set) var isSandboxThinking = false
    @Published private(set) var sandboxError: String?
    /// 玩家当前会被对方白吃的子。
    @Published private(set) var dangers: [ThreatAnalyzer.Danger] = []
    /// 选中棋子后，走过去会亏子的目标格。
    @Published private(set) var riskyTargets: [Square: ThreatAnalyzer.MoveRisk] = [:]
    /// 轮到玩家时最该留意的一条（威胁或机会），不含该走哪一步。
    @Published private(set) var keyPoint: CoachFinding?
    /// 「对方想干什么」的结果；局面一变就清除。
    @Published private(set) var threat: OpponentThreat?
    @Published private(set) var isThreatThinking = false
    @Published private(set) var threatError: String?

    private static let difficultyKey = "nookchess.difficulty"
    private static let modeKey = "nookchess.mode"
    private static let safetyKey = "nookchess.showsSafety"
    private static let riskyMovesKey = "nookchess.showsRiskyMoves"
    private static let feedbackKey = "nookchess.showsFeedback"
    private static let winChancesKey = "nookchess.showsWinChances"
    private static let keyPointsKey = "nookchess.showsKeyPoints"

    let playerColor: Piece.Color = .white
    /// Restored games should not replay the last move animation.
    private(set) var shouldAnimateLastMove = false
    /// 对手的走子动画正在播放（试走里的应对）；说明文字等动画结束再出现。由棋盘视图在动画结束时清除。
    @Published var opponentMoveAnimating = false
    /// 本局完整着法记录，按顺序从第一步开始。
    private(set) var moves: [MoveRecord] = []
    private var engineTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var winTask: Task<Void, Never>?
    /// 初始局面的引擎评估。
    private(set) var startEval: PositionEval?
    /// 这一局结束后对应的存档 id。
    @Published private(set) var archiveID: String?
    private var sandboxTask: Task<Void, Never>?
    /// 沙盒每次变动都 +1，丢弃过期的引擎结果。
    private var sandboxRevision = 0
    private var threatTask: Task<Void, Never>?
    /// 显示的局面每变一次就 +1，丢弃过期的「对方想干什么」结果。
    private var threatRevision = 0
    /// 提示 / 候选对应的局面每变一次就 +1（clearHint），丢弃过期的搜索结果。
    private var hintRevision = 0
    private var hintUCI: String?
    private var candidateTask: Task<Void, Never>?
    /// 候选线按局面 FEN 缓存，重复点「候选走法」不用再搜。
    private var candidateCache: [String: [EngineLine]] = [:]
    private let analyses = AnalysisCache()
    /// 候选走法的搜索时长（毫秒），满力、三条线。
    private static let candidateMovetime = 700
    /// 试走里对方应对的搜索时长（毫秒），满力。
    private static let sandboxMovetime = 800
    /// 「对方想干什么」的搜索时长（毫秒），要短，和对手走子共用同一个引擎。
    private static let threatMovetime = 400
    private var hasRatedThisGame = false
    private var positionRevision = 0

    var sideToMove: Piece.Color { board.position.sideToMove }

    // 棋盘实际显示的内容：试走时是沙盒，否则是真实对局。
    var isTrying: Bool { sandbox != nil }
    var shownBoard: Board { sandbox?.board ?? board }
    var shownPlayed: PlayedMove? { isTrying ? sandbox?.plies.last?.played : lastPlayed }
    var shownLastMove: (Square, Square)? { shownPlayed.map { ($0.from, $0.to) } }

    var legalTargets: Set<Square> {
        guard let selected, !isEngineThinking, !isSandboxThinking else { return [] }
        return Set(shownBoard.legalMoves(forPieceAt: selected))
    }

    /// 分级提示要高亮的格子。
    var hintSquares: Set<Square> {
        guard let hint else { return [] }
        switch hintLevel {
        case 0, 1: return []
        case 2: return [hint.0]
        default: return [hint.0, hint.1]
        }
    }

    var arrows: [BoardArrow] {
        let base = baseArrows
        guard let threat else { return base }
        return base + [BoardArrow(from: threat.from, to: threat.to, style: .threat)]
    }

    /// 候选列表里点中的那步，或提示的最终答案。
    private var hintArrows: [BoardArrow] {
        if candidatesVisible, let index = selectedCandidate, let set = candidates, set.candidates.indices.contains(index) {
            let move = set.candidates[index]
            return [BoardArrow(from: move.from, to: move.to, style: .hint)]
        }
        if hintLevel >= 3, let hint {
            return [BoardArrow(from: hint.0, to: hint.1, style: .hint)]
        }
        return []
    }

    private var baseArrows: [BoardArrow] {
        if let sandbox {
            var result = hintArrows
            if let ply = sandbox.plies.last, ply.isReply {
                result.insert(BoardArrow(from: ply.played.from, to: ply.played.to, style: .reply), at: 0)
            }
            return result
        }
        let shownHint = hintArrows
        if !shownHint.isEmpty { return shownHint }
        // 提示优先；没有提示时显示上一步点评里更好的走法。
        if hintLevel == 0, showsFeedback, feedbackPly == moves.count, let feedback, feedback.verdict.isProblem, let better = feedback.better {
            return [BoardArrow(from: better.from, to: better.to, style: .better)]
        }
        // 对手刚走的一步：留一支淡箭头，直到玩家落子。
        if let last = lastPlayed, last.piece.color != playerColor, sideToMove == playerColor, !isGameOver {
            return [BoardArrow(from: last.from, to: last.to, style: .opponent)]
        }
        return []
    }

    var canTry: Bool {
        activeMode.allowsAids && hasChosenDifficulty && !isGameOver && pendingPromotion == nil
            && sideToMove == playerColor && !isEngineThinking
    }
    var canSandboxBack: Bool { sandbox?.plies.isEmpty == false }
    var canPlaySandboxMove: Bool { sandbox?.firstMove != nil }

    /// 还没走过任何一步、也没结束的新局。
    var isFreshGame: Bool { moves.isEmpty && !isGameOver }

    var canUndo: Bool { activeMode.allowsAids && !isTrying && !hasResigned && !moves.isEmpty }
    /// 当前显示的局面（真实或试走）轮到玩家、没结束、没有搜索 / 动画在进行。
    private var canActOnShown: Bool {
        guard !isGameOver, pendingPromotion == nil, !isEngineThinking,
              shownBoard.position.sideToMove == playerColor else { return false }
        switch shownBoard.state {
        case .active, .check: break
        default: return false
        }
        return !isTrying || (!isSandboxThinking && !opponentMoveAnimating)
    }

    var canHint: Bool {
        activeMode.allowsAids && hintLevel < 3 && hasChosenDifficulty && !isHintThinking && canActOnShown
    }

    var canCompare: Bool {
        activeMode.allowsAids && hasChosenDifficulty && canActOnShown
    }

    var isGameOver: Bool {
        outcome != nil
    }

    var outcome: GameOutcome? {
        if hasResigned { return .resigned }
        switch board.state {
        case .checkmate(let color):
            return color == playerColor ? .loss : .win
        case .draw(let reason):
            let text: String
            switch reason {
            case .stalemate: text = String(localized: "Stalemate", bundle: .localized)
            case .repetition: text = String(localized: "Threefold repetition", bundle: .localized)
            case .fiftyMoves: text = String(localized: "Fifty-move rule", bundle: .localized)
            case .insufficientMaterial: text = String(localized: "Insufficient material", bundle: .localized)
            case .agreement: text = String(localized: "By agreement", bundle: .localized)
            }
            return .draw(text)
        default:
            return nil
        }
    }

    var pendingPromotion: Move? {
        if hasResigned { return nil }
        if case let .promotion(move) = board.state { return move }
        return nil
    }

    var ratingLine: String {
        if lastRatingDelta > 0 { return "\(rating)  +\(lastRatingDelta)" }
        if lastRatingDelta < 0 { return "\(rating)  \(lastRatingDelta)" }
        return "\(rating)"
    }

    var streakLine: String {
        if winStreak > 0 { return String(localized: "Win streak: \(winStreak)", bundle: .localized) }
        if lossStreak > 0 { return String(localized: "Loss streak: \(lossStreak)", bundle: .localized) }
        return String(localized: "No streak yet", bundle: .localized)
    }

    var recentLine: String {
        recentResults.suffix(8).map(\.mark).joined(separator: " ")
    }

    var safetyNote: String? {
        guard activeMode.allowsAids, !isGameOver, !isEngineThinking, !isSandboxThinking else { return nil }
        if selected != nil, !riskyTargets.isEmpty {
            return String(localized: "Red marks: moving there loses material", bundle: .localized)
        }
        guard let first = dangers.first else { return nil }
        let name = first.kind.localizedName
        let square = first.square.notation
        if dangers.count == 1 {
            return String(localized: "Your \(name) on \(square) can be captured for free", bundle: .localized)
        }
        return String(localized: "Your \(name) on \(square) and \(dangers.count - 1) more can be captured for free", bundle: .localized)
    }

    init() {
        showsSafety = UserDefaults.standard.object(forKey: Self.safetyKey) as? Bool ?? true
        showsRiskyMoves = UserDefaults.standard.bool(forKey: Self.riskyMovesKey)
        showsFeedback = UserDefaults.standard.object(forKey: Self.feedbackKey) as? Bool ?? true
        showsWinChances = UserDefaults.standard.bool(forKey: Self.winChancesKey)
        showsKeyPoints = UserDefaults.standard.object(forKey: Self.keyPointsKey) as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: Self.difficultyKey),
           let difficulty = Difficulty(rawValue: raw) {
            selectedDifficulty = difficulty
            activeDifficulty = difficulty
            hasChosenDifficulty = true
        }
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let mode = GameMode(rawValue: raw) {
            selectedMode = mode
            activeMode = mode
        }
        let stats = Strength.load()
        rating = stats.rating
        winStreak = stats.winStreak
        lossStreak = stats.lossStreak
        lastRatingDelta = stats.lastDelta
        recentResults = stats.recent
        restore()
        refreshSafety()
        #if DEBUG
        applyDebugPreset()
        #endif
    }

    func selectDifficulty(_ difficulty: Difficulty) {
        selectedDifficulty = difficulty
        hasChosenDifficulty = true
        UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        if isFreshGame {
            activeDifficulty = difficulty
        }
        persist()
        requestEngineMoveIfNeeded()
    }

    /// 没开始的新局立刻生效，对局中从下一局起生效（和难度一致）。
    func selectMode(_ mode: GameMode) {
        selectedMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        if isFreshGame {
            activeMode = mode
            clearHint()
        }
        persist()
    }

    var statusText: String {
        if isTrying { return String(localized: "Trying moves", bundle: .localized) }
        if hasResigned { return String(localized: "You resigned · You lost", bundle: .localized) }
        if isEngineThinking { return String(localized: "Computer is thinking", bundle: .localized) }
        switch board.state {
        case .active:
            return sideToMove == playerColor ? String(localized: "Your turn", bundle: .localized) : String(localized: "Computer’s turn", bundle: .localized)
        case .check(let color):
            return color == playerColor ? String(localized: "You are in check", bundle: .localized) : String(localized: "Computer is in check", bundle: .localized)
        case .checkmate(let color):
            return color == playerColor ? String(localized: "Checkmate · You lost", bundle: .localized) : String(localized: "Checkmate · You won", bundle: .localized)
        case .draw(let reason):
            switch reason {
            case .stalemate: return String(localized: "Draw · Stalemate", bundle: .localized)
            case .repetition: return String(localized: "Draw · Threefold repetition", bundle: .localized)
            case .fiftyMoves: return String(localized: "Draw · Fifty-move rule", bundle: .localized)
            case .insufficientMaterial: return String(localized: "Draw · Insufficient material", bundle: .localized)
            case .agreement: return String(localized: "Draw", bundle: .localized)
            }
        case .promotion:
            return String(localized: "Choose a promotion", bundle: .localized)
        }
    }

    func piece(at square: Square) -> Piece? {
        shownBoard.position.piece(at: square)
    }

    func tap(_ square: Square) {
        guard hasChosenDifficulty else { return }
        if pendingPromotion != nil || isGameOver || isEngineThinking { return }
        guard sideToMove == playerColor else { return }
        if isTrying {
            sandboxTap(square)
            return
        }

        if let selected, legalTargets.contains(square) {
            play(from: selected, to: square)
            return
        }

        if let piece = piece(at: square), piece.color == playerColor {
            self.selected = self.selected == square ? nil : square
            return
        }

        selected = nil
    }

    func completePromotion(to kind: Piece.Kind) {
        guard let move = pendingPromotion else { return }
        positionRevision += 1
        var next = board
        let final = next.completePromotion(of: move, to: kind)
        board = next
        if !moves.isEmpty { moves[moves.count - 1] = MoveRecord(move: final, fen: next.position.fen) }
        selected = nil
        persist()
        finishGameIfNeeded()
        startFeedback()
        requestEngineMoveIfNeeded()
        ensureWinChances()
    }

    /// 连按逐级加深：先说想法，再标出要动的子并说为什么，最后画出完整走法、说清原因和胜率。
    /// 试走里也能用（对着沙盒当前局面）。
    func showHint() {
        guard canHint else { return }
        clearThreat()
        hideCandidates()
        if hint != nil {
            hintLevel += 1
            // 到了答案这一级，顺手把前三名候选算好，答案里就能说「只有这一步」。
            if hintLevel >= 3 { ensureCandidates() }
            return
        }
        let snapshot = shownBoard
        let revision = hintRevision
        isHintThinking = true
        hintError = nil
        hintTask = Task {
            defer { if hintRevision == revision { isHintThinking = false } }
            do {
                let analysis = try await analyze(snapshot.position.fen)
                guard hintRevision == revision else { return }
                // 候选已经算过时，以它的第一名为准，箭头和列表一致。
                let uci = candidates?.candidates.first?.uci ?? analysis.bestMove
                guard let applied = MoveExplainer.apply(uci: uci, on: snapshot) else {
                    throw HintError.unavailable
                }
                hint = (applied.played.start, applied.played.end)
                hintUCI = uci
                hintSAN = applied.final.san
                hintLine = analysis.pv.first == uci
                    ? MoveExplainer.sanLine(pv: analysis.pv, from: snapshot, limit: 4)
                    : [applied.final.san]
                hintWin = analysis.pv.first == uci ? analysis.score.map { MoveClassifier.winPercent($0) } : candidates?.candidates.first?.winPercent
                hintExplanation = HintExplanation.make(board: snapshot, uci: uci, analysis: analysis)
                hintLevel = 1
                selected = nil
            } catch is CancellationError {
            } catch {
                if hintRevision == revision { hintError = error.localizedDescription }
            }
        }
    }

    // MARK: - 候选走法

    /// 「候选走法」按钮：显示 / 收起前三名对比。
    func toggleCandidates() {
        if candidatesVisible {
            hideCandidates()
            return
        }
        guard canCompare else { return }
        clearThreat()
        candidatesVisible = true
        hintError = nil
        if candidates != nil {
            selectedCandidate = selectedCandidate ?? 0
        } else {
            ensureCandidates()
        }
    }

    func hideCandidates() {
        if candidatesVisible { candidatesVisible = false }
        if selectedCandidate != nil { selectedCandidate = nil }
    }

    /// 点一步候选：棋盘画出它的箭头，列表下方给出它的变例；再点一次取消。
    func selectCandidate(_ index: Int) {
        guard candidatesVisible, let set = candidates, set.candidates.indices.contains(index) else { return }
        selectedCandidate = selectedCandidate == index ? nil : index
    }

    /// 对当前显示的局面跑一次 MultiPV=3；已经有 / 在算就不重复。
    private func ensureCandidates() {
        guard candidates == nil, !isCandidatesThinking, canCompare else { return }
        let snapshot = shownBoard
        let fen = snapshot.position.fen
        let revision = hintRevision
        let preferred = hintUCI
        isCandidatesThinking = true
        candidateTask = Task { [weak self] in
            do {
                var lines = self?.candidateCache[fen] ?? []
                if lines.isEmpty {
                    let analysis = try await StockfishHintEngine.shared.analyze(
                        fen: fen, movetime: Self.candidateMovetime, multipv: 3
                    )
                    lines = analysis.lines
                    if lines.isEmpty, let score = analysis.score {
                        lines = [EngineLine(multipv: 1, score: score, pv: analysis.pv, depth: analysis.depth)]
                    }
                }
                guard let self, !Task.isCancelled, hintRevision == revision else { return }
                isCandidatesThinking = false
                guard let set = CandidateSet.make(board: snapshot, lines: lines, preferred: preferred) else {
                    throw HintError.unavailable
                }
                if candidateCache.count > 16 { candidateCache.removeAll() }
                candidateCache[fen] = lines
                candidates = set
                if candidatesVisible, selectedCandidate == nil { selectedCandidate = 0 }
            } catch is CancellationError {
            } catch {
                guard let self, hintRevision == revision else { return }
                isCandidatesThinking = false
                hintError = error.localizedDescription
            }
        }
    }

    func undo() {
        guard canUndo else { return }
        // 终局后悔棋：这盘不算结束，已归档的记录撤掉，再结束时重新归档。
        if let id = archiveID {
            GameArchive.shared.delete(id)
            archiveID = nil
            hasRatedThisGame = false
        }
        positionRevision += 1
        cancelEngine()
        cancelHint()
        cancelFeedback()
        clearHint()
        hintError = nil
        // 最后一步是玩家走的就撤一步，是电脑走的连同玩家那步一起撤。
        let lastWasPlayer = (moves.count % 2 == 1) == (playerColor == .white)
        let removing = lastWasPlayer || moves.count < 2 ? 1 : 2
        moves.removeLast(removing)
        board = boardAfter(plies: moves.count)
        selected = nil
        lastPlayed = nil
        persist()
        precomputeAnalysisIfNeeded()
        ensureWinChances()
    }

    func resign() {
        guard !isGameOver else { return }
        positionRevision += 1
        exitSandbox()
        cancelEngine()
        selected = nil
        cancelHint()
        cancelFeedback()
        clearHint()
        hasResigned = true
        refreshSafety()
        finishGameIfNeeded()
    }

    func restart() {
        // 没下完就放弃的对局，走了几步以上也留一份，标记为未完成。
        if !isGameOver { archiveFinishedGame(abandoned: true) }
        positionRevision += 1
        winTask?.cancel()
        winTask = nil
        startEval = nil
        archiveID = nil
        exitSandbox()
        cancelEngine()
        cancelHint()
        cancelFeedback()
        hasResigned = false
        activeDifficulty = selectedDifficulty
        activeMode = selectedMode
        engineError = nil
        hintError = nil
        board = Board()
        moves = []
        selected = nil
        lastPlayed = nil
        clearHint()
        isEngineThinking = false
        hasRatedThisGame = false
        evalRevision += 1
        persist()
        precomputeAnalysisIfNeeded()
        ensureWinChances()
    }

    func resumeIfNeeded() {
        requestEngineMoveIfNeeded()
        precomputeAnalysisIfNeeded()
        ensureWinChances()
        PostGameAnalyzer.shared.resumePending()
    }

    func persistNow() {
        persist()
    }

    private func play(from start: Square, to end: Square) {
        var next = board
        guard let played = next.move(pieceAt: start, to: end) else { return }
        positionRevision += 1
        cancelHint()
        hintError = nil
        board = next
        moves.append(MoveRecord(move: played, fen: next.position.fen))
        selected = nil
        shouldAnimateLastMove = true
        lastPlayed = PlayedMove(from: played)
        persist()
        finishGameIfNeeded()
        if pendingPromotion == nil {
            startFeedback()
            requestEngineMoveIfNeeded()
            ensureWinChances()
        }
    }

    private func requestEngineMoveIfNeeded() {
        guard hasChosenDifficulty, !isEngineThinking else { return }
        guard !isGameOver, pendingPromotion == nil, sideToMove != playerColor else { return }
        isEngineThinking = true
        selected = nil
        clearHint()
        let snapshot = board
        let difficulty = activeDifficulty
        engineError = nil
        // 先让走后点评用完引擎，再轮到对手走子。
        let pendingFeedback = feedbackTask
        engineTask = Task { [weak self] in
            await pendingFeedback?.value
            do {
                let move: EngineMove?
                if let elo = difficulty.engineElo {
                    // 直接 await 引擎 actor，取消任务时会连带停掉 Stockfish 的搜索。
                    let analysis = try await StockfishHintEngine.shared.analyze(fen: snapshot.position.fen, elo: elo)
                    guard let parsed = EngineLANParser.parse(move: analysis.bestMove, for: snapshot.position.sideToMove, in: snapshot.position),
                          snapshot.legalMoves(forPieceAt: parsed.start).contains(parsed.end) else {
                        throw HintError.unavailable
                    }
                    move = EngineMove(from: parsed.start, to: parsed.end, promotion: parsed.promotedPiece?.kind)
                } else {
                    move = await Task.detached(priority: .userInitiated) {
                        SimpleChessEngine.chooseMove(
                            on: snapshot,
                            depth: difficulty == .novice ? 1 : 2,
                            noiseWindow: difficulty == .novice ? 90 : 35
                        )
                    }.value
                }
                try await Task.sleep(for: .milliseconds(420))
                guard let self, !Task.isCancelled else { return }
                self.applyEngineMove(move)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isEngineThinking = false
                self.engineError = error.localizedDescription
            }
        }
    }

    private func applyEngineMove(_ move: EngineMove?) {
        isEngineThinking = false
        guard let move, !isGameOver, sideToMove != playerColor else { return }
        var next = board
        guard let played = next.move(pieceAt: move.from, to: move.to) else { return }
        positionRevision += 1
        var final = played
        if case let .promotion(pending) = next.state {
            final = next.completePromotion(of: pending, to: move.promotion ?? .queen)
        }
        // 重点提醒等对手的走子动画播完再出现。
        markOpponentAnimating()
        board = next
        moves.append(MoveRecord(move: final, fen: next.position.fen))
        shouldAnimateLastMove = true
        lastPlayed = PlayedMove(from: played)
        persist()
        finishGameIfNeeded()
        precomputeAnalysisIfNeeded()
        ensureWinChances()
    }

    private func persist() {
        let snapshot = SavedGame(
            fen: board.position.fen,
            // 旧版本只认 history（每步之前的局面），继续写，方便回退。
            history: moves.isEmpty ? [] : [Board().position.fen] + moves.dropLast().map(\.fen),
            lastFrom: lastPlayed.map { $0.from.notation },
            lastTo: lastPlayed.map { $0.to.notation },
            hasRatedThisGame: hasRatedThisGame,
            hasResigned: hasResigned,
            difficulty: activeDifficulty,
            mode: activeMode,
            moves: moves,
            startEval: startEval,
            archiveID: archiveID
        )
        SavedGame.save(snapshot)
    }

    private func restore() {
        guard let saved = SavedGame.load() else { return }
        guard let position = Position(fen: saved.fen) else { return }
        activeDifficulty = saved.difficulty ?? .novice
        hasResigned = saved.hasResigned ?? false
        activeMode = saved.mode ?? .practice
        moves = saved.moves ?? Self.reconstructMoves(history: saved.history, current: saved.fen)
        // Board(position:) 的状态永远是 active，认不出将死 / 和棋 / 将军；
        // 从头重放着法才能还原真实状态。重放不上就退回到只按局面恢复。
        if let replayed = Self.replay(moves), replayed.position.fen == saved.fen {
            board = replayed
        } else {
            board = Board(position: position)
        }
        startEval = saved.startEval
        archiveID = saved.archiveID
        if let from = saved.lastFrom, let to = saved.lastTo,
           let piece = board.position.piece(at: Square(to)) {
            shouldAnimateLastMove = false
            lastPlayed = PlayedMove(
                id: UUID(),
                from: Square(from),
                to: Square(to),
                piece: piece,
                captured: nil
            )
        }
        hasRatedThisGame = saved.hasRatedThisGame ?? false
        finishGameIfNeeded()
        // 旧版本结束的对局没有存档，补一份。
        if isGameOver, archiveID == nil { archiveFinishedGame() }
    }

    private func finishGameIfNeeded() {
        guard isGameOver, !hasRatedThisGame else { return }
        hasRatedThisGame = true
        // 练习局不计分。
        if activeMode.countsForRating {
            switch outcome {
            case .win: apply(.win)
            case .loss, .resigned: apply(.loss)
            case .draw: apply(.draw)
            case nil: break
            }
        }
        archiveFinishedGame()
        persist()
    }

    private var endReason: GameEndReason? {
        if hasResigned { return .resignation }
        switch board.state {
        case .checkmate: return .checkmate
        case .draw(let reason):
            switch reason {
            case .stalemate: return .stalemate
            case .repetition: return .repetition
            case .fiftyMoves: return .fiftyMoves
            case .insufficientMaterial: return .insufficientMaterial
            case .agreement: return .agreement
            }
        default: return nil
        }
    }

    /// 把这一局存进对局记录。abandoned：没下完被放弃，至少走了 8 个半步才留。
    private func archiveFinishedGame(abandoned: Bool = false) {
        guard archiveID == nil, !moves.isEmpty, !abandoned || moves.count >= 8 else { return }
        let result: GameResult?
        let reason: GameEndReason
        if abandoned {
            result = nil
            reason = .abandoned
        } else {
            guard let outcome, let ended = endReason else { return }
            switch outcome {
            case .win: result = .win
            case .loss, .resigned: result = .loss
            case .draw: result = .draw
            }
            reason = ended
            // 终局局面不能搜索，直接补上固定评估，胜率条 / 曲线才完整。
            if let eval = ended.terminalEval, moves[moves.count - 1].eval == nil {
                moves[moves.count - 1].eval = eval
                evalRevision += 1
            }
        }
        let rated = activeMode.countsForRating && !abandoned
        let record = GameRecord(
            id: UUID().uuidString,
            date: Date(),
            mode: activeMode,
            difficulty: activeDifficulty,
            result: result,
            reason: reason,
            ratingDelta: rated ? lastRatingDelta : nil,
            ratingAfter: rated ? rating : nil,
            startEval: startEval,
            moves: moves
        )
        GameArchive.shared.add(record)
        guard !abandoned else { return }
        archiveID = record.id
        PostGameAnalyzer.shared.enqueue(record.id)
    }

    private func apply(_ result: GameResult) {
        recentResults.append(result)
        if recentResults.count > 12 {
            recentResults.removeFirst(recentResults.count - 12)
        }
        switch result {
        case .win:
            winStreak += 1
            lossStreak = 0
            lastRatingDelta = min(28, 8 + (winStreak - 1) * 4)
        case .loss:
            lossStreak += 1
            winStreak = 0
            lastRatingDelta = lossStreak >= 3 ? -(8 + (lossStreak - 3) * 4) : 0
        case .draw:
            winStreak = 0
            lastRatingDelta = 0
        }
        rating = min(Strength.maxRating, max(Strength.minRating, rating + lastRatingDelta))
        Strength.save(
            rating: rating,
            winStreak: winStreak,
            lossStreak: lossStreak,
            lastDelta: lastRatingDelta,
            recent: recentResults
        )
    }

    /// 安全标记基于当前显示的局面，试走时就是沙盒局面。
    private func refreshSafety() {
        guard !isGameOver, activeMode.allowsAids else {
            dangers = []
            riskyTargets = [:]
            return
        }
        let shown = shownBoard
        dangers = showsSafety ? ThreatAnalyzer.dangers(for: playerColor, in: shown.position) : []
        var risks: [Square: ThreatAnalyzer.MoveRisk] = [:]
        if showsRiskyMoves, let selected, shown.position.sideToMove == playerColor {
            for target in shown.legalMoves(forPieceAt: selected) {
                risks[target] = ThreatAnalyzer.risk(of: shown, from: selected, to: target)
            }
        }
        riskyTargets = risks
    }

    // MARK: - 走后点评

    /// 玩家的局面在轮到他时就预先分析好（缓存），走完后点评、提示都直接用。
    private func precomputeAnalysisIfNeeded() {
        guard activeMode.allowsAids, hasChosenDifficulty, !isGameOver, pendingPromotion == nil,
              sideToMove == playerColor else { return }
        let fen = board.position.fen
        guard analyses.peek(fen) == nil else { return }
        Task { _ = try? await analyze(fen) }
    }

    /// 玩家刚走完一步（moves 最后一项）：分析走后局面，对比走前评分给出评价。
    private func startFeedback() {
        cancelFeedback()
        guard activeMode.allowsAids, showsFeedback, let record = moves.last, !record.from.isEmpty else { return }
        let index = moves.count
        let number = (index + 1) / 2
        let san = record.san ?? ""
        switch board.state {
        case .checkmate:
            feedback = MoveFeedback(verdict: .best, reason: nil, better: nil, moveNumber: number, san: san)
            feedbackPly = index
            return
        case .draw:
            return
        default:
            break
        }
        let before = boardAfter(plies: index - 1)
        let fenBefore = before.position.fen
        let fenAfter = record.fen
        isFeedbackPending = true
        feedbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let scoreBefore = try await analyze(fenBefore)
                let scoreAfter = try await analyze(fenAfter)
                // 期间悔棋 / 重开 / 又走了新的一步，就丢弃。
                guard !Task.isCancelled, moves.count >= index, moves[index - 1].fen == fenAfter else { return }
                feedback = MoveExplainer.feedback(
                    boardBefore: before,
                    from: Square(record.from),
                    to: Square(record.to),
                    promotion: record.promotion,
                    before: scoreBefore,
                    after: scoreAfter,
                    san: san,
                    moveNumber: number
                )
                feedbackPly = index
                isFeedbackPending = false
            } catch {
                // 点评拿不到就不显示，不打扰对局。
                if !Task.isCancelled { isFeedbackPending = false }
            }
        }
    }

    private func cancelFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        feedback = nil
        isFeedbackPending = false
        analyses.cancelAll()
    }

    // MARK: - 评估记录与实时胜率

    /// 取局面评估（走缓存），并记到对应的着法记录里，赛后复盘直接复用。
    private func analyze(_ fen: String, background: Bool = false) async throws -> EngineAnalysis {
        let analysis = try await analyses.analysis(fen: fen, background: background)
        recordEval(fen: fen, analysis: analysis)
        // 轮到玩家的局面分析好了，杀棋信息可能补充重点提醒。
        refreshKeyPoint()
        return analysis
    }

    private func recordEval(fen: String, analysis: EngineAnalysis) {
        guard analysis.score != nil else { return }
        let eval = PositionEval(analysis)
        if let index = moves.lastIndex(where: { $0.fen == fen }) {
            guard moves[index].eval != eval else { return }
            moves[index].eval = eval
        } else if fen == GameRecord.startFEN {
            guard startEval != eval else { return }
            startEval = eval
        } else {
            return
        }
        evalRevision += 1
        persist()
    }

    /// 每个局面（0 = 初始）的评估。
    var evals: [PositionEval?] { GameAnalysis.evals(startEval: startEval, moves: moves) }
    /// 玩家的胜率曲线，每个局面一项。
    var winSeries: [Double?] { GameAnalysis.winSeries(evals) }
    /// 最新胜率；isCurrent 为 false 说明当前局面还在计算，显示的是上一个局面的值。
    var winLatest: (value: Double, delta: Double?, isCurrent: Bool)? { GameAnalysis.latestWin(winSeries) }

    /// 打开「显示胜率」时，保证当前局面（以及之前的空缺）都有评估：当前局面最优先，其余后台慢慢补。
    /// 评估按 FEN 记录，所以走了新的一步后旧结果不会套到新局面上。
    private func ensureWinChances() {
        winTask?.cancel()
        winTask = nil
        guard showsWinChances, hasChosenDifficulty, !isGameOver, pendingPromotion == nil else { return }
        let missing = GameAnalysis.missingPlies(evals)
        guard !missing.isEmpty else { return }
        let fens = missing.reversed().map { $0 == 0 ? GameRecord.startFEN : moves[$0 - 1].fen }
        let aids = activeMode.allowsAids
        winTask = Task { [weak self] in
            for (offset, fen) in fens.enumerated() {
                guard let self, !Task.isCancelled else { return }
                do {
                    // 练习局当前局面和点评共用前台队列；其余、以及对战局一律后台，对手走子优先。
                    _ = try await self.analyze(fen, background: !(aids && offset == 0))
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - 重点提醒与「对方想干什么」

    /// 重点提醒能显示：练习模式、轮到玩家、对手没在想 / 没在走子动画中。
    var keyPointVisible: Bool {
        activeMode.allowsAids && showsKeyPoints && hasChosenDifficulty && !isGameOver && pendingPromotion == nil
            && shownBoard.position.sideToMove == playerColor
            && !isEngineThinking && !isSandboxThinking && !opponentMoveAnimating
    }

    var keyPointText: String? {
        keyPoint.map { CoachExplainer.text(for: $0, viewer: playerColor) }
    }

    /// 基于当前显示的局面（试走时是沙盒局面）重新挑一条。杀棋信息取自已缓存的分析。
    private func refreshKeyPoint() {
        guard activeMode.allowsAids, showsKeyPoints, !isGameOver else {
            keyPoint = nil
            return
        }
        let shown = shownBoard.position
        guard shown.sideToMove == playerColor else {
            keyPoint = nil
            return
        }
        let analysis = analyses.peek(shown.fen)
        // 安全标记开着时，会被白吃的子已经在底部那行说了，这里不重复。
        let covered = showsSafety
        let point = CoachExplainer.keyPoint(position: shown, viewer: playerColor, analysis: analysis) {
            covered && $0.side != self.playerColor && $0.victim != nil
        }
        if point != keyPoint { keyPoint = point }
    }

    var canShowThreat: Bool {
        activeMode.allowsAids && hasChosenDifficulty && !isGameOver && pendingPromotion == nil
            && shownBoard.position.sideToMove == playerColor
            && !isEngineThinking && !isSandboxThinking && !opponentMoveAnimating
    }

    /// 对方想干什么：把对方当成轮到它走，问引擎它的最佳着法，红箭头 + 一句解释。再按一次收起。
    func showThreat() {
        if threat != nil || isThreatThinking {
            clearThreat()
            return
        }
        guard canShowThreat else { return }
        hideCandidates()
        let shown = shownBoard
        threatError = nil
        // 正被将军：威胁就是将军本身，不用搜索。
        if let check = CoachExplainer.checkThreat(in: shown.position, viewer: playerColor) {
            threat = check
            return
        }
        guard let nullBoard = CoachExplainer.nullMove(shown) else { return }
        let revision = threatRevision
        let viewer = playerColor
        isThreatThinking = true
        threatTask = Task { [weak self] in
            do {
                let analysis = try await StockfishHintEngine.shared.analyze(fen: nullBoard.position.fen, movetime: Self.threatMovetime)
                guard let self, !Task.isCancelled, threatRevision == revision else { return }
                isThreatThinking = false
                guard let result = CoachExplainer.threat(board: nullBoard, analysis: analysis, viewer: viewer) else {
                    throw HintError.unavailable
                }
                threat = result
            } catch is CancellationError {
            } catch {
                guard let self, threatRevision == revision else { return }
                isThreatThinking = false
                threatError = error.localizedDescription
            }
        }
    }

    /// 收起结果；正在搜索的会被取消。
    func clearThreat() {
        invalidateThreat()
    }

    /// 局面变了：作废结果和还在跑的搜索。
    private func invalidateThreat() {
        threatRevision += 1
        threatTask?.cancel()
        threatTask = nil
        if threat != nil { threat = nil }
        if isThreatThinking { isThreatThinking = false }
        if threatError != nil { threatError = nil }
    }

    // MARK: - 试走

    func setTrying(_ on: Bool) {
        if on {
            guard canTry, !isTrying else { return }
            selected = nil
            shouldAnimateLastMove = false
            sandboxError = nil
            sandbox = SandboxState(root: board)
        } else {
            exitSandbox()
        }
    }

    /// 回到真实局面，沙盒里的内容全部丢弃。
    private func exitSandbox() {
        sandboxRevision += 1
        sandboxTask?.cancel()
        sandboxTask = nil
        isSandboxThinking = false
        sandboxError = nil
        guard sandbox != nil else { return }
        sandbox = nil
        selected = nil
        shouldAnimateLastMove = false
    }

    /// 退一步：撤掉最近一次试走（连同对方的应对）。
    func sandboxBack() {
        guard var state = sandbox, !state.plies.isEmpty else { return }
        sandboxRevision += 1
        sandboxTask?.cancel()
        sandboxTask = nil
        isSandboxThinking = false
        sandboxError = nil
        while let last = state.plies.popLast(), last.isReply {}
        sandbox = state
        selected = nil
        shouldAnimateLastMove = false
    }

    /// 重新试：回到进入试走时的局面，仍留在试走里。
    func sandboxReset() {
        guard var state = sandbox else { return }
        sandboxRevision += 1
        sandboxTask?.cancel()
        sandboxTask = nil
        isSandboxThinking = false
        sandboxError = nil
        state.plies = []
        sandbox = state
        selected = nil
        shouldAnimateLastMove = false
    }

    /// 这步就走它：只把试走的第一步提交到真实对局，之后对手照常应对。
    func playSandboxMove() {
        guard let first = sandbox?.firstMove else { return }
        exitSandbox()
        play(from: first.from, to: first.to)
    }

    private func sandboxTap(_ square: Square) {
        guard let state = sandbox, !isSandboxThinking, state.board.position.sideToMove == playerColor else { return }
        if let selected, legalTargets.contains(square) {
            sandboxPlay(from: selected, to: square)
            return
        }
        if let piece = state.board.position.piece(at: square), piece.color == playerColor {
            selected = selected == square ? nil : square
            return
        }
        selected = nil
    }

    private func sandboxPlay(from start: Square, to end: Square) {
        guard var state = sandbox else { return }
        var next = state.board
        guard var played = next.move(pieceAt: start, to: end) else { return }
        let animated = PlayedMove(from: played)
        // 试走里升变直接升后。
        if case let .promotion(pending) = next.state {
            played = next.completePromotion(of: pending, to: .queen)
        }
        var note: SandboxNote?
        switch next.state {
        case .checkmate: note = .checkmatesOpponent
        case .draw: note = .draw
        default: break
        }
        state.plies.append(SandboxPly(board: next, played: animated, san: played.san, isReply: false, note: note))
        sandboxRevision += 1
        selected = nil
        shouldAnimateLastMove = true
        sandboxError = nil
        sandbox = state
        if note == nil { requestSandboxReply() }
    }

    /// 兜底：视图没来得及清除时，2 秒后自动解除。
    private func markOpponentAnimating() {
        opponentMoveAnimating = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.opponentMoveAnimating = false
        }
    }

    /// 让引擎（满力）为对手选应对，走在沙盒上并解释。
    private func requestSandboxReply() {
        guard let state = sandbox else { return }
        let boardNow = state.board
        let fen = boardNow.position.fen
        let revision = sandboxRevision
        let evalBefore = state.plies.reversed().lazy.compactMap { ply -> EngineScore? in
            if case let .reply(note)? = ply.note { return note.evalAfter }
            return nil
        }.first ?? analyses.peek(state.root.position.fen)?.score
        isSandboxThinking = true
        sandboxTask = Task { [weak self] in
            do {
                let analysis = try await StockfishHintEngine.shared.analyze(fen: fen, movetime: Self.sandboxMovetime)
                guard let self, !Task.isCancelled, sandboxRevision == revision, var state = sandbox else { return }
                isSandboxThinking = false
                guard let applied = MoveExplainer.apply(uci: analysis.bestMove, on: boardNow) else {
                    throw HintError.unavailable
                }
                let note = MoveExplainer.replyNote(
                    boardBeforeReply: boardNow,
                    reply: applied,
                    analysis: analysis,
                    evalBefore: evalBefore,
                    player: playerColor
                )
                state.plies.append(SandboxPly(
                    board: applied.board,
                    played: PlayedMove(from: applied.played),
                    san: applied.final.san,
                    isReply: true,
                    note: .reply(note)
                ))
                shouldAnimateLastMove = true
                markOpponentAnimating()
                sandbox = state
            } catch is CancellationError {
            } catch {
                guard let self, sandboxRevision == revision else { return }
                isSandboxThinking = false
                sandboxError = error.localizedDescription
            }
        }
    }

    /// 局面变了（或收起提示）：提示、候选和还在跑的搜索全部作废。
    private func clearHint() {
        hintRevision += 1
        cancelHint()
        candidateTask?.cancel()
        candidateTask = nil
        hint = nil
        hintUCI = nil
        hintSAN = nil
        hintLine = []
        hintLevel = 0
        hintExplanation = nil
        hintWin = nil
        if candidates != nil { candidates = nil }
        if isCandidatesThinking { isCandidatesThinking = false }
        if candidatesVisible { candidatesVisible = false }
        if selectedCandidate != nil { selectedCandidate = nil }
    }

    private func cancelHint() {
        hintTask?.cancel()
        hintTask = nil
        isHintThinking = false
    }

    /// 走完前 plies 步后的局面。
    private func boardAfter(plies: Int) -> Board {
        guard plies > 0, plies <= moves.count else { return Board() }
        if let replayed = Self.replay(Array(moves.prefix(plies))) { return replayed }
        guard let position = Position(fen: moves[plies - 1].fen) else { return Board() }
        return Board(position: position)
    }

    /// 从初始局面把着法记录依次走一遍，得到带真实状态（将军 / 将死 / 和棋 / 重复局面）的棋盘。
    /// 最后一步是升变且还没选子（记录里没有升变棋子）时，停在待选升变的状态。
    nonisolated static func replay(_ records: [MoveRecord]) -> Board? {
        var board = Board()
        for (index, record) in records.enumerated() {
            guard !record.from.isEmpty,
                  board.move(pieceAt: Square(record.from), to: Square(record.to)) != nil else { return nil }
            if case let .promotion(pending) = board.state {
                if record.promotion == nil, index == records.count - 1 { break }
                let kind: Piece.Kind
                switch record.promotion {
                case "r": kind = .rook
                case "b": kind = .bishop
                case "n": kind = .knight
                default: kind = .queen
                }
                _ = board.completePromotion(of: pending, to: kind)
            }
        }
        return board
    }

    /// 旧存档只有每步之前的局面，通过试走所有合法着法还原出着法记录。
    private static func reconstructMoves(history: [String], current: String) -> [MoveRecord] {
        let fens = history + [current]
        var records: [MoveRecord] = []
        for index in 0..<history.count {
            let target = fens[index + 1]
            var found: MoveRecord?
            if let position = Position(fen: fens[index]) {
                let board = Board(position: position)
                search: for piece in position.pieces where piece.color == position.sideToMove {
                    for end in board.legalMoves(forPieceAt: piece.square) {
                        var next = board
                        guard let played = next.move(pieceAt: piece.square, to: end) else { continue }
                        if next.position.fen == target {
                            found = MoveRecord(move: played, fen: target)
                            break search
                        }
                        if case let .promotion(pending) = next.state {
                            for kind in [Piece.Kind.queen, .rook, .bishop, .knight] {
                                var promoted = next
                                let final = promoted.completePromotion(of: pending, to: kind)
                                if promoted.position.fen == target {
                                    found = MoveRecord(move: final, fen: target)
                                    break search
                                }
                            }
                        }
                    }
                }
            }
            records.append(found ?? MoveRecord(from: "", to: "", fen: target))
        }
        return records
    }

    private func cancelEngine() {
        engineTask?.cancel()
        engineTask = nil
        isEngineThinking = false
    }
}

extension PlayedMove {
    init(from move: Move) {
        var captured: Piece?
        if case let .capture(piece) = move.result {
            captured = piece
        }
        self.init(
            id: UUID(),
            from: move.start,
            to: move.end,
            piece: move.promotedPiece ?? move.piece,
            captured: captured
        )
    }
}

private struct SavedGame: Codable {
    var fen: String
    var history: [String]
    var lastFrom: String?
    var lastTo: String?
    var hasRatedThisGame: Bool?
    var hasResigned: Bool?
    var difficulty: Difficulty?
    var mode: GameMode?
    var moves: [MoveRecord]?
    var startEval: PositionEval?
    var archiveID: String?

    private static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = folder.appendingPathComponent("nookchess", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("saved-game.json")
    }

    static func load() -> SavedGame? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedGame.self, from: data)
    }

    static func save(_ game: SavedGame) {
        guard let data = try? JSONEncoder().encode(game) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension Square {
    static func at(row: Int, col: Int) -> Square {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        return Square("\(files[col])\(8 - row)")
    }

    nonisolated var notation: String { "\(file.rawValue)\(rank.value)" }
    var row: Int { 8 - rank.value }
    var col: Int { file.number - 1 }
}

extension Piece.Kind {
    var assetKind: PieceKind {
        switch self {
        case .pawn: .pawn
        case .knight: .knight
        case .bishop: .bishop
        case .rook: .rook
        case .queen: .queen
        case .king: .king
        }
    }
}

extension Piece.Kind {
    var localizedName: String {
        switch self {
        case .pawn: String(localized: "Pawn", bundle: .localized)
        case .knight: String(localized: "Knight", bundle: .localized)
        case .bishop: String(localized: "Bishop", bundle: .localized)
        case .rook: String(localized: "Rook", bundle: .localized)
        case .queen: String(localized: "Queen", bundle: .localized)
        case .king: String(localized: "King", bundle: .localized)
        }
    }
}

extension Piece.Color {
    var side: SideColor { self == .white ? .white : .black }
}

extension GameResult {
    nonisolated var mark: String {
        switch self {
        case .win: String(localized: "W", bundle: .localized)
        case .loss: String(localized: "L", bundle: .localized)
        case .draw: String(localized: "D", bundle: .localized)
        }
    }
}

enum Strength {
    static let defaultRating = 600
    static let minRating = 400
    static let maxRating = 1800

    private static let ratingKey = "nookchess.rating"
    private static let winKey = "nookchess.winStreak"
    private static let lossKey = "nookchess.lossStreak"
    private static let deltaKey = "nookchess.lastRatingDelta"
    private static let recentKey = "nookchess.recentResults"

    struct Stats {
        var rating: Int
        var winStreak: Int
        var lossStreak: Int
        var lastDelta: Int
        var recent: [GameResult]
    }

    static func load() -> Stats {
        let defaults = UserDefaults.standard
        let rating = defaults.object(forKey: ratingKey) == nil
            ? defaultRating
            : defaults.integer(forKey: ratingKey)
        var recent: [GameResult] = []
        if let data = defaults.data(forKey: recentKey) {
            recent = (try? JSONDecoder().decode([GameResult].self, from: data)) ?? []
        }
        return Stats(
            rating: rating,
            winStreak: defaults.integer(forKey: winKey),
            lossStreak: defaults.integer(forKey: lossKey),
            lastDelta: defaults.integer(forKey: deltaKey),
            recent: recent
        )
    }

    static func save(
        rating: Int,
        winStreak: Int,
        lossStreak: Int,
        lastDelta: Int,
        recent: [GameResult]
    ) {
        let defaults = UserDefaults.standard
        defaults.set(rating, forKey: ratingKey)
        defaults.set(winStreak, forKey: winKey)
        defaults.set(lossStreak, forKey: lossKey)
        defaults.set(lastDelta, forKey: deltaKey)
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: recentKey)
        }
    }
}

#if DEBUG
extension ChessGameStore {
    /// 仅调试：用启动参数 `-nookchess.debugPreset <名字>` 预置界面状态，方便截图。
    func applyDebugPreset() {
        let from = Square("d2"), to = Square("d3")
        let preset = UserDefaults.standard.string(forKey: "nookchess.debugPreset") ?? ""
        switch preset {
        case "hint1", "hint2", "hint3", "cand", "cand2", "hint1-sb", "hint2-sb", "hint3-sb", "cand-sb":
            // 真实引擎：摆好局面，按几次「提示」，再打开候选列表；`-nookchess.debugFEN` 可换局面。
            let fen = UserDefaults.standard.string(forKey: "nookchess.debugFEN")
                ?? "rnbqkbnr/pppp1ppp/8/4p3/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 2"
            debugSetPosition(fen)
            let sandboxed = preset.hasSuffix("-sb")
            if sandboxed {
                setTrying(true)
                sandboxPlay(from: Square("d2"), to: Square("d4"))
            }
            let presses = preset.hasPrefix("cand") ? 3 : Int(String(preset.dropFirst(4).prefix(1)))!
            DispatchQueue.main.asyncAfter(deadline: .now() + (sandboxed ? 4 : 1.5)) { [self] in
                Task {
                    for _ in 0..<presses {
                        showHint()
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                    if preset.hasPrefix("cand") {
                        toggleCandidates()
                        try? await Task.sleep(for: .seconds(2))
                        if preset == "cand2" { selectCandidate(1) }
                    }
                }
            }
        case "multipv-probe":
            Task { await runMultiPVProbe() }
        case "blunder":
            feedback = MoveFeedback(
                verdict: .blunder,
                reason: .losesPiece(.knight),
                better: BetterMove(from: from, to: to, san: "d3"),
                moveNumber: 1, san: "e4", winBefore: 52, winAfter: 30
            )
        case "good":
            feedback = MoveFeedback(verdict: .good, reason: nil, better: nil, moveNumber: 1, san: "e4", winBefore: 53, winAfter: 51)
        case "try":
            setTrying(true)
        case "trymove":
            setTrying(true)
            sandboxPlay(from: Square("f3"), to: Square("g5"))
        case "tryplay":
            // 试走 d3，等对方应对后提交，验证提交到真实对局。
            setTrying(true)
            sandboxPlay(from: from, to: to)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                playSandboxMove()
            }
        case "keypoint":
            // 白方的马和 g2 兵都没人保护（黑后在 g5）。
            debugSetPosition("r1b1kbnr/pppp1ppp/8/4N1q1/2BnP3/8/PPPP1PPP/RNBQK2R w KQkq - 3 5")
        case "keypoint-opp":
            // 1.Nf3 e5：黑方 e5 的兵没人保护。
            debugSetPosition("rnbqkbnr/pppp1ppp/8/4p3/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 2")
        case "keypoint-mate":
            debugSetPosition("r5k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1")
        case "threat", "threat-mate", "threat-check":
            let fens = [
                "threat": "r1b1kbnr/pppp1ppp/8/4N1q1/2BnP3/8/PPPP1PPP/RNBQK2R w KQkq - 3 5",
                "threat-mate": "r5k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1",
                "threat-check": "rnbqk1nr/pppp1ppp/8/4p3/1b1P4/8/PPP1PPPP/RNBQKBNR w KQkq - 1 3",
            ]
            debugSetPosition(fens[preset]!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in showThreat() }
        case "probe":
            Task { await runFeedbackProbe() }
        case "over-loss", "over-loss-live":
            debugFinish(Self.debugLoss, resign: true, withEvals: preset != "over-loss-live")
        case "over-win":
            debugFinish(Self.debugWin, resign: false, withEvals: true)
        case "over-draw":
            debugFinish(Self.debugStalemate, resign: false, withEvals: true)
        case "history", "review", "review-history":
            debugSeedArchive()
        case "wc-mid":
            // 对局进行中的状态：开局几步，带评估，便于看胜率条 / 趋势图。
            debugResume(Self.debugLoss.prefix(12))
            feedback = MoveFeedback(
                verdict: .blunder, reason: .losesPiece(.knight),
                better: BetterMove(from: Square("b1"), to: Square("c3"), san: "Nc3"),
                moveNumber: 6, san: "Nxf7", winBefore: 47, winAfter: 25
            )
            feedbackPly = moves.count - 1
        default:
            break
        }
    }

    /// 直接放一个指定局面（白方走），没有着法记录。
    private func debugSetPosition(_ fen: String) {
        guard let position = Position(fen: fen) else { return }
        board = Board(position: position)
        moves = []
        startEval = nil
        lastPlayed = nil
        selected = nil
    }

    // MARK: 调试数据：脚本化的对局 + 手写评估（白方视角）

    private enum DebugEval {
        case cp(Int), mate(Int)
        var white: EngineScore {
            switch self {
            case let .cp(v): .centipawns(v)
            case let .mate(v): .mate(v)
            }
        }
    }

    private struct DebugGame {
        let ucis: [String]
        /// 每个局面（含初始）的白方视角评估。
        let evals: [DebugEval]
        /// 玩家走了坏棋的局面里，引擎认为更好的着法。
        var betters: [Int: String] = [:]

        func prefix(_ count: Int, flat: Bool = false) -> DebugGame {
            DebugGame(
                ucis: Array(ucis.prefix(count)),
                evals: flat ? Array(repeating: .cp(0), count: evals.count) : evals,
                betters: flat ? [:] : betters
            )
        }
    }

    private static let debugLoss = DebugGame(
        ucis: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "f3g5", "d7d5", "e4d5", "f6d5", "g5f7", "e8f7", "d1f3", "f7e6", "b1c3", "c6b4", "f3e4", "c7c6"],
        evals: [30, 30, 35, 35, 30, 35, 30, -35, -45, -30, -35, -300, -310, -330, -320, -420, -460, -900, -950].map(DebugEval.cp),
        betters: [6: "d2d3", 10: "b1c3", 16: "a2a3"]
    )

    /// 萨姆·劳埃德的 10 步逼和：白方一路大优，最后一步走成和棋。
    private static let debugStalemate = DebugGame(
        ucis: ["e2e3", "a7a5", "d1h5", "a8a6", "h5a5", "h7h5", "h2h4", "a6h6", "a5c7", "f7f6", "c7d7", "e8f7", "d7b7", "d8d3", "b7b8", "d3h7", "b8c8", "f7g6", "c8e6"],
        evals: [0, 10, 10, 20, 25, 150, 160, 200, 200, 450, 450, 700, 700, 900, 900, 950, 950, 990, 990].map(DebugEval.cp)
    )

    private static let debugWin = DebugGame(
        ucis: ["e2e4", "e7e5", "g1f3", "d7d6", "f1c4", "c8g4", "b1c3", "g7g6", "f3e5", "g4d1", "c4f7", "e8e7", "c3d5"],
        evals: [.cp(30), .cp(30), .cp(35), .cp(35), .cp(30), .cp(40), .cp(35), .cp(40), .cp(45), .cp(350), .mate(3), .mate(2), .mate(1), .mate(1)]
    )

    private func debugBuild(_ game: DebugGame, withEvals: Bool) -> (Board, [MoveRecord]) {
        var board = Board()
        var records: [MoveRecord] = []
        for (index, uci) in game.ucis.enumerated() {
            guard let applied = MoveExplainer.apply(uci: uci, on: board) else { break }
            board = applied.board
            var record = MoveRecord(move: applied.final, fen: board.position.fen)
            if withEvals, game.evals.indices.contains(index + 1) {
                record.eval = debugEval(game, ply: index + 1)
            }
            records.append(record)
        }
        return (board, records)
    }

    private func debugEval(_ game: DebugGame, ply: Int) -> PositionEval {
        let white = game.evals[ply].white
        let mover = ply % 2 == 0 ? white : white.flipped
        // 轮到玩家的局面：推荐着法 = 实际走的那步，除非指定了更好的。
        let best = ply < game.ucis.count ? (game.betters[ply] ?? game.ucis[ply]) : nil
        return PositionEval(score: mover, best: best, pv: best.map { [$0] }, depth: 14)
    }

    /// 把对局放到棋盘上并立即结束，走正常的结算 / 归档流程。
    private func debugFinish(_ game: DebugGame, resign: Bool, withEvals: Bool) {
        let (board, records) = debugBuild(game, withEvals: withEvals)
        self.board = board
        moves = records
        startEval = withEvals ? debugEval(game, ply: 0) : nil
        hasResigned = resign
        hasRatedThisGame = false
        archiveID = nil
        lastPlayed = nil
        evalRevision += 1
        finishGameIfNeeded()
    }

    /// 进行中的对局（轮到玩家），带已有评估。
    private func debugResume(_ game: DebugGame) {
        let (board, records) = debugBuild(game, withEvals: true)
        self.board = board
        moves = records
        startEval = debugEval(game, ply: 0)
        evalRevision += 1
    }

    /// 往存档里放几盘不同结果的示例对局（id 以 debug- 开头），复盘 / 列表截图用。
    private func debugSeedArchive() {
        for old in GameArchive.shared.records where old.id.hasPrefix("debug-") { GameArchive.shared.delete(old.id) }
        func make(_ id: String, _ game: DebugGame, _ result: GameResult?, _ reason: GameEndReason, mode: GameMode, level: Difficulty, delta: Int?, days: Double) -> GameRecord {
            let (_, records) = debugBuild(game, withEvals: true)
            return GameRecord(
                id: id, date: Date().addingTimeInterval(-86_400 * days), mode: mode, difficulty: level,
                result: result, reason: reason, ratingDelta: delta, ratingAfter: delta.map { 600 + $0 },
                startEval: debugEval(game, ply: 0), moves: records
            )
        }
        let archive = GameArchive.shared
        archive.add(make("debug-unfinished", Self.debugLoss.prefix(10), nil, .abandoned, mode: .practice, level: .novice, delta: nil, days: 3))
        archive.add(make("debug-draw", Self.debugStalemate, .draw, .stalemate, mode: .battle, level: .practiced, delta: 0, days: 2))
        archive.add(make("debug-win", Self.debugWin, .win, .checkmate, mode: .battle, level: .beginner, delta: 8, days: 1))
        archive.add(make("debug-loss", Self.debugLoss, .loss, .resignation, mode: .practice, level: .beginner, delta: nil, days: 0))
    }

    /// 仅调试：对几个局面跑 MultiPV=3，确认三条线各不相同，且之后的单线搜索不受影响。
    func runMultiPVProbe() async {
        let url = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-feiandxs-workspace-ichess/f1acede5-ef41-4382-91e9-a0965c5c7938/scratchpad/multipv.log")
        try? "".write(to: url, atomically: false, encoding: .utf8)
        func log(_ text: String) {
            Swift.print(text)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write((text + "\n").data(using: .utf8)!); try? handle.close()
            }
        }
        let fens = [
            "rnbqkbnr/pppp1ppp/8/4p3/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 2",
            "r1b1kbnr/pppp1ppp/8/4N1q1/2BnP3/8/PPPP1PPP/RNBQK2R w KQkq - 3 5",
            "r5k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1",
        ]
        let engine = StockfishHintEngine.shared
        for fen in fens {
            do {
                let started = Date()
                let multi = try await engine.analyze(fen: fen, movetime: Self.candidateMovetime, multipv: 3)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let board = Board(position: Position(fen: fen)!)
                let sans = multi.lines.map { MoveExplainer.sanLine(pv: $0.pv, from: board, limit: 4).joined(separator: " ") }
                log("MULTI \(fen) ms=\(ms) lines=\(multi.lines.count) distinctFirst=\(Set(multi.lines.compactMap { $0.pv.first }).count) best=\(multi.bestMove)")
                for (line, san) in zip(multi.lines, sans) { log("   #\(line.multipv) d\(line.depth) \(line.score) \(san)") }
                if let set = CandidateSet.make(board: board, lines: multi.lines) {
                    log("   verdict=\(set.verdict) labels=\(set.candidates.map(\.label)) wins=\(set.candidates.map { Int($0.winPercent) })")
                    for c in set.candidates { log("   \(c.san): \(c.reason(mover: .white)) | steps=\(c.line.count)") }
                }
                let single = try await engine.analyze(fen: fen, movetime: 300)
                log("SINGLE lines=\(single.lines.count) best=\(single.bestMove) pv=\(single.pv.prefix(3))")
                let again = try await engine.analyze(fen: fen, movetime: 300, multipv: 3)
                log("AGAIN lines=\(again.lines.count)")
            } catch {
                log("ERR \(error)")
            }
        }
        log("DONE")
    }

    /// 仅调试：走 1.e4 / 2.Nf3，打印真实引擎评分和点评结果。
    func runFeedbackProbe() async {
        func print(_ text: String) {
            Swift.print(text)
            let url = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-feiandxs-workspace-ichess/f1acede5-ef41-4382-91e9-a0965c5c7938/scratchpad/probe.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write((text + "\n").data(using: .utf8)!); try? handle.close()
            } else {
                try? (text + "\n").write(to: url, atomically: false, encoding: .utf8)
            }
        }
        func dump(_ tag: String) {
            let f = feedback.map { "\($0.verdict) reason=\(String(describing: $0.reason)) better=\($0.better?.san ?? "-")" } ?? "nil"
            print("PROBE[\(tag)] moves=\(moves.count) feedback=\(f) head=\(feedback?.headline ?? "-") | \(feedback?.winLine ?? "-") series=\(winSeries.map { $0.map { String(Int($0)) } ?? "_" }.joined(separator: ",")) thinking=\(isEngineThinking)")
            fflush(stdout)
        }
        try? await Task.sleep(for: .seconds(2))
        restart()
        try? await Task.sleep(for: .seconds(2))
        tap(Square("e2")); tap(Square("e4"))
        for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(700)); dump("t") }
        tap(Square("g1")); tap(Square("f3"))
        for _ in 0..<8 { try? await Task.sleep(for: .milliseconds(700)); dump("nf3") }
    }
}
#endif
