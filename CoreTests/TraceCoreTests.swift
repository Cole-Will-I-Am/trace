import XCTest
@testable import TraceCore

final class TraceCoreTests: XCTestCase {

    // MARK: determinism

    func testSplitMix64Reference() {
        var r = SplitMix64(seed: 0)
        XCTAssertEqual(r.next(), 0xE220_A839_7B1D_CDAF)   // matches RUNG/Chainfall PRNG
    }

    /// Same level builds byte-identical twice — every player gets the same maze, and the
    /// server can rebuild it to validate a run.
    func testGenerationDeterminism() {
        for id in 1...Levels.count {
            let a = Levels.maze(id)
            let b = Levels.maze(id)
            XCTAssertEqual(a.passages, b.passages, "passages differ on level \(id)")
            XCTAssertEqual(a.spikes, b.spikes, "spikes differ on level \(id)")
            XCTAssertEqual(a.checkpoints, b.checkpoints, "checkpoints differ on level \(id)")
            XCTAssertEqual(a.gates, b.gates, "gates differ on level \(id)")
            XCTAssertEqual(a.oneWays, b.oneWays, "oneways differ on level \(id)")
            XCTAssertEqual(a.parTime, b.parTime, "par differs on level \(id)")
        }
    }

    // MARK: the solvability proof — the whole point of "spikes off the path"

    /// Every one of the 21 levels must be solvable: a spike-free route from start to goal
    /// has to exist (gates/movers/phantoms are time-passable, so a static spike-free path
    /// proves the level can be cleared). Also sanity-check structure.
    func testAllLevelsSolvable() {
        XCTAssertEqual(Levels.count, 21)
        for id in 1...Levels.count {
            let m = Levels.maze(id)
            XCTAssertEqual(m.start, Coord(0, 0))
            XCTAssertEqual(m.goal, Coord(m.width - 1, m.height - 1))
            XCTAssertFalse(m.spikes.contains(m.start), "spike on start, level \(id)")
            XCTAssertFalse(m.spikes.contains(m.goal), "spike on goal, level \(id)")

            // a route avoiding every spike reaches the goal
            let safe = m.reachable(from: m.start, blocked: m.spikes)
            XCTAssertTrue(safe.contains(m.goal), "no spike-free route to goal on level \(id)")

            // checkpoints sit on reachable, non-spike cells
            for cp in m.checkpoints {
                XCTAssertFalse(m.spikes.contains(cp), "checkpoint is a spike, level \(id)")
                XCTAssertTrue(safe.contains(cp), "checkpoint unreachable, level \(id)")
            }

            // the canonical solution path itself is spike-free and one-ways point forward
            guard let path = MazeGenerator.bfsPath(m.passages, w: m.width, h: m.height,
                                                   from: m.start, to: m.goal) else {
                return XCTFail("no BFS path on level \(id)")
            }
            for c in path { XCTAssertFalse(m.spikes.contains(c), "spike on solution path L\(id)") }
            // each one-way's allowed direction agrees with forward progress along P if it lies on P
            let order = Dictionary(uniqueKeysWithValues: path.enumerated().map { ($1, $0) })
            for ow in m.oneWays {
                if let i = order[ow.from], let j = order[ow.to] {
                    XCTAssertLessThan(i, j, "one-way points backward along path, level \(id)")
                }
            }
        }
    }

    /// The solution path is a real corridor walk: consecutive cells are adjacent AND have an
    /// open passage between them. Guards against a generator that "teleports".
    func testSolutionPathIsConnectedCorridor() {
        for id in 1...Levels.count {
            let m = Levels.maze(id)
            guard let path = MazeGenerator.bfsPath(m.passages, w: m.width, h: m.height,
                                                   from: m.start, to: m.goal) else {
                return XCTFail("no path L\(id)")
            }
            for i in 0..<(path.count - 1) {
                let a = path[i], b = path[i + 1]
                guard let d = m.direction(from: a, to: b) else { return XCTFail("non-adjacent L\(id)") }
                XCTAssertTrue(m.isOpen(a, d), "wall between path cells on L\(id)")
            }
        }
    }

    // MARK: engine mechanics

    /// A hand-built tiny maze to exercise advance / backtrack / wall / spike / checkpoint /
    /// gate / one-way / goal precisely.
    private func corridor() -> Maze {
        // 1×4 vertical corridor: (0,0)→(0,1)→(0,2)→(0,3). Open N/S along it.
        var p = Array(repeating: Array(repeating: UInt8(0), count: 4), count: 1)
        p[0][0] = Direction.north.bit
        p[0][1] = Direction.north.bit | Direction.south.bit
        p[0][2] = Direction.north.bit | Direction.south.bit
        p[0][3] = Direction.south.bit
        return Maze(levelID: 99, theme: .stoneMaze, width: 1, height: 4, passages: p,
                    start: Coord(0, 0), goal: Coord(0, 3), checkpoints: [Coord(0, 1)],
                    spikes: [], gates: [], oneWays: [], moving: [], phantoms: [],
                    fogRadius: nil, slippery: false, parTime: 5)
    }

    func testAdvanceBacktrackAndGoal() {
        let e = TraceEngine(maze: corridor())
        XCTAssertEqual(e.move(to: Coord(0, 1), at: 0), .advanced(Coord(0, 1)))
        XCTAssertEqual(e.lastCheckpoint, Coord(0, 1))               // captured checkpoint
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0), .advanced(Coord(0, 2)))
        XCTAssertEqual(e.move(to: Coord(0, 1), at: 0), .backtracked(Coord(0, 1)))  // reverse pops
        XCTAssertEqual(e.trail, [Coord(0, 0), Coord(0, 1)])
        XCTAssertEqual(e.backtrackCount, 1)
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0), .advanced(Coord(0, 2)))
        XCTAssertEqual(e.move(to: Coord(0, 3), at: 0), .reachedGoal)
        XCTAssertEqual(e.status, .won)
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0), .ignored)    // run is over
    }

    func testReplayRecordsBacktracksAndGoal() {
        let e = TraceEngine(maze: corridor())
        _ = e.move(to: Coord(0, 1), at: 0)
        _ = e.move(to: Coord(0, 2), at: 0)
        _ = e.move(to: Coord(0, 1), at: 0)
        _ = e.move(to: Coord(0, 2), at: 0)
        _ = e.move(to: Coord(0, 3), at: 0)
        XCTAssertEqual(e.replay, [[0, 1, 0], [0, 2, 0], [0, 1, 1], [0, 2, 0], [0, 3, 0]])
        XCTAssertEqual(e.backtrackCount, 1)
    }

    func testWallBlocksNonAdjacentAndClosedSides() {
        let e = TraceEngine(maze: corridor())
        // east is an orthogonal neighbour but there's no corridor (and it's off-grid) → wall
        XCTAssertEqual(e.move(to: Coord(1, 0), at: 0), .blockedByWall)
        // a two-cell jump isn't an orthogonal neighbour at all → ignored
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0), .ignored)
    }

    func testSpikeSnapsBackToCheckpoint() {
        var m = corridor()
        m.spikes = [Coord(0, 2)]
        let e = TraceEngine(maze: m)
        XCTAssertEqual(e.move(to: Coord(0, 1), at: 0), .advanced(Coord(0, 1)))  // checkpoint
        let r = e.move(to: Coord(0, 2), at: 0)
        XCTAssertEqual(r, .reset(to: Coord(0, 1), cause: .spike))
        XCTAssertEqual(e.current, Coord(0, 1))
        XCTAssertEqual(e.resetCount, 1)
    }

    func testGateOpenAndClosed() {
        var m = corridor()
        m.gates = [Gate(a: Coord(0, 1), b: Coord(0, 2), period: 2, openFraction: 0.5, phase: 0)]
        let e = TraceEngine(maze: m)
        _ = e.move(to: Coord(0, 1), at: 0)
        // open in [0,1)s of the 2s cycle; closed in [1,2)s
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 1.5), .blockedByGate)
        XCTAssertEqual(e.current, Coord(0, 1))
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0.2), .advanced(Coord(0, 2)))
    }

    func testOneWayBlocksReverse() {
        var m = corridor()
        m.oneWays = [OneWay(from: Coord(0, 1), to: Coord(0, 2))]  // up only
        let e = TraceEngine(maze: m)
        _ = e.move(to: Coord(0, 1), at: 0)
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0), .advanced(Coord(0, 2)))   // forward ok
        XCTAssertEqual(e.move(to: Coord(0, 1), at: 0), .blockedOneWay)           // can't go back
        XCTAssertEqual(e.current, Coord(0, 2))
    }

    func testMovingHazardTiming() {
        var m = corridor()
        // hazard sits on (0,2) for t in [0,1), then (0,3) for t in [1,2), looping.
        m.moving = [MovingHazard(path: [Coord(0, 2), Coord(0, 3)], stepSeconds: 1)]
        let e = TraceEngine(maze: m)
        _ = e.move(to: Coord(0, 1), at: 0)
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 0.5), .reset(to: Coord(0, 1), cause: .moving))
        XCTAssertEqual(e.move(to: Coord(0, 2), at: 1.5), .advanced(Coord(0, 2)))  // hazard moved on
    }

    func testEngineReplayDeterminism() {
        let m = Levels.maze(20)
        guard let path = MazeGenerator.bfsPath(m.passages, w: m.width, h: m.height,
                                               from: m.start, to: m.goal) else { return XCTFail() }
        let a = TraceEngine(maze: m), b = TraceEngine(maze: m)
        for i in 1..<path.count {
            let ra = a.move(to: path[i], at: Double(i) * 0.3)
            let rb = b.move(to: path[i], at: Double(i) * 0.3)
            XCTAssertEqual(ra, rb)
        }
        XCTAssertEqual(a.trail, b.trail)
        XCTAssertEqual(a.status, b.status)
    }
}
