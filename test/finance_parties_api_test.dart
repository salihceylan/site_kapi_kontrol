// İki hesap (İP-1A, karar G12): istemci uçları `account_party` alanını yalnız SEÇİLDİYSE gönderir (seçilmezse eski istek
// birebir aynıdır; sunucu varsayılanı uygular). MockClient ile yol, gövde ve sorgu parametreleri denetlenir. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
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

AuthApi _authApi(_Rec rec, FutureOr<http.Response> Function(http.Request request) handler) => AuthApi(
  baseUrl: 'https://api.example.test',
  client: MockClient((request) async {
    rec.requests.add(request);
    return handler(request);
  }),
  retryDelay: Duration.zero,
);

Finance4bApi _f4Api(_Rec rec, FutureOr<http.Response> Function(http.Request request) handler) => Finance4bApi(
  baseUrl: 'https://api.example.test/',
  client: MockClient((request) async {
    rec.requests.add(request);
    return handler(request);
  }),
);

Map<String, dynamic> _payment({String? account}) => <String, dynamic>{
  'id': 5,
  'kind': 'payment',
  'amount_minor': -5000,
  'period': '2026-10',
  'entry_date': '2026-10-21',
  'method': 'cash',
  'payer_party': 'both',
  'account_party': ?account,
};

Map<String, dynamic> _statement() => <String, dynamic>{
  'apartment': <String, dynamic>{'id': 301},
  'opening_balance_minor': 0,
  'closing_balance_minor': 0,
  'items': <dynamic>[],
  'totals': <String, dynamic>{'charged_minor': 0, 'paid_minor': 0, 'reversed_minor': 0},
  'account_party': 'tenant',
  'role': 'read_only',
};

Map<String, dynamic> _aging() => <String, dynamic>{
  'totals': <String, dynamic>{'not_due_minor': 0, 'd0_30_minor': 0, 'd31_60_minor': 0, 'd61_90_minor': 0, 'd91_180_minor': 0, 'd181_365_minor': 0, 'd366_plus_minor': 0, 'credit_minor': 0, 'total_overdue_minor': 0},
  'items': <dynamic>[],
  'total': 0,
  'account_party': 'owner',
};

void main() {
  group('AuthApi (4a uçları)', () {
    test('ekstre: ?account_party= yalnız hesap seçilince; seçilmezse eski sorgu', () async {
      final rec = _Rec();
      final api = _authApi(rec, (r) => _json(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 301},
        'balance_minor': 168000,
        'items': <dynamic>[],
        'account_party': 'tenant',
        'accounts': <String, dynamic>{
          'owner': <String, dynamic>{'balance_minor': -10000},
          'tenant': <String, dynamic>{'balance_minor': 168000},
        },
        'show_tenant_account': true,
        'default_payment_account': 'tenant',
      }));
      final view = await api.getFinanceAccount(token: 'tok', siteCode: 7, apartmentId: 301, accountParty: AccountParty.tenant);
      expect(rec.last.url.path, '/manager/sites/7/finance/apartments/301/account');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50', 'account_party': 'tenant'});
      expect(view.accountParty, AccountParty.tenant);
      expect(view.hasTwoAccounts, isTrue);
      await api.getFinanceAccount(token: 'tok', siteCode: 7, apartmentId: 301);
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50'});
    });

    test('tahsilat: account_party yalnız seçilince gövdede; yanıtta hesap bakiyesi', () async {
      final rec = _Rec();
      final api = _authApi(rec, (r) => _json(<String, dynamic>{'entry': _payment(account: 'owner'), 'balance_minor': 100, 'account_balance_minor': -50}, 201));
      final result = await api.recordFeePayment(
        token: 'tok',
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.cash,
        idempotencyKey: 'pay-1',
        accountParty: AccountParty.owner,
      );
      expect(rec.body['account_party'], 'owner');
      expect(result.accountBalanceMinor, -50);
      expect(result.entry.accountParty, AccountParty.owner);
      await api.recordFeePayment(
        token: 'tok',
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.cash,
        idempotencyKey: 'pay-2',
      );
      expect(rec.body.containsKey('account_party'), isFalse, reason: 'eski istemci isteği aynı kalır; sunucu varsayılanı seçer');
    });

    test('düzeltme: account_party ile hesap değiştirilir; verilmezse alan yok (asılın hesabı korunur)', () async {
      final rec = _Rec();
      final api = _authApi(rec, (r) => _json(<String, dynamic>{
        'reversal': <String, dynamic>{..._payment(account: 'owner'), 'id': 6, 'kind': 'reversal', 'amount_minor': 5000, 'reverses_entry_id': 5},
        'entry': <String, dynamic>{..._payment(account: 'tenant'), 'id': 7},
        'balance_minor': 0,
        'account_balance_minor': -5000,
      }, 201));
      final result = await api.correctFinancePayment(
        token: 'tok',
        siteCode: 7,
        entryId: 5,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.cash,
        idempotencyKey: 'cor-1',
        accountParty: AccountParty.tenant,
      );
      expect(rec.last.url.path, '/manager/sites/7/finance/entries/5/correct');
      expect(rec.body['account_party'], 'tenant');
      expect(result.reversal!.accountParty, AccountParty.owner);
      expect(result.entry.accountParty, AccountParty.tenant);
      await api.correctFinancePayment(
        token: 'tok',
        siteCode: 7,
        entryId: 5,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.cash,
        idempotencyKey: 'cor-2',
      );
      expect(rec.body.containsKey('account_party'), isFalse);
    });
  });

  group('Finance4bApi', () {
    const token = 'tok';

    test('hesap seçimli tahsilat ve düzeltme: account_party gövdede', () async {
      final rec = _Rec();
      final api = _f4Api(rec, (r) => _json(<String, dynamic>{'entry': _payment(account: 'tenant'), 'balance_minor': 0}, 201));
      await api.recordPayment(
        token: token,
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.transfer,
        accountId: 2,
        idempotencyKey: 'k1',
        accountParty: AccountParty.tenant,
      );
      expect(rec.body['account_party'], 'tenant');
      expect(rec.body['account_id'], 2);
      await api.correctPayment(
        token: token,
        siteCode: 7,
        entryId: 5,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.transfer,
        idempotencyKey: 'k2',
        accountParty: AccountParty.owner,
      );
      expect(rec.body['account_party'], 'owner');
      await api.recordPayment(
        token: token,
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 21),
        method: PaymentMethod.transfer,
        idempotencyKey: 'k3',
      );
      expect(rec.body.containsKey('account_party'), isFalse);
    });

    test('sakin ekstresi ve makbuzları: ?account_party= (salt okunur görünüm); verilmezse kendi hesabı', () async {
      final rec = _Rec();
      final api = _f4Api(rec, (r) => r.url.path.endsWith('/receipts') ? _json(<String, dynamic>{'items': <dynamic>[]}) : _json(_statement()));
      final statement = await api.getMyStatement(token: token, apartmentId: 301, accountParty: AccountParty.tenant);
      expect(rec.last.url.path, '/app/my-finance/apartments/301/statement');
      expect(rec.last.url.queryParameters['account_party'], 'tenant');
      expect(statement.readOnly, isTrue);
      await api.getMyStatement(token: token, apartmentId: 301);
      expect(rec.last.url.queryParameters.containsKey('account_party'), isFalse);
      await api.listMyReceipts(token: token, accountParty: AccountParty.owner);
      expect(rec.last.url.path, '/app/my-finance/receipts');
      expect(rec.last.url.queryParameters['account_party'], 'owner');
      await api.listMyReceipts(token: token);
      expect(rec.last.url.queryParameters.containsKey('account_party'), isFalse);
    });

    test('yaşlandırma ve yönetici ekstresi: hesap süzgeci sorguda', () async {
      final rec = _Rec();
      final api = _f4Api(rec, (r) => r.url.path.endsWith('/aging') ? _json(_aging()) : _json(_statement()));
      final aging = await api.getAgingReport(token: token, siteCode: 7, accountParty: AccountParty.owner);
      expect(rec.last.url.path, '/manager/sites/7/finance/reports/aging');
      expect(rec.last.url.queryParameters['account_party'], 'owner');
      expect(aging.accountParty, AccountParty.owner);
      await api.getAgingReport(token: token, siteCode: 7);
      expect(rec.last.url.queryParameters.containsKey('account_party'), isFalse);
      await api.getApartmentStatement(token: token, siteCode: 7, apartmentId: 301, accountParty: AccountParty.tenant);
      expect(rec.last.url.path, '/manager/sites/7/finance/apartments/301/statement');
      expect(rec.last.url.queryParameters['account_party'], 'tenant');
      await api.getApartmentStatement(token: token, siteCode: 7, apartmentId: 301);
      expect(rec.last.url.queryParameters.containsKey('account_party'), isFalse);
    });
  });
}
