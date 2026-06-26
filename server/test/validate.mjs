// Pure unit tests for the Worker's maze-replay anti-cheat (no D1 / no live worker).
//   node test/validate.mjs   (requires src/levels.js)
import { validateTrail, LEVELS_DATA, HARD_MIN_MS_PER_CELL, SOFT_MIN_MS_PER_CELL } from "../src/index.js";
import assert from "node:assert";

let pass = 0;
function ok(name, fn) { try { fn(); pass++; console.log("  ✓", name); } catch (e) { console.error("  ✗", name, "—", e.message); process.exitCode = 1; } }
function throws(code, fn) { try { fn(); throw new Error("expected throw " + code); } catch (e) { assert.equal(e.message, code, `wanted ${code} got ${e.message}`); } }

// Synthetic 2×2 maze: (0,0)-N-(0,1)-E-(1,1); (1,0) isolated. passages[x*h + y], bits N1 S2 E4 W8.
//   (0,0): N=1 @0   (0,1): S|E=6 @1   (1,0): 0 @2   (1,1): W=8 @3
const lvl = { w: 2, h: 2, minLen: 2, spikes: [], passages: [1, 6, 0, 8] };

ok("valid maze path accepted", () => assert.equal(validateTrail([[0, 0], [0, 1], [1, 1]], lvl), 2));
ok("trail crossing a wall is rejected", () => throws("trail_crosses_wall", () => validateTrail([[0, 0], [1, 0], [1, 1]], lvl)));
ok("non-contiguous jump rejected", () => throws("trail_not_contiguous", () => validateTrail([[0, 0], [1, 1]], lvl)));
ok("wrong start rejected", () => throws("trail_bad_start", () => validateTrail([[0, 1], [1, 1]], lvl)));
ok("wrong goal rejected", () => throws("trail_bad_goal", () => validateTrail([[0, 0], [0, 1]], lvl)));
ok("spike on the path rejected", () => throws("trail_hits_spike", () => validateTrail([[0, 0], [0, 1], [1, 1]], { ...lvl, spikes: [[0, 1]] })));

ok("LEVELS_DATA has all 21 levels with full passages", () => {
  assert.equal(Object.keys(LEVELS_DATA).length, 21);
  for (let i = 1; i <= 21; i++) {
    const L = LEVELS_DATA[i];
    assert.equal(L.passages.length, L.w * L.h, `level ${i} passages length`);
    assert.ok(L.minLen >= (L.w - 1) + (L.h - 1), `level ${i} minLen >= manhattan`);
  }
});
ok("the real solution path of every level validates", () => {
  for (let i = 1; i <= 21; i++) {
    const L = LEVELS_DATA[i];
    const path = bfsSolve(L);
    assert.ok(path, `level ${i} has a BFS solution`);
    assert.equal(validateTrail(path, L), path.length - 1, `level ${i} solution validates`);
  }
});
ok("a fabricated Manhattan L-path is rejected on level 21", () => {
  const L = LEVELS_DATA[21];
  const trail = [];
  for (let y = 0; y <= L.h - 1; y++) trail.push([0, y]);
  for (let x = 1; x <= L.w - 1; x++) trail.push([x, L.h - 1]);
  let threw = false;
  try { validateTrail(trail, L); } catch { threw = true; }
  assert.ok(threw, "a straight L-path should not validate on a real maze");
});
ok("time floors ordered", () => assert.ok(HARD_MIN_MS_PER_CELL < SOFT_MIN_MS_PER_CELL));

console.log(`\n${pass} checks passed`);

// BFS over the baked passages (mirrors the Swift generator) — used to prove real paths pass.
function bfsSolve(L) {
  const { w, h, passages, spikes } = L;
  const spikeSet = new Set((spikes || []).map(([x, y]) => x + "," + y));
  const key = (x, y) => x + "," + y, start = [0, 0], goal = [w - 1, h - 1];
  const prev = new Map(), seen = new Set([key(0, 0)]);
  const q = [start];
  const dirs = [[0, 1, 1], [0, -1, 2], [1, 0, 4], [-1, 0, 8]]; // dx,dy,bit
  while (q.length) {
    const [x, y] = q.shift();
    if (x === goal[0] && y === goal[1]) break;
    for (const [dx, dy, bit] of dirs) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
      if ((passages[x * h + y] & bit) === 0) continue;
      if (spikeSet.has(key(nx, ny)) || seen.has(key(nx, ny))) continue;
      seen.add(key(nx, ny)); prev.set(key(nx, ny), [x, y]); q.push([nx, ny]);
    }
  }
  if (!seen.has(key(goal[0], goal[1]))) return null;
  const path = [goal]; let c = goal;
  while (!(c[0] === 0 && c[1] === 0)) { c = prev.get(key(c[0], c[1])); path.push(c); }
  return path.reverse();
}
