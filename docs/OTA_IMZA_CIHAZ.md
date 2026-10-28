# OTA imza doğrulaması — cihaz (firmware) tarafı

Dalga F (OTA imza, sahip onayı 2026-10-28) — firmware parçası. Sunucu (imzasız paket reddi, imza meta) ve imzalama aracı (`tools/ota_imza`) ayrı dallardadır; bu belge **cihazın** ne yaptığını ve diğer parçaların cihaza karşı uyması gereken **sözleşmeyi** anlatır.

| | |
|---|---|
| Sürümler | ESP32-C3 **4.4.0**, ESP32-WROOM **5.3.0** (= "köprü sürüm", aşağıda) |
| Algoritma | Ed25519 (RFC 8032), cihazda yalnız **doğrulama**; kütüphane: TweetNaCl uyarlaması (public domain) |
| Kodlar | `cihaz_kontrol/include/ota_ed25519.h` (çekirdek) · `ota_imza.h` (yük, bicim, anahtar durumu) · `ota_public_key.h` (gömülü genel anahtar) · `ota_guncelleme.h` (akış) |
| Araç | `cihaz_kontrol/tools/ota_anahtar.mjs` (anahtarı başlığa yazar, yayın öncesi ikiliyi denetler) |
| Testler | `cihaz_kontrol/host_test` (`t_imza.cpp`, `t_mqtt.cpp` S bölümü), `cihaz_kontrol/tools/ota_anahtar.test.mjs` |

## 1. Ne sağlar, ne sağlamaz

**Sağlar.** Cihaz, imzası doğrulanmamış hiçbir paketi kurmaz: `Update.end()` (boot bölümünü değiştiren tek adım) ancak imza geçerliyse çağrılır. VPS'in ele geçirilmesi (parola açık depoda ve eski firmware'de, karar: "şimdilik dokunma") sunucuyu kontrol eden birinin cihazlara istediği yazılımı yüklemesine **yetmez**; ona özel anahtar gerekir.

**İmza yalnız dosyayı değil, kim-hangi-sürüm bilgisini de bağlar.** Eski ama geçerli imzalı bir paketi yeniden sunarak sürüm düşürtme (rollback) ya da C3 paketini WROOM'a kurdurma saldırıları imza denetiminde yakalanır (bkz. 4).

**Sağlamaz (bilinen sınırlar).**

- Güvenli önyükleme (secure boot) yoktur: kartın USB'sine fiziksel erişimi olan biri yine istediğini yazabilir. Bu iş yalnız **OTA yolunu** korur.
- Özel anahtar sızarsa ya da kaybolursa OTA ile düzeltme yapılamaz; USB ile yeni anahtarlı firmware yazmak gerekir (bkz. 9).
- İmzaya son kullanma tarihi konmadı; sürüm tekrarı **sürüm yalnız artar** kuralıyla sınırlıdır (bkz. 7).

## 2. Anahtar ve ilk kurulum (kullanıcının yapacağı)

`ota_public_key.h` bu teslimde **YER TUTUCU** içerir (ASCII `OTA-PUBLIC-KEY-NOT-SET-REPLACE!!`; geçerli bir anahtar değildir). Gerçek anahtarı **kullanıcı üretir**; özel anahtar depoya, firmware'e, günlüğe, ajan çıktısına ASLA girmez.

1. İmza anahtar çiftini üretin (`tools/ota_imza` aracı; özel anahtar depo DIŞINDA, yedekli ve parolalı saklanır). Yalnız **genel** anahtarı alın.
2. `node cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar>` — 64 hane hex, base64 ya da SPKI PEM dosyası kabul eder; **özel anahtar verilirse reddeder**. Başlığı baştan yazar, parmak izini gösterir. Zayıf (küçük mertebeli), kanonik olmayan, geçersiz ya da yer tutucu anahtarı kabul etmez.
3. Derleyin (`pio run -e lolin_c3_mini`, `pio run -e esp32_relay_wroom`). **Yayın derlemesini `SKP_OTA_ANAHTAR_ZORUNLU=1` ile yapın:** `ota_public_key.h` hâlâ yer tutucuysa derleme **durur** (`tools/ota_anahtar_kontrol_pio.py`; değişken yoksa yalnız belirgin bir UYARI basar).
4. **Yayın öncesi zorunlu denetim:** `node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar>`. Çıkış 0 = tamam; **2 = ikilide yer tutucu var, YAYINLAMAYIN**; 3 = beklenen anahtar ikilide yok. (Yer tutuculu sürüm sahaya çıkarsa o cihazlar bir daha OTA ile güncellenemez.) Bu denetim gerçek `pio run` çıktılarıyla sınandı: gerçek anahtarlı ikili → 0, yer tutuculu ikili → 2, başka anahtar → 3.
5. Kartın seri çıkışında açılışta şu satırı görün: `OTA imza anahtari: HAZIR (Ed25519, zorunlu); parmak izi <16 hane>` ve betiğin gösterdiği parmak iziyle karşılaştırın.

Cihaz anahtarı çalışma zamanında sınıflar: `HAZIR` (geçerli, küçük mertebeli olmayan Ed25519 noktası) · `YER TUTUCU` · `GECERSIZ` (nokta değil, kanonik değil, tüm-sıfır, bilinen zayıf nokta). HAZIR değilse hiçbir paket indirilmez bile (`ota_failed`, `imza: anahtar yerlestirilmemis`, deneme hakkı yakılmaz). Zayıf anahtarla sahte imza üretmek kolay olduğundan doğrulama bu kapıdan geçmeden çalışmaz (testte gösterildi: kimlik noktası anahtarıyla ham doğrulama sahte imzayı kabul eder; kapı bunu keser).

Yer tutucu metnini (`OTA-PUBLIC-KEY-NOT-SET-REPLACE!!`) tanıyan tablo firmware'de **XOR'lanmış** saklanır; böylece düz metin ikilide **yalnız** `ota_public_key.h` hâlâ yer tutucuysa bulunur ve ikili taraması gerçek anahtarlı derlemede yanlış alarm vermez.

## 3. Cihaz akışı

```text
manifest GET (?current_version=&uid=&imza=ed25519-v1)
  -> sürüm kararı (yalnız artan; istisna: izinli düşürme, bkz. 7)
  -> ön koşullar (indirme yok, deneme hakkı yanmaz): url, sha256, sürüm alanı imza yüküne uygun mu,
     imza adresi yalnız https://api.gudeteknoloji.com.tr/ , OTA bölümü var mı
  -> imza anahtarı HAZIR mı?   değilse: dur  (ota_failed "imza: anahtar yerlestirilmemis")
  -> deneme hakkı ayrılır (aynı sürüm için en çok 3)
  -> MQTT oturumu kapanır
  -> İMZA ALINIR  (manifest "signature" ya da  <paket>.sig)     paket HENÜZ indirilmedi
  -> paket indirilir: OTA bölümüne yazılır + akışlı SHA-256
  -> SHA-256 manifestle aynı mı?
  -> İMZA DOĞRULANIR  (yük: hedef + sürüm + bayt sayısı + SHA-256 [+ rollback_max])
  -> yalnız ikisi de doğruysa  Update.end()  ->  ota_success -> yeniden başlat
     aksi halde  Update.abort()  -> ota_failed  (boot bölümü DEĞİŞMEZ)
```

İmza **önce** alınır: `.sig` yoksa 1,8 MB indirilmez ve OTA bölümüne hiçbir şey yazılmaz. Doğrulama `Update.end()`'den **önce** yapıldığı için geçersiz imzada eski imaj çalışmaya devam eder.

### Hata durumları (sunucu `ota_failed` olay ayrıntısı = cihaz durum metni)

| Ayrıntı metni (başı) | Anlamı | Deneme hakkı |
|---|---|---|
| `imza: anahtar yerlestirilmemis; guncelleme yapilmadi` | gömülü anahtar yer tutucu/geçersiz | yanmaz, indirme yok |
| `imza: manifest surum alani gecersiz` | sürüm metni yüke girmeye uygun değil (satır eklemeye karşı) | yanmaz |
| `imza: adres turetilemedi (sig_url gerekli)` | paket adresi sorgu içeriyor, `sig_url` yok | yanmaz |
| `imza: adres reddedildi (https/sunucu uyusmuyor)` | imza adresi izinli sunucu/HTTPS değil | yanmaz |
| `guncelleme basarisiz: imza: dosya yok (http 404/403/410)` | **imzasız paket** — sunucuda `.sig` yok | **yanar** (kalıcı) |
| `guncelleme basarisiz: imza: dosya alinamadi (http N)` | geçici ağ/sunucu hatası | iade edilir |
| `guncelleme basarisiz: imza: dosya cok buyuk` | imza dosyası > 256 bayt | yanar |
| `guncelleme basarisiz: imza: bicim gecersiz` | 64 bayt ham / 128 hane hex / 88 karakter base64 değil | yanar |
| `guncelleme basarisiz: imza: dogrulama basarisiz` | imza bu anahtar + bu yük için geçersiz (bozuk, başka anahtar, başka sürüm/paket/hedef) | **yanar** |

Aynı sürüm için en çok 3 deneme (mevcut kural); yönetici `retry:true` ile sıfırlar. Seri çıkışa ayrıca `OTA GUVENLIK: paket imzasi dogrulanamadi; guncelleme REDDEDILDI (boot bolumu degismedi).` yazılır.

## 4. İmzalanan ileti (imzalayan araç BİREBİR bu baytları imzalamalıdır)

ASCII, her satır tek `\n` ile biter (son satır dahil), başka boşluk yok:

```text
SKP-OTA-V1
target=esp32-c3
version=4.4.1
size=1743720
sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

- `target`: `esp32-c3` | `esp32-wroom` (cihaz **kendi** hedefini kullanır, manifesttekini değil).
- `version`: manifestteki sürüm metni, **aynen** (ör. `4.4.1`; harf/rakam/`.`/`_`/`+`/`-`, en çok 24 karakter).
- `size`: `firmware.bin` bayt sayısı (ondalık).
- `sha256`: `firmware.bin` SHA-256'sı, **64 küçük harf** hex.
- Yalnız izinli sürüm düşürmede altıncı satır: `rollback_max=<sürüm>` (bkz. 7). Yoksa satır **hiç** bulunmaz.
- İlk satır (`SKP-OTA-V1`) alan ayırıcıdır: aynı anahtarla başka amaçla atılan imza OTA imzası sayılmaz.
- İmza: bu baytların Ed25519 imzası (64 bayt, RFC 8032 saf EdDSA — önceden özetleme yok).

Referans uygulama (Node; gerçek anahtar dosyası depo dışında):

```js
const yuk = Buffer.from(`SKP-OTA-V1\ntarget=${hedef}\nversion=${surum}\nsize=${govde.length}\nsha256=${sha256Kucuk}\n`);
fs.writeFileSync('firmware.bin.sig', crypto.sign(null, yuk, crypto.createPrivateKey(fs.readFileSync(ozelAnahtarDosyasi))));
```

Aynı kurucunun test sürümü: `cihaz_kontrol/host_test/gen_imza_vectors.mjs` içindeki `imzaYuku()`; cihazın C++ kurucusu (`otaImzaYukuOlustur`) ile 60 rastgele vektörde bayt-bayt aynı sonucu verdiği her çalıştırmada doğrulanır.

**İmza dosyası** (`<paket adresi>.sig`, varsayılan; ya da manifestte `sig_url`/`signature_url`; ya da manifestte `signature`): 64 bayt ham, **veya** 128 hane hex (boşluk/satır sonu serbest), **veya** 88 karakter base64 (`==` dolgulu).

## 5. Manifest alanları (hepsi isteğe bağlı; hiçbiri imza zorunluluğunu kapatamaz)

| Alan | Etkisi |
|---|---|
| `signature` | imza metni (hex/base64); varsa `.sig` indirilmez |
| `sig_url`, `signature_url` | imza dosyası adresi (`https://api.gudeteknoloji.com.tr/` ile başlamak zorunda) |
| `allow_downgrade`, `downgrade_allowed` | **yalnız JSON `true`** — izinli sürüm düşürme **adaylığı** (bkz. 7) |
| `rollback_max` | düşürme izninin kapsamı (bu sürüm ve daha eski cihazlar); yoksa cihazın kendi sürümü |

Manifest isteği artık `&imza=ed25519-v1` parametresini de taşır: bu cihaz imza doğrulayabilir demektir. Eski (köprü öncesi) cihazlar göndermez; sunucu geçiş mantığını buna (ya da `current_version >= 4.4.0 / 5.3.0`) bağlayabilir.

## 6. KÖPRÜ SÜRÜM PLANI (imzasız → imzalı geçiş)

Sahadaki cihazlar (**N**: 4.3.3 / 5.2.2 ve öncesi) imza bilmez; onlara imza zorunluluğu getirmek mümkün değildir. Bu sürüm (**N+1**: 4.4.0 / 5.3.0) tek köprüdür.

| Aşama | Sahadaki cihaz | Yayın | Sonuç |
|---|---|---|---|
| 1 | N | N+1, **eski yolla** (manifest + sha256; imza dosyası olabilir ama gerekmez) | N paketi sha256 ile kurar — N imzaya bakmaz. **N+1'in kendisi yüklenirken imza aranmaz.** |
| 2 | N+1 (çalışıyor) | N+2 **imzalı** (`.sig` yanında) | N+1 imzayı doğrular; imzasız ya da bozuk imzalı N+2'yi **reddeder** |
| 3 | N+1 ve sonrası | sunucu "imzasız paket reddi"ni açar | N cihazı kalmadığında tüm yayınlar imzalıdır |

**Bu, derleme bayrağıyla değil çalışma mantığıyla yapılır.** `-DOTA_IMZA_ZORUNLU=0/1` gibi bir bayrakla iki ayrı derleme gerekirdi: köprü derlemesi sahada imza zorunluluğu olmadan kalır (saldırı penceresi) ve yanlış derlemenin sahaya çıkma riski doğar. Burada **tek derleme** vardır ve imza denetimi **her kurulumda koşulsuz** çalışır; köprü yalnızca N'nin imzayı bilmemesinden doğar. Zorunluluğu hiçbir şey kapatamaz: ne manifest alanı (`force`, `signed`, `allow_downgrade` …), ne NVS ayarı, ne MQTT komutu, ne de derleme bayrağı vardır (testler: `t_mqtt.cpp` S2, S4, S5, S6, S10). Çalışma zamanındaki durum kararları şunlardır: anahtar durumu (HAZIR değilse kurulum yok), izinli düşürmenin imzaya bağlı olması ve `imza=ed25519-v1` yetenek bildirimi.

**Sunucu/araç tarafına düşenler (sözleşme):**

1. Köprü için N+1'i imzasız (eski biçimde) sunabilmek; imza bilmeyen cihazlar `imza` parametresini göndermez.
2. N+2 ve sonrası için `firmware.bin.sig` üretmek ve `GET /firmware/<hedef>/firmware.bin.sig` ile sunmak (yukarıdaki yük biçimi). `sha256` küçük harf olmalı.
3. `imza=ed25519-v1` bildiren (ya da sürümü ≥ köprü olan) cihazlara imzasız paket **sunmamak** (cihaz zaten reddeder; sunucu fazladan 1,8 MB boşa yollamasın).
4. İmzalama aracı (ve sunucunun yükleme doğrulaması), imzalanan `firmware.bin`'in içinde **imzalayan anahtarın genel anahtarının gömülü olduğunu** ve **yer tutucu metnin bulunmadığını** doğrulamalı (`ota_anahtar.mjs kontrol <bin> <genel_anahtar>` mantığı; yer tutucu düz metni `OTA-PUBLIC-KEY-NOT-SET-REPLACE!!`): aksi halde o sürümü kuran cihaz sonraki imzalı güncellemeyi doğrulayamaz. Ayrıca imzalanan `version` metninin ikilide geçtiği (`OTA_VERSION_*` sabiti) denetlenirse sürüm numarası yanlış yazılan paket imzalanmaz.
5. Köprü sürümün (N+1) kendisi **yer tutuculu derlemeyle yayınlanmamalı**: sunucu tarafında "yer tutucu içeren paket reddi" en ucuz ikinci güvencedir (birinci güvence: `SKP_OTA_ANAHTAR_ZORUNLU=1` derlemesi ve `kontrol`).

**Gerçek anahtar yerleşmeden köprü yayınlanmaz** (bkz. 2, adım 3-4).

**Sunucu notu (mevcut kod):** `server/src/utils/helpers.js` `safeFirmwareFile` yalnız `.bin` biter dosya adı kabul eder; `GET /firmware/<hedef>/firmware.bin.sig` bu haliyle 400 döner. İmza dosyasını sunmak için sunucuda `.sig` uzantısına izin verilmeli ya da imza manifestte `signature` alanıyla (veya farklı bir `sig_url` ile) verilmelidir; cihaz üçünü de destekler.

## 7. Sürüm düşürme

Varsayılan: cihaz mevcut sürüme **eşit ya da düşük** sürümü kurmaz (`ota_up_to_date`, "downgrade reddedildi"). Geri dönüş gerekirse eski kod **daha yüksek** bir sürüm numarasıyla yeniden derlenip imzalanır (OTA_KURULUM.txt'deki kural değişmedi).

İstisna — **izinli düşürme** (sunucudan gelen işaret **tek başına yetmez**):

1. Manifest `allow_downgrade: true` (JSON boolean; dize/sayı sayılmaz) **ve** sürüm cihazın sürümünden gerçekten **eski** (eşit asla).
2. Kapsam: `rollback_max` (yoksa cihazın kendi sürümü). Cihazın sürümü `rollback_max`'tan büyükse bu cihaz için güncelleme yoktur (`ota_up_to_date`).
3. İmzalanan yük `rollback_max=<aynı değer>` satırını **içermek zorundadır**. Sunucu kapsamı genişletemez (imza bozulur), yükseltmeye düşürme izni ekleyemez, imzasız izin veremez.

Böylece ele geçirilmiş sunucu "izin var" dese bile sahip, imzalamadığı bir düşürmeyi yaptıramaz; sahibin imzaladığı izin de sürüm aralığıyla sınırlıdır. İzinli düşürme operasyonel bir istisnadır; imzalama aracında ayrı bir bayrak (örn. `--rollback-max <sürüm>`) gerektirir (araç dalı).

**Kalan risk (bilinçli):** imzalı bir düşürme paketi (örn. 4.3.0, `rollback_max=4.4.2`) **süresizdir**; ele geçirilmiş bir sunucu onu, sürümü ≤ `rollback_max` olan her cihaza istediği zaman yeniden sunabilir. Filo `rollback_max`'ı geçince (örn. hepsi 4.4.3+) artık etkisizdir. Bu yüzden `rollback_max` **olabildiğince dar** (düşürme gerektiren en yeni sürüm) seçilmeli ve düşürmeden sonra filo hızla `rollback_max`'ın üstüne yükseltilmelidir. İzin üretmek gerekmiyorsa hiç üretilmemelidir (varsayılan çözüm: eski kodu yüksek numarayla yeniden imzalamak).

## 8. Boyut, bellek ve süre (`pio run`, espressif32@6.5.0, 2026-10-29)

| | Önce (HEAD) | Sonra | Fark | Bölümde boş kalan |
|---|---|---|---|---|
| ESP32-C3 flash | 1.730.940 B (%88,0) | 1.743.724 B (%88,7) | **+12.784 B** | 222.356 B (%11,3) |
| ESP32-C3 RAM (statik) | 64.508 B | 64.764 B | +256 B (imza dosyası tamponu) | — |
| ESP32-WROOM flash | 1.848.341 B (%94,0) | 1.861.757 B (%94,7) | **+13.416 B** | 104.323 B (%5,3) |
| ESP32-WROOM RAM (statik) | 62.972 B | 63.228 B | +256 B | — |

- **WROOM flash bölümü %94,7 dolu** (kalan ~102 KB): sonraki özellikler için dikkat. C3'te pay geniş (AGENTS.md kural 3: C3'ün flash/RAM sınırları gözetildi, RAM artışı yalnız 256 B).
- Ed25519 çekirdeği (SHA-512 dahil) derlenmiş ~7,8 KB (C3, RISC-V) / ~6,5 KB (WROOM, Xtensa) tutar (`-Os`, çapraz derleyici çıktısı).
- **Yığın:** en derin zincir ≈ 1,6 KB (`nktEkle` 1,2 KB + `gfM` 0,3 KB; `-fstack-usage` ile ölçüldü). 3 noktalık + SHA-512 çalışma alanı (~1,9 KB) **yığında değil `malloc` ile** ayrılır; ayrılamazsa doğrulama **başarısız** sayılır (güvenli taraf). Loop görevinin 8 KB'lik yığını TLS indirme zinciriyle zaten derindir; imza tamponu da yığında değil kalıcı bellektedir.
- **Süre:** masaüstünde bir doğrulama ~12-18 ms; ESP32'de tahmini 0,3-1,5 sn (TweetNaCl, 2 skaler çarpım; 30 sn'lik watchdog doğrulama öncesi/sonrası beslenir). **Gerçek kart süresi saha denemesinde ölçülmelidir** (bu işte karta yazılmadı).
- Yer tutuculu (teslim edilen) hâl ile gerçek anahtarlı hâlin boyutu aynıdır (anahtar 32 B).

**Kütüphane seçimi.** Araç zincirindeki mbedtls (2.28.4, Arduino-ESP32 2.0.14 / ESP-IDF 4.4.6) Ed25519 içermez. SDK'da libsodium (`-llibsodium`, `crypto_sign_verify_detached`) vardır ve bağlanabilir; ölçüldü: yalnız o doğrulama çağrısı C3'te **+29.970 B**, WROOM'da **+31.512 B** flash ekler (gömülü çekirdek: akış mantığı dahil +12,8 / +13,4 KB). **Gömülü çekirdek seçildi:** (1) WROOM bölümü %94,7 dolu, libsodium boş payı ~74 KB'a düşürürdü; (2) cihazdaki gerçek doğrulama yolu ana makinede OpenSSL vektörleriyle sınanabilir (SDK'nın derlenmiş libsodium'u ana makinede çalıştırılamaz, testlerde yalnız taklit edilirdi); (3) libsodium bir SDK bileşenidir, platform yükseltmesinde (Arduino-ESP32 3.x / ESP-IDF 5.x) ayrıca yönetilmesi gerekir. Arayüz tek fonksiyondur (`ota_ed25519::dogrula`); ileride libsodium'a geçmek bu gövdeyi `crypto_sign_verify_detached` ile değiştirmekten ibarettir (yük, anahtar kapısı ve akış aynı kalır).

## 9. Anahtar döndürme ve sızma

- **Planlı döndürme:** yeni çift üretilir; yeni genel anahtarı gömen bir sürüm **eski özel anahtarla** imzalanır ve yayınlanır; bütün cihazlar bu sürüme geçince sonraki sürümler yeni anahtarla imzalanır. (Cihazda tek anahtar yuvası vardır.)
- **Özel anahtar sızdı/kayboldu:** OTA ile kurtarma yoktur — sızan anahtarla imza atılabilir; kayıpta yeni imza atılamaz. Bu durumda yeni genel anahtarlı firmware USB ile (company_qr_tool USB paketi) yazılır. Bu yüzden özel anahtarın çevrimdışı yedeği şarttır.

## 10. Testler

```bash
cd cihaz_kontrol/host_test && python run_all.py        # t_imza (SHA-512/Ed25519/yük/anahtar), t_mqtt WROOM + C3 (akış)
node --test "cihaz_kontrol/tools/*.test.mjs"           # anahtar yardımcısı
```

- Çekirdek: RFC 8032 7.1 vektörleri (gizli anahtarsız), OpenSSL ile imzalanan 200 rastgele vektör (test imzalayıcısı OpenSSL ile **bayt-bayt aynı** imzayı üretir), 512 tek-bit bozma, `S ≥ L` esnek imza reddi, 8 küçük mertebeli nokta, kanonik olmayan `y`, bağımsız JS (BigInt) gerçeklemesiyle 356 anahtar adayında aynı karar.
- Akış (`t_mqtt.cpp` S1-S12): geçerli imza; `.sig` yok (404/403/410); geçici hata (hak iadesi); bozuk imza (`Update.end` çağrılmaz); başka sürüm/paket/hedef/anahtar için imza; yetkisiz `rollback_max`; gömülü imza; `sig_url`; büyük dosya; satır ekleme; yer tutucu/sıfır/zayıf anahtar; izinli düşürme; deneme sınırı; açılış günlüğü, özel anahtarın hiçbir günlüğe yazılmaması.
- Mutasyon denetimi: doğrulamayı atlayan, `Update.end` sonrasına alan, düşürme iznini açan, anahtar kapısını kaldıran, `S < L` denetimini silen, yüke hedef eklemeyen mutasyonlar testleri **kırar** (her biri tek başına).
- Test anahtarları çalışma zamanında etiketten türetilir (`ed25519_test_imzalayici.h`, "TEST ANAHTARI — üretimde kullanılmaz"); depoda gizli anahtar yoktur. Node vektörleri (`imza_vectors.txt`) git'e girmez.

## 11. Saha denemesi (kullanıcı; kart yazma ve deneme bu işte yapılmadı)

1. Tezgâh kartı için **geçici test anahtarı** üretin (gerçek anahtar değil), `ota_anahtar.mjs yaz` ile gömün, USB ile yazın; açılışta `HAZIR` + parmak izi satırını görün.
2. `allowed_uids` ile yalnız bu karta bir sonraki sürümü **imzalı** yayınlayın → `ota_success`, kart yeni sürümle açılır, 60 sn sonra `ota_validated`.
3. Aynı paketi `.sig` olmadan yayınlayın → `ota_failed` (`imza: dosya yok`), kart eski sürümde çalışmaya devam eder, panelde durum metni görünür.
4. `.sig` içinde tek bayt bozun → `imza: dogrulama basarisiz`; eski imaj çalışıyor.
5. C3 için imzalanmış paketi WROOM manifestine koyun (yanlış hedef) → reddedilir.
6. Yer tutuculu bir derlemeyi (`ota_anahtar.mjs yer-tutucu`) tezgâh kartına yazın → açılışta `YER TUTUCU` uyarısı, OTA denemesi `imza: anahtar yerlestirilmemis`.
7. Gerçek anahtarı gömüp `kontrol` çıkış kodunu 0 görün; köprü sürümü önce 1-2 kartla (`allowed_uids`), sonra tüm filoyla yayınlayın.
8. Köprüden sonra imzalı bir sürüm yayınlayıp filoda `ota_success` sayısını izleyin; imzasız deneme yalnız **reddedilmeli**.
