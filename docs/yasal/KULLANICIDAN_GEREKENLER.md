# Kullanıcıdan Gerekenler (2026-10-16)

Yasal metinlerin (`server/legal/*.md`) yayına alınabilmesi için sizden (Güde Teknoloji) gereken bilgi ve kararlar. Üç bölüm: (1) şirket bilgileri ve `PUT /admin/platform-config` eşlemesi, (2) metinlerde köşeli işaretle bırakılmış bilgi/kararlar, (3) metne yazdığımız taahhütlerin onayı. Sonda geliştirme gerektiren noktalar ve önerilen sıra vardır.

---

## 1. Şirket bilgileri ve platform ayarları eşlemesi

Bu alanlar süper kullanıcı ayarlarından girilir: `PUT /admin/platform-config` gövdesi `legal` grubu (`docs/PLATFORM_SATISA_HAZIRLIK.md` §1.2). Boş dize "ayarsız" demektir; ayarsız alan belgede `[……]` olarak görünür ve belge eksik sayılır.

```json
{
  "legal": {
    "company_name": "…",
    "company_address": "…",
    "mersis_no": "…",
    "kep_address": "…",
    "contact_email": "…",
    "contact_phone": "…",
    "enforce_consents": false
  }
}
```

Doğrulama kuralları (`server/src/modules/platform_config_service.js:22-25,43-52,160-166`): ad en çok 200, adres en çok 500 karakter; MERSİS numarası 16 haneli (boşluk ve tire kaldırılır); `kep_address` ve `contact_email` geçerli e-posta; telefon `+90 212 000 00 00` biçimi gibi 6-29 karakter; metin alanlarında `[ ] < > \` \\ **` karakterleri ve satır başında `# > * + -` kabul edilmez (Markdown'a sızmasın diye).

- **`legal.company_name`**: Güde Teknoloji'nin ticaret unvanı (tam, anonim/limited ekiyle). Yer tutucu `{{company_name}}`. Geçtiği belgeler: KVKK Aydınlatma (bölüm 1.1), Gizlilik (bölüm 2), Kullanım Koşulları (giriş, bölüm 15), Veri İşleme Sözleşmesi (giriş), Hesap ve Veri Silme (giriş, bölüm 6).
- **`legal.mersis_no`**: 16 haneli MERSİS numarası. Yer tutucu `{{mersis_no}}`. KVKK Aydınlatma (1.1), Gizlilik (2), Kullanım Koşulları (giriş), Veri İşleme Sözleşmesi (giriş).
- **`legal.company_address`**: tebligata elverişli açık adres. Yer tutucu `{{company_address}}`. KVKK Aydınlatma (1.1, bölüm 9 yazılı başvuru), Gizlilik (2, 12), Kullanım Koşulları (giriş, 15), Veri İşleme Sözleşmesi (giriş), Hesap ve Veri Silme (bölüm 4, 6).
- **`legal.kep_address`**: kayıtlı elektronik posta (KEP) adresi. Yer tutucu `{{kep_address}}`. KVKK Aydınlatma (1.1, bölüm 9), Gizlilik (2, 12), Kullanım Koşulları (15), Hesap ve Veri Silme (4, 6). KEP'iniz yoksa edinmeniz gerekir; veri sahipleri başvuruyu KEP ile yapabilir.
- **`legal.contact_email`**: kişisel veri, gizlilik ve silme talepleri için izlenen e-posta (öneri: `kvkk@…` gibi ayrı bir kutu). Yer tutucu `{{contact_email}}`. KVKK Aydınlatma (1.1, 9), Gizlilik (2, 8, 12), Kullanım Koşulları (3, 15), Hesap ve Veri Silme (4, 6). Başvurular 30 gün içinde yanıtlanmak zorundadır; kutuyu izleyen bir kişi atayın.
- **`legal.contact_phone`**: iletişim telefonu. Yer tutucu `{{contact_phone}}`. KVKK Aydınlatma (1.1), Gizlilik (2), Kullanım Koşulları (15), Hesap ve Veri Silme (6).
- **`legal.enforce_consents`**: tüm belgeler kesinleşip `complete: false` satırları kaldırılana kadar **kapalı** kalsın (bölüm 5'e bakın). Açıldığında kayıt (`terms`, `privacy`, `kvkk_notice`) ve site başvurusu (`dpa`) onaysız tamamlanmaz.
- **`support.email / phone / hours / web_url`** (aynı uç, `support` grubu): yasal belgelerde yer tutucu olarak geçmez; uygulamadaki Yardım ve güncelleme ekranlarında gösterilir. Gizlilik/silme talepleri için `contact_email` kullanılır; ikisini aynı yapabilirsiniz.

Bir bilgi eksik kalırsa ilgili belge `complete:false` ve sayfada "[……]" gösterir; `GET /public/legal-documents` listesinde `complete` alanı bunu bildirir.

---

## 2. Metinlerde köşeli işaretle bırakılmış bilgi ve kararlar

Aranacak desen: `[KARAR/BİLGİ GEREKLİ: …]`. Her madde için hangi belgede geçtiği ve önerdiğimiz varsayılan yazılıdır. Karar verdiğinizde ilgili cümleyi düzeltip köşeli işareti silin.

### 2.1 Altyapı ve sağlayıcılar

1. **Sunucu barındırma (VPS) sağlayıcısı: unvan, veri merkezi ülkesi/şehri.** Geçtiği yer: KVKK Aydınlatma bölüm 5; Gizlilik bölüm 6; DPA Ek-3. Repoda sağlayıcı adı yoktur. Yurt dışındaysa Kanun m.9 mekanizması (yeterlilik kararı, standart sözleşme vb.) gerekir; Türkiye'de ise aktarım cümlesi sadeleşir. Öneri: veri merkezi ülkesini netleştirin; mümkünse Türkiye.
2. **E-posta (SMTP) sağlayıcısı: unvan ve sunucu ülkesi.** KVKK bölüm 5; Gizlilik bölüm 6; DPA Ek-3. Repoda yalnız `SMTP_HOST` ortam değişkeni vardır; adı bilinmiyor. Sunucudaki `server/.env` içindeki `SMTP_HOST` değerinden sağlayıcıyı öğrenebilirsiniz (değeri paylaşmanız gerekmez; yalnız sağlayıcı adı ve ülkesi yeterli).
3. **Cloudflare: API trafiği vekil mi, MQTT adresi vekil mi?** KVKK bölüm 5; Gizlilik bölüm 6; DPA Ek-3. Koordinatör bildirimine göre API alan adı Cloudflare kenar ağına çözümleniyor (turuncu bulut), yani Cloudflare API trafiğinde vekil/alt işleyen; metinler böyle yazıldı. Operasyon listesinde kayıtların gri bulutta olması beklenir (`SAHA_KONTROL_LISTESI.md:1303-1305`); bu liste güncellenmeli. **MQTT adresinin durumu belirsiz** (cihazlar turuncu bulutta bağlanamaz): netleşince `[KARAR/BİLGİ GEREKLİ: MQTT ...]` işaretli cümle düzeltilir. Yurt dışına aktarım değerlendirmesi avukatta (kontrol listesi madde 6).
4. **Web sürümü barındırma ve içerik dağıtım ağları.** Gizlilik bölüm 5; DPA Ek-3. Web sürümü sunucuda mı (`server.js` `build/web` sunar) yoksa Apache hosting'de mi (`web/.htaccess`) yayında? Flutter web derlemesi CanvasKit/yazı tiplerini Google'dan mı yüklüyor? Öneri: derlemeyi kendi sunucudan yükleyecek biçimde yapın (geliştirme), sonra cümleyi "üçüncü taraf kullanılmaz" olarak sadeleştirin.
5. **nginx erişim günlüğünün saklama süresi.** Gizlilik bölüm 3.6; Hesap Silme bölüm 3. nginx yapılandırması repoda yok. PM2 uygulama günlükleri için `deploy/ops/logrotate_pm2.sh` haftalık veya 20 MB'ta döndürür, 8 eski dosya tutar (metinde bu yazıldı; üretimde zamanlanıp çalıştığını doğrulayın). Öneri: nginx erişim günlüğü en çok 90 gün (IP içerdiği için kısa tutun).
6. **Yedekleme: üretimde devrede mi, şifreleme, saklama süresi, konum.** Gizlilik bölüm 7 ve 8; DPA Ek-2, 5.2, 5.3 ve Ek-3; Hesap Silme bölüm 3 ve 5. Metinler şu düzeni yazıyor: sunucuda günlük 14, haftalık 8, aylık 6 yedek; dış kopyalar en çok yaklaşık 210 gün; haftalık/aylık ve dış kopyalar şifreli, en son günlük döküm şifresiz ama 600/700 izinli; yönetim bilgisayarı da bir yedek konumu olabilir; silinen verinin yedeklerden yok olması en geç yaklaşık 7 ay. Repodaki betikte (`deploy/ops/backup_db.sh:21-24`) dış kopya adedi 14'tür ve haftalık/aylık kopyalar düz kopyadır; OPS düzeltmesi tamamlanınca metin ve üretim düzeni karşılaştırılmalıdır. Dış kopya hedefini (sağlayıcı, ülke), şifre anahtarının saklandığı yeri ve Windows bilgisayarının yedek konumu olup olmadığını bildirin.
7. **Sunucu diski/veritabanı şifrelemesi var mı?** DPA Ek-2. Yoksa satır silinir; hosting panelinden disk şifreleme durumuna bakın.
8. **Personel gizlilik taahhüdü var mı?** DPA 3.2 ve Ek-2. Çalışanlar/yüklenicilerden yazılı gizlilik taahhüdü alınmasını öneririz.

### 2.2 Site Yönetimi tarafı

9. **Site Yönetimi'nin kimlik/iletişim bilgisi uygulama içinde gösterilecek mi?** KVKK bölüm 1.2. Öneri: evet, sakin için "Site yönetimi" kartında yönetici adı ve iletişim (geliştirme); sonra cümle güncellenir.
10. **Site Yönetimi için varsayılan saklama süreleri** (kişi/daire/araç kayıtları, duyurular, aidat ve borç kayıtları). Gizlilik bölüm 7; DPA 5.2; Hesap Silme bölüm 3 ve 5. Öneri: aidat/borç ve ilişki geçmişi 10 yıl; araç kaydı pasifleştikten 1 yıl sonra silme; duyurular 5 yıl. Avukat onayı gerekir (kontrol listesi madde 3 ve 15).
11. **Diğer kayıtların saklama süresi:** denetim kaydı, yasal belge onay kayıtları, misafir geçiş bağlantıları, katılım başvuruları ve davetler, abonelikten çıkma listesi. Gizlilik bölüm 7; Hesap Silme bölüm 3 (onay ve denetim kayıtları). Öneri: denetim 5 yıl, onay kayıtları 10 yıl, misafir bağlantıları süre bitiminden 30 gün, katılım başvuruları/davetler karardan 1 yıl, abonelikten çıkma özeti süresiz. Kodda bu kayıtlar için temizlik işi yoktur; süreler kesinleşince geliştirme gerekir.
12. **Sistem verisinin iadesi (DPA 5.3):** Site Yönetimine hizmet sonunda veri hangi biçim ve araçlarla verilecek (ör. CSV/PDF dışa aktarma, talep üzerine Güde tarafından)? Bugün kişi listesi dışa aktarma (Faz 2b) ve toplu işlemler tamamlanmadıysa, geçiş kayıtlarının PDF çıktısı vardır (`lib/services/pdf_logs_service.dart`).

### 2.3 Güvenlik ve ürün kararları

13. **Daire hesabı PIN'inin okunabilir saklanması kaldırılacak mı?** Gizlilik bölüm 8; DPA Ek-2. Kaldırılması geliştirme gerektirir (kontrol listesi madde 14); kaldırılana kadar metindeki istisna cümleleri kalır.
13a. **Setup-site ve süper kullanıcı site oluşturma akışlarında DPA onayı.** DPA giriş. Bugün yalnız site başvurusu akışında onay alınır (kontrol listesi madde 28). Geliştirme gerekir.
13b. **Yönetici kimliksizleştirme aracı.** Hesap ve Veri Silme §4. Uygulamaya erişemeyen kullanıcının e-posta talebinde süper kullanıcının kalıcı silme yolu uygulamadaki silmeden farklı sonuç verir (kontrol listesi madde 29). Geliştirme gerekir.
13c. **Site silindiğinde denetim kaydının (`audit_log`) temizlenmesi.** DPA 5.3. Bugün temizlenmez (kontrol listesi madde 32). Geliştirme gerekir.
13d. **Süper kullanıcı görüntüleme erişimlerinin kaydı ve personel gizlilik taahhüdü.** DPA 3.2 (kontrol listesi madde 16).

### 2.4 Sözleşme/ticari kararlar

14. **Hizmetin ücreti/abonelik koşulları.** Kullanım Koşulları bölüm 2. Bugün `standard` plan "Yakında" ve fiyat yoktur (`db.js:1351-1355`); ücretsizse cümleyi kaldırın.
15. **Hizmet seviyesi (SLA) ve planlı bakım bildirimi.** Kullanım Koşulları bölüm 10. Öneri: SLA taahhüdü vermeyin; bakımı uygulama içi duyuru ile bildirin (`maintenance` ayarı mevcuttur).
16. **Güde'nin sorumluluk üst sınırı.** Kullanım Koşulları bölüm 11; DPA bölüm 6 (ayrı üst sınır var mı). Öneri: ücretsiz hizmette sembolik/yok; ücretli hizmette son 12 ayda ödenen bedel; avukat onayıyla.
17. **Koşullarda değişiklik için önceden bildirim süresi.** Kullanım Koşulları bölüm 13. Öneri: esaslı değişikliklerde en az 15 gün.
18. **Yetkili mahkeme ve icra daireleri.** Kullanım Koşulları bölüm 14; DPA bölüm 7. Öneri: Güde'nin ticari merkezinin bulunduğu il mahkemeleri ve icra daireleri (tüketici işlemlerinde tüketici mevzuatı saklıdır). Şirket merkezi ilini bildirin.

### 2.5 P1 modülleri (2026-10-17 eki): telefon bildirimi, belgeler, finans 4b

19. **Telefon bildirimi canlıya ne zaman ve hangi koşulla açılacak?** Gizlilik 3.8; DPA Ek-3. Sunucuda `PUSH_ENABLED` varsayılan 0'dır (`server/.env.example:166`); açmak için Firebase projesi, `google-services.json` / `GoogleService-Info.plist` (Android/iOS), APNs anahtarı ve yalnız FCM gönderim yetkili özel hizmet hesabı gerekir; hizmet hesabı dosyası depo dışında `FCM_SERVICE_ACCOUNT_FILE` ile gösterilir (`docs/PLATFORM_BELGELER.md` Bölüm B, açılış koşulları 1-9). Öneri: yasal metinler (özellikle Gizlilik 3.8 ve Google/Apple'ın rolü, madde 34-35) avukat onayından geçmeden `PUSH_ENABLED=1` yapmayın. Firebase projesinin sahibi (hangi Google hesabı), proje bölgesi ve Analytics'in KAPALI olduğunu bildirin (belge öneriyor, doğrulanamadı).
20. **Mağaza beyanları.** Google Play "Veri güvenliği" ve App Store gizlilik etiketi: telefon bildirimi için "cihaz veya diğer kimlikler" (FCM jetonu) beyanı; Firebase bileşeninin kendiliğinden gönderdiği teknik veri doğrulanana kadar (avukat listesi madde 35) beyan kesinleşmez.
21. **Belge saklama süreleri** (belgeler, gider belgeleri, makbuz ve finans kayıtları, tedarikçi kayıtları, hatırlatma geçmişi). Gizlilik 7; Hesap Silme 3 ve 5. Öneri: avukat listesi madde 36, 37, 39; kodda bu kayıtlar için temizlik işi yoktur (belgeler yalnız yönetim silince 30 gün; gider belgeleri hiç silinmez).
22. **Belge deposu yedeği üretimde devrede mi?** Gizlilik 7; DPA Ek-2. `deploy/ops/backup_db.sh` belge arşivi yedeği (şifreli, son 5, 210 gün) üretimde zamanlanmış ve dış kopya hedefi yapılandırılmış mı; geri yükleme denemesi (`restore_test.sh`) yapıldı mı? Disk üzerindeki belgeler uygulama düzeyinde şifrelenmez (avukat listesi madde 36).
23. **`finance.legal_ok` hukuk kapısı kimde?** Gecikme tazminatı ve borç hatırlatma bu anahtar açılmadan açılamaz; anahtarı yalnız süper kullanıcı `PUT /admin/finance-legal-gate` ile açar (`finance_4b_routes.js:492-503`). Avukat onayını kimin vereceği ve kaydedileceği (madde 37-38) belirlenmeli; anahtar kapatılırsa gönderilmemiş hatırlatmalar iptal edilir.
24. **Makbuz şablonu ve hatırlatma e-posta metni avukat onayı.** Taslak metinler: `finance_receipts.js:43-51`, `finance_reminder_mail.js` (tam metin avukat listesi madde 38'de). Onaydan sonra makbuz `template_version` yükseltilir.
25. **Toplu yükleme onay penceresindeki KVKK metni.** `docs/PLATFORM_TOPLU_ISLEMLER.md` satır 144'te "KVKK onay kutusu" geçer; metni sizin/avukatın görmesi gerekir (madde 40).
26. **Tedarikçi ve gider belgesi için silme/anonimleştirme talebi nasıl karşılanacak?** Kodda silme ucu yok (madde 36); geçici çözüm olarak talebin Güde'ye e-postayla gelmesi ve elle düzeltilmesi mi, yoksa geliştirme mi?

---

## 3. Metne yazdığımız taahhütlerin onayı

Metinler aşağıdaki sayısal ve operasyonel taahhütleri içerir. Güde'nin bunları fiilen karşılayabileceğini onaylayın veya değiştirin:

- Başvuruların (KVKK ve silme) **en geç 30 gün** içinde ücretsiz yanıtlanması (KVKK bölüm 9; Hesap Silme bölüm 4). Yanıtlayacak kişi ve kutu: `contact_email`.
- DPA 3.7: Site verisini etkileyen ihlal öğrenildiğinde **24 saat içinde** Site Yönetimine bildirim. İhlal tespiti ve nöbet süreci var mı?
- DPA 3.6: Doğrudan Güde'ye gelen site verisi başvurusunun **5 iş günü** içinde Site Yönetimine iletilmesi.
- DPA 3.4: Yeni alt işleyen eklemeden **15 gün** önce bildirim ve itiraz hakkı.
- DPA 3.8: Yılda bir kez, 30 gün önceden bildirimle denetim bilgisi/belgesi sağlama.
- DPA 5.3: Hizmet sonunda **30 gün** içinde silme/anonimleştirme.
- Gizlilik/KVKK: "verileriniz satılmaz, pazarlama için paylaşılmaz", "arka planda konum izlenmez", "kamera görüntüsü kaydedilmez, ses kaydı Güde'ye gönderilmez" ifadeleri koddan doğrulanmıştır; ürünü bu yönde değiştirecek bir plan varsa söyleyin.
- Kullanım Koşulları bölüm 10: kullanıcıları ağır etkileyen değişikliklerde makul süre önceden duyuru.

---

## 4. Yayın öncesi geliştirme/doğrulama gerektiren noktalar

(Ayrıntı `AVUKAT_KONTROL_LISTESI.md` ve `VERI_ENVANTERI.md` içinde.)

0. Misafir geçişlerinin IP adresinin oluşturan sakinin veri dışa aktarımına girmemesi (kod düzeltmesi sürüyor; gizlilik metni bu davranışı yazıyor).
1. Daire PIN'inin düz saklanmasının kaldırılması (veya istisnanın açıkça kabulü).
2. Google bağlantı denetimi (`lib/services/network_service.dart:57-60`) ve web derlemesi CDN'i: kaldırma/kendi sunucuya alma.
3. Saklama süreleri kesinleşince otomatik temizlik işleri (denetim kaydı, misafir bağlantısı, pasif araç, katılım başvuruları/davetler, eski site başvuruları).
4. Hesapsız kişiler için aydınlatma (şablon veya otomatik e-posta) ve misafir sayfasına kısa bilgilendirme.
5. İstemci `device_token` saklamaya başlarsa Gizlilik Politikası bölüm 3.7 güncellemesi.
6. Sunucu `complete` hesabı: `server/src/modules/legal_documents.js` yalnız `{{…}}` ve `[……]` boşluklarını eksik sayar; `[KARAR/BİLGİ GEREKLİ …]` ve `[AVUKAT DOĞRULASIN …]` işaretlerini saymaz. Bu yüzden her dosyada `complete: false` satırı bırakıldı. İsterseniz sunucu tarafında bu iki işareti de "eksik" sayacak küçük bir değişiklik yapılabilir (bu görev kapsamında kod değiştirilmedi).
7. (2026-10-17) Hesap silme önizlemesi (`account_deletion_service.js` `will_keep`/`will_remove`) ile `server/legal/account_deletion.md` birebir uyumlu tutulmalı; önizlemede olmayan ama yasal metinde yazan iki madde: gönderilmiş aidat hatırlatma geçmişinin (kişi, daire, durum, zaman) kalması ve gecikme tazminatı/gider/tedarikçi kayıtlarının hesap silmeden etkilenmemesi. Önizleme makbuz satırı KMK/VUK saklama yükümlülüğünü kesin ifadeyle yazıyor; dayanak avukat onayına kadar doğrulanmadı.
8. (2026-10-17) Hatırlatma e-postası altbilgisi hesaplı kullanıcıya "uygulamadaki Bildirim Tercihleri'ni kullanabilir" diyor; `lib/` altında `email_finance_reminders` için ekran anahtarı bulunamadı (sunucu API'si var). Anahtar eklenmeli ya da altbilgi değişmeli.
9. (2026-10-17) `finance_reminder_items` temizleme/saklama işi; tedarikçi, kategori ve kasa/banka hesabı için silme veya anonimleştirme ucu; gider belgeleri için süre sonu silme işi; telefon bildirimi soft istemine Google/Apple aktarım cümlesi; "acil bildirimi de kapat" seçeneği (madde 34).
10. (2026-10-17) Firebase bileşeninin açılışta Google'a gönderdiği teknik verinin ağ trafiğiyle doğrulanması (madde 35).

## 5. Önerilen sıra

1. Şirket bilgilerini girin (bölüm 1), sağlayıcı adlarını ve ülkelerini toplayın (2.1 madde 1-4).
2. Avukatla kontrol listesinin en kritik 10 maddesini görüşün; saklama sürelerini (2.2) kesinleştirin.
3. Teknik düzeltmeleri yapın (bölüm 4).
4. Köşeli işaretleri ve `complete: false` satırlarını silin, `version` ve `effective_date` değerlerini güncelleyin.
5. `legal.enforce_consents` anahtarını açın.
