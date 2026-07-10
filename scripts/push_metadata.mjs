#!/usr/bin/env node
// Push Trace App Store metadata to App Store Connect via the REST API.
// Requires: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64 env vars.
// Run from CI (iOS - Push Metadata workflow) or locally with secrets exported.
import crypto from "node:crypto";

const apiBase = "https://api.appstoreconnect.apple.com/v1";
const bundleId = process.env.BUNDLE_ID || "com.colecantcode.trace";
const token = makeToken();

// ── auth (shared with asc_status.mjs) ──────────────────────────────────────
function requireEnv(name) {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}
function b64u(input) {
  return Buffer.from(input).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
function makeToken() {
  const keyId = requireEnv("ASC_KEY_ID");
  const issuerId = requireEnv("ASC_ISSUER_ID");
  const privateKey = Buffer.from(requireEnv("ASC_KEY_P8_BASE64"), "base64").toString("utf8");
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = { iss: issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const sig = crypto.sign("sha256", Buffer.from(signingInput), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64u(sig)}`;
}
async function api(path, opts = {}) {
  const { method = "GET", body } = opts;
  const r = await fetch(`${apiBase}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await r.text();
  const data = text ? JSON.parse(text) : {};
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status}: ${JSON.stringify(data.errors || data)}`);
  return data;
}

// ── metadata ──────────────────────────────────────────────────────────────
const METADATA = {
  description: `Trace is a maze game where your finger never leaves the screen.

Press the glowing start dot and drag through the corridors to the goal — all in one continuous motion. Hit a wall and you stop. Hit a dead end and your trail rewinds back along the path you just drew, cell by cell, to the last junction. Hit a trap and you snap back to your last checkpoint.

Twenty-one handcrafted mazes, each glowing with its own colour palette. Every level introduces one new mechanic before combining them — timed gates that open and close on a rhythm, one-way corridors you can't backtrack through, patrolling orange orbs, ghostly tiles that blink out of existence, and fog-shrouded levels where you can only see a few cells ahead.

Three stars per level. Par time. Zero-backtrack runs. A per-level leaderboard for best time and fewest backtracks, plus a total completion-time board across the full campaign. Play anonymously from the moment you launch, or Sign in with Apple to carry your name across devices.

No ads. No currencies. No timers that pressure you. Just your finger, a maze, and a trail of light.`,
  keywords: "maze,puzzle,trace,labyrinth,finger,drag,trail,path,logic,runner,backtrack,one-touch,minimalist,challenge,brain,glow,dark,levels,speedrun,leaderboard",
  whatsNew: "First App Store release — 21 maze levels with per-level and total leaderboards, progressive mechanics (gates, one-ways, moving hazards, phantoms, fog), and Sign in with Apple.",
};

// ── main ──────────────────────────────────────────────────────────────────
console.log(`Looking up app ${bundleId}…`);
const apps = await api(`/apps?filter[bundleId]=${bundleId}`);
const app = apps.data?.[0];
if (!app) { console.log(`No app found for ${bundleId}`); process.exit(1); }
console.log(`App: ${app.attributes?.name} (id=${app.id})\n`);

// Find the editable app store version (state = PREPARE_FOR_SUBMISSION, READY_FOR_SALE, etc.)
const versions = await api(`/apps/${app.id}/appStoreVersions?limit=5`);
const version = versions.data?.find(v => {
  const s = v.attributes?.appStoreState;
  return s === "PREPARE_FOR_SUBMISSION" || s === "READY_FOR_SALE"
    || s === "PENDING_DEVELOPER_RELEASE" || s === "IN_REVIEW"
    || s === "WAITING_FOR_REVIEW" || s === "REJECTED";
});
if (!version) { console.log("No editable app store version found."); process.exit(1); }

const vid = version.id;
const vs = version.attributes?.versionString;
const state = version.attributes?.appStoreState;
console.log(`Patching version ${vs} (id=${vid}, state=${state})…`);

const patchBody = {
  data: {
    type: "appStoreVersions",
    id: vid,
    attributes: {
      description: METADATA.description,
      keywords: METADATA.keywords,
      whatsNew: METADATA.whatsNew,
    },
  },
};

const patched = await api(`/appStoreVersions/${vid}`, { method: "PATCH", body: patchBody });
const a = patched.data?.attributes || {};
console.log(`✓ Updated version ${a.versionString}`);
console.log(`  description: ${(a.description || "").length} chars`);
console.log(`  keywords: ${a.keywords || "(empty)"}`);
console.log(`  whatsNew: ${a.whatsNew || "(empty)"}`);
console.log(`  state: ${a.appStoreState}`);
console.log("\nDone. Open App Store Connect to add screenshots and submit.");
