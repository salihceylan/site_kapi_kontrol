// Online Tahsilat penceresi (FinanceOnlineCollectionDialog) + sakin "Online Öde" görünürlüğü (PayContent).
// Davranış: bağlantı yokken kurulum adımları; sır alanı maskeli ve kayıtlı sır geri gösterilmez; sınama sürücü etkin değilken DÜRÜST sonuç
// verir (başarı demez); kurul üyesi form görmez; "Online Öde" yalnız sunucu bayrağı true iken çizilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/payment_info.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_online_collection_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/pay_sheet.dart';

import 'dialog_layout_harness.dart';
import 'finance_fixtures.dart';

const _iyzico = CollectionProvider(
  code: 'iyzico',
  name: 'iyzico',
  driverActive: false,
  fields: <CollectionField>[
    CollectionField(key: 'api_key', label: 'API anahtarı', secret: true, required: true),
    CollectionField(key: 'merchant_id', label: 'Üye işyeri no (varsa)', secret: false, required: false),
  ],
);

class _FakeApi extends DeviceIntegrationsApi {
  _FakeApi() : super(baseUrl: 'http://localhost');

  OnlineCollectionState state = const OnlineCollectionState(status: 'none', providers: <CollectionProvider>[_iyzico]);
  final List<Map<String, String>> saved = <Map<String, String>>[];

  @override
  Future<OnlineCollectionState> onlineCollection(String token, int siteCode) async => state;

  @override
  Future<OnlineCollectionState> saveOnlineCollection(String token, int siteCode, {required String provider, required String mode, required Map<String, String> values}) async {
    saved.add(values);
    state = OnlineCollectionState(
      status: mode == 'live' ? 'configured_live' : 'configured_test',
      provider: provider,
      mode: mode,
      secretsSet: const <String, bool>{'api_key': true},
      complete: true,
      providers: const <CollectionProvider>[_iyzico],
    );
    return state;
  }

  @override
  Future<CollectionTestResult> testOnlineCollection(String token, int siteCode) async {
    const message = 'Alanlar geçerli ancak sağlayıcı sürücüsü bu sürümde etkin değil; gerçek bağlantı sınanmadı.';
    state = OnlineCollectionState(
      status: state.status,
      provider: state.provider,
      mode: state.mode,
      secretsSet: state.secretsSet,
      complete: true,
      lastTestStatus: 'driver_inactive',
      lastTestMessage: message,
      providers: const <CollectionProvider>[_iyzico],
    );
    return CollectionTestResult(ok: false, message: message, state: state);
  }
}

Future<void> _open(WidgetTester t, _FakeApi api, {bool canWrite = true}) async {
  final auth = FinanceFakeAuth.seeded();
  await openDialogAt(
    t,
    (context) => FinanceOnlineCollectionDialog.show(
      context,
      scope: PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite),
      service: DeviceIntegrationsService(authService: auth, api: api),
    ),
    width: 400,
    height: 1200,
    scale: 1.0,
    dark: false,
  );
  await settleFor(t);
}

void main() {
  layoutMatrix('Online Tahsilat penceresi', (t, width, height, scale, dark) async {
    final auth = FinanceFakeAuth.seeded();
    await openDialogAt(
      t,
      (context) => FinanceOnlineCollectionDialog.show(
        context,
        scope: PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true),
        service: DeviceIntegrationsService(authService: auth, api: _FakeApi()),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);
    expect(find.text('Online Tahsilat'), findsOneWidget);
    expect(find.text('Bağlantı kurulmadı'), findsOneWidget);
  });

  testWidgets('kurulum: bağlantı yokken adımlar görünür; kaydedince durum "test modu" olur; sır alanı maskeli, sınama dürüst sonuç verir', (t) async {
    final api = _FakeApi();
    await _open(t, api);
    expect(find.textContaining('Kurulum adımları'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('finance_online_test')), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('finance_online_provider_none')));
    await t.pump(const Duration(milliseconds: 450));
    await t.tap(find.text('iyzico').last);
    await t.pump(const Duration(milliseconds: 450));
    final secret = t.widget<TextField>(find.byKey(const ValueKey<String>('finance_online_field_api_key')));
    expect(secret.obscureText, isTrue);
    await t.enterText(find.byKey(const ValueKey<String>('finance_online_field_api_key')), 'abcdefgh12');
    await t.tap(find.byKey(const ValueKey<String>('finance_online_save')));
    await settleFor(t);
    expect(api.saved.single['api_key'], 'abcdefgh12');
    expect(find.text('Kuruldu — test modu'), findsOneWidget);
    // Kaydedilen sır forma geri YAZILMAZ.
    expect(find.text('abcdefgh12'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('finance_online_test')));
    await settleFor(t);
    expect(find.textContaining('etkin değil'), findsWidgets);
    expect(find.text('Bağlantı doğrulandı.'), findsNothing);
  });

  testWidgets('kurul üyesi (salt okur) formu ve düğmeleri görmez', (t) async {
    final api = _FakeApi()..state = const OnlineCollectionState(status: 'configured_live', provider: 'iyzico', mode: 'live', providers: <CollectionProvider>[_iyzico]);
    await _open(t, api, canWrite: false);
    expect(find.text('Kuruldu — canlı mod'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('finance_online_save')), findsNothing);
    expect(find.byKey(const ValueKey<String>('finance_online_remove')), findsNothing);
  });

  testWidgets('sakin: "Online Öde" yalnız sunucu bayrağı true iken çizilir; yoksa hiçbir şey eklenmez', (t) async {
    Future<void> pump(bool available) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PayContent(
                info: PaymentInfoItem(siteCode: 1, apartmentId: 2, onlinePaymentAvailable: available),
                amountMinor: 150000,
              ),
            ),
          ),
        ),
      );
    }

    await pump(false);
    expect(find.byKey(const ValueKey<String>('pay_online')), findsNothing);
    await pump(true);
    expect(find.byKey(const ValueKey<String>('pay_online')), findsOneWidget);
  });
}
