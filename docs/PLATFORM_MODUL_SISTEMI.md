# Platform modül sistemi — Faz 1 sözleşmesi (F0 + F1)

Site ve toplu yaşam yönetim platformunun çekirdeği: site başına **seçmeli modüller**, **yönetim türü**, **denetim kaydı** ve isteğe bağlı **ek roller**.
Sunucu ve Flutter uygulaması bu belgeye göre yazılır. Deneme listesi: `tools/deneme_listesi/platform.json` (claude.ai sayfası). Kurallar: `AGENTS.md`
(özellikle 2 geriye dönük uyum, 6 taşma yok, 7 canlı yenileme).

## Temel kararlar

1. **Geriye dönük uyum:** Modül satırı olmayan site, katalogdaki varsayılana göre davranır. `door_control` varsayılanı AÇIK; bu yüzden mevcut siteler, mevcut
   uygulamalar ve cihazlar hiçbir değişiklik görmez. Yeni modüller varsayılan KAPALI/"yakında".
2. **Yönetim türü:** `sites.management_type` (varsayılan `apartment_site`). Bu fazda yalnız `apartment_site` seçilebilir; diğer dördü reddedilir ("Yakında…").
3. **Çekirdek modüller** (`people`, `announcements`) her sitede hep açıktır ama ekranları Faz 2/3'te gelir; o zamana kadar `status: coming_soon`.
4. **Denetim kaydı** (`audit_log`) yalnız eklenir; API'de güncelleme/silme yoktur, bakım servisi temizlemez.
5. **Ek roller:** `BOARD_MEMBER` (Yönetim Kurulu / Denetçi) ve `STAFF` (Görevli), `site_memberships.role` değerleridir. Kullanıcının genel rolü (`users.role`) DEĞİŞMEZ.
   Site yöneticisi isterse atar; atamazsa bu rollerin işi site yöneticisinde kalır. `requireSiteManager`/`hasSiteManagementAccess` bu rolleri YÖNETİCİ saymaz.
6. **Doğrudan canlı:** ayrı test ortamı yok. Her şema değişikliği ekleyicidir (var olan veriye dokunmaz) ve `ensureDbSchema` ile `migrations/029_*.sql` aynı DDL'dir.

## Modül kataloğu (sunucuda sabit, `server/src/modules/catalog.js`)

| code | Ad | core | status | Varsayılan (satır yoksa) |
|---|---|---|---|---|
| `door_control` | Geçiş Kontrol (AHBU) | hayır | `available` | AÇIK |
| `people` | Kişi ve Daire Kayıtları | evet | `coming_soon` | — |
| `announcements` | Duyuru ve Bildirim | evet | `coming_soon` | — |
| `finance` | Aidat ve Finans | hayır | `coming_soon` | KAPALI |
| `reservation` | Rezervasyon ve Konsiyerj | hayır | `coming_soon` | KAPALI |
| `work_tracking` | İş Takibi | hayır | `coming_soon` | KAPALI |
| `metering` | Sayaç Okuma ve Faturalandırma | hayır | `coming_soon` | KAPALI |
| `online_payment` | Online Tahsilat ve Banka Bağlantısı | hayır | `coming_soon` | KAPALI |

Açıklamalar (Türkçe, kısa) katalogda tutulur. `toggleable = !core && status === 'available'`.
`enabled` hesabı: `status !== 'available'` → `false`; `core` → `true`; aksi halde `site_modules` satırı varsa `enabled`, yoksa varsayılan.

## Veritabanı (migrations/029_platform_modules.sql + db.js'te aynı DDL)

- `sites.management_type TEXT NOT NULL DEFAULT 'apartment_site'` + CHECK (`apartment_site`, `residence`, `business_center`, `cooperative`, `shopping_mall`).
- `site_modules(site_code BIGINT REFERENCES sites(site_code) ON DELETE CASCADE, module_code TEXT, enabled BOOLEAN NOT NULL, updated_by INTEGER NULL REFERENCES users(user_code) ON DELETE SET NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(site_code, module_code))`.
- `audit_log(id BIGSERIAL PK, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), actor_user_code INTEGER NULL REFERENCES users(user_code) ON DELETE SET NULL, actor_name TEXT, actor_role TEXT, action TEXT NOT NULL, site_code BIGINT NULL (FK YOK), target_type TEXT, target_id TEXT, details JSONB NOT NULL DEFAULT '{}')`; indeksler `(site_code, id DESC)`, `(id DESC)`.
- `site_memberships.role` CHECK genişler: `SITE_OWNER, SITE_ADMIN, RESIDENT, BOARD_MEMBER, STAFF` (users.role'daki DROP+ADD CONSTRAINT / DO bloğu örneği gibi).
- Eski sitelere satır yazılmaz (varsayılan yeter).

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
  "modules": [ { "code": "door_control", "name": "Geçiş Kontrol (AHBU)", "description": "…", "core": false, "status": "available",
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
`POST /admin/sites` ve `POST /membership/setup-site` gövdesine isteğe bağlı `management_type` (varsayılan `apartment_site`). `apartment_site` dışı → 400 `MANAGEMENT_TYPE_COMING_SOON` ("Bu yönetim türü yakında."); bilinmeyen değer → 400 `MANAGEMENT_TYPE_INVALID`. `mapSiteRow` çıktısına `management_type` ve `management_type_label` eklenir (etiketler: Apartman ve Site, Rezidans, İş Merkezi, Kooperatif, Alışveriş Merkezi). Türü sonradan değiştirme bu fazda yok.

### Kapı açma koruması (Geçiş Kontrol kapalıysa)
Hata: HTTP 403 `{ "error": "Geçiş Kontrol modülü kapalı.", "code": "MODULE_DISABLED", "module": "door_control" }`.
- Politika noktası: `evaluateDoorOpenPolicy` (door_access_policy.js) kanal ayrımından önce; `door` nesnesine `module_door_control` (boolean) eklenir (kapıyı getiren 3 SELECT + guest_passes_routes.js SELECT'i `LEFT JOIN site_modules` ile `COALESCE(sm.enabled, TRUE)`). Alan YOKSA (eski testler/çağrılar) politika "açık" sayar.
- Ek korunacak yerler: `POST /app/guest-passes` (satır içi kontrol), `GET /guest/:token` sayfası (kapalıysa kibar bilgi sayfası, kapı açma düğmesi yok), `qr-token` üretimi.
- MQTT `qr_verify` yolu aynı politikadan geçer: modül kapalıyken okuyucudan açma da reddedilir (red nedeni `module_disabled`).
- `GET /app/my-doors` modülü kapalı sitelerin kapılarını LİSTELEMEZ (yerel kontrol anahtarı da uygulamaya gitmez).
- ETKİLENMEYENLER: cihaz MQTT abonelikleri (availability/state/event/logs), `/health`, `/firmware/*`, `/api/company/*`, `local-open-notify` (cihazın yaptığı açmanın bildirimi), kapı günlüğü okuma uçları.
- Bilinen sınır: yerel (LAN) açma cihaz üzerinde yapıldığından, modül kapatılırken anahtar döndürülür (yukarıya bakın); cihaz o sırada çevrimdışıysa yeni anahtar cihaz bağlanınca gider ve ondan önce eski anahtar geçerli kalabilir. Yeni sürüm uygulama kapalı sitelerin kapılarını hiç göstermez.
- Süper kullanıcı kapı korumasından MUAF DEĞİLDİR (tutarlı deneme ve güvenlik için); uygulamada Panel'de seçili site için `getSiteModules` ile durumu öğrenir ve kapalıysa kapı kartları yerine bilgi kartı gösterir.

## Flutter

- **Modeller** (`lib/models/`): `PlatformModule`, `SiteModulesState`, `MySiteModules`/`MyModulesResult`, `AuditLogEntry`/`AuditLogPage`, `StaffRoleRecord`, `ManagementType` (5 değer, etiket, `selectable`). `SiteRecord`'a `managementType` + `managementTypeLabel` (alan yoksa `apartment_site`).
- **AuthApi/AuthService:** `getModuleCatalog`, `getMyModules`, `getSiteModules(siteCode)`, `setSiteModule(siteCode, code, enabled, {confirm})`, `listAuditLog({siteCode, limit, beforeId})`, `listStaffRoles(siteCode)`, `assignStaffRole(siteCode, email, role)`, `removeStaffRole(siteCode, userCode)`; `setupSite`/`createSite` `managementType` iletir.
- **Hata kodları → Türkçe mesaj** (`messageForErrorCode`, her biri <140 karakter, '_' içermez): `MODULE_DISABLED` "Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir." · `MODULE_COMING_SOON` "Bu modül yakında." · `MODULE_NOT_TOGGLEABLE` "Bu modül kapatılamaz." · `MODULE_NOT_FOUND` "Modül bulunamadı." · `MODULE_CONFIRM_REQUIRED` (sunucu metni kullanılır; uygulama onay penceresini önceden gösterir) · `MANAGEMENT_TYPE_COMING_SOON` "Bu yönetim türü yakında." · `MANAGEMENT_TYPE_INVALID` "Geçersiz yönetim türü." · `USER_NOT_FOUND` "Bu e-posta ile kayıtlı hesap yok." · `USER_NOT_ACTIVE` "Bu hesap henüz etkin değil." · `ALREADY_SITE_MANAGER` "Bu kişi zaten site yöneticisi." · `ROLE_INVALID` "Geçersiz rol." · `ROLE_NOT_FOUND` "Bu kişide kurul veya görevli rolü yok." (mevcut kodlarla çakışanlar yeniden kullanılır).
- **ModuleAccess** (ChangeNotifier, `lib/services/module_access.dart`): girişten sonra ve her genel yenilemede `getMyModules` çeker; `AdaptivePoller` ile kısa aralıklı tazelenir (arka planda durur). `isEnabled(siteCode, code)`, `anyEnabled(code)`, `sitesWith(code)`. Süper kullanıcıda her şey açık sayılır. Çağrı hatası durumunda mevcut değer korunur; ilk yükleme başarısızsa TÜM modüller açık sayılır (fail-open: ağ hatası yüzünden menüler kaybolmasın).
- **Menü:** `SirketMenuItem.moduller` ("Modüller": süper kullanıcı + site yöneticisi yönetici modunda), `SirketMenuItem.denetimKaydi` ("Denetim Kaydı": yalnız süper kullanıcı). `YanMenu`'ye gizlenecek öğe kümesi verilir; `_canAccessMenu` aynı süzgeci uygular. Süper olmayan kullanıcıda, bağlı OLDUĞU TÜM sitelerde `door_control` kapalıysa kapıyla ilgili öğeler (`kayitliCihazlar`, `bluetoothWifiKur`, `ellerSerbest`) gizlenir; `dashboard` kalır ve kapı kartları yerine "Geçiş Kontrol modülü kapalı" bilgi kartı gösterilir. Panel'deki site seçici yalnız modülü açık siteleri listeler.
- **Yönetim türü seçici:** `SetupSiteDialog` ve `SiteDialog`'da Site Adı ile İl arasında; "Apartman ve Site" seçili, diğer dördü `StatusChip` "Yakında…" ile devre dışı. Site kartında tür çipi.
- **Modüller ekranı:** site seçici (süper kullanıcıda tüm siteler, yönetici modunda yönetilen siteler), modül kartları (ad, açıklama, durum çipi: Açık / Kapalı / Yakında… / Her sitede açık, anahtar), `door_control` kapatırken önce `AppDialog` onayı (uyarı metni sunucudakiyle aynı), sonra `confirm: true`. Yenileme: çekip yenileme + yenile düğmesi, işlem sonrası otomatik yeniden çekme. "Ek roller" bölümü: liste, ekle (e-posta + rol), kaldır.
- **Denetim Kaydı ekranı:** liste (tarih, kim, ne, site), site süzgeci, "Daha fazla yükle", çekip yenileme.
- Taşma yok (320x640 ×2,0), iskelet/boş durum/hata durumu, tasarım sistemi bileşenleri (`lib/ui/design/`).

## Kabul ölçütleri (özet)

- Sunucu: `npm test` + `npm run lint` yeşil; yeni testler (katalog hesabı, uçlar ve yetki, onay zorunluluğu, audit yazımı, kapı koruması, `my-doors` süzgeci, site oluşturma türü, rol atama) mevcut hiçbir testi gevşetmeden.
- Uygulama: `flutter analyze` temiz, `flutter test` yeşil; yeni testler (modeller, servis, Modüller/Denetim/Ek roller görünümleri 320x640 ×2,0, çekmece öğe sayıları, kapalı modül görünümü).
