// İki kasa (docs/PLATFORM_FINANS_KASALAR.md §6): "İşletme Projesi (Aidat) Hesabı" ve "Yatırım ve Demirbaş (Fon) Hesabı".
//
// Kapsam: Finans > Kasa sekmesinin üst bölümü (iki kasa kartı, avans, eşlenmemiş / fark / eksi bakiye notları, dönem seçimi,
// sayfalı döküm), "Kasalar Arası Aktarım" penceresi ve listesi (gerekçeli ters çevirme), tahsilat / gider / kategori / tanım /
// ek borç formlarındaki "Kasa" seçimi, daire ekstresi, sakin "Borcum" ve makbuz görünümü.
//
// AGENTS.md kural 6: dört hücre (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) x açık / koyu tema; kural 7: yazma
// sonrası veriler kendiliğinden yenilenir. Eski sunucu (kasa alanları yok) çökmez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/finance_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_catalog_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_expense_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_fund_transfer_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_cash_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_funds_section.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

FinanceFakeAuth _auth({bool accounts = true}) {
  final auth = FinanceFakeAuth.seeded();
  if (accounts) {
    auth.f4.accounts
      ..add(f4AccountJson(1, 'Nakit Kasa', balance: 250050, opening: 100000))
      ..add(f4AccountJson(2, 'Ziraat Bankası', kind: 'bank', balance: 1200000, opening: 1000000));
  }
  return auth;
}

/// "Kasa" seçim satırı seçili mi? (Seçili satır dolu radyo simgesi taşır.)
bool _fundSelected(WidgetTester t, String key) => find
    .descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byIcon(Icons.radio_button_checked_rounded))
    .evaluate()
    .isNotEmpty;

String _text(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

Map<String, dynamic> _movement(int i, {String type = 'collection', int amount = 100000, String label = 'Aylık aidat'}) => <String, dynamic>{
  'key': '$type:$i',
  'type': type,
  'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
  'amount_minor': amount + i,
  'label': label,
  'apartment': type == 'collection' ? <String, dynamic>{'id': 301, 'label': 'A Blok - 5'} : null,
  'account': null,
  'category': type == 'expense' ? 'Asansör bakım' : null,
  'ref_id': i,
};

Map<String, dynamic> _transferRow(int id, {String from = 'operating', String to = 'capital', int amount = 150000, int? reverses, int? reversedBy, String? reason, String? description = 'Kurul kararı'}) =>
    <String, dynamic>{
      'id': id,
      'from_fund': from,
      'to_fund': to,
      'amount_minor': amount,
      'transfer_date': '2026-10-10',
      'period': '2026-10',
      'description': description,
      'reverses_transfer_id': reverses,
      'reversed_by_transfer_id': reversedBy,
      'reversal_reason': reason,
      'created_by_name': 'Site Yöneticisi',
      'created_at': '2026-10-10T09:00:00Z',
    };

int _sectionChanged = 0;

Future<GlobalKey<FinanceFundsSectionState>> _pumpSection(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  double width = 400,
  double height = 3000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<FinanceFundsSectionState>();
  _sectionChanged = 0;
  await pumpList(
    t,
    FinanceFundsSection(key: key, scope: _scope(auth, canWrite: canWrite), onDataChanged: () => _sectionChanged++, now: () => _now),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Future<void> _tap(WidgetTester t, String key) async {
  await f4Tap(t, key);
  await settleFor(t);
}

void main() {
  group('kasa bölümü: taşma matrisi', () {
    layoutMatrix('dolu: iki kart, avans, eşlenmemiş + fark + eksi bakiye notları, açık döküm, düğmeler', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4
        ..fundBase['capital']!['expenses'] = 900000 // fon bakiyesi eksiye düşer
        ..fundsBalanced = false
        ..fundsDifferenceMinor = 4500
        ..fundsUnassignedCount = 3
        ..fundsUnassignedTotal = 150000
        ..fundMovementRows['operating'] = <Map<String, dynamic>>[
          for (var i = 0; i < 3; i++) _movement(i, label: 'Çok uzun bir tahsilat açıklaması: ekim ayı aylık aidat ve ek katkı payı ödemesi'),
          _movement(8, type: 'expense', amount: -250000, label: 'Eylül ayı asansör bakım bedeli'),
        ];
      await _pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_operating')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_capital')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_funds_unassigned')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_funds_unbalanced')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fund_negative_capital')), findsOneWidget);
      await _tap(t, 'fund_movements_toggle_operating');
      expect(find.byType(FundMovementTile), findsNWidgets(4));
      for (final key in const ['fund_balance_capital', 'finance_funds_advance', 'finance_funds_transfer', 'finance_funds_transfers']) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    layoutMatrix('yükleniyor: iskelet; "0" yazılmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.fundSummaryGate = Completer<void>();
      await _pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_operating')), findsNothing);
      auth.f4.fundSummaryGate!.complete();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_operating')), findsOneWidget);
    });

    layoutMatrix('hata: Tekrar Dene; eski tutar ve "0" yok', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.fundSummaryError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_funds_error')), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_operating')), findsNothing);
      expect(find.textContaining('0,00 ₺'), findsNothing);
    });

    layoutMatrix('tüm Kasa sekmesi: iki kasa bölümü + nakit / banka hesapları birlikte', (t, w, h, s, dark) async {
      final auth = _auth();
      await pumpList(t, FinanceCashTab(scope: _scope(auth), onDataChanged: () {}, now: () => _now), width: w, height: h, scale: s, dark: dark);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byKey(const ValueKey<String>('finance_funds_section')), findsOneWidget);
      expect(find.text('Nakit ve banka hesapları'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_total')), findsOneWidget);
    });
  });

  group('kasa bölümü: davranış', () {
    testWidgets('iki kart TAM adlarla; bakiye, açılış, tahsilat, gider, aktarım, düzeltme; avans satırı', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      expect(_text(t, 'fund_title_operating'), 'İşletme Projesi (Aidat) Hesabı');
      expect(_text(t, 'fund_title_capital'), 'Yatırım ve Demirbaş (Fon) Hesabı');
      expect(find.text('Borcu dairede oturan öder (kiracı varsa kiracı)'), findsOneWidget);
      expect(find.text('Borcu malik öder'), findsOneWidget);
      // sunucu rakamları: İşletme 10.000 + 5.000 − 2.000 = 13.000; Fon 3.000
      expect(_text(t, 'fund_balance_operating'), '13.000,00 ₺');
      expect(_text(t, 'fund_balance_capital'), '3.000,00 ₺');
      expect(find.text('Dönem başı'), findsNWidgets(2));
      for (final label in const ['Tahsilat', 'Gider', 'Aktarım (giren)', 'Aktarım (çıkan)', 'Düzeltme']) {
        expect(find.text(label), findsNWidgets(2), reason: label);
      }
      expect(_text(t, 'finance_funds_advance_amount'), '250,00 ₺');
      // dengeli ve eşlenmemiş yok: not yok
      expect(find.byKey(const ValueKey<String>('finance_funds_unassigned')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_funds_unbalanced')), findsNothing);
      expect(find.byType(InlineNotice), findsNothing);
    });

    testWidgets('dönem seçimi: Bu ay (varsayılan) / Geçen ay / Tüm zamanlar -> özet ve açılış etiketi buna göre', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      expect(auth.f4.fundSummaryCalls.last, <String, Object?>{'from': '2026-10-01', 'to': '2026-10-16'});
      await _tap(t, 'finance_funds_period_lastMonth');
      expect(auth.f4.fundSummaryCalls.last, <String, Object?>{'from': '2026-09-01', 'to': '2026-09-30'});
      await _tap(t, 'finance_funds_period_all');
      expect(auth.f4.fundSummaryCalls.last, <String, Object?>{'from': null, 'to': null});
      expect(find.text('Açılış'), findsNWidgets(2), reason: 'tüm zamanlarda "Dönem başı" yerine "Açılış"');
      expect(find.text('Dönem başı'), findsNothing);
    });

    testWidgets('eşlenmemiş tahsilat: bilgi notu; dengesiz: fark notu; eksi bakiye: uyarı (engellenmez)', (t) async {
      final auth = _auth();
      auth.f4
        ..fundsUnassignedCount = 2
        ..fundsUnassignedTotal = 90000
        ..fundsBalanced = false
        ..fundsDifferenceMinor = -4500
        ..fundBase['capital']!['expenses'] = 900000;
      await _pumpSection(t, auth);
      expect(find.textContaining('eşlenmemiş 2 tahsilat var (900,00 ₺)'), findsOneWidget);
      expect(find.textContaining('45,00 ₺ fazla'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fund_negative_capital')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fund_negative_operating')), findsNothing);
      expect(find.text('Bakiye eksi'), findsOneWidget);
      auth.f4.fundsDifferenceMinor = 4500;
      final key = await _pumpSection(t, auth);
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.textContaining('45,00 ₺ eksik'), findsOneWidget);
    });

    testWidgets('hata asla "0" demez; Tekrar Dene toparlar; yenileme eski hatayı temizler', (t) async {
      final auth = _auth();
      auth.f4.fundSummaryError = ApiException('x', statusCode: 500);
      final key = await _pumpSection(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_funds_error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_operating')), findsNothing);
      auth.f4.fundSummaryError = null;
      await _tap(t, 'finance_funds_period_thisMonth');
      expect(find.byKey(const ValueKey<String>('finance_funds_error')), findsOneWidget, reason: 'seçili çipe tekrar dokunmak yeniden yüklemez');
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_funds_error')), findsNothing);
      expect(_text(t, 'fund_balance_operating'), '13.000,00 ₺');
    });

    testWidgets('sitede hesap yoksa bilgi notu; kartlar yine sunucu rakamıyla çizilir', (t) async {
      final auth = _auth(accounts: false);
      auth.f4.fundsHasAccounts = false;
      await _pumpSection(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_funds_no_accounts')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_fund_card_operating')), findsOneWidget);
    });

    testWidgets('kurul: aktarım düğmesi YOK, aktarım listesi VAR', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_funds_transfer')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_funds_transfers')), findsOneWidget);
    });

    testWidgets('sekme yenilenince (FinanceCashTab.reload) iki kasa da tazelenir', (t) async {
      final auth = _auth();
      final key = GlobalKey<FinanceCashTabState>();
      await pumpList(t, FinanceCashTab(key: key, scope: _scope(auth), onDataChanged: () {}, now: () => _now), width: 400, height: 3000, scale: 1.0, dark: false);
      await settleFor(t, 100);
      await settleFor(t, 100);
      final before = auth.f4.callCount('getFundSummary');
      auth.f4.fundBase['operating']!['collections'] = 700000;
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.f4.callCount('getFundSummary'), before + 1);
      expect(_text(t, 'fund_balance_operating'), '15.000,00 ₺');
    });
  });

  group('kasa dökümü (sayfalı)', () {
    testWidgets('Hareketler açılır: 25\'erli; "Daha fazla yükle" sonraki sayfayı offset ile alır; kapatılır', (t) async {
      final auth = _auth();
      auth.f4.fundMovementRows['operating'] = <Map<String, dynamic>>[for (var i = 0; i < 30; i++) _movement(i)];
      await _pumpSection(t, auth);
      expect(find.byType(FundMovementTile), findsNothing);
      await _tap(t, 'fund_movements_toggle_operating');
      expect(auth.f4.fundMovementCalls.single['fund'], 'operating');
      expect(auth.f4.fundMovementCalls.single['limit'], 25);
      expect(auth.f4.fundMovementCalls.single['offset'], 0);
      expect(find.byType(FundMovementTile), findsNWidgets(25));
      await _tap(t, 'finance_funds_period_all'); // dönem değişince döküm yeniden kurulur
      expect(find.byType(FundMovementTile), findsNWidgets(25));
      await f4TapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.f4.fundMovementCalls.last['offset'], 25);
      expect(find.byType(FundMovementTile), findsNWidgets(30));
      expect(find.text('Daha fazla yükle'), findsNothing);
      await _tap(t, 'fund_movements_toggle_operating');
      expect(find.byType(FundMovementTile), findsNothing);
      await _tap(t, 'fund_movements_toggle_capital');
      expect(auth.f4.fundMovementCalls.last['fund'], 'capital');
      expect(find.textContaining('için hareket yok'), findsOneWidget, reason: 'boş kasa: açıklayıcı durum');
    });

    testWidgets('satır: tür rozeti, tarih, işaretli tutar, daire etiketi / kategori; giderde eksi', (t) async {
      final auth = _auth();
      auth.f4.fundMovementRows['operating'] = <Map<String, dynamic>>[
        _movement(5),
        _movement(6, type: 'expense', amount: -250000, label: 'Asansör bakımı'),
      ];
      await _pumpSection(t, auth);
      await _tap(t, 'fund_movements_toggle_operating');
      expect(find.text('Tahsilat'), findsWidgets);
      expect(find.text('Gider'), findsWidgets);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('Asansör bakım'), findsOneWidget);
      expect(find.textContaining('-2.499,94 ₺'), findsOneWidget, reason: 'işaretli tutar');
      expect(find.text('06.10.2026'), findsOneWidget);
    });

    testWidgets('döküm hatası "hareket yok" demez; Tekrar Dene', (t) async {
      final auth = _auth();
      auth.f4.fundMovementsError = ApiException('x', statusCode: 500);
      await _pumpSection(t, auth);
      await _tap(t, 'fund_movements_toggle_operating');
      expect(find.textContaining('için hareket yok'), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      auth.f4.fundMovementsError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.textContaining('için hareket yok'), findsOneWidget);
    });
  });

  group('kasalar arası aktarım', () {
    testWidgets('çıkış kasası seçilir, giriş diğeridir; kayıt gövdesi kesin; özet ve onDataChanged kendiliğinden yenilenir', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfer');
      expect(find.text('Kasalar Arası Aktarım'), findsWidgets);
      expect(find.text('Aidat Hesabı → Fon Hesabı'), findsNothing);
      await f4Tap(t, 'finance_fund_transfer_from_operating');
      expect(_fundSelected(t, 'finance_fund_transfer_from_operating'), isTrue);
      expect(find.textContaining('Giriş kasası: Yatırım ve Demirbaş (Fon) Hesabı'), findsOneWidget);
      expect(find.textContaining('bakiye 13.000,00 ₺'), findsOneWidget, reason: 'çıkış seçeneğinde güncel bakiye');
      await f4Enter(t, 'finance_fund_transfer_amount', '1.500');
      await f4Enter(t, 'finance_fund_transfer_description', ' Kurul kararı: asansör ');
      await _tap(t, 'finance_fund_transfer_submit');
      final call = auth.f4.fundTransferCalls.single;
      expect(call['from_fund'], 'operating');
      expect(call['to_fund'], 'capital');
      expect(call['amount_minor'], 150000);
      expect(call['transfer_date'], '2026-10-16');
      expect(call['description'], 'Kurul kararı: asansör');
      expect((call['key'] as String).length, lessThanOrEqualTo(64));
      expect(find.text('Aktarım yapıldı: 1.500,00 ₺ (Aidat Hesabı → Fon Hesabı).'), findsOneWidget);
      expect(_sectionChanged, 1);
      expect(_text(t, 'fund_balance_operating'), '11.500,00 ₺');
      expect(_text(t, 'fund_balance_capital'), '4.500,00 ₺');
    });

    testWidgets('doğrulama: kasa seçilmeden / tutarsız gönderilmez', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfer');
      await _tap(t, 'finance_fund_transfer_submit');
      expect(find.text('Para çıkacak kasayı seçin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(auth.f4.fundTransferCalls, isEmpty);
    });

    testWidgets('tutar çıkış kasasının bakiyesini aşarsa uyarı (ENGELLENMEZ, gönderilir)', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfer');
      await f4Tap(t, 'finance_fund_transfer_from_capital');
      await f4Enter(t, 'finance_fund_transfer_amount', '3.000,01');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_fund_transfer_exceeds')), findsOneWidget);
      await _tap(t, 'finance_fund_transfer_submit');
      expect(auth.f4.fundTransferCalls, hasLength(1));
    });

    testWidgets('çift dokunuş tek aktarım yazar', (t) async {
      final auth = _auth();
      auth.f4.fundSummaryGate = null;
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfer');
      await f4Tap(t, 'finance_fund_transfer_from_operating');
      await f4Enter(t, 'finance_fund_transfer_amount', '100');
      final submit = find.byKey(const ValueKey<String>('finance_fund_transfer_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await t.tap(submit, warnIfMissed: false);
      await settleFor(t);
      expect(auth.f4.fundTransferCalls, hasLength(1));
    });

    testWidgets('PERIOD_CLOSED ve IDEMPOTENCY_CONFLICT pencerede Türkçe gösterilir; pencere AÇIK kalır', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfer');
      await f4Tap(t, 'finance_fund_transfer_from_operating');
      await f4Enter(t, 'finance_fund_transfer_amount', '100');
      auth.f4.fundTransferWriteError = f4Coded('PERIOD_CLOSED', 409);
      await _tap(t, 'finance_fund_transfer_submit');
      expect(find.textContaining('kapatılmış'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_fund_transfer_submit')), findsOneWidget);
      auth.f4.fundTransferWriteError = f4Coded('IDEMPOTENCY_CONFLICT', 409);
      await _tap(t, 'finance_fund_transfer_submit');
      expect(find.textContaining('Kasalar Arası Aktarım Listesi'), findsWidgets);
      expect(find.textContaining('daire hesaplarını'), findsNothing, reason: 'genel "daire hesapları" metni yanıltıcı');
      expect(find.byKey(const ValueKey<String>('finance_fund_transfer_submit')), findsOneWidget);
    });

    testWidgets('sonucu belirsiz aktarım (502): kayıt oluşmuş olabilir ipucu; AYNI veriyle yeniden deneme AYNI anahtar, çift kayıt yok', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfer');
      await f4Tap(t, 'finance_fund_transfer_from_operating');
      await f4Enter(t, 'finance_fund_transfer_amount', '100');
      auth.f4.fundTransferWriteError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _tap(t, 'finance_fund_transfer_submit');
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      auth.f4.fundTransferWriteError = null;
      await _tap(t, 'finance_fund_transfer_submit');
      final keys = auth.f4.fundTransferCalls.map((c) => c['key']).toList();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1]);
      expect(auth.f4.fundTransfers, hasLength(1));
    });

    testWidgets('kaydedilmemiş veri koruması: değişiklikten sonra Vazgeç onay sorar', (t) async {
      final auth = _auth();
      await _pumpSection(t, auth);
      await f4ExpectDiscardGuard(
        t,
        open: () => _tap(t, 'finance_funds_transfer'),
        edit: () => f4Enter(t, 'finance_fund_transfer_amount', '10'),
        markerKey: 'finance_fund_transfer_submit',
      );
    });
  });

  group('kasalar arası aktarım listesi', () {
    FinanceFakeAuth seeded() {
      final auth = _auth();
      auth.f4.fundTransfers.addAll(<Map<String, dynamic>>[
        _transferRow(3, reversedBy: 4),
        _transferRow(4, from: 'capital', to: 'operating', reverses: 3, reason: 'Yanlış tutar girildi'),
        _transferRow(5, amount: 50000, description: null),
      ]);
      return auth;
    }

    testWidgets('liste: yön, tutar, durum rozetleri, gerekçe; ters çevrilebilir yalnız asıl + çevrilmemiş aktarım', (t) async {
      final auth = seeded();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfers');
      expect(find.text('Kasalar Arası Aktarım Listesi'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('fund_transfer_3')), findsOneWidget);
      expect(find.text('Ters çevrildi'), findsOneWidget);
      expect(find.text('Ters aktarım'), findsOneWidget);
      expect(find.text('Gerekçe: Yanlış tutar girildi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fund_transfer_reverse_5')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fund_transfer_reverse_3')), findsNothing, reason: 'zaten ters çevrilmiş');
      expect(find.byKey(const ValueKey<String>('fund_transfer_reverse_4')), findsNothing, reason: 'ters aktarım tekrar çevrilmez');
    });

    testWidgets('ters çevirme GEREKÇELİ: boş gerekçe reddedilir; onayda ters aktarım yazılır, liste ve kasa özeti yenilenir', (t) async {
      final auth = seeded();
      await _pumpSection(t, auth);
      // hazır aktarımlar: 3 (İşletme -> Fon 1.500), 4 (Fon -> İşletme 1.500; 3'ün tersi), 5 (İşletme -> Fon 500)
      expect(_text(t, 'fund_balance_operating'), '12.500,00 ₺');
      await _tap(t, 'finance_funds_transfers');
      await _tap(t, 'fund_transfer_reverse_5');
      expect(find.text('Aktarımı Ters Çevir'), findsOneWidget);
      expect(find.textContaining('Asıl kayıt silinmez'), findsOneWidget);
      await _tap(t, 'finance_reason_confirm');
      expect(find.text('Gerekçe girin.'), findsOneWidget);
      expect(auth.f4.fundReverseCalls, isEmpty);
      await f4Enter(t, 'finance_reason_text', 'Kurul kararından vazgeçildi');
      await _tap(t, 'finance_reason_confirm');
      expect(auth.f4.fundReverseCalls.single['id'], 5);
      expect(auth.f4.fundReverseCalls.single['reason'], 'Kurul kararından vazgeçildi');
      expect(find.byKey(const ValueKey<String>('fund_transfer_reverse_5')), findsNothing, reason: 'liste kendiliğinden yenilendi');
      expect(find.text('Ters çevrildi'), findsNWidgets(2));
      expect(_sectionChanged, 1);
      await _tap(t, 'finance_fund_transfers_close');
      expect(_text(t, 'fund_balance_operating'), '13.000,00 ₺', reason: 'ters aktarım 500 TL tutarı İşletme Hesabına geri verdi; kasa özeti yenilendi');
    });

    testWidgets('FUND_TRANSFER_ALREADY_REVERSED pencerede anlaşılır mesajla; kurul ters çevirme düğmesi görmez', (t) async {
      final auth = seeded();
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfers');
      await _tap(t, 'fund_transfer_reverse_5');
      await f4Enter(t, 'finance_reason_text', 'Yanlış');
      auth.f4.fundTransferWriteError = f4Coded('FUND_TRANSFER_ALREADY_REVERSED', 409);
      await _tap(t, 'finance_reason_confirm');
      expect(find.textContaining('zaten ters çevrilmiş'), findsOneWidget);
      expect(find.textContaining('FUND_TRANSFER'), findsNothing);
      // kurul
      await t.pumpWidget(const SizedBox.shrink());
      final board = seeded();
      await _pumpSection(t, board, canWrite: false);
      await _tap(t, 'finance_funds_transfers');
      expect(find.byKey(const ValueKey<String>('fund_transfer_5')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fund_transfer_reverse_5')), findsNothing);
      expect(find.textContaining('Kaydeden:'), findsNothing);
    });

    testWidgets('liste hatası "aktarım yok" demez; Tekrar Dene; boş liste açıklayıcı', (t) async {
      final auth = _auth();
      auth.f4.fundTransferListError = ApiException('x', statusCode: 500);
      await _pumpSection(t, auth);
      await _tap(t, 'finance_funds_transfers');
      expect(find.text('Henüz kasalar arası aktarım yapılmamış.'), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      auth.f4.fundTransferListError = null;
      await f4TapInDialog(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Henüz kasalar arası aktarım yapılmamış.'), findsOneWidget);
    });

    layoutMatrix('aktarım listesi: asıl / ters çevrilmiş / ters aktarım (gerekçeli) satırları', (t, w, h, s, dark) async {
      final auth = seeded();
      auth.f4.fundTransfers.add(_transferRow(6, description: 'Çok uzun bir açıklama: kurul kararı ile asansör yenileme projesi için fon hesabına aktarım yapıldı'));
      await openDialogAt(
        t,
        (context) => FinanceFundTransfersDialog.show(context, scope: _scope(auth)),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('fund_transfer_6')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('fund_transfer_4')));
      expect(find.text('Gerekçe: Yanlış tutar girildi'), findsOneWidget);
    });

    layoutMatrix('ters çevirme penceresi: gerekçe alanı', (t, w, h, s, dark) async {
      final auth = seeded();
      await openDialogAt(
        t,
        (context) => FinanceFundTransfersDialog.show(context, scope: _scope(auth)),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      await _tap(t, 'fund_transfer_reverse_5');
      expect(find.text('Aktarımı Ters Çevir'), findsOneWidget);
      await f4Tap(t, 'finance_reason_confirm');
      expect(find.text('Gerekçe girin.'), findsOneWidget);
    });
  });

  group('kasalar arası aktarım penceresi: taşma matrisi', () {
    layoutMatrix('form: seçili çıkış kasası, bakiye aşımı uyarısı, hata özeti', (t, w, h, s, dark) async {
      final auth = _auth();
      final summary = FundSummary.fromJson(auth.f4.fundSummaryJson());
      await openDialogAt(
        t,
        (context) => FinanceFundTransferDialog.show(context, scope: _scope(auth), summary: summary, now: () => _now),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      expect(find.text('Kasalar Arası Aktarım'), findsWidgets);
      await f4Tap(t, 'finance_fund_transfer_submit'); // boş gönderim: alan hataları
      expect(find.text('Para çıkacak kasayı seçin.'), findsOneWidget);
      await f4Tap(t, 'finance_fund_transfer_from_capital');
      await f4Enter(t, 'finance_fund_transfer_amount', '99.999,99');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_fund_transfer_exceeds')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_fund_transfer_description')));
    });
  });

  group('tahsilat formu: İşletme / Fon hesabı (K3)', () {
    Future<_Out> open(WidgetTester t, FinanceFakeAuth auth, {LedgerEntry? correcting, double width = 420, double height = 2600, double scale = 1.0, bool dark = false}) async {
      final out = _Out();
      await openDialogAt(
        t,
        (context) async {
          out.result = await FinancePaymentDialog.show(
            context,
            scope: _scope(auth),
            apartmentId: correcting == null ? 301 : 302,
            apartmentLabel: correcting == null ? 'A Blok - 5' : 'A Blok - 6',
            correcting: correcting,
            now: () => _now,
          );
        },
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      return out;
    }

    Future<void> pay(WidgetTester t, String amount) async {
      await f4Enter(t, 'finance_payment_amount', amount);
      await f4Tap(t, 'finance_method_cash');
      await _tap(t, 'finance_payment_submit');
    }

    testWidgets('K3 açık borç yok: seçim zorunlu değil, "Hesap seçmeden (genel avans)" seçili; gövdede fund YOK; kayıttan sonra dağılım gösterilir', (t) async {
      final auth = _auth(accounts: false);
      auth.paymentFundSplit = <String, dynamic>{'operating_minor': 150000, 'capital_minor': 50000, 'advance_minor': 0};
      final out = await open(t, auth);
      expect(find.text('İşletme / Fon hesabı'), findsOneWidget);
      expect(find.text('Kasa'), findsNothing, reason: 'K9: kasa sözcüğü kullanılmaz');
      expect(auth.f4.fundChoiceCalls.single['apartment_id'], 301, reason: 'durum sunucudan okunur');
      expect(_fundSelected(t, 'finance_payment_fund_auto'), isTrue);
      expect(find.textContaining('Hesap seçmeden (genel avans)'), findsOneWidget);
      expect(find.textContaining('İşletme Projesi (Aidat) Hesabı — açık borç yok'), findsOneWidget);
      expect(find.textContaining('Açık borç yok. Hesap seçmezseniz tutar genel avans olarak kalır'), findsOneWidget);
      await pay(t, '2.000');
      expect(auth.paymentCalls.single.containsKey('fund'), isFalse);
      expect(out.result!.message, contains('Tahsilat kaydedildi: 2.000,00 ₺.'));
      expect(out.result!.message, contains('Dağıtım: Aidat Hesabı 1.500,00 ₺, Fon Hesabı 500,00 ₺, avans 0,00 ₺.'));
    });

    testWidgets('K3 TEK tür borç: önerilen hesap SEÇİLİ gelir ("Otomatik" yok); gövdede o hesap gider', (t) async {
      final auth = _auth(accounts: false);
      auth.f4.fundChoiceBodies[301] = FakeFinance4bApi.fundChoiceBody(operating: 50000);
      await open(t, auth);
      expect(_fundSelected(t, 'finance_payment_fund_operating'), isTrue);
      expect(_fundSelected(t, 'finance_payment_fund_capital'), isFalse);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing, reason: 'yazılım kendiliğinden atamaz: "Otomatik" yok');
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_required')), findsNothing);
      expect(find.textContaining('Açık borç yalnız Aidat Hesabı için; bu hesap seçili geldi'), findsOneWidget);
      expect(find.textContaining('İşletme Projesi (Aidat) Hesabı — açık borç 500,00 ₺'), findsOneWidget);
      await pay(t, '500');
      expect(auth.paymentCalls.single['fund'], 'operating');
    });

    testWidgets('K3 tek tür borç: yönetici seçili öneriyi DEĞİŞTİREBİLİR (Fon Hesabı seçilirse gövdede capital)', (t) async {
      final auth = _auth(accounts: false);
      auth.f4.fundChoiceBodies[301] = FakeFinance4bApi.fundChoiceBody(capital: 80000);
      await open(t, auth);
      expect(_fundSelected(t, 'finance_payment_fund_capital'), isTrue);
      await f4Tap(t, 'finance_payment_fund_operating');
      expect(_fundSelected(t, 'finance_payment_fund_operating'), isTrue);
      expect(_fundSelected(t, 'finance_payment_fund_capital'), isFalse);
      await pay(t, '300');
      expect(auth.paymentCalls.single['fund'], 'operating');
    });

    testWidgets('K3 İKİ tür borç: seçim ZORUNLU — önceden seçili değil, "Otomatik" yok; seçilmeden kayıt GÖNDERİLMEZ; seçilince fund gider', (t) async {
      final auth = _auth(accounts: false);
      auth.f4.fundChoiceBodies[301] = FakeFinance4bApi.fundChoiceBody(
        operating: 100000,
        capital: 300000,
        proposal: <String, dynamic>{'operating_minor': 100000, 'capital_minor': 100000, 'advance_minor': 0},
      );
      await open(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_required')), findsOneWidget);
      expect(find.textContaining('hem Aidat Hesabı (1.000,00 ₺) hem Fon Hesabı (3.000,00 ₺) için açık borç var'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing, reason: 'iki türde "Otomatik" sunulmaz');
      expect(_fundSelected(t, 'finance_payment_fund_operating'), isFalse);
      expect(_fundSelected(t, 'finance_payment_fund_capital'), isFalse);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_proposal')), findsOneWidget, reason: 'otomatik dağıtım önerisi yalnız bilgi');
      expect(find.textContaining('Aidat Hesabı 1.000,00 ₺, Fon Hesabı 1.000,00 ₺, avans 0,00 ₺ olurdu'), findsOneWidget);
      await pay(t, '2.000');
      expect(auth.paymentCalls, isEmpty, reason: 'seçim yokken sunucuya HİÇ gitmez');
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsWidgets);
      await f4Tap(t, 'finance_payment_fund_capital');
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsNothing, reason: 'seçilince hata kalkar');
      await _tap(t, 'finance_payment_submit');
      expect(auth.paymentCalls.single['fund'], 'capital');
    });

    testWidgets('K3 bayat bilgi: form borçsuz sanırken sunucu iki tür görürse 400 FUND_CHOICE_REQUIRED => panel ZORUNLU kipe geçer, kayıt yazılmaz; seçilince yazılır', (t) async {
      final auth = _auth();
      auth.f4.serverFundChoice[301] = FakeFinance4bApi.fundChoiceBody(operating: 100000, capital: 300000); // GET borçsuz der, kayıt anında iki tür
      await open(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_required')), findsNothing);
      await f4Tap(t, 'finance_payment_account_1');
      await pay(t, '1.000');
      expect(auth.f4.paymentCalls, hasLength(1), reason: 'gönderildi ve sunucu reddetti');
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_required')), findsOneWidget, reason: 'sunucunun yetkili durumu panele işlendi');
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing);
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsWidgets);
      await f4Tap(t, 'finance_payment_fund_operating');
      await _tap(t, 'finance_payment_submit');
      expect(auth.f4.paymentCalls, hasLength(2));
      expect(auth.f4.paymentCalls.last['fund'], 'operating');
    });

    testWidgets('K3 bilgi alınamazsa uyarı + Tekrar Dene gösterilir ve kayıt ENGELLENMEZ (sunucu gerekirse seçim ister)', (t) async {
      final auth = _auth(accounts: false);
      auth.f4.fundChoiceError = f4Coded('SERVER_DOWN', 500);
      final out = await open(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_failed')), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsWidgets);
      await pay(t, '300');
      expect(auth.paymentCalls, hasLength(1), reason: 'bilgi yokken de kayıt denenebilir');
      expect(out.result, isNotNull);
    });

    testWidgets('Fon Hesabı seçilirse gövdede fund=capital; farklı kasa = farklı işlem anahtarı', (t) async {
      final auth = _auth(accounts: false);
      auth.paymentFundSplit = <String, dynamic>{'operating_minor': 0, 'capital_minor': 100000, 'advance_minor': 0};
      await open(t, auth);
      await f4Tap(t, 'finance_payment_fund_capital');
      expect(_fundSelected(t, 'finance_payment_fund_capital'), isTrue);
      expect(_fundSelected(t, 'finance_payment_fund_auto'), isFalse);
      await pay(t, '1.000');
      expect(auth.paymentCalls.single['fund'], 'capital');
    });

    testWidgets('kasa/banka hesabı seçili yolda da (4b) fund gider', (t) async {
      final auth = _auth();
      await open(t, auth);
      await f4Tap(t, 'finance_payment_fund_operating');
      await f4Tap(t, 'finance_payment_account_1');
      await pay(t, '500');
      expect(auth.f4.paymentCalls.single['fund'], 'operating');
      expect(auth.f4.paymentCalls.single['account_id'], 1);
    });

    testWidgets('sunucu fund_split göndermezse (eski sunucu) ileti dağılım satırı eklemez', (t) async {
      final auth = _auth(accounts: false);
      final out = await open(t, auth);
      await pay(t, '300');
      expect(out.result!.message, isNot(contains('Dağıtım')));
    });

    testWidgets('düzeltme: kısıtsız asılda Otomatik başlar, fund yalnız seçilirse gider; kısıtlı asılda Otomatik sunulmaz ve değişmezse fund gitmez', (t) async {
      // kısıtsız asıl
      var auth = _auth(accounts: false);
      var entry = LedgerEntry.fromJson(<String, dynamic>{...auth.ledger.firstWhere((e) => e['id'] == 4), 'reversed_by_entry_id': null});
      await open(t, auth, correcting: entry);
      expect(_fundSelected(t, 'finance_payment_fund_auto'), isTrue);
      await f4Tap(t, 'finance_payment_fund_capital');
      await _tap(t, 'finance_payment_submit');
      expect(auth.correctCalls.single['fund'], 'capital');
      // kısıtlı asıl (Aidat Hesabı)
      await t.pumpWidget(const SizedBox.shrink());
      auth = _auth(accounts: false);
      auth.ledger.firstWhere((e) => e['id'] == 4)['fund'] = 'operating';
      entry = LedgerEntry.fromJson(<String, dynamic>{...auth.ledger.firstWhere((e) => e['id'] == 4), 'reversed_by_entry_id': null});
      expect(entry.fund, FinanceFund.operating);
      await open(t, auth, correcting: entry);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing, reason: 'sunucu asıl kısıtı kaldıramaz');
      expect(_fundSelected(t, 'finance_payment_fund_operating'), isTrue);
      expect(find.textContaining('aynı kısıt korunur'), findsOneWidget);
      await _tap(t, 'finance_payment_submit');
      expect(auth.correctCalls.single.containsKey('fund'), isFalse, reason: 'değişmediyse sunucu asıl kısıtı korur');
    });

    testWidgets('K3 düzeltme: durum okunmaz (asıl kayıt hâlâ defterde); sunucu iki tür görüp 400 verirse panel zorunlu kipe geçer, seçilince düzeltme yazılır', (t) async {
      final auth = _auth();
      auth.f4.correctionFundChoice = FakeFinance4bApi.fundChoiceBody(operating: 100000, capital: 300000);
      final entry = LedgerEntry.fromJson(<String, dynamic>{...auth.ledger.firstWhere((e) => e['id'] == 4), 'reversed_by_entry_id': null});
      await open(t, auth, correcting: entry);
      expect(auth.f4.fundChoiceCalls, isEmpty, reason: 'düzeltmede sunucu durumu okunmaz');
      expect(_fundSelected(t, 'finance_payment_fund_auto'), isTrue);
      await f4Tap(t, 'finance_payment_account_1');
      await _tap(t, 'finance_payment_submit');
      expect(auth.f4.correctPaymentCalls, hasLength(1), reason: 'gönderildi ve sunucu reddetti');
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_required')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing);
      await f4Tap(t, 'finance_payment_fund_capital');
      await _tap(t, 'finance_payment_submit');
      expect(auth.f4.correctPaymentCalls, hasLength(2));
      expect(auth.f4.correctPaymentCalls.last['fund'], 'capital');
    });

    layoutMatrix('Tahsilat Ekle: borçsuz hesap (seçim isteğe bağlı: üç seçenek)', (t, w, h, s, dark) async {
      final auth = _auth(accounts: false);
      await open(t, auth, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_payment_fund_capital')));
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_operating')), findsOneWidget);
    });

    layoutMatrix('Tahsilat Ekle: İKİ tür borç (zorunlu seçim, uyarı, öneri, hata) taşmaz', (t, w, h, s, dark) async {
      final auth = _auth(accounts: false);
      auth.f4.fundChoiceBodies[301] = FakeFinance4bApi.fundChoiceBody(
        operating: 123456789,
        capital: 987654321,
        proposal: <String, dynamic>{'operating_minor': 123456789, 'capital_minor': 500, 'advance_minor': 0},
      );
      await open(t, auth, width: w, height: h, scale: s, dark: dark);
      await pay(t, '1.000'); // seçimsiz gönderim: alan hatası
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_payment_fund_capital')));
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_required')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_proposal')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing);
      expect(auth.paymentCalls, isEmpty);
    });

    layoutMatrix('Tahsilat Ekle: TEK tür borç (öneri seçili) taşmaz', (t, w, h, s, dark) async {
      final auth = _auth(accounts: false);
      auth.f4.fundChoiceBodies[301] = FakeFinance4bApi.fundChoiceBody(capital: 99999999);
      await open(t, auth, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_payment_fund_capital')));
      expect(_fundSelected(t, 'finance_payment_fund_capital'), isTrue);
    });

    layoutMatrix('Tahsilatı Düzelt: kısıtlı asıl (Otomatik yok) ve uzun açıklamalar', (t, w, h, s, dark) async {
      final auth = _auth(accounts: false);
      auth.ledger.firstWhere((e) => e['id'] == 4)['fund'] = 'capital';
      final entry = LedgerEntry.fromJson(<String, dynamic>{...auth.ledger.firstWhere((e) => e['id'] == 4), 'reversed_by_entry_id': null});
      await open(t, auth, correcting: entry, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_payment_fund_capital')));
      expect(find.byKey(const ValueKey<String>('finance_payment_fund_auto')), findsNothing);
    });
  });

  group('gider formu ve kategori yönetimi: Kasa', () {
    FinanceFakeAuth withCapitalCategory() {
      final auth = _auth();
      auth.f4.categories.add(<String, dynamic>{'id': 4, 'name': 'Yatırım ve demirbaş', 'is_system': true, 'is_active': true, 'sort_order': 4, 'fund': 'capital'});
      return auth;
    }

    Future<void> openExpense(WidgetTester t, FinanceFakeAuth auth, {Expense? correcting, double width = 420, double height = 3000, double scale = 1.0, bool dark = false}) async {
      await openDialogAt(
        t,
        (context) => FinanceExpenseDialog.show(context, scope: _scope(auth), correcting: correcting, now: () => _now),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      await settleFor(t);
    }

    Future<void> pickCategory(WidgetTester t, String name) async {
      await f4Tap(t, 'finance_expense_category_0');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text(name).last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
    }

    testWidgets('kasa kategoriden öndoldurulur (Fon kategorisi => Fon Hesabı); gövdede fund HER ZAMAN gider', (t) async {
      final auth = withCapitalCategory();
      await openExpense(t, auth);
      expect(_fundSelected(t, 'finance_expense_fund_operating'), isTrue, reason: 'kategori seçilmeden varsayılan');
      await pickCategory(t, 'Yatırım ve demirbaş');
      expect(_fundSelected(t, 'finance_expense_fund_capital'), isTrue);
      await f4Enter(t, 'finance_expense_description', 'Yeni jeneratör');
      await f4Enter(t, 'finance_expense_amount', '40.000');
      await f4Tap(t, 'finance_expense_account_1');
      await _tap(t, 'finance_expense_submit');
      expect(auth.f4.expenseCalls.single['fund'], 'capital');
      expect(auth.f4.expenses.single['fund'], 'capital');
    });

    testWidgets('kullanıcı kasaya dokunduysa kategori değişimi onu bozmaz; bu gider için kategorinin kasası aşılabilir', (t) async {
      final auth = withCapitalCategory();
      await openExpense(t, auth);
      await f4Tap(t, 'finance_expense_fund_capital');
      await pickCategory(t, 'Elektrik');
      expect(_fundSelected(t, 'finance_expense_fund_capital'), isTrue, reason: 'dokunulan kasa korunur');
      await f4Enter(t, 'finance_expense_description', 'Ortak alan aydınlatma yatırımı');
      await f4Enter(t, 'finance_expense_amount', '1.000');
      await f4Tap(t, 'finance_expense_account_1');
      await _tap(t, 'finance_expense_submit');
      expect(auth.f4.expenseCalls.single['fund'], 'capital');
      expect(auth.f4.expenseCalls.single['category_id'], 1);
    });

    testWidgets('düzeltme: asıl giderin kasasıyla başlar ve yeni gider kendi fund değerini taşır', (t) async {
      final auth = withCapitalCategory();
      auth.f4.expenses.add(<String, dynamic>{
        'id': 9,
        'category_id': 4,
        'category_name': 'Yatırım ve demirbaş',
        'supplier_id': null,
        'supplier_name': null,
        'description': 'Jeneratör',
        'amount_minor': 4000000,
        'vat_minor': null,
        'expense_date': '2026-10-05',
        'account_id': 1,
        'document_kind': 'none',
        'document_no': null,
        'doc_norm': '',
        'voided': null,
        'corrects_expense_id': null,
        'fund': 'capital',
      });
      final expense = Expense.fromJson(<String, dynamic>{...auth.f4.expenses.single, 'account': <String, dynamic>{'id': 1, 'name': 'Nakit Kasa'}});
      expect(expense.fund, FinanceFund.capital);
      await openExpense(t, auth, correcting: expense);
      expect(_fundSelected(t, 'finance_expense_fund_capital'), isTrue);
      await f4Enter(t, 'finance_expense_amount', '39.000');
      await _tap(t, 'finance_expense_submit');
      expect(auth.f4.expenseCalls.single['op'], 'correct');
      expect(auth.f4.expenseCalls.single['fund'], 'capital');
    });

    layoutMatrix('Gider Ekle: Kasa seçimi + Fon kategorisi öndoldurma', (t, w, h, s, dark) async {
      final auth = withCapitalCategory();
      await openExpense(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4Tap(t, 'finance_expense_category_0');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Yatırım ve demirbaş').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_expense_fund_operating')));
      expect(_fundSelected(t, 'finance_expense_fund_capital'), isTrue);
      expect(find.textContaining('Kasa seçtiğiniz kategoriden öndoldurulur'), findsOneWidget);
    });

    testWidgets('kategori listesi kasa rozetiyle; ekleme formunda Kasa seçimi (varsayılan Aidat Hesabı) gövdeye girer', (t) async {
      final auth = withCapitalCategory();
      await openDialogAt(t, (context) => FinanceCatalogDialog.show(context, scope: _scope(auth)), width: 420, height: 3000, scale: 1.0, dark: false);
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Aidat Hesabı'), findsWidgets);
      expect(find.text('Fon Hesabı'), findsOneWidget, reason: 'yalnız Fon kategorisinde');
      expect(_fundSelected(t, 'finance_category_new_fund_operating'), isTrue);
      await f4Enter(t, 'finance_category_name', 'Çatı onarımı');
      await f4Tap(t, 'finance_category_new_fund_capital');
      await _tap(t, 'finance_category_add');
      expect(auth.f4.writes.last['op'], 'createExpenseCategory');
      expect(auth.f4.writes.last['fund'], 'capital');
      expect(auth.f4.categories.last['fund'], 'capital');
      expect(_fundSelected(t, 'finance_category_new_fund_operating'), isTrue, reason: 'eklemeden sonra form varsayılana döner');
    });

    testWidgets('kategori düzenleme: kasa değişir; hazır kategoride kilitli; kullanılmış kategori CATEGORY_FUND_LOCKED anlaşılır mesajla', (t) async {
      final auth = withCapitalCategory();
      auth.f4.expenses.add(<String, dynamic>{'id': 1, 'category_id': 2, 'category_name': 'Asansör bakım', 'amount_minor': 100, 'expense_date': '2026-10-01', 'account_id': 1, 'description': 'x', 'voided': null});
      auth.f4.categories.add(<String, dynamic>{'id': 5, 'name': 'Boya', 'is_system': false, 'is_active': true, 'sort_order': 5, 'fund': 'operating'});
      await openDialogAt(t, (context) => FinanceCatalogDialog.show(context, scope: _scope(auth)), width: 420, height: 3400, scale: 1.0, dark: false);
      await settleFor(t);
      await settleFor(t);
      // serbest kategori: Fon'a alınır
      await _tap(t, 'finance_category_edit_5');
      expect(_fundSelected(t, 'finance_category_edit_fund_operating'), isTrue);
      await f4Tap(t, 'finance_category_edit_fund_capital');
      await _tap(t, 'finance_category_save');
      expect(auth.f4.writes.last['fund'], 'capital');
      expect(auth.f4.categories.firstWhere((c) => c['id'] == 5)['fund'], 'capital');
      // hazır kategori: seçim kilitli, metin açıklar, fund gönderilmez
      await _tap(t, 'finance_category_edit_4');
      expect(find.text('Hazır kategorinin kasası değiştirilemez.'), findsOneWidget);
      await f4Tap(t, 'finance_category_edit_fund_operating');
      expect(_fundSelected(t, 'finance_category_edit_fund_capital'), isTrue, reason: 'kilitli: dokunuş etkisiz');
      await f4TapInDialog(t, 'Vazgeç');
      // eski gideri olan kategori: sunucu 409 CATEGORY_FUND_LOCKED
      await _tap(t, 'finance_category_edit_2');
      await f4Tap(t, 'finance_category_edit_fund_capital');
      await _tap(t, 'finance_category_save');
      expect(find.textContaining('kasası değiştirilemez'), findsWidgets);
      expect(find.textContaining('CATEGORY_FUND_LOCKED'), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_category_save')), findsOneWidget, reason: 'pencere açık kalır');
    });

    layoutMatrix('Kategori düzenle: hazır kategori (Kasa kilitli) ve kasa seçimi', (t, w, h, s, dark) async {
      final auth = withCapitalCategory();
      await openDialogAt(t, (context) => FinanceCatalogDialog.show(context, scope: _scope(auth)), width: w, height: h, scale: s, dark: dark);
      await settleFor(t);
      await settleFor(t);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_category_new_fund_capital')));
      await f4Tap(t, 'finance_category_edit_4');
      expect(find.text('Hazır kategorinin kasası değiştirilemez.'), findsOneWidget);
    });
  });

  group('tanım ve ek borç: kasa etiketi', () {
    layoutMatrix('tanım kartı: "Kasa: ..." satırı (Fon ve eski sunucu türetmesi)', (t, w, h, s, dark) async {
      final withFund = FeeDefinition.fromJson(finDefinition(1, name: 'Asansör yenileme katkı payı', kind: 'one_time', fund: 'capital'));
      final old = FeeDefinition.fromJson(finDefinition(2));
      await pumpList(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FeeDefinitionCard(definition: withFund, onEdit: () {}, onPost: () {}),
            const SizedBox(height: 12),
            FeeDefinitionCard(definition: old, onEdit: () {}, onPost: () {}),
          ],
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Kasa: Yatırım ve Demirbaş (Fon) Hesabı'), findsOneWidget);
      expect(find.text('Kasa: İşletme Projesi (Aidat) Hesabı'), findsOneWidget, reason: 'eski sunucu: aylık aidat => Aidat Hesabı');
      expect(find.byKey(const ValueKey<String>('fee_definition_fund_1')), findsOneWidget);
    });
  });

  group('daire ekstresi: kasa bazında durum', () {
    Future<void> openAccount(WidgetTester t, FinanceFakeAuth auth, {double width = 420, double height = 3200, double scale = 1.0, bool dark = false}) async {
      await openDialogAt(
        t,
        (context) => FinanceAccountDialog.show(context, scope: _scope(auth), apartmentId: 301, initialLabel: 'A Blok - 5', now: () => _now),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      await settleFor(t);
    }

    FinanceFakeAuth withFunds() {
      final auth = _auth(accounts: false);
      auth.accountFundsJson = finFundsJson(operating: 150000, operatingOverdue: 50000, capital: 0, capitalAdvance: 20000);
      auth.accountAdvanceMinor = 20000;
      auth.ledger.firstWhere((e) => e['id'] == 1)['fund'] = 'capital';
      auth.ledger.add(finEntry(6, 301, kind: 'payment', amount: -200000, entryDate: '2026-10-10', method: 'cash', fund: 'operating'));
      auth.ledger.add(finEntry(7, 301, kind: 'payment', amount: -100000, entryDate: '2026-10-11', method: 'transfer'));
      auth.fundSplitOfEntries[6] = <String, dynamic>{'operating_minor': 150000, 'capital_minor': 50000, 'advance_minor': 0};
      return auth;
    }

    testWidgets('başlıkta iki kasa (açık borç / vadesi geçen / avans) ve toplam avans; satırlarda kasa rozeti ve dağılım', (t) async {
      await openAccount(t, withFunds());
      expect(find.byKey(const ValueKey<String>('finance_account_funds')), findsOneWidget);
      expect(find.text('İşletme Projesi (Aidat) Hesabı'), findsOneWidget);
      expect(find.text('Yatırım ve Demirbaş (Fon) Hesabı'), findsOneWidget);
      expect(_text(t, 'finance_account_funds_operating_balance'), 'Açık borç: 1.500,00 ₺');
      expect(_text(t, 'finance_account_funds_operating_overdue'), 'Vadesi geçen: 500,00 ₺');
      expect(_text(t, 'finance_account_funds_capital_balance'), 'Borç yok', reason: 'yönetici ekstresi sıfır kasayı da yazar');
      expect(_text(t, 'finance_account_funds_capital_advance'), 'Avans: 200,00 ₺');
      expect(_text(t, 'finance_account_funds_advance'), 'Toplam avans: 200,00 ₺');
      // satırlar
      expect(find.text('Fon Hesabı'), findsOneWidget, reason: 'borç satırı: kasa rozeti (kısa ad)');
      expect(find.text('Yalnız Aidat Hesabı'), findsOneWidget, reason: 'kısıtlı tahsilat');
      expect(_text(t, 'ledger_fund_split_6'), 'Dağıtım: Aidat Hesabı 1.500,00 ₺, Fon Hesabı 500,00 ₺, avans 0,00 ₺');
      expect(find.byKey(const ValueKey<String>('ledger_fund_split_7')), findsNothing, reason: 'dağılım yalnız sunucu verdiyse');
    });

    testWidgets('eski sunucu (funds yok): kırılım çizilmez, ekstre eski görünümde', (t) async {
      await openAccount(t, _auth(accounts: false));
      expect(find.byKey(const ValueKey<String>('finance_account_funds')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_account_header')), findsOneWidget);
    });

    layoutMatrix('ekstre: kasa kırılımı + kısıtlı tahsilat + dağılım satırı', (t, w, h, s, dark) async {
      await openAccount(t, withFunds(), width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_account_funds')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('ledger_fund_split_6')));
    });
  });

  group('sakin Borcum: kasa kırılımı', () {
    Future<void> pump(WidgetTester t, FinanceFakeAuth auth, {double width = 420, double height = 3200, double scale = 1.0, bool dark = false}) async {
      await pumpList(t, MyFinanceView(authService: auth), width: width, height: height, scale: scale, dark: dark);
      await settleFor(t, 100);
      await settleFor(t, 100);
    }

    testWidgets('kiracı yalnız Aidat Hesabı\'nı görür (Fon sıfır, gösterilmez)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(account: 'tenant', funds: finFundsJson(operating: 100000, operatingOverdue: 50000), advance: 0),
        ];
      await pump(t, auth);
      expect(find.byKey(const ValueKey<String>('my_finance_funds')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_funds_operating')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_funds_capital')), findsNothing);
      expect(find.text('İşletme Projesi (Aidat) Hesabı'), findsOneWidget);
      expect(find.text('Yatırım ve Demirbaş (Fon) Hesabı'), findsNothing);
      expect(_text(t, 'my_finance_funds_operating_balance'), 'Açık borç: 1.000,00 ₺');
      expect(_text(t, 'my_finance_funds_operating_overdue'), 'Vadesi geçen: 500,00 ₺');
    });

    testWidgets('kiracılı dairede malik yalnız Fon Hesabı\'nı görür; avans yazılır', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(account: 'owner', funds: finFundsJson(capital: 300000, capitalOverdue: 300000, capitalAdvance: 5000), advance: 5000),
        ];
      await pump(t, auth);
      expect(find.byKey(const ValueKey<String>('my_finance_funds_capital')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_funds_operating')), findsNothing);
      expect(_text(t, 'my_finance_funds_capital_advance'), 'Avans: 50,00 ₺');
      expect(_text(t, 'my_finance_funds_advance'), 'Toplam avans: 50,00 ₺');
    });

    testWidgets('iki kasa da sıfırsa ve avans yoksa kırılım hiç çizilmez; eski sunucuda da yok', (t) async {
      final zero = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem(balance: 0, overdue: 0, funds: finFundsJson(), advance: 0)];
      await pump(t, zero);
      expect(find.byKey(const ValueKey<String>('my_finance_funds')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      final old = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await pump(t, old);
      expect(find.byKey(const ValueKey<String>('my_finance_funds')), findsNothing);
      expect(find.byType(MyFinanceCard), findsOneWidget);
    });

    testWidgets('salt okunur kiracı hesabı kendi kasa kırılımını taşır; kendi hesabına karışmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(
            account: 'owner',
            balance: 0,
            overdue: 0,
            funds: finFundsJson(),
            accounts: <Map<String, dynamic>>[
              finMyAccount(party: 'owner', funds: finFundsJson()),
              finMyAccount(party: 'tenant', role: 'read_only', balance: 70000, overdue: 70000, funds: finFundsJson(operating: 70000, operatingOverdue: 70000)),
            ],
          ),
        ];
      await pump(t, auth);
      expect(find.byKey(const ValueKey<String>('my_finance_funds')), findsNothing, reason: 'kendi hesabı sıfır');
      expect(find.byKey(const ValueKey<String>('my_finance_ro_tenant_funds')), findsOneWidget);
      expect(_text(t, 'my_finance_ro_tenant_funds_operating_balance'), 'Açık borç: 700,00 ₺');
    });

    layoutMatrix('Borcum: kasa kırılımı (kendi hesabı + salt okunur hesap)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(
            account: 'owner',
            funds: finFundsJson(operating: 100000, operatingOverdue: 50000, operatingAdvance: 1000, capital: 250000, capitalOverdue: 250000),
            advance: 3000,
            accounts: <Map<String, dynamic>>[
              finMyAccount(party: 'owner', balance: 100000, funds: finFundsJson(operating: 100000, capital: 250000)),
              finMyAccount(party: 'tenant', role: 'read_only', balance: 70000, funds: finFundsJson(operating: 70000, operatingOverdue: 70000), advance: 500),
            ],
          ),
        ];
      await pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('my_finance_funds')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_ro_tenant_funds')), findsOneWidget);
    });
  });

  group('makbuz: kasalara dağılım', () {
    Future<void> openReceipt(WidgetTester t, FinanceFakeAuth auth, {double width = 420, double height = 3000, double scale = 1.0, bool dark = false}) async {
      await openDialogAt(
        t,
        (context) => FinanceReceiptDialog.show(context, scope: _scope(auth), receiptId: 1, initialNumber: 'MK-2026-000001'),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      await settleFor(t);
    }

    FinanceFakeAuth withReceipt({bool split = true}) {
      final auth = _auth(accounts: false);
      final json = f4ReceiptJson(1);
      if (split) {
        (json['snapshot'] as Map<String, dynamic>)['fund_split'] = <String, dynamic>{'operating_minor': 100000, 'capital_minor': 23456, 'advance_minor': 0};
      }
      auth.f4.receipts[1] = json;
      return auth;
    }

    testWidgets('makbuzda verildiği andaki dağılım yazılır; 080 öncesi makbuzda satır yok', (t) async {
      await openReceipt(t, withReceipt());
      expect(_text(t, 'finance_receipt_fund_split'), 'Aidat Hesabı 1.000,00 ₺, Fon Hesabı 234,56 ₺, avans 0,00 ₺');
      expect(find.text('Kasalara dağılım'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await openReceipt(t, withReceipt(split: false));
      expect(find.byKey(const ValueKey<String>('finance_receipt_fund_split')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsOneWidget);
    });

    layoutMatrix('makbuz penceresi: kasalara dağılım satırı', (t, w, h, s, dark) async {
      await openReceipt(t, withReceipt(), width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_receipt_fund_split')));
      expect(find.byKey(const ValueKey<String>('finance_receipt_fund_split')), findsOneWidget);
    });
  });

  group('ekran okuyucu: ham tutar okunuşu yok (R14)', () {
    testWidgets('kasa bölümü, açık döküm, aktarım penceresi ve aktarım listesi tutarları okunuşla verir', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      auth.f4
        ..fundsUnassignedCount = 2
        ..fundsUnassignedTotal = 90000
        ..fundsBalanced = false
        ..fundsDifferenceMinor = 4500
        ..fundMovementRows['operating'] = <Map<String, dynamic>>[_movement(1), _movement(2, type: 'expense', amount: -250000)]
        ..fundTransfers.addAll(<Map<String, dynamic>>[_transferRow(3), _transferRow(4, from: 'capital', to: 'operating', reverses: 3, reason: 'Yanlış')]);
      await _pumpSection(t, auth);
      await _tap(t, 'fund_movements_toggle_operating');
      f4ExpectSpokenMoney(t);
      await _tap(t, 'finance_funds_transfer');
      await f4Tap(t, 'finance_fund_transfer_from_operating');
      await f4Enter(t, 'finance_fund_transfer_amount', '99.999');
      await settleFor(t);
      f4ExpectSpokenMoney(t);
      await f4TapInDialog(t, 'Vazgeç');
      await f4TapInDialog(t, 'Vazgeç ve Kapat');
      await _tap(t, 'finance_funds_transfers');
      f4ExpectSpokenMoney(t);
      handle.dispose();
    });

    testWidgets('ekstre kırılımı, Borcum kırılımı ve makbuz dağılımı tutarları okunuşla verir', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth(accounts: false);
      auth.accountFundsJson = finFundsJson(operating: 150000, operatingOverdue: 50000, capital: 0, capitalAdvance: 20000);
      auth.accountAdvanceMinor = 20000;
      auth.ledger.add(finEntry(6, 301, kind: 'payment', amount: -200000, entryDate: '2026-10-10', method: 'cash', fund: 'operating'));
      auth.fundSplitOfEntries[6] = <String, dynamic>{'operating_minor': 150000, 'capital_minor': 50000, 'advance_minor': 0};
      await openDialogAt(
        t,
        (context) => FinanceAccountDialog.show(context, scope: _scope(auth), apartmentId: 301, initialLabel: 'A Blok - 5', now: () => _now),
        width: 420,
        height: 3200,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await settleFor(t);
      f4ExpectSpokenMoney(t);
      await t.pumpWidget(const SizedBox.shrink());
      auth.myFinanceItems = <Map<String, dynamic>>[
        finMyItem(account: 'owner', funds: finFundsJson(operating: 100000, operatingOverdue: 50000, capital: 250000), advance: 3000),
      ];
      await pumpList(t, MyFinanceView(authService: auth), width: 420, height: 3200, scale: 1.0, dark: false);
      await settleFor(t, 100);
      await settleFor(t, 100);
      f4ExpectSpokenMoney(t);
      handle.dispose();
    });
  });

  group('FundChoice parçası', () {
    testWidgets('seçim dokunuşla değişir; açıklamalar TAM adla; ekran okuyucu etiketi ad + açıklama', (t) async {
      final handle = t.ensureSemantics();
      FinanceFund? picked = FinanceFund.operating;
      await pumpList(
        t,
        StatefulBuilder(
          builder: (context, setState) => FundChoice(selected: picked, onSelected: (v) => setState(() => picked = v)),
        ),
        width: 400,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      expect(find.text('İşletme Projesi (Aidat) Hesabı — dairede oturan öder (kiracı varsa kiracı)'), findsOneWidget);
      expect(find.text('Yatırım ve Demirbaş (Fon) Hesabı — malik öder'), findsOneWidget);
      expect(find.bySemanticsLabel('Yatırım ve Demirbaş (Fon) Hesabı, malik öder'), findsOneWidget);
      expect(_fundSelected(t, 'finance_fund_operating'), isTrue);
      await t.tap(find.byKey(const ValueKey<String>('finance_fund_capital')));
      await t.pump();
      expect(picked, FinanceFund.capital);
      expect(_fundSelected(t, 'finance_fund_capital'), isTrue);
      expect(_fundSelected(t, 'finance_fund_operating'), isFalse);
      handle.dispose();
    });

    testWidgets('devre dışıyken dokunuş etkisiz', (t) async {
      FinanceFund? picked = FinanceFund.operating;
      await pumpList(
        t,
        FundChoice(selected: picked, enabled: false, onSelected: (v) => picked = v),
        width: 400,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      await t.tap(find.byKey(const ValueKey<String>('finance_fund_capital')));
      await t.pump();
      expect(picked, FinanceFund.operating);
    });

    testWidgets('allowAuto: ilk seçenek "Otomatik (en eski vade önce)"; null seçili sayılır', (t) async {
      await pumpList(
        t,
        FundChoice(selected: null, allowAuto: true, onSelected: (_) {}),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(_fundSelected(t, 'finance_fund_auto'), isTrue);
      expect(find.textContaining('Otomatik (en eski vade önce)'), findsOneWidget);
    });
  });
}

class _Out {
  FinancePaymentOutcome? result;
}
