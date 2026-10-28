# Yetenek / menü katman ayrımı: kompakt menü ve "Tüm işlemler" (K8, P1-16)

Karar K8 (`docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md`): **yetenek** (hangi modül sitede açık) ile **menü
yerleşimi** (açık yeteneklerden hangilerinin ana menüde öne çıkacağı) ayrı katmanlardır. Fiyat / paket etkisi sahibin kararı
olarak açık kalır; bu iş yalnız yerleşim katmanını kurar.

## 1. Kavramlar

| Katman | Kim belirler | Nerede durur | Değişir mi |
| --- | --- | --- | --- |
| **Yetenek** | Sunucu kataloğu (`server/src/modules/catalog.js`) + `site_modules` | `GET /app/my-modules` → `sites[].modules` | Bu işle DEĞİŞMEZ. Temel (core) 8 modül (`people`, `announcements`, `finance`, `survey`, `neighbor_board`, `equipment`, `annual_report`, `drive_storage`) her sitede açıktır ve **kapatılamaz** (AGENTS.md Kural 25). |
| **Menü yerleşimi** | Site yöneticisi (varsayılan: yönetim türü önerileri) | `site_menu_layouts` (migration **102**) → `sites[].menu_layout` | Yönetici istediği zaman değiştirir; yetenekleri etkilemez. |

- **Kompakt menü kümesi**: ana menüde (yan menü çekmecesi + Panel modül vitrini) öne çıkan **modül kodları** listesi.
- **Sabit öğeler** kümeden etkilenmez, hep ana menüdedir: Panel, **Kapılar** (kapı açma ürünün ana eylemidir), Dairem, Site Yönetimi,
  Daireye Katıl, Yeni Site Oluştur ve **Ayarlar grubunun tümü** (Profilim, Modüller, cihazlar, kullanıcı yönetimi ... sağ üstteki dişli).
- Kümede olmayan açık modül **kaybolmaz**: **"Tüm işlemler"** ekranı kullanıcının görebildiği her işlemi kümeden bağımsız listeler.

## 2. Varsayılan küme (satır yoksa)

`server/src/modules/menu_layout_common.js` → `deriveDefaultCompactModules`. Sitede **açık** olan modüllerden şunlar:

1. günlük işler: `people`, `announcements`, `finance`, `door_control`;
2. sitenin **yönetim türünün önerdiği** modüller (`management_type_terms.js` `recommended_modules`);
3. **isteyerek açılmış** (temel olmayan) modüller: süper kullanıcının siteye özel açtığı modül menüde görünür olmalıdır.

Sonuç: her sitede açık olup önerilmeyen temel modüller (örn. apartmanda Anket, Komşu Panosu, Faaliyet Raporu, Ekipman) varsayılan
olarak yalnız "Tüm işlemler"de durur; isteyen yönetici "Ana menüyü düzenle"den öne çıkarır. Kapalı modül hiçbir kümede yer almaz
(ekranı yoktur). Yönetici kümeyi varsayılanla **aynı** kaydederse özelleştirme sayılmaz (satır silinir): sonradan açılan modüller
varsayılanı izlemeye devam eder.

## 3. Sunucu

- **Tablo** `site_menu_layouts(site_code PK → sites ON DELETE CASCADE, compact_modules TEXT[], updated_by, updated_at)`;
  `migrations/102_site_menu_layout.sql` = `src/modules/menu_layout_schema.js` (test: `server/test/menu_layout.test.js`). Satır yok =
  varsayılan. `db.js` `ensureDbSchema` tabloyu açılışta kurar (hata yoksa bir sorgu).
- **`GET /app/my-modules`** (ekleyici): her site nesnesine `menu_layout: { compact_modules: [...], customized: bool }`. Okuma hatası bu
  ucu bozmaz (varsayılan türetilmiş küme döner). Eski istemci alanı yok sayar.
- **Yönetici uçları** (`requireSiteManager` + `hasSiteManagementAccess`; süper kullanıcı her site; hız sınırı kullanıcı başına 60/saat):
  - `GET /manager/sites/:siteCode/menu-layout` → `{ site_code, site_name, management_type, management_type_label, customized,
    compact_modules, default_compact_modules, modules: [{ code, name, description, core, enabled, compact, recommended }] }`
    (`enabled` = yetenek, `compact` = yerleşim).
  - `PUT .../menu-layout` gövde `{ compact_modules: ["finance", ...] }` → güncel görünüm. Bilinmeyen / "yakında" / metin olmayan kod
    `400 INVALID_MENU_MODULE`, dizi değilse `400 INVALID_BODY`; boş dizi geçerlidir. Katalog sırasına çevrilir, tekrar atılır, eski
    `documents` kodu `drive_storage` olur. **`site_modules`'a ASLA yazılmaz.**
  - `DELETE .../menu-layout` → varsayılana döner (satır silinir).
  - Denetim kaydı: `menu_layout.updated` (ayrıntı: kod listesi), `menu_layout.reset`; değişiklik yoksa satır yazılmaz.
- **Temel modüller kapatılamaz** kuralı aynen geçerlidir: `PUT /manager/sites/:siteCode/modules/:kod` temel modülde
  `400 MODULE_NOT_TOGGLEABLE` döner; menü kümesi bunu değiştirmez (test: "temel modül KAPATILAMAZ").

## 4. İstemci

- `lib/models/menu_layout.dart` modeller; `MySiteModules.menuLayout` (eşitliğe dahil: küme değişince menü hemen yenilenir).
- `lib/ui/helpers/menu_layout.dart` **saf kurallar**: menü öğesi → modül kodu eşlemesi (`menuModuleCodes`), `featuredMenuItems`,
  `allActionsSections`, arama (`foldSearchText`, `filterAllActions`).
  - Kompakt menü **uygulanmaz** (`null` = her şey öne çıkar): süper kullanıcı, modül verisi hiç gelmemiş, hiçbir sitede `menu_layout`
    yok (eski sunucu). Kümesi bilinmeyen site "hepsi öne çıkar" sayılır.
  - Modüle bağlı öğe, o modülün **açık** olduğu sitelerden en az birinin kümesindeyse öne çıkar (site seçici kapsamı geçerlidir);
    modülün açık olduğu bilinmiyorsa öğe gizlenmez.
- `YanMenu(featuredItems, onOpenAllActions)`: çekmecede yalnız öne çıkanlar çizilir; görünürlük (`visibleItems`, `hiddenItems`) ve erişim
  (`HomePage._canAccessMenu`) **değişmez**. **"Tüm işlemler"** girişi başlıklı bölümlerin ardında ("Yardım ve Destek"in üstünde) HER ZAMAN
  vardır; rozeti kompakt menüde gizlenen öğelerin bekleyen / okunmamış sayıları toplamıdır (kompakt menü bir sinyali gizlemez).
- `ModuleShowcaseView(featuredItems, onOpenAllActions)`: Modüller ızgarası çekmeceyle aynı kümeyi gösterir; kompakt menü bir şeyi
  gizliyorsa ızgaranın sonunda "Tüm işlemler" kartı çıkar. Borç özeti, hızlı işlemler, dikkat barı ve "Hesap ve ayarlar" satırı kompakt
  menüden etkilenmez; sakin alt çubuğu (`ResidentBottomBar`) de tam görünür listeden türer.
- `lib/ui/views/all_actions_view.dart` **Tüm işlemler**: görünür TÜM işlemler (Panel hariç) kategorili (Daireler, Borçlar, İletişim, Site
  hizmetleri, Ayarlar), arama kutusuyla (Türkçe katlama; başlık + açıklama + kategori), rozetli; öne çıkanlar "Ana menüde" işaretlidir;
  satıra dokunmak çekmeceden seçmekle AYNI gezinmedir. Yöneticiye "Ana menüyü düzenle" düğmesi çıkar. Modül durumu değişince liste yenilenir.
- `lib/ui/views/menu_layout_view.dart` **Ana menü düzeni** (yönetici / süper kullanıcı): site seçici, yalnız **açık** ve menü yüzeyi olan
  modüller için "Ana menüde" anahtarı (temel modül satırında "Her sitede açık" rozeti), "Hepsini göster", "Önerilen düzene dön", kaydedilmemiş
  değişiklikte onay. Hiçbir modülü açıp kapatmaz.
- `lib/services/menu_layout_api.dart` uç istemcisi (yazma yeniden denenmez; 401 oturum bitişidir).

## 5. Geriye uyum

- Eski istemci + yeni sunucu: `menu_layout` alanını yok sayar, menü eskisi gibi tamdır.
- Yeni istemci + eski sunucu: alan yok → kompakt menü yok, menü eskisi gibi tamdır ("Tüm işlemler" girişi yine vardır).
- Yeni istemci + yeni sunucu: mevcut siteler varsayılan türetilmiş kümeyle gelir (temel olup önerilmeyen modüller "Tüm işlemler"e iner);
  yönetici "Hepsini göster" ile eski tam menüye dönebilir.

## 6. Dağıtım notları

- Migration **102** (`IF NOT EXISTS`); dağıtım provasına (`deploy/remote_rehearse_schema.sh`) `ok102` = `site_menu_layouts` tablosu eklenmelidir
  (paylaşılan dosya: toplu dağıtımda eklenir).
- Sunucu paketi önce, istemci sonra yayınlanır (sıra zorunlu değildir; iki yön de uyumludur).

## 7. Testler

`server/test/menu_layout.test.js`, `server/test/platform_module_routes.test.js` (my-modules `menu_layout`), `test/menu_layout_test.dart`,
`test/menu_layout_api_test.dart`, `test/screens/yan_menu_compact_test.dart`, `test/screens/all_actions_view_test.dart`,
`test/screens/menu_layout_view_test.dart`, `test/screens/menu_layout_home_page_test.dart`.
Çekirdek sözleşme: **kompakt küme değişince menü değişir ama "Tüm işlemler" tam kalır; temel modüller kapatılamaz.**
