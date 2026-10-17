// Platform Faz 4b (Finans devamı): Finance4bApi / Finance4bService uçları (docs/PLATFORM_FINANS_4B.md).
//
// MockClient ile: uç yolları, HTTP yöntemleri, gövdeler (tutarlar KURUŞ tamsayı), sorgu parametreleri, Bearer
// başlığı, 200/201 (idempotent tekrar) ayrımı, hata kodu -> Türkçe mesaj eşlemeleri ve yazma isteklerinin ASLA
// otomatik yeniden denenmemesi. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';

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

Map<String, dynamic> _receiptJson() => <String, dynamic>{
  'id': 9,
  'status': 'active',
  'copy_count': 0,
  'snapshot': <String, dynamic>{
    'number': 'MK-2026-000123',
    'kind': 'collection',
    'amount_minor': 123456,
    'issued_on': '2026-10-16',
    'paid_on': '2026-10-14',
    'method': 'cash',
    'site': <String, dynamic>{'name': 'Gül Sitesi'},
    'apartment': <String, dynamic>{'label': 'A Blok - 5'},
    'payer': <String, dynamic>{'party': 'owner', 'name': null},
    'issuer': <String, dynamic>{'name': 'Yönetici'},
    'verification_code': 'AB12CD34EF56',
    'cekince': true,
    'template_version': 1,
  },
};

void main() {
  const token = 'tok';

  group('taşıma: yetki, yol ve hata çevirisi', () {
    test('Bearer başlığı gider; temel adres sonundaki / temizlenir; sorgu yalnız dolu süzgeçleri taşır', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'items': <dynamic>[], 'next_before_id': null}));
      await api.listReceipts(token: token, siteCode: 11, apartmentId: 301, year: 2026, kind: ReceiptKind.collection, query: ' MK ', limit: 20, beforeId: 50);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/11/finance/receipts');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(rec.last.url.queryParameters, <String, String>{
        'apartment_id': '301',
        'year': '2026',
        'kind': 'collection',
        'q': 'MK',
        'limit': '20',
        'before_id': '50',
      });
      await api.listReceipts(token: token, siteCode: 11);
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50'});
    });

    test('4b hata kodu Türkçe metne eşlenir; ham kod ve teknik ifade sızmaz', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'error': 'raw english text', 'code': 'ACCOUNT_REQUIRED'}, 409));
      try {
        await api.listAccounts(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.code, 'ACCOUNT_REQUIRED');
        expect(e.statusCode, 409);
        expect(e.message, 'Bu sitede kasa ya da banka hesabı tanımlı; tahsilat için bir hesap seçin.');
        expect(e.genericFallback, isFalse);
      }
    });

    test('yeni sözleşme kodlarının hepsi Türkçe metinle eşli (ham kod gösterilmez)', () async {
      const codes = <String>[
        'RECEIPT_NOT_FOUND', 'PAYMENT_REVERSED', 'RECEIPT_ALREADY_CANCELLED', 'RECEIPT_NOT_CANCELLABLE',
        'LATE_FEE_DISABLED', 'LATE_FEE_NOT_CONFIGURED', 'LATE_FEE_PERIOD_NOT_CLOSED', 'LATE_FEE_PERIOD_NOT_ENDED',
        'LATE_FEE_PERIOD_NOT_NEXT', 'LATE_FEE_ALREADY_POSTED', 'LATE_FEE_RUN_NOT_FOUND', 'LATE_FEE_RUN_NOT_VOIDABLE',
        'PERIOD_HAS_LATE_FEE_RUN', 'NO_ACCOUNT', 'ACCOUNT_NOT_FOUND', 'ACCOUNT_REQUIRED',
        'ACCOUNT_LIMIT', 'ACCOUNT_NAME_TAKEN', 'BEFORE_OPENING_DATE', 'TRANSFER_NOT_FOUND', 'TRANSFER_ALREADY_VOIDED',
        'RECONCILIATION_STALE', 'RECONCILIATION_ORDER', 'PERIOD_HAS_UNASSIGNED_PAYMENTS', 'EXPENSE_NOT_FOUND', 'EXPENSE_ALREADY_VOIDED',
        'DUPLICATE_EXPENSE', 'DUPLICATE_DOCUMENT_NO', 'CATEGORY_NOT_FOUND', 'CATEGORY_INACTIVE', 'SUPPLIER_NOT_FOUND',
        'DOCUMENTS_NOT_AVAILABLE', 'EXPENSE_DOCUMENT_LIMIT', 'STATEMENT_TOO_LARGE', 'REPORT_BUSY', 'REMINDERS_DISABLED',
        'REMINDER_DAILY_LIMIT', 'NO_REMINDER_RECIPIENTS', 'EMAIL_NOT_CONFIGURED', 'REMINDER_RUN_NOT_FOUND',
        'REMINDER_RUN_NOT_CANCELLABLE', 'SETTINGS_STALE', 'EXPORT_TOO_LARGE', 'DOCUMENT_NOT_FOUND', 'DOCUMENT_TOO_LARGE',
        'DOCUMENT_TYPE_NOT_ALLOWED', 'DOCUMENT_CONTENT_MISMATCH', 'DOCUMENT_ACTIVE_CONTENT', 'DOCUMENT_QUOTA_EXCEEDED',
        'UPLOAD_BUSY', 'DOCUMENT_STORAGE_FULL', 'DOCUMENT_STORAGE_NOT_CONFIGURED',
      ];
      for (final code in codes) {
        final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'english', 'code': code}, 409));
        try {
          await api.listAccounts(token: token, siteCode: 11);
          fail('hata bekleniyordu: $code');
        } on ApiException catch (e) {
          expect(e.genericFallback, isFalse, reason: code);
          expect(e.message, isNot(contains(code)), reason: code);
          expect(e.message, isNot(contains('english')), reason: code);
          expect(e.message.trim(), isNotEmpty, reason: code);
        }
      }
    });

    test('429: bekleme süresi ileti ve alanda; 401: oturum bitti; JSON olmayan 403 geçici ağ hatası', () async {
      final api429 = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'x', 'code': 'RATE', 'retry_after_seconds': 90}, 429));
      try {
        await api429.listAccounts(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.isRateLimited, isTrue);
        expect(e.retryAfterSeconds, 90);
      }
      final api401 = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'x'}, 401));
      expect(api401.listAccounts(token: token, siteCode: 11), throwsA(isA<SessionExpiredException>()));
      final apiProxy = _api(_Rec(), (r) => http.Response('<html>blocked</html>', 403));
      try {
        await apiProxy.listAccounts(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.fromIntermediary, isTrue);
        expect(e.invalidatesSession, isFalse);
      }
    });

    test('REPORT_BUSY Retry-After başlığından bekleme süresi alır', () async {
      final api = _api(
        _Rec(),
        (r) => http.Response(
          jsonEncode(<String, dynamic>{'error': 'busy', 'code': 'REPORT_BUSY'}),
          503,
          headers: <String, String>{'content-type': 'application/json', 'retry-after': '7'},
        ),
      );
      try {
        await api.getCashPositionReport(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.retryAfterSeconds, 7);
        expect(e.message, contains('7 saniye'));
      }
    });

    test('yazma isteği bir kez gönderilir: ağ hatasında otomatik yeniden deneme YOK', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => throw http.ClientException('kopuk'));
      await expectLater(
        api.createAccount(
          token: token,
          siteCode: 11,
          name: 'Kasa',
          kind: CashAccountKind.cash,
          openingBalanceMinor: 0,
          openingDate: DateTime(2026, 1, 1),
          idempotencyKey: 'k1',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(rec.requests, hasLength(1));
    });

    test('okuma yanıtı boşsa "veri yok" sayılmaz: hata', () async {
      final api = _api(_Rec(), (r) => http.Response('', 200));
      await expectLater(api.listAccounts(token: token, siteCode: 11), throwsA(isA<ApiException>()));
    });

    test('bozuk tutar "veri işlenemedi" ApiException olur (FormatException sızmaz)', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'items': <dynamic>[], 'total_balance_minor': 'abc'}));
      try {
        await api.listAccounts(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.message, contains('işlenemedi'));
      }
    });
  });

  group('ayarlar', () {
    test('GET settings; PUT kısmi gövde expected_settings_version ile', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.method == 'PUT') {
          return _json(<String, dynamic>{'settings_version': 5, 'late_fee': <String, dynamic>{'enabled': true}});
        }
        return _json(<String, dynamic>{'settings_version': 4});
      });
      final got = await api.getSettings(token: token, siteCode: 11);
      expect(got.settingsVersion, 4);
      final updated = await api.updateSettings(
        token: token,
        siteCode: 11,
        patch: const FinanceSettingsPatch(lateFeeEnabled: true),
        expectedVersion: 4,
      );
      expect(rec.last.method, 'PUT');
      expect(rec.body, <String, dynamic>{
        'expected_settings_version': 4,
        'late_fee': <String, dynamic>{'enabled': true},
      });
      expect(updated!.settingsVersion, 5);
    });

    test('PUT yanıtı ayar taşımıyorsa null (çağıran yeniden okur)', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'ok': true}));
      final updated = await api.updateSettings(
        token: token,
        siteCode: 11,
        patch: const FinanceSettingsPatch(receiptAutoIssue: false),
        expectedVersion: 1,
      );
      expect(updated, isNull);
    });
  });

  group('makbuz', () {
    test('issueReceipt: 201 yeni, 200 var olan; getReceipt tam snapshot', () async {
      var status = 201;
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'receipt': _receiptJson()}, status));
      final created = await api.issueReceipt(token: token, siteCode: 11, entryId: 55);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/entries/55/receipt');
      expect(created.created, isTrue);
      expect(created.receipt.number, 'MK-2026-000123');
      status = 200;
      final again = await api.issueReceipt(token: token, siteCode: 11, entryId: 55);
      expect(again.created, isFalse);
      final api2 = _api(rec, (r) => _json(_receiptJson()));
      final receipt = await api2.getReceipt(token: token, siteCode: 11, receiptId: 9);
      expect(rec.last.url.path, '/manager/sites/11/finance/receipts/9');
      expect(receipt.amountMinor, 123456);
    });

    test('cancelReceipt: sabit neden kodu, not ve işlem anahtarı; print: kopya numarası', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/print')) return _json(<String, dynamic>{'copy_number': 2});
        return _json(<String, dynamic>{
          'cancellation': <String, dynamic>{..._receiptJson(), 'id': 10},
          'receipt': <String, dynamic>{..._receiptJson(), 'status': 'cancelled'},
        }, 201);
      });
      final result = await api.cancelReceipt(token: token, siteCode: 11, receiptId: 9, note: ' hatalı ', idempotencyKey: 'k2');
      expect(rec.body, <String, dynamic>{'reason_code': 'issued_in_error', 'note': 'hatalı', 'idempotency_key': 'k2'});
      expect(result.cancellation.id, 10);
      expect(result.receipt!.isCancelled, isTrue);
      final copy = await api.recordReceiptPrint(token: token, siteCode: 11, receiptId: 9, idempotencyKey: 'p1');
      expect(copy, 2);
      expect(rec.last.url.path, '/manager/sites/11/finance/receipts/9/print');
      expect(rec.body, <String, dynamic>{'idempotency_key': 'p1'});
    });

    test('print: kopya numarası okunamazsa hata (ASIL/KOPYA damgası uydurulmaz)', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'ok': true}));
      await expectLater(api.recordReceiptPrint(token: token, siteCode: 11, receiptId: 9), throwsA(isA<ApiException>()));
    });

    test('verify: gövde numara + kod, sonuç valid/status', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'valid': true, 'status': 'cancelled'}));
      final result = await api.verifyReceipt(token: token, siteCode: 11, number: ' MK-2026-000123 ', code: 'ab12cd34ef56');
      expect(rec.body, <String, dynamic>{'number': 'MK-2026-000123', 'code': 'ab12cd34ef56'});
      expect(result.valid, isTrue);
      expect(result.status, 'cancelled');
    });

    test('sakin uçları /app/my-finance altında', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.url.path.contains('/late-fee')) {
          return _json(<String, dynamic>{'period': '2026-09', 'rate_bp': 500, 'amount_minor': 100, 'segments': <dynamic>[]});
        }
        if (r.url.path.contains('/statement')) {
          return _json(<String, dynamic>{
            'apartment': <String, dynamic>{'id': 301},
            'opening_balance_minor': 0,
            'closing_balance_minor': 0,
            'items': <dynamic>[],
            'totals': <String, dynamic>{'charged_minor': 0, 'paid_minor': 0, 'reversed_minor': 0},
          });
        }
        if (r.url.path.endsWith('/receipts')) return _json(<String, dynamic>{'items': <dynamic>[]});
        return _json(_receiptJson());
      });
      await api.listMyReceipts(token: token, apartmentId: 301, limit: 10, beforeId: 4);
      expect(rec.last.url.path, '/app/my-finance/receipts');
      expect(rec.last.url.queryParameters, <String, String>{'apartment_id': '301', 'limit': '10', 'before_id': '4'});
      await api.getMyReceipt(token: token, receiptId: 9);
      expect(rec.last.url.path, '/app/my-finance/receipts/9');
      await api.getMyStatement(token: token, apartmentId: 301, from: DateTime(2026, 1, 1), to: DateTime(2026, 10, 16));
      expect(rec.last.url.path, '/app/my-finance/apartments/301/statement');
      expect(rec.last.url.queryParameters, <String, String>{'from': '2026-01-01', 'to': '2026-10-16'});
      final explanation = await api.getMyLateFeeExplanation(token: token, entryId: 77);
      expect(rec.last.url.path, '/app/my-finance/entries/77/late-fee');
      expect(explanation.amountMinor, 100);
    });
  });

  group('gecikme tazminatı', () {
    test('önizleme gövdesi: dönem, sıralı tekil muaf kimlikleri', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'period': '2026-09',
        'total_minor': 0,
        'apartment_count': 0,
        'lines': <dynamic>[],
        'can_post': false,
        'blockers': <String>['LATE_FEE_PERIOD_NOT_CLOSED'],
      }));
      final p = await api.previewLateFee(token: token, siteCode: 11, period: const FinancePeriod(2026, 9), excludedApartmentIds: <int>[5, 3, 5]);
      expect(rec.last.url.path, '/manager/sites/11/finance/late-fee/preview');
      expect(rec.body, <String, dynamic>{'period': '2026-09', 'excluded_apartment_ids': <int>[3, 5]});
      expect(p.canPost, isFalse);
    });

    test('post: beklenen toplam, sayı, özet ve işlem anahtarı; PREVIEW_STALE güncel değerleri taşır', () async {
      final rec = _Rec();
      var stale = false;
      final api = _api(rec, (r) {
        if (stale) {
          return _json(<String, dynamic>{'error': 'x', 'code': 'PREVIEW_STALE', 'total_minor': 999, 'apartment_count': 3, 'preview_hash': 'new'}, 409);
        }
        return _json(<String, dynamic>{
          'run': <String, dynamic>{'id': 13, 'period': '2026-09', 'total_minor': 12345, 'apartment_count': 2},
          'entries_count': 2,
        }, 201);
      });
      final result = await api.postLateFee(
        token: token,
        siteCode: 11,
        period: const FinancePeriod(2026, 9),
        excludedApartmentIds: <int>[7],
        expectedTotalMinor: 12345,
        expectedApartmentCount: 2,
        expectedHash: 'h1',
        idempotencyKey: 'late-1',
      );
      expect(rec.body, <String, dynamic>{
        'period': '2026-09',
        'excluded_apartment_ids': <int>[7],
        'expected_total_minor': 12345,
        'expected_apartment_count': 2,
        'expected_hash': 'h1',
        'idempotency_key': 'late-1',
      });
      expect(result.run.id, 13);
      stale = true;
      try {
        await api.postLateFee(
          token: token,
          siteCode: 11,
          period: const FinancePeriod(2026, 9),
          expectedTotalMinor: 1,
          expectedApartmentCount: 1,
          expectedHash: 'old',
          idempotencyKey: 'late-2',
        );
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.code, 'PREVIEW_STALE');
        final info = PreviewStaleInfo.fromPayload(e.payload);
        expect(info.totalMinor, 999);
        expect(info.apartmentCount, 3);
        expect(info.previewHash, 'new');
      }
    });

    test('runs / lines / void', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/void')) {
          return _json(<String, dynamic>{'run': <String, dynamic>{'id': 13, 'status': 'voided', 'total_minor': 1}, 'reversed_count': 2});
        }
        if (r.url.path.endsWith('/lines')) return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
        return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
      });
      await api.listLateFeeRuns(token: token, siteCode: 11, limit: 10, offset: 20);
      expect(rec.last.url.path, '/manager/sites/11/finance/late-fee/runs');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '10', 'offset': '20'});
      await api.listLateFeeRunLines(token: token, siteCode: 11, runId: 13);
      expect(rec.last.url.path, '/manager/sites/11/finance/late-fee/runs/13/lines');
      final voided = await api.voidLateFeeRun(token: token, siteCode: 11, runId: 13, reason: ' yanlış oran ', idempotencyKey: 'v1');
      expect(rec.last.url.path, '/manager/sites/11/finance/late-fee/runs/13/void');
      expect(rec.body, <String, dynamic>{'reason': 'yanlış oran', 'idempotency_key': 'v1'});
      expect(voided.run.isVoided, isTrue);
    });
  });

  group('kasa / banka', () {
    test('createAccount gövdesi: kuruş, açılış tarihi, anahtar; boş not gitmez', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'account': <String, dynamic>{'id': 1, 'name': 'Kasa', 'kind': 'cash', 'balance_minor': 100000},
      }, 201));
      final account = await api.createAccount(
        token: token,
        siteCode: 11,
        name: ' Kasa ',
        kind: CashAccountKind.cash,
        note: '  ',
        openingBalanceMinor: 100000,
        openingDate: DateTime(2026, 1, 1),
        idempotencyKey: 'a1',
      );
      expect(rec.body, <String, dynamic>{
        'name': 'Kasa',
        'kind': 'cash',
        'opening_balance_minor': 100000,
        'opening_date': '2026-01-01',
        'idempotency_key': 'a1',
      });
      expect(account.balanceMinor, 100000);
    });

    test('hareketler, düzeltme (işaretli tutar), aktarım ve iptali', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        final path = r.url.path;
        if (path.endsWith('/adjustments')) {
          return _json(<String, dynamic>{'movement': <String, dynamic>{'id': 5, 'kind': 'adjustment', 'amount_minor': -1500}}, 201);
        }
        if (path.endsWith('/transfers') && r.method == 'POST') {
          return _json(<String, dynamic>{
            'transfer': <String, dynamic>{'id': 3, 'amount_minor': 5000},
            'movements': <dynamic>[],
          }, 201);
        }
        if (path.endsWith('/void')) return _json(<String, dynamic>{'ok': true});
        if (path.endsWith('/movements')) {
          return _json(<String, dynamic>{'account': <String, dynamic>{'id': 1}, 'balance_minor': 0, 'items': <dynamic>[]});
        }
        return _json(<String, dynamic>{'items': <dynamic>[]});
      });
      await api.listMovements(token: token, siteCode: 11, accountId: 1, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31), limit: 20, beforeId: 9);
      expect(rec.last.url.path, '/manager/sites/11/finance/accounts/1/movements');
      expect(rec.last.url.queryParameters, <String, String>{'from': '2026-10-01', 'to': '2026-10-31', 'limit': '20', 'before_id': '9'});
      final movement = await api.adjustAccount(
        token: token,
        siteCode: 11,
        accountId: 1,
        amountMinor: -1500,
        movementDate: DateTime(2026, 10, 16),
        reason: AdjustmentReason.bankFee,
        note: '',
        idempotencyKey: 'adj1',
      );
      expect(rec.body, <String, dynamic>{
        'amount_minor': -1500,
        'movement_date': '2026-10-16',
        'reason_code': 'bank_fee',
        'idempotency_key': 'adj1',
      });
      expect(movement.amountMinor, -1500);
      await api.createTransfer(
        token: token,
        siteCode: 11,
        fromAccountId: 1,
        toAccountId: 2,
        amountMinor: 5000,
        transferDate: DateTime(2026, 10, 16),
        description: 'Bankaya yatırma',
        idempotencyKey: 't1',
      );
      expect(rec.last.url.path, '/manager/sites/11/finance/transfers');
      expect(rec.body, <String, dynamic>{
        'from_account_id': 1,
        'to_account_id': 2,
        'amount_minor': 5000,
        'transfer_date': '2026-10-16',
        'description': 'Bankaya yatırma',
        'idempotency_key': 't1',
      });
      await api.voidTransfer(token: token, siteCode: 11, transferId: 3, reason: 'Yanlış hesap', idempotencyKey: 't2');
      expect(rec.last.url.path, '/manager/sites/11/finance/transfers/3/void');
    });

    test('toplu eşleme önizleme + onay; mutabakat gövdesi (düzeltme isteğe bağlı)', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        final path = r.url.path;
        if (path.endsWith('/preview')) {
          return _json(<String, dynamic>{'count': 2, 'total_minor': 700, 'by_method': <dynamic>[], 'preview_hash': 'x'});
        }
        if (path.endsWith('/commit')) return _json(<String, dynamic>{'count': 2, 'total_minor': 700}, 201);
        return _json(<String, dynamic>{
          'reconciliation': <String, dynamic>{
            'id': 1,
            'statement_balance_minor': 100,
            'computed_balance_minor': 90,
            'difference_minor': 10,
          },
          'account_balance_minor': 100,
        }, 201);
      });
      final preview = await api.previewAssignPayments(token: token, siteCode: 11, accountByMethod: <String, int>{'cash': 1, 'transfer': 2});
      expect(rec.body, <String, dynamic>{'account_by_method': <String, int>{'cash': 1, 'transfer': 2}});
      expect(preview.previewHash, 'x');
      await api.commitAssignPayments(
        token: token,
        siteCode: 11,
        accountByMethod: <String, int>{'cash': 1},
        expectedCount: 2,
        expectedTotalMinor: 700,
        expectedHash: 'x',
        idempotencyKey: 'as1',
      );
      expect(rec.body['expected_count'], 2);
      expect(rec.body['expected_total_minor'], 700);
      expect(rec.body['expected_hash'], 'x');
      expect(rec.body['idempotency_key'], 'as1');
      final result = await api.reconcileAccount(
        token: token,
        siteCode: 11,
        accountId: 1,
        asOfDate: DateTime(2026, 10, 16),
        statementBalanceMinor: 100,
        expectedComputedMinor: 90,
        note: 'Ekstre ile',
        adjustReason: AdjustmentReason.cashCount,
        adjustNote: '',
        idempotencyKey: 'r1',
      );
      expect(rec.body, <String, dynamic>{
        'as_of_date': '2026-10-16',
        'statement_balance_minor': 100,
        'expected_computed_minor': 90,
        'note': 'Ekstre ile',
        'adjust': <String, dynamic>{'reason_code': 'cash_count'},
        'idempotency_key': 'r1',
      });
      expect(result.reconciliation.differenceMinor, 10);
      expect(result.accountBalanceMinor, 100);
    });

    test('hesap seçimli tahsilat: account_id gövdede, makbuz yanıtta', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'entry': <String, dynamic>{'id': 8, 'kind': 'payment', 'amount_minor': -50000},
        'balance_minor': 0,
        'receipt': <String, dynamic>{'id': 3, 'number': 'MK-2026-000001'},
        'movement_id': 4,
      }, 201));
      final result = await api.recordPayment(
        token: token,
        siteCode: 11,
        apartmentId: 301,
        amountMinor: 50000,
        entryDate: DateTime(2026, 10, 16),
        method: PaymentMethod.transfer,
        description: ' ',
        accountId: 2,
        idempotencyKey: 'pay-1',
      );
      expect(rec.last.url.path, '/manager/sites/11/finance/payments');
      expect(rec.body, <String, dynamic>{
        'apartment_id': 301,
        'amount_minor': 50000,
        'entry_date': '2026-10-16',
        'method': 'transfer',
        'account_id': 2,
        'idempotency_key': 'pay-1',
      });
      expect(result.receipt!.number, 'MK-2026-000001');
      expect(result.movementId, 4);
    });

    test('R13 P2-2: hesap seçimli düzeltme: aynı 4a ucu + account_id gövdede', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'entry': <String, dynamic>{'id': 9, 'kind': 'payment', 'amount_minor': -70000},
        'reversal': <String, dynamic>{'id': 10, 'kind': 'reversal', 'amount_minor': 50000},
        'balance_minor': 0,
        'movement_id': 6,
      }, 201));
      await api.correctPayment(
        token: token,
        siteCode: 11,
        entryId: 8,
        amountMinor: 70000,
        entryDate: DateTime(2026, 10, 16),
        method: PaymentMethod.cash,
        accountId: 1,
        idempotencyKey: 'cor-1',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/entries/8/correct');
      expect(rec.body, <String, dynamic>{
        'amount_minor': 70000,
        'entry_date': '2026-10-16',
        'method': 'cash',
        'account_id': 1,
        'idempotency_key': 'cor-1',
      });
    });

    test('tazminat işareti: record_empty YALNIZ true iken gövdede; beklenen 0/0 ve önizleme özeti gider', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'run': <String, dynamic>{'id': 40, 'period': '2026-09', 'status': 'active', 'total_minor': 0, 'apartment_count': 0, 'empty': true},
        'entries_count': 0,
      }, 201));
      final result = await api.postLateFee(
        token: token,
        siteCode: 11,
        period: FinancePeriod(2026, 9),
        expectedTotalMinor: 0,
        expectedApartmentCount: 0,
        expectedHash: 'abc',
        idempotencyKey: 'lf-1',
        recordEmpty: true,
      );
      expect(rec.last.url.path, '/manager/sites/11/finance/late-fee/post');
      expect(rec.body, <String, dynamic>{
        'period': '2026-09',
        'excluded_apartment_ids': <int>[],
        'expected_total_minor': 0,
        'expected_apartment_count': 0,
        'expected_hash': 'abc',
        'record_empty': true,
        'idempotency_key': 'lf-1',
      });
      expect(result.run.empty, isTrue);
      expect(result.entriesCount, 0);
      await api.postLateFee(
        token: token,
        siteCode: 11,
        period: FinancePeriod(2026, 9),
        expectedTotalMinor: 100,
        expectedApartmentCount: 1,
        expectedHash: 'abc',
        idempotencyKey: 'lf-2',
      );
      expect(rec.body.containsKey('record_empty'), isFalse, reason: 'normal çalıştırmada alan hiç gönderilmez');
    });

    test('ACCOUNT_INACTIVE: sunucunun kendi Türkçe iletisi önceliklidir (tek hesap pasif / TÜM hesaplar pasif ayrımı)', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'error': 'Tüm kasa ve banka hesapları pasif. Tahsilat girmek için önce bir hesabı yeniden etkinleştirin.',
        'code': 'ACCOUNT_INACTIVE',
      }, 409));
      await expectLater(
        api.recordPayment(
          token: token,
          siteCode: 11,
          apartmentId: 301,
          amountMinor: 100,
          entryDate: DateTime(2026, 10, 16),
          method: PaymentMethod.cash,
          idempotencyKey: 'pay-2',
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', startsWith('Tüm kasa ve banka hesapları pasif'))),
      );
    });
  });

  group('gider', () {
    test('createExpense: gövde + idempotency_key; DUPLICATE_EXPENSE mevcut gider kimliğini taşır', () async {
      final rec = _Rec();
      var duplicate = false;
      final api = _api(rec, (r) {
        if (duplicate) {
          return _json(<String, dynamic>{'error': 'x', 'code': 'DUPLICATE_EXPENSE', 'existing_expense_id': 41}, 409);
        }
        return _json(<String, dynamic>{
          'expense': <String, dynamic>{'id': 5, 'amount_minor': 250000, 'description': 'Asansör'},
          'movement': <String, dynamic>{'id': 9},
          'account_balance_minor': 750000,
        }, 201);
      });
      final input = ExpenseInput(
        categoryId: 3,
        description: 'Asansör',
        amountMinor: 250000,
        expenseDate: DateTime(2026, 10, 5),
        accountId: 1,
      );
      final result = await api.createExpense(token: token, siteCode: 11, input: input, idempotencyKey: 'e1');
      expect(rec.last.url.path, '/manager/sites/11/finance/expenses');
      expect(rec.body['idempotency_key'], 'e1');
      expect(rec.body['amount_minor'], 250000);
      expect(result.accountBalanceMinor, 750000);
      duplicate = true;
      try {
        await api.createExpense(token: token, siteCode: 11, input: input, idempotencyKey: 'e2');
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.code, 'DUPLICATE_EXPENSE');
        expect(existingExpenseIdOf(e.payload), 41);
      }
    });

    test('liste süzgeçleri, iptal ve düzeltme uçları', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        final path = r.url.path;
        if (path.endsWith('/correct')) {
          return _json(<String, dynamic>{
            'voided': <String, dynamic>{'id': 5, 'amount_minor': 1},
            'expense': <String, dynamic>{'id': 6, 'amount_minor': 2},
          }, 201);
        }
        if (path.endsWith('/void')) return _json(<String, dynamic>{'expense': <String, dynamic>{'id': 5, 'amount_minor': 1}});
        return _json(<String, dynamic>{'items': <dynamic>[]});
      });
      await api.listExpenses(
        token: token,
        siteCode: 11,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        categoryId: 3,
        supplierId: 8,
        accountId: 1,
        status: 'all',
        query: 'asansör',
        limit: 25,
        beforeId: 40,
      );
      expect(rec.last.url.queryParameters, <String, String>{
        'from': '2026-10-01',
        'to': '2026-10-31',
        'category_id': '3',
        'supplier_id': '8',
        'account_id': '1',
        'status': 'all',
        'q': 'asansör',
        'limit': '25',
        'before_id': '40',
      });
      await api.voidExpense(token: token, siteCode: 11, expenseId: 5, reason: ' çift kayıt ', idempotencyKey: 'v1');
      expect(rec.last.url.path, '/manager/sites/11/finance/expenses/5/void');
      expect(rec.body, <String, dynamic>{'reason': 'çift kayıt', 'idempotency_key': 'v1'});
      final corrected = await api.correctExpense(
        token: token,
        siteCode: 11,
        expenseId: 5,
        input: ExpenseInput(categoryId: 3, description: 'Düz', amountMinor: 200, expenseDate: DateTime(2026, 10, 5), accountId: 1),
        idempotencyKey: 'c1',
      );
      expect(rec.last.url.path, '/manager/sites/11/finance/expenses/5/correct');
      expect(corrected.expense.id, 6);
      expect(corrected.voided!.id, 5);
    });

    test('kategori ve tedarikçi uçları; boş alanlar gönderilmez', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/suppliers') && r.method == 'GET') return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
        if (r.url.path.endsWith('/suppliers')) return _json(<String, dynamic>{'supplier': <String, dynamic>{'id': 1, 'name': 'A'}}, 201);
        if (r.url.path.contains('/expense-categories')) {
          return _json(<String, dynamic>{'items': <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'name': 'Elektrik'}], 'category': <String, dynamic>{'id': 2, 'name': 'Yeni'}}, 201);
        }
        return _json(<String, dynamic>{});
      });
      final cats = await api.listExpenseCategories(token: token, siteCode: 11, active: true);
      expect(rec.last.url.queryParameters, <String, String>{'active': 'true'});
      expect(cats.single.name, 'Elektrik');
      final cat = await api.createExpenseCategory(token: token, siteCode: 11, name: ' Yeni ');
      expect(rec.body, <String, dynamic>{'name': 'Yeni'});
      expect(cat.id, 2);
      await api.listSuppliers(token: token, siteCode: 11, query: 'ener', active: true, limit: 10, offset: 5);
      expect(rec.last.url.queryParameters, <String, String>{'q': 'ener', 'active': 'true', 'limit': '10', 'offset': '5'});
      await api.createSupplier(token: token, siteCode: 11, name: ' A ', taxId: '', phone: ' 0555 ', note: null);
      expect(rec.body, <String, dynamic>{'name': 'A', 'phone': '0555'});
    });

    test('belge: önce üstveri, sonra ham PUT (octet-stream); göreli olmayan yol reddedilir', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.method == 'PUT') {
          return _json(<String, dynamic>{'document': <String, dynamic>{'id': 7, 'status': 'ready', 'display_name': 'fis.jpg', 'size_bytes': 3}});
        }
        return _json(<String, dynamic>{
          'document': <String, dynamic>{'id': 7, 'status': 'uploading'},
          'upload': <String, dynamic>{
            'method': 'PUT',
            'path': '/manager/sites/11/finance/expenses/5/documents/7/content',
            'content_type': 'application/octet-stream',
            'size': 3,
          },
        }, 201);
      });
      final ticket = await api.createExpenseDocument(
        token: token,
        siteCode: 11,
        expenseId: 5,
        fileName: 'fis.jpg',
        size: 3,
        contentType: 'image/jpeg',
        kind: ExpenseAttachmentKind.receipt,
        idempotencyKey: 'd1',
      );
      expect(rec.body, <String, dynamic>{
        'file': <String, dynamic>{'name': 'fis.jpg', 'size': 3, 'content_type': 'image/jpeg'},
        'kind': 'receipt',
        'idempotency_key': 'd1',
      });
      final done = await api.uploadExpenseDocument(token: token, ticket: ticket, bytes: Uint8List.fromList(<int>[1, 2, 3]));
      expect(rec.last.method, 'PUT');
      expect(rec.last.url.path, '/manager/sites/11/finance/expenses/5/documents/7/content');
      expect(rec.last.headers['Content-Type'], 'application/octet-stream');
      expect(rec.last.bodyBytes, <int>[1, 2, 3]);
      expect(done.isReady, isTrue);
      final evil = ExpenseUploadTicket(
        document: ticket.document,
        method: 'PUT',
        path: '//evil.example/x',
        contentType: 'application/octet-stream',
        size: 3,
      );
      await expectLater(
        api.uploadExpenseDocument(token: token, ticket: evil, bytes: Uint8List(3)),
        throwsA(isA<ApiException>()),
      );
      final dots = ExpenseUploadTicket(
        document: ticket.document,
        method: 'PUT',
        path: '/manager/../admin',
        contentType: 'application/octet-stream',
        size: 3,
      );
      await expectLater(api.uploadExpenseDocument(token: token, ticket: dots, bytes: Uint8List(3)), throwsA(isA<ApiException>()));
    });
  });

  group('raporlar ve dışa aktarma', () {
    test('rapor uçları ve süzgeç parametreleri', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'totals': <String, dynamic>{
          'not_due_minor': 0, 'd0_30_minor': 0, 'd31_60_minor': 0, 'd61_90_minor': 0,
          'd91_180_minor': 0, 'd181_365_minor': 0, 'd366_plus_minor': 0, 'total_overdue_minor': 0,
          'balance_minor': 0,
        },
        'items': <dynamic>[],
        'total_balance_minor': 0,
        'months': <dynamic>[],
      }));
      await api.getAgingReport(token: token, siteCode: 11, asOf: DateTime(2026, 10, 16), status: 'debtor', limit: 100, offset: 100);
      expect(rec.last.url.path, '/manager/sites/11/finance/reports/aging');
      expect(rec.last.url.queryParameters, <String, String>{'as_of': '2026-10-16', 'status': 'debtor', 'limit': '100', 'offset': '100'});
      await api.getIncomeExpenseReport(token: token, siteCode: 11, from: const FinancePeriod(2026, 1), to: const FinancePeriod(2026, 10));
      expect(rec.last.url.queryParameters, <String, String>{'from': '2026-01', 'to': '2026-10'});
      await api.getCashPositionReport(token: token, siteCode: 11);
      expect(rec.last.url.path, '/manager/sites/11/finance/reports/cash-position');
      expect(rec.last.url.queryParameters, isEmpty);
      await api.getBoardSummary(token: token, siteCode: 11, from: const FinancePeriod(2026, 1), to: const FinancePeriod(2026, 12));
      expect(rec.last.url.queryParameters['include_debtor_list'], 'false');
      await api.getBoardSummary(token: token, siteCode: 11, from: const FinancePeriod(2026, 1), to: const FinancePeriod(2026, 12), includeDebtorList: true);
      expect(rec.last.url.queryParameters['include_debtor_list'], 'true');
    });

    test('dışa aktarma zarfı finance/exports/:kind yolundan ve zarf olarak ayrıştırılır', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'kind': 'finance_aging',
        'spec_version': 1,
        'generated_at': '2026-10-16T09:00:00Z',
        'filename_base': 'yaslandirma_gul-sitesi_20261016',
        'columns': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'label', 'label': 'Daire', 'type': 'text'},
          <String, dynamic>{'key': 'overdue', 'label': 'Gecikmiş', 'type': 'money'},
        ],
        'rows': <List<Object?>>[
          <Object?>['A Blok - 5', 12345],
        ],
        'row_count': 1,
      }));
      final envelope = await api.getExport(token: token, siteCode: 11, kind: 'finance_aging', query: <String, String>{'as_of': '2026-10-16'});
      expect(rec.last.url.path, '/manager/sites/11/finance/exports/finance_aging');
      expect(rec.last.url.queryParameters, <String, String>{'as_of': '2026-10-16'});
      expect(envelope.rowCount, 1);
      expect(envelope.rows.single[1], 12345);
    });

    test('rapor ağır istek: 5xx bütün yanıtı hataya çevirir, kısmi sıfır dönmez', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'iç hata', 'errorId': 'abc123'}, 500));
      try {
        await api.getAgingReport(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.isServerError, isTrue);
        expect(e.message, contains('abc123'));
      }
    });
  });

  group('hatırlatma', () {
    test('muafiyet ekle (PUT) / kaldır (DELETE); önizleme gövdesi ton; gönder gövdesi', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        final path = r.url.path;
        if (path.endsWith('/reminders/preview')) {
          return _json(<String, dynamic>{'apartment_count': 1, 'person_count': 1, 'preview_hash': 'h'});
        }
        if (path.endsWith('/reminders/send')) {
          return _json(<String, dynamic>{'run': <String, dynamic>{'id': 3, 'status': 'active', 'tone': 'standard'}}, 201);
        }
        return _json(<String, dynamic>{});
      });
      await api.addReminderExclusion(token: token, siteCode: 11, apartmentId: 301, reason: ' Dava ');
      expect(rec.last.method, 'PUT');
      expect(rec.last.url.path, '/manager/sites/11/finance/reminders/exclusions/301');
      expect(rec.body, <String, dynamic>{'reason': 'Dava'});
      await api.removeReminderExclusion(token: token, siteCode: 11, apartmentId: 301);
      expect(rec.last.method, 'DELETE');
      final preview = await api.previewReminders(token: token, siteCode: 11, tone: ReminderTone.standard);
      expect(rec.body, <String, dynamic>{'tone': 'standard'});
      expect(preview.previewHash, 'h');
      final sent = await api.sendReminders(
        token: token,
        siteCode: 11,
        tone: ReminderTone.standard,
        note: ' Lütfen ',
        expectedHash: 'h',
        expectedApartmentCount: 1,
        expectedPersonCount: 1,
        idempotencyKey: 'rem-1',
      );
      expect(rec.body, <String, dynamic>{
        'tone': 'standard',
        'note': 'Lütfen',
        'expected_hash': 'h',
        'expected_apartment_count': 1,
        'expected_person_count': 1,
        'idempotency_key': 'rem-1',
      });
      expect(sent.created, isTrue);
      expect(sent.run.tone, ReminderTone.standard);
    });

    test('çalıştırma listesi ve iptal', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/cancel')) {
          return _json(<String, dynamic>{'run': <String, dynamic>{'id': 3, 'status': 'cancelled'}});
        }
        return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
      });
      await api.listReminderRuns(token: token, siteCode: 11, limit: 5, offset: 10);
      expect(rec.last.url.queryParameters, <String, String>{'limit': '5', 'offset': '10'});
      final run = await api.cancelReminderRun(token: token, siteCode: 11, runId: 3, idempotencyKey: 'c1');
      expect(rec.last.url.path, '/manager/sites/11/finance/reminders/runs/3/cancel');
      expect(run.isCancelled, isTrue);
    });
  });
}
