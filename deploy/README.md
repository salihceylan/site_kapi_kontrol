# Canlı sunucu dağıtımı (AGENTS.md kural 8)

VPS: `178.210.161.55` (SSH portu `22667`, kullanıcı `salihceylan`, **anahtarla giriş**), uygulama dizini `/var/www/site_kapi_kontrol/server`, PM2 süreç adı `kapi-api` (`npm start`), veritabanı Docker kapsayıcısı `site_kapi_kontrol_postgres`. Sunucuda başka projeler de çalışır (ev-api, teklif-pro-api, dijitarla…): yalnız `kapi-api` ve bu dizine dokunulur.

Betikler sır içermez. Parola/anahtar yazılmaz; `.env` dosyası dağıtım paketine GİRMEZ.

## Adımlar

1. **Yerel doğrulama:** `cd server && npm test && npm run lint` (hepsi geçmeli).
2. **Paket (yerelde, Git Bash):**
   ```bash
   cd server
   TS=$(date +%Y%m%d_%H%M%S)
   tar czf /tmp/kapi_deploy_$TS.tgz src scripts migrations package.json package-lock.json ecosystem.config.cjs .env.example
   sha256sum /tmp/kapi_deploy_$TS.tgz
   ```
   (`tar` Windows yolundaki `C:` önekini uzak sunucu sanır: `/c/...` biçimini kullanın veya `--force-local` verin.)
3. **Yükleme:**
   ```bash
   scp -P 22667 /tmp/kapi_deploy_$TS.tgz salihceylan@178.210.161.55:/home/salihceylan/
   scp -P 22667 deploy/remote_deploy.sh salihceylan@178.210.161.55:/home/salihceylan/kapi_remote_deploy_$TS.sh
   ssh -p 22667 salihceylan@178.210.161.55 "sha256sum /home/salihceylan/kapi_deploy_$TS.tgz"   # yereldeki özetle aynı olmalı
   ```
4. **Hazırlık (canlıya dokunmaz):** `ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS prepare"` → yedek (`~/backups/kapi_$TS/server_code.tgz` [.env ve data dahil], `db.sql.gz`), `node --check`, aşamalı `npm ci --omit=dev`. Çıktı `PREPARE_OK` ile bitmeli.
5. **İsteğe bağlı kuru çalıştırma (ACL):** yeni kodun ürettiği MQTT ACL'ini canlı DB ile görmek için sunucuda hazırlık dizininden `node scripts/sync_mqtt_acl.js --dry-run` çalıştırın. **`.env` dosyasını `source` ETMEYİN** (satırlardaki boşluklu değerler komut olarak çalışır).
6. **Etkinleştirme:** `ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS activate"` → `COMPANY_API_KEY` yoksa üretir, kodu yerleştirir, `node_modules` değiştirir, `pm2 restart kapi-api --update-env`, `/health` bekler. Sağlık başarısızsa **otomatik geri alma** yapılır.
7. **MQTT ACL (cihaz konuları değiştiyse):** yedekten sonra `sudo -n /usr/local/bin/kapi-mqtt-sync` (NOPASSWD sarmalayıcı; ACL'yi DB'den üretir ve mosquitto'yu yeniden yükler).
8. **Doğrulama:** `ssh ... 'bash -s' < deploy/remote_verify.sh` ve `pm2 logs kapi-api --lines 40 --nostream`.

## Geri alma

`ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS rollback"` — yedekteki kodu (data hariç) geri yükler, eski `node_modules`'i (`node_modules.old_$TS`) geri koyar ve PM2'yi yeniden başlatır. Şema değişiklikleri ekleyici olduğundan veritabanı geri alınmaz (gerekirse `db.sql.gz` ile elle).

## Notlar

- `.env` değişiklikleri (ör. `COMPANY_API_KEY`) elle ve sırlar yazdırılmadan yapılır; aynı anahtar `company_qr_tool/.env` içine konur.
- Uzak-yalnız artık dosyalar (`src/services/membership_routes.js`, `migrations/apply_020.js`, `scripts/trigger_ota_wroom.js`) silinmez.
- Canlı `JWT_SECRET` (≥32 karakter), `JWT_EXPIRES_IN` ve `NODE_ENV=production` kararları kullanıcıya aittir (`BEKLEYEN_ISLER.md`).
