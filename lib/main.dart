import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/app.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';

export 'package:site_kapi_kontrol/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {}
  }
  // Kayıtlı tema tercihi ilk karedeki temayı belirler: önce okunur (yanlış temayla açılıp sonra değişmesin).
  final themeService = ThemeService();
  await themeService.load();
  runApp(MyApp(themeService: themeService));
}
