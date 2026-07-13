// Trace backend Worker. Per-level best-time + fewest-backtracks leaderboards on D1, with
// server-side anti-cheat: every submitted run is REPLAYED against the real maze (levels.js,
// generated from the same Swift generator the app uses) — each step must cross an open
// corridor, never touch a spike, and run start→goal — and its time must clear a plausible
// per-cell floor; the trail is hashed for audit.

import {
  HttpError, sha256hex, hmacHex, randomToken, randomId,
  verifyAppleIdentityToken, createSession, authPlayer, constantTimeEqual,
} from "./auth.js";
import { LEVELS_DATA } from "./levels.js";

const BUNDLE_ID = "com.colecantcode.trace";
const LEVEL_COUNT = 21;

// Grid sizes derived from the real maze data (LEVELS_DATA also carries passages + spikes).
const LEVELS = Object.fromEntries(Object.entries(LEVELS_DATA).map(([k, v]) => [Number(k), [v.w, v.h]]));

const HARD_MIN_MS_PER_CELL = 30;     // below this finger speed = impossible → reject
const SOFT_MIN_MS_PER_CELL = 85;     // below this = dubious → accepted but time-shadowed
const MAX_TIME_MS = 20 * 60 * 1000;

const json = (obj, status = 200, headers = {}) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...headers } });
const ok = (obj, headers) => json(obj, 200, headers);
const fail = (status, error) => json({ error }, status);

async function readJson(req) { try { return await req.json(); } catch { return {}; } }
const nowS = () => Math.floor(Date.now() / 1000);

async function rateLimit(env, req, key, limit, windowSec) {
  const ip = req.headers.get("CF-Connecting-IP") || "0";
  const bucket = Math.floor(Date.now() / 1000 / windowSec);
  const k = `${key}:${ip}:${bucket}`;
  const row = await env.DB.prepare(
    "INSERT INTO rate(k,n,exp) VALUES(?,1,?) ON CONFLICT(k) DO UPDATE SET n=n+1 RETURNING n"
  ).bind(k, (bucket + 1) * windowSec).first();
  // best-effort purge of expired buckets on the first hit of a new window (keeps the table small)
  if ((row?.n ?? 1) === 1) {
    try { await env.DB.prepare("DELETE FROM rate WHERE exp < ?").bind(nowS()).run(); } catch {}
  }
  return (row?.n ?? 1) <= limit;
}

function shortCode() {
  const b = new Uint8Array(2); crypto.getRandomValues(b);
  return (b[0].toString(16) + b[1].toString(16)).toUpperCase().padStart(4, "0").slice(0, 4);
}

async function newPlayer(env, { apple_sub = null, isAnon = 1 }) {
  const id = randomId("p_");
  await env.DB.prepare(
    `INSERT INTO players(id, apple_sub, display, is_anonymous, created_at) VALUES(?,?,?,?,?)`
  ).bind(id, apple_sub, "Tracer-" + shortCode(), isAnon, nowS()).run();
  return env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first();
}

function playerView(p) {
  return { id: p.id, username: p.username, display: p.display, isAnonymous: !!p.is_anonymous };
}
const nameOf = (r) => r.username || r.display;

// ---------------- account ----------------

async function hAccount(req, env) {
  if (!(await rateLimit(env, req, "acct", 30, 3600))) return fail(429, "rate_limited");
  const body = await readJson(req);

  if (body.appleIdentityToken) {
    const sub = await verifyAppleIdentityToken(body.appleIdentityToken, body.nonce ?? null, BUNDLE_ID);
    const subKey = await hmacHex(sub, env.APPLE_SUB_PEPPER);
    let p = await env.DB.prepare("SELECT * FROM players WHERE apple_sub = ?").bind(subKey).first();
    if (!p && body.deviceId && body.deviceSecret) {
      const link = await env.DB.prepare("SELECT * FROM device_links WHERE device_id = ?").bind(body.deviceId).first();
      if (link && link.secret_hash && constantTimeEqual(link.secret_hash, await sha256hex(body.deviceSecret))) {
        const anon = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND is_anonymous = 1").bind(link.player_id).first();
        if (anon) {
          await env.DB.prepare("UPDATE players SET apple_sub = ?, is_anonymous = 0 WHERE id = ?").bind(subKey, anon.id).run();
          p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(anon.id).first();
        }
      }
    }
    if (!p) p = await newPlayer(env, { apple_sub: subKey, isAnon: 0 });
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }

  const deviceId = body.deviceId;
  if (!deviceId) return fail(400, "missing_deviceId");
  const link = await env.DB.prepare("SELECT * FROM device_links WHERE device_id = ?").bind(deviceId).first();
  if (link) {
    if (!body.deviceSecret || !link.secret_hash ||
        !constantTimeEqual(link.secret_hash, await sha256hex(body.deviceSecret))) {
      return fail(401, "bad_device_secret");
    }
    const p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(link.player_id).first();
    if (!p) return fail(401, "bad_device_secret");
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }
  // New device: mint a player + a device secret, atomically claiming the deviceId. If a
  // concurrent request won the row, fall through and reject (the client will retry with it).
  const secret = randomToken(32);
  const p = await newPlayer(env, { isAnon: 1 });
  const ins = await env.DB.prepare(
    "INSERT OR IGNORE INTO device_links(device_id, player_id, secret_hash, created_at) VALUES(?,?,?,?)"
  ).bind(deviceId, p.id, await sha256hex(secret), nowS()).run();
  if (ins.meta.changes !== 1) {
    await env.DB.prepare("DELETE FROM players WHERE id = ?").bind(p.id).run();   // undo the orphan
    return fail(409, "device_race_retry");
  }
  const s = await createSession(env, p.id);
  return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p), deviceSecret: secret });
}

// ---------------- score submission ----------------

/// Which side of cell (x,y) the step (dx,dy) crosses, as a Direction bitmask (N=1,S=2,E=4,W=8).
function stepBit(dx, dy) { return dx === 1 ? 4 : dx === -1 ? 8 : dy === 1 ? 1 : 2; }

/// Replay a trail against the real maze. Returns the step count, or throws HttpError. Each
/// step must cross an OPEN corridor; no cell may be a spike; it must run start→goal.
export function validateTrail(trail, lvl) {
  const { w, h, minLen, passages, spikes } = lvl;
  if (!Array.isArray(trail) || trail.length < 2 || trail.length > w * h * 3) throw new HttpError(422, "bad_trail");
  const spikeSet = new Set((spikes || []).map(([x, y]) => x + "," + y));
  for (const c of trail) {
    if (!Array.isArray(c) || c.length !== 2) throw new HttpError(422, "bad_trail_cell");
    const [x, y] = c;
    if (!Number.isInteger(x) || !Number.isInteger(y) || x < 0 || x >= w || y < 0 || y >= h) throw new HttpError(422, "trail_out_of_bounds");
    if (spikeSet.has(x + "," + y)) throw new HttpError(422, "trail_hits_spike");
  }
  if (trail[0][0] !== 0 || trail[0][1] !== 0) throw new HttpError(422, "trail_bad_start");
  if (trail[trail.length - 1][0] !== w - 1 || trail[trail.length - 1][1] !== h - 1) throw new HttpError(422, "trail_bad_goal");
  for (let i = 1; i < trail.length; i++) {
    const dx = trail[i][0] - trail[i - 1][0], dy = trail[i][1] - trail[i - 1][1];
    if (Math.abs(dx) + Math.abs(dy) !== 1) throw new HttpError(422, "trail_not_contiguous");
    const [px, py] = trail[i - 1];
    if ((passages[px * h + py] & stepBit(dx, dy)) === 0) throw new HttpError(422, "trail_crosses_wall");
  }
  const steps = trail.length - 1;
  if (steps < minLen) throw new HttpError(422, "trail_too_short");
  return steps;
}

// Replay the app's accepted movement events so the backtrack metric is derived from the
// actual trail transitions instead of trusted from a client-supplied integer. Event kinds:
// 0 = forward step, 1 = one-cell backtrack, 2 = trap snap-back to a cell already on the trail.
export function validateReplay(replay, finalTrail, lvl) {
  const { w, h, passages, spikes } = lvl;
  if (!Array.isArray(replay) || replay.length < 1 || replay.length > w * h * 100) {
    throw new HttpError(422, "bad_replay");
  }
  const spikeSet = new Set((spikes || []).map(([x, y]) => x + "," + y));
  const trail = [[0, 0]];
  let backtracks = 0;

  const validCell = (c) => Array.isArray(c) && c.length >= 2 &&
    Number.isInteger(c[0]) && Number.isInteger(c[1]) && c[0] >= 0 && c[0] < w && c[1] >= 0 && c[1] < h;
  const openStep = (from, to) => {
    const dx = to[0] - from[0], dy = to[1] - from[1];
    if (Math.abs(dx) + Math.abs(dy) !== 1) return false;
    const bit = stepBit(dx, dy);
    return (passages[from[0] * h + from[1]] & bit) !== 0;
  };

  for (const event of replay) {
    if (!Array.isArray(event) || event.length !== 3 || !validCell(event) ||
        !Number.isInteger(event[2]) || event[2] < 0 || event[2] > 2) {
      throw new HttpError(422, "bad_replay_event");
    }
    const to = [event[0], event[1]], kind = event[2];
    const from = trail[trail.length - 1];

    if (kind === 0) {
      if (spikeSet.has(to[0] + "," + to[1]) || !openStep(from, to)) {
        throw new HttpError(422, "replay_invalid_forward");
      }
      // The engine emits a backtrack event when returning to the immediately previous cell.
      if (trail.length >= 2 && to[0] === trail[trail.length - 2][0] && to[1] === trail[trail.length - 2][1]) {
        throw new HttpError(422, "replay_bad_backtrack");
      }
      trail.push(to);
    } else if (kind === 1) {
      if (trail.length < 2 || to[0] !== trail[trail.length - 2][0] || to[1] !== trail[trail.length - 2][1]) {
        throw new HttpError(422, "replay_bad_backtrack");
      }
      trail.pop();
      backtracks += 1;
    } else {
      const idx = trail.findIndex(([x, y]) => x === to[0] && y === to[1]);
      if (idx < 0 || spikeSet.has(to[0] + "," + to[1])) throw new HttpError(422, "replay_bad_reset");
      const removed = trail.length - idx - 1;
      trail.length = idx + 1;
      backtracks += removed;
    }
  }

  if (!Array.isArray(finalTrail) || JSON.stringify(trail) !== JSON.stringify(finalTrail)) {
    throw new HttpError(422, "replay_trail_mismatch");
  }
  validateTrail(trail, lvl);
  return { trail, backtracks };
}

async function hScore(req, env, player) {
  if (!(await rateLimit(env, req, "score", 120, 3600))) return fail(429, "rate_limited");
  const body = await readJson(req);
  const levelId = Number(body.levelId);
  const timeMs = Number(body.timeMs);
  const claimedBacktracks = Number(body.backtracks);
  const trail = body.trail;
  const replay = body.replay;

  const lvl = LEVELS_DATA[levelId];
  if (!lvl) return fail(400, "bad_level");
  if (!Number.isFinite(timeMs) || timeMs <= 0 || timeMs > MAX_TIME_MS) return fail(422, "bad_time");
  if (!Number.isInteger(claimedBacktracks) || claimedBacktracks < 0 || claimedBacktracks > 100000) return fail(422, "bad_backtracks");

  let steps, backtracks;
  try {
    if (!Array.isArray(replay)) return fail(422, "replay_required");
    const result = validateReplay(replay, trail, lvl);
    steps = result.trail.length - 1;
    backtracks = result.backtracks;
    if (claimedBacktracks !== backtracks) return fail(422, "backtrack_mismatch");
  }
  catch (e) { if (e instanceof HttpError) return fail(e.status, e.message); throw e; }

  // finger must have crossed at least (forward steps + each backtracked cell) boundaries.
  const traveled = steps + backtracks;
  if (timeMs < traveled * HARD_MIN_MS_PER_CELL) return fail(422, "impossible_time");
  const timeVerified = timeMs >= traveled * SOFT_MIN_MS_PER_CELL ? 1 : 0;

  const trailHash = await sha256hex(JSON.stringify(trail));
  const t = nowS();

  // single atomic upsert — keeps the best time + fewest backtracks without a read-modify race.
  const row = await env.DB.prepare(
    `INSERT INTO scores(player_id, level_id, best_time_ms, fewest_backtracks, trail_hash, time_verified, plays, created_at, updated_at)
     VALUES(?1,?2,?3,?4,?5,?6,1,?7,?7)
     ON CONFLICT(player_id, level_id) DO UPDATE SET
       trail_hash        = CASE WHEN excluded.best_time_ms < scores.best_time_ms THEN excluded.trail_hash    ELSE scores.trail_hash END,
       time_verified     = CASE WHEN excluded.best_time_ms < scores.best_time_ms THEN excluded.time_verified ELSE scores.time_verified END,
       best_time_ms      = MIN(scores.best_time_ms, excluded.best_time_ms),
       fewest_backtracks = MIN(scores.fewest_backtracks, excluded.fewest_backtracks),
       plays             = scores.plays + 1,
       updated_at        = excluded.updated_at
     RETURNING best_time_ms, fewest_backtracks, time_verified`
  ).bind(player.id, levelId, timeMs, backtracks, trailHash, timeVerified, t).first();

  const bestTime = row.best_time_ms;
  const improved = bestTime === timeMs;
  const tv = row.time_verified;

  // rank on the TIME board (verified only); 0/unranked if this player's best is shadowed.
  const playerCount = (await env.DB.prepare("SELECT COUNT(*) AS c FROM scores WHERE level_id = ? AND time_verified = 1").bind(levelId).first()).c;
  let rank = 0, percentile = 0;
  if (tv) {
    rank = (await env.DB.prepare("SELECT COUNT(*) AS c FROM scores WHERE level_id = ? AND time_verified = 1 AND best_time_ms < ?").bind(levelId, bestTime).first()).c + 1;
    const beaten = playerCount - rank;
    percentile = playerCount > 0 ? Math.round((1000 * Math.max(0, beaten)) / playerCount) / 10 : 0;
  }
  return ok({ levelId, bestTimeMs: bestTime, rank, percentile, playerCount, improved });
}

// ---------------- boards ----------------

async function hBoard(req, env, url, player) {
  if (!(await rateLimit(env, req, "board", 240, 3600))) return fail(429, "rate_limited");
  const level = Number(url.searchParams.get("level"));
  const metric = url.searchParams.get("metric") === "backtracks" ? "backtracks" : "time";
  const limit = Math.min(Number(url.searchParams.get("limit") || 50), 100);
  if (!LEVELS[level]) return fail(400, "bad_level");

  // time board shows only verified runs; backtracks board shows all (every accepted run is a
  // maze-valid trail, so its backtrack count is trustworthy regardless of speed).
  const where = metric === "backtracks" ? "s.level_id = ?" : "s.level_id = ? AND s.time_verified = 1";
  const order = metric === "backtracks" ? "fewest_backtracks ASC, best_time_ms ASC" : "best_time_ms ASC";
  const { results } = await env.DB.prepare(
    `SELECT p.id, p.username, p.display, s.best_time_ms AS bt, s.fewest_backtracks AS fb
     FROM scores s JOIN players p ON p.id = s.player_id
     WHERE ${where} ORDER BY ${order} LIMIT ?`
  ).bind(level, limit).all();

  const entries = results.map((r) => ({
    id: r.id, name: nameOf(r), value: metric === "backtracks" ? r.fb : r.bt, extra: null,
  }));

  let me = null;
  if (player) {
    const mine = await env.DB.prepare("SELECT * FROM scores WHERE player_id = ? AND level_id = ?").bind(player.id, level).first();
    if (mine && (metric === "backtracks" || mine.time_verified)) {
      let rank, total, val;
      if (metric === "backtracks") {
        val = mine.fewest_backtracks;
        rank = (await env.DB.prepare("SELECT COUNT(*) AS c FROM scores WHERE level_id = ? AND (fewest_backtracks < ? OR (fewest_backtracks = ? AND best_time_ms < ?))")
          .bind(level, mine.fewest_backtracks, mine.fewest_backtracks, mine.best_time_ms).first()).c + 1;
        total = (await env.DB.prepare("SELECT COUNT(*) AS c FROM scores WHERE level_id = ?").bind(level).first()).c;
      } else {
        val = mine.best_time_ms;
        rank = (await env.DB.prepare("SELECT COUNT(*) AS c FROM scores WHERE level_id = ? AND time_verified = 1 AND best_time_ms < ?").bind(level, val).first()).c + 1;
        total = (await env.DB.prepare("SELECT COUNT(*) AS c FROM scores WHERE level_id = ? AND time_verified = 1").bind(level).first()).c;
      }
      const beaten = Math.max(0, total - rank);
      me = { rank, value: val, percentile: total > 0 ? Math.round((1000 * beaten) / total) / 10 : 0 };
    }
  }
  return ok({ scope: "level", metric, level, entries, me }, { "cache-control": "public, max-age=20" });
}

async function hBoardTotal(req, env, url, player) {
  if (!(await rateLimit(env, req, "boardtot", 120, 3600))) return fail(429, "rate_limited");
  const limit = Math.min(Number(url.searchParams.get("limit") || 50), 100);
  const { results } = await env.DB.prepare(
    `SELECT p.id, p.username, p.display, SUM(s.best_time_ms) AS total, COUNT(*) AS lv
     FROM scores s JOIN players p ON p.id = s.player_id
     WHERE s.time_verified = 1 GROUP BY s.player_id ORDER BY lv DESC, total ASC LIMIT ?`
  ).bind(limit).all();
  const entries = results.map((r) => ({ id: r.id, name: nameOf(r), value: r.total, extra: r.lv }));

  let me = null;
  if (player) {
    const mine = await env.DB.prepare(
      "SELECT SUM(best_time_ms) AS total, COUNT(*) AS lv FROM scores WHERE player_id = ? AND time_verified = 1"
    ).bind(player.id).first();
    if (mine && mine.lv > 0) {
      const rank = (await env.DB.prepare(
        `SELECT COUNT(*) AS c FROM (
           SELECT player_id, SUM(best_time_ms) AS total, COUNT(*) AS lv FROM scores WHERE time_verified = 1 GROUP BY player_id
         ) WHERE lv > ? OR (lv = ? AND total < ?)`
      ).bind(mine.lv, mine.lv, mine.total).first()).c + 1;
      me = { rank, value: mine.total, percentile: 0 };
    }
  }
  return ok({ scope: "total", metric: "time", level: null, entries, me }, { "cache-control": "public, max-age=20" });
}

// ---------------- account utils ----------------

async function hMe(req, env, player) { return ok({ player: playerView(player) }); }

async function hUsername(req, env, player) {
  if (!(await rateLimit(env, req, "uname", 30, 3600))) return fail(429, "rate_limited");
  const { username } = await readJson(req);
  const u = String(username || "").trim().toLowerCase();
  if (!/^[a-z0-9_]{3,16}$/.test(u)) return fail(400, "invalid_username");
  const BLOCK = ["admin", "trace", "moderator", "fuck", "shit", "nigger", "faggot", "cunt"];
  if (BLOCK.some((b) => u.includes(b))) return fail(400, "blocked_username");
  const taken = await env.DB.prepare("SELECT 1 FROM players WHERE username = ? COLLATE NOCASE AND id <> ?").bind(u, player.id).first();
  if (taken) return fail(409, "username_taken");
  try {
    await env.DB.prepare("UPDATE players SET username = ?, display = ? WHERE id = ?").bind(u, u, player.id).run();
  } catch (e) {
    return fail(409, "username_taken");   // lost the uniqueness race
  }
  const p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(player.id).first();
  return ok({ player: playerView(p) });
}

async function hDeleteAccount(req, env, player) {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM scores WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM sessions WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM device_links WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM reports WHERE reporter_id = ? OR target_id = ?").bind(player.id, player.id),
    env.DB.prepare("DELETE FROM players WHERE id = ?").bind(player.id),
  ]);
  return ok({ deleted: true });
}

// A leaderboard username is the only user-generated content in the app (no chat/messaging).
// Reports are stored for manual moderation review; repeatedly reported players can be
// username-reset or removed by an operator directly in D1. Rate-limited to prevent report spam.
const REPORT_REASONS = new Set(["offensive_username", "impersonation", "other"]);

async function hReport(req, env, player) {
  if (!(await rateLimit(env, req, "report", 20, 3600))) return fail(429, "rate_limited");
  const { targetId, reason } = await readJson(req);
  const r = REPORT_REASONS.has(reason) ? reason : "other";
  if (!targetId || typeof targetId !== "string") return fail(400, "invalid_target");
  if (targetId === player.id) return fail(400, "cannot_report_self");
  const target = await env.DB.prepare("SELECT id FROM players WHERE id = ?").bind(targetId).first();
  if (!target) return fail(404, "not_found");
  await env.DB.prepare(
    "INSERT INTO reports(id, reporter_id, target_id, reason, created_at) VALUES(?,?,?,?,?)"
  ).bind(randomId("rp_"), player.id, targetId, r, nowS()).run();
  return ok({ reported: true });
}

async function hHealth(req, env) {
  const r = await env.DB.prepare("SELECT COUNT(*) AS c FROM players").first().catch(() => null);
  return ok({ ok: !!r, levels: LEVEL_COUNT, dataLevels: Object.keys(LEVELS_DATA).length });
}

// ---------------- static pages ----------------

function htmlPage(body) {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><title>Trace</title>` +
    `<style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;` +
    `background:#0B0E12;color:#EDF2F7;max-width:680px;margin:0 auto;padding:44px 22px;line-height:1.62}` +
    `h1{font-size:30px;margin:.2em 0;letter-spacing:.1em}h2{margin-top:1.6em}a{color:#6FE39A}.muted{color:#97A2B0}` +
    `ul{padding-left:20px}.bars{display:flex;gap:6px;margin-bottom:26px}.bars span{height:7px;width:38px;border-radius:2px}</style>` +
    `</head><body>${body}</body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } }
  );
}
const BARS = `<div class="bars"><span style="background:#6FE39A"></span><span style="background:#4FE0E8"></span><span style="background:#9D7BFF"></span><span style="background:#FFD66B"></span></div>`;

function hLanding() {
  return htmlPage(`${BARS}<h1>TRACE</h1>
    <p class="muted">A finger-on-screen maze tracer. One continuous drag from start to goal — backtrack to re-route, dodge the traps, race the clock across 21 levels.</p>
    <p><a href="/privacy">Privacy Policy</a> &middot; <a href="/terms">Terms of Use</a></p>`);
}
function hPrivacy() {
  return htmlPage(`<h1>Trace — Privacy Policy</h1><p class="muted">Last updated 26 June 2026.</p>
    <p>Trace is a maze game. We collect the minimum needed to run the game and its leaderboards. We show no ads, use no third-party analytics or tracking, and never sell your data.</p>
    <h2>What we collect</h2><ul>
      <li><b>Gameplay data</b> — your level times, backtrack counts, and the trail of cells from a completed run, used to score and rank you.</li>
      <li><b>An account identifier</b> — if you play anonymously, a random identifier generated on your device; if you Sign in with Apple, a one-way hashed identifier derived from Apple. We never receive or store your real name or email.</li>
      <li><b>A username</b>, only if you choose to set one (shown on leaderboards).</li>
    </ul>
    <h2>What we do not collect</h2><p>No name, email, phone number, contacts, location, photos, or advertising identifier. No cross-app or cross-site tracking.</p>
    <h2>How we use it</h2><p>Only to operate the game: validate and rank runs, compute per-level and total leaderboards, and show your standing.</p>
    <h2>Where it is stored</h2><p>On Cloudflare, our infrastructure provider, processing the data on our behalf.</p>
    <h2>Your choices</h2><p>You can play entirely anonymously. You can delete your account and all associated data at any time from <b>Leaderboard &rarr; Delete account</b> in the app, or by emailing us.</p>
    <h2>Children</h2><p>Trace is not directed to children under 13 and collects no personal information beyond what is described above.</p>
    <h2>Contact</h2><p>Questions or deletion requests: <a href="mailto:cole@manticthink.com">cole@manticthink.com</a>.</p>`);
}
function hTerms() {
  return htmlPage(`<h1>Trace — Terms of Use</h1><p class="muted">Last updated 26 June 2026.</p>
    <p>Trace is provided as-is, for personal entertainment. Play fair: do not cheat, automate, or manipulate the leaderboards — we may remove scores or accounts that do. We may update or discontinue the game at any time. By playing, you agree to these terms.</p>
    <p>Contact: <a href="mailto:cole@manticthink.com">cole@manticthink.com</a>.</p>`);
}

// ---------------- router ----------------

async function requireAuth(req, env) {
  const p = await authPlayer(req, env);
  if (!p) throw new HttpError(401, "unauthorized");
  return p;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const path = url.pathname;
    const method = req.method.toUpperCase();
    try {
      if (!env.SESSION_SECRET || !env.APPLE_SUB_PEPPER) return fail(500, "server_misconfigured");
      if (path === "/healthz") return hHealth(req, env);
      if (path === "/" && method === "GET") return hLanding();
      if (path === "/privacy" && method === "GET") return hPrivacy();
      if (path === "/terms" && method === "GET") return hTerms();
      if (path === "/v1/account" && method === "POST") return hAccount(req, env);
      if (path === "/v1/account" && method === "DELETE") return hDeleteAccount(req, env, await requireAuth(req, env));
      if (path === "/v1/score" && method === "POST") return hScore(req, env, await requireAuth(req, env));
      if (path === "/v1/board" && method === "GET") return hBoard(req, env, url, await authPlayer(req, env));
      if (path === "/v1/board/total" && method === "GET") return hBoardTotal(req, env, url, await authPlayer(req, env));
      if (path === "/v1/me" && method === "GET") return hMe(req, env, await requireAuth(req, env));
      if (path === "/v1/username" && method === "PUT") return hUsername(req, env, await requireAuth(req, env));
      if (path === "/v1/report" && method === "POST") return hReport(req, env, await requireAuth(req, env));
      return fail(404, "not_found");
    } catch (e) {
      if (e instanceof HttpError) return fail(e.status, e.message);
      console.error("internal", e && (e.stack || e.message));
      return fail(500, "internal_error");
    }
  },
};

export { LEVELS, LEVELS_DATA, HARD_MIN_MS_PER_CELL, SOFT_MIN_MS_PER_CELL };
