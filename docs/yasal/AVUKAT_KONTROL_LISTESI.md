# Avukat Kontrol Listesi (2026-10-16)

Bu liste, `server/legal/*.md` içindeki yasal metin taslaklarını yayına almadan önce bir avukatın karar vermesi veya doğrulaması gereken noktaları toplar. Her madde için: soru, **önerdiğimiz varsayılan**, gerekçe, kodda fiilen olan ve metinde nerede geçtiği yer alır. Kodla ilgili olgular `docs/yasal/VERI_ENVANTERI.md` içinde dosya:satır kaynaklıdır; koddan veya repodan doğrulanamayanlar orada "DOĞRULANAMADI" ile işaretlidir. Madde 28-33 sonradan eklenen açık sorunlardır.

Bu belge hukuki görüş değildir; kararlar avukata aittir. Öneriler, ürünün mevcut davranışını koruyarak riski azaltan en az değişiklik ilkesine göre yazılmıştır.

---

## 1. Rol ayrımı: kim veri sorumlusu, kim veri işleyen?

- **Soru:** Hesap ve platform verisi için Güde, site verisi için Site Yönetimi veri sorumlusu, Güde veri işleyen varsayımı doğru mu? Bir sakinin adı/e-postası/telefonu hem hesapta (Güde) hem sitenin kişi kaydında (SY) görünür: ortak veri sorumluluğu mu, ayrı sorumluluk mu?
- **Önerilen varsayılan:** İki ayrı sorumlu (metinlerde böyle yazıldı). Hesap bilgisinin siteye "görünür olması" sakinin siteye katılmasıyla SY'nin kendi sorumluluğundaki bir işleme olarak tanımlandı. Süper kullanıcı (Güde personeli) erişimi veri işleyen sıfatıyla destek/bakım amaçlıdır.
- **Gerekçe:** KVKK m.3'teki tanımlar ve Kurul'un güncel Kurul kararlarında rol tespiti fiili belirlemeye göre yapılır; netlik için metinde ayrıntılı ayrım var.
- **Kodda:** Süper kullanıcı tüm sitelerin kişi, finans ve geçiş kayıtlarına teknik olarak erişebilir (`people_access.js:29-33`, `door_log_routes.js:27`). Hesaptaki ad/telefon/e-posta, kişi siteye katılınca yöneticiye ve kurula hesaptan canlı görünür (`people_service.js:106-108`) ve aynı dairedeki üyeler birbirini görür (`membership_service.js:1415-1455`): tasarım sorusu için madde 30.
- **Metinde:** KVKK Aydınlatma bölüm 1; DPA bölüm 2.

## 2. Site yönetiminin hukuki niteliği ve DPA'nın akdi

- **Soru:** Site/apartman yönetiminin tüzel kişiliği yoktur. Veri sorumlusu kat malikleri kurulu mu, yönetici mi, yönetim şirketi mi? Site başvurusunu yapan kişi DPA'yı site adına bağlayıcı biçimde onaylayabilir mi? Kullandığımız "temsil yetkisi beyanı" yeterli mi?
- **Önerilen varsayılan:** Metinde veri sorumlusu "Site Yönetimi" olarak tanımlı; başvuran "yetkili olduğunu beyan eder"; onay `user_consents` içinde belge, sürüm ve zamanla kaydedilir.
- **Gerekçe:** Pratikte başvuran genelde yöneticidir; yetki yönetim planı ve kurul kararına dayanır. Ek güvence için başvuru ekranına "yetkiliyim" beyan kutusu eklenebilir.
- **Metinde:** KVKK bölüm 1.2 (AVUKAT işareti), DPA giriş ve bölüm 8.

## 3. Kat mülkiyeti ve finansal kayıtların saklama süresi; hesap silmeyle ilişkisi

- **Soru:** Aidat/borç/tahsilat defteri ve daire-kişi ilişki geçmişi ne kadar süre saklanmalı? Hesap silinince kişinin **adının** bu kayıtlarda kalması hukuka uygun mu?
- **Önerilen varsayılan:** (a) Defter ve ilişki geçmişi ilgili dönem sonundan itibaren **10 yıl** (TBK genel zamanaşımı); dönemsel aidat alacağı için kısa süre (5 yıl) tartışmalı olduğundan uzun olan alınır. (b) `CRM_KEEP_NAME = true` kalsın: ad (ve daire geçmişi) kayıtta kalır, hesaptaki e-posta, telefon, kullanıcı adı ve hesap bağlantısı kaldırılır (`account_common.js:19`, `account_deletion_service.js:531-541`). (c) Süre sonunda SY'nin silmesi/anonimleştirmesi gerekir; bugün otomatik iş yok.
- **Gerekçe:** Borcun kime ait olduğu ispatı (m.5/2-e) ve KMK'dan doğan yönetici hesap verme görevi (m.5/2-a) adın tutulmasını destekler; ad dışındaki iletişim verisi bu amaç için gerekli değildir (ölçülülük). Kurul'un 2026/348 sayılı ilke kararı da KMK kaynaklı ortak gider tahsili ve hesap verme için sınırlı veri işlemeyi kabul eder.
- **Doğrulanamayan atıflar:** KMK'nın yönetici defter/hesap/karar defteri maddeleri; VUK m.253 ve TTK m.82 saklama yükümlülüğünün site yönetimine uygulanıp uygulanmadığı; TBK m.146-147 (aidat alacağının 5 mi 10 yıl mı olduğu). Hepsi [AVUKAT DOĞRULASIN].
- **Kodda:** ledger silinemez, tek istisna site silinince CASCADE (`db.js:1586-1695`); CRM kayıtları silinmez; otomatik saklama süresi yok. Hesap silmede CRM'de ad, yönetimin girdiği telefon ve notlar ile araç plakası/notu kalır; hesaptaki telefon ve e-posta kopyalanmaz (`account_common.js:15-19`, `account_deletion_service.js:531-541`). Süper kullanıcının kalıcı silme yolunda ise ad ve telefon tetikleyiciyle CRM'e yedeklenir (`db.js:1168-1220`, `admin_routes.js:440-553`).
- **Metinde:** Gizlilik bölüm 7; Hesap Silme bölüm 3.
- **Alternatif:** `CRM_KEEP_NAME = false` yapılırsa ad "Silinmiş Kullanıcı" olur, ekstreler kime ait olduğunu göstermez; yönetim ispat riski taşır. Önerilmez.

## 4. Kapı geçiş kayıtları ve IP adresi

- **Soru:** Geçiş kaydı (ad, rol, daire etiketi, yöntem, zaman, IP) için 30 gün yeterli ve ölçülü mü? IP adresinin kaydı gerekli mi?
- **Önerilen varsayılan:** 30 gün kalsın (mevcut otomatik silme); IP kaydı kalsın ama yalnız yönetici/süper görsün (bugünkü durum). Daha uzun saklama isteyen siteler için ayar eklemeyin.
- **Gerekçe:** Kısa süre, veri en aza indirme ilkesine uygun; güvenlik olaylarında ilk haftalar yeterli. IP, sahte/yetkisiz kullanım tespiti için meşru menfaat (m.5/2-f).
- **Kodda:** `maintenance_service.js:58-63`; hesap silmede hesaba bağlı satırlarda ad ve IP silinir (`account_deletion_service.js:452-455`), ancak cihazdan senkronlanan çevrimdışı kayıtlarda `user_code` boş olduğundan ad 30 güne kadar kalır (`door_log_service.js:311-313`). Misafir bağlantısıyla yapılan geçişte IP misafire aittir; oluşturan sakinin "Verilerimi İndir" dosyasına girmemesi için dışa aktarmada `trigger_type='guest_pass'` satırlarının IP alanı boşaltılacaktır (kod düzeltmesi bekleniyor: `account_export_service.js:189-192`). Geçiş kaydı bir "iş kaydı" olduğundan çalışanlar (görevli) için ayrıca iş hukuku değerlendirmesi gerekebilir.

## 5. Konum verisi: açık rıza gerekir mi?

- **Soru:** Geofence/karekod için gönderilen konum (enlem, boylam, doğruluk, sahte konum bayrağı) açık rıza gerektirir mi, yoksa m.5/2-c ve f yeterli mi? Karekod belirteciyle kısa süre saklanması ölçülü mü?
- **Önerilen varsayılan:** Açık rıza kutusu eklemeyin; işletim sistemi konum izni + net aydınlatma + yalnız işlem anında alma. Metinde böyle yazıldı (işaretli).
- **Gerekçe:** Konum, sözleşmenin (kapı güvenliği) ifası için gereklidir ve site politikasına bağlıdır. Arka plan izleme yoktur (`AndroidManifest.xml:2-14`). Belirteçle saklama, site ayarına bağlı kısa ömürlü belirteç (`qr_rotation_seconds` site bazındadır: sunucu 10-300 sn arasına kısar, varsayılan 30; `site_rules.js:348-356`, `admin_routes.js:993-994`) + en geç ~2 gündür.
- **Kodda ayrıca:** ekransız (statik karekodlu) kapı cihazlarında karekod okutulurken konum, site ayarından bağımsız zorunludur (sitede konum merkezi tanımlıysa; `app_doors_routes.js:347-354`, `geofence_service.js:229`, `door_record.dart:135`); site yöneticisi geofence merkezini kendi o anki GPS konumuyla belirleyebilir (`site_security_policy_dialog.dart:214-231`).
- **Risk azaltma:** Uzaktan açmada konum hiç saklanmaz; karekodda saklanması gerekmiyorsa `request_latitude/longitude` yazımı kaldırılabilir (geliştirme).
- **Metinde:** KVKK bölüm 4 (AVUKAT işareti); Gizlilik 3.3, 4.

## 6. Yurt dışına aktarım olasılıkları

- **Soru:** Hangi akışlar yurt dışına veri götürebilir ve hangi KVKK m.9 mekanizması gerekir? Kurul'un 7499 sayılı Kanunla değişen m.9 düzeni (yeterlilik kararı, standart sözleşme, bağlayıcı şirket kuralları; standart sözleşmenin imzadan sonra 5 iş günü içinde Kuruma bildirimi) uygulanacak mı?
- **Önerilen varsayılan:** (a) VPS ve SMTP sağlayıcılarının ülkesi netleşene kadar metin "yurt dışı aktarım" cümlesini işaretli bırakıyor. (b) Türkiye'de barındırma/SMTP tercih edilirse aktarım olmaz. (c) **Cloudflare:** API alan adı Cloudflare kenar ağına çözümleniyor (turuncu bulut, 172.67.x.x; koordinatör bildirimi) → Cloudflare, API trafiği (oturum belirteçleri, kişisel veri yükleri) için vekil ve alt işleyendir; metinlerde böyle yazıldı. Yurt dışı aktarım değerlendirmesi ve Cloudflare ile sözleşme koşulları [AVUKAT DOĞRULASIN]. MQTT alan adının vekil olup olmadığı belirsiz (cihazlar için vekil olmaması beklenir); metinde belirsiz bırakıldı. (d) Kalan kaçınılmaz noktalar: Google bağlantı denetimi (`clients3.google.com/generate_204`, yalnız IP görünür); cihaz işletim sisteminin konuşma tanıma hizmeti (kullanıcının kendi cihazı, bizim aktarımımız değil); web sürümünde Google CDN (derleme ayarına bağlı); Android'de ML Kit.
- **Teknik öneri (geliştirme):** `generate_204` yedek denetimi kaldırılabilir veya kendi sunucumuzun ikinci adresine alınabilir; web derlemesi CanvasKit ve yazı tiplerini kendi sunucudan yüklesin.
- **Doğrulanan:** m.9 yeni düzeni (7499, RG 12.03.2024/32487, m.34; yürürlük 01.06.2024; geçiş 01.09.2024; standart sözleşme bildirimi 5 iş günü).
- **Metinde:** KVKK bölüm 5; Gizlilik bölüm 5-6; DPA 3.5, Ek-3.

## 7. VERBİS yükümlülüğü eşikleri

- **Soru:** Güde ve her Site Yönetimi VERBİS'e kayıt yükümlüsü mü?
- **Önerilen varsayılan:** Güde için çalışan sayısı ve yıllık mali bilanço toplamıyla değerlendirme yapılsın (aşağıdaki eşikler); eşiğin altındaysa kayıt yükümlülüğü yoktur ama aydınlatma, güvenlik ve silme/imha yükümlülükleri sürer. Site yönetimleri için (genellikle çalışan/bilanço yok) avukat görüşü alın; metinlerde VERBİS'ten söz edilmedi.
- **Doğrulananlar (ikincil kaynaklarla):** Kurul'un 04.09.2025 tarihli 2025/1572 sayılı kararı: yıllık çalışan sayısı 50'den az **ve** yıllık mali bilanço toplamı 100 milyon TL'den az olanlar (ana faaliyeti özel nitelikli kişisel veri işleme olmayanlar) muaf; ana faaliyeti özel nitelikli veri işlemek olanlarda 10'dan az çalışan ve 10 milyon TL'den az bilanço. 25.12.2025 tarihli 2025/2393 sayılı karar: bilanço esasına göre defter tutmayanlarda yalnız çalışan sayısı; tutanlarda iki ölçüt birlikte. 12.01.2026 tarihli kamuoyu duyurusu: muaf olanlar kaydı sildirebilir veya sicilde kalabilir.
- **Doğrulanamayanlar:** bu kararların Resmî Gazete tarihi ve yürürlüğü; site/apartman yönetimlerine özgü bir muafiyet kararı. [AVUKAT DOĞRULASIN]
- **Ek:** Saklama ve imha politikası yalnız sicile kayıt yükümlülerine zorunludur (Silme Yönetmeliği m.5/1) ama diğerleri silme/imha yükümlülüğünden kurtulmaz (m.5/3); periyodik imha aralığı altı ayı geçemez (m.11/2) — doğrulandı.

## 8. Açık rıza gereken ve gerekmeyen işlemler; "okudum, onaylıyorum"

- **Soru:** Kayıtta KVKK Aydınlatma Metni onayı alınıyor (`required_for: [register]`). Bu açık rıza gibi görünürse sorun olur mu? Hangi işlemler açık rıza gerektirir?
- **Önerilen varsayılan:** Onay kutusu metni "aydınlatma metnini okudum" (bilgilendirildim) olsun, **açık rıza ifadesi içermesin**; ayrı bir açık rıza kutusu eklemeyin. Metin bunu açıkça yazıyor.
- **Gerekçe (doğrulandı):** Aydınlatma Tebliği m.5(d) aydınlatmanın talebe bağlı olmadığını, m.5(e) ispat yükünün veri sorumlusunda olduğunu, m.5(f) aydınlatma ile açık rızanın ayrı yapılması gerektiğini söyler. Onayın amacı ispat kaydıdır.
- **Açık rıza gerektirmediğini düşündüğümüz işlemler:** hesap, kapı geçişi, CRM, aidat, duyuru, hata raporu, konum (madde 5). **Açık rıza veya ayrıca izin gerekebilecekler:** ileride push bildirimi, ticari içerikli iletiler, pazarlama.
- **Kodda:** `user_consents` kaydı; `legal.enforce_consents` anahtarı (varsayılan kapalı).

## 9. Duyuru e-postaları: ticari ileti mi, bilgilendirme mi (6563)?

- **Soru:** Site yönetiminin duyuru e-postaları 6563 sayılı Kanun kapsamında "ticari elektronik ileti" mi sayılır (önceden onay + İYS)?
- **Önerilen varsayılan:** Hayır; yönetim bilgilendirmesidir. Kullanım Koşulları duyuruların ticari/reklam amacıyla kullanılmasını yasaklıyor. Yine de her e-postada tek tıkla abonelikten çıkma ve tercih bulunuyor.
- **Gerekçe:** 6563 m.2'ye göre ticari elektronik ileti "ticari amaçlarla gönderilen" iletidir (ikincil kaynaklarla doğrulandı); aidat, bakım, toplantı duyurusu ticari amaç taşımaz.
- **Doğrulanamayan:** Ticari İletişim ve Ticari Elektronik İletiler Hakkında Yönetmelik (RG 15.07.2015/29417, ikincil kaynak) kapsamındaki istisnalar. Bir sitede yönetim reklam/sponsor duyurusu yaparsa ticari ileti niteliği doğar.
- **Dikkat:** Acil duyurular kullanıcının e-posta tercihini atlar (tercih yalnız normal duyuruları durdurur); bağlantıyla çıkış her şeyi durdurur (`mailer.js:640-698`, `docs/PLATFORM_DUYURU.md` madde 14-15). Bu davranış "itiraz hakkı" açısından kabul edilebilir mi? [AVUKAT DOĞRULASIN]
- **Hesapsız kişilere e-posta:** yönetimin girdiği adres doğrulanmaz; yanlış adrese gitme riski ve SY'nin hukuki dayanağı.

## 10. Site yönetiminin veri sorumlusu olarak yükümlülükleri

- **Soru:** SY'ye (Kullanım Koşulları bölüm 5 ve DPA bölüm 4) yüklediğimiz yükümlülükler yeterli ve uygulanabilir mi?
- **Önerilen varsayılan:** Mevcut hâl. Başlıca maddeler: aydınlatma (özellikle hesabı olmayan kişiler), hukuki sebep, doğruluk, yetkilendirme ve yetki kaldırma, ilgili kişi başvurularını 30 gün içinde yanıtlama, ihlalde Kurula 72 saat içinde bildirim, VERBİS/saklama-imha yükümlülüğü varsa yerine getirme, borç listelerini ortak alanlara asmama.
- **Doğrulanan:** Başvuruya en geç 30 gün içinde yanıt (Başvuru Tebliği m.6); ihlalde 72 saat (Kurul 2019/10, 24.01.2019); Kurul'un 18.02.2026 tarihli 2026/348 sayılı ilke kararı (RG 31.03.2026/33210): borç/aidat/avans bilgilerinin bina girişi, asansör, koridor gibi ortak alanlara asılması KVKK m.5'teki işleme şartına dayanmaz ve m.12'ye aykırıdır; kapalı e-posta/mesajlaşma grupları veya bu hizmete özgülenmiş uygulamalar gibi yalnız ilgililerin erişebileceği yöntemler gerekir. Kararın tam metni okunamadı (başlık/sayı Resmî Gazete listesinde doğrulandı, içerik ikincil özetlerden). [AVUKAT DOĞRULASIN]
- **Ürün tasarımı bu karara uyumludur:** borç bilgisi yalnız ilgili kişilere uygulama içinde gösterilir. Dikkat edilecekler: kurul üyesi **tüm** daire bakiyelerini ve malik/kiracı adlarını görür; sakin dairenin önceki kiracı dönemini de görür (`docs/PLATFORM_FINANS.md` risk 7). Kurul üyesinin tam görünürlüğü için karar defteri/yönetim planı dayanağı ve gizlilik taahhüdü gerekir mi?

## 11. Kamera, plaka ve benzeri veriler

- **Soru:** Kamera/plaka tanıma kullanılmıyorsa metinde "yapılmaz" demek yeterli mi?
- **Önerilen varsayılan:** Metinde "kamera görüntüsü kaydedilmez, yüz tanıma ve otomatik plaka tanıma yapılmaz" yazıyor. Plaka yalnız yönetimin elle girdiği bir kayıt; hukuki sebep m.5/2-f (otopark ve site güvenliği).
- **Doğrulandı:** kodda kamera/ANPR/biyometri yok (`pubspec.yaml`, `AndroidManifest.xml`). Kamera izni yalnız karekod okumak içindir.
- **Soru ek:** Plaka kaydı pasifleştikten sonra silinmiyor (madde 15).

## 12. Hesabı olmayan kişiler ve misafirler

- **Soru:** Yönetimin kaydettiği ve hiç hesabı olmayan kişilere (malik, kiracı, aile üyesi) aydınlatmayı kim, nasıl yapacak? Misafir bağlantısını kullananın IP'si için aydınlatma?
- **Önerilen varsayılan:** Aydınlatma yükümlülüğü SY'dedir (DPA bölüm 4, Kullanım Koşulları bölüm 5); platform hesaplı kullanıcıya KVKK metnini gösterir. Hesapsız kişi için platform tarafından otomatik aydınlatma e-postası YOK; eklenmesi önerilir (geliştirme) veya SY'ye hazır bir aydınlatma şablonu verilmelidir. Misafir için yalnız IP işlenir; misafir sayfasına tek cümlelik bilgilendirme ve Gizlilik linki eklenmesi önerilir (geliştirme: `guest_pass_utils.js` sayfası).
- **Kodda:** CRM hesapsız kişiyi e-posta ile duyuru kitlesine alır (`docs/PLATFORM_DUYURU.md` Kitle kuralı).

## 13. Çocuklar ve yaş sınırı

- **Soru:** "18 yaş" koşulu ve küçüklerin (aile üyesi olarak CRM'e girilen) verisi için ifade yeterli mi?
- **Önerilen varsayılan:** Terms/Privacy: hesap için 18 yaş; küçüklerin kaydından SY sorumlu, en az veri. Kayıtta yaş doğrulaması yok (yalnız beyan).
- **Doğrulanamayan:** erginlik yaşının TMK'daki maddesi (genel bilgiyle 18) ve küçüklerin verisinin işlenmesi için velinin rolü. [AVUKAT DOĞRULASIN]

## 14. Daire PIN'inin düz metin saklanması

- **Soru:** Eski tip "daire hesabı" PIN'i `apartments.resident_pin_code` sütununda düz metin ve e-postayla düz gönderiliyor. Bu, KVKK m.12 teknik tedbir yükümlülüğü ve gizlilik metinlerindeki "parola özet olarak saklanır" ifadesiyle bağdaşır mı?
- **Önerilen varsayılan:** (1) Metinler istisnayı açıkça yazıyor (bugünkü hâliyle). (2) Önerilen: geliştirme ile düz kopyayı kaldırmak (PIN yalnız oluşturulurken bir kez gösterilsin/e-postalansın), sonra metindeki istisna cümleleri silinsin.
- **Gerekçe:** Düz metin parola, yönetici ve veritabanı yedeklerini okuyan herkes için hesap ele geçirme riski; ihlal halinde sorumluluk artar.
- **Kodda:** `membership_service.js:1891-1978`, `apartment_service.js:63-105`, `mailer.js:160-194`; PIN site yöneticisi tarafından da görülür (`site_service.js:741`). Ayrıca ana ekran widget'ında oturum anahtarının bir kopyası işletim sisteminin anahtar deposunda değil widget deposunda tutulur (`door_widget_service.dart:496`); metinlerde "güvenli depolama" iddiası bu kopyayı kapsamayacak şekilde yazıldı.
- **Metinde:** Gizlilik bölüm 8; DPA Ek-2 (KARAR işareti).

## 15. Süresiz saklanan kayıtlar ve saklama/imha politikası

- **Soru:** Otomatik silinmeyen kayıtlar için süre ne olmalı? Bunlar: denetim kaydı, yasal onay kayıtları, misafir geçiş bağlantıları, katılım başvuruları ve davetler, abonelikten çıkma özetleri, pasif araç/kişi kayıtları, yayınlanmış duyurular, site başvuruları.
- **Önerilen varsayılan (işaretli, avukat onayına tabi):** denetim kaydı 5 yıl; yasal onay kayıtları hesap kapanışından/sürüm geçersizliğinden itibaren 10 yıl; misafir bağlantıları süre bitiminden 30 gün; katılım başvuruları ve davetler karardan 1 yıl; abonelikten çıkma özetleri süresiz (itirazı korumak için); pasif araç kaydı 1 yıl; site başvurusu kararından 5 yıl.
- **Kodda:** bu kayıtlar için temizlik işi yok (`maintenance_service.js:13-94` yalnız token/kod/geçiş/bağlantı kayıtlarını siler). Süreler kararlaştırılınca temizlik işi yazılmalıdır. `audit_log` değişmezdir (yalnız eklenir); hesap silindiğinde eski satırlardaki ad anlık görüntüsü değiştirilmez (karar: koordinatör) ve site silindiğinde de temizlenmez (`db.js:992`: `site_code` yabancı anahtarı yok; geliştirme bekliyor). `audit_log.details` hesabı olmayan kişinin eski/yeni adını, plakaları ve silinen dairenin geçmiş sakinlerinin ad/tarihlerini taşıyabilir (`people_service.js:952-960`, `vehicle_service.js:157,190`, `apartment_deletion_audit.js:60-96`); kayıtların kişi/daire/araç geçmişi kısmını yönetici ve kurul üyeleri görür (`people_history_service.js:104-116`, `people_access.js:83-84`). Bu içerik için ayrıca saklama süresi ve görünürlük değerlendirmesi gerekir.
- **Doğrulandı:** periyodik imha ≤ 6 ay (Silme Yönetmeliği m.11/2).
- **Metinde:** Gizlilik bölüm 7 (KARAR işareti).

## 16. Güde personeli / süper kullanıcı erişimi

- **Soru:** Güde personelinin tüm sitelerin verisine teknik erişimi var. DPA'daki "yalnız destek/bakım/güvenlik/başvuru" sınırı ve gizlilik taahhüdü yeterli mi? Personel için ayrı bir gizlilik sözleşmesi ve erişim kaydı gerekli mi?
- **Önerilen varsayılan:** Süper kullanıcı sayısını en aza indirin; personel gizlilik taahhütnamesi imzalatın; yönetim işlemleri denetim kaydına yazılıyor (okuma erişimi yazılmıyor). Süper kullanıcının site verisini görüntülemesi için "destek talebi" ilkesini DPA'ya ekleyin.
- **Kodda:** `people_access.js:29-33`; denetim yalnız yönetim yazma işlemlerinde (`audit_service.js`); süper kullanıcının **okumaları kaydedilmez**; bazı olaylar yalnız konsol günlüğüne düşer (`helpers.js:7-14`). Metinlerde "kayıtlı erişim" iddiası bu duruma göre yazıldı (değiştirme işlemleri kayıtlı, salt görüntüleme kayıtsız).
- **Metinde:** DPA 3.2 (KARAR işareti), Ek-2.

## 17. Veri ihlali bildirim akışı

- **Soru:** DPA'da Güde'nin SY'ye 24 saat içinde bildirimi, SY'nin Kurula 72 saat içinde bildirimi doğru ve uygulanabilir mi?
- **Önerilen varsayılan:** Mevcut metin (24 saat Güde → SY; 72 saat SY → Kurul; kişilere makul en kısa süre).
- **Doğrulandı (kvkk.gov.tr, Kurul 24.01.2019 tarih ve 2019/10 sayılı karar):** veri sorumlusu öğrendiği tarihten itibaren gecikmeksizin ve en geç 72 saat içinde Kurula; veri işleyen gecikmeksizin veri sorumlusuna; ilgili kişilere ihlalden etkilenenler belirlendikten sonra makul en kısa sürede.
- **Not:** 24 saat Güde'nin iç taahhüdüdür; 72 saatlik sürenin SY için öğrenme anından başladığı kabul edilir. Güde'nin operasyonel olarak ihlali 24 saatte tespit edip bildirebilecek bir süreci (nöbet, e-posta listesi) var mı? Kullanıcıdan gerekli.
- **Kodda:** erişilebilirlik izlemesi var (sunucuda 5 dakikada bir `deploy/ops/healthcheck.sh`: API sağlığı, PM2, Postgres, disk, yedek yaşı, TLS bitişi, MQTT uçları, uyarı e-postası süper kullanıcılara; ayrıca `.github/workflows/uptime.yml` ile GitHub Actions `/health` yoklaması), ancak kişisel veri ihlali tespiti yok: yetkisiz erişim, veri sızması veya anormal kullanım için izleme/uyarı sistemi bulunmaz (`docs/codebase/INTEGRATIONS.md`: APM yok). Süper kullanıcı okumaları kaydedilmez (madde 16).

## 18. Sorumluluk sınırları, genel işlem koşulları, tüketici hukuku

- **Soru:** Kullanım Koşulları bölüm 11'deki sorumluluk sınırlaması (kast/ağır kusur dışı; üst sınır) TBK sorumsuzluk anlaşması ve genel işlem koşulları kurallarına, ayrıca 6502 sayılı TKHK'ya uygun mu? Yetki şartı?
- **Önerilen varsayılan:** Metin emredici hükümleri ve tüketici haklarını saklı tutar; kast ve ağır kusuru sınırlamaz; üst sınır "ödenen bedel" esaslı (hizmet şu anda bedelsiz olabileceğinden tutar belirlenmeli).
- **Doğrulandı:** TBK m.115/1: "Borçlunun ağır kusurundan sorumlu olmayacağına ilişkin önceden yapılan anlaşma kesin olarak hükümsüzdür."
- **Doğrulanamayan:** TBK m.20-25 (genel işlem koşulları: tanım m.20, dahil edilme/yazılmamış sayılma m.21, içerik denetimi m.25 ikincil kaynaklara göre); TKHK m.73 (tüketici mahkemesi görevi ve tüketicinin yerleşim yeri yetkisi, ikincil kaynak); HMK m.17 yetki sözleşmesinin tüketici işlemlerindeki sınırı. [AVUKAT DOĞRULASIN]
- **Not:** Site yöneticisi (tacir olmayan gerçek kişi/kurul) tüketici mi? Güde ile ilişki "tüketici işlemi" sayılırsa haksız şart denetimi uygulanır. Yetkili mahkeme bilgisi kullanıcıdan gerekli.
- **Kabul mekanizması:** Koşullar kayıtta tıklayarak kabul edilir; sürüm değişince yeniden onay istenir (TBK genel işlem koşullarının karşı tarafa bildirilmesi ve kabulü için yeterli mi?).

## 19. Finans modülünün hukuki konumu

- **Soru:** "Platform ödeme/muhasebe hizmeti değildir; kayıtlar belge yerine geçmez" ifadesi doğru mu? Defterin değişmezliği ve ters kayıt yöntemi yasal kayıt/belge gereklerini karşılar mı? 6493 sayılı Kanun kapsamı dışında kalındığı teyit edilsin.
- **Önerilen varsayılan:** Metin böyle yazıldı (işaretli). Online ödeme yok; para tutulmaz/aktarılmaz; tahsilat elle girilir (nakit, havale, çek). Faz 4b'de makbuz PDF eklenirse makbuzun hukuki niteliği (belge yerine geçme, e-makbuz/e-arşiv gereği) ayrıca değerlendirilmeli.
- **Kodda:** `docs/PLATFORM_FINANS.md` Kapsam; ledger tetikleyicileri.

## 20. Onay mekanizması ve ispat

- **Soru:** `user_consents` kaydı (belge kimliği, sürüm, zaman, kaynak) ispat için yeterli mi? IP/cihaz bilgisi de saklanmalı mı? `legal.enforce_consents` ne zaman açılmalı?
- **Önerilen varsayılan:** Mevcut alanlar yeterli; IP saklamayın (veri en aza indirme). Tüm belgeler avukat onayından geçip işaretler temizlendikten ve `complete: false` satırı kaldırıldıktan sonra `enforce_consents` açılsın.
- **Not:** Bu belgelerde front-matter'da `complete: false` var; bu, sunucunun belgeyi eksik saymasını ve zorunlu onayın açılmamasını sağlar.
- **Kodda:** onay kaydı yalnız tamamlanmış (`complete:true`) ve `required_for` içeren belgeler için yazılır; `complete:false` belge için **hiç** kayıt yazılmaz (`legal_consent_service.js:72,92-95`). Belgeler yayınlanmadan önce kayıt olan kullanıcılar için onay kaydı bulunmaz; yayından sonra `GET /me/consents` bu kullanıcıları "bekleyen onay" olarak listeler. Yayın öncesi kayıt olanlardan yeniden onay alınıp alınmayacağı kararlaştırılmalıdır. Metinlerde (KVKK §4, DPA §8) "onay kaydı yalnız yayımlanmış belge sürümleri için tutulur" yazıldı.

## 21. Hata raporları ve rastgele kurulum kimliği

- **Soru:** Hata raporu (kullanıcı/cihaz/IP saklanmaz; istemci rastgele `install_id` yollar, tabloya yazılmaz) için açık rıza veya devre dışı bırakma seçeneği gerekir mi?
- **Önerilen varsayılan:** Gerekmez (m.5/2-f; kişisel veriden arındırılmış). İstemcide `install_id` hız sınırı içindir. İsteğe bağlı: Profil'e "hata raporu gönder" anahtarı eklemek riski sıfırlar (geliştirme).
- **Kodda:** `crash_reporter.dart:100-118`, `035_platform_services.sql:23-50`.

## 22. Yedekler ve silme talepleri

- **Soru:** Silinen/kimliksizleştirilen verilerin yedeklerdeki kopyaları ne zaman yok edilmeli?
- **Önerilen varsayılan:** Yedek döngüsü içinde yok olur: sunucuda günlük 14, haftalık 8, aylık 6 yedek (`deploy/ops/backup_db.sh:21-23`); dış kopyalar en çok yaklaşık 210 gün (OPS düzeltmesi sürüyor; repodaki betikte dış kopya adedi 14'tür, `:24`). Bu nedenle silinen verinin yedeklerden yok olması **en geç yaklaşık 7 ay**; metinlerde bu süre `[KARAR/BİLGİ GEREKLİ]` işaretiyle yazıldı. Yedeklerin şifreleme durumu: haftalık/aylık ve dış kopyalar şifreli, en son günlük döküm şifresiz ama 600/700 izinli (koordinatör bildirimi; repoda haftalık/aylık kopyalar düz kopya olarak görülür: `backup_db.sh:82-110`); yedek konumlarından biri yönetim (Windows) bilgisayarı olabilir (`pull_backups_windows.ps1`). Geri yüklenen yedekte silinmiş hesap yeniden belirirse silme işleminin yeniden uygulanması prosedürü yazılsın.
- **Doğrulanamayan:** betiklerin üretimde zamanlanıp çalıştığı (OPS çıktısı); dış kopya yapılandırması.

## 23. Üçüncü taraf ve işletim sistemi temas noktaları

- **Soru:** Ses komutu (cihazın konuşma tanıma hizmeti), karekod okuyucu (Android ML Kit), Google bağlantı denetimi, web CDN, mağazalar için metinlerdeki ifade yeterli mi?
- **Önerilen varsayılan:** Metinler bu noktaları açıklıyor; Google bağlantı denetimi ve web CDN için teknik düzeltme önerildi (madde 6). Ses komutu isteğe bağlıdır; mikrofon izni reddedilince özellik çalışmaz.
- **Doğrulanamayan:** ML Kit'in tanılama verisi gönderip göndermediği; Flutter web derlemesinin CDN kullanımı.

## 24. Rol bazlı görünürlük

- **Soru:** Kurul üyesi (tüm daire bakiyeleri, malik/kiracı adları, kişi listesi) ve sakinin (önceki kiracı dönemi dahil dairenin hareketleri) görünürlüğü ölçülü mü?
- **Önerilen varsayılan:** Kurul görünürlüğü yönetim planı/kurul kararıyla desteklenirse kalsın; SY'nin kurul üyesini atarken bunu bilmesi için uyarı metni eklensin. Sakinin önceki kiracı dönemi hareketlerini görmesi için ürün tarafında "yalnız kendi dönemi" kısıtı önerilir (geliştirme).
- **Kodda:** `finance_routes.js:272-278`; `docs/PLATFORM_FINANS.md` risk 7.

## 25. İlgili kişi başvuru kanalları

- **Soru:** Başvuru yöntemleri doğru tarif edildi mi? Uygulama içi "Verilerimi İndir" ve "Hesabımı Sil" başvuru yazılımı yerine geçer mi?
- **Önerilen varsayılan:** Metin: kayıtlı e-posta, KEP/güvenli e-imza, yazılı; ad-soyad, T.C. kimlik no (yabancılar için uyruk/pasaport), tebligat adresi, bildirim e-postası/telefon, talep konusu; 30 gün; ücretsiz (10 sayfaya kadar). Uygulama içi işlemler ek kolaylık olarak sunuluyor.
- **Doğrulandı:** Başvuru Tebliği (RG 10.03.2018/30356) m.5 (yazılı, KEP, güvenli e-imza, mobil imza, kayıtlı e-posta veya başvuru amacına yönelik yazılım/uygulama), m.5/2 içerik, m.6 (30 gün), m.7 (ücret).
- **Doğrulanamayan:** Kurula şikâyet süreleri (cevabı öğrenmeden 30 gün, her halde başvurudan 60 gün; Kurul 2019/9 ikincil kaynaklarda) — metinde süre yazılmadı. [AVUKAT DOĞRULASIN]
- **Not:** E-postayla T.C. kimlik no istemek veri en aza indirme açısından tartışmalı; Tebliğ gereği metinde yazıldı.

## 26. Alt işleyen sözleşmeleri

- **Soru:** Barındırma, SMTP ve DNS sağlayıcılarıyla yapılmış veri işleme sözleşmeleri var mı? Sağlayıcıların kendi koşulları yeterli mi? Yurt dışındaysa m.9?
- **Önerilen varsayılan:** Sağlayıcı adları kullanıcıdan alınıp DPA Ek-3 ve Gizlilik bölüm 6'ya yazılsın; her biriyle yazılı gizlilik/veri işleme hükümleri kontrol edilsin.

## 27. Push bildirimi (ileride)

- **Soru:** İleride Firebase/FCM eklenirse ne gerekir?
- **Önerilen varsayılan:** Şu an YOK; metinde işaretli bir cümle var. Eklenirse: yeni alt işleyen, olası yurt dışı aktarım (m.9), cihaz belirteci verisi, izin akışı (iOS/Android 13 bildirim izni), Gizlilik/KVKK/DPA sürümlerinin yükseltilip yeniden onay istenmesi.

## 28. DPA onayı alınmayan site açma yolları (açık sorun)

- **Soru:** Veri İşleme Sözleşmesi yalnız site başvurusu akışında (`required_for: [site_application]`) onaylatılıyor. Sahiplik bağı olan yöneticinin anında site kurması (`POST /membership/setup-site`, `membership_routes.js:106-130`) ve süper kullanıcının site oluşturması (`POST /admin/sites`, `admin_routes.js:700`; ikisi de `site_setup_core.js` / `membership_service.js:741` üzerinden) DPA onayı almıyor (`resolveAcceptedDocuments` yalnız `site_application_service.js:437` ve kayıt akışında çağrılıyor). Bu sitelerde Güde'nin veri işleyen sıfatı yazılı sözleşmesiz kalır mı?
- **Önerilen varsayılan:** Geliştirme: setup-site ve süper kullanıcı akışına DPA onayı (sürüm ve zamanla `user_consents` kaydı) eklensin; mevcut sitelerin yöneticilerinden bir sonraki girişte onay istensin. DPA metni "site başvurusunda ya da Platformda site oluşturulurken onaylanır" diye yazıldı ve bu geliştirme için DPA girişinde işaret bırakıldı.
- **Metinde:** DPA giriş ve bölüm 8 (KARAR işareti).

## 29. E-posta ile hesap silme talebi ve süper kullanıcının kalıcı silme yolu

- **Soru:** Uygulamaya erişemeyen kişinin e-posta ile silme talebi için yönetim aracı yok; yetkili personel `DELETE /admin/users/:id` ile hesabı **kalıcı** siler (`admin_routes.js:440-553`). Bu yolun sonuçları kullanıcının uygulamadaki silmesinden farklıdır: hesap satırı tamamen silinir; yasal onay kayıtları CASCADE ile silinir (ispat kaybı); kapı geçiş kayıtlarında ad ve IP 30 gün kalır; CRM'e ad ve telefon yedeklenir; "hesabınız silindi" e-postası gitmez. İki yöntem arasındaki fark hukuken kabul edilebilir mi?
- **Önerilen varsayılan:** Geliştirme: yönetici için de kimliksizleştirme (kullanıcının kendi silmesiyle aynı sonuçlar) aracı. O zamana kadar e-posta ile gelen taleplerde kullanıcı önce "Şifremi unuttum" ile hesaba girip uygulamadan silmeye yönlendirilsin; yalnız erişemeyenler için kalıcı silme kullanılsın ve farklar Hesap ve Veri Silme §4'te açıkça anlatılsın (öyle yazıldı).
- **Metinde:** Hesap ve Veri Silme §4 (KARAR işareti).

## 30. Hesap bilgilerinin CRM'de canlı görünmesi ve aynı daire üyelerinin birbirini görmesi (tasarım sorusu)

- **Soru:** Bir kişinin hesabındaki ad, telefon ve e-posta, siteye katıldığında yönetici ve kurul üyelerine **hesaptan canlı** gösteriliyor (`people_service.js:106-108`); aynı daireye bağlı üyeler birbirinin ad/e-posta/telefonunu görüyor (`membership_service.js:1415-1455`). Bu görünürlük ölçülü mü, hukuki dayanağı nedir, ürün tarafında kısıtlanmalı mı?
- **Önerilen varsayılan:** Yönetici için kalsın (m.5/2-a, e); kurul üyesi için ad ve daire yeterli, telefon/e-posta gizlenebilir; aile üyeleri/diğer daire üyeleri birbirinin e-posta ve telefonunu görmesin, yalnız ad görünsün (geliştirme). O zamana kadar KVKK, Gizlilik ve DPA metinleri bu görünürlüğü açıkça yazıyor.
- **Metinde:** KVKK §2, §5; Gizlilik §3.1, §6; DPA §2.2.

## 31. Öz hizmet işlemlerinde veri işleyen rolü

- **Soru:** "Verilerimi İndir" ve "Hesabımı Sil", Site Yönetiminin talimatı olmadan Site Verisinin kullanıcıya ait kısmını okuyor/değiştiriyor (`account_export_service.js:148-166,189-192,275`; `account_deletion_service.js:404-541`). Bu, veri işleyenin yalnız veri sorumlusunun talimatıyla hareket etmesi ilkesiyle uyumlu mu? İlgili kişinin kendi hakkını kullanması istisnası yeterli mi?
- **Önerilen varsayılan:** DPA bölüm 2.4 bu işlemleri "ilgili kişinin kendi hakkını kullanması" olarak tanımlıyor ve işaretli bırakıldı; DPA'ya, Site Yönetiminin yasal saklama kayıtlarının silinmediği açıkça yazıldı (bölüm 5.4).
- **Metinde:** DPA §2.4, §5.4.

## 32. Denetim kaydının içeriği, görünürlüğü ve hesap silmedeki değişmezliği

- **Soru:** `audit_log` değişmezdir; hesap silinse de eski satırlardaki ad anlık görüntüsü değişmez (koordinatör kararı). Ayrıntı alanı (`details`) hesabı olmayan kişinin eski/yeni adını, plakaları ve silinen dairenin geçmiş sakinlerinin ad ve tarihlerini taşıyabilir; yönetici ve kurul üyeleri bunların kişi/daire/araç geçmişi kısmını görür. Site silindiğinde `audit_log` temizlenmiyor. Bu içerik ve süre hukuken savunulabilir mi?
- **Önerilen varsayılan:** Saklama süresi 5 yıl ve site silindiğinde temizlik (geliştirme); `details` içindeki adların kısaltılması veya yalnız kimlik numarası saklanması düşünülebilir; metinler mevcut durumu açıkça yazıyor (KVKK §2, Hesap Silme §3, DPA §5.3 işareti).
- **Metinde:** KVKK §2; Hesap ve Veri Silme §3; DPA §5.3, Ek-1.

## 33. Giriş cihazı belirteci ve widget oturum kopyası

- **Soru:** (a) İstemci, giriş cihazı belirtecini güvenli depoda saklar, çıkışta silmez, hesap silmede siler (180 gün, en çok 8 tanımlayıcı; `login_device_token_store.dart`); bu bir "cihaz tanımlayıcısı" olarak ayrıca aydınlatma/izin gerektirir mi? (b) Ana ekran widget'ı için oturum anahtarının bir kopyası anahtar deposunda değil widget deposunda (Android SharedPreferences / iOS App Group UserDefaults) tutuluyor (`door_widget_service.dart:496`); bu, "güvenli depolama" ve teknik tedbir iddialarıyla bağdaşır mı?
- **Önerilen varsayılan:** (a) Giriş güvenliği için meşru menfaat (m.5/2-f), metinde açıklandı; (b) Metinler kopyayı açıkça anlatıyor; teknik olarak widget için kısa ömürlü ayrı bir belirtece geçilmesi önerilir (geliştirme).
- **Metinde:** Gizlilik §3.7, §8; DPA Ek-2.

---

## Atıf doğrulama durumu

**Doğrulananlar (kaynakla):**
- KVKK m.10 (a-d unsurları): metin alıntısı hukukihaber.net; Aydınlatma Yükümlülüğünün Yerine Getirilmesinde Uyulacak Usul ve Esaslar Hakkında Tebliğ (RG 10.03.2018/30356): m.4 içerik, m.5(d), m.5(e), m.5(f). Kaynak: resmigazete.gov.tr/eskiler/2018/03/20180310-5.htm.
- Veri Sorumlusuna Başvuru Usul ve Esasları Hakkında Tebliğ (RG 10.03.2018/30356): m.5, m.6, m.7. Kaynak: resmigazete.gov.tr/eskiler/2018/03/20180310-6.htm.
- KVKK m.11 hakları (a-ğ): lexpera ve cottgroup özetleri (ikincil).
- Kurul 24.01.2019 tarihli 2019/10 sayılı karar (72 saat; veri işleyenin gecikmeksizin bildirimi; ilgili kişilere makul en kısa süre): kvkk.gov.tr/Icerik/5362/Veri-Ihlali-Bildirimi (birincil).
- 7499 sayılı Kanun (RG 12.03.2024/32487): m.34 ile KVKK m.9 değişikliği, m.36 geçici madde (01.09.2024), yürürlük 01.06.2024, standart sözleşme bildirimi 5 iş günü: resmigazete.gov.tr/eskiler/2024/03/20240312-1.htm.
- Silme, Yok Etme veya Anonim Hale Getirme Yönetmeliği (RG 28.10.2017/30224; değ. 28.04.2019/30758): m.5, m.7, m.11/2, m.12: kvkk.gov.tr/Icerik/5441.
- Kurul 18.02.2026 tarihli 2026/348 sayılı ilke kararı (RG 31.03.2026/33210): Resmî Gazete listesinde başlık ve sayı doğrulandı; içerik ikincil özetlerden (alomaliye, cottgroup). m.5/2 (a) ve (e) bentlerine atıf bu özetlerde geçer.
- TBK m.115/1 metni: av-saimincekas.com.
- VERBİS eşikleri (2025/1572, 2025/2393, 12.01.2026 duyurusu): alomaliye.com ve erdem-erdem.av.tr (ikincil).
- 6563 m.2 "ticari amaçlarla gönderilen" tanımı ve Yönetmelik RG 15.07.2015/29417: ikincil.
- KVKK m.12/2 "müştereken sorumluluk" ve m.12/5 ilk cümle: ikincil kaynaklar; m.5/2 (c) ikincil.

**Doğrulanamayanlar [AVUKAT DOĞRULASIN]:**
- KVKK m.5/2 (ç) ve (f) bent harfleri ve metni; m.12/3 (denetim) ve m.12/4 (sır saklama) fıkra numaraları; m.14 şikâyet süreleri ve Kurul 2019/9 kararı.
- VERBİS kararlarının RG tarihi/yürürlüğü; site yönetimlerine özgü muafiyet.
- Kat Mülkiyeti Kanunu'nun yönetici görev, defter ve ortak gider maddeleri; VUK m.253, TTK m.82; TBK m.146-147 uygulaması.
- TBK m.20-25 madde numaraları ve içerikleri; TKHK m.73; HMK m.17; TMK erginlik maddesi; 6493 kapsamı; Ticari İletişim Yönetmeliği istisnaları.

---

## Yayın öncesi teknik adımlar

1. `server/legal/*.md` içindeki tüm `[KARAR/BİLGİ GEREKLİ ...]` ve `[AVUKAT DOĞRULASIN ...]` işaretlerini çözüp silin (arama deseni: `\[KARAR` ve `\[AVUKAT`).
2. Her dosyanın front-matter'ındaki `complete: false` satırını silin (sunucu bu satır varken belgeyi eksik sayar, zorunlu onay açılmaz).
3. `PUT /admin/platform-config` ile `legal.*` alanlarını doldurun (bkz. `KULLANICIDAN_GEREKENLER.md`).
4. Sürümü (`version`) ve `effective_date` değerini yayın tarihine göre güncelleyin; metin değiştikçe sürüm yükseltilir ve yeniden onay istenir.
5. En son `legal.enforce_consents` anahtarını açın.
