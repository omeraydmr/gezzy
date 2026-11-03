// Biten seyahatlerin anonim rota raporları. Kişi adı, gün tarihi, not, otel ve uçuş bilgisi alınmaz.

import { isPlausibleName, type Database } from "./community.ts";

export const REPORT_DAILY_QUOTA = 20;
export const RETENTION_MS = 730 * 24 * 3600 * 1000;
export const MAX_PAYLOAD_BYTES = 64 * 1024;

const CATEGORIES = new Set(["stays", "transport", "food", "activities", "other"]);

export interface ReportPlace { ref: string; name: string; lat: number; lon: number; kind: string; category?: string; liked?: number; verified?: boolean }
export interface ReportStop { ref: string; startMinutes?: number; durationMinutes: number }
export interface ReportDay { index: number; stops: ReportStop[] }
export interface ReportExpense { day: number | null; category: string; amount: number; splitCount: number; originalAmount?: number; originalCurrency?: string }

export interface RouteReport {
  reportID: string;
  country: string;
  city: string;
  cities: string[];
  year: number;
  month: number;
  nights: number;
  travellers: number;
  currency: string;
  places: ReportPlace[];
  days: ReportDay[];
  budget: Record<string, number>;
  expenses: ReportExpense[];
}

const UUID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
const int = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;

export function validateReport(x: unknown): RouteReport | string {
  const r = x as Partial<RouteReport> | null;
  if (typeof r !== "object" || r === null) return "body";
  if (typeof r.reportID !== "string" || !UUID.test(r.reportID)) return "reportID";
  if (typeof r.country !== "string" || !/^[A-Z]{2}$/.test(r.country)) return "country";
  if (typeof r.city !== "string" || !isPlausibleName(r.city) || r.city.length > 80) return "city";
  const cities = r.cities ?? [];
  if (!Array.isArray(cities) || cities.length > 20 || cities.some((c) => typeof c !== "string" || c.length > 80 || !isPlausibleName(c))) return "cities";
  if (!int(r.year, 2000, 2100)) return "year";
  if (!int(r.month, 1, 12)) return "month";
  if (!int(r.nights, 0, 90)) return "nights";
  if (!int(r.travellers, 1, 30)) return "travellers";
  if (typeof r.currency !== "string" || !/^[A-Z]{3}$/.test(r.currency)) return "currency";
  if (!Array.isArray(r.places) || r.places.length < 1 || r.places.length > 200) return "places";
  const refs = new Set<string>();
  for (const p of r.places) {
    if (typeof p?.ref !== "string" || p.ref.length > 64 || refs.has(p.ref)) return "ref";
    refs.add(p.ref);
    if (typeof p.name !== "string" || !isPlausibleName(p.name)) return "name";
    if (typeof p.lat !== "number" || typeof p.lon !== "number" || !(Math.abs(p.lat) <= 90) || !(Math.abs(p.lon) <= 180)) return "coordinate";
    if (typeof p.kind !== "string" || p.kind.length > 30) return "kind";
    if (p.category !== undefined && (typeof p.category !== "string" || p.category.length > 40 || (p.category !== "" && !isPlausibleName(p.category)))) return "category";
    if (p.liked !== undefined && ![1, 0, -1].includes(p.liked)) return "liked";
    if (p.verified !== undefined && typeof p.verified !== "boolean") return "verified";
  }
  if (!Array.isArray(r.days) || r.days.length > 60) return "days";
  for (const d of r.days) {
    if (!int(d?.index, 0, 1000) || !Array.isArray(d.stops) || d.stops.length > 30) return "day";
    for (const s of d.stops) {
      if (typeof s?.ref !== "string" || !refs.has(s.ref)) return "stop";
      if (s.startMinutes !== undefined && s.startMinutes !== null && !int(s.startMinutes, 0, 1439)) return "startMinutes";
      if (!int(s.durationMinutes, 0, 1440)) return "durationMinutes";
    }
  }
  const budget = r.budget ?? {};
  if (typeof budget !== "object" || Array.isArray(budget) || Object.keys(budget).length > 30) return "budget";
  for (const [k, v] of Object.entries(budget)) if (!CATEGORIES.has(k) || !int(v, 0, 1e9)) return "budget";
  const expenses = r.expenses ?? [];
  if (!Array.isArray(expenses) || expenses.length > 500) return "expenses";
  for (const e of expenses) {
    if (typeof e?.category !== "string" || !CATEGORIES.has(e.category) || !int(e.amount, 0, 1e9) || !int(e.splitCount, 1, 30)) return "expense";
    if (e.day !== null && e.day !== undefined && !int(e.day, 0, 1000)) return "expense";
    if (e.originalAmount !== undefined && !int(e.originalAmount, 0, 1e9)) return "expense";
    if (e.originalCurrency !== undefined && (typeof e.originalCurrency !== "string" || !/^[A-Z]{3}$/.test(e.originalCurrency))) return "expense";
  }
  const clean: RouteReport = {
    reportID: r.reportID, country: r.country, city: r.city, cities, year: r.year, month: r.month, nights: r.nights,
    travellers: r.travellers, currency: r.currency,
    places: r.places.map((p) => ({ ref: p.ref, name: p.name, lat: p.lat, lon: p.lon, kind: p.kind, category: p.category ?? "", liked: p.liked ?? 0, verified: p.verified ?? false })),
    days: r.days.map((d) => ({ index: d.index, stops: d.stops.map((s) => ({ ref: s.ref, startMinutes: s.startMinutes ?? undefined, durationMinutes: s.durationMinutes })) })),
    budget: { ...(budget as Record<string, number>) },
    expenses: expenses.map((e) => ({ day: e.day ?? null, category: e.category, amount: e.amount, splitCount: e.splitCount, originalAmount: e.originalAmount, originalCurrency: e.originalCurrency })),
  };
  if (JSON.stringify(clean).length > MAX_PAYLOAD_BYTES) return "size";
  return clean;
}

/** Raporu kaydeder. Aynı kişinin aynı id'li raporu üzerine yazılır; başkasınınki "conflict"; kota aşılırsa "quota". */
export async function submitReport(db: Database, contributor: string, r: RouteReport, now = Date.now()): Promise<"ok" | "conflict" | "quota"> {
  await db.prepare("DELETE FROM trip_reports WHERE created_at < ?").bind(now - RETENTION_MS).run();
  const existing = await db.prepare("SELECT contributor FROM trip_reports WHERE id = ?").bind(r.reportID).first<{ contributor: string }>();
  if (existing && existing.contributor !== contributor) return "conflict";
  if (!existing) { // aynı raporun yeniden gönderimi (yeniden deneme) kota harcamaz
    const day = "r:" + new Date(now).toISOString().slice(0, 10);
    const used = await db.prepare("SELECT count FROM quotas WHERE contributor = ? AND day = ?").bind(contributor, day).first<{ count: number }>();
    if ((used?.count ?? 0) + 1 > REPORT_DAILY_QUOTA) return "quota";
    await db.prepare(
      "INSERT INTO quotas (contributor, day, count) VALUES (?, ?, 1) ON CONFLICT (contributor, day) DO UPDATE SET count = count + 1",
    ).bind(contributor, day).run();
  }
  const payload = JSON.stringify({ cities: r.cities, places: r.places, days: r.days, budget: r.budget, expenses: r.expenses });
  await db.prepare(
    `INSERT INTO trip_reports (id, contributor, country, city, year, month, nights, travellers, currency, payload, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (id) DO UPDATE SET country = excluded.country, city = excluded.city, year = excluded.year, month = excluded.month,
       nights = excluded.nights, travellers = excluded.travellers, currency = excluded.currency, payload = excluded.payload,
       created_at = excluded.created_at`,
  ).bind(r.reportID, contributor, r.country, r.city, r.year, r.month, r.nights, r.travellers, r.currency, payload, now).run();
  return "ok";
}

/** Yalnızca kendi raporunu siler; başkasınınki ya da olmayan sessizce yok sayılır. */
export async function withdrawReport(db: Database, contributor: string, id: string): Promise<void> {
  await db.prepare("DELETE FROM trip_reports WHERE id = ? AND contributor = ?").bind(id, contributor).run();
}
