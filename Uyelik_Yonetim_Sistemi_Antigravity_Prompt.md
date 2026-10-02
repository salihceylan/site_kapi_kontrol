# ÜYELİK YÖNETİM SİSTEMİ – ANTIGRAVITY AJAN GÖREV DOSYASI

## 1. ÇALIŞMANIN KİMLİĞİ

Bu çalışma proje içinde bağımsız bir iş paketi olarak ele alınacaktır.

**Çalışma adı:** `Üyelik Yönetim Sistemi`

> KRİTİK: Projede hâlihazırda devam eden ve **4. aşamada bulunan başka bir çalışma vardır.**
>
> Bu dosya kapsamında yapılacak işler o 4. aşamanın devamı değildir.
>
> Önce bu **Üyelik Yönetim Sistemi** eksiksiz şekilde tamamlanacak, test edilecek ve mevcut çalışan sistemin bozulmadığı doğrulanacaktır.
>
> Üyelik Yönetim Sistemi tamamlandıktan sonra, daha önce devam eden ana çalışma **4. aşamadan kaldığı yerden devam edecektir.**
>
> Ajan mevcut 4. aşamadaki işi silmeyecek, yeniden yorumlamayacak, numarasını değiştirmeyecek ve bu üyelik sistemi çalışmasını “4. aşama” olarak etiketlemeyecektir.

Bu çalışmanın görev/commit/not başlıklarında mümkün olduğunca:

`[ÜYELİK YÖNETİM SİSTEMİ]`

etiketi kullanılmalıdır.

---

# 2. EN ÖNEMLİ KURAL: ÇALIŞAN SİSTEM BOZULMAYACAK

Bu proje hâlihazırda çalışan bir sistemdir.

Ajanın temel görevi mevcut yapıyı yeniden yazmak değil, yeni üyelik yönetim modelini mevcut sistemin yanına güvenli ve modüler şekilde eklemektir.

Özellikle aşağıdaki çalışan işlevler korunacaktır:

- ESP32 cihazlarının internete bağlanma mekanizması
- mevcut Wi‑Fi bağlantı akışı
- mevcut Bluetooth bağlantı akışı
- çalışan kapı açma mekanizması
- mevcut cihaz–backend haberleşmesi
- çalışan MQTT/SIP/kapı tetikleme akışları
- mevcut QR ile kapı açma çalışmalarında çalışan kodlar
- sahada bulunan eski ESP32‑C3 cihazlarının çalışma mantığı
- mevcut kullanıcıların çalışan girişleri
- mevcut API'lerin çalışan bölümleri
- mevcut uygulama ekranlarında çalışan özellikler

Yeni özellik eklemek için çalışan bir modül gereksiz yere yeniden yazılmamalıdır.

Mevcut kodda değişiklik zorunluysa:

1. Önce ilgili kod incelenecek.
2. Değişikliğin etkilediği alanlar belirlenecek.
3. Mümkün olan en küçük değişiklik yapılacak.
4. Geriye dönük uyumluluk korunacak.
5. Değişiklikten sonra eski davranış ayrıca test edilecek.

---

# 3. ÇALIŞMA YÖNTEMİ

Bu görev tek seferde büyük çaplı refactor yapılarak tamamlanmayacaktır.

Her özellik:

`incele → küçük değişiklik yap → çalıştır → test et → doğrula → sonraki adıma geç`

şeklinde ilerletilecektir.

Ajan hiçbir aşamada:

- bütün kullanıcı sistemini bir anda silip yeniden yazmamalı,
- çalışan tabloları doğrudan kaldırmamalı,
- mevcut API'leri sebepsiz yere kırmamalı,
- mevcut rollerin davranışını doğrulamadan değiştirmemeli,
- eski mobil uygulama akışını test etmeden yeni akışa zorlamamalıdır.

Gerekli yerlerde yeni tablolar, yeni servisler, yeni repository/service katmanları ve feature flag kullanılmalıdır.

---

# 4. YENİ ÜYELİK SİSTEMİNİN TEMEL FELSEFESİ

Yeni sistemde artık Süper User tarafından:

- site oluşturulmayacak,
- site yöneticisi oluşturulmayacak,
- daire kullanıcıları otomatik oluşturulmayacak,
- daireler için kullanıcı adı ve şifre üretilmeyecek,
- kullanıcı listeleri PDF oluşturulup başka bir yere gönderilmeyecek.

Sistem **self-service** çalışacaktır.

Her gerçek kişi önce kendi hesabını oluşturacaktır.

Bir kullanıcının sistemdeki rolü global bir kullanıcı tipi olarak düşünülmemelidir.

Aynı kullanıcı:

- bir sitede Site Sahibi,
- başka bir sitede Site Yöneticisi,
- başka bir sitede Daire Admini,
- başka bir sitede Aile Üyesi

olabilir.

Bu nedenle roller **kullanıcı–site / kullanıcı–daire ilişkileri üzerinden** tutulmalıdır.

---

# 5. NORMAL KULLANICI KAYIT AKIŞI

Yeni hesap kayıt ekranında aşağıdaki alanlar bulunacaktır:

- Ad
- Soyad
- E-posta
- Şifre
- Şifre tekrar

Kullanıcı kayıt olduktan sonra e-posta adresine:

**4 haneli sayısal doğrulama kodu**

gönderilecektir.

Örnek:

`4837`

Kurallar:

- Kod 4 rakam olacaktır.
- Kullanıcı e-postasını doğrulamadan siteye katılamaz.
- Kullanıcı e-postasını doğrulamadan cihaz sahiplenemez.
- Doğrulama kodunda süre sınırı uygulanmayacaktır.
- Yeni doğrulama kodu oluşturulduğunda önceki kod geçersiz hale getirilebilir.
- Kaba kuvvet denemelerine karşı backend tarafında makul deneme sınırlaması kullanılabilir.
- Kullanıcı başarılı doğrulamadan sonra `email_verified = true` durumuna geçecektir.

Kullanıcıya kayıt sırasında:

- "Site yöneticisiyim"
- "Daire kullanıcısıyım"

gibi global rol seçimi yaptırılmayacaktır.

---

# 6. KULLANICI ANA EKRANI

E-postası doğrulanmış fakat hiçbir site ilişkisi bulunmayan kullanıcı için sade bir başlangıç ekranı hazırlanmalıdır.

Temel seçenekler:

- `Cihaz Ekle`
- `Siteye Katıl`
- `Sitelerim`

Kullanıcı daha sonra birden fazla siteye bağlı olabilmelidir.

---

# 7. CİHAZ QR KODU VE CİHAZ SAHİPLENME

Fiziksel cihazın QR kodu cihazın kapıya monte edilmiş gövdesinde bulunmayacaktır.

QR kod **cihazın ambalaj kutusunda** olacaktır.

Bu QR kod şimdilik yalnızca cihazın kimliğini içerir:

`device_id`

Örnek:

`GD-C3-8A72F931`

Bu görev kapsamında cihaz QR güvenliği ayrıca yeniden tasarlanmayacaktır.

**Bu konu şimdilik kapsam dışıdır.**

Ajan QR'ın yalnızca device_id içermesi kararını değiştirmeye çalışmamalıdır.

Kullanıcı:

`Cihaz Ekle`

dediğinde QR'ı okutur.

Backend:

1. cihazın kayıtlı olup olmadığını,
2. aktif olup olmadığını,
3. başka bir site/hesapla ilişkilendirilmiş olup olmadığını

kontrol eder.

İlk başarılı sahiplenme işleminden sonra cihaz kullanıcı hesabıyla ilişkilendirilebilir.

Ancak cihazı sahiplenmek ile site üyeliği aynı kavram değildir.

---

# 8. SİTE OLUŞTURMA AKIŞI

Cihazı ilk kez ekleyen kullanıcı, cihazın kontrol paneline erişim hakkı kazanacaktır.

Bu kullanıcı site oluşturma sürecini başlatabilir.

Site oluşturulurken:

- Site adı girilir.
- Site daha sonra yeniden adlandırılabilir.
- Kullanıcı birden fazla site oluşturabilir/yönetebilir.
- Bir yönetim firması hesabı istediği kadar site yönetebilir.

Site oluşturulduktan sonra ilgili kullanıcı o site için:

`SITE_OWNER`

veya eşdeğer **Site Sahibi** rolüne sahip olacaktır.

İleride ayrıca Site Yöneticileri eklenebilmelidir.

---

# 9. BLOK YÖNETİMİ

Site sahibi/yöneticisi:

- yeni blok oluşturabilmeli,
- blok adını belirleyebilmeli,
- blok adını daha sonra değiştirebilmeli,
- sonradan yeni blok ekleyebilmelidir.

Örnek:

- A Blok
- B Blok
- C Blok

Bloklar siteye bağlı ayrı veri nesneleri olmalıdır.

---

# 10. DAİRE YÖNETİMİ

Her blok altında daireler oluşturulacaktır.

Örnek:

`A Blok → Daire 1, Daire 2, Daire 3...`

Daire:

- kullanıcıdan bağımsız kalıcı bir nesnedir,
- içine sonradan kullanıcılar bağlanır,
- kullanıcı ayrıldığında daire silinmez.

Daire üyelikleri ayrı ilişki tablosuyla tutulmalıdır.

---

# 11. KAPI İLE CİHAZ AYRI NESNELERDİR

Bu mimarinin en önemli kurallarından biri:

**KAPI ≠ CİHAZ**

olmasıdır.

Kapı fiziksel erişim noktasıdır.

Cihaz ise o kapıyı kontrol eden elektronik donanımdır.

Örnek:

`Kapı: A Blok Ana Giriş`

`Cihaz: GD-C3-8A72F931`

Kapı aynı kalırken cihaz değiştirilebilir.

Kullanıcı erişimleri mümkün olduğunca kapıya verilmelidir; doğrudan cihaz kimliğine bağlanmamalıdır.

---

# 12. BİR SİTEDE BİRDEN FAZLA KAPI

Sistem bir site için tek kapı varsaymamalıdır.

Bir sitede örneğin:

- Site Ana Giriş 1
- Site Ana Giriş 2
- Garaj Kapısı
- A Blok Giriş
- A Blok Arka Giriş
- B Blok Giriş
- C Blok Giriş

bulunabilir.

Kapı sayısı mimaride sabitlenmemelidir.

---

# 13. KAPI OLUŞTURMA VE İSİMLENDİRME

Site sahibi/yöneticisi:

- yeni kapı oluşturabilmeli,
- kapıya isim verebilmeli,
- kapının adını daha sonra değiştirebilmeli,
- kapının türünü/kapsamını belirleyebilmelidir.

Kapı için en az aşağıdaki erişim kapsamları desteklenmelidir:

### SITE_COMMON

Sitede onaylı tüm sakinlerin otomatik erişebildiği ortak kapı.

Örnek:

- Site Ana Giriş 1
- Site Ana Giriş 2

### BLOCK

Belirli bir blok sakinlerinin otomatik erişebildiği kapı.

Örnek:

`A Blok Giriş → A Blok`

### RESTRICTED / CUSTOM

Sadece site yöneticisinin ayrıca yetkilendirdiği kullanıcıların/grupların erişebildiği kapı.

Örnek:

- Garaj
- Teknik oda
- Personel bölümü

Garajın ortak veya özel olması sabit kodlanmamalıdır; yönetici tarafından yapılandırılabilmelidir.

---

# 14. CİHAZIN KAPIYA ATANMASI

Cihaz sahiplenildikten sonra mevcut veya yeni oluşturulan bir kapıya atanır.

Örnek:

`Güneş Sitesi`
→ `Site Ana Giriş 1`
→ `GD-C3-8A72F931`

Bir sitede birden fazla cihaz bulunabilir.

Her cihaz doğru kapıyla ilişkilendirilmelidir.

---

# 15. ARIZALI CİHAZI DEĞİŞTİRME

Bu özellik zorunludur.

Site yönetimi ekranında her kapıda:

`Cihazı Değiştir`

butonu bulunmalıdır.

Akış:

1. Yönetici ilgili kapıyı açar.
2. `Cihazı Değiştir` seçer.
3. Yeni cihazın kutusundaki QR okutulur.
4. Yeni device_id backend tarafından doğrulanır.
5. Kullanıcıdan onay alınır.
6. Yeni cihaz mevcut kapıya bağlanır.
7. Eski cihaz pasif/değiştirilmiş olarak işaretlenir.

KRİTİK:

Cihaz değiştirildiğinde:

- kapı ID'si değişmemeli,
- site yapısı değişmemeli,
- kullanıcı erişimleri silinmemeli,
- daire erişimleri yeniden oluşturulmak zorunda kalmamalı,
- çalışan site üyelikleri bozulmamalıdır.

---

# 16. SİTE KATILIM QR KODU

Site kurulumu tamamlandıktan sonra sistem otomatik bir:

`Site Katılım QR Kodu`

üretecektir.

Bu QR kodun görevi yalnızca siteye üyelik talebi başlatmaktır.

Bu QR:

- kapı açmaz,
- cihaz eklemez,
- kullanıcıya otomatik yetki vermez,
- kullanıcıyı otomatik site üyesi yapmaz,
- kullanıcıyı yönetici yapmaz.

Site yöneticisi bu QR'ı daire sakinlerine dağıtabilir.

Site katılım QR kodu kalıcı olabilir.

Site yöneticisi gerektiğinde mevcut QR'ı iptal edip yeni QR oluşturabilmelidir.

---

# 17. SİTEYE KATILMA AKIŞI

Bir daire sakini önce normal kullanıcı hesabını oluşturmuş ve e-postasını doğrulamış olmalıdır.

Daha sonra:

1. `Siteye Katıl` seçilir.
2. Site Katılım QR kodu okutulur.
3. Site bilgisi gösterilir.
4. Kullanıcı blok seçer.
5. Kullanıcı daire seçer.
6. `Katılım Talebi Gönder` seçilir.

Arayüz:

`Blok: [ A Blok ▼ ]`

`Daire: [ Daire 12 ▼ ]`

şeklinde sade dropdown yapısıyla hazırlanmalıdır.

Kullanıcı siteye üye değilken diğer sakinlerin isimleri gösterilmemelidir.

---

# 18. KATILIM TALEBİ

Katılım talebi site yönetimine bildirim olarak ulaşmalıdır.

Örnek:

`Yeni Daire Katılım Talebi`

`Salih Ceylan`

`A Blok / Daire 12`

Site yöneticisi:

- Onayla
- Reddet

işlemlerini yapabilmelidir.

Önerilen talep durumları:

- PENDING
- APPROVED
- REJECTED
- CANCELLED

Gerekirse daha sonra genişletilebilir.

Aynı kullanıcının aynı site için birbiriyle çakışan birden fazla bekleyen talep oluşturmasına izin verilmemelidir.

---

# 19. DAİRE ADMINI

Bir daireye **ilk onaylanan kullanıcı**:

`APARTMENT_ADMIN`

veya kullanıcı arayüzünde:

`Daire Admini`

olarak işaretlenmelidir.

Buradaki kural:

**ilk başvuran değil, ilk ONAYLANAN kullanıcı**

Daire Admini olur.

Backend onaylama sırasında dairede aktif Daire Admini olup olmadığını yeniden kontrol etmelidir.

---

# 20. AİLE ÜYELERİ

Aynı daireye daha sonra katılımı onaylanan kullanıcılar:

`FAMILY_MEMBER`

olarak işaretlenecektir.

Örnek:

A Blok / Daire 12

- Salih Ceylan — Daire Admini
- Ayşe Ceylan — Aile Üyesi
- Ali Ceylan — Aile Üyesi

Daire Admini kendi dairesine daha sonra eklenen aile üyelerini uygulama içerisinde görebilmelidir.

Bu görev kapsamında Daire Admininin aile üyelerini onaylama/silme yetkisi zorunlu değildir.

Şimdilik temel gereksinim:

**Daire Admini aile üyelerini görebilsin.**

---

# 21. OTOMATİK KAPI ERİŞİMİ

Bir kullanıcı belirli bir bloktaki daireye onaylandığında erişim hakları otomatik hesaplanmalıdır.

Örnek:

Kullanıcı:

`A Blok / Daire 12`

üyesidir.

Otomatik erişim:

- Site Ana Giriş 1 ✅
- Site Ana Giriş 2 ✅
- A Blok Giriş ✅
- A Blok Arka Giriş ✅
- B Blok Giriş ❌
- C Blok Giriş ❌

Kural:

`Onaylı site üyesi`
→ tüm `SITE_COMMON` kapıları

`A Blok üyesi`
→ A Blok'a atanmış tüm `BLOCK` kapıları

---

# 22. DİĞER BLOKLARA EK ERİŞİM

Normal kullanıcı kendi kendine başka blok erişimi alamaz.

Sadece Site Sahibi / Site Yöneticisi kullanıcıya başka blokların kapılarına erişim verebilir.

Örnek:

A Blok kullanıcısına yönetici ayrıca:

- B Blok Giriş
- B Blok Arka Giriş

yetkisi verebilir.

Bu ek erişimler otomatik blok erişiminden ayrı tutulmalıdır.

Öneri:

- automatic permissions
- manual overrides / extra permissions

mantığı kullanılabilir.

---

# 23. TOPLU YETKİLENDİRME

Site yöneticisi kullanıcıları toplu seçebilmelidir.

Örnek:

- A Blok sakinlerinin tamamını seç
- belirli daireleri seç
- belirli kullanıcıları seç

ve ardından:

`Ek Erişim Ver`

ile:

- Garaj
- B Blok
- başka özel kapı

yetkisini toplu verebilmelidir.

Toplu yetki kaldırma da desteklenmelidir.

---

# 24. SAKİN LİSTESİ – PDF KALKACAK

Eski sistemde kullanıcı listesinin PDF'e dönüştürülerek bir yere gönderilmesi yaklaşımı artık kullanılmayacaktır.

Yeni sistemde Site Yöneticisi sakinleri doğrudan uygulama içinde görecektir.

Liste **akordiyon yapıda** hazırlanmalıdır.

Örnek:

`▶ A Blok — 48 sakin`

Açılınca:

`▶ Daire 1 — 3 kişi`

`▶ Daire 2 — 2 kişi`

`▼ Daire 12 — 4 kişi`

- Salih Ceylan — Daire Admini
- Ayşe Ceylan — Aile Üyesi
- Ali Ceylan — Aile Üyesi
- Zeynep Ceylan — Aile Üyesi

PDF üretme/gönderme bağımlılığı kaldırılacaktır.

Ancak mevcut çalışan eski özellik herhangi bir yerde kullanılıyorsa, doğrulanmadan fiziksel olarak silinmemelidir; önce yeni ekran devreye alınmalı, sonra eski kullanımın gereksiz olduğu teyit edilmelidir.

---

# 25. ÇOKLU SİTE YÖNETİMİ

Bir kullanıcı / yönetim firması istediği kadar site yönetebilmelidir.

Sistem:

`user.site_id`

gibi tek siteye kilitleyen bir veri modeli kullanmamalıdır.

Bunun yerine ilişki bazlı yapı kullanılmalıdır.

Örnek:

| Kullanıcı | Site | Rol |
|---|---|---|
| Mehmet | Güneş Sitesi | OWNER |
| Mehmet | Deniz Sitesi | ADMIN |
| Mehmet | Ege Residence | ADMIN |

Ana ekranda:

`Yönettiğim Siteler`

alanı bulunabilir.

---

# 26. AYNI KULLANICININ BİRDEN FAZLA SİTEDE YAŞAMASI

Bir kullanıcı birden fazla sitenin sakini de olabilir.

Örnek:

Salih:

- Güneş Sitesi → A Blok / Daire 12 → Daire Admini
- Yazlık Sitesi → C Blok / Daire 7 → Aile Üyesi

Bu destek baştan veri modeline dahil edilmelidir.

---

# 27. SITE OWNER VE SITE ADMIN AYRIMI

Cihazı ilk sahiplenip siteyi kuran kişi:

`SITE_OWNER`

olmalıdır.

Bu rol site üzerindeki ana sahiplik rolüdür.

Daha sonra OWNER başka doğrulanmış kullanıcılara:

`SITE_ADMIN`

yetkisi verebilmelidir.

Bir sitenin birden fazla yöneticisi olabilir.

Ancak ana sahiplik ve yönetici rolü veri modelinde ayrı tutulmalıdır.

Bu özellik ilk UI sürümünde tamamlanmasa bile veri modeli ileride bunu destekleyecek şekilde tasarlanmalıdır.

---

# 28. ÖNERİLEN VERİ MODELİ

Mevcut veritabanını doğrudan bozmak yerine önce mevcut tablolar analiz edilmelidir.

Yeni yapı için aşağıdaki kavramlara ihtiyaç vardır:

- users
- email_verifications
- sites
- site_memberships
- blocks
- apartments
- apartment_memberships
- doors
- devices
- door_device_assignments
- site_join_codes / site_join_qr
- join_requests
- access_permissions
- access_overrides
- audit_logs

Bu tablo isimleri zorunlu değildir.

Mevcut projedeki adlandırma standardına uyulabilir.

Ancak kavramsal ayrımlar korunmalıdır.

Özellikle:

- user ≠ site
- user ≠ apartment
- door ≠ device
- site role ≠ global user role
- apartment membership ≠ user account
- automatic access ≠ manual extra access

---

# 29. ESKİ SİSTEMLE GERİYE DÖNÜK UYUMLULUK

Mevcut kullanıcı sistemi bir anda silinmemelidir.

Önce:

1. mevcut auth sistemi incelenecek,
2. mevcut users tablosu incelenecek,
3. mevcut roller incelenecek,
4. mevcut API'ler listelenecek,
5. yeni modelin mevcut yapı ile nasıl yaşayacağı belirlenecek.

Gerekirse yeni sistem:

`membership_v2`

veya benzeri feature flag ile devreye alınabilir.

Eski sahadaki kullanıcılar ve cihazlar çalışmaya devam etmelidir.

---

# 30. FLUTTER ARAYÜZ KURALLARI

Yeni ekranlarda:

- RenderFlex overflow oluşturulmayacak.
- Sabit ekran yüksekliğine güvenilmeyecek.
- Küçük ekranlar desteklenecek.
- Scroll gerektiren alanlarda uygun scroll widget kullanılacak.
- Klavye açıldığında form alanları taşmayacak.
- Uzun site/blok/kapı isimleri UI'ı bozmayacak.
- Dropdown içerikleri ekrana taşmayacak.
- Akordiyon listeleri performanslı hazırlanacak.
- Responsive yapı korunacak.

---

# 31. MODÜLERLİK

Yeni üyelik sistemi ayrı modüller halinde hazırlanmalıdır.

Örnek mantıksal modüller:

- auth / email verification
- membership
- site management
- block management
- apartment management
- door management
- device assignment
- join request
- access control
- resident list

Bir dosyada veya serviste bütün iş mantığı toplanmamalıdır.

UI doğrudan veritabanı detaylarını bilmemelidir.

Mümkün olan yerlerde mevcut projenin:

- service
- repository
- provider
- controller
- state management

desenleri korunmalıdır.

---

# 32. API DEĞİŞİKLİKLERİNDE KURAL

Mevcut çalışan endpoint'i değiştirmek yerine mümkün olduğunda:

- yeni endpoint,
- yeni version,
- opsiyonel alan,
- geriye uyumlu response

tercih edilmelidir.

Mevcut mobil uygulamanın kullandığı response alanları sebepsiz yere kaldırılmamalıdır.

---

# 33. AUDIT / İŞLEM KAYDI

En azından aşağıdaki kritik işlemler kaydedilebilir olmalıdır:

- cihaz ilk sahiplenme
- cihaz değiştirme
- site oluşturma
- site adı değiştirme
- blok oluşturma
- blok adı değiştirme
- kapı oluşturma
- kapı adı değiştirme
- kullanıcı katılım talebi
- talep onayı
- talep reddi
- ek erişim verme
- ek erişim kaldırma

Audit sistemi mevcut projede varsa kullanılmalıdır.

Yoksa ilk aşamada minimum log yapısı kurulabilir.

---

# 34. UYGULAMA ADIMLARI

Ajan aşağıdaki sırayla ilerlemelidir.

## ÜYS-0 — MEVCUT SİSTEMİ İNCELE

Henüz kod değiştirme.

Belirle:

- mevcut auth yapısı
- users modeli
- rol sistemi
- site modeli
- cihaz modeli
- kapı açma akışı
- API'ler
- Flutter state management yapısı
- mevcut migration sistemi
- mevcut QR işlemleri

Sonunda kısa teknik not çıkar.

---

## ÜYS-1 — VERİ MODELİ

Mevcut yapıyı bozmadan yeni üyelik ilişkilerini ekle.

Önce migration/model testleri.

Uygulama ekranlarında büyük değişiklik yapma.

---

## ÜYS-2 — YENİ KULLANICI KAYDI VE E-POSTA DOĞRULAMA

- Ad
- Soyad
- E-posta
- Şifre
- Şifre tekrar
- 4 haneli mail doğrulama

tamamla.

Eski giriş sistemini bozma.

---

## ÜYS-3 — CİHAZ SAHİPLENME

`Cihaz Ekle`

ve cihaz QR → device_id akışını hazırla.

Mevcut ESP32 haberleşme koduna dokunma.

---

## ÜYS-4 — SİTE / BLOK / DAİRE YÖNETİMİ

- site oluştur
- site düzenle
- blok oluştur
- blok düzenle
- daire oluştur

özelliklerini tamamla.

---

## ÜYS-5 — KAPI YÖNETİMİ

- çoklu kapı
- kapı adı
- kapı kapsamı
- kapıyı bloğa bağlama
- cihazı kapıya atama

tamamla.

---

## ÜYS-6 — CİHAZ DEĞİŞTİRME

Mevcut kapı üzerinden yeni cihaz QR'ı okutularak cihaz değiştir.

Kapı ve kullanıcı yetkilerini koru.

---

## ÜYS-7 — SİTE KATILIM QR

Site Katılım QR oluştur.

Bu QR sadece katılım talebi başlatsın.

---

## ÜYS-8 — DAİRE KATILIM TALEBİ

QR okut:

- blok seç
- daire seç
- talep gönder

Yönetici:

- bildirimi gör
- onayla
- reddet

---

## ÜYS-9 — DAİRE ADMINI / AİLE ÜYESİ

İlk onaylanan:

`Daire Admini`

Sonrakiler:

`Aile Üyesi`

Daire Admini aile üyelerini görebilsin.

---

## ÜYS-10 — OTOMATİK ERİŞİM

Onaylı kullanıcıya:

- site ortak kapıları
- kendi blok kapıları

otomatik erişim sağla.

Mevcut kapı açma mekanizmasını değiştirmeden authorization katmanını bağla.

---

## ÜYS-11 — EK VE TOPLU ERİŞİM

Site yöneticisi:

- başka blok
- özel kapı
- garaj vb.

ek yetkileri tekli veya toplu verebilsin.

---

## ÜYS-12 — AKORDİYON SAKİN LİSTESİ

Site → Blok → Daire → Sakinler

hiyerarşik akordiyon ekranını oluştur.

PDF tabanlı sakin listesi yerine bu ekran kullanılacak.

---

## ÜYS-13 — ÇOKLU SİTE TESTLERİ

Test et:

- bir kullanıcı iki site yönetiyor
- yönetim firması çok sayıda site yönetiyor
- kullanıcı iki farklı sitede sakin
- bir sitede çok sayıda kapı
- bir blokta çok sayıda kapı
- cihaz değişimi
- kullanıcıya başka blok yetkisi
- toplu yetkilendirme

---

## ÜYS-14 — REGRESYON TESTİ

Özellikle eski çalışan özellikleri tekrar test et:

- login
- ESP internet bağlantısı
- Bluetooth
- MQTT
- kapı açma
- mevcut cihazlar
- mevcut eski kullanıcılar
- mevcut QR özellikleri
- sahadaki eski C3 cihazları

Hiçbiri bozulmamalıdır.

---

# 35. HER ALT AŞAMADAN SONRA ZORUNLU RAPOR

Ajan her ÜYS aşamasından sonra kısa bir rapor yazmalıdır:

### Tamamlanan
Ne yapıldı?

### Değiştirilen dosyalar
Hangi dosyalara dokunuldu?

### Veritabanı değişikliği
Migration var mı?

### Eski sistem testi
Hangi eski işlevler tekrar test edildi?

### Sonuç
PASS / FAIL

### Sonraki adım
Hangi ÜYS aşamasına geçilecek?

Bir aşamada FAIL varsa sonraki aşamaya geçmeden önce hata çözülmelidir.

---

# 36. YASAKLAR

Ajan:

- eski çalışan ESP bağlantı kodunu sebepsiz yere yeniden yazmayacak,
- Bluetooth altyapısını değiştirmeyecek,
- çalışan kapı açma fonksiyonunu yeniden tasarlamayacak,
- sahadaki ESP32-C3 cihazlarını yeni QR özelliklerine zorlamayacak,
- cihazları tek kapı varsayımıyla modellemeyecek,
- kullanıcıyı tek siteye kilitlemeyecek,
- site yöneticisini global kullanıcı rolü olarak sabitlemeyecek,
- Site ile Cihazı aynı nesne gibi ele almayacak,
- Kapı ile Cihazı aynı nesne gibi ele almayacak,
- daire kullanıcılarını site oluşturulurken otomatik üretmeyecek,
- otomatik kullanıcı adı/şifre oluşturmayacak,
- sakin listesi için yeni PDF bağımlılığı kurmayacak,
- büyük tek seferlik refactor yapmayacak,
- kullanıcının açık onayı olmadan veri kaybına neden olacak migration çalıştırmayacaktır.

---

# 37. BU ÇALIŞMANIN TAMAMLANMA KRİTERİ

`Üyelik Yönetim Sistemi` ancak aşağıdakilerin tamamı sağlandıktan sonra tamamlanmış kabul edilir:

- yeni kullanıcı kendi hesabını oluşturabiliyor,
- 4 haneli kodla mail doğrulayabiliyor,
- cihazı QR ile ekleyebiliyor,
- cihaz sahibi site oluşturabiliyor,
- blokları yönetebiliyor,
- daireleri yönetebiliyor,
- birden fazla kapı oluşturabiliyor,
- kapı isimlerini değiştirebiliyor,
- cihazları kapılara atayabiliyor,
- cihazı değiştirebiliyor,
- Site Katılım QR'ı oluşturuluyor,
- doğrulanmış kullanıcı QR ile siteye katılım talebi gönderebiliyor,
- blok/daire dropdown seçimi çalışıyor,
- site yönetimi talebi onaylayabiliyor/reddedebiliyor,
- ilk onaylanan kişi Daire Admini oluyor,
- sonraki kişiler Aile Üyesi oluyor,
- Daire Admini aile üyelerini görebiliyor,
- sakin listesi akordiyon yapıda gösteriliyor,
- site ortak kapıları otomatik atanıyor,
- kullanıcının kendi blok kapıları otomatik atanıyor,
- başka blok erişimini yalnızca yönetici verebiliyor,
- toplu erişim verme/kaldırma çalışıyor,
- bir kullanıcı birden fazla siteyle ilişkilendirilebiliyor,
- bir yönetim firması birden fazla site yönetebiliyor,
- eski çalışan sistemde regresyon oluşmuyor.

---

# 38. ÜYELİK SİSTEMİ BİTİNCE

Bu bölüm çok önemlidir.

Üyelik Yönetim Sistemi tamamlandığında ajan:

1. `Üyelik Yönetim Sistemi TAMAMLANDI` şeklinde açık bir sonuç notu oluşturacak.
2. Yapılan migrationları özetleyecek.
3. Eski sistem regresyon test sonuçlarını yazacak.
4. Açık kalan teknik borç varsa ayrıca listeleyecek.
5. Daha önce devam eden ana projenin hangi noktada kaldığını değiştirmeyecek.
6. Ardından ana projede **önceden devam eden 4. aşamaya geri dönecek.**
7. 4. aşamaya başlamadan önce mevcut durumunu yeniden okuyacak ve kaldığı yerden devam edecek.

> Üyelik Yönetim Sistemi hiçbir koşulda ana projenin 4. aşamasının yerine geçmez.
>
> Bu, 4. aşama arasına alınmış bağımsız ve öncelikli bir çalışma paketidir.

---

# 39. AJANA SON TALİMAT

Önce bu dosyanın tamamını oku.

Ardından hemen kod yazmaya başlama.

İlk iş olarak:

**ÜYS-0 — Mevcut sistemi incele**

aşamasını gerçekleştir.

Mevcut yapıya göre yeni sistemin hangi dosya, tablo ve servislerle entegre edileceğini belirle.

Çalışan sisteme en az müdahale eden yolu seç.

Her değişikliği küçük, geri alınabilir ve test edilebilir şekilde yap.

Her aşamada:

**önce çalışan sistemi koru, sonra yeni özelliği ekle.**

