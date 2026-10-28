// Kart Ödemesi penceresi (FinanceCardPaymentsDialog): Aidat ve Finans'ın parçası (eski `card_payments` modülü kaldırıldı).
//
// AGENTS.md kural 6: dört hücre (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) x açık / koyu; taşma yok.
// Davranış: sağlayıcılar "Yakında…" etiketiyle listelenir; yönetici komisyon notunu düzenler ve kaydeder, kurul üyesi (salt okur)
// düzenleme düğmesi görmez; yükleme hatası yeniden denenir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_card_payments_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'finance_fixtures.dart';

class _FakeApi extends DeviceIntegrationsApi {
  _FakeApi() : super(baseUrl: 'http://localhost');

  final Map<String, String?> notes = <String, String?>{'iyzico': null, 'paytr': 'Eski not'};
  int failLoads = 0;
  int loads = 0;
  final List<String> saves = <String>[];

  PaymentOverview _overview() => PaymentOverview(
    notice: 'Kart ödeme komisyonu ödemeyi yapana (ev sahibi / kiracı) yansıtılır.',
    providers: <PaymentProviderInfo>[
      PaymentProviderInfo(code: 'iyzico', name: 'iyzico', commissionInfo: notes['iyzico']),
      PaymentProviderInfo(code: 'paytr', name: 'PayTR', commissionInfo: notes['paytr']),
    ],
  );

  @override
  Future<PaymentOverview> payments(String token, int siteCode) async {
    loads++;
    if (failLoads > 0) {
      failLoads--;
      throw ApiException('Sunucuya bağlanılamadı.');
    }
    return _overview();
  }

  @override
  Future<PaymentOverview> saveCommissionInfo(String token, int siteCode, String provider, String info) async {
    saves.add('$siteCode/$provider/$info');
    notes[provider] = info.trim().isEmpty ? null : info.trim();
    return _overview();
  }
}

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Future<void> _open(
  WidgetTester t,
  FinanceFakeAuth auth,
  _FakeApi api, {
  bool canWrite = true,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  await openDialogAt(
    t,
    (context) => FinanceCardPaymentsDialog.show(
      context,
      scope: _scope(auth, canWrite: canWrite),
      service: DeviceIntegrationsService(authService: auth, api: api),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

void main() {
  layoutMatrix('Kart Ödemesi penceresi', (t, width, height, scale, dark) async {
    await _open(t, FinanceFakeAuth.seeded(), _FakeApi(), width: width, height: height, scale: scale, dark: dark);
    expect(find.text('Kart Ödemesi'), findsOneWidget);
    expect(find.text('iyzico'), findsOneWidget);
    expect(find.text('PayTR'), findsOneWidget);
    expect(find.text('Yakında…'), findsNWidgets(2));
  });

  testWidgets('sağlayıcılar Yakında etiketiyle ve komisyon notuyla listelenir; yönetici düzenleme düğmesini görür', (t) async {
    await _open(t, FinanceFakeAuth.seeded(), _FakeApi());
    expect(find.text('Komisyon notu yok'), findsOneWidget);
    expect(find.text('Eski not'), findsOneWidget);
    expect(find.byTooltip('Komisyon notunu düzenle'), findsNWidgets(2));
    expect(find.textContaining('Kartla ödeme henüz açık değil'), findsOneWidget);
  });

  testWidgets('kurul üyesi (salt okur) düzenleme düğmesini görmez', (t) async {
    await _open(t, FinanceFakeAuth.seeded(), _FakeApi(), canWrite: false);
    expect(find.text('iyzico'), findsOneWidget);
    expect(find.byTooltip('Komisyon notunu düzenle'), findsNothing);
  });

  testWidgets('yönetici komisyon notunu kaydeder: istek doğru sağlayıcıya gider, not satırda görünür', (t) async {
    final api = _FakeApi();
    await _open(t, FinanceFakeAuth.seeded(), api);
    await t.tap(find.byTooltip('Komisyon notunu düzenle').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 450));
    await t.enterText(find.byKey(const ValueKey<String>('finance_card_payments_note_field')), '  %2,5 + 0,25 TL  ');
    await t.tap(find.byKey(const ValueKey<String>('finance_card_payments_note_save')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 450));
    expect(api.saves, <String>['11/iyzico/  %2,5 + 0,25 TL  ']);
    expect(find.text('%2,5 + 0,25 TL'), findsOneWidget);
    expect(find.text('Bilgi kaydedildi.'), findsOneWidget);
  });

  testWidgets('yükleme hatası mesajla gösterilir ve Tekrar dene ile yeniden denenir', (t) async {
    final api = _FakeApi()..failLoads = 1;
    await _open(t, FinanceFakeAuth.seeded(), api);
    expect(find.byKey(const ValueKey<String>('finance_card_payments_error')), findsOneWidget);
    expect(find.text('iyzico'), findsNothing);
    await t.tap(find.text('Tekrar dene'));
    await settleFor(t);
    expect(api.loads, 2);
    expect(find.byKey(const ValueKey<String>('finance_card_payments_error')), findsNothing);
    expect(find.text('iyzico'), findsOneWidget);
  });

  testWidgets('Kapat pencereyi kapatır', (t) async {
    await _open(t, FinanceFakeAuth.seeded(), _FakeApi());
    await t.tap(find.byKey(const ValueKey<String>('finance_card_payments_close')));
    await settleFor(t);
    expect(find.byType(FinanceCardPaymentsDialog), findsNothing);
  });
}
