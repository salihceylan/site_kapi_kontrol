import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_live_feed_panel.dart';

class _FakeService extends Fake implements PlateRecognitionService {
  _FakeService(this.responder);

  final PlateLiveFeed Function(int call) responder;
  int calls = 0;

  @override
  Future<PlateLiveFeed> liveFeed(int site, {int? limit}) async {
    calls++;
    return responder(calls);
  }
}

Map<String, dynamic> _row(int id, String plate, String kind, String? direction, {String? door = 'Ana Giriş'}) => <String, dynamic>{
  'id': id,
  'plate': plate,
  'decision': kind == 'acildi' ? 'ALLOWED' : (kind == 'tanimsiz' ? 'UNKNOWN' : 'DENIED'),
  'decision_kind': kind,
  'direction': direction,
  'reason_label': 'x',
  'seen_at': DateTime.now().toUtc().toIso8601String(),
  'door_name': door,
};

PlateLiveFeed _feed({int inside = 7, int refresh = 5, List<Map<String, dynamic>>? rows}) => PlateLiveFeed.fromJson(<String, dynamic>{
  'inside_count': inside,
  'refresh_seconds': refresh,
  'limit': 30,
  'events': rows ??
      <Map<String, dynamic>>[
        _row(4, '34 ABC 123', 'acildi', 'giris'),
        _row(3, '06 XY 99', 'red', 'cikis', door: 'Yan Kapı'),
        _row(2, '35 DEF 456', 'tanimsiz', null),
        _row(1, '16 KL 777', 'kara_liste', 'giris'),
      ],
});

Future<void> _pump(WidgetTester tester, _FakeService service) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PlateLiveFeedPanel(service: service, siteCode: 1)))));
  await tester.pump();
  await tester.pump();
}

Future<void> _close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('PlateLiveFeedPanel', () {
    testWidgets('sayaç, yön, monospace plaka ve dört karar rozeti 320 dp genişlikte taşmadan çizilir', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeService((_) => _feed());
      await _pump(tester, service);

      expect(tester.takeException(), isNull);
      expect(find.text('İçeride: 7 araç', findRichText: true), findsOneWidget);
      for (final badge in <String>['AÇILDI', 'RED', 'TANIMSIZ', 'KARA LİSTE']) {
        expect(find.text(badge), findsOneWidget);
      }
      final plate = tester.widget<Text>(find.text('34 ABC 123'));
      expect(plate.style?.fontFamily, 'monospace');
      expect(find.byIcon(Icons.south_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.north_rounded), findsOneWidget);
      expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Plaka 34 ABC 123, Giriş, AÇILDI, Ana Giriş')), findsOneWidget);
      expect(find.bySemanticsLabel('İçeride 7 araç'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('sunucunun söylediği aralıkta kendiliğinden yenilenir; kapatılınca durur, açılınca hemen yeniler', (tester) async {
      final service = _FakeService((call) => _feed(inside: call, refresh: 7));
      await _pump(tester, service);
      expect(service.calls, 1);
      await tester.pump(const Duration(seconds: 6));
      expect(service.calls, 1, reason: 'aralık 7 sn (istemcide sabit 5 sn yok)');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(service.calls, 2);
      expect(find.text('İçeride: 2 araç', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('live_auto')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(service.calls, 2, reason: 'otomatik yenileme kapalı');
      expect(find.text('Otomatik yenileme kapalı'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('live_auto')));
      await tester.pump();
      await tester.pump();
      expect(service.calls, 3);
      await _close(tester);
    });

    testWidgets('boş durum: "Henüz geçiş yok"', (tester) async {
      final service = _FakeService((_) => _feed(inside: 0, rows: const <Map<String, dynamic>>[]));
      await _pump(tester, service);
      expect(find.text('Henüz geçiş yok'), findsOneWidget);
      expect(find.text('İçeride: 0 araç', findRichText: true), findsOneWidget);
      await _close(tester);
    });

    testWidgets('bağlantı hatası: ilk yüklemede zarif hata + yeniden dene; sonradan hatada son liste korunur', (tester) async {
      final service = _FakeService((call) {
        if (call == 1 || call == 3) throw ApiException('Sunucuya ulaşılamadı.');
        return _feed();
      });
      await _pump(tester, service);
      expect(find.text('Bağlantı kurulamadı'), findsOneWidget);
      expect(find.text('Sunucuya ulaşılamadı.'), findsOneWidget);

      await tester.tap(find.text('Yeniden dene'));
      await tester.pump();
      await tester.pump();
      expect(find.text('34 ABC 123'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.textContaining('Bağlantı kesildi; son bilinen liste gösteriliyor.'), findsOneWidget);
      expect(find.text('34 ABC 123'), findsOneWidget, reason: 'hata son listeyi silmez');
      await _close(tester);
    });

    test('liveDecisionOf: karar türü yoksa eski decision alanından türetilir', () {
      PlateDecisionRow row(String decision, [String? kind]) =>
          PlateDecisionRow.fromJson(<String, dynamic>{'id': 1, 'plate': '34ABC123', 'decision': decision, 'decision_kind': kind});
      expect(liveDecisionOf(row('ALLOWED')), LiveDecision.acildi);
      expect(liveDecisionOf(row('DENIED')), LiveDecision.red);
      expect(liveDecisionOf(row('UNKNOWN')), LiveDecision.tanimsiz);
      expect(liveDecisionOf(row('DENIED', 'kara_liste')), LiveDecision.karaListe);
    });
  });
}
