-- 030: Modül talebi (Faz 1.1): site yöneticisi modül TALEP eder, sistem yöneticisi (süper kullanıcı) onaylar/reddeder
-- Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Faz 1.1")
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent: mevcut tabloları/verileri değiştirmez, hiçbir satır YAZMAZ.

CREATE TABLE IF NOT EXISTS module_requests (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  module_code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  requested_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  requested_by_name TEXT,
  note TEXT,
  decided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  decided_by_name TEXT,
  decision_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at TIMESTAMPTZ,
  CONSTRAINT chk_module_requests_status CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'))
);

-- Aynı (site, modül) için TEK bekleyen talep: eşzamanlı çift talep ikinci satırı oluşturamaz.
CREATE UNIQUE INDEX IF NOT EXISTS uq_module_requests_pending
  ON module_requests (site_code, module_code) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_module_requests_status_id ON module_requests (status, id DESC);
CREATE INDEX IF NOT EXISTS idx_module_requests_site_id ON module_requests (site_code, id DESC);
