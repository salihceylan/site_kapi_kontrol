# Platform yol haritası ve yapılacaklar

Kaynak: 2026-10-19 karşılaştırması ("Yazılımcı için Yol Haritası — Ekranlar ve Menü" belgesi ile bugünkü sistem). Bu dosya
yapılacakların tek listesidir; bir madde bitince işaretlenir ve tarih, commit ve canlı bilgisi yanına yazılır.

Öncelik: **P0** hukuki risk / satış öncesi şart · **P1** en büyük kullanıcı değeri · **P2** önemli iyileştirme · **P3** sonra.
Büyüklük: **S** bir gün içinde · **M** birkaç gün · **L** bir haftadan uzun (inceleme ve gerçek PG QA dahil).

## 1. Hukuki ve KVKK

- [x] **P0 · M — Borcum sakin kapsamı (2026-10-19).** Sakin dairenin defterini yalnız kendi taşınma ayından itibaren görür (borç,
  ödeme, makbuz, ekstre, gecikme açıklaması, veri dışa aktarma); bakiye mahsup kuralıyla (vadesi en eski borçtan) hesaplanır,
  böylece önceki sakinin geç ödemesi ya da geçmiş aya yazılan borç yanlış bakiye üretmez. Yönetici tüm defteri görür. Ayrıntı:
  `docs/PLATFORM_FINANS.md` "Sakin kapsamı". Gerçek PG: `QA_ONLY=finance4b QA_PART=resident_scope` (S0-S11).
- [ ] **P1 · S — Taşınma tarihinin önemi yöneticiye gösterilsin.** Kişi eklerken ve toplu yüklemede "Borcum bu tarihten itibaren
  gösterir" uyarısı; yöneticinin daire / kişi kartında "sakin X ayından itibaren görür" göstergesi.
- [ ] **P2 · L — Kişi bazlı tahsilat.** Tahsilatta "kim ödedi" (kişi) tutulursa önceki sakinin taşınmadan sonra yaptığı ödeme yeni
  sakine hiç görünmez; malik ve kiracı için ayrı hesap (yazılımcı belgesindeki "her dairenin iki hesabı") bunun üzerine kurulur.
- [ ] **P0 · kullanıcıda — Yasal metinlerin yayını.** KVKK aydınlatma, gizlilik, kullanım koşulları, hesap ve veri silme, veri
  işleme sözleşmesi şablonları ve uygulamadaki gösterim altyapısı hazır. Gerekenler: şirket bilgileri (unvan, MERSİS, adres,
  KEP) ve avukat onayı (`docs/yasal/KULLANICIDAN_GEREKENLER.md`, `docs/yasal/AVUKAT_KONTROL_LISTESI.md`). Yayından sonra
  `legal.enforce_consents` açılır. Kontrol: aydınlatma metni "onay" istemez (bilgilendirmedir); açık rıza gereken işlem
  varsa ayrı alınır.
- [ ] **P0 · satış sürecinde — Veri işleme sözleşmesi.** Her site yönetimiyle (veri sorumlusu) Güde Teknoloji (veri işleyen)
  arasında imzalanır; şablon hazır.
- [ ] **P0 · M — Gecikme tazminatı ve borç hatırlatmayı açmadan önce dönem kapsamı.** Bugün ikisi de daire bazında hesaplanıyor:
  daire el değiştirince önceki dönemin gecikmiş borcu yeni sakine tazminat ya da hatırlatma olarak yansıyabilir. Açılmadan
  önce Borcum'daki kapsamla aynı kural uygulanmalı. İkisi de bugün varsayılan KAPALI ve hukuk onayı bayrağına bağlı.
- [ ] **P0 · kullanıcıda — Avukat onayı:** gecikme tazminatı (KMK 20: aylık %5, gün hesabı), borç hatırlatma metni,
  makbuz çekincesi (TBK 102/104).

## 2. Para akışı (en büyük değer)

- [ ] **P1 · M — Sakine ödeme bilgisi.** Borcum'da sitenin IBAN'ı ve daireye / aya özel referans kodu (ör. `GUL-A2-1026`),
  "kopyala" düğmeleriyle. Para doğrudan sitenin hesabına gider; ödeme lisansı gerekmez. Bağımlılık: kasa / banka hesabına
  IBAN alanı. Referans kodu, aşağıdaki banka eşlemesinin ilk kuralıdır.
- [ ] **P1 · L — Banka ekstresi yükleme ve otomatik eşleme.** Excel / CSV yüklenir, dosya olduğu gibi saklanır. Eşleme sırası:
  referans kodu → açıklamadaki daire kodu → daha önce eşlenmiş IBAN → gönderen adı → "bekliyor" (yönetici seçer, sistem
  ezberler). Kurallar: aynı satır iki kez işlenmez (tarih + tutar + açıklama + IBAN özeti); birden çok aya yayılan ödeme en
  eski borçtan kapatılır; daire olmayan satırlar (faiz, masraf, tedarikçi) gelir / gider olarak işlenir; "bu yüklemeyi geri
  al" tüm satırları ters kayıtla sıfırlar. Kabul: 3 aylık gerçek dosyada satırların en az %80'i kendiliğinden eşleşir; aynı
  dosya ikinci kez yüklenince hiçbir şey çift yazılmaz. Hukuk: banka dosyası üçüncü kişilerin verisini içerir, saklama süresi
  yasal metinlere yazılır.
- [ ] **P2 · L — Online kart ödemesi.** Yalnız lisanslı bir ödeme kuruluşu üzerinden ve para sitenin hesabına (6493 sayılı
  Kanun). Sağlayıcı seçimi ve sözleşme kullanıcıda.

## 3. Yönetici deneyimi

- [ ] **P1 · M — Yönetici ana sayfası "Bu ay".** Dört sayı: bu ay yazılan, toplanan (yüzdesiyle), geciken daire sayısı,
  kasa + banka toplamı (karta dokununca ilgili liste). Altında aylık beş adım (borç yaz → haber ver → parayı eşle → gider gir
  → rapor al), yapılanlar işaretli, yapılmamış ilk adımın yanında tek düğme. Son 5 para hareketi tek satırda.
- [ ] **P2 · M — Yönetim firması için "Tüm siteler" tablosu.** Yöneticinin sitelerinde aynı dört sayı, satır başına bir site,
  en düşük tahsilat oranı en üstte.
- [ ] **P2 · S — Ekranlarda sade dil.** "Tahakkuk", "Mutabakat" gibi sözcükler ekrandan çıkar ("Borç yazma", "Banka / kasa
  kontrolü"); kod ve API adları değişmez.
- [ ] **P2 · S — Her listede Excel'e aktarma.** Kişi, daire, araç ve finans raporlarında var; eksik listelerin envanteri
  çıkarılıp tamamlanır.

## 4. Bütçe ve raporlar

- [ ] **P2 · L — İşletme projesi (bütçe).** KMK 37 (7579 sayılı Kanunla 2026'da değişti): genel kurul onayı, onaylı proje
  yoksa geçici proje (en geç üç ayda kurula), yürürlükteki projeye göre artış en fazla yeniden değerleme oranı. Bütçe ile
  gerçekleşen karşılaştırması, kesinleşen projenin PDF'i.
- [ ] **P3 · M — İcra dökümü PDF.** Kesinleşmiş işletme projesi ya da kurul kararı + daire ekstresi (İİK 68/1). Avukat
  görüşüyle.
- [ ] **P3 · L — Isı pay ölçer paylaşımı** (Sayaç Okuma modülü, sitede "Yakında"). Sayaç firmasının dosyası yüklenir; fatura
  %70 ölçüme, %30 m²'ye bölünür (yönetmelik); önizleme ve onay.

## 5. Sakin uygulaması ve iletişim

- [ ] **P1 · kullanıcıda — Telefon bildirimini canlıya alma.** Kod hazır ve kapalı; Firebase hizmet hesabı dosyası ve
  `PUSH_ENABLED` bekliyor.
- [ ] **P2 · M — Telefon + SMS koduyla şifresiz giriş.** SMS sağlayıcısı ve maliyet kararı kullanıcıda.
- [ ] **P2 · M — SMS ve WhatsApp bildirimleri** (sitede "Yakında"). WhatsApp için KVKK 9. madde (yurt dışına aktarım:
  standart sözleşme ve Kurum'a bildirim) avukatla netleşir. Borç bilgisi yalnız ilgilisine gider (KVKK Kurulu 2026/348).
- [x] **İş takibinde fotoğraf eki** (2026-10-19, migration 047/048, canlıda).

## Sizden gerekenler (özet)

1. Şirket bilgileri ve avukat onayı → yasal metinler (P0).
2. Avukat onayı → gecikme tazminatı, borç hatırlatma, makbuz metni (P0).
3. Firebase hizmet hesabı → telefon bildirimi (P1).
4. Sitelerin IBAN bilgileri → sakine ödeme bilgisi (P1).
5. SMS sağlayıcı ve ödeme kuruluşu seçimi (P2).

## Önerilen sıra

1. Yasal metinler (sizden bilgi gelince) ve gecikme tazminatı / hatırlatmada dönem kapsamı.
2. Sakine IBAN + referans kodu, ardından banka ekstresi eşleme.
3. Yönetici ana sayfası "Bu ay", ardından "Tüm siteler".
4. Sade dil ve Excel'e aktarma tamamlama.
5. İşletme projesi, SMS girişi ve bildirimleri, icra dökümü, ısı paylaşımı.
