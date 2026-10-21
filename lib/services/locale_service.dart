import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/l10n/gen/app_localizations.dart';

/// Kullanıcının dil tercihi. Varsayılan Türkçe; tercih cihazda saklanır (`tr` / `en`).
/// Depolama hatası uygulamayı bozmaz (tercih bellekte kalır).
class LocaleService extends ChangeNotifier {
  LocaleService();

  static const String storageKey = 'app_locale';
  static const List<Locale> supported = [Locale('tr'), Locale('en')];

  Locale _locale = const Locale('tr');
  Locale get locale => _locale;

  Future<void> load() async {
    Locale loaded = const Locale('tr');
    try {
      final prefs = await SharedPreferences.getInstance();
      loaded = parse(prefs.getString(storageKey));
    } catch (_) {}
    if (loaded != _locale) {
      _locale = loaded;
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    final next = parse(locale.languageCode);
    if (next == _locale) {
      return;
    }
    _locale = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, next.languageCode);
    } catch (_) {}
  }

  /// Bilinmeyen/bozuk değer Türkçeye döner.
  static Locale parse(String? raw) => raw == 'en' ? const Locale('en') : const Locale('tr');
}

/// [LocaleService]'i ağaca taşır (MaterialApp'ın üstünde). Kapsam yoksa null.
class LocaleScope extends InheritedNotifier<LocaleService> {
  const LocaleScope({super.key, required LocaleService service, required super.child})
      : super(notifier: service);

  static LocaleService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.notifier;
}

extension L10nContext on BuildContext {
  /// Yerelleştirme yoksa (kapsamsız testler/tek başına sayfalar) Türkçe metinler.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? lookupAppLocalizations(const Locale('tr'));
}
