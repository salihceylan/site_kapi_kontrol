# Flutter uygulama çekirdeği — kök, oturum, HTTP istemcisi, yerel kapı, konum, ses, BLE, widget, tema, PDF

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm lib/main.dart, lib/app.dart, lib/config, lib/models, lib/data, lib/services ve lib/styles/app_theme.dart içindeki istemci arızalarını kapsar. İlk bakılacak yerler: ağ/hata mesajı için lib/services/auth_api.dart (_sendRequest, _ensureStatus, _decodePayload, messageForErrorCode), oturum için lib/services/auth_service.dart (initialize, _handleSessionError, refreshSession), ekran seçimi için lib/app.dart (home).

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [lib/main.dart](../../lib/main.dart) | Giriş noktası: yön kilidi, tema tercihini önceden yükler, MyApp başlatır |
| [lib/app.dart](../../lib/app.dart) | Kök widget: servisleri kurar, oturum/ağ durumuna göre ekran seçer, deep link/kısayol/yaşam döngüsü |
| [lib/config/app_config.dart](../../lib/config/app_config.dart) | API adresi (--dart-define=API_BASE_URL), uygulama adı/sürümü |
| [lib/services/auth_api.dart](../../lib/services/auth_api.dart) | HTTP istemcisi: zaman aşımı, GET yeniden denemesi, durum kodu/hata kodu eşlemesi, JSON ayrıştırma |
| [lib/services/auth_service.dart](../../lib/services/auth_service.dart) | Oturum (güvenli depo, /me doğrulaması), kapı açma akışı (yerel/bulut/konum), widget senkronu |
| [lib/services/api_exception.dart](../../lib/services/api_exception.dart) | ApiException / SessionExpiredException: oturum sonu ve ara katman ayrımı |
| [lib/services/network_service.dart](../../lib/services/network_service.dart) | Açılışta internet yoklaması (/health + yedek adres) |
| [lib/services/local_door_service.dart](../../lib/services/local_door_service.dart) | Yerel ağ UDP: beacon dinleme, keşif, imzalı açma paketi (protokol v2) |
| [lib/services/geofence_service.dart](../../lib/services/geofence_service.dart) | Konum izni/GPS doğrulaması, mesafe hesabı |
| [lib/services/voice_door_service.dart](../../lib/services/voice_door_service.dart) | Sesle kapı açma: konuşma tanıma, Türkçe komut eşleme, sesli geri bildirim |
| [lib/services/ble_wifi_provision_service.dart](../../lib/services/ble_wifi_provision_service.dart) | Bluetooth ile cihaza Wi-Fi/MQTT bilgisi yazma |
| [lib/services/deep_link_service.dart](../../lib/services/deep_link_service.dart) | sitekapi:// bağlantıları ve kısayol eylemleri kuyruğu |
| [lib/services/quick_actions_service.dart](../../lib/services/quick_actions_service.dart) | Uygulama simgesi kısayolları (long-press) |
| [lib/services/door_widget_service.dart](../../lib/services/door_widget_service.dart) | Ana ekran widget'ı: kapı listesi senkronu ve arka planda kapı açma |
| [lib/services/theme_service.dart](../../lib/services/theme_service.dart) | Aydınlık/karanlık/sistem tema tercihi ve kalıcılığı |
| [lib/services/adaptive_poller.dart](../../lib/services/adaptive_poller.dart) | Yoklama zamanlayıcısı: üstel geri çekilme, görünür değilken atlama |
| [lib/services/background_work.dart](../../lib/services/background_work.dart) | Büyük JSON/PDF işlerini arka plan izolesine alır |
| [lib/services/pdf_font_set.dart](../../lib/services/pdf_font_set.dart) | PDF yazı tipleri (Roboto ya da Helvetica yedeği) |
| [lib/services/pdf_logs_service.dart](../../lib/services/pdf_logs_service.dart) | Kapı geçiş günlüğü PDF raporu |
| [lib/services/pdf_credentials_service.dart](../../lib/services/pdf_credentials_service.dart) | Site giriş bilgileri PDF raporu |
| [lib/services/pdf_device_firmware_service.dart](../../lib/services/pdf_device_firmware_service.dart) | Cihaz firmware durum PDF raporu |
| [lib/models/user_session.dart](../../lib/models/user_session.dart) | Oturum modeli (güvenli depoya JSON olarak yazılır) |
| [lib/models/door_record.dart](../../lib/models/door_record.dart) | Kapı modeli: politika bayrakları, geofence alanları, JSON ayrıştırma |
| [lib/models/door_runtime_status.dart](../../lib/models/door_runtime_status.dart) | Kapı canlı durumu modeli (cihaz çevrimiçi mi, yerel kontrol bilgisi) |
| [lib/models/local_door_access.dart](../../lib/models/local_door_access.dart) | Yerel kontrol anahtarı önbellek kaydı (24 saat geçerlilik) |
| [lib/data/turkey_cities_districts.dart](../../lib/data/turkey_cities_districts.dart) | İl/ilçe listesi (site oluşturma/düzenleme listeleri) |
| [lib/styles/app_theme.dart](../../lib/styles/app_theme.dart) | Aydınlık/karanlık ThemeData üretimi |

## Bu bölümdeki girişler (51)

- [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi) — Ekranda "Sunucuya bağlanılamadı" / "Sunucuya ulaşılamadı" / "Sunucuya baglanilamadi." hatası çıkıyor
- [cekirdek-api-adresi-yanlis](#cekirdek-api-adresi-yanlis) — Uygulama yanlış/eski sunucuya bağlanıyor ya da hiç bağlanamıyor (API adresi yanlış, localhost, http)
- [cekirdek-internet-yok-ekrani](#cekirdek-internet-yok-ekrani) — Giriş ekranı yerine "İnternet yok" ekranı çıkıyor (internet var) ya da o ekran kalkmıyor
- [cekirdek-acilis-splash-takili](#cekirdek-acilis-splash-takili) — Açılışta logo + dönen çark ekranı çok uzun sürüyor ya da hiç kalkmıyor
- [cekirdek-giris-sonrasi-ekran-bos](#cekirdek-giris-sonrasi-ekran-bos) — Giriş yaptıktan sonra ekran beyaz/boş kalıyor ya da giriş ekranından ilerlemiyor
- [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor) — Oturum kendiliğinden düşüyor: uygulama bir anda giriş ekranına dönüyor ("Oturum süreniz doldu. Lütfen tekrar giriş yapın.")
- [cekirdek-sifre-degisince-oturum-kapandi](#cekirdek-sifre-degisince-oturum-kapandi) — "Şifreniz değiştirildiği için oturumunuz sonlandırıldı" mesajıyla çıkış yapılıyor ya da şifre değişince uygulama düşüyor
- [cekirdek-hesap-pasif-oturum-kapandi](#cekirdek-hesap-pasif-oturum-kapandi) — Oturum kapanıp girişte "Hesap aktif degil.", "E-posta adresiniz dogrulanmadi.", "Abonelik talebiniz onay bekliyor." ya da "Hesabınız pasif duruma alındı. Lütfen yöneticinizle iletişime geçin." mesajı görünüyor
- [cekirdek-acilista-oturum-yok](#cekirdek-acilista-oturum-yok) — Uygulama her açılışta giriş istiyor (oturum hatırlanmıyor) ya da kayıtlı oturum silinmiş görünüyor
- [cekirdek-yanlis-rol-menu](#cekirdek-yanlis-rol-menu) — Kullanıcı yanlış rolle görünüyor (yönetici menüsü yok / daire kullanıcısı gibi) ya da rol değişikliği uygulamaya yansımıyor
- [cekirdek-sifre-degistirme-hatalari](#cekirdek-sifre-degistirme-hatalari) — Profilde şifre değişmiyor: "Mevcut şifreniz hatalı", "mevcut şifrenizi girmelisiniz" ya da "Kendi şifrenizi Profilim ekranından değiştirin"
- [cekirdek-hiz-siniri-cok-fazla-deneme](#cekirdek-hiz-siniri-cok-fazla-deneme) — "Çok fazla hatalı deneme yapıldı. N dakika sonra tekrar deneyin" ya da "Çok fazla istek gönderildi" (429) mesajı çıkıyor
- [cekirdek-dogrulama-kodu-hatalari](#cekirdek-dogrulama-kodu-hatalari) — E-posta doğrulama kodu kabul edilmiyor ("Kod 30 dakika geçerlidir; yeni kod için ...") ya da kod tekrar gönderilemiyor
- [cekirdek-kapi-ac-zaman-asimi](#cekirdek-kapi-ac-zaman-asimi) — Kapı açarken "Kapı komutuna zamanında yanıt alınamadı. Kapı açılmış olabilir..." ya da "Kapı açılamadı. Sunucuya bağlanılamadı."
- [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari) — Kapı açılmıyor ve ekranda "Cihaz şu an çevrimdışı", "Sunucunun cihaz bağlantısı şu an hazır değil" ya da "Bu sitede ... kapalı" yazıyor
- [cekirdek-kapi-ac-istemci-reddi](#cekirdek-kapi-ac-istemci-reddi) — Kapı açma düğmesine basınca istek hiç gitmeden "Bu kapı için uygulamadan açma kapalı." ya da "Bu kapıda uzaktan açma kapalı..." çıkıyor
- [cekirdek-kapi-ac-konum-zorunlu](#cekirdek-kapi-ac-konum-zorunlu) — Kapı açarken konum isteniyor ya da "Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin." hatası çıkıyor
- [cekirdek-konum-izni-gps-hatasi](#cekirdek-konum-izni-gps-hatasi) — "Konum servisleri kapalı", "Konum izni verilmedi", "GPS doğruluğu yetersiz", "Sahte konum tespit edildi" ya da "GPS sinyali alınamadı (zaman aşımı)"
- [cekirdek-konum-mesafe-disi](#cekirdek-konum-mesafe-disi) — "N m uzaktasınız, izin verilen mesafe M m. Lütfen kapıya yaklaşın." / "Kapı konumunda değilsiniz" / "konum çemberi tanımlı değil"
- [cekirdek-karekod-ile-kapi-acilmiyor](#cekirdek-karekod-ile-kapi-acilmiyor) — Karekod okutulunca kapı açılmıyor: "Karekod geçersiz", "süresi doldu", "daha önce kullanıldı" ya da "Karekod okutularak kapı açılamadı"
- [cekirdek-yerel-kapi-bulunmuyor](#cekirdek-yerel-kapi-bulunmuyor) — Yerel (Wi-Fi) kapı açma çalışmıyor: kapı her seferinde buluttan açılıyor ya da cihaz yerel ağda görünmüyor
- [cekirdek-yerel-udp-acma-basarisiz](#cekirdek-yerel-udp-acma-basarisiz) — Cihaz yerelde görünüyor ama UDP ile kapı açılmıyor (yanıt doğrulanamıyor, 150 ms içinde cevap yok)
- [cekirdek-yerel-beacon-alinmiyor](#cekirdek-yerel-beacon-alinmiyor) — Cihazın yerel ağ beacon'ı alınmıyor: "yerelde görünmüyor", beacon günlüğü hiç akmıyor
- [cekirdek-yerel-token-yok](#cekirdek-yerel-token-yok) — "Yerel kontrol anahtarı yok, bulut üzerinden açılıyor" ya da yerel açma hiç denenmiyor
- [cekirdek-kapi-durumu-cevrimdisi](#cekirdek-kapi-durumu-cevrimdisi) — Kapı durumu "çevrimdışı" görünüyor, durum geç güncelleniyor ya da durum hatası ekranda kalıyor
- [cekirdek-yasam-dongusu-dinleyici](#cekirdek-yasam-dongusu-dinleyici) — Uygulama arka plana alınıp dönünce cihaz yerelde bir süre görünmüyor ya da arka planda pil/ağ kullanımı soruluyor
- [cekirdek-kullanici-degisince-eski-veri](#cekirdek-kullanici-degisince-eski-veri) — Çıkış yapıp başka kullanıcıyla girince eski kullanıcının kapıları, sesli komut listesi ya da bekleyen kısayol/link görünüyor
- [cekirdek-proxy-html-modem-mesaji](#cekirdek-proxy-html-modem-mesaji) — Ekranda "İnternet bağlantısı yok (Modem internete bağlı değil)" çıkıyor, oysa telefonda internet var; ya da "güvenlik duvarı/proxy" mesajı
- [cekirdek-json-ayristirma-hatasi](#cekirdek-json-ayristirma-hatasi) — Ekranda "... verisi beklenen formatta degil." ya da "... verisi islenemedi." (ör. Oturum bilgisi, Profil bilgisi, Gecis kaydi) yazıyor
- [cekirdek-widget-bos-ya-da-giris-yapin](#cekirdek-widget-bos-ya-da-giris-yapin) — Ana ekran widget'ı "Giriş Yapın" ya da "Kapı Tanımlı Değil" gösteriyor, kapı adı boş ya da widget güncellenmiyor
- [cekirdek-widget-acma-sonuc-mesajlari](#cekirdek-widget-acma-sonuc-mesajlari) — Ana ekran widget'ındaki "Aç" düğmesi "Bağlantı hatası", "Yetkiniz yok", "Kapı çevrimdışı", "Konum için uygulamayı açın" ya da "Çok sık deneme, bekleyin" diyor; ya da düğmeye basınca hiçbir şey olmuyor
- [cekirdek-widget-kapi-gecisi](#cekirdek-widget-kapi-gecisi) — Widget'ta ◀ ▶ ile kapı değiştirilemiyor, yanlış kapı gösteriyor ya da kapı durumu (Çevrimiçi/Çevrimdışı) yanlış
- [cekirdek-sesli-komut-anlasilmadi](#cekirdek-sesli-komut-anlasilmadi) — Sesli komutla kapı açılmıyor: "Anlaşılamadı", "Hangi kapıyı açmamı istersiniz?", "Bu isimde bir kapı bulunamadı" ya da "Komut yakın zamanda işlendi"
- [cekirdek-sesli-komut-mikrofon-hatasi](#cekirdek-sesli-komut-mikrofon-hatasi) — Sesli komut başlamıyor: "Mikrofon veya ses tanıma izni alınamadı", "Ses motoru başlatılamadı", "Ses algılanamadı (...)" ya da cevap sesli okunmuyor
- [cekirdek-deep-link-kisayol-calismiyor](#cekirdek-deep-link-kisayol-calismiyor) — sitekapi:// bağlantısı ya da kısayol kapıyı açmıyor / hiçbir şey yapmıyor, ya da "Kapı açılsın mı?" onayı çıkıyor
- [cekirdek-kisayol-gorunmuyor](#cekirdek-kisayol-gorunmuyor) — Uygulama simgesine uzun basınca "Sesli Kapı Aç" / kapı kısayolları görünmüyor ya da kısayol eskimiş kapıyı gösteriyor
- [cekirdek-tema-tercihi-kaydedilmiyor](#cekirdek-tema-tercihi-kaydedilmiyor) — Koyu/aydınlık tema tercihi uygulama kapanınca sıfırlanıyor, yanlış temayla açılıyor ya da tema düğmesi tersini seçiyor
- [cekirdek-mqtt-dogrudan-baglanti](#cekirdek-mqtt-dogrudan-baglanti) — Uygulamadan doğrudan MQTT ile kapı komutu: "MQTT baglanamadi", "MQTT baglantisi kurulamadi", "Komut gonderilemedi" ya da web'de "Bu platform MQTT TCP baglantisini desteklemiyor."
- [cekirdek-ble-izin-ve-tarama](#cekirdek-ble-izin-ve-tarama) — Bluetooth ile cihaz kurulumunda cihaz listede görünmüyor ya da "Bluetooth kapali", "Konum servislerini acip tekrar deneyin", "Bluetooth izni verilmedi", "yalnizca Android ve iPhone" uyarısı çıkıyor
- [cekirdek-ble-baglanti-ve-wifi-listesi](#cekirdek-ble-baglanti-ve-wifi-listesi) — Bluetooth ile cihaza bağlanılamıyor ("Cihaza baglanilamadi veya baglanti koptu", "zaman asimina ugradi") ya da cihazın gördüğü Wi-Fi ağları listelenmiyor
- [cekirdek-ble-wifi-yazma-basarisiz](#cekirdek-ble-wifi-yazma-basarisiz) — Bluetooth ile Wi-Fi bilgisi yazılırken "MQTT cihaz kimligi hazir degil", "SSID secimi zorunludur", "Wi-Fi baglantisi kurulamadi" ya da "Wi-Fi baglantisi zaman asimina ugradi" hatası
- [cekirdek-pdf-turkce-karakter-font](#cekirdek-pdf-turkce-karakter-font) — PDF raporunda Türkçe karakterler (ş, ğ, İ, ı) bozuk/kutu görünüyor ya da PDF çevrimdışıyken farklı yazı tipiyle çıkıyor
- [cekirdek-pdf-gecis-raporu-bos](#cekirdek-pdf-gecis-raporu-bos) — Kapı geçiş günlüğü PDF raporu üretilmiyor, boş çıkıyor ya da "Çok sayıda kayıt var; rapor en yeni kayıtlarla sınırlandırıldı" / "rapor eksik olabilir" uyarısı veriyor
- [cekirdek-pdf-giris-bilgileri-raporu](#cekirdek-pdf-giris-bilgileri-raporu) — Site giriş bilgileri PDF'i (daire/kullanıcı şifre listesi) boş, eksik ya da paylaşılamıyor
- [cekirdek-pdf-firmware-raporu](#cekirdek-pdf-firmware-raporu) — Cihaz firmware/güncelleme PDF raporunda sürümler yanlış "güncel değil" görünüyor, "Bilinmiyor" çok ya da rapor oluşmuyor
- [cekirdek-sifremi-unuttum-eposta-gelmiyor](#cekirdek-sifremi-unuttum-eposta-gelmiyor) — "Şifremi unuttum" isteği başarılı görünüyor ama sıfırlama e-postası gelmiyor
- [cekirdek-kapi-listesi-bos-alinamadi](#cekirdek-kapi-listesi-bos-alinamadi) — Ana ekranda kapı listesi boş geliyor ya da kapılar yüklenmiyor ("Kapılar alınamadı", "Oturum bulunamadi")
- [cekirdek-cihaz-sahiplenme-hatalari](#cekirdek-cihaz-sahiplenme-hatalari) — Cihaz sahiplenme/ekleme sırasında "Bu cihaz başka bir hesaba ait", "Cihaz bulunamadı", "Bu cihaz arızalı olarak işaretlenmiş" ya da "Bu cihaz bu kapıya atanamaz" hatası
- [cekirdek-il-ilce-listesi](#cekirdek-il-ilce-listesi) — Site oluşturma/düzenlemede İl ya da İlçe listesi boş, il seçilince ilçe gelmiyor ya da kayıtlı il/ilçe seçili görünmüyor
- [cekirdek-buyuk-yanit-yavas-arayuz](#cekirdek-buyuk-yanit-yavas-arayuz) — Büyük listeler (site yapısı, günlükler) yüklenirken arayüz takılıyor ya da kareler atlıyor; PDF üretirken uygulama donuyor
- [cekirdek-uygulama-baslangic-yon-kilidi](#cekirdek-uygulama-baslangic-yon-kilidi) — Uygulama yatay döndürülemiyor ya da açılışta ekran yönü/tema beklenmedik; main.dart başlangıç sırası soruluyor

## Girişler

<a id="cekirdek-sunucuya-baglanilamadi"></a>
### cekirdek-sunucuya-baglanilamadi · Ekranda "Sunucuya bağlanılamadı" / "Sunucuya ulaşılamadı" / "Sunucuya baglanilamadi." hatası çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:3596](../../lib/services/auth_api.dart#L3596) | <code>} on http.ClientException catch (error) {</code> | Aktarım hatası (DNS, bağlantı kopması, TLS) burada yakalanır; GET ise bir kez yeniden denenir, değilse ApiException üretilir |
| [lib/services/auth_api.dart:4236](../../lib/services/auth_api.dart#L4236) | <code>String _mapClientError(http.ClientException error) {</code> | ClientException metnini üç Türkçe mesaja eşler: SSL, "Sunucuya ulasilamadi" (DNS/soket), genel istemci hatası |
| [lib/services/auth_api.dart:4222](../../lib/services/auth_api.dart#L4222) | <code>'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',</code> | Yanıt JSON değil (5xx/413/429 dışı) ve gövdede "<html"/"<!doctype"/router/modem/gateway YOK (düz metin vb.): ara katman hatası sayılır. HTML/router/modem/gateway içeren gövde ise "İnternet bağlantısı yok (Modem internete bağlı değil)." olur |
| [lib/services/auth_api.dart:3792](../../lib/services/auth_api.dart#L3792) | <code>'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyi…</code> | 401/403 yanıtının gövdesi JSON hata zarfı değil: proxy/WAF/captive portal; oturum SONU değildir |
| [lib/services/auth_service.dart:288-307](../../lib/services/auth_service.dart#L288-L307) | <code>_session = await api.login(</code> | Giriş: ApiException mesajı aynen döner; ApiException dışındaki HER istisna "Sunucuya baglanilamadi." olur (güvenilir cihaz belirtecinin okunup yazılması hata verse de girişi bozmaz) |
| [lib/services/auth_service.dart:523-534](../../lib/services/auth_service.dart#L523-L534) | <code>await api.registerIndividual(</code> | Kayıt (ve parola sıfırlama) için ayrı genel mesaj (Unicode yazımlı) |

**Olası nedenler**
- Telefonda internet yok ya da alan adı çözülemiyor (ClientException metninde "failed host lookup"/"socket" -> "Sunucuya ulasilamadi. Internet veya DNS ...")
- TLS/sertifika sorunu (metinde "certificate"/"handshake"/"tls" -> "SSL baglantisi kurulurken hata olustu.")
- API adresi yanlış ya da sunucu kapalı (bkz. cekirdek-api-adresi-yanlis)
- Araya giren katman (nginx hata sayfası, modem/captive portal) JSON olmayan gövde döndürdü (bkz. cekirdek-proxy-html-modem-mesaji)
- Kod ApiException dışında beklenmeyen bir istisna fırlattı: auth_service genel catch gerçek nedeni gizler ve aynı mesajı gösterir

**Adım adım kontrol**
- Mesajın yazımına bakın: ASCII "ulasilamadi/baglanilamadi" aktarım katmanından, Unicode "ulaşılamadı/bağlanılamadı" sunucu-ara katman yanıtından ya da kayıt/şifre akışından gelir
- Aynı ağdan sunucu sağlığını deneyin (aşağıdaki komut): 200 değilse sorun istemci dışındadır
- Derlemedeki API adresini doğrulayın (--dart-define=API_BASE_URL verildi mi)
- Sorun yalnız belirli bir ağdaysa (otel/şirket Wi-Fi) captive portal/proxy şüphesi: tarayıcıda aynı adresi açın
- Sunucu tarafında isteğin ulaşıp ulaşmadığına sunucu alanı girişlerinden bakın (günlükte ilgili yol arayın)

**Komutlar**
```bash
curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/health
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/auth_api_policy_test.dart
```

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart), [test/fix_fx1_session_test.dart](../../test/fix_fx1_session_test.dart)

**Bkz.:** [cekirdek-api-adresi-yanlis](#cekirdek-api-adresi-yanlis), [cekirdek-proxy-html-modem-mesaji](#cekirdek-proxy-html-modem-mesaji), [cekirdek-internet-yok-ekrani](#cekirdek-internet-yok-ekrani)

<a id="cekirdek-api-adresi-yanlis"></a>
### cekirdek-api-adresi-yanlis · Uygulama yanlış/eski sunucuya bağlanıyor ya da hiç bağlanamıyor (API adresi yanlış, localhost, http)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/config/app_config.dart:1](../../lib/config/app_config.dart#L1) | <code>const String _defaultApiBaseUrl = 'https://api.gudeteknoloji.com.tr';</code> | Varsayılan (canlı) API adresi: --dart-define verilmediyse bu kullanılır |
| [lib/config/app_config.dart:12](../../lib/config/app_config.dart#L12) | <code>'API_BASE_URL',</code> | Derleme zamanı geçersiz kılma anahtarı: --dart-define=API_BASE_URL=... (çalışma zamanında değişmez) |
| [lib/config/app_config.dart:20](../../lib/config/app_config.dart#L20) | <code>const String apiBaseUrl = AppConfig.baseUrl;</code> | Eski kodun kullandığı üst düzey takma ad; kök widget bunu okur |
| [lib/app.dart:122](../../lib/app.dart#L122) | <code>_authService = AuthService(api: AuthApi(baseUrl: apiBaseUrl));</code> | Tüm API istekleri bu tek AuthApi örneğiyle gider |
| [lib/services/network_service.dart:58](../../lib/services/network_service.dart#L58) | <code>Uri.parse('$apiBaseUrl/health'),</code> | Açılıştaki internet yoklaması da aynı adresin /health ucuna gider |
| [lib/services/auth_api.dart:3449](../../lib/services/auth_api.dart#L3449) | <code>final uri = Uri.parse('$baseUrl$path');</code> | Adres + yol düz birleştirilir (sonda "/" kırpılmaz): sonda "/" kalırsa "//auth/login" olur |
| [lib/services/door_widget_service.dart:72](../../lib/services/door_widget_service.dart#L72) | <code>String? normalizeWidgetApiBase(String? raw) {</code> | Widget yalnız https (ya da derlemedeki aynı http adresi) kabul eder; aksi halde widget "Giriş Yapın" der |
| [android/app/src/main/AndroidManifest.xml:36](../../android/app/src/main/AndroidManifest.xml#L36) | <code>android:usesCleartextTraffic="false"&gt;</code> | Release derlemede düz http KAPALI: http adresli release sürüm bağlanamaz |
| [android/app/src/debug/AndroidManifest.xml:11](../../android/app/src/debug/AndroidManifest.xml#L11) | <code>android:usesCleartextTraffic="true"</code> | Yalnız debug derlemede http serbest (emülatörde http://10.0.2.2:8080 için) |

**Olası nedenler**
- --dart-define=API_BASE_URL verilmeden derlendi: uygulama canlı API'ye gider (yerel sunucu denerken veri canlıya yazılabilir)
- Release derlemede http:// adres verildi: Android cleartext yasağı nedeniyle bağlanılamaz
- Android emülatöründe localhost verildi: emülatör için http://10.0.2.2:8080 gerekir (debug derleme)
- Adresin sonunda "/" ya da yol var: istekler "//" ile birleşir (AuthApi adresi kırpmaz)
- Adres değişti ama uygulama yeniden DERLENMEDİ: değer çalışma zamanında okunmaz

**Adım adım kontrol**
- Yeniden derleyip adresi açıkça verin: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 (yalnız debug)
- Uygulamanın gittiği adresi ağ izleyicisiyle ya da sunucu günlüğüyle doğrulayın
- Widget sorunuysa widget'ın kayıtlı adresi uygulama her kapı listesi alışında yeniden yazılır (api.baseUrl): uygulamayı açıp listeyi yenileyin

**Komutlar**
```bash
curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/health
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

**İlgili testler:** [test/door_widget_service_test.dart](../../test/door_widget_service_test.dart)

**Bkz.:** [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi), [cekirdek-widget-bos-ya-da-giris-yapin](#cekirdek-widget-bos-ya-da-giris-yapin)

<a id="cekirdek-internet-yok-ekrani"></a>
### cekirdek-internet-yok-ekrani · Giriş ekranı yerine "İnternet yok" ekranı çıkıyor (internet var) ya da o ekran kalkmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/app.dart:534](../../lib/app.dart#L534) | <code>if (!_networkService.hasInternet) {</code> | Yalnız OTURUMSUZ kullanıcı için: internet yoksa NoInternetPage gösterilir (oturumluysa HomePage daha önce döner) |
| [lib/app.dart:537](../../lib/app.dart#L537) | <code>onRetry: _networkService.refresh,</code> | "Tekrar dene" düğmesi yoklamayı yeniden çalıştırır |
| [lib/services/network_service.dart:53](../../lib/services/network_service.dart#L53) | <code>Future&lt;bool&gt; _probeInternet() async {</code> | Önce API /health, yanıt gecikirse/başarısızsa yedek adres; biri başarılıysa internet VAR sayılır |
| [lib/services/network_service.dart:59](../../lib/services/network_service.dart#L59) | <code>Uri.parse('https://clients3.google.com/generate_204'),</code> | Yedek adres: /health erişilemezse bu denenir (bu alan adı engelli ağda yedek de başarısız olur) |
| [lib/services/network_service.dart:102](../../lib/services/network_service.dart#L102) | <code>return response.statusCode &gt;= 200 &amp;&amp; response.statusCode &lt; 400;</code> | 4xx/5xx yanıt "internet yok" sayılır: /health 404/500 dönerse yedek adrese bakılır |
| [lib/services/network_service.dart:101](../../lib/services/network_service.dart#L101) | <code>.timeout(const Duration(seconds: 5));</code> | Her yoklama 5 sn ile sınırlıdır; zaman aşımı = başarısız |

**Olası nedenler**
- API /health ucu yanıt vermiyor (sunucu kapalı/5xx) VE yedek adres (google generate_204) de engelli ya da erişilemiyor
- Ağ çok yavaş: iki adres de 5 sn içinde yanıtlamadı (en kötü ~6,5 sn sonra "internet yok")
- Yoklama yalnız açılışta ve "Tekrar dene" ile çalışır: sonradan düzelen ağ otomatik algılanmaz
- Test/geliştirme: NetworkService(enabled: false) ise yoklama yapılmaz ve internet VAR kabul edilir

**Adım adım kontrol**
- Aynı ağdan API /health yanıtını kontrol edin (aşağıdaki komut)
- Ekran "Tekrar dene" ile kalkıyorsa geçici ağ sorunudur; kalkmıyorsa API adresini doğrulayın (cekirdek-api-adresi-yanlis)
- Oturumlu kullanıcı bu ekranı görmez; görüyorsa oturum açılışta düşmüştür (cekirdek-oturum-kendiliginden-dusuyor)

**Komutlar**
```bash
curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/health
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/cold_start_test.dart test/screens/no_internet_layout_test.dart
```

**İlgili testler:** [test/cold_start_test.dart](../../test/cold_start_test.dart), [test/screens/no_internet_layout_test.dart](../../test/screens/no_internet_layout_test.dart)

**Bkz.:** [cekirdek-api-adresi-yanlis](#cekirdek-api-adresi-yanlis), [cekirdek-acilis-splash-takili](#cekirdek-acilis-splash-takili)

<a id="cekirdek-acilis-splash-takili"></a>
### cekirdek-acilis-splash-takili · Açılışta logo + dönen çark ekranı çok uzun sürüyor ya da hiç kalkmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/app.dart:513](../../lib/app.dart#L513) | <code>if (!authReady) {</code> | Oturum yüklemesi bitene kadar her durumda StartupSplash |
| [lib/app.dart:531](../../lib/app.dart#L531) | <code>if (!networkReady) {</code> | Oturumsuzsa ağ yoklaması bitene kadar da splash (oturumluysa beklenmez) |
| [lib/app.dart:130](../../lib/app.dart#L130) | <code>final authInit = _authService.initialize();</code> | Oturum başlatma açılışta bir kez, beklenmeden başlar; bitince deep link kuyruğu işlenir |
| [lib/services/auth_service.dart:122](../../lib/services/auth_service.dart#L122) | <code>Future&lt;String?&gt; _readStoredSessionRaw() async {</code> | Güvenli depo okuması ZAMAN AŞIMSIZDIR: platform kanalı yanıt vermezse initialize bitmez |
| [lib/services/auth_service.dart:163](../../lib/services/auth_service.dart#L163) | <code>await cacheFuture;</code> | Açılış, üç bağımsız okumanın EN YAVAŞINI bekler (oturum, eski kopya, yerel erişim önbelleği) |
| [lib/services/auth_service.dart:166](../../lib/services/auth_service.dart#L166) | <code>_isReady = true;</code> | Hata olsa bile (try/catch dışında) hazır işaretlenir; yani hata splash'ı kalıcı yapmaz, askıda kalan okuma yapar |

**Olası nedenler**
- flutter_secure_storage okuması askıda kalıyor (zaman aşımı yok): initialize hiç tamamlanmaz
- Oturumsuz kullanıcıda ağ yoklaması sürüyor: her iki adres yanıtsızsa ~6,5 sn
- Soğuk açılışta cihaz yavaş: üç okuma eşzamanlı ama en yavaşı kadar beklenir

**Adım adım kontrol**
- Splash kalıcıysa Android/iOS güvenli depo erişimini (Keystore/Keychain) ve uygulama verisini temizleyip deneyin
- Splash birkaç saniye sonra giriş ekranına geçiyorsa ağ yoklaması nedenidir (cekirdek-internet-yok-ekrani)
- Giriş yapılmış kullanıcıda splash sonrası boş ekran için cekirdek-giris-sonrasi-ekran-bos girişine bakın

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/cold_start_test.dart test/screens/startup_splash_layout_test.dart
```

**İlgili testler:** [test/cold_start_test.dart](../../test/cold_start_test.dart), [test/screens/startup_splash_layout_test.dart](../../test/screens/startup_splash_layout_test.dart)

**Bkz.:** [cekirdek-internet-yok-ekrani](#cekirdek-internet-yok-ekrani), [cekirdek-giris-sonrasi-ekran-bos](#cekirdek-giris-sonrasi-ekran-bos)

<a id="cekirdek-giris-sonrasi-ekran-bos"></a>
### cekirdek-giris-sonrasi-ekran-bos · Giriş yaptıktan sonra ekran beyaz/boş kalıyor ya da giriş ekranından ilerlemiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/app.dart:509](../../lib/app.dart#L509) | <code>animation: Listenable.merge([_authService, _networkService]),</code> | Ekran seçimi hem oturumu hem ağ durumunu dinler; oturum açılınca yeniden kurulup HomePage döner |
| [lib/app.dart:522](../../lib/app.dart#L522) | <code>child: HomePage(</code> | Oturumlu kullanıcı için ana sayfa ("Güncellenen koşullar" kapısı LegalConsentGate'in çocuğu: bekleyen yasal onay varsa üstüne tam ekran onay sayfası biner, hata/zaman aşımında kilitlemez); bu widget'ın kendi build hatası ekranı boş/gri bırakabilir (ekran alanı: lib/ui) |
| [lib/services/auth_service.dart:288](../../lib/services/auth_service.dart#L288) | <code>_session = await api.login(</code> | Oturum atanır, kalıcılaştırılır, SONRA dinleyiciler bilgilendirilir |
| [lib/services/auth_service.dart:4332](../../lib/services/auth_service.dart#L4332) | <code>void _notifySafely() {</code> | AuthService dispose edilmişse bildirim atlanır: ekran yenilenmez |
| [lib/services/auth_api.dart:3459](../../lib/services/auth_api.dart#L3459) | <code>final session = _parsePayload('Oturum bilgisi', () {</code> | Giriş yanıtı beklenen şekilde değilse (user/token eksik) ekran değil HATA MESAJI döner: "Oturum bilgisi verisi beklenen formatta degil." |
| [lib/app.dart:491](../../lib/app.dart#L491) | <code>builder: (context, child) {</code> | Tüm sayfaların zemini burada çizilir; Scaffold zemini şeffaf olduğu için bu katman yoksa sayfa boş görünür |
| [lib/styles/app_theme.dart:35](../../lib/styles/app_theme.dart#L35) | <code>scaffoldBackgroundColor: Colors.transparent,</code> | Aydınlık temada Scaffold şeffaf (karanlık temada da aynı satır var): zemin MaterialApp builder'ından gelir |

**Olası nedenler**
- HomePage build sırasında istisna fırlattı (release'te gri/boş alan): asıl hata ekran koduna aittir, konsolda "Exception"/"RenderFlex" arayın
- Giriş yanıtının şekli bozuk: ekran değişmez, giriş ekranında "verisi beklenen formatta degil" görünür
- Sayfa MaterialApp'ın dışında/üstünde kurulmuş: app.dart builder zemini olmadığı için şeffaf Scaffold boş görünür
- Oturum atanmadı: login ApiException ile döndü (mesaj giriş ekranında görünür)

**Adım adım kontrol**
- Debug derlemede konsolu açıp giriş anındaki ilk istisnayı bulun (flutter run çıktısı)
- Giriş ekranında kırmızı hata metni var mı? Varsa cekirdek-sunucuya-baglanilamadi ya da cekirdek-json-ayristirma-hatasi
- Splash'ta kalıyorsa cekirdek-acilis-splash-takili

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat analyze
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/design/app_shell_test.dart test/widget_test.dart
```

**İlgili testler:** [test/design/app_shell_test.dart](../../test/design/app_shell_test.dart), [test/widget_test.dart](../../test/widget_test.dart)

**Bkz.:** [cekirdek-acilis-splash-takili](#cekirdek-acilis-splash-takili), [cekirdek-json-ayristirma-hatasi](#cekirdek-json-ayristirma-hatasi)

<a id="cekirdek-oturum-kendiliginden-dusuyor"></a>
### cekirdek-oturum-kendiliginden-dusuyor · Oturum kendiliğinden düşüyor: uygulama bir anda giriş ekranına dönüyor ("Oturum süreniz doldu. Lütfen tekrar giriş yapın.")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3524](../../lib/services/auth_service.dart#L3524) | <code>void _handleSessionError(</code> | Her yetkili istek hatası buradan geçer: 401 (SessionExpiredException) oturumu kapatır, 403 ise önce /me ile doğrulanır |
| [lib/services/auth_service.dart:3551](../../lib/services/auth_service.dart#L3551) | <code>if (error is SessionExpiredException &#124;&#124;</code> | Oturumu kapatma kararı: durum koduna dayanır (metne değil); mesaj girişte bir kez gösterilmek üzere saklanır |
| [lib/services/auth_api.dart:3694](../../lib/services/auth_api.dart#L3694) | <code>if (status == 401 &amp;&amp; unauthorizedIsSession) {</code> | Yetkili uçlarda 401 -> SessionExpiredException ("Oturum süreniz doldu..."); giriş uçlarında bu dal atlanır |
| [lib/services/api_exception.dart:42](../../lib/services/api_exception.dart#L42) | <code>bool get invalidatesSession =&gt;</code> | Varsayılan: yalnız 401 ve ara katmandan gelmeyen yanıt oturumu geçersiz sayar |
| [lib/services/auth_service.dart:226](../../lib/services/auth_service.dart#L226) | <code>Future&lt;void&gt; _runSessionRefresh(UserSession active) async {</code> | GET /me doğrulaması: 401/403 oturumu kapatır; ağ/5xx/ara katman hatasında çevrimdışı oturum KORUNUR |
| [lib/services/auth_service.dart:71](../../lib/services/auth_service.dart#L71) | <code>static const Duration _sessionCheckMinInterval = Duration(seconds: 20);</code> | /me doğrulaması art arda en çok 20 sn'de bir (force olmadıkça) |
| [lib/ui/pages/home_page.dart:794](../../lib/ui/pages/home_page.dart#L794) | <code>unawaited(widget.authService.refreshSession());</code> | Uygulama ön plana dönünce /me doğrulaması tetiklenir (oturum bu anda düşebilir) |
| [lib/services/auth_service.dart:115](../../lib/services/auth_service.dart#L115) | <code>String? takeSessionNotice() {</code> | Düşme nedeni mesajı giriş ekranında BİR KEZ gösterilir ve temizlenir |

**Olası nedenler**
- Sunucu 401 döndü: token süresi doldu, iptal edildi (parola değişti: TOKEN_REVOKED) ya da kullanıcı silindi
- /me doğrulaması (açılış, ön plana dönüş) 401 ya da 403 aldı: hesap pasif/onaysız -> çıkış
- Yanıtta is_active=false: "Hesabınız pasif duruma alındı..." mesajıyla çıkış (cekirdek-hesap-pasif-oturum-kapandi)
- Başka cihazda/ekranda parola değişimi (cekirdek-sifre-degisince-oturum-kapandi)
- ÇIKIŞ OLMAYAN durumlar: ağ hatası, 5xx, proxy/HTML 401-403, eski token ile geç gelen istek yeni oturumu kapatmaz

**Adım adım kontrol**
- Girişte gösterilen mesaj nedeni söyler: "Oturum süreniz doldu", "Şifreniz değiştirildiği için ...", "Hesabınız pasif ..."
- Sunucu günlüğünde o kullanıcının /me ve diğer isteklerinin durum kodlarına bakın (401/403 mü)
- Sorun yalnız belirli bir ağdaysa 401/403 HTML ise oturum kapanmaz; kapanıyorsa yanıt JSON hata zarfıdır (sunucu kaynaklı)
- Token süresi/iptal kuralları sunucu tarafındadır: sunucu alanı klavuzundaki giriş/oturum girişlerine bakın

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /me"
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/auth_service_session_test.dart test/fix_fx1_session_test.dart
```

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/fix_fx1_session_test.dart](../../test/fix_fx1_session_test.dart), [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart)

**Bkz.:** [cekirdek-hesap-pasif-oturum-kapandi](#cekirdek-hesap-pasif-oturum-kapandi), [cekirdek-sifre-degisince-oturum-kapandi](#cekirdek-sifre-degisince-oturum-kapandi), [cekirdek-acilista-oturum-yok](#cekirdek-acilista-oturum-yok)

<a id="cekirdek-sifre-degisince-oturum-kapandi"></a>
### cekirdek-sifre-degisince-oturum-kapandi · "Şifreniz değiştirildiği için oturumunuz sonlandırıldı" mesajıyla çıkış yapılıyor ya da şifre değişince uygulama düşüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:3696](../../lib/services/auth_api.dart#L3696) | <code>if (code == 'TOKEN_REVOKED') {</code> | Parola değişince eski token'lar iptal edilir (sunucu 401 TOKEN_REVOKED): özel mesajlı SessionExpiredException |
| [lib/services/auth_service.dart:96](../../lib/services/auth_service.dart#L96) | <code>int _credentialSwapDepth = 0;</code> | Süren parola değişimi sayısı: bu aralıkta eşzamanlı isteklerin TOKEN_REVOKED 401'i yok sayılır |
| [lib/services/auth_service.dart:3348](../../lib/services/auth_service.dart#L3348) | <code>Future&lt;String?&gt; updateMyProfile({</code> | Profil/şifre güncelleme: sunucunun döndürdüğü YENİ token oturuma yazılır; kendi 401'i gerçek oturum sonudur |
| [lib/services/auth_api.dart:3407](../../lib/services/auth_api.dart#L3407) | <code>final newToken = payload['token'];</code> | Şifre değişiminde sunucu yeni token döndürürse o kullanılır, yoksa eski token korunur |
| [lib/services/auth_service.dart:3405](../../lib/services/auth_service.dart#L3405) | <code>if (tokenChanged &amp;&amp; knownDoors != null) {</code> | Token değişince ana ekran widget'ı da yeni token ile yeniden yazılır (aksi halde widget eski token ile 401 alır) |

**Olası nedenler**
- Başka cihazda parola değiştirildi: bu cihazdaki eski token iptal oldu (beklenen davranış)
- Sunucu parola değişiminde yeni token döndürmedi: istemci eski (iptal) token ile kalır ve sonraki istek 401 alır
- Widget eski token ile kaldı: widget "Giriş Yapın" gösterir (cekirdek-widget-bos-ya-da-giris-yapin)

**Adım adım kontrol**
- Mesaj "Şifreniz değiştirildiği için..." ise nedeni parola değişimidir; yeniden giriş yeterlidir
- Parolayı bu cihazda değiştirdiyseniz ve çıkış olduysa PATCH /me yanıtında "token" alanı var mı (sunucu alanı)
- Değişimi yapan istek sırasında eşzamanlı isteklerin oturumu kapatmadığı testle doğrulanır (auth_service_session_test)

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart)

**Bkz.:** [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-sifre-degistirme-hatalari](#cekirdek-sifre-degistirme-hatalari)

<a id="cekirdek-hesap-pasif-oturum-kapandi"></a>
### cekirdek-hesap-pasif-oturum-kapandi · Oturum kapanıp girişte "Hesap aktif degil.", "E-posta adresiniz dogrulanmadi.", "Abonelik talebiniz onay bekliyor." ya da "Hesabınız pasif duruma alındı. Lütfen yöneticinizle iletişime geçin." mesajı görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:234](../../lib/services/auth_service.dart#L234) | <code>_sessionNotice = 'Hesabınız pasif duruma alındı. Lütfen yöneticinizle iletişime geçin.';</code> | /me yanıtında is_active=false ise bu mesajla çıkış yapılır |
| [lib/services/auth_service.dart:3564](../../lib/services/auth_service.dart#L3564) | <code>} else if (error is ApiException &amp;&amp; error.isForbidden) {</code> | Bir istek 403 alırsa oturum hemen kapanmaz: önce /me ile hesabın gerçekten pasif olup olmadığı doğrulanır |
| [lib/services/api_exception.dart:46](../../lib/services/api_exception.dart#L46) | <code>bool get isForbidden =&gt; statusCode == 403 &amp;&amp; !fromIntermediary;</code> | Proxy/WAF kaynaklı 403 bu sınıfa girmez (hesap pasif sinyali sayılmaz) |
| [lib/services/auth_api.dart:3420](../../lib/services/auth_api.dart#L3420) | <code>Future&lt;UserSession&gt; fetchMe({</code> | GET /me: 401 -> SessionExpiredException; 403 -> ApiException(403); is_active alanı oturuma işlenir |

**Olası nedenler**
- Sunucu auth_middleware 403 döner: hesap pasif ("Hesap aktif degil."), e-posta doğrulanmamış, abonelik talebi onay bekliyor ya da reddedilmiş. İstemci 403 durumunda /me ile doğrular; /me de 403 verince sunucunun mesajı olduğu gibi girişte gösterilir
- "Hesabınız pasif duruma alındı..." mesajı yalnız /me 200 dönüp is_active=false gelirse çıkar (mevcut sunucuda authRequired pasif hesabı 403 ile kestiği için bu yol nadirdir)
- ÇIKIŞ DEĞİL: 403 HTML ise (proxy/WAF) bu akış tetiklenmez

**Adım adım kontrol**
- Girişte görünen mesaja bakın: "Hesap aktif degil." pasif, "E-posta adresiniz dogrulanmadi." doğrulama, "Abonelik talebiniz ..." onay durumudur (sunucu auth_middleware)
- Kullanıcının is_active / email_verified / approval_status değerini sunucu tarafında doğrulayın (kullanıcı yönetimi ekranı ya da veritabanı; sunucu alanı klavuzu)
- Yönetici kullanıcıyı yeniden etkinleştirdiyse kullanıcı yeniden giriş yapmalıdır

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/fix_fx1_session_test.dart](../../test/fix_fx1_session_test.dart)

**Bkz.:** [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor)

<a id="cekirdek-acilista-oturum-yok"></a>
### cekirdek-acilista-oturum-yok · Uygulama her açılışta giriş istiyor (oturum hatırlanmıyor) ya da kayıtlı oturum silinmiş görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:154-156](../../lib/services/auth_service.dart#L154-L156) | <code>final data = jsonDecode(raw) as Map&lt;String, dynamic&gt;;</code> | Kayıtlı oturum JSON'u çözülemezse ya da UserSession.fromJson fırlatırsa kayıt SESSİZCE SİLİNİR ve giriş ekranı gelir |
| [lib/models/user_session.dart:80](../../lib/models/user_session.dart#L80) | <code>factory UserSession.fromJson(Map&lt;String, dynamic&gt; json) {</code> | id/full_name/email/role/token zorunlu cast'ler: biri eksik/tipi farklıysa fırlatır (eski şemalı kayıtlar silinir) |
| [lib/services/auth_service.dart:3601](../../lib/services/auth_service.dart#L3601) | <code>Future&lt;void&gt; _persist() async {</code> | Oturumu güvenli depoya yazar; yazma hatası YUTULUR (catch (_) {}): giriş çalışır ama kalıcı olmaz |
| [lib/services/auth_service.dart:68](../../lib/services/auth_service.dart#L68) | <code>static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();</code> | Oturum yalnızca güvenli depoda tutulur (SharedPreferences'ta tutulmaz) |
| [lib/services/auth_service.dart:177](../../lib/services/auth_service.dart#L177) | <code>Future&lt;String?&gt; _takeLegacySession() async {</code> | Eski sürümlerin SharedPreferences kopyası bir kez güvenli depoya taşınır ve silinir |
| [lib/services/auth_service.dart:793](../../lib/services/auth_service.dart#L793) | <code>Future&lt;void&gt; logout() async {</code> | Çıkış: oturum + yerel erişim önbelleği + widget verisi silinir; sonraki açılışta oturum olmaması normaldir |

**Olası nedenler**
- Güvenli depo yazması başarısız (platform Keystore/Keychain hatası): _persist hatayı yutar, oturum yalnızca bellekte kalır
- Uygulama verisi temizlendi / yeniden yüklendi: güvenli depo boş
- Kayıtlı JSON bozuk ya da eski şemalı: initialize kaydı siler
- Açılışta /me 401/403 aldı: oturum sunucuca geçersiz (cekirdek-oturum-kendiliginden-dusuyor)

**Adım adım kontrol**
- Girişten sonra uygulamayı kapatıp açın: hâlâ giriş istiyorsa güvenli depo yazma/okuma sorunudur
- Girişte bir mesaj gösterildi mi (takeSessionNotice)? Gösterildiyse oturum sunucu tarafından sonlandırılmıştır
- Testle doğrulama: auth_service_session_test "Oturum saklama: yalnızca güvenli depo"

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/cold_start_test.dart](../../test/cold_start_test.dart), [test/model_parsing_test.dart](../../test/model_parsing_test.dart)

**Bkz.:** [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-acilis-splash-takili](#cekirdek-acilis-splash-takili)

<a id="cekirdek-yanlis-rol-menu"></a>
### cekirdek-yanlis-rol-menu · Kullanıcı yanlış rolle görünüyor (yönetici menüsü yok / daire kullanıcısı gibi) ya da rol değişikliği uygulamaya yansımıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/user_role.dart:15](../../lib/models/user_role.dart#L15) | <code>orElse: () =&gt; UserRole.apartmentOwner,</code> | Bilinmeyen/yeni rol değeri SESSİZCE daire kullanıcısına düşer (hata vermez) |
| [lib/services/auth_service.dart:268](../../lib/services/auth_service.dart#L268) | <code>bool _sessionDiffers(UserSession a, UserSession b) {</code> | /me yanıtındaki rol/aktiflik/ad/e-posta farkı oturuma yazılır ve ekran yenilenir |
| [lib/services/auth_api.dart:4913](../../lib/services/auth_api.dart#L4913) | <code>UserSession _toUserSession({</code> | Sunucu yanıtından oturum üretir; rol alanı yoksa önceki (fallback) rol korunur |
| [lib/services/auth_service.dart:593](../../lib/services/auth_service.dart#L593) | <code>Future&lt;Map&lt;String, dynamic&gt;&gt; claimDevice({</code> | Cihaz sahiplenince rol sunucuda yükselir; istemci tahmin etmez, /me ile eşitler |
| [lib/app.dart:231](../../lib/app.dart#L231) | <code>final currentRole = _authService.session?.role;</code> | Kısayol/deep link ile sesli komut yalnız daire kullanıcısı ve bireysel kullanıcı için açılır |

**Olası nedenler**
- Sunucuda rol değişti ama /me henüz çalışmadı: açılışta, ön plana dönüşte (20 sn aralık) ve cihaz sahiplenmeden sonra eşitlenir
- Sunucu uygulamanın bilmediği bir rol değeri döndürdü: istemci apartmentOwner varsayar
- Kayıtlı (eski) oturumdaki rol: /me çevrimdışıyken güncellenmez

**Adım adım kontrol**
- Uygulamayı arka plana alıp geri getirin (/me tetiklenir) ya da çıkış-giriş yapın
- Sunucuda kullanıcının rol değerini doğrulayın; değer UserRole.apiValue listesinde olmalı (super_user, site_manager, apartment_owner, individual)
- Menü/ekran seçimi rolden gelir: ekran alanı klavuzuna bakın

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/model_parsing_test.dart](../../test/model_parsing_test.dart)

**Bkz.:** [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor)

<a id="cekirdek-sifre-degistirme-hatalari"></a>
### cekirdek-sifre-degistirme-hatalari · Profilde şifre değişmiyor: "Mevcut şifreniz hatalı", "mevcut şifrenizi girmelisiniz" ya da "Kendi şifrenizi Profilim ekranından değiştirin"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3362](../../lib/services/auth_service.dart#L3362) | <code>return 'Şifrenizi değiştirmek için mevcut şifrenizi girin.';</code> | İstemci tarafı ön kontrol: yeni şifre varsa mevcut şifre boş olamaz (istek gitmez) |
| [lib/services/auth_api.dart:3382](../../lib/services/auth_api.dart#L3382) | <code>if (password != null) 'current_password': currentPassword,</code> | Şifre değişiyorsa mevcut şifre sunucuya zorunlu olarak gönderilir |
| [lib/services/auth_api.dart:3976](../../lib/services/auth_api.dart#L3976) | <code>case 'CURRENT_PASSWORD_INVALID':</code> | Yanlış mevcut şifre: 400 ve oturumu KAPATMAZ |
| [lib/services/auth_api.dart:3978](../../lib/services/auth_api.dart#L3978) | <code>case 'CURRENT_PASSWORD_LOCKED':</code> | Mevcut şifre için çok fazla hatalı deneme: bekleme süresi mesaja eklenir |
| [lib/services/auth_api.dart:3982](../../lib/services/auth_api.dart#L3982) | <code>case 'USE_PROFILE_PASSWORD_CHANGE':</code> | Yönetici ekranından kendi parolasını değiştirmeye çalışınca çıkar (Profilim kullanılmalı) |

**Olası nedenler**
- Mevcut şifre yanlış girildi (CURRENT_PASSWORD_INVALID)
- Art arda yanlış denemeyle mevcut şifre kilitlendi (CURRENT_PASSWORD_LOCKED, Retry-After)
- Yönetici kendi hesabının parolasını kullanıcı yönetiminden değiştirmeyi denedi

**Adım adım kontrol**
- Mesaj metnine bakın: kod -> mesaj eşlemesi messageForErrorCode içindedir
- Kilit mesajındaki bekleme süresi dolana kadar bekleyin
- Değişiklikten sonra çıkış olursa cekirdek-sifre-degisince-oturum-kapandi

**İlgili testler:** [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart), [test/fix_fx1_session_test.dart](../../test/fix_fx1_session_test.dart), [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart)

**Bkz.:** [cekirdek-sifre-degisince-oturum-kapandi](#cekirdek-sifre-degisince-oturum-kapandi), [cekirdek-hiz-siniri-cok-fazla-deneme](#cekirdek-hiz-siniri-cok-fazla-deneme)

<a id="cekirdek-hiz-siniri-cok-fazla-deneme"></a>
### cekirdek-hiz-siniri-cok-fazla-deneme · "Çok fazla hatalı deneme yapıldı. N dakika sonra tekrar deneyin" ya da "Çok fazla istek gönderildi" (429) mesajı çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:3980](../../lib/services/auth_api.dart#L3980) | <code>case 'LOGIN_LOCKED':</code> | Giriş kilidi: "Çok fazla hatalı deneme yapıldı." + bekleme süresi |
| [lib/services/auth_api.dart:3814](../../lib/services/auth_api.dart#L3814) | <code>int? _retryAfterSeconds(http.Response response, Map&lt;String, dynamic&gt; payload) {</code> | Bekleme süresi: önce gövdedeki retry_after_seconds, yoksa Retry-After başlığı |
| [lib/services/auth_api.dart:3832](../../lib/services/auth_api.dart#L3832) | <code>static String formatWait(int seconds) {</code> | Saniyeyi "45 saniye / 5 dakika / 2 saat" yazar (yukarı yuvarlar) |
| [lib/services/auth_api.dart:3750](../../lib/services/auth_api.dart#L3750) | <code>if (status == 429 &amp;&amp; mappedMessage == null) {</code> | Kodu eşlenmemiş genel 429: mesaja "Lütfen X sonra tekrar deneyin." eklenir |
| [lib/services/auth_api.dart:4201](../../lib/services/auth_api.dart#L4201) | <code>if (status == 429) {</code> | Proxy (nginx) JSON olmayan 429 döndürürse de "Çok fazla istek gönderildi." sınıflanır |
| [lib/services/api_exception.dart:47](../../lib/services/api_exception.dart#L47) | <code>bool get isRateLimited =&gt; statusCode == 429;</code> | Arayüzün 429 durumunu ayırt etmesi için |

**Olası nedenler**
- Art arda hatalı giriş: sunucu hesabı/IP'yi geçici kilitler (LOGIN_LOCKED)
- Kapı açma/istek sıklığı sunucu hız sınırını aştı (genel 429)
- Nginx/proxy kendi hız sınırını uyguladı (JSON olmayan 429)

**Adım adım kontrol**
- Mesajdaki bekleme süresi kadar bekleyin; süre sunucudan gelir (istemci uydurmaz)
- Sunucu günlüğünde ilgili yolun 429 yanıtlarını arayın
- Kilit/sınır kuralları sunucu alanındadır: sunucu alanı klavuzundaki giriş kilidi ve hız sınırı girişleri

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /auth/login"
```

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart), [test/fix_fx1_session_test.dart](../../test/fix_fx1_session_test.dart)

**Bkz.:** [cekirdek-sifre-degistirme-hatalari](#cekirdek-sifre-degistirme-hatalari)

<a id="cekirdek-dogrulama-kodu-hatalari"></a>
### cekirdek-dogrulama-kodu-hatalari · E-posta doğrulama kodu kabul edilmiyor ("Kod 30 dakika geçerlidir; yeni kod için ...") ya da kod tekrar gönderilemiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:121](../../lib/services/auth_api.dart#L121) | <code>Future&lt;Map&lt;String, dynamic&gt;&gt; registerIndividual({</code> | Bireysel kayıt: oturum DÖNMEZ; kullanıcı kodu doğrulayınca oturum açılır |
| [lib/services/auth_api.dart:145](../../lib/services/auth_api.dart#L145) | <code>Future&lt;UserSession&gt; verifyIndividualCode({</code> | Kod doğrulama: başarılıysa sunucu oturum (token) döndürür |
| [lib/services/auth_service.dart:552](../../lib/services/auth_service.dart#L552) | <code>if (e.statusCode == 404) {</code> | 404 = aktif kod yok: mesaja "Kod 30 dakika geçerlidir; yeni kod için ..." yönlendirmesi eklenir |
| [lib/services/auth_service.dart:571](../../lib/services/auth_service.dart#L571) | <code>return 'Kod tekrar gönderilemedi.';</code> | Tekrar gönderme ApiException dışı hatada bu genel mesajı verir |
| [lib/services/auth_api.dart:159](../../lib/services/auth_api.dart#L159) | <code>Future&lt;Map&lt;String, dynamic&gt;&gt; resendIndividualCode({</code> | Kodu yeniden gönderme isteği (POST /auth/resend-code) |

**Olası nedenler**
- Kodun 30 dakikalık süresi doldu ya da hiç oluşturulmadı (sunucu 404 "aktif kod yok")
- Yanlış kod girildi (sunucu mesajı gösterilir)
- Kayıtta e-posta gönderilemediyse sunucu dürüst 503 (EMAIL_DELIVERY_FAILED) döner; "Kodu Tekrar Gönder" ise HER durumda 200 genel mesaj döner (gönderim arka planda, hata yalnız sunucu günlüğünde): mail gelmiyorsa istemci hata görmez (ayrıntı sunucu alanı ve docs/EPOSTA_DOGRULAMA.md)
- Çok fazla hatalı kod denemesi: sunucu 429 döner ("Çok fazla hatalı deneme yapıldı...", yeni kod istemek gerekir)
- Zaten kullanılmış ya da geçersiz biçimli kod (6 haneli sayı olmalı): sunucu 400 mesajı gösterilir

**Adım adım kontrol**
- Kullanıcıya "Kodu Tekrar Gönder" yaptırın ve gelen en son kodu girmesini söyleyin
- Sunucuda /auth/verify-code ve /auth/resend-code isteklerinin durum kodlarına bakın
- E-posta akışı ayrıntısı: docs/EPOSTA_DOGRULAMA.md

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a verify-code"
```

**İlgili testler:** [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart), [test/screens/verify_email_code_layout_test.dart](../../test/screens/verify_email_code_layout_test.dart)

**Bkz.:** [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi)

<a id="cekirdek-kapi-ac-zaman-asimi"></a>
### cekirdek-kapi-ac-zaman-asimi · Kapı açarken "Kapı komutuna zamanında yanıt alınamadı. Kapı açılmış olabilir..." ya da "Kapı açılamadı. Sunucuya bağlanılamadı."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:3185](../../lib/services/auth_api.dart#L3185) | <code>Future&lt;DoorRuntimeStatus&gt; openDoor({</code> | Bulut kapı açma: POST /app/doors/:id/open, kısa zaman aşımı ile; beklenen yanıt kodu 202 |
| [lib/services/auth_api.dart:63](../../lib/services/auth_api.dart#L63) | <code>_doorOpenTimeout = doorOpenTimeout ?? const Duration(seconds: 10),</code> | Kapı açma zaman aşımı 10 sn (kullanıcı kapıda bekler); okuma 20 sn, yazma 45 sn |
| [lib/services/auth_api.dart:3198](../../lib/services/auth_api.dart#L3198) | <code>'Kapı komutuna zamanında yanıt alınamadı. Kapı açılmış olabilir; durumu kontrol edip gere…</code> | Zaman aşımı mesajı: komut sunucuya GİTMİŞ olabilir, kapı açılmış olabilir; tekrar denemeden önce durum kontrol edilmeli |
| [lib/services/auth_api.dart:3586](../../lib/services/auth_api.dart#L3586) | <code>} on TimeoutException {</code> | Zaman aşımında ApiException; yazma isteği (POST) ASLA otomatik tekrar edilmez (çift açma riski) |
| [lib/services/auth_api.dart:3578](../../lib/services/auth_api.dart#L3578) | <code>final isIdempotentRead = method == 'GET';</code> | Yeniden deneme yalnız GET'te; kapı açma POST olduğu için tek denemedir |
| [lib/services/auth_api.dart:3201](../../lib/services/auth_api.dart#L3201) | <code>_ensureStatus(response, 202);</code> | Açma yanıtı YALNIZ 202 kabul edilir; başka 2xx (örn. 200) "İşlem başarısız (200)" olur (bu dosyada ikinci eşleşme: openDoor içinde) |
| [server/src/routes/app_doors_routes.js:240](../../server/src/routes/app_doors_routes.js#L240) | <code>return res.status(202).json({</code> | Sunucu tarafı: açma komutu kabul edilince 202 döner (sözleşme) |
| [lib/services/auth_service.dart:3130](../../lib/services/auth_service.dart#L3130) | <code>return (null, 'Kapı açılamadı. Sunucuya bağlanılamadı.');</code> | ApiException dışı her istisna bu genel mesaja düşer |

**Olası nedenler**
- Ağ yavaş/kopuk: 10 sn içinde yanıt gelmedi (komut sunucuya ulaşmış olabilir)
- Sunucu ya da MQTT köprüsü yanıtı geciktirdi (sunucu alanına bakın)
- Sunucu 202 yerine başka 2xx döndürüyor (sözleşme bozulmuş)
- ApiException dışı beklenmeyen istisna: genel "Sunucuya bağlanılamadı" mesajı gerçek nedeni gizler

**Adım adım kontrol**
- Kapı fiziksel olarak açıldı mı? Zaman aşımı mesajı "açılmış olabilir" der; çift tetiklemeden önce kontrol edin
- Sunucu günlüğünde /app/doors/<id>/open isteğinin durum koduna ve süresine bakın
- Kapı durumu ekranında cihaz çevrimiçi mi (cekirdek-kapi-durumu-cevrimdisi)

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /open"
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/auth_api_policy_test.dart test/auth_api_offload_test.dart
```

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart), [test/auth_api_offload_test.dart](../../test/auth_api_offload_test.dart)

**Bkz.:** [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari), [cekirdek-kapi-durumu-cevrimdisi](#cekirdek-kapi-durumu-cevrimdisi), [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi)

<a id="cekirdek-kapi-ac-sunucu-kodlari"></a>
### cekirdek-kapi-ac-sunucu-kodlari · Kapı açılmıyor ve ekranda "Cihaz şu an çevrimdışı", "Sunucunun cihaz bağlantısı şu an hazır değil" ya da "Bu sitede ... kapalı" yazıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:3939](../../lib/services/auth_api.dart#L3939) | <code>static String? messageForErrorCode(</code> | Sunucunun makine kodunu (code alanı) Türkçe mesaja çevirir; bilinmeyen kodda sunucunun error metni kullanılır |
| [lib/services/auth_api.dart:4040](../../lib/services/auth_api.dart#L4040) | <code>case 'DEVICE_OFFLINE':</code> | Cihaz sunucuya bağlı değil (MQTT çevrimdışı): cihazın internetini kontrol edin |
| [lib/services/auth_api.dart:4038](../../lib/services/auth_api.dart#L4038) | <code>case 'MQTT_BRIDGE_NOT_CONNECTED':</code> | Sunucunun MQTT köprüsü hazır değil: sorun cihazda değil sunucu/MQTT tarafında |
| [lib/services/auth_api.dart:4008](../../lib/services/auth_api.dart#L4008) | <code>case 'REMOTE_OPEN_DISABLED':</code> | Site politikası uzaktan açmayı kapatmış (site özellik/güvenlik ayarı) |
| [lib/services/auth_api.dart:4036](../../lib/services/auth_api.dart#L4036) | <code>case 'DOOR_ACCESS_DENIED':</code> | Kullanıcının bu kapı için yetkisi yok (daire/blok/özel erişim kapsamı) |
| [lib/services/auth_api.dart:3724](../../lib/services/auth_api.dart#L3724) | <code>final rawCode = payload['code'];</code> | Hata gövdesindeki code alanı burada okunur; code yoksa error metni, o da yoksa "İşlem başarısız (durum)" |

**Olası nedenler**
- DEVICE_OFFLINE: cihazın Wi-Fi/internet bağlantısı yok ya da MQTT'ye bağlanamıyor
- MQTT_BRIDGE_NOT_CONNECTED: sunucudaki MQTT köprüsü kopuk (sunucu alanı)
- REMOTE_OPEN_DISABLED / QR_DISABLED / GUEST_DISABLED / LOCAL_DISABLED: site özelliği kapalı
- DOOR_ACCESS_DENIED: kullanıcının kapıya erişimi yok ya da kısıtlandı

**Adım adım kontrol**
- Ekrandaki mesajı messageForErrorCode ile eşleyip hangi kodun döndüğünü bulun
- Cihaz durumu: yönetici ekranında cihaz çevrimiçi mi; sunucuda MQTT köprü durumu (sunucu alanı)
- Site özellikleri/güvenlik politikası ekranından ilgili özellik açık mı
- Kapı için yetkinin sunucuda var olduğunu kapı izinleri ekranından doğrulayın

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart), [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart)

**Bkz.:** [cekirdek-kapi-ac-zaman-asimi](#cekirdek-kapi-ac-zaman-asimi), [cekirdek-kapi-ac-istemci-reddi](#cekirdek-kapi-ac-istemci-reddi), [cekirdek-kapi-durumu-cevrimdisi](#cekirdek-kapi-durumu-cevrimdisi)

<a id="cekirdek-kapi-ac-istemci-reddi"></a>
### cekirdek-kapi-ac-istemci-reddi · Kapı açma düğmesine basınca istek hiç gitmeden "Bu kapı için uygulamadan açma kapalı." ya da "Bu kapıda uzaktan açma kapalı..." çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3051](../../lib/services/auth_service.dart#L3051) | <code>final allowRemote = door == null &#124;&#124; door.canOpenRemote &#124;&#124; isSuper;</code> | İstemci politikası: kapı bayrakları biliniyorsa uzaktan açma izni bayraktan gelir (süper kullanıcı istisna) |
| [lib/services/auth_service.dart:3060](../../lib/services/auth_service.dart#L3060) | <code>: 'Bu kapı için uygulamadan açma kapalı.',</code> | Hem uzaktan hem yerel kapalıysa istek GÖNDERİLMEZ |
| [lib/services/auth_service.dart:3078](../../lib/services/auth_service.dart#L3078) | <code>: 'Bu kapıda uzaktan açma kapalı. Cihaza yerel ağdan ulaşılamadı; telefonu cihazla aynı W…</code> | Uzaktan kapalı, yerel açma denendi ama cihaza ulaşılamadı |
| [lib/models/door_record.dart:205](../../lib/models/door_record.dart#L205) | <code>featureRemoteOpenEnabled: json['feature_remote_open_enabled'] as bool? ?? true,</code> | Bayrak sunucudan gelmezse true varsayılır (kapalıysa sunucu false göndermeli) |
| [lib/models/door_record.dart:161](../../lib/models/door_record.dart#L161) | <code>bool get isQrOnly =&gt; !canOpenRemote &amp;&amp; (canOpenQr &#124;&#124; hasDisplay);</code> | Uzaktan açma kapalı ve QR/ekran varsa kapı "yalnız QR" kabul edilir |

**Olası nedenler**
- Site/kapı politikasında uzaktan açma kapalı (feature_remote_open_enabled=false) ve yerel açma da uygun değil
- Telefon cihazla aynı Wi-Fi'da değil / cihaz yerel ağda görünmüyor (cekirdek-yerel-kapi-bulunmuyor)
- Kapı listesi bayat: bayraklar eski; uygulamayı yenileyip kapı listesini tekrar alın

**Adım adım kontrol**
- Site güvenlik politikasında uzaktan açma açık mı
- Yerel açma için: telefon Wi-Fi'da mı, cihaz beacon'ı görünüyor mu (yerel kapı girişleri)
- İstek gitmeden dönen mesajsa sunucu günlüğünde /open isteği YOKTUR

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart)

**Bkz.:** [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari), [cekirdek-yerel-kapi-bulunmuyor](#cekirdek-yerel-kapi-bulunmuyor)

<a id="cekirdek-kapi-ac-konum-zorunlu"></a>
### cekirdek-kapi-ac-konum-zorunlu · Kapı açarken konum isteniyor ya da "Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin." hatası çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3084](../../lib/services/auth_service.dart#L3084) | <code>if (door != null &amp;&amp; door.requireGeofence) {</code> | Konum zorunlu kapıda önce konum alınır; alınamazsa istek HİÇ gönderilmez ve neden mesaj olur |
| [lib/services/auth_service.dart:3109](../../lib/services/auth_service.dart#L3109) | <code>if (location == null &amp;&amp; e.code == 'GEOFENCE_LOCATION_REQUIRED') {</code> | Kapı bayrağı bayatsa sunucu konum ister: konum alınıp BİR KEZ yeniden denenir (açma isteği için) |
| [lib/services/geofence_service.dart:94](../../lib/services/geofence_service.dart#L94) | <code>static Map&lt;String, dynamic&gt; locationRequestFields(Position position) {</code> | Sunucuya giden konum alanları: latitude, longitude, accuracy, timestamp (UTC), is_mocked |
| [lib/services/auth_api.dart:3987](../../lib/services/auth_api.dart#L3987) | <code>case 'GEOFENCE_LOCATION_REQUIRED':</code> | Sunucu konum istedi ve istemci göndermedi: "Bu kapı için konum doğrulaması zorunludur..." |
| [lib/models/door_record.dart:135](../../lib/models/door_record.dart#L135) | <code>bool get requiresLocationForQrScan =&gt; requireGeofence &#124;&#124; (hasDevice &amp;&amp; !hasDisplay);</code> | Karekodla açmada da konum gerekir: konum çemberi açıksa ya da ekransız (statik UID karekodlu) cihazlarda |

**Olası nedenler**
- Kapıda/sitede konum doğrulaması (require_geofence) açık: her açmada konum gerekir
- Telefonda konum servisi kapalı ya da izin verilmemiş (cekirdek-konum-izni-gps-hatasi)
- Konum alındı ama sunucu reddetti: mesafe dışı/sahte/eski/yanlış doğruluk (cekirdek-konum-mesafe-disi)
- Ekransız cihaz + karekod: site bayrağı kapalı olsa da sunucu konum ister

**Adım adım kontrol**
- Telefonun konumunu ve uygulamanın konum iznini açın; açık alanda tekrar deneyin
- Site güvenlik politikasında konum çemberi (enlem/boylam/yarıçap) tanımlı mı
- Hangi hata kodunun döndüğünü messageForErrorCode eşlemesiyle belirleyin

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart)

**Bkz.:** [cekirdek-konum-izni-gps-hatasi](#cekirdek-konum-izni-gps-hatasi), [cekirdek-konum-mesafe-disi](#cekirdek-konum-mesafe-disi)

<a id="cekirdek-konum-izni-gps-hatasi"></a>
### cekirdek-konum-izni-gps-hatasi · "Konum servisleri kapalı", "Konum izni verilmedi", "GPS doğruluğu yetersiz", "Sahte konum tespit edildi" ya da "GPS sinyali alınamadı (zaman aşımı)"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/geofence_service.dart:105](../../lib/services/geofence_service.dart#L105) | <code>Future&lt;String?&gt; _checkServiceAndPermission() async {</code> | Servis kapalı, izin reddedildi, izin kalıcı engelli durumlarının Türkçe mesajları burada |
| [lib/services/geofence_service.dart:61](../../lib/services/geofence_service.dart#L61) | <code>static LocationFixIssue? evaluateFix({</code> | Konum politikası: sahte konum, doğruluk > 50 m, yaş > 30 sn reddedilir |
| [lib/services/geofence_service.dart:41](../../lib/services/geofence_service.dart#L41) | <code>static const double maxAccuracyMeters = 50;</code> | İstemci doğruluk sınırı 50 m (sunucu sınırı 100 m: istemci daha sıkı) |
| [lib/services/geofence_service.dart:42](../../lib/services/geofence_service.dart#L42) | <code>static const int maxFixAgeSeconds = 30;</code> | Konum 30 sn'den eskiyse "güncel değil" |
| [lib/services/geofence_service.dart:47](../../lib/services/geofence_service.dart#L47) | <code>static const Duration _fixTimeLimit = Duration(seconds: 10);</code> | Konum alma 10 sn ile sınırlı; aşılırsa zaman aşımı mesajı |
| [lib/services/geofence_service.dart:166](../../lib/services/geofence_service.dart#L166) | <code>for (var attempt = 0; attempt &lt; 2; attempt++) {</code> | En fazla iki örnek denenir; sahte konumda hemen bırakılır |
| [lib/services/geofence_service.dart:124](../../lib/services/geofence_service.dart#L124) | <code>String _describeLocationError(Object error) {</code> | Beklenmeyen konum istisnasını kullanıcı metnine çevirir (ham hata gösterilmez) |
| [android/app/src/main/AndroidManifest.xml:11](../../android/app/src/main/AndroidManifest.xml#L11) | <code>&lt;uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/&gt;</code> | Android konum izni bildirimi (yoksa izin penceresi hiç çıkmaz) |

**Olası nedenler**
- Telefon GPS/konum servisi kapalı
- Konum izni "reddedildi" ya da "kalıcı engellendi": ayarlardan açılmalı
- Kapalı alanda GPS doğruluğu 50 m'den kötü
- Geliştirici seçeneklerinde sahte konum uygulaması açık: istemci hemen reddeder
- Konum örneği 30 sn'den eski (GPS yeni sinyal alamıyor)

**Adım adım kontrol**
- Mesaja göre: konumu aç / izin ver / açık alana çık / sahte konum uygulamasını kapat
- Uygulama ayarları > izinler > konum
- Testle davranış doğrulama: geofence_and_site_policy_test (evaluateFix sınırları)

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/geofence_and_site_policy_test.dart
```

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart)

**Bkz.:** [cekirdek-kapi-ac-konum-zorunlu](#cekirdek-kapi-ac-konum-zorunlu), [cekirdek-konum-mesafe-disi](#cekirdek-konum-mesafe-disi)

<a id="cekirdek-konum-mesafe-disi"></a>
### cekirdek-konum-mesafe-disi · "N m uzaktasınız, izin verilen mesafe M m. Lütfen kapıya yaklaşın." / "Kapı konumunda değilsiniz" / "konum çemberi tanımlı değil"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:3997](../../lib/services/auth_api.dart#L3997) | <code>case 'GEOFENCE_OUT_OF_RANGE':</code> | Sunucu mesafe dışı dedi: mesaj distance_meters ve allowed_radius_meters alanlarından kurulur |
| [lib/services/auth_api.dart:4004](../../lib/services/auth_api.dart#L4004) | <code>case 'GEOFENCE_SITE_MISCONFIGURED':</code> | Sitenin konum çemberi sunucuda hatalı tanımlı: site yöneticisi düzeltmeli |
| [lib/services/geofence_service.dart:201](../../lib/services/geofence_service.dart#L201) | <code>Future&lt;GeofenceCheckResult&gt; verifyWithinGeofence({</code> | İstemci tarafı mesafe kontrolü: hedef koordinat geçersizse fail-closed (izin verilmez) |
| [lib/services/geofence_service.dart:223](../../lib/services/geofence_service.dart#L223) | <code>'Bu kapı için konum çemberi tanımlı değil. Lütfen site yöneticinize başvurun.',</code> | Kapıda enlem/boylam tanımsız ya da geçersiz aralıkta |
| [lib/services/geofence_service.dart:38](../../lib/services/geofence_service.dart#L38) | <code>static const int defaultRadiusMeters = 100;</code> | Yarıçap 0/negatifse 100 m varsayılır (sunucu sözleşmesiyle aynı sabit) |
| [lib/models/door_record.dart:212](../../lib/models/door_record.dart#L212) | <code>geofenceRadiusMeters: (json['geofence_radius_meters'] as num?)?.toInt() ?? 100,</code> | Sunucudan yarıçap gelmezse 100 m varsayılır |
| [lib/ui/views/individual_home_view.dart:305](../../lib/ui/views/individual_home_view.dart#L305) | <code>final result = await GeofenceService.instance.verifyWithinGeofence(</code> | Çağrı noktası (bireysel ana ekran): kapı açmadan önce istemci mesafe kontrolü |
| [lib/ui/widgets/resident_door_actions.dart:60](../../lib/ui/widgets/resident_door_actions.dart#L60) | <code>final result = await GeofenceService.instance.verifyWithinGeofence(</code> | Çağrı noktası (daire kullanıcısı: kart ve çekmece aynı yardımcıyı kullanır) |

**Olası nedenler**
- Kullanıcı kapı konum çemberinin dışında (mesaj ölçülen mesafeyi söyler)
- Çember merkezi/yarıçapı yanlış girilmiş (site güvenlik politikası)
- Kapıda enlem/boylam yok: istemci fail-closed, mesafe doğrulanamaz
- GPS sapması: doğruluk 50 m sınırı içinde ama çember dar (örn. 20 m)

**Adım adım kontrol**
- Mesajdaki mesafe/izin verilen değerleri karşılaştırın; yakınsa yarıçapı büyütmeyi site yöneticisine önerin
- Çember koordinatlarının doğru kapıyı gösterdiğini haritada doğrulayın
- Site güvenlik politikası ekranında enlem/boylam/yarıçap alanları dolu mu

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart)

**Bkz.:** [cekirdek-kapi-ac-konum-zorunlu](#cekirdek-kapi-ac-konum-zorunlu), [cekirdek-konum-izni-gps-hatasi](#cekirdek-konum-izni-gps-hatasi)

<a id="cekirdek-karekod-ile-kapi-acilmiyor"></a>
### cekirdek-karekod-ile-kapi-acilmiyor · Karekod okutulunca kapı açılmıyor: "Karekod geçersiz", "süresi doldu", "daha önce kullanıldı" ya da "Karekod okutularak kapı açılamadı"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3149](../../lib/services/auth_service.dart#L3149) | <code>Future&lt;(Map&lt;String, dynamic&gt;?, String?)&gt; openDoorWithScannedQr({</code> | Karekodla açma: konum zorunluysa önce konum alınır; sunucu konum isterse bir kez yeniden denenir |
| [lib/services/auth_api.dart:3209](../../lib/services/auth_api.dart#L3209) | <code>Future&lt;Map&lt;String, dynamic&gt;&gt; openDoorWithScannedQr({</code> | POST /app/doors/scan-qr-open; 10 sn zaman aşımı, yeniden deneme yok |
| [lib/services/auth_api.dart:4020](../../lib/services/auth_api.dart#L4020) | <code>case 'DYNAMIC_QR_REQUIRED':</code> | Kapıda dinamik karekod geçerli: statik/eski karekod reddedilir |
| [lib/services/auth_api.dart:4022](../../lib/services/auth_api.dart#L4022) | <code>case 'SCREEN_QR_ALREADY_USED':</code> | Ekran karekodu tek kullanımlık: aynı kod ikinci kez okutuldu |
| [lib/services/auth_api.dart:4026](../../lib/services/auth_api.dart#L4026) | <code>case 'EKRAN_QR_BEKLENIYOR':</code> | Kapı ekranı henüz karekod üretmedi/göndermedi: birkaç sn sonra tekrar denenmeli |
| [lib/services/auth_api.dart:4028](../../lib/services/auth_api.dart#L4028) | <code>case 'INVALID_QR_PAYLOAD':</code> | Okutulan metin karekod biçiminde değil |
| [lib/services/auth_service.dart:3204](../../lib/services/auth_service.dart#L3204) | <code>return (null, 'Karekod okutularak kapı açılamadı. Sunucuya bağlanılamadı.');</code> | ApiException dışı hata genel mesajı |
| [lib/models/door_record.dart:124](../../lib/models/door_record.dart#L124) | <code>bool get canOpenQr =&gt;</code> | QR ile giriş için: özellik + kapı QR aktif + fiziksel QR okuyucu (C3 olmayan, qr_reader_enabled) |

**Olası nedenler**
- Karekodun süresi doldu ya da zaten kullanıldı (ekran karekodu tek kullanımlık ve döner)
- Kapı ekranı karekod göndermiyor (EKRAN_QR_BEKLENIYOR): cihaz/ekran bağlantısı
- Site/kapı için QR kapalı (QR_DISABLED / QR_ENTRY_INACTIVE)
- Konum zorunlu ve alınamadı ya da çember dışı (cekirdek-kapi-ac-konum-zorunlu)
- Cihaz C3 ise fiziksel QR okuyucusu yoktur: canOpenQr false

**Adım adım kontrol**
- Ekrandaki mesajı kodla eşleyin (messageForErrorCode)
- Kapı ekranında güncel karekod görünüyor mu; birkaç sn bekleyip yeniden okutun
- Kapı için QR ile giriş ve QR okuyucu etkin mi (kapı/site ayarları)

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/fix_fx2_qr_modal_test.dart](../../test/fix_fx2_qr_modal_test.dart), [test/qr_modal_polling_test.dart](../../test/qr_modal_polling_test.dart)

**Bkz.:** [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari), [cekirdek-kapi-ac-konum-zorunlu](#cekirdek-kapi-ac-konum-zorunlu)

<a id="cekirdek-yerel-kapi-bulunmuyor"></a>
### cekirdek-yerel-kapi-bulunmuyor · Yerel (Wi-Fi) kapı açma çalışmıyor: kapı her seferinde buluttan açılıyor ya da cihaz yerel ağda görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3702](../../lib/services/auth_service.dart#L3702) | <code>Future&lt;(DoorRuntimeStatus?, String?)?&gt; _tryOpenDoorLocallyIfAlive(</code> | Yerel yol YALNIZ şu koşullarda denenir: sunucudan alınmış token + telefon Wi-Fi'da + cihazın taze beacon'ı var |
| [lib/services/auth_service.dart:3717](../../lib/services/auth_service.dart#L3717) | <code>if (liveBeacon == null &#124;&#124; !liveBeacon.isFresh) {</code> | Taze beacon yoksa yerel deneme yapılmaz, bulutla devam edilir |
| [lib/services/auth_service.dart:3726](../../lib/services/auth_service.dart#L3726) | <code>debugPrint('[AuthService] Yerel ağ yanıt vermedi -&gt; buluta devrediliyor...');</code> | Yerel açma başarısız: hata KULLANICIYA gösterilmez, sessizce buluta düşülür (yalnız bu günlük iz bırakır) |
| [lib/services/auth_service.dart:3054](../../lib/services/auth_service.dart#L3054) | <code>final allowLocal = door != null &amp;&amp; (door.canOpenLocalUdp &#124;&#124; isSuper) &amp;&amp; !moduleClosed;</code> | Kapı politikası yerel açmaya izin vermiyorsa yerel yol hiç denenmez |
| [lib/services/auth_service.dart:3136](../../lib/services/auth_service.dart#L3136) | <code>bool canTryLocalDoorOpen(DoorRecord door) {</code> | Arayüzün "yerelden açılabilir" kararı: politika + cihaz UID + kullanılabilir token önbelleği |
| [lib/services/local_door_service.dart:92](../../lib/services/local_door_service.dart#L92) | <code>bool get isFresh =&gt;</code> | Beacon 60 sn'den eskiyse "taze değil": cihaz yerelde yok sayılır |
| [lib/services/local_door_service.dart:565](../../lib/services/local_door_service.dart#L565) | <code>CachedDeviceLocation? getCachedDevice(String deviceUid) {</code> | Beacon önbelleğinden cihazı döndürür (yalnız taze kayıt) |
| [lib/services/local_door_service.dart:574](../../lib/services/local_door_service.dart#L574) | <code>Future&lt;bool&gt; hasLocalWifiConnection() async {</code> | Telefon yerel Wi-Fi'da mı: Android'de yerel köprü, değilse özel adresli ağ arayüzü araması |
| [lib/services/local_door_service.dart:691](../../lib/services/local_door_service.dart#L691) | <code>message: 'Yerel ağ yanıt vermedi, bulut üzerinden açılıyor.',</code> | Önbellekteki IP ile UDP açma yanıtsız kalırsa dönen sonuç (kullanıcıya gösterilmez) |

**Olası nedenler**
- Cihazın beacon'ı alınmıyor (cekirdek-yerel-beacon-alinmiyor): telefon farklı alt ağda, AP izolasyonu, çok-yayın engeli
- Yerel kontrol anahtarı (token) önbellekte yok (cekirdek-yerel-token-yok)
- Kapı politikasında yerel açma kapalı (LOCAL_DISABLED / feature_local_udp_enabled=false)
- Telefon mobil veride, Wi-Fi'da değil
- UDP paketi gitti ama imza/challenge/yanıt doğrulanamadı (cekirdek-yerel-udp-acma-basarisiz)

**Adım adım kontrol**
- Debug konsolunda "[YerelKapi] Beacon alındı" satırı akıyor mu: akıyorsa cihaz görünüyordur
- "[AuthService] Cihaz yerel ağda canlı" sonrası "Yerel ağ yanıt vermedi" geliyorsa sorun imza/yanıt tarafındadır
- Telefon ve cihaz AYNI alt ağda mı (router misafir ağı/AP izolasyonu kapalı olmalı)
- Beklenen davranış: yerel başarısızsa kapı buluttan açılır; kapı hiç açılmıyorsa bulut girişlerine bakın

**Günlükte aranacak ifadeler**
- `[YerelKapi] Beacon alındı -> UID:`
- `[AuthService] Cihaz yerel ağda canlı`
- `[AuthService] Yerel ağ yanıt vermedi -> buluta devrediliyor...`
- `[YerelKapi] Yerel ağda canlı cihaz bulunamadı/yanıt vermedi -> Anında buluta devrediliyor.`

**İlgili testler:** [test/local_door_service_security_test.dart](../../test/local_door_service_security_test.dart), [test/local_door_service_v2_test.dart](../../test/local_door_service_v2_test.dart), [test/local_door_access_test.dart](../../test/local_door_access_test.dart)

**Bkz.:** [cekirdek-yerel-beacon-alinmiyor](#cekirdek-yerel-beacon-alinmiyor), [cekirdek-yerel-token-yok](#cekirdek-yerel-token-yok), [cekirdek-yerel-udp-acma-basarisiz](#cekirdek-yerel-udp-acma-basarisiz), [cekirdek-kapi-ac-istemci-reddi](#cekirdek-kapi-ac-istemci-reddi)

<a id="cekirdek-yerel-udp-acma-basarisiz"></a>
### cekirdek-yerel-udp-acma-basarisiz · Cihaz yerelde görünüyor ama UDP ile kapı açılmıyor (yanıt doğrulanamıyor, 150 ms içinde cevap yok)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/local_door_service.dart:815](../../lib/services/local_door_service.dart#L815) | <code>Future&lt;bool&gt; _directUdpOpen(</code> | İmzalı açma paketi gönderimi, challenge ile TEK yeniden deneme, yanıt doğrulama |
| [lib/services/local_door_service.dart:822](../../lib/services/local_door_service.dart#L822) | <code>if (!access.hasToken &#124;&#124; !targetFilter(ip)) {</code> | Token yoksa ya da hedef özel ağ adresi değilse paket HİÇ gönderilmez |
| [lib/services/local_door_service.dart:863](../../lib/services/local_door_service.dart#L863) | <code>deadline = Timer(const Duration(milliseconds: 150), () {</code> | Her deneme için yalnız 150 ms yanıt penceresi; dolunca buluta düşülür |
| [lib/services/local_door_service.dart:441](../../lib/services/local_door_service.dart#L441) | <code>static String localOpenSignature({</code> | sig = HMAC-SHA256(token, "open\|UID\|ch"); token ağa çıkmaz |
| [lib/services/local_door_service.dart:347](../../lib/services/local_door_service.dart#L347) | <code>static bool isValidOpenReply({</code> | Yanıt kaynağı ip:port hedefle aynı, ok:true, UID eşleşmeli ve (varsa) nonce aynı olmalı |
| [lib/services/local_door_service.dart:401](../../lib/services/local_door_service.dart#L401) | <code>static String? parseChallengeReply({</code> | Cihaz "challenge" hatası ve güncel ch döndürürse istemci bir kez o ch ile yeniden dener |
| [lib/services/local_door_service.dart:132](../../lib/services/local_door_service.dart#L132) | <code>static const Duration challengeMaxAge = Duration(seconds: 12);</code> | ch 12 sn'den eskiyse boş gönderilir (cihaz güncel değeri hata ile verir) |
| [lib/services/local_door_service.dart:894](../../lib/services/local_door_service.dart#L894) | <code>debugPrint('[YerelKapi] UDP açma yanıtı doğrulandı ($ip)');</code> | Başarı izi: bu satır yoksa yanıt doğrulanamadı ya da gelmedi |
| [docs/YEREL_KONTROL_V2.md:15](../../docs/YEREL_KONTROL_V2.md#L15) | <code>- **Yanıtlar** (hepsi `device_uid` ve varsa `nonce` yankılar):</code> | Protokol: cihaz yanıt türleri (ok / duplicate / challenge / unauthorized / role_mesgul) |

**Olası nedenler**
- Token cihazdaki ile uyuşmuyor (token döndürüldü, cihaz eski token'da): cihaz "unauthorized" döner ve istemci tekrar denemez
- Röle meşgul (role_mesgul): kesin ret, yeniden denenmez
- Yanıt başka ip:port'tan geldi (çoklu arayüz/NAT): isValidOpenReply reddeder
- Wi-Fi gecikmesi 150 ms'den uzun: paket cihaza ulaşsa bile istemci beklemeyi bırakır ve buluta düşer
- Cihaz yerel kontrol öz-testi başarısız: yerel açma kapalı (cihaz olayı local_control_selftest_failed; docs/YEREL_KONTROL_V2.md)

**Adım adım kontrol**
- Konsolda "[YerelKapi] UDP açma yanıtı doğrulandı" var mı: yoksa yanıt/imza sorunu
- Tokenın sunucudan taze alındığından emin olmak için kapı durumunu yenileyin (önbellek güncellenir)
- Cihaz seri çıktısı/OTA durumu ile yerel kontrol sürümünün v2 olduğunu doğrulayın (firmware alanı)
- Bilinen-cevap vektörü: docs/YEREL_KONTROL_V2.md sonundaki örnekle localOpenSignature çıktısını karşılaştırın

**Günlükte aranacak ifadeler**
- `[YerelKapi] UDP açma yanıtı doğrulandı`
- `[YerelKapi] UDP Açma hatası:`
- `[YerelKapi] Canlı beacon önbelleği kullanılıyor ->`

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/local_door_service_v2_test.dart test/local_door_service_security_test.dart
```

**İlgili testler:** [test/local_door_service_v2_test.dart](../../test/local_door_service_v2_test.dart), [test/local_door_service_security_test.dart](../../test/local_door_service_security_test.dart)

**Bkz.:** [cekirdek-yerel-kapi-bulunmuyor](#cekirdek-yerel-kapi-bulunmuyor), [cekirdek-yerel-token-yok](#cekirdek-yerel-token-yok)

<a id="cekirdek-yerel-beacon-alinmiyor"></a>
### cekirdek-yerel-beacon-alinmiyor · Cihazın yerel ağ beacon'ı alınmıyor: "yerelde görünmüyor", beacon günlüğü hiç akmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/local_door_service.dart:459](../../lib/services/local_door_service.dart#L459) | <code>Future&lt;void&gt; startBeaconListener() async {</code> | UDP dinleyiciyi başlatır (idempotent): anyIPv4 + her Wi-Fi arayüzüne ayrı soket; 10 sn'de bir yeni arayüz taranır |
| [lib/services/local_door_service.dart:495](../../lib/services/local_door_service.dart#L495) | <code>reusePort: !(Platform.isWindows &#124;&#124; Platform.isAndroid),</code> | Soket 8765 portuna bağlanır; bağlanma hatası SESSİZCE yutulur (catch (_) {}) |
| [lib/services/local_door_service.dart:225](../../lib/services/local_door_service.dart#L225) | <code>CachedDeviceLocation? handleBeaconDatagram(Datagram dg, {DateTime? now}) {</code> | Paket doğrulaması: IPv4, kaynak özel ağda, <= 1024 bayt, JSON, geçerli device_uid; IP paket kaynağından alınır |
| [lib/services/local_door_service.dart:128](../../lib/services/local_door_service.dart#L128) | <code>static final RegExp _uidPattern = RegExp(r'^[0-9A-Z_-]{4,32}$');</code> | device_uid biçimi: 4-32 karakter büyük harf/rakam/_/- (aksi halde paket atılır) |
| [lib/services/local_door_service.dart:139](../../lib/services/local_door_service.dart#L139) | <code>static const _cellularKeywords = [</code> | Adı bu sözcüklerden birini İÇEREN arayüzler atlanır ("lo" dahil: "wlo1", "Local Area Connection" gibi adlar da elenir) |
| [lib/services/local_door_service.dart:584](../../lib/services/local_door_service.dart#L584) | <code>Future&lt;List&lt;InternetAddress&gt;&gt; getAllLocalWifiAddresses() async {</code> | Dinlenecek yerel arayüz adreslerini seçer: önce wlan/wifi/eth/en/wl/lan, sonra diğer hücresel olmayanlar; yalnız özel adresler |
| [lib/services/local_door_service.dart:45](../../lib/services/local_door_service.dart#L45) | <code>static Future&lt;void&gt; acquireMulticastLock() async {</code> | Android çok-yayın kilidi: yoksa bazı cihazlar yayın paketlerini almaz (izin: CHANGE_WIFI_MULTICAST_STATE) |
| [android/app/src/main/AndroidManifest.xml:5](../../android/app/src/main/AndroidManifest.xml#L5) | <code>&lt;uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/&gt;</code> | Çok-yayın kilidi için gerekli izin bildirimi |

**Olası nedenler**
- Telefon ve cihaz farklı alt ağda / router AP izolasyonu ya da yayın paketlerini engelliyor
- Port 8765 başka bir süreç tarafından tutuluyor: bind hatası yutulur, dinleyici kurulmaz
- Ağ arayüzü adı elenen sözcük içeriyor (_cellularKeywords): arayüz dinlenmez
- Uygulama arka planda: dinleyici bilerek durdurulur (cekirdek-yasam-dongusu-dinleyici)
- Beacon paketi geçersiz (UID biçimi, boyut > 1024, JSON değil): sessizce atılır
- Web derlemesinde yerel dinleme yoktur (kIsWeb)

**Adım adım kontrol**
- Konsolda "[YerelKapi] UDP Beacon dinleyicisi port 8765 üzerinde aktif." ve "[YerelKapi] Beacon alındı" satırlarını arayın
- Dinleyici aktif ama beacon yoksa ağ tarafı (aynı alt ağ, yayın engeli) şüphelidir
- Aynı ağdaki başka bir bilgisayardan UDP 8765 dinleyerek cihazın beacon yayınladığını doğrulayın (cihaz ~5 sn'de bir yayınlar: docs/YEREL_KONTROL_V2.md)

**Günlükte aranacak ifadeler**
- `[YerelKapi] UDP Beacon dinleyicisi port 8765 üzerinde aktif.`
- `[YerelKapi] Beacon alındı -> UID:`

**İlgili testler:** [test/local_door_service_security_test.dart](../../test/local_door_service_security_test.dart), [test/local_door_service_battery_test.dart](../../test/local_door_service_battery_test.dart)

**Bkz.:** [cekirdek-yerel-kapi-bulunmuyor](#cekirdek-yerel-kapi-bulunmuyor), [cekirdek-yasam-dongusu-dinleyici](#cekirdek-yasam-dongusu-dinleyici)

<a id="cekirdek-yerel-token-yok"></a>
### cekirdek-yerel-token-yok · "Yerel kontrol anahtarı yok, bulut üzerinden açılıyor" ya da yerel açma hiç denenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3660](../../lib/services/auth_service.dart#L3660) | <code>Future&lt;void&gt; _cacheLocalDoorAccess(DoorRuntimeStatus status) async {</code> | Token önbelleğini sunucu yanıtından doldurur; sunucu token vermezse eski token SİLİNİR (fail-closed) |
| [lib/services/auth_service.dart:2932](../../lib/services/auth_service.dart#L2932) | <code>await _cacheLocalDoorAccess(status);</code> | Önbellek kapı DURUMU yoklamasından dolar: durum hiç alınmadıysa token yoktur |
| [lib/services/auth_service.dart:3124](../../lib/services/auth_service.dart#L3124) | <code>unawaited(_cacheLocalDoorAccess(status));</code> | Bulut açma yanıtı da önbelleği tazeler |
| [lib/models/door_runtime_status.dart:110](../../lib/models/door_runtime_status.dart#L110) | <code>localControlToken: localControl['token'] as String?,</code> | Sunucu yanıtındaki device_status.local_control.token alanı |
| [lib/models/local_door_access.dart:18](../../lib/models/local_door_access.dart#L18) | <code>static const Duration cacheValidity = Duration(hours: 24);</code> | Önbellek kaydı 24 saatten eskiyse kullanılmaz (üyelik/izin kalkınca token döndürüldüğü için) |
| [lib/services/auth_service.dart:3614](../../lib/services/auth_service.dart#L3614) | <code>Future&lt;void&gt; _loadLocalDoorCache() async {</code> | Açılışta güvenli depodan yalnız kullanılabilir (geçerli) kayıtlar yüklenir; bozuk kayıt silinir |
| [lib/services/local_door_service.dart:654](../../lib/services/local_door_service.dart#L654) | <code>message: 'Yerel kontrol anahtarı yok, bulut üzerinden açılıyor.',</code> | Token yoksa yerel açma ağa hiç çıkmadan reddedilir |

**Olası nedenler**
- Kapı durumu bu cihazda hiç yoklanmadı/yenilenmedi: önbellek boş
- Sunucu bu kullanıcıya token vermiyor (kod yorumu: yetki kalktı ya da token döndürüldü); önbellekteki eski token da düşürülür
- Önbellek 24 saatten eski
- Çıkış yapıldı: yerel önbellek silinir

**Adım adım kontrol**
- Kapı detay/durum ekranını açıp durumun yüklenmesini bekleyin; sonra yerel açmayı yeniden deneyin
- Sunucu yanıtında device_status.local_control.available ve token alanı var mı (sunucu alanı)
- Site özelliklerinde yerel UDP açık mı

**İlgili testler:** [test/local_door_access_test.dart](../../test/local_door_access_test.dart), [test/local_door_service_security_test.dart](../../test/local_door_service_security_test.dart)

**Bkz.:** [cekirdek-yerel-kapi-bulunmuyor](#cekirdek-yerel-kapi-bulunmuyor), [cekirdek-yerel-udp-acma-basarisiz](#cekirdek-yerel-udp-acma-basarisiz)

<a id="cekirdek-kapi-durumu-cevrimdisi"></a>
### cekirdek-kapi-durumu-cevrimdisi · Kapı durumu "çevrimdışı" görünüyor, durum geç güncelleniyor ya da durum hatası ekranda kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:2918](../../lib/services/auth_service.dart#L2918) | <code>Future&lt;(DoorRuntimeStatus?, String?)&gt; getDoorRuntimeStatus({</code> | GET /app/doors/:id/status: başarıda yerel erişim önbelleği tazelenir, hatada bulut-erişilemez bayrağı güncellenir |
| [lib/services/auth_service.dart:2915](../../lib/services/auth_service.dart#L2915) | <code>static bool _isCloudUnreachableError(ApiException e) =&gt;</code> | "Bulut erişilemiyor" = durum kodu yok (ağ/zaman aşımı), 5xx ya da ara katman yanıtı; 403/404 gibi iş hataları sayılmaz |
| [lib/models/door_runtime_status.dart:84](../../lib/models/door_runtime_status.dart#L84) | <code>bool get commandEnabled =&gt;</code> | Komut gönderilebilir mi: (MQTT köprüsü VE cihaz bağlı) ya da (yerel kontrol token + IP var) |
| [lib/models/door_runtime_status.dart:124](../../lib/models/door_runtime_status.dart#L124) | <code>DoorRuntimeStatus copyWithOffline() {</code> | Durum alınamadı ve yerelde de erişilemiyorsa son durum "çevrimdışı"ya çevrilir |
| [lib/ui/pages/home_page.dart:3420](../../lib/ui/pages/home_page.dart#L3420) | <code>_doorRuntimeStatus = _doorRuntimeStatus!.copyWithOffline();</code> | Çağrı noktası (ekran): arka plan yoklaması hata verip yerel ulaşılamazsa çevrimdışı gösterilir |
| [lib/ui/pages/home_page.dart:452](../../lib/ui/pages/home_page.dart#L452) | <code>late final AdaptivePoller _statusPoller = AdaptivePoller(</code> | Durum yoklaması 3 sn aralıklı kurulur (görünür ve ön plandayken) |
| [lib/services/adaptive_poller.dart:52](../../lib/services/adaptive_poller.dart#L52) | <code>Duration get currentDelay {</code> | Ardışık hatada aralık üstel artar (en çok 30 sn): hata sürerken durum geç güncellenir; başarıda 3 sn'ye döner |
| [lib/services/adaptive_poller.dart:114](../../lib/services/adaptive_poller.dart#L114) | <code>if (active != null &amp;&amp; !active()) {</code> | Ekran görünür/ön planda değilse tur atlanır: ağ isteği yapılmaz |

**Olası nedenler**
- Cihaz gerçekten MQTT'ye bağlı değil (cihaz Wi-Fi/MQTT sorunu): durum yanıtında mqtt_connected=false
- Sunucu MQTT köprüsü kopuk: mqtt_bridge_connected=false
- Bulut erişilemiyor (ağ/5xx/proxy) ve yerelde de erişilemiyor: istemci çevrimdışı gösterir
- Art arda hata sonrası yoklama aralığı uzadı (en çok 30 sn)
- Başka menü/sayfa açık ya da uygulama arka planda: yoklama durdurulur

**Adım adım kontrol**
- Sunucu yanıtındaki device_status alanını kontrol edin (mqtt_connected, mqtt_bridge_connected, last_seen_at)
- Cihaz tarafı için cihaz/firmware alanı girişlerine bakın (MQTT bağlantısı)
- Hata sürüyorsa "Sunucuya bağlanılamadı" girişine gidin

**İlgili testler:** [test/adaptive_poller_test.dart](../../test/adaptive_poller_test.dart), [test/home_polling_test.dart](../../test/home_polling_test.dart), [test/door_field_equality_test.dart](../../test/door_field_equality_test.dart)

**Bkz.:** [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari), [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi), [cekirdek-yerel-kapi-bulunmuyor](#cekirdek-yerel-kapi-bulunmuyor)

<a id="cekirdek-yasam-dongusu-dinleyici"></a>
### cekirdek-yasam-dongusu-dinleyici · Uygulama arka plana alınıp dönünce cihaz yerelde bir süre görünmüyor ya da arka planda pil/ağ kullanımı soruluyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/app.dart:395](../../lib/app.dart#L395) | <code>void didChangeAppLifecycleState(AppLifecycleState state) {</code> | Ön plan: yerel dinleyici yeniden başlar; arka plan/inactive/hidden/detached: durdurulur |
| [lib/services/local_door_service.dart:548](../../lib/services/local_door_service.dart#L548) | <code>void pauseListening() {</code> | Soketleri ve 10 sn'lik yenileme zamanlayıcısını kapatır, çok-yayın kilidini bırakır |
| [lib/services/local_door_service.dart:555](../../lib/services/local_door_service.dart#L555) | <code>void resumeListening() {</code> | Dinleyiciyi yeniden başlatır; ilk beacon gelene kadar cihaz yerelde "görünmez" |
| [lib/ui/pages/home_page.dart:794](../../lib/ui/pages/home_page.dart#L794) | <code>unawaited(widget.authService.refreshSession());</code> | Ön plana dönüşte oturum doğrulaması (durum yoklaması da yeniden başlar) |

**Olası nedenler**
- Dinleyici bilerek arka planda durdurulur (pil tasarrufu); ön plana dönünce yeniden kurulur
- Dönüşten sonraki ilk beacon (~5 sn) gelene kadar cihaz taze sayılmaz: yerel açma o sürede buluta düşer
- "inactive" durumu da (örn. bildirim çubuğu çekme) dinleyiciyi durdurur

**Adım adım kontrol**
- Konsolda "[YerelKapi] Arka plana geçildi" ve "[YerelKapi] Ön plana dönüldü" satırları sırayla görünmeli
- Dönüşten birkaç sn sonra "Beacon alındı" gelmiyorsa cekirdek-yerel-beacon-alinmiyor

**Günlükte aranacak ifadeler**
- `[YerelKapi] Arka plana geçildi: UDP dinleyici durduruldu (pil tasarrufu).`
- `[YerelKapi] Ön plana dönüldü: UDP dinleyici yeniden başlatılıyor.`

**İlgili testler:** [test/local_door_service_battery_test.dart](../../test/local_door_service_battery_test.dart), [test/home_polling_test.dart](../../test/home_polling_test.dart)

**Bkz.:** [cekirdek-yerel-beacon-alinmiyor](#cekirdek-yerel-beacon-alinmiyor)

<a id="cekirdek-kullanici-degisince-eski-veri"></a>
### cekirdek-kullanici-degisince-eski-veri · Çıkış yapıp başka kullanıcıyla girince eski kullanıcının kapıları, sesli komut listesi ya da bekleyen kısayol/link görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/app.dart:152](../../lib/app.dart#L152) | <code>void _onAuthChanged() {</code> | Oturum kapanınca ya da kullanıcı değişince sesli servis, bekleyen eylemler ve yerel ağ önbelleği temizlenir |
| [lib/app.dart:160](../../lib/app.dart#L160) | <code>_voiceDoorService.clearSession();</code> | Önceki kullanıcının kapı listesi/eşleşmesi/konuşma durumu silinir |
| [lib/services/voice_door_service.dart:119](../../lib/services/voice_door_service.dart#L119) | <code>void clearSession() {</code> | Oturum sayacını artırır: eski oturumdan kalan asenkron işlerin sonucu yok sayılır |
| [lib/services/auth_service.dart:793](../../lib/services/auth_service.dart#L793) | <code>Future&lt;void&gt; logout() async {</code> | Bellek, güvenli depo ve widget verisi temizlenir; ekran hemen giriş ekranına döner |
| [lib/services/deep_link_service.dart:220](../../lib/services/deep_link_service.dart#L220) | <code>void clearPending() {</code> | Oturum hazır olmadan kuyruğa alınmış eylemler atılır |

**Olası nedenler**
- Kullanıcı değişimi _onAuthChanged'de yalnız _lastUserId farklıysa algılanır (aynı kimlikle yeniden giriş "değişim" sayılmaz)
- Temizlik yalnız oturum kapanışında/kullanıcı değişiminde çalışır; oturum açık kalırken veri yenilenmez

**Adım adım kontrol**
- Çıkış sonrası widget "Giriş Yapın" gösteriyor mu (clearDoorData)
- Sesli komutla açılan kapının doğru kullanıcıya ait olduğunu kapı listesinden doğrulayın

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/voice_door_service_test.dart](../../test/voice_door_service_test.dart), [test/deep_link_service_test.dart](../../test/deep_link_service_test.dart)

**Bkz.:** [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-widget-bos-ya-da-giris-yapin](#cekirdek-widget-bos-ya-da-giris-yapin)

<a id="cekirdek-proxy-html-modem-mesaji"></a>
### cekirdek-proxy-html-modem-mesaji · Ekranda "İnternet bağlantısı yok (Modem internete bağlı değil)" çıkıyor, oysa telefonda internet var; ya da "güvenlik duvarı/proxy" mesajı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:4175](../../lib/services/auth_api.dart#L4175) | <code>Map&lt;String, dynamic&gt; _decodePayload(http.Response response) {</code> | Gövde JSON değilse durum koduna göre sınıflar: 5xx sunucu mesajı, 413, 429, sonra HTML/modem sezgisi, sonra genel mesaj |
| [lib/services/auth_api.dart:4213](../../lib/services/auth_api.dart#L4213) | <code>bodyLower.contains('modem') &#124;&#124;</code> | Gövdede html/doctype/router/modem/gateway geçerse "Modem internete bağlı değil" denir (sezgisel: proxy/captive portal sayfası da buna düşer) |
| [lib/services/auth_api.dart:4216](../../lib/services/auth_api.dart#L4216) | <code>'İnternet bağlantısı yok (Modem internete bağlı değil).',</code> | Kullanıcıya görünen mesaj; fromIntermediary=true olduğu için oturum kapanmaz |
| [lib/services/auth_api.dart:3775](../../lib/services/auth_api.dart#L3775) | <code>ApiException? _intermediaryAuthError(http.Response response) {</code> | 401/403 gövdesi JSON hata zarfı değilse "güvenlik duvarı/proxy" mesajı: oturum sonu değildir |
| [lib/services/api_exception.dart:8](../../lib/services/api_exception.dart#L8) | <code>this.fromIntermediary = false,</code> | Ara katman işareti: invalidatesSession ve isForbidden bu bayrakla yok sayılır |

**Olası nedenler**
- Otel/şirket/okul Wi-Fi captive portal giriş sayfası API isteğine HTML döndürüyor
- Modem/router kendi hata sayfasını dönüyor ya da DNS başka bir sayfaya yönlendiriyor
- Nginx/WAF ile uygulama arasında JSON olmayan 401/403 üretildi (ör. engelleme sayfası)
- Sunucu gerçekten HTML dönüyor (yanlış API adresi bir web sitesine işaret ediyor, cekirdek-api-adresi-yanlis)
- Sezgi yanlış pozitif verebilir: gövde "gateway" kelimesi içeren herhangi bir JSON olmayan metin de bu mesajı üretir (5xx hariç)

**Adım adım kontrol**
- Telefonun tarayıcısında API adresinin /health ucunu açın: JSON {"ok":...} yerine giriş/HTML sayfası geliyorsa ağ katmanıdır
- Mobil veriye geçip tekrar deneyin: orada düzeliyorsa Wi-Fi/modem sorunudur
- Mesaj "Sunucu geçici olarak yanıt vermiyor (502/503/504)" ise bu giriş değil, sunucu/nginx tarafıdır (sunucu alanı)

**Komutlar**
```bash
curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/health
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/auth_api_policy_test.dart
```

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart), [test/fix_fx1_session_test.dart](../../test/fix_fx1_session_test.dart)

**Bkz.:** [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi), [cekirdek-oturum-kendiliginden-dusuyor](#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-api-adresi-yanlis](#cekirdek-api-adresi-yanlis)

<a id="cekirdek-json-ayristirma-hatasi"></a>
### cekirdek-json-ayristirma-hatasi · Ekranda "... verisi beklenen formatta degil." ya da "... verisi islenemedi." (ör. Oturum bilgisi, Profil bilgisi, Gecis kaydi) yazıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:4252](../../lib/services/auth_api.dart#L4252) | <code>T _parsePayload&lt;T&gt;(String label, T Function() parser) {</code> | Her model ayrıştırması buradan geçer: FormatException "verisi islenemedi", TypeError (null/yanlış tip cast) "verisi beklenen formatta degil" |
| [lib/services/auth_api.dart:4258](../../lib/services/auth_api.dart#L4258) | <code>throw ApiException('$label verisi beklenen formatta degil.');</code> | Sunucu alanı eksik/başka tipte döndürünce fromJson içindeki "as" dönüşümü TypeError fırlatır; etiket hangi isteğin olduğunu söyler |
| [lib/services/auth_api.dart:3624](../../lib/services/auth_api.dart#L3624) | <code>Future&lt;void&gt; _decodeLargeBodyInBackground(http.Response response) async {</code> | 64 KB üstü gövdeler arka planda çözülür; çözülemezse eşzamanlı yol aynı hatayı üretir |
| [lib/services/background_work.dart:16](../../lib/services/background_work.dart#L16) | <code>static const int jsonIsolateThresholdBytes = 64 * 1024;</code> | Arka plan çözümleme eşiği |
| [lib/models/door_record.dart:178](../../lib/models/door_record.dart#L178) | <code>factory DoorRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | En sık ayrıştırılan model: zorunlu alanlar "as int/String" ile okunur, eksikse TypeError |
| [lib/models/user_session.dart:80](../../lib/models/user_session.dart#L80) | <code>factory UserSession.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Giriş yanıtının "Oturum bilgisi" ayrıştırması buraya dayanır |

**Olası nedenler**
- Sunucu yanıt şeması değişti (alan adı/tipi) ama uygulama eski: zorunlu cast patlar
- Sunucu yeni sürümü eski uygulamayla uyumsuz (geriye uyumluluk bozulmuş)
- Tarih/sayı alanı beklenmedik biçimde (String yerine num ya da tersi)
- Yanıt gövdesi JSON ama beklenen nesne değil (ör. dizi/boş nesne): payload["alan"] null olur ve cast TypeError verir

**Adım adım kontrol**
- Mesajdaki etiketten (Oturum bilgisi, Profil bilgisi, Gecis kaydi...) hangi uç noktanın bozulduğunu bulun (auth_api.dart içinde _parsePayload çağrısı)
- Aynı isteğin ham yanıtını sunucuda deneyip alan adı/tiplerini ilgili modelin fromJson ile karşılaştırın
- Eski uygulama sürümü varsa sunucu değişikliğinin geriye uyumlu olduğunu doğrulayın
- Model testi: test/model_parsing_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/model_parsing_test.dart test/auth_api_offload_test.dart
```

**İlgili testler:** [test/model_parsing_test.dart](../../test/model_parsing_test.dart), [test/auth_api_offload_test.dart](../../test/auth_api_offload_test.dart)

**Bkz.:** [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi), [cekirdek-giris-sonrasi-ekran-bos](#cekirdek-giris-sonrasi-ekran-bos)

<a id="cekirdek-widget-bos-ya-da-giris-yapin"></a>
### cekirdek-widget-bos-ya-da-giris-yapin · Ana ekran widget'ı "Giriş Yapın" ya da "Kapı Tanımlı Değil" gösteriyor, kapı adı boş ya da widget güncellenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/door_widget_service.dart:307](../../lib/services/door_widget_service.dart#L307) | <code>Future&lt;DoorWidgetOpenOutcome&gt; _performOpen() async {</code> | Token, adres ya da kapı kimliği eksikse istek HİÇ gönderilmez: "Giriş Yapın" / "Kapı Tanımlı Değil" |
| [lib/services/door_widget_service.dart:566](../../lib/services/door_widget_service.dart#L566) | <code>Future&lt;void&gt; clearDoorData() async {</code> | Çıkışta/kapı kalmayınca widget belleği silinir: yer tutucu "Giriş Yapın" kalır |
| [lib/services/door_widget_service.dart:475](../../lib/services/door_widget_service.dart#L475) | <code>Future&lt;void&gt; syncDoorsList({</code> | Kapı listesini widget belleğine yazar; liste boşsa temizler. Yalnız uygulama çalıştığında/kapı listesi alındığında tetiklenir |
| [lib/services/door_widget_service.dart:340](../../lib/services/door_widget_service.dart#L340) | <code>// Token geçersiz/iptal edildi (ör. parola değişti, hesap pasif): widget'ta TUTMA.</code> | Açma isteği 401 alırsa widget token'ı silinir: sonraki durum "Giriş Yapın" |
| [lib/services/auth_service.dart:3230](../../lib/services/auth_service.dart#L3230) | <code>void _syncDoorWidget(UserSession active, List&lt;DoorRecord&gt; doors) {</code> | Süper kullanıcı ve web için widget senkronu YOK; diğerleri listMyDoors sonrası senkronlanır |
| [lib/services/door_widget_service.dart:72](../../lib/services/door_widget_service.dart#L72) | <code>String? normalizeWidgetApiBase(String? raw) {</code> | Kayıtlı API adresi geçersiz/http ise adres null olur ve widget "Giriş Yapın" der |

**Olası nedenler**
- Kullanıcı çıkış yaptı ya da hiç giriş yapmadı: widget belleği boş
- Widget açma isteği 401 aldı: token widget belleğinden silinir ve uygulama açılıp oturum yenilenene dek "Giriş Yapın" kalır
- Süper kullanıcı hesabı: widget kullanılmaz, kapı verisi yazılmaz
- Kullanıcının erişebildiği kapı yok: liste boş, widget temizlenir
- Widget belleğindeki api_base_url https değil (ya da derlemedeki adresle aynı http değil): normalizeWidgetApiBase reddeder
- Uygulama hiç açılmadı: widget verisi yalnız uygulama kapı listesini aldığında yazılır

**Adım adım kontrol**
- Uygulamayı açıp ana ekranda kapı listesinin yüklenmesini bekleyin; widget yeniden yazılır
- Widget bir kapı gösteriyor ama "Giriş Yapın" diyorsa token silinmiştir: uygulamayı açın (oturum yenilenir)
- Rol süper kullanıcı mı (widget kullanılamaz)
- Parola değiştirildiyse (cekirdek-sifre-degisince-oturum-kapandi) widget yeni token ile yeniden yazılır

**Günlükte aranacak ifadeler**
- `[DoorWidgetService] syncDoorsList error:`
- `[DoorWidget] callback error:`

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/door_widget_service_test.dart
```

**İlgili testler:** [test/door_widget_service_test.dart](../../test/door_widget_service_test.dart)

**Bkz.:** [cekirdek-widget-acma-sonuc-mesajlari](#cekirdek-widget-acma-sonuc-mesajlari), [cekirdek-api-adresi-yanlis](#cekirdek-api-adresi-yanlis), [cekirdek-kullanici-degisince-eski-veri](#cekirdek-kullanici-degisince-eski-veri)

<a id="cekirdek-widget-acma-sonuc-mesajlari"></a>
### cekirdek-widget-acma-sonuc-mesajlari · Ana ekran widget'ındaki "Aç" düğmesi "Bağlantı hatası", "Yetkiniz yok", "Kapı çevrimdışı", "Konum için uygulamayı açın" ya da "Çok sık deneme, bekleyin" diyor; ya da düğmeye basınca hiçbir şey olmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/door_widget_service.dart:150](../../lib/services/door_widget_service.dart#L150) | <code>DoorWidgetOpenOutcome mapDoorOpenResponse(int statusCode, String body) {</code> | Sunucu durum kodunu widget metnine çevirir: 200/202 Komut gönderildi, 401 Giriş Yapın, 403 (GEOFENCE* konum / REMOTE_OPEN_DISABLED / Yetkiniz yok), 404, 409 çevrimdışı, 429, 5xx |
| [lib/services/door_widget_service.dart:352](../../lib/services/door_widget_service.dart#L352) | <code>return const DoorWidgetOpenOutcome('Bağlantı hatası ❌');</code> | Her ağ istisnası/zaman aşımı (10 sn) bu metne düşer; is_online DEĞİŞTİRİLMEZ |
| [lib/services/door_widget_service.dart:103](../../lib/services/door_widget_service.dart#L103) | <code>bool tryBegin(DateTime now) {</code> | Önceki istek sürerken ya da 2 sn içinde ikinci dokunuş SESSİZCE yok sayılır (düğme "tepkisiz" görünür) |
| [lib/services/door_widget_service.dart:43](../../lib/services/door_widget_service.dart#L43) | <code>DoorWidgetAction? parseDoorWidgetUri(Uri? uri) {</code> | Düğme URI'si katı doğrulanır: yalnız sitekapi://next_door\|prev_door\|open_door_action\|door_offline_action; başka biçim sessizce yok sayılır |
| [lib/services/door_widget_service.dart:231](../../lib/services/door_widget_service.dart#L231) | <code>Future&lt;void&gt; doorWidgetBackgroundCallback(Uri? uri) async {</code> | Uygulama kapalıyken widget düğmesinin çalıştırdığı arka plan girişi; hata yalnız debugPrint ile yutulur |
| [lib/services/door_widget_service.dart:462](../../lib/services/door_widget_service.dart#L462) | <code>await HomeWidget.registerInteractivityCallback(</code> | Arka plan çağrısı uygulama açılışında kaydedilir; kayıt hatası "[DoorWidgetService] initialize error" ile yutulur |
| [android/app/src/main/kotlin/tr/com/gudeteknoloji/siteyonetim/DoorWidgetProvider.kt:14](../../android/app/src/main/kotlin/tr/com/gudeteknoloji/siteyonetim/DoorWidgetProvider.kt#L14) | <code>class DoorWidgetProvider : HomeWidgetProvider() {</code> | Android tarafı: widget düzeni ve düğmelerin PendingIntent'leri |

**Olası nedenler**
- "Bağlantı hatası": telefonda internet yok, DNS/TLS sorunu ya da 10 sn zaman aşımı (kapı yine de açılmış olabilir)
- "Kapı çevrimdışı": sunucu 409 döndü, cihaz MQTT'de yok (widget is_online=false yazar)
- "Konum için uygulamayı açın": kapıda konum doğrulaması var; widget konum göndermez, uygulamadan açılmalı
- "Yetkiniz yok": 403 ve kodu REMOTE_OPEN_DISABLED ya da GEOFENCE dışında (örn. DOOR_ACCESS_DENIED)
- "Çok sık deneme": sunucu 429 (hız sınırı)
- Düğme tepkisiz: önceki istek sürüyor ya da 2 sn içinde tekrar dokunuldu; ya da widget eski sürümden kalma/URI tanınmıyor

**Adım adım kontrol**
- Aynı kapıyı uygulamadan açın: açılıyorsa widget belleği/token sorunudur (cekirdek-widget-bos-ya-da-giris-yapin)
- Konum gerekliyse uygulamadan açın (cekirdek-kapi-ac-konum-zorunlu)
- Sunucuda /app/doors/<id>/open isteğinin durum koduna bakın (günlükte /open arayın)
- Widget'ın kapı değiştirme düğmeleri için cekirdek-widget-kapi-gecisi

**Günlükte aranacak ifadeler**
- `[DoorWidget] callback error:`
- `[DoorWidgetService] initialize error:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /open"
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/door_widget_service_test.dart
```

**İlgili testler:** [test/door_widget_service_test.dart](../../test/door_widget_service_test.dart), [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [cekirdek-widget-bos-ya-da-giris-yapin](#cekirdek-widget-bos-ya-da-giris-yapin), [cekirdek-widget-kapi-gecisi](#cekirdek-widget-kapi-gecisi), [cekirdek-kapi-ac-zaman-asimi](#cekirdek-kapi-ac-zaman-asimi)

<a id="cekirdek-widget-kapi-gecisi"></a>
### cekirdek-widget-kapi-gecisi · Widget'ta ◀ ▶ ile kapı değiştirilemiyor, yanlış kapı gösteriyor ya da kapı durumu (Çevrimiçi/Çevrimdışı) yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/door_widget_service.dart:356](../../lib/services/door_widget_service.dart#L356) | <code>Future&lt;void&gt; _cycleDoor({required int step}) async {</code> | door_count <= 1 ise hiçbir şey yapmaz; uçlarda (ilk/son) döngü YOKTUR; kapıyı önbellekten anında değiştirir, sonra /status ile 4 sn içinde doğrular |
| [lib/services/door_widget_service.dart:199](../../lib/services/door_widget_service.dart#L199) | <code>int resolveWidgetActiveIndex({</code> | Aktif kapı seçimi: açık seçim > widget'taki önceki kapı (kimlikle) > uygulamanın seçtiği > 0 |
| [lib/services/door_widget_service.dart:422](../../lib/services/door_widget_service.dart#L422) | <code>if (activeNow == doorId &amp;&amp; mqttConn != cachedOnline) {</code> | Canlı doğrulama yalnız hâlâ aynı kapı aktifse yazılır; ağ hatasında önbellekteki durum kalır (bayat olabilir) |
| [lib/services/door_widget_service.dart:226](../../lib/services/door_widget_service.dart#L226) | <code>online ? 'Çevrimiçi / Hazır' : 'Kapı Çevrimdışı';</code> | Dinlenme durumu metni: is_online değerinden gelir |
| [lib/services/door_widget_service.dart:510](../../lib/services/door_widget_service.dart#L510) | <code>final doorOnline = d.assignedDeviceIsOnline ?? false;</code> | Çevrimiçi bilgisi kapı listesinden gelir; bilinmiyorsa (null) widget çevrimdışı gösterir |
| [lib/services/auth_service.dart:3251](../../lib/services/auth_service.dart#L3251) | <code>void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {</code> | Uygulamada bir kapı seçilince widget aktif kapısı da ona çekilir (forceSelectDoor) |

**Olası nedenler**
- Kullanıcının tek kapısı var (door_count <= 1): ok düğmeleri bir şey yapmaz
- İlk kapıdayken ◀ ya da son kapıdayken ▶: sona gelindiğinde başa dönülmez
- Kapı listesi yalnız uygulama kapı listesini aldığında senkronlanır: yeni eklenen kapı widget'ta yoktur
- Çevrimiçi/çevrimdışı bilgisi son listeden/önbellekten geldi; /status 4 sn içinde yanıt vermediyse düzeltilmez

**Adım adım kontrol**
- Uygulamayı açıp kapı listesini yenileyin (widget belleği yeniden yazılır)
- Çok kapılı kullanıcıda uygulamadan kapı seçip widget'ın o kapıya geçtiğini doğrulayın
- Durum yanlışsa sunucudaki device_status.mqtt_connected değerine bakın (cekirdek-kapi-durumu-cevrimdisi)

**İlgili testler:** [test/door_widget_service_test.dart](../../test/door_widget_service_test.dart), [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [cekirdek-widget-acma-sonuc-mesajlari](#cekirdek-widget-acma-sonuc-mesajlari), [cekirdek-widget-bos-ya-da-giris-yapin](#cekirdek-widget-bos-ya-da-giris-yapin), [cekirdek-kapi-durumu-cevrimdisi](#cekirdek-kapi-durumu-cevrimdisi)

<a id="cekirdek-sesli-komut-anlasilmadi"></a>
### cekirdek-sesli-komut-anlasilmadi · Sesli komutla kapı açılmıyor: "Anlaşılamadı", "Hangi kapıyı açmamı istersiniz?", "Bu isimde bir kapı bulunamadı" ya da "Komut yakın zamanda işlendi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/voice_door_service.dart:613](../../lib/services/voice_door_service.dart#L613) | <code>static DoorMatchResult resolveDoorFromCommand(</code> | Eşleme: ters niyet > "aç" fiili şart > kapı puanlama; belirsizse ASLA açmaz |
| [lib/services/voice_door_service.dart:524](../../lib/services/voice_door_service.dart#L524) | <code>static const Set&lt;String&gt; _openVerbs = {</code> | Tanınan "aç" biçimleri (kelime sınırlı; "acil" gibi kelimeler sayılmaz). Konuşma tanıma "aç"ı farklı yazarsa niyet bulunamaz |
| [lib/services/voice_door_service.dart:633](../../lib/services/voice_door_service.dart#L633) | <code>token.startsWith('acma') &#124;&#124; // açma, açmayın, açmasın, açmak...</code> | "açma/kapat/kilitle/iptal" gibi sözcük varsa komut ters niyet sayılır ve reddedilir |
| [lib/services/voice_door_service.dart:490](../../lib/services/voice_door_service.dart#L490) | <code>static String _messageForUnmatched(DoorMatchResult resolution) {</code> | Kullanıcıya gösterilen/okunan ret mesajları (belirsiz, bulunamadı, anlaşılamadı) |
| [lib/services/voice_door_service.dart:355](../../lib/services/voice_door_service.dart#L355) | <code>now.difference(_lastCommandProcessedAt!).inSeconds &lt; 5) {</code> | Son komuttan sonra 5 sn içinde gelen yeni komut "Komut yakın zamanda işlendi" diye düşer |
| [lib/services/voice_door_service.dart:807](../../lib/services/voice_door_service.dart#L807) | <code>static int? _extractDoorNumber(List&lt;String&gt; tokens) {</code> | Kapı numarası: rakam her zaman sayı; yazıyla sayı yalnız bağlamdan belliyse ("1. kapı", "bir numaralı") |
| [lib/services/voice_door_service.dart:429](../../lib/services/voice_door_service.dart#L429) | <code>'${matched.doorName} kapısına henüz aktif bir cihaz atanmamış.';</code> | Eşleşen kapıda cihaz atanmamışsa açma isteği hiç gönderilmez |
| [lib/services/voice_door_service.dart:485](../../lib/services/voice_door_service.dart#L485) | <code>await Future.delayed(const Duration(seconds: 3));</code> | Komut işlendikten sonra 3 sn daha yeni komut kabul edilmez (_isProcessingCommand) |

**Olası nedenler**
- Komutta kapı adı/numarası yok ve kullanıcının birden çok kapısı var: "Hangi kapıyı açmamı istersiniz?" (tek kapılıda genel "kapıyı aç" yeter)
- İki kapının adı eşit puan aldı (aynı ad/aynı numara farklı sitelerde): belirsiz, açılmaz
- Tanıma yanlış duydu ("aç" yerine başka sözcük): niyet bulunamaz, "Anlaşılamadı"
- Komutta "açma/kapat/kilitle" gibi sözcük geçti: ters niyet
- Eşleşen kapıya cihaz atanmamış
- Önceki komuttan 5 sn dolmadan yeni komut verildi

**Adım adım kontrol**
- Net söyleyin: "1. kapıyı aç" ya da kapının tam adıyla "otopark kapısını aç"
- Kapı adlarında ayırt edici sözcük olduğundan emin olun (3 harften kısa ve "kapı/site" gibi sözcükler puan vermez)
- Kapıya cihaz atanmış mı (yönetici ekranı)
- Testle davranış doğrulama: voice_door_service_test (eşleme kuralları)

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/voice_door_service_test.dart
```

**İlgili testler:** [test/voice_door_service_test.dart](../../test/voice_door_service_test.dart), [test/voice_live_banner_test.dart](../../test/voice_live_banner_test.dart), [test/screens/voice_control_modal_layout_test.dart](../../test/screens/voice_control_modal_layout_test.dart)

**Bkz.:** [cekirdek-sesli-komut-mikrofon-hatasi](#cekirdek-sesli-komut-mikrofon-hatasi), [cekirdek-kapi-ac-zaman-asimi](#cekirdek-kapi-ac-zaman-asimi), [cekirdek-kullanici-degisince-eski-veri](#cekirdek-kullanici-degisince-eski-veri)

<a id="cekirdek-sesli-komut-mikrofon-hatasi"></a>
### cekirdek-sesli-komut-mikrofon-hatasi · Sesli komut başlamıyor: "Mikrofon veya ses tanıma izni alınamadı", "Ses motoru başlatılamadı", "Ses algılanamadı (...)" ya da cevap sesli okunmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/voice_door_service.dart:184](../../lib/services/voice_door_service.dart#L184) | <code>Future&lt;bool&gt; initializeSpeech() async {</code> | Web'de her zaman kapalı; başlatma hatasında/izin yokta durum error olur ve mesajlar buradan gelir |
| [lib/services/voice_door_service.dart:229](../../lib/services/voice_door_service.dart#L229) | <code>_feedbackText = 'Mikrofon veya ses tanıma izni alınamadı.';</code> | initialize false dönerse (izin reddi ya da cihazda ses tanıma servisi yok) |
| [lib/services/voice_door_service.dart:201](../../lib/services/voice_door_service.dart#L201) | <code>_feedbackText = 'Ses algılanamadı (${val.errorMsg})';</code> | Dinleme sırasında platform hatası (sessizlik, ağ, no_match vb.) ham hata koduyla gösterilir |
| [lib/services/voice_door_service.dart:285](../../lib/services/voice_door_service.dart#L285) | <code>listenFor: const Duration(seconds: 12),</code> | Dinleme en çok 12 sn, 3 sn sessizlikte biter; yalnız Türkçe (tr) yerel ayar aranır, yoksa tr_TR denenir |
| [lib/services/voice_door_service.dart:310](../../lib/services/voice_door_service.dart#L310) | <code>_feedbackText = 'Mikrofon başlatılırken hata oluştu.';</code> | listen çağrısı istisna fırlatırsa |
| [lib/services/voice_door_service.dart:174](../../lib/services/voice_door_service.dart#L174) | <code>Future&lt;void&gt; speak(String text) async {</code> | Sesli geri bildirim: web'de ya da ttsEnabled=false iken sessiz; hatalar yutulur |
| [lib/services/voice_door_service.dart:165](../../lib/services/voice_door_service.dart#L165) | <code>await _tts.setLanguage('tr-TR');</code> | TTS Türkçe ayarlanır; cihazda Türkçe ses paketi yoksa hata yutulur ve varsayılan/sessiz kalabilir |
| [android/app/src/main/AndroidManifest.xml:8](../../android/app/src/main/AndroidManifest.xml#L8) | <code>&lt;uses-permission android:name="android.permission.RECORD_AUDIO"/&gt;</code> | Android mikrofon izni bildirimi |
| [lib/app.dart:232](../../lib/app.dart#L232) | <code>if (currentRole != UserRole.apartmentOwner &amp;&amp;</code> | Sesli komut kısayolu yalnız daire kullanıcısı ve bireysel kullanıcı için çalışır; diğer rollerde sessizce yok sayılır |

**Olası nedenler**
- Mikrofon ya da konuşma tanıma izni verilmedi/kalıcı engellendi
- Cihazda Google/Apple ses tanıma servisi yok ya da devre dışı
- Web ya da masaüstü derlemesi: ses tanıma desteklenmez
- Gürültü/sessizlik: platform "no_match"/"speech_timeout" hatası verir (mesajda ham kod görünür)
- Telefonda Türkçe TTS sesi kurulu değil: sesli yanıt duyulmaz (metin ekranda görünür)
- Rol sesli komuta uygun değil (yönetici/şirket)

**Adım adım kontrol**
- Uygulama ayarlarından mikrofon iznini açın
- Telefonun kendi sesli asistan/dikte özelliğinin çalıştığını doğrulayın
- Ekranda yazı akıyor ama ses yoksa TTS ses paketini ve ses seviyesini kontrol edin
- Eller serbest otomatik dinleme tercihi için ayarı kontrol edin (hands_free_auto_listen)

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/voice_door_service_test.dart test/voice_live_banner_test.dart
```

**İlgili testler:** [test/voice_door_service_test.dart](../../test/voice_door_service_test.dart), [test/voice_live_banner_test.dart](../../test/voice_live_banner_test.dart)

**Bkz.:** [cekirdek-sesli-komut-anlasilmadi](#cekirdek-sesli-komut-anlasilmadi)

<a id="cekirdek-deep-link-kisayol-calismiyor"></a>
### cekirdek-deep-link-kisayol-calismiyor · sitekapi:// bağlantısı ya da kısayol kapıyı açmıyor / hiçbir şey yapmıyor, ya da "Kapı açılsın mı?" onayı çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/deep_link_service.dart:272](../../lib/services/deep_link_service.dart#L272) | <code>static DeepLinkAction? parseUri(Uri uri) {</code> | Geçersiz parametreli bağlantı null döner ve SESSİZCE yok sayılır (geçersiz id asla "ilk kapıyı aç"a dönüşmez) |
| [lib/services/deep_link_service.dart:144](../../lib/services/deep_link_service.dart#L144) | <code>static const Duration duplicateWindow = Duration(seconds: 2);</code> | Aynı bağlantı 2 sn içinde ikinci kez gelirse tek sayılır |
| [lib/services/deep_link_service.dart:195](../../lib/services/deep_link_service.dart#L195) | <code>void markReady({DateTime? now}) {</code> | Oturum hazır olana dek eylemler kuyruktadır; 60 sn'den eski olanlar atılır, kuyruk en çok 3 eylem tutar |
| [lib/services/deep_link_service.dart:150](../../lib/services/deep_link_service.dart#L150) | <code>static const int _maxUriLength = 512;</code> | 512 karakterden uzun bağlantılar reddedilir |
| [lib/services/deep_link_service.dart:72](../../lib/services/deep_link_service.dart#L72) | <code>static DeepLinkDoorResolution resolve(</code> | Kapı kullanıcının KENDİ kapıları içinde aranır; yoksa "Kapı bulunamadı."; "ilk kapı" yalnız tek kapıda, çoklu kapıda seçtirilir |
| [lib/app.dart:209](../../lib/app.dart#L209) | <code>Future&lt;void&gt; _handleDeepLinkAction(DeepLinkAction action) async {</code> | Oturum yoksa yalnız "Lütfen önce uygulamaya giriş yapın." okunur; eylem kaybolur |
| [lib/app.dart:355](../../lib/app.dart#L355) | <code>Future&lt;DoorRecord?&gt; _confirmDoorOpen(List&lt;DoorRecord&gt; candidates) async {</code> | Kapı açan her bağlantı onay ister; arayüz hazır değilse ya da başka onay penceresi açıksa GÜVENLİ taraf: açılmaz |
| [lib/app.dart:186](../../lib/app.dart#L186) | <code>Future&lt;void&gt; _handleQuickAction(String actionType) async {</code> | Kısayol eylemleri de aynı deep link/onay yolundan geçer |
| [android/app/src/main/AndroidManifest.xml:59](../../android/app/src/main/AndroidManifest.xml#L59) | <code>&lt;data android:scheme="sitekapi"/&gt;</code> | Android intent-filter: sitekapi şeması bu satırla uygulamaya bağlanır |

**Olası nedenler**
- Bağlantıda doorId/doorIndex/siteCode geçersiz (sayı değil, 0, çok büyük): bağlantı yok sayılır
- Kullanıcı giriş yapmamış: eylem uygulanmaz
- Kapı bu kullanıcının kapıları arasında değil ya da siteCode yanlış: "Kapı bulunamadı."
- Birden çok kapı eşleşti (farklı sitede aynı numara): kullanıcıya seçtirilir
- Oturum hazır olmadan 60 sn'den uzun beklendi: kuyruktaki eylem atıldı
- Onay penceresi açılamadı (uygulama arayüzü hazır değil): güvenlik gereği açılmaz
- Web derlemesinde deep link dinlenmez

**Adım adım kontrol**
- Bağlantıyı biçimiyle doğrulayın: sitekapi://open?doorId=12 | sitekapi://open?doorIndex=1&siteCode=5 | sitekapi://qr?doorId=12 | sitekapi://voice
- Uygulamada oturum açık mı; açık olup onay penceresi çıkmıyorsa uygulamayı ön plana alıp bağlantıyı yeniden açın
- Kapı numarasının/id'nin kullanıcının kapı listesinde olduğunu doğrulayın
- Android'de bağlantıyı adb ile deneyebilirsiniz: adb shell am start -a android.intent.action.VIEW -d "sitekapi://voice"

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/deep_link_service_test.dart test/deep_link_dialogs_test.dart
```

**İlgili testler:** [test/deep_link_service_test.dart](../../test/deep_link_service_test.dart), [test/deep_link_dialogs_test.dart](../../test/deep_link_dialogs_test.dart)

**Bkz.:** [cekirdek-kisayol-gorunmuyor](#cekirdek-kisayol-gorunmuyor), [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari), [cekirdek-kullanici-degisince-eski-veri](#cekirdek-kullanici-degisince-eski-veri)

<a id="cekirdek-kisayol-gorunmuyor"></a>
### cekirdek-kisayol-gorunmuyor · Uygulama simgesine uzun basınca "Sesli Kapı Aç" / kapı kısayolları görünmüyor ya da kısayol eskimiş kapıyı gösteriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/quick_actions_service.dart:34](../../lib/services/quick_actions_service.dart#L34) | <code>Future&lt;void&gt; updateDoorShortcuts(List&lt;DoorRecord&gt; doors) async {</code> | Sesli Kapı Aç + en çok 3 kapı (doorIndex sırasıyla) kısayolu üretir; hata sessizce yutulur |
| [lib/services/quick_actions_service.dart:50](../../lib/services/quick_actions_service.dart#L50) | <code>for (final door in sortedDoors.take(3)) {</code> | En fazla 3 kapı kısayolu: 4. ve sonraki kapılar için kısayol YOKTUR |
| [lib/services/quick_actions_service.dart:12](../../lib/services/quick_actions_service.dart#L12) | <code>void initialize(void Function(String actionType) onAction) {</code> | Web'de çalışmaz; eklenti yoksa (masaüstü) hata yutulur ve "[QuickActions] initialize yok sayıldı" yazılır |
| [lib/app.dart:135](../../lib/app.dart#L135) | <code>_quickActionsService.initialize(_handleQuickAction);</code> | Seçilen kısayol _handleQuickAction ile deep link yoluna aktarılır |
| [lib/ui/pages/home_page.dart:280](../../lib/ui/pages/home_page.dart#L280) | <code>final QuickActionsService? quickActionsService;</code> | Ana sayfa servisi alır; kodda updateDoorShortcuts çağrısı SADECE test dosyasında geçer (depoda başka çağrı bulunamadı) |

**Olası nedenler**
- Kısayol listesi uygulama kodunda hiçbir yerde güncellenmiyor görünüyor (updateDoorShortcuts çağıranı yok): kısayollar oluşmaz
- Cihaz/launcher uzun basma kısayollarını desteklemiyor ya da masaüstü/web derlemesi
- Kısayol seçildiğinde oturum yok: eylem sessizce giriş uyarısına döner (cekirdek-deep-link-kisayol-calismiyor)
- Kapı adı sonradan değişti ama kısayollar güncellenmedi

**Adım adım kontrol**
- Önce kodda updateDoorShortcuts'ın çağrılıp çağrılmadığını doğrulayın: node tools/klavuz/build.mjs --where "updateDoorShortcuts"
- Kısayol çalışıyorsa seçince onay penceresi ("Kapı açılsın mı?") gelir
- Launcher kısayol desteğini farklı bir cihazda deneyin

**Günlükte aranacak ifadeler**
- `[QuickActions] initialize yok sayıldı:`

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/quick_actions_service_test.dart
```

**İlgili testler:** [test/quick_actions_service_test.dart](../../test/quick_actions_service_test.dart)

**Bkz.:** [cekirdek-deep-link-kisayol-calismiyor](#cekirdek-deep-link-kisayol-calismiyor)

<a id="cekirdek-tema-tercihi-kaydedilmiyor"></a>
### cekirdek-tema-tercihi-kaydedilmiyor · Koyu/aydınlık tema tercihi uygulama kapanınca sıfırlanıyor, yanlış temayla açılıyor ya da tema düğmesi tersini seçiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/theme_service.dart:13](../../lib/services/theme_service.dart#L13) | <code>static const String storageKey = 'app_theme_mode';</code> | SharedPreferences anahtarı: light/dark; yok ya da başka değer = sistem teması |
| [lib/services/theme_service.dart:20](../../lib/services/theme_service.dart#L20) | <code>Future&lt;void&gt; load() async {</code> | Okuma hatası sessizce sistem temasına döner |
| [lib/services/theme_service.dart:35](../../lib/services/theme_service.dart#L35) | <code>Future&lt;void&gt; setMode(ThemeMode mode) async {</code> | Önce bellekte değişir sonra yazılır: yazma hatası yutulur, tercih yalnız o oturum için geçerli kalır |
| [lib/services/theme_service.dart:51](../../lib/services/theme_service.dart#L51) | <code>Future&lt;void&gt; toggle(Brightness effective) {</code> | Düğme GÖRÜNEN temanın tersini seçer; sistem modunda da bir kez basınca açık kalır (system seçeneği düğmeyle dönülmez) |
| [lib/main.dart:34](../../lib/main.dart#L34) | <code>await themeService.load();</code> | Tercih ilk kareden önce yüklenir (yanlış temayla açılıp değişmesin) |
| [lib/app.dart:482](../../lib/app.dart#L482) | <code>themeMode: _themeService.mode,</code> | MaterialApp tema modu servisten gelir; light()/dark() AppTheme'dedir |
| [lib/styles/app_theme.dart:263](../../lib/styles/app_theme.dart#L263) | <code>static ThemeData dark([AppPalette palette = AppPalette.dark]) {</code> | Koyu tema üretimi: renk/kontrast sorunları (okunmayan metin) burada ve AppPalette'te aranır |

**Olası nedenler**
- SharedPreferences yazma/okuma başarısız (depolama dolu/engelli): tercih kalıcı olmaz
- Hiç tercih yapılmadı: uygulama cihaz temasını izler (beklenen)
- Kayıtlı değer bozuk/bilinmiyor: sistem temasına düşer
- Test/geliştirmede ThemeService verilmeden MyApp kuruldu: tercih arka planda yüklenir, ilk karede sistem teması görünebilir

**Adım adım kontrol**
- Temayı seçip uygulamayı tamamen kapatıp açın
- Telefonun sistem temasını değiştirip uygulamanın (tercih yoksa) onu izlediğini doğrulayın
- Belirli bir ekranda renk sorunu varsa o ekran paletten mi (context.palette) yoksa sabit renkten mi çiziyor, ekran alanı klavuzuna bakın

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/theme_service_test.dart
```

**İlgili testler:** [test/theme_service_test.dart](../../test/theme_service_test.dart)

**Bkz.:** [cekirdek-giris-sonrasi-ekran-bos](#cekirdek-giris-sonrasi-ekran-bos)

<a id="cekirdek-mqtt-dogrudan-baglanti"></a>
### cekirdek-mqtt-dogrudan-baglanti · Uygulamadan doğrudan MQTT ile kapı komutu: "MQTT baglanamadi", "MQTT baglantisi kurulamadi", "Komut gonderilemedi" ya da web'de "Bu platform MQTT TCP baglantisini desteklemiyor."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/mqtt_door_service.dart:1](../../lib/services/mqtt_door_service.dart#L1) | <code>export 'mqtt_door_service_stub.dart'</code> | Platform seçimi: dart.library.io varsa gerçek istemci, yoksa (web) stub |
| [lib/services/mqtt_door_service_io.dart:115](../../lib/services/mqtt_door_service_io.dart#L115) | <code>_lastError = 'MQTT baglanamadi: $e';</code> | TLS (secure=true) bağlantı/kimlik doğrulama hatası mesajı |
| [lib/services/mqtt_door_service_io.dart:123](../../lib/services/mqtt_door_service_io.dart#L123) | <code>Future&lt;String?&gt; sendPulseCommand({required String requestedBy}) async {</code> | cmd konusuna {"action":"pulse"} yayınlar; bağlı değilse önce bağlanır |
| [lib/services/mqtt_door_service_io.dart:50](../../lib/services/mqtt_door_service_io.dart#L50) | <code>String get _topicPrefix =&gt; topicPrefix ?? 'site/$siteId/door/$doorId';</code> | Konu öneki site/<site>/door/<kapı>; cihazın dinlediği konuyla aynı olmalı (cihaz alanı) |
| [lib/services/mqtt_door_service_io.dart:43](../../lib/services/mqtt_door_service_io.dart#L43) | <code>bool get commandEnabled =&gt; _connected &amp;&amp; _deviceOnline == true &amp;&amp; !_sending;</code> | Komut yalnız bağlı + availability "online" iken serbest |
| [lib/services/mqtt_door_service_stub.dart:30](../../lib/services/mqtt_door_service_stub.dart#L30) | <code>String? get lastError =&gt; 'Bu platform MQTT TCP baglantisini desteklemiyor.';</code> | Web derlemesinde MQTT TCP yoktur: her zaman bu hata |

**Olası nedenler**
- Bu sınıf lib/ içinde başka hiçbir dosya tarafından kullanılmıyor görünüyor: uygulamanın normal kapı açma yolu sunucu API'sidir (cekirdek-kapi-ac-zaman-asimi), bu servis değil
- Broker adresi/portu/kullanıcı/parola yanlış ya da TLS sertifikası geçersiz
- Cihaz availability konusunda "online" yayınlamıyor: commandEnabled false kalır
- Web derlemesi: stub her zaman hata döner

**Adım adım kontrol**
- Önce bu servisin gerçekten çağrıldığını doğrulayın: node tools/klavuz/build.mjs --where "MqttDoorService("
- Kapı açılmıyorsa gerçek yol olan sunucu API girişlerine bakın
- Broker tarafı için sunucu alanı (mosquitto) girişlerine bakın

**Bkz.:** [cekirdek-kapi-ac-zaman-asimi](#cekirdek-kapi-ac-zaman-asimi), [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari)

<a id="cekirdek-ble-izin-ve-tarama"></a>
### cekirdek-ble-izin-ve-tarama · Bluetooth ile cihaz kurulumunda cihaz listede görünmüyor ya da "Bluetooth kapali", "Konum servislerini acip tekrar deneyin", "Bluetooth izni verilmedi", "yalnizca Android ve iPhone" uyarısı çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/ble_wifi_provision_service.dart:156](../../lib/services/ble_wifi_provision_service.dart#L156) | <code>Future&lt;void&gt; ensureReady() async {</code> | Platform + izin + Bluetooth durumu kontrolü; her durumun Türkçe (ASCII) mesajı burada üretilir |
| [lib/services/ble_wifi_provision_service.dart:235](../../lib/services/ble_wifi_provision_service.dart#L235) | <code>Future&lt;void&gt; _requestPermissions() async {</code> | Android: bluetoothScan/Connect, ikisi de yoksa konum ya da bluetooth izni; iOS: bluetooth izni. Reddedilirse BleProvisionException |
| [lib/services/ble_wifi_provision_service.dart:264](../../lib/services/ble_wifi_provision_service.dart#L264) | <code>Future&lt;List&lt;BleProvisionDevice&gt;&gt; scanDevices({</code> | Yalnız kurulum servisi UUID'sini yayınlayan ve adı "SmartKey" (SmartKeyPass) ya da "AHBU" (eski kartlar) ile başlayan cihazları listeler; 6 sn tarar, sinyal gücüne göre sıralar |
| [lib/services/ble_wifi_provision_service.dart:282](../../lib/services/ble_wifi_provision_service.dart#L282) | <code>if (!isBleProvisionDeviceName(name)) {</code> | Adı SmartKey ya da AHBU (eski kartlar) ile başlamayan cihaz sessizce atlanır |
| [lib/services/ble_wifi_provision_service.dart:8](../../lib/services/ble_wifi_provision_service.dart#L8) | <code>const String bleWifiServiceUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f001';</code> | Servis UUID'si cihaz yazılımındakiyle AYNI olmalı (aksi halde hiçbir cihaz bulunmaz) |
| [cihaz_kontrol/include/wifi_baglanti.h:28](../../cihaz_kontrol/include/wifi_baglanti.h#L28) | <code>inline constexpr char BLE_WIFI_SERVICE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f001";</code> | Cihaz tarafı UUID; ESP32-C3 sahada çalışıyor: bu değeri/ad önekini (SmartKeyPass+UID; eski kartlarda AHBU+UID) değiştirmeyin |
| [cihaz_kontrol/include/wifi_baglanti.h:520](../../cihaz_kontrol/include/wifi_baglanti.h#L520) | <code>BLEDevice::init(bleName.c_str());</code> | Cihazın yayınladığı BLE adı (SmartKeyPass + cihaz kimliği; eski firmware AHBU + cihaz kimliği); uygulama SmartKey ve AHBU önekleriyle filtreler |
| [android/app/src/main/AndroidManifest.xml:13](../../android/app/src/main/AndroidManifest.xml#L13) | <code>&lt;uses-permission android:name="android.permission.BLUETOOTH_SCAN"/&gt;</code> | Android 12+ tarama izni bildirimi |

**Olası nedenler**
- Telefonda Bluetooth kapalı ya da (eski Android) konum servisi kapalı
- Bluetooth/konum izni verilmedi ya da kalıcı reddedildi: ayarlardan açılmalı
- Cihaz kurulum (BLE) modunda değil ya da çok uzak: yayın görünmez; ad SmartKey ya da AHBU (eski kartlar) ile başlamıyorsa atlanır
- Masaüstü/web derlemesi: Bluetooth kurulumu yalnız Android ve iOS'ta desteklenir
- Telefon BLE desteklemiyor (BleStatus.unsupported)
- Tarama hatası: platform hatası ham metinle gösterilir

**Adım adım kontrol**
- Telefonda Bluetooth ve (gerekirse) konumu açın; uygulama izinlerini kontrol edin
- Cihazı yeniden başlatıp kurulum moduna alın; telefona yaklaşın ve listeyi yenileyin
- Cihazın BLE adı SmartKeyPass (eski kartlarda AHBU) ile başlıyor mu (başka bir BLE tarayıcı uygulamasıyla bakın)
- Cihaz yazılımı alanındaki BLE kurulum girişlerine bakın

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/ble_wifi_provision_service_test.dart
```

**İlgili testler:** [test/ble_wifi_provision_service_test.dart](../../test/ble_wifi_provision_service_test.dart), [test/screens/bluetooth_wifi_view_layout_test.dart](../../test/screens/bluetooth_wifi_view_layout_test.dart)

**Bkz.:** [cekirdek-ble-baglanti-ve-wifi-listesi](#cekirdek-ble-baglanti-ve-wifi-listesi), [cekirdek-ble-wifi-yazma-basarisiz](#cekirdek-ble-wifi-yazma-basarisiz)

<a id="cekirdek-ble-baglanti-ve-wifi-listesi"></a>
### cekirdek-ble-baglanti-ve-wifi-listesi · Bluetooth ile cihaza bağlanılamıyor ("Cihaza baglanilamadi veya baglanti koptu", "zaman asimina ugradi") ya da cihazın gördüğü Wi-Fi ağları listelenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/ble_wifi_provision_service.dart:311](../../lib/services/ble_wifi_provision_service.dart#L311) | <code>Future&lt;BleWifiState&gt; connect(BleProvisionDevice device) async {</code> | Bağlantı 12 sn, tamamlanma 15 sn ile sınırlı; kopma ya da hata BleProvisionException olur; bağlanınca durum karakteristiği okunur |
| [lib/services/ble_wifi_provision_service.dart:340](../../lib/services/ble_wifi_provision_service.dart#L340) | <code>'Cihaza baglanilamadi veya baglanti koptu.',</code> | Bağlantı kurulamadı/koptu mesajı |
| [lib/services/ble_wifi_provision_service.dart:409](../../lib/services/ble_wifi_provision_service.dart#L409) | <code>Future&lt;List&lt;BleWifiNetwork&gt;&gt; scanNetworks() async {</code> | Cihaza {"action":"scan"} yazar, 20 kez 350 ms aralıkla sonucu bekler; "scan_complete" gelmezse "Wi-Fi taramasi zaman asimina ugradi." |
| [lib/services/ble_wifi_provision_service.dart:387](../../lib/services/ble_wifi_provision_service.dart#L387) | <code>Future&lt;List&lt;BleWifiNetwork&gt;&gt; readNetworks() async {</code> | Boş SSID'li ağlar elenir; JSON bozuksa boş liste döner (hata verilmez) |
| [lib/services/ble_wifi_provision_service.dart:113](../../lib/services/ble_wifi_provision_service.dart#L113) | <code>Map&lt;String, dynamic&gt; _decodeJsonMap(String payload) {</code> | Cihazdan gelen bozuk/boş JSON SESSİZCE boş haritaya döner: durum "bağlı değil/idle" görünür |
| [lib/services/ble_wifi_provision_service.dart:521](../../lib/services/ble_wifi_provision_service.dart#L521) | <code>throw const BleProvisionException('Once Bluetooth cihazina baglanin.');</code> | Bağlantı yokken okuma/yazma denenirse |
| [lib/ui/pages/wifi_provision_page.dart:232](../../lib/ui/pages/wifi_provision_page.dart#L232) | <code>final List&lt;BleWifiNetwork&gt; networks = await _service.scanNetworks();</code> | Çağrı noktası (kurulum sayfası): Wi-Fi taraması |
| [cihaz_kontrol/include/wifi_baglanti.h:368](../../cihaz_kontrol/include/wifi_baglanti.h#L368) | <code>wifiNotifyBleResult("scan_complete", "WiFi listesi guncellendi.");</code> | Cihaz tarafı tarama bitiş bildirimi (ESP32-C3 sahada çalışıyor: bu davranışı bozmayın) |

**Olası nedenler**
- Cihaz uzakta ya da başka bir telefona bağlı olabilir: bağlantı 12-15 sn içinde kurulamazsa zaman aşımı
- Telefon BLE yığını takıldı: Bluetooth'u kapatıp açmak gerekebilir
- Cihazın Wi-Fi taraması 7 sn'den uzun sürdü ya da cihaz hiç ağ görmüyor: liste boş/zaman aşımı
- Cihaz yeniden başladı ve bağlantı koptu
- Cihaz durum/sonuç JSON'u bozuk geldi: boş durum görünür (hata mesajı yok)

**Adım adım kontrol**
- Cihazı kapatıp açın, kurulum sayfasında listeyi yenileyip tekrar bağlanın
- Telefonda Bluetooth'u kapatıp açın; diğer telefonların cihaza bağlı olmadığından emin olun
- Cihaz Wi-Fi taramasının çalıştığını cihaz seri çıktısıyla doğrulayın (cihaz yazılımı alanı)
- Ağ görünmüyorsa 2,4 GHz olduğundan emin olun (ESP32 5 GHz ağı görmez)

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/ble_wifi_provision_service_test.dart
```

**İlgili testler:** [test/ble_wifi_provision_service_test.dart](../../test/ble_wifi_provision_service_test.dart)

**Bkz.:** [cekirdek-ble-izin-ve-tarama](#cekirdek-ble-izin-ve-tarama), [cekirdek-ble-wifi-yazma-basarisiz](#cekirdek-ble-wifi-yazma-basarisiz)

<a id="cekirdek-ble-wifi-yazma-basarisiz"></a>
### cekirdek-ble-wifi-yazma-basarisiz · Bluetooth ile Wi-Fi bilgisi yazılırken "MQTT cihaz kimligi hazir degil", "SSID secimi zorunludur", "Wi-Fi baglantisi kurulamadi" ya da "Wi-Fi baglantisi zaman asimina ugradi" hatası

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/ble_wifi_provision_service.dart:432](../../lib/services/ble_wifi_provision_service.dart#L432) | <code>Future&lt;BleWifiResult&gt; provisionWifi({</code> | SSID + MQTT kimliğini JSON olarak cihaza yazar; sonucu en çok 28 sn (1 sn aralıkla) okur |
| [lib/services/ble_wifi_provision_service.dart:451](../../lib/services/ble_wifi_provision_service.dart#L451) | <code>'MQTT cihaz kimligi hazir degil. Once cihazi sirket hesabina kaydedin.',</code> | mqtt_host/kullanıcı/parola boşsa yazma HİÇ yapılmaz: cihaz önce sistemde kayıtlı olmalı |
| [lib/services/ble_wifi_provision_service.dart:476](../../lib/services/ble_wifi_provision_service.dart#L476) | <code>message: 'Wi-Fi bilgileri cihaza yazildi. Cihaz yeniden baslatiliyor.',</code> | Sonuç okunamaz hale gelirse (cihaz yeniden başladı, bağlantı koptu) BAŞARI sayılır |
| [lib/services/ble_wifi_provision_service.dart:101](../../lib/services/ble_wifi_provision_service.dart#L101) | <code>bool get isProvisionAccepted =&gt;</code> | connected / restarting / saved durumları kabul sayılır; error ve failed hata sayılır |
| [lib/ui/pages/wifi_provision_page.dart:324](../../lib/ui/pages/wifi_provision_page.dart#L324) | <code>await authService.getDeviceMqttCredentials(deviceUid: deviceUid);</code> | Çağrı noktası: MQTT kimliği sunucudan (yönetim yetkisiyle) alınır; yetki yok/sunucu hatası burada çıkar |
| [lib/services/auth_service.dart:2885](../../lib/services/auth_service.dart#L2885) | <code>Future&lt;(Map&lt;String, dynamic&gt;?, String?)&gt; getDeviceMqttCredentials({</code> | Yalnız yönetim rolleri için; daire kullanıcısı "site yonetim yetkisi gerekir" alır |
| [cihaz_kontrol/include/wifi_baglanti.h:492](../../cihaz_kontrol/include/wifi_baglanti.h#L492) | <code>wifiNotifyBleResult("error", "MQTT sunucu adresi izinli degil.");</code> | Cihaz izinli MQTT adresi listesi dışındaki sunucuyu reddeder (ESP32-C3 sahada çalışıyor: bu davranışı bozmayın) |
| [cihaz_kontrol/include/wifi_baglanti.h:405](../../cihaz_kontrol/include/wifi_baglanti.h#L405) | <code>wifiNotifyBleResult("restarting", "WiFi ve MQTT bilgileri kaydedildi. Cihaz temiz baglant…</code> | Cihaz kaydı tamamlayınca yeniden başlar; bağlantı bu yüzden kopar |

**Olası nedenler**
- Cihaz henüz şirket hesabına/sisteme kaydedilmedi: MQTT kimliği alınamaz
- Wi-Fi parolası yanlış ya da ağ 5 GHz: cihaz bağlanamaz, sonuç "failed/error"
- Cihaz yazdıktan sonra yeniden başlıyor ve bağlantı kopuyor (beklenen, başarı sayılır)
- Cihaz MQTT sunucu adresini izinli bulmadı (MQTT sunucu adresi izinli degil)
- 28 sn içinde ne kabul ne ret geldi: zaman aşımı
- Kullanıcı yönetim yetkisine sahip değil: MQTT kimliği alınamaz

**Adım adım kontrol**
- Cihazın sistemde kayıtlı olduğunu doğrulayın (cihaz listesi); kayıtlıysa sunucudan MQTT kimliği alınabilir
- Wi-Fi parolasını ve 2,4 GHz olduğunu kontrol edip tekrar deneyin
- Yazma sonrası cihaz birkaç sn içinde çevrimiçi görünüyor mu (cekirdek-kapi-durumu-cevrimdisi)
- Cihaz tarafı için cihaz yazılımı alanındaki Wi-Fi/MQTT girişlerine bakın

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/ble_wifi_provision_service_test.dart
```

**İlgili testler:** [test/ble_wifi_provision_service_test.dart](../../test/ble_wifi_provision_service_test.dart)

**Bkz.:** [cekirdek-ble-baglanti-ve-wifi-listesi](#cekirdek-ble-baglanti-ve-wifi-listesi), [cekirdek-kapi-durumu-cevrimdisi](#cekirdek-kapi-durumu-cevrimdisi)

<a id="cekirdek-pdf-turkce-karakter-font"></a>
### cekirdek-pdf-turkce-karakter-font · PDF raporunda Türkçe karakterler (ş, ğ, İ, ı) bozuk/kutu görünüyor ya da PDF çevrimdışıyken farklı yazı tipiyle çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/pdf_font_set.dart:27](../../lib/services/pdf_font_set.dart#L27) | <code>static Future&lt;PdfFontSet&gt; loadRoboto() async {</code> | Üç Roboto yazı tipini PdfGoogleFonts ile (ağ + önbellek) yükler; hata yakalanmaz, bayt yoksa Helvetica yedeği |
| [lib/services/pdf_font_set.dart:73](../../lib/services/pdf_font_set.dart#L73) | <code>static pw.Font _fontOf(Uint8List? bytes) {</code> | Bayt null ise pw.Font.helvetica(): Helvetica Türkçe karakterleri (ş, ğ, İ, ı) doğru göstermez |
| [lib/services/pdf_font_set.dart:57](../../lib/services/pdf_font_set.dart#L57) | <code>static Uint8List? _bytesOf(pw.Font font) {</code> | Font TtfFont değilse (indirme başarısız, Helvetica'ya düşmüş) null: yedek devreye girer |
| [lib/services/pdf_logs_service.dart:53](../../lib/services/pdf_logs_service.dart#L53) | <code>final fontSet = fonts ?? await PdfFontSet.loadRoboto();</code> | Günlük PDF'i yazı tiplerini her üretimde buradan yükler |

**Olası nedenler**
- İlk kullanımda cihaz çevrimdışı: Roboto indirilemedi, Helvetica yedeği kullanıldı (önbellekte varsa sorun olmaz)
- Google Fonts adresine erişim engelli ağ
- Helvetica yedeğinde Türkçe karakterler bozuk/eksik çıkabilir

**Adım adım kontrol**
- İnternete bağlıyken raporu yeniden üretin (font önbelleğe alınır), sonra çevrimdışı deneyin
- Sorun yalnız belirli bir ağdaysa fonts.gstatic.com erişimini kontrol edin
- Testler Helvetica ile (ağsız) çalışır; gerçek font davranışı test edilmez

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/pdf_background_test.dart
```

**İlgili testler:** [test/pdf_background_test.dart](../../test/pdf_background_test.dart)

**Bkz.:** [cekirdek-pdf-gecis-raporu-bos](#cekirdek-pdf-gecis-raporu-bos), [cekirdek-pdf-giris-bilgileri-raporu](#cekirdek-pdf-giris-bilgileri-raporu), [cekirdek-pdf-firmware-raporu](#cekirdek-pdf-firmware-raporu)

<a id="cekirdek-pdf-gecis-raporu-bos"></a>
### cekirdek-pdf-gecis-raporu-bos · Kapı geçiş günlüğü PDF raporu üretilmiyor, boş çıkıyor ya da "Çok sayıda kayıt var; rapor en yeni kayıtlarla sınırlandırıldı" / "rapor eksik olabilir" uyarısı veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:6010](../../lib/ui/pages/home_page.dart#L6010) | <code>_fetchLogsForPdf({</code> | Çağrı noktası: kayıtlar sayfa sayfa alınır; hata olursa o ana kadarki kayıtlarla devam edilir (error alanı doldurulur) |
| [lib/ui/pages/home_page.dart:6068](../../lib/ui/pages/home_page.dart#L6068) | <code>_showMessage('Çok sayıda kayıt var; rapor en yeni kayıtlarla sınırlandırıldı.');</code> | Sayfa üst sınırına ulaşılınca rapor kısıtlanır (eski kayıtlar PDF'e girmez) |
| [lib/ui/pages/home_page.dart:6061](../../lib/ui/pages/home_page.dart#L6061) | <code>'${door.doorName} için son 7 güne ait kapı geçiş kaydı bulunamadı.',</code> | Rapor yalnız son 7 gün içindir; kayıt yoksa PDF üretilmez, bu mesaj gösterilir |
| [lib/services/pdf_logs_service.dart:44](../../lib/services/pdf_logs_service.dart#L44) | <code>static Future&lt;Uint8List&gt; generateLogsPdf({</code> | PDF arka plan izolesinde derlenir; hata fırlarsa çağıran "Geçiş raporu PDF oluşturulurken hata:" gösterir |
| [lib/services/pdf_logs_service.dart:85](../../lib/services/pdf_logs_service.dart#L85) | <code>int countGroup(String group) =&gt; logs.where((l) =&gt; l.triggerGroup == group).length;</code> | İstatistik kutuları tetik gruplarından (cloud/local/guest/voice/offline/other) hesaplanır |
| [lib/services/pdf_logs_service.dart:33](../../lib/services/pdf_logs_service.dart#L33) | <code>await Printing.layoutPdf(</code> | Yazdır/kaydet/paylaş önizlemesi platform eklentisiyle açılır; eklenti yoksa (bazı masaüstü/web ortamları) istisna olur |
| [lib/services/auth_service.dart:2657](../../lib/services/auth_service.dart#L2657) | <code>Future&lt;(DoorAccessLogPage?, String?)&gt; listDoorAccessLogs({</code> | Günlük sayfası alma: yetki/ağ hatası burada ApiException mesajına çevrilir |
| [lib/services/auth_api.dart:2822](../../lib/services/auth_api.dart#L2822) | <code>if (startDate != null) 'start_date': startDate.toUtc().toIso8601String(),</code> | Tarih aralığı UTC gönderilir; sunucu tarafı filtre/saat dilimi için sunucu alanına bakın |

**Olası nedenler**
- Seçilen aralıkta (son 7 gün) hiç geçiş kaydı yok
- Günlük sayfaları alınırken ağ/yetki hatası: rapor eksik ya da hiç üretilmez
- Kayıt sayısı sayfa üst sınırını aştı: rapor en yeni kayıtlarla sınırlı
- Yazdırma/paylaşma eklentisi yok ya da önizleme açılamadı
- Türkçe karakter sorunu için cekirdek-pdf-turkce-karakter-font

**Adım adım kontrol**
- Aynı kapının/sitenin geçiş günlüğünü ekranda açın: kayıt görünüyor mu
- Mesajı okuyun: "kayıt bulunamadı" (veri yok), "rapor eksik olabilir" (ağ hatası), "sınırlandırıldı" (çok kayıt)
- Sunucuda door-logs isteklerinin durum kodlarına bakın
- Testle doğrulama: test/pdf_background_test.dart

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a door-logs"
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/pdf_background_test.dart
```

**İlgili testler:** [test/pdf_background_test.dart](../../test/pdf_background_test.dart)

**Bkz.:** [cekirdek-pdf-turkce-karakter-font](#cekirdek-pdf-turkce-karakter-font), [cekirdek-pdf-giris-bilgileri-raporu](#cekirdek-pdf-giris-bilgileri-raporu), [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi)

<a id="cekirdek-pdf-giris-bilgileri-raporu"></a>
### cekirdek-pdf-giris-bilgileri-raporu · Site giriş bilgileri PDF'i (daire/kullanıcı şifre listesi) boş, eksik ya da paylaşılamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/pdf_credentials_service.dart:25](../../lib/services/pdf_credentials_service.dart#L25) | <code>static Future&lt;Uint8List&gt; generateSiteCredentialsPdf({</code> | Tek site: yapıdaki (SiteStructureRecord) daireleri tabloya döker; veri sunucudan gelen yapıdır, PDF veri üretmez |
| [lib/services/pdf_credentials_service.dart:87](../../lib/services/pdf_credentials_service.dart#L87) | <code>static Future&lt;Uint8List&gt; generateMultiSiteCredentialsPdf({</code> | Birden çok site: her site için ayrı sayfa; liste boşsa boş PDF çıkar |
| [lib/services/pdf_credentials_service.dart:152](../../lib/services/pdf_credentials_service.dart#L152) | <code>static Future&lt;void&gt; printOrShareSitePdf({</code> | Yazdır/kaydet önizlemesi (Printing.layoutPdf); dosya adı site adından türetilir |
| [lib/services/pdf_credentials_service.dart:168](../../lib/services/pdf_credentials_service.dart#L168) | <code>static Future&lt;void&gt; shareSitePdf({</code> | Doğrudan paylaşım (Printing.sharePdf) |
| [lib/services/pdf_credentials_service.dart:399](../../lib/services/pdf_credentials_service.dart#L399) | <code>'Kullanıcı Adı (Giriş)',</code> | Tablo sütunları: PIN sütunu YOK (migration 051: sunucu PIN saklamaz; PIN yalnız oluşturma / sıfırlamada bir kez gösterilir) |
| [lib/ui/pages/home_page.dart:5986](../../lib/ui/pages/home_page.dart#L5986) | <code>await PdfCredentialsService.printOrShareSitePdf(</code> | Çağrı noktası (ana sayfa): site yapısı alındıktan sonra çağrılır |
| [lib/services/auth_service.dart:2549](../../lib/services/auth_service.dart#L2549) | <code>Future&lt;(SiteStructureRecord?, String?)&gt; getSiteStructure({</code> | PDF'in veri kaynağı: site yapısı alınamazsa rapor üretilmez |

**Olası nedenler**
- Site yapısı (daire listesi) alınamadı ya da boş: PDF boş/eksik
- Daire kaydında şifre/PIN alanı sunucudan dolu gelmiyor
- Paylaşma/yazdırma eklentisi platformda yok
- Türkçe karakterler için cekirdek-pdf-turkce-karakter-font

**Adım adım kontrol**
- Siteler ekranında daire/sakin listesinin dolu olduğunu doğrulayın
- Veri doluysa ama PDF boşsa test/pdf_background_test.dart ile üretimi deneyin
- Sunucu yanıtındaki apartman alanlarını sunucu alanı klavuzundan doğrulayın

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/pdf_background_test.dart
```

**İlgili testler:** [test/pdf_background_test.dart](../../test/pdf_background_test.dart)

**Bkz.:** [cekirdek-pdf-turkce-karakter-font](#cekirdek-pdf-turkce-karakter-font), [cekirdek-pdf-gecis-raporu-bos](#cekirdek-pdf-gecis-raporu-bos)

<a id="cekirdek-pdf-firmware-raporu"></a>
### cekirdek-pdf-firmware-raporu · Cihaz firmware/güncelleme PDF raporunda sürümler yanlış "güncel değil" görünüyor, "Bilinmiyor" çok ya da rapor oluşmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/pdf_device_firmware_service.dart:69](../../lib/services/pdf_device_firmware_service.dart#L69) | <code>static Map&lt;String, String&gt; latestVersionsByTarget(List&lt;DeviceRecord&gt; devices) {</code> | Hedef sürüm verilmezse her donanım (C3/WROOM) için LİSTEDEKİ en yüksek sürüm "güncel" sayılır: sunucunun yayınladığı sürüm değil |
| [lib/services/pdf_device_firmware_service.dart:50](../../lib/services/pdf_device_firmware_service.dart#L50) | <code>static int compareFirmwareVersions(String a, String b) {</code> | Sayısal sürüm karşılaştırma (1.10.0 > 1.9.0); sayı olmayan parçalar 0 sayılır |
| [lib/services/pdf_device_firmware_service.dart:161](../../lib/services/pdf_device_firmware_service.dart#L161) | <code>final ver = (dev.firmwareVersion ?? 'Bilinmiyor').trim();</code> | Sürüm alanı boşsa "Bilinmiyor" kovasına düşer (cihaz sürümü hiç bildirmemiş) |
| [lib/services/pdf_device_firmware_service.dart:35](../../lib/services/pdf_device_firmware_service.dart#L35) | <code>static String _targetKey(DeviceRecord d) =&gt; d.hardwareTarget ?? 'bilinmiyor';</code> | Donanım hedefi boşsa tüm cihazlar tek "bilinmiyor" hattında karşılaştırılır |
| [lib/services/pdf_device_firmware_service.dart:141](../../lib/services/pdf_device_firmware_service.dart#L141) | <code>final onlineDevices = devices.where((d) =&gt; d.mqttConnected == true).length;</code> | Çevrimiçi sayısı mqttConnected alanından gelir |
| [lib/ui/pages/home_page.dart:5612](../../lib/ui/pages/home_page.dart#L5612) | <code>await PdfDeviceFirmwareService.printOrShareFirmwareReportPdf(</code> | Çağrı noktası: latestTargetVersion VERİLMİYOR, bu yüzden en yüksek listedeki sürüm esas alınır |

**Olası nedenler**
- Listede hiçbir cihaz en güncel sürümde değilse hepsi "güncel" sayılabilir (en yüksek sürüm yine listeden)
- Cihaz sürümü bildirmemiş ya da biçimi sürüm kalıbına uymuyor: "Bilinmiyor"
- Cihaz hardware_target bildirmemiş: tek hatta karıştırılır
- Cihaz listesi eksik/sayfalanmış alındı: rapor yalnız verilen cihazları içerir

**Adım adım kontrol**
- Cihaz sürümünün gerçekte ne olduğunu cihaz listesinden ve sunucudaki firmware kaydından doğrulayın
- Rapor hedef sürümü listeden türettiği için sunucudaki yayın sürümüyle (OTA manifesti) elle karşılaştırın
- Cihaz yazılımı/OTA girişlerine bakın (sunucu ve cihaz alanı)

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/pdf_background_test.dart
```

**İlgili testler:** [test/pdf_background_test.dart](../../test/pdf_background_test.dart)

**Bkz.:** [cekirdek-pdf-turkce-karakter-font](#cekirdek-pdf-turkce-karakter-font), [cekirdek-pdf-gecis-raporu-bos](#cekirdek-pdf-gecis-raporu-bos)

<a id="cekirdek-sifremi-unuttum-eposta-gelmiyor"></a>
### cekirdek-sifremi-unuttum-eposta-gelmiyor · "Şifremi unuttum" isteği başarılı görünüyor ama sıfırlama e-postası gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:782](../../lib/services/auth_service.dart#L782) | <code>Future&lt;String?&gt; forgotPassword({required String email}) async {</code> | Başarıda null döner (başarı mesajı arayüzde); ApiException mesajı ya da genel "Sunucuya bağlanılamadı..." döner |
| [lib/services/auth_api.dart:178](../../lib/services/auth_api.dart#L178) | <code>final uri = Uri.parse('$baseUrl/auth/forgot-password');</code> | POST /auth/forgot-password; yalnız 200 beklenir |
| [server/src/routes/auth_routes.js:387](../../server/src/routes/auth_routes.js#L387) | <code>authRouter.post('/auth/forgot-password', forgotPasswordLimiter, async (req, res) =&gt; {</code> | Sunucu hesap yoksa/pasifse/e-posta gönderimi başarısızsa da AYNI 200 yanıtını döner (istemci farkı göremez); işlem arka planda yürür |

**Olası nedenler**
- E-posta adresi sistemde kayıtlı değil ya da hesap pasif: sunucu bilerek aynı başarı yanıtını verir, e-posta gönderilmez
- E-posta gönderimi sunucuda başarısız oldu (SMTP): istemciye yansımaz, yalnız sunucu günlüğünde "[forgot-password] islem basarisiz" olur
- Hız sınırı (forgotPasswordLimiter) aşıldı: 429 ve bekleme mesajı (cekirdek-hiz-siniri-cok-fazla-deneme)
- E-posta spam klasörüne düştü
- Telefonda internet yok: "Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz." (cekirdek-sunucuya-baglanilamadi)

**Adım adım kontrol**
- E-postanın doğru yazıldığını ve hesabın var/aktif olduğunu kullanıcı yönetiminden doğrulayın
- Sunucu günlüğünde "[forgot-password] islem basarisiz" satırını arayın (aşağıdaki komut)
- SMTP durumu için sunucu alanı e-posta girişlerine bakın

**Günlükte aranacak ifadeler**
- `[forgot-password] islem basarisiz:`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a forgot-password"
```

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart)

**Bkz.:** [cekirdek-dogrulama-kodu-hatalari](#cekirdek-dogrulama-kodu-hatalari), [cekirdek-hiz-siniri-cok-fazla-deneme](#cekirdek-hiz-siniri-cok-fazla-deneme), [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi)

<a id="cekirdek-kapi-listesi-bos-alinamadi"></a>
### cekirdek-kapi-listesi-bos-alinamadi · Ana ekranda kapı listesi boş geliyor ya da kapılar yüklenmiyor ("Kapılar alınamadı", "Oturum bulunamadi")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:3208](../../lib/services/auth_service.dart#L3208) | <code>Future&lt;(List&lt;DoorRecord&gt;?, String?)&gt; listMyDoors() async {</code> | GET /app/my-doors: oturum yoksa "Oturum bulunamadi."; ApiException mesajı aynen döner; diğer istisna "Sunucuya baglanilamadi." |
| [lib/services/auth_api.dart:3295](../../lib/services/auth_api.dart#L3295) | <code>Future&lt;List&lt;DoorRecord&gt;&gt; listMyDoors({required String token}) async {</code> | Yanıttaki doors dizisi yoksa boş liste olur (hata verilmez); bir kapı satırı bozuksa tüm liste "Kapilar verisi ..." hatasına düşer |
| [lib/app.dart:271](../../lib/app.dart#L271) | <code>_showFeedback(error ?? 'Kapılar alınamadı.');</code> | Kısayol/deep link yolunda kapı listesi alınamazsa gösterilen mesaj |
| [lib/services/auth_service.dart:3216](../../lib/services/auth_service.dart#L3216) | <code>if (_session?.token == active.token) {</code> | Liste yalnız oturum hâlâ aynı token'dayken widget'a senkronlanır |
| [server/src/routes/app_doors_routes.js:109](../../server/src/routes/app_doors_routes.js#L109) | <code>appDoorsRouter.get('/app/my-doors', authRequired, async (req, res) =&gt; {</code> | Sunucu tarafı: kullanıcının erişebildiği kapıları döndüren uç nokta |

**Olası nedenler**
- Kullanıcının erişebildiği kapı yok (üyelik/izin yok): sunucu boş liste döner, istemci hata vermez
- Ağ/sunucu hatası: mesaj ApiException'dan gelir (cekirdek-sunucuya-baglanilamadi)
- Bir kapı satırının alanı beklenmedik tipte: "Kapilar verisi beklenen formatta degil." (cekirdek-json-ayristirma-hatasi)
- Oturum düştü: giriş ekranına dönülür (cekirdek-oturum-kendiliginden-dusuyor)

**Adım adım kontrol**
- Aynı kullanıcıyla sunucuda /app/my-doors yanıtına bakın (sunucu alanı kapı erişim girişleri)
- Kullanıcının daire/üyelik ve kapı izinlerinin tanımlı olduğunu yönetici ekranından doğrulayın
- Hata mesajı görünüyorsa mesajın kaynağına göre ilgili girişe gidin

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a my-doors"
```

**İlgili testler:** [test/model_parsing_test.dart](../../test/model_parsing_test.dart), [test/door_widget_service_test.dart](../../test/door_widget_service_test.dart)

**Bkz.:** [cekirdek-json-ayristirma-hatasi](#cekirdek-json-ayristirma-hatasi), [cekirdek-widget-bos-ya-da-giris-yapin](#cekirdek-widget-bos-ya-da-giris-yapin), [cekirdek-sunucuya-baglanilamadi](#cekirdek-sunucuya-baglanilamadi)

<a id="cekirdek-cihaz-sahiplenme-hatalari"></a>
### cekirdek-cihaz-sahiplenme-hatalari · Cihaz sahiplenme/ekleme sırasında "Bu cihaz başka bir hesaba ait", "Cihaz bulunamadı", "Bu cihaz arızalı olarak işaretlenmiş" ya da "Bu cihaz bu kapıya atanamaz" hatası

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_service.dart:593](../../lib/services/auth_service.dart#L593) | <code>Future&lt;Map&lt;String, dynamic&gt;&gt; claimDevice({</code> | Başarıdan sonra rol sunucuda yükselir; istemci /me ile zorla eşitler (force) |
| [lib/services/auth_api.dart:4333](../../lib/services/auth_api.dart#L4333) | <code>path: '/membership/claim-device',</code> | POST /membership/claim-device {deviceInput}; yalnız 200 beklenir |
| [lib/services/auth_api.dart:4044](../../lib/services/auth_api.dart#L4044) | <code>case 'DEVICE_OWNED_BY_ANOTHER':</code> | Cihaz başka bir hesapta kayıtlı (devir gerekir) |
| [lib/services/auth_api.dart:4046](../../lib/services/auth_api.dart#L4046) | <code>case 'DEVICE_DEFECTIVE':</code> | Cihaz arızalı işaretli: sahiplenme/atama reddedilir |
| [lib/services/auth_api.dart:4042](../../lib/services/auth_api.dart#L4042) | <code>case 'DEVICE_NOT_ASSIGNABLE':</code> | Cihaz bu kapıya atanamaz (durumu uygun değil) |
| [lib/services/auth_api.dart:4048](../../lib/services/auth_api.dart#L4048) | <code>case 'DEVICE_NOT_FOUND':</code> | Girilen cihaz kimliği/QR sistemde yok |
| [server/src/routes/membership_routes.js:80](../../server/src/routes/membership_routes.js#L80) | <code>membershipRouter.post('/membership/claim-device', authRequired, claimDeviceLimiter, async…</code> | Sunucu tarafı: hız sınırlı sahiplenme uç noktası |

**Olası nedenler**
- Cihaz kimliği yanlış yazıldı ya da cihaz henüz sisteme kaydedilmedi (DEVICE_NOT_FOUND)
- Cihaz başka hesapta kayıtlı (DEVICE_OWNED_BY_ANOTHER): önce sahibinden bırakılmalı
- Cihaz arızalı olarak işaretlenmiş (DEVICE_DEFECTIVE)
- Cihaz durum olarak atanamaz (DEVICE_NOT_ASSIGNABLE)
- Çok fazla deneme: hız sınırı (429)

**Adım adım kontrol**
- Cihaz kimliğini cihaz etiketi/QR ile karşılaştırın
- Yönetici/şirket ekranında cihazın sahibini ve arıza durumunu doğrulayın
- Sahiplenme sonrası rol değişmediyse /me eşitlemesine bakın (cekirdek-yanlis-rol-menu)

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a claim-device"
```

**İlgili testler:** [test/auth_api_policy_test.dart](../../test/auth_api_policy_test.dart), [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart)

**Bkz.:** [cekirdek-yanlis-rol-menu](#cekirdek-yanlis-rol-menu), [cekirdek-kapi-ac-sunucu-kodlari](#cekirdek-kapi-ac-sunucu-kodlari)

<a id="cekirdek-il-ilce-listesi"></a>
### cekirdek-il-ilce-listesi · Site oluşturma/düzenlemede İl ya da İlçe listesi boş, il seçilince ilçe gelmiyor ya da kayıtlı il/ilçe seçili görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/data/turkey_cities_districts.dart:3](../../lib/data/turkey_cities_districts.dart#L3) | <code>const Map&lt;String, List&lt;String&gt;&gt; turkeyCitiesAndDistricts = {</code> | İl -> ilçe haritası (81 il); yazım Türkçe büyük/küçük harfli birebir anahtarlardır |
| [lib/data/turkey_cities_districts.dart:1146](../../lib/data/turkey_cities_districts.dart#L1146) | <code>List&lt;String&gt; getDistrictsForCity(String? city) {</code> | İl adı haritada birebir yoksa BOŞ liste döner (örn. "Istanbul" yazımı "İstanbul" ile eşleşmez) |
| [lib/data/turkey_cities_districts.dart:1140](../../lib/data/turkey_cities_districts.dart#L1140) | <code>List&lt;String&gt; get turkeyCityNames {</code> | İl adları alfabetik sıralanır (Dart varsayılan sıralaması: Türkçe harf sırası değildir) |
| [lib/ui/dialogs/site_dialog.dart:365](../../lib/ui/dialogs/site_dialog.dart#L365) | <code>turkeyCityNames.contains(_selectedCity)</code> | Kayıtlı il listede yoksa (yazım farkı) seçim BOŞ görünür |
| [lib/ui/dialogs/setup_site_dialog.dart:734](../../lib/ui/dialogs/setup_site_dialog.dart#L734) | <code>final cities = turkeyCitiesAndDistricts.keys.toList();</code> | Kurulum diyaloğu listeyi doğrudan haritadan alır |

**Olası nedenler**
- Sitede kayıtlı il/ilçe adı listedeki yazımla birebir değil (ör. eski/ASCII yazım): seçili görünmez, ilçe listesi boş olur
- İl değiştirilince ilçe bilerek sıfırlanır (_selectedDistrict = null)
- İlçe listesinde olmayan (yeni) ilçe: listeye eklenmesi gerekir

**Adım adım kontrol**
- Sitenin kayıtlı il/ilçe değerini veritabanında/yönetici ekranında listedeki yazımla karşılaştırın
- Eksik ilçe için lib/data/turkey_cities_districts.dart dosyasına ekleyin

**Bkz.:** [cekirdek-json-ayristirma-hatasi](#cekirdek-json-ayristirma-hatasi)

<a id="cekirdek-buyuk-yanit-yavas-arayuz"></a>
### cekirdek-buyuk-yanit-yavas-arayuz · Büyük listeler (site yapısı, günlükler) yüklenirken arayüz takılıyor ya da kareler atlıyor; PDF üretirken uygulama donuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/background_work.dart:28](../../lib/services/background_work.dart#L28) | <code>static Future&lt;R&gt; run&lt;M, R&gt;(</code> | Ağır işleri compute (isolate) ile çalıştırır; web'de aynı izolede çalışır (web'de takılma beklenir) |
| [lib/services/background_work.dart:16](../../lib/services/background_work.dart#L16) | <code>static const int jsonIsolateThresholdBytes = 64 * 1024;</code> | 64 KB altı JSON ana izolede çözülür (isolate maliyeti daha yüksek olduğu için) |
| [lib/services/background_work.dart:46](../../lib/services/background_work.dart#L46) | <code>Object? decodeJsonUtf8Bytes(Uint8List bytes) =&gt; jsonDecode(utf8.decode(bytes));</code> | UTF-8 baytlar arka planda çözülür |
| [lib/services/auth_api.dart:3624](../../lib/services/auth_api.dart#L3624) | <code>Future&lt;void&gt; _decodeLargeBodyInBackground(http.Response response) async {</code> | Büyük yanıtlar için arka plan çözümleme: hata olursa eşzamanlı yola düşer (yine çalışır ama ana izolede) |
| [lib/services/pdf_logs_service.dart:64](../../lib/services/pdf_logs_service.dart#L64) | <code>debugLabel: 'pdf.logs',</code> | PDF derlemesi arka planda; takılma sürüyorsa asıl maliyet yazı tipi yükleme (ağ) ya da önizleme olabilir |
| [lib/services/adaptive_poller.dart:52](../../lib/services/adaptive_poller.dart#L52) | <code>Duration get currentDelay {</code> | Yoklama sıklığı: görünür değilken atlanır, hata sürerken seyrekleşir |

**Olası nedenler**
- Web derlemesinde isolate yoktur: büyük JSON ve PDF ana izolede çözülür
- Yanıt gövdesi 64 KB altında: ana izolede çözülür (küçük, normalde sorun olmaz)
- Isolate'a gönderilemeyen veri: arka plan çözümleme sessizce atlanır ve eşzamanlı yola düşülür
- Liste çok büyük ve ekran bunu tek seferde çiziyor: ekran alanı klavuzuna bakın

**Adım adım kontrol**
- Sorun yalnız web ise beklenen davranıştır; mobilde profil (DevTools) ile jsonDecode/PDF maliyetini ölçün
- Aynı yanıtın boyutunu sunucuda kontrol edin (sayfalama parametreleri)
- Testle doğrulama: test/auth_api_offload_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/auth_api_offload_test.dart test/pdf_background_test.dart
```

**İlgili testler:** [test/auth_api_offload_test.dart](../../test/auth_api_offload_test.dart), [test/pdf_background_test.dart](../../test/pdf_background_test.dart)

**Bkz.:** [cekirdek-json-ayristirma-hatasi](#cekirdek-json-ayristirma-hatasi), [cekirdek-pdf-gecis-raporu-bos](#cekirdek-pdf-gecis-raporu-bos), [cekirdek-kapi-durumu-cevrimdisi](#cekirdek-kapi-durumu-cevrimdisi)

<a id="cekirdek-uygulama-baslangic-yon-kilidi"></a>
### cekirdek-uygulama-baslangic-yon-kilidi · Uygulama yatay döndürülemiyor ya da açılışta ekran yönü/tema beklenmedik; main.dart başlangıç sırası soruluyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/main.dart:26](../../lib/main.dart#L26) | <code>await SystemChrome.setPreferredOrientations([</code> | Web dışında yalnız dikey (portraitUp/Down) kilitlenir: yatay döndürme KASITLI olarak kapalı; hata yutulur |
| [lib/main.dart:46](../../lib/main.dart#L46) | <code>child: MyApp(</code> | Başlatma sırası: binding + çökme raporlama kancaları -> yön kilidi -> tema, Kolay görünüm ve liste/kutucuk tercihlerinin yüklenmesi -> açılış kapısı (AppGate: bakım/zorunlu güncelleme) -> uygulama |
| [lib/app.dart:497](../../lib/app.dart#L497) | <code>maxScaleFactor: 2.0,</code> | Yazı ölçeği 2.0 ile sınırlanır: sistem yazı boyutu daha büyükse uygulama onu kırpar |

**Olası nedenler**
- Yatay mod bilerek kapalı (portrait kilidi)
- Sistem yazı boyutu çok büyük: ölçek en çok 2.0 uygulanır
- Tema servisi okunamadı: sistem teması (cekirdek-tema-tercihi-kaydedilmiyor)

**Adım adım kontrol**
- Yatay mod gerekiyorsa lib/main.dart içindeki yön listesi değiştirilmelidir (tasarım kararı: dikey)
- Taşma sorunları için ekran alanı klavuzu ve test/screens/* düzen testleri

**İlgili testler:** [test/cold_start_test.dart](../../test/cold_start_test.dart), [test/design/app_shell_test.dart](../../test/design/app_shell_test.dart)

**Bkz.:** [cekirdek-tema-tercihi-kaydedilmiyor](#cekirdek-tema-tercihi-kaydedilmiyor), [cekirdek-acilis-splash-takili](#cekirdek-acilis-splash-takili)

