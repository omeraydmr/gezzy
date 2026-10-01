import assert from "node:assert/strict";
import test from "node:test";
import { sendLiveActivity } from "./apns.ts";

test("push request carries a valid ES256 provider token and live activity headers", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
  const env = { APNS_KEY_ID: "ABC123", APNS_TEAM_ID: "4BAD86T55H", APNS_PRIVATE_KEY: pem, APNS_BUNDLE_ID: "app.traveller.ios" };

  let captured: { url: string; init: RequestInit } | undefined;
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    captured = { url, init };
    return new Response(null, { status: 200 });
  }) as typeof fetch;

  const result = await sendLiveActivity(env, "ab01", "development", "update", { status: "Biniş" });
  assert.equal(result.ok, true);
  assert.equal(captured!.url, "https://api.sandbox.push.apple.com/3/device/ab01");
  const headers = captured!.init.headers as Record<string, string>;
  assert.equal(headers["apns-push-type"], "liveactivity");
  assert.equal(headers["apns-topic"], "app.traveller.ios.push-type.liveactivity");
  const body = JSON.parse(captured!.init.body as string);
  assert.equal(body.aps.event, "update");
  assert.deepEqual(body.aps["content-state"], { status: "Biniş" });

  const [header, claims, signature] = headers.authorization.replace("bearer ", "").split(".");
  const decode = (part: string) => Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  assert.deepEqual(JSON.parse(new TextDecoder().decode(decode(header))), { alg: "ES256", kid: "ABC123" });
  assert.equal(JSON.parse(new TextDecoder().decode(decode(claims))).iss, "4BAD86T55H");
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, decode(signature),
    new TextEncoder().encode(`${header}.${claims}`));
  assert.equal(valid, true);
});
