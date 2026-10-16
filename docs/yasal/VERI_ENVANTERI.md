# Kişisel Veri Envanteri (2026-10-16)

Kapsam: Site ve Toplu Yaşam Yönetim Sistemi (sunucu `server/`, mobil/web uygulaması `lib/`, kapı cihazı yazılımı `cihaz_kontrol/`, operasyon betikleri `deploy/ops/`). Satırlar koddan çıkarılmıştır ve kaynak olarak tablo/dosya:satır verilir; kodda veya repoda bulunmayan bilgiler (sunucu yapılandırması, sağlayıcı adları, üretimde fiilen çalışan düzen) "DOĞRULANAMADI" olarak ayrıca işaretlenmiştir. Satır numaraları 2026-10-16 tarihli ağaca göredir (paylaşılan sıcak dosyalarda küçük kaymalar olabilir).

Rol kısaltmaları: **Güde** = platform işleticisi (hesap ve platform verisi için veri sorumlusu); **SY** = Site Yönetimi (site verisi için veri sorumlusu, Güde veri işleyen); **süper** = Güde'nin süper kullanıcı rolü (`users.role = 'super_user'`).

Yetki kaynakları: `server/src/modules/people_access.js:29-95` (yönetici/süper yazar; kurul üyesi salt okur; görevli ve sakin kişi listesini göremez), `server/src/modules/finance_access.js:23-38` (finans aynı kural + modül açık olmalı), `server/src/routes/door_log_routes.js:26-199` (geçiş kayıtlarını süper ve site yöneticisi görür).

Hukuki sebep ve saklama sütunları **öneridir**; hukuki karar avukat kontrol listesindedir (`docs/yasal/AVUKAT_KONTROL_LISTESI.md`). "Mevcut davranış" kodda fiilen olandır.

Hesap silme iki farklı yolla olur ve sonuçları farklıdır: (1) kullanıcının uygulamadan silmesi (kimliksizleştirme: `server/src/modules/account_deletion_service.js`), (2) süper kullanıcının yönetim ucundan kalıcı silmesi (`DELETE /admin/users/:id`, `server/src/routes/admin_routes.js:440-553`, gerçek `DELETE FROM users`). Her satırda "Hesap silmede" bu iki yolu ayırır; (2) için ortak notlar V19'dadır.

---

## A. Güde sorumluluğundaki hesap ve platform verileri

### V01 Hesap kimliği ve iletişim
- **Alanlar:** `full_name`, `email`, `phone_number` (isteğe bağlı), `login_name` (yalnız yönetimin açtığı daire hesabı), `user_code`, `role` (super_user, site_manager, apartment_owner, individual), `is_active`, `email_verified`, `approval_status`, `created_at`, `updated_at`, `deleted_at`.
- **Kaynak:** `server/migrations/001_init.sql:19-29`; `server/src/db.js:65-92,138-141,1748`; kayıt alanları (ad, soyad, e-posta, parola) `server/src/services/membership_service.js:219-250`; telefon `server/src/routes/auth_routes.js` PATCH /me.
- **Amaç:** hesap açma, giriş, rol ve yetki, iletişim.
- **Hukuki sebep önerisi:** KVKK m.5/2-c (üyelik sözleşmesi), m.5/2-f.
- **Kim görür:** hesap sahibi; süper; kişinin üyesi olduğu sitenin yöneticisi ve kurul üyesi (ad, e-posta, telefon CRM üzerinden hesaptan **canlı** okunur: `server/src/modules/people_service.js:106-108`; kurul yanıtı `user_code` ve notu içermez: `docs/PLATFORM_KISILER.md` karar 17); **aynı daireye bağlı üyeler birbirinin ad, e-posta ve telefon bilgisini görür** (`server/src/services/membership_service.js:1415-1455`).
- **Saklama:** mevcut davranış hesap açık kaldığı sürece. Öneri: aynı.
- **Hesap silmede (1):** `account_deletion_service.js:371-380`: ad "Silinmiş Kullanıcı", e-posta `deleted-<user_code>@deleted.invalid`, telefon ve kullanıcı adı NULL, rol `individual`, `is_active=false`, `deleted_at` dolu. Satır silinmez.

### V02 Parola ve doğrulama sırları
- **Alanlar:** `password_hash` (bcrypt, maliyet 10), `email_verification_code_hash`, `email_verification_expires_at`, `password_reset_token_hash` (SHA-256), `password_reset_expires_at`.
- **Kaynak:** `server/src/db.js:81-92`; bcrypt: `server/src/routes/auth_routes.js:472`, `server/src/services/membership_service.js:158,260`; sıfırlama belirteci ve 30 dk: `auth_routes.js:304-315`.
- **Amaç:** kimlik doğrulama.
- **Hukuki sebep önerisi:** m.5/2-c, m.5/2-f (güvenlik).
- **Kim görür:** kimse düz halini göremez (yalnız özet).
- **Saklama:** parola sıfırlama belirteci kullanılınca NULL olur; **süresi dolan sıfırlama özeti users satırında kalır** ve `email_verification_code_hash` (eski doğrulanmamış hesap yolu) temizlenmez; ikisi de yalnız özettir.
- **Hesap silmede (1):** NULL'lanır; parola özeti kullanılamaz rastgele değerle değişir (`account_deletion_service.js:296,372-374`).
- **UYARI (istisna):** yönetimin açtığı eski tip daire hesaplarında 4 haneli PIN `apartments.resident_pin_code` sütununda **düz metin** saklanır, yönetici tarafından görülür (`server/src/services/site_service.js:741`) ve PIN değişince bu kopya da güncellenir (`server/src/services/membership_service.js:1891-1978`, `server/src/services/apartment_service.js:63-105,203-214`; kod yorumu "tasarım gereği düz metin"). PIN ayrıca e-postayla düz gönderilebilir (`server/src/mailer.js:160-194`). Gizlilik metinleri bu istisnayı açıkça belirtir; karar avukat kontrol listesinde (madde 14).

### V03 E-posta doğrulama kayıtları
- **Alanlar:** `email`, `code_hash`, `attempt_count`, `is_verified`, `verified_at`, `created_at`.
- **Kaynak:** `server/src/db.js:827-838`.
- **Amaç:** e-posta sahipliğinin kanıtı.
- **Hukuki sebep önerisi:** m.5/2-c, f.
- **Kim görür:** yalnız sunucu.
- **Saklama:** mevcut davranış 2 gün sonra silinir (`server/src/services/maintenance_service.js:37-42`; günlük çalışır: `server/src/server.js:183-203`). Öneri: aynı.
- **Hesap silmede (1):** o e-postaya ait satırlar silinir (`account_deletion_service.js:544`).

### V04 Bekleyen kayıt (e-posta doğrulanmamış)
- **Alanlar:** `email`, `full_name`, `password_hash`, `accepted_documents` (belge, sürüm, zaman), `created_at`, `updated_at`. Hesap bu aşamada oluşmaz.
- **Kaynak:** `server/src/db.js:842-853,1740-1741`; `server/migrations/035_platform_services.sql:52-55`.
- **Amaç:** kayıt akışında doğrulama bekleme.
- **Hukuki sebep önerisi:** m.5/2-c.
- **Kim görür:** yalnız sunucu.
- **Saklama:** mevcut davranış 2 gün sonra silinir (`maintenance_service.js:44-49`).
- **Hesap silmede (1):** o e-postaya ait satır silinir (`account_deletion_service.js:545`).

### V05 Oturum belirteci ve giriş cihazı belirteci
- **Alanlar:** JWT (HS256): yalnız `sub` (kullanıcı kodu), `pv` (parola sürümü), `iat`, `exp`; **e-posta ve rol belirtece yazılmaz** (rol her istekte veritabanından okunur). Varsayılan 30 gün, üst sınır 90 gün. Sunucuda oturum tablosu **yoktur**.
- **Kaynak:** `server/src/jwt.js:10-19,93-94`; cihaz tarafı `lib/services/auth_service.dart:59-61,112,3123` (flutter_secure_storage, anahtar `auth_session`).
- **Amaç:** oturum.
- **Hukuki sebep önerisi:** m.5/2-c.
- **Kim görür:** kullanıcının cihazı.
- **Saklama:** süre dolumuna kadar; çıkışta cihazdan silinir (`auth_service.dart:586-587`).
- **Hesap silmede (1):** hesap pasif + `deleted_at` olduğu için belirteçler geçersizdir; yerel durum `LocalDataWiper` ile silinir (`lib/services/account_local_wipe.dart:60-94`, `lib/services/account_api.dart:507-524`).
- **Giriş cihazı belirteci (S-C):** sunucu girişte `device_token` döndürür (`server/src/routes/auth_routes.js:785`; üretim `server/src/security/login_device_token.js:17-67`; kilit mantığı `server/src/security/login_guard.js:25-29`). Belirteç sunucuda saklanmaz (kullanıcı kodu + rastgele cihaz kimliği, imzalı, 180 gün). **İstemci saklar:** `lib/services/login_device_token_store.dart:19-28,64-103` (`flutter_secure_storage`, anahtar `login_device_tokens_v1`; tanımlayıcılar SHA-256 özeti; en çok 8 kayıt), `lib/services/auth_service.dart:264-277`. **Çıkışta silinmez**, hesap silmede silinir (`login_device_token_store.dart:16-18`, `account_local_wipe.dart:74`).

### V06 Yasal belge onay kayıtları
- **Alanlar:** `user_code`, `document_id`, `version`, `accepted_at`, `source` (register, site_application, in_app).
- **Kaynak:** `server/src/db.js:1699-1710`; `server/migrations/035_platform_services.sql:10-21`. Kayıt yalnız **tamamlanmış** (`complete:true`) ve onay istenen belgeler için yazılır; `complete:false` belge için hiç yazılmaz (`server/src/modules/legal_consent_service.js:72,92-95`).
- **Amaç:** hangi belgenin hangi sürümünün ne zaman onaylandığının ispatı.
- **Hukuki sebep önerisi:** m.5/2-e, m.5/2-f; Aydınlatma Tebliği ispat yükü veri sorumlusundadır.
- **Kim görür:** hesap sahibi (`GET /me/consents`); süper.
- **Saklama:** otomatik silme yok. Öneri: [AVUKAT] ispat süresi (ör. onaydan itibaren 10 yıl veya hesap kapanışından itibaren zamanaşımı süresi).
- **Hesap silmede (1):** kalır, kimliksizleştirilmiş hesaba bağlıdır (`account_deletion_service.js:226-228`). **Hesap silmede (2):** `ON DELETE CASCADE` ile **silinir** (`db.js:1701`).

### V07 Site kurulum başvurusu
- **Alanlar:** `applicant_user_code`, `site_name`, `city`, `district`, `address`, `management_type`, `blocks`, `doors` (JSON), sayılar, `device_uid`, `note`, `status`, `decided_by`, `decision_note`, `plan_code`, `payment_status`; başvuran adı, e-postası ve telefonu `users` tablosundan birleştirilir (kopyalanmaz).
- **Kaynak:** `server/src/db.js:1387-1422`; `server/src/modules/site_application_service.js:120-150`.
- **Amaç:** yeni site kurulumunun incelenmesi.
- **Hukuki sebep önerisi:** m.5/2-c (başvuru), m.5/2-f.
- **Kim görür:** başvuran; süper (başvuran iletişim bilgisiyle).
- **Saklama:** otomatik silme yok. Öneri: karar tarihinden itibaren [AVUKAT] süre.
- **Hesap silmede (1):** yalnız bekleyen başvuru iptal edilir (`account_deletion_service.js:476-502`); **kapanmış (onaylı/reddedilmiş) başvuru satırı kalır**, `applicant_user_code` kimliksizleştirilmiş hesaba bağlıdır.

### V08 Denetim kaydı
- **Alanlar:** `actor_user_code`, `actor_name`, `actor_role`, `action`, `site_code`, `target_type`, `target_id`, `details` (JSON).
- **Kaynak:** `server/src/db.js:985-998` (`site_code` üzerinde yabancı anahtar **yok**); `server/src/modules/audit_service.js:1-102` ("yalnızca eklenir; bakım servisi temizlemez").
- **`details` içinde kişisel veri bulunabilir:** hesabı olmayan kişinin adı değiştirilirse eski ve yeni ad (`server/src/modules/people_service.js:952-960,1060-1061`; telefon, e-posta ve not için değer saklanmaz, yalnız "değişti" yazılır); araç eklenip silinirse plaka (`server/src/modules/vehicle_service.js:157,190`); daire silinirse geçmiş sakinlerin adı, ilişki türü ve tarihleri ile araç sayısı (`server/src/modules/apartment_deletion_audit.js:60-96`).
- **Amaç:** yönetim işlemlerinin izlenebilirliği, güvenlik.
- **Hukuki sebep önerisi:** m.5/2-f, m.5/2-ç.
- **Kim görür:** süper (tamamı); kişi/daire/araç geçmişi uçları o sitenin ilgili kayıtlarını **site yöneticisi ve kurul üyesine** gösterir (`server/src/modules/people_history_service.js:80-121`, `people_access.js:83-84`; telefon, e-posta ve not değerleri `scrubSensitiveChanges` ile ayıklanır).
- **Saklama:** otomatik silme yok (süresiz büyür). **Site silindiğinde de silinmez** (yabancı anahtar yok): geliştirme bekliyor. Öneri: [AVUKAT] sınırlı süre (ör. 2-5 yıl) ve temizleme işi.
- **Hesap silmede (1):** `audit_log`'a **dokunulmaz**: `actor_name` anlık görüntüsü değişmeden kalır (`account_deletion_service.js:546-548`); yalnız yeni bir kimliksiz `account.deleted` satırı eklenir (`:555-563`). **Hesap silmede (2):** `actor_user_code` SET NULL olur, `actor_name` kalır (`db.js:988`).

### V09 İstemci hata raporları
- **Alanlar:** `fingerprint`, `error_type`, `message` (≤500), `app_version`, `build`, `platform`, `os_version`, `route`, `fatal`, `count`, `first_seen`, `last_seen`, `sample_stack` (≤8000). Kullanıcı kodu, IP ve cihaz kimliği (`install_id`) **saklanmaz** (`install_id` yalnız bellek içi hız sınırı anahtarıdır). Metinler saklanmadan önce e-posta, telefon, JWT/Bearer, sorgu dizesi sırları, IPv4, uzun sayı dizileri maskelenerek temizlenir; **ad ve adres gibi serbest metin her koşulda yakalanamaz** (`server/src/modules/client_error_service.js:4-7`). `route` alanı bugün gönderilmez (`currentRoute` hiçbir yerde atanmaz: `lib/services/crash_reporter.dart:133,250`).
- **Kaynak:** `server/src/db.js:1713-1737`; `server/migrations/035_platform_services.sql:23-50`; istemci: `lib/services/crash_reporter.dart:17-62,251-267`.
- **Amaç:** hata ayıklama.
- **Hukuki sebep önerisi:** m.5/2-f.
- **Kim görür:** süper.
- **Saklama:** 90 gün (`server/src/modules/client_error_purge.js:1-57`, `server/src/server.js:200`).
- **Hesap silmede:** hesapla bağı yok.

### V10 Sunucu günlükleri (PM2 stdout, nginx)
- **Alanlar:** HTTP istek satırı (yöntem, gizli değerleri maskelenmiş URL, durum kodu, süre; **IP yok**); `auditLog` JSON satırları (olay adı; bazılarında `user_code`, `device_uid`, `ip`; cihaz kaydı/devri/serbest bırakma olaylarında yöneticinin **e-postası**); QR doğrulama günlüğü yalnız kullanıcı **kodu** yazar (ad yazmaz); posta hataları (e-posta maskelenir). nginx erişim günlüğü (IP + istek adresi) kullanılır, yapılandırması repoda **yoktur**.
- **Kaynak:** `server/src/middlewares/request_logger.js:3-63`; `server/src/utils/helpers.js:7-14`; `server/src/routes/guest_passes_routes.js:417-423` (misafir bağlantısı açılışında `ip`); `server/src/services/device_service.js:936,980,1046` (yönetici e-postası); `server/src/services/qr_access_service.js:287,304,330,411` (kullanıcı kodu); `server/src/services/membership_service.js:93-104`.
- **Amaç:** güvenlik ve hata ayıklama.
- **Hukuki sebep önerisi:** m.5/2-f.
- **Kim görür:** sunucu yöneticisi.
- **Saklama:** PM2 uygulama günlükleri haftalık veya 20 MB'ı aşınca döndürülür, 8 eski dosya tutulur, sıkıştırılır (`deploy/ops/logrotate_pm2.sh:10,21-33`; zamanlama `deploy/ops/install_ops.sh:73`, üretimde devrede olduğu DOĞRULANAMADI). nginx erişim günlüğü süresi DOĞRULANAMADI → kullanıcıdan gerekli.
- **Hesap silmede:** günlüklerden silinmez; süre sınırıyla sınırlanır.

### V11 Bellek içi güvenlik sayaçları
- **Alanlar:** hatalı giriş sayaçları (anahtar: küçük harfli e-posta/kullanıcı adı veya `u:<user_code>`, IP kovası veya giriş cihazı kimliği), hız sınırı kayıtları (IP/kullanıcı).
- **Kaynak:** `server/src/middlewares/login_throttle.js`; `server/src/middlewares/rate_limiters.js:19-38`; `server/src/security/login_guard.js:1-29`.
- **Amaç:** kaba kuvvet ve kötüye kullanımı önleme.
- **Hukuki sebep önerisi:** m.5/2-f.
- **Saklama:** yalnız bellek; süreç yeniden başlayınca silinir.

### V12 E-posta gönderimi (SMTP)
- **Gönderimler:** doğrulama kodu, parola sıfırlama bağlantısı, yönetici daveti, daire giriş bilgileri (kullanıcı adı + PIN), katılım başvurusu bildirimi (başvuran adı, e-postası, notu → yöneticiye), modül talebi ve site başvurusu bildirimi (→ süper), site silme kodu (→ süper), duyuru e-postası, hesap silindi bildirimi.
- **Kaynak:** `server/src/mailer.js:85-709`; `server/src/modules/account_deletion_service.js:626-637`; SMTP sunucusu yalnız ortam değişkeni (`server/.env.example:49-53`), sağlayıcı adı repoda **yok**.
- **Amaç:** işlem ve bilgilendirme iletileri.
- **Hukuki sebep önerisi:** m.5/2-c, m.5/2-f; duyurular için SY m.5/2-a/f.
- **Kim görür:** alıcı; SMTP sağlayıcı (veri işleyen).
- **Saklama:** Güde tarafında gönderilmiş posta kopyası tutulmaz; sağlayıcı tarafı DOĞRULANAMADI.
- **Hesap silmede (1):** eski adrese bilgilendirme e-postası gönderilebilir (SMTP ayarlıysa). **(2):** gönderilmez.

### V13 Platform ayarları (şirket ve destek bilgisi)
- **Alanlar:** `legal.company_name`, `company_address`, `mersis_no`, `kep_address`, `contact_email`, `contact_phone`, `enforce_consents`; `support.email/phone/hours/web_url`; `app.*`.
- **Kaynak:** `server/src/db.js:1374-1382`; `server/src/modules/platform_config_service.js:28-52`.
- **Not:** Güde'nin kendi kurumsal bilgisidir; denetim kaydı yalnız değişen anahtar adlarını yazar.

### V14 Süper kullanıcı OTA işleri
- **Alanlar:** `requested_by_user_code`, `requested_by_email`.
- **Kaynak:** `server/src/db.js:515-528`.
- **Hukuki sebep önerisi:** m.5/2-f (personel verisi).
- **Hesap silmede (1):** `requested_by_email` NULL (`account_deletion_service.js:551`).

### V15 Dışa aktarma hız kaydı
- **Alanlar:** `user_code`, `requested_at` (içerik saklanmaz).
- **Kaynak:** `server/src/db.js:1761-1766`; `server/migrations/036_account_deletion.sql:21-28`.
- **Saklama:** 7 günden eski satırlar dışa aktarma sırasında silinir; hesap silmede silinir (`account_deletion_service.js:552`).

### V16 Destek yazışmaları
- DOĞRULANAMADI: kodda destek talep sistemi yok; yalnız `support.email` ayarı var (`platform_config_service.js:37-42`). E-posta kutusundaki yazışmalar Güde'nin kurumsal e-posta altyapısındadır → saklama süresi kullanıcıdan gerekli.

### V17 Yedekler
- **İçerik:** tam veritabanı dökümü (`pg_dump`, tüm kişisel veri) ve yapılandırma yedeği (`.env`, nginx sitesi, `data`, `public`, roller).
- **Kaynak:** `deploy/ops/backup_db.sh:1-60,117-125,132-137,170-196,230-270`; `deploy/ops/offsite_push.sh`; `deploy/ops/pull_backups_windows.ps1:1-60`; `deploy/ops/install_ops.sh:26-28`.
- **Repoda görülen düzen:** sunucuda günlük 14, haftalık 8, aylık 6 yedek (`backup_db.sh:4-6,21-23`); yapılandırma yedeği ve dış kopya AES-256-CBC ile şifrelenir (`:7-8,113,241-253`); dosya ve dizin izinleri 600/700 (`:121,137,245`); dış kopya hedefi `~/.config/kapi-offsite.env` ile verilir, yapılandırılmamışsa atlanır (`offsite_push.sh:34-38`); Windows bilgisayarı şifreli dosyaları `scp` ile çekebilir (`pull_backups_windows.ps1:3-10`; yönetim bilgisayarı bir yedek konumudur). Repoda görülen sürümde dış kopya adedi 14'tür (`backup_db.sh:24`) ve haftalık/aylık kopyalar günlük dosyanın düz kopyasıdır (`promote`: `backup_db.sh:82-110`).
- **Koordinatörün bildirdiği hedef düzen (OPS düzeltmesi sürüyor, repoda henüz doğrulanmadı):** haftalık, aylık ve dış kopyalar şifreli; yalnız en son günlük döküm şifresiz ama 600/700 izinli; dış kopyalar en çok ~210 gün. Metinler bu hedefe göre yazıldı ve üretimdeki fiili düzen `[KARAR/BİLGİ GEREKLİ]` ile işaretli bırakıldı.
- **Hukuki sebep önerisi:** m.5/2-f (güvenlik, süreklilik); m.5/2-ç.
- **Saklama:** yerel en çok ~6 ay (aylık 6 adet), dış kopya ~210 gün → silinen verinin yedeklerden yok olması en geç yaklaşık 7 ay.
- **Hesap silmede:** yedekten silinmez; yedek döngüsüyle yok olur. Geri yüklenen yedekte silinmiş hesap yeniden belirebilir (silme işleminin yeniden uygulanması prosedürü gerekir).
- **Üretimde zamanlanıp zamanlanmadığı, dış kopya hedefi ve şifre anahtarının saklanması:** DOĞRULANAMADI.

### V18 Operasyon uyarı alıcı önbelleği
- **Alanlar:** aktif süper kullanıcıların e-posta adresleri listesi (`~/ops/state/recipients`, izin 600), uyarı e-postaları ve `~/ops/logs/alerts.log`.
- **Kaynak:** `deploy/ops/common.sh:103-134`; `deploy/ops/healthcheck.sh:2-11` (API sağlığı, PM2, Postgres, disk, bellek, yedek yaşı, TLS sertifika bitişi, MQTT uçları); `.github/workflows/uptime.yml:15-39` (GitHub Actions saatlik/yarım saatlik `/health` yoklaması; kişisel veri taşımaz).
- **Amaç:** erişilebilirlik uyarısı. Kişisel veri ihlali tespiti yapmaz.
- **Hukuki sebep önerisi:** m.5/2-f (personel verisi).
- **Saklama:** önbellek dosyası silinmez, güncellenir.

### V19 Süper kullanıcının kalıcı silme yolu
- **Davranış:** `DELETE /admin/users/:id` gerçek `DELETE FROM users` yapar (`server/src/routes/admin_routes.js:440-553`): üyelikler, katılım talepleri, karekod belirteçleri, misafir bağlantıları (`guest_passes` satırları silinir), kapı yetki istisnaları silinir; `door_access_logs.user_code` NULL olur ama **`user_name` ve `ip_address` kalır** (30 gün sınırına kadar); `user_consents` **CASCADE ile silinir**; CRM satırında ad ve telefon `BEFORE DELETE` tetikleyicisiyle yedeklenir ve e-posta temizlenir (`server/src/db.js:1168-1220`); **hesap silindi e-postası gitmez**; denetim satırlarında `actor_user_code` NULL, ad kalır.
- **Fark:** bu yol, kullanıcının kendi silmesindeki kimliksizleştirmeden farklıdır; yönetici kimliksizleştirme aracı geliştirilecek (bkz. Hesap ve Veri Silme §4 işareti).

---

## B. Site Yönetimi sorumluluğundaki site verisi (Güde veri işleyen)

### V20 Site ve yapı bilgisi
- **Alanlar:** `sites`: `name`, `address`, `city`, `district`, blok/daire/kapı sayıları, özellik bayrakları, geofence merkezi (`geofence_latitude`, `geofence_longitude`, yarıçap), `qr_totp_secret`, `qr_rotation_seconds` (site bazında; sunucu 10-300 sn arasına kısar, varsayılan 30), silme talebi alanları (`deletion_requested_by_name`, `_role`, `_at`); `site_blocks.block_name`; `apartments.unit_label`, `floor`, `gross_area_m2`, `net_area_m2`, `land_share_*`, `category`, `responsible_party`; `site_doors.door_name`. Site yöneticisi geofence merkezini kendi o anki GPS konumuyla belirleyebilir (`lib/ui/widgets/site_security_policy_dialog.dart:214-231`).
- **Kaynak:** `server/src/db.js:200-322,584-637,1105-1141`; `server/src/utils/site_rules.js:348-356`; `server/src/routes/admin_routes.js:993-994`.
- **Amaç:** site yönetimi, kapı ve aidat hesapları.
- **Hukuki sebep önerisi:** m.5/2-a (KMK), m.5/2-c.
- **Kim görür:** SY; sakin kendi dairesi.
- **Not:** adres ve daire bilgisi tek başına kişiye bağlanmazsa kişisel veri değildir; `responsible_party` ve dairenin CRM ilişkisiyle birleşince kişisel veridir.
- **Saklama:** site ömrü. **Hesap silmede:** etkilenmez.

### V21 Üyelik ve roller
- **Alanlar:** `site_manager_sites` (site, yönetici, `link_source`), `site_memberships` (`user_code`, rol: SITE_OWNER, SITE_ADMIN, RESIDENT, BOARD_MEMBER, STAFF, `is_active`), `apartment_memberships` (rol: APARTMENT_ADMIN, FAMILY_MEMBER).
- **Kaynak:** `server/src/db.js:572-578,855-881,1005-1022`.
- **Amaç:** yetkilendirme.
- **Hukuki sebep önerisi:** m.5/2-c, m.5/2-a.
- **Kim görür:** SY, süper; kullanıcı kendi üyelikleri.
- **Hesap silmede (1):** silinir (`account_deletion_service.js:405-426`).

### V22 Katılım başvuruları ve davetler
- **Alanlar:** `join_requests` (`user_code`, daire, durum, `notes` ≤500, `rejection_reason`, `reviewed_by_user_code`), `site_join_tokens` (belirteç, oluşturan), `site_manager_invitations` (`email`, `full_name`, `invited_by_user_code`, belirteç, durum, 7 gün süre).
- **Kaynak:** `server/src/db.js:883-912,946-959`; `server/src/services/membership_service.js:57` (NOTE_MAX_LENGTH).
- **Amaç:** sakin onayı, yönetici daveti.
- **Hukuki sebep önerisi:** m.5/2-c, f.
- **Kim görür:** SY, süper; başvuran kendi başvurusu.
- **Saklama:** otomatik silme yok (süresi dolan davetler EXPIRED olarak satırda kalır). Öneri: kapanıştan sonra [AVUKAT] süre.
- **Hesap silmede (1):** kullanıcının talepleri silinir; davet belirteçleri iptal; kullanıcının eski e-postasına gelen davetlerde e-posta tombstone ile değişir (`account_deletion_service.js:429-443`).

### V23 Daire hesabı (eski tip)
- **Alanlar:** `apartments.resident_user_code`, `resident_email`, `resident_pin_code` (düz metin), `users.login_name`, `users.phone_number`.
- **Kaynak:** `server/src/db.js:595-617`; `server/src/services/apartment_service.js:63-105,113-292,380-400`.
- **Amaç:** hesapsız sakine kapı erişimi için yönetimin açtığı hesap.
- **Hukuki sebep önerisi:** m.5/2-c, f.
- **Kim görür:** SY (PIN dahil: `server/src/services/site_service.js:741`), süper.
- **Hesap silmede (1):** `resident_email` NULL, devir kuralları (`account_deletion_service.js:405-420`).
- **Risk:** düz metin PIN (bkz. V02 uyarısı).

### V24 CRM kişi kaydı
- **Alanlar:** `site_people`: `full_name`, `phone`, `email`, `note`, `user_code`, `is_active`, `created_by`. Hesabı olan kişide ad/telefon/e-posta `users`'tan okunur (burada boş).
- **Kaynak:** `server/src/db.js:1047-1065`; `docs/PLATFORM_KISILER.md` Temel kararlar.
- **Amaç:** malik/kiracı/aile üyesi kaydı, duyuru kitlesi, borç sorumlusu.
- **Hukuki sebep önerisi:** m.5/2-a (KMK yönetim görevleri), m.5/2-e, m.5/2-f.
- **Kim görür:** SY yazar; kurul üyesi okur (not hariç); görevli ve sakin göremez; sakin kendi kaydını `GET /app/my-records` ile görür.
- **Saklama:** kayıtlar silinmez (pasifleşir). Öneri: ilişki bitiminden itibaren [AVUKAT] süre sonunda silme/anonimleştirme (otomatik iş yok → geliştirme gerekir).
- **Hesap silmede (1):** kişi pasifleşir, `user_code` NULL, ad **kalır** (`CRM_KEEP_NAME = true`: `server/src/modules/account_common.js:15-19`; `account_deletion_service.js:531-541`), e-posta NULL; hesaptaki telefon kopyalanmaz **ama yönetimin kişi satırına girdiği telefon ve not kalır**. **(2):** ad ve telefon tetikleyiciyle yedeklenir (V19).
- **Serbest metin riski:** `note` özel nitelikli veri içerebilir (yönetici girer).

### V25 Daire-kişi ilişkisi ve geçmişi
- **Alanlar:** `apartment_residencies`: `relation` (owner, tenant, family_member, resident), `is_current`, `move_in_date`, `move_out_date`, `origin`.
- **Kaynak:** `server/src/db.js:1068-1102`.
- **Amaç:** kimin hangi dönemde hangi dairede olduğu (aidat ve duyuru için).
- **Hukuki sebep önerisi:** m.5/2-a, e, f.
- **Kim görür:** SY, kurul (okur); kişi kendi kaydını.
- **Saklama:** silinmez ("Kayıtlar silinmez": `docs/PLATFORM_KISILER.md`). Öneri: V24 ile aynı.
- **Hesap silmede (1):** güncel ilişkiler biter (`account_deletion_service.js:518-526`); kayıt kalır.

### V26 Araç kaydı
- **Alanlar:** `plate` (normalize), `plate_display`, `note`, `person_id`, `apartment_id`, `is_active`.
- **Kaynak:** `server/src/db.js:1144-1157`. Kamera veya otomatik plaka tanıma kodda **yoktur** (plaka elle girilir).
- **Amaç:** otopark ve site güvenliği.
- **Hukuki sebep önerisi:** m.5/2-f (SY).
- **Kim görür:** SY, kurul (not hariç).
- **Saklama:** pasif kayıt silinmez. Öneri: pasifleşmeden [AVUKAT] süre sonra silme (geliştirme gerekir).
- **Hesap silmede (1):** pasifleşir; plaka ve araç notu kalır (`account_deletion_service.js:527-530`).

### V27 Kapı yetki istisnaları
- **Alanlar:** `user_code`, `door_id`, `is_allowed`, `granted_by_user_code`, `notes`.
- **Kaynak:** `server/src/db.js:931-944`.
- **Hesap silmede (1):** silinir (`account_deletion_service.js:451`).

### V28 Karekod belirteçleri ve konum
- **Alanlar:** `token`, `user_code`, `user_role`, `user_name`, `request_latitude`, `request_longitude`, `request_accuracy`, `is_mocked`, kullanım/red alanları (`used_at`, `last_denial_reason`, `denied_door_name`, `used_device_uid`), süre alanları.
- **Kaynak:** `server/src/db.js:685-697,770-824`; `server/migrations/013-015`; `server/src/services/qr_access_service.js:64-67,91-124`. İstemci konumu karekod oluştururken yalnız site `require_geofence` ise gönderir (`lib/ui/widgets/dynamic_qr_pass_modal.dart:439-452`). **Ekransız (statik karekodlu) kapı cihazında karekod okutulurken konum, site ayarından bağımsız zorunludur** (sitede konum merkezi tanımlıysa): `server/src/routes/app_doors_routes.js:347-354`, `server/src/services/geofence_service.js:229`, `lib/models/door_record.dart:135`. Uzaktan kapı açmada konum yalnız doğrulanır, yazılmaz (`app_doors_routes.js:222-233`).
- **Amaç:** tek kullanımlık, kısa ömürlü kapı geçişi; konum doğrulaması.
- **Hukuki sebep önerisi:** m.5/2-c, f; konum için açık rıza gerekip gerekmediği avukat sorusu.
- **Kim görür:** sunucu; kullanıcı kendi belirtecinin durumu.
- **Saklama:** süresi dolan/değiştirilen belirteçler 1 gün sonra silinir; temizlik günlük çalıştığından en geç ~2 gün (`maintenance_service.js:29-35`). Belirteç ömrü site ayarına göredir (10-300 sn; varsayılan 30).
- **Hesap silmede (1):** silinir (`account_deletion_service.js:446`).

### V29 Misafir geçiş bağlantıları
- **Alanlar:** `title` (≤80, kullanıcının yazdığı serbest metin, ör. misafir adı), `token`, `expires_at`, `max_uses`, `used_count`, `created_by_user_code`. Bağlantıyı kullanan misafirden yalnız IP geçiş kaydına yazılır.
- **Kaynak:** `server/src/db.js:655-669`; `server/src/utils/guest_pass_utils.js:9-11`; `server/src/routes/guest_passes_routes.js:84-114,415-459`. Misafir sayfası konum veya başka veri toplamaz (`guest_pass_utils.js:222`).
- **Hukuki sebep önerisi:** m.5/2-f.
- **Kim görür:** oluşturan kullanıcı; SY geçiş kaydında.
- **Saklama:** **otomatik silme yok** (süresi bitmiş satırlar kalır). Öneri: süre bitiminden [ÖNERİ 30 gün] sonra silme (geliştirme gerekir).
- **Hesap silmede (1):** pasifleşir, başlık "Silinmiş kullanıcının geçişi" olur (`account_deletion_service.js:447-450`). **(2):** satırlar silinir.

### V30 Kapı geçiş kayıtları
- **Alanlar:** `site_code`, `door_id`, `door_name`, `user_code`, `user_name`, `user_role`, `apartment_label`, `trigger_type`, `opened_at`, `ip_address`, `device_uid`, `client_log_id`.
- **Kaynak:** `server/src/db.js:718-744`; `server/src/services/door_service.js:70-128`; `server/src/routes/app_doors_routes.js:222-233` (`ipAddress: req.ip`); `server/src/routes/guest_passes_routes.js:442-453`; çevrimdışı cihaz kayıtları `server/src/services/door_log_service.js:303-347,423-425` (**`user_code` NULL** yazılır, ad cihazdan gelir). Çıktı alanları: `server/src/utils/helpers.js:444-460` (IP dahil).
- **Amaç:** güvenlik, uyuşmazlık, yönetim raporu (yönetici PDF çıktısı: `lib/services/pdf_logs_service.dart`).
- **Hukuki sebep önerisi:** m.5/2-f (SY); m.5/2-e.
- **Kim görür:** SY (yönetici), süper. Sakin kendi geçişlerini yalnız "Verilerimi İndir" dosyasında görür (`server/src/modules/account_export_service.js:189-192`). **Misafir bağlantısıyla yapılan geçişte (`trigger_type='guest_pass'`) IP adresi misafire aittir; oluşturan sakinin dışa aktarımına girmez** (kod düzeltmesi bekleniyor: dışa aktarmada bu satırların `ip_address` alanı boşaltılacak).
- **Saklama:** 30 gün (`maintenance_service.js:58-63`). Öneri: koru.
- **Hesap silmede (1):** hesaba bağlı satırlarda `user_name` "Silinmiş Kullanıcı", `ip_address` NULL (`account_deletion_service.js:452-455`); **cihazdan senkronlanan çevrimdışı kayıtlarda `user_code` boş olduğundan ad 30 güne kadar kalır**. **(2):** `user_code` NULL; `user_name` ve `ip_address` kalır.

### V31 Duyurular
- **Alanlar:** `title` (≤120), `body` (≤5000, düz metin, serbest), `importance`, `status`, hedef, `created_by`, `published_by`, zamanlama alanları.
- **Kaynak:** `server/src/db.js:1227-1259`.
- **Amaç:** sakinlere bilgilendirme.
- **Hukuki sebep önerisi:** m.5/2-a, f (SY). E-posta ile gönderilen duyurular bilgilendirmedir; ticari ileti ayrımı avukat sorusu (madde 9).
- **Kim görür:** hedef kitlesi; yönetici; kurul (alıcı adları hariç).
- **Saklama:** yayınlanmış duyuru silinmez (yalnız taslak/zamanlanmış silinir). Öneri: [AVUKAT] süre.
- **Serbest metin riski:** gövdeye kişisel veri yazılabilir.

### V32 Duyuru alıcıları ve e-posta kuyruğu
- **Alanlar:** `person_id`, `email` (yalnız gönderilene kadar), `email_hash` (tuzlu SHA-256), `email_status`, `email_attempts`, `read_at`.
- **Kaynak:** `server/src/db.js:1293-1319`; `server/src/modules/announcement_email_queue.js:40,113-126`.
- **Amaç:** teslim ve okundu takibi, günlük sınır.
- **Saklama:** adres gönderim sonrası NULL; özet 3 gün sonra NULL; alıcı satırı duyuruyla birlikte kalır.
- **Hesap silmede (1):** `read_at`, `email`, `email_hash` NULL (`account_deletion_service.js:460-471`).

### V33 Bildirim tercihi ve abonelikten çıkma listesi
- **Alanlar:** `notification_preferences` (`email_announcements`, `push_announcements`); `announcement_email_suppressions.email_hash` (tuzlu özet).
- **Kaynak:** `server/src/db.js:1322-1334`; `server/src/modules/announcement_public_routes.js:177-200`.
- **Amaç:** itiraz/çıkış hakkının uygulanması.
- **Saklama:** özet listesi süresiz. Öneri: [AVUKAT] (itirazın korunması gerekçesiyle süresiz makul olabilir).
- **Hesap silmede (1):** tercih satırı silinir (`account_deletion_service.js:472`); **bastırma özeti kalır**.

### V34 Aidat tanımları ve borçlandırma çalıştırmaları
- **Alanlar:** ad, tür, dağıtım yöntemi, tutar, dönem, hedef; `fee_runs`: toplam, daire sayısı, `posted_by`. Kişi verisi yok (yalnız oluşturan kullanıcı kodu).
- **Kaynak:** `server/src/db.js:1441-1518`.
- **Hukuki sebep önerisi:** m.5/2-a, ç, e.
- **Saklama:** silinmez (defter bütünlüğü); site silinirse CASCADE.

### V35 Defter (borç/tahsilat)
- **Alanlar:** `apartment_id`, `kind`, `amount_minor`, `period`, `entry_date`, `due_date`, `definition_name`, `payer_party`, `method` (nakit, havale/EFT, çek), `description` (≤200, serbest), `reverses_entry_id`, `reversal_reason`, `created_by`. Kişi adı yok; daire üzerinden kişiye ulaşılır.
- **Kaynak:** `server/src/db.js:1523-1572,1586-1695` (değişmezlik tetikleyicileri); `docs/PLATFORM_FINANS.md`.
- **Amaç:** aidat/borç takibi, hesap verme.
- **Hukuki sebep önerisi:** m.5/2-a, ç, e.
- **Kim görür:** yönetici, süper; kurul üyesi tüm daire bakiyelerini salt okur; sakin yalnız kendi dairesinin borcunu görür: sorumlu tarafta (malik/kiracı/ikisi) güncel kişi yoksa **yedek kural** dairenin güncel malik/kiracı/sakin kayıtlarına görünürlük verir (`server/src/modules/finance_read_service.js:293-333`); son 30 hareket önceki kiracı dönemini de kapsayabilir (`server/src/modules/finance_routes.js:272-278`, `docs/PLATFORM_FINANS.md` risk 7).
- **Saklama:** UPDATE/DELETE tetikleyiciyle engellenir; **tek istisna: üst `sites` satırı artık yoksa (site silme) CASCADE ile silinir** (`db.js:1586-1595`). Öneri: [AVUKAT] 5/10 yıl (TBK zamanaşımı + defter saklama).
- **Hesap silmede:** etkilenmez; `created_by` kimliksizleştirilmiş hesaba bağlı kalır.
- **Serbest metin riski:** `description`, `reversal_reason`.
- **Not:** Kurul'un 18.02.2026 tarihli 2026/348 sayılı ilke kararı borç listelerinin ortak alanlara asılmasını hukuka aykırı bulur; platform bu bilgiyi uygulama içinde yalnız ilgili kişilere gösterir.

### V36 Dönem kapanışları ve modül durumu
- **Alanlar:** `finance_period_closures.closed_by`; `site_modules.updated_by`; `module_requests.requested_by_name`, `note`, `decided_by_name`, `decision_note`.
- **Kaynak:** `server/src/db.js:976-983,1025-1043,1576-1584`.
- **Hesap silmede (1):** `module_requests` adları "Silinmiş Kullanıcı" olur (`account_deletion_service.js:549-550`).

---

## C. Cihaz ve ağ verileri

### V40 Kapı cihazı envanteri ve sahiplik
- **Alanlar:** `device_uid`, `assigned_user_code`, `owner_user_id`, `claimed_at`, `site_code`, `gate_name`, `mqtt_username`, `mqtt_password`, `local_control_token`, `inventory_notes`.
- **Kaynak:** `server/src/db.js:380-440`.
- **Amaç:** cihaz kimliği ve yetkilendirme (cihaz kimlik bilgisi kişisel veri değildir; sahiplik bağı kişiseldir).
- **Hesap silmede (1):** `assigned_user_code` ve `owner_user_id` NULL; erişim anahtarları döndürülür (`account_deletion_service.js:339-349,620-626`).

### V41 Cihaz çalışma durumu
- **Alanlar:** `local_ip`, `public_ip` (sitenin internet çıkış adresi), `firmware_version`, `wifi_rssi`, `last_seen_at`.
- **Kaynak:** `server/src/db.js:474-513`.
- **Not:** `public_ip` bir hanenin/sitenin internet bağlantısı olabilir; tek başına kişisel veri sayılması riski → avukat sorusu 6'ya dahil.
- **Kim görür:** SY (cihaz ekranı), süper.
- **Saklama:** son durum satırı güncellenir (geçmiş tutulmaz).

### V42 Cihaz bağlantı kayıtları
- **Alanlar:** `event_type`, `online_at`, `offline_at`, `duration_seconds`, `reason`, `wifi_rssi`, `local_ip`.
- **Kaynak:** `server/src/db.js:748-763`.
- **Saklama:** 30 gün (`maintenance_service.js:51-56`).

### V43 MQTT komut yükü ve cihaz çevrimdışı kaydı
- **Alanlar:** kapı açma komutunda `requested_by` (uzaktan açmada kullanıcının e-postası, karekodda ad, misafirde `guest_pass:<başlık>`; ≤64 karakter), `request_id`, `requested_at`. Cihaz çevrimdışı kaydı: `user_name` (≤40 bayt), `trigger_type`, daire etiketi, zaman; cihazda **LittleFS `/offline_logs.ndjson`** dosyasında tutulur, dosya 16 KB'ı aşınca en eski kayıtlar atılır, sunucu `logs_ack` gönderince ilgili kayıtlar silinir (ack gelmezse zaman aşımıyla yeniden gönderilir), yazma geçici dosya + yeniden adlandırmayla yapılır.
- **Kaynak:** `server/src/mqtt_bridge.js:91-115,1122-1147`; `server/src/routes/app_doors_routes.js:191-196,368-374`; `cihaz_kontrol/include/offline_log.h:4-12,26-31,75-143,165-180`; teslim: `door_log_service.js:381-461`.
- **Amaç:** kapının açılması, cihaz yerelde kayıt tutması.
- **Hukuki sebep önerisi:** m.5/2-c, f.
- **Not:** cihaz belleğinde zaman bazlı silme yoktur (yalnız ack ve dosya boyutu); ack hiç gelmezse kayıtlar 16 KB sınırına kadar cihazda kalır.

### V44 Kurulum sırasında Wi-Fi bilgisi
- Kullanıcının Wi-Fi adı/parolası Bluetooth ile doğrudan cihaza yazılır; sunucuya HTTP ile gönderilmez (`lib/services/ble_wifi_provision_service.dart`: HTTP çağrısı yok; sunucuda `wifi_password`/`ssid` alanı yok).

---

## D. İstemci (telefon/tarayıcı) verileri

### V50 Güvenli depolama
- `auth_session` (JWT) ve `local_door_cache` (yerel kontrol anahtarları): `lib/services/auth_service.dart:59-61,112,3123,3137`; çıkışta silinir (`:586-587`). `login_device_tokens_v1` (V05): çıkışta silinmez. Hesap silmede `deleteAll` ile hepsi silinir (`lib/services/account_local_wipe.dart:74`). Android yedeklemesi kapalı: `android/app/src/main/AndroidManifest.xml:29-32`.

### V51 Yerel tercihler ve ana ekran widget deposu
- `saved_login_identifier` (e-posta veya kullanıcı adı, "beni hatırla" açıksa) ve `remember_login_credentials`: `lib/ui/pages/login_page.dart:31-32`; `hands_free_auto_listen`: `lib/services/voice_door_service.dart:70`; tema: `lib/services/theme_service.dart`; hata raporu `install_id` (rastgele UUID) ve gönderilemeyen rapor kuyruğu (≤20): `lib/services/crash_reporter.dart:106,117-118`.
- **Ana ekran widget deposu (`home_widget`):** **oturum anahtarının (`auth_token`) bir kopyası**, `api_base_url`, kapı/site adları, kapı durumu, çevrimiçi/karekod bayrakları: `lib/services/door_widget_service.dart:495-545`. Depo Android'de uygulama tercihleri, iOS'ta uygulama grubu (`group.tr.com.gudeteknoloji.siteyonetim`, `door_widget_service.dart:19`) deposudur; **Keychain/Keystore değildir**. Çıkışta ve kapı kalmayınca silinir (`door_widget_service.dart:563-590`, `lib/services/auth_service.dart:590-595`); hesap silmede `logout` aracılığıyla silinir (`account_api.dart:503-523`).

### V52 Cihaz izinleri
- Android: INTERNET, ağ durumu, Wi-Fi durumu, kamera, mikrofon, Bluetooth (+ tarama/bağlanma), yaklaşık ve kesin konum; **arka plan konum izni yok** (`AndroidManifest.xml:2-14`). iOS: yerel ağ (`NSLocalNetworkUsageDescription`), kamera (cihaz, kapı ve site katılım karekodları), mikrofon, konuşma tanıma, Bluetooth, konum (kullanımda) (`ios/Runner/Info.plist:37-50`).
- Konum yalnız `acquireVerifiedPosition` ile alınır (`lib/services/geofence_service.dart:139-196`): geofence gereken kapılarda, ekransız cihaz karekodu okutulurken ve **site yöneticisi konum merkezini belirlerken** (`lib/ui/widgets/site_security_policy_dialog.dart:218`).
- Kamera: `mobile_scanner` ile cihaz, kapı ve **site katılım** karekodlarını okumak için (`lib/ui/pages/qr_scan_page.dart`; kullanım yerleri `lib/ui/dialogs/submit_join_request_dialog.dart:75`, `lib/ui/widgets/claim_device_dialog.dart:92`, `lib/ui/pages/wifi_provision_page.dart:259`, `lib/ui/widgets/resident_door_actions.dart:112`).
- Konuşma: `speech_to_text` cihazın işletim sistemi tanıyıcısını çağırır; `onDevice` zorlaması yoktur (`lib/services/voice_door_service.dart:282-290`), bu nedenle ses işletim sistemi hizmet sağlayıcısının sunucularına gidebilir. Ses Güde sunucusuna gönderilmez (yükleme kodu yok).

---

## E. Üçüncü taraf temas noktaları

- **Sunucu barındırma (VPS):** sağlayıcı adı/ülkesi repoda YOK → kullanıcıdan gerekli.
- **SMTP:** sağlayıcı adı repoda YOK (`server/.env.example:49`: `mail.example.com`).
- **DNS / Cloudflare:** API alan adı Cloudflare kenarına çözümlenir (turuncu bulut; koordinatör bildirimi, repoda doğrulanamaz) → Cloudflare API trafiği için vekil/alt işleyendir. Operasyon listesi (`SAHA_KONTROL_LISTESI.md:1303-1305`) kayıtların "yalnız DNS" olmasını bekler; bu, API için fiili durumla çelişir. MQTT adresinin vekil olup olmadığı belirsizdir (cihazlar bağlanamayacağından vekil olmaması gerekir) → metinde belirsiz bırakıldı.
- **Google bağlantı denetimi:** uygulama API `/health` yanıtlamazsa `https://clients3.google.com/generate_204` adresine içeriksiz istek atar (`lib/services/network_service.dart:57-60`) → IP Google'a görünür.
- **Web sürümü:** `web/.htaccess:38-39` CSP'si Google CDN (gstatic/googleapis) kaynaklarına izin verir; Flutter web derlemesinin CanvasKit ve yazı tiplerini bu adreslerden yükleyip yüklemediği derleme ayarına bağlıdır, DOĞRULANAMADI.
- **Android karekod okuyucu:** `mobile_scanner` (Android'de Google ML Kit kullanır) — görüntü cihazda işlenir; ML Kit'in kendi tanılama verisi göndermesi DOĞRULANAMADI.
- **GitHub Actions:** `.github/workflows/uptime.yml` `/health` adresini yoklar; kişisel veri taşımaz.
- **Mağazalar (Google Play, App Store):** dağıtım kanalı; ayrı veri sorumlusu.
- **Firebase/push, analitik, reklam, çerez:** YOK (`pubspec.yaml:9-33`, `web/index.html`, sunucuda `Set-Cookie` yok).
- **MQTT aracısı:** Güde'nin kendi sunucusu (`mqtt.gudeteknoloji.com.tr`, TLS 8883): `server/.env.example:80-81`; mobil uygulama doğrudan MQTT'ye bağlanmaz (`MqttDoorService` hiçbir yerde örneklenmez).

---

## F. Koddan doğrulanan "olmayan" şeyler (metinlerde bu yönde ifade kullanılabilir)

- Kamera ile görüntü kaydı, yüz tanıma, otomatik plaka tanıma, biyometrik giriş: kodda yok.
- Online ödeme, kart/banka bilgisi: yok (`docs/PLATFORM_FINANS.md` Kapsam; `site_applications.payment_status` alanı vardır ama ödeme sağlayıcısı yoktur: `db.js:1404`).
- Arka plan konum izleme: yok.
- Reklam/analitik SDK, çerez: yok.
- Telefon bildirimi (push): yok (`notification_preferences.push_announcements` yalnız saklanır, `push_available:false`).
- Uygulamanın ses kaydını Güde sunucusuna göndermesi: yok.
