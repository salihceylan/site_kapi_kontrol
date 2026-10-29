-- 117: Site basina SMS + WhatsApp baglantisi (yonetici kendi saglayicisini baglar). Tablo: site_messaging_connections (site_code, channel) birincil anahtarli.
-- db.js ile ayni ifade (src/modules/messaging_schema.js MESSAGING_DDL; test: messaging_connections). Yeni tablo; mevcut tablolara dokunulmaz, geri alma guvenlidir.
-- config = sirsiz alanlar (sms: header; whatsapp: phone_number_id, business_name). secret_enc = AES-256-GCM sifreli JSON (sms: usercode + password; whatsapp: access_token),
-- anahtar .env MESSAGING_SECRET_KEY (en az 32 karakter; DB'ye YAZILMAZ). Anahtar yoksa baglanti kaydedilmez / sinanamaz (503); SMS gonderiminde site ayari yoksa global .env kullanilir.

CREATE TABLE IF NOT EXISTS site_messaging_connections (
  site_code INTEGER NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  provider TEXT NOT NULL,
  config JSONB NOT NULL DEFAULT '{}'::jsonb,
  secret_enc TEXT NOT NULL,
  last_test_at TIMESTAMPTZ,
  last_test_ok BOOLEAN,
  last_test_code TEXT,
  updated_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, channel),
  CONSTRAINT chk_site_messaging_channel CHECK (channel IN ('sms', 'whatsapp'))
);
