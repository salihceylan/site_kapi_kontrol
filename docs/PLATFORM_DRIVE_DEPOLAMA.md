# Sitenin dosyaları sitenin Google Drive'ında — plan ve uygulanabilirlik

2026-10-20 · Yol haritası karar 13'ün (`docs/PLATFORM_YOL_HARITASI.md`) ayrıntısı. Durum: **D1 (sunucu temeli + "Dosya deposu" kartı) yazıldı, bayrak KAPALI; D2-D5 sürüyor.**

İstek: her site yöneticisi sitesi için bir Google Drive hesabı açıp sisteme bağlar. Sitenin sisteme kaydettiği **her dosya**
(fotoğraf, PDF, Word, Excel, her tür belge) o sitenin Drive'ına kaydedilir, gösterilirken ve indirilirken de oradan çekilir.
Gerekçe: dosya alanını sunucuda biz karşılayamayız; alan sitenin kendi hesabından gelmeli.

## Kısa cevap

**Yapılabilir, ama dört koşulla:**

1. **Dosyalar telefona Drive'dan doğrudan gelmez; sunucumuz Drive'dan çekip verir.** Drive'ın paylaşım bağlantıları hem gizlilik
   açığı ("bağlantısı olan herkes görür") hem de 2024'ten beri resim göstermede güvenilmez. Bu yüzden dosya alanı sunucudan tamamen
   kalkar, ama trafik sunucudan geçmeye devam eder. Bugünkü "kim hangi belgeyi görür" kuralları aynen korunur.
2. **Sunucuda kalıcı dosya kalmaz.** Sunucuda yalnızca toplam boyutu sabit bir önbellek (site sayısıyla büyümez) ve bağlantı kopukken
   kullanılan küçük, geçici bir bekleme alanı olur.
3. **Drive bağlantısı zorunlu olur.** Bağlamayan sitede dosya yükleme kapalıdır. Bağlantı koparsa yeni dosyalar kısa süre bekler,
   eski dosyalar bağlantı gelene kadar açılmaz; bunun için uyarılar ve önbellek var.
4. **KVKK:** Drive sunucuları yurt dışında; bu, kişisel verinin yurt dışına aktarımı (KVKK m.9) demek. Kişisel (ücretsiz) Gmail
   hesabında Google'ın veri işleme eki yok; kurumsal Google Workspace hesabında var. Hangi hesap türünün kabul edileceğine ve
   aktarım mekanizmasına avukat karar vermeli. **Bu, işe başlamadan önceki en önemli açık nokta.**

Google tarafında engel yok: yalnızca "uygulamanın kendi oluşturduğu dosyalara erişim" izni (`drive.file`) yeterli. Bu izin
Google'ın sınıflamasında hassas değildir; geniş Drive izinlerinin istediği yıllık bağımsız güvenlik denetimi gerekmez.

Büyüklük: **L** (bir haftadan uzun, inceleme ve gerçek PG QA dahil). Başlamadan önce marka doğrulaması ve gizlilik politikası
yayında olmalı (yasal metinlere bağlı).

## 1. Kapsam

| Dahil | Hariç |
| --- | --- |
| Sitenin yüklediği her dosya: belgeler (duyuru ekleri, gider belgeleri dahil), iş takibi fotoğrafları, ileride eklenecek her yükleme | Veritabanı (kişiler, daireler, finans defteri; ayrı P0 maddesi "veritabanının dış kopyası") |
| Bu dosyaların önizlemeleri (fotoğraf ve PDF küçük resmi) | Anında üretilen PDF'ler (makbuz, rapor): kaydedilmez, her istekte yeniden üretilir |
| | Uygulama ve cihaz yazılımı dosyaları |

Bugün bu dosyalar sunucu diskinde `<site>/<uuid>` anahtarıyla tutuluyor (`server/src/modules/document_storage.js`). Boyut,
tür, kota ve bütünlük (SHA-256) denetimleri var, indirme yetki kontrolüyle sunucu üzerinden yapılıyor. Site başına üst sınır:
belgelerde 200 MB, fotoğraflarda 10 GB. 5.000 sitede bu üst sınır 50 TB'tan fazla eder; sunucuda karşılanamaz. Depolama tek modülde
toplandığı için "Drive" seçeneği aynı yere eklenebilir; belge ve fotoğraf modülleri aynı katmanı kullanır.

## 2. Araştırma bulguları

| Konu | Bulgu | Bize etkisi |
| --- | --- | --- |
| İzin kapsamı | `drive.file` hassas olmayan kapsamdır: uygulama yalnız kendi oluşturduğu ya da kullanıcının açıkça verdiği dosyalara erişir. `drive` / `drive.readonly` kısıtlı kapsamdır; sunucuda veri tutan uygulamadan bağımsız güvenlik denetimi ister. | Yalnız `drive.file` isteriz; yöneticinin Drive'ındaki diğer dosyaları göremeyiz, görmemeliyiz. |
| Marka doğrulaması | Her uygulama doğrulanmalı: alan adı sahipliği, giriş sayfası olmayan bir ana sayfa, aynı alan adında gizlilik politikası, Google düğme kuralları. | gudeteknoloji.com.tr ana sayfası ve yayınlanmış gizlilik politikası şart (yasal metinlere bağlı). |
| Yayın durumu | Onay ekranı "Testing" durumundayken verilen yenileme anahtarı 7 günde geçersiz olur. | Google Cloud projesi "In production" durumuna alınmalı. |
| Bağlantının kopması | Yenileme anahtarı şu durumlarda biter: kullanıcı erişimi kaldırırsa, 6 ay kullanılmazsa, aynı hesap ve istemci için 100 anahtar sınırı aşılırsa (en eskisi düşer), Workspace yöneticisi kısıtlarsa. Şifre değişikliği yalnız Gmail izinlerinde anahtarı düşürür. | Günlük sağlık denetimi (6 ay kuralını da önler); kopunca yöneticiye uyarı. |
| Dosya gösterme | Drive'ın `uc?export=view` gibi doğrudan bağlantıları 2024'te 403 vermeye başladı; `thumbnail` yolu belgelenmemiş ve kararsız. Paylaşıma açmak gizlilik ihlali olur. | Gösterim ve indirme sunucu üzerinden (Drive API ile çekip uygulamaya verme). |
| Kotalar (1 Mayıs 2026'dan beri yeni model) | Proje başına dakikada 1.000.000, site hesabı başına dakikada 325.000 birim. İndirme 200 birim. Günlük 400 milyon birime ve 1 TB çıkış trafiğine kadar ücretsiz. Aşımın 2026 sonunda ücretlendirilmesi planlanıyor, 90 gün önceden duyurulacak. Kullanıcı başına günlük yükleme sınırı 750 GB. | Tüm sistem için dakikada en çok ~5.000 indirme; önbellek olmadan büyüyemeyiz. Yükleme sınırı sorun değil. |
| Alan | Ücretsiz Google hesabı 15 GB (Gmail ve Fotoğraflar ile ortak). Uygulama fotoğrafı en uzun kenar 2560 px, JPEG %85 ile küçültüyor (tanesi ~0,6–1,2 MB). | Ücretsiz hesap ~15–25 bin fotoğraf ya da buna denk belge taşır; yoğun sitelere Google One gerekir (2026'da Türkiye fiyatları zamlandı, güncel fiyat Google One sayfasında). |
| KVKK | Yurt dışı sunucuda işleme m.9 kapsamında aktarımdır. Yeterlilik kararı yoksa standart sözleşme gerekir ve imzadan sonra 5 iş günü içinde Kurul'a bildirilir (bildirmeme cezası 50.000–1.000.000 TL, yıllık yeniden değerleme). Açık rıza sürekli aktarım için uygun yol değil. Workspace'te Google'ın veri işleyen olduğu veri işleme eki var; kişisel hesapta yok. | Veri sorumlusu site yönetimidir. Aydınlatma metni ve veri işleme sözleşmemiz güncellenir; hesap türü ve mekanizma avukatla netleşir. |

## 3. Üç model

| | A. Yalnız Drive | B. Sunucu asıl, Drive kopya | **C. Drive asıl, sunucuda sabit önbellek (önerilen)** |
| --- | --- | --- | --- |
| Sunucu diski | Sıfır | Site sayısıyla büyür (karşılanamaz) | Sabit üst sınırlı önbellek + küçük geçici bekleme alanı; site sayısıyla büyümez |
| Bağlantı koparsa | Hiçbir dosya açılmaz, yükleme yapılamaz | Etkilenmez | Son açılanlar önbellekten açılır; yeni yüklemeler kısa süre bekler; diğerleri "bağlantı kopuk" der |
| Drive'dan dosya silinirse | Dosya kaybolur | Sunucuda durur | Dosya kaybolur; yöneticiye bildirim |
| Google kotası | Her görüntüleme bir Drive çağrısı | Az çağrı | Önbellek çağrıları azaltır |
| KVKK | Yurt dışı aktarım | Yurt dışı aktarım | Yurt dışı aktarım |
| İsteğe uygunluk | Tam ama kırılgan | Uymaz (alan bizde kalır) | Tam |

**Önerim C.** Bütün dosyalar sitenin Drive'ında durur ve sunucu alanı site sayısıyla büyümez. Bağlantı ya da kota sorununda sistem
çökmez, sakin boş ekran görmez, ne olduğunu okur.

## 4. Önerilen model nasıl çalışır

**Bağlama (yönetici, bir kez):** Ayarlar → "Dosya deposu" → "Google Drive'ı bağla". Google onay ekranı yalnız "bu uygulamayla
kullandığınız dosyalar" iznini sorar. Onaydan sonra Drive'da `SmartKeyPass — <Site adı>` klasörü ve altında modül klasörleri
(Belgeler, İş Takibi, …) oluşur. Ekranda bağlı hesap, doluluk ve son başarılı gönderim görünür. Bağlantı kurulmadan dosya yükleme
düğmeleri kapalıdır ve "Önce sitenin Google Drive hesabını bağlayın" yazar.

**Yükleme:**

1. Dosya sunucuya gelir; bugünkü denetimler (boyut, tür, kota, bütünlük) aynen çalışır.
2. Fotoğraf ve PDF için küçük önizleme üretilir.
3. Asıl dosya ve önizlemesi sitenin Drive klasörüne gönderilir; Drive dosya kimlikleri ve SHA-256 kaydedilir.
4. Drive'daki kopya doğrulanınca sunucudaki geçici kopya silinir. Sunucuda kalıcı dosya kalmaz. "Doğrulama" = Drive dosya kimliğini döndürdü ve (bildirdiyse) boyut gönderilenle aynı; doğrulanamazsa dosya sunucuda kalır ve yeniden denenir (K6: geçici dosya yalnız Drive teyidinden SONRA silinir). Kullanıcının kendi cihazındaki kopyayı sistem hiçbir koşulda kendiliğinden silmez.

**Gösterim ve indirme:**

- Sunucu dosyayı (listelerde önizlemeyi) Drive'dan çeker ve uygulamaya verir; yetki kuralları bugünkü gibi sunucuda uygulanır.
- Çekilen dosyalar sunucuda üst sınırı sabit bir önbellekte tutulur (ör. toplam 20 GB; en uzun süredir açılmayan çıkar). Böylece
  sık açılan dosyalar hızlı açılır ve Google kotası korunur.

**Sorun çıkınca:**

| Durum | Davranış |
| --- | --- |
| Bağlantı koptu ya da Drive doldu | Yükleme kabul edilir; dosya sunucuda bekler (site başına küçük bekleme alanı, ör. 100 MB). Bekleyen dosya **süre doldu diye SİLİNMEZ** (karar K6, "silmeyi biz yapmayız"): Drive'a ulaşana kadar "bekliyor" kalır. Yönetici ekranında uyarı çıkar (bekleyen sayısı; 7 günden uzun bekleyenler için "uzun süredir bekliyor"). Bağlantı gelince bekleyenler gönderilir. |
| Bekleme alanı doldu | **Yeni** yükleme açık Türkçe mesajla reddedilir (503 `DRIVE_QUEUE_FULL`: "... bekleyen dosyalar silinmedi. Yönetiminize bildirin"); bekleyen ve kayıtlı hiçbir dosyaya dokunulmaz. Yöneticiye uyarı düşer: durum ekranında %80'de "dolmak üzere", %95'te "doldu", denetim kaydında `drive.queue_full` (aynı site için saatte bir). Drive o anda ayaktaysa yükleme yine doğrudan Drive'a gider; kuyruk yalnız kopukken gerekir. |
| Bağlantı kopukken dosya açılmak istendi | Önbellekteyse açılır; değilse "Sitenin Drive bağlantısı kopuk" yazar. |
| Dosya Drive'dan silinmiş | "Dosya sitenin Drive'ında bulunamadı" yazar; yöneticiye bildirim gider. Drive içinde taşımak sorun değildir (kimlik değişmez); silmek sorundur. |
| Doluluk %80 ve %95 | Yöneticiye uyarı (günlük sağlık denetimi). |

**Silme:** Sistemden silinen dosya Drive'dan da silinir (Drive çöp kutusuna gider, 30 gün sonra kalıcı silinir). Hesap silme ve
veri dışa aktarma akışları bu kurala göre güncellenir.

**Yönetim değişimi:** Hesap kişinin değil sitenin olmalı; şifre ve kurtarma bilgileri devir tutanağıyla yeni yönetime geçer.
`drive.file` izni hesaba ve uygulamaya bağlıdır: site AYNI hesapla yeniden bağlanırsa eski dosyalara erişim sürer. BAŞKA bir hesaba
geçilecekse sistem dosyaları eski hesaptan yenisine kopyalar (geçiş sırasında iki hesap da bağlı kalır).

## 5. Gereklilikler

**Sizden (şirket):**

1. Şirket hesabıyla bir Google Cloud projesi; Drive API açık; OAuth istemcisi; onay ekranı "External" ve "In production".
2. Marka doğrulaması için gudeteknoloji.com.tr alan adı doğrulaması (Search Console), uygulamayı anlatan ana sayfa ve aynı alan
   adında gizlilik politikası. Politika Google kullanıcı verisinin nasıl kullanıldığını yazmalı (Google API Hizmetleri Kullanıcı
   Verisi Politikası).
3. Avukat görüşü: Drive'a aktarımın mekanizması (standart sözleşme ve bildirim), kişisel Gmail hesabının kabul edilip
   edilmeyeceği, aydınlatma metni ve veri işleme sözleşmesine eklenecek madde.

**Geliştirme (bizden):**

1. Depolama katmanı: belge ve fotoğraf modüllerinin ortak kullandığı "Drive" deposu; site başına bağlantı kaydı (hesap e-postası,
   klasör kimlikleri, durum, son başarı, doluluk). Yenileme anahtarı sunucuda şifreli tutulur, anahtar `.env`'de.
2. Gönderim kuyruğu: yeniden deneme, hız sınırına uyma (403/429'da artan bekleme), site başına bekleme alanı ve süresi.
3. Önizleme üretimi (fotoğraf ve PDF) ve üst sınırı sabit önbellek.
4. Günlük sağlık denetimi: bağlantı canlılığı, doluluk uyarıları, Drive'da bulunamayan dosyalar.
5. Uygulama: "Dosya deposu" ekranı (bağla, kes, durum, doluluk), bağlama akışı, bağlantı yokken kapalı yükleme düğmeleri,
   uyarılar ve açık Türkçe hata mesajları. Dosya adresleri değişmez (yine sunucu), bu yüzden gösterim ekranları büyük ölçüde aynı
   kalır.
6. Geçiş: mevcut dosyaların arka planda sitenin Drive'ına taşınması, boyut ve SHA-256 ile doğrulama, doğrulamadan 30 gün sonra
   sunucudaki asıl kopyanın silinmesi. Geçiş süresince (ör. 60 gün) taşınmamış sitelere uyarı.
7. Silme, hesap silme, veri dışa aktarma ve yedek akışlarının güncellenmesi. Dosyalar artık sunucu yedeğine girmez; yedekleri
   sitenin Drive'ındaki çöp kutusu ve sürüm geçmişidir. Bu, aydınlatma metnine ve sözleşmeye yazılmalı.
8. Özellik bayrağı (varsayılan KAPALI), birim testleri, gerçek PG QA, en az iki tur inceleme (dosya ve yetki işi).

**Site yönetiminden:**

1. Sitenin adına açılmış bir Google hesabı (kişisel hesap değil). Avukat görüşüne göre tercihen Google Workspace.
2. Yeterli alan: ücretsiz 15 GB yetmezse Google One.
3. Uygulamada bir kez "Drive'ı bağla" adımı. Drive'daki SmartKeyPass klasörünü silmemek.
4. Hesap bilgilerini yönetim değişiminde devretmek.

## 6. Aşamalar

| Aşama | İş | Önkoşul |
| --- | --- | --- |
| D0 | Google Cloud projesi, marka doğrulaması, gizlilik politikası; avukat görüşü | Yasal metinlerin yayını |
| D1 | Sunucu: Drive deposu, bağlantı kaydı, şifreli anahtar, gönderim kuyruğu, bekleme alanı; yalnız YENİ yüklemeler; bayrak kapalı | D0 (deneme için test projesi yeter) |
| D2 | Uygulama: "Dosya deposu" ekranı, bağlama akışı, bağlantısız yükleme kilidi, uyarılar | D1 |
| D3 | Önizleme ve sabit önbellek, günlük sağlık denetimi, doluluk uyarıları | D1 |
| D4 | Mevcut dosyaların taşınması; silme, hesap silme, dışa aktarma, yedek güncellemeleri | D1–D3 |
| D5 | Pilot: 1–2 site, deneme maddeleri Faz Kontrol Listesi'ne; sonra genel açılış ve geçiş süresi | D4, avukat onayı |

## 7. Riskler

| Risk | Önlem |
| --- | --- |
| KVKK'da yanlış mekanizma (ceza riski) | D0'da avukat görüşü; olumsuzsa aşağıdaki alternatif |
| Yönetici klasörü siler ya da hesabı kapatır | Yöneticiye bildirim; devir tutanağı; aydınlatma metninde ve sözleşmede sorumluluk sitede |
| Site Drive'ı hiç bağlamaz | Dosya yükleme kapalı kalır; kurulumda ve panelde hatırlatma |
| Google kota ya da ücret değişikliği | Önbellekle düşük çağrı; kota izleme; 90 günlük duyuru süresi |
| Bağlantı sessizce ölür (6 ay, iptal) | Günlük sağlık denetimi ve uyarı |
| Trafik yine sunucudan geçer | Sabit önbellek; gerekirse büyük dosyada kısa ömürlü indirme yolu ayrıca değerlendirilir |

**Alternatif (KVKK görüşü olumsuz çıkarsa):** Türkiye'de bir S3 uyumlu nesne depolama hizmeti yurt dışı aktarım sorunu doğurmaz,
ama alanın bedeli bizde kalır; bu durumda dosya alanı site başına ücretli bir paket olarak satılmalı.

## 8. Kararlarınız (önerilerimle)

1. **Model:** C (Drive asıl depo, sunucuda yalnız sabit önbellek ve geçici bekleme alanı). Önerim.
2. **Zorunluluk:** Dosya yükleyen her modül için zorunlu. Bağlamayan sitede yükleme kapalı; mevcut sitelere geçiş süresi
   (ör. 60 gün) verilir.
3. **Hesap türü:** Avukat görüşüne bağlı; KVKK açısından Workspace daha sağlam.
4. **Eski dosyalar:** Drive'a taşınıp doğrulandıktan 30 gün sonra sunucudan silinir.

## Kaynaklar

- [Google Drive API izin kapsamları](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Google Drive API kullanım sınırları (2026 modeli)](https://developers.google.com/workspace/drive/api/guides/limits)
- [Google OAuth 2.0: yenileme anahtarının geçersiz olması](https://developers.google.com/identity/protocols/oauth2)
- [Google: marka doğrulaması gereklilikleri](https://support.google.com/cloud/answer/13464321)
- [Google: doğrulanmamış uygulamalar](https://support.google.com/cloud/answer/7454865)
- [Drive resim gömmede 403 (Justin Poehnelt)](https://justin.poehnelt.com/posts/google-drive-embed-images-403/)
- [Google Cloud veri işleme eki (Workspace)](https://workspace.google.com/intl/af/terms/dpa_terms.html)
- [KVKK standart sözleşme bildirim modülü duyurusu](https://www.alomaliye.com/2024/10/30/kvkk-standart-sozlesme-bildirim-modulu/)
- [KVKK yurt dışı aktarım rehberi özeti (Erdem & Erdem)](https://www.erdem-erdem.av.tr/bilgi-bankasi/yurt-disina-kisisel-veri-aktarimi-rehberi-neleri-duzenliyor)
- [Google One Türkiye zammı (Teknoblog)](https://www.teknoblog.com/google-one-fiyatlari-yuzde-76ya-kadar-artti/)

## 7. D1 uygulaması (2026-10-21)

Modül `drive_storage` ("Dosya Deposu"): TEMEL modül (2026-10-28, AGENTS.md Kural 25): her sitede hep açıktır; talep edilmez, kapatılamaz (`site_modules` satırı kurulumda yazılır, `migrations/082` mevcut siteleri doldurur). Google Drive hesabı ayrıca bağlanır. **2026-10-28 (084): Belgeler (`docs/PLATFORM_BELGELER.md`) bu modüle katıldı; ayrı `documents` modülü yoktur.** (084 eski `documents` `site_modules` satırlarını SİLMEZ: katalog onları yok sayar, ama dağıtım otomatik geri alınırsa önceki sürüm Belgeler'in açık/kapalı bilgisini onlardan okur. Birleştirme SQL'i `documents_into_drive.js`'tedir; kendi PG'nde iki kez çalıştırıp satırların ve belge tablolarının değişmediğini doğrula.)
Arayüzde tek menü öğesi "Dosya Deposu": belge listesi + altında "Google Drive" bölümü (eski Modüller ekranı Drive kartı buraya taşındı).
Mevcut belge ve iş takibi yüklemeleri DEĞİŞMEDİ (sunucu diskinde sürer);
yeni uçlar kendi yolundadır. Google bilgileri `.env`'de yoksa arayüz ve `POST .../connect` "Google Drive bağlantısı Yakında…" (503 `DRIVE_NOT_CONFIGURED`) der.

**.env:** `DRIVE_CLIENT_ID`, `DRIVE_CLIENT_SECRET`, `DRIVE_REDIRECT_URI` (= `https://<api>/drive/oauth/callback`), `DRIVE_TOKEN_KEY` (en az 32 karakter), isteğe bağlı `DRIVE_PENDING_DIR`.
Kapsam yalnız `drive.file`. Yenileme belirteci AES-256-GCM ile şifreli saklanır (anahtar `DRIVE_TOKEN_KEY`); anahtar kaybolursa siteler Drive'ı yeniden bağlar.

**Tablolar (migration 060, db.js ile aynı; 097 `drive_files`'a `source_type` + `source_id` ekler):** `site_drive_connections` (site başına bağlantı: durum, hesap, şifreli belirteç, klasör kimlikleri), `drive_oauth_states`
(tek kullanımlık, 10 dk), `drive_files` (Drive'a giden ya da bekleyen dosya; `UNIQUE (site_code, folder_name, name)`), `drive_pending_uploads` (bekleme kuyruğu).

**Uçlar** (site yöneticisi / süper; modül kapalıysa 403 `MODULE_DISABLED`; başka site 403): `GET|DELETE /manager/sites/:siteCode/drive` (durum / bağlantıyı kes),
`POST .../drive/connect` (`{url}`), `GET|POST .../drive/files` (liste / yükleme: gövde `application/octet-stream`, sorgu `kind, mime, date, block, apartment`; en çok 10 MB),
`GET .../drive/files/:id/content` (Drive'dan sunucu üzerinden indirme; bekleyen dosya diskten), `POST .../drive/flush`, `GET /drive/oauth/callback` (kimliksiz, state ile).

**Adlandırma (karar T1-T5):** klasör `<Tür><Ay>_<yy>`: `SrvEkim_26` (sözleşme), `suEkim_26`, `elektrikEkim_26`, `TeklifEkim_26`, `DekontEkim_26`, `GiderEkim_26`, `BelgeEkim_26`;
hepsi sitenin `SmartKeyPass — <Site adı>` klasörü altında. Dosya adı daireliyse `AB_D13_201026` (A blok, daire 13, 20.10.2026), dairesizse `Gider_201026`; aynı ad varsa `_2`, `_3`.
İçerik türü baytlardan doğrulanır (PDF, JPEG, PNG, WebP, Word, Excel, düz metin).

**Bekleme alanı ("silmeyi biz yapmayız", karar K6, 2026-10-28):** bağlantı koptuysa yükleme kabul edilir, dosya sunucuda `DRIVE_PENDING_DIR` altında bekler (site başına 100 MB).
Bekleyen dosya SİLİNMEZ: eski "7 gün sonra sil" kuralı kaldırıldı; `drive_pending_uploads.expires_at` artık silme zamanı değil, 7 günlük **"uzun süredir bekliyor" uyarı eşiğidir**
(sütun eski sürümle uyum için korunur). Alan dolunca YENİ yükleme 503 `DRIVE_QUEUE_FULL` ile reddedilir, mevcut dosyalara dokunulmaz. Sunucudaki geçici dosya yalnız Drive teyidinden (dosya kimliği + boyut)
sonra silinir; yarıda kesilmiş turdan kalan "kayıtlı ama satırı duran" dosya tekrar gönderilmez, yalnız kalıntısı temizlenir. Aynı sitenin gönderimleri sırayla çalışır (aynı dosya iki kez gitmez).
Gönderim `POST .../flush` (elle; artan bekleme süreleri yok sayılır) ile ya da yeniden bağlanınca denenir. Bağlı değilse yükleme 409 `DRIVE_NOT_CONNECTED`.
`GET .../drive` yanıtı: `pending_count`, `pending_bytes`, `pending_limit_bytes`, `pending_overdue_count`, `oldest_pending_at` ve `warnings[]` (`{code, message}`: `DRIVE_FILES_WAITING`, `DRIVE_FILES_OVERDUE`,
`DRIVE_QUEUE_NEARLY_FULL`, `DRIVE_QUEUE_FULL`). Uygulamada Dosya Deposu > Google Drive kartı bunları uyarı olarak gösterir ve "Bekleyenleri şimdi gönder" düğmesi sunar. Yönetici e-postası ve günlük sağlık
denetimi D3'tedir (henüz yok).

**Kaynak kayıt bağı (P1-11, migration 097):** dosya adına kaydın kimliği önek olarak eklenir: `<ÖN EK>-<kayıt no>_<ad>` (örn. `IS-123_AB_D13_201026.pdf`, `GDR-18_Gider_201026.pdf`; çakışma eki sonda: `IS-123_AB_D13_201026_2.pdf`).
Önekler: `work_item` IS (iş kaydı), `meter_reading` OKM (sayaç okuması), `expense` GDR (gider), `payment_notice` DKN (dekont), `contract` SZL (sözleşme), `quote` TKL (teklif), `document` BLG (belge), `equipment` EKP (ekipman).
`drive_files.source_type` + `source_id` (ikisi birlikte dolu ya da boş; CHECK) kaydı bağlar; belge hem adından hem kayıttan açılır: `GET .../drive/files?source_type=work_item&source_id=123`. Kaynak bağı HTTP yükleme
sorgusundan ALINMAZ (doğrulanamayan kayda bağ kurulamasın); yalnız sunucu içi çağıran verir (bugün sayaç okuma fotoğrafı: `OKM-<okuma no>_...`, Drive yoksa/dolu ise sunucudaki `meter_reading_photos.name` da aynı adı taşır).
Kaynak yoksa ad eskisi gibidir (geriye dönük uyum). İş ekleri, gider ve dekont belgeleri Drive'a taşınınca (D2/D4) kendi türleriyle bu bağı kullanır.

**Henüz yok (D2-D5):** otomatik zamanlayıcı ve günlük sağlık denetimi, önbellek ve önizleme, mevcut dosyaların taşınması, silme/dışa aktarma güncellemeleri, belge ve fotoğraf
ekranlarının bu depoya bağlanması, bağlantısız yükleme kilidi. Google Cloud projesi ve marka doğrulaması (D0) yapılana dek canlıda "Yakında…" görünür.
