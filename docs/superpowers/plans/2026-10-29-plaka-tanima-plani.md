# Plaka Tanıma Sistemi — Plan ve El-Devri Dokümanı (2026-10-29)

Bu belge, konuya başka bir yapay zekâ ajanıyla (veya yeni bir oturumla) devam edilebilsin diye yazıldı.
Durum: PLANLAMA aşaması — kod yazılmadı. Sahibin 3 açık sorusuna cevap bekleniyor (en altta).

## 1. Senaryo (sahibin tarifi)
- IP kameralar (giriş + çıkış) PoE switch'e ya da kablosuz ağa bağlı; güvenlik kulübesinde aynı ağda bir Windows PC var, kameralar izlenebiliyor.
- İstenen: plaka kamerayla okunur → sistemde tanımlıysa geçiş verilir → log tutulur; çıkış kamerası aracı "çıktı" işaretler. Sonrası özellikleri bu plan tanımlar.

## 2. Verilen kararlar (sahiple konuşuldu)
- **YOLO kullanılmayacak (ilk sürüm).** "Yol A": tamamen klasik görüntü işleme — Sobel dikey kenar + morfoloji + kontur (TR plakası ~4.7:1 en-boy) → perspektif düzeltme + Otsu → karakter segmentasyonu → **kendi eğittiğimiz küçük karakter CNN'i** (34 sınıf: 0-9 + TR plaka harfleri, 28×28, ~1-2 MB, ONNX). Lisans derdi yok, her satır bizim. Saha %90 altında kalırsa detektör katmanı sonradan eklenir (o zaman Apache-2.0: RT-DETR/YOLOX; Ultralytics YOLO **AGPL — ticari üründe kullanma**).
- **Karar KENARDA, kayıt SUNUCUDA (offline-first).** Güvenlik PC'sindeki Windows uygulaması izin listesinin yerel kopyasını tutar (sunucudan periyodik delta senkron), kararı yerelde verir; olayları sunucuya asenkron bildirir (kopukta SQLite kuyruğu — Drive kuyruğu felsefesiyle aynı).
- **Kapıyı açan mevcut SmartKeyPass cihazıdır.** Cihazın YEREL kontrol anahtarıyla LAN'dan komut alma özelliği var (claim akışında veriliyor); PC aynı ağdan "aç" komutu gönderir → internetsiz de çalışır. Yeni açma donanımı yok.
- **Emniyet çizgisi:** yazılım yalnız "aç" der; kapanma/ezme emniyeti bariyerin kendi sensörünün işidir, asla "kapat" komutu verilmez.
- Doğrulama: ardışık 2-3 karede aynı okuma = teyit; 5 sn pencerede tekilleştirme; TR plaka regex: `^(0[1-9]|[1-7][0-9]|8[01])\s?[A-PR-VYZ]{1,3}\s?\d{2,4}$`.
- KVKK: kareler PC'de tutulmaz (yalnız olay); istenirse yalnız TANIMSIZ araç karesi X gün (site ayarı). Olay saklama süresi site ayarı. VERI_ENVANTERI'ne V-kaydı eklenecek.

## 3. Üründe HAZIR olan parçalar (yeniden yazma!)
- `vehicles` rota ailesi: daire/araç plaka kayıtları (Flutter ekranları dahil).
- `plate_recognition` (migration 073) + `plate-events` olay ucu + `camera_devices` (plaka kamerası kaydı, şifreli parola, belirteç) + `device_integrations_view` (Flutter) + kamera "Bağlantıyı sına" uçları (TCP probe, 2026-10-29).
- `cctv_cameras` (şifreli kimlik, kapı eşleme). Ziyaretçi modülü (misafir akışı için taban). Bildirim altyapısı (e-posta/uygulama içi). Site denetim kaydı kataloğu (`site_audit_log_catalog.js` — yeni eylemlere Türkçe başlık ZORUNLU, test bekçisi var).
- Windows araç kalıbı: `company_qr_tool` (Tkinter + `ui_kit.py`, tepsi/tek pencere deseni) — kenar uygulamasının ayar penceresi için emsal.

## 4. Aşamalar
- **A1 Sunucu:** olay modeline yön (giriş/çıkış) + karar (açıldı/red/tanımsız) + kamera-kapı eşlemesi; "içeride" durumu (giriş işaretler, çıkış düşürür) + içerideki araçlar/doluluk ekranı; kenar istemci için cihaz-anahtarlı izin-listesi delta senkron ucu; misafir plaka → süreli izin (ziyaretçi modülüne bağlan). Migration: depodaki EN BÜYÜK numara+1 (2026-10-29 itibarıyla son: 119; db.js sıra listesine ekleme zorunlu).
- **A2 Kenar (Windows):** Python 3.11 + ONNX Runtime CPU; OpenCV RTSP düşük fps (2-4) ya da tetikli tek kare; Yol A boru hattı; yerel izin listesi + karar; SmartKeyPass yerel "aç"; SQLite olay kuyruğu; `ayarlar.json` + Tkinter ayar penceresi ("Sına": kamera + sunucu erişimi); PyInstaller tek exe + NSSM Windows servisi.
- **A3 Güvenlik ekranı:** canlı olay şeridi; tanımsız araçta tek tuş "Misafir olarak aç / Açma"; sakine "aracınız giriş yaptı" bildirimi; çıkışı olmayan giriş / girişi olmayan çıkış raporu; kara liste.
- **A4 Saha (kullanıcı):** montaj (durma noktasına 2-4 m, hafif yukarıdan, IR aydınlatma), eşik kalibrasyonu, karakter CNN'i için birkaç yüz etiketli kare toplama (eğitim yerel/Colab; üründe yalnız ONNX gider).

## 5. Sahip cevapları ve kalan sorular
- **CEVAPLANDI (2026-10-29, soru 1):** Giriş ve çıkışta AYRI kamera olacak; ama topoloji sabitlenmez — YÖNETİCİ SEÇER. Tasarım: **"Geçiş noktası" (kapı) modeli** — her kapı bir kayıt: ad + yön modu (yalnız giriş | yalnız çıkış | çift yön) + bağlı kamera(lar) + bağlı SmartKeyPass cihazı. Site birden çok kapı tanımlayabilir; A1'deki kamera-kapı eşlemesi bu modelden türetilir. "Bilinmeyen durumlar" bu esneklikle karşılanır (örn. tek kameralı çift yön kapı: yön, içeride-mi durumundan çıkarılır).
Kalan sorular:
2. Tanımsız araçta varsayılan davranış: kesin açmama mı, güvenlik onayına düşürme mi?
3. İlk sürümde misafir-plaka akışı olsun mu, yoksa önce yalnız kayıtlı araç geçişi mi?

## 6. Bu depoda çalışmanın kuralları (başka ajan için zorunlu özet)
- Her iş: ayrı dal/worktree → hedefli test → main'e merge → commit+push (sormadan; kalıcı onay) → gerekirse dağıtım. Dağıtım akışı: `deploy/README.md` (prova PROVA_OK → activate → verify SORUNLU 0; web `build/web` takası canlı APK'yı koruyarak; APK: önce `flutter pub get`, `APK_EXIT` + mtime kontrolü).
- Kullanıcıya görünen her değişiklik `tools/deneme_listesi/platform.json` (SON bölümden sonra, iç madde no = bölüm no, yeni:true) + `SAHA_KONTROL_LISTESI.md`; `python tools/deneme_listesi/uret.py` assert'leri geçmeli. Faz sayfası yayını ana oturumun işi.
- Bekçi testler: `site_audit_log` (yeni denetim eylemine Türkçe başlık), `trial_access_guard` (yeni rota ailesine deneme ilkesi kararı), `hardware_pin_docs`, `deneme_ve_saha_listeleri`. Klavuz: `node tools/klavuz/build.mjs --check --fresh`.
- Sır/parola/fiyat depoya ASLA yazılmaz; sırlar DB'de AES-GCM (env anahtarı deseni: DRIVE_TOKEN_KEY / PAYMENT_SECRET_KEY / MESSAGING_SECRET_KEY emsalleri; .env.example'a yalnız AD). Güvenlik testleri gevşetilmez. Denemeleri kullanıcı yapar; emülatör/tarayıcı gezilmez.
- sed -i yasak (CRLF bozar) — Write/Edit ya da python ile düzenle. Worktree başlatmadan önce BÜYÜK harfli `cd /g/site/site_kapi_kontrol`.
