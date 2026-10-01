// APNs'e Live Activity push'u: ES256 imzalı JWT ile token tabanlı kimlik doğrulama.

export interface ApnsEnv {
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_PRIVATE_KEY: string;
  APNS_BUNDLE_ID: string;
}

let cached: { token: string; issuedAt: number } | undefined;

function base64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function providerToken(env: ApnsEnv, now = Date.now()): Promise<string> {
  // Apple aynı JWT'nin 20–60 dakika arasında yeniden kullanılmasını ister.
  if (cached && now - cached.issuedAt < 50 * 60_000) return cached.token;
  const pem = env.APNS_PRIVATE_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const issuedAt = Math.floor(now / 1000);
  const unsigned = `${base64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }))}.${base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: issuedAt }))}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  const token = `${unsigned}.${base64url(signature)}`;
  cached = { token, issuedAt: now };
  return token;
}

export interface PushResult {
  ok: boolean;
  status: number;
  /** Token artık geçersiz (kart kapatılmış): kayıt silinmeli. */
  gone: boolean;
}

export async function sendLiveActivity(
  env: ApnsEnv,
  pushToken: string,
  environment: string,
  event: "update" | "end",
  contentState: unknown,
  dismissalDate?: number,
): Promise<PushResult> {
  const host = environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const aps: Record<string, unknown> = {
    timestamp: Math.floor(Date.now() / 1000),
    event,
    "content-state": contentState,
  };
  if (dismissalDate) aps["dismissal-date"] = dismissalDate;
  const response = await fetch(`https://${host}/3/device/${pushToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken(env)}`,
      "apns-push-type": "liveactivity",
      "apns-topic": `${env.APNS_BUNDLE_ID}.push-type.liveactivity`,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps }),
  });
  return { ok: response.ok, status: response.status, gone: response.status === 410 || response.status === 400 };
}
