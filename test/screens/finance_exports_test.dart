// Platform Faz 4b: gider listesi ve makbuz listesi dışa aktarma düğmeleri (Faz 2b ExportSource / ExportSheet altyapısı).
//
// Yalnız yönetici (kurul 403 alır, düğme çizilmez); dosya ekrandaki UYGULANMIŞ süzgeçlerle istenir; format yalnız
// denetim içindir; zarf sunucunun ham gövdesidir (CSV / XLSX'i istemci üretir).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show ExportFormat;
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_list_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_expenses_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;

import 'dialog_layout_harness.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

final List<List<ExportSource>> _launched = <List<ExportSource>>[];

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Future<void> _launcher(BuildContext context, List<ExportSource> sources) async => _launched.add(sources);

Future<void> _pumpExpenses(WidgetTester t, FinanceFakeAuth auth, {bool canWrite = true}) async {
  await pumpList(
    t,
    FinanceExpensesTab(scope: _scope(auth, canWrite: canWrite), onDataChanged: () {}, now: () => _now, exportLauncher: _launcher),
    width: 400,
    height: 2400,
    scale: 1.0,
    dark: false,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _openReceipts(WidgetTester t, FinanceFakeAuth auth, {bool canWrite = true, int? apartmentId}) async {
  await openDialogAt(
    t,
    (context) => FinanceReceiptListDialog.show(
      context,
      scope: _scope(auth, canWrite: canWrite),
      apartmentId: apartmentId,
      apartmentLabel: apartmentId == null ? null : 'A Blok - 5',
      now: () => _now,
      exportLauncher: _launcher,
    ),
    width: 400,
    height: 1200,
    scale: 1.0,
    dark: false,
  );
  await settleFor(t);
}

void main() {
  setUp(_launched.clear);

  group('giderler', () {
    testWidgets('yönetici: UYGULANMIŞ süzgeçler (dönem, durum, kategori, arama) kaynağa yazılır; format denetim için gider', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pumpExpenses(t, auth);
      await f4Tap(t, 'finance_expense_period_lastMonth');
      await settleFor(t);
      await f4Tap(t, 'finance_expense_status_all');
      await settleFor(t);
      await f4Tap(t, 'finance_expense_export');
      final source = _launched.single.single;
      expect(source.label, 'Giderler');
      expect(source.filterSummary, contains('Geçen ay'));
      expect(source.filterSummary, contains('Hepsi'));
      final envelope = await source.fetch(ExportFormat.xlsx);
      expect(envelope.kind, 'finance_expenses');
      expect(auth.f4.exportCalls.single, <String, Object?>{
        'kind': 'finance_expenses',
        'from': '2026-09-01',
        'to': '2026-09-30',
        'status': 'all',
        'format': 'xlsx',
      });
    });

    testWidgets('varsayılan: bu ay + yalnız geçerli giderler', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pumpExpenses(t, auth);
      await f4Tap(t, 'finance_expense_export');
      await _launched.single.single.fetch(ExportFormat.csv);
      expect(auth.f4.exportCalls.single['from'], '2026-10-01');
      expect(auth.f4.exportCalls.single['to'], '2026-10-31');
      expect(auth.f4.exportCalls.single['status'], 'active');
      expect(auth.f4.exportCalls.single.containsKey('q'), isFalse);
    });

    testWidgets('kurul: düğme YOK', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pumpExpenses(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_expense_export')), findsNothing);
    });
  });

  group('makbuzlar', () {
    testWidgets('yönetici: yıl süzgeci kaynağa yazılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openReceipts(t, auth);
      await f4Tap(t, 'finance_receipts_export');
      final source = _launched.single.single;
      expect(source.label, 'Makbuzlar');
      expect(source.filterSummary, contains('2026 yılı'));
      await source.fetch(ExportFormat.csv);
      expect(auth.f4.exportCalls.single, <String, Object?>{'kind': 'finance_receipts', 'year': '2026', 'format': 'csv'});
    });

    testWidgets('tüm yıllar + daire süzgeci', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openReceipts(t, auth, apartmentId: 301);
      await f4Tap(t, 'finance_receipts_year_all');
      await settleFor(t);
      await f4Tap(t, 'finance_receipts_export');
      final source = _launched.single.single;
      expect(source.filterSummary, contains('Tüm yıllar'));
      expect(source.filterSummary, contains('A Blok - 5'));
      await source.fetch(ExportFormat.xlsx);
      expect(auth.f4.exportCalls.single, <String, Object?>{'kind': 'finance_receipts', 'apartment_id': '301', 'format': 'xlsx'});
    });

    testWidgets('kurul: düğme YOK (Makbuz Doğrula kalır)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openReceipts(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_receipts_export')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_receipts_verify')), findsOneWidget);
    });

    f4Matrix('iki düğmeli satır taşmaz', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await openDialogAt(
        t,
        (context) => FinanceReceiptListDialog.show(context, scope: _scope(auth), now: () => _now, exportLauncher: _launcher),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_receipts_export')));
    });
  });
}
