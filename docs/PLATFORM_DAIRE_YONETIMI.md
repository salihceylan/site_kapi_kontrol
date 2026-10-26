# Daire sahipliği ve yönetimi - sözleşme (migration 074)

Bu belge "Dairem" özelliğinin sunucu ve uygulama sözleşmesidir. Koruma (güvenlik) kuralları ayrı belgededir: `docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md`.
Üst sözleşmeler: `docs/PLATFORM_KISILER.md` (kişi / daire kayıtları), `docs/PLATFORM_KARAR_DEFTERI.md`.
Modül gerektirmez (çekirdek). Kapı açma kodu (kapı komutları, MQTT, BLE, firmware, kapı servisleri) bu özellikte DEĞİŞMEZ.

## Kurallar (kullanıcı kararı + verdiğimiz kararlar)

1. Her dairenin bir MALİKİ vardır (`apartment_residencies.relation = 'owner'`; dairede aynı anda tek güncel malik, mevcut kısmi tekil indeks).
2. **Daire admini** = dairenin yönetimini yapan kişi. Kiracı yoksa admin MALİKTİR. Malik dairesine KİRACI ekler (yeni kişi ya da sistemden arayıp seçerek).
   "Yönetimi kiracıya devret" kutusu (varsayılan AÇIK) işaretliyse kiracı admin olur; kapatılırsa admin malik kalır. Kiracı adminken yönetim
   KİRACI ÇIKANA KADAR sürer; malik tek taraflı geri alamaz. Yollar: kiracı çıkışı, karşılıklı onaylı bağ kesme, site yöneticisi müdahalesi. Kiracı ilişkisi kapanınca (taşındı, üyelikten çıkarma, silme, çıkış) açık devir ve vekaletler de kapanır; devir yalnız devralan güncel kiracıysa ve aktif üyeliği varsa geçerlidir (bkz. «Yönetim devrinin geçerliliği ve kapanması»).
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

### Yönetim devrinin geçerliliği ve kapanması (2026-10-26, koddan doğrulandı)

Açık devir satırı (`apartment_admin_delegations`, `ended_at IS NULL`) admini YALNIZ aşağıdaki koşullarda belirler (`apartment_mgmt_rules.js` `resolveApartmentRoles`, iç işlev `delegationApplies`). Koşul sağlanmıyorsa devir yok sayılır: admin aktif `APARTMENT_ADMIN` üyeliğinden, o da yoksa eski sakin göstergesinden çıkar. Geçerli devir, üyelikten gelen adminin yerine geçer.

- Devralan hesaplıysa (`admin_user_code`) bu dairede AKTİF üyeliği vardır.
- Devir kaynağı `tenant_delegated` ise (malik -> kiracı devri; kaynak yazılmamışsa da bu sayılır) devralan dairenin GÜNCEL KİRACISIDIR. Diğer kaynaklarda (ör. site yöneticisinin «Daire adminini değiştir»i, `manager`) devralan dairenin en az güncel bir sakinidir (malik ya da aile üyesi de olabilir).
- Hesapsız devralanda (`pending_account`) kişi kaydı güncel ilişkiler arasında bulunur.

Devir satırı şu durumlarda KAPANIR (`state = 'ended'`, `ended_at` dolar, `end_reason` yazılır):

| Olay | `end_reason` | Kod |
|---|---|---|
| Devralan kişi daireden ayrılır, çıkarılır ya da silinir (kiracı ilişkisi ya da hesaplı kişinin herhangi bir ilişkisi biter: «Taşındı», onaylı bağ kesme, aile çıkarma vb.) | `residency_<neden>` (`residency_ended` nedensizse) | `apartment_delegation_close.js` `closeDelegationsOnLeave`; çağıran `people_service.closeResidency` |
| Üye daireden çıkarılır (`removeApartmentMember`: süper kullanıcı, site yöneticisi ya da daire yöneticisi) | `member_removed` | `membership_service.js` -> `closeDelegationsOnLeave` |
| Daire sakini tamamen silinir (`deleteApartmentMember`: süper kullanıcı, site yöneticisi) | `member_deleted` | `membership_service.js` -> `closeDelegationsOnLeave` |
| Kiracılık sona erer (kiracı çıkışı, onaylı bağ kesme) | çıkış nedeni (`tenant_exit`, `tenant_left`, `disconnect_approved`) | `apartment_mgmt_service.js` `endTenancy` |
| Aile reisi değişir («Aile Reisini Değiştir», `setApartmentPrimaryAdmin`) | `admin_changed` | `membership_service.js` |
| Site yöneticisi daire adminini değiştirir | `manager_changed` (yeni admin için `manager` kaynaklı yeni devir açılır) | `apartment_mgmt_manager.js` |
| Aynı dairede yeni devir açılır | `replaced` | `apartment_mgmt_core.js` `recordDelegation` |
| Bekleyen (`pending_account`) devir uygulanırken kiracı artık güncel kiracı değildir | `tenant_gone` | `apartment_mgmt_core.js` `activatePendingDelegations` |

Aynı `closeDelegationsOnLeave` çağrısı, ayrılan kişinin VEKİL olduğu ya da vekalet VERDİĞİ açık vekaletleri de iptal eder (`revoked_at` dolar, `revoked_reason` = aynı neden kodu). Çağrı, kişi kaydı hesaptan koparılmadan ÖNCE yapılır (son ilişki bitince `site_people.user_code` boşalır ve kişi aranamazdı). İşlem idempotenttir; eşleşen satır yoksa hiçbir şey yapmaz.

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
| `GET /app/apartments/:id/vehicles` | dairede bağı olan herkes + site yöneticisi | dairenin aktif araçları, `can_manage`, `limit`, `owners`; aşağıdaki "Araçlar" bölümü |
| `POST /app/apartments/:id/vehicles`, `PUT .../vehicles/:vehicleId`, `DELETE .../vehicles/:vehicleId` | daire admini VEYA site yöneticisi / süper | ekle `{ plate, note?, person_id? }`, not / sahip düzenle, çıkar (pasife al) |
| `GET\|PUT /manager/sites/:siteCode/apartments/:id/admin-candidates`, `.../admin` | site yöneticisi / süper | daire adminini değiştir (aşağıda) |
| `GET /manager/sites/:siteCode/apartments/:id/household` | site yöneticisi / süper tam; kurul yalnız ad + ilişki | dairenin TÜM güncel sakinleri + daire admini (aşağıda "Site yöneticisi: dairenin sakinleri") |
| `GET /manager/sites/:siteCode/signing-roster?date=` | yönetici / kurul okur | Karar Defteri imza hakkı sahipleri; `decision_book` modülü AÇIK olmalı |

Audit eylemleri (`target_type: apartment`): `apartment_mgmt.tenant_added | tenant_invited | tenant_invite_accepted | family_added | family_invited | family_removed | member_removal_requested | member_removal_approved | management_delegated | tenant_exit | disconnect_requested | disconnect_approved | member_left | proxy_created | proxy_revoked | owner_recorded | admin_changed_by_manager`. Kişi araması: `apartment_mgmt.person_search` (maskeli sorgu).

## Araçlar ("Dairem > Araçlarım")

Aracı yalnız site yöneticisi değil, **daire admini de** girer ("bu işler sırf site yöneticisine kalmasın"); site yöneticisi de yapabilir. Kod: `src/modules/apartment_mgmt_vehicles.js`
(plaka / not / kayıt biçimi mevcut `people_common` ve `plate_recognition_common` kurallarını, listeleme ve kaynak etiketi `vehicle_service.js`'i kullanır). Yeni tablo ya da migration YOKTUR:
araç `vehicles` satırıdır; daire yöneticisinin eklediği araçta mevcut `apartment_id` kolonu bu daireye bağlanır.

| Kim | Ne yapar |
|---|---|
| Daire admini (dairede oturan: kiracı varsa kiracı, yoksa malik) | KENDİ dairesi adına araç ekler, notu / sahibi düzenler, aracı çıkarır (pasife alır) |
| Aile üyesi, admin olmayan malik / kiracı | dairenin araçlarını yalnız GÖRÜR; ekleme / düzenleme / çıkarma 403 `FORBIDDEN_ROLE` |
| Site yöneticisi / süper | mevcut Kişiler > Araçlar ekranı aynen kalır; ayrıca aynı uçlarla da yazabilir (kaynak etiketi "Site yönetimi") |
| Dairede bağı olmayan | 404 `APARTMENT_NOT_FOUND` (dairenin varlığı sızdırılmaz); başka dairenin aracı 404 `VEHICLE_NOT_FOUND` |

Kurallar:

1. **Sınır**: daire başına en çok **4** aktif araç (site yöneticisi için **8**); aşılırsa 409 `VEHICLE_LIMIT`. Çıkarılan araç yer açar.
2. **Plaka**: geçerli Türk plakası (il kodu 01-81 + 1-3 harf + 2-4 rakam, `plate_recognition_common.TR_PLATE_RE`); aksi 400 `PLATE_INVALID`. Plaka kaydedildikten sonra DEĞİŞMEZ (çıkarılıp yeniden eklenir). Not en çok 200 karakter (marka / model / renk).
3. **Tekillik**: aynı sitede aynı plaka bir kez (mevcut kısmi tekil indeks `uq_vehicles_plate`; site kilidi altında). Plaka başka bir kayıtta kullanılıyorsa 409 `PLATE_IN_USE` ve iletide hiçbir daire / kişi bilgisi yoktur:
   "Bu plaka başka bir kayıtta kullanılıyor; site yönetimiyle görüşün." Aynı dairenin kendi aracıysa 409 `PLATE_EXISTS`.
4. **Sahip**: dairenin aktif sakinlerinden biri (`person_id`; varsayılan daire admini). Başka dairenin kişisi 409 `NOT_AN_ACTIVE_RESIDENT`. Kapı erişimi askıya alınmış admin yazamaz.
5. **Hız sınırı**: yazma uçları kullanıcı başına saatte 60 (plaka denemesiyle başka kayıtları yoklamayı sınırlar).
6. **Audit**: `vehicle.added | vehicle.updated | vehicle.removed` (`target_type: vehicle`); plaka MASKELİ (`34***23`), `details`: `apartment_id`, `person_id`, `source` (`apartment_admin` | `site_manager`).
   Kaynak etiketi ayrı kolonda değil audit'te tutulur; `GET .../vehicles` ve site yöneticisinin Araçlar ekranı bunu `source` / `added_by` olarak gösterir ("Ekleyen: Daire yöneticisi (Ad) / Site yönetimi").
   Eski kayıtlar (ve yönetici ekranından eklenenler) `apartment_id` boş olduğundan "Site yönetimi" sayılır.

**ÖNEMLİ ETKİ**: kayıtlı aktif araç plaka tanıma modülünde **yetkili araç** sayılır (`plate_recognition_service` aktif araç listesi). Bu yüzden admin yalnız KENDİ dairesi adına ekler ve ekranda
"Eklediğiniz plaka, sitede plaka tanıma açıksa yetkili araç sayılır." uyarısı yazar. Kara liste (blacklist) araç kaydından üstündür; yani eklenen plaka kara listedeyse yine izinli olmaz.
Kapı açma kodu (kapı komutları, MQTT, BLE, firmware, kapı servisleri) bu özellikte DEĞİŞMEZ.

Kapsam kararı ("daire düzeyinde yalnız site yöneticisinin yaptığı işler" incelemesi): yetkisi admine açılan tek diğer iş yoktur; kendi telefon / e-postasını zaten Profilim'den değiştirir.
Mali / yapısal alanlar (arsa payı, aidat, borç sorumlusu, daire silme / birleştirme, PIN sıfırlama) SİTE YÖNETİCİSİNDE KALIR (m² sistemden kaldırıldı).

## Site yöneticisi: "Daire adminini değiştir"

Kişiler > Daireler > daire kartı > "Daire adminini değiştir" -> aktif sakin listesi (malik, kiracı, aile üyesi: dairede AKTİF bağı olan) -> onay ("Daire admini X yerine Y olacak").
Sunucu: yetki site yöneticisi / süper (kurul ve görevli 403, başka site 403, başka sitenin dairesi 404). Eski admin dairede KALIR (bağı silinmez, kapı erişimi değişmez); yalnız yönetim yetkisi geçer.
Malik-kiracı "kiracı çıkana kadar geri alınamaz" kuralı site yöneticisini BAĞLAMAZ (acil durum / anlaşmazlık müdahalesi). Audit `apartment_mgmt.admin_changed_by_manager`; eski ve yeni admine uygulama içi bildirim (`apartment_notices`).

## Site yöneticisi: dairenin sakinleri (Site Yönetimi > Daireler)

Eski sorun: Site Yönetimi'nin yapı ucu (`GET /sites/:id/structure`) daire satırına yalnız eski tek-sakin göstergesini (`apartments.resident_user_code` -> `resident_*` alanları) verdiği için dairede tek kişi görünüyordu.
Çözüm (salt okunur, migration YOK): `GET /manager/sites/:siteCode/apartments/:id/household` (`src/modules/apartment_mgmt_household.js`) dairenin güncel kişilerini tek istekte verir:
`{ apartment_id, label, detail: 'full'|'basic', admin, absent_owner, members[], total }`. Kaynak: `apartment_residencies` (is_current; hesapsız çocuk / yaşlı dahil) + `apartment_memberships` + eski gösterge;
admin `resolveApartmentRoles` ile çözülür. Kiracı varsa ve malik admin değilse malik `absent_owner` ("Malik (oturmuyor)") olur.

- Yetki: `resolvePeopleAccess` (okuma): yönetici / süper `detail: 'full'` (telefon, `is_minor`, `has_account`, `access_suspended` = açık askıya alma kaydı ya da pasife alınmış üyelik);
  kurul üyesi `detail: 'basic'` (YALNIZ `person_id`, `name`, `relation`, `is_admin`). Görevli / sakin 403 `FORBIDDEN_ROLE`, başka sitenin yöneticisi 403 `FORBIDDEN_SITE`, başka sitenin dairesi 404 `APARTMENT_NOT_FOUND`. Kullanıcı kodu hiçbir durumda dönmez.
- Yapı ucu eski `resident_*` alanlarını AYNEN korur; ek olarak daire satırına `household_count` (güncel kişi sayısı, tek toplu sorgu) eklenir. Eski istemci bu alanı yok sayar.
- İlişki türleri `owner | tenant | family_member | resident`; "eş / yaşlı ebeveyn" ayrımı sunucuda tutulmaz. Küçük (`is_minor`) "Çocuk" olarak gösterilir.
- Uygulama: `ApartmentCard` (Site Yönetimi) daire açılınca bu ucu çağırır; üstte daire admini, altında "Aile üyeleri (N)" akordiyonu; kişi satırı kişi kartını, "Daire kartı" düğmesi daire kartını (admin değiştir, kapı erişimi askısı, adli kayıt, geçmiş) açar.

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
7. Hesap silinen kişide talepler CASCADE temizlenir; vekil kiracı çıkınca vekalet iptal olur (kapanış yoluna göre `revoked_reason` `residency_<neden>` ya da `tenant_left`; bkz. «Yönetim devrinin geçerliliği ve kapanması»).
8. Vekalet kaydı iç kayıttır (yukarıdaki [AVUKAT DOĞRULASIN]).

## KVKK

Kişi arama yalnız maskeli veri döner ve her arama maskeli sorguyla denetim kaydına yazılır. Davetle kişinin onayı olmadan hiçbir bağ kurulmaz. Aile üyesi finans bilgisini görmez. Güvenlik talebi ve askıya alma
kayıtları özel hassasiyetli sayılır (güvenlik politikası belgesi).

## Askıya alınmış kişinin katılım başvurusu (2026-10-26, koddan doğrulandı)

Site yönetiminin kapı erişimini askıya aldığı kişinin (`apartment_access_suspensions`, `lifted_at IS NULL`) dairede erişimi katılım yoluyla geri alması engellenir (`membership_service.js` `hasOpenAccessSuspension`, `suspendedHttpError`):

- Katılım QR'ı ile başvuru: `403` ve `code: 'ACCESS_SUSPENDED'` («Bu daireye şu anda başvuru yapılamıyor. Site yönetimine başvurun.»). Askının nedeni gösterilmez.
- Bekleyen katılım başvurusunu onaylamak: askı sonradan konmuş ya da başvuru askılı kişiden gelmişse onay `409` ve `code: 'ACCESS_SUSPENDED'` ile reddedilir (onay üyeliği yeniden aktifleştirirdi); yönetici askıyı kaldırana dek bekler ya da başvuruyu reddeder.
- Daire adminin askılı üyeyi yeniden etkinleştirmesi de reddedilir (`403`, genel ileti, kodsuz).

## Site yapısı küçültülürken dolu daire koruması (`APARTMENT_OCCUPIED`; 2026-10-26, koddan doğrulandı)

Daire sayısını azaltan yapı düzenlemesi (`PATCH /admin/sites/:id` süper kullanıcı, `PATCH /manager/sites/:id` site yöneticisi; `site_service.syncSiteStructureCounts`) silinecek TÜM daireleri hiçbir şey silinmeden ÖNCE denetler (`assertApartmentsRemovable`; adaylar `FOR UPDATE` ile ve id sırasıyla kilitlenir). Biri bile doluysa işlem `409` ve `code: 'APARTMENT_OCCUPIED'` ile durur, geri alınır ve hiçbir şey silinmez. İleti dolu daireleri ve nedenlerini sayar (en çok 10; yanıtta `apartments` listesi).

Dolu sayılma nedenleri: aktif sakin (eski `resident_user_code` göstergesi dahil), güncel sakin kaydı (`apartment_residencies.is_current`), aktif üyelik (`apartment_memberships`), kapı erişimi askı kaydı (açık ya da kaldırılmış herhangi biri), çözülmemiş güvenlik talebi (`status <> 'resolved'`). Bu kayıtlar daire silinince CASCADE ile geri dönüşsüz giderdi. Boş dairelerin silinmesi (anlık görüntü + denetim yolu) aynen sürer; mali kaydı olan daire için ayrıca 409 `APARTMENT_HAS_FINANCE` kuralı geçerlidir. Sakinler önce daireden çıkarılmalı, askı ve güvenlik kayıtları sonuçlandırılmalıdır.

## Bilinen sınırlar

- Uygulama içi bildirim kutusu vardır; telefon bildirimi (push) ve e-posta bu olaylar için gönderilmez.
- Kurul üyesi atama ekranında vekil için özel bir seçici yoktur; imza listesi vekili gösterir, atama mevcut Kadro ekranından yapılır.
- Eski `getMyApartments` (Daire Kullanıcıları ekranı) üyelerin e-posta / telefonunu aynı dairedekilere gösterir; bu özellikte değiştirilmedi.
- Daireden ayrılan / çıkarılan kişinin araçları kendiliğinden pasifleşmez (mevcut CRM davranışı); yeni daire admini "Araçlarım"dan çıkarır. Site yöneticisinin eski Kişiler > Araçlar uçları 4/8 sınırını ve katı Türk plakası kuralını uygulamaz (davranış değişmedi).
- Gerçek PostgreSQL ile uçtan uca sınama yapılmadı (saf kural testleri, şema / migration eşitliği ve kaynak denetimleri var).

## Doğrulama

`server/test/apartment_mgmt.test.js` (şema <-> migration, admin çözümleme, devir, vekalet, imza hakkı, arama gizliliği, yetişkin üye kuralı), `server/test/apartment_mgmt_vehicles.test.js` (araçlar: yetki, limit, tekil plaka, mesaj sızdırmama), `test/screens/my_apartment_view_test.dart`.


---

## Daire Sakini İlk Şifre ve Zorunlu Şifre Değişimi (`must_change_password`)

Toplu yüklemeyle (`people` / `all_in_one`) açılan hesaplar, kişi kartından site yöneticisinin atadığı hesaplar (`POST /manager/sites/:siteCode/people/:personId/account`, varsayılan geçici şifre `1234`) ve PIN'i oluşturulan / sıfırlanan daire hesapları için:
1. Başlangıç şifresi (varsayılan `1234` veya Excel'de belirtilen değer) tanımlanır ve bcrypt ile hashlenir.
2. `users.must_change_password = TRUE` ve `apartments.resident_pin_issued = TRUE` olarak işaretlenir.
3. Sakin mobil veya web uygulamada oturum açtığında `authService.session.mustChangePassword == true` ise ekrana zorunlu `ForceChangePasswordDialog` açılır. Bayrak, `users.must_change_password` VEYA hesabın sakin göstergesi olduğu dairede `apartments.resident_pin_issued = TRUE` olmasıdır (`auth_middleware.js`).
4. Sakin kendi belirlediği kalıcı şifreyi girip kaydetmeden diğer ekranlara devam edemez. Zorunluluk SUNUCUDA uygulanır: bayrak açıkken `GET /me`, `PATCH /me`, `GET|POST /me/consents`, daire sakininin kendi şifresini değiştirme ucu ve telefon bildirimi cihaz kaydını silme dışındaki tüm kimlik doğrulamalı uçlar `403 PASSWORD_CHANGE_REQUIRED` döner (API doğrudan kullanılarak da atlanamaz). Başarılı güncelleme sonrası `must_change_password = FALSE` olur ve bayrak sıfırlanır.
5. Sakin ayrıca dilediği zaman "Profilim" ekranındaki "Şifremi Değiştir" kartından şifresini güncelleyebilir.
