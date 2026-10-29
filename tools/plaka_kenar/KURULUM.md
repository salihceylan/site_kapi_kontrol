# AHBU Plaka Kenar Uygulaması — Kurulum (A2)

Güvenlik kulübesindeki Windows PC'de çalışır: IP kameralardan plaka okur, kararı **yerelde** (senkron edilen izin listesiyle) verir, kapıyı SmartKeyPass'in **yerel kontrol** protokolüyle açar, olayları sunucuya asenkron bildirir. Plan: `docs/superpowers/plans/2026-10-29-plaka-tanima-plani.md`.

## 1. Geliştirme / elle çalıştırma
1. Python 3.11 (64 bit). `calistir.bat` ilk çalıştırmada `.venv` kurar ve `requirements.txt`'i yükler.
2. `ayarlar.ornek.json` dosyasını `ayarlar.json` olarak kopyalayın **ya da** pencereden girin (pencere kaydedince dosyayı kendisi yazar). `ayarlar.json` sır içerir (cihaz anahtarı, SmartKeyPass yerel kontrol anahtarı, RTSP parolası) — `.gitignore`'dadır, depoya girmez.
3. `calistir.bat` → ayar penceresi: Genel (sunucu, misafir kuralı, tanımsız kare), Kameralar ve Kapılar (sınırsız satır), Canlı Olaylar. **Sına** düğmesi her kameradan tek kare alır, sunucuya TCP bağlanır, ayar uyarılarını ve tanıma motoru durumunu listeler. Komut satırı: `calistir.bat --sina`.
4. Testler: `python -m unittest discover -s testler -t .` (kamera/ağ gerekmez).

## 2. KALİBRASYON MODU (varsayılan açılış)
`modeller/karakter.onnx` yoksa (ve `sablonlar/` onaylı/tam değilse) uygulama **kalibrasyon modunda** açılır: okumalar `dogrulanmamis` işaretlenir, **kapı hiçbir koşulda açılmaz**, sunucuya olay gönderilmez (`sunucu.dogrulanmamis_olay_gonder=false`). Pencerenin üstündeki şerit durumu gösterir.
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

## 7. Sunucu sözleşmesi (A1 ile uzlaşılacak taslak)
Yollar `ayarlar.json > sunucu.uclar` içindedir ve **tek tek kapatılabilir** (sunucu hazır değilken `sunucu.etkin=false` ya da uç bazında `etkin=false`). Başlıklar `X-Site-Kodu` / `X-Cihaz-Anahtari` (adları ayarlanabilir); her gövdede `schema_version`.
- `POST …/register` kamera+kapı listesi (token yok) · `GET …/sync?imlec=` delta: `{imlec, devam?, araclar:[{plaka, daire_id, tur: sakin|misafir, gecerli_bitis, kara_liste, iceride, silindi}], daireler:[{daire_id, park_yeri, iceride}]}`
- `POST …/events` `{olaylar:[{event_id, zaman, kamera_id, kapi_id, yon, plaka, guven, karar: acildi|red|tanimsiz|acma_basarisiz, neden, arac_tur}]}` — `event_id` ile idempotent; 5xx/ağ hatasında SQLite kuyruğundan artan aralıkla yeniden denenir.
- `POST …/heartbeat` kamera başına durum/son kare/son okuma + kuyruk sayıları (kalp atışı 90 sn).

## 8. KVKK
Kareler yalnız bellekte işlenir. İstisna: `karar.tanimsiz_kare_sakla=true` ise **yalnız tanımsız** aracın karesi `veri/tanimsiz/`'a yazılır ve `tanimsiz_kare_gun` sonra silinir (varsayılan kapalı). Olay kuyruğu kayıtları `sunucu.olay_saklama_gun` sonra silinir. Günlüğe plaka dışında kişisel veri yazılmaz.
