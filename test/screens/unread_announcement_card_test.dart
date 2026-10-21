// Saha denemesi F3.03: sakin Panel'inin en üstünde okunmamış duyuru KARTI (3 tur yanıp söner sonra durağan, "Oku", "+N duyuru daha").
// Bileşen testleri: içerik, düğmeler, anlamsal etiket (canlı bölge DEĞİL), yanıp sönme (3 tur, 4,8 sn, sonra durağan; sert flaş yok),
// hareketi azalt ile durağan, açık + koyu tema ve taşma matrisi.
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

/// Kartın kenar çerçevesinin o anki rengi.
Color _edgeColor(WidgetTester t) {
  final material = t.widget<Material>(find.byKey(const ValueKey<String>('unread_announcement_card_surface')));
  return ((material.shape! as RoundedRectangleBorder).side).color;
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
    expect(node.label, startsWith('Yeni duyuru: Asansör bakımı'));
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

  group('yanıp sönme (sınırlı)', () {
    testWidgets('3 kez yanıp söner, 4,8 sn sonra DURAĞAN vurgulu kalır (pumpAndSettle biter); gölge yok', (t) async {
      await pumpAt(t, _card(), width: 400, height: 800, scale: 1.0);
      final samples = <Color>[_edgeColor(t)];
      for (var i = 0; i < 48; i++) {
        await t.pump(const Duration(milliseconds: 100));
        samples.add(_edgeColor(t));
      }
      // Renk değişir (yanıp söner) ve en sonda durağan vurgulu renge oturur.
      expect(samples.map((c) => c.toARGB32()).toSet().length, greaterThan(5));
      await t.pumpAndSettle();
      final steady = _edgeColor(t);
      await t.pump(const Duration(seconds: 2));
      expect(_edgeColor(t), steady);
      expect(t.binding.hasScheduledFrame, isFalse, reason: 'sonsuz animasyon yok');
      final shadows = <BoxShadow>[
        for (final box in t.widgetList<DecoratedBox>(find.descendant(of: find.byType(UnreadAnnouncementCard), matching: find.byType(DecoratedBox))))
          if (box.decoration is BoxDecoration) ...?(box.decoration as BoxDecoration).boxShadow,
      ];
      expect(shadows, isEmpty);
    });

    testWidgets('hareketi azalt açıkken doğrudan durağan vurgulu', (t) async {
      await pumpAt(t, _card(), width: 400, height: 800, scale: 1.0, reduce: true);
      final a = _edgeColor(t);
      await t.pump(const Duration(milliseconds: 700));
      expect(_edgeColor(t), a);
      expect(t.binding.hasScheduledFrame, isFalse);
      // Hareketli kartın durağan hâliyle aynı renk.
      await pumpAt(t, _card(), width: 400, height: 800, scale: 1.0);
      await t.pumpAndSettle();
      expect(_edgeColor(t), a);
    });

    testWidgets('duyuru kimliği değişince yeniden başlar', (t) async {
      await pumpAt(t, _card(), width: 400, height: 800, scale: 1.0);
      await t.pumpAndSettle();
      final steady = _edgeColor(t);
      await pumpAt(t, _card(announcement: ResidentAnnouncement(id: 8, title: 'Başka', bodyPreview: '')), width: 400, height: 800, scale: 1.0);
      await t.pump(const Duration(milliseconds: 100));
      expect(_edgeColor(t), isNot(steady), reason: 'yeni duyuruda soluk renkten yeniden başlar');
      await t.pumpAndSettle();
      expect(_edgeColor(t), steady);
    });

    testWidgets('pulse false: durağan vurgulu', (t) async {
      await pumpAt(t, _card(pulse: false), width: 400, height: 800, scale: 1.0);
      expect(t.binding.hasScheduledFrame, isFalse);
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
