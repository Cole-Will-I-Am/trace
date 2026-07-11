# Trace — App Store Connect Metadata

## App Info
- **Name:** Trace
- **Bundle ID:** com.colecantcode.trace
- **SKU:** trace
- **Category:** Games (Primary: Puzzle, Secondary: Casual)

## Description

Trace is a maze game where your finger never leaves the screen.

Press the glowing start dot and drag through the corridors to the goal — all in one continuous motion. Hit a wall and you stop. Hit a dead end and your trail rewinds back along the path you just drew, cell by cell, to the last junction. Hit a trap and you snap back to your last checkpoint.

Twenty-one handcrafted mazes, each glowing with its own colour palette. Every level introduces one new mechanic before combining them — timed gates that open and close on a rhythm, one-way corridors you can't backtrack through, patrolling orange orbs, ghostly tiles that blink out of existence, and fog-shrouded levels where you can only see a few cells ahead.

Three stars per level. Par time. Zero-backtrack runs. A per-level leaderboard for best time and fewest backtracks, plus a total completion-time board across the full campaign. Play anonymously from the moment you launch, or Sign in with Apple to carry your name across devices.

No ads. No currencies. No timers that pressure you. Just your finger, a maze, and a trail of light.

## Keywords
maze, puzzle, trace, labyrinth, finger, drag, trail, path, logic, runner, backtrack, one-touch, minimalist, challenge, brain, glow, dark, levels, speedrun, leaderboard

## Age Rating
4+ (no objectionable content)

## What's New (for this version)
First App Store release — Trace is a finger-on-screen maze tracer with 21 levels, per-level and total leaderboards, and Sign in with Apple.

---

## App Review Information (Notes field)

### 1. Device Models & OS Tested
- **iPhone 16 Pro Max simulator** (latest iOS) via GitHub Actions CI (macOS 15 runner)
- **Deployment target:** iOS 17.0+
- **All 21 levels** pass automated solvability tests — every level has a spike-free start→goal route
- **Engine tests** verify: deterministic maze generation, trail advance/backtrack mechanics, checkpoint snap-back on traps, gate phase timing, one-way direction enforcement, moving hazard patrol, phantom blink cycles
- **Device family:** iPhone only (TARGETED_DEVICE_FAMILY: 1), portrait orientation only

### 2. External Services
| Service | Purpose |
|---------|---------|
| Cloudflare Workers + D1 (trace-api.manticthink.com) | Per-level leaderboard backend with server-side trail replay validation |
| App Store Connect API | TestFlight distribution, code signing, build upload |
| Sign in with Apple | Optional account authentication for cross-device leaderboard identity |

No analytics, no ads, no third-party SDKs. Pure Swift/SpriteKit app.

### 3. Regional Differences
None. The app functions identically across all regions. All content is original game material.

### 4. Regulated Industry / Protected Material
N/A. Trace is a maze puzzle game with original content. Not a regulated industry app.

### 5. Account Access
The app works fully **without signing in** — it mints an anonymous account on first launch. Sign in with Apple is optional. Reviewers can test both:

**Anonymous flow:** Launch the app → tap any unlocked level → play → trophy icon → view leaderboard (anonymous entry)

**Signed-in flow:** Trophy icon → Leaderboard → Account → Sign in with Apple → username appears on leaderboard

### 6. Gameplay Instructions
1. Tap any unlocked level card
2. Press and drag from the glowing "start" dot through corridors to the goal — one continuous motion
3. **Walls:** Buzz and block movement
4. **Dead ends:** Trail rewinds backward along your path to the last junction
5. **Spikes (red stars):** Snap back to last checkpoint (mint ring)
6. **Gates:** Timed red bars — wait for them to turn cyan (open), then pass
7. **One-ways:** Arrows — can only go the indicated direction, can't backtrack
8. **Moving hazards:** Orange orbs patrol on cycles — dodge them
9. **Phantoms:** Ghost tiles blink in/out — time your crossing
10. **Fog:** Limited visibility radius — the trail lights your way
11. **Ice:** Slippery corridors with tighter steering tolerance
12. **Goal:** Reach the golden goal ring to complete the level

### 7. Leaderboard
- Trophy icon on level-select screen opens the leaderboard
- Per-level boards: best time and fewest backtracks
- Total completion-time board across all 21 levels
- Server-side anti-cheat: every submitted trail is replayed against the real maze walls — each step must cross an open corridor, never touch a spike, and run start→goal

### 8. Privacy
- Privacy manifest (PrivacyInfo.xcprivacy) included in build
- Privacy policy: https://trace-api.manticthink.com/privacy
- Terms of use: https://trace-api.manticthink.com/terms
- No encryption: ITSAppUsesNonExemptEncryption = false
