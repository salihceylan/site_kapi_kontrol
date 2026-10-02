// FAZ 5 / A0: tasarım sistemi bileşen/ekran testlerinin ortak düzeneği.
//
// `pumpAt` imzası spesifikasyondaki (DESIGN_SPEC G) ile AYNIDIR; değiştirmeyin: A1b/A2 testleri
// bunu kullanır. Bu dosya `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';

/// Taşma matrisi genişlikleri (mantıksal px): küçük telefon, 360, geniş telefon, tablet.
const List<double> kHarnessWidths = <double>[320, 360, 412, 820];

/// Taşma matrisi yazı ölçekleri. Uygulama kökü ölçeği 2,0 ile sınırlar.
const List<double> kHarnessScales = <double>[1.0, 1.5, 2.0];

/// [w]'yi verilen boyutta, yazı ölçeğinde ve temada kurar; taşma dahil hiçbir çerçeve hatası
/// kalmamasını doğrular.
///
/// - `width`/`height` mantıksal px'tir (devicePixelRatio 1,0).
/// - `scale`: sistem yazı ölçeği; uygulama kökündeki 2,0 sınırı bu düzenekte YOKTUR.
/// - `dark`: koyu tema (`ThemeMode.dark`).
/// - `reduce`: `MediaQuery.disableAnimations` (hareket azaltma).
///
/// Yeni kurulum öncesi ağaç boşaltılır: aynı testte art arda çağrılan hücrelerde State sızmaz.
/// Kurulumdan sonra 450 ms ilerletilir (giriş animasyonları [StaggeredEntry] dahil biter).
///
/// Dikkat (gövde): `Scaffold(body: SingleChildScrollView(child: w))` çocuğunu kendi genişliğine
/// SARAR (sınırlar gevşek). Ekran genişliğini kaplaması gereken bir widget'ı sınamak için
/// `SizedBox(width: double.infinity, ...)`/`Column(crossAxisAlignment: stretch)` kullanın; aksi
/// hâlde dar-ekran taşması gerçekte olduğundan hafif görünür. Negatif kontroller
/// `pump_at_test.dart` içindedir (taşan widget `TestFailure` fırlatır: `try/catch` ile `await` edin,
/// `expectLater(pumpAt(...))` kullanmayın: guarded-pump çakışması olur).
Future<void> pumpAt(
  WidgetTester t,
  Widget w, {
  double width = 320,
  double height = 640,
  double scale = 2.0,
  bool dark = false,
  bool reduce = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduce,
        ),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  );
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull); // RenderFlex overflow dahil
}

/// Tüm matris hücreleri: [kHarnessWidths] x [kHarnessScales] x {açık, koyu}.
/// Gövde her hücrede `pumpAt` çağırıp kendi doğrulamasını yapar.
Future<void> forEachHarnessCell(
  Future<void> Function(double width, double scale, bool dark) body,
) async {
  for (final width in kHarnessWidths) {
    for (final scale in kHarnessScales) {
      for (final dark in const <bool>[false, true]) {
        await body(width, scale, dark);
      }
    }
  }
}

/// `pumpAt` olmadan, ilk kareyi de gözlemlemek isteyen testler için ince bir uygulama kabuğu.
Widget harnessApp(
  Widget home, {
  bool dark = false,
  bool reduce = false,
  double scale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduce,
      ),
      child: child!,
    ),
    home: Scaffold(body: home),
  );
}

/// `HapticFeedback.*` çağrılarını kaydeder. Dönen listeye her çağrının argümanı eklenir
/// (örn. `HapticFeedbackType.selectionClick`, `HapticFeedbackType.mediumImpact`).
List<String> recordHaptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}
