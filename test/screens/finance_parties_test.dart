// İki hesap (İP-1A, karar G12) istemci davranışı: ekstre penceresinde [Kiracı hesabı] [Ev sahibi hesabı] sekmeleri, tahsilatta
// "Daire hesabı" seçimi (varsayılan sunucudan), düzeltmede hesap değiştirme, ek borç / tanımda "Kim öder", bakiye listesinde
// hesap kırılımı, Borcum'da kendi hesabı + salt okunur kiracı hesabı, rapor hesap süzgeci ve gecikme tazminatında aynı
// dairenin iki satırı. Eski sunucu biçimindeki daireler (sahte serviste `twoAccountApartments` dışında) eski görünümü korur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_definition_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_run_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_late_fee_section.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reports_tab.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

/// 301 iki hesaplı daire (güncel kiracı var): ev sahibi hesabında eylül (vadesi geçmiş) + ekim (vadesi gelmemiş) aidatı
/// (1.000 TL borç, 500 TL vadesi geçmiş); kiracı hesabında 700 TL vadesi geçmiş borç. Varsayılan tahsilat hesabı kiracı
/// (vadesi geçeni büyük olan hesap).
FinanceFakeAuth _twoAccounts() {
  final auth = FinanceFakeAuth.seeded();
  auth.twoAccountApartments.add(301);
  auth.currentTenantApartments.add(301);
  auth.ledger.add(
    finEntry(5, 301, amount: 70000, period: '2026-09', entryDate: '2026-09-01', dueDate: '2026-09-10', definitionName: 'Aylık aidat', account: 'tenant'),
  );
  return auth;
}

Future<void> _tap(WidgetTester t, String key) async {
  await f4Tap(t, key);
  await settleFor(t);
}

Future<void> _openAccount(WidgetTester t, FinanceFakeAuth auth, {int apartmentId = 301, double height = 2400}) async {
  await openDialogAt(
    t,
    (context) => FinanceAccountDialog.show(context, scope: _scope(auth), apartmentId: apartmentId, initialLabel: 'A Blok - 5', now: () => _now),
    width: 420,
    height: height,
    scale: 1.0,
    dark: false,
  );
  await settleFor(t);
  await settleFor(t);
}

Future<void> _pay(WidgetTester t, String amount) async {
  await f4Enter(t, 'finance_payment_amount', amount);
  await f4Tap(t, 'finance_method_cash');
  await _tap(t, 'finance_payment_submit');
}

bool _selected(WidgetTester t, String key) => t.widget<ChoiceChip>(find.byKey(ValueKey<String>(key))).selected;

void main() {
  group('taşma matrisi (dar ekran / büyük yazı / koyu tema)', () {
    f4Matrix('ekstre: iki hesap sekmesi + başlık', (t, w, h, s, dark) async {
      final auth = _twoAccounts();
      await openDialogAt(
        t,
        (context) => FinanceAccountDialog.show(context, scope: _scope(auth), apartmentId: 301, initialLabel: 'A Blok - 5', now: () => _now),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      await settleFor(t);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_account_tab_owner')));
      expect(find.byKey(const ValueKey<String>('finance_account_tab_tenant')), findsOneWidget);
    });

    f4Matrix('tahsilat: daire hesabı seçimi', (t, w, h, s, dark) async {
      final auth = _twoAccounts();
      await openDialogAt(
        t,
        (context) => FinancePaymentDialog.show(
          context,
          scope: _scope(auth),
          apartmentId: 301,
          apartmentLabel: 'A Blok - 5',
          now: () => _now,
          accountParty: AccountParty.tenant,
          accountChoice: true,
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_payment_party_owner')));
      expect(find.byKey(const ValueKey<String>('finance_payment_party_tenant')), findsOneWidget);
    });

    f4Matrix('Borcum: salt okunur kiracı hesabı bölümü', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      auth.myFinanceItems = <Map<String, dynamic>>[
        finMyItem(
          balance: 0,
          overdue: 0,
          account: 'owner',
          accounts: <Map<String, dynamic>>[
            finMyAccount(party: 'owner'),
            finMyAccount(party: 'tenant', role: 'read_only', balance: 168000, overdue: 156000, nextDueDate: '2026-11-01', nextDueMinor: 12000),
          ],
        ),
      ];
      await pumpList(t, MyFinanceView(authService: auth, now: () => _now), width: w, height: h, scale: s, dark: dark);
      await settleFor(t, 100);
      await settleFor(t, 100);
      await scrollTo(t, find.byKey(const ValueKey<String>('my_finance_ro_tenant_statement_share')));
      expect(find.byKey(const ValueKey<String>('my_finance_ro_tenant_balance')), findsOneWidget);
    });
  });

  group('ekstre penceresi: iki hesap sekmesi', () {
    testWidgets('iki hesaplı daire: [Kiracı hesabı] [Ev sahibi hesabı]; ilk sekme varsayılan hesap; liste ve bakiye yalnız seçili hesabın', (t) async {
      final auth = _twoAccounts();
      await _openAccount(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_account_tabs')), findsOneWidget);
      expect(_selected(t, 'finance_account_tab_tenant'), isTrue);
      expect(_selected(t, 'finance_account_tab_owner'), isFalse);
      expect(find.text('Kiracı hesabı • Borç 700,00 ₺'), findsOneWidget);
      expect(find.text('Ev sahibi hesabı • Borç 1.000,00 ₺'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_account_party_label')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger_entry_5')), findsOneWidget, reason: 'kiracı hesabı satırı');
      expect(find.byKey(const ValueKey<String>('ledger_entry_1')), findsNothing, reason: 'ev sahibi hesabı satırı karışmaz');
      // ilk istek süzgeçsiz (sekme bilgisi), ikincisi seçili hesap
      expect(auth.accountCalls.map((c) => c.party).toList(), <String?>[null, 'tenant']);

      await _tap(t, 'finance_account_tab_owner');
      expect(auth.accountCalls.last.party, 'owner');
      expect(_selected(t, 'finance_account_tab_owner'), isTrue);
      expect(find.byKey(const ValueKey<String>('ledger_entry_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger_entry_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger_entry_5')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_account_balance')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('finance_account_balance'))).data, '1.000,00 ₺');
    });

    testWidgets('eski biçim (tek hesap) daire: sekme yok, tek istek, eski görünüm', (t) async {
      final auth = _twoAccounts();
      await _openAccount(t, auth, apartmentId: 302);
      expect(find.byKey(const ValueKey<String>('finance_account_tabs')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_account_party_label')), findsNothing);
      expect(auth.accountCalls.single.party, isNull);
    });
  });

  group('tahsilat: daire hesabı', () {
    testWidgets('ekstreden: seçili sekmenin hesabıyla açılır; tahsilat o hesaba yazılır, mesaj hesabın bakiyesini söyler', (t) async {
      final auth = _twoAccounts();
      await _openAccount(t, auth);
      await _tap(t, 'finance_account_add_payment');
      expect(find.byKey(const ValueKey<String>('finance_payment_party')), findsOneWidget);
      expect(_selected(t, 'finance_payment_party_tenant'), isTrue);
      await _pay(t, '700');
      expect(auth.paymentCalls.single['account_party'], 'tenant');
      final entry = auth.ledger.firstWhere((e) => e['kind'] == 'payment' && e['apartment_id'] == 301);
      expect(entry['account_party'], 'tenant');
      expect(find.textContaining('Kiracı hesabı: Borç yok'), findsOneWidget, reason: 'tahsilat mesajı hesabın bakiyesini söyler');
    });

    testWidgets('hesap değiştirilir: ev sahibi hesabı seçilince tahsilat ev sahibi hesabına', (t) async {
      final auth = _twoAccounts();
      await _openAccount(t, auth);
      await _tap(t, 'finance_account_add_payment');
      await f4Tap(t, 'finance_payment_party_owner');
      expect(_selected(t, 'finance_payment_party_owner'), isTrue);
      await _pay(t, '250');
      expect(auth.paymentCalls.single['account_party'], 'owner');
    });

    testWidgets('ekstre dışından (daire hazır, hesap bilgisi yok): sunucuya sorulur, iki hesapta seçim varsayılan hesapla gelir', (t) async {
      final auth = _twoAccounts();
      await openDialogAt(
        t,
        (context) => FinancePaymentDialog.show(context, scope: _scope(auth), apartmentId: 301, apartmentLabel: 'A Blok - 5', now: () => _now),
        width: 420,
        height: 1800,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(auth.accountCalls.single.party, isNull, reason: 'yalnız sekme bilgisi sorulur');
      expect(_selected(t, 'finance_payment_party_tenant'), isTrue);
      await _pay(t, '100');
      expect(auth.paymentCalls.single['account_party'], 'tenant');
    });

    testWidgets('tek hesaplı (eski biçim) daire: seçim çizilmez, istek eskisi gibi (account_party yok)', (t) async {
      final auth = _twoAccounts();
      await openDialogAt(
        t,
        (context) => FinancePaymentDialog.show(context, scope: _scope(auth), apartmentId: 302, apartmentLabel: 'A Blok - 6', now: () => _now),
        width: 420,
        height: 1800,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_payment_party')), findsNothing);
      await _pay(t, '100');
      expect(auth.paymentCalls.single.containsKey('account_party'), isFalse);
    });

    testWidgets('düzeltme: eski tahsilatın hesabıyla başlar; diğer hesaba taşınır (ters kayıt eski hesapta kalır)', (t) async {
      final auth = _twoAccounts();
      auth.ledger.add(finEntry(6, 301, kind: 'payment', amount: -20000, period: '2026-10', entryDate: '2026-10-05', method: 'cash', account: 'tenant'));
      auth.defaultPaymentAccounts[301] = 'tenant';
      await _openAccount(t, auth);
      await _tap(t, 'ledger_correct_6');
      expect(_selected(t, 'finance_payment_party_tenant'), isTrue, reason: 'eski tahsilatın hesabı');
      await f4Tap(t, 'finance_payment_party_owner');
      await _tap(t, 'finance_payment_submit');
      expect(auth.correctCalls.single['account_party'], 'owner');
      final reversal = auth.ledger.firstWhere((e) => e['reverses_entry_id'] == 6);
      expect(reversal['account_party'], 'tenant', reason: 'ters kayıt asılın hesabında');
      final moved = auth.ledger.lastWhere((e) => e['kind'] == 'payment');
      expect(moved['account_party'], 'owner');
    });
  });

  group('"Kim öder"', () {
    Future<void> openCharge(WidgetTester t, FinanceFakeAuth auth) => openDialogAt(
      t,
      (context) => FinanceRunDialog.showCharge(context, scope: _scope(auth), now: () => _now),
      width: 420,
      height: 2400,
      scale: 1.0,
      dark: false,
    );

    testWidgets('ek borç: varsayılan ev sahibi (gövdede alan yok); dairede oturan seçilince charge_party gider; önizleme satırı hesabı yazar', (t) async {
      final auth = _twoAccounts();
      auth.previewAccounts[301] = 'tenant';
      await openCharge(t, auth);
      await settleFor(t);
      expect(_selected(t, 'finance_charge_party_owner'), isTrue);
      expect(find.byKey(const ValueKey<String>('finance_charge_party_note')), findsOneWidget);
      await f4Enter(t, 'finance_charge_name', 'Çatı onarımı');
      await f4Tap(t, 'charge_spec_dist_equal');
      await f4Enter(t, 'charge_spec_amount', '3.000');
      await _tap(t, 'finance_run_preview');
      expect(auth.chargePreviewCalls.single.containsKey('charge_party'), isFalse, reason: 'varsayılan: eski istekle aynı');
      expect(find.text('Kiracı hesabı'), findsOneWidget, reason: 'iki hesaplı dairenin satırı hesabı yazar');
      await _tap(t, 'finance_run_back');
      await f4Tap(t, 'finance_charge_party_occupant');
      expect(_selected(t, 'finance_charge_party_occupant'), isTrue);
      await _tap(t, 'finance_run_preview');
      expect(auth.chargePreviewCalls.last['charge_party'], 'occupant');
    });

    Future<void> openForm(WidgetTester t, FinanceFakeAuth auth, {FeeDefinition? definition}) => openDialogAt(
      t,
      (context) => FinanceDefinitionFormDialog.show(context, scope: _scope(auth), definition: definition, now: () => _now),
      width: 420,
      height: 2400,
      scale: 1.0,
      dark: false,
    );

    testWidgets('yeni tanım: aylık varsayılan dairede oturan, tek seferlik ev sahibi; varsayılan gönderilmez, değiştirilen gider', (t) async {
      final auth = _twoAccounts();
      await openForm(t, auth);
      await settleFor(t);
      expect(_selected(t, 'finance_def_charge_party_occupant'), isTrue);
      await f4Tap(t, 'finance_kind_one_time');
      expect(_selected(t, 'finance_def_charge_party_owner'), isTrue, reason: 'tür değişince seçilmemiş değer türün varsayılanına geçer');
      await f4Tap(t, 'finance_kind_recurring');
      expect(_selected(t, 'finance_def_charge_party_occupant'), isTrue);
      await f4Tap(t, 'finance_def_charge_party_owner');
      await f4Enter(t, 'finance_definition_name', 'Demirbaş');
      await f4Enter(t, 'def_spec_amount', '50');
      await _tap(t, 'finance_definition_submit');
      expect(auth.definitionCreateCalls.single['charge_party'], 'owner');
    });

    testWidgets('yeni aylık tanım varsayılanla: charge_party gövdede yok (sunucu varsayılanı)', (t) async {
      final auth = _twoAccounts();
      await openForm(t, auth);
      await settleFor(t);
      await f4Enter(t, 'finance_definition_name', 'Aidat');
      await f4Enter(t, 'def_spec_amount', '500');
      await _tap(t, 'finance_definition_submit');
      expect(auth.definitionCreateCalls.single.containsKey('charge_party'), isFalse);
    });

    testWidgets('borçlandırılmış tanım: "Kim öder" değişir (yalnız sonraki borçlandırmalar); yalnız charge_party gider', (t) async {
      final auth = _twoAccounts();
      await openForm(t, auth, definition: FeeDefinition.fromJson(auth.definitions[1]!));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_definition_charge_party_note')), findsOneWidget);
      await f4Tap(t, 'finance_def_charge_party_owner');
      await _tap(t, 'finance_definition_submit');
      expect(auth.definitionUpdateCalls.single.fields, <String, Object?>{'charge_party': 'owner'});
    });
  });

  group('bakiye listesi', () {
    testWidgets('kiracı hesabında tutar varsa iki hesap ayrı rozetle; yoksa eski tek rozet', (t) async {
      final row = BalanceRow.fromJson(<String, dynamic>{
        'apartment_id': 301,
        'label': 'A Blok - 5',
        'balance_minor': 158000,
        'overdue_minor': 156000,
        'debt_minor': 168000,
        'credit_minor': 10000,
        'accounts': <String, dynamic>{
          'owner': <String, dynamic>{'balance_minor': -10000, 'overdue_minor': 0},
          'tenant': <String, dynamic>{'balance_minor': 168000, 'overdue_minor': 156000},
        },
      });
      await pumpList(t, BalanceRowCard(row: row, onTap: () {}), width: 400, height: 800, scale: 1.0, dark: false);
      expect(find.byKey(const ValueKey<String>('balance_row_301_tenant')), findsOneWidget);
      expect(find.text('Kiracı hesabı: Borç 1.680,00 ₺'), findsOneWidget);
      expect(find.text('Ev sahibi hesabı: Alacak 100,00 ₺'), findsOneWidget);
      expect(find.text('Borç 1.580,00 ₺'), findsNothing, reason: 'iki hesabın toplamı yanıltıcıdır, gösterilmez');

      final single = BalanceRow.fromJson(<String, dynamic>{'apartment_id': 302, 'label': 'A Blok - 6', 'balance_minor': 5000});
      await pumpList(t, BalanceRowCard(row: single, onTap: () {}), width: 400, height: 800, scale: 1.0, dark: false);
      expect(find.text('Borç 50,00 ₺'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('balance_row_302_tenant')), findsNothing);
    });
  });

  group('Borcum: kendi hesabı + salt okunur kiracı hesabı', () {
    final pdfs = <FinancePdfRequest>[];
    setUp(() {
      pdfs.clear();
      FinancePdfActions.debugOverride = (request) async => pdfs.add(request);
    });
    tearDown(() => FinancePdfActions.debugOverride = null);

    FinanceFakeAuth resident({required bool readOnly}) {
      final auth = FinanceFakeAuth.seeded();
      auth.myFinanceItems = <Map<String, dynamic>>[
        finMyItem(
          balance: 0,
          overdue: 0,
          nextDueDate: null,
          nextDueMinor: null,
          payer: 'both',
          recent: const <Map<String, dynamic>>[],
          account: 'owner',
          accounts: <Map<String, dynamic>>[
            finMyAccount(party: 'owner'),
            if (readOnly)
              finMyAccount(
                party: 'tenant',
                role: 'read_only',
                balance: 168000,
                overdue: 156000,
                recent: <Map<String, dynamic>>[
                  <String, dynamic>{...finEntry(9, 301, amount: 168000, dueDate: '2026-09-10', definitionName: 'Aylık aidat', account: 'tenant'), 'description': null, 'created_by_name': null},
                ],
              ),
          ],
        ),
      ];
      return auth;
    }

    testWidgets('malik: kendi (ev sahibi) hesabı "Borcunuz yok"; kiracı hesabı ayrı SALT OKUNUR bölümde, toplamlara eklenmez', (t) async {
      final auth = resident(readOnly: true);
      await pumpList(t, MyFinanceView(authService: auth, now: () => _now), width: 400, height: 3000, scale: 1.0, dark: false);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.text('Kendi hesabınız: Ev sahibi hesabı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_no_debt')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_ro_tenant')), findsOneWidget);
      expect(find.text('Salt okunur'), findsOneWidget);
      expect(find.text(myFinanceReadOnlyNote), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('my_finance_ro_tenant_balance'))).data, 'Borç 1.680,00 ₺');
      expect(find.byKey(const ValueKey<String>('ledger_entry_9')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_ro_tenant_receipts')), findsNothing, reason: 'makbuz listesi tek (iki görünümü kapsar)');

      await f4Tap(t, 'my_finance_ro_tenant_statement_print');
      await settleFor(t);
      expect(auth.f4.myStatementCalls.single['account_party'], 'tenant', reason: 'salt okunur hesabın ekstresi');
      await f4Tap(t, 'my_finance_statement_print');
      await settleFor(t);
      expect(auth.f4.myStatementCalls.last['account_party'], isNull, reason: 'kendi hesabı: sunucu varsayılanı');
    });

    testWidgets('salt okunur görünüm yoksa bölüm çizilmez; eski sunucu yanıtında hesap adı yazılmaz', (t) async {
      final auth = resident(readOnly: false);
      await pumpList(t, MyFinanceView(authService: auth, now: () => _now), width: 400, height: 3000, scale: 1.0, dark: false);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byKey(const ValueKey<String>('my_finance_ro_tenant')), findsNothing);
      expect(find.text('Kendi hesabınız: Ev sahibi hesabı'), findsOneWidget);

      final old = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await pumpList(t, MyFinanceView(authService: old, now: () => _now), width: 400, height: 3000, scale: 1.0, dark: false);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byKey(const ValueKey<String>('my_finance_account_party')), findsNothing);
    });
  });

  group('raporlar: hesap süzgeci', () {
    final launched = <List<ExportSource>>[];
    setUp(launched.clear);

    Future<void> pumpReports(WidgetTester t, FinanceFakeAuth auth) async {
      await pumpList(
        t,
        FinanceReportsTab(scope: _scope(auth), now: () => _now, exportLauncher: (context, sources) async => launched.add(sources)),
        width: 420,
        height: 3000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t, 100);
      await settleFor(t, 100);
    }

    testWidgets('yaşlandırma: "Tüm hesaplar" varsayılan; kiracı hesabı seçilince istek ve dışa aktarma account_party taşır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await pumpReports(t, auth);
      expect(_selected(t, 'finance_aging_party_all'), isTrue);
      expect(auth.f4.reportCalls.last['account_party'], isNull);
      await f4Tap(t, 'finance_aging_party_tenant');
      await _tap(t, 'finance_report_fetch');
      final call = auth.f4.reportCalls.lastWhere((c) => c['name'] == 'getAgingReport');
      expect(call['account_party'], 'tenant');
      await _tap(t, 'finance_report_export');
      final source = launched.single.single;
      expect(source.filterSummary, contains('Kiracı hesabı'));
    });

    testWidgets('yaşlandırma kartı: süzgeçsiz raporda kiracı hesabında tutar varsa hesap kırılımı', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final items = List<Map<String, dynamic>>.of((auth.f4.agingJson['items'] as List).cast<Map<String, dynamic>>());
      items[0] = <String, dynamic>{
        ...items[0],
        'account_party': null,
        'accounts': <String, dynamic>{
          'owner': <String, dynamic>{'total_overdue_minor': 0, 'credit_minor': 10000},
          'tenant': <String, dynamic>{'total_overdue_minor': 75000, 'credit_minor': 0},
        },
      };
      auth.f4.agingJson = <String, dynamic>{...auth.f4.agingJson, 'items': items};
      await pumpReports(t, auth);
      expect(find.byKey(const ValueKey<String>('aging_item_301_tenant')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aging_item_301_owner')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aging_item_302_tenant')), findsNothing, reason: 'kırılımsız satırda pill yok');
    });
  });

  group('gecikme tazminatı: aynı dairenin iki hesabı iki satır', () {
    testWidgets('önizleme iki satırı ayrı anahtarla çizer (çakışma yok); sayı "1 daire, 2 hesap"', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.settingsJson = f4SettingsJson(version: 2, lateFee: true, startPeriod: '2026-08-01', nextPeriod: '2026-09');
      final base = f4LatePreviewJson();
      final line = (base['lines'] as List).first as Map<String, dynamic>;
      auth.f4.latePreviewJson = <String, dynamic>{
        ...base,
        'apartment_count': 2,
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{...line, 'account_party': 'owner', 'amount_minor': 10000},
          <String, dynamic>{...line, 'account_party': 'tenant', 'amount_minor': 2345},
        ],
      };
      final controller = FinanceSettingsController(_scope(auth));
      addTearDown(controller.dispose);
      unawaited(controller.load());
      await pumpList(
        t,
        FinanceLateFeeSection(scope: _scope(auth), settings: controller, onOpenSettings: () {}, onDataChanged: () {}, now: () => _now),
        width: 420,
        height: 3000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t, 100);
      await settleFor(t, 100);
      await _tap(t, 'finance_latefee_calculate');
      await _tap(t, 'finance_latefee_preview');
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('finance_latefee_line_301_owner')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_line_301_tenant')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('finance_latefee_count'))).data, '1 daire, 2 hesap');
      await _tap(t, 'finance_latefee_explain_301_tenant');
      expect(find.byKey(const ValueKey<String>('finance_latefee_breakdown_301_tenant')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_breakdown_301_owner')), findsNothing, reason: 'döküm satır başına açılır');
    });
  });
}
