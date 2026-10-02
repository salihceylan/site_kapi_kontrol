// FAZ 5 / A2-G4: WifiProvisionPage (Bluetooth ile Wi-Fi kurulumu) taşma ve davranış testleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema. Sayfa kendi `Scaffold`unu taşır:
// `pumpAt` gövdeyi `SingleChildScrollView` (sınırsız yükseklik) içine koyduğundan burada aynı ölçü/ölçek/
// tema/hareket düzeneği `harnessApp` ile kurulur (aynı 450 ms ilerletme + çerçeve hatası doğrulaması).
// BLE gerçek donanıma/izin kanalına DOKUNMAZ: `FakeBleService` (WifiProvisionPage.service) kullanılır.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/wifi_provision_page.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

const List<BleProvisionDevice> _devices = <BleProvisionDevice>[
  BleProvisionDevice(id: 'AA:BB:CC:DD:EE:01', name: 'AHBU-KAPI-01', rssi: -48),
  BleProvisionDevice(id: 'AA:BB:CC:DD:EE:02', name: 'AHBU-KAPI-02', rssi: -60),
  BleProvisionDevice(id: 'AA:BB:CC:DD:EE:03', name: 'AHBU-KAPI-03', rssi: -72),
  BleProvisionDevice(id: 'AA:BB:CC:DD:EE:04', name: 'AHBU-KAPI-04', rssi: -90),
];

const List<BleWifiNetwork> _networks = <BleWifiNetwork>[
  BleWifiNetwork(ssid: 'Ev_Modem_5G_Uzun_Ag_Adi', rssi: -50, secure: true),
  BleWifiNetwork(ssid: 'Misafir', rssi: -80, secure: false),
];

const BleWifiState _connectedState = BleWifiState(
  deviceUid: 'ESP32_C3_ABCDEF123456',
  wifiConnected: true,
  provisioning: true,
  hasCredentials: true,
  mqttConfigured: true,
  ssid: 'EvModem',
  ip: '192.168.1.45',
);

/// `pumpAt` ile aynı düzenek (ölçü, ölçek, tema, hareket azaltma, 450 ms, çerçeve hatası yok);
/// farkı: sayfanın kendi Scaffold'u için kaydırma sarmalayıcısı YOK.
Future<void> _pumpPage(
  WidgetTester t,
  WifiProvisionPage page, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    harnessApp(page, dark: dark, scale: scale, reduce: reduce),
  );
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull);
}

Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Future<void> _tapVisible(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
}

/// Cihaza bağlanmış sayfa: (cihaz bulundu -> ilk cihaza dokun -> bağlandı).
Future<void> _connect(WidgetTester t) async {
  await _tapVisible(t, find.text('AHBU-KAPI-01'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('taşma matrisi', () {
    g4LayoutMatrix('masaüstü: BLE desteklenmiyor bilgisi', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final service = FakeBleService(supported: false);
      await _pumpPage(
        t,
        WifiProvisionPage(service: service),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Kurulum Sırası'), findsOneWidget);
      expect(find.text('Bluetooth Cihazları'), findsOneWidget);
      expect(
        find.textContaining('Bu ekranı Android veya iPhone cihazdan açın'),
        findsOneWidget,
      );
      await _dispose(t);
    });

    g4LayoutMatrix('cihaz taraması sürüyor (iskelet)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final service = FakeBleService(scanGate: Completer<void>());
      await _pumpPage(
        t,
        WifiProvisionPage(service: service),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'başlıktaki yenile düğmesi tarama göstergesi (eski davranış)',
      );
      await _dispose(t);
    });

    g4LayoutMatrix('cihaz bulunamadı', (t, width, height, scale, dark) async {
      final service = FakeBleService();
      await _pumpPage(
        t,
        WifiProvisionPage(service: service),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(
        find.textContaining(
          'Kurulum modunda cihaz bulunamadı. Gerekirse cihazdaki butona 3 saniye basın ve yeniden tarayın.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ShimmerScope), findsNothing);
      await _dispose(t);
    });

    g4LayoutMatrix('4 cihaz, sinyal rozetleri', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final service = FakeBleService(devices: _devices);
      await _pumpPage(
        t,
        WifiProvisionPage(service: service),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('AHBU-KAPI-01'), findsOneWidget);
      expect(find.text('Çok güçlü (-48 dBm)'), findsOneWidget);
      expect(find.text('Güçlü (-60 dBm)'), findsOneWidget);
      expect(find.text('Orta (-72 dBm)'), findsOneWidget);
      expect(find.text('Zayıf (-90 dBm)'), findsOneWidget);
      await _dispose(t);
    });

    g4LayoutMatrix('bağlı cihaz paneli + taranmış ağlar + şifre alanı', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final service = FakeBleService(
        devices: _devices,
        networks: _networks,
        state: _connectedState,
      );
      await _pumpPage(
        t,
        WifiProvisionPage(service: service, authService: G4MqttAuth()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await _connect(t);

      expect(find.text('Bluetooth ID: AA:BB:CC:DD:EE:01'), findsOneWidget);
      expect(find.text('Unique ID: ESP32_C3_ABCDEF123456'), findsOneWidget);
      expect(find.text('Kayıtlı SSID: EvModem'), findsOneWidget);
      expect(find.text('Wi-Fi Durumu: Bağlı'), findsOneWidget);
      expect(find.text('IP: 192.168.1.45'), findsOneWidget);
      expect(find.text('MQTT Kimliği: Hazır'), findsOneWidget);

      await _tapVisible(t, find.text('Wi-Fi Ağlarını Tara'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Seçili Wi-Fi Ağı'), findsOneWidget);
      expect(find.text('Ev_Modem_5G_Uzun_Ag_Adi'), findsOneWidget);
      expect(find.text('Şifreli'), findsOneWidget);
      expect(find.text('Açık ağ'), findsOneWidget);
      expect(find.text('Wi-Fi Şifresi'), findsOneWidget);
      expect(find.text('Wi-Fi Bilgilerini Cihaza Kaydet'), findsOneWidget);
      await _dispose(t);
    });

    g4LayoutMatrix('Wi-Fi ağı taranıyor (iskelet) ve kaydediliyor (spinner)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final networksGate = Completer<void>();
      final provisionGate = Completer<void>();
      final service = FakeBleService(
        devices: _devices,
        networks: _networks,
        state: _connectedState,
        networksGate: networksGate,
        provisionGate: provisionGate,
      );
      await _pumpPage(
        t,
        WifiProvisionPage(service: service, authService: G4MqttAuth()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await _connect(t);

      // Ağ taraması sürüyor: satır iskeletleri + "Taranıyor..." etiketi.
      await _tapVisible(t, find.text('Wi-Fi Ağlarını Tara'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Taranıyor...'), findsOneWidget);
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(t.takeException(), isNull);

      // Tarama biter, şifre girilir, kayıt sürerken (bekleyen) düğme etiketi değişir.
      networksGate.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ShimmerScope), findsNothing);

      await t.enterText(find.byType(TextField), 'gizli-sifre');
      await t.pump();
      await _tapVisible(t, find.text('Wi-Fi Bilgilerini Cihaza Kaydet'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Bağlanıyor ve Kaydediliyor...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      provisionGate.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await _dispose(t);
    });
  });

  group('davranış (Kural 7 ve mevcut akış korunur)', () {
    testWidgets('açılışta otomatik tarama; yenile düğmesi yeniden tarar', (
      t,
    ) async {
      final service = FakeBleService(devices: _devices);
      await _pumpPage(t, WifiProvisionPage(service: service));
      expect(service.scans, 1, reason: 'sayfa açılınca cihaz taraması başlar');

      await _tapVisible(t, find.byIcon(Icons.refresh));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(service.scans, 2);
      expect(find.text('AHBU-KAPI-01'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets(
      'uçtan uca: cihaz seç -> ağları tara -> ağ + şifre -> kaydet; SnackBar ve çağrı',
      (t) async {
        final service = FakeBleService(
          devices: _devices,
          networks: _networks,
          state: _connectedState,
        );
        await _pumpPage(
          t,
          WifiProvisionPage(service: service, authService: G4MqttAuth()),
          height: 1400,
        );
        await _connect(t);

        await _tapVisible(t, find.text('Wi-Fi Ağlarını Tara'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        // İlk ağ varsayılan seçili; ikinciyi seç.
        await _tapVisible(t, find.text('Misafir'));
        await t.pump();
        await t.enterText(find.byType(TextField), 'misafir-sifresi');
        await t.pump();

        await _tapVisible(t, find.text('Wi-Fi Bilgilerini Cihaza Kaydet'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        expect(service.provisioned, [('Misafir', 'misafir-sifresi')]);
        expect(find.text('Wi-Fi ayarı kaydedildi.'), findsOneWidget);
        await _dispose(t);
      },
    );

    testWidgets(
      'şifre boşken kaydetmek uyarı verir ve cihaza yazılmaz (mevcut doğrulama)',
      (t) async {
        final service = FakeBleService(
          devices: _devices,
          networks: _networks,
          state: _connectedState,
        );
        await _pumpPage(
          t,
          WifiProvisionPage(service: service, authService: G4MqttAuth()),
          height: 1400,
        );
        await _connect(t);
        await _tapVisible(t, find.text('Wi-Fi Ağlarını Tara'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        await _tapVisible(t, find.text('Wi-Fi Bilgilerini Cihaza Kaydet'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        expect(find.text('Seçilen ağ için şifre girin.'), findsWidgets);
        expect(service.provisioned, isEmpty);
        await _dispose(t);
      },
    );

    testWidgets(
      'sinyal rozeti tonları: çok güçlü=başarı, güçlü=bilgi, orta=uyarı, zayıf=hata',
      (t) async {
        final service = FakeBleService(devices: _devices);
        await _pumpPage(t, WifiProvisionPage(service: service), height: 1400);

        AppTone toneOf(String label) =>
            t.widget<StatusChip>(find.widgetWithText(StatusChip, label)).tone;
        expect(toneOf('Çok güçlü (-48 dBm)'), AppTone.success);
        expect(toneOf('Güçlü (-60 dBm)'), AppTone.info);
        expect(toneOf('Orta (-72 dBm)'), AppTone.warning);
        expect(toneOf('Zayıf (-90 dBm)'), AppTone.danger);
        await _dispose(t);
      },
    );

    testWidgets(
      'seçili cihaz kartı vurgulanır (1,5 px kenar); tarama sırasında cihaz satırı dokunulabilir kalır',
      (t) async {
        final service = FakeBleService(
          devices: _devices,
          state: _connectedState,
        );
        await _pumpPage(t, WifiProvisionPage(service: service), height: 1400);
        await _connect(t);

        final selected = t.widget<ListTile>(
          find.widgetWithText(ListTile, 'AHBU-KAPI-01'),
        );
        expect(selected.selected, isTrue);
        final other = t.widget<ListTile>(
          find.widgetWithText(ListTile, 'AHBU-KAPI-02'),
        );
        expect(other.selected, isFalse);
        await _dispose(t);
      },
    );
  });

  group('AppBar kontrastı (rol rengi üstünde başlık >= 4,5:1)', () {
    for (final entry in <(String, Color)>[
      ('süper kullanıcı (mavi)', const Color(0xFF3B82F6)),
      ('site yöneticisi (zümrüt)', const Color(0xFF10B981)),
      ('bireysel/sakin (mor)', const Color(0xFFA855F7)),
      ('bilinmeyen açık renk', const Color(0xFFFFEB3B)),
      ('varsayılan (accentColor yok)', Colors.transparent),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${entry.$1}, ${dark ? 'koyu' : 'açık'} tema', (t) async {
          final service = FakeBleService(devices: _devices);
          final accent = entry.$2 == Colors.transparent ? null : entry.$2;
          await _pumpPage(
            t,
            WifiProvisionPage(service: service, accentColor: accent),
            dark: dark,
          );

          final bar = t.widget<AppBar>(find.byType(AppBar));
          final background = bar.backgroundColor!;
          final foreground = bar.foregroundColor!;
          expect(
            _contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: 'AppBar ön plan/arka plan',
          );
          expect(
            bar.titleTextStyle!.color,
            foreground,
            reason: 'başlık metni de aynı okunur renkte',
          );
          await _dispose(t);
        });
      }
    }
  });

  group('mevcut düzen korunur', () {
    testWidgets(
      'sayfa arka planı gövdeyi doldurur (E2E bulgusu: altta koyu şerit)',
      (t) async {
        final service = FakeBleService(devices: _devices);
        await _pumpPage(
          t,
          WifiProvisionPage(
            service: service,
            surfaceColor: const Color(0xFF1A2555),
          ),
          width: 412,
          height: 915,
        );

        final background = find.byKey(
          const ValueKey<String>('wifi_provision_background'),
        );
        expect(background, findsOneWidget);
        final backgroundSize = t.getSize(background);
        final scaffoldSize = t.getSize(find.byType(Scaffold).last);
        final appBarHeight = t.getSize(find.byType(AppBar)).height;
        expect(backgroundSize.width, closeTo(scaffoldSize.width, 0.5));
        expect(
          backgroundSize.height,
          closeTo(scaffoldSize.height - appBarHeight, 0.5),
        );
        await _dispose(t);
      },
    );

    testWidgets(
      'hareket azaltma: tarama iskeleti durağandır (tek pump ile son görünüm)',
      (t) async {
        final service = FakeBleService(scanGate: Completer<void>());
        await _pumpPage(t, WifiProvisionPage(service: service), reduce: true);
        expect(find.byType(ShimmerScope), findsOneWidget);
        await _dispose(t);
      },
    );
  });
}
