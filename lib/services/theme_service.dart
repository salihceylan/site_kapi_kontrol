import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının tema tercihi: sistem (varsayılan) / aydınlık / karanlık.
///
/// - Varsayılan [ThemeMode.system]: tercih hiç yapılmadıysa uygulama önceki gibi cihaz temasını izler.
/// - Tercih cihazda (SharedPreferences, [storageKey]) saklanır; bozuk/bilinmeyen değer sistem temasına döner.
/// - Depolama hatası uygulamayı bozmaz: tercih bellekte geçerli kalır, yalnız kalıcı olmaz.
class ThemeService extends ChangeNotifier {
  ThemeService();

  /// SharedPreferences anahtarı (değerler: `light`, `dark`; yok/başka = sistem).
  static const String storageKey = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Kayıtlı tercihi okur (uygulama açılışında bir kez). Değişiklik varsa dinleyicileri bilgilendirir.
  Future<void> load() async {
    ThemeMode loaded = ThemeMode.system;
    try {
      final prefs = await SharedPreferences.getInstance();
      loaded = _parse(prefs.getString(storageKey));
    } catch (_) {
      // Depolama okunamadı: sistem teması.
    }
    if (loaded != _mode) {
      _mode = loaded;
      notifyListeners();
    }
  }

  /// Tercihi ayarlar ve saklar. Aynı değer yeniden bildirilmez.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, _serialize(mode));
    } catch (_) {
      // Kalıcılık en iyi çabadır; tercih bu oturum için geçerli.
    }
  }

  /// Düğme davranışı: [effective] ekranda GÖRÜNEN temadır (sistem modunda da). Koyuysa aydınlığa, aksi
  /// hâlde karanlığa geçilir; böylece düğme her zaman görünenin tersini seçer.
  Future<void> toggle(Brightness effective) {
    return setMode(effective == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}
