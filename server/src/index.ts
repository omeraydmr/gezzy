// Traveller sunucusu (Cloudflare Worker).
//  POST   /activities          uygulama canlı uçuş kartının push token'ını ve uçuşu kaydeder
//  DELETE /activities/:token   kart kapatıldı
//  POST   /attest/challenge    App Attest için tek kullanımlık challenge (5 dk)
//  POST   /attest/register     cihaz anahtarının Apple onayı (attestation); açık anahtar saklanır
//  POST   /places/contribute   seyahati biten kullanıcının onayla paylaştığı yerler ve geçişler (D1)
//  POST   /places/report       yanlış ya da spam yer bildirimi
//  GET    /places/nearby       ?lat&lon  en az 3 kişinin önerdiği yerler
//  GET    /places/next         ?lat&lon  bu yerden sonra en sık gidilenler
//  cron   */5                  izlenen uçuşları AeroDataBox'tan sorgular, değişeni APNs ile gönderir

import { sendLiveActivity, type ApnsEnv } from "./apns.ts";
import { base64ToBytes, verifyAssertion, verifyAttestation } from "./appattest.ts";
import { contribute, contributorHash, nearby, nextPlaces, report, validate, type Database } from "./community.ts";
import { contentState, isFinished, isWatchWindow, parseAeroDataBox, type Registration } from "./flight.ts";

interface Env extends ApnsEnv {
  ACTIVITIES: KVNamespace;
  CLIENT_KEY: string;
  RAPIDAPI_KEY: string;
  /** Topluluk öneri havuzu (D1). */
  DB: Database;
  /** Katkı veren kimliklerini özetlemek için gizli tuz. */
  CONTRIBUTOR_SALT: string;
  /** App Attest uygulama kimliği: "TEAMID.bundle.id". */
  APP_ID: string;
  /** "true" ise katkı ve bildirim yalnızca App Attest imzasıyla kabul edilir (eski cihaz kimliği yolu kapanır). */
  REQUIRE_APP_ATTEST?: string;
  /** "false" ise geliştirme (Xcode) ortamının attestation'ları reddedilir. */
  ALLOW_DEV_ATTEST?: string;
}

interface Stored {
  registration: Registration;
  lastState?: string;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function isValid(r: Partial<Registration>): r is Registration {
  return typeof r.pushToken === "string" && /^[0-9a-f]{16,256}$/.test(r.pushToken) &&
    (r.environment === "development" || r.environment === "production") &&
    typeof r.flightNumber === "string" && /^[A-Z0-9]{3,8}$/.test(r.flightNumber) &&
    typeof r.localDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(r.localDate) &&
    !isNaN(Date.parse(r.scheduledDeparture ?? "")) && !isNaN(Date.parse(r.scheduledArrival ?? ""));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (env.CLIENT_KEY && request.headers.get("x-traveller-key") !== env.CLIENT_KEY) return json({ error: "unauthorized" }, 401);
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/activities") {
      const body = (await request.json().catch(() => ({}))) as Partial<Registration>;
      if (!isValid(body)) return json({ error: "invalid registration" }, 400);
      const stored: Stored = { registration: body };
      // Varıştan 12 saat sonra kendiliğinden silinir.
      const ttl = Math.max(60, Math.floor((Date.parse(body.scheduledArrival) - Date.now()) / 1000) + 12 * 3600);
      await env.ACTIVITIES.put(body.pushToken, JSON.stringify(stored), { expirationTtl: ttl });
      return json({ ok: true });
    }
    if (url.pathname.startsWith("/places/")) return places(request, url, env);
    if (url.pathname.startsWith("/attest/")) return attest(request, url, env);
    const match = url.pathname.match(/^\/activities\/([0-9a-f]+)$/);
    if (request.method === "DELETE" && match) {
      await env.ACTIVITIES.delete(match[1]);
      return json({ ok: true });
    }
    return json({ error: "not found" }, 404);
  },

  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(checkAll(env));
  },
};

async function attest(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method !== "POST") return json({ error: "not found" }, 404);
  if (url.pathname === "/attest/challenge") {
    const challenge = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));
    await env.ACTIVITIES.put(`challenge:${challenge}`, "1", { expirationTtl: 300 });
    return json({ challenge });
  }
  if (url.pathname === "/attest/register") {
    const body = (await request.json().catch(() => ({}))) as { keyId?: string; attestation?: string; challenge?: string };
    if (!body.keyId || !body.attestation || !body.challenge || !env.APP_ID) return json({ error: "invalid" }, 400);
    // Challenge tek kullanımlık.
    if (!(await env.ACTIVITIES.get(`challenge:${body.challenge}`))) return json({ error: "challenge" }, 400);
    await env.ACTIVITIES.delete(`challenge:${body.challenge}`);
    try {
      const key = await verifyAttestation(base64ToBytes(body.attestation), body.keyId, new TextEncoder().encode(body.challenge),
                                          { appID: env.APP_ID, allowDevelopment: env.ALLOW_DEV_ATTEST !== "false" });
      await env.DB.prepare(
        `INSERT INTO attested_keys (key_id, public_key, counter, environment, created_at) VALUES (?, ?, 0, ?, ?)
         ON CONFLICT (key_id) DO NOTHING`,
      ).bind(key.keyID, btoa(String.fromCharCode(...key.publicKey)), key.environment, Date.now()).run();
      return json({ ok: true });
    } catch (error) {
      return json({ error: `attestation: ${(error as Error).message}` }, 401);
    }
  }
  return json({ error: "not found" }, 404);
}

/** Katkı ve bildirim gönderen: App Attest imzası (tercih) ya da geçiş döneminde cihaz kimliği. Özetlenmiş kimlik
 *  ya da hata yanıtı döner. */
async function sender(request: Request, body: Uint8Array, env: Env): Promise<string | Response> {
  if (!env.CONTRIBUTOR_SALT) return json({ error: "contributor" }, 400);
  const keyID = request.headers.get("x-traveller-attest-key");
  const assertion = request.headers.get("x-traveller-assertion");
  if (keyID && assertion) {
    const row = await env.DB.prepare("SELECT public_key, counter FROM attested_keys WHERE key_id = ?").bind(keyID)
      .first<{ public_key: string; counter: number }>();
    if (!row) return json({ error: "attest unknown" }, 401);
    const counter = await verifyAssertion(base64ToBytes(assertion), body, base64ToBytes(row.public_key), row.counter, env.APP_ID)
      .catch(() => null);
    if (counter === null) return json({ error: "attest" }, 401);
    await env.DB.prepare("UPDATE attested_keys SET counter = ? WHERE key_id = ?").bind(counter, keyID).run();
    return contributorHash(`attest:${keyID}`, env.CONTRIBUTOR_SALT);
  }
  if (env.REQUIRE_APP_ATTEST === "true") return json({ error: "attest required" }, 401);
  const raw = request.headers.get("x-traveller-contributor") ?? "";
  if (!/^[0-9A-Fa-f-]{36}$/.test(raw)) return json({ error: "contributor" }, 400);
  return contributorHash(raw.toLowerCase(), env.CONTRIBUTOR_SALT);
}

async function places(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method === "POST" && (url.pathname === "/places/contribute" || url.pathname === "/places/report")) {
    // İmza istek gövdesinin baytları üzerinden doğrulanır; JSON ondan sonra okunur.
    const bytes = new Uint8Array(await request.arrayBuffer());
    const who = await sender(request, bytes, env);
    if (who instanceof Response) return who;
    let parsed: unknown = null;
    try { parsed = JSON.parse(new TextDecoder().decode(bytes)); } catch { /* geçersiz gövde */ }
    if (url.pathname === "/places/report") {
      const r = parsed as { placeId?: number; reason?: string } | null;
      return (await report(env.DB, who, Number(r?.placeId), String(r?.reason ?? ""))) ? json({ ok: true }) : json({ error: "invalid" }, 400);
    }
    const body = validate(parsed);
    if (typeof body === "string") return json({ error: `invalid ${body}` }, 400);
    const accepted = await contribute(env.DB, who, body);
    return accepted ? json({ ok: true }) : json({ error: "quota" }, 429);
  }
  if (request.method === "GET" && (url.pathname === "/places/nearby" || url.pathname === "/places/next")) {
    const lat = Number(url.searchParams.get("lat")), lon = Number(url.searchParams.get("lon"));
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return json({ error: "coordinate" }, 400);
    }
    const result = url.pathname === "/places/nearby" ? await nearby(env.DB, lat, lon) : await nextPlaces(env.DB, lat, lon);
    return new Response(JSON.stringify({ places: result }), {
      headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" },
    });
  }
  return json({ error: "not found" }, 404);
}

async function checkAll(env: Env, now = new Date()): Promise<void> {
  let cursor: string | undefined;
  const statuses = new Map<string, unknown>();
  do {
    const page = await env.ACTIVITIES.list({ cursor });
    for (const key of page.keys) {
      const raw = await env.ACTIVITIES.get(key.name);
      if (!raw) continue;
      const stored = JSON.parse(raw) as Stored;
      const registration = stored.registration;
      if (!isWatchWindow(registration, now)) continue;

      // Aynı uçuşu izleyen birden çok kart için tek sorgu.
      const flightKey = `${registration.flightNumber}/${registration.localDate}`;
      if (!statuses.has(flightKey)) statuses.set(flightKey, await fetchFlight(env, registration));
      const status = parseAeroDataBox(statuses.get(flightKey), new Date(registration.scheduledDeparture));
      if (!status) continue;

      const state = contentState(registration, status);
      const serialized = JSON.stringify(state);
      const finished = isFinished(status);
      if (serialized === stored.lastState && !finished) continue;

      const result = await sendLiveActivity(env, registration.pushToken, registration.environment,
        finished ? "end" : "update", state, finished ? Math.floor(now.getTime() / 1000) + 3600 : undefined);
      if (result.gone || finished) {
        await env.ACTIVITIES.delete(key.name);
      } else if (result.ok) {
        await env.ACTIVITIES.put(key.name, JSON.stringify({ ...stored, lastState: serialized }), {
          expiration: key.expiration,
        });
      }
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
}

async function fetchFlight(env: Env, registration: Registration): Promise<unknown> {
  const response = await fetch(
    `https://aerodatabox.p.rapidapi.com/flights/number/${registration.flightNumber}/${registration.localDate}?withAircraftImage=false&withLocation=false`,
    { headers: { "X-RapidAPI-Key": env.RAPIDAPI_KEY, "X-RapidAPI-Host": "aerodatabox.p.rapidapi.com" } },
  );
  if (!response.ok) return undefined;
  return response.json().catch(() => undefined);
}
