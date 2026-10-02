# 📋 AHBU Kapı Kontrol Sistemi — Üyelik Yönetim Sistemi Adım Adım Doğrulama ve Test Kılavuzu

Bu belge, **Üyelik Yönetim Sistemi (Aşama 0'dan Aşama 14'e kadar)** kapsamında geliştirilen tüm özelliklerin sahada, mobil uygulamada ve sunucu tarafında adım adım nasıl test edileceğini, beklenen sonuçlarını ve doğrulama kriterlerini içerir.

---

## 📑 İÇİNDEKİLER

1. [Aşama 0 — Veritabanı Şeması ve Rol Altyapısı](#aşama-0--veritabanı-şeması-ve-rol-altyapısı)
2. [Aşama 1 — Bireysel Kullanıcı Kaydı ve E-posta Doğrulama](#aşama-1--bireysel-kullanıcı-kaydı-ve-e-posta-doğrulama)
3. [Aşama 2 — Bireysel Giriş ve Akıllı Rol Yönlendirmesi](#aşama-2--bireysel-giriş-ve-akıllı-rol-yönlendirmesi)
4. [Aşama 3 — Cihaz Sahiplenme (Device Claiming) & Güvenlik](#aşama-3--cihaz-sahiplenme-device-claiming--güvenlik)
5. [Aşama 4 — Müstakil / Standalone Kapı Kurulumu](#aşama-4--müstakil--standalone-kapı-kurulumu)
6. [Aşama 5 — Bireysel Ana Ekran ve Temel Sakin Deneyimi](#aşama-5--bireysel-ana-ekran-ve-temel-sakin-deneyimi)
7. [Aşama 6 — Dinamik Site Kurulumu (Site Kur Wizard)](#aşama-6--dinamik-site-kurulumu-site-kur-wizard)
8. [Aşama 7 — Site Katılım QR Kodu Üretimi ve Yönetimi](#aşama-7--site-katılım-qr-kodu-üretimi-ve-yönetimi)
9. [Aşama 8 — Sakin Katılım Talebi ve Yönetici Onay/Ret Paneli](#aşama-8--sakin-katılım-talebi-ve-yönetici-onayret-paneli)
10. [Aşama 9 — Daire Admini ve Aile Üyeleri Hiyerarşisi](#aşama-9--daire-admini-ve-aile-üyeleri-hiyerarşisi)
11. [Aşama 10 — Otomatik Kapı Yetkilendirmesi (Ortak ve Blok İzolasyonu)](#aşama-10--otomatik-kapı-yetkilendirmesi-ortak-ve-blok-izolasyonu)
12. [Aşama 11 — Ek Kapı Yetkileri ve Toplu Blok Yetkilendirme](#aşama-11--ek-kapı-yetkileri-ve-toplu-blok-yetkilendirme)
13. [Aşama 12 — Akordiyon Sakin Listesi (PDF Bağımlılığının Bitişi)](#aşama-12--akordiyon-sakin-listesi-pdf-bağımlılığının-bitişi)
14. [Aşama 13 — Çoklu Site Switcher ve Çift Rol (Dual Mode)](#aşama-13--çoklu-site-switcher-ve-çift-rol-dual-mode)
15. [Aşama 14 — Regresyon, Donanım (ESP32-C3 / WROOM / GM60) ve Uçtan Uca Bütünlük](#aşama-14--regresyon-donanım-esp32-c3--wroom--gm60-ve-uçtan-uca-bütünlük)

---

## Aşama 0 — Veritabanı Şeması ve Rol Altyapısı

- [ ] **0.1. Veritabanı Tablolarının Varlığı:**
  - **Nasıl Test Edilir:** PostgreSQL sunucusunda `\dt` komutu çalıştırılarak tablolar kontrol edilir.
  - **Beklenen Sonuç:** `site_memberships`, `user_apartment_memberships`, `site_join_tokens`, `site_join_requests`, `door_access_overrides`, `device_claims` tabloları eksiksiz bulunmalıdır.
- [ ] **0.2. Kullanıcı Rol Kısıtı (ENUM/Check):**
  - **Nasıl Test Edilir:** `users` tablosundaki `role` sütunu kontrol edilir.
  - **Beklenen Sonuç:** `individual` rolü kabul edilmeli, mevcut `super_user`, `site_manager`, `apartment_owner` rolleri bozulmamış olmalıdır.
- [ ] **0.3. Şema Bütünlüğü ve İndeksler:**
  - **Nasıl Test Edilir:** `site_code`, `user_code`, `apartment_id`, `door_id` indeksleri incelenir.
  - **Beklenen Sonuç:** Tüm yabancı anahtar (FK) ve tekillik (UNIQUE) kısıtları aktif olmalıdır.

---

## Aşama 1 — Bireysel Kullanıcı Kaydı ve E-posta Doğrulama

- [ ] **1.1. Bireysel Kayıt Formu Arayüzü:**
  - **Nasıl Test Edilir:** Giriş ekranında "Hesabınız yok mu? Yeni Hesap Oluştur" linkine dokunun.
  - **Beklenen Sonuç:** Ad Soyad, E-posta, Telefon ve Şifre alanlarını içeren modern kayıt ekranı açılmalı; küçük ekranlarda taşma (overflow) olmamalıdır.
- [ ] **1.2. 6 Haneli Doğrulama Kodu Gönderimi:**
  - **Nasıl Test Edilir:** Formu doldurup "Kayıt Ol" butonuna basın.
  - **Beklenen Sonuç:** E-posta adresine 6 haneli güvenlik kodu iletilmeli ve kullanıcı otomatik olarak "E-posta Doğrulama" ekranına yönlendirilmelidir.
- [ ] **1.3. Doğrulama Kodunun Girilmesi ve Hesap Aktivasyonu:**
  - **Nasıl Test Edilir:** Gelen 6 haneli kodu kutucuklara girip "Doğrula" butonuna basın.
  - **Beklenen Sonuç:** Kod kabul edilmeli, hesabın `email_verified` durumu `true` yapılmalı ve "Giriş ekranına yönlendiriliyorsunuz" yeşil bildirimi çıkmalıdır.
- [ ] **1.4. Hatalı Kod veya Süre Aşımı Koruması:**
  - **Nasıl Test Edilir:** Kasıtlı olarak yanlış kod girin veya "Yeni Kod Gönder" butonuna basın.
  - **Beklenen Sonuç:** Hatalı kodda "Geçersiz veya süresi dolmuş kod" uyarısı verilmeli, yeni kod istendiğinde sayaç sıfırlanıp yeni e-posta gönderilmelidir.

---

## Aşama 2 — Bireysel Giriş ve Akıllı Rol Yönlendirmesi

- [ ] **2.1. Bireysel Sakin Girişi:**
  - **Nasıl Test Edilir:** `individual` rolüne sahip kullanıcının e-posta ve şifresiyle giriş yapın.
  - **Beklenen Sonuç:** Kullanıcı doğrudan ve takılmasız olarak **Bireysel Ana Ekranına (`IndividualHomeView`)** yönlendirilmelidir.
- [ ] **2.2. Yönetici / Süper Kullanıcı Girişi Ayrımı:**
  - **Nasıl Test Edilir:** `site_manager` veya `super_user` rolündeki bir hesapla giriş yapın.
  - **Beklenen Sonuç:** Yönetici klasik yönetim paneline (`DashboardView`) yönlendirilmeli; roller birbirine kesinlikle karışmamalıdır.
- [ ] **2.3. Doğrulanmamış E-posta ile Giriş Engeli:**
  - **Nasıl Test Edilir:** E-postasını henüz doğrulamamış bir hesapla giriş yapmayı deneyin.
  - **Beklenen Sonuç:** "E-posta adresiniz doğrulanmadı" uyarısı çıkmalı ve sistem doğrulama ekranına yönlendirmelidir.

---

## Aşama 3 — Cihaz Sahiplenme (Device Claiming) & Güvenlik

- [ ] **3.1. Cihaz Üzerindeki Karekodun Okutulması:**
  - **Nasıl Test Edilir:** Bireysel ekrandan "Cihaz Ekle" butonuna basıp yeni bir ESP32 kartının QR etiketini kameraya okutun (veya UID manuel yazın).
  - **Beklenen Sonuç:** Cihaz UID (`00861A0D5020`) tanınmalı ve cihaz başarıyla kullanıcının hesabına zimmetlenmelidir (`is_claimed = true`).
- [ ] **3.2. Çift Sahiplenme (Double-Claim) Engeli:**
  - **Nasıl Test Edilir:** Sahiplenilmiş aynı cihazı ikinci bir farklı hesapla okutmayı deneyin.
  - **Beklenen Sonuç:** Sunucu `409 Conflict` hatası vermeli ve "Bu cihaz zaten başka bir hesaba kayıtlı" uyarısı gösterilmelidir.
- [ ] **3.3. Sahiplenilen Cihazın Listelenmesi:**
  - **Nasıl Test Edilir:** Bireysel ana ekrandaki cihazlar listesini inceleyin.
  - **Beklenen Sonuç:** Sahiplenilen cihaz çevrimiçi/çevrimdışı durumu ve IP bilgisiyle anında ekranda görünmelidir.

---

## Aşama 4 — Müstakil / Standalone Kapı Kurulumu

- [ ] **4.1. Müstakil Kapı Oluşturma:**
  - **Nasıl Test Edilir:** Sahiplenilen cihaza bağlı olarak "Kapı Olarak Ayarla" seçeneğiyle "Ev Garajı" adında bağımsız bir kapı oluşturun.
  - **Beklenen Sonuç:** Herhangi bir site veya blok ihtiyacı olmadan müstakil kapı kaydı oluşmalı ve cihaza bağlanmalıdır.
- [ ] **4.2. Müstakil Kapıyı Uzaktan Açma:**
  - **Nasıl Test Edilir:** Bireysel ekrandan oluşturulan müstakil kapının "Kapıyı Aç" butonuna dokunun.
  - **Beklenen Sonuç:** Cihazın rölesi çekmeli, ekranda yeşil "Kapı açılıyor..." bildirimi gösterilmelidir.

---

## Aşama 5 — Bireysel Ana Ekran ve Temel Sakin Deneyimi

- [ ] **5.1. Bireysel Panel Kartlarının Düzeni:**
  - **Nasıl Test Edilir:** Bireysel kullanıcı hesabıyla ana sayfayı inceleyin.
  - **Beklenen Sonuç:** En üstte "Yetkili Kapılarım", altında "Kayıtlı Dairelerim" ve "Siteye Katıl" butonu düzenli ve responsive yerleşmelidir.
- [ ] **5.2. Geçici Misafir Şifresi (Guest Pass) Üretimi:**
  - **Nasıl Test Edilir:** Kapı kartındaki "Misafir Kodu" butonuna dokunun; geçerlilik süresi (örn. 2 saat) seçip kod üretin.
  - **Beklenen Sonuç:** Geçici bağlantı/kod üretilmeli, paylaş butonuyla WhatsApp/SMS üzerinden gönderilebilmelidir.
- [ ] **5.3. Canlı Yenileme (Kural 7):**
  - **Nasıl Test Edilir:** Ekranı aşağı çekip bırakın (`RefreshIndicator`).
  - **Beklenen Sonuç:** Uygulamayı kapatıp açmaya gerek kalmadan tüm kapı durumları canlı güncellenmelidir.

---

## Aşama 6 — Dinamik Site Kurulumu (Site Kur Wizard)

- [ ] **6.1. Site Kur Sihirbazının Açılması:**
  - **Nasıl Test Edilir:** Bireysel ekrandaki "Site Kur" butonuna dokunun.
  - **Beklenen Sonuç:** Site Adı, İl, İlçe, Blok Sayısı ve Daire Sayısı giriş alanlarını içeren modal diyalog açılmalıdır.
- [ ] **6.2. Otomatik Blok ve Daire Üretimi:**
  - **Nasıl Test Edilir:** Site Adı: "Çiçek Sitesi", Blok Sayısı: 2, Daire Sayısı: 10 girip "Siteyi Kur" butonuna basın.
  - **Beklenen Sonuç:** 
    - Veritabanında "A Blok" (5 daire) ve "B Blok" (5 daire) otomatik oluşturulmalı.
    - Siteyi kuran kullanıcı otomatik olarak `SITE_OWNER` ve `site_manager` yapılmalıdır.
    - Ekranda "Site ve bloklar başarıyla kuruldu!" yeşil bildirimi çıkmalıdır.

---

## Aşama 7 — Site Katılım QR Kodu Üretimi ve Yönetimi

- [ ] **7.1. Site Katılım QR Kodunun Görüntülenmesi:**
  - **Nasıl Test Edilir:** Site Yöneticisi panelinde "Siteler" sayfasına gidin, site kartındaki **"Site Katılım QR"** butonuna dokunun.
  - **Beklenen Sonuç:** Sitenin katılım token'ını içeren büyük QR kod, site adı ve son geçerlilik tarihi ekranda görüntülenmelidir.
- [ ] **7.2. QR Kodun Paylaşılması ve İndirilmesi:**
  - **Nasıl Test Edilir:** QR ekranındaki "Paylaş" butonuna dokunun.
  - **Beklenen Sonuç:** QR kod görseli sistem paylaşım menüsü aracılığıyla diğer uygulamalara aktarılabilmelidir.
- [ ] **7.3. QR Kodun Döndürülmesi (Yenilenmesi):**
  - **Nasıl Test Edilir:** "Kodu Yenile / Döndür" butonuna dokunun ve onaylayın.
  - **Beklenen Sonuç:** Eski katılım token'ı geçersiz kalmalı, ekranda anında yeni bir QR kod üretilmelidir.

---

## Aşama 8 — Sakin Katılım Talebi ve Yönetici Onay/Ret Paneli

- [ ] **8.1. Sakin Tarafından Katılım QR'ının Okutulması:**
  - **Nasıl Test Edilir:** İkinci bir bireysel hesapla "Siteye Katıl (QR Okut)" butonuna dokunup yöneticinin Site Katılım QR'ını okutun.
  - **Beklenen Sonuç:** Site adı doğrulanmalı; ekranda `[Blok Seçin ▼]` ve `[Daire Seçin ▼]` açılır menüleri listelenmelidir.
- [ ] **8.2. Daire Seçimi ve Başvuru Gönderimi:**
  - **Nasıl Test Edilir:** "A Blok" ve "Daire 4" seçip not yazarak "Başvuru Gönder" butonuna basın.
  - **Beklenen Sonuç:** "Katılım talebiniz yöneticiye iletildi" mesajı çıkmalı ve "Katılım Başvurularım" altında "Onay Bekliyor" rozetiyle görünmelidir.
- [ ] **8.3. Yöneticinin Katılım Talebini Onaylaması:**
  - **Nasıl Test Edilir:** Yönetici hesabıyla "Katılım Talepleri" diyalogunu açın; gelen başvuruyu inceleyip **"Onayla"** butonuna basın.
  - **Beklenen Sonuç:** Başvuru onaylanmalı, sakin ilgili daireye kaydedilmeli ve bildirim gönderilmelidir.
- [ ] **8.4. Yöneticinin Katılım Talebini Reddetmesi:**
  - **Nasıl Test Edilir:** Bir başvuruyu seçip "Reddet" butonuna basın.
  - **Beklenen Sonuç:** Başvuru reddedilmeli, sakinin ekranında "Reddedildi" durumu görünmelidir.

---

## Aşama 9 — Daire Admini ve Aile Üyeleri Hiyerarşisi

- [ ] **9.1. İlk Sakinin Otomatik "Daire Admini" Olması:**
  - **Nasıl Test Edilir:** Boş bir daireye (örn. Daire 1) ilk sakini onaylayın. Sakinin panelindeki daire kartını inceleyin.
  - **Beklenen Sonuç:** Sakinin rolü altın sarısı rozetle **"👑 Daire Yöneticisi"** (`APARTMENT_ADMIN`) olarak görünmelidir.
- [ ] **9.2. İkinci Sakinin Otomatik "Aile Üyesi" Olması:**
  - **Nasıl Test Edilir:** Aynı daireye ikinci bir sakini onaylayın.
  - **Beklenen Sonuç:** İkinci sakinin rolü mavi rozetle **"👨‍👩‍👧 Aile Üyesi"** (`FAMILY_MEMBER`) olarak atanmalıdır.
- [ ] **9.3. Daire Admininin Aile Üyelerini Görebilmesi:**
  - **Nasıl Test Edilir:** Daire Admini hesabıyla daire kartındaki "Daire Sakinleri" listesini açın.
  - **Beklenen Sonuç:** Dairedeki tüm aile üyeleri ad, soyad ve e-posta bilgileriyle listelenmelidir.
- [ ] **9.4. Daire Admininin Aile Üyesini Çıkarabilmesi:**
  - **Nasıl Test Edilir:** Daire Admini ekranında aile üyesinin yanındaki kırmızı "Üyeyi Çıkar" butonuna dokunup onaylayın.
  - **Beklenen Sonuç:** Aile üyesi daireden çıkarılmalı, kapı erişimleri iptal edilmeli ve liste canlı güncellenmelidir.

---

## Aşama 10 — Otomatik Kapı Yetkilendirmesi (Ortak ve Blok İzolasyonu)

- [ ] **10.1. Ortak Kapılara Otomatik Yetki (SITE_COMMON):**
  - **Nasıl Test Edilir:** Dairesi onaylanan sakinin "Yetkili Kapılarım" listesini açın.
  - **Beklenen Sonuç:** Sitenin ana giriş, otopark bariyeri vb. tüm ortak kapıları yeşil rozetli `Site Ortak Kapısı` olarak görünmeli ve açılabilmelidir.
- [ ] **10.2. Kendi Bloğunun Kapısına Otomatik Yetki (BLOCK):**
  - **Nasıl Test Edilir:** A Blok'ta oturan sakinin kapı listesini inceleyin.
  - **Beklenen Sonuç:** Mavi rozetli `A Blok Kapısı` listede görünmeli ve kapıyı açabilmelidir.
- [ ] **10.3. Farklı Blok Kapısının Gizlenmesi ve İzolasyonu:**
  - **Nasıl Test Edilir:** A Blok sakininin listesinde B Blok kapısının olup olmadığını kontrol edin.
  - **Beklenen Sonuç:** B Blok kapısı listede KESİNLİKLE görünmemelidir. API üzerinden doğrudan açma isteği gönderilse dahi `403/404 Yetkisiz Erişim` dönmelidir.

---

## Aşama 11 — Ek Kapı Yetkileri ve Toplu Blok Yetkilendirme

- [ ] **11.1. Kapı Yetkileri Diyalogunun Açılması:**
  - **Nasıl Test Edilir:** Yöneticide Siteler -> Kapılar -> Kapının `⋮` menüsünden **"Kapı Yetkileri"** seçeneğine dokunun.
  - **Beklenen Sonuç:** Sitedeki tüm blokların, dairelerin ve sakinlerin hiyerarşik yetki listesi açılmalıdır.
- [ ] **11.2. Bireysel Sakine Ek Kapı Yetkisi Verme:**
  - **Nasıl Test Edilir:** B Blok kapısı için A Blok'ta oturan bir sakinin yanındaki switch'i açın.
  - **Beklenen Sonuç:** Sakinin durumu mavi `Ek İzinli` olmalı; sakin kendi ekranını yenilediğinde B Blok kapısını görüp açabilmelidir.
- [ ] **11.3. Bloğa Toplu Yetki Verme:**
  - **Nasıl Test Edilir:** Kapı Yetkileri ekranında A Blok başlığındaki `⋮` menüsünden **"Tüm Bloğa Yetki Ver"** seçin.
  - **Beklenen Sonuç:** A Blok'taki tüm sakinler tek tıkla yetkilendirilmeli, sayaç tam sayıya güncellenmelidir.
- [ ] **11.4. Bloğun Ek Yetkilerini Sıfırlama:**
  - **Nasıl Test Edilir:** Blok başlığındaki `⋮` menüsünden **"Bloğun Yetkilerini Sıfırla"** seçin.
  - **Beklenen Sonuç:** Ek yetkiler tek tıkla temizlenmeli ve varsayılan yetki durumuna dönülmelidir.

---

## Aşama 12 — Akordiyon Sakin Listesi (PDF Bağımlılığının Bitişi)

- [ ] **12.1. Akordiyon Sakin Listesinin Açılması:**
  - **Nasıl Test Edilir:** Site kartındaki yeşil renkli **"Sakin Listesi (Akordiyon)"** butonuna dokunun.
  - **Beklenen Sonuç:** Blok, daire ve sakin sayılarını gösteren özet sayaçlar ve akordiyon ağacı açılmalıdır.
- [ ] **12.2. Ağaç Gezinimi (Blok ▶ Daire ▶ Sakinler):**
  - **Nasıl Test Edilir:** Blok ve daire başlıklarına dokunarak genişletin / daraltın. "Tümünü Genişlet" butonuna basın.
  - **Beklenen Sonuç:** Ağaç akıcı şekilde açılıp kapanmalı; dairedeki sakinler admin/üye rozetleriyle listelenmelidir.
- [ ] **12.3. Dinamik Arama ve Filtreleme:**
  - **Nasıl Test Edilir:** Arama çubuğuna sakin adı veya daire no yazın; "Dolu Daireler" filtresine basın.
  - **Beklenen Sonuç:** Eşleşmeyen blok ve daireler anında gizlenmeli, aranan sakin doğrudan ekranda kalmalıdır.
- [ ] **12.4. Tek Dokunuşla Telefon / E-posta Kopyalama:**
  - **Nasıl Test Edilir:** Sakinin telefon numarasına dokunun.
  - **Beklenen Sonuç:** Bilgi anında panoya kopyalanmalı ve mavi "Panoya kopyalandı" bildirimi çıkmalıdır.
- [ ] **12.5. Yöneticinin Daireden Sakin Çıkarabilmesi:**
  - **Nasıl Test Edilir:** Sakinin yanındaki `⋮` menüsünden "Daireden Çıkar" seçin ve onaylayın.
  - **Beklenen Sonuç:** Sakin daireden çıkarılmalı, sayaçlar canlı güncellenmeli ve uygulama kapatma gerektirmemelidir.

---

## Aşama 13 — Çoklu Site Switcher ve Çift Rol (Dual Mode)

- [ ] **13.1. Yönetim Firması / Çoklu Site Yönetimi:**
  - **Nasıl Test Edilir:** Tek hesapla birden fazla site kurun veya yetki alın. Yönetici paneline girin.
  - **Beklenen Sonuç:** "Siteler" sayfasında tüm siteler listelenmeli; "Dashboard" ekranındaki "Site Seçin" menüsünden siteler arasında geçiş yapılabilmelidir.
- [ ] **13.2. Çift Rol Geçiş Butonu (AppBar ve Yan Menü):**
  - **Nasıl Test Edilir:** Hem yönetici hem sakin olan bir hesapla AppBar'daki **"Sakin Modu"** veya **"Yönetici Paneli"** butonuna dokunun.
  - **Beklenen Sonuç:** Tek tıkla panel türü değişmeli; Sakin Modunda kendi dairesi/kapıları, Yönetici Modunda yönetim araçları ekrana gelmelidir.
- [ ] **13.3. Sakin Ekranında Çoklu Site Switcher (Site Filtre Çipleri):**
  - **Nasıl Test Edilir:** 2 veya daha fazla sitede dairesi olan bir hesapla Sakin Moduna girin; üstteki site çiplerine dokunun (`[ Tüm Siteler ]`, `[ Gül Sitesi ]`, `[ Lale Sitesi ]`).
  - **Beklenen Sonuç:** Seçilen siteye göre hem daireler hem de kapılar anında süzülmelidir.
- [ ] **13.4. Kapı Kartlarında Belirgin Site Adı Rozeti:**
  - **Nasıl Test Edilir:** Bireysel kapı kartlarındaki başlığı inceleyin.
  - **Beklenen Sonuç:** Kapı adının altında bina ikonuyla birlikte `🏢 Site Adı` belirgin şekilde görünmeli, taşma (overflow) olmamalıdır.

---

## Aşama 14 — Regresyon, Donanım (ESP32-C3 / WROOM / GM60) ve Uçtan Uca Bütünlük

- [ ] **14.1. ESP32-C3 Süper Mini Sahadaki Cihaz Güvencesi (Kural 3):**
  - **Nasıl Test Edilir:** Sahada aktif çalışan ESP32-C3 cihazını açın; mobil uygulamadan kapıyı açın.
  - **Beklenen Sonuç:** GPIO 10 üzerinden 1.5s röle pulse üretilmeli, GPIO 2 durum LED'i çalışmalı, cihaz kesintisiz çalışmalıdır.
- [ ] **14.2. ESP32-WROOM-32E Röle Kartı ve GM60 Entegrasyonu (Kural 4):**
  - **Nasıl Test Edilir:** GM60 barkod/QR okuyucusuna dinamik QR kodu okutun.
  - **Beklenen Sonuç:** UART2 üzerinden okunan QR doğrulanmalı; GPIO 16 röle tetiklenmeli, 5s debounce devrede olmalıdır.
- [ ] **14.3. Bluetooth ile Wi-Fi Kurulumu (BLE Provisioning):**
  - **Nasıl Test Edilir:** Mobil uygulamadan "Bluetooth ile Wi-Fi Kur" ekranına girip cihaza bağlanın.
  - **Beklenen Sonuç:** BLE üzerinden Wi-Fi SSID ve şifre aktarılmalı; cihaz başarıyla ağa bağlanmalıdır.
- [ ] **14.4. Tüm Kapı Açma Metotlarının Eşzamanlı Doğrulaması:**
  - **Nasıl Test Edilir:**
    1. Mobil butonla uzaktan açma (MQTT),
    2. GM60 kameraya dinamik QR göstererek açma,
    3. Geçici misafir kodu (Guest Pass) ile açma.
  - **Beklenen Sonuç:** Her 3 yöntem de hatasız kapı açmalı ve sunucu loglarına doğru kullanıcı ve yöntemle kaydedilmelidir.
- [ ] **14.5. Otomatik Testlerin ve Statik Analizin Yeşil Olması:**
  - **Nasıl Test Edilir:** Terminalde `npm test` (server) ve `flutter test` (mobil) komutlarını çalıştırın.
  - **Beklenen Sonuç:** 20/20 backend testi ve 34/34 Flutter testi %100 başarılı olmalı; `flutter analyze` 0 hata/0 uyarı vermelidir.

---

> 🎯 **Sonuç:** Bu kontrol listesindeki tüm adımlar başarıyla test edildiğinde, AHBU Üyelik Yönetim Sistemi sahada sıfır risk ve tam güvenilirlikle hizmet vermeye hazırdır.

