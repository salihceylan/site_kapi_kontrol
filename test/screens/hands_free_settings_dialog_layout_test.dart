// FAZ 5 / A2-G5: HandsFreeSettingsDialog (alt sayfa) taşma testi (AGENTS.md kural 6).
//
// `showModalBottomSheet` ile açılır (alt sayfa tipi KORUNUR): başlık şeridi sabit, dört kart ve
// güvenlik notu kaydırılan listede akar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
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
