-- Topluluk öneri havuzu. Kişi kimliği saklanmaz: "contributor", cihaza özel rastgele kimliğin sunucudaki
-- gizli tuzla (CONTRIBUTOR_SALT) alınmış SHA-256 özetidir; yalnızca aynı kişinin aynı yeri iki kez
-- saymasını önlemek için kullanılır. Tarih, ekip ve tam rota tutulmaz.

CREATE TABLE IF NOT EXISTS places (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  country TEXT NOT NULL,
  name TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  kind TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS places_lat_lon ON places (lat, lon);

-- Kişi başına bir oy: gidildi mi (fotoğrafla doğrulandı mı) ve beğenildi mi (1, -1, 0 = belirtilmedi).
CREATE TABLE IF NOT EXISTS votes (
  place_id INTEGER NOT NULL REFERENCES places (id),
  contributor TEXT NOT NULL,
  liked INTEGER NOT NULL DEFAULT 0,
  verified INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (place_id, contributor)
);

-- Aynı gün art arda gidilen iki yer ("A'dan sonra B"); kişi başına bir kez.
CREATE TABLE IF NOT EXISTS transitions (
  from_id INTEGER NOT NULL REFERENCES places (id),
  to_id INTEGER NOT NULL REFERENCES places (id),
  contributor TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (from_id, to_id, contributor)
);
CREATE INDEX IF NOT EXISTS transitions_from ON transitions (from_id);

-- Kötüye kullanım sınırı: kişi başına günlük katkı sayısı.
CREATE TABLE IF NOT EXISTS quotas (
  contributor TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (contributor, day)
);
