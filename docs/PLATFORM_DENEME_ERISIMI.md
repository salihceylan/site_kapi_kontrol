# Deneme erişim kodu (P2-27, karar K10)

Adaya **tek kullanımlık** bir kod verilir; aday giriş ekranında "Deneme kodum var" der, kodu girer ve **72 saatlik**, **yalnız demo siteye kilitli**
bir oturum alır. Oturumda üstte "Deneme - X saat kaldı" şeridi görünür. Demo sitenin verisinde işlem serbesttir (K10); demo sitenin dışına hiçbir
yoldan çıkılamaz.

Kaynak: `docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md` (K10, P2-27). Sunucu: `server/src/modules/trial_access_*.js`,
migration `106_trial_access_codes.sql`. İstemci: `lib/ui/widgets/trial_banner.dart`, `lib/ui/pages/login_page.dart`, `lib/ui/helpers/trial_code_input.dart`.

## 1. Model

| Öğe | Açıklama |
| --- | --- |
| Demo site | `platform_settings` anahtarı `trial_access.demo_site` (`{ "site_code": N }`). Aynı anda **tek** demo site. Yalnız **süper kullanıcı** işaretler / kaldırır. |
| Kod | 12 karakter (`XXXX-XXXX-XXXX`), alfabe 31 karakter (0, 1, I, L, O yok), `crypto.randomInt` ile rastgele (~59 bit). Veritabanında **düz kod yok**: HMAC-SHA256 özeti (`code_hash`, anahtar `TRIAL_CODE_PEPPER`, yoksa `JWT_SECRET`) + son 4 karakter (`code_hint`). Düz kod yalnız üretim yanıtında **bir kez** görünür. |
| Kod geçerliliği | Kullanılabileceği süre 1-60 gün (varsayılan 14). Aynı anda en çok 100 kullanılmamış kod. |
| Oturum | Kod kullanılınca gerçek bir kullanıcı satırı açılır: rol `site_manager`, e-posta `trial-<rastgele>@deneme.invalid`, ad `Deneme Kullanıcısı <kod no>`, parola özeti hiçbir parolayla eşleşmez (parolayla giriş imkânsız). Tek bağ: demo siteye yönetici bağı. Süre kullanım anından **72 saat**; JWT `exp` ve veritabanı süresi birlikte uygulanır (belirteç oturumdan uzun yaşamaz). |
| Kapanış | Süre dolunca ya da kod iptal edilince erişim **anında** kesilir (her istekte kontrol). Hesap kalıntısı (kullanıcı pasif, yönetici bağı silinir) kod üretimi / kullanımı / listelemesinde ve günlük bakımda temizlenir (`closeExpiredTrialAccounts`). Kullanıcı satırı silinmez (denetim izi; `users.user_code` havuzu 90 bin). |

## 2. Uçlar

| Uç | Yetki | Açıklama |
| --- | --- | --- |
| `POST /auth/trial-access` `{ code }` | herkese açık | 200 `{ token, user, trial }` (giriş yanıtıyla aynı biçim; `user.is_trial`, `user.trial_expires_at`, `user.trial_site_code` yalnız deneme hesabında bulunur; `/me` de aynı alanları verir). 401 `TRIAL_CODE_INVALID` / `TRIAL_CODE_USED` / `TRIAL_CODE_EXPIRED` / `TRIAL_CODE_REVOKED`, 503 `TRIAL_UNAVAILABLE` (demo site tanımlı değil), 429 hız sınırı. |
| `GET /manager/sites/:siteCode/trial-access` | süper veya o sitenin yöneticisi | `{ site_code, is_demo, session_hours, items[] }`. `items`: `id, hint, status (active/expired/revoked/in_use/ended), note, created_at, expires_at, used_at, session_expires_at, revoked_at`. |
| `PUT /manager/sites/:siteCode/trial-access/demo` `{ enabled }` | **yalnız süper kullanıcı** | Siteyi demo yapar (öncekinin işareti kalkar; öncekinin açık oturumları ve bekleyen kodları geçersizleşir) ya da bu site demo ise işareti kaldırır. Onaylı site gerekir. |
| `POST /manager/sites/:siteCode/trial-access/codes` `{ note?, valid_days? }` | süper veya o sitenin yöneticisi | 201 `{ code, item, session_hours }`. Site demo olarak işaretli olmalı (409 `NOT_DEMO_SITE`). |
| `DELETE /manager/sites/:siteCode/trial-access/codes/:id` | süper veya o sitenin yöneticisi | Kodu iptal eder; süren oturum da biter. Idempotent. |

Yönetim uçları **deneme oturumuna kapalıdır** (kendini çoğaltma yok). Başka sitenin yöneticisi 403 `FORBIDDEN_SITE`.

### Sahip için adımlar (curl)

```bash
# 1) Demo siteyi işaretle (süper kullanıcı belirteci)
curl -X PUT  "$API/manager/sites/<DEMO_SITE_KODU>/trial-access/demo" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"enabled":true}'
# 2) Kod üret (yanıttaki "code" bir kez görünür; adaya iletin)
curl -X POST "$API/manager/sites/<DEMO_SITE_KODU>/trial-access/codes" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"note":"Aday adı","valid_days":7}'
# 3) Durum / iptal
curl "$API/manager/sites/<DEMO_SITE_KODU>/trial-access" -H "Authorization: Bearer $TOKEN"
curl -X DELETE "$API/manager/sites/<DEMO_SITE_KODU>/trial-access/codes/<KOD_NO>" -H "Authorization: Bearer $TOKEN"
```

**Sunucuda betikle (belirteç gerekmez, veritabanına doğrudan)** — `server/` dizininde, `.env` okunur, hedef veritabanı ekrana basılır, yazan komutlar `--yes` ister:

```bash
node scripts/trial_code.mjs status                          # demo site + son 10 kod (salt okunur)
node scripts/trial_code.mjs demo <DEMO_SITE_KODU> --yes     # siteyi demo yap (--off: işareti kaldır)
node scripts/trial_code.mjs create --days 7 --note "Aday A" --yes   # kod üret; düz kod YALNIZ burada, bir kez yazılır
node scripts/trial_code.mjs list                            # tüm kodlar (son 4 karakter, durum, süreler)
node scripts/trial_code.mjs revoke <KOD_NO> --yes           # iptal (süren oturum da biter)
```

`note` alanına kişisel veri (ad-soyad, telefon) yazmayın; "Aday A / Ekim-3" gibi kısa bir etiket yeterlidir (yalnız yöneticilere görünür).

**Dikkat:** demo olarak işaretlenen site, deneme hesaplarına yönetici olarak açılır. Yalnız uydurma veriyle dolu demo sitesini işaretleyin
(`docs/DEMO_VERI.md`); gerçek bir müşteri sitesini asla işaretlemeyin.

## 3. Güvenlik

**Kaba kuvvet.** Kod ~59 bit rastgeledir. Ayrıca `POST /auth/trial-access`: IP başına 15 dakikada 10, saatte 30 deneme (IPv6 /64 kovası) ve **tüm kaynaklardan**
saatte 120 deneme (dağıtık saldırı da saatte en çok 120 tahmin yapar). Başarılı / başarısız her deneme sayılır; sınır aşılınca doğru kod bile 429 alır ve
yanmaz. Kod yazım biçimi (alfabe / uzunluk) uymuyorsa veritabanına hiç gidilmez.

**Tek kullanım.** Tek atomik `UPDATE ... WHERE used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW() AND site_code = <demo>`: 8 eşzamanlı istekte tam
1 başarı (gerçek PostgreSQL ile kanıtlı). Hesap oluşturma aynı işlemdedir; hata olursa işlem geri alınır ve kod yanmaz.

**Erişim ilkesi (varsayılan RED).** `authRequired` her istekte deneme bağlamını **aynı sorguda** okur ve `evaluateTrialRequest` (`trial_access_common.js`) çalıştırır:

- süre doldu / kod iptal / demo site kaldırıldı ya da değişti -> **401** (`TRIAL_EXPIRED`, `TRIAL_REVOKED`); istemci oturumu kapatıp nedeni gösterir.
- demo dışı siteye giden **her** yol (okuma ve yazma, her alt yol) -> **403 `TRIAL_SCOPE_DENIED`**.
- açık küme yalnız: `GET /me`, `GET|POST /me/consents`, `/app/*` (kapı komutu, misafir geçişi ve davet kabulü hariç), `GET /manager/sites|devices|door-logs`,
  `/manager/sites/<demo>/...` (aşağıdaki kapalılar hariç), `/sites/<demo>/...`, salt-okunur `/membership/*` kendi-kapsamlı uçlar, `GET /brand-theme/mine`.
- tanınmayan her yol ve `/admin`, `/companies`, `/brand-themes`, `/device`, `/manager/{apartments,doors,join-requests}`, site açma, profil / parola / hesap silme -> **403 `TRIAL_ACTION_DENIED`**.
- yol saldırıları (yüzde kodlaması, `..`, `//`, noktalı virgül, ASCII dışı) -> **403 `TRIAL_PATH_DENIED`**; yol büyük/küçük harf duyarsız karşılaştırılır.

Demo sitenin **içinde bile** kapalı olanlar (gerekçe: dış etki, kullanıcı kodu havuzu, platform genelinde sorgu, sitenin kendisinin bozulması):

| Alt yol | Neden |
| --- | --- |
| `managers`, `invitations`, `join-token`, `join-requests`, `security-policy`, `approve-deletion`, `reject-deletion`, site düzenleme / silme (`PATCH`, `DELETE /manager/sites/:id`) | site yaşam döngüsü ve üyelik (yabancıya yöneticilik verilemez) |
| `doors`, `assignable-devices`, `cameras`, `cctv`, `plate-recognition`, `plate-events` | donanım; kamera adresine sunucudan istek gider |
| `drive`, `access-cards`, `card-payments`, `modules` (yazma) | dış hesap bağlama / kart verme / ödeme sağlayıcı ayarı / modül açıp kapama (okuma açık) |
| `staff-roles` (yazma) | e-postayla **platformdaki herhangi bir hesabı** bulur ("bu e-posta kayıtlı mı") |
| `people/bulk-actions`, `people/:id/{invitation,password-reset,account,reset-pin}` | dış e-posta / SMS gönderir, hesap ve kullanıcı kodu üretir |
| `finance/reminders/send` | borçlulara dış e-posta / SMS |
| `imports/:kind/{commit,accounts}`, `imports/login-names/*` | hesap üretir (bcrypt, kullanıcı kodu) ve platform genelinde ad / e-posta sorgular (`preview`, `spec`, `exports/*` açık) |
| `module-requests`, `trial-access` | platform düzeyi talep; kendini çoğaltma |

**Derinlemesine savunma.** Deneme hesabının tek yönetici bağı demo sitedir: `hasSiteManagementAccess` / `getManagedSiteCodes` başka siteye izin vermez
(testle kanıtlı). `server/test/trial_access_guard.test.js` gerçek `server.js` rota tablosunu tarar: demo dışı siteye giden hiçbir rota geçmez, kapalı aileler
kapalı kalır, tehlikeli uçların adı değişirse test düşer (ilke yeniden gözden geçirilir). **Yeni bir rota eklenince** bu test onu kendiliğinden kapsar; yeni
dış etkili / hesap üreten / platform genelinde sorgulayan bir uç ekleniyorsa `SITE_DENIED_FIRST`, `SITE_READ_ONLY_FIRST` ya da alt yol kuralına eklenmelidir.
"YENİ ROTA AİLESİ ALARMI" testi, gözden geçirilmiş listede olmayan yeni bir kimlikli rota ailesi (ör. `/manager/sites/:s/<yeni>`, `/app/<yeni>`) ortaya çıkınca
düşer: önce deneme ilkesine karar verilir, sonra aile listeye eklenir. Kod satırı silinmiş (ör. demo site silinip CASCADE ile kodlar gittiyse) ama hesabı
(`@deneme.invalid`) kalmışsa hesap "yetim" sayılır: her istek 401 `TRIAL_REVOKED` alır, sıradan site yöneticisi gibi çalışamaz.

**Kalan risk (bilinçli).** Demo sitede duyuru yayımlanırsa ve kişi kaydına gerçek bir e-posta girilirse duyuru e-postası o adrese gider (dış etki). Demo sitedeki
kişilerin e-postaları `@demo.invalid` olmalıdır (`tools/demo_seed`). Demo verisi adaylarca bozulabilir: demo sitesi periyodik olarak `tools/demo_seed/cleanup.mjs` ile sıfırlanır.

**Saklama (kapanış).** Bitmiş kod satırları bakım temizliğinde (`maintenance_service.js`, günlük rutin) 90 gün sonra SİLİNİR: hiç kullanılmamış ve süresi dolmuş / iptal edilmiş kodlar (süre dolumu ya da iptalden, hangisi önceyse, 90 gün sonra); kullanılmış ve oturumu KAPANMIŞ kodlar (`closed_at` + 90 gün); kullanan hesabı silinmiş (`used_by` boş) ve oturum süresi 90 gündür bitmiş kodlar. Kullanılmış ama henüz kapanmamış satıra dokunulmaz (`closeExpiredTrialAccounts` onu kapatır). `users` satırına (deneme hesabı) dokunulmaz. Silinen sayı işlem izine (`maintenance.trial_access_codes_purged`, yalnız `deleted` ve `retention_days`) yazılır; hiç satır silinmediyse kayıt düşmez.

## 4. Test

- Birim / uç testleri (hermetik): `cd server && node --test test/trial_access_*.test.js` (PG testi `TRIAL_ACCESS_PG_URL` yoksa atlanır).
- Gerçek PostgreSQL (migration zinciri + ensureDbSchema + HTTP uçtan uca + eşzamanlı kullanım):
  `TRIAL_ACCESS_PG_URL=postgres://postgres@127.0.0.1:<port>/postgres node --test test/trial_access_pg.test.js` (geçici veritabanı açıp düşürür; ~1 dk).
- İstemci: `flutter test test/trial_access_test.dart test/trial_banner_test.dart test/trial_login_dialog_test.dart`.

## 5. İstemci davranışı

- Giriş ekranı: "Deneme kodum var" -> kod diyaloğu (otomatik büyük harf ve tire; 12 karakter; hata mesajı diyalogda). Başarıda ana sayfaya geçilir.
- Üst şerit (`TrialBannerFrame`, `MaterialApp.builder`): "Deneme - 72 saat kaldı" (saat yukarı yuvarlanır; son saatte dakika), 30 sn'de bir yenilenir; süre dolunca
  sunucuyla oturum doğrulanır (401 `TRIAL_EXPIRED` -> giriş ekranı + "Deneme süreniz doldu..."). Normal oturumda şerit yoktur ve ağaç biçimi değişmez.
- Oturum bitiş anı (`trial_expires_at`) güvenli depoda saklanır ve `/me` ile korunur. Eski istemciler yeni alanları yok sayar.
