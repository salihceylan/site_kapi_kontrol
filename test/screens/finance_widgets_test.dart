// Platform Faz 4a: ortak finans bileşenleri — para alanı (MoneyFormField), dağıtım formu (FeeSpecForm), hedef seçici
// (FinanceTargetPicker), idempotency anahtarı ve modül kartı (finance "Aidat ve Finans" available).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/fee_spec_form.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_target_picker.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'finance_fixtures.dart';
import 'list_fixtures.dart';
import 'modules_fixtures.dart';

PeopleScope _scope(FinanceFakeAuth auth) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);

class _MoneyHost extends StatefulWidget {
  const _MoneyHost({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<_MoneyHost> createState() => _MoneyHostState();
}

class _MoneyHostState extends State<_MoneyHost> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  bool banner = false;

  void showBanner() => setState(() => banner = true);

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          if (banner) const Text('özet'),
          MoneyFormField(
            key: const ValueKey<String>('m'),
            fieldKey: const ValueKey<String>('money'),
            controller: widget.controller,
            label: 'Tutar',
          ),
        ],
      ),
    );
  }
}

void main() {
  group('MoneyFormField', () {
    testWidgets('yazarken ayrıştırılan tutar gösterilir; geçersizde gösterilmez', (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpList(
        t,
        Form(
          child: MoneyFormField(key: const ValueKey<String>('m'), controller: controller, label: 'Tutar'),
        ),
        width: 400,
        height: 600,
        scale: 1.0,
        dark: false,
      );
      await t.enterText(find.byType(TextFormField), '1.250,5');
      await t.pump();
      expect(find.text('Girilen tutar: 1.250,50 ₺'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), '12,345');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('money_preview')), findsNothing);
    });

    testWidgets('harf girişi süzülür; eksi işareti KORUNUR (sessizce pozitife çevrilmez)', (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpList(
        t,
        Form(
          child: MoneyFormField(key: const ValueKey<String>('m'), controller: controller, label: 'Tutar'),
        ),
        width: 400,
        height: 600,
        scale: 1.0,
        dark: false,
      );
      await t.enterText(find.byType(TextFormField), 'abc12,5x');
      await t.pump();
      expect(controller.text, '12,5');
      await t.enterText(find.byType(TextFormField), '-50');
      await t.pump();
      expect(controller.text, '-50', reason: 'eksi işareti korunur; doğrulayıcı "negatif olamaz" der');
      expect(validateMoneyInput(controller.text), 'Tutar negatif olamaz.');
    });

    testWidgets('doğrulama hatası üst Column yapısı değişse de KAYBOLMAZ (anahtarlı alan)', (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final hostKey = GlobalKey<_MoneyHostState>();
      await pumpList(
        t,
        _MoneyHost(key: hostKey, controller: controller),
        width: 400,
        height: 600,
        scale: 1.0,
        dark: false,
      );
      expect(hostKey.currentState!.formKey.currentState!.validate(), isFalse);
      await t.pump();
      expect(find.text('Tutarı girin.'), findsOneWidget);
      // Yapı değişir (üste bir öğe eklenir): anahtarsız alan yeniden kurulur ve hatayı kaybederdi.
      hostKey.currentState!.showBanner();
      await t.pump();
      expect(find.text('özet'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
    });

    testWidgets('isteğe bağlı alan: boş geçerli, dolu ve bozuksa hata', (t) async {
      expect(validateMoneyInput('', required: false), isNull);
      expect(validateMoneyInput('abc', required: false), isNotNull);
    });
  });

  group('FeeSpecForm', () {
    Future<GlobalKey<FeeSpecFormState>> pumpSpec(
      WidgetTester t,
      FinanceFakeAuth auth, {
      FeeDistribution distribution = FeeDistribution.fixed,
      int? amount,
      Map<String, int> categories = const <String, int>{},
      FeeTarget target = const FeeTarget(),
      double width = 400,
      double scale = 1.0,
    }) async {
      final key = GlobalKey<FeeSpecFormState>();
      await pumpList(
        t,
        Form(
          child: FeeSpecForm(
            key: key,
            scope: _scope(auth),
            initialDistribution: distribution,
            initialAmountMinor: amount,
            initialCategoryAmounts: categories,
            initialTarget: target,
          ),
        ),
        width: width,
        height: 3000,
        scale: scale,
        dark: false,
      );
      await settleFor(t);
      return key;
    }

    testWidgets('sabit: read() kuruşu verir; geçersiz tutarda null', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpSpec(t, auth, amount: 123456);
      final spec = key.currentState!.read()!;
      expect(spec.distribution, FeeDistribution.fixed);
      expect(spec.amountMinor, 123456);
      expect(spec.target, const FeeTarget());
      await t.enterText(find.byKey(const ValueKey<String>('fee_spec_amount')), '12,345');
      await t.pump();
      expect(key.currentState!.read(), isNull);
    });

    testWidgets('kategori: başlangıç haritası satırlara dökülür, read() haritayı kuruş olarak verir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpSpec(
        t,
        auth,
        distribution: FeeDistribution.category,
        categories: const <String, int>{'3+1': 75050, '2+1': 50000},
      );
      expect(find.byKey(const ValueKey<String>('fee_spec_category_name_0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fee_spec_category_name_1')), findsOneWidget);
      final spec = key.currentState!.read()!;
      expect(spec.categoryAmounts, <String, int>{'3+1': 75050, '2+1': 50000});
      expect(spec.amountMinor, isNull);
      expect(key.currentState!.validateExtras(), isTrue);
    });

    testWidgets('en çok 30 kategori eklenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await pumpSpec(t, auth, distribution: FeeDistribution.category);
      for (var i = 0; i < 40; i++) {
        final add = find.byKey(const ValueKey<String>('fee_spec_add_category'));
        await t.ensureVisible(add);
        await t.pump();
        await t.tap(add);
        await t.pump();
      }
      expect(find.byKey(const ValueKey<String>('fee_spec_category_error')), findsOneWidget);
      expect(find.text('En çok 30 kategori eklenebilir.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fee_spec_category_name_29')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fee_spec_category_name_30')), findsNothing);
    });

    testWidgets('yönteme göre etiket / açıklama: m² için alan esası seçilir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpSpec(t, auth, amount: 100000);
      await t.tap(find.byKey(const ValueKey<String>('fee_spec_dist_area')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('fee_spec_area_net')));
      await t.pump();
      final spec = key.currentState!.read()!;
      expect(spec.distribution, FeeDistribution.area);
      expect(spec.areaBasis, AreaBasis.net);
      // m² dışına geçince alan esası taşınmaz.
      await t.tap(find.byKey(const ValueKey<String>('fee_spec_dist_equal')));
      await t.pump();
      expect(key.currentState!.read()!.areaBasis, isNull);
    });

    testWidgets('320 dp x2,0: kategori satırları taşmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await pumpSpec(
        t,
        auth,
        distribution: FeeDistribution.category,
        categories: const <String, int>{'Çok uzun kategori adı örneği': 123456789},
        width: 320,
        scale: 2.0,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('FinanceTargetPicker', () {
    Future<GlobalKey<FinanceTargetPickerState>> pumpPicker(
      WidgetTester t,
      FinanceFakeAuth auth, {
      FeeTarget initial = const FeeTarget(),
    }) async {
      final key = GlobalKey<FinanceTargetPickerState>();
      await pumpList(
        t,
        FinanceTargetPicker(key: key, scope: _scope(auth), initial: initial),
        width: 400,
        height: 1600,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      return key;
    }

    testWidgets('tüm site: geçerli; blok seçimi boşken validate() hata verir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpPicker(t, auth);
      expect(key.currentState!.validate(), isTrue);
      expect(key.currentState!.target, const FeeTarget());
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_target_blocks')));
      expect(key.currentState!.validate(), isFalse);
      await t.pump();
      expect(find.text('En az bir blok seçin.'), findsOneWidget);
    });

    testWidgets('blok ekle -> çip, hedefe girer; çıkar -> kalkar; aynı blok iki kez eklenmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpPicker(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_target_blocks')));
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_block')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('B Blok')));
      await settleFor(t);
      expect(key.currentState!.target.blockIds, <int>[2]);
      expect(key.currentState!.target.type, FeeTargetType.blocks);
      // Seçici açıkken zaten seçili blok listede yok.
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_block')));
      await settleFor(t);
      expect(find.descendant(of: find.byType(AlertDialog).last, matching: find.text('B Blok')), findsNothing);
      expect(find.descendant(of: find.byType(AlertDialog).last, matching: find.text('A Blok')), findsOneWidget);
      await tapFinder(t, find.text('Vazgeç'));
      await settleFor(t);
      await t.tap(find.byTooltip('B Blok hedeften çıkar'));
      await t.pump();
      expect(key.currentState!.target.blockIds, isEmpty);
    });

    testWidgets('daire ekle: seçici pencereden; hedef kimlikleri gider', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpPicker(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_target_apartments')));
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_apartment')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('A Blok - 6')));
      await settleFor(t);
      expect(key.currentState!.target.apartmentIds, <int>[302]);
      expect(key.currentState!.validate(), isTrue);
      expect(key.currentState!.target.toJson(), <String, dynamic>{
        'type': 'apartments',
        'apartment_ids': <int>[302],
      });
    });

    testWidgets('kayıtlı hedef: etiketli çip; etiketsiz kimlik "N daire" + Seçimi temizle', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpPicker(
        t,
        auth,
        initial: const FeeTarget(
          type: FeeTargetType.apartments,
          apartmentIds: <int>[301, 302, 999],
          apartmentItems: <FeeTargetItem>[
            FeeTargetItem(id: 301, label: 'A Blok - 5'),
            FeeTargetItem(id: 302, label: 'A Blok - 6'),
          ],
        ),
      );
      expect(find.byKey(const ValueKey<String>('finance_pick_301')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_pick_302')), findsOneWidget);
      expect(find.text('1 daire'), findsOneWidget, reason: 'etiketsiz kimlik');
      expect(key.currentState!.target.apartmentIds.toSet(), <int>{301, 302, 999});
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_apartment_clear')));
      expect(key.currentState!.target.apartmentIds.toSet(), <int>{301, 302});
    });

    testWidgets('kayıtlı blok kimlikleri site yapısından adlarıyla çözülür', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await pumpPicker(
        t,
        auth,
        initial: const FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1, 2]),
      );
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_pick_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_pick_2')), findsOneWidget);
      expect(key.currentState!.target.blockIds.toSet(), <int>{1, 2});
    });
  });

  group('financeWriteMessage: belirsiz sonuç ipuçları', () {
    test('4xx kesin reddir: ipucu eklenmez; ağ / 5xx belirsizdir: ipucu eklenir', () {
      final rejected = ApiException('Bu dönem kapatılmış.', statusCode: 409, code: 'PERIOD_CLOSED');
      expect(financeWriteMessage(rejected, 'x'), 'Bu dönem kapatılmış.');
      expect(financeOutcomeUncertain(rejected), isFalse);

      final network = ApiException('Sunucuya ulaşılamadı.');
      expect(financeOutcomeUncertain(network), isTrue);
      expect(
        financeWriteMessage(network, 'x'),
        'Sunucuya ulaşılamadı. Kayıt oluşmuş olabilir. Aynı bilgilerle tekrar denerseniz çift kayıt oluşmaz.',
      );
      final server = ApiException('Sunucuda hata', statusCode: 502);
      expect(financeOutcomeUncertain(server), isTrue);
      expect(financeWriteMessage(server, 'x'), endsWith(kFinanceUncertainHint));
      expect(financeOutcomeUncertain(StateError('x')), isTrue);
    });

    test('tanım ekleme / durum değişikliği için ayrı ipuçları (çift kayıt vaadi yok)', () {
      final network = ApiException('Sunucuya ulaşılamadı.');
      final definition = financeWriteMessage(network, 'x', hint: kFinanceUncertainDefinitionHint);
      expect(definition, endsWith(kFinanceUncertainDefinitionHint));
      expect(definition.contains('çift kayıt oluşmaz'), isFalse);
      final state = financeWriteMessage(network, 'x', hint: kFinanceUncertainStateHint);
      expect(state, endsWith(kFinanceUncertainStateHint));
      expect(state.contains('çift kayıt oluşmaz'), isFalse);
    });

    test('mesaj yoksa yedek metin kullanılır; kod yardımcıları', () {
      expect(financeWriteMessage(ApiException('', statusCode: 400), 'Yedek metin.'), 'Yedek metin.');
      expect(isFinanceModuleDisabled(ApiException('x', statusCode: 403, code: 'MODULE_DISABLED')), isTrue);
      expect(isFinanceModuleDisabled(ApiException('x', statusCode: 403, code: 'FORBIDDEN_ROLE')), isFalse);
      expect(isFinanceModuleDisabled(StateError('x')), isFalse);
      expect(hasErrorCode(ApiException('x', code: 'PREVIEW_STALE'), 'PREVIEW_STALE'), isTrue);
      expect(hasErrorCode('metin', 'PREVIEW_STALE'), isFalse);
    });
  });

  group('idempotency anahtarı', () {
    test('64 karakteri aşmaz; yalnız küçük harf / rakam / tire; her seferinde farklı', () {
      final keys = <String>{for (var i = 0; i < 500; i++) newIdempotencyKey('pay')};
      expect(keys.length, 500);
      for (final key in keys) {
        expect(key.length, lessThanOrEqualTo(64));
        expect(RegExp(r'^[a-z0-9-]+$').hasMatch(key), isTrue, reason: key);
        expect(key.startsWith('pay-'), isTrue);
      }
    });

    test('aynı imza aynı anahtar, farklı imza yeni anahtar; reset yeni anahtar üretir', () {
      final keys = IdempotencyKeys('run');
      final a = keys.keyFor('x');
      expect(keys.keyFor('x'), a);
      final b = keys.keyFor('y');
      expect(b, isNot(a));
      expect(keys.keyFor('y'), b);
      keys.reset();
      expect(keys.keyFor('y'), isNot(b));
    });
  });

  group('Modüller ekranı: "Aidat ve Finans" kartı (katalogda available)', () {
    Future<void> pumpModules(
      WidgetTester t,
      ModulesFakeAuth auth, {
      double width = 400,
      double scale = 1.0,
      bool dark = false,
    }) async {
      await pumpList(
        t,
        ModulesView(authService: auth),
        width: width,
        height: 3000,
        scale: scale,
        dark: dark,
      );
      await settleFor(t, 100);
      await settleFor(t, 100);
    }

    testWidgets('site yöneticisi: finance "Tanımlı değil" + "Modül Talep Et" (anahtar yok)', (t) async {
      final auth = ModulesFakeAuth(
        fixtureRole: UserRole.siteManager,
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', financeAvailable: true, superView: false)},
        sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')],
      );
      await pumpModules(t, auth);
      final card = find.ancestor(of: find.text('Aidat ve Finans'), matching: find.byType(ModuleCard));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Modül Talep Et')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(Switch)), findsNothing);
      expect(find.descendant(of: card, matching: find.widgetWithText(StatusChip, 'Tanımlı değil')), findsOneWidget);
      expect(find.byType(Switch), findsNothing, reason: 'yönetici hiçbir modülü kendi açmaz');
    });

    testWidgets('süper kullanıcı: finance kartında anahtar var (kapalı), diğerleri "Yakında…"', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', financeAvailable: true)},
        sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')],
      );
      await pumpModules(t, auth);
      expect(moduleSwitch('finance'), findsOneWidget);
      expect(t.widget<Switch>(moduleSwitch('finance')).value, isFalse);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(4), reason: 'finance artık yakında değil');
    });

    testWidgets('320 dp x2,0 taşma yok (finance kartı etkin)', (t) async {
      final auth = ModulesFakeAuth(
        fixtureRole: UserRole.siteManager,
        states: <int, SiteModulesState>{
          11: mdState(11, 'Gül Sitesi', financeAvailable: true, finance: true, superView: false),
        },
        sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')],
      );
      await pumpModules(t, auth, width: 320, scale: 2.0);
      expect(find.widgetWithText(StatusChip, 'Tanımlı'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });
}
