// FAZ 5 / A4: "Bağlantı & Kopma Geçmişi" akordiyonu (device_connectivity_logs_accordion.dart; şirket
// cihaz kartının içinde). Spesifikasyonun ekran listesinde ayrı bir sahibi yoktu; A4 doğrulamasında
// açık temada düşük kontrastlı (emeraldLight/amberLight/roseLight) metin-ikonlar ve dar ekranda
// taşabilen iki satır (log başlığı, sayfalama) bulundu.
//
// Kapsam: açık+koyu tema x 320x640 (x2,0), 360x640 (x1,5), 412x915 (x1,0) taşmaz (üç durum: çevrimiçi +
// loglar + sayfalama, çevrimdışı + boş log, hata + Tekrar Dene); açık temada metin >= 4,5:1 ve ikon
// >= 3:1; metinler/davranış (aç/kapat, yenile, sayfa değiştir, tekrar dene) AYNI.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_connectivity_logs_accordion.dart';

import '../design/harness.dart';

DeviceRecord _device({bool online = true}) => DeviceRecord(
  id: 1,
  deviceUid: 'DEV-AABB1122',
  assignedUserCode: 1001,
  siteCode: 10,
  siteName: 'Güneş Sitesi',
  assignedDoorId: 5,
  assignedDoorName: 'Ana Giriş Kapısı',
  gateName: 'Giriş',
  siteApprovalStatus: 'approved',
  mqttUsername: 'device_DEV-AABB1122',
  mqttConfigured: true,
  mqttConnected: online,
  firmwareVersion: '3.0.3',
  hardwareTarget: 'esp32-c3',
  otaStatus: null,
  otaLastVersion: null,
  wifiRssi: -58,
  wifiSignalPercent: 82,
  lastSeenAt: DateTime(2026, 1, 1),
  lastEvent: null,
  localIp: '192.168.1.105',
  createdAt: DateTime(2026, 1, 1),
);

DeviceConnectivityReport _report({
  bool online = true,
  int logCount = 2,
  int page = 1,
  int totalPages = 3,
}) => DeviceConnectivityReport.fromJson({
  'device_uid': 'DEV-AABB1122',
  'is_online': online,
  'current_online_since': '2026-09-08T18:00:00.000Z',
  'current_online_duration_seconds': 14400,
  'current_online_duration_text': '4 saat 12 dakika',
  'last_offline_at': '2026-09-08T17:50:00.000Z',
  'logs': [
    for (var i = 0; i < logCount; i++)
      {
        'id': i + 1,
        'device_uid': 'DEV-AABB1122',
        'event_type': 'offline',
        'online_at': '2026-09-08T12:00:00.000Z',
        'offline_at': '2026-09-08T17:50:00.000Z',
        'duration_seconds': 21000,
        'duration_text': '5 saat 50 dk',
        'reason': 'Wi-Fi / Bağlantı Kesildi (LWT)',
        'wifi_rssi': -65,
        'wifi_signal_percent': 75,
        'local_ip': '192.168.1.105',
        'created_at': '2026-09-08T17:50:02.000Z',
      },
  ],
  'pagination': {
    'page': page,
    'pageSize': 10,
    'total': logCount * totalPages,
    'totalPages': totalPages,
  },
});

class _LogsAuth extends AuthService {
  _LogsAuth({this.report, this.error, this.never = false})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  DeviceConnectivityReport? report;
  String? error;

  /// true: yanıt hiç gelmez (ilk yükleme / iskelet durumu).
  final bool never;
  final List<int> pages = <int>[];
  final Completer<(DeviceConnectivityReport?, String?)> _pending =
      Completer<(DeviceConnectivityReport?, String?)>();

  @override
  Future<(DeviceConnectivityReport?, String?)> getDeviceConnectivityLogs({
    required String deviceUid,
    int page = 1,
    int pageSize = 10,
  }) async {
    pages.add(page);
    if (never) return _pending.future;
    if (error != null) return (null, error);
    return (report, null);
  }
}

Widget _accordion(_LogsAuth auth, {bool online = true}) => Padding(
  padding: const EdgeInsets.all(16),
  child: DeviceConnectivityLogsAccordion(
    device: _device(online: online),
    authService: auth,
  ),
);

/// Akordiyonu açar ve yüklemeyi bitirir.
Future<void> _expand(WidgetTester t) async {
  await t.tap(find.text('Logları Gör'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

double _lum(Color c) => c.computeLuminance();

double _ratio(Color a, Color b) {
  final l1 = _lum(a);
  final l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// [fg] saydam rengini [bg] üstüne bindirir.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

// Akordiyon açık zemini: sayfa zemini (en açık olası yüzey); panel artık palet.surfaceMuted (#F1F5F9).
// Metin ve ikon kontrastı her iki zeminde de sınanır (en kötü durum alınır).
const Color _lightSurface = Color(0xFFF8FAFC);

Color _textColor(WidgetTester t, String text) {
  final w = t.widget<Text>(find.text(text));
  return w.style!.color!;
}

Color _iconColor(WidgetTester t, IconData icon) =>
    t.widget<Icon>(find.byIcon(icon)).color!;

/// [icon] bir [IconOrb] içindedir. Sade stilde (İP-1C) rozet düzdür: soluk yüzey zemin, ikon tonun işaret rengi
/// ([AppTone.sign]: durum tonlarında ink); ikon zemine >= 3:1 (ikon eşiği; ölçüm ayrıca `icon_orb_test.dart`'ta).
void _expectOrbIcon(
  WidgetTester t,
  IconData icon,
  AppTone tone, {
  required String reason,
}) {
  final p = t.element(find.byIcon(icon).first).palette;
  final icons = find.byIcon(icon).evaluate().toList();
  expect(icons, isNotEmpty, reason: reason);
  for (final e in icons) {
    expect((e.widget as Icon).color, tone.sign(p), reason: reason);
  }
  final orbs = find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(IconOrb),
  );
  expect(orbs, findsWidgets, reason: '$reason: ikon IconOrb içinde');
  for (final e in orbs.evaluate()) {
    expect((e.widget as IconOrb).tone, tone, reason: reason);
  }
  expect(
    _ratio(tone.sign(p), p.surfaceMuted),
    greaterThanOrEqualTo(3.0),
    reason: '$reason (${tone.name} rozet zemini)',
  );
}

void main() {
  group('taşma: açık+koyu x 320 (x2,0) / 360 (x1,5) / 412 (x1,0)', () {
    const cells = <({double w, double s})>[
      (w: 320, s: 2.0),
      (w: 360, s: 1.5),
      (w: 412, s: 1.0),
    ];
    for (final c in cells) {
      for (final dark in const <bool>[false, true]) {
        final tag = '${c.w.toInt()} x${c.s} ${dark ? 'koyu' : 'açık'}';

        testWidgets('çevrimiçi + log kartları + sayfalama: $tag', (t) async {
          final auth = _LogsAuth(report: _report());
          await pumpAt(t, _accordion(auth), width: c.w, scale: c.s, dark: dark);
          await _expand(t);
          expect(t.takeException(), isNull);
          expect(find.textContaining('Kesintisiz Çevrimiçi'), findsOneWidget);
          expect(find.text('Kopma / Çevrimdışı Logları'), findsOneWidget);
          expect(find.textContaining('Sayfa 1 / 3'), findsOneWidget);
        });

        testWidgets('çevrimdışı + boş log listesi: $tag', (t) async {
          final auth = _LogsAuth(
            report: _report(online: false, logCount: 0, totalPages: 1),
          );
          await pumpAt(
            t,
            _accordion(auth, online: false),
            width: c.w,
            scale: c.s,
            dark: dark,
          );
          await _expand(t);
          expect(t.takeException(), isNull);
          expect(find.text('🔴 Cihaz Şu An Çevrimdışı'), findsOneWidget);
          expect(find.text('Kayıtlı kopma logu bulunmuyor.'), findsOneWidget);
        });

        testWidgets('hata + Tekrar Dene: $tag', (t) async {
          final auth = _LogsAuth(error: 'Sunucu yanıt vermedi.');
          await pumpAt(t, _accordion(auth), width: c.w, scale: c.s, dark: dark);
          await _expand(t);
          expect(t.takeException(), isNull);
          expect(find.text('Sunucu yanıt vermedi.'), findsOneWidget);
          expect(find.text('Tekrar Dene'), findsOneWidget);
        });
      }
    }
  });

  group('açık tema kontrastı (metin >= 4,5:1, ikon >= 3:1)', () {
    testWidgets(
      'çevrimiçi: başlık ikonu, uptime metinleri, banner ikonu, log ikonu',
      (t) async {
        final auth = _LogsAuth(report: _report());
        await pumpAt(t, _accordion(auth), width: 412, scale: 1.0);
        const p = AppPalette.light;
        // Başlık ikonu: çevrimiçi = success küresi.
        _expectOrbIcon(
          t,
          Icons.history_toggle_off_rounded,
          AppTone.success,
          reason: 'başlık ikonu (çevrimiçi)',
        );
        await _expand(t);

        // Aktif Uptime metni: panel (soluk yüzey) ve sayfa zemini üstünde.
        for (final surface in <Color>[_lightSurface, p.surfaceMuted]) {
          expect(
            _ratio(_textColor(t, 'Aktif Uptime: 4 saat 12 dakika'), surface),
            greaterThanOrEqualTo(4.5),
            reason: 'Aktif Uptime metni zemin=$surface',
          );
        }

        // Çevrimiçi banner: success tint'i satır yüzeyi (beyaz) üstünde; ikon success küresinde.
        final bannerBg = _over(AppTone.success.tint(p), p.surface);
        _expectOrbIcon(
          t,
          Icons.wifi_rounded,
          AppTone.success,
          reason: 'banner ikonu',
        );
        expect(
          _ratio(
            _textColor(t, '🟢 Kesintisiz Çevrimiçi (Uptime): 4 saat 12 dakika'),
            bannerBg,
          ),
          greaterThanOrEqualTo(4.5),
        );
        // Alt satırın saati yerel saat dilimine bağlıdır: yalnız önek ile bulunur.
        final sinceColor = t
            .widget<Text>(find.textContaining('Bağlantı başlangıcı: '))
            .style!
            .color!;
        expect(
          _ratio(sinceColor, bannerBg),
          greaterThanOrEqualTo(4.5),
          reason: 'banner alt satırı',
        );

        // Log kartı: danger küresi (beyaz kart üstünde).
        _expectOrbIcon(
          t,
          Icons.cloud_off_rounded,
          AppTone.danger,
          reason: 'log kartı ikonu',
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'çevrimdışı: başlık ikonu, banner ikonu; boş durumda onay ikonu',
      (t) async {
        final auth = _LogsAuth(
          report: _report(online: false, logCount: 0, totalPages: 1),
        );
        await pumpAt(
          t,
          _accordion(auth, online: false),
          width: 412,
          scale: 1.0,
        );
        const p = AppPalette.light;
        _expectOrbIcon(
          t,
          Icons.history_toggle_off_rounded,
          AppTone.warning,
          reason: 'başlık ikonu (çevrimdışı = uyarı tonu)',
        );
        await _expand(t);

        _expectOrbIcon(
          t,
          Icons.wifi_off_rounded,
          AppTone.danger,
          reason: 'çevrimdışı banner ikonu',
        );
        final bannerBg = _over(AppTone.danger.tint(p), p.surface);
        expect(
          _ratio(_textColor(t, '🔴 Cihaz Şu An Çevrimdışı'), bannerBg),
          greaterThanOrEqualTo(4.5),
          reason: 'çevrimdışı banner başlığı',
        );
        // Boş durum (EmptyState.compact): onay ikonu success küresinde.
        _expectOrbIcon(
          t,
          Icons.verified_rounded,
          AppTone.success,
          reason: 'boş durum onay ikonu',
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('hata kutusu: metin ve ikon danger tonlu zeminde', (t) async {
      final auth = _LogsAuth(error: 'Sunucu yanıt vermedi.');
      await pumpAt(t, _accordion(auth), width: 412, scale: 1.0);
      await _expand(t);
      const p = AppPalette.light;
      final bg = _over(AppTone.danger.tint(p), p.surface);
      expect(
        _ratio(_textColor(t, 'Sunucu yanıt vermedi.'), bg),
        greaterThanOrEqualTo(4.5),
        reason: 'hata metni',
      );
      expect(
        _ratio(_iconColor(t, Icons.error_outline_rounded), bg),
        greaterThanOrEqualTo(3.0),
        reason: 'hata ikonu',
      );
    });
  });

  group('davranış AYNI (metinler, aç/kapat, sayfalama, tekrar dene)', () {
    testWidgets(
      'açılınca loglar yüklenir (sayfa 1); sonraki sayfa 2 ister; Gizle kapatır',
      (t) async {
        final auth = _LogsAuth(report: _report());
        await pumpAt(t, _accordion(auth), width: 412, scale: 1.0);
        expect(find.text('Bağlantı & Kopma Geçmişi'), findsOneWidget);
        expect(find.text('Logları Gör'), findsOneWidget);

        await _expand(t);
        expect(auth.pages, <int>[1]);
        expect(find.text('Gizle'), findsOneWidget);
        expect(find.text('Kopma / Çevrimdışı Logları'), findsOneWidget);
        expect(find.textContaining('Kopma: '), findsNWidgets(2));

        await t.ensureVisible(find.byIcon(Icons.chevron_right_rounded));
        await t.pump();
        await t.tap(find.byIcon(Icons.chevron_right_rounded));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(auth.pages, <int>[1, 2]);

        await t.ensureVisible(find.text('Gizle'));
        await t.pump();
        await t.tap(find.text('Gizle'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Logları Gör'), findsOneWidget);
        expect(find.text('Kopma / Çevrimdışı Logları'), findsNothing);
      },
    );

    testWidgets('hata: Tekrar Dene yeniden ister; başarıda loglar gelir', (
      t,
    ) async {
      final auth = _LogsAuth(error: 'Sunucu yanıt vermedi.');
      await pumpAt(t, _accordion(auth), width: 412, scale: 1.0);
      await _expand(t);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth
        ..error = null
        ..report = _report();
      await t.tap(find.text('Tekrar Dene'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.pages, <int>[1, 1]);
      expect(find.text('Tekrar Dene'), findsNothing);
      expect(find.text('Kopma / Çevrimdışı Logları'), findsOneWidget);
    });
  });

  group('premium görünüm: küreler, kademeli giriş, iskelet, dokunma hedefleri', () {
    testWidgets(
      'her log satırı: IconOrb + süre StatusChip + kademeli giriş (StaggeredEntry); başlık ve özet küreleri',
      (t) async {
        final auth = _LogsAuth(report: _report(logCount: 3));
        await pumpAt(t, _accordion(auth), width: 412, scale: 1.0);
        await _expand(t);
        expect(find.byType(StaggeredEntry), findsNWidgets(3));
        // başlık küresi + özet kutusu küresi + 3 satır küresi
        expect(find.byType(IconOrb), findsNWidgets(5));
        expect(find.byType(StatusChip), findsNWidgets(3));
        expect(find.text('5 saat 50 dk'), findsNWidgets(3));
        for (final chip in t.widgetList<StatusChip>(find.byType(StatusChip))) {
          expect(chip.tone, AppTone.primary);
          expect(chip.pulse, isFalse, reason: 'kararlı durumda nabız yok');
        }
        // Kararlı durumda hiçbir animasyon kalmaz (giriş sonlu).
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('boş log: EmptyState(kompakt) ve mevcut iki cümle; satır küresi yok', (
      t,
    ) async {
      final auth = _LogsAuth(
        report: _report(online: false, logCount: 0, totalPages: 1),
      );
      await pumpAt(t, _accordion(auth, online: false), width: 412, scale: 1.0);
      await _expand(t);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(t.widget<EmptyState>(find.byType(EmptyState)).compact, isTrue);
      expect(find.text('Kayıtlı kopma logu bulunmuyor.'), findsOneWidget);
      expect(
        find.text('Cihaz bağlantısı stabil ve kesintisiz çalışıyor.'),
        findsOneWidget,
      );
      expect(find.byType(StaggeredEntry), findsNothing);
    });

    testWidgets('yenile ve sayfa düğmeleri >= 44 dp dokunma hedefi', (t) async {
      final auth = _LogsAuth(report: _report());
      await pumpAt(t, _accordion(auth), width: 360, scale: 1.0);
      await _expand(t);
      final targets = <String, Finder>{
        'Yenile': find.byTooltip('Yenile'),
        'önceki sayfa': find.ancestor(
          of: find.byIcon(Icons.chevron_left_rounded),
          matching: find.byType(IconButton),
        ),
        'sonraki sayfa': find.ancestor(
          of: find.byIcon(Icons.chevron_right_rounded),
          matching: find.byType(IconButton),
        ),
      };
      for (final entry in targets.entries) {
        final size = t.getSize(entry.value.first);
        expect(size.width, greaterThanOrEqualTo(44), reason: entry.key);
        expect(size.height, greaterThanOrEqualTo(44), reason: entry.key);
      }
    });

    testWidgets('ilk yükleme: iskelet satırlar (tek ShimmerScope, "Yükleniyor"); spinner/boş durum yok', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final auth = _LogsAuth(never: true);
      await pumpAt(t, _accordion(auth), width: 412, scale: 1.0);
      await t.tap(find.text('Logları Gör'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(
        find.byType(SkeletonBox),
        findsNWidgets(12),
        reason: '3 satır x (küre + 2 satır + rozet)',
      );
      expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(InlineNotice), findsNothing);
      handle.dispose();
    });

    testWidgets('hata: InlineNotice (danger) mesajı birebir; açık ve koyu temada taşmaz', (
      t,
    ) async {
      for (final dark in const <bool>[false, true]) {
        final auth = _LogsAuth(error: 'Sunucu yanıt vermedi.');
        await pumpAt(
          t,
          _accordion(auth),
          width: 320,
          scale: 2.0,
          dark: dark,
        );
        await _expand(t);
        expect(find.byType(InlineNotice), findsOneWidget);
        expect(t.widget<InlineNotice>(find.byType(InlineNotice)).tone, AppTone.danger);
        expect(find.text('Sunucu yanıt vermedi.'), findsOneWidget);
      }
    });

    testWidgets('başlık küresi: çevrimiçi success, çevrimdışı warning', (t) async {
      for (final online in const <bool>[true, false]) {
        final auth = _LogsAuth(report: _report(online: online));
        await pumpAt(t, _accordion(auth, online: online), width: 412, scale: 1.0);
        final orb = t.widget<IconOrb>(
          find
              .ancestor(
                of: find.byIcon(Icons.history_toggle_off_rounded),
                matching: find.byType(IconOrb),
              )
              .first,
        );
        expect(orb.tone, online ? AppTone.success : AppTone.warning);
        expect(orb.size, 36);
      }
    });
  });
}
