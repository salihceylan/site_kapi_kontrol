-- 106: Deneme erisim kodu (P2-27, karar K10: tek kullanimlik kod, 72 saat, DEMO siteye kilitli).
-- db.js (src/modules/trial_access_schema.js) ile AYNI DDL; ekleyici ve idempotent; mevcut tablolara DOKUNMAZ (ALTER yok).
-- Kodun kendisi ASLA saklanmaz: yalniz HMAC-SHA256 ozeti (code_hash) ve tanimak icin son 4 karakter (code_hint).
-- Kod kullanilinca bir deneme hesabi (users satiri, e-posta <rastgele>@deneme.invalid) olusur; used_by bu hesabi gosterir.
-- Kullanim ATOMIKTIR: UPDATE ... WHERE used_at IS NULL (ikinci kullanim 0 satir doner).
-- closed_at: oturum bitince (sure doldu / iptal) hesabin kapatildigi an (kullanici pasife alinir, demo site yonetici bagi silinir).
CREATE TABLE IF NOT EXISTS trial_access_codes (
  id BIGSERIAL PRIMARY KEY,
  code_hash TEXT NOT NULL,
  code_hint TEXT NOT NULL,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  note TEXT,
  used_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  used_at TIMESTAMPTZ,
  session_expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  CONSTRAINT uq_trial_access_codes_hash UNIQUE (code_hash),
  CONSTRAINT chk_trial_access_codes_hint CHECK (char_length(code_hint) = 4),
  CONSTRAINT chk_trial_access_codes_note CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_trial_access_codes_used CHECK ((used_at IS NULL) = (session_expires_at IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_trial_access_codes_used_by ON trial_access_codes (used_by) WHERE used_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_trial_access_codes_created ON trial_access_codes (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_trial_access_codes_open ON trial_access_codes (session_expires_at) WHERE used_by IS NOT NULL AND closed_at IS NULL;
