// "Öde" sayfası (2A): kopyala satırları (boşluksuz IBAN, anlamsal etiket, 48 dp hedef, "Kopyalandı"), ayar yok durumu, IBAN değişti uyarısı,
// "Kartla öde" pasif, "Dekont yükle" yalnız geri çağrı varken. Model: TR IBAN denetimi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/payment_info.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show formatMinor;
import 'package:site_kapi_kontrol/ui/widgets/pay_sheet.dart';

import 'screens/list_fixtures.dart';

const _iban = 'TR330006100519786457841326';
final DateTime _now = DateTime(2026, 10, 21, 12);

PaymentInfoItem _info({DateTime? changedAt, bool configured = true}) => PaymentInfoItem(
  siteCode: 1,
  apartmentId: 7,
  configured: configured,
  payeeName: 'Gül Sitesi Yönetimi',
  iban: configured ? _iban : null,
  ibanDisplay: configured ? groupIban(_iban) : null,
  reference: configured ? 'GUL-A2-1026' : null,
  referenceShort: configured ? 'GUL-A2' : null,
  detailsChangedAt: changedAt,
);

Future<List<String>> _pump(WidgetTester t, PaymentInfoItem? info, {VoidCallback? onUpload}) async {
  final copied = <String>[];
  await pumpList(
    t,
    SingleChildScrollView(
      child: PayContent(
        info: info,
        amountMinor: 125000,
        accountLabel: 'Kiracı hesabı',
        onUploadReceipt: onUpload,
        now: () => _now,
        copy: (text) async => copied.add(text),
      ),
    ),
    width: 400,
    height: 900,
    scale: 1,
    dark: false,
  );
  return copied;
}

void main() {
  group('PayContent', () {
    testWidgets('tutar, alıcı, gruplu IBAN ve kod görünür; kopyalar boşluksuz IBAN ve kodu yazar', (t) async {
      final copied = await _pump(t, _info());
      expect(find.text(formatMinor(125000)), findsOneWidget);
      expect(find.text('Kiracı hesabı'), findsOneWidget);
      expect(find.text('Gül Sitesi Yönetimi'), findsOneWidget);
      expect(find.text(groupIban(_iban)), findsOneWidget);
      expect(find.text('GUL-A2-1026'), findsOneWidget);
      expect(find.textContaining('Düzenli ödeme talimatında GUL-A2 yazabilirsiniz.'), findsOneWidget);
      expect(find.text('FAST veya havale ile komisyonsuz ödeyebilirsiniz.'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey<String>('pay_row_iban_copy')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('pay_row_ref_copy')));
      await t.pump();
      expect(copied, [_iban, 'GUL-A2-1026']);
      expect(find.text('Kopyalandı'), findsOneWidget);
    });

    testWidgets('kopyala düğmeleri 48 dp ve anlamsal etiketli', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, _info());
      for (final key in const ['pay_row_payee_copy', 'pay_row_iban_copy', 'pay_row_ref_copy']) {
        final size = t.getSize(find.byKey(ValueKey<String>(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
      }
      expect(find.bySemanticsLabel("IBAN'ı kopyala"), findsOneWidget);
      expect(find.bySemanticsLabel('Açıklama kodunu kopyala'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ayar yoksa dürüst açıklama; kopyala satırı ve dekont yok', (t) async {
      await _pump(t, _info(configured: false), onUpload: () {});
      expect(find.byKey(const ValueKey<String>('pay_not_configured')), findsOneWidget);
      expect(find.textContaining('Site yönetimi ödeme bilgisini henüz girmedi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('pay_row_iban')), findsNothing);
      expect(find.byKey(const ValueKey<String>('pay_upload_receipt')), findsNothing);
      await _pump(t, null);
      expect(find.byKey(const ValueKey<String>('pay_not_configured')), findsOneWidget);
    });

    testWidgets('IBAN son 14 günde değiştiyse uyarı; eskiyse yok', (t) async {
      await _pump(t, _info(changedAt: DateTime(2026, 10, 15)));
      expect(find.byKey(const ValueKey<String>('pay_changed_warning')), findsOneWidget);
      expect(find.textContaining('15.10.2026 tarihinde değişti'), findsOneWidget);
      await _pump(t, _info(changedAt: DateTime(2026, 9, 1)));
      expect(find.byKey(const ValueKey<String>('pay_changed_warning')), findsNothing);
    });

    testWidgets('"Kartla öde — Yakında…" pasif; "Dekont yükle" yalnız geri çağrı verilince', (t) async {
      await _pump(t, _info());
      expect(find.text('Kartla öde — Yakında…'), findsOneWidget);
      final card = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Kartla öde — Yakında…'));
      expect(card.onPressed, isNull);
      expect(find.byKey(const ValueKey<String>('pay_upload_receipt')), findsNothing);
      var uploads = 0;
      await _pump(t, _info(), onUpload: () => uploads++);
      await t.tap(find.byKey(const ValueKey<String>('pay_upload_receipt')));
      expect(uploads, 1);
    });
  });

  group('parseTrIban', () {
    test('geçerli IBAN kabul edilir; boşluk ve küçük harf normalleşir', () {
      expect(parseTrIban(_iban), _iban);
      expect(parseTrIban(groupIban(_iban).toLowerCase()), _iban);
    });
    test('sağlama, uzunluk ve ülke hataları reddedilir', () {
      expect(parseTrIban('${_iban.substring(0, 25)}7'), isNull);
      expect(parseTrIban(_iban.substring(0, 25)), isNull);
      expect(parseTrIban('DE${_iban.substring(2)}'), isNull);
      expect(parseTrIban(''), isNull);
    });
  });
}
