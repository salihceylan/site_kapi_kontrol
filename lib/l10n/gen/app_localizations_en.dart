// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginIdentifierLabel => 'Email or username';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String get menuSwitchToAdmin => 'Switch to admin panel';

  @override
  String get menuSwitchToResident => 'Switch to resident mode';

  @override
  String get menuHelp => 'Help and support';

  @override
  String get menuLogout => 'Sign out';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'Device language';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';
}
