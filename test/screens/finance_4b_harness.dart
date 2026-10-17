// Platform Faz 4b: ekran / pencere testlerinin ortak düzeneği (taşma matrisi + kısa yardımcılar).
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5 ZORUNLU; ek olarak yatay telefon (640x360 x2,0 — görev
// şartı: yatayda da büyük yazı) ve tablet (820x1180). Her hücre açık + koyu tema.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dialog_layout_harness.dart' show scrollTo, settleFor;

const List<(double, double, double)> kF4Cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (820, 1180, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalı.
void f4Matrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kF4Cells) {
    for (final dark in const <bool>[false, true]) {
      final label =
          '$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok';
      testWidgets(label, (t) async {
        await body(t, width, height, scale, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

/// Ekran okuyucu ağacında HAM tutar yazımı ("2.500,00 ₺") taşıyan etiketler. Para, okunuşla ("iki bin beş yüz lira")
/// verilmelidir (`moneySemanticLabel` / `spokenMoneyText`); ham rakam yığını basamak basamak okunur.
final RegExp kRawMoney = RegExp(r'\d[\d.]*,\d{2}\s?₺');

List<String> f4RawMoneyLabels(WidgetTester t) {
  final found = <String>[];
  final root = t.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root == null) return found;
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    for (final text in <String>[data.label, data.value, data.hint, data.tooltip]) {
      if (kRawMoney.hasMatch(text)) found.add(text);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return found;
}

/// Ekranda ham tutar okunuşu kalmadığını doğrular (R14: okunan para ifadeleri). Anlamsal ağaç için önce `ensureSemantics`.
void f4ExpectSpokenMoney(WidgetTester t) {
  expect(f4RawMoneyLabels(t), isEmpty, reason: 'ekran okuyucuya ham tutar yazımı sızdı');
}

/// Anahtarlı öğeye kaydırıp dokunur ve giriş / geçiş animasyonunu bitirir.
Future<void> f4Tap(WidgetTester t, String key, {int milliseconds = 450}) async {
  final finder = find.byKey(ValueKey<String>(key));
  expect(finder, findsAtLeastNWidgets(1), reason: 'öğe yok: $key');
  await scrollTo(t, finder.first);
  await t.tap(finder.first);
  await t.pump();
  await t.pump(Duration(milliseconds: milliseconds));
}

/// Metne (ilk eşleşme) kaydırıp dokunur.
Future<void> f4TapText(WidgetTester t, String text, {int milliseconds = 450}) async {
  final finder = find.text(text);
  expect(finder, findsAtLeastNWidgets(1), reason: 'metin yok: $text');
  await scrollTo(t, finder.first);
  await t.tap(finder.first);
  await t.pump();
  await t.pump(Duration(milliseconds: milliseconds));
}

/// Anahtarlı metin alanına yazar.
Future<void> f4Enter(WidgetTester t, String key, String text) async {
  final finder = find.byKey(ValueKey<String>(key));
  expect(finder, findsOneWidget, reason: 'alan yok: $key');
  await scrollTo(t, finder);
  await t.enterText(finder, text);
  await t.pump();
}

/// Açık pencerenin (son AlertDialog) içindeki [label] düğmesine dokunur.
Future<void> f4TapInDialog(WidgetTester t, String label, {int milliseconds = 450}) async {
  final finder = find.descendant(of: find.byType(AlertDialog).last, matching: find.text(label));
  expect(finder, findsAtLeastNWidgets(1), reason: 'pencerede "$label" yok');
  await t.ensureVisible(finder.first);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(finder.first);
  await t.pump();
  await t.pump(Duration(milliseconds: milliseconds));
}

/// Kaydedilmemiş veri koruması (R14): [open] pencereyi açar (içinde [markerKey] anahtarlı bir öğe vardır), [edit] bir alanı değiştirir.
///  a) değişiklik YOKKEN "Vazgeç" onaysız kapatır;
///  b) değişiklikten sonra "Vazgeç" onay sorar; "Düzenlemeye Dön" pencereyi ve veriyi korur;
///  c) geri tuşu (sistem geri) AYNI onayı sorar; "Vazgeç ve Kapat" kapatır.
Future<void> f4ExpectDiscardGuard(
  WidgetTester t, {
  required Future<void> Function() open,
  required Future<void> Function() edit,
  required String markerKey,
}) async {
  final marker = find.byKey(ValueKey<String>(markerKey));
  await open();
  expect(marker, findsOneWidget, reason: 'pencere açık olmalı');
  await f4TapInDialog(t, 'Vazgeç');
  expect(find.text('Değişiklikler silinsin mi?'), findsNothing, reason: 'değişiklik yok: onay sorulmaz');
  expect(marker, findsNothing, reason: 'değişiklik yok: pencere kapanır');

  await open();
  await edit();
  await f4TapInDialog(t, 'Vazgeç');
  expect(find.text('Değişiklikler silinsin mi?'), findsOneWidget);
  expect(marker, findsOneWidget, reason: 'onay beklenirken pencere açık');
  await f4TapInDialog(t, 'Düzenlemeye Dön');
  expect(find.text('Değişiklikler silinsin mi?'), findsNothing);
  expect(marker, findsOneWidget, reason: 'Düzenlemeye Dön: veri korunur');

  await t.binding.handlePopRoute();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
  expect(find.text('Değişiklikler silinsin mi?'), findsOneWidget, reason: 'geri tuşu da onay sorar');
  expect(marker, findsOneWidget);
  await f4TapInDialog(t, 'Vazgeç ve Kapat');
  expect(find.text('Değişiklikler silinsin mi?'), findsNothing);
  expect(marker, findsNothing, reason: 'Vazgeç ve Kapat: pencere kapanır');
}

/// Ekranda hiçbir yerde görünmemesi gereken teknik ifadeler (ham kod, durum numarası).
void expectNoTechnicalText(WidgetTester t) {
  for (final text in const ['Exception', 'FormatException', 'null', 'Instance of']) {
    expect(find.textContaining(text), findsNothing, reason: 'teknik ifade sızdı: $text');
  }
}

/// Kısa ilerletme (`settleFor` yeniden dışa aktarımı).
Future<void> f4Settle(WidgetTester t, [int milliseconds = 500]) => settleFor(t, milliseconds);
