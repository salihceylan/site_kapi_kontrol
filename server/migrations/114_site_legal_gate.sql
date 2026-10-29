-- 114: Site basina hukuk onayi bayragi (sites.legal_ok). Satis hazirligi: gecikme tazminati ve borc hatirlatma, sistem geneli `finance.legal_ok` yerine SITE bazinda kapilanir.
-- db.js ile ayni ifadeler, ayni sira (src/modules/site_legal_gate_schema.js SITE_LEGAL_GATE_DDL; test: site_legal_gate_schema).
-- 1) Sutun DEFAULT TRUE ile eklenir: sutun eklendigi anda MEVCUT tum siteler ACIK kalir (davranis kirilmaz; PG 11+ icin yalniz katalog degisikligi, tablo yeniden yazilmaz).
-- 2) Varsayilan hemen FALSE yapilir: bundan sonra olusan YENI siteler KAPALI baslar; avukat onayindan sonra super kullanici acar (PUT /admin/sites/:siteCode/finance-legal-gate, islem izi).
-- Ekleyici ve idempotent: tekrar calistirilirsa hicbir satirin degerini degistirmez. Eski sunucu surumu sutunu yok sayar; geri alma guvenlidir.

ALTER TABLE sites ADD COLUMN IF NOT EXISTS legal_ok BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE sites ALTER COLUMN legal_ok SET DEFAULT FALSE;
