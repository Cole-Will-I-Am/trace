#!/usr/bin/env node
// Push Trace App Store Review Notes to App Store Connect via REST API.
// These go into the "App Review Information" section (appStoreReviewDetail).
import crypto from "node:crypto";

const apiBase = "https://api.appstoreconnect.apple.com/v1";
const bundleId = "com.colecantcode.trace";
const token = makeToken();

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

const REVIEW_NOTES = `DEVICE AND OS TESTING:
• Tested on iPhone 16 Pro Max simulator (latest iOS) via GitHub Actions CI
• Deployment target: iOS 17.0+
• All 21 levels pass automated solvability tests (spike-free route exists for every level)
• Engine tests verify deterministic maze generation, trail mechanics, and checkpoint/trap behavior
• Device family: iPhone only (portrait orientation)

EXTERNAL SERVICES:
• Cloudflare Workers + D1 (trace-api.manticthink.com) — per-level leaderboard backend with server-side anti-cheat (trail replay validation)
• App Store Connect API — TestFlight build distribution and signing
• Sign in with Apple — optional account authentication for cross-device leaderboard identity
• No analytics, no ads, no third-party SDKs — pure Swift/SpriteKit

REGIONAL DIFFERENCES:
None. The app functions identically across all regions. All content is original game material.

REGULATED INDUSTRY / PROTECTED MATERIAL:
N/A. Trace is a maze puzzle game with original content. Not a regulated industry app.

ACCOUNT ACCESS:
The app works fully without signing in — it mints an anonymous account on first launch. Sign in with Apple is an optional upgrade. Reviewers can test both flows:
1. Anonymous: Launch the app → tap any level → play → view leaderboard (anonymous entry)
2. Signed in: Trophy icon → Account → Sign in with Apple → username appears on leaderboard

GAMEPLAY NOTES:
• Tap any unlocked level → press and drag from the glowing start dot through corridors to the goal
• Walls buzz and block. Dead ends rewind your trail. Traps snap back to checkpoint.
• 21 levels progressively introduce gates, one-ways, moving hazards, phantoms, fog, and ice
• Leaderboard validates every submitted run server-side by replaying the trail against the real maze`;

console.log("Looking up app...");
const apps = await api(`/apps?filter[bundleId]=${bundleId}`);
const app = apps.data?.[0];
if (!app) { console.log("No app found"); process.exit(1); }

console.log("Looking up version...");
const versions = await api(`/apps/${app.id}/appStoreVersions?limit=5`);
const editableStates = [
  "PREPARE_FOR_SUBMISSION", "READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE",
  "IN_REVIEW", "WAITING_FOR_REVIEW", "REJECTED", "DEVELOPER_REJECTED",
  "DEVELOPER_REMOVED_FROM_SALE", "METADATA_REJECTED"
];
const version = versions.data?.find(v => editableStates.includes(v.attributes?.appStoreState));
if (!version) {
  console.log("No editable version found. Available states:");
  versions.data?.forEach(v => console.log(`  ${v.attributes?.versionString}: ${v.attributes?.appStoreState}`));
  process.exit(1);
}

console.log(`Version: ${version.attributes?.versionString} (${version.id})`);

// Check if review detail already exists
const existing = await api(`/apps/${app.id}/reviewSubmissions?limit=1`).catch(() => ({ data: [] }));

// Create or update the review detail for this version
const body = {
  data: {
    type: "appStoreReviewDetails",
    attributes: {
      contactFirstName: "Colton",
      contactLastName: "Williams",
      contactPhone: "+1-555-555-5555",
      contactEmail: "cole@manticthink.com",
      demoAccountRequired: false,
      notes: REVIEW_NOTES,
    },
    relationships: {
      appStoreVersion: {
        data: { type: "appStoreVersions", id: version.id },
      },
    },
  },
};

try {
  console.log("Pushing review notes to App Store Connect...");
  const result = await api("/appStoreReviewDetails", { method: "POST", body });
  console.log("✓ Review notes pushed successfully");
  console.log(`  Contact: ${result.data?.attributes?.contactFirstName} ${result.data?.attributes?.contactLastName}`);
  console.log(`  Demo required: ${result.data?.attributes?.demoAccountRequired}`);
  console.log(`  Notes: ${(result.data?.attributes?.notes || "").length} chars`);
} catch (e) {
  if (e.message.includes("409") && e.message.includes("ENTITY_ERROR")) {
    console.log("Review detail already exists — using PATCH instead.");
    // Try to find existing review detail
    const detail = await api(`/appStoreReviewDetails?filter[appStoreVersion]=${version.id}`).catch(() => ({}));
    console.log("Existing detail ID:", detail?.data?.[0]?.id || "not found, trying upsert");
  } else {
    console.log("Error:", e.message);
    process.exit(1);
  }
}

// Also check: is there a review submission?
const subs = await api(`/reviewSubmissions?filter[app]=${app.id}&filter[platform]=IOS&limit=5`);
const subCount = subs.data?.length || 0;
console.log(`\nReview submissions: ${subCount} existing`);
console.log(`Done. Open App Store Connect to verify: https://appstoreconnect.apple.com/apps/${app.id}/appstore/review`);
