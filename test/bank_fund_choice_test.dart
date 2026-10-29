// Banka satırları: K3 (İşletme / Fon hesabı seçimi) + C-26 ("güçlü eşleşmeleri de tek tek gözden geçir"). Ağ yok: sahte API.
//  - "Daireye işle": iki türlü borçta hesap seçilmeden gönderilmez; tek türde öneri seçili gelir; değişen daire hesabında bilgi yeniden okunur.
//  - "Tek tek gözden geçir" akışı: sırayla Onayla / Atla; hesap seçimi satır başınadır; özet sayıları.
//  - Satır listesi: REVIEW_EACH / FUND_CHOICE_REQUIRED notları, toplu onayın hesap seçimi gereken satırları dışarıda bırakması.
//  - API gövdeleri: review_each yalnız true iken gider; fund / fund_choices yalnız doluyken.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/services/bank_statement_reader.dart';
import 'package:site_kapi_kontrol/ui/dialogs/bank_line_assign_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/bank_line_review_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bank_lines_view.dart';

import 'bulk_fakes.dart';

typedef _FundLoader = Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn});

Map<String, dynamic> _fundBody({int operating = 0, int capital = 0, String party = 'owner'}) => <String, dynamic>{
  'apartment_id': 7,
  'account_party': party,
  'open': <String, dynamic>{'operating_minor': operating, 'capital_minor': capital},
  'advance_minor': 0,
  'choice_required': operating > 0 && capital > 0,
  'suggested_fund': operating > 0 && capital == 0 ? 'operating' : (capital > 0 && operating == 0 ? 'capital' : null),
  'proposal': null,
};

/// Daire kimliğine göre yanıt veren sahte yükleyici (yoksa borçsuz).
_FundLoader _loaderBy(Map<int, Map<String, dynamic>> bodies, {List<Map<String, Object?>>? calls}) =>
    ({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn}) async {
      calls?.add(<String, Object?>{'apartment_id': apartmentId, 'account_party': accountParty?.apiValue});
      return FundChoiceInfo.tryParse(<String, dynamic>{...(bodies[apartmentId] ?? _fundBody()), 'account_party': accountParty?.apiValue ?? 'owner'})!;
    };

bool _selected(String key) => find
    .descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byIcon(Icons.radio_button_checked_rounded))
    .evaluate()
    .isNotEmpty;

BankLineItem _line(int id, int apartmentId, {String? note, String party = 'owner', int amount = 150000, String status = 'suggested', String label = 'A Blok - 3'}) => BankLineItem(
  id: id,
  accountId: 5,
  valueDate: '2026-10-20',
  amountMinor: amount,
  description: 'GUL-A$apartmentId aidat',
  status: status,
  counterpartyName: 'Ali Veli',
  apartmentId: apartmentId,
  apartmentLabel: label,
  party: party,
  matchMethod: 'ref',
  note: note,
);

class _FakeBankApi extends BankImportApi {
  _FakeBankApi({this.lines = const <BankLineItem>[]}) : super(baseUrl: 'http://localhost');

  List<BankLineItem> lines;
  final assignCalls = <Map<String, Object?>>[];
  final confirmCalls = <Map<String, Object?>>[];
  Object? assignError;
  Map<int, String> confirmFailures = <int, String>{};

  @override
  Future<List<BankLineItem>> listLinesByStatus({required String token, required int siteCode, required String status}) async => lines;

  @override
  Future<void> assignLine({
    required String token,
    required int siteCode,
    required int lineId,
    required int apartmentId,
    String? party,
    bool saveIban = false,
    FinanceFund? fund,
  }) async {
    assignCalls.add(<String, Object?>{'line_id': lineId, 'apartment_id': apartmentId, 'party': party, 'fund': fund?.apiValue});
    final error = assignError;
    if (error != null) {
      assignError = null; // yalnız ilk deneme reddedilir
      throw error;
    }
  }

  @override
  Future<({int done, int failed, Map<int, String> failedCodes})> confirmLines({
    required String token,
    required int siteCode,
    required List<int> lineIds,
    Map<int, FinanceFund> fundChoices = const <int, FinanceFund>{},
  }) async {
    confirmCalls.add(<String, Object?>{'line_ids': lineIds, 'fund_choices': <int, String>{for (final e in fundChoices.entries) e.key: e.value.apiValue}});
    final failed = <int, String>{for (final id in lineIds) if (confirmFailures.containsKey(id)) id: confirmFailures[id]!};
    return (done: lineIds.length - failed.length, failed: failed.length, failedCodes: failed);
  }
}

PeopleScope _scope(FakeBulkAuth auth) => PeopleScope(authService: auth, siteCode: 1, siteName: 'Gül', canWrite: true);

Future<void> _show(WidgetTester t, Widget dialog) async {
  t.view.physicalSize = const Size(1000, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: TextButton(onPressed: () => showDialog<void>(context: ctx, builder: (_) => dialog), child: const Text('aç'))))));
  await t.tap(find.text('aç'));
  await t.pumpAndSettle();
}

({FakeBulkAuth auth, _FakeBankApi api}) _setup({List<BankLineItem> lines = const <BankLineItem>[]}) {
  final auth = FakeBulkAuth();
  final api = _FakeBankApi(lines: lines);
  BankImportService.register(auth, BankImportService(authService: auth, api: api, tokenProvider: () => 'tok'));
  return (auth: auth, api: api);
}

void main() {
  group('Daireye işle penceresi: İşletme / Fon hesabı (K3)', () {
    testWidgets('iki tür borç: hesap seçilmeden İşle sunucuya GİTMEZ; seçilince fund gider', (t) async {
      final s = _setup();
      await _show(t, BankLineAssignDialog(scope: _scope(s.auth), line: _line(11, 7), fundChoiceLoader: _loaderBy(<int, Map<String, dynamic>>{7: _fundBody(operating: 100000, capital: 300000)})));
      expect(find.byKey(const ValueKey<String>('bank_assign_fund_required')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bank_assign_fund_auto')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_save')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls, isEmpty);
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_fund_capital')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_save')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls.single['fund'], 'capital');
      expect(s.api.assignCalls.single['apartment_id'], 7);
    });

    testWidgets('tek tür borç: önerilen hesap seçili gelir ve gönderilir', (t) async {
      final s = _setup();
      await _show(t, BankLineAssignDialog(scope: _scope(s.auth), line: _line(11, 7), fundChoiceLoader: _loaderBy(<int, Map<String, dynamic>>{7: _fundBody(operating: 100000)})));
      expect(_selected('bank_assign_fund_operating'), isTrue);
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_save')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls.single['fund'], 'operating');
    });

    testWidgets('açık borç yok: fund gönderilmez', (t) async {
      final s = _setup();
      await _show(t, BankLineAssignDialog(scope: _scope(s.auth), line: _line(11, 7), fundChoiceLoader: _loaderBy(const <int, Map<String, dynamic>>{})));
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_save')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls.single['fund'], isNull);
    });

    testWidgets('bayat bilgi: sunucu 400 FUND_CHOICE_REQUIRED verirse panel zorunlu kipe geçer', (t) async {
      final s = _setup();
      s.api.assignError = ApiException(
        'Bu daire hesabında hem İşletme hem Fon için açık borç var.',
        statusCode: 400,
        code: 'FUND_CHOICE_REQUIRED',
        payload: <String, dynamic>{'code': 'FUND_CHOICE_REQUIRED', 'fund_choice': _fundBody(operating: 100000, capital: 300000)},
      );
      await _show(t, BankLineAssignDialog(scope: _scope(s.auth), line: _line(11, 7), fundChoiceLoader: _loaderBy(const <int, Map<String, dynamic>>{})));
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_save')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls, hasLength(1));
      expect(find.byKey(const ValueKey<String>('bank_assign_fund_required')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_fund_operating')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('bank_assign_save')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls, hasLength(2));
      expect(s.api.assignCalls.last['fund'], 'operating');
    });
  });

  group('Tek tek gözden geçir (C-26)', () {
    testWidgets('sırayla gösterir: iki türlü satırda hesap seçilmeden Onayla gitmez; sonra tek türlü satır önerilen hesapla; özet sayıları', (t) async {
      final s = _setup();
      final lines = <BankLineItem>[_line(11, 7, note: kBankNoteReviewEach), _line(12, 8, label: 'B Blok - 2'), _line(13, 9, label: 'C Blok - 1')];
      final loader = _loaderBy(<int, Map<String, dynamic>>{
        7: _fundBody(operating: 100000, capital: 300000),
        8: _fundBody(operating: 50000),
      });
      await _show(t, BankLineReviewDialog(scope: _scope(s.auth), lines: reviewableBankLines(lines), fundChoiceLoader: loader));
      expect(find.text('Tek tek gözden geçir (1 / 3)'), findsOneWidget);
      expect(find.textContaining('Öneri: A Blok - 3 (ev sahibi)'), findsOneWidget);
      expect(find.textContaining('Güçlü eşleşme; tek tek onayınız istendi.'), findsOneWidget);
      // iki tür: seçmeden Onayla -> gitmez
      await t.tap(find.byKey(const ValueKey<String>('bank_review_approve')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls, isEmpty);
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('bank_review_fund_capital')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('bank_review_approve')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls.single, <String, Object?>{'line_id': 11, 'apartment_id': 7, 'party': 'owner', 'fund': 'capital'});
      // 2. satır: tek tür -> öneri seçili, doğrudan onay
      expect(find.text('Tek tek gözden geçir (2 / 3)'), findsOneWidget);
      expect(_selected('bank_review_fund_operating'), isTrue);
      await t.tap(find.byKey(const ValueKey<String>('bank_review_approve')));
      await t.pumpAndSettle();
      expect(s.api.assignCalls.last['fund'], 'operating');
      expect(s.api.assignCalls.last['line_id'], 12);
      // 3. satır: atla
      expect(find.text('Tek tek gözden geçir (3 / 3)'), findsOneWidget);
      expect(_selected('bank_review_fund_operating'), isFalse, reason: 'önceki satırın seçimi geçmez');
      await t.tap(find.byKey(const ValueKey<String>('bank_review_skip')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('bank_review_finished')), findsOneWidget);
      expect(find.text('2 satır işlendi, 1 satır atlandı (beklemeye devam eder).'), findsOneWidget);
      expect(s.api.assignCalls, hasLength(2));
    });

    testWidgets('yalnız önerili, gelen paralı, bekleyen satırlar incelenir; hiç satır yoksa boş durum', (t) async {
      final lines = <BankLineItem>[
        _line(1, 7),
        _line(2, 7, status: 'unmatched'),
        _line(3, 7, amount: -5000),
        BankLineItem(id: 4, valueDate: '2026-10-20', amountMinor: 1000, description: 'x', status: 'suggested'),
      ];
      expect(reviewableBankLines(lines).map((l) => l.id), <int>[1]);
      final s = _setup();
      await _show(t, BankLineReviewDialog(scope: _scope(s.auth), lines: const <BankLineItem>[]));
      expect(find.byKey(const ValueKey<String>('bank_review_empty')), findsOneWidget);
    });

    testWidgets('sunucu seçim isterse (bayat bilgi) panel zorunlu kipe geçer; satır ilerlemez', (t) async {
      final s = _setup();
      s.api.assignError = ApiException(
        'Seçim gerekli.',
        statusCode: 400,
        code: 'FUND_CHOICE_REQUIRED',
        payload: <String, dynamic>{'code': 'FUND_CHOICE_REQUIRED', 'fund_choice': _fundBody(operating: 100000, capital: 300000)},
      );
      await _show(t, BankLineReviewDialog(scope: _scope(s.auth), lines: <BankLineItem>[_line(11, 7)], fundChoiceLoader: _loaderBy(const <int, Map<String, dynamic>>{})));
      await t.tap(find.byKey(const ValueKey<String>('bank_review_approve')));
      await t.pumpAndSettle();
      expect(find.text('Tek tek gözden geçir (1 / 1)'), findsOneWidget, reason: 'reddedilen satır ilerlemez');
      expect(find.byKey(const ValueKey<String>('bank_review_fund_required')), findsOneWidget);
    });
  });

  group('Banka satırları ekranı', () {
    Future<_FakeBankApi> pumpView(WidgetTester t, List<BankLineItem> lines) async {
      final s = _setup(lines: lines);
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: BankLinesView(scope: _scope(s.auth))));
      await t.pumpAndSettle();
      return s.api;
    }

    testWidgets('REVIEW_EACH ve FUND_CHOICE_REQUIRED notları açıkça yazılır; hesap seçimi gereken satırın düğmesi "Hesabı seçerek onayla"', (t) async {
      await pumpView(t, <BankLineItem>[_line(11, 7, note: kBankNoteReviewEach), _line(12, 8, note: kBankNoteFundChoice, label: 'B Blok - 2')]);
      expect(find.byKey(const ValueKey<String>('bank_note_review_11')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bank_note_fund_12')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('bank_confirm_11')), matching: find.text('Onayla')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('bank_confirm_12')), matching: find.text('Hesabı seçerek onayla')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bank_review_each')), findsOneWidget);
    });

    testWidgets('toplu onay hesap seçimi gereken satırları DIŞARIDA bırakır ve nedenini söyler', (t) async {
      final api = await pumpView(t, <BankLineItem>[_line(11, 7), _line(12, 8, note: kBankNoteFundChoice, label: 'B Blok - 2'), _line(13, 9, label: 'C Blok - 1')]);
      await t.tap(find.byKey(const ValueKey<String>('bank_confirm_all')));
      await t.pumpAndSettle();
      expect(api.confirmCalls.single['line_ids'], <int>[11, 13], reason: '12 hesap seçimi gerektirdiği için toplu onayda yok');
      expect(find.textContaining('1 satır hesap (İşletme / Fon) seçimi gerektiriyor (tek tek onaylayın)'), findsOneWidget);
    });

    testWidgets('tek satır Onayla: sunucu FUND_CHOICE_REQUIRED derse Daireye işle penceresi açılır (hesap orada seçilir)', (t) async {
      final api = await pumpView(t, <BankLineItem>[_line(11, 7)]);
      api.confirmFailures = <int, String>{11: kBankNoteFundChoice};
      await t.tap(find.byKey(const ValueKey<String>('bank_confirm_11')));
      await t.pumpAndSettle();
      expect(api.confirmCalls, hasLength(1));
      expect(find.byType(BankLineAssignDialog), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bank_assign_save')), findsOneWidget);
    });

    testWidgets('notu FUND_CHOICE_REQUIRED olan satırda Onayla doğrudan Daireye işle penceresini açar (boşuna istek yok)', (t) async {
      final api = await pumpView(t, <BankLineItem>[_line(12, 8, note: kBankNoteFundChoice, label: 'B Blok - 2')]);
      await t.tap(find.byKey(const ValueKey<String>('bank_confirm_12')));
      await t.pumpAndSettle();
      expect(api.confirmCalls, isEmpty);
      expect(find.byType(BankLineAssignDialog), findsOneWidget);
    });

    testWidgets('tek tek gözden geçir düğmesi incelemeyi açar', (t) async {
      await pumpView(t, <BankLineItem>[_line(11, 7)]);
      await t.tap(find.byKey(const ValueKey<String>('bank_review_each')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('bank_review')), findsOneWidget);
      expect(find.text('Tek tek gözden geçir (1 / 1)'), findsOneWidget);
    });
  });

  group('API gövdeleri', () {
    late List<http.Request> sent;
    late BankImportApi api;

    setUp(() {
      sent = <http.Request>[];
      api = BankImportApi(
        baseUrl: 'http://localhost',
        client: http_testing.MockClient((request) async {
          sent.add(request);
          if (request.url.path.endsWith('/bank-lines/confirm')) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'done': <int>[12],
                'failed': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 11, 'code': 'FUND_CHOICE_REQUIRED'},
                  <String, dynamic>{'id': 13, 'code': 'BANK_LINE_NOT_OPEN'},
                ],
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/bank-imports')) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'replayed': false,
                'import': <String, dynamic>{'id': 3},
                'counts': <String, dynamic>{'posted': 0, 'linked': 0, 'attention': 2},
              }),
              201,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200, headers: <String, String>{'content-type': 'application/json'});
        }),
      );
    });

    Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

    test('assignLine: fund yalnız doluyken gider', () async {
      await api.assignLine(token: 't', siteCode: 1, lineId: 11, apartmentId: 7, party: 'owner');
      expect(bodyOf(sent.last).containsKey('fund'), isFalse);
      await api.assignLine(token: 't', siteCode: 1, lineId: 11, apartmentId: 7, party: 'owner', fund: FinanceFund.capital);
      expect(bodyOf(sent.last)['fund'], 'capital');
    });

    test('confirmLines: fund_choices SATIR BAŞINA gider (boşsa hiç gitmez); işlenemeyenlerin hata kodları okunur', () async {
      final plain = await api.confirmLines(token: 't', siteCode: 1, lineIds: <int>[11, 12, 13]);
      expect(bodyOf(sent.last).containsKey('fund_choices'), isFalse);
      expect(plain.done, 1);
      expect(plain.failed, 2);
      expect(plain.failedCodes, <int, String>{11: 'FUND_CHOICE_REQUIRED', 13: 'BANK_LINE_NOT_OPEN'});
      await api.confirmLines(token: 't', siteCode: 1, lineIds: <int>[11, 12], fundChoices: <int, FinanceFund>{11: FinanceFund.operating});
      expect(bodyOf(sent.last)['fund_choices'], <Map<String, dynamic>>[
        <String, dynamic>{'line_id': 11, 'fund': 'operating'},
      ]);
    });

    test('commit: review_each YALNIZ true iken gider (varsayılan istek eskisiyle aynı)', () async {
      final file = BankFile(kind: BankFileKind.csv, name: 'e.csv', size: 10, sha256: 'a' * 64);
      const lines = <BankLine>[BankLine(n: 1, valueDate: '2026-10-20', amountMinor: 1000, description: 'x')];
      await api.commit(token: 't', siteCode: 1, accountId: 5, file: file, lines: lines, previewHash: 'b' * 64, idempotencyKey: 'bi-anahtar-0001');
      expect(bodyOf(sent.last).containsKey('review_each'), isFalse);
      final reviewed = await api.commit(token: 't', siteCode: 1, accountId: 5, file: file, lines: lines, previewHash: 'b' * 64, idempotencyKey: 'bi-anahtar-0002', reviewEach: true);
      expect(bodyOf(sent.last)['review_each'], isTrue);
      expect(reviewed.attention, 2);
    });

    test('önizleme özeti fund_choice sayısını okur (eski sunucuda alan yok: 0)', () {
      expect(BankPreviewSummary.fromJson(<String, dynamic>{'recognized': 2, 'check': 3, 'fund_choice': 1}).fundChoice, 1);
      expect(BankPreviewSummary.fromJson(<String, dynamic>{'recognized': 2}).fundChoice, 0);
    });

    test('FUND_CHOICE_REQUIRED hata kodu Türkçe metne eşlenir ve kasa sözcüğü geçmez', () {
      final text = bankErrorMessage('FUND_CHOICE_REQUIRED')!;
      expect(text, contains('İşletme Projesi (Aidat) Hesabı'));
      expect(text, contains('Yatırım ve Demirbaş (Fon) Hesabı'));
      expect(text.toLowerCase(), isNot(contains('kasa')));
    });
  });
}
