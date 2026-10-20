# Demo senaryosu: iki haftada bir 15 dakika (2026-10-21)

İki haftada bir yapılan canlı ekran demosu için sabit akış (karar G15, `komutlar` talimat 5). Amaç: işverene ve ekibe sistemin
bugün ne yaptığını gerçek ekranlarda göstermek, yeni gelenleri öne çıkarmak, geri bildirimi aynı gün kayda geçirmek.

Ekran adları 2026-10-21'deki uygulamaya göredir. Dalga 1 ile menü başlıklara ayrılır (Ana sayfa, Daireler, Borçlar, Tahsilat, Giderler,
İletişim, Raporlar, Site hizmetleri; Ayarlar sağ üstte dişli) ve sakinin alt çubuğu gelir (Özet, Duyuru, Arıza, Kapı, Belgeler). Ekran
yerleri değişince bu belgedeki adımlar da güncellenir (bölüm 6).

## 1. Kurallar

- **Gerçek kişi verisi gösterilmez.** Demo, uydurma adlı bir **demo sitesinde** yapılır. Ekran paylaşımında gerçek sitelerin kişi, borç,
  plaka ya da adres bilgisi görünmez (KVKK; mağaza görüntüleri için de aynı kural: `docs/YAYIN_HAZIRLIGI.md` bölüm 7).
- **"Yakında…" olan çalışıyor gibi gösterilmez.** Kartla ödeme, SMS, Drive, telefon bildirimi gibi dış hesap bekleyen özellikler
  "Yakında…" olarak gösterilir ve öyle anlatılır.
- **Hukuk onayı bekleyen özellik açılmaz.** Gecikme tazminatı ve borç hatırlatma uygulamada "Hukuk onayı bekleniyor" der; demo
  için açılmaz (`docs/yasal/AVUKATA_GECIKME_HATIRLATMA_MAKBUZ.md`).
- **Kapı:** demo sitesinde bağlı bir kapı cihazı yoksa kapı açma gösterilmez; Kapılar ekranı yalnız gezilir. Kapı ayarlarına demo için
  dokunulmaz.
- **Süre sınırı:** her bölümün süresi yazılıdır; aşan bölüm kısaltılır, soru sonda alınır.

## 2. Hazırlık

### 2.1 Bir kez (demo sitesi)

1. Süper kullanıcı bir demo sitesi kurar (ör. "Örnek Sitesi"; 2 blok, 24 daire). Daire künyesine m² ve arsa payı girilir.
2. Kişiler **Toplu Yükle** ile uydurma adlarla doldurulur (malik, kiracı; birkaç araç).
3. Modüller ekranından demo sitesinde şu modüller açılır: Aidat ve Finans, Belgeler (Dosya Deposu), İş Takibi, Rezervasyon ve
   Konsiyerj, Ziyaretçi ve Kargo, Firma ve Sözleşme Takibi, Karar Defteri. (Kişi ve Daire Kayıtları ile Duyuru ve Bildirim her sitede
   zaten açıktır.) **Anket ve Oylama kapalı bırakılır:** süper kullanıcı bölümünde canlı açılacak; demodan sonra yeniden kapatılır.
4. Üç demo hesabı: **yönetici**, **sakin (kiracı)** ve **süper kullanıcı**. Sakin hesabı bir daireye bağlı olmalı; taşınma tarihi
   geçmiş bir ay olsun (Borcum o tarihten itibaren gösterir).
5. Örnek veriler: aylık aidat tanımı (arsa payına göre dağıtım) ve geçmiş bir ayın borçlandırması; iki tahsilat (makbuzlu); bir gider
   ve belgesi; bir açık talep (fotoğraflı); bir duyuru; bir kesinleşmiş karar.
6. Parolalar bir parola yöneticisinde tutulur; bu belgeye ya da sohbete yazılmaz.

### 2.2 Demo günü sabahı

- [ ] Sunucu ayakta: uygulama açılıyor, giriş yapılıyor.
- [ ] Üç hesapla giriş denendi (yönetici web'de ya da bilgisayarda, sakin telefonda, süper kullanıcı ikinci tarayıcıda).
- [ ] Telefon şarjlı, ekranı paylaşılabiliyor; bildirimler sessizde.
- [ ] Demo sitesinde Anket ve Oylama kapalı (süper kullanıcı bölümünde açılacak).
- [ ] "Bu iki haftada yeni" listesi hazır (en çok 3 madde; bölüm 4).
- [ ] Yedek plan hazır (bölüm 5).

## 3. Akış (15 dakika)

### 0:00-1:00 Açılış

- Bu iki haftada ne bitti, ne canlıya çıktı (bir cümle). Bugün gösterilecek üç bölüm: yönetici, sakin, süper kullanıcı.

### 1:00-6:00 Yönetici (5 dakika)

1. Giriş: **Panel** açılır; yöneticiye tanımlı modüller kartlar hâlinde dizili.
2. **Kişiler → Daireler:** bir dairenin künyesi (m², arsa payı), maliki ve kiracısı.
3. **Finans → Tanımlar:** aylık aidat tanımı; **Borçlandır** ile yeni ayın borcu (önizleme, sonra "Onayla ve Borçlandır"). Dağıtımın
   arsa payına göre bölündüğü önizlemede görünür.
4. **Tahsilat Ekle:** bir daireye ödeme girilir; makbuz kendiliğinden düzenlenir (numara MK-yıl-sıra); **Makbuzlar**dan makbuz açılır.
5. **Finans → Raporlar:** yaşlandırma ya da gelir-gider; **Dışa Aktar** ile Excel.
6. **Duyurular → Yeni Duyuru:** kısa bir duyuru yayımlanır (sakin bölümünde görülecek).

### 6:00-10:00 Sakin (4 dakika, telefon)

1. Giriş: **Panel**; borç bilgisi ve modül kartları.
2. **Borcum:** güncel borç, ekstre, **Makbuzlarım**. Not: sakin borcu yalnız kendi taşınma ayından itibaren görür.
3. **Duyurular:** yöneticinin az önce yayımladığı duyuru gelmiş.
4. **Taleplerim → Yeni Talep:** fotoğraflı arıza bildirimi. Ekran yöneticiye geçer: **Talepler**de yeni talep görünür, görevliye atanır.
5. Süre kalırsa: **Rezervasyon** ya da **Ziyaretçilerim**.

### 10:00-13:00 Süper kullanıcı (3 dakika)

1. **Site Başvuruları** ve **Modül Talepleri:** bekleyen istekler ve onay akışı.
2. **Modüller:** demo sitesinde kapalı duran Anket ve Oylama açılır; yöneticinin Panel'inde kart ve menüde öğe belirir.
3. **Platform Ayarları:** şirket ve yasal bilgiler (unvan, adres, telefon). Yasal metin sayfası açılır (ör. `/legal/kvkk_notice`):
   KEP ve MERSİS boşken metinde bu satırlar hiç görünmez; e-posta girilene kadar "[……]" ve "taslak" uyarısı görünür.
4. **Denetim Kaydı:** demoda yapılan işlemler (borçlandırma, tahsilat, modül açma) kim ve ne zaman bilgisiyle kayıtlı.

### 13:00-15:00 Kapanış

- Sorular. Geri bildirimler bölüm 7'deki tabloya o anda yazılır.
- Sonraki iki haftanın hedefi (bir cümle).

## 4. "Bu iki haftada yeni" (en çok 3 dakika)

Açılıştan hemen sonra ya da ilgili bölümün içinde gösterilir; toplam süre 15 dakikayı aşmaz (gerekirse sakin bölümünün 5. adımı ve
süper kullanıcının 1. adımı atlanır). Her madde için: hangi ekran, hangi rolde, bir cümlelik fayda.

Dalga 1'den sonra eklenecek gösterim önerileri (dalga canlıya çıktıysa):

- Daire finans kartında **Kiracı hesabı** ve **Ev sahibi hesabı** sekmeleri (G12): iki bakiye karışmaz.
- Gruplu menü ve sağ üstte dişli (G2); sakinin alt çubuğu: Özet, Duyuru, Arıza, Kapı, Belgeler (G3).
- Sade tasarım: beyaz kartlar, koyu ana düğme, durum noktaları (G6, G7).
- Platform Ayarları'nda kurallar tablosu (G11): ör. aylık %5 üst sınırı, saklama süreleri (`retention.*`).

## 5. Yedek plan

- **İnternet ya da sunucu sorunu:** önceden çekilmiş ekran görüntüleriyle (demo sitesinden) aynı akış anlatılır; sorun kaydedilir.
- **Bir adım hata verirse:** hata ekranı gösterilir, ne olduğu tek cümleyle söylenir, sonraki adıma geçilir; hata demo sonrası
  kayda geçer (bölüm 7).
- **Telefon paylaşılamazsa:** sakin bölümü uygulamanın web sürümünde sakin hesabıyla gösterilir.

## 6. Bu belgenin bakımı

- Her dalga canlıya çıkınca: değişen ekran adları bölüm 3'te düzeltilir, yeni ekran bölüm 4'e bir madde olarak eklenir.
- Demo sitesinin verisi her demodan önce gözden geçirilir; gerçek kişi verisi girilmez.
- Demo sitesi gerektiğinde süper kullanıcı tarafından silinip yeniden kurulur.

## 7. Demo kaydı

| Tarih | Sunan | Katılanlar | Gösterilen yeni maddeler | Geri bildirim | Kime / ne zamana |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
