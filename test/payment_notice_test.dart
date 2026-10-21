// Dekont bildirimi (2B): dosya tanıma / hazırlık, model ayrıştırma, sakin penceresi (doğrulama + gönderim sırası), karşılaştırma penceresi (önemli uyarı varken onay
// pasif; onay gövdesi), "İnceleniyor" satırı. Ağ yok: sahte API.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/services/payment_notice_file.dart';
import 'package:site_kapi_kontrol/services/share_inbox.dart';
import 'package:site_kapi_kontrol/ui/dialogs/payment_notice_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/payment_notice_review_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/payment_notice_status.dart';

import 'bulk_fakes.dart';

Map<String, dynamic> _noticeJson({String status = 'pending', int id = 5}) => <String, dynamic>{
  'id': id,
  'site_code': 1,
  'apartment_id': 7,
  'apartment_label': 'A Blok - 3',
  'account_party': 'owner',
  'origin': 'resident_app',
  'status': status,
  'amount_minor': 125000,
  'paid_on': '2026-10-20',
  'method': 'transfer',
  'sender_name': 'Ayşe Yılmaz',
  'description': 'GUL-A2',
  'has_file': false,
  'submitted_at': '2026-10-20T10:00:00Z',
  'unseen_decision': status != 'pending',
  'reject_reason_text': status == 'rejected' ? 'Ödeme başka bir daire için yapılmış görünüyor.' : null,
};

class _FakeApi extends PaymentNoticeApi {
  _FakeApi({this.warnings = const <Map<String, dynamic>>[]}) : super(baseUrl: 'http://localhost');

  final List<Map<String, dynamic>> warnings;
  final calls = <String>[];
  Map<String, dynamic>? createBody;
  Map<String, dynamic>? approveBody;
  Uint8List? uploaded;
  List<String> acknowledgedSent = const <String>[];

  @override
  Future<NoticeDetail> detail({required String token, required int siteCode, required int id}) async => NoticeDetail.fromJson(<String, dynamic>{
    'notice': _noticeJson(id: id),
    'apartment': <String, dynamic>{
      'people': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Ayşe Yılmaz', 'relation': 'owner'},
      ],
      'balances': <String, dynamic>{
        'owner': <String, dynamic>{'balance_minor': 125000},
        'tenant': <String, dynamic>{'balance_minor': 0},
      },
      'recent_payments': <Map<String, dynamic>>[
        <String, dynamic>{'id': 9, 'entry_date': '2026-10-19', 'amount_minor': 125000, 'account_party': 'owner'},
      ],
    },
    'warnings': warnings,
  });

  @override
  Future<Map<String, dynamic>> approve({
    required String token,
    required int siteCode,
    required int id,
    int? accountId,
    String? accountParty,
    bool bookInOpenPeriod = false,
    List<String> acknowledged = const <String>[],
  }) async {
    calls.add('approve');
    acknowledgedSent = acknowledged;
    approveBody = <String, dynamic>{'account_id': accountId, 'account_party': accountParty, 'book': bookInOpenPeriod};
    return <String, dynamic>{};
  }

  @override
  Future<NoticeCreated> createMine({required String token, required Map<String, dynamic> body}) async {
    calls.add('create');
    createBody = body;
    return NoticeCreated.fromJson(<String, dynamic>{
      'notice': _noticeJson(status: 'uploading'),
      'upload': <String, dynamic>{'path': '/app/my-finance/payment-notices/5/content'},
    });
  }

  @override
  Future<PaymentNotice> putMineContent({required String token, required int id, required Uint8List bytes}) async {
    calls.add('put');
    uploaded = bytes;
    return PaymentNotice.fromJson(_noticeJson());
  }

  @override
  Future<MyNotices> listMine({required String token, int? apartmentId}) async => MyNotices.fromJson(<String, dynamic>{
    'items': <Map<String, dynamic>>[_noticeJson(), _noticeJson(status: 'rejected', id: 6)],
    'pending_total_minor': 125000,
  });
}

Future<void> _show(WidgetTester t, Widget dialog) async {
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: TextButton(onPressed: () => showDialog<void>(context: ctx, builder: (_) => dialog), child: const Text('aç'))))));
  await t.tap(find.text('aç'));
  await t.pumpAndSettle();
}

void main() {
  group('dosya hazırlığı', () {
    test('tür içerik imzasından anlaşılır', () {
      expect(sniffNoticeMime(Uint8List.fromList('%PDF-1.7 x'.codeUnits)), 'application/pdf');
      expect(sniffNoticeMime(Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0])), 'image/jpeg');
      expect(sniffNoticeMime(Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0])), 'image/png');
      expect(sniffNoticeMime(Uint8List.fromList('<html>'.codeUnits)), isNull);
    });

    test('PDF olduğu gibi gider; 10 MB üstü ve tanınmayan tür reddedilir', () async {
      final pdf = Uint8List.fromList('%PDF-1.7 icerik'.codeUnits);
      final ready = await prepareNoticeFile('C:\\x\\Dekont Ekim.PDF', pdf);
      expect(ready.mime, 'application/pdf');
      expect(ready.name, 'Dekont Ekim.pdf');
      expect(ready.bytes, pdf);
      final big = Uint8List(kNoticeMaxBytes + 1)..setAll(0, '%PDF-'.codeUnits);
      await expectLater(prepareNoticeFile('a.pdf', big), throwsA(isA<NoticeFileException>()));
      await expectLater(prepareNoticeFile('a.exe', Uint8List.fromList('MZ......'.codeUnits)), throwsA(isA<NoticeFileException>()));
      await expectLater(prepareNoticeFile('a.pdf', Uint8List(0)), throwsA(isA<NoticeFileException>()));
    });
  });

  group('model', () {
    test('bildirim, uyarılar ve toplu sonuç ayrıştırılır', () {
      final detail = NoticeDetail.fromJson(<String, dynamic>{
        'notice': _noticeJson(),
        'apartment': <String, dynamic>{'balances': <String, dynamic>{'owner': <String, dynamic>{'balance_minor': 5}}},
        'warnings': <Map<String, dynamic>>[
          <String, dynamic>{'code': 'POSSIBLE_DUPLICATE', 'level': 'strong'},
          <String, dynamic>{'code': 'OLD_DATE', 'level': 'info'},
        ],
      });
      expect(detail.notice.amountMinor, 125000);
      expect(detail.notice.status, NoticeStatus.pending);
      expect(detail.ownerBalanceMinor, 5);
      expect(detail.strongWarnings.map((w) => w.code), <String>['POSSIBLE_DUPLICATE']);
      expect(parseBulkResults(<String, dynamic>{
        'results': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'ok': true},
          <String, dynamic>{'id': 2, 'ok': false, 'code': 'NOTICE_WARNINGS_UNACKNOWLEDGED'},
        ],
      }).where((r) => !r.ok).length, 1);
    });

    test('işlem anahtarı 64 karakteri aşmaz ve her seferinde farklıdır', () {
      final a = newNoticeKey();
      expect(a.length, lessThanOrEqualTo(64));
      expect(RegExp(r'^[\x21-\x7e]+$').hasMatch(a), isTrue);
      expect(newNoticeKey(), isNot(a));
    });
  });

  group('sakin penceresi', () {
    testWidgets('dosya yokken gönderilmez; dosya + tutar varken önce kayıt sonra dosya gider', (t) async {
      final auth = FakeBulkAuth(role: UserRole.apartmentOwner);
      final api = _FakeApi();
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      final pdf = Uint8List.fromList('%PDF-1.7 icerik'.codeUnits);
      await _show(
        t,
        PaymentNoticeDialog(
          authService: auth,
          choices: const <NoticeApartmentChoice>[NoticeApartmentChoice(apartmentId: 7, label: 'Gül Sitesi - A Blok 3', reference: 'GUL-A2-1026')],
          amountMinor: 125000,
          pickFile: () async => SharedReceipt(name: 'dekont.pdf', mime: 'application/pdf', bytes: pdf),
          now: () => DateTime(2026, 10, 21, 12),
        ),
      );
      expect(find.byKey(const ValueKey<String>('notice_privacy')), findsOneWidget);
      // referans kodu açıklamada hazır gelir
      expect(find.widgetWithText(TextFormField, 'GUL-A2-1026'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('notice_submit')));
      await t.pumpAndSettle();
      expect(find.text('Önce dekontu seçin.'), findsOneWidget);
      expect(api.calls, isEmpty);

      await t.tap(find.byKey(const ValueKey<String>('notice_pick')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('notice_submit')));
      await t.pumpAndSettle();
      expect(api.calls, <String>['create', 'put']);
      expect(api.createBody!['amount_minor'], 125000);
      expect(api.createBody!['paid_on'], '2026-10-21');
      expect((api.createBody!['file'] as Map)['content_type'], 'application/pdf');
      expect((api.createBody!['idempotency_key'] as String).isNotEmpty, isTrue);
      expect(api.uploaded, pdf);
    });
  });

  group('karşılaştırma penceresi', () {
    PeopleScope scopeOf(FakeBulkAuth auth) => PeopleScope(authService: auth, siteCode: 1, siteName: 'Gül', canWrite: true);

    testWidgets('önemli uyarı varken onay pasif; işaretlenince açılır ve uyarı kodu gönderilir', (t) async {
      final auth = FakeBulkAuth();
      final api = _FakeApi(warnings: <Map<String, dynamic>>[<String, dynamic>{'code': 'SAME_FILE_OTHER_NOTICE', 'level': 'strong'}]);
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      await _show(t, PaymentNoticeReviewDialog(scope: scopeOf(auth), noticeId: 5, accountsLoader: (_) async => const <CashAccount>[]));
      final approve = find.byKey(const ValueKey<String>('notice_review_approve'));
      expect(approve, findsOneWidget);
      expect(t.widget<StatefulWidget>(find.byType(PaymentNoticeReviewDialog)), isNotNull);
      await t.tap(approve, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(api.calls, isEmpty, reason: 'uyarı işaretlenmeden onay gitmemeli');

      await t.tap(find.byKey(const ValueKey<String>('notice_warning_SAME_FILE_OTHER_NOTICE')));
      await t.pumpAndSettle();
      await t.tap(approve);
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve']);
      expect(api.acknowledgedSent, <String>['SAME_FILE_OTHER_NOTICE']);
      expect(api.approveBody!['account_party'], 'owner');
    });

    testWidgets('uyarı yoksa onay doğrudan açık; bilgi uyarısı onayı engellemez', (t) async {
      final auth = FakeBulkAuth();
      final api = _FakeApi(warnings: <Map<String, dynamic>>[<String, dynamic>{'code': 'OLD_DATE', 'level': 'info'}]);
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      await _show(t, PaymentNoticeReviewDialog(scope: scopeOf(auth), noticeId: 5, accountsLoader: (_) async => const <CashAccount>[]));
      await t.tap(find.byKey(const ValueKey<String>('notice_review_approve')));
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve']);
    });
  });

  group('İnceleniyor satırı', () {
    testWidgets('bekleyen tutar ve iptal nedeni gösterilir', (t) async {
      final auth = FakeBulkAuth(role: UserRole.apartmentOwner);
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: _FakeApi(), tokenProvider: () => 'tok'));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PaymentNoticeStatusLine(authService: auth, apartmentId: 7))));
      await t.pumpAndSettle();
      expect(find.textContaining('İnceleniyor: 1.250,00'), findsOneWidget);
      expect(find.textContaining('başka bir daire için yapılmış'), findsOneWidget);
    });
  });
}
