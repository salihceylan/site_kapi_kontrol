// Platform Faz 4a (Aidat ve Finans): AuthApi / AuthService uçları (docs/PLATFORM_FINANS.md).
//
// MockClient ile: uç yolları, HTTP yöntemleri, gövdeler (tutarlar KURUŞ tamsayı), sorgu parametreleri, Bearer
// başlığı, 200/201 (idempotent tekrar) kabulü, hata kodu -> Türkçe mesaj eşlemeleri ve yazma isteklerinin
// ASLA otomatik yeniden denenmemesi. Yanıt gövdeleri sunucunun gerçek biçimindedir. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Recorder {
  final List<http.Request> requests = <http.Request>[];

  http.Request get last => requests.last;

  Map<String, dynamic> get lastBody => jsonDecode(last.body) as Map<String, dynamic>;
}

AuthApi _api(_Recorder rec, FutureOr<http.Response> Function(http.Request request) handler) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient((request) async {
      rec.requests.add(request);
      return handler(request);
    }),
    retryDelay: Duration.zero,
  );
}

Map<String, dynamic> _error(String code, String message) => <String, dynamic>{
  'error': message,
  'code': code,
};

Map<String, dynamic> _definition({int id = 7}) => <String, dynamic>{
  'id': id,
  'name': 'Aylık aidat',
  'kind': 'recurring',
  'distribution': 'fixed',
  'amount_minor': 50000,
  'category_amounts': null,
  'due_day': 15,
  'start_period': '2026-01',
  'end_period': null,
  'target_type': 'site',
  'target_block_ids': <int>[],
  'target_apartment_ids': <int>[],
  'is_active': true,
  'has_runs': false,
  'last_posted_period': null,
};

Map<String, dynamic> _entry({int id = 5, String kind = 'payment', int amount = -50000}) => <String, dynamic>{
  'id': id,
  'kind': kind,
  'amount_minor': amount,
  'period': '2026-10',
  'entry_date': '2026-10-05',
  'due_date': null,
  'description': null,
  'method': 'cash',
  'payer_party': 'owner',
  'definition_name': null,
  'reverses_entry_id': null,
  'reversed_by_entry_id': null,
  'reversal_reason': null,
  'created_by_name': 'Site Yöneticisi',
  'created_at': '2026-10-05T09:00:00.000Z',
};

Map<String, dynamic> _preview() => <String, dynamic>{
  'period': '2026-10',
  'definition_id': 7,
  'total_minor': 100000,
  'apartment_count': 2,
  'lines': <Map<String, dynamic>>[
    <String, dynamic>{
      'apartment_id': 301,
      'label': 'A Blok - 5',
      'block_name': 'A Blok',
      'payer_party': 'owner',
      'amount_minor': 50000,
    },
    <String, dynamic>{
      'apartment_id': 302,
      'label': 'A Blok - 6',
      'block_name': 'A Blok',
      'payer_party': 'tenant',
      'amount_minor': 50000,
    },
  ],
  'missing_data': <dynamic>[],
  'already_posted': false,
  'closed': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthApi: tanımlar', () {
    test('listFeeDefinitions: GET, süzgeçler yalnız verilince sorguya yazılır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[_definition()],
      }));
      final items = await api.listFeeDefinitions(
        token: 'tok',
        siteCode: 7,
        kind: FeeKind.oneTime,
        active: false,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/finance/definitions');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(rec.last.url.queryParameters, <String, String>{'kind': 'one_time', 'active': 'false'});
      expect(items.single.name, 'Aylık aidat');
      expect(items.single.amountMinor, 50000);

      await api.listFeeDefinitions(token: 'tok', siteCode: 7);
      expect(rec.last.url.queryParameters, isEmpty);
      await api.listFeeDefinitions(token: 'tok', siteCode: 7, active: true);
      expect(rec.last.url.queryParameters, <String, String>{'active': 'true'});
    });

    test('createFeeDefinition: POST, 201; tutar KURUŞ tamsayı `amount_minor`', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_definition(id: 8), 201));
      final created = await api.createFeeDefinition(
        token: 'tok',
        siteCode: 7,
        input: const FeeDefinitionInput(
          name: ' Aylık aidat ',
          kind: FeeKind.recurring,
          distribution: FeeDistribution.fixed,
          amountMinor: 123456,
          dueDay: 15,
          startPeriod: FinancePeriod(2026, 10),
          target: FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1, 2]),
        ),
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/finance/definitions');
      expect(rec.lastBody, <String, dynamic>{
        'name': 'Aylık aidat',
        'kind': 'recurring',
        'distribution': 'fixed',
        'amount_minor': 123456,
        'due_day': 15,
        'start_period': '2026-10',
        'target': <String, dynamic>{'type': 'blocks', 'block_ids': <int>[1, 2]},
      });
      expect(rec.lastBody['amount_minor'], isA<int>());
      expect(created.id, 8);
    });

    test('createFeeDefinition: { definition: {...} } sarmalı da okunur', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{'definition': _definition(id: 9)}, 201));
      final created = await api.createFeeDefinition(
        token: 'tok',
        siteCode: 7,
        input: const FeeDefinitionInput(
          name: 'x',
          kind: FeeKind.oneTime,
          distribution: FeeDistribution.equal,
          amountMinor: 100,
          startPeriod: FinancePeriod(2026, 10),
        ),
      );
      expect(created.id, 9);
    });

    test('updateFeeDefinition: PATCH yalnız verilen alanlar', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_definition()));
      await api.updateFeeDefinition(
        token: 'tok',
        siteCode: 7,
        definitionId: 7,
        fields: <String, Object?>{'is_active': false, 'end_period': null},
      );
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/manager/sites/7/finance/definitions/7');
      expect(rec.lastBody, <String, dynamic>{'is_active': false, 'end_period': null});
    });
  });

  group('AuthApi: önizleme ve borçlandırma', () {
    test('previewFeeRun: aylık -> period (YYYY-AA); tek seferlik -> due_date', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_preview()));
      final preview = await api.previewFeeRun(
        token: 'tok',
        siteCode: 7,
        definitionId: 7,
        period: const FinancePeriod(2026, 10),
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/finance/definitions/7/preview');
      expect(rec.lastBody, <String, dynamic>{'period': '2026-10'});
      expect(preview.totalMinor, 100000);
      expect(preview.lines.length, 2);

      await api.previewFeeRun(token: 'tok', siteCode: 7, definitionId: 7, dueDate: DateTime(2026, 11, 5));
      expect(rec.lastBody, <String, dynamic>{'due_date': '2026-11-05'});
      await api.previewFeeRun(token: 'tok', siteCode: 7, definitionId: 7);
      expect(rec.lastBody, <String, dynamic>{});
    });

    test('postFeeRun: beklenen toplam / sayı, skip_missing yalnız true iken, idempotency_key', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'run': <String, dynamic>{
          'id': 9,
          'definition_id': 7,
          'period': '2026-10',
          'total_minor': 100000,
          'apartment_count': 2,
        },
        'entries_count': 2,
      }, 201));
      final result = await api.postFeeRun(
        token: 'tok',
        siteCode: 7,
        definitionId: 7,
        period: const FinancePeriod(2026, 10),
        expectedTotalMinor: 100000,
        expectedApartmentCount: 2,
        idempotencyKey: 'run-abc',
      );
      expect(rec.last.url.path, '/manager/sites/7/finance/definitions/7/post');
      expect(rec.lastBody, <String, dynamic>{
        'period': '2026-10',
        'expected_total_minor': 100000,
        'expected_apartment_count': 2,
        'idempotency_key': 'run-abc',
      });
      expect(result.totalMinor, 100000);
      expect(result.entriesCount, 2);

      await api.postFeeRun(
        token: 'tok',
        siteCode: 7,
        definitionId: 7,
        period: const FinancePeriod(2026, 10),
        expectedTotalMinor: 100000,
        expectedApartmentCount: 2,
        skipMissing: true,
      );
      expect(rec.lastBody['skip_missing'], true);
      expect(rec.lastBody.containsKey('idempotency_key'), isFalse);
    });

    test('aynı anahtarla tekrar (200) başarıdır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'run': <String, dynamic>{'id': 9, 'total_minor': 100000, 'apartment_count': 2},
        'entries_count': 2,
      }));
      final result = await api.postFeeRun(
        token: 'tok',
        siteCode: 7,
        definitionId: 7,
        expectedTotalMinor: 100000,
        expectedApartmentCount: 2,
        idempotencyKey: 'k',
      );
      expect(result.runId, 9);
    });

    test('ek borç önizleme ve onay yolları / gövdeleri', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/preview')) return _json(_preview());
        return _json(<String, dynamic>{
          'run': <String, dynamic>{'id': 3, 'total_minor': 100000, 'apartment_count': 2},
          'entries_count': 2,
          'definition': _definition(id: 60),
        }, 201);
      });
      final input = ExtraChargeInput(
        name: 'Asansör',
        distribution: FeeDistribution.landShare,
        amountMinor: 12000000,
        dueDate: DateTime(2026, 11, 5),
      );
      await api.previewExtraCharge(token: 'tok', siteCode: 7, input: input);
      expect(rec.last.url.path, '/manager/sites/7/finance/charges/preview');
      expect(rec.lastBody['amount_minor'], 12000000);
      expect(rec.lastBody.containsKey('expected_total_minor'), isFalse);

      final result = await api.postExtraCharge(
        token: 'tok',
        siteCode: 7,
        input: input,
        expectedTotalMinor: 12000000,
        expectedApartmentCount: 30,
        idempotencyKey: 'chg-1',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/finance/charges');
      expect(rec.lastBody['expected_total_minor'], 12000000);
      expect(rec.lastBody['expected_apartment_count'], 30);
      expect(rec.lastBody['idempotency_key'], 'chg-1');
      expect(rec.lastBody['due_date'], '2026-11-05');
      expect(result.entriesCount, 2);
    });
  });

  group('AuthApi: hesaplar ve özet', () {
    test('listFinanceBalances: durum, arama, sayfa', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 301,
            'label': 'A Blok - 5',
            'block_name': 'A Blok',
            'balance_minor': 100000,
            'overdue_minor': 50000,
            'owner_name': 'Ayşe',
            'tenant_name': null,
          },
        ],
        'total': 9,
        'totals': <String, dynamic>{'debt_minor': 100000, 'credit_minor': 0},
      }));
      final page = await api.listFinanceBalances(
        token: 'tok',
        siteCode: 7,
        status: 'debtor',
        query: '  ayşe ',
        limit: 20,
        offset: 40,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/finance/balances');
      expect(rec.last.url.queryParameters, <String, String>{
        'status': 'debtor',
        'q': 'ayşe',
        'limit': '20',
        'offset': '40',
      });
      expect(page.total, 9);
      expect(page.items.single.balanceMinor, 100000);

      await api.listFinanceBalances(token: 'tok', siteCode: 7, query: '   ');
      expect(rec.last.url.queryParameters, <String, String>{'status': 'all', 'limit': '50', 'offset': '0'});
    });

    test('getFinanceAccount: yol, limit ve before_id imleci', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'apartment': <String, dynamic>{
          'id': 301,
          'label': 'A Blok - 5',
          'block_name': 'A Blok',
          'responsible_party': 'owner',
        },
        'balance_minor': 100000,
        'overdue_minor': 0,
        'items': <Map<String, dynamic>>[_entry(kind: 'charge', amount: 100000)],
        'next_before_id': 4,
      }));
      final view = await api.getFinanceAccount(
        token: 'tok',
        siteCode: 7,
        apartmentId: 301,
        limit: 20,
        beforeId: 9,
      );
      expect(rec.last.url.path, '/manager/sites/7/finance/apartments/301/account');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '20', 'before_id': '9'});
      expect(view.nextBeforeId, 4);
      expect(view.balanceMinor, 100000);
      await api.getFinanceAccount(token: 'tok', siteCode: 7, apartmentId: 301);
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50'});
    });

    test('getFinanceSummary ve getMyFinance', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.url.path == '/app/my-finance') {
          return _json(<String, dynamic>{'items': <dynamic>[]});
        }
        return _json(<String, dynamic>{
          'currency': 'TRY',
          'open_period': '2026-10',
          'balance_total_minor': 1,
          'debt_total_minor': 2,
          'credit_total_minor': 1,
          'debtor_count': 1,
          'this_period': <String, dynamic>{'charged_minor': 5, 'collected_minor': 4},
        });
      });
      final summary = await api.getFinanceSummary(token: 'tok', siteCode: 7);
      expect(rec.last.url.path, '/manager/sites/7/finance/summary');
      expect(summary.debtTotalMinor, 2);
      final mine = await api.getMyFinance(token: 'tok');
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/my-finance');
      expect(mine.items, isEmpty);
    });
  });

  group('AuthApi: tahsilat ve düzeltme', () {
    test('recordFeePayment: tutar POZİTİF kuruş, tarih YYYY-AA-GG, boş açıklama gitmez; 201 ve 200 başarı', () async {
      final rec = _Recorder();
      var status = 201;
      final api = _api(rec, (r) => _json(<String, dynamic>{'entry': _entry(), 'balance_minor': -2500}, status));
      final result = await api.recordFeePayment(
        token: 'tok',
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 123456,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.transfer,
        description: '   ',
        idempotencyKey: 'pay-1',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/finance/payments');
      expect(rec.lastBody, <String, dynamic>{
        'apartment_id': 301,
        'amount_minor': 123456,
        'entry_date': '2026-10-05',
        'method': 'transfer',
        'idempotency_key': 'pay-1',
      });
      expect(result.balanceMinor, -2500);

      status = 200; // aynı anahtarla tekrar = aynı kayıt
      final replay = await api.recordFeePayment(
        token: 'tok',
        siteCode: 7,
        apartmentId: 301,
        amountMinor: 123456,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        description: ' Elden ',
        idempotencyKey: 'pay-1',
      );
      expect(rec.lastBody['description'], 'Elden');
      expect(replay.entry.id, 5);
    });

    test('reverseFinanceEntry: neden kırpılır, boşsa gitmez', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'entry': _entry(id: 6, kind: 'reversal', amount: 50000),
        'balance_minor': 0,
      }, 201));
      await api.reverseFinanceEntry(
        token: 'tok',
        siteCode: 7,
        entryId: 5,
        reason: '  Yanlış daire ',
        idempotencyKey: 'rev-1',
      );
      expect(rec.last.url.path, '/manager/sites/7/finance/entries/5/reverse');
      expect(rec.lastBody, <String, dynamic>{'reason': 'Yanlış daire', 'idempotency_key': 'rev-1'});
      await api.reverseFinanceEntry(token: 'tok', siteCode: 7, entryId: 5, reason: '  ');
      expect(rec.lastBody, <String, dynamic>{});
    });

    test('correctFinancePayment: ters kayıt + yeni tahsilat yanıtı', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'reversal': _entry(id: 6, kind: 'reversal', amount: 50000),
        'entry': _entry(id: 7, amount: -40000),
        'balance_minor': 10000,
      }, 201));
      final result = await api.correctFinancePayment(
        token: 'tok',
        siteCode: 7,
        entryId: 5,
        amountMinor: 40000,
        entryDate: DateTime(2026, 10, 6),
        method: PaymentMethod.cheque,
        idempotencyKey: 'cor-1',
      );
      expect(rec.last.url.path, '/manager/sites/7/finance/entries/5/correct');
      expect(rec.lastBody, <String, dynamic>{
        'amount_minor': 40000,
        'entry_date': '2026-10-06',
        'method': 'cheque',
        'idempotency_key': 'cor-1',
      });
      expect(result.reversal!.id, 6);
      expect(result.entry.id, 7);
      expect(result.balanceMinor, 10000);
    });
  });

  group('AuthApi: dönemler', () {
    test('getFinancePeriods; close ve reopen yolu YYYY-AA taşır, 200 başarıdır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'closed_through': '2026-09',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'period': '2026-09', 'closed_at': '2026-10-01T08:00:00Z', 'closed_by_name': 'Ali'},
        ],
        'open_period': '2026-10',
      }));
      final periods = await api.getFinancePeriods(token: 'tok', siteCode: 7);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/finance/periods');
      expect(periods.openPeriod, const FinancePeriod(2026, 10));

      await api.closeFinancePeriod(token: 'tok', siteCode: 7, period: const FinancePeriod(2026, 10));
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/finance/periods/2026-10/close');
      await api.reopenFinancePeriod(token: 'tok', siteCode: 7, period: const FinancePeriod(2026, 9));
      expect(rec.last.url.path, '/manager/sites/7/finance/periods/2026-09/reopen');
    });
  });

  group('hata kodları -> Türkçe mesaj', () {
    const codes = <String>[
      'MODULE_DISABLED',
      'PREVIEW_STALE',
      'PREVIEW_INCOMPLETE',
      'PERIOD_ALREADY_POSTED',
      'PERIOD_CLOSED',
      'PERIOD_NOT_CLOSABLE',
      'PERIOD_NOT_REOPENABLE',
      'DEFINITION_INACTIVE',
      'DEFINITION_LOCKED',
      'ENTRY_ALREADY_REVERSED',
      'ENTRY_NOT_REVERSIBLE',
      'ENTRY_NOT_CORRECTABLE',
      'APARTMENT_HAS_FINANCE',
      'NOTHING_TO_POST',
      'IDEMPOTENCY_CONFLICT',
      'DEFINITION_NOT_FOUND',
      'ENTRY_NOT_FOUND',
      'FORBIDDEN_ROLE',
    ];

    test('her kodun mesajı var; kısa, alt çizgisiz, AHBU / JetPass içermez', () {
      for (final code in codes) {
        final message = AuthApi.messageForErrorCode(code);
        expect(message, isNotNull, reason: code);
        expect(message!.length, lessThan(140), reason: '$code: ${message.length}');
        expect(message.contains('_'), isFalse, reason: code);
        expect(message.toLowerCase().contains('ahbu'), isFalse, reason: code);
        expect(message.toLowerCase().contains('jetpass'), isFalse, reason: code);
        expect(message.contains('minor'), isFalse, reason: code);
      }
    });

    test('belirli mesajlar', () {
      expect(
        AuthApi.messageForErrorCode('PREVIEW_STALE'),
        'Veriler önizlemeden sonra değişti. Önizleme yenilendi; kontrol edip yeniden onaylayın.',
      );
      expect(
        AuthApi.messageForErrorCode('PERIOD_ALREADY_POSTED'),
        'Bu tanım bu dönem için zaten borçlandırılmış. Aynı ay ikinci kez borçlandırılamaz.',
      );
      expect(AuthApi.messageForErrorCode('APARTMENT_HAS_FINANCE'), 'Mali kaydı olan daire silinemez.');
      expect(
        AuthApi.messageForErrorCode('MODULE_DISABLED'),
        'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.',
      );
    });

    test('sunucu yanıtı: kod eşlemesi sunucu metnini ezer (tek, tutarlı Türkçe)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_error('PERIOD_CLOSED', 'Bu dönem kapatılmış; ...'), 409));
      await expectLater(
        api.recordFeePayment(
          token: 'tok',
          siteCode: 7,
          apartmentId: 1,
          amountMinor: 100,
          entryDate: DateTime(2026, 10, 5),
          method: PaymentMethod.cash,
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'PERIOD_CLOSED')
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', AuthApi.messageForErrorCode('PERIOD_CLOSED')),
        ),
      );
    });

    test('INVALID_BODY: Türkçe sunucu metni kullanılır; alan adı jargonu sızmaz', () async {
      final rec = _Recorder();
      var text = 'Gelecek tarihli tahsilat girilemez.';
      final api = _api(rec, (r) => _json(_error('INVALID_BODY', text), 400));
      Future<ApiException> run() async {
        try {
          await api.createFeeDefinition(
            token: 'tok',
            siteCode: 7,
            input: const FeeDefinitionInput(
              name: 'x',
              kind: FeeKind.oneTime,
              distribution: FeeDistribution.equal,
              amountMinor: 1,
              startPeriod: FinancePeriod(2026, 10),
            ),
          );
        } on ApiException catch (e) {
          return e;
        }
        fail('hata bekleniyordu');
      }

      expect((await run()).message, 'Gelecek tarihli tahsilat girilemez.');
      text = 'amount_minor kuruş cinsinden tamsayı olmalıdır.';
      expect((await run()).message, AuthApi.jargonFallbackMessage);
      text = 'Tarih geçersiz (YYYY-AA-GG).';
      expect((await run()).message, AuthApi.jargonFallbackMessage);
    });

    test('INVALID_BODY metinsiz gelirse genel Türkçe yedek metin', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{'code': 'INVALID_BODY'}, 400));
      await expectLater(
        api.getFinanceSummary(token: 'tok', siteCode: 7),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Gönderilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.',
          ),
        ),
      );
    });

    test('403 MODULE_DISABLED: modül kapalı mesajı ve kod korunur', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'error': 'Aidat ve Finans modülü kapalı.',
        'code': 'MODULE_DISABLED',
        'module': 'finance',
      }, 403));
      await expectLater(
        api.listFinanceBalances(token: 'tok', siteCode: 7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'MODULE_DISABLED')
              .having((e) => e.isForbidden, 'forbidden', isTrue),
        ),
      );
    });

    test('429 hız sınırı: bekleme süresi taşınır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'error': 'Çok fazla finans işlemi. Biraz sonra tekrar deneyin.',
        'retry_after_seconds': 90,
      }, 429));
      await expectLater(
        api.reverseFinanceEntry(token: 'tok', siteCode: 7, entryId: 1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isRateLimited, 'rate', isTrue)
              .having((e) => e.retryAfterSeconds, 'retry', 90),
        ),
      );
    });
  });

  group('para bütünlüğü: yazmalar tekrarlanmaz, bozuk veri hata verir', () {
    test('POST isteği 503 alsa da ASLA otomatik yeniden denenmez (çift kayıt riski)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => http.Response('Service Unavailable', 503));
      await expectLater(
        api.recordFeePayment(
          token: 'tok',
          siteCode: 7,
          apartmentId: 1,
          amountMinor: 100,
          entryDate: DateTime(2026, 10, 5),
          method: PaymentMethod.cash,
          idempotencyKey: 'k',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(rec.requests.length, 1);
      rec.requests.clear();
      await expectLater(
        api.postFeeRun(
          token: 'tok',
          siteCode: 7,
          definitionId: 1,
          expectedTotalMinor: 1,
          expectedApartmentCount: 1,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(rec.requests.length, 1);
    });

    test('bakiye okunamayan yanıt "veri işlenemedi" hatasıdır (uydurma 0 YOK)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'apartment_id': 1, 'label': 'A'},
        ],
        'total': 1,
      }));
      await expectLater(
        api.listFinanceBalances(token: 'tok', siteCode: 7),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('islenemedi'))),
      );
      final mineApi = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'apartment_id': 1},
        ],
      }));
      await expectLater(mineApi.getMyFinance(token: 'tok'), throwsA(isA<ApiException>()));
    });
  });

  group('AuthService: finans sarmalayıcıları', () {
    UserSession session0() => UserSession(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: UserRole.siteManager,
      isActive: true,
      token: 'tok-A',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    Future<({AuthService service, _Recorder rec})> makeService(
      FutureOr<http.Response> Function(http.Request request) handler,
    ) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'auth_session': jsonEncode(session0().toJson()),
      });
      final rec = _Recorder();
      final service = AuthService(api: _api(rec, (r) {
        if (r.url.path == '/me') {
          return _json({
            'user': {
              'id': 5,
              'full_name': 'Ali Veli',
              'email': 'ali@example.com',
              'login_name': null,
              'role': UserRole.siteManager.apiValue,
              'is_active': true,
            },
          });
        }
        return handler(r);
      }));
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rec.requests.clear();
      return (service: service, rec: rec);
    }

    test('tüm sarmalayıcılar oturum belirteciyle sözleşmedeki yollara gider', () async {
      final h = await makeService((r) {
        final path = r.url.path;
        if (path.endsWith('/definitions') && r.method == 'GET') {
          return _json(<String, dynamic>{'items': <dynamic>[]});
        }
        if (path.endsWith('/definitions') && r.method == 'POST') return _json(_definition(), 201);
        if (path.contains('/definitions/') && r.method == 'PATCH') return _json(_definition());
        if (path.endsWith('/preview')) return _json(_preview());
        if (path.endsWith('/post') || path.endsWith('/finance/charges')) {
          return _json(<String, dynamic>{
            'run': <String, dynamic>{'id': 1, 'total_minor': 100000, 'apartment_count': 2},
            'entries_count': 2,
          }, 201);
        }
        if (path.endsWith('/balances')) return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
        if (path.endsWith('/account')) {
          return _json(<String, dynamic>{
            'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5'},
            'balance_minor': 0,
            'items': <dynamic>[],
          });
        }
        if (path.endsWith('/payments') || path.endsWith('/reverse')) {
          return _json(<String, dynamic>{'entry': _entry(), 'balance_minor': 0}, 201);
        }
        if (path.endsWith('/correct')) {
          return _json(<String, dynamic>{'reversal': _entry(id: 6), 'entry': _entry(id: 7), 'balance_minor': 0}, 201);
        }
        if (path.endsWith('/periods')) {
          return _json(<String, dynamic>{'closed_through': null, 'items': <dynamic>[], 'open_period': '2026-10'});
        }
        if (path.endsWith('/close') || path.endsWith('/reopen')) {
          return _json(<String, dynamic>{'closed_through': null, 'items': <dynamic>[], 'open_period': '2026-10'});
        }
        if (path.endsWith('/summary')) {
          return _json(<String, dynamic>{
            'open_period': '2026-10',
            'balance_total_minor': 0,
            'debt_total_minor': 0,
            'credit_total_minor': 0,
            'debtor_count': 0,
            'this_period': <String, dynamic>{'charged_minor': 0, 'collected_minor': 0},
          });
        }
        if (path == '/app/my-finance') return _json(<String, dynamic>{'items': <dynamic>[]});
        return _json(<String, dynamic>{});
      });
      final s = h.service;
      void expectCall(String method, String path) {
        expect(h.rec.last.method, method, reason: path);
        expect(h.rec.last.url.path, path);
        expect(h.rec.last.headers['Authorization'], 'Bearer tok-A');
      }

      await s.listFeeDefinitions(7, kind: FeeKind.recurring, active: true);
      expectCall('GET', '/manager/sites/7/finance/definitions');
      expect(h.rec.last.url.queryParameters, <String, String>{'kind': 'recurring', 'active': 'true'});
      await s.createFeeDefinition(
        7,
        const FeeDefinitionInput(
          name: 'A',
          kind: FeeKind.recurring,
          distribution: FeeDistribution.fixed,
          amountMinor: 100,
          dueDay: 5,
          startPeriod: FinancePeriod(2026, 10),
        ),
      );
      expectCall('POST', '/manager/sites/7/finance/definitions');
      await s.updateFeeDefinition(7, 7, <String, Object?>{'name': 'B'});
      expectCall('PATCH', '/manager/sites/7/finance/definitions/7');
      await s.previewFeeRun(7, 7, period: const FinancePeriod(2026, 10));
      expectCall('POST', '/manager/sites/7/finance/definitions/7/preview');
      await s.postFeeRun(
        7,
        7,
        period: const FinancePeriod(2026, 10),
        expectedTotalMinor: 100000,
        expectedApartmentCount: 2,
        idempotencyKey: 'k',
      );
      expectCall('POST', '/manager/sites/7/finance/definitions/7/post');
      expect(h.rec.lastBody['expected_total_minor'], 100000);
      const charge = ExtraChargeInput(name: 'E', distribution: FeeDistribution.equal, amountMinor: 100);
      await s.previewExtraCharge(7, charge);
      expectCall('POST', '/manager/sites/7/finance/charges/preview');
      await s.postExtraCharge(7, charge, expectedTotalMinor: 100, expectedApartmentCount: 1);
      expectCall('POST', '/manager/sites/7/finance/charges');
      await s.listFinanceBalances(7, status: 'credit', query: 'a');
      expectCall('GET', '/manager/sites/7/finance/balances');
      await s.getFinanceAccount(7, 301, beforeId: 3);
      expectCall('GET', '/manager/sites/7/finance/apartments/301/account');
      await s.recordFeePayment(
        7,
        apartmentId: 301,
        amountMinor: 5000,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        idempotencyKey: 'p',
      );
      expectCall('POST', '/manager/sites/7/finance/payments');
      await s.reverseFinanceEntry(7, 5, reason: 'x', idempotencyKey: 'r');
      expectCall('POST', '/manager/sites/7/finance/entries/5/reverse');
      await s.correctFinancePayment(
        7,
        5,
        amountMinor: 100,
        entryDate: DateTime(2026, 10, 5),
        method: PaymentMethod.cash,
        idempotencyKey: 'c',
      );
      expectCall('POST', '/manager/sites/7/finance/entries/5/correct');
      await s.getFinancePeriods(7);
      expectCall('GET', '/manager/sites/7/finance/periods');
      await s.closeFinancePeriod(7, const FinancePeriod(2026, 10));
      expectCall('POST', '/manager/sites/7/finance/periods/2026-10/close');
      await s.reopenFinancePeriod(7, const FinancePeriod(2026, 10));
      expectCall('POST', '/manager/sites/7/finance/periods/2026-10/reopen');
      await s.getFinanceSummary(7);
      expectCall('GET', '/manager/sites/7/finance/summary');
      await s.getMyFinance();
      expectCall('GET', '/app/my-finance');
    });

    test('oturum yokken Türkçe ApiException ve ağ isteği yapılmaz', () async {
      final rec = _Recorder();
      final loggedOut = AuthService(api: _api(rec, (r) => _json(<String, dynamic>{})));
      await expectLater(
        loggedOut.getMyFinance(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Oturum açmanız gerekmektedir.')),
      );
      await expectLater(loggedOut.getFinanceSummary(7), throwsA(isA<ApiException>()));
      expect(rec.requests, isEmpty);
    });
  });
}
