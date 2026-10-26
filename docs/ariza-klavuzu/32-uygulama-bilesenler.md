# Flutter bileşenler, tasarım sistemi ve stiller

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm lib/ui/design (jeton, hareket, kart, düğme, rozet, iskelet, geri sayım), lib/ui/widgets (kart/modal/diyalog bileşenleri), lib/ui/helpers ve lib/styles (renk, dekorasyon, rol teması) için görsel/animasyon arızalarını kapsar. İlk bakılacak yer çoğu zaman lib/ui/design/tokens.dart (AppMotion.reduced, palet) ve ilgili bileşenin kendi dosyasıdır; sayfa düzeyi sorunlar için 31-uygulama-arayuz bölümüne bakın.

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [lib/ui/design/tokens.dart](../../lib/ui/design/tokens.dart) | Aralık, köşe, hareket süreleri, AppPalette, AppTone, tipografi ölçeği |
| [lib/ui/design/countdown_ring.dart](../../lib/ui/design/countdown_ring.dart) | QR geri sayım halkası ve kalan saniye metni |
| [lib/ui/design/skeleton.dart](../../lib/ui/design/skeleton.dart) | ShimmerScope + SkeletonBox yükleniyor iskeleti |
| [lib/ui/design/status_chip.dart](../../lib/ui/design/status_chip.dart) | Durum rozeti ve nabız noktası |
| [lib/ui/design/motion_widgets.dart](../../lib/ui/design/motion_widgets.dart) | AnimatedCount, StaggeredEntry, Pop |
| [lib/ui/design/page_transitions.dart](../../lib/ui/design/page_transitions.dart) | Rota geçişi ve PageEntry |
| [lib/ui/design/app_snack.dart](../../lib/ui/design/app_snack.dart) | Tek tip SnackBar gösterici |
| [lib/ui/helpers/ui_helpers.dart](../../lib/ui/helpers/ui_helpers.dart) | Diyalog genişliği, blok etiketi, tarih biçimi |
| [lib/styles/role_theme.dart](../../lib/styles/role_theme.dart) | Rol -> vurgu rengi / yüzey / gradyan |
| [lib/menu.dart](../../lib/menu.dart) | Tek satır: yan_menu.dart yeniden dışa aktarımı |

## Bu bölümdeki girişler (49)

- [bilesen-hareket-azaltma](#bilesen-hareket-azaltma) — Cihazda "animasyonları kaldır / hareketi azalt" açıkken ekranda animasyon yok ya da testte animasyon hemen bitiyor
- [bilesen-geri-sayim-halka](#bilesen-geri-sayim-halka) — QR geri sayım halkası yanlış doluyor, rengi yanlış ya da hiç boşalmıyor
- [bilesen-geri-sayim-saniye](#bilesen-geri-sayim-saniye) — Geri sayımda kalan saniye yanlış gösteriliyor ya da her karede yeniden kurulup takılıyor
- [bilesen-iskelet-bitmiyor](#bilesen-iskelet-bitmiyor) — Yükleniyor iskeleti (shimmer) hiç bitmiyor, ekran sürekli animasyonda ya da testte pumpAndSettle zaman aşımına uğruyor
- [bilesen-iskelet-tasma](#bilesen-iskelet-tasma) — İskelet kutusu "sonsuz genişlik" hatası veriyor ya da Row içinde taşıyor
- [bilesen-durum-rozeti](#bilesen-durum-rozeti) — Çevrimiçi/çevrimdışı durum rozeti yanlış renkte, nabız atmıyor ya da etiket kesiliyor
- [bilesen-nabiz-ticker](#bilesen-nabiz-ticker) — Durum rozetindeki nokta sürekli ya da hiç nabız atmıyor; testte ticker kalıyor
- [bilesen-snackbar-gorunmuyor](#bilesen-snackbar-gorunmuyor) — Başarı/hata mesajı (SnackBar) ekranda görünmüyor, geç görünüyor ya da yanlış renkte
- [bilesen-snackbar-okunmuyor](#bilesen-snackbar-okunmuyor) — SnackBar metni kısalıyor ("...") ya da eylem düğmesi (Geri al vb.) okunmuyor
- [bilesen-sayi-akisi](#bilesen-sayi-akisi) — Sayaç ("2 Kapı", "(3)") titriyor, ilk açılışta animasyonlu geliyor ya da ekran okuyucu ara değerleri okuyor
- [bilesen-liste-girisi](#bilesen-liste-girisi) — Liste öğeleri her yenilemede tekrar kayarak geliyor ya da girişte öğe görünmüyor (saydam kalıyor)
- [bilesen-sayfa-gecisi](#bilesen-sayfa-gecisi) — Sayfa geçişi takılıyor, menü değişince içerik iki kez beliriyor ya da geçiş animasyonu yok
- [bilesen-pop-belirme](#bilesen-pop-belirme) — Durum metni/hata kutusu değişince eski ve yeni metin birlikte görünüyor ya da belirme animasyonu oynamıyor
- [bilesen-dialog-genisligi](#bilesen-dialog-genisligi) — Diyalog dar ekranda taşıyor ya da çok geniş görünüyor; blok etiketi (A, B, ... AA) ya da tarih yanlış
- [bilesen-rol-rengi](#bilesen-rol-rengi) — Rol rengi (yönetici yeşil, sakin mor, süper kullanıcı mavi) yanlış ya da metin olarak okunmuyor
- [bilesen-kart-tasma](#bilesen-kart-tasma) — Kart içeriği taşıyor, kart çok dar/geniş görünüyor ya da kart dokunulamıyor
- [bilesen-bolum-basligi-tasma](#bilesen-bolum-basligi-tasma) — Bölüm başlığı ve sayaç rozeti dar ekranda/büyük yazıda kırpılıyor ya da eylem düğmesi yanlış yerde
- [bilesen-satir-ici-bildirim](#bilesen-satir-ici-bildirim) — Form/hata kutusunda "Tekrar Dene" düğmesi yok, hata kutusu ekran okuyucuya duyurulmuyor ya da rengi okunmuyor
- [bilesen-birincil-dugme](#bilesen-birincil-dugme) — Birincil eylem düğmesi tıklanmıyor, yükleniyor halinde kalıyor ya da başarı tiki görünmüyor
- [bilesen-basma-olcegi](#bilesen-basma-olcegi) — Düğmeye basınca küçülme efekti takılı kalıyor ya da çift tıklama algılanıyor
- [bilesen-bos-durum](#bilesen-bos-durum) — Boş liste mesajı (ikon + başlık + "Ekle" düğmesi) görünmüyor, taşıyor ya da eylem düğmesi çıkmıyor
- [bilesen-diyalog-sablonu](#bilesen-diyalog-sablonu) — Ortak diyalog (başlık şeridi + eylemler) dar ekranda taşıyor, başlık kırpılıyor ya da eylemler görünmüyor
- [bilesen-giris-logosu](#bilesen-giris-logosu) — Giriş ekranında logo görünmüyor, ışık animasyonu çalışmıyor ya da başlık/alt başlık yanlış
- [bilesen-sayfa-zemini](#bilesen-sayfa-zemini) — Sayfa arka planı ya da kart yüzeyi temaya göre yanlış (koyu temada beyaz kart / açıkta koyu zemin)
- [bilesen-eski-renkler](#bilesen-eski-renkler) — Bir ekranda renkler tema ile uyumsuz (sabit AppColors değeri), metin koyu zeminde okunmuyor
- [bilesen-saat-donuyor](#bilesen-saat-donuyor) — Dijital saat durmuş gibi, uygulamaya dönünce yanlış saat gösteriyor ya da saat kartı her saniye yeniden kuruluyor (takılma)
- [bilesen-saat-tasma](#bilesen-saat-tasma) — Dijital saat kartında saat, TSİ rozeti ya da kullanıcı adı/rol dar ekranda taşıyor ya da alt alta kayıyor
- [bilesen-sesli-banner](#bilesen-sesli-banner) — Kart içindeki sesli dinleme bandı yanlış durum/metin gösteriyor, mikrofon düğmesi dinlemeyi başlatmıyor ya da büyük yazıda metin eziliyor
- [bilesen-sesli-modal](#bilesen-sesli-modal) — Sesli kontrol penceresi otomatik kapanmıyor/çok erken kapanıyor, nabız animasyonu takılıyor ya da dinlemeyi durdurmuyor
- [bilesen-sesli-modal-tasma](#bilesen-sesli-modal-tasma) — Sesli kontrol penceresinde düğmeler taşıyor ya da pencere ekranı aşıyor; sesli yanıt (TTS) düğmesi çalışmıyor
- [bilesen-eller-serbest-ayar](#bilesen-eller-serbest-ayar) — Eller serbest / Araba modu ayarı kaydedilmiyor, Siri bağlantısı kopyalanınca mesaj çıkmıyor ya da ayar sayfası taşıyor
- [bilesen-liste-ortak-parcalar](#bilesen-liste-ortak-parcalar) — Liste ekranlarında sayfalama okları, baş harf avatarı ya da ikon karosu büyük yazıda kayboluyor; kart dolgusu dar ekranda farklı
- [bilesen-genisleyen-kart](#bilesen-genisleyen-kart) — Listedeki kart açılıp kapanmıyor, ok simgesi dönmüyor ya da genişleme animasyonu takılıyor
- [bilesen-liste-iskeleti](#bilesen-liste-iskeleti) — Liste ilk yüklenirken iskelet satırları sonsuza dek kalıyor ya da boş liste kartı yanlış görünüyor
- [bilesen-eylem-dugme-stilleri](#bilesen-eylem-dugme-stilleri) — Karttaki Düzenle/Sil/Onayla düğmeleri tema ile uyumsuz renkte, devre dışıyken okunmuyor ya da dokunma alanı küçük
- [bilesen-cihaz-karti-durum](#bilesen-cihaz-karti-durum) — Şirket cihaz kartında çevrimiçi/çevrimdışı, "KAPI ATANMAMIŞ" ya da "ARIZALI" rozeti yanlış
- [bilesen-cihaz-karti-ayrinti](#bilesen-cihaz-karti-ayrinti) — Cihaz kartı ayrıntılarında Wi-Fi gücü, firmware, OTA durumu ya da sahip bilgisi yanlış/eksik; Depoya Al ve Arızalı İşaretle düğmeleri görünmüyor
- [bilesen-daire-karti](#bilesen-daire-karti) — Yönetici daire kartında sakin bilgisi, Aktif/Pasif rozeti ya da "Bilgileri Gönder" düğmesi yanlış
- [bilesen-bireysel-daire-karti](#bilesen-bireysel-daire-karti) — Bireysel kullanıcının daire kartında "Daire Yöneticisi / Aile Üyesi" rozeti, üye listesi ya da "Üyeyi Çıkar" düğmesi yanlış
- [bilesen-yonetilen-kullanici-karti](#bilesen-yonetilen-kullanici-karti) — Yönetilen kullanıcı kartında aktif/pasif anahtarı çalışmıyor, kendi hesabında kapatılamıyor ya da Sil düğmesi yok
- [bilesen-onay-bekleyen-kartlar](#bilesen-onay-bekleyen-kartlar) — Site onay isteği ya da abonelik talebi kartında Onayla/Reddet düğmeleri yok, dönüp duruyor ya da bilgiler eksik
- [bilesen-kurulum-secenek-karti](#bilesen-kurulum-secenek-karti) — İlk açılışta "Site Sakini Girişi" / "Yönetici & Cihaz Kurulumu" seçenek kartları ya da başvuru kartı rozeti yanlış
- [bilesen-cihaz-eylem-karti](#bilesen-cihaz-eylem-karti) — Cihaz ekleme/eşleştirme seçeneği kartındaki düğme tepki vermiyor ya da kart genişliği bozuk
- [bilesen-guvenlik-politikasi-dogrulama](#bilesen-guvenlik-politikasi-dogrulama) — Site güvenlik politikası penceresinde konum (enlem/boylam/mesafe) hata veriyor ya da "Kaydedilemedi" çıkıyor
- [bilesen-guvenlik-politikasi-konum](#bilesen-guvenlik-politikasi-konum) — "Mevcut Konumu Al" düğmesi koordinat doldurmuyor ya da GPS izni hatası çıkıyor
- [bilesen-guvenlik-politikasi-erisim](#bilesen-guvenlik-politikasi-erisim) — Site güvenlik politikasında kapı açma yöntemi (uygulama / QR / ikisi) seçilemiyor ya da QR yenilenme süresi değişmiyor
- [bilesen-kapi-gecis-gecmisi](#bilesen-kapi-gecis-gecmisi) — Kapı geçiş geçmişi (log) listesi yüklenmiyor, eski kapının kayıtları görünüyor ya da kapı açılınca liste güncellenmiyor
- [bilesen-kapi-ac-dugmesi-durum](#bilesen-kapi-ac-dugmesi-durum) — Kapıyı aç düğmesi yanlış durumda (hazır/açılıyor/çevrimdışı), başarı tiki görünmüyor ya da çevrimdışıyken tepki vermiyor
- [bilesen-yan-menu-ogeleri](#bilesen-yan-menu-ogeleri) — Yan menüde bir öğe yok ya da yanlış rolde görünüyor; menü dosyası (menu.dart) neyi dışa aktarıyor

## Girişler

<a id="bilesen-hareket-azaltma"></a>
### bilesen-hareket-azaltma · Cihazda "animasyonları kaldır / hareketi azalt" açıkken ekranda animasyon yok ya da testte animasyon hemen bitiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/tokens.dart:45](../../lib/ui/design/tokens.dart#L45) | <code>static bool reduced(BuildContext context) =&gt;</code> | Tek karar noktası: MediaQuery.disableAnimations açıksa true (MediaQuery yoksa false) |
| [lib/ui/design/tokens.dart:49](../../lib/ui/design/tokens.dart#L49) | <code>static Duration of(BuildContext context, Duration duration) =&gt;</code> | Hareket azaltma açıkken süreyi sıfırlar; bileşenler süreyi buradan alır |
| [lib/ui/design/motion_widgets.dart:103](../../lib/ui/design/motion_widgets.dart#L103) | <code>AppMotion.reduced(context);</code> | StaggeredEntry hareket azaltmada animasyonu atlar |

**Olası nedenler**
- Cihaz erişilebilirlik ayarı açık: bileşenler bilerek animasyonsuzdur (hata değil)
- Bileşen süreyi AppMotion.of yerine sabit Duration ile veriyorsa hareket azaltma yok sayılır

**Adım adım kontrol**
- Cihaz ayarlarında "Animasyonları kaldır" durumuna bakın
- Sorunlu bileşende süre AppMotion.of(context, ...) üzerinden mi geçiyor kontrol edin

**İlgili testler:** [test/design/motion_widgets_test.dart](../../test/design/motion_widgets_test.dart), [test/design/pump_at_test.dart](../../test/design/pump_at_test.dart)

**Bkz.:** [bilesen-iskelet-bitmiyor](#bilesen-iskelet-bitmiyor), [bilesen-sayfa-gecisi](#bilesen-sayfa-gecisi)

<a id="bilesen-geri-sayim-halka"></a>
### bilesen-geri-sayim-halka · QR geri sayım halkası yanlış doluyor, rengi yanlış ya da hiç boşalmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/countdown_ring.dart:73](../../lib/ui/design/countdown_ring.dart#L73) | <code>static Color colorFor(double t) {</code> | İlerlemeye göre yeşil > 0,4 > amber > 0 kırmızı geçişi |
| [lib/ui/design/countdown_ring.dart:134](../../lib/ui/design/countdown_ring.dart#L134) | <code>canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * t, false, paint);</code> | Kalan süre yayı: 12 yönünden saat yönünde t oranında |
| [lib/ui/design/countdown_ring.dart:115](../../lib/ui/design/countdown_ring.dart#L115) | <code>final t = progress.value.isNaN ? 0.0 : progress.value.clamp(0.0, 1.0);</code> | NaN ya da aralık dışı değer 0..1 e sıkıştırılır |
| [lib/ui/design/countdown_ring.dart:139](../../lib/ui/design/countdown_ring.dart#L139) | <code>bool shouldRepaint(_RingPainter oldDelegate) =&gt;</code> | Animasyon nesnesi, sabit renk ya da kalınlık değişmedikçe yeniden çizilmez |

**Olası nedenler**
- Çağıran progress animasyonunu 1 -> 0 yerine 0 -> 1 veriyor (halka dolar)
- colorOverride verilmiş: renk sabit kalır (başarı/ret anları için tasarlandı)
- Halka açık gri surfaceMuted üstüne konmuş: amber kontrastı düşer

**Adım adım kontrol**
- QR modalında controller yönünü ve süresini kontrol edin
- Birim testi renk eşiklerini doğrular

**İlgili testler:** [test/design/countdown_ring_test.dart](../../test/design/countdown_ring_test.dart)

**Bkz.:** [bilesen-geri-sayim-saniye](#bilesen-geri-sayim-saniye), [ui-qr-modal-sure](31-uygulama-arayuz.md#ui-qr-modal-sure)

<a id="bilesen-geri-sayim-saniye"></a>
### bilesen-geri-sayim-saniye · Geri sayımda kalan saniye yanlış gösteriliyor ya da her karede yeniden kurulup takılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/countdown_ring.dart:172](../../lib/ui/design/countdown_ring.dart#L172) | <code>static int secondsFor(double value, int totalSeconds) {</code> | İlerlemeyi yukarı yuvarlanan kalan saniyeye çevirir (0..totalSeconds) |
| [lib/ui/design/countdown_ring.dart:213](../../lib/ui/design/countdown_ring.dart#L213) | <code>if (next != _seconds &amp;&amp; mounted) setState(() =&gt; _seconds = next);</code> | Yalnız gösterilen rakam değişince setState: saniyede bir kurulum |
| [lib/ui/design/countdown_ring.dart:192](../../lib/ui/design/countdown_ring.dart#L192) | <code>widget.progress.addListener(_onTick);</code> | Dinleyici initState te eklenir; dispose ta kaldırılmazsa sızıntı olur |

**Olası nedenler**
- totalSeconds, animasyon süresiyle uyuşmuyor (varsayılan 30)
- progress animasyonu değişince didUpdateWidget dinleyiciyi taşır; farklı controller verilirse sayı sıfırdan okunur

**Adım adım kontrol**
- Çağıranda totalSeconds değerini controller süresiyle karşılaştırın

**İlgili testler:** [test/design/countdown_ring_test.dart](../../test/design/countdown_ring_test.dart)

**Bkz.:** [bilesen-geri-sayim-halka](#bilesen-geri-sayim-halka)

<a id="bilesen-iskelet-bitmiyor"></a>
### bilesen-iskelet-bitmiyor · Yükleniyor iskeleti (shimmer) hiç bitmiyor, ekran sürekli animasyonda ya da testte pumpAndSettle zaman aşımına uğruyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/skeleton.dart:67](../../lib/ui/design/skeleton.dart#L67) | <code>if (!_controller.isAnimating) _controller.repeat();</code> | Kapsam etkinken denetleyici sonsuz döner: kapsam ağaçta kaldıkça ticker sürer |
| [lib/ui/design/skeleton.dart:50](../../lib/ui/design/skeleton.dart#L50) | <code>bool get _animate =&gt; widget.active &amp;&amp; !AppMotion.reduced(context);</code> | active=false ya da hareket azaltma açıkken durur ve durağan çizilir |
| [lib/ui/design/skeleton.dart:65](../../lib/ui/design/skeleton.dart#L65) | <code>void _sync() {</code> | active ve bağımlılık değişince denetleyiciyi başlatır/durdurur |
| [lib/ui/design/skeleton.dart:90](../../lib/ui/design/skeleton.dart#L90) | <code>label: active ? 'Yükleniyor' : null,</code> | Etkin kapsam ekran okuyucuya canlı bölge olarak "Yükleniyor" der |

**Olası nedenler**
- Yükleme bitince ShimmerScope ağaçtan çıkarılmadı ve active false yapılmadı
- Kapsam sayfanın tamamına konmuş: tüm sayfa her karede yeniden boyanır

**Adım adım kontrol**
- Çağıranda "if (loading) ShimmerScope(...) else içerik" kalıbını doğrulayın
- Hareket azaltmayı açıp ticker un durduğunu görün

**İlgili testler:** [test/design/skeleton_test.dart](../../test/design/skeleton_test.dart)

**Bkz.:** [bilesen-hareket-azaltma](#bilesen-hareket-azaltma), [bilesen-iskelet-tasma](#bilesen-iskelet-tasma)

<a id="bilesen-iskelet-tasma"></a>
### bilesen-iskelet-tasma · İskelet kutusu "sonsuz genişlik" hatası veriyor ya da Row içinde taşıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/skeleton.dart:138](../../lib/ui/design/skeleton.dart#L138) | <code>width: width ?? double.infinity,</code> | Genişlik verilmezse sonsuz: Row içinde Expanded ya da sabit genişlik gerekir |
| [lib/ui/design/skeleton.dart:119](../../lib/ui/design/skeleton.dart#L119) | <code>class SkeletonBox extends StatelessWidget {</code> | width/height/radius parametreleri; radius yüksekliğin yarısını aşarsa hap/daire olur |

**Olası nedenler**
- SkeletonBox sınırsız genişlikli Row/Wrap içine genişliksiz konmuş

**Adım adım kontrol**
- Row içinde SkeletonBox u Expanded ile sarın ya da width verin

**İlgili testler:** [test/design/skeleton_test.dart](../../test/design/skeleton_test.dart)

**Bkz.:** [bilesen-iskelet-bitmiyor](#bilesen-iskelet-bitmiyor)

<a id="bilesen-durum-rozeti"></a>
### bilesen-durum-rozeti · Çevrimiçi/çevrimdışı durum rozeti yanlış renkte, nabız atmıyor ya da etiket kesiliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/status_chip.dart:23](../../lib/ui/design/status_chip.dart#L23) | <code>class StatusChip extends StatefulWidget {</code> | Rozet: tone (renk), label, isteğe bağlı icon ve pulse |
| [lib/ui/design/status_chip.dart:153](../../lib/ui/design/status_chip.dart#L153) | <code>decoration: StatusDot.decorationOf(tone, p),</code> | Sade stil (İP-1C, G7): rozetin zemini ve kenarı boyanmaz; renk yalnız noktadadır (StatusDot), etiket gövde metni renginde |
| [lib/ui/design/status_chip.dart:186](../../lib/ui/design/status_chip.dart#L186) | <code>overflow: TextOverflow.ellipsis,</code> | Etiket tek satır + elips: dar alanda kısalır |
| [lib/ui/design/tokens.dart:421](../../lib/ui/design/tokens.dart#L421) | <code>Color get dot =&gt; isStatus ? hue : neutral.hue;</code> | Nokta rengi: yalnız tamam / bekliyor / kritik tonları renkli; öteki tonlar (bilgi, birincil, rol) nötr gri |
| [lib/ui/design/tokens.dart:424](../../lib/ui/design/tokens.dart#L424) | <code>Color sign(AppPalette p) =&gt; isStatus ? ink(p) : p.textSecondary;</code> | İkon rengi: durum tonlarında tonun ink rengi, ötekilerde gövde metni rengi |

**Olası nedenler**
- Çağıran yanlış AppTone verdi (çevrimiçi = success, yerel ağ = warning, çevrimdışı = danger)
- Durum olmayan ton (bilgi, birincil, rol tonu) verildi: nokta bilerek nötr gridir (sade stil)
- Hareket azaltma açık: nabız bilerek kapalı
- pulse true iken icon verilirse nokta öncelik alır, ikon görünmez

**Adım adım kontrol**
- Çağıran kartta tone eşlemesini kontrol edin
- Koyu temada kontrast için test/design/contrast_test.dart a bakın

**İlgili testler:** [test/design/status_chip_test.dart](../../test/design/status_chip_test.dart), [test/design/contrast_test.dart](../../test/design/contrast_test.dart)

**Bkz.:** [bilesen-nabiz-ticker](#bilesen-nabiz-ticker), [ui-koyu-tema-okunmuyor](31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor)

<a id="bilesen-nabiz-ticker"></a>
### bilesen-nabiz-ticker · Durum rozetindeki nokta sürekli ya da hiç nabız atmıyor; testte ticker kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/status_chip.dart:82](../../lib/ui/design/status_chip.dart#L82) | <code>..repeat(count: _pings);</code> | Nabız 3 tur atar ve durur (kararlı durumda ticker yok) |
| [lib/ui/design/status_chip.dart:71](../../lib/ui/design/status_chip.dart#L71) | <code>if (widget.pulse != oldWidget.pulse) _sync();</code> | false -> true geçişinde nabız yeniden başlar |
| [lib/ui/design/status_chip.dart:103](../../lib/ui/design/status_chip.dart#L103) | <code>if (!c.isAnimating) return const SizedBox.shrink();</code> | Animasyon bitince halka ağaçta iz bırakmaz |

**Olası nedenler**
- Nabız tasarım gereği 3 tur sonra durur; sürekli atması beklenmemeli
- pulse hiç false e dönmeden aynı değerde kalırsa yeniden başlamaz

**Adım adım kontrol**
- pulse değerinin çağıranda durum değişince false -> true döndüğünü doğrulayın

**İlgili testler:** [test/design/status_chip_test.dart](../../test/design/status_chip_test.dart)

**Bkz.:** [bilesen-durum-rozeti](#bilesen-durum-rozeti), [bilesen-hareket-azaltma](#bilesen-hareket-azaltma)

<a id="bilesen-snackbar-gorunmuyor"></a>
### bilesen-snackbar-gorunmuyor · Başarı/hata mesajı (SnackBar) ekranda görünmüyor, geç görünüyor ya da yanlış renkte

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/app_snack.dart:62](../../lib/ui/design/app_snack.dart#L62) | <code>final messenger = ScaffoldMessenger.maybeOf(context);</code> | Messenger yoksa mesaj sessizce yutulur |
| [lib/ui/design/app_snack.dart:75](../../lib/ui/design/app_snack.dart#L75) | <code>messenger.clearSnackBars();</code> | replace true ise sıradakiler atılır ve mesaj hemen gösterilir; false ise kuyruğa girer |
| [lib/ui/design/app_snack.dart:29](../../lib/ui/design/app_snack.dart#L29) | <code>static const Duration defaultDuration = Duration(seconds: 4);</code> | Varsayılan süre 4 sn |
| [lib/ui/design/app_snack.dart:92](../../lib/ui/design/app_snack.dart#L92) | <code>final (Color iconColor, IconData icon) = switch (kind) {</code> | Tür -> simge ve simge rengi; dolgu her türde aynı koyu tema yüzeyidir (sade stil, İP-1C) |

**Olası nedenler**
- context ağaçta ScaffoldMessenger yok ya da await sonrası context ölü (mounted kontrolü yok)
- Önceki mesajlar kuyrukta: yenisi sıra bekler (replace: true ile hemen gösterilir)
- Kapı açma gibi akışta mesaj başka bir kod yolundan (elle SnackBar) veriliyor
- "Yanlış renk" sanılan durum: sade stilde başarı / hata dolgusu boyanmaz; tür simgeden ve simge renginden anlaşılır

**Adım adım kontrol**
- Çağıranda await sonrası mounted kontrolü var mı bakın
- Mesajın AppSnack.show mu elle SnackBar mı olduğunu --where "showSnackBar" ile arayın

**İlgili testler:** [test/design/app_snack_test.dart](../../test/design/app_snack_test.dart)

**Bkz.:** [bilesen-snackbar-okunmuyor](#bilesen-snackbar-okunmuyor)

<a id="bilesen-snackbar-okunmuyor"></a>
### bilesen-snackbar-okunmuyor · SnackBar metni kısalıyor ("...") ya da eylem düğmesi (Geri al vb.) okunmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/app_snack.dart:59](../../lib/ui/design/app_snack.dart#L59) | <code>int maxLines = 4,</code> | Varsayılan 4 satır; uzun cümle için çağıran artırabilir |
| [lib/styles/app_theme.dart:206](../../lib/styles/app_theme.dart#L206) | <code>actionTextColor: AppPalette.dark.link,</code> | Renk verilmemiş eylem etiketi temadan bağlantı mavisini alır (koyu bildirim yüzeyinde okunur) |

**Olası nedenler**
- Mesaj 4 satırdan uzun
- Eylemin textColor değeri açıkça verilmiş ve dolguyla çakışıyor

**Adım adım kontrol**
- Çağıranda maxLines değerini artırın ya da mesajı kısaltın

**İlgili testler:** [test/design/app_snack_test.dart](../../test/design/app_snack_test.dart)

**Bkz.:** [bilesen-snackbar-gorunmuyor](#bilesen-snackbar-gorunmuyor)

<a id="bilesen-sayi-akisi"></a>
### bilesen-sayi-akisi · Sayaç ("2 Kapı", "(3)") titriyor, ilk açılışta animasyonlu geliyor ya da ekran okuyucu ara değerleri okuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/motion_widgets.dart:13](../../lib/ui/design/motion_widgets.dart#L13) | <code>class AnimatedCount extends StatelessWidget {</code> | Tam sayı değişince 320 ms akan sayaç |
| [lib/ui/design/motion_widgets.dart:48](../../lib/ui/design/motion_widgets.dart#L48) | <code>fontFeatures: const &lt;FontFeature&gt;[FontFeature.tabularFigures()],</code> | Sabit genişlikli rakam: sayı akarken metin titremez |
| [lib/ui/design/motion_widgets.dart:37](../../lib/ui/design/motion_widgets.dart#L37) | <code>label: '$prefix$value$suffix',</code> | Ekran okuyucu yalnız hedef değeri okur |

**Olası nedenler**
- Yazı tipi tabular rakam desteklemiyorsa titreme görülebilir
- Çağıran int olmayan değeri yuvarlayıp veriyor

**Adım adım kontrol**
- Çağıranda prefix/suffix ve value kontrol edin

**İlgili testler:** [test/design/motion_widgets_test.dart](../../test/design/motion_widgets_test.dart)

**Bkz.:** [bilesen-liste-girisi](#bilesen-liste-girisi)

<a id="bilesen-liste-girisi"></a>
### bilesen-liste-girisi · Liste öğeleri her yenilemede tekrar kayarak geliyor ya da girişte öğe görünmüyor (saydam kalıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/motion_widgets.dart:65](../../lib/ui/design/motion_widgets.dart#L65) | <code>class StaggeredEntry extends StatefulWidget {</code> | İlk 8 öğe için 12 dp yukarıdan kayarak gelen giriş |
| [lib/ui/design/motion_widgets.dart:102](../../lib/ui/design/motion_widgets.dart#L102) | <code>widget.index &gt;= StaggeredEntry.maxAnimated &#124;&#124;</code> | Sıra 8 ve üstü öğeler animasyonsuz görünür |
| [lib/ui/design/motion_widgets.dart:119](../../lib/ui/design/motion_widgets.dart#L119) | <code>controller.forward();</code> | Animasyon yalnız ilk kurulumda bir kez oynar |

**Olası nedenler**
- ListView.builder gibi tembel listede öğe yeniden kurulunca animasyon tekrar oynar (bu bileşen orada kullanılmamalı)
- Öğeye her yenilemede yeni key verilirse State yeniden kurulur

**Adım adım kontrol**
- Kullanıldığı listenin Column+for mu ListView.builder mı olduğuna bakın

**İlgili testler:** [test/design/motion_widgets_test.dart](../../test/design/motion_widgets_test.dart)

**Bkz.:** [bilesen-hareket-azaltma](#bilesen-hareket-azaltma)

<a id="bilesen-sayfa-gecisi"></a>
### bilesen-sayfa-gecisi · Sayfa geçişi takılıyor, menü değişince içerik iki kez beliriyor ya da geçiş animasyonu yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/page_transitions.dart:27](../../lib/ui/design/page_transitions.dart#L27) | <code>if (AppMotion.reduced(context)) return child;</code> | Hareket azaltmada rota geçişi yok, içerik doğrudan gelir |
| [lib/ui/design/page_transitions.dart:90](../../lib/ui/design/page_transitions.dart#L90) | <code>const PageTransitionsTheme appPageTransitions = PageTransitionsTheme(</code> | iOS/macOS Cupertino, diğerleri uygulama geçişi |
| [lib/ui/design/page_transitions.dart:107](../../lib/ui/design/page_transitions.dart#L107) | <code>class PageEntry extends StatefulWidget {</code> | Menü öğesi değişince yalnız yeni içerik 200 ms solarak gelir; çağıranın key vermesi gerekir |
| [lib/ui/design/page_transitions.dart:69](../../lib/ui/design/page_transitions.dart#L69) | <code>_curved.dispose();</code> | Animasyon değişince eski CurvedAnimation bırakılır (dinleyici sızıntısı önlemi) |

**Olası nedenler**
- PageEntry e değişen bir key verilmedi: içerik değişse de giriş animasyonu oynamaz
- AnimatedSwitcher kullanılırsa iki görünüm aynı anda ağaçta kalır (GlobalKey çakışması); tasarım bunu bilerek önlüyor

**Adım adım kontrol**
- Çağıranda PageEntry key değerini kontrol edin (menü adı + mod)

**İlgili testler:** [test/design/page_transitions_test.dart](../../test/design/page_transitions_test.dart)

**Bkz.:** [bilesen-hareket-azaltma](#bilesen-hareket-azaltma), [ui-menu-yanlis-rol](31-uygulama-arayuz.md#ui-menu-yanlis-rol)

<a id="bilesen-pop-belirme"></a>
### bilesen-pop-belirme · Durum metni/hata kutusu değişince eski ve yeni metin birlikte görünüyor ya da belirme animasyonu oynamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/motion_widgets.dart:153](../../lib/ui/design/motion_widgets.dart#L153) | <code>class Pop extends StatelessWidget {</code> | Key değişince yalnız yeni çocuk 0,9 -> 1 ölçekle gelir |
| [lib/ui/design/motion_widgets.dart:165](../../lib/ui/design/motion_widgets.dart#L165) | <code>curve: Curves.easeOutBack,</code> | easeOutBack hafif aşar: opaklık 0..1 e sıkıştırılır |

**Olası nedenler**
- Pop a ValueKey verilmedi: durum değişse de animasyon yeniden başlamaz

**Adım adım kontrol**
- Kullanım yerinde Pop(key: ValueKey(durum), ...) kalıbını doğrulayın

**İlgili testler:** [test/design/motion_widgets_test.dart](../../test/design/motion_widgets_test.dart)

**Bkz.:** [bilesen-sayi-akisi](#bilesen-sayi-akisi)

<a id="bilesen-dialog-genisligi"></a>
### bilesen-dialog-genisligi · Diyalog dar ekranda taşıyor ya da çok geniş görünüyor; blok etiketi (A, B, ... AA) ya da tarih yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/helpers/ui_helpers.dart:4](../../lib/ui/helpers/ui_helpers.dart#L4) | <code>double dialogWidthForScreen(BuildContext context) {</code> | Genişlik ekran - 72 olup 260 ile 420 arasına sıkıştırılır |
| [lib/ui/helpers/ui_helpers.dart:9](../../lib/ui/helpers/ui_helpers.dart#L9) | <code>String blockLabelFromIndex(int index) {</code> | Blok sırasını A..Z, AA.. etiketine çevirir (taban 26 harf) |
| [lib/ui/helpers/ui_helpers.dart:22](../../lib/ui/helpers/ui_helpers.dart#L22) | <code>String formatDateTimeOrUnknown(DateTime? dateTime) {</code> | Tarih yoksa "Bilinmiyor" yazar |
| [lib/ui/helpers/ui_helpers.dart:30](../../lib/ui/helpers/ui_helpers.dart#L30) | <code>final local = dateTime.toLocal();</code> | Tarih cihaz yerel saatine çevrilip gg.aa.yyyy ss:dd biçiminde yazılır |

**Olası nedenler**
- Diyalog dialogWidthForScreen yerine sabit genişlik kullanıyor
- Sunucudan gelen tarih UTC: yerel saate çevrildiği için sunucu günlüğüyle saat farkı görünür

**Adım adım kontrol**
- Diyalog kodunda genişliğin bu yardımcıdan geldiğini doğrulayın
- Saat farkı için cihaz saat dilimini kontrol edin

<a id="bilesen-rol-rengi"></a>
### bilesen-rol-rengi · Rol rengi (yönetici yeşil, sakin mor, süper kullanıcı mavi) yanlış ya da metin olarak okunmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/styles/role_theme.dart:6](../../lib/styles/role_theme.dart#L6) | <code>Color get accentColor {</code> | Rol -> canlı vurgu rengi (tint/kenar/şerit için) |
| [lib/styles/role_theme.dart:53](../../lib/styles/role_theme.dart#L53) | <code>Color inkColor(AppPalette palette) =&gt; tone.ink(palette);</code> | Rol rengini METİN olarak kullanmak için kontrastlı ton |
| [lib/ui/design/tokens.dart:430](../../lib/ui/design/tokens.dart#L430) | <code>UserRole.superUser =&gt; AppTone.primary,</code> | Rol -> AppTone köprüsü; accentColor ile aynı hue olmalı |

**Olası nedenler**
- accentColor metin rengi olarak kullanılmış: açık zeminde kontrast yetersiz (inkColor kullanılmalı)
- Rol eklenince ya da rengi değişince role_theme.dart ve tokens.dart eşlemesi birlikte güncellenmedi

**Adım adım kontrol**
- Metin rengi için inkColor(context.palette) kullanıldığını doğrulayın

**İlgili testler:** [test/design/contrast_test.dart](../../test/design/contrast_test.dart)

**Bkz.:** [ui-koyu-tema-okunmuyor](31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor), [ui-menu-yanlis-rol](31-uygulama-arayuz.md#ui-menu-yanlis-rol)

<a id="bilesen-kart-tasma"></a>
### bilesen-kart-tasma · Kart içeriği taşıyor, kart çok dar/geniş görünüyor ya da kart dokunulamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/app_card.dart:33](../../lib/ui/design/app_card.dart#L33) | <code>class AppCard extends StatelessWidget {</code> | Tüm kart yüzeylerinin tek karşılığı; child e sabit yükseklik verilmez |
| [lib/ui/design/app_card.dart:111](../../lib/ui/design/app_card.dart#L111) | <code>constraints: const BoxConstraints(minHeight: 48),</code> | onTap varsa en az 48 dp dokunma hedefi |
| [lib/ui/design/app_card.dart:70](../../lib/ui/design/app_card.dart#L70) | <code>int get _effectiveLevel =&gt; selected &amp;&amp; level &lt; 2 ? 2 : level;</code> | Seçili kart en az seviye 2 gölgeyle çizilir |
| [lib/ui/design/app_card.dart:100](../../lib/ui/design/app_card.dart#L100) | <code>child: ColoredBox(color: bar),</code> | accentBar: üstte 3 dp rol/ton şeridi (düzeni değiştirmez) |

**Olası nedenler**
- Kart sınırsız genişlikli üst öğede (örn. Scaffold gövdesi) kullanılmış: içeriği kadar dar kalır
- onTap null verilmiş: kart bilerek dokunulamaz (InkWell eklenmez)
- Çağıran dar kartta padding vermemiş (varsayılan 16)

**Adım adım kontrol**
- Kartın Column/ListView çocuğu olduğunu doğrulayın
- onTap bağlantısını kontrol edin

**İlgili testler:** [test/design/app_card_test.dart](../../test/design/app_card_test.dart)

**Bkz.:** [bilesen-bolum-basligi-tasma](#bilesen-bolum-basligi-tasma), [bilesen-satir-ici-bildirim](#bilesen-satir-ici-bildirim)

<a id="bilesen-bolum-basligi-tasma"></a>
### bilesen-bolum-basligi-tasma · Bölüm başlığı ve sayaç rozeti dar ekranda/büyük yazıda kırpılıyor ya da eylem düğmesi yanlış yerde

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/app_card.dart:155](../../lib/ui/design/app_card.dart#L155) | <code>class SectionHeader extends StatelessWidget {</code> | Başlık + sayaç + eylem; başlık en çok 3 satır |
| [lib/ui/design/app_card.dart:275](../../lib/ui/design/app_card.dart#L275) | <code>static const double _inlineFraction = 0.4;</code> | trailing genişliğin %40 ından büyükse başlığın altına düşer |
| [lib/ui/design/app_card.dart:270](../../lib/ui/design/app_card.dart#L270) | <code>class _RenderHeaderFlow extends RenderBox</code> | Özel yerleşim: başlık ile rozet birlikte alt satıra iner |

**Olası nedenler**
- trailing en çok 2 IconButton ya da 1 TextButton olmalı; daha genişi altına düşer
- Başlık 3 satırdan uzunsa elips ile kısalır

**Adım adım kontrol**
- trailing e verilen widget in genişliğine bakın
- Büyük yazı tipiyle dar ekranda deneyin

**İlgili testler:** [test/design/app_card_test.dart](../../test/design/app_card_test.dart)

**Bkz.:** [bilesen-kart-tasma](#bilesen-kart-tasma), [bilesen-sayi-akisi](#bilesen-sayi-akisi)

<a id="bilesen-satir-ici-bildirim"></a>
### bilesen-satir-ici-bildirim · Form/hata kutusunda "Tekrar Dene" düğmesi yok, hata kutusu ekran okuyucuya duyurulmuyor ya da rengi okunmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/app_card.dart:424](../../lib/ui/design/app_card.dart#L424) | <code>class InlineNotice extends StatelessWidget {</code> | İkon + metin; ton ve isteğe bağlı onRetry alır |
| [lib/ui/design/app_card.dart:466](../../lib/ui/design/app_card.dart#L466) | <code>liveRegion: true,</code> | Hata/başarı kutusu canlı bölge: ekran okuyucu değişince okur |
| [lib/ui/design/app_card.dart:499](../../lib/ui/design/app_card.dart#L499) | <code>label: const Text('Tekrar Dene'),</code> | Düğme yalnız onRetry verilirse gösterilir |

**Olası nedenler**
- Çağıran onRetry vermemiş
- Yanlış ton (danger yerine info) verilmiş

**Adım adım kontrol**
- Çağıranda onRetry ve tone değerlerini kontrol edin

**İlgili testler:** [test/design/app_card_test.dart](../../test/design/app_card_test.dart)

**Bkz.:** [bilesen-kart-tasma](#bilesen-kart-tasma), [bilesen-snackbar-gorunmuyor](#bilesen-snackbar-gorunmuyor)

<a id="bilesen-birincil-dugme"></a>
### bilesen-birincil-dugme · Birincil eylem düğmesi tıklanmıyor, yükleniyor halinde kalıyor ya da başarı tiki görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/buttons.dart:158](../../lib/ui/design/buttons.dart#L158) | <code>final canTap = onPressed != null &amp;&amp; !loading &amp;&amp; !success;</code> | Düğme yalnız onPressed doluyken, yükleme ve başarı yokken dokunulur |
| [lib/ui/design/buttons.dart:230](../../lib/ui/design/buttons.dart#L230) | <code>HapticFeedback.selectionClick();</code> | Her basışta hafif titreşim, sonra onPressed çağrılır |
| [lib/ui/design/buttons.dart:154](../../lib/ui/design/buttons.dart#L154) | <code>final t = success ? AppTone.success : tone;</code> | success true olunca ton yeşile döner ve onay simgesi çıkar |
| [lib/ui/design/buttons.dart:168](../../lib/ui/design/buttons.dart#L168) | <code>child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),</code> | loading true iken dönen gösterge; çağıran false a döndürmezse sonsuz kalır |

**Olası nedenler**
- Çağıran loading değerini işlem bitince false yapmıyor (hata dalında unutulmuş olabilir)
- onPressed null: düğme gri ve devre dışı
- ElevatedButton/OutlinedButton kullanan yerlerde bu bileşen kullanılmaz; görünümü tema yönetir

**Adım adım kontrol**
- Çağıranda loading un try/finally ile sıfırlandığını doğrulayın

**İlgili testler:** [test/design/buttons_test.dart](../../test/design/buttons_test.dart)

**Bkz.:** [bilesen-basma-olcegi](#bilesen-basma-olcegi)

<a id="bilesen-basma-olcegi"></a>
### bilesen-basma-olcegi · Düğmeye basınca küçülme efekti takılı kalıyor ya da çift tıklama algılanıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/buttons.dart:19](../../lib/ui/design/buttons.dart#L19) | <code>class PressableScale extends StatefulWidget {</code> | Basılıyken 0,97 ölçek (varsayılan) uygular |
| [lib/ui/design/buttons.dart:62](../../lib/ui/design/buttons.dart#L62) | <code>onTapCancel: () =&gt; _set(false),</code> | İptal edilen dokunuşta ölçek geri döner |
| [lib/ui/design/buttons.dart:51](../../lib/ui/design/buttons.dart#L51) | <code>if (!widget.enabled &amp;&amp; _down) _down = false;</code> | Devre dışı kalınca basılı durumu sıfırlanır |

**Olası nedenler**
- enabled false iken efekt bilerek yok
- Anlamsal tap eylemi eklenmez: tıklama içteki InkWell dedir

**Adım adım kontrol**
- İçteki InkWell onTap bağlantısını kontrol edin

**İlgili testler:** [test/design/buttons_test.dart](../../test/design/buttons_test.dart)

**Bkz.:** [bilesen-birincil-dugme](#bilesen-birincil-dugme)

<a id="bilesen-bos-durum"></a>
### bilesen-bos-durum · Boş liste mesajı (ikon + başlık + "Ekle" düğmesi) görünmüyor, taşıyor ya da eylem düğmesi çıkmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/empty_state.dart:21](../../lib/ui/design/empty_state.dart#L21) | <code>class EmptyState extends StatelessWidget {</code> | İkon karosu + başlık + isteğe bağlı mesaj ve eylem |
| [lib/ui/design/empty_state.dart:75](../../lib/ui/design/empty_state.dart#L75) | <code>final hasAction = onAction != null &amp;&amp; actionLabel != null;</code> | Eylem düğmesi için hem etiket hem geri çağrı gerekir |
| [lib/ui/design/empty_state.dart:134](../../lib/ui/design/empty_state.dart#L134) | <code>constraints: const BoxConstraints(maxWidth: 360),</code> | Tam boy görünüm 360 dp ile sınırlı ve kaydırılabilir (taşmaz) |
| [lib/ui/design/empty_state.dart:34](../../lib/ui/design/empty_state.dart#L34) | <code>const EmptyState.compact({</code> | Kart içi kompakt biçim: sola hizalı satır |

**Olası nedenler**
- actionLabel ya da onAction eksik: düğme gösterilmez
- Liste yükleniyorken boş durum gösterilir: önce SkeletonBox kullanılmalı

**Adım adım kontrol**
- Çağıranda yükleme/boş ayrımını kontrol edin

**İlgili testler:** [test/design/empty_state_test.dart](../../test/design/empty_state_test.dart)

**Bkz.:** [bilesen-iskelet-bitmiyor](#bilesen-iskelet-bitmiyor), [bilesen-birincil-dugme](#bilesen-birincil-dugme)

<a id="bilesen-diyalog-sablonu"></a>
### bilesen-diyalog-sablonu · Ortak diyalog (başlık şeridi + eylemler) dar ekranda taşıyor, başlık kırpılıyor ya da eylemler görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/app_dialog.dart:106](../../lib/ui/design/app_dialog.dart#L106) | <code>class AppDialog extends StatelessWidget {</code> | Başlık şeridi + içerik + eylem satırı şablonu |
| [lib/ui/design/app_dialog.dart:132](../../lib/ui/design/app_dialog.dart#L132) | <code>scrollable: true,</code> | İçerik kaydırılabilir: uzun içerik taşma yerine kayar |
| [lib/ui/design/app_dialog.dart:146](../../lib/ui/design/app_dialog.dart#L146) | <code>content: SizedBox(width: dialogWidthForScreen(context), child: child),</code> | Genişlik ui_helpers.dialogWidthForScreen ten gelir |
| [lib/ui/design/app_dialog.dart:15](../../lib/ui/design/app_dialog.dart#L15) | <code>class AppDialogHeader extends StatelessWidget {</code> | İkon karosu + en çok 3 satır başlık + alt başlık |

**Olası nedenler**
- Çağıran actions boş verdi: eylem satırı yok
- Başlık 3 satırdan uzun: elips

**Adım adım kontrol**
- Diyalogu açan kodda actions listesini kontrol edin

**İlgili testler:** [test/design/app_dialog_test.dart](../../test/design/app_dialog_test.dart)

**Bkz.:** [bilesen-dialog-genisligi](#bilesen-dialog-genisligi)

<a id="bilesen-giris-logosu"></a>
### bilesen-giris-logosu · Giriş ekranında logo görünmüyor, ışık animasyonu çalışmıyor ya da başlık/alt başlık yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/login_hero.dart:66](../../lib/ui/design/login_hero.dart#L66) | <code>return AnimatedGudeLogo(height: height, semanticLabel: null);</code> | Logo vektör olarak çizilir (lib/brand); görsel dosyası yoktur |
| [lib/ui/design/login_hero.dart:46](../../lib/ui/design/login_hero.dart#L46) | <code>duration: AppMotion.of(context, AppMotion.slow),</code> | Giriş solma + yukarı kayma; hareket azaltmada anında |

**Olası nedenler**
- Cihazda "animasyonları azalt" açık: logo durağan çizilir (beklenen)
- Başlık/alt başlık çağıranda null

**Adım adım kontrol**
- Cihaz erişilebilirlik ayarında animasyonların kapalı olup olmadığına bakın
- lib/brand/gude_logo_animated.dart içindeki GudeLogoAnimation.enabledByDefault değeri (yalnız testte false)

**İlgili testler:** [test/design/login_hero_test.dart](../../test/design/login_hero_test.dart), [test/brand/gude_logo_animated_test.dart](../../test/brand/gude_logo_animated_test.dart)

**Bkz.:** [ui-giris-hata](31-uygulama-arayuz.md#ui-giris-hata)

<a id="bilesen-sayfa-zemini"></a>
### bilesen-sayfa-zemini · Sayfa arka planı ya da kart yüzeyi temaya göre yanlış (koyu temada beyaz kart / açıkta koyu zemin)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/styles/app_decorations.dart:16](../../lib/styles/app_decorations.dart#L16) | <code>static BoxDecoration pageBackground(BuildContext context) =&gt;</code> | Tema parlaklığına göre DÜZ zemin (açıkta #F8FAFC, koyuda #0F172A; sade stil G6: degrade ve ışıma yok) |
| [lib/styles/app_decorations.dart:38](../../lib/styles/app_decorations.dart#L38) | <code>static BoxDecoration glassCard(BuildContext context) =&gt;</code> | Palet yüzeyi + 1 px palet kenarı, GÖLGESİZ kart (sade stil; eski cam kartın yerine, ad aynı) |
| [lib/styles/app_decorations.dart:46](../../lib/styles/app_decorations.dart#L46) | <code>static BoxDecoration glowingBadge(Color accentColor, {bool isDark = true}) =&gt; BoxDecorati…</code> | Kapsül rozet (adı eski; sade stilde ışıma yok): isDark varsayılanı TRUE; açık temada false verilmezse koyu tema saydamlığıyla çizilir |

**Olası nedenler**
- glowingBadge çağrısında isDark verilmemiş: açık temada koyu rozet tonu
- Sabit glassCardDark/Light doğrudan kullanılıyor, tema değişince güncellenmiyor

**Adım adım kontrol**
- Çağıranda context.palette.isDark verildiğini kontrol edin

**Bkz.:** [ui-tema-gecisi](31-uygulama-arayuz.md#ui-tema-gecisi), [bilesen-eski-renkler](#bilesen-eski-renkler)

<a id="bilesen-eski-renkler"></a>
### bilesen-eski-renkler · Bir ekranda renkler tema ile uyumsuz (sabit AppColors değeri), metin koyu zeminde okunmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/styles/app_colors.dart:58](../../lib/styles/app_colors.dart#L58) | <code>static bool isDark(BuildContext context) =&gt;</code> | Tema duyarlı yardımcıların kökü |
| [lib/styles/app_colors.dart:67](../../lib/styles/app_colors.dart#L67) | <code>static Color textMutedColor(BuildContext context) =&gt;</code> | Soluk metin: koyuda açık gri, açıkta slate |
| [lib/styles/app_colors.dart:47](../../lib/styles/app_colors.dart#L47) | <code>static const Color textMuted = Color(0xFF64748B);</code> | Sabit renk: koyu zeminde düşük kontrast; context yardımcısı tercih edilmeli |
| [lib/ui/design/tokens.dart:64](../../lib/ui/design/tokens.dart#L64) | <code>class AppPalette extends ThemeExtension&lt;AppPalette&gt; {</code> | Yeni kod bu palete (context.palette) bağlanmalı; AppColors eski yüzeydir |

**Olası nedenler**
- Bileşen sabit AppColors.* kullanıyor, context.palette ya da AppColors.xxx(context) kullanmıyor

**Adım adım kontrol**
- --where "AppColors.textMuted" ile sabit kullanımları bulun

**İlgili testler:** [test/design/contrast_test.dart](../../test/design/contrast_test.dart)

**Bkz.:** [ui-koyu-tema-okunmuyor](31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor), [bilesen-sayfa-zemini](#bilesen-sayfa-zemini)

<a id="bilesen-saat-donuyor"></a>
### bilesen-saat-donuyor · Dijital saat durmuş gibi, uygulamaya dönünce yanlış saat gösteriyor ya da saat kartı her saniye yeniden kuruluyor (takılma)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/digital_clock_widget.dart:61](../../lib/ui/widgets/digital_clock_widget.dart#L61) | <code>_timer = Timer.periodic(const Duration(seconds: 1), (_) =&gt; _tick());</code> | Saniyelik zamanlayıcı yalnız iki ValueNotifier ı günceller; kart iskeleti yeniden kurulmaz |
| [lib/ui/widgets/digital_clock_widget.dart:70](../../lib/ui/widgets/digital_clock_widget.dart#L70) | <code>void didChangeAppLifecycleState(AppLifecycleState state) {</code> | Arka planda zamanlayıcı durur; öne gelince hemen _tick + yeniden başlatma |
| [lib/ui/widgets/digital_clock_widget.dart:215](../../lib/ui/widgets/digital_clock_widget.dart#L215) | <code>valueListenable: _timeText,</code> | Yalnız saat metni (kendi RepaintBoundary sinde) her saniye yeniden kurulur |
| [lib/ui/widgets/digital_clock_widget.dart:27](../../lib/ui/widgets/digital_clock_widget.dart#L27) | <code>final DateTime Function() nowProvider;</code> | Testte sahte saat verilebilir; üretimde DateTime.now |

**Olası nedenler**
- Uygulama arka plandayken zamanlayıcı bilerek durur; öne gelince _tick çağrılır
- Cihaz saati/saat dilimi yanlış: metin cihazın yerel saatindedir (rozet "TSİ (UTC+3)" yazar ama saat dönüşümü yapılmaz)
- Üst widget her saniye setState yapıyorsa kart yine de yeniden kurulur (bu bileşenin dışında)

**Adım adım kontrol**
- Cihaz saat/saat dilimi ayarını doğrulayın
- Ana sayfada DigitalClockWidget için key değişimi ya da sık setState olup olmadığına bakın

**İlgili testler:** [test/digital_clock_widget_test.dart](../../test/digital_clock_widget_test.dart)

**Bkz.:** [bilesen-saat-tasma](#bilesen-saat-tasma)

<a id="bilesen-saat-tasma"></a>
### bilesen-saat-tasma · Dijital saat kartında saat, TSİ rozeti ya da kullanıcı adı/rol dar ekranda taşıyor ya da alt alta kayıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/digital_clock_widget.dart:148](../../lib/ui/widgets/digital_clock_widget.dart#L148) | <code>Widget _buildTopRow(BuildContext context, Widget timeBlock, Widget zoneBadge) {</code> | Genişlik yetmezse saat ve rozet Wrap ile alt alta iner (taşmaz) |
| [lib/ui/widgets/digital_clock_widget.dart:143](../../lib/ui/widgets/digital_clock_widget.dart#L143) | <code>static const double _minInlineShrink = 0.85;</code> | Saat bloğu en çok %15 küçülerek rozetle yan yana kalabilir; aşarsa Wrap |
| [lib/ui/widgets/digital_clock_widget.dart:253](../../lib/ui/widgets/digital_clock_widget.dart#L253) | <code>label: 'TSİ (UTC+3)',</code> | Sabit metin: saat dilimi dönüşümü yapılmaz, yalnız etikettir |
| [lib/ui/widgets/digital_clock_widget.dart:91](../../lib/ui/widgets/digital_clock_widget.dart#L91) | <code>String _formatTurkishDate(DateTime dt) {</code> | Tarih Türkçe gün/ay adlarıyla biçimlenir |

**Olası nedenler**
- Yazı ölçeği büyük: yerleşim tahminleri (_timeTextWidth, _badgeTextWidth) sabit sayılara dayanır
- Uzun kullanıcı adı elips ile kısalır

**Adım adım kontrol**
- Büyük yazı ve dar ekranla düzeni gözden geçirin

**İlgili testler:** [test/digital_clock_widget_test.dart](../../test/digital_clock_widget_test.dart)

**Bkz.:** [bilesen-saat-donuyor](#bilesen-saat-donuyor), [bilesen-durum-rozeti](#bilesen-durum-rozeti)

<a id="bilesen-sesli-banner"></a>
### bilesen-sesli-banner · Kart içindeki sesli dinleme bandı yanlış durum/metin gösteriyor, mikrofon düğmesi dinlemeyi başlatmıyor ya da büyük yazıda metin eziliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/voice_live_banner.dart:22](../../lib/ui/widgets/voice_live_banner.dart#L22) | <code>class VoiceLiveBanner extends StatelessWidget {</code> | Servise bağlanır (AnimatedBuilder) ve durumu görünüme iletir |
| [lib/ui/widgets/voice_live_banner.dart:199](../../lib/ui/widgets/voice_live_banner.dart#L199) | <code>onPressed: listening ? onStop : onStart,</code> | Dinliyorsa durdurur, değilse startListening çağırır |
| [lib/ui/widgets/voice_live_banner.dart:225](../../lib/ui/widgets/voice_live_banner.dart#L225) | <code>factory _VoiceBannerLook.of(</code> | Durum -> ton, simge, başlık ve alt başlık eşlemesi |
| [lib/ui/widgets/voice_live_banner.dart:145](../../lib/ui/widgets/voice_live_banner.dart#L145) | <code>final compact = textWidth &lt; _minTextEm * 16 * scale;</code> | Dar/büyük yazıda simge gizlenir, metin daha çok satıra yayılır |
| [lib/ui/widgets/voice_live_banner.dart:40](../../lib/ui/widgets/voice_live_banner.dart#L40) | <code>onStart: () =&gt; service.startListening(candidateDoors: candidateDoors),</code> | Aday kapılar listesi sesli komutun hangi kapıyı açacağını belirler |

**Olası nedenler**
- Servis durumu (VoiceStatus) beklenmedik: idle/initializing aynı "Başlatmak için dokunun" görünümünü alır
- candidateDoors boş/yanlış verilmiş: komut hedef kapıyı bulamaz (servis tarafı)
- Mikrofon izni verilmemiş ya da konuşma motoru başlamıyor (servis katmanı)

**Adım adım kontrol**
- Servis durumunu ve feedbackText i kontrol edin
- Banner ı kullanan kartlarda candidateDoors verilip verilmediğine bakın

**İlgili testler:** [test/voice_live_banner_test.dart](../../test/voice_live_banner_test.dart), [test/voice_door_service_test.dart](../../test/voice_door_service_test.dart)

**Bkz.:** [bilesen-sesli-modal](#bilesen-sesli-modal)

<a id="bilesen-sesli-modal"></a>
### bilesen-sesli-modal · Sesli kontrol penceresi otomatik kapanmıyor/çok erken kapanıyor, nabız animasyonu takılıyor ya da dinlemeyi durdurmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/voice_control_modal.dart:26](../../lib/ui/widgets/voice_control_modal.dart#L26) | <code>static Future&lt;void&gt; show(</code> | showModalBottomSheet ile açılır; voiceService ve aday kapılar verilir |
| [lib/ui/widgets/voice_control_modal.dart:77](../../lib/ui/widgets/voice_control_modal.dart#L77) | <code>widget.voiceService.startListening(candidateDoors: widget.candidateDoors);</code> | Pencere açılır açılmaz ilk karede dinlemeyi otomatik başlatır |
| [lib/ui/widgets/voice_control_modal.dart:100](../../lib/ui/widgets/voice_control_modal.dart#L100) | <code>void _onVoiceStatusChange() {</code> | Başarıda 1,4 sn, hatada 2,5 sn sonra pencere kendiliğinden kapanır |
| [lib/ui/widgets/voice_control_modal.dart:90](../../lib/ui/widgets/voice_control_modal.dart#L90) | <code>void _syncPulse() {</code> | Nabız yalnız dinlerken ve hareket azaltma kapalıyken döner |
| [lib/ui/widgets/voice_control_modal.dart:128](../../lib/ui/widgets/voice_control_modal.dart#L128) | <code>_pulseController.dispose();</code> | Pencere kapanırken (dispose) nabız denetleyicisi bırakılır ve hemen ardından dinleme durdurulur |

**Olası nedenler**
- Başarı/hata sonrası otomatik kapanma tasarım gereği: kullanıcı tekrar dinletmek için yeniden açar
- Hareket azaltma açık: nabız yok
- Ses motoru başlatılamadı: durum error, metin feedbackText ten gelir

**Adım adım kontrol**
- VoiceDoorService durumunu ve feedbackText i kontrol edin
- Mikrofon/konuşma izinlerine bakın

**İlgili testler:** [test/voice_door_service_test.dart](../../test/voice_door_service_test.dart)

**Bkz.:** [bilesen-sesli-banner](#bilesen-sesli-banner), [bilesen-sesli-modal-tasma](#bilesen-sesli-modal-tasma)

<a id="bilesen-sesli-modal-tasma"></a>
### bilesen-sesli-modal-tasma · Sesli kontrol penceresinde düğmeler taşıyor ya da pencere ekranı aşıyor; sesli yanıt (TTS) düğmesi çalışmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/voice_control_modal.dart:216](../../lib/ui/widgets/voice_control_modal.dart#L216) | <code>final maxHeight = MediaQuery.sizeOf(context).height * 0.92;</code> | Pencere yüksekliği ekranın %92 si ile sınırlı; içerik kaydırılır |
| [lib/ui/widgets/voice_control_modal.dart:370](../../lib/ui/widgets/voice_control_modal.dart#L370) | <code>MediaQuery.textScalerOf(context).scale(1) &gt; 1.3 &#124;&#124;</code> | Büyük yazı ya da dar ekranda Kapat/Dinle düğmeleri alt alta dizilir |
| [lib/ui/widgets/voice_control_modal.dart:309](../../lib/ui/widgets/voice_control_modal.dart#L309) | <code>widget.voiceService.ttsEnabled =</code> | Sesli yanıt anahtarı servisteki ttsEnabled alanını değiştirir |
| [lib/ui/widgets/voice_control_modal.dart:133](../../lib/ui/widgets/voice_control_modal.dart#L133) | <code>AppTone _statusTone(VoiceStatus status) {</code> | Durum rengi eşlemesi |

**Olası nedenler**
- ttsEnabled yalnız çalışma zamanı değeridir; kalıcılığı serviste aranmalı

**Adım adım kontrol**
- Büyük yazıyla pencereyi açıp düğme dizilimine bakın

**Bkz.:** [bilesen-sesli-modal](#bilesen-sesli-modal)

<a id="bilesen-eller-serbest-ayar"></a>
### bilesen-eller-serbest-ayar · Eller serbest / Araba modu ayarı kaydedilmiyor, Siri bağlantısı kopyalanınca mesaj çıkmıyor ya da ayar sayfası taşıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/hands_free_settings_dialog.dart:129](../../lib/ui/widgets/hands_free_settings_dialog.dart#L129) | <code>widget.voiceDoorService.setHandsFreeAutoListen(val);</code> | Anahtar değişince açılışta otomatik dinleme ayarı servise yazılır |
| [lib/ui/widgets/hands_free_settings_dialog.dart:50](../../lib/ui/widgets/hands_free_settings_dialog.dart#L50) | <code>Clipboard.setData(ClipboardData(text: text));</code> | Bağlantı panoya kopyalanır ve AppSnack ile bildirilir |
| [lib/ui/widgets/hands_free_settings_dialog.dart:162](../../lib/ui/widgets/hands_free_settings_dialog.dart#L162) | <code>'sitekapi://open?doorIndex=1',</code> | Siri/NFC kestirmesi için sabit örnek bağlantı: doorIndex=1 (ilk kapı) |
| [lib/ui/widgets/hands_free_settings_dialog.dart:62](../../lib/ui/widgets/hands_free_settings_dialog.dart#L62) | <code>final maxHeight = MediaQuery.sizeOf(context).height * 0.85;</code> | Alt sayfa ekranın %85 i ile sınırlı; içerik ListView ile kayar |

**Olası nedenler**
- Bağlantı şeması (sitekapi://) uygulamanın derin bağlantı kaydıyla uyuşmuyorsa kestirme uygulamayı açmaz
- Bağlantı her zaman doorIndex=1 yazar; başka kapı için kullanıcı elle değiştirmelidir

**Adım adım kontrol**
- Derin bağlantı işleyicisinin aynı şemayı dinlediğini --where "sitekapi" ile doğrulayın

**Bkz.:** [bilesen-sesli-modal](#bilesen-sesli-modal), [bilesen-sesli-banner](#bilesen-sesli-banner)

<a id="bilesen-liste-ortak-parcalar"></a>
### bilesen-liste-ortak-parcalar · Liste ekranlarında sayfalama okları, baş harf avatarı ya da ikon karosu büyük yazıda kayboluyor; kart dolgusu dar ekranda farklı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/list_parts.dart:18](../../lib/ui/widgets/list_parts.dart#L18) | <code>bool isLargeText(BuildContext context) =&gt;</code> | Yazı ölçeği 1,75 ve üstüyse true: avatar ve ikon karosu gizlenir |
| [lib/ui/widgets/list_parts.dart:254](../../lib/ui/widgets/list_parts.dart#L254) | <code>class InitialAvatar extends StatelessWidget {</code> | Adın ilk harfi (boşsa "?"); büyük yazıda hiç çizilmez |
| [lib/ui/widgets/list_parts.dart:309](../../lib/ui/widgets/list_parts.dart#L309) | <code>class IconTile extends StatelessWidget {</code> | Yuvarlak tonlu ikon karosu; büyük yazıda gizlenir |
| [lib/ui/widgets/list_parts.dart:199](../../lib/ui/widgets/list_parts.dart#L199) | <code>class PaginationBar extends StatelessWidget {</code> | Önceki/sonraki okları 44 dp; onPrevious/onNext null ise ok devre dışı |
| [lib/ui/widgets/list_parts.dart:22](../../lib/ui/widgets/list_parts.dart#L22) | <code>EdgeInsets listCardPadding(BuildContext context) =&gt; EdgeInsets.all(</code> | 360 dp altı ekranda kart dolgusu 12, değilse 16 |

**Olası nedenler**
- Büyük yazı tipi: avatar/ikon karosu bilerek gizlenir (yer açmak için)
- Sayfalama okları pasif: çağıran sınırda onPrevious/onNext e null veriyor

**Adım adım kontrol**
- Yazı ölçeğini normale alıp tekrar bakın
- Çağıranda sayfa sınır koşullarını kontrol edin

**İlgili testler:** [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [bilesen-genisleyen-kart](#bilesen-genisleyen-kart), [bilesen-liste-iskeleti](#bilesen-liste-iskeleti)

<a id="bilesen-genisleyen-kart"></a>
### bilesen-genisleyen-kart · Listedeki kart açılıp kapanmıyor, ok simgesi dönmüyor ya da genişleme animasyonu takılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/list_parts.dart:103](../../lib/ui/widgets/list_parts.dart#L103) | <code>class ExpandableSection extends StatelessWidget {</code> | expanded değerine göre yükseklik faktörü animasyonu; kapalıyken boş kutu |
| [lib/ui/widgets/list_parts.dart:144](../../lib/ui/widgets/list_parts.dart#L144) | <code>turns: expanded ? 0.5 : 0,</code> | Ok yarım tur döner |
| [lib/ui/widgets/managed_user_card.dart:153](../../lib/ui/widgets/managed_user_card.dart#L153) | <code>onTap: () =&gt; setState(() =&gt; _expanded = !_expanded),</code> | Kartlar açık/kapalı durumunu kendi State inde tutar; yeniden kurulursa kapanır |

**Olası nedenler**
- Kart yeniden kurulunca (key değişimi/liste yenilemesi) _expanded sıfırlanır ve kart kapanır
- Hareket azaltma açık: açılma anlıktır

**Adım adım kontrol**
- Kartın listede kararlı key ile kurulduğunu kontrol edin

**İlgili testler:** [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [bilesen-hareket-azaltma](#bilesen-hareket-azaltma), [bilesen-yonetilen-kullanici-karti](#bilesen-yonetilen-kullanici-karti)

<a id="bilesen-liste-iskeleti"></a>
### bilesen-liste-iskeleti · Liste ilk yüklenirken iskelet satırları sonsuza dek kalıyor ya da boş liste kartı yanlış görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/list_parts.dart:345](../../lib/ui/widgets/list_parts.dart#L345) | <code>class ListSkeleton extends StatelessWidget {</code> | rows adet satır; kendi ShimmerScope unu kurar, çağıran yüklenince ağaçtan çıkarmalı |
| [lib/ui/widgets/list_parts.dart:399](../../lib/ui/widgets/list_parts.dart#L399) | <code>class EmptyCard extends StatelessWidget {</code> | Boş liste kartı: EmptyState + isteğe bağlı alt çocuk |
| [lib/ui/widgets/list_parts.dart:34](../../lib/ui/widgets/list_parts.dart#L34) | <code>class PageHeaderCard extends StatelessWidget {</code> | Başlık kartı; 680 dp altında eylem başlığın altına iner |

**Olası nedenler**
- Çağıran yükleme bitince ListSkeleton ı kaldırmıyor (isLoading bayrağı sıfırlanmıyor)
- Boş durum ile yükleme durumu karıştırılmış

**Adım adım kontrol**
- Listeyi kuran görünümde yükleme bayrağının hata dalında da sıfırlandığını doğrulayın

**Bkz.:** [bilesen-iskelet-bitmiyor](#bilesen-iskelet-bitmiyor), [bilesen-bos-durum](#bilesen-bos-durum)

<a id="bilesen-eylem-dugme-stilleri"></a>
### bilesen-eylem-dugme-stilleri · Karttaki Düzenle/Sil/Onayla düğmeleri tema ile uyumsuz renkte, devre dışıyken okunmuyor ya da dokunma alanı küçük

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/list_parts.dart:448](../../lib/ui/widgets/list_parts.dart#L448) | <code>ButtonStyle tonalActionStyle(</code> | Tonlu zeminli outlined düğme; minimum yükseklik 44 |
| [lib/ui/widgets/list_parts.dart:477](../../lib/ui/widgets/list_parts.dart#L477) | <code>ButtonStyle dangerOutlineStyle(BuildContext context) {</code> | Silme/ret düğmesi: danger tonlu kenar |
| [lib/ui/widgets/list_parts.dart:500](../../lib/ui/widgets/list_parts.dart#L500) | <code>ButtonStyle filledToneStyle(</code> | Düz dolgu, gölgesiz tonlu düğme (Onayla) |

**Olası nedenler**
- Çağıran bu stilleri kullanmayıp tema varsayılanını kullanmış
- Devre dışı renkleri palette textSecondary/border dır; çok soluksa palet değerine bakın

**Adım adım kontrol**
- Düğmenin style: parametresini kontrol edin

**Bkz.:** [bilesen-eski-renkler](#bilesen-eski-renkler)

<a id="bilesen-cihaz-karti-durum"></a>
### bilesen-cihaz-karti-durum · Şirket cihaz kartında çevrimiçi/çevrimdışı, "KAPI ATANMAMIŞ" ya da "ARIZALI" rozeti yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/company_device_card.dart:94](../../lib/ui/widgets/company_device_card.dart#L94) | <code>final isOnline = device.mqttConnected == true;</code> | Çevrimiçi yalnız mqttConnected == true iken; null ise "Bilinmiyor" |
| [lib/ui/widgets/company_device_card.dart:162](../../lib/ui/widgets/company_device_card.dart#L162) | <code>label: 'KAPI ATANMAMIŞ',</code> | assignedDoorId boş ya da 0 ise gösterilir; kart uyarı tonlu olur |
| [lib/ui/widgets/company_device_card.dart:167](../../lib/ui/widgets/company_device_card.dart#L167) | <code>label: 'ARIZALI',</code> | Cihaz arızalı işaretliyse rozet çıkar |
| [lib/ui/widgets/company_device_card.dart:151](../../lib/ui/widgets/company_device_card.dart#L151) | <code>pulse: isOnline,</code> | Çevrimiçi rozet nabız atar (3 tur, durur) |

**Olası nedenler**
- mqttConnected sunucudan gelmiyor/null: kart "Bilinmiyor" gösterir (cihaz durumu için sunucu ve MQTT tarafına bakın)
- assignedDoorId 0 ya da null: cihaz atanmamış sayılır
- Son görülme eski ama mqttConnected true: sunucudaki durum bayrağı bayat olabilir

**Adım adım kontrol**
- Cihaz API yanıtında mqttConnected, assignedDoorId, isDefective alanlarına bakın
- Cihaz çevrimdışı görünüyorsa sunucu/MQTT bölümlerindeki cihaz girişlerine geçin

**İlgili testler:** [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [bilesen-durum-rozeti](#bilesen-durum-rozeti), [bilesen-cihaz-karti-ayrinti](#bilesen-cihaz-karti-ayrinti)

<a id="bilesen-cihaz-karti-ayrinti"></a>
### bilesen-cihaz-karti-ayrinti · Cihaz kartı ayrıntılarında Wi-Fi gücü, firmware, OTA durumu ya da sahip bilgisi yanlış/eksik; Depoya Al ve Arızalı İşaretle düğmeleri görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/company_device_card.dart:216](../../lib/ui/widgets/company_device_card.dart#L216) | <code>Widget _buildDetails(BuildContext context, bool isAssigned) {</code> | Genişleyen bölüm: bilgi çipleri ve eylem düğmeleri |
| [lib/ui/widgets/company_device_card.dart:260](../../lib/ui/widgets/company_device_card.dart#L260) | <code>'OTA Durumu: ${device.displayOtaStatus}',</code> | OTA durumu yalnız süper kullanıcıya gösterilir |
| [lib/ui/widgets/company_device_card.dart:296](../../lib/ui/widgets/company_device_card.dart#L296) | <code>if (widget.isSuperUser &amp;&amp; widget.onToggleDefect != null)</code> | Arıza işaretleme düğmesi süper kullanıcıya ve geri çağrı doluysa |
| [lib/ui/widgets/company_device_card.dart:315](../../lib/ui/widgets/company_device_card.dart#L315) | <code>(device.assignedDoorId != null &#124;&#124; device.hasOwner))</code> | Depoya Al yalnız kapıya atanmış ya da sahibi olan cihazda görünür |
| [lib/ui/widgets/company_device_card.dart:224](../../lib/ui/widgets/company_device_card.dart#L224) | <code>: '%${device.wifiSignalPercent}'</code> | Wi-Fi gücü yüzde (ve varsa dBm) olarak yazılır; veri yoksa "-" |

**Olası nedenler**
- Düğme/çip yalnız isSuperUser true iken çıkar: rol kontrolü ya da çağıran geri çağrı vermemiş
- Cihaz alanları (wifiSignalPercent, firmwareVersion) sunucudan gelmiyorsa "-" görünür

**Adım adım kontrol**
- Kartı kuran görünümde isSuperUser ve onToggleDefect/onReleaseOwnership verildiğini kontrol edin

**İlgili testler:** [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [bilesen-cihaz-karti-durum](#bilesen-cihaz-karti-durum), [bilesen-genisleyen-kart](#bilesen-genisleyen-kart)

<a id="bilesen-daire-karti"></a>
### bilesen-daire-karti · Yönetici daire kartında sakin bilgisi, Aktif/Pasif rozeti ya da "Bilgileri Gönder" düğmesi yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/apartment_card.dart:104](../../lib/ui/widgets/apartment_card.dart#L104) | <code>apartment.residentIsActive ?? (hasResident &amp;&amp; apartment.isActive);</code> | Aktif/Pasif: sakin durumu varsa o, yoksa sakin var ve daire aktif |
| [lib/ui/widgets/apartment_card.dart:140](../../lib/ui/widgets/apartment_card.dart#L140) | <code>label: active ? 'Aktif' : 'Pasif',</code> | Rozet etiketi ve rengi |
| [lib/ui/widgets/apartment_card.dart:269](../../lib/ui/widgets/apartment_card.dart#L269) | <code>onPressed: widget.resettingPin &#124;&#124; needsSuper</code> | PIN'i Sıfırla yalnız dahili daire hesabında (resident_pin_resettable); sakin şifresini kendisi belirlemişse (resident_pin_issued false) yöneticide devre dışı + 'yalnız süper kullanıcı' notu; sıfırlanırken pasif ve dönen gösterge |
| [lib/ui/widgets/apartment_card.dart:228](../../lib/ui/widgets/apartment_card.dart#L228) | <code>? 'Şifre (PIN): yönetim verdi'</code> | PIN değeri ASLA yazılmaz (sunucu saklamaz, migration 051); yalnız "verildi" durumu ve "bir kez gösterilir" notu |
| [lib/ui/widgets/apartment_card.dart:298](../../lib/ui/widgets/apartment_card.dart#L298) | <code>if (hasResident &amp;&amp; widget.onDelete != null)</code> | Sakini Sil düğmesi yalnız sakin varsa |

**Olası nedenler**
- Sakin adı boş: daire boş sayılır (turuncu ikon, Sakini Sil yok)
- Sakin e-postası yok: Bilgileri Gönder gizli

**Adım adım kontrol**
- Daire API yanıtında residentFullName, residentEmail, residentIsActive alanlarına bakın

**İlgili testler:** [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [bilesen-genisleyen-kart](#bilesen-genisleyen-kart), [bilesen-bireysel-daire-karti](#bilesen-bireysel-daire-karti)

<a id="bilesen-bireysel-daire-karti"></a>
### bilesen-bireysel-daire-karti · Bireysel kullanıcının daire kartında "Daire Yöneticisi / Aile Üyesi" rozeti, üye listesi ya da "Üyeyi Çıkar" düğmesi yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/individual_apartment_card.dart:35](../../lib/ui/widgets/individual_apartment_card.dart#L35) | <code>final isAdmin = apt.isApartmentAdmin;</code> | Daire yöneticisi bayrağı ton, rozet ve çıkarma yetkisini belirler |
| [lib/ui/widgets/individual_apartment_card.dart:129](../../lib/ui/widgets/individual_apartment_card.dart#L129) | <code>!apt.members[i].isApartmentAdmin,</code> | Çıkarma yalnız yönetici için; kendini ve diğer yöneticiyi çıkaramaz |
| [lib/ui/widgets/individual_apartment_card.dart:116](../../lib/ui/widgets/individual_apartment_card.dart#L116) | <code>'Henüz başka sakin bulunmuyor.',</code> | Üye listesi boşken gösterilen metin |
| [lib/ui/widgets/individual_apartment_card.dart:221](../../lib/ui/widgets/individual_apartment_card.dart#L221) | <code>tooltip: 'Üyeyi Çıkar',</code> | Onay diyaloğu bu kartta değil, üst görünümde açılır |

**Olası nedenler**
- Kullanıcı daire yöneticisi değil: çıkarma düğmesi hiç görünmez
- Üye listesi sunucudan eksik geliyor (members boş)

**Adım adım kontrol**
- Daire/üye API yanıtında isApartmentAdmin ve isCurrentUser alanlarına bakın
- Onay diyaloğu için bireysel ana görünüme geçin

**Bkz.:** [bilesen-daire-karti](#bilesen-daire-karti), [ui-bireysel-ana-ekran-kapilar](31-uygulama-arayuz.md#ui-bireysel-ana-ekran-kapilar)

<a id="bilesen-yonetilen-kullanici-karti"></a>
### bilesen-yonetilen-kullanici-karti · Yönetilen kullanıcı kartında aktif/pasif anahtarı çalışmıyor, kendi hesabında kapatılamıyor ya da Sil düğmesi yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/managed_user_card.dart:188](../../lib/ui/widgets/managed_user_card.dart#L188) | <code>onChanged: widget.isSelf</code> | Kendi hesabında anahtar devre dışıdır (kendini pasifleştirememe) |
| [lib/ui/widgets/managed_user_card.dart:179](../../lib/ui/widgets/managed_user_card.dart#L179) | <code>widget.activationBusy</code> | İşlem sürerken anahtar yerine dönen gösterge |
| [lib/ui/widgets/managed_user_card.dart:242](../../lib/ui/widgets/managed_user_card.dart#L242) | <code>if (!widget.isSelf &amp;&amp; widget.onDelete != null)</code> | Sil düğmesi kendi hesabında ve geri çağrı yoksa gizlidir |
| [lib/ui/widgets/managed_user_card.dart:219](../../lib/ui/widgets/managed_user_card.dart#L219) | <code>InfoChip('Kullanıcı ID: ${user.id}'),</code> | Ayrıntıda kimlik, e-posta ve telefon çipleri |

**Olası nedenler**
- isSelf true: tasarım gereği anahtar ve Sil kapalı
- activationBusy true kalmış: çağıran işlem sonunda sıfırlamamış

**Adım adım kontrol**
- Çağıran görünümde activationBusy bayrağını ve onActivationChanged sonucunu kontrol edin

**Bkz.:** [bilesen-genisleyen-kart](#bilesen-genisleyen-kart)

<a id="bilesen-onay-bekleyen-kartlar"></a>
### bilesen-onay-bekleyen-kartlar · Site onay isteği ya da abonelik talebi kartında Onayla/Reddet düğmeleri yok, dönüp duruyor ya da bilgiler eksik

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/site_approval_request_card.dart:10](../../lib/ui/widgets/site_approval_request_card.dart#L10) | <code>class SiteApprovalRequestCard extends StatelessWidget {</code> | Site onay isteği: ad, blok/daire/kapı sayısı, yönetici, adres |
| [lib/ui/widgets/site_approval_request_card.dart:105](../../lib/ui/widgets/site_approval_request_card.dart#L105) | <code>child: CircularProgressIndicator(</code> | busy true iken düğmeler yerine dönen gösterge çıkar |
| [lib/ui/widgets/subscription_request_card.dart:91](../../lib/ui/widgets/subscription_request_card.dart#L91) | <code>onApprove();</code> | Abonelik talebinde busy iken iki düğme pasif; Onayla üzerinde dönen gösterge |
| [lib/ui/widgets/subscription_request_card.dart:73](../../lib/ui/widgets/subscription_request_card.dart#L73) | <code>Text('E-posta: ${request.email}', style: th.bodyMedium),</code> | Talep sahibi e-postası; telefon yalnız doluysa |

**Olası nedenler**
- Çağıran busy değerini işlem hatasında false yapmıyor: kart sonsuz dönen gösterge ile kalır
- Talep verisinde alan boş (adres, yönetici): ilgili satır gizlenir

**Adım adım kontrol**
- Onay/ret işlemini yapan görünümde busy kimliğinin finally ile temizlendiğini doğrulayın

**Bkz.:** [ui-abonelik-site-onay-menude-yok](31-uygulama-arayuz.md#ui-abonelik-site-onay-menude-yok), [ui-site-silme-akisi](31-uygulama-arayuz.md#ui-site-silme-akisi)

<a id="bilesen-kurulum-secenek-karti"></a>
### bilesen-kurulum-secenek-karti · İlk açılışta "Site Sakini Girişi" / "Yönetici & Cihaz Kurulumu" seçenek kartları ya da başvuru kartı rozeti yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/setup_option_card.dart:24](../../lib/ui/widgets/setup_option_card.dart#L24) | <code>class SetupOptionCard extends StatelessWidget {</code> | Ton, ikon, başlık, rozet, açıklama ve eylem düğmesinden oluşan ortak kart |
| [lib/ui/widgets/join_request_card.dart:32](../../lib/ui/widgets/join_request_card.dart#L32) | <code>static JoinRequestStatus statusOf(JoinRequestRecord request) {</code> | Başvuru durumu: onaylı yeşil, reddedilmiş kırmızı, aksi hâlde "Onay Bekliyor" turuncu |
| [lib/ui/widgets/join_request_card.dart:46](../../lib/ui/widgets/join_request_card.dart#L46) | <code>final List&lt;Widget&gt; details;</code> | Ayrıntı satırlarını çağıran verir; iki ekranda farklıdır |

**Olası nedenler**
- Başvuru ne onaylı ne reddedilmiş görünüyorsa durum "Onay Bekliyor" sayılır (isApproved/isRejected alanları)
- Ayrıntı satırları çağıranın işidir: eksik bilgi çağıran ekranda aranmalı

**Adım adım kontrol**
- Başvuru kaydının durum alanlarını API yanıtında kontrol edin

**Bkz.:** [ui-kurulum-sihirbazi](31-uygulama-arayuz.md#ui-kurulum-sihirbazi), [ui-bireysel-ana-ekran-kapilar](31-uygulama-arayuz.md#ui-bireysel-ana-ekran-kapilar)

<a id="bilesen-cihaz-eylem-karti"></a>
### bilesen-cihaz-eylem-karti · Cihaz ekleme/eşleştirme seçeneği kartındaki düğme tepki vermiyor ya da kart genişliği bozuk

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/device_action_tile.dart:8](../../lib/ui/widgets/device_action_tile.dart#L8) | <code>class DeviceActionTile extends StatelessWidget {</code> | İkon + başlık + açıklama + tam genişlik düğme |
| [lib/ui/widgets/device_action_tile.dart:43](../../lib/ui/widgets/device_action_tile.dart#L43) | <code>onPressed: onPressed,</code> | Düğme yalnız çağıranın verdiği geri çağrıyı tetikler |

**Olası nedenler**
- Geri çağrı çağıranda eksik ya da yanlış işleve bağlı

**Adım adım kontrol**
- Kartı kullanan cihaz ekleme görünümünde onPressed bağlantısını kontrol edin

**Bkz.:** [ui-cihaz-sahiplen](31-uygulama-arayuz.md#ui-cihaz-sahiplen), [ui-cihaz-ekle-sonrasi](31-uygulama-arayuz.md#ui-cihaz-ekle-sonrasi)

<a id="bilesen-guvenlik-politikasi-dogrulama"></a>
### bilesen-guvenlik-politikasi-dogrulama · Site güvenlik politikası penceresinde konum (enlem/boylam/mesafe) hata veriyor ya da "Kaydedilemedi" çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/site_security_policy_dialog.dart:113](../../lib/ui/widgets/site_security_policy_dialog.dart#L113) | <code>GeofenceFormValidation validateGeofenceForm({</code> | Enlem -90..90, boylam -180..180, mesafe 10..2000 m; virgül ondalık kabul edilir |
| [lib/ui/widgets/site_security_policy_dialog.dart:147](../../lib/ui/widgets/site_security_policy_dialog.dart#L147) | <code>latError = 'Koordinatlar tanımsız görünüyor.';</code> | (0, 0) noktası geçersiz sayılır |
| [lib/ui/widgets/site_security_policy_dialog.dart:244](../../lib/ui/widgets/site_security_policy_dialog.dart#L244) | <code>Future&lt;void&gt; _handleSave() async {</code> | Konum doğrulaması açıkken doğrulama geçmezse kayıt yapılmaz |
| [lib/ui/widgets/site_security_policy_dialog.dart:298](../../lib/ui/widgets/site_security_policy_dialog.dart#L298) | <code>'Kaydedilemedi: ${e.toString().replaceFirst('Exception: ', '')}',</code> | Sunucu/servis hatası kullanıcıya bu mesajla gösterilir |
| [lib/ui/widgets/site_security_policy_dialog.dart:67](../../lib/ui/widgets/site_security_policy_dialog.dart#L67) | <code>final error = await authService.updateSiteSecurityPolicy(</code> | Kayıt çağrısı: yalnız süper kullanıcı özellik anahtarlarını ve QR süresini gönderir |

**Olası nedenler**
- Konum doğrulaması açık ama koordinat boş/aralık dışı/(0,0)
- Yönetici (süper olmayan) rolü: özellik anahtarları gönderilmez (null), yalnız konum ve QR giriş alanları gider
- Sunucu reddetti: hata metni Kaydedilemedi: ile görünür (sunucu günlüğüne bakın)

**Adım adım kontrol**
- Alan hata metinlerini okuyun
- Sunucu tarafında site güvenlik politikası ucunun yanıtını günlükten kontrol edin

**İlgili testler:** [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart)

**Bkz.:** [bilesen-guvenlik-politikasi-konum](#bilesen-guvenlik-politikasi-konum), [bilesen-guvenlik-politikasi-erisim](#bilesen-guvenlik-politikasi-erisim)

<a id="bilesen-guvenlik-politikasi-konum"></a>
### bilesen-guvenlik-politikasi-konum · "Mevcut Konumu Al" düğmesi koordinat doldurmuyor ya da GPS izni hatası çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/site_security_policy_dialog.dart:214](../../lib/ui/widgets/site_security_policy_dialog.dart#L214) | <code>Future&lt;void&gt; _fetchCurrentLocation() async {</code> | Konumu alırken düğme pasif (_isLocating); başarıda enlem/boylam alanları dolar |
| [lib/ui/widgets/site_security_policy_dialog.dart:218](../../lib/ui/widgets/site_security_policy_dialog.dart#L218) | <code>final fix = await GeofenceService.instance.acquireVerifiedPosition();</code> | Doğrulanmış konum servisten alınır; başarısızsa errorMessage gösterilir |
| [lib/ui/widgets/site_security_policy_dialog.dart:235](../../lib/ui/widgets/site_security_policy_dialog.dart#L235) | <code>fix.errorMessage ?? 'Konum alınamadı. Lütfen GPS iznini kontrol edin.',</code> | Hata metni servisten gelir, yoksa genel GPS izni uyarısı |

**Olası nedenler**
- Konum izni verilmemiş ya da GPS kapalı
- Konum doğrulama servisi konumu güvenilmez buldu (errorMessage)

**Adım adım kontrol**
- Cihaz konum iznini ve GPS i kontrol edin
- GeofenceService hata mesajını okuyun

**İlgili testler:** [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart)

**Bkz.:** [bilesen-guvenlik-politikasi-dogrulama](#bilesen-guvenlik-politikasi-dogrulama), [ui-qr-konum-hatasi](31-uygulama-arayuz.md#ui-qr-konum-hatasi)

<a id="bilesen-guvenlik-politikasi-erisim"></a>
### bilesen-guvenlik-politikasi-erisim · Site güvenlik politikasında kapı açma yöntemi (uygulama / QR / ikisi) seçilemiyor ya da QR yenilenme süresi değişmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/site_security_policy_dialog.dart:754](../../lib/ui/widgets/site_security_policy_dialog.dart#L754) | <code>onTap: isEnabled ? () =&gt; setState(() =&gt; _accessMode = mode) : null,</code> | Seçenek yalnız isEnabled (süper kullanıcı) iken tıklanır |
| [lib/ui/widgets/site_security_policy_dialog.dart:274](../../lib/ui/widgets/site_security_policy_dialog.dart#L274) | <code>final isQrActive = _accessMode != 'app_only';</code> | Erişim modundan QR açık mı hesaplanır |
| [lib/ui/widgets/site_security_policy_dialog.dart:275](../../lib/ui/widgets/site_security_policy_dialog.dart#L275) | <code>final isRemoteActive = _accessMode != 'qr_only';</code> | Erişim modundan uzaktan açma açık mı hesaplanır |
| [lib/ui/widgets/site_security_policy_dialog.dart:463](../../lib/ui/widgets/site_security_policy_dialog.dart#L463) | <code>title: 'Dinamik QR Yenilenme Süresi',</code> | QR dönüş süresi seçici; kayıtta qrRotationSeconds olarak gider |

**Olası nedenler**
- Kullanıcı süper kullanıcı değil: yöntem seçenekleri ve QR süresi kilitlidir ("Sadece Süper User")
- Mod app_only ise QR kapalı, qr_only ise uzaktan açma kapalı olur (tasarım gereği)

**Adım adım kontrol**
- Oturum rolünü kontrol edin (superUser / super_user)
- Sakin tarafında kapı açma düğmesi durumu için ilgili ui girişlerine bakın

**İlgili testler:** [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart)

**Bkz.:** [bilesen-guvenlik-politikasi-dogrulama](#bilesen-guvenlik-politikasi-dogrulama), [ui-kapi-ac-sakin](31-uygulama-arayuz.md#ui-kapi-ac-sakin)

<a id="bilesen-kapi-gecis-gecmisi"></a>
### bilesen-kapi-gecis-gecmisi · Kapı geçiş geçmişi (log) listesi yüklenmiyor, eski kapının kayıtları görünüyor ya da kapı açılınca liste güncellenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/door_logs_accordion.dart:70](../../lib/ui/widgets/door_logs_accordion.dart#L70) | <code>Future&lt;void&gt; _loadLogs({int? page}) async {</code> | Her istek bir belirteç alır; eski yanıt (kapı değişti) yok sayılır |
| [lib/ui/widgets/door_logs_accordion.dart:88](../../lib/ui/widgets/door_logs_accordion.dart#L88) | <code>final (result, error) = await service.listDoorAccessLogs(</code> | Sunucudan sayfa sayfa (10 kayıt) geçiş kaydı çekilir |
| [lib/ui/widgets/door_logs_accordion.dart:46](../../lib/ui/widgets/door_logs_accordion.dart#L46) | <code>void didUpdateWidget(covariant DoorLogsAccordion oldWidget) {</code> | Kapı/site değişince liste sıfırlanır; kapı açma bitince açıksa ilk sayfa yeniden yüklenir |
| [lib/ui/widgets/door_logs_accordion.dart:334](../../lib/ui/widgets/door_logs_accordion.dart#L334) | <code>onRetry: () =&gt; _loadLogs(page: _currentPage),</code> | Hata kutusundaki Tekrar Dene aynı sayfayı yeniden ister |
| [lib/ui/widgets/door_logs_accordion.dart:342](../../lib/ui/widgets/door_logs_accordion.dart#L342) | <code>title: 'Kayıtlı kapı geçiş kaydı bulunamadı.',</code> | Liste boşsa gösterilen kompakt boş durum |

**Olası nedenler**
- Oturum yok: "Giriş oturumu bulunamadı." (authService null)
- Sunucu hata döndü ya da bağlantı koptu: "Bağlantı hatası" / sunucu mesajı
- Bölüm kapalıyken kapı açılırsa liste yalnız sıfırlanır; açılınca yeniden yüklenir

**Adım adım kontrol**
- Sunucuda kapı geçiş günlüğü ucunun (listDoorAccessLogs) yanıtını kontrol edin
- Kapı/site seçiminin doğru geçtiğini doğrulayın

**Bkz.:** [bilesen-liste-girisi](#bilesen-liste-girisi), [bilesen-satir-ici-bildirim](#bilesen-satir-ici-bildirim), [bilesen-iskelet-bitmiyor](#bilesen-iskelet-bitmiyor)

<a id="bilesen-kapi-ac-dugmesi-durum"></a>
### bilesen-kapi-ac-dugmesi-durum · Kapıyı aç düğmesi yanlış durumda (hazır/açılıyor/çevrimdışı), başarı tiki görünmüyor ya da çevrimdışıyken tepki vermiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/door_open_button.dart:29](../../lib/ui/design/door_open_button.dart#L29) | <code>enum DoorOpenState {</code> | ready / opening / offline / disabled durumları |
| [lib/ui/design/door_open_button.dart:342](../../lib/ui/design/door_open_button.dart#L342) | <code>void _tap() {</code> | ready: onPressed; offline: titreme + onBlocked ?? onPressed; opening/disabled: hiçbir şey |
| [lib/ui/design/door_open_button.dart:297](../../lib/ui/design/door_open_button.dart#L297) | <code>void _showDone() {</code> | successTick artınca 1,4 sn başarı gösterimi; komut sürerken geldiyse bekletilir |
| [lib/ui/design/door_open_button.dart:350](../../lib/ui/design/door_open_button.dart#L350) | <code>if (!AppMotion.reduced(context)) _shake.forward(from: 0);</code> | Çevrimdışı titreme hareket azaltmada yoktur |

**Olası nedenler**
- Çağıran state i yanlış hesaplıyor (örn. cihaz çevrimiçi ama offline verilmiş)
- disabled durumunda dokunma bilerek hiçbir şey yapmaz; offline durumunda onBlocked gerekir
- Opening durumunda spinner sürekli döner: testte pumpAndSettle bitmez

**Adım adım kontrol**
- Düğmeyi kullanan kartta state ve successTick değerlerinin nasıl türetildiğine bakın

**İlgili testler:** [test/design/door_open_button_test.dart](../../test/design/door_open_button_test.dart)

**Bkz.:** [ui-kapi-ac-yonetici](31-uygulama-arayuz.md#ui-kapi-ac-yonetici), [ui-kapi-ac-sakin](31-uygulama-arayuz.md#ui-kapi-ac-sakin), [ui-kapi-ac-basari-tiki](31-uygulama-arayuz.md#ui-kapi-ac-basari-tiki)

<a id="bilesen-yan-menu-ogeleri"></a>
### bilesen-yan-menu-ogeleri · Yan menüde bir öğe yok ya da yanlış rolde görünüyor; menü dosyası (menu.dart) neyi dışa aktarıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/menu.dart:1](../../lib/menu.dart#L1) | <code>export 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';</code> | menu.dart tek satırlık yeniden dışa aktarımdır; gerçek kod yan_menu.dart ta |
| [lib/ui/widgets/yan_menu.dart:1320](../../lib/ui/widgets/yan_menu.dart#L1320) | <code>List&lt;SirketMenuItem&gt; _itemsForRole(</code> | Rol ve mod başına menü öğeleri burada seçilir |
| [lib/ui/widgets/yan_menu.dart:495](../../lib/ui/widgets/yan_menu.dart#L495) | <code>title: isResidentMode ? context.l10n.menuSwitchToAdmin : context.l10n.menuSwitchToResiden…</code> | Çift rollü kullanıcıda mod değiştirme satırı |

**Olası nedenler**
- _itemsForRole listesinde öğe o rol/mod için yok
- Mod değiştirme yalnız canToggleMode true iken çıkar

**Adım adım kontrol**
- Rol ve mod bayraklarını home_page tarafında kontrol edin

**Bkz.:** [ui-menu-yanlis-rol](31-uygulama-arayuz.md#ui-menu-yanlis-rol), [ui-mod-hapi](31-uygulama-arayuz.md#ui-mod-hapi), [ui-abonelik-site-onay-menude-yok](31-uygulama-arayuz.md#ui-abonelik-site-onay-menude-yok)

