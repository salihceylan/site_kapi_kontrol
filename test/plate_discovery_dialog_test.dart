import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_discovery_dialog.dart';

import 'plate_cameras_support.dart';

const Duration _poll = Duration(seconds: 3);

EdgeSummary _edge({int clients = 1}) => EdgeSummary.fromJson(<String, dynamic>{
  'clients': <Map<String, dynamic>>[for (var i = 0; i < clients; i++) edgeClientJson(id: 3 + i, name: 'PC ${i + 1}')],
  'online': true,
  'count': clients,
});

/// Diyaloğu bir düğmeyle açar; sonuç [result] içinde toplanır.
Future<void> _open(WidgetTester tester, FakeCamerasService service, {EdgeSummary? edge, List<DiscoveryChoice?>? result}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final choice = await showPlateDiscoveryDialog(context, service: service, siteCode: 5, edge: edge ?? _edge(), pollInterval: _poll);
                result?.add(choice);
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('PlateDiscoveryDialog', () {
    testWidgets('bekliyor -> çalışıyor -> bitti: cihaz listesi gelir, cihaza dokununca seçim döner', (tester) async {
      final service = FakeCamerasService()
        ..discoveryPolls = <Map<String, dynamic>?>[
          commandJson(status: 'pending'),
          commandJson(status: 'running'),
          commandJson(status: 'done', result: discoveryResultJson()),
        ];
      final result = <DiscoveryChoice?>[];
      await _open(tester, service, result: result);
      expect(service.startCalls, 1);
      expect(find.text('Komut kenar PC\'ye iletiliyor…'), findsOneWidget);

      await tester.pump(_poll);
      await tester.pump();
      expect(find.text('Komut kenar PC\'ye iletiliyor…'), findsOneWidget, reason: 'yoklama 1: hâlâ bekliyor');
      await tester.pump(_poll);
      await tester.pump();
      expect(find.text('Aranıyor…'), findsOneWidget);
      await tester.pump(_poll);
      await tester.pump();
      expect(find.text('Aranıyor…'), findsNothing);
      expect(find.textContaining('2 cihaz bulundu'), findsOneWidget);
      expect(find.text('DS-2CD2043 · Hikvision'), findsOneWidget);
      expect(find.textContaining('192.168.1.64'), findsOneWidget);
      expect(find.textContaining('açık portlar: 554, 80, 8000'), findsOneWidget);
      expect(find.text('Yeniden ara'), findsOneWidget);

      final pollsBefore = service.pollCalls;
      await tester.pump(const Duration(seconds: 30));
      expect(service.pollCalls, pollsBefore, reason: 'bitince yoklama durur');

      await tester.tap(find.text('DS-2CD2043 · Hikvision'));
      await tester.pumpAndSettle();
      expect(result.single?.device?.ip, '192.168.1.64');
      expect(result.single?.manual, isFalse);
    });

    testWidgets('kenar PC çevrimdışı: dürüst uyarı (son görülme + bağlanmazsa iptal olur); sunucu süre bildirirse yazılır', (tester) async {
      final service = FakeCamerasService()
        ..startResponder = ((_) => DiscoveryStart(command: EdgeCommand.fromJson(commandJson(status: 'pending', waitingOffline: true)), reused: false))
        ..discoveryPolls = <Map<String, dynamic>?>[
          <String, dynamic>{...commandJson(status: 'pending', waitingOffline: true), 'ttl_seconds': 600},
        ];
      await _open(tester, service);
      expect(find.byKey(const ValueKey<String>('discovery_offline')), findsOneWidget);
      expect(find.textContaining('Kenar PC çevrimdışı'), findsOneWidget);
      expect(find.textContaining('son görülme'), findsOneWidget);
      expect(find.textContaining('Bağlanınca arama çalışır'), findsOneWidget);
      expect(find.textContaining('bağlanmazsa iptal olur'), findsOneWidget);
      expect(find.text('Kenar PC bekleniyor…'), findsOneWidget);
      await tester.pump(_poll);
      await tester.pump();
      expect(find.textContaining('10 dk içinde'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('discovery_close')));
      await tester.pumpAndSettle();
      final calls = service.pollCalls;
      await tester.pump(const Duration(minutes: 1));
      expect(service.pollCalls, calls, reason: 'diyalog kapanınca yoklama durur');
    });

    testWidgets('süresi dolan ya da başarısız arama: mesaj + yeniden dene yeni komut açar', (tester) async {
      final service = FakeCamerasService()
        ..startResponder = ((_) => DiscoveryStart(command: EdgeCommand.fromJson(commandJson(id: 12, status: 'expired', message: 'kenar komutu almadı')), reused: false));
      await _open(tester, service);
      expect(find.byKey(const ValueKey<String>('discovery_failed')), findsOneWidget);
      expect(find.textContaining('Arama süresi doldu'), findsOneWidget);
      expect(find.text('Yeniden dene'), findsOneWidget);

      service.startResponder = ((_) => DiscoveryStart(command: EdgeCommand.fromJson(commandJson(id: 13, status: 'failed', message: 'ağ kartı bulunamadı')), reused: false));
      await tester.tap(find.text('Yeniden dene'));
      await tester.pump();
      await tester.pump();
      expect(service.startCalls, 2);
      expect(find.textContaining('Arama başarısız oldu: ağ kartı bulunamadı'), findsOneWidget);
    });

    testWidgets('boş sonuç: "Ağda kamera bulunamadı" + Elle ekle seçimi döner', (tester) async {
      final service = FakeCamerasService()
        ..startResponder = ((_) => DiscoveryStart(command: EdgeCommand.fromJson(commandJson(status: 'done', result: <String, dynamic>{'devices': <Object>[], 'summary': 'Ağda kamera bulunamadı.'})), reused: false));
      final result = <DiscoveryChoice?>[];
      await _open(tester, service, result: result);
      expect(find.textContaining('Ağda kamera bulunamadı. Kameranın IP adresini'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('discovery_manual')));
      await tester.pumpAndSettle();
      expect(result.single?.manual, isTrue);
    });

    testWidgets('kenar istemci tanımlı değil: yönlendirme gösterilir, arama yapılmaz', (tester) async {
      final service = FakeCamerasService()
        ..startResponder = ((_) => throw ApiException('x', statusCode: 409, code: PlateCameraErrors.noEdgeClient));
      await _open(tester, service, edge: _edge(clients: 0));
      expect(find.textContaining('kenar uygulama'), findsOneWidget);
      expect(find.textContaining('Geçiş noktaları'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('birden çok kenar PC: önce seçim; seçilen kimlikle komut verilir', (tester) async {
      final service = FakeCamerasService();
      await _open(tester, service, edge: _edge(clients: 2));
      expect(service.startCalls, 0, reason: 'seçim yapılmadan komut verilmez');
      expect(find.byKey(const ValueKey<String>('discovery_edge_pick')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('discovery_edge_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PC 2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('discovery_start')));
      await tester.pump();
      await tester.pump();
      expect(service.startCalls, 1);
      expect(service.lastEdgeId, 4);
    });

    testWidgets('yoklama hatası geçici uyarıdır: liste/durum korunur ve yoklama sürer', (tester) async {
      var polls = 0;
      final service = FakeCamerasService();
      // latestDiscovery'yi ilk çağrıda hata, sonra başarı verecek şekilde sarmala.
      final wrapper = _FlakyPollService(service, failFirst: true, final_: commandJson(status: 'done', result: discoveryResultJson()));
      await _openWith(tester, wrapper);
      await tester.pump(_poll);
      await tester.pump();
      polls = wrapper.polls;
      expect(find.textContaining('Durum alınamadı'), findsOneWidget);
      expect(find.text('Komut kenar PC\'ye iletiliyor…'), findsOneWidget);
      await tester.pump(_poll);
      await tester.pump();
      expect(wrapper.polls, greaterThan(polls));
      expect(find.textContaining('Durum alınamadı'), findsNothing);
      expect(find.text('DS-2CD2043 · Hikvision'), findsOneWidget);
    });
  });
}

Future<void> _openWith(WidgetTester tester, PlateCamerasService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(onPressed: () => showPlateDiscoveryDialog(context, service: service, siteCode: 5, edge: _edge(), pollInterval: _poll), child: const Text('aç')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pump();
  await tester.pump();
}

/// İlk yoklamada hata veren, sonra bitmiş komut dönen sahte servis.
class _FlakyPollService extends FakeCamerasService {
  _FlakyPollService(FakeCamerasService base, {required this.failFirst, required this.final_}) : super(overview: base.overviewBody);

  final bool failFirst;
  final Map<String, dynamic> final_;
  int polls = 0;

  @override
  Future<EdgeCommand?> latestDiscovery(int site) async {
    polls++;
    if (failFirst && polls == 1) throw ApiException('Sunucuya bağlanılamadı.');
    return EdgeCommand.fromJson(final_);
  }
}
