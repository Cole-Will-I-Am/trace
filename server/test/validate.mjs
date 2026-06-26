// Pure unit tests for the Worker's v1 anti-cheat trail validation (no D1 / no live worker).
//   node test/validate.mjs
import { validateTrail, LEVELS, HARD_MIN_MS_PER_CELL, SOFT_MIN_MS_PER_CELL } from "../src/index.js";
import assert from "node:assert";

let pass = 0;
function ok(name, fn) { try { fn(); pass++; console.log("  ✓", name); } catch (e) { console.error("  ✗", name, "—", e.message); process.exitCode = 1; } }
function throws(code, fn) { try { fn(); throw new Error("expected throw " + code); } catch (e) { assert.equal(e.message, code, `wanted ${code} got ${e.message}`); } }

// a legal walk on a 5×5: up the left edge, then across the top to the goal (4,4)
const legal5 = [];
for (let y = 0; y <= 4; y++) legal5.push([0, y]);
for (let x = 1; x <= 4; x++) legal5.push([x, 4]);

ok("legal walk returns step count", () => assert.equal(validateTrail(legal5, 5, 5), 8));
ok("non-contiguous jump rejected", () => throws("trail_not_contiguous", () => validateTrail([[0,0],[0,2],[2,2],[2,4],[3,4],[4,4]], 5, 5)));
ok("wrong start rejected", () => throws("trail_bad_start", () => validateTrail([[1,0],[2,0],[3,0],[4,0],[4,1],[4,2],[4,3],[4,4]], 5, 5)));
ok("wrong goal rejected", () => throws("trail_bad_goal", () => validateTrail([[0,0],[1,0],[2,0],[3,0]], 5, 5)));
ok("out of bounds rejected", () => throws("trail_out_of_bounds", () => validateTrail([[0,0],[0,1],[0,9],[4,4]], 5, 5)));
ok("all 21 levels dimensioned", () => { for (let i = 1; i <= 21; i++) assert.ok(Array.isArray(LEVELS[i]) && LEVELS[i].length === 2, `level ${i}`); });
ok("time floors ordered", () => assert.ok(HARD_MIN_MS_PER_CELL < SOFT_MIN_MS_PER_CELL));

console.log(`\n${pass} checks passed`);
