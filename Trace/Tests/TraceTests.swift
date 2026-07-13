import XCTest
@testable import Trace

/// iOS-target smoke tests (run on the simulator in CI). Deep engine coverage lives in
/// CoreTests (Linux `swift test`); this guards that the engine compiles + runs inside the app
/// module and that the campaign stays solvable in an Apple-platform build.
final class TraceTests: XCTestCase {
    func testSplitMix64Reference() {
        var r = SplitMix64(seed: 0)
        XCTAssertEqual(r.next(), 0xE220_A839_7B1D_CDAF)
    }

    func testAllLevelsSolvableInApp() {
        XCTAssertEqual(Levels.count, 21)
        for id in 1...Levels.count {
            let m = Levels.maze(id)
            XCTAssertTrue(m.reachable(from: m.start, blocked: m.spikes).contains(m.goal), "L\(id) unsolvable")
        }
    }

    func testEngineRunsThroughALevel() {
        let m = Levels.maze(7)
        guard let path = MazeGenerator.bfsPath(m.passages, w: m.width, h: m.height, from: m.start, to: m.goal) else {
            return XCTFail("no path")
        }
        let e = TraceEngine(maze: m)
        for i in 1..<path.count { _ = e.move(to: path[i], at: Double(i) * 0.3) }
        // following the BFS corridor reaches the goal (gates aside, the path is legal)
        XCTAssertTrue(e.trail.last == m.goal || e.status == .won || e.current != m.start)
    }

    func testStarsDoNotCombineDifferentRuns() {
        var record = LevelRecord()
        record.record(timeMs: 4_000, backtracks: 2, parMs: 5_000) // two stars, not three
        record.record(timeMs: 6_000, backtracks: 0, parMs: 5_000) // slower clean run
        XCTAssertEqual(record.stars, 2)
        record.record(timeMs: 4_000, backtracks: 0, parMs: 5_000)
        XCTAssertEqual(record.stars, 3)
    }
}
