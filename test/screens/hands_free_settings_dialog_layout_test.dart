// FAZ 5 / A2-G5: HandsFreeSettingsDialog (alt sayfa) taşma testi (AGENTS.md kural 6).
//
// `showModalBottomSheet` ile açılır (alt sayfa tipi KORUNUR): başlık şeridi sabit, dört kart ve
// güvenlik notu kaydırılan listede akar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/hands_free_settings_dialog.dart';

import 'dialog_layout_harness.dart';
import 'voice_fake.dart';

void main() {
  layoutMatrix('HandsFreeSettingsDialog (alt sayfa: dört kart + güvenlik notu)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final voice = FakeVoiceDoorService();
    await openDialogAt(
      t,
      (context) =>
          HandsFreeSettingsDialog.show(context, voiceDoorService: voice),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Eller Serbest & Araba Modu'), findsOneWidget);

    // Anahtar: servis tercihi güncellenir (büyük yazıda ilk kart ekranın altındadır: önce kaydır).
    await scrollIntoBuilt(t, find.byType(Switch), find.byType(ListView));
    expect(find.byType(Switch), findsOneWidget);
    await t.tap(find.byType(Switch));
    await settleFor(t);
    expect(voice.handsFreeAutoListen, isFalse);

    // Tüm kartları alta kadar kaydır: hiçbiri taşmaz.
    await scrollIntoBuilt(
      t,
      find.text('🏷️ NFC Araç Tutacağı Etiketi'),
      find.byType(ListView),
    );
    await scrollIntoBuilt(
      t,
      find.textContaining('Güvenlik: Bağlantı, NFC'),
      find.byType(ListView),
    );
  });

  testWidgets(
    'HandsFreeSettingsDialog: cilalı küreler, tam satır anahtar (>= 56 dp, tek anlamsal düğüm), güvenlik notu InlineNotice',
    (t) async {
      final handle = t.ensureSemantics();
      final voice = FakeVoiceDoorService();
      await openDialogAt(
        t,
        (context) =>
            HandsFreeSettingsDialog.show(context, voiceDoorService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      // Başlık küresi (AppDialogHeader, 44) + dinleme kartı küresi (info, 36).
      final orbs = t.widgetList<IconOrb>(find.byType(IconOrb)).toList();
      expect(orbs.any((o) => o.size == 44 && o.glow), isTrue, reason: 'başlık');
      expect(
        orbs.any((o) => o.size == 36 && o.tone == AppTone.info),
        isTrue,
        reason: 'dinleme kartı',
      );

      // Anahtar satırı: tam satır dokunulur (>= 56 dp) ve başlık + açıklamayla birlikte okunur.
      expect(
        t.getSize(find.byType(SwitchListTile)).height,
        greaterThanOrEqualTo(56),
      );
      expect(
        find.bySemanticsLabel(RegExp('Araba / Açılışta Dinleme Modu')),
        findsOneWidget,
      );
      await t.tap(find.text('🚗 Araba / Açılışta Dinleme Modu'));
      await settleFor(t);
      expect(voice.handsFreeAutoListen, isFalse, reason: 'satıra dokunmak anahtarı çevirir');

      // Kart küreleri ton taşır (Siri primary, Google success, NFC violet) ve güvenlik notu InlineNotice.
      await scrollIntoBuilt(
        t,
        find.byType(InlineNotice),
        find.byType(ListView),
      );
      final notice = t.widget<InlineNotice>(find.byType(InlineNotice));
      expect(notice.tone, AppTone.info);
      expect(notice.icon, Icons.verified_user_outlined);
      expect(notice.message, startsWith('Güvenlik: Bağlantı, NFC'));
      expect(
        t
            .widgetList<IconOrb>(find.byType(IconOrb))
            .any((o) => o.tone == AppTone.violet),
        isTrue,
        reason: 'NFC kartı küresi',
      );
      // Kararlı durumda hiçbir animasyon kalmaz (statik küreler, sonlu InlineNotice belirmesi).
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
      handle.dispose();
    },
  );

  testWidgets('HandsFreeSettingsDialog: kopyala düğmesi bildirim gösterir', (
    t,
  ) async {
    await openDialogAt(
      t,
      (context) => HandsFreeSettingsDialog.show(
        context,
        voiceDoorService: FakeVoiceDoorService(),
      ),
      width: 400,
      height: 900,
      scale: 1.0,
      dark: false,
    );
    await scrollIntoBuilt(t, find.byTooltip('Kopyala'), find.byType(ListView));
    await t.tap(find.byTooltip('Kopyala'));
    await settleFor(t, 700);
    expect(find.text('Siri Kestirme URL panoya kopyalandı!'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
