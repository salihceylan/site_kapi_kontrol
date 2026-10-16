// Satışa hazırlık / F3: açılış kapısı ekranları (zorunlu güncelleme, bakım, yumuşak uyarı) ve AppGate.
//
// AGENTS.md kural 6: taşma matrisi 320x640 x2,0 ve 360x640 x1,5, açık/koyu tema, ayrıca yatay (640x360).
// Not: widget testleri Ahem yazı tipiyle çalışır (her harf 1 em); satır sarma gerçek cihazdan serttir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/app_config.dart';
import 'package:site_kapi_kontrol/services/app_config_service.dart';
import 'package:site_kapi_kontrol/services/app_gate_state.dart';
import 'package:site_kapi_kontrol/services/app_version.dart';
import 'package:site_kapi_kontrol/services/stored_session_probe.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/app_gate_view.dart';
import 'package:site_kapi_kontrol/ui/views/maintenance_view.dart';
import 'package:site_kapi_kontrol/ui/views/update_required_view.dart';

/// (genişlik, yükseklik, yazı ölçeği): AGENTS.md matrisi + yatay.
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 1.5),
];

const String _playUrl = 'https://play.google.com/store/apps/details?id=x';

Future<void> _pumpView(
  WidgetTester t,
  Widget view, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: view,
    ),
  );
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull);
}

AppConfig _config({
  String min = '2.0.0',
  String latest = '2.0.0',
  bool maintenance = false,
  String? message,
  String? android = _playUrl,
  String? email,
}) => AppConfig(
  minSupportedVersion: min,
  latestVersion: latest,
  updateUrlAndroid: android,
  updateUrlIos: 'https://apps.apple.com/app/id1',
  maintenanceActive: maintenance,
  maintenanceMessage: message,
  supportEmail: email,
);

/// Sunucuya gitmeyen sahte yapılandırma servisi: sıradaki yanıtları sırayla verir.
class _FakeService extends AppConfigService {
  _FakeService(this.responses);

  final List<AppConfig?> responses;

  /// Verilirse load() bu gelecek tamamlanana kadar bekler (yavaş ağ benzetimi).
  Future<void>? hold;
  int loads = 0;
  final List<bool> forces = <bool>[];
  AppConfig? _last;

  @override
  AppConfig? get current => _last;

  @override
  Future<AppConfig?> load({bool force = false}) async {
    forces.add(force);
    final waiting = hold;
    if (waiting != null) await waiting;
    final index = loads < responses.length ? loads : responses.length - 1;
    loads++;
    final next = responses[index];
    if (next != null) _last = next;
    return next;
  }
}

Future<InstalledAppInfo> _installed() async =>
    const InstalledAppInfo(version: '1.0.0', build: '1');

Future<void> _pumpGate(
  WidgetTester t, {
  required AppConfigService service,
  TargetPlatform platform = TargetPlatform.android,
  StoreLauncher? launcher,
  double width = 360,
  double height = 640,
  Widget? child,
  StoredSessionProbe? probe,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink()); // önceki kapı State'i sızmasın
  await t.pumpWidget(
    AppGate(
      configService: service,
      installedInfoLoader: _installed,
      platform: platform,
      launcher: launcher ?? ((_) async => true),
      sessionProbe: probe ?? (() async => StoredSessionKind.none),
      entryPollInterval: const Duration(milliseconds: 100),
      child:
          child ??
          MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: Center(child: Text('uygulama-acik'))),
          ),
    ),
  );
  // İlk kare + yapılandırma çözülür.
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

/// Kapının altındaki uygulamanın State'inin korunduğunu ölçer.
class _StateProbe extends StatefulWidget {
  const _StateProbe();

  static int inits = 0;
  static int taps = 0;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  int _local = 0;

  @override
  void initState() {
    super.initState();
    _StateProbe.inits++;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => setState(() {
              _local++;
              _StateProbe.taps++;
            }),
            child: Text('sayac-$_local'),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('UpdateRequiredView', () {
    for (final (w, h, s) in _cells) {
      for (final dark in const <bool>[false, true]) {
        for (final hasUrl in const <bool>[true, false]) {
          final cell =
              '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'} ${hasUrl ? 'URL var' : 'URL yok'}';
          testWidgets('taşma matrisi ($cell)', (t) async {
            await _pumpView(
              t,
              UpdateRequiredView(
                installedVersion: '1.0.0',
                minimumVersion: '2.0.0',
                storeUrl: hasUrl ? _playUrl : null,
                config: _config(email: 'destek@example.com'),
              ),
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            expect(find.text('Güncelleme gerekli'), findsOneWidget);
            expect(find.textContaining('(1.0.0)'), findsOneWidget);
            expect(find.textContaining('2.0.0'), findsOneWidget);
            expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
            expect(find.text('Güncelle'), hasUrl ? findsOneWidget : findsNothing);
            expect(find.textContaining('Destek: destek@example.com'), findsOneWidget);
            expect(t.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('"Güncelle" platform URL\'sini harici açar; düğme >= 44 dp', (t) async {
      final opened = <Uri>[];
      await _pumpView(
        t,
        UpdateRequiredView(
          installedVersion: '1.0.0',
          minimumVersion: '2.0.0',
          storeUrl: _playUrl,
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      final button = find.widgetWithText(ElevatedButton, 'Güncelle');
      expect(button, findsOneWidget);
      expect(t.getSize(button).height, greaterThanOrEqualTo(44));
      await t.tap(button);
      await t.pump();
      expect(opened, <Uri>[Uri.parse(_playUrl)]);
      expect(find.textContaining('Mağaza bağlantısı açılamadı'), findsNothing);
    });

    testWidgets('URL yoksa düğme yok, genel yönerge görünür', (t) async {
      await _pumpView(
        t,
        const UpdateRequiredView(installedVersion: '1.0.0', minimumVersion: '2.0.0'),
      );
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.textContaining('Google Play veya App Store'), findsOneWidget);
    });

    testWidgets('bağlantı açılamazsa elle güncelleme yönergesi çıkar (çökme yok)', (t) async {
      await _pumpView(
        t,
        UpdateRequiredView(
          installedVersion: '1.0.0',
          minimumVersion: '2.0.0',
          storeUrl: _playUrl,
          launcher: (_) async => throw StateError('mağaza yok'),
        ),
      );
      await t.tap(find.text('Güncelle'));
      await t.pump();
      expect(find.textContaining('Mağaza bağlantısı açılamadı'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('https olmayan bağlantı asla açılmaz', (t) async {
      var calls = 0;
      await _pumpView(
        t,
        UpdateRequiredView(
          installedVersion: '1.0.0',
          minimumVersion: '2.0.0',
          storeUrl: 'http://evil.example/x',
          launcher: (_) async {
            calls++;
            return true;
          },
        ),
      );
      await t.tap(find.text('Güncelle'));
      await t.pump();
      expect(calls, 0);
      expect(find.textContaining('Mağaza bağlantısı açılamadı'), findsOneWidget);
    });

    testWidgets('başlık anlamsal başlık; ikon rozeti dekoratif; tek AppCard', (t) async {
      await _pumpView(
        t,
        const UpdateRequiredView(installedVersion: '1.0.0', minimumVersion: '2.0.0'),
      );
      expect(find.byType(AppCard), findsOneWidget);
      expect(t.widget<AppCard>(find.byType(AppCard)).level, 2);
      expect(find.byType(IconOrb), findsOneWidget);
      expect(
        t.getSemantics(find.text('Güncelleme gerekli')),
        isSemantics(isHeader: true),
      );
    });
  });

  group('MaintenanceView', () {
    for (final (w, h, s) in _cells) {
      for (final dark in const <bool>[false, true]) {
        final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';
        testWidgets('taşma matrisi ($cell)', (t) async {
          await _pumpView(
            t,
            MaintenanceView(
              message:
                  'Sistemimiz gece 02:00 - 04:00 arasında bakımdadır. Bu süre içinde kapı kontrolü '
                  'etkilenmeyecek, yalnızca yönetim ekranları kullanılamayacaktır.',
              config: _config(email: 'destek@example.com'),
              onRetry: () async => null,
            ),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(find.text('Bakım çalışması'), findsOneWidget);
          expect(find.text('Yeniden dene'), findsOneWidget);
          expect(find.byIcon(Icons.construction_rounded), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('ileti yoksa genel metin gösterilir', (t) async {
      await _pumpView(t, MaintenanceView(onRetry: () async => null));
      expect(find.text(MaintenanceView.defaultMessage), findsOneWidget);
      await _pumpView(t, MaintenanceView(message: '   ', onRetry: () async => null));
      expect(find.text(MaintenanceView.defaultMessage), findsOneWidget);
    });

    testWidgets('"Yeniden dene": kontrol sırasında düğme pasif, ağ yoksa uyarı', (t) async {
      var calls = 0;
      final pending = Completer<AppConfig?>();
      await _pumpView(
        t,
        MaintenanceView(
          onRetry: () {
            calls++;
            return pending.future; // sunucu henüz yanıtlamadı
          },
        ),
      );
      await t.tap(find.text('Yeniden dene'));
      await t.pump(); // _checking = true
      expect(find.text('Kontrol ediliyor...'), findsOneWidget);
      expect(
        t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      pending.complete(null); // sunucuya ulaşılamadı
      await t.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
      expect(find.text('Yeniden dene'), findsOneWidget);
      expect(find.textContaining('Sunucuya ulaşılamadı'), findsOneWidget);
    });

    testWidgets('hâlâ bakımdaysa bilgilendirir; onRetry hata fırlatsa bile çökmez', (t) async {
      var mode = 0;
      await _pumpView(
        t,
        MaintenanceView(
          onRetry: () async {
            mode++;
            if (mode == 1) return _config(maintenance: true);
            throw StateError('beklenmedik');
          },
        ),
      );
      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('hâlâ bakımda'), findsOneWidget);

      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Sunucuya ulaşılamadı'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('AppGate', () {
    testWidgets('yapılandırma yüklenemezse uygulama ENGELLENMEZ', (t) async {
      final service = _FakeService(<AppConfig?>[null]);
      await _pumpGate(t, service: service);
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.text('Güncelleme gerekli'), findsNothing);
      expect(find.text('Bakım çalışması'), findsNothing);
      expect(service.loads, 1);
    });

    testWidgets('açılış beklemez: uygulama ilk karede çizilir', (t) async {
      final service = _FakeService(<AppConfig?>[_config()]);
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        AppGate(
          configService: service,
          installedInfoLoader: _installed,
          child: const MaterialApp(home: Text('uygulama-acik')),
        ),
      );
      expect(find.text('uygulama-acik'), findsOneWidget);
    });

    testWidgets('min sürümün altında: tam ekran güncelleme, uygulama gizli ama ağaçta', (t) async {
      final service = _FakeService(<AppConfig?>[_config(min: '1.5.0')]);
      await _pumpGate(t, service: service);
      expect(find.text('Güncelleme gerekli'), findsOneWidget);
      expect(find.text('uygulama-acik'), findsNothing); // Offstage: bulunmaz
      expect(find.text('uygulama-acik', skipOffstage: false), findsOneWidget);
    });

    testWidgets('"Güncelle" platforma uygun URL\'yi açar (Android)', (t) async {
      final opened = <Uri>[];
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.5.0')]),
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await t.tap(find.text('Güncelle'));
      await t.pump();
      expect(opened.single.toString(), _playUrl);
    });

    testWidgets('iOS\'ta iOS bağlantısı kullanılır', (t) async {
      final opened = <Uri>[];
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.5.0')]),
        platform: TargetPlatform.iOS,
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await t.tap(find.text('Güncelle'));
      await t.pump();
      expect(opened.single.host, 'apps.apple.com');
    });

    testWidgets('bakım modu: bakım ekranı; "Yeniden dene" bitince uygulamaya döner (durum korunur)', (t) async {
      final service = _FakeService(<AppConfig?>[
        _config(maintenance: true, message: 'Kısa bakım'),
        _config(maintenance: true, message: 'Kısa bakım'),
        _config(min: '1.0.0'),
      ]);
      await _pumpGate(t, service: service);
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.text('Kısa bakım'), findsOneWidget);

      // 1. deneme: hâlâ bakımda.
      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.textContaining('hâlâ bakımda'), findsOneWidget);

      // 2. deneme: bakım bitti.
      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Bakım çalışması'), findsNothing);
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(service.forces.skip(1), everyElement(isTrue), reason: 'yeniden dene force ile sorar');
    });

    testWidgets('engel kalkınca uygulama durumu KORUNUR (yeniden kurulmaz)', (t) async {
      _StateProbe.inits = 0;
      _StateProbe.taps = 0;
      final service = _FakeService(<AppConfig?>[
        _config(maintenance: true),
        _config(min: '1.0.0'),
      ]);
      await _pumpGate(t, service: service, child: const _StateProbe());
      expect(find.text('Bakım çalışması'), findsOneWidget);
      // Altta kalan uygulamaya dokunulamaz / görünmez (Offstage).
      expect(find.text('sayac-0'), findsNothing);
      expect(find.text('sayac-0', skipOffstage: false), findsOneWidget);

      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('sayac-0'), findsOneWidget);
      await t.tap(find.text('sayac-0'));
      await t.pump();
      expect(find.text('sayac-1'), findsOneWidget);
      expect(_StateProbe.inits, 1, reason: 'State bir kez kuruldu, atılıp yeniden kurulmadı');
    });

    testWidgets('bakım ekranındayken ağ koparsa bakım ekranı KALIR', (t) async {
      final service = _FakeService(<AppConfig?>[_config(maintenance: true), null]);
      await _pumpGate(t, service: service);
      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.textContaining('Sunucuya ulaşılamadı'), findsOneWidget);
    });

    testWidgets('latest_version üstündeyse kapatılabilir uyarı; kapatma kalıcıdır', (t) async {
      final service = _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]);
      await _pumpGate(t, service: service);
      expect(find.text('uygulama-acik'), findsOneWidget, reason: 'uygulama engellenmez');
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsOneWidget);

      await t.tap(find.text('Sonra'));
      await t.pump();
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppGate.dismissedLatestKey), '1.4.0');

      // Yeni açılış: aynı sürüm için uyarı tekrar çıkmaz.
      await _pumpGate(t, service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]));
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsNothing);

      // Daha yeni bir sürüm çıkınca yeniden gösterilir.
      await _pumpGate(t, service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.5.0')]));
      expect(find.text('Yeni sürüm hazır (1.5.0)'), findsOneWidget);
    });

    testWidgets('yumuşak uyarıdaki "Güncelle" URL\'yi açar; uygulama dokunuşları geçer', (t) async {
      final opened = <Uri>[];
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]),
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await t.tap(find.widgetWithText(FilledButton, 'Güncelle'));
      await t.pump();
      expect(opened, hasLength(1));
      // Uyarı dışındaki alan hâlâ uygulamanındır.
      expect(find.text('uygulama-acik'), findsOneWidget);
    });

    testWidgets('en son sürümdeysek uyarı da engel de yok', (t) async {
      final service = _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.0.0')]);
      await _pumpGate(t, service: service);
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.textContaining('Yeni sürüm hazır'), findsNothing);
    });

    testWidgets('yumuşak uyarı dar ekranda ve büyük yazıda taşmaz', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]),
        width: 320,
        height: 640,
      );
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('AppGate: yönetici kaçışı (süper kullanıcı kendini kilitlemez)', () {
    StoredSessionProbe probeOf(List<StoredSessionKind> kinds) {
      var i = 0;
      return () async {
        final kind = kinds[i < kinds.length ? i : kinds.length - 1];
        i++;
        return kind;
      };
    }

    testWidgets('bakım açık + süper kullanıcı oturumu -> uygulama görünür, yönetici şeridi var', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true, message: 'Gece bakımı')]),
        probe: probeOf(<StoredSessionKind>[StoredSessionKind.superUser]),
      );
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.text('Bakım çalışması'), findsNothing);
      expect(find.textContaining('Bakım modu açık (yönetici görünümü)'), findsOneWidget);
      expect(AppGateBlock.active.value, isFalse, reason: 'uygulama gizli değil');
    });

    testWidgets('zorunlu güncelleme + süper kullanıcı oturumu -> uygulama görünür, şerit var', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '9.0.0')]),
        probe: probeOf(<StoredSessionKind>[StoredSessionKind.superUser]),
      );
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.text('Güncelleme gerekli'), findsNothing);
      expect(find.textContaining('artık desteklenmiyor (yönetici görünümü)'), findsOneWidget);
    });

    testWidgets('normal kullanıcı oturumu -> bakım ekranı (yönetici düğmesiyle); şerit yok', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: probeOf(<StoredSessionKind>[StoredSessionKind.other]),
      );
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.text('uygulama-acik'), findsNothing);
      expect(find.textContaining('yönetici görünümü'), findsNothing);
      expect(find.text('Yönetici girişi'), findsOneWidget);
      expect(AppGateBlock.active.value, isTrue);
    });

    testWidgets('engel yokken oturum yoklanmaz ve şerit çıkmaz', (t) async {
      var probes = 0;
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.0.0')]),
        probe: () async {
          probes++;
          return StoredSessionKind.superUser;
        },
      );
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.textContaining('yönetici görünümü'), findsNothing);
      expect(probes, 0);
    });

    testWidgets('"Yönetici girişi" başka hesap açıkken engeli KALDIRMAZ, açıklama gösterir', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '9.0.0')]),
        probe: probeOf(<StoredSessionKind>[StoredSessionKind.other]),
      );
      await t.tap(find.text('Yönetici girişi'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Güncelleme gerekli'), findsOneWidget);
      expect(find.text('uygulama-acik'), findsNothing);
      expect(find.textContaining('Bu cihazda başka bir hesabın oturumu açık'), findsOneWidget);
    });

    testWidgets('oturum yokken "Yönetici girişi" giriş ekranını geçici açar; "Vazgeç" engeli geri getirir', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: probeOf(<StoredSessionKind>[StoredSessionKind.none]),
      );
      expect(find.text('Bakım çalışması'), findsOneWidget);

      await t.tap(find.text('Yönetici girişi'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Bakım çalışması'), findsNothing);
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.textContaining('Yönetici girişi: yalnızca süper kullanıcı hesabıyla'), findsOneWidget);
      expect(AppGateBlock.active.value, isFalse);

      await t.tap(find.text('Vazgeç'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.text('uygulama-acik'), findsNothing);
      expect(AppGateBlock.active.value, isTrue);
      await t.pumpWidget(const SizedBox.shrink()); // zamanlayıcılar kapansın
    });

    testWidgets('giriş modunda süper kullanıcı girişi yapılırsa engel kalkık kalır (şerit değişir)', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        // 1: açılış yoklaması (yok), 2: düğme (yok), 3+: giriş sonrası (süper kullanıcı)
        probe: probeOf(<StoredSessionKind>[
          StoredSessionKind.none,
          StoredSessionKind.none,
          StoredSessionKind.superUser,
        ]),
      );
      await t.tap(find.text('Yönetici girişi'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Vazgeç'), findsOneWidget);

      await t.pump(const Duration(milliseconds: 250)); // yoklama aralığı 100 ms
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.text('Vazgeç'), findsNothing);
      expect(find.textContaining('Bakım modu açık (yönetici görünümü)'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('giriş modunda süper kullanıcı olmayan hesap girerse engel geri gelir', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: probeOf(<StoredSessionKind>[
          StoredSessionKind.none,
          StoredSessionKind.none,
          StoredSessionKind.other,
        ]),
      );
      await t.tap(find.text('Yönetici girişi'));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 250));
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.text('uygulama-acik'), findsNothing);
      expect(find.textContaining('Bu hesap süper kullanıcı değil'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('AppGateBlock: engelde true, bakım bitince false, kapı kalkınca (dispose) false', (t) async {
      final service = _FakeService(<AppConfig?>[
        _config(maintenance: true),
        _config(min: '1.0.0'),
      ]);
      await _pumpGate(t, service: service);
      expect(AppGateBlock.active.value, isTrue);
      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 100));
      expect(AppGateBlock.active.value, isFalse);

      final blocked = _FakeService(<AppConfig?>[_config(maintenance: true)]);
      await _pumpGate(t, service: blocked);
      expect(AppGateBlock.active.value, isTrue);
      await t.pumpWidget(const SizedBox.shrink());
      expect(AppGateBlock.active.value, isFalse);
    });

    testWidgets('öncül: gizli uygulamanın gezginine açılan pencere engel kalkınca görünür (derin bağlantı koruması bu yüzden gerekli)', (t) async {
      final navKey = GlobalKey<NavigatorState>();
      final service = _FakeService(<AppConfig?>[
        _config(maintenance: true),
        _config(min: '1.0.0'),
      ]);
      await _pumpGate(
        t,
        service: service,
        child: MaterialApp(
          navigatorKey: navKey,
          theme: AppTheme.light(),
          home: const Scaffold(body: Text('uygulama-acik')),
        ),
      );
      expect(AppGateBlock.active.value, isTrue);
      unawaited(
        showDialog<void>(
          context: navKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Kapı açılsın mı?')),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Kapı açılsın mı?'), findsNothing, reason: 'gizliyken görünmez');

      await t.tap(find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Kapı açılsın mı?'),
        findsOneWidget,
        reason: 'engel kalkınca bekleyen pencere belirir: lib/app.dart gizliyken gelen bağlantıları yok sayar',
      );
    });
  });

  group('AppGate: alt şerit uygulamanın üzerine binmez', () {
    Widget appWithBottomButton(void Function() onTap) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: Center(child: Text('uygulama-acik'))),
            ElevatedButton(
              key: const ValueKey<String>('gonder'),
              onPressed: onTap,
              child: const Text('Gönder'),
            ),
          ],
        ),
      ),
    );

    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 1.5),
    ]) {
      testWidgets('yumuşak uyarı ${w.toInt()}x${h.toInt()} x$s: alttaki düğme kapanmaz, dokunulabilir, taşma yok', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = s;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        var taps = 0;
        await _pumpGate(
          t,
          service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]),
          width: w,
          height: h,
          child: appWithBottomButton(() => taps++),
        );
        expect(find.text('Yeni sürüm hazır (1.4.0)'), findsOneWidget);

        final banner = t.getRect(find.byType(SoftUpdateBanner));
        final button = t.getRect(find.byKey(const ValueKey<String>('gonder')));
        expect(button.bottom, lessThanOrEqualTo(banner.top + 0.5), reason: 'düğme uyarının üstünde kalır');
        // Uyarı en çok ekranın %35'i (aşarsa içerik kayar).
        final scroller = t.getRect(
          find.ancestor(
            of: find.byType(SoftUpdateBanner),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(scroller.height, lessThanOrEqualTo(h * AppGate.bottomBarMaxHeightFraction + 0.5));

        await t.tap(find.byKey(const ValueKey<String>('gonder')));
        await t.pump();
        expect(taps, 1);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('yönetici şeridi de uygulamaya yer ayırır', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      var taps = 0;
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: () async => StoredSessionKind.superUser,
        width: 320,
        height: 640,
        child: appWithBottomButton(() => taps++),
      );
      final strip = t.getRect(find.textContaining('Bakım modu açık'));
      final button = t.getRect(find.byKey(const ValueKey<String>('gonder')));
      expect(button.bottom, lessThanOrEqualTo(strip.top + 0.5));
      await t.tap(find.byKey(const ValueKey<String>('gonder')));
      expect(taps, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('klavye açıkken uyarı gizlenir, kapanınca geri gelir', (t) async {
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]),
      );
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsOneWidget);

      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsNothing);

      t.view.resetViewInsets();
      await t.pump();
      expect(find.text('Yeni sürüm hazır (1.4.0)'), findsOneWidget);
    });
  });

  group('engel ekranları: "Yönetici girişi" düğmesi ve açıklama (taşma matrisi)', () {
    for (final (w, h, s) in _cells) {
      for (final dark in const <bool>[false, true]) {
        final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';
        const notice =
            'Yönetici girişi yalnızca süper kullanıcı hesabıyla yapılabilir. '
            'Bu cihazda başka bir hesabın oturumu açık.';
        testWidgets('güncelleme ekranı ($cell)', (t) async {
          var taps = 0;
          await _pumpView(
            t,
            UpdateRequiredView(
              installedVersion: '1.0.0',
              minimumVersion: '2.0.0',
              storeUrl: _playUrl,
              config: _config(email: 'destek@example.com'),
              onOperatorLogin: () => taps++,
              operatorNotice: notice,
            ),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(find.text('Yönetici girişi'), findsOneWidget);
          expect(find.text(notice), findsOneWidget);
          await t.ensureVisible(find.text('Yönetici girişi'));
          await t.tap(find.text('Yönetici girişi'));
          expect(taps, 1);
          expect(t.takeException(), isNull);
        });
        testWidgets('bakım ekranı ($cell)', (t) async {
          var taps = 0;
          await _pumpView(
            t,
            MaintenanceView(
              message: 'Gece bakımı sürüyor.',
              config: _config(email: 'destek@example.com'),
              onRetry: () async => null,
              onOperatorLogin: () => taps++,
              operatorNotice: notice,
            ),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(find.text('Yönetici girişi'), findsOneWidget);
          expect(find.text(notice), findsOneWidget);
          await t.ensureVisible(find.text('Yönetici girişi'));
          await t.tap(find.text('Yönetici girişi'));
          expect(taps, 1);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('düğme verilmezse "Yönetici girişi" görünmez', (t) async {
      await _pumpView(
        t,
        const UpdateRequiredView(installedVersion: '1.0.0', minimumVersion: '2.0.0'),
      );
      expect(find.text('Yönetici girişi'), findsNothing);
      await _pumpView(t, MaintenanceView(onRetry: () async => null));
      expect(find.text('Yönetici girişi'), findsNothing);
    });
  });

  group('AppGate: yönetici kaçışı mandal değildir (R8 B1)', () {
    testWidgets('süper kullanıcı çıkış yapıp sıradan kullanıcı girince bakım ekranı geri gelir', (t) async {
      var kind = StoredSessionKind.superUser;
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: () async => kind,
      );
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.textContaining('yönetici görünümü'), findsOneWidget);
      expect(AppGateBlock.active.value, isFalse);

      // Süper kullanıcı çıkış yaptı, sıradan kullanıcı girdi: kayıtlı oturum rolü değişti.
      kind = StoredSessionKind.other;
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      // İlk kaçırmada hemen düşmez (tek seferlik okuma hatası ekranı yanıp söndürmesin) ...
      expect(find.text('uygulama-acik'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      // ... ardışık ikinci kaçırmada engel geri gelir.
      expect(find.text('Bakım çalışması'), findsOneWidget);
      expect(find.text('uygulama-acik'), findsNothing);
      expect(find.textContaining('yönetici görünümü'), findsNothing);
      expect(AppGateBlock.active.value, isTrue);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('çıkış yapılınca (oturum yok) da kaçış kalkar; Yönetici girişi ile yeniden açılır', (t) async {
      var kind = StoredSessionKind.superUser;
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: () async => kind,
      );
      kind = StoredSessionKind.none;
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 110));
        await t.pump();
      }
      expect(find.text('Bakım çalışması'), findsOneWidget);

      kind = StoredSessionKind.superUser;
      await t.tap(find.text('Yönetici girişi'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('uygulama-acik'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tek seferlik geçici okuma hatası kaçışı düşürmez', (t) async {
      final answers = <StoredSessionKind>[
        StoredSessionKind.superUser, // açılış
        StoredSessionKind.none, // geçici hata
        StoredSessionKind.superUser, // düzeldi
        StoredSessionKind.superUser,
      ];
      var i = 0;
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: () async => answers[i < answers.length ? i++ : answers.length - 1],
      );
      for (var k = 0; k < 4; k++) {
        await t.pump(const Duration(milliseconds: 110));
        await t.pump();
      }
      expect(find.text('uygulama-acik'), findsOneWidget);
      expect(find.text('Bakım çalışması'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('arka plandayken yoklama yapılmaz; öne dönünce hemen yeniden denetlenir', (t) async {
      var kind = StoredSessionKind.superUser;
      var probes = 0;
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(maintenance: true)]),
        probe: () async {
          probes++;
          return kind;
        },
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = probes;
      kind = StoredSessionKind.other;
      for (var k = 0; k < 5; k++) {
        await t.pump(const Duration(milliseconds: 110));
        await t.pump();
      }
      expect(probes, before, reason: 'arka planda yoklama yok');
      expect(find.text('uygulama-acik'), findsOneWidget);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Bakım çalışması'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('engel kalkınca (bakım bitti) yoklama durur', (t) async {
      var probes = 0;
      final service = _FakeService(<AppConfig?>[
        _config(maintenance: true),
        _config(min: '1.0.0'),
      ]);
      await _pumpGate(
        t,
        service: service,
        probe: () async {
          probes++;
          return StoredSessionKind.superUser;
        },
      );
      // süper kullanıcı: kaçış açık, yoklama çalışıyor; bir yeniden denetim bakımı bitmiş görür.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final after = probes;
      for (var k = 0; k < 5; k++) {
        await t.pump(const Duration(milliseconds: 110));
        await t.pump();
      }
      expect(probes, after, reason: 'engel yokken oturum yoklanmaz');
      expect(find.textContaining('yönetici görünümü'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });

  group('AppGate: soğuk açılışta derin bağlantı koruması (R8 B3)', () {
    /// lib/app.dart `_handleDeepLinkAction` başındaki sıranın aynısı: önce ilk denetimi bekle, sonra engele bak.
    Future<bool> handlerWouldProceed() async {
      await AppGateBlock.waitForFirstCheck();
      return !AppGateBlock.active.value;
    }

    testWidgets('kapı ağaçta değilse beklenmez ve bağlantı yutulmaz', (t) async {
      await t.pumpWidget(const SizedBox.shrink());
      expect(AppGateBlock.pendingFirstCheck.value, isFalse);
      expect(await handlerWouldProceed(), isTrue);
    });

    testWidgets('bağlantı ilk denetimden ÖNCE gelirse bekler; bakım çıkarsa yok sayılır', (t) async {
      final hold = Completer<void>();
      final service = _FakeService(<AppConfig?>[_config(maintenance: true)])..hold = hold.future;
      await _pumpGate(t, service: service);
      expect(AppGateBlock.pendingFirstCheck.value, isTrue, reason: 'denetim sürüyor');
      expect(AppGateBlock.active.value, isFalse, reason: 'henüz karar yok');

      bool? proceeded;
      unawaited(handlerWouldProceed().then((v) => proceeded = v));
      await t.pump(const Duration(seconds: 1));
      expect(proceeded, isNull, reason: 'ilk denetimi bekliyor');

      hold.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(AppGateBlock.pendingFirstCheck.value, isFalse);
      expect(proceeded, isFalse, reason: 'bakım ekranı varken bağlantı yok sayıldı');
      expect(find.text('Bakım çalışması'), findsOneWidget);
    });

    testWidgets('engel yoksa bekleyen bağlantı denetim bitince işlenir', (t) async {
      final hold = Completer<void>();
      final service = _FakeService(<AppConfig?>[_config(min: '1.0.0')])..hold = hold.future;
      await _pumpGate(t, service: service);
      bool? proceeded;
      unawaited(handlerWouldProceed().then((v) => proceeded = v));
      await t.pump(const Duration(milliseconds: 500));
      expect(proceeded, isNull);
      hold.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(proceeded, isTrue);
    });

    testWidgets('yapılandırma yüklenemese de (null) bekleme biter ve bağlantı işlenir', (t) async {
      final hold = Completer<void>();
      final service = _FakeService(<AppConfig?>[null])..hold = hold.future;
      await _pumpGate(t, service: service);
      bool? proceeded;
      unawaited(handlerWouldProceed().then((v) => proceeded = v));
      hold.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(AppGateBlock.pendingFirstCheck.value, isFalse);
      expect(proceeded, isTrue, reason: 'kapı engellemedi: bağlantı yutulmamalı');
    });

    testWidgets('bekleme en çok 5 sn sürer (yavaş ağda bağlantı sonsuza dek beklemez)', (t) async {
      final hold = Completer<void>(); // hiç tamamlanmaz
      final service = _FakeService(<AppConfig?>[_config(maintenance: true)])..hold = hold.future;
      await _pumpGate(t, service: service);
      bool? proceeded;
      unawaited(handlerWouldProceed().then((v) => proceeded = v));
      await t.pump(const Duration(milliseconds: 4900));
      expect(proceeded, isNull);
      await t.pump(const Duration(milliseconds: 300));
      expect(proceeded, isTrue, reason: '5 sn dolunca karar henüz yok: bağlantı işlenir');
      hold.complete();
      await t.pump();
    });

    testWidgets('kapı kalkınca (dispose) bekleyenler serbest kalır', (t) async {
      final hold = Completer<void>();
      final service = _FakeService(<AppConfig?>[_config(maintenance: true)])..hold = hold.future;
      await _pumpGate(t, service: service);
      bool? proceeded;
      unawaited(handlerWouldProceed().then((v) => proceeded = v));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      expect(AppGateBlock.pendingFirstCheck.value, isFalse);
      expect(proceeded, isTrue);
      hold.complete();
    });
  });

  group('AppGate: alt güvenli alan çift sayılmaz (R8 B6)', () {
    Future<void> pumpWithInset(
      WidgetTester t, {
      required double inset,
      required AppConfig config,
      StoredSessionProbe? probe,
    }) async {
      t.view.padding = FakeViewPadding(bottom: inset);
      t.view.viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[config]),
        probe: probe,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: const Center(child: Text('uygulama-acik')),
            bottomNavigationBar: const SafeArea(
              child: SizedBox(key: ValueKey<String>('nav'), height: 56, child: Text('nav')),
            ),
          ),
        ),
      );
    }

    for (final inset in <double>[0, 24, 34]) {
      testWidgets('yumuşak uyarı, alt inset $inset: uygulamanın alt kenarı şeridin üst kenarında biter', (t) async {
        await pumpWithInset(t, inset: inset, config: _config(min: '1.0.0', latest: '1.4.0'));
        final banner = t.getRect(find.byType(SoftUpdateBanner));
        final nav = t.getRect(find.byKey(const ValueKey<String>('nav')));
        // Şerit: dış dolgu 12 dp + güvenli alan. Şeridin üst kenarı = banner.top - 12.
        final barTop = banner.top - AppSpace.md;
        expect(nav.bottom, closeTo(barTop, 0.5), reason: 'çift güvenli alan boşluğu kalmamalı (inset $inset)');
        expect(banner.bottom, closeTo(640 - inset - AppSpace.md, 0.5), reason: 'şerit güvenli alanın üstünde');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('yönetici şeridi de aynı: boşluk yok, uygulama içeriği şeridin üstünde', (t) async {
      await pumpWithInset(
        t,
        inset: 34,
        config: _config(maintenance: true),
        probe: () async => StoredSessionKind.superUser,
      );
      final strip = t.getRect(find.textContaining('Bakım modu açık'));
      final nav = t.getRect(find.byKey(const ValueKey<String>('nav')));
      expect(nav.bottom, lessThanOrEqualTo(strip.top));
      // Şerit kartının üst kenarına (kart dolgusu dahil) en çok birkaç dp uzaklıkta.
      expect(strip.top - nav.bottom, lessThan(AppSpace.md + AppSpace.md + 1));
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('şerit yokken uygulama tüm alanı kullanır (yerleşim değişmez)', (t) async {
      await pumpWithInset(t, inset: 34, config: _config(min: '1.0.0', latest: '1.0.0'));
      final nav = t.getRect(find.byKey(const ValueKey<String>('nav')));
      expect(nav.bottom, closeTo(640 - 34, 0.5));
    });

    testWidgets('alt inset altında uygulamanın en alt düğmesi şerit varken de dokunulabilir', (t) async {
      var taps = 0;
      t.view.padding = const FakeViewPadding(bottom: 34);
      t.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      await _pumpGate(
        t,
        service: _FakeService(<AppConfig?>[_config(min: '1.0.0', latest: '1.4.0')]),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const Expanded(child: Center(child: Text('uygulama-acik'))),
                  ElevatedButton(
                    key: const ValueKey<String>('gonder'),
                    onPressed: () => taps++,
                    child: const Text('Gönder'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final banner = t.getRect(find.byType(SoftUpdateBanner));
      final button = t.getRect(find.byKey(const ValueKey<String>('gonder')));
      expect(button.bottom, lessThanOrEqualTo(banner.top));
      await t.tap(find.byKey(const ValueKey<String>('gonder')));
      expect(taps, 1);
    });
  });
}
