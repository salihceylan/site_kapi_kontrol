# Beyaz etiket tema ve Phosphor ikonlar (G8 + G9)

## G8: Phosphor ikon seti
- Paket: `phosphor_glyphs` 2.1.2 (düz `const IconData`; `phosphor_flutter` 2.1.0 bu Flutter sürümünde derlenmez çünkü `IconData` artık `final`).
- Ağırlık: yalnız `PhosphorIconsRegular`.
- Değişen yerler: çekmece/menü (`yan_menu.dart` içindeki `_iconForItem` ve çekmece eylemleri; vitrin kartları aynı işlevi kullandığı için kendiliğinden) ve sakin alt çubuğu (`resident_tabs.dart`).
- Kalan yerler (diyaloglar, modül ekranları, `module_icon`) `Icons.*` kullanmaya devam eder; sonraki dalgada taşınır.

## G9: Beyaz etiket tema
- Tablo: `brand_themes` (migration 071; `scope_type` = `company` | `site`, `scope_id`; 5 renk `#RRGGBB`, `display_name` <= 40, `logo_data` png/jpeg/webp veri URL'si <= 200000 karakter). FK yok; kapsam başına tek satır.
- Çözümleme: site teması > bağlı olduğu firmanın teması > varsayılan Güde teması. Varsayılan Güde temasında hiçbir satır gerekmez.
- Uçlar (`brand_theme_routes.js`, hepsi `authRequired`, `no-store`):
  - `GET /brand-theme/mine` kullanıcının etkin teması (`{ theme: null }` = varsayılan). Süper kullanıcı varsayılanı alır.
  - `GET|PUT|DELETE /brand-themes/:scopeType/:scopeId` yalnız süper kullanıcı ya da ilgili firmanın sahibi (site kapsamı için siteyi bağlı tutan firmanın sahibi). Yetkisiz: 404/403.
- Kurallar: yazı rengi zemin ve kartta, vurgu rengi kartta en az 4,5:1 karşıtlık (sunucu `LOW_CONTRAST` döner, istemci de kaydetmez ve gelen okunaksız temayı yok sayar). Ana düğme yazısı ana renge göre beyaz ya da koyu lacivert otomatik seçilir.
- İstemci: `lib/brand/brand_theme.dart` (model, `lightPalette()` 1C sade belirteçlerinin `AppPalette.light` değerlerini 5 renkten türetir), `BrandThemeController` + `BrandThemeScope` + `BrandBar` (çekmecenin üstünde logo ve ad), düzenleyici `lib/ui/views/brand_theme_view.dart` (Yönetim Firması sayfasında "Marka teması" bölümü).
- Kapsam dışı / "Yakında": koyu tema markalanmaz (varsayılan koyu palet kalır); durum renkleri (yeşil/sarı/kırmızı) markalanmaz; SVG logo; giriş öncesi ekranda marka (tema giriş yapınca yüklenir); sitesi olmayan bireysel kullanıcı varsayılan temayı görür; site yöneticisinin kendi site temasını düzenlemesi (şimdilik süper ve firma sahibi).
- Denetim: `brand_theme.saved` / `brand_theme.reset` (renkler ve ad kaydedilir, logo kaydedilmez).
- Test: `server/test/brand_theme.test.js`, `test/brand_theme_test.dart`.
