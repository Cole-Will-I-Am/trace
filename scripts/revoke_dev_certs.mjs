// Revoke stale cloud-managed Apple Development certificates before archiving.
// Fresh hosted runners mint these during automatic signing; they otherwise accumulate until
// the Apple account reaches its certificate limit. Distribution/TestFlight certificates are
// never touched. Cleanup is best-effort and never fails the release.
import crypto from "node:crypto";

const apiBase = "https://api.appstoreconnect.apple.com/v1";

function base64url(input) {
  return Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function makeToken() {
  const keyId = process.env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID;
  const privateKey = Buffer.from(process.env.ASC_KEY_P8_BASE64 || "", "base64").toString("utf8");
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = { iss: issuerId, iat: now, exp: now + 19 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${base64url(signature)}`;
}

async function api(token, method, path) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${method} ${path} -> ${response.status}: ${JSON.stringify(body.errors || body)}`);
  return body;
}

async function main() {
  if (!process.env.ASC_KEY_ID || !process.env.ASC_ISSUER_ID || !process.env.ASC_KEY_P8_BASE64) {
    console.log("ASC secrets not present — skipping cert cleanup.");
    return;
  }
  const token = makeToken();
  const certs = (await api(token, "GET", "/certificates?limit=200")).data || [];
  const development = certs.filter((certificate) =>
    /DEVELOPMENT/i.test(certificate.attributes?.certificateType || "")
  );
  console.log(`Certificates: ${certs.length} total — ${development.length} development.`);

  let revoked = 0;
  for (const certificate of development) {
    try {
      await api(token, "DELETE", `/certificates/${certificate.id}`);
      revoked++;
      console.log(`  revoked DEVELOPMENT "${certificate.attributes?.displayName}" (${certificate.id})`);
    } catch (error) {
      console.log(`  could not revoke ${certificate.id}: ${error.message}`);
    }
  }
  console.log(`Revoked ${revoked} development cert(s).`);
}

main().catch((error) => {
  console.log(`Cert cleanup skipped (non-fatal): ${error.message}`);
  process.exit(0);
});
