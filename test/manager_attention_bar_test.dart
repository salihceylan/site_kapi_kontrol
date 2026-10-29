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
    expect(find.textContaining('2 tahsilat kasa / banka hesabına eşlenmedi'), findsOneWidget);
    expect(find.text('Hesaba Aktar'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    _expectNoMonthPanel();
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_unassigned_payments')));
    expect(opened, <(int, int)>[(1, FinanceHomeTab.cash)]);
  });

  
  testWidgets('bank_lines bekleyen iş varken açıklayıcı metin, İncele ve Onayla butonu ve onOpenBankLines çağrısı', (t) async {
    PeopleSite? openedSite;
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => _home(attention: const [FinanceHomeAttention(key: 'bank_lines', count: 4)]),
      onOpenFinance: (_, _) {},
      onOpenBankLines: (site) async => openedSite = site,
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('month_attention_bar')), findsOneWidget);
    expect(find.text('Dikkat edilmesi gereken 1 iş var'), findsOneWidget);
    expect(find.textContaining('Bankadan gelen 4 ödeme daireyle eşleştirilmeyi ve onayınızı bekliyor'), findsOneWidget);
    expect(find.text('İncele ve Onayla'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_bank_lines')));
    expect(openedSite?.code, 1);
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

  testWidgets('K17 tenant_debt_overdue_transfer: açık etiket + Devri İncele; onOpenLiabilityTransfer çağrılır ve satır yeniden yüklenir', (t) async {
    PeopleSite? openedSite;
    var fetches = 0;
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async {
        fetches++;
        return _home(attention: const [FinanceHomeAttention(key: 'tenant_debt_overdue_transfer', count: 3)]);
      },
      onOpenFinance: (_, _) => fail('doğrudan pencere varken Finans sekmesine gidilmez'),
      onOpenLiabilityTransfer: (site) async => openedSite = site,
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('3 dairede kiracının borcu gecikti; ev sahibine devredilebilir'), findsOneWidget);
    expect(find.textContaining('bekleyen iş var'), findsNothing, reason: 'genel "bekleyen iş var" metni değil, açık etiket');
    expect(find.text('Devri İncele'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_tenant_debt_overdue_transfer')));
    await t.pumpAndSettle();
    expect(openedSite?.code, 1);
    expect(fetches, 2, reason: 'pencereden dönünce dikkat satırları yeniden okunur');
  });

  testWidgets('K17 sayı kesilmiş listeden çıktıysa (at_least) "En az N dairede" yazılır; tam sayı gibi yazılmaz', (t) async {
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => FinanceHome.fromJson(<String, dynamic>{
        'month': '2026-10',
        'numbers': <String, dynamic>{},
        'attention': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'tenant_debt_overdue_transfer', 'count': 500, 'total_minor': 9000000, 'at_least': true},
        ],
      }),
      onOpenFinance: (_, _) {},
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('En az 500 dairede kiracının borcu gecikti'), findsOneWidget);
  });

  testWidgets('K17 tenant_debt_pending_transfer (kiracı ayrıldı): açık etiket; doğrudan pencere verilmezse Daireler sekmesine gider', (t) async {
    final opened = <(int, int)>[];
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async => _home(attention: const [FinanceHomeAttention(key: 'tenant_debt_pending_transfer', count: 2)]),
      onOpenFinance: (s, tab) => opened.add((s, tab)),
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('2 dairede kiracı ayrıldı, borcu kiracı hesabında duruyor; ev sahibine devredilebilir'), findsOneWidget);
    expect(find.text('Devri İncele'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_tenant_debt_pending_transfer')));
    expect(opened, <(int, int)>[(1, FinanceHomeTab.balances)]);
  });

  testWidgets('K4 refund_requests: "N iade talebi onayınızı bekliyor, toplam ..." + İadeleri İncele; onOpenRefunds çağrılır ve satır yeniden yüklenir; verilmezse Daireler sekmesine gider', (t) async {
    PeopleSite? openedSite;
    final opened = <(int, int)>[];
    var fetches = 0;
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      sites: sites,
      fetch: (_) async {
        fetches++;
        return FinanceHome.fromJson(<String, dynamic>{
          'month': '2026-10',
          'numbers': <String, dynamic>{},
          'attention': <Map<String, dynamic>>[
            <String, dynamic>{'key': 'refund_requests', 'count': 2, 'total_minor': 75000},
          ],
        });
      },
      onOpenFinance: (s, tab) => opened.add((s, tab)),
      onOpenRefunds: (site) async => openedSite = site,
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('2 iade talebi onayınızı bekliyor, toplam 750,00 ₺'), findsOneWidget);
    expect(find.textContaining('bekleyen iş var'), findsNothing, reason: 'genel metin değil, açık etiket');
    expect(find.text('İadeleri İncele'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_refund_requests')));
    await t.pumpAndSettle();
    expect(openedSite?.code, 1);
    expect(opened, isEmpty, reason: 'doğrudan pencere varken Finans sekmesine gidilmez');
    expect(fetches, 2, reason: 'pencereden dönünce dikkat satırları yeniden okunur');

    // pencere verilmezse Daireler (iade girişi) sekmesine gider
    await t.pumpWidget(_wrap(ManagerAttentionBar(
      key: const ValueKey<String>('no_dialog'),
      sites: sites,
      fetch: (_) async => FinanceHome.fromJson(<String, dynamic>{
        'month': '2026-10',
        'numbers': <String, dynamic>{},
        'attention': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'refund_requests', 'count': 1},
        ],
      }),
      onOpenFinance: (s, tab) => opened.add((s, tab)),
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('1 iade talebi onayınızı bekliyor'), findsOneWidget);
    expect(find.textContaining('toplam'), findsNothing, reason: 'toplam bilinmiyorsa yazılmaz');
    await t.tap(find.byKey(const ValueKey<String>('month_attention_1_refund_requests')));
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
    expect(find.textContaining('Site B: 5 tahsilat kasa / banka hesabına eşlenmedi'), findsOneWidget);
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
