import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_attention_bar.dart';

FinanceHome _home({List<FinanceHomeAttention>? attention}) => FinanceHome.fromJson(<String, dynamic>{
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
        <String, dynamic>{'key': 'charge', 'status': 'done'},
        <String, dynamic>{'key': 'notify', 'status': 'todo'},
      ],
      'attention': <Map<String, dynamic>>[
        for (final a in attention ?? const <FinanceHomeAttention>[]) <String, dynamic>{'key': a.key, 'count': a.count},
      ],
      'recent': <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'payment', 'date': '2026-10-02', 'amount_minor': 50000, 'label': 'A - 3'},
      ],
    });

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

const List<String> _removedTexts = <String>[
  'Bu ay',
  'Aylık döngü',
  'Borç yaz',
  'Haber ver',
  'Tahsilatları eşle',
  'Giderleri gir',
  'Rapor al',
  'Yazılan',
  'Toplanan',
  'Geciken daire',
  'Kasa + banka',
  'Son hareketler',
];

void _expectNoMonthPanel() {
  for (final text in _removedTexts) {
    expect(find.textContaining(text), findsNothing, reason: '"$text" artık Panel\'de çizilmez');
  }
  expect(find.byKey(const ValueKey<String>('manager_month_panel')), findsNothing);
  expect(find.byKey(const ValueKey<String>('month_cycle')), findsNothing);
  expect(find.byKey(const ValueKey<String>('month_recent')), findsNothing);
}

void main() {
  const sites = <PeopleSite>[PeopleSite(code: 1, name: 'Site A', canWrite: true)];

  testWidgets('bekleyen iş varken yalnız koyu dikkat barı çıkar; Bu ay paneli, sayılar ve aylık döngü yok', (t) async {
    final opened = <(int, int)>[];
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => _home(attention: const [FinanceHomeAttention(key: 'unassigned_payments', count: 2)]),
      onOpenFinance: (s, tab) => opened.add((s, tab)),
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsOneWidget);
    expect(find.text('Dikkat edilmesi gereken 1 iş var'), findsOneWidget);
    expect(find.textContaining('2 tahsilat kasa / bankaya eşlenmedi'), findsOneWidget);
    expect(find.text('Eşle'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    _expectNoMonthPanel();
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_unassigned_payments')));
    expect(opened, <(int, int)>[(1, FinanceHomeTab.cash)]);
  });

  testWidgets('genel bekleyen iş varken buton İncele yazar ve bakiyeler sekmesini açar', (t) async {
    final opened = <(int, int)>[];
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => _home(attention: const [FinanceHomeAttention(key: 'general', count: 4)]),
      onOpenFinance: (s, tab) => opened.add((s, tab)),
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsOneWidget);
    expect(find.text('Dikkat edilmesi gereken 1 iş var'), findsOneWidget);
    expect(find.textContaining('4 bekleyen iş var'), findsOneWidget);
    expect(find.text('İncele'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_general')));
    expect(opened, <(int, int)>[(1, FinanceHomeTab.balances)]);
  });

  testWidgets('bekleyen iş yokken hiçbir şey çizilmez (boşluk bile yok)', (t) async {
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => _home(),
      onOpenFinance: (_, _) {},
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    _expectNoMonthPanel();
    expect(t.getSize(find.byType(ManagerAttentionBar)).height, 0, reason: 'iş yoksa yükseklik 0');
  });

  testWidgets('sayısı 0 olan iş çizilmez', (t) async {
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => _home(attention: const [FinanceHomeAttention(key: 'unassigned_payments', count: 0)]),
      onOpenFinance: (_, _) {},
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsNothing);
  });

  testWidgets('veri alınamazsa hata kutusu ya da sayı çizilmez; yükleme göstergesi de kalmaz', (t) async {
    var calls = 0;
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async {
        calls++;
        throw Exception('x');
      },
      onOpenFinance: (_, _) {},
    )));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('alınamadı'), findsNothing);
    _expectNoMonthPanel();
  });

  testWidgets('birden çok sitede her sitenin işi ayrı satır, site adıyla; biri hata verse öteki görünür', (t) async {
    const two = <PeopleSite>[
      PeopleSite(code: 1, name: 'Site A', canWrite: true),
      PeopleSite(code: 2, name: 'Site B', canWrite: true),
      PeopleSite(code: 3, name: 'Site C', canWrite: true),
    ];
    final opened = <(int, int)>[];
    final fetched = <int>[];
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: two,
      fetch: (code) async {
        fetched.add(code);
        if (code == 3) throw Exception('x');
        return _home(attention: code == 2 ? const [FinanceHomeAttention(key: 'unassigned_payments', count: 5)] : const []);
      },
      onOpenFinance: (s, tab) => opened.add((s, tab)),
    )));
    await t.pumpAndSettle();
    expect(fetched.toSet(), <int>{1, 2, 3});
    expect(find.text('Dikkat edilmesi gereken 1 iş var'), findsOneWidget);
    expect(find.textContaining('Site B: 5 tahsilat kasa / bankaya eşlenmedi'), findsOneWidget);
    expect(find.textContaining('Site A'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('month_attention_2_unassigned_payments')));
    expect(opened, <(int, int)>[(2, FinanceHomeTab.cash)]);
  });

  testWidgets('320 dp ve 2x yazıda taşmaz', (t) async {
    t.view.physicalSize = const Size(640, 1280);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2.0)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: ManagerAttentionBar(
              sites: const <PeopleSite>[PeopleSite(code: 1, name: 'Çok Uzun Adlı Güneş Vadisi Evleri Sitesi', canWrite: true)],
              fetch: (_) async => _home(attention: const [FinanceHomeAttention(key: 'unassigned_payments', count: 12)]),
              onOpenFinance: (_, _) {},
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
