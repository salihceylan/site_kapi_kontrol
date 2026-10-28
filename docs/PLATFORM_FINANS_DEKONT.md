# Dekont bildirimi ve geçici kabul (Dalga 2 / 2B)

Sakin ödemesini dekontla bildirir; kayıt **deftere yazılmaz**, "inceleniyor"dadır. Yönetici karşılaştırma ekranında onaylayınca tahsilat (ve makbuz) **dekont tarihiyle** oluşur, iptal ederse neden sakine gösterilir. Elden alınan para da aynı yoldan girer.

Bağımlılıklar: `finance` modülü açık + 2A ayarında `notices_enabled` açık (aksi 403 `PAYMENT_NOTICES_DISABLED`). Yeni modül yok. Migration `066` (`server/migrations/066_payment_notices.sql` = `payment_notice_schema.js`).

## Tablo: `payment_notices`
Durumlar: `uploading` -> `pending` -> `approved` | `rejected` | `withdrawn`. Tetikleyici yalnız bu geçişlere izin verir; karara bağlanmış satır değişmez (yalnız `resident_seen_at`). Onaylı satır `ledger_entry_id` (tekil, FK) ile korunur. Kaynak: `resident_app | resident_share | manager`. Hesap: `account_party owner|tenant`. Para tamsayı kuruş.

## Uçlar (sözleşme)
Sakin (kendi dairesi; aile üyesi ve başka site reddedilir):
- `POST /app/my-finance/payment-notices` `{apartment_id, amount_minor, paid_on, sender_name?, sender_iban?, description?, note?, origin?, file{name,size,content_type}, idempotency_key}` -> 201 `{notice, upload}`
- `PUT .../:id/content` ham gövde (`application/octet-stream`, `Content-Length` = bildirilen boyut) -> `pending`
- `GET ...?apartment_id=` -> `{items, pending_total_minor, unseen_count}`; `GET .../:id/file`; `POST .../:id/withdraw`; `POST .../seen`

Yönetici / süper (kurul ve görevli 403) `/manager/sites/:siteCode/finance/payment-notices`:
- `GET ?status=&apartment_id=&before_id=` -> `{items, has_more, counts}`; `GET /summary` -> `{attention:{code:'payment_notices', count, total_minor, oldest_at}}`; `GET /:id` (bildirim + daire kişileri + iki hesap bakiyesi + son tahsilatlar + uyarılar); `GET /:id/file`
- `POST` elden giriş (dosya isteğe bağlı; kayıt yine `pending`); `PUT /:id/content`
- `POST /:id/approve {account_id?, account_party?, book_in_open_period?, acknowledged[]}`, `POST /:id/link {ledger_entry_id}`, `POST /:id/reject {reason_code, note?}`
- `POST /bulk-approve | /bulk-reject {ids}` (en çok 50; her öğe ayrı işlem; yanıt `{results}`)

## Kurallar
- **Hesap (İşletme / Fon) seçimi (K3, 2026-10-28):** onay gövdesinde isteğe bağlı `fund` (`operating` | `capital`). Dairenin ilgili hesabında İKİ türün de açık borcu varsa `fund` ZORUNLUDUR (yoksa 400 `FUND_CHOICE_REQUIRED`; bildirim `pending` kalır, tahsilat yazılmaz); tek türde önerilen hesap seçili gönderilir; borçsuzda seçilmeyebilir. Toplu onayda iki türlü bildirim `FUND_CHOICE_REQUIRED` koduyla başarısız olur, tek tek incelenir. Ayrıntı: `PLATFORM_FINANS_KASALAR.md` §3.1.
- **Onay** tek işlemde `finance_parties.postPayment` (kaynak `payment_notice`, anahtar `pn:<id>`, tarih = dekont tarihi) + makbuz + denetim. Eşzamanlı/tekrar onay tek defter satırı üretir (`pn:<id>` idempotans + `FOR UPDATE`). Hesap (kasa/banka): gövdeden, yoksa havalede 2A `resident_account_id`; nakit/çekte etkin hesap varsa seçilmelidir (`ACCOUNT_REQUIRED`).
- **Ay kapalıysa** 409 `NOTICE_PERIOD_CLOSED`; `book_in_open_period` ile bugünün tarihine yazılır, dekont tarihi açıklamada kalır.
- **Uyarılar** (hesaplanır, onayda yeniden): `REFERENCE_OTHER_APARTMENT`, `SAME_FILE_OTHER_NOTICE`, `POSSIBLE_DUPLICATE` = *önemli* (her biri `acknowledged` ile işaretlenmeden 409 `NOTICE_WARNINGS_UNACKNOWLEDGED`; toplu onay bu öğeleri atlar); `NAME_MISMATCH`, `OVERPAYMENT`, `OLD_DATE` = bilgi. Çözüm: "Bağla" (mevcut tahsilata, yeni satır yazılmaz).
- Yönetici daireyi değiştiremez: yanlış daire `wrong_apartment` nedeniyle iptal, tahsilat elle girilir. Hesap (kiracı/ev sahibi) değişikliği serbest, denetime yazılır.
- Onayın geri alınması ayrı durum değildir: mevcut tahsilat iptali (ters kayıt).
- Sınırlar: sakin başına en çok 5 bekleyen, daire başına 30 günde 20 bildirim, dosya 10 MB (PDF/JPEG/PNG), site kotası `PAYMENT_NOTICES_SITE_QUOTA_MB` (varsayılan 2048). Ödeme tarihi gelecekte olamaz; sakin için en çok 1 yıl geri.

## Dosya
`<DOCUMENTS_DIR>/sites/<site>/<uuid>` (mali belge sınıfı, yedeğe kendiliğinden girer). `document_storage.js`'e `storeUpload` EKLENMEZ (gider belgesi dikişi kapalı kalır). **Bilinen anahtar kümesi** = `document_versions` ∪ `expense_documents` ∪ `payment_notices` (`document_integrity.js`; `documents_fsck.mjs` DB->disk denetimine dahil). Eksik olursa hazır dekontlar 24 saat sonra karantinaya alınırdı: testler korur. 2 saati aşan `uploading` satır + dosya bakım işinde silinir (`sweepStaleNoticeUploads`). Reddedilen/geri çekilen dosya Dalga 2'de silinmez (öneri: `retention.rejected_notice_files_days = 180`). İndirme HEP `inline` + `nosniff` + sandbox CSP; yönetici indirmesi denetim kaydı yazar. PDF'te etkin içerik (`/JavaScript`, `/Launch` ...) reddedilir (415 `NOTICE_PDF_ACTIVE_CONTENT`; en iyi çaba, ekran görüntüsü önerilir).

**Dağıtım notu:** nginx'te `PUT .../payment-notices/:id/content` yolları için `client_max_body_size 11m` konumu gerekir (`PLATFORM_IS_TAKIBI.md` kalıbı). Canlı ayar depoda olmadığından doğrulanmadı.

## İstemci
- Sakin: "Öde" sayfası > **Dekont yükle** (`PaymentNoticeDialog`; yalnız `notices_enabled` iken). Fotoğraf cihazda küçültülür, EXIF/GPS silinir. Borcum kartında `PaymentNoticeStatusLine`: "İnceleniyor: 1.250,00 ₺" ve tek seferlik karar notu.
- Yönetici: Finans > **Dekontlar** sekmesi (`PaymentNoticesView`; rozet = bekleyen sayı): çoklu seçim, "Seçilenleri onayla (5) - 6.250,00 ₺", karşılaştırma penceresi, "Elden giriş".
- Android Paylaş: ayrı `ShareReceiverActivity` (paketsiz; yalnız `content://`, kendi sağlayıcımız ve `file://` reddedilir, 10 MB; `cache/share_inbox`, 30 dk). `MainActivity`'ye yalnız kanal kaydı eklendi, `launchMode` değişmedi. `HomePage` açılış/öne gelişte `ShareInbox.take()` ile "Dekont bildir"i açar.
- **Yakında:** iOS paylaşım uzantısı (App Group + Team ID gerekir), telefon bildirimi (N8/5B), 2F ana sayfa "dikkat" kartı (sunucu satırı hazır: `paymentNoticeAttention`), hesap silme/dışa aktarma bölümü (2I), `getMyFinance` kalemine `pending_review_minor` (istemci kendi listesini çağırır).
