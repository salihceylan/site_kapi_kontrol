// İşletme projesi ayrıntısı: üst çubuktaki "Ana sayfa" düğmesi form taşıyan bir ekrandadır (taslakta kalem tutarı kutuları).
// `popUntil` sayfanın kendi korumasını atladığından düğme, kaydedilmemiş tutarı sormadan ATMAMALI (docs/TASARIM_DILI.md,
// "Ana sayfa" düğmesi > derin ekranlar). Kaydedilmemiş tutar yoksa (temiz taslak, geri yazılmış değer, salt okur) doğrudan Panel'e döner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/budget_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/budget_api.dart';
import 'package:site_kapi_kontrol/services/panel_return_requests.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/views/budget_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'people_fixtures.dart' show PeopleFakeAuth;

class _FakeBudgetService extends BudgetService {
  _FakeBudgetService({required super.authService}) : super(api: BudgetApi(baseUrl: 'http://localhost'));

  @override
  Future<BudgetDetail> get(int siteCode, int id) async => BudgetDetail.fromJson(<String, dynamic>{
    'project': <String, dynamic>{'id': id, 'year': 2027, 'title': '2027 yılı işletme projesi', 'status': 'taslak'},
    'items': <Map<String, dynamic>>[],
  });

  @override
  Future<List<ExpenseCategory>> categories(int siteCode) async => <ExpenseCategory>[
    ExpenseCategory.fromJson(<String, dynamic>{'id': 1, 'name': 'Asansör'}),
    ExpenseCategory.fromJson(<String, dynamic>{'id': 2, 'name': 'Temizlik'}),
  ];
}

final Finder _homeButton = find.byKey(const ValueKey<String>('ana_sayfa_dugmesi'));
final Finder _discardTitle = find.text('Kaydedilmemiş değişiklikler');

/// Kabuk yerine geçen ilk sayfa + onun üstüne itilmiş proje ayrıntısı. Dönen sayaç, Panel'e dönüş isteği sayısıdır
/// ([PanelReturnRequests]: gerçek kabuk bunu dinleyip Panel'i seçer).
Future<List<int>> _openDetail(WidgetTester t, {bool canWrite = true}) async {
  final requests = <int>[0];
  void onRequest() => requests[0]++;
  PanelReturnRequests.instance.addListener(onRequest);
  addTearDown(() => PanelReturnRequests.instance.removeListener(onRequest));

  t.view.physicalSize = const Size(400, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final auth = PeopleFakeAuth();
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BudgetDetailPage(
                    service: _FakeBudgetService(authService: auth),
                    site: BudgetSite(code: 11, name: 'Gül Sitesi', canWrite: canWrite),
                    projectId: 7,
                  ),
                ),
              ),
              child: const Text('Projeyi aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Projeyi aç'));
  await settleFor(t, 600);
  expect(find.byType(BudgetDetailPage), findsOneWidget);
  return requests;
}

Future<void> _type(WidgetTester t, String label, String value) async {
  await t.enterText(find.widgetWithText(TextField, label), value);
  await t.pump();
}

void main() {
  testWidgets('temiz taslakta düğme sormadan tüm ekranları kapatır ve Panel\'e dönüş ister', (t) async {
    final requests = await _openDetail(t);
    expect(find.widgetWithText(TextField, 'Asansör'), findsOneWidget, reason: 'taslak + yazma yetkisi: tutar kutuları var');
    expect(_homeButton, findsOneWidget);

    await t.tap(_homeButton);
    await settleFor(t, 600);

    expect(_discardTitle, findsNothing);
    expect(find.byType(BudgetDetailPage), findsNothing, reason: 'ayrıntı ekranı kapandı');
    expect(find.text('Projeyi aç'), findsOneWidget, reason: 'ilk sayfaya (kabuğa) dönüldü');
    expect(requests[0], 1, reason: 'kabuğa Panel isteği iletildi');
    expect(t.takeException(), isNull);
  });

  testWidgets('kaydedilmemiş tutar varken önce sorar: "Düzenlemeye Dön" ekranda bırakır ve yazılan tutar korunur', (t) async {
    final requests = await _openDetail(t);
    await _type(t, 'Asansör', '1250');

    await t.tap(_homeButton);
    await settleFor(t, 600);

    expect(_discardTitle, findsOneWidget);
    expect(find.textContaining('Kalem tutarlarında kaydedilmemiş değişiklikleriniz var'), findsOneWidget);
    expect(find.text('Düzenlemeye Dön'), findsOneWidget);
    expect(find.text('Değişiklikleri Sil'), findsOneWidget);
    expect(find.byType(BudgetDetailPage), findsOneWidget, reason: 'onay beklenirken ekran açık');
    expect(requests[0], 0);

    await t.tap(find.text('Düzenlemeye Dön'));
    await settleFor(t, 600);

    expect(_discardTitle, findsNothing);
    expect(find.byType(BudgetDetailPage), findsOneWidget, reason: 'vazgeçildi: ekranda kaldı');
    expect(t.widget<TextField>(find.widgetWithText(TextField, 'Asansör')).controller!.text, '1250', reason: 'yazılan tutar kaybolmadı');
    expect(requests[0], 0, reason: 'Panel isteği gitmedi');
    expect(t.takeException(), isNull);
  });

  testWidgets('"Değişiklikleri Sil" onayından sonra Panel\'e döner (tutar kaydedilmez)', (t) async {
    final requests = await _openDetail(t);
    await _type(t, 'Temizlik', '980,50');

    await t.tap(_homeButton);
    await settleFor(t, 600);
    expect(_discardTitle, findsOneWidget);

    await t.tap(find.text('Değişiklikleri Sil'));
    await settleFor(t, 600);

    expect(find.byType(BudgetDetailPage), findsNothing);
    expect(find.text('Projeyi aç'), findsOneWidget);
    expect(requests[0], 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('yazılıp kayıtlı değere geri alınan tutar kaydedilmemiş sayılmaz (sormadan döner)', (t) async {
    final requests = await _openDetail(t);
    await _type(t, 'Asansör', '500');
    await _type(t, 'Asansör', '');

    await t.tap(_homeButton);
    await settleFor(t, 600);

    expect(_discardTitle, findsNothing);
    expect(find.byType(BudgetDetailPage), findsNothing);
    expect(requests[0], 1);
  });

  testWidgets('salt okur görünümde (yazma yetkisi yok) tutar kutusu yoktur: sormadan döner', (t) async {
    final requests = await _openDetail(t, canWrite: false);
    expect(find.byType(TextField), findsNothing);

    await t.tap(_homeButton);
    await settleFor(t, 600);

    expect(_discardTitle, findsNothing);
    expect(find.byType(BudgetDetailPage), findsNothing);
    expect(requests[0], 1);
  });
}
