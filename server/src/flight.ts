// Uçuş durumundan canlı kart içeriği üretir. Uygulamadaki FlightStatusParser ve
// FlightSegment.statusText mantığının sunucu kopyası; değiştirirken ikisini birlikte güncelle.

export type Phase =
  | "scheduled" | "checkIn" | "boarding" | "gateClosed" | "departed" | "enRoute"
  | "approaching" | "arrived" | "delayed" | "canceled" | "diverted" | "unknown";

export interface Registration {
  pushToken: string;
  environment: "development" | "production";
  language: string;
  flightNumber: string;
  localDate: string;
  scheduledDeparture: string;
  scheduledArrival: string;
  seat?: string | null;
  gate?: string | null;
}

export interface LiveStatus {
  phase: Phase;
  gate?: string;
  terminal?: string;
  estimatedDeparture?: Date;
  estimatedArrival?: Date;
}

/** ActivityKit `FlightActivityAttributes.ContentState` ile aynı anahtarlar. */
export interface ContentState {
  gate?: string;
  seat?: string;
  terminal?: string;
  status: string;
  /** Apple referans tarihinden (2001-01-01) saniye: Swift'in varsayılan Date çözümü. */
  departure: number;
  arrival: number;
  isDelayed: boolean;
  isCanceled: boolean;
}

export const DELAY_THRESHOLD_MINUTES = 15;
const APPLE_EPOCH_OFFSET = 978_307_200;

export function appleTime(date: Date): number {
  return date.getTime() / 1000 - APPLE_EPOCH_OFFSET;
}

function parseTime(value: unknown): Date | undefined {
  const raw = (value as { utc?: string } | undefined)?.utc?.trim();
  if (!raw) return undefined;
  const iso = raw.replace(" ", "T").replace(/Z$/, "") + (raw.length <= 17 ? ":00Z" : "Z");
  const date = new Date(iso);
  return isNaN(date.getTime()) ? undefined : date;
}

function nonEmpty(value: unknown): string | undefined {
  const text = typeof value === "string" ? value.trim() : "";
  return text ? text : undefined;
}

export function phaseFrom(status: unknown): Phase {
  switch (String(status ?? "").toLowerCase()) {
    case "expected": return "scheduled";
    case "checkin": return "checkIn";
    case "boarding": return "boarding";
    case "gateclosed": return "gateClosed";
    case "departed": return "departed";
    case "enroute": return "enRoute";
    case "approaching": return "approaching";
    case "arrived": return "arrived";
    case "delayed": return "delayed";
    case "canceled": case "cancelled": case "canceleduncertain": return "canceled";
    case "diverted": return "diverted";
    default: return "unknown";
  }
}

/** AeroDataBox `/flights/number/{numara}/{tarih}` yanıtından planlanana en yakın kaydı çözer. */
export function parseAeroDataBox(body: unknown, scheduledDeparture: Date): LiveStatus | undefined {
  if (!Array.isArray(body) || body.length === 0) return undefined;
  let best: any;
  let bestDistance = Infinity;
  for (const entry of body) {
    const scheduled = parseTime(entry?.departure?.scheduledTime);
    const distance = scheduled ? Math.abs(scheduled.getTime() - scheduledDeparture.getTime()) : Infinity;
    if (distance < bestDistance || best === undefined) { best = entry; bestDistance = distance; }
  }
  if (bestDistance > 18 * 3600_000 && body.length > 1) return undefined;
  const departure = best.departure ?? {};
  const arrival = best.arrival ?? {};
  const estimatedDeparture = parseTime(departure.revisedTime) ?? parseTime(departure.predictedTime) ?? parseTime(departure.runwayTime);
  const estimatedArrival = parseTime(arrival.revisedTime) ?? parseTime(arrival.predictedTime) ?? parseTime(arrival.runwayTime);
  let phase = phaseFrom(best.status);
  if (phase === "scheduled" && estimatedDeparture &&
      estimatedDeparture.getTime() - scheduledDeparture.getTime() >= DELAY_THRESHOLD_MINUTES * 60_000) {
    phase = "delayed";
  }
  return { phase, gate: nonEmpty(departure.gate), terminal: nonEmpty(departure.terminal), estimatedDeparture, estimatedArrival };
}

const TITLES: Record<string, Record<Phase, string>> = {
  tr: {
    scheduled: "Zamanında", checkIn: "Check-in açık", boarding: "Biniş", gateClosed: "Kapı kapandı", departed: "Kalktı",
    enRoute: "Havada", approaching: "İnişe geçti", arrived: "İndi", delayed: "Rötarlı", canceled: "İptal",
    diverted: "Yönlendirildi", unknown: "Bilinmiyor",
  },
  en: {
    scheduled: "On time", checkIn: "Check-in open", boarding: "Boarding", gateClosed: "Gate closed", departed: "Departed",
    enRoute: "In the air", approaching: "Approaching", arrived: "Landed", delayed: "Delayed", canceled: "Canceled",
    diverted: "Diverted", unknown: "Unknown",
  },
};

const AIRBORNE_OR_DONE: Phase[] = ["departed", "enRoute", "approaching", "arrived", "diverted"];

export function contentState(registration: Registration, status: LiveStatus): ContentState {
  const titles = TITLES[registration.language] ?? TITLES.en;
  const scheduledDeparture = new Date(registration.scheduledDeparture);
  const scheduledArrival = new Date(registration.scheduledArrival);
  const delayMinutes = status.estimatedDeparture
    ? Math.max(0, Math.round((status.estimatedDeparture.getTime() - scheduledDeparture.getTime()) / 60_000))
    : 0;
  const isDelayed = delayMinutes >= DELAY_THRESHOLD_MINUTES;
  const airborne = AIRBORNE_OR_DONE.includes(status.phase);
  const departure = isDelayed ? status.estimatedDeparture ?? scheduledDeparture : scheduledDeparture;
  const arrival = status.estimatedArrival && (isDelayed || airborne) ? status.estimatedArrival : scheduledArrival;

  let text: string;
  if (status.phase === "canceled") text = titles.canceled;
  else if (isDelayed && !airborne && status.phase !== "boarding") {
    text = registration.language === "tr" ? `Rötarlı +${delayMinutes} dk` : `Delayed +${delayMinutes} min`;
  } else text = titles[status.phase];

  return {
    gate: status.gate ?? registration.gate ?? undefined,
    seat: registration.seat ?? undefined,
    terminal: status.terminal,
    status: text,
    departure: appleTime(departure),
    arrival: appleTime(arrival),
    isDelayed,
    isCanceled: status.phase === "canceled",
  };
}

/** Uçuşun izlenme penceresi: kalkıştan 8 saat önce başlar, varıştan 1 saat sonra biter. */
export function isWatchWindow(registration: Registration, now: Date): boolean {
  const departure = new Date(registration.scheduledDeparture).getTime();
  const arrival = new Date(registration.scheduledArrival).getTime();
  return now.getTime() >= departure - 8 * 3600_000 && now.getTime() <= arrival + 6 * 3600_000;
}

export function isFinished(status: LiveStatus): boolean {
  return status.phase === "arrived";
}
