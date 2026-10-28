# Karşılaştırma güçlendirme programı (2026-10-28)

Kaynak: Astra karşılaştırma raporu (5 mercek, 113 satır → 19 P1 / 31 P2 / 28 karar; oturum scratchpad `astra-karsilastirma/RAPOR.md`).
Amaç: raporun gösterdiği tüm eksikleri kapatmak, güçsüz yönleri güçlendirmek. Sahibin talimatı: "eksik olan tüm eksiklerimizi tamamla, güçsüz olan tüm yönlerimizi ekle güçlendir."

Çalışma kuralları:
- Her dalga: ayrı worktree'lerde işçiler → birleştirme + tam test → en az 1 inceleme turu → düzeltme → main'e merge → canlıya dağıtım (sunucu/web/APK gerekenine göre) → faz sayfası güncellemesi.
- Para/yetki dokunuşu olan dalgalar (B, G): en az 2 inceleme turu + gerçek PostgreSQL koşusu.
- Migration numarası: depodaki en büyük + 1'den devam (084 sonrası 085+). Finans kasa tasarımındaki 085-090 rezervi bu kurala göre kayar; `finans-kasa/TASARIM.md` uygulanırken numaralar yeniden verilir.
- Paylaşılan dosyalar (home_page.dart, yan_menu.dart, catalog.js): dalga içinde tek işçi dokunur.
- Deneme maddeleri: kullanıcıya görünen her değişiklik `tools/deneme_listesi/platform.json` + SAHA listesine işlenir (yeni:true).
- 2026-10-28 hızlandırma (sahibin talimatı: kullanım süresi ~24 saat): A dışındaki tüm dalgalar (G/B/C/D/E) PARALEL başlatıldı. Her dalga kendi dalında biter, main'e SIRALI merge'i ana oturum yapar (dalga iş akışları main'e dokunmaz). Dağıtım 2-3 toplu seferde (örn. A+G, B+C, D+E) — "her iş sonrası dağıtım" kuralının hızlandırılmış uygulaması.
- 2026-10-29 TOKEN KISITI (sahip: haftalik ~%33 kaldi; "asiri inceleme/deneme yok, isi bitirin, denemeleri ben yaparim"): inceleme TEK tur TEK mercek ve yalniz YUKSEK bulgular (G/B/F/H); C/D/E/I incelemesiz; dalga birlestirmelerinde TAM flutter paketi kosulmaz (analyze + degisen alan testleri), tam paket yalniz son dagitimdan once 1 kez ana agacta; isci testleri asgari (1-2 kritik yol). "Para/yetki isinde 2+ inceleme" kurali bu program icin sahip talimatiyla askiya alindi.
- Migration numara blokları (paralel çakışmayı önlemek için; kullanılmayan numara boş kalabilir, db.js uygulananı ada göre izler): G 085-086 (gerekmedikçe migration YOK), B 087-094, C 095-101, D 102-103, E 104-107, F 108-109, H 110-112, I 113+ (sıradaki boş). db.js sıra listesi çakışması numara sırasına göre birleştirilir.

## Dalgalar

### Dalga A — küçük P1'ler (karar gerektirmez) [BU OTURUMDA BAŞLADI]
- P1-9 saha ekranlarındaki bayat etiketler (+ P1-5'in "m²" etiket kısmı) — YALNIZ etiket yarısı yapıldı; raporun P1-9 ikinci yarısı (saha ekranında fotoğrafın nereye gittiğini gösteren Drive / sunucu / hiçbiri satırı) bilerek Dalga C'de P1-8 ile yapılır (aşağıya bkz.)
- P1-13 görünür "Ana sayfa" düğmesi
- P1-15 kapı dili: "açıldı!" → "komut gönderildi" (cihaz yanıtı zinciri ayrı iş, bu dalgada yalnız metin/akış dili)
- P1-17 server/.env.example eksik 8 SMS/NetGSM/Web Push ayar adı
- P1-18 BEKLEYEN_ISLER / SAHA_KONTROL_LISTESI donanım pin çelişkisi (device_konfig.h esas) + "kod kanıtı / saha kabulü" kutu ayrımı
- P1-19 tools/demo_seed m² kırığı (078 sonrası şema)

### Dalga G — güvenlik güçlendirme (2026-10-28 denetiminin yüksekleri; 2+ inceleme + gerçek PG)
- Claim-device / replace-device site kapsamı (SQL WHERE)
- 4 haneli ilk PIN için kalıcı deneme sınırı
- Toplu yükleme login-names/check kullanıcı adı/e-posta sayımının site kapsamına indirilmesi
- bcrypt olay döngüsü DoS (async), e-posta/SMS kod kaba kuvvet sınırları
- web-push URL allowlist; npm body-parser/nodemailer güncellemeleri
- (OTA imzalama ve VPS parola/geçmiş temizliği ayrı: sahibin kararları bekliyor)

### Dalga B — finans kuralları (P1 karar maddeleri; kararlar aşağıda; 2+ inceleme + gerçek PG + altın veri seti)
- P1-3 ödemenin kasasını yönetici seçer (tüm tahsilat yolları; K3)
- P1-2 kasa/demirbaş tahakkuku ↔ Karar Defteri bağı (K2)
- P1-1 kiracı borcunun malike devri + çıkış öncesi bildirim (K1)
- P1-4 fazla ödemenin onaylı iadesi (K4)
- P1-5 ısı payı/dağıtım tabanını yönetim seçer, varsayılan eşit (K5)
- P2-1 sakin "Borçlarım" kalem dökümü (karar no ile; P1-2'ye bağlanır)
- P2-4 açılış bakiyesi genişletmesi (alacaklı devir: K16)
- C-26 banka güçlü eşleşmelerinde "tek tek gözden geçir" seçeneği

### Dalga C — saha paketleri
- P1-6 + P1-7 sayaç saha akışı (blok seç → çekilenler → yeniden çekim) + sıçrama uyarısı (K12: eşik site ayarı, varsayılan son 3 dönem medyanı × 5)
- P1-10 iş kaydı ↔ ekipman bağı (önce/sonra fotoğraf, servis geçmişi)
- P1-11 dosya adında kayıt kimliği + Drive kaydının kaynak kayda bağı
- P1-8 silme kuralı (K6): Drive kuyruğunda otomatik silme kalkar (bekliyor + yönetici uyarısı + kota dolunca yeni yükleme reddi); telefon fotoğraf kopyası kabulde otomatik silinmez
  - **+ P1-9 ikinci yarısı (Dalga A'dan devredildi): saha ekranında "fotoğraf nereye gitti" satırı** (Drive / sunucu / hiçbiri). Neden burada: satır, sunucu yanıtındaki `photo.storage` değerinin istemcide okunmasını gerektirir (bugün `meter_field_queue.dart` `postFieldReading` sonucunu okumuyor; `FieldReadingResult.photoStorage` hazır) ve bu, P1-8'in "fotoğraf ulaşmadı" rozetiyle AYNI veridir. Tek başına eklenmez: P1-8'in "telefon kopyası yalnız `storage` drive / server dönünce silinir" kuralı olmadan satır, fotoğraf telefondan zaten silindikten sonra kaybı bildirirdi (bugün `meter_field_queue.dart` kabulde kopyayı siliyor). Sahadaki görevli yönetici ucunu (`GET /manager/sites/:siteCode/drive`) okuyamaz: bağlantı durumu önceden değil, gönderim sonucundan ya da sayaç saha uçlarına eklenecek bir ipucundan gelmelidir. Dalga C P1-6/P1-7 ile `meter_field_view.dart`'ı zaten yeniden kurar; satır aynı değişiklikte eklenir (ayrı parça bırakmak iki kez dokunmak olurdu).
- P2-6 fotoğraf daire etiketi uyuşmazlık uyarısı; P2-7 kayıt ↔ dosya kimliği izi; P2-9 onaylı kayıt kilidi/revizyon (K14: yeni sürüm + önceki bağ); P2-10 teklif karşılaştırma alanları; P2-11 yönetilebilir kategoriler

### Dalga D — arayüz
- P1-16 yetenek/menü katman ayrımı (K8): site başına "kompakt menü" + "Tüm işlemler" ekranı; çekirdek yetenekler her sitede açık kalır
- P1-14 sayfa bağlamlı "Geri bildirim" (K11: 4 dosya × 5 MB, toplam 20 MB)
- P2-21 bağlam şeridi + boş/hata/bağlı-değil üçlüsü; P2-22 Liste↔Kutucuk anahtarı; P2-23 yöneticiyi/112'yi dokun-ara (K13); P2-25 "Kolay görünüm"; P2-26 Çıkış↔Yenile ayrımı + son güncelleme saati

### Dalga E — kişi, kapsam, süreç
- P1-12 çoklu malik (K7: tüm malikler kayıtlı, hesap muhatabı tek; migration)
- P2-15 kurulum sihirbazı; P2-16 "Excel'den yükle" kısayolu; P2-14 kaynak belge ↔ kayıt izi
- P2-24 acil yardım akışı (112, kuru mod; yangın/asansör ayrı düğme)
- P2-27 deneme erişimi tek kullanımlık kod (K10: 72 saat, demo siteye kilitli)
- P2-19 yönetici kendi sitesinin işlem kayıtları; P2-29 Komşu Panosu istemci sınır testleri; P2-31 A-E durum sözlüğü + ekran envanteri; P2-28 README/teknik not bayatlıkları
- P2-30 `astra/yerel-kabul` → yalnız `tools/yerel/yalitim` seçmeli alınır (satır satır inceleme sonrası)

### Dalga F — OTA imza (sahip onayı 2026-10-28) [BAŞLATILDI 2026-10-28]
- Ed25519 imza araç zinciri `tools/ota_imza` (özel anahtar repo DIŞI; firmware'e yalnız public key gömülür)
- Sunucu: yeni OTA paketlerinde imza zorunlu (yüklemede doğrulama + imza meta + sürüm düşürme koruması); mevcut paketler geçiş için sunulabilir kalır
- Firmware: OTA yazmadan önce imza doğrulama (ilk imzalı sürümden itibaren zorunlu); sahadaki cihazlar için geçiş planı (imzasız→imzalı tek köprü sürüm)
- Belgeler + SAHA/deneme maddeleri; kart yazma ve saha denemesi kullanıcıda
- 2 inceleme turu (güvenlik işi). Migration bloğu: 108-109 (gerekirse)

### Dalga H — karar-sonrası kuyruk [tetik: B ve C main'e girince; betik hazır: oturum scratchpad `dalga-h.js`]
- P2-20 kararı: gider/dekont "kontrol edildi (kim, ne zaman)" izi (rol açılmaz; migration 110)
- P2-3 dönemsel finans rapor paketi · P2-5 ikinci altın veri seti + örnek site (gerçek PG)
- P2-8 taşeron formu + P2-12 firmaya yönlendirme (migration 111)
- P2-13/K15: cihaz-içi ML Kit belge okuma (görüntü/metin ağa çıkmaz; öneri olarak ön-doldurma)
- VERI_ENVANTERI yeni/birleşen modül V-kayıtları · PLATFORM_YOL_HARITASI'na K1-K18 + sahip kararları (fiyat rakamı ve parola YAZILMAZ)

### Dalga I — P3 ve süpürme [tetik: tüm dalgalar (F, H dahil) main'de; betik hazır: oturum scratchpad `dalga-i.js`]
- Triyaj: rapor P3 maddeleri + BEKLEYEN_ISLER + yol haritası açıkları + planın koşulu kalkan ertelenenleri; "zaten yapılmış" kod kanıtıyla elenir
- Karar/dış hesap/avukat/donanım gerektirmeyen HER iş uygulanır; kalanlar gerekçeli tek listede raporlanır

### Ertelenen / karara veya dış koşula bağlı (gerekçeli)
- P2-2, P2-17, P2-18 (Drive canlı değil; D2 Drive işi öncesi P1-11 şart) · P2-13 (yalnız cihaz-içi ML Kit; dış AI için avukat görüşü K15) · P2-3 dönemsel rapor paketi, P2-5 ikinci altın veri seti + örnek site, P2-8/12 taşeron formu ve yönlendirme (sıra E sonrası kuyruk).

### Sahip kararları (2026-10-28, soruldu ve seçildi)
- VPS parolası / depo görünürlüğü / geçmiş temizliği: "ŞİMDİLİK DOKUNMA" — risk kabul edildi; "satışa hazır" aşamasında hukuk bayrağıyla birlikte yeniden sorulacak.
- Tanıtım sitesi fiyat çelişkisi: Belgeler + Anket "pakete dahil" gösterilecek, ayrı fiyat (Belgeler 5 TL) kalkar; ana fiyat değişmez. → Bu oturumda ayrı ajanla uygulanıyor (g:/site/gudeteknoloji_com_tr).
- OTA imzalama: ONAYLANDI → dalgalar bitince "Dalga F — OTA imza" (firmware imza + cihaz doğrulaması + sunucuda imzasız paket reddi + sahadaki cihazlar için geçiş planı).
- P2-20 muhasebeci rolü: ROL YOK; bunun yerine gider/dekont belgesine "kontrol edildi (kim, ne zaman)" alanı — Dalga B merge SONRASI küçük iş (finans dosya çakışması bitince).
- K9 Hesap/Kasa: Hesap kesin. · K17: ayar kalır + "kiracı vermezse malik öder" kuralı (yukarıda).
- A7 AHBU: AHBU ayrı marka olarak KALIR — Ev Otomasyonu tanıtımına iş çıkmaz, madde kapandı.
- iOS: şimdilik Android+Web; Apple Developer hesabı açılınca iOS tek paket halinde yapılır.

## Kararlar (sahibin "standarda göre karar ver" kalıcı talimatıyla; rapor önerileri esas)
- K1 (P1-1): Hesap modeli korunur; "malike devret" açık, yönetici onaylı, izli ve geri alınabilir eylem + kiracı çıkışı öncesi malike borç bildirimi. Bildirim/devir metinleri AVUKAT_KONTROL_LISTESI'ne eklenir.
- K2 (P1-2): Karar Defteri modülü açık sitede demirbaş/fon tahakkuku karar kaydına bağlanmak zorunda; kapalı sitede zorunlu serbest metin gerekçe.
- K3 (P1-3): Yazılım ödemeyi kendiliğinden kasaya atamaz. Tek tür borçta önerilen kasa seçili gelir (değiştirilebilir); iki tür borçta seçim zorunlu. Dekont onayı ve banka içe aktarma dahil tüm yollara uygulanır.
- K4 (P1-4): İade: fazla ödeme varsayılan alacak; iade yönetici onaylı, kasadan çıkış kaydı + iz + makbuz.
- K5 (P1-5): Dağıtım/ısı payı tabanını yönetim seçer; varsayılan EŞİT; kod formül seçmez. %70/30 mevzuat teyidi avukat listesine.
- K6 (P1-8): "Silmeyi biz yapmayız": otomatik silme kaldırılır; bekleyen dosya + yönetici uyarısı; kota dolunca yeni yükleme reddi. Sunucu geçici dosyası yalnız Drive teyidi SONRASI silinir (C-28); kullanıcı cihaz kopyası asla otomatik silinmez.
- K7 (P1-12): Çoklu malik "tüm malikler kayıtlı + tek hesap muhatabı" modeliyle.
- K8 (P1-16): Yetenek (çekirdek, her sitede açık) ↔ menü yerleşimi (site başına kompakt küme + "Tüm işlemler") ayrılır; kompakt kümenin varsayılanı yönetim türü önerilerinden türetilir. Fiyat/paket etkisi sahibin kararı olarak açık kalır.
- K9 — SAHİP TEYİDİ (2026-10-28): "Hesap" adları kesinleşti (İşletme / Fon); "Kasa" terimine geçilmeyecek.
- K10 (P2-27): Deneme erişimi 72 saat, demo siteye kilitli, deneme verisinde işlem serbest.
- K11 (P1-14): Geri bildirim eki 4 dosya, dosya başı 5 MB, toplam 20 MB; gönderen ekran bağlamı otomatik eklenir.
- K12 (P1-7): Sıçrama eşiği site ayarı; varsayılan son 3 dönem medyanının 5 katı.
- K13: Acil numara 112; kanal bağlanana dek kuru mod; yangın/asansör ayrı hızlı düğme (sahibin teyidi (b) ile uyumlu).
- K14 (P2-9): Revizyon modeli: yeni sürüm + önceki sürüme bağ (zeyilname yerine).
- K15 (P2-13): Belge okuma yalnız cihaz-içi (ML Kit); dış yapay zekâya gönderim avukat görüşü olmadan yapılmaz (KVKK m.9).
- K16 (C-21): Alacaklı devir bakiyesi Dalga B'de desteklenir (OPENING_CREDIT_UNSUPPORTED kalkar; altın veri setine senaryo eklenir).
- K17 (C-24) — SAHİP TEYİDİ + EK (2026-10-28): Ayar KALIR (Malik/Kiracı/İkisi). Sahibin eki: "Borç mutlaka tahsil edilir; kiracı vermezse mal sahibi öder." Uygulama: geciken kiracı borcu için malike devir YALNIZ çıkışta değil, gecikmede de yönetici önüne açıkça önerilir (K1'in onaylı/izli/geri alınabilir deseniyle). Dalga B b2 (fin/devir-iade) kapsamı; birleştirme/incelemede bu kural denetlenecek, eksikse tamamlanacak.
- K18 (C-25): Ay ortası GİRİŞTE ayın tamamının malike yazılması mevcut davranış olarak korunur; bilgi notu faz sayfasına.

## Durum izleme
- Dalga A: 2026-10-28 başladı.
- Dalga G/B/C/D/E: 2026-10-28 paralel başlatıldı (hızlandırma).
- Dalga A inceleme turu (2026-10-28): 15 bulgu işlendi. Düzeltilenler: SAHA 25.4 kapı bildirimi, arıza klavuzu `ui-kapi-ac-basari-tiki`, m² kalıntıları (DEMO_SENARYOSU, SAHA 72.3-72.5, F2.04/F2.11/F13.03-F13.05/F30.57), F28.13/F28.15/F28.17/F28.19 metinleri, İşletme Projesi ayrıntısında "Ana sayfa" için kaydedilmemiş tutar onayı (TASARIM_DILI konum + istisna kuralı), `tools/demo_seed` hedef koruması (`--allow-target`). Bilerek ertelenen: P1-9 ikinci yarısı (Dalga C, P1-8 ile).
- Dalga A main'e alındı (2026-10-28, merge). Dağıtım: G ile birlikte toplu sefer 1.
- Dalga G main'de (397f644) ve 1. DAGITIM CANLIDA (2026-10-29, TS 20261029_020707): sunucu PROVA_OK+ACTIVATE_OK+verify temiz (migration 085, body-parser/nodemailer guncel), web takasi dogrulandi (main.dart.js 9.966.596), faz sayfasi v31 (593 madde, F39 guvenlik 13 madde). APK derlemesi arka planda, bitince canli APK degisecek. G slim inceleme: 0 yuksek bulgu.
- Dalga D main'de (260774f, 2026-10-29): K8 menu katmani (mig 102) + geri bildirim (mig 103) + serit/cikis/gorunum/dokun-ara; D bolumleri F40-F44 + SAHA 117-121'e kaydirildi (G=F39/116). NOT: yeni sunucu yayininda mevcut sitelere kompakt menu gelir (hicbir yetenek kapanmaz, 'Tum islemler'de); rehearse/verify betiklerine ok102/ok103 2. dagitimda eklenecek; feedback ekleri dizini backup_db.sh kapsamina alinacak. 2. dagitim B+C+E bekliyor.
- Sahip (2026-10-28): "karar kalmadıysa yapılacak iş bırakma" → Dalga F başlatıldı; H (tetik: B+C main'de) ve I (tetik: hepsi main'de) betikleri hazır; tanıtım sitesi fiyat ajanı çalışıyor (80 TL birleşik fiyat + Belgeler/Anket dahil).
- Her dalga bitişinde: bu dosyada işaret + PLATFORM_YOL_HARITASI karar bölümüne K-maddeleri + faz sayfası (uret.py) + karşılaştırma sayfası güncellenir.
