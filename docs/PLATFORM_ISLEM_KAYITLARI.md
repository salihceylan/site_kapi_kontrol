# Site yöneticisinin İşlem Kayıtları (P2-19)

Kullanıcı isteği (karşılaştırma güçlendirme programı, P2-19): "Yönetici kendi sitesinin işlem (audit) kayıtlarını görür." Bu belge ucu, kapsam ve gizlilik kurallarını, filtreleri, istemci
ekranını ve doğrulamayı anlatır. Hukuki görüş değildir.

Migration YOKTUR: okunan tablo mevcut `audit_log`'dur (bkz. `PLATFORM_MODUL_SISTEMI.md`); sorgu mevcut `idx_audit_log_site_id (site_code, id DESC)` indeksini kullanır.

## 1. Mevcut iz kaydı

| Ne | Nerede |
| --- | --- |
| `audit_log` tablosu (yalnız eklenir) | `recordAudit` (`server/src/modules/audit_service.js`) yönetim işlemlerinde satır ekler: modül, rol, kişi / daire, finans, duyuru, belge, talep, rezervasyon, anket, karar, sözleşme, ekipman ... |
| Süper kullanıcı ekranı | `GET /admin/audit-log` (tüm siteler, ham ayrıntı) + istemcide "Denetim Kaydı". **Değişmedi.** |
| Konsol günlüğü (`auditLog`) | yalnız `console.log`; veritabanına yazmaz, bu özellikle ilgisizdir |
| Kapı geçiş kayıtları (`door_access_logs`) | ayrı özellik (kapı olayları); bu ekranda YOKTUR |

## 2. Uç

`GET /manager/sites/:siteCode/audit-log`

| Sorgu | Anlam |
| --- | --- |
| `from`, `to` | `YYYY-AA-GG`; **İstanbul günü**, ikisi de DAHİL; biri boş olabilir. Biçim / takvim / 2000-2100 dışı: `400 INVALID_QUERY`; `from > to`: `400 INVALID_DATE_RANGE` |
| `category` | işlem türü: `modules`, `roles`, `access`, `people`, `finance`, `announcements`, `documents`, `services`, `settings` (aşağıdaki tablo). Bilinmeyen: `400 INVALID_QUERY` |
| `action` | tam eylem adı (ör. `finance.run.posted`); gizli / kataloğa girmeyen eylem için BOŞ liste döner |
| `limit` | 1-200, varsayılan 50 |
| `before_id` | sayfalama imleci (bir önceki yanıttaki `next_before_id`) |

Yanıt: `{ items: [...], next_before_id: <sayı|null> }`, `id DESC`. Öğe:

```json
{
  "id": 412,
  "created_at": "2026-10-27T11:20:00.000Z",
  "actor_name": "Ayşe Yönetici",
  "actor_role": "site_manager",
  "actor_role_label": "Site yöneticisi",
  "action": "board_decision.finalized",
  "action_label": "Karar kesinleştirildi",
  "category": "services",
  "category_label": "Site hizmetleri",
  "target_type": "board_decision",
  "target_id": "17",
  "details": { "number_label": "2026/5" }
}
```

Üstbilgi: `Cache-Control: no-store`. Hız sınırı: kullanıcı başına 600/saat, IP başına 3000/saat (`429`).

### Yetki ve site kapsamı

- YALNIZ o sitenin yöneticisi (`site_manager_sites` ya da aktif `SITE_OWNER` / `SITE_ADMIN`) ve süper kullanıcı (`resolvePeopleAccess write:true`). Kurul üyesi, görevli, sakin, ilgisiz kullanıcı: `403 FORBIDDEN_ROLE`; **başka sitenin yöneticisi: `403 FORBIDDEN_SITE`**; olmayan site (yalnız süper kullanıcıda ulaşılır): `404 SITE_NOT_FOUND`.
- Sorgu YALNIZ yola yazılan siteyi okur (`WHERE a.site_code = $1`); site kodu sorgu dizesinden / gövdeden ALINMAZ. Siteye bağlı olmayan (`site_code` boş) satırlar hiç dönmez.
- Modül gerektirmez (çekirdek). Uç audit_log'a **yazmaz** (okuma izi tutulmaz).

## 3. Kişisel veri asgari (kim, ne zaman, ne yaptı)

- Satırda: sıra no, zaman, işlemi yapanın görünen adı + rol başlığı, eylem + Türkçe başlığı, kategori, hedef türü / no, elekten geçmiş kısa ayrıntı. **Kullanıcı kodu, site kodu, e-posta, telefon, IP, parola / belirteç / anahtar YOKTUR.**
- `details` ham dönmez: yalnız izinli anahtarlar (`module_code`, `number_label`, `old_role`, `new_role`, `role`, `assigned_role`, `door_id`, `count`, `scope`, `enabled`, `is_active`, `status`, `from`, `to`, `field`, `kind`, `via`) ve yalnız kısa, kod benzeri TEK değerler (sayı, mantıksal, ≤ 64 karakter metin). Nesne / dizi / serbest metin / 7+ rakamlı dizi (telefon, kimlik no, IBAN) / belirteç benzeri değer atılır. Hedef no (`target_id`) için de aynı savunma (11+ rakam, belirteç benzeri, e-posta atılır).
- Süper kullanıcının adı yönetici ekranına ÇIKMAZ: "Sistem yöneticisi". Sistem satırı "Sistem". **Silinmiş hesap** (`users.deleted_at` dolu) ya da hesabı kalmamış kişi: "Silinmiş Kullanıcı"; `audit_log` ad anlık görüntüsü bu uçta gösterilmez (anlık görüntü yalnız süper kullanıcıya özeldir; bkz. `account_deletion_service.js`).
- **Gizli liste** (yönetici hiçbir koşulda görmez; kategoriden ÖNCELİKLİ): `residency_log.*` (adli kayıt görüntüleme / dökümü), `safety_request.*` ve `access_suspension.*` (sakinin gizli güvenlik talebi, `PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md`), `apartment_mgmt.person_search` ve `search_visibility_changed` (sakinin kişi arama tercihi), `account.*`, `user.*`, `platform_config.*`, `platform_settings.*`, `subscription.*`, `site_application.*`.
- **Varsayılan KAPALI:** kataloğa girmeyen yeni bir eylem yönetici listesinde görünmez. Görünür olması için `server/src/modules/site_audit_log_catalog.js` içine bilinçli eklenir (kategori öneki + Türkçe başlık). Bilinen bir ailedeki (ör. `finance.`) başlıksız eylem "<Kategori> işlemi" başlığıyla listelenir. `server/test/site_audit_log.test.js` kodda geçen her görünür eylemin başlığı olduğunu denetler.

## 4. İşlem türleri (`category`)

| Anahtar | Başlık | Eylem aileleri |
| --- | --- | --- |
| `modules` | Modüller | `module.`, `module_request.` |
| `roles` | Yetki ve roller | `staff_role.`, `site_manager.`, `team.`, `join_request.` |
| `access` | Kapı ve geçiş | `door_permission.`, `access_card.`, `plate.`, `device.` |
| `people` | Kişi ve daire kayıtları | `person.`, `residency.`, `apartment.`, `apartment_mgmt.`, `vehicle.`, `directory.`, `people.`, `import.`, `export` |
| `finance` | Aidat ve finans | `finance.`, `budget.`, `metering.` |
| `announcements` | Duyurular | `announcement.` |
| `documents` | Dosya deposu | `document.`, `drive.` |
| `services` | Site hizmetleri | `work_item.`, `reservation.`, `reservation_area.`, `concierge.`, `survey.`, `visitor_entry.`, `board_decision.`, `contract.`, `contract_vendor.`, `equipment.`, `quote.`, `cctv.`, `annual_report.`, `neighbor_board.` |
| `settings` | Site ayarları | `site.`, `brand_theme.`, `management_company.`, `platform_rule.`, `emergency.` |

## 5. İstemci

- Menü: **Ayarlar paneli → "İşlem Kayıtları"** (`SirketMenuItem.islemKayitlari`, "Modüller"in hemen altında). YALNIZ yönetici modundaki site yöneticisinde ve yöneticisi olduğu en az bir site bilindiğinde görünür (fail-closed); sakin, kurul, görevli, bireysel ve süper kullanıcıda yoktur (süper kullanıcının tüm siteleri gören ekranı "Denetim Kaydı"dır).
- Ekran (`lib/ui/views/site_audit_log_view.dart`): site seçici (birden fazla site varsa), **İşlem türü** açılır listesi, **Dönem** çipleri (Tümü / Bugün / Son 7 gün / Son 30 gün / Özel aralık; özel aralıkta GG.AA.YYYY alanları, biri boş olabilir), kayıt kartları (ne yapıldı + hedef, kim, kategori, İstanbul saati), "Daha fazla yükle" (devam sayfası İLK sayfanın süzgeciyle istenir), yenile ve aşağı çekip yenileme. Hata asla "kayıt yok" demez.
- Dosyalar: `lib/models/site_audit_log.dart`, `lib/services/site_audit_log_api.dart`, `lib/ui/widgets/site_audit_log_card.dart`. Hedef etiketi süper kullanıcı ekranının mevcut etiket mantığını (`AuditLogEntry.targetLabel`) yeniden kullanır; eylem başlığını sunucu verir (`action_label`), eski sunucuda istemci tablosuna düşer.

## 6. Doğrulama

- `server/test/site_audit_log.test.js` (50 test, DB'siz): katalog / gizli liste, sorgu doğrulama, satır sunumu, sabit sorgu, site kapsamı, tarih / tür / eylem süzgeçleri, sayfalama, erişim matrisi (sakin / kurul / görevli / başka site 403), yanıt gizliliği, hata davranışı.
- `server/scripts/qa_site_audit_log.mjs` (GERÇEK PostgreSQL, `npm test` içinde değildir): LIKE kaçışı, İstanbul gün sınırları, silinmiş hesap, gerçek JWT + `authRequired` ile HTTP erişim matrisi, uç yazmaz, 120 bin satırda indeks erişimi (EXPLAIN: `audit_log` üzerinde Seq Scan yok).
- İstemci: `test/site_audit_log_test.dart` (gerçek sunucu çıktısı fixture'ı, kategori sözleşmesi, HTTP katmanı), `test/screens/site_audit_log_view_test.dart` (taşma matrisi + davranış), `test/screens/site_audit_log_home_page_test.dart` (menü kapıları), `test/menu_groups_test.dart` / `test/module_showcase_test.dart` güncellemeleri.

## 7. Açık noktalar

- Yönetim Kurulu / Denetçi (salt okur) bu ekranı GÖRMEZ; denetçi erişimi bir ürün kararıdır (açılırsa `resolvePeopleAccess` `write:false` ile gizlilik gözden geçirilmelidir).
- Kayıt dışa aktarma (CSV / PDF) yok; döküm gerekirse `PLATFORM_ADLI_KAYIT.md` akışındaki gerekçe + denetim şartı örnek alınmalıdır.
- Hedef kişi / daire adı gösterilmez (yalnız numara); ad çözümlemesi ek kişisel veri ifşasıdır ve ayrı karar gerektirir.
- Çok eski tarih aralıkları büyük tabloda `idx_audit_log_site_id` üzerinde id sırasıyla taranır (120 bin satırda ölçüm: ~0,1 sn); çok büyümesi halinde `(site_code, created_at)` indeksi migration ile eklenebilir.
