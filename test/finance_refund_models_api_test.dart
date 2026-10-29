// Alacak iadesi (K4): modeller + Finance4bApi uçları (docs/PLATFORM_FINANS.md "Alacak iadesi"). MockClient ile: uç yolları, HTTP yöntemleri, gövdeler (tutar KURUŞ tamsayı,
// kırpılmış neden / not, işlem anahtarı), 200/201 ayrımı, bozuk yanıtın sessiz 0 yerine hata vermesi ve hata kodlarının Türkçe eşlenmesi.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';
import 'package:site_kapi_kontrol/services/finance_4b_errors.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Rec {
  final List<http.Request> requests = <http.Request>[];

  http.Request get last => requests.last;

  Map<String, dynamic> get body => jsonDecode(last.body) as Map<String, dynamic>;
}

Finance4bApi _api(_Rec rec, FutureOr<http.Response> Function(http.Request request) handler) {
  return Finance4bApi(
    baseUrl: 'https://api.example.test/',
    client: MockClient((request) async {
      rec.requests.add(request);
      return handler(request);
    }),
  );
}

Map<String, dynamic> _refund({String status = 'requested', bool receipt = false}) => <String, dynamic>{
  'id': 9,
  'apartment_id': 301,
  'apartment_label': 'A Blok - 5',
  'account_party': 'owner',
  'amount_minor': 25000,
  'status': status,
  'requested_by_kind': 'resident',
  'requested_at': '2026-10-28T08:00:00.000Z',
  'resolved_at': null,
  'reject_reason': status == 'rejected' ? 'Önce borç kapanmalı' : null,
  'note': 'Fazla ödedim',
  'pay_date': receipt ? '2026-10-29' : null,
  'reversed_at': null,
  'receipt': receipt
      ? <String, dynamic>{
          'number': 'IA-2026-000003',
          'issued_on': '2026-10-29',
          'verification_code': 'KOD12345',
          'status': status == 'reversed' ? 'cancelled' : 'active',
          'snapshot': <String, dynamic>{
            'site': <String, dynamic>{'name': 'Gül Sitesi'},
            'apartment': <String, dynamic>{'label': 'A Blok - 5'},
            'payee': <String, dynamic>{'party': 'owner', 'name': 'Ayşe Yılmaz'},
            'from_account': <String, dynamic>{'name': 'Banka'},
            'issuer': <String, dynamic>{'name': 'Yönetici'},
            'method': 'transfer',
            'paid_on': '2026-10-29',
          },
        }
      : null,
};

void main() {
  const token = 'tok';

  group('modeller', () {
    test('RefundRequest: kuruş tamsayı, durum, hesap türü, makbuz özeti ve anlık görüntü alanları; sakin görünümünde yönetici alanları boş', () {
      final refund = RefundRequest.fromJson(_refund(status: 'approved', receipt: true));
      expect(refund.amountMinor, 25000);
      expect(refund.status, RefundStatus.approved);
      expect(refund.isApproved, isTrue);
      expect(refund.accountParty, AccountParty.owner);
      expect(refund.note, 'Fazla ödedim');
      expect(refund.receipt?.number, 'IA-2026-000003');
      expect(refund.receipt?.cancelled, isFalse);
      expect(refund.receipt?.fromAccountName, 'Banka');
      expect(refund.receipt?.payeeName, 'Ayşe Yılmaz');
      expect(refund.receipt?.method, 'transfer');
      expect(refund.receipt?.apartmentLabel, 'A Blok - 5');
      expect(refund.payAccountName, isNull, reason: 'sakin görünümünde sunucu yönetici alanı göndermez');
      expect(RefundRequest.fromJson(_refund(status: 'reversed', receipt: true)).receipt?.cancelled, isTrue, reason: 'geri alınan iadenin makbuzu iptal sayılır');
      expect(RefundRequest.fromJson(_refund(status: 'rejected')).rejectReason, 'Önce borç kapanmalı');
    });

    test('bilinmeyen durum "Durum bilinmiyor" olur; bozuk tutar / kimlik sessiz 0 yerine FormatException', () {
      expect(RefundRequest.fromJson(<String, dynamic>{..._refund(), 'status': 'yeni_bir_durum'}).status, RefundStatus.unknown);
      expect(RefundStatus.unknown.label, 'Durum bilinmiyor');
      expect(() => RefundRequest.fromJson(<String, dynamic>{..._refund(), 'amount_minor': 'abc'}), throwsFormatException);
      expect(() => RefundRequest.fromJson(<String, dynamic>{..._refund(), 'id': null}), throwsFormatException);
    });

    test('RefundPage: bekleyen özet ve sonraki sayfa imleci', () {
      final page = RefundPage.fromJson(<String, dynamic>{
        'items': <dynamic>[_refund()],
        'pending_count': 3,
        'pending_total_minor': 70000,
        'next_before_id': 9,
      });
      expect(page.items.length, 1);
      expect(page.pendingCount, 3);
      expect(page.pendingTotalMinor, 70000);
      expect(page.nextBeforeId, 9);
    });
  });

  group('Finance4bApi iade uçları', () {
    test('createMyRefundRequest: POST /app/my-finance/refund-requests { apartment_id, amount_minor (kuruş), kırpılmış not, idempotency_key }; boş not gönderilmez', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'refund': _refund()}, 201));
      final created = await api.createMyRefundRequest(token: token, apartmentId: 301, amountMinor: 25000, note: '  Fazla ödedim  ', idempotencyKey: 'rfn-req-1');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/app/my-finance/refund-requests');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(rec.body, <String, dynamic>{'apartment_id': 301, 'amount_minor': 25000, 'note': 'Fazla ödedim', 'idempotency_key': 'rfn-req-1'});
      expect(created.id, 9);
      await api.createMyRefundRequest(token: token, apartmentId: 301, amountMinor: 100, note: '   ', idempotencyKey: 'rfn-req-2');
      expect(rec.body.containsKey('note'), isFalse);
    });

    test('listMyRefundRequests: GET ?apartment_id=; cancelMyRefundRequest: POST …/:id/cancel (gövdesiz)', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.method == 'GET') return _json(<String, dynamic>{'items': <dynamic>[_refund(), _refund(status: 'cancelled')]});
        return _json(<String, dynamic>{'refund': _refund(status: 'cancelled')});
      });
      final items = await api.listMyRefundRequests(token: token, apartmentId: 301);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/my-finance/refund-requests');
      expect(rec.last.url.queryParameters, <String, String>{'apartment_id': '301'});
      expect(items.map((r) => r.status).toList(), <RefundStatus>[RefundStatus.requested, RefundStatus.cancelled]);
      final cancelled = await api.cancelMyRefundRequest(token: token, refundId: 9);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/app/my-finance/refund-requests/9/cancel');
      expect(cancelled.status, RefundStatus.cancelled);
    });

    test('yönetici: listRefunds süzgeç + imleç; approve { pay_account_id, idempotency_key }; reject / reverse { kırpılmış neden, idempotency_key }', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.method == 'GET') return _json(<String, dynamic>{'items': <dynamic>[_refund()], 'pending_count': 1, 'pending_total_minor': 25000, 'next_before_id': null});
        return _json(<String, dynamic>{'refund': _refund(status: 'approved', receipt: true)}, 201);
      });
      final page = await api.listRefunds(token: token, siteCode: 11, status: 'all', beforeId: 20, limit: 25);
      expect(rec.last.url.path, '/manager/sites/11/finance/refunds');
      expect(rec.last.url.queryParameters, <String, String>{'status': 'all', 'before_id': '20', 'limit': '25'});
      expect(page.pendingCount, 1);
      expect((await api.listRefunds(token: token, siteCode: 11)).items.length, 1);
      expect(rec.last.url.queryParameters['status'], 'requested', reason: 'varsayılan: bekleyenler');

      final approved = await api.approveRefund(token: token, siteCode: 11, refundId: 9, payAccountId: 2, idempotencyKey: 'rfn-ok-1');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/refunds/9/approve');
      expect(rec.body, <String, dynamic>{'pay_account_id': 2, 'idempotency_key': 'rfn-ok-1'});
      expect(approved.receipt?.number, 'IA-2026-000003');

      await api.rejectRefund(token: token, siteCode: 11, refundId: 9, reason: '  Önce borç kapanmalı ', idempotencyKey: 'rfn-rej-1');
      expect(rec.last.url.path, '/manager/sites/11/finance/refunds/9/reject');
      expect(rec.body, <String, dynamic>{'reason': 'Önce borç kapanmalı', 'idempotency_key': 'rfn-rej-1'});

      await api.reverseRefund(token: token, siteCode: 11, refundId: 9, reason: ' Yanlış daire ', idempotencyKey: 'rfn-rev-1');
      expect(rec.last.url.path, '/manager/sites/11/finance/refunds/9/reverse');
      expect(rec.body, <String, dynamic>{'reason': 'Yanlış daire', 'idempotency_key': 'rfn-rev-1'});
    });

    test('sunucu hataları ApiException olur ve kodu korunur; yazma isteği yeniden denenmez; bozuk yanıt Türkçe hata verir', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'error': 'Seçilen kasada yeterli nakit yok.', 'code': 'CASH_INSUFFICIENT'}, 409));
      await expectLater(
        api.approveRefund(token: token, siteCode: 11, refundId: 9, payAccountId: 1, idempotencyKey: 'rfn-ok-2'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CASH_INSUFFICIENT').having((e) => e.statusCode, 'status', 409)),
      );
      expect(rec.requests.length, 1, reason: 'yazma isteği yeniden denenmez');
      final broken = _api(_Rec(), (r) => _json(<String, dynamic>{'refund': <String, dynamic>{'id': 9, 'apartment_id': 301, 'status': 'requested'}}, 201));
      await expectLater(
        broken.cancelMyRefundRequest(token: token, refundId: 9),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('işlenemedi'))),
      );
    });
  });

  test('iade hata kodları Türkçe eşlenir; teknik kod görünmez', () {
    for (final code in const ['NO_CREDIT', 'REFUND_EXCEEDS_CREDIT', 'TOO_MANY_PENDING', 'REFUND_NOT_FOUND', 'REFUND_NOT_PENDING', 'REFUND_NOT_APPROVED', 'CASH_INSUFFICIENT', 'RECEIPT_UNAVAILABLE']) {
      final message = finance4bErrorMessage(code);
      expect(message, isNotNull, reason: code);
      expect(message, isNot(contains(code)), reason: code);
      expect(message!.endsWith('.'), isTrue, reason: code);
    }
  });
}
