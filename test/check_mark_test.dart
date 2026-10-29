// Kontrol izi (P2-20): "Kontrol edildi - <kim>, <tarih>" rozeti, yönetici için işaretleme düğmesi, kurulda salt okuma, hata yolu ve model ayrıştırma.
// Muhasebeci rolü yok: işareti siteyi yöneten koyar/kaldırır. Dekont karşılaştırma penceresinde iz, karar akışından ayrı çalışır (pencere kapanmaz).
// Ağ yok: sahte API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/check_mark.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/payment_notice_review_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/check_mark_panel.dart';

import 'bulk_fakes.dart';

// 10:30 UTC = 13:30 İstanbul (UTC+3, yaz saati yok).
final DateTime _at = DateTime.utc(2026, 10, 29, 10, 30);
const String _atText = '29.10.2026 13:30';
final CheckMark _mark = CheckMark(at: _at, byName: 'Ayşe Yönetici');

Finder get _toggle => find.byKey(const ValueKey<String>('check_mark_toggle'));

Future<void> _pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(900, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child)))));
}

void main() {
  group('model', () {
    test('iz yoksa ya da tarih okunamıyorsa null (kontrolsüz); eski sunucu alanları hiç göndermez', () {
      expect(CheckMark.tryParse(<String, dynamic>{}), isNull);
      expect(CheckMark.tryParse(<String, dynamic>{'checked_at': null, 'checked_by_name': 'x'}), isNull);
      expect(CheckMark.tryParse(<String, dynamic>{'checked_at': 'bozuk'}), isNull);
    });

    test('ad ve zaman okunur; kurulda ad null gelir', () {
      final full = CheckMark.tryParse(<String, dynamic>{'checked_at': '2026-10-29T10:30:00.000Z', 'checked_by_name': ' Ayşe Yönetici '});
      expect(full, _mark);
      final board = CheckMark.tryParse(<String, dynamic>{'checked_at': '2026-10-29T10:30:00.000Z', 'checked_by_name': null});
      expect(board?.at, _at);
      expect(board?.byName, isNull);
    });

    test('gider ve dekont aynı düz alanları okur; alan yoksa checkMark null', () {
      final json = <String, dynamic>{'checked_at': '2026-10-29T10:30:00.000Z', 'checked_by_name': 'Ayşe Yönetici'};
      final expense = Expense.fromJson(<String, dynamic>{'id': 3, 'amount_minor': 1000, ...json});
      expect(expense.checkMark, _mark);
      expect(Expense.fromJson(<String, dynamic>{'id': 3, 'amount_minor': 1000}).checkMark, isNull);
      final notice = PaymentNotice.fromJson(<String, dynamic>{'id': 5, 'amount_minor': 1000, 'status': 'approved', 'paid_on': '2026-10-20', ...json});
      expect(notice.checkMark, _mark);
      expect(notice.canBeChecked, isTrue);
      expect(PaymentNotice.fromJson(<String, dynamic>{'id': 5, 'amount_minor': 1000, 'status': 'withdrawn', 'paid_on': '2026-10-20'}).canBeChecked, isFalse);
    });
  });

  group('CheckMarkPanel', () {
    testWidgets('yönetici: kontrolsüzken "Henüz kontrol edilmedi"; işaretleyince "Kontrol edildi - kim, tarih"; kaldırınca geri döner', (t) async {
      final calls = <String>[];
      await _pump(
        t,
        CheckMarkPanel(
          mark: null,
          canWrite: true,
          onSet: () async {
            calls.add('set');
            return _mark;
          },
          onClear: () async {
            calls.add('clear');
            return null;
          },
        ),
      );
      expect(find.text('Henüz kontrol edilmedi'), findsOneWidget);
      expect(find.text('Kontrol Edildi Olarak İşaretle'), findsOneWidget);

      await t.tap(_toggle);
      await t.pumpAndSettle();
      expect(calls, <String>['set']);
      expect(find.text('Kontrol edildi - Ayşe Yönetici, $_atText'), findsOneWidget);
      expect(find.text('Kontrol İşaretini Kaldır'), findsOneWidget);

      await t.tap(_toggle);
      await t.pumpAndSettle();
      expect(calls, <String>['set', 'clear']);
      expect(find.text('Henüz kontrol edilmedi'), findsOneWidget);
    });

    testWidgets('kurul (salt okunur): rozet görünür, ad yoksa yalnız tarih; işaretleme düğmesi çizilmez', (t) async {
      await _pump(
        t,
        CheckMarkPanel(
          mark: CheckMark(at: _at),
          canWrite: false,
          onSet: () async => fail('kurul işaret koyamaz'),
          onClear: () async => fail('kurul işaret kaldıramaz'),
        ),
      );
      expect(find.text('Kontrol edildi - $_atText'), findsOneWidget);
      expect(_toggle, findsNothing);
    });

    testWidgets('sunucu reddederse ekran bozulmaz: neden düğmenin altında, rozet değişmez', (t) async {
      await _pump(
        t,
        CheckMarkPanel(
          mark: null,
          canWrite: true,
          onSet: () async => throw ApiException('Bu gider zaten iptal edilmiş.', statusCode: 409, code: 'EXPENSE_ALREADY_VOIDED'),
          onClear: () async => null,
        ),
      );
      await t.tap(_toggle);
      await t.pumpAndSettle();
      expect(find.text('Bu gider zaten iptal edilmiş.'), findsOneWidget);
      expect(find.text('Henüz kontrol edilmedi'), findsOneWidget);
      expect(_toggle, findsOneWidget);
    });
  });

  group('dekont karşılaştırma penceresi', () {
    testWidgets('onaylı dekontta iz görünür; kaldırma pencereyi KAPATMAZ ve karar akışına dokunmaz', (t) async {
      final auth = FakeBulkAuth();
      final api = _FakeNoticeApi();
      PaymentNoticeService.register(auth, PaymentNoticeService(authService: auth, api: api, tokenProvider: () => 'tok'));
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final scope = PeopleScope(authService: auth, siteCode: 1, siteName: 'Gül', canWrite: true);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => PaymentNoticeReviewDialog(scope: scope, noticeId: 5, accountsLoader: (_) async => const <CashAccount>[]),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();

      expect(find.text('Kontrol edildi - Ayşe Yönetici, $_atText'), findsOneWidget);
      await t.ensureVisible(_toggle);
      await t.tap(_toggle);
      await t.pumpAndSettle();
      expect(api.calls, <String>['clear']);
      expect(find.byKey(const ValueKey<String>('notice_review')), findsOneWidget, reason: 'pencere kapanmaz');
      expect(find.text('Henüz kontrol edilmedi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notice_review_approve')), findsNothing, reason: 'karara bağlanmış bildirimde onay düğmesi yok');
    });
  });
}

class _FakeNoticeApi extends PaymentNoticeApi {
  _FakeNoticeApi() : super(baseUrl: 'http://localhost');

  final calls = <String>[];

  @override
  Future<NoticeDetail> detail({required String token, required int siteCode, required int id}) async => NoticeDetail.fromJson(<String, dynamic>{
    'notice': <String, dynamic>{
      'id': id,
      'site_code': siteCode,
      'apartment_id': 7,
      'apartment_label': 'A Blok - 3',
      'account_party': 'owner',
      'origin': 'resident_app',
      'status': 'approved',
      'amount_minor': 125000,
      'paid_on': '2026-10-20',
      'method': 'transfer',
      'has_file': false,
      'submitted_at': '2026-10-20T10:00:00Z',
      'checked_at': '2026-10-29T10:30:00.000Z',
      'checked_by_name': 'Ayşe Yönetici',
    },
    'apartment': <String, dynamic>{
      'people': <Map<String, dynamic>>[],
      'balances': <String, dynamic>{},
      'recent_payments': <Map<String, dynamic>>[],
    },
    'warnings': <Map<String, dynamic>>[],
  });

  @override
  Future<CheckMark?> clearCheck({required String token, required int siteCode, required int id}) async {
    calls.add('clear');
    return null;
  }

  @override
  Future<CheckMark?> setCheck({required String token, required int siteCode, required int id}) async {
    calls.add('set');
    return CheckMark(at: _at, byName: 'Ayşe Yönetici');
  }
}
