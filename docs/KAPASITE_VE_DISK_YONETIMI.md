# Kapasite ve Disk Yönetimi

Durum: analiz belgesi (2026-10-18). Hiçbir kod, veritabanı veya sunucu ayarı değiştirilmedi. Sayıların kaynağı her yerde işaretlidir:
**[Ö]** canlıdan ölçüldü, **[K]** koddan okundu, **[T]** tahmin/varsayım (kesin değildir; ilk gerçek siteler gelince ölçülüp düzeltilmeli).

## 1. Kısa cevap

Evet, ölçek büyüyünce disk bir problem olur, ama bugün değil ve asıl yük beklenen yerden gelmiyor:

1. Veritabanının kendisi yönetilebilir boyutta kalır: 5.000 site için ilk yıl sonunda yaklaşık 40 GB, üç yılda yaklaşık 90 GB [T].
2. Asıl disk yiyen şey **yedek çoğaltması**: mevcut tutma kuralları diskte aynı veritabanının yaklaşık 42 sıkıştırılmış kopyasını bırakıyor; bu, veritabanı boyutunun yaklaşık 5 katı eder [K+T].
3. İkinci büyük kalem **belge deposu**: site başına 200 MB kota × site sayısı kuramsal tavanı verir (5.000 site = 1 TB), yedek betiği ise 3 GB'ın üstünde hata verir ve belge arşivinin yaklaşık 10 tam kopyasını diskte tutar [K].
4. Silinmeyen tablolar (makbuz, defter, duyuru alıcıları, denetim kaydı) yıllar içinde sessizce büyür; kapı geçiş kaydı ise sabit bir tavana oturur (30 gün).

## 2. Canlı taban ölçümü [Ö] (2026-10-18, salt okunur, tek seferlik)

| Kalem | Ölçülen |
|---|---|
| Kök disk | 49 GB toplam, 14 GB kullanılan (%29), 35 GB boş |
| Yedek dizini (toplam) | 102 MB; zamanlanmış günlük/haftalık/aylık kısmı 8,7 MB, kalanı tek seferlik dağıtım/silme öncesi yedekler |
| Belge deposu | 16 KB (fiilen boş) |
| PM2 günlükleri | 25 MB |
| mosquitto günlükleri | 0,7 MB |
| En büyük 15 tablo | Hepsi 1 MB'ın altında (en büyük `users` 664 kB; yaklaşık 1 site, 4 kullanıcı, 112 daire satırı) |
| Veri dışı taban yük | Yaklaşık 14 GB (işletim sistemi, kapsayıcı görüntüleri, bağımlılıklar); ayrıntısı ölçülmedi |

Sonuç: canlı veri bugün boyut tahmini için yetersiz; tablo boyutları sayfa/indeks taban maliyetiyle dolu. Bu yüzden satır başı bayt değerleri aşağıda **[T]**dir. İlk 5-10 gerçek site geldiğinde bölüm 6.6'daki haftalık rapordan gerçek bayt/satır çıkarılmalı.

## 3. Büyüme kaynakları ve mevcut mekanizmalar [K]

| Kaynak | Büyüme tipi | Mevcut saklama / temizlik | Durum |
|---|---|---|---|
| `door_access_logs` | Günlük, daire × 1,5 | 30 gün; `maintenance_service` başlangıçta ve 24 saatte bir tek `DELETE`; hesap silmede kimliksizleştirme | VAR (ölçekte bölümleme gerekir) |
| `device_connectivity_logs` | Cihaz olayı | 30 gün (aynı iş) | VAR |
| `qr_access_tokens`, `email_verifications`, `pending_registrations` | Kısa ömürlü | 1 gün / 2 gün / 2 gün (aynı iş) | VAR |
| `audit_log` | İşlem başına, yalnız ekleme | **Yok**; kodda ve testlerde "silinmez" değişmezi; yedek betiği silinmiş hesap listesini buradan üretir | EKSİK |
| `ledger_entries`, `receipts`, `receipt_print_events`, `late_fee_run_lines`, `expenses`, `account_*`, `receipt_counters` | Aylık, daire başına | Silme yok; `trg_finance_immutable` tetikleyicisi UPDATE/DELETE engeller (yalnız site silinmişse DELETE serbest) | Kasıtlı; arşiv stratejisi yok |
| `announcements`, `announcement_recipients`, `announcement_attachments` | Duyuru × kişi | Satır silinmez; `ANNOUNCEMENT_INBOX_RETENTION_DAYS` yalnız gelen kutusu görünürlüğünü sınırlar; e-posta adresi gönderim sonrası NULL yapılır | EKSİK (satır birikir) |
| `finance_reminder_runs`, `finance_reminder_items` | Aylık | Yalnız `finance_reminder_apartments` özetleri 8 gün; run/item silinmez | EKSİK |
| `push_outbox`, `push_devices` | Duyuru × kullanıcı (push şu an kapalı) | 14 gün (bekleyen hariç) / 60 gün hareketsizlik | VAR |
| `client_error_reports` | İstemci hatası | 90 gün + 20.000 satır tavanı, 6 saatte bir | VAR |
| `account_data_exports` | Talep | 7 gün | VAR |
| `bulk_import_runs`, `ota_update_jobs` (+ `_devices`), `guest_passes` | İşlem | Bakım işinde görünmüyor | EKSİK (küçük) |
| `users`, `site_people`, `vehicles`, üyelikler, `user_consents` | Kullanıcı sayısı | Hesap silmede silinir/kimliksizleşir; onay kaydı yasal ispat için kalır | VAR (kasıtlı) |
| Belge deposu | Yükleme | Dosya ≤ 10 MB (tavan 25 MB), site kotası 200 MB, site başına ≤ 2000 belge, boş disk ≥ 2 GiB koruması, silinen belge 30 gün sonra, yetim dosya 14 gün karantina (`document_maintenance`) | VAR; platform toplam tavanı ve alarmı yok |
| Yedekler (`deploy/ops/backup_db.sh`) | Günlük | 14 günlük + 8 haftalık + 6 aylık + dış kopya hazırlığı 14; yapılandırma/firmware/belge arşivi; disk ön kontrolü | VAR; ölçekte katlanıyor |
| PM2 günlükleri | Trafik | `logrotate_pm2.sh`: 20 MB'ta döndür, 8 yedek | VAR |
| mosquitto, nginx, Docker, journald | Trafik | Paket varsayılanı varsayılıyor; bu çalışmada doğrulanmadı | BELİRSİZ |
| OTA firmware | Sürüm başına 1-2 MB | Yedekte son 5 arşiv; depoda 5,3 MB | İhmal edilebilir |
| WAL / PITR | Yazma | Arşivleme yok (depoda PostgreSQL yapılandırması da yok); kurtarma noktası en kötü ~24 saat | EKSİK |

## 4. Kapasite modeli [T]

### 4.1 Varsayımlar

- Site başına ortalama 80 daire; kullanıcı = daire × 2,5; kişi (`site_people`) = daire × 2; kapı açma = daire × 1,5 / gün.
- Aylık aidat borçlandırma: daire başına 1 borç + 1 tahsilat + 0,5 diğer (gecikme, ters kayıt, ek ücret) = 2,5 defter satırı/ay; her tahsilata 1 makbuz; daire başına gecikme satırı oranı %15/ay.
- Duyuru: site başına ayda 3, tüm kişilere; denetim kaydı: site başına ayda 200 satır (finans işlemleri tek tek denetleniyorsa gerçek değer çok daha yüksek olabilir; EN BELİRSİZ KALEM).
- Tüm siteler yıl boyunca aktif (üst sınır). İndeks şişmesi payı %20. Sıkıştırılmış dökümün oranı veritabanı boyutunun %12'si (aralık %8-20).
- Beklenen belge kullanımı: site başına 20 MB (kotanın %10); tavan: 200 MB.

### 4.2 Satır başı bayt (yığın + indeksler) ve site başına yıllık hacim

| Tablo | Bayt/satır | Satır/site/yıl | MB/site/yıl | Tip |
|---|---|---|---|---|
| `receipts` (JSONB anlık görüntü ~1 KB, 6 indeks) | ~1.400 | 960 | 1,34 | Kalıcı |
| `ledger_entries` (9 indeks) | ~450 | 2.400 | 1,08 | Kalıcı |
| `announcement_recipients` (gönderim sonrası e-posta NULL) | ~150 | 5.760 | 0,86 | Kalıcı |
| `audit_log` (3 indeks, JSONB `details`) | ~350 | 2.400 | 0,84 | Kalıcı |
| `late_fee_run_lines` (JSONB döküm) | ~800 | 144 | 0,12 | Kalıcı |
| Diğer finans, hatırlatma, duyuru gövdesi, yazdırma olayı | karışık | - | ~0,25 | Kalıcı |
| **Kalıcı toplam** | | | **~4,5** | |
| `door_access_logs` (30 gün tavanı, 4 indeks) | ~330 | 3.600 (sabit) | ~1,2 | Sabit |
| Ana veri (kullanıcı, kişi, daire, araç, üyelik, onay) | karışık | - | ~0,6 | Sabit |
| Bağlantı günlüğü, push, hata raporu, diğer | karışık | - | ~0,2 | Sabit |

### 4.3 Senaryolar

| | 100 site | 1.000 site | 5.000 site |
|---|---|---|---|
| Daire / kullanıcı | 8 bin / 20 bin | 80 bin / 200 bin | 400 bin / 1 milyon |
| Kapı olayı / gün | 12 bin | 120 bin | 600 bin (ort. ~7/sn) |
| `door_access_logs` sabit boyut | 0,12 GB | 1,2 GB | 6 GB (18 milyon satır) |
| Veritabanı, yıl 1 sonu | 0,8 GB | 7,8 GB | 39 GB |
| Veritabanı, yıl 3 sonu | 1,9 GB | 18,6 GB | 93 GB |
| Kalıcı artış / yıl | 0,5 GB | 5,4 GB | 27 GB |
| Sıkıştırılmış döküm (yıl 1 / yıl 3) | 0,09 / 0,22 GB | 0,94 / 2,2 GB | 4,7 / 11 GB |
| Yerel yedek hacmi, DB dökümü × 42 kopya (yıl 1 / yıl 3) | 4 / 9 GB | 39 / 94 GB | 197 / 470 GB |
| Belge deposu, beklenen / kota tavanı | 2 / 20 GB | 20 / 200 GB | 100 / 1.000 GB |
| Belge arşivi yedeği (~10 tam kopya, beklenen) | 20 GB | 200 GB | 1.000 GB |
| Ham WAL (yalnız PITR açılırsa), günlük | <0,1 GB | 0,2-0,6 GB | 1-3 GB |
| PM2 günlük tavanı | ~0,4 GB (sabit; trafik artınca saklama süresi saatlere iner) | | |

Yorumlar:
- 42 kopya = 1 düz son günlük + 13 şifreli günlük + 14 dış kopya hazırlık dizini + 8 haftalık + 6 aylık [K]. Dış kopya hazırlık dizini günlükle aynı içeriği ikinci kez tutar.
- Yedek hacmi 1.000 sitede (yıl 1) bugünkü boş alanın (35 GB) üstüne çıkar. Mevcut disk için güvenli ölçek yaklaşık 300-500 site.
- Belge arşivi yedeği 3 GB sınırında (`DOCUMENTS_BACKUP_MAX_MB`) hata verir: site başına 20 MB ile yaklaşık 150 siteye karşılık gelir. Bu eşik, disk dolmadan önce yedeğin kırılacağı ilk noktadır.
- Sayılar tek kaynaklı bir tahmindir: en büyük belirsizlikler denetim kaydı hacmi, makbuz anlık görüntü boyutu ve belge kullanım oranıdır.

## 5. Eksik mekanizmalar (özet)

1. `audit_log`, `announcement_recipients`, `finance_reminder_*`, `bulk_import_runs`, `ota_update_*`, `guest_passes` için saklama/silme işi yok.
2. Kapı geçiş kaydı silme işi tek `DELETE` (toplu, kilitsiz, bölümsüz) ve ayrı bir eşzamanlılık kilidi yok.
3. Platform genelinde disk/büyüme/kota alarmı yok; `healthcheck.sh` yalnız disk yüzdesi (%85 uyarı / %95 kritik) ve inode bakıyor.
4. Belge deposunun toplam tavanı, site kotası doluluk görünürlüğü ve ücretli ek depolama yok.
5. Yedek: kopya sayısı veritabanı boyutuna göre uyarlanmıyor; belge yedeği tam arşiv (artımlı değil); WAL arşivi/PITR yok.
6. Docker, journald, nginx günlük sınırları doğrulanmadı.
7. Gereksiz indeks: `audit_log` içindeki `idx_audit_log_id (id DESC)` birincil anahtarla aynı işi görür [K].

## 6. Öneriler

### 6.1 Tablo bazında saklama politikası (öneri)

Hukuki süreler (vergi usul ve ticaret defteri süreleri, zamanaşımı, KVKK imha yükümlülüğü) için **hukuk danışmanı teyidi gerekir**; aşağıdakiler mühendislik varsayılanıdır.

| Tablo | Önerilen süre | Not |
|---|---|---|
| `door_access_logs`, `device_connectivity_logs` | 30 gün (mevcut) | Değiştirme; KVKK açısından kısa tutmak zaten avantaj |
| `client_error_reports`, `push_*`, `account_data_exports` | Mevcut | Değiştirme |
| `announcement_recipients` | Duyuru yaşı 24 ay | Okundu bilgisi kişisel veridir; silinince `announcements.recipient_count` kalır |
| `announcements` (+ ekler) | 5 yıl veya site silinene dek | Belge eki varsa belge süresiyle birlikte |
| `finance_reminder_runs/items` | 24 ay | E-posta alanları gönderim sonrası zaten NULL |
| `bulk_import_runs`, `ota_update_*`, `guest_passes` | 12-24 ay | Küçük tablolar; düzen için |
| `audit_log` | 24 ay sıcak; sonrası şifreli dışa aktarım + bölüm kaldırma | `account.deleted` satırları kalıcı kalmalı (yedek betiği silinmiş hesap listesini buradan okur): ayrı bir `deleted_accounts` tablosuna taşıyın. Değişmez kuralının ("yalnız eklenir") bilinçli olarak güncellenmesi gerekir |
| Finans (defter, makbuz, gider, hesap hareketi) | **Silme yok; en az yasal süre, öneri ≥ 10 yıl** | Tetikleyici kasıtlı. Büyümeyi bölümleme + soğuk arşiv ile yönetin, silerek değil |
| `user_consents` | Yasal ispat süresi (≥ 10 yıl önerilir) | Hesap silmede kimliksizleştirilmiş kalır |
| Yedekler | Mevcut (aylık 6, belge 210 gün) | KVKK silme taleplerinin yedeklerde ne kadar kalacağını belirler; gizlilik metninde yazılmalı |

### 6.2 Otomatik temizlik/arşiv işleri

- **Tek bir "saklama yürütücüsü"** (mevcut `client_error_purge` kalıbı): `pg_try_advisory_xact_lock` ile çoklu süreçte tek çalışan, gece düşük yükte, tablo başına ortam değişkeni (`*_RETENTION_DAYS`, 0 = kapalı).
- **Toplu ve idempotent silme**: `DELETE ... WHERE id IN (SELECT id ... WHERE tarih < eşik ORDER BY id LIMIT 5000)` döngüsü, partiler arası kısa bekleme, `statement_timeout`; zaman koşulu olduğu için yeniden çalıştırmak zararsız.
- Sonuç sayılarını `app_maintenance_runs` içine yazın; aşırı silme koruması: tek koşuda tablo satırının %10'undan fazlası silinecekse durdurup uyarın.
- Kapı geçiş kaydı için mevcut tek `DELETE` partili hale getirilsin (ölçekte günlük 600 bin satır tek ifadede uzun kilit/şişme yaratır).
- Finans arşivi (ileride): kapanmış dönemleri (`finance_period_closures`) 3 yıldan eski olan satırları ayrı soğuk bölüme/tablolara taşımak; tetikleyici DELETE'e izin vermediği için taşıma yerine **bölüm ayırma (DETACH)** tercih edilir.
- Belge deposu için mevcut `document_maintenance` yeterli; eklenecek: site silindiğinde dizin temizliğinin doğrulanması ve yetim karantinası sayıları için alarm.

### 6.3 PostgreSQL

| Konu | Öneri / eşik |
|---|---|
| Bölümleme | `door_access_logs` aylık (opened_at) ve `audit_log` aylık (created_at). Eşik: `door_access_logs` > 5 milyon satır veya günlük silme > 500 bin; `audit_log` > 20 milyon satır veya > 10 GB. Bölümlemeden önce çözülmesi gerekenler: birincil anahtar ve `idx_door_access_logs_client_log` benzersiz indeksi bölüm anahtarını içermeli (tekillik anlamı değişir), uygulama yazımları gözden geçirilmeli. Bölüm kaldırma `DELETE` yerine anlık ve şişmesiz |
| Autovacuum | Çok `DELETE` alan tablolarda (`door_access_logs`, `device_connectivity_logs`, `push_outbox`): `autovacuum_vacuum_scale_factor` 0,02, `autovacuum_vacuum_threshold` 10.000; `announcement_recipients` (gönderimde UPDATE) 0,05. Varsayılan %20 olduğunda 18 milyon satırlık tabloda 3,6 milyon ölü satır birikmeden temizlik başlamaz |
| İndeks | `audit_log.idx_audit_log_id` kaldırılabilir (birincil anahtar yeter). 30 gün sonra `pg_stat_user_indexes.idx_scan = 0` olanları gözden geçirin. Şişme > %30 ise `REINDEX CONCURRENTLY` |
| Tablo şişmesi | Önce bölüm kaldırma, sonra `pg_repack` (> 1 GB ve > %40 şişme; eklenti kapsayıcıda yüklü olmalı, ön doğrulama gerekir). `VACUUM FULL` canlıda kullanılmaz |
| Ayar kontrolü | PostgreSQL ayarları depoda yok; `shared_buffers`, `work_mem`, `max_wal_size`, `random_page_cost`, `log_min_duration_statement`, `pg_stat_statements` mevcut değerleri belgelenmeli |
| Bağlantı havuzu | Uygulama süreci başına `DB_POOL_MAX` varsayılan 12. Eşik: süreç sayısı × havuz > `max_connections`'ın %60'ı veya eşzamanlı istemci > ~300 → işlem modunda PgBouncer (oturum düzeyi kilit/LISTEN kullanılmadığı doğrulanmalı; mevcut kilitler işlem düzeyinde) |
| Ayrı DB sunucusu / okuma kopyası | Eşik: DB > 100 GB'a yaklaşırken ya da çalışma kümesi RAM'e sığmayınca (önbellek isabeti < %99), sürekli CPU > %60, p95 sorgu > 200 ms, döküm > 30 dk. İlk adım: DB'yi ayrı makineye taşıyıp akış kopyası kurmak; rapor/dışa aktarma sorgularını kopyaya yönlendirmek |

### 6.4 Dosya depolama (belgeler)

- **Nesne depolamaya (S3 uyumlu) geçiş ölçütleri**: belge deposu > 2 GB (yedek sınırına yaklaşım), disk kullanımı %50'yi aşıp çoğu belgeden geliyorsa, birden fazla uygulama sunucusu gerekiyorsa, belge yedeği gece penceresine sığmıyorsa. Sağlayıcı seçim ölçütleri: veri yerleşimi (KVKK; yurt içi/AB tercihi), sürüm geçmişi + nesne kilidi, yaşam döngüsü kuralları, sunucu tarafı şifreleme, dayanıklılık hedefi, çıkış trafiği (egress) koşulları, VPS'ten gecikme, SLA.
- Geçişin kolaylığı: `document_versions` zaten `storage_key` tutuyor; `document_storage.js` arkasına "dosya sistemi / nesne" sürücüsü eklenir, yeni yüklemeler nesneye, eskiler tembel (lazy) taşınır; indirmeler kısa ömürlü imzalı adresle.
- Nesne depolamaya geçince tam arşiv yedeği (10 tam kopya) bırakılır; sağlayıcı tarafı sürümleme/çoğaltma kullanılır.
- **Kota**: varsayılan 200 MB ücretsiz; ücretli plan alanı ile ek depolama blokları (ör. 1 GB'lık), %80/%95 doluluk e-postası, aşımda yükleme reddi (mevcut davranış). Platform toplam tavanı ve "kota doluluğu ≥ %90 olan site sayısı" izlenmeli.
- **Tekilleştirme**: site içi `sha256` zaten tutuluyor; siteler arası tekilleştirmenin kazancı düşük (belgeler siteye özel), nesne depolamaya geçene dek yapmayın. Daha değerli: yüklemede görüntü yeniden boyutlandırma/sıkıştırma (uzun kenar ~1600 px) ve PDF için boyut uyarısı.

### 6.5 Yedekleme ölçeği

- **Döküm süresi**: betikte `pg_dump` için 900 sn sınırı var [K]; düşük öncelikli (`nice`/`ionice`) çalıştığı için DB yaklaşık 15-30 GB'a gelince bu sınır aşılabilir [T]. Eşik uyarısı: döküm süresi 450 sn'yi geçerse.
- **Slot ekonomisi (hemen)**: dış kopya hazırlık dizini ile günlük şifreli kopya aynı içeriği iki kez tutar; birleştirin. Veritabanı büyüdükçe günlük 14 yerine 7, haftalık 4, aylık 12 (dış kopyada soğuk katman) düşünün. Dış kopya maliyeti ∝ saklanan GB × slot sayısı + geri yükleme çıkış trafiği; şifreli dökümler tekilleştirilemez, bu yüzden slot sayısı doğrudan maliyettir.
- **PITR eşiği** (WAL arşivi, pgBackRest benzeri; haftalık tam + günlük fark + sürekli WAL, nesne depolamaya): şu üç koşuldan biri: (a) ilk gerçek tahsilat giren ücretli finans müşterisi (24 saatlik kurtarma noktası artık kabul edilemez), (b) DB > 10 GB, (c) döküm > 5 dk. Hedef: RPO < 5 dk. Mantıksal döküm (aylık) bağımsız emniyet ağı olarak kalır.
- **Geri yükleme testi**: mantıksal geri yükleme dökümün 3-5 katı sürer (indeksler yeniden kurulur); test için DB boyutunun ≥ 2 katı boş disk gerekir. `restore_test.sh` DB büyüdükçe süresi ölçülüp RTO (hedef < 1 saat) ile karşılaştırılmalı; 20 GB üstünde PITR/fiziksel geri yükleme gerekir.
- **Belge yedeği**: tam arşiv yerine artımlı (değişen dosya) ya da nesne sürümleme; ara çözüm olarak `DOCUMENTS_BACKUP_MAX_MB` hata vermeden önce uyarı üretsin.

### 6.6 İzleme ve alarm

| Kontrol | Eşik |
|---|---|
| Disk kullanımı | %70 uyarı, %85 kritik (`DISK_WARN`/`DISK_CRIT` ortam değişkeniyle ayarlanabilir; bugün 85/95) |
| Disk büyüme hızı | Günlük `df` örneği; bu hızla doluma < 30 gün kaldıysa uyarı |
| Tablo boyutu | Haftalık e-posta: ilk 10 tablonun `pg_total_relation_size` ve bir önceki haftaya göre değişim; tek tablo > 5 GB uyarı |
| Ölü satır / şişme | `n_dead_tup / n_live_tup` > %20 olan tablo (özellikle `door_access_logs`) |
| Bölüm kaldırma/temizlik işi | Son başarılı çalışma > 36 saat; silinen satır sayısı sıfır (sıkışmış iş) |
| Belge kota | Site kotası ≥ %90; belge deposu toplamı `DOCUMENTS_BACKUP_MAX_MB`'in %70'i; yetim karantina sayısı |
| Yedek | Yedek dizini toplamı / boş alan; son döküm süresi (900 sn sınırının %50'si); belge arşivi boyutu |
| Günlükler | Docker kapsayıcı günlükleri ve journald boyutu; PM2/nginx döndürme çalışıyor mu |
| PITR açılınca | `pg_wal` boyutu ve arşivleme gecikmesi; çoğaltma gecikmesi |

Mevcut `deploy/ops/healthcheck.sh`: disk yüzdesi + inode, yedek yaşı, geri yükleme/dış kopya durumu, bellek, TLS var; yukarıdakilerden hiçbiri yok. Eklenecek kontroller aynı `result` mekanizmasını (tekilleştirme, hatırlatma) kullanabilir.

## 7. Yol haritası

| Eşik (biri yeterli) | Yapılacak |
|---|---|
| Şimdi (1 gerçek site) | Aşağıdaki 5 hızlı kazanım |
| İlk ücretli finans müşterisi veya ≥ 25 site | WAL arşivi/PITR hazırlığı (RPO), saklama yürütücüsü devrede, denetim kaydı politikası kararı |
| ≥ 100 site, belge > 2 GB veya disk %50 | Belgeleri nesne depolamaya taşı; belge yedeğini nesne sürümlemeye ya da artımlıya çevir; diski büyüt veya ayrı birim ekle; ücretli ek depolama planı |
| ≥ 300-500 site, DB > 5 GB veya `door_access_logs` > 2 milyon satır | `door_access_logs` ve `audit_log` aylık bölümleme, tablo başına autovacuum, `pg_stat_statements`, yedek slotlarını azalt |
| ≥ 1.000 site, DB > 15 GB veya döküm > 5 dk | DB'yi ayrı sunucuya taşı, akış kopyası, rapor/dışa aktarma kopyaya, yedek ana yolu PITR (mantıksal döküm yalnız aylık) |
| ≥ 2.500 site, DB > 40 GB, günlük > 300 bin kapı olayı | PgBouncer zorunlu, uygulama çok süreçli, finans eski dönemlerini soğuk bölüme ayır, günlük/MQTT altyapısını ayır |
| ≥ 5.000 site | Ayrı NVMe DB makinesi, okuma kopyaları, finans tablolarını `site_code`'a göre bölümle veya kiracı parçalama değerlendirmesi |

### Bugün yapılabilecek en değerli 5 kazanım

| # | İş | Emek |
|---|---|---|
| 1 | Disk uyarısını %70/%85'e çek (`kapi-ops.env`), günlük büyüme hızı örneği + haftalık tablo boyutu e-postası | Küçük (eşik) / orta (rapor) |
| 2 | Yedek slotlarını sadeleştir: dış kopya hazırlık kopyasını günlükle birleştir, `KEEP_*` değerlerini gerçek döküm boyutuna göre ayarla, belge arşivi 10 → 4-6 tam kopya | Küçük |
| 3 | Saklama yürütücüsü: `announcement_recipients`, `finance_reminder_*`, `bulk_import_runs`, `ota_update_*`, `guest_passes` + kapı geçiş silmesini parti halinde; `door_access_logs` için tablo bazlı autovacuum | Orta |
| 4 | Docker kapsayıcı günlükleri (`max-size`), journald, nginx/mosquitto döndürme ayarlarını doğrula ve gerekirse sınırla; PostgreSQL ayarlarını depoya belgele | Küçük |
| 5 | Belge deposu görünürlüğü: toplam kullanım ve kota doluluğu metriği, `DOCUMENTS_BACKUP_MAX_MB` için erken uyarı, `audit_log` fazlalık indeksinin kaldırılması ve `deleted_accounts` kaynağının ayrılması kararı | Orta |

## 8. Doğrulanacaklar (belirsizlikler)

- Denetim kaydı gerçek hacmi (her tahsilat tek tek yazılıyor mu?): ilk sitelerde `audit_log` satır/gün ölçülmeli.
- Makbuz `snapshot` JSONB gerçek boyutu; 2 KB'ı aşarsa TOAST devreye girer ve bayt/satır değişir.
- Dış kopyanın canlıda etkin olup olmadığı (`docs/OPERASYON_YEDEK_IZLEME.md` "yapılandırılmadı" diyor; bu çalışmada doğrulanmadı).
- Docker, journald, nginx, mosquitto günlük sınırları; PostgreSQL ayarları (depoda yok).
- Uygulamanın PM2 çok süreçli (cluster) olup olmadığı: temizlik işinin eşzamanlılık kilidine ihtiyacını belirler.
- Hukuki saklama süreleri (finans, onay, denetim, KVKK imha politikası): hukuk teyidi.
