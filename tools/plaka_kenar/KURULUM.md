# AHBU Plaka Kenar Uygulaması — Kurulum (A2)

Güvenlik kulübesindeki Windows PC'de çalışır: IP kameralardan plaka okur, kararı **yerelde** (senkron edilen izin listesiyle) verir, kapıyı SmartKeyPass'in **yerel kontrol** protokolüyle açar, olayları sunucuya asenkron bildirir. Plan: `docs/superpowers/plans/2026-10-29-plaka-tanima-plani.md`.

## 1. Geliştirme / elle çalıştırma
1. Python 3.11 (64 bit). `calistir.bat` ilk çalıştırmada `.venv` kurar ve `requirements.txt`'i yükler.
2. `ayarlar.ornek.json` dosyasını `ayarlar.json` olarak kopyalayın **ya da** pencereden girin (pencere kaydedince dosyayı kendisi yazar). `ayarlar.json` sır içerir (cihaz anahtarı, SmartKeyPass yerel kontrol anahtarı, RTSP parolası) — `.gitignore`'dadır, depoya girmez.
3. `calistir.bat` → ayar penceresi, **sunucu/site/anahtar bilgisi girmeden** kullanılır: **Kameralar** (sınırsız satır; *Ağda kamera ara* = ONVIF WS-Discovery + yerel /24 alt ağ TCP taraması birlikte, ONVIF yanıt vermese bile bulunan IP + açık portlar listelenir; *El ile ekle* = IP ya da tam RTSP + kullanıcı/parola → RTSP şablon önerileri → Sına; her kameraya **yön: giriş / çıkış** verilir — çift yönlü kapıda biri giriş biri çıkış kamerası beklenir, eksikse satırda sarı uyarı çıkar, engel değildir; olay yönü kameranın yönünden alınır), **Canlı İzleme** (eklenen TÜM kameralar 1/2/4/6/9 karoluk mozaikte, karoya tıklayınca tek kamera + ROI), Canlı Olaylar, Yerel ayarlar, **Sunucu bağlantısı (isteğe bağlı)** (boş bırakılırsa olay gönderimi sessizce kapalı kalır). **Sına** düğmesi kameralardan tek kare alır, ayar uyarılarını ve tanıma motoru durumunu listeler. Tarama portları/zaman aşımı ve mozaik hızları `ayarlar.json` > `kesif` / `izleme` bölümlerindedir. Komut satırı: `calistir.bat --sina`.
4. Testler: `python -m unittest discover -s testler -t .` (kamera/ağ gerekmez).

## 2. KALİBRASYON MODU (varsayılan açılış)
`modeller/karakter.onnx` yoksa (ve `sablonlar/` onaylı/tam değilse) uygulama **kalibrasyon modunda** açılır: okumalar `dogrulanmamis` işaretlenir, **kapı hiçbir koşulda açılmaz**, sunucuya olay gönderilmez (sözleşmede "doğrulanmamış" karar türü yoktur). Pencerenin üstündeki şerit durumu gösterir.
- Çıkış: eğitilmiş ONNX modeli `modeller/karakter.onnx` yoluna koyun (`egitim/karakter_cnn_egit.py`; 33 sınıf, 28×28), ya da `sablonlar/<sınıf>/*.png` kapsamı tamamlanıp sahada doğrulanınca `tanima.sablon_onayli=true` yapın.
- Yeni modeli sahada denemek için `tanima.model_onayli=false` (yüklenir, okumalar doğrulanmamış kalır).
- Saha verisi toplamak için geçici olarak `karar.kalibrasyon_kare_kaydet=true` (yalnız perspektifi düzeltilmiş plaka kırpığı `veri/kalibrasyon/`'a yazılır; işiniz bitince kapatıp klasörü silin — KVKK).

## 3. Tek exe (PyInstaller)
Derleme makinesinde (`pip install pyinstaller`):
```
cd tools\plaka_kenar
pyinstaller --onefile --name plaka_kenar --collect-all onnxruntime baslat.py
```
`dist\plaka_kenar.exe` → `C:\AHBU\plaka_kenar\` klasörüne kopyalayın. `ayarlar.json`, `veri\`, `modeller\`, `sablonlar\` exe'nin yanında durur (yol çözümü exe klasörüne göredir).

## 4. Windows servisi (NSSM)
Ayarlar pencereden yapıldıktan sonra (servis çalışmıyorken `plaka_kenar.exe` ile pencereyi açın, Kaydet) — servis penceresiz çalışır (`--servis`):
```
nssm install PlakaKenar "C:\AHBU\plaka_kenar\plaka_kenar.exe" --servis
nssm set PlakaKenar AppDirectory "C:\AHBU\plaka_kenar"
nssm set PlakaKenar Start SERVICE_AUTO_START
nssm set PlakaKenar AppExit Default Restart
nssm set PlakaKenar AppRestartDelay 5000
nssm set PlakaKenar AppStdout "C:\AHBU\plaka_kenar\veri\servis.out.log"
nssm set PlakaKenar AppStderr "C:\AHBU\plaka_kenar\veri\servis.err.log"
nssm start PlakaKenar
```
Ayar değişikliğinden sonra `nssm restart PlakaKenar`. Günlük: `veri\plaka_kenar.log` (yalnız plaka + karar + kamera kodu; kare/kişisel veri yok).

## 5. Kamera montajı (plan A4 özeti)
1. Durma noktasına 2–4 m, plakaya hafif yukarıdan bakacak şekilde, aracın eksenine yakın.
2. IR aydınlatma (gece için); mümkünse kısa pozlama (hareket bulanıklığı) ve far parlamasına karşı WDR/HLC.
3. Yüksek çözünürlüklü ana akışı kullanın (uygulama zaten 2–4 kare/sn okur); giriş ve çıkış için ayrı kamera, eşik/ROI kalibrasyonu sahada `ayarlar.json` ile yapılır (kodda sabit değer yok).

## 6. SmartKeyPass yerel "aç" (gerçek protokol)
`docs/YEREL_KONTROL_V2.md` (UDP 8765, challenge'a bağlı HMAC-SHA256) birebir uygulanır: discover → `ch` → `{"action":"open", device_uid, ch, sig}`; `challenge` hatasında tek yeniden deneme; `unauthorized`/`role_mesgul` kesin ret. Yalnız `open`/`pulse` gönderilir, **"kapat" komutu yoktur**. Hedef yalnız özel ağ (RFC1918/link-local) olabilir. Cihaz kimliği ve yerel kontrol anahtarı kapı satırında (`skp_uid`, `skp_token`); anahtar ağa çıkmaz, günlüğe yazılmaz. İmza hesabı belgedeki bilinen-cevap vektörüyle test edilir.

## 7. Sunucu sözleşmesi (A1, sürüm 2)
Tam sözleşme: `docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md`. Kimlik: yönetici ekranında (Plaka Tanıma → Geçiş noktaları → Kenar istemci) üretilen anahtar `<id>.<48 onaltılık>` → `sunucu.cihaz_anahtari` (`Authorization: Bearer`). Anahtar hangi siteye bağlıysa kapsam odur; site kodu gerekmez. Yollar `ayarlar.json > sunucu.uclar` içindedir (`/edge/plate/v1/...`) ve **tek tek kapatılabilir**; her gövdede `schema_version` (2).
- `POST claim` açılışta bir kez; yanıttaki `intervals` (kalp atışı / senkron saniyesi) yerel aralık ayarının yerine geçer (site ayarı sunucudadır).
- `GET sync?updated_since&vehicles_rev&permits_rev&blacklist_rev`: araçlar, misafir izinleri, **kara liste**, daire kapasitesi (park yeri + içerideki sayı), "içeride" farkı. Bölüm `unchanged` ise yerel kopya geçerli. Gönderilmemiş yerel olay varken "içeride" görünümü uygulanmaz (yerel iyimser durum bozulmasın).
- `POST events` **tek olay**: `{schema_version, event_id, camera_id, plate, decision: acildi|red|tanimsiz|kara_liste, seen_at, direction, confidence, reason}`. `camera_id` sunucudaki kamera kimliğidir: her kamera satırına **`sunucu_id`** yazın (yoksa o kameranın olayı gönderilemez, ayar penceresi uyarır). `event_id` olay başına sabit, yeniden gönderimde idempotent. Geçici hatada (ağ, 5xx, 401/403) olay kuyrukta kalır; kalıcı 4xx olayı "hatalı" işaretler; kuyruk kayıtları `olay_saklama_gun` sonra silinir. Doğrulanmamış (kalibrasyon) okuma sunucuya **hiç gitmez**.
- `POST heartbeat`: kamera başına son kare / son okuma + kuyruk derinliği. Kenar PC veya kamera yönetici ekranındaki kırmızı eşiği aşarsa yöneticilere uygulama içi uyarı düşer (saatte en çok bir).
- Kara listedeki plaka **asla açılmaz** (olay: `kara_liste`). İçeride kalan kara listeli aracın çıkışına izin vermek için `karar.kara_liste_cikis_acilir=true` (varsayılan kapalı).

## 8. KVKK
Kareler yalnız bellekte işlenir. İstisna: `karar.tanimsiz_kare_sakla=true` ise **yalnız tanımsız** aracın karesi `veri/tanimsiz/`'a yazılır ve `tanimsiz_kare_gun` sonra silinir (varsayılan kapalı). Olay kuyruğu kayıtları `sunucu.olay_saklama_gun` sonra silinir. Günlüğe plaka dışında kişisel veri yazılmaz.
