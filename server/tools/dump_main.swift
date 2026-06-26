import Foundation
var entries: [String] = []
for id in 1...Levels.count {
  let m = Levels.maze(id)
  var flat: [UInt8] = []
  for x in 0..<m.width { for y in 0..<m.height { flat.append(m.passages[x][y]) } }
  let passStr = flat.map { String($0) }.joined(separator: ",")
  let spikes = m.spikes.map { "[\($0.x),\($0.y)]" }.sorted().joined(separator: ",")
  let path = MazeGenerator.bfsPath(m.passages, w: m.width, h: m.height, from: m.start, to: m.goal)!
  let minLen = path.count - 1
  // sanity: spike-free reachability (the same invariant the XCTest suite asserts)
  let safe = m.reachable(from: m.start, blocked: m.spikes)
  precondition(safe.contains(m.goal), "level \(id) unsolvable")
  entries.append("  \"\(id)\": { \"w\": \(m.width), \"h\": \(m.height), \"minLen\": \(minLen), \"spikes\": [\(spikes)], \"passages\": [\(passStr)] }")
}
let js = "// AUTO-GENERATED from the Swift maze generator (TraceCore). Do not edit by hand.\n"
  + "// passages[x*h + y] = open-side bitmask: N=1, S=2, E=4, W=8 (Direction.bit).\n"
  + "export const LEVELS_DATA = {\n" + entries.joined(separator: ",\n") + "\n};\n"
try! js.write(toFile: "/root/trace/server/src/levels.js", atomically: true, encoding: .utf8)
print("WROTE levels.js with \(entries.count) levels")
