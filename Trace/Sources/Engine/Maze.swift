import Foundation

// Trace maze model — a PURE, Foundation-only description of one level. No SpriteKit/UIKit
// here: the renderer projects this model and the TraceEngine runs the rules on top of it,
// so the whole thing is unit-testable with `swift test` on Linux.
//
// Coordinate convention: integer grid, origin bottom-left, y-up. `north` is +y.

public struct Coord: Hashable, Codable, Sendable {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

public enum Direction: Int, CaseIterable, Codable, Sendable {
    case north, south, east, west

    public var dx: Int { self == .east ? 1 : (self == .west ? -1 : 0) }
    public var dy: Int { self == .north ? 1 : (self == .south ? -1 : 0) }

    public var bit: UInt8 {
        switch self {
        case .north: return 1
        case .south: return 2
        case .east:  return 4
        case .west:  return 8
        }
    }

    public var opposite: Direction {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east:  return .west
        case .west:  return .east
        }
    }
}

/// Theme id lives in the pure layer (drives generation parameters + difficulty banding); the
/// UI maps it to a colour palette. Order matches the 21-level progression.
public enum ThemeID: String, Codable, Sendable, CaseIterable {
    case tutorialGrove, gardenPath, stoneMaze, sandDunes, crystalCavern, frostHollow,
         emberForge, tidePools, neonCircuit, clockworkHalls, shadowVault, mirrorLabyrinth,
         thornThicket, stormSpire, moltenCore, glacierDepths, voidNexus, ancientMechanism,
         phantomMaze, infernoGauntlet, finalKnot
}

// ---- time-driven hazards (pure functions of elapsed seconds; fully deterministic) ----

/// A gate sits on the EDGE between two adjacent cells and is a temporary wall: when closed,
/// the edge can't be crossed in either direction. Open/closed cycles on a fixed period.
public struct Gate: Codable, Sendable, Equatable {
    public let a: Coord
    public let b: Coord
    public let period: Double          // full open→closed→open cycle, seconds
    public let openFraction: Double    // share of the cycle the gate is open (0..1)
    public let phase: Double           // 0..1 offset, lets gates desync

    public init(a: Coord, b: Coord, period: Double, openFraction: Double, phase: Double) {
        self.a = a; self.b = b; self.period = period; self.openFraction = openFraction; self.phase = phase
    }

    public func covers(_ p: Coord, _ q: Coord) -> Bool {
        (a == p && b == q) || (a == q && b == p)
    }

    public func isOpen(at t: Double) -> Bool {
        guard period > 0 else { return true }
        var u = (t / period + phase).truncatingRemainder(dividingBy: 1.0)
        if u < 0 { u += 1 }
        return u < openFraction
    }

    /// Fraction-through-the-cycle, for the renderer to animate the gate.
    public func phaseValue(at t: Double) -> Double {
        guard period > 0 else { return 0 }
        var u = (t / period + phase).truncatingRemainder(dividingBy: 1.0)
        if u < 0 { u += 1 }
        return u
    }
}

/// A one-way edge: crossing is allowed ONLY in the `from → to` direction. It blocks the
/// reverse — including backtracking — which is what makes "no-backtrack zones" (§2/§3 L12).
public struct OneWay: Codable, Sendable, Equatable {
    public let from: Coord
    public let to: Coord
    public init(from: Coord, to: Coord) { self.from = from; self.to = to }
}

/// A hazard that patrols an ordered list of cells, one cell per `stepSeconds`, looping. If
/// the finger enters the cell the hazard currently occupies, the run resets to checkpoint.
public struct MovingHazard: Codable, Sendable, Equatable {
    public let path: [Coord]
    public let stepSeconds: Double
    public init(path: [Coord], stepSeconds: Double) { self.path = path; self.stepSeconds = stepSeconds }

    public func cell(at t: Double) -> Coord {
        guard !path.isEmpty else { return Coord(-1, -1) }
        guard stepSeconds > 0 else { return path[0] }
        let i = Int((t / stepSeconds).rounded(.down))
        let n = path.count
        let idx = ((i % n) + n) % n
        return path[idx]
    }
}

/// A path cell that blinks out of existence on a cycle (§3 L19). Entering it while it is
/// "gone" drops the player back to the last checkpoint.
public struct Phantom: Codable, Sendable, Equatable {
    public let cell: Coord
    public let period: Double
    public let solidFraction: Double
    public let phase: Double
    public init(cell: Coord, period: Double, solidFraction: Double, phase: Double) {
        self.cell = cell; self.period = period; self.solidFraction = solidFraction; self.phase = phase
    }

    public func isSolid(at t: Double) -> Bool {
        guard period > 0 else { return true }
        var u = (t / period + phase).truncatingRemainder(dividingBy: 1.0)
        if u < 0 { u += 1 }
        return u < solidFraction
    }
}

public struct Maze: Codable, Sendable {
    public let levelID: Int
    public let theme: ThemeID
    public let width: Int
    public let height: Int

    /// `passages[x][y]` is a bitmask of `Direction.bit` for the sides that are OPEN (a
    /// corridor connects to that neighbour). Symmetric by construction.
    public var passages: [[UInt8]]

    public let start: Coord
    public let goal: Coord
    public var checkpoints: Set<Coord>
    public var spikes: Set<Coord>
    public var gates: [Gate]
    public var oneWays: [OneWay]
    public var moving: [MovingHazard]
    public var phantoms: [Phantom]

    /// Reveal radius for fog-of-war levels (cells farther than this from the finger are
    /// dimmed by the renderer). `nil` = fully lit. Pure metadata; the engine ignores it.
    public let fogRadius: Int?
    /// Glacier momentum: the renderer keeps sliding the finger until a wall/junction.
    public let slippery: Bool
    /// Suggested clean-run time (seconds), derived from the solution length at build time.
    public let parTime: Double

    public init(levelID: Int, theme: ThemeID, width: Int, height: Int, passages: [[UInt8]],
                start: Coord, goal: Coord, checkpoints: Set<Coord>, spikes: Set<Coord>,
                gates: [Gate], oneWays: [OneWay], moving: [MovingHazard], phantoms: [Phantom],
                fogRadius: Int?, slippery: Bool, parTime: Double) {
        self.levelID = levelID; self.theme = theme; self.width = width; self.height = height
        self.passages = passages; self.start = start; self.goal = goal
        self.checkpoints = checkpoints; self.spikes = spikes; self.gates = gates
        self.oneWays = oneWays; self.moving = moving; self.phantoms = phantoms
        self.fogRadius = fogRadius; self.slippery = slippery; self.parTime = parTime
    }

    // MARK: topology helpers

    public func inBounds(_ c: Coord) -> Bool { c.x >= 0 && c.x < width && c.y >= 0 && c.y < height }

    public func isOpen(_ c: Coord, _ d: Direction) -> Bool {
        guard inBounds(c) else { return false }
        return passages[c.x][c.y] & d.bit != 0
    }

    public func neighbor(_ c: Coord, _ d: Direction) -> Coord { Coord(c.x + d.dx, c.y + d.dy) }

    /// The orthogonal step direction from `a` to `b`, or nil if they aren't adjacent.
    public func direction(from a: Coord, to b: Coord) -> Direction? {
        let dx = b.x - a.x, dy = b.y - a.y
        switch (dx, dy) {
        case (0, 1):  return .north
        case (0, -1): return .south
        case (1, 0):  return .east
        case (-1, 0): return .west
        default:      return nil
        }
    }

    /// Cells reachable from `a` by open passages, treating every cell in `blocked` as
    /// impassable. Used to prove static solvability (a spike-free route exists).
    public func reachable(from a: Coord, blocked: Set<Coord> = []) -> Set<Coord> {
        var seen: Set<Coord> = [a]
        var stack = [a]
        while let c = stack.popLast() {
            for d in Direction.allCases where isOpen(c, d) {
                let n = neighbor(c, d)
                if blocked.contains(n) || seen.contains(n) { continue }
                seen.insert(n); stack.append(n)
            }
        }
        return seen
    }
}
