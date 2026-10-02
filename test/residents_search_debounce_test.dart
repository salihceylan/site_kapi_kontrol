// FAZ 5 / P-e: sakin ağacı penceresinde arama süzmesi yazma durunca uygulanır; hızlı yazımda
// yüzlerce kartın tamamı her tuş vuruşunda yeniden kurulmaz. Sonuç eskisiyle aynıdır.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_residents_tree_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_residents_accordion_dialog.dart';

import 'support/rebuild_probe.dart';

Map<String, dynamic> _member(int code, String name) => {
      'user_code': code,
      'full_name': name,
      'email': 'u$code@example.com',
      'role': 'FAMILY_MEMBER',
      'is_active': true,
      'account_is_active': true,
    };

Map<String, dynamic> _tree() => {
      'site': {'id': 101, 'name': 'Güneş Sitesi', 'total_blocks': 1, 'total_apartments': 3, 'total_residents': 3},
      'blocks': [
        {
          'id': 11,
          'block_name': 'A Blok',
          'sort_order': 1,
          'total_apartments': 3,
          'total_residents': 3,
          'apartments': [
            {
              'id': 501,
              'block_id': 11,
              'unit_label': 'Daire 1',
              'sort_order': 1,
              'total_residents': 1,
              'residents': [_member(1, 'Ayşe Yılmaz')],
            },
            {
              'id': 502,
              'block_id': 11,
              'unit_label': 'Daire 2',
              'sort_order': 2,
              'total_residents': 1,
              'residents': [_member(2, 'Mehmet Kaya')],
            },
            {
              'id': 503,
              'block_id': 11,
              'unit_label': 'Daire 3',
              'sort_order': 3,
              'total_residents': 1,
              'residents': [_member(3, 'Zeynep Demir')],
            },
          ],
        },
      ],
    };

class _Auth extends AuthService {
  _Auth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  Future<(SiteResidentsTreeData?, String?)> getSiteResidentsTree(int siteCode) async =>
      (SiteResidentsTreeData.fromJson(_tree()), null);
}

SiteRecord _site() => SiteRecord.fromJson({
      'id': 101,
      'name': 'Güneş Sitesi',
      'block_count': 1,
      'apartment_count': 3,
      'door_count': 1,
    });

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => SiteResidentsAccordionDialog.show(context, site: _site(), authService: _Auth()),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(RebuildProbe.stop);

  testWidgets('ÖLÇÜM: 6 hızlı tuş vuruşu tek süzme/yeniden kurma üretir; sonuç aynıdır', (tester) async {
    await _open(tester);
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsOneWidget);

    RebuildProbe.start();
    const typed = ['M', 'Me', 'Meh', 'Mehm', 'Mehme', 'Mehmet'];
    for (final text in typed) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 40)); // hızlı yazım
    }
    final tilesWhileTyping = RebuildProbe.count(ExpansionTile);
    // Yazma bitti: süzme uygulanır.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final tilesTotal = RebuildProbe.count(ExpansionTile);
    print('ÖLÇÜM 6 tuş: yazarken ExpansionTile yeniden kurma=$tilesWhileTyping, süzme sonrası toplam=$tilesTotal');

    expect(tilesWhileTyping, 0, reason: 'yazma sürerken liste yeniden kurulmaz');
    expect(find.text('Mehmet Kaya'), findsOneWidget);
    expect(find.text('Ayşe Yılmaz'), findsNothing, reason: 'süzme sonucu eskisiyle aynı');
    expect(find.text('Zeynep Demir'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temizle düğmesi aramayı ve listeyi hemen sıfırlar', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'Zeynep');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Ayşe Yılmaz'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsOneWidget);
    expect(find.text('Zeynep Demir'), findsOneWidget);
  });

  testWidgets('bekleyen arama zamanlayıcısı pencere kapanınca temizlenir', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'Mehmet');
    await tester.pump(const Duration(milliseconds: 50));
    // Süzme uygulanmadan pencereyi kapat: bekleyen Timer kalırsa flutter_test testi başarısız kılar.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
