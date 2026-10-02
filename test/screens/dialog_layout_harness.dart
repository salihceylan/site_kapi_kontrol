// FAZ 5 / A2-G5: diyalog taşma testlerinin ortak düzeneği.
//
// AGENTS.md kural 6: hiçbir ekranda taşma olmaz. Her diyalog için zorunlu iki hücre sınanır: 320x640
// yazı ölçeği 2,0 ve 360x640 yazı ölçeği 1,5 (ek: yatay telefon 640x360 ve tablet 820x1180); her hücre
// açık ve koyu temada. Diyalog gerçek `showDialog` ile açılır (`pumpAt` ölçü/ölçek/tema düzeneği);
// taşma dahil çerçeve hatası kalmamalıdır.
//
// Bu dosya `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/harness.dart';

/// (genişlik, yükseklik, yazı ölçeği): AGENTS.md kural 6 matrisi.
///
/// 320x640 x2,0 ve 360x640 x1,5 zorunlu hücrelerdir; ek olarak yatay telefon (640x360) ve tablet
/// (820x1180) ayrıca doğrulanır (kural 6: yatay ve tablet/masaüstü de taşmamalı).
const List<(double, double, double)> kLayoutCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 1.0),
  (820, 1180, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder.
void layoutMatrix(
  String name,
  Future<void> Function(
    WidgetTester t,
    double width,
    double height,
    double scale,
    bool dark,
  )
  body,
) {
  for (final (width, height, scale) in kLayoutCells) {
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

/// [opener] diyaloğu açar (genellikle `XxxDialog.show(context, ...)`); düğmeye dokunulup diyalog
/// girişi (~450 ms) bitene kadar ilerletilir. `pumpAndSettle` KULLANILMAZ: yüklenirken dönen
/// göstergeler (CircularProgressIndicator) bitmeyen animasyondur.
Future<void> openDialogAt(
  WidgetTester t,
  Future<void> Function(BuildContext context) opener, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
  bool reduce = false,
}) async {
  await pumpAt(
    t,
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => opener(context),
        child: const Text('Aç'),
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
  await t.tap(find.text('Aç'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull);
}

/// Kısa süre ilerletir (ağ/animasyon sonrası). `pumpAndSettle` değildir: sonsuz animasyonda takılmaz.
Future<void> settleFor(WidgetTester t, [int milliseconds = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: milliseconds));
}

/// [finder]'ı görünür alana kaydırır ve bir kare çizer (kaydırılabilir diyalog içeriği için).
Future<void> scrollTo(WidgetTester t, Finder finder) async {
  // Önce bekleyen kaydırma animasyonlarının bitmesini bekle: odaktaki bir metin alanının imleç-
  // görünür-kaydırması (`enterText` sonrası) kaydırıcıyı geri çeker ve sürerken dokunuşları yok sayar.
  await t.pump(const Duration(milliseconds: 800));
  await t.ensureVisible(finder);
  await t.pump(const Duration(milliseconds: 300));
}

/// Tembel (lazy) liste/sliver içinde henüz KURULMAMIŞ bir öğeye ulaşmak için: [scrollable] (örn.
/// `find.byType(CustomScrollView)`) aşağı sürüklenir; [finder] ağaçta belirince görünür alana alınır.
Future<void> scrollIntoBuilt(
  WidgetTester t,
  Finder finder,
  Finder scrollable,
) async {
  // `dragUntilVisible` tek eşleşme ister; burada çok eşleşmeli bulucular da (örn. menü düğmeleri) olur.
  var guard = 0;
  while (finder.evaluate().isEmpty && guard < 60) {
    await t.drag(scrollable, const Offset(0, -200));
    await t.pump();
    guard++;
  }
  expect(finder, findsAtLeastNWidgets(1));
  await t.ensureVisible(finder.first);
  await t.pump(const Duration(milliseconds: 300));
}
