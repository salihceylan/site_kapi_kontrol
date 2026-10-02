# E-posta Doğrulama (Bireysel Kayıt) — Tasarım, Parametreler, İşletim

Son güncelleme: 2026-10-02. Kod: `server/src/services/membership_service.js`, `membership_rules.js`, `server/src/mailer.js`,
`server/src/routes/auth_routes.js`. Şema: `server/migrations/028_pending_registrations.sql` (+ `server/src/db.js`).

## Neden değişti

Önceki akış, kod doğrulanmadan `users` satırı açıyor ve SMTP gönderimi başarısız olsa bile "kod gönderildi" diyordu.
Canlıda kodlar geç ulaştığında 10 dakikalık süre yetmiyor, kullanıcı hesabı "yarım" kalıyordu.

## Akış (referans: OWASP Authentication Cheat Sheet / ASVS V2 yaklaşımı)

1. `POST /auth/register-individual`: girdi doğrulanır. Doğrulanmış hesap varsa **409**. Hesap yoksa ad + **bcrypt parola özeti**
   `pending_registrations` tablosuna yazılır (e-posta başına tek satır; tekrar kayıt satırı günceller). **`users` satırı açılmaz.**
2. 6 haneli kod (CSPRNG) üretilir, **bcrypt özeti** saklanır, e-posta gönderilir. Gönderim **başarısızsa**:
   kod satırı silinir (bekleme sayacı tüketilmez), yanıt **503 `EMAIL_DELIVERY_FAILED`** (Retry-After: 60). Bekleme/tavan
   aşıldıysa **429**. Kullanıcıya hiçbir zaman gönderilmemiş kod vaat edilmez.
   Ad + parola özeti **yalnızca e-posta gönderildikten sonra** yazılır: reddedilen (429) veya başarısız (503) bir deneme
   bekleyen kaydı değiştirmez; daha yeni bir açık kod varsa (yavaş, sırası geçmiş bir gönderim) yazılmaz.
   Eski kodlar yalnızca **daha eski** olanlar için (`id < yeni`) ve gönderim başarılı olunca kapatılır.
3. `POST /auth/verify-code`: doğru kodla, **tek işlemde** (transaction) hesap açılır (`email_verified = TRUE`, `role = individual`),
   bekleyen kayıt silinir, JWT döner. Kod tek kullanımlıktır. Aynı e-postayla araya hesap girmişse 409 + geri alma.
4. `POST /auth/resend-code`: bekleyen kayıt veya (eski) doğrulanmamış hesap varsa yeni kod; yanıt her durumda aynıdır
   (hesap varlığı sızdırılmaz). Yeni kod **başarıyla gönderilince** eski açık kodlar kapanır; gönderim başarısızsa önceki
   geçerli kod korunur (geç ulaşan kod boşa çıkmasın).
5. `POST /auth/login`: bekleyen kaydın **doğru** parolası eski davranışı korur: **403 "E-posta adresiniz dogrulanmadi"**
   (token yok, kilit sayacı işlemez). Yanlış parola ve hiç kayıt olmayan hesap aynı **401**'i alır (hesap varlığı ayırt edilemez).
6. Bakım servisi: 2 günden eski bekleyen kayıtları siler (`updated_at`). Hesap silmez.

Geriye uyum: bu sürümden önce açılmış doğrulanmamış `users` satırları eski yolla (UPDATE) doğrulanır; eski mobil
sürümler aynı uçları/yanıt şekillerini kullanır (201/200 JSON; hatalarda `error` + isteğe bağlı `code`).

## Parametreler (`membership_rules.js`)

| Parametre | Değer | Not |
| --- | --- | --- |
| Kod geçerlilik süresi | **30 dk** | E-posta teslimi gecikebilir; kaba kuvveti sayaçlar engeller |
| Kod başına deneme | 5 | Aşılırsa 429, yeni kod gerekir |
| Pencere (30 dk) toplam deneme | 10 | Yeni kod istemek sayacı sıfırlamaz |
| Tekrar gönderme beklemesi | 30 sn | 429 yanıtı kalan saniyeyi söyler |
| Saatlik kod tavanı | 10 | E-posta başına |
| SMTP zaman aşımları | bağlantı 10 sn, karşılama 10 sn, soket 20 sn | `mailer.js` |

E-posta gövdesi istek saatini (Türkiye saati) ve geçerlilik süresini yazar; birden fazla e-posta alındığında yalnızca
EN SON istenen kod geçerlidir.

## Bilinen kalıntı riskler ve sınırlamalar

1. **Pre-hijacking (önerilen sonraki iş).** Parolayı kayıt anında alıp sonra e-posta doğrulayan her akışta, başka biri aynı
   e-postayla ve kendi parolasıyla (bekleme süresi geçince) tekrar kayıt olursa bekleyen kaydın parolasını değiştirir; mağdur
   kendi gelen kodunu girerse hesap saldırganın parolasıyla açılır (ve o e-postaya bekleyen yönetici davetleri de bu
   hesaba bağlanır). Reddedilen denemeler artık veri ezmez, ama başarılı ikinci kayıt yine ezer. Bu risk eski tasarımda da vardı.
   **Kalıcı çözüm:** doğrulamayı kaydı başlatan istemciye bağlamak: kayıt yanıtı bir `registration_token` döner (özeti bekleyen
   kayıtta saklanır), `/auth/verify-code` bu belirteci de ister; böylece başkasının yaptığı yeni kayıt eskisini geçersiz kılar
   ve yanlış istemcinin girdiği kod hesap açamaz. Sözleşme değişikliğidir: eski uygulama sürümleri belirteç göndermez
   (sunucu geçiş için belirteçsiz doğrulamayı kabul etmek zorunda kalır, yani koruma yeni uygulama sürümüyle etkinleşir);
   uygulama + sunucu birlikte yayınlanmalı, bu yüzden ayrı iş olarak onay beklemektedir.
   Mağdur "Şifremi unuttum" ile kendi e-postasına gelen bağlantıyla parolayı sıfırlayabilir.
2. **Kaba kuvvet tavanı.** E-posta başına yaklaşık 20 tahmin/saat (pencere başına 10 deneme), 6 haneli kodda günde ~1/2000.
   İstenirse e-posta başına günlük hatalı deneme tavanı (ör. 30) eklenebilir; TTL'den bağımsızdır.
3. **Kod, gönderim bitene dek "en yeni açık kod"tur.** Yeni kod satırı e-postadan önce yazılır; gönderim sürerken (normalde ~0,3 sn,
   en kötü ~40 sn) girilen önceki kod yeni satırla karşılaştırılır ve bir deneme hakkı harcar. Kesin çözüm `sent_at` kolonu +
   deneme sorgularında `sent_at IS NOT NULL` süzgecidir (şema değişikliği gerektirir); etkisi düşük olduğu için ertelendi.
4. **Eski doğrulanmamış hesap yolu** (bu sürümden önce açılmış satırlar) rol/doğrulanmışlık süzgeci taşımayan `UPDATE` kullanır
   (önceki davranış); eski satırlar bakım/zamanla bittiğinde sadeleştirilebilir.
5. Hız sınırlayıcılar süreç belleğindedir (tek PM2 örneği için yeterli); çok örnekli kurulumda ortak depoya taşınmalıdır.

## Doğrulama kanıtı

- `cd server && npm test` (826+ test) ve `npm run lint`.
- Gerçek PostgreSQL üzerinde uçtan uca: boş yerel veritabanı hazırlayıp
  `QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_pending_registration_pg.mjs` (yalnızca 127.0.0.1/localhost, tek kullanımlık DB;
  15 adım: şema idempotent, upsert, bekleme/503/sıra dışı gönderim, eşzamanlı doğrulama, geriye uyum, bakım).

## İşletim: "kod gelmiyor / geç geliyor" teşhisi

1. API günlüğü: `pm2 logs kapi-api --lines 300 --nostream | grep -a "Mail Gönderim"` → `code` (ETIMEDOUT, EAUTH, ECONNECTION…)
   ve `responseCode` (535, 550…) alanları. `SMTP ayarlari eksik` uyarısı başlangıçta yazılır.
2. Bağlantı/kimlik testi (e-posta göndermez): `nodemailer.createTransport({...}).verify()`; 2026-10-02'de
   `mint.trdns.com:587` ve `mail.gudeteknoloji.com.tr:587` her ikisi de ~0,3 sn'de başarılıydı (parola geçerli, TLS sorunu yok).
   İki ad aynı IP'ye (77.245.149.47) çözülür.
3. DNS: SPF `+a +mx +ip4:77.245.149.47 +include:_spf.trdns.com -all`, DKIM (`default._domainkey`) ve DMARC (`p=none`) mevcut.
4. Sunucu kabul ettiği hâlde ulaşma gecikiyorsa sorun kabulden SONRA (gönderen sunucunun kuyruğu / alıcı tarafı):
   geç gelen e-postanın "orijinali göster" başlıklarındaki `Received:` satırlarının saatleri gecikmenin hangi sıçramada
   oluştuğunu gösterir; ardından gönderen sunucuda (WHM → Mail Queue / Email Delivery Reports) alan adı başına saatlik
   gönderim sınırı ve ertelenen iletiler kontrol edilir.

## Geri alma

Şema ekleyicidir (yeni tablo). Kod geri alınırsa (`deploy/README.md` → rollback) `pending_registrations` tablosu kullanılmadan
kalır ve zararsızdır; geri almadan önce bekleyen kayıtlar (hesap değil) kullanıcıların yeniden kayıt olmasıyla yenilenir.
