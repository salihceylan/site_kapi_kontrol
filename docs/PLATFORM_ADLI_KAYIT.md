# Daire sakini ADLİ KAYDI (migration 075)

Kullanıcı isteği: "Eski kiracı / yeni kiracı durumu var. Kiracı ayrılırsa LOG KAYDI KALMALI; adli bir durumda bilgi için, SADECE bunun için."

Bu belge kayıt tablosunu, olayları, erişim kuralını, saklamayı, dışa aktarımı ve KVKK notlarını anlatır. Hukuki görüş değildir; işaretli yerler
`[AVUKAT DOĞRULASIN]`.

## 1. Amaç ve sınır

- Sakin ayrılığı ve değişikliği olayları **değiştirilemez** bir kayda yazılır: kim, hangi daire, hangi dönem, hangi rolde, nasıl ayrıldı, işlemi kim yaptı.
- Kayıt **yalnız resmî talep halinde bilgi amaçlıdır**. Sakinlere gösterilmez; yeni kiracı eski kiracının hiçbir verisini göremez.
- Kapı açma, MQTT, BLE, firmware ve kapı servisleri mantığına dokunulmadı; yalnız mevcut merkezi işlevlere **yazma kancası** (aynı transaction'da tek `INSERT`) eklendi.
- "Borcum" kapsamı (taşınma tarihinden itibaren) değişmedi.

## 2. Tablo: `apartment_residency_log` (yalnız-ekleme)

DDL: `server/migrations/075_residency_log.sql` = `server/src/modules/residency_log_schema.js` (`ensureDbSchema` sonrası katalog korumalı `ensureResidencyLogSchema`).

| Sütun | Anlam |
| --- | --- |
| `site_code` | site (tek FK: `sites` ON DELETE CASCADE) |
| `apartment_id`, `apartment_label` | daire (FK'sız) ve o anki "Blok - No" görüntüsü |
| `event_type` | aşağıdaki 10 olay türü |
| `reason_code` | neden kodu (`moved_out`, `handover`, `mutual`, `site_manager`, `apartment_admin`, `self`, `consent`, `suspension`, `account_deleted`, `bulk_import`, `sync`, `manual_add`, `invite_accepted`, `role_change`, `admin_change`, `owner_record`) |
| `subject_name`, `subject_relation` | kişinin ad soyad anlık görüntüsü; ilişki: `owner` / `tenant` / `family_member` / `resident` |
| `subject_person_id`, `subject_user_code` | kişi ve kullanıcı kodu (**FK'sız sayı**: hesap silinse de kalır) |
| `period_start`, `period_end` | dairedeki dönem |
| `actor_user_code`, `actor_name`, `actor_role` | işlemi yapan; rol: `system`, `super_user`, `site_manager`, `apartment_admin`, `owner`, `tenant`, `resident` |
| `related` | olay bağı: yalnız sayısal kimlikler ve kısa kodlar (`residency_id`, `from_user_code`, `to_user_code`, `from_relation`, `to_relation`, `suspension_reason`, `auto`...) |
| `occurred_at` | zaman damgası |

- **İletişim bilgisi (telefon, e-posta, TCKN) ve serbest not sütunu YOKTUR** (KVKK veri azaltma). Kod alanları CHECK ile sınırlıdır.
- Tetikleyici `trg_apartment_residency_log_immutable`: UPDATE **hiç** yapılamaz; DELETE yalnız `sites` satırı artık yokken (site silme CASCADE); TRUNCATE engelli. Daire silinirse satır kalır.
- Kullanıcı satırı fiziksel silinirken (süper kullanıcı hesap silme, daire sıfırlama) `trg_users_log_residencies` güncel daire bağlarını `moved_out / account_deleted` olarak kaydeder; hata silmeyi engellemez.

## 3. Olaylar ve yazıldığı yerler

| Olay | Nereden |
| --- | --- |
| `moved_in` | `people_service.insertResidency` (kişi + daire, ilişki ekleme, malik kaydı, kiracı/aile ekleme, davet kabulü); eşitleme (`people_sync_sql` insert_residencies; erişim üyeliğinden doğan sakin, katılım onayı dahil); toplu yükleme |
| `moved_out` | `people_service.closeResidency` (site yöneticisi "Taşındı", kişiyi pasifleştirme, kiracı çıkışı = devir); eşitleme (destekleyen kayıt kalmadı / yetim kişi); hesap silme (`account_deletion_service`) |
| `role_changed` | `people_service.updateResidency` (ilişki türü); malik kaydı tamamlama; toplu yükleme yükseltmesi |
| `admin_changed` | `membership_service.applyApartmentPrimaryAdmin` (aile reisi değiştirme, site yöneticisi "Daire adminini değiştir", yönetim devri, davetle gelen kiracıya devir, kiracı her zaman daire admini kuralı: çalışma anı ve migration 081 / açılış toplu SQL'i `apartment_tenant_admin_sql.js` aynı alanları yazar, neden `handover`) |
| `handover` | `membership_service.handOverApartmentResident` (yönetici/gösterge başka kişiye geçti) |
| `link_cut_mutual` | karşılıklı bağ kesme onayı (`endTenancy`, neden `mutual`) |
| `member_removed` | `endResidenciesForMemberRemoval` ("Daireden çıkar", "Sakini sil"; CRM ilişkisi yoksa üyelik yine kaydedilir); üyenin onayladığı çıkarma; aile üyesini yönetici çıkarması; hesap silmede ilişkisiz üyelik |
| `member_left` | "Bu daireden ayrıl" (kiracı, aile üyesi, malik üyeliği) |
| `access_suspended` / `access_lifted` | `toggleApartmentMemberStatus` (geçici pasife alma / yeniden açma; güvenlik kararı askıya almada neden `suspension` + `suspension_reason`) |

Kural: kayıt, değişikliğin kendisiyle **aynı transaction'dadır**; yazılamazsa değişiklik de geri alınır (kayıtsız taşınma olmaz). Toplu yükleme yalnız ekleme ve
yükseltme yapar (kapatma yok). Hesap silmede ad, hesap kimliksizleştirilmeden **önce** okunan değerdir.

## 4. Erişim

- Liste: `GET /manager/sites/:siteCode/apartments/:apartmentId/residency-log?limit=&offset=` (yeniden eskiye). Yanıtta `items` (kayıt) ve yalnız ilk sayfada `legacy_items`:
  kayıt tablosuna yazılmamış kapalı dönemler `apartment_residencies` geçmişinden **türetilir** (salt okunur, `source: "legacy"`, etiket "Eski kayıt"; kayıtlı kapanışlar tekrarlanmaz).
  Geri doldurma (backfill) YAPILMAZ.
- Döküm: `GET|POST /manager/sites/:siteCode/residency-log/export` — `format=pdf|csv`, `reason_code=official_request|law_enforcement|court|other` ve `note` (5-200 karakter) **zorunlu**;
  isteğe bağlı `apartment_id`, `from`, `to`. İstemci notu URL'ye koymamak için POST kullanır. Üst sınır 5000 satır (kesilirse belgede yazar).
- **Yalnız site yöneticisi ve süper kullanıcı** (`resolvePeopleAccess write:true`). Kurul, görevli, daire admini, malik, kiracı, aile üyeleri, **yeni kiracı** ve başka sitenin yöneticisi 403.
- Döküm almak `audit_log`'a yazılır (`residency_log.exported`: kim, ne zaman, hangi daire, biçim, gerekçe kodu + not, satır sayısı). Audit yazılamazsa döküm **verilmez** (503).
  Listeyi açmak da `residency_log.viewed` ile izlenir. Hız sınırı: döküm kullanıcı başına 10/saat, IP başına 60/saat; liste 240/saat.
- Döküm ve yanıtlarda iletişim bilgisi yoktur.

## 5. Saklama ve KVKK

- Kural anahtarı `retention.residency_log_days` (varsayılan **3650 gün = 10 yıl**, 1825-7300, sitede değişmez). **Otomatik silme kapalı**; `retention.enforce` kilidi aynen (yazma 400 `RULE_LOCKED`).
  Kayıt tetikleyiciyle de silinemez; ileride otomatik silme açılırsa tetikleyiciye saklama istisnası eklenmesi gerekir (bilinen sınır).
- Hesap silme: kayıt **KVKK saklama istisnası** olarak kalır (kullanıcı kodu FK'sız sayı + ad anlık görüntüsü). `docs/PLATFORM_SATISA_HAZIRLIK.md` bölüm 1.6 ve
  `account_deletion_service.js` kaydı bozmaz/silmez.
- `[AVUKAT DOĞRULASIN]` dayanak: hukuki yükümlülük / hakkın tesisi, kullanılması veya korunması (KVKK m.5/2-ç, e), meşru menfaat (m.5/2-f), kira sözleşmesi alacaklarında TBK m.146-147 zamanaşımı,
  KVKK m.4/2-d ve m.7. Aydınlatma metninde **ayrıca** belirtilmelidir (taslak: `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md`). `server/legal/*.md` şablonlarına dokunulmadı.

## 6. İstemci

Site yöneticisinin Daire kartında (yalnız yönetici ve süper kullanıcı; kurul/görevli görmez) "Eski sakinler / Adli kayıt" bölümü: üstte "Bu kayıt yalnız resmî talep halinde bilgi
amaçlıdır; sakinlere gösterilmez." notu, zaman çizgisi (kim, rol, dönem, nasıl ayrıldı) ve "Adli bilgi dökümü al" (gerekçe seçimi + not, indirme). Menü değişmedi.
Yardım: site yöneticisi konusu "Eski sakin kayıtları" (sakin yardımına eklenmedi).

## 7. Bilinen sınırlar

- Geri doldurma yok: 075 öncesi ayrılıklar yalnız türetilmiş "Eski kayıt" satırı olarak görünür (ad, kişinin güncel adıdır; yapan ve neden bilinmez).
- Katılım onayı ile oluşan sakin kaydı eşitlemeyle yazılır (`sync`, işlemi yapan "Sistem"); onaylayan yönetici `audit_log`'dadır.
- Süper kullanıcının fiziksel hesap silmesinde (`DELETE FROM users`) yalnız o anda güncel ilişkisi olanlar kaydedilir; ilişkisiz üyelik kaydı yoktur.
- Otomatik saklama silmesi yok (tetikleyici engeller); dökümde ad = kayıt anındaki addır, sonradan değişen ad yansımaz.
- Gerçek PostgreSQL'de tetikleyici / CASCADE davranışı bu işte çalıştırılmadı (DB'siz testler SQL metnini doğrular; `scripts/qa_platform_pg.mjs` kapsamına alınabilir).
