import Foundation
import Combine

/// One level's local record. Best time + fewest backtracks are the two skill metrics the
/// blueprint tracks (§4); `completed` drives sequential unlocking.
struct LevelRecord: Codable, Equatable {
    var completed = false
    var bestTimeMs: Int? = nil
    var fewestBacktracks: Int? = nil
    var stars: Int = 0          // 0…3 earned by beating par / par×1.5 / any-clear

    mutating func record(timeMs: Int, backtracks: Int, parMs: Int) {
        completed = true
        if bestTimeMs == nil || timeMs < bestTimeMs! { bestTimeMs = timeMs }
        if fewestBacktracks == nil || backtracks < fewestBacktracks! { fewestBacktracks = backtracks }
        stars = max(stars, Self.earnedStars(timeMs: bestTimeMs ?? timeMs, backtracks: fewestBacktracks ?? backtracks, parMs: parMs))
    }

    static func earnedStars(timeMs: Int, backtracks: Int, parMs: Int) -> Int {
        var s = 1                                   // 1 for clearing it
        if timeMs <= Int(Double(parMs) * 1.5) { s = 2 }
        if timeMs <= parMs && backtracks == 0 { s = 3 }
        return s
    }
}

/// Persistent local progress. The source of truth for unlocks and personal bests; the online
/// leaderboard (§4/§5) is layered on top, never required to play.
@MainActor
final class Progress: ObservableObject {
    @Published private(set) var records: [Int: LevelRecord] = [:]
    @Published var seenHowTo = false

    private let fileName = "trace-progress.json"
    private let howToKey = "trace.seenHowTo"

    init() { load() }

    func record(_ id: Int) -> LevelRecord { records[id] ?? LevelRecord() }

    /// A level is unlocked if it's the first, or the previous one is completed.
    func isUnlocked(_ id: Int) -> Bool {
        id <= 1 || record(id - 1).completed
    }

    var totalStars: Int { records.values.reduce(0) { $0 + $1.stars } }
    var completedCount: Int { records.values.filter { $0.completed }.count }

    /// Sum of best times across all completed levels (the "total completion time" board, §4).
    var totalBestMs: Int? {
        let done = (1...Levels.count).compactMap { records[$0]?.bestTimeMs }
        return done.count == Levels.count ? done.reduce(0, +) : nil
    }

    func complete(level id: Int, timeMs: Int, backtracks: Int, parMs: Int) {
        var r = records[id] ?? LevelRecord()
        r.record(timeMs: timeMs, backtracks: backtracks, parMs: parMs)
        records[id] = r
        save()
    }

    // MARK: persistence

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
    }

    private func load() {
        seenHowTo = UserDefaults.standard.bool(forKey: howToKey)
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Int: LevelRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: fileURL, options: .atomic) }
    }

    func markSeenHowTo() {
        seenHowTo = true
        UserDefaults.standard.set(true, forKey: howToKey)
    }
}

extension Int {
    /// ms → "1:23.4" / "12.3s" for HUD + results.
    var asClock: String {
        let s = Double(self) / 1000
        if s >= 60 { return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60)) }
        return String(format: "%.1fs", s)
    }
}
