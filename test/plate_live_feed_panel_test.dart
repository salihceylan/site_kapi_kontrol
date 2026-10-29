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

Map<String, dynamic> _row(int id, String plate, String kind, String? direction, {String? door = 'Ana Giriş', Map<String, dynamic>? identity, String? gateState}) => <String, dynamic>{
  'id': id,
  'plate': plate,
  'decision': kind == 'acildi' ? 'ALLOWED' : (kind == 'tanimsiz' ? 'UNKNOWN' : 'DENIED'),
  'decision_kind': kind,
  'direction': direction,
  'reason_label': 'x',
  'seen_at': DateTime.now().toUtc().toIso8601String(),
  'door_name': door,
  'identity': identity,
  'gate_state': gateState,
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
      for (final badge in <String>['İZİN VERİLDİ', 'RED', 'TANIMSIZ', 'KARA LİSTE']) {
        expect(find.text(badge), findsOneWidget);
      }
      final plate = tester.widget<Text>(find.text('34 ABC 123'));
      expect(plate.style?.fontFamily, 'monospace');
      expect(find.byIcon(Icons.south_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.north_rounded), findsOneWidget);
      expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Plaka 34 ABC 123, Giriş, İZİN VERİLDİ, Ana Giriş')), findsOneWidget);
      expect(find.text('AÇILDI'), findsNothing, reason: 'P1-15: kanıtsız "açıldı" yok');
      expect(find.byKey(const ValueKey<String>('plate_identity_text')), findsNothing, reason: 'kimlik yoksa satır HİÇ çizilmez');
      expect(find.textContaining('Kapı tetiklendi'), findsNothing);
      expect(find.textContaining('Kapı yanıt vermedi'), findsNothing);
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

    testWidgets('kimlik satırı: sakin "Daire … · Ali Y.", misafir "Misafir — Daire …"; tanımsızda ve kimliksizde satır yok; 320 dp taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeService(
        (_) => _feed(
          rows: <Map<String, dynamic>>[
            _row(5, '34 ABC 123', 'acildi', 'giris', identity: <String, dynamic>{'kind': 'resident', 'apartment_label': 'A Blok - 5', 'person_label': 'Ali Y.'}),
            _row(4, '06 MIS 22', 'acildi', 'giris', identity: <String, dynamic>{'kind': 'guest', 'apartment_label': 'A Blok - 5', 'person_label': null}),
            _row(3, '35 SOL 11', 'acildi', 'cikis', identity: <String, dynamic>{'kind': 'resident', 'apartment_label': null, 'person_label': 'Veli K.'}),
            _row(2, '35 DEF 456', 'tanimsiz', null, identity: null),
            _row(1, '16 KL 777', 'kara_liste', 'giris', identity: <String, dynamic>{'kind': 'bilinmeyen'}),
          ],
        ),
      );
      await _pump(tester, service);
      expect(tester.takeException(), isNull);
      expect(find.text('Daire A Blok - 5 · Ali Y.'), findsOneWidget);
      expect(find.text('Misafir — Daire A Blok - 5'), findsOneWidget);
      expect(find.text('Veli K.'), findsOneWidget, reason: 'daire etiketi yoksa yalnız kişi');
      expect(find.byKey(const ValueKey<String>('plate_identity_text')), findsNWidgets(3), reason: 'tanımsız ve bilinmeyen tür için satır yok');
      expect(find.bySemanticsLabel(RegExp('Plaka 34 ABC 123, Daire A Blok - 5 · Ali Y., Giriş, İZİN VERİLDİ')), findsOneWidget);
      await _close(tester);
    });

    testWidgets('kapı durumu rozeti: tetiklendi ✓ / yanıt vermedi ✗; durum yoksa rozet yok; "açıldı" denmez', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeService(
        (_) => _feed(
          rows: <Map<String, dynamic>>[
            _row(3, '34 ABC 123', 'acildi', 'giris', gateState: 'triggered'),
            _row(2, '06 XY 99', 'red', 'giris', gateState: 'no_response'),
            _row(1, '35 DEF 456', 'tanimsiz', null),
          ],
        ),
      );
      await _pump(tester, service);
      expect(tester.takeException(), isNull);
      expect(find.text('Kapı tetiklendi ✓'), findsOneWidget);
      expect(find.text('Kapı yanıt vermedi ✗'), findsOneWidget);
      expect(find.textContaining('açıldı'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Plaka 34 ABC 123, Giriş, İZİN VERİLDİ, Kapı tetiklendi, komut kabul edildi, Ana Giriş')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Plaka 06 XY 99, Giriş, RED, Kapı yanıt vermedi, Ana Giriş')), findsOneWidget);
      await _close(tester);
    });

    test('PlateDecisionRow: identity ve gate_state ayrıştırması (bilinmeyen değerler yok sayılır)', () {
      final row = PlateDecisionRow.fromJson(<String, dynamic>{
        'id': 1,
        'plate': '34ABC123',
        'identity': <String, dynamic>{'kind': 'guest', 'apartment_label': ' A - 2 ', 'person_label': ''},
        'gate_state': 'triggered',
      });
      expect(row.identity?.isGuest, isTrue);
      expect(row.identity?.apartmentLabel, 'A - 2');
      expect(row.identity?.personLabel, isNull);
      expect(row.gateState, 'triggered');
      final odd = PlateDecisionRow.fromJson(<String, dynamic>{'id': 2, 'plate': 'X', 'identity': 'x', 'gate_state': 'opened'});
      expect(odd.identity, isNull);
      expect(odd.gateState, isNull);
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
