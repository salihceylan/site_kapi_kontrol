// İki kasa (docs/PLATFORM_FINANS_KASALAR.md): model ayrıştırma, ad sabitleri ve uç sözleşmeleri.
//
// Kasalar: `operating` = "İşletme Projesi (Aidat) Hesabı", `capital` = "Yatırım ve Demirbaş (Fon) Hesabı". Tutarlar
// KURUŞ tamsayıdır. Eski sunucu `fund` / `funds` / `fund_split` göndermez: modeller null alır, çökmez. MockClient ile uç
// yolları, gövdeler (yalnız verilen `fund` gider), sorgu parametreleri, 200/201 ayrımı ve hata kodu -> Türkçe eşlemeleri.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/fund_text.dart';

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

Finance4bApi _api(_Rec rec, FutureOr<http.Response> Function(http.Request request) handler) => Finance4bApi(
  baseUrl: 'https://api.example.test/',
  client: MockClient((request) async {
    rec.requests.add(request);
    return handler(request);
  }),
);

AuthApi _authApi(_Rec rec, FutureOr<http.Response> Function(http.Request request) handler) => AuthApi(
  baseUrl: 'https://api.example.test',
  client: MockClient((request) async {
    rec.requests.add(request);
    return handler(request);
  }),
  retryDelay: Duration.zero,
);

Map<String, dynamic> _fundJson(String fund, {int opening = 100000, int balance = 250000, bool negative = false}) => <String, dynamic>{
  'fund': fund,
  'fund_label': fund == 'operating' ? 'İşletme Projesi (Aidat) Hesabı' : 'Yatırım ve Demirbaş (Fon) Hesabı',
  'fund_short_label': fund == 'operating' ? 'Aidat Hesabı' : 'Fon Hesabı',
  'opening_minor': opening,
  'collections_minor': 200000,
  'expenses_minor': 50000,
  'transfers_in_minor': 10000,
  'transfers_out_minor': 5000,
  'adjustments_minor': -5000,
  'balance_minor': balance,
  'negative_balance': negative,
};

Map<String, dynamic> _summaryJson() => <String, dynamic>{
  'currency': 'TRY',
  'from': '2026-10-01',
  'to': '2026-10-16',
  'has_accounts': true,
  'funds': <String, dynamic>{'operating': _fundJson('operating'), 'capital': _fundJson('capital', balance: -1200, negative: true)},
  'advance_minor': 25000,
  'accounts_total_minor': 273800,
  'difference_minor': 0,
  'balanced': true,
  'unassigned_payments': <String, dynamic>{'count': 2, 'total_minor': 90000},
};

Map<String, dynamic> _transferJson({int id = 9, int? reverses, int? reversedBy, String? reason}) => <String, dynamic>{
  'id': id,
  'from_fund': 'operating',
  'to_fund': 'capital',
  'amount_minor': 150000,
  'transfer_date': '2026-10-16',
  'period': '2026-10',
  'description': 'Kurul kararı',
  'reverses_transfer_id': reverses,
  'reversed_by_transfer_id': reversedBy,
  'reversal_reason': reason,
  'created_by_name': 'Site Yöneticisi',
  'created_at': '2026-10-16T09:00:00Z',
};

Map<String, dynamic> _entryJson({String kind = 'payment', int amount = -200000, Map<String, dynamic>? extra}) => <String, dynamic>{
  'id': 5,
  'kind': kind,
  'amount_minor': amount,
  'period': '2026-10',
  'entry_date': '2026-10-05',
  'due_date': null,
  'method': 'cash',
  ...?extra,
};

void main() {
  const token = 'tok';

  group('ad sabitleri (tek yer): kasalar TAM adlarla anılır', () {
    test('tam ve kısa adlar; seçim satırı metni', () {
      expect(kFundOperatingName, 'İşletme Projesi (Aidat) Hesabı');
      expect(kFundCapitalName, 'Yatırım ve Demirbaş (Fon) Hesabı');
      expect(kFundOperatingShortName, 'Aidat Hesabı');
      expect(kFundCapitalShortName, 'Fon Hesabı');
      expect(kFundAutoName, 'Otomatik (en eski vade önce)');
      expect(FinanceFund.operating.label, kFundOperatingName);
      expect(FinanceFund.capital.label, kFundCapitalName);
      expect(FinanceFund.operating.shortLabel, kFundOperatingShortName);
      expect(FinanceFund.capital.shortLabel, kFundCapitalShortName);
      expect(FinanceFund.operating.choiceText, 'İşletme Projesi (Aidat) Hesabı — dairede oturan öder (kiracı varsa kiracı)');
      expect(FinanceFund.capital.choiceText, 'Yatırım ve Demirbaş (Fon) Hesabı — malik öder');
    });

    test('tryParse: yalnız operating / capital; bilinmeyen null; "kim öder"den türetme', () {
      expect(FinanceFund.tryParse('operating'), FinanceFund.operating);
      expect(FinanceFund.tryParse(' Capital '), FinanceFund.capital);
      expect(FinanceFund.tryParse('tenant'), isNull);
      expect(FinanceFund.tryParse(null), isNull);
      expect(FinanceFund.tryParse(3), isNull);
      expect(ChargeParty.occupant.fund, FinanceFund.operating);
      expect(ChargeParty.owner.fund, FinanceFund.capital);
    });

    test('fundSplitText: kısa adlar + avans (tutarlar kuruştan biçimlenir)', () {
      const split = FundSplit(operatingMinor: 150000, capitalMinor: 50000, advanceMinor: 0);
      expect(fundSplitText(split), 'Aidat Hesabı 1.500,00 ₺, Fon Hesabı 500,00 ₺, avans 0,00 ₺');
      expect(split.totalMinor, 200000);
      expect(split.of(FinanceFund.capital), 50000);
    });
  });

  group('çekirdek ayrıştırma', () {
    test('FundSplit: üç alan da okunabilirse dağılım; eksik / bozuksa null (uydurma 0 yok)', () {
      final ok = FundSplit.tryParse(<String, dynamic>{'operating_minor': 150000, 'capital_minor': '50000', 'advance_minor': 0});
      expect(ok, const FundSplit(operatingMinor: 150000, capitalMinor: 50000, advanceMinor: 0));
      expect(FundSplit.tryParse(<String, dynamic>{'operating_minor': 1, 'capital_minor': 2}), isNull);
      expect(FundSplit.tryParse(<String, dynamic>{'operating_minor': 1.5, 'capital_minor': 2, 'advance_minor': 0}), isNull);
      expect(FundSplit.tryParse('x'), isNull);
      expect(FundSplit.tryParse(null), isNull);
    });

    test('FundBreakdown: iki kasa; sıfır kasa isZero; eksik / bozuk null', () {
      final ok = FundBreakdown.tryParse(<String, dynamic>{
        'operating': <String, dynamic>{'balance_minor': 150000, 'overdue_minor': 50000, 'advance_minor': 0},
        'capital': <String, dynamic>{'balance_minor': 0, 'overdue_minor': 0, 'advance_minor': 0},
      });
      expect(ok, isNotNull);
      expect(ok!.of(FinanceFund.operating).balanceMinor, 150000);
      expect(ok.of(FinanceFund.operating).overdueMinor, 50000);
      expect(ok.of(FinanceFund.capital).isZero, isTrue);
      expect(ok.of(FinanceFund.operating).isZero, isFalse);
      // vadesi geçen / avans alanı yoksa 0 sayılır (eski biçim); bakiye yoksa kırılım yok
      final lean = FundBreakdown.tryParse(<String, dynamic>{
        'operating': <String, dynamic>{'balance_minor': 100},
        'capital': <String, dynamic>{'balance_minor': 0},
      });
      expect(lean!.operating.overdueMinor, 0);
      expect(FundBreakdown.tryParse(<String, dynamic>{'operating': <String, dynamic>{'balance_minor': 100}}), isNull);
      expect(
        FundBreakdown.tryParse(<String, dynamic>{
          'operating': <String, dynamic>{'balance_minor': 'x'},
          'capital': <String, dynamic>{'balance_minor': 0},
        }),
        isNull,
      );
      expect(FundBreakdown.tryParse(null), isNull);
    });
  });

  group('mevcut modellerde kasa alanları', () {
    test('FeeDefinition: fund okunur; eski sunucuda "kim öder"den türer', () {
      final withFund = FeeDefinition.fromJson(<String, dynamic>{'id': 1, 'kind': 'recurring', 'distribution': 'fixed', 'fund': 'capital', 'charge_party': 'owner'});
      expect(withFund.fund, FinanceFund.capital);
      expect(withFund.effectiveFund, FinanceFund.capital);
      final oldRecurring = FeeDefinition.fromJson(<String, dynamic>{'id': 2, 'kind': 'recurring', 'distribution': 'fixed'});
      expect(oldRecurring.fund, isNull);
      expect(oldRecurring.effectiveFund, FinanceFund.operating, reason: 'aylık aidat: dairede oturan öder');
      final oldOneTime = FeeDefinition.fromJson(<String, dynamic>{'id': 3, 'kind': 'one_time', 'distribution': 'fixed'});
      expect(oldOneTime.effectiveFund, FinanceFund.capital, reason: 'tek seferlik: malik öder');
      final oldOwner = FeeDefinition.fromJson(<String, dynamic>{'id': 4, 'kind': 'recurring', 'distribution': 'fixed', 'charge_party': 'owner'});
      expect(oldOwner.effectiveFund, FinanceFund.capital, reason: 'charge_party=owner => Fon Hesabı');
    });

    test('tanım ve ek borç gövdesi: yalnız verilen fund gider (charge_party kendiliğinden eklenmez)', () {
      final now = FinancePeriod(2026, 10);
      final input = FeeDefinitionInput(
        name: 'Asansör',
        kind: FeeKind.oneTime,
        distribution: FeeDistribution.equal,
        startPeriod: now,
        amountMinor: 5000,
        fund: FinanceFund.capital,
      );
      expect(input.toJson()['fund'], 'capital');
      expect(input.toJson().containsKey('charge_party'), isFalse);
      final none = FeeDefinitionInput(name: 'A', kind: FeeKind.recurring, distribution: FeeDistribution.equal, startPeriod: now, amountMinor: 1);
      expect(none.toJson().containsKey('fund'), isFalse);
      const charge = ExtraChargeInput(name: 'Çatı', distribution: FeeDistribution.equal, amountMinor: 3000, fund: FinanceFund.operating);
      expect(charge.toJson()['fund'], 'operating');
      expect(const ExtraChargeInput(name: 'Çatı', distribution: FeeDistribution.equal, amountMinor: 3000).toJson().containsKey('fund'), isFalse);
    });

    test('LedgerEntry: fund (kısıt) ve fund_split; yanıtta fund_split üstte ya da satırda', () {
      final entry = LedgerEntry.fromJson(_entryJson(extra: <String, dynamic>{
        'fund': 'operating',
        'fund_split': <String, dynamic>{'operating_minor': 150000, 'capital_minor': 50000, 'advance_minor': 0},
      }));
      expect(entry.fund, FinanceFund.operating);
      expect(entry.fundSplit, const FundSplit(operatingMinor: 150000, capitalMinor: 50000, advanceMinor: 0));
      final old = LedgerEntry.fromJson(_entryJson());
      expect(old.fund, isNull);
      expect(old.fundSplit, isNull);
      final top = LedgerWriteResult.fromJson(<String, dynamic>{
        'entry': _entryJson(extra: <String, dynamic>{'fund': null}),
        'balance_minor': 0,
        'fund_split': <String, dynamic>{'operating_minor': 100, 'capital_minor': 0, 'advance_minor': 25},
      });
      expect(top.entry.fund, isNull, reason: 'kısıtsız = otomatik');
      expect(top.fundSplit, const FundSplit(operatingMinor: 100, capitalMinor: 0, advanceMinor: 25));
      final noSplit = LedgerWriteResult.fromJson(<String, dynamic>{'entry': _entryJson(), 'balance_minor': 0});
      expect(noSplit.fundSplit, isNull);
    });

    test('AccountView: kasa kırılımı ve toplam avans; eski sunucuda null', () {
      final view = AccountView.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5'},
        'balance_minor': 100000,
        'items': <dynamic>[],
        'funds': <String, dynamic>{
          'operating': <String, dynamic>{'balance_minor': 150000, 'overdue_minor': 50000, 'advance_minor': 0},
          'capital': <String, dynamic>{'balance_minor': 0, 'overdue_minor': 0, 'advance_minor': 50000},
        },
        'advance_minor': 50000,
      });
      expect(view.funds!.operating.balanceMinor, 150000);
      expect(view.funds!.capital.advanceMinor, 50000);
      expect(view.advanceMinor, 50000);
      final old = AccountView.fromJson(<String, dynamic>{'apartment': <String, dynamic>{'id': 301}, 'balance_minor': 0});
      expect(old.funds, isNull);
      expect(old.advanceMinor, isNull);
    });

    test('Borcum: öğede ve hesap görünümünde funds + advance_minor; kendi hesabı üst düzeyden', () {
      final funds = <String, dynamic>{
        'operating': <String, dynamic>{'balance_minor': 150000, 'overdue_minor': 0, 'advance_minor': 0},
        'capital': <String, dynamic>{'balance_minor': 0, 'overdue_minor': 0, 'advance_minor': 0},
      };
      final item = MyFinanceApartment.fromJson(<String, dynamic>{
        'site_code': 11,
        'apartment_id': 301,
        'balance_minor': 150000,
        'funds': funds,
        'advance_minor': 0,
        'accounts': <dynamic>[
          <String, dynamic>{'account_party': 'tenant', 'role': 'own', 'balance_minor': 150000, 'funds': funds, 'advance_minor': 0},
        ],
      });
      expect(item.funds!.operating.balanceMinor, 150000);
      expect(item.ownAccount.funds, same(item.funds));
      expect(item.accounts.single.funds!.capital.isZero, isTrue);
      final old = MyFinanceApartment.fromJson(<String, dynamic>{'site_code': 11, 'apartment_id': 301, 'balance_minor': 0});
      expect(old.funds, isNull);
    });

    test('Gider ve kategori: fund okunur; ExpenseInput gövdesine yalnız verilirse girer', () {
      final category = ExpenseCategory.fromJson(<String, dynamic>{'id': 1, 'name': 'Yatırım ve demirbaş', 'is_system': true, 'fund': 'capital'});
      expect(category.fund, FinanceFund.capital);
      expect(ExpenseCategory.fromJson(<String, dynamic>{'id': 2, 'name': 'Elektrik'}).effectiveFund, FinanceFund.operating, reason: 'eski sunucu');
      final expense = Expense.fromJson(<String, dynamic>{'id': 3, 'amount_minor': 1000, 'fund': 'capital'});
      expect(expense.fund, FinanceFund.capital);
      expect(Expense.fromJson(<String, dynamic>{'id': 4, 'amount_minor': 1000}).fund, isNull);
      final input = ExpenseInput(
        categoryId: 1,
        description: 'Asansör',
        amountMinor: 1000,
        expenseDate: DateTime(2026, 10, 5),
        accountId: 2,
        fund: FinanceFund.capital,
      );
      expect(input.toJson()['fund'], 'capital');
      expect(
        ExpenseInput(categoryId: 1, description: 'x', amountMinor: 1, expenseDate: DateTime(2026, 10, 5), accountId: 2).toJson().containsKey('fund'),
        isFalse,
      );
    });

    test('Makbuz: snapshot.fund_split okunur; 080 öncesi makbuzda null', () {
      final json = <String, dynamic>{
        'id': 9,
        'status': 'active',
        'snapshot': <String, dynamic>{
          'number': 'MK-2026-000123',
          'kind': 'collection',
          'amount_minor': 200000,
          'fund_split': <String, dynamic>{'operating_minor': 150000, 'capital_minor': 50000, 'advance_minor': 0},
        },
      };
      expect(Receipt.fromJson(json).fundSplit, const FundSplit(operatingMinor: 150000, capitalMinor: 50000, advanceMinor: 0));
      final old = <String, dynamic>{
        'id': 9,
        'snapshot': <String, dynamic>{'number': 'MK-2026-000123', 'amount_minor': 100},
      };
      expect(Receipt.fromJson(old).fundSplit, isNull);
    });

    test('denetim eylemleri Türkçe başlıkla eşli', () {
      expect(financeActionLabel('finance.fund_transfer.created'), 'Kasalar arası aktarım yapıldı');
      expect(financeActionLabel('finance.fund_transfer.reversed'), 'Kasalar arası aktarım ters çevrildi');
    });
  });

  group('kasa özeti, döküm ve aktarım modelleri', () {
    test('FundSummary: iki kasa, avans, fark, eşlenmemiş tahsilat; eksi bakiye işareti', () {
      final summary = FundSummary.fromJson(_summaryJson());
      expect(summary.operating.balanceMinor, 250000);
      expect(summary.operating.isNegative, isFalse);
      expect(summary.capital.balanceMinor, -1200);
      expect(summary.capital.isNegative, isTrue);
      expect(summary.of(FinanceFund.capital), same(summary.capital));
      expect(summary.advanceMinor, 25000);
      expect(summary.balanced, isTrue);
      expect(summary.differenceMinor, 0);
      expect(summary.unassigned.count, 2);
      expect(summary.unassigned.totalMinor, 90000);
      expect(summary.hasAccounts, isTrue);
      expect(summary.from, DateTime(2026, 10, 1));
      expect(summary.operating.transfersInMinor, 10000);
      expect(summary.operating.adjustmentsMinor, -5000);
    });

    test('FundSummary: bozuk tutar / eksik kasa FormatException (sessiz 0 yok)', () {
      final bad = _summaryJson();
      ((bad['funds'] as Map)['operating'] as Map)['balance_minor'] = 'x';
      expect(() => FundSummary.fromJson(bad), throwsFormatException);
      final missing = _summaryJson();
      (missing['funds'] as Map).remove('capital');
      expect(() => FundSummary.fromJson(missing), throwsFormatException);
    });

    test('FundSummary: dengesiz özet balanced=false ve fark', () {
      final json = _summaryJson()
        ..['balanced'] = false
        ..['difference_minor'] = 4500;
      final summary = FundSummary.fromJson(json);
      expect(summary.balanced, isFalse);
      expect(summary.differenceMinor, 4500);
    });

    test('FundMovementPage: türler, işaretli tutar, daire etiketi (kişi adı yok), sayfa alanları', () {
      final page = FundMovementPage.fromJson(<String, dynamic>{
        'fund': 'capital',
        'balance_minor': 99000,
        'total': 3,
        'limit': 2,
        'offset': 0,
        'items': <dynamic>[
          <String, dynamic>{'key': 'collection:7', 'type': 'collection', 'date': '2026-10-05', 'amount_minor': 50000, 'label': 'Çatı katkı payı', 'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5'}, 'account': null, 'category': null, 'ref_id': 7},
          <String, dynamic>{'key': 'expense:3', 'type': 'expense', 'date': '2026-10-04', 'amount_minor': -20000, 'label': 'Asansör', 'apartment': null, 'account': null, 'category': 'Yatırım ve demirbaş', 'ref_id': 3},
          <String, dynamic>{'key': 'x:1', 'type': 'tuhaf', 'date': '2026-10-01', 'amount_minor': 1, 'label': null, 'apartment': null, 'account': <String, dynamic>{'id': 2, 'name': 'Ziraat'}, 'category': null, 'ref_id': null},
        ],
      }, FinanceFund.capital);
      expect(page.fund, FinanceFund.capital);
      expect(page.total, 3);
      expect(page.items[0].type, FundMovementType.collection);
      expect(page.items[0].apartmentLabel, 'A Blok - 5');
      expect(page.items[1].type, FundMovementType.expense);
      expect(page.items[1].amountMinor, -20000);
      expect(page.items[1].category, 'Yatırım ve demirbaş');
      expect(page.items[2].type, FundMovementType.unknown);
      expect(page.items[2].accountName, 'Ziraat');
    });

    test('FundTransfer: yön, tutar, ters çevirme durumu; ters aktarım tekrar ters çevrilemez', () {
      final original = FundTransfer.fromJson(_transferJson());
      expect(original.fromFund, FinanceFund.operating);
      expect(original.toFund, FinanceFund.capital);
      expect(original.amountMinor, 150000);
      expect(original.period, FinancePeriod(2026, 10));
      expect(original.canReverse, isTrue);
      final reversed = FundTransfer.fromJson(_transferJson(reversedBy: 10));
      expect(reversed.isReversed, isTrue);
      expect(reversed.canReverse, isFalse);
      final reversal = FundTransfer.fromJson(_transferJson(id: 10, reverses: 9, reason: 'Yanlış tutar'));
      expect(reversal.isReversal, isTrue);
      expect(reversal.reversalReason, 'Yanlış tutar');
      expect(reversal.canReverse, isFalse);
      final bad = _transferJson()..['from_fund'] = 'tenant';
      expect(() => FundTransfer.fromJson(bad), throwsFormatException);
      final result = FundTransferReverseResult.fromJson(<String, dynamic>{
        'transfer': _transferJson(id: 10, reverses: 9, reason: 'x'),
        'original': _transferJson(reversedBy: 10),
      });
      expect(result.transfer.isReversal, isTrue);
      expect(result.original!.isReversed, isTrue);
    });
  });

  group('Finance4bApi: kasa uçları', () {
    test('getFundSummary: GET …/finance/funds; from / to yalnız verilirse sorguya girer', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(_summaryJson()));
      final summary = await api.getFundSummary(token: token, siteCode: 11, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16));
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/11/finance/funds');
      expect(rec.last.url.queryParameters, <String, String>{'from': '2026-10-01', 'to': '2026-10-16'});
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(summary.advanceMinor, 25000);
      await api.getFundSummary(token: token, siteCode: 11);
      expect(rec.last.url.queryParameters, isEmpty);
    });

    test('getFundSummary: bozuk gövde ApiException ("işlenemedi"); REPORT_BUSY Retry-After ile beklemeye yönlendirir', () async {
      final bad = _api(_Rec(), (r) => _json(<String, dynamic>{'funds': <String, dynamic>{}}));
      await expectLater(bad.getFundSummary(token: token, siteCode: 11), throwsA(isA<ApiException>()));
      final busy = _api(_Rec(), (r) => http.Response(jsonEncode(<String, dynamic>{'error': 'busy', 'code': 'REPORT_BUSY'}), 503, headers: <String, String>{'content-type': 'application/json', 'retry-after': '30'}));
      try {
        await busy.getFundSummary(token: token, siteCode: 11);
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.code, 'REPORT_BUSY');
        expect(e.statusCode, 503);
        expect(e.retryAfterSeconds, 30);
        expect(e.message, contains('30 saniye'));
        expect(e.genericFallback, isFalse);
      }
    });

    test('listFundMovements: kasa yolda, limit / offset sorguda', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'fund': 'capital', 'balance_minor': 100, 'total': 0, 'limit': 25, 'offset': 25, 'items': <dynamic>[]}));
      final page = await api.listFundMovements(token: token, siteCode: 11, fund: FinanceFund.capital, limit: 25, offset: 25);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/11/finance/funds/capital/movements');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '25', 'offset': '25'});
      expect(page.fund, FinanceFund.capital);
      await api.listFundMovements(token: token, siteCode: 11, fund: FinanceFund.operating, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
      expect(rec.last.url.path, '/manager/sites/11/finance/funds/operating/movements');
      expect(rec.last.url.queryParameters['from'], '2026-09-01');
      expect(rec.last.url.queryParameters['to'], '2026-09-30');
    });

    test('createFundTransfer: POST gövdesi kesin alanlar; 201 yeni, 200 aynı kayıt', () async {
      final rec = _Rec();
      var status = 201;
      final api = _api(rec, (r) => _json(<String, dynamic>{'transfer': _transferJson()}, status));
      final transfer = await api.createFundTransfer(
        token: token,
        siteCode: 11,
        fromFund: FinanceFund.operating,
        toFund: FinanceFund.capital,
        amountMinor: 150000,
        transferDate: DateTime(2026, 10, 16),
        description: '  Kurul kararı ',
        idempotencyKey: 'fx-1',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/fund-transfers');
      expect(rec.body, <String, dynamic>{
        'from_fund': 'operating',
        'to_fund': 'capital',
        'amount_minor': 150000,
        'transfer_date': '2026-10-16',
        'description': 'Kurul kararı',
        'idempotency_key': 'fx-1',
      });
      expect(transfer.id, 9);
      status = 200;
      await api.createFundTransfer(
        token: token,
        siteCode: 11,
        fromFund: FinanceFund.operating,
        toFund: FinanceFund.capital,
        amountMinor: 150000,
        transferDate: DateTime(2026, 10, 16),
        description: '   ',
        idempotencyKey: 'fx-1',
      );
      expect(rec.body.containsKey('description'), isFalse, reason: 'boş açıklama gitmez');
    });

    test('reverseFundTransfer: POST …/fund-transfers/:id/reverse { reason, idempotency_key }', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'transfer': _transferJson(id: 10, reverses: 9, reason: 'Yanlış'), 'original': _transferJson(reversedBy: 10)}, 201));
      final result = await api.reverseFundTransfer(token: token, siteCode: 11, transferId: 9, reason: ' Yanlış ', idempotencyKey: 'fr-1');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/fund-transfers/9/reverse');
      expect(rec.body, <String, dynamic>{'reason': 'Yanlış', 'idempotency_key': 'fr-1'});
      expect(result.transfer.isReversal, isTrue);
      expect(result.original!.isReversed, isTrue);
    });

    test('listFundTransfers: GET …/fund-transfers; limit / before_id; next_before_id', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'items': <dynamic>[_transferJson()], 'next_before_id': 9}));
      final page = await api.listFundTransfers(token: token, siteCode: 11, limit: 20, beforeId: 30);
      expect(rec.last.url.path, '/manager/sites/11/finance/fund-transfers');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '20', 'before_id': '30'});
      expect(page.items.single.id, 9);
      expect(page.nextBeforeId, 9);
    });

    test('tahsilat ve düzeltme: fund yalnız verilirse gövdede; yanıttan fund_split okunur', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'entry': _entryJson(extra: <String, dynamic>{'fund': 'capital'}),
        'balance_minor': 0,
        'fund_split': <String, dynamic>{'operating_minor': 0, 'capital_minor': 200000, 'advance_minor': 0},
      }, 201));
      final result = await api.recordPayment(
        token: token,
        siteCode: 11,
        apartmentId: 301,
        amountMinor: 200000,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        accountId: 2,
        idempotencyKey: 'p-1',
        fund: FinanceFund.capital,
      );
      expect(rec.body['fund'], 'capital');
      expect(result.fundSplit!.capitalMinor, 200000);
      expect(result.entry.fund, FinanceFund.capital);
      await api.recordPayment(token: token, siteCode: 11, apartmentId: 301, amountMinor: 1, entryDate: DateTime(2026, 10, 5), method: PaymentMethod.cash, idempotencyKey: 'p-2');
      expect(rec.body.containsKey('fund'), isFalse, reason: 'otomatik: alan yok');
      await api.correctPayment(
        token: token,
        siteCode: 11,
        entryId: 5,
        amountMinor: 1,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        idempotencyKey: 'c-1',
        fund: FinanceFund.operating,
      );
      expect(rec.last.url.path, '/manager/sites/11/finance/entries/5/correct');
      expect(rec.body['fund'], 'operating');
    });

    test('4a yolu: recordFeePayment / correctFinancePayment fund taşır', () async {
      final rec = _Rec();
      final api = _authApi(rec, (r) => _json(<String, dynamic>{'entry': _entryJson(), 'balance_minor': 0}, 201));
      await api.recordFeePayment(
        token: token,
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 100,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        idempotencyKey: 'a-1',
        fund: FinanceFund.operating,
      );
      expect(rec.body['fund'], 'operating');
      await api.correctFinancePayment(
        token: token,
        siteCode: 7,
        entryId: 5,
        amountMinor: 100,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        idempotencyKey: 'a-2',
      );
      expect(rec.body.containsKey('fund'), isFalse);
    });

    test('kategori ve gider: fund gövdede; sistem kategorisinin kasası CATEGORY_FUND_LOCKED (409) anlaşılır mesajla', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.method == 'PATCH') {
          return _json(<String, dynamic>{'error': 'locked', 'code': 'CATEGORY_FUND_LOCKED'}, 409);
        }
        return _json(<String, dynamic>{'category': <String, dynamic>{'id': 5, 'name': 'Boya', 'fund': 'capital'}}, 201);
      });
      final created = await api.createExpenseCategory(token: token, siteCode: 11, name: 'Boya', fund: FinanceFund.capital);
      expect(rec.body, <String, dynamic>{'name': 'Boya', 'fund': 'capital'});
      expect(created.fund, FinanceFund.capital);
      try {
        await api.updateExpenseCategory(token: token, siteCode: 11, categoryId: 1, fields: <String, Object?>{'fund': 'capital'});
        fail('hata bekleniyordu');
      } on ApiException catch (e) {
        expect(e.code, 'CATEGORY_FUND_LOCKED');
        expect(e.statusCode, 409);
        expect(e.genericFallback, isFalse);
        expect(e.message, contains('kasası değiştirilemez'));
        expect(e.message, isNot(contains('CATEGORY_FUND_LOCKED')));
      }
      await api.createExpenseCategory(token: token, siteCode: 11, name: 'Su');
      expect(rec.body.containsKey('fund'), isFalse);
    });

    test('kasa hata kodlarının hepsi Türkçe metinle eşli (ham kod / teknik ifade sızmaz)', () async {
      const codes = <String>[
        'FUND_NOT_FOUND',
        'FUND_TRANSFER_NOT_FOUND',
        'FUND_TRANSFER_ALREADY_REVERSED',
        'FUND_TRANSFER_NOT_REVERSIBLE',
        'CATEGORY_FUND_LOCKED',
        'IDEMPOTENCY_CONFLICT',
        'PERIOD_CLOSED',
        'REPORT_BUSY',
      ];
      for (final code in codes) {
        final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'english text', 'code': code}, 409));
        try {
          await api.getFundSummary(token: token, siteCode: 11);
          fail('hata bekleniyordu: $code');
        } on ApiException catch (e) {
          expect(e.genericFallback, isFalse, reason: code);
          expect(e.message, isNot(contains(code)), reason: code);
          expect(e.message, isNot(contains('english')), reason: code);
          expect(e.message.trim(), isNotEmpty, reason: code);
        }
      }
      for (final status in const <(int, String)>[(400, 'INVALID_BODY'), (400, 'INVALID_QUERY')]) {
        final api = _api(_Rec(), (r) => _json(<String, dynamic>{'code': status.$2}, status.$1));
        try {
          await api.getFundSummary(token: token, siteCode: 11);
          fail('hata bekleniyordu: ${status.$2}');
        } on ApiException catch (e) {
          expect(e.genericFallback, isFalse, reason: status.$2);
          expect(e.message, isNot(contains(status.$2)));
        }
      }
    });

    test('aktarım ve ters aktarım yazmaları ASLA otomatik yeniden denenmez', () async {
      var calls = 0;
      final api = _api(_Rec(), (r) {
        calls++;
        return http.Response('{"error":"x"}', 502, headers: <String, String>{'content-type': 'application/json'});
      });
      await expectLater(
        api.createFundTransfer(
          token: token,
          siteCode: 11,
          fromFund: FinanceFund.operating,
          toFund: FinanceFund.capital,
          amountMinor: 100,
          transferDate: DateTime(2026, 10, 16),
          idempotencyKey: 'fx',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
      await expectLater(api.reverseFundTransfer(token: token, siteCode: 11, transferId: 9, reason: 'x', idempotencyKey: 'fr'), throwsA(isA<ApiException>()));
      expect(calls, 2);
    });
  });

  // K3 (P1-3): yazılım ödemeyi kendiliğinden İşletme / Fon hesabına atamaz.
  group('FundChoiceInfo (K3 hesap seçimi): model', () {
    Map<String, dynamic> body({int operating = 0, int capital = 0, bool? required, String? suggested, Object? proposal, String party = 'owner'}) => <String, dynamic>{
      'apartment_id': 7,
      'account_party': party,
      'open': <String, dynamic>{'operating_minor': operating, 'capital_minor': capital},
      'advance_minor': 250,
      'choice_required': required ?? (operating > 0 && capital > 0),
      'suggested_fund': suggested,
      'proposal': proposal,
    };

    test('iki tür açık borç: seçim zorunlu, öneri yok; tek tür: öneri o hesap; borçsuz: ikisi de yok', () {
      final both = FundChoiceInfo.tryParse(body(operating: 100000, capital: 300000))!;
      expect(both.choiceRequired, isTrue);
      expect(both.suggestedFund, isNull);
      expect(both.hasOpenDebt, isTrue);
      expect(both.openOf(FinanceFund.operating), 100000);
      expect(both.openOf(FinanceFund.capital), 300000);
      expect(both.advanceMinor, 250);
      final single = FundChoiceInfo.tryParse(body(capital: 5000, suggested: 'capital'))!;
      expect(single.choiceRequired, isFalse);
      expect(single.suggestedFund, FinanceFund.capital);
      final none = FundChoiceInfo.tryParse(body())!;
      expect([none.choiceRequired, none.suggestedFund, none.hasOpenDebt], [false, null, false]);
    });

    test('otomatik dağıtım önerisi (proposal) FundSplit olarak okunur; bozuksa null; hesap kiracı olabilir', () {
      final info = FundChoiceInfo.tryParse(
        body(operating: 100, capital: 100, party: 'tenant', proposal: <String, dynamic>{'operating_minor': 100, 'capital_minor': 20, 'advance_minor': 0}),
      )!;
      expect(info.accountParty, 'tenant');
      expect(info.proposal, const FundSplit(operatingMinor: 100, capitalMinor: 20, advanceMinor: 0));
      expect(FundChoiceInfo.tryParse(body(operating: 100, capital: 100, proposal: <String, dynamic>{'operating_minor': 'x'}))!.proposal, isNull);
    });

    test('bozuk ya da eksik gövde null (uydurma 0 yazılmaz); bilinmeyen öneri değeri yok sayılır', () {
      expect(FundChoiceInfo.tryParse(null), isNull);
      expect(FundChoiceInfo.tryParse(<String, dynamic>{'choice_required': true}), isNull);
      expect(FundChoiceInfo.tryParse(<String, dynamic>{'open': <String, dynamic>{'operating_minor': 1}}), isNull);
      expect(FundChoiceInfo.tryParse(<String, dynamic>{'open': <String, dynamic>{'operating_minor': -5, 'capital_minor': 1}}), isNull);
      expect(FundChoiceInfo.tryParse(body(operating: 5, suggested: 'kasa'))!.suggestedFund, isNull);
    });

    test('eşitlik değerle: aynı alanlar eşit', () {
      expect(FundChoiceInfo.tryParse(body(operating: 5, suggested: 'operating')), FundChoiceInfo.tryParse(body(operating: 5, suggested: 'operating')));
      expect(FundChoiceInfo.tryParse(body(operating: 5, suggested: 'operating')), isNot(FundChoiceInfo.tryParse(body(operating: 6, suggested: 'operating'))));
    });
  });

  group('Finance4bApi.getFundChoice (K3)', () {
    const token = 'tok';

    test('GET .../finance/payments/fund-choice: sorgu yalnız verilenleri taşır; yanıt ayrıştırılır', () async {
      final rec = _Rec();
      final api = _api(
        rec,
        (r) => _json(<String, dynamic>{
          'apartment_id': 7,
          'account_party': 'owner',
          'open': <String, dynamic>{'operating_minor': 100000, 'capital_minor': 300000},
          'advance_minor': 0,
          'choice_required': true,
          'suggested_fund': null,
          'proposal': <String, dynamic>{'operating_minor': 100000, 'capital_minor': 50000, 'advance_minor': 0},
        }),
      );
      final info = await api.getFundChoice(token: token, siteCode: 11, apartmentId: 7);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/11/finance/payments/fund-choice');
      expect(rec.last.url.queryParameters, <String, String>{'apartment_id': '7'});
      expect(info.choiceRequired, isTrue);
      expect(info.proposal, const FundSplit(operatingMinor: 100000, capitalMinor: 50000, advanceMinor: 0));
      await api.getFundChoice(token: token, siteCode: 11, apartmentId: 7, accountParty: AccountParty.tenant, amountMinor: 150000, paidOn: DateTime(2026, 10, 20));
      expect(rec.last.url.queryParameters, <String, String>{'apartment_id': '7', 'account_party': 'tenant', 'amount_minor': '150000', 'paid_on': '2026-10-20'});
      await api.getFundChoice(token: token, siteCode: 11, apartmentId: 7, amountMinor: 0);
      expect(rec.last.url.queryParameters.containsKey('amount_minor'), isFalse, reason: 'sıfır / eksik tutar gönderilmez');
    });

    test('okunamayan yanıt Türkçe hata verir; 403 (kurul / yetkisiz) yazma yetkisi hatası olarak yükselir', () async {
      final bad = _api(_Rec(), (r) => _json(<String, dynamic>{'choice_required': true}));
      await expectLater(bad.getFundChoice(token: token, siteCode: 11, apartmentId: 7), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Hesap bilgisi'))));
      final forbidden = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'Bu işlem için yetkiniz yok.', 'code': 'FORBIDDEN_ROLE'}, 403));
      await expectLater(forbidden.getFundChoice(token: token, siteCode: 11, apartmentId: 7), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
    });

    test('tahsilat 400 FUND_CHOICE_REQUIRED: hata gövdesi `fund_choice` payload olarak KORUNUR (panel zorunlu kipe geçer) ve Türkçe metin kasa sözcüğü içermez', () async {
      final rec = _Rec();
      final choice = <String, dynamic>{
        'apartment_id': 7,
        'account_party': 'owner',
        'open': <String, dynamic>{'operating_minor': 100000, 'capital_minor': 300000},
        'advance_minor': 0,
        'choice_required': true,
        'suggested_fund': null,
        'proposal': null,
      };
      final api = _api(rec, (r) => _json(<String, dynamic>{'error': 'sunucu metni', 'code': 'FUND_CHOICE_REQUIRED', 'fund_choice': choice}, 400));
      Object? caught;
      try {
        await api.recordPayment(
          token: token,
          siteCode: 11,
          apartmentId: 7,
          amountMinor: 1000,
          entryDate: DateTime(2026, 10, 20),
          method: PaymentMethod.cash,
          idempotencyKey: 'k1',
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ApiException>());
      final error = caught! as ApiException;
      expect(error.code, 'FUND_CHOICE_REQUIRED');
      expect(error.statusCode, 400);
      expect(error.message.toLowerCase(), isNot(contains('kasa')));
      expect(error.message, contains('Yatırım ve Demirbaş (Fon) Hesabı'));
      expect(FundChoiceInfo.tryParse(error.payload?['fund_choice'])!.choiceRequired, isTrue);
      expect(rec.body.containsKey('fund'), isFalse, reason: 'seçim yoksa fund gövdede yok');
    });
  });
}
