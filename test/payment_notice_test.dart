// Dekont bildirimi (2B): dosya tanıma / hazırlık, model ayrıştırma, sakin penceresi (doğrulama + gönderim sırası), karşılaştırma penceresi (önemli uyarı varken onay
// pasif; onay gövdesi), "İnceleniyor" satırı. Ağ yok: sahte API.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_text_reader.dart' show DocumentTextReader;
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
  FinanceFund? approveFund;
  Object? approveError;
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
    FinanceFund? fund,
    bool bookInOpenPeriod = false,
    List<String> acknowledged = const <String>[],
  }) async {
    calls.add('approve');
    acknowledgedSent = acknowledged;
    approveFund = fund;
    approveBody = <String, dynamic>{'account_id': accountId, 'account_party': accountParty, 'book': bookInOpenPeriod, 'fund': fund?.apiValue};
    final error = approveError;
    if (error != null) {
      approveError = null; // yalnız ilk deneme reddedilir
      throw error;
    }
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

/// K3: sahte `GET payments/fund-choice` yükleyicisi (sunucu biçimi). [calls] her çağrının daire / hesap bilgisini kaydeder.
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

_FundLoader _loaderOf(Map<String, dynamic> body, {List<Map<String, Object?>>? calls}) =>
    ({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn}) async {
      calls?.add(<String, Object?>{'apartment_id': apartmentId, 'account_party': accountParty?.apiValue, 'amount_minor': amountMinor});
      return FundChoiceInfo.tryParse(<String, dynamic>{...body, 'account_party': accountParty?.apiValue ?? body['account_party']})!;
    };

/// Sahte cihaz içi metin okuyucu (P2-13): her zaman desteklenir, verilen metni döndürür.
class _FakeOcr implements DocumentTextReader {
  _FakeOcr(this.text);

  final String text;

  @override
  bool get supported => true;

  @override
  Future<String?> read(Uint8List imageBytes) async => text;
}

String _amountText(WidgetTester t) =>
    t.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey<String>('notice_amount')), matching: find.byType(EditableText))).controller.text;

bool _selected(WidgetTester t, String key) => find
    .descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byIcon(Icons.radio_button_checked_rounded))
    .evaluate()
    .isNotEmpty;

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
      // PDF'te "Görselden oku" çizilmez; form eski haliyle çalışır.
      expect(find.byKey(const ValueKey<String>('notice_ocr_read')), findsNothing);
    });

    testWidgets('görselden oku: öneri dokunulmadan forma yazılmaz; dokunulan tutar ve tarih gönderilir', (t) async {
      final auth = FakeBulkAuth(role: UserRole.apartmentOwner);
      final api = _FakeApi();
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      final jpeg = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
      await _show(
        t,
        PaymentNoticeDialog(
          authService: auth,
          choices: const <NoticeApartmentChoice>[NoticeApartmentChoice(apartmentId: 7, label: 'Gül Sitesi - A Blok 3')],
          amountMinor: 125000,
          pickFile: () async => SharedReceipt(name: 'dekont.jpg', mime: 'image/jpeg', bytes: jpeg),
          now: () => DateTime(2026, 10, 21, 12),
          ocrReader: _FakeOcr('İşlem Tarihi: 15.10.2026 14:32\nTutar: 1.250,50 TL'),
        ),
      );
      // Dosya seçilmeden düğme yok.
      expect(find.byKey(const ValueKey<String>('notice_ocr_read')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('notice_pick')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('notice_ocr_read')));
      await t.pumpAndSettle();
      // Öneri göründü ama alanlar değişmedi.
      expect(find.byKey(const ValueKey<String>('notice_ocr_amount_0')), findsOneWidget);
      expect(_amountText(t), '1.250,00');
      expect(find.text('Ödeme tarihi: 21.10.2026'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey<String>('notice_ocr_amount_0')));
      await t.tap(find.byKey(const ValueKey<String>('notice_ocr_date_0')));
      await t.pumpAndSettle();
      expect(_amountText(t), '1.250,50');
      expect(find.text('Ödeme tarihi: 15.10.2026'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('notice_submit')));
      await t.pumpAndSettle();
      expect(api.createBody!['amount_minor'], 125050);
      expect(api.createBody!['paid_on'], '2026-10-15');
    });
  });

  group('karşılaştırma penceresi', () {
    PeopleScope scopeOf(FakeBulkAuth auth) => PeopleScope(authService: auth, siteCode: 1, siteName: 'Gül', canWrite: true);

    testWidgets('önemli uyarı varken onay pasif; işaretlenince açılır ve uyarı kodu gönderilir', (t) async {
      final auth = FakeBulkAuth();
      final api = _FakeApi(warnings: <Map<String, dynamic>>[<String, dynamic>{'code': 'SAME_FILE_OTHER_NOTICE', 'level': 'strong'}]);
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      await _show(t, PaymentNoticeReviewDialog(scope: scopeOf(auth), noticeId: 5, accountsLoader: (_) async => const <CashAccount>[], fundChoiceLoader: _loaderOf(_fundBody())));
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
      await _show(t, PaymentNoticeReviewDialog(scope: scopeOf(auth), noticeId: 5, accountsLoader: (_) async => const <CashAccount>[], fundChoiceLoader: _loaderOf(_fundBody())));
      await t.tap(find.byKey(const ValueKey<String>('notice_review_approve')));
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve']);
    });
  });

  // K3 (P1-3): dekont onayı da İşletme / Fon hesabı seçimine tabidir (yazılım ödemeyi kendiliğinden atamaz).
  group('karşılaştırma penceresi: İşletme / Fon hesabı (K3)', () {
    PeopleScope scopeOf(FakeBulkAuth auth) => PeopleScope(authService: auth, siteCode: 1, siteName: 'Gül', canWrite: true);
    final approveKey = find.byKey(const ValueKey<String>('notice_review_approve'));

    Future<_FakeApi> open(WidgetTester t, _FundLoader loader) async {
      final auth = FakeBulkAuth();
      final api = _FakeApi();
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      await _show(t, PaymentNoticeReviewDialog(scope: scopeOf(auth), noticeId: 5, accountsLoader: (_) async => const <CashAccount>[], fundChoiceLoader: loader));
      return api;
    }

    testWidgets('iki tür borç: seçim ZORUNLU — seçilmeden onay sunucuya GİTMEZ; seçilince fund gider', (t) async {
      final api = await open(t, _loaderOf(_fundBody(operating: 100000, capital: 300000)));
      expect(find.byKey(const ValueKey<String>('notice_fund_required')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notice_fund_auto')), findsNothing, reason: 'iki türde Otomatik yok');
      expect(_selected(t, 'notice_fund_operating'), isFalse);
      expect(_selected(t, 'notice_fund_capital'), isFalse);
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.calls, isEmpty, reason: 'seçim yokken onay gitmemeli');
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('notice_fund_capital')));
      await t.pumpAndSettle();
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsNothing);
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve']);
      expect(api.approveFund, FinanceFund.capital);
    });

    testWidgets('tek tür borç: önerilen hesap seçili gelir ve onayda o hesap gider; değiştirilebilir', (t) async {
      final api = await open(t, _loaderOf(_fundBody(operating: 100000)));
      expect(_selected(t, 'notice_fund_operating'), isTrue);
      expect(find.byKey(const ValueKey<String>('notice_fund_auto')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('notice_fund_capital')));
      await t.pumpAndSettle();
      expect(_selected(t, 'notice_fund_capital'), isTrue);
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.approveFund, FinanceFund.capital);
    });

    testWidgets('tek tür borç, seçim değiştirilmezse: önerilen hesap gider', (t) async {
      final api = await open(t, _loaderOf(_fundBody(capital: 50000)));
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.approveFund, FinanceFund.capital);
    });

    testWidgets('açık borç yok: seçim zorunlu değil; seçilmeden onay (fund gövdede yok)', (t) async {
      final api = await open(t, _loaderOf(_fundBody()));
      expect(find.byKey(const ValueKey<String>('notice_fund_auto')), findsOneWidget);
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve']);
      expect(api.approveFund, isNull);
    });

    testWidgets('bayat bilgi: sunucu 400 FUND_CHOICE_REQUIRED verirse panel zorunlu kipe geçer; seçince onay yazılır', (t) async {
      final api = await open(t, _loaderOf(_fundBody()));
      api.approveError = ApiException(
        'Bu hesapta hem İşletme hem Fon için açık borç var.',
        statusCode: 400,
        code: 'FUND_CHOICE_REQUIRED',
        payload: <String, dynamic>{'code': 'FUND_CHOICE_REQUIRED', 'fund_choice': _fundBody(operating: 100000, capital: 300000)},
      );
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve'], reason: 'gönderildi ve sunucu reddetti');
      expect(find.byKey(const ValueKey<String>('notice_fund_required')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notice_fund_auto')), findsNothing);
      expect(find.text('Ödemenin işleneceği İşletme / Fon hesabını seçin.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('notice_fund_operating')));
      await t.pumpAndSettle();
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.calls, <String>['approve', 'approve']);
      expect(api.approveFund, FinanceFund.operating);
    });

    testWidgets('daire hesabı (ev sahibi / kiracı) değişince bilgi yeniden okunur ve eski seçim geçmez', (t) async {
      final calls = <Map<String, Object?>>[];
      final api = await open(t, _loaderOf(_fundBody(operating: 100000), calls: calls));
      expect(_selected(t, 'notice_fund_operating'), isTrue);
      expect(calls.single['account_party'], 'owner');
      await t.tap(find.byKey(const ValueKey<String>('notice_party')));
      await t.pumpAndSettle();
      await t.tap(find.text('Kiracı hesabı').last);
      await t.pumpAndSettle();
      expect(calls.map((c) => c['account_party']), <String?>['owner', 'tenant']);
      expect(_selected(t, 'notice_fund_operating'), isTrue, reason: 'yeni hesabın önerisi yeniden seçili gelir');
      await t.tap(approveKey);
      await t.pumpAndSettle();
      expect(api.approveBody!['account_party'], 'tenant');
      expect(api.approveFund, FinanceFund.operating);
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
