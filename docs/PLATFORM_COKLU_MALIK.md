# Çoklu malik - sözleşme (migration 104)

Karşılaştırma güçlendirme programı, Dalga E, P1-12, karar **K7**: «tüm malikler kayıtlı + TEK hesap muhatabı».
Üst sözleşmeler: `docs/PLATFORM_KISILER.md` (kişi / daire kayıtları), `docs/PLATFORM_DAIRE_YONETIMI.md` (Dairem), `docs/PLATFORM_FINANS.md` (iki hesap).
Modül gerektirmez (çekirdek). Kapı açma kodu (kapı komutları, MQTT, BLE, firmware) DEĞİŞMEZ.

## Neden, ne

Eskiden bir dairede en çok BİR güncel malik tutuluyordu; hissedar / eş ikinci malik olarak girilemiyordu (toplu yüklemede `RELATION_TAKEN`, «aile yazın» önerisi). Artık:

- Bir dairede **birden çok güncel malik** kayıtlıdır (en çok 10).
- İçlerinden **TAM BİRİ hesap muhatabıdır**: borç, ekstre, makbuz, hatırlatma ve sakin «Borcum» görünümünün hitap ettiği tek malik. Veri: `apartment_residencies.is_account_holder`.
- **Borç / tahakkuk mantığı değişmez.** Dairenin `owner` ve `tenant` hesabı kişiye değil daireye bağlıdır (`ledger_entries.account_party`); muhatap yalnız «bu hesap kime hitap eder» bilgisidir. Muhatap değişince bakiyeler DEĞİŞMEZ.
- Dairede «borç muhatabı = Malik / Kiracı / İkisi» ayarı (`apartments.responsible_party`) **aynen kalır** (K17).
- Diğer malikler **malik yetkisi taşımaz** (kiracı ekleme, vekalet, kişi arama, bağ kesme onayı, imza hakkı yalnız muhatapta) ve **borç görmez** (sakin görünümü, hatırlatma alıcısı muhatapla sınırlı). Bu bilinçli bir veri-asgarileştirme kararıdır; ileride genişletilebilir.

## Veri modeli ve DB garantileri («muhatapsız daire oluşamaz»)

`migrations/104_apartment_multi_owner.sql` = `src/modules/apartment_owners_schema.js` adımları (aynı sıra; test eşitliği doğrular). Açılışta (`ensureDbSchema` -> `ensureApartmentOwnersSchema`) eksik nesne yoksa yalnız katalog okuması; varsa TEK transaction (`SHARE ROW EXCLUSIVE` kilidi altında).

| Garanti | Nasıl |
|---|---|
| Mevcut tek malik KAYIPSIZ muhatap | Yedekleme adımı: dairede güncel malik var ama muhatap yoksa EN ESKİ güncel malik muhatap olur (idempotent; bayrak dışında hiçbir sütuna, `updated_at` dahil, dokunmaz) |
| Dairede en çok BİR muhatap | `uq_apartment_residencies_owner` **AYNI ADLA** yeniden tanımlanır: `UNIQUE (apartment_id) WHERE is_current AND relation = 'owner' AND is_account_holder`. Ad korunur: eski sürüm açılışta `CREATE UNIQUE INDEX IF NOT EXISTS` ile aynı adı bulup atlar (geri alma güvenli) |
| Bayrak yalnız güncel malikte | `chk_apartment_residencies_holder` CHECK + BEFORE tetikleyici (malik olmayan satırda bayrağı kendisi kapatır) |
| İlk malik kendiliğinden muhatap | BEFORE tetikleyici; eski kod bayraktan haberdar değildir |
| Eski yollar TEK malikli kalır | İkinci güncel malik yalnız `SET LOCAL app.multi_owner = 'on'` ile eklenir (çoklu malik hizmeti). Aksi halde `23505` + `uq_apartment_residencies_owner` döner: `people_service` bunu AYNEN `409 RELATION_TAKEN`a çevirir (CRM «ilişki ekle / değiştir», davet, toplu yükleme davranışı değişmedi) |
| Muhatap ayrılırsa yerine malik geçer | AFTER tetikleyici: muhatap «Taşındı / silindi / ilişki türü değişti» ile ayrılırsa başka güncel malik varsa EN ESKİSİ muhatap olur (`audit_log`: Sistem, `apartment.account_holder_changed`, `auto: true`). Hesap silme tetikleyicisi, toplu yükleme, Taşındı bu sayede muhatapsız daire bırakmaz |
| Muhatapsız daire İŞLEM SONUNDA reddedilir | ERTELENMİŞ kısıt tetikleyicileri (ekleme / güncelleme / silme): «güncel maliki var ama muhatabı yok» -> `23514` (`chk_apartment_residencies_account_holder`) ile COMMIT geri alınır |
| Yarışlara karşı iyileştirme | Muhatapsız kalmış dairenin malik satırına her yazma onu muhatap yapar (bayrak elle değiştirilmiyorsa) |

## Sunucu uçları (`people_routes.js`; yetki: yazma = site yöneticisi / süper, okuma = + kurul; sakin / görevli 403 `FORBIDDEN_ROLE`, başka sitenin yöneticisi 403 `FORBIDDEN_SITE`, başka sitenin dairesi 404 `APARTMENT_NOT_FOUND`)

| Uç | Ne yapar |
|---|---|
| `GET /manager/sites/:siteCode/apartments/:apartmentId/owners` | `{ apartment_id, label, owners[], account_holder_residency_id, owner_limit }` (muhatap başta; `owners[]`: `residency_id, person_id, full_name, has_account, is_account_holder, move_in_date`; kullanıcı kodu / telefon / e-posta YOK) |
| `POST .../owners` | Malik ekler: `{ person_id }` (kayıtlı kişi) YA DA `{ person: { full_name, phone?, email? } }` (yeni kişi, HESAPSIZ CRM kaydı); `make_account_holder?`, `move_in_date?`. Bu dairede zaten sakin / aile üyesiyse ilişkisi malike ÇEVRİLİR (yeni satır açılmaz; küçük işaretliyse 409 `MINOR_CANNOT_OWN`); kiracıysa 409 `RESIDENCY_EXISTS`; zaten malikse 409 `ALREADY_OWNER`; aynı e-posta 409 `PERSON_EXISTS` + `person_id`; 11. malik 409 `OWNER_LIMIT`. Dairede hiç malik yoksa eklenen ilk malik muhatap olur. Hesabı olan ve sitede bağı bulunan kişiye daire erişimi `addResidency` ile aynı kuralla verilir |
| `PUT .../owners/account-holder` `{ residency_id }` | Muhatabı dairenin BAŞKA bir güncel malikine geçirir (iki ifade: eski bayrak kapanır, yeni açılır; ertelenmiş kısıt «tam bir muhatap»ı denetler). Zaten muhatapsa `changed: false`, denetim yok. Olmayan / başka dairenin / kiracı kaydı 404 `OWNER_NOT_FOUND`. Hesabı olan eski ve yeni muhataba uygulama içi bildirim (`apartment_notices`, işlemi yapana yazılmaz, ad içermez) |
| `POST .../owners/:residencyId/remove` `{ new_account_holder_residency_id?, move_out_date? }` | Maliki çıkarır («Taşındı» kurallarıyla: ilişki biter, hesabı varsa dairedeki erişimi kapanır, adli kayıt). TEK malik çıkarılamaz (409 `LAST_OWNER`: kişi kartından «Taşındı»). Çıkarılan muhatapsa yeni muhatap: tek kalan otomatik; birden çok kaldıysa `new_account_holder_residency_id` ZORUNLU (409 `ACCOUNT_HOLDER_REQUIRED` + `owners`); geçersiz seçim 409 `REPLACEMENT_INVALID`. Önce muhatap geçirilir, sonra ilişki kapanır (AFTER tetikleyicisi rastgele aday seçmesin) |

Mevcut uçlarda ek alanlar (hepsi OPSİYONEL; eski istemci yok sayar):

- `GET .../apartments`: her satırda `owner_count`; `owner` HER ZAMAN hesap muhatabıdır.
- `GET .../apartments/:id`: `owners[]` (muhatap başta), `owner_count`; `current_residents[]` malik satırında `is_account_holder`.
- `GET .../apartments/:id/household` (yalnız tam görünüm): malik satırında `is_account_holder` (kurulun ad + ilişki sözleşmesi DEĞİŞMEDİ).
- `GET /app/apartments/mine`: ortak malik için `my_role: 'co_owner'`, `is_owner: false`, tüm `can{}` false (eski istemci bilinmeyen rolü «Sakin» gösterir).
- Denetim (`audit_log`, `target_type: apartment`): `apartment.owner_added`, `apartment.owner_removed`, `apartment.account_holder_changed` (`details`: kayıt kimlikleri; ad / telefon / e-posta YOK). Adli kayıt (`apartment_residency_log`): `moved_in` + neden `co_owner_add`; `role_changed` + `account_holder_change`.

## Muhataba bakan yerler (davranış değişikliği YOK)

Tek malikli veride aşağıdakilerin hepsi eskisiyle **birebir** aynı sonucu verir (`scripts/qa_coklu_malik.mjs`, eski sürümün kodu yan yana çalıştırılarak kanıtlandı). Çoklu malikte:

| Yer | Kural |
|---|---|
| Sakin «Borcum» görünümü (`loadVisibleAccounts`), `resolvePersonParty` | YALNIZ muhatap ev sahibi hesabını görür; diğer malik hesap görmez |
| Borç hatırlatma alıcıları (`loadRecipientRows`) | YALNIZ muhatap |
| Bakiye listesi malik adı, makbuz ödeyen adı, rapor adları, dışa aktarma «Malik» sütunu, daire listesi sakin adı | Muhatap ilk (ad seçimi) |
| `resolveApartmentRoles` / `rolesOfUser` (Dairem), imza hakkı listesi, yönetici adayları, «Kişi arama» ön süzgeci | `owner` = muhatap; ortak malik `coOwners` |
| Duyuru, ziyaretçi / kargo, belge / karar görünürlüğü | Her malik (sakin gibi) - değişmedi |
| Tahakkuk, tahsilat, defter yazımı, gecikme tazminatı, sayaç faturalandırma | Kişiye değil daire + hesaba bağlı - muhatap bayrağına HİÇ bakmaz (test: finans dosyalarında bayrağı yalnız 5 okuma dosyası kullanır) |

## Bilinen sınırlar ve kararlar

- **Toplu yükleme** tek malikli kalır: dosyada ya da veride ikinci malik `RELATION_TAKEN`; ek malikler Daire kartı > «Malik ekle» ile girilir. İlişki sütununda «aile» önerisi kalkmaz ama gerekli değildir.
- **Dairem** (sakin ekranı) ortak malikleri listelemez ve ortak malik için özel ekran yoktur (`co_owner` rolü sade, yetkisiz); yalnız yönetici daire kartında yönetilir.
- Muhatap değişince eski muhatabın verdiği açık vekaletler **iptal edilmez** (eski muhatap hâlâ maliktir); muhatap malik olarak ÇIKARILIRSA «Taşındı» kuralıyla vekaletleri iptal olur.
- Ortak malikin «Borcum» göremeyişi ürün kararıdır (K7: tek hesap muhatabı). Genişletme (salt okunur görünüm) ayrı karar ister; KVKK ölçülülüğü için varsayılan kapalıdır.
- Geri alma: eski sürüm açılışta `uq_apartment_residencies_owner` adını bulup atlar; ANCAK çoklu malikli bir dairede eski sürümün «bir dairede tek malik» varsayımı (ör. listede ilk malikin gösterilmesi) bozulabilir. Geri almadan önce ek malikler `POST .../owners/:id/remove` ile çıkarılmalıdır.
- `apartment_tenant_admin_sql.js` içindeki `owner_person_id` (devir kaydındaki «devreden malik») çoklu malikte keyfî bir güncel malik olabilir (yalnız bilgi alanı; 081 migration metniyle aynı kalması için dokunulmadı).

## Arayüz (Flutter)

Daire kartı (`apartment_card_dialog.dart`): birden çok malik varsa «Malik (hesap muhatabı)» satırı, malik satırlarında **Hesap muhatabı** rozeti ve açıklama bandı; yazma yetkisiyle (kurul salt okur) satır başına **Muhatap yap** (onaylı) ve **Maliki çıkar**, kart altında **Malik ekle**. Pencereler: `apartment_owner_dialogs.dart` (`AddOwnerDialog`: kayıtlı kişi / yeni kişi + «Hesap muhatabı olsun»; `RemoveOwnerDialog`: muhatap çıkarılırken yeni muhatap seçimi). Eski sunucuda `owners` alanı yoksa liste güncel sakinlerden türetilir. Geçmiş ekranı üç yeni eylemi Türkçe başlıklarla gösterir.

## Doğrulama

- Gerçek PostgreSQL: `server/scripts/qa_coklu_malik.mjs` (`QA_PG_PORT`, `QA_OLD_SERVER_SRC`): `upgrade_migrate` / `upgrade_ensure` (001..084 canlı şema + tek malikli veri -> kayıpsız, borç ve hesap çıktıları eski kodla birebir, ikinci uygulama no-op, eski yol 23505 / `RELATION_TAKEN`), `invariants` (tetikleyici garantileri, eşzamanlı ilk malik, hesap silme tetikleyicisi, daire silme, toplu ekleme), `services` (ekle / çevir / muhatap değiştir / çıkar, yetki ve site kapsamı, denetim, adli kayıt, bildirim, finans muhatapla sınırlı, 6 eşzamanlı değişim).
- DB'siz: `server/test/apartment_owners_schema.test.js`, `apartment_owners_routes.test.js`, `apartment_owners_rules.test.js`; Flutter: `test/apartment_owners_models_test.dart`, `test/screens/apartment_owners_card_test.dart`.
