-- 085: kalici (DB) deneme sinirlari. 4 haneli ilk PIN ile girisin, e-posta ve SMS dogrulama kodlarinin yanlis deneme sayaci + kilidi:
-- yeniden baslatmada / dagitimda sifirlanmaz (bellek ici login_guard sifirlanir). Ekleyici, idempotent (IF NOT EXISTS), FK'siz.
-- target = SHA-256 ozeti (e-posta / telefon / hesap duz metin tutulmaz); PIN hedefi parola ozetini de icerir (PIN yenilenince sayac sifirdan baslar).
-- fail_count: penceredeki yanlis sayisi; window_started_at: pencere basi; locked_until: kilit bitisi; lock_level: art arda kilit sayisi (sure iki katina cikar).
-- Esikler uygulamada (server/src/security/attempt_limits.js): PIN 5 yanlis -> 15 dk; e-posta/SMS kodu 24 saatte 15 yanlis -> 1 sa.
CREATE TABLE IF NOT EXISTS auth_attempt_limits (
  scope TEXT NOT NULL,
  target TEXT NOT NULL,
  fail_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_until TIMESTAMPTZ,
  lock_level SMALLINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_auth_attempt_limits PRIMARY KEY (scope, target),
  CONSTRAINT chk_auth_attempt_limits_scope CHECK (char_length(scope) BETWEEN 1 AND 40),
  CONSTRAINT chk_auth_attempt_limits_target CHECK (char_length(target) BETWEEN 1 AND 128),
  CONSTRAINT chk_auth_attempt_limits_counters CHECK (fail_count >= 0 AND lock_level >= 0)
);
CREATE INDEX IF NOT EXISTS idx_auth_attempt_limits_updated ON auth_attempt_limits (updated_at);
