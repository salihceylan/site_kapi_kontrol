// Saha denemesi F3.03: sakin Panel'inin en üstünde okunmamış duyuru KARTI (yumuşak nabız, "Oku", "+N duyuru daha").
// Bileşen testleri: içerik, düğmeler, anlamsal etiket (canlı bölge DEĞİL), nabız hızı (sert flaş yok),
// hareketi azalt / test anahtarı ile durağan, açık + koyu tema ve taşma matrisi.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/widgets/unread_announcement_card.dart';

import '../design/harness.dart';

ResidentAnnouncement _item({String title = 'Asansör bakımı', String preview = 'Yarın 09:00-12:00 arası asansör hizmet vermeyecek.'}) =>
    ResidentAnnouncement(id: 7, title: title, bodyPreview: preview);

Widget _card({
  ResidentAnnouncement? announcement,
  int more = 0,
  bool? pulse,
  VoidCallback? onOpen,
  VoidCallback? onAll,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: UnreadAnnouncementCard(
    announcement: announcement ?? _item(),
    moreCount: more,
    pulse: pulse,
    onOpen: onOpen ?? () {},
    onOpenAll: onAll,
  ),
);

/// Kartın dış parıltısının (BoxShadow) o anki saydamlığı.
double _glowAlpha(WidgetTester t) {
  final box = t.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(UnreadAnnouncementCard),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  final decoration = box.decoration as BoxDecoration;
  return decoration.boxShadow!.first.color.a;
}

void main() {
  testWidgets('başlık, özet ve Oku görünür; +N yalnız sayı > 0 ve eylem varken', (t) async {
    var opened = 0;
    var all = 0;
    await pumpAt(
      t,
      _card(more: 2, onOpen: () => opened++, onAll: () => all++),
      width: 400,
      height: 800,
      scale: 1.0,
    );
    expect(find.text('Yeni duyuru'), findsOneWidget);
    expect(find.text('Asansör bakımı'), findsOneWidget);
    expect(find.textContaining('asansör hizmet vermeyecek'), findsOneWidget);
    expect(find.text('+2 duyuru daha'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('unread_announcement_open')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('unread_announcement_more')));
    await t.pump();
    expect(opened, 1);
    expect(all, 1);

    await pumpAt(t, _card(more: 0, onAll: () {}), width: 400, height: 800, scale: 1.0);
    expect(find.byKey(const ValueKey<String>('unread_announcement_more')), findsNothing);
  });

  testWidgets('anlamsal etiket "Yeni duyuru: başlık", canlı bölge DEĞİL; Oku odaklanabilir düğme', (t) async {
    final handle = t.ensureSemantics();
    await pumpAt(t, _card(more: 1, onAll: () {}), width: 400, height: 800, scale: 1.0);

    final node = t.getSemantics(find.bySemanticsLabel(RegExp(r'^Yeni duyuru: Asansör bakımı')).first);
    expect(node.label, 'Yeni duyuru: Asansör bakımı');
    expect(node.flagsCollection.isLiveRegion, isFalse);

    final open = t.getSemantics(find.byKey(const ValueKey<String>('unread_announcement_open')));
    expect(open.flagsCollection.isButton, isTrue);
    expect(open.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    // Klavye ile odaklanabilir: ilk Tab "Oku" düğmesine gelir.
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    var onOpenButton = false;
    focused!.visitAncestorElements((e) {
      if (e.widget.key == const ValueKey<String>('unread_announcement_open')) onOpenButton = true;
      return !onOpenButton;
    });
    expect(onOpenButton, isTrue);
    expect(open.label, contains('Oku'));
    handle.dispose();
  });

  testWidgets('boş başlık "Başlıksız duyuru" yazar', (t) async {
    await pumpAt(t, _card(announcement: _item(title: '  ', preview: '')), width: 400, height: 800, scale: 1.0);
    expect(find.text('Başlıksız duyuru'), findsOneWidget);
  });

  group('nabız animasyonu', () {
    testWidgets('açıkken parıltı yavaşça değişir: örnekler arası küçük adım, saniyede 3\'ten az tam tur', (t) async {
      await pumpAt(t, _card(pulse: true), width: 400, height: 800, scale: 1.0);
      final samples = <double>[_glowAlpha(t)];
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 100));
        samples.add(_glowAlpha(t));
      }
      var maxStep = 0.0;
      var turns = 0; // yön değişimi sayısı
      var lastSign = 0;
      for (var i = 1; i < samples.length; i++) {
        final d = samples[i] - samples[i - 1];
        if (d.abs() > maxStep) maxStep = d.abs();
        final sign = d == 0 ? 0 : (d > 0 ? 1 : -1);
        if (sign != 0 && lastSign != 0 && sign != lastSign) turns++;
        if (sign != 0) lastSign = sign;
      }
      final range = samples.reduce((a, b) => a > b ? a : b) - samples.reduce((a, b) => a < b ? a : b);
      expect(range, greaterThan(0.2), reason: 'nabız görünür olmalı');
      expect(maxStep, lessThan(0.12), reason: 'sert flaş yok: 100 ms\'de küçük adım');
      // 4 sn'de en çok ~3 yön değişimi (tam tur ~3 sn): saniyede 3 flaştan çok uzak.
      expect(turns, lessThanOrEqualTo(3));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('hareketi azalt açıkken durağan ve vurgulu (pumpAndSettle biter)', (t) async {
      await pumpAt(t, _card(pulse: true), width: 400, height: 800, scale: 1.0, reduce: true);
      final a = _glowAlpha(t);
      await t.pump(const Duration(milliseconds: 700));
      expect(_glowAlpha(t), a);
      expect(a, greaterThan(0.45), reason: 'durağan hâl vurgulu');
      await t.pumpAndSettle();
    });

    testWidgets('pulse false ya da test anahtarı kapalıyken durağan (pumpAndSettle biter)', (t) async {
      expect(UnreadAnnouncementCard.pulseEnabledByDefault, isFalse, reason: 'flutter_test_config kapatır');
      await pumpAt(t, _card(), width: 400, height: 800, scale: 1.0);
      await t.pumpAndSettle();
      final a = _glowAlpha(t);
      await t.pump(const Duration(milliseconds: 700));
      expect(_glowAlpha(t), a);

      await pumpAt(t, _card(pulse: false), width: 400, height: 800, scale: 1.0);
      await t.pumpAndSettle();
    });

    testWidgets('anahtar açılınca varsayılan olarak nabız atar; geri alınır', (t) async {
      UnreadAnnouncementCard.pulseEnabledByDefault = true;
      addTearDown(() => UnreadAnnouncementCard.pulseEnabledByDefault = false);
      await pumpAt(t, _card(), width: 400, height: 800, scale: 1.0);
      final a = _glowAlpha(t);
      await t.pump(const Duration(milliseconds: 700));
      expect(_glowAlpha(t), isNot(a));
      await t.pumpWidget(const SizedBox());
    });
  });

  testWidgets('taşma matrisi: 320x640@2,0 koyu, 360x640@1,5 açık, 640x360@2,0, tablet; çok uzun metin', (t) async {
    final long = _item(
      title: 'Çok uzun başlıklı site genel kurul toplantısı ve yıllık bütçe görüşmesi duyurusu ' * 2,
      preview: 'Çok uzun özet metni, kapıcı ve güvenlik görevlisi ile ilgili önemli değişiklikler hakkında bilgilendirme. ' * 3,
    );
    for (final cell in const <(double, double, double, bool)>[
      (320, 640, 2.0, true),
      (320, 640, 2.0, false),
      (360, 640, 1.5, false),
      (360, 640, 1.5, true),
      (640, 360, 2.0, false),
      (640, 360, 2.0, true),
      (800, 1280, 1.0, false),
      (1024, 768, 1.0, true),
    ]) {
      await pumpAt(
        t,
        _card(announcement: long, more: 12, onAll: () {}),
        width: cell.$1,
        height: cell.$2,
        scale: cell.$3,
        dark: cell.$4,
      );
      expect(find.text('+12 duyuru daha'), findsOneWidget, reason: '${cell.$1}x${cell.$2}@${cell.$3}');
      expect(t.takeException(), isNull);
    }
  });
}
