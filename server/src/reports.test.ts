import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import test from "node:test";
import type { Database } from "./community.ts";
import { REPORT_DAILY_QUOTA, RETENTION_MS, submitReport, validateReport, withdrawReport, type RouteReport } from "./reports.ts";

/** node:sqlite'ı D1 arayüzüne uyduran küçük adaptör. */
function d1(): Database {
  const db = new DatabaseSync(":memory:");
  for (const file of ["0001_community.sql", "0002_attest_reports.sql", "0003_trip_reports.sql"]) {
    db.exec(readFileSync(new URL(`../migrations/${file}`, import.meta.url), "utf8"));
  }
  return {
    prepare(sql: string) {
      let values: unknown[] = [];
      const statement = {
        bind(...v: unknown[]) { values = v; return statement; },
        async first<T>() { return (db.prepare(sql).get(...(values as never[])) ?? null) as T | null; },
        async all<T>() { return { results: db.prepare(sql).all(...(values as never[])) as T[] }; },
        async run() { return db.prepare(sql).run(...(values as never[])); },
      };
      return statement;
    },
  };
}

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
