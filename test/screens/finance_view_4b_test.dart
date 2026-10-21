// Platform Faz 4b: FinanceView bağlantıları (yeni sekmeler Kasa / Giderler / Raporlar, Finans Ayarları, borç hatırlatma
// kartı, gecikme tazminatı bölümü) ve ekstredeki makbuz eylemleri. 4a sekmeleri (Daireler / Tanımlar / Dönemler) ve
// anahtarları (finance_tab_0..2) değişmez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_cash_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_charts_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_expenses_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reports_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart' show BalanceRowCard;

import 'dialog_layout_harness.dart' show scrollTo, settleFor;
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList, tapFinder;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

const List<PeopleSite> _manage = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true)];
const List<PeopleSite> _board = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];
const List<PeopleSite> _two = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
  PeopleSite(code: 12, name: 'Lale Sitesi', canWrite: true),
];

FinanceFakeAuth _auth({bool seedCash = true}) {
  final auth = FinanceFakeAuth.seeded();
  if (seedCash) {
    auth.f4.accounts
      ..add(f4AccountJson(1, 'Nakit Kasa', balance: 250050, opening: 100000))
      ..add(f4AccountJson(2, 'Ziraat Bankası', kind: 'bank', balance: 1200000, opening: 1000000));
  }
  return auth;
}

Future<GlobalKey<FinanceViewState>> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  List<PeopleSite> sites = _manage,
  double width = 400,
  double height = 3000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<FinanceViewState>();
  await pumpList(
    t,
    FinanceView(key: key, authService: auth, sites: sites, now: () => _now),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Future<void> _tab(WidgetTester t, int index) async {
  await tapFinder(t, find.byKey(ValueKey<String>('finance_tab_$index')));
  await settleFor(t);
}

void main() {
  group('sekmeler', () {
    f4Matrix('altı sekme + Finans Ayarları + hatırlatma kartı taşmaz', (t, w, h, s, dark) async {
      await _pump(t, _auth(), width: w, height: h, scale: s, dark: dark);
      for (final label in const ['Daireler', 'Tanımlar', 'Dönemler', 'Kasa', 'Giderler', 'Raporlar']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_open_settings')));
      expect(find.byKey(const ValueKey<String>('finance_open_settings')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_card')), findsOneWidget);
    });

    testWidgets('Kasa / Giderler / Raporlar tembel kurulur: sekmeye girmeden istek atılmaz', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(auth.f4.callCount('listAccounts'), 0);
      expect(auth.f4.callCount('listExpenses'), 0);
      expect(find.byType(FinanceCashTab), findsNothing);
      await _tab(t, 3);
      expect(find.byType(FinanceCashTab), findsOneWidget);
      expect(auth.f4.callCount('listAccounts'), greaterThan(0));
      expect(find.text('Nakit Kasa'), findsOneWidget);
      await _tab(t, 4);
      expect(find.byType(FinanceExpensesTab), findsOneWidget);
      expect(auth.f4.callCount('listExpenses'), greaterThan(0));
      await _tab(t, 5);
      expect(find.byType(FinanceReportsTab), findsOneWidget);
    });

    testWidgets('Grafikler sekmesi Raporlar sekmesinin yanında; tembel kurulur, tek uçtan 12 ay çeker, kurul da görür', (t) async {
      for (final sites in <List<PeopleSite>>[_manage, _board]) {
        final auth = _auth();
        await _pump(t, auth, sites: sites);
        final chips = find.byType(ChoiceChip).evaluate().map((e) => ((e.widget as ChoiceChip).label as Text).data).toList();
        expect(chips.indexOf('Grafikler'), chips.indexOf('Raporlar') + 1, reason: 'çubukta Raporlar sekmesinin hemen yanında');
        expect(find.byType(FinanceChartsTab), findsNothing);
        expect(auth.f4.callCount('getFinanceCharts'), 0, reason: 'sekmeye girmeden istek atılmaz');
        await _tab(t, 7);
        expect(find.byType(FinanceChartsTab), findsOneWidget);
        expect(auth.f4.callCount('getFinanceCharts'), 1);
        expect(find.text('Aylık gelir ve gider'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('finance_chart_card_aging')), findsOneWidget);
        await _tab(t, 6);
        await _tab(t, 7);
        expect(auth.f4.callCount('getFinanceCharts'), 1, reason: 'bayat değilse yeniden çekilmez');
      }
    });

    testWidgets('kurul: Finans Ayarları ve yazma düğmeleri yok; Kasa ve Raporlar okunur', (t) async {
      final auth = _auth();
      await _pump(t, auth, sites: _board);
      expect(find.byKey(const ValueKey<String>('finance_open_settings')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsNothing);
      await _tab(t, 3);
      expect(find.text('Nakit Kasa'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_add')), findsNothing);
      await _tab(t, 4);
      expect(find.byKey(const ValueKey<String>('finance_expense_add')), findsNothing);
      await _tab(t, 5);
      expect(find.byType(FinanceReportsTab), findsOneWidget);
    });

    testWidgets('bir sekmedeki yazma öteki sekmeleri bayatlatır; çekip yenileme ayarları da yeniler', (t) async {
      final auth = _auth();
      final key = await _pump(t, auth);
      await _tab(t, 3);
      final before = auth.f4.callCount('getSettings');
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.f4.callCount('getSettings'), greaterThan(before));
    });
  });

  group('Finans Ayarları', () {
    testWidgets('düğme pencereyi açar; kaydedilince hatırlatma kartı kullanıma açılır', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsNothing);
      expect(find.textContaining('Borç hatırlatma bu sitede kapalı'), findsOneWidget);
      await f4Tap(t, 'finance_open_settings');
      expect(find.text('Gül Sitesi'), findsWidgets);
      await f4Tap(t, 'finance_settings_reminders_enabled');
      await f4Tap(t, 'finance_settings_submit');
      await settleFor(t);
      expect(auth.f4.settingsUpdates.single['reminders'], <String, dynamic>{'enabled': true});
      expect(find.text('Finans ayarları kaydedildi.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsOneWidget);
    });

    testWidgets('ayarlar okunamazsa pencere AÇILMAZ (varsayılanla üstüne yazılmaz); hata bildirimi', (t) async {
      final auth = _auth();
      auth.f4.settingsError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await _pump(t, auth);
      await f4Tap(t, 'finance_open_settings');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_settings_submit')), findsNothing);
      expect(find.textContaining('Ayarlar yüklenemedi'), findsWidgets);
    });

    testWidgets('Dönemler sekmesinde gecikme tazminatı: önce pasif neden; ayar açılınca (yenilemeyle) Hesapla görünür', (t) async {
      final auth = _auth();
      final key = await _pump(t, auth);
      await _tab(t, 2);
      expect(find.text('Gecikme tazminatı bu sitede kapalı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_calculate')), findsNothing);
      auth.f4.settingsJson = f4SettingsJson(version: 2, lateFee: true, legalOk: true, startPeriod: '2026-08-01', nextPeriod: '2026-09');
      await key.currentState!.reload();
      await settleFor(t);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_status')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_calculate')), findsOneWidget);
      expect(find.text('Henüz gecikme tazminatı hesaplanmadı.'), findsOneWidget);
    });

    testWidgets('hukuk onayı bekleniyor: hem hatırlatma hem tazminat pasif ve nedeni yazılı', (t) async {
      final auth = _auth();
      auth.f4.settingsJson = f4SettingsJson(version: 2, lateFee: true, reminders: true, legalOk: false);
      await _pump(t, auth);
      expect(find.textContaining('Hukuk onayı bekleniyor'), findsOneWidget);
      await _tab(t, 2);
      expect(find.textContaining('Hukuk onayı bekleniyor'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_latefee_calculate')), findsNothing);
    });

    testWidgets('site değişince ayar yükleyicisi yenilenir (eski sitenin ayarı görünmez)', (t) async {
      final auth = _auth();
      await _pump(t, auth, sites: _two);
      final before = auth.f4.callCount('getSettings');
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await settleFor(t);
      await t.tap(find.text('Lale Sitesi').last);
      await settleFor(t);
      expect(auth.f4.callCount('getSettings'), greaterThan(before));
    });
  });

  group('ekstre: makbuz', () {
    Future<void> openStatement(WidgetTester t, String apartment) async {
      await tapFinder(t, find.widgetWithText(BalanceRowCard, apartment));
      await settleFor(t);
    }

    testWidgets('tahsilattan sonra makbuz penceresi açılır ("düzenlendi" bildirimiyle)', (t) async {
      final auth = _auth();
      auth.f4.receipts[77] = f4ReceiptJson(77, number: 'MK-2026-000077', amount: 100000);
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 5');
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_account_add_payment')));
      await settleFor(t);
      await f4Enter(t, 'finance_payment_amount', '1.000');
      await f4Tap(t, 'finance_method_transfer');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      await settleFor(t);
      expect(auth.f4.paymentCalls.single['account_id'], 2);
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsOneWidget);
      expect(find.textContaining('Makbuz MK-2026-000077 düzenlendi'), findsOneWidget);
    });

    testWidgets('makbuz yoksa (otomatik düzenleme kapalı) makbuz penceresi AÇILMAZ', (t) async {
      final auth = _auth();
      auth.f4.paymentReceipt = null;
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 5');
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_account_add_payment')));
      await settleFor(t);
      await f4Enter(t, 'finance_payment_amount', '1.000');
      await f4Tap(t, 'finance_method_transfer');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.f4.paymentCalls, hasLength(1));
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsNothing);
      expect(auth.f4.callCount('getReceipt'), 0);
    });

    testWidgets('makbuzu olmayan tahsilatta yönetici "Makbuz Düzenle" der; makbuz açılır; tek istek', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 6');
      expect(find.byKey(const ValueKey<String>('ledger_issue_receipt_4')), findsOneWidget);
      await f4Tap(t, 'ledger_issue_receipt_4');
      await settleFor(t);
      expect(auth.f4.issueCalls, <int>[4]);
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsOneWidget);
    });

    testWidgets('makbuz düzenleme hatası ekstrede Türkçe ileti olarak kalır, "Makbuz Düzenle" tekrar denenebilir', (t) async {
      final auth = _auth();
      auth.f4.issueError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 6');
      await f4Tap(t, 'ledger_issue_receipt_4');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_account_action_error')), findsOneWidget);
      expect(find.textContaining('Makbuz düzenlenemedi'), findsOneWidget);
      auth.f4.issueError = null;
      await f4Tap(t, 'ledger_issue_receipt_4');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsOneWidget);
    });

    testWidgets('makbuzu olan satırda "Makbuz MK-..." düğmesi makbuzu açar; "Makbuz Düzenle" yok', (t) async {
      final auth = _auth();
      auth.f4.receipts[31] = f4ReceiptJson(31, number: 'MK-2026-000031', amount: 80000);
      auth.ledger.firstWhere((e) => e['id'] == 4)['receipt'] = <String, dynamic>{'id': 31, 'number': 'MK-2026-000031', 'status': 'active'};
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 6');
      expect(find.byKey(const ValueKey<String>('ledger_issue_receipt_4')), findsNothing);
      expect(find.text('Makbuz MK-2026-000031'), findsOneWidget);
      await f4Tap(t, 'ledger_receipt_4');
      await settleFor(t);
      expect(auth.f4.callCount('getReceipt'), 1);
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsNothing, reason: 'yeni düzenlenmedi');
    });

    testWidgets('R13 P1-4: makbuzu İPTAL edilmiş (hatalı düzenlenmiş) ödemeye YENİ makbuz düzenlenebilir', (t) async {
      final auth = _auth();
      auth.f4.receipts[31] = f4ReceiptJson(31, number: 'MK-2026-000031', amount: 80000, status: 'cancelled');
      auth.ledger.firstWhere((e) => e['id'] == 4)['receipt'] = <String, dynamic>{'id': 31, 'number': 'MK-2026-000031', 'status': 'cancelled'};
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 6');
      expect(find.byKey(const ValueKey<String>('ledger_receipt_4')), findsOneWidget, reason: 'iptal edilen makbuz yine açılabilir');
      expect(find.byKey(const ValueKey<String>('ledger_issue_receipt_4')), findsOneWidget);
      await f4Tap(t, 'ledger_issue_receipt_4');
      await settleFor(t);
      expect(auth.f4.issueCalls, <int>[4]);
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsOneWidget);
    });

    testWidgets('aktif makbuzu olan ödemede "Makbuz Düzenle" YOK; iptal edilmiş + ters kaydı olan ödemede de YOK', (t) async {
      final auth = _auth();
      auth.ledger.firstWhere((e) => e['id'] == 4)['receipt'] = <String, dynamic>{'id': 31, 'number': 'MK-2026-000031', 'status': 'active'};
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 6');
      expect(find.byKey(const ValueKey<String>('ledger_issue_receipt_4')), findsNothing);
    });

    testWidgets('R13 P2-12: ekstrede "Hatırlatmadan Muaf Tut" (spec §7): nedenle eklenir, bildirim çıkar', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 5');
      await f4Tap(t, 'finance_account_reminder_exempt');
      await settleFor(t);
      expect(auth.f4.callCount('listReminderExclusions'), 1, reason: 'durum sunucudan okunur');
      await f4Enter(t, 'finance_reminder_exempt_reason', '  Hukuki takip  ');
      await f4Tap(t, 'finance_reminder_exempt_submit');
      await settleFor(t);
      final write = auth.f4.writes.singleWhere((w) => w['op'] == 'addReminderExclusion');
      expect(write['reason'], 'Hukuki takip');
      expect(find.byKey(const ValueKey<String>('finance_reminder_exempt_submit')), findsNothing, reason: 'pencere kapandı');
      expect(find.textContaining('borç hatırlatmalarından muaf tutuldu'), findsOneWidget);
    });

    testWidgets('ekstrede zaten muaf daire: neden gösterilir; "Muafiyeti Kaldır" kaldırır', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 5');
      // Dairenin kimliği sahte sunucuda sabit: önce ekleyip sonra aynı pencereyi yeniden açarak kaldırılır.
      await f4Tap(t, 'finance_account_reminder_exempt');
      await settleFor(t);
      await f4Enter(t, 'finance_reminder_exempt_reason', 'Taşınıyor');
      await f4Tap(t, 'finance_reminder_exempt_submit');
      await settleFor(t);
      await f4Tap(t, 'finance_account_reminder_exempt');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exempt_current')), findsOneWidget);
      expect(find.textContaining('Neden: Taşınıyor'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exempt_submit')), findsNothing);
      await f4Tap(t, 'finance_reminder_exempt_remove');
      await settleFor(t);
      expect(auth.f4.callCount('removeReminderExclusion'), 1);
      expect(auth.f4.reminderExclusions, isEmpty);
      expect(find.textContaining('yeniden borç hatırlatmalarına dahil edildi'), findsOneWidget);
    });

    testWidgets('muafiyet durumu okunamazsa neden yazılır; tahmin yürütülmez, "Muaf Tut" yok', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 5');
      auth.f4.reminderExclusionError = ApiException('x', statusCode: 502);
      await f4Tap(t, 'finance_account_reminder_exempt');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exempt_load_error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exempt_submit')), findsNothing);
      expect(auth.f4.callCount('addReminderExclusion'), 0);
    });

    testWidgets('yazılmış neden varken Vazgeç / geri tuşu onay sorar; hiçbir şey yazılmaz', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 5');
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_reminder_exempt_submit',
        open: () async {
          await f4Tap(t, 'finance_account_reminder_exempt');
          await settleFor(t);
        },
        edit: () async => f4Enter(t, 'finance_reminder_exempt_reason', 'Neden'),
      );
      expect(auth.f4.callCount('addReminderExclusion'), 0);
    });

    testWidgets('kurul: "Hatırlatmadan Muaf Tut" YOK', (t) async {
      final auth = _auth();
      await _pump(t, auth, sites: _board);
      await openStatement(t, 'A Blok - 5');
      expect(find.byKey(const ValueKey<String>('finance_account_reminder_exempt')), findsNothing);
    });

    testWidgets('kurul: makbuzu açar, "Makbuz Düzenle" YOK', (t) async {
      final auth = _auth();
      auth.f4.receipts[31] = f4ReceiptJson(31, number: 'MK-2026-000031', amount: 80000);
      auth.ledger.firstWhere((e) => e['id'] == 4)['receipt'] = <String, dynamic>{'id': 31, 'number': 'MK-2026-000031', 'status': 'active'};
      await _pump(t, auth, sites: _board);
      await openStatement(t, 'A Blok - 6');
      expect(find.text('Makbuz MK-2026-000031'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger_issue_receipt_4')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_account_add_payment')), findsNothing);
    });

    testWidgets('"Makbuzlar" bu dairenin makbuz listesini açar (kurul da)', (t) async {
      final auth = _auth();
      auth.f4.receipts[31] = f4ReceiptJson(31, number: 'MK-2026-000031', amount: 80000);
      await _pump(t, auth, sites: _board);
      await openStatement(t, 'A Blok - 6');
      await f4Tap(t, 'finance_account_receipts');
      await settleFor(t);
      expect(auth.f4.callCount('listReceipts'), 1);
    });

    testWidgets('iptal edilmiş ve gecikme tazminatı satırları işaretlenir', (t) async {
      final auth = _auth();
      auth.ledger.firstWhere((e) => e['id'] == 3)
        ..['definition_name'] = 'Gecikme tazminatı'
        ..['late_fee_run_id'] = 40;
      await _pump(t, auth);
      await openStatement(t, 'A Blok - 6');
      expect(find.text('Gecikme tazminatı'), findsWidgets);
    });
  });
}
