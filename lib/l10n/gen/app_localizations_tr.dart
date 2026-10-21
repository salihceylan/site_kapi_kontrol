// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get loginIdentifierLabel => 'E-posta veya Kullanıcı Adı';

  @override
  String get loginPasswordLabel => 'Şifre';

  @override
  String get loginForgotPassword => 'Şifremi Unuttum?';

  @override
  String get loginSubmit => 'Giriş Yap';

  @override
  String get menuSwitchToAdmin => 'Yönetici Paneline Geç';

  @override
  String get menuSwitchToResident => 'Sakin Moduna Geç';

  @override
  String get menuHelp => 'Yardım ve Destek';

  @override
  String get menuLogout => 'Çıkış Yap';

  @override
  String get languageTitle => 'Dil';

  @override
  String get languageSystem => 'Cihaz dili';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';
}
