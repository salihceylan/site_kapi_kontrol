# Kişisel Veri Envanteri (2026-10-16)

Kapsam: Site ve Toplu Yaşam Yönetim Sistemi (sunucu `server/`, mobil/web uygulaması `lib/`, kapı cihazı yazılımı `cihaz_kontrol/`, operasyon betikleri `deploy/ops/`). Satırlar koddan çıkarılmıştır ve kaynak olarak tablo/dosya:satır verilir; kodda veya repoda bulunmayan bilgiler (sunucu yapılandırması, sağlayıcı adları, üretimde fiilen çalışan düzen) "DOĞRULANAMADI" olarak ayrıca işaretlenmiştir. Satır numaraları 2026-10-16 tarihli ağaca göredir (paylaşılan sıcak dosyalarda küçük kaymalar olabilir).

Rol kısaltmaları: **Güde** = platform işleticisi (hesap ve platform verisi için veri sorumlusu); **SY** = Site Yönetimi (site verisi için veri sorumlusu, Güde veri işleyen); **süper** = Güde'nin süper kullanıcı rolü (`users.role = 'super_user'`).

Yetki kaynakları: `server/src/modules/people_access.js:29-95` (yönetici/süper yazar; kurul üyesi salt okur; görevli ve sakin kişi listesini göremez), `server/src/modules/finance_access.js:23-38` (finans aynı kural + modül açık olmalı), `server/src/routes/door_log_routes.js:26-199` (geçiş kayıtlarını süper ve site yöneticisi görür).

Hukuki sebep ve saklama sütunları **öneridir**; hukuki karar avukat kontrol listesindedir (`docs/yasal/AVUKAT_KONTROL_LISTESI.md`). "Mevcut davranış" kodda fiilen olandır.

Hesap silme iki farklı yolla olur ve sonuçları farklıdır: (1) kullanıcının uygulamadan silmesi (kimliksizleştirme: `server/src/modules/account_deletion_service.js`), (2) süper kullanıcının yönetim ucundan kalıcı silmesi (`DELETE /admin/users/:id`, `server/src/routes/admin_routes.js:440-553`, gerçek `DELETE FROM users`). Her satırda "Hesap silmede" bu iki yolu ayırır; (2) için ortak notlar V19'dadır.

**2026-10-17 eki (P1 modülleri):** toplu yükleme/dışa aktarma (migration 038), belgeler (039), finans 4b: makbuz, gecikme tazminatı, gider, kasa/banka, hatırlatma (040) ve telefon bildirimi (041) için yeni kayıtlar Bölüm G'dedir (V60-V75); Bölüm E (üçüncü taraflar) ve F ("olmayan şeyler") buna göre güncellendi, V12, V17, V33, V35, V50-V52 satırlarına notlar eklendi. Bu eklerin dayandığı kod, sözleşme belgeleri (`docs/PLATFORM_BELGELER.md`, `docs/PLATFORM_FINANS_4B.md`, `docs/PLATFORM_TOPLU_ISLEMLER.md`) ve migration dosyaları okunarak doğrulanmıştır; kaynaklı satır numaraları 2026-10-17 tarihli ağaca göredir ve bu modüller henüz geliştirildiği için kayabilir. Dağıtım durumu (hangi modülün canlıda açık olduğu) repodan doğrulanamaz: belgeler ve finans modülleri modül kataloğunda varsayılan kapalıdır (`server/src/modules/catalog.js`), telefon bildirimi `PUSH_ENABLED` varsayılan 0'dır (`server/src/modules/push_config.js:4`).

**2026-10-29 eki (modül birleşimi ve karşılaştırma programı):** Bölüm H (V80-V94), temel modül olan anket, komşu panosu, ekipman ve bakım, faaliyet raporu ve dosya deposunu (Drive); Aidat ve Finans'ın içine alınan kart ödemesi ayarını; karşılaştırma programının Dalga B, D ve E ile gelen veri alanlarını (alacak iadesi, kiracı borcunun malike devri, tahakkuk dayanağı, devir alacağı, çoklu malik, geri bildirim ve ekleri, deneme erişim kodu, acil durum bilgisi, yönetici işlem kayıtları görünümü) kapsar. Her satır 2026-10-29 tarihli ağaçta (dal `kuyruk/veri-envanteri`, taban accb247) migration dosyası, hizmet kodu ve sözleşme belgesi okunarak yazılmıştır; okuma kılavuzu Bölüm H başındadır. Bu ağaçta bulunmayan migration numaraları (086, 087, 092-095, 101, 105) için kayıt YAZILMADI. Envantere HÂLÂ girmemiş modüller Bölüm H sonundaki tabloda adıyla listelidir. V08, V20, V25, V26, V35, Bölüm E ve Bölüm F'ye düzeltme veya yönlendirme notu eklendi.

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
- **2026-10-19 GİDERİLDİ (migration 051):** eski tip daire hesaplarının PIN'i artık yalnız `users.password_hash` (bcrypt) olarak saklanır; `apartments.resident_pin_code` her zaman NULL (geri dönüş uyumluluğu için sütun duruyor), yalnız `resident_pin_issued` bayrağı tutulur. PIN oluşturma/sıfırlamada bir kez gösterilir ve bir kez e-postalanır. Değişiklik öncesi yedeklerde eski PIN'ler yedek döngüsü dolana kadar bulunabilir. İnceleme düzeltmeleri (2026-10-19, 2. tur kesin karar): sakin şifresini kendisi belirlemişse (`resident_pin_issued` FALSE) PIN'i YÖNETİCİ sıfırlayamaz (409 `APARTMENT_PIN_RESET_NEEDS_SUPER`; hiçbir şey değişmez), yalnız süper kullanıcı sıfırlayabilir (PIN ona bir kez gösterilir, işaret TRUE olur); sakin kendi şifresini uygulamadan değiştirebilir. Bayrak 051 aktarımında yalnız düz kopya bcrypt ile GÜNCEL parolaya eşitse TRUE yazılır (051 öncesi parolasını değiştiren sakinde FALSE); SQL migration temkinlidir (doğrulanamayanlar FALSE + NULL), doğrulanabilir kopyaları sunucu açılışı bcrypt ile tamamlar. Sıfırlama aynı işlemde hesabın misafir geçişlerini pasifleştirir, kapı karekodlarını iptal eder, telefon bildirimi kayıtlarını siler; gösterge temizlenen/devredilen dairede eski sakinin `resident_email`'i silinir (yeni hesabın PIN'i eski sakine gitmez).

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
- **Kim görür:** süper (tamamı); kişi/daire/araç geçmişi uçları o sitenin ilgili kayıtlarını **site yöneticisi ve kurul üyesine** gösterir (`server/src/modules/people_history_service.js:80-121`, `people_access.js:83-84`; telefon, e-posta ve not değerleri `scrubSensitiveChanges` ile ayıklanır). **2026-10-29 eki:** site yöneticisi ayrıca kendi sitesinin işlem kayıtlarını süzülmüş görünümle okur (`GET /manager/sites/:siteCode/audit-log`, `server/src/modules/site_audit_log_routes.js:31`); ayrıntı V92.
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
- **Kalıcı (DB) istisna — `auth_attempt_limits` (migration 085):** 4 haneli ilk PIN ile giriş ve e-posta / SMS doğrulama kodları için hatalı deneme sayacı, pencere başlangıcı, kilit bitişi ve kilit seviyesi. Hedef anahtar **SHA-256 özetidir** (e-posta, telefon, kullanıcı kodu ve PIN/parola düz metin saklanmaz; PIN hedefi parola özetini de içerir). **Kaynak:** `server/src/security/attempt_limits.js`; `server/src/modules/auth_attempt_limits_schema.js`; `server/migrations/085_auth_attempt_limits.sql`. **Saklama:** kilidi bitmiş ve 30 gündür dokunulmamış satırlar bakım işiyle silinir (`server/src/services/maintenance_service.js`); doğru PIN / kod satırı hemen siler. **Hesap silmede:** özet anahtarlı olduğundan hesapla doğrudan bağı yoktur; süre sınırıyla silinir.

### V12 E-posta gönderimi (SMTP)
- **Gönderimler:** doğrulama kodu, parola sıfırlama bağlantısı, yönetici daveti, daire giriş bilgileri (kullanıcı adı + PIN), katılım başvurusu bildirimi (başvuran adı, e-postası, notu → yöneticiye), modül talebi ve site başvurusu bildirimi (→ süper), site silme kodu (→ süper), duyuru e-postası, hesap silindi bildirimi; 2026-10-17 eki: aidat borç hatırlatma e-postası (→ dairenin sorumlu tarafına; bkz. V71).
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
- **Repoda görülen düzen:** sunucuda günlük 7, haftalık 4, aylık 6 yedek (`backup_db.sh` `KEEP_DAILY`/`KEEP_WEEKLY`/`KEEP_MONTHLY` varsayılanları; kapi-ops.env ile değişir); yapılandırma yedeği ve dış kopya AES-256-CBC ile şifrelenir (`:7-8,113,241-253`); dosya ve dizin izinleri 600/700 (`:121,137,245`); dış kopya hedefi `~/.config/kapi-offsite.env` ile verilir, yapılandırılmamışsa atlanır (`offsite_push.sh:34-38`); Windows bilgisayarı şifreli dosyaları `scp` ile çekebilir (`pull_backups_windows.ps1:3-10`; yönetim bilgisayarı bir yedek konumudur). Repoda görülen sürümde dış kopya adedi 14'tür (`backup_db.sh:24`) ve haftalık/aylık kopyalar günlük dosyanın düz kopyasıdır (`promote`: `backup_db.sh:82-110`).
- **Koordinatörün bildirdiği hedef düzen (OPS düzeltmesi sürüyor, repoda henüz doğrulanmadı):** haftalık, aylık ve dış kopyalar şifreli; yalnız en son günlük döküm şifresiz ama 600/700 izinli; dış kopyalar en çok ~210 gün. Metinler bu hedefe göre yazıldı ve üretimdeki fiili düzen `[KARAR/BİLGİ GEREKLİ]` ile işaretli bırakıldı.
- **2026-10-17 eki (belge deposu):** `deploy/ops/backup_db.sh:10-11,459-460` belge deposunu (`DOCUMENTS_DIR/sites`, `_tmp` hariç; yüklenen belgeler ve gider belgeleri) `config/kapi_documents_<TS>.tgz.enc` adıyla ayrı, şifreli bir arşive alır ve dış kopya klasörüne de kopyalar; yalnızca içerik değişince yeni arşiv üretir, son 5 arşivi tutar, en yenisi hariç 210 günden eskileri siler (`backup_db.sh:42-43`; dış kopya budaması `offsite_push.sh:12-16`). `deploy/ops/restore_test.sh:10,203-208,262` geri yükleme testinde veritabanındaki hazır belge sürümlerinin arşivde bulunmasını denetler. Bu betikler oturum başındaki git durumunda değiştirilmiş (commit'siz) görünüyordu ve üretimde devrede olduğu DOĞRULANAMADI; bir belge diskten kalıcı silinse bile eski arşivlerde 210 güne kadar kalır.
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
- **Alanlar:** `sites`: `name`, `address`, `city`, `district`, blok/daire/kapı sayıları, özellik bayrakları, geofence merkezi (`geofence_latitude`, `geofence_longitude`, yarıçap), `qr_totp_secret`, `qr_rotation_seconds` (site bazında; sunucu 10-300 sn arasına kısar, varsayılan 30), silme talebi alanları (`deletion_requested_by_name`, `_role`, `_at`); `site_blocks.block_name`; `apartments.unit_label`, `floor`, `gross_area_m2`, `net_area_m2` [2026-10-29 düzeltmesi: bu iki sütun migration 078 ile KALDIRILDI, daire alanı artık tutulmaz; geçmiş daire silme denetim kaydında NULL döner: `apartment_deletion_audit.js:30`], `land_share_*`, `category`, `responsible_party`; `site_doors.door_name`. Site yöneticisi geofence merkezini kendi o anki GPS konumuyla belirleyebilir (`lib/ui/widgets/site_security_policy_dialog.dart:214-231`).
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
- **Alanlar:** `apartments.resident_user_code`, `resident_email`, `resident_pin_issued` (bayrak; `resident_pin_code` 051'den beri NULL), `users.login_name`, `users.phone_number`.
- **Kaynak:** `server/src/db.js:595-617`; `server/src/services/apartment_service.js:63-105,113-292,380-400`.
- **Amaç:** hesapsız sakine kapı erişimi için yönetimin açtığı hesap.
- **Hukuki sebep önerisi:** m.5/2-c, f.
- **Kim görür:** SY ve süper; PIN yalnız oluşturma/sıfırlama anında bir kez (yanıtta, `Cache-Control: no-store`). Sakin şifresini kendisi belirlemişse SY PIN'i sıfırlayamaz; yalnız süper kullanıcı sıfırlar ve PIN'i bir kez görür. Sıfırlama denetim kaydına (`apartment.pin_reset`) PIN'siz yazılır: sakinin kendi şifresinin ezilip ezilmediği (`resident_chosen_password`) ve kapanan misafir geçişi / karekod / bildirim kaydı sayıları.
- **Hesap silmede (1):** `resident_email` NULL, devir kuralları (`account_deletion_service.js:405-420`). Gösterge devrinde / temizlenmesinde (üye çıkarma, taşındı, aile reisi değişikliği, yönetici kullanıcı silme) da `resident_email` ve PIN bayrağı silinir; yalnız geri alınabilir pasife alma korur.
- **Risk:** 4 haneli PIN kısa bir sırdır; giriş hız sınırı ve kilit uygulanır. Düz metin saklama 2026-10-19'da kaldırıldı.

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
- **Alanlar:** `apartment_residencies`: `relation` (owner, tenant, family_member, resident), `is_current`, `move_in_date`, `move_out_date`, `origin`; 2026-10-29 eki: `is_account_holder` (çoklu malikte hesap muhatabı işareti, migration 104; bkz. V89).
- **Kaynak:** `server/src/db.js:1068-1102`.
- **Amaç:** kimin hangi dönemde hangi dairede olduğu (aidat ve duyuru için).
- **Hukuki sebep önerisi:** m.5/2-a, e, f.
- **Kim görür:** SY, kurul (okur); kişi kendi kaydını.
- **Saklama:** silinmez ("Kayıtlar silinmez": `docs/PLATFORM_KISILER.md`). Öneri: V24 ile aynı.
- **Hesap silmede (1):** güncel ilişkiler biter (`account_deletion_service.js:518-526`); kayıt kalır.

### V26 Araç kaydı
- **Alanlar:** `plate` (normalize), `plate_display`, `note`, `person_id`, `apartment_id`, `is_active`.
- **Kaynak:** `server/src/db.js:1144-1157`. Araç kaydındaki plaka elle girilir. [2026-10-29 düzeltmesi: eski cümle "kamera veya otomatik plaka tanıma kodda yoktur" artık geçerli DEĞİLDİR. Kamera olayıyla gelen plaka metni ayrıca `plate_events` (`065_device_integrations.sql:52`) ve `plate_decisions` (`073_plate_recognition.sql:81`) tablolarına yazılır; bunlar ve kamera kayıtları bu envanterde henüz yoktur, bkz. Bölüm H sonundaki tablo.]
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
- **Alanlar:** `notification_preferences` (`email_announcements`, `push_announcements`; 2026-10-17 eki: `email_finance_reminders`, `push_show_preview`, `push_quiet_enabled`, `push_quiet_start`, `push_quiet_end`, bkz. V62); `announcement_email_suppressions.email_hash` (tuzlu özet; borç hatırlatma e-postası da aynı listeyi kullanır: `finance_reminder_queue.js:1-3`).
- **Kaynak:** `server/src/db.js:1322-1334`; `server/src/modules/announcement_public_routes.js:177-200`. `push_announcements` artık gerçekten kullanılır: normal duyuru bildirimi için sorgulanır (`push_outbox.js:35`), acil duyuruda yok sayılır.
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
- **2026-10-17 eki:** finans 4b ile aynı daireye bağlı yeni kayıtlar (makbuz V66, gecikme tazminatı V67, gider/tedarikçi V68, kasa-banka V69, ayarlar V70, hatırlatma V71) Bölüm G'dedir. Defterdeki `late_fee_run_id` ile gecikme tazminatı kalemleri aynı değişmez deftere yazılır (`040_finance_4b.sql` başlık yorumu). **2026-10-29 eki:** deftere `source_kind` ile işaretlenen yeni kalem türleri de yazılır: alacak iadesi (`refund`, V86), malike devir (`liability_transfer`, V87), devir bakiyesi ve devir alacağı (`opening`, V94); Fon borcunun dayanağı `fee_runs` üzerinde V88'dedir.

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
- **Telefon bildirimi yerel durumu (2026-10-17 eki):** `SharedPreferences` anahtarları `push.install_id` (rastgele UUID; hata raporu `install_id`'sinden ayrı), `push.registration` (kullanıcı no, FCM jetonunun SHA-256 özeti, izin durumu, zaman), `push.device_enabled` (kullanıcı başına "bu cihazda açık" işareti = açık rıza kaydı), `push.pending_fcm_cleanup`, `push.prompt_dismissed` (`lib/services/push_store.dart:3-19,75-79`). Jetonun kendisi uygulama tarafından saklanmaz; Firebase bileşeni kendi deposunda tutar. Çıkışta sunucu kaydı silinir ve FCM jetonu silinir (`push_service.dart:13-20,386-461`); `install_id` ve tercihler çıkışta silinmez, hesap silmede `LocalDataWiper` tema dışındaki tüm tercihleri sildiği için gider (`account_local_wipe.dart:12-16,100-111`). Android yedeklemesi kapalı olduğundan yedekten dönmez (`push_store.dart:6-8`).
- **Dışa aktarılan / indirilen dosyalar (2026-10-17 eki):** kişi listesi, finans dışa aktarması, hata raporu ve şablon (`toplu_dosya_*`), veri indirme dosyası (`kisisel_veri_*`) ve indirilen belge (`kisisel_veri_belge_*`) paylaşım için geçici klasöre yazılır; paylaşım sonrası ~2 dk içinde silinmek üzere zamanlanır ve 10 dakikadan eski kalanlar süpürülür (`document_file_share.dart:32,57`; `account_export_share.dart:35,107`; `bulk_file_delivery.dart:34`). Eklenti önbellekleri (`share_plus`, `file_picker`) ayrıca silinir (`lib/services/local_cache_purge.dart:1-23`); çıkışta ve hesap silmede tümü süpürülür (`account_local_wipe.dart:72-87,128`). Android'de `share_plus` önbelleği bir sonraki paylaşıma veya silmeye kadar kalabilir; belge TC/IBAN içerebilir (`local_cache_purge.dart:5-7`).
- **Ana ekran widget deposu (`home_widget`):** **oturum anahtarının (`auth_token`) bir kopyası**, `api_base_url`, kapı/site adları, kapı durumu, çevrimiçi/karekod bayrakları: `lib/services/door_widget_service.dart:495-545`. Depo Android'de uygulama tercihleri, iOS'ta uygulama grubu (`group.tr.com.gudeteknoloji.siteyonetim`, `door_widget_service.dart:19`) deposudur; **Keychain/Keystore değildir**. Çıkışta ve kapı kalmayınca silinir (`door_widget_service.dart:563-590`, `lib/services/auth_service.dart:590-595`); hesap silmede `logout` aracılığıyla silinir (`account_api.dart:503-523`).

### V52 Cihaz izinleri
- Android: INTERNET, ağ durumu, Wi-Fi durumu, kamera, mikrofon, Bluetooth (+ tarama/bağlanma), yaklaşık ve kesin konum, bildirim (`POST_NOTIFICATIONS`, 2026-10-17 eki: `AndroidManifest.xml:17`; Android 13 öncesinde çalışma zamanı izni yoktur, `push_firebase_gateway.dart:161-163`; izin yalnız kullanıcı telefon bildirimini açarken istenir, `push_service.dart:9`); **arka plan konum izni yok** (`AndroidManifest.xml:2-14`). iOS: yerel ağ (`NSLocalNetworkUsageDescription`), kamera (cihaz, kapı ve site katılım karekodları), mikrofon, konuşma tanıma, Bluetooth, konum (kullanımda) (`ios/Runner/Info.plist:37-50`).
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
- **Google Drive (sitenin kendi hesabı; 2026-10-29 eki, V84):** `drive_storage` modülü her sitede açıktır, ancak bağlantı yalnız site yöneticisi Google onay ekranını tamamlarsa kurulur ve sunucuda `DRIVE_CLIENT_ID`, `DRIVE_CLIENT_SECRET`, `DRIVE_REDIRECT_URI`, `DRIVE_TOKEN_KEY` tanımlı olmalıdır (`server/src/modules/drive_common.js:23-31`; yoksa `503 DRIVE_NOT_CONFIGURED`). Sunucu şu adreslere bağlanır: `accounts.google.com` (onay), `oauth2.googleapis.com/token` ve `/revoke`, `www.googleapis.com/drive/v3` ve `/upload/drive/v3/files` (`drive_client.js:6-10`); izin kapsamı yalnız `drive.file` (`drive_common.js:8`). Google'a giden içerik: yüklenen dosyanın kendisi (fotoğraf, PDF, belge) ve dosya adı. Üretimde yapılandırıldığı ve bağlı site olup olmadığı DOĞRULANAMADI → kullanıcıdan gerekli. KVKK m.9 yurt dışı aktarımı ve hesap türü (kişisel Gmail / Workspace) avukat konusudur (`docs/PLATFORM_DRIVE_DEPOLAMA.md` bölüm 2; avukat listesi madde 41; saklama taslağı soru 10).
- **Google Firebase Cloud Messaging (FCM) ve iOS'ta Apple APNs (telefon bildirimi):** VAR, 2026-10-17 itibarıyla kodda. Uygulama `firebase_core` ve `firebase_messaging` paketlerini içerir (`pubspec.yaml:37-38`); Firebase Analytics gibi başka Firebase paketi `pubspec.yaml`'da yoktur. Sunucu, hizmet hesabıyla `https://oauth2.googleapis.com/token` ve `https://fcm.googleapis.com/v1/projects/{project_id}/messages:send` adreslerine bağlanır (`server/src/modules/push_fcm.js:4-6,26-27`); Google'a giden içerik: FCM kayıt jetonu, bildirim başlığı ve metni (site adı dâhil; kullanıcı önizlemeyi açtıysa duyuru başlığı), `data` alanında duyuru no, site no ve önem (`push_message.js:4-9,73-92`); iOS'ta `apns` bloğu ile Apple'a da iletilir. Kayıt jetonu yalnızca kullanıcı bir cihazda telefon bildirimini açıkça açtığında üretilir: Android'de `firebase_messaging_auto_init_enabled=false` (`AndroidManifest.xml:83-85`), iOS'ta `FirebaseMessagingAutoInitEnabled=false` (`Info.plist:27-28`), açma anında `setAutoInitEnabled(true)` (`lib/services/push_firebase_gateway.dart:176-179`). `Firebase.initializeApp` Android ve iOS'ta uygulama açılışında çağrılır (`push_firebase_gateway.dart:3-12,220-224`); bu çağrının ve Firebase bileşenlerinin Google'a kendiliğinden gönderdiği teknik veriler (ör. Firebase Installations kimliği) kodla DOĞRULANAMADI → avukat listesi madde 35. Sunucu tarafı varsayılan KAPALI: `PUSH_ENABLED=0` iken hiç kuyruk satırı yazılmaz ve hizmet hesabı dosyası (`FCM_SERVICE_ACCOUNT_FILE`) yoksa özellik kullanılamaz (`push_config.js:4-5,63-78`; `push_outbox.js:60-62`). Üretimde `PUSH_ENABLED` ve Firebase projesi DOĞRULANAMADI → kullanıcıdan gerekli. Google Play "Veri güvenliği" ve App Store gizlilik etiketi beyanları bu modül için güncellenmelidir (`docs/PLATFORM_BELGELER.md` B0 madde 9).
- **Analitik, reklam, çerez:** YOK (`pubspec.yaml`, `web/index.html`, sunucuda `Set-Cookie` yok).
- **MQTT aracısı:** Güde'nin kendi sunucusu (`mqtt.gudeteknoloji.com.tr`, TLS 8883): `server/.env.example:80-81`; mobil uygulama doğrudan MQTT'ye bağlanmaz (`MqttDoorService` hiçbir yerde örneklenmez).

---

## F. Koddan doğrulanan "olmayan" şeyler (metinlerde bu yönde ifade kullanılabilir)

- Kamera ile görüntü kaydı, yüz tanıma, biyometrik giriş: kodda yok (kamera bağlantısı video SAKLAMAZ: `docs/PLATFORM_KAMERA_CCTV.md` "Tasarım"; pubspec'te `local_auth` yok). **2026-10-29 düzeltmesi:** bu satırın eski hâlindeki "otomatik plaka tanıma: kodda yok" ifadesi geçerli DEĞİLDİR; kamera olayıyla gelen plaka METNİ kaydedilir (`plate_events`, `plate_decisions`; görüntü saklanmaz) ve kapı bu karardan açılmaz (`docs/PLATFORM_PLAKA_TANIMA.md` "Bu sürümde ne var, ne yok"). Metinlerde "plaka tanıma yok" denmemelidir.
- Online ödeme, kart bilgisi: yok (`docs/PLATFORM_FINANS.md` Kapsam; `site_applications.payment_status` alanı vardır ama ödeme sağlayıcısı yoktur: `db.js:1404`). 2026-10-29: kart ödemesi için yalnız komisyon bilgi notu tutan ayar tablosu vardır, tahsilat ve kart verisi yoktur (V85). 2026-10-17 düzeltmesi: eski ifade "banka bilgisi yok" idi; finans 4b ile sitenin kendi kasa/banka hesabının adı, notu ve hareketleri yönetimce girilebilir (V69), ancak hesap numarası (IBAN) için ayrı alan yoktur.
- Arka plan konum izleme: yok.
- Reklam/analitik SDK, çerez: yok.
- Hesap sahibine ait banka hesap numarası (IBAN) veya kart bilgisi için ayrı bir alan: yok (`server/` altında IBAN alanı bulunmaz; gider belgeleri ve belgeler serbest dosya olduğu için IBAN/TC içerebilir, bkz. V64-V65). Tedarikçi için yalnız `tax_id` (10-11 haneli vergi veya T.C. kimlik no) alanı vardır (`040_finance_4b.sql:199,207`).
- Telefon bildirimine finansal ayrıntı, tutar, ad veya daire yazmak: yok (bildirim türü yalnız `announcement`: `041_push.sql:59`; metin ayrıntısız: `push_message.js:4-9`). E-postaya belge eki: yok (`docs/PLATFORM_BELGELER.md` A12). Belgeyi kimin indirdiğinin kaydı: yok, yalnız toplu sayaç (`document_resident.js:244`). Toplu yüklemede dosyanın veya ham satırların saklanması: yok (`bulk_import_service.js:4`).
- Telefon bildirimi (push): VAR (yalnız kullanıcı açarsa; bkz. Bölüm E ve V60-V63). Eski ifade ("push yok", `push_available:false`) artık geçerli değildir.
- Uygulamanın ses kaydını Güde sunucusuna göndermesi: yok.

---

## G. P1 modülleri (2026-10-17 eki): telefon bildirimi, belgeler, finans 4b, toplu işlemler

Bu bölümdeki modüller kod olarak vardır. Aidat ve Finans (`finance`) ile Dosya Deposu (`drive_storage`; Belgeler 084'ten beri onun parçasıdır, ayrı `documents` modülü yoktur) modül kataloğunda TEMEL modüldür (`core: true`, `server/src/modules/catalog.js`; AGENTS.md Kural 25): talep gerekmeden her sitede açıktır ve kapatılamaz, yani finans ve belge verisi her sitede işlenebilir. Aynısı 2026-10-28'den beri Anket ve Oylama, Komşu Panosu, Ekipman ve Bakım ve Faaliyet Raporu için de geçerlidir; bu dört modülün ve Drive bağlantısının veri kayıtları 2026-10-29 itibarıyla Bölüm H'dedir (V80-V84; avukat listesi madde 41). Toplu yükleme çekirdek `people` modülündedir (`PLATFORM_TOPLU_ISLEMLER.md` "Modül anahtarı yoktur"), telefon bildirimi sunucuda `PUSH_ENABLED=0` ile kapalı başlar (`push_config.js:4`). Rol: telefon bildirimi cihaz kayıtları Güde'nin hesap/platform verisi olarak kabul edildi (karar avukat listesinde madde 34); diğerleri SY verisidir, Güde veri işleyendir.

### V60 Telefon bildirimi cihaz kaydı (`push_devices`)
- **Alanlar:** `user_code`, `install_id` (16-64 karakter rastgele UUID), `platform` (android/ios), `fcm_token` (FCM kayıt jetonu, 20-2048 karakter), `app_version` (≤32), `notifications_enabled` (işletim sistemi izni), `failure_count`, `last_error_code`, `created_at`, `last_seen_at`, `last_success_at`.
- **Kaynak:** `server/migrations/041_push.sql:13-36`; kayıt `PUT /app/push/devices` (`push_routes.js:3`; `push_devices.js:140-163`: aynı jeton tek satırda, kullanıcı başına en çok 10 cihaz, en eski düşer). İstemci: `lib/services/push_service.dart:1-28`.
- **Amaç:** uygulama kapalıyken yeni duyuruyu bildirmek.
- **Rıza/aydınlatma:** kayıt yalnızca kullanıcı o cihazda "Bu cihazda aç" / "Telefon bildirimi" / Duyurular'daki "Aç" ile açıkça açarsa yapılır, izin açma anında istenir, açılışta sorulmaz (`push_service.dart:5-9`; `push_soft_prompt_card.dart:18,38-41`; `push_prefs_panel.dart:29-32`). Android 12 ve öncesinde izin varsayılan açık olsa da kendiliğinden kayıt yoktur (`push_service.dart:7-8`). Duyuru alamayan roller (süper kullanıcı, bireysel kullanıcı) için kayıt tutulmaz (`push_service.dart:380-383`). Soft istem metni Google'a aktarımdan söz etmez (`push_soft_prompt_card.dart:39-41`) → avukat listesi madde 34.
- **Hukuki sebep önerisi:** açık rıza (m.5/1) veya m.5/2-c/f: karar avukatın (madde 34).
- **Kim görür:** sunucu; hesap sahibi kendi cihaz listesini (platform, sürüm, tarihler) görür; kullanıcı dışa aktarmasında platform, `app_version`, izin durumu ve tarihler yer alır, jeton ve kurulum kimliği hariçtir (`push_devices.js:395-421`; `account_export_service.js:54`).
- **Alıcı:** Google (FCM), iOS'ta ek olarak Apple (bkz. Bölüm E, V63).
- **Saklama:** çıkışta ve cihaz kaldırılınca silinir; 60 gün hareketsiz kayıt silinir; ≥5 hata ve 30 gündür başarı yoksa silinir; kimliksizleştirilmiş hesaba kalan satır süpürülür (`push_common.js:72-76`; `push_worker.js:694-708`; bakım saatliktir: `push_worker.js:75` ve `PUSH_ENABLED` kapalıyken de çalışır: `push_worker.js:759-775`).
- **Hesap silmede (1):** aynı işlemde silinir (`account_deletion_service.js:547-548`; `push_devices.js:370-389`); önizleme metni "Telefon bildirimi için kayıtlı cihazlarınız…" der (`account_deletion_service.js:313-315`). **(2):** `ON DELETE CASCADE` (`041_push.sql:15`).
- **Hesap silme önizlemesi:** `server/legal/account_deletion.md` §2 ile uyumlu; önizleme koşullu satır olarak yalnızca cihaz kaydı varken çıkar.

### V61 Bildirim kuyruğu (`push_outbox`)
- **Alanlar:** `kind` (yalnız `announcement`), `site_code`, `announcement_id`, `user_code` (yabancı anahtar yok), `importance` (normal/urgent), `status` (pending/sent/failed/skipped/expired), `skip_reason`, `attempts`, `not_before`, `expires_at`, `claimed_at`, `sent_device_count`, `last_error_code`, `created_at`, `sent_at`. **Bildirim metni saklanmaz** (gönderim anında kurulur).
- **Kaynak:** `041_push.sql:41-75`; yazım duyuru yayın işleminde (`push_outbox.js:24-39,59-85`); PUSH_ENABLED kapalıyken veya hizmet hesabı yüklenemediyse hiç satır yazılmaz (`push_outbox.js:60-62`).
- **Saklama:** biten satırlar 14 gün; süresi geçen bekleyenler `expired`; silinmiş/kimliksizleşmiş kullanıcı satırları saatlik süpürülür (`push_outbox.js:107-135`).
- **Hesap silmede (1):** silinir (`push_devices.js:383-387`). **(2):** `push_outbox.user_code`'da yabancı anahtar olmadığı için bakım süpürmesi siler (en geç ~1 saat).
- **Kişisel veri notu:** hangi kullanıcıya hangi duyurunun hangi sonuçla gönderildiği bir kullanım izidir; 14 gün sonra silinir.

### V62 Bildirim tercihleri (`notification_preferences` eklemeleri)
- **Alanlar:** `push_show_preview` (varsayılan FALSE), `push_quiet_enabled` (FALSE), `push_quiet_start` 1380, `push_quiet_end` 420 (Europe/Istanbul), `push_announcements` (TRUE); `email_finance_reminders` (TRUE).
- **Kaynak:** `041_push.sql:79-83`; `040_finance_4b.sql:1489`; `announcement_inbox.js:289-372`.
- **Not (UI açığı):** `email_finance_reminders` sunucu API'sinde var (`announcement_inbox.js:306-372`) ve hatırlatma kuyruğu bunu dikkate alır (`finance_reminder_queue.js:192`), ancak `lib/` altında bu tercih için bir ekran anahtarı bulunamadı; hatırlatma e-postasının altbilgisi hesaplı kullanıcıya "uygulamadaki Bildirim Tercihleri'ni kullanabilir" der (`finance_reminder_mail.js:76-77`) → avukat listesi madde 38 ve koordinatör notu.
- **Acil duyuru:** `urgent` bildirim `push_announcements` ve sessiz saatleri atlar; yalnızca cihaz kaydı/izin kapanırsa durur (`push_outbox.js:35`; `push_worker.js:200-216`; `push_prefs_panel.dart:33,541,563`).
- **Hesap silmede (1):** satır silinir (`account_deletion_service.js:545`).

### V63 FCM'e giden mesaj (Google/Apple alıcıları)
- **İçerik:** `notification.title` normal duyuruda site adı (≤40, yoksa "Site Yönetimi"), acil duyuruda "Acil duyuru"; `body` varsayılan "Yönetimden yeni bir duyuru var." / "{Site adı}: acil bir duyuru var. Ayrıntı için uygulamayı açın."; kullanıcı `push_show_preview` açtıysa gövde duyuru başlığıdır (≤80). `data`: `type`, `announcement_id`, `site_code`, `importance`. `collapse_key`/`apns-collapse-id` `ann-<id>`; iOS `thread-id` `site-<site_code>` (`push_message.js:4-9,52-92`). Finansal veya kişisel ayrıntı, tutar, ad, daire yoktur.
- **Günlük:** jeton ve mesaj günlüğe yazılmaz (`push_message.js:61-63`; `push_service.dart:28`).
- **Önizleme riski:** kullanıcı başlığı açarsa metin kilit ekranında görünür (`push_prefs_panel.dart:550-554` uyarı verir).

### V64 Belgeler (`documents`, `document_versions`, `announcement_attachments`, diskteki dosyalar)
- **Alanlar:** `documents`: `site_code`, `title` (≤120), `description` (≤1000), `category` (regulation/minutes/contract/notice/other), `audience` (residents/board/managers), hedef (site/blok/daire), `status` (pending/active/deleted), `download_count`, `created_by`, `deleted_by`, `deleted_at`; `document_versions`: `storage_key`, `display_name` (≤120), `mime_type`, `size_bytes`, `sha256`, `uploaded_by`; `announcement_attachments`: duyuru-belge bağı. Dosya içeriği diskte `DOCUMENTS_DIR/sites/<site_code>/<uuid>`.
- **İçerik riski:** serbest dosya; **T.C. kimlik no, IBAN, telefon, adres, ad içerebilir** (yükleme formunda zorunlu uyarı: `lib/ui/dialogs/document_upload_dialog.dart:39`; `PLATFORM_BELGELER.md` A11 satır 163). Tür: PDF, JPG, PNG, DOCX, XLSX (varsayılan; `DOCUMENTS_ALLOW_OFFICE`); ≤10 MiB dosya, site kotası 200 MiB varsayılan (`document_common.js:57-66`).
- **Kaynak:** `server/migrations/039_documents.sql:11-90`; `document_common.js:12-34`; `document_storage.js:34,53,183` (dizin 0700, dosya 0600); `document_service.js`.
- **Kim görür:** yazma yönetici/süper; kurul üyesi `board` ve `residents` kitlelerini salt okur, `managers` kitlesini görmez (`document_routes.js:10`; `document_service.js:158-169`); sakin kendi kitlesi ve hedefindeki `residents` belgelerini görür (`document_resident.js:81`); duyuruya ekli belgeyi duyurunun tüm alıcıları indirir, belgenin kendi hedefine bakılmaz (`PLATFORM_BELGELER.md` A12 satır 172; `document_resident.js:198-216`). Hesapsız kişi indiremez (`document_resident.js:6`). Yükleyen adı yalnız yöneticiye/süper kullanıcıya görünür (`document_service.js:213,270`). Kimin indirdiği kaydedilmez, yalnız sayaç (`document_resident.js:244`).
- **İndirme güvenliği:** `Content-Disposition: attachment`, `nosniff`, `Cache-Control: private, no-store`, CSP sandbox (`document_download.js:4-5,77-80`). Uygulama düzeyinde şifreleme yok (`document_*.js` içinde şifreleme kodu bulunmadı; `PLATFORM_BELGELER.md` A11 satır 165). Disk/veritabanı şifrelemesi DOĞRULANAMADI.
- **E-posta:** belge e-postaya eklenmez (`PLATFORM_BELGELER.md` A12 satır 174).
- **Amaç:** yönetmelik, tutanak, sözleşme gibi site belgelerini ilgili kitleye sunmak.
- **Hukuki sebep önerisi:** m.5/2-a, f (SY); belge içeriğindeki özel durumlar SY sorumluluğunda.
- **Saklama:** Site Yönetimi silince `deleted`; 30 gün (`DOCUMENTS_RETENTION_DAYS`, `document_common.js:58`) sonra bakım işi dosyayı ve satırı kalıcı siler (`document_maintenance.js:5,117`); "kalıcı sil" hemen siler (`document_routes.js:240`); yetim dosyalar 24 saat sonra süpürülür (`document_maintenance.js:6`). Belge için başka saklama süresi yoktur → avukat listesi madde 36.
- **Hesap silmede (1):** belge ve sürümler silinmez; `created_by`/`deleted_by`/`uploaded_by` kimliksizleştirilmiş hesaba bağlı kalır, yükleyen adı "Silinmiş Kullanıcı" olur (`account_deletion_service.js:7-8`); önizleme "Yüklediğiniz belgeler (n dosya sürümü) site yönetiminde kalır" der (`account_deletion_service.js:331-333`). **(2):** `ON DELETE SET NULL` (`039_documents.sql:27,31,73`).
- **Dışa aktarma:** dosya içeriği, depolama anahtarı, özet (hash), kitle / hedef ve sürüm notu hariç; **belgenin BAŞLIĞI ve durumu da dosyaya konmaz** (başlığı ve durumu site yöneticileri sonradan değiştirebilir ve başkasının yazdığı bilgi içerebilir). Yalnız hesabın yüklediği sürümlerin kayıt bilgisi `uploaded_documents` bölümündedir: dosya adı, tür (MIME), boyut, yükleme tarihi (`recorded_at`, `completed_at`), sürüm no, kategori, sürüm durumu, site kodu/adı ve belge numarası (sorgu `uploadedDocuments`: `account_export_service.js:219-230`; `excluded` açıklaması: `account_export_service.js:51`; eşleme: `:460`).
- **Yedek:** belge arşivi şifreli yedeklenir (V17 eki). Üretimde devrede olduğu DOĞRULANAMADI.

### V65 Gider belgeleri (`expense_documents`)
- **Alanlar:** `expense_id`, `storage_key`, `display_name` (≤120), `mime_type` (PDF/JPEG/PNG), `size_bytes`, `sha256`, `kind` (invoice/receipt/photo/other), `added_by`, `removed_at`, `removed_by`, `removal_reason` (≤200). Dosya belge deposunda (aynı dizin).
- **Kaynak:** `040_finance_4b.sql:273-308`; `finance_expense_documents.js:1-11,303-326`.
- **Kim görür:** yönetici/süper (yazma), kurul okuma (ilgili uçlar `finance_4b_routes.js`).
- **Kişisel veri riski:** fatura/fiş tedarikçi gerçek kişiyse onun adı, adresi, T.C. kimlik no'sunu içerebilir; gider ekranı "kimlik numarası ve IBAN gibi bilgileri karartın; fotoğraflar konum bilgisi içerebilir" uyarısı verir (`lib/ui/dialogs/finance_expense_dialog.dart:691`; `lib/services/expense_attachments.dart:14`).
- **Saklama:** gider belgesi KALICI SİLİNMEZ: kaldırma yalnız bağlantıyı keser (`removed_*`), dosya diskte kalır; kod yorumu bunu "KMK m.36" ile gerekçelendirir (`finance_expense_documents.js:6,303`; `finance_4b_*` sözleşme) → dayanak kodda yalnız yorum olarak vardır [AVUKAT DOĞRULASIN]. Süre yok. En çok 5 etkin belge/gider (`finance_expense_documents.js:5`).
- **Hesap silmede:** etkilenmez (V68 ile aynı).
- **Yedek:** V64 ile aynı belge arşivi. Yetim süpürmesi `document_versions ∪ expense_documents` bilir (`document_maintenance.js:6,170`).

### V66 Makbuzlar (`receipts`, `receipt_counters`, `receipt_print_events`)
- **Alanlar:** `receipts`: `site_code`, `receipt_year`, `receipt_no`, `kind` (collection/cancellation), `ledger_entry_id`, `cancels_receipt_id`, `apartment_id`, `amount_minor`, `paid_on`, `issued_on`, `issued_at`, `snapshot` (JSON), `snapshot_sha256`, `verification_code`, `template_version`, `cancel_reason_code`, `cancel_note` (≤200, serbest metin), `issued_by`. `snapshot`: sürüm, numara, tür, tarihler, tutar, para birimi, yöntem, **site adı, daire etiketi, `payer.name` (ödeyen olarak kayıtlı kişinin adı), `issuer.name` (makbuzu düzenleyen yöneticinin adı)**, doğrulama kodu; T.C. kimlik no, telefon, e-posta, adres, bakiye ve serbest açıklama yoktur (`finance_receipts.js:100-121,222-248`). `receipt_print_events`: `printed_by`, `printed_at`, `copy_number`.
- **Kaynak:** `040_finance_4b.sql:90-156`; `finance_receipts.js`.
- **Amaç:** tahsilatın belgelenmesi (borçlunun makbuz isteme hakkı: `docs/PLATFORM_FINANS_4B.md` TBK m.103 atfı, doğrulanmadı), uyuşmazlık ispatı.
- **Hukuki sebep önerisi:** m.5/2-a, ç, e.
- **Kim görür:** yönetici/süper ve kurul üyesi site makbuzlarını listeler (`finance_4b_routes.js:101-112`); sakin yalnızca kendi görebildiği dairelerin makbuzlarını (`finance_receipts.js:732-770`); `receipts/verify` numara+kodla tutar, tarih ve daire etiketi döndürür (`finance_receipts.js:607-627`). Kurul üyesi doğrulama ucunu kullanabilir, düzenleme/iptal/yazdırma yönetici işlemidir (`finance_4b_routes.js:12`).
- **Saklama:** UPDATE/DELETE engelli (yalnız site silinirse CASCADE; yalnız kullanıcı satırı silinirse `issued_by` NULL olabilir: `040_finance_4b.sql:485-509,811-813`); süre yok. Makbuz hatası ters makbuzla (cancellation) düzeltilir.
- **Hesap silmede (1):** snapshot'taki ödeyen adı ve düzenleyen adı **değişmez**, kimliksizleştirilmez (kasıtlı; `docs/PLATFORM_FINANS_4B.md` açık soru A7 bunu hukuki gerilim olarak işaretler; avukat listesi madde 39); önizleme "Makbuz ve tahsilat kayıtları … KMK … VUK … DEĞİŞTİRİLMEDEN saklanır" der (`account_deletion_service.js:334-336`). **(2):** `issued_by` NULL, snapshot'ta ad kalır.
- **Dışa aktarma:** yalnız makbuz özeti (numara, tür, durum, tutar, tarih, daire); ad, doğrulama kodu ve snapshot hariç (`account_export_service.js:52`).
- **Şablon metinleri:** mahsup, çekince ve "noter onaylı karar defteri/yasal defterlerin yerine geçmez" cümleleri sabit ve **taslak** (`RECEIPT_TEMPLATE.draft = true`) [AVUKAT DOĞRULASIN] (`finance_receipts.js:43-51`).

### V67 Gecikme tazminatı (`late_fee_runs`, `late_fee_run_lines`, `finance_settings`)
- **Alanlar:** `finance_settings`: `late_fee_enabled` (varsayılan FALSE), `late_fee_rate_bp` (0-500 = aylık %0-5; varsayılan 500), `late_fee_method` (`daily_30` | `daily_actual`), `late_fee_grace_days` (0-90), `late_fee_start_period`; `late_fee_runs`: dönem, parametreler, toplam, daire sayısı, muaf daire kimlikleri, `posted_by`, `voided_*`; `late_fee_run_lines`: `apartment_id`, `apartment_label`, tutar, gün esası, tepe borç, gün kırılımı (JSON), defter kalemi.
- **Kaynak:** `040_finance_4b.sql:7-88`; `finance_late_fee.js:4,295`; `finance_settings.js:6,31`.
- **Kapı:** `platform_settings` anahtarı `finance.legal_ok` (varsayılan KAPALI); kapalıyken tazminat ve hatırlatma AÇILAMAZ (409 `LEGAL_APPROVAL_REQUIRED`); bayrağı yalnız süper kullanıcı açar (`finance_4b_routes.js:492-503`; `PLATFORM_FINANS_4B.md` "Hukuk kapısı (Q2)" satır 327). Oran sunucuda 500 bp üstüne ayarlanamaz (`chk_finance_settings_rate`).
- **Hukuki dayanak (repo sözleşmesi):** KMK 634 m.20/2 "aylık yüzde beş" gecikme tazminatı; oran 5711/9 ile yüzde ondan yüzde beşe indi; 7579 sayılı Kanun (RG 22.05.2026) m.20'ye dokunmadı (`PLATFORM_FINANS_4B.md` satır 17). İkincil kaynakla doğrulandı: 5711 ile %5; 7579 sayılı Kanun RG 22.05.2026/33261. Resmî metne erişilemediği için gün esası, ek gün, faiz üstüne faiz ve yönetim planıyla oran değişikliği [AVUKAT DOĞRULASIN] (avukat listesi madde 37).
- **Kim görür:** yönetici/kurul (okuma); sakin kendi kaleminin açıklamasını görür (`/app/my-finance/entries/:entryId/late-fee`, `finance_4b_routes.js:454-461`). Kişisel veri dolaylı (daire etiketi + o dairenin sorumlu tarafı).
- **Saklama:** değişmez (`trg_late_fee_runs_guard` ve `trg_finance_immutable`), site silinince CASCADE.
- **Hesap silmede:** etkilenmez.

### V68 Gider, kategori, tedarikçi (`expenses`, `expense_voids`, `expense_categories`, `finance_suppliers`)
- **Alanlar:** `expenses`: kategori adı (anlık görüntü), tedarikçi adı (anlık görüntü), `description` (≤200), tutar, KDV, tarih, dönem, hesap, belge türü ve numarası, `created_by`; `expense_voids`: `reason` (≤200), `voided_by`; `finance_suppliers`: `name` (≤100), **`tax_id` (10-11 hane: vergi no veya T.C. kimlik no)**, `phone` (≤20), `note` (≤200), `is_active`, `created_by`.
- **Kaynak:** `040_finance_4b.sql:182-271`; `finance_expenses.js:1-7,192-207`.
- **Kim görür:** yönetici yazar; kurul okur ama tedarikçi listesinde `tax_id`, `phone`, `note` maskelenir (`finance_4b_routes.js:234`; `finance_expenses.js:207`). Denetim kaydına ad/açıklama/neden yazılmaz (`finance_expenses.js:6`).
- **Kişisel veri notu:** tedarikçi gerçek kişi ise (ör. usta, serbest meslek) ad, telefon ve T.C. kimlik no kişisel veridir; bu kişi sitenin kullanıcısı değildir ve aydınlatma SY'dedir.
- **Saklama:** gider silinmez, iptal (`expense_voids`) + ayna hareketle düzeltilir (`finance_expenses.js:4`); tedarikçi için **silme ucu yok**, yalnız `is_active=false`; kategori ve hesap için de silme ucu bulunamadı (`server/src` içinde `DELETE FROM finance_suppliers|expense_categories|finance_accounts` yok). Tedarikçi gerçek kişiyse silme/anonimleştirme talebi uygulama içinden karşılanamaz → avukat listesi madde 36 ve geliştirme listesi.
- **Hesap silmede:** etkilenmez (tedarikçi hesap sahibi değildir; `created_by` kimliksizleştirilmiş hesaba bağlı kalır).

### V69 Kasa/banka hesabı, hareket, virman, mutabakat (`finance_accounts`, `account_movements`, `account_transfers`, `account_reconciliations`)
- **Alanlar:** hesap `name` (≤60), `kind` (cash/bank), `note` (≤200), açılış bakiyesi; hareket: tür, tutar, tarih, `note` (≤200), `created_by`; virman `description` (≤200); mutabakat: ekstre bakiyesi, fark, `note`, `reconciled_by`.
- **Kaynak:** `040_finance_4b.sql:158-180,310-406`.
- **Not:** hesap numarası (IBAN) alanı yoktur; serbest metin alanlarına (`name`, `note`) yazılırsa kayıt altına girer.
- **Saklama:** hareketler değişmezdir; hesap silinmez (pasifleşir). **Hesap silmede:** etkilenmez.

### V70 Finans ayarları (`finance_settings`)
- V67'ye bakınız. Ek: `receipts_auto_issue` (varsayılan TRUE: her tahsilatta makbuz otomatik), `reminders_enabled` (varsayılan FALSE), `reminder_min_overdue_minor` (5000 = 50 TL), `reminder_min_days_overdue` (5), `reminder_min_interval_days` (14), `reminder_max_consecutive` (3), `updated_by` (`040_finance_4b.sql:7-36`).

### V71 Borç hatırlatma (`finance_reminder_runs`, `finance_reminder_items`, `finance_reminder_apartments`, `finance_reminder_exclusions`) ve e-posta
- **Alanlar:** `runs`: `tone` (friendly/standard), `note` (≤300), parametreler, sayılar, `created_by`; **`items` (kişi başına): `run_id`, `person_id`, `apartment_ids`, `with_amount`, `has_account`, `email` (yalnız gönderilene kadar), `email_hash` (tuzlu özet), `email_status` (pending/sent/failed/no_address/skipped_pref/duplicate/capped/resolved/cancelled), `email_attempts`, `sent_at`**; `apartments`: daire başına son hatırlatma zamanı; `exclusions`: muaf daireler ve `reason` (≤100).
- **E-posta içeriği:** sabit şablon, iki ton; konu "[Site] Ödeme hatırlatması" (tutar, ad, daire konuda yok); gövde ad kullanmaz ("Merhaba," / "Sayın site sakini,"), daire etiketini yazar; **tutar ve en eski vade tarihi yalnızca doğrulanmış gerçek hesap e-postasına** (`with_amount && account_kind='registered' && verified`) yazılır; yönetici notu ≤300 karakter düz metin ve bağlantı içeremez; altbilgide gönderen, "tanıtım iletisi değildir" ve abonelikten çık bağlantısı + RFC 8058 `List-Unsubscribe` (`finance_reminder_mail.js:1-7,36-100`; `finance_reminder_queue.js:315-326`). Abonelikten çıkış duyuru e-postalarıyla ortak bastırma listesine yazılır ("site duyuru ve borç hatırlatma e-postaları durdurulur": `finance_reminder_mail.js:77-78`).
- **Kapılar:** (1) çalıştırma oluşturma: `finance.legal_ok`, modül ve site `reminders_enabled` (varsayılan FALSE) (`finance_reminders.js:357`; `040_finance_4b.sql:15`); (2) gönderim anı: çalıştırma oluşturulduktan sonra bayrak, modül veya ayar kapanırsa satır `cancelled` olur ve adres silinir, denetime `finance.reminder.cancelled` yazılır (`finance_reminder_queue.js:209-252,286-289`; bu davranış kod okunduğu sırada vardı, S-4b ajanı çalışmaya devam ettiği için yayından önce yeniden doğrulanmalıdır). Önceki gözlem ("kuyruk anında yeniden denetlemiyor") bu kodla geçersizdir.
- **Saklama:** `email` gönderim/ vazgeçme sonrası NULL, bekleyen kalem 24 saatte `failed` + adres NULL; `email_hash` gönderimden 8 gün sonra NULL (`finance_reminder_queue.js:33-35,115-158`). Ancak **`finance_reminder_items` satırları (kişi no, daire kimlikleri, durum, gönderim zamanı) süresiz kalır**: temizleme işi bulunamadı (satırlar yalnız site silinirse CASCADE); bu bir "kişiye hatırlatma gönderildi" izidir → avukat listesi madde 38.
- **Alıcı:** SMTP sağlayıcısı (V12). Hatırlatma push ile gönderilmez (outbox türü yalnız `announcement`).
- **Kim görür:** yönetici/süper çalıştırma geçmişini; alıcı kendi aldığı hatırlatmaların geçmişini (tarih, ton, durum) kullanıcı dışa aktarmasında görür (`account_export_service.js:195-204`, `:53`).
- **Hesap silmede (1):** bekleyen kalemlerin adresi/özeti NULL, durum `resolved`; gönderilmiş kalemler kalır (`account_deletion_service.js:103-131,628`); önizleme "bekleyen aidat hatırlatma e-postalarının (n) kayıtlarındaki e-posta adresiniz silinir; bu hatırlatmalar gönderilmez" der (`:316-318`). **(2):** bu adım yok; adres kuyruk işçisince `resolved`/24 saat içinde temizlenir.

### V72 Toplu yükleme çalışma kaydı (`bulk_import_runs`)
- **Alanlar:** site, tür (apartments/people/vehicles), satır sayısı, `counts` (JSON sayılar), `created_by` (yönetici), parmak izi/anahtar. **Kişisel veri taşımaz; dosya ve ham satırlar saklanmaz.**
- **Kaynak:** `server/migrations/038_bulk_imports.sql:11-56`; `bulk_import_service.js:3-5`; `PLATFORM_TOPLU_ISLEMLER.md` madde 2 (satır 23).
- **Hesap silmede (1):** kimliksizleştirilmiş hesaba bağlı kalır; **(2):** `created_by` SET NULL (`038:47-50`). Kayıt silinmez (site silinirse CASCADE).

### V73 Toplu yükleme/dışa aktarma ile işlenen kişi verisi (akış)
- **Yükleme:** istemci dosyayı ayrıştırır, sunucuya JSON satırlar (≤5000) gider; sunucu her hücreyi doğrular, önizler ve onaydan sonra kişi, daire ilişkisi ve araç kayıtlarına yazar; hesap, davet e-postası, kapı erişimi ve rol verilmez. Yalnız yönetici/süper; kurul, görevli, sakin 403 (`PLATFORM_TOPLU_ISLEMLER.md` satır 18,101,173-180). Her yazma `audit_log`'a yönetici adıyla yazılır; ayrıntı `via: 'import'`, `run_id` ve alan değişimlerini içerir (`bulk_import_writer.js:32-41,89-93,188-192,233-237`).
- **Dışa aktarma:** kişi/daire/araç (≤20.000 satır) ve makbuz/finans dışa aktarmaları yalnız yönetici/süper; kurul 403; telefon `0 (555) …` biçiminde; `not` yalnız `include_notes=true`; yanıt `Cache-Control: no-store`; her dışa aktarma `export` eylemiyle denetlenir (tür, satır sayısı, biçim, süzgeç adları; arama metni yok) (`PLATFORM_TOPLU_ISLEMLER.md` satır 153-164; `bulk_import_export.js:415-437`; `finance_export_tables.js:287-297`). Dosya yöneticinin cihazında oluşur ve sonrası yöneticinin sorumluluğundadır.
- **Hukuki not:** dışa aktarılan dosya kontrolsüz bir kopyadır (paylaşım hedefi bizim denetimimizde değil); ölçülülük gerekçesiyle kurul dışa aktaramaz (`PLATFORM_TOPLU_ISLEMLER.md` karar 12). Toplu yüklenen hesapsız kişilere aydınlatma SY'dedir (madde 12 ile aynı boşluk).

### V74 Kullanıcının veri dışa aktarması (`/me/account-export`) kapsam eklemeleri
- Yeni bölümler: kayıtlı telefon bildirimi cihazları (jeton/kurulum kimliği hariç), `uploaded_documents` (yalnız kayıt bilgisi: dosya adı, tür, boyut, tarih, sürüm no, kategori; belge BAŞLIĞI yok), `receipts` (yalnız makbuz özeti), `finance_reminders_received` (yalnız tarih, ton, durum); bildirim tercihleri `email_finance_reminders` ve `push_*` alanlarını içerir (`account_export_service.js:43-55,176-204,298-299,361,423`). `excluded` bölümü neden hariç tutulduğunu yazar.

### V75 Sunucuya ait olmayan ama P1 kapsamında oluşan veriler (özet)
- FCM jetonu Google/Firebase sistemlerinde, iOS'ta APNs'te de bulunur (saklama süresi ve silme davranışı DOĞRULANAMADI). Telefondaki Firebase bileşeninin kendi deposu (jeton, Installations kimliği) uygulama tarafından yönetilmez. Dışa aktarma dosyaları ve paylaşılan kopyalar (V51 eki). Belge/makbuz PDF'leri istemcide üretilir ve paylaşılır (`pdf_finance_service.dart`; sunucuda PDF yok: `PLATFORM_FINANS_4B.md` Q5).

---

## H. Modül birleşimi ve karşılaştırma programı eki (2026-10-29): V80-V94

**Okuma kılavuzu.** Bu bölümdeki her kayıt, migration dosyası (tablo ve sütun adları), hizmet kodu ve ilgili `docs/PLATFORM_*.md` sözleşmesi okunarak yazıldı; kodda doğrulanamayan her şey "DOĞRULANAMADI" ile işaretlidir. Rol: aksi yazılmadıkça kayıtlar SY verisidir, Güde veri işleyendir (V90 ve V91 istisnadır). Hukuki sebep ve saklama sütunları öneridir; "Mevcut davranış" kodda fiilen olandır. Saklama önerisi mali kayıtlarda `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md` bölüm 1'e bağlanır (10 yıl, `retention.finance_days`, otomatik silme KAPALI); taslakta satırı olmayan kayıtlar için süre `[AVUKAT]` bırakıldı.

**"Hesap silmede" satırlarının dayanağı.** (1) kullanıcının uygulamadan silmesi; (2) süper kullanıcının `DELETE /admin/users/:id` ile kalıcı silmesi (`admin_routes.js` bu bölümdeki tablolara özel kod içermez, yani (2) için geçerli olan yabancı anahtar eylemidir). (1) için dayanak iki yerden okunur: `server/scripts/qa_platform_pg.mjs` içindeki "FK politika katalogu" (`users`'a bağlanan HER yabancı anahtar için karar; `POLICY` nesnesi, A6 kontrolü) ve `server/src/modules/account_deletion_service.js` ile `account_export_service.js` içinde ilgili modülün bulunup bulunmadığı (grep ile doğrulandı: yalnız anket için kod vardır; drive, komşu panosu, ekipman, faaliyet raporu, iade, devir, geri bildirim, deneme kodu için YOKTUR). "Tombstone" = kullanıcı satırı silinmez, kimliksizleştirilir (ad "Silinmiş Kullanıcı") ve bu tablolardaki `*_by` / `user_code` sütunları o satıra bağlı kalır; yabancı anahtarın `SET NULL` eylemi ancak satır fiziksel silinirse (yol 2) çalışır. **Kullanıcı veri dışa aktarması** (`/me/account-export`) bu bölümde yalnız anket oylarını içerir (`survey_votes_cast`); diğer kayıtlar dışa aktarmada YOKTUR.

### V80 Anket ve oylama (`surveys`, `survey_votes`)
- **Alanlar:** `surveys`: `site_code`, `title` (≤120), `question` (≤1000), `options` (JSON, 2-10 seçenek, her biri ≤80), `status` (draft, open, closed), hedef (`target_type` site/blocks/apartments, `target_block_ids`, `target_apartment_ids`), `anonymous` (varsayılan TRUE), `one_vote_per_apartment`, `closes_at`, `opened_at`, `closed_at`, `created_by`; `survey_votes`: `survey_id`, `user_code`, `apartment_id`, `option_index`, `voted_at`.
- **Kaynak:** `server/migrations/044_survey.sql:12-38,60-68`; sözleşme `docs/PLATFORM_ANKET.md`; oy yazımı `server/src/modules/survey_resident.js:159`; oy kuralı `survey_common.js:307-317`. Temel modül, her sitede açık (`082_more_core_modules.sql`).
- **"Anonim" sözünün sınırı (kodda doğrulandı):** `anonymous` yalnız GÖSTERİMİ sınırlar. Oy satırına `user_code` her ankette yazılır (`survey_resident.js:159`; tekil dizin `uq_survey_votes_user`, `044:88`) ve `apartment_id` her oyda yazılır (kullanıcının hedefteki en küçük numaralı aktif dairesi: `survey_common.js:314`, `one_vote_per_apartment` kapalı olsa bile). Anonim ankette "oy verenler" ucu 409 döner (`survey_service.js:206-208`); veritabanına erişen kişi kim-ne oy verdiğini görebilir. Aydınlatma ve arayüz metninde "gizli oy" benzeri söz kullanılmamalıdır (avukat listesi madde 41-c).
- **Amaç:** site kararlarına sakin görüşü almak.
- **Hukuki sebep önerisi:** m.5/2-a, f (SY).
- **Kim görür:** yönetici ve süper kullanıcı anket, sayımlar ve (yalnız `anonymous=false` ise) oy verenlerin kodu, adı, daire etiketi ve seçeneği; kurul üyesi anket ve sayımları görür, oy verenleri GÖREMEZ; sakin yalnız hedef kitlesinde olduğu açık/kapalı anketi, kendi oyunu ve (oy verdikten ya da kapandıktan sonra) sayımları görür; taslak sakine ASLA görünmez (`PLATFORM_ANKET.md` "Kurallar").
- **Saklama:** otomatik silme yok; yalnız taslak anket silinebilir (`survey_service.js:385`). Açık/kapalı anket ve oylar yalnız site silinince CASCADE ile gider. Öneri: kapanıştan sonra `[AVUKAT]` süre (saklama taslağında satırı yok).
- **Hesap silmede (1):** oylar SİLİNMEZ; `survey_votes.user_code` NULL yapılır, açtığı anketlerde `surveys.created_by` NULL yapılır (`survey_service.js:408-416`; `account_deletion_service.js:730-734`); önizleme "oylar kalır" notunu verir (`survey_common.js` `surveyVotesKeepNote`). **Dikkat:** `apartment_id` KALIR; tek kişilik dairede "bu daire şu seçeneğe oy verdi" bilgisi hesap silinse de dairenin sakin geçmişiyle eşleştirilebilir, yani silme tam anonimleştirme değildir. **(2):** `ON DELETE SET NULL` (`044:54,84`), `apartment_id` kalır.
- **Dışa aktarma:** yalnız kullanıcının kendi oyları (`survey_title`, `option_text`, `voted_at`; `account_export_service.js:294-296,546`).
- **Serbest metin riski:** başlık, soru ve seçenek metni (yönetici yazar).
- **Denetim:** `survey.created|updated|opened|closed|deleted`; başlık, soru, seçenek ve oy içeriği yazılmaz, oy için denetim satırı yoktur (`survey_resident.js:158`).

### V81 Komşu panosu (`neighbor_posts`, `neighbor_post_reports`)
- **Alanlar:** `neighbor_posts`: `site_code`, `author_user_code`, `title` (3-120), `body` (3-2000, serbest metin), `status` (pending, published, rejected, removed, withdrawn), `decision_note` (≤300), `decided_by`, `decided_at`, `created_at`; `neighbor_post_reports`: `post_id`, `reporter_user_code`, `reason` (1-200, serbest metin), `created_at`; kişi başına ilan başına tek şikâyet (`uq_neighbor_post_reports_once`).
- **Kaynak:** `server/migrations/064_neighbor_board.sql:7-22,28-35`; sözleşme `docs/PLATFORM_KOMSU_PANOSU.md`; ilan yazımı `neighbor_board_routes.js:180`, şikâyet `:204`. Temel modül, her sitede açık (`082`).
- **Amaç:** sakinlerin birbirine ilan ve duyuru vermesi, yönetici onayıyla.
- **Hukuki sebep önerisi:** m.5/2-f (SY); yayın kararı ve içerik sorumluluğu için avukat sorusu (avukat listesi madde 41-b).
- **Kim görür:** sitenin onaylı sakinleri yayındaki ilanları yazar adı "Ad S." biçiminde (ad ve soyad baş harfi) görür ve kendi ilanlarını (bekleyen, reddedilen, kaldırılan) durum ve kararla görür (`neighbor_board_routes.js:89-93`); yönetici ve süper kullanıcı tüm ilanları ve şikâyet gerekçelerini görür (`:268`); kurul ve görevli 403 (`PLATFORM_KOMSU_PANOSU.md` "Uçlar"). Şikâyet eden komşuya gösterilmez.
- **Saklama:** silme ucu ve temizlik işi yok (kodda `DELETE FROM neighbor_posts` yok); yazar geri çekse bile satır `withdrawn` olarak kalır. Yalnız site silinince CASCADE. Öneri: `[AVUKAT]` süre (saklama taslağında satırı yok).
- **Hesap silmede (1):** kullanıcının yazdığı İLANLAR silinir (kapanış kararı, KVKK; `account_neighbor_cleanup.js`, `account_deletion_service.js` adım 13; şikâyet kayıtları CASCADE ile ilanla gider); silme işlem izine (`audit_log`, eylem `neighbor_board.posts_deleted_account_closed`) site başına yalnız sayı, durum dağılımı ve neden yazılır (başlık, gövde, ad YOK) ve `account.deleted` özetinde `neighbor_posts_deleted` sayısı bulunur. Kullanıcının BAŞKA ilanlara yaptığı şikâyetler KALIR (FK katalogu: `neighbor_post_reports.reporter_user_code` "SAKLANIR - adli saklama kararı 2026-10-27", `qa_platform_pg.mjs`); `decided_by` TOMBSTONE. Önizleme "Komşu panosundaki ilanlarınız (N) silinir." satırını gösterir. **(2):** `author_user_code`, `reporter_user_code`, `decided_by` `ON DELETE SET NULL` (`064:10,15,31`).
- **Serbest metin riski:** ilan metni ad, telefon, adres içerebilir; şikâyet gerekçesi üçüncü kişiyi anabilir.
- **Denetim:** onay, ret, kaldırma ve şikâyet için `audit_log` satırı YAZILMAZ (`neighbor_board_routes.js` içinde `recordAudit` çağrısı yok; yalnız `actorFromAuthUser` içe aktarılır). `neighbor_board.` öneki yönetici işlem kayıtları kataloğunda tanımlı olsa da (`site_audit_log_catalog.js`) bu önekle kayıt oluşmaz; kararı veren yalnız `neighbor_posts.decided_by` / `decided_at` ile izlenir. Başlık ve metin günlüğe yazılmaz (`PLATFORM_KOMSU_PANOSU.md` "Kurallar").

### V82 Ekipman, bakım ve teklifler (`equipment_*`; ek: `work_items.equipment_id`)
- **Alanlar:** `equipment_items`: `kind`, `name`, `location`, `vendor_id` (firma kaydı, `contract_vendors` 049), `serial_no`, `installed_on`, `note` (≤1000), `is_active`, `created_by`; `equipment_plans`: `title`, `interval_months`, `legal`, `next_due`, `last_done`; `equipment_maintenance_logs`: `done_on`, `vendor_name` (≤120), `cost_kurus`, `expense_id`, `note` (≤1000), `created_by`; `equipment_expense_links` (gider-ekipman bağı); `equipment_quotes`: `topic`, `vendor_name`, `amount_kurus`, `valid_until`, `document_note` (≤300), `equipment_id`, `status`, `accepted_as`, `expense_id`, `contract_id`, `created_by`; 098: `delivery_days`, `note` (≤500), `vat_included`; 099: `revision_no`, `previous_id`, `revision_reason` (3-300). Migration 096: `work_items.equipment_id` (iş kaydını ekipmana bağlar) ve `work_item_attachments.phase` (before/after fotoğraf etiketi).
- **Kaynak:** `server/migrations/068_equipment.sql:5-85` (tablolar), `098_equipment_quote_compare.sql:7-9`, `099_equipment_quote_revisions.sql:11-13`, `096_work_equipment_link.sql:9,22`; sözleşme `docs/PLATFORM_EKIPMAN.md`; ekleme sorguları `equipment_service.js:203,292,352,384,633,744`. Temel modül (`082`).
- **Amaç:** demirbaş, bakım ve yasal kontrol takibi, teklif karşılaştırma.
- **Hukuki sebep önerisi:** m.5/2-a, f (SY). Kişisel veri düşüktür: tablolarda kişi alanı yoktur; kişiye dönüşebilen yerler `vendor_name` (gerçek kişi usta olabilir) ve serbest `note` / `document_note` alanlarıdır.
- **Kim görür:** yönetici ve süper yazar; kurul ve görevli salt okur; sakin ve ilgisiz 403 (`PLATFORM_EKIPMAN.md` "Kurallar"). Ekipmana bağlı iş kaydı geçmişi, iş takibinin görünürlük kuralıyla gelir (talebi açanın kimliği ve telefonu bu uçta yoktur).
- **Saklama:** silme ucu yok: ekipman pasife alınır (`is_active`), bakım kaydı uygulamada yalnız eklenir (veritabanında ayrıca kilit yok); kabul edilmiş teklif tetikleyiciyle değiştirilemez ve silinemez (`trg_equipment_quotes_locked`, `099:71`). Yalnız site silinince CASCADE. Öneri: ticari kayıt niteliğindeki teklif ve bakım için `[AVUKAT]` süre (saklama taslağında satırı yok).
- **Hesap silmede (1):** akış bu tablolara dokunmaz; `created_by` TOMBSTONE (FK katalogu: `equipment_items`, `equipment_maintenance_logs`, `equipment_quotes`). **(2):** `created_by` `ON DELETE SET NULL` (`068`).
- **Denetim:** `equipment.`, `quote.updated|revised|accepted` yalnız alan adlarını ve tutarı taşır; kapsam, not ve gerekçe metni günlüğe yazılmaz (`PLATFORM_EKIPMAN.md` satır 40).

### V83 Faaliyet raporu (`annual_reports`)
- **Alanlar:** `site_code`, `year`, `edits` (JSON; bölüm başına yönetici metni, ≤4000 karakter), `growth_bp`, `updated_by`, `created_at`, `updated_at`; (site, yıl) tekil.
- **Kaynak:** `server/migrations/069_annual_report.sql:6-19`; `server/src/modules/annual_report_service.js:17,294-299`; sözleşme `docs/PLATFORM_FAALIYET_RAPORU.md`. Temel modül (`082`).
- **Amaç:** yıllık faaliyet raporu taslağı ve PDF.
- **Hukuki sebep önerisi:** m.5/2-a (SY).
- **Kim görür:** yönetici ve süper yazar, kurul salt okur; sakin ve görevli yok. Rapor bölümleri sunucuda saklanmaz; her okumada diğer modül kayıtlarından (defter, gider, iş kaydı, sözleşme, kesin karar, duyuru) hesaplanır ve yalnız yönetici düzenlemesi saklanır (`PLATFORM_FAALIYET_RAPORU.md` "Tablo"); PDF istemcide üretilir (`lib/services/pdf_annual_report_service.dart`).
- **Saklama:** otomatik silme yok; yeniden kaydedince üzerine yazılır. Yalnız site silinince CASCADE. Öneri: `[AVUKAT]` süre (saklama taslağında satırı yok).
- **Hesap silmede (1):** `updated_by` TOMBSTONE (FK katalogu `annual_reports.updated_by`); akış tabloya dokunmaz. **(2):** `ON DELETE SET NULL` (`069:12`).
- **Serbest metin riski:** bölüm metinleri yönetici yazısıdır, kişi adı içerebilir. Denetim: `annual_report.save` (yalnız yıl ve bölüm sayısı).

### V84 Dosya deposu: Google Drive bağlantısı (`site_drive_connections`, `drive_oauth_states`, `drive_files`, `drive_pending_uploads`)
- **Alanlar:** `site_drive_connections`: `site_code` (PK), `status` (connected, error, disconnected), `account_email` (bağlanan Google hesabının e-postası; yöneticinin kişisel Gmail'i olabilir), `refresh_token_enc` (yenileme belirteci, AES-256-GCM, anahtar `.env` `DRIVE_TOKEN_KEY`), `root_folder_id`, `folder_ids`, `connected_by`, `connected_at`, `last_ok_at`, `last_error`; `drive_oauth_states`: `state_hash` (özet), `site_code`, `user_code`, `expires_at` (10 dk); `drive_files`: `kind` (sozlesme, su, isi, elektrik, teklif, dekont, gider, belge), `folder_name`, `name` (dosya adı daire etiketi ve tarih taşıyabilir: `IS-123_AB_D13_201026`), `mime_type`, `size_bytes`, `sha256`, `drive_file_id`, `status` (pending, stored), `uploaded_by`, `stored_at`, 097: `source_type` / `source_id` (dosyanın bağlı olduğu iş kaydı, sayaç okuması, gider, dekont bildirimi, sözleşme, teklif, belge, ekipman); `drive_pending_uploads`: `storage_path` (sunucu diskindeki geçici dosya yolu), `attempts`, `next_attempt_at`, `expires_at`, `last_error`.
- **Dosya içeriği:** Google Drive'da, sitenin kendi hesabında (`drive.file` kapsamı). Bağlantı kopukken ya da gönderilemeyen dosya sunucuda `DRIVE_PENDING_DIR` (varsayılan `~/kapi-drive-pending`) altında dosya izni 0600 ile bekler (`drive_service.js:68,314`); site başına 100 MiB sınır (`drive_common.js:11-16`).
- **Kaynak:** `server/migrations/060_drive_storage.sql:7-60` (tablolar), `097_drive_file_source_link.sql:7-8`, `084_documents_into_drive_storage.sql` (Belgeler modülü Dosya Deposu'na katıldı; `documents` tabloları ve diskteki belge dosyaları DEĞİŞMEZ); `drive_service.js:224-232,238-254`; `drive_client.js:6-10`; sözleşme `docs/PLATFORM_DRIVE_DEPOLAMA.md` (D1). Temel modül (`082`). Bugün Drive'a yazan çağıranlar: yönetici yükleme ucu (`POST /manager/sites/:siteCode/drive/files`) ve sayaç okuma fotoğrafı (`metering_field_routes.js:9,90-96`); belgeler (V64) ve iş takibi fotoğrafları hâlâ sunucu diskindedir (`grep` ile `driveService` yalnız bu iki dosyada geçer).
- **Amaç:** dosya alanını sitenin kendi hesabına yüklemek.
- **Hukuki sebep önerisi:** m.5/2-a, f (SY); yurt dışı aktarım için m.9 yolu `[AVUKAT]` (V84 notu Bölüm E'de).
- **Kim görür:** durum, dosya listesi ve indirme yalnız site yöneticisi ve süper kullanıcıdadır (`resolveManagedSite`, `drive_routes.js`); durum ekranında bağlı Google hesabının e-postası görünür (`drive_service.js:166`). İndirme sunucudan geçer, `Content-Disposition: attachment` ve `nosniff` ile (`drive_routes.js:135-141`). Kurul ve sakin Drive uçlarına erişemez.
- **Saklama:** bekleyen dosya SÜRE DOLDU DİYE SİLİNMEZ (karar K6): Drive teyidine kadar sunucuda kalır, 7 günü aşınca yalnız uyarı çıkar (`drive_common.js:11-17`, `driveConfirmed`). `drive_oauth_states` süresi dolanlar sonraki bağlanma girişiminde silinir (`drive_service.js:186`). `drive_files` satırları silinmez; tek istisna, bekleme alanı dolduğu için reddedilen YENİ yüklemenin kendi `pending` satırı (`drive_service.js:301`) ve beklenmedik hatada o yüklemenin satırıdır (`:365`). **Sunucu Drive'daki dosyayı hiçbir koşulda silmez** (`drive_client.js` işlemleri: onay adresi, kod değişimi, belirteç yenileme ve iptal, hesap e-postası, klasör, yükleme, indirme; silme yok). Bağlantı kesilince belirteç Google'da iptal edilir ve `refresh_token_enc` NULL yapılır; dosyalar sitenin Drive'ında kalır (`drive_service.js:238-254`). Site silinince dört tablo CASCADE; Drive'daki dosyalar KALIR. Öneri: dosya türüne göre V64 / V65 ve mali kayıt süreleri; bağlantı için `[AVUKAT]`.
- **Hesap silmede (1):** `drive_files.uploaded_by` ve `site_drive_connections.connected_by` TOMBSTONE (FK katalogu); akış bu tablolara dokunmaz. `audit_log` içindeki `drive.connected` satırı bağlanan Google e-postasını `details.account_email` olarak taşır (`drive_service.js:232`) ve V08 gereği silinmez. **(2):** iki sütun `ON DELETE SET NULL`; `drive_oauth_states.user_code` yabancı anahtarsızdır.
- **Yedek:** `deploy/ops/backup_db.sh` `DRIVE_PENDING_DIR` dizinini içermez (`pending` / `kapi-drive` grep ile bulunmadı); veritabanı dökümü `refresh_token_enc` şifreli değerini taşır, anahtar `.env` yedeğindedir (V17). Drive içeriği bizim yedek döngümüzün dışındadır, sitenin Google hesabındadır.
- **DOĞRULANAMADI:** üretimde `DRIVE_*` değişkenlerinin tanımlı olup olmadığı ve herhangi bir sitenin Drive'ı bağlayıp bağlamadığı (repoda görülmez); yapılandırma yoksa uçlar `503 DRIVE_NOT_CONFIGURED` döner.

### V85 Kart ödemesi ayarı (`payment_provider_settings`; Aidat ve Finans'ın içinde)
- **Alanlar:** `site_code`, `provider` (iyzico, paytr), `commission_info` (≤300, serbest metin), `updated_by` (yabancı anahtarsız), `updated_at`; (site, sağlayıcı) tekil.
- **Kaynak:** `server/migrations/065_device_integrations.sql:4-14`; `083_card_payments_into_finance.sql` (ayrı `card_payments` modülü kaldırıldı; yalnız bekleyen modül talepleri "onaylandı" yapıldı, ayarlar DEĞİŞMEZ); sözleşme `docs/PLATFORM_ODEME_KAMERA.md` "Kart ödemesi". Kapısı `finance` temel modülüdür.
- **Kapsam sınırı (doğrulandı):** sağlayıcı bağdaştırıcıları boş ve devre dışıdır (`status: soon`), tahsilat YAPILMAZ ve `finance_parties.postPayment` çağrılmaz (`PLATFORM_ODEME_KAMERA.md`); `server/src` ve `lib` altında kart numarası, son kullanma, CVV/CVC alanı bulunmaz (grep). Defter `source_kind` listesinde `card` değeri tanımlıdır (`finance_parties.js:48`) ancak bugün onu yazan bir akış yoktur.
- **Kim görür:** yönetici ve süper yazar, kurul salt okur, diğerleri 403.
- **Saklama:** otomatik silme yok; site silinince CASCADE (`065`). **Hesap silmede:** etkilenmez (kullanıcı yabancı anahtarı yok).
- **Not:** kart sağlayıcısı devreye alınırsa (iyzico / PayTR) yeni bir üçüncü taraf ve ayrı kayıt gerekir; bu satır o zaman yeniden yazılmalıdır.

### V86 Alacak iadesi (`finance_refunds`, `finance_refund_counters`; ek: `account_movements.refund_id`)
- **Alanlar:** `finance_refunds`: `site_code`, `apartment_id`, `account_party` (owner/tenant), `amount_minor`, `status` (requested, approved, rejected, cancelled, reversed), `requested_by_kind` (resident/manager), `requested_by`, `requested_at`, `note` (≤200), `resolved_by`, `resolved_at`, `reject_reason` (≤200), `pay_account_id`, `pay_date`, `pay_method` (cash, transfer, cheque), `ledger_entry_id`, makbuz alanları (`receipt_year`, `receipt_no`, `receipt_issued_on`, `receipt_snapshot` JSON, `receipt_sha256`, `receipt_code`), `reversed_by`, `reversed_at`, `reversal_reason` (≤200), `reversal_ledger_entry_id`, anahtar alanları; `finance_refund_counters` (site, yıl, son no). Defter satırı `ledger_entries.source_kind='refund'`; hesap hareketi `account_movements.kind='refund'`.
- **Makbuz anlık görüntüsü:** site adı, daire etiketi, **alacaklı kişinin adı** (`payee.name`), ödeme yapılan hesabın adı, **iadeyi onaylayan yöneticinin adı** (`issuer.name`), tutar, tarih, doğrulama kodu; T.C. kimlik no, telefon, e-posta, adres, bakiye ve serbest not YOKTUR (`finance_refunds.js:145-162`). Alacaklı adı dairenin o hesabındaki ilk güncel kişiden seçilir, `r.id` sırasıyla (`:476-486`); çoklu malikte bu hesap muhatabına göre değil en eski malik kaydına göre seçilir (doğrulanmış gözlem, V89).
- **Kaynak:** `server/migrations/088_finance_refunds.sql:78-137,138-145,264`; `finance_refunds.js`; sözleşme `docs/PLATFORM_FINANS.md` "Alacak iadesi". Modül kapısı `finance` (temel modül).
- **Amaç:** fazla ödemenin sakin isterse yönetici onayıyla iadesi ve belgelenmesi.
- **Hukuki sebep önerisi:** m.5/2-a, ç, e (V35 ile aynı).
- **Kim görür:** sakin yalnız kendi hesabı için talep açar ve kendi talebini görür; yönetici ve süper yazar, kurul adsız okur, görevli ve sakin yönetim uçlarında 403 (`PLATFORM_FINANS.md` "Alacak iadesi" Uçlar). Sakin onayda bildirim alır.
- **Saklama:** durum makinesi tetikleyicisi (`trg_finance_refunds_guard`, `088`) çekirdek sütunların değişmesini ve satırın silinmesini engeller (yalnız üst `sites` satırı artık yoksa silinir); makbuz sayacı da değişmezdir. Öneri: mali kayıtlar 10 yıl (`retention.finance_days`, taslak; otomatik silme kapalı).
- **Hesap silmede (1):** akış bu tabloya dokunmaz; `requested_by`, `resolved_by`, `reversed_by` TOMBSTONE (FK katalogu), makbuz anlık görüntüsündeki alacaklı ve düzenleyen adı DEĞİŞMEZ (V66 ile aynı gerilim, avukat listesi madde 39 ve 42). Kullanıcı dışa aktarmasında iade kaydı YOKTUR. **(2):** üç `*_by` sütunu `ON DELETE SET NULL`, anlık görüntüde ad kalır.
- **Serbest metin riski:** `note`, `reject_reason`, `reversal_reason`. Denetim: `finance.refund.approved|reversed` yalnız tutar, hesap ve makbuz no taşır; not ve ret nedeni yazılmaz.

### V87 Kiracı borcunun malike devri (`finance_liability_transfers`; ek: defter satırları, `apartment_notices`)
- **Alanlar:** `finance_liability_transfers`: `site_code`, `apartment_id`, `from_party`, `to_party` (tenant→owner; geri almada owner→tenant), `total_minor`, `item_count`, `reason` (1-200, serbest metin), `preview_hash`, `reverses_transfer_id`, `idempotency_key`, `request_fingerprint`, `created_by`, `created_at`. Devir defterde `ledger_entries.source_kind='liability_transfer'` ve `source_id` ile işaretli kalemlerle yazılır; uygulama içi bildirim `apartment_notices` (074) satırıdır: `user_code`, `kind` (`liability_transfer` | `tenant_exit_debt`), `message` (≤300; **borç tutarını** içerir, kişi adı içermez).
- **Kaynak:** `server/migrations/089_finance_liability_transfers.sql:27-48`; `finance_liability_service.js:353,391,460-473`; `finance_exit_notice.js:30-41,56-75`; `074_apartment_management.sql:46-57`; sözleşme `docs/PLATFORM_FINANS.md` "Kiracı borcunun malike devri" (K1 ve gecikmede öneri K17). Modül kapısı `finance`.
- **Gecikmede öneri (K17):** yeni saklanan alan YOKTUR. Aday listesi (`GET .../liability-transfer/candidates`) ve yönetici dikkat satırı (`tenant_debt_overdue_transfer`, `tenant_debt_pending_transfer`) her okumada defterden hesaplanır; kişi adı taşımaz.
- **Amaç:** kiracının ödemediği borcun yönetici onayıyla, izli ve geri alınabilir biçimde malik hesabına geçirilmesi; kiracı çıkışında malike önceden bilgi.
- **Hukuki sebep önerisi:** m.5/2-a, ç, e; metinler ve hukuki nitelendirme avukat onayı bekler (avukat listesi madde 42 ve 43).
- **Kim görür:** yönetici ve süper yazar, kurul adsız okur, görevli ve sakin yönetim uçlarında 403; sakin kendi ekstresinde kalemleri açık etiketle görür. **Bildirim alıcıları (kodda doğrulandı):** dairenin güncel, hesabı olan TÜM malik kayıtlarına gider (`finance_liability_service.js:460-473`, `finance_exit_notice.js:30-41`), hesap muhatabıyla sınırlı DEĞİLDİR. Bu, "ortak malik borç görmez" kararıyla (`PLATFORM_COKLU_MALIK.md` "Neden, ne") çelişir: ortak malik, kiracı borcunun TUTARINI bildirim metninden öğrenir. Ürün ve hukuk kararı gerekir `[AVUKAT DOĞRULASIN]`.
- **Saklama:** devir kaydı değişmezdir (`trg_finance_liability_transfers_immutable`, geri alma yeni satırdır), site silinince CASCADE. `apartment_notices` için temizlik işi yoktur (kodda `DELETE FROM apartment_notices` yok); satırlar süresiz kalır. Öneri: devir kaydı mali kayıt olarak 10 yıl (`retention.finance_days`); bildirim metni için `[AVUKAT]` süre.
- **Hesap silmede (1):** `finance_liability_transfers.created_by` TOMBSTONE; `apartment_notices.user_code` SAKLANIR (FK katalogu: "adli saklama kararı 2026-10-27"; bildirim tutarı içerir). **(2):** `created_by` `ON DELETE SET NULL`; `apartment_notices.user_code` kalıcı silmede CASCADE ile gider (katalog notu).
- **Serbest metin riski:** `reason`. Denetim: `finance.liability_transfer.created|reversed` ve `finance.tenant_exit.debt_notified` tutar, kalem sayısı ve daire taşır; neden metni yazılmaz.

### V88 Fon tahakkukunun dayanağı ve dağıtım tabanı (`fee_runs.decision_id`, `fee_runs.decision_reason`; `fee_definitions` dağıtımı `person_count`)
- **Alanlar:** `fee_runs.decision_id` (Karar Defteri'nde KESİN karar; aynı sitede), `fee_runs.decision_reason` (1-300 karakter, serbest metin; Karar Defteri kapalı sitede Fon borcu için zorunlu). `person_count` dağıtım tabanı (091) yeni kişi verisi SAKLAMAZ: kişi sayısı her hesapta `apartment_residencies.is_current` kayıtlarından sayılır (`PLATFORM_FINANS.md` satır 34).
- **Kaynak:** `server/migrations/090_finance_run_decision.sql:8` ve `091_fee_distribution_person_count.sql`; sözleşme `docs/PLATFORM_FINANS_KARAR_BAGI.md`; kural `finance_run_decision.js`. Karar Defteri kayıtları (`board_decisions`, 050) bu envanterde henüz yoktur.
- **Amaç:** Yatırım ve Demirbaş (Fon) Hesabı'na yazılan borcun hangi karara ya da gerekçeye dayandığının izlenmesi.
- **Hukuki sebep önerisi:** m.5/2-a, ç, e.
- **Kim görür:** yönetici ve kurul ekstrede karar ve gerekçeyi görür; **sakin Borcum ekranında** kalemin karar numarasını, (karar sakinlere açıksa) başlığını ve gerekçe metnini görür (`PLATFORM_FINANS_KARAR_BAGI.md` bölüm 2; yönetici serbest metninin sakine gösterilmesi bilinçli tek istisnadır, yazarken uyarı verilir).
- **Saklama:** `fee_runs` eklemelidir (`trg_fee_runs_append_only`), dayanak sonradan değişmez; 090 öncesi çalıştırmalar dayanaksız kalır (geri doldurma yok). Öneri: mali kayıt 10 yıl (`retention.finance_days`).
- **Hesap silmede:** etkilenmez (`fee_runs.posted_by` TOMBSTONE: V34/FK katalogu). **Serbest metin riski:** gerekçe metni kişi adı içerebilir ve sakinlere görünür. Denetim: `finance.run.posted` / `finance.charge.posted` `decision_id` ve `decision_reason_given: true` taşır, gerekçe metni yazılmaz.

### V89 Çoklu malik ve hesap muhatabı (`apartment_residencies.is_account_holder`)
- **Alanlar:** `apartment_residencies.is_account_holder` (BOOLEAN, varsayılan FALSE; dairede güncel malikler içinde TAM BİRİ muhatap). Bir dairede en çok 10 güncel malik kaydı (`OWNER_LIMIT`). Yeni malik için ya mevcut kişi seçilir ya da hesapsız CRM kişisi (ad, isteğe bağlı telefon ve e-posta) oluşturulur, yani V24'teki kişi verisi daire başına çoğalabilir.
- **Kaynak:** `server/migrations/104_apartment_multi_owner.sql:12` (sütun) ve tetikleyiciler; `server/src/modules/apartment_owners_service.js`; sözleşme `docs/PLATFORM_COKLU_MALIK.md`. Çekirdek özellik (modül kapısı yok).
- **Amaç:** hissedar ve eşlerin hepsinin malik olarak kayıtlı olması; borç, ekstre, makbuz ve hatırlatmanın tek muhataba gitmesi.
- **Hukuki sebep önerisi:** m.5/2-a, e, f (V25 ile aynı).
- **Kim görür:** yönetici ve süper yazar, kurul okur; malik listesi yanıtı ad, `has_account`, muhatap işareti ve taşınma tarihini verir, kullanıcı kodu, telefon ve e-posta içermez (`PLATFORM_COKLU_MALIK.md` "Sunucu uçları"). Diğer malikler malik yetkisi taşımaz ve "Borcum" göremez; ortak malik için `my_role: co_owner` döner. Bildirim istisnası V87'dedir.
- **Saklama:** ilişki kayıtları silinmez (V25). Muhatap ayrılırsa dairedeki EN ESKİ güncel malik otomatik muhatap olur ve denetime "Sistem" kaydı düşer (`apartment.account_holder_changed`, `auto: true`).
- **Hesap silmede (1):** V25 ile aynı (güncel ilişki biter, kayıt kalır); muhatap hesabı silinirse veritabanı tetikleyicisi başka maliki muhatap yapar, muhatapsız daire işlem sonunda reddedilir (`PLATFORM_COKLU_MALIK.md` "DB garantileri"). Denetim: `apartment.owner_added|owner_removed|account_holder_changed` yalnız kayıt kimliklerini taşır; adli kayıtta (`apartment_residency_log`, 075) `co_owner_add` ve `account_holder_change` nedenleri yazılır (075 bu envanterde henüz yoktur).

### V90 Geri bildirim ve ekleri (`feedback_reports`, `feedback_attachments`; dosyalar diskte)
- **Alanlar:** `feedback_reports`: `site_code` (boş olabilir), `user_code`, `role` (sunucuda türetilir), `screen_name`, `screen_route` (istemci otomatik ekler), `message` (1-2000, serbest metin), `app_version`, `platform`, `created_at`; `feedback_attachments`: `feedback_id`, `file_name` (≤160), `mime_type` (jpeg, png, webp), `size_bytes` (≤5 MiB), `sha256`, `status` (uploading, ready), `storage_key`, `ready_at`. En çok 4 ek, toplam 20 MiB. Ekler `<DOCUMENTS_DIR>/feedback_attachments/<site_code | 1000000000>/<uuid>` yoluna yazılır (`feedback_common.js:32`).
- **Kaynak:** `server/migrations/103_feedback.sql:11-45`; `server/src/modules/feedback_*.js`; istemci `lib/ui/dialogs/feedback_dialog.dart`, `lib/services/work_attachment_picker.dart`; sözleşme `docs/PLATFORM_GERI_BILDIRIM.md`. Modül değildir (platform özelliği, kapısı yok).
- **Amaç:** ürün hatası ve öneri toplamak; ekran görüntüsü eklenebilir.
- **Hukuki sebep önerisi:** m.5/2-f. **Rol belirsiz:** geri bildirimi hem site yöneticisi hem Güde ekibi (süper) okuyabildiği için veri sorumlusunun kim olduğu koddan çıkmaz → `[AVUKAT]` kararı gerekir; DOĞRULANAMADI.
- **Kim görür:** siteye bağlı geri bildirimi o sitenin yöneticisi (SITE_OWNER/SITE_ADMIN yönetici bağı) ve süper kullanıcı görür, siteye bağlı olmayanı yalnız süper kullanıcı; kurul, görevli, sakin ve başka site yöneticisi 403. Liste gönderenin adını ve rolünü, ekranı, sürümü, platformu, metni ve ekleri gösterir (`PLATFORM_GERI_BILDIRIM.md` "Kullanıcı tarafı"). Formda kimlerin göreceği yazar.
- **Ekler ve üstveri:** istemci fotoğrafı küçültür (en çok 2560 px, JPEG kalite 85) ve EXIF/GPS'i siler, ayıklanamazsa yüklemez; sunucu içerik imzasını ve piksel boyutunu denetler (415). Ekran görüntüsü başka kişilerin verisini (ad, borç, telefon) içerebilir.
- **Saklama:** otomatik silme yok; yalnız 2 saati aşan `uploading` ek satırları silinir (`feedback_maintenance.js:37`). Site silinince satırlar CASCADE gider ama **dosyalar diskte kalır** (`103` başlık yorumu); yetim dosya süpürmesi yok. Öneri: `[AVUKAT]` süre (saklama taslağında satırı yok).
- **Yedek:** `feedback_attachments` dizini `deploy/ops/backup_db.sh` arşivlerinde YOKTUR (grep ile doğrulandı); metin veritabanı dökümüyle yedeklenir.
- **Hesap silmede (1):** akış bu tablolara dokunmaz; `feedback_reports.user_code` TOMBSTONE, gönderen "Silinmiş Kullanıcı" görünür, metin ve ekler kalır; hesap silme önizlemesi ve veri dışa aktarma kapsamına geri bildirim EKLENMEDİ (`PLATFORM_GERI_BILDIRIM.md` "Bilinen sınırlar"). **(2):** `user_code` `ON DELETE SET NULL` (`103`).
- **Denetim:** `feedback.created`, `feedback.attachment_added` kimlik, rol, rota, ek sayısı ve bayt taşır; metin ve dosya adı yazılmaz.

### V91 Deneme erişim kodu ve deneme hesabı (`trial_access_codes`; `users` satırı)
- **Alanlar:** `trial_access_codes`: `code_hash` (HMAC-SHA256 özeti; düz kod ASLA saklanmaz), `code_hint` (son 4 karakter), `site_code` (demo site), `created_by`, `created_at`, `expires_at`, `note` (≤200, serbest metin), `used_by`, `used_at`, `session_expires_at`, `revoked_at`, `closed_at`. Kod kullanılınca gerçek bir `users` satırı açılır: rol `site_manager`, e-posta `trial-<rastgele>@deneme.invalid`, ad `Deneme Kullanıcısı <kod no>`, parola özeti hiçbir parolayla eşleşmez (`trial_access_service.js:7,357`).
- **Kaynak:** `server/migrations/106_trial_access_codes.sql:7-26`; `server/src/modules/trial_access_*.js`; sözleşme `docs/PLATFORM_DENEME_ERISIMI.md`. Platform özelliği (modül değil); Güde'nin kendi verisidir (veri sorumlusu Güde).
- **Amaç:** satış adayına 72 saatlik, yalnız demo siteye kilitli deneme.
- **Hukuki sebep önerisi:** m.5/2-f (Güde). Aday hakkında sunucuda kişisel veri tutulması beklenmez: ad, e-posta, telefon alınmaz; tek kişisel veri riski `note` alanıdır (belgede "ad-soyad, telefon yazmayın" uyarısı var, kod bunu zorlamaz: yalnız ≤200 karakter denetimi) ve kod kullanımı sırasındaki IP hız sınırı sayaçları (V11'deki bellek içi sınırlayıcı: `trial_access_routes.js:23`).
- **Kim görür:** süper kullanıcı ve demo sitenin yöneticisi kod listesini (son 4 karakter, durum, süreler, not) görür; düz kod yalnız üretim yanıtında bir kez görünür. Deneme oturumu yönetim ve hesap uçlarına kapalıdır (`PLATFORM_DENEME_ERISIMI.md` bölüm 3).
- **Saklama:** kod satırlarını silen kod yok (`DELETE FROM trial_access_codes` bulunmadı): kullanılmış, süresi dolmuş ve iptal edilmiş kodlar kalır; süre dolunca kullanıcı satırı pasife alınır ve demo site yönetici bağı silinir (`closeExpiredTrialAccounts`, `trial_access_service.js:158`), `users` satırı silinmez (denetim izi). Demo site silinirse kod satırları CASCADE ile gider, hesap kalıntısı yetim sayılır. Öneri: kullanım ve süre sonu `[ÖNERİ 1 yıl]` sonra silme/anonimleştirme (geliştirme gerekir; saklama taslağında satırı yok).
- **Hesap silmede (1):** deneme oturumunda hesap silme ucu kapalıdır (403 `TRIAL_ACTION_DENIED`); `created_by` ve `used_by` TOMBSTONE (FK katalogu). **(2):** iki sütun `ON DELETE SET NULL` (`106:12,16`).

### V92 Site yöneticisinin işlem kayıtları görünümü (yeni depolama YOK; `audit_log` okunur)
- **Veri:** yeni tablo ya da sütun yoktur; V08'deki `audit_log` satırları yönetici için süzülmüş olarak sunulur (`GET /manager/sites/:siteCode/audit-log`).
- **Kaynak:** `server/src/modules/site_audit_log_routes.js:31`, `site_audit_log_service.js`, `site_audit_log_catalog.js`; sözleşme `docs/PLATFORM_ISLEM_KAYITLARI.md`. Çekirdek özellik.
- **Gizlilik süzgeçleri (kodda doğrulandı):** yanıtta kullanıcı kodu, site kodu, e-posta, telefon, IP, parola ve belirteç YOKTUR; `details` yalnız izinli anahtarları (`SAFE_DETAIL_KEYS`) ve ≤64 karakterlik kod benzeri tek değerleri taşır (`site_audit_log_service.js:157,177`); süper kullanıcı adı "Sistem yöneticisi", silinmiş hesap "Silinmiş Kullanıcı" görünür ve `audit_log.actor_name` anlık görüntüsü yöneticiye gösterilmez (V08'deki anlık görüntü yalnız süper kullanıcıya özeldir). **Gizli liste** (yönetici hiçbir koşulda görmez): `residency_log.`, `safety_request.`, `access_suspension.`, `account.`, `user.`, `platform_config.`, `platform_settings.`, `subscription.`, `site_application.` önekleri ve `apartment_mgmt.person_search` / `search_visibility_changed` (`site_audit_log_catalog.js:78-90`). Kataloğa girmeyen yeni eylem yöneticiye varsayılan olarak görünmez.
- **Kim görür:** yalnız o sitenin yöneticisi ve süper kullanıcı (`resolvePeopleAccess` `write:true`); kurul, görevli, sakin ve başka site yöneticisi 403. Okuma izi tutulmaz (uç `audit_log`'a yazmaz). **Hesap silmede / saklama:** V08 ile aynı (süresiz; yeni saklama yok). Görünüm, V08'deki "kim görür" listesini genişletir: yönetici artık yalnız kişi/daire/araç geçmişini değil, kendi sitesinin tüm görünür eylem türlerini (kimin ne zaman ne yaptığını) listeleyebilir.

### V93 Acil durum bilgisi: asansör bakım firması (`site_emergency_info`)
- **Alanlar:** `site_code` (PK), `elevator_firm_name` (≤120), `elevator_firm_phone` (3-32), `created_at`, `updated_at`. Kullanıcı yabancı anahtarı yoktur; değiştiren yönetici denetim kaydındadır.
- **Kaynak:** `server/migrations/107_site_emergency_info.sql:7-16`; `server/src/modules/emergency_routes.js`; sözleşme `docs/PLATFORM_ACIL_DURUM.md`. Çekirdek özellik (modül kapısı yok).
- **Amaç:** asansörde mahsur kalan sakinin bakım firmasını arayabilmesi.
- **Hukuki sebep önerisi:** m.5/2-f (SY). Kişisel veri düşüktür: firma bilgisidir; ad ve telefon gerçek kişiye (tek usta) ait olabilir.
- **Kim görür:** sitenin yöneticisi, kurulu, görevlisi ve sakinleri `GET /app/emergency` ile kendi sitesinin firma adını ve telefonunu görür (başka sitenin bilgisi dönmez); yazma yalnız yönetici ve süper (`PUT /manager/sites/:siteCode/emergency`).
- **Saklama:** ikisi de boş kaydedilirse satır silinir; aksi halde site ömrü; site silinince CASCADE. **Hesap silmede:** etkilenmez. Denetim: `emergency.info_updated` (`set` / `cleared`; telefon yazılmaz).

### V94 Devir bakiyesi ve alacaklı devir (`finance_opening_reverts`; `ledger_entries.source_kind='opening'`; `bulk_import_runs`)
- **Alanlar:** devir bakiyesi dairenin hesabına defter kalemi olarak yazılır (borç: `kind='charge'`; alacak: `kind='payment'`, tutar eksi, `definition_name='Devir alacağı'`, `source_kind='opening'`, `source_id` = yükleme); `finance_opening_reverts`: `run_id`, `site_code`, `reversed_count`, `reversed_total_minor`, `idempotency_key`, `reverted_by`, `reverted_at`. Yükleme çalışması V72'deki `bulk_import_runs` satırıdır; 055 ile `kind` sabit listeden biçim denetimine geçti (V72'deki "apartments/people/vehicles" listesi artık devir yüklemesini de içerir).
- **Kaynak:** `server/migrations/055_opening_balances.sql:16-26`; alacaklı devir (K16) şema DEĞİŞTİRMEZ, `docs/PLATFORM_FINANS.md` "Alacaklı devir (K16, P2-4; 2026-10-29)"; yükleme `bulk_import_*`, `finance_opening.js`.
- **Kişisel veri:** kalemler daireye ve hesap tarafına (malik/kiracı) bağlıdır; dosyadaki kişi adı saklanmaz (`bulk_import_runs`: dosya ve ham satırlar saklanmaz, V72/V73). Tutar daire üzerinden kişiye ulaşır (V35 ile aynı).
- **Kim görür ve saklama:** V35 ile aynı (defter değişmez, yalnız site silinince CASCADE); devir alacağı tahsilat DEĞİLDİR (gelir raporlarına girmez, makbuz düzenlenmez). **Hesap silmede:** etkilenmez; `finance_opening_reverts.reverted_by` ve `bulk_import_runs.created_by` TOMBSTONE (FK katalogu).

### Envantere HÂLÂ girmemiş modüller (açık iş; 2026-10-29 itibarıyla bu ağaçta migration dosyası var, V-kaydı YOK)

Aşağıdaki liste yalnız migration dosya adlarından ve başlık satırlarından çıkarılmıştır; içerikleri okunmadığı için kişisel veri değerlendirmesi YAPILMADI. Sıra, kullanıcıya ya da kişi verisine dokunma ihtimali yüksek olandan başlar (tahmin; kodla doğrulanmadı).

| Migration | Tablolar / konu |
| --- | --- |
| 074, 075, 081 | Daire sahipliği ve yönetimi (`apartment_admin_delegations`, `apartment_link_requests`, `apartment_notices`, `apartment_proxies` ve diğerleri); daire sakini adli kaydı `apartment_residency_log` (sakin adı, ilişki, dönem; `docs/PLATFORM_ADLI_KAYIT.md`, saklama taslağında 10 yıl); kiracının daire yöneticisi olması |
| 042, 047, 096 (kısmen V82), 100 | İş takibi: `work_items`, `work_item_events`, `work_item_attachments`, `work_categories` |
| 043, 048 | Rezervasyon ve konsiyerj: `reservation_areas`, `reservations`, `concierge_requests` |
| 045, 046 | Ziyaretçi ve kargo `visitor_entries`; kartlı geçiş `access_cards` |
| 049, 050 | Firma ve sözleşme `contract_vendors`, `site_contracts`, `contract_reminders`; Karar Defteri `board_decisions` |
| 052, 054, 056, 059, 066, 067, 080 | Finans: iki hesap (malik/kiracı), ödeme bilgisi (`finance_payment_settings`, `finance_apartment_ref_codes`, `finance_account_bank_details`), gider türü, işletme projesi/bütçe, dekont bildirimi `payment_notices`, banka dosyası içe aktarma, İşletme/Fon hesapları |
| 061, 070 | Sayaç okuma ve faturalandırma `meters`, `meter_readings`, `meter_billings`; okuma fotoğrafları |
| 058, 062, 071 | Yönetim kadrosu, davet ve rehber (`site_team_duties`, `site_directory_contacts`, `person_invitations`); yönetim firması; beyaz etiket tema |
| 063, 076, 077 | SMS giriş kodları, tarayıcı (web push) abonelikleri, kargo bildirimi kaydı; Google/Apple OAuth kimlik bağlantıları; bütünlük sertleştirme (`users.must_change_password`) |
| 065 (kamera kısmı), 072, 073 | Kamera/plaka: `camera_devices` (kamera kullanıcı adı ve şifreli parola), `plate_events`; CCTV bağlantısı `cctv_cameras`; plaka tanıma `plate_guest_permits`, `plate_blacklist`, `plate_gate_settings`, `plate_decisions` |
| 053, 057, 102 | Kurallar tablosu `platform_rule_values`; duyuru gizleme/yumuşak silme; site menü düzeni `site_menu_layouts` |

Bu ağaçta HİÇ bulunmayan migration numaraları (086, 087, 092-095, 101, 105): başka dalların işi olabilir; kayıt yazılmadı. Bu bölümü okuyan kişi, o dallar birleştirildiğinde ilgili V-kayıtlarının eklenmesi gerektiğini bilmelidir.
