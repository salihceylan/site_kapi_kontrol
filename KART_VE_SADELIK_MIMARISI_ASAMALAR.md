# TÜM PROJE İÇİN MENÜLÜ KART VE SADELİK MİMARİSİ (AŞAMALAR VE DEVİR PLANI)

Bu belge, **Site Yönetim ve Geçiş Kontrol Platformu** genelindeki tüm ekranların, HCI (İnsan-Bilgisayar Etkileşimi) ve modern arayüz mühendisliği standartlarına uygun olarak **"Evrensel Menülü Kart Mimarisi"ne (`AppActionCard`)** dönüştürülme sürecini, aşamalarını ve teknik detaylarını belgeler. 

Herhangi bir yapay zeka ajanı veya yazılımcı bu belgeyi okuduğunda, projenin hangi aşamada olduğunu, neyin yapıldığını ve sıradaki adımı nasıl icra edeceğini eksiksiz olarak görebilir.

---

## 🎯 Temel Kurallar ve İlkeler

1. **Sıfır Taşma (Rule 6):** Tüm kartlarda metinler `TextOverflow.ellipsis`, `maxLines: 1` veya `2`, rozetler `Wrap(spacing: 6, runSpacing: 4)` ile sarmalanır. 2.0x font boyutu ve 320px dar ekranlarda taşma (overflow) kesinlikle yasaktır.
2. **Geriye Dönük Uyumluluk (Rule 2):** Mevcut iş mantığı, API uç noktaları ve test sözleşmeleri korunmalıdır. Hem ergonomik 3-nokta menü hem de birincil hızlı erişim butonları çift-eylem (dual-action) stratejisiyle sunulur.
3. **Canlı Yenileme (Rule 7):** Yapılan işlemler sonrasında ekran otomatik tazelenmelidir.
4. **Hick-Hyman & Fitts Yasaları:** Açık buton kalabalığı yok; her kartın sağında ergonomik `⋮` (3 nokta) menüsü ve minimum 48×48 dp dokunma alanı.

---

## 🗺️ Aşama Takip Tablosu (Roadmap)

| Aşama | Kapsam / Ekran | Durum | Ana Dosyalar |
| :--- | :--- | :---: | :--- |
| **Aşama 1** | Evrensel Menülü Kart Bileşeni (`AppActionCard`) | **TAMAMLANDI** ✅ | `lib/ui/design/app_action_card.dart` |
| **Aşama 2** | Daire Detay Kartı Sakinleri (`ApartmentCardDialog`) | **TAMAMLANDI** ✅ | `lib/ui/dialogs/apartment_card_dialog.dart` |
| **Aşama 3** | Kişi Kartı ve Araçlar Listesi (`PersonCardDialog`) | **TAMAMLANDI** ✅ | `lib/ui/dialogs/person_card_dialog.dart` |
| **Aşama 4** | Sakin Portalı ("Dairem" Ekranı - Hane & Araçlar) | **TAMAMLANDI** ✅ | `lib/ui/views/my_apartment_view.dart`, `my_apartment_vehicles.dart` |
| **Aşama 5** | Kapılar ve Geçiş Noktaları Kontrol Kartları | **TAMAMLANDI** ✅ | `lib/ui/widgets/admin_door_status_card.dart`, `door_permissions_dialog.dart` |
| **Aşama 6** | PTS Plaka Tanıma & Canlı Kamera Kartları | **TAMAMLANDI** ✅ | `lib/ui/widgets/plate_gates_panel.dart` |
| **Aşama 7** | Finans, Kasa/Banka ve Makbuz Kartları | **TAMAMLANDI** ✅ | `lib/ui/widgets/finance_4b_parts.dart`, `finance_receipt_list_dialog.dart` |
| **Aşama 8** | İş Takibi, Görevler ve Ziyaretçi/Kargo Kartları | **TAMAMLANDI** ✅ | `lib/ui/widgets/work_tracking_parts.dart`, `visitor_log_parts.dart` |
| **Aşama 9** | Bütüncül Testler, Canlı VPS Dağıtımı ve Saha Doğrulaması | **TAMAMLANDI** ✅ | Flutter testleri, PM2, GitHub commit/push |

---

## 📋 Aşamaların Detaylı İçeriği ve Tamamlanan İşler

### Aşama 1: Ortak Çekirdek Bileşen (`AppActionCard`) - TAMAMLANDI ✅
- `lib/ui/design/app_action_card.dart` oluşturuldu.
- `CardActionItem` (label, icon, onTap, key, isDestructive, tone, enabled).
- `AppActionCard` (leading avatar, title, subtitle, badges, actions 3-dot popup menu, inlineActions, touch target 48x48 dp).
- `CardAvatarIcon` (renkli yuvarlak/kare ikon rozeti).
- `flutter analyze lib/ui/design/app_action_card.dart` hatasız doğrulandı.

### Aşama 2: Daire Yönetimi ve Sakinler Ekranı (`ApartmentCardDialog`) - TAMAMLANDI ✅
- `lib/ui/dialogs/apartment_card_dialog.dart` içerisindeki `_residentRow` `AppActionCard` yapısına kavuşturuldu.
- Sağ Menü (`⋮`): "Daireden Ayrıldı / Taşındı" (360° sihirbaz), "Muhatap yap", "Maliki çıkar", "PIN Sıfırla".
- Doğrulama: `test/screens/apartment_owners_card_test.dart` (33/33 test geçti), `apartment_pin_layout_test.dart` ve `apartment_household_test.dart` (88/88 test geçti).

### Aşama 3: Kişi Kartı ve Araçlar Ekranı (`PersonCardDialog`) - TAMAMLANDI ✅
- `lib/ui/dialogs/person_card_dialog.dart` içindeki `_residencyRow` ve araç listesi `AppActionCard` formatına taşındı.
- Sağ Menü (`⋮`): "Notu Düzenle", "Aracı Çıkar", "Pasife Al".
- Doğrulama: `test/screens/people_dialogs_layout_test.dart` (204/204 test geçti).

### Aşama 4: Sakin Portalı ("Dairem" Ekranı - Hane & Araçlar) - TAMAMLANDI ✅
- `lib/ui/views/my_apartment_view.dart` ve `lib/ui/views/my_apartment_vehicles.dart` dönüştürüldü.
- Hane halkı ve sakin araçları `AppActionCard` ile listelendi.
- Doğrulama: `test/screens/my_apartment_view_test.dart` (12/12 test geçti).

### Aşama 5: Kapılar ve Geçiş Noktaları Kontrol Kartları - TAMAMLANDI ✅
- `lib/ui/widgets/admin_door_status_card.dart` ve `lib/ui/dialogs/door_permissions_dialog.dart`.
- Kapı başlığındaki dar ekran 2.0x taşması `Wrap` ile çözüldü; `EmptyState` düzenlendi.
- Doğrulama: `test/screens/admin_door_status_card_layout_test.dart` (48/48 test geçti).

### Aşama 6: PTS Plaka Tanıma & Canlı Kamera Kartları - TAMAMLANDI ✅
- `lib/ui/widgets/plate_gates_panel.dart`.
- Kamera kartları ve kapı başlıkları sağ üst `⋮` 3-nokta eylem menüsü kazandı (Süreleri Ayarla, Canlı Akış, Kamera Ekle, Sına, Düzenle, Kapıdan Ayır, Durdur/Başlat, Sil).
- İçerideki araçlar `AppActionCard` ile listelendi.
- Doğrulama: `test/plate_gates_panel_test.dart` (7/7 test geçti).

### Aşama 7: Finans, Kasa/Banka ve Makbuz Kartları - TAMAMLANDI ✅
- `lib/ui/widgets/finance_4b_parts.dart` ve `lib/ui/dialogs/finance_receipt_list_dialog.dart`.
- `ReceiptTile` ve `CashAccountCard` sağ üst `⋮` menüsüyle zenginleştirildi (Makbuzu Görüntüle, Hareketler, Düzeltme, Banka/Kasa Kontrolü, Düzenle).
- Doğrulama: `test/screens/finance_receipt_test.dart` (85/85 test geçti) ve `test/screens/finance_cash_test.dart` (115/115 test geçti).

### Aşama 8: İş Takibi, Görevler ve Ziyaretçi/Kargo Kartları - TAMAMLANDI ✅
- `lib/ui/widgets/work_tracking_parts.dart` ve `lib/ui/widgets/visitor_log_parts.dart`.
- Sakin ve yönetim arıza/iş takibi kartları (`WorkResidentCard`, `WorkManagedCard`) ile ziyaretçi/kargo kartları (`VisitorManagedCard`, `VisitorResidentCard`) sağ `⋮` menüsüyle modernleştirildi.
- Doğrulama: `test/screens/work_manager_view_test.dart` ve `test/screens/visitor_manager_view_test.dart` (129/129 test geçti).

### Aşama 9: Bütüncül Testler, Canlı VPS Dağıtımı ve Saha Doğrulaması - TAMAMLANDI ✅
- Proje genelinde `flutter analyze lib/...` sıfır hatayla doğrulandı.
- Toplam 600+ birim ve arayüz taşma testi kesintisiz geçirildi.
- Git commit ve push `origin/main` (`3f652539` ve `5c21...`).
- VPS sunucu (`178.210.161.55`) sağlığı ve PM2 durumu doğrulandı (`/health: ok, database: connected, mqtt: connected`).
- `SAHA_KONTROL_LISTESI.md` Bölüm 169 eklendi.
