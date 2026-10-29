# OTA Firmware İmzası (Ed25519): Mimari, Anahtar Saklama, Yayın Akışı ve Geçiş Planı

Son güncelleme: 2026-10-29. Durum: **Dalga F (sahip onayı 2026-10-28): imzalama aracı, sunucu yükleme/sunum kuralları ve cihaz doğrulayıcısı yazıldı, birleştirildi ve
testlerle sınandı; canlıya ALINMADI, hiçbir karta YAZILMADI, üretim anahtarı üretilmedi.** Bu belgedeki hiçbir adım henüz kartta ya da canlı sunucuda çalıştırılmadı
**[denenmedi]**: ilk kullanımda önce bir TEST kartıyla ve `allowed_uids` ile kısıtlı yayınla deneyin.

Kapsam: iki OTA hedefinin (`esp32-c3`, `esp32-wroom`) cihaz yazılımı güncellemelerinin imzalanması. Mevcut OTA akışı (SHA-256, artan sürüm, geri alma,
`allowed_uids`) `OTA_KURULUM.txt`'de anlatılır; imza onun ÜSTÜNE eklenen ek bir katmandır, hiçbirini kaldırmaz. Plan:
`docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md` (Dalga F). Saha denemeleri: `SAHA_KONTROL_LISTESI.md` bölüm 122. Kullanıcıya düşen işler:
`BEKLEYEN_ISLER.md` bölüm 7. Bu belge bütünü anlatır; ayrıntı belgeleri: araç `tools/ota_imza/README.md`, sunucu yükleme ucu
`server/src/routes/firmware_admin_routes.js` (üst açıklaması), cihaz tarafı `docs/OTA_IMZA_CIHAZ.md`.

İşaretler:

- **[kullanıcıda]**: proje sahibinin yapacağı adım. Yapay zekâ ajanı bunları yapmaz: üretim anahtarını üretmek, imzalamak, karta yazmak/flaşlamak, canlıya
  firmware yayınlamak.
- **[denenmedi]**: yazıldı ama kartta ya da canlıda çalıştırılmadı.
- Komut sözdiziminin, imza dosyası biçiminin ve imzalanan iletinin bayt düzeninin tek kaynağı `node tools/ota_imza/ota_imza.mjs yardim` çıktısı ve
  `tools/ota_imza/README.md`'dir (sunucu ve firmware aynı biçimi uygular); bu belgedeki komutlar akışı göstermek içindir.

---

## 1. Neden imza?

Kapı denetleyicisi fiziksel girişi açar. Cihaza giren yazılım değişirse kapının davranışı değişir (örneğin röle hep açık, kayıtlar kapalı, cihaz saldırganın ağ
içi dayanak noktası). Bugün OTA kanalını şunlar korur (hepsi kodda doğrulandı: `cihaz_kontrol/include/ota_guncelleme.h`, `server/src/routes/firmware_routes.js`):

| Koruma | Nerede | Neyi engeller | Neyi ENGELLEMEZ |
|---|---|---|---|
| HTTPS + cihazda sabit kök sertifika (ISRG Root X1, `tls_kok_sertifika.h`) | cihaz | ağ üzerinde araya girme | sunucunun, alan adının ya da sertifikanın kendisinin ele geçirilmesi |
| İndirme adresi ön eki `https://api.gudeteknoloji.com.tr/` (`OTA_ALLOWED_URL_PREFIX`) | cihaz | başka alan adından yazılım indirtme | aynı alan adından kötü ikili |
| SHA-256 zorunlu, akışlı hesap (`otaIndirVeYaz`) | cihaz | bozuk/eksik indirme | özeti manifest'ten alır: manifest'i değiştiren özeti de değiştirir |
| Yalnız artan sürüm (cihazda `otaSurumKarsilastir`, sunucuda `compareVersionParts`) | cihaz + sunucu | eski sürüme dönüş | manifest'e yazılmış uydurma yüksek sürüm numarası |
| Geri alma: yeni imaj Wi-Fi + MQTT ile 60 sn sağlıklı kalmazsa eski sürüme dönülür (`otaGecerliligiDogrula`) | cihaz | açılmayan/bağlanamayan imaj | bağlanıp çalışan ama kötü niyetli imaj |

**Kalan boşluk:** ikili, SHA-256 ve sürüm aynı sunucudan gelir. Sunucuya yazabilen biri (sızan parola, ele geçirilen hesap, hatalı dağıtım) ikiliyi, özetini ve
sürümünü birlikte değiştirir; sahadaki bütün kapı denetleyicileri bunu kabul eder. Sunucu erişim bilgilerinin sızması riski gerçektir (bkz. `BEKLEYEN_ISLER.md`
bölüm 6, "Canlı parola ve sır döndürme"); imza, bu risk kapanana kadar da kapandıktan sonra da geçerli ikinci savunma hattıdır.

**İmza ile:** cihaz, yalnız proje sahibinin özel anahtarıyla imzalanmış yazılımı kurar. Sunucu ele geçirilse bile saldırgan geçerli imza üretemez; yapabileceği en
kötü şey yeni güncelleme dağıtımını durdurmaktır (hizmet engelleme). Aynı katman şu kazaları da yakalar: yanlış hedefin paketini yayınlamak (C3 yerine WROOM), eski
bir sürümü yüksek numarayla yayınlamak, yedekten dönerken bozuk dosya. Korumadığı şeyler: bölüm 10.

---

## 2. Mimari

### 2.1 Kararlar

| Konu | Karar | Kaynak |
|---|---|---|
| Algoritma | Ed25519 (RFC 8032): 32 bayt genel anahtar, 64 bayt imza. Node yerleşik `crypto` ile, ek bağımlılık yok | Dalga F planı |
| İmza biçimi | AYRIK imza: `firmware.bin` değişmez; imza yanında `firmware.bin.sig` (JSON, içinde 64 baytlık Ed25519 imzası 128 hane hex olarak) durur; mevcut SHA-256/md5 akışı bozulmaz. Etiket tek: `KAPI-OTA-IMZA-V1` | Dalga F tasarımı + `tools/ota_imza/README.md` |
| Güven kökü | Genel anahtar cihazın yazılımına derleme zamanında gömülür; cihaz anahtarı sunucudan indirmez | Dalga F planı |
| Özel anahtar | Depo DIŞINDA, yalnız proje sahibinde; ayrıca sunucuda, CI'da ve ajan oturumunda bulunmaz | Dalga F planı (depo dışı) + bu belge |
| Sunucunun rolü | Genel anahtarla doğrular, düşürmeyi engeller, imza bilgisini yansıtır; imzalayamaz. Güvenlik sınırı sunucu DEĞİL cihazdır | Dalga F planı |
| Geçiş | Tek köprü sürüm: sahadaki cihazlar onu eski yolla alır, sonrası imzalı (bölüm 7) | Dalga F planı |
| İmzalanan şey | Dosyanın kendisi değil, onu bağlayan kısa bir ileti: hedef + sürüm + boyut + SHA-256 (+ yalnız bilinçli, sınırlı sürüm düşürmede `rollback_max`) (2.3) | `tools/ota_imza` biçimi |
| Anahtar sayısı | Tek anahtar çifti iki hedef için ortak (hedef imzalı iletinin içinde olduğundan hedefler karışmaz); yedek anahtar için 8.4 | bu belge (gerekçeli varsayılan) |
| Üretim imzası | Yalnız proje sahibi, kendi oturumunda; ajan imzalamaz | bu belge (gerekçeli varsayılan) |

Gerekçeler:

- **Ed25519:** küçük anahtar ve imza (cihazda yer az), hızlı doğrulama, imza deterministiktir (zayıf rastgelelik yüzünden anahtar sızma riski yok), Node'da yerleşik.
- **Ayrık imza:** ikili olduğu gibi kalır; sahadaki eski cihazların kullandığı `firmware.bin` + SHA-256 yolu hiç değişmez (AGENTS.md kural 2 ve 3).
- **İleti imzası:** cihaz 1,8 MB'lık imajı belleğe alamaz, zaten akışlı SHA-256 hesaplar; imza bu özeti, hedefi ve sürümü bağlayan kısa iletiyi korur.
- **Tek anahtar çifti:** saklanacak ve yedeklenecek sır sayısı en azda kalır. İki hedef AGENTS.md kural 4 gereği ayrı klasör, ayrı manifest ve ayrı imzalı hedef alanı
  ile zaten karışmaz. Hedef başına ayrı çift istenirse aynı araç iki kez çalıştırılır; bunun bedeli iki kat sır ve iki kat yedektir.
- **Yalnız sahip imzalar:** ajan oturumlarının günlükleri saklanır ve komut enjeksiyonuna ya da çıktıya sızmaya açıktır; anahtar bir kez sızarsa bütün filo tehlikeye
  girer. Test imzaları (araç testleri, atılabilir deneme anahtarları) bunun dışındadır.

### 2.2 Akış

```text
 İMZA MAKİNESİ (proje sahibi)          SUNUCU (VPS)                              CİHAZ (ESP32)
 ----------------------------          ------------                              -------------
 1. derle -> firmware.bin
 2. imzala (özel anahtar)
    -> firmware.bin.sig
 3. kendi makinede doğrula
 4. yükle (bin + imza) ------------> 5. genel anahtarla doğrula
                                          imzasız / yanlış / düşük sürüm -> REDDET
                                       6. dosyaları yaz, manifest'i EN SON değiştir;
                                          imza bilgisi manifest yanıtına yansır
                                                                          <--- 7. manifest iste (HTTPS)
                                       8. manifest + imza bilgisi ------>
                                                                               9. URL ön eki + artan sürüm kontrolü;
                                                                                  ikiliyi indir (SHA-256 akışlı hesaplanır)
                                                                              10. iletiyi KENDİ değerleriyle kur
                                                                                  (hedef, boyut, SHA-256), gömülü genel
                                                                                  anahtarla doğrula
                                                                              11. yalnız doğruysa etkinleştir; açılışta
                                                                                  geri alma sınaması
```

### 2.3 İmzalanan ileti ve imza dosyası

Ed25519'un imzaladığı şey `firmware.bin`'in kendisi değil, onu bağlayan kısa bir iletidir (cihaz 1,8 MB'lık imajı belleğe alamaz; zaten akışlı SHA-256 hesaplar). İletinin
yapısı (ASCII, her satır tek LF ile biter, CR/boşluk/ek satır yok; BAĞLAYICI tanım `tools/ota_imza/README.md`'dedir ve üç taraf da — araç, sunucu, cihaz — AYNI baytları kurar):

```text
KAPI-OTA-IMZA-V1<LF>
target=<esp32-c3 | esp32-wroom><LF>
version=<X.Y.Z veya X.Y.Z.W><LF>
size=<bayt sayısı><LF>
sha256=<64 hane küçük harf hex><LF>
rollback_max=<sürüm><LF>        <- YALNIZ imzalı, sınırlı sürüm düşürme yetkisinde (aşağıda); yoksa bu satır HİÇ olmaz
```

Sürüm biçimi: `X.Y.Z` ya da `X.Y.Z.W`, her parça 0–9999, başında sıfır yok (`4.4.0` evet; `v4.4.0`, `4.4`, `4.4.0-beta` hayır). `ota_guncelleme.h`'deki `OTA_VERSION_*`
sabitleri bu biçimde olmalı ve manifestteki `version` imzadakiyle HARFİ HARFİNE aynı olmalıdır. Etiket (`KAPI-OTA-IMZA-V1`) alan ayırıcıdır: aynı anahtarla başka amaçla atılan
imza OTA imzası sayılmaz. (Cihaz yazılımı taslağındaki eski `SKP-OTA-V1` etiketi KALDIRILDI; üç bileşen de yalnız `KAPI-OTA-IMZA-V1` bilir.)

İmza dosyası (`firmware.bin.sig`) aracın ürettiği JSON'dur: `format` (`KAPI-OTA-IMZA-V1`), `algorithm` (`Ed25519`), `target`, `version`, `size`, `sha256`, (varsa) `rollback_max`,
`key_id` ve 128 hane hex `signature` (64 baytlık Ed25519 imzası). Sunucu yüklemede bu dosyayı sıkı ayrıştırır, imzayı doğrular, KANONİK biçimde (araçla aynı alan sırası) diske yazar ve
cihaza `<imaj>.bin.sig` adresinden sunar; imza ayrıca manifest yanıtında `signature` alanı olarak da iletilir (aynı 128 hane hex) ve cihaz öncelikle onu kullanır. `key_id`, genel
anahtarın SHA-256 özetinin ilk 8 baytıdır (16 hane hex); iletinin parçası değildir, hangi genel anahtarın kullanılacağını ve anahtar uyuşmazlığını görmek içindir (bölüm 8). Araç ve
sunucu aynı değeri gösterir; firmware'in seri günlüğe yazdığı anahtar parmak izi de bununla karşılaştırılır (bölüm 7, G0). İmza dosyasını elle düzenlemeyin.

**Sürüm düşürme yetkisi (`rollback_max`):** varsayılan imza HİÇBİR düşürmeyi yetkilendirmez; cihaz yalnız ARTAN sürümü kurar. Bilinçli, sınırlı bir düşürme gerekirse eski kod
`imzala ... --rollback-max <sürüm>` ile imzalanır: yetki iletinin son satırı olarak imzanın İÇİNE girer (sunucu ya da manifest tek başına bir şey açamaz). Cihaz, yalnız sürümü
`rollback_max`'a kadar (dahil) olan ve manifestte `allow_downgrade: true` gören durumda bu paketi, kendi sürümünden DÜŞÜK olsa da kurar. `rollback_max` imzalanan sürümden BÜYÜK
olmalıdır ve imza yalnız düşürme için doğrulanır (sürümü paketin altındaki cihaz bu paketi yükseltme olarak kuramaz; sunucu ona sunmaz). Bu bir operasyonel istisnadır; asıl geri dönüş yolu
eski kodu DAHA YÜKSEK bir sürüm numarasıyla yeniden derleyip normal imzalamaktır.

Cihaz iletiyi kendi bildiği/hesapladığı değerlerle yeniden kurar: hedef = derleme sabiti `OTA_TARGET`, boyut ve SHA-256 = indirdiği baytlar; yalnız sürüm ve imza
sunucudan gelir. Bundan çıkan güvenceler:

| Saldırı (sunucuya yazabilen biri) | Sonuç |
|---|---|
| Manifest'teki `sha256`'yı değiştirilmiş ikiliye göre güncellemek | Cihaz kendi hesapladığı özetle iletiyi kurar, imza tutmaz: REDDEDİLİR |
| Başka hedefin (ör. WROOM) imzalı paketini C3 klasörüne koymak | Hedef cihazın kendi sabitidir, imza tutmaz: REDDEDİLİR |
| Eski imzalı paketi manifest'te yüksek sürüm numarasıyla sunmak | Sürüm imzanın içindedir, imza tutmaz: REDDEDİLİR |
| Başka bir anahtarla imzalamak | Gömülü genel anahtarla doğrulanmaz: REDDEDİLİR |
| Eski imzalı paketi KENDİ sürüm numarasıyla sunmak | İmza geçerlidir; cihaz varsayılan olarak yalnız ARTAN sürümü kurar (izinli düşürme: S5), yani yalnız o sürümden daha eski çalışan cihazlar etkilenir (bölüm 10) |

Bu satırların cihaz düzeyindeki doğrulaması firmware ana makine testleriyle ve aracın test vektörleriyle yapılır. Saha denemesinde sunucu kendi doğrulamasını yaptığı için
imzası doğrulanamayan manifest cihaza hiç sunulmaz (bölüm 5, S3); cihaz düzeyindeki ret sahada yalnız imzasız paketle görülebilir (SAHA 122.5).

---

## 3. Anahtarlar: üretim, saklama, erişim, yedek

Bu belgenin en önemli bölümü budur: sistemin güvenliği özel anahtarın güvenliğine eşittir. Anahtar kaybolursa sahadaki cihazlara bir daha imzalı OTA gönderilemez
(8.1); anahtar sızarsa saldırgan, sunucuya yazabildiği anda bütün filoya yazılım gönderebilir (8.3).

### 3.1 Üretim [kullanıcıda]

- **Yer:** proje sahibinin kendi bilgisayarı (imza makinesi), uzaktan masaüstü/ekran paylaşımı kapalıyken.
- **Kendi PowerShell pencerenizde çalıştırın, ajan terminalinde DEĞİL.** Ajan oturumlarının günlükleri saklanır; özel anahtarın yolu, parolası ve araç çıktısı sohbete ya da
  günlüğe yapıştırılmaz. Genel anahtar ve `key_id` paylaşılabilir (sır değildir).
- **Klasör:** depo DIŞINDA oluşturun. Öneri: `G:\site\_anahtarlar\ota-imza\` (Android yükleme anahtarının üst klasörüyle aynı; bkz. `docs/YAYIN_HAZIRLIGI.md` bölüm 3).
  Araç, depo içindeki bir yolu REDDEDER ve var olan dosyanın üzerine yazmaz.
- **Parola:** anahtar PAROLALI üretilir (PKCS#8, AES-256-CBC). Parola yalnız `OTA_IMZA_PAROLA` ortam değişkeniyle verilir (komut satırında kabul edilmez). Kabuk
  geçmişine düşmesin diye `Read-Host -AsSecureString` kullanın. Depo kökünden, PowerShell:

```powershell
New-Item -ItemType Directory -Force 'G:\site\_anahtarlar\ota-imza' | Out-Null
$g = Read-Host 'Anahtar parolası (en az 8 karakter)' -AsSecureString
$env:OTA_IMZA_PAROLA = [System.Net.NetworkCredential]::new('', $g).Password
node tools\ota_imza\ota_imza.mjs anahtar-uret --ozel 'G:\site\_anahtarlar\ota-imza\ota-imza-k1.pem' --genel 'G:\site\_anahtarlar\ota-imza\ota-imza-k1.pub.pem'
Remove-Item Env:OTA_IMZA_PAROLA
```

- **Çıktı:** genel anahtar (PEM, hex ve firmware için C++ tanımı) ve `key_id`. Bunları not alın (3.6). Genel anahtarın C++ tanımı firmware'in OTA imza başlığına
  işlenir (`cihaz_kontrol/include/`); `.pub.pem` dosyası depoya girmez (`.gitignore` `*.pem` kuralı) ve girmesi gerekmez.
- **Hemen sonra:** yedekleri alın (3.5) ve yedekten deneme imzası doğrulayın (SAHA 122.1).
- **Test anahtarları üretim anahtarından AYRIDIR:** araç testleri her koşuda atılabilir anahtar üretir; hiçbir test anahtarının genel kısmı üretim firmware'ine girmez.

### 3.2 Saklama [kullanıcıda]

| Öğe | Nerede durur | Kural |
|---|---|---|
| Özel anahtar dosyası (parolalı) | Asıl kopya: şifreli harici bellek (Windows 11 Pro'da BitLocker To Go ya da eşdeğeri); yalnız imza oturumunda bilgisayara takılır. Çalışma kopyası gerekirse `G:\site\_anahtarlar\ota-imza\` | Depo klasörünün (`G:\site\site_kapi_kontrol`) DIŞINDA. Sunucuya, e-postaya, sohbete ve bulut klasörüne (OneDrive/Drive/Dropbox) KONMAZ. `.gitignore` `*.pem`/`*.key` dosyalarını yok sayar, ama bu yalnız son güvenlik ağıdır, saklama yeri değildir |
| Parola | Parola yöneticisi + kâğıt kopya (ayrı fiziksel yer) | Anahtar dosyasıyla AYNI yerde durmaz; hiçbir dosyaya, betiğe ya da komut satırına yazılmaz |
| Yedek 1 | İkinci şifreli harici bellek, asıl kopyadan FARKLI fiziksel konumda | Anahtar dosyasının birebir kopyası |
| Yedek 2 | Parola yöneticisi kasasında dosya eki ya da üçüncü şifreli bellek | Şifreli; aynı yerde iki yedek tutulmaz |
| Genel anahtar | Firmware kaynağı (depoda) ve sunucu ayarı | Sır değildir; yedeği gerekmez ama değeri 3.6'da yazılı olmalı |

Windows'ta dosya izinleri otomatik kısıtlanmaz: yalnız kendi hesabınıza açın (PowerShell: `icacls '<yol>' /inheritance:r /grant:r "$($env:USERNAME):F"`). Bu yalnız başka
kullanıcı hesaplarını engeller; aynı hesapla çalışan her süreç (ajan dahil) dosyayı yine okuyabilir, bu yüzden asıl koruma parola ve çıkarılabilir şifreli bellektir.

### 3.3 Kim erişir

| Kim / ne | Özel anahtar | Parola | Genel anahtar | `.bin` ve `.sig` |
|---|---|---|---|---|
| Proje sahibi | EVET (tek kişi) | EVET | evet | evet |
| Geliştirici / yapay zekâ ajanı | HAYIR | HAYIR | evet (depoda) | evet |
| GitHub Actions / CI | HAYIR (CI imzalamaz) | HAYIR | evet | — |
| Canlı sunucu (VPS) | HAYIR | HAYIR | evet (doğrulamak için) | evet (sunar) |
| Sunucu yedekleri (`kapi_firmware_*.tgz.enc`) | HAYIR | HAYIR | evet | evet |
| Cihazlar | HAYIR | HAYIR | evet (gömülü) | indirir |

Sunucudaki firmware yedeği (`deploy/ops/backup_db.sh`, bkz. `docs/OPERASYON_YEDEK_IZLEME.md`) `server/firmware` içindeki `.bin`, `.sig` ve manifest dosyalarını arşivler.
Özel anahtarı `server/firmware` içine ya da sunucudaki herhangi bir klasöre KOYMAK, onu yedek arşivlerine ve dış kopyalara da taşımak demektir; yasaktır.

### 3.4 Yapılmayacaklar

- Özel anahtarı ya da parolasını depoya, `server/firmware`'e, `.env`'e, betiklere, CI gizli değişkenlerine, sohbete, e-postaya, ekran görüntüsüne ya da bulut klasörüne koymak.
- Bir ajanın (ya da başka birinin) anahtarı okuyabileceği oturumda imzalamak; ajan çıktısına `OTA_IMZA_PAROLA` değerini basmak.
- Üretim anahtarıyla deneme/test imzası atmak (testler atılabilir anahtar kullanır).
- Anahtarı "geçici olarak" sunucuya kopyalayıp imzalamak.

### 3.5 Yedek ve geri yükleme provası [kullanıcıda]

Yılda bir ve imza makinesi her değiştiğinde: yedek kopyadan bir deneme `firmware.bin`'ini imzalayın ve genel anahtarla doğrulayın (`dogrula` komutu `SONUC: GECTI`
yazmalı). Geçmezse yedek geçersizdir: hemen yenileyin. Yedeklerden biri kaybolduysa aynı gün yenisini üretin; anahtarın tek kopyası kalması kabul edilmez.

### 3.6 Genel anahtar ve parmak izi

Anahtar üretilince doldurulur. Genel anahtarın tamamı firmware'in OTA imza başlığındadır; burada yalnız `key_id` (16 hane hex) yazılır ve cihazdaki / sunucudaki /
araç çıktısındaki değerlerle karşılaştırmak için kullanılır.

| Anahtar | Rol | Üretim tarihi | `key_id` |
|---|---|---|---|
| K1 | Aktif imza anahtarı | (anahtar üretilince yazılır) | (anahtar üretilince yazılır) |
| K2 | Yedek anahtar (yalnız cihaz iki yuvalıysa; 8.4) | | |

---

## 4. İmzalama ve yayın akışı (her yeni sürüm için, köprü sürüm dahil)

Ön koşul: anahtar çifti üretildi ve yedeklendi (bölüm 3), genel anahtar firmware'e ve sunucuya işlendi (bölüm 7, G0).

| # | Kim | Adım | Kanıt |
|---|---|---|---|
| 1 | ajan | Kod hazırlanır; ilgili hedefin sürüm sabiti ARTIRILIR (`cihaz_kontrol/include/ota_guncelleme.h`: `OTA_VERSION_C3` ya da `OTA_VERSION_WROOM`). Sürüm yalnız artar | `git diff` |
| 2 | ajan | İlgili ortam derlenir (PlatformIO): C3 `lolin_c3_mini`, WROOM `esp32_relay_wroom`. Ana makine testleri geçer | Çıktı: `cihaz_kontrol\.pio\build\<ortam>\firmware.bin`; boyutu OTA bölümüne sığmalı (0x1E0000 = 1.966.080 bayt) |
| 3 | kullanıcıda | İmza makinesinde şifreli bellek takılır; parola ve anahtar yolu yalnız bu pencerede tanımlanır (aşağıdaki blok) | — |
| 4 | kullanıcıda | `imzala` çalıştırılır | `IMZALANDI`; ekranda `sha256` ve `key_id` (`key_id` 3.6'daki değerle aynı olmalı) |
| 5 | kullanıcıda | `dogrula` çalıştırılır | `SONUC: GECTI` |
| 6 | kullanıcıda | Yayın: `firmware.bin` ve imza sunucunun yükleme ucuna gönderilir (aşağıda). Sunucu hedefi, sürümü, imaj başlığını, SHA-256'yı ve imzayı doğrular; dosyaları yazar, manifest'i EN SON ve atomik değiştirir | HTTP 201; yanıtta `signed: true`, `audience` (`allowed_uids` ya da `all`), `sha256` = araç çıktısındaki `sha256` |
| 7 | kullanıcıda | Hızlı kontrol (`curl`) | `update_available: true`, doğru `version`, `sha256`, `url` ve imza alanları (`signature*`) |
| 8 | kullanıcıda | Önce yalnız 1–2 TEST cihazı (`allowed_uids`); OTA kontrolü tetiklenir | `ota_validated` (~60 sn) |
| 9 | kullanıcıda | Kapsam genişletilir (bölüm 7 kapıları geçildiyse `allowed_uids` boşaltılır) | Sürüm Raporu (PDF) |
| 10 | kullanıcıda | Yayın günlüğüne satır eklenir (bölüm 12) | — |

Adım 3–5 (PowerShell, depo kökünden; `<hedef>` = `esp32-c3` ya da `esp32-wroom`, `<X.Y.Z>` = adım 1'deki sürüm):

```powershell
$g = Read-Host 'Anahtar parolası' -AsSecureString
$env:OTA_IMZA_PAROLA = [System.Net.NetworkCredential]::new('', $g).Password
$env:OTA_IMZA_OZEL_ANAHTAR = 'G:\site\_anahtarlar\ota-imza\ota-imza-k1.pem'
node tools\ota_imza\ota_imza.mjs imzala cihaz_kontrol\.pio\build\<ortam>\firmware.bin --hedef <hedef> --surum <X.Y.Z>
node tools\ota_imza\ota_imza.mjs dogrula cihaz_kontrol\.pio\build\<ortam>\firmware.bin --genel 'G:\site\_anahtarlar\ota-imza\ota-imza-k1.pub.pem' --hedef <hedef> --surum <X.Y.Z>
Remove-Item Env:OTA_IMZA_PAROLA, Env:OTA_IMZA_OZEL_ANAHTAR
```

Aracın yaptığı denetimler (README esastır): imaj başlığındaki yonga kimliği hedefle uyuşmalı; sürüm metni imajın içinde bulunmalı (bulunmazsa UYARI: sürüm
sabiti artırılmadan derlenmiş ya da eski `.bin` verilmiş olabilir; cihaz güncellemeden sonra aynı sürümü tekrar tekrar indirmeye çalışır, bu durumda DURUN); imza
üretildikten sonra aynı ileti genel anahtarla yeniden doğrulanır ve geçmezse `.sig` dosyası YAZILMAZ.

Yayın (adım 6) yükleme ucuyla yapılır, yalnız süper kullanıcıya açıktır: `POST /admin/firmware/<hedef>/releases?[version=<X.Y.Z>&allowed_uids=<UID,UID>&notes=<not>&interval_hours=<1-168>&enabled=<0|1>]`;
gövde ham `firmware.bin` (`Content-Type: application/octet-stream`), imza `X-Ota-Signature` başlığında: aracın ürettiği `.sig` dosyasının base64'ü (ÖNERİLEN; sürüm, hedef, boyut ve özet dosyadan
okunup yüklenen paketle birebir karşılaştırılır, `version` parametresi gerekmez) ya da tek satırlık ham JSON'u; ya da yalnız 64 baytlık ÇIPLAK imza (128 hane hex / 88 karakter base64) ve bu durumda
`version` parametresi ZORUNLUDUR. `Authorization: Bearer <süper kullanıcı JWT'si>`. Belirteci komut satırına düz yazmayın (ortam değişkeninden okutun), sohbete ya da günlüğe
yapıştırmayın. Tam parametre listesi ve hata kodları: `server/src/routes/firmware_admin_routes.js` üst açıklaması. `GET /admin/firmware/<hedef>/releases` canlı yayını ve diskteki
imzalı kayıtları listeler (imza değeri dönmez). **[denenmedi]**

Windows PowerShell örneği (depo kökünden; `curl.exe` yazın — `curl` PowerShell'de başka bir komutun takma adıdır; `-X POST --data-binary @dosya` dosyayı olduğu gibi gönderir):

```powershell
$jwt = Read-Host 'Süper kullanıcı JWT' -AsSecureString
$env:OTA_JWT = [System.Net.NetworkCredential]::new('', $jwt).Password
$bin = 'cihaz_kontrol\.pio\build\<ortam>\firmware.bin'
$sig = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$bin.sig"))
curl.exe -sS -X POST --data-binary "@$bin" -H "Authorization: Bearer $env:OTA_JWT" -H "Content-Type: application/octet-stream" -H "X-Ota-Signature: $sig" "https://api.gudeteknoloji.com.tr/admin/firmware/<hedef>/releases?allowed_uids=<TEST KARTI UID>"
Remove-Item Env:OTA_JWT
```

Başarılı yanıt 201'dir (`signed: true`, `sha256` araç çıktısındakiyle aynı). Hata kodları bölüm 9'dadır.

Yayın kuralları:

- **Yükleme ucu esastır:** yeni paketler yalnız bu uçla yüklenir. Sunucu dosyaları kendisi yazar (bölüm 5, S2); `scp` ile dosya kopyalayıp `manifest.json`'u elle düzenlemek
  YENİ paketler için kullanılmaz: doğrulamayı, düşürme korumasını ve denetim kaydını atlar. Yükleme sırasında Windows'ta `>` yönlendirmesi ya da metin kipli aktarım dosyayı
  bozar; dosyayı olduğu gibi (`--data-binary @dosya`) gönderin. İmza dosyasını metin düzenleyiciyle açıp kaydetmeyin.
- **Sunucu ön koşulları (G0):** canlı `.env`'de `OTA_PUBLIC_KEY` tanımlı olmalı (bölüm 5, S7) ve nginx'te `/admin/firmware/` yolu için istek gövdesi sınırı yükseltilmiş olmalı
  (varsayılan 1 MB yetmez; `OTA_MAX_FIRMWARE_BYTES` varsayılanı 1.966.080 bayttır, yani en az 2 MB). Aksi hâlde yükleme 503 (`OTA_KEY_NOT_CONFIGURED`) ya da nginx 413 ile reddedilir.
  `allowed_uids` önce yalnız test cihazları; `usb_required`, `interval_hours`, `force` alanlarının anlamı `OTA_KURULUM.txt`'deki gibidir.
- **Hızlı kontrol:** `curl "https://api.gudeteknoloji.com.tr/firmware/<hedef>/manifest.json?current_version=<eski sürüm>&uid=<test cihazı UID>"`.
- **Aynı sürüm numarasını yeniden kullanmayın:** cihazlar aynı sürümü yeniden kurmaz ve sunucu aynı numarayı farklı içerikle reddeder (409 `FIRMWARE_VERSION_EXISTS`); içeriği değişen
  paket için sürümü artırıp yeniden derleyin ve imzalayın.
- **OTA tetikleme:** tek cihaz için kartı yeniden başlatın (açılıştan yaklaşık 90–150 sn sonra kendiliğinden kontrol eder) ya da sunucuda `server/` klasöründe
  `node scripts/trigger_ota.js <UID>` (MQTT ortam değişkenleri `.env`'de; komut `retry` taşımaz). Şirket Paneli > Kayıtlı Cihazlar > "Tümüne OTA Kontrolü" BÜTÜN kayıtlı
  cihazlara komut gönderir (`retry` ile); `allowed_uids` dışındaki cihazlar paketi almaz.
- **Deneme paketi kuralı:** olumsuz denemeler (imzasız, yanlış anahtarlı, düşük sürümlü paket; SAHA 122) ASLA `allowed_uids` boş bırakılarak yayınlanmaz. İmzayı henüz bilmeyen
  sahadaki eski cihazlar SHA-256 tuttuğu için bu paketi kurar. Deneme paketi her zaman ÇALIŞAN, zararsız bir derleme olmalı; `allowed_uids` yalnız TEST kartının UID'sini
  içermeli. Sunucu korumasını aşan denemelerde (paketi elle klasöre koymak) önce mevcut `manifest.json`'un yedeğini alın, iş bitince geri koyun.
- **Her yükleme canlı yayını değiştirir:** hedef başına tek `manifest.json` vardır; yükleme ucuyla gönderilen her paket, `allowed_uids` yalnız kimin alacağını sınırlasa da, o hedefin
  CANLI yayını olur (öncekini sahadaki diğer cihazlar artık görmez). Deneme sürümlerini gerçek sürüm sırasına uygun numaralandırın (düşürme gerektirmeyecek biçimde) ve
  sıradaki gerçek sürümü yayınlayarak ilerleyin; geri dönmek gerekirse S5 (izinli düşürme) ya da daha yüksek numaralı yeniden yayın.

---

## 5. Sunucu kuralları

Dalga F planı: "yüklemede doğrulama + imza meta + sürüm düşürme koruması; mevcut paketler geçiş için sunulabilir kalır". Kural ayrıntıları sunucu kodundadır
(`server/src/services/ota_signature.js`, `firmware_release_service.js`, `server/src/routes/firmware_admin_routes.js`, `firmware_routes.js`). Yükleme ucu yalnız süper kullanıcıya
açıktır.

| # | Kural | Ne olur |
|---|---|---|
| S1 | Yeni paket imzalı olmalıdır | Yükleme ucu imzasız (400 `FIRMWARE_SIGNATURE_REQUIRED`), biçimi bozuk (400 `FIRMWARE_SIGNATURE_MALFORMED`) ya da doğrulanamayan (400 `FIRMWARE_SIGNATURE_INVALID`) paketi reddeder: imza `OTA_PUBLIC_KEY` ile eşleşmeli ve imzalanan hedef/sürüm/boyut/SHA-256 (varsa `rollback_max` da) yüklenen paketle birebir aynı olmalıdır. İmaj da denetlenir: ilk bayt 0xE9, imaj başlığındaki yonga kimliği hedefle uyumlu (`FIRMWARE_TARGET_MISMATCH`), boyut `OTA_MAX_FIRMWARE_BYTES` altında (varsayılan 0x1E0000; `FIRMWARE_TOO_LARGE`) |
| S2 | Sunucu yazar | Dosyalar `firmware-v<sürüm>.bin` (içeriği bir daha DEĞİŞMEZ), `firmware-v<sürüm>.bin.sig` ve `firmware-v<sürüm>.release.json` olarak yazılır; `manifest.json` EN SON ve atomik değişir (cihaz yarım yayın görmez). Elle manifest düzenlemek gerekmez |
| S3 | İmza bilgisi yansıtılır | Manifest yanıtına `signature` (128 hane hex), `signature_alg`, `signature_format`, `signature_key_id` ve `signature_url` (`<imaj>.bin.sig`) eklenir; imzayı bilmeyen eski firmware ek alanları yok sayar (geriye uyum). Elle bozulmuş ya da doğrulanamayan imzalı manifest cihazlara SUNULMAZ |
| S4 | Düşürme koruması | Yayındaki sürümden DÜŞÜK sürüm reddedilir (409 `FIRMWARE_DOWNGRADE_REJECTED`); aynı sürüm numarası farklı içerikle reddedilir (409 `FIRMWARE_VERSION_EXISTS`) |
| S5 | İzinli düşürme | `allow_downgrade=1` ve `downgrade_reason` (10-300 karakter) ile yapılır; platform denetim kaydı ÖNCE yazılır, yazılamazsa işlem yapılmaz (503 `FIRMWARE_AUDIT_UNAVAILABLE`). Bu tek başına yalnız "canlı sürüm artık budur" kararıdır: sürümü paketin altındaki cihazlar bunu normal yükseltme olarak alır, daha yeni sürümdekilere DÜŞÜRME SUNULMAZ (cihaz imzasız yetkiyle düşürmeyi kurmaz). Düşürmenin cihaza yansıması ayrıca ve yalnız İMZAYLA yetkilendirilir: paket `imzala --rollback-max <sürüm>` ile atılmış olmalıdır; bu durumda sunucu yalnız sürümü `rollback_max`'a kadar olan (ve paketten yeni) cihazlara `allow_downgrade: true` + `rollback_max` ile teklif eder; `rollback_max` taşıyan imza yalnız `allow_downgrade=1` ile ve gerçekten düşürme olan yüklemede kabul edilir (400 `FIRMWARE_ROLLBACK_NOT_ALLOWED` / `FIRMWARE_ROLLBACK_NOT_DOWNGRADE`; `rollback_max` paket sürümünden büyük olmalı: `FIRMWARE_ROLLBACK_INVALID`), sürümü paketin altındaki cihaza sunulmaz. En güvenli geri dönüş yine de eski kodu DAHA YÜKSEK bir sürüm numarasıyla yeniden derleyip normal imzalamaktır (`OTA_KURULUM.txt` kuralı) |
| S6 | Geçiş | `OTA_SERVE_UNSIGNED` (varsayılan 1): yayında olan mevcut (imzasız) manifest'ler geçiş boyunca sunulmaya devam eder; yalnız YENİ yüklemeler imza ister. 0 yapılınca imzasız manifest'ler sunulmaz (bölüm 7, G5) |
| S7 | Özel anahtar yok | `OTA_PUBLIC_KEY` yalnız GENEL anahtar alır (PEM ya da 32 bayt hex/base64); özel anahtar yazılırsa reddedilir. Tanımlı değilse yükleme ucu 503 (`OTA_KEY_NOT_CONFIGURED`) verir. Sunucuda özel anahtar, parola ya da bunların yolu hiçbir yerde (`.env`, betik, yedek) bulunmaz |

Sunucu doğrulaması **erken uyarıdır, güvenlik sınırı değildir:** sunucuyu ele geçiren biri bu kontrolleri atlayabilir; asıl savunma cihazdadır (bölüm 6). Sunucu
kuralları operasyon kazalarını (yanlış dosya, eski sürüm, imzasız paket) yayından önce yakalar. Sunucudaki düşürme koruması da yalnız operasyon hatasına karşıdır;
saldırgana karşı koruma cihazdaki sürüm kuralıdır ve sürümün imzada olmasıdır (2.3). Yükleme ucu süper kullanıcı oturumuna dayanır; çalınan bir oturum belirteci bile, özel
anahtar olmadan üretilemeyen imza yüzünden, imzasız paket yükletemez.

---

## 6. Cihaz kuralları

Köprü sürümden (ilk imzalı sürüm) itibaren, her iki hedefte:

| # | Kural |
|---|---|
| C1 | **İmza zorunludur.** İmza yoksa, geçersizse ya da tanınmayan bir anahtarla atılmışsa güncelleme KURULMAZ: `ota_failed` olayı yayınlanır, yeni imaj önyükleme bölümü yapılmaz, cihaz mevcut sürümle çalışmaya devam eder. İmzasız yola geri düşülmez |
| C2 | **Sıra:** ileti cihazın bildiği/hesapladığı değerlerle kurulur (2.3), gömülü genel anahtarla doğrulanır; yalnız doğruysa yeni imaj etkinleştirilir (önyükleme bölümü değiştirilmeden önce) |
| C3 | **Mevcut kontroller aynen sürer:** HTTPS + sabit kök sertifika, URL ön eki, SHA-256, varsayılan olarak yalnız artan sürüm (tek istisna imzayla yetkilendirilmiş izinli düşürmedir: iletide `rollback_max` + manifestte `allow_downgrade: true` + cihazın sürümü `rollback_max` içinde; S5 ve `docs/OTA_IMZA_CIHAZ.md`. İmzalı yetki yoksa cihaz hiçbir düşürmeyi kurmaz), 3 deneme + 10/20/40 dk geri çekilme, röle aktifken ve saat senkron değilken OTA yok, indirme sırasında MQTT oturumunun kapatılması, yeni imaj için 60 sn sağlık sınaması ve geri alma |
| C4 | **Anahtar cihaz yazılımında sabittir:** sunucudan indirilmez, NVS'te tutulmaz, kullanıcı arayüzünden ya da MQTT'den değiştirilemez |
| C5 | **Doğrulayıcı geri alınamaz:** sonraki hiçbir sürümde kaldırılmaz, atlanmaz ya da derleme bayrağıyla kapatılamaz (aksi hâlde köprü etkisiz kalır). Firmware ana makine testi her sürümde imzasız ve yanlış imzalı paket reddini sınamalıdır |
| C6 | **Kapı işlevi etkilenmez:** reddedilen ya da başarısız güncelleme sırasında röle, QR, MQTT ve yerel kontrol çalışır (AGENTS.md kural 3; ESP32-C3 sahada aktif) |
| C7 | **Hedef:** cihaz yalnız kendi hedefi (`OTA_TARGET`) için atılmış imzayı kabul eder |
| C8 | **Yer tutucu anahtar:** genel anahtar henüz yerleştirilmemişse (yer tutucu değerle derlenmiş sürüm) cihaz hiçbir paketi kurmaz (güvenli kapanış). Böyle bir sürüm yayınlanırsa o cihazlar bir daha OTA ile güncellenemez, USB gerekir; bu yüzden yayın öncesi ikilide yer tutucu kalmadığı ve doğru anahtarın gömüldüğü denetlenir (bölüm 7, G0 ve 7.4) |

---

## 7. Geçiş planı: tek köprü sürüm

### 7.1 Sorun

Sahadaki cihazlar imzayı BİLMEZ. Onlara imza denetimini getirecek yazılım da OTA ile gelmek zorundadır ve cihazlar bu yazılımı kendi eski kurallarıyla (HTTPS +
SHA-256 + artan sürüm) kurar. Bu yüzden geçişte bir kez eski güven modeline dayanılır:

- **N:** sahadaki mevcut sürüm (imzayı bilmez).
- **N+1 = köprü sürüm:** genel anahtarı ve doğrulayıcıyı taşıyan İLK sürüm. Eski cihazlar onu eski yolla kurar (imza bilgisini yok sayar). Köprü de araçla imzalanır
  (zincir tek tip kalır, sunucu "yeni paket imzalı olmalı" kuralını ona da uygular), ama imzayı bilmeyen cihazlar için bu imza henüz bir şey ifade etmez.
- **N+2 ve sonrası:** köprüyü çalıştıran cihazlar yalnız geçerli imzalı paket kurar.

Köprü sürüm eski yolla geldiği için geçişin **TEK güven anıdır:** bu yayını güvenli makineden yapın ve her adımda kendi hesapladığınız SHA-256 ile sunucudaki
dosyayı karşılaştırın.

| Cihaz | Bildiği | Kurduğu |
|---|---|---|
| Köprü öncesi (N ve eski) | SHA-256 + artan sürüm | Manifest'in sunduğu daha yüksek her sürümü. Köprüyü kaçıran bir cihaz sonraki imzalı sürümü de bu yolla kurar; her imzalı sürüm doğrulayıcıyı taşıdığı için o da köprü işlevi görür |
| Köprü ve sonrası | + imza | Yalnız geçerli imzalı ve daha yüksek sürüm |
| USB ile yeni yazılan kart | yazılan sürüme bağlı | Yeni kart ve atölye yüklemeleri köprü ya da sonrası sürümle yapılmalıdır (G5) |

### 7.2 Aşamalar

| Aşama | Ne yapılır | Çıkış kriteri |
|---|---|---|
| **G0 Hazırlık** (sahaya dokunmaz) | Anahtar çifti üretilir, yedeklenir, yedekten doğrulanır [kullanıcıda]; `key_id` 3.6'ya yazılır. Genel anahtar firmware'e işlenir (yer tutucu kalmamalı; firmware'in anahtar kontrol betiği ikilide doğru anahtarın gömülü olduğunu doğrular, bkz. `docs/OTA_IMZA_CIHAZ.md`), köprü sürüm HER hedef için ayrı derlenir (boyut 7.3); ana makine testleri geçer. Sunucu yeni kurallarla dağıtılır (AGENTS.md kural 8): canlı `.env`'e `OTA_PUBLIC_KEY` (genel anahtar) yazılır, nginx'te yükleme yolunun gövde sınırı yükseltilir. Mevcut manifest'ler DEĞİŞMEDEN yanıt vermeye devam eder | SAHA 122.1 ve 122.2 yeşil; firmware parmak izi = araç `key_id` |
| **G1 TEST kartı** | Köprü sürüm TEST kartına USB ile yazılır [kullanıcıda]; kart normal çalışır (kapı, MQTT, QR, Wi-Fi). İmzalı bir deneme sürümü (N+2) `allowed_uids` = o kart ile yayınlanır, kurulur. Olumsuz denemeler yapılır | SAHA 122.4 – 122.8 yeşil |
| **G2 Eski yolla köprü** | İmzayı bilmeyen eski firmware'li ikinci TEST kartı; köprü `allowed_uids` = o kart ile yayınlanır; kart köprüyü OTA ile alır, sonra imzalı N+2'yi alır. Eski → köprü → imzalı zinciri uçtan uca kanıtlanır | SAHA 122.3 yeşil; aynı kartta 122.4 |
| **G3 Pilot (ZORUNLU KAPI)** | Her hedef için 1–2 saha cihazı (`allowed_uids`), 2–3 gün izleme; sonra bu cihazlara imzalı N+2 | Pilot cihazlar N+2'yi İMZA DOĞRULAYARAK kurdu ve `ota_validated` geldi (SAHA 122.9). Bu sonuç alınmadan G4'e geçilmez |
| **G4 Yaygın yayın** | `allowed_uids` boşaltılır (manifest son yazılan dosya). Şirket Paneli > Kayıtlı Cihazlar: "Tümüne OTA Kontrolü" (isteğe bağlı; yoksa cihazlar `interval_hours` aralığıyla kendiliğinden kontrol eder) ve ilerleme için "Sürüm Raporu (PDF)" + panelin OTA iş sonuçları. Çevrimdışı cihazlar geldiklerinde alır | Bütün kayıtlı cihazlar köprü ya da daha yeni sürümde; kalanların listesi ve nedeni yazılı (SAHA 122.10) |
| **G5 Kapanış** | İmzasız paket sunumu kapatılır: canlı `.env`'de `OTA_SERVE_UNSIGNED=0` (eski imzasız manifest/ikili dosyalar, yedeği alındıktan sonra, kaldırılabilir). İmzalı canlı yayın imzayı bilmeyen eski cihazlara da sunulmaya devam eder; kapatma yalnız imzasız manifest'leri durdurur. Atölye/fabrika USB yüklemeleri köprü ya da sonrası sürümle yapılır. `OTA_KURULUM.txt` ve bu belge "geçiş tamam" olarak güncellenir | İmzasız yayın artık yapılamıyor (sunucu reddeder, manifest sunmaz) ve köprü sonrası cihazlar kabul etmez |

Tek TEST kartınız varsa sırayı değiştirin: önce G2 (kartı imzayı bilmeyen eski firmware ile USB'den yazın; köprüyü OTA ile alsın, sonra imzalı N+2'yi alsın), ardından
aynı kartta G1'in olumsuz denemelerini yapın. Hedef başına (C3 ve WROOM) ayrı kart gerekir: iki hedef birbirinin yerine denenemez (AGENTS.md kural 4).

### 7.3 Köprü sürüm boyutu

OTA bölümleri `app0`/`app1` 0x1E0000 = 1.966.080 bayttır (`cihaz_kontrol/partitions_ota_4mb.csv`). Eklenen kodla birlikte `firmware.bin` bu sınırın altında kalmalıdır;
sığmazsa OTA ile kurulamaz. Derleme çıktısındaki boyutu G0'da yazın.

### 7.4 Ölümcül hatalar ve önlemleri

| Hata | Sonuç | Önlem |
|---|---|---|
| Gömülü genel anahtar imza makinesindekiyle uyuşmuyor | Köprüyü alan HER cihaz sonraki imzalı sürümleri reddeder; düzeltme USB ile sahaya gidiş demektir | G0'da `key_id` karşılaştırması (araç çıktısı ↔ firmware); G1–G3'te imzalı N+2'nin kurulduğunun kanıtı |
| Doğrulayıcıda yazılım hatası (geçerli imzayı reddediyor) | Aynı | Araçla üretilen test vektörleriyle ana makine testi; G1–G3 |
| Köprü sürüm yer tutucu anahtarla derlenip yayınlandı | Cihaz hiçbir paketi kurmaz (C8); bir daha OTA ile güncellenemez | G0: ikilide yer tutucu kalmadığı ve doğru anahtarın gömüldüğü kontrol edilir; G1'de seri günlükte anahtarın HAZIR olduğu görülür |
| Yükleme ucu çalışmıyor (`OTA_PUBLIC_KEY` yok, nginx gövde sınırı) | Köprü yayınlanamaz; elle kopyalama yoluna kaçılırsa doğrulama atlanır | G0: SAHA 122.2; elle kopyalamaya KAÇMAYIN, ön koşulu düzeltin |
| Doğrulayıcı sonraki bir sürümde sessizce kaldırılmış ya da devre dışı | İmza zorunluluğu kalkar | C5; her sürümde imzasız paket reddi testi |
| Köprü sürüm kapı/röle işlevini bozuyor | Kapı çalışmaz | Mevcut geri alma (60 sn sağlık) ve G1–G3 aşamaları; ESP32-C3 sahada aktif (AGENTS.md kural 3) |
| Köprü paketi boyut sınırını aşıyor | OTA ile kurulamaz | 7.3 |

### 7.5 Vazgeçme

G1–G3'te sorun çıkarsa yayını durdurun (hedefin `manifest.json`'unda `"enabled": false` ya da `allowed_uids`'i daraltın); köprüyü almış cihazlar için düzeltmeyi DAHA
YÜKSEK bir sürüm numarasıyla imzalayıp yayınlayın. Doğrulayıcı hatası yüzünden imzalı güncellemeyi hiç kabul etmeyen cihazlar yalnız USB ile kurtarılır. Köprüyü
almamış cihazlar eski güven modelinde kalır ve etkilenmez.

---

## 8. Anahtar kaybı, sızıntı ve devir

### 8.1 Durumlar

| Durum | Etki | Ne yapılır |
|---|---|---|
| Anahtar bozuldu/silindi ama yedek var | Yok | Yedekten geri yükleyin, deneme imzasını doğrulayın (3.5), nedeni giderin |
| Anahtar kayıp, yedek de yok, sızıntı yok | Yeni imzalı sürüm üretilemez; filo bugünkü sürümde kalır, OTA ile düzeltme/yenileme YOK. (Cihaz iki yuvalıysa ve yedek anahtar elinizdeyse etkisi yoktur: 8.4) | Tek yol: yeni anahtar çifti + yeni genel anahtarlı firmware'in her karta USB ile yazılması (saha ziyareti) |
| Özel anahtar ya da parola sızdı / şüphe var | Sunucuya (ya da TLS/DNS'e) erişebilen herkes filoya yazılım gönderebilir | 8.3 |
| Sunucu ele geçirildi, anahtar güvende | Saldırgan geçerli imza üretemez; hizmeti durdurabilir, eski imzalı paketi sunabilir (bölüm 10) | Sunucuyu ve kimlik bilgilerini temizleyin/döndürün (`BEKLEYEN_ISLER.md` bölüm 6); imzalı paketleri yeniden yükleyin. Cihazlar güvende |
| İmza makinesinde kötü amaçlı yazılım şüphesi | Anahtarı sızmış sayın | 8.3 |

### 8.2 Devir (rotasyon)

Takvimli (örneğin yıllık) devir ÖNERİLMEZ: her devir filo çapında riskli bir işlemdir. Yalnız gerekçe varsa yapılır: anahtar sızdı/şüphe var (8.3), imza makinesi
değişti ya da güvenilmez hâle geldi, yedek geri yükleme provası başarısız oldu ve tek kopya kaldı.

Araç birden çok güvenilen genel anahtarı destekler (`dogrula --genel` tekrarlanabilir; imzadaki `key_id` hangisinin kullanılacağını gösterir); sunucu ise tek `OTA_PUBLIC_KEY` ile
doğrular (en çok 4 anahtarı birlikte güvenebilir; `key_id` hangisinin kullanılacağını seçer), yani sunucudaki `OTA_PUBLIC_KEY` devir anında yeni anahtarı da içerecek biçimde güncellenir (S7). Köprü sürümde
cihazda TEK genel anahtar yuvası vardır (`cihaz_kontrol/include/ota_public_key.h`, `OTA_IMZA_GENEL_ANAHTAR[32]`); iki yuvalı tasarım (8.4) UYGULANMADI, ileride eklenebilecek bir iyileştirmedir.
Bu yüzden bugünkü devir yolu "tek yuvalı cihaz"dır; iki durum ayrı ayrı:

**İki yuvalı cihaz (UYGULANMADI; gelecekte önerilen tasarım, 8.4):**

1. K2 zaten cihazdadır. K2 ile imzalamaya başlayın (yeni firmware gerekmez); sunucudaki `OTA_PUBLIC_KEY` değerini K2 genel anahtarıyla değiştirin.
2. Filo K2 imzalı bir sürüme geçince, K1'i yuvadan çıkaran sürümü K2 ile imzalayıp yayınlayın; boşalan yuvaya yeni bir yedek (K3) konur.
3. Her adımda 7.2'deki pilot kapısı geçerlidir (pilot cihaz yeni anahtarla imzalı sürümü kurmalı).

**Tek yuvalı cihaz (devir sürümü):**

1. Yeni çifti (K2) üretin ve yedekleyin (bölüm 3).
2. Firmware'deki genel anahtarı K2 ile değiştirin, sürümü artırın (devir sürümü R).
3. R'yi ESKİ anahtar K1 ile imzalayın (filo hâlâ K1'e güvenir); pilot (R'den sonra K2 imzalı bir sürümün pilot cihazda kurulması dahil), sonra yaygın yayın.
4. Filo R'ye geçince yeni sürümleri K2 ile imzalayın; sunucudaki `OTA_PUBLIC_KEY` değerini K2 genel anahtarıyla değiştirin (K1 imzalı yüklemeler artık reddedilir).
5. R'ye geçemeyen (uzun süre çevrimdışı) cihazlar hâlâ K1'e güvenir ve K2 imzalı yeni sürümleri reddeder: onlar için R'yi (K1 imzalı) ya da daha yüksek numaralı K1
   imzalı bir kurtarma sürümünü gerektiği süre ayrıca yayınlamanız gerekir. K1'in arşivde tutulması bunun içindir (K1 sızdıysa 8.3).

### 8.3 Sızıntı şüphesinde acil sıra

1. K1 ile imzalamayı DURDURUN.
2. OTA'yı durdurun: her iki hedefin sunucudaki `manifest.json`'unda `"enabled": false` yapın (cihazlar güncelleme indirmez). Doğrulama: `curl` çıktısında
   `enabled: false`. Sunucunun da ele geçirildiğinden şüpheleniyorsanız `server/firmware/<hedef>/` içindeki `.bin` ve `.sig` dosyalarının yedeğini alıp kaldırın.
3. Kapsamı belirleyin: yalnız anahtar mı, sunucu da mı? Sunucuda `server/firmware/` dosya zamanlarına ve SHA-256'larına bakın (yayın günlüğünüzle, bölüm 12,
   karşılaştırın); SSH ve PM2 günlüklerine bakın.
4. İki yuvalı cihazlarda: yedek K2 ile K1'i çıkaran sürümü imzalayıp yayınlayın (8.2). Tek yuvalıda: devir sürümünü (K1 imzalı) HEMEN hazırlayıp yayınlayın. İki durumda
   da OTA'yı yalnız bu paket için yeniden açın (`allowed_uids` ile pilot cihazlardan başlayarak). Saldırgan sunucuya yazamıyorsa yarışı siz kazanırsınız; sunucu da ele
   geçirildiyse kazanamayabilirsiniz ve USB ile sahaya gitmek gerekebilir.
5. Sunucu kimlik bilgilerini döndürün (VPS SSH/sudo, MQTT `api_bridge`, veritabanı, SMTP; bkz. `BEKLEYEN_ISLER.md` bölüm 6) ve olayı yazılı kayda geçirin.

### 8.4 Yedek (ikinci) anahtar yuvası: öneri

Tek anahtarlı tasarımda (köprü sürümün BUGÜNKÜ durumu) anahtar kaybı sahaya gidiş demektir. Önlem (UYGULANMADI, ileride): cihazda İKİ genel anahtar yuvası, K1 (aktif) ve K2 (yedek). K2'nin özel anahtarı K1'den AYRI
bir yerde, çevrimdışı ve şifreli saklanır; normal akışta hiç kullanılmaz. Kayıp ya da sızıntıda K2 ile devir yapılır (8.2). Maliyet: 32 bayt ve küçük bir kod parçası
daha, saklanacak ikinci bir sır. Köprü sürümün cihazında tek yuva vardır (`ota_public_key.h`); **yedek yuva olmadığı için** `BEKLEYEN_ISLER.md` bölüm 7'deki anahtar
yedeği maddesi hayati önemdedir.

---

## 9. Sorun giderme

| Belirti | Olası neden | Ne yapılır |
|---|---|---|
| `imzala`: "imza URETILMEDI" ve imaj/hedef uyumsuzluğu | Yanlış `--hedef` ya da başka hedefin `.bin`'i | Doğru ortamda derlenmiş `.bin`'i ve doğru `--hedef`'i kullanın |
| `imzala`: UYARI "surum metni … imajin icinde bulunamadi" | `ota_guncelleme.h` sürümü artırılmadan derlenmiş ya da eski `.bin` verilmiş | DURUN. Sürümü artırıp yeniden derleyin; aksi hâlde cihaz güncellemeden sonra aynı sürümü tekrar tekrar indirir |
| `dogrula`: `SONUC: GECMEDI`, "boyut" ya da "sha256" HATA | `.bin` imzadan sonra değişti / başka derleme; `.sig` başka dosyaya ait | `.bin`'i yeniden imzalayın; aynı derlemenin `.sig`'ini kullanın |
| `dogrula`: "anahtar kimligi" HATA | `.sig` başka anahtarla atılmış ya da verilen genel anahtar yanlış | `key_id` değerlerini karşılaştırın (3.6); doğru `--genel`'i verin |
| Yükleme 400 `FIRMWARE_SIGNATURE_REQUIRED` / `FIRMWARE_SIGNATURE_MALFORMED` / `FIRMWARE_SIGNATURE_MISMATCH` / `FIRMWARE_SIGNATURE_INVALID` / `FIRMWARE_SIGNATURE_KEY_UNKNOWN` | `X-Ota-Signature` yok / `.sig` ya da çıplak imza biçimi bozuk / `.sig` alanları yüklenen paketle (hedef, sürüm, boyut, SHA-256, `rollback_max`) uyuşmuyor / imza `OTA_PUBLIC_KEY` ile eşleşmiyor / imzadaki `key_id` sunucudaki anahtarlar arasında yok | Başlıktaki değer `.sig` dosyasının base64'ü mü (çıplak imza ise `version` verildi mi); `--hedef` ve `--surum` yüklemedeki `<hedef>` ve `.sig`'teki sürümle AYNI mı; `.bin` imzadan sonra değişmedi mi; sunucudaki genel anahtarın `key_id` değeri imza makinesindekiyle aynı mı |
| Yükleme 400 `FIRMWARE_ROLLBACK_NOT_ALLOWED` / `FIRMWARE_ROLLBACK_NOT_DOWNGRADE` / `FIRMWARE_ROLLBACK_INVALID` | `.sig` `rollback_max` taşıyor ama `allow_downgrade=1` yok / yükleme yayındaki sürümden düşük değil / `rollback_max` paket sürümünden büyük değil | Normal yayın için `--rollback-max` KULLANMAYIN; gerçekten düşürme isteniyorsa S5 |
| Yükleme 409 `FIRMWARE_DOWNGRADE_REJECTED` | Yayındaki sürümden düşük sürüm | Sürümü artırın; gerçekten geri çekilecekse `allow_downgrade=1` + `downgrade_reason` (S5) |
| Yükleme 409 `FIRMWARE_VERSION_EXISTS` | Aynı sürüm numarası farklı içerikle zaten yayınlanmış | Sürümü artırıp yeniden derleyin ve imzalayın |
| Yükleme 400 `FIRMWARE_TARGET_MISMATCH` | `.bin` başka hedefin derlemesi (imaj başlığındaki yonga kimliği uyuşmuyor) | Doğru ortamda derlenmiş `.bin` ve doğru `<hedef>` |
| Yükleme 503 `OTA_KEY_NOT_CONFIGURED` / `OTA_KEY_INVALID` | Sunucuda `OTA_PUBLIC_KEY` yok ya da bozuk | Canlı `.env`'e GENEL anahtarı yazın (özel anahtar reddedilir) |
| Yükleme 413 (nginx) / `FIRMWARE_TOO_LARGE` | nginx gövde sınırı düşük ya da imaj `OTA_MAX_FIRMWARE_BYTES` üstünde | nginx sınırını yükseltin; imaj bölüm sınırını (1.966.080 bayt) aşıyorsa küçültün |
| Yükleme başarılı ama manifest'te imza alanları yok / cihazlar paketi almıyor | Manifest elle yazılmış eski (imzasız) paketten geliyor; `enabled: false`; `allowed_uids` listesinde değil | `GET /admin/firmware/<hedef>/releases` ile canlı yayına bakın; `curl` ile manifest'i okuyun |
| Cihaz `ota_failed` (neden imza) | Gömülü genel anahtar ≠ imza makinesindeki; manifest `version` ≠ imzalanan sürüm; `.bin` ≠ imzalanan | `key_id` değerlerini karşılaştırın; manifest değerlerini araç çıktısından BİREBİR yazın; `dogrula` ile yeniden doğrulayın |
| Cihaz hiç güncellemiyor (hata da yok) | `allowed_uids` listesinde değil; sürüm yükseltilmemiş (cihaz yalnız ARTAN sürümü kurar); 3 deneme hakkı bitti | `OTA_KURULUM.txt` "Notlar"; "Tümüne OTA Kontrolü" ya da MQTT `{"action":"ota_check","retry":true}` deneme sayacını sıfırlar |
| Köprüyü almış cihaz imzalı sürümü kurmuyor | G3 kapısı atlandı ya da anahtar uyuşmazlığı | 7.4 ve 7.5 |

---

## 10. Bilinen sınırlar

- **Secure Boot ve flaş şifreleme YOK:** USB ile (fiziksel erişimle) cihaza yazabilen biri imzayı atlayabilir; gömülü genel anahtar da fiziksel erişimle değiştirilebilir.
  Bu belge UZAKTAN (ağ/sunucu) saldırıyı kapatır.
- **İmzaların son kullanma tarihi yoktur** (imza saate bağlı değildir): eski ama geçerli imzalı bir sürüm, o sürümden DAHA ESKİ çalışan cihazlara (sunucuyu ele geçiren
  biri tarafından) sunulabilir. Sürüm iletide olduğu için daha yeni sürümdeki cihazlar etkilenmez. Bilinen açıklı bir sürüm için çare, onu atlatan yeni bir sürüm
  yayınlamaktır; kritik durumda anahtar devri (8.2).
- **Hizmet engelleme:** sunucuyu ele geçiren OTA'yı durdurabilir ya da cihazların güncelleme almasını geciktirebilir; imza bunu engellemez.
- **Köprü sürüm tek güven anıdır** (7.1); köprüyü almamış cihazlar eski güven modelinde kalır.
- **Kapsam:** yalnız `esp32-c3` ve `esp32-wroom` OTA yolu. Ekran yazılımı (`ekran_yazilimi`) OTA almaz, USB ile yüklenir. Mobil uygulama (APK/mağaza) ayrı imza
  zinciridir (`docs/YAYIN_HAZIRLIGI.md` bölüm 3).

---

## 11. İlgili dosyalar

- `OTA_KURULUM.txt`: mevcut OTA akışı, manifest alanları, geri alma.
- `tools/ota_imza/` ve `tools/ota_imza/README.md`: anahtar üretimi, imzalama, doğrulama; imza biçiminin tek tanımı.
- Cihaz tarafı: `docs/OTA_IMZA_CIHAZ.md`, `cihaz_kontrol/include/ota_guncelleme.h`, `ota_imza.h`, `ota_public_key.h` (genel anahtar yer tutucusu ve yerleştirme / kontrol adımları).
- Sunucu tarafı: `server/src/routes/firmware_admin_routes.js` (yükleme ucu), `firmware_routes.js` (cihaza sunum), `server/src/services/ota_signature.js`,
  `firmware_release_service.js`, `server/.env.example` (Firmware (OTA) bölümü: `OTA_PUBLIC_KEY`, `OTA_SERVE_UNSIGNED`, `OTA_MAX_FIRMWARE_BYTES`).
- `SAHA_KONTROL_LISTESI.md` bölüm 122 (imza denemeleri), bölüm 44 ve 51 (mevcut OTA maddeleri).
- `BEKLEYEN_ISLER.md` bölüm 7: kullanıcıya düşen işler.
- `docs/YAYIN_HAZIRLIGI.md` bölüm 3: Android yükleme anahtarı (aynı depo-dışı anahtar kuralı).
- `docs/OPERASYON_YEDEK_IZLEME.md`: firmware arşivi (`kapi_firmware_*.tgz.enc`); `.sig` dosyaları buna girer, özel anahtar ASLA.
- `AGENTS.md` kural 2, 3, 4 ve 8.

---

## 12. Yayın günlüğü

Her imzalı yayında bir satır ekleyin (sır içermez; SHA-256 ve `key_id` herkese açık bilgidir). Sızıntı anında sunucudaki dosyalarla karşılaştırmak için kullanılır (8.3).

| Tarih | Hedef | Sürüm | SHA-256 (`firmware.bin`) | `key_id` | Kapsam | Sonuç |
|---|---|---|---|---|---|---|
| (henüz imzalı yayın yok) | | | | | | |
