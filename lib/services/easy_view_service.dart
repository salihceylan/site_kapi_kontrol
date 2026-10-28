import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Kolay görünüm" tercihi: büyük yazı + yüksek karşıtlık + büyük düğmeli sade ana ekran.
///
/// - Varsayılan KAPALI: tercih hiç yapılmadıysa uygulama eskisi gibi görünür.
/// - Tercih cihazda (SharedPreferences, [storageKey]) saklanır; bozuk/bilinmeyen değer kapalı sayılır.
/// - Depolama hatası uygulamayı bozmaz: tercih bellekte geçerli kalır, yalnız kalıcı olmaz ([ThemeService] ile aynı desen).
/// - Tema düzeyinde çalışır (`lib/styles/easy_view_theme.dart`, `lib/app.dart`): tek tek ekranlar yeniden çizilmez.
class EasyViewService extends ChangeNotifier {
  EasyViewService();

  /// SharedPreferences anahtarı (değer: bool). Hesap silinirken de korunur (cihaz görünümü ayarıdır).
  static const String storageKey = 'app_easy_view';

  /// Kolay görünümde uygulamanın en az kullandığı yazı ölçeği. Cihazın yazı boyutu bundan büyükse o geçerlidir;
  /// üst sınır (2,0) uygulama kökünde aynen kalır.
  static const double minTextScale = 1.3;

  bool _enabled = false;

  bool get enabled => _enabled;

  /// Kayıtlı tercihi okur (uygulama açılışında bir kez). Değişiklik varsa dinleyicileri bilgilendirir.
  Future<void> load() async {
    var loaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      loaded = _parse(prefs.get(storageKey));
    } catch (_) {
      // Depolama okunamadı: kapalı.
    }
    if (loaded != _enabled) {
      _enabled = loaded;
      notifyListeners();
    }
  }

  /// Tercihi ayarlar ve saklar. Aynı değer yeniden bildirilmez.
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, value);
    } catch (_) {
      // Kalıcılık en iyi çabadır; tercih bu oturum için geçerli.
    }
  }

  Future<void> toggle() => setEnabled(!_enabled);

  static bool _parse(Object? raw) => raw == true || raw == 'true';
}
