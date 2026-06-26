import Foundation

/// SplitMix64 — the deterministic PRNG shared with RUNG/Chainfall, so a Trace maze is fully
/// reproducible from its level seed (every player solves the SAME maze per level) and a run
/// can be replayed server-side for anti-cheat. Wrapping arithmetic reproduces bit-for-bit
/// across platforms (Linux engine tests ⇄ the iOS app).
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<bound` (bound > 0).
    public mutating func int(_ bound: Int) -> Int {
        precondition(bound > 0)
        return Int(next() % UInt64(bound))
    }

    /// Fisher–Yates shuffle in place (deterministic for a given seed).
    public mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, through: 1, by: -1) {
            let j = int(i + 1)
            if i != j { a.swapAt(i, j) }
        }
    }
}
