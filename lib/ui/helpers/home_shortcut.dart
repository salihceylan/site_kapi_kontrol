import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart' show SirketMenuItem;

// P1-13 (karşılaştırma raporu, Arayüz): iç ekranlardan tek dokunuşla ana sayfaya (Panel) dönüş. Bu dosya üst çubuktaki
// "Ana sayfa" düğmesinin SAF görünürlük kuralıdır (widget yok); düğmenin kendisi `HomeShortcutButton`.

/// Üst çubuğun solunda, "Ana sayfa" düğmesi varken menü düğmesiyle (48 dp) onun yanındaki düğmenin (48 dp: temanın dokunma
/// hedefi payı dahil) toplam genişliği (dp). Düğme yokken yalnız menü düğmesi (48 dp) vardır.
const double homeShortcutLeadingWidth = 96;

/// "Ana sayfa" düğmesi ile sağdaki eylemler arasında bırakılan pay (dp): yuvarlama ve yazı tipi farkları üst üste bindirmesin.
const double homeShortcutSlack = 2;

/// Üst çubukta "Ana sayfa" düğmesi çizilir mi.
///
/// - [page] Panel'in kendisiyse çizilmez: zaten ana sayfadasınız.
/// - Sakin alt çubuğu çiziliyorsa ([residentBarVisible]) çizilmez: çubuktaki "Özet" sekmesi AYNI işi görür, Panel'e dönmek
///   için ikinci bir yol üretilmez. Çubuk yokken düğme çıkar: yönetici, süper kullanıcı, bireysel kullanıcı, ikiden az
///   sekmesi olan sakin hesabı (örneğin yalnız görevli bağı) ve yatay tutulan telefon.
/// - Düğme sağdaki eylemlerle ([actionsWidth]: yenile + çıkış payı (P2-26: çıkış artık çekmecede, pay bilerek korunur) + dişli + varsa tema düğmesi + varsa mod hapı + kenar boşluğu)
///   üst üste binmeden sığmıyorsa çizilmez ([width] dar): taşma yerine Panel'e menüden ya da geri tuşuyla dönülür. Bu yalnız
///   en dar telefonlarda (çift modlu hesap + tema düğmesi için ~350 dp altı) olur; 360 dp ve üstünde her hesapta sığar.
bool showsHomeShortcut({
  required SirketMenuItem page,
  required bool residentBarVisible,
  required double width,
  required double actionsWidth,
}) =>
    page != SirketMenuItem.dashboard &&
    !residentBarVisible &&
    width >= homeShortcutLeadingWidth + actionsWidth + homeShortcutSlack;
