#!/usr/bin/env node
// Read-only App Store Connect status for Trace: versions + review submissions (with how long
// the current submission has been waiting). No writes.
import crypto from "node:crypto";

const apiBase = "https://api.appstoreconnect.apple.com/v1";
const bundleId = process.env.BUNDLE_ID || "com.colecantcode.trace";
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
async function api(path) {
  const r = await fetch(`${apiBase}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  const text = await r.text();
  const data = text ? JSON.parse(text) : {};
  if (!r.ok) throw new Error(`${path} -> ${r.status}: ${JSON.stringify(data.errors || data)}`);
  return data;
}

const apps = await api(`/apps?filter[bundleId]=${bundleId}`);
const app = apps.data?.[0];
if (!app) { console.log(`No app for ${bundleId}`); process.exit(0); }
console.log(`App: ${app.attributes?.name} (${bundleId}) id=${app.id}\n`);

const versions = await api(`/apps/${app.id}/appStoreVersions?limit=10`);
console.log("=== App Store Versions ===");
for (const v of versions.data || []) {
  const a = v.attributes || {};
  console.log(`  ${a.versionString}  state=${a.appStoreState}  created=${a.createdDate}`);
}

const subs = await api(`/reviewSubmissions?filter[app]=${app.id}&filter[platform]=IOS&limit=10`);
console.log("\n=== Review Submissions ===");
const now = Date.now();
for (const s of subs.data || []) {
  const a = s.attributes || {};
  const sd = a.submittedDate ? new Date(a.submittedDate) : null;
  const days = sd ? ((now - sd.getTime()) / 86_400_000).toFixed(1) : "-";
  console.log(`  state=${a.state}  submitted=${a.submittedDate || "-"}  (${days} days ago)`);
}
