# Uçtan uca akış haritaları (uygulama -> sunucu -> veritabanı -> MQTT -> cihaz)

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm bir özellik bozulduğunda zinciri BAŞTAN SONA izlemek içindir. Her giriş bir akıştır; tablodaki satırlar Adım 1, 2, 3... sırasındadır ve her satırın notu "Adım N — katman: ne olur" ile başlar. Katmanlar: uygulama (Flutter: lib/ui -> lib/services), sunucu (Express: routes -> services -> db.js), MQTT (server/src/mqtt_bridge.js <-> Mosquitto), cihaz (ESP32: cihaz_kontrol/include|src). Nasıl okunur: (1) belirtiyi anlatan akışı seçin ("... akışı bozuldu"); (2) adımları sırayla açın ve "Adım N"de beklenen şeyin gerçekten olduğunu doğrulayın (günlük, SQL, seri port); (3) ilk gerçekleşmeyen adım arıza halkasıdır; "Olası nedenler" o halka için ipuçlarını, "Adım adım kontrol" bakış sırasını verir. Sunucu günlükleri her istek için "[API] YÖNTEM yol -> durum (süre)" satırı yazar (token/kod değerleri maskelenir); tek bir kapı komutunun cihaza ulaşıp ulaşmadığı yalnızca cihaz seri günlüğünden ve MQTT olaylarından (pulse_started, pulse_rejected) anlaşılır. Akışlar kodda gerçekten bulunan halkaları gösterir; olmayan halka eklenmemiştir. Ayrıntılı tek-belirti girişleri için ilgili diğer alan bölümlerine bakın.

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [lib/services/auth_api.dart](../../lib/services/auth_api.dart) | Uygulamanın TÜM HTTP çağrıları (yol + durum kodu eşlemesi + zaman aşımı) |
| [lib/services/auth_service.dart](../../lib/services/auth_service.dart) | Oturum, kapı açma kararı (yerel -> bulut), önbellekler, hata -> oturum sonu eşlemesi |
| [lib/services/local_door_service.dart](../../lib/services/local_door_service.dart) | Yerel UDP: beacon dinleme, challenge, HMAC imzası, doğrudan UDP açma |
| [server/src/routes/auth_routes.js](../../server/src/routes/auth_routes.js) | Giriş / kayıt / doğrulama / şifre sıfırlama uçları |
| [server/src/routes/app_doors_routes.js](../../server/src/routes/app_doors_routes.js) | Kapı listesi, durum, bulut açma, karekod ile açma, yerel açma bildirimi, QR token |
| [server/src/services/door_service.js](../../server/src/services/door_service.js) | Erişilebilir kapılar SQL'i, kapı geçiş günlüğü, yerel kontrol anahtarı dağıtımı |
| [server/src/services/door_access_policy.js](../../server/src/services/door_access_policy.js) | Kanal politikası (remote/qr/guest/local) ve ekran karekod tokenı kuralları |
| [server/src/services/geofence_service.js](../../server/src/services/geofence_service.js) | Konum (geofence) doğrulaması |
| [server/src/services/qr_access_service.js](../../server/src/services/qr_access_service.js) | Dinamik QR token üretimi ve cihazdan gelen QR doğrulaması |
| [server/src/services/membership_service.js](../../server/src/services/membership_service.js) | Kayıt/doğrulama, cihaz sahiplenme, site kurulumu, katılım başvurusu |
| [server/src/mqtt_bridge.js](../../server/src/mqtt_bridge.js) | Mosquitto köprüsü: abonelikler, durum/olay/günlük işleme, cmd/qr_result yayınları |
| [server/src/mqtt_acl_sync.js](../../server/src/mqtt_acl_sync.js) | Mosquitto ACL metni (cihaz başına konu izinleri) ve senkron komutu |
| [cihaz_kontrol/include/mqtt_baglanti.h](../../cihaz_kontrol/include/mqtt_baglanti.h) | Cihaz MQTT: bağlantı, abonelik, cmd/qr_result işleyicileri, durum/olay yayını |
| [cihaz_kontrol/include/role_kontrol.h](../../cihaz_kontrol/include/role_kontrol.h) | Röle tetikleme (debounce, esp_timer ile bırakma) |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h](../../cihaz_kontrol/include/yerel_kapi_kontrol.h) | Cihaz yerel UDP/HTTP: beacon, challenge, imzalı açma |
| [cihaz_kontrol/include/wifi_baglanti.h](../../cihaz_kontrol/include/wifi_baglanti.h) | Wi-Fi, BLE kurulum servisi, NVS kimlik bilgileri |
| [cihaz_kontrol/include/ota_guncelleme.h](../../cihaz_kontrol/include/ota_guncelleme.h) | Cihaz OTA: manifest, indirme, doğrulama, geri dönüş |
| [cihaz_kontrol/include/offline_log.h](../../cihaz_kontrol/include/offline_log.h) | Cihazın çevrimdışı kapı geçiş kayıtları ve MQTT ile senkronu |
| [server/src/routes/public_guest_routes.js](../../server/src/routes/public_guest_routes.js) | guest_passes_routes.js yönlendiricisinin yeniden dışa aktarımı (misafir akışı: akis-misafir-gecis) |
| [docs/EPOSTA_DOGRULAMA.md](../../docs/EPOSTA_DOGRULAMA.md) | Bekleyen kayıt modeli, parametreler, "kod gelmiyor" teşhisi |
| [docs/YEREL_KONTROL_V2.md](../../docs/YEREL_KONTROL_V2.md) | Yerel kontrol protokolü v2 (challenge + HMAC) sözleşmesi |
| [deploy/README.md](../../deploy/README.md) | Canlı dağıtım, PM2 ve geri alma adımları |

## Bu bölümdeki girişler (11)

- [akis-giris-oturum-jwt](#akis-giris-oturum-jwt) — Giriş akışı bozuldu (uçtan uca): uygulamada giriş yapılamıyor ya da oturum beklenmedik biçimde kapanıyor
- [akis-kayit-eposta-dogrulama](#akis-kayit-eposta-dogrulama) — Kayıt + e-posta doğrulama akışı bozuldu (uçtan uca): kod gelmiyor, geç geliyor, "kod hatalı/süresi dolmuş" ya da hesap açılmıyor
- [akis-sifre-sifirlama](#akis-sifre-sifirlama) — Şifre sıfırlama akışı bozuldu (uçtan uca): bağlantı e-postası gelmiyor, bağlantı "geçersiz/süresi dolmuş" diyor ya da yeni parola kaydedilmiyor
- [akis-bulut-kapi-acma](#akis-bulut-kapi-acma) — Bulut kapı açma akışı bozuldu (uçtan uca): uygulamada "Kapıyı aç" denince kapı açılmıyor, hata gösteriyor ya da komut gidiyor ama röle çekmiyor
- [akis-dinamik-qr-gm60](#akis-dinamik-qr-gm60) — Dinamik QR ile kapı açma akışı bozuldu (uçtan uca): telefondaki QR'ı cihaz kamerası (GM60) okuyor ama kapı açılmıyor / "geçersiz, kullanılmış, süresi dolmuş" deniyor
- [akis-ekran-qr-uygulama-okutma](#akis-ekran-qr-uygulama-okutma) — Karekod okutarak kapı açma akışı bozuldu (uçtan uca): uygulamayla cihaz ekranındaki karekodu okutunca kapı açılmıyor / "karekod süresi dolmuş" / "karekod henüz alınamadı"
- [akis-yerel-kapi-acma](#akis-yerel-kapi-acma) — Yerel kapı açma akışı bozuldu (uçtan uca): telefon cihazla aynı Wi-Fi'de ama kapı yerel ağdan açılmıyor, hep buluta düşüyor
- [akis-bakim-temizlik-health](#akis-bakim-temizlik-health) — Bakım/temizlik ve sağlık akışı bozuldu (uçtan uca): eski kayıtlar silinmiyor, süper kullanıcı "Veritabanı Sağlığı" penceresi hata veriyor ya da /health "ok:false" dönüyor
- [akis-cihaz-baglanti-gunlukleri](#akis-cihaz-baglanti-gunlukleri) — Cihaz bağlantı akışı bozuldu (uçtan uca): cihaz fiilen çevrimiçi ama uygulamada çevrimdışı görünüyor (ya da tersi) ya da "Bağlantı günlükleri" boş/eksik
- [akis-misafir-gecis](#akis-misafir-gecis) — Misafir/kurye geçişi akışı bozuldu (uçtan uca): geçiş bağlantısı oluşturulamıyor ya da misafir bağlantıyı açınca "iptal/süresi dolmuş/kullanılmış/cihaz bağlı değil" deyip kapı açılmıyor
- [akis-cevrimdisi-kapi-gunlukleri](#akis-cevrimdisi-kapi-gunlukleri) — Çevrimdışı kapı günlüğü akışı bozuldu (uçtan uca): yerel/çevrimdışı yapılan kapı geçişleri uygulamadaki kapı günlüğünde görünmüyor, geç görünüyor ya da tekrarlanıyor

## Girişler

<a id="akis-giris-oturum-jwt"></a>
### akis-giris-oturum-jwt · Giriş akışı bozuldu (uçtan uca): uygulamada giriş yapılamıyor ya da oturum beklenmedik biçimde kapanıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/login_page.dart:123](../../lib/ui/pages/login_page.dart#L123) | <code>final errorMessage = await widget.authService.login(</code> | Adım 1 — uygulama (ekran): Giriş düğmesi e-posta/kullanıcı adı + parolayı AuthService.login çağrısına verir; dönen hata metni AppSnack ile gösterilir (kilit, doğrulanmadı, onay bekliyor mesajları buradan okunur). |
| [lib/services/auth_service.dart:288](../../lib/services/auth_service.dart#L288) | <code>_session = await api.login(</code> | Adım 2 — uygulama (servis): önceki girişte verilen güvenilir cihaz belirteci (varsa) gönderilir, yanıtta yenisi gelirse saklanır; ApiException mesajı kullanıcıya döner; ağ hatasında "Sunucuya baglanilamadi."; başarıda oturum _session'a yazılır ve kalıcılaştırılır. |
| [lib/services/auth_api.dart:105](../../lib/services/auth_api.dart#L105) | <code>path: '/auth/login',</code> | Adım 3 — uygulama (HTTP): POST {baseUrl}/auth/login (baseUrl lib/config/app_config.dart içinde; varsayılan https://api.gudeteknoloji.com.tr, --dart-define=API_BASE_URL ile değişir). 200 beklenir; 401/403 bu uçta oturum sonu sayılmaz, sunucu mesajı gösterilir. |
| [server/src/routes/auth_routes.js:765](../../server/src/routes/auth_routes.js#L765) | <code>authRouter.post('/auth/login', loginRateLimiter, async (req, res) =&gt; {</code> | Adım 4 — sunucu (rota): önce IP + IP/kimlik bazlı hız sınırı (429 "Cok fazla giris denemesi"), sonra gövde doğrulaması (email/login/identifier + password zorunlu, 400). |
| [server/src/routes/auth_routes.js:833](../../server/src/routes/auth_routes.js#L833) | <code>const reservation = loginGuard.reserve(attempt);</code> | Adım 5 — sunucu (giriş kilidi, security/login_guard.js): üç katman (hesap × kaynak 5 hata / 15 dk, hesap geneli 20 / 60 dk, IP geneli 30 / 15 dk; ilk kilit 15 dk, tekrarında uzar); hata hakkı bcrypt'ten ÖNCE ayrılır; kilitliyse 429 + code LOGIN_LOCKED + Retry-After. Hesapla eşleşen güvenilir cihaz belirteci hesap ve IP geneli kilitten muaftır. Sayaç süreç belleğindedir; PM2 yeniden başlatması sıfırlar. |
| [server/src/routes/auth_routes.js:804](../../server/src/routes/auth_routes.js#L804) | <code>WHERE LOWER(email) = LOWER($1) OR LOWER(login_name) = LOWER($1)</code> | Adım 6 — veritabanı: users satırı e-posta VEYA login_name ile aranır. Satır yoksa bekleyen kayıt (pending_registrations) parolası da denenir; doğruysa 403 "E-posta adresiniz dogrulanmadi." döner. |
| [server/src/routes/auth_routes.js:855](../../server/src/routes/auth_routes.js#L855) | <code>const compared = await bcrypt.compare(candidate, usableHash ? storedHash : await getDummy…</code> | Adım 7 — sunucu (parola): kullanıcı bulunmasa ya da saklı özet kullanılamaz olsa da tek bcrypt karşılaştırması yapılır (zaman ölçümüyle hesap taraması engellenir). Uyuşmazsa commitFailure + 401 "Giris bilgileri hatali." (eşik dolduysa 429 LOGIN_LOCKED). |
| [server/src/routes/auth_routes.js:879](../../server/src/routes/auth_routes.js#L879) | <code>if (!row.email_verified) {</code> | Adım 8 — sunucu (durum kapıları): sırayla seçilen rol uyuşmazlığı (403), e-posta doğrulanmadı (403), abonelik onay bekliyor/reddedildi (403), hesap aktif değil (403). Parola doğru olsa bile token bu kapılardan geçmeden verilmez. |
| [server/src/routes/auth_routes.js:894](../../server/src/routes/auth_routes.js#L894) | <code>const token = signAccessToken(user, { passwordHash: row.password_hash });</code> | Adım 9 — sunucu (JWT): jwt.js signAccessToken HS256 ile sub/email/role + pv (parola sürümü) imzalar; ömür JWT_EXPIRES_IN (varsayılan 30d). JWT_SECRET yoksa/kısaysa token üretimi hata verir (500). Yanıta güvenilir cihaz belirteci (device_token) de eklenir. |
| [lib/services/auth_service.dart:3605](../../lib/services/auth_service.dart#L3605) | <code>final raw = jsonEncode(_session!.toJson());</code> | Adım 10 — uygulama (güvenli depo): oturum flutter_secure_storage içinde "auth_session" anahtarına yazılır; yazma hatası sessizce yutulur (oturum yalnızca bellekte kalır, uygulama yeniden açılınca giriş istenir). |
| [server/src/middlewares/auth_middleware.js:43](../../server/src/middlewares/auth_middleware.js#L43) | <code>claims = verifyAccessToken(token);</code> | Adım 11 — sunucu (sonraki her istek): authRequired Bearer token'ı doğrular (imza/süre -> 401 "Gecersiz veya suresi dolmus token."), sonra rol/aktiflik/onay DB'den TAZE okunur; token'daki rol kullanılmaz. |
| [server/src/middlewares/auth_middleware.js:116](../../server/src/middlewares/auth_middleware.js#L116) | <code>if (!isPasswordVersionValid(claims, passwordHash)) {</code> | Adım 12 — sunucu (oturum iptali): parola değişince pv uyuşmaz -> 401 code TOKEN_REVOKED; uygulama _handleSessionError ile oturumu kapatır ve giriş ekranında bir kez açıklama gösterir (takeSessionNotice). |

**Olası nedenler**
- Adım 4-5: hız sınırı (429) ya da hatalı deneme kilidi (LOGIN_LOCKED: aynı hesap ve kaynaktan 5 hata; ilk kilit 15 dk, tekrarında daha uzun); PM2 yeniden başlatması kilidi sıfırlar
- Adım 6-7: parola yanlış, kullanıcı adı/e-posta farklı yazılmış ya da hesap hiç yok (aynı 401 döner: hesap varlığı ayırt edilmez)
- Adım 8: hesap pasif, e-posta doğrulanmamış, abonelik onay bekliyor/reddedildi; rol seçimi uyuşmuyor
- Adım 9: sunucuda JWT_SECRET eksik/geçersiz (500 "Giris islemi basarisiz." + errorId)
- Adım 3: baseUrl yanlış derlenmiş uygulama (API_BASE_URL) ya da araya giren proxy/captive portal (JSON olmayan 401/403 oturum sonu sayılmaz)
- Adım 11-12: JWT süresi dolmuş (30 gün) ya da parola başka cihazdan değişmiş (TOKEN_REVOKED); hesap sonradan pasife alınmış

**Adım adım kontrol**
- Ekrandaki mesajı not edin; tam metni docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md içinde aratıp hangi adımdan geldiğini belirleyin
- Sunucu günlüğünde isteği bulun: "[API] POST /auth/login -> <durum>" (401: parola/kimlik, 403: durum kapıları, 429: hız/kilit, 500: errorId ile ayrıntı)
- Kullanıcı satırını salt-okunur sorguyla görün (parola özeti seçilmez): SELECT user_code, role, is_active, email_verified, approval_status FROM users WHERE LOWER(email) = LOWER('<e-posta>');
- 403 ise yanıttaki Türkçe metne göre Adım 8'deki kapıyı bulun; "dogrulanmadi" ise akis-kayit-eposta-dogrulama akışına geçin
- 429 + LOGIN_LOCKED ise yanıttaki retry_after_seconds kadar bekleyin (ilk kilit 15 dk) ya da şifre sıfırlama (akis-sifre-sifirlama) hesap kilidini açar
- Oturum açıkken sonradan çıkış oluyorsa 401 yanıtına bakın: code TOKEN_REVOKED = parola değişmiş; "Gecersiz veya suresi dolmus token." = süre bitmiş ya da imza geçersiz (JWT_SECRET değişmiş); "Kullanici bulunamadi." = kullanıcı silinmiş (uygulama her 401'de oturumu kapatır)
- Sunucu açılışında "[ENV] HATA" ya da "[JWT]" uyarısı var mı: pm2 logs içinde arayın

**Günlükte aranacak ifadeler**
- `[login] hata (errorId=`
- `[ENV] HATA:`
- `[API] `

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a '/auth/login'"
ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"
```

**İlgili testler:** [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js), [server/test/security_login_guard.test.js](../../server/test/security_login_guard.test.js), [server/test/core_jwt.test.js](../../server/test/core_jwt.test.js), [server/test/core_auth_middleware.test.js](../../server/test/core_auth_middleware.test.js), [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart)

**Bkz.:** [akis-sifre-sifirlama](#akis-sifre-sifirlama), [akis-kayit-eposta-dogrulama](#akis-kayit-eposta-dogrulama)

<a id="akis-kayit-eposta-dogrulama"></a>
### akis-kayit-eposta-dogrulama · Kayıt + e-posta doğrulama akışı bozuldu (uçtan uca): kod gelmiyor, geç geliyor, "kod hatalı/süresi dolmuş" ya da hesap açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/register_individual_page.dart:91](../../lib/ui/pages/register_individual_page.dart#L91) | <code>final error = await widget.authService.registerIndividual(</code> | Adım 1 — uygulama (ekran): Ad/soyad/e-posta/parola AuthService.registerIndividual'a gider; başarıda VerifyEmailCodePage açılır (30 sn tekrar-gönder bekleme sayacı ve 30 dk geçerlilik metni orada). |
| [lib/services/auth_api.dart:128](../../lib/services/auth_api.dart#L128) | <code>final uri = Uri.parse('$baseUrl/auth/register-individual');</code> | Adım 2 — uygulama (HTTP): POST /auth/register-individual, 201 beklenir; 409/429/503 sunucu mesajıyla kullanıcıya gösterilir (AuthService.registerIndividual ApiException.message döndürür). |
| [server/src/routes/auth_routes.js:55](../../server/src/routes/auth_routes.js#L55) | <code>authRouter.post('/auth/register-individual', registerLimiter, async (req, res) =&gt; {</code> | Adım 3 — sunucu (rota): registerLimiter (IP+e-posta 15 dk/5, IP saatlik 40) -> registerIndividualUser; kod e-postayla gönderilemediyse dürüst 503 EMAIL_DELIVERY_FAILED + Retry-After: 60. |
| [server/src/services/membership_service.js:261](../../server/src/services/membership_service.js#L261) | <code>export async function registerIndividualUser({</code> | Adım 4 — sunucu (iş kuralı): girdi doğrulanır; doğrulanmış hesap varsa 409; hesap yoksa users satırı AÇILMAZ, yalnızca ad + bcrypt parola özeti beklemeye alınır. Eski doğrulanmamış individual hesap UPDATE ile güncellenir. |
| [server/src/services/membership_service.js:177](../../server/src/services/membership_service.js#L177) | <code>async function issueVerificationCode({ email, fullName, persistCredentials }) {</code> | Adım 5 — veritabanı: e-posta başına advisory kilit + 30 sn bekleme + saatlik 10 kod tavanı (429), sonra 6 haneli kodun bcrypt özeti email_verifications tablosuna INSERT edilir. |
| [server/src/services/membership_service.js:216](../../server/src/services/membership_service.js#L216) | <code>await sendIndividualVerificationEmail({</code> | Adım 6 — sunucu -> SMTP: mailer.js nodemailer ile SMTP_HOST/SMTP_USER/SMTP_PASSWORD kullanır (bağlantı 10 sn, soket 20 sn zaman aşımı). Hata olursa kod satırı silinir, günlüğe "[Mail Gönderim Hatası]" düşer, istemciye 503 döner. |
| [server/src/services/membership_rules.js:139](../../server/src/services/membership_rules.js#L139) | <code>export const SQL_UPSERT_PENDING_REGISTRATION = `</code> | Adım 7 — veritabanı: ad + parola özeti pending_registrations tablosuna YALNIZCA e-posta gönderildikten sonra yazılır (e-posta başına tek satır; daha yeni açık kod varsa yazılmaz). |
| [lib/ui/pages/verify_email_code_page.dart:95](../../lib/ui/pages/verify_email_code_page.dart#L95) | <code>final error = await widget.authService.verifyIndividualCode(</code> | Adım 8 — uygulama (ekran): kullanıcı 6 haneli kodu girer; AuthService.verifyIndividualCode çağrılır ve dönen hata metni ekranda gösterilir (404 durumunda AuthService mesaja "Kod 30 dakika geçerlidir; yeni kod için Kodu Tekrar Gönder" ipucunu ekler). |
| [server/src/routes/auth_routes.js:92](../../server/src/routes/auth_routes.js#L92) | <code>authRouter.post('/auth/verify-code', verifyCodeLimiter, async (req, res) =&gt; {</code> | Adım 9 — sunucu (rota): verifyCodeLimiter (IP+e-posta 15 dk/10, e-posta başına 20) -> verifyIndividualEmailCode; yanıt 200 + token + user. |
| [server/src/services/membership_service.js:405](../../server/src/services/membership_service.js#L405) | <code>const claim = await client.query(SQL_CLAIM_VERIFICATION_ATTEMPT, [</code> | Adım 10 — veritabanı: deneme hakkı ATOMİK alınır (kod başına 5, 30 dk pencerede e-posta başına 10); hak alınamazsa aktif kod yok -> 404, kod/pencere deneme sınırı aşıldı -> 429; yanlış kod 400 "...kod hatalıdır" olur ve artan sayaç kalıcıdır. |
| [server/src/services/membership_service.js:471](../../server/src/services/membership_service.js#L471) | <code>INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, pa…</code> | Adım 11 — veritabanı (tek işlem): kod doğruysa hesap ANCAK ŞİMDİ açılır (role individual, email_verified TRUE), bekleyen kayıt silinir, bekleyen yönetici davetleri bağlanır; işlem sonunda signAccessToken ile JWT döner. Bekleyen kayıt yoksa 404. |
| [lib/services/auth_service.dart:543](../../lib/services/auth_service.dart#L543) | <code>_session = await api.verifyIndividualCode(</code> | Adım 12 — uygulama (oturum): yanıttaki token+user oturum olarak kaydedilir; kök rota (lib/app.dart) oturuma tepki verip HomePage'e döner; kayıt ve doğrulama sayfaları popUntil ile kapanır. |

**Olası nedenler**
- Adım 6: SMTP kimliği/portu yanlış, sağlayıcı sınırı ya da ağ (ETIMEDOUT, EAUTH, 535/550); kod hiç gönderilmemiştir ve istemci 503 almıştır
- Adım 6 sonrası: sunucu e-postayı kabul etti ama alıcıya geç ulaştı (kod 30 dk geçerlidir; birden fazla e-postada yalnızca EN SON kod geçerli)
- Adım 5: 30 sn bekleme ya da saatlik tavan (429); aynı e-postaya birden çok kayıt denemesi
- Adım 10: kod başına 5 / pencere başına 10 deneme aşıldı (429) ya da kod süresi doldu / yeni kod istendi (eski kod geçersiz)
- Adım 11: bekleyen kayıt 2 günden eskiydi ve bakım servisince silindi (404 "Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz."); aynı e-postayla araya hesap girdi (409)
- Adım 4: e-posta zaten doğrulanmış hesapta (409) ya da başka rolde bekleyen hesap

**Adım adım kontrol**
- İstek günlükte var mı: "[API] POST /auth/register-individual -> <durum>"; 201 ise kod satırı yazılmıştır, 503 ise gönderim başarısızdır
- Mail hatasını görün: pm2 logs içinde "[Mail Gönderim Hatası]" satırındaki code (ETIMEDOUT/EAUTH/ECONNECTION) ve responseCode (535/550) alanları
- Başlangıçta "SMTP ayarlari eksik" uyarısı var mı (env eksikliği: SMTP_HOST, SMTP_USER, SMTP_PASSWORD; SMTP_FROM yoksa SMTP_USER gönderen olur)
- Veritabanında bekleyen kayıt ve kodlar: SELECT email, updated_at FROM pending_registrations WHERE LOWER(email) = LOWER('<e-posta>'); SELECT id, attempt_count, is_verified, created_at FROM email_verifications WHERE LOWER(email) = LOWER('<e-posta>') ORDER BY id DESC LIMIT 5;
- Giriş denemesinde "dogrulanmadi" 403 geliyorsa bekleyen kayıt (ya da eski doğrulanmamış hesap) vardır: kod girilince hesap açılır/doğrulanır; yeni kod için Kodu Tekrar Gönder (/auth/resend-code, yanıt hesabı belli etmez)
- Kod geç geliyorsa docs/EPOSTA_DOGRULAMA.md "İşletim" bölümündeki SMTP/DNS/Received başlıkları teşhisini uygulayın

**Günlükte aranacak ifadeler**
- `[Mail Gönderim Hatası]`
- `[Doğrulama Kodu]`
- `[resend-code] gonderim basarisiz`
- `SMTP ayarlari eksik`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Mail G'"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a '/auth/verify-code'"
```

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/members_verification.test.js](../../server/test/members_verification.test.js), [server/test/mailer.test.js](../../server/test/mailer.test.js), [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart)

**Bkz.:** [akis-giris-oturum-jwt](#akis-giris-oturum-jwt), [akis-bakim-temizlik-health](#akis-bakim-temizlik-health)

<a id="akis-sifre-sifirlama"></a>
### akis-sifre-sifirlama · Şifre sıfırlama akışı bozuldu (uçtan uca): bağlantı e-postası gelmiyor, bağlantı "geçersiz/süresi dolmuş" diyor ya da yeni parola kaydedilmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/login_page.dart:278](../../lib/ui/pages/login_page.dart#L278) | <code>final error = await widget.authService.forgotPassword(</code> | Adım 1 — uygulama (ekran): "Şifremi Unuttum" penceresi e-postayı AuthService.forgotPassword'a verir; başarıda hesap varsa bağlantı gönderildi uyarısı gösterilir (hesap varlığı belli edilmez). |
| [lib/services/auth_api.dart:178](../../lib/services/auth_api.dart#L178) | <code>final uri = Uri.parse('$baseUrl/auth/forgot-password');</code> | Adım 2 — uygulama (HTTP): POST /auth/forgot-password, her zaman 200 beklenir; 429 (hız sınırı) mesajı pencerede gösterilir. |
| [server/src/routes/auth_routes.js:387](../../server/src/routes/auth_routes.js#L387) | <code>authRouter.post('/auth/forgot-password', forgotPasswordLimiter, async (req, res) =&gt; {</code> | Adım 3 — sunucu (rota): forgotPasswordLimiter (IP+e-posta 15 dk/3, e-posta saatlik 5); işlem arka planda yürür, yanıt hesap var/yok için AYNIDIR (200 ok:true). |
| [server/src/routes/auth_routes.js:405](../../server/src/routes/auth_routes.js#L405) | <code>if (userRes.rowCount === 0 &#124;&#124; !userRes.rows[0].is_active) {</code> | Adım 4 — veritabanı: users satırı e-postayla aranır; hesap yoksa ya da pasifse SESSİZCE çıkılır (e-posta gönderilmez, günlüğe bile düşmez). "Mail gelmiyor"un en sık nedeni budur. |
| [server/src/routes/auth_routes.js:360](../../server/src/routes/auth_routes.js#L360) | <code>SET password_reset_token_hash = $1,</code> | Adım 5 — veritabanı: 32 baytlık rastgele token üretilir, yalnızca SHA-256 özeti users.password_reset_token_hash + password_reset_expires_at (30 dk) olarak saklanır; ham token yalnızca e-postadaki bağlantıdadır. |
| [server/src/routes/auth_routes.js:375](../../server/src/routes/auth_routes.js#L375) | <code>const resetUrl = `${baseUrl}/auth/reset-password?token=${token}`;</code> | Adım 6 — sunucu: bağlantı PUBLIC_APP_URL / PUBLIC_BASE_URL (yoksa https://api.gudeteknoloji.com.tr) + /auth/reset-password?token=... ile kurulur; yanlış env bağlantıyı ölü adrese çevirir. |
| [server/src/mailer.js:376](../../server/src/mailer.js#L376) | <code>export async function sendPasswordResetEmail({</code> | Adım 7 — sunucu -> SMTP: şifre sıfırlama e-postası gönderilir; hata YALNIZCA günlüğe "[forgot-password] islem basarisiz" olarak yazılır, kullanıcıya yansımaz. |
| [server/src/routes/auth_routes.js:421](../../server/src/routes/auth_routes.js#L421) | <code>authRouter.get('/auth/reset-password', resetPasswordLimiter, async (req, res) =&gt; {</code> | Adım 8 — sunucu (tarayıcı): kullanıcı e-postadaki bağlantıyı açar; token biçimi (64 hex) -> 404, hash bulunamadı -> 404, süresi dolmuş -> 410, geçerliyse parola formu (sıkı CSP'li HTML) döner. |
| [server/src/routes/auth_routes.js:479](../../server/src/routes/auth_routes.js#L479) | <code>authRouter.post('/auth/reset-password', resetPasswordLimiter, async (req, res) =&gt; {</code> | Adım 9 — sunucu (rota): form POST ile yeni parola (6-128 karakter) gönderir; token yeniden doğrulanır (geçersiz/süresi dolmuş -> 400). |
| [server/src/routes/auth_routes.js:525](../../server/src/routes/auth_routes.js#L525) | <code>SET password_hash = $1,</code> | Adım 10 — veritabanı: parola özeti, token ve süre TEK atomik UPDATE ile yazılır/temizlenir (token tek kullanımlıktır; eşzamanlı iki istekten biri 0 satır alır -> 400). |
| [server/src/routes/auth_routes.js:544](../../server/src/routes/auth_routes.js#L544) | <code>clearAccountLocks({</code> | Adım 11 — sunucu: posta kutusuna erişim kanıtlandığı için hesap bazlı giriş/parola-değişim kilitleri (LOGIN_LOCKED) açılır; kullanıcı yeni parolayla beklemeden girer. |
| [server/src/middlewares/auth_middleware.js:116](../../server/src/middlewares/auth_middleware.js#L116) | <code>if (!isPasswordVersionValid(claims, passwordHash)) {</code> | Adım 12 — sunucu (eski oturumlar): parola özeti değiştiği için eski token'ların pv claim'i uyuşmaz; diğer cihazlardaki oturumlar 401 TOKEN_REVOKED ile kapanır. |

**Olası nedenler**
- Adım 4: e-posta kayıtlı değil / hesap pasif (sessizce çıkılır) ya da e-posta farklı yazılmış
- Adım 7: SMTP hatası (kullanıcı yine de "gönderildi" görür); alıcı tarafında spam klasörü
- Adım 6: PUBLIC_APP_URL/PUBLIC_BASE_URL yanlış, bağlantı doğru adrese gitmiyor
- Adım 8: bağlantı 30 dk geçti (410), daha önce kullanıldı ya da yeni talep eskisini ezdi (404)
- Adım 3: hız sınırı (15 dk içinde 3 istek, saatte 5) nedeniyle 429
- Adım 12: kullanıcı parolayı değiştirdikten sonra eski cihazda oturum kapanır (beklenen davranış)

**Adım adım kontrol**
- Günlükte isteği bulun: "[API] POST /auth/forgot-password -> 200" (maske nedeniyle token görünmez); 429 ise limiter
- Hesap var mı ve aktif mi: SELECT user_code, is_active, password_reset_expires_at FROM users WHERE LOWER(email) = LOWER('<e-posta>'); (özet alanını seçmeyin)
- Günlükte "[forgot-password] islem basarisiz" satırını arayın (SMTP/DB hatası burada tek satır olarak görünür; "[Mail Gönderim Hatası]" etiketi yalnız doğrulama kodu e-postası içindir)
- Bağlantıyı tarayıcıda açınca dönen durum: 404 geçersiz/kullanılmış, 410 süresi dolmuş, 200 form
- Sunucu env: PUBLIC_APP_URL / PUBLIC_BASE_URL değerleri (değeri paylaşmadan varlığını doğrulayın)
- Parola yazıldıktan sonra girişte hâlâ 401 ise akis-giris-oturum-jwt adımlarını izleyin

**Günlükte aranacak ifadeler**
- `[forgot-password] islem basarisiz`
- `[reset-password:get] hata`
- `[reset-password:post] hata (errorId=`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'forgot-password'"
```

**İlgili testler:** [server/test/password_reset.test.js](../../server/test/password_reset.test.js), [server/test/core_mailer_escape.test.js](../../server/test/core_mailer_escape.test.js)

**Bkz.:** [akis-giris-oturum-jwt](#akis-giris-oturum-jwt), [akis-kayit-eposta-dogrulama](#akis-kayit-eposta-dogrulama)

<a id="akis-bulut-kapi-acma"></a>
### akis-bulut-kapi-acma · Bulut kapı açma akışı bozuldu (uçtan uca): uygulamada "Kapıyı aç" denince kapı açılmıyor, hata gösteriyor ya da komut gidiyor ama röle çekmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3485](../../lib/ui/pages/home_page.dart#L3485) | <code>final (status, error) = await widget.authService.openDoor(</code> | Adım 1 — uygulama (ekran): kapı panelindeki düğme AuthService.openDoor'u çağırır. Aynı çağrıyı sesli komut (voice_door_service.dart), widget/kısayol/deep link (lib/app.dart) ve bireysel ana ekran (individual_home_view.dart) da yapar. |
| [lib/services/auth_service.dart:3051](../../lib/services/auth_service.dart#L3051) | <code>final allowRemote = door == null &#124;&#124; door.canOpenRemote &#124;&#124; isSuper;</code> | Adım 2 — uygulama (karar): kapı bayrakları istemcide de uygulanır; önce (izinliyse) yerel UDP denenir, olmazsa buluta düşülür; require_geofence kapıda konum alınamazsa istek HİÇ gönderilmez. |
| [lib/services/auth_api.dart:3193](../../lib/services/auth_api.dart#L3193) | <code>path: '/app/doors/$doorId/open',</code> | Adım 3 — uygulama (HTTP): POST /app/doors/:id/open, 202 beklenir; kapı komutu için 10 sn kısa zaman aşımı ("Kapı komutuna zamanında yanıt alınamadı. Kapı açılmış olabilir..."). |
| [server/src/routes/app_doors_routes.js:162](../../server/src/routes/app_doors_routes.js#L162) | <code>appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (r…</code> | Adım 4 — sunucu (rota): authRequired + kullanıcı/yol başına 10 sn'de 4 istek sınırı (429 "Kapi komutu cok sik gonderildi"); kapı id doğrulanır (400 INVALID_DOOR_ID). |
| [server/src/services/door_service.js:513](../../server/src/services/door_service.js#L513) | <code>export async function getAccessibleDoorForUser({ authUser, doorId }) {</code> | Adım 5 — veritabanı: kullanıcının bu kapıya yetkisi SQL ile hesaplanır (yönetici/site sahibi, özel kapı izni, sakin + SITE_COMMON/BLOCK kapsamı). Kapı yoksa/yetki yoksa 404 "Kapi bulunamadi."; cihaz atanmamışsa 409 "Bu kapiya cihaz atanmamis." |
| [server/src/services/door_access_policy.js:86](../../server/src/services/door_access_policy.js#L86) | <code>case 'remote':</code> | Adım 6 — sunucu (politika): sitede uzaktan açma kapalıysa (feature_remote_open_enabled=false) 403 REMOTE_OPEN_DISABLED; süper kullanıcı istisnası vardır. |
| [server/src/services/geofence_service.js:220](../../server/src/services/geofence_service.js#L220) | <code>export function validateGeofenceForDoorRequest({</code> | Adım 7 — sunucu (konum): site require_geofence ise konum alanları (latitude, longitude, accuracy, timestamp, is_mocked) doğrulanır; eksik/geçersiz/bayat (>60 sn)/yetersiz doğruluk (>100 m)/sahte konum/mesafe dışı -> 403 GEOFENCE_*. Site koordinatı tanımsızsa uyarıyla geçilir. |
| [server/src/mqtt_bridge.js:1122](../../server/src/mqtt_bridge.js#L1122) | <code>export async function publishDoorPulse({</code> | Adım 8 — MQTT (yayın): köprü bağlı değilse MQTT_BRIDGE_NOT_CONNECTED (503), cihaz çevrimdışıysa DEVICE_OFFLINE (409); aksi halde device/<UID>/cmd konusuna QoS1 {action:"pulse", request_id, requested_at(epoch sn), door_id, site_code} yayınlanır. Mosquitto ACL cihaza bu konuyu okuma izni verir (mqtt_acl_sync.js). |
| [server/src/routes/app_doors_routes.js:224](../../server/src/routes/app_doors_routes.js#L224) | <code>await recordDoorAccessLog({</code> | Adım 9 — veritabanı (günlük): yayın başarılı olunca arka planda door_access_logs satırı (trigger_type cloud_app / voice / screen_qr) yazılır ve istemciye 202 döner. 202 "komut yayınlandı" demektir, cihazın uyguladığını GARANTİ ETMEZ; DB yazma hatası yalnızca günlüğe düşer. |
| [cihaz_kontrol/include/mqtt_baglanti.h:247](../../cihaz_kontrol/include/mqtt_baglanti.h#L247) | <code>inline void mqttHandlePulse(JsonDocument&amp; json) {</code> | Adım 10 — cihaz (komut): requested_at ile saat farkı >60 sn ise pulse_rejected/stale, aynı request_id tekrar gelirse yok sayılır, röle meşgulse pulse_rejected/role_busy; aksi halde röle tetiklenir, gDoorLocked=false, ekrana CMD_DOOR_OPENED, durum + pulse_started olayı yayınlanır. |
| [cihaz_kontrol/include/role_kontrol.h:124](../../cihaz_kontrol/include/role_kontrol.h#L124) | <code>inline bool roleTetikle() {</code> | Adım 11 — cihaz (röle): röle aktifse ya da son tetikten 2.5 sn geçmediyse reddedilir (debounce); aksi halde ROLE_PIN aktif olur ve esp_timer ile ROLE_SURE_MS (1500 ms) sonra bırakılır; bırakınca pulse_completed olayı + kilitli durum yayınlanır. |
| [server/src/mqtt_bridge.js:903](../../server/src/mqtt_bridge.js#L903) | <code>if (kind === 'state') {</code> | Adım 12 — dönüş (durum): cihazın device/<UID>/state yayını köprüde door_locked/wifi/firmware olarak güncellenir ve device_runtime_status'a yazılır; uygulama kapı panelinde ~3 sn'lik yoklamayla GET /app/doors/:id/status üzerinden bunu görür. |

**Olası nedenler**
- Adım 2: kapı bayrağı kapalı ("Bu kapı için uygulamadan açma kapalı") ya da konum izni/servisi kapalı (require_geofence)
- Adım 4: 10 sn içinde 4'ten fazla istek (429)
- Adım 5: kullanıcının kapıya yetkisi yok / üyelik pasif / kapıya cihaz atanmamış (404/409)
- Adım 6-7: site politikası (REMOTE_OPEN_DISABLED) ya da geofence reddi (GEOFENCE_OUT_OF_RANGE, GEOFENCE_MOCK_LOCATION, GEOFENCE_LOCATION_STALE...)
- Adım 8: MQTT köprüsü bağlı değil (MQTT_HOST/USER/PASSWORD eksik, broker kapalı) ya da cihaz çevrimdışı görünüyor (409); ACL'de cihaz yok
- Adım 10: cihaz saati senkron değil/çok kaymış (stale), röle zaten aktif (role_busy), cihazın MQTT bağlantısı sessizce kopuk (LWT henüz tetiklenmedi)
- Adım 11: röle pini/kablo/kilit arızası (yazılım pulse_started yayınlar ama kapı açılmaz)
- Adım 3: ağ/proxy kesintisi; 10 sn zaman aşımı kapının açılmış olmasını engellemez (kontrol edin)

**Adım adım kontrol**
- Uygulamada görünen mesajı aratın (docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md): hangi adımdan geldiğini bulun
- Sunucu günlüğü: "[API] POST /app/doors/<id>/open -> <durum>" (202 başarı; 403 politika/konum; 409 cihaz yok/çevrimdışı; 429 sınır; 503 köprü) ve "door_open_command" denetim satırı
- Köprü sağlığı: GET /health -> mqtt.connected true mu, last_error ne (mqtt_not_configured | mqtt_offline | mqtt_error | db_error)
- Cihaz çevrimiçi mi: SELECT device_uid, is_online, last_online_at FROM devices WHERE device_uid = '<UID>'; SELECT mqtt_connected, last_seen_at, last_event FROM device_runtime_status WHERE device_uid = '<UID>';
- Cihaz seri günlüğünde "MQTT komut alindi", "Role tetiklendi GPIO", "MQTT pulse REDDEDILDI" ya da "Role debounce" satırını arayın
- Cihaz olayları: device_runtime_status.last_event = pulse_started / pulse_completed / pulse_rejected (last_event_detail: stale | role_busy)
- Röle çekiyor ama kapı açılmıyorsa donanıma bakın (ROLE_PIN, röle kartı, kilit besleme); yazılım katmanı çalışmıştır
- Yerel ağdan açılıyor ama bulut açmıyorsa akis-yerel-kapi-acma ile karşılaştırın (MQTT yolu bozuktur)

**Günlükte aranacak ifadeler**
- `door_open_command`
- `Kapi gecis logu DB kayit hatasi:`
- `[MQTT bridge] `
- `MQTT komut alindi (`
- `MQTT pulse REDDEDILDI: requested_at zaman penceresi disinda.`
- `MQTT pulse yok sayildi: ayni request_id tekrar geldi.`
- `Role tetiklendi GPIO`
- `Role debounce: Role zaten aktif veya son tetikten bu yana 2.5s gecmedi.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a '/open'"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'MQTT bridge'"
```

**İlgili testler:** [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js), [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js), [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js), [server/test/doors_geofence.test.js](../../server/test/doors_geofence.test.js), [test/local_door_access_test.dart](../../test/local_door_access_test.dart)

**Bkz.:** [akis-yerel-kapi-acma](#akis-yerel-kapi-acma), [akis-cihaz-baglanti-gunlukleri](#akis-cihaz-baglanti-gunlukleri), [akis-dinamik-qr-gm60](#akis-dinamik-qr-gm60)

<a id="akis-dinamik-qr-gm60"></a>
### akis-dinamik-qr-gm60 · Dinamik QR ile kapı açma akışı bozuldu (uçtan uca): telefondaki QR'ı cihaz kamerası (GM60) okuyor ama kapı açılmıyor / "geçersiz, kullanılmış, süresi dolmuş" deniyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:455](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L455) | <code>final (data, error) = await auth.requestDoorQrToken(</code> | Adım 1 — uygulama (ekran): QR penceresi açılınca (konum zorunluysa önce GPS konumuyla) /qr-token istenir; dönen token QR olarak çizilir, geri sayım ve durum yoklaması başlar. |
| [server/src/routes/app_doors_routes.js:477](../../server/src/routes/app_doors_routes.js#L477) | <code>appDoorsRouter.post('/app/doors/:id/qr-token', authRequired, qrTokenRateLimiter, async (r…</code> | Adım 2 — sunucu (rota): authRequired + kullanıcı başına dakikada 6 istek (429 "Karekod talebi çok sık yapıldı"); hata gövdesi code alanı taşır (NO_QR_SCANNER_HARDWARE, GEOFENCE_*, QR_DISABLED). |
| [server/src/services/qr_access_service.js:22](../../server/src/services/qr_access_service.js#L22) | <code>export async function generateQrTokenForDoor({ authUser, doorId, clientLocation }) {</code> | Adım 3 — sunucu (kurallar): kapı erişimi, qr kanalı politikası (QR_DISABLED/QR_ENTRY_INACTIVE), kapıda fiziksel okuyucu (C3 cihazı ya da qr_reader_enabled=false -> 400 NO_QR_SCANNER_HARDWARE) ve geofence doğrulanır. |
| [server/src/services/qr_access_service.js:61](../../server/src/services/qr_access_service.js#L61) | <code>const rawToken = 'QR:' + crypto.randomBytes(24).toString('hex');</code> | Adım 4 — veritabanı: 192 bit rastgele "QR:..." token qr_access_tokens'a yazılır; aynı kullanıcı+kapı için önceki aktif token'lar aynı işlemde SUPERSEDE edilir; süre site qr_rotation_seconds (varsayılan 30 sn). |
| [cihaz_kontrol/include/gm60_scanner.h:206](../../cihaz_kontrol/include/gm60_scanner.h#L206) | <code>inline void gm60QrVerisiniIsle(String qrData) {</code> | Adım 5 — cihaz (okuma): GM60 UART'tan gelen veri temizlenir; sunucu yanıtı beklenirken, 5 sn debounce içinde ve aynı token 8 sn içinde tekrar okunursa atlanır; MQTT yoksa dinamik QR açılmaz (CMD_QR_DENIED). |
| [cihaz_kontrol/include/gm60_scanner.h:270](../../cihaz_kontrol/include/gm60_scanner.h#L270) | <code>const bool gonderildi = mqttPublishQrVerify(qrData, istekId);</code> | Adım 6 — MQTT (cihaz -> sunucu): token device/<UID>/qr_verify konusuna {token, request_id} olarak yayınlanır (cihaz ACL'de bu konuya yazabilmeli); 10 sn qr_result beklenir. |
| [server/src/mqtt_bridge.js:803](../../server/src/mqtt_bridge.js#L803) | <code>if (kind === 'qr_verify') {</code> | Adım 7 — sunucu (köprü): retained qr_verify yok sayılır; verifyQrTokenAndOpenDoor çağrılır ve sonuç device/<UID>/qr_result konusuna aynı request_id ile yayınlanır (allowed/reason). |
| [server/src/services/qr_access_service.js:163](../../server/src/services/qr_access_service.js#L163) | <code>export async function verifyQrTokenAndOpenDoor({ deviceUid, token }) {</code> | Adım 8 — veritabanı + kurallar: cihaz->kapı eşleşmesi, qr_reader_enabled, token durumu (ALREADY_USED, SUPERSEDED_TOKEN, EXPIRED_TOKEN, TOKEN_OR_USER_INACTIVE, DOOR_MISMATCH) ve tüketim anında yetki + site politikası yeniden denetlenir; token kaynaklı redler (ve tanımsız QR) door_access_logs'a (qr_scanner) yazılır; cihaz/okuyucu/kapı atama redleri (DEVICE_NOT_FOUND, QR_READER_NOT_ENABLED, DOOR_NOT_ASSIGNED) yazılmaz. |
| [server/src/services/qr_access_service.js:347](../../server/src/services/qr_access_service.js#L347) | <code>SET is_used = TRUE,</code> | Adım 9 — veritabanı (atomik tüketim): tek UPDATE ile token tek kullanımlık işaretlenir; 0 satır dönerse yarış kaybedilmiştir (ALREADY_USED). |
| [server/src/services/qr_access_service.js:377](../../server/src/services/qr_access_service.js#L377) | <code>assumeOnline: true,</code> | Adım 10 — MQTT (sunucu -> cihaz): publishDoorPulse çağrılır (istek cihazdan geldiği için çevrimiçi varsayılır); komut gönderilemezse token geri verilir (PULSE_FAILED) ve başarısız olarak loglanır. Başarıda "[QR Dogrulama ONAY]" günlüğü ve door_access_logs (qr_scanner) satırı yazılır. |
| [cihaz_kontrol/include/mqtt_baglanti.h:278](../../cihaz_kontrol/include/mqtt_baglanti.h#L278) | <code>inline void mqttHandleQrResult(const String&amp; message) {</code> | Adım 11 — cihaz (sonuç): request_id bekleyen istekle eşleşmezse sonuç yok sayılır; allowed=false ise CMD_QR_DENIED gösterilir ve aynı QR yeniden denenebilir; allowed=true ise röle pulse komutu AYRICA gelir (mqttHandlePulse) ve kapıyı açar. |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:284](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L284) | <code>final (data, error) = await auth.getDoorQrStatus(qrToken);</code> | Adım 12 — dönüş (uygulama): telefon /app/doors/qr-status ile token durumunu yoklar; geçiş başarılı / kullanılmış / yenilenmiş / süresi dolmuş / reddedildi durumlarını ekranda başlık olarak gösterir. |

**Olası nedenler**
- Adım 3: kapıda QR kapalı (QR_DISABLED), ekransız C3 cihazı ya da qr_reader_enabled=false (NO_QR_SCANNER_HARDWARE), geofence reddi
- Adım 5: GM60 kamera bağlı değil/yanıt vermiyor (gm60Bagli false), ekran-telefon mesafesi/parlaklığı, MQTT bağlı değil (offline QR açmaz)
- Adım 8: token 30 sn doldu (EXPIRED_TOKEN), yeni QR istendi (SUPERSEDED_TOKEN), aynı QR ikinci kez okutuldu (ALREADY_USED), başka kapıdaki okuyucuya gösterildi (DOOR_MISMATCH), üyelik/izin sonradan kalktı (ACCESS_REVOKED)
- Adım 6-7: cihazın MQTT ACL'de qr_verify yazma izni yok / köprü qr_verify aboneliği düşmüş (qr_result hiç gelmez, cihaz 10 sn sonra vazgeçer)
- Adım 10: cihaz çevrimdışı/köprü bağlı değil (PULSE_FAILED); röle meşgul (pulse_rejected role_busy)

**Adım adım kontrol**
- Cihaz seri günlüğü: "[GM60] QR okundu", "[GM60] QR basariyla sunucuya gonderildi", "[MQTT QR Sonuc] Izin: ONAYLANDI/REDDEDILDI | Neden: ..." satırları hangi adımda durduğunu söyler
- Neden kodu "Neden:" alanında görünür (ALREADY_USED, EXPIRED_TOKEN, SUPERSEDED_TOKEN, DOOR_MISMATCH, ACCESS_REVOKED, PULSE_FAILED, INVALID_TOKEN, QR_READER_NOT_ENABLED, DOOR_NOT_ASSIGNED)
- Sunucu günlüğünde "[QR Dogrulama RED]" veya "[QR Dogrulama ONAY]" satırını arayın
- DB: SELECT id, is_active, is_used, expires_at, last_denial_reason FROM qr_access_tokens WHERE user_code = <kod> ORDER BY id DESC LIMIT 5; SELECT device_uid, qr_reader_enabled FROM devices WHERE device_uid = '<UID>';
- Kameradan hiç satır gelmiyorsa donanım (GM60 bağlantısı, "k" seri komutu = kamera self-test)
- QR gösterildi ama telefon durum başlığı değişmiyorsa /app/doors/qr-status isteğini günlükte arayın

**Günlükte aranacak ifadeler**
- `[QR Dogrulama RED]`
- `[QR Dogrulama ONAY]`
- `[MQTT QR Verify] Islem hatasi:`
- `[GM60] QR basariyla sunucuya gonderildi. Sunucu dogrulamasi bekleniyor.`
- `[MQTT QR Sonuc] Izin: `

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'QR Dogrulama'"
```

**İlgili testler:** [server/test/doors_qr_access.test.js](../../server/test/doors_qr_access.test.js), [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js), [test/fix_fx2_qr_modal_test.dart](../../test/fix_fx2_qr_modal_test.dart), [test/qr_modal_polling_test.dart](../../test/qr_modal_polling_test.dart)

**Bkz.:** [akis-bulut-kapi-acma](#akis-bulut-kapi-acma), [akis-ekran-qr-uygulama-okutma](#akis-ekran-qr-uygulama-okutma), [akis-misafir-gecis](#akis-misafir-gecis)

<a id="akis-ekran-qr-uygulama-okutma"></a>
### akis-ekran-qr-uygulama-okutma · Karekod okutarak kapı açma akışı bozuldu (uçtan uca): uygulamayla cihaz ekranındaki karekodu okutunca kapı açılmıyor / "karekod süresi dolmuş" / "karekod henüz alınamadı"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/individual_home_view.dart:383](../../lib/ui/views/individual_home_view.dart#L383) | <code>final (result, error) = await widget.authService.openDoorWithScannedQr(</code> | Adım 1 — uygulama (ekran): kamera ile okunan karekod metni AuthService.openDoorWithScannedQr'a verilir (konum zorunluysa GPS konumu eklenir). Daire sakini kartı da aynı çağrıyı yapar (resident_door_remote_card.dart). |
| [lib/services/auth_api.dart:3216](../../lib/services/auth_api.dart#L3216) | <code>path: '/app/doors/scan-qr-open',</code> | Adım 2 — uygulama (HTTP): POST /app/doors/scan-qr-open {qr_payload + konum}, 200 beklenir; 10 sn zaman aşımı ("Karekod doğrulamasına zamanında yanıt alınamadı. Kapı açılmış olabilir..."). |
| [server/src/routes/app_doors_routes.js:263](../../server/src/routes/app_doors_routes.js#L263) | <code>appDoorsRouter.post('/app/doors/scan-qr-open', authRequired, doorCommandRateLimiter, asyn…</code> | Adım 3 — sunucu (rota): qr_payload ayrıştırılır (400 INVALID_QR_PAYLOAD), karekoddaki UID ile aktif kapı aranır (404 DOOR_NOT_FOUND), kullanıcının kapıya yetkisi denetlenir (403 DOOR_ACCESS_DENIED). |
| [server/src/routes/app_doors_routes.js:305](../../server/src/routes/app_doors_routes.js#L305) | <code>assertDoorOpenAllowed({ door, channel: 'qr', authUser: req.authUser });</code> | Adım 4 — sunucu (politika): qr kanalı kapalıysa 403 QR_DISABLED / QR_ENTRY_INACTIVE (süper kullanıcı istisnası). |
| [cihaz_kontrol/src/main.cpp:267](../../cihaz_kontrol/src/main.cpp#L267) | <code>const String qrCmd = String(CMD_SHOW_QR_PREFIX) + "AHBU:DOOR:" + cihazUniqueId() + ":" + …</code> | Adım 5 — cihaz (arka plan, sürekli): ekranlı WROOM her 30 sn'de 6 karakterlik yeni ekran tokenı üretir, UART ile ekrana gönderir; Adım 8'in ön koşuludur. C3'te ekran/token yoktur. |
| [cihaz_kontrol/include/mqtt_baglanti.h:188](../../cihaz_kontrol/include/mqtt_baglanti.h#L188) | <code>inline bool mqttPublishScreenQr(const String&amp; token, int validSeconds = 30) {</code> | Adım 6 — MQTT (cihaz -> sunucu, sürekli): token device/<UID>/screen_qr konusuna yayınlanır (retained DEĞİL; token seriye yazılmaz). |
| [server/src/mqtt_bridge.js:777](../../server/src/mqtt_bridge.js#L777) | <code>if (kind === 'screen_qr') {</code> | Adım 7 — sunucu (köprü, sürekli): token deviceScreenQrStore belleğine (cihaz UID anahtarıyla) yazılır; retained mesajlar yok sayılır. Süreç yeniden başlayınca bellek boştur: ilk yayına kadar 409 EKRAN_QR_BEKLENIYOR. |
| [server/src/routes/app_doors_routes.js:333](../../server/src/routes/app_doors_routes.js#L333) | <code>const check = checkScreenQrToken(screenEntry, parsed.token);</code> | Adım 8 — sunucu (token): ekranlı cihazda token ZORUNLU (403 DYNAMIC_QR_REQUIRED); bellekte token yoksa 409 EKRAN_QR_BEKLENIYOR; süresi dolmuş -> 403 SCREEN_QR_EXPIRED; kullanılmış -> 403 SCREEN_QR_ALREADY_USED. Eşleşmeyen/eski token da istemciye 403 SCREEN_QR_EXPIRED döner (denetim satırında kod SCREEN_QR_MISMATCH olur). |
| [server/src/routes/app_doors_routes.js:355](../../server/src/routes/app_doors_routes.js#L355) | <code>forceRequire: !hasScreen,</code> | Adım 9 — sunucu (konum): ekransız (statik UID karekodlu) cihazda geofence site bayrağından bağımsız ZORUNLUDUR; ekranlıda site ayarına bağlıdır. |
| [server/src/routes/app_doors_routes.js:360](../../server/src/routes/app_doors_routes.js#L360) | <code>const consumed = consumeScreenQrToken(screenEntry, parsed.token);</code> | Adım 10 — sunucu (tüketim): ekran tokenı TEK KULLANIMLIK tüketilir (senkron; yarış yok); sonraki adımda komut gönderilemezse releaseScreenQrToken ile geri verilir. |
| [server/src/routes/app_doors_routes.js:371](../../server/src/routes/app_doors_routes.js#L371) | <code>await publishDoorPulse({</code> | Adım 11 — MQTT (sunucu -> cihaz): device/<UID>/cmd pulse yayınlanır (hata kodları bulut açmayla aynı: 503 köprü, 409 çevrimdışı); ardından arka planda door_access_logs (trigger_type screen_qr) yazılır ve 200 döner. |
| [cihaz_kontrol/include/mqtt_baglanti.h:348](../../cihaz_kontrol/include/mqtt_baglanti.h#L348) | <code>if (action == "pulse") {</code> | Adım 12 — cihaz: pulse komutu mqttHandlePulse -> roleTetikle ile röleyi çeker (ayrıntı için akis-bulut-kapi-acma Adım 10-11). |

**Olası nedenler**
- Adım 8: karekod yenilenmiş (30 sn) -> SCREEN_QR_EXPIRED; aynı karekod ikinci kez -> SCREEN_QR_ALREADY_USED; sunucu yeniden başlamış/cihaz çevrimdışı -> EKRAN_QR_BEKLENIYOR
- Adım 5-7: cihaz ekran tokenını yayınlamıyor (MQTT bağlı değil, ekran kartı yok) ya da ACL screen_qr yazma izni yok
- Adım 3: karekod başka siteye/kapıya ait ya da kullanıcının yetkisi yok (DOOR_ACCESS_DENIED)
- Adım 9: ekransız cihazda konum zorunlu; konum izni/doğruluğu yetersiz (GEOFENCE_*)
- Adım 11: cihaz çevrimdışı (409) ya da köprü bağlı değil (503); bu durumda token geri verilir, tekrar denenebilir

**Adım adım kontrol**
- Sunucu günlüğünde "[API] POST /app/doors/scan-qr-open -> <durum>" ve yanıttaki code alanı (uygulama mesajı da aynı metni gösterir)
- Köprü ekran tokenını alıyor mu: cihaz seri portuna "s" gönderip "MQTT: bagli" satırına bakın; sunucuda device_runtime_status.last_seen_at güncel mi
- Denetim satırı: "scan_qr_open_rejected" olayı ve code alanı (DYNAMIC_QR_REQUIRED, EKRAN_QR_BEKLENIYOR, SCREEN_QR_...)
- Ekran QR sürekli yenileniyorsa kullanıcının okuttuğu kodun hâlâ güncel olduğundan emin olun (yenilenme 30 sn)
- Komut gitti ama kapı açılmadıysa akis-bulut-kapi-acma Adım 10-12 kontrollerine geçin

**Günlükte aranacak ifadeler**
- `scan_qr_open_rejected`
- `[app_doors] `
- `Kapi gecis logu DB kayit hatasi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a 'scan-qr-open'"
```

**İlgili testler:** [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js), [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [akis-bulut-kapi-acma](#akis-bulut-kapi-acma), [akis-dinamik-qr-gm60](#akis-dinamik-qr-gm60)

<a id="akis-yerel-kapi-acma"></a>
### akis-yerel-kapi-acma · Yerel kapı açma akışı bozuldu (uçtan uca): telefon cihazla aynı Wi-Fi'de ama kapı yerel ağdan açılmıyor, hep buluta düşüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3067](../../lib/services/auth_service.dart#L3067) | <code>final localResult = await _tryOpenDoorLocallyIfAlive(door);</code> | Adım 1 — uygulama (karar): yerel yol YALNIZCA kapı yerel açmaya izin veriyorsa, telefon yerel Wi-Fi'deyse, önbellekte geçerli token varsa ve cihazın taze beacon'ı görüldüyse denenir; aksi halde sessizce buluta düşülür. |
| [lib/services/auth_service.dart:3660](../../lib/services/auth_service.dart#L3660) | <code>Future&lt;void&gt; _cacheLocalDoorAccess(DoorRuntimeStatus status) async {</code> | Adım 2 — uygulama (önbellek): token sunucudan kapı durumu yanıtıyla gelir ve güvenli depoya yazılır; sunucu token vermezse (yetki kalktı/token döndürüldü) önbellek temizlenir ve yerel açma denenmez (fail-closed). |
| [server/src/services/door_service.js:37](../../server/src/services/door_service.js#L37) | <code>export async function localDoorControlForStatus({ deviceUid, currentToken, status, allowL…</code> | Adım 3 — sunucu: sitede yerel açma kapalıysa (feature_local_udp_enabled=false) token VERİLMEZ; aksi halde cihaz için local_control_token üretilir/okunur ve cihaz bunu henüz bilmiyorsa (local_control_available false) dakikada bir MQTT ile cihaza gönderilir. |
| [server/src/mqtt_bridge.js:1161](../../server/src/mqtt_bridge.js#L1161) | <code>export async function publishLocalControlConfig({</code> | Adım 4 — MQTT (sunucu -> cihaz): device/<UID>/cmd konusuna {action:"local_control_config", local_control_token} yayınlanır; cihaz çevrimdışıysa false döner (token iletilmez). |
| [cihaz_kontrol/include/mqtt_baglanti.h:361](../../cihaz_kontrol/include/mqtt_baglanti.h#L361) | <code>} else if (action == "local_control_config") {</code> | Adım 5 — cihaz (anahtar): token doğrulanıp NVS'e yazılır (wifiPersistLocalToken; geçersizse local_control_config_rejected olayı); sonraki durum yayınında local_control_available true olur. |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:341](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L341) | <code>inline void yerelBeaconYayinla() {</code> | Adım 6 — cihaz (beacon): ~5 sn'de bir UDP broadcast {device_uid, ip, port 8765, rssi, hw, ch(challenge)}; uygulama bunu dinleyip önbelleğe alır (LocalDoorService.startBeaconListener). |
| [lib/services/local_door_service.dart:815](../../lib/services/local_door_service.dart#L815) | <code>Future&lt;bool&gt; _directUdpOpen(</code> | Adım 7 — uygulama (UDP): sig = HMAC-SHA256(token, "open\|UID\|ch") ile imzalı paket cihazın IP:8765 adresine gider (token ağa çıkmaz); 150 ms içinde yanıt gelmezse false -> buluta düşülür; "challenge" hatasında güncel ch ile TEK yeniden deneme. |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:385](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L385) | <code>inline void yerelUdpAcmaIsle(JsonDocument&amp; doc, const String&amp; action, const String&amp; benim…</code> | Adım 8 — cihaz (karar): token yok / yinelenen / ch geçersiz / imza yanlış / röle meşgul sonuçları unauthorized, duplicate, challenge, role_mesgul olarak yanıtlanır; doğruysa yanıt gönderilir ve yan etkiler çalışır (yerelKontrolKullanilabilirMi: HMAC öz-testi + token şart). |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:264](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L264) | <code>inline void yerelKapiAcildiYanEtkileri(const char* olay, const char* offlineTur, const St…</code> | Adım 9 — cihaz (röle + günlük): gDoorLocked=false, ekran, MQTT olayı local_udp_pulse_started + durum ve offlineLogKaydet("local_udp") ile cihazın çevrimdışı günlüğüne satır (MQTT ile senkronlanır: akis-cevrimdisi-kapi-gunlukleri). |
| [lib/services/auth_service.dart:3776](../../lib/services/auth_service.dart#L3776) | <code>.notifyLocalDoorOpened(</code> | Adım 10 — uygulama (bildirim): yerel açma başarılı olunca arka planda sunucuya /local-open-notify gönderilir (hata oturumu etkilemez). |
| [server/src/routes/app_doors_routes.js:420](../../server/src/routes/app_doors_routes.js#L420) | <code>appDoorsRouter.post('/app/doors/:id/local-open-notify', authRequired, doorCommandRateLimi…</code> | Adım 11 — sunucu (rota): kapı yetkisi + local kanal politikası denetlenir (403 LOCAL_DISABLED), local_ip normalize edilir, "door_open_local_command" denetim satırı yazılır. |
| [server/src/routes/app_doors_routes.js:455](../../server/src/routes/app_doors_routes.js#L455) | <code>await recordLocalOpenNotifyLog({</code> | Adım 12 — veritabanı (günlük): door_access_logs'a trigger_type local_wifi satırı yazılır (aynı kullanıcı + kapı için 15 sn içinde yerel satır varsa yazılmaz); bu uç yerel açmayı DOĞRULAMAZ, yalnızca kaydeder. |
| [server/src/services/door_log_service.js:439](../../server/src/services/door_log_service.js#L439) | <code>export async function reconcileLocalOpenLogs({ siteCode, doorId, around }, db = pool) {</code> | Adım 13 — veritabanı (tekilleştirme): cihaz aynı yerel açmayı kendi offline logu olarak da (local_udp, kullanıcısız) gönderir; 15 sn içinde eşleşen çiftte cihaz satırı korunur, kullanıcı bilgisi ona taşınır, uygulama satırı silinir (eşleşme gelişin sırasından bağımsız; saati bilinmeyen kayıtlar eşleşmez, çift satır kalabilir). |

**Olası nedenler**
- Adım 1: telefon farklı ağda/mobil veride, VPN ya da "AP izolasyonu" açık modem (UDP broadcast ulaşmaz); beacon dinleyici duraklatılmış
- Adım 2-3: kapıda/sitede yerel açma kapalı (token verilmez) ya da sunucu henüz token üretmemiş/cihaza iletmemiş
- Adım 5: cihazda token yok ya da HMAC öz-testi başarısız (local_control_selftest_failed olayı; yerel açma fail-closed KAPALI)
- Adım 7-8: imza uyuşmuyor (token döndürülmüş, uygulama eski token kullanıyor) -> unauthorized; ch bayat -> tek yeniden deneme; kaynak adres özel ağ değil
- Adım 8: röle meşgul (role_mesgul) ya da paket 512 bayttan büyük
- Adım 6: cihaz Wi-Fi'de değil, beacon yayınlamıyor (yalnızca Wi-Fi bağlıyken yayınlar)

**Adım adım kontrol**
- Uygulama hata ayıklama günlüğünde "[YerelKapi]" satırları: canlı beacon bulundu mu, UDP yanıtı doğrulandı mı
- Cihaz seri günlüğü: "Yerel kapi kontrol aktif", "UDP Kapi Acma REDDEDILDI: imza gecersiz.", "Yerel UDP: KAPI ACILDI (role tetiklendi)."
- Cihaz seri durum dökümü ("s" komutu): "Yerel kontrol: etkin (anahtar var)" mı, "kapali (anahtar yok)" mı
- Sunucuda token iletildi mi: device_runtime_status.local_control_available ve "local_control_token_synced" denetim satırı
- Site politikası: sites.feature_local_udp_enabled (false ise yerel açma bilerek kapalıdır)
- Token döndürüldüyse (üyelik/izin değişimi) uygulama kapı durumunu yenileyince yeni token gelir; o ana kadar unauthorized normaldir
- Protokol ayrıntısı ve test vektörü: docs/YEREL_KONTROL_V2.md

**Günlükte aranacak ifadeler**
- `UDP Kapi Acma REDDEDILDI: imza gecersiz.`
- `Yerel UDP: KAPI ACILDI (role tetiklendi).`
- `Yerel kontrol: HMAC oz-testi basarili.`
- `local_control_token_synced`
- `door_open_local_command`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'local'"
```

**İlgili testler:** [test/local_door_service_v2_test.dart](../../test/local_door_service_v2_test.dart), [test/local_door_service_security_test.dart](../../test/local_door_service_security_test.dart), [test/local_door_access_test.dart](../../test/local_door_access_test.dart), [server/test/devices_device_service.test.js](../../server/test/devices_device_service.test.js), [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp)

**Bkz.:** [akis-bulut-kapi-acma](#akis-bulut-kapi-acma), [akis-cevrimdisi-kapi-gunlukleri](#akis-cevrimdisi-kapi-gunlukleri)

<a id="akis-bakim-temizlik-health"></a>
### akis-bakim-temizlik-health · Bakım/temizlik ve sağlık akışı bozuldu (uçtan uca): eski kayıtlar silinmiyor, süper kullanıcı "Veritabanı Sağlığı" penceresi hata veriyor ya da /health "ok:false" dönüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/server.js:404](../../server/src/server.js#L404) | <code>setInterval(runCleanupSafely, 24 * 60 * 60 * 1000).unref();</code> | Adım 1 — sunucu (zamanlayıcı): açılışta bir kez ve sonra 24 saatte bir runCleanupSafely çalışır; hata yalnızca "[Bakim] Temizlik hatasi:" olarak günlüğe düşer, süreç düşmez. PM2 yeniden başlayınca sayaç sıfırlanır. |
| [server/src/services/maintenance_service.js:16](../../server/src/services/maintenance_service.js#L16) | <code>export async function runDatabaseCleanup(db = pool) {</code> | Adım 2 — sunucu (iş kuralı): yalnızca süresi dolmuş QR token (1 gün), e-posta doğrulama kodu (2 gün), bekleyen kayıt (2 gün), 30 günden eski bağlantı ve kapı günlükleri silinir; kullanıcı hesabı, üyelik veya tablo SİLİNMEZ. |
| [server/src/services/maintenance_service.js:109](../../server/src/services/maintenance_service.js#L109) | <code>DELETE FROM door_access_logs</code> | Adım 3 — veritabanı: kapı geçiş günlüğü 30 gün saklanır (opened_at). Uygulamada eski günlüğün görünmemesi hata değil, saklama süresidir. |
| [server/src/services/maintenance_service.js:122](../../server/src/services/maintenance_service.js#L122) | <code>VALUES ('routine_cleanup', NOW())</code> | Adım 4 — veritabanı: son başarılı temizlik app_maintenance_runs tablosuna "routine_cleanup" anahtarıyla yazılır; sağlık penceresindeki "son temizlik" buradan okunur. Hata olursa bu satır güncellenmez. |
| [lib/ui/views/all_users_view.dart:428](../../lib/ui/views/all_users_view.dart#L428) | <code>final data = await widget.onGetDatabaseHealth!();</code> | Adım 5 — uygulama (ekran): süper kullanıcının sağlık penceresi açılınca AuthService.getDatabaseHealth çağrılır; "Temizle" düğmesi onRunDatabaseCleanup'ı çağırır, ardından sağlığı yeniler. |
| [lib/services/auth_api.dart:550](../../lib/services/auth_api.dart#L550) | <code>path: '/admin/maintenance/health',</code> | Adım 6 — uygulama (HTTP): GET /admin/maintenance/health (200 beklenir); temizlik için POST /admin/maintenance/cleanup (hemen altında). |
| [server/src/routes/admin_routes.js:1862](../../server/src/routes/admin_routes.js#L1862) | <code>adminRouter.get('/admin/maintenance/health', authRequired, requireSuperUser, async (_req,…</code> | Adım 7 — sunucu (rota): yalnızca süper kullanıcı (aksi halde 401/403); getDatabaseHealth hata verirse 500 + errorId ("Veritabani saglik bilgisi alinamadi."). |
| [server/src/routes/admin_routes.js:1874](../../server/src/routes/admin_routes.js#L1874) | <code>adminRouter.post('/admin/maintenance/cleanup', authRequired, requireSuperUser, async (req…</code> | Adım 8 — sunucu (rota): "database_maintenance_cleanup_requested" denetim satırı yazılır ve runDatabaseCleanup elle çalıştırılır; hata 500 + errorId. |
| [server/src/services/maintenance_service.js:148](../../server/src/services/maintenance_service.js#L148) | <code>export async function getDatabaseHealth(db = pool) {</code> | Adım 9 — veritabanı: kullanıcı/yapı/cihaz sayıları, silinebilir kayıt sayıları (pendingCleanup) ve son temizlik tarihi SELECT'lerle toplanır. isClean yalnızca silinebilir kayıt sayısına bağlıdır. |
| [server/src/routes/firmware_routes.js:123](../../server/src/routes/firmware_routes.js#L123) | <code>firmwareRouter.get('/health', async (_req, res) =&gt; {</code> | Adım 10 — sunucu (/health): herkese açık; checkDbConnection (SELECT 1) başarılıysa 200 {ok:true, database, mqtt}; DB hatasında 500 {ok:false, database:"disconnected"}. Deploy betiği ve PM2 sonrası kontrol bu yanıtı kullanır. |
| [server/src/mqtt_bridge.js:1090](../../server/src/mqtt_bridge.js#L1090) | <code>export function mqttBridgeHealth() {</code> | Adım 11 — MQTT (köprü sağlığı): /health içindeki mqtt alanı configured/connected/has_error ve kısa last_error kodunu verir (ham hata metni sızmaz). MQTT kopuk olsa bile /health ok:true kalabilir; MQTT durumuna ayrıca bakın. |
| [deploy/remote_deploy.sh:15](../../deploy/remote_deploy.sh#L15) | <code>curl -fsS -m 10 http://127.0.0.1:8080/health 2&gt;/dev/null &#124; grep -q '"ok":true'</code> | Adım 12 — dağıtım: yayın sonrası /health "ok":true içermezse betik otomatik geri alma yapar. |

**Olası nedenler**
- Adım 1: süreç sık yeniden başlıyor (zamanlayıcı yalnızca açılışta + 24 saatte bir); "[Bakim] Temizlik hatasi:" günlükte
- Adım 2-4: DB yetkisi/bağlantı hatası nedeniyle temizlik başarısız (success:false, "Veritabanı temizliği başarısız oldu."); son temizlik tarihi eski kalır
- Adım 7: hesap süper kullanıcı değil (403) ya da oturum geçersiz (401)
- Adım 10: PostgreSQL erişilemiyor / bağlantı havuzu dolu (500 ok:false)
- Adım 11: MQTT_HOST/USER/PASSWORD eksik (mqtt_not_configured), broker kapalı (mqtt_offline); /health yine de ok:true olabilir
- Kayıtların "silinmemesi" çoğu zaman bilinçli sınırdır: hesaplar ve üyelikler hiç silinmez, günlükler 30 gün saklanır

**Adım adım kontrol**
- Sunucuda canlı sağlık: curl http://127.0.0.1:8080/health -> ok, database, mqtt.connected, mqtt.last_error
- Günlükte "[Maintenance Cleanup]" (başarı) ya da "[Bakim] Temizlik hatasi:" / "[Maintenance Cleanup] Hata:" satırını arayın
- Son temizlik: SELECT executed_at FROM app_maintenance_runs WHERE maintenance_key = 'routine_cleanup';
- Silinebilir kayıt var mı: SELECT COUNT(*) FROM door_access_logs WHERE opened_at < NOW() - INTERVAL '30 days';
- Sağlık penceresi açılmıyorsa günlükte "[API] GET /admin/maintenance/health -> <durum>" satırına bakın (401/403 yetki, 500 errorId)
- Elle temizlik yalnızca süper kullanıcıdan uygulamadaki "Temizle" düğmesiyle yapılır; sunucuda elle DELETE yazmayın

**Günlükte aranacak ifadeler**
- `[Maintenance Cleanup]`
- `[Bakim] Temizlik hatasi:`
- `Veritabani saglik bilgisi alinamadi.`
- `database_maintenance_cleanup_requested`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Maintenance Cleanup\|Bakim'"
```

**İlgili testler:** [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js)

**Bkz.:** [akis-kayit-eposta-dogrulama](#akis-kayit-eposta-dogrulama), [akis-cihaz-baglanti-gunlukleri](#akis-cihaz-baglanti-gunlukleri)

<a id="akis-cihaz-baglanti-gunlukleri"></a>
### akis-cihaz-baglanti-gunlukleri · Cihaz bağlantı akışı bozuldu (uçtan uca): cihaz fiilen çevrimiçi ama uygulamada çevrimdışı görünüyor (ya da tersi) ya da "Bağlantı günlükleri" boş/eksik

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:464](../../cihaz_kontrol/include/mqtt_baglanti.h#L464) | <code>const bool baglandi = client.connect(clientId.c_str(), mqttUser.c_str(), mqttPass.c_str()…</code> | Adım 1 — cihaz (MQTT bağlantısı): bağlanırken LWT (retained "offline") device/<UID>/availability konusuna kaydedilir. Bu satırdaki istemci kimliği/kullanıcı Mosquitto ACL ile uyuşmazsa cihaz hiç bağlanamaz. Sahadaki davranışı bozmayın (ESP32-C3). |
| [cihaz_kontrol/include/mqtt_baglanti.h:488](../../cihaz_kontrol/include/mqtt_baglanti.h#L488) | <code>mqttPublishAvailability("online");</code> | Adım 2 — cihaz (MQTT yayını): bağlanınca retained "online" yayınlanır; OTA öncesi temiz kapanışta LWT tetiklenmediği için "offline" açıkça yayınlanır (mqttOtaOncesiKapat). |
| [server/src/mqtt_bridge.js:1027](../../server/src/mqtt_bridge.js#L1027) | <code>client.subscribe('device/+/availability', { qos: 1 });</code> | Adım 3 — MQTT (köprü aboneliği): sunucu tüm cihazların availability konusuna abonedir; abonelik ya da köprü bağlantısı yoksa durum hiç güncellenmez. |
| [server/src/mqtt_bridge.js:845](../../server/src/mqtt_bridge.js#L845) | <code>if (kind === 'availability') {</code> | Adım 4 — sunucu (köprü): "online" ise online_since atanır ve yerel kontrol anahtarı eşitlenir; "online"dan "offline"a geçişte recordDeviceOfflineTransition çağrılır (yalnızca önceki durum online ise). |
| [server/src/mqtt_bridge.js:400](../../server/src/mqtt_bridge.js#L400) | <code>is_online = $2,</code> | Adım 5 — veritabanı (durum): persistRuntimeStatus device_runtime_status'a yazar ve devices.is_online / last_online_at / last_offline_at alanlarını günceller; yazma hatası "db_error" olarak /health'te görünür. |
| [server/src/mqtt_bridge.js:700](../../server/src/mqtt_bridge.js#L700) | <code>async function recordDeviceOfflineTransition(status, reason = 'Wi-Fi/MQTT Bağlantısı Kesi…</code> | Adım 6 — sunucu (günlük kuralı): çevrimiçi kalma süresi online_since ya da devices.last_online_at'ten hesaplanır; yalnızca KOPMA (offline) için satır yazılır. Sunucu yeniden başladığında online_since bellekte olmadığından DB'deki last_online_at kullanılır. |
| [server/src/mqtt_bridge.js:726](../../server/src/mqtt_bridge.js#L726) | <code>INSERT INTO device_connectivity_logs (</code> | Adım 7 — veritabanı (günlük): device_connectivity_logs satırı (event_type offline, süre, neden, Wi-Fi RSSI/yüzde, yerel IP). Hata yalnızca "Offline baglanti log DB kayit hatasi:" olarak günlüğe düşer. |
| [server/src/services/device_service.js:757](../../server/src/services/device_service.js#L757) | <code>export async function getDeviceConnectivityLogs({</code> | Adım 8 — sunucu (servis): is_online değeri mqtt_connected öncelikli hesaplanır; toplam sayı + sayfalı günlük (en yeni önce, sayfa boyutu en çok 100) ve "şu an çevrimiçi süresi" döner. |
| [server/src/routes/admin_routes.js:1551](../../server/src/routes/admin_routes.js#L1551) | <code>adminRouter.get('/admin/devices/:deviceUid/connectivity-logs', authRequired, requireSuper…</code> | Adım 9 — sunucu (rota): yalnızca süper kullanıcı; UID 6 karakterden kısaysa 400, cihaz yoksa 404. |
| [lib/services/auth_api.dart:2857](../../lib/services/auth_api.dart#L2857) | <code>final uri = Uri.parse('$baseUrl/admin/devices/${Uri.encodeComponent(deviceUid)}/connectiv…</code> | Adım 10 — uygulama (HTTP): GET /admin/devices/<UID>/connectivity-logs?page&page_size; yanıt DeviceConnectivityReport modeline çevrilir. |
| [lib/ui/widgets/device_connectivity_logs_accordion.dart:79](../../lib/ui/widgets/device_connectivity_logs_accordion.dart#L79) | <code>final (result, error) = await widget.authService.getDeviceConnectivityLogs(</code> | Adım 11 — uygulama (ekran): şirket cihaz kartındaki akordeon açılınca günlük sayfalı yüklenir; hata mesajı ekranda gösterilir, yarış için istek sayacı kullanılır. |
| [server/src/services/maintenance_service.js:102](../../server/src/services/maintenance_service.js#L102) | <code>DELETE FROM device_connectivity_logs</code> | Adım 12 — bakım: 30 günden eski bağlantı günlükleri günlük temizlikte silinir (bkz. akis-bakim-temizlik-health). |

**Olası nedenler**
- Adım 1-2: cihaz MQTT'ye bağlanamıyor (Wi-Fi yok, broker/TLS, kullanıcı/parola ya da ACL hatası); LWT süresi (keepalive) dolmadan kopma henüz görünmez
- Adım 3-4: sunucu köprüsü bağlı değil/abonelik düşmüş
- Adım 5: veritabanı yazma hatası (/health mqtt.last_error = db_error); cihaz daha önce is_online=true kalmış olabilir
- Adım 6-7: günlük yalnızca offline geçişinde yazılır; cihaz hiç "online"a düşmediyse ya da sunucu offline mesajını önceki durum bilinmeden aldıysa satır oluşmaz
- Adım 9-11: süper kullanıcı değil; cihaz UID yanlış; uygulama eski sürümle farklı yanıt bekliyor
- Günlüğün eski kayıtları 30 gün sonra bilinçli silinir (adım 12)

**Adım adım kontrol**
- Cihaz seri günlüğünde "MQTT baglaniyor (id=SmartKeyPass-..." ve "baglandi" ya da hata kodunu görün
- Köprü: GET /health -> mqtt.connected true mu, last_error ne
- Durum: SELECT mqtt_connected, last_seen_at, last_event FROM device_runtime_status WHERE device_uid = '<UID>'; SELECT is_online, last_online_at, last_offline_at FROM devices WHERE device_uid = '<UID>';
- Günlük: SELECT event_type, offline_at, duration_seconds, reason FROM device_connectivity_logs WHERE device_uid = '<UID>' ORDER BY created_at DESC LIMIT 10;
- Sunucu günlüğünde "Offline baglanti log DB kayit hatasi:" ve "[MQTT bridge] " satırlarını arayın
- Uygulamada boş liste ama DB doluysa günlükte "[API] GET /admin/devices/<UID>/connectivity-logs -> <durum>" satırına bakın

**Günlükte aranacak ifadeler**
- `Offline baglanti log DB kayit hatasi:`
- `[MQTT bridge] `
- `Device status DB yazilamadi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'baglanti log\|MQTT bridge'"
```

**İlgili testler:** [server/test/devices_device_service.test.js](../../server/test/devices_device_service.test.js), [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js), [server/test/devices_mqtt_acl.test.js](../../server/test/devices_mqtt_acl.test.js)

**Bkz.:** [akis-bulut-kapi-acma](#akis-bulut-kapi-acma), [akis-bakim-temizlik-health](#akis-bakim-temizlik-health)

<a id="akis-misafir-gecis"></a>
### akis-misafir-gecis · Misafir/kurye geçişi akışı bozuldu (uçtan uca): geçiş bağlantısı oluşturulamıyor ya da misafir bağlantıyı açınca "iptal/süresi dolmuş/kullanılmış/cihaz bağlı değil" deyip kapı açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/dialogs/create_guest_pass_dialog.dart:127](../../lib/ui/dialogs/create_guest_pass_dialog.dart#L127) | <code>final (pass, error) = await widget.authService.createGuestPass(</code> | Adım 1 — uygulama (ekran): kapı, başlık, tür (tek kullanımlık / süreli), süre ve kullanım sayısı AuthService.createGuestPass'a verilir; dönen web_url paylaşılır. |
| [lib/services/auth_api.dart:4272](../../lib/services/auth_api.dart#L4272) | <code>path: '/app/guest-passes',</code> | Adım 2 — uygulama (HTTP): POST /app/guest-passes (201 beklenir). Aynı yola GET (liste) ve /app/guest-passes/:id için DELETE (iptal) çağrıları da aynı dosyadadır. |
| [server/src/routes/guest_passes_routes.js:54](../../server/src/routes/guest_passes_routes.js#L54) | <code>guestPassesRouter.post('/app/guest-passes', authRequired, async (req, res) =&gt; {</code> | Adım 3 — sunucu (rota): giriş doğrulanır, normalizeGuestPassInput ile kapı/tür/süre doğrulanır (400); kapıya yetki yoksa 404; sitede misafir geçişi kapalıysa (feature_guest_pass_enabled=false) süper kullanıcı dahil 403 GUEST_DISABLED. |
| [server/src/routes/guest_passes_routes.js:89](../../server/src/routes/guest_passes_routes.js#L89) | <code>INSERT INTO guest_passes (</code> | Adım 4 — veritabanı: 48 karakterlik rastgele token, bitiş zamanı (şimdi + süre) ve max_uses ile guest_passes satırı yazılır; yanıttaki web_url PUBLIC_APP_URL / PUBLIC_BASE_URL (yoksa https://api.gudeteknoloji.com.tr) + /guest/<token> olarak kurulur. |
| [server/src/routes/guest_passes_routes.js:477](../../server/src/routes/guest_passes_routes.js#L477) | <code>guestPassesRouter.get('/guest/:token', async (req, res) =&gt; {</code> | Adım 5 — sunucu (herkese açık sayfa): misafir bağlantıyı tarayıcıda açar; biçimi bozuk ya da kayıtsız token 404 "geçersiz" sayfası, aksi halde durumuna göre açma sayfası (nonce'lu sıkı CSP) döner. Oturum gerekmez. |
| [server/src/utils/guest_pass_utils.js:222](../../server/src/utils/guest_pass_utils.js#L222) | <code>var res = await fetch('/public/guest-pass/' + encodeURIComponent(token) + '/open', { meth…</code> | Adım 6 — tarayıcı (sayfa betiği): "Kapıyı aç" düğmesi POST /public/guest-pass/<token>/open çağırır; dönen JSON hata metni sayfada gösterilir. |
| [server/src/routes/guest_passes_routes.js:221](../../server/src/routes/guest_passes_routes.js#L221) | <code>guestPassesRouter.post('/public/guest-pass/:token/open', doorCommandRateLimiter, async (r…</code> | Adım 7 — sunucu (rota): doorCommandRateLimiter (429), token biçimi (400), geçiş + kapı + site + cihaz tek SQL ile okunur (yoksa 404); site bayrağı kapalıysa 403 GUEST_DISABLED; iptal/süre/tükenme için getGuestPassState -> 410; cihaz atanmamışsa 409. |
| [server/src/routes/guest_passes_routes.js:321](../../server/src/routes/guest_passes_routes.js#L321) | <code>code: 'GUEST_PASS_OWNER_INACTIVE',</code> | Adım 8 — sunucu (oluşturan kontrolü): geçişi oluşturan kullanıcı hâlâ aktif/doğrulanmış/onaylı ve kapıya yetkili olmalı (403 GUEST_PASS_OWNER_INACTIVE / GUEST_PASS_OWNER_NO_ACCESS); üyelik kalkınca tüm linkleri ölür. |
| [server/src/routes/guest_passes_routes.js:364](../../server/src/routes/guest_passes_routes.js#L364) | <code>channel: 'guest',</code> | Adım 9 — sunucu (politika): assertDoorOpenAllowed misafir kanalı kuralını uygular (403 GUEST_DISABLED ya da genel "Bu kapi icin misafir gecisi su anda kullanilamiyor."). |
| [server/src/utils/guest_pass_utils.js:89](../../server/src/utils/guest_pass_utils.js#L89) | <code>export const CLAIM_GUEST_PASS_SQL = `</code> | Adım 10 — veritabanı (atomik hak tüketimi): tek UPDATE ile used_count artar; iptal/süre/limit koşulları UPDATE içindedir, 0 satır dönerse hak başka istekte tüketilmiştir (409 ya da 410). Pulse gönderilemezse RELEASE_GUEST_PASS_SQL hakkı iade eder. |
| [server/src/routes/guest_passes_routes.js:402](../../server/src/routes/guest_passes_routes.js#L402) | <code>requestedBy: `guest:${Number(pass.id)}`,</code> | Adım 11 — MQTT (yayın): publishDoorPulse device/<UID>/cmd konusuna pulse yayınlar (MQTT'ye misafir başlığı gitmez, yalnız geçiş kimliği: guest:<id>); köprü/cihaz yoksa MQTT_BRIDGE_NOT_CONNECTED / DEVICE_OFFLINE -> 503 "Kapi cihazi su anda bagli degil." Cihaz tarafı için akis-bulut-kapi-acma Adım 10-11. |
| [server/src/routes/guest_passes_routes.js:451](../../server/src/routes/guest_passes_routes.js#L451) | <code>triggerType: 'guest_pass',</code> | Adım 12 — veritabanı (günlük): door_access_logs'a "(Gecis Linki)" adıyla guest_pass satırı yazılır; yazma hatası "[guest_passes] acilis kaydi yazilamadi" olarak günlüğe düşer, misafire yine başarı döner. |

**Olası nedenler**
- Adım 3: sitede misafir geçişi kapalı (GUEST_DISABLED) ya da kullanıcının kapıya yetkisi yok
- Adım 4-5: PUBLIC_APP_URL/PUBLIC_BASE_URL yanlış (paylaşılan bağlantı ölü adrese gider); bağlantı eksik kopyalanmış (token biçimi bozuk -> 404)
- Adım 7: geçiş iptal edilmiş/süresi bitmiş/tek kullanımlık ise kullanılmış (410); hız sınırı (429)
- Adım 8: geçişi oluşturan kullanıcı pasife alınmış ya da kapıdan yetkisi alınmış
- Adım 10: iki istek aynı anda geldi (409 "baska bir istekle kullaniliyor"); max_uses doldu
- Adım 11: MQTT köprüsü bağlı değil ya da kapı cihazı çevrimdışı (503); hak iade edilir, tekrar denenebilir
- Adım 11 sonrası: komut gitti ama röle çekmedi (bkz. akis-bulut-kapi-acma Adım 10-11)

**Adım adım kontrol**
- Hata metnini ve durum kodunu not edin (410 = geçiş durumu, 403 = politika/oluşturan, 409 = cihaz atanmamış/yarış, 503 = cihaz bağlı değil)
- Geçiş satırı: SELECT id, door_id, is_active, expires_at, max_uses, used_count, created_by_user_code FROM guest_passes WHERE id = <id>; (token sütununu seçmeyin)
- Site bayrağı: SELECT feature_guest_pass_enabled FROM sites WHERE site_code = <site>;
- Oluşturan kullanıcı: SELECT is_active, email_verified, approval_status FROM users WHERE user_code = <kod>;
- Sunucu günlüğünde "[guest_passes] " satırları (errorId ile) ve "[API] POST /public/guest-pass/... -> <durum>" (token maskelenir)
- Cihaz durumunu akis-cihaz-baglanti-gunlukleri adımlarıyla doğrulayın; kapıyı süper kullanıcıyla uygulamadan açmayı deneyin

**Günlükte aranacak ifadeler**
- `[guest_passes] `
- `[guest_passes] hak iadesi basarisiz`
- `[guest_passes] acilis kaydi yazilamadi`
- `guest_pass_opened`
- `guest_pass_created`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'guest'"
```

**İlgili testler:** [server/test/sites_guest_pass.test.js](../../server/test/sites_guest_pass.test.js), [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js)

**Bkz.:** [akis-bulut-kapi-acma](#akis-bulut-kapi-acma), [akis-cihaz-baglanti-gunlukleri](#akis-cihaz-baglanti-gunlukleri)

<a id="akis-cevrimdisi-kapi-gunlukleri"></a>
### akis-cevrimdisi-kapi-gunlukleri · Çevrimdışı kapı günlüğü akışı bozuldu (uçtan uca): yerel/çevrimdışı yapılan kapı geçişleri uygulamadaki kapı günlüğünde görünmüyor, geç görünüyor ya da tekrarlanıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/offline_log.h:163](../../cihaz_kontrol/include/offline_log.h#L163) | <code>inline void offlineLogEkle(</code> | Adım 1 — cihaz (kayıt): kapı geçişi LittleFS'te /offline_logs.ndjson dosyasına satır olarak eklenir (client_log_id, epoch/boot_ms, trigger_type, ad, daire). Dosya 16 KB aşınca EN ESKİ kayıtlar atılır. Sahadaki biçimi bozmayın (ESP32-C3). |
| [cihaz_kontrol/include/offline_log.h:147](../../cihaz_kontrol/include/offline_log.h#L147) | <code>inline const char* offlineLogTurSecimi(const char* tur) {</code> | Adım 2 — cihaz (tür süzgeci): sunucunun izin listesi dışındaki trigger_type "offline_sync"e çevrilir; aksi halde sunucu kaydı reddeder ve ack ile düşer (veri kaybı). Yeni tür eklerken iki listeyi birlikte güncelleyin. |
| [cihaz_kontrol/include/offline_log.h:407](../../cihaz_kontrol/include/offline_log.h#L407) | <code>inline void offlineLogSenkronizeEt() {</code> | Adım 3 — cihaz (teslim): 3 sn aralıkla; Wi-Fi ve MQTT hazırsa dosya başından en çok ~800 baytlık batch hazırlanıp device/<UID>/logs konusuna QoS0 yayınlanır; ack gelmezse süre katlanarak (15 sn - 10 dk) aynı kayıtlar yeniden yayınlanır. |
| [server/src/mqtt_bridge.js:898](../../server/src/mqtt_bridge.js#L898) | <code>if (kind === 'logs') {</code> | Adım 4 — MQTT (köprü): device/<UID>/logs mesajı handleDeviceLogsMessage'a gider (abonelik ve ACL'de logs yazma izni şarttır). |
| [server/src/mqtt_bridge.js:640](../../server/src/mqtt_bridge.js#L640) | <code>export async function handleDeviceLogsMessage(topicUid, text, deps = {}) {</code> | Adım 5 — sunucu (köprü): JSON ayrıştırılır, aynı batch eşzamanlı işlenmez, insertDeviceLogBatch çağrılır; cihaz henüz siteye atanmamışsa (DEVICE_NOT_ASSIGNED) ack GÖNDERİLMEZ, cihaz kayıtları saklar; hata olursa da ack yoktur. |
| [server/src/services/door_log_service.js:151](../../server/src/services/door_log_service.js#L151) | <code>export function validateDeviceLogEntry(item, { now = Date.now() } = {}) {</code> | Adım 6 — sunucu (doğrulama): her kayıt doğrulanır (izinli trigger_type, client_log_id deseni, zaman); geçersiz kayıt reddedilir ama batch yine ack'lenir. Saati bilinmeyen kayıtların zamanı boot_ms farkıyla son 30 gün tabanına göre kestirilir. |
| [server/src/services/door_log_service.js:551](../../server/src/services/door_log_service.js#L551) | <code>export async function insertDeviceLogBatch({</code> | Adım 7 — veritabanı: cihaz UID'sinden site/kapı çözülür (DEVICE_NOT_FOUND / DEVICE_NOT_ASSIGNED); kayıtlar tek işlemde door_access_logs'a idempotent yazılır (client_log_id benzersiz dizini; yoksa doğal anahtar); tekrar gelenler "duplicate" sayılır. |
| [server/src/mqtt_bridge.js:623](../../server/src/mqtt_bridge.js#L623) | <code>function publishLogsAck(normalizedUid, batchId) {</code> | Adım 8 — MQTT (sunucu -> cihaz): işlem başarılıysa device/<UID>/cmd konusuna {action:"logs_ack", batch_id} yayınlanır; yayın hatası "[MQTT Logs] logs_ack yayinlanamadi" yazar. |
| [cihaz_kontrol/include/mqtt_baglanti.h:386](../../cihaz_kontrol/include/mqtt_baglanti.h#L386) | <code>} else if (action == "logs_ack") {</code> | Adım 9 — cihaz (ack): offlineLogAckIsle batch kimliği bekleyenle eşleşirse o satırları dosyadan siler ve sıradaki batch'i hemen yollar; eşleşmezse (dosya sıkıştırıldı, MQTT yeniden bağlandı) silmez, kayıtlar tekrar gönderilir. |
| [server/src/routes/door_log_routes.js:271](../../server/src/routes/door_log_routes.js#L271) | <code>doorLogRouter.post('/device/sync-logs', authRequired, syncDeviceLogsHandler);</code> | Adım 10 — sunucu (alternatif yol): aynı kayıtlar HTTP ile de yüklenebilir (JWT; süper kullanıcı, site yöneticisi ya da kapıya erişen kullanıcı). İstek en çok 256 KB / 200 kayıt; 404 cihaz/site yok, 403 yetki yok. Uygulamada AuthService.syncDeviceLogs bulunur, ancak arayüzde çağıranı görülmedi. |
| [server/src/routes/door_log_routes.js:106](../../server/src/routes/door_log_routes.js#L106) | <code>doorLogRouter.get('/manager/door-logs', authRequired, requireSiteManager, async (req, res…</code> | Adım 11 — sunucu (okuma): yönetici günlüğü (site kapsamlı); süper kullanıcı için /admin/door-logs aynı dosyadadır; sayfa boyutu en çok 200, opened_at azalan sıra. |
| [lib/ui/widgets/door_logs_accordion.dart:88](../../lib/ui/widgets/door_logs_accordion.dart#L88) | <code>final (result, error) = await service.listDoorAccessLogs(</code> | Adım 12 — uygulama (ekran): kapı günlüğü akordeonu açılınca ya da kapı açıldığında sayfa yüklenir; kayıtlar door_access_logs satırlarının modelidir. Çevrimdışı kayıtlar cihaz geri bağlanıp batch ack'lenince görünür. |

**Olası nedenler**
- Adım 1: cihaz LittleFS başlatılamadı (gOfflineLogFsHazir=false) ya da dosya dolup en eski kayıtlar atıldı
- Adım 3-4: cihaz Wi-Fi/MQTT'ye bağlanamıyor (kayıtlar cihazda bekler); ACL'de logs yazma izni yok
- Adım 5: cihaz henüz bir siteye/kapıya atanmamış (ack yok; atanınca kayıtlar işlenir); köprü bağlı değil
- Adım 6: trigger_type izin listesinde değil ya da client_log_id deseni bozuk (kayıt reddedilir)
- Adım 7: kayıt "duplicate" sayıldı (aynı client_log_id daha önce yazılmış) ya da DB hatası (ack yok, cihaz yeniden dener)
- Adım 9: ack cihaza ulaşmadı (QoS/bağlantı) -> aynı kayıtlar yeniden gönderilir, idempotent olduğundan çift satır oluşmaz
- Adım 12: kayıt 30 günden eski (bakım temizliği siler) ya da uygulamada yanlış site/kapı filtresi seçili

**Adım adım kontrol**
- Cihaz seri günlüğü: "Offline Log: kapi gecisi kaydedildi.", "Offline Log: batch yayinlandi, ack bekleniyor", "Offline Log: batch sunucu tarafindan onaylandi"
- Sunucu günlüğü: "[MQTT Logs] Cihaz <UID> batch=<n>: eklenen=.. tekrar=.. reddedilen=.." satırı hangi adımda durduğunu söyler
- Atama yoksa "henuz bir siteye atanmamis" uyarısını arayın; cihazı kapıya atayın (akis-cihaz-baglanti-gunlukleri ile bağlantıyı doğrulayın)
- DB: SELECT opened_at, trigger_type, user_name, door_name FROM door_access_logs WHERE device_uid = '<UID>' ORDER BY opened_at DESC LIMIT 20;
- Reddedilen sayısı yüksekse trigger_type değerlerini ve cihaz saatini (epoch=0 / boot_ms) inceleyin
- Uygulamada görünmüyor ama DB dolu ise "[API] GET /manager/door-logs -> <durum>" (ya da /admin/door-logs) ve seçili site/kapı filtresine bakın

**Günlükte aranacak ifadeler**
- `Offline Log: kapi gecisi kaydedildi.`
- `Offline Log: batch yayinlandi, ack bekleniyor (satir=`
- `Offline Log: batch sunucu tarafindan onaylandi, yerel kayitlar silindi.`
- `[MQTT Logs] Cihaz `
- `[MQTT Logs] logs_ack yayinlanamadi`
- `Error syncing device offline logs`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'MQTT Logs'"
```

**İlgili testler:** [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js), [server/test/devices_door_log_service.test.js](../../server/test/devices_door_log_service.test.js), [server/test/devices_sync_logs_route.test.js](../../server/test/devices_sync_logs_route.test.js), [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp)

**Bkz.:** [akis-yerel-kapi-acma](#akis-yerel-kapi-acma), [akis-cihaz-baglanti-gunlukleri](#akis-cihaz-baglanti-gunlukleri)

