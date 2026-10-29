-- 121: Plaka Tanima A3 - "iceride" rapor / zaman asimi esikleri, kopukluk uyari sikligi, sakin bildirimi yasi (plate_site_settings sutunlari), olay karar turune 'kara_liste',
-- kopukluk uyarisi sinirlayici (plate_alert_state), sakin bildirim tercihi (plate_notify_prefs; varsayilan KAPALI), "iceride" suresi indeksi.
-- Kaynak: src/modules/plate_alerts_schema.js (ayni ifadeler, ayni sira; test: plate_alerts). Ekleyici ve idempotent; mevcut satirlara dokunmaz.
-- Kara liste TABLOSU 073'ten beri vardir (plate_blacklist); bu migration yalniz plate_events.decision_kind CHECK listesine 'kara_liste' ekler
-- (yalniz 'kara_liste' yoksa DROP CONSTRAINT + ADD CONSTRAINT; kenar sozlesmesi surum 2).
-- Hicbir esik koda gomulu degil: hepsi plate_site_settings kaydi (yonetici ekranindan degisir).

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS inside_report_hours INTEGER NOT NULL DEFAULT 12;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS inside_timeout_hours INTEGER NOT NULL DEFAULT 24;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS alert_interval_minutes INTEGER NOT NULL DEFAULT 60;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS resident_notify_max_age_minutes INTEGER NOT NULL DEFAULT 15;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_inside_report' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_inside_report CHECK (inside_report_hours BETWEEN 1 AND 720);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_inside_timeout' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_inside_timeout CHECK (inside_timeout_hours BETWEEN 2 AND 720);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_inside_order' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_inside_order CHECK (inside_timeout_hours > inside_report_hours);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_alert_interval' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_alert_interval CHECK (alert_interval_minutes BETWEEN 5 AND 1440);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_notify_age' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_notify_age CHECK (resident_notify_max_age_minutes BETWEEN 1 AND 1440);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_decision_kind' AND conrelid = 'plate_events'::regclass AND pg_get_constraintdef(oid) LIKE '%kara_liste%') THEN
    ALTER TABLE plate_events DROP CONSTRAINT IF EXISTS chk_plate_events_decision_kind;
    ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_decision_kind CHECK (decision_kind IS NULL OR decision_kind IN ('acildi', 'red', 'tanimsiz', 'kara_liste'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS plate_alert_state (
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  last_sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, kind),
  CONSTRAINT chk_plate_alert_state_kind CHECK (kind IN ('edge_lost'))
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_alert_state_site_code_fkey' AND conrelid = 'plate_alert_state'::regclass) THEN
    ALTER TABLE plate_alert_state ADD CONSTRAINT plate_alert_state_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS plate_notify_prefs (
  site_code BIGINT NOT NULL,
  user_code INTEGER NOT NULL,
  movement_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, user_code)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_notify_prefs_site_code_fkey' AND conrelid = 'plate_notify_prefs'::regclass) THEN
    ALTER TABLE plate_notify_prefs ADD CONSTRAINT plate_notify_prefs_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_presence_since ON plate_presence (site_code, since_at) WHERE inside;
