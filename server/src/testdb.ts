import { DatabaseSync } from "node:sqlite";
import { readdirSync, readFileSync } from "node:fs";
import type { Database } from "./community.ts";

/** node:sqlite'ı D1 arayüzüne uyduran küçük adaptör. */
export function d1(): Database {
  const db = new DatabaseSync(":memory:");
  const dir = new URL("../migrations/", import.meta.url);
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()) {
    db.exec(readFileSync(new URL(file, dir), "utf8"));
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
