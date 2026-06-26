import Foundation

/// The pure trace state-machine: it owns the player's recorded trail and decides, for every
/// attempted cell-to-cell step, what happens — advance, backtrack (pop), bonk a wall, get
/// blocked by a gate / one-way, hit a trap (reset to checkpoint), or reach the goal.
///
/// It knows nothing about fingers, points, or pixels. The renderer maps the touch to cell
/// steps and calls `move(to:at:)`; `at` is elapsed seconds since the run began, which is all
/// the engine needs to evaluate timed gates / moving hazards / phantoms deterministically.
public final class TraceEngine {
    public enum Status: Equatable { case tracing, won }

    public enum ResetCause: Equatable { case spike, moving, phantom }

    public enum MoveResult: Equatable {
        case advanced(Coord)                      // stepped forward; pushed onto the trail
        case backtracked(Coord)                   // reversed along the trail; popped a cell
        case blockedByWall                        // no corridor that way — buzz, no movement
        case blockedByGate                        // a closed timed gate
        case blockedOneWay                        // a one-way corridor, wrong direction
        case reset(to: Coord, cause: ResetCause)  // trap → snapped back to last checkpoint
        case reachedGoal                          // win
        case ignored                              // not adjacent / already there / run over
    }

    public let maze: Maze
    public private(set) var trail: [Coord]
    public private(set) var lastCheckpoint: Coord
    public private(set) var status: Status

    /// Total cells removed from the trail across the run (manual reversals + trap snap-backs).
    /// The secondary leaderboard skill metric — "fewest backtracks" (§4).
    public private(set) var backtrackCount: Int = 0
    /// How many times a trap snapped the player back to a checkpoint.
    public private(set) var resetCount: Int = 0

    public init(maze: Maze) {
        self.maze = maze
        self.trail = [maze.start]
        self.lastCheckpoint = maze.start
        self.status = .tracing
    }

    public var current: Coord { trail.last ?? maze.start }
    public var reachedCheckpoints: Set<Coord> { maze.checkpoints.intersection(trail) }

    /// Restart this level from scratch (lift-and-retry).
    public func reset() {
        trail = [maze.start]
        lastCheckpoint = maze.start
        status = .tracing
        backtrackCount = 0
        resetCount = 0
    }

    /// Attempt to move from the current cell to an orthogonally adjacent `to`, at elapsed
    /// time `t` (seconds). Returns what happened so the renderer can react.
    @discardableResult
    public func move(to: Coord, at t: Double) -> MoveResult {
        guard status == .tracing else { return .ignored }
        let cur = current
        if to == cur { return .ignored }
        guard let d = maze.direction(from: cur, to: to) else { return .ignored }

        // 1. wall — there must be an open corridor between the two cells.
        guard maze.isOpen(cur, d) else { return .blockedByWall }

        // 2. one-way — crossing against an arrow is blocked (also kills backtracking here).
        if oneWayBlocks(from: cur, to: to) { return .blockedOneWay }

        // 3. gate — a closed timed gate is a temporary wall in both directions.
        if let g = gate(cur, to), !g.isOpen(at: t) { return .blockedByGate }

        // backtrack? (the step lands on the cell we came from)
        if trail.count >= 2 && to == trail[trail.count - 2] {
            trail.removeLast()
            backtrackCount += 1
            recomputeCheckpoint()
            return .backtracked(to)
        }

        // reaching the goal always wins — even if a moving hazard happens to occupy it.
        if to == maze.goal { trail.append(to); status = .won; return .reachedGoal }

        // 4. traps on the destination → snap back to the last checkpoint.
        if maze.spikes.contains(to) { return snapBack(.spike) }
        if movingHazardOccupies(to, at: t) { return snapBack(.moving) }
        if let ph = phantom(at: to), !ph.isSolid(at: t) { return snapBack(.phantom) }

        // 5. advance.
        trail.append(to)
        if maze.checkpoints.contains(to) { lastCheckpoint = to }
        return .advanced(to)
    }

    // MARK: - trap / edge resolution

    private func snapBack(_ cause: ResetCause) -> MoveResult {
        guard let idx = trail.lastIndex(of: lastCheckpoint) else {
            // shouldn't happen (checkpoint is always on the trail), but stay total.
            let removed = max(0, trail.count - 1)
            trail = [maze.start]; lastCheckpoint = maze.start
            backtrackCount += removed; resetCount += 1
            return .reset(to: maze.start, cause: cause)
        }
        let removed = trail.count - (idx + 1)
        trail.removeLast(removed)
        backtrackCount += removed
        resetCount += 1
        return .reset(to: lastCheckpoint, cause: cause)
    }

    private func recomputeCheckpoint() {
        lastCheckpoint = trail.last(where: { maze.checkpoints.contains($0) }) ?? maze.start
    }

    private func gate(_ a: Coord, _ b: Coord) -> Gate? {
        maze.gates.first { $0.covers(a, b) }
    }

    private func oneWayBlocks(from: Coord, to: Coord) -> Bool {
        // blocked iff a one-way on this edge allows only the opposite direction.
        for ow in maze.oneWays where (ow.from == from && ow.to == to) || (ow.from == to && ow.to == from) {
            if !(ow.from == from && ow.to == to) { return true }
        }
        return false
    }

    private func movingHazardOccupies(_ c: Coord, at t: Double) -> Bool {
        maze.moving.contains { $0.cell(at: t) == c }
    }

    private func phantom(at c: Coord) -> Phantom? {
        maze.phantoms.first { $0.cell == c }
    }
}
