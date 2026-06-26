import Foundation

/// Builds a concrete `Maze` from a `LevelSpec`, deterministically from the spec's seed.
///
/// Pipeline (blueprint §7.5 — recursive-backtracker authoring):
///   1. carve a perfect maze (recursive backtracker → spanning tree, every cell reachable)
///   2. braid: knock out a fraction of dead ends to add loops/junctions (re-routing)
///   3. find the start→goal solution path P (BFS)
///   4. lay checkpoints / gates / one-ways ALONG P (never block forward progress)
///   5. scatter spikes OFF P (so a spike-free route always exists → provably solvable)
///   6. add moving hazards (≥2-cell patrols, always vacate) + phantoms (always re-solidify)
///   7. derive a fair par time from the solution length
public enum MazeGenerator {

    public static func build(_ spec: LevelSpec) -> Maze {
        var rng = SplitMix64(seed: spec.seed)
        let w = spec.width, h = spec.height

        var passages = carve(w: w, h: h, rng: &rng)
        braid(&passages, w: w, h: h, factor: spec.braid, rng: &rng)

        let start = Coord(0, 0)
        let goal = Coord(w - 1, h - 1)

        guard let path = bfsPath(passages, w: w, h: h, from: start, to: goal) else {
            // A perfect maze always connects start↔goal; this is unreachable, but stay total.
            return Maze(levelID: spec.id, theme: spec.theme, width: w, height: h, passages: passages,
                        start: start, goal: goal, checkpoints: [], spikes: [], gates: [], oneWays: [],
                        moving: [], phantoms: [], fogRadius: spec.fogRadius, slippery: spec.slippery,
                        parTime: 30)
        }
        let onPath = Set(path)

        // ---- checkpoints: evenly spaced interior cells of P ----
        var checkpoints = Set<Coord>()
        if spec.checkpoints > 0 && path.count > 2 {
            for i in 1...spec.checkpoints {
                let idx = path.count * i / (spec.checkpoints + 1)
                let c = path[min(max(idx, 1), path.count - 2)]
                if c != start && c != goal { checkpoints.insert(c) }
            }
        }

        // ---- gates on P edges (timing, not blocking) ----
        var gates: [Gate] = []
        if spec.gates > 0 {
            let edges = pickPathEdges(path, count: spec.gates, rng: &rng, avoidFirst: 1)
            for (k, (a, b)) in edges.enumerated() {
                let phase = spec.gatesSynced ? 0.0 : Double(k) / Double(max(1, spec.gates)) * spec.gatePhaseSpread
                gates.append(Gate(a: a, b: b, period: spec.gatePeriod,
                                  openFraction: spec.gateOpenFraction, phase: phase))
            }
        }

        // ---- one-ways on P edges, oriented forward (block backtracking) ----
        var oneWays: [OneWay] = []
        if spec.oneWays > 0 {
            // keep one-ways off gate edges to avoid double-constraining a single step
            let gateEdges = gates.map { edgeKey($0.a, $0.b) }
            let edges = pickPathEdges(path, count: spec.oneWays, rng: &rng, avoidFirst: 1)
                .filter { !gateEdges.contains(edgeKey($0.0, $0.1)) }
            for (a, b) in edges { oneWays.append(OneWay(from: a, to: b)) } // a precedes b on P
        }

        // ---- spikes OFF P (preserves a spike-free route) ----
        var offPath = [Coord]()
        for x in 0..<w { for y in 0..<h {
            let c = Coord(x, y)
            if !onPath.contains(c) && c != start && c != goal { offPath.append(c) }
        }}
        rng.shuffle(&offPath)
        var spikes = Set(offPath.prefix(min(spec.spikes, offPath.count)))

        // ---- moving hazards: short patrols (≥2 cells so they always clear a cell) ----
        var moving: [MovingHazard] = []
        if spec.moving > 0 {
            var seeds = offPath.filter { !spikes.contains($0) }
            rng.shuffle(&seeds)
            var used: Set<Coord> = [start, goal]   // never let a patrol cover start/goal
            for s in seeds where moving.count < spec.moving {
                if used.contains(s) { continue }
                let patrol = walkCorridor(from: s, passages: passages, w: w, h: h,
                                          maxLen: spec.movingPatrol, avoid: used, rng: &rng)
                if patrol.count >= 2 {
                    moving.append(MovingHazard(path: patrol, stepSeconds: spec.movingStep))
                    patrol.forEach { used.insert($0) }
                }
            }
        }

        // ---- phantoms: on P for the "disappearing segments" level, else off P ----
        var phantoms: [Phantom] = []
        if spec.phantoms > 0 {
            var cands: [Coord]
            if spec.phantomsOnPath {
                cands = path.filter { $0 != start && $0 != goal && !checkpoints.contains($0) }
            } else {
                cands = offPath.filter { !spikes.contains($0) }
            }
            rng.shuffle(&cands)
            for (k, c) in cands.prefix(spec.phantoms).enumerated() {
                phantoms.append(Phantom(cell: c, period: spec.phantomPeriod,
                                        solidFraction: spec.phantomSolidFraction,
                                        phase: Double(k) * 0.37))
                spikes.remove(c)
            }
        }

        let par = Double(path.count) * spec.secondsPerCell
            + Double(spec.gates) * 2.2 + Double(spec.moving) * 1.5 + 4.0

        return Maze(levelID: spec.id, theme: spec.theme, width: w, height: h, passages: passages,
                    start: start, goal: goal, checkpoints: checkpoints, spikes: spikes,
                    gates: gates, oneWays: oneWays, moving: moving, phantoms: phantoms,
                    fogRadius: spec.fogRadius, slippery: spec.slippery,
                    parTime: (par * 10).rounded() / 10)
    }

    // MARK: - carving

    static func carve(w: Int, h: Int, rng: inout SplitMix64) -> [[UInt8]] {
        var passages = Array(repeating: Array(repeating: UInt8(0), count: h), count: w)
        var visited = Array(repeating: Array(repeating: false, count: h), count: w)
        var stack = [Coord(0, 0)]
        visited[0][0] = true
        while let c = stack.last {
            var dirs = Direction.allCases
            rng.shuffle(&dirs)
            var advanced = false
            for d in dirs {
                let n = Coord(c.x + d.dx, c.y + d.dy)
                guard n.x >= 0, n.x < w, n.y >= 0, n.y < h, !visited[n.x][n.y] else { continue }
                passages[c.x][c.y] |= d.bit
                passages[n.x][n.y] |= d.opposite.bit
                visited[n.x][n.y] = true
                stack.append(n)
                advanced = true
                break
            }
            if !advanced { stack.removeLast() }
        }
        return passages
    }

    /// Open an extra wall on a fraction of dead-end cells → loops, junctions, alternate routes.
    static func braid(_ passages: inout [[UInt8]], w: Int, h: Int, factor: Double, rng: inout SplitMix64) {
        guard factor > 0 else { return }
        for x in 0..<w { for y in 0..<h {
            let openCount = Direction.allCases.filter { passages[x][y] & $0.bit != 0 }.count
            guard openCount == 1, rng.int(10_000) < Int(factor * 10_000) else { continue }
            var cands = Direction.allCases.filter { d in
                passages[x][y] & d.bit == 0 &&
                (x + d.dx) >= 0 && (x + d.dx) < w && (y + d.dy) >= 0 && (y + d.dy) < h
            }
            rng.shuffle(&cands)
            if let d = cands.first {
                let nx = x + d.dx, ny = y + d.dy
                passages[x][y] |= d.bit
                passages[nx][ny] |= d.opposite.bit
            }
        }}
    }

    // MARK: - pathing

    static func bfsPath(_ passages: [[UInt8]], w: Int, h: Int, from start: Coord, to goal: Coord,
                        blocked: Set<Coord> = []) -> [Coord]? {
        func open(_ c: Coord, _ d: Direction) -> Bool { passages[c.x][c.y] & d.bit != 0 }
        var prev = [Coord: Coord]()
        var seen: Set<Coord> = [start]
        var q = [start]; var head = 0
        while head < q.count {
            let c = q[head]; head += 1
            if c == goal { break }
            for d in Direction.allCases where open(c, d) {
                let n = Coord(c.x + d.dx, c.y + d.dy)
                if blocked.contains(n) || seen.contains(n) { continue }
                seen.insert(n); prev[n] = c; q.append(n)
            }
        }
        guard seen.contains(goal) else { return nil }
        var path = [goal]; var c = goal
        while c != start { guard let p = prev[c] else { return nil }; path.append(p); c = p }
        return path.reversed()
    }

    /// Pick `count` distinct consecutive-cell edges from the path (skipping the first
    /// `avoidFirst` cells so the player isn't blocked on step one).
    static func pickPathEdges(_ path: [Coord], count: Int, rng: inout SplitMix64, avoidFirst: Int) -> [(Coord, Coord)] {
        var idxs = Array(avoidFirst..<(path.count - 1))
        guard !idxs.isEmpty else { return [] }
        rng.shuffle(&idxs)
        return idxs.prefix(count).sorted().map { (path[$0], path[$0 + 1]) }
    }

    /// Walk open corridors from `from` up to `maxLen` cells, avoiding `avoid`, to build a
    /// patrol route for a moving hazard.
    static func walkCorridor(from: Coord, passages: [[UInt8]], w: Int, h: Int, maxLen: Int,
                             avoid: Set<Coord>, rng: inout SplitMix64) -> [Coord] {
        var route = [from]
        var used = avoid; used.insert(from)
        var c = from
        while route.count < maxLen {
            var dirs = Direction.allCases.filter { passages[c.x][c.y] & $0.bit != 0 }
            rng.shuffle(&dirs)
            var moved = false
            for d in dirs {
                let n = Coord(c.x + d.dx, c.y + d.dy)
                if used.contains(n) { continue }
                route.append(n); used.insert(n); c = n; moved = true; break
            }
            if !moved { break }
        }
        return route
    }

    static func edgeKey(_ a: Coord, _ b: Coord) -> String {
        let (p, q) = (a.x, a.y) <= (b.x, b.y) ? (a, b) : (b, a)
        return "\(p.x),\(p.y)-\(q.x),\(q.y)"
    }
}

private func <= (l: (Int, Int), r: (Int, Int)) -> Bool { l.0 != r.0 ? l.0 < r.0 : l.1 <= r.1 }
