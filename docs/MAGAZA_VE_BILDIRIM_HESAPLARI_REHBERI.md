# Mağaza ve bildirim hesapları rehberi (2026-10-21)

Cenk ve Salih için adım adım rehber: Apple (App Store), Google Play, Firebase (telefon bildirimi) ve Google Cloud (Drive onay ekranı).
Ücret ve sürelerin hepsi kaynağıyla yazıldı (bölüm 8, erişim 2026-10-21). Ekranlar zamanla değişebilir; adım adları değişmişse aynı
anlama gelen düğmeyi arayın. Doğrulayamadığımız yerler "doğrulanamadı" diye işaretli.

Kararlar: H5 ve H6 (`docs/PLATFORM_YOL_HARITASI.md` "Karar kaydı (2026-10-21)"): mağaza hesapları **şirket adına** açılır.
Uygulama yükleme adımları ayrı belgede: `docs/YAYIN_HAZIRLIGI.md`.

## Kısa yanıt: "Apple hesabını açarız, şirket adına olması şart mı?"

**Şart değil, ama şirket adına öneriyoruz.**

- Apple'da kişi olarak (bireysel) kayıt olursanız App Store'da satıcı olarak **kişinin yasal adı** görünür. Kuruluş olarak kayıt
  olursanız **şirketin yasal adı** görünür.
- Kuruluş kaydı için şirketin tüzel kişi olması, bir **D-U-N-S numarası**, kaydı yapanın şirketi bağlama yetkisi, çalışan bir web sitesi
  ve şirket alan adında bir iş e-postası gerekir. Apple şahıs işletmelerini (tek kişilik işletme) bireysel kayda yönlendirir; marka
  adı ve şube kabul etmez.
- Güde bir limited şirkettir (GÜDE TEKNOLOJİ LTD. ŞTİ.); Apple'ın "tüzel kişi" şartına uyar görünüyor. D-U-N-S numarası olup olmadığı
  bilinmiyor (**doğrulanamadı**).
- Google Play'de de kuruluş hesabı öneriyoruz. Google'ın sayfasına göre 13 Kasım 2023'ten sonra açılan **kişisel** hesaplar uygulamayı
  yayımlamadan önce en az 12 test kullanıcısıyla 14 gün kesintisiz kapalı test yapmak zorunda. Sayfa bu şartı kuruluş hesapları için
  yazmıyor.

## 0. Önce toplayın (Cenk)

| Bilgi | Değer / not |
| --- | --- |
| Şirketin yasal adı (ticaret sicilindeki gibi) | GÜDE TEKNOLOJİ LTD. ŞTİ. (karar H1) |
| Merkez adresi | Yalı Mah. 6436 Sok. No:37/A Karşıyaka / İzmir (H1). D-U-N-S kaydındaki adresle aynı olmalı. |
| Telefon | 0543 795 60 44 (H1). Google Play kuruluş hesabında **herkese açık** görünür. |
| Web sitesi | gudeteknoloji.com.tr. 2026-10-21'de açılıyor ve şirketi anlatıyor. Apple çalışan, içerikli bir site ister. |
| Şirket alan adında e-posta | Apple, kaydı yapanın iş e-postasının şirket alan adında olmasını ister. Sitede `bilgi@gudeteknoloji.com` görünüyor; hangi alan adının şirkete ait olduğunu Cenk teyit etsin. |
| Yetkili kişi | Apple'da kaydı yapan kişi şirketi sözleşmeyle bağlayabilmeli: sahip ya da kurucu, üst yönetici ya da bu yetki verilmiş çalışan. |
| Kart | Apple yıllık 99 USD (yerel para birimiyle gösterilebilir); web'den alımda USD çekilebilen kredi kartı ister. Google bir kez 25 USD; ön ödemeli kart kabul etmez. |
| Belgeler | Ticaret sicil kaydı ve imza yetkisini gösteren belgeler elinizin altında olsun: D&B arayıp sorabilir, Apple noter onaylı belge isteyebilir. |

## 1. D-U-N-S numarası (Apple ve Google ortak)

D-U-N-S, Dun & Bradstreet'in (D&B) şirketlere verdiği 9 haneli numaradır. Apple ve Google kuruluş hesabı için ister.

1. Apple'ın D-U-N-S arama aracını açın (Apple hesabıyla giriş ister): developer.apple.com/enroll/duns-lookup.
2. Şirketin yasal adını, merkez adresini, posta adresini ve iş iletişim bilgilerinizi girin.
3. Şirket listede çıkarsa numarayı not edin. Çıkmazsa bilgileri D&B'ye gönderme seçeneği gelir; gönderin.
4. D&B temsilcisi sizi arayıp şirket türü, çalışan sayısı gibi bilgileri sorabilir. Sicil belgelerini hazır tutun.

- **Ücret:** Apple'a göre "çoğu ülkede ücretsiz". Google da D&B'den ücretsiz alınabileceğini yazıyor. Türkiye'ye özgü bilgi bulunamadı
  (**doğrulanamadı**).
- **Süre:** Apple: numaranın D&B'den gelmesi **5 iş gününe kadar**, ardından Apple'a ulaşması **2 iş gününe kadar** sürer; iki haftayı
  geçerse D&B'ye yazın. Google: süreç **30 güne kadar** sürebilir. Erken başlayın.

## 2. Apple Developer Program (kuruluş hesabı)

1. **Apple Hesabı:** şirket e-postanızla bir Apple Hesabı açın (Apple bunu önerir). İki adımlı doğrulamayı açın. Ad ve soyad alanına
   kendi yasal adınızı yazın (takma ad ya da şirket adı yazmayın, onay gecikir).
2. developer.apple.com/programs/enroll sayfasında "Start your enrollment" deyin ve kuruluş olarak kaydı seçin.
3. Şirketin yasal adını (marka adı değil), D-U-N-S numarasını, web sitesini, iş e-postanızı ve telefonunuzu girin.
4. Apple bilgileri doğrular ve e-postayla sonraki adımı bildirir. Gerekirse "noter onaylı" şirket belgesi isteyebilir.
5. Onaydan sonra Apple Developer Program Lisans Sözleşmesi'ni kabul edip ödemeyi yapın: **yılda 99 USD** (bölgeye göre yerel para
   birimiyle gösterilir). Ödemeden sonra 24 saat içinde üyelik onayı gelmezse Apple'a yazın.
6. **Team ID:** üyelik sayfasında görünür. Salih'e güvenli bir kanaldan verin; depoya ve sohbete yazılmaz.
7. **Salih'i ekleyin:** ekibe "Admin" rolüyle davet edin (bildirim anahtarı oluşturmak için Account Holder ya da Admin gerekir).

- **Süre:** Apple doğrulamanın ne kadar sürdüğünü yazmıyor (**doğrulanamadı**).
- **Bireysel hesaptan kuruluşa geçiş:** Apple "bize yazın" diyor; süreci sayfada anlatmıyor.
- **Sonra:** App Store Connect'te uygulama kaydı (paket kimliği `tr.com.gudeteknoloji.siteyonetim`) ve `docs/YAYIN_HAZIRLIGI.md`
  bölüm 6.

## 3. Google Play Console (kuruluş hesabı)

1. **Google Hesabı:** şirket adına, kişisel olmayan bir hesap kullanın (18 yaş şartı var).
2. play.google.com/console sayfasından kaydolun; Google Play Geliştirici Dağıtım Sözleşmesi'ni kabul edin.
3. **Ücret:** bir kez **25 USD** (kredi ya da banka kartı; ön ödemeli kart olmaz).
4. **Hesap türü:** "Kuruluş" (Organization).
5. İstenenler: D-U-N-S numarası (Google: "olmadan kuruluş hesabı açamazsınız"), kuruluş adı ve adresi (Google ödeme profilinden),
   kuruluş telefonu ve web sitesi, iletişim kişisinin adı, e-postası ve telefonu, geliştirici e-postası ve telefonu.
6. **Kimlik doğrulama:** Google geçerli kimlik ve kart gibi belgeler isteyebilir. Bilgiler geçersiz bulunursa kayıt ücreti iade edilmez.
7. **Herkese açık bilgiler:** kuruluş hesabında Google Play'de yasal ad, yasal adres, geliştirici e-postası ve geliştirici telefonu
   görünür. (Kişisel hesapta yasal ad, ülke ve e-posta görünür.)
8. **Kapalı test şartı:** Google'ın sayfası bu şartı yalnız 13 Kasım 2023'ten sonra açılan kişisel hesaplar için yazıyor (12 test
   kullanıcısı, 14 gün).
9. **Bazı uygulamalar kuruluş hesabı ister:** Google'a göre "Financial products and services, including but not limited to banking,
   loans, stock trading, investment funds, cryptocurrency software wallets, and cryptocurrency exchanges", sağlık, VPN ve devlet
   uygulamaları. Uygulamamız bugün para almıyor; kartla ödeme (F6) eklenince bu maddenin bizi kapsayıp kapsamadığı ayrıca bakılmalı
   (**doğrulanamadı**).
10. **Salih'i ekleyin:** Kullanıcılar ve izinler bölümünden davet edin.

- **Kişiselden kuruluşa geçiş:** mümkün. Hesap sahibi web sitesini doğrular, kuruluş ödeme profili (D-U-N-S ile) bağlar; Google geçişten
  sonra yeni uygulama göndermeden önce en az 72 saat beklemeyi öneriyor. Kuruluştan kişisele dönüş yoktur.
- **Sonra:** uygulama oluşturma, Play App Signing ve iç test: `docs/YAYIN_HAZIRLIGI.md` bölüm 5.

## 4. Firebase: telefon bildirimi

Kod hazır; sunucuda bildirim kapalı (`PUSH_ENABLED=0`). Ayrıntılı teknik koşullar: `docs/PLATFORM_BELGELER.md` "B0. Durum ve
kullanıcıdan gerekenler".

1. **Proje:** şirket Google hesabıyla console.firebase.google.com'da yeni proje. Google Analytics'i **kapalı** bırakın (gereksiz veri).
2. **Android uygulaması:** paket adı `tr.com.gudeteknoloji.siteyonetim`; yayın imzasının parmak izini ekleyin (`docs/YAYIN_HAZIRLIGI.md`
   bölüm 3). `google-services.json` dosyasını indirip Salih'e verin.
3. **iOS uygulaması:** aynı paket kimliği; `GoogleService-Info.plist` dosyasını Salih'e verin.
4. **Apple bildirim anahtarı (APNs):** Apple Developer'da Certificates, Identifiers & Profiles, Keys, "+" deyin; ad verin; "Apple Push
   Notification service" kutusunu seçip yapılandırın; onaylayın ve **.p8** dosyasını indirin. Apple uyarısı: anahtar hesabınızda
   saklanmaz, **bir daha indirilemez**; güvenli yerde tutun. Key ID'yi not edin. Firebase'de Proje ayarları, Cloud Messaging, iOS
   uygulama yapılandırması, "APNs authentication key", Upload: dosyayı seçin ve Key ID'yi girin. (Firebase sayfası Team ID'den söz
   etmiyor; ekran isterse Team ID'yi girin.)
5. **Hizmet hesabı (sunucunun bildirim gönderebilmesi için):**
   - Firebase belgesindeki yol: Proje ayarları, Hizmet hesapları, "Generate New Private Key", "Generate Key". JSON dosyası iner.
     Depodaki teknik belgeye göre (`docs/PLATFORM_BELGELER.md` B0 madde 6) bu varsayılan hesap gerekenden geniş yetkilidir.
   - Önerdiğimiz yol (en az yetki): Google Cloud Console'da IAM, Hizmet hesapları, yeni hesap; rol olarak yalnız **Firebase Cloud
     Messaging API Admin** (`roles/firebasecloudmessaging.admin`; mesaj gönderme izni `cloudmessaging.messages.create` içinde). Sonra
     Anahtarlar, Anahtar ekle, JSON. (Bu rolle gönderimin çalıştığı bu çalışmada denenmedi.)
   - **Tuzak:** 3 Mayıs 2024 ve sonrasında oluşturulan Google Cloud kuruluşlarında "Disable service account key creation" kısıtı
     (`constraints/iam.managed.disableServiceAccountKeyCreation`) varsayılan olarak uygulanır. Google'a göre kuruluş, alan adınızdan bir
     kullanıcı ilk kez girdiğinde ya da kuruluşa bağlı olmayan bir faturalama hesabı açıldığında kendiliğinden oluşur. Anahtar oluşturma
     hata verirse kuruluş politikası yöneticisi (`roles/orgpolicy.policyAdmin`) bu proje için istisna tanımlamalıdır.
   - JSON dosyasını e-postayla, mesajla, sohbete ya da depoya **koymayın**. Salih sunucuya güvenli kopyalar (`/etc/kapi/` altına, yalnız
     uygulama kullanıcısı okuyabilir) ve `.env`'de yolunu verir.
6. Google Cloud'da Android ve iOS API anahtarlarını uygulama kimliğiyle kısıtlayın.
7. **Ücret:** Firebase fiyat sayfasında Cloud Messaging (FCM) "No-cost" (ücretsiz) yazıyor.
8. **Açılış sırası:** yasal metinler (Gizlilik Politikası 3.8) avukattan geçer, sonra Salih `PUSH_ENABLED=1` yapar (en son adım).

## 5. Google Cloud: Drive onay ekranı (dalga 4 için hazırlık)

Sitelerin dosyaları ileride sitenin kendi Google Drive'ında duracak (karar D1). Bunun için Google'ın onay ekranı hazırlanmalı.
Ayrıntı: `docs/PLATFORM_DRIVE_DEPOLAMA.md`.

1. Şirket hesabıyla bir Google Cloud projesi açın (bildirim projesinden ayrı olması önerilir, yetkiler karışmaz).
2. Google Drive API'yi etkinleştirin.
3. **Google Auth Platform (OAuth onay ekranı):** Kitle "External" (dışarıya açık); marka bilgileri: uygulama adı, destek e-postası, logo,
   ana sayfa (gudeteknoloji.com.tr), gizlilik politikası adresi, yetkili alan adları.
4. **İzin kapsamı:** yalnız `drive.file`. Google bu kapsamı "hassas olmayan" ve "çoğu kullanım için önerilen" kapsamlar arasında
   sayıyor (uygulama yalnız kendi oluşturduğu ya da kullanıcının açtığı dosyalara erişir).
5. **Alan adı doğrulaması:** gudeteknoloji.com.tr'yi Google Search Console'da, projede Sahip ya da Düzenleyici olan bir hesapla doğrulayın.
6. **Yayın durumu:** "Testing" durumunda en çok 100 test kullanıcısı olur ve verilen yenileme anahtarı **7 günde** geçersiz olur.
   Canlıya geçmek için "Publish app" ile "In production" yapın.
7. **Doğrulama:** Google'a göre yalnız hassas olmayan kapsam kullanan uygulamada uygulama doğrulaması **zorunlu değil**; ama adın ve
   logonun onay ekranında görünmesi için **marka doğrulaması** gerekir. Otomatik kontrol genellikle birkaç dakika; elle incelemeye
   düşerse genellikle **2-3 iş günü**.
8. **Ana sayfa ve gizlilik politikası şartları:** ana sayfa herkese açık olmalı, uygulamayı tanıtmalı, yalnız giriş sayfası olmamalı
   (Play Store ya da Facebook sayfası geçmez). Gizlilik politikası ana sayfayla **aynı alan adında** olmalı, ana sayfadan ve onay
   ekranından bağlantı verilmeli, Google kullanıcı verisinin nasıl kullanıldığını anlatmalı. Not: 2026-10-21'de ana sayfa otomatik
   okunduğunda gizlilik politikası bağlantısı görülmedi; elle kontrol edin.
9. OAuth istemcisi ve yönlendirme adresi Drive bağlantısı yazılırken (dalga 4) Salih tarafından eklenir.

- **Ücret:** onay ekranı ve doğrulama için ücret bilgisi sayfalarda yok (**doğrulanamadı**). Drive API kotaları ve ücretsiz sınırlar
  `docs/PLATFORM_DRIVE_DEPOLAMA.md` bölüm 2'de; bu çalışmada yeniden doğrulanmadı.

## 6. Ücret ve süre özeti

| Kalem | Ücret | Süre | Kaynak (bölüm 8) |
| --- | --- | --- | --- |
| D-U-N-S | Çoğu ülkede ücretsiz (Apple); D&B'den ücretsiz (Google) | Apple: 5 iş günü + Apple'a ulaşması 2 iş günü; Google: 30 güne kadar | [1], [3] |
| Apple Developer Program | Yılda 99 USD (yerel para birimi olabilir) | Doğrulama süresi yazmıyor | [2], [4] |
| Google Play Console | Bir kez 25 USD | Doğrulama süresi yazmıyor; kişiden kuruluşa geçişte 72 saat bekleme önerisi | [5], [7] |
| Firebase Cloud Messaging | Ücretsiz | — | [10] |
| Google OAuth marka doğrulaması | Yazmıyor | Dakikalar; elle incelemede 2-3 iş günü | [14] |

## 7. Kim ne yapar?

| İş | Kim |
| --- | --- |
| D-U-N-S başvurusu, Apple ve Google kuruluş kaydı, ödeme | Cenk (şirketi bağlama yetkisi olan kişi) |
| Şirket alan adında e-posta | Cenk |
| Salih'i Apple'a (Admin), Google Play'e ve Firebase / Google Cloud projelerine eklemek | Cenk |
| APNs anahtarı, Firebase uygulama kayıtları, yapılandırma dosyalarını depoya ve sunucuya koymak | Salih |
| Hizmet hesabı dosyasını sunucuya güvenli kopyalamak, `PUSH_ENABLED=1` (en son) | Salih |
| Uygulama kayıtları, mağaza metinleri, ekran görüntüleri | Salih ve Cenk (`docs/YAYIN_HAZIRLIGI.md`) |

## 8. Kaynaklar (hepsine 2026-10-21'de erişildi)

1. Apple, D-U-N-S Number: <https://developer.apple.com/support/D-U-N-S/>
2. Apple, Enrollment (bireysel ve kuruluş, ücret, belgeler): <https://developer.apple.com/support/enrollment/>
3. Apple, D-U-N-S arama aracı (Apple hesabıyla giriş ister): <https://developer.apple.com/enroll/duns-lookup/>
4. Apple, Enroll: <https://developer.apple.com/programs/enroll/>
5. Google Play Console Help, hesap açma ve 25 USD ücret: <https://support.google.com/googleplay/android-developer/answer/6112435>
6. Google Play Console Help, "Required information to create a Play Console developer account" (D-U-N-S, herkese açık bilgiler):
   <https://support.google.com/googleplay/android-developer/answer/13628312>
7. Google Play Console Help, "Update developer identity details managed by a Google payments profile" (kişiselden kuruluşa geçiş):
   <https://support.google.com/googleplay/android-developer/answer/16260648>
8. Google Play Console Help, kişisel hesaplarda test şartı (12 test kullanıcısı, 14 gün):
   <https://support.google.com/googleplay/android-developer/answer/14151465>
9. Google Play Console Help, "Play Console Requirements" (kuruluş hesabı gereken uygulamalar):
   <https://support.google.com/googleplay/android-developer/answer/10788890>
10. Firebase fiyatları: <https://firebase.google.com/pricing>
11. Firebase, sunucudan gönderim yetkisi (hizmet hesabı, kapsam): <https://firebase.google.com/docs/cloud-messaging/auth-server>
12. Firebase, APNs anahtarını yükleme: <https://firebase.google.com/docs/cloud-messaging/ios/certs>
13. Apple, özel anahtar oluşturma (APNs): <https://developer.apple.com/help/account/keys/create-a-private-key/>
14. Google, marka doğrulaması: <https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification>
15. Google Cloud Help, "Verification requirements": <https://support.google.com/cloud/answer/13464321>
16. Google Cloud Help, "Manage App Audience" (Testing, 100 test kullanıcısı): <https://support.google.com/cloud/answer/15549945>
17. Google Cloud Help, "OAuth App Verification Help Center": <https://support.google.com/cloud/answer/13463073>
18. Google, OAuth 2.0 (Testing durumunda 7 günlük yenileme anahtarı): <https://developers.google.com/identity/protocols/oauth2>
19. Google Drive API kapsamları (`drive.file` hassas değil): <https://developers.google.com/workspace/drive/api/guides/api-specific-auth>
20. Google Cloud IAM, Firebase Cloud Messaging rolleri: <https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging>
21. Google Cloud, güvenlik taban kısıtları (hizmet hesabı anahtarı): <https://docs.cloud.google.com/organization-policy/manage-baseline-constraints>
    ve kuruluşun ne zaman kendiliğinden oluştuğu: <https://docs.cloud.google.com/resource-manager/docs/secure-by-default-organizations>
22. Güde Teknoloji web sitesi (çalışıyor mu, iletişim bilgileri): <https://gudeteknoloji.com.tr/>
