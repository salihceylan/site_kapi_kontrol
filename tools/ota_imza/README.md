# OTA imza aracı (`tools/ota_imza`)

`firmware.bin` dosyalarını **Ed25519** ile imzalayan ve imzayı doğrulayan küçük komut satırı aracı. Amaç: cihaza giden güncellemenin
**sunucudan bağımsız** olarak kanıtlanabilir biçimde bizden çıktığını göstermek. Bugün cihaz, manifestteki SHA-256 ile indirdiği dosyanın
özetini karşılaştırır; manifesti ve dosyayı aynı sunucu sunduğu için sunucuya (ya da yönetici hesabına) giren biri ikisini birlikte
değiştirip tüm cihazlara kendi firmware'ini yollayabilir. İmza ile cihaz, **yalnızca özel anahtarın sahibinin** imzaladığı paketi yazar;
özel anahtar sunucuda hiç bulunmaz, firmware'e yalnızca **genel anahtar** gömülür.

- Bağımlılık **yok**: yalnızca Node.js yerleşik `crypto` (Node 20+ gerekir; Node 24.15 ile doğrulandı). `npm install` gerekmez, `server/` bağımlılıklarına dokunmaz.
- Özel anahtar **asla depoya, loga ya da teste girmez**: araç özel anahtarı yalnızca sizin verdiğiniz **depo dışı** bir yola yazar/oradan okur (aşağıya bakın).
- Kart yazma / saha denemesi bu aracın işi değildir; araç yalnızca imzayı üretir ve denetler.

## Hızlı akış: anahtar üret → derle → imzala → doğrula → sunucuya yükle

```bash
# 1) BİR KEZ: anahtar çifti üret. Özel anahtar depo DIŞINDA bir yola yazılır (yol vermezseniz araç reddeder; varsayılan yol YOKTUR).
#    Özel anahtarı parolalı üretmek için önce OTA_IMZA_PAROLA ortam değişkenini tanımlayın (en az 8 karakter; komut satırında parola verilmez).
node tools/ota_imza/ota_imza.mjs anahtar-uret --ozel D:\anahtarlar\ota_imza_ozel.pem
#    -> ekrana GENEL anahtar basılır (PEM, hex, key_id, firmware için C++ tanımı). Özel anahtarı hemen YEDEKLEYİN (aşağıya bakın).

# 2) Önce sürümü artır: cihaz_kontrol/include/ota_guncelleme.h -> OTA_VERSION_C3 / OTA_VERSION_WROOM; sonra derle.
#    firmware.bin çıktısının yolu PlatformIO yapılandırmasına göre değişir (genellikle cihaz_kontrol/.pio/build/<ortam>/firmware.bin).
pio run -e lolin_c3_mini            # ESP32-C3
pio run -e esp32_relay_wroom        # ESP32-WROOM

# 3) İmzala (yanına firmware.bin.sig yazılır; firmware.bin DEĞİŞMEZ).
node tools/ota_imza/ota_imza.mjs imzala cihaz_kontrol/.pio/build/lolin_c3_mini/firmware.bin --hedef esp32-c3 --surum 4.3.4 --ozel D:\anahtarlar\ota_imza_ozel.pem
#    -> manifest.json için "target", "version" ve "sha256" değerleri de ekrana basılır; manifestte BİREBİR aynı yazılmalıdır.

# 4) Yüklemeden ÖNCE genel anahtarla doğrula (manifest ile imzanın uyuştuğunu da denetler).
node tools/ota_imza/ota_imza.mjs dogrula cihaz_kontrol/.pio/build/lolin_c3_mini/firmware.bin --genel genel_anahtar.pem --manifest manifest.json

# 5) Sunucuya yükle: POST /admin/firmware/<hedef>/releases (yalnız süper kullanıcı; gövde firmware.bin, başlık X-Ota-Signature = firmware.bin.sig'in base64'ü).
#    Sunucu imzayı OTA_PUBLIC_KEY ile doğrular, dosyaları kendisi yazar, manifest.json'u EN SON değiştirir; elle klasöre kopyalamayın (doğrulamayı atlar).
#    Komut örneği (PowerShell), hata kodları ve geçiş planı: docs/OTA_IMZA.md bölüm 4. İki donanım hedefinin dosyaları ASLA karışmaz (esp32-c3 <-> esp32-wroom).
```

Her komutun sonunda çıkış kodu: `0` başarılı / **GEÇTİ**, `1` reddedildi / **GEÇMEDİ**, `2` komut satırı hatası.
Özel anahtar yolu `--ozel` yerine `OTA_IMZA_OZEL_ANAHTAR` ortam değişkeniyle de verilebilir (aşağıdaki tablo).
Ortam dosyası ile: `node --env-file=tools/ota_imza/.env tools/ota_imza/ota_imza.mjs imzala ...` (`.env.example` yalnızca **adları** içerir; `.env` git'e girmez).

## Komutlar

| Komut | Ne yapar |
| --- | --- |
| `anahtar-uret --ozel <yol> [--genel <dosya>]` | Yeni Ed25519 çifti üretir. Özel anahtar PKCS#8 PEM olarak **yeni** bir dosyaya yazılır (0600; var olan dosyanın üzerine **asla** yazılmaz). Genel anahtar ekrana (PEM, hex, `key_id`, C++ tanımı) basılır; `--genel` verilirse ayrıca PEM dosyasına yazılır. Yazılan anahtar diskten geri okunup deneme imzasıyla sınanır; sınanamazsa dosya silinir. |
| `genel-anahtar --ozel <yol>` | Özel anahtardan genel anahtarı yeniden üretip basar (firmware'e gömülecek değeri kaybettiyseniz). |
| `imzala <firmware.bin> --hedef <esp32-c3\|esp32-wroom> --surum <X.Y.Z> [--rollback-max <X.Y.Z>] [--ozel <yol>] [--cikti <yol>]` | `<firmware.bin>.sig` (ya da `--cikti`) dosyasını üretir. Üretilen imza hemen genel anahtarla yeniden doğrulanır; geçmezse dosya **yazılmaz**. `--rollback-max` YALNIZ bilinçli, sınırlı sürüm düşürmede kullanılır (aşağıda); normal yayında KULLANMAYIN. |
| `dogrula <firmware.bin> (--genel <dosya> \| --genel-hex <64 hane>) [--sig <yol>] [--manifest <manifest.json>] [--hedef <ad>] [--surum <X.Y.Z>]` | Dosya + imza + genel anahtarı denetler, her kontrolü `[TAMAM]` / `[HATA ]` / `[UYARI]` olarak yazar, sonda `SONUC: GECTI` ya da `GECMEDI` der. `--genel` / `--genel-hex` birden fazla verilebilir (anahtar dönüşü). |
| `yardim` | Kısa kullanım. |

| Ortam değişkeni | Anlamı |
| --- | --- |
| `OTA_IMZA_OZEL_ANAHTAR` | Özel anahtar **dosyasının yolu** (içeriği değil). `--ozel` verilirse o kullanılır. İkisi de yoksa araç **reddeder**. |
| `OTA_IMZA_PAROLA` | Özel anahtar dosyasının parolası. `anahtar-uret` sırasında tanımlıysa anahtar PKCS#8 AES-256-CBC ile şifreli yazılır; `imzala` / `genel-anahtar` şifreli anahtarı açmak için aynı değişkeni ister. **Komut satırı parolası kabul edilmez** (kabuk geçmişine düşer). |

İmzalamadan önce araç şunları **zorunlu** denetler (biri başarısızsa imza dosyası üretilmez):

- `--hedef` bilinen bir hedef olmalı (`esp32-c3`, `esp32-wroom`); `--surum` `X.Y.Z` (ya da `X.Y.Z.W`) biçiminde, başında sıfır olmadan. `--rollback-max` verilirse aynı biçimde ve `--surum`'dan **büyük** olmalı (aksi halde hiçbir cihaz düşürülemez; imza üretilmez).
- Dosya gerçek bir ESP32 uygulama imajı olmalı (ilk bayt `0xE9`, segment sayısı 1–16) ve **derlendiği çip `--hedef` ile uyuşmalı**
  (imaj başlığındaki `chip_id`: ESP32/WROOM-32E `0x0000`, ESP32-C3 `0x0005`). C3 imajını yanlışlıkla `esp32-wroom` diye imzalamak mümkün değildir.
- Dosya boş olamaz ve 16 MiB'ı aşamaz.
- Özel anahtar yolu bir **git deposunun / bu projenin klasörünün içinde olamaz** (sembolik bağlantı ve `..` ile dolaşma çözülerek bakılır).
- İmza dosyası yolu (`<firmware.bin>.sig` ya da `--cikti`) yalnızca **yoksa ya da zaten geçerli bir önceki imza dosyasıysa** üzerine yazılır; başka her var olan dosya
  (`firmware.bin`, özel anahtar, `manifest.json`, klasör ...) reddedilir. Yanlış yazılmış bir `--cikti` bunları ezemez. Yazma geçici dosya + yeniden adlandırma ile yapılır (yarım `.sig` kalmaz).

Ek olarak şu **uyarı** (imzayı engellemez) verilir: `--surum` metni imajın içinde NUL sonlu dize olarak bulunamazsa, `ota_guncelleme.h` içindeki
`OTA_VERSION_*` artırılmadan derlenmiş ya da başka bir derlemenin `.bin` dosyası verilmiş olabilir (cihaz güncellemeden sonra aynı sürümü tekrar tekrar
indirmeye çalışırdı). Sezgi, `cihaz_kontrol/firmware_releases` arşivindeki gerçek imajların tamamında (2026-10-28'de 41 imaj) doğru çalışır.

## İmza biçimi: `KAPI-OTA-IMZA-V1`

> Bu bölüm **firmware (C++) ve sunucu (Node) için bağlayıcı tanımdır.** Referans uygulama: `lib/bicim.mjs`; bilinen-cevap vektörleri: `test/vektorler.json`.

### Neden ayrık dosya (`firmware.bin.sig`), neden bin'in sonuna blok yok

İmza, `firmware.bin` dosyasının **yanında** ayrı bir JSON dosyasıdır. `.bin` PlatformIO'nun ürettiği haliyle kalır; çünkü
(1) manifestteki `sha256` (`sha256sum firmware.bin`) ve `x-MD5` değişmez, (2) sahadaki imzayı bilmeyen cihazlar aynı dosyayı bugünkü gibi indirip yazmaya devam eder
(AGENTS.md kural 2: geriye uyumluluk), (3) cihaz akışı imza bloğunu ayrıştırmak zorunda kalmaz, akışlı SHA-256 + `Update` mantığı aynı kalır.

### İmzalanan mesaj

Ed25519, `firmware.bin`'in kendisini değil, onu bağlayan **kısa bir mesajı** imzalar (cihaz 1,8 MB'yi RAM'e alamaz; zaten akışlı SHA-256 hesaplar). Saf Ed25519 (RFC 8032) kullanılır;
`Ed25519ph` değil. Mesaj, ASCII, satır sonları **LF (`0x0A`)**, sabit sırada:

```text
KAPI-OTA-IMZA-V1<LF>
target=<hedef><LF>
version=<sürüm><LF>
size=<bayt sayısı><LF>
sha256=<64 hane küçük harfli hex><LF>
rollback_max=<sürüm><LF>          <- YALNIZ imzalı, sınırlı sürüm düşürme yetkisinde (imzala --rollback-max); yoksa bu satır HİÇ olmaz
```

| Alan | Kural |
| --- | --- |
| `target` | `esp32-c3` ya da `esp32-wroom` (tam bu yazım). Cihazda derleme sabiti `OTA_TARGET`. |
| `version` | `X.Y.Z` ya da `X.Y.Z.W`, her parça 0–9999, **başında sıfır yok** (`4.3.4` evet; `v4.3.4`, `4.03.4`, `4.3`, `4.3.4-beta` hayır). Manifestteki `version` ile **harfi harfine** aynı olmalı. |
| `size` | İmajın bayt sayısı, ondalık, işaretsiz, başında sıfır/boşluk yok (1 – 16 777 216). |
| `sha256` | İmajın tamamının SHA-256 özeti, **küçük harfli** hex, 64 hane. |
| `rollback_max` | **İsteğe bağlı**, son satır: `version` biçiminde bir sürüm, `version`'dan büyük. Varsa imza bir **sürüm düşürme yetkisi** taşır: cihazın sürümü `rollback_max`'a kadar (dahil) olan cihazlar bu paketi, sürümleri `version`'dan yüksek olsa da kurabilir (cihaz kuralı: manifestte `allow_downgrade: true` + aynı `rollback_max`). Yoksa satır hiç bulunmaz ve imza hiçbir düşürmeyi yetkilendirmez (varsayılan). |

Mesajda CR, fazladan boşluk, ek satır yoktur; son satır da LF ile biter. Alanlar yukarıdaki desenlerle kısıtlı olduğu için satır/alan enjeksiyonu mümkün değildir.
Örnek (değerler yer tutucu): `KAPI-OTA-IMZA-V1\ntarget=esp32-c3\nversion=4.3.4\nsize=1234567\nsha256=<64 hane>\n`; düşürme yetkisiyle: sonuna `rollback_max=4.3.9\n` eklenir.
**Tek etiket:** `KAPI-OTA-IMZA-V1`. Cihaz yazılımı taslağında geçen eski `SKP-OTA-V1` etiketi KALDIRILDI; araç, sunucu ve cihaz yalnız bunu bilir.

İmza şu dörtlüyü birbirine bağlar: **hedef** (bir C3 paketi WROOM'a yazılamaz), **sürüm** (eski bir imzalı imaj yeni sürüm numarasıyla yayınlanamaz),
**boyut** ve **içerik özeti** (düşürme yetkisinde ayrıca **`rollback_max`**). Ed25519 deterministiktir: aynı anahtar + aynı mesaj her zaman aynı imzayı verir.

**Sürüm düşürme yetkisi (`--rollback-max`) neden imzanın İÇİNDE?** Varsayılan olarak cihaz yalnız ARTAN sürümü kurar. Bilinçli bir düşürme gerekirse yetki sunucuda ya da manifestte değil
imzada durur: ele geçirilmiş bir sunucu "izin var" dese de imzalanmamış bir düşürmeyi yaptıramaz ve sahibin imzaladığı izin `rollback_max` ile sınırlıdır. Cihaz `rollback_max` satırını
yükü YALNIZ düşürme modunda (manifest sürümü cihazınkinden eski + `allow_downgrade: true`) kurar; yükseltmede 5 satırlı yükü kurar. Bu yüzden `rollback_max`'lı imza yalnız düşürme için
doğrulanır (sürümü paketin altındaki cihaz bu paketi yükseltme olarak kuramaz; sunucu ona sunmaz). Güvenli ve basit geri dönüş genellikle ESKİ KODU DAHA YÜKSEK SÜRÜM NUMARASIYLA yeniden
derleyip normal imzalamaktır; `--rollback-max` yalnız bunun mümkün olmadığı durumlar içindir. İmzalı düşürme paketi süresizdir, bu yüzden `rollback_max` olabildiğince dar seçilmelidir.

### `.sig` dosyası

```json
{
  "format": "KAPI-OTA-IMZA-V1",
  "algorithm": "Ed25519",
  "target": "esp32-c3",
  "version": "4.3.4",
  "size": 1234567,
  "sha256": "<64 hane küçük harfli hex>",
  "key_id": "<16 hane küçük harfli hex>",
  "signature": "<128 hane küçük harfli hex: 64 baytlık Ed25519 imzası>"
}
```

Düşürme yetkili imzada `"rollback_max": "<sürüm>"` alanı `sha256` ile `key_id` arasına eklenir (yoksa alan hiç yazılmaz).
- Alan adları `manifest.json` ile uyumlu İngilizcedir (`version`, `sha256`, `target`); "sürüm / özet / imza" = `version` / `sha256` / `signature`.
- `key_id` = ham 32 baytlık genel anahtarın SHA-256'sının **ilk 8 baytının hex'i**. Yalnızca bir **ipucudur** (anahtar dönüşünde doğru genel anahtarı seçmek için); imzalanan mesajın parçası değildir ve güvenlik kararı vermez.
- UTF-8, 2 boşluk girinti, sonda LF. Bilinmeyen ek alanlar yok sayılır (ileriye uyum); bilinen alanların her biri sıkı denetlenir (küçük harf, uzunluk, tür).
- Sunucu imzayı cihaza manifestte `signature` alanı olarak da iletir; değeri `.sig` içindeki `signature` ile **aynıdır** (128 hane hex) ve cihaz öncelikle onu kullanır. `.sig` dosyasını sunucu da
  `GET /firmware/<hedef>/<imaj>.bin.sig` ile sunar; cihaz (manifestte `signature` yoksa) bu JSON'dan yalnız `format` / `algorithm` / `signature` alanlarını okur ve yükü kendi değerlerinden kurar.

### Cihaz (firmware) için doğrulama adımları

Cihaz mesajı **kendi bildiği / hesapladığı** değerlerle yeniden kurar; sunucudan yalnızca `version` ve `signature` gelir:

1. `T` = derleme sabiti `OTA_TARGET` (manifesttekine **güvenilmez**), `N` = indirilen gerçek bayt sayısı, `H` = indirme sırasında akışlı hesaplanan SHA-256 (küçük harfli hex), `V` = manifestin `version` dizesi (aynen).
2. `M = "KAPI-OTA-IMZA-V1\ntarget=" + T + "\nversion=" + V + "\nsize=" + N + "\nsha256=" + H + "\n"` (YALNIZ izinli düşürme modunda sonuna `"rollback_max=" + R + "\n"` eklenir; `R` = manifestin `rollback_max` değeri)
3. `signature` 128 hanelik hex'ten 64 bayta çevrilir; yanlış uzunluk/karakter = **red**.
4. `Ed25519_doğrula(imza, M, GÖMÜLÜ_GENEL_ANAHTAR)` doğruysa devam; değilse `Update.abort()`, `ota_failed` olayı, boot bölümü **değişmez**.
5. Bu doğrulama **`Update.end()` çağrılmadan ÖNCE** yapılmalıdır (şu anki `sha256 uyusmuyor` kontrolüyle aynı yer): boot bölümü, imza geçmeden asla değişmemeli.
6. Mevcut kurallar aynen kalır: sürüm yalnızca artar (`V > OTA_CURRENT_VERSION`; tek istisna imzalı `rollback_max` yetkisiyle düşürme), indirme adresi izinli sunucuya aittir, hedef uyuşmalıdır.

Genel anahtar firmware'e `cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar.pem>` ile (ya da `anahtar-uret` / `genel-anahtar` çıktısındaki C++ tanımıyla) gömülür (`OTA_IMZA_GENEL_ANAHTAR[32]`);
yayın öncesi `ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar.pem>` yer tutucunun kalmadığını denetler. Cihazda TEK anahtar yuvası vardır (iki anahtarlı tasarım uygulanmadı; anahtar dönüşü aşağıda).
Cihaz tarafında mbedTLS Ed25519 imza doğrulaması sunmaz; cihaz kodu gömülü bir TweetNaCl uyarlaması kullanır (`docs/OTA_IMZA_CIHAZ.md`) ve bu aracın `test/vektorler.json` dosyasındaki bilinen-cevap vektörlerini
(`rollback_vektoru` dahil) her ana makine testinde doğrular.

### Sunucu için

Yüklemede aynı doğrulama yapılır (`server/src/services/ota_signature.js`, `firmware_release_service.js`): `.sig` ayrıştırılır (sıkı), `sha256` / `size` yüklenen dosyadan **yeniden hesaplanır**, `key_id` kayıtlı genel
anahtarla eşleşmeli, mesaj yukarıdaki gibi kurulup Node `crypto.verify(null, mesaj, genelAnahtar, imza)` ile doğrulanır; sunucu `.sig`'i KANONİK biçimde (bu aracın ürettiğiyle bayt-bayt aynı) diske yazar. Manifestteki
`version` / `sha256` / `target` (ve varsa `rollback_max`), `.sig` ile birebir aynı olmalıdır (`dogrula --manifest` bu denetimi yapar). Sunucuda yalnızca **genel** anahtar bulunur.

### Test vektörleri (`test/vektorler.json`)

Yalnızca **açık** veri içerir: genel anahtar, mesaj, imza (özel anahtar yoktur; vektörler atılabilir anahtarlarla üretilip anahtarlar atıldı; dosya "URETIMDE KULLANILMAZ" başlığı taşır).
`vektorler` iki normal vektördür (her hedef için bir); `rollback_vektoru` ayrı bir atılabilir anahtarla üretilmiş, `rollback_max` satırlı tek vektördür.
Her vektörün imajı `bayt[i] = (i * 31 + 7) mod 256` formülüyle (sonra `bayt[0]=0xE9`, `bayt[1]=0x05`, `bayt[12..13]=chip_id`) yeniden üretilebilir; firmware ve sunucu testleri
SHA-256'yı hesaplayıp mesajı kurar ve imzayı doğrulayarak kendi uygulamalarını bu araçla çapraz sınar.

## Özel anahtar saklama uyarısı

**Özel anahtar, sahadaki tüm cihazların güvenlik kökü olarak düşünülmelidir.** Ele geçiren, sunucuya erişebildiği anda tüm cihazlara kendi firmware'ini yollayabilir.

Yapılmayacaklar (hiçbir koşulda):

- Depoya, **git geçmişine**, `server/` klasörüne, `.env` dosyalarına **değer olarak**, e-postaya, sohbete, ekran görüntüsüne koymak.
- Sunucuya (VPS), CI'ya, ortak bir klasöre ya da bulut eşitlemeli klasöre (OneDrive / Google Drive / Dropbox) koymak.
- Komut satırında parola vermek, parolayı ya da anahtarı günlüklere yazmak.

Yapılacaklar:

- Aracın zorunlu kıldığı gibi **depo dışında** tutun; tercihen şifreli bir diskte ya da çevrimdışı bir USB bellekte. İmzalama yalnızca bu anahtarın bulunduğu bilgisayarda yapılır.
- Anahtarı **parolalı** üretin (`OTA_IMZA_PAROLA`; uzun, rastgele, parola yöneticisinde). Parola ve anahtar dosyası aynı yerde durmasın. PKCS#8 şifrelemesi OpenSSL varsayılanlarını kullanır; zayıf parola çevrimdışı denemeye karşı koruma sağlamaz.
- Linux/macOS'ta dosya izni `0600` olarak oluşur. **Windows'ta izinler otomatik kısıtlanmaz**; `anahtar-uret` çıktısındaki komutla dosyayı yalnızca kendi hesabınıza açın:
  `icacls "<yol>" /inheritance:r /grant:r "<kullanıcı adınız>:F"`.
- Dosya izinleri gevşekse (`group/other` okuyabiliyorsa) `imzala` uyarı verir.

### Yedekleme notu

- Özel anahtar dosyasını **en az iki ayrı güvenli yere** yedekleyin (şifreli USB bellek, parola yöneticisi kasası, kasa). Yedeğin parolası anahtardan **ayrı** saklanır.
- **Anahtar kaybolursa** sahadaki imza doğrulayan cihazlara bir daha imzalı OTA gönderilemez: yeni genel anahtar gömülü firmware'i her karta **USB ile** yazmak gerekir. Bu yüzden yedek şarttır.
- **Anahtar sızarsa** (ya da şüphe varsa) sunucu erişimi olan saldırgan cihazlara zararlı paket yollayabilir. Önlem olarak ikinci bir anahtar çifti üretip **yalnızca genel anahtarını** ilk imzalı
  firmware'lere birincil anahtarla birlikte gömün, özel anahtarını çevrimdışı saklayın; sızıntıda yedek anahtarla imzalanmış "anahtar dönüşü" sürümü yayınlanır. Yedek yoksa tek çare USB'dir.
- Anahtar dönüşü planı: yeni çift `anahtar-uret` ile üretilir; yeni genel anahtar **eski anahtarla imzalanmış** bir sürümle cihazlara iletilir; ardından yeni anahtarla imzalamaya geçilir (`dogrula --genel A --genel B` ile iki anahtar birlikte sınanır).

## Güvenlik özellikleri ve sınırları

Sağladıkları:

- Firmware yukarıdaki doğrulamayı uyguladığında, sunucu ya da yönetici hesabı ele geçse bile **özel anahtar olmadan** cihazın kabul edeceği paket üretilemez (cihaz imzasız / yanlış imzalı paketi yazmaz). Bu araç yalnızca imzayı üretir ve denetler; cihaz tarafındaki zorunluluk firmware işidir.
- Hedef, sürüm, boyut ve özet imzaya bağlıdır: başka hedefe, başka sürüm etiketiyle ya da değiştirilmiş içerikle yeniden oynatma reddedilir.
- Tek bit değişen `.bin`, tek hane değişen imza, değiştirilmiş `.sig` alanı (sürüm, hedef, boyut, özet, `key_id`) ve başka anahtarın imzası **reddedilir** (testlerle sınanır).
- Özel anahtar yalnızca depo dışı yoldan okunur/yazılır; var olan anahtar ezilmez; hiçbir çıktıda özel anahtar ya da parola görünmez (testlerle sınanır).

Kapsam dışı / bilinen sınırlar:

- **Eski ama geçerli imzalı** bir sürüm, kendisinden daha eski bir cihaza yeniden sunulabilir (cihaz yalnızca `V > mevcut` kuralını uygular). Güvenlik açığı olan bir sürümün imzası geçerli kalır; çare cihazları güncel tutmak ya da anahtarı döndürmektir.
- **`--rollback-max` imzalı düşürme paketi süresizdir:** sahibin attığı imza geçerli kaldığı sürece, sürümü `rollback_max`'a kadar olan her cihaza (sunucuyu ele geçiren biri tarafından) yeniden sunulabilir. `rollback_max` düşürme gerektiren en yeni sürüm olarak DAR seçilmeli, düşürmeden sonra filo hızla üstüne yükseltilmeli; mümkünse hiç kullanılmamalıdır.
- İmza **kaynağı** kanıtlar, **kalitesini** değil: hatalı ama imzalı firmware yine yüklenir (rollback ve sağlık kontrolü ayrıca çalışır).
- Aracın ESP32 başlık denetimi bir kolaylık/çapraz kontroldür, güvenlik sınırı değildir; güvenlik sınırı cihazdaki imza doğrulamasıdır.
- Ed25519'un kuantum sonrası güvenliği yoktur (burada gerçekçi bir tehdit değildir).

## Geçiş notu (sahadaki cihazlar)

Bugünkü sahadaki sürümler imzayı doğrulamaz (yalnızca `sha256`). Plan (`docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md`, Dalga F): imza doğrulamayı **ilk kez** içeren sürüm
(köprü sürüm: ESP32-C3 4.4.0, ESP32-WROOM 5.3.0) da bu araçla imzalanıp yayınlanır; eski cihazlar `signature` alanını yok sayarak onu yine sha256 ile yazar, köprü sürümü çalışan cihazlar ise bundan sonra imzasız paketi reddeder.
Köprü sürümü cihaza ulaşmadan **imza zorunlu hale getirilmemeli** (sunucuda `OTA_SERVE_UNSIGNED=0` en son adımdır); ayrıntılar `docs/OTA_IMZA.md` ve `docs/OTA_IMZA_CIHAZ.md` belgelerindedir. Kart yazma ve saha denemesi kullanıcıdadır.

## Testler

```bash
node --test "tools/ota_imza/test/*.test.mjs"        # Node 22+ (glob); Node 20.x'te dizin biçimi: node --test tools/ota_imza/test/  (yalnız Node 24.15 ile denendi)
```

Testler anahtarı **çalışma anında, geçici klasörde** üretir ve bitince siler; depoda sabit özel anahtar, PEM ya da tohum yoktur
(`vektorler.json` yalnızca açık veri taşır). Kapsam: format ve katı ayrıştırma (`bicim`), anahtar üretimi ve depo-içi koruma (`anahtar`), üret → imzala → doğrula
döngüsü ve **bozuk bin / bozuk imza / değiştirilmiş `.sig` / yanlış anahtar / yeniden oynatma reddi** (`dongu`), bilinen-cevap vektörleri (`vektor`), imzalı sürüm düşürme yetkisi (`rollback`: mesaj, `.sig`, komut satırı,
manifest çapraz kontrolü ve `rollback_vektoru`), imaj başlığı ve hedef uyumu (`imaj`),
çıktılarda özel anahtar/parola sızıntısı ve depoda anahtar bulunmaması (`sizinti`), gerçek sürüm arşivi imajlarıyla gerçeklik denetimi (`gercek_imaj`).

## Dosyalar

| Dosya | Görevi |
| --- | --- |
| `ota_imza.mjs` | Komut satırı (`anahtar-uret`, `genel-anahtar`, `imzala`, `dogrula`) |
| `lib/bicim.mjs` | İmza biçiminin tek tanımı: mesaj, `.sig` kur/ayrıştır, alan denetimleri, bilinen hedefler |
| `lib/anahtar.mjs` | Anahtar üretimi/okuma/yazma, genel anahtar biçimleri, **depo-içi koruma** |
| `lib/imaj.mjs` | İmaj okuma, ESP32 başlık / çip / hedef denetimi, sürüm metni sezgisi |
| `lib/imza.mjs` | İmzalama ve doğrulama çekirdeği |
| `lib/dosya.mjs` | Boyut sınırlı küçük dosya okuma (anahtar, imza, manifest): yanlış dosya belleğe alınmadan reddedilir |
| `lib/hata.mjs` | Hata sınıfları (çıkış kodu eşlemesi), güvenli mesaj biçimlendirme |
| `.env.example` | Ortam değişkeni **adları** (değer yok) |
| `test/` | Testler (`bicim`, `anahtar`, `dongu`, `vektor`, `rollback`, `imaj`, `sizinti`, `gercek_imaj`) ve açık test vektörleri (`vektorler.json`) |
