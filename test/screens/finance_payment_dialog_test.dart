// Platform Faz 4a: tahsilat penceresi (FinancePaymentDialog: ekle + düzelt) ve iptal penceresi
// (FinanceReverseDialog).
//
// AGENTS.md kural 6: dört hücre (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) x açık / koyu;
// klavye açıkken de taşma yok. Davranış: doğrulama (tutar kuralları, tarih, yöntem, daire), tutarın kuruşa
// KESİN çevrilmesi, idempotency_key (aynı veri = aynı anahtar, değişen veri = yeni anahtar), çift gönderim
// koruması, geri tuşu, sunucu reddi pencerede kalır, belirsiz sonuç uyarısı.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reverse_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show tapFinder, tapText;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

class _Out<T> {
  T? result;
  bool closed = false;
  int refreshes = 0;
}

PeopleScope _scope(FinanceFakeAuth auth) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);

Future<_Out<FinancePaymentOutcome>> _openPayment(
  WidgetTester t,
  FinanceFakeAuth auth, {
  int? apartmentId,
  String? apartmentLabel,
  LedgerEntry? correcting,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out<FinancePaymentOutcome>();
  await openDialogAt(
    t,
    (context) async {
      out.result = await FinancePaymentDialog.show(
        context,
        scope: _scope(auth),
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        correcting: correcting,
        now: () => _now,
        onRefreshNeeded: () => out.refreshes++,
      );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return out;
}

Future<_Out<FinanceReverseOutcome>> _openReverse(
  WidgetTester t,
  FinanceFakeAuth auth,
  LedgerEntry entry, {
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out<FinanceReverseOutcome>();
  await openDialogAt(
    t,
    (context) async {
      out.result = await FinanceReverseDialog.show(
        context,
        scope: _scope(auth),
        entry: entry,
        onRefreshNeeded: () => out.refreshes++,
      );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return out;
}

Future<void> _enter(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await scrollTo(t, finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _submit(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await scrollTo(t, finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Daire seçicisini açıp [label] dairesini seçer.
Future<void> _pickApartment(WidgetTester t, String label) async {
  await _tapKey(t, 'finance_payment_apartment');
  await settleFor(t);
  await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text(label)));
  await settleFor(t);
}

LedgerEntry _paymentEntry(FinanceFakeAuth auth) {
  final row = auth.ledger.firstWhere((e) => e['id'] == 4);
  return LedgerEntry.fromJson(<String, dynamic>{...row, 'reversed_by_entry_id': null});
}

void main() {
  group('tahsilat: taşma matrisi', () {
    layoutMatrix('Tahsilat Ekle: varsayılan görünüm', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Tahsilat Ekle'), findsWidgets);
      for (final label in const ['Tahsilat tutarı', 'Tahsilat tarihi', 'Yöntem']) {
        await scrollTo(t, find.text(label).first);
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Borçtan fazla ödeme alacak olarak görünür.'), findsOneWidget);
      await scrollTo(t, find.text('Kaydet'));
      expect(find.text('Kaydet'), findsOneWidget);
    });

    layoutMatrix('Tahsilatı Düzelt: eski kayıt özeti ve ters kayıt açıklaması', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(
        t,
        auth,
        apartmentId: 302,
        apartmentLabel: 'A Blok - 6',
        correcting: _paymentEntry(auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Tahsilatı Düzelt'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_payment_original')), findsOneWidget);
      expect(find.textContaining('800,00 ₺'), findsWidgets);
      await scrollTo(t, find.text('Düzelt').last);
    });

    layoutMatrix('hatalı gönderim: özet + alan hataları taşmaz', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(t, auth, width: w, height: h, scale: s, dark: dark);
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
    });

    layoutMatrix('İptal penceresi: kayıt özeti ve neden alanı', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openReverse(t, auth, _paymentEntry(auth), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Kaydı İptal Et'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reverse_entry')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_reverse_reason')));
      expect(find.text('İptal nedeni'), findsOneWidget);
    });

    testWidgets('klavye açıkken (320x640 x2,0) alanlar taşmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5', width: 320, height: 640, scale: 2.0);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await _enter(t, 'finance_payment_amount', '1.250,50');
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Tahsilat yöntemini seçin.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('tahsilat: kayıt', () {
    testWidgets('daire + tutar + yöntem: kuruşa KESİN çevrilir, tarih İstanbul bugünü, anahtar gider, bakiye mesajda', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openPayment(t, auth);
      expect(
        t.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey<String>('finance_payment_date')),
          matching: find.byType(TextField),
        )).controller!.text,
        '16.10.2026',
        reason: 'varsayılan: İstanbul bugünü',
      );
      await _pickApartment(t, 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '1.250,50');
      expect(find.text('Girilen tutar: 1.250,50 ₺'), findsOneWidget, reason: 'ayrıştırılan tutar yanında gösterilir');
      await _tapKey(t, 'finance_method_transfer');
      await _enter(t, 'finance_payment_note', '  Elden teslim  ');
      await _submit(t, 'finance_payment_submit');

      expect(auth.paymentCalls.length, 1);
      final call = auth.paymentCalls.single;
      expect(call['apartment_id'], 301);
      expect(call['amount_minor'], 125050);
      expect(call['entry_date'], '2026-10-16');
      expect(call['method'], 'transfer');
      expect(call['description'], '  Elden teslim  '.trim(), reason: 'açıklama kırpılır');
      expect((call['idempotency_key'] as String).length, lessThanOrEqualTo(64));
      expect(out.closed, isTrue);
      final outcome = out.result!;
      expect(outcome.message, startsWith('Tahsilat kaydedildi: 1.250,50 ₺.'));
      expect(
        outcome.message,
        contains('Güncel bakiye: Alacak 250,50 ₺'),
        reason: '301 numaralı dairenin 1.000,00 ₺ borcu vardı; 1.250,50 ₺ ödendi',
      );
      expect(outcome.result.entry.amountMinor, -125050, reason: 'defterde tahsilat negatif');
    });

    testWidgets('fazla ödeme alacak olarak görünür (mesajda "Alacak")', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openPayment(t, auth, apartmentId: 303, apartmentLabel: 'B Blok - 2');
      await _enter(t, 'finance_payment_amount', '500');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(out.result!.message, contains('Güncel bakiye: Alacak 500,00 ₺'));
      expect(auth.balanceOf(303), -50000);
    });

    testWidgets('önceden seçili daire (ekstreden): seçici devre dışı', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      expect(find.text('A Blok - 5'), findsWidgets);
      final field = t.widget<InkWell>(find.descendant(
        of: find.byKey(const ValueKey<String>('finance_payment_apartment')),
        matching: find.byType(InkWell),
      ));
      expect(field.onTap, isNull);
    });
  });

  group('tahsilat: doğrulama', () {
    testWidgets('boş gönderim: özet + tüm alan hataları, sunucuya gidilmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openPayment(t, auth);
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(find.text('Daire seçin.'), findsOneWidget);
      expect(find.text('Tahsilat yöntemini seçin.'), findsOneWidget);
      expect(auth.paymentCalls, isEmpty);
      expect(out.closed, isFalse);
    });

    testWidgets('tutar kuralları: 3 ondalık, negatif, sıfır, çok büyük, harf', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _tapKey(t, 'finance_method_cash');
      final cases = <String, String>{
        '12,345': 'Kuruş en çok 2 basamak olabilir (örn. 1.250,50).',
        '-5': 'Tutar negatif olamaz.',
        '0': 'Tutar sıfırdan büyük olmalı.',
        '1.000.000.000': 'Tutar en çok 999.999.999,99 ₺ olabilir.',
        '1.25.000': 'Tutarı rakamlarla girin (örn. 1.250,50).',
      };
      for (final entry in cases.entries) {
        await _enter(t, 'finance_payment_amount', entry.key);
        await _submit(t, 'finance_payment_submit');
        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
        expect(auth.paymentCalls, isEmpty, reason: entry.key);
      }
    });

    testWidgets('tarih: gelecek ve geçersiz tarih reddedilir; yöntem seçilmeden gönderilmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _enter(t, 'finance_payment_date', '17.10.2026');
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Tarih bugünden ileri olamaz.'), findsOneWidget);
      await _enter(t, 'finance_payment_date', '31.02.2026');
      await _submit(t, 'finance_payment_submit');
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      await _enter(t, 'finance_payment_date', '');
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Tahsilat tarihini girin.'), findsOneWidget);
      expect(auth.paymentCalls, isEmpty);
    });

    testWidgets('açıklama sınırı 200 KOD NOKTASI (emoji tek sayılır); aşan giriş kırpılmaz, gönderim engellenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _enter(t, 'finance_payment_note', '😀' * 201);
      expect(find.text('201/200'), findsOneWidget);
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Açıklama en çok 200 karakter olabilir.'), findsOneWidget);
      expect(auth.paymentCalls, isEmpty);

      await _enter(t, 'finance_payment_note', '😀' * 200);
      expect(find.text('200/200'), findsOneWidget);
      await _submit(t, 'finance_payment_submit');
      expect(auth.paymentCalls.length, 1, reason: '200 emoji = 200 kod noktası (UTF-16 400): geçerli');
      expect(out.closed, isTrue);
    });
  });

  group('tahsilat: idempotency_key, çift gönderim, hata', () {
    testWidgets('ağ hatası sonrası AYNI veriyle yeniden deneme AYNI anahtarı kullanır; veri değişince yeni anahtar', (t) async {
      final auth = FinanceFakeAuth.seeded()..paymentError = ApiException('Sunucuya ulaşılamadı.');
      final out = await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(auth.paymentCalls.length, 1);
      expect(
        find.textContaining('Kayıt oluşmuş olabilir. Aynı bilgilerle tekrar denerseniz çift kayıt oluşmaz.'),
        findsOneWidget,
      );
      expect(out.closed, isFalse);

      // Aynı veri: aynı anahtar.
      await _submit(t, 'finance_payment_submit');
      expect(auth.paymentCalls.length, 2);
      expect(auth.paymentCalls[1]['idempotency_key'], auth.paymentCalls[0]['idempotency_key']);

      // Tutar değişti: yeni anahtar.
      await _enter(t, 'finance_payment_amount', '200');
      await _submit(t, 'finance_payment_submit');
      expect(auth.paymentCalls.length, 3);
      expect(auth.paymentCalls[2]['idempotency_key'], isNot(auth.paymentCalls[0]['idempotency_key']));

      // Sonuç belirsizdi: pencere kapanırken çağıran listeyi tazeler.
      auth.paymentError = null;
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(out.refreshes, 1);
    });

    testWidgets('İKİ KEZ başarısız deneme + sonra başarı: tek kayıt (sunucu anahtarı tekrar eder)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(out.closed, isTrue);
      // Aynı anahtarla bir kez daha çağrı = aynı kayıt (sunucu tarafı idempotans).
      final key = auth.paymentCalls.single['idempotency_key'] as String;
      final before = auth.ledger.length;
      await auth.recordFeePayment(
        11,
        apartmentId: 301,
        amountMinor: 10000,
        entryDate: DateTime(2026, 10, 16),
        method: PaymentMethod.cash,
        idempotencyKey: key,
      );
      expect(auth.ledger.length, before, reason: 'çift kayıt yok');
    });

    testWidgets('gönderim sürerken: düğme kilitli "Kaydediliyor...", tek istek; geri tuşu kapatmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..paymentGate = Completer<void>();
      final out = await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(find.text('Kaydediliyor...'), findsOneWidget);
      expect(auth.paymentCalls.length, 1);

      await t.tap(find.text('Kaydediliyor...'), warnIfMissed: false);
      await t.pump();
      expect(auth.paymentCalls.length, 1, reason: 'çift dokunuş ikinci istek göndermez');
      expect(t.widget<TextButton>(find.widgetWithText(TextButton, 'Vazgeç')).onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(FinancePaymentDialog), findsOneWidget, reason: 'geri tuşu gönderim sürerken kapatmaz');

      auth.paymentGate!.complete();
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(auth.paymentCalls.length, 1);
      expect(auth.ledger.where((e) => e['kind'] == 'payment' && e['amount_minor'] == -10000).length, 1);
    });

    testWidgets('kapalı dönem: Türkçe hata pencerede, pencere AÇIK, kayıt yok, belirsizlik uyarısı YOK', (t) async {
      final auth = FinanceFakeAuth.seeded()..closedPeriods.add('2026-10');
      final out = await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(find.text(AuthApi.messageForErrorCode('PERIOD_CLOSED')!), findsOneWidget);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsNothing, reason: '4xx kesin reddir');
      expect(out.closed, isFalse);
      expect(auth.ledger.where((e) => e['kind'] == 'payment').length, 1, reason: 'yalnız tohum tahsilatı');
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.refreshes, 0, reason: 'kesin ret: liste tazelenmez');
    });

    testWidgets('modül kapalı (403): açık Türkçe mesaj', (t) async {
      final auth = FinanceFakeAuth.seeded()..moduleEnabled = false;
      await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(find.text(AuthApi.messageForErrorCode('MODULE_DISABLED')!), findsOneWidget);
    });

    testWidgets('hız sınırı (429): düğme geçici kilitlenir, bekleme süresi söylenir', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..paymentError = ApiException('x', statusCode: 429, retryAfterSeconds: 90);
      await _openPayment(t, auth, apartmentId: 301, apartmentLabel: 'A Blok - 5');
      await _enter(t, 'finance_payment_amount', '100');
      await _tapKey(t, 'finance_method_cash');
      await _submit(t, 'finance_payment_submit');
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      final submit = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_payment_submit')));
      expect(submit.onPressed, isNull);
      // Süre dolunca düğme açılır.
      await t.pump(const Duration(seconds: 95));
      await t.pump();
      final reopened = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_payment_submit')));
      expect(reopened.onPressed, isNotNull);
    });
  });

  group('tahsilat düzeltme', () {
    testWidgets('eski değerler gelir; düzeltme TEK işlemde ters kayıt + yeni tahsilat yazar', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final entry = _paymentEntry(auth);
      final out = await _openPayment(t, auth, apartmentId: 302, apartmentLabel: 'A Blok - 6', correcting: entry);
      expect(find.text('Tahsilatı Düzelt'), findsWidgets);
      expect(
        t.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey<String>('finance_payment_amount')),
          matching: find.byType(TextField),
        )).controller!.text,
        '800,00',
      );
      expect(
        t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_method_cash'))).selected,
        isTrue,
      );
      await _enter(t, 'finance_payment_amount', '300');
      await _submit(t, 'finance_payment_submit');

      expect(auth.correctCalls.length, 1);
      expect(auth.correctCalls.single['entry_id'], 4);
      expect(auth.correctCalls.single['amount_minor'], 30000);
      expect(auth.paymentCalls, isEmpty);
      expect(out.result!.message, startsWith('Tahsilat düzeltildi: 300,00 ₺.'));
      expect(out.result!.result.reversal, isNotNull);
      // Defter: eski tahsilat silinmedi; ters kaydı + yeni tahsilat eklendi.
      expect(auth.ledger.where((e) => e['id'] == 4).length, 1);
      expect(auth.ledger.where((e) => e['reverses_entry_id'] == 4).length, 1);
      expect(auth.balanceOf(302), 50000 - 30000);
    });

    testWidgets('düzeltme reddedilirse (kapalı dönem) hiçbir yarım kayıt kalmaz', (t) async {
      // Eski tahsilat eylülde yapılmıştı; düzeltilen tahsilat da o tarihle yazılır -> eylül kapalı.
      final auth = FinanceFakeAuth.seeded()..closedPeriods.add('2026-09');
      final entry = _paymentEntry(auth);
      await _openPayment(t, auth, apartmentId: 302, apartmentLabel: 'A Blok - 6', correcting: entry);
      await _enter(t, 'finance_payment_amount', '300');
      final before = auth.ledger.length;
      await _submit(t, 'finance_payment_submit');
      expect(find.text(AuthApi.messageForErrorCode('PERIOD_CLOSED')!), findsOneWidget);
      expect(auth.ledger.length, before, reason: 'ters kayıt dahil hiçbir şey yazılmadı');
    });
  });

  group('kayıt iptali', () {
    testWidgets('neden zorunlu; kırpılıp gönderilir; ters kayıt eklenir, kayıt silinmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openReverse(t, auth, _paymentEntry(auth));
      await _submit(t, 'finance_reverse_submit');
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.text('İptal nedenini yazın.'), findsOneWidget);
      expect(auth.reverseCalls, isEmpty);

      await _enter(t, 'finance_reverse_reason', '  Yanlış daireye girildi  ');
      await _submit(t, 'finance_reverse_submit');
      expect(auth.reverseCalls.length, 1);
      expect(auth.reverseCalls.single['reason'], 'Yanlış daireye girildi');
      expect((auth.reverseCalls.single['idempotency_key'] as String).isNotEmpty, isTrue);
      expect(out.closed, isTrue);
      expect(out.result!.message, startsWith('Kayıt iptal edildi (ters kayıt eklendi).'));
      expect(auth.ledger.where((e) => e['id'] == 4).length, 1, reason: 'asıl kayıt silinmez');
      expect(auth.balanceOf(302), 50000, reason: 'ters kayıt bakiyeyi düzeltir');
    });

    testWidgets('neden sınırı 200 kod noktası', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openReverse(t, auth, _paymentEntry(auth));
      await _enter(t, 'finance_reverse_reason', 'a' * 201);
      await _submit(t, 'finance_reverse_submit');
      expect(find.text('Neden en çok 200 karakter olabilir.'), findsOneWidget);
      expect(auth.reverseCalls, isEmpty);
    });

    testWidgets('zaten iptal edilmiş kayıt: Türkçe hata, pencere açık, kapanırken liste tazelenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      // Başka bir yönetici önce iptal etti.
      await auth.reverseFinanceEntry(11, 4, reason: 'x', idempotencyKey: 'ilk');
      final out = await _openReverse(t, auth, _paymentEntry(auth));
      await _enter(t, 'finance_reverse_reason', 'Tekrar');
      await _submit(t, 'finance_reverse_submit');
      expect(find.text(AuthApi.messageForErrorCode('ENTRY_ALREADY_REVERSED')!), findsOneWidget);
      expect(out.closed, isFalse);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.refreshes, 1, reason: 'kayıt durumu eskidi: liste tazelenir');
    });

    testWidgets('gönderim sürerken çift dokunuş tek istek; geri tuşu kapatmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..paymentGate = Completer<void>();
      final out = await _openReverse(t, auth, _paymentEntry(auth));
      await _enter(t, 'finance_reverse_reason', 'Neden');
      await _submit(t, 'finance_reverse_submit');
      expect(find.text('İptal ediliyor...'), findsOneWidget);
      await t.tap(find.text('İptal ediliyor...'), warnIfMissed: false);
      await t.pump();
      expect(auth.reverseCalls.length, 1);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(FinanceReverseDialog), findsOneWidget);
      auth.paymentGate!.complete();
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(auth.reverseCalls.length, 1);
    });
  });
}
