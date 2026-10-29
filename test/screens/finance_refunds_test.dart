// Alacak iadesi (karar K4) yönetici arayüzü: iade talepleri penceresi (bekleyen liste, Hesap seçerek onay, nedenli ret, onaylı iadeyi geri alma, makbuz görüntüleme) ve
// Bakiyeler sekmesindeki giriş. Sunucu davranışı sahte 4b API'sinde taklit edilir (finance_4b_fixtures.dart: nakit Hesapta bakiye yetmezse 409, onayda makbuz, geri almada iptal).
//
// Fazla ödeme varsayılan olarak ALACAK kalır; iade YALNIZ yönetici onayıyla yapılır: onay Hesap seçmeden gönderilmez, ret gerekçe ister, kurul yalnız okur.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_refunds_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_refunds_entry.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

FinanceFakeAuth _auth() {
  final auth = FinanceFakeAuth.seeded();
  auth.f4.accounts.addAll(<Map<String, dynamic>>[
    f4AccountJson(1, 'Ana Kasa', balance: 100000),
    f4AccountJson(2, 'Banka', kind: 'bank', balance: 500000),
  ]);
  return auth;
}

Future<void> _open(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  double width = 420,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onChanged,
}) async {
  await openDialogAt(
    t,
    (context) => FinanceRefundsDialog.show(context, scope: _scope(auth, canWrite: canWrite), onChanged: onChanged),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  await settleFor(t);
}

Future<void> _tap(WidgetTester t, String key) async {
  await f4Tap(t, key);
  await settleFor(t);
}

bool _has(String key) => find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty;

/// Onay penceresinde Hesabı seçip onaylar.
Future<void> _approve(WidgetTester t, int refundId, int accountId) async {
  await _tap(t, 'finance_refund_approve_$refundId');
  await _tap(t, 'finance_refund_account_$accountId');
  await _tap(t, 'finance_refund_approve_confirm');
  await settleFor(t);
  await settleFor(t);
}

void main() {
  group('iade talepleri penceresi', () {
    testWidgets('bekleyen talepler daire, tutar, hesap türü ve sakin notuyla listelenir; özet doğru; hiçbir şey yazılmaz', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11, amount: 25000, note: 'Fazla ödedim');
      auth.f4.addRefund(id: 12, apartmentId: 302, label: 'A Blok - 6', amount: 10000, party: 'tenant', kind: 'manager');
      await _open(t, auth);
      expect(_has('finance_refund_11'), isTrue);
      expect(_has('finance_refund_12'), isTrue);
      expect(find.text('2 talep onay bekliyor'), findsOneWidget);
      expect(find.text('Toplam 350,00 ₺'), findsOneWidget);
      expect(find.text('250,00 ₺'), findsOneWidget);
      expect(find.text('Sakinin notu: Fazla ödedim'), findsOneWidget);
      expect(find.text('Yönetim açtı'), findsOneWidget);
      expect(find.text('Onay bekliyor'), findsNWidgets(2));
      expect(auth.f4.writes, isEmpty, reason: 'listeleme yazmaz');
      expect(auth.f4.callCount('listRefunds'), 1);
    });

    testWidgets('kurul (salt okur): liste görünür; Onayla / Reddet / Geri Al düğmeleri YOK', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11);
      await _open(t, auth, canWrite: false);
      expect(_has('finance_refund_11'), isTrue);
      expect(_has('finance_refund_approve_11'), isFalse);
      expect(_has('finance_refund_reject_11'), isFalse);
    });

    testWidgets('okunamazsa asla "talep yok" denmez: neden yazılır, Tekrar Dene yeniden okur', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11);
      auth.f4.refundListError = ApiException('İade talepleri yüklenemedi.', statusCode: 500, code: 'INTERNAL');
      await _open(t, auth);
      expect(_has('finance_refunds_error'), isTrue);
      expect(_has('finance_refunds_empty'), isFalse);
      expect(find.text('Onay bekleyen iade talebi yok.'), findsNothing);
      auth.f4.refundListError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      await settleFor(t);
      expect(_has('finance_refund_11'), isTrue);
    });

    testWidgets('boş liste: "Onay bekleyen iade talebi yok." yazılır', (t) async {
      final auth = _auth();
      await _open(t, auth);
      expect(_has('finance_refunds_empty'), isTrue);
      expect(find.text('Onay bekleyen iade talebi yok.'), findsWidgets);
    });
  });

  group('onay, ret, geri alma', () {
    testWidgets('onay: Hesap seçilmeden gönderilmez; nakit yetmezse sunucu reddi pencerede kalır; banka Hesabıyla onaylanınca makbuz yazılır ve listeden düşer', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11, amount: 150000);
      var changed = 0;
      await _open(t, auth, onChanged: () => changed++);
      await _tap(t, 'finance_refund_approve_11');
      expect(find.text('İadeyi Onayla'), findsWidgets);
      final confirm = find.byKey(const ValueKey<String>('finance_refund_approve_confirm'));
      expect(t.widget<ElevatedButton>(confirm).onPressed, isNull, reason: 'Hesap seçilmeden onay açılmaz');
      expect(auth.f4.writes, isEmpty);

      // nakit kasa: bakiye 1.000,00 ₺ < 1.500,00 ₺ -> uyarı + sunucu 409
      await _tap(t, 'finance_refund_account_1');
      expect(_has('finance_refund_cash_short'), isTrue);
      await _tap(t, 'finance_refund_approve_confirm');
      await settleFor(t);
      expect(find.textContaining('Seçilen kasada yeterli nakit yok'), findsWidgets);
      expect(_has('finance_refund_approve_error'), isTrue);
      expect(auth.f4.refundRows.single['status'], 'requested', reason: 'reddedilen onay hiçbir şeyi değiştirmez');

      // banka Hesabı: onay
      await _tap(t, 'finance_refund_account_2');
      expect(_has('finance_refund_cash_short'), isFalse);
      await _tap(t, 'finance_refund_approve_confirm');
      await settleFor(t);
      await settleFor(t);
      final approve = auth.f4.writes.where((w) => w['op'] == 'approveRefund').last;
      expect(approve['refund_id'], 11);
      expect(approve['pay_account_id'], 2);
      expect((approve['key'] as String).isNotEmpty, isTrue);
      expect(changed, 1);
      expect(auth.f4.refundRows.single['status'], 'approved');
      expect(_has('finance_refund_approve_confirm'), isFalse, reason: 'başarıda onay penceresi kapanır');
      expect(_has('finance_refund_11'), isFalse, reason: 'bekleyen süzgecinde artık yok');
      expect(find.text('Onay bekleyen iade talebi yok.'), findsWidgets);
    });

    testWidgets('onaylı iade: "İade edilen" süzgecinde makbuz numarası, Makbuzu Gör makbuzu açar (numara, hesap, doğrulama kodu)', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11, amount: 25000);
      await _open(t, auth);
      await _approve(t, 11, 2);
      await _tap(t, 'finance_refunds_filter_approved');
      expect(_has('finance_refund_11'), isTrue);
      expect(find.text('İade edildi'), findsOneWidget);
      expect(find.textContaining('İade makbuzu IA-2026-000001 • Banka'), findsOneWidget);
      await _tap(t, 'finance_refund_receipt_11');
      expect(find.text('İade Makbuzu'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_refund_receipt_number')), findsOneWidget);
      expect(find.text('IA-2026-000001'), findsOneWidget);
      expect(find.text('KOD12345'), findsOneWidget);
      expect(find.text('Banka'), findsWidgets);
      expect(_has('finance_refund_receipt_cancelled'), isFalse);
    });

    testWidgets('ret: gerekçe zorunlu; gerekçe sunucuya gider, talep düşer ve sakine görünecek neden kaydedilir', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11, amount: 25000);
      var changed = 0;
      await _open(t, auth, onChanged: () => changed++);
      await _tap(t, 'finance_refund_reject_11');
      await _tap(t, 'finance_reason_confirm');
      expect(find.text('Ret nedeni girin.'), findsOneWidget);
      expect(auth.f4.writes, isEmpty);
      await f4Enter(t, 'finance_reason_text', 'Alacak başka borca mahsup edildi');
      await _tap(t, 'finance_reason_confirm');
      await settleFor(t);
      await settleFor(t);
      final write = auth.f4.writes.single;
      expect(write['op'], 'rejectRefund');
      expect(write['reason'], 'Alacak başka borca mahsup edildi');
      expect(auth.f4.refundRows.single['status'], 'rejected');
      expect(auth.f4.refundRows.single['reject_reason'], 'Alacak başka borca mahsup edildi');
      expect(changed, 1);
      expect(_has('finance_refund_11'), isFalse);
    });

    testWidgets('onaylı iadeyi geri al: nedenli; makbuz iptal sayılır; Geri Al düğmesi kaybolur', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11, amount: 25000);
      await _open(t, auth);
      await _approve(t, 11, 2);
      await _tap(t, 'finance_refunds_filter_approved');
      await _tap(t, 'finance_refund_reverse_11');
      await f4Enter(t, 'finance_reason_text', 'Yanlış daireye onaylandı');
      await _tap(t, 'finance_reason_confirm');
      await settleFor(t);
      await settleFor(t);
      final write = auth.f4.writes.where((w) => w['op'] == 'reverseRefund').single;
      expect(write['reason'], 'Yanlış daireye onaylandı');
      expect(auth.f4.refundRows.single['status'], 'reversed');
      // geçmişte (Tümü) kayıt kalır: durum, neden ve iptal edilmiş makbuz
      await _tap(t, 'finance_refunds_filter_all');
      expect(find.text('İade geri alındı'), findsOneWidget);
      expect(find.text('Geri alma nedeni: Yanlış daireye onaylandı'), findsOneWidget);
      expect(_has('finance_refund_reverse_11'), isFalse);
      await _tap(t, 'finance_refund_receipt_11');
      expect(_has('finance_refund_receipt_cancelled'), isTrue);
    });
  });

  group('Bakiyeler sekmesi girişi', () {
    testWidgets('bekleyen talep varsa uyarı kartı sayı ve toplamı yazar, İadeleri İncele pencereyi açar; her durumda İade talepleri düğmesi vardır', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 11, amount: 25000);
      await pumpAt(
        t,
        SingleChildScrollView(
          child: FinanceRefundsEntry(scope: _scope(auth), onChanged: () {}, extraAction: const OutlinedButton(onPressed: null, child: Text('Devir bakiyesi'))),
        ),
        width: 420,
        height: 1200,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await settleFor(t);
      expect(_has('finance_refunds_banner'), isTrue);
      expect(find.textContaining('1 sakin fazla ödemesinin iadesini istedi, toplam 250,00 ₺.'), findsOneWidget);
      expect(_has('finance_refunds_button'), isTrue);
      expect(find.text('Devir bakiyesi'), findsOneWidget);
      await _tap(t, 'finance_refunds_banner_open');
      expect(_has('finance_refund_11'), isTrue);
    });

    testWidgets('bekleyen yoksa kart çizilmez ama İade talepleri düğmesi durur; sayı okunamazsa da kart çizilmez (yanlış güvence yok)', (t) async {
      final auth = _auth();
      await pumpAt(t, SingleChildScrollView(child: FinanceRefundsEntry(scope: _scope(auth), onChanged: () {})), width: 420, height: 800, scale: 1.0, dark: false);
      await settleFor(t);
      await settleFor(t);
      expect(_has('finance_refunds_banner'), isFalse);
      expect(_has('finance_refunds_button'), isTrue);
    });
  });

  testWidgets('dar ekran, büyük yazı, koyu tema: uzun not ve ret nedeniyle taşma yok', (t) async {
    final auth = _auth();
    auth.f4.addRefund(id: 11, amount: 123456789, note: 'Çok uzun bir sakin notu ' * 6);
    auth.f4.addRefund(id: 12, status: 'rejected', rejectReason: 'Ret nedeni de oldukça uzun bir açıklama içeriyor ' * 3);
    await _open(t, auth, width: 320, height: 640, scale: 2.0, dark: true);
    await f4Tap(t, 'finance_refunds_filter_all');
    await settleFor(t);
    expect(_has('finance_refund_11'), isTrue);
    expect(_has('finance_refund_12'), isTrue);
    expect(t.takeException(), isNull);
  });
}
