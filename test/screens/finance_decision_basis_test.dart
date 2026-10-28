// Tahakkuk dayanağı (K2, P1-2) ve sakin kalem dökümü (P2-1) ekranları.
//
// 1. "Borçlandır" / "Ek Borç Ekle" penceresi: önizleme `decision_requirement` isterse Karar Defteri açık sitede kesin karar seçilmeden,
//    kapalı sitede gerekçe yazılmadan ONAY KAPALIDIR; seçim/gerekçe onay isteğine (`decision_id` / `decision_reason`) gider; dayanak
//    istenmiyorsa (işletme hesabı, eski sunucu) hiçbir şey çizilmez/gönderilmez.
// 2. Sakin "Borcum": "Borç kalemleri" açılımı her ödenmemiş kalemin kaynağını (dönem, tür, hesap) ve dayanağını (karar no / gerekçe) gösterir.
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_run_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/debt_breakdown_panel.dart';

import 'decision_fixtures.dart';
import 'dialog_layout_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart';

final DateTime _now = DateTime.utc(2026, 10, 28, 9);

// --------------------------------------------------------------------------------------------------------------------
// Pencere
// --------------------------------------------------------------------------------------------------------------------

Map<String, dynamic> _requirement(String mode) => <String, dynamic>{
  'required': mode != 'none',
  'mode': mode,
  'module_enabled': mode == 'decision',
  'reason_min': 3,
  'reason_max': 300,
};

class _Open {
  _Open(this.auth, this.decisions);

  final FinanceFakeAuth auth;
  final FakeDecisionService decisions;
  FinanceRunOutcome? result;
}

FakeDecisionService _decisionService(FinanceFakeAuth auth, {bool withDecisions = true}) {
  final service = FakeDecisionService(authService: auth);
  if (withDecisions) {
    service.rows
      ..add(dcJson(1, date: '2026-10-12', status: 'kesin', no: 4, title: 'Asansör yenileme', vote: 'kabul'))
      ..add(dcJson(2, date: '2026-09-02', status: 'kesin', no: 3, title: 'Çatı onarımı', vote: 'kabul'))
      ..add(dcJson(3, date: '2026-10-20', title: 'Henüz taslak olan karar'));
  }
  return service;
}

Future<_Open> _openCharge(
  WidgetTester t, {
  String? mode,
  bool withDecisions = true,
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  FeeDefinition? definition,
}) async {
  final auth = FinanceFakeAuth.seeded();
  if (mode != null) auth.decisionRequirementJson = _requirement(mode);
  final decisions = _decisionService(auth, withDecisions: withDecisions);
  final open = _Open(auth, decisions);
  final scope = PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);
  await openDialogAt(
    t,
    (context) async {
      open.result = definition == null
          ? await FinanceRunDialog.showCharge(context, scope: scope, now: () => _now, decisionService: decisions)
          : await FinanceRunDialog.showDefinition(context, scope: scope, definition: definition, now: () => _now, decisionService: decisions);
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return open;
}

Future<void> _enter(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await scrollTo(t, finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _fillChargeAndPreview(WidgetTester t) async {
  await _enter(t, 'finance_charge_name', 'Asansör yenileme');
  await _tapKey(t, 'charge_spec_dist_equal');
  await _enter(t, 'charge_spec_amount', '100.000');
  await _tapKey(t, 'finance_run_preview');
  await settleFor(t);
}

bool _confirmEnabled(WidgetTester t) =>
    t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_run_confirm'))).onPressed != null;

Future<void> _pickDecision(WidgetTester t, String label) async {
  await _tapKey(t, 'run_basis_decision');
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

void main() {
  group('pencere: dayanak istenmiyorsa', () {
    testWidgets('önizleme decision_requirement göndermezse (eski sunucu / işletme hesabı) dayanak alanı ÇİZİLMEZ ve onay eskisi gibi çalışır', (t) async {
      final open = await _openCharge(t);
      await _fillChargeAndPreview(t);
      expect(find.byKey(const ValueKey<String>('run_basis_panel')), findsNothing);
      expect(_confirmEnabled(t), isTrue);
      await _tapKey(t, 'finance_run_confirm');
      await settleFor(t);
      final post = open.auth.chargePostCalls.single;
      expect(post.containsKey('decision_id'), isFalse);
      expect(post.containsKey('decision_reason'), isFalse);
      expect(open.decisions.listManagedCalls, isEmpty, reason: 'Karar Defteri hiç sorgulanmaz');
    });

    testWidgets('mod "none" (işletme hesabı): dayanak alanı yok, karar listesi yüklenmez', (t) async {
      final open = await _openCharge(t, mode: 'none');
      await _fillChargeAndPreview(t);
      expect(find.byKey(const ValueKey<String>('run_basis_panel')), findsNothing);
      expect(_confirmEnabled(t), isTrue);
      expect(open.decisions.listManagedCalls, isEmpty);
    });
  });

  group('pencere: Karar Defteri AÇIK (karar seçimi zorunlu)', () {
    testWidgets('karar seçilmeden onay KAPALI; neden yazılır; yalnız KESİN kararlar listelenir (taslak yok)', (t) async {
      final open = await _openCharge(t, mode: 'decision');
      await _fillChargeAndPreview(t);
      expect(find.byKey(const ValueKey<String>('run_basis_panel')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('run_basis_decision')), findsOneWidget);
      expect(open.decisions.listManagedCalls.single.status, 'kesin');
      expect(open.decisions.listManagedCalls.single.site, 11);
      expect(_confirmEnabled(t), isFalse);
      expect(find.byKey(const ValueKey<String>('finance_run_blocked_reason')), findsOneWidget);
      expect(find.text('Onaylamak için: Dayanak olarak Karar Defteri\'nden bir karar seçin.'), findsOneWidget);
      await _tapKey(t, 'run_basis_decision');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('2026/4 • Asansör yenileme • 12.10.2026'), findsWidgets);
      expect(find.text('2026/3 • Çatı onarımı • 02.09.2026'), findsWidgets);
      expect(find.textContaining('Henüz taslak olan karar'), findsNothing);
    });

    testWidgets('karar seçilince onay açılır ve onay isteği decision_id taşır (gerekçe yok); başarı normal', (t) async {
      final open = await _openCharge(t, mode: 'decision');
      await _fillChargeAndPreview(t);
      await _pickDecision(t, '2026/4 • Asansör yenileme • 12.10.2026');
      expect(_confirmEnabled(t), isTrue);
      expect(find.byKey(const ValueKey<String>('run_basis_selected_note')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_run_blocked_reason')), findsNothing);
      await _tapKey(t, 'finance_run_confirm');
      await settleFor(t);
      final post = open.auth.chargePostCalls.single;
      expect(post['decision_id'], 1);
      expect(post.containsKey('decision_reason'), isFalse);
      expect(open.result!.message, 'Ek borç yazıldı: 3 daire, toplam 100.000,00 ₺.');
    });

    testWidgets('aylık borçlandırma: seçilen karar postFeeRun\'a gider', (t) async {
      final auth0 = FinanceFakeAuth.seeded();
      final open = await _openCharge(t, mode: 'decision', definition: FeeDefinition.fromJson(auth0.definitions[1]!));
      await _tapKey(t, 'finance_run_preview');
      await settleFor(t);
      expect(_confirmEnabled(t), isFalse);
      await _pickDecision(t, '2026/3 • Çatı onarımı • 02.09.2026');
      expect(_confirmEnabled(t), isTrue);
      await _tapKey(t, 'finance_run_confirm');
      await settleFor(t);
      expect(open.auth.postCalls.single['decision_id'], 2);
      expect(open.auth.postCalls.single.containsKey('decision_reason'), isFalse);
    });

    testWidgets('kesin karar yoksa uyarı gösterilir ve onay KAPALI kalır (önce Karar Defteri\'nde karar eklenir)', (t) async {
      await _openCharge(t, mode: 'decision', withDecisions: false);
      await _fillChargeAndPreview(t);
      expect(find.byKey(const ValueKey<String>('run_basis_empty')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('run_basis_decision')), findsNothing);
      expect(_confirmEnabled(t), isFalse);
    });

    testWidgets('karar listesi yüklenemezse hata + "Tekrar Dene"; tekrar denenince yüklenir', (t) async {
      final auth = FinanceFakeAuth.seeded()..decisionRequirementJson = _requirement('decision');
      final decisions = _decisionService(auth)..failures['listManaged'] = <Object>[Exception('ağ')];
      final scope = PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);
      await openDialogAt(
        t,
        (context) => FinanceRunDialog.showCharge(context, scope: scope, now: () => _now, decisionService: decisions),
        width: 400,
        height: 1600,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await _fillChargeAndPreview(t);
      expect(find.byKey(const ValueKey<String>('run_basis_error')), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('run_basis_decision')), findsOneWidget);
      expect(decisions.listManagedCalls.length, 2);
    });
  });

  group('pencere: Karar Defteri KAPALI (gerekçe zorunlu)', () {
    testWidgets('gerekçe yazılmadan onay KAPALI; yazılınca açılır ve onay isteği decision_reason taşır (karar kimliği yok); karar listesi hiç sorgulanmaz', (t) async {
      final open = await _openCharge(t, mode: 'reason');
      await _fillChargeAndPreview(t);
      expect(find.byKey(const ValueKey<String>('run_basis_reason')), findsOneWidget);
      expect(find.text('Bu gerekçe sakinlerin Borcum ekranındaki borç dökümünde görünür.'), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
      expect(find.text('Onaylamak için: Borcun dayanağını (gerekçe) yazın.'), findsOneWidget);
      await _enter(t, 'run_basis_reason', 'ab');
      expect(_confirmEnabled(t), isFalse, reason: 'en az 3 karakter');
      await _enter(t, 'run_basis_reason', '  Yönetim kurulunun 14 Ekim tarihli kararı  ');
      expect(_confirmEnabled(t), isTrue);
      await _tapKey(t, 'finance_run_confirm');
      await settleFor(t);
      final post = open.auth.chargePostCalls.single;
      expect(post['decision_reason'], 'Yönetim kurulunun 14 Ekim tarihli kararı');
      expect(post.containsKey('decision_id'), isFalse);
      expect(open.decisions.listManagedCalls, isEmpty);
    });

    testWidgets('boşluk-yalnız gerekçe geçersiz sayılır; 300 karakterden uzun gerekçe geçersiz', (t) async {
      await _openCharge(t, mode: 'reason');
      await _fillChargeAndPreview(t);
      await _enter(t, 'run_basis_reason', '        ');
      expect(_confirmEnabled(t), isFalse);
      await _enter(t, 'run_basis_reason', 'x' * 301);
      expect(_confirmEnabled(t), isFalse);
      await _enter(t, 'run_basis_reason', 'x' * 300);
      expect(_confirmEnabled(t), isTrue);
    });

    testWidgets('Geri -> yeniden önizleme: yazılan gerekçe KORUNUR', (t) async {
      await _openCharge(t, mode: 'reason');
      await _fillChargeAndPreview(t);
      await _enter(t, 'run_basis_reason', 'Genel kurul kararı, 12 Ekim');
      await _tapKey(t, 'finance_run_back');
      await _tapKey(t, 'finance_run_preview');
      await settleFor(t);
      expect(find.text('Genel kurul kararı, 12 Ekim'), findsOneWidget);
      expect(_confirmEnabled(t), isTrue);
    });
  });

  group('taşma matrisi: pencere', () {
    layoutMatrix('Karar Defteri açık: karar seçici', (t, w, h, s, dark) async {
      await _openCharge(t, mode: 'decision', width: w, height: h, scale: s, dark: dark);
      await _fillChargeAndPreview(t);
      await scrollTo(t, find.byKey(const ValueKey<String>('run_basis_decision')));
      expect(find.byKey(const ValueKey<String>('run_basis_panel')), findsOneWidget);
    });

    layoutMatrix('Karar Defteri kapalı: gerekçe alanı', (t, w, h, s, dark) async {
      await _openCharge(t, mode: 'reason', width: w, height: h, scale: s, dark: dark);
      await _fillChargeAndPreview(t);
      await _enter(t, 'run_basis_reason', 'Yönetim kurulunun 14 Ekim tarihli ve 6 sayılı kararı uyarınca demirbaş katkı payı');
      await scrollTo(t, find.byKey(const ValueKey<String>('run_basis_reason')));
      expect(find.byKey(const ValueKey<String>('run_basis_panel')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------------------------
  // Sakin: kalem dökümü
  // ------------------------------------------------------------------------------------------------------------------

  Map<String, dynamic> breakdownJson() => <String, dynamic>{
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'entry_id': 902,
        'type': 'one_time',
        'name': 'Asansör yenileme',
        'fund': 'capital',
        'period': '2026-10',
        'due_date': '2026-10-15',
        'overdue': true,
        'amount_minor': 100000,
        'remaining_minor': 93000,
        'decision': <String, dynamic>{'number_label': '2026/4', 'title': 'Asansör yenileme', 'reason': null},
      },
      <String, dynamic>{
        'entry_id': 903,
        'type': 'one_time',
        'name': 'Dış cephe',
        'fund': 'capital',
        'period': '2026-10',
        'due_date': '2026-11-20',
        'overdue': false,
        'amount_minor': 50000,
        'remaining_minor': 50000,
        'decision': <String, dynamic>{'number_label': null, 'title': null, 'reason': 'Yönetim kurulunun 3 Ekim tarihli kararı'},
      },
      <String, dynamic>{
        'entry_id': 904,
        'type': 'monthly',
        'name': 'Aidat',
        'fund': 'operating',
        'period': '2026-10',
        'due_date': '2026-10-05',
        'overdue': true,
        'amount_minor': 3000,
        'remaining_minor': 3000,
        'decision': null,
      },
    ],
    'truncated': false,
  };

  Future<void> pumpMyFinance(WidgetTester t, FinanceFakeAuth auth, {double width = 400, double height = 2600, double scale = 1.0, bool dark = false}) async {
    await pumpList(t, MyFinanceView(authService: auth), width: width, height: height, scale: scale, dark: dark);
    await settleFor(t, 100);
    await settleFor(t, 100);
  }

  group('sakin Borcum: kalem dökümü', () {
    testWidgets('varsayılan KAPALI; düğme sayıyı gösterir; açılınca her kalemin kaynağı, kalan tutarı ve dayanağı görünür', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem(breakdown: breakdownJson())];
      await pumpMyFinance(t, auth);
      expect(find.byType(DebtBreakdownPanel), findsOneWidget);
      expect(find.text('Borç kalemleri (3)'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_breakdown_item_902')), findsNothing);

      await tapFinder(t, find.byKey(const ValueKey<String>('my_finance_breakdown_toggle')));
      expect(find.text('Borç kalemlerini gizle'), findsOneWidget);
      // 902: kaynak (dönem • tür • hesap), tutarlar, vade ve KARAR NUMARASI
      expect(find.text('Ekim 2026 • Ek borç • Fon Hesabı'), findsNWidgets(2));
      expect(find.byKey(const ValueKey<String>('debt_item_remaining_902')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('debt_item_remaining_902'))).data, '930,00 ₺');
      expect(find.text('Tutar 1.000,00 ₺ • Ödenen 70,00 ₺'), findsOneWidget);
      expect(find.text('Vadesi geçti: 15.10.2026'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('debt_item_basis_902'))).data, 'Dayanak: Karar 2026/4 · Asansör yenileme');
      // 903: kapalı modül gerekçesi; vadesi gelmemiş
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('debt_item_basis_903'))).data, 'Dayanak: Gerekçe: Yönetim kurulunun 3 Ekim tarihli kararı');
      expect(find.text('Vade: 20.11.2026'), findsOneWidget);
      expect(find.text('Tutar 500,00 ₺'), findsOneWidget, reason: 'hiç ödenmemiş kalemde "Ödenen" yazılmaz');
      // 904: işletme hesabı aidatı, dayanaksız
      expect(find.text('Ekim 2026 • Aylık borç • Aidat Hesabı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('debt_item_basis_904')), findsNothing);

      await tapFinder(t, find.byKey(const ValueKey<String>('my_finance_breakdown_toggle')));
      expect(find.byKey(const ValueKey<String>('my_finance_breakdown_item_902')), findsNothing);
    });

    testWidgets('eski sunucu (breakdown yok) ya da boş döküm: bölüm çizilmez, ekran "borç yok" DEMEZ', (t) async {
      final legacy = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await pumpMyFinance(t, legacy);
      expect(find.byType(DebtBreakdownPanel), findsNothing);
      expect(find.text('Borcunuz yok.'), findsNothing);
      final empty = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem(breakdown: <String, dynamic>{'items': <dynamic>[], 'truncated': false})];
      await pumpMyFinance(t, empty);
      expect(find.byType(DebtBreakdownPanel), findsNothing);
    });

    testWidgets('sunucu çok kalemi kestiyse not yazılır', (t) async {
      final json = breakdownJson()..['truncated'] = true;
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem(breakdown: json)];
      await pumpMyFinance(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('my_finance_breakdown_toggle')));
      expect(find.byKey(const ValueKey<String>('my_finance_breakdown_truncated')), findsOneWidget);
    });

    testWidgets('son hareketler satırı da dayanağı gösterir (borç satırı); tahsilat satırında dayanak yok', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(
            recent: <Map<String, dynamic>>[
              <String, dynamic>{
                ...finEntry(31, 301, amount: 93000, dueDate: '2026-10-15', definitionName: 'Asansör yenileme'),
                'description': null,
                'reversal_reason': null,
                'created_by_name': null,
                'decision': <String, dynamic>{'number_label': '2026/4', 'title': null, 'reason': null},
              },
            ],
          ),
        ];
      await pumpMyFinance(t, auth);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('ledger_basis_31'))).data, 'Dayanak: Karar 2026/4');
    });

    listMatrix('kalem dökümü açık', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem(breakdown: breakdownJson())];
      await pumpMyFinance(t, auth, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, find.byKey(const ValueKey<String>('my_finance_breakdown_toggle')));
      expect(find.byKey(const ValueKey<String>('my_finance_breakdown_item_903')), findsOneWidget);
    });
  });
}
