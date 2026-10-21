# Banka dosyası ile tahsilat (Dalga 2 / 2C)

Migration 067 (`server/migrations/067_bank_imports.sql`, `server/src/modules/bank_import_schema.js` ile aynı ifadeler; `db.js` ensure). Modül: `finance` (yeni modül yok). Yetki: yalnız yönetici/süper (kurul, görevli, sakin 403; başka site 403; modül kapalıysa `MODULE_DISABLED`).

## İlke
- Dosya (XLSX / CSV / MT940) **istemcide** ayrıştırılır (Karar C). Sunucuya yalnız satır JSON'u ve dosyanın adı, boyutu, sha256 değeri gelir; ham dosya saklanmaz. Gövde genel 1 MB sınırındadır, bir yüklemede **en çok 1500 satır** (5 MB kapısı bu işte yok; büyük dosya dönemlere bölünür).
- Para tamsayı kuruş. Tahsilat yalnız `finance_parties.postPayment` ile (`sourceKind 'bank_line'`, anahtar `bl:<satır>`, hesap = yüklemenin banka hesabı). Defter eklemelidir; geri alma ters kayıtladır.
- İstemci okuyucuları: `bank_statement_reader.dart` (zip -> `XlsxReader`, `:20:`+`:61:` -> `mt940_parser.dart`, kalan -> CSV), `bank_amount.dart` (metin -> kuruş, double yok).

## Tablolar
`bank_import_profiles` (hesap başına sütun eşlemesi + başlık imzası), `bank_imports` (dosya özeti, durum active/reverted, `(hesap, sha256)` aktifte tekil, `idempotency_key`), `bank_statement_lines` (durum unmatched/suggested/posted/linked/classified/ignored/reverted; `(hesap, fingerprint)` tekil), `bank_payer_ibans` (IBAN hafızası).

## Uçlar (`/manager/sites/:siteCode/finance/...`)
`GET|PUT accounts/:id/bank-profile`; `POST bank-imports/preview`; `POST bank-imports` (+ `expected_hash`, `idempotency_key`; durum değiştiyse 409 `BANK_PREVIEW_STALE`, aynı dosya 409 `FILE_ALREADY_IMPORTED`); `GET bank-imports`; `POST bank-imports/:id/revert`; `GET bank-lines?status=attention|done|...`; `GET bank-lines/summary`; `POST bank-lines/:id/assign|link|classify|unclassify`; `POST bank-lines/confirm` (toplu); `GET|DELETE bank-ibans`.

## Eşleme sırası (`bank_line_match.js`, saf)
0 yinelenen (parmak izi: hesap, valör, tutar, katlanmış açıklama, banka ref, dosyadaki eş satır sırası) -> atlanır; 1 referans kodu (2A `findRefs`, tekil) **güçlü**; 2 açıklamadaki daire kodu (tam sözcük, tekil) zayıf; 3 IBAN hafızası (tekil, taşınmayla bayatlamamış) **güçlü**; 4 gönderen adı (güncel kişilerle en az 2 belirteç, tekil) zayıf; 5 bekliyor.
Güçlüler yüklemede işlenir; zayıflar `suggested` olur (daire önseçili, onayla işlenir). Çoklu aday = eşleme yok. Daireye eşleşen satırda önce mevcut tahsilat aranır (aynı daire, hesap, tutar; valörden 5 gün önce - 2 gün sonra; ters kaydı ve başka satıra bağı yok): tek eşleşme varsa satır `linked` olur, ikinci tahsilat yazılmaz. Kapalı ay satırı `suggested` + `PERIOD_CLOSED` notuyla "kontrol edin"e düşer. Kayıt başına en çok 1000 otomatik işleme.

## Daire dışı satırlar
Çıkan para: Gider (`createExpense`), Banka masrafı (düzeltme `bank_fee`), Aktarım, Yok say. Giren para: Faiz (`bank_interest`), Diğer gelir (düzeltme `other`, açıklama zorunlu), Aktarım, Yok say. Anahtarlar `bl:<satır>:exp|adj|tr`. "Geri al": gider/aktarım iptal edilir, düzeltme ters işaretli yeni hareketle dengelenir.

## Geri alma
`POST bank-imports/:id/revert`: işlenmiş satırlar `reverseEntry` ile (makbuz iptali + hareket aynası) `blrev:<satır>` anahtarıyla geri alınır, bağlar çözülür, bu yüklemenin IBAN kayıtları silinir. Sınıflanmış satır varsa 409 `BANK_IMPORT_HAS_CLASSIFIED`. Her ters kayıt kendi finans işlemindedir (tek işlem DEĞİL); yarıda kalırsa aynı çağrı kaldığı yerden sürer.

## Dikkat sayacı
`bankLineAttention` (unmatched + suggested, aktif yüklemeler) `attention_registry` kaynağı `bank_lines` olarak kayıtlıdır; 2F toplu dikkat ucu bunu toplar. Ekranda Banka dosyası ekranının üstünde gösterilir.

## Bilinen sınırlar
Gerçek banka örnek dosyası yoktur: CSV/XLSX düzenleri ve MT940 `:86:` alt alanları doğrulanmadı (eşleme penceresi bu boşluğu karşılar). Foto/PDF ekstre, MT942 ve CAMT.053: Yakında. Satır/IBAN verisi üçüncü kişi verisidir; kurul göremez; IBAN hafızası listelenir ve silinir. Saklama süresi avukat onayına kadar uygulanmaz.
