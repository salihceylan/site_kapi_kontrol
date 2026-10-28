# Flutter veri modelleri (lib/models) — JSON ayrıştırma

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Sunucu JSON'u uygulamada lib/models içindeki fromJson ile modele çevrilir. Liste boş/yarım, "verisi beklenen formatta degil", yanlış tarih/rol, alan adı uyuşmazlığı gibi belirtilerde önce ilgili modelin fromJson'ına, sonra servisteki _parsePayload sarmalayıcısına bakın. Kimlik alanı kuralı: kimlikler sunucuda sayıdır; modeller int ya da num.toInt() bekler, bazıları string de kabul eder.

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [lib/models/user_role.dart](../../lib/models/user_role.dart) | Rol enum: sunucu değeri (super_user, site_manager, apartment_owner, individual) -> UserRole |
| [lib/models/user_session.dart](../../lib/models/user_session.dart) | Oturum modeli: giriş yanıtı + yerelde saklanan kopya (fromJson/toJson) |
| [lib/models/managed_user_account.dart](../../lib/models/managed_user_account.dart) | Yönetilen kullanıcı satırı (süper kullanıcı listesi): rol, aktiflik, e-posta doğrulama, onay durumu |
| [lib/models/managed_user_page.dart](../../lib/models/managed_user_page.dart) | Sayfalı kullanıcı listesi sarmalayıcısı (users/total/page/pageSize) |
| [lib/models/super_user_account.dart](../../lib/models/super_user_account.dart) | Süper kullanıcı hesabı özeti |
| [lib/models/subscription_request.dart](../../lib/models/subscription_request.dart) | Abonelik talebi satırı |
| [lib/models/subscription_request_page.dart](../../lib/models/subscription_request_page.dart) | Sayfalı abonelik talebi listesi sarmalayıcısı |
| [lib/models/site_record.dart](../../lib/models/site_record.dart) | Site kaydı: özellik bayrakları, geofence, silme durumu, onay durumu; erişim modu etiketleri |
| [lib/models/site_page.dart](../../lib/models/site_page.dart) | Sayfalı site listesi sarmalayıcısı |
| [lib/models/site_structure_record.dart](../../lib/models/site_structure_record.dart) | Site yapısı: site + bloklar + daireler + kapılar |
| [lib/models/site_block_record.dart](../../lib/models/site_block_record.dart) | Blok satırı |
| [lib/models/apartment_record.dart](../../lib/models/apartment_record.dart) | Daire satırı + yönetici görünümündeki sakin bilgisi |
| [lib/models/apartment_member_record.dart](../../lib/models/apartment_member_record.dart) | Daire üyeleri ve "benim dairem" modeli (camelCase + snake_case anahtarlar) |
| [lib/models/site_residents_tree_record.dart](../../lib/models/site_residents_tree_record.dart) | Sakinler ağacı: site > blok > daire > sakin |
| [lib/models/site_manager_record.dart](../../lib/models/site_manager_record.dart) | Site yöneticileri + yönetici davetleri |
| [lib/models/site_join_info.dart](../../lib/models/site_join_info.dart) | Katılım QR'ı çözülünce gelen site/blok/daire bilgisi |
| [lib/models/site_join_token_record.dart](../../lib/models/site_join_token_record.dart) | Site katılım belirteci ve qr_payload |
| [lib/models/join_request_record.dart](../../lib/models/join_request_record.dart) | Katılım isteği (PENDING/APPROVED/REJECTED), iki anahtar biçimi |
| [lib/models/door_record.dart](../../lib/models/door_record.dart) | Kapı kaydı: atanmış cihaz alanları, erişim kapsamı, donanım/ekran türetmeleri |
| [lib/models/door_runtime_status.dart](../../lib/models/door_runtime_status.dart) | Kapı anlık durumu: MQTT/yerel kontrol, komut verilebilir mi |
| [lib/models/door_permission_record.dart](../../lib/models/door_permission_record.dart) | Kapı izin matrisi: blok > daire > sakin, yeni/eski anahtar uyumu |
| [lib/models/door_access_log_record.dart](../../lib/models/door_access_log_record.dart) | Geçiş günlüğü satırı + sayfa; tetikleyici ve rol etiketleri |
| [lib/models/device_record.dart](../../lib/models/device_record.dart) | Cihaz kaydı: sayısal kimlikler, donanım hedefi, OTA durumu, arızalı bayrağı |
| [lib/models/device_page.dart](../../lib/models/device_page.dart) | Sayfalı cihaz listesi sarmalayıcısı |
| [lib/models/device_connectivity_log.dart](../../lib/models/device_connectivity_log.dart) | Cihaz bağlantı günlüğü satırı + özet rapor |
| [lib/models/guest_pass.dart](../../lib/models/guest_pass.dart) | Misafir/kurye geçiş linki: süre ve kullanım hakkı türetmeleri |
| [lib/models/local_door_access.dart](../../lib/models/local_door_access.dart) | Yerel kapı kontrol önbelleği (IP, port, token, 24 saat geçerlilik) |

## Bu bölümdeki girişler (22)

- [model-tip-hatasi-beklenen-formatta-degil](#model-tip-hatasi-beklenen-formatta-degil) — Liste ya da ekran "... verisi beklenen formatta degil." / "... verisi islenemedi." hatasıyla açılmıyor
- [model-rol-yanlis-gorunuyor](#model-rol-yanlis-gorunuyor) — Kullanıcının rolü yanlış görünüyor (örn. site yöneticisi "Daire Kullanıcısı" menüsüyle açılıyor)
- [model-oturum-yerel-kopya-bozuk](#model-oturum-yerel-kopya-bozuk) — Uygulama her açılışta giriş ekranına dönüyor: kayıtlı oturum okunamıyor (saklı JSON eksik ya da bozuk)
- [model-tarih-saat-yanlis](#model-tarih-saat-yanlis) — Tarih/saat boş ("-" ya da "Bilinmiyor") ya da yanlış saat dilimiyle görünüyor
- [model-sayfali-liste-bos-yarim](#model-sayfali-liste-bos-yarim) — Sayfalı liste (site, kullanıcı, cihaz, abonelik talebi) boş ya da toplam/sayfa sayısı yanlış
- [model-site-alan-varsayilanlari](#model-site-alan-varsayilanlari) — Site özellikleri (QR, uzaktan açma, misafir linki) sunucuda kapalı olduğu halde uygulamada açık görünüyor
- [model-site-silme-durumu-etiketi](#model-site-silme-durumu-etiketi) — Site silme bekleyen onay durumu yanlış gösteriliyor ya da silme düğmeleri yanlış çıkıyor
- [model-kimlik-id-user-code-site-code](#model-kimlik-id-user-code-site-code) — Yanlış kayıt işleniyor ya da kimlik 0 geliyor (site kodu, kullanıcı kodu, id karışıklığı)
- [model-sakinler-agaci-yarim](#model-sakinler-agaci-yarim) — Sakinler ağacı (site > blok > daire > sakin) boş, eksik ya da sayaçlar tutmuyor
- [model-sakin-pasif-gorunuyor](#model-sakin-pasif-gorunuyor) — Sakin listede "pasif" görünüyor ya da üyelik aktif olduğu halde giriş/kapı erişimi yok
- [model-kapi-cihaz-alanlari-ve-ekran](#model-kapi-cihaz-alanlari-ve-ekran) — Kapı kartında cihaz çevrimdışı/yanlış donanım görünüyor ya da QR/ekran seçenekleri yanlış çıkıyor
- [model-kapi-anlik-durum-komut-verilemiyor](#model-kapi-anlik-durum-komut-verilemiyor) — Kapı anlık durumu "komut verilemez" görünüyor ya da sunucu hatasında durum bir anda çevrimdışı oluyor
- [model-cihaz-kaydi-donanim-ve-ota](#model-cihaz-kaydi-donanim-ve-ota) — Cihaz listesinde OTA durumu/donanım türü yanlış, sahip bilgisi ya da arızalı işareti eksik
- [model-baglanti-gunlugu-sure-ve-sebep](#model-baglanti-gunlugu-sure-ve-sebep) — Cihaz bağlantı günlüğünde süre "-" ya da sebep hep "Bağlantı Kesildi" görünüyor, rapor açılmıyor
- [model-gecis-gunlugu-etiketleri](#model-gecis-gunlugu-etiketleri) — Geçiş günlüğünde tetikleyici ya da kullanıcı rolü yanlış etiketli ("Mobil Bulut" yerine ham metin, "Kullanıcı"), özet sayaçları tutmuyor
- [model-kapi-izin-matrisi-hatali](#model-kapi-izin-matrisi-hatali) — Kapı izinleri ekranında sakinlerin yetkisi yanlış ("izinli" sayısı, durum etiketi) ya da liste boş
- [model-yerel-kapi-onbellek-kullanilmiyor](#model-yerel-kapi-onbellek-kullanilmiyor) — Yerel (Wi-Fi) kapı açma çalışmıyor: kayıtlı yerel erişim kullanılamaz sayılıyor
- [model-katilim-istegi-ve-qr-bilgisi](#model-katilim-istegi-ve-qr-bilgisi) — Siteye katılım isteği ya da katılım QR'ı bilgileri eksik (site adı, blok, daire boş; durum yanlış)
- [model-yonetici-listesi-ve-davetler](#model-yonetici-listesi-ve-davetler) — Site yöneticileri listesi ya da davet listesi boş/eksik; "Kurucu Yönetici" etiketi yanlış
- [model-misafir-linki-gecersiz](#model-misafir-linki-gecersiz) — Misafir/kurye linki listede "süresi dolmuş" ya da "kullanım hakkı bitti" görünüyor, oysa yeni oluşturuldu
- [model-daire-uyelik-ve-site-yapisi](#model-daire-uyelik-ve-site-yapisi) — Daire üyeleri ("Dairem"), daire/blok listesi ya da site yapısı eksik/yanlış görünüyor
- [model-kullanici-hesabi-onay-ve-dogrulama](#model-kullanici-hesabi-onay-ve-dogrulama) — Kullanıcı listesinde e-posta doğrulama durumu yanlış görünüyor (doğrulanmış kullanıcı "doğrulanmamış"); abonelik talebi satırı boş

## Girişler

<a id="model-tip-hatasi-beklenen-formatta-degil"></a>
### model-tip-hatasi-beklenen-formatta-degil · Liste ya da ekran "... verisi beklenen formatta degil." / "... verisi islenemedi." hatasıyla açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/services/auth_api.dart:4224](../../lib/services/auth_api.dart#L4224) | <code>T _parsePayload&lt;T&gt;(String label, T Function() parser) {</code> | Yalnız bu sarmalayıcıdan geçen uçlarda fromJson sırasındaki FormatException "<etiket> verisi islenemedi.", TypeError "<etiket> verisi beklenen formatta degil." iletisine çevrilir |
| [lib/models/site_structure_record.dart:19](../../lib/models/site_structure_record.dart#L19) | <code>factory SiteStructureRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Zorunlu alt nesne: json['site'] yoksa ya da nesne değilse TypeError, tüm yapı yüklenmez |
| [lib/models/door_record.dart:178](../../lib/models/door_record.dart#L178) | <code>factory DoorRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | id ve site_code "as int" (null/string gelirse TypeError); diğer alanlar varsayılanlı/boş olabilir ama yanlış tipte gelirse (örn. "as int?" alanına metin) yine TypeError |
| [lib/models/apartment_record.dart:56](../../lib/models/apartment_record.dart#L56) | <code>factory ApartmentRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | id, site_code, block_id "as int": biri string ya da null gelirse hata |
| [lib/models/managed_user_account.dart:54](../../lib/models/managed_user_account.dart#L54) | <code>factory ManagedUserAccount.fromJson(Map&lt;String, dynamic&gt; json) {</code> | id, full_name, email, role zorunlu tip dönüşümü; null gelirse hata |

**Olası nedenler**
- Sunucu bir alanı beklenmeyen tipte döndü (örn. sayı yerine metin, null) ve modelde "as int" / "as String" zorunlu
- Sunucu alan adını değiştirdi; zorunlu alan null kaldı
- Liste öğesi nesne değil ya da bir alt nesne (örn. door, site) beklenen tipte değil
- Kimlik/sayaç alanı beklenen tipte değil (örn. "as int?" alanına ondalık ya da metin)

**Adım adım kontrol**
- Hata iletisindeki etiketi (Site listesi, Cihazlar, Kullanici listesi vb.) _parsePayload çağrısına eşleyin
- İlgili modelin fromJson'ında "as int" / "as String" (soru işaretsiz) olan alanları ham yanıtla karşılaştırın
- Sunucu ucunun gerçek yanıtını alıp alan adı ve tipini model satırıyla kıyaslayın
- Bu iki ileti yalnız _parsePayload kullanan uçlarda çıkar: sakinler ağacı, kapı izinleri, site yöneticileri, "Dairelerim" ve katılım istekleri sarmalayıcıdan geçmez (hata ayrı iletiye ya da sessiz null/boş listeye döner)
- Sayfalı listelerde total/page/page_size okuması _parsePayload dışındadır: orada yanlış tip ham TypeError olarak sızar

**Günlükte aranacak ifadeler**
- `verisi beklenen formatta degil.`
- `verisi islenemedi.`

**Bkz.:** [cekirdek-sunucuya-baglanilamadi](30-uygulama-cekirdek.md#cekirdek-sunucuya-baglanilamadi)

<a id="model-rol-yanlis-gorunuyor"></a>
### model-rol-yanlis-gorunuyor · Kullanıcının rolü yanlış görünüyor (örn. site yöneticisi "Daire Kullanıcısı" menüsüyle açılıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/user_role.dart:12](../../lib/models/user_role.dart#L12) | <code>static UserRole fromApi(String value) {</code> | Bilinmeyen/yazımı farklı rol değeri sessizce apartmentOwner olur (orElse) |
| [lib/models/user_session.dart:76](../../lib/models/user_session.dart#L76) | <code>role: UserRole.fromApi(json['role'] as String),</code> | Oturum rolü sunucu "role" alanından gelir; alan null ise TypeError |
| [lib/models/managed_user_account.dart:60](../../lib/models/managed_user_account.dart#L60) | <code>role: UserRole.fromApi(json['role'] as String),</code> | Liste satırı rolü aynı eşlemeyle çözülür |

**Olası nedenler**
- Sunucu rol değeri enum'daki dört apiValue'dan biri değil (yeni rol eklendi ya da büyük/küçük harf farkı); varsayılan apartmentOwner'a düşer
- Yerelde saklı oturum kopyası eski rolü taşıyor: açılışta /me çağrısı sunucudaki rolü uygular, çağrı başarısız olursa (ağ hatası) eski rol kalır

**Adım adım kontrol**
- Giriş yanıtındaki role değerini apiValue listesiyle birebir karşılaştırın
- Yeni rol eklenecekse UserRole enum'una apiValue ile ekleyin; fromApi varsayılanına güvenmeyin

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart)

**Bkz.:** [cekirdek-yanlis-rol-menu](30-uygulama-cekirdek.md#cekirdek-yanlis-rol-menu), [ui-menu-yanlis-rol](31-uygulama-arayuz.md#ui-menu-yanlis-rol)

<a id="model-oturum-yerel-kopya-bozuk"></a>
### model-oturum-yerel-kopya-bozuk · Uygulama her açılışta giriş ekranına dönüyor: kayıtlı oturum okunamıyor (saklı JSON eksik ya da bozuk)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/user_session.dart:69](../../lib/models/user_session.dart#L69) | <code>factory UserSession.fromJson(Map&lt;String, dynamic&gt; json) {</code> | id (int), full_name, email, token zorunlu String/int; is_active yoksa true, created_at boş/bozuksa null |
| [lib/models/user_session.dart:54](../../lib/models/user_session.dart#L54) | <code>Map&lt;String, dynamic&gt; toJson() {</code> | Yerele yazılan biçim; alan adları fromJson ile aynı olmalı |
| [lib/services/auth_service.dart:155](../../lib/services/auth_service.dart#L155) | <code>_session = UserSession.fromJson(data);</code> | Açılışta güvenli depodaki oturum JSON'u burada UserSession'a çevrilir; fromJson hata verirse catch saklı oturumu sessizce siler (giriş ekranı) |

**Olası nedenler**
- Saklanan JSON'da zorunlu alan (token, email) yok ya da farklı tipte
- Eski sürümden kalan kayıtta alan adları farklı
- created_at bozuk metinse DateTime.tryParse null döner (hata vermez, tarih boş kalır)

**Adım adım kontrol**
- toJson ile fromJson anahtarlarının birebir aynı olduğunu doğrulayın
- AuthService.initialize içinde fromJson hatasında saklı oturum anahtarının silindiğini (kullanıcı girişe düşer) izleyin

**İlgili testler:** [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/model_parsing_test.dart](../../test/model_parsing_test.dart)

**Bkz.:** [cekirdek-acilista-oturum-yok](30-uygulama-cekirdek.md#cekirdek-acilista-oturum-yok), [cekirdek-oturum-kendiliginden-dusuyor](30-uygulama-cekirdek.md#cekirdek-oturum-kendiliginden-dusuyor)

<a id="model-tarih-saat-yanlis"></a>
### model-tarih-saat-yanlis · Tarih/saat boş ("-" ya da "Bilinmiyor") ya da yanlış saat dilimiyle görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/door_access_log_record.dart:44](../../lib/models/door_access_log_record.dart#L44) | <code>openedAt: DateTime.tryParse(json['opened_at']?.toString() ?? '')?.toLocal(),</code> | Geçiş zamanı model katmanında yerel saate çevrilir (modeller arasında tek toLocal); yok/bozuksa null |
| [lib/ui/helpers/ui_helpers.dart:26](../../lib/ui/helpers/ui_helpers.dart#L26) | <code>String formatDateTime(DateTime? dateTime) {</code> | Ekranda gösterirken toLocal çağrılır; null ise "-" yazar (formatDateTimeOrUnknown "Bilinmiyor" yazar) |
| [lib/models/site_record.dart:236](../../lib/models/site_record.dart#L236) | <code>createdAt: json['created_at'] == null</code> | Tarihler tryParse: biçim bozuksa hata değil null olur, ekranda boş kalır |
| [lib/models/guest_pass.dart:38](../../lib/models/guest_pass.dart#L38) | <code>expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ??</code> | Geçersiz expires_at şimdiki zamana düşer: link hemen "süresi dolmuş" sayılır |
| [lib/models/local_door_access.dart:59](../../lib/models/local_door_access.dart#L59) | <code>DateTime.fromMillisecondsSinceEpoch(0),</code> | updated_at okunamazsa 1970 olur: yerel kayıt kullanılamaz sayılır |
| [lib/models/device_connectivity_log.dart:37](../../lib/models/device_connectivity_log.dart#L37) | <code>onlineAt: json['online_at'] != null ? DateTime.tryParse(json['online_at'] as String) : nu…</code> | Bağlantı günlüğü tarihleri; "as String" ile okunur, metin değilse TypeError |

**Olası nedenler**
- Sunucu tarihi ISO 8601 dışı biçimde ya da metin olmayan tipte gönderdi
- Z eki/saat dilimi olmayan ISO metni Dart tarafından yerel saat sayılır: sunucu UTC değeri Z eksik gönderirse saat kayar
- expires_at/updated_at eksik: varsayılan değerler (şimdi / 1970) davranışı değiştirir

**Adım adım kontrol**
- Ham JSON'daki tarih metnini (ISO, saat dilimi eki) kontrol edin
- Ekranda biçimlendiren kodun (ui_helpers formatDateTime, door_logs_accordion) toLocal çağırdığını ve hangi alanın gösterildiğini doğrulayın

**İlgili testler:** [test/model_parsing_test.dart](../../test/model_parsing_test.dart), [test/local_door_access_test.dart](../../test/local_door_access_test.dart)

**Bkz.:** [model-misafir-linki-gecersiz](#model-misafir-linki-gecersiz), [model-yerel-kapi-onbellek-kullanilmiyor](#model-yerel-kapi-onbellek-kullanilmiyor)

<a id="model-sayfali-liste-bos-yarim"></a>
### model-sayfali-liste-bos-yarim · Sayfalı liste (site, kullanıcı, cihaz, abonelik talebi) boş ya da toplam/sayfa sayısı yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_page.dart:30](../../lib/models/site_page.dart#L30) | <code>int get totalPages {</code> | Toplam sayfa = ((total-1) ~/ pageSize)+1; total<=0 ise 1 |
| [lib/models/device_page.dart:16](../../lib/models/device_page.dart#L16) | <code>int get totalPages {</code> | Aynı formül; yönetici ucunda pageSize=devices.length verilir (liste boşsa total 0 olduğundan 1 sayfa döner) |
| [lib/models/managed_user_page.dart:30](../../lib/models/managed_user_page.dart#L30) | <code>int get totalPages {</code> | Kullanıcı listesi toplam sayfa hesabı |
| [lib/models/subscription_request_page.dart:16](../../lib/models/subscription_request_page.dart#L16) | <code>int get totalPages {</code> | Abonelik talebi toplam sayfa hesabı |
| [lib/services/auth_api.dart:594](../../lib/services/auth_api.dart#L594) | <code>return SitePage(</code> | Sunucu total/page/page_size yoksa 0 / istenen sayfa / istenen boyut kullanılır |
| [lib/services/auth_api.dart:440](../../lib/services/auth_api.dart#L440) | <code>return ManagedUserPage(</code> | Kullanıcı sayfası aynı varsayılanlarla kurulur; liste anahtarı "users" |
| [lib/services/auth_api.dart:3323](../../lib/services/auth_api.dart#L3323) | <code>return SubscriptionRequestPage(</code> | Liste anahtarı "requests" |
| [lib/services/auth_api.dart:3032](../../lib/services/auth_api.dart#L3032) | <code>return DevicePage(</code> | Site yöneticisi rolünün /manager/devices ucunda sayfalama yok: total=devices.length, page=1, pageSize=devices.length |

**Olası nedenler**
- Sunucu liste anahtarını değiştirdi (sites/users/devices/requests); "?? []" yüzünden hata yerine boş liste görünür
- total yanıtta yok: 0 olur, sayfa düğmeleri tek sayfa gösterir
- Yönetici cihaz ucu tüm listeyi tek sayfada döndürür; sunucu tarafı sayfalama beklenmemeli

**Adım adım kontrol**
- Yanıtta liste anahtarı ve total/page/page_size alanlarının adını model satırıyla karşılaştırın
- Boş liste ile hata ayırt edilemiyorsa ham yanıtı kaydedip anahtarlara bakın

<a id="model-site-alan-varsayilanlari"></a>
### model-site-alan-varsayilanlari · Site özellikleri (QR, uzaktan açma, misafir linki) sunucuda kapalı olduğu halde uygulamada açık görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_record.dart:219](../../lib/models/site_record.dart#L219) | <code>featureQrEnabled: json['feature_qr_enabled'] as bool? ?? true,</code> | Alan yoksa/null ise özellik AÇIK sayılır (eski sunucu uyumu); yanlış anahtar adı sessizce açık bırakır |
| [lib/models/site_record.dart:97](../../lib/models/site_record.dart#L97) | <code>String get accessModeLabel {</code> | Sadece Uygulama / Sadece QR / Hibrit etiketi iki bayraktan türetilir |
| [lib/models/site_record.dart:103](../../lib/models/site_record.dart#L103) | <code>String get approvalLabel {</code> | pending/rejected dışındaki her değer "Onaylandi" görünür; approval_status boşsa "approved" varsayılır |
| [lib/models/site_record.dart:206](../../lib/models/site_record.dart#L206) | <code>blockCount: (json['block_count'] as num?)?.toInt() ?? 1,</code> | block_count/door_count eksikse 1 gösterilir (gerçek sayı değil) |

**Olası nedenler**
- Sunucu alan adı farklı yazıldığı için model varsayılana (true) düşüyor
- Sayaçlar eksikse 1 varsayılanı gerçek değeri gizler
- Onay durumu eksikse site onaylı gibi görünür

**Adım adım kontrol**
- Sunucu site yanıtında feature_* anahtarlarının tam adlarını model satırlarıyla kıyaslayın
- Kapı ekranı modelindeki aynı bayraklar için DoorRecord.fromJson'a da bakın

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart)

**Bkz.:** [sunucu-karekod-politika-kapali](10-sunucu-api.md#sunucu-karekod-politika-kapali), [sunucu-kapi-acma-403-uzaktan-kapali](10-sunucu-api.md#sunucu-kapi-acma-403-uzaktan-kapali)

<a id="model-site-silme-durumu-etiketi"></a>
### model-site-silme-durumu-etiketi · Site silme bekleyen onay durumu yanlış gösteriliyor ya da silme düğmeleri yanlış çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_record.dart:83](../../lib/models/site_record.dart#L83) | <code>bool get isDeletionPending =&gt;</code> | İki bekleme durumundan biriyse silme beklemede sayılır; başka metin değeri "beklemiyor" demektir |
| [lib/models/site_record.dart:229](../../lib/models/site_record.dart#L229) | <code>deletionStatus: json['deletion_status'] as String? ?? 'none',</code> | Alan yoksa "none": silme akışı hiç başlamamış görünür |

**Olası nedenler**
- Sunucu yeni bir silme durum metni ekledi; modelde tanımsız olduğu için bekleyen sayılmaz
- deletion_requested_by_* alanları eksik: isteyen adı/rolü boş görünür

**Adım adım kontrol**
- Veritabanındaki/yanıttaki deletion_status değerini iki sabit metinle karşılaştırın
- site_card.dart ve home_page.dart içinde isDeletionPending / isPendingSuperUserApproval / isPendingSiteManagerApproval getter'larının nasıl okunduğuna bakın

**Bkz.:** [ui-site-silme-akisi](31-uygulama-arayuz.md#ui-site-silme-akisi)

<a id="model-kimlik-id-user-code-site-code"></a>
### model-kimlik-id-user-code-site-code · Yanlış kayıt işleniyor ya da kimlik 0 geliyor (site kodu, kullanıcı kodu, id karışıklığı)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_record.dart:195](../../lib/models/site_record.dart#L195) | <code>final rawId = json['id'] ?? json['site_code'];</code> | Site kimliği id, yoksa site_code; ikisi de yoksa/çözülemezse 0 |
| [lib/models/site_record.dart:186](../../lib/models/site_record.dart#L186) | <code>int get siteCode =&gt; id;</code> | siteCode ayrı alan değil, id'nin takma adıdır |
| [lib/models/door_permission_record.dart:11](../../lib/models/door_permission_record.dart#L11) | <code>int? _asIntOrNull(Object? value) {</code> | Sayı ya da sayısal metni int yapar; çözülemezse null, çağıranlar çoğunlukla 0'a düşer |
| [lib/models/door_permission_record.dart:39](../../lib/models/door_permission_record.dart#L39) | <code>siteId: _asIntOrNull(json['site_code'] ?? json['site_id']) ?? 0,</code> | İzin modelinde site_code önce, site_id eski anahtar |
| [lib/models/site_residents_tree_record.dart:70](../../lib/models/site_residents_tree_record.dart#L70) | <code>userCode: json['user_code'] as int? ?? 0,</code> | Sakin kimliği user_code (id değil); eksikse 0 |
| [lib/models/apartment_member_record.dart:26](../../lib/models/apartment_member_record.dart#L26) | <code>membershipId: (json['membership_id'] as num?)?.toInt() ?? 0,</code> | Üyelik kimliği (membership_id) ile kullanıcı kodu (user_code) farklı alanlardır |
| [lib/models/device_record.dart:114](../../lib/models/device_record.dart#L114) | <code>id: int.tryParse(json['id']?.toString() ?? '') ?? 0,</code> | Cihaz kimlikleri metin/sayı fark etmeksizin tryParse; çözülemeyen id 0 olur |

**Olası nedenler**
- Sunucu kimliği farklı anahtarla gönderdi (id / site_code / user_code / membership_id)
- Kimlik 0 görünüyorsa alan eksik ya da sayıya çevrilemedi; işlem yanlış kayda gidebilir
- Çıplak "as int" kullanan modeller metin kimlikte hata verir, tryParse kullananlar sessizce 0 üretir

**Adım adım kontrol**
- İlgili ucun yanıtında kimlik alanı adlarını modelin okuduğu adlarla kıyaslayın
- İstek gövdesine giden kimliğin hangi alandan alındığını çağıran ekranda doğrulayın

**Bkz.:** [model-tip-hatasi-beklenen-formatta-degil](#model-tip-hatasi-beklenen-formatta-degil)

<a id="model-sakinler-agaci-yarim"></a>
### model-sakinler-agaci-yarim · Sakinler ağacı (site > blok > daire > sakin) boş, eksik ya da sayaçlar tutmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_residents_tree_record.dart:176](../../lib/models/site_residents_tree_record.dart#L176) | <code>factory SiteResidentsTreeData.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Kök: site + blocks; anahtar yoksa boş site/liste ile devam eder (hata vermez) |
| [lib/models/site_residents_tree_record.dart:153](../../lib/models/site_residents_tree_record.dart#L153) | <code>factory SiteResidentBlock.fromJson(Map&lt;String, dynamic&gt; json) {</code> | blocks[].apartments listesi; sayaçlar sunucudan okunur, listeden hesaplanmaz |
| [lib/models/site_residents_tree_record.dart:120](../../lib/models/site_residents_tree_record.dart#L120) | <code>factory SiteResidentApartment.fromJson(Map&lt;String, dynamic&gt; json) {</code> | apartments[].residents (PIN alanı YOK, migration 051); daire boşluğu residents.isEmpty ile belirlenir |
| [lib/models/site_residents_tree_record.dart:25](../../lib/models/site_residents_tree_record.dart#L25) | <code>factory SiteResidentsTreeSite.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Site özeti sayaçları (total_blocks, total_apartments, empty_apartments_count) |
| [lib/services/auth_service.dart:4035](../../lib/services/auth_service.dart#L4035) | <code>return (SiteResidentsTreeData.fromJson(json), null);</code> | Ağaç yanıtı doğrudan fromJson ile çevrilir (_parsePayload yok); ayrıştırma hatası catch ile "Sakin listesi yüklenemedi." iletisine döner |

**Olası nedenler**
- Sunucu anahtar adları (blocks, apartments, residents) değişti; "?? const []" boş ağaç üretir
- Üst sayaç (total_residents) ile alt liste uzunluğu uyuşmuyor: ikisi bağımsız okunur
- Alt öğe nesne değilse "as Map<String, dynamic>" TypeError verir ve ekran "Sakin listesi yüklenemedi." gösterir

**Adım adım kontrol**
- Ham yanıtta site, blocks[].apartments[].residents[] yapısını model satırlarıyla izleyin
- Sayaç tutarsızlığında sunucu hesabına bakın; modelde yeniden hesaplanmaz

**İlgili testler:** [test/fix_fx2_residents_dialog_test.dart](../../test/fix_fx2_residents_dialog_test.dart)

**Bkz.:** [model-sakin-pasif-gorunuyor](#model-sakin-pasif-gorunuyor)

<a id="model-sakin-pasif-gorunuyor"></a>
### model-sakin-pasif-gorunuyor · Sakin listede "pasif" görünüyor ya da üyelik aktif olduğu halde giriş/kapı erişimi yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_residents_tree_record.dart:77](../../lib/models/site_residents_tree_record.dart#L77) | <code>isActive: json['is_active'] != false,</code> | Üyelik VE hesap birlikte aktif mi; yalnız açık false pasif sayılır (eksik alan aktif) |
| [lib/models/site_residents_tree_record.dart:78](../../lib/models/site_residents_tree_record.dart#L78) | <code>accountIsActive: json['account_is_active'] != false,</code> | Global hesap durumu; eski sunucuda alan yoksa true sayılır |
| [lib/models/managed_user_account.dart:61](../../lib/models/managed_user_account.dart#L61) | <code>isActive: json['is_active'] as bool? ?? true,</code> | Kullanıcı satırında da eksik alan aktif demektir |
| [lib/models/site_residents_tree_record.dart:85](../../lib/models/site_residents_tree_record.dart#L85) | <code>String get roleLabel =&gt; isAdmin ? 'Daire Admini' : 'Aile Üyesi';</code> | Rol etiketi yalnız APARTMENT_ADMIN için "Daire Admini"; başka her değer "Aile Üyesi" |

**Olası nedenler**
- Hesap sistem yöneticisi tarafından pasife alındı: üyelik aktif edilse bile giriş ve kapı erişimi kapalı kalır
- Sunucu eski sürüm: account_is_active gelmez, pasiflik ayırt edilemez
- Beklenmeyen rol metni "Aile Üyesi" olarak görünür

**Adım adım kontrol**
- Yanıtta is_active ile account_is_active'i ayrı ayrı karşılaştırın
- Kullanıcı hesabının users tablosundaki aktiflik durumuna bakın (salt-okunur SELECT)

**İlgili testler:** [test/fix_fx2_residents_dialog_test.dart](../../test/fix_fx2_residents_dialog_test.dart)

**Bkz.:** [sunucu-oturum-403-hesap-pasif](10-sunucu-api.md#sunucu-oturum-403-hesap-pasif), [cekirdek-hesap-pasif-oturum-kapandi](30-uygulama-cekirdek.md#cekirdek-hesap-pasif-oturum-kapandi)

<a id="model-kapi-cihaz-alanlari-ve-ekran"></a>
### model-kapi-cihaz-alanlari-ve-ekran · Kapı kartında cihaz çevrimdışı/yanlış donanım görünüyor ya da QR/ekran seçenekleri yanlış çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/door_record.dart:191](../../lib/models/door_record.dart#L191) | <code>assignedDeviceHardwareTarget: json['assigned_device_hardware_target'] as String? ?? json[…</code> | Önek'li (assigned_device_*) anahtar önce, önek'siz anahtar yedek; iki biçim de sunucuda olabilir |
| [lib/models/door_record.dart:194](../../lib/models/door_record.dart#L194) | <code>assignedDeviceIsOnline: json['assigned_device_is_online'] as bool? ?? json['is_online'] a…</code> | Çevrimiçi bilgisi bool? : alan yoksa null (bilinmiyor) |
| [lib/models/door_record.dart:159](../../lib/models/door_record.dart#L159) | <code>bool get hasDisplay =&gt; hasDevice &amp;&amp; (isHardwareWroom &#124;&#124; (!isHardwareC3 &amp;&amp; (assignedDevice…</code> | Ekranlı mı: cihaz var ve (WROOM/esp32dev ya da [C3 değil ve assigned_device_hardware_target boş]); hedef yalnız hardware_type ile gelirse ve WROOM değilse ekran yok sayılır |
| [lib/models/door_record.dart:163](../../lib/models/door_record.dart#L163) | <code>bool get isHardwareC3 =&gt;</code> | Donanım hedefi metninde "c3" geçiyorsa C3 sayılır |
| [lib/models/door_record.dart:135](../../lib/models/door_record.dart#L135) | <code>bool get requiresLocationForQrScan =&gt; requireGeofence &#124;&#124; (hasDevice &amp;&amp; !hasDisplay);</code> | Konum zorunluluğu: geofence açık ya da (cihaz var ve ekran yok) |
| [lib/models/door_record.dart:199](../../lib/models/door_record.dart#L199) | <code>assignedDeviceLastSeenAt: json['assigned_device_last_seen_at'] == null</code> | Son görülme: önekli yoksa last_seen_at; tarih metni bozuksa null |

**Olası nedenler**
- Sunucu donanım hedefini boş gönderdi: hasDisplay yanlış çıkabilir (ekran yok/var tahmini)
- Önekli ve önekisiz anahtarlardan ilk dolu olan alınır; çelişen iki değer varsa önekli kazanır
- Atanmış cihaz yoksa tüm assigned_device_* alanları null
- assigned_device_qr_reader_enabled için önek'siz yedek anahtar yoktur: alan yoksa false olur, hasPhysicalQrScanner ve canOpenQr kapanır (QR seçeneği çıkmaz)

**Adım adım kontrol**
- Kapı yanıtında assigned_device_hardware_target / hardware_type değerini kontrol edin
- DeviceRecord.hasHardwareMismatch ile kayıtlı tür ile cihazın bildirdiği hedef çelişkisine bakın

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/screens/individual_door_card_model_test.dart](../../test/screens/individual_door_card_model_test.dart)

**Bkz.:** [model-cihaz-kaydi-donanim-ve-ota](#model-cihaz-kaydi-donanim-ve-ota), [ui-bireysel-kapi-karti-dugmeleri](31-uygulama-arayuz.md#ui-bireysel-kapi-karti-dugmeleri)

<a id="model-kapi-anlik-durum-komut-verilemiyor"></a>
### model-kapi-anlik-durum-komut-verilemiyor · Kapı anlık durumu "komut verilemez" görünüyor ya da sunucu hatasında durum bir anda çevrimdışı oluyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/door_runtime_status.dart:90](../../lib/models/door_runtime_status.dart#L90) | <code>factory DoorRuntimeStatus.fromJson(Map&lt;String, dynamic&gt; json) {</code> | door + device_status ayrıştırması ("door" yoksa TypeError); ip/port/available local_control iç nesnesinden, yoksa düz local_ip/local_control_port/local_control_available alanlarından okunur; token YALNIZ local_control.token'dan |
| [lib/models/door_runtime_status.dart:84](../../lib/models/door_runtime_status.dart#L84) | <code>bool get commandEnabled =&gt;</code> | Komut açık = (MQTT köprüsü ve cihaz bağlı) VEYA (yerel kontrol var + token + IP dolu) |
| [lib/models/door_runtime_status.dart:124](../../lib/models/door_runtime_status.dart#L124) | <code>DoorRuntimeStatus copyWithOffline() {</code> | Arka plan yoklaması sunucu hatası alır ve cihaz yerel Wi-Fi'de de erişilemezse (home_page) bu kopya ile bağlantı bayrakları sıfırlanır, diğer alanlar korunur |
| [lib/models/door_runtime_status.dart:97](../../lib/models/door_runtime_status.dart#L97) | <code>mqttBridgeConnected: status['mqtt_bridge_connected'] as bool? ?? false,</code> | Alan yoksa false: köprü bağlı değilmiş gibi görünür |

**Olası nedenler**
- device_status alanı eksik ya da boş: tüm bağlantı bayrakları false, komut kapalı
- Yerel kontrol token'ı ya da IP boş: yalnız yerel yol kapalı kalır
- Arka plan yoklaması sunucu hatası aldı ve yerel ağda cihaza da ulaşılamadı: son bilinen veriler korunur ama bağlantı kapalı (çevrimdışı) gösterilir
- wifi_rssi / wifi_signal_percent / local_control.port "as int?" ile okunur: ondalık ya da metin gelirse TypeError ("Kapi durumu verisi beklenen formatta degil.")

**Adım adım kontrol**
- Durum yanıtında device_status.mqtt_bridge_connected, mqtt_connected ve local_control alanlarına bakın
- home_page.dart içinde arka plan yoklamasının copyWithOffline'ı ne zaman kullandığını izleyin

**Bkz.:** [ui-kapi-durum-yoklama](31-uygulama-arayuz.md#ui-kapi-durum-yoklama), [cekirdek-kapi-durumu-cevrimdisi](30-uygulama-cekirdek.md#cekirdek-kapi-durumu-cevrimdisi), [sunucu-kapi-acma-cihaz-offline](10-sunucu-api.md#sunucu-kapi-acma-cihaz-offline)

<a id="model-cihaz-kaydi-donanim-ve-ota"></a>
### model-cihaz-kaydi-donanim-ve-ota · Cihaz listesinde OTA durumu/donanım türü yanlış, sahip bilgisi ya da arızalı işareti eksik

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/device_record.dart:81](../../lib/models/device_record.dart#L81) | <code>static String? normalizeHardwareTarget(Object? raw) {</code> | 'esp32_c3' -> 'esp32-c3' biçimine çevirir; boşsa null |
| [lib/models/device_record.dart:87](../../lib/models/device_record.dart#L87) | <code>bool get hasHardwareMismatch {</code> | Kayıtlı donanım türü ile cihazın bildirdiği hedef farklıysa OTA 403 teşhisi için işaretlenir |
| [lib/models/device_record.dart:93](../../lib/models/device_record.dart#L93) | <code>String get displayOtaStatus {</code> | Ham ota_status metni Türkçe etikete çevrilir; "indiriliyor" iken firmware_version == ota_last_version ise "Güncel" gösterilir; tanınmayan metin ham gösterilir |
| [lib/models/device_record.dart:149](../../lib/models/device_record.dart#L149) | <code>isDefective: json['is_defective'] == true &#124;&#124; json['is_defective'] == 1,</code> | Arızalı bayrağı bool ya da 1 olarak kabul edilir |
| [lib/models/device_record.dart:136](../../lib/models/device_record.dart#L136) | <code>publicIp: json['public_ip'] as String? ?? json['client_ip'] as String?,</code> | Genel IP alanı eski adıyla (client_ip) da okunur |
| [lib/models/device_record.dart:74](../../lib/models/device_record.dart#L74) | <code>bool get hasOwner =&gt;</code> | Sahip: kullanıcı kodu/kimliği/adı/e-postasından herhangi biri doluysa sahiplenilmiş sayılır |

**Olası nedenler**
- Kayıtlı hardware_type ile cihazın bildirdiği hardware_target çelişiyor: OTA reddedilebilir
- OTA durum metni tanımlı kalıplara uymuyor: ham metin gösterilir
- Sayısal alanlar tryParse ile okunur; sayıya çevrilemezse null (RSSI, atanmış kapı/kullanıcı kodu boş görünür)

**Adım adım kontrol**
- Cihaz kaydında hardware_type ve hardware_target değerlerini karşılaştırın
- Sunucu OTA durum metni ile displayOtaStatus eşlemesini kıyaslayın

**İlgili testler:** [test/fix_fx2_models_test.dart](../../test/fix_fx2_models_test.dart)

**Bkz.:** [model-kapi-cihaz-alanlari-ve-ekran](#model-kapi-cihaz-alanlari-ve-ekran)

<a id="model-baglanti-gunlugu-sure-ve-sebep"></a>
### model-baglanti-gunlugu-sure-ve-sebep · Cihaz bağlantı günlüğünde süre "-" ya da sebep hep "Bağlantı Kesildi" görünüyor, rapor açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/device_connectivity_log.dart:32](../../lib/models/device_connectivity_log.dart#L32) | <code>factory DeviceConnectivityLogRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | duration_text alanı hiç gelmezse "-", reason hiç gelmezse "Bağlantı Kesildi", event_type hiç gelmezse "offline" varsayılır |
| [server/src/services/device_service.js:847](../../server/src/services/device_service.js#L847) | <code>duration_text: formatDurationTurkish(row.duration_seconds),</code> | Sunucu satırında duration_seconds NULL ise duration_text "-" gelir (formatDurationTurkish); reason boşsa sunucu "Wi-Fi / Bağlantı Kesildi" yazar |
| [lib/models/device_connectivity_log.dart:39](../../lib/models/device_connectivity_log.dart#L39) | <code>durationSeconds: json['duration_seconds'] as int?,</code> | Sayı int değilse (ondalık/metin) TypeError |
| [lib/models/device_connectivity_log.dart:79](../../lib/models/device_connectivity_log.dart#L79) | <code>factory DeviceConnectivityReport.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Rapor: pagination iç nesnesi (camelCase pageSize/totalPages) ve logs; eksikse 1/10/0/1 ve boş liste; logs içindeki nesne olmayan öğeler sessizce atlanır |

**Olası nedenler**
- Süre "-" ise çoğunlukla satırın duration_seconds değeri NULL (sunucu "-" üretir); modelin kendi "-" ve "Bağlantı Kesildi" varsayılanları yalnız alan yanıtta hiç yoksa devreye girer
- wifi_rssi ya da duration_seconds sayı yerine ondalık/metin geldi: "as int?" TypeError

**Adım adım kontrol**
- Ham yanıtta logs[] öğelerindeki alan tiplerine bakın
- Sunucuda aynı cihaz için bağlantı günlüğü satırlarının dolu olup olmadığını SELECT ile görün

**İlgili testler:** [test/device_connectivity_test.dart](../../test/device_connectivity_test.dart)

**Bkz.:** [altyapi-cihaz-cevrimdisi-gorunuyor](20-sunucu-altyapi-ve-yayin.md#altyapi-cihaz-cevrimdisi-gorunuyor)

<a id="model-gecis-gunlugu-etiketleri"></a>
### model-gecis-gunlugu-etiketleri · Geçiş günlüğünde tetikleyici ya da kullanıcı rolü yanlış etiketli ("Mobil Bulut" yerine ham metin, "Kullanıcı"), özet sayaçları tutmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/door_access_log_record.dart:51](../../lib/models/door_access_log_record.dart#L51) | <code>String get triggerTypeDisplay {</code> | Bilinen tetikleyiciler Türkçe etiketlenir; bilinmeyen değer ham gösterilir |
| [lib/models/door_access_log_record.dart:93](../../lib/models/door_access_log_record.dart#L93) | <code>String get triggerGroup {</code> | Özet sayaçları için grup (cloud/local/guest/voice/offline/other); bu beş grubun dışındaki her değer (ekran, QR okuyucu, Bluetooth, bilinmeyen) other olur |
| [lib/models/door_access_log_record.dart:116](../../lib/models/door_access_log_record.dart#L116) | <code>String get userRoleDisplay {</code> | Rol etiketi; tanınmayan rol "Kullanıcı" |
| [lib/models/door_access_log_record.dart:43](../../lib/models/door_access_log_record.dart#L43) | <code>triggerType: json['trigger_type'] as String? ?? 'cloud_app',</code> | trigger_type yoksa bulut uygulaması sayılır |
| [lib/models/door_access_log_record.dart:147](../../lib/models/door_access_log_record.dart#L147) | <code>factory DoorAccessLogPage.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Sayfa: total/page/page_size/total_pages sayıya çevrilir; yoksa sırasıyla liste uzunluğu / 1 / 50 / 1 |

**Olası nedenler**
- Sunucu yeni tetikleyici ekledi ama modelde etiketi yok: ham metin görünür, grup "other" olur
- trigger_type boş/eksik: "Mobil Bulut" olarak sayılır
- user_role eksik ya da farklı: "Kullanıcı" görünür

**Adım adım kontrol**
- Sunucu tarafındaki izinli tetikleyici listesiyle triggerTypeDisplay anahtarlarını karşılaştırın
- Günlük satırında trigger_type ve user_role ham değerlerine bakın

**İlgili testler:** [test/fix_fx2_models_test.dart](../../test/fix_fx2_models_test.dart)

**Bkz.:** [sunucu-yonetici-gecis-gunlugu-bos](10-sunucu-api.md#sunucu-yonetici-gecis-gunlugu-bos), [sunucu-kapi-gecis-logu-yazilmadi](10-sunucu-api.md#sunucu-kapi-gecis-logu-yazilmadi)

<a id="model-kapi-izin-matrisi-hatali"></a>
### model-kapi-izin-matrisi-hatali · Kapı izinleri ekranında sakinlerin yetkisi yanlış ("izinli" sayısı, durum etiketi) ya da liste boş

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/door_permission_record.dart:260](../../lib/models/door_permission_record.dart#L260) | <code>factory DoorPermissionsData.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Kök: door + blocks; eksikse boş nesne/liste |
| [lib/models/door_permission_record.dart:226](../../lib/models/door_permission_record.dart#L226) | <code>factory DoorBlockPermission.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Sunucu total_apartments göndermezse daire listesinden türetilir; authorized_count yoksa canOpen sayılır |
| [lib/models/door_permission_record.dart:89](../../lib/models/door_permission_record.dart#L89) | <code>factory DoorResidentPermission.fromJson(Map&lt;String, dynamic&gt; json) {</code> | has_access (bool) yoksa eski can_open; override iç nesnesi ya da override_* alanları |
| [lib/models/door_permission_record.dart:128](../../lib/models/door_permission_record.dart#L128) | <code>String get statusLabel {</code> | access_source değerine göre durum yazısı |
| [lib/models/door_permission_record.dart:202](../../lib/models/door_permission_record.dart#L202) | <code>String get label {</code> | Daire başlığı: "Daire" öneki yoksa eklenir |
| [lib/services/auth_service.dart:3958](../../lib/services/auth_service.dart#L3958) | <code>return (DoorPermissionsData.fromJson(json), null);</code> | İzin yanıtı doğrudan fromJson ile çevrilir (_parsePayload yok); ayrıştırma hatası catch ile "Kapı yetkileri alınamadı." iletisine döner |

**Olası nedenler**
- Sunucu eski/yeni anahtar adını değiştirdi (has_access/can_open, role/member_role, unit_label/door_number)
- access_source tanımsız bir değer: durum etiketi ve getter'lar (isSiteCommon vb.) hiçbirine uymaz
- has_access bool değilse (örn. sayı) canOpen eski can_open'a bakar ve false kalabilir

**Adım adım kontrol**
- İzin yanıtında sakin nesnesinin anahtarlarını fromJson'daki "yeni ?? eski" okumalarıyla kıyaslayın
- Kapı erişim kapsamı için DoorPermissionInfo.accessScope değerine bakın (SITE_COMMON/BLOCK/CUSTOM)

**İlgili testler:** [test/fix_fx2_models_test.dart](../../test/fix_fx2_models_test.dart)

**Bkz.:** [sunucu-sakin-kapi-listede-yok](10-sunucu-api.md#sunucu-sakin-kapi-listede-yok)

<a id="model-yerel-kapi-onbellek-kullanilmiyor"></a>
### model-yerel-kapi-onbellek-kullanilmiyor · Yerel (Wi-Fi) kapı açma çalışmıyor: kayıtlı yerel erişim kullanılamaz sayılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/local_door_access.dart:25](../../lib/models/local_door_access.dart#L25) | <code>bool isUsableAt(DateTime now) {</code> | Cihaz kimliği + token dolu ve 24 saat içinde güncellenmiş olmalı; gelecek damga (-5 dk ötesi) güvenilmez |
| [lib/models/local_door_access.dart:18](../../lib/models/local_door_access.dart#L18) | <code>static const Duration cacheValidity = Duration(hours: 24);</code> | Önbellek geçerliliği 24 saat |
| [lib/models/local_door_access.dart:49](../../lib/models/local_door_access.dart#L49) | <code>factory LocalDoorAccess.fromJson(Map&lt;String, dynamic&gt; json) {</code> | port yoksa 8765, ip boşsa null, updated_at bozuksa 1970 (kullanılamaz) |
| [lib/services/auth_service.dart:3612](../../lib/services/auth_service.dart#L3612) | <code>final access = LocalDoorAccess.fromJson(value);</code> | Açılışta saklı kayıtlar okunur; isUsable olmayanlar (24 saatten eski, token/uid boş) önbelleğe alınmaz, JSON bozuksa tüm önbellek anahtarı silinir |

**Olası nedenler**
- Token boş: yerel kontrol kapalı sayılır (güvenlik gereği)
- Kayıt 24 saatten eski ya da telefon saati yanlış (gelecek damga)
- Saklanan JSON'da updated_at yok/bozuk: epoch 0 olur

**Adım adım kontrol**
- Telefon saatinin doğru olduğunu doğrulayın
- Sunucudan taze yerel erişim bilgisi alınıp alınmadığına bakın (durum yenilemesi)

**İlgili testler:** [test/local_door_access_test.dart](../../test/local_door_access_test.dart)

**Bkz.:** [cekirdek-yerel-token-yok](30-uygulama-cekirdek.md#cekirdek-yerel-token-yok), [sunucu-yerel-kontrol-token-bos](10-sunucu-api.md#sunucu-yerel-kontrol-token-bos), [model-tarih-saat-yanlis](#model-tarih-saat-yanlis)

<a id="model-katilim-istegi-ve-qr-bilgisi"></a>
### model-katilim-istegi-ve-qr-bilgisi · Siteye katılım isteği ya da katılım QR'ı bilgileri eksik (site adı, blok, daire boş; durum yanlış)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/join_request_record.dart:50](../../lib/models/join_request_record.dart#L50) | <code>factory JoinRequestRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Her alan camelCase (siteCode) ve snake_case (site_code) anahtarlarla okunur; id zorunlu |
| [lib/models/join_request_record.dart:72](../../lib/models/join_request_record.dart#L72) | <code>status: (json['status'] as String? ?? 'PENDING').toUpperCase(),</code> | Durum büyük harfe çevrilir; yoksa PENDING |
| [lib/models/site_join_info.dart:68](../../lib/models/site_join_info.dart#L68) | <code>factory SiteJoinInfo.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Katılım QR'ından gelen site/blok/daire bilgisi; iki anahtar biçimi de kabul edilir |
| [lib/models/site_join_info.dart:37](../../lib/models/site_join_info.dart#L37) | <code>factory SiteJoinApartmentInfo.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Daire kimliği (id) zorunlu "as num"; null gelirse TypeError |
| [lib/models/site_join_token_record.dart:28](../../lib/models/site_join_token_record.dart#L28) | <code>qrPayload: json['qr_payload'] as String? ??</code> | qr_payload yoksa token'dan "SITE_JOIN:<token>" üretilir |

**Olası nedenler**
- Sunucu yanıtı bu iki anahtar biçiminden birine uymuyor: alan boş kalır
- Blok ya da daire id'si null: zorunlu "as num" alanlarında TypeError
- Yanıtta token ya da site_name yok: SiteJoinInfo bunları boş metin yapar (hata vermez), site adı/token boş görünür

**Adım adım kontrol**
- Yanıtta camelCase/snake_case alan adlarını fromJson satırlarıyla karşılaştırın
- QR yükünün SITE_JOIN: önekiyle başladığını doğrulayın

**İlgili testler:** [test/model_parsing_test.dart](../../test/model_parsing_test.dart)

**Bkz.:** [ui-qr-tarama-sayfasi](31-uygulama-arayuz.md#ui-qr-tarama-sayfasi)

<a id="model-yonetici-listesi-ve-davetler"></a>
### model-yonetici-listesi-ve-davetler · Site yöneticileri listesi ya da davet listesi boş/eksik; "Kurucu Yönetici" etiketi yanlış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/site_manager_record.dart:22](../../lib/models/site_manager_record.dart#L22) | <code>factory SiteManagerRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | user_code "as num" zorunlu; full_name yoksa "İsimsiz"; site_role yoksa SITE_ADMIN |
| [lib/models/site_manager_record.dart:37](../../lib/models/site_manager_record.dart#L37) | <code>String get roleLabel =&gt; isOwner ? 'Kurucu Yönetici' : 'Site Yöneticisi';</code> | is_owner true ise "Kurucu Yönetici", değilse "Site Yöneticisi" |
| [lib/models/site_manager_record.dart:63](../../lib/models/site_manager_record.dart#L63) | <code>factory SiteManagerInvitationRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | id, site_code, invited_by_user_code zorunlu sayı; status yoksa PENDING |
| [lib/models/site_manager_record.dart:91](../../lib/models/site_manager_record.dart#L91) | <code>factory SiteManagersData.fromJson(Map&lt;String, dynamic&gt; json) {</code> | managers ve invitations anahtarları; yoksa boş liste |
| [lib/services/auth_api.dart:4796](../../lib/services/auth_api.dart#L4796) | <code>return SiteManagersData.fromJson(data);</code> | Yanıt doğrudan SiteManagersData.fromJson ile çevrilir (_parsePayload yok); auth_service.getSiteManagers hatada sessizce null döner |

**Olası nedenler**
- is_owner alanı eksik: kurucu yönetici sıradan yönetici görünür
- Davet satırında invited_by_user_code ya da site_code null: TypeError
- Ayrıştırma hatası ekrana iletilmez: getSiteManagers null döner, liste boş/eksik görünür

**Adım adım kontrol**
- Yanıtta managers[] ve invitations[] öğelerinin alanlarını model satırlarıyla kıyaslayın

**İlgili testler:** [test/model_parsing_test.dart](../../test/model_parsing_test.dart)

**Bkz.:** [ui-site-yoneticisi-secici](31-uygulama-arayuz.md#ui-site-yoneticisi-secici)

<a id="model-misafir-linki-gecersiz"></a>
### model-misafir-linki-gecersiz · Misafir/kurye linki listede "süresi dolmuş" ya da "kullanım hakkı bitti" görünüyor, oysa yeni oluşturuldu

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/guest_pass.dart:30](../../lib/models/guest_pass.dart#L30) | <code>bool get isUsable =&gt; isActive &amp;&amp; !isExpired &amp;&amp; !isExhausted;</code> | Kullanılabilir = aktif ve süresi geçmemiş ve hakkı bitmemiş |
| [lib/models/guest_pass.dart:28](../../lib/models/guest_pass.dart#L28) | <code>bool get isExpired =&gt; DateTime.now().isAfter(expiresAt);</code> | Süre telefonun yerel saatine göre karşılaştırılır (DateTime.now) |
| [lib/models/guest_pass.dart:32](../../lib/models/guest_pass.dart#L32) | <code>factory GuestPassRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | max_uses yoksa 1, used_count yoksa 0, web_url yoksa boş; expires_at bozuksa şimdi |

**Olası nedenler**
- Telefon saati yanlış: isExpired yanlış hesaplanır (sunucu yalnız süresi geçmemiş ve hakkı bitmemiş linkleri listeler)
- expires_at bozuk/eksik: şimdiki zaman kullanılır, link hemen süresi dolmuş sayılır
- max_uses eksikse 1 varsayılır; kullanılmışsa isExhausted true olur

**Adım adım kontrol**
- Telefon saatini ve saat dilimini doğrulayın
- Yanıttaki expires_at metninin ISO 8601 olduğuna bakın

**Bkz.:** [ui-misafir-gecis-dugmesi](31-uygulama-arayuz.md#ui-misafir-gecis-dugmesi), [model-tarih-saat-yanlis](#model-tarih-saat-yanlis)

<a id="model-daire-uyelik-ve-site-yapisi"></a>
### model-daire-uyelik-ve-site-yapisi · Daire üyeleri ("Dairem"), daire/blok listesi ya da site yapısı eksik/yanlış görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/apartment_member_record.dart:76](../../lib/models/apartment_member_record.dart#L76) | <code>factory MyApartmentRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Alanlar snake_case ve camelCase anahtarlarla okunur; blok adı/şehir/ilçe yoksa boş metin |
| [lib/models/apartment_member_record.dart:24](../../lib/models/apartment_member_record.dart#L24) | <code>factory ApartmentMemberRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | is_apartment_admin yoksa role == APARTMENT_ADMIN'dan türetilir |
| [lib/models/apartment_record.dart:56](../../lib/models/apartment_record.dart#L56) | <code>factory ApartmentRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Yönetici görünümünde daire + tek sakin alanları (resident_*); "as int" zorunlu kimlikler |
| [lib/models/site_block_record.dart:16](../../lib/models/site_block_record.dart#L16) | <code>factory SiteBlockRecord.fromJson(Map&lt;String, dynamic&gt; json) {</code> | Blok: id ve site_code "as int" zorunlu; sort_order yoksa 0 |
| [lib/models/site_structure_record.dart:22](../../lib/models/site_structure_record.dart#L22) | <code>blocks: (json['blocks'] as List&lt;dynamic&gt;? ?? const &lt;dynamic&gt;[])</code> | blocks/apartments/doors anahtarları yoksa boş liste; yalnız site zorunlu |
| [lib/services/auth_api.dart:4620](../../lib/services/auth_api.dart#L4620) | <code>return list.map((item) =&gt; MyApartmentRecord.fromJson(item as Map&lt;String, dynamic&gt;)).toLis…</code> | Dairelerim yanıtının liste çevrimi (_parsePayload yok; öğe nesne değilse ham TypeError) |

**Olası nedenler**
- Sunucu anahtar biçimini (snake/camel) değiştirdi: modelde ikisi de okunur ama üçüncü bir ad boş bırakır
- Zorunlu kimlik (id, block_id) null: TypeError
- Yapı yanıtında anahtar adı değişince liste boş görünür (hata yok)

**Adım adım kontrol**
- Yanıt alan adlarını fromJson satırlarıyla kıyaslayın
- Yönetici için daire başına tek sakin alanlarının (resident_*) sunucuda doldurulduğuna bakın

**Bkz.:** [model-sakinler-agaci-yarim](#model-sakinler-agaci-yarim)

<a id="model-kullanici-hesabi-onay-ve-dogrulama"></a>
### model-kullanici-hesabi-onay-ve-dogrulama · Kullanıcı listesinde e-posta doğrulama durumu yanlış görünüyor (doğrulanmış kullanıcı "doğrulanmamış"); abonelik talebi satırı boş

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/models/managed_user_account.dart:66](../../lib/models/managed_user_account.dart#L66) | <code>emailVerified: json['email_verified'] as bool? ?? false,</code> | Alan yoksa (null) doğrulanmamış (false) sayılır; bool olmayan değer TypeError verir |
| [lib/models/managed_user_account.dart:67](../../lib/models/managed_user_account.dart#L67) | <code>approvalStatus: json['approval_status'] as String?,</code> | Onay durumu ham metin olarak saklanır; kullanıcı listesi arayüzünde bu alanı okuyan kod bulunmuyor |
| [lib/models/subscription_request.dart:16](../../lib/models/subscription_request.dart#L16) | <code>factory SubscriptionRequest.fromJson(Map&lt;String, dynamic&gt; json) {</code> | full_name/email yoksa boş metin; id zorunlu "as int" |
| [lib/models/super_user_account.dart:16](../../lib/models/super_user_account.dart#L16) | <code>factory SuperUserAccount.fromJson(Map&lt;String, dynamic&gt; json) {</code> | full_name ve email zorunlu (null olursa TypeError) |

**Olası nedenler**
- email_verified anahtarı gelmiyor: varsayılan false
- Abonelik talebinde alan adı farklı: satır boş metinle görünür

**Adım adım kontrol**
- Kullanıcı satırının ham JSON'unda email_verified ve approval_status alanlarına bakın
- users tablosunda aynı kullanıcının doğrulama durumunu SELECT ile görün

**Bkz.:** [sunucu-giris-403-eposta-dogrulanmadi](10-sunucu-api.md#sunucu-giris-403-eposta-dogrulanmadi)

