// Traveller canlı uçuş kartı sunucusu (Cloudflare Worker).
//  POST   /activities          uygulama kartın push token'ını ve uçuşu kaydeder
//  DELETE /activities/:token   kart kapatıldı
//  cron   */5                  izlenen uçuşları AeroDataBox'tan sorgular, değişeni APNs ile gönderir

import { sendLiveActivity, type ApnsEnv } from "./apns.ts";
import { contentState, isFinished, isWatchWindow, parseAeroDataBox, type Registration } from "./flight.ts";

interface Env extends ApnsEnv {
  ACTIVITIES: KVNamespace;
  CLIENT_KEY: string;
  RAPIDAPI_KEY: string;
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
