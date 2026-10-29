// Alacak iadesi (karar K4) sakin arayüzü: "Borcum" kartında "Fazla ödememi iade et" talebi ve talep durumları.
//
// Fazla ödeme varsayılan olarak ALACAK kalır ve sonraki borçtan düşer; iade istek + site yönetiminin onayıyla yapılır. Talep tutarı alacakla (bekleyen talepler düşülerek) sınırlıdır,
// bekleyen talep onaydan önce geri çekilebilir, talepler okunamazsa "talep yok" denmez. Alacak ve talep yoksa bölüm hiç çizilmez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 29, 9);

/// [balance] eksi ise alacak (kuruş).
FinanceFakeAuth _auth({int balance = -50000}) {
  final auth = FinanceFakeAuth.seeded();
  auth.myFinanceItems = <Map<String, dynamic>>[
    finMyItem(balance: balance, overdue: 0, nextDueDate: null, nextDueMinor: null, recent: <Map<String, dynamic>>[]),
  ];
  auth.f4.refundCreditMinor = balance < 0 ? -balance : 0;
  return auth;
}

Future<void> _pump(WidgetTester t, FinanceFakeAuth auth, {double width = 400, double height = 3000, double scale = 1.0, bool dark = false}) async {
  await pumpList(t, MyFinanceView(authService: auth, now: () => _now), width: width, height: height, scale: scale, dark: dark);
  await settleFor(t, 100);
  await settleFor(t, 100);
}

bool _has(String key) => find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty;

Future<void> _tap(WidgetTester t, String key) async {
  await f4Tap(t, key);
  await settleFor(t);
}

void main() {
  group('talep açma', () {
    testWidgets('alacak varken bölüm çıkar; tutar alacağa kadar önerilir; talep yönetici onayını bekler ve talepler listesinde görünür', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(_has('my_refund_section'), isTrue);
      expect(find.textContaining('iade site yönetiminin onayıyla yapılır'), findsWidgets);
      await _tap(t, 'my_refund_request');
      expect(find.text('Fazla Ödememi İade Et'), findsOneWidget);
      expect(find.text('İstenebilecek en çok tutar: 500,00 ₺'), findsOneWidget);
      final amount = t.widget<TextFormField>(find.byKey(const ValueKey<String>('my_refund_amount')));
      expect(amount.controller?.text, '500,00', reason: 'varsayılan: alacağın tamamı');

      await f4Enter(t, 'my_refund_amount', '200');
      await f4Enter(t, 'my_refund_note', 'Lütfen iade edin');
      await _tap(t, 'my_refund_submit');
      await settleFor(t);
      final write = auth.f4.writes.single;
      expect(write['op'], 'createMyRefundRequest');
      expect(write['apartment_id'], 301);
      expect(write['amount_minor'], 20000);
      expect(write['note'], 'Lütfen iade edin');
      expect((write['key'] as String).isNotEmpty, isTrue);
      expect(_has('my_refund_submit'), isFalse, reason: 'başarıda pencere kapanır');

      // talep listede; onaylanana dek "Onay bekliyor" ve geri çekilebilir; kalan tutar bekleyen talep düşülerek yazılır
      expect(find.text('200,00 ₺'), findsOneWidget);
      expect(find.text('Onay bekliyor'), findsOneWidget);
      expect(_has('my_refund_cancel_1'), isTrue);
      expect(find.text('Yeni talep için kalan: 300,00 ₺'), findsOneWidget);
    });

    testWidgets('alacaktan fazla tutar sunucuya gitmez: neden alacak tutarıyla yazılır', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _tap(t, 'my_refund_request');
      await f4Enter(t, 'my_refund_amount', '600');
      await _tap(t, 'my_refund_submit');
      expect(find.text('İade tutarı alacağınızdan (500,00 ₺) fazla olamaz.'), findsOneWidget);
      expect(auth.f4.writes, isEmpty);
      expect(_has('my_refund_submit'), isTrue, reason: 'pencere açık kalır');
    });

    testWidgets('sunucu reddederse (alacak bu arada kapandı) pencerede Türkçe neden görünür ve talep açılmaz', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      auth.f4.refundCreditMinor = 0; // sunucu tarafında alacak değişti
      await _tap(t, 'my_refund_request');
      await _tap(t, 'my_refund_submit');
      await settleFor(t);
      expect(find.text('Bu hesapta iade edilecek alacak (fazla ödeme) yok.'), findsOneWidget);
      expect(auth.f4.refundRows, isEmpty);
    });

    testWidgets('bekleyen talepler alacağın tamamını kapsıyorsa düğme yerine açıklama çıkar', (t) async {
      final auth = _auth();
      auth.f4.addRefund(amount: 50000);
      await _pump(t, auth);
      expect(_has('my_refund_request'), isFalse);
      expect(_has('my_refund_all_pending'), isTrue);
      expect(find.text('Bekleyen iade talepleriniz alacağınızın tamamını kapsıyor.'), findsOneWidget);
    });
  });

  group('talep durumları', () {
    testWidgets('bekleyen talep geri çekilir: durum "Geri çekildi", düğme kalkar, alacak yeniden istenebilir', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 7, amount: 50000);
      await _pump(t, auth);
      await _tap(t, 'my_refund_cancel_7');
      await settleFor(t);
      expect(auth.f4.callCount('cancelMyRefundRequest'), 1);
      expect(find.text('Geri çekildi'), findsOneWidget);
      expect(_has('my_refund_cancel_7'), isFalse);
      expect(_has('my_refund_request'), isTrue, reason: 'bekleyen talep kalmadı: yeniden istenebilir');
    });

    testWidgets('onaylanan talep: iade makbuzu numarası ve Makbuzu Gör; reddedilen talep: neden sakine görünür', (t) async {
      final auth = _auth(balance: 0); // iade sonrası alacak sıfır: bölüm talep geçmişi için yine de çıkar
      auth.f4.addRefund(id: 8, amount: 30000, status: 'approved').addAll(<String, dynamic>{
        'pay_date': '2026-10-28',
        'receipt': <String, dynamic>{
          'number': 'IA-2026-000004',
          'issued_on': '2026-10-28',
          'verification_code': 'KOD99999',
          'status': 'active',
          'snapshot': <String, dynamic>{
            'from_account': <String, dynamic>{'name': 'Ana Kasa'},
            'apartment': <String, dynamic>{'label': 'A Blok - 5'},
            'site': <String, dynamic>{'name': 'Gül Sitesi'},
            'method': 'transfer',
            'paid_on': '2026-10-28',
          },
        },
      });
      auth.f4.addRefund(id: 9, amount: 10000, status: 'rejected', rejectReason: 'Önce aidat borcunuz kapanmalı');
      await _pump(t, auth);
      expect(_has('my_refund_section'), isTrue);
      expect(_has('my_refund_request'), isFalse, reason: 'alacak yok: yeni talep düğmesi yok');
      expect(find.text('İade edildi'), findsOneWidget);
      expect(find.text('İade makbuzu IA-2026-000004'), findsOneWidget);
      expect(find.text('Reddedildi'), findsOneWidget);
      expect(find.text('Ret nedeni: Önce aidat borcunuz kapanmalı'), findsOneWidget);
      await _tap(t, 'my_refund_receipt_8');
      expect(find.text('İade Makbuzu'), findsOneWidget);
      expect(find.text('IA-2026-000004'), findsOneWidget);
      expect(find.text('KOD99999'), findsOneWidget);
    });

    testWidgets('talepler okunamazsa "talep yok" denmez: neden + Tekrar Dene; alacak varsa yine de iade istenebilir', (t) async {
      final auth = _auth();
      auth.f4.refundListError = ApiException('İade talepleri yüklenemedi.', statusCode: 500, code: 'INTERNAL');
      await _pump(t, auth);
      expect(_has('my_refund_load_error'), isTrue);
      expect(find.text('İade taleplerim'), findsNothing);
      auth.f4.refundListError = null;
      auth.f4.addRefund(id: 3, amount: 10000);
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      await settleFor(t);
      expect(_has('my_refund_load_error'), isFalse);
      expect(_has('my_refund_3'), isTrue);
    });
  });

  group('görünürlük', () {
    testWidgets('borcu olan ve talebi olmayan daire: bölüm hiç çizilmez', (t) async {
      final auth = _auth(balance: 100000);
      await _pump(t, auth);
      expect(_has('my_refund_section'), isFalse);
      expect(find.text('Fazla ödememi iade et'), findsNothing);
    });

    testWidgets('bakiyesi sıfır ve talebi olmayan daire: bölüm hiç çizilmez', (t) async {
      final auth = _auth(balance: 0);
      await _pump(t, auth);
      expect(_has('my_refund_section'), isFalse);
    });

    testWidgets('dar ekran, büyük yazı, koyu tema: bölüm, talep penceresi ve uzun ret nedeni taşmaz', (t) async {
      final auth = _auth();
      auth.f4.addRefund(id: 5, amount: 10000, status: 'rejected', rejectReason: 'Uzun bir ret nedeni açıklaması ' * 5);
      await _pump(t, auth, width: 320, height: 640, scale: 2.0, dark: true);
      await _tap(t, 'my_refund_request');
      expect(find.text('Fazla Ödememi İade Et'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
