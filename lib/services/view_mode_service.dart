import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Liste ekranlarının gösterim biçimi: satır listesi ya da kutucuk (ızgara).
enum ListViewMode {
  /// Alt alta satır kartları.
  list,

  /// Yan yana kutucuklar (dar telefonda 2, geniş ekranda 3-4 sütun; büyük yazıda azalır).
  tiles,
}

/// Cihaz depolamasındaki anahtarlar (hesap silinirken de korunur: bkz. `LocalDataWiper`). Anahtar adları değişmez:
/// kayıtlı tercih yeni sürümde de okunur.
abstract final class ViewModeKeys {
  static const String modules = 'app_view_mode_modules';
  static const String apartments = 'app_view_mode_apartments';
  static const String persons = 'app_view_mode_persons';

  /// Hepsi (hesap silme sonrası korunacak cihaz görünümü anahtarları).
  static const Set<String> all = <String>{modules, apartments, persons};
}

/// Liste ↔ kutucuk anahtarı bulunan ekranlar. Her ekranın [defaultMode]'u, anahtar eklenmeden önceki GÖRÜNÜMDÜR:
/// kullanıcı hiç seçim yapmadıysa ekran eskisi gibi görünür.
enum ViewScreen {
  /// Panel vitrini "Modüller" bölümü (eskiden yalnız kutucuk).
  modules(ListViewMode.tiles, ViewModeKeys.modules),

  /// Kişiler → Daireler sekmesi (eskiden yalnız liste).
  apartments(ListViewMode.list, ViewModeKeys.apartments),

  /// Kişiler → Kişiler sekmesi (eskiden yalnız liste).
  persons(ListViewMode.list, ViewModeKeys.persons);

  const ViewScreen(this.defaultMode, this.storageKey);

  final ListViewMode defaultMode;

  /// SharedPreferences anahtarı (değerler: `list`, `tiles`).
  final String storageKey;
}

/// Kullanıcının ekran başına liste / kutucuk tercihi.
///
/// - Varsayılan her ekranın bugünkü görünümüdür ([ViewScreen.defaultMode]); tercih hiç yapılmadıysa hiçbir ekran değişmez.
/// - Tercih cihazda (SharedPreferences, [ViewScreen.storageKey]) saklanır; bozuk/bilinmeyen değer o ekranın
///   varsayılanına döner. Ekranlar birbirinden bağımsızdır.
/// - Depolama hatası uygulamayı bozmaz: tercih bellekte geçerli kalır, yalnız kalıcı olmaz ([ThemeService] ile aynı desen).
class ViewModeService extends ChangeNotifier {
  ViewModeService();

  final Map<ViewScreen, ListViewMode> _modes = <ViewScreen, ListViewMode>{};

  /// [screen] için geçerli kip (seçim yoksa ekranın varsayılanı).
  ListViewMode modeOf(ViewScreen screen) => _modes[screen] ?? screen.defaultMode;

  /// Kayıtlı tercihleri okur (uygulama açılışında bir kez). Değişiklik varsa dinleyicileri bilgilendirir.
  Future<void> load() async {
    final loaded = <ViewScreen, ListViewMode>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final screen in ViewScreen.values) {
        final parsed = _parse(prefs.get(screen.storageKey));
        if (parsed != null) loaded[screen] = parsed;
      }
    } catch (_) {
      // Depolama okunamadı: varsayılan görünümler.
    }
    var changed = false;
    for (final screen in ViewScreen.values) {
      final before = modeOf(screen);
      final next = loaded[screen];
      if (next == null) {
        _modes.remove(screen);
      } else {
        _modes[screen] = next;
      }
      if (modeOf(screen) != before) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// [screen] için tercihi ayarlar ve saklar. Aynı değer yeniden bildirilmez.
  Future<void> setMode(ViewScreen screen, ListViewMode mode) async {
    if (modeOf(screen) == mode) return;
    _modes[screen] = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(screen.storageKey, _serialize(mode));
    } catch (_) {
      // Kalıcılık en iyi çabadır; tercih bu oturum için geçerli.
    }
  }

  /// Düğme davranışı: liste ise kutucuğa, kutucuk ise listeye geçer.
  Future<void> toggle(ViewScreen screen) =>
      setMode(screen, modeOf(screen) == ListViewMode.list ? ListViewMode.tiles : ListViewMode.list);

  static ListViewMode? _parse(Object? raw) {
    switch (raw) {
      case 'list':
        return ListViewMode.list;
      case 'tiles':
        return ListViewMode.tiles;
      default:
        return null;
    }
  }

  static String _serialize(ListViewMode mode) => mode == ListViewMode.list ? 'list' : 'tiles';
}
