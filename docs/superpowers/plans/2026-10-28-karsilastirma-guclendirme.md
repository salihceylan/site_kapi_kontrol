# Karşılaştırma güçlendirme programı (2026-10-28)

Kaynak: Astra karşılaştırma raporu (5 mercek, 113 satır → 19 P1 / 31 P2 / 28 karar; oturum scratchpad `astra-karsilastirma/RAPOR.md`).
Amaç: raporun gösterdiği tüm eksikleri kapatmak, güçsüz yönleri güçlendirmek. Sahibin talimatı: "eksik olan tüm eksiklerimizi tamamla, güçsüz olan tüm yönlerimizi ekle güçlendir."

Çalışma kuralları:
- Her dalga: ayrı worktree'lerde işçiler → birleştirme + tam test → en az 1 inceleme turu → düzeltme → main'e merge → canlıya dağıtım (sunucu/web/APK gerekenine göre) → faz sayfası güncellemesi.
- Para/yetki dokunuşu olan dalgalar (B, G): en az 2 inceleme turu + gerçek PostgreSQL koşusu.
- Migration numarası: depodaki en büyük + 1'den devam (084 sonrası 085+). Finans kasa tasarımındaki 085-090 rezervi bu kurala göre kayar; `finans-kasa/TASARIM.md` uygulanırken numaralar yeniden verilir.
- Paylaşılan dosyalar (home_page.dart, yan_menu.dart, catalog.js): dalga içinde tek işçi dokunur.
- Deneme maddeleri: kullanıcıya görünen her değişiklik `tools/deneme_listesi/platform.json` + SAHA listesine işlenir (yeni:true).

## Dalgalar

### Dalga A — küçük P1'ler (karar gerektirmez) [BU OTURUMDA BAŞLADI]
- P1-9 saha ekranlarındaki bayat etiketler (+ P1-5'in "m²" etiket kısmı)
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

### Ertelenen / karara veya dış koşula bağlı (gerekçeli)
- P2-2, P2-17, P2-18 (Drive canlı değil; D2 Drive işi öncesi P1-11 şart) · P2-13 (yalnız cihaz-içi ML Kit; dış AI için avukat görüşü K15) · P2-20 muhasebeci rolü (rol kararı sahibde) · P2-3 dönemsel rapor paketi, P2-5 ikinci altın veri seti + örnek site, P2-8/12 taşeron formu ve yönlendirme (sıra E sonrası kuyruk) · OTA imza, VPS parolası/geçmiş temizliği, depo görünürlüğü (sahip kararı) · A7 AHBU/Ev Otomasyonu tanıtımı (sahip kararı).

## Kararlar (sahibin "standarda göre karar ver" kalıcı talimatıyla; rapor önerileri esas)
- K1 (P1-1): Hesap modeli korunur; "malike devret" açık, yönetici onaylı, izli ve geri alınabilir eylem + kiracı çıkışı öncesi malike borç bildirimi. Bildirim/devir metinleri AVUKAT_KONTROL_LISTESI'ne eklenir.
- K2 (P1-2): Karar Defteri modülü açık sitede demirbaş/fon tahakkuku karar kaydına bağlanmak zorunda; kapalı sitede zorunlu serbest metin gerekçe.
- K3 (P1-3): Yazılım ödemeyi kendiliğinden kasaya atamaz. Tek tür borçta önerilen kasa seçili gelir (değiştirilebilir); iki tür borçta seçim zorunlu. Dekont onayı ve banka içe aktarma dahil tüm yollara uygulanır.
- K4 (P1-4): İade: fazla ödeme varsayılan alacak; iade yönetici onaylı, kasadan çıkış kaydı + iz + makbuz.
- K5 (P1-5): Dağıtım/ısı payı tabanını yönetim seçer; varsayılan EŞİT; kod formül seçmez. %70/30 mevzuat teyidi avukat listesine.
- K6 (P1-8): "Silmeyi biz yapmayız": otomatik silme kaldırılır; bekleyen dosya + yönetici uyarısı; kota dolunca yeni yükleme reddi. Sunucu geçici dosyası yalnız Drive teyidi SONRASI silinir (C-28); kullanıcı cihaz kopyası asla otomatik silinmez.
- K7 (P1-12): Çoklu malik "tüm malikler kayıtlı + tek hesap muhatabı" modeliyle.
- K8 (P1-16): Yetenek (çekirdek, her sitede açık) ↔ menü yerleşimi (site başına kompakt küme + "Tüm işlemler") ayrılır; kompakt kümenin varsayılanı yönetim türü önerilerinden türetilir. Fiyat/paket etkisi sahibin kararı olarak açık kalır.
- K9: "Kasa" sözcüğü değil mevcut "Hesap" adları korunur (İşletme / Fon); nihai ad sahibin teyidine açık.
- K10 (P2-27): Deneme erişimi 72 saat, demo siteye kilitli, deneme verisinde işlem serbest.
- K11 (P1-14): Geri bildirim eki 4 dosya, dosya başı 5 MB, toplam 20 MB; gönderen ekran bağlamı otomatik eklenir.
- K12 (P1-7): Sıçrama eşiği site ayarı; varsayılan son 3 dönem medyanının 5 katı.
- K13: Acil numara 112; kanal bağlanana dek kuru mod; yangın/asansör ayrı hızlı düğme (sahibin teyidi (b) ile uyumlu).
- K14 (P2-9): Revizyon modeli: yeni sürüm + önceki sürüme bağ (zeyilname yerine).
- K15 (P2-13): Belge okuma yalnız cihaz-içi (ML Kit); dış yapay zekâya gönderim avukat görüşü olmadan yapılmaz (KVKK m.9).
- K16 (C-21): Alacaklı devir bakiyesi Dalga B'de desteklenir (OPENING_CREDIT_UNSUPPORTED kalkar; altın veri setine senaryo eklenir).
- K17 (C-24): Daire bazında "borç muhatabı = Malik/Kiracı/İkisi" ayarı KALIR (canlı davranış + F2.05 deneme maddesi bunu belgeliyor; kaldırmak davranış kırar). Sahibin "kiracı varsa kiracı öder" sözüyle çelişki görülürse tek commit'le kaldırılabilir — teyide açık.
- K18 (C-25): Ay ortası GİRİŞTE ayın tamamının malike yazılması mevcut davranış olarak korunur; bilgi notu faz sayfasına.

## Durum izleme
- Dalga A: 2026-10-28 başladı.
- Her dalga bitişinde: bu dosyada işaret + PLATFORM_YOL_HARITASI karar bölümüne K-maddeleri + faz sayfası (uret.py) + karşılaştırma sayfası güncellenir.
