// Platform Faz 4b: sakin "Borcum" ekranının makbuz / ekstre PDF / tazminat açıklaması eylemleri.
//
// Salt okuma: sakin hiçbir şey yazmaz; makbuz basımı "KOPYA" damgalıdır (makbuz testinde); hata görünür kalır ve
// "makbuz yok / açıklama yok" demez; işlem sürerken düğmeler pasiftir; 4a davranışı (authService verilmeyen kart) değişmez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

import 'dialog_layout_harness.dart' show scrollTo, settleFor;
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

final List<FinancePdfRequest> _pdfs = <FinancePdfRequest>[];

Map<String, dynamic> _entry(int id, {int amount = 50000, String? name = 'Aylık aidat', Map<String, dynamic>? extra}) => <String, dynamic>{
  ...finEntry(id, 301, amount: amount, dueDate: '2026-10-25', definitionName: name),
  'description': null,
  'reversal_reason': null,
  'created_by_name': null,
  'reversed_by_entry_id': null,
  ...?extra,
};

FinanceFakeAuth _auth({List<Map<String, dynamic>>? recent}) {
  final auth = FinanceFakeAuth.seeded();
  auth.myFinanceItems = <Map<String, dynamic>>[finMyItem(recent: recent ?? <Map<String, dynamic>>[_entry(2)])];
  auth.f4.receipts[31] = f4ReceiptJson(31, number: 'MK-2026-000031', amount: 80000);
  return auth;
}

Future<void> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  double width = 400,
  double height = 3000,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpList(
    t,
    MyFinanceView(authService: auth, now: () => _now),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  setUp(() {
    _pdfs.clear();
    FinancePdfActions.debugOverride = (request) async => _pdfs.add(request);
  });
  tearDown(() => FinancePdfActions.debugOverride = null);

  group('kart eylemleri', () {
    f4Matrix('Makbuzlarım / Ekstreyi Yazdır / Ekstreyi Paylaş taşmaz', (t, w, h, s, dark) async {
      final auth = _auth(recent: <Map<String, dynamic>>[
        _entry(7, amount: -80000, name: null, extra: <String, dynamic>{'kind': 'payment', 'receipt': <String, dynamic>{'id': 31, 'number': 'MK-2026-000031'}}),
        _entry(8, amount: 12345, name: 'Gecikme tazminatı', extra: <String, dynamic>{'late_fee_run_id': 40}),
      ]);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      for (final key in const ['my_finance_receipts', 'my_finance_statement_print', 'my_finance_statement_share', 'ledger_receipt_7', 'ledger_latefee_explain_8']) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('authService verilmeyen kart (4a görünümü) 4b eylemlerini ÇİZMEZ', (t) async {
      final auth = _auth();
      final item = (await auth.getMyFinance()).items.first;
      await pumpList(t, MyFinanceCard(item: item), width: 400, height: 2000, scale: 1.0, dark: false);
      expect(find.byKey(const ValueKey<String>('my_finance_receipts')), findsNothing);
      expect(find.byKey(const ValueKey<String>('my_finance_statement_print')), findsNothing);
    });

    testWidgets('Makbuzlarım: kendi dairesinin makbuzları (sakin ucu); yönetici düğmeleri YOK', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'my_finance_receipts');
      await settleFor(t);
      expect(auth.f4.callCount('listMyReceipts'), 1);
      expect(auth.f4.callCount('listReceipts'), 0);
      expect(find.byKey(const ValueKey<String>('finance_receipts_verify')), findsNothing, reason: 'doğrulama yönetici / kurul içindir');
    });

    testWidgets('makbuzlu satır: "Makbuz MK-..." sakin ucundan açılır ve düzenle düğmesi yoktur', (t) async {
      final auth = _auth(recent: <Map<String, dynamic>>[
        _entry(7, amount: -80000, name: null, extra: <String, dynamic>{'kind': 'payment', 'receipt': <String, dynamic>{'id': 31, 'number': 'MK-2026-000031'}}),
        _entry(9, amount: -1000, name: null, extra: <String, dynamic>{'kind': 'payment'}),
      ]);
      await _pump(t, auth);
      expect(find.text('Makbuz MK-2026-000031'), findsOneWidget);
      expect(find.text('Makbuz Düzenle'), findsNothing, reason: 'sakin makbuz düzenleyemez');
      await f4Tap(t, 'ledger_receipt_7');
      await settleFor(t);
      expect(auth.f4.callCount('getMyReceipt'), 1);
      expect(auth.f4.callCount('getReceipt'), 0);
    });

    testWidgets('makbuz açılamazsa pencerede hata + Tekrar Dene ("makbuz yok" denmez)', (t) async {
      final auth = _auth(recent: <Map<String, dynamic>>[
        _entry(7, amount: -80000, name: null, extra: <String, dynamic>{'kind': 'payment', 'receipt': <String, dynamic>{'id': 31, 'number': 'MK-2026-000031'}}),
      ]);
      auth.f4.receiptError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      await f4Tap(t, 'ledger_receipt_7');
      await settleFor(t);
      expect(find.text('Tekrar Dene'), findsWidgets);
    });
  });

  group('gecikme tazminatı açıklaması', () {
    Future<FinanceFakeAuth> lateFeeAuth() async => _auth(recent: <Map<String, dynamic>>[
      _entry(8, amount: 10000, name: 'Gecikme tazminatı', extra: <String, dynamic>{'late_fee_run_id': 40}),
      _entry(9),
    ]);

    testWidgets('yalnız tazminat satırında "Nasıl hesaplandı?" vardır; döküm sunucu değerlerinden', (t) async {
      final auth = await lateFeeAuth();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('ledger_latefee_explain_8')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger_latefee_explain_9')), findsNothing);
      expect(find.text('Gecikme tazminatı'), findsWidgets);
      await f4Tap(t, 'ledger_latefee_explain_8');
      await settleFor(t);
      expect(auth.f4.myLateFeeCalls, <int>[8]);
      expect(find.byKey(const ValueKey<String>('finance_latefee_explain_amount')), findsOneWidget);
      expect(find.text('100,00 ₺'), findsWidgets);
      expect(find.text('Oran: %5,00 aylık.'), findsOneWidget);
      expect(find.text('Gün esası: Aylık oran ÷ 30 gün.'), findsOneWidget);
      expect(find.text('Vadeye ek gün: 0.'), findsOneWidget);
      expect(find.textContaining('gün toplamı: 12.000,00 ₺ (tutar x gün)'), findsOneWidget);
      expect(find.text('01.09.2026 - 10.09.2026: gecikmiş 500,00 ₺'), findsOneWidget);
      expect(find.text('11.09.2026 - 30.09.2026: gecikmiş 1.000,00 ₺'), findsOneWidget);
      expect(find.textContaining('faiz'), findsNothing, reason: 'uydurma hukuki iddia yok');
    });

    testWidgets('açıklama yüklenemezse hata + Tekrar Dene; tekrar deneyince açılır', (t) async {
      final auth = await lateFeeAuth();
      auth.f4.myLateFeeError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      await f4Tap(t, 'ledger_latefee_explain_8');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_explain_error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_explain_amount')), findsNothing);
      auth.f4.myLateFeeError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_explain_amount')), findsOneWidget);
    });

    f4Matrix('açıklama penceresi taşmaz', (t, w, h, s, dark) async {
      final auth = await lateFeeAuth();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4Tap(t, 'ledger_latefee_explain_8');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_explain_panel')), findsOneWidget);
    });

    testWidgets('ekran okuyucu: tutar "yüz lira" diye okunur', (t) async {
      final handle = t.ensureSemantics();
      final auth = await lateFeeAuth();
      await _pump(t, auth);
      await f4Tap(t, 'ledger_latefee_explain_8');
      await settleFor(t);
      expect(find.bySemanticsLabel(RegExp('Bu ay için gecikme tazminatı: yüz lira')), findsOneWidget);
      handle.dispose();
    });
  });

  group('ekstre PDF', () {
    testWidgets('Yazdır: yılbaşından bugüne ekstre çekilir, PDF yazdırma yoluna gider', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'my_finance_statement_print');
      await settleFor(t);
      final call = auth.f4.myStatementCalls.single;
      expect(call['apartment_id'], 301);
      expect(call['from'], '2026-01-01');
      expect(call['to'], '2026-10-16');
      expect(_pdfs.single.kind, 'statement');
      expect(_pdfs.single.share, isFalse);
    });

    testWidgets('Paylaş: paylaşım yoluna gider', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'my_finance_statement_share');
      await settleFor(t);
      expect(_pdfs.single.share, isTrue);
    });

    testWidgets('sürerken düğmeler pasif (çift dokunuş yok); bitince açılır', (t) async {
      final auth = _auth();
      auth.f4.myStatementGate = Completer<void>();
      await _pump(t, auth);
      await f4Tap(t, 'my_finance_statement_print');
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('my_finance_statement_share'))).onPressed, isNull);
      await t.tap(find.byKey(const ValueKey<String>('my_finance_statement_print')), warnIfMissed: false);
      auth.f4.myStatementGate!.complete();
      await settleFor(t);
      expect(auth.f4.myStatementCalls, hasLength(1));
      expect(_pdfs, hasLength(1));
    });

    testWidgets('hata: Türkçe ileti kartta kalır, PDF üretilmez; yeniden denenebilir', (t) async {
      final auth = _auth();
      auth.f4.myStatementError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await _pump(t, auth);
      await f4Tap(t, 'my_finance_statement_print');
      await settleFor(t);
      expect(find.text('Ekstre hazırlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(_pdfs, isEmpty);
      auth.f4.myStatementError = null;
      await f4Tap(t, 'my_finance_statement_print');
      await settleFor(t);
      expect(_pdfs, hasLength(1));
      expect(find.byKey(const ValueKey<String>('my_finance_action_error')), findsNothing);
    });

    testWidgets('PDF üretimi hata verirse ileti görünür (sessiz kapanmaz)', (t) async {
      final auth = _auth();
      FinancePdfActions.debugOverride = (_) async => throw StateError('pdf');
      await _pump(t, auth);
      await f4Tap(t, 'my_finance_statement_print');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('my_finance_action_error')), findsOneWidget);
    });
  });

  testWidgets('4a ekranındaki satırlar değişmedi: ekstre kartı + hareket listesi', (t) async {
    final auth = _auth();
    await _pump(t, auth);
    expect(find.byType(MyFinanceCard), findsOneWidget);
    expect(find.byType(LedgerEntryTile), findsOneWidget);
    expect(find.text('Online ödeme yakında. Ödemelerinizi şimdilik site yönetimine yapabilirsiniz.'), findsOneWidget);
  });
}
