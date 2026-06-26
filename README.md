# Trace

A finger-on-screen maze tracer for iOS. Press the glowing start dot and drag — in one
continuous motion — through the corridors to the goal. Hit a wall and you're stopped; hit a
dead end or a trap and you slide **backward along your own trail** to re-route. Pure maze
navigation, no numbers. 21 levels, each introducing one new mechanic before combining them,
with online best-time and fewest-backtrack leaderboards.

Built on the team's no-Mac iOS pipeline: a pure, Linux-testable engine; a SpriteKit projector
for the trace; XcodeGen + GitHub Actions → TestFlight; a Cloudflare Worker + D1 backend.

## Layout

```
Trace/Sources/
  Engine/        PURE game logic (no SpriteKit/UIKit) — compiled into the app AND TraceCore
    Maze.swift            grid model + time-driven hazards (gates / movers / phantoms)
    MazeGenerator.swift   recursive-backtracker + braiding; spikes off the solution path
    TraceEngine.swift     the trace state machine: advance / backtrack / traps / goal
    Levels.swift          the 21 LevelSpecs that drive generation
    SeededRNG.swift       SplitMix64 — deterministic mazes, reproducible runs
  Theme/         design system: 21 themed palettes, type, haptics
  Views/         MazeScene (SpriteKit), GameView/GameViewModel, LevelSelect, HowToPlay, …
  Leaderboard/   Backend client, Sign in with Apple, Keychain, local Progress
CoreTests/       `swift test` — engine determinism + ALL 21 levels proven solvable
Trace/Tests/     iOS-target smoke tests (run on the simulator in CI)
server/          Cloudflare Worker + D1: per-level boards with lightweight anti-cheat
project.yml      XcodeGen (the .xcodeproj is generated in CI, never committed)
.github/         TestFlight release + read-only ASC status workflows
```

## Engine, locally

```bash
swift test          # builds TraceCore and runs the engine + solvability suite
```

The crux test, `testAllLevelsSolvable`, proves every level has a **spike-free** start→goal
route (gates/movers/phantoms are time-passable), so the campaign is always clearable.

## Ship a TestFlight build

No Mac required. Push, then run the **iOS — TestFlight Release** workflow from the Actions tab.
It generates the project with XcodeGen, runs the tests on a simulator, archives + signs with
the App Store Connect API key, and uploads. Repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8_BASE64`. **Bump `MARKETING_VERSION` in `project.yml` on every build.**

## Backend

`server/` is a Cloudflare Worker on D1 (`trace-arena`), serving `trace-api.manticthink.com`.
The client submits a level's time, backtrack count, and final trail; the server **replays the
trail against the real maze** (`src/levels.js`, generated from the same Swift generator) — every
step must cross an actual open corridor, never touch a spike, and run start→goal — then enforces
a plausible per-cell time floor, hashes the trail for audit, and keeps the best. Anonymous by
default; Sign in with Apple to claim a username across devices. The backtracks board trusts any
maze-valid run; the time board shadow-ranks a run whose time is below the soft floor
(`time_verified`).

Regenerate the maze data after any level change:
```bash
swiftc Trace/Sources/Engine/*.swift server/tools/dump_main.swift -o /tmp/td && /tmp/td   # writes server/src/levels.js
```

```bash
cd server
npm i
wrangler d1 create trace-arena                 # paste the id into wrangler.toml
wrangler d1 execute trace-arena --remote --file=schema.sql
wrangler secret put SESSION_SECRET
wrangler secret put APPLE_SUB_PEPPER
npm run deploy
node test/validate.mjs                          # offline anti-cheat unit tests
```
