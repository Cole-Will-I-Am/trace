-- Trace backend schema (Cloudflare D1 / SQLite). Per-level best-time + fewest-backtracks
-- leaderboards with lightweight, server-side anti-cheat.
PRAGMA foreign_keys = ON;

-- ===== players / identity =====
CREATE TABLE IF NOT EXISTS players (
  id              TEXT    PRIMARY KEY,            -- 'p_' + random
  apple_sub       TEXT    UNIQUE,                 -- HMAC(sub) lookup key; nullable until SIWA
  username        TEXT    UNIQUE COLLATE NOCASE,  -- nullable until chosen
  display         TEXT    NOT NULL,
  is_anonymous    INTEGER NOT NULL DEFAULT 1,
  created_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS device_links (
  device_id   TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  secret_hash TEXT,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token       TEXT PRIMARY KEY,                   -- sha256(token)
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_player ON sessions(player_id);

-- ===== per-level results (ONE row per player per level — keep their best) =====
-- Every accepted submission is a maze-valid trail (server replays it against the real maze
-- walls), so backtrack counts are always trustworthy. `time_verified` shadow-ranks a run
-- whose TIME is below the soft per-cell floor (suspiciously fast but otherwise legal) — it
-- gates only the time + total boards, never the backtracks board.
CREATE TABLE IF NOT EXISTS scores (
  player_id          TEXT    NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  level_id           INTEGER NOT NULL,
  best_time_ms       INTEGER NOT NULL,
  fewest_backtracks  INTEGER NOT NULL,
  trail_hash         TEXT    NOT NULL,            -- sha256 of the best-time run's trail (audit/dedup)
  time_verified      INTEGER NOT NULL DEFAULT 1,  -- 0 = best time below the soft floor (shadow)
  plays              INTEGER NOT NULL DEFAULT 1,
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL,
  PRIMARY KEY (player_id, level_id)
);
CREATE INDEX IF NOT EXISTS idx_scores_level_time ON scores(level_id, best_time_ms ASC) WHERE time_verified = 1;
CREATE INDEX IF NOT EXISTS idx_scores_level_bt   ON scores(level_id, fewest_backtracks ASC, best_time_ms ASC);
CREATE INDEX IF NOT EXISTS idx_scores_player     ON scores(player_id);

-- ===== fixed-window rate limiter =====
CREATE TABLE IF NOT EXISTS rate (
  k    TEXT PRIMARY KEY,
  n    INTEGER NOT NULL,
  exp  INTEGER NOT NULL
);
