// ModuleArt testleri: sözleşme (tür sırası, kurucu, imza), her tür x boyut x tema çizimi, kontrast
// (WCAG 1.4.11, ana ton ve vurgu üstü ayrıntı >= 3:1), durum anlamı yok (durum renkleri / "açık kilit" süs değildir),
// erişilebilirlik (dışlanır), durağanlık, yeniden boyama ve rozet sınırı.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

const List<double> _sizes = <double>[32, 64, 96];
const double _graphicMin = 3.0; // WCAG 1.4.11: anlamlı grafik nesne >= 3:1

/// WCAG 2.x kontrast oranı. İki renk de opak olmalı.
double _contrast(Color a, Color b) {
  expect(a.a, greaterThan(0.999), reason: 'ön plan opak olmalı');
  expect(b.a, greaterThan(0.999), reason: 'arka plan opak olmalı');
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

ModuleArtColors _colors(ModuleArtKind kind, bool dark) =>
    ModuleArtColors.resolve(kind, dark ? AppPalette.dark : AppPalette.light);

Widget _all(double size) => Wrap(
  children: <Widget>[
    for (final k in ModuleArtKind.values)
      Padding(
        padding: const EdgeInsets.all(2),
        child: ModuleArt(kind: k, size: size),
      ),
  ],
);

/// [kind]'ı [s] x [s] px'e boyar; RGBA baytları döner.
Future<Uint8List> _raster(ModuleArtKind kind, bool dark, int s) async {
  final recorder = ui.PictureRecorder();
  ModuleArtPainter(
    kind: kind,
    colors: _colors(kind, dark),
  ).paint(Canvas(recorder), Size.square(s.toDouble()));
  final image = await recorder.endRecording().toImage(s, s);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Vitrinin durum noktası renkleri (işveren tasarım kuralı): zümrüt, kehribar, mercan. Yalnız gerçek durumu gösterir.
const List<Color> _statusColors = <Color>[
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFE11D48),
];

List<int> _rgb(Color c) => <int>[
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
];

/// Yeşil baskın (durum yeşili ailesi) piksel.
bool _greenish(int r, int g, int b) => g > r + 40 && g > b + 20;

/// Sıcak (mercan / kehribar ailesi) piksel.
bool _warm(int r, int g, int b) => r > b + 60 && r > g + 30;

/// 48 birimlik ızgaradaki (ux, uy) noktasının [s] px'lik boyamadaki rengi (opak olmalı).
List<int> _pixelAt(Uint8List px, int s, double ux, double uy) {
  final x = (ux * s / 48).floor();
  final y = (uy * s / 48).floor();
  final i = (y * s + x) * 4;
  expect(px[i + 3], 255, reason: '($ux, $uy) opak olmalı');
  return <int>[px[i], px[i + 1], px[i + 2]];
}

void _expectNear(List<int> actual, Color expected, String what) {
  final want = _rgb(expected);
  for (var i = 0; i < 3; i++) {
    expect(
      (actual[i] - want[i]).abs(),
      lessThanOrEqualTo(6),
      reason: '$what: $actual, beklenen $want',
    );
  }
}

void main() {
  group('sözleşme', () {
    test('ModuleArtKind değerleri ve sırası değişmez', () {
      expect(ModuleArtKind.values.map((k) => k.name).toList(), <String>[
        'door',
        'accessCards',
        'people',
        'announcements',
        'finance',
        'myDebt',
        'documents',
        'workTracking',
        'reservation',
        'survey',
        'visitor',
        'contracts',
        'decisions',
        'sites',
        'modules',
        'devices',
        'users',
        'reports',
        'settings',
        'help',
        'generic',
      ]);
    });

    test('moduleArtAccent: her tür için opak renk', () {
      for (final k in ModuleArtKind.values) {
        expect(moduleArtAccent(k).a, 1.0, reason: k.name);
      }
    });

    testWidgets('varsayılan boyut 64; size < 32 iddiayı patlatır', (t) async {
      await t.pumpWidget(
        harnessApp(const Center(child: ModuleArt(kind: ModuleArtKind.door))),
      );
      expect(t.getSize(find.byType(ModuleArt)), const Size(64, 64));
      expect(
        () => ModuleArt(kind: ModuleArtKind.door, size: 31.9),
        throwsAssertionError,
      );
    });

    testWidgets('boyut sabit dp: yazı ölçeğinden etkilenmez', (t) async {
      for (final scale in <double>[1.0, 2.0]) {
        await t.pumpWidget(
          harnessApp(
            const Center(
              child: ModuleArt(kind: ModuleArtKind.finance, size: 96),
            ),
            scale: scale,
          ),
        );
        expect(t.getSize(find.byType(ModuleArt)), const Size(96, 96));
      }
    });
  });

  group('çizim', () {
    for (final dark in <bool>[false, true]) {
      testWidgets(
        'her tür x (32, 64, 96) hatasız çizilir (${dark ? 'koyu' : 'açık'})',
        (t) async {
          for (final size in _sizes) {
            await t.pumpWidget(
              harnessApp(SingleChildScrollView(child: _all(size)), dark: dark),
            );
            await t.pump();
            expect(t.takeException(), isNull, reason: 'boyut $size');
            expect(
              find.byType(ModuleArt),
              findsNWidgets(ModuleArtKind.values.length),
            );
            for (final e in t.widgetList<ModuleArt>(find.byType(ModuleArt))) {
              expect(e.size, size);
            }
            for (final el in t.elementList(find.byType(ModuleArt))) {
              expect(el.size, Size(size, size));
            }
          }
        },
      );
    }

    testWidgets('tema değişince renkler değişir, aynı temada aynı kalır', (
      t,
    ) async {
      Future<ModuleArtPainter> painterIn(bool dark) async {
        await t.pumpWidget(
          harnessApp(
            const Center(child: ModuleArt(kind: ModuleArtKind.people)),
            dark: dark,
          ),
        );
        await t.pumpAndSettle(); // AnimatedTheme geçişi bitsin
        final paint = t.widget<CustomPaint>(
          find.descendant(
            of: find.byType(ModuleArt),
            matching: find.byType(CustomPaint),
          ),
        );
        return paint.painter! as ModuleArtPainter;
      }

      final light1 = await painterIn(false);
      final dark1 = await painterIn(true);
      final light2 = await painterIn(false);
      expect(light1.colors, light2.colors);
      expect(light1.colors, isNot(dark1.colors));
      expect(light1.shouldRepaint(light2), isFalse);
      expect(light1.shouldRepaint(dark1), isTrue);
    });

    test('shouldRepaint yalnız tür ya da renk değişince true', () {
      final a = ModuleArtPainter(
        kind: ModuleArtKind.door,
        colors: _colors(ModuleArtKind.door, false),
      );
      final same = ModuleArtPainter(
        kind: ModuleArtKind.door,
        colors: _colors(ModuleArtKind.door, false),
      );
      final otherKind = ModuleArtPainter(
        kind: ModuleArtKind.finance,
        colors: _colors(ModuleArtKind.door, false),
      );
      final otherColors = ModuleArtPainter(
        kind: ModuleArtKind.door,
        colors: _colors(ModuleArtKind.door, true),
      );
      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(otherKind), isTrue);
      expect(a.shouldRepaint(otherColors), isTrue);
    });

    testWidgets('durağan: animasyon/ticker yok', (t) async {
      await t.pumpWidget(harnessApp(SingleChildScrollView(child: _all(64))));
      await t.pumpAndSettle(); // sonsuz animasyon olsaydı zaman aşımı verirdi
      expect(t.binding.hasScheduledFrame, isFalse);
    });
  });

  group('piksel', () {
    for (final dark in <bool>[false, true]) {
      final theme = dark ? 'koyu' : 'açık';

      testWidgets('rozet köşeleri saydam, figür rozetin içinde kalır ($theme)', (
        t,
      ) async {
        await t.runAsync(() async {
          for (final k in ModuleArtKind.values) {
            for (final s in <int>[64, 96]) {
              final px = await _raster(k, dark, s);
              int a(int x, int y) => px[(y * s + x) * 4 + 3];
              bool inkish(int x, int y) {
                final i = (y * s + x) * 4;
                final r = px[i], g = px[i + 1], b = px[i + 2];
                return dark
                    ? (r > 190 && g > 190 && b > 190)
                    : (r < 90 && g < 90 && b < 90);
              }

              // Dört köşe saydam (yuvarlak kare), orta opak.
              for (final (x, y) in <(int, int)>[
                (0, 0),
                (s - 1, 0),
                (0, s - 1),
                (s - 1, s - 1),
              ]) {
                expect(a(x, y), 0, reason: '${k.name} $s köşe ($x,$y)');
              }
              expect(a(s ~/ 2, s ~/ 2), 255, reason: '${k.name} $s orta');

              // Dış %8'lik bantta ana ton (ink) piksel yok: figür rozetin içinde.
              final m = (s * 0.08).round();
              var leaked = 0;
              var ink = 0;
              for (var y = 0; y < s; y++) {
                for (var x = 0; x < s; x++) {
                  if (a(x, y) != 255) continue;
                  final inMargin = x < m || x >= s - m || y < m || y >= s - m;
                  if (inkish(x, y)) {
                    ink++;
                    if (inMargin) leaked++;
                  }
                }
              }
              expect(leaked, 0, reason: '${k.name} $s: figür kenara taşıyor');
              // Figür gerçekten çizilmiş (boş rozet değil).
              expect(
                ink,
                greaterThan(s ~/ 2),
                reason: '${k.name} $s: figür yok',
              );
            }
          }
        });
      });

      testWidgets('her tür birbirinden farklı çizilir ($theme)', (t) async {
        await t.runAsync(() async {
          final seen = <int, ModuleArtKind>{};
          for (final k in ModuleArtKind.values) {
            final px = await _raster(k, dark, 64);
            final h = Object.hashAll(px);
            expect(
              seen.containsKey(h),
              isFalse,
              reason: '${k.name} ile ${seen[h]?.name} aynı görünüyor',
            );
            seen[h] = k;
          }
          expect(seen.length, ModuleArtKind.values.length);
        });
      });
    }
  });

  group('kontrast (WCAG 1.4.11)', () {
    for (final dark in <bool>[false, true]) {
      final theme = dark ? 'koyu' : 'açık';

      test(
        'ana ton (ink) rozet zeminine ve figür yüzeylerine >= 3:1 ($theme)',
        () {
          for (final k in ModuleArtKind.values) {
            final c = _colors(k, dark);
            final grounds = <String, Color>{
              'rozet sol-üst': c.badgeTop,
              'rozet sağ-alt': c.badgeBottom,
              'kağıt': c.paper,
              'ikinci ton': c.wash,
              'ikinci ton (orta)': c.accentSoft,
            };
            grounds.forEach((name, bg) {
              expect(
                _contrast(c.ink, bg),
                greaterThanOrEqualTo(_graphicMin),
                reason: '${k.name} ink / $name',
              );
            });
          }
        },
      );

      test('vurgu rengi rozet zeminine, rozet halkasına ve kağıda >= 3:1 ($theme)', () {
        for (final k in ModuleArtKind.values) {
          final c = _colors(k, dark);
          for (final (name, bg) in <(String, Color)>[
            ('rozet sol-üst', c.badgeTop),
            ('rozet sağ-alt', c.badgeBottom),
            ('rozet halkası', c.ring),
            ('kağıt', c.paper),
          ]) {
            expect(
              _contrast(c.accent, bg),
              greaterThanOrEqualTo(_graphicMin),
              reason: '${k.name} accent / $name',
            );
          }
        }
      });

      test('vurgu üstündeki ayrıntı (kapı kilidi, onay, "+") vurguya >= 3:1 ($theme)', () {
        for (final k in ModuleArtKind.values) {
          final c = _colors(k, dark);
          expect(
            _contrast(c.onAccent, c.accent),
            greaterThanOrEqualTo(_graphicMin),
            reason: '${k.name} onAccent / accent',
          );
        }
      });
    }

    test('ayrıntı rengi: açıkta beyaz, koyuda rozetin koyu zemini (sabit beyaz değil)', () {
      for (final k in ModuleArtKind.values) {
        expect(_colors(k, false).onAccent, const Color(0xFFFFFFFF), reason: k.name);
        final dark = _colors(k, true);
        expect(dark.onAccent, dark.badgeBottom, reason: k.name);
        expect(dark.onAccent, isNot(const Color(0xFFFFFFFF)), reason: k.name);
      }
    });

    testWidgets('koyu temada saf beyaz ayrıntı yok (kilit, onay, "+" vurgu üstünde okunur)', (t) async {
      await t.runAsync(() async {
        for (final k in ModuleArtKind.values) {
          final px = await _raster(k, true, 96);
          var white = 0;
          for (var i = 0; i < px.length; i += 4) {
            if (px[i + 3] == 255 && px[i] >= 250 && px[i + 1] >= 250 && px[i + 2] >= 250) {
              white++;
            }
          }
          expect(white, 0, reason: '${k.name}: koyu temada sabit beyaz ayrıntı (vurguya ~1,9:1)');
        }
      });
    });

    test('ana ton, açık temada marka lacivertidir', () {
      expect(ModuleArtColors.inkLight, const Color(0xFF0F2A4A));
      for (final k in ModuleArtKind.values) {
        expect(_colors(k, false).ink, ModuleArtColors.inkLight);
        expect(_colors(k, true).ink, ModuleArtColors.inkDark);
      }
    });
  });

  group('durum anlamı yok (durum renkleri ve "açık kilit" süs değildir)', () {
    test('tür vurgusu ve hiçbir renk rolü vitrinin durum rengi değildir (her tür, her tema)', () {
      for (final k in ModuleArtKind.values) {
        expect(_statusColors, isNot(contains(moduleArtAccent(k))), reason: k.name);
        for (final dark in <bool>[false, true]) {
          final c = _colors(k, dark);
          for (final (name, role) in <(String, Color)>[
            ('badgeTop', c.badgeTop),
            ('badgeBottom', c.badgeBottom),
            ('ring', c.ring),
            ('ink', c.ink),
            ('paper', c.paper),
            ('wash', c.wash),
            ('accentSoft', c.accentSoft),
            ('accent', c.accent),
            ('onAccent', c.onAccent),
          ]) {
            expect(
              _statusColors,
              isNot(contains(role)),
              reason: '${k.name} ${dark ? 'koyu' : 'açık'} $name',
            );
          }
        }
      }
    });

    for (final dark in <bool>[false, true]) {
      final theme = dark ? 'koyu' : 'açık';

      // Yeşil ya da sıcak ton yalnız türün KENDİ rengi o aileden ise çizilir (Finans yeşili, Duyuru turuncusu).
      // Kapıdaki yeşil "açık kilit", rezervasyondaki yeşil onay, cihazdaki yeşil ışık ve İş Takibi / Ziyaretçi'deki
      // mercan bu testi kırar.
      testWidgets('durum yeşili / mercan / kehribar süs olarak çizilmez ($theme)', (t) async {
        await t.runAsync(() async {
          for (final k in ModuleArtKind.values) {
            final own = _rgb(moduleArtAccent(k));
            final ownGreen = _greenish(own[0], own[1], own[2]);
            final ownWarm = _warm(own[0], own[1], own[2]);
            final px = await _raster(k, dark, 96);
            var green = 0;
            var warm = 0;
            for (var i = 0; i < px.length; i += 4) {
              if (px[i + 3] != 255) continue;
              if (_greenish(px[i], px[i + 1], px[i + 2])) green++;
              if (_warm(px[i], px[i + 1], px[i + 2])) warm++;
            }
            if (!ownGreen) {
              expect(green, 0, reason: '${k.name}: durum yeşili süs olarak çizilmiş');
            }
            if (!ownWarm) {
              expect(warm, 0, reason: '${k.name}: mercan / kehribar süs olarak çizilmiş');
            }
          }
        });
      });

      testWidgets('kapı: rozet tür vurgusu (mavi), kilit KAPALI (iki bacak da gövdeye iner) ($theme)', (t) async {
        await t.runAsync(() async {
          const s = 96; // 1 birim = 2 px
          final c = _colors(ModuleArtKind.door, dark);
          expect(moduleArtAccent(ModuleArtKind.door), const Color(0xFF2563EB));
          final px = await _raster(ModuleArtKind.door, dark, s);
          _expectNear(_pixelAt(px, s, 34.2, 33.3), c.onAccent, 'kilit gövdesi');
          _expectNear(_pixelAt(px, s, 32.3, 30.3), c.onAccent, 'kilidin sol bacağı');
          // Açık kilitte sağ bacak gövdeye inmiyordu: burada rozet rengi görünürdü.
          _expectNear(_pixelAt(px, s, 35.7, 30.3), c.onAccent, 'kilidin sağ bacağı');
          _expectNear(_pixelAt(px, s, 34.2, 37.2), c.accent, 'rozet (kilit dışı)');
        });
      });

      testWidgets('küçük boyutta (40 dp, hızlı işlem) kapı rozeti yalnız vurgu noktasıdır ($theme)', (t) async {
        await t.runAsync(() async {
          const s = 40; // ayrıntı (< 44 dp) çizilmez
          final c = _colors(ModuleArtKind.door, dark);
          final px = await _raster(ModuleArtKind.door, dark, s);
          _expectNear(_pixelAt(px, s, 34.2, 31.8), c.accent, 'rozet merkezi');
        });
      });
    }
  });

  group('erişilebilirlik', () {
    testWidgets('görsel dekoratif: ExcludeSemantics, anlamsal düğüm üretmez', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        harnessApp(
          Center(
            child: Semantics(
              container: true,
              label: 'Kart',
              child: const ModuleArt(kind: ModuleArtKind.door),
            ),
          ),
        ),
      );
      final exclude = t.widget<ExcludeSemantics>(
        find.descendant(
          of: find.byType(ModuleArt),
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(exclude.excluding, isTrue);
      final paint = t.widget<CustomPaint>(
        find.descendant(
          of: find.byType(ModuleArt),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paint.painter!.semanticsBuilder, isNull);
      // Kartın etiketi görünür; görselin kendi düğümü yok (alt düğüm sayısı 0).
      final node = t.getSemantics(find.bySemanticsLabel('Kart'));
      var children = 0;
      node.visitChildren((_) {
        children++;
        return true;
      });
      expect(children, 0);
      handle.dispose();
    });
  });
}
