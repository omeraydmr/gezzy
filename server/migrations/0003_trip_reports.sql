-- Biten seyahatlerin rota raporları (kullanıcı izin verdiyse). Kişi adı, gün tarihi, not, otel, uçuş tutulmaz.
CREATE TABLE IF NOT EXISTS trip_reports (
  id TEXT PRIMARY KEY,
  contributor TEXT NOT NULL,
  country TEXT NOT NULL,
  city TEXT NOT NULL,
  year INTEGER NOT NULL,
  month INTEGER NOT NULL,
  nights INTEGER NOT NULL,
  travellers INTEGER NOT NULL,
  currency TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS trip_reports_country_city ON trip_reports (country, city);
CREATE INDEX IF NOT EXISTS trip_reports_created ON trip_reports (created_at);
