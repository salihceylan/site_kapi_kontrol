# Platform — Kurallar tablosu (G11) sözleşmesi

Bu belge sunucu (`server/`) ve uygulama (`lib/`) için BAĞLAYICIDIR. Karar: `docs/PLATFORM_YOL_HARITASI.md` "Karar kaydı (2026-10-21)" G11
("%5 gecikme", "90 gün geçici bütçe", "itiraz süresi", "%70/%30 ısı payı" gibi değerler koddan değil tablodan okunur; her kuralın
geçerlilik tarihi ve mevzuat notu olur; yasal üst sınır site ayarıyla aşılamaz) ve H2 (saklama süreleri kural verisi olarak; otomatik silme
avukat onayına kadar kapalı). Ana plan: `docs/superpowers/plans/2026-10-21-eksik-listesi-programi.md` sözleşme 2.2; alt plan
`docs/superpowers/plans/2026-10-21-ip-1b.md`.

`[AVUKAT DOĞRULASIN]` işareti hukuki yorum gerektiren maddedir; mevzuat notları bilgi amaçlıdır, hukuki görüş değildir.

## Kurallar

Kayıt defteri: `server/src/modules/platform_rules.js` (`RULES`, sıra = ekrandaki sıra). Birimler: `bp` baz puan (100 bp = %1), `pct` yüzde,
`days` gün. "Site": sitede değişebilir mi (site değeri verilebilir). "Plan": ileri tarihli değer yazılabilir mi.

| Anahtar | Ad | Tür | Varsayılan | Sınır | Site | Plan | Not |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `finance.late_fee.monthly_bp_max` | Gecikme tazminatı aylık üst sınırı | bp | 500 (%5) | 0..500 | hayır | hayır | KMK 634 m.20/2 aylık %5; yasal sınır kodda da korunur |
| `budget.provisional_max_days` | Geçici işletme projesi en uzun süresi | gün | 90 | 1..90 | hayır | evet | KMK m.37 (7579 ile değişik), karar F7 |
| `budget.objection_days` | İşletme projesine itiraz süresi | gün | 7 | 1..30 | hayır | evet | KMK m.37, karar F7 |
| `heat.measured_share_pct` | Isınma gideri: ölçüme göre pay | yüzde | 70 | 0..100 | hayır | evet | çift: alan payıyla toplam 100 (karar T2) |
| `heat.area_share_pct` | Isınma gideri: alan payı | yüzde | 30 | 0..100 | hayır | evet | çift: ölçüme göre payla toplam 100; alan payı, katılan dairelerin hepsinde arsa payı tanımlıysa arsa payına, değilse eşit dağıtılır (m² kaldırıldı) |
| `forecast.default_increase_bp` | Gelecek yıl tahmini: varsayılan artış oranı | bp | 0 | 0..10000 | EVET | evet | ürün varsayılanı (karar R1) |
| `retention.finance_days` | Mali kayıtlar | gün | 3650 | 1825..7300 | hayır | evet | TTK m.82, VUK m.253; H2: 10 yıl |
| `retention.contact_after_moveout_days` | Taşınan kişinin iletişim bilgileri | gün | 365 | 30..3650 | hayır | evet | KVKK m.4/2-d, m.7; H2: açık borç yoksa 1 yıl |
| `retention.door_logs_days` | Kapı geçiş kayıtları | gün | 365 | 30..3650 | hayır | evet | H2: 1 yıl; bugün bakım işi 30 gün sonra siler (aşağıda) |
| `retention.visitor_logs_days` | Ziyaretçi ve kargo kayıtları | gün | 365 | 30..3650 | hayır | evet | H2: 1 yıl |
| `retention.work_photos_after_close_days` | İş takibi fotoğrafları (talep kapandıktan sonra) | gün | 730 | 30..3650 | hayır | evet | H2: 2 yıl |
| `retention.announcements_days` | Duyurular | gün | 1825 | 365..3650 | hayır | evet | H2: 5 yıl |
| `retention.audit_days` | Denetim kaydı | gün | 1825 | 365..3650 | hayır | evet | H2: 5 yıl (denetim kaydı bugün hiç silinmez) |
| `retention.residency_log_days` | Daire sakini adli kaydı | gün | 3650 | 1825..7300 | hayır | evet | KVKK m.4/2-d, m.5/2-ç,e,f, m.7; TBK m.146-147; yalnız resmî talep halinde bilgi amaçlı (`docs/PLATFORM_ADLI_KAYIT.md`); kayıt değiştirilemez, otomatik silme kapalı |
| `retention.decision_book_days` | Karar defteri | gün, süresiz olabilir | null (süresiz) | 3650..36500 ya da null | hayır | evet | KMK m.32; H2: süresiz |
| `retention.enforce` | Otomatik silme | açık / kapalı | kapalı | — | hayır | evet | KİLİTLİ: değiştirilemez (aşağıda) |

Her kuralın tam mevzuat notu kayıt defterindedir ve uçlarda `legal_note` olarak döner. Notlardaki tüm hukuki dayanaklar
`[AVUKAT DOĞRULASIN]` işaretlidir; ısınma payı yönetmeliğinin numarası ve oranları (RG 26847) mevzuat.gov.tr'den doğrulanmadı.

## Çözüm sırası, tarih ve kırpma

`getRule(db, key, { siteCode, onDate })` (`platform_rules.js`):

1. **Site değeri** (yalnız sitede değişebilen kuralda ve `siteCode` verildiyse) -> **platform değeri** -> **varsayılan** (koddaki değer).
2. Her kapsamda `onDate` (varsayılan: İstanbul bugünü) itibarıyla geçerli satır, `valid_from <= onDate` olanların en yenisidir
   (`valid_from DESC`, eşitlikte büyük `id` = sonraki kayıt). İleri tarihli satır o güne dek yok sayılır.
3. `inherit = TRUE` satırı "bu tarihten itibaren üst düzeye dön" demektir: site satırı platform değerine, platform satırı varsayılana döndürür.
4. Sitede değişemeyen kuralda site satırı (doğrudan SQL ile yazılmış olsa bile) yok sayılır.
5. **Kırpma:** sonuç HER ZAMAN kuralın sınırına kırpılır (`normalizeRuleValue`): sınır dışı tam sayı sınıra (ör. 9000 -> 500, -50 -> 0),
   tür uymayan değer (metin, ondalık, nesne, sayı kuralında boolean) ve izin verilmeyen `null` varsayılana düşer; süresiz kuralda `null` geçerlidir.
   Yazma ucu ise sınır dışı değeri KIRPMAZ, reddeder (aşağıda).

**Önbellek:** satırlar kural + site başına 30 sn bellekte tutulur (`ruleCacheTuning.ttlMs`); en çok 1000 girdi (aşılınca boşaltılır).
Yazma COMMIT'inden sonra `invalidateRuleCache()` önbelleği boşaltır; nesil sayacı sayesinde boşaltmadan önce başlamış bir okuma eski satırları
önbelleğe geri koyamaz. Çok süreçli dağıtımda diğer süreçler değişikliği en geç 30 sn içinde görür. `fresh: true` önbelleği atlar.
Bilinmeyen anahtar programlama hatasıdır (istisna).

## Veritabanı (migration `053_platform_rules.sql`)

`server/src/modules/platform_rules_schema.js` (`PLATFORM_RULES_DDL`) migration ile AYNI ifadeleri AYNI sırayla taşır (test: `platform_rules_schema`);
`db.js` yalnız `ensurePlatformRulesSchema(client)` çağırır (051'den sonra, `runPeopleBackfill`'den önce; katalog kontrolüyle yalnız eksik
nesneler, her biri kendi otomatik onaylı ifadesiyle; her şey varsa yalnız tek katalog sorgusu, kilit yok). Ekleyici ve idempotent; tohum satır yazılmaz.

- `platform_rule_values(id BIGSERIAL PK, rule_key TEXT NOT NULL, site_code BIGINT NULL, value JSONB NULL, inherit BOOLEAN NOT NULL DEFAULT FALSE,
  valid_from DATE NOT NULL, note TEXT NULL, created_by INTEGER NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`.
  CHECK: anahtar biçimi (`^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*)+$`, 3..80), `value` yalnız sayı / boolean ya da SQL NULL (JSON `null` reddedilir),
  `inherit => value IS NULL`, not 1..200, `valid_from` 2000-01-01..2200-12-31.
- FK: `site_code -> sites ON DELETE CASCADE`, `created_by -> users ON DELETE SET NULL` (tablo FK'sız oluşturulur, her FK ayrı katalog korumalı ifade).
- İndeksler: `(rule_key, site_code, valid_from, id)`, `(site_code) WHERE site_code IS NOT NULL`, `(created_by) WHERE created_by IS NOT NULL`.
- **Yalnız ekleme** (`trg_platform_rule_values_immutable`, işaret `prv:1`): UPDATE ve DELETE reddedilir; istisnalar yalnız FK eylemleri
  (site satırında üst site artık yoksa DELETE; `created_by` NULL'a iniyorsa ve kullanıcı artık yoksa UPDATE). TRUNCATE engellenir.
  Geçmiş günün kuralı geriye dönük değişmez (4b "tarihli model" ilkesi); yanlış değer yeni satırla düzeltilir.
- Hesap silme (kimliksizleştirme) satırlara dokunmaz: değiştiren adı JOIN ile "Silinmiş Kullanıcı" olur (FK politika tablosunda TOMBSTONE).

## Uçlar

Hata gövdesi `{ error, code }` (Türkçe); 5xx `{ error, errorId }` (iç ayrıntı yok). Tüm yanıtlar `Cache-Control: no-store`.
Rotalar `platform_rules_routes.js`, `platform_config_routes.js`'teki `platformServicesRouter`'a bağlanır (server.js değişmedi).
Hız sınırı: okuma kullanıcı başına 600/saat (+ IP 20000), yazma 60/saat (+ IP 300).

- `GET /admin/rules[?site_code=]` — yalnız süper kullanıcı. Biçimsiz `site_code` 400 `INVALID_QUERY`, olmayan site 404 `SITE_NOT_FOUND`.
- `GET /manager/sites/:siteCode/rules` — site yöneticisi kendi sitesi (`requireSiteManager` + `hasSiteManagementAccess`; başka site 403
  `FORBIDDEN_SITE`), süper kullanıcı her site; salt okunur (`can_edit: false`), değiştirenin adı DÖNMEZ.
- `PUT /admin/rules` — yalnız süper kullanıcı.

Liste gövdesi:

```json
{ "on_date": "2026-10-21", "site": { "site_code": 1000000001, "site_name": "Gül Sitesi" } | null, "can_edit": true,
  "groups": [ { "code": "finance", "label": "Finans" }, … ],
  "items": [ { "key", "group", "label", "description", "type": "int|bool", "unit": "bp|pct|days|null", "nullable", "min", "max", "default",
               "site_overridable", "schedulable", "editable", "locked_reason", "pair": { "key", "sum" } | null, "legal_note",
               "platform": { "value", "source": "platform|default", "valid_from", "note", "updated_at", "updated_by_name" },
               "site": { "value", "valid_from", "note", "updated_at", "updated_by_name" } | null,
               "effective": { "value", "source": "site|platform|default", "valid_from" },
               "scheduled": [ { "scope": "platform|site", "value", "inherit", "valid_from", "note" } ] } ] }
```

Yazma gövdesi ve kuralları:

```json
{ "site_code": null | 1000000001, "valid_from": "2026-11-01", "note": "Kurul kararı",
  "changes": [ { "key": "heat.measured_share_pct", "value": 60 }, { "key": "heat.area_share_pct", "value": 40 },
               { "key": "forecast.default_increase_bp", "inherit": true } ] }
```

- `valid_from` yoksa bugün (İstanbul); bugünden eski olamaz, en çok 5 yıl ileri (400 `INVALID_BODY`). Not projedeki serbest metin kuralıyla
  temizlenir (`finance_common.normalizeFreeText`: NFC, tek satır, görünmez ve yön denetim karakterleri atılır), en çok 200 karakter (kod noktası).
  1..20 değişiklik; bilinmeyen kök alan / biçimsiz değişiklik 400 `INVALID_BODY`.
- Kural hataları TEK yanıtta: 400 `VALIDATION_FAILED` + `fields` (anahtar -> Türkçe metin) + `rule_codes` (anahtar -> kod):
  `RULE_UNKNOWN`, `RULE_DUPLICATE`, `RULE_VALUE_INVALID` (tür, sınır, izin verilmeyen null), `RULE_LOCKED`, `RULE_NOT_SITE_OVERRIDABLE`,
  `RULE_NOT_SCHEDULABLE`, `RULE_PAIR_MISMATCH` (ısı payı toplamı 100 değil; etkili tarihte ve sonraki planlı tarihlerde denetlenir).
- Site kapsamında site yoksa 404 `SITE_NOT_FOUND`; silinmiş hesap 401 `ACCOUNT_DELETED`.
- Tek işlem: `pg_advisory_xact_lock` (sınıf "PRUL") -> işlemi yapan `users` KEY SHARE -> (site kapsamı) `sites` KEY SHARE -> satırlar -> INSERT
  -> audit -> COMMIT -> önbellek boşalır. Eşzamanlı yazmalar sıraya girer (no-op ve çift denetimi yarışmaz).
- **No-op:** kapsamın `valid_from` tarihindeki değeriyle aynı değişiklik yazılmaz (satır ve audit yok); `changed` yalnız yazılan anahtarlardır.
- **Audit (katı):** her yazılan satır için `platform_rule.updated` (`target_type: 'platform_rule'`, `target_id: <anahtar>`, `site_code` site kapsamında);
  `details: { scope: 'platform'|'site', valid_from, from, to, inherit }` (yalnız sayı / boolean; not metni YAZILMAZ). Denetim satırı yazılamazsa
  değişiklik geri alınır.
- Yanıt: güncel görünüm (aynı kapsam, adlar dahil) + `changed`.

## Gecikme tazminatı üst sınırı

`finance_settings.js`: etkin üst sınır `lateFeeMaxRateBp = min(getRule('finance.late_fee.monthly_bp_max', bugün), LATE_FEE_MAX_MONTHLY_BP = 500)`.
Kural kendi sınırına (0..500) zaten kırpılır; yasal sınır (KMK m.20, aylık %5) kodda ikinci kez ve DB CHECK'inde (`late_fee_rate_bp BETWEEN 0 AND 500`)
korunur. Bu, `docs/PLATFORM_FINANS_4B.md` "Hukuki dayanak"taki sabit üst sınır cümlesinin yerine geçer (sabit artık yalnız yasal tavandır).

- `PUT …/finance/settings`: gönderilen `late_fee.rate_bp` etkin üst sınırın üstündeyse 400 `INVALID_BODY` ("0 ile X arasında"); 500 üstü zaten ayrıştırmada reddedilir.
- `GET …/finance/settings`: `late_fee.max_rate_bp` = etkin üst sınır; `late_fee.rate_bp` bu sınıra kırpılmış gösterilir.
- `loadEffectiveSettings`: tazminat AÇIKKEN oran üst sınıra kırpılır; önizleme, onay, çalıştırma `params` anlık görüntüsü ve `preview_hash`
  kırpılmış oranla yapılır (sınır önizleme ile onay arasında düşerse 409 `PREVIEW_STALE`). Tazminat KAPALIYKEN oran hiçbir hesaba girmediğinden
  kural okunmaz (ödeme ve hatırlatma yolunda ek sorgu yok).
- Sınır düşürülünce sitenin saklı oranı DEĞİŞMEZ (yöneticinin seçimidir); hesap sınırla yapılır, sınır yeniden yükselirse saklı oran geçerli olur.
- Üst sınır ileri tarihli planlanamaz (her zaman bugünden geçerli); hesap, dönemin değil hesaplandığı günün sınırını kullanır.

## Uygulama

- **Platform Ayarları** (yalnız süper kullanıcı): üstte "Kurallar" kartı -> "Kuralları Aç" -> `PlatformRulesScreen` (platform geneli; kurallar
  gruplu, her kartta değer, kaynak, sınır, varsayılan, geçerlilik tarihi, planlı değerler, son değiştiren ve not, mevzuat notu; kilitli kuralda
  neden). "Değiştir" -> `PlatformRuleDialog`: değer (baz puan yüzde metniyle "4,50"; sınır dışı kaydedilmez), süresiz anahtarı, ısı payında eşin değeri
  toplamdan hesaplanıp birlikte gönderilir, planlanabilen kuralda geçerlilik tarihi (GG.AA.YYYY, bugün..5 yıl), not; sunucu reddi pencerede gösterilir;
  kayıt sürerken geri tuşu pencereyi kapatmaz. Site görünümünde planlı platform değeri "(platform geneli)" ekiyle yazılır.
- **Modüller** (seçili site): altta "Kurallar" kartı. Site yöneticisi "Kuralları Görüntüle" ile salt okunur görür (yönetici ucu, değiştirenin adı yok).
  Süper kullanıcı "Kuralları Aç" ile site görünümünde yalnız sitede değişebilen kuralları değiştirir ("Platform değerini kullan" = siteye özel değeri kaldır);
  diğer kurallarda "Platform genelinden değiştirilir".
- "Platform Ayarları" menüsü bilerek yalnız süper kullanıcıda kaldı (mevcut sözleşme ve testler; menü İP-1D'de yeniden kuruluyor). Yöneticinin
  kuralları gördüğü yer kendi ayar ekranı olan "Modüller"dir.
- Denetim kaydı: "Kural değeri güncellendi"; hedef "Kural adı • Platform geneli" / "• Site"; eylem süzgecinde de var.

## Saklama süreleri (H2)

`retention.*` kuralları bugün YALNIZ VERİDİR: bu kurallara bağlı silme işi yoktur. `retention.enforce` kapalıdır ve KİLİTLİDİR (`editable: false`,
yazma 400 `RULE_LOCKED`): silme işi yazılmadı; avukat onayı ve silme işi geldiğinde kilit kaldırılır, iş `getRule` ile günün değerini okur.
Taslak ve dayanaklar: `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md` (İP-1E).

**Kurallardan bağımsız, bugün de çalışan silme (2026-10-21 inceleme notu):** bakım servisi (`server/src/services/maintenance_service.js`,
açılışta ve günde bir) kapı geçiş kayıtlarını (`door_access_logs`) ve cihaz bağlantı kayıtlarını 30 gün sonra siler. Bu yüzden
`retention.door_logs_days` (365, karar H2) bugün UYGULANMAZ; kural açıklaması ve otomatik silme açıklaması bunu ekranda söyler (test:
`platform_rules.test.js` bakım servisindeki gün sayısını okur). H2'deki 1 yıl ile bugünkü 30 gün arasındaki fark avukat sorusudur
(`docs/yasal/AVUKAT_KONTROL_LISTESI.md` geçiş kaydı maddesi 30 günü önerir); bakım silmesi bu İP'de değiştirilmedi (kapı tarafı).

## Bilinen sınırlar ve kararlar

1. Kural değeri tarihli ve yalnız eklenir; gelecekte planlanmış bir değeri iptal etmek için aynı tarihe yeni değer yazılır (ayrı "iptal" ucu yok).
2. Isı payı kuralları şimdilik yalnız platform genelidir (çift toplamının site bazında tutarlılığı için); siteye özel ısı payı sayaç modülünde (İP-4B) ele alınacak.
3. Gecikme tazminatı kapalıyken önizleme saklı oranla hesaplanır (kayıt yapılamaz; açılınca kırpılır).
4. Çok süreçli dağıtımda önbellek gecikmesi en çok 30 sn.

## Doğrulama

- Birim: `server/test/platform_rules.test.js` (kayıt defteri, çözüm sırası, kırpma, doğrulama, önbellek), `platform_rules_schema.test.js`,
  `platform_rules_service.test.js`, `platform_rules_routes.test.js`, `finance_late_fee_rule_limit.test.js`; istemci `test/platform_rules_models_test.dart`,
  `test/platform_rules_api_test.dart`, `test/screens/platform_rules_view_test.dart`, `test/screens/platform_rules_entry_test.dart`.
- Gerçek PostgreSQL: `QA_ONLY=chain,live,platform_rules node scripts/qa_platform_pg.mjs` (`scripts/qa_platform_rules_section.mjs`: şema, yalnız ekleme
  ve FK istisnaları, çözüm sırası + kırpma, önbellek, yetki matrisi + IDOR, doğrulama, no-op, audit, eşzamanlı yazma 40P01 = 0, gecikme üst sınırı).
