// ignore_for_file: avoid_print
//
// E2E surucu katmani (Windows masaustu + Android emulator).
//
// Calistirma (proje kokunden; ayni anda YALNIZ BIR `flutter test -d windows`):
//   node integration_test/tool/make_defines.mjs --e2e "<E2E>"
//   flutter test integration_test/walk_super_user_test.dart -d windows \
//     --dart-define=API_BASE_URL=http://127.0.0.1:18080 \
//     --dart-define-from-file=<E2E>/dart_defines.json
//
// Ozellikler:
//  - bootApp / login / logout / pumpUntilFound / tapText / openDrawerAndTap / scrollAllTheWay
//  - pumpAndSettle KULLANMAZ (uygulamada 3 sn'lik yoklamalar var): sabit aralikli pump dongusu
//  - guvenli-dokunma politikasi: yikici eylemler engellenir ([E2ePolicy])
//  - hata toplayici: FlutterError.onError + zone hatalari ilk hatada testi COKERTMEZ, raporlanir
//  - ekran goruntusu: RenderView katmanindan PNG (Windows/Android ortak; takeScreenshot gerekmez)
//  - gorunum presetleri + yazi olcegi (taşma taramasi)

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:site_kapi_kontrol/main.dart' as app;
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';

import 'e2e_env.dart';
import 'e2e_report.dart';

// ---------------------------------------------------------------------------
// Gorunum presetleri
// ---------------------------------------------------------------------------

class E2eViewPreset {
  const E2eViewPreset(this.id, this.logicalSize, this.devicePixelRatio);

  final String id;
  final Size logicalSize;
  final double devicePixelRatio;

  Size get physicalSize =>
      Size(logicalSize.width * devicePixelRatio, logicalSize.height * devicePixelRatio);

  static const E2eViewPreset smallPhone = E2eViewPreset('small_360x640', Size(360, 640), 2.0);
  static const E2eViewPreset phone = E2eViewPreset('phone_412x915', Size(412, 915), 2.6);
  static const E2eViewPreset tablet = E2eViewPreset('tablet_1024x768', Size(1024, 768), 1.0);
}

class E2eCombo {
  const E2eCombo(this.preset, this.textScale);

  final E2eViewPreset preset;
  final double textScale;

  String get id => '${preset.id}_x${textScale.toStringAsFixed(1)}';

  @override
  String toString() => id;

  /// E2E_COMBOS ayrisimi. Bos = tum kombinasyonlar (phone@1.0 once). "quick" = yalniz phone@1.0.
  static List<E2eCombo> parse(String raw) {
    final text = raw.trim().toLowerCase();
    const defaults = <E2eCombo>[
      E2eCombo(E2eViewPreset.phone, 1.0),
      E2eCombo(E2eViewPreset.smallPhone, 1.0),
      E2eCombo(E2eViewPreset.tablet, 1.0),
      E2eCombo(E2eViewPreset.smallPhone, 1.5),
      E2eCombo(E2eViewPreset.phone, 1.5),
      E2eCombo(E2eViewPreset.tablet, 1.5),
    ];
    if (text.isEmpty || text == 'all') return defaults;
    if (text == 'quick') return const <E2eCombo>[E2eCombo(E2eViewPreset.phone, 1.0)];
    final out = <E2eCombo>[];
    for (final token in text.split(',')) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final parts = t.split('@');
      final name = parts.first;
      final scale = parts.length > 1 ? (double.tryParse(parts[1]) ?? 1.0) : 1.0;
      final preset = switch (name) {
        'small' || 'smallphone' || 'small_phone' => E2eViewPreset.smallPhone,
        'phone' || 'normal' => E2eViewPreset.phone,
        'tablet' || 'desktop' => E2eViewPreset.tablet,
        _ => null,
      };
      if (preset != null) out.add(E2eCombo(preset, scale));
    }
    return out.isEmpty ? defaults : out;
  }
}

// ---------------------------------------------------------------------------
// Guvenli-dokunma politikasi
// ---------------------------------------------------------------------------

/// Yikici / geri donusumsuz / veri degistiren eylemlere dokunmayi engeller.
/// Metinler [foldText] ile katlanir (kucuk harf, aksansiz).
class E2ePolicy {
  E2ePolicy._();

  static final List<RegExp> _forbidden = <RegExp>[
    RegExp(r'\bsil\b'),
    RegExp(r'\bsilme\b'),
    RegExp(r'\bsilinsin'),
    RegExp(r'kalici'),
    RegExp(r'\bcikis\b'),
    RegExp(r'pasife al'),
    RegExp(r'\breddet'),
    RegExp(r'iptal et'),
    RegExp(r'\bkaldir'),
    RegExp(r'yeniden baslat'),
    RegExp(r'\bsifirla'),
    RegExp(r'depoya al'),
    RegExp(r'kapidan cikar'),
    RegExp(r'\bonayla'),
    RegExp(r'\bkabul\b'),
    RegExp(r'\bkabul et'),
    RegExp(r'\bpdf\b'),
    RegExp(r'\bota\b'),
    RegExp(r'cop temizlig'),
    RegExp(r'temizligi yap'),
    RegExp(r'\bcikar\b'),
    RegExp(r'\bayril'),
    RegExp(r'\bgonder'),
  ];

  /// Diyalog/alt sayfa ACIKKEN ek olarak yasak olan onay/kayit dugmeleri.
  static final List<RegExp> _forbiddenInDialog = <RegExp>[
    RegExp(r'^kaydet'),
    RegExp(r'^olustur'),
    RegExp(r'^gonder'),
    RegExp(r'^davet'),
    RegExp(r'^ekle\b'),
    RegExp(r'^guncelle'),
    RegExp(r'^degistir'),
    RegExp(r'^evet'),
    RegExp(r'^devam'),
    RegExp(r'^dogrula'),
    RegExp(r'^bagla'),
    RegExp(r'^sahiplen'),
    RegExp(r'^kur\b'),
  ];

  /// Yasaksa nedenini, serbestse null dondurur.
  static String? check(String label, {required bool inDialog}) {
    final f = foldText(label);
    for (final r in _forbidden) {
      if (r.hasMatch(f)) return 'yikici eylem ("$label")';
    }
    if (inDialog) {
      for (final r in _forbiddenInDialog) {
        if (r.hasMatch(f)) return 'diyalogda veri degistiren dugme ("$label")';
      }
    }
    return null;
  }
}

/// Kucuk harfe + aksansiza katlar (Turkce uyumlu), bosluklari tek bosluga indirir.
String foldText(String input) {
  const map = <String, String>{
    'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'İ': 'i', 'I': 'i',
    'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
    'â': 'a', 'Â': 'a', 'î': 'i', 'Î': 'i', 'û': 'u', 'Û': 'u',
    '’': "'", ' ': ' ',
  };
  final b = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    b.write(map[ch] ?? ch.toLowerCase());
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------------
// Calisma zamani durumu
// ---------------------------------------------------------------------------

class E2eRuntime {
  E2eRuntime._();

  static final E2eCollector collector = E2eCollector();

  /// Su an gezilen ekranin sonucu (eylem gunlugu icin).
  static E2eScreenResult? screen;

  static void act(String description) {
    screen?.actions.add(description);
    print('E2E> ${collector.currentScreen}: $description');
  }

  static void skip(String description) {
    screen?.skipped.add(description);
    print('E2E~ ${collector.currentScreen}: atlandi: $description');
  }
}

// ---------------------------------------------------------------------------
// Pompalama
// ---------------------------------------------------------------------------

DateTime _lastFrameWall = DateTime.now();
bool _frameClockHooked = false;
int _rescueFrames = 0;

/// Her karede (motor veya elle) duvar saatini gunceller: elle kare zaman damgasi, son karedeki
/// sistem damgasina GECEN GERCEK SURE kadar eklenir -> motorun sonraki damgalarindan asla buyuk olmaz
/// (aksi halde AnimationController "elapsedInSeconds >= 0.0" assert'i atar).
void _hookFrameClock(WidgetTester tester) {
  if (_frameClockHooked) return;
  _frameClockHooked = true;
  tester.binding.addPersistentFrameCallback((_) => _lastFrameWall = DateTime.now());
}

/// Elle kare uretir (motor kare gondermiyorsa: pencere simge durumunda/arka planda).
void _manualFrame(WidgetTester tester) {
  try {
    final binding = tester.binding;
    var elapsed = DateTime.now().difference(_lastFrameWall);
    if (elapsed < const Duration(milliseconds: 1)) elapsed = const Duration(milliseconds: 1);
    binding.handleBeginFrame(binding.currentSystemFrameTimeStamp + elapsed);
    binding.handleDrawFrame();
  } catch (e) {
    print('E2E~ elle kare uretilemedi: $e');
  }
}

/// tester.pump(duration) + yedek kare surucusu: pencere paylasimli makinede simge durumuna/arka plana
/// alinirsa motor kare uretmez ve tester.pump asla donmez; bu durumda kareyi elle uretiriz.
Future<void> e2ePump(WidgetTester tester, [Duration? duration]) async {
  var finished = false;
  Object? failure;
  StackTrace? failureStack;
  final future = tester.pump(duration).then<void>(
    (_) => finished = true,
    onError: (Object e, StackTrace s) {
      finished = true;
      failure = e;
      failureStack = s;
    },
  );
  var nextRescue = DateTime.now().add((duration ?? Duration.zero) + const Duration(milliseconds: 2500));
  while (!finished) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (finished) break;
    final now = DateTime.now();
    if (now.isAfter(nextRescue)) {
      _rescueFrames += 1;
      if (_rescueFrames == 1 || _rescueFrames % 25 == 0) {
        print('E2E~ motor kare uretmiyor (pencere arka planda olabilir): elle kare #$_rescueFrames');
      }
      _manualFrame(tester);
      nextRescue = now.add(const Duration(milliseconds: 400));
    }
  }
  await future;
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
}

/// Uygulama yasam dongusu degisikliklerini (pencere odagi/simge durumu) zaman damgasiyla yazar.
class _LifecycleLogger with WidgetsBindingObserver {
  final Stopwatch _clock = Stopwatch()..start();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('E2E~ yasam dongusu: $state (+${_clock.elapsed.inSeconds}s)');
  }
}

final _LifecycleLogger _lifecycleLogger = _LifecycleLogger();

/// Gercek zamanli (canli baglama) sabit aralikli pump dongusu.
Future<void> pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(total);
  do {
    await e2ePump(tester, step);
  } while (DateTime.now().isBefore(end));
}

/// [finder] gorunene kadar (en cok [timeout]) pump eder. Bulunduysa true.
Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    if (finder.evaluate().isNotEmpty) return true;
    if (!DateTime.now().isBefore(end)) return false;
    await e2ePump(tester, step);
  }
}

/// [finder] kaybolana kadar pump eder. Kaybolduysa true.
Future<bool> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    if (finder.evaluate().isEmpty) return true;
    if (!DateTime.now().isBefore(end)) return false;
    await e2ePump(tester, step);
  }
}

bool _hasSpinner() =>
    find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
    find.byType(LinearProgressIndicator).evaluate().isNotEmpty;

/// Ag/animasyon sakinlesene kadar bekler: en az [min], donen gostergeler varsa en cok [max].
Future<void> settle(
  WidgetTester tester, {
  Duration min = const Duration(milliseconds: 500),
  Duration max = const Duration(seconds: 6),
}) async {
  final start = DateTime.now();
  await pumpFor(tester, min);
  while (_hasSpinner() && DateTime.now().difference(start) < max) {
    await e2ePump(tester, const Duration(milliseconds: 150));
  }
  await e2ePump(tester, const Duration(milliseconds: 100));
  captureSnackBars();
}

// ---------------------------------------------------------------------------
// Bulucular
// ---------------------------------------------------------------------------

String _textOf(Text w) => w.data ?? w.textSpan?.toPlainText() ?? '';

/// Metni (aksan/buyuk-kucuk harf duyarsiz) eslesen [Text] widget'larini bulur.
Finder findText(String label, {bool exact = false, Finder? within, bool skipOffstage = true}) {
  final needle = foldText(label);
  final base = find.byWidgetPredicate((w) {
    if (w is! Text) return false;
    final f = foldText(_textOf(w));
    if (f.isEmpty) return false;
    return exact ? f == needle : f.contains(needle);
  }, skipOffstage: skipOffstage);
  return within == null ? base : find.descendant(of: within, matching: base);
}

/// Etiketi/ipucu eslesen [TextField] (TextFormField dahil).
Finder findField({String? label, String? hint, Finder? within, bool exact = false}) {
  bool match(String? actual, String? wanted) {
    if (wanted == null) return true;
    if (actual == null) return false;
    final a = foldText(actual);
    final w = foldText(wanted);
    return exact ? a == w : a.contains(w);
  }

  final base = find.byWidgetPredicate((w) {
    if (w is! TextField) return false;
    final d = w.decoration;
    final lbl = d?.labelText ?? (d?.label is Text ? _textOf(d!.label! as Text) : null);
    return match(lbl, label) && match(d?.hintText, hint);
  });
  return within == null ? base : find.descendant(of: within, matching: base);
}

Finder get _topOverlay {
  // Dialog/BottomSheet (en ustte olan, listenin sonundaki).
  final dialogs = find.byType(Dialog);
  final sheets = find.byType(BottomSheet);
  if (dialogs.evaluate().isNotEmpty) return dialogs.last;
  if (sheets.evaluate().isNotEmpty) return sheets.last;
  return find.byType(Dialog);
}

bool hasOverlay() =>
    find.byType(Dialog).evaluate().isNotEmpty || find.byType(BottomSheet).evaluate().isNotEmpty;

NavigatorState? _rootNavigator(WidgetTester tester) {
  final nav = find.byType(Navigator);
  if (nav.evaluate().isEmpty) return null;
  return tester.firstState<NavigatorState>(nav);
}

// ---------------------------------------------------------------------------
// Genel metin taramalari (supheli metin, hata mesaji)
// ---------------------------------------------------------------------------

final List<RegExp> _suspiciousText = <RegExp>[
  RegExp(r'Instance of'),
  RegExp(r'\bnull\b'),
  RegExp(r'\bNaN\b'),
  RegExp(r'Infinity'),
  RegExp(r'\bundefined\b'),
  RegExp(r'Exception'),
  RegExp(r'Bad state'),
  RegExp(r'is not a subtype'),
  RegExp(r'\[object'),
  RegExp(r'Unhandled'),
  RegExp(r'\$\{?[a-zA-Z_]+\}?'), // enterpolasyon kalintisi: "$name"
];

/// Ekrandaki (gorunen) tum Text metinlerini toplar.
List<String> visibleTexts() {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget;
    if (w is Text) {
      final t = _textOf(w).trim();
      if (t.isNotEmpty) out.add(t);
    }
  }
  return out;
}

/// "null", "Instance of", istisna adi vb. supheli metin parcalarini rapora yazar.
void scanSuspiciousText() {
  final seen = <String>{};
  for (final t in visibleTexts()) {
    for (final r in _suspiciousText) {
      if (r.hasMatch(t) && seen.add(t)) {
        E2eRuntime.collector.note(
          kind: 'suspicious-text',
          message: 'Supheli metin gorunuyor: "${t.length > 160 ? '${t.substring(0, 160)}...' : t}"',
        );
        break;
      }
    }
  }
}

const List<String> _errorishWords = <String>[
  'hata',
  'basarisiz',
  'ulasilamadi',
  'yuklenemedi',
  'alinamadi',
  'olusturulamadi',
  'acilamadi',
  'zaman asimi',
  'sunucu',
  'baglanti',
];

/// Gorunen SnackBar metinlerini eylem gunlugune yazar; hata benzeri ise bulgu uretir.
void captureSnackBars() {
  final snacks = find.byType(SnackBar);
  if (snacks.evaluate().isEmpty) return;
  for (final e in find.descendant(of: snacks, matching: find.byType(Text)).evaluate()) {
    final w = e.widget;
    if (w is! Text) continue;
    final text = _textOf(w).trim();
    if (text.isEmpty) continue;
    final entry = 'snackbar: "$text"';
    final acts = E2eRuntime.screen?.actions;
    final recent = acts == null ? const <String>[] : acts.skip(acts.length > 6 ? acts.length - 6 : 0);
    if (!recent.contains(entry)) E2eRuntime.act(entry);
    final folded = foldText(text);
    if (_errorishWords.any(folded.contains)) {
      E2eRuntime.collector.note(kind: 'ui-error', message: 'Hata benzeri bildirim: "$text"');
    }
  }
}

// ---------------------------------------------------------------------------
// Dokunma / yazma
// ---------------------------------------------------------------------------

bool _isHittable(Finder f) => f.hitTestable().evaluate().isNotEmpty;

/// [scrollable] icinde (yoksa herhangi bir dikey kaydirilabilirde) [finder] gorunene kadar kaydirir.
Future<bool> scrollUntilFound(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
  double step = 160,
  int maxSteps = 60,
}) async {
  if (finder.evaluate().isNotEmpty) return true;
  final scrollables = scrollable ?? find.byType(Scrollable);
  for (final direction in <int>[1, -1]) {
    for (var i = 0; i < maxSteps; i++) {
      if (finder.evaluate().isNotEmpty) return true;
      var moved = false;
      for (final e in scrollables.evaluate().toList()) {
        if (e is! StatefulElement) continue;
        final state = e.state;
        if (state is! ScrollableState) continue;
        final axis = state.axisDirection;
        if (axis != AxisDirection.down && axis != AxisDirection.up) continue;
        final pos = state.position;
        if (!pos.hasContentDimensions) continue;
        final target = (pos.pixels + direction * step).clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((target - pos.pixels).abs() > 0.5) {
          pos.jumpTo(target);
          moved = true;
        }
      }
      await e2ePump(tester, const Duration(milliseconds: 50));
      if (!moved) break;
    }
  }
  return finder.evaluate().isNotEmpty;
}

/// [label] metnine sahip ogeye dokunur. Gorunmuyorsa bekler/kaydirir. Politika kontrolu yapar.
/// Dokunuldu ise true. [unsafe]=true yalniz veri DEGISTIREN ozel testlerde kullanilir.
Future<bool> tapText(
  WidgetTester tester,
  String label, {
  bool exact = false,
  int index = 0,
  Finder? within,
  Finder? scrollable,
  bool required = true,
  bool unsafe = false,
  Duration? waitFor,
  Duration settleAfter = const Duration(milliseconds: 500),
}) async {
  if (!unsafe) {
    final reason = E2ePolicy.check(label, inDialog: hasOverlay());
    if (reason != null) {
      E2eRuntime.collector.note(kind: 'policy', message: 'Dokunma engellendi: $reason');
      E2eRuntime.skip('"$label" ($reason)');
      return false;
    }
  }
  final finder = findText(label, exact: exact, within: within);
  // Istege bagli (required: false) dokunuslar yoksa hizla gecilir.
  var found = await pumpUntilFound(
    tester,
    finder,
    timeout: waitFor ?? (required ? const Duration(seconds: 3) : const Duration(milliseconds: 1200)),
  );
  if (!found && (required || scrollable != null)) {
    found = await scrollUntilFound(tester, finder, scrollable: scrollable);
  }
  if (!found) {
    if (required) {
      E2eRuntime.collector.note(kind: 'tap-missing', message: 'Dokunulacak metin bulunamadi: "$label"');
    }
    E2eRuntime.skip('"$label" bulunamadi');
    return false;
  }
  final ok = await _tapFinder(tester, finder, index: index, description: '"$label"');
  if (ok) await settle(tester, min: settleAfter, max: const Duration(seconds: 4));
  return ok;
}

Future<bool> _tapFinder(
  WidgetTester tester,
  Finder finder, {
  int index = 0,
  required String description,
}) async {
  final count = finder.evaluate().length;
  if (count == 0) return false;

  // 1) Kaydirmadan dokunulabilir olan n'inci eslesme (modal katmanin arkasindakiler elenir).
  var pick = _nthHittable(finder, index);
  // 2) Yoksa her adayi gorunur kilmayi dene (ListView/SingleChildScrollView icinde).
  if (pick == null) {
    for (var i = 0; i < count; i++) {
      if (finder.evaluate().length <= i) break;
      try {
        await tester.ensureVisible(finder.at(i));
      } catch (_) {}
      await e2ePump(tester, const Duration(milliseconds: 80));
      pick = _nthHittable(finder, index);
      if (pick != null) break;
    }
  }
  // 3) SnackBar altta dugmeyi kapatiyor olabilir: kaybolmasini bekle (en cok ~5 sn).
  var waited = 0;
  while (pick == null && find.byType(SnackBar).evaluate().isNotEmpty && waited < 5) {
    await pumpFor(tester, const Duration(seconds: 1));
    waited += 1;
    pick = _nthHittable(finder, index);
  }
  if (pick == null) {
    E2eRuntime.collector.note(
      kind: 'tap-not-hittable',
      message: 'Dokunulamadi (ustu kapali/ekran disi): $description',
    );
    E2eRuntime.skip('$description dokunulabilir degil');
    return false;
  }
  await tester.tap(pick, warnIfMissed: false);
  E2eRuntime.act('dokun $description');
  return true;
}

/// [finder] eslesmeleri arasinda dokunulabilir (hit-test edilebilir) olanlarin [index]'incisi.
Finder? _nthHittable(Finder finder, int index) {
  final n = finder.evaluate().length;
  var seen = 0;
  for (var i = 0; i < n; i++) {
    final f = finder.at(i).hitTestable();
    if (f.evaluate().isNotEmpty) {
      if (seen == index) return f;
      seen += 1;
    }
  }
  return null;
}

Future<bool> tapFinder(
  WidgetTester tester,
  Finder finder, {
  int index = 0,
  required String description,
  Duration settleAfter = const Duration(milliseconds: 500),
}) async {
  final ok = await _tapFinder(tester, finder, index: index, description: description);
  if (ok) await settle(tester, min: settleAfter, max: const Duration(seconds: 4));
  return ok;
}

/// Ipucu (tooltip) metniyle bulunan dugmeye dokunur (AppBar ikonlari).
Future<bool> tapTooltip(
  WidgetTester tester,
  String message, {
  bool unsafe = false,
  bool required = true,
  Duration settleAfter = const Duration(milliseconds: 500),
}) async {
  if (!unsafe) {
    final reason = E2ePolicy.check(message, inDialog: hasOverlay());
    if (reason != null) {
      E2eRuntime.collector.note(kind: 'policy', message: 'Dokunma engellendi: $reason');
      E2eRuntime.skip('tooltip "$message" ($reason)');
      return false;
    }
  }
  final finder = find.byTooltip(message);
  if (!await pumpUntilFound(tester, finder, timeout: const Duration(seconds: 3))) {
    if (required) {
      E2eRuntime.collector.note(kind: 'tap-missing', message: 'Tooltip bulunamadi: "$message"');
    }
    E2eRuntime.skip('tooltip "$message" bulunamadi');
    return false;
  }
  final ok = await _tapFinder(tester, finder, description: 'tooltip "$message"');
  if (ok) await settle(tester, min: settleAfter, max: const Duration(seconds: 4));
  return ok;
}

/// Ikona (find.byIcon) dokunur; tooltip'i olmayan IconButton'lar icin.
Future<bool> tapIcon(
  WidgetTester tester,
  IconData icon, {
  int index = 0,
  bool required = true,
  Finder? within,
  Duration settleAfter = const Duration(milliseconds: 500),
}) async {
  final base = find.byIcon(icon);
  final finder = within == null ? base : find.descendant(of: within, matching: base);
  if (!await pumpUntilFound(tester, finder, timeout: const Duration(seconds: 3))) {
    if (required) {
      E2eRuntime.collector.note(kind: 'tap-missing', message: 'Ikon bulunamadi: ${icon.codePoint.toRadixString(16)}');
    }
    E2eRuntime.skip('ikon ${icon.codePoint.toRadixString(16)} bulunamadi');
    return false;
  }
  final ok = await _tapFinder(tester, finder, index: index, description: 'ikon 0x${icon.codePoint.toRadixString(16)}');
  if (ok) await settle(tester, min: settleAfter, max: const Duration(seconds: 4));
  return ok;
}

/// Sayfadaki tum ExpansionTile'lari sirayla acip kapatir (akordeon taramasi). Acilan sayisini dondurur.
Future<int> toggleExpansionTiles(
  WidgetTester tester, {
  Future<void> Function(int index)? whileOpen,
  int max = 6,
}) async {
  var opened = 0;
  final count = find.byType(ExpansionTile).evaluate().length;
  for (var i = 0; i < count && i < max; i++) {
    final tile = find.byType(ExpansionTile).at(i);
    if (tile.evaluate().isEmpty) break;
    final header = find.descendant(of: tile, matching: find.byType(ListTile));
    if (header.evaluate().isEmpty) continue;
    if (!await tapFinder(tester, header.first, description: 'akordeon #$i')) continue;
    opened += 1;
    await settle(tester, min: const Duration(milliseconds: 500), max: const Duration(seconds: 4));
    if (whileOpen != null) await whileOpen(i);
    final again = find.byType(ExpansionTile).at(i);
    final header2 = find.descendant(of: again, matching: find.byType(ListTile));
    if (header2.evaluate().isNotEmpty) {
      await tapFinder(tester, header2.first, description: 'akordeon #$i (kapat)');
    }
  }
  return opened;
}

/// Acilir listeyi (DropdownButton/FormField) etiketine gore acip [itemText] ogesini secer.
Future<bool> selectDropdownItem(
  WidgetTester tester, {
  required String label,
  required String itemText,
}) async {
  final needle = foldText(label);
  final decorator = find.byWidgetPredicate(
    (w) => w is InputDecorator && foldText(w.decoration.labelText ?? '') == needle,
  );
  if (!await pumpUntilFound(tester, decorator, timeout: const Duration(seconds: 3))) {
    E2eRuntime.skip('liste "$label" bulunamadi');
    return false;
  }
  final arrow = find.descendant(of: decorator, matching: find.byIcon(Icons.arrow_drop_down));
  if (arrow.evaluate().isEmpty) {
    E2eRuntime.skip('liste "$label" oku bulunamadi');
    return false;
  }
  if (!await tapFinder(tester, arrow.first, description: 'liste "$label"')) return false;
  final item = findText(itemText);
  if (!await pumpUntilFound(tester, item, timeout: const Duration(seconds: 3))) {
    E2eRuntime.skip('liste ogesi "$itemText" yok');
    await closeOverlays(tester);
    return false;
  }
  await pumpFor(tester, const Duration(milliseconds: 450)); // acilis animasyonu bitsin
  final ok = await tapFinder(tester, item.last, description: 'liste ogesi "$itemText"');
  if (!ok) await closeOverlays(tester);
  return ok;
}

/// Etiketi/ipucu eslesen alana yazar.
Future<bool> enterField(
  WidgetTester tester,
  String text, {
  String? label,
  String? hint,
  Finder? within,
  int index = 0,
  bool exact = false,
  bool secret = false,
}) async {
  final finder = findField(label: label, hint: hint, within: within, exact: exact);
  final name = label ?? hint ?? 'alan';
  if (!await pumpUntilFound(tester, finder, timeout: const Duration(seconds: 3))) {
    E2eRuntime.collector.note(kind: 'tap-missing', message: 'Yazilacak alan bulunamadi: "$name"');
    E2eRuntime.skip('alan "$name" bulunamadi');
    return false;
  }
  final count = finder.evaluate().length;
  final i = index < count ? index : count - 1;
  try {
    await tester.ensureVisible(finder.at(i));
  } catch (_) {}
  await e2ePump(tester, const Duration(milliseconds: 60));
  final editable = tester.state<EditableTextState>(
    find.descendant(of: finder.at(i), matching: find.byType(EditableText), matchRoot: true),
  );
  tester.binding.focusedEditable = editable;
  await e2ePump(tester);
  tester.testTextInput.enterText(text);
  await e2ePump(tester, const Duration(milliseconds: 150));
  E2eRuntime.act(secret ? 'yaz alan "$name" (gizli)' : 'yaz alan "$name": "$text"');
  return true;
}

// ---------------------------------------------------------------------------
// Kaydirma / katmanlar / cekmece
// ---------------------------------------------------------------------------

List<ScrollableState> _verticalScrollables(Finder scope) {
  final out = <ScrollableState>[];
  for (final e in scope.evaluate()) {
    if (e is! StatefulElement) continue;
    final state = e.state;
    if (state is! ScrollableState) continue;
    final axis = state.axisDirection;
    if (axis != AxisDirection.down && axis != AxisDirection.up) continue;
    final pos = state.position;
    if (!pos.hasContentDimensions) continue;
    out.add(state);
  }
  return out;
}

/// Sayfanin (veya [within] icindeki) dikey kaydirilabilir alanlarini sonuna kadar kaydirir (tembel
/// icerik olusur, taşma yakalanir), sonra basa doner. Kaydirilan alan sayisini dondurur.
Future<int> scrollAllTheWay(WidgetTester tester, {Finder? within, bool backToTop = true}) async {
  final scope = within == null
      ? find.byType(Scrollable)
      : find.descendant(of: within, matching: find.byType(Scrollable));
  var scrolled = 0;
  final states = _verticalScrollables(scope);
  for (final state in states) {
    if (!state.mounted) continue;
    final pos = state.position;
    if (!pos.hasContentDimensions) continue;
    if (pos.maxScrollExtent <= 0.5) continue;
    scrolled += 1;
    var guard = 0;
    while (guard++ < 80) {
      final step = (pos.viewportDimension * 0.85).clamp(120.0, 900.0);
      final next = (pos.pixels + step).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((next - pos.pixels).abs() < 0.5 && pos.pixels >= pos.maxScrollExtent - 0.5) break;
      pos.jumpTo(next);
      await e2ePump(tester, const Duration(milliseconds: 90));
      if (pos.pixels >= pos.maxScrollExtent - 0.5) {
        // Tembel icerik maxScrollExtent'i buyutmus olabilir: bir kez daha dene.
        await e2ePump(tester, const Duration(milliseconds: 90));
        if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
      }
    }
  }
  if (backToTop) {
    await scrollToTop(tester, within: within);
  }
  return scrolled;
}

Future<void> scrollToTop(WidgetTester tester, {Finder? within}) async {
  final scope = within == null
      ? find.byType(Scrollable)
      : find.descendant(of: within, matching: find.byType(Scrollable));
  for (final state in _verticalScrollables(scope)) {
    if (!state.mounted) continue;
    state.position.jumpTo(state.position.minScrollExtent);
  }
  await e2ePump(tester, const Duration(milliseconds: 120));
}

/// Dikey kaydirilabilir alanlardan sonuna ulasilabilen en buyugu, "sayfa sonunda" gorunumu icin.
Future<void> scrollPageToEnd(WidgetTester tester, {Finder? within}) async {
  final scope = within == null
      ? find.byType(Scrollable)
      : find.descendant(of: within, matching: find.byType(Scrollable));
  for (final state in _verticalScrollables(scope)) {
    if (!state.mounted) continue;
    final pos = state.position;
    if (pos.maxScrollExtent > 0.5) pos.jumpTo(pos.maxScrollExtent);
  }
  await e2ePump(tester, const Duration(milliseconds: 150));
}

/// En ustteki katmani (dialog/alt sayfa/sayfa) kapatir: once Vazgec/Iptal/Kapat dokunusu, yoksa pop.
Future<bool> closeTop(WidgetTester tester) async {
  final nav = _rootNavigator(tester);
  if (nav == null) return false;
  final scaffold = _homeScaffoldState(tester);
  if (scaffold != null && scaffold.isDrawerOpen) {
    scaffold.closeDrawer();
    await pumpFor(tester, const Duration(milliseconds: 350));
    return true;
  }
  if (!nav.canPop()) return false;
  if (hasOverlay()) {
    for (final label in <String>['Vazgeç', 'İptal', 'Kapat', 'Geri', 'Şimdi Değil', 'Anladım', 'Tamam']) {
      final f = findText(label, exact: true, within: _topOverlay);
      if (f.evaluate().isNotEmpty && _isHittable(f.first)) {
        await tester.tap(f.first, warnIfMissed: false);
        E2eRuntime.act('kapat "$label"');
        await pumpFor(tester, const Duration(milliseconds: 450));
        return true;
      }
    }
    final closeTip = find.descendant(of: _topOverlay, matching: find.byTooltip('Kapat'));
    if (closeTip.evaluate().isNotEmpty && _isHittable(closeTip.first)) {
      await tester.tap(closeTip.first, warnIfMissed: false);
      E2eRuntime.act('kapat (Kapat ikonu)');
      await pumpFor(tester, const Duration(milliseconds: 450));
      return true;
    }
  }
  nav.pop();
  E2eRuntime.act('kapat (geri/pop)');
  await pumpFor(tester, const Duration(milliseconds: 450));
  return true;
}

/// Tum acik katmanlari (cekmece, diyalog, alt sayfa, itilmis sayfa) kapatip ana sayfaya doner.
Future<void> closeOverlays(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    final nav = _rootNavigator(tester);
    final scaffold = _homeScaffoldState(tester);
    final drawerOpen = scaffold?.isDrawerOpen ?? false;
    if (nav == null || (!nav.canPop() && !drawerOpen)) return;
    await closeTop(tester);
  }
}

ScaffoldState? _homeScaffoldState(WidgetTester tester) {
  final home = find.byType(HomePage);
  if (home.evaluate().isEmpty) return null;
  final scaffold = find.descendant(of: home, matching: find.byType(Scaffold));
  if (scaffold.evaluate().isEmpty) return null;
  return tester.firstState<ScaffoldState>(scaffold);
}

Future<bool> openDrawer(WidgetTester tester) async {
  final scaffold = _homeScaffoldState(tester);
  if (scaffold == null) return false;
  if (!scaffold.isDrawerOpen) {
    scaffold.openDrawer();
  }
  await pumpFor(tester, const Duration(milliseconds: 450));
  return find.byType(Drawer).evaluate().isNotEmpty;
}

/// Cekmeceyi acip [label] menu ogesine dokunur (cekmece kapanir, ekran degisir).
Future<bool> openDrawerAndTap(
  WidgetTester tester,
  String label, {
  bool unsafe = false,
}) async {
  await closeOverlays(tester);
  if (!await openDrawer(tester)) {
    E2eRuntime.collector.note(kind: 'navigation', message: 'Cekmece acilamadi (menu: "$label")');
    return false;
  }
  final drawer = find.byType(Drawer);
  final drawerScrollable = find.descendant(of: drawer, matching: find.byType(Scrollable));
  return tapText(
    tester,
    label,
    exact: true,
    within: drawer,
    scrollable: drawerScrollable,
    unsafe: unsafe,
    settleAfter: const Duration(milliseconds: 600),
  );
}

// ---------------------------------------------------------------------------
// Ekran goruntusu
// ---------------------------------------------------------------------------

String _safeName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]+'), '_');

/// Kok RenderView katmanini PNG olarak [path]'e yazar. Basarisizsa null.
Future<String?> saveScreenshot(WidgetTester tester, String path) async {
  try {
    await e2ePump(tester, const Duration(milliseconds: 60));
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer;
    if (layer is! OffsetLayer) {
      E2eRuntime.collector.note(kind: 'note', message: 'Ekran goruntusu alinamadi (katman yok)');
      return null;
    }
    final bounds = renderView.paintBounds;
    final longest = bounds.width > bounds.height ? bounds.width : bounds.height;
    final ratio = longest <= E2eEnv.shotMax ? 1.0 : E2eEnv.shotMax / longest;
    final bytes = await tester.runAsync<List<int>?>(() async {
      final ui.Image image = await layer.toImage(bounds, pixelRatio: ratio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    if (bytes == null) return null;
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return path;
  } catch (e) {
    E2eRuntime.collector.note(kind: 'note', message: 'Ekran goruntusu hatasi: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Uygulama acilis / giris / cikis
// ---------------------------------------------------------------------------

/// lib/main.dart'in main()'ini cagirir. Oncesinde kayitli oturumu temizler (temiz baslangic).
Future<void> bootApp(WidgetTester tester) async {
  E2eEnv.assertLocalApi();
  // IntegrationTestWidgetsFlutterBinding klavye taklidini kaydetmez; enterText icin gerekli
  // (her testte yeniden kaydedilir: baglama testler arasinda sifirlayabilir).
  tester.testTextInput.register();
  try {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'auth_session');
    await storage.delete(key: 'local_door_cache');
  } catch (e) {
    print('E2E~ guvenli depo temizlenemedi: $e');
  }
  unawaited(app.main());
  final reached = await pumpUntilFound(
    tester,
    find.byType(LoginPage),
    timeout: const Duration(seconds: 45),
  );
  if (!reached) {
    throw StateError('Giris ekrani acilmadi (uygulama acilisi/NoInternet?).');
  }
  await settle(tester, min: const Duration(milliseconds: 600));
}

/// Giris ekranindan [user] ile giris yapar; ana sayfa gorunene kadar bekler.
Future<void> login(WidgetTester tester, E2eUser user) async {
  E2eRuntime.collector.beginScreen('login');
  final onLogin = await pumpUntilFound(tester, find.byType(LoginPage), timeout: const Duration(seconds: 30));
  if (!onLogin) throw StateError('Giris ekrani yok.');
  await enterField(tester, user.login, label: 'E-posta veya Kullanıcı Adı');
  await enterField(tester, user.password, label: 'Şifre', exact: true, secret: true);
  await tapText(tester, 'Giriş Yap', exact: true, unsafe: true);
  final ok = await pumpUntilFound(tester, find.byType(HomePage), timeout: const Duration(seconds: 40));
  if (!ok) {
    final snacks = <String>[];
    for (final e in find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)).evaluate()) {
      snacks.add(_textOf(e.widget as Text));
    }
    throw StateError('Giris basarisiz (${user.key}): ${snacks.isEmpty ? 'ana sayfa acilmadi' : snacks.join(' | ')}');
  }
  await settle(tester, min: const Duration(milliseconds: 800), max: const Duration(seconds: 8));
  E2eRuntime.act('giris yapildi (${user.key})');
}

/// AppBar "Çıkış Yap" ile oturumu kapatir; giris ekranini bekler.
Future<void> logout(WidgetTester tester) async {
  await closeOverlays(tester);
  await tapTooltip(tester, 'Çıkış Yap', unsafe: true);
  final ok = await pumpUntilFound(tester, find.byType(LoginPage), timeout: const Duration(seconds: 20));
  if (!ok) {
    E2eRuntime.collector.note(kind: 'navigation', message: 'Cikis sonrasi giris ekrani gelmedi');
  }
  await settle(tester, min: const Duration(milliseconds: 500));
}

// ---------------------------------------------------------------------------
// Oturum / senaryo / ekran gezintisi
// ---------------------------------------------------------------------------

typedef E2eInteractions = Future<void> Function(E2eScreenContext ctx);

/// Gezilecek bir ekranin tanimi.
class E2eScreenSpec {
  const E2eScreenSpec({
    required this.name,
    required this.menuLabel,
    this.titleText,
    this.interactions,
    this.expectTexts = const <String>[],
    this.opensDialogInstead = false,
  });

  /// Dosya adi dostu ekran adi (ornek: "site_yonetimi").
  final String name;

  /// Cekmecedeki menu etiketi (tam eslesme).
  final String menuLabel;

  /// AppBar baslik metni (gectigimizi dogrulamak icin).
  final String? titleText;

  /// Ekranda mutlaka gorunmesi beklenen metinler (bos/yanlis veri tespiti).
  final List<String> expectTexts;

  /// Menu ogesi sayfa degil diyalog aciyorsa (ornek: Eller Serbest).
  final bool opensDialogInstead;

  final E2eInteractions? interactions;
}

/// Ekran etkilesimleri icin yardimci baglam.
class E2eScreenContext {
  E2eScreenContext(this.session, this.tester, this.result);

  final E2eSession session;
  final WidgetTester tester;
  final E2eScreenResult result;

  String get name => result.name;

  Future<bool> tap(
    String label, {
    bool exact = false,
    int index = 0,
    Finder? within,
    bool required = true,
    Duration settleAfter = const Duration(milliseconds: 500),
  }) =>
      tapText(
        tester,
        label,
        exact: exact,
        index: index,
        within: within,
        required: required,
        settleAfter: settleAfter,
      );

  Future<bool> tapTip(String message, {bool required = true, bool unsafe = false}) =>
      tapTooltip(tester, message, required: required, unsafe: unsafe);

  Future<bool> type(String text, {String? label, String? hint, int index = 0}) =>
      enterField(tester, text, label: label, hint: hint, index: index);

  bool has(String label, {bool exact = false}) => findText(label, exact: exact).evaluate().isNotEmpty;

  /// Beklenen metin yoksa 'expectation' bulgusu uretir.
  Future<bool> expect(String label, {bool exact = false, Duration wait = const Duration(seconds: 6)}) async {
    final ok = await pumpUntilFound(tester, findText(label, exact: exact), timeout: wait);
    if (!ok) {
      E2eRuntime.collector.note(kind: 'expectation', message: 'Beklenen metin yok: "$label"');
    }
    return ok;
  }

  Future<bool> tapIconButton(IconData icon, {int index = 0, bool required = true, Finder? within}) =>
      tapIcon(tester, icon, index: index, required: required, within: within);

  Future<int> expandTiles({Future<void> Function(int index)? whileOpen}) =>
      toggleExpansionTiles(tester, whileOpen: whileOpen);

  Future<bool> pick({required String label, required String item}) =>
      selectDropdownItem(tester, label: label, itemText: item);

  Future<void> closeTopOverlay() async {
    await closeTop(tester);
  }

  Future<void> closeAll() => closeOverlays(tester);

  int count(String label, {bool exact = false}) => findText(label, exact: exact).evaluate().length;

  /// Metin ekranda OLMAMALI (ornek: arama sonrasi elenen kayit); varsa 'expectation' bulgusu.
  Future<bool> expectAbsent(String label, {bool exact = false}) async {
    await settle(tester, min: const Duration(milliseconds: 300), max: const Duration(seconds: 3));
    final present = findText(label, exact: exact).evaluate().isNotEmpty;
    if (present) {
      E2eRuntime.collector.note(kind: 'expectation', message: 'Olmamasi gereken metin gorunuyor: "$label"');
    }
    return !present;
  }

  /// Sayfayi (veya [within]) sonuna kaydirip goruntuler, sonra basa doner.
  Future<void> shotAtEnd(String suffix, {Finder? within}) async {
    await scrollAllTheWay(tester, within: within, backToTop: false);
    await scrollPageToEnd(tester, within: within);
    await shot(suffix);
    await scrollToTop(tester, within: within);
  }

  /// PopupMenuButton'u (Icons.more_vert) acip [item] ogesini secer.
  Future<bool> popupMenu(String item, {int index = 0}) async {
    var opened = await tapIcon(tester, Icons.more_vert_rounded, index: index, required: false);
    if (!opened) opened = await tapIcon(tester, Icons.more_vert, index: index, required: false);
    if (!opened) return false;
    final entry = findText(item);
    if (!await pumpUntilFound(tester, entry, timeout: const Duration(seconds: 3))) {
      await closeOverlays(tester);
      return false;
    }
    await pumpFor(tester, const Duration(milliseconds: 450)); // acilis animasyonu bitsin
    return tapFinder(tester, entry.last, description: 'menu ogesi "$item"');
  }

  Future<void> shot(String suffix) async {
    final path = session.shotPath(result.index, '${result.name}_${_safeName(suffix)}');
    final saved = await saveScreenshot(tester, path);
    if (saved != null) E2eRuntime.act('ekran goruntusu: $suffix');
  }

  Future<void> settleUi({Duration min = const Duration(milliseconds: 500)}) => settle(tester, min: min);

  Future<void> scrollEnd({Finder? within}) async {
    await scrollAllTheWay(tester, within: within);
  }

  /// [opener] metnine dokunup acilan diyalog/alt sayfayi tarar ve kapatir.
  /// Donus: diyalog gercekten acildiysa true.
  Future<bool> openAndClose(
    String opener, {
    String? shotName,
    List<String> expectTexts = const <String>[],
    bool exact = false,
    int index = 0,
    Future<void> Function()? whileOpen,
    Finder? within,
    bool required = true,
  }) {
    return openByAndClose(
      () => tapText(tester, opener, exact: exact, index: index, within: within, required: required),
      name: shotName ?? opener,
      expectTexts: expectTexts,
      whileOpen: whileOpen,
    );
  }

  /// [trigger] (dokunma/menu) ile acilan diyalog/alt sayfayi tarar ve kapatir.
  /// Acilip acilmadigi ve yalniz bu tetikleyicinin actigi katmanlarin kapatilmasi, gorunen metinlerin
  /// parmak izi (yeni gelen / kaybolan metinler) ile izlenir (ic ice diyalog/sayfa destekli).
  Future<bool> openByAndClose(
    Future<bool> Function() trigger, {
    required String name,
    List<String> expectTexts = const <String>[],
    Future<void> Function()? whileOpen,
  }) async {
    final nav = _rootNavigator(tester);
    final before = nav?.canPop() ?? false;
    final preTexts = _stableTexts();
    final tapped = await trigger();
    if (!tapped) return false;
    await settle(tester, min: const Duration(milliseconds: 700), max: const Duration(seconds: 5));
    final nav2 = _rootNavigator(tester);
    final newTexts = _stableTexts().difference(preTexts);
    final opened = (!before && (nav2?.canPop() ?? false)) || newTexts.length >= 2;
    if (!opened) {
      E2eRuntime.skip('"$name" diyalog/sayfa acmadi');
      return false;
    }
    for (final t in expectTexts) {
      await expect(t);
    }
    scanSuspiciousText();
    await shot(name);
    final overlay = hasOverlay() ? _topOverlay : null;
    await scrollAllTheWay(tester, within: overlay);
    if (overlay != null && _hasScrollExtent(overlay)) {
      await scrollPageToEnd(tester, within: overlay);
      await shot('${name}_sonu');
      await scrollToTop(tester, within: overlay);
    }
    if (whileOpen != null) await whileOpen();
    // Yalniz bu tetikleyicinin actigi katmani kapat: yeni metinlerin cogu kaybolana kadar (en cok 3 kez).
    for (var i = 0; i < 3; i++) {
      await closeTop(tester);
      await settle(tester, min: const Duration(milliseconds: 300), max: const Duration(seconds: 3));
      final now = _stableTexts();
      final remaining = newTexts.where(now.contains).length;
      if (newTexts.isEmpty || remaining <= newTexts.length * 0.2) break;
    }
    return true;
  }

  /// Saat/sayac gibi her saniye degisen metinler haric, gorunen metinlerin kumesi.
  Set<String> _stableTexts() {
    final clock = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$');
    return visibleTexts().where((t) => !clock.hasMatch(t.trim())).toSet();
  }

  bool _hasScrollExtent(Finder scope) {
    final inner = find.descendant(of: scope, matching: find.byType(Scrollable));
    return _verticalScrollables(inner).any((s) => s.position.maxScrollExtent > 0.5);
  }
}

/// Bir test dosyasinin E2E oturumu (rapor + toplayici + gorunum yonetimi).
class E2eSession {
  E2eSession._(this.tester, this.suite) : report = E2eReport(suite: suite);

  final WidgetTester tester;
  final String suite;
  final E2eReport report;

  E2eScenarioResult? scenario;
  E2eCombo? combo;
  String userKey = '';
  String mode = '';
  int _screenIndex = 0;
  DateTime _scenarioStart = DateTime.now();

  static Future<E2eSession> begin(WidgetTester tester, {required String suite}) async {
    final binding = tester.binding;
    if (binding is LiveTestWidgetsFlutterBinding) {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    }
    E2eEnv.assertLocalApi();
    final session = E2eSession._(tester, suite);
    E2eRuntime.collector.install(platformDispatcher: tester.platformDispatcher);
    WidgetsBinding.instance.addObserver(_lifecycleLogger);
    _hookFrameClock(tester);
    print('E2E= suite=$suite run=${E2eEnv.runName} out=${E2eEnv.runDir} api=${E2eEnv.appApiBase}');
    return session;
  }

  String shotPath(int index, String screenName) {
    final c = combo;
    final tag = c == null ? 'default' : c.id;
    final nn = index.toString().padLeft(2, '0');
    final dir = '${E2eEnv.runDir}/$userKey'.replaceAll(r'\', '/');
    final m = mode.isEmpty ? '' : '${mode}_';
    return '$dir/${nn}_${_safeName(screenName)}__$m$tag.png';
  }

  /// Gorunum presetini + yazi olcegini uygular.
  Future<void> applyCombo(E2eCombo c) async {
    combo = c;
    tester.view.physicalSize = c.preset.physicalSize;
    tester.view.devicePixelRatio = c.preset.devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = c.textScale;
    await pumpFor(tester, const Duration(milliseconds: 500));
  }

  void resetView() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  }

  /// Bir (kullanici x kombinasyon) senaryosu: ekranlarin hepsini gezer. Oturum ACIK olmalidir.
  Future<E2eScenarioResult> runScenario({
    required E2eUser user,
    required E2eCombo combination,
    required List<E2eScreenSpec> screens,
    String scenarioMode = '',
  }) async {
    userKey = user.key;
    mode = scenarioMode;
    await applyCombo(combination);
    final sc = report.beginScenario(
      userKey: user.key,
      role: user.role,
      preset: combination.preset.id,
      textScale: combination.textScale,
      mode: scenarioMode,
    );
    scenario = sc;
    _screenIndex = 0;
    _scenarioStart = DateTime.now();
    print('E2E= senaryo: ${user.key}${scenarioMode.isEmpty ? '' : ' [$scenarioMode]'} ${combination.id}');
    final only = E2eEnv.onlyScreens;
    for (final spec in screens) {
      if (only.isNotEmpty && !only.contains(spec.name)) continue;
      await walkScreen(sc, spec);
    }
    final leftovers = E2eRuntime.collector.drain();
    sc.global.addAll(leftovers);
    final secs = DateTime.now().difference(_scenarioStart).inSeconds;
    print('E2E= senaryo bitti: ${user.key} ${combination.id} ekran=${sc.screens.length} hata=${sc.errorCount} sure=${secs}s');
    report.write();
    return sc;
  }

  /// Tek ekrani gez: menuye gir, bekle, sonuna kadar kaydir, etkilesim yap, goruntule.
  Future<E2eScreenResult> walkScreen(E2eScenarioResult sc, E2eScreenSpec spec) async {
    final index = ++_screenIndex;
    final result = E2eScreenResult(name: spec.name, index: index);
    sc.screens.add(result);
    E2eRuntime.collector.beginScreen(spec.name);
    E2eRuntime.screen = result;
    final started = DateTime.now();
    // Onceki adimlardan kalan bulgular bu ekrana karismasin.
    sc.global.addAll(E2eRuntime.collector.drain());
    E2eRuntime.collector.beginScreen(spec.name);
    try {
      final navigated = await openDrawerAndTap(tester, spec.menuLabel);
      if (!navigated) {
        result.status = 'missing';
        return result;
      }
      await settle(tester, min: const Duration(milliseconds: 900), max: const Duration(seconds: 9));
      if (spec.opensDialogInstead) {
        await pumpUntilFound(tester, find.byType(Dialog), timeout: const Duration(seconds: 4));
      }
      if (spec.titleText != null) {
        final inTitle = await pumpUntilFound(
          tester,
          findText(spec.titleText!, exact: true),
          timeout: const Duration(seconds: 5),
        );
        if (!inTitle) {
          E2eRuntime.collector.note(
            kind: 'navigation',
            message: 'Menu sonrasi baslik gorunmedi: "${spec.titleText}"',
          );
        }
      }
      final ctx = E2eScreenContext(this, tester, result);
      final overlayScope = spec.opensDialogInstead && hasOverlay() ? _topOverlay : null;
      if (_hasSpinner()) {
        // Yukleme gostergesi uzun sure donuyorsa (takili ekran) bir kez daha bekle, hala varsa bildir.
        await pumpFor(tester, const Duration(seconds: 6));
        if (_hasSpinner()) {
          E2eRuntime.collector.note(
            kind: 'loading-stuck',
            message: 'Ekran yuklenirken ilerleme gostergesi 15 sn sonra hala donuyor',
          );
        }
      }
      scanSuspiciousText();
      for (final t in spec.expectTexts) {
        await ctx.expect(t);
      }
      result.screenshot = await saveScreenshot(tester, shotPath(index, spec.name));
      final scrolled = await scrollAllTheWay(tester, within: overlayScope, backToTop: false);
      if (scrolled > 0) {
        await scrollPageToEnd(tester, within: overlayScope);
        result.screenshotEnd = await saveScreenshot(tester, shotPath(index, '${spec.name}_sonu'));
      }
      await scrollToTop(tester, within: overlayScope);
      if (!spec.opensDialogInstead) {
        // Kural 7: AppBar "Yenile" her ekranda hatasiz calismali.
        await tapTooltip(tester, 'Yenile', required: false, settleAfter: const Duration(milliseconds: 900));
      }
      if (spec.interactions != null) {
        try {
          await spec.interactions!(ctx);
        } catch (e, st) {
          E2eRuntime.collector.add(E2eFinding(
            kind: 'exception',
            message: 'Etkilesim betigi hatasi: $e',
            screen: spec.name,
            stack: st.toString().split('\n').take(3).toList(),
          ));
        }
      }
      scanSuspiciousText();
      await closeOverlays(tester);
    } catch (e, st) {
      result.status = 'error';
      E2eRuntime.collector.add(E2eFinding(
        kind: 'exception',
        message: 'Ekran gezintisi hatasi: $e',
        screen: spec.name,
        stack: st.toString().split('\n').take(3).toList(),
      ));
      try {
        await closeOverlays(tester);
      } catch (_) {}
    } finally {
      result.findings.addAll(E2eRuntime.collector.drain());
      result.elapsedMs = DateTime.now().difference(started).inMilliseconds;
      E2eRuntime.screen = null;
      report.write();
      print('E2E= ekran ${spec.name}: ${result.status}, hata=${result.findings.length}, ${result.elapsedMs}ms');
    }
    return result;
  }

  /// Oturumu bitirir: toplayiciyi kaldirir, gorunumu sifirlar, raporu yazar ve ozet basar.
  Future<void> end() async {
    final leftovers = E2eRuntime.collector.drain();
    if (leftovers.isNotEmpty && scenario != null) scenario!.global.addAll(leftovers);
    E2eRuntime.collector.uninstall();
    WidgetsBinding.instance.removeObserver(_lifecycleLogger);
    resetView();
    report.write();
    var screens = 0;
    var errors = 0;
    var overflow = 0;
    for (final s in report.scenarios) {
      errors += s.errorCount;
      for (final sc in s.screens) {
        if (sc.status != 'missing') screens += 1;
        overflow += sc.findings.where((f) => f.kind == 'overflow').length;
      }
    }
    print('E2E= OZET suite=$suite senaryo=${report.scenarios.length} ekran=$screens hata=$errors tasma=$overflow rapor=${E2eEnv.runDir}${Platform.pathSeparator}report.json');
  }
}

/// Bir test govdesini calistirir: yakalanmamis async hatalar toplayiciya gider, test COKMEZ; govde
/// hatasi (giris basarisiz vb.) rapora yazilip sonda testi basarisiz kilar.
Future<void> runE2e(
  WidgetTester tester, {
  required String suite,
  required Future<void> Function(E2eSession session) body,
}) async {
  final session = await E2eSession.begin(tester, suite: suite);
  final done = Completer<void>();
  Object? fatalError;
  StackTrace? fatalStack;
  runZonedGuarded<void>(() async {
    // Kare geri cagrilari (build/initState/Timer) de bu bolgede calissin: aksi halde uygulamadaki
    // yakalanmamis asenkron hatalar flutter_test'in test bolgesine duser ve testi sonlandirir.
    final dispatcher = tester.platformDispatcher;
    final zone = Zone.current;
    final originalBegin = dispatcher.onBeginFrame;
    final originalDraw = dispatcher.onDrawFrame;
    if (originalBegin != null) {
      dispatcher.onBeginFrame = (Duration t) => zone.runUnary<void, Duration>(originalBegin, t);
    }
    if (originalDraw != null) {
      dispatcher.onDrawFrame = () => zone.run<void>(originalDraw);
    }
    try {
      await body(session);
    } catch (e, st) {
      fatalError = e;
      fatalStack = st;
    } finally {
      dispatcher.onBeginFrame = originalBegin;
      dispatcher.onDrawFrame = originalDraw;
      if (!done.isCompleted) done.complete();
    }
  }, (error, stack) {
    E2eRuntime.collector.recordZoneError(error, stack);
  });
  await done.future;
  if (fatalError != null) {
    session.scenario?.fatal = '$fatalError';
    print('E2E! FATAL: $fatalError\n${fatalStack.toString().split('\n').take(6).join('\n')}');
  }
  await session.end();
  if (fatalError != null) {
    throw TestFailure('E2E govdesi basarisiz: $fatalError');
  }
}

/// Test dosyalarinin main() basinda cagrilir.
IntegrationTestWidgetsFlutterBinding initE2eBinding() {
  return IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}
