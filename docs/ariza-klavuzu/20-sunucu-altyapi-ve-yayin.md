# Sunucu altyapısı ve yayın — açılış, veritabanı şeması, MQTT, OTA, dağıtım

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm API sürecinin ayağa kalkması (PM2, ortam doğrulaması, /health), veritabanı şeması (db.js, migrations), MQTT köprüsü ve mosquitto ACL senkronu, OTA manifest/dosya sunumu ve VPS dağıtım/geri alma sorunlarını kapsar. Önce `pm2 logs kapi-api --lines 100 --nostream` çıktısındaki İLK hata satırına ve `curl -s https://api.gudeteknoloji.com.tr/health` yanıtına bakın.

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [server/src/server.js](../../server/src/server.js) | Açılış sırası (ortam → şema → MQTT → temizlik → dinleme), düzgün kapanma, bakım zamanlayıcısı |
| [server/src/config/env.js](../../server/src/config/env.js) | Ortam doğrulaması: JWT_SECRET hatası sunucuyu durdurur; diğerleri yalnız uyarıdır |
| [server/src/config/process_handlers.js](../../server/src/config/process_handlers.js) | unhandledRejection (süreç sürer) ve uncaughtException (exit 1, PM2 yeniden başlatır) |
| [server/src/db.js](../../server/src/db.js) | Bağlantı havuzu/zaman aşımları, checkDbConnection ve ensureDbSchema (açılışta çalışan EKLEYİCİ şema) |
| [server/migrations/001_init.sql](../../server/migrations/001_init.sql) | Numaralı SQL migration zincirinin başı (001-028); docker initdb.d ve migrate.js bunları kullanır |
| [server/scripts/migrate.js](../../server/scripts/migrate.js) | Elle çalıştırılan migration koşucusu (--status / --apply / --baseline); schema_migrations tablosu |
| [server/scripts/_dev_guard.js](../../server/scripts/_dev_guard.js) | apply_*.js / check_*.js / test_*.js geliştirme betiklerini ALLOW_DEV_SCRIPTS=1 yoksa durdurur |
| [server/src/mqtt_bridge.js](../../server/src/mqtt_bridge.js) | API ↔ broker köprüsü: konular, cihaz durumu, komut yayını, offline log alımı, /health mqtt alanı |
| [server/src/mqtt_acl_sync.js](../../server/src/mqtt_acl_sync.js) | Mosquitto ACL metni üretimi ve senkron komutunun (MQTT_SYNC_COMMAND) çalıştırılması |
| [server/scripts/sync_mqtt_acl.js](../../server/scripts/sync_mqtt_acl.js) | DB'deki cihazlardan passwd + acl dosyalarını yazar (--dry-run ile yalnız çıktı) |
| [server/scripts/kapi-mqtt-sync.sh](../../server/scripts/kapi-mqtt-sync.sh) | Root sarmalayıcı: sync_mqtt_acl.js çalıştırır, mosquitto'yu reload/restart eder |
| [server/src/routes/firmware_routes.js](../../server/src/routes/firmware_routes.js) | GET /health, OTA manifest ve .bin dosyası sunumu |
| [server/src/services/firmware_manifest_service.js](../../server/src/services/firmware_manifest_service.js) | Manifest hedefi / cihaz donanım hedefi uyum kontrolü, UID ve IP doğrulama |
| [server/scripts/trigger_ota.js](../../server/scripts/trigger_ota.js) | Tek cihaza MQTT ota_check komutu gönderen elle betik |
| [server/src/services/maintenance_service.js](../../server/src/services/maintenance_service.js) | Rutin temizlik (süresi dolmuş token/kod, 30 günden eski loglar) ve veritabanı sağlık özeti |
| [server/src/services/device_service.js](../../server/src/services/device_service.js) | OTA iş kaydı (ota_update_jobs) oluşturma/bitirme |
| [server/src/middlewares/request_logger.js](../../server/src/middlewares/request_logger.js) | [API] istek günlüğü biçimi; /health günlüğe yazılmaz |
| [deploy/README.md](../../deploy/README.md) | Canlı dağıtım adımları ve geri alma |
| [deploy/remote_deploy.sh](../../deploy/remote_deploy.sh) | Sunucuda prepare / activate / rollback aşamaları (yedek, node --check, PM2 restart, /health) |
| [deploy/remote_verify.sh](../../deploy/remote_verify.sh) | Dağıtım sonrası doğrulama (sunucunun kendi loopback'i üzerinden) |
| [deploy/remote_audit.sh](../../deploy/remote_audit.sh) | Salt-okunur canlı denetim (.env değerleri maskeli) |
| [server/ecosystem.config.cjs](../../server/ecosystem.config.cjs) | PM2 tanımı: tek kopya, bellek sınırı, yeniden başlatma politikası, kill_timeout |
| [docker-compose.yml](../../docker-compose.yml) | PostgreSQL konteyneri (site_kapi_kontrol_postgres), initdb.d ve healthcheck |
| [server/.env.example](../../server/.env.example) | Sunucu ortam değişkenleri şablonu (DB_*, MQTT_*, MQTT_SYNC_*, FIRMWARE_DIR); gerçek değerler yalnız sunucudaki .env'de |
| [sunucu_kurulum.txt](../../sunucu_kurulum.txt) | VPS kurulumu: PM2, Docker Postgres, nginx, SSL, migrate komutları |
| [MQTT_kurulum.txt](../../MQTT_kurulum.txt) | Mosquitto kurulumu, ACL, kapi-mqtt-sync sudoers, sık hatalar |
| [OTA_KURULUM.txt](../../OTA_KURULUM.txt) | OTA akışı, klasör düzeni, manifest alanları ve kuralları |

## Bu bölümdeki girişler (59)

- [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu) — API açılmıyor / PM2 "kapi-api" sürekli yeniden başlıyor (status errored, restarts sayısı artıyor)
- [altyapi-env-hata-sunucu-baslamiyor](#altyapi-env-hata-sunucu-baslamiyor) — Günlükte "[ENV] HATA: JWT_SECRET tanimli degil veya yer tutucu bir deger" ve sunucu açılmıyor
- [altyapi-env-uyari-jwt-kisa](#altyapi-env-uyari-jwt-kisa) — Günlükte "[ENV] UYARI: JWT_SECRET 20 karakter; en az 32 karakter onerilir" (sunucu açılıyor)
- [altyapi-env-uyari-eksik-ayarlar](#altyapi-env-uyari-eksik-ayarlar) — Günlükte "[ENV] UYARI: Veritabani/MQTT/SMTP ayarlari eksik", "COMPANY_API_KEY tanimli degil", "CORS allowlist bos" ya da "NODE_ENV=production degil"
- [altyapi-env-degisikligi-etkisiz](#altyapi-env-degisikligi-etkisiz) — .env'i değiştirdim ama canlı API eski değeri kullanıyor (yeni MQTT/SMTP/anahtar etkisiz)
- [altyapi-health-database-disconnected](#altyapi-health-database-disconnected) — /health 500 döner: {"ok":false,"database":"disconnected",...}
- [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok) — /health 200 ok:true ama mqtt.connected:false, has_error:true (last_error: "mqtt_offline" ya da "mqtt_error")
- [altyapi-health-mqtt-yapilandirilmamis](#altyapi-health-mqtt-yapilandirilmamis) — /health mqtt.configured:false ve last_error:"mqtt_not_configured" (API MQTT komutları pasif)
- [altyapi-health-mqtt-db-error-kodu](#altyapi-health-mqtt-db-error-kodu) — /health mqtt.has_error:true, last_error:"db_error" veya "local_control_sync_failed" (köprü bağlı ama DB yazımı hatalı)
- [altyapi-health-acl-sync-kapali](#altyapi-health-acl-sync-kapali) — /health mqtt.acl_sync_configured:false (yeni cihaz broker ACL'ine kendiliğinden eklenmiyor ya da cihaz eklerken 503)
- [altyapi-nginx-502-504](#altyapi-nginx-502-504) — https://api.gudeteknoloji.com.tr/health 502/504 veriyor (sunucunun içinden 127.0.0.1:8080/health çalışıyor olabilir)
- [altyapi-port-8080-kullanimda](#altyapi-port-8080-kullanimda) — Günlükte "[uncaughtException] ... EADDRINUSE" (8080 portu dolu); PM2 yeniden başlama döngüsünde
- [altyapi-kapanis-zorla-cikis](#altyapi-kapanis-zorla-cikis) — Yeniden başlatmada günlükte "[SHUTDOWN] Sure asildi, zorla cikiliyor." ya da istekler yarıda kesiliyor
- [altyapi-yakalanmamis-hata-loglari](#altyapi-yakalanmamis-hata-loglari) — Günlükte "[unhandledRejection] <id>" veya "[uncaughtException] <id>" satırları; süreç çöküp yeniden başlıyor
- [altyapi-pm2-bellek-ve-restart](#altyapi-pm2-bellek-ve-restart) — pm2 status: kapi-api restart sayısı artıyor ya da bellek ~400 MB civarında (planlanmamış yeniden başlatma)
- [altyapi-pm2-ecosystem-gecis](#altyapi-pm2-ecosystem-gecis) — pm2 start ecosystem.config.js "module is not defined in ES module scope" hatası ya da PM2 kaydı ecosystem ayarlarını (bellek, kill_timeout) uygulamıyor
- [altyapi-sema-users-yok](#altyapi-sema-users-yok) — Açılışta "Veritabani semasi kurulu degil (users tablosu yok)" hatası; API kalkmıyor
- [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist) — İstek 500 döner / günlükte `relation "xxx" does not exist` veya `column "xxx" does not exist`
- [altyapi-sema-baslangic-sql-hatasi](#altyapi-sema-baslangic-sql-hatasi) — Açılışta "Server startup failed: error: ..." (ensureDbSchema içinde SQL hatası: duplicate key, constraint, yetki)
- [altyapi-db-havuz-zaman-asimi](#altyapi-db-havuz-zaman-asimi) — İstekler yavaşlıyor ya da askıda kalıyor; sorgu/bağlantı zaman aşımı (havuz doldu, statement timeout, idle in transaction)
- [altyapi-db-baglanti-reddi](#altyapi-db-baglanti-reddi) — Açılışta "Server startup failed:" + ECONNREFUSED 127.0.0.1:5432 / "password authentication failed" / "database ... does not exist"
- [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor) — Postgres konteyneri çalışmıyor/unhealthy ya da "docker compose up" POSTGRES_PASSWORD zorunlu hatasıyla duruyor
- [altyapi-migrate-baseline-reddi](#altyapi-migrate-baseline-reddi) — node scripts/migrate.js --apply: "REDDEDILDI: schema_migrations yok/bos ama veritabaninda users tablosu var"
- [altyapi-migrate-sql-hatasi](#altyapi-migrate-sql-hatasi) — migrate.js: "HATA (NNN_ad): ..." + "Bu migration geri alindi; sonrakiler calistirilmadi" ya da "ust duzey BEGIN/COMMIT/CONCURRENTLY"
- [altyapi-migrate-uyarilar-checksum](#altyapi-migrate-uyarilar-checksum) — migrate.js --status: "[!] ... dosya uygulandiktan sonra DEGISMIS", "[?] ... DB'de kayitli ama dosyasi yok", "Ayni numarali iki migration var" ya da "Gecersiz migration dosya adi"
- [altyapi-migrate-baglanti-kilit](#altyapi-migrate-baglanti-kilit) — migrate.js "Eksik ortam degiskeni: DB_HOST..." veriyor, kilit beklerken takılıyor ya da "Onay gerekli ama etkilesimli terminal yok"
- [altyapi-apply-betikleri-dev-guard](#altyapi-apply-betikleri-dev-guard) — apply_0xx.js / check_*.js / test_*.js çalıştırınca "Bu gelistirme betigi gercek veritabanina dokunabilir..." yazıp hemen çıkıyor
- [altyapi-bakim-temizlik-hatasi](#altyapi-bakim-temizlik-hatasi) — Günlükte "[Bakim] Temizlik hatasi" / "[Maintenance Cleanup] Hata:"; yönetici panelinde veritabanı sağlığı "temizlenecek kayıt var" kalıyor
- [altyapi-bakim-saklama-sureleri](#altyapi-bakim-saklama-sureleri) — Eski kapı/bağlantı kayıtları, QR token'ları ve e-posta kodları kayboluyor (30 gün / 1-2 gün sonra siliniyor)
- [altyapi-mqtt-tls-baglanti](#altyapi-mqtt-tls-baglanti) — MQTT köprüsü broker'a bağlanamıyor: günlükte "[MQTT bridge] ..." sertifika/TLS hatası ya da ECONNREFUSED/ETIMEDOUT
- [altyapi-mqtt-kimlik-reddi](#altyapi-mqtt-kimlik-reddi) — Köprü bağlanıp hemen kopuyor; günlükte "[MQTT bridge] Connection refused: Not authorized" benzeri kimlik hatası (api_bridge parolası)
- [altyapi-mqtt-konu-ve-uid](#altyapi-mqtt-konu-ve-uid) — Cihaz MQTT'ye yayın yapıyor ama sunucu durumunu/olayını görmüyor (konu adı, UID biçimi ya da kayıtsız cihaz)
- [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi) — Cihaz brokere bağlanıyor ama yayın yapamıyor (ACL reddi): durum/olay/log sunucuya hiç ulaşmıyor ya da komut/qr_result alamıyor
- [altyapi-acl-cihaz-atlandi](#altyapi-acl-cihaz-atlandi) — sync_mqtt_acl çıktısında "UYARI: cihaz atlandi (device_uid | mqtt_username | mqtt_password | duplicate)"; o cihaz brokere bağlanamıyor
- [altyapi-acl-senkron-503](#altyapi-acl-senkron-503) — Cihaz eklerken/silerken 503 "MQTT broker senkronu basarisiz" (yanıtta mqtt_sync.ok:false)
- [altyapi-kapi-mqtt-sync-betik-hatalari](#altyapi-kapi-mqtt-sync-betik-hatalari) — sudo -n /usr/local/bin/kapi-mqtt-sync "HATA: ..." (herkes tarafindan yazilabilir / APP_DIR / node bulunamadi) ya da sudo parola istiyor
- [altyapi-acl-silinen-cihaz-baglaniyor](#altyapi-acl-silinen-cihaz-baglaniyor) — Silinen/değiştirilen cihaz hâlâ brokere bağlanabiliyor ya da broker passwd dosyasında eski kullanıcılar duruyor
- [altyapi-mosquitto-servis-calismiyor](#altyapi-mosquitto-servis-calismiyor) — Mosquitto servisi başlamıyor ("Address already in use" / "Unable to open acl_file") ya da 8883 dışarıdan açılmıyor
- [altyapi-cihaz-cevrimdisi-gorunuyor](#altyapi-cihaz-cevrimdisi-gorunuyor) — Cihaz çevrimdışı görünüyor (sunucu tarafı: devices.is_online=false / mqtt_connected=false) ama cihaz Wi-Fi'ye bağlı
- [altyapi-durum-api-yeniden-baslayinca](#altyapi-durum-api-yeniden-baslayinca) — API yeniden başlatılınca (dağıtım sonrası) cihaz durumları kısa süre eski ya da boş görünüyor
- [altyapi-komut-yayini-roleyi-calistirmiyor](#altyapi-komut-yayini-roleyi-calistirmiyor) — Cihaz komut alıyor ama röle çalışmıyor — sunucu yayın yapıyor mu? (uygulama "komut gönderildi" diyor, kapı açılmıyor)
- [altyapi-qr-sonuc-cihaza-donmuyor](#altyapi-qr-sonuc-cihaza-donmuyor) — Cihaz karekodu okutuyor ama "qr_result" yanıtı gelmiyor (kapı açılmıyor, cihaz zaman aşımına düşüyor)
- [altyapi-ekran-qr-token-sunucuda](#altyapi-ekran-qr-token-sunucuda) — Ekranlı (WROOM) cihazın ekran QR kodu sunucuda görünmüyor ya da API yeniden başlayınca boşalıyor
- [altyapi-offline-log-alimi](#altyapi-offline-log-alimi) — Cihazın çevrimdışıyken biriktirdiği kapı kayıtları sunucuya gelmiyor ya da cihaz aynı kayıt paketini tekrar tekrar yolluyor (logs_ack yok)
- [altyapi-sertifika-suresi](#altyapi-sertifika-suresi) — HTTPS sertifikası (api.gudeteknoloji.com.tr) ya da MQTT TLS sertifikası (mqtt.gudeteknoloji.com.tr) süresi doldu/dolmak üzere; uygulama ya da cihazlar bağlanamıyor
- [altyapi-komut-rehberi](#altyapi-komut-rehberi) — Canlı sunucuda sorunu nereden okuyacağımı bilmiyorum (günlük, /health, veritabanı, PM2 durumu için güvenli komutlar)
- [altyapi-geri-alma-ve-yedek](#altyapi-geri-alma-ve-yedek) — Dağıtımdan sonra API bozuldu; eski sürüme/veriye dönmem gerekiyor (yedek nerede, nasıl geri alınır)
- [altyapi-deploy-prepare-basarisiz](#altyapi-deploy-prepare-basarisiz) — Dağıtım "prepare" aşaması PREPARE_OK yazmadan duruyor ("HATA: DB yedegi bos/kucuk", node --check ya da npm ci hatası)
- [altyapi-deploy-activate-geri-alma](#altyapi-deploy-activate-geri-alma) — Dağıtım "activate" sırasında "SAGLIK KONTROLU BASARISIZ" yazdı ve otomatik geri alma başladı ya da ACTIVATE_OK hiç görünmedi
- [altyapi-deploy-dogrulama-sonuclari](#altyapi-deploy-dogrulama-sonuclari) — Dağıtım sonrası remote_verify.sh / remote_audit.sh çıktısında beklenmeyen satır var (boş cihaz listesi, yeni kolon yok, şirket ucu 401 değil, OTA manifest boş)
- [altyapi-ota-manifest-guncelleme-sunmuyor](#altyapi-ota-manifest-guncelleme-sunmuyor) — Cihaz OTA kontrol ediyor ama güncelleme almıyor: manifest update_available:false döner ("Bu hedef icin OTA yayini yok", "Cihaz bu yayin grubunda degil", "USB ile tam yukleme")
- [altyapi-ota-hedef-uyusmazligi](#altyapi-ota-hedef-uyusmazligi) — OTA manifest 403 "FIRMWARE_TARGET_MISMATCH" döner ya da günlükte "[OTA] Manifest hedefi klasorle uyusmuyor"
- [altyapi-ota-dosya-indirilemiyor](#altyapi-ota-dosya-indirilemiyor) — Cihaz manifesti alıyor ama .bin indiremiyor ya da manifest 500/503 veriyor ("Firmware manifest okunamadi", "Firmware dosyasi bulunamadi", "Cihaz dogrulamasi gecici olarak yapilamadi")
- [altyapi-ota-toplu-komut-hatasi](#altyapi-ota-toplu-komut-hatasi) — Şirket/yönetici panelinde "Tümüne OTA kontrolü" 503 "MQTT baglantisi hazir degil" ya da 500 veriyor; ota_check cihazlara gitmiyor (trigger_ota.js dahil)
- [altyapi-apply-013-024-tek-seferlik](#altyapi-apply-013-024-tek-seferlik) — apply_013 ... apply_024 betiği hata verdi ya da başarılı göründü ama tablo/kolon yok ("Migration error:", "MIGRATION_0xx_SUCCESS" görünmedi)
- [altyapi-teshis-betikleri](#altyapi-teshis-betikleri) — check_devs.js / check_screen_qr.js / test_doors_qr.js / test_query.js ne yapar, hangi veritabanına bağlanır, çalıştırmak güvenli mi, neden boş/hatalı çıktı veriyor
- [altyapi-test-endpoint-artik-kullanici](#altyapi-test-endpoint-artik-kullanici) — test_endpoint.js çalıştırıldıktan sonra "Delete Test User" / deletetest99991@example.com kullanıcısı veritabanında kalmış
- [altyapi-company-api-key-uretildi](#altyapi-company-api-key-uretildi) — Dağıtımdan sonra şirket aracı (company_qr_tool) sunucuya 401 alıyor ya da "COMPANY_API_KEY tanimli degil" uyarısı çıkıyor
- [altyapi-disk-dolu-yedekler](#altyapi-disk-dolu-yedekler) — Sunucu diski doluyor / dağıtım yedeği alınırken yazma hatası; ~/backups altında çok sayıda kapi_<TS> dizini birikmiş

## Girişler

<a id="altyapi-api-acilmiyor-pm2-dongu"></a>
### altyapi-api-acilmiyor-pm2-dongu · API açılmıyor / PM2 "kapi-api" sürekli yeniden başlıyor (status errored, restarts sayısı artıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/server.js:344](../../server/src/server.js#L344) | <code>async function startServer() {</code> | Açılış sırası: checkEnvOrExit → ensureDbSchema → startMqttBridge → temizlik → dinleme; ilk başarısız adım süreci düşürür |
| [server/src/server.js:384](../../server/src/server.js#L384) | <code>console.error('Server startup failed:', error);</code> | Açılışta fırlatılan her hata (DB'ye ulaşılamadı, şema SQL hatası) buraya düşer, ardından process.exit(1) |
| [server/src/server.js:346](../../server/src/server.js#L346) | <code>checkEnvOrExit();</code> | Ortam doğrulaması DB'den ÖNCE çalışır; JWT_SECRET hatasında DB'ye hiç bağlanılmaz |
| [server/src/config/process_handlers.js:28](../../server/src/config/process_handlers.js#L28) | <code>const onUncaughtException = (error) =&gt; {</code> | Yakalanmamış istisna: günlüğe yazar ve exit(1); PM2 yeniden başlatır |
| [server/ecosystem.config.cjs:38](../../server/ecosystem.config.cjs#L38) | <code>min_uptime: '15s',</code> | 15 sn dayanmayan çıkışlar "kararsız" sayılır ve yeniden başlatma sayacını artırır |
| [server/ecosystem.config.cjs:39](../../server/ecosystem.config.cjs#L39) | <code>max_restarts: 30,</code> | Üst üste kararsız yeniden başlatma sınırı; aşılınca PM2 süreci errored bırakır |

**Olası nedenler**
- Ortam doğrulaması başarısız: JWT_SECRET boş/yer tutucu → "[ENV] HATA" (altyapi-env-hata-sunucu-baslamiyor)
- Veritabanına ulaşılamıyor (konteyner kapalı, DB_* yanlış, parola değişmiş) → "Server startup failed:" (altyapi-db-baglanti-reddi)
- ensureDbSchema sırasında SQL hatası (yinelenen veri, yetki) (altyapi-sema-baslangic-sql-hatasi)
- Boş veritabanı: "users" tablosu yok (altyapi-sema-users-yok)
- 8080 portu başka süreçte (altyapi-port-8080-kullanimda)

**Adım adım kontrol**
- pm2 logs içinde EN ESKİ yeni-başlatma hatasını bulun: "Server startup failed:", "[ENV] HATA:" ya da "[uncaughtException]"; sonraki yeniden denemeler aynı hatayı tekrarlar.
- "[ENV] HATA" ise .env'i düzeltin (değerleri yazdırmayın); DB hatasıysa docker ps ile konteyneri doğrulayın; şema hatasıysa hata satırındaki indeks/kısıt adını arayın.
- Sunucu içinden 127.0.0.1:8080/health yanıt veriyorsa sorun nginx/DNS tarafındadır (altyapi-nginx-502-504).

**Günlükte aranacak ifadeler**
- `Server startup failed:`
- `[ENV] HATA:`
- `Gecersiz yapilandirma nedeniyle sunucu baslatilmadi.`
- `[uncaughtException]`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 status | grep kapi-api"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 describe kapi-api | grep -E 'status|restarts|uptime|script path|exec cwd'"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a -E 'Server startup failed|\[ENV\]|uncaughtException' | cut -c1-220"
```

**İlgili testler:** [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [altyapi-env-hata-sunucu-baslamiyor](#altyapi-env-hata-sunucu-baslamiyor), [altyapi-db-baglanti-reddi](#altyapi-db-baglanti-reddi), [altyapi-sema-baslangic-sql-hatasi](#altyapi-sema-baslangic-sql-hatasi), [altyapi-port-8080-kullanimda](#altyapi-port-8080-kullanimda), [altyapi-pm2-bellek-ve-restart](#altyapi-pm2-bellek-ve-restart)

<a id="altyapi-env-hata-sunucu-baslamiyor"></a>
### altyapi-env-hata-sunucu-baslamiyor · Günlükte "[ENV] HATA: JWT_SECRET tanimli degil veya yer tutucu bir deger" ve sunucu açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/config/env.js:67](../../server/src/config/env.js#L67) | <code>'JWT_SECRET tanimli degil veya yer tutucu bir deger. Guclu, rastgele bir secret tanimlayi…</code> | Hata iletisinin üretildiği yer: secret boş ya da yer tutucuysa evaluateJwtSecret ok:false döner |
| [server/src/config/env.js:45](../../server/src/config/env.js#L45) | <code>export function isPlaceholderSecret(value) {</code> | Hangi değerlerin "yer tutucu" sayıldığı (PLACEHOLDER_EXACT / PLACEHOLDER_PATTERNS: change_this_secret, your-secret, <JWT_SECRET> ...) |
| [server/src/config/env.js:249](../../server/src/config/env.js#L249) | <code>const jwtCheck = evaluateJwtSecret(env.JWT_SECRET);</code> | validateEnv içinde TEK "errors" kaynağı budur; diğer eksikler yalnız uyarıdır |
| [server/src/server.js:270](../../server/src/server.js#L270) | <code>function checkEnvOrExit() {</code> | errors doluysa [ENV] HATA yazar ve process.exit(1); uyarılar [ENV] UYARI olarak yazılır |

**Olası nedenler**
- server/.env içinde JWT_SECRET yok ya da boş
- Değer bilinen bir yer tutucu (change_this_secret, secret, test, <...>, ${...}, xxx...)
- Süreç yanlış dizinden başlatıldı: dotenv .env'i çalışma dizininde arar (ecosystem cwd = server/)

**Adım adım kontrol**
- .env içeriğini ASLA yazdırmayın; yalnız uzunluk bakın: deploy/remote_audit.sh "kritik uzunluklar" bölümü JWT_SECRET uzunluğunu verir.
- Düzeltmeden sonra `pm2 restart kapi-api --update-env` ve /health.

**Günlükte aranacak ifadeler**
- `[ENV] HATA:`
- `Gecersiz yapilandirma nedeniyle sunucu baslatilmadi.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_audit.sh   # salt-okunur, .env değerleri maskeli (JWT_SECRET uzunluk=...)
```

**İlgili testler:** [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-env-uyari-jwt-kisa](#altyapi-env-uyari-jwt-kisa), [altyapi-env-degisikligi-etkisiz](#altyapi-env-degisikligi-etkisiz)

<a id="altyapi-env-uyari-jwt-kisa"></a>
### altyapi-env-uyari-jwt-kisa · Günlükte "[ENV] UYARI: JWT_SECRET 20 karakter; en az 32 karakter onerilir" (sunucu açılıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/config/env.js:71](../../server/src/config/env.js#L71) | <code>if (length &lt; MIN_RECOMMENDED_JWT_SECRET_LENGTH) {</code> | 32 karakterden kısa secret yalnız UYARI üretir (ok:true); sunucu açılır |
| [server/src/config/env.js:257](../../server/src/config/env.js#L257) | <code>warnings.push('JWT_EXPIRES_IN gecersiz bicimde (ornek: 30d, 12h); varsayilan 30 gun kulla…</code> | JWT_EXPIRES_IN biçimi hatalıysa (30d, 12h gibi olmalı) yalnız uyarı; token üretimi başarısız olabilir |
| [server/src/server.js:273](../../server/src/server.js#L273) | <code>console.warn(`[ENV] UYARI: ${warning}`);</code> | Tüm uyarıların yazıldığı yer; secret değeri asla yazılmaz (yalnız uzunluk) |
| [deploy/README.md:39](../../deploy/README.md#L39) | <code>- Canlı `JWT_SECRET` (≥32 karakter), `JWT_EXPIRES_IN` ve `NODE_ENV=production` kararları …</code> | Canlıdaki secret/süre/NODE_ENV kararları kullanıcıya aittir; kendiliğinden değiştirilmez |

**Olası nedenler**
- Canlı .env'deki secret 20 karakter (kullanıcı kararıyla değiştirilmedi); bu bir arıza değil, bilinen uyarıdır
- Secret değiştirilirse mevcut TÜM oturum belirteçleri geçersiz olur (kullanıcılar yeniden giriş yapar)

**Adım adım kontrol**
- Uyarı yalnız bilgidir; sunucu çalışıyorsa işlem gerekmez. Değiştirme kararı bakım penceresinde, kullanıcı onayıyla alınır.

**Günlükte aranacak ifadeler**
- `[ENV] UYARI:`
- `karakter onerilir`

**İlgili testler:** [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [altyapi-env-hata-sunucu-baslamiyor](#altyapi-env-hata-sunucu-baslamiyor), [altyapi-env-uyari-eksik-ayarlar](#altyapi-env-uyari-eksik-ayarlar)

<a id="altyapi-env-uyari-eksik-ayarlar"></a>
### altyapi-env-uyari-eksik-ayarlar · Günlükte "[ENV] UYARI: Veritabani/MQTT/SMTP ayarlari eksik", "COMPANY_API_KEY tanimli degil", "CORS allowlist bos" ya da "NODE_ENV=production degil"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/config/env.js:272](../../server/src/config/env.js#L272) | <code>const missingDb = ['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'].filter((name) =&gt; !isSe…</code> | DB_HOST/DB_NAME/DB_USER/DB_PASSWORD eksikse uyarı (sunucu yine de başlar; DB bağlantısı sonra hata verir) |
| [server/src/config/env.js:277](../../server/src/config/env.js#L277) | <code>const missingMqtt = ['MQTT_HOST', 'MQTT_USER', 'MQTT_PASSWORD'].filter((name) =&gt; !isSet(e…</code> | MQTT_HOST/MQTT_USER/MQTT_PASSWORD eksikse uyarı: cihaz komutları çalışmaz |
| [server/src/config/env.js:282](../../server/src/config/env.js#L282) | <code>const missingSmtp = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD'].filter((name) =&gt; !isSet(e…</code> | SMTP eksikse e-posta (doğrulama kodu, şifre sıfırlama, davet) gönderilemez |
| [server/src/config/env.js:325](../../server/src/config/env.js#L325) | <code>warnings.push('COMPANY_API_KEY tanimli degil; /api/company/* yalnizca super_user JWT ile …</code> | Anahtar yoksa /api/company/* yalnız super_user JWT ile çalışır (şirket aracı X-Company-Key kullanamaz) |
| [server/src/config/env.js:331](../../server/src/config/env.js#L331) | <code>warnings.push('CORS allowlist bos (CORS_ORIGINS/PUBLIC_APP_URL/PUBLIC_BASE_URL); tarayici…</code> | CORS_ORIGINS/PUBLIC_APP_URL/PUBLIC_BASE_URL üçü de boşsa tarayıcı tabanlı cross-origin istekler reddedilir |
| [server/src/config/env.js:335](../../server/src/config/env.js#L335) | <code>warnings.push('NODE_ENV=production degil (Express gelistirme varsayilanlari aktif); oneri…</code> | NODE_ENV production değilse yalnız uyarı (hata yanıtları ortamdan bağımsız güvenlidir) |
| [server/src/server.js:276](../../server/src/server.js#L276) | <code>console.warn(`[CORS] Gecersiz origin girdisi yok sayildi: ${entry}`);</code> | CORS_ORIGINS içindeki geçersiz girdi (şema yok, * vb.) sessizce atılmaz; burada loglanır |

**Olası nedenler**
- İlgili anahtar sunucudaki server/.env dosyasında yok/boş
- PM2 yeniden başlatılırken .env değişikliği okunmadı (altyapi-env-degisikligi-etkisiz)

**Adım adım kontrol**
- Hangi anahtarın eksik olduğu uyarı metninde yazar; değerini değil yalnız varlığını doğrulayın: deploy/remote_audit.sh ".env anahtarlari (DEGER YOK)" bölümü.
- MQTT eksikse /health mqtt.configured:false görünür (altyapi-health-mqtt-yapilandirilmamis).

**Günlükte aranacak ifadeler**
- `Veritabani ayarlari eksik:`
- `MQTT ayarlari eksik:`
- `SMTP ayarlari eksik:`
- `CORS allowlist bos`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a 'UYARI' | cut -c1-200"
```

**İlgili testler:** [server/test/core_startup.test.js](../../server/test/core_startup.test.js), [server/test/core_cors.test.js](../../server/test/core_cors.test.js)

**Bkz.:** [altyapi-env-uyari-jwt-kisa](#altyapi-env-uyari-jwt-kisa), [altyapi-health-mqtt-yapilandirilmamis](#altyapi-health-mqtt-yapilandirilmamis)

<a id="altyapi-env-degisikligi-etkisiz"></a>
### altyapi-env-degisikligi-etkisiz · .env'i değiştirdim ama canlı API eski değeri kullanıyor (yeni MQTT/SMTP/anahtar etkisiz)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/server.js:99](../../server/src/server.js#L99) | <code>dotenv.config();</code> | .env yalnız süreç AÇILIRKEN okunur; dotenv varsayılanı, süreç ortamında zaten tanımlı değişkenin üzerine YAZMAZ |
| [deploy/README.md:27](../../deploy/README.md#L27) | <code>6. **Etkinleştirme:** `ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS acti…</code> | Dağıtım sonrası etkinleştirme PM2'yi --update-env ile yeniden başlatır |
| [server/ecosystem.config.cjs:15](../../server/ecosystem.config.cjs#L15) | <code>// Gizli degerler BURAYA yazilmaz; server/.env dosyasindan dotenv ile okunur</code> | Gizli değerler ecosystem'e değil server/.env'e yazılır; cwd = server/ olduğu için dotenv bulur |

**Olası nedenler**
- API yeniden başlatılmadı: .env değişikliği çalışan sürece yansımaz
- Aynı değişken PM2 ortamında/kabukta zaten tanımlıydı; dotenv onu ezmez
- Yanlış dosya düzenlendi (canlı yol /var/www/site_kapi_kontrol/server/.env)

**Adım adım kontrol**
- Düzenlemeden sonra: pm2 restart kapi-api --update-env ve pm2 logs ile "[ENV]" satırlarına bakın.
- Sır basmayın: .env'i cat etmeyin, `source` ETMEYİN (boşluklu değerler komut olarak çalışır); yalnız deploy/remote_audit.sh çıktısına bakın.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 restart kapi-api --update-env && sleep 10 && curl -s http://127.0.0.1:8080/health"   # DEĞİŞTİRİR: canlı API yeniden başlar
```

**Bkz.:** [altyapi-env-hata-sunucu-baslamiyor](#altyapi-env-hata-sunucu-baslamiyor), [altyapi-env-uyari-eksik-ayarlar](#altyapi-env-uyari-eksik-ayarlar)

<a id="altyapi-health-database-disconnected"></a>
### altyapi-health-database-disconnected · /health 500 döner: {"ok":false,"database":"disconnected",...}

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:95](../../server/src/routes/firmware_routes.js#L95) | <code>firmwareRouter.get('/health', async (_req, res) =&gt; {</code> | /health uç noktası: DB'ye SELECT 1 atar; başarılıysa ok:true/connected, hata olursa 500 |
| [server/src/routes/firmware_routes.js:104](../../server/src/routes/firmware_routes.js#L104) | <code>res.status(500).json({ ok: false, database: 'disconnected', mqtt });</code> | catch (_e) hatayı YUTAR: nedeni ne yanıtta ne günlükte görünür; nedeni docker/psql ile arayın |
| [server/src/db.js:93](../../server/src/db.js#L93) | <code>export async function checkDbConnection() {</code> | Havuzdan bağlantı alıp SELECT 1 çalıştırır; havuz doluysa ya da DB kapalıysa fırlatır |
| [server/src/db.js:81](../../server/src/db.js#L81) | <code>connectionTimeoutMillis: DB_CONNECT_TIMEOUT_MS,</code> | Bağlantı alma/kurma zaman aşımı (varsayılan 5 sn, DB_CONNECT_TIMEOUT_MS) |
| [server/src/db.js:68](../../server/src/db.js#L68) | <code>const DB_POOL_MAX = Math.max(2, Number(process.env.DB_POOL_MAX) &#124;&#124; 12);</code> | Havuz üst sınırı 12; hepsi meşgulse yeni istek bağlantı bekler ve zaman aşımına düşer |

**Olası nedenler**
- PostgreSQL konteyneri durmuş / unhealthy / yeniden başlıyor
- DB_HOST/DB_PORT/DB_PASSWORD yanlış ya da parola değişmiş
- Havuz tükenmiş: uzun süren sorgular/kilitler tüm bağlantıları tutuyor (altyapi-db-havuz-zaman-asimi)

**Adım adım kontrol**
- Konteyner: docker ps (Status: healthy olmalı) ve docker logs --tail 50 site_kapi_kontrol_postgres.
- psql ile SELECT 1 çalışıyorsa sorun havuz/kimlik bilgisindedir: pg_stat_activity'de application_name=kapi-api bağlantı sayısına bakın.
- pm2 logs içinde "[DB] Bosta bekleyen istemci hatasi:" ya da başka DB hata satırı var mı?

**Günlükte aranacak ifadeler**
- `[DB] Bosta bekleyen istemci hatasi:`

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "docker ps --format '{{.Names}} | {{.Status}} | {{.Ports}}'"
ssh -p 22667 salihceylan@178.210.161.55 "docker logs --tail 50 site_kapi_kontrol_postgres 2>&1 | cut -c1-200"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT application_name, state, count(*) FROM pg_stat_activity GROUP BY 1, 2 ORDER BY 1, 2;"
```

**İlgili testler:** [server/test/core_robustness.test.js](../../server/test/core_robustness.test.js), [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js)

**Bkz.:** [altyapi-db-baglanti-reddi](#altyapi-db-baglanti-reddi), [altyapi-db-havuz-zaman-asimi](#altyapi-db-havuz-zaman-asimi), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor)

<a id="altyapi-health-mqtt-baglanti-yok"></a>
### altyapi-health-mqtt-baglanti-yok · /health 200 ok:true ama mqtt.connected:false, has_error:true (last_error: "mqtt_offline" ya da "mqtt_error")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1090](../../server/src/mqtt_bridge.js#L1090) | <code>export function mqttBridgeHealth() {</code> | /health'in mqtt alanı: configured, connected, has_error ve YALNIZ kısa kod last_error (ham hata metni dönmez) |
| [server/src/mqtt_bridge.js:25](../../server/src/mqtt_bridge.js#L25) | <code>function recordBridgeError(code, detail) {</code> | Hata kodunu ve ayrıntısını saklar; ayrıntı günlüğe EN FAZLA dakikada bir yazılır |
| [server/src/mqtt_bridge.js:32](../../server/src/mqtt_bridge.js#L32) | <code>console.warn(`[MQTT bridge] ${detail}`);</code> | Köprü hatasının günlükteki hali; broker ayrıntısı yalnız burada görülür |
| [server/src/mqtt_bridge.js:1059](../../server/src/mqtt_bridge.js#L1059) | <code>client.on('error', (error) =&gt; {</code> | Bağlantı/TLS/kimlik hataları mqtt_error koduyla kaydedilir |
| [server/src/mqtt_bridge.js:1063](../../server/src/mqtt_bridge.js#L1063) | <code>client.on('offline', () =&gt; {</code> | Bağlantı koptuğunda mqtt_offline kaydedilir; kütüphane 3 sn'de bir yeniden dener (reconnectPeriod) |
| [server/src/mqtt_bridge.js:1019](../../server/src/mqtt_bridge.js#L1019) | <code>reconnectPeriod: 3000,</code> | Otomatik yeniden bağlanma aralığı; broker dönünce köprü kendiliğinden bağlanır, API yeniden başlatmak gerekmez |

**Olası nedenler**
- Mosquitto servisi kapalı/çökmüş (MQTT_kurulum.txt 13-14)
- TLS sertifikası süresi dolmuş/uyuşmuyor (köprü sertifikayı DOĞRULAR) (altyapi-mqtt-tls-baglanti)
- api_bridge kullanıcı/parolası geçersiz (altyapi-mqtt-kimlik-reddi)
- MQTT_HOST/MQTT_PORT yanlış, 8883 güvenlik duvarında kapalı

**Adım adım kontrol**
- pm2 logs içinde "[MQTT bridge]" satırını bulun (kütüphanenin hata iletisi orada); satır dakikada en fazla bir kez yazılır, eski olabilir.
- Sunucuda: sudo systemctl status mosquitto --no-pager ve sudo ss -ltnp | grep 8883.
- Bağlantı kurulunca günlükte "MQTT bridge connected: host:port" görülür ve hata bayrağı temizlenir.

**Günlükte aranacak ifadeler**
- `[MQTT bridge]`
- `MQTT bridge offline.`
- `MQTT bridge connected:`

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a 'MQTT bridge' | tail -n 10 | cut -c1-200"
ssh -p 22667 salihceylan@178.210.161.55 "sudo systemctl status mosquitto --no-pager | head -n 12"
```

**İlgili testler:** [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js)

**Bkz.:** [altyapi-mqtt-tls-baglanti](#altyapi-mqtt-tls-baglanti), [altyapi-mqtt-kimlik-reddi](#altyapi-mqtt-kimlik-reddi), [altyapi-mosquitto-servis-calismiyor](#altyapi-mosquitto-servis-calismiyor), [altyapi-health-mqtt-yapilandirilmamis](#altyapi-health-mqtt-yapilandirilmamis)

<a id="altyapi-health-mqtt-yapilandirilmamis"></a>
### altyapi-health-mqtt-yapilandirilmamis · /health mqtt.configured:false ve last_error:"mqtt_not_configured" (API MQTT komutları pasif)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1003](../../server/src/mqtt_bridge.js#L1003) | <code>if (!config.host &#124;&#124; !config.username &#124;&#124; !config.password) {</code> | Üç değerden biri boşsa köprü HİÇ başlamaz (yeniden deneme yok); bağlantı kurulmaz |
| [server/src/mqtt_bridge.js:1006](../../server/src/mqtt_bridge.js#L1006) | <code>lastBridgeErrorCode = 'mqtt_not_configured';</code> | /health'te görünen kod |
| [server/src/mqtt_bridge.js:65](../../server/src/mqtt_bridge.js#L65) | <code>function mqttConfig() {</code> | MQTT_HOST, MQTT_PORT (varsayılan 8883), MQTT_USER, MQTT_PASSWORD ve MQTT_ALLOW_INSECURE_TLS okunur |
| [server/src/config/env.js:279](../../server/src/config/env.js#L279) | <code>warnings.push(`MQTT ayarlari eksik: ${missingMqtt.join(', ')}; cihaz komutlari calismayab…</code> | Açılışta aynı eksiği "[ENV] UYARI: MQTT ayarlari eksik" olarak bildirir |

**Olası nedenler**
- server/.env içinde MQTT_HOST / MQTT_USER / MQTT_PASSWORD eksik ya da boş
- .env düzeltildi ama PM2 yeniden başlatılmadı (köprü yalnız açılışta yapılandırılır)

**Adım adım kontrol**
- Anahtarların varlığını değerleri basmadan doğrulayın (deploy/remote_audit.sh).
- Düzeltmeden sonra pm2 restart kapi-api --update-env; günlükte "MQTT bridge connected:" aranır.

**Günlükte aranacak ifadeler**
- `MQTT_HOST, MQTT_USER ve MQTT_PASSWORD tanimli degil; API MQTT komutlari pasif.`
- `MQTT ayarlari eksik:`

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_audit.sh   # salt-okunur; .env anahtar adları (değer yok)
```

**İlgili testler:** [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js)

**Bkz.:** [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-env-uyari-eksik-ayarlar](#altyapi-env-uyari-eksik-ayarlar), [altyapi-env-degisikligi-etkisiz](#altyapi-env-degisikligi-etkisiz)

<a id="altyapi-health-mqtt-db-error-kodu"></a>
### altyapi-health-mqtt-db-error-kodu · /health mqtt.has_error:true, last_error:"db_error" veya "local_control_sync_failed" (köprü bağlı ama DB yazımı hatalı)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:409](../../server/src/mqtt_bridge.js#L409) | <code>recordBridgeError('db_error', `Device status DB yazilamadi: ${error.message}`);</code> | Cihaz durum satırı (device_runtime_status / devices.is_online) yazılamadı |
| [server/src/mqtt_bridge.js:281](../../server/src/mqtt_bridge.js#L281) | <code>recordBridgeError('db_error', `Cihaz kaydi sorgulanamadi: ${error.message}`);</code> | Gelen iletinin cihazı kayıtlı mı diye DB sorgusu başarısız; ileti işlenmeden düşer |
| [server/src/mqtt_bridge.js:547](../../server/src/mqtt_bridge.js#L547) | <code>recordBridgeError('db_error', `OTA job event DB yazilamadi: ${error.message}`);</code> | Cihazın OTA olayı iş kaydına yazılamadı |
| [server/src/mqtt_bridge.js:449](../../server/src/mqtt_bridge.js#L449) | <code>recordBridgeError('db_error', `Cihaz donanim tipi senkronu basarisiz: ${error.message}`);</code> | Cihazın bildirdiği donanım hedefiyle devices.hardware_type eşitlenemedi |
| [server/src/mqtt_bridge.js:604](../../server/src/mqtt_bridge.js#L604) | <code>recordBridgeError('local_control_sync_failed', `Yerel kontrol token senkronu basarisiz: $…</code> | Çevrimiçi olan cihaza yerel kontrol token'ı gönderilirken DB/yayın hatası |
| [server/src/mqtt_bridge.js:1025](../../server/src/mqtt_bridge.js#L1025) | <code>lastBridgeError = null;</code> | Hata bayrağı YALNIZ bir sonraki MQTT "connect" olayında temizlenir: DB düzelse bile bayrak kalır |

**Olası nedenler**
- Geçici DB kesintisi/zaman aşımı; DB döndü ama bayrak MQTT yeniden bağlanana (ya da API yeniden başlayana) kadar kalır
- device_runtime_status / devices tablosunda eksik kolon (relation/column does not exist) (altyapi-relation-does-not-exist)
- Kalıcı DB hatası: kimlik bilgisi, havuz, kilit

**Adım adım kontrol**
- pm2 logs içinde "[MQTT bridge] Device status DB yazilamadi: ..." satırının hata metnine bakın (ayrıntı yalnız günlükte).
- DB sağlıklıysa ve cihaz mesajları işleniyorsa (devices.last_online_at güncelleniyor) bayrak eski olabilir; API'yi yeniden başlatmak temizler.

**Günlükte aranacak ifadeler**
- `[MQTT bridge] Device status DB yazilamadi`
- `Yerel kontrol token senkronu basarisiz`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -E 'DB yazilamadi|sorgulanamadi|senkronu basarisiz' | tail -n 8 | cut -c1-220"
```

**İlgili testler:** [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js)

**Bkz.:** [altyapi-health-database-disconnected](#altyapi-health-database-disconnected), [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist), [altyapi-cihaz-cevrimdisi-gorunuyor](#altyapi-cihaz-cevrimdisi-gorunuyor)

<a id="altyapi-health-acl-sync-kapali"></a>
### altyapi-health-acl-sync-kapali · /health mqtt.acl_sync_configured:false (yeni cihaz broker ACL'ine kendiliğinden eklenmiyor ya da cihaz eklerken 503)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:98](../../server/src/routes/firmware_routes.js#L98) | <code>acl_sync_configured: mqttAclSyncConfigured(),</code> | /health yanıtına eklenen alan: senkron komutu tanımlı mı |
| [server/src/mqtt_acl_sync.js:157](../../server/src/mqtt_acl_sync.js#L157) | <code>export function mqttAclSyncConfigured() {</code> | Yalnızca MQTT_SYNC_COMMAND dolu mu diye bakar |
| [server/src/mqtt_acl_sync.js:169](../../server/src/mqtt_acl_sync.js#L169) | <code>message: 'MQTT_SYNC_COMMAND tanimli degil.',</code> | Komut yoksa senkron atlanır (ok:false, skipped:true) |
| [server/src/mqtt_acl_sync.js:257](../../server/src/mqtt_acl_sync.js#L257) | <code>if (!result.ok &amp;&amp; envFlag('MQTT_SYNC_REQUIRED', false)) {</code> | MQTT_SYNC_REQUIRED=true iken "atlandı" bile hata sayılır: cihaz ekleme/silme 503 MQTT_ACL_SYNC_FAILED verir |
| [server/.env.example:92](../../server/.env.example#L92) | <code>MQTT_SYNC_COMMAND=sudo</code> | Beklenen canlı yapılandırma: sudo -n /usr/local/bin/kapi-mqtt-sync (MQTT_SYNC_ARGS ile) |

**Olası nedenler**
- Canlı .env'de MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS yok (cihaz ACL'i elle senkronlanmalı)
- MQTT_SYNC_REQUIRED=true ama komut tanımsız: her cihaz kaydı/silmesi 503 döner

**Adım adım kontrol**
- Canlı değerlerin varlığını remote_audit.sh ile (maskeli) doğrulayın: MQTT_SYNC_REQUIRED "güvenli değerler" bölümünde görünür.
- Komut tanımlıysa ama senkron başarısızsa: altyapi-acl-senkron-503.

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_audit.sh
```

**İlgili testler:** [server/test/devices_mqtt_acl.test.js](../../server/test/devices_mqtt_acl.test.js), [server/test/fix_sx2_device_delete.test.js](../../server/test/fix_sx2_device_delete.test.js)

**Bkz.:** [altyapi-acl-senkron-503](#altyapi-acl-senkron-503), [altyapi-kapi-mqtt-sync-betik-hatalari](#altyapi-kapi-mqtt-sync-betik-hatalari)

<a id="altyapi-nginx-502-504"></a>
### altyapi-nginx-502-504 · https://api.gudeteknoloji.com.tr/health 502/504 veriyor (sunucunun içinden 127.0.0.1:8080/health çalışıyor olabilir)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [sunucu_kurulum.txt:92](../../sunucu_kurulum.txt#L92) | <code>9) NGINX REVERSE PROXY</code> | nginx site dosyası /etc/nginx/sites-available/api.gudeteknoloji.com.tr; hedef 127.0.0.1:8080 (yapılandırma depoda YOK, sunucuda) |
| [sunucu_kurulum.txt:99](../../sunucu_kurulum.txt#L99) | <code>sudo nginx -t</code> | Yapılandırma testi ve reload: sudo nginx -t; sudo systemctl reload nginx |
| [sunucu_kurulum.txt:139](../../sunucu_kurulum.txt#L139) | <code>- Guvenlik duvari: 5432 (PostgreSQL) ve 8080 (Node) disariya ACIK olmamali; yalnizca 80/4…</code> | 8080 yalnız nginx'ten erişilmeli; dışarıdan 8080 testi başarısız olması normaldir |
| [server/src/server.js:110](../../server/src/server.js#L110) | <code>app.set('trust proxy', resolveTrustProxy(process.env).value);</code> | trust proxy varsayılanı "loopback": istemci IP'si yalnız aynı makinedeki nginx'in X-Forwarded-For başlığından alınır; TRUST_PROXY ile değişir (Cloudflare turuncu bulut önündeyse "loopback,cloudflare") |

**Olası nedenler**
- kapi-api çalışmıyor/çöküp yeniden başlıyor (nginx 502 verir) → önce altyapi-api-acilmiyor-pm2-dongu
- nginx yapılandırması bozuk ya da servis kapalı
- SSL sertifikası süresi dolmuş (HTTPS hatası, 502 değil) → altyapi-sertifika-suresi
- Paylaşımlı sunucuda başka site yapılandırması etkiliyor

**Adım adım kontrol**
- ÖNCE sunucu içinden sorun: curl -s http://127.0.0.1:8080/health. Yanıt varsa API sağlam, sorun nginx/DNS/SSL; yoksa PM2/DB tarafı.
- nginx: sudo nginx -t, sudo systemctl status nginx --no-pager; hata günlüğü varsayılan konumda (/var/log/nginx/error.log; depoda tanımlı değil).

**Komutlar**
```bash
curl -s -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 5 http://127.0.0.1:8080/health | head -c 300"
ssh -p 22667 salihceylan@178.210.161.55 "sudo nginx -t"
ssh -p 22667 salihceylan@178.210.161.55 "sudo tail -n 30 /var/log/nginx/error.log"
```

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-sertifika-suresi](#altyapi-sertifika-suresi), [altyapi-komut-rehberi](#altyapi-komut-rehberi)

<a id="altyapi-port-8080-kullanimda"></a>
### altyapi-port-8080-kullanimda · Günlükte "[uncaughtException] ... EADDRINUSE" (8080 portu dolu); PM2 yeniden başlama döngüsünde

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/server.js:111](../../server/src/server.js#L111) | <code>const port = Number(process.env.PORT &#124;&#124; 8080);</code> | Dinlenen port: PORT ortam değişkeni, yoksa 8080 (nginx buraya yönlenir) |
| [server/src/server.js:374](../../server/src/server.js#L374) | <code>httpServer = listenHost ? app.listen(port, listenHost, onListening) : app.listen(port, on…</code> | Dinleme hatası bu çağrıda try/catch ile YAKALANMAZ (sunucuda "error" dinleyicisi yok); Node'un yakalanmamış istisnasına döner. LISTEN_HOST verilmişse (ör. 127.0.0.1: yalnız aynı makinedeki nginx erişir) yalnız o adreste dinlenir |
| [server/src/config/process_handlers.js:28](../../server/src/config/process_handlers.js#L28) | <code>const onUncaughtException = (error) =&gt; {</code> | Bu yüzden günlükte "Server startup failed" değil "[uncaughtException] <id>: Error: listen EADDRINUSE" görünür; exit(1) |

**Olası nedenler**
- Aynı dizinden elle başlatılmış eski `node src/server.js` / `npm start` süreci hâlâ çalışıyor
- PM2'de iki farklı kapi-api kaydı (ecosystem dışı ilk kurulumdan kalan)
- Paylaşımlı sunucuda başka bir uygulama 8080'i tutuyor (yalnız kapi-api'ye dokunulur)
- PORT .env'de başka bir değere ayarlanmış, nginx hâlâ 8080'e yönleniyor

**Adım adım kontrol**
- ss -ltn | grep :8080 ile portu kimin tuttuğuna bakın; pm2 status ile kapi-api kopyalarını sayın.
- Başka projenin sürecini DURDURMAYIN; yalnız kapi-api'yi yönetin.

**Günlükte aranacak ifadeler**
- `[uncaughtException]`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "ss -ltn | grep :8080"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 status"
```

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-yakalanmamis-hata-loglari](#altyapi-yakalanmamis-hata-loglari), [altyapi-pm2-ecosystem-gecis](#altyapi-pm2-ecosystem-gecis)

<a id="altyapi-kapanis-zorla-cikis"></a>
### altyapi-kapanis-zorla-cikis · Yeniden başlatmada günlükte "[SHUTDOWN] Sure asildi, zorla cikiliyor." ya da istekler yarıda kesiliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/server.js:294](../../server/src/server.js#L294) | <code>async function shutdown(signal) {</code> | Düzgün kapanma: yeni bağlantı almayı bırakır, süren istekleri bitirir, MQTT ve DB havuzunu kapatır |
| [server/src/server.js:288](../../server/src/server.js#L288) | <code>const SHUTDOWN_GRACE_MS = 8000;</code> | 8 sn içinde bitmezse zorla exit(1) |
| [server/src/server.js:304](../../server/src/server.js#L304) | <code>console.error('[SHUTDOWN] Sure asildi, zorla cikiliyor.');</code> | Zorla çıkış satırı; uzun süren istek/bağlantı kapanmayı geciktirmiştir |
| [server/src/server.js:324](../../server/src/server.js#L324) | <code>await stopMqttBridge();</code> | MQTT bağlantısı kapatılır (stopMqttBridge asla fırlatmaz) |
| [server/ecosystem.config.cjs:41](../../server/ecosystem.config.cjs#L41) | <code>kill_timeout: 10000,</code> | PM2 SIGKILL'i 10 sn sonra gönderir; bu, 8 sn'lik kapanma süresinden büyük olmalıdır |

**Olası nedenler**
- Uzun süren istek ya da açık keep-alive bağlantısı 8 sn içinde kapanmadı
- DB havuzu kapanışı bekleyen sorgu yüzünden gecikti

**Adım adım kontrol**
- Satır nadirse zararsızdır; her yeniden başlatmada çıkıyorsa kapanış öncesi hangi isteğin sürdüğüne [API] günlüklerinden bakın.
- "[SHUTDOWN] Kapanis hatasi:" satırı varsa hata iletisi nedenini verir.

**Günlükte aranacak ifadeler**
- `[SHUTDOWN]`
- `sunucu kapatiliyor...`
- `Sure asildi, zorla cikiliyor.`
- `[SHUTDOWN] Kapanis hatasi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a SHUTDOWN | tail -n 10 | cut -c1-200"
```

**İlgili testler:** [server/test/core_robustness.test.js](../../server/test/core_robustness.test.js)

**Bkz.:** [altyapi-pm2-bellek-ve-restart](#altyapi-pm2-bellek-ve-restart), [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu)

<a id="altyapi-yakalanmamis-hata-loglari"></a>
### altyapi-yakalanmamis-hata-loglari · Günlükte "[unhandledRejection] <id>" veya "[uncaughtException] <id>" satırları; süreç çöküp yeniden başlıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/config/process_handlers.js:23](../../server/src/config/process_handlers.js#L23) | <code>const onUnhandledRejection = (reason) =&gt; {</code> | Yakalanmamış promise reddi: yalnız loglanır, süreç DEVAM eder |
| [server/src/config/process_handlers.js:28](../../server/src/config/process_handlers.js#L28) | <code>const onUncaughtException = (error) =&gt; {</code> | Yakalanmamış istisna: loglanır ve süreç kapanır |
| [server/src/config/process_handlers.js:31](../../server/src/config/process_handlers.js#L31) | <code>exit(1);</code> | exit(1) → PM2 yeniden başlatır (min_uptime/max_restarts politikasıyla) |
| [server/src/server.js:2](../../server/src/server.js#L2) | <code>import './utils/async_errors.js';</code> | async route hatalarını next(err)'e bağlayan yama; bu sayede route hataları süreci düşürmez, global hata middleware'ine gider |

**Olası nedenler**
- Route dışı (zamanlayıcı, MQTT geri çağrısı, olay dinleyicisi) bir async hata yakalanmadı
- Dinleme hatası (EADDRINUSE) ya da bir modülün açılışta fırlattığı hata

**Adım adım kontrol**
- Satırdaki 8 haneli id yalnız günlük içindir (istemciye gitmez); aynı id'nin tamamını (stack) okuyun, ilk "at ..." satırı dosyayı verir.
- Route hatalarında istemciye dönen 5xx yanıtı "errorId" taşır; aynı id ile günlükte arayın (error_handler).

**Günlükte aranacak ifadeler**
- `[unhandledRejection]`
- `[uncaughtException]`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a -A6 -E 'unhandledRejection|uncaughtException' | tail -n 30 | cut -c1-220"
```

**İlgili testler:** [server/test/core_error_handler.test.js](../../server/test/core_error_handler.test.js)

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-port-8080-kullanimda](#altyapi-port-8080-kullanimda)

<a id="altyapi-pm2-bellek-ve-restart"></a>
### altyapi-pm2-bellek-ve-restart · pm2 status: kapi-api restart sayısı artıyor ya da bellek ~400 MB civarında (planlanmamış yeniden başlatma)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/ecosystem.config.cjs:36](../../server/ecosystem.config.cjs#L36) | <code>max_memory_restart: '400M',</code> | Bellek 400 MB'ı aşınca PM2 süreci KASITLI yeniden başlatır (hata değil, günlükte [SHUTDOWN] ile görünür) |
| [server/ecosystem.config.cjs:37](../../server/ecosystem.config.cjs#L37) | <code>exp_backoff_restart_delay: 200,</code> | Çökme sonrası yeniden başlatma gecikmesi 200 ms'den üstel artar |
| [server/ecosystem.config.cjs:26](../../server/ecosystem.config.cjs#L26) | <code>instances: 1,</code> | Tek kopya şart: MQTT köprüsü ve bellek içi sayaçlar çoklu kopyada tutarsız çalışır; cluster moduna GEÇİLMEZ |
| [server/ecosystem.config.cjs:34](../../server/ecosystem.config.cjs#L34) | <code>autorestart: true,</code> | Süreç çıkınca otomatik yeniden başlatılır |

**Olası nedenler**
- Bellek sınırı (400M) aşıldı: PM2 sürecin düzgün kapanmasını isteyip yeniden başlatır
- Çökme döngüsü (altyapi-api-acilmiyor-pm2-dongu) ya da yakalanmamış istisna

**Adım adım kontrol**
- Ayrım: günlükte "[SHUTDOWN] ... alindi" + temiz çıkış = PM2 kasıtlı yeniden başlatma; "[uncaughtException]"/"Server startup failed" = çökme.
- pm2 describe çıktısında restarts ve uptime değerlerine bakın; uptime sürekli kısaysa çökme döngüsüdür.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 status | grep kapi-api"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 describe kapi-api | grep -E 'status|restarts|uptime'"
```

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-kapanis-zorla-cikis](#altyapi-kapanis-zorla-cikis), [altyapi-pm2-ecosystem-gecis](#altyapi-pm2-ecosystem-gecis)

<a id="altyapi-pm2-ecosystem-gecis"></a>
### altyapi-pm2-ecosystem-gecis · pm2 start ecosystem.config.js "module is not defined in ES module scope" hatası ya da PM2 kaydı ecosystem ayarlarını (bellek, kill_timeout) uygulamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/ecosystem.config.cjs:4](../../server/ecosystem.config.cjs#L4) | <code>// ".js" uzantili bir ecosystem dosyasi ESM sayilir ve PM2'nin require()'i ile</code> | server/package.json "type":"module" olduğu için dosya .cjs olmak zorunda; .js olursa PM2 yükleyemez |
| [server/ecosystem.config.cjs:7](../../server/ecosystem.config.cjs#L7) | <code>// Ilk gecis (mevcut surec "pm2 start npm --name kapi-api -- run start" ile baslatildiysa…</code> | Eski "pm2 start npm --name kapi-api -- run start" kaydından ecosystem'e geçiş adımları |
| [server/ecosystem.config.cjs:21](../../server/ecosystem.config.cjs#L21) | <code>script: 'src/server.js',</code> | PM2 doğrudan src/server.js'i çalıştırır (npm start değil); cwd = server/ olduğu için .env bulunur |
| [sunucu_kurulum.txt:146](../../sunucu_kurulum.txt#L146) | <code>pm2 delete kapi-api &amp;&amp; pm2 start ecosystem.config.cjs &amp;&amp; pm2 save</code> | Kurulum belgesindeki ilk geçiş komutu |

**Olası nedenler**
- Ecosystem dosyası .js uzantısıyla çağrıldı (ESM sayılır)
- Süreç hâlâ eski "npm start" kaydıyla çalışıyor; ecosystem ayarları (400M sınırı, kill_timeout) uygulanmıyor
- pm2 save yapılmadı: sunucu yeniden açılınca kapi-api geri gelmez

**Adım adım kontrol**
- pm2 describe kapi-api çıktısında "script path"in .../src/server.js (ecosystem) mı yoksa npm mi olduğuna bakın.
- Geçiş canlıyı kısa süre durdurur: yalnız planlı zamanda, kullanıcı onayıyla yapın.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 describe kapi-api | grep -E 'script path|exec cwd|interpreter'"
# DEĞİŞTİRİR (canlı kısa süre kapanır): ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && pm2 delete kapi-api && pm2 start ecosystem.config.cjs && pm2 save"
```

**Bkz.:** [altyapi-pm2-bellek-ve-restart](#altyapi-pm2-bellek-ve-restart), [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu)

<a id="altyapi-sema-users-yok"></a>
### altyapi-sema-users-yok · Açılışta "Veritabani semasi kurulu degil (users tablosu yok)" hatası; API kalkmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/db.js:224](../../server/src/db.js#L224) | <code>'Veritabani semasi kurulu degil ("users" tablosu yok). Bos veritabaninda once `node scrip…</code> | ensureDbSchema ilk iş "users" tablosunu arar; yoksa anlaşılır bir hata fırlatır (ALTER TABLE users patlamasın diye) |
| [server/src/db.js:217](../../server/src/db.js#L217) | <code>export async function ensureDbSchema() {</code> | Temel tablolar migration'larla gelir; ensureDbSchema yalnız EKLEYİCİ ve IF NOT EXISTS ifadeleri çalıştırır |
| [server/migrations/001_init.sql:19](../../server/migrations/001_init.sql#L19) | <code>CREATE TABLE IF NOT EXISTS users (</code> | users tablosunun tek tanımı migration 001'dedir (db.js bunu oluşturmaz) |
| [docker-compose.yml:30](../../docker-compose.yml#L30) | <code>- ./server/migrations:/docker-entrypoint-initdb.d:ro</code> | Migration SQL'leri YALNIZ boş veri dizininde ilk kurulumda otomatik çalışır |
| [server/scripts/migrate.js:497](../../server/scripts/migrate.js#L497) | <code>async function runApply(opts, env, log, logError, open, ask) {</code> | Boş veritabanına migration uygulayan elle komut (node scripts/migrate.js --apply) |

**Olası nedenler**
- Veritabanı boş: yeni volume/yeni sunucu, migration'lar hiç uygulanmadı (hiçbir şey kendiliğinden çalışmaz)
- DB_NAME/DB_HOST boş ya da yanlış bir veritabanını gösteriyor
- Postgres konteyneri yeni volume ile yeniden oluşturuldu; eski veri dizini kayboldu

**Adım adım kontrol**
- psql ile to_regclass('public.users') ve \dt sonucuna bakın.
- Boş DB ise önce `node scripts/migrate.js --apply --dry-run`, sonra --apply (hedef DB ekrana yazılır, onay sorar).
- DOLU ama schema_migrations boş DB'de --apply REDDEDİLİR; önce --baseline gerekir (altyapi-migrate-baseline-reddi).

**Günlükte aranacak ifadeler**
- `Veritabani semasi kurulu degil`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT to_regclass('public.users');"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< '\dt'
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --status"
```

**İlgili testler:** [server/test/ops_migration_chain.test.js](../../server/test/ops_migration_chain.test.js), [server/test/ops_migrate_runner.test.js](../../server/test/ops_migrate_runner.test.js)

**Bkz.:** [altyapi-migrate-baseline-reddi](#altyapi-migrate-baseline-reddi), [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor)

<a id="altyapi-relation-does-not-exist"></a>
### altyapi-relation-does-not-exist · İstek 500 döner / günlükte `relation "xxx" does not exist` veya `column "xxx" does not exist`

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/db.js:217](../../server/src/db.js#L217) | <code>export async function ensureDbSchema() {</code> | Tablo/kolon/indeks tanımlarının çoğu burada (CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS); AÇILIŞTA çalışır |
| [server/src/db.js:1015](../../server/src/db.js#L1015) | <code>CREATE TABLE IF NOT EXISTS pending_registrations (</code> | Örnek (son eklenen): e-posta doğrulama bekleyen kayıt tablosu; migration 028 ile aynı DDL |
| [server/src/db.js:688](../../server/src/db.js#L688) | <code>CREATE TABLE IF NOT EXISTS ota_update_jobs (</code> | ota_update_jobs / ota_update_job_devices / app_maintenance_runs YALNIZ db.js'te tanımlı (migration'da yok) |
| [server/migrations/001_init.sql:19](../../server/migrations/001_init.sql#L19) | <code>CREATE TABLE IF NOT EXISTS users (</code> | users tablosu YALNIZ migration'da tanımlı; db.js yalnız bu tabloya kolon ekler |
| [server/scripts/migrate.js:43](../../server/scripts/migrate.js#L43) | <code>export const MIGRATIONS_TABLE = 'schema_migrations';</code> | Migration koşucusunun kendi takip tablosu (uygulama tablosu değildir) |

**Olası nedenler**
- Eski bir yedek geri yüklendi / daha eski bir veritabanına bağlanıldı: şema yalnız API AÇILIRKEN tamamlanır → API'yi yeniden başlatın
- DB_NAME/DB_HOST yanlış veritabanını gösteriyor
- Kod yeni bir tablo/kolon bekliyor ama ensureDbSchema açılışta başarısız oldu (süreç kapandı, eski çalışan yoktur) (altyapi-sema-baslangic-sql-hatasi)
- Tablo yalnız migration'da ya da yalnız db.js'te tanımlı; ilgili adım (migrate.js / API açılışı) hiç çalışmadı

**Adım adım kontrol**
- Hata metnindeki tablo/kolon adını `node tools/klavuz/build.mjs --where "CREATE TABLE IF NOT EXISTS <ad>"` ile arayıp tanımını bulun (docs/ARIZA_KLAVUZU.md "Ek D" tüm tabloları db.js/migration satırıyla listeler).
- Canlıda tablo/kolon gerçekten var mı: to_regclass ve information_schema sorgusu (aşağıda).
- Yoksa API'yi yeniden başlatıp ensureDbSchema'nın başarıyla geçtiğini doğrulayın (pm2 logs'ta "Server startup failed" olmamalı, /health ok).

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT to_regclass('public.pending_registrations'), to_regclass('public.ota_update_jobs');"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'devices' ORDER BY ordinal_position;"
```

**İlgili testler:** [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js), [server/test/ops_migration_chain.test.js](../../server/test/ops_migration_chain.test.js)

**Bkz.:** [altyapi-sema-baslangic-sql-hatasi](#altyapi-sema-baslangic-sql-hatasi), [altyapi-sema-users-yok](#altyapi-sema-users-yok), [altyapi-health-mqtt-db-error-kodu](#altyapi-health-mqtt-db-error-kodu)

<a id="altyapi-sema-baslangic-sql-hatasi"></a>
### altyapi-sema-baslangic-sql-hatasi · Açılışta "Server startup failed: error: ..." (ensureDbSchema içinde SQL hatası: duplicate key, constraint, yetki)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/db.js:322](../../server/src/db.js#L322) | <code>CREATE UNIQUE INDEX IF NOT EXISTS idx_users_login_name_unique</code> | login_name (küçük harfe göre) benzersiz indeksi: mevcut veride yinelenen değer varsa oluşturulamaz |
| [server/src/db.js:537](../../server/src/db.js#L537) | <code>CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_mqtt_site_id_unique</code> | sites.mqtt_site_id benzersiz indeksi (önce NULL satırlar UPDATE ile doldurulur) |
| [server/src/db.js:534](../../server/src/db.js#L534) | <code>ALTER COLUMN mqtt_site_id SET NOT NULL</code> | NULL kalan satır varsa başarısız olur; öncesindeki UPDATE bunu önlemek içindir |
| [server/src/db.js:634](../../server/src/db.js#L634) | <code>CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_mqtt_username_unique</code> | devices.mqtt_username benzersiz indeksi (NULL olmayanlar için) |
| [server/src/db.js:915](../../server/src/db.js#L915) | <code>CREATE UNIQUE INDEX IF NOT EXISTS idx_door_access_logs_client_log</code> | Offline log idempotansı: (device_uid, client_log_id) benzersiz indeksi |
| [server/src/db.js:905](../../server/src/db.js#L905) | <code>ALTER TABLE door_access_logs ALTER COLUMN site_code TYPE BIGINT;</code> | Her açılışta çalışan tip değişikliği ifadeleri (sütun zaten BIGINT ise yan etkisizdir) |
| [server/src/db.js:299](../../server/src/db.js#L299) | <code>ELSIF current_def NOT LIKE '%super_user%'</code> | users_role_check yalnız eksikse/eski tanımsa yenilenir; her açılışta DROP/ADD yapılmaz |
| [server/src/server.js:384](../../server/src/server.js#L384) | <code>console.error('Server startup failed:', error);</code> | Hata burada günlüğe yazılır ve süreç kapanır (PM2 döngüsü başlar) |

**Olası nedenler**
- Mevcut veride yinelenen değer yüzünden bir UNIQUE indeks oluşturulamıyor (login_name, mqtt_username, e-posta, client_log_id)
- DB kullanıcısı tablonun sahibi değil: ALTER TABLE yetki hatası (PostgreSQL kuralı)
- Bir önceki ifade yarım kalmıştı: ensureDbSchema TEK transaction DEĞİLDİR; ifadeler sırayla uygulanır, hata yeri sonrası uygulanmaz
- idle_in_transaction / statement_timeout yüzünden uzun bir ALTER kesildi

**Adım adım kontrol**
- Günlükteki hata iletisinden kısıt/indeks adını okuyun (örn. idx_users_login_name_unique).
- Yinelenen kayıt arayın (aşağıdaki sorgular salt-okunurdur); veriyi düzeltmeden API'yi yeniden başlatmak aynı hatayı verir.
- İfadeler idempotent: düzeltme sonrası pm2 restart kapi-api yeterlidir; elle DDL yazmayın.

**Günlükte aranacak ifadeler**
- `Server startup failed:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a -A4 'Server startup failed' | head -n 12 | cut -c1-220"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT LOWER(login_name) AS ad, count(*) FROM users WHERE login_name IS NOT NULL GROUP BY 1 HAVING count(*) > 1;"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT mqtt_username, count(*) FROM devices WHERE mqtt_username IS NOT NULL GROUP BY 1 HAVING count(*) > 1;"
```

**İlgili testler:** [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js), [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist)

<a id="altyapi-db-havuz-zaman-asimi"></a>
### altyapi-db-havuz-zaman-asimi · İstekler yavaşlıyor ya da askıda kalıyor; sorgu/bağlantı zaman aşımı (havuz doldu, statement timeout, idle in transaction)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/db.js:68](../../server/src/db.js#L68) | <code>const DB_POOL_MAX = Math.max(2, Number(process.env.DB_POOL_MAX) &#124;&#124; 12);</code> | Aynı anda en fazla 12 bağlantı (DB_POOL_MAX); hepsi doluysa yenisi bağlantı bekler |
| [server/src/db.js:82](../../server/src/db.js#L82) | <code>statement_timeout: DB_STATEMENT_TIMEOUT_MS,</code> | Tek sorgunun en uzun süresi 30 sn (DB_STATEMENT_TIMEOUT_MS); kilit beklemeyi de kapsar |
| [server/src/db.js:83](../../server/src/db.js#L83) | <code>query_timeout: DB_STATEMENT_TIMEOUT_MS + 5000,</code> | İstemci tarafı sorgu zaman aşımı: sunucu iptal etmezse 5 sn sonra istemci bırakır |
| [server/src/db.js:78](../../server/src/db.js#L78) | <code>options: '-c timezone=Europe/Istanbul -c idle_in_transaction_session_timeout=60000',</code> | Açık unutulan transaction 60 sn sonra SUNUCU tarafında kapatılır (kilit sızıntısını önler) |
| [server/src/db.js:90](../../server/src/db.js#L90) | <code>console.error('[DB] Bosta bekleyen istemci hatasi:', error?.code &#124;&#124; error?.message);</code> | Boştaki bağlantı koparsa süreç düşmez; yalnız bu satır yazılır |
| [server/src/db.js:85](../../server/src/db.js#L85) | <code>application_name: 'kapi-api',</code> | pg_stat_activity'de API bağlantılarını ayırt etmek için ad |

**Olası nedenler**
- Uzun süren sorgu ya da kilit (başka bir transaction satırı tutuyor) bağlantıları dolduruyor
- Trafik/eşzamanlılık havuz sınırını (12) aşıyor
- Postgres konteyneri aşırı yüklü ya da yeniden başlıyor

**Adım adım kontrol**
- pg_stat_activity: application_name = kapi-api bağlantıları state'e göre (idle / active / idle in transaction) sayın; "idle in transaction" çoksa transaction sızıntısı vardır.
- Uzun süredir çalışan sorguları listeleyin; kilit bekleyenleri wait_event_type ile görün.
- Sınırları ihtiyaç halinde .env'den ayarlayın: DB_POOL_MAX, DB_STATEMENT_TIMEOUT_MS, DB_CONNECT_TIMEOUT_MS (varsayılanlar server/.env.example'da).

**Günlükte aranacak ifadeler**
- `[DB] Bosta bekleyen istemci hatasi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT state, count(*) FROM pg_stat_activity WHERE application_name = 'kapi-api' GROUP BY 1;"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT pid, state, wait_event_type, now() - query_start AS sure, left(query, 80) AS sorgu FROM pg_stat_activity WHERE application_name = 'kapi-api' AND state <> 'idle' ORDER BY query_start LIMIT 10;"
```

**İlgili testler:** [server/test/core_robustness.test.js](../../server/test/core_robustness.test.js)

**Bkz.:** [altyapi-health-database-disconnected](#altyapi-health-database-disconnected), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor)

<a id="altyapi-db-baglanti-reddi"></a>
### altyapi-db-baglanti-reddi · Açılışta "Server startup failed:" + ECONNREFUSED 127.0.0.1:5432 / "password authentication failed" / "database ... does not exist"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/db.js:73](../../server/src/db.js#L73) | <code>host: process.env.DB_HOST,</code> | Bağlantı bilgileri yalnız ortamdan okunur (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD) |
| [docker-compose.yml:19](../../docker-compose.yml#L19) | <code>- "127.0.0.1:5432:5432"</code> | Postgres yalnız loopback'e bağlıdır: API aynı makinede olmalı; dışarıdan erişim SSH tüneliyle |
| [docker-compose.yml:5](../../docker-compose.yml#L5) | <code># NOT: POSTGRES_PASSWORD yalnizca BOS veri dizininde (ilk kurulum) uygulanir.</code> | POSTGRES_PASSWORD sonradan değişse de mevcut veritabanının parolası DEĞİŞMEZ (ALTER USER gerekir) |
| [server/.env.example:31](../../server/.env.example#L31) | <code>DB_HOST=127.0.0.1</code> | Beklenen canlı DB_HOST; DB_PASSWORD docker-compose POSTGRES_PASSWORD ile aynı olmalı |
| [server/src/config/env.js:272](../../server/src/config/env.js#L272) | <code>const missingDb = ['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'].filter((name) =&gt; !isSe…</code> | Eksik DB_* değişkeni açılışta uyarı olarak görünür |

**Olası nedenler**
- Postgres konteyneri kapalı/yeniden başlıyor (ECONNREFUSED)
- DB_PASSWORD, veritabanındaki gerçek parolayla uyuşmuyor (password authentication failed)
- DB_NAME/DB_USER yanlış (database/role does not exist)
- DB_HOST başka bir makineyi gösteriyor; konteyner dışarıya kapalı

**Adım adım kontrol**
- docker ps: site_kapi_kontrol_postgres çalışıyor ve "healthy" mi?
- Parola şüphesi: değeri yazdırmayın; psql ile (konteyner içinden) bağlanabiliyorsanız parola DB'de çalışır, sorun server/.env DB_PASSWORD'dedir. Parola değişimi: ALTER USER postgres PASSWORD ... + server/.env'i AYNI değerle güncelleyin.
- Düzeltmeden sonra pm2 restart kapi-api --update-env ve /health.

**Günlükte aranacak ifadeler**
- `Server startup failed:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "docker ps --format '{{.Names}} | {{.Status}} | {{.Ports}}'"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT 1;"
ssh -p 22667 salihceylan@178.210.161.55 "docker logs --tail 40 site_kapi_kontrol_postgres 2>&1 | cut -c1-200"
```

**İlgili testler:** [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor), [altyapi-health-database-disconnected](#altyapi-health-database-disconnected)

<a id="altyapi-docker-postgres-calismiyor"></a>
### altyapi-docker-postgres-calismiyor · Postgres konteyneri çalışmıyor/unhealthy ya da "docker compose up" POSTGRES_PASSWORD zorunlu hatasıyla duruyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [docker-compose.yml:12](../../docker-compose.yml#L12) | <code>container_name: site_kapi_kontrol_postgres</code> | Konteyner adı: docker exec / docker logs komutlarında bu ad kullanılır |
| [docker-compose.yml:17](../../docker-compose.yml#L17) | <code>POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD zorunlu - depo kokundeki .env d…</code> | Parola tanımsızsa compose KASITLI olarak hata verip durur (varsayılan parola yok); depo kökündeki .env'e yazılır |
| [docker-compose.yml:13](../../docker-compose.yml#L13) | <code>restart: unless-stopped</code> | Elle durdurulmadıkça sunucu yeniden açılınca konteyner da geri gelir |
| [docker-compose.yml:20](../../docker-compose.yml#L20) | <code>healthcheck:</code> | pg_isready ile 10 sn'de bir sağlık denetimi; docker ps'te "healthy/unhealthy" buradan |
| [docker-compose.yml:27](../../docker-compose.yml#L27) | <code>- pg_data:/var/lib/postgresql/data</code> | Veri adlandırılmış volume'da; `docker compose down -v` ya da volume silinirse TÜM veri gider |
| [sunucu_kurulum.txt:54](../../sunucu_kurulum.txt#L54) | <code>docker-compose up -d postgres</code> | Kurulumda Postgres'in kaldırılma komutu |

**Olası nedenler**
- POSTGRES_PASSWORD depo kökündeki .env ya da ortamda tanımlı değil (compose hata verir)
- Konteyner durmuş (disk dolu, docker servisi kapalı, elle durduruldu)
- Volume silindi/yenilendi: veri yok, şema boş (altyapi-sema-users-yok)

**Adım adım kontrol**
- docker ps -a ile durumu, docker logs ile son satırları okuyun.
- Disk doluluğunu kontrol edin (df -h /var/www).
- Konteyneri yeniden başlatmadan önce volume'a DOKUNMAYIN; yedekler ~/backups/kapi_<TS>/db.sql.gz içindedir.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "docker ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}}' | head -n 8"
ssh -p 22667 salihceylan@178.210.161.55 "docker logs --tail 50 site_kapi_kontrol_postgres 2>&1 | cut -c1-200"
ssh -p 22667 salihceylan@178.210.161.55 "df -h /var/www | tail -n 1"
```

**Bkz.:** [altyapi-db-baglanti-reddi](#altyapi-db-baglanti-reddi), [altyapi-sema-users-yok](#altyapi-sema-users-yok), [altyapi-geri-alma-ve-yedek](#altyapi-geri-alma-ve-yedek)

<a id="altyapi-migrate-baseline-reddi"></a>
### altyapi-migrate-baseline-reddi · node scripts/migrate.js --apply: "REDDEDILDI: schema_migrations yok/bos ama veritabaninda users tablosu var"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/migrate.js:518](../../server/scripts/migrate.js#L518) | <code>`REDDEDILDI: ${MIGRATIONS_TABLE} ${tablePresent ? 'bos' : 'yok'} ama veritabaninda 'users…</code> | Takip tablosu boşken ve users tablosu varken --apply reddedilir (tüm migration'ları yeniden çalıştırmak veriyi bozabilir) |
| [server/scripts/migrate.js:437](../../server/scripts/migrate.js#L437) | <code>async function runBaseline(opts, env, log, logError, open, ask) {</code> | --baseline <numara>: SQL ÇALIŞTIRMADAN <= numara olan migration'ları "uygulanmış" diye işaretler |
| [server/scripts/migrate.js:481](../../server/scripts/migrate.js#L481) | <code>`INSERT INTO ${MIGRATIONS_TABLE} (version, checksum) VALUES ($1, $2) ON CONFLICT (version…</code> | Baseline yalnız schema_migrations'a (version, checksum) yazar |
| [server/scripts/migrate.js:451](../../server/scripts/migrate.js#L451) | <code>"UYARI: 'users' tablosu yok; bu veritabani bos gorunuyor. Bos veritabanina baseline yazma…</code> | Boş veritabanına baseline yazmak da engellenir (--force ile aşılır; yapmayın) |
| [sunucu_kurulum.txt:151](../../sunucu_kurulum.txt#L151) | <code>node scripts/migrate.js --baseline 24</code> | Canlıdaki ilk kurulum örneği (o günkü son numara 24; şimdi klasördeki en yüksek numara 028) |

**Olası nedenler**
- Canlı/yerel veritabanı zaten kurulu ama migrate.js hiç kullanılmamış (schema_migrations yok)

**Adım adım kontrol**
- Şema gerçekten migration'larla uyumlu mu doğrulayın (baseline SQL çalıştırmaz, yalnız kayıt tutar).
- Sıra: --status → --baseline <son uygulanmış numara> → --apply --dry-run → --apply. ssh ile onay istenirse --yes ya da ssh -t kullanın.
- Not: db.js (ensureDbSchema) zaten idempotent olarak şemayı tamamlar; migrate.js asıl olarak yeni/boş kurulumlar içindir.

**Günlükte aranacak ifadeler**
- `REDDEDILDI:`
- `Hedef veritabani:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --status"
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --apply --dry-run"
# DEĞİŞTİRİR (yalnız kayıt yazar): ssh -p 22667 salihceylan@178.210.161.55 -t "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --baseline 28"
```

**İlgili testler:** [server/test/ops_migrate_runner.test.js](../../server/test/ops_migrate_runner.test.js)

**Bkz.:** [altyapi-sema-users-yok](#altyapi-sema-users-yok), [altyapi-migrate-sql-hatasi](#altyapi-migrate-sql-hatasi), [altyapi-migrate-uyarilar-checksum](#altyapi-migrate-uyarilar-checksum)

<a id="altyapi-migrate-sql-hatasi"></a>
### altyapi-migrate-sql-hatasi · migrate.js: "HATA (NNN_ad): ..." + "Bu migration geri alindi; sonrakiler calistirilmadi" ya da "ust duzey BEGIN/COMMIT/CONCURRENTLY"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/migrate.js:570](../../server/scripts/migrate.js#L570) | <code>logError('Bu migration geri alindi; sonrakiler calistirilmadi.');</code> | Her migration TEK transaction'da çalışır; hata olursa ROLLBACK edilir ve sonrakiler çalıştırılmaz |
| [server/scripts/migrate.js:278](../../server/scripts/migrate.js#L278) | <code>export function findUnsafeStatements(sql) {</code> | Çalıştırmadan önce taranır: üst düzey BEGIN/COMMIT, START TRANSACTION, CONCURRENTLY, VACUUM yasak |
| [server/scripts/migrate.js:287](../../server/scripts/migrate.js#L287) | <code>problems.push(`ust duzey ${firstWord} ifadesi (calistirici zaten transaction acar)`);</code> | Hata iletisi: dosyanın kendi BEGIN/COMMIT'i koşucunun transaction'ını bozar (DO $$ ... BEGIN ... $$ blokları sorun değildir) |
| [server/scripts/migrate.js:182](../../server/scripts/migrate.js#L182) | <code>export function blankSqlNoise(sql) {</code> | Yorum, metin sabiti ve dollar-quoted gövdeleri boşaltıp yanlış pozitifi önler |

**Olası nedenler**
- SQL hatası: eksik tablo (başka tabloya bağımlı), yinelenen veri, yetki
- Migration dosyası kendi BEGIN/COMMIT ya da CREATE INDEX CONCURRENTLY içeriyor
- Bağımlı olunan tablo yalnız db.js'te tanımlı ve henüz oluşmamış (altyapi-relation-does-not-exist)

**Adım adım kontrol**
- Çıktıdaki sürümü (NNN_ad) ve PostgreSQL hata metnini okuyun; o migration geri alınmıştır, öncekiler uygulanmış kalır.
- Uygulanmış bir migration dosyasını DÜZENLEMEYİN; düzeltme için yeni numaralı bir migration ekleyin (checksum uyarısı).
- Önce --apply --dry-run ile bekleyenleri ve güvenlik taramasını görün.

**Günlükte aranacak ifadeler**
- `HATA (`
- `Bu migration geri alindi; sonrakiler calistirilmadi.`
- `Migration dosyalari tek transaction icinde calistirilamiyor`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --apply --dry-run"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT version, applied_at FROM schema_migrations ORDER BY version DESC LIMIT 5;"
```

**İlgili testler:** [server/test/ops_migrate_runner.test.js](../../server/test/ops_migrate_runner.test.js), [server/test/ops_migration_chain.test.js](../../server/test/ops_migration_chain.test.js)

**Bkz.:** [altyapi-migrate-baseline-reddi](#altyapi-migrate-baseline-reddi), [altyapi-migrate-uyarilar-checksum](#altyapi-migrate-uyarilar-checksum)

<a id="altyapi-migrate-uyarilar-checksum"></a>
### altyapi-migrate-uyarilar-checksum · migrate.js --status: "[!] ... dosya uygulandiktan sonra DEGISMIS", "[?] ... DB'de kayitli ama dosyasi yok", "Ayni numarali iki migration var" ya da "Gecersiz migration dosya adi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/migrate.js:306](../../server/scripts/migrate.js#L306) | <code>export function planMigrations(local, appliedRows) {</code> | Yerel dosyalarla schema_migrations karşılaştırması: applied / pending / changed / unknown |
| [server/scripts/migrate.js:402](../../server/scripts/migrate.js#L402) | <code>const note = entry.checksumChanged ? '  UYARI: dosya uygulandiktan sonra DEGISMIS (checks…</code> | Uygulanmış migration'ın içeriği (SHA-256) sonradan değişmiş; yeniden ÇALIŞTIRILMAZ, yalnız uyarı |
| [server/scripts/migrate.js:409](../../server/scripts/migrate.js#L409) | <code>log(`  [?] ${row.version}  (DB'de kayitli ama dosyasi yok)`);</code> | DB'de kaydı olan ama klasörde dosyası bulunmayan sürüm (dosya silinmiş/yeniden adlandırılmış) |
| [server/scripts/migrate.js:154](../../server/scripts/migrate.js#L154) | <code>`Gecersiz migration dosya adi: ${entry.name} (beklenen bicim: NNN_aciklama.sql)`,</code> | Dosya adı NNN_aciklama.sql biçiminde olmalı (MIGRATION_FILE_RE) |
| [server/scripts/migrate.js:170](../../server/scripts/migrate.js#L170) | <code>`Ayni numarali iki migration var: ${migrations[i - 1].file} ve ${migrations[i].file}`,</code> | Aynı numaralı iki dosya koşucuyu durdurur |

**Olası nedenler**
- Uygulanmış migration dosyası elle düzenlendi (CRLF/LF ve BOM farkı checksum'a girmez; içerik farkı girer)
- Dosya yeniden adlandırıldı ya da silindi
- İki geliştirici aynı numarayı kullandı

**Adım adım kontrol**
- [!] yalnız uyarıdır; düzeltmek için eski dosyayı git geçmişinden geri getirin ya da değişikliği yeni numaralı migration olarak ekleyin.
- Numara çakışmasında sonrakini bir sonraki boş numaraya taşıyın (docker initdb.d adı alfabetik sırayla uygular).

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --status"
```

**İlgili testler:** [server/test/ops_migrate_runner.test.js](../../server/test/ops_migrate_runner.test.js)

**Bkz.:** [altyapi-migrate-sql-hatasi](#altyapi-migrate-sql-hatasi), [altyapi-migrate-baseline-reddi](#altyapi-migrate-baseline-reddi)

<a id="altyapi-migrate-baglanti-kilit"></a>
### altyapi-migrate-baglanti-kilit · migrate.js "Eksik ortam degiskeni: DB_HOST..." veriyor, kilit beklerken takılıyor ya da "Onay gerekli ama etkilesimli terminal yok"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/migrate.js:327](../../server/scripts/migrate.js#L327) | <code>export function dbConfigFromEnv(env) {</code> | DB_HOST, DB_NAME, DB_USER zorunlu; DB_PORT geçersizse hata ("Eksik ortam degiskeni" / "DB_PORT gecersiz") |
| [server/scripts/migrate.js:45](../../server/scripts/migrate.js#L45) | <code>const ADVISORY_LOCK_KEY = '7420251';</code> | Eş zamanlı çalışmayı pg_advisory_lock ile engeller; başka bir migrate süreci açıksa bekler |
| [server/scripts/migrate.js:371](../../server/scripts/migrate.js#L371) | <code>const lockTimeoutMs = Math.max(1000, Number(process.env.MIGRATE_LOCK_TIMEOUT_MS &#124;&#124; 15_000…</code> | Kilit bekleme zaman aşımı (lock_timeout, varsayılan 15 sn); DDL başka bir oturumun kilidine takılırsa bu sürede hata verir |
| [server/scripts/migrate.js:356](../../server/scripts/migrate.js#L356) | <code>console.error('Onay gerekli ama etkilesimli terminal yok. Otomasyon icin --yes kullanin.'…</code> | TTY yokken (ssh komutu, otomasyon) onay alınamaz; --yes verin ya da ssh -t kullanın |

**Olası nedenler**
- Komut server/ dizininde çalıştırılmadı: dotenv .env'i bulamadı (DB_* eksik)
- Başka bir migrate süreci/transaction kilidi tutuyor
- ssh ile TTY olmadan çalıştırıldı ve --yes verilmedi

**Adım adım kontrol**
- Komutu cd /var/www/site_kapi_kontrol/server içinden çalıştırın; "Hedef veritabani: host:port/db (kullanici: ...)" satırı doğru hedefi göstermeli (parola yazılmaz).
- Bekliyorsa pg_stat_activity'de uzun süren oturumlara bakın.

**Günlükte aranacak ifadeler**
- `Eksik ortam degiskeni:`
- `Hedef veritabani:`
- `Onay gerekli ama etkilesimli terminal yok.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/migrate.js --status"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT pid, state, wait_event_type, left(query, 80) FROM pg_stat_activity WHERE state <> 'idle' ORDER BY query_start LIMIT 10;"
```

**İlgili testler:** [server/test/ops_migrate_runner.test.js](../../server/test/ops_migrate_runner.test.js)

**Bkz.:** [altyapi-migrate-baseline-reddi](#altyapi-migrate-baseline-reddi), [altyapi-migrate-sql-hatasi](#altyapi-migrate-sql-hatasi)

<a id="altyapi-apply-betikleri-dev-guard"></a>
### altyapi-apply-betikleri-dev-guard · apply_0xx.js / check_*.js / test_*.js çalıştırınca "Bu gelistirme betigi gercek veritabanina dokunabilir..." yazıp hemen çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/_dev_guard.js:3](../../server/scripts/_dev_guard.js#L3) | <code>if (process.env.ALLOW_DEV_SCRIPTS !== '1') {</code> | Bayrak 1 değilse betik hiçbir şey yapmadan çıkar (gerçek DB'ye kazara dokunulmasın) |
| [server/scripts/_dev_guard.js:5](../../server/scripts/_dev_guard.js#L5) | <code>'Bu gelistirme betigi gercek veritabanina dokunabilir. Bilerek calistirmak icin ALLOW_DEV…</code> | Görülen mesaj |
| [server/scripts/apply_016.js:1](../../server/scripts/apply_016.js#L1) | <code>import './_dev_guard.js';</code> | Her apply_*/check_*/test_* betiğinin İLK importu bekçidir |
| [server/scripts/apply_024.js:12](../../server/scripts/apply_024.js#L12) | <code>const sqlPath = path.join(__dirname, '..', 'migrations', '024_device_inventory_and_defect…</code> | apply_* betikleri yalnız 013-024 içindir; 025-028 için betik YOKTUR (migrate.js ya da ensureDbSchema kullanılır) |
| [server/.env.example:242](../../server/.env.example#L242) | <code># ALLOW_DEV_SCRIPTS=1</code> | Yalnız geliştirmede tanımlanır; üretimde tanımlamayın |

**Olası nedenler**
- Bekçi kasıtlı çalışıyor: ALLOW_DEV_SCRIPTS=1 verilmedi

**Adım adım kontrol**
- Canlı/üretim veritabanında bu betikleri çalıştırmayın; şema için `node scripts/migrate.js` ya da API açılışındaki ensureDbSchema kullanılır.
- Gerçekten geliştirme DB'sindeyseniz: ALLOW_DEV_SCRIPTS=1 node scripts/apply_016.js (hedef DB .env'den okunur).

**Günlükte aranacak ifadeler**
- `Bu gelistirme betigi gercek veritabanina dokunabilir`

**Bkz.:** [altyapi-migrate-baseline-reddi](#altyapi-migrate-baseline-reddi), [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist)

<a id="altyapi-bakim-temizlik-hatasi"></a>
### altyapi-bakim-temizlik-hatasi · Günlükte "[Bakim] Temizlik hatasi" / "[Maintenance Cleanup] Hata:"; yönetici panelinde veritabanı sağlığı "temizlenecek kayıt var" kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/server.js:362](../../server/src/server.js#L362) | <code>void runCleanupSafely();</code> | Temizlik her AÇILIŞTA bir kez çalışır (PM2 sık yeniden başlıyorsa sık çalışır) |
| [server/src/server.js:364](../../server/src/server.js#L364) | <code>setInterval(runCleanupSafely, 24 * 60 * 60 * 1000).unref();</code> | Ardından 24 saatte bir; unref sayesinde süreç kapanmasını engellemez |
| [server/src/server.js:340](../../server/src/server.js#L340) | <code>console.error('[Bakim] Temizlik hatasi:', error?.code &#124;&#124; error?.message);</code> | Beklenmeyen fırlatma burada yakalanır (süreç düşmez) |
| [server/src/services/maintenance_service.js:113](../../server/src/services/maintenance_service.js#L113) | <code>console.error('[Maintenance Cleanup] Hata:', error);</code> | DB hatası: ayrıntı yalnız günlükte; dönen değerde "Veritabanı temizliği başarısız oldu." genel metni vardır |
| [server/src/services/maintenance_service.js:95](../../server/src/services/maintenance_service.js#L95) | <code>VALUES ('routine_cleanup', NOW())</code> | Son başarılı temizlik zamanı app_maintenance_runs'a yazılır |
| [server/src/services/maintenance_service.js:224](../../server/src/services/maintenance_service.js#L224) | <code>isClean: pendingTotal === 0,</code> | Panelin "temiz" durumu yalnız silinebilir kayıt sayısına bağlıdır |

**Olası nedenler**
- app_maintenance_runs ya da silinen tablolardan biri yok (şema tamamlanmadı) (altyapi-relation-does-not-exist)
- Silme sırasında zaman aşımı/kilit

**Adım adım kontrol**
- Günlükte "[Maintenance Cleanup] Hata:" satırının PostgreSQL ayrıntısını okuyun.
- Son başarılı temizlik: app_maintenance_runs sorgusu (aşağıda). Temizlik hesap/kullanıcı SİLMEZ.
- Yönetici panelinden elle tetikleme ve sağlık özeti: /admin/maintenance/health, /admin/maintenance/cleanup (super_user).

**Günlükte aranacak ifadeler**
- `[Bakim] Temizlik hatasi:`
- `[Maintenance Cleanup] Hata:`
- `[Maintenance Cleanup]: Rutin temizlik`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT maintenance_key, executed_at FROM app_maintenance_runs;"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Maintenance Cleanup\|\[Bakim\]' | tail -n 5 | cut -c1-200"
```

**İlgili testler:** [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js)

**Bkz.:** [altyapi-bakim-saklama-sureleri](#altyapi-bakim-saklama-sureleri), [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist)

<a id="altyapi-bakim-saklama-sureleri"></a>
### altyapi-bakim-saklama-sureleri · Eski kapı/bağlantı kayıtları, QR token'ları ve e-posta kodları kayboluyor (30 gün / 1-2 gün sonra siliniyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/maintenance_service.js:82](../../server/src/services/maintenance_service.js#L82) | <code>DELETE FROM door_access_logs</code> | Kapı geçiş logları 30 günden eski silinir (opened_at) |
| [server/src/services/maintenance_service.js:75](../../server/src/services/maintenance_service.js#L75) | <code>DELETE FROM device_connectivity_logs</code> | Cihaz bağlantı (offline) logları 30 günden eski silinir |
| [server/src/services/maintenance_service.js:33](../../server/src/services/maintenance_service.js#L33) | <code>DELETE FROM qr_access_tokens</code> | Süresi dolmuş ya da yenisiyle değiştirilmiş (superseded) QR token'lar 1 gün sonra silinir |
| [server/src/services/maintenance_service.js:41](../../server/src/services/maintenance_service.js#L41) | <code>DELETE FROM email_verifications</code> | E-posta doğrulama kodu kayıtları 2 günden eski silinir |
| [server/src/services/maintenance_service.js:48](../../server/src/services/maintenance_service.js#L48) | <code>DELETE FROM pending_registrations</code> | Doğrulanmamış bekleyen kayıtlar (hesap DEĞİL) 2 gün sonra silinir; kullanıcı yeniden kayıt olur |

**Olası nedenler**
- Beklenen davranış: rutin temizlik yalnız süresi dolmuş token/kod ve eski logları siler; users/üyelik/tablo silmez

**Adım adım kontrol**
- 30 günden eski kapı logu "kayıp" ise arıza değil saklama kuralıdır; daha uzun saklama gerekiyorsa maintenance_service.js'teki aralık değiştirilir (kod değişikliği + dağıtım).
- Kullanıcı kaydı kaybı şüphesi varsa temizlik değil başka bir silme yoludur: altyapi-bakim-temizlik-hatasi ve admin silme uçlarına bakın.

**Günlükte aranacak ifadeler**
- `[Maintenance Cleanup]: Rutin temizlik`

**İlgili testler:** [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js)

**Bkz.:** [altyapi-bakim-temizlik-hatasi](#altyapi-bakim-temizlik-hatasi)

<a id="altyapi-mqtt-tls-baglanti"></a>
### altyapi-mqtt-tls-baglanti · MQTT köprüsü broker'a bağlanamıyor: günlükte "[MQTT bridge] ..." sertifika/TLS hatası ya da ECONNREFUSED/ETIMEDOUT

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1012](../../server/src/mqtt_bridge.js#L1012) | <code>client = mqtt.connect(`mqtts://${config.connectHost}:${config.port}`, {</code> | Köprü HER ZAMAN mqtts://MQTT_HOST:MQTT_PORT (varsayılan 8883) ile bağlanır; düz mqtt yoktur |
| [server/src/mqtt_bridge.js:75](../../server/src/mqtt_bridge.js#L75) | <code>rejectUnauthorized: !envFlag('MQTT_ALLOW_INSECURE_TLS', false),</code> | Sertifika doğrulaması varsayılan AÇIK; yalnız MQTT_ALLOW_INSECURE_TLS=1/true ile kapanır |
| [server/src/mqtt_bridge.js:1020](../../server/src/mqtt_bridge.js#L1020) | <code>connectTimeout: 10000,</code> | Bağlantı kurma zaman aşımı 10 sn; erişilemeyen broker bu süre sonunda hata verir ve 3 sn'de bir yeniden denenir |
| [MQTT_kurulum.txt:39](../../MQTT_kurulum.txt#L39) | <code>3) TLS sertifikasi (Let's Encrypt)</code> | Broker sertifikası certbot ile alınır (mqtt.gudeteknoloji.com.tr) |
| [MQTT_kurulum.txt:42](../../MQTT_kurulum.txt#L42) | <code>4) Sertifika dosyalarini Mosquitto yoluna bagla</code> | Let's Encrypt dosyalarına /etc/mosquitto/certs altındaki bağlantılarla erişilir; izinler/sahiplik burada tanımlı |
| [MQTT_kurulum.txt:145](../../MQTT_kurulum.txt#L145) | <code>tls_version tlsv1.2</code> | Broker 8883 dinleyicisi en az TLS 1.2 ister |

**Olası nedenler**
- Sertifika süresi doldu ya da yenilendi ama mosquitto yenilenen dosyayı almadı (servisi yeniden başlatmak gerekir)
- MQTT_HOST, sertifikadaki ada uymuyor (ör. IP ile bağlanma) ya da DNS yanlış
- 8883/TCP güvenlik duvarında kapalı ya da mosquitto dinlemiyor (ECONNREFUSED / ETIMEDOUT)
- MQTT_PORT yanlış

**Adım adım kontrol**
- Sertifika bitiş tarihini dışarıdan doğrulayın (aşağıdaki openssl komutu); süresi dolmuşsa sudo certbot certificates ile yenileme durumuna bakın.
- MQTT_ALLOW_INSECURE_TLS=1 yapmak sorunu GİZLER ve güvenliği kapatır: yalnız geliştirmede kullanın, üretimde asla.
- Köprü günlüğü dakikada en fazla bir kez yazar: "[MQTT bridge] <hata>" satırının zamanına dikkat edin.

**Günlükte aranacak ifadeler**
- `[MQTT bridge]`
- `MQTT bridge connected:`

**Komutlar**
```bash
echo | openssl s_client -connect mqtt.gudeteknoloji.com.tr:8883 -servername mqtt.gudeteknoloji.com.tr 2>/dev/null | openssl x509 -noout -dates
ssh -p 22667 salihceylan@178.210.161.55 "sudo systemctl status mosquitto --no-pager | head -n 12"
ssh -p 22667 salihceylan@178.210.161.55 "sudo ss -ltnp | grep 8883"
```

**Bkz.:** [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-sertifika-suresi](#altyapi-sertifika-suresi), [altyapi-mosquitto-servis-calismiyor](#altyapi-mosquitto-servis-calismiyor)

<a id="altyapi-mqtt-kimlik-reddi"></a>
### altyapi-mqtt-kimlik-reddi · Köprü bağlanıp hemen kopuyor; günlükte "[MQTT bridge] Connection refused: Not authorized" benzeri kimlik hatası (api_bridge parolası)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1014](../../server/src/mqtt_bridge.js#L1014) | <code>username: config.username,</code> | Köprü MQTT_USER (api_bridge) ve MQTT_PASSWORD ile bağlanır |
| [server/src/mqtt_bridge.js:1060](../../server/src/mqtt_bridge.js#L1060) | <code>recordBridgeError('mqtt_error', error.message);</code> | Kütüphanenin kimlik reddi iletisi buraya düşer ve /health'te last_error:"mqtt_error" olur |
| [MQTT_kurulum.txt:52](../../MQTT_kurulum.txt#L52) | <code>5) MQTT kullanicilarini olustur</code> | api_bridge ve cihaz kullanıcıları mosquitto_passwd ile oluşturulur (-c yalnız İLK kullanıcıda: dosyayı sıfırlar) |
| [MQTT_kurulum.txt:255](../../MQTT_kurulum.txt#L255) | <code>Sifre bir yere acik yazildiysa veya git gecmisine girdiyse DONDURULMALI:</code> | api_bridge parola döndürme sırası: mosquitto_passwd (-c OLMADAN) → server/.env MQTT_PASSWORD → pm2 restart --update-env |
| [server/scripts/sync_mqtt_acl.js:86](../../server/scripts/sync_mqtt_acl.js#L86) | <code>if (username.startsWith('device_') &amp;&amp; !wantedUsers.has(username)) {</code> | Senkron yalnız device_* ve eski kullanıcıları siler; api_bridge passwd satırına dokunmaz (parolası elle yönetilir) |

**Olası nedenler**
- server/.env MQTT_PASSWORD ile broker passwd dosyasındaki api_bridge parolası uyuşmuyor (parola döndürüldü, .env güncellenmedi)
- passwd dosyası mosquitto_passwd -c ile yeniden yaratıldı: api_bridge ve tüm cihaz kullanıcıları silindi
- MQTT_USER api_bridge dışında bir ad

**Adım adım kontrol**
- Parolayı komut satırına/betiğe AÇIK yazmayın; yalnız server/.env (chmod 600) içinde tutulur.
- passwd'de yalnız api_bridge eksikse elle ekleyin (-c OLMADAN); cihaz kullanıcıları eksikse sudo -n /usr/local/bin/kapi-mqtt-sync ile DB'den yeniden yazılır.
- Düzeltmeden sonra pm2 restart kapi-api --update-env; günlükte "MQTT bridge connected:" ve /health mqtt.connected:true.

**Günlükte aranacak ifadeler**
- `[MQTT bridge]`
- `MQTT bridge connected:`

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a 'MQTT bridge' | tail -n 5 | cut -c1-200"
```

**Bkz.:** [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-kapi-mqtt-sync-betik-hatalari](#altyapi-kapi-mqtt-sync-betik-hatalari)

<a id="altyapi-mqtt-konu-ve-uid"></a>
### altyapi-mqtt-konu-ve-uid · Cihaz MQTT'ye yayın yapıyor ama sunucu durumunu/olayını görmüyor (konu adı, UID biçimi ya da kayıtsız cihaz)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1027-1032](../../server/src/mqtt_bridge.js#L1027-L1032) | <code>client.subscribe('device/+/availability', { qos: 1 });</code> | Köprünün abone olduğu 6 konu: availability, state, event, logs, qr_verify, screen_qr (qos 1) |
| [server/src/mqtt_bridge.js:230](../../server/src/mqtt_bridge.js#L230) | <code>export function deviceUidFromTopic(topic) {</code> | Konu device/<uid>/(availability\|state\|event\|logs\|qr_verify\|screen_qr) biçiminde ve UID 6-16 onaltılık olmalı; aksi sessizce atılır |
| [server/src/mqtt_bridge.js:79](../../server/src/mqtt_bridge.js#L79) | <code>export function normalizeDeviceTopicUid(uid) {</code> | MAC biçimli UID (E0:72:...) bayt-ters çevrilip düz hex yapılır; diğerlerinde hex olmayan karakterler atılır |
| [server/src/mqtt_bridge.js:1038](../../server/src/mqtt_bridge.js#L1038) | <code>if (payload.length &gt; MAX_INBOUND_PAYLOAD_BYTES) {</code> | 16 KB üstü yük SESSİZCE atılır (günlük yok) |
| [server/src/mqtt_bridge.js:249](../../server/src/mqtt_bridge.js#L249) | <code>export async function isRegisteredDeviceUid(uid) {</code> | Yalnız devices tablosunda kayıtlı UID'ler için durum tutulur; kayıtsız sonucu 60 sn önbellekte kalır |
| [server/src/mqtt_bridge.js:244](../../server/src/mqtt_bridge.js#L244) | <code>const REGISTERED_NEGATIVE_TTL_MS = 60 * 1000;</code> | Yeni kaydedilen cihaz, önceki "kayıtsız" sonucu yüzünden en çok 1 dk daha görünmeyebilir |
| [server/src/mqtt_bridge.js:1037](../../server/src/mqtt_bridge.js#L1037) | <code>client.on('message', (topic, payload, packet) =&gt; {</code> | Gelen tüm iletilerin giriş noktası |

**Olası nedenler**
- Cihaz farklı bir konu adına yayın yapıyor (ör. device/<uid>/status) ya da UID 6-16 hex dışı
- Cihaz devices tablosunda yok / UID biçimi uyuşmuyor (DB'deki UID ile topic UID'si: MAC bayt-ters kuralı)
- Yük 16 KB'ı aşıyor (cihaz yayınları normalde ~1 KB)
- DB sorgusu hata verdi: günlükte "Cihaz kaydi sorgulanamadi" (db_error)
- ACL cihazın bu konuya yazmasına izin vermiyor (altyapi-mqtt-acl-yayin-reddi)

**Adım adım kontrol**
- Cihazın DB'de kayıtlı olduğunu doğrulayın: UID'nin hem düz hem bayt-ters biçimiyle arayın (örnek aşağıda).
- Konular için ACL ve cihaz tarafı: MQTT_kurulum.txt "Topic yapisi" bölümündeki adlarla karşılaştırın.

**Günlükte aranacak ifadeler**
- `Cihaz kaydi sorgulanamadi`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT device_uid, hardware_type, is_online FROM devices WHERE UPPER(REPLACE(REPLACE(device_uid, ':', ''), '-', '')) IN ('D4C771A172E0', 'E072A171C7D4');"
```

**İlgili testler:** [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js)

**Bkz.:** [altyapi-cihaz-cevrimdisi-gorunuyor](#altyapi-cihaz-cevrimdisi-gorunuyor), [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-acl-cihaz-atlandi](#altyapi-acl-cihaz-atlandi)

<a id="altyapi-mqtt-acl-yayin-reddi"></a>
### altyapi-mqtt-acl-yayin-reddi · Cihaz brokere bağlanıyor ama yayın yapamıyor (ACL reddi): durum/olay/log sunucuya hiç ulaşmıyor ya da komut/qr_result alamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_acl_sync.js:71](../../server/src/mqtt_acl_sync.js#L71) | <code>export function buildMqttAclText(devices) {</code> | ACL metninin üretildiği yer: önce api_bridge bloğu, sonra her geçerli cihaz için kendi UID'sine özel blok |
| [server/src/mqtt_acl_sync.js:89](../../server/src/mqtt_acl_sync.js#L89) | <code>lines.push(`topic read device/${uid}/cmd`);</code> | Cihaz yalnız KENDİ cmd ve qr_result konusunu okuyabilir |
| [server/src/mqtt_acl_sync.js:93](../../server/src/mqtt_acl_sync.js#L93) | <code>lines.push(`topic write device/${uid}/availability`);</code> | Cihaz yalnız kendi state/event/availability/qr_verify/screen_qr/logs konularına yazabilir |
| [server/src/mqtt_acl_sync.js:96](../../server/src/mqtt_acl_sync.js#L96) | <code>lines.push(`topic write device/${uid}/logs`);</code> | Çevrimdışı log teslimi için gerekli satır; eski ACL'de yoksa cihaz logları teslim edemez |
| [server/src/mqtt_acl_sync.js:82](../../server/src/mqtt_acl_sync.js#L82) | <code>'topic write device/+/qr_result',</code> | api_bridge'in cihaza QR sonucu yazabilmesi için; cihaz tarafında karşılığı topic read device/<uid>/qr_result |
| [server/scripts/sync_mqtt_acl.js:78](../../server/scripts/sync_mqtt_acl.js#L78) | <code>renameSync(tmpAclFile, aclFile);</code> | ACL dosyası geçici dosyadan atomik yazılır; mosquitto'nun yeniden yüklemesi ayrıca (kapi-mqtt-sync.sh) yapılır |
| [MQTT_kurulum.txt:193](../../MQTT_kurulum.txt#L193) | <code>Beklenen: PUBACK RC:135 (Not authorized)</code> | ACL reddinin doğrulanması: MQTT v5 ile PUBACK RC:135 yetki hatasıdır |

**Olası nedenler**
- Cihaz ACL'de yok: DB'de mqtt_username/mqtt_password boş ya da senkron hiç çalışmadı/başarısız (altyapi-acl-cihaz-atlandi, altyapi-acl-senkron-503)
- ACL eski: yeni konu satırları (logs, qr_result) yok ya da mosquitto dosyayı yeniden yüklemedi
- Cihaz firmware'i başka bir UID/kullanıcı adıyla bağlanıyor (kullanıcı adı device_<UID> olmalı)
- Broker passwd dosyasında cihaz kullanıcısı yok (bağlantı hiç kurulmaz)

**Adım adım kontrol**
- Canlı ACL'de logs satırı sayısı: remote_verify.sh "mosquitto + acl" bölümü (grep -c logs /etc/mosquitto/acl).
- Sunucunun ÜRETECEĞİ ACL'i görmek için kuru çalıştırma (dosya yazmaz, parola basmaz): node scripts/sync_mqtt_acl.js --dry-run.
- Gerekirse senkron: sudo -n /usr/local/bin/kapi-mqtt-sync (ACL + passwd yazar, mosquitto reload eder).
- Beklenen test: MQTT_kurulum.txt "12) ACL dogrulama" (RC:135 yetki hatası; RC:16 "No matching subscribers" yetki hatası DEĞİLDİR).

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "grep -c logs /etc/mosquitto/acl"
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/sync_mqtt_acl.js --dry-run | grep -A9 'user device_D4C771A172E0'"
# DEĞİŞTİRİR (ACL/passwd yazar, mosquitto reload): ssh -p 22667 salihceylan@178.210.161.55 "sudo -n /usr/local/bin/kapi-mqtt-sync"
```

**İlgili testler:** [server/test/devices_mqtt_acl.test.js](../../server/test/devices_mqtt_acl.test.js)

**Bkz.:** [altyapi-acl-cihaz-atlandi](#altyapi-acl-cihaz-atlandi), [altyapi-acl-senkron-503](#altyapi-acl-senkron-503), [altyapi-kapi-mqtt-sync-betik-hatalari](#altyapi-kapi-mqtt-sync-betik-hatalari), [altyapi-mqtt-konu-ve-uid](#altyapi-mqtt-konu-ve-uid)

<a id="altyapi-acl-cihaz-atlandi"></a>
### altyapi-acl-cihaz-atlandi · sync_mqtt_acl çıktısında "UYARI: cihaz atlandi (device_uid | mqtt_username | mqtt_password | duplicate)"; o cihaz brokere bağlanamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_acl_sync.js:36](../../server/src/mqtt_acl_sync.js#L36) | <code>export function partitionAclDevices(devices) {</code> | Geçersiz UID/kullanıcı adı/parola ve yinelenen kayıtlar ACL ve passwd'ye ALINMAZ (fail-closed); neden reason alanındadır |
| [server/src/mqtt_acl_sync.js:8](../../server/src/mqtt_acl_sync.js#L8) | <code>const ACL_DEVICE_UID_PATTERN = /^[0-9A-F]{6,32}$/;</code> | UID yalnız BÜYÜK harf onaltılık olmalı: iki nokta üst üste içeren eski MAC biçimli UID bu kalıba UYMAZ ("device_uid" nedeni) |
| [server/src/mqtt_acl_sync.js:10](../../server/src/mqtt_acl_sync.js#L10) | <code>const ACL_MQTT_USERNAME_PATTERN = /^device_[0-9A-F]{6,32}$/;</code> | Kullanıcı adı device_<UID> olmalı ("mqtt_username" nedeni) |
| [server/src/mqtt_acl_sync.js:22](../../server/src/mqtt_acl_sync.js#L22) | <code>export function isValidAclMqttPassword(password) {</code> | Parola 1-256 karakter ve kontrol karakteri içermemeli ("mqtt_password" nedeni; ACL satır enjeksiyonunu önler) |
| [server/scripts/sync_mqtt_acl.js:65](../../server/scripts/sync_mqtt_acl.js#L65) | <code>console.error(`UYARI: cihaz atlandi (${item.reason}): ${JSON.stringify(item.device_uid)}`…</code> | Atlanan her kayıt için stderr'e yazılır (UID 40 karaktere kısaltılır) |
| [server/scripts/sync_mqtt_acl.js:57](../../server/scripts/sync_mqtt_acl.js#L57) | <code>WHERE mqtt_username IS NOT NULL</code> | Yalnız mqtt_username ve mqtt_password dolu cihazlar işlenir; boş olanlar hiç görünmez |

**Olası nedenler**
- device_uid: DB'de eski MAC biçimiyle (E0:72:...) ya da küçük harfle/hatalı uzunlukta saklanmış
- mqtt_username: device_<UID> kalıbında değil ya da UID ile uyuşmayan elle yazılmış kullanıcı adı
- mqtt_password: boş/çok uzun/kontrol karakterli
- duplicate: aynı kullanıcı adı ya da UID iki satırda var
- Cihazın mqtt_username/mqtt_password alanı hiç üretilmemiş (sorguda görünmez; admin "mqtt-credentials" ucu üretir)

**Adım adım kontrol**
- Hangi cihazın neden atlandığını kuru çalıştırmayla görün (stderr satırları).
- Atlanan cihazın DB satırını inceleyin (UID biçimi); veriyi düzeltmeden senkron tekrar çalıştırmak sonucu değiştirmez.

**Günlükte aranacak ifadeler**
- `UYARI: cihaz atlandi`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/sync_mqtt_acl.js --dry-run 2>&1 >/dev/null | head -n 20"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT device_uid, mqtt_username, (mqtt_password IS NOT NULL) AS parola_var FROM devices WHERE device_uid !~ '^[0-9A-F]{6,32}$' OR mqtt_username !~ '^device_[0-9A-F]{6,32}$' ORDER BY device_uid;"
```

**İlgili testler:** [server/test/devices_mqtt_acl.test.js](../../server/test/devices_mqtt_acl.test.js)

**Bkz.:** [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-acl-senkron-503](#altyapi-acl-senkron-503)

<a id="altyapi-acl-senkron-503"></a>
### altyapi-acl-senkron-503 · Cihaz eklerken/silerken 503 "MQTT broker senkronu basarisiz" (yanıtta mqtt_sync.ok:false)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_acl_sync.js:255](../../server/src/mqtt_acl_sync.js#L255) | <code>export async function syncMqttAclOrThrow({ reason = 'manual' } = {}) {</code> | Senkron başarısızsa ve MQTT_SYNC_REQUIRED açıksa MQTT_ACL_SYNC_FAILED fırlatır (route 503 döner) |
| [server/src/mqtt_acl_sync.js:161](../../server/src/mqtt_acl_sync.js#L161) | <code>export async function syncMqttAcl({ reason = 'manual' } = {}) {</code> | MQTT_SYNC_COMMAND'ı shell OLMADAN (spawn) çalıştırır; ortamı filtreler (JWT_SECRET, SMTP_* geçmez) |
| [server/src/mqtt_acl_sync.js:174](../../server/src/mqtt_acl_sync.js#L174) | <code>const timeoutMs = Math.max(3000, Number(process.env.MQTT_SYNC_TIMEOUT_MS &#124;&#124; 30000));</code> | Senkron zaman aşımı: varsayılan 30 sn (en az 3 sn) |
| [server/src/mqtt_acl_sync.js:208](../../server/src/mqtt_acl_sync.js#L208) | <code>message: `MQTT ACL senkronu zaman asimina ugradi (${timeoutMs} ms).`,</code> | Zaman aşımı mesajı (mqtt_sync.message) |
| [server/src/mqtt_acl_sync.js:247](../../server/src/mqtt_acl_sync.js#L247) | <code>message: code === 0 ? 'MQTT ACL senkronu tamamlandi.' : `MQTT ACL senkronu hata kodu: ${c…</code> | Komut sıfır olmayan kodla çıktı (mqtt_sync.message ve stderr nedeni verir) |
| [server/src/mqtt_acl_sync.js:182](../../server/src/mqtt_acl_sync.js#L182) | <code>message: 'MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS gecersiz karakter iceriyor.',</code> | Komut/argüman güvenli karakter kümesi dışındaysa hiç çalıştırılmaz (SAFE_COMMAND_PATTERN / SAFE_ARG_PATTERN) |
| [server/src/routes/admin_routes.js:1770](../../server/src/routes/admin_routes.js#L1770) | <code>error: 'Cihaz kaydedildi ama MQTT broker senkronu basarisiz.',</code> | Cihaz kaydı DB'de oluştu ama broker senkronu başarısız: cihaz yeniden denemeye değil senkronu düzeltmeye ihtiyaç duyar |

**Olası nedenler**
- sudo parola istiyor: sudoers NOPASSWD satırı yok/yanlış (MQTT_SYNC_ARGS "-n" parola sorusunu hataya çevirir)
- /usr/local/bin/kapi-mqtt-sync kurulmamış ya da eski kopya (betik güncellenince yeniden kurulmalı)
- Sarmalayıcı hata verdi (altyapi-kapi-mqtt-sync-betik-hatalari) ya da mosquitto reload/restart başarısız
- Senkron 30 sn içinde bitmedi
- Komut/argüman geçersiz karakter içeriyor

**Adım adım kontrol**
- Yanıttaki mqtt_sync.message / stderr alanları asıl nedeni verir (bu metinler günlükte DEĞİL yanıttadır).
- Aynı komutu sunucuda elle çalıştırıp çıktısını okuyun: sudo -n /usr/local/bin/kapi-mqtt-sync (MQTT_kurulum.txt 6.1).
- Cihaz DB'de oluştuğu için senkron düzeldikten sonra tekrar senkron yeterlidir; cihazı yeniden kaydetmeyin.

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health   # mqtt.acl_sync_configured:true olmalı
ssh -p 22667 salihceylan@178.210.161.55 "ls -l /usr/local/bin/kapi-mqtt-sync"
# DEĞİŞTİRİR (ACL/passwd yazar, mosquitto reload): ssh -p 22667 salihceylan@178.210.161.55 "sudo -n /usr/local/bin/kapi-mqtt-sync; echo cikis=$?"
```

**İlgili testler:** [server/test/devices_mqtt_acl.test.js](../../server/test/devices_mqtt_acl.test.js), [server/test/fix_sx2_device_delete.test.js](../../server/test/fix_sx2_device_delete.test.js)

**Bkz.:** [altyapi-health-acl-sync-kapali](#altyapi-health-acl-sync-kapali), [altyapi-kapi-mqtt-sync-betik-hatalari](#altyapi-kapi-mqtt-sync-betik-hatalari), [altyapi-acl-cihaz-atlandi](#altyapi-acl-cihaz-atlandi)

<a id="altyapi-kapi-mqtt-sync-betik-hatalari"></a>
### altyapi-kapi-mqtt-sync-betik-hatalari · sudo -n /usr/local/bin/kapi-mqtt-sync "HATA: ..." (herkes tarafindan yazilabilir / APP_DIR / node bulunamadi) ya da sudo parola istiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/kapi-mqtt-sync.sh:21](../../server/scripts/kapi-mqtt-sync.sh#L21) | <code>fail "root olarak yalnizca ${DEFAULT_APP_DIR} kullanilabilir (ozel dizin icin KAPI_ALLOW_…</code> | Root iken yalnız varsayılan APP_DIR (/var/www/site_kapi_kontrol/server) kullanılır; ortamdan gelen dizine güvenilmez |
| [server/scripts/kapi-mqtt-sync.sh:39](../../server/scripts/kapi-mqtt-sync.sh#L39) | <code>fail "${target} herkes tarafindan yazilabilir durumda; izinleri duzeltin."</code> | scripts/sync_mqtt_acl.js, src/mqtt_acl_sync.js, src/db.js "diğer" kullanıcılarca yazılabilirse (o+w) betik reddeder (yetki yükselmesi koruması) |
| [server/scripts/kapi-mqtt-sync.sh:44](../../server/scripts/kapi-mqtt-sync.sh#L44) | <code>[ -n "$NODE_BIN" ] &#124;&#124; fail "node bulunamadi."</code> | root ortamında node PATH'te yoksa; betik node'u command -v ile arar |
| [server/scripts/kapi-mqtt-sync.sh:63](../../server/scripts/kapi-mqtt-sync.sh#L63) | <code>env -i "${ENV_ARGS[@]}" "$NODE_BIN" scripts/sync_mqtt_acl.js</code> | Node betiğine yalnız DB_*, PG*, MQTT_*, MOSQUITTO_*, KAPI_*, TZ, LC_* ortam değişkenleri geçer |
| [server/scripts/kapi-mqtt-sync.sh:65](../../server/scripts/kapi-mqtt-sync.sh#L65) | <code>if systemctl reload mosquitto; then</code> | Önce reload; başarısızsa systemctl restart mosquitto |
| [MQTT_kurulum.txt:101](../../MQTT_kurulum.txt#L101) | <code>salihceylan ALL=(root) NOPASSWD: /usr/local/bin/kapi-mqtt-sync</code> | Sudoers satırı yalnız bu tek komuta parolasız yetki verir |
| [MQTT_kurulum.txt:232](../../MQTT_kurulum.txt#L232) | <code>- Betik her degistiginde kopya yeniden kurulmali:</code> | Repodaki betik güncellenince /usr/local/bin kopyası yeniden kurulmalı (sudoers repo yolunu ASLA göstermemeli) |

**Olası nedenler**
- APP_DIR altındaki bir dosya herkes tarafından yazılabilir (izinleri gevşek): "HATA: ... herkes tarafindan yazilabilir durumda"
- sudoers NOPASSWD satırı yok/yanlış → sudo -n parola sorusunu hataya çevirir
- /usr/local/bin kopyası eski ya da root:root 0755 değil
- node root'un PATH'inde yok
- mosquitto reload ve restart ikisi de başarısız (systemctl hatası)

**Adım adım kontrol**
- Betik terminale "HATA: ..." yazar (API bu çıktıyı mqtt_sync.stderr olarak taşır).
- ls -l /usr/local/bin/kapi-mqtt-sync → sahip root:root, yalnız root yazabilir; sudoers: /etc/sudoers.d/kapi-mqtt-sync.
- Sarmalayıcı repodan değil root'a ait kopyadan çalışmalı; güncelleme: MQTT_kurulum.txt 15a'daki sudo install komutu.

**Günlükte aranacak ifadeler**
- `herkes tarafindan yazilabilir durumda`
- `node bulunamadi.`
- `root olarak yalnizca`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "ls -l /usr/local/bin/kapi-mqtt-sync /etc/sudoers.d/kapi-mqtt-sync"
ssh -p 22667 salihceylan@178.210.161.55 "ls -l /var/www/site_kapi_kontrol/server/scripts/sync_mqtt_acl.js /var/www/site_kapi_kontrol/server/src/mqtt_acl_sync.js /var/www/site_kapi_kontrol/server/src/db.js"
```

**Bkz.:** [altyapi-acl-senkron-503](#altyapi-acl-senkron-503), [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-mosquitto-servis-calismiyor](#altyapi-mosquitto-servis-calismiyor)

<a id="altyapi-acl-silinen-cihaz-baglaniyor"></a>
### altyapi-acl-silinen-cihaz-baglaniyor · Silinen/değiştirilen cihaz hâlâ brokere bağlanabiliyor ya da broker passwd dosyasında eski kullanıcılar duruyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/sync_mqtt_acl.js:86](../../server/scripts/sync_mqtt_acl.js#L86) | <code>if (username.startsWith('device_') &amp;&amp; !wantedUsers.has(username)) {</code> | DB'de olmayan device_* kullanıcıları passwd'den silinir |
| [server/scripts/sync_mqtt_acl.js:89](../../server/scripts/sync_mqtt_acl.js#L89) | <code>if (legacyUsers.includes(username)) {</code> | Eski ortak kullanıcılar (varsayılan app_client, esp32_door_01; MQTT_LEGACY_USERS) silinir |
| [server/src/routes/admin_routes.js:1707](../../server/src/routes/admin_routes.js#L1707) | <code>await syncMqttAclOrThrow({ reason: 'device_deleted' });</code> | Cihaz silinince senkron tetiklenir; başarısızsa 503 (cihaz DB'den silinmiştir ama broker eski kalır) |
| [server/src/mqtt_acl_sync.js:107](../../server/src/mqtt_acl_sync.js#L107) | <code>const CHILD_ENV_PREFIXES = ['LC_', 'DB_', 'PG', 'MQTT_', 'MOSQUITTO_', 'KAPI_'];</code> | Senkron alt sürecine geçen ortam: MQTT_PASSWD_FILE/MQTT_ACL_FILE gibi MQTT_* değişkenleri dahil |

**Olası nedenler**
- Silme sonrası ACL senkronu çalışmadı ya da başarısız (MQTT_SYNC_COMMAND tanımsız / hata)
- Mosquitto reload edilmedi: passwd/acl dosyaları güncel ama broker eskisini kullanıyor
- Kullanıcı device_ ile başlamıyor ve legacy listesinde değil: senkron dokunmaz (api_bridge kasıtlı korunur)

**Adım adım kontrol**
- sudo -n /usr/local/bin/kapi-mqtt-sync çıkışı ve /health mqtt.acl_sync_configured değeri.
- Silinen cihazın artık sync_mqtt_acl --dry-run çıktısında OLMADIĞINI doğrulayın.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "cd /var/www/site_kapi_kontrol/server && node scripts/sync_mqtt_acl.js --dry-run | grep -c '^user device_'"
ssh -p 22667 salihceylan@178.210.161.55 "sudo -n /usr/local/bin/kapi-mqtt-sync; echo cikis=$?"   # DEĞİŞTİRİR: ACL/passwd yazar, mosquitto reload
```

**İlgili testler:** [server/test/fix_sx2_device_delete.test.js](../../server/test/fix_sx2_device_delete.test.js)

**Bkz.:** [altyapi-acl-senkron-503](#altyapi-acl-senkron-503), [altyapi-kapi-mqtt-sync-betik-hatalari](#altyapi-kapi-mqtt-sync-betik-hatalari)

<a id="altyapi-mosquitto-servis-calismiyor"></a>
### altyapi-mosquitto-servis-calismiyor · Mosquitto servisi başlamıyor ("Address already in use" / "Unable to open acl_file") ya da 8883 dışarıdan açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [MQTT_kurulum.txt:203](../../MQTT_kurulum.txt#L203) | <code>13) Siklikla gorulen hatalar</code> | Sık hatalar ve çözümleri (port dolu, acl_file açılamıyor, servis sürekli fail) |
| [MQTT_kurulum.txt:204](../../MQTT_kurulum.txt#L204) | <code>- "Address already in use": Elle "mosquitto -c ... -v" calistirilmis ve port dolu.</code> | Elle "mosquitto -c ... -v" çalıştırıldı ve port dolu: systemctl stop, pkill -9, start |
| [MQTT_kurulum.txt:210](../../MQTT_kurulum.txt#L210) | <code>- "Unable to open acl_file": acl dosyasi yok/izin hatali.</code> | acl dosyası yok/izin hatalı: chown mosquitto:mosquitto ve chmod 640 |
| [MQTT_kurulum.txt:216](../../MQTT_kurulum.txt#L216) | <code>sudo journalctl -xeu mosquitto.service --no-pager &#124; tail -n 80</code> | Servis sürekli düşüyorsa nedeni gösteren günlük komutu |
| [MQTT_kurulum.txt:163](../../MQTT_kurulum.txt#L163) | <code>10) Firewall</code> | 8883/TCP için ufw kuralı |
| [MQTT_kurulum.txt:145](../../MQTT_kurulum.txt#L145) | <code>tls_version tlsv1.2</code> | 10-secure.conf içindeki dinleyici: 8883, passwd + acl + sertifika dosya yolları |

**Olası nedenler**
- Port 8883 başka bir mosquitto sürecinde (elle başlatılmış) dolu
- passwd/acl/sertifika dosyası yok ya da sahiplik/izin yanlış (mosquitto kullanıcısı okuyamıyor)
- Yapılandırma dosyası hatalı (10-secure.conf, include_dir)
- ufw 8883'e izin vermiyor (dışarıdan bağlanılamaz, servis ayakta)

**Adım adım kontrol**
- sudo systemctl status mosquitto --no-pager ve journalctl çıktısındaki ilk hata satırı.
- Servis ayakta ise sudo ss -ltnp | grep 8883 ile dinlemeyi, sudo ufw status ile kuralı doğrulayın.
- Servisi yönetmek için systemd kullanın; çalışırken elle mosquitto -c ... -v çalıştırmayın.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "sudo systemctl status mosquitto --no-pager | head -n 15"
ssh -p 22667 salihceylan@178.210.161.55 "sudo journalctl -u mosquitto -n 40 --no-pager | cut -c1-200"
ssh -p 22667 salihceylan@178.210.161.55 "sudo ss -ltnp | grep 8883"
ssh -p 22667 salihceylan@178.210.161.55 "sudo ufw status | grep -E '8883|22667'"
```

**Bkz.:** [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-mqtt-tls-baglanti](#altyapi-mqtt-tls-baglanti), [altyapi-sertifika-suresi](#altyapi-sertifika-suresi)

<a id="altyapi-cihaz-cevrimdisi-gorunuyor"></a>
### altyapi-cihaz-cevrimdisi-gorunuyor · Cihaz çevrimdışı görünüyor (sunucu tarafı: devices.is_online=false / mqtt_connected=false) ama cihaz Wi-Fi'ye bağlı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:845](../../server/src/mqtt_bridge.js#L845) | <code>if (kind === 'availability') {</code> | Durum yalnız cihazın availability iletisinden ("online" dışı her şey offline) belirlenir; zaman aşımına dayalı otomatik offline yoktur |
| [server/src/mqtt_bridge.js:858](../../server/src/mqtt_bridge.js#L858) | <code>void recordDeviceOfflineTransition(status, 'Wi-Fi/MQTT Bağlantısı Kesildi (LWT)');</code> | online→offline geçişinde (LWT) bağlantı logu yazılır |
| [server/src/mqtt_bridge.js:737](../../server/src/mqtt_bridge.js#L737) | <code>) VALUES ($1, 'offline', $2, $3, $4, $5, $6, $7, $8, NOW())</code> | device_connectivity_logs'a yalnız "offline" satırı yazılır (köprü "online" satırı yazmaz) |
| [server/src/mqtt_bridge.js:329](../../server/src/mqtt_bridge.js#L329) | <code>async function persistRuntimeStatus(status) {</code> | device_runtime_status ve devices.is_online/last_online_at/last_offline_at buradan güncellenir |
| [server/src/mqtt_bridge.js:400](../../server/src/mqtt_bridge.js#L400) | <code>is_online = $2,</code> | devices.is_online güncellemesi: WHERE device_uid = $1 (UID birebir eşleşmezse satır güncellenmez) |
| [server/src/mqtt_bridge.js:1099](../../server/src/mqtt_bridge.js#L1099) | <code>export function getDeviceRuntimeStatus(deviceUid) {</code> | API yanıtları bellekteki bu durumdan beslenir (DB değil) |

**Olası nedenler**
- MQTT köprüsü bağlı değil (/health mqtt.connected:false) — hiçbir cihaz iletisi işlenmiyor
- Cihaz brokere bağlanamıyor: kimlik/ACL/TLS (altyapi-mqtt-acl-yayin-reddi)
- Cihaz kayıtlı değil ya da UID biçimi uyuşmuyor; devices.device_uid eski MAC biçimindeyse köprü cihazı tanır ama DB satırı yazılamaz (olası)
- OTA sırasında cihaz MQTT oturumunu bilerek kapatır: kısa "offline (LWT)" kaydı normaldir (OTA_KURULUM.txt)
- DB yazımı başarısız: /health mqtt.last_error:"db_error"

**Adım adım kontrol**
- Önce /health: mqtt.connected true mu? Değilse cihaz sorunu değil köprü sorunudur (altyapi-health-mqtt-baglanti-yok).
- DB satırı: devices.is_online/last_online_at ve device_runtime_status.last_seen_at/last_event (aşağıdaki sorgu).
- Son bağlantı kayıtlarına bakın: event_type yalnız "offline" olur; reason alanı LWT mi Wi-Fi mı söyler.

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT d.device_uid, d.is_online, d.last_online_at, d.last_offline_at, r.mqtt_connected, r.last_seen_at, r.last_event, r.firmware_version FROM devices d LEFT JOIN device_runtime_status r ON r.device_uid = d.device_uid WHERE d.device_uid = 'D4C771A172E0';"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT event_type, online_at, offline_at, duration_seconds, reason FROM device_connectivity_logs WHERE device_uid = 'D4C771A172E0' ORDER BY created_at DESC LIMIT 5;"
```

**İlgili testler:** [server/test/fix_sx1_bridge_logs.test.js](../../server/test/fix_sx1_bridge_logs.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js)

**Bkz.:** [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-mqtt-konu-ve-uid](#altyapi-mqtt-konu-ve-uid), [altyapi-durum-api-yeniden-baslayinca](#altyapi-durum-api-yeniden-baslayinca), [altyapi-health-mqtt-db-error-kodu](#altyapi-health-mqtt-db-error-kodu)

<a id="altyapi-durum-api-yeniden-baslayinca"></a>
### altyapi-durum-api-yeniden-baslayinca · API yeniden başlatılınca (dağıtım sonrası) cihaz durumları kısa süre eski ya da boş görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1000](../../server/src/mqtt_bridge.js#L1000) | <code>loadInitialDeviceRuntimeStatuses().catch(() =&gt; {});</code> | Köprü başlarken son bilinen durumlar DB'den belleğe yüklenir (hata yutulur) |
| [server/src/mqtt_bridge.js:947](../../server/src/mqtt_bridge.js#L947) | <code>export async function loadInitialDeviceRuntimeStatuses() {</code> | device_runtime_status satırlarını belleğe taşır; mqtt_connected DB'deki son değerdir |
| [server/src/mqtt_bridge.js:978](../../server/src/mqtt_bridge.js#L978) | <code>console.warn('Initial device runtime statuses yuklenemedi:', error.message);</code> | Yükleme başarısızsa durumlar boş başlar (cihaz iletileri gelince dolar) |
| [server/src/mqtt_bridge.js:291](../../server/src/mqtt_bridge.js#L291) | <code>function ensureStatus(deviceUid) {</code> | Bilinmeyen cihaz için varsayılan durum mqtt_connected:false'tur |

**Olası nedenler**
- Durum belleğe DB'den yüklenir; güncel durum cihazın sonraki availability/state iletisiyle (ya da brokerdaki retained availability ile) düzelir
- DB yükleme hatası: günlükte "Initial device runtime statuses yuklenemedi"
- Köprü henüz brokere bağlanmadı (restart sonrası birkaç sn)

**Adım adım kontrol**
- Birkaç dakika sonra düzelmiyorsa altyapi-cihaz-cevrimdisi-gorunuyor akışına geçin.
- Dağıtım sonrası doğrulama için remote_verify.sh "cihazlar" bölümünde uid | tip | online listesi vardır.

**Günlükte aranacak ifadeler**
- `Initial device runtime statuses yuklenemedi:`
- `MQTT bridge connected:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_verify.sh
```

**Bkz.:** [altyapi-cihaz-cevrimdisi-gorunuyor](#altyapi-cihaz-cevrimdisi-gorunuyor), [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok)

<a id="altyapi-komut-yayini-roleyi-calistirmiyor"></a>
### altyapi-komut-yayini-roleyi-calistirmiyor · Cihaz komut alıyor ama röle çalışmıyor — sunucu yayın yapıyor mu? (uygulama "komut gönderildi" diyor, kapı açılmıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:1122](../../server/src/mqtt_bridge.js#L1122) | <code>export async function publishDoorPulse({</code> | Kapı açma komutunu device/<UID>/cmd konusuna yayınlar (qos 1, retain yok) |
| [server/src/mqtt_bridge.js:1141](../../server/src/mqtt_bridge.js#L1141) | <code>error.code = 'DEVICE_OFFLINE';</code> | Bellekteki durum çevrimdışıysa (assumeOnline değilse) komut YAYINLANMAZ ve DEVICE_OFFLINE fırlatılır |
| [server/src/mqtt_bridge.js:1139](../../server/src/mqtt_bridge.js#L1139) | <code>if (status.mqtt_connected !== true &amp;&amp; !assumeOnline) {</code> | Kontrol köprü belleğine bakar: durum bayatsa komut gereksiz reddedilir ya da çevrimdışı cihaza yayınlanır |
| [server/src/mqtt_bridge.js:1146](../../server/src/mqtt_bridge.js#L1146) | <code>const pulse = buildPulsePayload({ requestedBy, doorId, siteCode });</code> | Yük: {action:"pulse", request_id, requested_by, requested_at(epoch sn), door_id, site_code} |
| [server/src/mqtt_bridge.js:102](../../server/src/mqtt_bridge.js#L102) | <code>export function buildPulsePayload({</code> | requested_at epoch SANİYE (sayı), request_id 16 karakter hex; firmware bu biçime göre doğrular |
| [server/src/mqtt_acl_sync.js:89](../../server/src/mqtt_acl_sync.js#L89) | <code>lines.push(`topic read device/${uid}/cmd`);</code> | Cihazın kendi cmd konusunu okuyabilmesi ACL'e bağlı; ACL'de yoksa komut cihaza hiç ulaşmaz |

**Olası nedenler**
- Köprü bağlı değil: istek 503 "MQTT baglantisi hazir degil" (code MQTT_BRIDGE_NOT_CONNECTED) döner
- Cihaz sunucuya göre çevrimdışı (DEVICE_OFFLINE): yayın hiç yapılmaz
- Yayın yapıldı ama cihaz ACL gereği cmd konusunu okuyamıyor (altyapi-mqtt-acl-yayin-reddi)
- qos 1 yayın tamamlandı = BROKER aldı; cihazın işlediğini göstermez. Cihaz abone değilse mosquitto RC:16 "No matching subscribers" der (yetki hatası değildir)
- Cihaz komutu aldı ama firmware reddetti (request_id/zaman/yük biçimi) — firmware tarafı bu klavuzun kapsamı dışında

**Adım adım kontrol**
- Sıra: /health mqtt.connected → cihazın sunucudaki durumu (devices.is_online, device_runtime_status.last_seen_at) → ACL (cmd okuma satırı) → firmware günlüğü.
- İstek günlüğünde [API] POST ... -> 200/503 koduna bakın (kapı uçlarının ayrıntısı kapı alanındadır).

**Günlükte aranacak ifadeler**
- `[API]`

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT d.device_uid, d.is_online, r.mqtt_connected, r.last_seen_at FROM devices d LEFT JOIN device_runtime_status r ON r.device_uid = d.device_uid WHERE d.device_uid = 'D4C771A172E0';"
ssh -p 22667 salihceylan@178.210.161.55 "grep -A4 'user device_D4C771A172E0' /etc/mosquitto/acl"
```

**İlgili testler:** [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js), [server/test/doors_routes.test.js](../../server/test/doors_routes.test.js)

**Bkz.:** [altyapi-cihaz-cevrimdisi-gorunuyor](#altyapi-cihaz-cevrimdisi-gorunuyor), [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok)

<a id="altyapi-qr-sonuc-cihaza-donmuyor"></a>
### altyapi-qr-sonuc-cihaza-donmuyor · Cihaz karekodu okutuyor ama "qr_result" yanıtı gelmiyor (kapı açılmıyor, cihaz zaman aşımına düşüyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:803](../../server/src/mqtt_bridge.js#L803) | <code>if (kind === 'qr_verify') {</code> | device/<uid>/qr_verify iletisini çözer; token 128 karakteri aşarsa boşaltılır; request_id cihaza aynen geri yankılanır |
| [server/src/mqtt_bridge.js:769](../../server/src/mqtt_bridge.js#L769) | <code>if (retained &amp;&amp; (kind === 'screen_qr' &#124;&#124; kind === 'qr_verify')) {</code> | Retained qr_verify/screen_qr iletileri YOK SAYILIR (eski doğrulama tekrar işlenmesin); cihaz retain:false yayınlamalı |
| [server/src/mqtt_bridge.js:838](../../server/src/mqtt_bridge.js#L838) | <code>const resTopic = `device/${normalizeDeviceTopicUid(match[1])}/qr_result`;</code> | Sonuç device/<uid>/qr_result konusuna yayınlanır; köprü bağlı değilse yayın SESSİZCE atlanır |
| [server/src/mqtt_bridge.js:835](../../server/src/mqtt_bridge.js#L835) | <code>console.error('[MQTT QR Verify] Islem hatasi:', err.message);</code> | Doğrulama servisi hata verirse cihaza reason:"ERROR" sonucu gider; ayrıntı yalnız bu satırdadır |
| [server/src/mqtt_acl_sync.js:90](../../server/src/mqtt_acl_sync.js#L90) | <code>lines.push(`topic read device/${uid}/qr_result`);</code> | Cihazın qr_result okuyabilmesi için ACL satırı gerekir (api_bridge tarafında topic write device/+/qr_result) |

**Olası nedenler**
- Köprü brokere bağlı değil: sonuç yayınlanmaz (günlük de yazılmaz)
- Cihazın ACL'inde qr_result okuma satırı yok (eski ACL): sync gerekir
- Cihaz qr_verify'yi retained yayınladı: köprü yok sayar
- qr_access_service hata verdi: günlükte "[MQTT QR Verify] Islem hatasi:"

**Adım adım kontrol**
- /health mqtt.connected, sonra ACL (grep qr_result), sonra pm2 logs "[MQTT QR Verify]".
- Doğrulama kuralları (token geçerliliği, geofence vb.) bu bölümün değil kapı/QR alanının konusudur.

**Günlükte aranacak ifadeler**
- `[MQTT QR Verify] Islem hatasi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "grep -c qr_result /etc/mosquitto/acl"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a 'MQTT QR Verify' | tail -n 5 | cut -c1-200"
```

**İlgili testler:** [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js), [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js)

**Bkz.:** [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-ekran-qr-token-sunucuda](#altyapi-ekran-qr-token-sunucuda)

<a id="altyapi-ekran-qr-token-sunucuda"></a>
### altyapi-ekran-qr-token-sunucuda · Ekranlı (WROOM) cihazın ekran QR kodu sunucuda görünmüyor ya da API yeniden başlayınca boşalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:777](../../server/src/mqtt_bridge.js#L777) | <code>if (kind === 'screen_qr') {</code> | Ekran token'ı çözer (JSON {token, valid_seconds} ya da düz metin), geçerlilik süresini sınırlar ve belleğe yazar; token LOGLANMAZ |
| [server/src/mqtt_bridge.js:15](../../server/src/mqtt_bridge.js#L15) | <code>export const deviceScreenQrStore = new Map();</code> | Ekran QR'ları yalnız BELLEKTE tutulur: API yeniden başlayınca boşalır, cihazın sonraki yayınıyla dolar |
| [server/src/mqtt_bridge.js:769](../../server/src/mqtt_bridge.js#L769) | <code>if (retained &amp;&amp; (kind === 'screen_qr' &#124;&#124; kind === 'qr_verify')) {</code> | Retained screen_qr yok sayılır: eski token "taze" görünmesin diye |
| [server/src/mqtt_acl_sync.js:95](../../server/src/mqtt_acl_sync.js#L95) | <code>lines.push(`topic write device/${uid}/screen_qr`);</code> | Cihazın screen_qr konusuna yazabilmesi için ACL satırı gerekir |

**Olası nedenler**
- API yeniden başlatıldı: bellek boş, cihazın bir sonraki screen_qr yayınına (30 sn rotasyon) kadar bekler
- Cihaz screen_qr'ı retained yayınlıyor: köprü yok sayar
- ACL'de screen_qr yazma satırı yok ya da köprü bağlı değil
- Cihaz kayıtsız: bilinmeyen UID'lerin iletileri işlenmez

**Adım adım kontrol**
- /health mqtt.connected ve cihazın kayıtlı olduğunu doğrulayın; ACL'de screen_qr satırını arayın.
- Ekran QR yayını cihaz firmware tarafıdır (30 sn rotasyon); sunucu yalnız alır.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "grep -c screen_qr /etc/mosquitto/acl"
```

**İlgili testler:** [server/test/doors_screen_qr.test.js](../../server/test/doors_screen_qr.test.js)

**Bkz.:** [altyapi-qr-sonuc-cihaza-donmuyor](#altyapi-qr-sonuc-cihaza-donmuyor), [altyapi-mqtt-konu-ve-uid](#altyapi-mqtt-konu-ve-uid)

<a id="altyapi-offline-log-alimi"></a>
### altyapi-offline-log-alimi · Cihazın çevrimdışıyken biriktirdiği kapı kayıtları sunucuya gelmiyor ya da cihaz aynı kayıt paketini tekrar tekrar yolluyor (logs_ack yok)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/mqtt_bridge.js:640](../../server/src/mqtt_bridge.js#L640) | <code>export async function handleDeviceLogsMessage(topicUid, text, deps = {}) {</code> | device/<uid>/logs paketini çözer, door_log_service'e yazar ve BAŞARILIYSA logs_ack yayınlar |
| [server/src/mqtt_bridge.js:187](../../server/src/mqtt_bridge.js#L187) | <code>export function normalizeDeviceLogBatch(decoded, { nowMs = Date.now() } = {}) {</code> | Biçim: {"batch_id":N,"logs":[{client_log_id,epoch,boot_ms,trigger_type,user_name,apartment_label,action}]}; bozuk kalemler atlanır |
| [server/src/mqtt_bridge.js:41](../../server/src/mqtt_bridge.js#L41) | <code>export const MAX_DEVICE_LOG_BATCH_ITEMS = 200;</code> | Tek pakette en fazla 200 kayıt; fazlası yok sayılır |
| [server/src/mqtt_bridge.js:676](../../server/src/mqtt_bridge.js#L676) | <code>transientReject = result?.reason === 'DEVICE_NOT_ASSIGNED';</code> | Cihaz henüz siteye/kapıya atanmamışsa ack GÖNDERİLMEZ (cihaz sakladığı kayıtları atanınca yeniden yollar) |
| [server/src/mqtt_bridge.js:623](../../server/src/mqtt_bridge.js#L623) | <code>function publishLogsAck(normalizedUid, batchId) {</code> | logs_ack, köprü bağlıysa device/<uid>/cmd konusuna yayınlanır |
| [server/src/services/door_log_service.js:419](../../server/src/services/door_log_service.js#L419) | <code>result.reason = 'DEVICE_NOT_ASSIGNED';</code> | Atanmamış cihaz nedeniyle yazılmayan kayıtlar rejected sayılır |
| [server/src/db.js:915](../../server/src/db.js#L915) | <code>CREATE UNIQUE INDEX IF NOT EXISTS idx_door_access_logs_client_log</code> | Tekrar gelen aynı (device_uid, client_log_id) kayıtları eklenmez: tekrar yayın güvenlidir (idempotent) |
| [server/src/mqtt_acl_sync.js:96](../../server/src/mqtt_acl_sync.js#L96) | <code>lines.push(`topic write device/${uid}/logs`);</code> | Cihazın logs konusuna yazabilmesi için ACL'de bu satır gerekir |

**Olası nedenler**
- Cihaz henüz bir siteye/kapıya atanmamış (DEVICE_NOT_ASSIGNED): ack gönderilmez, kayıtlar cihazda kalır
- ACL'de logs yazma satırı yok (eski ACL): paket brokerda reddedilir (altyapi-mqtt-acl-yayin-reddi)
- JSON bozuk ya da 16 KB üstü: sessizce/loglanarak atılır
- DB hatası: günlükte "islenemedi" (ack YOK; cihaz yeniden dener)
- Köprü bağlı değil: ack yayınlanamaz

**Adım adım kontrol**
- Günlükte "[MQTT Logs] Cihaz <UID> batch=<N>: eklenen=... tekrar=... reddedilen=..." özet satırını arayın.
- "henuz bir siteye atanmamis" görülüyorsa cihazı kapıya atamak yeterlidir; kayıtlar sonraki yayında teslim olur.

**Günlükte aranacak ifadeler**
- `[MQTT Logs] JSON parse hatasi`
- `henuz bir siteye atanmamis`
- `islenemedi:`
- `[MQTT Logs] logs_ack yayinlanamadi`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'MQTT Logs' | tail -n 10 | cut -c1-220"
```

**İlgili testler:** [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js), [server/test/devices_door_log_service.test.js](../../server/test/devices_door_log_service.test.js)

**Bkz.:** [altyapi-mqtt-acl-yayin-reddi](#altyapi-mqtt-acl-yayin-reddi), [altyapi-mqtt-konu-ve-uid](#altyapi-mqtt-konu-ve-uid)

<a id="altyapi-sertifika-suresi"></a>
### altyapi-sertifika-suresi · HTTPS sertifikası (api.gudeteknoloji.com.tr) ya da MQTT TLS sertifikası (mqtt.gudeteknoloji.com.tr) süresi doldu/dolmak üzere; uygulama ya da cihazlar bağlanamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [sunucu_kurulum.txt:108](../../sunucu_kurulum.txt#L108) | <code>sudo certbot --nginx -d api.gudeteknoloji.com.tr --redirect -m &lt;mail&gt; --agree-tos -n</code> | API sertifikası certbot nginx eklentisiyle alınır ve yenilenir (nginx sertifikayı kendisi yeniden yükler) |
| [MQTT_kurulum.txt:40](../../MQTT_kurulum.txt#L40) | <code>sudo certbot certonly --nginx -d mqtt.gudeteknoloji.com.tr -m MAIL_ADRESIN --agree-tos -n</code> | MQTT sertifikası AYRI alınır (certonly): yalnız dosya üretir, mosquitto'yu kendiliğinden yeniden yüklemez |
| [MQTT_kurulum.txt:44](../../MQTT_kurulum.txt#L44) | <code>sudo ln -sf /etc/letsencrypt/live/mqtt.gudeteknoloji.com.tr/fullchain.pem /etc/mosquitto/…</code> | Mosquitto /etc/mosquitto/certs altındaki bağlantı üzerinden okur; yenilenince hedef dosya değişir, süreç eski sertifikayı bellekte tutabilir |
| [MQTT_kurulum.txt:143](../../MQTT_kurulum.txt#L143) | <code>certfile /etc/mosquitto/certs/fullchain.pem</code> | Broker 8883 dinleyicisinin sertifika yolu (mosquitto.conf) |
| [server/src/mqtt_bridge.js:75](../../server/src/mqtt_bridge.js#L75) | <code>rejectUnauthorized: !envFlag('MQTT_ALLOW_INSECURE_TLS', false),</code> | API köprüsü sertifikayı DOĞRULAR: süresi dolan MQTT sertifikasıyla köprü bağlanamaz |
| [server/scripts/trigger_ota.js:51](../../server/scripts/trigger_ota.js#L51) | <code>rejectUnauthorized: !allowInsecureTls,</code> | trigger_ota.js de doğrulamayı varsayılan açık tutar; sertifika sorunu bu betikte de görülür |

**Olası nedenler**
- certbot yenilemesi çalışmadı ya da başarısız oldu (zamanlayıcı/DNS/80 portu)
- MQTT sertifikası yenilendi ama mosquitto yeniden yüklenmedi: depoda yenileme sonrası mosquitto'yu yeniden yükleyen kanca (deploy-hook) tanımlı DEĞİL; sunucudaki certbot yapılandırmasına bakın
- API sertifikası süresi doldu: tarayıcı/uygulama HTTPS hatası verir (nginx 502 değil, TLS hatası)

**Adım adım kontrol**
- Bitiş tarihini dışarıdan okuyun (komutlar aşağıda): notAfter geçmişse ya da birkaç gün kaldıysa certbot durumuna bakın.
- API için nginx sertifikayı kendisi yeniler; MQTT için yenilemeden sonra mosquitto'yu yeniden yüklemek GEREKEBİLİR (sudo systemctl reload mosquitto; açık cihaz bağlantıları kısa süre düşebilir, ESP32 kendiliğinden yeniden bağlanır).
- MQTT_ALLOW_INSECURE_TLS=1 ile geçici çözüm üretimde KULLANILMAZ (altyapi-mqtt-tls-baglanti).

**Komutlar**
```bash
echo | openssl s_client -connect api.gudeteknoloji.com.tr:443 -servername api.gudeteknoloji.com.tr 2>/dev/null | openssl x509 -noout -dates
echo | openssl s_client -connect mqtt.gudeteknoloji.com.tr:8883 -servername mqtt.gudeteknoloji.com.tr 2>/dev/null | openssl x509 -noout -dates
ssh -p 22667 salihceylan@178.210.161.55 "sudo certbot certificates"
```

**Bkz.:** [altyapi-mqtt-tls-baglanti](#altyapi-mqtt-tls-baglanti), [altyapi-nginx-502-504](#altyapi-nginx-502-504), [altyapi-mosquitto-servis-calismiyor](#altyapi-mosquitto-servis-calismiyor)

<a id="altyapi-komut-rehberi"></a>
### altyapi-komut-rehberi · Canlı sunucuda sorunu nereden okuyacağımı bilmiyorum (günlük, /health, veritabanı, PM2 durumu için güvenli komutlar)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_audit.sh:2](../../deploy/remote_audit.sh#L2) | <code># SALT-OKUNUR canli sunucu denetimi (degerler maskelenir; hicbir sey degistirmez).</code> | Tek komutla: .env anahtar adları (değersiz), uzunluklar, PM2, docker, migrations, firmware dizini, disk, /health, son günlük satırları |
| [deploy/remote_audit.sh:6](../../deploy/remote_audit.sh#L6) | <code>echo "== .env anahtarlari (DEGER YOK)"; grep -v '^\s*#' .env 2&gt;/dev/null &#124; grep -v '^\s*$…</code> | .env değerlerini maskeler: çıktı paylaşılabilir (parola/anahtar basmaz) |
| [deploy/remote_verify.sh:2](../../deploy/remote_verify.sh#L2) | <code># Dagitim sonrasi dogrulama (sunucunun KENDI loopback'i uzerinden, az sayida istek; sir y…</code> | Dağıtım sonrası: cihaz listesi, yeni kolonlar, /health, şirket ucu 401, OTA manifest, pm2, mosquitto |
| [server/src/routes/firmware_routes.js:95](../../server/src/routes/firmware_routes.js#L95) | <code>firmwareRouter.get('/health', async (_req, res) =&gt; {</code> | /health: ok, database ve mqtt alanları (acl_sync_configured dahil); yetkisiz ve sır içermez |
| [deploy/README.md:7](../../deploy/README.md#L7) | <code>## Adımlar</code> | Canlı yollar ve dağıtım adımları; VPS, PM2 adı ve DB konteyneri burada yazılıdır |
| [server/ecosystem.config.cjs:45](../../server/ecosystem.config.cjs#L45) | <code>merge_logs: true,</code> | Tek günlük akışı (stdout+stderr birleşik, zaman damgalı); pm2 logs bunu okur |

**Olası nedenler**
- Bu bir arıza değil, operasyon rehberidir: belirtiye göre ilgili giriş "related" bağlantılarındadır

**Adım adım kontrol**
- Sıra: 1) /health (dışarıdan), 2) pm2 status + günlüğün İLK hata satırı, 3) docker ps (DB), 4) salt-okunur SELECT.
- YAZMAYIN/ÇALIŞTIRMAYIN: cat .env, pm2 env, pm2 jlist (parola/anahtar basar), .env'i source etmek.
- Veritabanında yalnız SELECT çalıştırın; UPDATE/DELETE/DROP için kullanıcı onayı ve yedek (altyapi-geri-alma-ve-yedek) gerekir.

**Komutlar**
```bash
curl -s https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_audit.sh
ssh -p 22667 salihceylan@178.210.161.55 "pm2 status | grep kapi-api"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | cut -c1-220"
ssh -p 22667 salihceylan@178.210.161.55 "docker ps --format '{{.Names}} | {{.Status}}'"
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT count(*) AS cihaz, count(*) FILTER (WHERE is_online) AS cevrimici FROM devices;"
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_verify.sh
```

**Bkz.:** [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu), [altyapi-health-database-disconnected](#altyapi-health-database-disconnected), [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-nginx-502-504](#altyapi-nginx-502-504), [altyapi-geri-alma-ve-yedek](#altyapi-geri-alma-ve-yedek)

<a id="altyapi-geri-alma-ve-yedek"></a>
### altyapi-geri-alma-ve-yedek · Dağıtımdan sonra API bozuldu; eski sürüme/veriye dönmem gerekiyor (yedek nerede, nasıl geri alınır)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_deploy.sh:9](../../deploy/remote_deploy.sh#L9) | <code>BK="$HOME/backups/kapi_$TS"</code> | Yedek konumu: ~/backups/kapi_<TS>/ (TS = dağıtım zaman damgası) |
| [deploy/remote_deploy.sh:18](../../deploy/remote_deploy.sh#L18) | <code>rollback() {</code> | Geri alma: yedek kodu (data hariç) açar, node_modules.old_<TS>'i geri koyar, PM2 yeniden başlatır, /health bakar |
| [deploy/remote_deploy.sh:21](../../deploy/remote_deploy.sh#L21) | <code>tar -xzf "$BK/server_code.tgz" --exclude='server/data' -C "$BASE"</code> | Kodu geri yükler; yedek .env'i de içerdiğinden .env yedek anındaki haline döner, server/data ise dokunulmaz |
| [deploy/remote_deploy.sh:38](../../deploy/remote_deploy.sh#L38) | <code>docker exec "$DBC" pg_dump -U postgres -d site_kapi_kontrol &#124; gzip &gt; "$BK/db.sql.gz"</code> | Veritabanı yedeği db.sql.gz; otomatik geri almada GERİ YÜKLENMEZ (şema değişiklikleri ekleyicidir), gerekirse elle |
| [deploy/README.md:31](../../deploy/README.md#L31) | <code>## Geri alma</code> | Elle geri alma komutu: remote_deploy.sh <TS> rollback |
| [deploy/README.md:33](../../deploy/README.md#L33) | <code>`ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS rollback"` — yedekteki kod…</code> | Veritabanının geri alınmaması bilinçli karardır; db.sql.gz ile elle ve onayla geri yüklenir |

**Olası nedenler**
- Yeni sürümde çalışma zamanı hatası (sağlık geçse bile bir uç bozuk)
- Otomatik geri alma çalıştı ama /health hâlâ hatalı (betik "UYARI: geri almadan sonra /health HATALI" yazar): sorun kodda değil veri/.env/DB'de olabilir

**Adım adım kontrol**
- Yedekleri listeleyin (komut aşağıda); en yeni kapi_<TS> dizininde server_code.tgz ve db.sql.gz olmalı.
- Kod geri alma: bash kapi_remote_deploy_<TS>.sh <TS> rollback (README "Geri alma"). Bu PM2'yi yeniden başlatır: canlıyı etkiler, kullanıcı onayı alın.
- Veritabanı geri yükleme çok risklidir (yeni veriyi siler): önce mevcut durumdan ayrı bir pg_dump alın; yalnız kullanıcı onayıyla ve bakım penceresinde.
- node_modules.old_<TS> yalnız aktivasyondan sonra vardır; yoksa geri alma eski bağımlılıkları getiremez (npm ci ile yeniden kurulur).

**Günlükte aranacak ifadeler**
- `GERI ALMA basliyor`
- `GERI ALMA TAMAM: /health ok`
- `UYARI: geri almadan sonra /health HATALI`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "ls -la ~/backups | tail -n 8"
ssh -p 22667 salihceylan@178.210.161.55 "ls -l ~/backups/kapi_<TS>"   # <TS> yerine dizin adını yazın
ssh -p 22667 salihceylan@178.210.161.55 "df -h /var/www | tail -n 1"
```

**Bkz.:** [altyapi-deploy-activate-geri-alma](#altyapi-deploy-activate-geri-alma), [altyapi-deploy-prepare-basarisiz](#altyapi-deploy-prepare-basarisiz), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor)

<a id="altyapi-deploy-prepare-basarisiz"></a>
### altyapi-deploy-prepare-basarisiz · Dağıtım "prepare" aşaması PREPARE_OK yazmadan duruyor ("HATA: DB yedegi bos/kucuk", node --check ya da npm ci hatası)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_deploy.sh:31](../../deploy/remote_deploy.sh#L31) | <code>prepare() {</code> | Hazırlık canlıya DOKUNMAZ: yedek alır, paketi aşama dizinine açar, sözdizimi ve bağımlılık denetler |
| [deploy/remote_deploy.sh:41](../../deploy/remote_deploy.sh#L41) | <code>echo "HATA: DB yedegi bos/kucuk"</code> | db.sql.gz boş ya da 2000 bayttan küçükse exit 3: DB konteyneri/pg_dump sorunu; dağıtım ilerlemez (doğru davranış) |
| [deploy/remote_deploy.sh:50](../../deploy/remote_deploy.sh#L50) | <code>find src scripts -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print0 &#124; x…</code> | src ve scripts altındaki her .js/.mjs/.cjs dosyasında sözdizimi hatası burada yakalanır; canlı kod etkilenmez |
| [deploy/remote_deploy.sh:52](../../deploy/remote_deploy.sh#L52) | <code>npm ci --omit=dev --no-audit --no-fund 2&gt;&amp;1 &#124; tail -3</code> | Bağlantılar aşama dizininde kurulur; paket-kilit uyuşmazlığı ya da ağ hatası burada çıkar |
| [deploy/remote_deploy.sh:55](../../deploy/remote_deploy.sh#L55) | <code>echo PREPARE_OK</code> | Başarı işareti: bu satır yoksa ACTIVATE çalıştırılmamalı |
| [deploy/remote_deploy.sh:4](../../deploy/remote_deploy.sh#L4) | <code>set -euo pipefail</code> | Herhangi bir komut hata verirse betik anında durur (sessiz geçmez) |

**Olası nedenler**
- Paket (kapi_deploy_<TS>.tgz) yüklenmedi ya da bozuk (sha256 uyuşmuyor)
- PostgreSQL konteyneri kapalı: pg_dump boş çıktı verir (altyapi-docker-postgres-calismiyor)
- Pakette sözdizimi hatası olan dosya var
- Disk dolu: yedek yazılamadı
- npm ci: package-lock.json ile package.json uyumsuz ya da ağ erişimi yok

**Adım adım kontrol**
- Çıktıdaki son [n/5] adımı hatanın yerini söyler; canlı kod ve PM2 bu aşamada hiç değişmediğinden güvenle tekrar denenebilir.
- Paketi yerelde yeniden oluşturun, sha256'yı sunucudakiyle karşılaştırın (deploy/README adım 2-3).
- Disk: df -h /var/www; yedek dizini: ~/backups.

**Günlükte aranacak ifadeler**
- `HATA: DB yedegi bos/kucuk`
- `PREPARE_OK`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "df -h /var/www | tail -n 1; ls -la ~/backups | tail -n 5"
ssh -p 22667 salihceylan@178.210.161.55 "docker ps --format '{{.Names}} | {{.Status}}'"
```

**Bkz.:** [altyapi-geri-alma-ve-yedek](#altyapi-geri-alma-ve-yedek), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor), [altyapi-deploy-activate-geri-alma](#altyapi-deploy-activate-geri-alma)

<a id="altyapi-deploy-activate-geri-alma"></a>
### altyapi-deploy-activate-geri-alma · Dağıtım "activate" sırasında "SAGLIK KONTROLU BASARISIZ" yazdı ve otomatik geri alma başladı ya da ACTIVATE_OK hiç görünmedi

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_deploy.sh:58](../../deploy/remote_deploy.sh#L58) | <code>activate() {</code> | Etkinleştirme: COMPANY_API_KEY denetimi, kod+bağımlılık yerleştirme, PM2 restart, 12 sn bekleyip /health kontrolü |
| [deploy/remote_deploy.sh:59](../../deploy/remote_deploy.sh#L59) | <code>[ -d "$STAGE/node_modules" ] &#124;&#124; { echo "HATA: hazirlik (prepare) yapilmamis"; exit 2; }</code> | Aşama dizininde node_modules yoksa (prepare çalışmamış ya da başka TS) exit 2; hiçbir şey değişmez |
| [deploy/remote_deploy.sh:62](../../deploy/remote_deploy.sh#L62) | <code>if ! grep -q '^COMPANY_API_KEY=.\{24,\}' .env; then</code> | Anahtar yoksa ya da 24 karakterden kısaysa YENİSİ üretilip .env'e eklenir; şirket aracının .env'ine de aynı değer girilmeli |
| [deploy/remote_deploy.sh:14](../../deploy/remote_deploy.sh#L14) | <code>health_ok() {</code> | Sağlık ölçütü: 127.0.0.1:8080/health yanıtında "ok":true geçmesi (nginx/DNS bu ölçüte girmez) |
| [deploy/remote_deploy.sh:93](../../deploy/remote_deploy.sh#L93) | <code>echo "SAGLIK KONTROLU BASARISIZ"</code> | Hata durumunda son 40 günlük satırı basılır, rollback() çağrılır ve exit 4 ile çıkılır |
| [deploy/remote_deploy.sh:89](../../deploy/remote_deploy.sh#L89) | <code>echo "ACTIVATE_OK"</code> | Başarı işareti; ardından /health çıktısının ilk 400 karakteri yazılır |

**Olası nedenler**
- Yeni kod açılışta düşüyor (ENV/şema/MQTT hatası): basılan günlük satırlarındaki İLK hata (altyapi-api-acilmiyor-pm2-dongu)
- API 12 sn içinde ayağa kalkmadı (yavaş şema güncellemesi): /health bir süre sonra ok olabilir ama betik zaten geri almış olur
- DB bağlantı sorunu nedeniyle /health 500 (altyapi-health-database-disconnected)

**Adım adım kontrol**
- Geri alma TAMAM yazdıysa canlı eski sürümdedir: günlükteki hatayı düzeltip prepare'den yeniden başlayın.
- "UYARI: geri almadan sonra /health HATALI" görürseniz sorun kod dışındadır: DB/.env/MQTT; altyapi-geri-alma-ve-yedek.
- Aktivasyon sonrası MQTT ACL değiştiyse ayrıca kapi-mqtt-sync gerekir (README adım 7).

**Günlükte aranacak ifadeler**
- `SAGLIK KONTROLU BASARISIZ`
- `ACTIVATE_OK`
- `COMPANY_API_KEY tanimlandi`
- `HATA: hazirlik (prepare) yapilmamis`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 60 --nostream | cut -c1-220"
ssh -p 22667 salihceylan@178.210.161.55 "curl -s -m 8 http://127.0.0.1:8080/health | head -c 300"
```

**Bkz.:** [altyapi-geri-alma-ve-yedek](#altyapi-geri-alma-ve-yedek), [altyapi-deploy-prepare-basarisiz](#altyapi-deploy-prepare-basarisiz), [altyapi-deploy-dogrulama-sonuclari](#altyapi-deploy-dogrulama-sonuclari), [altyapi-api-acilmiyor-pm2-dongu](#altyapi-api-acilmiyor-pm2-dongu)

<a id="altyapi-deploy-dogrulama-sonuclari"></a>
### altyapi-deploy-dogrulama-sonuclari · Dağıtım sonrası remote_verify.sh / remote_audit.sh çıktısında beklenmeyen satır var (boş cihaz listesi, yeni kolon yok, şirket ucu 401 değil, OTA manifest boş)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_verify.sh:21](../../deploy/remote_verify.sh#L21) | <code>echo "== yeni kolonlar/indeks"</code> | users.updated_at, door_access_logs.client_log_id ve client_log indeksinin varlığını information_schema ile sorar; boşsa şema tamamlanmamıştır |
| [deploy/remote_verify.sh:27](../../deploy/remote_verify.sh#L27) | <code>echo "== sirket ucu anahtarsiz (401 beklenir)"; curl -s -m 8 -o /dev/null -w "%{http_code…</code> | Anahtarsız /api/company/labeled-devices 401 vermeli; 200 ise yetkilendirme açığı, 5xx ise sunucu hatası |
| [deploy/remote_verify.sh:30](../../deploy/remote_verify.sh#L30) | <code>echo "== OTA manifest (200 + sha256/hedef alanlari)"; curl -s -m 8 "http://127.0.0.1:8080…</code> | Gerçek cihaz UID'siyle manifest isteği: enabled/sha256/target alanları görünmeli (altyapi-ota-manifest-guncelleme-sunmuyor) |
| [deploy/remote_verify.sh:113](../../deploy/remote_verify.sh#L113) | <code>echo "== mosquitto + acl"; systemctl is-active mosquitto; grep -c "logs" /etc/mosquitto/a…</code> | mosquitto aktif mi ve ACL'de "logs" satırı sayısı (offline log yazma izni); 0 ise ACL eski (altyapi-mqtt-acl-yayin-reddi) |
| [deploy/remote_audit.sh:17](../../deploy/remote_audit.sh#L17) | <code>echo "== uzak-yalniz artik dosyalar"; ls -1 src/services/membership_routes.js apply_014.j…</code> | Depoda olmayıp sunucuda kalan eski dosyalar listelenir; silinmez (deploy/README Notlar) |
| [deploy/remote_audit.sh:18](../../deploy/remote_audit.sh#L18) | <code>echo "== firmware dizini"; ls -A firmware 2&gt;&amp;1 &#124; tr '\n' ' '; echo; for d in firmware/*; …</code> | firmware/<hedef> klasörleri ve içindeki dosyalar: manifest.json ve .bin var mı |

**Olası nedenler**
- Şema güncellemesi uygulanmadı/başarısız (ensureDbSchema hatası) (altyapi-sema-baslangic-sql-hatasi)
- Cihaz tablosu boş ya da farklı bir veritabanına bakılıyor
- Firmware klasörü/manifest sunucuda yok: OTA yayını yoktur (hata değil)
- ACL eski: kapi-mqtt-sync çalıştırılmadı

**Adım adım kontrol**
- Betikler yalnız okur; çıktıyı bir önceki dağıtımla karşılaştırın.
- Çıktıda sır yoktur (.env değerleri maskeli); yine de paylaşırken UID/IP gibi verileri gözden geçirin.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_verify.sh
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_audit.sh
```

**Bkz.:** [altyapi-deploy-activate-geri-alma](#altyapi-deploy-activate-geri-alma), [altyapi-komut-rehberi](#altyapi-komut-rehberi), [altyapi-ota-manifest-guncelleme-sunmuyor](#altyapi-ota-manifest-guncelleme-sunmuyor)

<a id="altyapi-ota-manifest-guncelleme-sunmuyor"></a>
### altyapi-ota-manifest-guncelleme-sunmuyor · Cihaz OTA kontrol ediyor ama güncelleme almıyor: manifest update_available:false döner ("Bu hedef icin OTA yayini yok", "Cihaz bu yayin grubunda degil", "USB ile tam yukleme")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:111](../../server/src/routes/firmware_routes.js#L111) | <code>firmwareRouter.get('/firmware/:target/manifest.json', async (req, res) =&gt; {</code> | Manifest ucu: klasör hedefini doğrular, cihazı DB'de arar, manifest.json'u okuyup update_available hesaplar |
| [server/src/routes/firmware_routes.js:165](../../server/src/routes/firmware_routes.js#L165) | <code>message: 'Bu hedef icin OTA yayini yok.',</code> | firmware/<hedef>/manifest.json dosyası YOKSA 200 ve enabled:false döner (hata değil) |
| [server/src/routes/firmware_routes.js:186](../../server/src/routes/firmware_routes.js#L186) | <code>const updateAvailable =</code> | Güncelleme sunma koşulu: enabled, hedef uyumu, allowed_uids, usb_required değil ve sürüm cihazınkinden BÜYÜK |
| [server/src/routes/firmware_routes.js:176](../../server/src/routes/firmware_routes.js#L176) | <code>const blockedByUid = allowedUids.length &gt; 0 &amp;&amp; !allowedUids.includes(uid);</code> | allowed_uids doluysa listede olmayan cihaz yayını görmez; uid sorgu parametresi verilmezse de engellenir |
| [server/src/routes/firmware_routes.js:201](../../server/src/routes/firmware_routes.js#L201) | <code>message = 'Bu surum icin USB ile tam yukleme gerekiyor.';</code> | usb_required:true ise uzaktan güncelleme sunulmaz |
| [server/src/utils/helpers.js:36](../../server/src/utils/helpers.js#L36) | <code>export function compareVersionParts(left, right) {</code> | Sürüm karşılaştırması parça parça sayısaldır; manifest sürümü eşit ya da küçükse güncelleme sunulmaz |
| [OTA_KURULUM.txt:61](../../OTA_KURULUM.txt#L61) | <code>- allowed_uids bos ise o hedefin tum cihazlari bu yayini gorebilir.</code> | Manifest alanlarının anlamı ve yayın adımları |

**Olası nedenler**
- manifest.json yok ya da "enabled": false
- Manifest sürümü cihaz sürümünden büyük değil (geri dönüş için daha YÜKSEK numara verilmeli)
- allowed_uids dolu ve cihaz listede değil (test grubu yayını)
- usb_required:true (bölüm tablosu/bootloader değişikliği)
- manifest hedefi klasörle uyuşmuyor (altyapi-ota-hedef-uyusmazligi)
- Cihaz sorguda current_version/uid göndermiyor: allowed_uids doluysa engellenir

**Adım adım kontrol**
- Manifest yanıtını gerçek UID ve cihazın sürümüyle alın (komut aşağıda); message alanı nedeni söyler.
- Sunucuda firmware/<hedef>/ içinde manifest.json ve .bin dosyası var mı (deploy/remote_audit.sh "firmware dizini").
- ESP32-C3 sahada çalışıyor: manifest alanlarını/yanıt şeklini değiştirmeyin; firmware bu şekle göre yazılmıştır, yanıt alanları geriye uyumlu kalmalı.

**Komutlar**
```bash
curl -s "https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json?current_version=4.1.4&uid=<CIHAZ_UID>"
ssh -p 22667 salihceylan@178.210.161.55 "ls -l /var/www/site_kapi_kontrol/server/firmware/esp32-c3 /var/www/site_kapi_kontrol/server/firmware/esp32-wroom"
```

**İlgili testler:** [server/test/devices_firmware_manifest.test.js](../../server/test/devices_firmware_manifest.test.js)

**Bkz.:** [altyapi-ota-hedef-uyusmazligi](#altyapi-ota-hedef-uyusmazligi), [altyapi-ota-dosya-indirilemiyor](#altyapi-ota-dosya-indirilemiyor), [altyapi-ota-toplu-komut-hatasi](#altyapi-ota-toplu-komut-hatasi)

<a id="altyapi-ota-hedef-uyusmazligi"></a>
### altyapi-ota-hedef-uyusmazligi · OTA manifest 403 "FIRMWARE_TARGET_MISMATCH" döner ya da günlükte "[OTA] Manifest hedefi klasorle uyusmuyor"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:143](../../server/src/routes/firmware_routes.js#L143) | <code>code: 'FIRMWARE_TARGET_MISMATCH',</code> | Cihazın KENDİ bildirdiği donanım hedefi istenen klasörle çelişirse 403; cihaz yanlış hedefin manifestini istiyor |
| [server/src/routes/firmware_routes.js:139](../../server/src/routes/firmware_routes.js#L139) | <code>if (targetCheck.source === 'reported') {</code> | Yalnız cihaz bildirimi kesin sayılır; sadece devices.hardware_type çelişiyorsa cihaz kilitlenmez, uyarı yazılır |
| [server/src/routes/firmware_routes.js:183](../../server/src/routes/firmware_routes.js#L183) | <code>console.error(`[OTA] Manifest hedefi klasorle uyusmuyor: klasor=${folderTarget}, manifest…</code> | manifest.json içindeki target alanı bulunduğu klasörle uyuşmuyorsa yayın durdurulur (yanlış klasöre konmuş dosya) |
| [server/src/routes/firmware_routes.js:48](../../server/src/routes/firmware_routes.js#L48) | <code>function warnDbTargetMismatch(uid, targetCheck) {</code> | DB tipi ile istenen hedef farkı UID başına 10 dakikada bir "[OTA] Kayitli hardware_type" uyarısı olarak yazılır |
| [server/src/services/firmware_manifest_service.js:29](../../server/src/services/firmware_manifest_service.js#L29) | <code>export function resolveManifestTarget(manifest, folderTarget) {</code> | Manifest target alanı yoksa klasör adı; varsa kanonikleştirilip klasörle karşılaştırılır (esp32_c3 = esp32-c3) |
| [server/src/services/firmware_manifest_service.js:50](../../server/src/services/firmware_manifest_service.js#L50) | <code>export function checkDeviceFirmwareTarget({ folderTarget, hardwareType, reportedTarget = …</code> | Cihaz bildirimi varsa o esas alınır; yoksa devices.hardware_type ile karşılaştırılır |

**Olası nedenler**
- İki donanımın (C3 ve WROOM) .bin ya da manifest dosyaları birbirinin klasörüne konmuş (kural: asla karıştırılmaz)
- Cihaz yanlış hedef yoluyla manifest istiyor (firmware OTA_TARGET ayarı)
- DB'deki hardware_type yanlış; cihaz bildirimi gelene kadar uyarı üretir

**Adım adım kontrol**
- Cihazın bildirdiği hedefi (device_runtime_status.hardware_target) ve devices.hardware_type'ı sorgulayın.
- Klasördeki manifest.json "target" alanı klasör adıyla aynı olmalı; hedefler karıştırılmadan düzeltin ve sha256'yı yeniden doğrulayın.
- Sunucu kodunu cihazı yanlışlıkla kilitleyecek şekilde gevşetmeyin/sıkılaştırmayın; sahadaki cihazların davranışı değişir.

**Günlükte aranacak ifadeler**
- `[OTA] Manifest hedefi klasorle uyusmuyor`
- `[OTA] Kayitli hardware_type`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT d.device_uid, d.hardware_type, r.hardware_target FROM devices d LEFT JOIN device_runtime_status r ON r.device_uid = d.device_uid ORDER BY 1;"
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a '\[OTA\]' | tail -n 8 | cut -c1-220"
```

**İlgili testler:** [server/test/devices_firmware_manifest.test.js](../../server/test/devices_firmware_manifest.test.js)

**Bkz.:** [altyapi-ota-manifest-guncelleme-sunmuyor](#altyapi-ota-manifest-guncelleme-sunmuyor), [altyapi-ota-dosya-indirilemiyor](#altyapi-ota-dosya-indirilemiyor)

<a id="altyapi-ota-dosya-indirilemiyor"></a>
### altyapi-ota-dosya-indirilemiyor · Cihaz manifesti alıyor ama .bin indiremiyor ya da manifest 500/503 veriyor ("Firmware manifest okunamadi", "Firmware dosyasi bulunamadi", "Cihaz dogrulamasi gecici olarak yapilamadi")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/firmware_routes.js:221](../../server/src/routes/firmware_routes.js#L221) | <code>return res.status(500).json({ error: 'Firmware manifest okunamadi.' });</code> | manifest.json bozuk JSON ya da okunamıyorsa 500; ayrıntı günlüğe yazılmaz (catch hatayı yutar), dosyayı elle doğrulayın |
| [server/src/routes/firmware_routes.js:127](../../server/src/routes/firmware_routes.js#L127) | <code>return res.status(503).json({ error: 'Cihaz dogrulamasi gecici olarak yapilamadi.' });</code> | Geçerli UID ile gelen istekte DB sorgusu başarısızsa 503 (DB sorunu; cihaz sonra yeniden dener) |
| [server/src/routes/firmware_routes.js:240](../../server/src/routes/firmware_routes.js#L240) | <code>return res.status(404).json({ error: 'Firmware dosyasi bulunamadi.' });</code> | manifestteki filename klasörde yok: .bin kopyalanmamış ya da ad farklı |
| [server/src/routes/firmware_routes.js:212](../../server/src/routes/firmware_routes.js#L212) | <code>? `${publicBaseUrl(req)}/firmware/${folderTarget}/${fileName}`</code> | İndirme URL'si PUBLIC_BASE_URL'den üretilir; cihaz yalnız https://api.gudeteknoloji.com.tr/ ile başlayanı kabul eder (OTA_KURULUM.txt) |
| [server/src/routes/firmware_routes.js:254](../../server/src/routes/firmware_routes.js#L254) | <code>headers['x-MD5'] = md5;</code> | Manifestte geçerli md5 varsa x-MD5 başlığı gönderilir (cihaz ikinci kontrol olarak kullanır) |
| [server/src/routes/firmware_routes.js:25](../../server/src/routes/firmware_routes.js#L25) | <code>const firmwareRoot = path.resolve(process.env.FIRMWARE_DIR &#124;&#124; path.join(process.cwd(), 'f…</code> | Kök klasör FIRMWARE_DIR ya da <cwd>/firmware; PM2 cwd = server/ olmalı |
| [server/src/utils/helpers.js:31](../../server/src/utils/helpers.js#L31) | <code>export function safeFirmwareFile(value) {</code> | Dosya adı yalnız harf/rakam/_/./- ve .bin uzantılı olabilir; aksi halde 400 |

**Olası nedenler**
- .bin dosyası klasörde yok ya da manifest filename ile farklı adda
- manifest.json geçersiz JSON (virgül/tırnak hatası)
- sha256 manifestte yok/yanlış: cihaz indirir ama güncellemeyi UYGULAMAZ (firmware tarafı; ota_failed olayı)
- PUBLIC_BASE_URL yanlış: URL cihazın kabul ettiği adresle başlamaz
- DB geçici hatası: manifest 503

**Adım adım kontrol**
- Sunucuda dosya var mı ve sha256 manifestle aynı mı: sha256sum firmware/<hedef>/<dosya>.bin.
- Manifest dosyasını JSON olarak doğrulayın (node -e "JSON.parse(...)" ya da jq).
- İndirmeyi dışarıdan deneyin (komut aşağıda; dosyayı kaydetmeden yalnız başlıkları görün).

**Komutlar**
```bash
curl -sI https://api.gudeteknoloji.com.tr/firmware/esp32-c3/firmware.bin
ssh -p 22667 salihceylan@178.210.161.55 "sha256sum /var/www/site_kapi_kontrol/server/firmware/esp32-c3/firmware.bin; head -c 600 /var/www/site_kapi_kontrol/server/firmware/esp32-c3/manifest.json"
```

**İlgili testler:** [server/test/devices_firmware_manifest.test.js](../../server/test/devices_firmware_manifest.test.js)

**Bkz.:** [altyapi-ota-manifest-guncelleme-sunmuyor](#altyapi-ota-manifest-guncelleme-sunmuyor), [altyapi-ota-hedef-uyusmazligi](#altyapi-ota-hedef-uyusmazligi), [altyapi-ota-toplu-komut-hatasi](#altyapi-ota-toplu-komut-hatasi)

<a id="altyapi-ota-toplu-komut-hatasi"></a>
### altyapi-ota-toplu-komut-hatasi · Şirket/yönetici panelinde "Tümüne OTA kontrolü" 503 "MQTT baglantisi hazir degil" ya da 500 veriyor; ota_check cihazlara gitmiyor (trigger_ota.js dahil)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/routes/admin_routes.js:1581](../../server/src/routes/admin_routes.js#L1581) | <code>adminRouter.post('/admin/devices/ota-check', authRequired, requireSuperUser, async (req, …</code> | Toplu uç: tüm cihaz UID'lerini alır, iş kaydı açar, her cihaza ota_check yayınlar; yalnız super_user |
| [server/src/routes/admin_routes.js:1616](../../server/src/routes/admin_routes.js#L1616) | <code>return res.status(503).json({ error: 'MQTT baglantisi hazir degil.' });</code> | Köprü bağlı değilse yayın yapılamaz: önce /health mqtt.connected (altyapi-health-mqtt-baglanti-yok) |
| [server/src/mqtt_bridge.js:1193](../../server/src/mqtt_bridge.js#L1193) | <code>export async function publishOtaCheckToDevices({</code> | Her UID için device/<uid>/cmd konusuna {action:ota_check, retry:true, ota_job_id} QoS1 yayınlar; tekil hatalar failed listesine girer |
| [server/src/services/device_service.js:428](../../server/src/services/device_service.js#L428) | <code>export async function createOtaUpdateJob({ authUser, deviceUids }) {</code> | ota_update_jobs ve cihaz bazlı satırlar oluşturulur; tablolar eksikse 500 |
| [server/src/mqtt_bridge.js:453](../../server/src/mqtt_bridge.js#L453) | <code>function otaJobDeviceEventStatus(eventName) {</code> | Cihazın OTA olayları (ota_success, ota_failed...) iş satırının durumuna çevrilir |
| [server/scripts/trigger_ota.js:59](../../server/scripts/trigger_ota.js#L59) | <code>`device/${targetUid}/cmd`,</code> | Tek cihaza elle ota_check: device/<UID>/cmd, yalnız UID argümanı zorunlu (varsayılan cihaz yok) |

**Olası nedenler**
- MQTT köprüsü bağlı değil (broker, sertifika, kimlik)
- ota_update_jobs tabloları yok (şema) (altyapi-relation-does-not-exist)
- trigger_ota.js: MQTT_URL/MQTT_HOST, MQTT_USER, MQTT_PASSWORD tanımsız ya da UID 6-32 haneli onaltılık değil
- Cihaz çevrimdışı: komut QoS1 ama retain değil; çevrimdışı cihaz komutu sonradan almayabilir (cihaz zaten 24 saatte bir kendi kontrol eder)

**Adım adım kontrol**
- /health mqtt.connected true mu? Değilse önce köprü sorununu çözün.
- trigger_ota.js: kullanım "node scripts/trigger_ota.js <UID>"; MQTT sırları .env'den okunur, betik sır basmaz. Gerçek cihaza komut gönderir: yalnız hedef UID'den emin olarak çalıştırın.
- İş sonucu: ota_update_jobs son satırı (aşağıdaki sorgu).

**Günlükte aranacak ifadeler**
- `MQTT_URL (veya MQTT_HOST), MQTT_USER ve MQTT_PASSWORD ortam degiskenleri tanimli olmali.`
- `OTA kontrol komutu basariyla yayinlandi!`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT id, status, requested_count, sent_count, failed_count, completed_at FROM ota_update_jobs ORDER BY id DESC LIMIT 5;"
```

**İlgili testler:** [server/test/ops_ota_check_retry.test.js](../../server/test/ops_ota_check_retry.test.js), [server/test/fix_sx1_company_ota.test.js](../../server/test/fix_sx1_company_ota.test.js)

**Bkz.:** [altyapi-health-mqtt-baglanti-yok](#altyapi-health-mqtt-baglanti-yok), [altyapi-ota-manifest-guncelleme-sunmuyor](#altyapi-ota-manifest-guncelleme-sunmuyor), [altyapi-mqtt-konu-ve-uid](#altyapi-mqtt-konu-ve-uid)

<a id="altyapi-apply-013-024-tek-seferlik"></a>
### altyapi-apply-013-024-tek-seferlik · apply_013 ... apply_024 betiği hata verdi ya da başarılı göründü ama tablo/kolon yok ("Migration error:", "MIGRATION_0xx_SUCCESS" görünmedi)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/apply_013.js:16](../../server/scripts/apply_013.js#L16) | <code>console.log('MIGRATION_013_SUCCESS');</code> | 013: qr_access_tokens.used_at / use_count ve indeks (SQL betikte satır içidir, migrations/ dosyası kullanmaz) |
| [server/scripts/apply_014.js:16](../../server/scripts/apply_014.js#L16) | <code>console.log('MIGRATION_014_SUCCESS');</code> | 014: qr_access_tokens red nedeni kolonları (satır içi SQL) |
| [server/scripts/apply_015.js:18](../../server/scripts/apply_015.js#L18) | <code>await pool.query(`UPDATE qr_access_tokens SET is_used = TRUE WHERE used_at IS NOT NULL OR…</code> | 015: migrations/015_qr_single_use.sql + mevcut kullanılmış token'ları is_used yapan veri güncellemesi |
| [server/scripts/apply_016.js:43](../../server/scripts/apply_016.js#L43) | <code>console.log('MIGRATION_016_SUCCESS');</code> | 016: üyelik v2 şeması; sonrasında tablo/kolon varlığı sorgulanır |
| [server/scripts/apply_017.js:27](../../server/scripts/apply_017.js#L27) | <code>console.log('MIGRATION_017_SUCCESS');</code> | 017: users.role için individual rolü; kendi pg Pool'unu server/.env'den kurar (src/db.js havuzunu kullanmaz) |
| [server/scripts/apply_018.js:27](../../server/scripts/apply_018.js#L27) | <code>console.log('MIGRATION_018_SUCCESS');</code> | 018: cihaz sahiplenme (device claiming) şeması |
| [server/scripts/apply_019.js:27](../../server/scripts/apply_019.js#L27) | <code>console.log('MIGRATION_019_SUCCESS');</code> | 019: katılma isteği notları |
| [server/scripts/apply_020.js:27](../../server/scripts/apply_020.js#L27) | <code>console.log('MIGRATION_020_SUCCESS');</code> | 020: QR güvenliği ve geofence kolonları |
| [server/scripts/apply_021.js:27](../../server/scripts/apply_021.js#L27) | <code>console.log('MIGRATION_021_SUCCESS');</code> | 021: site silme onayı |
| [server/scripts/apply_022.js:32](../../server/scripts/apply_022.js#L32) | <code>console.error('Migration 022 failed:', err);</code> | 022: süper kullanıcı site silme kodu |
| [server/scripts/apply_023.js:18](../../server/scripts/apply_023.js#L18) | <code>console.error('Migrasyon 023 hatası:', error);</code> | 023: yönetici davetleri. DİKKAT: hata yakalanır ve YALNIZ yazılır; çıkış kodu 0 kalır, başarısızlık fark edilmeyebilir |
| [server/scripts/apply_024.js:12](../../server/scripts/apply_024.js#L12) | <code>const sqlPath = path.join(__dirname, '..', 'migrations', '024_device_inventory_and_defect…</code> | 024: cihaz envanteri ve kusur yönetimi; 025-028 için apply betiği yoktur |

**Olası nedenler**
- ALLOW_DEV_SCRIPTS=1 verilmedi: betik hiçbir şey yapmadan çıkar (altyapi-apply-betikleri-dev-guard)
- Betik, .env'deki veritabanına bağlanır: yanlış/boş DB_* ile bağlantı hatası (altyapi-db-baglanti-reddi)
- Bağımlı tablo yok: önceki migrasyon uygulanmamış (sıra 013 -> 024)
- apply_023: hata yutulduğu için "başarılı" sanılır; çıktıda "Migrasyon 023 başarıyla uygulandı." satırı aranmalı

**Adım adım kontrol**
- Bu betikler ESKİ, tek seferlik uygulayıcılardır; güncel yol migrate.js (schema_migrations) ve açılıştaki ensureDbSchema'dır. Canlıda bu betikleri çalıştırmayın.
- Son satırda MIGRATION_0xx_SUCCESS (023 için "başarıyla uygulandı") görünmeli; yoksa hata metnini okuyun.
- Hedef kolon/tablonun varlığını information_schema ile salt-okunur sorgulayın.

**Günlükte aranacak ifadeler**
- `MIGRATION_013_SUCCESS`
- `Migration error:`
- `MIGRATION_015_FAILED:`
- `Migration failed:`
- `Migrasyon 023 hatası:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT column_name FROM information_schema.columns WHERE table_name='qr_access_tokens' ORDER BY 1;"
```

**İlgili testler:** [server/test/ops_migration_chain.test.js](../../server/test/ops_migration_chain.test.js)

**Bkz.:** [altyapi-apply-betikleri-dev-guard](#altyapi-apply-betikleri-dev-guard), [altyapi-migrate-sql-hatasi](#altyapi-migrate-sql-hatasi), [altyapi-relation-does-not-exist](#altyapi-relation-does-not-exist)

<a id="altyapi-teshis-betikleri"></a>
### altyapi-teshis-betikleri · check_devs.js / check_screen_qr.js / test_doors_qr.js / test_query.js ne yapar, hangi veritabanına bağlanır, çalıştırmak güvenli mi, neden boş/hatalı çıktı veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/check_devs.js:5](../../server/scripts/check_devs.js#L5) | <code>const devs = await pool.query('SELECT * FROM device_runtime_status');</code> | Salt-okunur: cihaz çalışma durumu ve kapı-cihaz eşleşmesi (LEFT JOIN) basılır; yazmaz |
| [server/scripts/check_screen_qr.js:15](../../server/scripts/check_screen_qr.js#L15) | <code>for (const [uid, data] of deviceScreenQrStore.entries()) {</code> | Bu betik kendi sürecinde yeni bir köprü bellek deposuna bakar: canlı API'nin belleğini GÖRMEZ, bu yüzden genelde "bellek bos" yazar |
| [server/scripts/check_screen_qr.js:5](../../server/scripts/check_screen_qr.js#L5) | <code>function maskToken(token) {</code> | Ekran QR token'ları kapı açabildiğinden ham yazılmaz: yalnız ilk 2 karakter ve uzunluk |
| [server/scripts/test_doors_qr.js:5](../../server/scripts/test_doors_qr.js#L5) | <code>const cleanUid = '00861A0D5020';</code> | SABİT bir UID için kapı eşleşmesini sorgular (salt-okunur); başka cihaz için dosyada UID değiştirilmeli |
| [server/scripts/test_query.js:5](../../server/scripts/test_query.js#L5) | <code>const dev = await pool.query("SELECT * FROM devices WHERE device_uid = 'D4C771A172E0'");</code> | SABİT UID/kullanıcı için cihaz, kullanıcı ve üyelik satırlarını basar (salt-okunur); kişisel veri içerir, çıktıyı paylaşmayın |
| [server/scripts/_dev_guard.js:3](../../server/scripts/_dev_guard.js#L3) | <code>if (process.env.ALLOW_DEV_SCRIPTS !== '1') {</code> | Tümü bekçi arkasında; ALLOW_DEV_SCRIPTS=1 olmadan çıkar |
| [server/src/db.js:72](../../server/src/db.js#L72) | <code>export const pool = new Pool({</code> | Betikler src/db.js havuzunu kullanır: server/.env'deki DB_* hangisiyse O veritabanına bağlanır (canlı sunucuda çalıştırılırsa CANLI DB) |

**Olası nedenler**
- Beklenen: bu betikler geliştirme yardımcılarıdır, sabit UID/kullanıcıya bağlıdır; boş sonuç çoğu zaman o kayıt bu veritabanında yoktur demektir
- check_screen_qr: ayrı süreç olduğu için canlı bellek deposunu göstermez

**Adım adım kontrol**
- Güvenlik: bu dört betik yalnız okur (SELECT) ve test_endpoint.js'ten farklı olarak veri yazmaz. Yine de .env canlıyı gösteriyorsa canlı DB'ye bağlanırlar ve çıktı kişisel veri içerebilir.
- Canlı durum için betik yerine altyapi-komut-rehberi'ndeki salt-okunur sorguları ve /health kullanın.

**Günlükte aranacak ifadeler**
- `Henuz screen_qr mesaji gelmedi veya bellek bos.`

**Bkz.:** [altyapi-apply-betikleri-dev-guard](#altyapi-apply-betikleri-dev-guard), [altyapi-test-endpoint-artik-kullanici](#altyapi-test-endpoint-artik-kullanici), [altyapi-komut-rehberi](#altyapi-komut-rehberi)

<a id="altyapi-test-endpoint-artik-kullanici"></a>
### altyapi-test-endpoint-artik-kullanici · test_endpoint.js çalıştırıldıktan sonra "Delete Test User" / deletetest99991@example.com kullanıcısı veritabanında kalmış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/test_endpoint.js:12](../../server/scripts/test_endpoint.js#L12) | <code>INSERT INTO users (user_code, full_name, email, password_hash, role, is_active, email_ver…</code> | DB'ye gerçek bir test kullanıcısı YAZAR (user_code 99991, parola özeti sahte); salt-okunur DEĞİLDİR |
| [server/scripts/test_endpoint.js:19](../../server/scripts/test_endpoint.js#L19) | <code>const delResponse = await fetch('http://localhost:8080/admin/users/99991', {</code> | Yerel 8080'deki API'ye DELETE atar; API ayakta değilse fetch hata verir ve kullanıcı SİLİNMEDEN kalır |
| [server/scripts/test_endpoint.js:8](../../server/scripts/test_endpoint.js#L8) | <code>const token = signAccessToken(admin, { passwordHash: admin.password_hash });</code> | DB'deki ilk (silinmemiş) super_user adına, parola sürümüne (pv) bağlı JWT üretir (JWT_SECRET .env'den); sır basmaz ama yetkili istek yapar |
| [server/scripts/_dev_guard.js:5](../../server/scripts/_dev_guard.js#L5) | <code>'Bu gelistirme betigi gercek veritabanina dokunabilir. Bilerek calistirmak icin ALLOW_DEV…</code> | Bekçi mesajı; bu betik için gerçekten geçerlidir |

**Olası nedenler**
- Betik silme isteği başarısız oldu (API kapalı, 401/403/500): geçici kullanıcı kaldı
- Betik silme adımından önce kesildi

**Adım adım kontrol**
- Canlı veritabanında çalıştırmayın: gerçek kullanıcı tablosuna kayıt ekler ve süper yönetici belirteciyle silme uçunu çağırır.
- Kalıntı kontrolü salt-okunur SELECT ile yapılır (aşağıda). Silme için kullanıcı onayı alın; uygun yol yönetici panelindeki kullanıcı silme ucudur.

**Günlükte aranacak ifadeler**
- `Created temp user:`
- `Delete Response Status:`
- `SUCCESS: User deleted cleanly via API!`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol' <<< "SELECT user_code, email, role FROM users WHERE user_code = 99991;"
```

**Bkz.:** [altyapi-teshis-betikleri](#altyapi-teshis-betikleri), [altyapi-apply-betikleri-dev-guard](#altyapi-apply-betikleri-dev-guard)

<a id="altyapi-company-api-key-uretildi"></a>
### altyapi-company-api-key-uretildi · Dağıtımdan sonra şirket aracı (company_qr_tool) sunucuya 401 alıyor ya da "COMPANY_API_KEY tanimli degil" uyarısı çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_deploy.sh:63](../../deploy/remote_deploy.sh#L63) | <code>KEY=$(node -e "console.log(require('crypto').randomBytes(36).toString('base64url'))")</code> | activate, anahtar yoksa/24 karakterden kısaysa YENİ rastgele anahtar üretip .env'e yazar; eski anahtar silinir, şirket aracındaki değer geçersiz kalır |
| [deploy/remote_deploy.sh:66](../../deploy/remote_deploy.sh#L66) | <code>echo "COMPANY_API_KEY tanimlandi (uzunluk ${#KEY})"</code> | Betik anahtarı DEĞİL yalnız uzunluğunu yazar; değeri sunucudaki .env'dedir |
| [deploy/remote_verify.sh:27](../../deploy/remote_verify.sh#L27) | <code>echo "== sirket ucu anahtarsiz (401 beklenir)"; curl -s -m 8 -o /dev/null -w "%{http_code…</code> | Doğrulama: anahtarsız şirket ucu 401 vermeli |
| [server/src/config/env.js:325](../../server/src/config/env.js#L325) | <code>warnings.push('COMPANY_API_KEY tanimli degil; /api/company/* yalnizca super_user JWT ile …</code> | Anahtar yoksa şirket uçları yalnız super_user JWT ile çalışır |
| [deploy/README.md:37](../../deploy/README.md#L37) | <code>- `.env` değişiklikleri (ör. `COMPANY_API_KEY`) elle ve sırlar yazdırılmadan yapılır; ayn…</code> | Anahtar elle ve sır yazdırmadan alınıp şirket aracının .env'ine konmalıdır |

**Olası nedenler**
- İlk dağıtımda anahtar otomatik üretildi ama company_qr_tool/.env güncellenmedi
- Sunucu .env'indeki anahtar 24 karakterden kısaydı ve yenisiyle değiştirildi
- Şirket aracı X-Company-Key başlığını göndermiyor

**Adım adım kontrol**
- Anahtarın varlığını ve uzunluğunu deploy/remote_audit.sh "kritik uzunluklar" bölümünden doğrulayın; DEĞERİ okumayın/yazdırmayın.
- Değeri kullanıcı elle sunucu .env'inden alıp şirket aracına koyar; anahtar sohbete/günlüğe/depoya yazılmaz.
- Değişikliği etkinleştirmek için API yeniden başlatılır (altyapi-env-degisikligi-etkisiz).

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_audit.sh   # COMPANY_API_KEY uzunluk=...
curl -s -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/api/company/labeled-devices
```

**Bkz.:** [altyapi-env-uyari-eksik-ayarlar](#altyapi-env-uyari-eksik-ayarlar), [altyapi-env-degisikligi-etkisiz](#altyapi-env-degisikligi-etkisiz), [altyapi-deploy-activate-geri-alma](#altyapi-deploy-activate-geri-alma)

<a id="altyapi-disk-dolu-yedekler"></a>
### altyapi-disk-dolu-yedekler · Sunucu diski doluyor / dağıtım yedeği alınırken yazma hatası; ~/backups altında çok sayıda kapi_<TS> dizini birikmiş

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [deploy/remote_deploy.sh:32](../../deploy/remote_deploy.sh#L32) | <code>mkdir -p "$BK"</code> | Her dağıtım yeni bir ~/backups/kapi_<TS>/ açar; betik eski yedekleri SİLMEZ |
| [deploy/remote_deploy.sh:35](../../deploy/remote_deploy.sh#L35) | <code>tar -czf "$BK/server_code.tgz" --exclude='server/node_modules' --exclude='server/node_mod…</code> | Kod yedeği (node_modules, firmware, public hariç; .env ve data dahil) |
| [deploy/remote_deploy.sh:83](../../deploy/remote_deploy.sh#L83) | <code>mv "$APP/node_modules" "$APP/node_modules.old_$TS"</code> | Her aktivasyonda eski node_modules server/ altında node_modules.old_<TS> olarak KALIR (otomatik temizlenmez) |
| [deploy/remote_deploy.sh:10](../../deploy/remote_deploy.sh#L10) | <code>STAGE="$HOME/kapi_stage_$TS"</code> | Aşama dizini ($HOME/kapi_stage_<TS>) ve paket (kapi_deploy_<TS>.tgz) de birikir |
| [deploy/remote_audit.sh:21](../../deploy/remote_audit.sh#L21) | <code>echo "== disk"; df -h /var/www &#124; tail -1</code> | Salt-okunur disk kullanımı satırı |
| [deploy/remote_audit.sh:20](../../deploy/remote_audit.sh#L20) | <code>echo "== yedek dizini"; ls -la ~/backups 2&gt;&amp;1 &#124; head -6</code> | Yedek dizini listesi (son girdiler) |

**Olası nedenler**
- Eski yedek/aşama/node_modules.old dizinleri hiç temizlenmemiş (betikte temizlik adımı yok)
- Docker/PostgreSQL ya da başka sitelerin verisi diski dolduruyor (paylaşımlı sunucu)

**Adım adım kontrol**
- Kullanımı ölçün (komut aşağıda). Silmeden önce kullanıcıya gösterin: yedekler son güvenli dönüş noktasıdır; en yeni yedeği ve son çalışan sürümün node_modules.old'unu silmeyin.
- Paylaşımlı sunucuda yalnız kapi-api'ye ait dizinlere dokunulur.

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "df -h /var/www | tail -n 1; du -sh ~/backups ~/kapi_stage_* ~/kapi_deploy_*.tgz 2>/dev/null | tail -n 12"
ssh -p 22667 salihceylan@178.210.161.55 "ls -d /var/www/site_kapi_kontrol/server/node_modules.old_* 2>/dev/null"
```

**Bkz.:** [altyapi-geri-alma-ve-yedek](#altyapi-geri-alma-ve-yedek), [altyapi-deploy-prepare-basarisiz](#altyapi-deploy-prepare-basarisiz), [altyapi-docker-postgres-calismiyor](#altyapi-docker-postgres-calismiyor)

