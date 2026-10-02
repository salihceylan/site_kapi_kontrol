# ÜYELİK YÖNETİM SİSTEMİ AŞAMALARI (UYELIK_SISTEMI_ASAMALAR.MD)

> **KRİTİK KURAL:** Bu iş paketi ana projedeki 4. aşamadan bağımsızdır ve araya alınmış öncelikli bir çalışmadır.
> Her aşama sırayla uygulanacak; kullanıcı sahada/telefonda test edip **"Tamam çalışıyor, sonraki aşamaya geç"** onayı vermeden kesinlikle bir sonraki aşamaya geçilmeyecektir.
> Sahada çalışan eski ESP32-C3 cihazları, mevcut kapı açma, MQTT ve QR altyapısı asla bozulmayacaktır.

---

### [ÜYELİK SİSTEMİ AŞAMA 0] — Mevcut Mimari Analizi ve Entegrasyon Haritası
* **Kapsam:** Sıfır kod değişikliği. Mevcut `users`, `doors`, `devices`, `sites`, `apartments` tabloları, auth ve session mimarisi incelenir; yeni tabloların ve servislerin eskileri bozmadan sisteme nasıl ekleneceği haritalandırılır.
* **Test & Doğrulama:** Ajan tarafından hazırlanan mimari analiz ve entegrasyon raporu incelenir ve kullanıcı onayı alınır.

---

### [ÜYELİK SİSTEMİ AŞAMA 1] — Veritabanı Genişletmesi (Geriye Dönük Uyumlu Migration)
* **Kapsam:** Mevcut tablolar silinmeden/bozulmadan yeni ilişki tabloları VPS PostgreSQL veritabanına eklenir (`site_memberships`, `apartment_memberships`, `site_join_tokens`, `join_requests`, `email_verifications`, `door_access_overrides`).
* **Test & Doğrulama:** Canlı VPS üzerinde tablolar ve kısıtlar doğrulanır; sahadaki mevcut kullanıcıların ve kapıların eskisi gibi çalıştığı teyit edilir.

---

### [ÜYELİK SİSTEMİ AŞAMA 2] — Bireysel Kullanıcı Kaydı & 4 Haneli E-posta Doğrulama
* **Kapsam:** Self-service kayıt ekranı (Ad, Soyad, E-posta, Şifre, Şifre Tekrar). Kayıt sonrası e-postaya 4 haneli sayısal kod (örn: `4837`) gönderimi ve doğrulama arayüzü. E-posta doğrulanmadan siteye katılma veya cihaz sahiplenme engeli.
* **Test & Doğrulama:** Uygulamadan yeni bir hesap açılır; gelen 4 haneli kod girilerek hesap onaylanır.

---

### [ÜYELİK SİSTEMİ AŞAMA 3] — Kutu QR Kodu ile Cihaz Sahiplenme (Device Claiming)
* **Kapsam:** Doğrulanmış kullanıcının ana ekranındaki `Cihaz Ekle` butonu. Cihaz ambalaj kutusundaki `device_id` QR kodunu okutarak cihazı kendi hesabına bağlama akışı.
* **Test & Doğrulama:** ESP32 cihazının kutu QR'ı veya UID'si kamera ile okutularak cihaz kullanıcı hesabıyla başarıyla ilişkilendirilir.

---

### [ÜYELİK SİSTEMİ AŞAMA 4] — Dinamik Site, Blok ve Daire Yönetimi
* **Kapsam:** Cihazı ekleyen kişinin otomatik `Site Sahibi (SITE_OWNER)` olması; site adı belirleme, dinamik blok ekleme (A Blok, B Blok...), blokların altına daireleri oluşturma ve düzenleme arayüzü.
* **Test & Doğrulama:** Uygulama içinden yeni bir site kurulur; bloklar ve daireler arayüzden oluşturulup listelenir.

---

### [ÜYELİK SİSTEMİ AŞAMA 5] — Bağımsız Kapı Yönetimi & Cihaz Atama (Kapı ≠ Cihaz)
* **Kapsam:** Kapı ile cihazın birbirinden ayrılması. Sitede birden fazla kapı tanımlama (Site Ana Giriş 1, Garaj Kapısı, A Blok Giriş), kapı kapsamı belirleme (`SITE_COMMON`, `BLOCK`, `CUSTOM`) ve sahiplenilen cihazı ilgili kapıya bağlama.
* **Test & Doğrulama:** Farklı kapılar oluşturulur ve sahiplenilen cihaz bu kapılardan birine atanır.

---

### [ÜYELİK SİSTEMİ AŞAMA 6] — Arızalı Cihazı Değiştirme (Kapı ve Yetkiler Korunarak)
* **Kapsam:** Kapı yönetim ekranında `Cihazı Değiştir` özelliği. Kapı ID'si, sakinlerin yetkileri ve site yapısı hiç bozulmadan, yeni cihazın kutu QR'ı okutularak eski cihazın yerine geçirilmesi.
* **Test & Doğrulama:** Mevcut bir kapıda "Cihazı Değiştir" seçilerek yeni UID tanımlanır; kapı yetkilerinin ve ayarlarının aynen korunduğu test edilir.

---

### [ÜYELİK SİSTEMİ AŞAMA 7] — Site Katılım QR Kodu Üretimi & Yönetimi
* **Kapsam:** Site kurulduğunda sistemin otomatik `Site Katılım QR Kodu` üretmesi. Yöneticinin bu QR'ı ekranda görebilmesi, paylaşabilmesi ve gerektiğinde iptal edip yenisini üretebilmesi. (Bu QR kapı açmaz, sadece üyelik başvurusu başlatır).
* **Test & Doğrulama:** Yönetici panelinden "Site Katılım QR Kodu" açılıp görüntülenir ve paylaşım fonksiyonu test edilir.

---

### [ÜYELİK SİSTEMİ AŞAMA 8] — Sakin Katılım Talebi & Yönetici Onay/Ret Paneli
* **Kapsam:** Normal kullanıcının `Siteye Katıl` deyip Site Katılım QR'ını okutması; açılan ekranda `[Blok ▼]` ve `[Daire ▼]` seçip katılım talebi göndermesi. Site yöneticisinin paneline düşen talepleri `Onayla` / `Reddet` butonlarıyla yönetmesi.
* **Test & Doğrulama:** İkinci bir kullanıcı hesabıyla QR okutulup daire seçilerek başvurulur; yönetici hesabıyla bildirim görülüp onaylanır.

---

### [ÜYELİK SİSTEMİ AŞAMA 9] — Daire Admini & Aile Üyeleri Hiyerarşisi
* **Kapsam:** Bir daireye onaylanan İLK kullanıcının otomatik `Daire Admini`, sonrakilerin `Aile Üyesi` olması. Daire Admininin kendi dairesindeki aile üyelerini uygulama içinde görebilmesi.
* **Test & Doğrulama:** Aynı daireye 2 farklı kullanıcı onaylanır; birincisinin Daire Admini olduğu, ikincisinin aile üyesi olarak adminin ekranında listelendiği doğrulanır.

---

### [ÜYELİK SİSTEMİ AŞAMA 10] — Otomatik Kapı Yetkilendirmesi
* **Kapsam:** Daireye onaylanan sakine otomatik yetki atanması: Sitenin tüm `SITE_COMMON` (ortak) kapılarına ve yalnızca kendi bloğunun `BLOCK` kapılarına erişim verilmesi (farklı blok kapılarının kapalı kalması).
* **Test & Doğrulama:** A Blok dairesine onaylanan kullanıcının ana giriş ve A Blok kapılarını açabildiği, B Blok kapısını göremediği/açamadığı test edilir.

---

### [ÜYELİK SİSTEMİ AŞAMA 11] — Ek Kapı Yetkileri ve Toplu Yetkilendirme
* **Kapsam:** Yöneticinin belirli dairelere/kullanıcılara veya tüm bloğa ek kapı yetkisi (örneğin Garaj veya B Blok kapısı) verebilmesi; toplu yetki verme/kaldırma paneli.
* **Test & Doğrulama:** A Blok sakinine yönetici panelinden tek tıkla Garaj veya B Blok kapı yetkisi verilip kapının açıldığı test edilir.

---

### [ÜYELİK SİSTEMİ AŞAMA 12] — Akordiyon Sakin Listesi (PDF Bağımlılığının Kalkması)
* **Kapsam:** Yöneticinin sakinleri hiyerarşik akordiyon liste olarak görmesi (`▶ A Blok (48 sakin)` → `▶ Daire 12 (4 kişi)` → `Salih Ceylan (Admin)`, `Ayşe Ceylan (Aile Üyesi)`).
* **Test & Doğrulama:** Yönetici panelinden sakin listesi akordiyon şeklinde açılıp kapatılarak akıcı şekilde incelenir.

---

### [ÜYELİK SİSTEMİ AŞAMA 13] — Çoklu Site & Yönetim Firması Senaryoları
* **Kapsam:** Bir kullanıcının hem bir sitede yönetici, hem başka sitede sakin olabilmesi; bir yönetim firmasının tek hesaptan birden fazla siteyi yönetebilmesi testleri.
* **Test & Doğrulama:** Aynı kullanıcıyla birden fazla site açılıp aralarında tek dokunuşla geçiş yapılarak doğrulanır.

---

### [ÜYELİK SİSTEMİ AŞAMA 14] — Regresyon Testi ve İş Paketinin Tamamlanması
* **Kapsam:** Sahadaki eski ESP32-C3 cihazları, mevcut MQTT/röle altyapısı, Bluetooth kurulumu ve önceki QR çalışmalarının eksiksiz çalıştığının doğrulanması.
* **Test & Doğrulama:** Hem eski butonla hem de QR okuyucuyla tüm kapı açma senaryoları test edilir.
* **Sonuç:** `[ÜYELİK YÖNETİM SİSTEMİ TAMAMLANDI]` raporu sunulur ve ana projedeki **Aşama 4'e** geri dönülür.

---

## 🏁 [ÜYELİK YÖNETİM SİSTEMİ TAMAMLANDI] (Aşama 0 — Aşama 14)
- **Tüm Aşamalar (0-14):** Eksiksiz kodlandı, canlı VPS'e (`178.210.161.55`) dağıtıldı.
- **Testler:** 20 Node.js backend testi ve 34 Flutter testi %100 başarıyla geçti.
- **Saha Test Listesi:** `SAHA_KONTROL_LISTESI.md` (Madde 20 - 29) güncellendi.
- **Durum:** Üyelik Yönetim Sistemi tamamlandı. Ana projedeki Aşama 4 için kullanıcı onayı bekleniyor.


