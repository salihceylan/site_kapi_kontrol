import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/app.dart';
import 'package:site_kapi_kontrol/services/crash_reporter.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';
import 'package:site_kapi_kontrol/ui/views/app_gate_view.dart';

export 'package:site_kapi_kontrol/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Çökme raporlama kancaları (FlutterError.onError + PlatformDispatcher.onError). Debug/testte kapalı,
  // raporlama hatası uygulamayı asla bozmaz; bekleyen yerel kuyruk kısa bir gecikmeyle gönderilir.
  unawaited(CrashReporter.instance.install());
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
  // Açılış kapısı: bakım / zorunlu güncelleme / yumuşak güncelleme uyarısı. Yapılandırma yüklenemezse
  // uygulama engellenmez; açılış beklemez (bkz. lib/ui/views/app_gate_view.dart).
  runApp(
    AppGate(
      themeService: themeService,
      child: MyApp(themeService: themeService),
    ),
  );
}
