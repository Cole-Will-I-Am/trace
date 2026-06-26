import Foundation

/// One level's authoring parameters. The mechanic-introduction ORDER is the load-bearing
/// part of the difficulty curve (blueprint §3): each new mechanic gets a teaching level
/// before being combined. Grid size, braid (loops), and trap density scale the pressure.
public struct LevelSpec: Sendable {
    public let id: Int
    public let theme: ThemeID
    public let title: String
    public let stars: Int                 // 1…5, shown on the level-select card

    public let width: Int
    public let height: Int
    public var seed: UInt64

    public var braid: Double              // 0 = perfect maze; higher = more loops/junctions
    public var checkpoints: Int
    public var spikes: Int

    public var gates: Int
    public var gatePeriod: Double
    public var gateOpenFraction: Double
    public var gatesSynced: Bool
    public var gatePhaseSpread: Double

    public var oneWays: Int

    public var moving: Int
    public var movingPatrol: Int
    public var movingStep: Double

    public var phantoms: Int
    public var phantomsOnPath: Bool
    public var phantomPeriod: Double
    public var phantomSolidFraction: Double

    public var fogRadius: Int?
    public var slippery: Bool
    public var secondsPerCell: Double

    public init(id: Int, theme: ThemeID, title: String, stars: Int, width: Int, height: Int,
                seed: UInt64? = nil, braid: Double = 0, checkpoints: Int = 0, spikes: Int = 0,
                gates: Int = 0, gatePeriod: Double = 3.6, gateOpenFraction: Double = 0.55,
                gatesSynced: Bool = false, gatePhaseSpread: Double = 1.0, oneWays: Int = 0,
                moving: Int = 0, movingPatrol: Int = 4, movingStep: Double = 0.6,
                phantoms: Int = 0, phantomsOnPath: Bool = false, phantomPeriod: Double = 3.0,
                phantomSolidFraction: Double = 0.6, fogRadius: Int? = nil, slippery: Bool = false,
                secondsPerCell: Double = 0.5) {
        self.id = id; self.theme = theme; self.title = title; self.stars = stars
        self.width = width; self.height = height
        self.seed = seed ?? (0x9E37_79B9_7F4A_7C15 &* UInt64(id &+ 1))
        self.braid = braid; self.checkpoints = checkpoints; self.spikes = spikes
        self.gates = gates; self.gatePeriod = gatePeriod; self.gateOpenFraction = gateOpenFraction
        self.gatesSynced = gatesSynced; self.gatePhaseSpread = gatePhaseSpread
        self.oneWays = oneWays; self.moving = moving; self.movingPatrol = movingPatrol
        self.movingStep = movingStep; self.phantoms = phantoms; self.phantomsOnPath = phantomsOnPath
        self.phantomPeriod = phantomPeriod; self.phantomSolidFraction = phantomSolidFraction
        self.fogRadius = fogRadius; self.slippery = slippery; self.secondsPerCell = secondsPerCell
    }
}

public enum Levels {
    /// The 21-level campaign. One new mechanic per teaching level, then combinations.
    public static let all: [LevelSpec] = [
        // ── ★ basics ──────────────────────────────────────────────────────────────
        LevelSpec(id: 1,  theme: .tutorialGrove, title: "Tutorial Grove", stars: 1,
                  width: 5, height: 5, secondsPerCell: 0.7),
        LevelSpec(id: 2,  theme: .gardenPath,    title: "Garden Path", stars: 1,
                  width: 6, height: 6, secondsPerCell: 0.6),
        LevelSpec(id: 3,  theme: .stoneMaze,     title: "Stone Maze", stars: 1,
                  width: 6, height: 7, braid: 0.18),
        // ── ★★ corridors + static spikes + checkpoints + first gates ──────────────
        LevelSpec(id: 4,  theme: .sandDunes,     title: "Sand Dunes", stars: 2,
                  width: 7, height: 8, braid: 0.08, secondsPerCell: 0.55),
        LevelSpec(id: 5,  theme: .crystalCavern, title: "Crystal Cavern", stars: 2,
                  width: 7, height: 8, braid: 0.12, spikes: 4),
        LevelSpec(id: 6,  theme: .frostHollow,   title: "Frost Hollow", stars: 2,
                  width: 8, height: 8, braid: 0.12, checkpoints: 2, spikes: 4),
        LevelSpec(id: 7,  theme: .emberForge,    title: "Ember Forge", stars: 2,
                  width: 8, height: 9, braid: 0.1, checkpoints: 1, gates: 1,
                  gatePeriod: 4.0, gateOpenFraction: 0.6),
        // ── ★★★ gate variations + fog ─────────────────────────────────────────────
        LevelSpec(id: 8,  theme: .tidePools,     title: "Tide Pools", stars: 3,
                  width: 8, height: 9, braid: 0.14, spikes: 3, gates: 2, gatePeriod: 3.6),
        LevelSpec(id: 9,  theme: .neonCircuit,   title: "Neon Circuit", stars: 3,
                  width: 9, height: 9, braid: 0.16, spikes: 3, gates: 2, gatePeriod: 2.6,
                  gateOpenFraction: 0.5),
        LevelSpec(id: 10, theme: .clockworkHalls, title: "Clockwork Halls", stars: 3,
                  width: 9, height: 10, braid: 0.12, checkpoints: 1, gates: 3, gatePeriod: 3.0,
                  gateOpenFraction: 0.5, gatesSynced: true),
        LevelSpec(id: 11, theme: .shadowVault,   title: "Shadow Vault", stars: 3,
                  width: 9, height: 10, braid: 0.14, checkpoints: 1, spikes: 5, fogRadius: 2),
        // ── ★★★★ one-ways, dense spikes, movers, combos, ice ──────────────────────
        LevelSpec(id: 12, theme: .mirrorLabyrinth, title: "Mirror Labyrinth", stars: 4,
                  width: 10, height: 10, braid: 0.28, oneWays: 3),
        LevelSpec(id: 13, theme: .thornThicket,  title: "Thorn Thicket", stars: 4,
                  width: 10, height: 11, braid: 0.22, spikes: 16),
        LevelSpec(id: 14, theme: .stormSpire,    title: "Storm Spire", stars: 4,
                  width: 10, height: 11, braid: 0.18, spikes: 4, moving: 3, movingPatrol: 5,
                  movingStep: 0.55),
        LevelSpec(id: 15, theme: .moltenCore,    title: "Molten Core", stars: 4,
                  width: 11, height: 11, braid: 0.18, checkpoints: 1, spikes: 8, gates: 2,
                  gatePeriod: 3.0, gateOpenFraction: 0.5),
        LevelSpec(id: 16, theme: .glacierDepths, title: "Glacier Depths", stars: 4,
                  width: 11, height: 11, braid: 0.16, spikes: 5, slippery: true),
        // ── ★★★★★ master tier ─────────────────────────────────────────────────────
        LevelSpec(id: 17, theme: .voidNexus,     title: "Void Nexus", stars: 5,
                  width: 12, height: 12, braid: 0.36, checkpoints: 2, spikes: 6, fogRadius: 3),
        LevelSpec(id: 18, theme: .ancientMechanism, title: "Ancient Mechanism", stars: 5,
                  width: 12, height: 13, braid: 0.16, checkpoints: 4, gates: 3, gatePeriod: 3.2,
                  gateOpenFraction: 0.5, gatesSynced: true, oneWays: 2),
        LevelSpec(id: 19, theme: .phantomMaze,   title: "Phantom Maze", stars: 5,
                  width: 12, height: 13, braid: 0.2, checkpoints: 1, spikes: 4, phantoms: 6,
                  phantomsOnPath: true, phantomPeriod: 2.8, phantomSolidFraction: 0.62),
        LevelSpec(id: 20, theme: .infernoGauntlet, title: "Inferno Gauntlet", stars: 5,
                  width: 13, height: 13, braid: 0.2, checkpoints: 3, spikes: 8, gates: 3,
                  gatePeriod: 2.8, gateOpenFraction: 0.5, oneWays: 2, moving: 3, movingPatrol: 5,
                  movingStep: 0.5),
        LevelSpec(id: 21, theme: .finalKnot,     title: "The Final Knot", stars: 5,
                  width: 13, height: 14, braid: 0.26, checkpoints: 4, spikes: 10, gates: 4,
                  gatePeriod: 2.8, gateOpenFraction: 0.5, gatesSynced: true, oneWays: 3,
                  moving: 4, movingPatrol: 5, movingStep: 0.5, phantoms: 4, phantomsOnPath: true,
                  phantomPeriod: 2.6, phantomSolidFraction: 0.6, fogRadius: 4),
    ]

    public static func spec(_ id: Int) -> LevelSpec { all.first { $0.id == id } ?? all[0] }

    /// Build (or rebuild) the maze for a level. Deterministic from the spec's seed.
    public static func maze(_ id: Int) -> Maze { MazeGenerator.build(spec(id)) }

    public static var count: Int { all.count }
}
