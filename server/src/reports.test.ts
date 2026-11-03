import assert from "node:assert/strict";
import test from "node:test";
import { d1 } from "./testdb.ts";
import { REPORT_DAILY_QUOTA, RETENTION_MS, submitReport, validateReport, withdrawReport, type RouteReport } from "./reports.ts";

const report = (o: Record<string, unknown> = {}) => ({
  reportID: "8F0C2A4E-1B2C-4D5E-8F90-123456789ABC", country: "DK", city: "Kopenhag", cities: ["Kopenhag"],
  year: 2026, month: 11, nights: 4, travellers: 3, currency: "DKK",
  places: [{ ref: "p0", name: "Nyhavn", lat: 55.6798, lon: 12.5907, kind: "sight", category: "", liked: 0, verified: false }],
  days: [{ index: 0, stops: [{ ref: "p0", startMinutes: 600, durationMinutes: 60 }] }],
  budget: { food: 450000 }, expenses: [{ day: 0, category: "food", amount: 62000, splitCount: 3 }], ...o,
});

test("valid report is stored once per id", async () => {
  const db = d1();
  assert.equal(await submitReport(db, "u1", validateReport(report()) as RouteReport), "ok");
  assert.equal(await submitReport(db, "u1", validateReport(report({ nights: 5 })) as RouteReport), "ok"); // aynı kişi: üzerine yazar
  const row = await db.prepare("SELECT nights, year FROM trip_reports").first<{ nights: number; year: number }>();
  assert.deepEqual({ ...row }, { nights: 5, year: 2026 });
});

test("another contributor cannot overwrite a report", async () => {
  const db = d1();
  await submitReport(db, "u1", validateReport(report()) as RouteReport);
  assert.equal(await submitReport(db, "u2", validateReport(report()) as RouteReport), "conflict");
});

test("validation rejects bad fields", () => {
  assert.equal(typeof validateReport(report({ month: 13 })), "string");
  assert.equal(typeof validateReport(report({ year: 1990 })), "string");
  assert.equal(typeof validateReport(report({ currency: "EURO" })), "string");
  assert.equal(typeof validateReport(report({ reportID: "x" })), "string");
  assert.equal(typeof validateReport(report({ days: [{ index: 0, stops: [{ ref: "zz", durationMinutes: 60 }] }] })), "string");
  assert.equal(typeof validateReport(report({ places: [{ ref: "p0", name: "www.spam.com", lat: 1, lon: 1, kind: "sight" }] })), "string");
  assert.equal(typeof validateReport(report()), "object");
});

test("withdraw deletes only own report", async () => {
  const db = d1();
  await submitReport(db, "u1", validateReport(report()) as RouteReport);
  await withdrawReport(db, "u2", report().reportID as string);
  assert.ok(await db.prepare("SELECT id FROM trip_reports").first());
  await withdrawReport(db, "u1", report().reportID as string);
  assert.equal(await db.prepare("SELECT id FROM trip_reports").first(), null);
});

test("daily quota of 20 reports", async () => {
  const db = d1();
  for (let i = 0; i < REPORT_DAILY_QUOTA; i++) {
    const id = `8F0C2A4E-1B2C-4D5E-8F90-${String(i).padStart(12, "0")}`;
    assert.equal(await submitReport(db, "u1", validateReport(report({ reportID: id })) as RouteReport), "ok");
  }
  assert.equal(await submitReport(db, "u1", validateReport(report({ reportID: "8F0C2A4E-1B2C-4D5E-8F90-999999999999" })) as RouteReport), "quota");
});

test("reports older than 24 months are pruned on submit", async () => {
  const db = d1();
  const old = Date.now() - RETENTION_MS - 1000;
  await submitReport(db, "u1", validateReport(report()) as RouteReport, old);
  await submitReport(db, "u2", validateReport(report({ reportID: "8F0C2A4E-1B2C-4D5E-8F90-000000000777" })) as RouteReport);
  const { results } = await db.prepare("SELECT id FROM trip_reports").all<{ id: string }>();
  assert.equal(results.length, 1);
});

test("re-submitting a stored report does not consume quota", async () => {
  const db = d1();
  for (let i = 0; i < REPORT_DAILY_QUOTA; i++) {
    const id = `8F0C2A4E-1B2C-4D5E-8F90-${String(i).padStart(12, "0")}`;
    await submitReport(db, "u1", validateReport(report({ reportID: id })) as RouteReport);
  }
  const again = validateReport(report({ reportID: "8F0C2A4E-1B2C-4D5E-8F90-000000000003" })) as RouteReport;
  assert.equal(await submitReport(db, "u1", again), "ok");
});

test("stored payload is whitelisted and keeps original amounts", async () => {
  const db = d1();
  const r = validateReport(report({
    note: "secret",
    places: [{ ref: "p0", name: "Nyhavn", lat: 55.6798, lon: 12.5907, kind: "sight", category: "", liked: 0, verified: false, note: "secret" }],
    expenses: [{ day: 0, category: "food", amount: 62000, splitCount: 3, originalAmount: 100, originalCurrency: "EUR", memo: "secret" }],
  }));
  assert.equal(typeof r, "object");
  await submitReport(db, "u1", r as RouteReport);
  const row = await db.prepare("SELECT payload FROM trip_reports").first<{ payload: string }>();
  assert.ok(!row!.payload.includes("secret"));
  const payload = JSON.parse(row!.payload);
  assert.equal(payload.expenses[0].originalAmount, 100);
  assert.equal(payload.expenses[0].originalCurrency, "EUR");
  assert.equal(typeof validateReport(report({ budget: { weird: 1 } })), "string");
  assert.equal(typeof validateReport(report({ expenses: [{ day: 0, category: "food", amount: 1, splitCount: 1, originalCurrency: "euro" }] })), "string");
});
