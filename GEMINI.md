# ÇALIŞMA VE KODLAMA KURALLARI (RULES)

Bu kurallar projede geliştirme yapılırken MUTLAKA ve İSTİSNASIZ olarak uygulanmalıdır:

1. **Modüler Yapıda Çalış:**
   - Kodları monolitik veya devasa tek bir dosya içerisine yazma.
   - Backend tarafında servisler (`services/`), yönlendiriciler (`routes/`), veri erişimi (`db.js`) ve yardımcılar (`utils/helpers.js`) şeklinde katmanlı ve modüler mimariyi koru.
   - Mobil tarafta modeller, servisler, UI sayfaları ve yeniden kullanılabilir widget bileşenleri ayrımına sadık kal.
   - Firmware tarafında başlık (`.h`) ve kaynak (`.cpp`) modüllerini koru.

2. **Geçmiş Özellikleri ve Geriye Dönük Uyumluluğu Asla Bozma:**
   - Kullanıcı tarafından açıkça bir özelliğin geliştirilmesi veya değiştirilmesi talep edilmedikçe, geçmişte yapılmış ve çalışan hiçbir özelliği, API uç noktasını, parametreyi veya iş mantığını bozma, kaldırma ya da değiştirme.
   - Yeni eklenen tüm özellikler geriye dönük uyumlu (backward-compatible) olmalı; mevcut istemciler ve sahadaki cihazlar kesintiye uğramamalıdır.

3. **ESP32-C3 Süper Mini Sahada Aktif - Çalışmasını Asla Bozma:**
   - ESP32-C3 Süper Mini cihazları sahada aktif olarak çalışmaya devam etmektedir.
   - ESP32-C3'ün çalışmasını, pin konfigürasyonunu, BLE/Wi-Fi/MQTT haberleşmesini veya işlevlerini bozacak/aksatacak hiçbir kodlama veya mimari değişiklik yapma.
   - Flash ve RAM kısıtlarını (NimBLE, bellek optimizasyonları) her zaman gözet.

4. **Güncellemeleri Cihaza Göre (İzole Hedefli) Yap:**
   - Yeni donanım (örneğin ESP32-WROOM-32E röle kartı) ve mevcut donanım (ESP32-C3 Süper Mini) birbirinden tamamen bağımsız iki donanım hedefidir.
   - Firmware derlemeleri, OTA manifest dosyaları (`/firmware/esp32-c3/manifest.json` ve `/firmware/esp32-wroom/manifest.json`) ve versiyon kontrolleri cihaz mimarisine (`hardware_target`) göre ayrı ayrı yürütülmeli ve asla birbirine karışmamalıdır.
   - Her cihaz yalnızca kendi mimarisine ait güncellemeleri çekmelidir.

5. **Saha Kontrol Listesini Güncel Tut:**
   - Kullanıcı yeni bir özellik talep ettiğinde ve bu özellik kodlanıp tamamlandığında, `SAHA_KONTROL_LISTESI.md` dosyasına ilgili özelliği test adımı (`- [ ]`) olarak ekle.
   - Test adımında özelliğin nasıl test edileceğini ve beklenen sonucunu net olarak açıkla.

6. **Mobil ve Arayüz Tasarımlarında Taşma (Overflow) Kesinlikle Yasaktır:**
   - Flutter/mobil ve masaüstü arayüz geliştirmelerinde hiçbir ekranda yatay veya dikey taşma ("Right/Bottom overflowed by X pixels") hatası oluşmayacak şekilde tasarım yapılması ZORUNLUDUR.
   - Tüm `Row`, `Column`, `Wrap` ve liste elemanlarında metin ve rozet gibi dinamik içerikler daima esnek/uyarlanabilir olmalıdır (`Flexible`, `Expanded`, `maxLines: 1`, `overflow: TextOverflow.ellipsis` veya `Wrap`).
   - Küçük ekranlar, farklı DPI oranları, uzun metinler (cihaz isimleri, mimari etiketleri, durum rozetleri) hesaba katılmalı; sabit genişlikler yerine esnek ve kırılmayan (responsive) tasarım garantilenecektir.

7. **Uygulamayı Kapatıp Açmayı Gerektirmeyen Canlı ve Otomatik Yenileme Şartı:**
   - Hiçbir sayfada veya işlem sonrasında (cihaz ekleme, kapı atama/çıkarma, düzenleme, silme, yetki verme vb.) kullanıcının güncel verileri ve durumu görmek için uygulamayı kapatıp açması KESİNLİKLE GEREKMEMELİDİR.
   - Yapılan her başarılı işlem/diyalog sonrasında ilgili sayfanın verileri otomatik olarak yeniden çekilmeli (`refresh()`, `loadData()`, `setState`) ve UI anında güncellenmelidir.
   - Sayfalarda ayrıca kullanıcının dilediğinde sayfayı tazeleyebileceği `RefreshIndicator` (aşağı çekip yenileme) ve/veya yenileme butonları mutlaka aktif tutulmalıdır.

8. **Sunucuyu (Backend VPS) Her Zaman Güncelle ve Canlı Doğrula (Zorunlu):**
   - Backend tarafında (servisler, rotalar, veritabanı şeması, migrasyonlar, MQTT köprüsü vb.) yapılan her değişiklik sonrasında sunucu güncellemesi MUTLAKA ve İSTİSNASIZ olarak canlı ortama (VPS `178.210.161.55` / `api.gudeteknoloji.com.tr`) anında dağıtılmalıdır.
   - Değiştirilen dosyalar SCP/SSH ile sunucuya aktarılmalı (`/var/www/site_kapi_kontrol/server/`), varsa migrasyon/şema kontrolleri çalıştırılmalı ve PM2 süreci (`pm2 restart kapi-api --update-env`) yeniden başlatılmalıdır.
   - Güncelleme sonrasında PM2 logları (`pm2 logs kapi-api --lines 20 --nostream`), sağlık kontrolü (`/health`) ve veritabanı/MQTT bağlantı durumu doğrulanmadan iş tamamlandı sayılmaz.
   - Sadece yerelde kod yazıp bırakmak kesinlikle yasaktır; her sunucu geliştirmesi derlenmeli, canlıya yüklenmeli ve çalıştığı uçtan uca teyit edilmelidir.

9. **Tam Yetki ve Doğrudan Uygulama (İzin İsteme Kesinlikle Yasaktır):**
   - Ajan tam yetkilidir (full access / autonomous). Kodlarda, dosyalarda, veritabanında, VPS sunucuda veya komutlarda değişiklik veya operasyon yapılması gerektiğinde kullanıcıdan ASLA "kabul ediyor musun?", "değiştireyim mi?", "onaylıyor musunuz?", "izin veriyor musunuz?" gibi ara onay soruları sorulmayacak, hiçbir şey için izin istenmeyecektir.
   - Gerekli tüm düzeltmeler, dosya yazımları, testler, migrasyonlar ve canlı sunucu dağıtımları doğrudan, tereddütsüz ve eksiksiz olarak icra edilecektir.

10. **Git Yüklemeleri ve `.git/index` Bütünlüğü (Index Temizliği & Hata Engelleme):**
    - Her Git commit / push (GitHub yüklemesi) işleminden önce `.git/index` dosyasının bütünlüğü doğrulanmalı; kilit (`.git/index.lock`) veya bozulma ihtimaline karşı index temizliği yapılmalı (`Remove-Item -Force .git\index; git reset`).
    - `fatal: .git/index: index file smaller than expected` hatasının oluşması kesinlikle engellenmeli; bozuk index tespit edildiğinde otomatik onarım uygulanarak VS Code ve Git işlemleri kesintisiz yürütülmelidir.

11. **Dinamik QR & GM60 Güvenlik Aşamaları (Aşama 4, 5, 6, 7 Tamamlandı):**
    - Aşama 4 (30s süre & supersede token iptali), Aşama 5 (Haversine geofence mesafe hesabı), Aşama 6 (sahte konum / mock location ve bayat konum engeli) ve Aşama 7 (rate limiting & yönetici QR iptali) başarıyla tamamlanmış, tüm birim testleri (34/34 Node, 34/34 Flutter) geçirilmiş ve canlı VPS'e dağıtılmıştır.

12. **Üyelik Yönetim Sistemi Çalışma Kuralları (`uyelik_sistemi_asamalar.md`):**
    - Üyelik Yönetim Sistemi geliştirmesi (Aşama 0'dan Aşama 14'e kadar) %100 tamamlanmıştır.
    - Saha ve uygulama doğrulamaları için `uyelik_adim_adim_test.md` kılavuzu hazırdır.

13. **Toplu Yükleme, Otomatik Kullanıcı Adı (Slug), Başlangıç Şifresi (1234), Zorunlu Şifre Değişimi ve Daire Adminliği (ASLA BOZULMAYACAK):**
    - **Neden Yapıldı:**
      - Yöneticilerin toplu Excel yüklemesiyle sakinleri sisteme aktardıklarında dairelerin boş kalmaması, her daire sakininin oturum açabileceği hazır kullanıcı hesabı (`users`) ve daire yöneticiliği (`APARTMENT_ADMIN`) ile donatılması sağlandı.
      - Şablon Excel/CSV dosyalarında her satırda hazır Başlangıç Şifresi (`1234`) ve Kullanıcı Adı (`kullanici_adi`) sütunu tanımlandı.
      - Excel yüklendiğinde ve tarandığında, `BulkImportController` ve `BulkEditableTable` kişinin ad-soyadından yola çıkarak Türkçe karakterleri arındırıp nokta ayırıcılı ve dosya içinde benzersiz kullanıcı adını (`generateUsernameFromFullName`, örn: `ahmet.yilmaz`, mükerrerlikte `ahmet.yilmaz2`) otomatik üretir ve tabloda gösterir.
      - Yönetici tabloda kullanıcı adını tıklayarak düzenleyebilir; düzenleme ekranında anlık teklik (uniqueness) denetimi vardır, mükerrer kullanıcı adına izin verilmez.
      - Toplu yükleme onaylandığında (`bulk_import_writer.js` -> `provisionImportedResidents`): Daireye atanan kişi için kullanıcı hesabı oluşturulur, `users.login_name` atanır (ve `ensureUniqueLoginName` ile DB tekilliği garanti edilir), rolü `APARTMENT_ADMIN` yapılır, şifresi `1234` (veya tablodaki şifre) olarak bcrypt ile hashlenir ve `must_change_password = TRUE` atanır.
      - Sakin 1234 şifresiyle ilk girişini yaptığında `ForceChangePasswordDialog` modalı ile karşılanır ve kendi yeni şifresini belirler. Profilim ekranında da şifre değiştirme kartı bulunur.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - `kullanici_adi` ve `sifre` sütunlarını `bulk_import_spec.js` ve `bulk_template.dart` içerisinden ASLA kaldırma.
      - `BulkImportController._enrichRowsWithAutoDefaults` ve `generateUsernameFromFullName` fonksiyonlarını ASLA silme; Excel okunduğunda tablodaki kullanıcı adının ve 1234 şifresinin dolu gelmesi şarttır.
      - `BulkEditableTable` içindeki kullanıcı adı hücre düzenleme ve mükerrer engelleme kontrollerini bozma.
      - `provisionImportedResidents` fonksiyonunu veya `bulk_import_service.js` içerisindeki çağrısını ASLA kaldırma; toplu yüklenen her sakinin daire admini hesabı açılmak zorundadır.
      - `ForceChangePasswordDialog` zorunlu şifre değiştirme modalını ve `UserSession.mustChangePassword` bayrağını ASLA iptal etme.

14. **Site Yöneticisi Doğrudan Site Kuramaz - Süper Kullanıcı Onayı Zorunludur (Site Başvuru Mimarisi):**
    - **Neden Yapıldı:**
      - Hiçbir site yöneticisi veya kullanıcı, platform süper kullanıcısının (`SUPER_USER`) onayı olmadan doğrudan yeni bir site (apartman, rezidans, kooperatif, iş merkezi, AVM vb.) oluşturamaz.
      - Tüm yeni site talepleri `POST /api/site-applications` üzerinden başvuru statüsünde (`PENDING`) toplanır; süper kullanıcı onayladığında site kurulur ve yetkiler atanır.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - `POST /api/sites` uç noktasını süper kullanıcı harici rollere ASLA açma. Doğrudan site oluşturma izni yalnızca `SUPER_USER` rolündedir.
      - Rezidans, apartman veya herhangi bir mülk tipi için süper kullanıcı onay mekanizmasını bypass eden hiçbir kod yazma.
      - UI tarafındaki site oluşturma butonlarını süper onayından geçmeyen doğrudan API çağrılarına ASLA bağlama.

15. **Metrekare (m²) Alanları Tüm Sistemden Kaldırılmıştır (ASLA GERİ EKLENMEYECEK):**
    - **Neden Yapıldı:**
      - Kullanıcı kararı doğrultusunda dairelerin metrekaresi sistemden tamamen çıkarılmıştır. Daire metrekaresi sisteme girilmekle uğraşılmayacak, hiçbir ekranda istenmeyecek ve yer kaplamayacaktır.
      - Veritabanında `apartments` tablosundaki `gross_area_m2` ve `net_area_m2` sütunları kalıcı olarak silinmiştir (DROP COLUMN).
      - Mobil/Web arayüzünde (Daire Ekle, Daire Düzenle, Daire Kartı, CRM, sayaç faturalandırma ve toplu içe aktarma şablonlarında) metrekareyle ilgili tüm alanlar kaldırılmıştır.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Veritabanına `gross_area_m2`, `net_area_m2` veya benzeri metrekare sütunlarını ASLA tekrar ekleme.
      - Flutter UI formlarına (kartlar, diyaloglar, detay sayfaları) metrekare giriş veya gösterim alanları ASLA ekleme.
      - Excel toplu içe aktarma şablonuna (`brut_m2`, `net_m2`) sütunlarını ASLA geri koyma.

16. **Panelden "Yeni Site Oluştur - YÖNETİCİ OLUN" Bannerı Kaldırılmıştır:**
    - **Neden Yapıldı:**
      - Daire kullanıcısı veya sakin olarak giriş yapıldığında ana panelde beliren "Yeni Site Oluştur - YÖNETİCİ OLUN / Henüz kayıtlı bir daireniz bulunmuyor..." kartı kullanıcının isteğiyle panelden kaldırılmıştır.
      - `lib/ui/pages/home_page.dart` içerisindeki `_canShowSiteCreationOnPanel` kontrolü `false` yapılarak sakin/daire kullanıcısı paneli sadeleştirilmiştir.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Panel ekranına sakinler veya normal kullanıcılar için izinsiz site oluşturma davet kartlarını ASLA tekrar yerleştirme.

17. **Daire Giriş ve PIN Mimarisi (KVKK m.12 Güvenlik Standardı):**
    - **Neden Yapıldı:**
      - KVKK m.12 veri güvenliği standardı gereği, sakinlerin PIN ve şifreleri veritabanında ASLA düz metin (plain text) olarak saklanmaz; yalnızca tek yönlü bcrypt hash ile tutulur.
      - Bu nedenle yönetici ekranlarında "PIN Göster" butonu bulunmaz ve bulunamaz (düz metin PIN geri okunamaz).
      - Bunun yerine "PIN Sıfırla" özelliği mevcuttur: Yönetici tıkladığında 6 haneli geçici tek seferlik bir PIN üretilir, ekranda o an modalda gösterilir ve hashlenerek DB'ye yazılır. Sakin dilerse ayrıca e-posta davetiyle kendi şifresini belirleyebilir.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Veritabanında PIN'leri veya şifreleri düz metin saklayacak sütunlar ASLA açma.
      - "PIN Göster" adı altında veritabanından şifre/PIN çekmeye çalışan güvensiz mekanizmalar kurma.

18. **Panel Görev / Dikkat Çubuğu (Attention Bar) Kontrast ve Buton Görünürlüğü:**
    - **Neden Yapıldı:**
      - Panelde "Dikkat edilmesi gereken işler" çubuğundaki eylem butonu koyu arka plan üzerinde beyaz kutu içinde beyaz yazı kaldığı için okunaksızdı ("buton boş" hatası).
      - Butonun arka plan rengi, kenarlığı ve yazı rengi net, kontrastlı ve okunabilir olacak şekilde (`attention_action_button`) standartlaştırıldı.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Attention bar butonunun kontrastını bozma, buton içi metnin arka planla aynı renk olmasına yol açacak stil değişiklikleri yapma.

19. **Excel Toplu Sakin ve Daire Yüklemede Akıllı Şablon Doldurma:**
    - **Neden Yapıldı:**
      - Yönetici "Şablonu İndir" butonuna bastığında, sitenin veritabanında zaten kayıtlı olan blokları ve daire numaraları Excel şablonunda hazır dolu olarak gelir.
      - Yönetici blok ve daireleri tek tek elle yazmak zorunda kalmaz; yalnızca ad_soyad, telefon, eposta vb. sakin bilgilerini doldurur.
      - Gereksiz ve kafa karıştırıcı sütunlar (`brut_m2`, `net_m2`, `arsa_payi_pay`, `arsa_payi_payda`, `not`) şablondan çıkarılmıştır.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - `bulk_template.dart` içindeki akıllı blok/daire ön-doldurma mekanizmasını ASLA bozma veya boş şablon indirmeye geri döndürme.

20. **Reddedilen Site Başvurusunun Panelde Sürekli Kalmaması ve "Yeniden Başvur" Düğmesinin Kaldırılması:**
    - **Neden Yapıldı:**
      - Bir kullanıcının site kurulum başvurusu reddedildiğinde, kullanıcının ana panelinde (Dashboard / Vitrin / Bireysel Ekran) kalıcı olarak "Yeniden başvur" butonunun ve kartının asılı kalması kullanıcı deneyimini bozuyordu.
      - Kullanıcı başvurusunun reddedildiğini ve gerekçesini gördükten sonra bunu tek tıkla kapatabilmeli ve ana panelde sürekli aynı bildirimle karşılaşmamalıdır.
      - Paneldeki `SiteApplicationStatusCard` üzerinde `showReapplyOnRejected: false` tanımlanarak "Yeniden başvur" düğmesi kaldırıldı; yerine ret gerekçesini onaylayıp kartı ekrandan silen "Anladım" (`site_application_dismiss_rejected`) butonu getirildi.
      - Kapatılan ret bildirimleri `SiteApplicationTracker.consumeRejected(id)` ile yerel hafızaya (`SharedPreferences`) kaydedilir ve sayfa yenilense veya uygulama kapatılıp açılsa dahi panelde tekrar görünmez.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Panel ve bireysel ana ekranlardaki `SiteApplicationStatusCard` bileşenlerine "Yeniden başvur" butonunu ASLA geri koyma (`showReapplyOnRejected: false` kuralını koru).
      - Ret kartından "Anladım" / kapatma butonunu ve `consumeRejected` mekanizmasını ASLA kaldırma.

21. **Daireye Kullanıcı Adı ve Şifre Verildiğinde Hesapsız Sakinin Bağlanması ve İkinci Kişi Oluşumunun Engellenmesi:**
    - **Neden Yapıldı:**
      - Excel toplu yüklemesi veya sakin ekleme ile daireye hesapsız bir sakin kaydedildikten sonra, yönetici bu daireye kullanıcı adı ve şifre verdiğinde (`PATCH /manager/apartments/:id/resident` ve `/admin/apartments/:id/resident`), backend yeni bir `users` ve `apartments.resident_user_code` açıyordu ancak bu hesabı dairedeki mevcut hesapsız sakinle (`site_people`) doğrudan bağlamıyordu.
      - Sonrasında tetiklenen kişi senkronizasyonu (`syncSitePeople`), bu `resident_user_code` için `site_people`'da eşleşme bulamayıp daireye sıfırdan ikinci bir kişi ve ikinci bir ikamet kaydı açıyor, daire kartında aynı isimde biri "Daire admini (Hesaplı)" diğeri "Aile üyesi (Hesapsız)" olmak üzere "Aktif - 2 kişi" saçmalığına yol açıyordu.
      - Yapılan geliştirmeyle `provisionApartmentResident` sonrasında dairede mevcut hesapsız aktif bir sakin varsa bu yeni hesap doğrudan o sakine bağlanır (`UPDATE site_people SET user_code = ... WHERE ...`) ve `apartment_memberships` kaydı atanır.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - `manager_routes.js` ve `admin_routes.js` içerisindeki sakin bağlama (`UPDATE site_people SET user_code = ... FROM apartment_residencies`) mantığını ASLA kaldırma.
      - Daire hesabı oluşturulduğunda veya güncellendiğinde dairedeki mevcut hesapsız sakini yok sayarak mükerrer kişi türeten kodlar yazma.

22. **Site Adlarının Benzersizliği (Uniqueness) ve Başvuru Aşamasında Mükerrerliğin Engellenmesi:**
    - **Neden Yapıldı:**
      - Türkiye'de hiçbir sitede iki aynı isimde site olamaz; her sitenin adı büyük/küçük harf ve boşluk fark etmeksizin benzersiz olmak zorundadır.
      - Kullanıcıların veya yöneticilerin aynı isimde (örneğin iki tane "Cenk2") site açabilmesi veya başvuru yapabilmesi engellendi.
      - Daha başvuru (`POST /api/site-applications`) aşamasında: Veritabanında mevcut/onaylı aynı isimde bir site varsa veya onay bekleyen (`status = 'pending'`) bir başvuru varsa anında `409 Conflict` (`SITE_NAME_EXISTS` veya `SITE_APPLICATION_NAME_PENDING`) ile talep aşamasında engellenir.
      - Doğrudan kurulum (`createSiteWithStructure`, `setupSiteWithClaimedDevice`, `createSite`) aşamasında da isim tekilliği denetlenir.
      - Veritabanında `sites(LOWER(TRIM(name)))` ve `site_applications(LOWER(TRIM(site_name))) WHERE status = 'pending'` unique indexleri oluşturulmuştur.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - `createSiteApplication`, `createSiteWithStructure` veya `createSite` fonksiyonlarındaki site adı benzersizlik kontrollerini ASLA kaldırma veya bypass etme.
      - `sites` tablosundaki `idx_sites_unique_name` benzersizlik indeksini ASLA silme.

23. **Aidat ve Borç Tanımlarında Metrekare (m²) Dağıtımının Kaldırılması (ASLA GERİ EKLENMEYECEK):**
    - **Neden Yapıldı:**
      - Kullanıcı kararıyla metrekareyle ilgili tüm veriler sistemden temizlendiği için, finans ve aidat tanımlarında "Metrekareye göre" (`FeeDistribution.area`) borç dağıtımı yöntemi ve arayüzdeki "Metrekare türü (Brüt m² / Net m²)" seçim bileşenleri tamamen kaldırılmıştır.
      - Aidat ve borç dağıtımları yalnızca "Sabit tutar" (`fixed`), "Eşit paylaşım" (`equal`), "Kategoriye göre" (`category`) veya "Arsa payına göre" (`landShare`) yöntemleriyle yapılır.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - `FeeDistribution.area` ('Metrekareye göre') seçeneğini `FeeSpecForm.distributions` listesine veya aidat/borçlandırma formlarına ASLA geri ekleme.
      - Aidat ve borçlandırma UI ekranlarına "Brüt m² / Net m²" seçimi veya metrekare giriş kutusu ASLA koyma.
      - `FeeSpecFormState` içine metrekare hesaplama mantığı ekleme.

24. **Sadelik ve Kolay Kullanım İlkesi (Gereksiz Veri Talebi ve Karmaşıklığın Engellenmesi):**
    - **Neden Yapıldı:**
      - Toplu yaşam yönetiminde yöneticinin ve sakinin işini zorlaştıran, gereksiz veri girişi dayatan ve kafa karıştıran form alanları sadeleştirildi.
      - Misafir geçiş linki oluşturmada başlık zorunluluğu kaldırıldı; başlık isteğe bağlı yapıldı (boş bırakıldığında sunucu varsayılan "Misafir" başlığını kullanır) ve altına tek dokunuşla dolan hazır etiketler (`Kurye`, `Misafir`, `Usta / Servis`, `Nakliye`) eklendi.
      - Daire düzenleme penceresinde (`ApartmentEditDialog`) çoğu sitede girilmeyen arsa payı (pay/payda) ve kategori alanları "Gelişmiş bilgiler" akordeonuna katlandı (`apartment_advanced_toggle`). Finans dağıtımında (`finance_distribution.js`) kullanıldığı için arsa payı kesinlikle silinmez, yalnızca ilk bakışta gizlenir; değeri olan dairede açık gelir.
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Sakin ve yönetici formlarına zorunlu olmayan hiçbir alanı "zorunlu (required)" yapma; isteğe bağlı alanları güvenli varsayılanlarla destekle.
      - Misafir linki başlığını yeniden zorunlu hale getirme; hazır hızlı etiketleri (`guest_title_chip_*`) kaldırma.
      - Daire düzenlemedeki `apartment_advanced_toggle` ve katlı arsa payı/kategori yapısını bozma, arsa payını finans motorundan koparma.

25. **Temel Modüller (Talep Gerekmez, Kapatılamaz): Aidat ve Finans (Kart Ödemesi dahil), Anket ve Oylama, Komşu Panosu, Ekipman ve Bakım, Faaliyet Raporu, Dosya Deposu (Belgeler ve Google Drive dahil):**
    - **Neden Yapıldı:**
      - Kullanıcı kararıyla şu modüller temel modül (`core`) yapıldı: `finance` Aidat ve Finans (2026-10-26), `survey` Anket ve Oylama, `neighbor_board` Komşu Panosu, `equipment` Ekipman ve Bakım, `annual_report` Faaliyet Raporu ve `drive_storage` Dosya Deposu (2026-10-28). Kişi ve Daire Kayıtları (`people`) ile Duyuru ve Bildirim (`announcements`) zaten temeldi; katalogdaki 23 modülün 8'i temeldir. Temel modül, her site kurulduğunda açık tanımlanır; yöneticinin talep etmesi veya süper kullanıcının açması gerekmez.
      - Katalogda `core: true, defaultEnabled: true` (`server/src/modules/catalog.js`); `computeModuleEnabled` temel modülde site_modules satırına bakmadan açık döner, `isToggleable` false'tur (açma/kapatma 400 `MODULE_NOT_TOGGLEABLE`, talep 400 "Bu modül her sitede hep açıktır; talep edilemez."). Uygulamada kartlar `core` bayrağından "Her sitede açık" olarak görünür, talep düğmesi ve kapatma anahtarı yoktur.
      - Site_modules satırı katalogdaki `core` bayrağından TÜRETİLİR (modül kodu elle listelenmez): `server/src/modules/core_modules.js`. Site oluşturan her yol (`site_setup_core.js` ve `site_service.js` içindeki `createSiteWithStructure`) aynı transaction'da `enableCoreModulesForSite` ile açık satırları yazar. Mevcut siteler açılışta `ensureDbSchema` (`CORE_MODULES_BACKFILL_SQL`) ve migration'larla doldurulur (`079_finance_core_module.sql` finans, `082_more_core_modules.sql` diğer beş modül); bekleyen modül talepleri "onaylandı" olarak sonuçlanır. Deploy provası `ok079` / `ok082` ile her sitede açık satırı ve bekleyen talep olmadığını denetler.
      - Kart Ödemesi (`card_payments`) ve Belgeler (`documents`) kataloktan kaldırıldı (2026-10-28; 25 modülden 23'e). Kart ödemesi Aidat ve Finans ekranındaki "Kart Ödemesi" düğmesidir (yönetici komisyon notunu düzenler, kurul salt okur; uçlar `/card-payments` ve `payment_provider_settings` tablosu aynı kaldı); eski "Ödeme ve Kamera" ekranı "Kamera ve Plaka" oldu ve yalnız `plate_cameras` kapısındadır. Belgeler tek menü öğesi "Dosya Deposu"dur (belge listesi; yazanlara altında "Google Drive" bölümü; sakin alt çubuğunda "Dosyalar"). `migrations/083` bekleyen `card_payments` taleplerini "onaylandı" yapar ve `card_payments` site_modules satırlarını siler (kart ödemesi ayarları ve geçmiş kayıtlar kalır); `migrations/084` `documents` satırlarını ve taleplerini Dosya Deposu'na katar (belge tabloları ve dosyalar değişmez). İkisi de `ensureDbSchema`'da temel modül doldurmasından SONRA, hata açılışı durdurmayacak biçimde çalışır (sıra: 081 -> temel modül doldurma 079/082 -> 083 -> 084; `card_payments_into_finance.js`, `documents_into_drive.js`); deploy provası `ok083` / `ok084`.
      - Eski uygulama sürümleri `card_payments` ya da `documents` koduyla modül açıp kapatmaya veya talep etmeye çalışırsa 500 / 404 değil, temel modüllerle aynı sözleşmeyle 400 `MODULE_NOT_TOGGLEABLE` ve açıklama alır; ilgili menü eski uygulamada güncelleme gelene kadar görünmeyebilir (kabul edildi).
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Yukarıdaki modüllerden hiçbirini katalogda yeniden `core: false` veya varsayılan kapalı YAPMA; modül talebi / vitrin "talep et" akışına geri koyma.
      - Kart Ödemesi (`card_payments`) ayrı modül değildir; Aidat ve Finans'ın (`finance`, temel modül) parçasıdır (migrations/083): `card_payments` kodunu kataloğa geri koyma, kart ödemesi uçlarının kapısı `finance`'tır, eski kod `retiredModuleNotice` ile 400 `MODULE_NOT_TOGGLEABLE` döner.
      - Belgeler ayrı modül değildir; belge uçları ve ekranları Dosya Deposu (`drive_storage`) modülünün parçasıdır. Modül kapısı olarak `documents` kodu kullanılmaz (`DOCUMENTS_MODULE = 'drive_storage'`); yeni dosya/belge özelliği ayrı modül açmaz, Dosya Deposu'na eklenir. Eski `documents` kodu yalnız `canonicalModuleCode` ile çevrilir.
      - Yeni bir temel modül gerekirse: `catalog.js` içinde `core: true, defaultEnabled: true` yap, yeni numaralı bir migration yaz (`buildCoreModulesBackfillSql([kodlar])` çıktısı) ve provaya `okNNN` ekle. Modül kodlarını site kurulumunda elle yazma; açılıştaki doldurma ve `enableCoreModulesForSite` kataloğu kendisi okur. Mevcut 079 / 082 doldurmalarını ve 083 / 084 birleştirmelerini kaldırma ya da değiştirme.
      - Yeni bir site oluşturma yolu eklenirse `enableCoreModulesForSite(client, siteCode)` çağrısını aynı transaction'a koy.
      - Bu modüllerin durumunu doğrudan SQL ile okuyan yerlerde satır yoksa açık say (`COALESCE(..., TRUE)`); `COALESCE(..., FALSE)` yazma. İstemci temel modülü sunucudan gelen `core` bayrağından tanır (`PlatformModule.defaultEnabled`); istemcide ayrıca modül kodu listesi tutma.
      - Bu kural yalnız modülün açık olmasını sağlar; modüllerin kendi kuralları aynen geçerlidir: finansın rol denetimleri (yönetici, kurul okuma, görevli yasağı), sistem hukuk onayı (`finance.legal_ok`) ve hatırlatma ayarı (`reminders_enabled`, varsayılan kapalı); Dosya Deposu için sitenin kendi Google Drive hesabının ayrıca bağlanması (modül açık olsa da bağlantı kurulmadan Google Drive yüklemesi yapılamaz) ve belgelerin kitle / yetki kuralları; anket, komşu panosu ve faaliyet raporunun yetki ve görünürlük kuralları.

26. **İki Kasa: İşletme Projesi (Aidat) Hesabı ve Yatırım ve Demirbaş (Fon) Hesabı; Kiracı Her Zaman Daire Admini:**
    - **Neden Yapıldı:**
      - Kullanıcı kararıyla (2026-10-26) her sitede iki kasa vardır: **"İşletme Projesi (Aidat) Hesabı"** (`operating`; aidat ve işletme giderleri, borcu dairede oturan öder: kiracı varsa kiracı, yoksa malik) ve **"Yatırım ve Demirbaş (Fon) Hesabı"** (`capital`; yatırım, demirbaş, büyük onarım; borcu her zaman malik öder). Bağlayıcı belge: `docs/PLATFORM_FINANS_KASALAR.md`.
      - Kasalar BAKİYEDİR (nakit / banka hesapları ortaktır). Borcun kasası tanımdan gelir (`charge_party` owner ⇒ Fon, occupant ⇒ Aidat). Tahsilat kasalara OTOMATİK, en eski vade önce dağıtılır (`finance_funds.js` `allocateFunds`, tek saf işlev); yönetici isterse tahsilatı tek kasaya kısıtlar. Gider kategorinin kasasından (değiştirilebilir) düşer. Kasalar arası aktarım eklemelidir (ters aktarımla düzeltilir).
      - Dairede güncel kiracı varsa daire admini kiracıdır; malik ve kiracı birlikte tanımlıdır. "Yönetimi kiracıya devret" seçimi kaldırıldı; mevcut daireler açılışta (081) kurala çekildi. Kiracı ayrılınca admin malike döner (öncelik: kiracı > malik > en eski aktif üye).
    - **Gelecek Ajanlar İçin Kesin Yasaklar ve Koruma İlkeleri:**
      - Kasa adlarını değiştirme; arayüzde, makbuzda ve raporda TAM adları kullan (yer darsa "Aidat Hesabı" / "Fon Hesabı").
      - Fon borcunu kiracıya, Aidat borcunu (kiracılı dairede) maliğe yazma; tanımın kasası ile ödeyeni ayrı ayrı seçtiren bir alan geri getirme.
      - Kasa dağıtımını ikinci bir yerde yeniden hesaplama; her ekran ve rapor `allocateFunds` sonucunu kullanır. Dağıtımı değiştiren her değişiklik `server/test/finance_funds.test.js` değişmez testlerini yeşil tutmalı.
      - Kasa aktarımlarını ve defter satırlarını silme / güncelleme; düzeltme yalnız ters kayıtla.
      - Kiracı varken maliği admin yapan bir yol ekleme (tek istisna: site yöneticisinin "Daire adminini değiştir" acil durum aracı). Toplu yüklemede admin önceliği kiracı > malik > diğerleri.
