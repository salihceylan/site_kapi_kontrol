# Operasyon: Yedekleme, Geri Yükleme, Dış Kopya ve İzleme

Son güncelleme: 2026-10-16. Kapsam: canlı sunucu (SSH `-p 22667`, kullanıcı `salihceylan`), proje `/var/www/site_kapi_kontrol/server`, PM2 süreci `kapi-api`, veritabanı Docker kapsayıcısı `site_kapi_kontrol_postgres` (postgres:16, veritabanı `site_kapi_kontrol`). Sunucu adresi ve oturum bilgileri için `deploy/README.md`.

Bu belgedeki komut ve sonuçlar şu şekilde işaretlidir:

- **[doğrulandı]**: canlıda (ya da yalıtılmış deneme düzeneğinde) gerçekten çalıştırıldı ve sonucu görüldü.
- **[denenmedi]**: yazıldı ama bu ortamda çalıştırılmadı (kök yetkisi, ikinci sunucu, hesap veya henüz canlıda olmayan özellik gerektirdiği için). İlk kullanımda dikkatle ve önce deneme amaçlı uygulayın.

> **Kapsam uyarısı:** Bu mekanizma yalnızca **site_kapi_kontrol** (kapi-api, `site_kapi_kontrol_postgres` ve ilgili yapılandırma) içindir. Aynı sunucudaki diğer projeler (ev_otomasyon / `ev-api`, EMQX, Redis ve onların veritabanları, teklifpro vb.) bu mekanizmayla **YEDEKLENMEZ**; onların yedekleri sahipleri tarafından ayrıca kurulmalıdır. Hiçbir adım onlara dokunmaz.

---

## 1. Hızlı özet

| Konu | Durum |
|---|---|
| Günlük veritabanı yedeği | Her gün **03:30 (İstanbul)**; `~/backups/scheduled/daily/kapi_<YYYYmmdd_HHMM>.sql.gz` |
| Diskte şifreleme | **Yalnızca en son günlük yedek düz** durur; eski günlükler, haftalık ve aylık kopyalar, yapılandırma ve firmware arşivleri **şifreli** (`.enc`) |
| Tutma | 14 günlük + 8 haftalık + 6 aylık (adet sayısıyla; başarısız çalışma hiçbir şey silmez). Dış kopyalar en çok ~**210 gün** |
| Yapılandırma yedeği (şifreli) | `.env`, nginx sitesi, MQTT broker yapılandırması, `data/`, `public/`, `ecosystem.config.cjs`, veritabanı rolleri, silinmiş hesap listesi |
| Firmware (OTA ikilileri) | `server/firmware` ayrı şifreli arşiv (yalnızca içerik değişince yenilenir) |
| Geri yükleme kanıtı | `restore_test.sh` (düz + şifreli kopyayı sınar); her ayın 2'si 04:15 (İstanbul) + elle |
| Dış kopya | **Henüz yapılandırılmadı** (karar sizde, bölüm 6); izleme bunu hatırlatır |
| Sunucu içi izleme | Her 5 dakikada `healthcheck.sh`; sorun olursa e-posta |
| Sunucu dışı izleme | `.github/workflows/uptime.yml` (30 dk) + ölü adam anahtarı (`HEARTBEAT_URL`) + UptimeRobot önerisi (bölüm 9) |
| PM2 günlük döngüsü | Haftalık / 20 MB, `copytruncate` (kapi-api yeniden başlamaz) |

**En önemli tek şey:** yedeklerin şifre çözme anahtarı `~/.config/kapi-backup.key` **yalnızca sunucuda** durur. Sunucu giderse ve anahtarın bir kopyası başka yerde yoksa şifreli yedeklerin (dış kopyalar dahil) hiçbiri açılamaz. Bölüm 3'ü bugün uygulayın.

---

## 2. Dosya ve zamanlama haritası

### Sunucuda (`/home/salihceylan`)

| Yol | Ne |
|---|---|
| `~/ops/healthcheck.sh` | Her 5 dk izleme + e-posta uyarısı + ölü adam anahtarı |
| `~/ops/backup_db.sh` | Günlük yedek (+ doğrulama, şifreleme, tutma) |
| `~/ops/restore_test.sh` | Geri yükleme kanıtı (geçici veritabanı) |
| `~/ops/offsite_push.sh` | Şifreli yedekleri dış hedefe gönderir (yapılandırma yoksa atlar) |
| `~/ops/logrotate_pm2.sh` | `kapi-api-*.log` döngüsü |
| `~/ops/install_ops.sh` | Dizinleri, anahtarı, parmak izini ve crontab bloğunu kurar (tekrar çalıştırılabilir) |
| `~/ops/common.sh`, `~/ops/ops_mail.mjs` | Ortak yardımcılar, e-posta gönderici (`server/node_modules/nodemailer` + `server/.env`) |
| `~/ops/state/` | Durum dosyaları (`health.state`, `backup.status`, `restore_test.status`, `offsite.status`, `key.sha256`, ...) |
| `~/ops/logs/` | Günlükler (`backup.log`, `healthcheck.log`, `alerts.log`, `restore_test_*.txt`, ...) |
| `~/backups/scheduled/daily` | En son `*.sql.gz` (düz) + eski günlükler `*.sql.gz.enc` (şifreli) + `.sha256` |
| `~/backups/scheduled/weekly`, `monthly` | Şifreli `*.sql.gz.enc` ve `kapi_config_*.tgz.enc` |
| `~/backups/scheduled/config/` | Şifreli `kapi_config_*.tgz.enc` ve `kapi_firmware_*.tgz.enc` |
| `~/backups/scheduled/offsite/` | Dış kopyaya gidecek **yalnızca şifreli** dosyalar |
| `~/.config/kapi-backup.key` | Şifreleme anahtarı (izin 600) |
| `~/.config/kapi-ops.env` (isteğe bağlı) | Alıcı / eşik / `HEARTBEAT_URL` ayarları. Örnek: `deploy/ops/kapi-ops.env.example` |
| `~/.config/kapi-offsite.env` (isteğe bağlı) | Dış kopya hedefi. Örnek: `deploy/ops/kapi-offsite.env.example` |

Dizinler 700, dosyalar 600 izinlidir. Eski elle yedekler (`~/backups/kapi_<TS>/`, dağıtım sırasında alınanlar) ayrıdır; bu mekanizma onlara dokunmaz (temizlik önerisi: bölüm 4.1).

Depodaki kaynak: `deploy/ops/*`. Sunucuya kopyalama (güvenli yöntem: önce geçici dosya, sonra yer değiştirme): `scp -P 22667 deploy/ops/*.sh deploy/ops/*.mjs deploy/ops/*.example salihceylan@<sunucu>:ops/.stage/` ardından sunucuda `bash -n` ve `mv -f` ile `~/ops/` altına alın, sonra `bash ~/ops/install_ops.sh`.

### Crontab (sunucu saati UTC; Türkiye UTC+3, yaz saati uygulaması yok)

```
# BEGIN kapi-ops (install_ops.sh yonetir; elle duzenlemeyin)
*/5 * * * *  ~/ops/healthcheck.sh
30 0 * * *   flock -n ~/ops/locks/cron_backup.lock    nice -n 19 ionice -c3 ~/ops/backup_db.sh      # 03:30 İstanbul
50 0 * * *   flock -n ~/ops/locks/cron_offsite.lock   nice -n 19 ionice -c3 ~/ops/offsite_push.sh   # 03:50 İstanbul
5 1 * * *    flock -n ~/ops/locks/cron_logrotate.lock nice -n 19 ionice -c3 ~/ops/logrotate_pm2.sh   # 04:05 İstanbul
15 1 2 * *   flock -n ~/ops/locks/cron_restore.lock   nice -n 19 ionice -c3 ~/ops/restore_test.sh    # ayın 2'si 04:15 İstanbul
# END kapi-ops
```

(Gerçek satırlarda `~` yerine `/home/salihceylan` yazılıdır; çıktılar `~/ops/logs/cron_*.out` dosyalarına gider.) Ağır işler (yedek / geri yükleme / dış kopya) ayrıca ortak `heavy.lock` kilidini kullanır; üst üste binmez, en fazla 15 dk beklerler. Kilit tanımlayıcıları alt süreçlere miras bırakılmaz (PM2 gibi uzun ömürlü bir alt süreç kilidi sonsuza dek tutamaz); `docker` / `psql` çağrıları zaman aşımlıdır.

`ionice -c3` yalnızca CFQ/BFQ gibi I/O zamanlayıcılarında etkilidir; modern çekirdek/disklerde (mq-deadline, none) etkisiz kalabilir (zararsızdır). Asıl koruma `nice` ve verinin küçük olmasıdır.

Crontab bloğunu kaldırmak için: `bash ~/ops/install_ops.sh --remove-cron` (blok dışındaki satırlara dokunmaz; önceki crontab `~/ops/state/crontab.before.<TS>` dosyasına yedeklenir). `crontab -l` "no crontab" dışında bir hata verirse veya blokta BEGIN var END yoksa betik **hiçbir şey değiştirmeden durur**.

---

## 3. Şifreleme anahtarı (bugün yapılacak)

Yapılandırma / firmware yedeği, eski günlük, haftalık ve aylık kopyalar ile dış kopyaya giden tüm dosyalar `openssl enc -aes-256-cbc -pbkdf2 -iter 200000` ile şifrelenir; parola olarak `~/.config/kapi-backup.key` dosyasının ilk satırı kullanılır. Anahtarı **hiçbir yere yapıştırmayın/yazdırmayın**; yalnızca güvenli bir yere kopyalayın.

**Parmak izi kontrolü:** `install_ops.sh` anahtarın SHA-256 değerini `~/ops/state/key.sha256` dosyasına kaydeder. Doğru anahtarı kopyaladığınızı anlamak için sunucuda `cut -c1-12 ~/ops/state/key.sha256` çıktısını, kopyaladığınız dosyanın SHA-256 değerinin ilk 12 hanesiyle (`certutil -hashfile dosya SHA256` veya Git Bash'te `sha256sum dosya`) karşılaştırın. `healthcheck.sh` her 5 dakikada anahtarı bu kayıtla karşılaştırır; **anahtar kaybolursa ya da değişirse CRIT uyarısı** verir, `install_ops.sh` ve `backup_db.sh` ise anahtar kayıtlıyken kaybolduğunda **sessizce yenisini üretmez** (bilerek yeni anahtar için `install_ops.sh --new-key`, değişikliği kabul için `--accept-new-key`).

**Anahtarı çıkarma (Windows PowerShell, tek seferlik):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\pull_backups_windows.ps1 -FetchKey
```

Bu, anahtarı **yedeklerin klasörünün dışında** `%LOCALAPPDATA%\kapi-anahtar-tasi\kapi-backup.key` dosyasına indirir (içeriği ekrana yazdırmaz; `-KeyDestination` ile başka bir yer verilebilir). Sonra:

1. Dosyanın içeriğini parola yöneticinize (veya çevrimdışı bir USB'ye) kaydedin; `kapi-anahtar-tasi` klasörünü silin.
2. **OneDrive / Dropbox / Google Drive gibi bir eşitlemeye dahil bir klasöre koymayın** (Belgeler ve Masaüstü klasörleri OneDrive ile eşitleniyor olabilir) ve yedeklerle **aynı yerde** tutmayın; aksi halde şifrelemenin anlamı kalmaz.
3. Doğrulama: yukarıdaki parmak izi karşılaştırması.

Anahtarı değiştirmek isterseniz yeni anahtar yalnızca **sonraki** yedekleri etkiler; eski şifreli dosyalar eski anahtarı gerektirir. Eski anahtarı da saklayın (`~/ops/state/key.history` değişiklik zamanlarını tutar).

---

## 4. Yedekler: ne, nasıl, nasıl doğrulanır

`backup_db.sh` sırası (7 adım):

1. `docker exec site_kapi_kontrol_postgres pg_dump -U postgres -d site_kapi_kontrol --lock-wait-timeout=60s | gzip` (zaman aşımlı) → `.kapi_<TS>.sql.gz.part`.
2. **Doğrulama** (hepsi geçmeden dosya yerine konmaz): `gzip -t`; boyut ≥ 8000 bayt (mevcut yedekler ≈ 21 KB); belge sonunda `-- PostgreSQL database dump complete` işareti (kesik yedeği yakalar); ≥ 30 tablo (şu an 42); `users`, `sites`, `site_memberships`, `audit_log` tablolarının varlığı; `users` için `COPY` bölümü; **`users` tablosunda 0 satır varsa FAIL** (önceki yedeğin yarısından azsa UYARI); önceki yedeğin yarısından küçükse UYARI. Disk kontrolü dinamiktir: en az 500 MB ve (son dump + son yapılandırma) × saklama adedi × 3.
3. Anahtar parmak izi doğrulanır, şifreli kopya `offsite/kapi_<TS>.sql.gz.enc` üretilir ve **şifresi çözülen içeriğin SHA-256'sı düz yedekle karşılaştırılır**.
4. Haftalık (ISO haftasının ilk yedeği) ve aylık (ayın ilk yedeği) kopyalar **şifreli** olarak alınır (+ `.sha256`). Kaçırılan günlere dayanıklıdır.
5. **Yapılandırma yedeği** (`config/kapi_config_<TS>.tgz.enc`): `server/.env`, `server/data/`, `server/public/`, `server/ecosystem.config.cjs`, nginx sitesi, MQTT broker yapılandırması (özel anahtarlar hariç) ve ACL eşitleme sarmalayıcısı `kapi-mqtt-sync`, `globals.sql` (veritabanı rolleri; parola özetleri içerir), **`deleted_accounts.csv`** (yalnızca `user_code,deleted_at_utc`; kişisel veri yok; hesap silme özelliği devredeyken `audit_log` `account.deleted` kayıtlarından üretilir), `crontab.txt`, `INFO.txt`. Oluşturulduktan sonra şifresi çözülüp `tar -t` ile `.env`, `globals.sql` ve `deleted_accounts.csv` varlığı doğrulanır.
6. **Firmware arşivi** (`config/kapi_firmware_<TS>.tgz.enc`): OTA ikilileri (`server/firmware`, `.gitignore`'da olduğu için depoda yoktur; ≈ 5 MB). Günlük 5 MB tekrarını önlemek için yalnızca **içerik özeti değişince** yeni arşiv alınır (son 5 tutulur, yaşa göre silinmez).
7. **Şifreleme ve tutma:** en son günlük dışındaki düz yedekler, şifreli kopyaları **doğrulandıktan sonra** (şifresi çözülen içeriğin SHA-256'sı aynı) şifreliye çevrilir. Tutma: günlük 14, haftalık 8, aylık 6 (yapılandırma yedeği için günlük 22, haftalık 8, aylık 6), firmware 5, `offsite/` 14. Adet esaslıdır: cron bir hafta çalışmasa bile eski yedekler silinmez. **Gelecek tarihli** (saati ileri alınmış) dosyalar saklama yuvası saymaz ve silinmez. Dış kopyaya henüz **gönderilmemiş** yerel `offsite/` dosyaları (dış kopya yapılandırılmışsa) budanmaz.

Geçiş notu: şifreli düzene **2026-10-16 20:14'te** geçildi. O andan önce alınmış düz test yedekleri (2026-10-16 18:03–18:13 günlük / haftalık / aylık) silinmedi ve düz kaldı; günlükler en geç 14 gün içinde kendiliğinden gider. Haftalık/aylık düz test kopyasını da şifrelemek isterseniz: `echo 1 > ~/ops/state/enc_scheme_since` yazıp bir sonraki yedeği bekleyin (en son günlük dışındaki tüm düz yedekleri doğrulayarak şifreler).

Neden: veritabanı dökümleri kişisel veriler ve kimlik doğrulama sırları içerebilir; diskte düz duran yedek sayısı en aza indirilir.

Başarısız olursa: durum `~/ops/state/backup.status` içine `result=FAIL` yazılır, hemen e-posta gönderilir ve `healthcheck.sh` aynı olayı tekrar bildirmeden izlemeye alır. Çıkış kodları: 0 tamam, 1 veritabanı yedeği başarısız, 2 düz veritabanı yedeği tamam ama şifreli kopya / yapılandırma / firmware başarısız, 75 kilit alınamadı. Hatalı `KEEP_*` değerleri (sayı ≥ 1 değilse) varsayılana döner ve UYARI yazar.

Elle yedek almak: `ssh -p 22667 salihceylan@<sunucu> "bash ~/ops/backup_db.sh"`. Dağıtımdan (özellikle migration içeren) hemen önce de çalıştırmak iyi bir alışkanlıktır.

### 4.1 Elle (dağıtım) yedekleri için bütçe ve temizlik önerisi

`remote_deploy.sh prepare` her dağıtımda `~/backups/kapi_<TS>/` oluşturur (`db.sql.gz` **düz** döküm + `server_code.tgz` içinde `server/.env`). Bunlar bu mekanizmanın dışındadır, **şifrelenmez ve süresiz kalır**; gizlilik metnindeki saklama süresiyle (dış kopyalar ~210 gün) çelişir. Şu an 13 klasör ≈ 255 MB'dır (ayrıca `server/node_modules.old_*` dağıtım artıkları ≈ 294 MB). Hiçbir şey otomatik silinmez; öneri:

- **Bütçe:** en son **10** dağıtım yedeği ve en fazla **30 gün**; diskin %85'ini aşmamak (`healthcheck` uyarır).
- Adayları görmek için (silmez): `ls -1dt ~/backups/kapi_2* | tail -n +11` (10'dan eskiler) ve `find ~/backups -maxdepth 1 -name 'kapi_2*' -mtime +30`.
- Karar sizindir; elle silerken yalnızca `kapi_<TS>` klasörlerini seçin (`ev_*`, `emqx_*` başka projelerindir, dokunmayın).
- `node_modules.old_*` dizinleri yalnızca geri alma içindir; son 2–3 dağıtımdan eskilerini silmek güvenlidir.

---

## 5. Geri yükleme el kitabı

Genel kural: **canlı veritabanına geri yüklemeden önce mevcut durumun yeni bir yedeğini alın** (`bash ~/ops/backup_db.sh`), geri yüklenecek dosyayı doğrulayın (`gzip -t`) ve hangi senaryoda olduğunuzu netleştirin. Hesap silme özelliği devredeyse **önce bölüm 5.6'daki listeyi çıkarın** (geri yükleme sonrası silinmiş hesapları yeniden kimliksizleştirmek için).

### 5.1 Geri yükleme provası (kanıt) — [doğrulandı, ilk sürüm]

```bash
ssh -p 22667 salihceylan@<sunucu> "bash ~/ops/restore_test.sh"
```

Varsayılan olarak **iki** dosyayı sınar: (1) en son düz günlük yedek, (2) en son **şifreli** dış kopya (`offsite/*.sql.gz.enc`; şifresi çözülür). Her biri `kapi_restoretest_<TS>` adlı geçici bir veritabanına yüklenir, tablo ve satır sayıları canlıyla karşılaştırılır (canlı tarafta oturum `default_transaction_read_only=on`, `lock_timeout=5s`, `statement_timeout=60s` ile salt okunurdur), geçici veritabanı silinir; sonuç `~/ops/state/restore_test.status` ve `~/ops/logs/restore_test_<TS>.txt` dosyalarına yazılır. Yalnızca kendi oluşturduğu `kapi_restoretest_*` veritabanını siler. Tek dosya için: `--file <yol>` (`.sql.gz` veya `.sql.gz.enc`).

**Güvenlik taraması:** yedek dosyası yüklenmeden önce taranır; `\connect`, `DROP/CREATE/ALTER DATABASE` veya beklenmeyen psql meta-komutları (`\!` gibi) içeriyorsa **reddedilir** (aksi halde psql başka/canlı veritabanına bağlanıp işlem yapabilirdi). Bu tarama ve şifreli dosya akışı yalıtılmış düzenekte sahte `docker` ile [doğrulandı]; **son sürümün canlı veritabanı üzerinde tam çalıştırılması henüz yapılmadı [denenmedi]** — ilk sürümün (yalnızca düz dosya) canlı sonucu aşağıdadır, aylık cron ilk kez 2026-11-02'de çalışır.

**İlk sürümün canlı sonucu (2026-10-16 18:03 İstanbul):** `PASS`; yükleme hatası **0**; tablo 42/42; toplam satır 243/243; yapı sayıları (indeks 164, kısıt 203, tetikleyici 7, sıra 29) eşit; süre 4 sn; geçici veritabanı silindi.

PASS ölçütleri: yükleme hatası 0, ≥ 30 tablo, satır > 0, `users`/`sites`/`site_memberships` canlıda doluysa yedekte de dolu. Yedekten sonra canlıda eklenen/silinen satırlar bilgi olarak "canlı +N / canlı -N" yazılır, hata sayılmaz. FAIL olursa e-posta gider ve bölüm 5.8'e bakın.

### 5.2 Şifreli dosyayı açma

Anahtar dosyası `ANAHTAR` olsun (parola yöneticisinden bir dosyaya yazdığınız kopya; iş bitince silin).

```bash
# Veritabanı yedeği (daily/weekly/monthly/offsite veya Windows'a çekilen .sql.gz.enc)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:ANAHTAR -in kapi_20261016_1803.sql.gz.enc -out kapi_20261016_1803.sql.gz
gzip -t kapi_20261016_1803.sql.gz && echo "yedek saglam"

# Yapılandırma yedeği: listele, sonra yalnızca gereken dosyayı çıkar (içinde .env gizlileri var!)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:ANAHTAR -in kapi_config_20261016_1803.tgz.enc | tar -tzf -
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:ANAHTAR -in kapi_config_20261016_1803.tgz.enc | tar -xzf - -C /guvenli/gecici/dizin
```

Windows'ta Git for Windows ile gelen OpenSSL kullanılabilir (`"C:\Program Files\Git\usr\bin\openssl.exe" enc -d ...`; bayraklar aynıdır, sunucu ile Windows arasında uyumluluk **[doğrulandı]**).

**Önemli — yanlış anahtar ve doğrulama:** AES-CBC *kimlik doğrulamasızdır*. Yanlış anahtar çoğu zaman `bad decrypt` hatası verir ama bu **garanti değildir** (dolgu denetimi rastlantıyla geçebilir ve çöp çıktı üretebilir). Gerçek doğrulayıcılar `gzip -t` (veritabanı) ve `tar -tzf` (arşivler) ile `.sha256` / içerik karşılaştırmalarıdır; çözülen çıktıyı bunlardan geçirmeden güvenmeyin.

### 5.3 Senaryo A — yanlışlıkla silinen/bozulan veriyi canlıya dokunmadan kurtarma

Örnek: bir sitenin kayıtları yanlışlıkla silindi. Canlıyı durdurmadan, yedeği geçici veritabanına yükleyip yalnızca gerekli satırları alırsınız.

```bash
# sunucuda
F=~/backups/scheduled/daily/kapi_YYYYmmdd_HHMM.sql.gz        # şifreliyse önce bölüm 5.2 ile açın (örn. ~/kurtar/x.sql.gz)
gzip -t "$F"
docker exec -i site_kapi_kontrol_postgres psql -U postgres -c 'CREATE DATABASE kapi_kurtar'
gzip -dc "$F" | docker exec -i site_kapi_kontrol_postgres psql -U postgres -X -q -d kapi_kurtar -v ON_ERROR_STOP=0 2>~/kurtar.err
grep -c 'ERROR:' ~/kurtar.err                                  # 0 olmalı

# Veriyi incele ve dışa aktar (örnek):
docker exec -i site_kapi_kontrol_postgres psql -U postgres -d kapi_kurtar -c "select count(*) from site_memberships where site_id = 1"
docker exec -i site_kapi_kontrol_postgres psql -U postgres -d kapi_kurtar -c "\copy (select * from site_memberships where site_id = 1) to '/tmp/sm.csv' csv header"
```

Satırları canlıya geri koymak için `INSERT ... SELECT` / `\copy ... from` kullanın; **yabancı anahtarlar ve eşsiz kısıtlar** nedeniyle sırayı (üst tablodan alta) gözetin, önce küçük bir deneme yapın. **Silinmiş bir hesaba ait satırları geri koymayın** (bölüm 5.6). İş bitince geçici veritabanını silin: `docker exec -i site_kapi_kontrol_postgres psql -U postgres -c 'DROP DATABASE kapi_kurtar'`. Bu senaryo [denenmedi] (yükleme kısmı `restore_test.sh` ile aynıdır ve [doğrulandı]).

### 5.4 Senaryo B — aynı sunucuda veritabanını tamamen geri yükleme

Veritabanı bozuldu veya hatalı bir işlemden önceki duruma dönülecek. **Kesinti oluşur**; son yedekten sonraki tüm veriler kaybolur. [denenmedi] (parçaları ayrı ayrı [doğrulandı]).

```bash
# 0) Mevcut durumun güvenlik yedeği + silinmiş hesap listesi (bölüm 5.6) -- geri yüklemeden ÖNCE
bash ~/ops/backup_db.sh || docker exec site_kapi_kontrol_postgres pg_dump -U postgres -d site_kapi_kontrol | gzip > ~/backups/pre_restore_$(date +%Y%m%d_%H%M).sql.gz
docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -At -F, -c "select target_id, created_at from audit_log where action='account.deleted' order by id" > ~/silinen_hesaplar_oncesi.csv
# 1) Geri yüklenecek yedeği seç ve doğrula (düz ya da bölüm 5.2 ile açılmış)
F=~/backups/scheduled/daily/kapi_YYYYmmdd_HHMM.sql.gz
gzip -t "$F" && (cd "$(dirname "$F")" && sha256sum -c "$(basename "$F").sha256")
# 2) API'yi durdur (açık bağlantıları kes)
pm2 stop kapi-api
# 3) Veritabanını yeniden oluştur
docker exec -i site_kapi_kontrol_postgres psql -U postgres -c 'DROP DATABASE site_kapi_kontrol WITH (FORCE)'
docker exec -i site_kapi_kontrol_postgres psql -U postgres -c 'CREATE DATABASE site_kapi_kontrol'
# 4) Yükle
gzip -dc "$F" | docker exec -i site_kapi_kontrol_postgres psql -U postgres -X -q -d site_kapi_kontrol -v ON_ERROR_STOP=0 2>~/restore.err
grep -c 'ERROR:' ~/restore.err                # 0 olmalı
docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -Atc "select count(*) from users"
# 5) Geri yükleme sonrası adımlar (bölüm 5.7): silinmiş hesapları yeniden kimliksizleştir, MQTT kimlik bilgilerini eşitle, e-posta kuyruğunu incele
# 6) API'yi başlat ve sağlık ucunu doğrula
pm2 start kapi-api
sleep 10; curl -s http://127.0.0.1:8080/health   # {"ok":true,"database":"connected",...}
```

Notlar:
- Yedek, `salihceylan` rolüne ait nesneleri ve `public` şeması sahipliğini içerir; rol zaten kapsayıcıda vardır.
- Yedekten sonra eklenen migration'ları uygulamanın `ensureDbSchema()` işlevi başlangıçta idempotent olarak yeniden uygular.
- `psql` sürümü yedeği alan `pg_dump` sürümüyle aynı olmalıdır (kapsayıcı postgres:16.x; 16.10+ sürümler dosya başına `\restrict`/`\unrestrict` satırları ekler). Başka bir makinede `psql` ile yüklerken sürümü ≥ 16.10 yapın.

### 5.5 Senaryo C — sunucu tamamen kayboldu (yeni VPS'te tam kurtarma)

Elinizde olması gerekenler: (1) en az bir **şifreli dış kopya** (`kapi_<TS>.sql.gz.enc`, `kapi_config_<TS>.tgz.enc` ve gerekirse `kapi_firmware_<TS>.tgz.enc`), (2) **`kapi-backup.key` kopyası**, (3) GitHub deposu. Bu senaryo uçtan uca [denenmedi]; adımlar sunucuda kullanılan kurulumdan (`sunucu_kurulum.txt`, `docker-compose.yml`, `deploy/README.md`, `MQTT_kurulum.txt`) türetilmiştir. Süre tahmini: 2–4 saat.

1. **Yeni VPS**: Ubuntu 22.04+, SSH portu 22667, `salihceylan` kullanıcısı, güvenlik duvarı (22667, 80, 443, 8883). `sudo apt install docker.io docker-compose-v2 nginx certbot python3-certbot-nginx mosquitto rsync`, Node.js 24, `sudo npm i -g pm2`.
2. **Dosyaları aç** (yeni sunucuda, güvenli geçici dizine):
   ```bash
   mkdir -m 700 ~/kurtar && cd ~/kurtar
   # kapi_*.enc dosyalarını buraya kopyalayın, anahtarı ~/kurtar/ANAHTAR olarak koyun (iş bitince silin)
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:ANAHTAR -in kapi_config_<TS>.tgz.enc | tar -xzf -
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:ANAHTAR -in kapi_<TS>.sql.gz.enc -out db.sql.gz && gzip -t db.sql.gz
   ls -R    # globals.sql, deleted_accounts.csv, INFO.txt, server/.env, nginx sitesi, MQTT yapılandırması, kapi-mqtt-sync ...
   ```
3. **Kodu getir**: `sudo mkdir -p /var/www/site_kapi_kontrol && sudo chown salihceylan: /var/www/site_kapi_kontrol && git clone https://github.com/salihceylan/site_kapi_kontrol /var/www/site_kapi_kontrol && cd /var/www/site_kapi_kontrol/server && npm ci --omit=dev`. Sonra `cp ~/kurtar/server/.env .env && chmod 600 .env`, `cp -a ~/kurtar/server/data .`, `cp -a ~/kurtar/server/public .`. **Firmware (OTA ikilileri) depoda YOKTUR** (`.gitignore`): `kapi_firmware_<TS>.tgz.enc` dosyasını bölüm 5.2 gibi açıp `tar -xzf - -C /var/www/site_kapi_kontrol` ile `server/firmware/` olarak yerine koyun.
4. **Veritabanı**:
   ```bash
   cd /var/www/site_kapi_kontrol
   # POSTGRES_PASSWORD: kapsayıcının "postgres" SÜPER KULLANICISI için YENİ, güçlü, rastgele bir değerdir (yalnızca ilk kurulumda boş veri dizinine uygulanır;
   # uygulama bunu KULLANMAZ). server/.env içindeki DB_PASSWORD ise uygulamanın kullandığı "salihceylan" rolünün parolasıdır ve aşağıda globals.sql ile geri gelir.
   POSTGRES_PASSWORD=<yeni-rastgele-deger> docker compose up -d postgres
   # (compose, server/migrations'ı ilk kurulumda çalıştırır; geri yüklemeden önce boş veritabanına dönüyoruz)
   docker exec -i site_kapi_kontrol_postgres psql -U postgres -c 'DROP DATABASE site_kapi_kontrol WITH (FORCE)'
   docker exec -i site_kapi_kontrol_postgres psql -U postgres -c 'CREATE DATABASE site_kapi_kontrol'
   # roller: yalnızca salihceylan rolünün satırlarını uygulayın (parola özeti DB_PASSWORD'ü yeniden kurar)
   grep -E '^(CREATE|ALTER) ROLE salihceylan' ~/kurtar/globals.sql | docker exec -i site_kapi_kontrol_postgres psql -U postgres -X -v ON_ERROR_STOP=1
   gzip -dc ~/kurtar/db.sql.gz | docker exec -i site_kapi_kontrol_postgres psql -U postgres -X -q -d site_kapi_kontrol -v ON_ERROR_STOP=0 2>~/restore.err
   grep -c 'ERROR:' ~/restore.err    # 0 olmalı
   ```
5. **Geri yükleme sonrası adımlar** (bölüm 5.7): `deleted_accounts.csv` içindeki hesapları yeniden kimliksizleştirin (liste en son yedek anına kadar olanları kapsar), e-posta kuyruğunu inceleyin.
6. **API**: `cd /var/www/site_kapi_kontrol/server && pm2 start ecosystem.config.cjs && pm2 save && pm2 startup` (başlatma komutunu `pm2 startup` yazdırır). `curl -s http://127.0.0.1:8080/health`.
7. **nginx + TLS**: `sudo cp ~/kurtar/api.gudeteknoloji.com.tr /etc/nginx/sites-available/` ve `sites-enabled` bağlantısı; içindeki `ssl_certificate` yolları eski sertifikaya işaret eder → önce geçici olarak yalnızca `listen 80` bloğuyla başlatıp `sudo certbot --nginx -d api.gudeteknoloji.com.tr` çalıştırın. DNS (`api...` → yeni IP) ve Cloudflare ayarlarını güncelleyin.
8. **MQTT (Mosquitto)**: yapılandırma yedeğindeki `mosquitto/` dizinindeki dosyaları `/etc/mosquitto/` altına, `kapi-mqtt-sync` dosyasını `/usr/local/bin/` altına (755) alın; sudoers kuralını yeniden tanımlayın (`salihceylan ALL=(root) NOPASSWD: /usr/local/bin/kapi-mqtt-sync`). Broker için TLS sertifikasını `mqtt.gudeteknoloji.com.tr` adına yeniden üretin (özel anahtarlar yedeğe alınmaz), Mosquitto'yu yeniden başlatın ve **parola/ACL dosyalarını veritabanından yeniden üretmek için** `sudo -n /usr/local/bin/kapi-mqtt-sync` çalıştırın (ayrıntı: depodaki `MQTT_kurulum.txt`).
9. **Ops araçlarını yeniden kur**: `scp deploy/ops/* ...`; **önce eski anahtarı** `~/.config/kapi-backup.key` olarak (izin 600) geri koyun, **sonra** `bash ~/ops/install_ops.sh` çalıştırın (aksi halde yeni anahtar üretilir; yedekler farklı anahtarla şifrelenir).
10. **Doğrulama**: uygulamadan giriş yapın; `bash ~/ops/restore_test.sh`; `bash ~/ops/healthcheck.sh --dry-run -v`.

### 5.6 Hesap silme ve yedekler: silinmiş hesaplar geri gelmesin

Hesap silme (kimliksizleştirme) canlıda yapılır; yedekten dönüşte, yedek anından **sonra** silinmiş hesaplar **eski kimlikli hâlleriyle geri gelir**. Bunu önlemek için silme kayıtları (`audit_log`, `action = 'account.deleted'`, `target_id = user_code`) kullanılır; bu kayıtlarda kişisel veri yoktur.

- **Yedekler, silinen hesap listesini her gece taşır:** `kapi_config_<TS>.tgz.enc` içindeki `deleted_accounts.csv` (`user_code,deleted_at_utc`). Senaryo C'de (canlı veritabanı yok) bu dosya tek kaynaktır; liste yalnızca **o yedek anına kadar** olan silmeleri kapsar (sonrası bilinemez; hesap sahipleri bu aralıkta tekrar silme talep etmeli).
- **Senaryo A/B'de:** geri yüklemeden **ÖNCE** canlıdan listeyi çıkarın (bölüm 5.4 adım 0 bunu yapar: `~/silinen_hesaplar_oncesi.csv`). Canlı veritabanı kullanılamıyorsa en yeni `deleted_accounts.csv` yeter.

### 5.7 Geri yükleme sonrası adımlar (API'yi başlatmadan ÖNCE)

1. **Silinmiş hesapları yeniden kimliksizleştir [denenmedi; hesap silme migration'ı 036 henüz canlıda değil]:** listedeki her `user_code` için, geri yüklenen veritabanında hâlâ kimlikli olanları bulun:
   ```bash
   docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -Atc \
     "select user_code from users where user_code in (1001,1002) and email not like '%@deleted.invalid'"
   ```
   ve silme servisini aynı kullanıcılar için yeniden çalıştırın (tek işlemde kimliksizleştirir; listelenen kodları yazın):
   ```bash
   cd /var/www/site_kapi_kontrol/server
   node --input-type=module -e "
   const m = await import('./src/modules/account_deletion_service.js');
   for (const c of process.argv.slice(1).map(Number)) {
     try { await m.performAccountDeletion(c); console.log('silindi', c); }
     catch (e) { console.log('ATLANDI/HATA', c, e?.code || e?.name || 'hata'); }
   }
   process.exit(0);" 1001 1002
   ```
   Not: bu çağrı yalnızca kimliksizleştirmeyi uygular; silme isteği akışındaki ek işleri (eski adrese bilgilendirme e-postası, yerel kontrol belirteçlerinin döndürülmesi) **yapmaz**. İlgili sitelerin belirteçlerinin döndürülmesi gerekirse süper kullanıcı/site yöneticisi yolundan yapın.
2. **MQTT kimlik bilgileri ve ACL:** veritabanı geri yüklendiği için broker tarafındaki dosyalar eski kalmış olabilir: `sudo -n /usr/local/bin/kapi-mqtt-sync` (parola/ACL dosyalarını veritabanından üretir ve Mosquitto'yu yeniden yükler).
3. **E-posta kuyruğunu incele:** geri yüklenen `announcement_recipients` tablosundaki bekleyen satırlar (`email_status = 'pending'`) yedek anından sonra zaten gönderilmiş olabilir (tekrar gönderim) ya da silinmiş hesaplara ait olabilir. API'yi başlatmadan önce sayıyı ve yaşı inceleyin:
   ```bash
   docker exec -i site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c \
     "select email_status, count(*) from announcement_recipients group by 1 order by 1"
   ```
   Tekrar gönderim istemiyorsanız ilgili duyuruların bekleyen satırlarını bilinçli olarak kapatmayı değerlendirin (karar ve SQL sizindir; hesaplar adım 1'den **sonra** değerlendirilmelidir, çünkü silme servisi silinen hesapların bekleyen satırlarını kapatır).
4. Yeni oluşturulmuş ama yedekte olmayan hesaplar/oturumlar kaybolur; kullanıcılara duyuru gerekebilir.

### 5.8 Sorun giderme

| Belirti | Neden / çözüm |
|---|---|
| `bad decrypt` | Büyük olasılıkla yanlış anahtar. Parmak izini (bölüm 3) karşılaştırın; eski bir yedek için eski anahtarı deneyin. Hata vermeyen ama `gzip -t` / `tar -t` ile doğrulanamayan çıktı da yanlış anahtar belirtisidir (bölüm 5.2). |
| `gzip: unexpected end of file` | Dosya kesik. Önceki günlük/haftalık/aylık yedeği veya dış kopyayı deneyin; `sha256sum -c` ile karşılaştırın. |
| Yüklemede `ERROR: role "salihceylan" does not exist` | Rolü oluşturun (bölüm 5.5 adım 4) ve yeniden yükleyin. |
| Yüklemede `already exists` hataları | Dolu bir veritabanına yüklüyorsunuz; `DROP DATABASE ... WITH (FORCE)` + `CREATE DATABASE` ile boşaltın. |
| `\restrict` ile ilgili hata | `psql` sürümünüz eski; kapsayıcıdaki `psql` (16.13) ile yükleyin. |
| `restore_test.sh`: "yedek dosyasi REDDEDILDI" | Dosya `\connect` / `DROP|CREATE|ALTER DATABASE` / `\!` gibi satırlar içeriyor: bu bir `pg_dump -C` / `pg_dumpall` çıktısı ya da kurcalanmış bir dosyadır. Bu betikle yüklemeyin. |
| `restore_test.sh` FAIL: "kritik tablo yedekte boş" | Yedek yapısal olarak sağlam ama veri yok: en son iyi yedeğe (weekly/monthly) bakın, `backup.log` ve `pg_dump` hatasını inceleyin, hemen elle yedek alın. |
| `restore_test.sh` "ATLANDI: baska bir ops isi calisiyor" | Yedek/dış kopya çalışıyor; kilit 15 dk sonra bırakılır. Tekrar deneyin. |
| Yedek durumu FAIL: "sifreleme anahtari DEGISMIS" | Anahtar dosyası kayıtlı parmak iziyle uyuşmuyor. Doğru anahtarı geri koyun; bilerek değiştirdiyseniz `install_ops.sh --accept-new-key` (eski anahtarı saklayın). |

---

## 6. Dış kopya: seçenekler ve karar

Kural: **yedek yalnızca aynı sunucuda durursa sunucuyla birlikte kaybolur.** `offsite_push.sh` dış hedefe **yalnızca şifreli** (`Salted__` başlığı doğrulanan `.enc`) dosyaları gönderir; hedef ele geçirilse bile içerik anahtarsız okunamaz. Veri küçüktür (günde ≈ 130 KB; firmware arşivi yalnızca değişince ≈ 3 MB), bu yüzden ücretsiz kotalar yeter.

**Saklama kuralı (gizlilik metniyle uyumlu): dış kopyalar en çok ~210 gün tutulur.**
- Yerel Windows kopyası: `pull_backups_windows.ps1 -PruneDays 210` (varsayılan; 0 = hiç silme).
- rsync / rclone hedefi: `offsite_push.sh` başarılı gönderimden sonra uzaktaki 210 günden eski günlük-veritabanı ve yapılandırma dosyalarını siler (`OFFSITE_PRUNE_DAYS`, varsayılan 210, 0 = kapalı). Yerel dizin hedefiyle [doğrulandı]; ssh üzerinden `find -delete` ve `rclone delete --min-age` yolları [denenmedi].
- **sftp-only hedefte uzak silme yapılamaz**: eski dosyaları hedefte elle silin (ya da rsync/rclone kullanın).
- Firmware arşivleri (`kapi_firmware_*`) yaşa göre silinmez (değişmedikçe tek yedek kopyadır).
- Bu süre, yerel tutma ile de uyumludur (günlük 14 gün, haftalık ≈ 56 gün, aylık ≈ 6 ay).

| Seçenek | Maliyet | Artı | Eksi | Kurulum |
|---|---|---|---|---|
| **A. Kendi bilgisayarınıza çekme** (Windows görev zamanlayıcı + `scp`) | Ücretsiz | Ek hesap yok; veri sizde; sunucuda ek yazılım yok; çalıştığı test edildi | Bilgisayar açık/ağda olmalı; tek fiziksel konum (yangın/hırsızlık/disk arızası) | Bölüm 7 |
| **B. İkinci bir sunucuya `rsync` (ssh)**: ucuz VPS veya "storage box" tipi hizmet | ≈ 3–5 €/ay (fiyatlar değişir, doğrulayın) | Otomatik, 7/24; farklı veri merkezi; `rsync` doğrulaması ve uzak budama dahil | Aylık ücret + ek bir sunucuyu yönetme; ssh anahtarı yetkilendirmesi | `OFFSITE_METHOD=rsync` |
| **C. Bulut nesne depolama + `rclone`**: Cloudflare R2 veya Backblaze B2 (küçük veri için ücretsiz katman yeter; güncel kotaları doğrulayın) | Bu veri boyutunda ≈ ücretsiz | Dayanıklı, sunucu yönetimi yok | `rclone` kurulumu gerekir (kök gerektirmeden `~/bin/rclone` olarak tek ikili dosya yeter; `PATH`'te `~/bin` ve `~/.local/bin` vardır); API anahtarı sunucuda durur | `OFFSITE_METHOD=rclone` |
| **D. Google Drive / OneDrive (`rclone` ile)** | Ücretsiz katman | Zaten hesabınız var | OAuth belirteci süresi dolabilir; ilk kimlik doğrulama tarayıcı gerektirir; kişisel hesaba bağımlılık | `OFFSITE_METHOD=rclone` |

**Öneri (iki katman):** hemen **A** (ücretsiz, bugün kurulur) + kısa sürede **C**. Böylece biri bozulsa diğeri kalır. Karar sizindir; hiçbir hedef şu an yapılandırılmadı.

### 6.1 Hedef yapılandırma (sunucuda)

`~/.config/kapi-offsite.env` oluşturun (`chmod 600`; örnek: `deploy/ops/kapi-offsite.env.example`).

**B (rsync/ssh):**
```
OFFSITE_METHOD=rsync
OFFSITE_TARGET=yedek@yedek-sunucusu.example.com:/yedekler/kapi
OFFSITE_SSH_PORT=22
OFFSITE_SSH_KEY=/home/salihceylan/.ssh/kapi_offsite
OFFSITE_PRUNE_DAYS=210
```
Kurulum: `ssh-keygen -t ed25519 -N '' -f ~/.ssh/kapi_offsite` (sunucuda), `~/.ssh/kapi_offsite.pub` içeriğini hedef sunucunun `authorized_keys` dosyasına ekleyin (mümkünse yalnızca `rsync` komutuna ve o dizine kısıtlayın), bir kez elle bağlanıp parmak izini onaylayın, sonra `bash ~/ops/offsite_push.sh --check`.

**C/D (rclone):**
```
OFFSITE_METHOD=rclone
OFFSITE_TARGET=r2:kapi-yedek
OFFSITE_PRUNE_DAYS=210
```
`rclone config` ile `r2` (veya `b2`, `drive`) uzak ucunu tanımlayın (R2/B2 için yalnızca o kovaya erişimi olan bir API anahtarı oluşturun; yönetici anahtarı kullanmayın). `rclone` yalnızca doğrulanmış (`Salted__`) dosya listesini gönderir (`--files-from`). `bash ~/ops/offsite_push.sh --check`.

Her iki durumda ilk gönderim: `bash ~/ops/offsite_push.sh --all`. Sonra cron (03:50 İstanbul) her gece yalnızca yeni dosyaları gönderir ve gönderimi doğrular (rsync: sağlama toplamlı ikinci geçiş; rclone: `rclone check`). Başarısızlıkta e-posta gider; `healthcheck.sh` 26 saatten uzun süre gönderim olmazsa uyarır. Yapılandırma dosyası yokken izleme "dış kopya yapılandırılmadı" uyarısını 24 saatte bir hatırlatır.

**[doğrulandı]** `rsync` yöntemi yerel bir hedef dizinle (ssh'siz) sınandı: yalnızca şifreli dosyalar gitti, düz metin `.enc` adlı dosya reddedildi, ikinci çalışma "yeni dosya yok" dedi, bozulmuş hedef dosya yeniden gönderilip düzeltildi, 210 günden eski kayıtlar silindi (firmware ve başka adlı dosyalar silinmedi), ulaşılamayan hedefte FAIL + e-posta denemesi çalıştı. `ssh` üzerinden rsync, `sftp` ve `rclone` yolları gerçek hedefle [denenmedi].

---

## 7. Windows tarafı: yedekleri bilgisayarınıza çekme

`deploy/ops/pull_backups_windows.ps1` yalnızca OpenSSH istemcisi (`ssh.exe`, `scp.exe`; Windows 11'de yerleşik) kullanır. Sunucudan `~/backups/scheduled/offsite/` içindeki **şifreli** dosyaları indirir, "Salted__" başlığını ve sunucudaki SHA-256 değerini doğrular (ssh uyarıları ayrıştırmaya karışmaz), var olanları yeniden indirmez. Sunucuya yazmaz, silmez. **[doğrulandı]** 2026-10-16 (dosyalar indirildi, özetler eşleşti, ikinci çalışma 0 yeni dosya).

1. Sunucuya parolasız bağlanabildiğinizi doğrulayın: `ssh -p 22667 -o BatchMode=yes salihceylan@<sunucu> echo tamam`. Başarılıysa anahtar zaten hazırdır. (Özel bir anahtar kullanacaksanız betiği `-KeyPath C:\Users\<siz>\.ssh\anahtar` ile çalıştırın.)
2. Betiği sabit bir yere kopyalayın, örn. `C:\kapi-ops\pull_backups_windows.ps1`.
3. Elle deneyin:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\kapi-ops\pull_backups_windows.ps1 -ListOnly
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\kapi-ops\pull_backups_windows.ps1
   ```
   Varsayılan hedef klasör `%USERPROFILE%\kapi-yedek`; günlük `pull.log`, son durum `LAST_OK.txt` / `LAST_FAILED.txt`.
4. Zamanlanmış görev (**siz kurun**; ben kurmadım). Yönetici olmayan PowerShell'de:
   ```powershell
   $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\kapi-ops\pull_backups_windows.ps1"'
   $trigger  = New-ScheduledTaskTrigger -Daily -At 11:00
   $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
   Register-ScheduledTask -TaskName 'KapiYedekCek' -Action $action -Trigger $trigger -Settings $settings -Description 'Kapi sunucu sifreli yedeklerini ceker'
   ```
   `-StartWhenAvailable` bilgisayar o saatte kapalıysa açıldığında çalıştırır. Görev Zamanlayıcı'da "Son çalıştırma sonucu" `0x0` olmalı; 1 ise `pull.log` dosyasına bakın.
5. **Saklama:** `-PruneDays` varsayılanı **210** gündür (yerel dosyalar bu yaştan sonra silinir; firmware arşivleri silinmez); hiç silmek istemezseniz `-PruneDays 0`.
6. Anahtar: bölüm 3 (`-FetchKey`, tek seferlik, yedek klasörünün dışına iner).
7. Bu klasörü OneDrive vb. bir eşitlemeye dahil etmek ek bir dış kopya katmanı sağlar (dosyalar şifrelidir), ancak **anahtarı** asla eşitlenen bir klasöre koymayın ve eşitleme de 210 gün kuralına tabidir.

---

## 8. İzleme ve uyarılar

`healthcheck.sh` her 5 dakikada çalışır. Kontroller ve eşikler:

| Kontrol | Ne bakılır | Uyarı |
|---|---|---|
| `api` | yerel sağlık ucu → `ok:true` ve `database:connected` | CRIT (2 ardışık başarısızlıktan sonra) |
| `mqtt_bridge` | `/health` içinde API'nin MQTT köprüsü bağlı mı | WARN |
| `api_public` | genel adres sağlık ucu (nginx + Cloudflare dahil) | CRIT |
| `pm2` | `kapi-api` `online` (CRIT için 2 ardışık); kararsız yeniden başlama | CRIT/WARN |
| `pm2_restart` | Yeniden başlama sayacı arttı. **Tek başına posta üretmez** (normal dağıtım); son 60 dk'da ≥ 3 yeniden başlama varsa OLAY postası (olaylar arası ≥ 30 dk) | OLAY |
| `pm2_loop` | Son 60 dk'da ≥ 6 yeniden başlama (çökme döngüsü); varken ayrıca OLAY üretilmez | CRIT |
| `postgres` | Kapsayıcı çalışıyor + `select 1` 20 sn içinde yanıt; bağlantı sayısı < %80 (`docker` çağrıları zaman aşımlı) | CRIT/WARN |
| `disk` | `/` doluluk ≥ %85 WARN, ≥ %95 CRIT; inode ≥ %90 | |
| `memory` | Kullanılabilir bellek < %10 WARN, < %5 CRIT; takas ≥ %80 | |
| `backup_age` | Son günlük yedek < 26 saat (gelecek tarihli dosyalar sayılmaz) | CRIT |
| `backup_run` | Son yedek çalışması başarılı mı | CRIT/WARN |
| `backup_key` | Şifreleme anahtarı var mı ve kayıtlı parmak iziyle aynı mı | CRIT |
| `restore_test` | Geri yükleme testi hiç çalışmadı / FAIL / 40 günden eski | WARN/CRIT |
| `offsite` | Dış kopya yapılandırılmadı / başarısız / 26 saatten eski | WARN/CRIT |
| `tls_origin` | nginx (Let's Encrypt) sertifikası: < 14 gün WARN, < 7 gün CRIT | |
| `tls_edge` | Genel (Cloudflare kenar) sertifika | |
| `tls_mqtt` | MQTT 8883 sertifikası: < 21 gün WARN, < 7 gün CRIT | |
| `mqtt_local` | `127.0.0.1:8883` TCP | CRIT |
| `mqtt_public` | MQTT genel adresi dışarıdan erişilebilir mi | WARN |

**Uyarı tekilleştirme:** bir sorun için (a) geçici kesintilere karşı çoğu kontrolde 2 ardışık başarısızlık (≈ 10 dk) sonrası **tek bir e-posta**, (b) seviye değişince (WARN↔CRIT) hemen, (c) değişmediyse **6 saatte bir** hatırlatma (yapılandırma eksikleri, MQTT genel adresi ve sertifika yaklaşması için 24 saatte bir), (d) **"düzeldi" postası ancak art arda 2 başarılı çalışmadan sonra** (titreşen sorunlarda posta yağmuru olmaz). Durum `~/ops/state/health.state` dosyasındadır; alanlar doğrulanır, bozuk satır betiği çökertmez, yazım hatası günlüğe düşer ve ölü adam anahtarı gitmez.

**[doğrulandı]** (yalıtılmış düzenekte, sahte e-posta göndericiyle): 1. başarısızlıkta sessizlik, 2.'de "SORUN", 1 temiz çalışmada sessizlik, tekrar bozulmada ek posta yok, 2 temiz çalışmadan sonra "DÜZELDİ"; yeniden başlama sayacı artışı son 60 dk'da <3 ise yalnızca günlük, 3–5 ise OLAY, ≥ 6 ise `pm2_loop` CRIT ve OLAY yok; 30 dk içinde ikinci olay bastırılır; `--test-alert` sayaç/durum dosyalarını değiştirmez; bozuk durum dosyası çökertmez.

**E-posta kanalı:** sunucunun mevcut SMTP ayarı (`server/.env` içindeki `SMTP_*`; değerler yazdırılmaz), alıcı = canlı veritabanındaki aktif `super_user` hesapların e-postaları (şu an 1 alıcı). Alıcı ve konu **komut satırında değil ortam değişkeniyle** geçer (`ps` çıktısında görünmez). Geçersiz kılmak için `~/.config/kapi-ops.env` içine `ALERT_EMAIL=ben@example.com,ortak@example.com` yazın. Alıcı listesi veritabanı kapalıyken de çalışsın diye `~/ops/state/recipients` içinde önbelleğe alınır.

**E-posta gönderilemezse:** uyarı `~/ops/logs/alerts.log` içine yazılır, `~/ops/state/ALERT_UNSENT` bayrak dosyası oluşur (içinde son uyarı metni), 30 dakika boyunca yeniden denenmez. **[doğrulandı]**

**Komutlar:**
```bash
bash ~/ops/healthcheck.sh --dry-run -v     # kontrolleri yap, yazdır; e-posta YOK, durum ve sayaç dosyaları değişmez
bash ~/ops/healthcheck.sh --test-alert     # alıcılara test e-postası gönder (TEST_ALERT_SENT / TEST_ALERT_FAILED)
tail -n 50 ~/ops/logs/healthcheck.log      # son olaylar
cat ~/ops/state/health.state               # kontrol|seviye|başlangıç|ardışık|bildirildi|son_bildirim|ardışık_ok
```

Eşikleri değiştirmek: `~/.config/kapi-ops.env` (anahtarlar `kapi-ops.env.example` içinde). Örn. `CHECK_MQTT_PUBLIC=0` genel MQTT adres kontrolünü kapatır.

---

## 9. Sunucu dışı izleme (VPS çökerse)

Sunucu içi izleme, sunucu tamamen kapalıysa e-posta gönderemez. Bu yüzden bağımsız dış izleme önerilir.

### 9.1 GitHub Actions: `.github/workflows/uptime.yml` (hazır, push sizde)

Her 30 dakikada (dakika 7 ve 37) sağlık ucunu 3 denemeyle (20 sn arayla) çağırır; `ok:true` ve `database:connected` yoksa iş **başarısız** sayılır ve GitHub size e-posta atar. Betik adımı yerelde sınandı (başarı ve başarısızlık yolu) [doğrulandı]; GitHub üzerindeki çalışması [denenmedi] (depo push edilmedi).

Yapılacaklar:
1. Dosyayı `main` dalına push edin (zamanlanmış işler yalnızca varsayılan daldan çalışır).
2. Actions sekmesi → "Uptime" → **Run workflow** ile bir kez elle çalıştırın, yeşil olduğunu doğrulayın. Cloudflare GitHub IP'lerine 403 (bot doğrulaması) dönerse çıktıda `HTTP 403` görürsünüz; bu durumda Cloudflare'da `/health` yolu için bir WAF "skip" kuralı ekleyin veya 9.2–9.3'e güvenin.
3. GitHub → Settings → Notifications → "Actions" bölümünde başarısız çalışmalar için e-postayı açın.
4. Kota: bir çalışma dakikaya yuvarlanır → 48/gün ≈ 1440 dk/ay. Genel (public) depoda sınırsız ücretsiz; özel depoda ücretsiz plan 2000 dk/ay ve `ci.yml` aynı kotayı yer. Kota daralırsa cron'u saatliğe çevirin (`"17 * * * *"` → ≈ 720 dk/ay).
5. Zamanlanmış çalışmalar kesin zamanlı değildir (yoğunlukta gecikebilir); GitHub, 60 gün etkinlik olmayan genel depolarda zamanlamayı durdurur.

### 9.2 Ölü adam anahtarı (heartbeat): `HEARTBEAT_URL` — sunucu *ya da izleme betiği* öldü mü?

`healthcheck.sh` her **başarıyla tamamlanan** çalışmasının sonunda (sorun bulunsa bile; kendisi çalıştı demektir) `~/.config/kapi-ops.env` içindeki `HEARTBEAT_URL` adresine `curl -fsS -m 10` ile GET atar. Beklenen aralıkta ping gelmezse heartbeat hizmeti sizi uyarır: sunucu çökse, cron durmuş olsa ya da betik bozulsa içeriden e-posta gelemeyeceği halde bu yöntem haber verir. Tanımsızsa sessizdir; adres (gizli bir anahtar içerir) günlüklere yazılmaz. Durum dosyası yazılamazsa ping gitmez (bilinçli: izleme bozuk demektir). Yerel sağlık ucuna GET ile başarılı ping, hatalı adreste "heartbeat gonderilemedi" ve adresin günlüğe yazılmadığı [doğrulandı]; gerçek bir heartbeat hizmetiyle [denenmedi].

Kurulum (healthchecks.io örneği; UptimeRobot "Heartbeat" monitörü de aynıdır — güncel ücretsiz plan koşullarını kayıt sırasında doğrulayın):
1. https://healthchecks.io → hesap açın → **Add Check**: ad `kapi healthcheck`, **Period 5 minutes**, **Grace Time 10 minutes** (iki kaçırılmış ping = alarm).
2. Entegrasyonlar bölümünden e-posta (isteğe bağlı Telegram/SMS) ekleyin.
3. Check'in **ping URL**'sini kopyalayın (örn. `https://hc-ping.com/<uuid>`).
4. Sunucuda: `umask 077; printf 'HEARTBEAT_URL=%s\n' 'https://hc-ping.com/<uuid>' >> ~/.config/kapi-ops.env; chmod 600 ~/.config/kapi-ops.env`.
5. 5 dakika içinde panelde ilk ping görünmeli (ya da `bash ~/ops/healthcheck.sh` çalıştırın). Test: cron satırını geçici olarak kapatıp (`crontab -e`) 15 dakika sonra alarm gelmesini bekleyebilirsiniz; ardından geri açın.

### 9.3 Ücretsiz harici izleme (kullanıcı eylemi, 5 dk)

Tercih: **UptimeRobot** (ücretsiz planı e-posta uyarısı ve dakikalar mertebesinde kontrol aralığı sunar; plan limitlerini ve ticari kullanım koşullarını kayıt sırasında kontrol edin).

1. https://uptimerobot.com → hesap açın → **Add New Monitor**.
2. Monitor 1: tür **HTTP(s)** (anahtar sözcük): URL `https://api.gudeteknoloji.com.tr/health`, anahtar sözcük `"ok":true` ("Alert when keyword *does not exist*"), aralık 5 dk.
3. Monitor 2 (isteğe bağlı): tür **Port**, sunucu IP'si, port `8883` (MQTT TCP; Cloudflare'dan geçmediği için IP ile).
4. Monitor 3 (isteğe bağlı): **SSL expiry** / "Domain/SSL" uyarısı açın.
5. Uyarı iletişimi: e-posta + (isteğe bağlı) Telegram/Webhook.

Alternatifler: Better Stack (Better Uptime) ücretsiz planı, Cronitor, Healthchecks.io. Hepsi aynı mantıkla çalışır.

---

## 10. PM2 günlük döngüsü

Bulgu: `~/.pm2/logs/kapi-api-out.log` (≈ 1,6 MB) ve `kapi-api-error.log` (≈ 0,6 MB) **hiç dönmüyordu**. Çözüm: kullanıcı düzeyinde `logrotate` (`~/ops/logrotate_pm2.sh`, günlük 04:05 İstanbul): haftalık veya 20 MB aşınca döner, 8 eski dosya tutar, sıkıştırır, `copytruncate` kullanır; tarih eki saniyeyi içerir (aynı gün iki kez dönme çakışması olmaz).

Neden bu yol (en düşük risk): `pm2-logrotate` modülü PM2 daemon'una yeni bir süreç ekler ve **tüm** uygulamaların günlüklerini etkiler; `copytruncate` ise `kapi-api`'ye sinyal göndermez, onu yeniden başlatmaz ve yalnızca `kapi-api-*.log` dosyalarına dokunur. **Etki kanıtı [doğrulandı]:** (1) PM2 daemon'u bu dosyaları `O_APPEND` bayrağıyla açık tutuyor ve uygulama çıktısı soket üzerinden daemon'a gidiyor; (2) aynı kipte açık bir deneme dosyasına yazan sürece `logrotate -f` uygulandı: yazıcı süreç aynı PID ile yaşamaya devam etti, 160/160 satır korundu, sıra boşluğu ve NUL bayt yok; (3) gerçek yapılandırma `logrotate -d` ile kuru çalıştırıldı. `kapi-api` PID'si ve çalışma süresi değişmedi.

Başka projelerin PM2 günlükleri bu kuralın dışındadır; sahipleri kendi döngülerini kurmalıdır.

---

## 11. Açık işler ve kullanıcı eylemleri

1. **Anahtar kopyası** (bölüm 3) ve **dış kopya hedefi seçimi** (bölüm 6).
2. **Heartbeat ve harici izleme** kurulumu (bölüm 9.2–9.3) ve `uptime.yml` dosyasının push edilmesi (9.1).
3. **Windows zamanlanmış görevi** (bölüm 7).
4. **Elle yedek klasörlerinin temizliği** kararı (bölüm 4.1).
5. MQTT güvenlik ve sertifika yapılandırması ayrıca gözden geçirilecek (ayrıntılar bu belgede tutulmaz; ayrı iletildi). İzleme bu alandaki sertifika bitişini ve erişilebilirliği denetler.
6. Süreç yönetimi (PM2) tanımının depodaki `ecosystem.config.cjs` ile hizalanması planlı bir bakımda değerlendirilecek (ayrıntı ayrı notta).
7. Aylık geri yükleme provasının yeni sürümünün (düz + şifreli kopya) canlıda ilk tam çalışması 2026-11-02 01:15 UTC'de olacak; önceden elle çalıştırmak isterseniz bölüm 5.1.

---

## 12. `kapi-api` yeniden başlama sayacı (≈ 891) araştırması

Kaynak: PM2 daemon günlüğü (2026-03-10'dan beri) ve `~/.pm2/logs/kapi-api-error.log`. Kişisel veri/sır yazılmadı.

- Toplam ≈ 923 başlatma kaydı (sayaç 891; sayaç bir noktada sıfırlanmış olabilir). Bunlardan **206'sı bilinçli** (`pm2 restart` / dağıtım; çıkış kodu 0), **717'si çökme** (çıkış kodu 1).
- Çökmelerin **tamamı açılışta** olan "bozuk dağıtım" döngüleridir (süreç kalkamadan ölüyor), çalışırken rastgele çökme değil:
  | Tarih (UTC) | Çökme | Neden | Süre |
  |---|---|---|---|
  | 2026-09-03 14:14–15:10 | **632** | `ReferenceError: __dirname is not defined in ES module scope` (`server.js`, `qrcodesRoot`) | ≈ 56 dk; düzeltici bir dağıtımla bitmiş görünüyor |
  | 2026-09-17 07:11–07:12 | 27 | `SyntaxError: Identifier 'triggerType' has already been declared` (`app_doors_routes.js`) | 24 sn |
  | 2026-08-31 19:42 | 22 | neden kayıtlı değil (günlük dosyasında karşılığı yok) | 36 sn |
  | 2026-09-11 18:42 | 17 | `SyntaxError: Identifier 'match' has already been declared` (günlük sırasından eşleştirildi) | 12 sn |
  | 2026-09-13 17:51 | 17 | `SyntaxError: Unexpected token ')'` (16) / `Invalid or unexpected token` (1) (günlük sırasından eşleştirildi) | 14 sn |
  | 2026-03-10 ve 2026-08-28 | 1 + 1 | Günlükte kalan iki tek seferlik çalışma zamanı çökmesi, büyük olasılıkla bunlar: `TypeError: ….trim().isNotEmpty is not a function` (`server.js:2093` hata işleyicisinde Dart sözdizimi) ve `error: terminating connection due to administrator command` (veritabanı kapsayıcısı yeniden başlatılınca boşta bekleyen havuz bağlantısının hatası, o zaman işlenmiyordu) | — |
- **2026-09-17'den sonra hiç çökme yok** (29 gün; 09-18 ve sonrası çıkış kodu 1 = 0).
- Geçerli kodda `isNotEmpty()` kalmadı ve `db.js` içinde `pool.on('error', ...)` var (iki çalışma zamanı çökmesinin nedenleri giderilmiş görünüyor).
- Çökme döngülerinin ortak paydası: dağıtımdan sonra açılışı doğrulayan bir kapı olmaması. Mevcut `remote_deploy.sh activate` zaten `/health` bekleyip otomatik geri alıyor; eski olaylar bundan öncesine ait olabilir. Dağıtım öncesi `node --check` aşaması (`prepare`) bu hata sınıfını yakalar.
- Ek iki küçük gözlem (hata değil): `kapi-api-error.log` içinde 40 adet pg uyarısı `Calling client.query() when the client is already executing a query is deprecated` (konumlar `routes/admin_routes.js:348` ve `mqtt_bridge.js:414`; pg 9'da hataya dönüşecek) ve 6 adet `CORS origin not allowed`.
- **İzleme:** `pm2_restart` (olay) ve `pm2_loop` (≥ 6/saat) kontrolleri bundan sonrasını yakalar.

---

## 13. Özet komutlar

```bash
ssh -p 22667 salihceylan@<sunucu>
bash ~/ops/healthcheck.sh --dry-run -v        # anlık durum (e-posta yok)
bash ~/ops/healthcheck.sh --test-alert        # test e-postası
bash ~/ops/backup_db.sh                       # elle yedek
bash ~/ops/restore_test.sh                    # geri yükleme kanıtı (düz + şifreli kopya)
bash ~/ops/offsite_push.sh --check            # dış kopya bağlantı denemesi
bash ~/ops/offsite_push.sh --all              # hepsini (yeniden) gönder
bash ~/ops/logrotate_pm2.sh --debug           # PM2 günlük döngüsü kuru çalıştırma
bash ~/ops/install_ops.sh --no-cron           # parmak izi/dizin/sözdizimi kontrolü, crontab'a dokunmaz
cat ~/ops/state/backup.status ~/ops/state/restore_test.status ~/ops/state/offsite.status
ls -la ~/backups/scheduled/daily ~/backups/scheduled/offsite
crontab -l
```

Dağıtım sonrası doğrulama listesine eklenecek: `bash ~/ops/healthcheck.sh --dry-run -v` (hepsi OK, yalnızca bilinen WARN'lar).
