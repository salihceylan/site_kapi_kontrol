# Satışa Hazırlık Paketi — Ortak Sözleşme (2026-10-16)

Bu belge, paralel çalışan ajanların (sunucu, Flutter, operasyon, hukuk taslakları) **bağlayıcı** ortak sözleşmesidir.
Her ajan yalnızca kendi sahiplik listesindeki dosyalara yazar; API şekilleri burada sabittir, değiştirmek gerekirse
önce raporda gerekçeyle belirtilir (sessizce sapılmaz).

## 0. Ortak kurallar (TÜM kod ajanları)

1. Çalışma dizini `G:\site\site_kapi_kontrol`. **Aynı ağaçta başka ajanlar eşzamanlı çalışıyor.** Yalnızca sahip olduğunuz dosyaları değiştirin.
2. **Paylaşılan sıcak dosyalar** (yalnız küçük, sabitlenmiş `Edit` çağrılarıyla; düzenlemeden hemen önce yeniden `Read` edin; asla yeniden yazma/biçimlendirme/sıra değiştirme yapmayın):
   `server/src/db.js`, `server/src/server.js`, `server/src/modules/catalog.js`, `server/scripts/qa_platform_pg.mjs`,
   `server/src/routes/auth_routes.js`, `lib/ui/pages/home_page.dart`, `lib/ui/widgets/yan_menu.dart`, `lib/main.dart`,
   `lib/ui/views/profile_view.dart`, `pubspec.yaml` (bağımlılıklar zaten eklendi: `url_launcher`, `package_info_plus`; başka bağımlılık eklemeyin).
3. **Git yazma komutları YASAK**: `git add/commit/push/stash/checkout/reset/clean/rm/restore` çalıştırmayın. Commit'i koordinatör atar. `git status/diff/log/show` serbest.
4. Kendi oluşturmadığınız dosyayı silmeyin. `flutter clean` ve ağaç genelinde biçimlendirme (`dart format .`) YASAK; yalnızca kendi dosyalarınızı biçimlendirin.
5. Tüm süiti çalıştırmayın (`npm test`, `flutter test` parametresiz). Yalnızca kendi test dosyalarınızı çalıştırın: `node --test <dosya>` (server), `flutter test <dosya>`, `flutter analyze <dosyalar>`, `npx eslint <dosyalar>`. Başkasının yarım dosyası derlemeyi kırarsa **düzeltmeyin**, kendi dosyalarınızın analizini süzün ve raporlayın.
6. Gizli bilgileri (parola, JWT sırrı, SMTP parolası, `.env` değerleri, SSH parolası) **asla** yazdırmayın, kaydetmeyin, commit'lemeyin, sohbete/rapora koymayın. Kullanıcıya soru soramazsınız; standartlara göre gerekçeli karar verin ve raporda "Kararlar" başlığında belirtin.
7. Sunucu hata gövdesi: `{ "error": "<mesaj>", "code": "<MAKINE_KODU>" , ... }`; 5xx'te `{error, errorId}`. Mevcut stile uyun (`server/src/modules/errors.js`, `route_helpers.js`). Flutter metinleri düzgün Türkçe karakterlerle.
8. Şema yalnızca `ensureDbSchema()` (`server/src/db.js`) ile uygulanır; `server/migrations/0NN_*.sql` aynı **idempotent, eklemeli** DDL'i taşımalıdır. Numaralar: **035** = Platform hizmetleri (S-B), **036** = Hesap silme (S-A), **037** = Sertleştirme (S-C, gerekirse), 038 = Faz 2b, 039 = Faz 3b-A (Belgeler), 040 = Faz 4b, 041 = Faz 3b-B (push) (ayrılmış).
9. Kişisel veri: günlüklere (log) ve hata raporlarına e-posta, telefon, ad, token, parola yazılmaz.
10. Bitirince rapor: değiştirilen/eklenen dosya listesi, çalıştırılan testler ve gerçek sonuçları (geçti/kaldı sayıları), kararlar, açık kalanlar, başka ajandan beklenen bağımlılıklar. Başarısız/atlanan bir şeyi olduğu gibi söyleyin.

## 1. API sözleşmesi

### 1.1 Uygulama yapılandırması — `GET /public/app-config` (kimliksiz, önbelleksiz: `Cache-Control: no-store`)
```json
{
  "server_time": "2026-10-16T10:00:00.000Z",
  "min_supported_version": "1.0.0",
  "latest_version": "1.0.0",
  "update_url_android": null,
  "update_url_ios": null,
  "maintenance": { "active": false, "message": null },
  "support": { "email": null, "phone": null, "hours": null, "web_url": null },
  "legal_enforced": false
}
```
Sürüm karşılaştırması `major.minor.patch` sayısal (build numarası `+N` yok sayılır). Ayarlar `platform_settings` tablosunda (`app.*`, `support.*`, `legal.*` anahtarları).

### 1.2 Süper kullanıcı ayarları — `GET/PUT /admin/platform-config` (yalnız `super_user`; PUT kısmi güncelleme; denetim kaydı: yalnızca değişen anahtar adları, değerler yok)
```json
{
  "app":     { "min_supported_version": "", "latest_version": "", "update_url_android": "", "update_url_ios": "", "maintenance_active": false, "maintenance_message": "" },
  "support": { "email": "", "phone": "", "hours": "", "web_url": "" },
  "legal":   { "company_name": "", "company_address": "", "mersis_no": "", "kep_address": "", "contact_email": "", "contact_phone": "", "enforce_consents": false }
}
```
Boş dize = ayarsız. Doğrulama: sürümler `^\d+\.\d+\.\d+$`; URL'ler yalnız `https://`; e-posta biçimi; uzunluk sınırları.

### 1.3 İstemci hata raporu — `POST /public/client-errors` (kimliksiz; yanıt `202 {"ok":true}`)
```json
{ "install_id": "uuid-v4", "app_version": "1.0.0", "build": "1", "platform": "android|ios|web|other",
  "os_version": "14", "error_type": "FlutterError", "message": "…≤500", "stack": "…≤8000",
  "fatal": true, "occurred_at": "ISO", "route": "/home" }
```
Sunucu: boyut/alan sınırı, hız sınırı (IP başına 30/saat, install_id başına 10/saat), **kişisel veri temizleme** (e-posta, telefon, JWT/`Bearer`, uzun sayı dizileri maskelenir), parmak izine göre tekilleştirme (`count++`), 90 gün sonra silme. Süper kullanıcı: `GET /admin/client-errors?limit=&cursor=` → `{items:[{fingerprint,error_type,message,app_version,platform,fatal,count,first_seen,last_seen,sample_stack}],next_cursor}`.

### 1.4 Yasal belgeler
Kaynak: `server/legal/*.md` (sahibi **hukuk ajanı**); ön yüz (front-matter):
```
---
id: privacy            # terms | privacy | kvkk_notice | dpa | account_deletion (bilgi sayfası; onay istenmez)
title: Gizlilik Politikası
version: 2026-10-16    # değiştikçe yeniden onay istenir
effective_date: 2026-10-16
required_for: [register]   # register | site_application | (boş)
---
```
Yer tutucular `{{company_name}}`, `{{company_address}}`, `{{mersis_no}}`, `{{kep_address}}`, `{{contact_email}}`, `{{contact_phone}}` — sunucu `platform_settings.legal.*` değerleriyle değiştirir; dolmamış olan `[……]` olarak bırakılır ve belge `complete:false` sayılır. İzinli Markdown alt kümesi: `#`/`##`/`###` başlık, paragraf, `-` ve `1.` listeler, `**kalın**`, `[metin](https://…)`. **Tablo yok.**

**Koşullu bölüm (2026-10-21, karar H1: KEP ve MERSİS boş kalabilir, boş alan metinde görünmez).** İsteğe bağlı alanlar (`LEGAL_OPTIONAL_PLACEHOLDERS` = `mersis_no`, `kep_address`) şablonda YALNIZ kendi bölümünün içinde kullanılır: `telefon {{contact_phone}}{{#kep_address}}; KEP {{kep_address}}{{/kep_address}}.` Alan doluysa bölümün içeriği yazılır (çıktı bölümsüz yazımla harfi harfine aynı); boşsa bölüm hiç yazılmaz, yalnız bölümden oluşup boşalan satır (ör. `{{#mersis_no}}- **MERSİS no:** {{mersis_no}}{{/mersis_no}}`) atılır ve belge bu yüzden eksik sayılmaz. Kurallar: bölüm tek satırdır, iç içe olamaz; zorunlu alanın bölümü etkisizdir (içerik yazılır, alan boşsa `[……]`); bilinmeyen alan ya da kapanmamış / eşleşmeyen / iç içe etiket `[……]` olur ve belgeyi eksik yapar. Bölümler değerler eklenmeden önce çözülür; eklenen değer etiket üretemez. Testler: `server/test/legal_documents.test.js` (birim), `server/test/legal_real_documents.test.js` (gerçek belgelerde bölüm dışı kullanım yasak; H1 değerleriyle boş etiket yok). Platform Ayarları ekranı (`lib/ui/views/platform_settings_view.dart`) iki alanı "isteğe bağlı" diye anlatır, "[……]" uyarısını yalnız diğer alanlar için verir (widget testi `test/screens/platform_settings_view_test.dart`, "karar H1").

- `GET /public/legal-documents` → `{"documents":[{"id","title","version","effective_date","required_for":[],"complete":true}]}`
- `GET /public/legal-documents/:id` → `{"id","title","version","effective_date","required_for":[],"complete":true,"content_md":"…"}`
- `GET /legal/:id` → aynı belgenin sade HTML sayfası (mağaza/web bağlantısı için; `text/html`, kendi içinde stilli, kaçışlı). Ayrıca `GET /legal/account-deletion` → `account_deletion` belgesinin sayfası (Google Play "veri silme URL'si"; içeriği hukuk ajanı yazar: uygulamadaki adımlar + e-posta ile talep yolu). Belge dosyası yoksa sunucu kısa bir yedek metin döner.
- Onay kaydı tablosu `user_consents(id, user_code, document_id, version, accepted_at, source)`; kimliksizleştirilen hesaplarda kayıtlar tombstone'a bağlı kalır.
- `GET /me/consents` → `{"consents":[{"document_id","version","accepted_at"}],"pending":[{"id","title","version"}]}` (`pending`: `required_for` belgelerden geçerli sürümü onaylanmamış olanlar; yalnız `complete:true` olanlar).
- `POST /me/consents` gövde `{"documents":[{"id","version"}]}` → `200 {"consents":[…]}`; sürüm güncel değilse `409 CONSENT_VERSION_STALE`.
- Kayıt uçları (`/auth/register-individual`, `/auth/register`, `/auth/site-manager/register`) ve site başvurusu (`POST /site-applications`) gövdesi isteğe bağlı `accepted_documents:[{id,version}]` alır (onaylar kayıtla birlikte yazılır). **Zorunluluk**: `platform_settings legal.enforce_consents = on` ise ve belge `complete` ise eksik/eski → `400 {"code":"CONSENT_REQUIRED","missing":["terms",…]}`. Varsayılan `off` (eski istemciler çalışır).

### 1.5 Veri dışa aktarma — `POST /me/data-export` (auth)
Gövde `{"current_password":"…"}`. Hatalar: `CURRENT_PASSWORD_REQUIRED` / `CURRENT_PASSWORD_INVALID` (400), `CURRENT_PASSWORD_LOCKED` (429, mevcut izleyici paylaşılır), `EXPORT_RATE_LIMITED` (429; kullanıcı başına 24 saatte 3). Yanıt `200`, `application/json; charset=utf-8`, `Cache-Control: no-store`, `Content-Disposition: attachment; filename="kisisel-veri-<user_code>-<YYYYMMDD>.json"`:
```json
{ "format_version": 1, "generated_at": "ISO", "notice": "…", "user": {…}, "memberships": [], "apartment_memberships": [],
  "people_records": [], "vehicles": [], "consents": [], "notification_preferences": {}, "announcements_received": [],
  "finance_statements": [], "site_applications": [], "guest_passes": [], "door_events": [], "excluded": ["…neden dışarıda"] }
```
Kapsam kullanıcının **kendi** verisidir (kendi verdiği ve kendi adına üretilen). Dışarıda: parola özeti, token'lar, başkalarının kişisel verisi (aynı dairedeki diğer sakinler), yönetici iç notları (sebep `excluded` içinde yazılır). Alanlar şemadan türetilir, uydurulmaz.

### 1.6 Hesap silme
- `POST /me/account-deletion/preview` (auth) → `{"can_delete":bool,"blockers":[{"code","message","site_id"?}],"will_remove":["…"],"will_keep":["…"]}`
- `POST /me/account-deletion` gövde `{"current_password":"…","confirm":true}` → `200 {"deleted":true}`; engel varsa `409 {"code":"ACCOUNT_DELETE_BLOCKED","blockers":[…]}`; parola hataları 1.5'teki kodlar.
- Engel kodları: `SUPER_USER`, `LAST_SITE_MANAGER` (sitenin tek aktif yöneticisi; üye olup olmadığına bakılmaz; reddedilmiş site ve yöneticinin kapatma talebi gönderdiği `pending_super_user_approval` site hariç; talep bekleyen site için önizleme `will_keep` notu), `OPEN_DEBT` (Finans modülü açık sitede KENDİ hesabın Borcum bakiyesi > 0; aile üyesi, salt okunur karşı hesap ve alacak hariç; ek alanlar `site_id`, `apartment_id`, `amount_minor` kuruş, `account_party`; hesap `finance_read_service.ownOpenDebts`, eşitleme yapmaz). İki engel birlikte 409 `ACCOUNT_DELETE_BLOCKED` `blockers` içinde döner; önizleme ve silme işlemi (kilitler altında) aynı kontrolü yapar. Yarış: eşzamanlı tahsilat silmeyi gereksiz engelleyebilir (güvenli taraf). Dekont gönderen sakin onaya kadar engelli kalır.
- **Saklama istisnası (075):** hesap silinse bile `apartment_residency_log` (daire sakini adli kaydı) satırları **silinmez ve değiştirilmez**; kayıtta kullanıcı kodu FK'sız sayı, ad ise silme anındaki anlık görüntüdür (iletişim bilgisi yok). Hesap silme akışı bu kaydı yalnız EKLER (`moved_out / account_deleted`). Dayanak ve avukat soruları: `docs/PLATFORM_ADLI_KAYIT.md`, `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md` (14-15). `[AVUKAT DOĞRULASIN]`
- Etki (tek işlemde): hesap **kimliksizleştirilir** (satır kalır — yabancı anahtarlar bozulmasın): `is_active=false`, `deleted_at`, ad `Silinmiş Kullanıcı`, e-posta `deleted-<user_code>@deleted.invalid`, telefon NULL, parola özeti kullanılamaz rastgele değer; tüm üyelikler ve kapı yetkileri kaldırılır; kullanıcının oluşturduğu aktif misafir geçişleri iptal; bildirim tercihleri, okundu kayıtları, bekleyen e-posta kuyruğu girdileri silinir; açık site başvurusu geri çekilir; `site_people.user_code` NULL yapılır (site yönetiminin CRM/borç/ekstre kayıtları **yasal saklama** gerekçesiyle kalır — hukuk onayına tabi karar); eski adrese "hesabınız silindi" e-postası; `audit_log`'a kimliksiz `account.deleted`. Aynı e-posta ile yeniden kayıt mümkün. Eski token'lar geçersiz (kullanıcı pasif + `deleted_at`).

### 1.8 İstemci ortak arayüzü (sahibi F3; F2 ve F1 bunu kullanır — F3 İLK İŞ olarak bu iki dosyayı yazar)
```dart
// lib/models/app_config.dart
class AppConfig {
  final String minSupportedVersion, latestVersion;
  final String? updateUrlAndroid, updateUrlIos, maintenanceMessage;
  final bool maintenanceActive, legalEnforced;
  final String? supportEmail, supportPhone, supportHours, supportWebUrl;
  factory AppConfig.fromJson(Map<String, dynamic> json); // eksik/null alanlara dayanıklı
}
// lib/services/app_config_service.dart
class AppConfigService {
  static final AppConfigService instance;
  AppConfig? get current;                          // son başarılı yükleme (yoksa null)
  Future<AppConfig?> load({bool force = false});   // 4 sn zaman aşımı; hata -> null (uygulama açılmaya devam eder)
}
```
F2 destek bilgisini `AppConfigService.instance.current` / `load()` ile okur, yoksa "Destek bilgisi yakında" gösterir.

### 1.6.1 Uygulamada eklenen hata kodları (sözleşmeye ek, hepsi geriye uyumlu)
- `POST /me/data-export`: `413 EXPORT_TOO_LARGE` (kısaltılamayan bölüm 5 MB'ı aşarsa; hak iade edilir).
- `POST /me/account-deletion`: `409 ACCOUNT_DELETE_BUSY` (kapsam üç denemede durulmadı), `400 CONFIRM_REQUIRED`; silinmiş hesabın her isteği `401 ACCOUNT_DELETED`.
- `PATCH /me` ve daire şifre değiştirme yarışında hesap silinmişse `401 ACCOUNT_DELETED`; parola değişince yanıta ek `device_token` (yeni parola sürümüne bağlı güvenilir cihaz belirteci).
- Yönetici: `DELETE /admin/users/:id` silinmiş (kimliksizleştirilmiş) hesapta `409 ACCOUNT_ALREADY_DELETED`; `PATCH /admin/users/:id` ve aktivasyon silinmiş hesapta `409 ACCOUNT_DELETED`; `GET /admin/users` silinmişleri varsayılan gizler (`include_deleted=true` ile görünür).
- `POST /auth/login`: yanıta `device_token`, isteğe bağlı gövde/`X-Device-Token`; geçici kilitte kısa `Retry-After` (≤2 sn), gerçek kilitte 900 sn ve artan süre; `WEAK_PASSWORD.reason ∈ required|too_short|too_long|same_as_email|same_as_name|common` (en çok 128 karakter VE 72 bayt).

### 1.7 Parola ve oturum (S-C)
Yeni/değişen/sıfırlanan parola: **en az 8**, en çok 128 karakter; e-posta/ad ile aynı olamaz; küçük bir yaygın parola listesinde olamaz → `400 {"code":"WEAK_PASSWORD","error":"…"}`. Mevcut kullanıcıların eski parolaları girişte çalışmaya devam eder. İstemci doğrulayıcı sahibi: F2 (`lib/ui/helpers/password_policy.dart`).

## 2. Ajan sahiplikleri

| Ajan | Sahip olduğu yeni dosyalar | Paylaşılan dosyada izin verilen küçük düzenleme |
|---|---|---|
| **S-A** sunucu hesap | `server/src/modules/account_*.js`, `server/migrations/036_*.sql`, `server/test/account_*.test.js` | `db.js` (036 bloğu), `server.js` (router bağla), `qa_platform_pg.mjs` (`account` bölümü) |
| **S-B** sunucu platform | `server/src/modules/{legal_*,app_config_*,client_error_*,platform_config_*}.js`, `server/migrations/035_*.sql`, `server/test/{legal,app_config,client_error,platform_config}*.test.js` | `db.js` (035 bloğu), `server.js`, `auth_routes.js` + `site_application_routes.js` (yalnız `accepted_documents`), `qa_platform_pg.mjs` (`platform_services` bölümü) |
| **S-C** sunucu güvenlik | `server/src/security/*`, `server/test/security_*.test.js` (+ gerekirse 037) | `auth_routes.js` (parola ilkesi/kilitleme), `config/env.js`, `jwt.js`, `login_throttle.js` |
| **F1** | `lib/ui/views/account_*`, `lib/ui/widgets/account_*`, `lib/services/account_api.dart`, `lib/models/account_*.dart`, `lib/ui/views/platform_settings_view.dart`, `lib/ui/views/client_errors_view.dart`, ilgili testler | `profile_view.dart` (tek satır giriş), `yan_menu.dart` + `home_page.dart` (süper kullanıcı girişi) |
| **F2** | `lib/models/legal_*.dart`, `lib/services/legal_api.dart`, `lib/ui/views/{legal_*,help_*,onboarding_*}`, `lib/ui/helpers/password_policy.dart`, ilgili testler | kayıt/giriş/sıfırlama/site başvurusu ekranları, `profile_view.dart` (yalnız parola doğrulayıcı), `yan_menu.dart` + `home_page.dart` (Yardım girişi) |
| **F3** | `lib/services/{app_config,crash_reporter,app_version}*.dart`, `lib/ui/views/{update_required,maintenance}_view.dart`, `android/**`, `ios/**`, `docs/YAYIN_HAZIRLIGI.md`, ilgili testler | `lib/main.dart` (hata kancaları + açılış kapısı) |
| **OPS** | `deploy/ops/*`, `docs/OPERASYON_YEDEK_IZLEME.md`, `.github/workflows/uptime.yml` | — (VPS'te yalnız `~/ops`, `~/backups/scheduled`, kullanıcı crontab'ı) |
| **LEGAL** | `server/legal/*.md`, `docs/yasal/*` | — |
