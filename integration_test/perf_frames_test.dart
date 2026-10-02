// ignore_for_file: avoid_print
//
// FAZ 5 / P: kare süresi ölçüm düzeneği (profile mod, masaüstü).
//
// Gezinti: giriş -> ana panel (boşta: 3 sn'lik yoklama + saat) -> bir kapı kartı (site/kapı seç,
// Detaylar, QR modalı) -> geçiş günlükleri listesi -> (isteğe bağlı) Site Yönetimi uzun liste kaydırma.
// `SchedulerBinding.addTimingsCallback` ile her aşama için build/raster/toplam p50/p90/p99 ve jank
// (>16 ms) oranını JSON'a yazar.
//
// ÇALIŞTIRMA (koordinatör; yerel yığın ayakta, E2E kullanıcıları tohumlanmış, pencere GÖRÜNÜR ve
// simge durumunda DEĞİL olmalı; aynı anda başka `flutter test -d windows` koşusu olmamalı):
//
//   node integration_test/tool/make_defines.mjs --e2e "<E2E>"
//   flutter drive --profile -d windows \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_frames_test.dart \
//     --dart-define=API_BASE_URL=http://127.0.0.1:18080 \
//     --dart-define-from-file=<E2E>/dart_defines.json \
//     --dart-define=PERF_USER=manager_1 --dart-define=PERF_SITE=site_1 \
//     --dart-define=PERF_OUT=<ÇIKTI_DİZİNİ>
//
// Çıktı: <PERF_OUT>/perf_frames.json (uygulama süreci) ve sürücü tarafında aynı içerik
// (test_driver/perf_driver.dart; PERF_OUT ortam değişkeni ya da build/perf). Karşılaştırma için aynı
// komutu taban ve çalışma kopyalarında çalıştırıp JSON'ları kıyaslayın. Üretime bağlanmaz:
// bootApp yalnız yerel API adresine izin verir (E2eEnv.assertLocalApi).
//
// Opsiyonel dart-define'lar: PERF_IDLE_SECONDS (varsayılan 8), PERF_SKIP_SITES=true (Site Yönetimi
// aşamasını atla), PERF_LABEL (JSON'a etiket, örn. "taban" / "faz5").

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_env.dart';
import 'support/perf_frames.dart';

const String _perfUser = String.fromEnvironment('PERF_USER', defaultValue: 'manager_1');
const String _perfSite = String.fromEnvironment('PERF_SITE', defaultValue: 'site_1');
const String _perfOut = String.fromEnvironment('PERF_OUT');
const String _perfLabel = String.fromEnvironment('PERF_LABEL');
const int _idleSeconds = int.fromEnvironment('PERF_IDLE_SECONDS', defaultValue: 8);
const bool _skipSites = bool.fromEnvironment('PERF_SKIP_SITES');

/// Aşama bitişinde zamanlama geri çağrılarının (toplu gelir) ulaşması için bekleme.
const Duration _flush = Duration(milliseconds: 500);

Future<void> _phase(
  FramePerfRecorder recorder,
  WidgetTester tester,
  String name,
  Future<void> Function() body,
) async {
  print('PERF> aşama: $name');
  recorder.beginPhase(name);
  try {
    await body();
  } finally {
    await pumpFor(tester, _flush);
    recorder.endPhase();
  }
}

Future<void> _doorCardTour(WidgetTester tester) async {
  final sites = E2eEnv.siteName(_perfSite);
  if (sites != null) {
    await selectDropdownItem(tester, label: 'Site Seçin', itemText: sites);
    await settle(tester, min: const Duration(milliseconds: 1200));
  }
  final doors = E2eEnv.doorNames(_perfSite);
  for (final door in doors.take(2)) {
    await selectDropdownItem(tester, label: 'Kapı Seçin', itemText: door);
    await settle(tester, min: const Duration(milliseconds: 1500));
    if (findText('Detaylar', exact: true).evaluate().isNotEmpty) {
      await tapText(tester, 'Detaylar', exact: true, required: false);
      await pumpFor(tester, const Duration(milliseconds: 900));
      await tapText(tester, 'Gizle', exact: true, required: false);
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
  }
  // Geri sayım halkası (60 fps çizim) + 800 ms'lik durum yoklaması.
  if (await tapText(tester, 'Giriş QR Kodu Göster', required: false)) {
    await pumpFor(tester, const Duration(seconds: 4));
    await closeOverlays(tester);
    await pumpFor(tester, const Duration(milliseconds: 600));
  }
}

Future<void> _logsTour(WidgetTester tester) async {
  if (!await tapText(tester, 'Geçiş Logları', required: false)) return;
  await pumpFor(tester, const Duration(seconds: 2));
  await scrollAllTheWay(tester);
  await pumpFor(tester, const Duration(milliseconds: 500));
  await tapText(tester, 'Geçiş Logları', required: false);
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// "Site Yönetimi" -> "Daireler" akordiyonunu açıp uzun listeyi kaydırır (RepaintBoundary etkisi).
Future<void> _sitesScrollTour(WidgetTester tester) async {
  if (!await openDrawerAndTap(tester, 'Site Yönetimi')) return;
  await settle(tester, min: const Duration(seconds: 2));
  if (await tapText(tester, 'Daireler', exact: true, required: false)) {
    await pumpFor(tester, const Duration(seconds: 1));
  }
  await scrollAllTheWay(tester);
  await pumpFor(tester, const Duration(milliseconds: 500));
  await scrollAllTheWay(tester);
}

void main() {
  final binding = initE2eBinding();

  testWidgets('PERF: giriş + ana panel + kapı kartı + günlük listesi (kare süreleri)', (tester) async {
    // Motorun gerçek vsync karelerini kullan (elle pump değil): FrameTiming ancak böyle anlamlıdır.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    if (!kProfileMode) {
      print('PERF! UYARI: profile modda değil (kDebugMode=$kDebugMode): sayılar yalnız göreceli kıyas içindir.');
    }

    final user = E2eEnv.user(_perfUser);
    final recorder = FramePerfRecorder()..attach();
    addTearDown(recorder.detach);
    final clock = Stopwatch()..start();

    await _phase(recorder, tester, 'acilis_giris', () async {
      await bootApp(tester);
      await login(tester, user);
      await settle(tester, min: const Duration(seconds: 1));
    });

    await _phase(recorder, tester, 'ana_panel_bosta', () async {
      await settle(tester, min: const Duration(seconds: 1));
      await pumpFor(tester, const Duration(seconds: _idleSeconds));
    });

    await _phase(recorder, tester, 'kapi_karti', () => _doorCardTour(tester));
    await _phase(recorder, tester, 'gecis_loglari', () => _logsTour(tester));
    if (!_skipSites) {
      await _phase(recorder, tester, 'site_yonetimi_liste', () => _sitesScrollTour(tester));
    }

    await closeOverlays(tester);
    await logout(tester);
    recorder.detach();

    final summary = recorder.summary(meta: <String, Object?>{
      'label': _perfLabel,
      'platform': Platform.operatingSystem,
      'user_key': user.key,
      'role': user.role,
      'site_key': _perfSite,
      'idle_seconds': _idleSeconds,
      'total_wall_ms': clock.elapsedMilliseconds,
      'date': DateTime.now().toIso8601String(),
    });
    final text = const JsonEncoder.withIndent('  ').convert(summary);

    // 1) Sürücüye (flutter drive): reportData -> test_driver/perf_driver.dart dosyaya yazar.
    binding.reportData = <String, dynamic>{'perf_frames': summary};

    // 2) Masaüstünde uygulama süreci de doğrudan yazar (sürücü olmadan da sonuç kalsın).
    try {
      final dir = Directory(_perfOut.isNotEmpty ? _perfOut : '${Directory.systemTemp.path}${Platform.pathSeparator}perf_out')
        ..createSync(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}perf_frames.json');
      file.writeAsStringSync(text);
      print('PERF> yazıldı: ${file.path}');
    } catch (e) {
      print('PERF~ dosya yazılamadı ($e); sonuç reportData ile sürücüye iletildi.');
    }
    print('PERF> ÖZET (genel): ${jsonEncode((summary['overall']))}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
