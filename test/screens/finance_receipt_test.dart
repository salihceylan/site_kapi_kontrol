// Platform Faz 4b, Ö1: makbuz ayrıntısı (FinanceReceiptDialog), makbuz listesi (FinanceReceiptListDialog) ve
// makbuz doğrulama penceresi.
//
// Taşma matrisi (320x640 x2,0 / 360x640 x1,5 / yatay 640x360 x2,0 / tablet) x açık-koyu; yükleniyor / hata / dolu /
// boş durumları; yönetici - kurul - sakin yetki farkı; ASIL / KOPYA numaralandırması (sunucudan); basım kaydı
// yazılamazsa PDF üretilmez; çift dokunuş; iptal akışı; ekran okuyucu etiketleri. PDF'in kendisi
// `pdf_finance_service_test.dart` ile sınanır (burada `FinancePdfActions.debugOverride` ile yakalanır).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_list_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

FinanceFakeAuth _auth() {
  final auth = FinanceFakeAuth.seeded();
  auth.f4.receipts[9] = f4ReceiptJson(9);
  return auth;
}

final List<FinancePdfRequest> _pdfRequests = <FinancePdfRequest>[];

Future<void> _openReceipt(
  WidgetTester t,
  FinanceFakeAuth auth, {
  int receiptId = 9,
  bool canWrite = true,
  bool resident = false,
  bool justIssued = false,
  VoidCallback? onChanged,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  await openDialogAt(
    t,
    (context) => FinanceReceiptDialog.show(
      context,
      scope: _scope(auth, canWrite: canWrite),
      receiptId: receiptId,
      initialNumber: 'MK-2026-000009',
      resident: resident,
      justIssued: justIssued,
      onChanged: onChanged,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

Future<void> _openList(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  bool resident = false,
  int? apartmentId,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  await openDialogAt(
    t,
    (context) => FinanceReceiptListDialog.show(
      context,
      scope: _scope(auth, canWrite: canWrite),
      apartmentId: apartmentId,
      apartmentLabel: apartmentId == null ? null : 'A Blok - 5',
      resident: resident,
      now: () => _now,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

void main() {
  setUp(() {
    _pdfRequests.clear();
    FinancePdfActions.debugOverride = (request) async => _pdfRequests.add(request);
  });

  tearDown(() => FinancePdfActions.debugOverride = null);

  group('makbuz ayrıntısı: taşma matrisi', () {
    f4Matrix('yönetici: dolu makbuz (numara, tutar, yazıyla, metin, düğmeler)', (t, w, h, s, dark) async {
      final auth = _auth();
      await _openReceipt(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsOneWidget);
      expect(find.text('MK-2026-000009'), findsWidgets);
      expect(find.text('1.234,56 ₺'), findsOneWidget);
      expect(find.textContaining('bin iki yüz otuz dört lira elli altı kuruş'), findsWidgets);
      for (final key in const ['finance_receipt_print', 'finance_receipt_share', 'finance_receipt_cancel']) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    f4Matrix('yükleniyor: iskelet; "makbuz yok / bulunamadı" yazılmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.receiptGate = Completer<void>();
      await _openReceipt(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Makbuz yükleniyor...'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsNothing);
      expect(find.text('Makbuz bulunamadı.'), findsNothing);
      auth.f4.receiptGate!.complete();
      await settleFor(t);
    });

    f4Matrix('hata: bildirim + Tekrar Dene; boş ekran yok', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.receiptError = ApiException('Sunucu hatası', statusCode: 500);
      await _openReceipt(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsNothing);
    });

    f4Matrix('iptal makbuzu ve iptal edilmiş makbuz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.receipts[9] = f4ReceiptJson(9, status: 'cancelled', cancelledByNumber: 'MK-2026-000010');
      auth.f4.receipts[10] = f4ReceiptJson(10, kind: 'cancellation', cancelsNumber: 'MK-2026-000009');
      await _openReceipt(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancelled')), findsOneWidget);
      expect(find.textContaining('İptal makbuzu No MK-2026-000010'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancel')), findsNothing, reason: 'iptal edilmişi tekrar iptal edilemez');
    });
  });

  group('makbuz ayrıntısı: davranış', () {
    testWidgets('tahsilat sonrası açılış: "Makbuz ... düzenlendi" bildirimi', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth, justIssued: true);
      expect(find.byKey(const ValueKey<String>('finance_receipt_issued')), findsOneWidget);
      expect(find.textContaining('Makbuz MK-2026-000009 düzenlendi'), findsOneWidget);
    });

    testWidgets('yönetici basımı: ilk basım ASIL, ikincisi KOPYA (2); numara SUNUCUDAN gelir', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth);
      expect(find.text('0'), findsOneWidget, reason: 'basım sayısı');
      await f4Tap(t, 'finance_receipt_print');
      expect(auth.f4.callCount('recordReceiptPrint'), 1);
      expect(_pdfRequests.single.kind, 'receipt');
      expect(_pdfRequests.single.stamp, 'ASIL');
      expect(_pdfRequests.single.share, isFalse);
      await f4Tap(t, 'finance_receipt_share');
      expect(auth.f4.callCount('recordReceiptPrint'), 2);
      expect(_pdfRequests.last.stamp, 'KOPYA (2)');
      expect(_pdfRequests.last.share, isTrue);
      expect(find.text('2'), findsOneWidget, reason: 'basım sayısı yenilendi');
    });

    testWidgets('çift dokunuş: işlem sürerken ikinci basım kaydı yazılmaz', (t) async {
      final auth = _auth();
      auth.f4.printGate = Completer<void>();
      await _openReceipt(t, auth);
      final button = find.byKey(const ValueKey<String>('finance_receipt_print'));
      await scrollTo(t, button);
      await t.tap(button);
      await t.pump();
      await t.tap(button, warnIfMissed: false);
      await t.tap(find.byKey(const ValueKey<String>('finance_receipt_share')), warnIfMissed: false);
      await t.pump();
      expect(auth.f4.callCount('recordReceiptPrint'), 1);
      auth.f4.printGate!.complete();
      await settleFor(t);
      expect(auth.f4.callCount('recordReceiptPrint'), 1);
      expect(_pdfRequests, hasLength(1));
    });

    testWidgets('basım kaydı yazılamazsa PDF ÜRETİLMEZ; ASIL damgası uydurulmaz; hata gösterilir', (t) async {
      final auth = _auth();
      auth.f4.printError = ApiException('Sunucu yanıt vermedi', statusCode: 500);
      await _openReceipt(t, auth);
      await f4Tap(t, 'finance_receipt_print');
      expect(_pdfRequests, isEmpty);
      expect(find.byKey(const ValueKey<String>('finance_receipt_error')), findsOneWidget);
      // Düğme yeniden denenebilir; başarıda ilk basım yine ASIL (olay yazılamamıştı).
      auth.f4.printError = null;
      await f4Tap(t, 'finance_receipt_print');
      expect(_pdfRequests.single.stamp, 'ASIL');
      expect(find.byKey(const ValueKey<String>('finance_receipt_error')), findsNothing);
    });

    testWidgets('belirsiz sonuçta yeniden deneme AYNI idempotency_key ile gider (çift olay yazılmaz)', (t) async {
      final auth = _auth();
      auth.f4.printError = ApiException('x', statusCode: 502);
      await _openReceipt(t, auth);
      await f4Tap(t, 'finance_receipt_print');
      auth.f4.printError = null;
      await f4Tap(t, 'finance_receipt_print');
      final keys = auth.f4.writes.where((w) => w['op'] == 'recordReceiptPrint').map((w) => w['key']).toList();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1], reason: 'belirsiz sonuçtan sonra aynı anahtar');
      // Başarılı basımdan SONRAKİ basım yeni bir olaydır: yeni anahtar.
      await f4Tap(t, 'finance_receipt_print');
      final all = auth.f4.writes.where((w) => w['op'] == 'recordReceiptPrint').map((w) => w['key']).toList();
      expect(all[2], isNot(all[1]));
    });

    testWidgets('PDF üretilemezse (basım kaydı yazıldı) açık ileti', (t) async {
      final auth = _auth();
      FinancePdfActions.debugOverride = (_) async => throw StateError('pdf');
      await _openReceipt(t, auth);
      await f4Tap(t, 'finance_receipt_print');
      expect(find.text('Basım kaydedildi ancak PDF hazırlanamadı. Tekrar deneyin; yeni bir kopya sayılmaz.'), findsOneWidget);
    });

    testWidgets('R13 P2-6: ekrandaki sabit metin sunucu şablonundan gelir (PDF ile AYNI kaynak)', (t) async {
      final auth = _auth();
      auth.f4.receipts[9] = <String, dynamic>{
        ...f4ReceiptJson(9),
        'template': <String, dynamic>{
          'version': 2,
          'mahsup_text': 'Şablon mahsup metni sürüm iki.',
          'cekince_text': 'Şablon çekince metni sürüm iki.',
          'disclaimer_text': 'Şablon uyarı metni sürüm iki.',
        },
      };
      await _openReceipt(t, auth);
      expect(find.text('Şablon mahsup metni sürüm iki.'), findsOneWidget);
      expect(find.text('Şablon çekince metni sürüm iki.'), findsOneWidget);
      expect(find.text('Şablon uyarı metni sürüm iki.'), findsOneWidget);
      expect(find.text(PdfFinanceService.mahsupText), findsNothing);
    });

    testWidgets('R13 P2-11: ödeyen "both" ise ad sıfatla birleştirilmez (Malik / kiracı - ad YOK)', (t) async {
      final auth = _auth();
      final json = f4ReceiptJson(9);
      ((json['snapshot'] as Map<String, dynamic>)['payer'] as Map<String, dynamic>)['party'] = 'both';
      auth.f4.receipts[9] = json;
      await _openReceipt(t, auth);
      expect(find.text('Ayşe Yılmaz'), findsWidgets);
      expect(find.textContaining('Malik / kiracı'), findsNothing);
    });

    testWidgets('R14 P1: basım kaydı yazıldı ama PDF üretilemedi -> yeniden deneme YENİ kopya saymaz; ASIL teslim edilir', (t) async {
      final auth = _auth();
      var attempts = 0;
      FinancePdfActions.debugOverride = (request) async {
        attempts++;
        if (attempts == 1) throw StateError('pdf');
        _pdfRequests.add(request);
      };
      await _openReceipt(t, auth);
      await f4Tap(t, 'finance_receipt_print');
      expect(find.textContaining('Basım kaydedildi ancak PDF hazırlanamadı'), findsOneWidget);
      expect(find.textContaining('yeni bir kopya sayılmaz'), findsOneWidget, reason: 'kullanıcı bilgilendirilir');
      expect(auth.f4.callCount('recordReceiptPrint'), 1);
      await f4Tap(t, 'finance_receipt_print');
      expect(auth.f4.callCount('recordReceiptPrint'), 1, reason: 'ikinci basım kaydı YAZILMADI');
      expect(_pdfRequests.single.stamp, 'ASIL', reason: 'teslim edilen ilk çıktı ASIL');
      // Teslimden SONRAKİ basım yeni bir kopyadır.
      await f4Tap(t, 'finance_receipt_print');
      expect(auth.f4.callCount('recordReceiptPrint'), 2);
      expect(_pdfRequests.last.stamp, 'KOPYA (2)');
    });

    testWidgets('sakin: basım kaydı YAZILMAZ, damga her zaman KOPYA; basım sayısı / iptal yok', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth, canWrite: false, resident: true);
      expect(find.text('Basım sayısı'), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancel')), findsNothing);
      expect(find.textContaining('KOPYA'), findsOneWidget);
      await f4Tap(t, 'finance_receipt_print');
      expect(auth.f4.callCount('recordReceiptPrint'), 0);
      expect(auth.f4.callCount('getMyReceipt'), greaterThanOrEqualTo(1));
      expect(_pdfRequests.single.stamp, 'KOPYA');
    });

    testWidgets('kurul: ayrıntıyı okur, ama yazdır / paylaş / iptal düğmesi YOK', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsOneWidget);
      for (final key in const ['finance_receipt_print', 'finance_receipt_share', 'finance_receipt_cancel']) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
      expect(find.text('Basım sayısı'), findsNothing);
    });

    testWidgets('iptal: onay penceresi, not gider, sonuç bildirilir; makbuz yenilenir ve onChanged çağrılır', (t) async {
      final auth = _auth();
      var changed = 0;
      await _openReceipt(t, auth, onChanged: () => changed++);
      await f4Tap(t, 'finance_receipt_cancel');
      expect(find.text('Makbuzu İptal Et'), findsWidgets);
      await f4Enter(t, 'finance_receipt_cancel_note', '  Yanlış daire  ');
      await f4Tap(t, 'finance_receipt_cancel_confirm');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'cancelReceipt');
      expect(write['note'], 'Yanlış daire');
      expect((write['key'] as String).length, lessThanOrEqualTo(64));
      expect(changed, 1);
      expect(find.textContaining('Makbuz iptal edildi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancelled')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancel')), findsNothing);
    });

    testWidgets('R15: makbuz iptali — aynı not AYNI anahtar; not değişince YENİ anahtar', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth);
      auth.f4.cancelError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await f4Tap(t, 'finance_receipt_cancel');
      await f4Enter(t, 'finance_receipt_cancel_note', 'Yanlış daire');
      await f4Tap(t, 'finance_receipt_cancel_confirm');
      await f4Tap(t, 'finance_receipt_cancel_confirm');
      await f4Enter(t, 'finance_receipt_cancel_note', 'Çift düzenlenmiş');
      await f4Tap(t, 'finance_receipt_cancel_confirm');
      final keys = auth.f4.writes.where((w) => w['op'] == 'cancelReceipt').map((w) => w['key']).toList();
      expect(keys, hasLength(3));
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
    });

    testWidgets('iptal reddi pencerede kalır, Türkçe metin; vazgeçince hiçbir şey yazılmaz', (t) async {
      final auth = _auth();
      auth.f4.cancelError = f4Coded('RECEIPT_ALREADY_CANCELLED', 409);
      await _openReceipt(t, auth);
      await f4Tap(t, 'finance_receipt_cancel');
      await f4Tap(t, 'finance_receipt_cancel_confirm');
      expect(find.text('Bu makbuz zaten iptal edilmiş. Listeyi yenileyip kontrol edin.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancel_confirm')), findsOneWidget, reason: 'pencere açık');
      await f4TapInDialog(t, 'Vazgeç');
      expect(find.byKey(const ValueKey<String>('finance_receipt_cancel_confirm')), findsNothing);
    });

    testWidgets('iptal notu 200 karakteri aşarsa gönderilmez', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth);
      await f4Tap(t, 'finance_receipt_cancel');
      await f4Enter(t, 'finance_receipt_cancel_note', 'x' * 201);
      await f4Tap(t, 'finance_receipt_cancel_confirm');
      expect(find.text('Not en çok 200 karakter olabilir.'), findsOneWidget);
      expect(auth.f4.callCount('cancelReceipt'), 0);
    });

    testWidgets('hata sonrası Tekrar Dene makbuzu getirir', (t) async {
      final auth = _auth();
      auth.f4.receiptError = ApiException('x', statusCode: 500);
      await _openReceipt(t, auth);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      auth.f4.receiptError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsOneWidget);
    });

    testWidgets('ekran okuyucu: tutar "bin iki yüz otuz dört lira elli altı kuruş" diye okunur', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _openReceipt(t, auth);
      expect(
        find.bySemanticsLabel(RegExp('bin iki yüz otuz dört lira elli altı kuruş')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('makbuz metni (mahsup + çekince) ve belge uyarısı ekranda', (t) async {
      final auth = _auth();
      await _openReceipt(t, auth);
      expect(find.textContaining('vadesi en eski borçtan başlayarak mahsup edilir'), findsOneWidget);
      expect(find.textContaining('haklar saklıdır'), findsOneWidget);
      expect(find.textContaining('yasal defterlerin yerine geçmez'), findsOneWidget);
    });
  });

  group('makbuz listesi', () {
    FinanceFakeAuth withReceipts() {
      final auth = _auth();
      auth.f4.receipts[10] = f4ReceiptJson(10, apartment: 'A Blok - 6', payerName: 'Mehmet Demir', amount: 50000);
      auth.f4.receipts[11] = f4ReceiptJson(11, status: 'cancelled', cancelledByNumber: 'MK-2026-000012');
      auth.f4.receipts[12] = f4ReceiptJson(12, kind: 'cancellation', cancelsNumber: 'MK-2026-000011');
      return auth;
    }

    f4Matrix('dolu liste: etiketler, tutarlar, durum rozetleri', (t, w, h, s, dark) async {
      final auth = withReceipts();
      await _openList(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ReceiptTile), findsNWidgets(4));
      expect(find.text('MK-2026-000012'), findsOneWidget);
      expect(find.text('İptal makbuzu'), findsOneWidget);
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(find.text('Geçerli'), findsNWidgets(2));
    });

    f4Matrix('hata: bildirim; "makbuz yok" yazılmaz', (t, w, h, s, dark) async {
      final auth = withReceipts();
      auth.f4.receiptListError = ApiException('x', statusCode: 500);
      await _openList(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Henüz makbuz düzenlenmemiş.'), findsNothing);
      expect(find.byType(ReceiptTile), findsNothing);
    });

    f4Matrix('yükleniyor ve boş durum', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.receipts.clear();
      auth.f4.receiptListGate = Completer<void>();
      await _openList(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz makbuz düzenlenmemiş.'), findsNothing);
      expect(find.text('Bu arama ve süzgeç için makbuz bulunamadı.'), findsNothing, reason: 'yükleme bitmeden boş durum yok');
      auth.f4.receiptListGate!.complete();
      await settleFor(t);
      expect(find.text('Bu arama ve süzgeç için makbuz bulunamadı.'), findsOneWidget, reason: 'yıl süzgeci açık');
    });

    testWidgets('varsayılan yıl içinde bulunulan yıl; "Tümü" süzgeci kaldırır; arama gecikmeli', (t) async {
      final auth = withReceipts();
      await _openList(t, auth);
      expect(auth.f4.receiptListCalls.first['year'], 2026);
      await f4Tap(t, 'finance_receipts_year_all');
      expect(auth.f4.receiptListCalls.last['year'], isNull);
      final before = auth.f4.receiptListCalls.length;
      await f4Enter(t, 'finance_receipts_search', 'Mehmet');
      expect(auth.f4.receiptListCalls.length, before, reason: 'gecikme dolmadan istek yok');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t);
      expect(auth.f4.receiptListCalls.last['q'], 'Mehmet');
      expect(find.byType(ReceiptTile), findsOneWidget);
    });

    testWidgets('sayfalama: Daha fazla yükle imleçle ikinci sayfayı ekler, yineleneni eklemez', (t) async {
      final auth = withReceipts();
      auth.f4.receiptPageSize = 2;
      await _openList(t, auth);
      expect(find.byType(ReceiptTile), findsNWidgets(2));
      await f4TapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(ReceiptTile), findsNWidgets(4));
      expect(auth.f4.receiptListCalls.last['before_id'], 11);
    });

    testWidgets('satıra dokununca ayrıntı açılır; çift dokunuş tek pencere açar', (t) async {
      final auth = withReceipts();
      await _openList(t, auth);
      final tile = find.byKey(const ValueKey<String>('receipt_tile_9'));
      await scrollTo(t, tile);
      await t.tap(tile);
      await t.tap(tile, warnIfMissed: false);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_receipt_number')), findsOneWidget);
      expect(auth.f4.callCount('getReceipt'), 1);
    });

    testWidgets('ekstreden açılış: yalnız o dairenin makbuzları istenir', (t) async {
      final auth = withReceipts();
      await _openList(t, auth, apartmentId: 301);
      expect(auth.f4.receiptListCalls.first['apartment_id'], 301);
      expect(find.text('A Blok - 5'), findsWidgets);
    });

    testWidgets('sakin: arama, yıl ve doğrulama yok; kendi uç noktası kullanılır', (t) async {
      final auth = withReceipts();
      await _openList(t, auth, canWrite: false, resident: true);
      expect(find.text('Makbuzlarım'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_receipts_search')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_receipts_verify')), findsNothing);
      expect(auth.f4.callCount('listMyReceipts'), 1);
      expect(auth.f4.callCount('listReceipts'), 0);
      // Sakin ödeyen adını görmez.
      expect(find.textContaining('Ödeyen:'), findsNothing);
    });

    testWidgets('kurul listeyi okur ve makbuz doğrulayabilir', (t) async {
      final auth = withReceipts();
      await _openList(t, auth, canWrite: false);
      expect(find.byType(ReceiptTile), findsNWidgets(4));
      expect(find.byKey(const ValueKey<String>('finance_receipts_verify')), findsOneWidget);
    });
  });

  group('makbuz doğrulama', () {
    Future<void> openVerify(WidgetTester t, FinanceFakeAuth auth) async {
      await _openList(t, auth);
      await f4Tap(t, 'finance_receipts_verify');
    }

    testWidgets('boş / hatalı biçim gönderilmez; kod 12 karakter', (t) async {
      final auth = _auth();
      await openVerify(t, auth);
      await f4Tap(t, 'finance_verify_submit');
      expect(find.text('Makbuz numarasını girin.'), findsOneWidget);
      expect(find.text('Doğrulama kodunu girin.'), findsOneWidget);
      await f4Enter(t, 'finance_verify_number', 'ABC');
      await f4Enter(t, 'finance_verify_code', '123');
      await f4Tap(t, 'finance_verify_submit');
      expect(find.text('Numara MK-2026-000123 biçiminde olmalı.'), findsOneWidget);
      expect(find.text('Kod 12 harf ya da rakamdan oluşur.'), findsOneWidget);
      expect(auth.f4.callCount('verifyReceipt'), 0);
    });

    testWidgets('geçerli, iptal edilmiş ve eşleşmeyen sonuçlar ayrı ayrı bildirilir; kod temizlenip büyütülür', (t) async {
      final auth = _auth();
      await openVerify(t, auth);
      await f4Enter(t, 'finance_verify_number', 'mk-2026-000009');
      await f4Enter(t, 'finance_verify_code', 'ab12-cd34-ef56');
      await f4Tap(t, 'finance_verify_submit');
      expect(auth.f4.verifyCalls.single, <String, String>{'number': 'MK-2026-000009', 'code': 'AB12CD34EF56'});
      expect(find.text('Bu makbuz kayıtlarla eşleşiyor ve geçerli.'), findsOneWidget);
      // Sunucu geçerli sonuçta eşleşen makbuzun özetini de verir: elindeki belgeyle karşılaştırılır.
      expect(find.byKey(const ValueKey<String>('finance_verify_details')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('finance_verify_details')), matching: find.text('MK-2026-000009')), findsOneWidget);
      final details = find.byKey(const ValueKey<String>('finance_verify_details'));
      for (final text in const ['1.234,56 ₺', 'A Blok - 5', '14.10.2026', '16.10.2026']) {
        expect(find.descendant(of: details, matching: find.text(text)), findsOneWidget, reason: text);
      }
      auth.f4.verifyStatus = 'cancelled';
      await f4Tap(t, 'finance_verify_submit');
      expect(find.text('Bu makbuz kayıtlarla eşleşiyor ancak İPTAL EDİLMİŞ.'), findsOneWidget);
      auth.f4.verifyStatus = 'cancellation';
      await f4Tap(t, 'finance_verify_submit');
      expect(find.text('Bu belge kayıtlarla eşleşiyor: bir makbuzu iptal eden İPTAL MAKBUZUDUR.'), findsOneWidget);
      auth.f4.verifyValid = false;
      await f4Tap(t, 'finance_verify_submit');
      expect(
        find.text('Girilen numara ve kod kayıtlarla eşleşmiyor. Bilgileri kontrol edin.'),
        findsOneWidget,
        reason: '"sahte" iddiası yok; yalnız eşleşmedi denir',
      );
      expect(find.byKey(const ValueKey<String>('finance_verify_details')), findsNothing, reason: 'geçersizde özet yok');
    });

    testWidgets('hata gösterilir; hız sınırında düğme geçici kilitlenir', (t) async {
      final auth = _auth();
      await openVerify(t, auth);
      await f4Enter(t, 'finance_verify_number', 'MK-2026-000009');
      await f4Enter(t, 'finance_verify_code', 'AB12CD34EF56');
      auth.f4.verifyError = ApiException('x', statusCode: 429, retryAfterSeconds: 5);
      await f4Tap(t, 'finance_verify_submit');
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      final submit = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_verify_submit')));
      expect(submit.onPressed, isNull, reason: 'kilitli');
      await t.pump(const Duration(seconds: 6));
      final again = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_verify_submit')));
      expect(again.onPressed, isNotNull, reason: 'süre dolunca açılır');
    });
  });

  testWidgets('semantik: makbuz satırı tek birleşik etiketle okunur', (t) async {
    final handle = t.ensureSemantics();
    final auth = _auth();
    await _openList(t, auth);
    final node = t.getSemantics(find.byKey(const ValueKey<String>('receipt_tile_9')));
    expect(node.label, contains('Makbuz MK-2026-000009'));
    expect(node.label, contains('bin iki yüz otuz dört lira elli altı kuruş'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  test('FinanceReceiptDialog sabitleri', () {
    expect(FinanceReceiptDialog.maxNoteLength, 200);
  });
}
