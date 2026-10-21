# Finans: Ödeme bilgisi (Dalga 2 / 2A, migration 054)

Kapsam: F1 + G4. Sakin borç kartında ve Borcum'da "Öde"; IBAN, alıcı adı, site kısa kodu, daire kodu ve referans kodu.
Dekont yükleme (2B) ve banka dosyası eşleme (2C) bu çatıya dayanır. Kartla ödeme "Yakında…" (pasif) kalır.

## Tablolar (054; `src/modules/finance_payment_schema.js` = `migrations/054_finance_payment_info.sql`)
- `finance_payment_settings`: site başına tek satır. `resident_account_id` (sakinlere gösterilen banka hesabı), `notices_enabled` (2B dekont anahtarı, varsayılan KAPALI), `settings_version`.
- `finance_site_ref_prefixes`: site kısa kodu, 3 harf A-Z. PK = önek: geçmişi dahil sistemde TEKİL. Eski önek takma ad olarak (`is_current=false`) kalır, başka siteye verilmez. Site başına tek güncel (kısmi tekil indeks).
- `finance_apartment_ref_codes`: kalıcı daire kodu (`UNIQUE(site_code, code)`). Bir kez üretilir; blok adı değişse de aynı kalır, yönetici değiştiremez.
- `finance_account_bank_details`: IBAN + alıcı adı SÜRÜMLERİ, yalnız eklemeli (güncel = en büyük id). `finance_accounts`'a dokunulmaz. UPDATE yalnız `created_by` NULL'a iner, DELETE yalnız site silinince, TRUNCATE engelli.
- Şema `ensureFinancePaymentSchema` ile (db.js, 040 ve 053'ten sonra) katalog kontrollü uygulanır; normal açılışta DDL yok.

## Kodlar (saf modüller)
- `finance_iban.js`: TR IBAN (`TR` + 24 rakam, ISO 13616 mod-97), gruplu gösterim, maske `TR** … 1234`. Banka adı tablosu yok.
- `finance_payment_ref.js` (2B ve 2C kullanır): `parsePrefix`, `suggestPrefix`, `aptCode`, `formatRef`, `findRefs`, `foldRef`.
  - Biçim `GUL-A2-1026` = önek-daire-AAYY (İstanbul saati, bu ay). Kısa biçim `GUL-A2` düzenli ödeme talimatı içindir.
  - Daire kodu: tek blokta `D5`; çok blokta blok jetonu + no (`A Blok`/2 -> `A2`, `Gül`/5 -> `GUL5`); jeton rakamla bitiyorsa araya `D` (`B1D5`); numara bulunamazsa `K<id>`.
  - `findRefs(metin, {prefixes, codes})` -> `none | unique | ambiguous`. Önek kelime başında aranır, ayırıcılar atılır; kodu metin sonu, ayırıcı ya da geçerli AAYY izlemelidir (bitişik yazımda yalnız geçerli AAYY). Geçersiz ay dönemsiz sayılır. Birden çok farklı daire adayı = belirsiz; eşleme YAPILMAZ.

## Uçlar (`finance_payment_routes.js`)
| Uç | Yetki | Not |
|---|---|---|
| `GET /manager/sites/:siteCode/finance/payment-settings` | yönetici, süper, kurul | Kurul IBAN'ı maskeli görür. Yanıt: `prefix`, `aliases`, `suggested_prefix`, `resident_account`, `bank_accounts`, `notices_enabled`, `settings_version`, `sample_reference` |
| `PUT .../payment-settings` | yönetici, süper | `expected_settings_version` ayar satırı varken zorunlu (409 `SETTINGS_VERSION_CONFLICT`). Önek çakışması 409 `PREFIX_TAKEN` + `suggestions`. Hesap: aynı sitenin, IBAN'ı girilmiş, etkin `bank` hesabı |
| `PUT .../accounts/:id/bank-details` `{iban, payee_name}` | yönetici, süper | 201 yeni sürüm; aynı değer 200 (`replayed`). Geçersiz IBAN 400 `IBAN_INVALID`; kasa hesabı 400; başka site 404. Denetim `finance.payment.bank_details_changed` YALNIZ maskeli IBAN yazar |
| `GET .../payment-references?block_id=` | yönetici, süper, kurul | Eksik daire kodlarını üretir; kısa kod + bu ayın kodu |
| `GET /app/my-finance/payment-info` | sakin | TUTAR DÖNMEZ. Yalnız görebildiği daireler (`loadVisibleAccounts`; aile üyesi görmez) ve `finance` açık siteler. `configured=false` ayar yokken. `details_changed_at` yalnız son iki sürümün IBAN'ı farklıysa |

Hepsi `authRequired`, site rolü ve `finance` modülü denetimi (kapalıysa 403 `MODULE_DISABLED`); başka site 403.

## İstemci
- `pay_sheet.dart`: Öde sayfası. Tutar çağıranın /app/my-finance kartındaki bakiyedir (kartla aynı sayı). Alıcı, IBAN (boşluksuz kopyalanır) ve açıklama kodu satırları, her birinde 48 dp "Kopyala". IBAN son 14 günde değiştiyse amber uyarı. Ayar yoksa açıklama metni. "Kartla öde — Yakında…" pasif. "Dekont yükle" yalnız `onUploadReceipt` verilince (2B bağlar).
- Panel borç kartı: borç varken "Öde" (tek borçlu daire varsa Öde sayfası, birden çoksa Borcum). Borcum kartı: borç varken "Öde"; "Online ödeme yakında" notu kalktı.
- Yönetici: Kasa sekmesinde "Ödeme bilgisi" (`finance_payment_settings_dialog.dart`) ve banka hesabı altında "IBAN ve alıcı adı" (`finance_bank_details_dialog.dart`).

## Bilinen sınırlar ve riskler
- Ele geçirilmiş yönetici hesabı IBAN'ı değiştirirse sakinler yanlış hesaba öder: sürümlü kayıt, denetim, alıcı adı gösterimi ve 14 gün sakin uyarısı var; ek kimlik doğrulama yok.
- Sakin ucu eksik daire kodlarını üretir (yazma, kısa finans kilidi); yalnız kod eksikse çalışır.
- Blok adları serbest metin olduğundan kodlar okunaksız çıkabilir (`K<id>` yedeği); kod kalıcıdır.
- Kod listesinin Excel'e aktarımı bu işte YOK (uç hazır: `payment-references`).
- Dişli menüsüne "Ödeme bilgisi" öğesi eklenmedi (menü grupları ortak dosya); giriş Kasa sekmesindedir.
- Gerçek PostgreSQL denemesi (eşzamanlı önek, değişmezlik tetikleyicisi) kullanıcıda; Node testleri sahte veritabanıyla.
