# Uçtan uca akış haritaları 2/2 (kurulum, OTA, katılım, abonelik, envanter, yetki, PDF)

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm 60 numaralı akış bölümünün devamıdır: bir özellik bozulduğunda zinciri BAŞTAN SONA izlemek içindir. Her giriş bir akıştır; tablo satırları Adım 1, 2, 3... sırasındadır ve her notun başı "Adım N — katman" ile başlar. Katmanlar: uygulama (Flutter: lib/ui -> lib/services), sunucu (Express: routes -> services -> db.js), MQTT (server/src/mqtt_bridge.js <-> Mosquitto), cihaz (ESP32: cihaz_kontrol/include). Nasıl okunur: belirtiyi anlatan akışı seçin, adımları sırayla açın, ilk gerçekleşmeyen adım arıza halkasıdır. Her akışta yalnızca kodda gerçekten var olan katmanlar gösterilir (ör. widget ve PDF akışlarında sunucu/MQTT halkası yoktur ya da kısmen vardır; notlarda belirtilmiştir).

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [server/src/routes/membership_routes.js](../../server/src/routes/membership_routes.js) | Cihaz sahiplenme, site kurulumu, katılım başvurusu, kapı izinleri uçları |
| [server/src/services/membership_service.js](../../server/src/services/membership_service.js) | claimDevice, setupSiteWithClaimedDevice, katılım başvurusu, kapı izin geçersiz kılmaları |
| [server/src/routes/manager_routes.js](../../server/src/routes/manager_routes.js) | Yönetici uçları: cihaz/kapı atama, davet, katılım onayı, MQTT kimliği |
| [server/src/routes/admin_routes.js](../../server/src/routes/admin_routes.js) | Süper kullanıcı uçları: cihaz envanteri, arıza, sahiplik bırakma, OTA kontrolü, site onayı |
| [server/src/services/device_service.js](../../server/src/services/device_service.js) | Cihaz kimlik bilgileri, OTA işleri, envanter, arıza ve sahiplik işlemleri |
| [server/src/mqtt_acl_sync.js](../../server/src/mqtt_acl_sync.js) | Mosquitto ACL metni ve senkron komutu |
| [lib/services/ble_wifi_provision_service.dart](../../lib/services/ble_wifi_provision_service.dart) | Uygulamanın BLE ile Wi-Fi + MQTT kimliği yazması |
| [cihaz_kontrol/include/wifi_baglanti.h](../../cihaz_kontrol/include/wifi_baglanti.h) | Cihaz BLE servisi, kimlik bilgilerinin NVS'ye yazılması |

## Bu bölümdeki girişler (11)

- [akis-cihaz-sahiplenme-wifi-kurulum](#akis-cihaz-sahiplenme-wifi-kurulum) — Cihaz sahiplenme ve Wi-Fi/BLE kurulum akışı bozuldu (uçtan uca): cihaz hesaba bağlanmıyor ya da Wi-Fi yazıldıktan sonra cihaz çevrimiçi olmuyor
- [akis-ota-guncelleme](#akis-ota-guncelleme) — OTA güncelleme akışı bozuldu (uçtan uca): "OTA kontrolü gönder" sonrası cihaz yeni sürüme geçmiyor ya da iş cihazda tamamlanmış görünmüyor
- [akis-site-kurulum-davet-sakin-katilim](#akis-site-kurulum-davet-sakin-katilim) — Site kurulumu ve sakin katılım akışı bozuldu (uçtan uca): site kurulamıyor, katılım QR'ı çalışmıyor ya da sakin başvurusu onaylanınca daireye eklenmiyor
- [akis-yonetici-daveti](#akis-yonetici-daveti) — Yönetici daveti akışı bozuldu (uçtan uca): davet edilen kişi site yöneticisi olmuyor ya da davet e-postası/rolü gelmiyor
- [akis-abonelik-talepleri-onay](#akis-abonelik-talepleri-onay) — Abonelik talepleri / süper kullanıcı onay akışı bozuldu (uçtan uca): bekleyen talep listede görünmüyor, onaylanamıyor ya da onaylanan kullanıcı/site hâlâ giriş-kapı kullanamıyor
- [akis-sesle-kapi-acma-widget-kisayol](#akis-sesle-kapi-acma-widget-kisayol) — Sesle kapı açma / hızlı eylem (uygulama simgesi kısayolu) akışı bozuldu (uçtan uca): "Kapıyı aç" denince kapı açılmıyor ya da kısayol hiçbir şey yapmıyor
- [akis-ana-ekran-widget-kapi-acma](#akis-ana-ekran-widget-kapi-acma) — Ana ekran widget'ı akışı bozuldu (uçtan uca): widget "Giriş Yapın" gösteriyor, kapı değişmiyor ya da dokununca kapı açılmıyor
- [akis-cihaz-envanter-ariza-degistirme](#akis-cihaz-envanter-ariza-degistirme) — Cihaz envanteri / arıza işaretleme / cihaz değiştirme akışı bozuldu (uçtan uca): cihaz sahiplenilemiyor ("envanterde kayıtlı değil", "arızalı"), arızalı cihaz kapıdan çıkarılamıyor ya da yeni cihaz kapıya bağlanmıyor
- [akis-kapi-yetkileri-izinler](#akis-kapi-yetkileri-izinler) — Kapı yetkileri / izinler akışı bozuldu (uçtan uca): verilen ek yetki sakinin kapı listesinde görünmüyor, engellenen sakin hâlâ açabiliyor ya da yerel kontrolde eski yetki sürüyor
- [akis-pdf-ciktilari](#akis-pdf-ciktilari) — Kapı geçiş günlüğü PDF raporu akışı bozuldu (uçtan uca): "kapı geçiş kaydı bulunamadı", rapor eksik/kesik ya da PDF hiç oluşmuyor
- [akis-pdf-giris-bilgileri-ve-surum-raporu](#akis-pdf-giris-bilgileri-ve-surum-raporu) — Site giriş bilgileri PDF'i / cihaz sürüm raporu PDF akışı bozuldu (uçtan uca): PDF "site yapısı alınamadı" diyor, daire/kullanıcı listesi eksik ya da sürüm raporu boş

## Girişler

<a id="akis-cihaz-sahiplenme-wifi-kurulum"></a>
### akis-cihaz-sahiplenme-wifi-kurulum · Cihaz sahiplenme ve Wi-Fi/BLE kurulum akışı bozuldu (uçtan uca): cihaz hesaba bağlanmıyor ya da Wi-Fi yazıldıktan sonra cihaz çevrimiçi olmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/claim_device_dialog.dart:65](../../lib/ui/widgets/claim_device_dialog.dart#L65) | <code>final res = await widget.authService.claimDevice(deviceInput: clean);</code> | Adım 1 — uygulama (ekran): kutu karekodu/seri no/UID metni authService.claimDevice'e verilir; sunucu hata metni kullanıcıya gösterilir. |
| [server/src/routes/membership_routes.js:74](../../server/src/routes/membership_routes.js#L74) | <code>membershipRouter.post('/membership/claim-device', authRequired, claimDeviceLimiter, async…</code> | Adım 2 — sunucu (rota): oturum + claimDeviceLimiter (hız sınırı) sonrası claimDevice çağrılır. |
| [server/src/services/membership_service.js:544](../../server/src/services/membership_service.js#L544) | <code>export async function claimDevice({ userCode, deviceInput }) {</code> | Adım 3 — sunucu (iş kuralı): e-posta doğrulanmış mı (403), cihaz envanterde var mı (404), arızalı mı (400), başka sahibi var mı (409). |
| [server/src/services/membership_service.js:628](../../server/src/services/membership_service.js#L628) | <code>const updateRes = await client.query(SQL_CLAIM_DEVICE_ATOMIC, [user.id, user.user_code, d…</code> | Adım 4 — veritabanı: devices.owner_user_id yalnız boşsa atomik UPDATE; ardından kullanıcı rolü site_manager yapılır. |
| [lib/ui/pages/wifi_provision_page.dart:324](../../lib/ui/pages/wifi_provision_page.dart#L324) | <code>await authService.getDeviceMqttCredentials(deviceUid: deviceUid);</code> | Adım 5 — uygulama (Wi-Fi kurulum ekranı): BLE'den okunan cihaz UID ile sunucudan cihaza özel MQTT kimliği istenir. |
| [server/src/routes/manager_routes.js:639](../../server/src/routes/manager_routes.js#L639) | <code>managerRouter.post('/manager/devices/mqtt-credentials', authRequired, requireSiteManager,…</code> | Adım 6 — sunucu (rota): cihaz yöneticiye görünür mü kontrol edilir; kimlik üretilir; ardından ACL senkronu yapılır (başarısızsa 503). |
| [server/src/services/device_service.js:145](../../server/src/services/device_service.js#L145) | <code>export async function ensureDeviceMqttCredentialsByUid(deviceUid) {</code> | Adım 7 — veritabanı: devices.mqtt_username/mqtt_password/local_control_token boşsa COALESCE ile üretilip yazılır. |
| [server/src/mqtt_acl_sync.js:71](../../server/src/mqtt_acl_sync.js#L71) | <code>export function buildMqttAclText(devices) {</code> | Adım 8 — MQTT (broker izni): cihaz kullanıcısına yalnız kendi device/<uid>/ konularında okuma/yazma izni verilir; senkron olmazsa cihaz bağlanamaz. |
| [lib/services/ble_wifi_provision_service.dart:432](../../lib/services/ble_wifi_provision_service.dart#L432) | <code>Future&lt;BleWifiResult&gt; provisionWifi({</code> | Adım 9 — uygulama (BLE): SSID, parola ve MQTT kimliği JSON olarak komut özelliğine yazılır; sonuç 28 sn boyunca okunur. |
| [cihaz_kontrol/include/wifi_baglanti.h:433](../../cihaz_kontrol/include/wifi_baglanti.h#L433) | <code>class WifiProvisionCommandCallbacks : public BLECharacteristicCallbacks {</code> | Adım 10 — cihaz (BLE işleyici): yalnız provisioning penceresi açıkken, alanlar geçerliyse ve MQTT sunucu adı izinliyse kabul eder. Bu davranışı bozmayın (sahada ESP32-C3). |
| [cihaz_kontrol/include/wifi_baglanti.h:404](../../cihaz_kontrol/include/wifi_baglanti.h#L404) | <code>wifiPersistMqttCredentials(mqttHost, mqttPort, mqttUser, mqttPassword);</code> | Adım 11 — cihaz (NVS): Wi-Fi ve MQTT bilgileri kaydedilir, cihaz yeniden başlar; açılışta MQTT bağlantısı bu kimlikle kurulur. |
| [cihaz_kontrol/include/mqtt_baglanti.h:464](../../cihaz_kontrol/include/mqtt_baglanti.h#L464) | <code>const bool baglandi = client.connect(clientId.c_str(), mqttUser.c_str(), mqttPass.c_str()…</code> | Adım 12 — cihaz (MQTT): kayıtlı kullanıcı/parola ile bağlanır; availability konusuna "offline" LWT ile; kimlik yoksa bağlanmaz. |

**Olası nedenler**
- Halka 3: cihaz şirket envanterinde yok (404), arızalı (400), başka hesapta (409) ya da e-posta doğrulanmamış (403)
- Halka 6/8: MQTT_SYNC_COMMAND tanımsız/başarısız; ACL güncellenmediği için broker cihazı reddeder (rc=4/5)
- Halka 10: BLE penceresi kapalı, MQTT sunucu adı izinli değil ya da alan eksik; cihaz "error" sonucu döndürür
- Halka 11-12: yanlış Wi-Fi parolası, NTP saati gelmediği için TLS bağlantısı bekletiliyor

**Adım adım kontrol**
- Uygulamada görülen hata metnini bulun; hangi adımın (sahiplenme mi, kimlik mi, BLE mi) hatası olduğunu belirleyin
- devices satırında owner_user_id, is_defective, mqtt_username dolu mu bakın (salt-okunur SELECT)
- Sunucu günlüğünde POST /membership/claim-device ve /manager/devices/mqtt-credentials durum kodlarına bakın
- Cihaz seri günlüğünde "MQTT baglaniyor" ve rc değerini okuyun

**Günlükte aranacak ifadeler**
- `MQTT kimligi yok; BLE provisioning ile cihaz kimligi yazilmali.`
- `MQTT sunucu adresi izinli degil.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 150 --nostream | grep -a -E 'claim-device|mqtt-credentials'"
```

**Bkz.:** [akis-bulut-kapi-acma](60-akislar.md#akis-bulut-kapi-acma)

<a id="akis-ota-guncelleme"></a>
### akis-ota-guncelleme · OTA güncelleme akışı bozuldu (uçtan uca): "OTA kontrolü gönder" sonrası cihaz yeni sürüme geçmiyor ya da iş cihazda tamamlanmış görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:2648](../../lib/services/auth_api.dart#L2648) | <code>path: '/admin/devices/ota-check',</code> | Adım 1 — uygulama (süper kullanıcı): POST /admin/devices/ota-check; yalnız 202 kabul edilir. |
| [server/src/routes/admin_routes.js:1426](../../server/src/routes/admin_routes.js#L1426) | <code>adminRouter.post('/admin/devices/ota-check', authRequired, requireSuperUser, async (req, …</code> | Adım 2 — sunucu (rota): tüm cihaz UID'leri listelenir, iş açılır, MQTT yayını yapılır, iş kapatılır; köprü bağlı değilse 503. |
| [server/src/services/device_service.js:427](../../server/src/services/device_service.js#L427) | <code>export async function createOtaUpdateJob({ authUser, deviceUids }) {</code> | Adım 3 — veritabanı: ota_update_jobs (status=publishing) ve her cihaz için ota_update_job_devices satırı yazılır. |
| [server/src/mqtt_bridge.js:1193](../../server/src/mqtt_bridge.js#L1193) | <code>export async function publishOtaCheckToDevices({</code> | Adım 4 — MQTT (yayın): her cihaza device/<uid>/cmd konusuna {action:ota_check, retry:true, ota_job_id} QoS 1 yayınlanır. |
| [cihaz_kontrol/include/mqtt_baglanti.h:350](../../cihaz_kontrol/include/mqtt_baglanti.h#L350) | <code>} else if (action == "ota_check") {</code> | Adım 5 — cihaz (MQTT işleyici): ota_check komutu otaTalepEt çağırır ve ota_check_requested olayını yayınlar; ota_job_id varsa kontrol 0-120 sn araya yayılır. |
| [cihaz_kontrol/include/ota_guncelleme.h:498](../../cihaz_kontrol/include/ota_guncelleme.h#L498) | <code>inline void otaCheckAndUpdate() {</code> | Adım 6 — cihaz (OTA döngüsü): manifest okunur, hedef (OTA_TARGET) eşleşmesi ve sürüm karşılaştırılır; hata olayları ota_check_failed/ota_target_mismatch/ota_usb_required. ESP32-C3 sahada çalışıyor: akışı bozmayın. |
| [server/src/routes/firmware_routes.js:111](../../server/src/routes/firmware_routes.js#L111) | <code>firmwareRouter.get('/firmware/:target/manifest.json', async (req, res) =&gt; {</code> | Adım 7 — sunucu (manifest): cihazın current_version'ına göre update_available, url, sha256, md5, usb_required döner; hedef uyuşmazlığında güncelleme sunulmaz. |
| [cihaz_kontrol/include/ota_guncelleme.h:436](../../cihaz_kontrol/include/ota_guncelleme.h#L436) | <code>inline String otaIndirVeYaz(const String&amp; url, const String&amp; beklenenSha256, const String…</code> | Adım 8 — cihaz (indirme): yalnız izinli HTTPS adresten indirir, flash'a yazar, sha256 ve md5 doğrular; uyuşmazlıkta deneme hakkı yanar (en fazla 3 deneme). |
| [cihaz_kontrol/include/ota_guncelleme.h:664](../../cihaz_kontrol/include/ota_guncelleme.h#L664) | <code>otaPublishEvent("ota_success", version);</code> | Adım 9 — cihaz (sonuç): ota_success olayı yeniden başlatmadan ÖNCE yayınlanır; başarısızlıkta ota_failed. |
| [server/src/mqtt_bridge.js:889](../../server/src/mqtt_bridge.js#L889) | <code>void recordOtaJobDeviceEvent(</code> | Adım 10 — sunucu (olay işleme): device/<uid>/event içindeki ota_* olayı ve ota_job_id ile iş/cihaz satırı güncellenir; runtime durumuna ota_status yazılır. |
| [server/src/services/device_service.js:465](../../server/src/services/device_service.js#L465) | <code>export async function finishOtaUpdateJob({ jobId, result }) {</code> | Adım 11 — veritabanı: yayın bitince sent/failed sayıları ve status (completed / completed_with_errors) yazılır; bu, cihazın güncellediği anlamına GELMEZ, yalnız komutun yayınlandığını gösterir. |

**Olası nedenler**
- Halka 2/4: MQTT köprüsü bağlı değil (503) ya da cihaz çevrimdışı (yanıtta failed listesi yalnız yayın hatasını gösterir, cihazın aldığını göstermez)
- Halka 6/7: manifest klasörü/hedefi uyuşmuyor, usb_required, cihaz yayın grubunda değil, sürüm cihazdakinden büyük değil
- Halka 8: sha256/md5 uyuşmuyor, indirme adresi izinli önek dışında, 3 deneme hakkı bitti (yönetici retry:true ile sayacı sıfırlar)
- Halka 10: olay geldi ama ota_job_id eşleşmiyor; iş satırı güncellenmez

**Adım adım kontrol**
- Süper kullanıcı yanıtındaki requested/sent/failed sayılarına bakın
- Sunucuda manifest uç noktasını çağırın: GET /firmware/<hedef>/manifest.json?current_version=...
- ota_update_job_devices satırlarında publish_status ve error_message değerlerine bakın (salt-okunur SELECT)
- Cihaz seri günlüğünde "OTA kontrolu basladi" ve sonraki hata satırını okuyun

**Günlükte aranacak ifadeler**
- `OTA kontrolu basladi.`
- `OTA HATA: Hedef mimari uyusmuyor!`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 150 --nostream | grep -a -E 'ota|firmware'"
```

**Bkz.:** [akis-cihaz-sahiplenme-wifi-kurulum](#akis-cihaz-sahiplenme-wifi-kurulum)

<a id="akis-site-kurulum-davet-sakin-katilim"></a>
### akis-site-kurulum-davet-sakin-katilim · Site kurulumu ve sakin katılım akışı bozuldu (uçtan uca): site kurulamıyor, katılım QR'ı çalışmıyor ya da sakin başvurusu onaylanınca daireye eklenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/dialogs/setup_site_dialog.dart:512](../../lib/ui/dialogs/setup_site_dialog.dart#L512) | <code>await widget.authService.setupSite(</code> | Adım 1 — uygulama (site kurulum sihirbazı): ad, blok/daire sayıları ve kapı listesi AuthService.setupSite'a verilir (anlık kurulum hakkı olmayan hesapta pencere site başvurusu kipindedir: createSiteApplication). |
| [server/src/routes/membership_routes.js:107](../../server/src/routes/membership_routes.js#L107) | <code>membershipRouter.post('/membership/setup-site', authRequired, setupSiteLimiter, async (re…</code> | Adım 2 — sunucu (rota): setupSiteLimiter sonrası setupSiteWithClaimedDevice; başarıda 201. |
| [server/src/services/membership_service.js:795](../../server/src/services/membership_service.js#L795) | <code>await assertInstantSetupAllowed(client, code, user.role);</code> | Adım 2b — sunucu (kurulum hakkı): anlık kurulum yalnız sahip bağı olan site yöneticisine ve süper kullanıcıya açık; bireysel / daire sahibi ve sahip bağı olmayan yönetici 409 APPLICATION_REQUIRED alır (site başvurusu yolu). |
| [server/src/services/membership_service.js:805](../../server/src/services/membership_service.js#L805) | <code>devQuery = `SELECT * FROM devices WHERE UPPER(device_uid) = $1 AND (owner_user_id = $2 OR…</code> | Adım 3 — sunucu/veritabanı (cihaz kuralı): deviceUid verildiyse kullanıcıya ait olmalı (değilse 404, site HİÇ kurulmaz); cihaz satırı kilitlenir. Cihaz belirtilmezse kullanıcının sahiplendiği ya da ona atanmış en son cihaz (varsa) bağlanır, yoksa site cihazsız kurulur. |
| [server/src/services/site_setup_core.js:173](../../server/src/services/site_setup_core.js#L173) | <code>INSERT INTO site_blocks (site_code, block_name, sort_order)</code> | Adım 4 — veritabanı (ortak çekirdek; site başvurusu onayı da aynısını kullanır): tek işlemde sites, site_manager_sites (sahip bağı), site_memberships (SITE_OWNER), site_blocks, apartments, site_doors yazılır; cihaz varsa ilk kapıya bağlanır. |
| [server/src/routes/manager_routes.js:547](../../server/src/routes/manager_routes.js#L547) | <code>managerRouter.get('/manager/sites/:id/join-token', authRequired, requireSiteManager, asyn…</code> | Adım 5 — sunucu (yönetici QR): yönetici site katılım tokenını alır (yoksa üretilir); rotate ucu eski QR'ları iptal eder. |
| [server/src/services/site_service.js:1387](../../server/src/services/site_service.js#L1387) | <code>export async function getSiteByJoinToken({ token }) {</code> | Adım 6 — sunucu (sakin QR okutma): GET /membership/join-info/:token ile site, blok ve daire listesi döner; iptal edilmiş token 404. |
| [lib/services/auth_api.dart:4061](../../lib/services/auth_api.dart#L4061) | <code>path: '/membership/join-request',</code> | Adım 7 — uygulama (sakin): seçilen daire ve not ile POST /membership/join-request; yalnız 201 kabul edilir. |
| [server/src/services/membership_service.js:977](../../server/src/services/membership_service.js#L977) | <code>INSERT INTO join_requests (</code> | Adım 8 — veritabanı: createJoinRequest e-posta doğrulamasını ve daire/site uyumunu denetler, join_requests satırı yazar. |
| [server/src/routes/manager_routes.js:1277](../../server/src/routes/manager_routes.js#L1277) | <code>managerRouter.post('/manager/join-requests/:requestId/approve', authRequired, requireSite…</code> | Adım 9 — sunucu (yönetici onayı): approveJoinRequest çağrılır. |
| [server/src/services/membership_service.js:1258](../../server/src/services/membership_service.js#L1258) | <code>INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active)</code> | Adım 10 — veritabanı: onayda apartment_memberships ve site_memberships yazılır, boşsa apartments.resident_user_code atanır, talep APPROVED olur. |

**Olası nedenler**
- Halka 2b: hesabın anında site kurma hakkı yok (409 APPLICATION_REQUIRED): site başvurusu yapılır, süper kullanıcı onaylayınca site kurulur
- Halka 3: belirtilen cihaz başka hesapta ya da yok (404; site HİÇ kurulmaz, işlem geri alınır)
- Halka 5/6: QR yenilenmiş (rotate) ya da token iptal; sakin eski QR'ı okutuyor
- Halka 8: sakin e-postasını doğrulamamış ya da seçilen daire o siteye ait değil
- Halka 10: talep zaten işlenmiş ya da yönetici o siteyi yönetmiyor (yetki hatası)

**Adım adım kontrol**
- Günlükte POST /membership/setup-site, GET /membership/join-info, POST /membership/join-request durum kodlarına bakın
- join_requests tablosunda talebin status değerine bakın (salt-okunur SELECT)
- Onay sonrası apartment_memberships satırı var mı bakın
- Sakin uygulamayı yenileyip daire listesini (my-apartments) görüyor mu doğrulayın

**Günlükte aranacak ifadeler**
- `Bu site katılım QR kodu geçersiz veya iptal edilmiş.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 150 --nostream | grep -a -E 'setup-site|join-request|join-info'"
```

**Bkz.:** [akis-cihaz-sahiplenme-wifi-kurulum](#akis-cihaz-sahiplenme-wifi-kurulum), [akis-yonetici-daveti](#akis-yonetici-daveti)

<a id="akis-yonetici-daveti"></a>
### akis-yonetici-daveti · Yönetici daveti akışı bozuldu (uçtan uca): davet edilen kişi site yöneticisi olmuyor ya da davet e-postası/rolü gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:4336](../../lib/services/auth_api.dart#L4336) | <code>path: '/manager/sites/$siteCode/managers/invite',</code> | Adım 1 — uygulama (HTTP): POST /manager/sites/<site>/managers/invite, gövde {email, full_name}. |
| [server/src/routes/manager_routes.js:1348](../../server/src/routes/manager_routes.js#L1348) | <code>managerRouter.post('/manager/sites/:siteCode/managers/invite', authRequired, requireSiteM…</code> | Adım 2 — sunucu (rota): site yönetim yetkisi (403) ve inviteLimiter sonrası inviteSiteManager. |
| [server/src/services/site_service.js:2015](../../server/src/services/site_service.js#L2015) | <code>export async function inviteSiteManager({ siteCode, email, fullName, inviterUser }) {</code> | Adım 3 — sunucu (iş kuralı): e-posta kayıtlı kullanıcıya aitse doğrudan yönetici yapılır; değilse davet satırı açılır. |
| [server/src/services/site_service.js:2102](../../server/src/services/site_service.js#L2102) | <code>VALUES ($1, $2, 'SITE_ADMIN', TRUE)</code> | Adım 4 — veritabanı (mevcut kullanıcı): site_manager_sites + site_memberships (SITE_ADMIN) yazılır, global rol site_manager olur. |
| [server/src/services/site_service.js:2162](../../server/src/services/site_service.js#L2162) | <code>INSERT INTO site_manager_invitations (</code> | Adım 5 — veritabanı (kayıtsız e-posta): SMI- belirteçli davet satırı 7 gün geçerli PENDING olarak yazılır. |
| [server/src/services/membership_service.js:433](../../server/src/services/membership_service.js#L433) | <code>`SELECT id, site_code FROM site_manager_invitations WHERE LOWER(email) = LOWER($1) AND st…</code> | Adım 6 — sunucu (kayıt doğrulaması): davetli e-posta kodunu doğrulayınca bekleyen davetler aynı işlemde yönetici yetkisine çevrilir. |
| [server/src/services/site_service.js:2139](../../server/src/services/site_service.js#L2139) | <code>await rotateLocalControlTokensForSite(code, 'site_manager_added');</code> | Adım 7 — sunucu (yerel kontrol anahtarı): yeni yönetici eklenince sitenin cihazlarının yerel kontrol anahtarı yenilenir. |
| [server/src/mqtt_bridge.js:1161](../../server/src/mqtt_bridge.js#L1161) | <code>export async function publishLocalControlConfig({</code> | Adım 8 — MQTT: cihaz çevrimiçiyse device/<uid>/cmd konusuna local_control_config yayınlanır; cihaz bağlı değilse false döner, gönderilmez. |
| [cihaz_kontrol/include/mqtt_baglanti.h:361](../../cihaz_kontrol/include/mqtt_baglanti.h#L361) | <code>} else if (action == "local_control_config") {</code> | Adım 9 — cihaz: yeni yerel kontrol anahtarı NVS'ye yazılır; geçersizse local_control_config_rejected olayı yayınlanır. |

**Olası nedenler**
- Halka 2: yönetim yetkisi yok (403) ya da davet hız sınırı
- Halka 3/4: kullanıcı zaten bu sitenin yöneticisi (409)
- Halka 5/6: davetli farklı e-posta ile kayıt oldu; davet 7 günü aştı ya da iptal edildi (REVOKED)
- Halka 8: cihaz o an çevrimdışı; yerel anahtar cihaza ulaşmaz (sunucu hatayı yutar, yalnız audit günlüğüne yazar)

**Adım adım kontrol**
- site_manager_invitations tablosunda e-postanın status ve expires_at değerine bakın (salt-okunur SELECT)
- Davetli kayıtlıysa site_manager_sites satırı var mı bakın
- Günlükte local_control_token_rotation_failed / local_control_token_synced kayıtlarını arayın

**Günlükte aranacak ifadeler**
- `Yönetici ekleme bildirimi gönderilemedi:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a -E 'managers/invite|local_control_token'"
```

**Bkz.:** [akis-site-kurulum-davet-sakin-katilim](#akis-site-kurulum-davet-sakin-katilim)

<a id="akis-abonelik-talepleri-onay"></a>
### akis-abonelik-talepleri-onay · Abonelik talepleri / süper kullanıcı onay akışı bozuldu (uçtan uca): bekleyen talep listede görünmüyor, onaylanamıyor ya da onaylanan kullanıcı/site hâlâ giriş-kapı kullanamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3855](../../lib/ui/pages/home_page.dart#L3855) | <code>Future&lt;void&gt; _resolveSubscriptionRequest({</code> | Adım 1 — uygulama (süper kullanıcı ekranı): Onayla/Reddet düğmesi authService.resolveSubscriptionRequest(action: approve\|reject) çağırır; hata metni gösterilir. |
| [lib/services/auth_api.dart:2867](../../lib/services/auth_api.dart#L2867) | <code>path: '/admin/subscription-requests/$userCode',</code> | Adım 2 — uygulama (HTTP): PATCH /admin/subscription-requests/<userCode>, gövde {action}; yalnız 200 kabul edilir. |
| [server/src/routes/admin_routes.js:662](../../server/src/routes/admin_routes.js#L662) | <code>'/admin/subscription-requests/:id',</code> | Adım 3 — sunucu (rota): yalnız süper kullanıcı; action approve/reject dışında 400. |
| [server/src/routes/admin_routes.js:702](../../server/src/routes/admin_routes.js#L702) | <code>[action === 'approve' ? 'approved' : 'rejected', action === 'approve', userCode],</code> | Adım 4 — veritabanı: users.approval_status approved/rejected ve is_active yazılır; yalnız role=site_manager ve pending satır için çalışır (aksi 404 "Bekleyen abonelik talebi bulunamadi"). |
| [server/src/routes/admin_routes.js:655](../../server/src/routes/admin_routes.js#L655) | <code>return sendServiceError(res, error, 'Abonelik talepleri alinamadi.');</code> | Adım 5 — sunucu (liste): GET /admin/subscription-requests yalnız e-postası doğrulanmış, pending, site_manager kullanıcıları listeler. |
| [server/src/routes/auth_routes.js:780](../../server/src/routes/auth_routes.js#L780) | <code>if (row.approval_status === 'pending') {</code> | Adım 6 — sunucu (giriş): pending kullanıcıya 403 "Abonelik talebiniz onay bekliyor.", rejected kullanıcıya 403 "Abonelik talebiniz reddedildi." |
| [server/src/middlewares/auth_middleware.js:93](../../server/src/middlewares/auth_middleware.js#L93) | <code>if (authUser.approval_status === 'pending') {</code> | Adım 7 — sunucu (her istek): açık oturumda da aynı onay denetimi uygulanır; durum değişince mevcut token ile 403 alınır. |
| [server/src/routes/auth_routes.js:557](../../server/src/routes/auth_routes.js#L557) | <code>error: 'Site yoneticisi kaydi yalnizca super user tarafindan yapilir.',</code> | Adım 8 — sunucu (dikkat): eski /auth/site-manager/register ucu 410 döner (kayıt kodu yorum satırında); yani yeni pending abonelik talebi bu yoldan OLUŞMAZ, listede yalnız eski kayıtlar görünür. |
| [server/src/routes/admin_routes.js:830](../../server/src/routes/admin_routes.js#L830) | <code>adminRouter.patch('/admin/sites/:id/approval', authRequired, requireSuperUser, async (req…</code> | Adım 9 — sunucu (site onayı, ayrı kuyruk): sites.approval_status pending ise approve/reject; onayda blok/daire/kapı sayıları eşitlenir. |
| [server/src/services/door_service.js:383](../../server/src/services/door_service.js#L383) | <code>AND s.approval_status = 'approved'</code> | Adım 10 — sunucu (sonuç): kapı listesi yalnız onaylı sitelerdeki kapıları döner; site pending/rejected ise kullanıcı kapıyı görmez. (setup-site ile kurulan site doğrudan approved yazılır.) |

**Olası nedenler**
- Halka 5: kullanıcının e-postası doğrulanmamış ya da rolü site_manager değil; liste dışında kalır
- Halka 4: talep başka işlemle zaten sonuçlanmış (404)
- Halka 8: yeni talep bekleniyor ama site yöneticisi kaydı kapalı (410)
- Halka 10: site pending/rejected olduğu için kapılar listelenmiyor

**Adım adım kontrol**
- users satırında role, email_verified, approval_status, is_active değerlerine bakın (salt-okunur SELECT)
- Süper kullanıcı oturumuyla GET /admin/subscription-requests yanıtını kontrol edin
- Site sorunuysa sites.approval_status değerine bakın

**Günlükte aranacak ifadeler**
- `Bekleyen abonelik talebi bulunamadi.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 150 --nostream | grep -a -E 'subscription-requests|/approval'"
```

**Bkz.:** [akis-giris-oturum-jwt](60-akislar.md#akis-giris-oturum-jwt), [akis-site-kurulum-davet-sakin-katilim](#akis-site-kurulum-davet-sakin-katilim)

<a id="akis-sesle-kapi-acma-widget-kisayol"></a>
### akis-sesle-kapi-acma-widget-kisayol · Sesle kapı açma / hızlı eylem (uygulama simgesi kısayolu) akışı bozuldu (uçtan uca): "Kapıyı aç" denince kapı açılmıyor ya da kısayol hiçbir şey yapmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/quick_actions_service.dart:41](../../lib/services/quick_actions_service.dart#L41) | <code>type: 'voice_open',</code> | Adım 1 — uygulama (kısayol kaydı): simge uzun basma menüsüne "Sesli Kapı Aç" ve ilk 3 kapı için open_door_<id> kısayolları yazılır (updateDoorShortcuts). |
| [lib/app.dart:126](../../lib/app.dart#L126) | <code>Future&lt;void&gt; _handleQuickAction(String actionType) async {</code> | Adım 2 — uygulama (kısayol seçimi): voice_open -> triggerVoice; open_door_<id> -> openDoorById deep link eylemi. |
| [lib/app.dart:170](../../lib/app.dart#L170) | <code>case DeepLinkActionType.triggerVoice:</code> | Adım 3 — uygulama (yönlendirme): yalnız apartmentOwner ve individual rolü için ses penceresi açılır; diğer rollerde hiçbir şey olmaz. |
| [lib/services/voice_door_service.dart:244](../../lib/services/voice_door_service.dart#L244) | <code>Future&lt;void&gt; startListening({List&lt;DoorRecord&gt;? candidateDoors}) async {</code> | Adım 4 — uygulama (konuşma tanıma): mikrofon/konuşma tanıma hazır değilse başlatılmaz; tanınan metin _processVoiceCommand'a gider. |
| [lib/services/voice_door_service.dart:613](../../lib/services/voice_door_service.dart#L613) | <code>static DoorMatchResult resolveDoorFromCommand(</code> | Adım 5 — uygulama (eşleme): komutta "aç" niyeti ve tek net kapı aranır; belirsiz/bulunamadı/ters niyet (kapat, kilitle) durumları kapı AÇMAZ. |
| [lib/services/voice_door_service.dart:454](../../lib/services/voice_door_service.dart#L454) | <code>final (status, error) = await _authService.openDoor(</code> | Adım 6 — uygulama (servis): eşleşen kapı için AuthService.openDoor çağrılır; 5 sn içinde ikinci komut ve eşzamanlı komut reddedilir. |
| [lib/services/auth_service.dart:2664](../../lib/services/auth_service.dart#L2664) | <code>Future&lt;(DoorRuntimeStatus?, String?)&gt; openDoor({</code> | Adım 7 — uygulama (karar): kapı politikası bayraklarına göre önce yerel UDP (canlı beacon + yerel token varsa), sonra bulut açma denenir; ayrıntı için akis-yerel-kapi-acma ve akis-bulut-kapi-acma. |
| [server/src/routes/app_doors_routes.js:161](../../server/src/routes/app_doors_routes.js#L161) | <code>appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (r…</code> | Adım 8 — sunucu: bulut açma ucu; kapı erişimi, cihaz atanmış mı (409) kontrolü ve publishDoorPulse ile MQTT darbesi; 202 döner (zincirin devamı akis-bulut-kapi-acma'da). |
| [cihaz_kontrol/include/mqtt_baglanti.h:247](../../cihaz_kontrol/include/mqtt_baglanti.h#L247) | <code>inline void mqttHandlePulse(JsonDocument&amp; json) {</code> | Adım 9 — cihaz: cmd konusundaki pulse komutu röleyi tetikler (tekrar eden request_id yok sayılır). ESP32-C3 sahada çalışıyor: bu davranışı bozmayın. |

**Olası nedenler**
- Halka 3: kullanıcı rolü ses özelliğini desteklemiyor (site yöneticisi/süper kullanıcı) ya da oturum yok ("Lütfen önce uygulamaya giriş yapın.")
- Halka 4: mikrofon izni verilmemiş ya da cihazda konuşma tanıma servisi yok
- Halka 5: komut "aç" içermiyor, birden çok kapıya uyuyor ya da kapı adı yanlış tanındı
- Halka 7-9: kapı için uzaktan açma kapalı, cihaz çevrimdışı (409) ya da geofence reddi; bunlar sesli değil açma zincirinin hatalarıdır

**Adım adım kontrol**
- Uygulamada ses penceresinde görünen "tanınan metin" ve geri bildirim satırını okuyun
- Aynı kapıyı düğmeyle açmayı deneyin: düğme de açılmıyorsa sorun açma zincirindedir (akis-bulut-kapi-acma)
- Sunucu günlüğünde POST /app/doors/<id>/open durum kodunu arayın
- Kısayol için: uygulama kapıları listeledikten sonra kısayollar güncellenir; liste boşsa yalnız sesli kısayol vardır

**Günlükte aranacak ifadeler**
- `[QuickActions] initialize yok sayıldı:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a /open"
```

**İlgili testler:** [test/voice_door_service_test.dart](../../test/voice_door_service_test.dart)

**Bkz.:** [akis-bulut-kapi-acma](60-akislar.md#akis-bulut-kapi-acma), [akis-yerel-kapi-acma](60-akislar.md#akis-yerel-kapi-acma), [akis-ana-ekran-widget-kapi-acma](#akis-ana-ekran-widget-kapi-acma)

<a id="akis-ana-ekran-widget-kapi-acma"></a>
### akis-ana-ekran-widget-kapi-acma · Ana ekran widget'ı akışı bozuldu (uçtan uca): widget "Giriş Yapın" gösteriyor, kapı değişmiyor ya da dokununca kapı açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/door_widget_service.dart:475](../../lib/services/door_widget_service.dart#L475) | <code>Future&lt;void&gt; syncDoorsList({</code> | Adım 1 — uygulama (veri aktarımı): uygulama açıkken kapı listesi, aktif kapı, auth_token ve api_base_url widget'ın paylaşılan depolamasına yazılır. Widget yalnızca bu yazılan veriyle çalışır. |
| [lib/services/door_widget_service.dart:231](../../lib/services/door_widget_service.dart#L231) | <code>Future&lt;void&gt; doorWidgetBackgroundCallback(Uri? uri) async {</code> | Adım 2 — uygulama (arka plan): widget dokunuşu (sonraki/önceki kapı, aç) uygulama kapalıyken bile bu işleve gelir. |
| [lib/services/door_widget_service.dart:356](../../lib/services/door_widget_service.dart#L356) | <code>Future&lt;void&gt; _cycleDoor({required int step}) async {</code> | Adım 3 — uygulama: ◀/▶ yalnız kapı sayısı 1'den büyükse aktif kapıyı değiştirir ve widget verisini günceller. |
| [lib/services/door_widget_service.dart:307](../../lib/services/door_widget_service.dart#L307) | <code>Future&lt;DoorWidgetOpenOutcome&gt; _performOpen() async {</code> | Adım 4 — uygulama (açma): token veya kapı yoksa "Giriş Yapın"/"Kapı Tanımlı Değil"; aksi halde POST <api>/app/doors/<id>/open doğrudan HTTP ile çağrılır (yerel UDP yolu yoktur). 401 gelirse token widget'tan silinir. |
| [server/src/routes/app_doors_routes.js:161](../../server/src/routes/app_doors_routes.js#L161) | <code>appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (r…</code> | Adım 5 — sunucu: bulut açma ucu; yanıt kodları widget metnine çevrilir (409 çevrimdışı, 403 yetki/geofence, 429 hız sınırı). |
| [lib/services/door_widget_service.dart:150](../../lib/services/door_widget_service.dart#L150) | <code>DoorWidgetOpenOutcome mapDoorOpenResponse(int statusCode, String body) {</code> | Adım 6 — uygulama (sonuç): 200/202 -> "Açıldı!"; 403 GEOFENCE* -> "Konum için uygulamayı açın"; 409 -> "Kapı çevrimdışı" (çevrimdışı işaretlenir). |
| [cihaz_kontrol/include/mqtt_baglanti.h:247](../../cihaz_kontrol/include/mqtt_baglanti.h#L247) | <code>inline void mqttHandlePulse(JsonDocument&amp; json) {</code> | Adım 7 — cihaz: sunucunun yayınladığı pulse komutu röleyi tetikler; widget cihazdan doğrulama beklemez, "Açıldı!" yalnız sunucunun 202 yanıtına dayanır. |
| [android/app/src/main/AndroidManifest.xml:105](../../android/app/src/main/AndroidManifest.xml#L105) | <code>android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver"</code> | Adım 8 — Android (yayın alıcısı): widget dokunuşunu arka plan işlevine taşıyan alıcı; bildirim kaydı bozulursa dokunuş hiçbir şey yapmaz. |

**Olası nedenler**
- Halka 1: uygulama hiç açılmadı ya da oturum kapandı; widget'ta token yok ("Giriş Yapın")
- Halka 4: 401 sonrası token silindi; uygulama açılıp oturum yenilenene dek widget giriş ister
- Halka 4: 2 sn içinde tekrar dokunuş ya da önceki istek sürüyor; dokunuş yok sayılır
- Halka 5-6: kapı çevrimdışı (409), uzaktan açma kapalı, geofence nedeniyle konum için uygulama gerekli

**Adım adım kontrol**
- Widget metnine göre halkayı seçin: "Giriş Yapın" -> halka 1/4; "Bağlantı hatası" -> ağ; "Kapı çevrimdışı" -> cihaz/MQTT
- Uygulamayı açıp kapı listesini yenileyin (widget verisi yeniden yazılır)
- Sunucu günlüğünde POST /app/doors/<id>/open durum kodunu arayın

**Günlükte aranacak ifadeler**
- `[DoorWidget] callback error:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a /open"
```

**Bkz.:** [akis-bulut-kapi-acma](60-akislar.md#akis-bulut-kapi-acma), [akis-sesle-kapi-acma-widget-kisayol](#akis-sesle-kapi-acma-widget-kisayol)

<a id="akis-cihaz-envanter-ariza-degistirme"></a>
### akis-cihaz-envanter-ariza-degistirme · Cihaz envanteri / arıza işaretleme / cihaz değiştirme akışı bozuldu (uçtan uca): cihaz sahiplenilemiyor ("envanterde kayıtlı değil", "arızalı"), arızalı cihaz kapıdan çıkarılamıyor ya da yeni cihaz kapıya bağlanmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:2013](../../company_qr_tool/app.py#L2013) | <code>def _server_device_save_worker(self, dev: EspDevice, payload: dict) -&gt; None:</code> | Adım 1 — şirket aracı (Python): etiketlenen cihaz POST /api/company/labeled-devices ile sunucuya gönderilir; şirket anahtarı yoksa ağ isteği hiç yapılmaz. |
| [server/src/routes/company_routes.js:340](../../server/src/routes/company_routes.js#L340) | <code>await syncCompanyDeviceRecord(pool, { deviceUid, hardwareType });</code> | Adım 2 — sunucu/veritabanı: etiket dosyalarından ÖNCE devices satırı yazılır (hata yutulmaz); sahiplenme bu envanter satırına dayanır. |
| [server/src/routes/admin_routes.js:1566](../../server/src/routes/admin_routes.js#L1566) | <code>adminRouter.post('/admin/devices', authRequired, requireSuperUser, async (req, res) =&gt; {</code> | Adım 3 — sunucu (süper kullanıcı, elle kayıt): UID doğrulanır, registerCompanyDevice ile envantere eklenir; kullanıcı/site verilirse ek UPDATE yapılır. |
| [lib/services/auth_api.dart:4384](../../lib/services/auth_api.dart#L4384) | <code>path: '/admin/devices/$deviceId/defect',</code> | Adım 4 — uygulama (süper kullanıcı): arıza işareti PATCH /admin/devices/<id>/defect, gövde {is_defective, defective_reason}. |
| [server/src/services/device_service.js:945](../../server/src/services/device_service.js#L945) | <code>export async function setDeviceDefectStatus({ deviceId, isDefective, defectiveReason, aut…</code> | Adım 5 — veritabanı: devices.is_defective/defective_reason/defective_at yazılır; arıza kalkınca temizlenir (audit: device_marked_defective). |
| [server/src/services/membership_service.js:593](../../server/src/services/membership_service.js#L593) | <code>if (deviceRow.is_defective) {</code> | Adım 6 — sunucu (sonuç): arızalı cihaz sahiplenilemez (400); atomik UPDATE sırasında da yeniden denetlenir. |
| [lib/services/auth_api.dart:3975](../../lib/services/auth_api.dart#L3975) | <code>path: '/manager/doors/$doorId/replace-device',</code> | Adım 7 — uygulama (yönetici): yeni cihazın karekod/seri/UID metni ile POST /manager/doors/<id>/replace-device. |
| [server/src/routes/manager_routes.js:925](../../server/src/routes/manager_routes.js#L925) | <code>managerRouter.post('/manager/doors/:id/replace-device', authRequired, requireSiteManager,…</code> | Adım 8 — sunucu (rota): kapının sitesi üzerinde yönetim yetkisi (403) denetlenir; DEVICE_NOT_FOUND 404. |
| [server/src/services/door_service.js:823](../../server/src/services/door_service.js#L823) | <code>export async function replaceDoorDevice({ doorId, newDeviceInput, newDeviceId, authUser }…</code> | Adım 9 — sunucu (iş kuralı): yeni cihaz arızalı (409), başkasına ait (409) ya da atanamaz (403) olmamalı; geçerli hex UID envanterde yoksa yeni satır açılır. |
| [server/src/services/door_service.js:989](../../server/src/services/door_service.js#L989) | <code>`UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`,</code> | Adım 10 — veritabanı: eski cihaz kapıdan/siteden boşaltılır, yeni cihaz AYNI site_doors satırına bağlanır; kapı kimliği değişmediği için kapı izinleri ve ayarları korunur. |
| [server/src/services/device_service.js:991](../../server/src/services/device_service.js#L991) | <code>export async function releaseDeviceOwnership({ deviceId, authUser }) {</code> | Adım 11 — veritabanı (stoğa iade): kapı atamasını, owner_user_id, site_code, claimed_at değerlerini sıfırlar; ardından yerel kontrol anahtarı yenilenir (eski sahibin önbelleği geçersiz olur). |

**Olası nedenler**
- Halka 1-2: şirket aracı sunucuya kaydedemedi (anahtar yok/401); cihaz envanterde olmadığı için sahiplenme 404 verir
- Halka 5-6: cihaz arızalı işaretli; kullanıcı "arızalı olarak işaretlenmiştir" mesajı alır
- Halka 9: yeni cihaz başka hesapta/başka kapıda ya da UID hex değil; cihaz değiştirme reddedilir
- Halka 10 sonrası: yeni cihaz fiziksel olarak Wi-Fi/MQTT kimliği almadıysa kapı çevrimdışı görünür (bu akışta MQTT adımı yoktur; kurulum için akis-cihaz-sahiplenme-wifi-kurulum)

**Adım adım kontrol**
- devices satırında device_uid, is_defective, owner_user_id, site_code değerlerine bakın (salt-okunur SELECT)
- site_doors.assigned_device_id yeni cihazın id'sine işaret ediyor mu bakın
- Günlükte POST /manager/doors/<id>/replace-device ve PATCH /admin/devices/<id>/defect durum kodlarını arayın
- Yeni cihaz çevrimiçi mi: yönetici ekranında kapı durumuna ve connectivity-logs'a bakın

**Günlükte aranacak ifadeler**
- `Bu cihaz şirket envanterinde kayıtlı değildir.`
- `Cihaz sahipliği sıfırlanamadı.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 150 --nostream | grep -a -E 'replace-device|/defect|labeled-devices'"
```

**Bkz.:** [akis-cihaz-sahiplenme-wifi-kurulum](#akis-cihaz-sahiplenme-wifi-kurulum), [akis-kapi-yetkileri-izinler](#akis-kapi-yetkileri-izinler)

<a id="akis-kapi-yetkileri-izinler"></a>
### akis-kapi-yetkileri-izinler · Kapı yetkileri / izinler akışı bozuldu (uçtan uca): verilen ek yetki sakinin kapı listesinde görünmüyor, engellenen sakin hâlâ açabiliyor ya da yerel kontrolde eski yetki sürüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/dialogs/door_permissions_dialog.dart:122](../../lib/ui/dialogs/door_permissions_dialog.dart#L122) | <code>final (success, message) = await widget.authService.setDoorAccessOverride(</code> | Adım 1 — uygulama (yönetici ekranı): tek sakin için izin ver/engelle/sıfırla; toplu işlem setBulkDoorAccessOverride ile yapılır. |
| [lib/services/auth_api.dart:4222](../../lib/services/auth_api.dart#L4222) | <code>path: '/membership/doors/$doorId/permissions/bulk',</code> | Adım 2 — uygulama (HTTP): izin uçları /membership/doors/<id>/permissions (tekil) ve /permissions/bulk (toplu). |
| [server/src/routes/membership_routes.js:347](../../server/src/routes/membership_routes.js#L347) | <code>membershipRouter.post('/membership/doors/:id/permissions', authRequired, async (req, res)…</code> | Adım 3 — sunucu (rota): userCode zorunlu (400); setDoorAccessOverride çağrılır. |
| [server/src/services/membership_service.js:2131](../../server/src/services/membership_service.js#L2131) | <code>export async function checkDoorManagementAccess(authUser, doorId) {</code> | Adım 4 — sunucu (yetki): çağıran bu kapının yetkilerini yönetebilir mi (aksi 403); kapı yoksa 404. |
| [server/src/services/membership_service.js:2398](../../server/src/services/membership_service.js#L2398) | <code>INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed, granted_by_…</code> | Adım 5 — veritabanı: door_access_overrides (door_id, user_code) tekil satırı eklenir/güncellenir; isAllowed null ise satır silinir (varsayılana dönüş). |
| [server/src/services/door_service.js:398](../../server/src/services/door_service.js#L398) | <code>-- 2. Özel Kapı İzni (Manuel ek yetki verilmiş)</code> | Adım 6 — veritabanı (okuma): kapı listesi SQL'i ek izni yalnız üyeliği askıya alınmamış kullanıcı için sayar; is_allowed=FALSE satırı otomatik sakin yetkisini (3. kural) keser. Yetki gerçekten burada uygulanır. |
| [server/src/services/local_token_service.js:38](../../server/src/services/local_token_service.js#L38) | <code>export async function rotateTokensForDevices({ deviceIds, reason, throwOnError = false })…</code> | Adım 7 — sunucu: engelleme/sıfırlama sonrası kapıdaki cihazın yerel kontrol anahtarı yenilenir (eski yetkiyle yerel UDP açma sürmesin); hata fırlatmaz, yalnız günlüğe yazar. |
| [server/src/services/device_service.js:225](../../server/src/services/device_service.js#L225) | <code>export async function pushLocalControlTokenToDevice({ deviceUid, token, reason }) {</code> | Adım 8 — MQTT: yeni anahtar cihaz çevrimiçiyse device/<uid>/cmd ile local_control_config olarak yayınlanır; cihaz çevrimdışıysa gönderilmez (false). |
| [cihaz_kontrol/include/mqtt_baglanti.h:361](../../cihaz_kontrol/include/mqtt_baglanti.h#L361) | <code>} else if (action == "local_control_config") {</code> | Adım 9 — cihaz: yeni anahtar NVS'ye yazılır; eski anahtarla imzalanmış yerel açma isteği artık reddedilir. Bu davranışı bozmayın (sahada ESP32-C3). |
| [server/src/routes/app_doors_routes.js:161](../../server/src/routes/app_doors_routes.js#L161) | <code>appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (r…</code> | Adım 10 — sunucu (sonuç): bulut açma getAccessibleDoorForUser ile aynı SQL'e dayanır; yetkisiz kullanıcı 404 "Kapi bulunamadi." alır. |

**Olası nedenler**
- Halka 4: yönetici bu kapıyı yönetemiyor (403)
- Halka 6: sakinin üyeliği pasif (ek izin geçersiz sayılır) ya da kapının erişim kapsamı (access_scope) sakini kapsamıyor
- Halka 6: is_allowed=FALSE satırı var; sıfırlama (isAllowed null) yapılmadıkça sakin göremez
- Halka 8-9: cihaz çevrimdışıyken anahtar yenilemesi cihaza ulaşmaz; cihazda eski anahtar sürer

**Adım adım kontrol**
- door_access_overrides tablosunda door_id + user_code satırına bakın (salt-okunur SELECT)
- Sakinin kapı listesini (GET /app/my-doors) yenileyip kapı görünüyor mu doğrulayın
- Günlükte local_control_token_synced / local_control_token_sync_failed denetim kayıtlarını arayın
- Yerel açma sorunuysa akis-yerel-kapi-acma akışına geçin

**Günlükte aranacak ifadeler**
- `[LocalToken] Token döndürme başarısız:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a -E 'permissions|LocalToken|local_control'"
```

**Bkz.:** [akis-yerel-kapi-acma](60-akislar.md#akis-yerel-kapi-acma), [akis-bulut-kapi-acma](60-akislar.md#akis-bulut-kapi-acma), [akis-cihaz-envanter-ariza-degistirme](#akis-cihaz-envanter-ariza-degistirme)

<a id="akis-pdf-ciktilari"></a>
### akis-pdf-ciktilari · Kapı geçiş günlüğü PDF raporu akışı bozuldu (uçtan uca): "kapı geçiş kaydı bulunamadı", rapor eksik/kesik ya da PDF hiç oluşmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/src/services/door_service.js:90](../../server/src/services/door_service.js#L90) | <code>INSERT INTO door_access_logs (</code> | Adım 1 — veritabanı (kayıt yazımı, bulut/QR açmalar): sunucu kapı açma/QR işlemlerinde door_access_logs satırı yazar (recordDoorAccessLog). |
| [cihaz_kontrol/include/offline_log.h:26](../../cihaz_kontrol/include/offline_log.h#L26) | <code>inline constexpr char OFFLINE_LOG_FILE[] = "/offline_logs.ndjson";</code> | Adım 2 — cihaz (çevrimdışı kayıt): yerel/çevrimdışı geçişler cihazın LittleFS dosyasında NDJSON tutulur, 16 KB aşılırsa en eski kayıtlar atılır. Bu davranışı bozmayın (sahada ESP32-C3). |
| [server/src/mqtt_bridge.js:640](../../server/src/mqtt_bridge.js#L640) | <code>export async function handleDeviceLogsMessage(topicUid, text, deps = {}) {</code> | Adım 3 — MQTT/sunucu: device/<uid>/logs yayını çözülür ve toplu yazılır; yazma başarısızsa logs_ack GÖNDERİLMEZ, cihaz aynı paketi sonra yeniden yollar. |
| [server/src/services/door_log_service.js:381](../../server/src/services/door_log_service.js#L381) | <code>export async function insertDeviceLogBatch({</code> | Adım 4 — veritabanı: cihaz kayıtları door_access_logs'a yazılır (yinelenenleri önleyen şema ile); çok eski/geleceğe dönük zaman damgaları sınırlanır. |
| [lib/ui/pages/home_page.dart:5126](../../lib/ui/pages/home_page.dart#L5126) | <code>Future&lt;void&gt; _exportSiteLogsPdf(SiteRecord site) async {</code> | Adım 5 — uygulama (ekran): "haftalık geçiş raporu" son 7 günü seçer; kayıt yoksa "kapı geçiş kaydı bulunamadı" mesajı verilir ve PDF üretilmez. |
| [lib/ui/pages/home_page.dart:5052](../../lib/ui/pages/home_page.dart#L5052) | <code>Future&lt;({List&lt;DoorAccessLogRecord&gt; logs, String? error, bool truncated})&gt;</code> | Adım 6 — uygulama (sayfalama): kayıtlar sayfa başına 200, en fazla 25 sayfa çekilir; aşılırsa rapor "en yeni kayıtlarla sınırlandırıldı", hata olursa "rapor eksik olabilir" uyarısı çıkar. |
| [lib/services/auth_api.dart:2337](../../lib/services/auth_api.dart#L2337) | <code>final uri = Uri.parse('$baseUrl${_managementPrefix(role)}/door-logs')</code> | Adım 7 — uygulama (HTTP): rol ön ekiyle /manager/door-logs veya /admin/door-logs; tarihler UTC ISO olarak gönderilir. |
| [server/src/routes/door_log_routes.js:106](../../server/src/routes/door_log_routes.js#L106) | <code>doorLogRouter.get('/manager/door-logs', authRequired, requireSiteManager, async (req, res…</code> | Adım 8 — sunucu (rota): yalnız yöneticinin yönettiği sitelerin kayıtları (başka site 403); site, kapı, tarih, arama filtreleri; sayfa boyutu en fazla 200. |
| [lib/services/pdf_logs_service.dart:44](../../lib/services/pdf_logs_service.dart#L44) | <code>static Future&lt;Uint8List&gt; generateLogsPdf({</code> | Adım 9 — uygulama (PDF): Roboto yazı tipi indirilir/önbellekten alınır, sayfa dizgisi arka plan izolesinde yapılır; ardından Printing.layoutPdf ile yazdır/paylaş penceresi açılır. |

**Olası nedenler**
- Halka 1-4: kayıtlar hiç yazılmamış (cihaz çevrimdışıydı ve paket henüz gelmedi, ack bekleniyor) ya da seçilen tarih aralığı boş
- Halka 6: sayfa çekimi hata verdi (oturum/yetki) ya da 25 sayfa sınırı aşıldı
- Halka 8: yönetici o siteyi yönetmiyor; liste boş döner
- Halka 9: yazı tipi ilk kullanımda indirilemedi (ağ yok) ya da cihazda yazdırma/paylaşım hizmeti yok

**Adım adım kontrol**
- Aynı site için uygulamadaki günlük listesinde kayıt görünüyor mu bakın (PDF aynı uçtan beslenir)
- door_access_logs tablosunda site_code ve opened_at aralığını sayın (salt-okunur SELECT)
- Sunucu günlüğünde GET /manager/door-logs durum kodlarını ve "[MQTT Logs]" satırlarını arayın
- Cihaz seri günlüğünde çevrimdışı kayıt senkronunu doğrulayın

**Günlükte aranacak ifadeler**
- `[MQTT Logs] JSON parse hatasi`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 150 --nostream | grep -a -E 'door-logs|MQTT Logs'"
```

**İlgili testler:** [test/pdf_background_test.dart](../../test/pdf_background_test.dart)

**Bkz.:** [akis-pdf-giris-bilgileri-ve-surum-raporu](#akis-pdf-giris-bilgileri-ve-surum-raporu)

<a id="akis-pdf-giris-bilgileri-ve-surum-raporu"></a>
### akis-pdf-giris-bilgileri-ve-surum-raporu · Site giriş bilgileri PDF'i / cihaz sürüm raporu PDF akışı bozuldu (uçtan uca): PDF "site yapısı alınamadı" diyor, daire/kullanıcı listesi eksik ya da sürüm raporu boş

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:5007](../../lib/ui/pages/home_page.dart#L5007) | <code>Future&lt;void&gt; _exportSiteCredentialsPdf(SiteRecord site) async {</code> | Adım 1 — uygulama (ekran): "kullanıcı ve şifre raporu" önce site yapısını sunucudan ister; alınamazsa "Site yapısı ve daireler alınamadı." ve PDF üretilmez. |
| [lib/services/auth_api.dart:604](../../lib/services/auth_api.dart#L604) | <code>path: '${_managementPrefix(role)}/sites/$siteCode/structure',</code> | Adım 2 — uygulama (HTTP): rol ön ekiyle /manager/sites/<id>/structure veya /admin/sites/<id>/structure. |
| [server/src/routes/manager_routes.js:525](../../server/src/routes/manager_routes.js#L525) | <code>managerRouter.get('/manager/sites/:id/structure', authRequired, requireSiteManager, async…</code> | Adım 3 — sunucu (rota): yönetim yetkisi denetlenir, blok/daire/sakin yapısı döner. |
| [lib/services/pdf_credentials_service.dart:152](../../lib/services/pdf_credentials_service.dart#L152) | <code>static Future&lt;void&gt; printOrShareSitePdf({</code> | Adım 4 — uygulama (PDF): yapı verisinden PDF baytları üretilir ve Printing.layoutPdf ile açılır; dosya adı <site>_Giris_Bilgileri.pdf. PDF yalnız sunucunun yapı yanıtındaki alanları basar. |
| [lib/ui/pages/home_page.dart:4639](../../lib/ui/pages/home_page.dart#L4639) | <code>Future&lt;void&gt; _exportFirmwareReportPdf() async {</code> | Adım 5 — uygulama (sürüm raporu): şirket cihaz listesi (daha önce yüklenmiş sayfa) boşsa "Raporlanacak kayıtlı cihaz bulunamadı." mesajı verilir. |
| [server/src/routes/admin_routes.js:1353](../../server/src/routes/admin_routes.js#L1353) | <code>adminRouter.get('/admin/devices', authRequired, requireSuperUser, async (req, res) =&gt; {</code> | Adım 6 — sunucu (veri kaynağı): süper kullanıcının cihaz listesi (sayfalı) rapora girdi olur; yalnız yüklenen sayfadaki cihazlar raporlanır. |
| [lib/services/pdf_device_firmware_service.dart:69](../../lib/services/pdf_device_firmware_service.dart#L69) | <code>static Map&lt;String, String&gt; latestVersionsByTarget(List&lt;DeviceRecord&gt; devices) {</code> | Adım 7 — uygulama (PDF): hedef (esp32-c3/esp32-wroom) başına en yeni sürüm bulunur; cihazlar bu sürümle karşılaştırılıp güncel/eski ayrımı yapılır. |

**Olası nedenler**
- Halka 1-3: oturum süresi dolmuş (401) ya da yönetici bu siteyi yönetmiyor (403); yapı alınamaz
- Halka 5-6: cihaz listesi henüz yüklenmedi ya da yalnız ilk sayfa yüklü; rapor eksik görünür
- Halka 7: cihaz sürüm bilgisi (hardware_target/firmware_version) bildirmemiş; "bilinmiyor" grubuna düşer

**Adım adım kontrol**
- Aynı siteyi uygulamada açıp yapı/daire listesi görünüyor mu bakın
- Günlükte GET /manager/sites/<id>/structure ve GET /admin/devices durum kodlarına bakın
- Sürüm raporu için cihaz listesinde sürüm sütununun dolu olduğunu doğrulayın

**Günlükte aranacak ifadeler**
- `Site yapısı ve daireler alınamadı.`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a -E '/structure|/admin/devices'"
```

**Bkz.:** [akis-pdf-ciktilari](#akis-pdf-ciktilari)

