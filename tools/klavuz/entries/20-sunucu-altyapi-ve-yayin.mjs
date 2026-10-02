// Alan: sunucu altyapısı ve canlı yayın (açılış, veritabanı şeması, MQTT, OTA sunumu, dağıtım, operasyon).
// Kural: satır numarası YOK; her ref {file, find, note}. Kontrol: node tools/klavuz/build.mjs --check --only 20-sunucu-altyapi-ve-yayin

// Canlı sunucuya salt-okunur erişim önekleri (SSH 22667, kullanıcı salihceylan; anahtarla giriş).
const SSH = 'ssh -p 22667 salihceylan@178.210.161.55';
const APP = '/var/www/site_kapi_kontrol/server';
// SQL, uzak psql'e stdin'den (<<<) verilir: tırnak karmaşası olmaz; yalnız SELECT yazılır.
const PSQL = `${SSH} 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol'`;

export default {
  title: 'Sunucu altyapısı ve yayın — açılış, veritabanı şeması, MQTT, OTA, dağıtım',
  intro:
    'Bu bölüm API sürecinin ayağa kalkması (PM2, ortam doğrulaması, /health), veritabanı şeması (db.js, migrations), ' +
    'MQTT köprüsü ve mosquitto ACL senkronu, OTA manifest/dosya sunumu ve VPS dağıtım/geri alma sorunlarını kapsar. ' +
    'Önce `pm2 logs kapi-api --lines 100 --nostream` çıktısındaki İLK hata satırına ve `curl -s https://api.gudeteknoloji.com.tr/health` yanıtına bakın.',
  files: [
    { file: 'server/src/server.js', note: 'Açılış sırası (ortam → şema → MQTT → temizlik → dinleme), düzgün kapanma, bakım zamanlayıcısı' },
    { file: 'server/src/config/env.js', note: 'Ortam doğrulaması: JWT_SECRET hatası sunucuyu durdurur; diğerleri yalnız uyarıdır' },
    { file: 'server/src/config/process_handlers.js', note: 'unhandledRejection (süreç sürer) ve uncaughtException (exit 1, PM2 yeniden başlatır)' },
    { file: 'server/src/db.js', note: 'Bağlantı havuzu/zaman aşımları, checkDbConnection ve ensureDbSchema (açılışta çalışan EKLEYİCİ şema)' },
    { file: 'server/migrations/001_init.sql', note: 'Numaralı SQL migration zincirinin başı (001-028); docker initdb.d ve migrate.js bunları kullanır' },
    { file: 'server/scripts/migrate.js', note: 'Elle çalıştırılan migration koşucusu (--status / --apply / --baseline); schema_migrations tablosu' },
    { file: 'server/scripts/_dev_guard.js', note: 'apply_*.js / check_*.js / test_*.js geliştirme betiklerini ALLOW_DEV_SCRIPTS=1 yoksa durdurur' },
    { file: 'server/src/mqtt_bridge.js', note: 'API ↔ broker köprüsü: konular, cihaz durumu, komut yayını, offline log alımı, /health mqtt alanı' },
    { file: 'server/src/mqtt_acl_sync.js', note: 'Mosquitto ACL metni üretimi ve senkron komutunun (MQTT_SYNC_COMMAND) çalıştırılması' },
    { file: 'server/scripts/sync_mqtt_acl.js', note: 'DB\'deki cihazlardan passwd + acl dosyalarını yazar (--dry-run ile yalnız çıktı)' },
    { file: 'server/scripts/kapi-mqtt-sync.sh', note: 'Root sarmalayıcı: sync_mqtt_acl.js çalıştırır, mosquitto\'yu reload/restart eder' },
    { file: 'server/src/routes/firmware_routes.js', note: 'GET /health, OTA manifest ve .bin dosyası sunumu' },
    { file: 'server/src/services/firmware_manifest_service.js', note: 'Manifest hedefi / cihaz donanım hedefi uyum kontrolü, UID ve IP doğrulama' },
    { file: 'server/scripts/trigger_ota.js', note: 'Tek cihaza MQTT ota_check komutu gönderen elle betik' },
    { file: 'server/src/services/maintenance_service.js', note: 'Rutin temizlik (süresi dolmuş token/kod, 30 günden eski loglar) ve veritabanı sağlık özeti' },
    { file: 'server/src/services/device_service.js', note: 'OTA iş kaydı (ota_update_jobs) oluşturma/bitirme' },
    { file: 'server/src/middlewares/request_logger.js', note: '[API] istek günlüğü biçimi; /health günlüğe yazılmaz' },
    { file: 'deploy/README.md', note: 'Canlı dağıtım adımları ve geri alma' },
    { file: 'deploy/remote_deploy.sh', note: 'Sunucuda prepare / activate / rollback aşamaları (yedek, node --check, PM2 restart, /health)' },
    { file: 'deploy/remote_verify.sh', note: 'Dağıtım sonrası doğrulama (sunucunun kendi loopback\'i üzerinden)' },
    { file: 'deploy/remote_audit.sh', note: 'Salt-okunur canlı denetim (.env değerleri maskeli)' },
    { file: 'server/ecosystem.config.cjs', note: 'PM2 tanımı: tek kopya, bellek sınırı, yeniden başlatma politikası, kill_timeout' },
    { file: 'docker-compose.yml', note: 'PostgreSQL konteyneri (site_kapi_kontrol_postgres), initdb.d ve healthcheck' },
    { file: 'server/.env.example', note: 'Sunucu ortam değişkenleri şablonu (DB_*, MQTT_*, MQTT_SYNC_*, FIRMWARE_DIR); gerçek değerler yalnız sunucudaki .env\'de' },
    { file: 'sunucu_kurulum.txt', note: 'VPS kurulumu: PM2, Docker Postgres, nginx, SSL, migrate komutları' },
    { file: 'MQTT_kurulum.txt', note: 'Mosquitto kurulumu, ACL, kapi-mqtt-sync sudoers, sık hatalar' },
    { file: 'OTA_KURULUM.txt', note: 'OTA akışı, klasör düzeni, manifest alanları ve kuralları' },
  ],
  entries: [
    {
      id: 'altyapi-api-acilmiyor-pm2-dongu',
      symptom: 'API açılmıyor / PM2 "kapi-api" sürekli yeniden başlıyor (status errored, restarts sayısı artıyor)',
      keywords: ['pm2', 'restart', 'errored', 'açılmıyor', 'crash', 'startup failed', 'kapi-api', 'exit 1', 'döngü', '502'],
      refs: [
        { file: 'server/src/server.js', find: 'async function startServer()',
          note: 'Açılış sırası: checkEnvOrExit → ensureDbSchema → startMqttBridge → temizlik → dinleme; ilk başarısız adım süreci düşürür' },
        { file: 'server/src/server.js', find: "console.error('Server startup failed:', error);",
          note: 'Açılışta fırlatılan her hata (DB\'ye ulaşılamadı, şema SQL hatası) buraya düşer, ardından process.exit(1)' },
        { file: 'server/src/server.js', find: 'checkEnvOrExit();',
          note: 'Ortam doğrulaması DB\'den ÖNCE çalışır; JWT_SECRET hatasında DB\'ye hiç bağlanılmaz' },
        { file: 'server/src/config/process_handlers.js', find: 'const onUncaughtException = (error) => {',
          note: 'Yakalanmamış istisna: günlüğe yazar ve exit(1); PM2 yeniden başlatır' },
        { file: 'server/ecosystem.config.cjs', find: "min_uptime: '15s',",
          note: '15 sn dayanmayan çıkışlar "kararsız" sayılır ve yeniden başlatma sayacını artırır' },
        { file: 'server/ecosystem.config.cjs', find: 'max_restarts: 30,',
          note: 'Üst üste kararsız yeniden başlatma sınırı; aşılınca PM2 süreci errored bırakır' },
      ],
      causes: [
        'Ortam doğrulaması başarısız: JWT_SECRET boş/yer tutucu → "[ENV] HATA" (altyapi-env-hata-sunucu-baslamiyor)',
        'Veritabanına ulaşılamıyor (konteyner kapalı, DB_* yanlış, parola değişmiş) → "Server startup failed:" (altyapi-db-baglanti-reddi)',
        'ensureDbSchema sırasında SQL hatası (yinelenen veri, yetki) (altyapi-sema-baslangic-sql-hatasi)',
        'Boş veritabanı: "users" tablosu yok (altyapi-sema-users-yok)',
        '8080 portu başka süreçte (altyapi-port-8080-kullanimda)',
      ],
      checks: [
        'pm2 logs içinde EN ESKİ yeni-başlatma hatasını bulun: "Server startup failed:", "[ENV] HATA:" ya da "[uncaughtException]"; sonraki yeniden denemeler aynı hatayı tekrarlar.',
        '"[ENV] HATA" ise .env\'i düzeltin (değerleri yazdırmayın); DB hatasıysa docker ps ile konteyneri doğrulayın; şema hatasıysa hata satırındaki indeks/kısıt adını arayın.',
        'Sunucu içinden 127.0.0.1:8080/health yanıt veriyorsa sorun nginx/DNS tarafındadır (altyapi-nginx-502-504).',
      ],
      logs: ['Server startup failed:', '[ENV] HATA:', 'Gecersiz yapilandirma nedeniyle sunucu baslatilmadi.', '[uncaughtException]'],
      commands: [
        `${SSH} "pm2 status | grep kapi-api"`,
        `${SSH} "pm2 describe kapi-api | grep -E 'status|restarts|uptime|script path|exec cwd'"`,
        `${SSH} "pm2 logs kapi-api --lines 100 --nostream | grep -a -E 'Server startup failed|\\[ENV\\]|uncaughtException' | cut -c1-220"`,
      ],
      tests: ['server/test/core_startup.test.js'],
      related: ['altyapi-env-hata-sunucu-baslamiyor', 'altyapi-db-baglanti-reddi', 'altyapi-sema-baslangic-sql-hatasi', 'altyapi-port-8080-kullanimda', 'altyapi-pm2-bellek-ve-restart'],
    },
    {
      id: 'altyapi-env-hata-sunucu-baslamiyor',
      symptom: 'Günlükte "[ENV] HATA: JWT_SECRET tanimli degil veya yer tutucu bir deger" ve sunucu açılmıyor',
      keywords: ['JWT_SECRET', 'env', 'yer tutucu', 'placeholder', 'baslatilmadi', '.env', 'ortam degiskeni'],
      refs: [
        { file: 'server/src/config/env.js', find: 'JWT_SECRET tanimli degil veya yer tutucu',
          note: 'Hata iletisinin üretildiği yer: secret boş ya da yer tutucuysa evaluateJwtSecret ok:false döner' },
        { file: 'server/src/config/env.js', find: 'export function isPlaceholderSecret(value) {',
          note: 'Hangi değerlerin "yer tutucu" sayıldığı (PLACEHOLDER_EXACT / PLACEHOLDER_PATTERNS: change_this_secret, your-secret, <JWT_SECRET> ...)' },
        { file: 'server/src/config/env.js', find: 'const jwtCheck = evaluateJwtSecret(env.JWT_SECRET);',
          note: 'validateEnv içinde TEK "errors" kaynağı budur; diğer eksikler yalnız uyarıdır' },
        { file: 'server/src/server.js', find: 'function checkEnvOrExit() {',
          note: 'errors doluysa [ENV] HATA yazar ve process.exit(1); uyarılar [ENV] UYARI olarak yazılır' },
      ],
      causes: [
        'server/.env içinde JWT_SECRET yok ya da boş',
        'Değer bilinen bir yer tutucu (change_this_secret, secret, test, <...>, ${...}, xxx...)',
        'Süreç yanlış dizinden başlatıldı: dotenv .env\'i çalışma dizininde arar (ecosystem cwd = server/)',
      ],
      checks: [
        '.env içeriğini ASLA yazdırmayın; yalnız uzunluk bakın: deploy/remote_audit.sh "kritik uzunluklar" bölümü JWT_SECRET uzunluğunu verir.',
        'Düzeltmeden sonra `pm2 restart kapi-api --update-env` ve /health.',
      ],
      logs: ['[ENV] HATA:', 'Gecersiz yapilandirma nedeniyle sunucu baslatilmadi.'],
      commands: [
        `${SSH} 'bash -s' < deploy/remote_audit.sh   # salt-okunur, .env değerleri maskeli (JWT_SECRET uzunluk=...)`,
      ],
      tests: ['server/test/core_startup.test.js'],
      related: ['altyapi-api-acilmiyor-pm2-dongu', 'altyapi-env-uyari-jwt-kisa', 'altyapi-env-degisikligi-etkisiz'],
    },
    {
      id: 'altyapi-env-uyari-jwt-kisa',
      symptom: 'Günlükte "[ENV] UYARI: JWT_SECRET 20 karakter; en az 32 karakter onerilir" (sunucu açılıyor)',
      keywords: ['JWT_SECRET', 'uyarı', '20 karakter', '32 karakter', 'oturum geçersiz', 'JWT_EXPIRES_IN'],
      refs: [
        { file: 'server/src/config/env.js', find: 'if (length < MIN_RECOMMENDED_JWT_SECRET_LENGTH) {',
          note: '32 karakterden kısa secret yalnız UYARI üretir (ok:true); sunucu açılır' },
        { file: 'server/src/config/env.js', find: 'JWT_EXPIRES_IN gecersiz bicimde',
          note: 'JWT_EXPIRES_IN biçimi hatalıysa (30d, 12h gibi olmalı) yalnız uyarı; token üretimi başarısız olabilir' },
        { file: 'server/src/server.js', find: 'console.warn(`[ENV] UYARI: ${warning}`);',
          note: 'Tüm uyarıların yazıldığı yer; secret değeri asla yazılmaz (yalnız uzunluk)' },
        { file: 'deploy/README.md', find: 'Canlı `JWT_SECRET` (≥32 karakter)',
          note: 'Canlıdaki secret/süre/NODE_ENV kararları kullanıcıya aittir; kendiliğinden değiştirilmez' },
      ],
      causes: [
        'Canlı .env\'deki secret 20 karakter (kullanıcı kararıyla değiştirilmedi); bu bir arıza değil, bilinen uyarıdır',
        'Secret değiştirilirse mevcut TÜM oturum belirteçleri geçersiz olur (kullanıcılar yeniden giriş yapar)',
      ],
      checks: [
        'Uyarı yalnız bilgidir; sunucu çalışıyorsa işlem gerekmez. Değiştirme kararı bakım penceresinde, kullanıcı onayıyla alınır.',
      ],
      logs: ['[ENV] UYARI:', 'karakter onerilir'],
      tests: ['server/test/core_startup.test.js'],
      related: ['altyapi-env-hata-sunucu-baslamiyor', 'altyapi-env-uyari-eksik-ayarlar'],
    },
    {
      id: 'altyapi-env-uyari-eksik-ayarlar',
      symptom: 'Günlükte "[ENV] UYARI: Veritabani/MQTT/SMTP ayarlari eksik", "COMPANY_API_KEY tanimli degil", "CORS allowlist bos" ya da "NODE_ENV=production degil"',
      keywords: ['env uyarı', 'DB_HOST', 'MQTT_HOST', 'SMTP', 'COMPANY_API_KEY', 'CORS', 'NODE_ENV', 'eksik ayar'],
      refs: [
        { file: 'server/src/config/env.js', find: "const missingDb = ['DB_HOST'",
          note: 'DB_HOST/DB_NAME/DB_USER/DB_PASSWORD eksikse uyarı (sunucu yine de başlar; DB bağlantısı sonra hata verir)' },
        { file: 'server/src/config/env.js', find: "const missingMqtt = ['MQTT_HOST'",
          note: 'MQTT_HOST/MQTT_USER/MQTT_PASSWORD eksikse uyarı: cihaz komutları çalışmaz' },
        { file: 'server/src/config/env.js', find: "const missingSmtp = ['SMTP_HOST'",
          note: 'SMTP eksikse e-posta (doğrulama kodu, şifre sıfırlama, davet) gönderilemez' },
        { file: 'server/src/config/env.js', find: 'COMPANY_API_KEY tanimli degil;',
          note: 'Anahtar yoksa /api/company/* yalnız super_user JWT ile çalışır (şirket aracı X-Company-Key kullanamaz)' },
        { file: 'server/src/config/env.js', find: 'CORS allowlist bos',
          note: 'CORS_ORIGINS/PUBLIC_APP_URL/PUBLIC_BASE_URL üçü de boşsa tarayıcı tabanlı cross-origin istekler reddedilir' },
        { file: 'server/src/config/env.js', find: 'NODE_ENV=production degil',
          note: 'NODE_ENV production değilse yalnız uyarı (hata yanıtları ortamdan bağımsız güvenlidir)' },
        { file: 'server/src/server.js', find: 'console.warn(`[CORS] Gecersiz origin girdisi yok sayildi: ${entry}`);',
          note: 'CORS_ORIGINS içindeki geçersiz girdi (şema yok, * vb.) sessizce atılmaz; burada loglanır' },
      ],
      causes: [
        'İlgili anahtar sunucudaki server/.env dosyasında yok/boş',
        'PM2 yeniden başlatılırken .env değişikliği okunmadı (altyapi-env-degisikligi-etkisiz)',
      ],
      checks: [
        'Hangi anahtarın eksik olduğu uyarı metninde yazar; değerini değil yalnız varlığını doğrulayın: deploy/remote_audit.sh ".env anahtarlari (DEGER YOK)" bölümü.',
        'MQTT eksikse /health mqtt.configured:false görünür (altyapi-health-mqtt-yapilandirilmamis).',
      ],
      logs: ['Veritabani ayarlari eksik:', 'MQTT ayarlari eksik:', 'SMTP ayarlari eksik:', 'CORS allowlist bos'],
      commands: [
        `${SSH} "pm2 logs kapi-api --lines 200 --nostream | grep -a 'UYARI' | cut -c1-200"`,
      ],
      tests: ['server/test/core_startup.test.js', 'server/test/core_cors.test.js'],
      related: ['altyapi-env-uyari-jwt-kisa', 'altyapi-health-mqtt-yapilandirilmamis'],
    },
    {
      id: 'altyapi-env-degisikligi-etkisiz',
      symptom: '.env\'i değiştirdim ama canlı API eski değeri kullanıyor (yeni MQTT/SMTP/anahtar etkisiz)',
      keywords: ['.env', 'update-env', 'pm2 restart', 'dotenv', 'değişiklik etkisiz', 'ortam değişkeni'],
      refs: [
        { file: 'server/src/server.js', find: 'dotenv.config();',
          note: '.env yalnız süreç AÇILIRKEN okunur; dotenv varsayılanı, süreç ortamında zaten tanımlı değişkenin üzerine YAZMAZ' },
        { file: 'deploy/README.md', find: 'pm2 restart kapi-api --update-env',
          note: 'Dağıtım sonrası etkinleştirme PM2\'yi --update-env ile yeniden başlatır' },
        { file: 'server/ecosystem.config.cjs', find: 'Gizli degerler BURAYA yazilmaz',
          note: 'Gizli değerler ecosystem\'e değil server/.env\'e yazılır; cwd = server/ olduğu için dotenv bulur' },
      ],
      causes: [
        'API yeniden başlatılmadı: .env değişikliği çalışan sürece yansımaz',
        'Aynı değişken PM2 ortamında/kabukta zaten tanımlıydı; dotenv onu ezmez',
        'Yanlış dosya düzenlendi (canlı yol /var/www/site_kapi_kontrol/server/.env)',
      ],
      checks: [
        'Düzenlemeden sonra: pm2 restart kapi-api --update-env ve pm2 logs ile "[ENV]" satırlarına bakın.',
        'Sır basmayın: .env\'i cat etmeyin, `source` ETMEYİN (boşluklu değerler komut olarak çalışır); yalnız deploy/remote_audit.sh çıktısına bakın.',
      ],
      commands: [
        `${SSH} "pm2 restart kapi-api --update-env && sleep 10 && curl -s http://127.0.0.1:8080/health"   # DEĞİŞTİRİR: canlı API yeniden başlar`,
      ],
      related: ['altyapi-env-hata-sunucu-baslamiyor', 'altyapi-env-uyari-eksik-ayarlar'],
    },
  ],
};
