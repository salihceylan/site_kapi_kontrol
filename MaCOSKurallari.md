# macOS iOS DERLEME AJANI KURALLARI

Bu proje normalde Windows ortamında geliştirilen ve çalışan bir Flutter uygulamasıdır.

Bu macOS ortamının TEK GÖREVİ:

- projeyi iOS için derlemek
- iOS Simulator üzerinde çalıştırmak
- Xcode hatalarını çözmek
- CocoaPods işlemlerini yapmak
- iOS signing / provisioning işlemlerini yapmak
- TestFlight / App Store için archive ve IPA oluşturmak

BU ORTAMDA NORMAL UYGULAMA GELİŞTİRMESİ YAPILMAYACAKTIR.

---

# 1. EN ÖNEMLİ KURAL

Uygulamanın Flutter/Dart tarafının çalıştığını kabul et.

iOS derleme problemi çıktığında:

ORTAK UYGULAMA KODUNU DEĞİŞTİRME.

Öncelikle problemin:

- Xcode
- CocoaPods
- iOS SDK
- signing
- provisioning
- deployment target
- Info.plist
- entitlements
- Swift / Objective-C
- iOS plugin configuration
- iOS permission
- Podfile

kaynaklı olduğunu varsay ve yalnızca iOS tarafında çözmeye çalış.

---

# 2. DEĞİŞTİRİLMESİ YASAK ALANLAR

Kullanıcı açıkça izin vermediği sürece aşağıdaki alanlara DOKUNMA:

lib/

test/

assets/

web/

windows/

linux/

macos/

android/

backend kodları

API yapısı

MQTT yapısı

authentication sistemi

üyelik sistemi

cihaz yönetimi

veritabanı modelleri

state management

uygulama ekranları

iş mantığı

routing yapısı

Flutter widget'ları

Dart servisleri

---

# 3. pubspec.yaml KURALI

pubspec.yaml dosyasını kendiliğinden değiştirme.

Şunları otomatik yapma:

- paket ekleme
- paket kaldırma
- paket sürümü değiştirme
- dependency upgrade
- Flutter SDK constraint değiştirme

Bir paket değişikliği zorunlu görünüyorsa:

DUR.

Önce kullanıcıya bildir.

Şu bilgileri ver:

1. Hangi paket sorun çıkarıyor?
2. Sorun neden iOS tarafında çözülemiyor?
3. Hangi sürüm değişmeli?
4. Android / Windows tarafını etkileyebilir mi?

Onay almadan pubspec.yaml değiştirme.

---

# 4. İZİN VERİLEN ALANLAR

Normal şartlarda yalnızca aşağıdaki iOS alanlarında işlem yapabilirsin:

ios/

Özellikle:

ios/Podfile

ios/Podfile.lock

ios/Runner/

ios/Runner/Info.plist

ios/Runner/Runner.entitlements

ios/Runner.xcodeproj

ios/Runner.xcworkspace

ios/Flutter/

Xcode Build Settings

Signing & Capabilities

Provisioning Profile

Bundle Identifier

Deployment Target

iOS permissions

Swift / Objective-C iOS bridge kodları

CocoaPods yapılandırması

---

# 5. IOS DIŞI DOSYA DEĞİŞİKLİĞİ

Bir iOS derleme problemini çözmek için ios/ klasörü dışındaki bir dosyanın değiştirilmesi gerektiğini düşünüyorsan:

DEĞİŞİKLİK YAPMA.

Önce kullanıcıya bildir.

Şu formatı kullan:

SORUN:
...

IOS TARAFINDA NEDEN ÇÖZÜLEMİYOR:
...

DEĞİŞMESİ GEREKEN DOSYA:
...

ÖNERİLEN DEĞİŞİKLİK:
...

WINDOWS / ANDROID RİSKİ:
...

Kullanıcı açıkça onay vermeden değişiklik yapma.

---

# 6. İLK KONTROLLER

Her çalışma başlangıcında önce ortamı kontrol et:

git status

flutter --version

flutter doctor -v

xcodebuild -version

pod --version

Sonra:

flutter pub get

çalıştır.

Ancak bağımlılıkları yükseltme.

---

# 7. OTOMATİK YÜKSELTME YASAK

Kullanıcı onayı olmadan aşağıdakileri çalıştırma:

flutter upgrade

flutter pub upgrade

flutter pub upgrade --major-versions

pod update

brew upgrade

dart pub upgrade

Toplu paket güncellemesi yapma.

---

# 8. COCOAPODS

İlk tercih:

cd ios
pod install
cd ..

olmalıdır.

pod update ancak gerçekten zorunluysa ve kullanıcı onay verdiyse kullanılabilir.

Pod problemlerinde önce:

Podfile

Podfile.lock

deployment target

CocoaPods sürümü

Xcode sürümü

plugin podspec uyumluluğu

kontrol edilmelidir.

---

# 9. DERLEME AKIŞI

İşleri küçük adımlar halinde yap.

Sıra:

1. Ortam kontrolü
2. flutter pub get
3. pod install
4. flutter analyze
5. iOS debug build
6. Simulator testi
7. release build
8. Xcode archive
9. TestFlight / App Store işlemleri

Bir aşama başarısız olursa sonraki aşamaya geçme.

Önce mevcut problemi çöz.

---

# 10. DERLEME KOMUTLARI

İlk olarak:

flutter build ios --debug

Başarılı olursa:

flutter build ios --release

Gerekirse:

open ios/Runner.xcworkspace

kullan.

CocoaPods kullanılan projelerde:

Runner.xcodeproj

yerine:

Runner.xcworkspace

kullan.

---

# 11. SIMULATOR

Önce Simulator üzerinde doğrulama yap.

Simulator sorunları ile:

- signing
- provisioning
- gerçek cihaz
- App Store

sorunlarını birbirine karıştırma.

Simulator için gereksiz signing değişiklikleri yapma.

---

# 12. FLUTTER CLEAN KURALI

Her hata çıktığında otomatik olarak:

flutter clean

çalıştırma.

Önce hatanın nedenini analiz et.

Gerçekten gerekirse:

flutter clean
flutter pub get
cd ios
pod install
cd ..

uygulanabilir.

---

# 13. REFACTOR YASAK

Bu macOS ortamında aşağıdakiler YAPILMAYACAK:

- refactor
- kod temizliği
- klasör taşıma
- class yeniden adlandırma
- mimari değişiklik
- state management değiştirme
- servis yeniden yazma
- ekran tasarımı değiştirme
- widget değiştirme
- backend değiştirme
- API yapısını değiştirme

Kodun güzel olup olmadığı bu ajanın konusu değildir.

Tek hedef:

IOS BUILD.

---

# 14. WINDOWS ANA GELİŞTİRME ORTAMIDIR

Windows tarafı ana geliştirme ortamıdır.

macOS yalnızca:

WINDOWS PROJESİ
        ↓
       Git
        ↓
     macOS
        ↓
   iOS Build
        ↓
     Xcode
        ↓
   Simulator
        ↓
    Archive
        ↓
TestFlight / App Store

iş akışında kullanılacaktır.

macOS üzerinde yapılan iOS değişiklikleri mümkün olduğunca:

ios/

klasörü ile sınırlı kalmalıdır.

---

# 15. GIT KURALI

Çalışmaya başlamadan önce:

git status

çalıştır.

Yerel değişiklikleri silme.

Reset yapma.

Force checkout yapma.

Kullanıcı onayı olmadan:

git reset --hard

git clean -fd

git checkout .

gibi veri kaybettirebilecek komutları çalıştırma.

---

# 16. DEĞİŞİKLİK RAPORU

Her değişiklikten sonra kullanıcıya şu formatta rapor ver:

DEĞİŞEN DOSYA:
...

DEĞİŞİKLİK:
...

NEDEN:
...

IOS'A ÖZEL Mİ:
Evet / Hayır

ANDROID / WINDOWS ETKİSİ:
Yok / Olası / Var

DERLEME SONUCU:
...

---

# 17. KRİTİK KARAR KURALI

Bir iOS derleme hatasını çözmenin iki yolu varsa:

A) Flutter ortak kodunu değiştirmek

B) iOS yapılandırmasını değiştirmek

HER ZAMAN B seçeneğini tercih et.

Ortak Flutter kodu yalnızca gerçekten kaçınılmazsa ve kullanıcı açıkça izin verdiyse değiştirilebilir.

---

# 18. ANA PRENSİP

Bu uygulama zaten çalışan bir uygulamadır.

Senin görevin uygulamayı yeniden geliştirmek değildir.

Senin görevin:

"BU ÇALIŞAN FLUTTER UYGULAMASINI IOS ÜZERİNDE DERLENEBİLİR VE YAYINLANABİLİR HALE GETİRMEK."

Bu görev sırasında ortak uygulama kodunu mümkün olduğunca sıfır değişiklikle koru.