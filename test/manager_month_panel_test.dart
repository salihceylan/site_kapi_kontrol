import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_month_panel.dart';

FinanceHome _home({List<FinanceHomeStep>? steps, List<FinanceHomeAttention>? attention}) => FinanceHome.fromJson(<String, dynamic>{
      'month': '2026-10',
      'numbers': <String, dynamic>{
        'charged_minor': 1000000,
        'late_fee_minor': 0,
        'collected_minor': 400000,
        'collection_rate_bp': 4000,
        'overdue_apartment_count': 3,
        'apartment_count': 20,
        'cash_total_minor': null,
        'cash_account_count': 0,
      },
      'steps': <Map<String, dynamic>>[
        for (final s in steps ?? const <FinanceHomeStep>[])
          <String, dynamic>{'key': s.key, 'status': s.status, 'done': s.done, 'total': s.total, 'pending': s.pending},
      ],
      'attention': <Map<String, dynamic>>[
        for (final a in attention ?? const <FinanceHomeAttention>[]) <String, dynamic>{'key': a.key, 'count': a.count},
      ],
      'recent': <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'payment', 'date': '2026-10-02', 'amount_minor': 50000, 'label': 'A - 3'},
      ],
    });

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  const sites = <PeopleSite>[PeopleSite(code: 1, name: 'Site A', canWrite: true)];

  testWidgets('sayilar, adimlar, tek dugme ve son hareketler gorunur', (t) async {
    final opened = <(int, int)>[];
    await t.pumpWidget(_wrap(ManagerMonthPanel(
      sites: sites,
      fetch: (_) async => _home(
        steps: const [
          FinanceHomeStep(key: 'charge', status: 'done'),
          FinanceHomeStep(key: 'notify', status: 'todo'),
          FinanceHomeStep(key: 'match', status: 'todo', pending: 2),
          FinanceHomeStep(key: 'expense', status: 'todo'),
          FinanceHomeStep(key: 'report', status: 'todo'),
        ],
        attention: const [FinanceHomeAttention(key: 'unassigned_payments', count: 2)],
      ),
      onOpenFinance: (s, tab) => opened.add((s, tab)),
      onOpenAnnouncements: () {},
    )));
    await t.pumpAndSettle();
    expect(find.text('Bu ay · Ekim 2026'), findsOneWidget);
    expect(find.text('Geciken daire'), findsOneWidget);
    expect(find.text('Hesap yok'), findsOneWidget, reason: 'hesap yoksa 0 gosterilmez');
    expect(find.textContaining('2 tahsilat kasa / bankaya eşlenmedi'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('month_step_action_notify')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('month_step_action_expense')), findsNothing, reason: 'yalniz ilk yapilmamis adimda dugme');
    expect(find.textContaining('Tahsilat · A - 3'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('month_card_cash')));
    expect(opened, <(int, int)>[(1, FinanceHomeTab.cash)]);
  });

  testWidgets('hata: "Bu ayin ozeti alinamadi." ve tekrar dene; sayi gosterilmez', (t) async {
    var calls = 0;
    await t.pumpWidget(_wrap(ManagerMonthPanel(
      sites: sites,
      fetch: (_) async {
        calls++;
        throw Exception('x');
      },
      onOpenFinance: (_, _) {},
    )));
    await t.pumpAndSettle();
    expect(find.text('Bu ayın özeti alınamadı.'), findsOneWidget);
    expect(find.text('Geciken daire'), findsNothing);
    expect(calls, 1);
  });
}
