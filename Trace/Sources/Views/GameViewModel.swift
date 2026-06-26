import SwiftUI
import SpriteKit

/// Owns one level's run: the scene + engine, the HUD clock, and what happens on a win
/// (record the personal best locally, then fire the score to the leaderboard). The engine is
/// the source of truth; this just mirrors its events for SwiftUI.
@MainActor
final class GameViewModel: ObservableObject {
    @Published var elapsedMs = 0
    @Published var backtracks = 0
    @Published var started = false
    @Published var won = false
    @Published var result: WinResult?
    @Published var onlineRank: String?      // filled in async after submit

    struct WinResult {
        let timeMs: Int
        let backtracks: Int
        let stars: Int
        let parMs: Int
        let isNewBest: Bool
        let beatPar: Bool
    }

    let levelID: Int
    let spec: LevelSpec
    let theme: Theme
    let scene: MazeScene

    private let maze: Maze
    private let progress: Progress
    private let account: Account
    private var startDate: Date?
    private var ticker: Timer?

    init(levelID: Int, progress: Progress, account: Account) {
        self.levelID = levelID
        self.progress = progress
        self.account = account
        let spec = Levels.spec(levelID)
        self.spec = spec
        self.maze = Levels.maze(levelID)
        self.theme = Theme.of(spec.theme)
        self.scene = MazeScene(maze: maze, theme: theme, easier: spec.stars <= 1)
        wire()
    }

    var parMs: Int { Int(maze.parTime * 1000) }

    private func wire() {
        scene.onStart = { [weak self] in self?.handleStart() }
        scene.onTrailChanged = { [weak self] bt, _ in self?.backtracks = bt }
        scene.onLiftReset = { [weak self] in self?.handleLift() }
        scene.onWin = { [weak self] elapsed, bt, rs in self?.handleWin(elapsed: elapsed, backtracks: bt, resets: rs) }
    }

    func setReduceMotion(_ on: Bool) { scene.reduceMotion = on }

    func retry() {
        ticker?.invalidate()
        scene.restart()
        elapsedMs = 0; backtracks = 0; started = false; won = false; result = nil; onlineRank = nil
    }

    private func handleStart() {
        started = true
        startDate = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.startDate, !self.won else { return }
                self.elapsedMs = Int(Date().timeIntervalSince(s) * 1000)
            }
        }
    }

    private func handleLift() {
        ticker?.invalidate()
        elapsedMs = 0; backtracks = 0; started = false
    }

    private func handleWin(elapsed: Double, backtracks bt: Int, resets: Int) {
        ticker?.invalidate()
        let ms = Int(elapsed * 1000)
        elapsedMs = ms; backtracks = bt; won = true

        let par = parMs
        let prevBest = progress.record(levelID).bestTimeMs
        progress.complete(level: levelID, timeMs: ms, backtracks: bt, parMs: par)
        let isNewBest = prevBest == nil || ms < prevBest!
        result = WinResult(timeMs: ms, backtracks: bt,
                           stars: progress.record(levelID).stars, parMs: par,
                           isNewBest: isNewBest, beatPar: ms <= par)

        let trail = scene.trailPairs
        Task { [weak self] in
            guard let self else { return }
            if let resp = await self.account.submit(levelId: self.levelID, timeMs: ms, backtracks: bt, trail: trail) {
                await MainActor.run {
                    if resp.playerCount > 1 {
                        let top = max(1, Int((100 - resp.percentile).rounded()))
                        self.onlineRank = "#\(resp.rank) of \(resp.playerCount) · top \(top)%"
                    } else {
                        self.onlineRank = "#\(resp.rank) of \(resp.playerCount)"
                    }
                }
            }
        }
    }
}
