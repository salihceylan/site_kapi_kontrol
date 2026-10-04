# Sunucu API — giriş, oturum, yetki, kayıt, kapı açma, site yönetimi

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm Express sunucusunun (server/src) HTTP uçlarını kapsar: giriş/JWT, e-posta doğrulama, şifre sıfırlama, roller, kapı açma/QR/geofence, misafir geçişi, üyelik ve katılım, site yöneticisi uçları, cihaz/firmware HTTP uçları, şirket uçları, hız sınırları, CORS ve hata yakalayıcı. Önce hata mesajının geldiği ucu (routes/*.js), sonra çağırdığı servisi (services/*.js) açın; canlı günlük için PM2 süreci `kapi-api` (SSH 22667, salihceylan).

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [server/src/routes/auth_routes.js](../../server/src/routes/auth_routes.js) | Giriş, kayıt (bireysel), doğrulama kodu, tekrar gönder, şifre sıfırlama, /me; eski kayıt uçları 410 |
| [server/src/routes/membership_routes.js](../../server/src/routes/membership_routes.js) | Cihaz sahiplenme, site kurulumu, katılım başvurusu, daire üyeleri, kapı yetkileri |
| [server/src/routes/app_doors_routes.js](../../server/src/routes/app_doors_routes.js) | Kapı listesi/durum, uzaktan açma, karekodla açma, yerel açma bildirimi, QR token |
| [server/src/routes/guest_passes_routes.js](../../server/src/routes/guest_passes_routes.js) | Misafir/kurye geçiş linki: oluşturma, listeleme, iptal, herkese açık açma, /guest/:token sayfası |
| [server/src/routes/public_guest_routes.js](../../server/src/routes/public_guest_routes.js) | guest_passes_routes için yeniden dışa aktarım (publicGuestRouter) |
| [server/src/routes/manager_routes.js](../../server/src/routes/manager_routes.js) | Site yöneticisi uçları: site, kapı, cihaz, sakin, katılım başvurusu, yönetici daveti, güvenlik politikası |
| [server/src/routes/admin_routes.js](../../server/src/routes/admin_routes.js) | Süper kullanıcı uçları: kullanıcı, site, daire, kapı, cihaz envanteri, OTA tetikleme, bakım |
| [server/src/routes/door_log_routes.js](../../server/src/routes/door_log_routes.js) | Kapı geçiş günlükleri (admin/yönetici) ve çevrimdışı günlük senkronu |
| [server/src/routes/firmware_routes.js](../../server/src/routes/firmware_routes.js) | /health, firmware manifest ve .bin sunumu (OTA) |
| [server/src/routes/company_routes.js](../../server/src/routes/company_routes.js) | Şirket uçları (/api/company, /qrcodes): etiketli cihaz kaydı, karekod resimleri |
| [server/src/middlewares/auth_middleware.js](../../server/src/middlewares/auth_middleware.js) | authRequired (JWT + taze DB okuması), requireSuperUser, requireSiteManager |
| [server/src/middlewares/login_throttle.js](../../server/src/middlewares/login_throttle.js) | Hesap bazlı hatalı giriş/parola sayacı (LOGIN_LOCKED, CURRENT_PASSWORD_LOCKED) |
| [server/src/middlewares/rate_limiters.js](../../server/src/middlewares/rate_limiters.js) | Bellek içi hız sınırlayıcılar (giriş, kayıt, kod, kapı komutu, QR, davet...) |
| [server/src/middlewares/error_handler.js](../../server/src/middlewares/error_handler.js) | 404, global hata yakalayıcı, errorId üretimi, respondWithServiceError |
| [server/src/middlewares/request_logger.js](../../server/src/middlewares/request_logger.js) | [API] istek günlüğü ve URL içindeki gizli değerlerin maskelenmesi |
| [server/src/middlewares/company_auth.js](../../server/src/middlewares/company_auth.js) | X-Company-Key veya süper kullanıcı JWT ile şirket erişimi |
| [server/src/middlewares/security_headers.js](../../server/src/middlewares/security_headers.js) | Genel güvenlik başlıkları (nosniff, X-Frame-Options, HSTS) |
| [server/src/jwt.js](../../server/src/jwt.js) | JWT üretim/doğrulama, pv (parola sürümü) claim'i, 30 gün süre |
| [server/src/mailer.js](../../server/src/mailer.js) | SMTP taşıyıcı ve tüm e-posta şablonları (kod, sıfırlama, davet, başvuru bildirimi) |
| [server/src/config/env.js](../../server/src/config/env.js) | Ortam değişkeni doğrulaması (JWT_SECRET, SMTP, COMPANY_API_KEY uyarıları) |
| [server/src/config/cors.js](../../server/src/config/cors.js) | CORS izin listesi (CORS_ORIGINS, PUBLIC_APP_URL, PUBLIC_BASE_URL) |
| [server/src/config/process_handlers.js](../../server/src/config/process_handlers.js) | unhandledRejection / uncaughtException yakalayıcıları (çökünce exit 1) |
| [server/src/services/membership_service.js](../../server/src/services/membership_service.js) | Kayıt/doğrulama kodu, cihaz sahiplenme, site kurulumu, katılım, daire üyeliği, kapı izinleri |
| [server/src/services/membership_rules.js](../../server/src/services/membership_rules.js) | Saf kurallar: kod süreleri/limitleri, SQL metinleri, giriş normalizasyonu |
| [server/src/services/site_service.js](../../server/src/services/site_service.js) | Site yapısı, katılım tokeni, silme akışları, yönetici daveti/çıkarma, yönetim yetkisi |
| [server/src/services/door_service.js](../../server/src/services/door_service.js) | Erişilebilir kapılar sorgusu, cihaz atama/değiştirme, kapı geçiş günlüğü yazma, yerel kontrol bilgisi |
| [server/src/services/door_access_policy.js](../../server/src/services/door_access_policy.js) | Kanal politikası (remote/qr/guest/local), karekod yükü ayrıştırma, ekran QR token mantığı |
| [server/src/services/geofence_service.js](../../server/src/services/geofence_service.js) | Sunucu tabanlı konum doğrulaması (GEOFENCE_* kodları) |
| [server/src/services/qr_access_service.js](../../server/src/services/qr_access_service.js) | Dinamik QR token üretimi ve GM60/WROOM okuyucu doğrulaması |
| [server/src/services/device_service.js](../../server/src/services/device_service.js) | Cihaz envanteri, yerel kontrol tokenı döndürme, sahiplik, arıza, OTA işi kaydı |
| [server/src/services/local_token_service.js](../../server/src/services/local_token_service.js) | Yetki kalkınca cihaz yerel kontrol tokenını döndürme yardımcısı |
| [server/src/services/firmware_manifest_service.js](../../server/src/services/firmware_manifest_service.js) | Manifest hedef kontrolü ve UID/IP ayrıştırma (saf) |
| [server/src/services/door_log_service.js](../../server/src/services/door_log_service.js) | Çevrimdışı günlük doğrulama ve toplu ekleme |
| [server/src/services/maintenance_service.js](../../server/src/services/maintenance_service.js) | Günlük temizlik ve veritabanı sağlık özeti |
| [server/src/services/apartment_service.js](../../server/src/services/apartment_service.js) | Daire sakini hesabı oluşturma/sıfırlama, giriş bilgisi e-postası |
| [server/src/services/user_service.js](../../server/src/services/user_service.js) | Kullanıcı oluşturma/güncelleme (bcrypt) |
| [server/src/utils/helpers.js](../../server/src/utils/helpers.js) | Rol kümesi, auditLog, eşleyiciler (mapDoorRow...), normalizasyon |
| [server/src/utils/validators.js](../../server/src/utils/validators.js) | Girdi doğrulayıcılar (400 metinleri) ve mutasyon hata eşleyicileri (409/500) |
| [server/src/utils/site_rules.js](../../server/src/utils/site_rules.js) | Güvenlik politikası kuralları, yönetici çıkarma kuralı, kapı hata eşlemesi, isClientSafeError |
| [server/src/utils/guest_pass_utils.js](../../server/src/utils/guest_pass_utils.js) | Misafir geçişi girdi doğrulama, durum sınıflama, atomik hak tüketimi SQL'i |
| [server/src/utils/ids.js](../../server/src/utils/ids.js) | İstekten gelen kimlik değerlerini güvenli ayrıştırma |
| [server/src/utils/async_errors.js](../../server/src/utils/async_errors.js) | Express 4 async hata yaması (reddedilen promise -> next(err)) |

## Bu bölümdeki girişler (82)

- [sunucu-giris-401](#sunucu-giris-401) — Doğru parolaya rağmen giriş "Giris bilgileri hatali." (401) veriyor
- [sunucu-giris-hesap-kilitli-429](#sunucu-giris-hesap-kilitli-429) — Giriş "Çok fazla hatalı giriş denemesi. Hesap geçici olarak kilitlendi" (429, LOGIN_LOCKED) veriyor
- [sunucu-giris-ip-hiz-siniri-429](#sunucu-giris-ip-hiz-siniri-429) — Giriş "Cok fazla giris denemesi. Biraz sonra tekrar deneyin." (429) veriyor; aynı ağdaki başka kullanıcılar da etkileniyor
- [sunucu-giris-403-eposta-dogrulanmadi](#sunucu-giris-403-eposta-dogrulanmadi) — Giriş "E-posta adresiniz dogrulanmadi." (403) veriyor; yeni kayıt olan kullanıcı içeri giremiyor
- [sunucu-giris-403-onay-pasif-rol](#sunucu-giris-403-onay-pasif-rol) — Giriş 403 veriyor: "Abonelik talebiniz onay bekliyor." / "reddedildi." / "Hesap aktif degil." / "Kullanici rolu ile secilen rol uyusmuyor."
- [sunucu-token-401-gecersiz](#sunucu-token-401-gecersiz) — Tüm uçlar 401 veriyor: "Yetkisiz erisim." veya "Gecersiz veya suresi dolmus token."; uygulama kullanıcıyı çıkışa zorluyor
- [sunucu-token-revoked-parola-degisti](#sunucu-token-revoked-parola-degisti) — Parola değişikliğinden sonra eski cihazlarda 401 "Oturum gecersiz. Lutfen tekrar giris yapin." (TOKEN_REVOKED)
- [sunucu-oturum-401-kullanici-yok](#sunucu-oturum-401-kullanici-yok) — Oturum açıkken tüm uçlar 401 "Kullanici bulunamadi." veriyor (hesap silinmiş)
- [sunucu-oturum-403-hesap-pasif](#sunucu-oturum-403-hesap-pasif) — Uygulama açıkken tüm uçlar 403 veriyor: "Hesap aktif degil." / "E-posta adresiniz dogrulanmadi." / "Abonelik talebiniz ..."
- [sunucu-db-kesintisi-500-oturum-dusmuyor](#sunucu-db-kesintisi-500-oturum-dusmuyor) — Tüm istekler 500 "Sunucu hatasi olustu. Lutfen daha sonra tekrar deneyin." dönüyor ama kullanıcılar çıkışa zorlanmıyor
- [sunucu-yetki-403-super-user](#sunucu-yetki-403-super-user) — Panel/yönetim ucu 403 "Bu islem icin super user yetkisi gerekir." veriyor
- [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi) — Site yöneticisi uçları 403 veriyor: "Bu islem icin site yoneticisi yetkisi gerekir." / "Bu siteyi yonetme yetkiniz yok."
- [sunucu-profil-parola-degistirme-hata](#sunucu-profil-parola-degistirme-hata) — Profilde parola değişmiyor: "Mevcut parola hatali." / "Parolayi degistirmek icin mevcut parolanizi girmelisiniz." / 429 CURRENT_PASSWORD_LOCKED
- [sunucu-profil-eposta-degistirilemiyor](#sunucu-profil-eposta-degistirilemiyor) — Profilde/yönetim panelinde e-posta değiştirilemiyor: "E-posta adresi güvenlik nedeniyle değiştirilemez."
- [sunucu-yonetici-sakin-sifre-403](#sunucu-yonetici-sakin-sifre-403) — Yönetici/site yöneticisi daire sakininin şifresini değiştiremiyor: 403 "Güvenlik kuralı: ... şifresini değiştiremez" ya da USE_PROFILE_PASSWORD_CHANGE
- [sunucu-kayit-kod-gelmiyor](#sunucu-kayit-kod-gelmiyor) — Kayıt olurken e-postaya doğrulama kodu gelmiyor ya da çok geç geliyor
- [sunucu-kayit-503-eposta-gonderilemedi](#sunucu-kayit-503-eposta-gonderilemedi) — Kayıt 503 veriyor: "Doğrulama kodu şu anda e-posta ile gönderilemiyor. Lütfen birkaç dakika sonra tekrar deneyiniz." (EMAIL_DELIVERY_FAILED)
- [sunucu-kayit-429-bekleme-sinir](#sunucu-kayit-429-bekleme-sinir) — Kayıt/kod isteme 429 veriyor: "Yeni kod istemek için lütfen N saniye bekleyiniz." / "Bu e-posta adresi için çok fazla kod istendi" / "Cok fazla kayit denemesi"
- [sunucu-kayit-409-zaten-kayitli](#sunucu-kayit-409-zaten-kayitli) — Kayıt 409 veriyor: "Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır."
- [sunucu-kayit-400-girdi](#sunucu-kayit-400-girdi) — Kayıt formu 400 veriyor: "Ad ve soyad alanları zorunludur." / "Geçerli bir e-posta adresi giriniz." / "Şifre en az 6 karakter olmalıdır."
- [sunucu-dogrulama-kod-hatali-400](#sunucu-dogrulama-kod-hatali-400) — Doğrulama kodu girilince 400 "Girdiğiniz 6 haneli kod hatalıdır." (kod doğru görünüyor)
- [sunucu-dogrulama-429-deneme-asildi](#sunucu-dogrulama-429-deneme-asildi) — Doğrulama 429 veriyor: "Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz." / "Lütfen 30 dakika sonra tekrar deneyiniz."
- [sunucu-dogrulama-404-bekleyen-kayit-yok](#sunucu-dogrulama-404-bekleyen-kayit-yok) — Doğrulama 404 veriyor: "Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz." ya da "Aktif bir doğrulama kodu bulunamadı."
- [sunucu-tekrar-gonder-hep-basarili](#sunucu-tekrar-gonder-hep-basarili) — "Tekrar gönder" her zaman başarılı görünüyor ama kod gelmiyor
- [sunucu-sifre-sifirlama-mail-gelmiyor](#sunucu-sifre-sifirlama-mail-gelmiyor) — "Şifremi unuttum" başarılı görünüyor ama sıfırlama e-postası gelmiyor
- [sunucu-sifre-sifirlama-baglanti-gecersiz](#sunucu-sifre-sifirlama-baglanti-gecersiz) — Şifre sıfırlama bağlantısı "geçersiz veya daha önce kullanılmış" / "süresi dolmuş (30 dakika)" diyor
- [sunucu-eski-kayit-uclari-410](#sunucu-eski-kayit-uclari-410) — Eski uygulama sürümünde kayıt/abonelik 410 veriyor: "Yeni kullanici kaydi yalnizca super user tarafindan yapilir." / "Site yoneticisi onay akisi kapatildi."
- [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp) — Sunucudan hiçbir e-posta çıkmıyor (kayıt kodu, şifre sıfırlama, yönetici daveti, daire giriş bilgisi, silme kodu)
- [sunucu-kapi-acma-404-yetki](#sunucu-kapi-acma-404-yetki) — Kapı açma isteği 404 "Kapi bulunamadi." dönüyor (kapı var ama kullanıcı açamıyor)
- [sunucu-sakin-kapi-listede-yok](#sunucu-sakin-kapi-listede-yok) — Onaylanan sakin/yönetici kapıyı uygulamada göremiyor ("Kapılarım" listesi boş ya da eksik)
- [sunucu-kapi-acma-409-cihaz-atanmamis](#sunucu-kapi-acma-409-cihaz-atanmamis) — Kapı açma/durum 409 "Bu kapiya cihaz atanmamis." veriyor
- [sunucu-kapi-acma-cihaz-offline](#sunucu-kapi-acma-cihaz-offline) — Kapı açma 409 "Cihaz online gorunmuyor." (DEVICE_OFFLINE) ya da 503 "MQTT baglantisi hazir degil." veriyor
- [sunucu-kapi-acma-429-cok-sik](#sunucu-kapi-acma-429-cok-sik) — Kapı açma 429 "Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin." veriyor
- [sunucu-kapi-acma-403-uzaktan-kapali](#sunucu-kapi-acma-403-uzaktan-kapali) — Kapı açma 403 "Bu sitede uygulama uzerinden uzaktan kapi acma yetkisi kapalidir." (REMOTE_OPEN_DISABLED)
- [sunucu-karekod-politika-kapali](#sunucu-karekod-politika-kapali) — Karekodla geçiş reddediliyor: 403 "Bu sitede karekod ile kapi acma yetkisi kapalidir." (QR_DISABLED) / "karekod ile giris yonetim tarafindan gecici olarak durdurulmustur." (QR_ENTRY_INACTIVE)
- [sunucu-geofence-konum-reddi](#sunucu-geofence-konum-reddi) — Kapı açma 403 GEOFENCE_LOCATION_REQUIRED / _INVALID / _STALE / _INACCURATE / _MOCK_LOCATION ("konum dogrulamasi zorunludur", "Konum bilginiz guncel degil", "Sahte konum")
- [sunucu-geofence-menzil-disi](#sunucu-geofence-menzil-disi) — Kapı açma 403 "Kapi konumunda degilsiniz (Mesafe: ~Xm, Izin verilen sinir: Ym)" (GEOFENCE_OUT_OF_RANGE) veya "Sitenin konum (geofence) ayari gecersiz" (SITE_MISCONFIGURED)
- [sunucu-tarama-qr-ekran-token](#sunucu-tarama-qr-ekran-token) — Kapı önündeki karekod okutulunca 409 "Cihaz ekranindaki guncel karekod henuz alinamadi" (EKRAN_QR_BEKLENIYOR) ya da 403 DYNAMIC_QR_REQUIRED
- [sunucu-tarama-qr-suresi-doldu](#sunucu-tarama-qr-suresi-doldu) — Karekod okutunca 403 "Karekodun süresi dolmuş" (SCREEN_QR_EXPIRED) ya da "Bu karekod daha once kullanildi" (SCREEN_QR_ALREADY_USED)
- [sunucu-tarama-qr-gecersiz-yuk](#sunucu-tarama-qr-gecersiz-yuk) — Karekod okutunca 400 "Gecersiz karekod verisi." (INVALID_QR_PAYLOAD), 404 "Karekod ile eslesen aktif bir kapi bulunamadi." ya da 403 DOOR_ACCESS_DENIED
- [sunucu-qr-token-uretilemiyor](#sunucu-qr-token-uretilemiyor) — Uygulamada dinamik karekod üretilemiyor: 400 "Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır." (NO_QR_SCANNER_HARDWARE), 403 ya da 429 "Karekod talebi çok sık yapıldı"
- [sunucu-gm60-okuyucu-reddi](#sunucu-gm60-okuyucu-reddi) — Kapı önündeki QR okuyucu (GM60/WROOM) telefondaki karekodu kabul etmiyor, kapı açılmıyor
- [sunucu-gm60-role-calismadi](#sunucu-gm60-role-calismadi) — Okuyucu karekodu kabul etti ama röle çalışmadı / kapı açılmadı (PULSE_FAILED)
- [sunucu-yerel-kontrol-token-bos](#sunucu-yerel-kontrol-token-bos) — Uygulama yerel (Wi-Fi) açma yapamıyor: durum yanıtında local_control.token boş, available false ya da 403 LOCAL_DISABLED
- [sunucu-yerel-token-rotasyonu](#sunucu-yerel-token-rotasyonu) — Yetkisi alınan kişi hâlâ yerel açabiliyor ya da yeni yetki verilen kişide yerel açma eski token yüzünden reddediliyor
- [sunucu-kapi-gecis-logu-yazilmadi](#sunucu-kapi-gecis-logu-yazilmadi) — Kapı açıldı ama geçiş günlüğünde (kapı kayıtları) satır yok ya da eski kayıtlar kayboldu
- [sunucu-yonetici-gecis-gunlugu-bos](#sunucu-yonetici-gecis-gunlugu-bos) — Site yöneticisi "Kapı geçiş günlüğü" ekranında hiç kayıt göremiyor ya da 403 "Bu sitenin loglarini gorme yetkiniz yok."
- [sunucu-offline-log-senkronu-hata](#sunucu-offline-log-senkronu-hata) — Çevrimdışı kapı kayıtları senkronlanmıyor: /device/sync-logs 400/403/404/413 veriyor ya da rejected_count yüksek
- [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri) — Bir işlem "Cok fazla ... denemesi. Biraz sonra tekrar deneyin." (429, Retry-After) ile reddediliyor; hangi sınırlayıcı olduğu belli değil
- [sunucu-hata-500-errorid](#sunucu-hata-500-errorid) — İstemci "Sunucu hatasi olustu. Lutfen daha sonra tekrar deneyin." + errorId (500) alıyor; nedeni ekranda görünmüyor
- [sunucu-admin-kullanici-yonetimi-400](#sunucu-admin-kullanici-yonetimi-400) — Süper kullanıcı panelinde kullanıcı oluşturma/düzenleme/aktiflik 400/403/409 veriyor ("Kendi hesabinizi pasif yapamazsiniz", "E-posta adresi güvenlik nedeniyle değiştirilemez" vb.)
- [sunucu-admin-kullanici-silme-hata](#sunucu-admin-kullanici-silme-hata) — Süper kullanıcı kullanıcıyı silemiyor: "Kullanici silinemedi." (500 + errorId), "Kendi hesabinizi silemezsiniz." ya da 404
- [sunucu-yonetici-daveti-eslesmedi](#sunucu-yonetici-daveti-eslesmedi) — Davet edilen kişi kayıt olup e-postasını doğruladı ama site yöneticisi yetkisi gelmedi (sitede yönetici görünmüyor)
- [sunucu-yonetici-daveti-mail-yok](#sunucu-yonetici-daveti-mail-yok) — Yönetici daveti "işleme alındı" diye başarılı görünüyor ama davet edilen kişiye e-posta gelmiyor
- [sunucu-yonetici-cikarma-hata](#sunucu-yonetici-cikarma-hata) — Site yöneticisi çıkarılamıyor: "Son yönetici çıkarılamaz", "Site Sahibi yalnızca Süper Kullanıcı tarafından çıkarılabilir" ya da 404
- [sunucu-daire-bilgisi-eposta-gitmiyor](#sunucu-daire-bilgisi-eposta-gitmiyor) — Yönetici "Giriş bilgilerini e-postayla gönder" diyor: "Mail gonderimi icin daire sakini e-postasi gerekli." / "Kullanici adi veya PIN hazir degil." / gönderim hatası
- [sunucu-daire-sakin-yonetimi-hata](#sunucu-daire-sakin-yonetimi-hata) — Yöneticinin daire sakini kaydetme/sıfırlama işlemi hata veriyor ("Sifre 4 haneli sayisal olmali.", "Daire bulunamadi.", 409 kullanıcı adı çakışması, "Bu daireyi yonetme yetkiniz yok.")
- [sunucu-katilim-basvuru-hata](#sunucu-katilim-basvuru-hata) — Sakinin QR ile site katılım başvurusu reddediliyor: "Bu site katılım QR kodu geçersiz veya iptal edilmiş.", "e-posta adresinizi doğrulamanız", "zaten onay bekleyen başvuru"
- [sunucu-katilim-onay-hata](#sunucu-katilim-onay-hata) — Yönetici katılım başvurusunu onaylayamıyor/reddedemiyor: "Bu talebi onaylama yetkiniz bulunmamaktadır.", "zaten ... durumunda", 404 ya da onaydan sonra sakin kapıyı göremiyor
- [sunucu-kapi-yetkisi-yonetimi-403](#sunucu-kapi-yetkisi-yonetimi-403) — Yönetici kapı yetkisi (tekil/toplu) veremiyor: "Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır." (403), 400 ya da "Seçilen alanda aktif sakin bulunamadı."
- [sunucu-daire-uye-yonetimi-hata](#sunucu-daire-uye-yonetimi-hata) — Daire üyesi çıkarma/pasife alma/silme/aile reisi değiştirme hata veriyor ("Daire yöneticisi kendi kendisini daireden çıkaramaz", "yalnızca site yöneticilerine aittir", "Mevcut şifre hatalı")
- [sunucu-yonetici-katilim-qr-hata](#sunucu-yonetici-katilim-qr-hata) — Yönetici panelinde site katılım QR'ı alınamıyor ya da yenilenemiyor ("Site katilim QR kodu alinamadi.", "Bu siteyi yonetme yetkiniz yok.")
- [sunucu-site-silme-cift-onay](#sunucu-site-silme-cift-onay) — Site silme isteği silmiyor, "Site silme talebi oluşturuldu... onayı gerekmektedir" diyor ya da "Bu silme talebini yalnızca ... onaylayabilir" (403)
- [sunucu-site-silme-kodu-hata](#sunucu-site-silme-kodu-hata) — Süper kullanıcı e-posta kodu ile siteyi silemiyor: kod gelmiyor, "silme doğrulama kodu hatalı", "10 dakikalık süresi dolmuş" ya da "Çok fazla hatalı doğrulama denemesi" (429)
- [sunucu-kapi-cihaz-atama-403](#sunucu-kapi-cihaz-atama-403) — Kapıya cihaz atanamıyor/değiştirilemiyor: "Bu cihaz yonettiginiz siteye atanamaz." (403), "baska bir kullanici hesabi tarafindan sahiplenilmis" (409), "arizali" (409), "Site sirket tarafindan onaylanmadan..." (403)
- [sunucu-guvenlik-politikasi-hata](#sunucu-guvenlik-politikasi-hata) — Site güvenlik politikası kaydedilemiyor: "Giris yontemi yetkilendirmesi ... yalnizca super user", "En az bir giris yontemi ... acik olmalidir", "Konum dogrulamasi acikken gecerli bir enlem ve boylam ..."
- [sunucu-cihaz-sahiplenme-hata](#sunucu-cihaz-sahiplenme-hata) — Kutu QR/seri no ile cihaz sahiplenme reddediliyor: "şirket envanterinde kayıtlı değildir" (404), "başka bir kullanıcı hesabı tarafından sahiplenilmiş" (409), "arızalı olarak işaretlenmiştir" (400), "e-posta adresinizi doğrulamanız" (403)
- [sunucu-site-kurulumu-hata](#sunucu-site-kurulumu-hata) — Site kurulum sihirbazı hata veriyor: "Site kurmak için önce bir cihaz sahiplenmelisiniz.", "Belirtilen cihaz hesabınıza ait değil.", "En fazla ... blok tanımlanabilir", "Cok fazla site kurulum denemesi"
- [sunucu-cors-tarayici-engeli](#sunucu-cors-tarayici-engeli) — Web (tarayıcı) sürümü API'ye erişemiyor: konsolda CORS hatası, istek "blocked by CORS policy"; mobil uygulama sorunsuz
- [sunucu-istek-gunlugu-ve-basliklar](#sunucu-istek-gunlugu-ve-basliklar) — Günlükte istek satırı yok/eksik ya da gizli değer (token, kod) görünüyor; ya da sayfa iframe içinde açılmıyor (X-Frame-Options)
- [sunucu-kimlik-gecersiz-400](#sunucu-kimlik-gecersiz-400) — Uç "Gecersiz ... ID/kodu" (400) veriyor; geçerli görünen bir kimlikle bile (örn. "1e3", boşluklu, çok büyük sayı) reddediliyor
- [sunucu-async-hata-istek-asili](#sunucu-async-hata-istek-asili) — Bir istek yanıt vermeden asılı kalıyor ya da sunucu tek bir hatayla çöküyor (yakalanmamış async hata)
- [sunucu-firmware-manifest-ota](#sunucu-firmware-manifest-ota) — Cihaz OTA güncellemesi almıyor: manifest "Bu hedef icin OTA yayini yok.", "Cihaz bu yayin grubunda degil.", 403 FIRMWARE_TARGET_MISMATCH ya da 503
- [sunucu-firmware-bin-indirilemiyor](#sunucu-firmware-bin-indirilemiyor) — Cihaz manifest'i alıyor ama .bin indirmesi başarısız: 400 "Gecersiz firmware dosyasi.", 404 "Firmware dosyasi bulunamadi." ya da cihazda MD5/başlık hatası
- [sunucu-sirket-ucu-401-anahtar](#sunucu-sirket-ucu-401-anahtar) — Şirket aracı ya da süper kullanıcı /api/company ve /qrcodes uçlarında 401 "Yetkisiz erisim." ya da 429 alıyor
- [sunucu-sirket-cihaz-kayit-hata](#sunucu-sirket-cihaz-kayit-hata) — Şirket aracı cihaz/karekod kaydedemiyor ya da silemiyor: 400 device_uid/PNG hatası, 500 "Cihaz veritabanina kaydedilemedi" (errorId)
- [sunucu-misafir-gecis-olusturma-hata](#sunucu-misafir-gecis-olusturma-hata) — Misafir/kurye geçiş linki oluşturulamıyor: "Bu sitede misafir/kurye gecis kodu olusturma kapalidir." (403 GUEST_DISABLED), "Kapi bulunamadi veya yetkiniz yok.", 400 geçersiz süre/tür
- [sunucu-misafir-gecis-acma-hata](#sunucu-misafir-gecis-acma-hata) — Misafir linkiyle kapı açılmıyor: 410 "iptal edilmis/suresi dolmus/daha once kullanilmis", 403 "olusturan kullanicinin yetkisi kalmamis", 409 "cihaz atanmamis", 503 "cihazi su anda bagli degil"
- [sunucu-misafir-sayfa-acilmiyor](#sunucu-misafir-sayfa-acilmiyor) — Misafir linki tarayıcıda açılınca "geçersiz" sayfası ya da "Sunucu hatasi olustu. Referans: ..." görünüyor; sayfa düğmesi çalışmıyor
- [sunucu-admin-ota-tetikleme-hata](#sunucu-admin-ota-tetikleme-hata) — Süper kullanıcı panelinden "OTA güncelleme denetimi" gönderilemiyor: 503 "MQTT baglantisi hazir degil.", 500 "OTA komutu gonderilemedi." ya da failed listesi dolu
- [sunucu-admin-cihaz-envanteri-hata](#sunucu-admin-cihaz-envanteri-hata) — Süper kullanıcı panelinde cihaz ekleme/düzenleme/silme hata veriyor: 409 "Bu cihazin unique id kayitli.", 404 "Kullanici/Site ID bulunamadi.", 503 "... MQTT broker senkronu basarisiz."
- [sunucu-admin-cihaz-ariza-sahiplik](#sunucu-admin-cihaz-ariza-sahiplik) — Cihaz sahiplenilemiyor/atanamıyor çünkü "arızalı" ya da sahipli görünüyor; süper kullanıcı arıza durumunu kaldıramıyor ya da sahipliği sıfırlayamıyor

## Girişler

<a id="sunucu-giris-401"></a>
### sunucu-giris-401 · Doğru parolaya rağmen giriş "Giris bilgileri hatali." (401) veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:663](../../server/src/routes/auth_routes.js#L663) | <code>authRouter.post('/auth/login', loginRateLimiter, async (req, res) =&gt; {</code> | Giriş ucu: kimlik (e-posta ya da kullanıcı adı) ve parola alır |
| [server/src/routes/auth_routes.js:665](../../server/src/routes/auth_routes.js#L665) | <code>req.body?.email ?? req.body?.login ?? req.body?.identifier,</code> | Kimlik küçük harfe çevrilir; alan adı email, login ya da identifier olabilir |
| [server/src/routes/auth_routes.js:699](../../server/src/routes/auth_routes.js#L699) | <code>WHERE LOWER(email) = LOWER($1) OR LOWER(login_name) = LOWER($1)</code> | Kullanıcı e-posta VEYA login_name ile bulunur (daire sakinleri login_name ile girer) |
| [server/src/routes/auth_routes.js:723](../../server/src/routes/auth_routes.js#L723) | <code>const isPasswordMatch = await bcrypt.compare(password, storedHash &#124;&#124; DUMMY_PASSWORD_HASH);</code> | bcrypt karşılaştırması; kullanıcı yoksa sahte özetle karşılaştırılır (süre sızmasın) |
| [server/src/routes/auth_routes.js:729](../../server/src/routes/auth_routes.js#L729) | <code>return res.status(401).json({ error: 'Giris bilgileri hatali.' });</code> | 401 yanıtının üretildiği satır (yanlış parola ve olmayan hesap AYNI yanıtı alır) |

**Olası nedenler**
- Parola gerçekten yanlış (parola baş/son boşlukları kırpılır; kayıtta da kırpıldığı için tutarlıdır)
- Hesap yok ya da kimlik yanlış yazılmış (e-posta/kullanıcı adı); hesap yoksa da aynı 401 döner
- Kullanıcının password_hash değeri boş (storedHash boşsa her parola reddedilir)
- İstemci kimliği email/login/identifier dışında bir alanla gönderiyor (kimlik boş kalır -> 400 "email ve password zorunlu.")
- Beşinci hatada 401 yerine 429 LOGIN_LOCKED döner (bkz. kilit girişi)

**Adım adım kontrol**
- Günlükte isteği bulun: yöntem POST, yol /auth/login, durum 401
- Kullanıcı var mı (parola özeti basılmaz): SELECT user_code, role, is_active, email_verified FROM users WHERE LOWER(email)=LOWER('...') OR LOWER(login_name)=LOWER('...')
- Kullanıcı yoksa pending_registrations tablosuna bakın: bekleyen kayıt varsa doğru parola 401 değil 403 verir
- Şifre sıfırlama sonrası mı oldu: sıfırlama kilidi temizler, yeni parola ile girilebilmeli

**Günlükte aranacak ifadeler**
- `[API] `

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /auth/login"
```

**İlgili testler:** [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js), [server/test/fix_sx2_auth.test.js](../../server/test/fix_sx2_auth.test.js)

**Bkz.:** [sunucu-giris-hesap-kilitli-429](#sunucu-giris-hesap-kilitli-429), [sunucu-giris-403-eposta-dogrulanmadi](#sunucu-giris-403-eposta-dogrulanmadi), [sunucu-sifre-sifirlama-mail-gelmiyor](#sunucu-sifre-sifirlama-mail-gelmiyor)

<a id="sunucu-giris-hesap-kilitli-429"></a>
### sunucu-giris-hesap-kilitli-429 · Giriş "Çok fazla hatalı giriş denemesi. Hesap geçici olarak kilitlendi" (429, LOGIN_LOCKED) veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/login_throttle.js:99](../../server/src/middlewares/login_throttle.js#L99) | <code>export const loginFailureTracker = createFailureTracker({ maxFailures: 5, windowMs: 15 * …</code> | Giriş sayacı: 5 hata / 15 dk pencere / 15 dk kilit (bellek içi) |
| [server/src/middlewares/login_throttle.js:78](../../server/src/middlewares/login_throttle.js#L78) | <code>entry.lockedUntil = at + lockMs;</code> | Eşik aşılınca anahtar kilitlenir |
| [server/src/routes/auth_routes.js:653](../../server/src/routes/auth_routes.js#L653) | <code>function respondLoginLocked(res, retryAfterSeconds) {</code> | 429 + Retry-After + code LOGIN_LOCKED + retry_after_seconds yanıtı |
| [server/src/routes/auth_routes.js:678](../../server/src/routes/auth_routes.js#L678) | <code>const lockState = loginFailureTracker.check(identifier);</code> | Her giriş denemesinde önce kilit sorgulanır (parola bile denenmez) |
| [server/src/routes/auth_routes.js:731](../../server/src/routes/auth_routes.js#L731) | <code>loginFailureTracker.recordSuccess(identifier);</code> | Doğru parola sayacı sıfırlar |
| [server/src/middlewares/login_throttle.js:126](../../server/src/middlewares/login_throttle.js#L126) | <code>export function clearAccountLocks({ email, loginName, userCode } = {}) {</code> | Şifre sıfırlama başarılı olunca e-posta/kullanıcı adı kilitleri açılır |

**Olası nedenler**
- Aynı kimlikle art arda 5 yanlış parola (anahtar küçük harfli e-posta/kullanıcı adıdır, IP'den bağımsız)
- Birisi o hesaba kaba kuvvet deniyor (dağıtık denemeler de aynı hesabı kilitler)
- Sayaç süreç belleğindedir: PM2 yeniden başlayınca (deploy/çökme) tüm kilitler sıfırlanır, çoklu süreçte sayaç süreç başınadır

**Adım adım kontrol**
- Yanıttaki retry_after_seconds / Retry-After süresini bekleyin (en çok 15 dk)
- Kullanıcı şifresini hatırlamıyorsa "Şifremi unuttum" ile e-postadan sıfırlasın: başarılı sıfırlama kilidi anında açar
- Aynı IP'den çok sayıda farklı hesap deneniyorsa IP kuralına bakın (bkz. giriş IP hız sınırı girişi)

**Günlükte aranacak ifadeler**
- `[API] `

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a /auth/login | grep -a 429"
```

**İlgili testler:** [server/test/core_rate_limiter.test.js](../../server/test/core_rate_limiter.test.js), [server/test/fix_sx2_auth.test.js](../../server/test/fix_sx2_auth.test.js)

**Bkz.:** [sunucu-giris-401](#sunucu-giris-401), [sunucu-giris-ip-hiz-siniri-429](#sunucu-giris-ip-hiz-siniri-429), [sunucu-sifre-sifirlama-baglanti-gecersiz](#sunucu-sifre-sifirlama-baglanti-gecersiz)

<a id="sunucu-giris-ip-hiz-siniri-429"></a>
### sunucu-giris-ip-hiz-siniri-429 · Giriş "Cok fazla giris denemesi. Biraz sonra tekrar deneyin." (429) veriyor; aynı ağdaki başka kullanıcılar da etkileniyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/rate_limiters.js:166](../../server/src/middlewares/rate_limiters.js#L166) | <code>export const loginRateLimiter = createRuleLimiter({</code> | Giriş limiti: IP başına 60 + IP+kimlik başına 15 deneme / 15 dk |
| [server/src/middlewares/rate_limiters.js:169](../../server/src/middlewares/rate_limiters.js#L169) | <code>{ windowMs: 15 * 60 * 1000, max: 15, key: (req) =&gt; `ipid:${clientIp(req)}:${emailKeyOf(re…</code> | Aynı IP ve aynı kimlik için dar kural (15 deneme / 15 dk) |
| [server/src/middlewares/rate_limiters.js:37](../../server/src/middlewares/rate_limiters.js#L37) | <code>export function clientIp(req) {</code> | İstemci IP'si req.ip (nginx arkasında trust proxy=1 ile gerçek istemci) |
| [server/src/middlewares/rate_limiters.js:95](../../server/src/middlewares/rate_limiters.js#L95) | <code>export function createRuleLimiter({ rules, message, includeRetryBody = false, now = Date.…</code> | Kural aşılınca 429 + Retry-After döner; sayaçlar bellek içidir |

**Olası nedenler**
- Aynı site/ofis ağındaki (NAT, ortak IP) çok kullanıcı kısa sürede çok giriş yaptı (IP kuralı 60/15 dk)
- Aynı kimlikle 15 dakikada 15'ten fazla deneme (hesap kilidi 5. hatada zaten devreye girer)
- Ters vekil (nginx) req.ip'yi bozuyorsa herkes tek IP gibi görünür: X-Forwarded-For ayarını kontrol edin

**Adım adım kontrol**
- Yanıttaki Retry-After saniyesi kadar bekleyin; bellek içi olduğu için PM2 yeniden başlatma sayaçları sıfırlar
- İstek günlüğünde 429 veren /auth/login isteklerinin sıklığına bakın

**Günlükte aranacak ifadeler**
- `[API] `

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a /auth/login | grep -a 429"
```

**İlgili testler:** [server/test/core_rate_limiter.test.js](../../server/test/core_rate_limiter.test.js)

**Bkz.:** [sunucu-giris-hesap-kilitli-429](#sunucu-giris-hesap-kilitli-429), [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-giris-403-eposta-dogrulanmadi"></a>
### sunucu-giris-403-eposta-dogrulanmadi · Giriş "E-posta adresiniz dogrulanmadi." (403) veriyor; yeni kayıt olan kullanıcı içeri giremiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:710](../../server/src/routes/auth_routes.js#L710) | <code>const pendingRes = await pool.query(SQL_FIND_PENDING_LOGIN_HASH, [identifier]);</code> | Hesap yoksa bekleyen kaydın parola özeti aranır (doğru parola -> 403, yanlış -> 401) |
| [server/src/routes/auth_routes.js:739](../../server/src/routes/auth_routes.js#L739) | <code>return res.status(403).json({ error: 'E-posta adresiniz dogrulanmadi.' });</code> | Doğrulanmamış hesap/bekleyen kayıt için 403; token verilmez |
| [server/src/services/membership_rules.js:162](../../server/src/services/membership_rules.js#L162) | <code>export const SQL_FIND_PENDING_LOGIN_HASH = `</code> | pending_registrations tablosundan e-posta ile parola özeti okuyan sorgu |
| [server/src/services/membership_service.js:316](../../server/src/services/membership_service.js#L316) | <code>export async function verifyIndividualEmailCode({ email, code }) {</code> | Doğru kod girilince hesap tek işlemde açılır (users satırı ancak burada oluşur) |

**Olası nedenler**
- Kullanıcı kayıt oldu ama e-postadaki 6 haneli kodu henüz girmedi: yeni modelde users satırı kod girilene kadar YOKTUR, bekleyen kayıt vardır
- Kod e-postası ulaşmadı veya süresi (30 dk) doldu: yeniden kod istenmeli
- Bekleyen kayıt 2 günden eskiyse bakım servisi sildi; bu durumda doğru parola bile 401 döner ve yeniden kayıt gerekir
- Bu sürümden önce açılmış eski doğrulanmamış hesap (email_verified = FALSE)

**Adım adım kontrol**
- Kullanıcıya doğrulama ekranında "Tekrar gönder" yaptırın ve 30 dk içinde kodu girmesini isteyin
- Kod gelmiyorsa e-posta gönderim girişlerine bakın
- SELECT email, updated_at FROM pending_registrations WHERE LOWER(email)=LOWER('...') (parola özeti seçilmez)

**Günlükte aranacak ifadeler**
- `[Mail Gönderim Hatası]`

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/fix_sx2_auth.test.js](../../server/test/fix_sx2_auth.test.js)

**Bkz.:** [sunucu-kayit-kod-gelmiyor](#sunucu-kayit-kod-gelmiyor), [sunucu-dogrulama-404-bekleyen-kayit-yok](#sunucu-dogrulama-404-bekleyen-kayit-yok), [sunucu-giris-401](#sunucu-giris-401)

<a id="sunucu-giris-403-onay-pasif-rol"></a>
### sunucu-giris-403-onay-pasif-rol · Giriş 403 veriyor: "Abonelik talebiniz onay bekliyor." / "reddedildi." / "Hesap aktif degil." / "Kullanici rolu ile secilen rol uyusmuyor."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:736](../../server/src/routes/auth_routes.js#L736) | <code>.json({ error: 'Kullanici rolu ile secilen rol uyusmuyor.' });</code> | İstemci body.role gönderdiyse DB'deki rolle eşleşmeli (parola doğrulandıktan sonra bakılır) |
| [server/src/routes/auth_routes.js:742](../../server/src/routes/auth_routes.js#L742) | <code>return res.status(403).json({ error: 'Abonelik talebiniz onay bekliyor.' });</code> | approval_status = pending (eski site yöneticisi abonelik akışı) |
| [server/src/routes/auth_routes.js:745](../../server/src/routes/auth_routes.js#L745) | <code>return res.status(403).json({ error: 'Abonelik talebiniz reddedildi.' });</code> | approval_status = rejected |
| [server/src/routes/auth_routes.js:748](../../server/src/routes/auth_routes.js#L748) | <code>return res.status(403).json({ error: 'Hesap aktif degil.' });</code> | users.is_active = FALSE |
| [server/src/routes/admin_routes.js:395](../../server/src/routes/admin_routes.js#L395) | <code>'/admin/users/:id/activation',</code> | Süper kullanıcının hesabı aktif/pasif yaptığı uç |
| [server/src/routes/admin_routes.js:583](../../server/src/routes/admin_routes.js#L583) | <code>'/admin/subscription-requests/:id',</code> | Bekleyen abonelik talebini onaylama/reddetme (approval_status ve is_active'i birlikte değiştirir) |

**Olası nedenler**
- Süper kullanıcı hesabı pasife aldı (is_active = FALSE) ya da PATCH /me ile kullanıcı kendisini pasif yaptı
- approval_status pending/rejected kalmış eski bir site yöneticisi hesabı
- Uygulama giriş ekranı farklı bir rol seçti (role gönderiliyor ve DB rolüyle uyuşmuyor)

**Adım adım kontrol**
- SELECT user_code, role, is_active, approval_status, email_verified FROM users WHERE LOWER(email)=LOWER('...')
- Doğru ise süper kullanıcı panelinden hesabı aktif edin (PATCH /admin/users/:id/activation)

**İlgili testler:** [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js), [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js)

**Bkz.:** [sunucu-oturum-403-hesap-pasif](#sunucu-oturum-403-hesap-pasif), [sunucu-giris-401](#sunucu-giris-401)

<a id="sunucu-token-401-gecersiz"></a>
### sunucu-token-401-gecersiz · Tüm uçlar 401 veriyor: "Yetkisiz erisim." veya "Gecersiz veya suresi dolmus token."; uygulama kullanıcıyı çıkışa zorluyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:14](../../server/src/middlewares/auth_middleware.js#L14) | <code>if (!header.startsWith('Bearer ')) {</code> | Authorization: Bearer başlığı yoksa 401 "Yetkisiz erisim." |
| [server/src/middlewares/auth_middleware.js:7](../../server/src/middlewares/auth_middleware.js#L7) | <code>function isTokenVerificationError(error) {</code> | Yalnızca imza/süre/biçim hataları 401 sayılır; DB/yapılandırma hatası 5xx olur |
| [server/src/middlewares/auth_middleware.js:24](../../server/src/middlewares/auth_middleware.js#L24) | <code>return res.status(401).json({ error: 'Gecersiz veya suresi dolmus token.' });</code> | 401 yanıtının üretildiği satır |
| [server/src/jwt.js:84](../../server/src/jwt.js#L84) | <code>export function verifyAccessToken(token) {</code> | HS256 doğrulaması; JWT_SECRET ile imzalanmış olmalı |
| [server/src/jwt.js:6](../../server/src/jwt.js#L6) | <code>export const DEFAULT_JWT_EXPIRES_IN = '30d';</code> | Token ömrü varsayılan 30 gün (JWT_EXPIRES_IN ile değişir) |
| [server/src/jwt.js:15](../../server/src/jwt.js#L15) | <code>function getJwtSecret() {</code> | JWT_SECRET boş/yer tutucuysa hata fırlatır (imzalama/doğrulama 500 olur) |

**Olası nedenler**
- Token 30 günlük (veya JWT_EXPIRES_IN) ömrünü doldurdu
- Sunucuda JWT_SECRET değiştirildi: önceki tüm tokenlar imza hatasıyla 401 olur (planlı değişiklikte herkes yeniden girer)
- İstemci Authorization başlığını göndermiyor ya da "Bearer " öneki eksik (ters vekil başlığı düşürüyor olabilir)
- Geçersiz biçimli ya da kırpılmış token

**Adım adım kontrol**
- Sadece bir kullanıcıda mı yoksa herkeste mi? Herkesteyse son deploy/.env değişikliğine (JWT_SECRET) bakın
- Tek kullanıcıysa yeniden giriş yaptırın; sorun sürüyorsa giriş girişlerine bakın
- Sunucu açılışında "[ENV]" uyarı/hata satırlarına bakın (JWT_SECRET)

**Günlükte aranacak ifadeler**
- `[ENV] HATA:`
- `[ENV] UYARI:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a '\[ENV\]'"
```

**İlgili testler:** [server/test/core_jwt.test.js](../../server/test/core_jwt.test.js), [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js)

**Bkz.:** [sunucu-token-revoked-parola-degisti](#sunucu-token-revoked-parola-degisti), [sunucu-oturum-401-kullanici-yok](#sunucu-oturum-401-kullanici-yok), [altyapi-env-hata-sunucu-baslamiyor](20-sunucu-altyapi-ve-yayin.md#altyapi-env-hata-sunucu-baslamiyor)

<a id="sunucu-token-revoked-parola-degisti"></a>
### sunucu-token-revoked-parola-degisti · Parola değişikliğinden sonra eski cihazlarda 401 "Oturum gecersiz. Lutfen tekrar giris yapin." (TOKEN_REVOKED)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:70](../../server/src/middlewares/auth_middleware.js#L70) | <code>if (!isPasswordVersionValid(claims, passwordHash)) {</code> | Token'daki pv claim'i güncel parola özetiyle uyuşmuyorsa reddedilir |
| [server/src/middlewares/auth_middleware.js:73](../../server/src/middlewares/auth_middleware.js#L73) | <code>.json({ error: 'Oturum gecersiz. Lutfen tekrar giris yapin.', code: 'TOKEN_REVOKED' });</code> | 401 gövdesindeki code alanı (istemci bunu görünce çıkış yapar) |
| [server/src/jwt.js:34](../../server/src/jwt.js#L34) | <code>export function passwordVersionOf(passwordHash) {</code> | pv = parola özetinden türetilen kısa geri çevrilemez parmak izi |
| [server/src/jwt.js:46](../../server/src/jwt.js#L46) | <code>export function isPasswordVersionValid(claims, passwordHash) {</code> | pv claim'i olmayan eski tokenlar süresi dolana dek geçerli kalır |
| [server/src/routes/auth_routes.js:458](../../server/src/routes/auth_routes.js#L458) | <code>password_reset_token_hash = NULL,</code> | Şifre sıfırlama parola özetini değiştirir -> o hesabın tüm pv'li tokenları düşer |
| [server/src/routes/admin_routes.js:291](../../server/src/routes/admin_routes.js#L291) | <code>adminRouter.patch('/admin/users/:id', authRequired, requireSuperUser, async (req, res) =&gt;…</code> | Süper kullanıcı başka kullanıcının parolasını değiştirirse o kullanıcının oturumları da düşer |

**Olası nedenler**
- Kullanıcı şifre sıfırladı ya da değiştirdi: diğer cihazlardaki tokenlar TOKEN_REVOKED olur (beklenen davranış)
- PATCH /me parola değişince YENİ token yanıtta döner; istemci yeni token'ı saklamazsa o cihaz da düşer
- Yönetici (admin) bir kullanıcının parolasını panelden değiştirdi

**Adım adım kontrol**
- Kullanıcı yeni parolasıyla yeniden giriş yapmalı; bu beklenen akıştır
- PATCH /me yanıtında token alanının uygulamada saklandığını doğrulayın (Flutter tarafı)

**İlgili testler:** [server/test/core_jwt.test.js](../../server/test/core_jwt.test.js), [server/test/password_reset.test.js](../../server/test/password_reset.test.js), [server/test/fix_sx2_auth.test.js](../../server/test/fix_sx2_auth.test.js)

**Bkz.:** [sunucu-token-401-gecersiz](#sunucu-token-401-gecersiz), [sunucu-profil-parola-degistirme-hata](#sunucu-profil-parola-degistirme-hata)

<a id="sunucu-oturum-401-kullanici-yok"></a>
### sunucu-oturum-401-kullanici-yok · Oturum açıkken tüm uçlar 401 "Kullanici bulunamadi." veriyor (hesap silinmiş)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:32](../../server/src/middlewares/auth_middleware.js#L32) | <code>return res.status(401).json({ error: 'Gecersiz token.' });</code> | Token sub alanı geçerli bir pozitif tamsayı değilse 401 |
| [server/src/middlewares/auth_middleware.js:36](../../server/src/middlewares/auth_middleware.js#L36) | <code>// Rol / aktiflik / onay durumu HER istekte DB'den TAZE okunur (token'daki role guvenilme…</code> | Rol/aktiflik her istekte users tablosundan okunur; token'daki rol önemsizdir |
| [server/src/middlewares/auth_middleware.js:61](../../server/src/middlewares/auth_middleware.js#L61) | <code>return res.status(401).json({ error: 'Kullanici bulunamadi.' });</code> | users satırı yoksa 401 |
| [server/src/routes/admin_routes.js:428](../../server/src/routes/admin_routes.js#L428) | <code>adminRouter.delete('/admin/users/:id', authRequired, requireSuperUser, async (req, res) =…</code> | Süper kullanıcının hesabı sildiği uç; silinen kullanıcının token'ı artık 401 alır |

**Olası nedenler**
- Süper kullanıcı hesabı sildi (DELETE /admin/users/:id)
- Başka veritabanına bağlanan test/staging sunucusundan alınmış token kullanılıyor

**Adım adım kontrol**
- SELECT user_code FROM users WHERE user_code = <token sub>
- Hesap silindiyse kullanıcı yeniden kayıt olmalıdır

**İlgili testler:** [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js)

**Bkz.:** [sunucu-token-401-gecersiz](#sunucu-token-401-gecersiz), [sunucu-admin-kullanici-silme-hata](#sunucu-admin-kullanici-silme-hata)

<a id="sunucu-oturum-403-hesap-pasif"></a>
### sunucu-oturum-403-hesap-pasif · Uygulama açıkken tüm uçlar 403 veriyor: "Hesap aktif degil." / "E-posta adresiniz dogrulanmadi." / "Abonelik talebiniz ..."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:79](../../server/src/middlewares/auth_middleware.js#L79) | <code>return res.status(403).json({ error: 'Hesap aktif degil.' });</code> | authRequired her istekte is_active kontrol eder (token geçerli olsa da) |
| [server/src/middlewares/auth_middleware.js:82](../../server/src/middlewares/auth_middleware.js#L82) | <code>return res.status(403).json({ error: 'E-posta adresiniz dogrulanmadi.' });</code> | email_verified = FALSE ise tüm korumalı uçlar 403 |
| [server/src/routes/auth_routes.js:877](../../server/src/routes/auth_routes.js#L877) | <code>await rotateLocalControlTokensForUserAccess(userCode, 'user_deactivated');</code> | Kullanıcı kendini pasif yapınca cihazların yerel kontrol tokenı döndürülür |
| [server/src/routes/admin_routes.js:409](../../server/src/routes/admin_routes.js#L409) | <code>return res.status(400).json({ error: 'Kendi hesabinizi pasif yapamazsiniz.' });</code> | Aktivasyon ucunda süper kullanıcı kendi hesabını pasif yapamaz (ilk eşleşme PATCH /admin/users/:id içindedir) |

**Olası nedenler**
- Hesap yönetici tarafından pasife alındı (PATCH /admin/users/:id/activation ya da PATCH /admin/users/:id)
- Kullanıcı PATCH /me ile is_active=false gönderdi
- Doğrulanmamış/onaylanmamış hesap için eski bir token kalmış

**Adım adım kontrol**
- SELECT user_code, is_active, email_verified, approval_status FROM users WHERE user_code = <id>
- Süper kullanıcı panelinden hesabı yeniden aktif edin

**İlgili testler:** [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js)

**Bkz.:** [sunucu-giris-403-onay-pasif-rol](#sunucu-giris-403-onay-pasif-rol)

<a id="sunucu-db-kesintisi-500-oturum-dusmuyor"></a>
### sunucu-db-kesintisi-500-oturum-dusmuyor · Tüm istekler 500 "Sunucu hatasi olustu. Lutfen daha sonra tekrar deneyin." dönüyor ama kullanıcılar çıkışa zorlanmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:7](../../server/src/middlewares/auth_middleware.js#L7) | <code>function isTokenVerificationError(error) {</code> | DB kesintisi/yapılandırma hatası token hatası sayılmaz -> 401 değil next(error) -> 500 |
| [server/src/middlewares/auth_middleware.js:37](../../server/src/middlewares/auth_middleware.js#L37) | <code>const result = await pool.query(</code> | Her istekte users sorgusu: veritabanı yoksa tüm korumalı uçlar hata verir |
| [server/src/middlewares/error_handler.js:103](../../server/src/middlewares/error_handler.js#L103) | <code>export function createErrorHandler({ logger = console } = {}) {</code> | Global hata yakalayıcı: 5xx'te genel mesaj + errorId, ayrıntı yalnız günlükte |
| [server/src/routes/firmware_routes.js:95](../../server/src/routes/firmware_routes.js#L95) | <code>firmwareRouter.get('/health', async (_req, res) =&gt; {</code> | /health veritabanı bağlantısını denetler (kopuksa 500 database: disconnected) |

**Olası nedenler**
- PostgreSQL kapsayıcısı (site_kapi_kontrol_postgres) durdu/yanıt vermiyor ya da bağlantı havuzu doldu
- Veritabanı parolası/ortamı değişti (.env DB_* değerleri)

**Adım adım kontrol**
- curl -s https://api.gudeteknoloji.com.tr/health -> ok:true ve database: connected olmalı
- Günlükte "[ERROR] <errorId> ..." satırının yığınına bakın (DB bağlantı hatası kodu)
- DB kapsayıcısını SSH ile docker ps üzerinden kontrol edin (yalnızca durum bakın, yeniden başlatmayın)

**Günlükte aranacak ifadeler**
- `[ERROR] `

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a '\[ERROR\]'"
```

**İlgili testler:** [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js), [server/test/core_error_handler.test.js](../../server/test/core_error_handler.test.js)

**Bkz.:** [altyapi-health-database-disconnected](20-sunucu-altyapi-ve-yayin.md#altyapi-health-database-disconnected), [sunucu-hata-500-errorid](#sunucu-hata-500-errorid)

<a id="sunucu-yetki-403-super-user"></a>
### sunucu-yetki-403-super-user · Panel/yönetim ucu 403 "Bu islem icin super user yetkisi gerekir." veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:98](../../server/src/middlewares/auth_middleware.js#L98) | <code>export function requireSuperUser(req, res, next) {</code> | Rol DB'den taze okunan req.authUser.role === super_user olmalı |
| [server/src/middlewares/auth_middleware.js:102](../../server/src/middlewares/auth_middleware.js#L102) | <code>.json({ error: 'Bu islem icin super user yetkisi gerekir.' });</code> | 403 yanıtı |
| [server/src/routes/admin_routes.js:149](../../server/src/routes/admin_routes.js#L149) | <code>adminRouter.get('/admin/users', authRequired, requireSuperUser, async (req, res) =&gt; {</code> | /admin/* uçlarının tamamı authRequired + requireSuperUser kullanır (örnek: kullanıcı listesi) |

**Olası nedenler**
- Giriş yapan kullanıcının rolü super_user değil (rol token'dan değil DB'den okunur; rol yeni değiştiyse hemen geçerlidir)
- Uygulama super_user dışı bir hesaba /admin/* çağrısı yapıyor (site yöneticisi /manager/* kullanmalı)

**Adım adım kontrol**
- SELECT user_code, role FROM users WHERE user_code = <id>
- İstemci yönetim önekini doğru seçiyor mu? (super_user: /admin, site yöneticisi: /manager)

**İlgili testler:** [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js)

**Bkz.:** [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi)

<a id="sunucu-yetki-403-site-yoneticisi"></a>
### sunucu-yetki-403-site-yoneticisi · Site yöneticisi uçları 403 veriyor: "Bu islem icin site yoneticisi yetkisi gerekir." / "Bu siteyi yonetme yetkiniz yok."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/auth_middleware.js:107](../../server/src/middlewares/auth_middleware.js#L107) | <code>export async function requireSiteManager(req, res, next) {</code> | Geçiş: rol site_manager/super_user VEYA site_manager_sites kaydı VEYA aktif SITE_OWNER/SITE_ADMIN üyeliği |
| [server/src/middlewares/auth_middleware.js:131](../../server/src/middlewares/auth_middleware.js#L131) | <code>.json({ error: 'Bu islem icin site yoneticisi yetkisi gerekir.' });</code> | Hiçbiri yoksa 403 |
| [server/src/services/site_service.js:293](../../server/src/services/site_service.js#L293) | <code>export async function hasSiteManagementAccess(authUser, siteCode) {</code> | Belirli bir site için yetki: super_user, site_manager_sites ya da SITE_OWNER/SITE_ADMIN üyeliği |
| [server/src/routes/manager_routes.js:226](../../server/src/routes/manager_routes.js#L226) | <code>return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });</code> | Site bazlı yetki yoksa uçlar bu mesajla 403 döner |

**Olası nedenler**
- Kullanıcı bu sitenin yöneticisi değil (site_manager_sites ve site_memberships satırı yok/pasif)
- Yöneticilik davetle verildiyse davet hesap açılışında (e-posta doğrulanınca) uygulanır; doğrulama öncesi yetki yoktur
- Başka sitenin kapı/daire/cihaz kimliği gönderiliyor (yetki o sitenin siteCode'una göre bakılır)

**Adım adım kontrol**
- SELECT * FROM site_manager_sites WHERE manager_user_code = <id>
- SELECT site_code, role, is_active FROM site_memberships WHERE user_code = <id>
- Bekleyen davet var mı: SELECT site_code, status, expires_at FROM site_manager_invitations WHERE LOWER(email)=LOWER('...')

**İlgili testler:** [server/test/sites_manager_rules.test.js](../../server/test/sites_manager_rules.test.js), [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js)

**Bkz.:** [sunucu-yonetici-daveti-eslesmedi](#sunucu-yonetici-daveti-eslesmedi), [sunucu-yetki-403-super-user](#sunucu-yetki-403-super-user)

<a id="sunucu-profil-parola-degistirme-hata"></a>
### sunucu-profil-parola-degistirme-hata · Profilde parola değişmiyor: "Mevcut parola hatali." / "Parolayi degistirmek icin mevcut parolanizi girmelisiniz." / 429 CURRENT_PASSWORD_LOCKED

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:771](../../server/src/routes/auth_routes.js#L771) | <code>authRouter.patch('/me', authRequired, async (req, res) =&gt; {</code> | Profil güncelleme ucu; parola değişiyorsa current_password ZORUNLU |
| [server/src/routes/auth_routes.js:827](../../server/src/routes/auth_routes.js#L827) | <code>code: 'CURRENT_PASSWORD_REQUIRED',</code> | 400: mevcut parola gönderilmemiş |
| [server/src/routes/auth_routes.js:830](../../server/src/routes/auth_routes.js#L830) | <code>const throttleKey = passwordChangeThrottleKey(userCode);</code> | Hesap bazlı yanlış-mevcut-parola sayacı anahtarı (u:<user_code>) |
| [server/src/routes/auth_routes.js:859](../../server/src/routes/auth_routes.js#L859) | <code>error: 'Mevcut parola hatali.',</code> | 400 (bilerek 401/403 değil: istemci oturum hatası sanıp çıkış yapmasın) |
| [server/src/middlewares/login_throttle.js:102](../../server/src/middlewares/login_throttle.js#L102) | <code>export const passwordChangeFailureTracker = createFailureTracker({ maxFailures: 5, window…</code> | 5 hata / 15 dk -> 15 dk kilit (429 CURRENT_PASSWORD_LOCKED) |
| [server/src/services/membership_service.js:2024](../../server/src/services/membership_service.js#L2024) | <code>const throttleKey = passwordChangeThrottleKey(tUserCode);</code> | Daire sakini change-password ucu AYNI kilidi paylaşır (bütçe ortak) |
| [server/src/utils/validators.js:125](../../server/src/utils/validators.js#L125) | <code>return 'Sifre en az 6 karakter olmali.';</code> | Yeni parola en az 6 karakter (validateUpdateInput); en çok 128 (route) |

**Olası nedenler**
- Mevcut parola yanlış yazıldı (parola kırpılarak karşılaştırılır)
- İstemci current_password göndermiyor (eski uygulama sürümü)
- 5 yanlış denemeden sonra 15 dk kilit: PATCH /me ve change-password ucu aynı sayacı kullanır
- Yeni parola 6 karakterden kısa ya da 128 karakterden uzun

**Adım adım kontrol**
- Yanıtın code alanına bakın: CURRENT_PASSWORD_REQUIRED / _INVALID / _LOCKED
- Kilit varsa retry_after_seconds kadar bekleyin ya da "Şifremi unuttum" akışıyla sıfırlayın (kilidi açar)

**İlgili testler:** [server/test/fix_sx2_auth.test.js](../../server/test/fix_sx2_auth.test.js), [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js)

**Bkz.:** [sunucu-token-revoked-parola-degisti](#sunucu-token-revoked-parola-degisti), [sunucu-yonetici-sakin-sifre-403](#sunucu-yonetici-sakin-sifre-403)

<a id="sunucu-profil-eposta-degistirilemiyor"></a>
### sunucu-profil-eposta-degistirilemiyor · Profilde/yönetim panelinde e-posta değiştirilemiyor: "E-posta adresi güvenlik nedeniyle değiştirilemez."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:820](../../server/src/routes/auth_routes.js#L820) | <code>return res.status(400).json({ error: 'E-posta adresi güvenlik nedeniyle değiştirilemez.' …</code> | PATCH /me: mevcut e-postadan farklı bir değer gönderilirse 400 |
| [server/src/routes/admin_routes.js:362](../../server/src/routes/admin_routes.js#L362) | <code>return res.status(400).json({ error: 'E-posta adresi güvenlik nedeniyle değiştirilemez.' …</code> | PATCH /admin/users/:id: süper kullanıcı için de aynı kural |
| [server/src/services/user_service.js:64](../../server/src/services/user_service.js#L64) | <code>export async function updateUserByCode({</code> | Güncelleme servisi (e-posta kuralı route katmanında uygulanır) |

**Olası nedenler**
- E-posta değişikliği bilerek kapalıdır (hesap devralma riskine karşı); yalnızca aynı değer gönderilebilir
- İstemci tüm profil alanlarını gönderirken e-postayı farklı büyük/küçük harfle gönderiyor değil: karşılaştırma küçük harfe çevrilerek yapılır, gerçek bir fark vardır

**Adım adım kontrol**
- E-posta gerçekten değişecekse yeni hesap açılmalı ya da DB'de yönetici müdahalesi gerekir (kod yolu yok)

**İlgili testler:** [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js)

<a id="sunucu-yonetici-sakin-sifre-403"></a>
### sunucu-yonetici-sakin-sifre-403 · Yönetici/site yöneticisi daire sakininin şifresini değiştiremiyor: 403 "Güvenlik kuralı: ... şifresini değiştiremez" ya da USE_PROFILE_PASSWORD_CHANGE

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:327](../../server/src/routes/admin_routes.js#L327) | <code>code: 'USE_PROFILE_PASSWORD_CHANGE',</code> | Süper kullanıcı kendi parolasını bu uçtan değiştiremez; Profilim (PATCH /me) kullanılmalı |
| [server/src/routes/admin_routes.js:370](../../server/src/routes/admin_routes.js#L370) | <code>error: 'Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez…</code> | apartment_owner/individual hesabının parolası yönetici tarafından değiştirilemez (403) |
| [server/src/services/membership_service.js:1979](../../server/src/services/membership_service.js#L1979) | <code>if (callerCode === null &#124;&#124; callerCode !== tUserCode) {</code> | change-password ucu yalnızca kullanıcının KENDİ şifresi içindir (yönetici olsa da 403) |
| [server/src/routes/membership_routes.js:268](../../server/src/routes/membership_routes.js#L268) | <code>'/membership/apartments/:apartmentId/members/:targetUserCode/change-password',</code> | Daire sakini şifre değiştirme ucu (current_password zorunlu) |

**Olası nedenler**
- Tasarım gereği: yöneticiler sakinlerin şifresini değiştiremez, sakin kendi hesabıyla girip değiştirir
- Sakin şifresini unuttuysa "Şifremi unuttum" akışı kullanılır (e-postası varsa); daire sakini için yönetici paneli kimlik bilgilerini yeniden gönderebilir

**Adım adım kontrol**
- Sakinin e-postası/kullanıcı adı kayıtlı mı? Yönetici "Giriş bilgilerini gönder" ucunu kullanabilir

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js), [server/test/members_claim_setup.test.js](../../server/test/members_claim_setup.test.js)

**Bkz.:** [sunucu-profil-parola-degistirme-hata](#sunucu-profil-parola-degistirme-hata), [sunucu-daire-bilgisi-eposta-gitmiyor](#sunucu-daire-bilgisi-eposta-gitmiyor)

<a id="sunucu-kayit-kod-gelmiyor"></a>
### sunucu-kayit-kod-gelmiyor · Kayıt olurken e-postaya doğrulama kodu gelmiyor ya da çok geç geliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_service.js:130](../../server/src/services/membership_service.js#L130) | <code>async function issueVerificationCode({ email, fullName, persistCredentials }) {</code> | Kod üretir, DB'ye yazar, e-posta gönderir; gönderim hatası fırlatılmaz, { sent:false } döner |
| [server/src/services/membership_service.js:177](../../server/src/services/membership_service.js#L177) | <code>console.error('[Mail Gönderim Hatası]:', describeMailError(mailError));</code> | SMTP hatasının günlüğe yazıldığı satır (code/responseCode alanları, adres maskeli) |
| [server/src/services/membership_service.js:92](../../server/src/services/membership_service.js#L92) | <code>function describeMailError(error) {</code> | Günlüğe giden alanlar: code (ETIMEDOUT, EAUTH...), responseCode (535, 550...), command |
| [server/src/mailer.js:85](../../server/src/mailer.js#L85) | <code>export async function sendIndividualVerificationEmail({</code> | Bireysel kayıt kod e-postası: konu "AHBU e-posta doğrulama kodunuz" |
| [server/src/mailer.js:24](../../server/src/mailer.js#L24) | <code>connectionTimeout: 10_000,</code> | SMTP zaman aşımları: bağlantı 10 sn, karşılama 10 sn, soket 20 sn |
| [server/src/config/env.js:130](../../server/src/config/env.js#L130) | <code>warnings.push(`SMTP ayarlari eksik: ${missingSmtp.join(', ')}; e-posta gonderilemez.`);</code> | Açılışta SMTP_HOST/SMTP_USER/SMTP_PASSWORD eksikse uyarı yazılır |

**Olası nedenler**
- SMTP kimlik doğrulama hatası (EAUTH, 535) ya da parola değişmiş
- SMTP bağlantı zaman aşımı (ETIMEDOUT/ECONNECTION): ağ ya da 587 portu engeli
- Alıcı sunucu reddetti (responseCode 550) ya da e-posta spam/gecikme kuyruğunda (kabul edildi ama geç ulaştı)
- Ortamda SMTP_HOST / SMTP_USER / SMTP_PASSWORD (veya SMTP_FROM) tanımsız
- Birden fazla kod istendi: yalnızca EN SON istenen kod geçerlidir; e-postadaki saat hangisinin son olduğunu gösterir

**Adım adım kontrol**
- Gönderim başarısızsa istemci 503 EMAIL_DELIVERY_FAILED alır; başarılı yanıt "kod gönderildi" demişse sunucu SMTP'ye kabul ettirmiştir (sorun alıcı/gönderen kuyruğundadır)
- Günlükte "Mail Gönderim" satırının code ve responseCode alanlarına bakın
- Kabul edildi ama ulaşmıyorsa: alıcı spam klasörü, gönderen sunucunun kuyruğu ve DNS (SPF/DKIM) — ayrıntı docs/EPOSTA_DOGRULAMA.md
- Kod 30 dk geçerlidir; kullanıcı beklemeden "Tekrar gönder" ile yeni kod istemeli (30 sn bekleme vardır)

**Günlükte aranacak ifadeler**
- `[Mail Gönderim Hatası]`
- `SMTP ayarlari eksik`
- `[resend-code] gonderim basarisiz:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Mail G.nderim'"
```

**İlgili testler:** [server/test/members_verification.test.js](../../server/test/members_verification.test.js), [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/mailer.test.js](../../server/test/mailer.test.js)

**Bkz.:** [sunucu-kayit-503-eposta-gonderilemedi](#sunucu-kayit-503-eposta-gonderilemedi), [sunucu-tekrar-gonder-hep-basarili](#sunucu-tekrar-gonder-hep-basarili), [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-kayit-429-bekleme-sinir](#sunucu-kayit-429-bekleme-sinir)

<a id="sunucu-kayit-503-eposta-gonderilemedi"></a>
### sunucu-kayit-503-eposta-gonderilemedi · Kayıt 503 veriyor: "Doğrulama kodu şu anda e-posta ile gönderilemiyor. Lütfen birkaç dakika sonra tekrar deneyiniz." (EMAIL_DELIVERY_FAILED)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:58](../../server/src/routes/auth_routes.js#L58) | <code>if (error?.code === 'EMAIL_DELIVERY_FAILED' &amp;&amp; error.expose === true) {</code> | 503 + Retry-After: 60 yanıtı (respondWithServiceError 5xx mesajını gizlediği için burada üretilir) |
| [server/src/services/membership_rules.js:109](../../server/src/services/membership_rules.js#L109) | <code>export function verificationIssueError(result) {</code> | MAIL_FAILED -> 503 EMAIL_DELIVERY_FAILED; COOLDOWN/HOURLY_CAP -> 429 |
| [server/src/services/membership_service.js:287](../../server/src/services/membership_service.js#L287) | <code>const issued = await issueVerificationCode({ email: cleanEmail, fullName, persistCredenti…</code> | Gönderilemediyse hata fırlatılır; kullanıcıya hiç gönderilmemiş kod vaat edilmez |
| [server/src/services/membership_service.js:107](../../server/src/services/membership_service.js#L107) | <code>async function discardUndeliveredCode(codeRowId) {</code> | Gönderilemeyen kod satırı silinir: bekleme süresi/saatlik tavan tüketilmez, hemen yeniden denenebilir |

**Olası nedenler**
- SMTP sunucusuna ulaşılamıyor / kimlik doğrulama hatası / zaman aşımı (günlükte "[Mail Gönderim Hatası]")
- SMTP ortam değişkenleri eksik

**Adım adım kontrol**
- Günlükte aynı anda "[Mail Gönderim Hatası]:" satırının code/responseCode değerlerine bakın
- SMTP'yi düzeltin; kullanıcı birkaç dakika sonra aynı formu tekrar gönderebilir (bekleme sayacı tüketilmedi)

**Günlükte aranacak ifadeler**
- `[Mail Gönderim Hatası]`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Mail G.nderim'"
```

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/members_verification.test.js](../../server/test/members_verification.test.js)

**Bkz.:** [sunucu-kayit-kod-gelmiyor](#sunucu-kayit-kod-gelmiyor), [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp)

<a id="sunucu-kayit-429-bekleme-sinir"></a>
### sunucu-kayit-429-bekleme-sinir · Kayıt/kod isteme 429 veriyor: "Yeni kod istemek için lütfen N saniye bekleyiniz." / "Bu e-posta adresi için çok fazla kod istendi" / "Cok fazla kayit denemesi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_rules.js:33](../../server/src/services/membership_rules.js#L33) | <code>export const VERIFICATION_RESEND_COOLDOWN_SECONDS = 30;</code> | Aynı e-posta için iki kod arası en az 30 sn |
| [server/src/services/membership_rules.js:34](../../server/src/services/membership_rules.js#L34) | <code>export const VERIFICATION_MAX_CODES_PER_HOUR = 10;</code> | E-posta başına saatte en çok 10 kod |
| [server/src/services/membership_rules.js:83](../../server/src/services/membership_rules.js#L83) | <code>export function decideVerificationIssue({ secondsSinceLast, codesLastHour }) {</code> | Bekleme/tavan kararı (COOLDOWN, HOURLY_CAP) |
| [server/src/middlewares/rate_limiters.js:215](../../server/src/middlewares/rate_limiters.js#L215) | <code>export const registerLimiter = createRuleLimiter({</code> | Kayıt ucu: IP+e-posta 5/15 dk, IP 40/saat |
| [server/src/middlewares/rate_limiters.js:232](../../server/src/middlewares/rate_limiters.js#L232) | <code>export const resendCodeLimiter = createRuleLimiter({</code> | Tekrar gönder: IP+e-posta 3/10 dk, e-posta 6/saat, IP 30/saat |

**Olası nedenler**
- Kullanıcı 30 sn dolmadan tekrar kod istedi (yanıt kalan saniyeyi söyler)
- Bir saatte 10'dan çok kod istendi ya da IP/e-posta hız sınırı aşıldı (Retry-After başlığı süreyi verir)
- Aynı IP'yi paylaşan çok kullanıcı (NAT) kayıt oluyor

**Adım adım kontrol**
- Retry-After / mesajdaki saniye kadar bekleyin
- SELECT COUNT(*), MAX(created_at) FROM email_verifications WHERE LOWER(email)=LOWER('...') AND created_at > NOW() - INTERVAL '1 hour'

**İlgili testler:** [server/test/members_membership_rules.test.js](../../server/test/members_membership_rules.test.js), [server/test/core_rate_limiter.test.js](../../server/test/core_rate_limiter.test.js)

**Bkz.:** [sunucu-kayit-kod-gelmiyor](#sunucu-kayit-kod-gelmiyor), [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-kayit-409-zaten-kayitli"></a>
### sunucu-kayit-409-zaten-kayitli · Kayıt 409 veriyor: "Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_service.js:242](../../server/src/services/membership_service.js#L242) | <code>const alreadyRegisteredError = () =&gt;</code> | 409 metni burada tanımlı |
| [server/src/services/membership_service.js:263](../../server/src/services/membership_service.js#L263) | <code>if (existing.role !== 'individual') {</code> | Başka rolde (örn. site_manager, apartment_owner) doğrulanmamış hesap da 409 verir: şifresi bu uçtan ezilemez |
| [server/src/services/membership_service.js:405](../../server/src/services/membership_service.js#L405) | <code>if (insertError?.code === '23505') {</code> | Doğrulama anında araya aynı e-postayla hesap girmişse 409 ve işlem geri alınır |
| [server/src/routes/auth_routes.js:45](../../server/src/routes/auth_routes.js#L45) | <code>authRouter.post('/auth/register-individual', registerLimiter, async (req, res) =&gt; {</code> | Bireysel kayıt ucu |

**Olası nedenler**
- E-posta zaten doğrulanmış bir hesapta kayıtlı (kullanıcı giriş yapmalı ya da şifresini sıfırlamalı)
- E-posta başka rolde (yönetici/daire sakini) bir hesaba ait
- Yönetici davetiyle aynı e-posta ile hesap oluşturulmuş olabilir

**Adım adım kontrol**
- SELECT user_code, role, email_verified FROM users WHERE LOWER(email)=LOWER('...')
- Kullanıcıyı "Şifremi unuttum" akışına yönlendirin

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js)

**Bkz.:** [sunucu-sifre-sifirlama-mail-gelmiyor](#sunucu-sifre-sifirlama-mail-gelmiyor), [sunucu-giris-401](#sunucu-giris-401)

<a id="sunucu-kayit-400-girdi"></a>
### sunucu-kayit-400-girdi · Kayıt formu 400 veriyor: "Ad ve soyad alanları zorunludur." / "Geçerli bir e-posta adresi giriniz." / "Şifre en az 6 karakter olmalıdır."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_service.js:226](../../server/src/services/membership_service.js#L226) | <code>throw httpError(400, 'Ad ve soyad alanları zorunludur.');</code> | Ad ve soyad boş olamaz (en çok 80 karakter) |
| [server/src/services/membership_service.js:235](../../server/src/services/membership_service.js#L235) | <code>throw httpError(400, 'Şifre en az 6 karakter olmalıdır.');</code> | Şifre 6-128 karakter |
| [server/src/utils/validators.js:49](../../server/src/utils/validators.js#L49) | <code>export function isValidEmail(raw) {</code> | E-posta biçim denetimi (alan adında nokta zorunlu, 254 karakter sınırı) |
| [server/src/routes/auth_routes.js:64](../../server/src/routes/auth_routes.js#L64) | <code>logLabel: 'register-individual',</code> | Hatalar respondWithServiceError ile yanıtlanır (4xx mesajı istemciye gider) |

**Olası nedenler**
- İstemci alan adlarını farklı gönderiyor (beklenen: first_name, last_name, email, password)
- E-posta biçimi geçersiz (alan adı noktasız, boşluk, çift nokta)
- Şifre 6 karakterden kısa ya da 128'den uzun

**Adım adım kontrol**
- Yanıtın error alanındaki metni kod satırıyla eşleştirin (hata mesajları klavuzu)

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/validators.test.js](../../server/test/validators.test.js)

**Bkz.:** [sunucu-kayit-409-zaten-kayitli](#sunucu-kayit-409-zaten-kayitli)

<a id="sunucu-dogrulama-kod-hatali-400"></a>
### sunucu-dogrulama-kod-hatali-400 · Doğrulama kodu girilince 400 "Girdiğiniz 6 haneli kod hatalıdır." (kod doğru görünüyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:70](../../server/src/routes/auth_routes.js#L70) | <code>authRouter.post('/auth/verify-code', verifyCodeLimiter, async (req, res) =&gt; {</code> | Doğrulama ucu |
| [server/src/services/membership_service.js:366](../../server/src/services/membership_service.js#L366) | <code>const isMatch = await bcrypt.compare(cleanCode, record.code_hash);</code> | Kod, EN SON açık kodun bcrypt özetiyle karşılaştırılır |
| [server/src/services/membership_service.js:371](../../server/src/services/membership_service.js#L371) | <code>throw httpError(400, `Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır.`);</code> | Hatalı kod yanıtı; deneme sayacı COMMIT ile kalıcı artar |
| [server/src/services/membership_rules.js:44](../../server/src/services/membership_rules.js#L44) | <code>export function isValidVerificationCodeFormat(code) {</code> | Biçim: 6 haneli (geçiş için 4 haneli de) rakam |
| [server/src/services/membership_rules.js:246](../../server/src/services/membership_rules.js#L246) | <code>export const SQL_SUPERSEDE_OLDER_VERIFICATION_CODES = `</code> | Yeni kod başarıyla gönderilince daha eski açık kodlar kapatılır |

**Olası nedenler**
- Kullanıcı önceki e-postadaki kodu giriyor: birden fazla kod istenmişse yalnızca EN SON istenen kod geçerlidir
- Kod yanlış yazıldı (her yanlış deneme kod başına 5 hakkın birini harcar)
- Kod satırı yazıldı ama e-posta gönderimi sürerken önceki kod girildi (yeni satırla karşılaştırılır)
- E-posta farklı yazılmış (kodlar e-posta adresine göre aranır; küçük harfe çevrilir)

**Adım adım kontrol**
- Kullanıcıya e-postadaki saati kontrol ettirip en son gelen kodu girmesini söyleyin
- SELECT id, attempt_count, is_verified, created_at FROM email_verifications WHERE LOWER(email)=LOWER('...') ORDER BY id DESC LIMIT 5

**İlgili testler:** [server/test/members_verification.test.js](../../server/test/members_verification.test.js), [server/test/members_membership_rules.test.js](../../server/test/members_membership_rules.test.js)

**Bkz.:** [sunucu-dogrulama-429-deneme-asildi](#sunucu-dogrulama-429-deneme-asildi), [sunucu-dogrulama-404-bekleyen-kayit-yok](#sunucu-dogrulama-404-bekleyen-kayit-yok)

<a id="sunucu-dogrulama-429-deneme-asildi"></a>
### sunucu-dogrulama-429-deneme-asildi · Doğrulama 429 veriyor: "Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz." / "Lütfen 30 dakika sonra tekrar deneyiniz."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_rules.js:29](../../server/src/services/membership_rules.js#L29) | <code>export const VERIFICATION_MAX_ATTEMPTS_PER_CODE = 5;</code> | Kod başına en çok 5 deneme |
| [server/src/services/membership_rules.js:32](../../server/src/services/membership_rules.js#L32) | <code>export const VERIFICATION_MAX_ATTEMPTS_PER_WINDOW = 10;</code> | 30 dk pencerede e-posta başına toplam 10 deneme (yeni kod istemek sayacı sıfırlamaz) |
| [server/src/services/membership_rules.js:51](../../server/src/services/membership_rules.js#L51) | <code>export function classifyVerificationDenial({ hasActiveCode, codeAttempts, windowAttempts …</code> | Reddin nedeni: NO_ACTIVE_CODE / CODE_ATTEMPTS_EXCEEDED / WINDOW_ATTEMPTS_EXCEEDED |
| [server/src/services/membership_rules.js:64](../../server/src/services/membership_rules.js#L64) | <code>export function verificationDenialError(reason) {</code> | Nedene göre 404/429 mesajı |
| [server/src/middlewares/rate_limiters.js:223](../../server/src/middlewares/rate_limiters.js#L223) | <code>export const verifyCodeLimiter = createRuleLimiter({</code> | İstek sınırı: IP+e-posta 10/15 dk, e-posta 20/15 dk ("Cok fazla dogrulama denemesi") |

**Olası nedenler**
- Aynı kod için 5 yanlış deneme: yeni kod istenmeli
- Son 30 dakikada toplam 10 yanlış deneme: 30 dakika beklenmeli (yeni kod isteyerek aşılamaz)
- IP/e-posta bazlı istek sınırı (verifyCodeLimiter) aşıldı

**Adım adım kontrol**
- SELECT attempt_count, created_at FROM email_verifications WHERE LOWER(email)=LOWER('...') AND created_at > NOW() - INTERVAL '30 minutes'
- Kullanıcıya yeni kod isteyip en son gelen kodu dikkatle girmesini söyleyin

**İlgili testler:** [server/test/members_verification.test.js](../../server/test/members_verification.test.js), [server/test/members_membership_rules.test.js](../../server/test/members_membership_rules.test.js)

**Bkz.:** [sunucu-dogrulama-kod-hatali-400](#sunucu-dogrulama-kod-hatali-400), [sunucu-kayit-429-bekleme-sinir](#sunucu-kayit-429-bekleme-sinir)

<a id="sunucu-dogrulama-404-bekleyen-kayit-yok"></a>
### sunucu-dogrulama-404-bekleyen-kayit-yok · Doğrulama 404 veriyor: "Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz." ya da "Aktif bir doğrulama kodu bulunamadı."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_service.js:392](../../server/src/services/membership_service.js#L392) | <code>throw httpError(404, 'Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz.');</code> | Kod doğru ama bekleyen kayıt silinmiş: işlem geri alınır (kod tüketilmez) |
| [server/src/services/membership_rules.js:167](../../server/src/services/membership_rules.js#L167) | <code>export const SQL_TAKE_PENDING_REGISTRATION = `</code> | Bekleyen kayıt DELETE ... RETURNING ile atomik alınır |
| [server/src/services/membership_rules.js:28](../../server/src/services/membership_rules.js#L28) | <code>export const VERIFICATION_CODE_TTL_MINUTES = 30;</code> | Kod 30 dk geçerli; süre dolunca aktif kod bulunamaz |
| [server/src/services/maintenance_service.js:46](../../server/src/services/maintenance_service.js#L46) | <code>DELETE FROM pending_registrations</code> | Bakım: 2 günden eski bekleyen kayıtlar silinir (hesap silmez) |

**Olası nedenler**
- Kod 30 dakikadan eski (aktif kod yok): yeniden kod istenmeli
- Bekleyen kayıt 2 günden eski olduğu için günlük bakımla silindi: kullanıcı yeniden kayıt olmalı
- Doğrulama başka bir cihazdan/aynı e-posta ile yapılıp bekleyen kayıt alındı

**Adım adım kontrol**
- SELECT email, updated_at FROM pending_registrations WHERE LOWER(email)=LOWER('...')
- Kayıt yoksa kullanıcı kayıt formunu yeniden doldurmalı (aynı e-posta, yeni kod)

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js)

**Bkz.:** [sunucu-dogrulama-kod-hatali-400](#sunucu-dogrulama-kod-hatali-400), [sunucu-giris-403-eposta-dogrulanmadi](#sunucu-giris-403-eposta-dogrulanmadi), [altyapi-bakim-temizlik-hatasi](20-sunucu-altyapi-ve-yayin.md#altyapi-bakim-temizlik-hatasi)

<a id="sunucu-tekrar-gonder-hep-basarili"></a>
### sunucu-tekrar-gonder-hep-basarili · "Tekrar gönder" her zaman başarılı görünüyor ama kod gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:89](../../server/src/routes/auth_routes.js#L89) | <code>authRouter.post('/auth/resend-code', resendCodeLimiter, async (req, res) =&gt; {</code> | Yanıt HER durumda 200 ok:true; gönderim arka planda yapılır |
| [server/src/routes/auth_routes.js:98](../../server/src/routes/auth_routes.js#L98) | <code>console.error('[resend-code] gonderim basarisiz:', error?.statusCode &#124;&#124; error?.code &#124;&#124; er…</code> | Gönderim hatası yalnızca günlüğe yazılır (kullanıcı varlığı sızdırılmasın) |
| [server/src/services/membership_service.js:476](../../server/src/services/membership_service.js#L476) | <code>export async function resendIndividualVerificationCode({ email }) {</code> | Hesap yoksa ya da doğrulanmışsa kod gönderilmez |
| [server/src/services/membership_service.js:504](../../server/src/services/membership_service.js#L504) | <code>void issueVerificationCode({ email: cleanEmail, fullName }).catch((error) =&gt; {</code> | Bekleme (30 sn) ve saatlik tavan burada da geçerlidir; reddedilirse sessizce gönderilmez |

**Olası nedenler**
- E-posta için bekleyen kayıt/doğrulanmamış hesap yok (ör. 2 gün geçip silindi ya da hesap zaten doğrulanmış): gönderim yapılmaz, yanıt yine ok
- 30 sn bekleme ya da saatte 10 kod tavanı: sessizce atlanır
- SMTP hatası: yalnızca günlükte görünür

**Adım adım kontrol**
- Günlükte "[resend-code] gonderim basarisiz:" ve "[Mail Gönderim Hatası]" satırlarını arayın
- users ve pending_registrations tablolarında e-posta var mı bakın

**Günlükte aranacak ifadeler**
- `[resend-code] gonderim basarisiz:`
- `[Mail Gönderim Hatası]`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -E 'resend-code|Mail G.nderim'"
```

**İlgili testler:** [server/test/members_verification.test.js](../../server/test/members_verification.test.js), [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js)

**Bkz.:** [sunucu-kayit-kod-gelmiyor](#sunucu-kayit-kod-gelmiyor), [sunucu-dogrulama-404-bekleyen-kayit-yok](#sunucu-dogrulama-404-bekleyen-kayit-yok)

<a id="sunucu-sifre-sifirlama-mail-gelmiyor"></a>
### sunucu-sifre-sifirlama-mail-gelmiyor · "Şifremi unuttum" başarılı görünüyor ama sıfırlama e-postası gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:320](../../server/src/routes/auth_routes.js#L320) | <code>authRouter.post('/auth/forgot-password', forgotPasswordLimiter, async (req, res) =&gt; {</code> | Yanıt her durumda aynı (200 ok:true); işlem arka planda |
| [server/src/routes/auth_routes.js:338](../../server/src/routes/auth_routes.js#L338) | <code>if (userRes.rowCount === 0 &#124;&#124; !userRes.rows[0].is_active) {</code> | Hesap yoksa ya da pasifse sessizce çıkılır (e-posta gitmez) |
| [server/src/routes/auth_routes.js:288](../../server/src/routes/auth_routes.js#L288) | <code>async function issuePasswordReset(user) {</code> | Token üretir (sha256 özeti DB'de), 30 dk süre verir, e-posta gönderir |
| [server/src/routes/auth_routes.js:343](../../server/src/routes/auth_routes.js#L343) | <code>console.error('[forgot-password] islem basarisiz:', error?.code &#124;&#124; error?.message);</code> | SMTP/DB hatası yalnızca günlüğe yazılır |
| [server/src/middlewares/rate_limiters.js:241](../../server/src/middlewares/rate_limiters.js#L241) | <code>export const forgotPasswordLimiter = createRuleLimiter({</code> | IP+e-posta 3/15 dk, e-posta 5/saat, IP 30/saat |
| [server/src/mailer.js:373](../../server/src/mailer.js#L373) | <code>export async function sendPasswordResetEmail({</code> | Sıfırlama e-postası şablonu (bağlantı + 30 dk bilgisi) |

**Olası nedenler**
- E-posta users tablosunda yok: yalnızca e-postası DOĞRULANMAMIŞ (bekleyen) kayıt olan kullanıcı için users satırı yoktur, sıfırlama gitmez; önce kayıt doğrulaması tamamlanmalı
- Hesap pasif (is_active = FALSE)
- SMTP hatası (günlükte "[forgot-password] islem basarisiz:")
- İstek hız sınırına takıldı (429 "Cok fazla sifre sifirlama istegi")

**Adım adım kontrol**
- SELECT user_code, is_active FROM users WHERE LOWER(email)=LOWER('...')
- Günlükte forgot-password satırına ve SMTP hatasına bakın

**Günlükte aranacak ifadeler**
- `[forgot-password] islem basarisiz:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -E 'forgot-password|Mail G.nderim'"
```

**İlgili testler:** [server/test/password_reset.test.js](../../server/test/password_reset.test.js)

**Bkz.:** [sunucu-sifre-sifirlama-baglanti-gecersiz](#sunucu-sifre-sifirlama-baglanti-gecersiz), [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-giris-hesap-kilitli-429](#sunucu-giris-hesap-kilitli-429)

<a id="sunucu-sifre-sifirlama-baglanti-gecersiz"></a>
### sunucu-sifre-sifirlama-baglanti-gecersiz · Şifre sıfırlama bağlantısı "geçersiz veya daha önce kullanılmış" / "süresi dolmuş (30 dakika)" diyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:354](../../server/src/routes/auth_routes.js#L354) | <code>authRouter.get('/auth/reset-password', resetPasswordLimiter, async (req, res) =&gt; {</code> | Web sayfası: 400 (token yok), 404 (biçim/özet yok), 410 (süre dolmuş) |
| [server/src/routes/auth_routes.js:274](../../server/src/routes/auth_routes.js#L274) | <code>const RESET_TOKEN_PATTERN = /^[0-9a-f]{64}$/i;</code> | Token tam 64 onaltılık karakter olmalı (e-posta istemcisi bağlantıyı kırparsa 404) |
| [server/src/routes/auth_routes.js:412](../../server/src/routes/auth_routes.js#L412) | <code>authRouter.post('/auth/reset-password', resetPasswordLimiter, async (req, res) =&gt; {</code> | Parolayı güncelleyen uç |
| [server/src/routes/auth_routes.js:462](../../server/src/routes/auth_routes.js#L462) | <code>AND password_reset_expires_at &gt; NOW()</code> | Atomik tek kullanım: süre dolmuş ya da zaten kullanılmışsa güncelleme 0 satır -> 400 |
| [server/src/routes/auth_routes.js:304](../../server/src/routes/auth_routes.js#L304) | <code>process.env.PUBLIC_APP_URL &#124;&#124;</code> | Bağlantının kök adresi PUBLIC_APP_URL / PUBLIC_BASE_URL (yoksa api.gudeteknoloji.com.tr) |

**Olası nedenler**
- Bağlantı 30 dakikadan eski
- Kullanıcı sonradan yeni sıfırlama istedi: kullanıcı başına tek token tutulur, yeni talep eskisini geçersiz kılar
- Bağlantı zaten kullanıldı (tek kullanımlık)
- E-posta istemcisi/koruma yazılımı bağlantıyı değiştirdi (token 64 hex değil)
- PUBLIC_APP_URL yanlış ayarlı: bağlantı yanlış adrese gidiyor

**Adım adım kontrol**
- Kullanıcıdan yeni bir sıfırlama isteyip yalnızca EN SON gelen e-postadaki bağlantıyı açmasını isteyin
- SELECT password_reset_expires_at FROM users WHERE LOWER(email)=LOWER('...') (token özeti seçilmez)
- Bağlantının başındaki adres beklenen API adresi mi (PUBLIC_APP_URL)?

**İlgili testler:** [server/test/password_reset.test.js](../../server/test/password_reset.test.js)

**Bkz.:** [sunucu-sifre-sifirlama-mail-gelmiyor](#sunucu-sifre-sifirlama-mail-gelmiyor), [sunucu-giris-hesap-kilitli-429](#sunucu-giris-hesap-kilitli-429)

<a id="sunucu-eski-kayit-uclari-410"></a>
### sunucu-eski-kayit-uclari-410 · Eski uygulama sürümünde kayıt/abonelik 410 veriyor: "Yeni kullanici kaydi yalnizca super user tarafindan yapilir." / "Site yoneticisi onay akisi kapatildi."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/auth_routes.js:491](../../server/src/routes/auth_routes.js#L491) | <code>authRouter.post('/auth/register', async (req, res) =&gt; {</code> | Eski genel kayıt ucu: 410 |
| [server/src/routes/auth_routes.js:534](../../server/src/routes/auth_routes.js#L534) | <code>authRouter.post('/auth/site-manager/register', async (req, res) =&gt; {</code> | Eski site yöneticisi kayıt ucu: 410 |
| [server/src/routes/auth_routes.js:636](../../server/src/routes/auth_routes.js#L636) | <code>authRouter.post('/auth/site-manager/verify-email', async (req, res) =&gt; {</code> | Eski yönetici doğrulama ucu: 410 |
| [server/src/routes/auth_routes.js:643](../../server/src/routes/auth_routes.js#L643) | <code>authRouter.post('/auth/site-manager/resend-code', async (req, res) =&gt; {</code> | Eski yönetici kod ucu: 410 |

**Olası nedenler**
- Uygulama sürümü eski: yeni kayıt ucu POST /auth/register-individual ve POST /auth/verify-code kullanılır
- Site yöneticisi artık kayıt olmaz: cihaz sahiplenme veya yönetici daveti ile yetki alır

**Adım adım kontrol**
- Uygulamayı güncelleyin; yeni sürüm bireysel kayıt ucunu çağırır

**İlgili testler:** [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js)

**Bkz.:** [sunucu-kayit-409-zaten-kayitli](#sunucu-kayit-409-zaten-kayitli)

<a id="sunucu-eposta-hic-cikmiyor-smtp"></a>
### sunucu-eposta-hic-cikmiyor-smtp · Sunucudan hiçbir e-posta çıkmıyor (kayıt kodu, şifre sıfırlama, yönetici daveti, daire giriş bilgisi, silme kodu)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mailer.js:3](../../server/src/mailer.js#L3) | <code>function requiredEnv(name) {</code> | SMTP_HOST/SMTP_USER/SMTP_PASSWORD eksikse "<AD> env degiskeni eksik." hatası fırlatır |
| [server/src/mailer.js:11](../../server/src/mailer.js#L11) | <code>function createTransporter() {</code> | Port 465 ise secure, aksi halde STARTTLS zorunlu (requireTLS); zaman aşımları sınırlı |
| [server/src/mailer.js:13](../../server/src/mailer.js#L13) | <code>const port = Number(process.env.SMTP_PORT &#124;&#124; 587);</code> | Varsayılan port 587 |
| [server/src/config/env.js:130](../../server/src/config/env.js#L130) | <code>warnings.push(`SMTP ayarlari eksik: ${missingSmtp.join(', ')}; e-posta gonderilemez.`);</code> | Açılış uyarısı: eksik SMTP değişkenleri listelenir |

**Olası nedenler**
- .env içinde SMTP_HOST / SMTP_USER / SMTP_PASSWORD (ve SMTP_FROM) eksik ya da yanlış
- SMTP parolası değişti (EAUTH 535)
- Sunucudan 587 çıkışı engelli / posta sunucusu yanıt vermiyor (ETIMEDOUT)

**Adım adım kontrol**
- Açılış günlüğünde "[ENV] UYARI: SMTP ayarlari eksik" satırı var mı
- Hata satırlarında code ve responseCode alanlarına bakın; kimlik doğrulama için yalnızca bağlantı/kimlik testi yapın (e-posta göndermeden), .env değerlerini ASLA yazdırmayın
- Ayrıntılı işletme teşhisi: docs/EPOSTA_DOGRULAMA.md (SMTP testi, DNS, kuyruk)

**Günlükte aranacak ifadeler**
- `SMTP ayarlari eksik`
- `[Mail Gönderim Hatası]`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -E 'SMTP|Mail G.nderim|Mailer'"
```

**İlgili testler:** [server/test/mailer.test.js](../../server/test/mailer.test.js), [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [sunucu-kayit-kod-gelmiyor](#sunucu-kayit-kod-gelmiyor), [sunucu-sifre-sifirlama-mail-gelmiyor](#sunucu-sifre-sifirlama-mail-gelmiyor), [sunucu-yonetici-daveti-mail-yok](#sunucu-yonetici-daveti-mail-yok)

<a id="sunucu-kapi-acma-404-yetki"></a>
### sunucu-kapi-acma-404-yetki · Kapı açma isteği 404 "Kapi bulunamadi." dönüyor (kapı var ama kullanıcı açamıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/app_doors_routes.js:156](../../server/src/routes/app_doors_routes.js#L156) | <code>appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (r…</code> | Uzaktan kapı açma ucu; önce kullanıcının bu kapıya erişimi sorgulanır |
| [server/src/services/door_service.js:492](../../server/src/services/door_service.js#L492) | <code>export async function getAccessibleDoorForUser({ authUser, doorId }) {</code> | Kapı, kullanıcının erişebildiği kapılar listesinde yoksa null -> 404 |
| [server/src/services/door_service.js:379](../../server/src/services/door_service.js#L379) | <code>AND s.approval_status = 'approved'</code> | Süper kullanıcı dışında yalnızca ONAYLI sitelerin kapıları görünür |
| [server/src/services/door_service.js:382](../../server/src/services/door_service.js#L382) | <code>-- 1. Site Yöneticisi veya Site Sahibi / Admini (Tüm kapıları görür)</code> | Yönetici/site sahibi sitenin tüm kapılarına erişir |
| [server/src/services/door_service.js:441](../../server/src/services/door_service.js#L441) | <code>AND dao_neg.is_allowed = FALSE</code> | Kapıya özel "engelle" kaydı varsa sakin otomatik yetkisi çalışmaz |

**Olası nedenler**
- Kullanıcının bu kapıya yetkisi yok: aktif daire üyeliği/site üyeliği yok, katılım başvurusu henüz onaylanmamış ya da üyelik pasif
- Yönetici kapıyı bu kullanıcı için engelledi (door_access_overrides.is_allowed = FALSE)
- Sitenin approval_status değeri approved değil (bekliyor/reddedildi)
- Kapı pasif (site_doors.is_active = FALSE) ya da kapı kimliği başka bir siteye ait
- Kapı erişim kapsamı BLOCK ve sakin başka blokta oturuyor

**Adım adım kontrol**
- SELECT id, site_code, is_active, access_scope, block_id FROM site_doors WHERE id = <kapı>
- SELECT approval_status FROM sites WHERE site_code = <site>
- SELECT apartment_id, role, is_active FROM apartment_memberships WHERE user_code = <kullanıcı>
- SELECT is_allowed FROM door_access_overrides WHERE door_id = <kapı> AND user_code = <kullanıcı>

**İlgili testler:** [server/test/doors_service.test.js](../../server/test/doors_service.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js), [server/test/fix_sx2_door_owner.test.js](../../server/test/fix_sx2_door_owner.test.js)

**Bkz.:** [sunucu-sakin-kapi-listede-yok](#sunucu-sakin-kapi-listede-yok), [sunucu-kapi-acma-409-cihaz-atanmamis](#sunucu-kapi-acma-409-cihaz-atanmamis)

<a id="sunucu-sakin-kapi-listede-yok"></a>
### sunucu-sakin-kapi-listede-yok · Onaylanan sakin/yönetici kapıyı uygulamada göremiyor ("Kapılarım" listesi boş ya da eksik)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/app_doors_routes.js:104](../../server/src/routes/app_doors_routes.js#L104) | <code>appDoorsRouter.get('/app/my-doors', authRequired, async (req, res) =&gt; {</code> | Kullanıcının erişebildiği kapı listesi |
| [server/src/services/door_service.js:277](../../server/src/services/door_service.js#L277) | <code>export async function listAccessibleDoorsForUser(authUser, { doorId = null } = {}) {</code> | Tüm erişim kuralları tek SQL'de: yönetici, ek izin, sakin otomatik yetkisi |
| [server/src/services/door_service.js:394](../../server/src/services/door_service.js#L394) | <code>-- 2. Özel Kapı İzni (Manuel ek yetki verilmiş)</code> | Ek izin yalnızca üyeliği pasife alınmamış kullanıcı için çalışır |
| [server/src/services/door_service.js:444](../../server/src/services/door_service.js#L444) | <code>-- 3a. Sitenin tüm ortak kapıları (SITE_COMMON)</code> | Aktif daire üyesi/sakini sitenin SITE_COMMON kapılarını görür |
| [server/src/services/door_service.js:462](../../server/src/services/door_service.js#L462) | <code>-- 3b. Yalnızca sakinin kendi bloğuna ait kapılar (BLOCK)</code> | BLOCK kapsamlı kapı yalnızca o bloktaki sakinlere görünür |
| [server/src/services/membership_service.js:1276](../../server/src/services/membership_service.js#L1276) | <code>export async function approveJoinRequest({ requestId, authUser }) {</code> | Onay, apartment_memberships ve site_memberships (RESIDENT) kayıtlarını oluşturur |

**Olası nedenler**
- Katılım başvurusu PENDING (yönetici onaylamadı) ya da REJECTED
- Daire üyeliği pasife alındı (apartment_memberships.is_active = FALSE) veya daire pasif
- Kapı access_scope = BLOCK ve sakinin dairesi başka blokta
- Kapı sakine özel engellenmiş (is_allowed = FALSE) veya site onaylı değil
- Kapı pasif (is_active = FALSE)

**Adım adım kontrol**
- SELECT jr.status FROM join_requests jr WHERE jr.user_code = <kullanıcı> ORDER BY jr.id DESC LIMIT 3
- SELECT apartment_id, role, is_active FROM apartment_memberships WHERE user_code = <kullanıcı>
- SELECT id, access_scope, block_id, is_active FROM site_doors WHERE site_code = <site>

**İlgili testler:** [server/test/doors_service.test.js](../../server/test/doors_service.test.js), [server/test/fix_sx2_door_owner.test.js](../../server/test/fix_sx2_door_owner.test.js)

**Bkz.:** [sunucu-kapi-acma-404-yetki](#sunucu-kapi-acma-404-yetki), [sunucu-kapi-yetkisi-yonetimi-403](#sunucu-kapi-yetkisi-yonetimi-403), [sunucu-katilim-onay-hata](#sunucu-katilim-onay-hata)

<a id="sunucu-kapi-acma-409-cihaz-atanmamis"></a>
### sunucu-kapi-acma-409-cihaz-atanmamis · Kapı açma/durum 409 "Bu kapiya cihaz atanmamis." veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/app_doors_routes.js:172](../../server/src/routes/app_doors_routes.js#L172) | <code>return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });</code> | Açma ucunda cihaz atanmamışsa 409 (1. eşleşme durum ucunda, 3. eşleşme karekod ucundadır) |
| [server/src/services/door_service.js:504](../../server/src/services/door_service.js#L504) | <code>export async function unassignDoorDevice({ doorId, authUser = null }) {</code> | Yönetici kapıdan cihazı çıkarınca assigned_device_id boşalır |
| [server/src/services/device_service.js:991](../../server/src/services/device_service.js#L991) | <code>export async function releaseDeviceOwnership({ deviceId, authUser }) {</code> | Sahiplik sıfırlanınca cihaz kapıdan da sökülür |
| [server/src/routes/company_routes.js:159](../../server/src/routes/company_routes.js#L159) | <code>export async function removeCompanyDeviceRecord(db, deviceUid) {</code> | Şirket aracıyla cihaz silinince kapı ataması da temizlenir |

**Olası nedenler**
- Kapı için hiç cihaz atanmamış (yeni kurulan site: cihaz yalnızca 1. kapıya otomatik bağlanır)
- Yönetici cihazı kapıdan çıkardı (unassign) ya da değiştirme işlemi yarım kaldı
- Süper kullanıcı cihaz sahipliğini sıfırladı / cihazı sildi (kapı ataması kalkar)

**Adım adım kontrol**
- SELECT id, door_name, assigned_device_id FROM site_doors WHERE id = <kapı>
- Yönetici panelinden "kapıya cihaz ata" ile cihazı yeniden bağlayın

**İlgili testler:** [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js), [server/test/device_assignment.test.js](../../server/test/device_assignment.test.js)

**Bkz.:** [sunucu-kapi-cihaz-atama-403](#sunucu-kapi-cihaz-atama-403), [sunucu-kapi-acma-404-yetki](#sunucu-kapi-acma-404-yetki)

<a id="sunucu-kapi-acma-cihaz-offline"></a>
### sunucu-kapi-acma-cihaz-offline · Kapı açma 409 "Cihaz online gorunmuyor." (DEVICE_OFFLINE) ya da 503 "MQTT baglantisi hazir degil." veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/app_doors_routes.js:67](../../server/src/routes/app_doors_routes.js#L67) | <code>if (error?.code === 'DEVICE_OFFLINE') {</code> | Köprü cihazı çevrimdışı görüyorsa 409 DEVICE_OFFLINE |
| [server/src/routes/app_doors_routes.js:63](../../server/src/routes/app_doors_routes.js#L63) | <code>if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED') {</code> | Sunucunun MQTT köprüsü brokera bağlı değilse 503 |
| [server/src/routes/app_doors_routes.js:186](../../server/src/routes/app_doors_routes.js#L186) | <code>await publishDoorPulse({</code> | Komut MQTT ile yayınlanır (publishDoorPulse mqtt_bridge.js içindedir); başarılıysa 202 döner |
| [server/src/routes/app_doors_routes.js:116](../../server/src/routes/app_doors_routes.js#L116) | <code>appDoorsRouter.get('/app/doors/:id/status', authRequired, async (req, res) =&gt; {</code> | Cihaz çevrimiçi/IP/yerel kontrol durumu bu uçtan okunur |
| [server/src/routes/firmware_routes.js:95](../../server/src/routes/firmware_routes.js#L95) | <code>firmwareRouter.get('/health', async (_req, res) =&gt; {</code> | /health yanıtındaki mqtt alanı köprü durumunu gösterir |

**Olası nedenler**
- Cihaz Wi-Fi/MQTT'ye bağlı değil (elektrik, internet, router) ya da yeniden başlıyor
- Sunucudaki MQTT köprüsü broker ile bağlantısını kaybetti (broker/kimlik/ACL sorunu)
- Cihazın MQTT kimliği/ACL'i senkron değil (yeni cihaz ya da silinip yeniden eklenen cihaz)

**Adım adım kontrol**
- curl -s https://api.gudeteknoloji.com.tr/health çıktısındaki mqtt alanına bakın
- GET /app/doors/:id/status yanıtındaki device_status (mqtt_connected, last_seen) değerlerine bakın
- Kapıdan "yerel" (aynı ağdan) açma çalışıyor mu? Çalışıyorsa sorun bulut/MQTT yoludur
- Köprü/ACL ayrıntıları için MQTT alanına (mqtt_bridge, mqtt_acl_sync) bakın

**Günlükte aranacak ifadeler**
- `[app_doors] `

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a -i mqtt"
```

**İlgili testler:** [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js)

**Bkz.:** [altyapi-health-database-disconnected](20-sunucu-altyapi-ve-yayin.md#altyapi-health-database-disconnected), [altyapi-acl-senkron-503](20-sunucu-altyapi-ve-yayin.md#altyapi-acl-senkron-503)

<a id="sunucu-kapi-acma-429-cok-sik"></a>
### sunucu-kapi-acma-429-cok-sik · Kapı açma 429 "Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin." veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/rate_limiters.js:175](../../server/src/middlewares/rate_limiters.js#L175) | <code>export const doorCommandRateLimiter = createRuleLimiter({</code> | Kapı komutu: kullanıcı+yol başına 10 sn'de en çok 4 istek |
| [server/src/middlewares/rate_limiters.js:186](../../server/src/middlewares/rate_limiters.js#L186) | <code>message: 'Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin.',</code> | 429 metni |
| [server/src/routes/app_doors_routes.js:256](../../server/src/routes/app_doors_routes.js#L256) | <code>appDoorsRouter.post('/app/doors/scan-qr-open', authRequired, doorCommandRateLimiter, asyn…</code> | Aynı sınırlayıcı karekodla açma ve yerel açma bildirimi uçlarında da kullanılır |

**Olası nedenler**
- Uygulama/kullanıcı 10 saniyede 4'ten fazla komut gönderdi (çift dokunuş, otomatik yeniden deneme)
- Anahtar kullanıcı koduna ve yola bağlıdır: aynı kullanıcı farklı kapılar için ayrı sayılır

**Adım adım kontrol**
- Birkaç saniye bekleyin; uygulamanın yeniden deneme döngüsü varsa o düzeltilmeli

**İlgili testler:** [server/test/core_rate_limiter.test.js](../../server/test/core_rate_limiter.test.js)

**Bkz.:** [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-kapi-acma-403-uzaktan-kapali"></a>
### sunucu-kapi-acma-403-uzaktan-kapali · Kapı açma 403 "Bu sitede uygulama uzerinden uzaktan kapi acma yetkisi kapalidir." (REMOTE_OPEN_DISABLED)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_access_policy.js:66](../../server/src/services/door_access_policy.js#L66) | <code>code: 'REMOTE_OPEN_DISABLED',</code> | feature_remote_open_enabled === false ve kullanıcı super_user değilse red |
| [server/src/routes/app_doors_routes.js:176](../../server/src/routes/app_doors_routes.js#L176) | <code>assertDoorOpenAllowed({ door, channel: 'remote', authUser: req.authUser });</code> | Açma ucunda politika kontrolü (kanal: remote) |
| [server/src/utils/site_rules.js:392](../../server/src/utils/site_rules.js#L392) | <code>error: 'Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapila…</code> | Bu bayrağı yalnızca süper kullanıcı değiştirebilir (site yöneticisi 403 alır) |
| [server/src/routes/admin_routes.js:940](../../server/src/routes/admin_routes.js#L940) | <code>adminRouter.patch('/admin/sites/:id/features', authRequired, requireSuperUser, async (req…</code> | Süper kullanıcı site modüllerini (uzaktan açma/QR/yerel/misafir) buradan açar-kapatır |

**Olası nedenler**
- Sitede sites.feature_remote_open_enabled = FALSE (yönetim uzaktan açmayı kapatmış; kapı önü QR okuyucu kullanılmalı)
- Süper kullanıcı bu kısıtlamadan etkilenmez; yalnızca normal kullanıcılar reddedilir

**Adım adım kontrol**
- SELECT feature_remote_open_enabled, feature_qr_enabled FROM sites WHERE site_code = <site>
- Açılacaksa süper kullanıcı PATCH /admin/sites/:id/features ile bayrağı açar

**İlgili testler:** [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js), [server/test/sites_security_policy.test.js](../../server/test/sites_security_policy.test.js)

**Bkz.:** [sunucu-guvenlik-politikasi-hata](#sunucu-guvenlik-politikasi-hata), [sunucu-karekod-politika-kapali](#sunucu-karekod-politika-kapali)

<a id="sunucu-karekod-politika-kapali"></a>
### sunucu-karekod-politika-kapali · Karekodla geçiş reddediliyor: 403 "Bu sitede karekod ile kapi acma yetkisi kapalidir." (QR_DISABLED) / "karekod ile giris yonetim tarafindan gecici olarak durdurulmustur." (QR_ENTRY_INACTIVE)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_access_policy.js:80](../../server/src/services/door_access_policy.js#L80) | <code>code: 'QR_DISABLED',</code> | feature_qr_enabled === false -> red (super_user hariç) |
| [server/src/services/door_access_policy.js:87](../../server/src/services/door_access_policy.js#L87) | <code>code: 'QR_ENTRY_INACTIVE',</code> | qr_entry_active === false (yönetim geçici durdurdu) -> red |
| [server/src/services/qr_access_service.js:36](../../server/src/services/qr_access_service.js#L36) | <code>assertDoorOpenAllowed({ door, channel: 'qr', authUser });</code> | QR token üretiminde politika kontrolü |
| [server/src/utils/site_rules.js:420](../../server/src/utils/site_rules.js#L420) | <code>if (!effQr) {</code> | QR özelliği kapanınca qr_entry_active otomatik FALSE yapılır (kapalı özellik aktif olamaz) |
| [server/src/routes/manager_routes.js:256](../../server/src/routes/manager_routes.js#L256) | <code>managerRouter.patch('/manager/sites/:id/security-policy', authRequired, requireSiteManage…</code> | Yönetici qr_entry_active (geçici durdurma) ve geofence ayarlarını buradan değiştirir |

**Olası nedenler**
- Süper kullanıcı sitede karekod özelliğini kapattı (feature_qr_enabled = FALSE)
- Site yöneticisi karekodla girişi geçici durdurdu (qr_entry_active = FALSE)

**Adım adım kontrol**
- SELECT feature_qr_enabled, qr_entry_active FROM sites WHERE site_code = <site>
- Yönetici panelinden "karekod girişi" anahtarını açın (özellik kapalıysa önce süper kullanıcı açmalı)

**İlgili testler:** [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js), [server/test/sites_security_policy.test.js](../../server/test/sites_security_policy.test.js)

**Bkz.:** [sunucu-kapi-acma-403-uzaktan-kapali](#sunucu-kapi-acma-403-uzaktan-kapali), [sunucu-guvenlik-politikasi-hata](#sunucu-guvenlik-politikasi-hata), [sunucu-gm60-okuyucu-reddi](#sunucu-gm60-okuyucu-reddi)

<a id="sunucu-geofence-konum-reddi"></a>
### sunucu-geofence-konum-reddi · Kapı açma 403 GEOFENCE_LOCATION_REQUIRED / _INVALID / _STALE / _INACCURATE / _MOCK_LOCATION ("konum dogrulamasi zorunludur", "Konum bilginiz guncel degil", "Sahte konum")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/geofence_service.js:220](../../server/src/services/geofence_service.js#L220) | <code>export function validateGeofenceForDoorRequest({</code> | Site require_geofence ise (ya da forceRequire) tüm konum kontrolleri burada |
| [server/src/services/geofence_service.js:251](../../server/src/services/geofence_service.js#L251) | <code>const missingFields = ['latitude', 'longitude', 'accuracy', 'timestamp'].filter((field) =…</code> | Dört alandan biri eksikse LOCATION_REQUIRED (missing_fields döner) |
| [server/src/services/geofence_service.js:282](../../server/src/services/geofence_service.js#L282) | <code>if (toBoolean(location.is_mocked ?? location.isMocked)) {</code> | is_mocked = true -> MOCK_LOCATION |
| [server/src/services/geofence_service.js:292](../../server/src/services/geofence_service.js#L292) | <code>if (ageMs &gt; GEOFENCE_MAX_AGE_MS) {</code> | Konum zaman damgası 60 sn'den eski (ya da gelecekte) -> LOCATION_STALE |
| [server/src/services/geofence_service.js:301](../../server/src/services/geofence_service.js#L301) | <code>if (clientAccuracy &gt; GEOFENCE_MAX_ACCURACY_METERS) {</code> | accuracy 100 m'den büyük -> LOCATION_INACCURATE |
| [server/src/services/geofence_service.js:151](../../server/src/services/geofence_service.js#L151) | <code>export function extractClientLocation(body) {</code> | Konum alanları gövdede üst düzey ya da location nesnesi içinde aranır |
| [server/src/routes/app_doors_routes.js:179](../../server/src/routes/app_doors_routes.js#L179) | <code>validateGeofenceForDoorRequest({</code> | Açma ucunda çağrı; hata buildGeofenceErrorBody ile code/missing_fields olarak döner |

**Olası nedenler**
- Uygulama konum göndermiyor: GPS izni/konum servisi kapalı (missing_fields hangisinin eksik olduğunu söyler)
- Konum bayat (timestamp > 60 sn) ya da telefon saati yanlış (zaman damgası UTC ISO8601 olmalı)
- GPS doğruluğu 100 m'den kötü (kapalı alan)
- Sahte konum uygulaması (is_mocked true)
- Karekodsuz/ekransız (C3) cihazda karekodla açma site bayrağından bağımsız konumu ZORUNLU kılar

**Adım adım kontrol**
- Yanıttaki code ve missing_fields alanına bakın
- SELECT require_geofence, geofence_latitude, geofence_longitude, geofence_radius_meters FROM sites WHERE site_code = <site>
- Telefon saatini ve konum iznini kontrol ettirin

**Günlükte aranacak ifadeler**
- `[Geofence GUVENLIK IHLALI] Sahte konum tespit edildi`
- `[Geofence] Bayat konum tespit edildi`
- `[Geofence] Yetersiz GPS dogrulugu`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a Geofence"
```

**İlgili testler:** [server/test/doors_geofence.test.js](../../server/test/doors_geofence.test.js), [server/test/geofence.test.js](../../server/test/geofence.test.js)

**Bkz.:** [sunucu-geofence-menzil-disi](#sunucu-geofence-menzil-disi), [sunucu-tarama-qr-ekran-token](#sunucu-tarama-qr-ekran-token)

<a id="sunucu-geofence-menzil-disi"></a>
### sunucu-geofence-menzil-disi · Kapı açma 403 "Kapi konumunda degilsiniz (Mesafe: ~Xm, Izin verilen sinir: Ym)" (GEOFENCE_OUT_OF_RANGE) veya "Sitenin konum (geofence) ayari gecersiz" (SITE_MISCONFIGURED)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/geofence_service.js:310](../../server/src/services/geofence_service.js#L310) | <code>const distanceMeters = calculateHaversineDistanceMeters(siteLat, siteLon, clientLat, clie…</code> | Sunucu Haversine ile site merkezi ile telefon konumu arasındaki mesafeyi hesaplar |
| [server/src/services/geofence_service.js:312](../../server/src/services/geofence_service.js#L312) | <code>const allowedRadiusMeters = siteRadius !== null &amp;&amp; siteRadius &gt; 0 ? siteRadius : GEOFENCE…</code> | İzinli yarıçap: site ayarı, yoksa 100 m |
| [server/src/services/geofence_service.js:244](../../server/src/services/geofence_service.js#L244) | <code>GEOFENCE_ERROR_CODES.SITE_MISCONFIGURED,</code> | Site koordinatı aralık dışıysa yönetici düzeltmeli (403) |
| [server/src/services/geofence_service.js:239](../../server/src/services/geofence_service.js#L239) | <code>return { allowed: true, geofence_required: true, warning: 'SITE_COORDINATES_NOT_CONFIGURE…</code> | Koordinat hiç tanımlı değilse geçişe İZİN verilir (yalnız uyarı) |
| [server/src/utils/site_rules.js:462](../../server/src/utils/site_rules.js#L462) | <code>error: 'Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur.',</code> | require_geofence açılırken geçerli enlem/boylam zorunlu; (0,0) geçersiz |
| [server/src/utils/site_rules.js:221](../../server/src/utils/site_rules.js#L221) | <code>export const GEOFENCE_RADIUS_MIN = 10;</code> | Yarıçap 10-2000 m aralığında ayarlanabilir |

**Olası nedenler**
- Kullanıcı gerçekten kapıdan uzakta (varsayılan 100 m)
- Site merkezi koordinatı yanlış girilmiş (kapıdan uzak bir nokta) ya da yarıçap çok küçük
- GPS sapması: kapalı alanda mesafe büyük görünür
- Koordinat aralık dışı kaydedilmişse SITE_MISCONFIGURED döner

**Adım adım kontrol**
- Yanıttaki distance_meters ve allowed_radius_meters değerlerini karşılaştırın
- Site merkezini yönetici panelinden (PATCH /manager/sites/:id/security-policy) doğru konuma alın veya yarıçapı artırın

**Günlükte aranacak ifadeler**
- `[Geofence RED] Kullanici kapi alaninda degil.`
- `[Geofence] Site koordinati gecersiz`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a Geofence"
```

**İlgili testler:** [server/test/doors_geofence.test.js](../../server/test/doors_geofence.test.js), [server/test/geofence.test.js](../../server/test/geofence.test.js), [server/test/sites_security_policy.test.js](../../server/test/sites_security_policy.test.js)

**Bkz.:** [sunucu-geofence-konum-reddi](#sunucu-geofence-konum-reddi), [sunucu-guvenlik-politikasi-hata](#sunucu-guvenlik-politikasi-hata)

<a id="sunucu-tarama-qr-ekran-token"></a>
### sunucu-tarama-qr-ekran-token · Kapı önündeki karekod okutulunca 409 "Cihaz ekranindaki guncel karekod henuz alinamadi" (EKRAN_QR_BEKLENIYOR) ya da 403 DYNAMIC_QR_REQUIRED

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/app_doors_routes.js:256](../../server/src/routes/app_doors_routes.js#L256) | <code>appDoorsRouter.post('/app/doors/scan-qr-open', authRequired, doorCommandRateLimiter, asyn…</code> | Uygulamanın kapı önündeki karekodu okutarak açtığı uç |
| [server/src/routes/app_doors_routes.js:312](../../server/src/routes/app_doors_routes.js#L312) | <code>deniedAudit('DYNAMIC_QR_REQUIRED');</code> | Ekranlı cihazda karekod token içermiyorsa (statik UID) 403 |
| [server/src/routes/app_doors_routes.js:320](../../server/src/routes/app_doors_routes.js#L320) | <code>deniedAudit('EKRAN_QR_BEKLENIYOR');</code> | Köprü ekran tokenını henüz almadıysa UID ile AÇILMAZ, 409 |
| [server/src/services/door_access_policy.js:200](../../server/src/services/door_access_policy.js#L200) | <code>export function doorDeviceHasScreen(row) {</code> | C3 dışındaki donanım "ekranlı" sayılır (bilinmeyen donanımda da fail-closed) |

**Olası nedenler**
- Cihaz ekranı dinamik token yayınlıyor ama sunucu (MQTT köprüsü) henüz almadı: sunucu yeni açıldı/yeniden başladı ya da cihaz çevrimdışı
- Okutulan karekod eski/statik biçimde (token yok) ama kapıdaki cihaz ekranlı
- Donanım tipi yanlış kayıtlı (C3 yerine WROOM veya tersi) olduğundan ekran var/yok kararı yanlış

**Adım adım kontrol**
- Birkaç saniye bekleyip ekrandaki güncel karekodu yeniden okutun
- Cihaz çevrimiçi mi (GET /app/doors/:id/status)?
- devices.hardware_type ile cihazın bildirdiği donanım hedefi uyuşuyor mu?

**İlgili testler:** [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js)

**Bkz.:** [sunucu-tarama-qr-suresi-doldu](#sunucu-tarama-qr-suresi-doldu), [sunucu-kapi-acma-cihaz-offline](#sunucu-kapi-acma-cihaz-offline)

<a id="sunucu-tarama-qr-suresi-doldu"></a>
### sunucu-tarama-qr-suresi-doldu · Karekod okutunca 403 "Karekodun süresi dolmuş" (SCREEN_QR_EXPIRED) ya da "Bu karekod daha once kullanildi" (SCREEN_QR_ALREADY_USED)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_access_policy.js:270](../../server/src/services/door_access_policy.js#L270) | <code>export function checkScreenQrToken(entry, token, now = Date.now()) {</code> | Geçerlilik: güncel token süresi + 12 sn tolerans; önceki token yalnızca 12 sn |
| [server/src/services/door_access_policy.js:210](../../server/src/services/door_access_policy.js#L210) | <code>export const SCREEN_QR_GRACE_MS = 12000;</code> | Token değişiminde tolerans penceresi |
| [server/src/services/door_access_policy.js:300](../../server/src/services/door_access_policy.js#L300) | <code>export function consumeScreenQrToken(entry, token, now = Date.now()) {</code> | Token tek kullanımlık; tüketimde usedTokens'a eklenir |
| [server/src/routes/app_doors_routes.js:332](../../server/src/routes/app_doors_routes.js#L332) | <code>code: 'SCREEN_QR_ALREADY_USED',</code> | Kullanılmış token 403 |
| [server/src/services/door_access_policy.js:313](../../server/src/services/door_access_policy.js#L313) | <code>export function releaseScreenQrToken(entry, token) {</code> | Komut gönderilemezse token iade edilir (yanmaz) |

**Olası nedenler**
- Karekod ekranda yenilendi (varsayılan 30 sn + 12 sn tolerans); kullanıcı eski karekodu okuttu
- Aynı karekod daha önce okutuldu (tek kullanımlık) — örn. çift okutma ya da başka telefon
- Fotoğraf/ekran görüntüsünden okutma

**Adım adım kontrol**
- Kullanıcı ekrandaki GÜNCEL karekodu doğrudan okutmalı

**İlgili testler:** [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js)

**Bkz.:** [sunucu-tarama-qr-ekran-token](#sunucu-tarama-qr-ekran-token), [sunucu-gm60-okuyucu-reddi](#sunucu-gm60-okuyucu-reddi)

<a id="sunucu-tarama-qr-gecersiz-yuk"></a>
### sunucu-tarama-qr-gecersiz-yuk · Karekod okutunca 400 "Gecersiz karekod verisi." (INVALID_QR_PAYLOAD), 404 "Karekod ile eslesen aktif bir kapi bulunamadi." ya da 403 DOOR_ACCESS_DENIED

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_access_policy.js:162](../../server/src/services/door_access_policy.js#L162) | <code>export function parseScanQrPayload(raw) {</code> | Biçimler: AHBU:DOOR:<uid>:<token>, AHBU:DOOR:<uid>, <uid>:<token>, <uid>; en çok 128 karakter |
| [server/src/routes/app_doors_routes.js:260](../../server/src/routes/app_doors_routes.js#L260) | <code>return res.status(400).json({ error: 'Gecersiz karekod verisi.', code: 'INVALID_QR_PAYLOA…</code> | Karekod metni çözülemezse 400 |
| [server/src/routes/app_doors_routes.js:279](../../server/src/routes/app_doors_routes.js#L279) | <code>code: 'DOOR_NOT_FOUND',</code> | UID'ye atanmış aktif kapı yoksa 404 |
| [server/src/routes/app_doors_routes.js:290](../../server/src/routes/app_doors_routes.js#L290) | <code>code: 'DOOR_ACCESS_DENIED',</code> | Kullanıcının o kapıya erişimi yoksa 403 |

**Olası nedenler**
- Başka bir karekod (örn. site katılım QR'ı ya da yabancı kod) okutuldu
- Cihaz henüz hiçbir aktif kapıya atanmamış ya da kapı pasif
- Kullanıcı o kapıya yetkili değil (bkz. kapı erişim girişleri)

**Adım adım kontrol**
- qr_payload alanının istemciden gelen ham metnini doğrulayın
- SELECT d.id, d.is_active FROM site_doors d JOIN devices v ON v.id = d.assigned_device_id WHERE v.device_uid = '<UID>'

**İlgili testler:** [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js), [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js)

**Bkz.:** [sunucu-kapi-acma-404-yetki](#sunucu-kapi-acma-404-yetki), [sunucu-kapi-acma-409-cihaz-atanmamis](#sunucu-kapi-acma-409-cihaz-atanmamis)

<a id="sunucu-qr-token-uretilemiyor"></a>
### sunucu-qr-token-uretilemiyor · Uygulamada dinamik karekod üretilemiyor: 400 "Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır." (NO_QR_SCANNER_HARDWARE), 403 ya da 429 "Karekod talebi çok sık yapıldı"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/app_doors_routes.js:468](../../server/src/routes/app_doors_routes.js#L468) | <code>appDoorsRouter.post('/app/doors/:id/qr-token', authRequired, qrTokenRateLimiter, async (r…</code> | Kullanıcıya kapı için 30 sn (site ayarı) geçerli token üretir |
| [server/src/services/qr_access_service.js:21](../../server/src/services/qr_access_service.js#L21) | <code>export async function generateQrTokenForDoor({ authUser, doorId, clientLocation }) {</code> | Yetki, politika, donanım, geofence ve token üretimi sırası |
| [server/src/services/qr_access_service.js:44](../../server/src/services/qr_access_service.js#L44) | <code>error.code = 'NO_QR_SCANNER_HARDWARE';</code> | C3 cihaz, cihaz atanmamış ya da qr_reader_enabled !== true ise 400 |
| [server/src/middlewares/rate_limiters.js:189](../../server/src/middlewares/rate_limiters.js#L189) | <code>export const qrTokenRateLimiter = createAuthUserRateLimiter({</code> | Kullanıcı+kapı başına dakikada 6 token isteği (429, retry_after_seconds döner) |

**Olası nedenler**
- Kapıdaki cihaz ESP32-C3 (ekran/okuyucu yok) ya da devices.qr_reader_enabled = FALSE
- Kapıya cihaz atanmamış
- Kapıya erişim yok (403 "Kapi bulunamadi veya erisim yetkiniz yok.") ya da site QR politikası kapalı (QR_DISABLED / QR_ENTRY_INACTIVE)
- Geofence reddi (konum alanları eksik/uzak)
- Dakikada 6'dan fazla istek (429)

**Adım adım kontrol**
- SELECT v.hardware_type, v.qr_reader_enabled FROM devices v JOIN site_doors d ON d.assigned_device_id = v.id WHERE d.id = <kapı>
- Yanıtın code alanına bakın (NO_QR_SCANNER_HARDWARE, QR_DISABLED, GEOFENCE_*)

**İlgili testler:** [server/test/doors_qr_access.test.js](../../server/test/doors_qr_access.test.js), [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js)

**Bkz.:** [sunucu-karekod-politika-kapali](#sunucu-karekod-politika-kapali), [sunucu-geofence-konum-reddi](#sunucu-geofence-konum-reddi), [sunucu-gm60-okuyucu-reddi](#sunucu-gm60-okuyucu-reddi)

<a id="sunucu-gm60-okuyucu-reddi"></a>
### sunucu-gm60-okuyucu-reddi · Kapı önündeki QR okuyucu (GM60/WROOM) telefondaki karekodu kabul etmiyor, kapı açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/qr_access_service.js:162](../../server/src/services/qr_access_service.js#L162) | <code>export async function verifyQrTokenAndOpenDoor({ deviceUid, token }) {</code> | Okuyucunun okuduğu token doğrulanır; sıra: cihaz, token durumu, yetki+politika, atomik tüketim, röle |
| [server/src/services/qr_access_service.js:281](../../server/src/services/qr_access_service.js#L281) | <code>return deny('ALREADY_USED', 'Zaten Kullanılmış QR');</code> | Token daha önce kullanılmış |
| [server/src/services/qr_access_service.js:287](../../server/src/services/qr_access_service.js#L287) | <code>return deny('SUPERSEDED', 'Hükümsüz/Yenilenmiş QR', 'SUPERSEDED_TOKEN');</code> | Kullanıcı daha yeni bir karekod üretti, eski hükümsüz |
| [server/src/services/qr_access_service.js:293](../../server/src/services/qr_access_service.js#L293) | <code>return deny('EXPIRED_TOKEN', 'Süresi Dolmuş QR');</code> | Süre SUNUCU saatine göre kontrol edilir (telefon saati önemsiz) |
| [server/src/services/qr_access_service.js:315](../../server/src/services/qr_access_service.js#L315) | <code>return deny('DOOR_MISMATCH', 'Kapı Uyuşmazlığı');</code> | Token başka kapı için üretilmiş |
| [server/src/services/qr_access_service.js:330](../../server/src/services/qr_access_service.js#L330) | <code>return deny('ACCESS_REVOKED', 'Kapı Yetkisi Yok');</code> | Üretimden sonra kullanıcının yetkisi alınmış (tüketim anında yeniden kontrol edilir) |
| [server/src/services/qr_access_service.js:304](../../server/src/services/qr_access_service.js#L304) | <code>return deny('TOKEN_OR_USER_INACTIVE', 'Pasif Hesap/Token');</code> | Hesap pasif/doğrulanmamış ya da token iptal edilmiş |
| [server/src/services/qr_access_service.js:199](../../server/src/services/qr_access_service.js#L199) | <code>return { allowed: false, reason: 'QR_READER_NOT_ENABLED' };</code> | Cihazda qr_reader_enabled kapalı |

**Olası nedenler**
- Token süresi (varsayılan 30 sn) doldu ya da kullanıcı yeni karekod üretti (SUPERSEDED)
- Aynı karekod ikinci kez okutuldu (tek kullanımlık)
- Karekod başka kapı/cihaz için üretildi (DOOR_MISMATCH)
- Kullanıcının kapı yetkisi alındı ya da site politikası (QR) kapandı
- Cihazın QR okuyucusu sunucuda kapalı (qr_reader_enabled) ya da cihaza kapı atanmamış (DOOR_NOT_ASSIGNED)

**Adım adım kontrol**
- Günlükte "[QR Dogrulama RED]" satırındaki neden kodunu bulun (ALREADY_USED, EXPIRED_TOKEN, ...)
- SELECT last_denial_reason, is_used, expires_at FROM qr_access_tokens WHERE user_code = <kullanıcı> ORDER BY id DESC LIMIT 3
- Kullanıcı uygulamada yeni karekod üretip hemen okutmalı

**Günlükte aranacak ifadeler**
- `[QR Dogrulama RED]`
- `[QR Dogrulama ONAY]`
- `[QR Dogrulama] Bilinmeyen cihaz UID`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'QR Dogrulama'"
```

**İlgili testler:** [server/test/doors_qr_access.test.js](../../server/test/doors_qr_access.test.js)

**Bkz.:** [sunucu-gm60-role-calismadi](#sunucu-gm60-role-calismadi), [sunucu-karekod-politika-kapali](#sunucu-karekod-politika-kapali), [sunucu-qr-token-uretilemiyor](#sunucu-qr-token-uretilemiyor)

<a id="sunucu-gm60-role-calismadi"></a>
### sunucu-gm60-role-calismadi · Okuyucu karekodu kabul etti ama röle çalışmadı / kapı açılmadı (PULSE_FAILED)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/qr_access_service.js:404](../../server/src/services/qr_access_service.js#L404) | <code>return { allowed: false, reason: 'PULSE_FAILED' };</code> | MQTT röle komutu yayınlanamadıysa PULSE_FAILED döner |
| [server/src/services/qr_access_service.js:374](../../server/src/services/qr_access_service.js#L374) | <code>assumeOnline: true,</code> | İstek cihazın kendisinden geldiği için çevrimiçi kabul edilir |
| [server/src/services/qr_access_service.js:377](../../server/src/services/qr_access_service.js#L377) | <code>console.error(`[QR Dogrulama] Role komutu gonderilemedi (${pulseError?.code &#124;&#124; 'HATA'}). …</code> | Komut hatasının günlük satırı |

**Olası nedenler**
- MQTT köprüsü broker'a bağlı değil ya da yayın hatası
- Token tüketimi geri alınır: kullanıcı süresi içinde aynı karekodu yeniden okutabilir

**Adım adım kontrol**
- Günlükte "Role komutu gonderilemedi" satırının hata kodu
- curl /health ile mqtt durumuna bakın; kapı günlüğünde "(Kapı Komutu Gönderilemedi)" etiketli kayıt görünür

**Günlükte aranacak ifadeler**
- `[QR Dogrulama] Role komutu gonderilemedi`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Role komutu'"
```

**İlgili testler:** [server/test/doors_qr_access.test.js](../../server/test/doors_qr_access.test.js)

**Bkz.:** [sunucu-gm60-okuyucu-reddi](#sunucu-gm60-okuyucu-reddi), [sunucu-kapi-acma-cihaz-offline](#sunucu-kapi-acma-cihaz-offline)

<a id="sunucu-yerel-kontrol-token-bos"></a>
### sunucu-yerel-kontrol-token-bos · Uygulama yerel (Wi-Fi) açma yapamıyor: durum yanıtında local_control.token boş, available false ya da 403 LOCAL_DISABLED

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_service.js:36](../../server/src/services/door_service.js#L36) | <code>export async function localDoorControlForStatus({ deviceUid, currentToken, status, allowL…</code> | Durum/açma yanıtındaki local_control (token, ip, port, available) buradan gelir |
| [server/src/services/door_service.js:39](../../server/src/services/door_service.js#L39) | <code>if (!allowLocal) {</code> | Site yerel açmayı kapattıysa token VERİLMEZ (uygulama buluta düşer) |
| [server/src/services/door_service.js:52](../../server/src/services/door_service.js#L52) | <code>(now - lastSent &gt; 60000)</code> | Cihaza local_control_config en çok 60 sn'de bir yeniden gönderilir |
| [server/src/services/device_service.js:189](../../server/src/services/device_service.js#L189) | <code>export async function ensureDeviceLocalControlToken(deviceUid) {</code> | Token yoksa üretir; cihaz kayıtlı değilse null |
| [server/src/services/door_access_policy.js:107](../../server/src/services/door_access_policy.js#L107) | <code>code: 'LOCAL_DISABLED',</code> | local-open-notify ucu: feature_local_udp_enabled = FALSE ise 403 |

**Olası nedenler**
- Sitede yerel ağ ile açma kapalı (feature_local_udp_enabled = FALSE)
- Cihaz MQTT'ye bağlı değil: yerel kontrol yapılandırması cihaza iletilemez (local_control_available false)
- Telefon cihazla aynı ağda değil ya da cihazın yerel IP bilgisi gelmedi (local_ip boş)
- Cihaz kayıtlı değil, token üretilemedi

**Adım adım kontrol**
- GET /app/doors/:id/status yanıtındaki device_status.local_control ve mqtt_connected değerlerine bakın
- SELECT feature_local_udp_enabled FROM sites WHERE site_code = <site>
- Günlükte local_control_config_failed denetim kaydı var mı

**Günlükte aranacak ifadeler**
- `local_control_config_failed`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a local_control"
```

**İlgili testler:** [server/test/doors_service.test.js](../../server/test/doors_service.test.js), [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js)

**Bkz.:** [sunucu-yerel-token-rotasyonu](#sunucu-yerel-token-rotasyonu), [sunucu-kapi-acma-cihaz-offline](#sunucu-kapi-acma-cihaz-offline)

<a id="sunucu-yerel-token-rotasyonu"></a>
### sunucu-yerel-token-rotasyonu · Yetkisi alınan kişi hâlâ yerel açabiliyor ya da yeni yetki verilen kişide yerel açma eski token yüzünden reddediliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/local_token_service.js:38](../../server/src/services/local_token_service.js#L38) | <code>export async function rotateTokensForDevices({ deviceIds, reason }) {</code> | Belirli cihazların token'ını döndürür (asla fırlatmaz; hata günlüğe) |
| [server/src/services/local_token_service.js:57](../../server/src/services/local_token_service.js#L57) | <code>export async function rotateTokensForSite({ siteCode, reason }) {</code> | Sitedeki tüm cihazların token'ını döndürür |
| [server/src/services/device_service.js:252](../../server/src/services/device_service.js#L252) | <code>export async function rotateLocalControlTokensForDeviceIds(deviceIds, reason) {</code> | DB'de yeni token yazar ve cihaza MQTT ile iletir |
| [server/src/services/device_service.js:225](../../server/src/services/device_service.js#L225) | <code>export async function pushLocalControlTokenToDevice({ deviceUid, token, reason }) {</code> | Cihaz çevrimdışıysa iletilemez (local_control_token_sync_failed) |
| [server/src/services/membership_service.js:1761](../../server/src/services/membership_service.js#L1761) | <code>await rotateTokensForSite({ siteCode: apt.site_code, reason: 'apartment_member_removed' }…</code> | Sakin daireden çıkarılınca site cihazlarının token'ı döndürülür |

**Olası nedenler**
- Token döndürme DB'de hemen olur ama cihaza MQTT ile iletilir: cihaz o sırada çevrimdışıysa eski token cihazda kalır (günlükte local_control_token_sync_failed)
- Uygulama eski token'ı önbellekte tutuyor: durum ucunu yeniden çağırınca yeni token alır
- Üyelik/izin değişikliği (çıkarma, pasife alma, silme, kapı izni verme/kaldırma, yönetici ekleme/çıkarma) token döndürür; ardışık değişikliklerde cihaz kısa süre eski token'ı kabul edebilir

**Adım adım kontrol**
- Günlükte local_control_token_synced ve local_control_token_sync_failed denetim kayıtlarına bakın
- Cihaz çevrimiçi olunca bir sonraki durum isteğinde yapılandırma yeniden gönderilir (60 sn aralık)

**Günlükte aranacak ifadeler**
- `local_control_token_sync_failed`
- `local_control_token_synced`
- `[LocalToken] Token döndürme başarısız:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -E 'local_control_token|LocalToken'"
```

**İlgili testler:** [server/test/devices_device_service.test.js](../../server/test/devices_device_service.test.js), [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js)

**Bkz.:** [sunucu-yerel-kontrol-token-bos](#sunucu-yerel-kontrol-token-bos), [sunucu-daire-sakin-yonetimi-hata](#sunucu-daire-sakin-yonetimi-hata)

<a id="sunucu-kapi-gecis-logu-yazilmadi"></a>
### sunucu-kapi-gecis-logu-yazilmadi · Kapı açıldı ama geçiş günlüğünde (kapı kayıtları) satır yok ya da eski kayıtlar kayboldu

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_service.js:70](../../server/src/services/door_service.js#L70) | <code>export async function recordDoorAccessLog({</code> | Günlük yazımı: hata YUTULUR (false döner), kapı yine açılmış olur |
| [server/src/services/door_service.js:119](../../server/src/services/door_service.js#L119) | <code>auditLog('door_access_log_write_failed', {</code> | Yazım hatasında denetim satırı |
| [server/src/routes/app_doors_routes.js:230](../../server/src/routes/app_doors_routes.js#L230) | <code>console.error('Kapi gecis logu DB kayit hatasi:', err.message);</code> | Açma ucu günlüğü arka planda yazar; hata yalnız burada görünür |
| [server/src/services/maintenance_service.js:60](../../server/src/services/maintenance_service.js#L60) | <code>DELETE FROM door_access_logs</code> | Günlük bakım 30 günden eski geçiş kayıtlarını siler |

**Olası nedenler**
- Günlük yazımı DB hatasıyla başarısız oldu (kapı açma etkilenmez; yalnız günlük kaybolur)
- Kayıt 30 günden eski: günlük bakım siler (door_service.cleanupOldDoorLogs 7 gün der ama bakım tarafı 30 gündür)
- Yerel/çevrimdışı açılışlar cihazdan toplu senkronla gelir (gecikmeli görünür)

**Adım adım kontrol**
- Günlükte "Kapi gecis logu DB kayit hatasi" ve "door_access_log_write_failed" satırlarını arayın
- SELECT trigger_type, opened_at FROM door_access_logs WHERE site_code = <site> ORDER BY opened_at DESC LIMIT 10

**Günlükte aranacak ifadeler**
- `Kapi gecis logu DB kayit hatasi:`
- `door_access_log_write_failed`
- `Error recording door access log:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -E 'gecis logu|door_access_log'"
```

**İlgili testler:** [server/test/doors_service.test.js](../../server/test/doors_service.test.js), [server/test/devices_door_log_service.test.js](../../server/test/devices_door_log_service.test.js)

**Bkz.:** [sunucu-yonetici-gecis-gunlugu-bos](#sunucu-yonetici-gecis-gunlugu-bos), [sunucu-offline-log-senkronu-hata](#sunucu-offline-log-senkronu-hata)

<a id="sunucu-yonetici-gecis-gunlugu-bos"></a>
### sunucu-yonetici-gecis-gunlugu-bos · Site yöneticisi "Kapı geçiş günlüğü" ekranında hiç kayıt göremiyor ya da 403 "Bu sitenin loglarini gorme yetkiniz yok."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/door_log_routes.js:106](../../server/src/routes/door_log_routes.js#L106) | <code>doorLogRouter.get('/manager/door-logs', authRequired, requireSiteManager, async (req, res…</code> | Yönetici günlük ucu |
| [server/src/routes/door_log_routes.js:13](../../server/src/routes/door_log_routes.js#L13) | <code>async function getManagedSiteCodes(authUser) {</code> | Bu dosyadaki yerel sürüm YALNIZCA site_manager_sites tablosuna bakar (site_memberships'e bakmaz) |
| [server/src/routes/door_log_routes.js:136](../../server/src/routes/door_log_routes.js#L136) | <code>return res.status(403).json({ error: 'Bu sitenin loglarini gorme yetkiniz yok.' });</code> | İstenen site_code yönetilen siteler arasında değilse 403 |
| [server/src/services/site_service.js:328](../../server/src/services/site_service.js#L328) | <code>export async function getManagedSiteCodes(authUser) {</code> | Diğer uçların kullandığı sürüm site_memberships'i de sayar (fark bu) |

**Olası nedenler**
- Kullanıcı yalnızca site_memberships (SITE_OWNER/SITE_ADMIN) ile yönetici, site_manager_sites satırı yok: günlük ucu boş liste döndürür
- Seçilen site_code kullanıcının yönettiği sitelerden değil (403)
- Kayıtlar 30 günden eski ya da tarih filtresi dışında

**Adım adım kontrol**
- SELECT site_code FROM site_manager_sites WHERE manager_user_code = <id>
- SELECT site_code, role FROM site_memberships WHERE user_code = <id> AND is_active
- Yalnızca site_memberships varsa site_manager_sites satırı eksiktir

**İlgili testler:** [server/test/devices_sync_logs_route.test.js](../../server/test/devices_sync_logs_route.test.js)

**Bkz.:** [sunucu-kapi-gecis-logu-yazilmadi](#sunucu-kapi-gecis-logu-yazilmadi), [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi)

<a id="sunucu-offline-log-senkronu-hata"></a>
### sunucu-offline-log-senkronu-hata · Çevrimdışı kapı kayıtları senkronlanmıyor: /device/sync-logs 400/403/404/413 veriyor ya da rejected_count yüksek

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/door_log_routes.js:220](../../server/src/routes/door_log_routes.js#L220) | <code>export async function syncDeviceLogsHandler(req, res) {</code> | device_uid, logs dizisi, boyut ve yetki kontrolleri |
| [server/src/routes/door_log_routes.js:207](../../server/src/routes/door_log_routes.js#L207) | <code>async function canSyncLogsForDevice(authUser, device) {</code> | Yetki: süper kullanıcı, cihazın sitesinin yöneticisi ya da cihazın kapısına erişimi olan kullanıcı |
| [server/src/routes/door_log_routes.js:205](../../server/src/routes/door_log_routes.js#L205) | <code>const SYNC_LOGS_MAX_BODY_BYTES = 256 * 1024;</code> | İstek gövdesi 256 KB üstü 413 |
| [server/src/services/door_log_service.js:14](../../server/src/services/door_log_service.js#L14) | <code>export const MAX_DEVICE_LOG_BATCH = 200;</code> | Tek istekte en çok 200 kayıt (aşılırsa 413 TOO_MANY_LOGS) |
| [server/src/services/door_log_service.js:151](../../server/src/services/door_log_service.js#L151) | <code>export function validateDeviceLogEntry(item, { now = Date.now() } = {}) {</code> | Kayıt başına doğrulama (trigger_type, client_log_id, zaman); geçersizler rejected sayılır |

**Olası nedenler**
- Cihaz kapıya/siteye atanmamış (404 "Cihaz veya bagli oldugu site bulunamadi.")
- Gönderen kullanıcının bu cihaza yetkisi yok (403)
- Toplu gönderim 200 kaydı ya da 256 KB'ı aşıyor
- Kayıtlarda bilinmeyen trigger_type, geçersiz client_log_id ya da geçersiz zaman damgası

**Adım adım kontrol**
- Yanıttaki synced_count / duplicate_count / rejected_count değerlerine bakın
- İstemci kayıtları 200'lük parçalara bölmeli; aynı client_log_id tekrar gönderilirse duplicate sayılır (zararsız)

**İlgili testler:** [server/test/devices_sync_logs_route.test.js](../../server/test/devices_sync_logs_route.test.js), [server/test/devices_door_log_service.test.js](../../server/test/devices_door_log_service.test.js)

**Bkz.:** [sunucu-kapi-gecis-logu-yazilmadi](#sunucu-kapi-gecis-logu-yazilmadi)

<a id="sunucu-429-genel-hiz-siniri"></a>
### sunucu-429-genel-hiz-siniri · Bir işlem "Cok fazla ... denemesi. Biraz sonra tekrar deneyin." (429, Retry-After) ile reddediliyor; hangi sınırlayıcı olduğu belli değil

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/rate_limiters.js:95](../../server/src/middlewares/rate_limiters.js#L95) | <code>export function createRuleLimiter({ rules, message, includeRetryBody = false, now = Date.…</code> | Tüm sınırlayıcıların ortak çekirdeği: kural aşılırsa 429 + Retry-After |
| [server/src/middlewares/rate_limiters.js:215](../../server/src/middlewares/rate_limiters.js#L215) | <code>export const registerLimiter = createRuleLimiter({</code> | Kayıt: 15 dk'da 5 (IP+e-posta), saatte 40 (IP) |
| [server/src/middlewares/rate_limiters.js:223](../../server/src/middlewares/rate_limiters.js#L223) | <code>export const verifyCodeLimiter = createRuleLimiter({</code> | Kod doğrulama: 15 dk'da 10 (IP+e-posta), 20 (yalnız e-posta) |
| [server/src/middlewares/rate_limiters.js:232](../../server/src/middlewares/rate_limiters.js#L232) | <code>export const resendCodeLimiter = createRuleLimiter({</code> | Kod yeniden gönderme: 10 dk'da 3, saatte 6 (e-posta), 30 (IP) |
| [server/src/middlewares/rate_limiters.js:241](../../server/src/middlewares/rate_limiters.js#L241) | <code>export const forgotPasswordLimiter = createRuleLimiter({</code> | Şifre sıfırlama isteği: 15 dk'da 3, saatte 5 (e-posta), 30 (IP) |
| [server/src/middlewares/rate_limiters.js:256](../../server/src/middlewares/rate_limiters.js#L256) | <code>export const claimDeviceLimiter = createRuleLimiter({</code> | Cihaz sahiplenme: 10 dk'da 10 (kullanıcı) |
| [server/src/middlewares/rate_limiters.js:265](../../server/src/middlewares/rate_limiters.js#L265) | <code>export const inviteLimiter = createRuleLimiter({</code> | Yönetici daveti: saatte 20 (kullanıcı) |
| [server/src/middlewares/rate_limiters.js:274](../../server/src/middlewares/rate_limiters.js#L274) | <code>export const adminSensitiveLimiter = createRuleLimiter({</code> | Süper kullanıcı hassas işlemleri: 15 dk'da 10 |

**Olası nedenler**
- İlgili işlem kısa sürede çok tekrarlandı (mesaj metni hangi sınırlayıcı olduğunu söyler: kayıt, doğrulama, kod isteme, sıfırlama, sahiplenme, davet, hassas işlem, giriş, kapı komutu, karekod)
- Ortak ağ (NAT) arkasında çok kullanıcı aynı IP kuralını paylaşıyor; kullanıcı doğrulanmışsa kural kullanıcı bazlıdır
- Sayaçlar bellek içidir: PM2 yeniden başlayınca sıfırlanır; her süreç kendi sayacını tutar

**Adım adım kontrol**
- Yanıt başlığı Retry-After (saniye) kadar bekleyin; includeRetryBody açık limitlerde gövdede retry_after_seconds de gelir
- Hangi uç olduğunu istek günlüğünde 429 satırından bulun
- Mesaja göre ilgili girişe geçin: giriş için sunucu-giris-ip-hiz-siniri-429, kapı komutu için sunucu-kapi-acma-429-cok-sik, kayıt için sunucu-kayit-429-bekleme-sinir

**Günlükte aranacak ifadeler**
- `[API] `

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a ' 429'"
```

**İlgili testler:** [server/test/core_rate_limiter.test.js](../../server/test/core_rate_limiter.test.js)

**Bkz.:** [sunucu-giris-ip-hiz-siniri-429](#sunucu-giris-ip-hiz-siniri-429), [sunucu-kapi-acma-429-cok-sik](#sunucu-kapi-acma-429-cok-sik), [sunucu-kayit-429-bekleme-sinir](#sunucu-kayit-429-bekleme-sinir), [sunucu-dogrulama-429-deneme-asildi](#sunucu-dogrulama-429-deneme-asildi)

<a id="sunucu-hata-500-errorid"></a>
### sunucu-hata-500-errorid · İstemci "Sunucu hatasi olustu. Lutfen daha sonra tekrar deneyin." + errorId (500) alıyor; nedeni ekranda görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/error_handler.js:103](../../server/src/middlewares/error_handler.js#L103) | <code>export function createErrorHandler({ logger = console } = {}) {</code> | Global yakalayıcı: 5xx'te stack/mesaj istemciye gitmez, errorId üretilir |
| [server/src/middlewares/error_handler.js:131](../../server/src/middlewares/error_handler.js#L131) | <code>`[ERROR] ${errorId} ${req.method} ${maskSensitiveUrl(req.originalUrl)}:`,</code> | Ayrıntı yalnızca sunucu günlüğüne yazılır; errorId ile eşleşir |
| [server/src/middlewares/error_handler.js:67](../../server/src/middlewares/error_handler.js#L67) | <code>export function respondWithServiceError(res, error, { fallbackMessage = GENERIC_SERVER_ER…</code> | Route'ların servis hatasını 4xx mesajı ya da 500+errorId'ye çevirdiği ortak yardımcı |
| [server/src/middlewares/error_handler.js:95](../../server/src/middlewares/error_handler.js#L95) | <code>logger.error(`[${logLabel}] ${errorId}:`, error?.stack &#124;&#124; error);</code> | respondWithServiceError yolunun günlük satırı |
| [server/src/utils/validators.js:347](../../server/src/utils/validators.js#L347) | <code>console.error(`[mutation-error] error_id=${errorId}`, error?.code &#124;&#124; error?.name &#124;&#124; 'erro…</code> | Mutasyon uçlarında errorId alan adı error_id (alt çizgili) olarak döner |
| [server/src/routes/admin_routes.js:114](../../server/src/routes/admin_routes.js#L114) | <code>console.error(`[admin] ${errorId} ${fallbackMessage}`, error);</code> | Admin uçlarının beklenmeyen hata günlüğü |

**Olası nedenler**
- Kodda ya da veritabanı sorgusunda beklenmeyen hata (TypeError, pg hatası, SMTP/ağ hatası); asıl neden yalnızca günlüktedir
- Şema/migration eksik (relation/column does not exist) ya da veritabanına ulaşılamıyor
- Bilerek fırlatılan 4xx hatası değil: statusCode taşımayan ve pg code/severity içeren hatalar 500 olur

**Adım adım kontrol**
- Yanıttaki errorId değerini kopyalayın ve günlükte arayın: pm2 logs ... | grep -a <errorId>
- Günlükteki stack'ten ilgili dosya/satırı açın; pg kodu varsa (42P01 tablo yok, 23505 tekrar kayıt) altyapı girişlerine bakın
- errorId yoksa hata başka yerde (nginx 502/504) üretilmiş olabilir: altyapi-nginx-502-504

**Günlükte aranacak ifadeler**
- `[ERROR] `
- `[mutation-error] error_id=`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 500 --nostream | grep -a '\[ERROR\]'"
```

**İlgili testler:** [server/test/core_error_handler.test.js](../../server/test/core_error_handler.test.js), [server/test/members_error_helpers.test.js](../../server/test/members_error_helpers.test.js)

**Bkz.:** [sunucu-db-kesintisi-500-oturum-dusmuyor](#sunucu-db-kesintisi-500-oturum-dusmuyor), [altyapi-relation-does-not-exist](20-sunucu-altyapi-ve-yayin.md#altyapi-relation-does-not-exist), [altyapi-nginx-502-504](20-sunucu-altyapi-ve-yayin.md#altyapi-nginx-502-504)

<a id="sunucu-admin-kullanici-yonetimi-400"></a>
### sunucu-admin-kullanici-yonetimi-400 · Süper kullanıcı panelinde kullanıcı oluşturma/düzenleme/aktiflik 400/403/409 veriyor ("Kendi hesabinizi pasif yapamazsiniz", "E-posta adresi güvenlik nedeniyle değiştirilemez" vb.)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:253](../../server/src/routes/admin_routes.js#L253) | <code>adminRouter.post('/admin/users', authRequired, requireSuperUser, async (req, res) =&gt; {</code> | Kullanıcı oluşturma: validateCreateInput ardından createUser (201) |
| [server/src/routes/admin_routes.js:291](../../server/src/routes/admin_routes.js#L291) | <code>adminRouter.patch('/admin/users/:id', authRequired, requireSuperUser, async (req, res) =&gt;…</code> | Düzenleme: boş alan, kendi parolası, e-posta değişimi ve daire sakini parolası kuralları |
| [server/src/routes/admin_routes.js:327](../../server/src/routes/admin_routes.js#L327) | <code>code: 'USE_PROFILE_PASSWORD_CHANGE',</code> | Süper kullanıcı kendi parolasını bu uçtan değiştiremez (Profilim kullanılmalı) |
| [server/src/routes/admin_routes.js:370](../../server/src/routes/admin_routes.js#L370) | <code>error: 'Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez…</code> | apartment_owner/individual parolası yöneticice değiştirilemez (403) |
| [server/src/routes/admin_routes.js:362](../../server/src/routes/admin_routes.js#L362) | <code>return res.status(400).json({ error: 'E-posta adresi güvenlik nedeniyle değiştirilemez.' …</code> | Mevcut e-postası olan kullanıcıda e-posta değişikliği reddedilir |
| [server/src/utils/validators.js:72](../../server/src/utils/validators.js#L72) | <code>export function validateCreateInput({</code> | Oluşturma girdi kuralları (ad >= 3, parola >= 6, rol, telefon) |
| [server/src/utils/validators.js:351](../../server/src/utils/validators.js#L351) | <code>export function handleUserMutationError(error, res, genericErrorMessage) {</code> | 23505 çakışmaları 409 (e-posta, kullanıcı adı, kod) olur |
| [server/src/services/user_service.js:4](../../server/src/services/user_service.js#L4) | <code>export async function createUser({</code> | bcrypt ile parola özeti üretip users satırını ekler |

**Olası nedenler**
- Girdi kuralı: full_name < 3 karakter, geçersiz e-posta, parola < 6, geçersiz rol, geçersiz telefon, is_active true/false değil
- Aynı e-posta ya da kullanıcı adı zaten kayıtlı (409)
- Panelden kendi hesabı pasife alınmaya ya da kendi parolası değiştirilmeye çalışılıyor (400)
- Daire sakini (apartment_owner/individual) parolası panelden değiştirilmeye çalışılıyor (403, bilinçli güvenlik kuralı)
- Hiçbir güncellenecek alan gönderilmedi (400 "Guncellenecek alan gonderilmedi.")

**Adım adım kontrol**
- Yanıt metnini tabloyla eşleştirin; alan adları istemcinin gönderdiğiyle uyuşuyor mu (full_name, phone_number, is_active)
- SELECT user_code, email, login_name, role, is_active FROM users WHERE LOWER(email)=LOWER('...')
- 500 + errorId gelirse sunucu-hata-500-errorid girişine geçin

**İlgili testler:** [server/test/validators.test.js](../../server/test/validators.test.js), [server/test/devices_admin_routes.test.js](../../server/test/devices_admin_routes.test.js), [server/test/fix_sx2_auth.test.js](../../server/test/fix_sx2_auth.test.js)

**Bkz.:** [sunucu-admin-kullanici-silme-hata](#sunucu-admin-kullanici-silme-hata), [sunucu-yonetici-sakin-sifre-403](#sunucu-yonetici-sakin-sifre-403), [sunucu-giris-403-onay-pasif-rol](#sunucu-giris-403-onay-pasif-rol)

<a id="sunucu-admin-kullanici-silme-hata"></a>
### sunucu-admin-kullanici-silme-hata · Süper kullanıcı kullanıcıyı silemiyor: "Kullanici silinemedi." (500 + errorId), "Kendi hesabinizi silemezsiniz." ya da 404

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:428](../../server/src/routes/admin_routes.js#L428) | <code>adminRouter.delete('/admin/users/:id', authRequired, requireSuperUser, async (req, res) =…</code> | Silme ucu: tek işlemde (BEGIN/COMMIT) bağlı kayıtları temizleyip users satırını siler |
| [server/src/routes/admin_routes.js:439](../../server/src/routes/admin_routes.js#L439) | <code>return res.status(400).json({ error: 'Kendi hesabinizi silemezsiniz.' });</code> | Kendi hesabını silme engeli (400) |
| [server/src/routes/admin_routes.js:465](../../server/src/routes/admin_routes.js#L465) | <code>await client.query('DELETE FROM site_manager_sites WHERE manager_user_code = $1', [target…</code> | Bağlı satır temizliği sırası; yeni bir FK eklenip buraya eklenmezse DELETE users patlar |
| [server/src/routes/admin_routes.js:136](../../server/src/routes/admin_routes.js#L136) | <code>async function runOptionalStep(client, sql, params) {</code> | İsteğe bağlı tablolar SAVEPOINT ile atlanabilir (tablo yoksa silme bozulmaz) |
| [server/src/routes/admin_routes.js:516](../../server/src/routes/admin_routes.js#L516) | <code>console.error(`Kullanici silinirken hata (${errorId}):`, error);</code> | Başarısızlıkta ayrıntı günlüğe yazılır; istemciye yalnız errorId gider |
| [server/src/routes/admin_routes.js:505](../../server/src/routes/admin_routes.js#L505) | <code>await rotateLocalControlTokensForDeviceIds(deviceIds, 'user_deleted');</code> | Silinen kullanıcının eriştiği cihazların yerel token'ı döndürülür (başarısızlık yalnız uyarı) |

**Olası nedenler**
- Kullanıcıya bağlı, temizlik listesinde olmayan bir yabancı anahtar var (users satırı silinemez, 500)
- Silinmek istenen hesap kendi hesabı (400)
- Kullanıcı zaten silinmiş (404 "Kullanici bulunamadi.")
- Veritabanı bağlantısı/zaman aşımı (pool.connect başarısız)

**Adım adım kontrol**
- errorId ile günlükte "Kullanici silinirken hata" satırını bulun; pg hata kodu ve constraint adı hangi tablonun engellediğini söyler
- SELECT conname, conrelid::regclass FROM pg_constraint WHERE confrelid = 'users'::regclass (hangi tablolar users'a bağlı)
- Yerel token rotasyonu uyarısı "Local control token rotasyonu atlandi" silmeyi geri almaz; cihaz token'ı sonra elle döndürülebilir

**Günlükte aranacak ifadeler**
- `Kullanici silinirken hata (`
- `Local control token rotasyonu atlandi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 500 --nostream | grep -a 'Kullanici silinirken'"
```

**İlgili testler:** [server/test/devices_admin_routes.test.js](../../server/test/devices_admin_routes.test.js)

**Bkz.:** [sunucu-oturum-401-kullanici-yok](#sunucu-oturum-401-kullanici-yok), [sunucu-hata-500-errorid](#sunucu-hata-500-errorid), [sunucu-yerel-token-rotasyonu](#sunucu-yerel-token-rotasyonu)

<a id="sunucu-yonetici-daveti-eslesmedi"></a>
### sunucu-yonetici-daveti-eslesmedi · Davet edilen kişi kayıt olup e-postasını doğruladı ama site yöneticisi yetkisi gelmedi (sitede yönetici görünmüyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/site_service.js:1992](../../server/src/services/site_service.js#L1992) | <code>export async function inviteSiteManager({ siteCode, email, fullName, inviterUser }) {</code> | Kayıtsız e-posta için 7 gün geçerli PENDING davet satırı yazılır |
| [server/src/services/site_service.js:2127](../../server/src/services/site_service.js#L2127) | <code>VALUES ($1, $2, $3, $4, $5, 'PENDING', NOW() + INTERVAL '7 days')</code> | Davet 7 gün sonra süresi dolar (expires_at) |
| [server/src/services/membership_service.js:415](../../server/src/services/membership_service.js#L415) | <code>`SELECT id, site_code FROM site_manager_invitations WHERE LOWER(email) = LOWER($1) AND st…</code> | Davet YALNIZCA e-posta doğrulama kodu girilince (verifyIndividualEmailCode) uygulanır; e-posta birebir (büyük/küçük harf duyarsız) eşleşmeli |
| [server/src/services/membership_service.js:431](../../server/src/services/membership_service.js#L431) | <code>`UPDATE site_manager_invitations SET status = 'ACCEPTED' WHERE id = $1 AND status = 'PEND…</code> | Uygulanan davet ACCEPTED olur ve kullanıcı rolü site_manager yapılır |
| [server/src/services/site_service.js:2303](../../server/src/services/site_service.js#L2303) | <code>SET status = 'REVOKED'</code> | İptal edilen davet artık uygulanmaz |

**Olası nedenler**
- Kişi davetteki e-postadan FARKLI bir e-postayla kayıt oldu (eşleşme yalnız e-posta iledir)
- Davet 7 günden eski (süresi doldu) ya da yönetici tarafından iptal edildi (REVOKED)
- Kişi önceden kayıtlıydı: bu durumda yetki davette hemen verilir, bekleyen davet yazılmaz (kayıtlı hesap başka e-postayla olabilir)
- Kişi kodu henüz girmedi: bekleyen kayıtta users satırı yoktur, yetki doğrulamayla birlikte gelir

**Adım adım kontrol**
- SELECT site_code, email, status, expires_at FROM site_manager_invitations WHERE LOWER(email)=LOWER('...') ORDER BY created_at DESC
- Kullanıcının e-postası davetteki ile aynı mı: SELECT user_code, email, role FROM users WHERE LOWER(email)=LOWER('...')
- Gerekirse yönetici aynı e-postayla daveti yeniden göndersin (süreyi ve belirteci yeniler)

**İlgili testler:** [server/test/sites_manager_rules.test.js](../../server/test/sites_manager_rules.test.js), [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js)

**Bkz.:** [sunucu-yonetici-daveti-mail-yok](#sunucu-yonetici-daveti-mail-yok), [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi), [sunucu-giris-403-eposta-dogrulanmadi](#sunucu-giris-403-eposta-dogrulanmadi)

<a id="sunucu-yonetici-daveti-mail-yok"></a>
### sunucu-yonetici-daveti-mail-yok · Yönetici daveti "işleme alındı" diye başarılı görünüyor ama davet edilen kişiye e-posta gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/site_service.js:2149](../../server/src/services/site_service.js#L2149) | <code>console.error('[Mailer] Yönetici davet e-postası gönderilemedi:', mailErr?.message);</code> | Kayıtsız e-posta için gönderim hatası YUTULUR: davet satırı yazılıdır, yanıt yine ok:true |
| [server/src/services/site_service.js:2091](../../server/src/services/site_service.js#L2091) | <code>console.error('[Mailer] Yönetici ekleme bildirimi gönderilemedi:', mailErr?.message);</code> | Kayıtlı kullanıcı için bildirim hatası da yutulur (yetki zaten verilmiştir) |
| [server/src/mailer.js:240](../../server/src/mailer.js#L240) | <code>export async function sendSiteManagerInvitationEmail({</code> | Davet e-postası: SMTP_FROM/SMTP_USER yoksa hata fırlatır |
| [server/src/mailer.js:11](../../server/src/mailer.js#L11) | <code>function createTransporter() {</code> | SMTP_HOST/SMTP_USER/SMTP_PASSWORD eksikse hata; zaman aşımları 10-20 sn |
| [server/src/routes/manager_routes.js:1295](../../server/src/routes/manager_routes.js#L1295) | <code>managerRouter.post('/manager/sites/:siteCode/managers/invite', authRequired, requireSiteM…</code> | Davet ucu inviteLimiter ile korunur (saatte 20) |

**Olası nedenler**
- SMTP ayarı eksik/yanlış ya da SMTP sağlayıcısı reddediyor: davet kaydedilir ama e-posta gitmez (sessiz başarı, bilinçli tasarım)
- Posta spam klasörüne düştü ya da adres yanlış yazıldı
- Davet yanıtı e-postanın kayıtlı olup olmadığını sızdırmamak için hep aynı mesajı verir; başarı e-postanın gittiğini göstermez

**Adım adım kontrol**
- Günlükte "[Mailer] Yönetici davet e-postası gönderilemedi" ya da "Yönetici ekleme bildirimi gönderilemedi" satırını arayın; mesaj SMTP nedenini verir
- Genel SMTP durumu için sunucu-eposta-hic-cikmiyor-smtp girişine bakın
- Davet yine geçerlidir: kişi e-posta olmadan da aynı adresle kayıt olup doğrularsa yetki gelir

**Günlükte aranacak ifadeler**
- `[Mailer] Yönetici davet e-postası gönderilemedi`
- `[Mailer] Yönetici ekleme bildirimi gönderilemedi`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 500 --nostream | grep -a 'Mailer'"
```

**İlgili testler:** [server/test/mailer.test.js](../../server/test/mailer.test.js), [server/test/sites_manager_rules.test.js](../../server/test/sites_manager_rules.test.js)

**Bkz.:** [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-yonetici-daveti-eslesmedi](#sunucu-yonetici-daveti-eslesmedi)

<a id="sunucu-yonetici-cikarma-hata"></a>
### sunucu-yonetici-cikarma-hata · Site yöneticisi çıkarılamıyor: "Son yönetici çıkarılamaz", "Site Sahibi yalnızca Süper Kullanıcı tarafından çıkarılabilir" ya da 404

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:1325](../../server/src/routes/manager_routes.js#L1325) | <code>managerRouter.delete('/manager/sites/:siteCode/managers/:userCode', authRequired, require…</code> | Yönetici çıkarma ucu |
| [server/src/services/site_service.js:2166](../../server/src/services/site_service.js#L2166) | <code>export async function removeSiteManager({ siteCode, targetUserCode, callerUser }) {</code> | Tek işlem + FOR UPDATE: eşzamanlı iki çıkarma son yöneticiyi silemez |
| [server/src/utils/site_rules.js:160](../../server/src/utils/site_rules.js#L160) | <code>export function evaluateManagerRemoval({</code> | Kurallar: hedef yönetici değilse 404, son yönetici 400, kurucu (SITE_OWNER) yalnız süper kullanıcı 403 |
| [server/src/utils/site_rules.js:181](../../server/src/utils/site_rules.js#L181) | <code>message: 'Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz.',</code> | Son yönetici koruması |
| [server/src/services/site_service.js:2296](../../server/src/services/site_service.js#L2296) | <code>export async function revokeSiteManagerInvitation({ siteCode, invitationId }) {</code> | Bekleyen davet iptali: PENDING değilse 404 "İptal edilecek bekleyen davet bulunamadı." |

**Olası nedenler**
- Çıkarılmak istenen kişi sitenin tek yöneticisi (bilinçli koruma)
- Hedef kişi site kurucusu (SITE_OWNER) ve çağıran süper kullanıcı değil
- Kullanıcı o sitenin yöneticisi değil (zaten çıkarılmış)
- Davet iptalinde davet zaten kabul edilmiş/iptal edilmiş ya da başka siteye ait

**Adım adım kontrol**
- SELECT manager_user_code FROM site_manager_sites WHERE site_code = <kod>; SELECT user_code, role FROM site_memberships WHERE site_code = <kod> AND role IN ('SITE_OWNER','SITE_ADMIN') AND is_active
- Kurucuyu çıkarmak gerekiyorsa süper kullanıcı panelinden yapılmalı
- Çıkarılan kişinin yerel kontrol token'ı döndürülür; başarısızsa yanıtta local_token_rotation_ok:false gelir

**İlgili testler:** [server/test/sites_manager_rules.test.js](../../server/test/sites_manager_rules.test.js)

**Bkz.:** [sunucu-yonetici-daveti-eslesmedi](#sunucu-yonetici-daveti-eslesmedi), [sunucu-yerel-token-rotasyonu](#sunucu-yerel-token-rotasyonu), [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi)

<a id="sunucu-daire-bilgisi-eposta-gitmiyor"></a>
### sunucu-daire-bilgisi-eposta-gitmiyor · Yönetici "Giriş bilgilerini e-postayla gönder" diyor: "Mail gonderimi icin daire sakini e-postasi gerekli." / "Kullanici adi veya PIN hazir degil." / gönderim hatası

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:766](../../server/src/routes/manager_routes.js#L766) | <code>managerRouter.post('/manager/apartments/:id/send-credentials', authRequired, requireSiteM…</code> | Yönetici ucu; hata eşlemesi (400/500) burada |
| [server/src/routes/admin_routes.js:1164](../../server/src/routes/admin_routes.js#L1164) | <code>adminRouter.post('/admin/apartments/:id/send-credentials', authRequired, requireSuperUser…</code> | Süper kullanıcı eşdeğeri |
| [server/src/services/apartment_service.js:367](../../server/src/services/apartment_service.js#L367) | <code>export async function sendApartmentCredentials(apartmentId) {</code> | e-posta, kullanıcı adı ve PIN'in üçü de dolu olmalı |
| [server/src/services/apartment_service.js:373](../../server/src/services/apartment_service.js#L373) | <code>throw new Error('APARTMENT_EMAIL_REQUIRED');</code> | Dairede resident_email boş (e-posta alanı kaydedilmemiş) |
| [server/src/services/apartment_service.js:376](../../server/src/services/apartment_service.js#L376) | <code>throw new Error('APARTMENT_CREDENTIALS_NOT_READY');</code> | login_name ya da resident_pin_code boş (sakin hesabı oluşturulmamış/şifre sıfırlanmış) |
| [server/src/mailer.js:160](../../server/src/mailer.js#L160) | <code>export async function sendApartmentCredentialsEmail({</code> | SMTP gönderimi; başarısızlık 500 + error_id ile döner |

**Olası nedenler**
- Sakin kaydedilirken e-posta alanı boş bırakıldı (resident_email NULL)
- Sakin hesabı yok ya da PIN temizlenmiş (resetApartmentResident sonrası)
- SMTP ayarı eksik/yanlış: gönderim hatası 500 "Daire bilgileri e-posta ile gonderilemedi."
- Gerçek (üyelikle gelen) kullanıcıda dahili PIN yoktur: PIN yalnız dahili (@ahbu.local) hesaplarda üretilir

**Adım adım kontrol**
- SELECT id, resident_email, resident_login_name IS NOT NULL FROM apartments a LEFT JOIN users u ON u.user_code = a.resident_user_code WHERE a.id = <daire>
- Önce sakin kaydını e-postayla güncelleyin (PATCH .../resident), sonra yeniden gönderin
- SMTP için sunucu-eposta-hic-cikmiyor-smtp; 500 için errorId ile günlüğe bakın

**Günlükte aranacak ifadeler**
- `[manager] `
- `(errorId=`

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js)

**Bkz.:** [sunucu-daire-sakin-yonetimi-hata](#sunucu-daire-sakin-yonetimi-hata), [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-yonetici-sakin-sifre-403](#sunucu-yonetici-sakin-sifre-403)

<a id="sunucu-daire-sakin-yonetimi-hata"></a>
### sunucu-daire-sakin-yonetimi-hata · Yöneticinin daire sakini kaydetme/sıfırlama işlemi hata veriyor ("Sifre 4 haneli sayisal olmali.", "Daire bulunamadi.", 409 kullanıcı adı çakışması, "Bu daireyi yonetme yetkiniz yok.")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:676](../../server/src/routes/manager_routes.js#L676) | <code>managerRouter.patch('/manager/apartments/:id/resident', authRequired, requireSiteManager,…</code> | Sakin kaydetme: yetki (hasSiteManagementAccess) + doğrulama + provisionApartmentResident |
| [server/src/routes/manager_routes.js:736](../../server/src/routes/manager_routes.js#L736) | <code>managerRouter.delete('/manager/apartments/:id/resident', authRequired, requireSiteManager…</code> | Sakin sıfırlama ucu |
| [server/src/utils/validators.js:233](../../server/src/utils/validators.js#L233) | <code>export function validateApartmentResidentInput({</code> | Ad >= 3, parola 4 haneli sayı, e-posta ve telefon biçimi |
| [server/src/services/apartment_service.js:180](../../server/src/services/apartment_service.js#L180) | <code>passwordError.code = 'APARTMENT_PASSWORD_REQUIRED';</code> | YENİ sakin için 4 haneli sayısal şifre zorunlu; mevcut sakin düzenlemede boş şifre "değiştirme" sayılır |
| [server/src/services/apartment_service.js:11](../../server/src/services/apartment_service.js#L11) | <code>export async function ensureUniqueLoginName({</code> | login_name çakışırsa _2, _3... eklenir; 100 denemede bulunamazsa APARTMENT_LOGIN_GENERATION_FAILED (500) |
| [server/src/services/apartment_service.js:218](../../server/src/services/apartment_service.js#L218) | <code>const isInternalAccount = existingUserRes.rowCount &gt; 0 &amp;&amp; existingEmail.endsWith('@ahbu.l…</code> | Ad/e-posta/kullanıcı adı yalnız dahili hesapta güncellenir; üyelikle gelen gerçek kullanıcı ezilmez |
| [server/src/services/apartment_service.js:282](../../server/src/services/apartment_service.js#L282) | <code>export async function resetApartmentResident(apartmentId, db = pool) {</code> | Sıfırlama: yalnız @ahbu.local hesabı SİLİNİR; gerçek kullanıcı hesabı silinmez, yalnız daire bağı kaldırılır |

**Olası nedenler**
- Yeni sakinde şifre 4 haneli rakam değil (400, code APARTMENT_PASSWORD_REQUIRED)
- Yönetici o sitenin yöneticisi değil (403) ya da daire yok (404)
- Kullanıcı adı/e-posta başka hesapta var (409)
- Düzenlemenin gerçek kullanıcı hesabında ad/e-posta değiştirmemesi beklenen davranıştır (yalnızca daire kaydı güncellenir)

**Adım adım kontrol**
- Yanıt metnini doğrulama kurallarıyla eşleştirin; istemci password alanını 4 haneli gönderiyor mu
- SELECT id, resident_user_code, resident_email, is_active FROM apartments WHERE id = <daire>
- 500 görülürse error_id ile günlükte "[manager] provision_resident" satırına bakın

**Günlükte aranacak ifadeler**
- `[manager] `
- `(errorId=`

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js), [server/test/validators.test.js](../../server/test/validators.test.js)

**Bkz.:** [sunucu-daire-bilgisi-eposta-gitmiyor](#sunucu-daire-bilgisi-eposta-gitmiyor), [sunucu-yonetici-sakin-sifre-403](#sunucu-yonetici-sakin-sifre-403), [sunucu-sakin-kapi-listede-yok](#sunucu-sakin-kapi-listede-yok)

<a id="sunucu-katilim-basvuru-hata"></a>
### sunucu-katilim-basvuru-hata · Sakinin QR ile site katılım başvurusu reddediliyor: "Bu site katılım QR kodu geçersiz veya iptal edilmiş.", "e-posta adresinizi doğrulamanız", "zaten onay bekleyen başvuru"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/membership_routes.js:131](../../server/src/routes/membership_routes.js#L131) | <code>membershipRouter.get('/membership/join-info/:token', authRequired, async (req, res) =&gt; {</code> | QR okutulunca site bilgisi: token yoksa 404, biçim bozuksa 400 |
| [server/src/routes/membership_routes.js:151](../../server/src/routes/membership_routes.js#L151) | <code>membershipRouter.post('/membership/join-request', authRequired, async (req, res) =&gt; {</code> | Başvuru ucu (201) |
| [server/src/services/membership_service.js:953](../../server/src/services/membership_service.js#L953) | <code>export async function createJoinRequest({</code> | Doğrulama sırası: oturum, daire/blok, e-posta doğrulanmış mı, token aktif mi, daire siteye ait mi, mükerrer başvuru |
| [server/src/services/membership_service.js:1054](../../server/src/services/membership_service.js#L1054) | <code>throw httpError(409, 'Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktad…</code> | Aynı site için bekleyen başvuru varken ikincisi 409 |
| [server/src/services/membership_service.js:1110](../../server/src/services/membership_service.js#L1110) | <code>console.error(`[Mailer] Katılım bildirimi e-postası gönderilemedi (${mgr.email}):`, err.m…</code> | Yöneticiye bildirim e-postası başarısız olsa da başvuru kaydedilir (yalnız günlük) |
| [server/src/services/site_service.js:1364](../../server/src/services/site_service.js#L1364) | <code>export async function getSiteByJoinToken({ token }) {</code> | Katılım tokeninin aktif olup olmadığını çözen sorgu |
| [server/src/services/site_service.js:1307](../../server/src/services/site_service.js#L1307) | <code>export async function rotateSiteJoinToken({ siteCode, authUser = null }) {</code> | Yönetici QR'ı yeniletince eski QR geçersiz olur ("iptal edilmiş") |

**Olası nedenler**
- Site yöneticisi katılım QR'ını yeniledi: eski basılı QR artık geçersiz (404)
- Başvuran kullanıcının e-postası doğrulanmamış (403)
- Seçilen daire/blok o siteye ait değil ya da yok (400)
- Kullanıcı zaten o dairenin aktif sakini (409) ya da bekleyen başvurusu var (409)
- Yönetici bildirim e-postası gitmedi: başvuru yine de kayıtlıdır, yönetici uygulamadan listeyi açınca görür

**Adım adım kontrol**
- SELECT id, site_code, status, created_at FROM join_requests WHERE user_code = <kod> ORDER BY created_at DESC
- Yönetici panelinde güncel katılım QR'ını gösterin ve yeniden okutun
- Yanıt metnini kodla eşleştirin (yukarıdaki httpError satırları)

**Günlükte aranacak ifadeler**
- `[Mailer] Katılım bildirimi e-postası gönderilemedi`

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js), [server/test/members_claim_setup.test.js](../../server/test/members_claim_setup.test.js)

**Bkz.:** [sunucu-katilim-onay-hata](#sunucu-katilim-onay-hata), [sunucu-yonetici-katilim-qr-hata](#sunucu-yonetici-katilim-qr-hata)

<a id="sunucu-katilim-onay-hata"></a>
### sunucu-katilim-onay-hata · Yönetici katılım başvurusunu onaylayamıyor/reddedemiyor: "Bu talebi onaylama yetkiniz bulunmamaktadır.", "zaten ... durumunda", 404 ya da onaydan sonra sakin kapıyı göremiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:1224](../../server/src/routes/manager_routes.js#L1224) | <code>managerRouter.post('/manager/join-requests/:requestId/approve', authRequired, requireSite…</code> | Onay ucu |
| [server/src/routes/manager_routes.js:1245](../../server/src/routes/manager_routes.js#L1245) | <code>managerRouter.post('/manager/join-requests/:requestId/reject', authRequired, requireSiteM…</code> | Red ucu (reason en çok 500 karakter) |
| [server/src/services/membership_service.js:1276](../../server/src/services/membership_service.js#L1276) | <code>export async function approveJoinRequest({ requestId, authUser }) {</code> | Yetki durumdan ÖNCE denetlenir; PENDING değilse 409; ilk sakin APARTMENT_ADMIN, sonrakiler FAMILY_MEMBER |
| [server/src/services/membership_service.js:1316](../../server/src/services/membership_service.js#L1316) | <code>throw httpError(403, 'Bu talebi onaylama yetkiniz bulunmamaktadır.');</code> | Talebin sitesinde yönetici/SITE_ADMIN olmayan yönetici 403 alır |
| [server/src/services/membership_service.js:1333](../../server/src/services/membership_service.js#L1333) | <code>const assignedRole = adminCheckRes.rowCount === 0 ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER';</code> | Rol belirleme: dairede aktif APARTMENT_ADMIN yoksa yeni sakin yönetici olur |
| [server/src/services/membership_service.js:1395](../../server/src/services/membership_service.js#L1395) | <code>export async function rejectJoinRequest({ requestId, authUser, reason }) {</code> | Red: aynı yetki/durum kuralları; gerekçe verilmezse varsayılan metin yazılır |
| [server/src/services/membership_service.js:1192](../../server/src/services/membership_service.js#L1192) | <code>export async function getSiteJoinRequests({ siteCode, authUser, status }) {</code> | Başvuru listesi: PENDING önde; yönetici olmayan 403 |

**Olası nedenler**
- Başvuru başka bir yönetici tarafından zaten onaylandı/reddedildi (409)
- Onaylayan kişi talebin sitesinin yöneticisi değil (403) ya da talep silinmiş (404)
- Onay sonrası sakinin kapıyı görmemesi: kapı izni daire/blok politikasına ve özel kapı yetkisine bağlıdır (bkz. sunucu-sakin-kapi-listede-yok)
- Uygulama eski listeyi gösteriyor: onay sonrası listeyi yenilemek gerekir

**Adım adım kontrol**
- SELECT id, status, reviewed_by_user_code, reviewed_at FROM join_requests WHERE id = <talep>
- SELECT role, is_active FROM apartment_memberships WHERE apartment_id = <daire> AND user_code = <sakin>
- Sakin kapı göremiyorsa kapı yetkileri ve politika girişlerine bakın

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js)

**Bkz.:** [sunucu-katilim-basvuru-hata](#sunucu-katilim-basvuru-hata), [sunucu-sakin-kapi-listede-yok](#sunucu-sakin-kapi-listede-yok), [sunucu-kapi-yetkisi-yonetimi-403](#sunucu-kapi-yetkisi-yonetimi-403)

<a id="sunucu-kapi-yetkisi-yonetimi-403"></a>
### sunucu-kapi-yetkisi-yonetimi-403 · Yönetici kapı yetkisi (tekil/toplu) veremiyor: "Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır." (403), 400 ya da "Seçilen alanda aktif sakin bulunamadı."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/membership_routes.js:314](../../server/src/routes/membership_routes.js#L314) | <code>membershipRouter.get('/membership/doors/:id/permissions', authRequired, async (req, res) …</code> | Yetki ağacı (blok > daire > sakin) okuma |
| [server/src/routes/membership_routes.js:362](../../server/src/routes/membership_routes.js#L362) | <code>membershipRouter.post('/membership/doors/:id/permissions/bulk', authRequired, async (req,…</code> | Blok, daire ya da kullanıcı listesi için toplu yetki |
| [server/src/services/membership_service.js:2162](../../server/src/services/membership_service.js#L2162) | <code>export async function checkDoorManagementAccess(authUser, doorId) {</code> | Yetki kapısı: süper kullanıcı, site_manager_sites ya da aktif SITE_OWNER/SITE_ADMIN; aksi 403 |
| [server/src/services/membership_service.js:2389](../../server/src/services/membership_service.js#L2389) | <code>export async function setDoorAccessOverride({</code> | isAllowed null = varsayılana dön (override silinir); true/false = ek yetki/engel |
| [server/src/services/membership_service.js:2456](../../server/src/services/membership_service.js#L2456) | <code>export async function setBulkDoorAccessOverride({</code> | Toplu: userCodes > apartmentId > blockId önceliği; hiçbiri yoksa 400 |
| [server/src/services/membership_service.js:2409](../../server/src/services/membership_service.js#L2409) | <code>await rotateTokensForDevices({</code> | Erişim daralınca cihazın yerel kontrol token'ı döndürülür (yetki kalkan kullanıcı çevrimdışı açamasın) |
| [server/src/services/membership_rules.js:365](../../server/src/services/membership_rules.js#L365) | <code>export function overrideRevokesAccess(isAllowed) {</code> | Hangi değişikliklerin token döndürmeyi tetiklediği (reddet / varsayılana dön) |

**Olası nedenler**
- Çağıran kişi kapının sitesinin yöneticisi değil (başka site ya da sıradan sakin) -> 403
- isAllowed true/false dışında bir metin gönderildi (katı ayrıştırma 400 verir)
- Toplu istekte blok/daire/kullanıcı listesi verilmedi (400) ya da seçilen alanda aktif sakin yok (count 0)
- Hedef kullanıcı yok (404); blok/daire kapının sitesine ait değil
- Yetki verilse de kapı cihazına atanmamışsa fiziksel kapı açılmaz (bkz. sunucu-kapi-acma-409-cihaz-atanmamis)

**Adım adım kontrol**
- SELECT user_code, is_allowed, updated_at FROM door_access_overrides WHERE door_id = <kapı> ORDER BY updated_at DESC
- Çağıranın yöneticiliği: SELECT 1 FROM site_manager_sites WHERE site_code = <site> AND manager_user_code = <kod>
- Yetki verildikten sonra sakin listesinde kapıyı görmüyorsa sunucu-sakin-kapi-listede-yok

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js), [server/test/members_membership_rules.test.js](../../server/test/members_membership_rules.test.js)

**Bkz.:** [sunucu-sakin-kapi-listede-yok](#sunucu-sakin-kapi-listede-yok), [sunucu-katilim-onay-hata](#sunucu-katilim-onay-hata), [sunucu-daire-uye-yonetimi-hata](#sunucu-daire-uye-yonetimi-hata)

<a id="sunucu-daire-uye-yonetimi-hata"></a>
### sunucu-daire-uye-yonetimi-hata · Daire üyesi çıkarma/pasife alma/silme/aile reisi değiştirme hata veriyor ("Daire yöneticisi kendi kendisini daireden çıkaramaz", "yalnızca site yöneticilerine aittir", "Mevcut şifre hatalı")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/membership_service.js:1559](../../server/src/services/membership_service.js#L1559) | <code>export async function checkApartmentManagementAccess(authUser, apartmentId) {</code> | Daireyi yönetme yetkisi: süper kullanıcı, site yöneticisi ya da dairenin aktif yöneticisi (APARTMENT_ADMIN) |
| [server/src/services/membership_service.js:1711](../../server/src/services/membership_service.js#L1711) | <code>export async function removeApartmentMember({ apartmentId, targetUserCode, authUser }) {</code> | Üye çıkarma; daire yöneticisi kendini çıkaramaz (400); gerekirse daire devri yapılır |
| [server/src/services/membership_service.js:1790](../../server/src/services/membership_service.js#L1790) | <code>export async function toggleApartmentMemberStatus({ apartmentId, targetUserCode, isActive…</code> | Aktif/pasif: daire yöneticisi kendini pasife alamaz |
| [server/src/services/membership_service.js:1897](../../server/src/services/membership_service.js#L1897) | <code>export async function deleteApartmentMember({ apartmentId, targetUserCode, authUser }) {</code> | Kalıcı silme yalnızca süper kullanıcı/site yöneticisi |
| [server/src/services/membership_service.js:1963](../../server/src/services/membership_service.js#L1963) | <code>export async function changeApartmentMemberPassword({</code> | Yalnız kullanıcının KENDİ şifresi ve mevcut şifre zorunlu; başkasınınki 403 |
| [server/src/services/membership_service.js:2081](../../server/src/services/membership_service.js#L2081) | <code>export async function setApartmentPrimaryAdmin({ apartmentId, targetUserCode, authUser })…</code> | Aile reisi değiştirme |
| [server/src/services/membership_service.js:1630](../../server/src/services/membership_service.js#L1630) | <code>async function cleanupDoorOverridesIfNoMembership(client, siteCode, userCode) {</code> | Üyelik bitince o sitede başka üyeliği kalmayan kullanıcının özel kapı izinleri silinir |

**Olası nedenler**
- Çağıran kişi dairenin yöneticisi ya da site yöneticisi değil (403 "Bu daireyi yönetme yetkiniz bulunmamaktadır.")
- Daire yöneticisi kendi kendini çıkarmaya/pasife almaya çalışıyor (önce başka birini yönetici yapmalı)
- Aile üyesi silmeye daire yöneticisi çalışıyor: kalıcı silme yalnız site yöneticisinde
- Hedef kullanıcı o dairede kayıtlı değil (404)
- Şifre değişiminde mevcut şifre yanlış ya da başka kullanıcı adına deneme (güvenlik kuralı)

**Adım adım kontrol**
- SELECT user_code, role, is_active FROM apartment_memberships WHERE apartment_id = <daire>
- Yanıt metnini yukarıdaki httpError satırlarıyla eşleştirin
- Şifre için profil ekranındaki "şifre değiştir" kullanılmalı (sunucu-profil-parola-degistirme-hata)

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js)

**Bkz.:** [sunucu-kapi-yetkisi-yonetimi-403](#sunucu-kapi-yetkisi-yonetimi-403), [sunucu-daire-sakin-yonetimi-hata](#sunucu-daire-sakin-yonetimi-hata), [sunucu-yonetici-sakin-sifre-403](#sunucu-yonetici-sakin-sifre-403)

<a id="sunucu-yonetici-katilim-qr-hata"></a>
### sunucu-yonetici-katilim-qr-hata · Yönetici panelinde site katılım QR'ı alınamıyor ya da yenilenemiyor ("Site katilim QR kodu alinamadi.", "Bu siteyi yonetme yetkiniz yok.")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:540](../../server/src/routes/manager_routes.js#L540) | <code>managerRouter.get('/manager/sites/:id/join-token', authRequired, requireSiteManager, asyn…</code> | Aktif katılım tokenini getirir (yoksa oluşturur) |
| [server/src/routes/manager_routes.js:565](../../server/src/routes/manager_routes.js#L565) | <code>managerRouter.post('/manager/sites/:id/join-token/rotate', authRequired, requireSiteManag…</code> | Yeni token üretir; eski QR'lar iptal edilir |
| [server/src/services/site_service.js:1234](../../server/src/services/site_service.js#L1234) | <code>export async function getOrCreateSiteJoinToken({ siteCode, authUser = null }) {</code> | Siteyi kilitler (FOR NO KEY UPDATE), aktif token yoksa üretir |
| [server/src/services/site_service.js:1307](../../server/src/services/site_service.js#L1307) | <code>export async function rotateSiteJoinToken({ siteCode, authUser = null }) {</code> | Eskiyi pasifleştirip yenisini yazar |
| [server/src/services/site_service.js:293](../../server/src/services/site_service.js#L293) | <code>export async function hasSiteManagementAccess(authUser, siteCode) {</code> | Yönetim yetkisi: süper kullanıcı, site_manager_sites ya da aktif SITE_OWNER/SITE_ADMIN |

**Olası nedenler**
- Çağıran kişi o sitenin yöneticisi değil (403)
- Site silinmiş (404 "Site bulunamadi.")
- Veritabanı hatası: site_join_tokens tablosu yok ya da bağlantı sorunu (500 + error_id)
- Yeni QR yaratıldığında eski basılı QR'lar sakinler için geçersiz olur (beklenen davranış)

**Adım adım kontrol**
- SELECT site_code, is_active, created_at FROM site_join_tokens WHERE site_code = <site> ORDER BY created_at DESC LIMIT 5 (token değeri yazdırılmaz)
- 500 için error_id ile günlükte "[manager] join_token" satırını arayın
- Sakin tarafı hatası için sunucu-katilim-basvuru-hata

**İlgili testler:** [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js)

**Bkz.:** [sunucu-katilim-basvuru-hata](#sunucu-katilim-basvuru-hata), [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi)

<a id="sunucu-site-silme-cift-onay"></a>
### sunucu-site-silme-cift-onay · Site silme isteği silmiyor, "Site silme talebi oluşturuldu... onayı gerekmektedir" diyor ya da "Bu silme talebini yalnızca ... onaylayabilir" (403)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/site_service.js:1506](../../server/src/services/site_service.js#L1506) | <code>export async function requestSiteDeletion({ siteCode, authUser }) {</code> | Çift taraflı teyit: ilk talep bekletilir, karşı taraf onaylayınca silinir; yöneticisiz sitede süper kullanıcı doğrudan siler |
| [server/src/services/site_service.js:1632](../../server/src/services/site_service.js#L1632) | <code>export async function approveSiteDeletion({ siteCode, authUser }) {</code> | Bekleyen talebi YALNIZ karşı rol onaylayabilir (talep süper kullanıcıdansa yönetici, yöneticiden ise süper kullanıcı) |
| [server/src/services/site_service.js:1679](../../server/src/services/site_service.js#L1679) | <code>export async function rejectOrCancelSiteDeletion({ siteCode, authUser }) {</code> | Talebi iptal/red: deletion_status none yapılır; bekleyen yoksa 400 |
| [server/src/services/site_service.js:1429](../../server/src/services/site_service.js#L1429) | <code>export async function deleteSitePermanently(siteCode, authUser) {</code> | Kalıcı silme: daire kullanıcıları silinmez; cihaz yerel token'ı döndürülür |
| [server/src/routes/manager_routes.js:473](../../server/src/routes/manager_routes.js#L473) | <code>managerRouter.delete('/manager/sites/:id', authRequired, requireSiteManager, async (req, …</code> | Yönetici silme talebi ucu |
| [server/src/routes/admin_routes.js:1009](../../server/src/routes/admin_routes.js#L1009) | <code>adminRouter.delete('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) =…</code> | Süper kullanıcı silme talebi ucu |
| [server/src/routes/admin_routes.js:1024](../../server/src/routes/admin_routes.js#L1024) | <code>adminRouter.post('/admin/sites/:id/approve-deletion', authRequired, requireSuperUser, asy…</code> | Süper kullanıcının yönetici talebini onay ucu |

**Olası nedenler**
- Bu bilinçli iki taraflı onay akışıdır: talep eden taraf tek başına silemez
- Onay bekleyen talebi yanlış rol onaylamaya çalışıyor (403)
- Bekleyen talep yokken onay/red çağrıldı (400)
- Siteyi silen kişinin yetkisi yok (403 "Bu siteyi silme yetkiniz bulunmamaktadır.")
- Süper kullanıcı e-posta kodu yolunu kullanıyorsa kod akışına bakın (bkz. sunucu-site-silme-kodu-hata)

**Adım adım kontrol**
- SELECT site_code, deletion_status, deletion_requested_by_role, deletion_requested_at FROM sites WHERE site_code = <site>
- İstekte bulunan rolü ve beklenen onaylayan rolü karşılaştırın
- Günlükte JSON satırında "site_deleted" olayı silmenin gerçekleştiğini gösterir

**Günlükte aranacak ifadeler**
- `site_deleted`

**İlgili testler:** [server/test/sites_manager_rules.test.js](../../server/test/sites_manager_rules.test.js), [server/test/sites_source_guards.test.js](../../server/test/sites_source_guards.test.js)

**Bkz.:** [sunucu-site-silme-kodu-hata](#sunucu-site-silme-kodu-hata), [ui-site-silme-akisi](31-uygulama-arayuz.md#ui-site-silme-akisi), [sunucu-yetki-403-site-yoneticisi](#sunucu-yetki-403-site-yoneticisi)

<a id="sunucu-site-silme-kodu-hata"></a>
### sunucu-site-silme-kodu-hata · Süper kullanıcı e-posta kodu ile siteyi silemiyor: kod gelmiyor, "silme doğrulama kodu hatalı", "10 dakikalık süresi dolmuş" ya da "Çok fazla hatalı doğrulama denemesi" (429)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/site_service.js:1731](../../server/src/services/site_service.js#L1731) | <code>export async function requestSiteDeletionEmailCode({ siteCode, authUser }) {</code> | Süper kullanıcının KENDİ e-postasına 6 haneli kod; 10 dk geçerli |
| [server/src/services/site_service.js:1813](../../server/src/services/site_service.js#L1813) | <code>export async function confirmSiteDeletionWithEmailCode({ siteCode, code, authUser }) {</code> | Kod doğrulama + tek kullanımlık tüketim + kalıcı silme |
| [server/src/services/site_service.js:1804](../../server/src/services/site_service.js#L1804) | <code>const deletionCodeAttempts = createAttemptTracker({</code> | Site+kullanıcı başına 5 hatada 15 dk kilit ve kod iptali |
| [server/src/services/site_service.js:1904](../../server/src/services/site_service.js#L1904) | <code>const err = new Error('Bu silme doğrulama kodu artık geçerli değil. Lütfen yeni bir kod i…</code> | Atomik tüketim: eşzamanlı ikinci istek aynı kodla silemez |
| [server/src/routes/admin_routes.js:1069](../../server/src/routes/admin_routes.js#L1069) | <code>adminRouter.post('/admin/sites/:id/confirm-email-deletion', authRequired, requireSuperUse…</code> | Doğrulama ucu ayrıca adminSensitiveLimiter ile sınırlı (15 dk'da 10) |
| [server/src/mailer.js:196](../../server/src/mailer.js#L196) | <code>export async function sendSuperUserSiteDeletionEmail({</code> | Kod e-postası; SMTP yoksa gönderim hatası |

**Olası nedenler**
- Kod e-postası gelmedi (SMTP sorunu) ya da süper kullanıcı hesabında e-posta yok (400)
- Kod 10 dakikayı geçti ya da yeni kod istenince eskisi geçersiz oldu
- 5 yanlış denemede kod iptal edilir ve 15 dk kilit uygulanır (429)
- Kod 6 haneli rakam değil (400)
- Çağıran süper kullanıcı değil (403)

**Adım adım kontrol**
- Süper kullanıcı hesabının e-postası var mı: SELECT email FROM users WHERE user_code = <kod>
- Yeni kod isteyip son gelen koda 10 dk içinde girin
- E-posta için sunucu-eposta-hic-cikmiyor-smtp; hız sınırı için sunucu-429-genel-hiz-siniri

**İlgili testler:** [server/test/sites_manager_rules.test.js](../../server/test/sites_manager_rules.test.js), [server/test/fix_sx2_site_policy.test.js](../../server/test/fix_sx2_site_policy.test.js)

**Bkz.:** [sunucu-site-silme-cift-onay](#sunucu-site-silme-cift-onay), [sunucu-eposta-hic-cikmiyor-smtp](#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-kapi-cihaz-atama-403"></a>
### sunucu-kapi-cihaz-atama-403 · Kapıya cihaz atanamıyor/değiştirilemiyor: "Bu cihaz yonettiginiz siteye atanamaz." (403), "baska bir kullanici hesabi tarafindan sahiplenilmis" (409), "arizali" (409), "Site sirket tarafindan onaylanmadan..." (403)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:799](../../server/src/routes/manager_routes.js#L799) | <code>managerRouter.patch('/manager/doors/:id/device', authRequired, requireSiteManager, async …</code> | Atama ucu: yetki, site onayı (siteHasApprovedStatus), uid doğrulama, updateDoorDeviceAssignment |
| [server/src/routes/manager_routes.js:816](../../server/src/routes/manager_routes.js#L816) | <code>return res.status(403).json({ error: 'Site sirket tarafindan onaylanmadan cihaza kapi ata…</code> | Şirket onayı olmayan sitede atama 403 |
| [server/src/routes/manager_routes.js:872](../../server/src/routes/manager_routes.js#L872) | <code>managerRouter.post('/manager/doors/:id/replace-device', authRequired, requireSiteManager,…</code> | Cihaz değiştirme: eski kapı yetkileri/ayarları korunur |
| [server/src/services/door_service.js:143](../../server/src/services/door_service.js#L143) | <code>export async function updateDoorDeviceAssignment({</code> | Cihaz uid ile bulunur; isDeviceAssignableToManagedSite false ise DEVICE_NOT_ASSIGNABLE |
| [server/src/services/site_service.js:391](../../server/src/services/site_service.js#L391) | <code>export function isDeviceAssignableToManagedSite(device, managedSiteCodes, targetSiteCode,…</code> | Atanabilirlik kuralı: arızalı değil, hedef site yönetilen sitelerde, başka sahibin cihazı değil; sahiplenilmemiş serbest envanter cihazı doğrudan atanamaz |
| [server/src/utils/site_rules.js:474](../../server/src/utils/site_rules.js#L474) | <code>const DOOR_ERROR_MAP = {</code> | Servis kodu -> HTTP durum/mesaj eşlemesi (404/403/409) |
| [server/src/services/door_service.js:819](../../server/src/services/door_service.js#L819) | <code>export async function replaceDoorDevice({ doorId, newDeviceInput, newDeviceId, authUser }…</code> | Değiştirmede DEVICE_DEFECTIVE / DEVICE_OWNED_BY_ANOTHER / DEVICE_NOT_ASSIGNABLE kodları burada fırlatılır |

**Olası nedenler**
- Yönetici cihazı önce kutu QR/seri no ile SAHİPLENMEDİ: sahipsiz şirket envanteri cihazı doğrudan kapıya atanamaz (bilinçli kural)
- Cihaz başka kullanıcıya ait ya da başka (yönetilmeyen) sitenin kapısına bağlı
- Cihaz arızalı işaretli (devices.is_defective)
- Site henüz şirket tarafından onaylanmamış (approval durumu)
- Cihaz uid şirket kaydında yok (404 "Cihaz sirket hesabinda kayitli degil.")
- Cihaz uid en az 6 karakter olmalı (400)

**Adım adım kontrol**
- SELECT device_uid, site_code, owner_user_id, assigned_user_code, is_defective FROM devices WHERE device_uid = '<UID>'
- SELECT site_code, approval_status FROM sites WHERE site_code = <site>
- Sahiplenme için önce "Cihaz sahiplen" akışı: sunucu-cihaz-sahiplenme-hata
- Atama sonrası MQTT yetkisi için altyapi-acl-senkron-503 girişine

**İlgili testler:** [server/test/device_assignment.test.js](../../server/test/device_assignment.test.js), [server/test/fix_sx2_door_owner.test.js](../../server/test/fix_sx2_door_owner.test.js), [server/test/fix_sx2_door_errors.test.js](../../server/test/fix_sx2_door_errors.test.js)

**Bkz.:** [sunucu-cihaz-sahiplenme-hata](#sunucu-cihaz-sahiplenme-hata), [sunucu-kapi-acma-409-cihaz-atanmamis](#sunucu-kapi-acma-409-cihaz-atanmamis), [ui-kapi-cihaz-ata](31-uygulama-arayuz.md#ui-kapi-cihaz-ata), [altyapi-acl-senkron-503](20-sunucu-altyapi-ve-yayin.md#altyapi-acl-senkron-503)

<a id="sunucu-guvenlik-politikasi-hata"></a>
### sunucu-guvenlik-politikasi-hata · Site güvenlik politikası kaydedilemiyor: "Giris yontemi yetkilendirmesi ... yalnizca super user", "En az bir giris yontemi ... acik olmalidir", "Konum dogrulamasi acikken gecerli bir enlem ve boylam ..."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/manager_routes.js:218](../../server/src/routes/manager_routes.js#L218) | <code>async function handleSecurityPolicyPatch(req, res) {</code> | Tek işleyici: /manager/... (yönetici + süper kullanıcı) ve /admin/... (yalnız süper kullanıcı) |
| [server/src/utils/site_rules.js:299](../../server/src/utils/site_rules.js#L299) | <code>export function parseSecurityPolicyBody(body) {</code> | Alan biçimi: true/false bayrakları, enlem -90..90, boylam -180..180, yarıçap sınırı, QR dönüş süresi kıstırılır |
| [server/src/utils/site_rules.js:378](../../server/src/utils/site_rules.js#L378) | <code>export function resolveSecurityPolicyUpdate({ patch, existing, isSuperUser }) {</code> | İş kuralları: giriş yöntemi bayraklarını yalnız süper kullanıcı değiştirir; en az bir yöntem açık; konum açıkken koordinat zorunlu |
| [server/src/utils/site_rules.js:415](../../server/src/utils/site_rules.js#L415) | <code>error: 'En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir.',</code> | Hem uzaktan hem QR kapatılamaz (400) |
| [server/src/utils/site_rules.js:462](../../server/src/utils/site_rules.js#L462) | <code>error: 'Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur.',</code> | require_geofence açıkken site merkezi koordinatı şart (400) |
| [server/src/services/site_service.js:93](../../server/src/services/site_service.js#L93) | <code>export async function updateSiteByCode({</code> | Politika alanlarını sites satırına yazar |

**Olası nedenler**
- Site yöneticisi, süper kullanıcıya ait "Mobil Uygulama/QR" açma-kapama bayrağını değiştirmeye çalışıyor (403); aynı değeri göndermek zararsızdır
- Her iki giriş yöntemi de kapatılmak isteniyor (400)
- Konum doğrulaması açıldı ama enlem/boylam boş ya da aralık dışı (400)
- Yarıçap izinli aralığın dışında (400 "Konum yaricapi ... arasinda olmalidir.")
- Politika kaydedilse de kapı açma/QR kanalı etkisi için bkz. sunucu-kapi-acma-403-uzaktan-kapali ve sunucu-karekod-politika-kapali

**Adım adım kontrol**
- SELECT feature_remote_open_enabled, feature_qr_enabled, qr_entry_active, require_geofence, geofence_latitude, geofence_longitude, geofence_radius_meters FROM sites WHERE site_code = <site>
- İsteği yapan rol: süper kullanıcı mı site yöneticisi mi (rol bayrak değiştirme yetkisini belirler)
- Konumu açmadan önce site merkez koordinatını kaydedin

**İlgili testler:** [server/test/sites_security_policy.test.js](../../server/test/sites_security_policy.test.js), [server/test/fix_sx2_site_policy.test.js](../../server/test/fix_sx2_site_policy.test.js)

**Bkz.:** [sunucu-kapi-acma-403-uzaktan-kapali](#sunucu-kapi-acma-403-uzaktan-kapali), [sunucu-karekod-politika-kapali](#sunucu-karekod-politika-kapali), [sunucu-geofence-menzil-disi](#sunucu-geofence-menzil-disi)

<a id="sunucu-cihaz-sahiplenme-hata"></a>
### sunucu-cihaz-sahiplenme-hata · Kutu QR/seri no ile cihaz sahiplenme reddediliyor: "şirket envanterinde kayıtlı değildir" (404), "başka bir kullanıcı hesabı tarafından sahiplenilmiş" (409), "arızalı olarak işaretlenmiştir" (400), "e-posta adresinizi doğrulamanız" (403)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/membership_routes.js:72](../../server/src/routes/membership_routes.js#L72) | <code>membershipRouter.post('/membership/claim-device', authRequired, claimDeviceLimiter, async…</code> | Sahiplenme ucu; deviceInput ya da deviceUid alır; claimDeviceLimiter ile korunur |
| [server/src/services/membership_service.js:523](../../server/src/services/membership_service.js#L523) | <code>export async function claimDevice({ userCode, deviceInput }) {</code> | Doğrulama: e-posta doğrulanmış, cihaz envanterde, arızalı değil, sahibi yok; atomik UPDATE; ilk sahiplenmede rol site_manager olur |
| [server/src/services/membership_rules.js:297](../../server/src/services/membership_rules.js#L297) | <code>export function normalizeClaimDeviceInput(deviceInput) {</code> | GD-C3-<UID>, MAC (: ve -), URL ve DEVICE: önekleri ayıklanarak UID'ye indirgenir |
| [server/src/services/membership_rules.js:275](../../server/src/services/membership_rules.js#L275) | <code>export const SQL_CLAIM_DEVICE_ATOMIC = `</code> | Yalnız sahibi olmayan ve arızalı olmayan cihaz güncellenir (yarış koruması) |
| [server/src/services/membership_service.js:565](../../server/src/services/membership_service.js#L565) | <code>'Bu cihaz şirket envanterinde kayıtlı değildir. Lütfen geçerli bir şirket cihazı karekodu…</code> | 404: UID şirket aracının kayıt ettiği devices tablosunda yok |
| [server/src/routes/admin_routes.js:1529](../../server/src/routes/admin_routes.js#L1529) | <code>adminRouter.post('/admin/devices/:id/release-ownership', authRequired, requireSuperUser, …</code> | Sahipliği serbest bırakma (süper kullanıcı): başka kullanıcıya devir için gerekir |

**Olası nedenler**
- Cihaz şirket aracıyla (company_qr_tool) kaydedilmemiş: devices tablosunda satır yok
- Cihaz daha önce başka hesaba sahiplendirilmiş: sahip ya da şirket sahipliği serbest bırakmalı
- Cihaz arızalı işaretli (is_defective)
- Kullanıcının e-postası doğrulanmamış (403)
- Çok sayıda deneme: 10 dk'da 10 istek sınırı (429, claimDeviceLimiter)
- Kare kod içeriği boş ya da 256 karakterden uzun (400)

**Adım adım kontrol**
- SELECT device_uid, owner_user_id, assigned_user_code, is_defective, site_code FROM devices WHERE UPPER(REPLACE(REPLACE(device_uid, ':', ''), '-', '')) = '<UID>'
- Kayıtlı değilse şirket aracıyla cihaz kaydını ve etiketini kontrol edin (arac-* girişleri)
- Başka sahip varsa süper kullanıcı panelinden "sahipliği serbest bırak" yapılır

**İlgili testler:** [server/test/members_claim_setup.test.js](../../server/test/members_claim_setup.test.js), [server/test/fix_sx2_membership.test.js](../../server/test/fix_sx2_membership.test.js)

**Bkz.:** [sunucu-site-kurulumu-hata](#sunucu-site-kurulumu-hata), [sunucu-kapi-cihaz-atama-403](#sunucu-kapi-cihaz-atama-403), [ui-cihaz-sahiplen](31-uygulama-arayuz.md#ui-cihaz-sahiplen), [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-site-kurulumu-hata"></a>
### sunucu-site-kurulumu-hata · Site kurulum sihirbazı hata veriyor: "Site kurmak için önce bir cihaz sahiplenmelisiniz.", "Belirtilen cihaz hesabınıza ait değil.", "En fazla ... blok tanımlanabilir", "Cok fazla site kurulum denemesi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/membership_routes.js:105](../../server/src/routes/membership_routes.js#L105) | <code>membershipRouter.post('/membership/setup-site', authRequired, setupSiteLimiter, async (re…</code> | Kurulum ucu (201); setupSiteLimiter: 10 dk'da 10 (kullanıcı) |
| [server/src/services/membership_service.js:703](../../server/src/services/membership_service.js#L703) | <code>export async function setupSiteWithClaimedDevice({</code> | Tek işlemde site + SITE_OWNER + bloklar + daireler + kapılar; cihaz 1. kapıya atanır; hata olursa hiçbir şey kurulmaz (ROLLBACK) |
| [server/src/services/membership_service.js:772](../../server/src/services/membership_service.js#L772) | <code>throw httpError(400, 'Site kurmak için önce bir cihaz sahiplenmelisiniz.');</code> | Bireysel kullanıcı cihazsız site kuramaz; süper kullanıcı ve zaten yönetici olanlar kurabilir |
| [server/src/services/membership_service.js:769](../../server/src/services/membership_service.js#L769) | <code>throw httpError(404, 'Belirtilen cihaz hesabınıza ait değil.');</code> | deviceUid verildiyse kullanıcıya ait olmalı |
| [server/src/services/membership_rules.js:440](../../server/src/services/membership_rules.js#L440) | <code>export function normalizeSetupSiteInput({</code> | Ad zorunlu ve <= 120; blok adları benzersiz; üst sınırlar |
| [server/src/utils/validators.js:13](../../server/src/utils/validators.js#L13) | <code>export const SITE_LIMITS = Object.freeze({</code> | En çok 100 blok, 5000 daire, 100 kapı (taşma/şişme koruması) |
| [server/src/routes/membership_routes.js:34](../../server/src/routes/membership_routes.js#L34) | <code>export const setupSiteLimiter = createRuleLimiter({</code> | Kurulum hız sınırı tanımı |

**Olası nedenler**
- Kullanıcı henüz cihaz sahiplenmedi (bireysel hesap için zorunlu)
- Gönderilen deviceUid başka hesaba ait ya da yok (404)
- Site adı boş/uzun, blok adı tekrar ediyor ya da blok/daire/kapı sayısı üst sınırı aşıyor (400)
- Kısa sürede çok kurulum denemesi (429)

**Adım adım kontrol**
- SELECT device_uid, site_code FROM devices WHERE owner_user_id = (SELECT id FROM users WHERE user_code = <kod>)
- Yanıt gövdesindeki hata metnini yukarıdaki httpError satırlarıyla eşleştirin
- Kurulan site yapısını görmek için GET /manager/sites/:id/structure

**İlgili testler:** [server/test/members_claim_setup.test.js](../../server/test/members_claim_setup.test.js), [server/test/sites_ids.test.js](../../server/test/sites_ids.test.js)

**Bkz.:** [sunucu-cihaz-sahiplenme-hata](#sunucu-cihaz-sahiplenme-hata), [ui-kurulum-sihirbazi](31-uygulama-arayuz.md#ui-kurulum-sihirbazi), [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-cors-tarayici-engeli"></a>
### sunucu-cors-tarayici-engeli · Web (tarayıcı) sürümü API'ye erişemiyor: konsolda CORS hatası, istek "blocked by CORS policy"; mobil uygulama sorunsuz

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/config/cors.js:21](../../server/src/config/cors.js#L21) | <code>export function buildCorsAllowlist(env = process.env) {</code> | İzin listesi yalnız CORS_ORIGINS + PUBLIC_APP_URL + PUBLIC_BASE_URL'den kurulur; geçersiz/"*" değerler reddedilir |
| [server/src/config/cors.js:4](../../server/src/config/cors.js#L4) | <code>export function normalizeOrigin(value) {</code> | Kaynak biçimi: şema+alan adı+port; "*" ve "null" kabul edilmez; şemasız değer https:// varsayılır |
| [server/src/config/cors.js:53](../../server/src/config/cors.js#L53) | <code>export function isOriginAllowed(origin, allowlist) {</code> | localhost / 127.0.0.1 her zaman izinli; diğerleri listede olmalı |
| [server/src/config/cors.js:65](../../server/src/config/cors.js#L65) | <code>export function createCorsOptionsDelegate(allowlist) {</code> | Listede olmayan Origin için hiçbir CORS başlığı eklenmez; listedekine credentials+Retry-After açığa çıkarılır |
| [server/src/config/env.js:140](../../server/src/config/env.js#L140) | <code>warnings.push('CORS allowlist bos (CORS_ORIGINS/PUBLIC_APP_URL/PUBLIC_BASE_URL); tarayici…</code> | Hiçbiri tanımlı değilse açılışta uyarı yazılır |

**Olası nedenler**
- Web uygulamasının yayın adresi CORS_ORIGINS/PUBLIC_APP_URL/PUBLIC_BASE_URL içinde yok (.env değişikliği sonrası PM2 yeniden başlatma gerekir)
- Adres yanlış yazılmış (http/https, www, port farkı ayrı kaynaktır)
- Listeye "*" yazıldı: bilinçli olarak reddedilir
- Mobil uygulama Origin göndermez, bu yüzden etkilenmez; sorun yalnız tarayıcıdadır

**Adım adım kontrol**
- Tarayıcı geliştirici araçlarında isteğin Origin başlığına bakın ve .env'deki listeyle karşılaştırın (değeri .env'den yazdırmak yerine yalnız alan adını doğrulayın)
- Açılış günlüğünde "[ENV] UYARI:" satırlarında CORS uyarısı var mı
- .env düzeltildiyse uygulama yeniden başlatılmalı (altyapi-env-degisikligi-etkisiz)

**Günlükte aranacak ifadeler**
- `[ENV] UYARI:`

**Komutlar**
```bash
curl -s -i -H "Origin: https://ornek.alan" https://api.gudeteknoloji.com.tr/health
```

**İlgili testler:** [server/test/core_cors.test.js](../../server/test/core_cors.test.js)

**Bkz.:** [altyapi-env-degisikligi-etkisiz](20-sunucu-altyapi-ve-yayin.md#altyapi-env-degisikligi-etkisiz), [altyapi-env-uyari-eksik-ayarlar](20-sunucu-altyapi-ve-yayin.md#altyapi-env-uyari-eksik-ayarlar)

<a id="sunucu-istek-gunlugu-ve-basliklar"></a>
### sunucu-istek-gunlugu-ve-basliklar · Günlükte istek satırı yok/eksik ya da gizli değer (token, kod) görünüyor; ya da sayfa iframe içinde açılmıyor (X-Frame-Options)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/request_logger.js:45](../../server/src/middlewares/request_logger.js#L45) | <code>export function createRequestLogger({ logger = console, skipPaths = ['/health'] } = {}) {</code> | Her yanıtta "[API] YÖNTEM URL -> DURUM (ms)" satırı; /health günlüğe yazılmaz |
| [server/src/middlewares/request_logger.js:37](../../server/src/middlewares/request_logger.js#L37) | <code>export function maskSensitiveUrl(url) {</code> | Sorgudaki token/code/key..., bilinen yol önekleri ve 24+ karakterli uzun segmentler *** olur |
| [server/src/middlewares/request_logger.js:3](../../server/src/middlewares/request_logger.js#L3) | <code>const SENSITIVE_QUERY_KEYS = [</code> | Maskelenen sorgu anahtarları listesi (yeni gizli parametre eklenince buraya eklenmeli) |
| [server/src/middlewares/security_headers.js:4](../../server/src/middlewares/security_headers.js#L4) | <code>export function createSecurityHeaders({ frameExemptPrefixes = [] } = {}) {</code> | nosniff, Referrer-Policy, Permissions-Policy; X-Frame-Options DENY (muaf yollar hariç); HSTS yalnız HTTPS isteklerde |
| [server/src/middlewares/security_headers.js:13](../../server/src/middlewares/security_headers.js#L13) | <code>res.setHeader('X-Frame-Options', 'DENY');</code> | Çerçeve içine gömme engeli; misafir sayfası gibi muaf önekler dışında geçerli |

**Olası nedenler**
- /health isteği bilerek günlüğe yazılmaz (skipPaths)
- İstek, uygulamaya ulaşmadan nginx'te sonlanmış olabilir (günlük satırı yoktur)
- Gizli bir parametre adı maskeleme listesinde yok: değer açık yazılır
- Sayfa iframe'de açılmıyorsa X-Frame-Options: DENY nedeniyledir (bilinçli); muaflık createSecurityHeaders çağrısındaki frameExemptPrefixes ile verilir

**Adım adım kontrol**
- pm2 logs içinde "[API]" satırlarını arayın; yok ise istek sunucuya ulaşmamıştır (nginx günlüğü)
- Yeni token/gizli sorgu parametresi eklendiyse SENSITIVE_QUERY_KEYS listesine ekleyin ve core_log_mask testini güncelleyin
- curl -I ile yanıt başlıklarını kontrol edin

**Günlükte aranacak ifadeler**
- `[API] `

**Komutlar**
```bash
curl -s -I https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 50 --nostream"
```

**İlgili testler:** [server/test/core_log_mask.test.js](../../server/test/core_log_mask.test.js)

**Bkz.:** [altyapi-nginx-502-504](20-sunucu-altyapi-ve-yayin.md#altyapi-nginx-502-504), [sunucu-misafir-sayfa-acilmiyor](#sunucu-misafir-sayfa-acilmiyor)

<a id="sunucu-kimlik-gecersiz-400"></a>
### sunucu-kimlik-gecersiz-400 · Uç "Gecersiz ... ID/kodu" (400) veriyor; geçerli görünen bir kimlikle bile (örn. "1e3", boşluklu, çok büyük sayı) reddediliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/utils/ids.js:13](../../server/src/utils/ids.js#L13) | <code>export function parseId(value, { max = Number.MAX_SAFE_INTEGER } = {}) {</code> | Yalnız 1-16 haneli ondalık rakam kabul edilir; "1e3", "0x10", ondalık, negatif, sıfır ve üst sınırı aşan değer null olur |
| [server/src/utils/ids.js:37](../../server/src/utils/ids.js#L37) | <code>export function parseOptionalId(value, options) {</code> | Alan hiç gelmediyse undefined, geldi ama bozuksa null (400 ile reddedilir) |
| [server/src/utils/ids.js:6](../../server/src/utils/ids.js#L6) | <code>export const INT32_MAX = 2147483647;</code> | PostgreSQL INTEGER sütunları için üst sınır: taşma 500 yerine 400 olur |
| [server/src/utils/validators.js:27](../../server/src/utils/validators.js#L27) | <code>export function parsePositiveId(value, { max = Number.MAX_SAFE_INTEGER } = {}) {</code> | Servis katmanındaki eşdeğer ayrıştırıcı |

**Olası nedenler**
- İstemci kimliği sayı yerine metin/boş/null gönderiyor (örn. id henüz yüklenmemiş)
- Kimlik int4 sınırını aşıyor (user_code/id taşma koruması)
- URL parametresi bozulmuş (boşluk, ondalık nokta)

**Adım adım kontrol**
- İstek URL'sinde ve gövdesinde kimlik alanının gerçek değerine bakın (günlükte [API] satırı)
- İstemcide kimliğin null/undefined olmadığını doğrulayın
- Hangi alanın reddedildiğini yanıt metninden bulun (kapı/site/daire/talep ayrı mesaj verir)

**İlgili testler:** [server/test/sites_ids.test.js](../../server/test/sites_ids.test.js), [server/test/validators.test.js](../../server/test/validators.test.js)

**Bkz.:** [sunucu-hata-500-errorid](#sunucu-hata-500-errorid), [sunucu-kapi-acma-404-yetki](#sunucu-kapi-acma-404-yetki)

<a id="sunucu-async-hata-istek-asili"></a>
### sunucu-async-hata-istek-asili · Bir istek yanıt vermeden asılı kalıyor ya da sunucu tek bir hatayla çöküyor (yakalanmamış async hata)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/utils/async_errors.js:15](../../server/src/utils/async_errors.js#L15) | <code>export function patchExpressLayer(Layer) {</code> | Async işleyicinin reddettiği promise next(err)'e bağlanır; hata global yakalayıcıya (500+errorId) düşer |
| [server/src/utils/async_errors.js:78](../../server/src/utils/async_errors.js#L78) | <code>export const asyncErrorsPatched = applyPatch();</code> | Yama import anında uygulanır; server.js'in en başında import edilmelidir |
| [server/src/utils/async_errors.js:73](../../server/src/utils/async_errors.js#L73) | <code>console.warn('[async_errors] Express Layer yamasi uygulanamadi:', error?.message);</code> | Yama uygulanamazsa yalnız uyarı yazılır: async hatalar o zaman yakalanmaz |
| [server/src/config/process_handlers.js:34](../../server/src/config/process_handlers.js#L34) | <code>proc.on('unhandledRejection', onUnhandledRejection);</code> | Yama dışında kalan reddedilmiş promise'lar süreç düzeyinde burada yakalanır |

**Olası nedenler**
- Express major sürümü değişti ya da layer.js yolu değişti: yama uygulanamaz (günlükte "[async_errors] Express Layer yamasi uygulanamadi")
- server.js içinde yama import'u en üstten kaldırıldı: yama sonradan yüklenen router'lara etki etmez
- Route dışında (zamanlayıcı, MQTT geri çağrısı) await edilmeyen promise hatası: süreç düzeyinde yakalanır

**Adım adım kontrol**
- Günlükte "[async_errors]" uyarısı var mı
- Hatalı isteğe karşılık "[ERROR] <errorId>" satırı var mı (yama çalışıyorsa vardır)
- Süreç çöktüyse altyapi-yakalanmamis-hata-loglari girişine bakın

**Günlükte aranacak ifadeler**
- `[async_errors] Express Layer yamasi uygulanamadi`

**İlgili testler:** [server/test/core_robustness.test.js](../../server/test/core_robustness.test.js)

**Bkz.:** [sunucu-hata-500-errorid](#sunucu-hata-500-errorid), [altyapi-yakalanmamis-hata-loglari](20-sunucu-altyapi-ve-yayin.md#altyapi-yakalanmamis-hata-loglari), [altyapi-kapanis-zorla-cikis](20-sunucu-altyapi-ve-yayin.md#altyapi-kapanis-zorla-cikis)

<a id="sunucu-firmware-manifest-ota"></a>
### sunucu-firmware-manifest-ota · Cihaz OTA güncellemesi almıyor: manifest "Bu hedef icin OTA yayini yok.", "Cihaz bu yayin grubunda degil.", 403 FIRMWARE_TARGET_MISMATCH ya da 503

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:111](../../server/src/routes/firmware_routes.js#L111) | <code>firmwareRouter.get('/firmware/:target/manifest.json', async (req, res) =&gt; {</code> | Manifest ucu: hedef doğrulama, kayıtlı cihaz denetimi, güncelleme kararı |
| [server/src/routes/firmware_routes.js:143](../../server/src/routes/firmware_routes.js#L143) | <code>code: 'FIRMWARE_TARGET_MISMATCH',</code> | Cihazın KENDİ bildirdiği donanım hedefi klasörle çelişirse 403 (yalnız DB hardware_type çelişirse kilitlenmez, uyarı yazılır) |
| [server/src/routes/firmware_routes.js:176](../../server/src/routes/firmware_routes.js#L176) | <code>const blockedByUid = allowedUids.length &gt; 0 &amp;&amp; !allowedUids.includes(uid);</code> | manifest.allowed_uids doluysa yalnız o UID'ler güncelleme alır |
| [server/src/routes/firmware_routes.js:193](../../server/src/routes/firmware_routes.js#L193) | <code>(!currentVersion &#124;&#124; compareVersionParts(version, currentVersion) &gt; 0);</code> | Yalnız manifest sürümü cihazınkinden YÜKSEKSE güncelleme sunulur |
| [server/src/routes/firmware_routes.js:127](../../server/src/routes/firmware_routes.js#L127) | <code>return res.status(503).json({ error: 'Cihaz dogrulamasi gecici olarak yapilamadi.' });</code> | UID kayıt sorgusu (DB) başarısızsa 503; cihaz bir sonraki aralıkta tekrar dener |
| [server/src/services/firmware_manifest_service.js:50](../../server/src/services/firmware_manifest_service.js#L50) | <code>export function checkDeviceFirmwareTarget({ folderTarget, hardwareType, reportedTarget = …</code> | Cihaz donanım hedefi ile klasör hedefi karşılaştırması |
| [server/src/services/firmware_manifest_service.js:29](../../server/src/services/firmware_manifest_service.js#L29) | <code>export function resolveManifestTarget(manifest, folderTarget) {</code> | Manifest içindeki target klasörle uyuşmuyorsa yayın durdurulur |

**Olası nedenler**
- Hedef klasörde manifest.json yok ya da enabled=false (OTA kapalı)
- Manifest sürümü cihaz sürümünden yüksek değil (güncelleme yok)
- Cihaz allowed_uids grubunda değil ya da usb_required=true (USB ile tam yükleme gerekir)
- Manifest hedefi klasörle uyuşmuyor ("[OTA] Manifest hedefi klasorle uyusmuyor")
- Cihaz donanım hedefi (c3/wroom) yanlış klasörü sorguluyor

**Adım adım kontrol**
- curl -s "https://api.gudeteknoloji.com.tr/firmware/<hedef>/manifest.json?current_version=<sürüm>&uid=<UID>" yanıtında enabled, update_available ve message alanlarına bakın
- Sunucuda firmware/<hedef>/manifest.json içeriği (sürüm, target, enabled, md5) doğru mu
- ESP32-C3 saha cihazlarının OTA davranışını ve yanıt şeklini değiştirmeyin: yanıt alanları sahadaki firmware ile uyumlu kalmalı

**Günlükte aranacak ifadeler**
- `[OTA] Manifest hedefi klasorle uyusmuyor`
- `[OTA] Kayitli hardware_type`

**Komutlar**
```bash
curl -s "https://api.gudeteknoloji.com.tr/firmware/esp32_c3/manifest.json?current_version=0.0.0"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a '\[OTA\]'"
```

**İlgili testler:** [server/test/devices_firmware_manifest.test.js](../../server/test/devices_firmware_manifest.test.js), [server/test/fix_sx1_company_ota.test.js](../../server/test/fix_sx1_company_ota.test.js)

**Bkz.:** [sunucu-firmware-bin-indirilemiyor](#sunucu-firmware-bin-indirilemiyor), [arac-ota-basligi-degisti](50-arac-test-ve-surec.md#arac-ota-basligi-degisti), [arac-surum-derleme](50-arac-test-ve-surec.md#arac-surum-derleme)

<a id="sunucu-firmware-bin-indirilemiyor"></a>
### sunucu-firmware-bin-indirilemiyor · Cihaz manifest'i alıyor ama .bin indirmesi başarısız: 400 "Gecersiz firmware dosyasi.", 404 "Firmware dosyasi bulunamadi." ya da cihazda MD5/başlık hatası

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:226](../../server/src/routes/firmware_routes.js#L226) | <code>firmwareRouter.get('/firmware/:target/:file', (req, res) =&gt; {</code> | Dosya sunumu: hedef/dosya adı doğrulaması, kök dizin dışına çıkış engeli |
| [server/src/routes/firmware_routes.js:254](../../server/src/routes/firmware_routes.js#L254) | <code>headers['x-MD5'] = md5;</code> | Manifest'teki dosya adı eşleşir ve md5 geçerliyse x-MD5 başlığı eklenir; cihaz bunu doğrular |
| [server/src/routes/firmware_routes.js:240](../../server/src/routes/firmware_routes.js#L240) | <code>return res.status(404).json({ error: 'Firmware dosyasi bulunamadi.' });</code> | Manifest'in gösterdiği dosya sunucuda yok (yükleme eksik) |
| [server/src/utils/helpers.js:28](../../server/src/utils/helpers.js#L28) | <code>export function safeFirmwareFile(value) {</code> | Dosya adı kısıtı: yalnız harf/rakam/_/./- içeren ve .bin ile biten ad kabul edilir |
| [server/src/utils/helpers.js:23](../../server/src/utils/helpers.js#L23) | <code>export function safeFirmwareTarget(value) {</code> | Hedef adı kısıtı |

**Olası nedenler**
- manifest.json'daki filename ile diskteki .bin adı uyuşmuyor ya da dosya yüklenmemiş (404)
- Hedef/dosya adı izinli desenin dışında (400)
- md5 değeri manifestte yok/yanlış: cihaz doğrulaması başarısız olur (x-MD5 yalnız geçerli 32 hex ile eklenir)
- Dosya sunucuya kopyalandıktan sonra yeniden derlenip md5 güncellenmedi

**Adım adım kontrol**
- curl -sI "https://api.gudeteknoloji.com.tr/firmware/<hedef>/<dosya>.bin" ile durum kodu ve x-MD5 başlığını görün
- Sunucuda manifest.json filename/md5 alanı ile dosyanın gerçek md5'ini karşılaştırın (md5sum)
- Yayını araçla yeniden üretin (arac-surum-derleme)

**Komutlar**
```bash
curl -sI "https://api.gudeteknoloji.com.tr/firmware/esp32_c3/firmware.bin"
```

**İlgili testler:** [server/test/devices_firmware_manifest.test.js](../../server/test/devices_firmware_manifest.test.js)

**Bkz.:** [sunucu-firmware-manifest-ota](#sunucu-firmware-manifest-ota), [arac-surum-derleme](50-arac-test-ve-surec.md#arac-surum-derleme), [arac-ota-basligi-degisti](50-arac-test-ve-surec.md#arac-ota-basligi-degisti)

<a id="sunucu-sirket-ucu-401-anahtar"></a>
### sunucu-sirket-ucu-401-anahtar · Şirket aracı ya da süper kullanıcı /api/company ve /qrcodes uçlarında 401 "Yetkisiz erisim." ya da 429 alıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/middlewares/company_auth.js:16](../../server/src/middlewares/company_auth.js#L16) | <code>export function hasValidCompanyKey(req, env = process.env) {</code> | X-Company-Key başlığı COMPANY_API_KEY ile sabit zamanlı karşılaştırılır; env boşsa anahtar yolu kapalı |
| [server/src/middlewares/company_auth.js:46](../../server/src/middlewares/company_auth.js#L46) | <code>return function requireCompanyAccess(req, res, next) {</code> | Önce anahtar, sonra Bearer + süper kullanıcı JWT; ikisi de yoksa 401 |
| [server/src/middlewares/company_auth.js:38](../../server/src/middlewares/company_auth.js#L38) | <code>audit('company_access_denied', {</code> | Her red denetim günlüğüne (company_access_denied) yazılır |
| [server/src/routes/company_routes.js:240](../../server/src/routes/company_routes.js#L240) | <code>companyRouter.use(['/qrcodes', '/api/company'], companyAccessLimiter, requireCompanyAcces…</code> | Önce hız sınırı (IP başına 15 dk'da 300), sonra yetki |
| [server/src/config/env.js:134](../../server/src/config/env.js#L134) | <code>warnings.push('COMPANY_API_KEY tanimli degil; /api/company/* yalnizca super_user JWT ile …</code> | Anahtar tanımlı değilse açılışta uyarı |

**Olası nedenler**
- Araçtaki anahtar sunucudaki COMPANY_API_KEY ile aynı değil ya da başlık hiç gönderilmiyor (araç tarafı: arac-anahtar-tanimli-degil / arac-http-anahtar-gonderilmiyor)
- COMPANY_API_KEY sunucuda tanımlı değil: yalnız süper kullanıcı JWT çalışır
- Bearer token süper kullanıcıya ait değil (403 yerine 401/403 zinciri authRequired/requireSuperUser'dan gelir)
- IP başına istek sınırı aşıldı (429)

**Adım adım kontrol**
- Günlükte JSON "company_access_denied" olayını arayın (ip, yol maskeli)
- Sunucuda COMPANY_API_KEY'in TANIMLI olup olmadığını (değerini değil) doğrulayın; env uyarılarına bakın
- Araç tarafı için arac-sunucu-401 girişi

**Günlükte aranacak ifadeler**
- `company_access_denied`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a company_access_denied"
```

**İlgili testler:** [server/test/core_company_auth.test.js](../../server/test/core_company_auth.test.js), [server/test/core_company_routes_http.test.js](../../server/test/core_company_routes_http.test.js)

**Bkz.:** [arac-sunucu-401](50-arac-test-ve-surec.md#arac-sunucu-401), [arac-anahtar-tanimli-degil](50-arac-test-ve-surec.md#arac-anahtar-tanimli-degil), [sunucu-sirket-cihaz-kayit-hata](#sunucu-sirket-cihaz-kayit-hata), [sunucu-429-genel-hiz-siniri](#sunucu-429-genel-hiz-siniri)

<a id="sunucu-sirket-cihaz-kayit-hata"></a>
### sunucu-sirket-cihaz-kayit-hata · Şirket aracı cihaz/karekod kaydedemiyor ya da silemiyor: 400 device_uid/PNG hatası, 500 "Cihaz veritabanina kaydedilemedi" (errorId)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/company_routes.js:279](../../server/src/routes/company_routes.js#L279) | <code>companyRouter.post('/api/company/labeled-devices', async (req, res) =&gt; {</code> | Kayıt: UID normalize, PNG doğrulama, ÖNCE DB sonra dosyalar (idempotent) |
| [server/src/routes/company_routes.js:45](../../server/src/routes/company_routes.js#L45) | <code>export function normalizeCompanyUid(raw) {</code> | UID 12 haneli büyük hex olmalı; ":" ve "-" ayırıcıları atılır |
| [server/src/routes/company_routes.js:76](../../server/src/routes/company_routes.js#L76) | <code>export function decodePngBase64(raw) {</code> | qr_image_base64: base64/data URL, PNG imzası, en çok 2 MB |
| [server/src/routes/company_routes.js:129](../../server/src/routes/company_routes.js#L129) | <code>export async function syncCompanyDeviceRecord(db, { deviceUid, hardwareType }) {</code> | devices tablosuna ekler; hata yutulmaz (araç "kaydedildi" deyip satırsız etiket bastırmasın) |
| [server/src/routes/company_routes.js:107](../../server/src/routes/company_routes.js#L107) | <code>export function resolveCompanyHardwareType(body) {</code> | c3 -> esp32_c3; wroom/wrover/d0wd -> esp32_wroom; belirsizse null (tahmin yok) |
| [server/src/routes/company_routes.js:373](../../server/src/routes/company_routes.js#L373) | <code>companyRouter.delete('/api/company/labeled-devices/:deviceUid', async (req, res) =&gt; {</code> | Silme: DB (cihaz + kapı ataması tek işlem), sonra PNG ve JSON, sonra MQTT ACL senkronu |
| [server/src/routes/company_routes.js:201](../../server/src/routes/company_routes.js#L201) | <code>export async function syncAclAfterCompanyDelete(syncFn = syncMqttAclOrThrow) {</code> | Silme sonrası ACL senkron hatası silmeyi geri almaz; yanıttaki mqtt_sync özetine bakın |

**Olası nedenler**
- device_uid boş ya da 12 haneli hex değil (400)
- PNG geçersiz/2 MB üstü (400)
- Veritabanı yazma hatası: yanıt ok:false, db_synced:false + errorId (500); tekrar denemek güvenlidir
- Silmede cihaz başka bir kapıya atanmışsa atama önce kaldırılır; MQTT ACL senkronu başarısızsa mqtt_sync.ok=false
- Donanım tipi belirlenemezse DB varsayılanı (esp32_c3) kalır; cihazın kendi MQTT bildirimi düzeltir

**Adım adım kontrol**
- Yanıttaki errorId ile günlükte "[company] <errorId> cihaz DB kaydi basarisiz" satırını bulun
- SELECT device_uid, hardware_type, owner_user_id FROM devices WHERE device_uid = '<UID>'
- Araç tarafı için arac-kayit-http-400-donanim ve arac-qr-etiket girişleri

**Günlükte aranacak ifadeler**
- `[company] `
- `cihaz DB kaydi basarisiz`
- `cihaz DB silme hatasi`

**İlgili testler:** [server/test/core_company_routes_http.test.js](../../server/test/core_company_routes_http.test.js), [server/test/fix_sx1_company_ota.test.js](../../server/test/fix_sx1_company_ota.test.js)

**Bkz.:** [arac-kayit-http-400-donanim](50-arac-test-ve-surec.md#arac-kayit-http-400-donanim), [arac-qr-etiket](50-arac-test-ve-surec.md#arac-qr-etiket), [sunucu-sirket-ucu-401-anahtar](#sunucu-sirket-ucu-401-anahtar), [altyapi-acl-senkron-503](20-sunucu-altyapi-ve-yayin.md#altyapi-acl-senkron-503)

<a id="sunucu-misafir-gecis-olusturma-hata"></a>
### sunucu-misafir-gecis-olusturma-hata · Misafir/kurye geçiş linki oluşturulamıyor: "Bu sitede misafir/kurye gecis kodu olusturma kapalidir." (403 GUEST_DISABLED), "Kapi bulunamadi veya yetkiniz yok.", 400 geçersiz süre/tür

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/guest_passes_routes.js:47](../../server/src/routes/guest_passes_routes.js#L47) | <code>guestPassesRouter.post('/app/guest-passes', authRequired, async (req, res) =&gt; {</code> | Oluşturma ucu: girdi doğrulama, kapıya erişim, politika, 48 hex karakterlik rastgele token |
| [server/src/utils/guest_pass_utils.js:38](../../server/src/utils/guest_pass_utils.js#L38) | <code>export function normalizeGuestPassInput(body) {</code> | Kapı, başlık, tür, süre (en az/en çok kıstırılır) ve kullanım limiti doğrulaması |
| [server/src/routes/guest_passes_routes.js:68](../../server/src/routes/guest_passes_routes.js#L68) | <code>code: 'GUEST_DISABLED',</code> | Sitede misafir özelliği kapalıysa kimse (süper kullanıcı dahil) geçiş üretemez |
| [server/src/routes/guest_passes_routes.js:105](../../server/src/routes/guest_passes_routes.js#L105) | <code>const webUrl = `${publicBaseUrl()}/guest/${token}`;</code> | Link tabanı PUBLIC_APP_URL > PUBLIC_BASE_URL > api.gudeteknoloji.com.tr |
| [server/src/routes/guest_passes_routes.js:137](../../server/src/routes/guest_passes_routes.js#L137) | <code>guestPassesRouter.get('/app/guest-passes', authRequired, async (req, res) =&gt; {</code> | Liste: yalnızca aktif, süresi dolmamış, hakkı kalmış son 50 geçiş |
| [server/src/routes/guest_passes_routes.js:181](../../server/src/routes/guest_passes_routes.js#L181) | <code>guestPassesRouter.delete('/app/guest-passes/:id', authRequired, async (req, res) =&gt; {</code> | İptal: yalnız oluşturan kullanıcı (is_active=FALSE) |

**Olası nedenler**
- Sitenin politikasında misafir geçişi kapalı (feature_guest_pass_enabled=false)
- Kapı kullanıcının erişebildiği kapılar arasında değil (404)
- Süre/tür/limit alanı geçersiz (400)
- Link yanlış alan adıyla üretiliyor: PUBLIC_APP_URL/PUBLIC_BASE_URL .env değerleri kontrol edilmeli
- Listede görünmeyen geçiş: süresi dolmuş, iptal edilmiş ya da hakları tükenmiştir (liste bunları eler)

**Adım adım kontrol**
- SELECT feature_guest_pass_enabled FROM sites WHERE site_code = <site>
- Kullanıcı kapıya erişebiliyor mu: kapı listesi ucu (sunucu-sakin-kapi-listede-yok)
- Günlükte JSON "guest_pass_created" olayı oluşturmanın başarılı olduğunu gösterir

**Günlükte aranacak ifadeler**
- `guest_pass_created`
- `[guest_passes] `

**İlgili testler:** [server/test/sites_guest_pass.test.js](../../server/test/sites_guest_pass.test.js)

**Bkz.:** [sunucu-misafir-gecis-acma-hata](#sunucu-misafir-gecis-acma-hata), [sunucu-misafir-sayfa-acilmiyor](#sunucu-misafir-sayfa-acilmiyor), [sunucu-guvenlik-politikasi-hata](#sunucu-guvenlik-politikasi-hata), [ui-misafir-gecis-dugmesi](31-uygulama-arayuz.md#ui-misafir-gecis-dugmesi)

<a id="sunucu-misafir-gecis-acma-hata"></a>
### sunucu-misafir-gecis-acma-hata · Misafir linkiyle kapı açılmıyor: 410 "iptal edilmis/suresi dolmus/daha once kullanilmis", 403 "olusturan kullanicinin yetkisi kalmamis", 409 "cihaz atanmamis", 503 "cihazi su anda bagli degil"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/guest_passes_routes.js:209](../../server/src/routes/guest_passes_routes.js#L209) | <code>guestPassesRouter.post('/public/guest-pass/:token/open', doorCommandRateLimiter, async (r…</code> | Herkese açık açma ucu; kapı komutu hız sınırı (10 sn'de 4) |
| [server/src/utils/guest_pass_utils.js:121](../../server/src/utils/guest_pass_utils.js#L121) | <code>export const GUEST_PASS_STATE_RESPONSES = Object.freeze({</code> | İptal/süre/hak durumları -> 410 ve Türkçe metinler |
| [server/src/routes/guest_passes_routes.js:302](../../server/src/routes/guest_passes_routes.js#L302) | <code>code: 'GUEST_PASS_OWNER_INACTIVE',</code> | Linki üreten kullanıcı pasif/doğrulanmamış/reddedilmişse link çalışmaz |
| [server/src/routes/guest_passes_routes.js:315](../../server/src/routes/guest_passes_routes.js#L315) | <code>code: 'GUEST_PASS_OWNER_NO_ACCESS',</code> | Üretenin kapıya yetkisi sonradan kalktıysa link çalışmaz |
| [server/src/routes/guest_passes_routes.js:321](../../server/src/routes/guest_passes_routes.js#L321) | <code>assertDoorOpenAllowed({</code> | Kapı politikası (kanal: guest): misafir kapalı, kapı pasif vb. 403 |
| [server/src/routes/guest_passes_routes.js:359](../../server/src/routes/guest_passes_routes.js#L359) | <code>const claim = await pool.query(CLAIM_GUEST_PASS_SQL, [Number(pass.id)]);</code> | Hak ATOMİK tüketilir; kapı komutu başarısızsa hak iade edilir |
| [server/src/routes/guest_passes_routes.js:387](../../server/src/routes/guest_passes_routes.js#L387) | <code>console.error('[guest_passes] hak iadesi basarisiz', { pass_id: Number(pass.id), message:…</code> | İade de başarısız olursa kullanıcı hakkını kaybedebilir (günlükte aranır) |
| [server/src/routes/guest_passes_routes.js:445](../../server/src/routes/guest_passes_routes.js#L445) | <code>if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED' &#124;&#124; error?.code === 'DEVICE_OFFLINE') {</code> | Köprü bağlı değil ya da cihaz çevrimdışı: 503 |

**Olası nedenler**
- Link iptal edildi, süresi doldu ya da kullanım hakkı bitti (410)
- Linki oluşturan kullanıcı pasifleşti ya da kapı yetkisini kaybetti (403; link kimliği yok, yetki ÜRETEN kullanıcıya bağlıdır)
- Sitede misafir geçişi sonradan kapatıldı (403 GUEST_DISABLED)
- Kapıya cihaz atanmamış (409) ya da cihaz çevrimdışı/MQTT köprüsü bağlı değil (503)
- Aynı linke eşzamanlı iki istek: ikincisi 409 "baska bir istekle kullaniliyor" alabilir
- Çok sık deneme (429)

**Adım adım kontrol**
- SELECT is_active, expires_at, used_count, max_uses FROM guest_passes WHERE id = <geçiş> (token değeri yazdırılmaz)
- Üreten kullanıcının durumu: SELECT is_active, email_verified FROM users WHERE user_code = <kod>
- Cihaz durumu için kapı açma çevrimdışı girişi: sunucu-kapi-acma-cihaz-offline
- Günlükte "guest_pass_opened" JSON olayı başarılı açılışı gösterir

**Günlükte aranacak ifadeler**
- `guest_pass_opened`
- `[guest_passes] hak iadesi basarisiz`
- `[guest_passes] acilis kaydi yazilamadi`

**İlgili testler:** [server/test/sites_guest_pass.test.js](../../server/test/sites_guest_pass.test.js), [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js)

**Bkz.:** [sunucu-misafir-gecis-olusturma-hata](#sunucu-misafir-gecis-olusturma-hata), [sunucu-kapi-acma-cihaz-offline](#sunucu-kapi-acma-cihaz-offline), [sunucu-kapi-acma-409-cihaz-atanmamis](#sunucu-kapi-acma-409-cihaz-atanmamis), [sunucu-misafir-sayfa-acilmiyor](#sunucu-misafir-sayfa-acilmiyor)

<a id="sunucu-misafir-sayfa-acilmiyor"></a>
### sunucu-misafir-sayfa-acilmiyor · Misafir linki tarayıcıda açılınca "geçersiz" sayfası ya da "Sunucu hatasi olustu. Referans: ..." görünüyor; sayfa düğmesi çalışmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/guest_passes_routes.js:453](../../server/src/routes/guest_passes_routes.js#L453) | <code>guestPassesRouter.get('/guest/:token', async (req, res) =&gt; {</code> | Mobil web sayfası: token biçimi kötüyse ya da kayıt yoksa 404 geçersiz sayfa |
| [server/src/utils/guest_pass_utils.js:19](../../server/src/utils/guest_pass_utils.js#L19) | <code>export function isWellFormedGuestToken(token) {</code> | Token biçim denetimi (16-128 karakter, harf/rakam/_/-); bozuk link doğrudan 404 olur |
| [server/src/utils/guest_pass_utils.js:135](../../server/src/utils/guest_pass_utils.js#L135) | <code>export function buildGuestPageCsp(nonce) {</code> | Sayfa CSP'si: yalnız nonce'lu script/style, connect-src self; satır içi/harici betik çalışmaz |
| [server/src/utils/guest_pass_utils.js:259](../../server/src/utils/guest_pass_utils.js#L259) | <code>export function renderGuestPassPage({ pass, nonce, now = new Date() }) {</code> | Sayfa HTML'i ve "aç" düğmesinin /public/guest-pass/:token/open çağrısı |
| [server/src/routes/guest_passes_routes.js:490](../../server/src/routes/guest_passes_routes.js#L490) | <code>console.error(`[guest_passes] page (errorId=${errorId})`, error);</code> | 500 durumunda sayfada yalnız Referans kodu görünür; ayrıntı günlüktedir |
| [server/src/routes/public_guest_routes.js:1](../../server/src/routes/public_guest_routes.js#L1) | <code>export { guestPassesRouter as publicGuestRouter } from './guest_passes_routes.js';</code> | Yalnız yeniden dışa aktarım; mantık guest_passes_routes.js içindedir |

**Olası nedenler**
- Link kopyalanırken kırpıldı ya da yanlış yapıştırıldı (token biçimi bozuk)
- Geçiş silinmiş (kayıt yok) -> geçersiz sayfa
- Veritabanı hatası: sayfada Referans kodu (errorId)
- Link yanlış alan adıyla üretilmiş (PUBLIC_APP_URL/PUBLIC_BASE_URL) ve nginx o yolu yönlendirmiyor
- Sayfa içine betik/stil ekleyen bir değişiklik CSP nedeniyle çalışmaz (nonce zorunlu)

**Adım adım kontrol**
- curl -s -o /dev/null -w "%{http_code}" https://api.gudeteknoloji.com.tr/guest/<token>
- Sayfada Referans kodu varsa günlükte "[guest_passes] page" satırını errorId ile arayın
- Sayfa açılıyor ama kapı açılmıyorsa sunucu-misafir-gecis-acma-hata

**Günlükte aranacak ifadeler**
- `[guest_passes] page (errorId=`

**İlgili testler:** [server/test/sites_guest_pass.test.js](../../server/test/sites_guest_pass.test.js)

**Bkz.:** [sunucu-misafir-gecis-acma-hata](#sunucu-misafir-gecis-acma-hata), [sunucu-misafir-gecis-olusturma-hata](#sunucu-misafir-gecis-olusturma-hata), [sunucu-istek-gunlugu-ve-basliklar](#sunucu-istek-gunlugu-ve-basliklar)

<a id="sunucu-admin-ota-tetikleme-hata"></a>
### sunucu-admin-ota-tetikleme-hata · Süper kullanıcı panelinden "OTA güncelleme denetimi" gönderilemiyor: 503 "MQTT baglantisi hazir degil.", 500 "OTA komutu gonderilemedi." ya da failed listesi dolu

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:1295](../../server/src/routes/admin_routes.js#L1295) | <code>adminRouter.post('/admin/devices/ota-check', authRequired, requireSuperUser, async (req, …</code> | Tüm kayıtlı cihazlara OTA denetim komutu yayınlar; iş kaydı (ota_update_jobs) açar/kapatır; 202 döner |
| [server/src/routes/admin_routes.js:1330](../../server/src/routes/admin_routes.js#L1330) | <code>return res.status(503).json({ error: 'MQTT baglantisi hazir degil.' });</code> | MQTT köprüsü bağlı değilse komut yayınlanamaz |
| [server/src/services/device_service.js:427](../../server/src/services/device_service.js#L427) | <code>export async function createOtaUpdateJob({ authUser, deviceUids }) {</code> | İş satırı oluşturma (requested_by_user_code) |
| [server/src/services/device_service.js:465](../../server/src/services/device_service.js#L465) | <code>export async function finishOtaUpdateJob({ jobId, result }) {</code> | Gönderilen/başarısız sayılarını işe yazar |
| [server/src/services/device_service.js:416](../../server/src/services/device_service.js#L416) | <code>export async function listAllDeviceUids() {</code> | Komutun hedefi: devices tablosundaki tüm UID'ler |

**Olası nedenler**
- MQTT köprüsü sunucuda bağlı değil (broker kapalı ya da kimlik hatası): 503
- Veritabanı hatası (iş kaydı yazılamadı): 500
- Yayın bazı cihazlar için başarısız: yanıttaki failed listesi hangi UID'lerin atlandığını gösterir
- Cihaz çevrimdışıysa komutu almaz; cihaz kendi aralığında manifest'i zaten sorgular (bkz. sunucu-firmware-manifest-ota)

**Adım adım kontrol**
- curl -s https://api.gudeteknoloji.com.tr/health yanıtında mqtt alanı
- Günlükte JSON "ota_check_broadcast" olayı: requested/sent/failed_count
- SELECT id, requested_count, sent_count FROM ota_update_jobs ORDER BY id DESC LIMIT 5

**Günlükte aranacak ifadeler**
- `ota_check_broadcast`

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
```

**İlgili testler:** [server/test/ops_ota_check_retry.test.js](../../server/test/ops_ota_check_retry.test.js), [server/test/devices_admin_routes.test.js](../../server/test/devices_admin_routes.test.js)

**Bkz.:** [sunucu-firmware-manifest-ota](#sunucu-firmware-manifest-ota), [altyapi-health-mqtt-baglanti-yok](20-sunucu-altyapi-ve-yayin.md#altyapi-health-mqtt-baglanti-yok), [altyapi-komut-yayini-roleyi-calistirmiyor](20-sunucu-altyapi-ve-yayin.md#altyapi-komut-yayini-roleyi-calistirmiyor)

<a id="sunucu-admin-cihaz-envanteri-hata"></a>
### sunucu-admin-cihaz-envanteri-hata · Süper kullanıcı panelinde cihaz ekleme/düzenleme/silme hata veriyor: 409 "Bu cihazin unique id kayitli.", 404 "Kullanici/Site ID bulunamadi.", 503 "... MQTT broker senkronu basarisiz."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:1435](../../server/src/routes/admin_routes.js#L1435) | <code>adminRouter.post('/admin/devices', authRequired, requireSuperUser, async (req, res) =&gt; {</code> | Envantere cihaz ekler (201) ve ACL senkronu yapar |
| [server/src/routes/admin_routes.js:1337](../../server/src/routes/admin_routes.js#L1337) | <code>adminRouter.patch('/admin/devices/:id', authRequired, requireSuperUser, async (req, res) …</code> | Kısmi güncelleme: yalnız gönderilen atama alanları değişir; hardware_type yalnız esp32_c3/esp32_wroom |
| [server/src/routes/admin_routes.js:1410](../../server/src/routes/admin_routes.js#L1410) | <code>adminRouter.delete('/admin/devices/:id', authRequired, requireSuperUser, async (req, res)…</code> | Silme: cihaz silinir, sonra ACL senkronu; senkron hatası 503 ama cihaz SİLİNMİŞTİR |
| [server/src/routes/admin_routes.js:1484](../../server/src/routes/admin_routes.js#L1484) | <code>error: 'Cihaz kaydedildi ama MQTT broker senkronu basarisiz.',</code> | Kayıt başarılı, broker yetkisi güncellenemedi: 503 (kayıt geri alınmaz) |
| [server/src/utils/validators.js:394](../../server/src/utils/validators.js#L394) | <code>export function handleDeviceMutationError(error, res, genericErrorMessage) {</code> | 23505 devices_device_uid_key -> 409 "Bu cihazin unique id kayitli." |
| [server/src/services/device_service.js:885](../../server/src/services/device_service.js#L885) | <code>export async function registerCompanyDevice({ deviceUid, hardwareType = 'esp32_wroom', in…</code> | Envanter kaydı; mevcut UID için durum/tip kuralları |
| [server/src/services/device_service.js:730](../../server/src/services/device_service.js#L730) | <code>export async function deleteDeviceById(deviceId) {</code> | Cihaz silme (bağlı kapı ataması vb. temizliği) |

**Olası nedenler**
- Aynı UID zaten kayıtlı (409)
- Atanacak kullanıcı/site yok (404) ya da id int4 sınırını aşıyor/sayısal değil (400)
- Donanım tipi esp32_c3/esp32_wroom dışında (400)
- Kayıt/silme başarılı ama MQTT ACL senkron betiği başarısız: 503; broker tarafı elle senkronlanmalı (altyapi-acl-senkron-503)

**Adım adım kontrol**
- SELECT id, device_uid, hardware_type, owner_user_id, site_code FROM devices WHERE device_uid = '<UID>'
- 503 aldıysanız işlem veritabanında YAPILMIŞTIR: tekrar denemeden önce cihazın durumunu doğrulayın
- Senkron hatası için ACL girişleri: altyapi-acl-senkron-503, altyapi-kapi-mqtt-sync-betik-hatalari

**İlgili testler:** [server/test/devices_admin_routes.test.js](../../server/test/devices_admin_routes.test.js), [server/test/fix_sx2_device_delete.test.js](../../server/test/fix_sx2_device_delete.test.js), [server/test/devices_device_service.test.js](../../server/test/devices_device_service.test.js)

**Bkz.:** [altyapi-acl-senkron-503](20-sunucu-altyapi-ve-yayin.md#altyapi-acl-senkron-503), [sunucu-sirket-cihaz-kayit-hata](#sunucu-sirket-cihaz-kayit-hata), [sunucu-admin-cihaz-ariza-sahiplik](#sunucu-admin-cihaz-ariza-sahiplik)

<a id="sunucu-admin-cihaz-ariza-sahiplik"></a>
### sunucu-admin-cihaz-ariza-sahiplik · Cihaz sahiplenilemiyor/atanamıyor çünkü "arızalı" ya da sahipli görünüyor; süper kullanıcı arıza durumunu kaldıramıyor ya da sahipliği sıfırlayamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:1496](../../server/src/routes/admin_routes.js#L1496) | <code>adminRouter.patch('/admin/devices/:id/defect', authRequired, requireSuperUser, async (req…</code> | is_defective true/false zorunlu; neden en çok 300 karakter |
| [server/src/routes/admin_routes.js:1529](../../server/src/routes/admin_routes.js#L1529) | <code>adminRouter.post('/admin/devices/:id/release-ownership', authRequired, requireSuperUser, …</code> | Sahiplik sıfırlama ucu |
| [server/src/services/device_service.js:945](../../server/src/services/device_service.js#L945) | <code>export async function setDeviceDefectStatus({ deviceId, isDefective, defectiveReason, aut…</code> | Arıza bayrağı ve gerekçesi yazılır; yoksa 404 |
| [server/src/services/device_service.js:991](../../server/src/services/device_service.js#L991) | <code>export async function releaseDeviceOwnership({ deviceId, authUser }) {</code> | Tek işlemde kapıdan sök + owner/assigned/site/gate/claimed_at sıfırla; sonra yerel token döndür |
| [server/src/services/device_service.js:1053](../../server/src/services/device_service.js#L1053) | <code>console.warn('Local control token rotasyonu atlandi:', tokenErr.message);</code> | Token döndürme başarısızlığı yalnız uyarıdır; sıfırlama geri alınmaz |

**Olası nedenler**
- Cihaz arızalı işaretli: sahiplenme (400) ve kapıya atama (409/atanamaz) reddedilir
- Cihaz başka hesapta sahipli: önce "sahipliği sıfırla" gerekir (süper kullanıcı)
- Sıfırlama sonrası eski sahibin cihazı kapıdan sökülür: kapı atamasını tekrar yapmak gerekir
- is_defective alanı true/false gönderilmedi (400)

**Adım adım kontrol**
- SELECT device_uid, is_defective, defective_reason, owner_user_id, site_code FROM devices WHERE id = <id>
- Günlükte JSON "device_ownership_released" olayı sıfırlamanın yapıldığını gösterir
- Sıfırlamadan sonra cihazın yerel kontrol token'ı döndürülür; eski sahibin uygulaması yerel açmayı yeniler

**Günlükte aranacak ifadeler**
- `device_ownership_released`

**İlgili testler:** [server/test/fix_sx1_device_hardware.test.js](../../server/test/fix_sx1_device_hardware.test.js), [server/test/devices_device_service.test.js](../../server/test/devices_device_service.test.js)

**Bkz.:** [sunucu-cihaz-sahiplenme-hata](#sunucu-cihaz-sahiplenme-hata), [sunucu-kapi-cihaz-atama-403](#sunucu-kapi-cihaz-atama-403), [sunucu-yerel-token-rotasyonu](#sunucu-yerel-token-rotasyonu)

