// E2E bulgu toplayici ve JSON rapor yazici.
//
// - E2eCollector: FlutterError.onError / PlatformDispatcher.onError / bolge (zone) hatalarini
//   gecici olarak yakalar; test ilk hatada COKMEZ, bulgular ekrana atfedilip sonda raporlanir.
// - E2eReport: <out>/<kosu>/report.json (ayni kosuya birden fazla test dosyasi yazarsa birlestirir).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'e2e_env.dart';

/// Tek bir bulgu (taşma, istisna, platform eklentisi eksikligi, gezinme hatasi...).
class E2eFinding {
  E2eFinding({
    required this.kind,
    required this.message,
    required this.screen,
    this.location,
    this.widget,
    this.stack = const <String>[],
    this.count = 1,
  });

  /// overflow | exception | rendering | assertion | missing-plugin | async-uncaught | navigation |
  /// tap-missing | tap-not-hittable | policy | expectation | note
  final String kind;
  final String message;
  final String screen;
  final String? location; // lib/...dart:satir
  final String? widget; // "hatayi uretti" diye raporlanan widget
  final List<String> stack; // ilk 3 satir
  int count;

  String get dedupeKey => '$kind|$screen|${message.split('\n').first}|${widget ?? ''}';

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'screen': screen,
        'message': message,
        if (location != null) 'location': location,
        if (widget != null) 'widget': widget,
        if (stack.isNotEmpty) 'stack': stack,
        'count': count,
      };
}

/// Bir ekranin gezinti sonucu.
class E2eScreenResult {
  E2eScreenResult({required this.name, required this.index});

  final String name;
  final int index;
  String? screenshot;
  String? screenshotEnd;
  String status = 'ok'; // ok | missing | error
  final List<String> actions = <String>[];
  final List<String> skipped = <String>[];
  final List<E2eFinding> findings = <E2eFinding>[];
  int elapsedMs = 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'index': index,
        'status': status,
        'elapsed_ms': elapsedMs,
        if (screenshot != null) 'screenshot': screenshot,
        if (screenshotEnd != null) 'screenshot_end': screenshotEnd,
        'actions': actions,
        if (skipped.isNotEmpty) 'skipped': skipped,
        'errors': findings.map((f) => f.toJson()).toList(),
      };
}

/// Bir (kullanici x gorunum x yazi olcegi) senaryosunun sonucu.
class E2eScenarioResult {
  E2eScenarioResult({
    required this.suite,
    required this.userKey,
    required this.role,
    required this.preset,
    required this.textScale,
    this.mode = '',
  });

  final String suite;
  final String userKey;
  final String role;
  final String preset;
  final double textScale;

  /// Ayni kullanicinin farkli modlari (ornek: yonetici paneli / sakin modu).
  final String mode;
  final List<E2eScreenResult> screens = <E2eScreenResult>[];
  final List<E2eFinding> global = <E2eFinding>[];
  String? fatal;

  String get id => '$suite|$userKey|$mode|$preset|$textScale';

  int get errorCount =>
      screens.fold<int>(0, (a, s) => a + s.findings.length) + global.length + (fatal == null ? 0 : 1);

  Map<String, Object?> toJson() => <String, Object?>{
        'suite': suite,
        'user': userKey,
        if (mode.isNotEmpty) 'mode': mode,
        'role': role,
        'preset': preset,
        'text_scale': textScale,
        'screens_visited': screens.where((s) => s.status != 'missing').length,
        'error_count': errorCount,
        if (fatal != null) 'fatal': fatal,
        'screens': screens.map((s) => s.toJson()).toList(),
        if (global.isNotEmpty) 'global_errors': global.map((f) => f.toJson()).toList(),
      };
}

/// Hata toplayici. Kurulum: [install]; temizlik: [uninstall].
class E2eCollector {
  FlutterExceptionHandler? _previousFlutterOnError;
  ui.ErrorCallback? _previousPlatformOnError;
  ui.PlatformDispatcher? _platformHook;
  bool _installed = false;

  String currentScreen = 'boot';
  final Map<String, E2eFinding> _byKey = <String, E2eFinding>{};
  final List<E2eFinding> _ordered = <E2eFinding>[];

  /// FlutterError.onError'i degistirir. [platformDispatcher] verilirse onError'i de yakalar.
  void install({ui.PlatformDispatcher? platformDispatcher}) {
    if (_installed) return;
    _installed = true;
    _previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = _onFlutterError;
    if (platformDispatcher != null) {
      _platformHook = platformDispatcher;
      _previousPlatformOnError = platformDispatcher.onError;
      platformDispatcher.onError = (Object error, StackTrace stack) {
        recordZoneError(error, stack, label: 'platform-dispatcher');
        return true;
      };
    }
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    FlutterError.onError = _previousFlutterOnError;
    if (_platformHook != null) {
      _platformHook!.onError = _previousPlatformOnError;
      _platformHook = null;
    }
  }

  /// Ekran gecisinde cagrilir: sonraki hatalar bu ekrana atfedilir.
  void beginScreen(String name) {
    currentScreen = name;
  }

  /// Su ana dek toplanan bulgulari verir ve sifirlar.
  List<E2eFinding> drain() {
    final out = List<E2eFinding>.from(_ordered);
    _ordered.clear();
    _byKey.clear();
    return out;
  }

  int get pendingCount => _ordered.length;

  void add(E2eFinding finding) {
    final existing = _byKey[finding.dedupeKey];
    if (existing != null) {
      existing.count += 1;
      return;
    }
    _byKey[finding.dedupeKey] = finding;
    _ordered.add(finding);
    // ignore: avoid_print
    print('E2E! [${finding.screen}] ${finding.kind}: ${_oneLine(finding.message)}');
  }

  void note({required String kind, required String message, String? screen}) {
    add(E2eFinding(kind: kind, message: message, screen: screen ?? currentScreen));
  }

  void _onFlutterError(FlutterErrorDetails details) {
    try {
      add(_fromDetails(details));
    } catch (e) {
      add(E2eFinding(
        kind: 'exception',
        message: 'Hata toplayici cozemedi: ${details.exceptionAsString()} ($e)',
        screen: currentScreen,
      ));
    }
  }

  void recordZoneError(Object error, StackTrace stack, {String label = 'async-uncaught'}) {
    final kind = error is MissingPluginException ? 'missing-plugin' : 'async-uncaught';
    add(E2eFinding(
      kind: kind,
      message: '[$label] $error',
      screen: currentScreen,
      location: _locationOf(stack.toString()),
      stack: _stackLines(stack),
    ));
  }

  E2eFinding _fromDetails(FlutterErrorDetails d) {
    final text = d.toString();
    final exception = d.exceptionAsString();
    final String kind;
    if (exception.contains('overflowed by') || text.contains('overflowed by')) {
      kind = 'overflow';
    } else if (d.exception is MissingPluginException) {
      kind = 'missing-plugin';
    } else if (d.exception is AssertionError) {
      kind = 'assertion';
    } else if ((d.library ?? '').contains('rendering')) {
      kind = 'rendering';
    } else {
      kind = 'exception';
    }

    String summary;
    try {
      summary = d.summary.toString();
    } catch (_) {
      summary = exception.split('\n').first;
    }
    final contextText = d.context?.toDescription() ?? '';
    final lib = d.library ?? '';
    final prefix = [lib, contextText].where((e) => e.isNotEmpty).join(' / ');
    final message = '${prefix.isEmpty ? '' : '[$prefix] '}${_clip(summary.isEmpty ? exception : summary, 500)}';

    String? widget;
    final w = RegExp(r'The relevant error-causing widget was:\s*\n\s*(.+)').firstMatch(text);
    if (w != null) widget = _clip(w.group(1)!.trim(), 300);

    final location = _locationOf(widget ?? '') ?? _locationOf(text);
    return E2eFinding(
      kind: kind,
      message: message,
      screen: currentScreen,
      location: location,
      widget: widget,
      stack: d.stack == null ? const <String>[] : _stackLines(d.stack!),
    );
  }

  static String? _locationOf(String text) {
    final m = RegExp(r'(lib/[\w/.\-]+\.dart:\d+(?::\d+)?)').firstMatch(text.replaceAll('\\', '/'));
    return m?.group(1);
  }

  static List<String> _stackLines(StackTrace stack) {
    final lines = stack
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('<asynchronous'))
        .toList();
    // Once uygulama (package:site_kapi_kontrol) satirlari, sonra genel ilk satirlar.
    final app = lines.where((l) => l.contains('package:site_kapi_kontrol')).toList();
    final chosen = <String>[...app, ...lines.where((l) => !app.contains(l))];
    return chosen.take(3).map((l) => _clip(l, 220)).toList();
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}...';

  static String _oneLine(String s) => _clip(s.replaceAll(RegExp(r'\s+'), ' '), 220);
}

/// Tum kosunun JSON raporu.
class E2eReport {
  E2eReport({required this.suite});

  final String suite;
  final List<E2eScenarioResult> scenarios = <E2eScenarioResult>[];
  final DateTime startedAt = DateTime.now();

  E2eScenarioResult beginScenario({
    required String userKey,
    required String role,
    required String preset,
    required double textScale,
    String mode = '',
  }) {
    final s = E2eScenarioResult(
      suite: suite,
      userKey: userKey,
      role: role,
      preset: preset,
      textScale: textScale,
      mode: mode,
    );
    scenarios.add(s);
    return s;
  }

  File get _file => File('${E2eEnv.runDir}/report.json');

  /// Mevcut report.json ile (baska test dosyalarindan) birlestirip yazar.
  void write() {
    try {
      Directory(E2eEnv.runDir).createSync(recursive: true);
      final existing = <Map<String, Object?>>[];
      if (_file.existsSync()) {
        try {
          final prev = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
          for (final s in (prev['scenarios'] as List? ?? const [])) {
            final m = Map<String, Object?>.from(s as Map);
            final mine = scenarios.any(
              (x) =>
                  x.suite == m['suite'] &&
                  x.userKey == m['user'] &&
                  x.mode == (m['mode'] ?? '') &&
                  x.preset == m['preset'] &&
                  x.textScale == m['text_scale'],
            );
            if (!mine) existing.add(m);
          }
        } catch (_) {}
      }
      final all = <Map<String, Object?>>[...existing, ...scenarios.map((s) => s.toJson())];
      var total = 0;
      var overflows = 0;
      final byKind = <String, int>{};
      for (final s in all) {
        for (final screen in (s['screens'] as List? ?? const [])) {
          for (final e in ((screen as Map)['errors'] as List? ?? const [])) {
            total += 1;
            final kind = (e as Map)['kind'] as String? ?? '?';
            byKind[kind] = (byKind[kind] ?? 0) + 1;
            if (kind == 'overflow') overflows += 1;
          }
        }
        for (final e in (s['global_errors'] as List? ?? const [])) {
          total += 1;
          final kind = (e as Map)['kind'] as String? ?? '?';
          byKind[kind] = (byKind[kind] ?? 0) + 1;
          if (kind == 'overflow') overflows += 1;
        }
        if (s['fatal'] != null) {
          total += 1;
          byKind['fatal'] = (byKind['fatal'] ?? 0) + 1;
        }
      }
      final doc = <String, Object?>{
        'run': E2eEnv.runName,
        'updated_at': DateTime.now().toIso8601String(),
        'platform': Platform.operatingSystem,
        'api_base': E2eEnv.appApiBase,
        'summary': <String, Object?>{
          'scenarios': all.length,
          'errors_total': total,
          'overflows': overflows,
          'by_kind': byKind,
        },
        'scenarios': all,
      };
      _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(doc));
    } catch (e) {
      // ignore: avoid_print
      print('E2E! rapor yazilamadi: $e');
    }
  }
}
