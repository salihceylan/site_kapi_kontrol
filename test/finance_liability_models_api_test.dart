// Kiracı borcunun malike devri (K1) ve gecikmede öneri (K17): modeller + Finance4bApi uçları (docs/PLATFORM_FINANS.md
// "Kiracı borcunun malike devri"). MockClient ile: uç yolları, HTTP yöntemleri, gövdeler (tutarlar KURUŞ tamsayı), Bearer başlığı,
// 200/201 (idempotent tekrar) ayrımı, bozuk yanıtın sessiz 0 yerine hata vermesi ve yazma isteklerinin ASLA yeniden denenmemesi.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/models/finance_liability.dart';
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

Map<String, dynamic> _candidate({String reason = 'overdue'}) => <String, dynamic>{
  'apartment_id': 301,
  'unit_label': 'Daire 5',
  'block_name': 'A Blok',
  'reason': reason,
  'tenant_present': reason == 'overdue',
  'has_owner': true,
  'can_transfer': true,
  'item_count': 2,
  'total_minor': 150000,
  'oldest_due_date': '2026-08-10',
};

Map<String, dynamic> _transfer({String kind = 'transfer', bool reversible = true}) => <String, dynamic>{
  'id': 7,
  'apartment_id': 301,
  'kind': kind,
  'from_party': 'tenant',
  'to_party': 'owner',
  'total_minor': 150000,
  'item_count': 2,
  'reason': 'Kiracı taşındı',
  'reverses_transfer_id': kind == 'reversal' ? 6 : null,
  'reversed_by_transfer_id': null,
  'created_by_name': 'Yönetici',
  'created_at': '2026-10-29T09:00:00.000Z',
  'reversible': reversible,
};

void main() {
  const token = 'tok';

  group('modeller', () {
    test('aday sayfası: daire, neden, tutar (kuruş), en eski vade; kişi adı alanı yok; kesilmiş liste işareti', () {
      final page = LiabilityCandidatePage.fromJson(<String, dynamic>{
        'items': <dynamic>[_candidate(), _candidate(reason: 'exited')],
        'count': 2,
        'total_minor': 300000,
        'truncated': true,
      });
      expect(page.count, 2);
      expect(page.totalMinor, 300000);
      expect(page.truncated, isTrue);
      final first = page.items.first;
      expect(first.apartmentId, 301);
      expect(first.title, 'A Blok / Daire 5');
      expect(first.reason, LiabilityReason.overdue);
      expect(first.tenantPresent, isTrue);
      expect(first.canTransfer, isTrue);
      expect(first.itemCount, 2);
      expect(first.totalMinor, 150000);
      expect(first.oldestDueDate, DateTime(2026, 8, 10));
      expect(page.items.last.reason, LiabilityReason.exited);
      // eski / eksik yanıt: boş sayfa, kesilmemiş
      final empty = LiabilityCandidatePage.fromJson(const <String, dynamic>{});
      expect(empty.items, isEmpty);
      expect(empty.truncated, isFalse);
    });

    test('aday satırında tutar ya da daire kimliği okunamazsa sessiz 0 değil FormatException', () {
      expect(() => LiabilityCandidate.fromJson(<String, dynamic>{..._candidate(), 'total_minor': null}), throwsFormatException);
      expect(() => LiabilityCandidate.fromJson(<String, dynamic>{..._candidate(), 'total_minor': 12.5}), throwsFormatException);
      expect(() => LiabilityCandidate.fromJson(<String, dynamic>{..._candidate(), 'apartment_id': null}), throwsFormatException);
    });

    test('önizleme: kalemler (kalan / ödenen), tazminat istisnası, özet ve bakiyeler; özet yoksa FormatException', () {
      final preview = LiabilityPreview.fromJson(<String, dynamic>{
        'apartment_id': 301,
        'has_owner': true,
        'can_transfer': true,
        'items': <dynamic>[
          <String, dynamic>{'entry_id': 11, 'name': 'Ağustos aidatı', 'due_date': '2026-08-10', 'original_minor': 100000, 'remaining_minor': 50000, 'paid_minor': 50000, 'fund': 'capital'},
        ],
        'excluded_late_fee': <dynamic>[
          <String, dynamic>{'entry_id': 13, 'name': 'Gecikme tazminatı', 'due_date': '2026-09-30', 'remaining_minor': 2500},
        ],
        'item_count': 1,
        'total_minor': 50000,
        'preview_hash': 'a' * 64,
        'tenant_balance_minor': 52500,
        'owner_balance_minor': 0,
      });
      expect(preview.itemCount, 1);
      expect(preview.items.single.remainingMinor, 50000);
      expect(preview.items.single.paidMinor, 50000);
      expect(preview.items.single.fund, 'capital');
      expect(preview.excludedLateFee.single.remainingMinor, 2500);
      expect(preview.excludedLateFeeMinor, 2500);
      expect(preview.totalMinor, 50000);
      expect(preview.previewHash, 'a' * 64);
      expect(preview.tenantBalanceMinor, 52500);
      expect(preview.ownerBalanceMinor, 0);
      expect(preview.isEmpty, isFalse);
      expect(
        () => LiabilityPreview.fromJson(<String, dynamic>{'apartment_id': 301, 'items': <dynamic>[], 'total_minor': 0}),
        throwsFormatException,
        reason: 'onay özeti olmadan devir yapılamaz',
      );
    });

    test('devir kaydı: tür, kim / ne zaman / ne kadar / neden, geri alınabilirlik; geri alma kaydı ayrı', () {
      final transfer = LiabilityTransfer.fromJson(_transfer());
      expect(transfer.id, 7);
      expect(transfer.isReversal, isFalse);
      expect(transfer.totalMinor, 150000);
      expect(transfer.itemCount, 2);
      expect(transfer.reason, 'Kiracı taşındı');
      expect(transfer.createdByName, 'Yönetici');
      expect(transfer.createdAt, isNotNull);
      expect(transfer.reversible, isTrue);
      expect(transfer.isReversed, isFalse);
      final reversal = LiabilityTransfer.fromJson(_transfer(kind: 'reversal', reversible: false));
      expect(reversal.isReversal, isTrue);
      expect(reversal.reversesTransferId, 6);
      final reversed = LiabilityTransfer.fromJson(<String, dynamic>{..._transfer(reversible: false), 'reversed_by_transfer_id': 8});
      expect(reversed.isReversed, isTrue);
    });

    test('dikkat satırı: at_least işareti okunur; yoksa false (eski sunucu)', () {
      expect(FinanceHomeAttention.fromJson(<String, dynamic>{'key': 'tenant_debt_overdue_transfer', 'count': 500, 'at_least': true}).atLeast, isTrue);
      expect(FinanceHomeAttention.fromJson(<String, dynamic>{'key': 'tenant_debt_overdue_transfer', 'count': 3}).atLeast, isFalse);
    });
  });

  group('uçlar', () {
    test('listLiabilityCandidates: GET …/liability-transfer/candidates, Bearer başlığı', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'items': <dynamic>[_candidate()], 'count': 1, 'total_minor': 150000, 'truncated': false}));
      final page = await api.listLiabilityCandidates(token: token, siteCode: 11);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/11/finance/liability-transfer/candidates');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(page.items.single.apartmentId, 301);
    });

    test('previewLiabilityTransfer: GET …/apartments/:id/liability-transfer/preview (yazmaz)', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'apartment_id': 301,
        'has_owner': true,
        'can_transfer': true,
        'items': <dynamic>[],
        'excluded_late_fee': <dynamic>[],
        'item_count': 0,
        'total_minor': 0,
        'preview_hash': 'b' * 64,
      }));
      final preview = await api.previewLiabilityTransfer(token: token, siteCode: 11, apartmentId: 301);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/11/finance/apartments/301/liability-transfer/preview');
      expect(preview.previewHash, 'b' * 64);
    });

    test('createLiabilityTransfer: POST gövdesi kesin alanlar (kuruş tamsayı, özet, kırpılmış neden, işlem anahtarı); 201 yeni, 200 aynı kayıt', () async {
      final rec = _Rec();
      var status = 201;
      final api = _api(rec, (r) => _json(<String, dynamic>{'transfer': _transfer(), 'tenant_balance_minor': 0, 'owner_balance_minor': 150000}, status));
      final created = await api.createLiabilityTransfer(
        token: token,
        siteCode: 11,
        apartmentId: 301,
        expectedTotalMinor: 150000,
        expectedHash: 'c' * 64,
        reason: '  Kiracı taşındı  ',
        idempotencyKey: 'liab-1',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/apartments/301/liability-transfer');
      expect(rec.body, <String, dynamic>{
        'expected_total_minor': 150000,
        'expected_hash': 'c' * 64,
        'reason': 'Kiracı taşındı',
        'idempotency_key': 'liab-1',
      });
      expect(created.replayed, isFalse);
      expect(created.transfer.id, 7);
      expect(created.ownerBalanceMinor, 150000);
      status = 200;
      final again = await api.createLiabilityTransfer(
        token: token,
        siteCode: 11,
        apartmentId: 301,
        expectedTotalMinor: 150000,
        expectedHash: 'c' * 64,
        reason: 'Kiracı taşındı',
        idempotencyKey: 'liab-1',
      );
      expect(again.replayed, isTrue, reason: 'aynı anahtar = aynı kayıt (çift kayıt yok)');
    });

    test('listLiabilityTransfers: GET …/liability-transfers -> items; reverseLiabilityTransfer: POST …/liability-transfers/:id/reverse { reason, idempotency_key }', () async {
      final rec = _Rec();
      final api = _api(rec, (r) {
        if (r.method == 'GET') return _json(<String, dynamic>{'items': <dynamic>[_transfer(), _transfer(kind: 'reversal', reversible: false)]});
        return _json(<String, dynamic>{'transfer': _transfer(kind: 'reversal', reversible: false), 'tenant_balance_minor': 150000, 'owner_balance_minor': 0}, 201);
      });
      final items = await api.listLiabilityTransfers(token: token, siteCode: 11, apartmentId: 301);
      expect(rec.last.url.path, '/manager/sites/11/finance/apartments/301/liability-transfers');
      expect(items.map((t) => t.isReversal).toList(), <bool>[false, true]);
      final result = await api.reverseLiabilityTransfer(token: token, siteCode: 11, transferId: 7, reason: ' Yanlış daire ', idempotencyKey: 'liabrev-1');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/11/finance/liability-transfers/7/reverse');
      expect(rec.body, <String, dynamic>{'reason': 'Yanlış daire', 'idempotency_key': 'liabrev-1'});
      expect(result.transfer.isReversal, isTrue);
      expect(result.tenantBalanceMinor, 150000);
    });

    test('sunucu hatası ApiException olur (409 bayat önizleme kodu korunur); yazma isteği yeniden denenmez; bozuk yanıt Türkçe hata verir', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(<String, dynamic>{'error': 'Kiracı borçları önizlemeden sonra değişti. Önizlemeyi yenileyip tekrar inceleyin.', 'code': 'LIABILITY_TRANSFER_CHANGED'}, 409));
      Object? caught;
      try {
        await api.createLiabilityTransfer(token: token, siteCode: 11, apartmentId: 301, expectedTotalMinor: 1, expectedHash: 'd' * 64, reason: 'x', idempotencyKey: 'k');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ApiException>());
      expect((caught as ApiException).code, 'LIABILITY_TRANSFER_CHANGED');
      expect(caught.statusCode, 409);
      expect(rec.requests.length, 1, reason: 'yazma isteği ASLA otomatik yeniden denenmez');

      final broken = _api(_Rec(), (r) => _json(<String, dynamic>{'apartment_id': 301, 'items': <dynamic>[], 'total_minor': 0}));
      await expectLater(broken.previewLiabilityTransfer(token: token, siteCode: 11, apartmentId: 301), throwsA(isA<ApiException>()));
    });
  });
}
