# Platform modül sistemi — Faz 1 sözleşmesi (F0 + F1)

Site ve toplu yaşam yönetim platformunun çekirdeği: site başına **seçmeli modüller**, **yönetim türü**, **denetim kaydı** ve isteğe bağlı **ek roller**.
Sunucu ve Flutter uygulaması bu belgeye göre yazılır. Deneme listesi: `tools/deneme_listesi/platform.json` (claude.ai sayfası). Kurallar: `AGENTS.md`
(özellikle 2 geriye dönük uyum, 6 taşma yok, 7 canlı yenileme).

## Temel kararlar

1. **Geriye dönük uyum:** Modül satırı olmayan site, katalogdaki varsayılana göre davranır. `door_control` varsayılanı AÇIK; bu yüzden mevcut siteler, mevcut
   uygulamalar ve cihazlar hiçbir değişiklik görmez. Yeni modüller varsayılan KAPALI/"yakında".
2. **Yönetim türü:** `sites.management_type` (varsayılan `apartment_site`). Beş türün hepsi seçilebilir (311ed6d); türe göre arayüz terimleri ve önerilen modüller F9 bölümündedir.
3. **Çekirdek (temel) modüller** her sitede hep açıktır, talep edilmez, kapatılamaz (AGENTS.md Kural 25): `people`, `announcements`, `finance`, `survey`, `neighbor_board`, `equipment`, `annual_report`, `drive_storage`.
   `people` Faz 2a'dan, `announcements` Faz 3a'dan beri `status: available`. `finance` 2026-10-26'dan, diğer beşi 2026-10-28'den beri temeldir. Kart ödemesi artık ayrı modül değil, Aidat ve Finans'ın parçasıdır;
   Belgeler artık ayrı modül değil, Dosya Deposu'nun parçasıdır. `site_modules` satırı katalogdaki `core` bayrağından türetilir (`server/src/modules/core_modules.js`): yeni sitede kurulumla aynı işlemde açık yazılır,
   mevcut sitelere açılışta (`ensureDbSchema`) ve `migrations/079`, `082` ile doldurulur; bekleyen modül talepleri "onaylandı" olarak sonuçlanır. Katalog 23 modüldür (Kart Ödemesi ve Belgeler kataloktan çıktı:
   `migrations/083`, `084`; ayrıntı aşağıdaki iki not).
4. **Denetim kaydı** (`audit_log`) yalnız eklenir; API'de güncelleme/silme yoktur, bakım servisi temizlemez.
5. **Ek roller:** `BOARD_MEMBER` (Yönetim Kurulu / Denetçi) ve `STAFF` (Görevli), `site_memberships.role` değerleridir. Kullanıcının genel rolü (`users.role`) DEĞİŞMEZ.
   Site yöneticisi isterse atar; atamazsa bu rollerin işi site yöneticisinde kalır. `requireSiteManager`/`hasSiteManagementAccess` bu rolleri YÖNETİCİ saymaz.
6. **Doğrudan canlı:** ayrı test ortamı yok. Her şema değişikliği ekleyicidir (var olan veriye dokunmaz) ve `ensureDbSchema` ile `migrations/029_*.sql` aynı DDL'dir.

## Modül kataloğu (sunucuda sabit, `server/src/modules/catalog.js`)

| code | Ad | core | status | Varsayılan (satır yoksa) |
|---|---|---|---|---|
| `door_control` | Geçiş Kontrol (SmartKeyPass) | hayır | `available` | KAPALI (2bf1bd4; cihaz kapıya bağlanınca açılır) |
| `people` | Kişi ve Daire Kayıtları | evet | `available` (Faz 2a) | — (hep açık) |
| `announcements` | Duyuru ve Bildirim | evet | `available` (Faz 3a) | — (hep açık) |
| `finance` | Aidat ve Finans | evet (2026-10-26, AGENTS.md Kural 25) | `available` (Faz 4a) | — (hep açık; kurulumda satırı yazılır, talep edilmez) |
| `survey` | Anket ve Oylama | evet (2026-10-28, Kural 25) | `available` | — (hep açık; kurulumda satırı yazılır, talep edilmez) |
| `neighbor_board` | Komşu Panosu | evet (2026-10-28, Kural 25) | `available` | — (hep açık) |
| `equipment` | Ekipman ve Bakım | evet (2026-10-28, Kural 25) | `available` | — (hep açık) |
| `annual_report` | Faaliyet Raporu | evet (2026-10-28, Kural 25) | `available` | — (hep açık) |
| `drive_storage` | Dosya Deposu (Belgeler + Google Drive) | evet (2026-10-28, Kural 25) | `available` (Faz 3b-A + D1; 084'te birleşti) | — (hep açık; Google Drive hesabı ayrıca bağlanır) |
| `reservation` | Rezervasyon ve Konsiyerj | hayır | `coming_soon` | KAPALI |
| `work_tracking` | İş Takibi | hayır | `available` (bkz. PLATFORM_IS_TAKIBI.md) | KAPALI |
| `metering` | Sayaç Okuma ve Faturalandırma | hayır | `coming_soon` | KAPALI |
| `online_payment` | Online Tahsilat ve Banka Bağlantısı | hayır | `coming_soon` | KAPALI |
| `contracts` | Firma ve Sözleşme Takibi | hayır | `available` (bkz. PLATFORM_SOZLESMELER.md) | KAPALI |
| `decision_book` | Karar Defteri | hayır | `available` | KAPALI |

Tam ve güncel liste `catalog.js` içindedir; bu tablo yalnız örnek satırları ve ilk sürüm durumlarını gösterir.

**Belgeler ayrı modül DEĞİLDİR (2026-10-28, migration 084).** Eski `documents` ("Belgeler (Dosya Deposu)") modülü katalogdan kaldırıldı; yönetmelik / tutanak / sözleşme
yükleme ve dağıtma (`docs/PLATFORM_BELGELER.md` Bölüm A) ile sitenin Google Drive bağlantısı (`docs/PLATFORM_DRIVE_DEPOLAMA.md`) TEK modülde, `drive_storage` ("Dosya Deposu"), toplandı.
- Belge uçlarının yolları DEĞİŞMEDİ (`/manager/sites/:siteCode/documents…`, `/app/documents…`); modül kapısı artık `drive_storage`. Dosya Deposu TEMEL modül olduğundan (Kural 25) kapı her sitede açıktır: `isModuleEnabled` katalogdan karar verir (`site_modules` satırı kapalı yazılsa da açık sayılır), sakin listesi/indirmesinin doğrudan SQL kapısı satır yoksa açık sayar (`COALESCE(..., TRUE)`); `MODULE_DISABLED` `{ module: 'drive_storage' }` yanıtı kod yolu olarak durur ama tetiklenmez.
- Belge verisi (tablolar `documents`, `document_versions`, `announcement_attachments` ve diskteki dosyalar) DEĞİŞMEDİ; migration 084 yalnız modül satırlarını ve bekleyen talepleri birleştirir (idempotent; `server/src/modules/documents_into_drive.js`, `ensureDbSchema` her açılışta uygular): Belgeler AÇIK olan sitede Dosya Deposu açılır, bekleyen `documents` talebi Dosya Deposu açıksa "onaylandı", değilse Dosya Deposu talebine çevrilir (o site için zaten bekleyen Dosya Deposu talebi varsa "iptal"). Eski `documents` site_modules satırları SİLİNMEZ: katalogda olmadıkları için `rowsByModuleCode` onları yok sayar, ama dağıtım sağlık denetimi başarısız olursa `deploy/remote_deploy.sh` yalnız KODU geri alır (veritabanını almaz) ve önceki sürüm Belgeler'in açık/kapalı bilgisini bu satırlardan okur. Sonuçlanmış eski talepler ve denetim kayıtları (`target_id = 'documents'`) olduğu gibi kalır.
- Eski uygulama sürümleri `documents` kodunu göndermeye devam edebilir: `PUT …/modules/documents` ve `POST …/module-requests { module_code: "documents" }` `catalog.js` `canonicalModuleCode` ile `drive_storage`'a çevrilir; Dosya Deposu temel modül olduğundan sonuç 400 `MODULE_NOT_TOGGLEABLE` olur (404/500 yok; satır, talep ya da denetim kaydı yazılmaz). `GET /app/modules/catalog`, `GET …/modules` ve `GET /app/my-modules` artık `documents` anahtarı taşımaz; eski uygulamada "Belgeler" menüsü, uygulama güncellenene kadar görünmez.
- Arayüz: tek menü öğesi "Dosya Deposu" (`SirketMenuItem.belgeler` iç adı korunur): üstte yükleme/dağıtım yapılan **Belgeler** listesi (yönetici/kurul) ya da sakinin **Belgelerim** listesi, yönetim görünümünün altında **Google Drive** bölümü (yazma yetkisi olanda; bağlantı henüz hazır değilse "Yakında…"). Daire sakini alt çubuğundaki sekme "Dosyalar" (dar ekran). Modüller ekranından ayrı Drive kartı kaldırıldı.

Açıklamalar (Türkçe, kısa) katalogda tutulur. `toggleable = !core && status === 'available'`.

**Kart Ödemesi ayrı modül değildir (2026-10-28):** eski `card_payments` modülü kataloktan KALDIRILDI; kart ödemesi (sağlayıcı arayüzü: iyzico, PayTR "Yakında…") Aidat ve Finans'ın (`finance`, temel modül) parçasıdır. Kart ödemesi uçlarının (`/manager/sites/:siteCode/card-payments[/:provider]`) kapısı `finance` modülüdür, yani her sitede açıktır; uç yolları ve veri tablosu (`payment_provider_settings`) DEĞİŞMEDİ. Uygulamada ayrı modül kartı ya da menü öğesi yoktur: Finans ekranındaki **Kart Ödemesi** düğmesi (yönetici düzenler, kurul salt okur) komisyon notu penceresini açar. Migration `083_card_payments_into_finance.sql` (aynı metin `card_payments_into_finance.js` `CARD_PAYMENTS_INTO_FINANCE_SQL`, açılışta `ensureDbSchema` de uygular; idempotent): bekleyen `card_payments` modül taleplerini "onaylandı" olarak sonuçlandırır (karar notu "Kart Ödemesi, Aidat ve Finans modülünün içine alındı; her sitede açık."); kart ödemesi AYARLARI, geçmiş talepler, `audit_log` kayıtları ve eski `card_payments` `site_modules` satırları KALIR (katalog satırları yok sayar; dağıtım otomatik geri alınırsa kod geri gelir, veritabanı gelmez ve önceki sürüm Kart Ödemesi'nin açık/kapalı bilgisini bu satırlardan okur). Geçmiş `card_payments` talepleri listelerde "Kart Ödemesi (Aidat ve Finans)" adıyla görünür (`catalog.js` `retiredModuleName`). Eski uygulama sürümü `card_payments` kodunu talep eder ya da açıp kapatmaya çalışırsa sunucu 404/500 değil, temel modüllerle aynı sözleşmeyle **400 `MODULE_NOT_TOGGLEABLE`** ve açıklayıcı metin döner (`catalog.js` `retiredModuleNotice`); katalogda ve `modules` haritalarında bu kod artık yoktur, eski uygulama kart ödemesi bölümünü göremez ama hata da almaz (uygulamayı güncelleyince Finans ekranından erişir).
`enabled` hesabı: `status !== 'available'` → `false`; `core` → `true`; aksi halde `site_modules` satırı varsa `enabled`, yoksa varsayılan.

## Veritabanı (migrations/029_platform_modules.sql + db.js'te aynı DDL)

- `sites.management_type TEXT NOT NULL DEFAULT 'apartment_site'` + CHECK (`apartment_site`, `residence`, `business_center`, `cooperative`, `shopping_mall`).
- `site_modules(site_code BIGINT REFERENCES sites(site_code) ON DELETE CASCADE, module_code TEXT, enabled BOOLEAN NOT NULL, updated_by INTEGER NULL REFERENCES users(user_code) ON DELETE SET NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(site_code, module_code))`.
- `audit_log(id BIGSERIAL PK, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), actor_user_code INTEGER NULL REFERENCES users(user_code) ON DELETE SET NULL, actor_name TEXT, actor_role TEXT, action TEXT NOT NULL, site_code BIGINT NULL (FK YOK), target_type TEXT, target_id TEXT, details JSONB NOT NULL DEFAULT '{}')`; indeksler `(site_code, id DESC)`, `(id DESC)`.
- `site_memberships.role` CHECK genişler: `SITE_OWNER, SITE_ADMIN, RESIDENT, BOARD_MEMBER, STAFF` (users.role'daki DROP+ADD CONSTRAINT / DO bloğu örneği gibi).
- Eski sitelere satır yazılmaz (varsayılan yeter); tek istisna temel modüllerdir: onların açık satırı `core_modules.js` ile kurulumda yazılır ve mevcut sitelere açılışta / `079`, `082` ile doldurulur.

## Sunucu uçları

Hata gövdesi her yerde mevcut biçimdedir: `{ "error": "<Türkçe mesaj>", "code": "<KOD>" }`.

### `GET /app/modules/catalog` (authRequired)
`{ "modules": [ { "code", "name", "description", "core", "status" } ] }`

### `GET /app/my-modules` (authRequired)
Kullanıcının bağlı olduğu siteler (yönetici: `site_manager_sites` + aktif SITE_OWNER/SITE_ADMIN; sakin: aktif `apartment_memberships`→`apartments.site_code`, eski `apartments.resident_user_code`, aktif `site_memberships` RESIDENT; kurul/görevli: BOARD_MEMBER/STAFF).
Yalnız `approval_status = 'approved'` siteler. Süper kullanıcı için `{ "scope": "all", "sites": [] }` (menüleri modüllerden etkilenmez).
```json
{ "scope": "sites",
  "sites": [ { "site_code": 1234567890, "site_name": "Gül Sitesi", "management_type": "apartment_site",
               "role": "manager|resident|board_member|staff",
               "modules": { "door_control": true, "finance": false, "...": false } } ] }
```
Aynı sitede birden çok bağ varsa en yetkili rol (`manager` > `board_member` > `staff` > `resident`).
`modules` tüm katalog kodlarını içerir (hesaplanmış `enabled`).
`door_access` (boolean, EKLEYİCİ alan): kullanıcının o sitede GERÇEK kapı erişim yolu var (yönetici, aktif daire/sakin üyeliği, kapı bazlı özel izin) → `true`; yalnız
`board_member`/`staff` bağı olanlar → `false`. Yalnız özel kapı izniyle (`door_access_overrides`) erişilen siteler de listeye girer. İstemci "Geçiş Kontrol her yerde kapalı"
kararını yalnız `door_access: true` siteler üzerinden verir; alan yoksa `true` sayılır (eski sunucu). Gerekçe: başka sitenin yöneticisi rızasız `STAFF` atayıp kendi sitesinde
modülü kapatarak bir kullanıcının uygulamasında kapı menülerini gizletemesin.

### `GET /manager/sites/:siteCode/modules` (requireSiteManager + hasSiteManagementAccess; süper kullanıcı geçer)
```json
{ "site_code": 1234567890, "site_name": "Gül Sitesi", "management_type": "apartment_site", "management_type_label": "Apartman ve Site",
  "modules": [ { "code": "door_control", "name": "Geçiş Kontrol (SmartKeyPass)", "description": "…", "core": false, "status": "available",
                 "enabled": true, "toggleable": true, "updated_at": "ISO|null", "updated_by": "Ad Soyad|null" } ] }
```
Yetkisiz: 403 `FORBIDDEN_SITE`; site yok: 404 `SITE_NOT_FOUND`.

### `PUT /manager/sites/:siteCode/modules/:moduleCode`
Gövde `{ "enabled": true|false, "confirm": true|false }`. Yanıt: GET ile aynı gövde. Kurallar:
- Bilinmeyen modül 404 `MODULE_NOT_FOUND`; `enabled` boolean değilse 400 `INVALID_BODY`.
- `core` modül 400 `MODULE_NOT_TOGGLEABLE`; `coming_soon` modül AÇILAMAZ 409 `MODULE_COMING_SOON` (kapatmak zaten kapalı: 200, değişiklik yok).
- `door_control` KAPATILIRKEN `confirm !== true` ise 409 `MODULE_CONFIRM_REQUIRED`, `error`: "Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?". Açarken onay gerekmez.
- Değişiklik varsa `site_modules` upsert + `audit_log` satırı: `module.enabled` / `module.disabled` (`target_type: 'module'`, `target_id: <code>`, `details: {"enabled": bool}`). Değişiklik yoksa audit yazılmaz.
- Süper kullanıcı da aynı uçla çalışır (hasSiteManagementAccess true).
- `door_control` KAPATILINCA (değişiklik olduysa, COMMIT'ten sonra) sitenin cihazlarının yerel kontrol anahtarları döndürülür (`rotateTokensForSite`); böylece uygulamalarda önbellekli
  eski anahtarla LAN'dan kapı açılamaz. Yeniden açılınca `/app/doors/:id/status` yeni anahtarı dağıtır. Kapalıyken `/status` yerel kontrol anahtarı vermez.
- Hız sınırı: kullanıcı başına ~60 istek/saat (her açma/kapama `audit_log` satırı ekler).

### `GET /admin/audit-log?site_code=&limit=50&before_id=` (yalnız süper kullanıcı)
```json
{ "items": [ { "id": 7, "created_at": "ISO", "actor_user_code": 1, "actor_name": "Ad", "actor_role": "super_user", "action": "module.disabled",
               "site_code": 1234567890, "site_name": "Gül Sitesi|null", "target_type": "module", "target_id": "door_control", "details": { "enabled": false } } ],
  "next_before_id": 7 }
```
`limit` 1–200 (varsayılan 50), `id DESC`; sonraki sayfa `before_id=<next_before_id>`; son sayfada `next_before_id: null`.
İsteğe bağlı `action` süzgeci (tam eşleşme: `module.enabled`, `module.disabled`, `staff_role.assigned`, `staff_role.removed`).

### Ek roller (requireSiteManager + hasSiteManagementAccess)
- `GET /manager/sites/:siteCode/staff-roles` → `{ "items": [ { "user_code", "full_name", "email", "role": "BOARD_MEMBER|STAFF", "created_at" } ] }` (yalnız aktif üyelikler).
- `PUT /manager/sites/:siteCode/staff-roles` gövde `{ "email": "…", "role": "BOARD_MEMBER|STAFF" }` → `{ "item": {…} }`. Hesap yoksa 404 `USER_NOT_FOUND` ("Bu e-posta ile kayıtlı hesap yok. Kişi kayıtları sonraki aşamada gelecek."); hesap pasif/onaysızsa 409 `USER_NOT_ACTIVE`; kişi zaten site yöneticisi/sahibiyse 409 `ALREADY_SITE_MANAGER`; rol geçersizse 400 `ROLE_INVALID`. Aynı kişiye ikinci rol: mevcut kurul/görevli rolü GÜNCELLENİR (tek satır, UNIQUE(site_code,user_code)); `RESIDENT` ise yükseltilir (kapı/daire yetkisi bozulmaz: apartment_memberships ayrı tablodur).
- `DELETE /manager/sites/:siteCode/staff-roles/:userCode` → `{ "ok": true }`; kurul/görevli satırı yoksa 404 `ROLE_NOT_FOUND`. Satır silinir (RESIDENT'a düşürülmez; kişi dairesindeki yetkileriyle kalır).
- Audit: `staff_role.assigned` / `staff_role.removed` (`target_type: 'user'`, `target_id: user_code`, `details: {"role": …}`).
- Hız sınırı: kullanıcı başına ~20 istek/saat (site yöneticisi davet akışıyla aynı düzey). Bilinen/kabul edilen risk: e-posta ile hesap var/yok ayrımı (404 `USER_NOT_FOUND`) bir site
  yöneticisine hesap numaralandırma imkânı verir; kişi kayıtları (Faz 2) ile hedef kişi site kayıtlarından seçilecek ve bu uç buna göre daraltılacaktır.
- Sakin/görevli/kurul üyesinin bu uçlardaki 403'ü mevcut `requireSiteManager` ara katmanından gelir ve `code` taşımaz; `FORBIDDEN_SITE` yalnız yönetici olup başka siteye ait kişilere döner.

### Site oluşturma
`POST /admin/sites` ve `POST /membership/setup-site` gövdesine isteğe bağlı `management_type` (varsayılan `apartment_site`). Beş tür de seçilebilir; `selectable: false` olan bir tür eklenirse o tür 400 `MANAGEMENT_TYPE_COMING_SOON` ("Bu yönetim türü yakında.") döndürür; bilinmeyen değer → 400 `MANAGEMENT_TYPE_INVALID`. `mapSiteRow` çıktısına `management_type` ve `management_type_label` eklenir (etiketler: Apartman ve Site, Rezidans, İş Merkezi, Kooperatif, Alışveriş Merkezi). Türü sonradan değiştirme bu fazda yok.

### Kapı açma koruması (Geçiş Kontrol kapalıysa)
Hata: HTTP 403 `{ "error": "Geçiş Kontrol modülü kapalı.", "code": "MODULE_DISABLED", "module": "door_control" }`.
- Politika noktası: `evaluateDoorOpenPolicy` (door_access_policy.js) kanal ayrımından önce; `door` nesnesine `module_door_control` (boolean) eklenir (kapıyı getiren 3 SELECT + guest_passes_routes.js SELECT'i `LEFT JOIN site_modules` ile `COALESCE(sm.enabled, TRUE)`). Alan YOKSA (eski testler/çağrılar) politika "açık" sayar.
- Ek korunacak yerler: `POST /app/guest-passes` (satır içi kontrol), `GET /guest/:token` sayfası (kapalıysa kibar bilgi sayfası, kapı açma düğmesi yok), `qr-token` üretimi.
- MQTT `qr_verify` yolu aynı politikadan geçer: modül kapalıyken okuyucudan açma da reddedilir (red nedeni `module_disabled`).
- `GET /app/my-doors` modülü kapalı sitelerin kapılarını LİSTELEMEZ (yerel kontrol anahtarı da uygulamaya gitmez).
- ETKİLENMEYENLER: cihaz MQTT abonelikleri (availability/state/event/logs), `/health`, `/firmware/*`, `/api/company/*`, `local-open-notify` (cihazın yaptığı açmanın bildirimi), kapı günlüğü okuma uçları.
- Bilinen sınır: yerel (LAN) açma cihaz üzerinde yapıldığından, modül kapatılırken anahtar döndürülür (yukarıya bakın); cihaz o sırada çevrimdışıysa yeni anahtar cihaz bağlanınca gider ve ondan önce eski anahtar geçerli kalabilir. Yeni sürüm uygulama kapalı sitelerin kapılarını hiç göstermez.
- Süper kullanıcı kapı korumasından MUAF DEĞİLDİR (tutarlı deneme ve güvenlik için); uygulamada Panel'de seçili site için `getSiteModules` ile durumu öğrenir ve kapalıysa kapı kartları yerine bilgi kartı gösterir.

### Cihaz ekleme kuralı (2026-10-21)
Sisteme cihazı (kutu QR / Seri No / UID ile sahiplenme) YALNIZ **süper kullanıcı** ya da **onaylı bir sitenin yöneticisi** ekleyebilir. Sakin, bireysel kullanıcı, kurul üyesi ve görevli ekleyemez. 2026-10-23 (2bf1bd4) güncellemesi: Geçiş Kontrol (`door_control`) yeni sitede varsayılan KAPALIDIR; cihaz kapıya bağlanınca modül otomatik açılır. Bu yüzden yönetici, modül kapalıyken de cihaz ekleyebilir. Tek istisna: süper kullanıcının modülü AÇIKÇA kapattığı (`site_modules.enabled = FALSE` satırı olan) sitede sunucu 403 verir.
- Sunucu: `POST /membership/claim-device` (`claimDevice`). Yetki, cihaz sorgusundan ÖNCE denetlenir (yetkisiz kullanıcıya cihazın varlığı/sahipliği sızmaz). Kural: kullanıcı onaylı bir sitenin yöneticisi (`site_manager_sites` ya da aktif `SITE_OWNER`/`SITE_ADMIN` üyeliği) VE o sitede `door_control` açıkça kapatılmamış (`site_modules` satırı yoksa izin verilir; katalog varsayılanı kapalı olsa da). Aksi 403 `{ "error": "Cihazı yalnız site yöneticisi, Geçiş Kontrol modülü açıkken ekleyebilir.", "code": "DEVICE_ADD_FORBIDDEN" }`. Süper kullanıcı mevcut davranışı korur. Sorgu: `SQL_MANAGED_SITE_WITH_DOOR_CONTROL` (membership_rules.js).
- Etkilenmeyenler: kapı açma, MQTT, BLE, firmware, kapı komutları, mevcut cihaz kayıtları ve sahiplikleri, süper kullanıcının `/admin/devices` kaydı, site başvurusu onayındaki cihaz bağlama (süper onayı), `company_qr_tool` yolları.
- Flutter: menü öğesi "Daireye Katıl" (eski "Daireye Katıl & Cihaz Ekle"); bu ekranda cihaz ekleme yok (yalnız daireye katılma ve site başvurusu). "Cihaz Ekle" girişleri (`Kayıtlı Cihazlar` ekranındaki "Yeni Cihaz Kaydet", bireysel ana ekrandaki düğmeler) tek kuralla (`canAddDevice`, lib/ui/helpers/device_add_gate.dart) süper kullanıcı ve site yöneticisinde görünür (modül durumuna bakılmaz); açıkça kapatılmış sitede sunucu 403 ile son kapıdır. Site başvurusunda cihaz isteğe bağlıdır: cihazı site kurulduktan sonra yönetici ekler.

## Flutter

- **Modeller** (`lib/models/`): `PlatformModule`, `SiteModulesState`, `MySiteModules`/`MyModulesResult`, `AuditLogEntry`/`AuditLogPage`, `StaffRoleRecord`, `ManagementType` (5 değer, etiket, `selectable`). `SiteRecord`'a `managementType` + `managementTypeLabel` (alan yoksa `apartment_site`).
- **AuthApi/AuthService:** `getModuleCatalog`, `getMyModules`, `getSiteModules(siteCode)`, `setSiteModule(siteCode, code, enabled, {confirm})`, `listAuditLog({siteCode, limit, beforeId})`, `listStaffRoles(siteCode)`, `assignStaffRole(siteCode, email, role)`, `removeStaffRole(siteCode, userCode)`; `setupSite`/`createSite` `managementType` iletir.
- **Hata kodları → Türkçe mesaj** (`messageForErrorCode`, her biri <140 karakter, '_' içermez): `MODULE_DISABLED` "Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir." · `MODULE_COMING_SOON` "Bu modül yakında." · `MODULE_NOT_TOGGLEABLE` "Bu modül kapatılamaz." · `MODULE_NOT_FOUND` "Modül bulunamadı." · `MODULE_CONFIRM_REQUIRED` (sunucu metni kullanılır; uygulama onay penceresini önceden gösterir) · `MANAGEMENT_TYPE_COMING_SOON` "Bu yönetim türü yakında." · `MANAGEMENT_TYPE_INVALID` "Geçersiz yönetim türü." · `USER_NOT_FOUND` "Bu e-posta ile kayıtlı hesap yok." · `USER_NOT_ACTIVE` "Bu hesap henüz etkin değil." · `ALREADY_SITE_MANAGER` "Bu kişi zaten site yöneticisi." · `ROLE_INVALID` "Geçersiz rol." · `ROLE_NOT_FOUND` "Bu kişide kurul veya görevli rolü yok." (mevcut kodlarla çakışanlar yeniden kullanılır).
- **ModuleAccess** (ChangeNotifier, `lib/services/module_access.dart`): girişten sonra ve her genel yenilemede `getMyModules` çeker; `AdaptivePoller` ile kısa aralıklı tazelenir (arka planda durur). `isEnabled(siteCode, code)`, `anyEnabled(code)`, `sitesWith(code)`. Süper kullanıcıda her şey açık sayılır. Çağrı hatası durumunda mevcut değer korunur; ilk yükleme başarısızsa TÜM modüller açık sayılır (fail-open: ağ hatası yüzünden menüler kaybolmasın).
- **Menü:** `SirketMenuItem.moduller` ("Modüller": süper kullanıcı + site yöneticisi yönetici modunda), `SirketMenuItem.denetimKaydi` ("Denetim Kaydı": yalnız süper kullanıcı). `YanMenu`'ye gizlenecek öğe kümesi verilir; `_canAccessMenu` aynı süzgeci uygular. Süper olmayan kullanıcıda, bağlı OLDUĞU TÜM sitelerde `door_control` kapalıysa kapıyla ilgili öğeler (`kayitliCihazlar`, `bluetoothWifiKur`, `ellerSerbest`) gizlenir; `dashboard` kalır ve kapı kartları yerine "Geçiş Kontrol modülü kapalı" bilgi kartı gösterilir. Panel'deki site seçici yalnız modülü açık siteleri listeler. Menünün başlıklara ve Ayarlar paneline dağılımı, çekmecedeki site seçici ve sakin alt çubuğu: aşağıda "Menü grupları ... (İP-1D)".

### Menü grupları, Ayarlar paneli, site seçici ve sakin alt çubuğu (İP-1D, 2026-10-21; karar G2 + G3)

Görünürlük kuralı DEĞİŞMEDİ ve tek yerdedir: `YanMenu.visibleItems` (rol listesi + `HomePage._extraMenuItems` - `_hiddenMenuItems`). Aynı liste
çekmeceye, Ayarlar paneline, Panel vitrinine ve sakin alt çubuğuna dağıtılır; kapalı / yetkisiz modülün öğesi bu dört yüzeyin hiçbirinde yoktur
(fail-closed) ve modül kapanınca öğe dördünden de kalkar (açık sayfa Panel'e düşer).

- **Grup eşlemesi** (`menuGroupOf`, `lib/ui/widgets/yan_menu.dart`; `switch` ifadesi eksik eşlemeyi derletmez): her `SirketMenuItem` tam bir yere gider.

| Grup (`SirketMenuGroup`) | Öğeler |
|---|---|
| Ana sayfa | Panel |
| Daireler | Site Yönetimi, Daire Sakinleri, Kişiler, Daireye Katıl |
| Borçlar | Finans, Borcum |
| Tahsilat | (bugün boş: dekont bildirimi, banka dosyası buraya gelecek) |
| Giderler | (bugün boş: gider analizi buraya gelecek) |
| İletişim | Duyurular, Talepler, Taleplerim, Anket ve Oylama, Anketler |
| Raporlar | (bugün boş: faaliyet raporu, icra dökümü buraya gelecek) |
| Site hizmetleri | Kapılar, Dosya Deposu, Rezervasyonlar, Rezervasyon, Ziyaretçi ve Kargo, Ziyaretçilerim, Sözleşmeler, Karar Defteri, Kararlar |
| Ayarlar (dişli; çekmece başlığı değil) | Profilim, Eller Serbest, Kullanıcı / Süper Kullanıcı / Site Yöneticileri Yönetimi, Modüller, Modül Talepleri, Site Başvuruları, cihaz ekranları, Bluetooth ile Wi-Fi Kur, Denetim Kaydı, Platform Ayarları, İstemci Hataları (+ eski iki talep ekranı) |

- **Çekmece**: yalnız görünür öğesi olan başlıklar, `SirketMenuGroup.drawerGroups` sırasıyla (`YanMenu.drawerSections`); grup içinde menü sırası
  korunur. Rozetler (bekleyen / okunmamış) çekmecede ve Ayarlar panelinde öğenin yanındadır.
- **Ayarlar paneli** (`YanMenuAyarlar`, `Scaffold.endDrawer`): AppBar'ın en sağındaki dişli açar; öğeler `YanMenu.settingsItems`. Paneldeki öğelerin
  rozet toplamı dişlide görünür (süper kullanıcının bekleyen modül talebi / site başvurusu sayıları dişlinin arkasında kaybolmaz). Panelde ayrıca
  "Masaüstüne Widget Ekle" eylemi (mobil, süper kullanıcı dışı).
- **Yeni ekran eklemek** = `SirketMenuItem` değeri + `menuGroupOf` eşlemesi + görünürlük kuralı (`_extraMenuItems` ve `_canAccessMenu`; modül
  kapalıyken ya da modül verisi yokken eklenmez). Yeni grup gerekmez; boş başlıklar öğesi gelince kendiliğinden görünür.
- **Site seçici** (çekmecenin en üstü): veriler `ModuleAccess.allSites`; yönetici görünümünde (süper kullanıcı hariç) iki ve daha çok sitede seçicidir.
  Seçim `ModuleAccess.setScopeSiteCode` ile kapsamı daraltır: `result` ve bütün sorgular (`isEnabled`, `anyEnabled`, `sitesWith`,
  `boardMemberSites`, `isDisabledEverywhere`) yalnız o siteyle çalışır; kapsam dışı site kapalı sayılır (menüler yalnız daralır). Kapsamdaki site
  sonraki `my-modules` yanıtında yoksa kapsam düşer; `clear` (çıkış), mod değişimi ve rol değişimi (`HomePage._onAuthChanged`) kapsamı sıfırlar;
  süper kullanıcıda kapsam yoktur. Sunucu
  sorguları değişmez (kapsam yalnız istemci süzgecidir; yetkiyi sunucu yine doğrular). Kendi site listesini sunucudan çeken ekranlar (Kişiler /
  Duyurular yönetimi, Modüller) kendi seçicisini korur; tüm ekranları kapsayan "etkin site" Y1 (yönetim firması) ile gelecektir.
- **Sakin alt çubuğu** (`residentTabsFor`, `lib/ui/helpers/resident_tabs.dart`): Özet (Panel) · Duyuru (Duyurular) · Arıza (Taleplerim) · Kapı
  (Kapılar) · Dosyalar (Dosya Deposu). Sekme yalnız öğesi görünürse çizilir; Kapı ayrıca kapı yetkisinin olumlu kanıtını ister (kapı listesi dolu ya da
  modül verisinde `door_access` site; Geçiş Kontrol kapalıysa yok). İki sekmeden azsa ve kısa pencerede (< 480 dp) çubuk yok. Yalnız sakin kitlesinde (`showcaseAudience ==
  resident`). Android widget'ı / kısayol isteği (`DoorPanelRequests`) soğuk açılışta modül verisinin ilk yüklemesini bekler; beklerken kullanıcı
  başka sayfaya geçerse (menü değişiminin tek kapısı `_requestMenuChange`) istek düşer; uygulanınca Kapı sekmesi seçilir.
- **Yönetim türü seçici:** `SetupSiteDialog` ve `SiteDialog`'da Site Adı ile İl arasında; beş tür de seçilebilir, her satırda türün açıklaması ve varsayılandan farklı terimlerin özeti (F9). Site kartında tür çipi.
- **Modüller ekranı:** site seçici (süper kullanıcıda tüm siteler, yönetici modunda yönetilen siteler), modül kartları (ad, açıklama, durum çipi: Açık / Kapalı / Yakında… / Her sitede açık, anahtar), `door_control` kapatırken önce `AppDialog` onayı (uyarı metni sunucudakiyle aynı), sonra `confirm: true`. Yenileme: çekip yenileme + yenile düğmesi, işlem sonrası otomatik yeniden çekme. "Ek roller" bölümü: liste, ekle (e-posta + rol), kaldır.
- **Denetim Kaydı ekranı:** liste (tarih, kim, ne, site), site süzgeci, "Daha fazla yükle", çekip yenileme.
- Taşma yok (320x640 ×2,0), iskelet/boş durum/hata durumu, tasarım sistemi bileşenleri (`lib/ui/design/`).

## Kabul ölçütleri (özet)

- Sunucu: `npm test` + `npm run lint` yeşil; yeni testler (katalog hesabı, uçlar ve yetki, onay zorunluluğu, audit yazımı, kapı koruması, `my-doors` süzgeci, site oluşturma türü, rol atama) mevcut hiçbir testi gevşetmeden.
- Uygulama: `flutter analyze` temiz, `flutter test` yeşil; yeni testler (modeller, servis, Modüller/Denetim/Ek roller görünümleri 320x640 ×2,0, çekmece öğe sayıları, kapalı modül görünümü).

## Faz 1.1 — Modül talebi ve ürün adı (2026-10-15, kullanıcı notu F0.06)

Karar: site yöneticisi modülü KENDİ açıp kapatmaz. Menüsünde yalnız kendisine TANIMLANAN (satın aldığı) modülleri görür; her yöneticinin Panel'i bu yüzden farklıdır.
Satın alma sistemi yapılana kadar yönetici modül TALEP EDER, talep süper kullanıcıya iletilir, süper kullanıcı onaylarsa modül siteye tanımlanır (satın alma gelince bu akış otomatikleşecek).

### Ürün adı
Platformun görünen adı **"Site ve Toplu Yaşam Yönetim Sistemi"**dir. **Kapı açma modülünün adı SmartKeyPass'tir (eski adı AHBU; 2026-10-16'da SmartKeyPass olarak değiştirildi). "AHBU" adı kullanıcıya görünen hiçbir metinde geçmez; yalnız protokol kimlikleri (`AHBU:DOOR:` karekod, `X-AHBU-Device-UID`, `/ahbu/status`, `_ahbu._tcp`, `@ahbu.local`, `AHBU_*` derleme bayrakları) aynen kalır.**
DEĞİŞİR (platform düzeyi): uygulama/web/pencere başlığı, giriş ekranı başlığı, Panel başlığı, e-posta konu/başlık/imzaları, parola sıfırlama sayfası başlıkları, "uygulamayı açın" gibi uygulama adı geçen metinler, daire giriş bilgileri PDF'i.
KALIR (kapı modülü): kapı kartı etiketleri ("SmartKeyPass AKILLI GEÇİŞ", "SmartKeyPass YEREL AĞ GEÇİŞ"), katalogdaki "Geçiş Kontrol (SmartKeyPass)", cihaz/BLE ad önekleri, `X-AHBU-Device-UID` başlığı, kapı günlüğü ve cihaz/firmware PDF raporları, firmware ve şirket aracı.

### Veritabanı (029'a EK, ayrı migration `030_module_requests.sql` + db.js'te aynı DDL)
`module_requests(id BIGSERIAL PK, site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE, module_code TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending' CHECK (pending|approved|rejected|cancelled), requested_by INTEGER NULL REFERENCES users(user_code) ON DELETE SET NULL, requested_by_name TEXT, note TEXT, decided_by INTEGER NULL REFERENCES users(user_code) ON DELETE SET NULL, decided_by_name TEXT, decision_note TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), decided_at TIMESTAMPTZ NULL)`; aynı (site, modül) için tek bekleyen talep: kısmi tekil indeks `WHERE status='pending'`; indeks `(status, id DESC)`.

### Uçlar (hata gövdesi `{error, code}`)
- **Değişen:** `PUT /manager/sites/:siteCode/modules/:moduleCode` YALNIZ süper kullanıcıya açıktır; site yöneticisi 403 `MODULE_ADMIN_ONLY` ("Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz."). `GET .../modules` yanıtına EKLEYİCİ alanlar: her modülde `can_toggle` (boolean: çağıran süper kullanıcı VE modül `toggleable` ise true) ve `request_status` (`"pending"|null`: o siteye ait bekleyen talep). `toggleable` bugünkü anlamıyla kalır (katalog özelliği). Eski istemciler `toggleable`'a baktığı için PUT'ta 403 mesajını görür.
- `POST /manager/sites/:siteCode/module-requests` gövde `{module_code, note?}` (note ≤ 500 karakter) → 201 `{request}`; yetki requireSiteManager + hasSiteManagementAccess; hız sınırı kullanıcı başına 200/saat (2026-10-22: 10/saat gerçek kullanımda yetmiyordu), IP başına 500/saat. Hatalar: 404 `MODULE_NOT_FOUND`; 400 `MODULE_NOT_TOGGLEABLE` (core); 409 `MODULE_COMING_SOON`; 409 `MODULE_ALREADY_ENABLED`; 409 `MODULE_REQUEST_PENDING` (aynı modül için bekleyen talep var); 400 `INVALID_BODY`.
- `GET /manager/sites/:siteCode/module-requests` → `{ "items": [ request ] }` (son 50, `id DESC`).
- `DELETE /manager/sites/:siteCode/module-requests/:id` → bekleyen talebi geri çeker (`cancelled`), `{request}`; başka sitenin talebi 404 `REQUEST_NOT_FOUND`; bekleyen değilse 409 `REQUEST_NOT_PENDING`.
- `GET /admin/module-requests?status=pending|approved|rejected|cancelled|all&limit=50&before_id=` (yalnız süper kullanıcı; varsayılan `pending`) → `{ "items": [ request ], "next_before_id": N|null, "pending_count": N }` (`pending_count` süzgeçten bağımsız toplam bekleyen sayısı).
- `PUT /admin/module-requests/:id` gövde `{decision: "approve"|"reject", note?}` → `{request}`. `approve`: aynı transaction'da `site_modules` upsert `enabled=true` (+ `module.enabled` audit satırı, `details: {"via":"request","request_id":N}`) ve talep `approved`; `reject`: talep `rejected`. Bekleyen değilse 409 `REQUEST_NOT_PENDING`; yok 404 `REQUEST_NOT_FOUND`; onay anında modül artık `coming_soon` ya da zaten açıksa 409 (`MODULE_COMING_SOON`/`MODULE_ALREADY_ENABLED`, talep bekleyen kalır). Süper kullanıcı e-posta/Panel dışında bildirim almaz (F3'te bildirim merkezi gelecek).
- `request` nesnesi: `{ id, site_code, site_name, module_code, module_name, status, note, requested_by_name, created_at, decided_by_name, decided_at, decision_note }`.
- Audit eylemleri: `module_request.created`, `module_request.approved`, `module_request.rejected`, `module_request.cancelled` (`target_type:'module_request'`, `target_id:<id>`, `details:{module_code, ...}`); `GET /admin/audit-log?action=` bu değerleri de süzer.
- Yeni talepte tüm AKTİF süper kullanıcılara e-posta (konu: "Site ve Toplu Yaşam Yönetim Sistemi - Yeni Modül Talebi"; site, modül, isteyen, not); gönderim hatası talebi bozmaz (fire-and-forget).

### Flutter
- **Modüller (site yöneticisi):** kartta anahtar YOKTUR. Durum çipleri: "Tanımlı" (açık), "Tanımlı değil" + "Modül Talep Et" düğmesi (not alanlı pencere → talep gider), "Talep gönderildi" + "Talebi Geri Çek", "Yakında…", "Her sitede açık". Çekmeceden "Modüller" yönetici menüsünde kalır. Süper kullanıcıda anahtarlar (mevcut) kalır.
- **Modül Talepleri (süper kullanıcı):** yeni çekmece öğesi, bekleyen sayısı rozetiyle; süzgeç (Bekleyen / Onaylanan / Reddedilen / Tümü); kart: site, modül, isteyen, not, tarih; "Onayla" ve "Reddet" (reddetmede isteğe bağlı gerekçe) — onay penceresi; işlem sonrası otomatik yenileme, çekip yenileme, "Daha fazla yükle". Rozet sayısı `pending_count` ile (ModuleAccess yoklamasıyla birlikte, yalnız süper kullanıcıda, arka planda durur).
- Hata kodu eşlemeleri (<140 karakter, '_' yok): `MODULE_ADMIN_ONLY` "Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz." · `MODULE_ALREADY_ENABLED` "Bu modül zaten açık." · `MODULE_REQUEST_PENDING` "Bu modül için bekleyen bir talebiniz var." · `REQUEST_NOT_FOUND` "Talep bulunamadı." · `REQUEST_NOT_PENDING` "Bu talep artık bekleyen durumda değil."

## Yönetim türü terimleri (F9) — 2026-10-19

Yeni tablo ve migration YOK. Türe göre veri modeli ve modüller AYNI kalır (blok/daire/sakin; API alan adları değişmez); yalnız kullanıcıya görünen kelimeler ve "bu tür için önerilen modüller" türe göre gelir. Kaynak: `server/src/modules/management_type_terms.js` (saf, DB'siz). Her tür için `terms {unit, unit_plural, resident, resident_plural, owner, fee, block, block_plural}` ve `recommended_modules[]`:

| Tür | unit / unit_plural | resident / resident_plural | owner | fee | block / block_plural | Önerilen modüller |
|---|---|---|---|---|---|---|
| `apartment_site` | Daire / Daireler | Sakin / Sakinler | Malik | Aidat | Blok / Bloklar | door_control, finance, drive_storage, announcements |
| `residence` | Daire / Daireler | Sakin / Sakinler | Malik | Aidat | Blok / Bloklar | reservation, visitor_log, work_tracking, door_control, finance |
| `business_center` | Ofis / Ofisler | Firma / Firmalar | Mal sahibi | Ortak gider | Kat / Katlar | work_tracking, visitor_log, finance, drive_storage |
| `cooperative` | Hisse / Hisseler | Üye / Üyeler | Üye | Üye aidatı | Blok / Bloklar | finance, drive_storage, announcements, survey |
| `shopping_mall` | Mağaza / Mağazalar | Kiracı firma / Kiracı firmalar | Mal sahibi | Ortak gider | Kat / Katlar | finance, work_tracking, visitor_log, drive_storage |

- Bilinmeyen/boş tür → `apartment_site` terimleri ve önerileri (varsayılan; `normalizeManagementType` ile aynı kural).
- Önerilen kodların hepsi artık katalogdadır (`survey`, `visitor_log` dahil); katalogda olmayan bir kod önerilirse OLDUĞU GİBİ döner ve istemci bilmediği kodu atlar. `GET /manager/sites/:siteCode/modules` `modules` dizisi yalnız katalogdaki modülleri (23) içerir; katalog dışı öneri modül listesine eklenmez.
- Her türün tek cümlelik Türkçe açıklaması `summary` (F9 deneme listesindeki tür açıklamaları; "Yakında" demez).

### Ekleyici alanlar (mevcut alanlar ve değerleri DEĞİŞMEZ; eski istemciler alanları yok sayar)
- `mapSiteRow` çıktısı (site nesnesi: `/admin/sites`, `/manager/sites`, site ayrıntısı vb.) → `management_terms`.
- `POST /membership/setup-site` yanıtındaki `site` → `management_terms`.
- `GET /app/my-modules` `sites[]` öğeleri → `management_terms`, `recommended_modules` (kod dizisi). K8 (2026-10-29): ayrıca `menu_layout` (ana menüde öne çıkan modüller; yetenek DEĞİL yerleşim, bkz. `docs/PLATFORM_MENU_KATMANI.md`).
- `GET /manager/sites/:siteCode/modules` → yanıta `management_terms`; her modül öğesine `recommended` (boolean: modül bu tür için önerilir mi).
- **Yeni uç** `GET /app/management-types` (authRequired; sabit tablo, veritabanı sorgulanmaz) → `{ "items": [ { "code", "label", "selectable", "terms", "recommended_modules", "summary" } ] }`; 5 tür `MANAGEMENT_TYPES` sırasıyla. Örnek öğe: `{ "code": "business_center", "label": "İş Merkezi", "selectable": true, "terms": { "unit": "Ofis", "unit_plural": "Ofisler", "resident": "Firma", "resident_plural": "Firmalar", "owner": "Mal sahibi", "fee": "Ortak gider", "block": "Kat", "block_plural": "Katlar" }, "recommended_modules": ["work_tracking", "visitor_log", "finance", "drive_storage"], "summary": "İş merkezi yönetimi: ..." }`.

### Flutter (ayrı iş, aynı sözleşme)
`lib/models/management_terms.dart` (JSON'dan parse; alan yoksa varsayılan Daire/Sakin/Malik/Aidat/Blok → eski sunucuyla çalışır), `SiteRecord` ve `MySiteModules`'e `managementTerms` (ekleyici), `AuthApi.getManagementTypes()`. Kullanım: Modüller ekranında "Bu tür için önerilir" çipi; `SetupSiteDialog`/`SiteDialog` tür seçicide `summary` ve kısa terim özeti ("Daire → Ofis, Sakin → Firma"); Kişiler ekranı Daireler sekmesi başlığı/boş durum metinleri `terms.unit` ile (yalnız metin; iş mantığı ve API alanları değişmez); site kartı tür çipinde terim özeti ipucu.

### Testler
`server/test/management_type_terms.test.js` (tablo, kopya/donmuş nesneler, bilinmeyen tür, katalog dışı kodlar, görünüm şekli); `platform_catalog.test.js` (mapSiteRow `management_terms`), `platform_module_routes.test.js` (her iki modül ucu + `/app/management-types`), `platform_site_create.test.js` (admin site yanıtında `management_terms`).

## Rehber modülü ve ek rollerin yeri (058)

Katalog: `directory` (Rehber), kullanılabilir, çekirdek değil, **varsayılan KAPALI**. Kadro yönetimi çekirdek `people` modülünde kalır (modülden bağımsız); `directory` yalnız sakine/kuruldaki kişiye açılan rehberi ve faydalı telefon yönetimini denetler. `GET /app/directory`: çağıranın bağı olduğu (aktif daire üyeliği ya da BOARD_MEMBER/STAFF üyeliği) ve `directory` açık siteler için yönetici adları, kurul, görevliler (yalnız `show_in_directory`; telefon yalnız elle girilen `public_phone`) ve faydalı telefonlar; kapalı modülde site listede yoktur. Yönetici ucu: `POST|PATCH|DELETE /manager/sites/:siteCode/directory/contacts[/:id]` (modül kapalıysa 403 `MODULE_DISABLED`). Sakin "Yöneticiyi ara" (dokun-ara, P2-23) rehbere bağlı DEĞİLDİR: `GET /app/manager-contact` çağıranın bağı olduğu (aynı kapsam) her site için `{ site_code, site_name, manager_name, manager_phone, is_self }` döner; telefon yöneticinin profilindeki numaradır (yalnız `+`, rakam, boşluk ve ( ) - . içeren 7-15 haneli değer; aksi null), site birden çok yöneticiye sahipse telefonu kayıtlı ilk yönetici (atanma sırasıyla) seçilir, çağıran o sitenin yöneticisiyse `is_self: true` ve numara döndürülmez; e-posta ve kullanıcı kodu hiç dönmez, `no-store`, modül kapısı yoktur (Rehber kapalı sitede de çalışır). Modüller ekranındaki "Ek Roller" bölümü bir yönlendirme kartına döndü; kadro Kişiler > Kadro sekmesinde, görev kişi kartındaki "Görev ver"dedir.
