import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import test from "node:test";
import { contribute, contributorHash, DAILY_QUOTA, nearby, nextPlaces, validate, type Contribution, type Database } from "./community.ts";

/** node:sqlite'ı D1 arayüzüne uyduran küçük adaptör. */
function d1(): Database {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../migrations/0001_community.sql", import.meta.url), "utf8"));
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

const castle = { ref: "a", name: "São Jorge Castle", lat: 38.7139, lon: -9.1335, kind: "sight", category: "Kale", liked: 1, verified: true };
const lift = { ref: "b", name: "Santa Justa Lift", lat: 38.7121, lon: -9.1394, kind: "sight", liked: 1, verified: false };
const cafe = { ref: "c", name: "Café A Brasileira", lat: 38.7107, lon: -9.1424, kind: "food", liked: 0, verified: true };
const trip = (overrides: Partial<Contribution> = {}): Contribution =>
  ({ country: "PT", places: [castle, lift, cafe], transitions: [["a", "b"], ["b", "c"]], ...overrides });

test("places appear only after three different contributors (k-anonymity)", async () => {
  const db = d1();
  await contribute(db, "u1", trip());
  await contribute(db, "u2", trip());
  assert.equal((await nearby(db, 38.712, -9.138)).length, 0);
  await contribute(db, "u2", trip()); // aynı kişi tekrar: sayılmaz
  assert.equal((await nearby(db, 38.712, -9.138)).length, 0);
  await contribute(db, "u3", trip());
  const places = await nearby(db, 38.712, -9.138);
  assert.equal(places.length, 3);
  assert.equal(places[0].name, "São Jorge Castle", "Doğrulanmış ziyaret + beğeni en üstte");
  assert.equal(places[0].contributors, 3);
});

test("same place in another language and slightly different coordinate merges", async () => {
  const db = d1();
  await contribute(db, "u1", trip({ places: [castle], transitions: [] }));
  await contribute(db, "u2", trip({ places: [{ ...castle, name: "São Jorge Kalesi", lat: 38.71395 }], transitions: [] }));
  await contribute(db, "u3", trip({ places: [{ ...castle, name: "Castelo de São Jorge", lon: -9.13355 }], transitions: [] }));
  const places = await nearby(db, 38.7139, -9.1335);
  assert.equal(places.length, 1);
  assert.equal(places[0].contributors, 3);
});

test("disliked places are hidden", async () => {
  const db = d1();
  for (const u of ["u1", "u2", "u3"]) {
    await contribute(db, u, trip({ places: [{ ...lift, liked: u === "u1" ? 1 : -1 }], transitions: [] }));
  }
  assert.equal((await nearby(db, 38.7121, -9.1394)).length, 0);
});

test("next places need three contributors who made the same move", async () => {
  const db = d1();
  await contribute(db, "u1", trip());
  await contribute(db, "u2", trip());
  await contribute(db, "u3", trip({ transitions: [["a", "c"]] }));
  assert.equal((await nextPlaces(db, castle.lat, castle.lon)).length, 0);
  await contribute(db, "u4", trip());
  const next = await nextPlaces(db, castle.lat, castle.lon);
  assert.deepEqual(next.map((p) => [p.name, p.followers]), [["Santa Justa Lift", 3]]);
});

test("daily quota", async () => {
  const db = d1();
  const many = Array.from({ length: 60 }, (_, i) => ({ ...castle, ref: `r${i}`, name: `Yer ${i}`, lat: 38 + i * 0.01 }));
  let accepted = 0;
  for (let i = 0; i < 10; i++) if (await contribute(db, "spammer", { country: "PT", places: many, transitions: [] })) accepted++;
  assert.equal(accepted, Math.floor(DAILY_QUOTA / 60));
});

test("validation", () => {
  assert.equal(typeof validate(trip()), "object");
  assert.equal(validate({ ...trip(), country: "pt" }), "country");
  assert.equal(validate({ ...trip(), transitions: [["a", "zz"]] }), "transition");
  assert.equal(validate({ ...trip(), places: [{ ...castle, kind: "bar" }] }), "kind");
  assert.equal(validate({ ...trip(), places: [] }), "places");
});

test("contributor hash is salted and stable", async () => {
  const id = "3F2504E0-4F89-11D3-9A0C-0305E82C3301".toLowerCase();
  assert.equal(await contributorHash(id, "s"), await contributorHash(id, "s"));
  assert.notEqual(await contributorHash(id, "s"), await contributorHash(id, "t"));
  assert.ok(!(await contributorHash(id, "s")).includes("3f2504e0"));
});
