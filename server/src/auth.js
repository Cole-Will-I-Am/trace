// Crypto + identity for the Trace Worker: Sign in with Apple verification, opaque sessions
// (D1-backed, revocable), and helpers. Uses Web Crypto (available in Workers). This module is
// game-agnostic and is shared verbatim with the RUNG/Chainfall backends.

const enc = (s) => new TextEncoder().encode(s);

function toHex(buf) {
  const b = new Uint8Array(buf);
  let s = "";
  for (let i = 0; i < b.length; i++) s += b[i].toString(16).padStart(2, "0");
  return s;
}

function b64urlToBytes(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64url(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256hex(s) {
  return toHex(await crypto.subtle.digest("SHA-256", enc(s)));
}

export async function hmacHex(message, keyStr) {
  const key = await crypto.subtle.importKey("raw", enc(keyStr), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, enc(message)));
}

export function randomToken(n = 32) {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return bytesToB64url(b);
}

export function randomId(prefix) {
  return prefix + randomToken(12);
}

// ---- Sign in with Apple: verify the identity token (RS256) ----
let JWKS = { keys: [], fetchedAt: 0 };
const JWKS_TTL = 600_000; // 10 min

async function appleKey(kid) {
  const fresh = Date.now() - JWKS.fetchedAt < JWKS_TTL;
  let jwk = fresh ? JWKS.keys.find((k) => k.kid === kid) : null;
  if (!jwk) {
    const r = await fetch("https://appleid.apple.com/auth/keys");
    JWKS = { keys: (await r.json()).keys, fetchedAt: Date.now() };
    jwk = JWKS.keys.find((k) => k.kid === kid);
  }
  if (!jwk) throw new HttpError(401, "apple_key_not_found");
  return crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
}

export class HttpError extends Error {
  constructor(status, msg) { super(msg); this.status = status; }
}

export function constantTimeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

/**
 * Verify an Apple identity token bound to nonceRaw; returns the stable Apple `sub`.
 * Checks signature, iss, aud (bundle id), exp (±120s skew), and the nonce hash.
 */
export async function verifyAppleIdentityToken(idToken, nonceRaw, bundleId) {
  let claims;
  try {
    const parts = String(idToken).split(".");
    if (parts.length !== 3) throw 0;
    const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
    if (header.alg !== "RS256" || header.typ !== "JWT") throw 0;   // pin the algorithm
    const key = await appleKey(header.kid);
    const ok = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5", key, b64urlToBytes(parts[2]), enc(parts[0] + "." + parts[1])
    );
    if (!ok) throw 0;
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError(401, "bad_token");
  }
  if (claims.iss !== "https://appleid.apple.com") throw new HttpError(401, "iss");
  if (claims.aud !== bundleId) throw new HttpError(401, "aud");
  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp !== "number" || claims.exp < now - 120) throw new HttpError(401, "expired");
  if (!nonceRaw || !claims.nonce) throw new HttpError(401, "nonce_required");
  if (!constantTimeEqual(claims.nonce, await sha256hex(nonceRaw))) throw new HttpError(401, "nonce");
  return claims.sub;
}

// ---- sessions (opaque token; D1 stores sha256(token)) ----
export async function createSession(env, playerId, ttlDays = 90) {
  const token = randomToken(32);
  const now = Math.floor(Date.now() / 1000);
  const expires = now + ttlDays * 86400;
  await env.DB.prepare(
    "INSERT INTO sessions(token,player_id,created_at,expires_at) VALUES(?,?,?,?)"
  ).bind(await sha256hex(token), playerId, now, expires).run();
  return { token, expiresAt: expires };
}

/** Resolve the caller's player row from the Authorization: Bearer header, or null. */
export async function authPlayer(req, env) {
  const h = req.headers.get("authorization") || "";
  const m = h.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const now = Math.floor(Date.now() / 1000);
  const row = await env.DB.prepare(
    `SELECT p.* FROM sessions s JOIN players p ON p.id = s.player_id
     WHERE s.token = ? AND s.expires_at > ?`
  ).bind(await sha256hex(m[1]), now).first();
  return row || null;
}
