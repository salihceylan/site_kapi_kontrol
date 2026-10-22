# Daire sahipliği ve yönetimi - sözleşme (migration 074)

Bu belge "Dairem" özelliğinin sunucu ve uygulama sözleşmesidir. Koruma (güvenlik) kuralları ayrı belgededir: `docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md`.
Üst sözleşmeler: `docs/PLATFORM_KISILER.md` (kişi / daire kayıtları), `docs/PLATFORM_KARAR_DEFTERI.md`.
Modül gerektirmez (çekirdek). Kapı açma kodu (kapı komutları, MQTT, BLE, firmware, kapı servisleri) bu özellikte DEĞİŞMEZ.

## Kurallar (kullanıcı kararı + verdiğimiz kararlar)

1. Her dairenin bir MALİKİ vardır (`apartment_residencies.relation = 'owner'`; dairede aynı anda tek güncel malik, mevcut kısmi tekil indeks).
2. **Daire admini** = dairenin yönetimini yapan kişi. Kiracı yoksa admin MALİKTİR. Malik dairesine KİRACI ekler (yeni kişi ya da sistemden arayıp seçerek).
   "Yönetimi kiracıya devret" kutusu (varsayılan AÇIK) işaretliyse kiracı admin olur; kapatılırsa admin malik kalır. Kiracı adminken yönetim
   KİRACI ÇIKANA KADAR sürer; malik tek taraflı geri alamaz. Yollar: kiracı çıkışı, karşılıklı onaylı bağ kesme, site yöneticisi müdahalesi.
3. Admin kendi AİLE ÜYELERİNİ ekler ve yönetir. Aile üyeleri daireyle ilgili ekranlara (talepler, ziyaretçi / kargo, rezervasyon, duyuru, anket, belgeler,
   kararlar) girer; daire yönetimi (kişi ekleme / çıkarma, kiracı işlemleri, devir) yalnız adminde. Aile üyesi borç / Borcum GÖRMEZ (finans görünürlüğü DEĞİŞMEDİ).
4. **Kişi arama** ("Sistemden ara"): en az 3 karakter; yalnız malik ve admin arar; saatte 60; sonuç <= 5 (fazlaysa hiç liste yok); maskeli ad / e-posta;
   daire, site, adres bilgisi YOK. Güvenlik sertleştirmesi (tam eşleşme, "Beni aramalarda göster") için güvenlik politikası belgesine bakın.
   Seçilen KAYITLI kişiye uygulama içi DAVET gider; kişi KABUL EDİNCE bağlanır (zorla ilişki kurulmaz), reddedebilir. Hesabı olmayan yeni kişi için mevcut
   uygulamaya davet (N3) e-postası kullanılır.
5. **Çıkış yolları:** (a) kiracı "Daireyi devret / Çıkış": kiracının ve KİRACININ ekledigi aile üyelerinin daire bağları biter (hesaplar silinmez), admin yeniden
   malik olur, açık borç uyarısı gösterilir ama ENGELLENMEZ (borç kiracı hesabında kalır, G12). (b) Karşılıklı onaylı bağ kesme: malik ya da kiracı talep açar, DİĞERİ onaylar / reddeder;
   14 gün yanıtsız kalırsa talep kapanır (otomatik kesme YOK). (c) Site yöneticisinin "Daireden çıkar / Taşındı" yetkisi AYNEN kalır.
6. **Vekalet:** malik, kiracısına `toplanti_imza` (toplantı kararlarına imza) ve `kurul_uyeligi` kapsamlarında vekalet verir. Geçerlilik başlangıç / bitiş (varsayılan 1 yıl,
   en çok 1 yıl), iptal edilebilir. Vekalet YOKSA toplantıda imza hakkı MALİKTEDİR. [AVUKAT DOĞRULASIN] KMK m.29: vekaletin yazılı olması ve sınırları; sistemdeki vekalet kaydı
   İÇ KAYITTIR, resmi genel kurulda yazılı vekaletname gerekebilir.

## Rol modeli (mevcut modelle uyum)

Erişim yetkisinin tek kaynağı `apartment_memberships` KALIR (kapı yetkisi, uygulama üyeliği). CRM `apartment_residencies` kayıt katmanıdır. Yeni tablolar yalnız durum / kayıt tutar.

| Kavram | Kaynak | Not |
|---|---|---|
| Daire admini | aktif `apartment_memberships.role = 'APARTMENT_ADMIN'`; yoksa eski `apartments.resident_user_code` göstergesi | Okuma tarafında TÜRETİLİR; 10 daire / 49 demo hesap verisi değişmez |
| Malik | güncel `owner` ilişkisi | Malik kaydı yoksa VE kiracı yoksa admin "türetilmiş malik" sayılır; ilk malik işleminde (kiracı ekle, vekalet, devir) ilişkisi `owner` olarak kaydedilir |
| Kiracı | güncel `tenant` ilişkisi | |
| Aile üyesi | güncel `family_member` ilişkisi (+ `sponsor_person_id`, `is_minor`) | Eski `resident` kayıtlar "Sakin" olarak listelenir |

`rolesOfUser` çıktısı: `my_role` (owner / tenant / family_member / resident), `is_admin`, `is_owner`, `can{...}` (arayüzün düğmeleri). Yetkinin tek kaynağı sunucudur.
Yönetim devri `membership_service.applyApartmentPrimaryAdmin` ("Aile Reisini Değiştir" kuralı: mevcut adminler FAMILY_MEMBER, hedef APARTMENT_ADMIN, gösterge taşınır) ile yapılır.

### Kapı yetkisi nasıl etkilenir (hangi mevcut servis çağrılır)

| İşlem | Çağrılan mevcut mekanizma |
|---|---|
| Kabul / kiracı bağlama / aile bağlama | `people_service.grantApartmentAccess` (üyelik + site RESIDENT; admin yoksa admin) |
| Yönetim devri | `membership_service.applyApartmentPrimaryAdmin` |
| Çıkış, onaylı bağ kesme, aile çıkarma, "Bu daireden ayrıl" | `people_service.closeResidency` -> `revokeApartmentAccess` (üyelik pasif, yönetici devri `handOverApartmentResident`, kapı izni temizliği `cleanupDoorOverridesIfNoMembership`) + `afterAccessClosed` (yerel kontrol anahtarı döndürme) |
| Malik "ayrıl" (malik kaydı kalır) | `handOverApartmentResident` + `cleanupDoorOverridesIfNoMembership` |
| Askıya alma / geri açma | `membership_service.toggleApartmentMemberStatus` (geçici pasife alma; bağlar korunur) |

## Veritabanı (migration 074 = `src/modules/apartment_mgmt_schema.js`; ekleyici, idempotent)

- `apartment_admin_delegations` (devir tarihçesi; açık satır dairede tek): admin kişi / kaynak, `state` active | pending_account (kiracının hesabı yok, hesap bağlanınca devir uygulanır) | ended.
- `apartment_link_requests` (durum makinesi): `kind` tenant_invite | family_invite | disconnect | member_removal; `status` pending | approved | rejected | expired | cancelled; `expires_at`.
- `apartment_proxies`: `scope` toplanti_imza | kurul_uyeligi, `valid_from` / `valid_until` (<= 366 gün), `revoked_at`; açık vekalet (daire, kapsam) başına tek.
- `apartment_notices`: uygulama içi bildirim kutusu (e-posta DEĞİL).
- Güvenlik: `apartment_safety_requests`, `apartment_safety_notes`, `apartment_access_suspensions` (bkz. güvenlik politikası).
- Ek kolonlar: `apartment_residencies.sponsor_person_id` (aile üyesini ekleyen), `apartment_residencies.is_minor`, `users.search_visible` (varsayılan KAPALI).

### Durum makineleri

```
tenant_invite / family_invite : pending --kabul--> approved (kişi bağlanır)   --red--> rejected   --geri çekme--> cancelled   --14 gün--> expired
disconnect                    : pending --karşı taraf onay--> approved (kiracılık biter)  --red--> rejected  --14 gün--> expired
member_removal                : pending --üye onay--> approved (üyenin bağı biter)  --red--> rejected  --7 gün--> expired   (otomatik kesme YOK)
```
Bekleyen talep süresi dolunca `expired` sayılır (okuma / yanıt anında) ve bakım işi (`maintenance_service` 3d) kalıcı olarak kapatır.

## Uçlar (hata gövdesi `{ error, code }`; ilgisiz daire 404 `APARTMENT_NOT_FOUND`, ilgili ama yetkisiz 403 `FORBIDDEN_ROLE`)

| Uç | Kim | Not |
|---|---|---|
| `GET /app/apartments/mine` | sakin | daireler, rol, admin, bekleyen talepler (`incoming_requests`), `notices`, `can_search` |
| `GET /app/apartments/:id` | ilgili kişi | tek daire kartı |
| `GET /app/apartments/people-search?q=` | malik / admin | maskeli sonuç + imzalı `handle`; saatte 60 |
| `POST /app/apartments/:id/tenant` | malik | `{ delegate_management?, candidate? \| person? }` |
| `POST /app/apartments/:id/family` | admin | `{ is_minor?, candidate? \| person? }` |
| `DELETE /app/apartments/:id/family/:residencyId` | admin / ekleyen | yetişkin hesaplı üye = onay isteği (`mode: consent_requested`) |
| `POST /app/apartments/:id/management/delegate` | malik | yönetimi mevcut kiracıya devret |
| `GET /app/apartments/:id/exit-preview`, `POST .../exit` | kiracı | borç uyarısı (engellemez) |
| `POST /app/apartments/:id/leave` | her üye | kendi bağını onaysız keser |
| `POST /app/apartments/:id/disconnect-requests` | malik / kiracı | karşı taraf onaylar |
| `POST /app/apartments/requests/:id/respond` `{accept}` , `.../cancel` | hedef / açan | |
| `GET\|POST /app/apartments/:id/proxies`, `DELETE .../proxies/:proxyId` | malik (vekil çekilebilir) | vekil = güncel kiracı |
| `POST /app/apartments/notices/read` | sakin | bildirimleri okundu işaretle |
| `GET\|PUT /manager/sites/:siteCode/apartments/:id/admin-candidates`, `.../admin` | site yöneticisi / süper | daire adminini değiştir (aşağıda) |
| `GET /manager/sites/:siteCode/signing-roster?date=` | yönetici / kurul okur | Karar Defteri imza hakkı sahipleri; `decision_book` modülü AÇIK olmalı |

Audit eylemleri (`target_type: apartment`): `apartment_mgmt.tenant_added | tenant_invited | tenant_invite_accepted | family_added | family_invited | family_removed | member_removal_requested | member_removal_approved | management_delegated | tenant_exit | disconnect_requested | disconnect_approved | member_left | proxy_created | proxy_revoked | owner_recorded | admin_changed_by_manager`. Kişi araması: `apartment_mgmt.person_search` (maskeli sorgu).

## Site yöneticisi: "Daire adminini değiştir"

Kişiler > Daireler > daire kartı > "Daire adminini değiştir" -> aktif sakin listesi (malik, kiracı, aile üyesi: dairede AKTİF bağı olan) -> onay ("Daire admini X yerine Y olacak").
Sunucu: yetki site yöneticisi / süper (kurul ve görevli 403, başka site 403, başka sitenin dairesi 404). Eski admin dairede KALIR (bağı silinmez, kapı erişimi değişmez); yalnız yönetim yetkisi geçer.
Malik-kiracı "kiracı çıkana kadar geri alınamaz" kuralı site yöneticisini BAĞLAMAZ (acil durum / anlaşmazlık müdahalesi). Audit `apartment_mgmt.admin_changed_by_manager`; eski ve yeni admine uygulama içi bildirim (`apartment_notices`).

## Karar Defteri: imza hakkı sahibi

Karar Defteri'nde katılım / imza satırı yoktur (katılanlar serbest metin). Bu yüzden toplantı hazırlığı için "İmza hakkı sahipleri" listesi eklendi: her aktif daire için aktif `toplanti_imza`
vekili varsa vekil ("Daire 5 - vekil: Ali Y. (malik: Veli K.)"), yoksa malik ("Daire 5 - malik: Veli K."). Aynı daire için tek kişi. Vekil hâlâ dairenin güncel kiracısı değilse vekalet yok sayılır.
`kurul_uyeligi` vekili listede ayrıca görünür; kurul üyesi atamasını mevcut Kadro ekranı yapar (kişi kaydı yeter).

## Verdiğimiz kararlar

1. Hesabı olmayan yeni kişinin e-postası kayıtlı bir hesaba aitse yeni kişi olarak eklenmez (409 `ACCOUNT_EXISTS_USE_SEARCH`): "Sistemden ara" kullanılır (hesap numaralandırma yüzü, arama kısıtlarıyla aynı düzeyde).
2. Yönetim devri, hesabı olmayan kiracıda `pending_account` olarak bekler; kiracı davetle hesap açınca (N3 kabul) yönetim ona geçer. O zamana dek admin malik kalır.
3. Malik devirden sonra dairede üye (FAMILY_MEMBER) olarak kalır; kapı erişimi mevcut kurallarla sürer.
4. Kiracı admin değilse de kendi çıkışını yapabilir ("hepsi admin ile" kuralı kiracının KENDİ bağını kesmesini engellemez).
5. Aile üyesi limiti dairede 12. Davet ve bağ kesme talebi 14 gün, üye çıkarma isteği 7 gün.
6. Davet edilen kişinin tam adı davet eden tarafta gösterilmez (maskeli); davetin içeriği (site, daire, davet eden) hedefe gösterilir.
7. Hesap silinen kişide talepler CASCADE temizlenir; vekil kiracı çıkınca vekalet `tenant_left` ile iptal olur.
8. Vekalet kaydı iç kayıttır (yukarıdaki [AVUKAT DOĞRULASIN]).

## KVKK

Kişi arama yalnız maskeli veri döner ve her arama maskeli sorguyla denetim kaydına yazılır. Davetle kişinin onayı olmadan hiçbir bağ kurulmaz. Aile üyesi finans bilgisini görmez. Güvenlik talebi ve askıya alma
kayıtları özel hassasiyetli sayılır (güvenlik politikası belgesi).

## Bilinen sınırlar

- Uygulama içi bildirim kutusu vardır; telefon bildirimi (push) ve e-posta bu olaylar için gönderilmez.
- Kurul üyesi atama ekranında vekil için özel bir seçici yoktur; imza listesi vekili gösterir, atama mevcut Kadro ekranından yapılır.
- Eski `getMyApartments` (Daire Kullanıcıları ekranı) üyelerin e-posta / telefonunu aynı dairedekilere gösterir; bu özellikte değiştirilmedi.
- Gerçek PostgreSQL ile uçtan uca sınama yapılmadı (saf kural testleri, şema / migration eşitliği ve kaynak denetimleri var).

## Doğrulama

`server/test/apartment_mgmt.test.js` (şema <-> migration, admin çözümleme, devir, vekalet, imza hakkı, arama gizliliği, yetişkin üye kuralı), `test/screens/my_apartment_view_test.dart`.
