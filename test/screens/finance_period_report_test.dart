// Dönemsel finans raporu ("Dönem raporu" rapor türü): iki Hesap kartı (Aidat / Fon), toplam, aylık kırılım, borçlu özeti; hazır dönem düğmeleri;
// rakamlar sunucudan (istemci hesaplamaz) ve birbirini tutar; dışa aktarma yalnız yönetici; kurul okur; taşma matrisi x açık-koyu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/period_report_models.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reports_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);
final List<List<ExportSource>> _launched = <List<ExportSource>>[];

Future<void> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  double width = 400,
  double height = 3600,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpList(
    t,
    FinanceReportsTab(
      scope: PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite),
      now: () => _now,
      exportLauncher: (context, sources) async => _launched.add(sources),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  await f4Tap(t, 'finance_report_chip_period_report');
  await settleFor(t);
}

void main() {
  setUp(_launched.clear);

  group('dönem raporu: model tutarlılığı', () {
    test('her Hesapta dönem sonu − dönem başı = dönem içi değişim; toplam iki Hesabın toplamı; aylık toplamlar dönem toplamına eşit', () {
      final r = PeriodReport.fromJson(f4PeriodJson());
      for (final f in [r.operating, r.capital]) {
        expect(f.closingMinor - f.openingMinor, f.changeMinor);
        expect(f.changeMinor, f.collectionsMinor - f.expensesMinor + f.transfersInMinor - f.transfersOutMinor + f.adjustmentsMinor);
        expect(f.expenseByCategory.fold<int>(0, (a, c) => a + c.totalMinor), f.expensesMinor);
      }
      expect(r.totals.closingMinor, r.operating.closingMinor + r.capital.closingMinor);
      expect(r.totals.collectionsMinor, r.months.fold<int>(0, (a, m) => a + m.collectionsMinor));
      expect(r.totals.expensesMinor, r.months.fold<int>(0, (a, m) => a + m.expensesMinor));
      expect(r.debtors.debtorCount, 1);
    });

    test('bozuk zorunlu tutar uydurma 0 olmaz: FormatException', () {
      final json = f4PeriodJson();
      ((json['funds'] as Map<String, dynamic>)['operating'] as Map<String, dynamic>).remove('closing_minor');
      expect(() => PeriodReport.fromJson(json), throwsFormatException);
    });
  });

  group('dönem raporu: ekran', () {
    f4Matrix('yönetici: iki Hesap kartı, toplam, aylık kırılım, borçlu özeti', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      final call = auth.f4.reportCalls.last;
      expect(call['name'], 'getPeriodReport');
      expect(call['from'], '2026-10');
      expect(call['to'], '2026-10', reason: 'varsayılan dönem: bu ay');
      for (final key in const ['fund_operating', 'fund_capital', 'totals', 'months', 'debtors']) {
        expect(find.byKey(ValueKey<String>('finance_period_$key')), findsOneWidget, reason: key);
      }
      expect(find.text('Dönem sonu bakiye'), findsNWidgets(3), reason: 'iki Hesap + toplam');
      expect(find.text('Gider kalemleri'), findsNWidgets(2));
      expect(find.text('Temizlik'), findsOneWidget);
      expect(find.text('Asansör'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget, reason: 'borçlu daire / daire sayısı; kişi bilgisi yok');
    });

    testWidgets('hazır dönem düğmesi raporu o aralıkla yeniden getirir; dışa aktarma yöneticide açılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await f4Tap(t, 'finance_period_preset_thisYear');
      await settleFor(t);
      final call = auth.f4.reportCalls.last;
      expect(call['from'], '2026-01');
      expect(call['to'], '2026-10');
      await f4Tap(t, 'finance_period_preset_lastYear');
      await settleFor(t);
      expect(auth.f4.reportCalls.last['from'], '2025-01');
      expect(auth.f4.reportCalls.last['to'], '2025-12');
      await f4Tap(t, 'finance_report_export');
      expect(_launched.single.single.label, 'Dönem raporu');
    });

    testWidgets('kurul okur ama dosya dışa aktaramaz ve PDF basamaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_period_fund_operating')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_report_export')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_report_pdf_print')), findsNothing);
    });
  });
}
