// Alan 60 — UÇTAN UCA AKIŞ HARİTALARI (uygulama -> sunucu -> veritabanı -> MQTT -> cihaz).
// Her giriş bir özelliğin zincirini SIRAYLA verir; ref note'ları "Adım N — katman: ne olur" ile başlar.
// Satır numarası yazılmaz: araç `find` parçasını koddan çözer (bkz. tools/klavuz/README.md).
export default {
  title: 'Uçtan uca akış haritaları (uygulama -> sunucu -> veritabanı -> MQTT -> cihaz)',
  intro:
    'Bu bölüm bir özellik bozulduğunda zinciri BAŞTAN SONA izlemek içindir. Her giriş bir akıştır; tablodaki satırlar ' +
    'Adım 1, 2, 3... sırasındadır ve her satırın notu "Adım N — katman: ne olur" ile başlar. Katmanlar: uygulama (Flutter: ' +
    'lib/ui -> lib/services), sunucu (Express: routes -> services -> db.js), MQTT (server/src/mqtt_bridge.js <-> Mosquitto), ' +
    'cihaz (ESP32: cihaz_kontrol/include|src). Nasıl okunur: (1) belirtiyi anlatan akışı seçin ("... akışı bozuldu"); ' +
    '(2) adımları sırayla açın ve "Adım N"de beklenen şeyin gerçekten olduğunu doğrulayın (günlük, SQL, seri port); ' +
    '(3) ilk gerçekleşmeyen adım arıza halkasıdır; "Olası nedenler" o halka için ipuçlarını, "Adım adım kontrol" bakış sırasını verir. ' +
    'Sunucu günlükleri her istek için "[API] YÖNTEM yol -> durum (süre)" satırı yazar (token/kod değerleri maskelenir); ' +
    'tek bir kapı komutunun cihaza ulaşıp ulaşmadığı yalnızca cihaz seri günlüğünden ve MQTT olaylarından (pulse_started, ' +
    'pulse_rejected) anlaşılır. Akışlar kodda gerçekten bulunan halkaları gösterir; olmayan halka eklenmemiştir. ' +
    'Ayrıntılı tek-belirti girişleri için ilgili diğer alan bölümlerine bakın.',
  files: [
    { file: 'lib/services/auth_api.dart', note: 'Uygulamanın TÜM HTTP çağrıları (yol + durum kodu eşlemesi + zaman aşımı)' },
    { file: 'lib/services/auth_service.dart', note: 'Oturum, kapı açma kararı (yerel -> bulut), önbellekler, hata -> oturum sonu eşlemesi' },
    { file: 'lib/services/local_door_service.dart', note: 'Yerel UDP: beacon dinleme, challenge, HMAC imzası, doğrudan UDP açma' },
    { file: 'server/src/routes/auth_routes.js', note: 'Giriş / kayıt / doğrulama / şifre sıfırlama uçları' },
    { file: 'server/src/routes/app_doors_routes.js', note: 'Kapı listesi, durum, bulut açma, karekod ile açma, yerel açma bildirimi, QR token' },
    { file: 'server/src/services/door_service.js', note: 'Erişilebilir kapılar SQL\'i, kapı geçiş günlüğü, yerel kontrol anahtarı dağıtımı' },
    { file: 'server/src/services/door_access_policy.js', note: 'Kanal politikası (remote/qr/guest/local) ve ekran karekod tokenı kuralları' },
    { file: 'server/src/services/geofence_service.js', note: 'Konum (geofence) doğrulaması' },
    { file: 'server/src/services/qr_access_service.js', note: 'Dinamik QR token üretimi ve cihazdan gelen QR doğrulaması' },
    { file: 'server/src/services/membership_service.js', note: 'Kayıt/doğrulama, cihaz sahiplenme, site kurulumu, katılım başvurusu' },
    { file: 'server/src/mqtt_bridge.js', note: 'Mosquitto köprüsü: abonelikler, durum/olay/günlük işleme, cmd/qr_result yayınları' },
    { file: 'server/src/mqtt_acl_sync.js', note: 'Mosquitto ACL metni (cihaz başına konu izinleri) ve senkron komutu' },
    { file: 'cihaz_kontrol/include/mqtt_baglanti.h', note: 'Cihaz MQTT: bağlantı, abonelik, cmd/qr_result işleyicileri, durum/olay yayını' },
    { file: 'cihaz_kontrol/include/role_kontrol.h', note: 'Röle tetikleme (debounce, esp_timer ile bırakma)' },
    { file: 'cihaz_kontrol/include/yerel_kapi_kontrol.h', note: 'Cihaz yerel UDP/HTTP: beacon, challenge, imzalı açma' },
    { file: 'cihaz_kontrol/include/wifi_baglanti.h', note: 'Wi-Fi, BLE kurulum servisi, NVS kimlik bilgileri' },
    { file: 'cihaz_kontrol/include/ota_guncelleme.h', note: 'Cihaz OTA: manifest, indirme, doğrulama, geri dönüş' },
    { file: 'cihaz_kontrol/include/offline_log.h', note: 'Cihazın çevrimdışı kapı geçiş kayıtları ve MQTT ile senkronu' },
    { file: 'server/src/routes/public_guest_routes.js', note: 'guest_passes_routes.js yönlendiricisinin yeniden dışa aktarımı (misafir akışı: akis-misafir-gecis)' },
    { file: 'docs/EPOSTA_DOGRULAMA.md', note: 'Bekleyen kayıt modeli, parametreler, "kod gelmiyor" teşhisi' },
    { file: 'docs/YEREL_KONTROL_V2.md', note: 'Yerel kontrol protokolü v2 (challenge + HMAC) sözleşmesi' },
    { file: 'deploy/README.md', note: 'Canlı dağıtım, PM2 ve geri alma adımları' },
  ],
  entries: [
    // ------------------------------------------------------------------------------------------------
    // 1) Giriş / oturum / JWT
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-giris-oturum-jwt',
      symptom: 'Giriş akışı bozuldu (uçtan uca): uygulamada giriş yapılamıyor ya da oturum beklenmedik biçimde kapanıyor',
      keywords: ['giriş', 'login', 'oturum', 'jwt', 'token', '401', '403', '429', 'LOGIN_LOCKED', 'TOKEN_REVOKED', 'authRequired', 'secure storage'],
      refs: [
        {
          file: 'lib/ui/pages/login_page.dart',
          find: 'await widget.authService.login(',
          note: 'Adım 1 — uygulama (ekran): Giriş düğmesi e-posta/kullanıcı adı + parolayı AuthService.login çağrısına verir; dönen hata metni AppSnack ile gösterilir (kilit, doğrulanmadı, onay bekliyor mesajları buradan okunur).',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '_session = await api.login(',
          note: 'Adım 2 — uygulama (servis): önceki girişte verilen güvenilir cihaz belirteci (varsa) gönderilir, yanıtta yenisi gelirse saklanır; ApiException mesajı kullanıcıya döner; ağ hatasında "Sunucuya baglanilamadi."; başarıda oturum _session\'a yazılır ve kalıcılaştırılır.',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "path: '/auth/login',",
          note: 'Adım 3 — uygulama (HTTP): POST {baseUrl}/auth/login (baseUrl lib/config/app_config.dart içinde; varsayılan https://api.gudeteknoloji.com.tr, --dart-define=API_BASE_URL ile değişir). 200 beklenir; 401/403 bu uçta oturum sonu sayılmaz, sunucu mesajı gösterilir.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: "authRouter.post('/auth/login', loginRateLimiter",
          note: 'Adım 4 — sunucu (rota): önce IP + IP/kimlik bazlı hız sınırı (429 "Cok fazla giris denemesi"), sonra gövde doğrulaması (email/login/identifier + password zorunlu, 400).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'const reservation = loginGuard.reserve(attempt);',
          note: 'Adım 5 — sunucu (giriş kilidi, security/login_guard.js): üç katman (hesap × kaynak 5 hata / 15 dk, hesap geneli 20 / 60 dk, IP geneli 30 / 15 dk; ilk kilit 15 dk, tekrarında uzar); hata hakkı bcrypt\'ten ÖNCE ayrılır; kilitliyse 429 + code LOGIN_LOCKED + Retry-After. Hesapla eşleşen güvenilir cihaz belirteci hesap ve IP geneli kilitten muaftır. Sayaç süreç belleğindedir; PM2 yeniden başlatması sıfırlar.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'WHERE LOWER(email) = LOWER($1) OR LOWER(login_name) = LOWER($1)',
          note: 'Adım 6 — veritabanı: users satırı e-posta VEYA login_name ile aranır. Satır yoksa bekleyen kayıt (pending_registrations) parolası da denenir; doğruysa 403 "E-posta adresiniz dogrulanmadi." döner.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'const compared = await bcrypt.compare(candidate, usableHash ? storedHash : await getDummyPasswordHash());',
          note: 'Adım 7 — sunucu (parola): kullanıcı bulunmasa ya da saklı özet kullanılamaz olsa da tek bcrypt karşılaştırması yapılır (zaman ölçümüyle hesap taraması engellenir). Uyuşmazsa commitFailure + 401 "Giris bilgileri hatali." (eşik dolduysa 429 LOGIN_LOCKED).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'if (!row.email_verified) {',
          note: 'Adım 8 — sunucu (durum kapıları): sırayla seçilen rol uyuşmazlığı (403), e-posta doğrulanmadı (403), abonelik onay bekliyor/reddedildi (403), hesap aktif değil (403). Parola doğru olsa bile token bu kapılardan geçmeden verilmez.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'const token = signAccessToken(user, { passwordHash: row.password_hash });',
          note: 'Adım 9 — sunucu (JWT): jwt.js signAccessToken HS256 ile sub/email/role + pv (parola sürümü) imzalar; ömür JWT_EXPIRES_IN (varsayılan 30d). JWT_SECRET yoksa/kısaysa token üretimi hata verir (500). Yanıta güvenilir cihaz belirteci (device_token) de eklenir.',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'final raw = jsonEncode(_session!.toJson());',
          note: 'Adım 10 — uygulama (güvenli depo): oturum flutter_secure_storage içinde "auth_session" anahtarına yazılır; yazma hatası sessizce yutulur (oturum yalnızca bellekte kalır, uygulama yeniden açılınca giriş istenir).',
        },
        {
          file: 'server/src/middlewares/auth_middleware.js',
          find: 'claims = verifyAccessToken(token);',
          note: 'Adım 11 — sunucu (sonraki her istek): authRequired Bearer token\'ı doğrular (imza/süre -> 401 "Gecersiz veya suresi dolmus token."), sonra rol/aktiflik/onay DB\'den TAZE okunur; token\'daki rol kullanılmaz.',
        },
        {
          file: 'server/src/middlewares/auth_middleware.js',
          find: 'if (!isPasswordVersionValid(claims, passwordHash)) {',
          note: 'Adım 12 — sunucu (oturum iptali): parola değişince pv uyuşmaz -> 401 code TOKEN_REVOKED; uygulama _handleSessionError ile oturumu kapatır ve giriş ekranında bir kez açıklama gösterir (takeSessionNotice).',
        },
      ],
      causes: [
        'Adım 4-5: hız sınırı (429) ya da hatalı deneme kilidi (LOGIN_LOCKED: aynı hesap ve kaynaktan 5 hata; ilk kilit 15 dk, tekrarında daha uzun); PM2 yeniden başlatması kilidi sıfırlar',
        'Adım 6-7: parola yanlış, kullanıcı adı/e-posta farklı yazılmış ya da hesap hiç yok (aynı 401 döner: hesap varlığı ayırt edilmez)',
        'Adım 8: hesap pasif, e-posta doğrulanmamış, abonelik onay bekliyor/reddedildi; rol seçimi uyuşmuyor',
        'Adım 9: sunucuda JWT_SECRET eksik/geçersiz (500 "Giris islemi basarisiz." + errorId)',
        'Adım 3: baseUrl yanlış derlenmiş uygulama (API_BASE_URL) ya da araya giren proxy/captive portal (JSON olmayan 401/403 oturum sonu sayılmaz)',
        'Adım 11-12: JWT süresi dolmuş (30 gün) ya da parola başka cihazdan değişmiş (TOKEN_REVOKED); hesap sonradan pasife alınmış',
      ],
      checks: [
        'Ekrandaki mesajı not edin; tam metni docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md içinde aratıp hangi adımdan geldiğini belirleyin',
        'Sunucu günlüğünde isteği bulun: "[API] POST /auth/login -> <durum>" (401: parola/kimlik, 403: durum kapıları, 429: hız/kilit, 500: errorId ile ayrıntı)',
        'Kullanıcı satırını salt-okunur sorguyla görün (parola özeti seçilmez): SELECT user_code, role, is_active, email_verified, approval_status FROM users WHERE LOWER(email) = LOWER(\'<e-posta>\');',
        '403 ise yanıttaki Türkçe metne göre Adım 8\'deki kapıyı bulun; "dogrulanmadi" ise akis-kayit-eposta-dogrulama akışına geçin',
        '429 + LOGIN_LOCKED ise yanıttaki retry_after_seconds kadar bekleyin (ilk kilit 15 dk) ya da şifre sıfırlama (akis-sifre-sifirlama) hesap kilidini açar',
        'Oturum açıkken sonradan çıkış oluyorsa 401 yanıtına bakın: code TOKEN_REVOKED = parola değişmiş; "Gecersiz veya suresi dolmus token." = süre bitmiş ya da imza geçersiz (JWT_SECRET değişmiş); "Kullanici bulunamadi." = kullanıcı silinmiş (uygulama her 401\'de oturumu kapatır)',
        'Sunucu açılışında "[ENV] HATA" ya da "[JWT]" uyarısı var mı: pm2 logs içinde arayın',
      ],
      logs: ['[login] hata (errorId=', '[ENV] HATA:', '[API] '],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a \'/auth/login\'"',
        'ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"',
      ],
      tests: [
        'server/test/core_auth_routes.test.js',
        'server/test/security_login_guard.test.js',
        'server/test/core_jwt.test.js',
        'server/test/core_auth_middleware.test.js',
        'test/auth_service_session_test.dart',
      ],
      related: ['akis-sifre-sifirlama', 'akis-kayit-eposta-dogrulama'],
    },

    // ------------------------------------------------------------------------------------------------
    // 2) Kayıt + e-posta doğrulama (bekleyen kayıt modeli)
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-kayit-eposta-dogrulama',
      symptom: 'Kayıt + e-posta doğrulama akışı bozuldu (uçtan uca): kod gelmiyor, geç geliyor, "kod hatalı/süresi dolmuş" ya da hesap açılmıyor',
      keywords: ['kayıt', 'register', 'e-posta doğrulama', 'doğrulama kodu', 'verify-code', 'resend-code', 'pending_registrations', 'SMTP', '503', 'EMAIL_DELIVERY_FAILED', 'kod gelmiyor'],
      refs: [
        {
          file: 'lib/ui/pages/register_individual_page.dart',
          find: 'await widget.authService.registerIndividual(',
          note: 'Adım 1 — uygulama (ekran): Ad/soyad/e-posta/parola AuthService.registerIndividual\'a gider; başarıda VerifyEmailCodePage açılır (30 sn tekrar-gönder bekleme sayacı ve 30 dk geçerlilik metni orada).',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "Uri.parse('$baseUrl/auth/register-individual');",
          note: 'Adım 2 — uygulama (HTTP): POST /auth/register-individual, 201 beklenir; 409/429/503 sunucu mesajıyla kullanıcıya gösterilir (AuthService.registerIndividual ApiException.message döndürür).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: "authRouter.post('/auth/register-individual', registerLimiter",
          note: 'Adım 3 — sunucu (rota): registerLimiter (IP+e-posta 15 dk/5, IP saatlik 40) -> registerIndividualUser; kod e-postayla gönderilemediyse dürüst 503 EMAIL_DELIVERY_FAILED + Retry-After: 60.',
        },
        {
          file: 'server/src/services/membership_service.js',
          find: 'export async function registerIndividualUser({',
          note: 'Adım 4 — sunucu (iş kuralı): girdi doğrulanır; doğrulanmış hesap varsa 409; hesap yoksa users satırı AÇILMAZ, yalnızca ad + bcrypt parola özeti beklemeye alınır. Eski doğrulanmamış individual hesap UPDATE ile güncellenir.',
        },
        {
          file: 'server/src/services/membership_service.js',
          find: 'async function issueVerificationCode({',
          note: 'Adım 5 — veritabanı: e-posta başına advisory kilit + 30 sn bekleme + saatlik 10 kod tavanı (429), sonra 6 haneli kodun bcrypt özeti email_verifications tablosuna INSERT edilir.',
        },
        {
          file: 'server/src/services/membership_service.js',
          find: 'await sendIndividualVerificationEmail({',
          note: 'Adım 6 — sunucu -> SMTP: mailer.js nodemailer ile SMTP_HOST/SMTP_USER/SMTP_PASSWORD kullanır (bağlantı 10 sn, soket 20 sn zaman aşımı). Hata olursa kod satırı silinir, günlüğe "[Mail Gönderim Hatası]" düşer, istemciye 503 döner.',
        },
        {
          file: 'server/src/services/membership_rules.js',
          find: 'export const SQL_UPSERT_PENDING_REGISTRATION',
          note: 'Adım 7 — veritabanı: ad + parola özeti pending_registrations tablosuna YALNIZCA e-posta gönderildikten sonra yazılır (e-posta başına tek satır; daha yeni açık kod varsa yazılmaz).',
        },
        {
          file: 'lib/ui/pages/verify_email_code_page.dart',
          find: 'await widget.authService.verifyIndividualCode(',
          note: 'Adım 8 — uygulama (ekran): kullanıcı 6 haneli kodu girer; AuthService.verifyIndividualCode çağrılır ve dönen hata metni ekranda gösterilir (404 durumunda AuthService mesaja "Kod 30 dakika geçerlidir; yeni kod için Kodu Tekrar Gönder" ipucunu ekler).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: "authRouter.post('/auth/verify-code', verifyCodeLimiter",
          note: 'Adım 9 — sunucu (rota): verifyCodeLimiter (IP+e-posta 15 dk/10, e-posta başına 20) -> verifyIndividualEmailCode; yanıt 200 + token + user.',
        },
        {
          file: 'server/src/services/membership_service.js',
          find: 'const claim = await client.query(SQL_CLAIM_VERIFICATION_ATTEMPT,',
          note: 'Adım 10 — veritabanı: deneme hakkı ATOMİK alınır (kod başına 5, 30 dk pencerede e-posta başına 10); hak alınamazsa aktif kod yok -> 404, kod/pencere deneme sınırı aşıldı -> 429; yanlış kod 400 "...kod hatalıdır" olur ve artan sayaç kalıcıdır.',
        },
        {
          file: 'server/src/services/membership_service.js',
          find: 'INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)',
          note: 'Adım 11 — veritabanı (tek işlem): kod doğruysa hesap ANCAK ŞİMDİ açılır (role individual, email_verified TRUE), bekleyen kayıt silinir, bekleyen yönetici davetleri bağlanır; işlem sonunda signAccessToken ile JWT döner. Bekleyen kayıt yoksa 404.',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '_session = await api.verifyIndividualCode(',
          note: 'Adım 12 — uygulama (oturum): yanıttaki token+user oturum olarak kaydedilir; kök rota (lib/app.dart) oturuma tepki verip HomePage\'e döner; kayıt ve doğrulama sayfaları popUntil ile kapanır.',
        },
      ],
      causes: [
        'Adım 6: SMTP kimliği/portu yanlış, sağlayıcı sınırı ya da ağ (ETIMEDOUT, EAUTH, 535/550); kod hiç gönderilmemiştir ve istemci 503 almıştır',
        'Adım 6 sonrası: sunucu e-postayı kabul etti ama alıcıya geç ulaştı (kod 30 dk geçerlidir; birden fazla e-postada yalnızca EN SON kod geçerli)',
        'Adım 5: 30 sn bekleme ya da saatlik tavan (429); aynı e-postaya birden çok kayıt denemesi',
        'Adım 10: kod başına 5 / pencere başına 10 deneme aşıldı (429) ya da kod süresi doldu / yeni kod istendi (eski kod geçersiz)',
        'Adım 11: bekleyen kayıt 2 günden eskiydi ve bakım servisince silindi (404 "Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz."); aynı e-postayla araya hesap girdi (409)',
        'Adım 4: e-posta zaten doğrulanmış hesapta (409) ya da başka rolde bekleyen hesap',
      ],
      checks: [
        'İstek günlükte var mı: "[API] POST /auth/register-individual -> <durum>"; 201 ise kod satırı yazılmıştır, 503 ise gönderim başarısızdır',
        'Mail hatasını görün: pm2 logs içinde "[Mail Gönderim Hatası]" satırındaki code (ETIMEDOUT/EAUTH/ECONNECTION) ve responseCode (535/550) alanları',
        'Başlangıçta "SMTP ayarlari eksik" uyarısı var mı (env eksikliği: SMTP_HOST, SMTP_USER, SMTP_PASSWORD; SMTP_FROM yoksa SMTP_USER gönderen olur)',
        'Veritabanında bekleyen kayıt ve kodlar: SELECT email, updated_at FROM pending_registrations WHERE LOWER(email) = LOWER(\'<e-posta>\'); SELECT id, attempt_count, is_verified, created_at FROM email_verifications WHERE LOWER(email) = LOWER(\'<e-posta>\') ORDER BY id DESC LIMIT 5;',
        'Giriş denemesinde "dogrulanmadi" 403 geliyorsa bekleyen kayıt (ya da eski doğrulanmamış hesap) vardır: kod girilince hesap açılır/doğrulanır; yeni kod için Kodu Tekrar Gönder (/auth/resend-code, yanıt hesabı belli etmez)',
        'Kod geç geliyorsa docs/EPOSTA_DOGRULAMA.md "İşletim" bölümündeki SMTP/DNS/Received başlıkları teşhisini uygulayın',
      ],
      logs: ['[Mail Gönderim Hatası]', '[Doğrulama Kodu]', '[resend-code] gonderim basarisiz', 'SMTP ayarlari eksik'],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'Mail G\'"',
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a \'/auth/verify-code\'"',
      ],
      tests: [
        'server/test/members_pending_registration.test.js',
        'server/test/members_verification.test.js',
        'server/test/mailer.test.js',
        'test/verify_and_profile_ui_test.dart',
      ],
      related: ['akis-giris-oturum-jwt', 'akis-bakim-temizlik-health'],
    },

    // ------------------------------------------------------------------------------------------------
    // 3) Şifre sıfırlama
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-sifre-sifirlama',
      symptom: 'Şifre sıfırlama akışı bozuldu (uçtan uca): bağlantı e-postası gelmiyor, bağlantı "geçersiz/süresi dolmuş" diyor ya da yeni parola kaydedilmiyor',
      keywords: ['şifre sıfırlama', 'şifremi unuttum', 'forgot-password', 'reset-password', 'sıfırlama bağlantısı', 'password_reset_token_hash', 'e-posta gelmiyor'],
      refs: [
        {
          file: 'lib/ui/pages/login_page.dart',
          find: 'final error = await widget.authService.forgotPassword(',
          note: 'Adım 1 — uygulama (ekran): "Şifremi Unuttum" penceresi e-postayı AuthService.forgotPassword\'a verir; başarıda hesap varsa bağlantı gönderildi uyarısı gösterilir (hesap varlığı belli edilmez).',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "Uri.parse('$baseUrl/auth/forgot-password');",
          note: 'Adım 2 — uygulama (HTTP): POST /auth/forgot-password, her zaman 200 beklenir; 429 (hız sınırı) mesajı pencerede gösterilir.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: "authRouter.post('/auth/forgot-password', forgotPasswordLimiter",
          note: 'Adım 3 — sunucu (rota): forgotPasswordLimiter (IP+e-posta 15 dk/3, e-posta saatlik 5); işlem arka planda yürür, yanıt hesap var/yok için AYNIDIR (200 ok:true).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'if (userRes.rowCount === 0 || !userRes.rows[0].is_active) {',
          note: 'Adım 4 — veritabanı: users satırı e-postayla aranır; hesap yoksa ya da pasifse SESSİZCE çıkılır (e-posta gönderilmez, günlüğe bile düşmez). "Mail gelmiyor"un en sık nedeni budur.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'SET password_reset_token_hash = $1,',
          note: 'Adım 5 — veritabanı: 32 baytlık rastgele token üretilir, yalnızca SHA-256 özeti users.password_reset_token_hash + password_reset_expires_at (30 dk) olarak saklanır; ham token yalnızca e-postadaki bağlantıdadır.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'const resetUrl =',
          note: 'Adım 6 — sunucu: bağlantı PUBLIC_APP_URL / PUBLIC_BASE_URL (yoksa https://api.gudeteknoloji.com.tr) + /auth/reset-password?token=... ile kurulur; yanlış env bağlantıyı ölü adrese çevirir.',
        },
        {
          file: 'server/src/mailer.js',
          find: 'export async function sendPasswordResetEmail({',
          note: 'Adım 7 — sunucu -> SMTP: şifre sıfırlama e-postası gönderilir; hata YALNIZCA günlüğe "[forgot-password] islem basarisiz" olarak yazılır, kullanıcıya yansımaz.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: "authRouter.get('/auth/reset-password'",
          note: 'Adım 8 — sunucu (tarayıcı): kullanıcı e-postadaki bağlantıyı açar; token biçimi (64 hex) -> 404, hash bulunamadı -> 404, süresi dolmuş -> 410, geçerliyse parola formu (sıkı CSP\'li HTML) döner.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: "authRouter.post('/auth/reset-password'",
          note: 'Adım 9 — sunucu (rota): form POST ile yeni parola (6-128 karakter) gönderir; token yeniden doğrulanır (geçersiz/süresi dolmuş -> 400).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'SET password_hash = $1,',
          note: 'Adım 10 — veritabanı: parola özeti, token ve süre TEK atomik UPDATE ile yazılır/temizlenir (token tek kullanımlıktır; eşzamanlı iki istekten biri 0 satır alır -> 400).',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'clearAccountLocks({',
          note: 'Adım 11 — sunucu: posta kutusuna erişim kanıtlandığı için hesap bazlı giriş/parola-değişim kilitleri (LOGIN_LOCKED) açılır; kullanıcı yeni parolayla beklemeden girer.',
        },
        {
          file: 'server/src/middlewares/auth_middleware.js',
          find: 'if (!isPasswordVersionValid(claims, passwordHash)) {',
          note: 'Adım 12 — sunucu (eski oturumlar): parola özeti değiştiği için eski token\'ların pv claim\'i uyuşmaz; diğer cihazlardaki oturumlar 401 TOKEN_REVOKED ile kapanır.',
        },
      ],
      causes: [
        'Adım 4: e-posta kayıtlı değil / hesap pasif (sessizce çıkılır) ya da e-posta farklı yazılmış',
        'Adım 7: SMTP hatası (kullanıcı yine de "gönderildi" görür); alıcı tarafında spam klasörü',
        'Adım 6: PUBLIC_APP_URL/PUBLIC_BASE_URL yanlış, bağlantı doğru adrese gitmiyor',
        'Adım 8: bağlantı 30 dk geçti (410), daha önce kullanıldı ya da yeni talep eskisini ezdi (404)',
        'Adım 3: hız sınırı (15 dk içinde 3 istek, saatte 5) nedeniyle 429',
        'Adım 12: kullanıcı parolayı değiştirdikten sonra eski cihazda oturum kapanır (beklenen davranış)',
      ],
      checks: [
        'Günlükte isteği bulun: "[API] POST /auth/forgot-password -> 200" (maske nedeniyle token görünmez); 429 ise limiter',
        'Hesap var mı ve aktif mi: SELECT user_code, is_active, password_reset_expires_at FROM users WHERE LOWER(email) = LOWER(\'<e-posta>\'); (özet alanını seçmeyin)',
        'Günlükte "[forgot-password] islem basarisiz" satırını arayın (SMTP/DB hatası burada tek satır olarak görünür; "[Mail Gönderim Hatası]" etiketi yalnız doğrulama kodu e-postası içindir)',
        'Bağlantıyı tarayıcıda açınca dönen durum: 404 geçersiz/kullanılmış, 410 süresi dolmuş, 200 form',
        'Sunucu env: PUBLIC_APP_URL / PUBLIC_BASE_URL değerleri (değeri paylaşmadan varlığını doğrulayın)',
        'Parola yazıldıktan sonra girişte hâlâ 401 ise akis-giris-oturum-jwt adımlarını izleyin',
      ],
      logs: ['[forgot-password] islem basarisiz', '[reset-password:get] hata', '[reset-password:post] hata (errorId='],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'forgot-password\'"',
      ],
      tests: ['server/test/password_reset.test.js', 'server/test/core_mailer_escape.test.js'],
      related: ['akis-giris-oturum-jwt', 'akis-kayit-eposta-dogrulama'],
    },

    // ------------------------------------------------------------------------------------------------
    // 4) Bulut kapı açma
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-bulut-kapi-acma',
      symptom: 'Bulut kapı açma akışı bozuldu (uçtan uca): uygulamada "Kapıyı aç" denince kapı açılmıyor, hata gösteriyor ya da komut gidiyor ama röle çekmiyor',
      keywords: ['kapı açılmıyor', 'kapı aç', 'door open', 'pulse', 'röle', 'mqtt', '202', '409', 'DEVICE_OFFLINE', 'MQTT_BRIDGE_NOT_CONNECTED', 'REMOTE_OPEN_DISABLED', 'geofence'],
      refs: [
        {
          file: 'lib/ui/pages/home_page.dart',
          find: 'final (status, error) = await widget.authService.openDoor(',
          note: 'Adım 1 — uygulama (ekran): kapı panelindeki düğme AuthService.openDoor\'u çağırır. Aynı çağrıyı sesli komut (voice_door_service.dart), widget/kısayol/deep link (lib/app.dart) ve bireysel ana ekran (individual_home_view.dart) da yapar.',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'final allowRemote = door == null || door.canOpenRemote || isSuper;',
          note: 'Adım 2 — uygulama (karar): kapı bayrakları istemcide de uygulanır; önce (izinliyse) yerel UDP denenir, olmazsa buluta düşülür; require_geofence kapıda konum alınamazsa istek HİÇ gönderilmez.',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "path: '/app/doors/$doorId/open',",
          note: 'Adım 3 — uygulama (HTTP): POST /app/doors/:id/open, 202 beklenir; kapı komutu için 10 sn kısa zaman aşımı ("Kapı komutuna zamanında yanıt alınamadı. Kapı açılmış olabilir...").',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: "appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter",
          note: 'Adım 4 — sunucu (rota): authRequired + kullanıcı/yol başına 10 sn\'de 4 istek sınırı (429 "Kapi komutu cok sik gonderildi"); kapı id doğrulanır (400 INVALID_DOOR_ID).',
        },
        {
          file: 'server/src/services/door_service.js',
          find: 'export async function getAccessibleDoorForUser({ authUser, doorId }) {',
          note: 'Adım 5 — veritabanı: kullanıcının bu kapıya yetkisi SQL ile hesaplanır (yönetici/site sahibi, özel kapı izni, sakin + SITE_COMMON/BLOCK kapsamı). Kapı yoksa/yetki yoksa 404 "Kapi bulunamadi."; cihaz atanmamışsa 409 "Bu kapiya cihaz atanmamis."',
        },
        {
          file: 'server/src/services/door_access_policy.js',
          find: "case 'remote':",
          note: 'Adım 6 — sunucu (politika): sitede uzaktan açma kapalıysa (feature_remote_open_enabled=false) 403 REMOTE_OPEN_DISABLED; süper kullanıcı istisnası vardır.',
        },
        {
          file: 'server/src/services/geofence_service.js',
          find: 'export function validateGeofenceForDoorRequest({',
          note: 'Adım 7 — sunucu (konum): site require_geofence ise konum alanları (latitude, longitude, accuracy, timestamp, is_mocked) doğrulanır; eksik/geçersiz/bayat (>60 sn)/yetersiz doğruluk (>100 m)/sahte konum/mesafe dışı -> 403 GEOFENCE_*. Site koordinatı tanımsızsa uyarıyla geçilir.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'export async function publishDoorPulse({',
          note: 'Adım 8 — MQTT (yayın): köprü bağlı değilse MQTT_BRIDGE_NOT_CONNECTED (503), cihaz çevrimdışıysa DEVICE_OFFLINE (409); aksi halde device/<UID>/cmd konusuna QoS1 {action:"pulse", request_id, requested_at(epoch sn), door_id, site_code} yayınlanır. Mosquitto ACL cihaza bu konuyu okuma izni verir (mqtt_acl_sync.js).',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: 'await recordDoorAccessLog({',
          nth: 1,
          note: 'Adım 9 — veritabanı (günlük): yayın başarılı olunca arka planda door_access_logs satırı (trigger_type cloud_app / voice / screen_qr) yazılır ve istemciye 202 döner. 202 "komut yayınlandı" demektir, cihazın uyguladığını GARANTİ ETMEZ; DB yazma hatası yalnızca günlüğe düşer.',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: 'inline void mqttHandlePulse(JsonDocument& json) {',
          note: 'Adım 10 — cihaz (komut): requested_at ile saat farkı >60 sn ise pulse_rejected/stale, aynı request_id tekrar gelirse yok sayılır, röle meşgulse pulse_rejected/role_busy; aksi halde röle tetiklenir, gDoorLocked=false, ekrana CMD_DOOR_OPENED, durum + pulse_started olayı yayınlanır.',
        },
        {
          file: 'cihaz_kontrol/include/role_kontrol.h',
          find: 'inline bool roleTetikle() {',
          note: 'Adım 11 — cihaz (röle): röle aktifse ya da son tetikten 2.5 sn geçmediyse reddedilir (debounce); aksi halde ROLE_PIN aktif olur ve esp_timer ile ROLE_SURE_MS (1500 ms) sonra bırakılır; bırakınca pulse_completed olayı + kilitli durum yayınlanır.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "if (kind === 'state') {",
          note: 'Adım 12 — dönüş (durum): cihazın device/<UID>/state yayını köprüde door_locked/wifi/firmware olarak güncellenir ve device_runtime_status\'a yazılır; uygulama kapı panelinde ~3 sn\'lik yoklamayla GET /app/doors/:id/status üzerinden bunu görür.',
        },
      ],
      causes: [
        'Adım 2: kapı bayrağı kapalı ("Bu kapı için uygulamadan açma kapalı") ya da konum izni/servisi kapalı (require_geofence)',
        'Adım 4: 10 sn içinde 4\'ten fazla istek (429)',
        'Adım 5: kullanıcının kapıya yetkisi yok / üyelik pasif / kapıya cihaz atanmamış (404/409)',
        'Adım 6-7: site politikası (REMOTE_OPEN_DISABLED) ya da geofence reddi (GEOFENCE_OUT_OF_RANGE, GEOFENCE_MOCK_LOCATION, GEOFENCE_LOCATION_STALE...)',
        'Adım 8: MQTT köprüsü bağlı değil (MQTT_HOST/USER/PASSWORD eksik, broker kapalı) ya da cihaz çevrimdışı görünüyor (409); ACL\'de cihaz yok',
        'Adım 10: cihaz saati senkron değil/çok kaymış (stale), röle zaten aktif (role_busy), cihazın MQTT bağlantısı sessizce kopuk (LWT henüz tetiklenmedi)',
        'Adım 11: röle pini/kablo/kilit arızası (yazılım pulse_started yayınlar ama kapı açılmaz)',
        'Adım 3: ağ/proxy kesintisi; 10 sn zaman aşımı kapının açılmış olmasını engellemez (kontrol edin)',
      ],
      checks: [
        'Uygulamada görünen mesajı aratın (docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md): hangi adımdan geldiğini bulun',
        'Sunucu günlüğü: "[API] POST /app/doors/<id>/open -> <durum>" (202 başarı; 403 politika/konum; 409 cihaz yok/çevrimdışı; 429 sınır; 503 köprü) ve "door_open_command" denetim satırı',
        'Köprü sağlığı: GET /health -> mqtt.connected true mu, last_error ne (mqtt_not_configured | mqtt_offline | mqtt_error | db_error)',
        'Cihaz çevrimiçi mi: SELECT device_uid, is_online, last_online_at FROM devices WHERE device_uid = \'<UID>\'; SELECT mqtt_connected, last_seen_at, last_event FROM device_runtime_status WHERE device_uid = \'<UID>\';',
        'Cihaz seri günlüğünde "MQTT komut alindi", "Role tetiklendi GPIO", "MQTT pulse REDDEDILDI" ya da "Role debounce" satırını arayın',
        'Cihaz olayları: device_runtime_status.last_event = pulse_started / pulse_completed / pulse_rejected (last_event_detail: stale | role_busy)',
        'Röle çekiyor ama kapı açılmıyorsa donanıma bakın (ROLE_PIN, röle kartı, kilit besleme); yazılım katmanı çalışmıştır',
        'Yerel ağdan açılıyor ama bulut açmıyorsa akis-yerel-kapi-acma ile karşılaştırın (MQTT yolu bozuktur)',
      ],
      logs: [
        'door_open_command',
        'Kapi gecis logu DB kayit hatasi:',
        '[MQTT bridge] ',
        'MQTT komut alindi (',
        'MQTT pulse REDDEDILDI: requested_at zaman penceresi disinda.',
        'MQTT pulse yok sayildi: ayni request_id tekrar geldi.',
        'Role tetiklendi GPIO',
        'Role debounce: Role zaten aktif veya son tetikten bu yana 2.5s gecmedi.',
      ],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"',
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a \'/open\'"',
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'MQTT bridge\'"',
      ],
      tests: [
        'server/test/doors_routes.test.js',
        'server/test/doors_mqtt.test.js',
        'server/test/doors_policy.test.js',
        'server/test/doors_geofence.test.js',
        'test/local_door_access_test.dart',
      ],
      related: ['akis-yerel-kapi-acma', 'akis-cihaz-baglanti-gunlukleri', 'akis-dinamik-qr-gm60'],
    },

    // ------------------------------------------------------------------------------------------------
    // 5) Dinamik QR (uygulama QR gösterir, cihazdaki GM60 okur)
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-dinamik-qr-gm60',
      symptom: 'Dinamik QR ile kapı açma akışı bozuldu (uçtan uca): telefondaki QR\'ı cihaz kamerası (GM60) okuyor ama kapı açılmıyor / "geçersiz, kullanılmış, süresi dolmuş" deniyor',
      keywords: ['dinamik qr', 'karekod', 'qr token', 'gm60', 'qr_verify', 'qr_result', 'geofence', 'ALREADY_USED', 'EXPIRED_TOKEN', 'SUPERSEDED_TOKEN', 'NO_QR_SCANNER_HARDWARE'],
      refs: [
        {
          file: 'lib/ui/widgets/dynamic_qr_pass_modal.dart',
          find: 'final (data, error) = await auth.requestDoorQrToken(',
          note: 'Adım 1 — uygulama (ekran): QR penceresi açılınca (konum zorunluysa önce GPS konumuyla) /qr-token istenir; dönen token QR olarak çizilir, geri sayım ve durum yoklaması başlar.',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: "appDoorsRouter.post('/app/doors/:id/qr-token', authRequired, qrTokenRateLimiter",
          note: 'Adım 2 — sunucu (rota): authRequired + kullanıcı başına dakikada 6 istek (429 "Karekod talebi çok sık yapıldı"); hata gövdesi code alanı taşır (NO_QR_SCANNER_HARDWARE, GEOFENCE_*, QR_DISABLED).',
        },
        {
          file: 'server/src/services/qr_access_service.js',
          find: 'export async function generateQrTokenForDoor(',
          note: 'Adım 3 — sunucu (kurallar): kapı erişimi, qr kanalı politikası (QR_DISABLED/QR_ENTRY_INACTIVE), kapıda fiziksel okuyucu (C3 cihazı ya da qr_reader_enabled=false -> 400 NO_QR_SCANNER_HARDWARE) ve geofence doğrulanır.',
        },
        {
          file: 'server/src/services/qr_access_service.js',
          find: "const rawToken = 'QR:' + crypto.randomBytes(24).toString('hex');",
          note: 'Adım 4 — veritabanı: 192 bit rastgele "QR:..." token qr_access_tokens\'a yazılır; aynı kullanıcı+kapı için önceki aktif token\'lar aynı işlemde SUPERSEDE edilir; süre site qr_rotation_seconds (varsayılan 30 sn).',
        },
        {
          file: 'cihaz_kontrol/include/gm60_scanner.h',
          find: 'inline void gm60QrVerisiniIsle(String qrData) {',
          note: 'Adım 5 — cihaz (okuma): GM60 UART\'tan gelen veri temizlenir; sunucu yanıtı beklenirken, 5 sn debounce içinde ve aynı token 8 sn içinde tekrar okunursa atlanır; MQTT yoksa dinamik QR açılmaz (CMD_QR_DENIED).',
        },
        {
          file: 'cihaz_kontrol/include/gm60_scanner.h',
          find: 'const bool gonderildi = mqttPublishQrVerify(qrData, istekId);',
          note: 'Adım 6 — MQTT (cihaz -> sunucu): token device/<UID>/qr_verify konusuna {token, request_id} olarak yayınlanır (cihaz ACL\'de bu konuya yazabilmeli); 10 sn qr_result beklenir.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "if (kind === 'qr_verify') {",
          note: 'Adım 7 — sunucu (köprü): retained qr_verify yok sayılır; verifyQrTokenAndOpenDoor çağrılır ve sonuç device/<UID>/qr_result konusuna aynı request_id ile yayınlanır (allowed/reason).',
        },
        {
          file: 'server/src/services/qr_access_service.js',
          find: 'export async function verifyQrTokenAndOpenDoor(',
          note: 'Adım 8 — veritabanı + kurallar: cihaz->kapı eşleşmesi, qr_reader_enabled, token durumu (ALREADY_USED, SUPERSEDED_TOKEN, EXPIRED_TOKEN, TOKEN_OR_USER_INACTIVE, DOOR_MISMATCH) ve tüketim anında yetki + site politikası yeniden denetlenir; token kaynaklı redler (ve tanımsız QR) door_access_logs\'a (qr_scanner) yazılır; cihaz/okuyucu/kapı atama redleri (DEVICE_NOT_FOUND, QR_READER_NOT_ENABLED, DOOR_NOT_ASSIGNED) yazılmaz.',
        },
        {
          file: 'server/src/services/qr_access_service.js',
          find: 'SET is_used = TRUE,',
          note: 'Adım 9 — veritabanı (atomik tüketim): tek UPDATE ile token tek kullanımlık işaretlenir; 0 satır dönerse yarış kaybedilmiştir (ALREADY_USED).',
        },
        {
          file: 'server/src/services/qr_access_service.js',
          find: 'assumeOnline: true,',
          note: 'Adım 10 — MQTT (sunucu -> cihaz): publishDoorPulse çağrılır (istek cihazdan geldiği için çevrimiçi varsayılır); komut gönderilemezse token geri verilir (PULSE_FAILED) ve başarısız olarak loglanır. Başarıda "[QR Dogrulama ONAY]" günlüğü ve door_access_logs (qr_scanner) satırı yazılır.',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: 'inline void mqttHandleQrResult(const String& message) {',
          note: 'Adım 11 — cihaz (sonuç): request_id bekleyen istekle eşleşmezse sonuç yok sayılır; allowed=false ise CMD_QR_DENIED gösterilir ve aynı QR yeniden denenebilir; allowed=true ise röle pulse komutu AYRICA gelir (mqttHandlePulse) ve kapıyı açar.',
        },
        {
          file: 'lib/ui/widgets/dynamic_qr_pass_modal.dart',
          find: 'final (data, error) = await auth.getDoorQrStatus(qrToken);',
          note: 'Adım 12 — dönüş (uygulama): telefon /app/doors/qr-status ile token durumunu yoklar; geçiş başarılı / kullanılmış / yenilenmiş / süresi dolmuş / reddedildi durumlarını ekranda başlık olarak gösterir.',
        },
      ],
      causes: [
        'Adım 3: kapıda QR kapalı (QR_DISABLED), ekransız C3 cihazı ya da qr_reader_enabled=false (NO_QR_SCANNER_HARDWARE), geofence reddi',
        'Adım 5: GM60 kamera bağlı değil/yanıt vermiyor (gm60Bagli false), ekran-telefon mesafesi/parlaklığı, MQTT bağlı değil (offline QR açmaz)',
        'Adım 8: token 30 sn doldu (EXPIRED_TOKEN), yeni QR istendi (SUPERSEDED_TOKEN), aynı QR ikinci kez okutuldu (ALREADY_USED), başka kapıdaki okuyucuya gösterildi (DOOR_MISMATCH), üyelik/izin sonradan kalktı (ACCESS_REVOKED)',
        'Adım 6-7: cihazın MQTT ACL\'de qr_verify yazma izni yok / köprü qr_verify aboneliği düşmüş (qr_result hiç gelmez, cihaz 10 sn sonra vazgeçer)',
        'Adım 10: cihaz çevrimdışı/köprü bağlı değil (PULSE_FAILED); röle meşgul (pulse_rejected role_busy)',
      ],
      checks: [
        'Cihaz seri günlüğü: "[GM60] QR okundu", "[GM60] QR basariyla sunucuya gonderildi", "[MQTT QR Sonuc] Izin: ONAYLANDI/REDDEDILDI | Neden: ..." satırları hangi adımda durduğunu söyler',
        'Neden kodu "Neden:" alanında görünür (ALREADY_USED, EXPIRED_TOKEN, SUPERSEDED_TOKEN, DOOR_MISMATCH, ACCESS_REVOKED, PULSE_FAILED, INVALID_TOKEN, QR_READER_NOT_ENABLED, DOOR_NOT_ASSIGNED)',
        'Sunucu günlüğünde "[QR Dogrulama RED]" veya "[QR Dogrulama ONAY]" satırını arayın',
        'DB: SELECT id, is_active, is_used, expires_at, last_denial_reason FROM qr_access_tokens WHERE user_code = <kod> ORDER BY id DESC LIMIT 5; SELECT device_uid, qr_reader_enabled FROM devices WHERE device_uid = \'<UID>\';',
        'Kameradan hiç satır gelmiyorsa donanım (GM60 bağlantısı, "k" seri komutu = kamera self-test)',
        'QR gösterildi ama telefon durum başlığı değişmiyorsa /app/doors/qr-status isteğini günlükte arayın',
      ],
      logs: [
        '[QR Dogrulama RED]',
        '[QR Dogrulama ONAY]',
        '[MQTT QR Verify] Islem hatasi:',
        '[GM60] QR basariyla sunucuya gonderildi. Sunucu dogrulamasi bekleniyor.',
        '[MQTT QR Sonuc] Izin: ',
      ],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'QR Dogrulama\'"',
      ],
      tests: [
        'server/test/doors_qr_access.test.js',
        'server/test/doors_screen_qr.test.js',
        'test/fix_fx2_qr_modal_test.dart',
        'test/qr_modal_polling_test.dart',
      ],
      related: ['akis-bulut-kapi-acma', 'akis-ekran-qr-uygulama-okutma', 'akis-misafir-gecis'],
    },

    // ------------------------------------------------------------------------------------------------
    // 6) Ekrandaki dinamik QR'ı uygulamayla okutma (scan-qr-open)
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-ekran-qr-uygulama-okutma',
      symptom: 'Karekod okutarak kapı açma akışı bozuldu (uçtan uca): uygulamayla cihaz ekranındaki karekodu okutunca kapı açılmıyor / "karekod süresi dolmuş" / "karekod henüz alınamadı"',
      keywords: ['scan-qr-open', 'ekran karekod', 'EKRAN_QR_BEKLENIYOR', 'SCREEN_QR_EXPIRED', 'SCREEN_QR_ALREADY_USED', 'DYNAMIC_QR_REQUIRED', 'karekod okut', 'screen_qr'],
      refs: [
        {
          file: 'lib/ui/views/individual_home_view.dart',
          find: 'await widget.authService.openDoorWithScannedQr(',
          note: 'Adım 1 — uygulama (ekran): kamera ile okunan karekod metni AuthService.openDoorWithScannedQr\'a verilir (konum zorunluysa GPS konumu eklenir). Daire sakini kartı da aynı çağrıyı yapar (resident_door_remote_card.dart).',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "path: '/app/doors/scan-qr-open',",
          note: 'Adım 2 — uygulama (HTTP): POST /app/doors/scan-qr-open {qr_payload + konum}, 200 beklenir; 10 sn zaman aşımı ("Karekod doğrulamasına zamanında yanıt alınamadı. Kapı açılmış olabilir...").',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: "appDoorsRouter.post('/app/doors/scan-qr-open', authRequired, doorCommandRateLimiter",
          note: 'Adım 3 — sunucu (rota): qr_payload ayrıştırılır (400 INVALID_QR_PAYLOAD), karekoddaki UID ile aktif kapı aranır (404 DOOR_NOT_FOUND), kullanıcının kapıya yetkisi denetlenir (403 DOOR_ACCESS_DENIED).',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: "assertDoorOpenAllowed({ door, channel: 'qr', authUser: req.authUser });",
          note: 'Adım 4 — sunucu (politika): qr kanalı kapalıysa 403 QR_DISABLED / QR_ENTRY_INACTIVE (süper kullanıcı istisnası).',
        },
        {
          file: 'cihaz_kontrol/src/main.cpp',
          find: 'const String qrCmd = String(CMD_SHOW_QR_PREFIX)',
          note: 'Adım 5 — cihaz (arka plan, sürekli): ekranlı WROOM her 30 sn\'de 6 karakterlik yeni ekran tokenı üretir, UART ile ekrana gönderir; Adım 8\'in ön koşuludur. C3\'te ekran/token yoktur.',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: 'inline bool mqttPublishScreenQr(',
          note: 'Adım 6 — MQTT (cihaz -> sunucu, sürekli): token device/<UID>/screen_qr konusuna yayınlanır (retained DEĞİL; token seriye yazılmaz).',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "if (kind === 'screen_qr') {",
          note: 'Adım 7 — sunucu (köprü, sürekli): token deviceScreenQrStore belleğine (cihaz UID anahtarıyla) yazılır; retained mesajlar yok sayılır. Süreç yeniden başlayınca bellek boştur: ilk yayına kadar 409 EKRAN_QR_BEKLENIYOR.',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: 'const check = checkScreenQrToken(screenEntry, parsed.token);',
          note: 'Adım 8 — sunucu (token): ekranlı cihazda token ZORUNLU (403 DYNAMIC_QR_REQUIRED); bellekte token yoksa 409 EKRAN_QR_BEKLENIYOR; süresi dolmuş -> 403 SCREEN_QR_EXPIRED; kullanılmış -> 403 SCREEN_QR_ALREADY_USED. Eşleşmeyen/eski token da istemciye 403 SCREEN_QR_EXPIRED döner (denetim satırında kod SCREEN_QR_MISMATCH olur).',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: 'forceRequire: !hasScreen,',
          note: 'Adım 9 — sunucu (konum): ekransız (statik UID karekodlu) cihazda geofence site bayrağından bağımsız ZORUNLUDUR; ekranlıda site ayarına bağlıdır.',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: 'const consumed = consumeScreenQrToken(screenEntry, parsed.token);',
          note: 'Adım 10 — sunucu (tüketim): ekran tokenı TEK KULLANIMLIK tüketilir (senkron; yarış yok); sonraki adımda komut gönderilemezse releaseScreenQrToken ile geri verilir.',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: 'await publishDoorPulse({',
          nth: 2,
          note: 'Adım 11 — MQTT (sunucu -> cihaz): device/<UID>/cmd pulse yayınlanır (hata kodları bulut açmayla aynı: 503 köprü, 409 çevrimdışı); ardından arka planda door_access_logs (trigger_type screen_qr) yazılır ve 200 döner.',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: 'if (action == "pulse") {',
          note: 'Adım 12 — cihaz: pulse komutu mqttHandlePulse -> roleTetikle ile röleyi çeker (ayrıntı için akis-bulut-kapi-acma Adım 10-11).',
        },
      ],
      causes: [
        'Adım 8: karekod yenilenmiş (30 sn) -> SCREEN_QR_EXPIRED; aynı karekod ikinci kez -> SCREEN_QR_ALREADY_USED; sunucu yeniden başlamış/cihaz çevrimdışı -> EKRAN_QR_BEKLENIYOR',
        'Adım 5-7: cihaz ekran tokenını yayınlamıyor (MQTT bağlı değil, ekran kartı yok) ya da ACL screen_qr yazma izni yok',
        'Adım 3: karekod başka siteye/kapıya ait ya da kullanıcının yetkisi yok (DOOR_ACCESS_DENIED)',
        'Adım 9: ekransız cihazda konum zorunlu; konum izni/doğruluğu yetersiz (GEOFENCE_*)',
        'Adım 11: cihaz çevrimdışı (409) ya da köprü bağlı değil (503); bu durumda token geri verilir, tekrar denenebilir',
      ],
      checks: [
        'Sunucu günlüğünde "[API] POST /app/doors/scan-qr-open -> <durum>" ve yanıttaki code alanı (uygulama mesajı da aynı metni gösterir)',
        'Köprü ekran tokenını alıyor mu: cihaz seri portuna "s" gönderip "MQTT: bagli" satırına bakın; sunucuda device_runtime_status.last_seen_at güncel mi',
        'Denetim satırı: "scan_qr_open_rejected" olayı ve code alanı (DYNAMIC_QR_REQUIRED, EKRAN_QR_BEKLENIYOR, SCREEN_QR_...)',
        'Ekran QR sürekli yenileniyorsa kullanıcının okuttuğu kodun hâlâ güncel olduğundan emin olun (yenilenme 30 sn)',
        'Komut gitti ama kapı açılmadıysa akis-bulut-kapi-acma Adım 10-12 kontrollerine geçin',
      ],
      logs: ['scan_qr_open_rejected', '[app_doors] ', 'Kapi gecis logu DB kayit hatasi:'],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a \'scan-qr-open\'"',
      ],
      tests: ['server/test/doors_screen_qr.test.js', 'server/test/doors_routes.test.js', 'test/fix_fx2_widgets_test.dart'],
      related: ['akis-bulut-kapi-acma', 'akis-dinamik-qr-gm60'],
    },

    // ------------------------------------------------------------------------------------------------
    // 7) Yerel (UDP) kapı açma
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-yerel-kapi-acma',
      symptom: 'Yerel kapı açma akışı bozuldu (uçtan uca): telefon cihazla aynı Wi-Fi\'de ama kapı yerel ağdan açılmıyor, hep buluta düşüyor',
      keywords: ['yerel kontrol', 'udp', 'local', 'beacon', 'challenge', 'hmac', 'local_control_token', 'yerel ağ', '8765', 'local-open-notify'],
      refs: [
        {
          file: 'lib/services/auth_service.dart',
          find: 'final localResult = await _tryOpenDoorLocallyIfAlive(door);',
          note: 'Adım 1 — uygulama (karar): yerel yol YALNIZCA kapı yerel açmaya izin veriyorsa, telefon yerel Wi-Fi\'deyse, önbellekte geçerli token varsa ve cihazın taze beacon\'ı görüldüyse denenir; aksi halde sessizce buluta düşülür.',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<void> _cacheLocalDoorAccess(DoorRuntimeStatus status) async {',
          note: 'Adım 2 — uygulama (önbellek): token sunucudan kapı durumu yanıtıyla gelir ve güvenli depoya yazılır; sunucu token vermezse (yetki kalktı/token döndürüldü) önbellek temizlenir ve yerel açma denenmez (fail-closed).',
        },
        {
          file: 'server/src/services/door_service.js',
          find: 'export async function localDoorControlForStatus(',
          note: 'Adım 3 — sunucu: sitede yerel açma kapalıysa (feature_local_udp_enabled=false) token VERİLMEZ; aksi halde cihaz için local_control_token üretilir/okunur ve cihaz bunu henüz bilmiyorsa (local_control_available false) dakikada bir MQTT ile cihaza gönderilir.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'export async function publishLocalControlConfig({',
          note: 'Adım 4 — MQTT (sunucu -> cihaz): device/<UID>/cmd konusuna {action:"local_control_config", local_control_token} yayınlanır; cihaz çevrimdışıysa false döner (token iletilmez).',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: '} else if (action == "local_control_config") {',
          note: 'Adım 5 — cihaz (anahtar): token doğrulanıp NVS\'e yazılır (wifiPersistLocalToken; geçersizse local_control_config_rejected olayı); sonraki durum yayınında local_control_available true olur.',
        },
        {
          file: 'cihaz_kontrol/include/yerel_kapi_kontrol.h',
          find: 'inline void yerelBeaconYayinla() {',
          note: 'Adım 6 — cihaz (beacon): ~5 sn\'de bir UDP broadcast {device_uid, ip, port 8765, rssi, hw, ch(challenge)}; uygulama bunu dinleyip önbelleğe alır (LocalDoorService.startBeaconListener).',
        },
        {
          file: 'lib/services/local_door_service.dart',
          find: 'Future<bool> _directUdpOpen(',
          note: 'Adım 7 — uygulama (UDP): sig = HMAC-SHA256(token, "open|UID|ch") ile imzalı paket cihazın IP:8765 adresine gider (token ağa çıkmaz); 150 ms içinde yanıt gelmezse false -> buluta düşülür; "challenge" hatasında güncel ch ile TEK yeniden deneme.',
        },
        {
          file: 'cihaz_kontrol/include/yerel_kapi_kontrol.h',
          find: 'inline void yerelUdpAcmaIsle(JsonDocument& doc,',
          note: 'Adım 8 — cihaz (karar): token yok / yinelenen / ch geçersiz / imza yanlış / röle meşgul sonuçları unauthorized, duplicate, challenge, role_mesgul olarak yanıtlanır; doğruysa yanıt gönderilir ve yan etkiler çalışır (yerelKontrolKullanilabilirMi: HMAC öz-testi + token şart).',
        },
        {
          file: 'cihaz_kontrol/include/yerel_kapi_kontrol.h',
          find: 'inline void yerelKapiAcildiYanEtkileri(',
          note: 'Adım 9 — cihaz (röle + günlük): gDoorLocked=false, ekran, MQTT olayı local_udp_pulse_started + durum ve offlineLogKaydet("local_udp") ile cihazın çevrimdışı günlüğüne satır (MQTT ile senkronlanır: akis-cevrimdisi-kapi-gunlukleri).',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '.notifyLocalDoorOpened(',
          note: 'Adım 10 — uygulama (bildirim): yerel açma başarılı olunca arka planda sunucuya /local-open-notify gönderilir (hata oturumu etkilemez).',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: "appDoorsRouter.post('/app/doors/:id/local-open-notify'",
          note: 'Adım 11 — sunucu (rota): kapı yetkisi + local kanal politikası denetlenir (403 LOCAL_DISABLED), local_ip normalize edilir, "door_open_local_command" denetim satırı yazılır.',
        },
        {
          file: 'server/src/routes/app_doors_routes.js',
          find: 'await recordLocalOpenNotifyLog({',
          note: 'Adım 12 — veritabanı (günlük): door_access_logs\'a trigger_type local_wifi satırı yazılır (aynı kullanıcı + kapı için 15 sn içinde yerel satır varsa yazılmaz); bu uç yerel açmayı DOĞRULAMAZ, yalnızca kaydeder.',
        },
        {
          file: 'server/src/services/door_log_service.js',
          find: 'export async function reconcileLocalOpenLogs(',
          note: 'Adım 13 — veritabanı (tekilleştirme): cihaz aynı yerel açmayı kendi offline logu olarak da (local_udp, kullanıcısız) gönderir; 15 sn içinde eşleşen çiftte cihaz satırı korunur, kullanıcı bilgisi ona taşınır, uygulama satırı silinir (eşleşme gelişin sırasından bağımsız; saati bilinmeyen kayıtlar eşleşmez, çift satır kalabilir).',
        },
      ],
      causes: [
        'Adım 1: telefon farklı ağda/mobil veride, VPN ya da "AP izolasyonu" açık modem (UDP broadcast ulaşmaz); beacon dinleyici duraklatılmış',
        'Adım 2-3: kapıda/sitede yerel açma kapalı (token verilmez) ya da sunucu henüz token üretmemiş/cihaza iletmemiş',
        'Adım 5: cihazda token yok ya da HMAC öz-testi başarısız (local_control_selftest_failed olayı; yerel açma fail-closed KAPALI)',
        'Adım 7-8: imza uyuşmuyor (token döndürülmüş, uygulama eski token kullanıyor) -> unauthorized; ch bayat -> tek yeniden deneme; kaynak adres özel ağ değil',
        'Adım 8: röle meşgul (role_mesgul) ya da paket 512 bayttan büyük',
        'Adım 6: cihaz Wi-Fi\'de değil, beacon yayınlamıyor (yalnızca Wi-Fi bağlıyken yayınlar)',
      ],
      checks: [
        'Uygulama hata ayıklama günlüğünde "[YerelKapi]" satırları: canlı beacon bulundu mu, UDP yanıtı doğrulandı mı',
        'Cihaz seri günlüğü: "Yerel kapi kontrol aktif", "UDP Kapi Acma REDDEDILDI: imza gecersiz.", "Yerel UDP: KAPI ACILDI (role tetiklendi)."',
        'Cihaz seri durum dökümü ("s" komutu): "Yerel kontrol: etkin (anahtar var)" mı, "kapali (anahtar yok)" mı',
        'Sunucuda token iletildi mi: device_runtime_status.local_control_available ve "local_control_token_synced" denetim satırı',
        'Site politikası: sites.feature_local_udp_enabled (false ise yerel açma bilerek kapalıdır)',
        'Token döndürüldüyse (üyelik/izin değişimi) uygulama kapı durumunu yenileyince yeni token gelir; o ana kadar unauthorized normaldir',
        'Protokol ayrıntısı ve test vektörü: docs/YEREL_KONTROL_V2.md',
      ],
      logs: [
        'UDP Kapi Acma REDDEDILDI: imza gecersiz.',
        'Yerel UDP: KAPI ACILDI (role tetiklendi).',
        'Yerel kontrol: HMAC oz-testi basarili.',
        'local_control_token_synced',
        'door_open_local_command',
      ],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'local\'"',
      ],
      tests: [
        'test/local_door_service_v2_test.dart',
        'test/local_door_service_security_test.dart',
        'test/local_door_access_test.dart',
        'server/test/devices_device_service.test.js',
        'cihaz_kontrol/host_test/t_core.cpp',
      ],
      related: ['akis-bulut-kapi-acma', 'akis-cevrimdisi-kapi-gunlukleri'],
    },

    // ------------------------------------------------------------------------------------------------
    // 8) Bakım zamanlayıcısı + /health
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-bakim-temizlik-health',
      symptom: 'Bakım/temizlik ve sağlık akışı bozuldu (uçtan uca): eski kayıtlar silinmiyor, süper kullanıcı "Veritabanı Sağlığı" penceresi hata veriyor ya da /health "ok:false" dönüyor',
      keywords: ['bakım', 'temizlik', 'cleanup', 'maintenance', 'health', '/health', 'app_maintenance_runs', 'routine_cleanup', 'veritabanı sağlığı', 'runDatabaseCleanup', 'mqtt_offline'],
      refs: [
        {
          file: 'server/src/server.js',
          find: 'setInterval(runCleanupSafely, 24 * 60 * 60 * 1000).unref();',
          note: 'Adım 1 — sunucu (zamanlayıcı): açılışta bir kez ve sonra 24 saatte bir runCleanupSafely çalışır; hata yalnızca "[Bakim] Temizlik hatasi:" olarak günlüğe düşer, süreç düşmez. PM2 yeniden başlayınca sayaç sıfırlanır.',
        },
        {
          file: 'server/src/services/maintenance_service.js',
          find: 'export async function runDatabaseCleanup(db = pool) {',
          note: 'Adım 2 — sunucu (iş kuralı): yalnızca süresi dolmuş QR token (1 gün), e-posta doğrulama kodu (2 gün), bekleyen kayıt (2 gün), 30 günden eski bağlantı ve kapı günlükleri silinir; kullanıcı hesabı, üyelik veya tablo SİLİNMEZ.',
        },
        {
          file: 'server/src/services/maintenance_service.js',
          find: 'DELETE FROM door_access_logs',
          note: 'Adım 3 — veritabanı: kapı geçiş günlüğü 30 gün saklanır (opened_at). Uygulamada eski günlüğün görünmemesi hata değil, saklama süresidir.',
        },
        {
          file: 'server/src/services/maintenance_service.js',
          find: "VALUES ('routine_cleanup', NOW())",
          note: 'Adım 4 — veritabanı: son başarılı temizlik app_maintenance_runs tablosuna "routine_cleanup" anahtarıyla yazılır; sağlık penceresindeki "son temizlik" buradan okunur. Hata olursa bu satır güncellenmez.',
        },
        {
          file: 'lib/ui/views/all_users_view.dart',
          find: 'final data = await widget.onGetDatabaseHealth!();',
          note: 'Adım 5 — uygulama (ekran): süper kullanıcının sağlık penceresi açılınca AuthService.getDatabaseHealth çağrılır; "Temizle" düğmesi onRunDatabaseCleanup\'ı çağırır, ardından sağlığı yeniler.',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "path: '/admin/maintenance/health',",
          note: 'Adım 6 — uygulama (HTTP): GET /admin/maintenance/health (200 beklenir); temizlik için POST /admin/maintenance/cleanup (hemen altında).',
        },
        {
          file: 'server/src/routes/admin_routes.js',
          find: "adminRouter.get('/admin/maintenance/health', authRequired, requireSuperUser",
          note: 'Adım 7 — sunucu (rota): yalnızca süper kullanıcı (aksi halde 401/403); getDatabaseHealth hata verirse 500 + errorId ("Veritabani saglik bilgisi alinamadi.").',
        },
        {
          file: 'server/src/routes/admin_routes.js',
          find: "adminRouter.post('/admin/maintenance/cleanup', authRequired, requireSuperUser",
          note: 'Adım 8 — sunucu (rota): "database_maintenance_cleanup_requested" denetim satırı yazılır ve runDatabaseCleanup elle çalıştırılır; hata 500 + errorId.',
        },
        {
          file: 'server/src/services/maintenance_service.js',
          find: 'export async function getDatabaseHealth(db = pool) {',
          note: 'Adım 9 — veritabanı: kullanıcı/yapı/cihaz sayıları, silinebilir kayıt sayıları (pendingCleanup) ve son temizlik tarihi SELECT\'lerle toplanır. isClean yalnızca silinebilir kayıt sayısına bağlıdır.',
        },
        {
          file: 'server/src/routes/firmware_routes.js',
          find: "firmwareRouter.get('/health', async (_req, res) => {",
          note: 'Adım 10 — sunucu (/health): herkese açık; checkDbConnection (SELECT 1) başarılıysa 200 {ok:true, database, mqtt}; DB hatasında 500 {ok:false, database:"disconnected"}. Deploy betiği ve PM2 sonrası kontrol bu yanıtı kullanır.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'export function mqttBridgeHealth() {',
          note: 'Adım 11 — MQTT (köprü sağlığı): /health içindeki mqtt alanı configured/connected/has_error ve kısa last_error kodunu verir (ham hata metni sızmaz). MQTT kopuk olsa bile /health ok:true kalabilir; MQTT durumuna ayrıca bakın.',
        },
        {
          file: 'deploy/remote_deploy.sh',
          find: "grep -q '\"ok\":true'",
          note: 'Adım 12 — dağıtım: yayın sonrası /health "ok":true içermezse betik otomatik geri alma yapar.',
        },
      ],
      causes: [
        'Adım 1: süreç sık yeniden başlıyor (zamanlayıcı yalnızca açılışta + 24 saatte bir); "[Bakim] Temizlik hatasi:" günlükte',
        'Adım 2-4: DB yetkisi/bağlantı hatası nedeniyle temizlik başarısız (success:false, "Veritabanı temizliği başarısız oldu."); son temizlik tarihi eski kalır',
        'Adım 7: hesap süper kullanıcı değil (403) ya da oturum geçersiz (401)',
        'Adım 10: PostgreSQL erişilemiyor / bağlantı havuzu dolu (500 ok:false)',
        'Adım 11: MQTT_HOST/USER/PASSWORD eksik (mqtt_not_configured), broker kapalı (mqtt_offline); /health yine de ok:true olabilir',
        'Kayıtların "silinmemesi" çoğu zaman bilinçli sınırdır: hesaplar ve üyelikler hiç silinmez, günlükler 30 gün saklanır',
      ],
      checks: [
        'Sunucuda canlı sağlık: curl http://127.0.0.1:8080/health -> ok, database, mqtt.connected, mqtt.last_error',
        'Günlükte "[Maintenance Cleanup]" (başarı) ya da "[Bakim] Temizlik hatasi:" / "[Maintenance Cleanup] Hata:" satırını arayın',
        'Son temizlik: SELECT executed_at FROM app_maintenance_runs WHERE maintenance_key = \'routine_cleanup\';',
        'Silinebilir kayıt var mı: SELECT COUNT(*) FROM door_access_logs WHERE opened_at < NOW() - INTERVAL \'30 days\';',
        'Sağlık penceresi açılmıyorsa günlükte "[API] GET /admin/maintenance/health -> <durum>" satırına bakın (401/403 yetki, 500 errorId)',
        'Elle temizlik yalnızca süper kullanıcıdan uygulamadaki "Temizle" düğmesiyle yapılır; sunucuda elle DELETE yazmayın',
      ],
      logs: ['[Maintenance Cleanup]', '[Bakim] Temizlik hatasi:', 'Veritabani saglik bilgisi alinamadi.', 'database_maintenance_cleanup_requested'],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"',
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'Maintenance Cleanup\\|Bakim\'"',
      ],
      tests: ['server/test/members_maintenance.test.js'],
      related: ['akis-kayit-eposta-dogrulama', 'akis-cihaz-baglanti-gunlukleri'],
    },

    // ------------------------------------------------------------------------------------------------
    // 9) Cihaz durumu -> bağlantı günlükleri -> uygulama
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-cihaz-baglanti-gunlukleri',
      symptom: 'Cihaz bağlantı akışı bozuldu (uçtan uca): cihaz fiilen çevrimiçi ama uygulamada çevrimdışı görünüyor (ya da tersi) ya da "Bağlantı günlükleri" boş/eksik',
      keywords: ['çevrimiçi', 'çevrimdışı', 'offline', 'online', 'availability', 'LWT', 'bağlantı günlükleri', 'connectivity-logs', 'device_connectivity_logs', 'device_runtime_status', 'wifi kopma'],
      refs: [
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: 'const bool baglandi = client.connect(clientId.c_str(), mqttUser.c_str(), mqttPass.c_str(), deviceAvailabilityTopic.c_str(), 1, true, "offline");',
          note: 'Adım 1 — cihaz (MQTT bağlantısı): bağlanırken LWT (retained "offline") device/<UID>/availability konusuna kaydedilir. Bu satırdaki istemci kimliği/kullanıcı Mosquitto ACL ile uyuşmazsa cihaz hiç bağlanamaz. Sahadaki davranışı bozmayın (ESP32-C3).',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: 'mqttPublishAvailability("online");',
          note: 'Adım 2 — cihaz (MQTT yayını): bağlanınca retained "online" yayınlanır; OTA öncesi temiz kapanışta LWT tetiklenmediği için "offline" açıkça yayınlanır (mqttOtaOncesiKapat).',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "client.subscribe('device/+/availability', { qos: 1 });",
          note: 'Adım 3 — MQTT (köprü aboneliği): sunucu tüm cihazların availability konusuna abonedir; abonelik ya da köprü bağlantısı yoksa durum hiç güncellenmez.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "if (kind === 'availability') {",
          note: 'Adım 4 — sunucu (köprü): "online" ise online_since atanır ve yerel kontrol anahtarı eşitlenir; "online"dan "offline"a geçişte recordDeviceOfflineTransition çağrılır (yalnızca önceki durum online ise).',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'is_online = $2,',
          note: 'Adım 5 — veritabanı (durum): persistRuntimeStatus device_runtime_status\'a yazar ve devices.is_online / last_online_at / last_offline_at alanlarını günceller; yazma hatası "db_error" olarak /health\'te görünür.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'async function recordDeviceOfflineTransition(status, reason',
          note: 'Adım 6 — sunucu (günlük kuralı): çevrimiçi kalma süresi online_since ya da devices.last_online_at\'ten hesaplanır; yalnızca KOPMA (offline) için satır yazılır. Sunucu yeniden başladığında online_since bellekte olmadığından DB\'deki last_online_at kullanılır.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "INSERT INTO device_connectivity_logs (",
          note: 'Adım 7 — veritabanı (günlük): device_connectivity_logs satırı (event_type offline, süre, neden, Wi-Fi RSSI/yüzde, yerel IP). Hata yalnızca "Offline baglanti log DB kayit hatasi:" olarak günlüğe düşer.',
        },
        {
          file: 'server/src/services/device_service.js',
          find: 'export async function getDeviceConnectivityLogs({',
          note: 'Adım 8 — sunucu (servis): is_online değeri mqtt_connected öncelikli hesaplanır; toplam sayı + sayfalı günlük (en yeni önce, sayfa boyutu en çok 100) ve "şu an çevrimiçi süresi" döner.',
        },
        {
          file: 'server/src/routes/admin_routes.js',
          find: "adminRouter.get('/admin/devices/:deviceUid/connectivity-logs', authRequired, requireSuperUser",
          note: 'Adım 9 — sunucu (rota): yalnızca süper kullanıcı; UID 6 karakterden kısaysa 400, cihaz yoksa 404.',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "/connectivity-logs')",
          note: 'Adım 10 — uygulama (HTTP): GET /admin/devices/<UID>/connectivity-logs?page&page_size; yanıt DeviceConnectivityReport modeline çevrilir.',
        },
        {
          file: 'lib/ui/widgets/device_connectivity_logs_accordion.dart',
          find: 'await widget.authService.getDeviceConnectivityLogs(',
          note: 'Adım 11 — uygulama (ekran): şirket cihaz kartındaki akordeon açılınca günlük sayfalı yüklenir; hata mesajı ekranda gösterilir, yarış için istek sayacı kullanılır.',
        },
        {
          file: 'server/src/services/maintenance_service.js',
          find: 'DELETE FROM device_connectivity_logs',
          note: 'Adım 12 — bakım: 30 günden eski bağlantı günlükleri günlük temizlikte silinir (bkz. akis-bakim-temizlik-health).',
        },
      ],
      causes: [
        'Adım 1-2: cihaz MQTT\'ye bağlanamıyor (Wi-Fi yok, broker/TLS, kullanıcı/parola ya da ACL hatası); LWT süresi (keepalive) dolmadan kopma henüz görünmez',
        'Adım 3-4: sunucu köprüsü bağlı değil/abonelik düşmüş',
        'Adım 5: veritabanı yazma hatası (/health mqtt.last_error = db_error); cihaz daha önce is_online=true kalmış olabilir',
        'Adım 6-7: günlük yalnızca offline geçişinde yazılır; cihaz hiç "online"a düşmediyse ya da sunucu offline mesajını önceki durum bilinmeden aldıysa satır oluşmaz',
        'Adım 9-11: süper kullanıcı değil; cihaz UID yanlış; uygulama eski sürümle farklı yanıt bekliyor',
        'Günlüğün eski kayıtları 30 gün sonra bilinçli silinir (adım 12)',
      ],
      checks: [
        'Cihaz seri günlüğünde "MQTT baglaniyor (id=SmartKeyPass-..." ve "baglandi" ya da hata kodunu görün',
        'Köprü: GET /health -> mqtt.connected true mu, last_error ne',
        'Durum: SELECT mqtt_connected, last_seen_at, last_event FROM device_runtime_status WHERE device_uid = \'<UID>\'; SELECT is_online, last_online_at, last_offline_at FROM devices WHERE device_uid = \'<UID>\';',
        'Günlük: SELECT event_type, offline_at, duration_seconds, reason FROM device_connectivity_logs WHERE device_uid = \'<UID>\' ORDER BY created_at DESC LIMIT 10;',
        'Sunucu günlüğünde "Offline baglanti log DB kayit hatasi:" ve "[MQTT bridge] " satırlarını arayın',
        'Uygulamada boş liste ama DB doluysa günlükte "[API] GET /admin/devices/<UID>/connectivity-logs -> <durum>" satırına bakın',
      ],
      logs: ['Offline baglanti log DB kayit hatasi:', '[MQTT bridge] ', 'Device status DB yazilamadi:'],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"',
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'baglanti log\\|MQTT bridge\'"',
      ],
      tests: ['server/test/devices_device_service.test.js', 'server/test/doors_mqtt.test.js', 'server/test/devices_mqtt_acl.test.js'],
      related: ['akis-bulut-kapi-acma', 'akis-bakim-temizlik-health'],
    },

    // ------------------------------------------------------------------------------------------------
    // 10) Misafir geçişi (oluşturma -> herkese açık bağlantı -> açma)
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-misafir-gecis',
      symptom: 'Misafir/kurye geçişi akışı bozuldu (uçtan uca): geçiş bağlantısı oluşturulamıyor ya da misafir bağlantıyı açınca "iptal/süresi dolmuş/kullanılmış/cihaz bağlı değil" deyip kapı açılmıyor',
      keywords: ['misafir', 'kurye', 'geçiş linki', 'guest pass', 'guest_passes', '/guest/', 'GUEST_DISABLED', 'GUEST_PASS_OWNER_INACTIVE', 'GUEST_PASS_OWNER_NO_ACCESS', 'single_use', '410'],
      refs: [
        {
          file: 'lib/ui/dialogs/create_guest_pass_dialog.dart',
          find: 'await widget.authService.createGuestPass(',
          note: 'Adım 1 — uygulama (ekran): kapı, başlık, tür (tek kullanımlık / süreli), süre ve kullanım sayısı AuthService.createGuestPass\'a verilir; dönen web_url paylaşılır.',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "path: '/app/guest-passes',",
          nth: 1,
          note: 'Adım 2 — uygulama (HTTP): POST /app/guest-passes (201 beklenir). Aynı yola GET (liste) ve /app/guest-passes/:id için DELETE (iptal) çağrıları da aynı dosyadadır.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: "guestPassesRouter.post('/app/guest-passes', authRequired, async (req, res) => {",
          note: 'Adım 3 — sunucu (rota): giriş doğrulanır, normalizeGuestPassInput ile kapı/tür/süre doğrulanır (400); kapıya yetki yoksa 404; sitede misafir geçişi kapalıysa (feature_guest_pass_enabled=false) süper kullanıcı dahil 403 GUEST_DISABLED.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: 'INSERT INTO guest_passes (',
          note: 'Adım 4 — veritabanı: 48 karakterlik rastgele token, bitiş zamanı (şimdi + süre) ve max_uses ile guest_passes satırı yazılır; yanıttaki web_url PUBLIC_APP_URL / PUBLIC_BASE_URL (yoksa https://api.gudeteknoloji.com.tr) + /guest/<token> olarak kurulur.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: "guestPassesRouter.get('/guest/:token', async (req, res) => {",
          note: 'Adım 5 — sunucu (herkese açık sayfa): misafir bağlantıyı tarayıcıda açar; biçimi bozuk ya da kayıtsız token 404 "geçersiz" sayfası, aksi halde durumuna göre açma sayfası (nonce\'lu sıkı CSP) döner. Oturum gerekmez.',
        },
        {
          file: 'server/src/utils/guest_pass_utils.js',
          find: "var res = await fetch('/public/guest-pass/' + encodeURIComponent(token) + '/open', { method: 'POST' });",
          note: 'Adım 6 — tarayıcı (sayfa betiği): "Kapıyı aç" düğmesi POST /public/guest-pass/<token>/open çağırır; dönen JSON hata metni sayfada gösterilir.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: "guestPassesRouter.post('/public/guest-pass/:token/open', doorCommandRateLimiter",
          note: 'Adım 7 — sunucu (rota): doorCommandRateLimiter (429), token biçimi (400), geçiş + kapı + site + cihaz tek SQL ile okunur (yoksa 404); site bayrağı kapalıysa 403 GUEST_DISABLED; iptal/süre/tükenme için getGuestPassState -> 410; cihaz atanmamışsa 409.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: "code: 'GUEST_PASS_OWNER_INACTIVE',",
          note: 'Adım 8 — sunucu (oluşturan kontrolü): geçişi oluşturan kullanıcı hâlâ aktif/doğrulanmış/onaylı ve kapıya yetkili olmalı (403 GUEST_PASS_OWNER_INACTIVE / GUEST_PASS_OWNER_NO_ACCESS); üyelik kalkınca tüm linkleri ölür.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: "channel: 'guest',",
          note: 'Adım 9 — sunucu (politika): assertDoorOpenAllowed misafir kanalı kuralını uygular (403 GUEST_DISABLED ya da genel "Bu kapi icin misafir gecisi su anda kullanilamiyor.").',
        },
        {
          file: 'server/src/utils/guest_pass_utils.js',
          find: 'export const CLAIM_GUEST_PASS_SQL = `',
          note: 'Adım 10 — veritabanı (atomik hak tüketimi): tek UPDATE ile used_count artar; iptal/süre/limit koşulları UPDATE içindedir, 0 satır dönerse hak başka istekte tüketilmiştir (409 ya da 410). Pulse gönderilemezse RELEASE_GUEST_PASS_SQL hakkı iade eder.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: 'requestedBy: `guest:${Number(pass.id)}`,',
          note: 'Adım 11 — MQTT (yayın): publishDoorPulse device/<UID>/cmd konusuna pulse yayınlar (MQTT\'ye misafir başlığı gitmez, yalnız geçiş kimliği: guest:<id>); köprü/cihaz yoksa MQTT_BRIDGE_NOT_CONNECTED / DEVICE_OFFLINE -> 503 "Kapi cihazi su anda bagli degil." Cihaz tarafı için akis-bulut-kapi-acma Adım 10-11.',
        },
        {
          file: 'server/src/routes/guest_passes_routes.js',
          find: "triggerType: 'guest_pass',",
          note: 'Adım 12 — veritabanı (günlük): door_access_logs\'a "(Gecis Linki)" adıyla guest_pass satırı yazılır; yazma hatası "[guest_passes] acilis kaydi yazilamadi" olarak günlüğe düşer, misafire yine başarı döner.',
        },
      ],
      causes: [
        'Adım 3: sitede misafir geçişi kapalı (GUEST_DISABLED) ya da kullanıcının kapıya yetkisi yok',
        'Adım 4-5: PUBLIC_APP_URL/PUBLIC_BASE_URL yanlış (paylaşılan bağlantı ölü adrese gider); bağlantı eksik kopyalanmış (token biçimi bozuk -> 404)',
        'Adım 7: geçiş iptal edilmiş/süresi bitmiş/tek kullanımlık ise kullanılmış (410); hız sınırı (429)',
        'Adım 8: geçişi oluşturan kullanıcı pasife alınmış ya da kapıdan yetkisi alınmış',
        'Adım 10: iki istek aynı anda geldi (409 "baska bir istekle kullaniliyor"); max_uses doldu',
        'Adım 11: MQTT köprüsü bağlı değil ya da kapı cihazı çevrimdışı (503); hak iade edilir, tekrar denenebilir',
        'Adım 11 sonrası: komut gitti ama röle çekmedi (bkz. akis-bulut-kapi-acma Adım 10-11)',
      ],
      checks: [
        'Hata metnini ve durum kodunu not edin (410 = geçiş durumu, 403 = politika/oluşturan, 409 = cihaz atanmamış/yarış, 503 = cihaz bağlı değil)',
        'Geçiş satırı: SELECT id, door_id, is_active, expires_at, max_uses, used_count, created_by_user_code FROM guest_passes WHERE id = <id>; (token sütununu seçmeyin)',
        'Site bayrağı: SELECT feature_guest_pass_enabled FROM sites WHERE site_code = <site>;',
        'Oluşturan kullanıcı: SELECT is_active, email_verified, approval_status FROM users WHERE user_code = <kod>;',
        'Sunucu günlüğünde "[guest_passes] " satırları (errorId ile) ve "[API] POST /public/guest-pass/... -> <durum>" (token maskelenir)',
        'Cihaz durumunu akis-cihaz-baglanti-gunlukleri adımlarıyla doğrulayın; kapıyı süper kullanıcıyla uygulamadan açmayı deneyin',
      ],
      logs: ['[guest_passes] ', '[guest_passes] hak iadesi basarisiz', '[guest_passes] acilis kaydi yazilamadi', 'guest_pass_opened', 'guest_pass_created'],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'guest\'"',
      ],
      tests: ['server/test/sites_guest_pass.test.js', 'server/test/doors_policy.test.js'],
      related: ['akis-bulut-kapi-acma', 'akis-cihaz-baglanti-gunlukleri'],
    },

    // ------------------------------------------------------------------------------------------------
    // 11) Çevrimdışı kapı günlükleri (cihaz -> MQTT logs -> door_access_logs -> uygulama)
    // ------------------------------------------------------------------------------------------------
    {
      id: 'akis-cevrimdisi-kapi-gunlukleri',
      symptom: 'Çevrimdışı kapı günlüğü akışı bozuldu (uçtan uca): yerel/çevrimdışı yapılan kapı geçişleri uygulamadaki kapı günlüğünde görünmüyor, geç görünüyor ya da tekrarlanıyor',
      keywords: ['çevrimdışı günlük', 'offline log', 'kapı günlüğü', 'door_access_logs', 'logs_ack', 'batch_id', 'client_log_id', 'sync-logs', 'device/<UID>/logs', 'geçiş kaydı yok'],
      refs: [
        {
          file: 'cihaz_kontrol/include/offline_log.h',
          find: 'inline void offlineLogEkle(',
          note: 'Adım 1 — cihaz (kayıt): kapı geçişi LittleFS\'te /offline_logs.ndjson dosyasına satır olarak eklenir (client_log_id, epoch/boot_ms, trigger_type, ad, daire). Dosya 16 KB aşınca EN ESKİ kayıtlar atılır. Sahadaki biçimi bozmayın (ESP32-C3).',
        },
        {
          file: 'cihaz_kontrol/include/offline_log.h',
          find: 'inline const char* offlineLogTurSecimi(const char* tur) {',
          note: 'Adım 2 — cihaz (tür süzgeci): sunucunun izin listesi dışındaki trigger_type "offline_sync"e çevrilir; aksi halde sunucu kaydı reddeder ve ack ile düşer (veri kaybı). Yeni tür eklerken iki listeyi birlikte güncelleyin.',
        },
        {
          file: 'cihaz_kontrol/include/offline_log.h',
          find: 'inline void offlineLogSenkronizeEt() {',
          note: 'Adım 3 — cihaz (teslim): 3 sn aralıkla; Wi-Fi ve MQTT hazırsa dosya başından en çok ~800 baytlık batch hazırlanıp device/<UID>/logs konusuna QoS0 yayınlanır; ack gelmezse süre katlanarak (15 sn - 10 dk) aynı kayıtlar yeniden yayınlanır.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: "if (kind === 'logs') {",
          note: 'Adım 4 — MQTT (köprü): device/<UID>/logs mesajı handleDeviceLogsMessage\'a gider (abonelik ve ACL\'de logs yazma izni şarttır).',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'export async function handleDeviceLogsMessage(topicUid, text, deps = {}) {',
          note: 'Adım 5 — sunucu (köprü): JSON ayrıştırılır, aynı batch eşzamanlı işlenmez, insertDeviceLogBatch çağrılır; cihaz henüz siteye atanmamışsa (DEVICE_NOT_ASSIGNED) ack GÖNDERİLMEZ, cihaz kayıtları saklar; hata olursa da ack yoktur.',
        },
        {
          file: 'server/src/services/door_log_service.js',
          find: 'export function validateDeviceLogEntry(item, { now = Date.now() } = {}) {',
          note: 'Adım 6 — sunucu (doğrulama): her kayıt doğrulanır (izinli trigger_type, client_log_id deseni, zaman); geçersiz kayıt reddedilir ama batch yine ack\'lenir. Saati bilinmeyen kayıtların zamanı boot_ms farkıyla son 30 gün tabanına göre kestirilir.',
        },
        {
          file: 'server/src/services/door_log_service.js',
          find: 'export async function insertDeviceLogBatch({',
          note: 'Adım 7 — veritabanı: cihaz UID\'sinden site/kapı çözülür (DEVICE_NOT_FOUND / DEVICE_NOT_ASSIGNED); kayıtlar tek işlemde door_access_logs\'a idempotent yazılır (client_log_id benzersiz dizini; yoksa doğal anahtar); tekrar gelenler "duplicate" sayılır.',
        },
        {
          file: 'server/src/mqtt_bridge.js',
          find: 'function publishLogsAck(normalizedUid, batchId) {',
          note: 'Adım 8 — MQTT (sunucu -> cihaz): işlem başarılıysa device/<UID>/cmd konusuna {action:"logs_ack", batch_id} yayınlanır; yayın hatası "[MQTT Logs] logs_ack yayinlanamadi" yazar.',
        },
        {
          file: 'cihaz_kontrol/include/mqtt_baglanti.h',
          find: '} else if (action == "logs_ack") {',
          note: 'Adım 9 — cihaz (ack): offlineLogAckIsle batch kimliği bekleyenle eşleşirse o satırları dosyadan siler ve sıradaki batch\'i hemen yollar; eşleşmezse (dosya sıkıştırıldı, MQTT yeniden bağlandı) silmez, kayıtlar tekrar gönderilir.',
        },
        {
          file: 'server/src/routes/door_log_routes.js',
          find: "doorLogRouter.post('/device/sync-logs', authRequired, syncDeviceLogsHandler);",
          note: 'Adım 10 — sunucu (alternatif yol): aynı kayıtlar HTTP ile de yüklenebilir (JWT; süper kullanıcı, site yöneticisi ya da kapıya erişen kullanıcı). İstek en çok 256 KB / 200 kayıt; 404 cihaz/site yok, 403 yetki yok. Uygulamada AuthService.syncDeviceLogs bulunur, ancak arayüzde çağıranı görülmedi.',
        },
        {
          file: 'server/src/routes/door_log_routes.js',
          find: "doorLogRouter.get('/manager/door-logs', authRequired, requireSiteManager",
          note: 'Adım 11 — sunucu (okuma): yönetici günlüğü (site kapsamlı); süper kullanıcı için /admin/door-logs aynı dosyadadır; sayfa boyutu en çok 200, opened_at azalan sıra.',
        },
        {
          file: 'lib/ui/widgets/door_logs_accordion.dart',
          find: 'await service.listDoorAccessLogs(',
          note: 'Adım 12 — uygulama (ekran): kapı günlüğü akordeonu açılınca ya da kapı açıldığında sayfa yüklenir; kayıtlar door_access_logs satırlarının modelidir. Çevrimdışı kayıtlar cihaz geri bağlanıp batch ack\'lenince görünür.',
        },
      ],
      causes: [
        'Adım 1: cihaz LittleFS başlatılamadı (gOfflineLogFsHazir=false) ya da dosya dolup en eski kayıtlar atıldı',
        'Adım 3-4: cihaz Wi-Fi/MQTT\'ye bağlanamıyor (kayıtlar cihazda bekler); ACL\'de logs yazma izni yok',
        'Adım 5: cihaz henüz bir siteye/kapıya atanmamış (ack yok; atanınca kayıtlar işlenir); köprü bağlı değil',
        'Adım 6: trigger_type izin listesinde değil ya da client_log_id deseni bozuk (kayıt reddedilir)',
        'Adım 7: kayıt "duplicate" sayıldı (aynı client_log_id daha önce yazılmış) ya da DB hatası (ack yok, cihaz yeniden dener)',
        'Adım 9: ack cihaza ulaşmadı (QoS/bağlantı) -> aynı kayıtlar yeniden gönderilir, idempotent olduğundan çift satır oluşmaz',
        'Adım 12: kayıt 30 günden eski (bakım temizliği siler) ya da uygulamada yanlış site/kapı filtresi seçili',
      ],
      checks: [
        'Cihaz seri günlüğü: "Offline Log: kapi gecisi kaydedildi.", "Offline Log: batch yayinlandi, ack bekleniyor", "Offline Log: batch sunucu tarafindan onaylandi"',
        'Sunucu günlüğü: "[MQTT Logs] Cihaz <UID> batch=<n>: eklenen=.. tekrar=.. reddedilen=.." satırı hangi adımda durduğunu söyler',
        'Atama yoksa "henuz bir siteye atanmamis" uyarısını arayın; cihazı kapıya atayın (akis-cihaz-baglanti-gunlukleri ile bağlantıyı doğrulayın)',
        'DB: SELECT opened_at, trigger_type, user_name, door_name FROM door_access_logs WHERE device_uid = \'<UID>\' ORDER BY opened_at DESC LIMIT 20;',
        'Reddedilen sayısı yüksekse trigger_type değerlerini ve cihaz saatini (epoch=0 / boot_ms) inceleyin',
        'Uygulamada görünmüyor ama DB dolu ise "[API] GET /manager/door-logs -> <durum>" (ya da /admin/door-logs) ve seçili site/kapı filtresine bakın',
      ],
      logs: [
        'Offline Log: kapi gecisi kaydedildi.',
        'Offline Log: batch yayinlandi, ack bekleniyor (satir=',
        'Offline Log: batch sunucu tarafindan onaylandi, yerel kayitlar silindi.',
        '[MQTT Logs] Cihaz ',
        '[MQTT Logs] logs_ack yayinlanamadi',
        'Error syncing device offline logs',
      ],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a \'MQTT Logs\'"',
      ],
      tests: ['server/test/fix_sx1_bridge_logs.test.js', 'server/test/devices_door_log_service.test.js', 'server/test/devices_sync_logs_route.test.js', 'cihaz_kontrol/host_test/t_core.cpp'],
      related: ['akis-yerel-kapi-acma', 'akis-cihaz-baglanti-gunlukleri'],
    },

    // --- AKIŞLAR SONU (yeni akışlar bu satırın üstüne eklenir) ---
  ],
};
