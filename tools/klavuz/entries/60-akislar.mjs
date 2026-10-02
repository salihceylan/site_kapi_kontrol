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
          find: '_session = await api.login(email: email, password: password, role: role);',
          note: 'Adım 2 — uygulama (servis): ApiException mesajı kullanıcıya döner; ağ hatasında "Sunucuya baglanilamadi."; başarıda oturum _session\'a yazılır ve kalıcılaştırılır.',
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
          find: 'const lockState = loginFailureTracker.check(identifier);',
          note: 'Adım 5 — sunucu (ara kural): hesap bazlı ardışık hata sayacı (login_throttle.js: 5 hata -> 15 dk); kilitliyse 429 + code LOGIN_LOCKED + Retry-After. Sayaç süreç belleğindedir; PM2 yeniden başlatması sıfırlar.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'WHERE LOWER(email) = LOWER($1) OR LOWER(login_name) = LOWER($1)',
          note: 'Adım 6 — veritabanı: users satırı e-posta VEYA login_name ile aranır. Satır yoksa bekleyen kayıt (pending_registrations) parolası da denenir; doğruysa 403 "E-posta adresiniz dogrulanmadi." döner.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'const isPasswordMatch = await bcrypt.compare(',
          note: 'Adım 7 — sunucu (parola): kullanıcı bulunmasa da tek bcrypt karşılaştırması yapılır (zaman ölçümüyle hesap taraması engellenir). Uyuşmazsa recordFailure + 401 "Giris bilgileri hatali."',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'if (!row.email_verified) {',
          note: 'Adım 8 — sunucu (durum kapıları): sırayla seçilen rol uyuşmazlığı (403), e-posta doğrulanmadı (403), abonelik onay bekliyor/reddedildi (403), hesap aktif değil (403). Parola doğru olsa bile token bu kapılardan geçmeden verilmez.',
        },
        {
          file: 'server/src/routes/auth_routes.js',
          find: 'const token = signAccessToken(user, { passwordHash: row.password_hash });',
          note: 'Adım 9 — sunucu (JWT): jwt.js signAccessToken HS256 ile sub/email/role + pv (parola sürümü) imzalar; ömür JWT_EXPIRES_IN (varsayılan 30d). JWT_SECRET yoksa/kısaysa token üretimi hata verir (500).',
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
        'Adım 4-5: hız sınırı (429) ya da 5 hatalı denemeden sonra hesap kilidi (LOGIN_LOCKED, 15 dk); PM2 yeniden başlatması kilidi sıfırlar',
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
        '429 + LOGIN_LOCKED ise 15 dk bekleyin ya da şifre sıfırlama (akis-sifre-sifirlama) kilidi açar',
        'Oturum açıkken sonradan çıkış oluyorsa 401 yanıtındaki code alanına bakın: TOKEN_REVOKED = parola değişmiş, yoksa JWT süresi bitmiş',
        'Sunucu açılışında "[ENV] HATA" ya da "[JWT]" uyarısı var mı: pm2 logs içinde arayın',
      ],
      logs: ['[login] hata (errorId=', '[ENV] HATA:', '[API] '],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a \'/auth/login\'"',
        'ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"',
      ],
      tests: [
        'server/test/core_auth_routes.test.js',
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
          note: 'Adım 8 — uygulama (ekran): kullanıcı 6 haneli kodu girer; AuthService.verifyIndividualCode çağrılır. 404 gelirse ekran "Kod 30 dakika geçerlidir; yeni kod için Kodu Tekrar Gönder" ipucunu ekler.',
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
        'Adım 11: bekleyen kayıt 2 günden eskiydi ve bakım servisince silindi (404 "Bekleyen kayit bulunamadi"); aynı e-postayla araya hesap girdi (409)',
        'Adım 4: e-posta zaten doğrulanmış hesapta (409) ya da başka rolde bekleyen hesap',
      ],
      checks: [
        'İstek günlükte var mı: "[API] POST /auth/register-individual -> <durum>"; 201 ise kod satırı yazılmıştır, 503 ise gönderim başarısızdır',
        'Mail hatasını görün: pm2 logs içinde "[Mail Gönderim Hatası]" satırındaki code (ETIMEDOUT/EAUTH/ECONNECTION) ve responseCode (535/550) alanları',
        'Başlangıçta "SMTP ayarlari eksik" uyarısı var mı (env eksikliği: SMTP_HOST, SMTP_USER, SMTP_PASSWORD, SMTP_FROM)',
        'Veritabanında bekleyen kayıt ve kodlar: SELECT email, updated_at FROM pending_registrations WHERE LOWER(email) = LOWER(\'<e-posta>\'); SELECT id, attempt_count, is_verified, created_at FROM email_verifications WHERE LOWER(email) = LOWER(\'<e-posta>\') ORDER BY id DESC LIMIT 5;',
        'Giriş denemesinde "dogrulanmadi" 403 geliyorsa bekleyen kayıt vardır: kod girilince hesap açılır; yeni kod için Kodu Tekrar Gönder (/auth/resend-code, yanıt hesabı belli etmez)',
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

    // --- AKIŞLAR SONU (yeni akışlar bu satırın üstüne eklenir) ---
  ],
};
