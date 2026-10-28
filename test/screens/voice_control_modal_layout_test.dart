// FAZ 5 / A2-G5: VoiceControlModal (alt sayfa) taşma testi (AGENTS.md kural 6).
//
// `showModalBottomSheet` ile açılır (alt sayfa tipi KORUNUR). Açılışta otomatik dinleme başlar;
// mikrofon nabzı YALNIZ dinlerken döner (durağan durumda ticker yok) ve hareket azaltmada çevrilmez.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_control_modal.dart';

import '../design/harness.dart' show recordHaptics;
import 'dialog_layout_harness.dart';
import 'voice_fake.dart';

/// Durumun beklenen küre tonu (sözleşme: dinliyor/başarı success, işleniyor primary, hata danger, boşta info).
AppTone _toneFor(VoiceStatus status) => switch (status) {
  VoiceStatus.listening || VoiceStatus.success => AppTone.success,
  VoiceStatus.processing => AppTone.primary,
  VoiceStatus.error => AppTone.danger,
  VoiceStatus.initializing || VoiceStatus.idle => AppTone.info,
};

void main() {
  for (final c in <(String, VoiceStatus, String)>[
    ('boşta', VoiceStatus.idle, ''),
    (
      'dinliyor',
      VoiceStatus.listening,
      'Dinleniyor... "Kapıyı aç" diyebilirsiniz.',
    ),
    ('komut işleniyor', VoiceStatus.processing, '"kapıyı aç"'),
    (
      'hata',
      VoiceStatus.error,
      'Mikrofon izni verilmediği için komut dinlenemiyor; lütfen ayarlardan izin verin.',
    ),
  ]) {
    layoutMatrix('VoiceControlModal (${c.$1})', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final voice = FakeVoiceDoorService(
        startStatus: c.$2 == VoiceStatus.idle ? null : c.$2,
        startFeedback: c.$3,
      );
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Sesli Kapı Kontrolü'), findsOneWidget);
      // Dinleme göstergesi: tek cilalı küre (IconOrb), durumun tonunda; düzene girmeyen aura statiktir.
      expect(find.byType(IconOrb), findsOneWidget);
      expect(t.widget<IconOrb>(find.byType(IconOrb)).tone, _toneFor(c.$2));
      expect(t.widget<IconOrb>(find.byType(IconOrb)).size, 92);
      expect(find.text('Kapat'), findsOneWidget);
      expect(
        find.text(c.$2 == VoiceStatus.listening ? 'Durdur' : 'Tekrar Dinle'),
        findsOneWidget,
      );
      if (c.$3.isNotEmpty) {
        expect(find.text(c.$3), findsOneWidget);
      }
      await scrollTo(t, find.text('Kapat'));

      // Hata durumunda alt sayfa 2,5 sn sonra kendiliğinden kapanır; bekleyen zamanlayıcı kalmasın.
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'VoiceControlModal: mikrofon düğmesi dinlemeyi durdurur; nabız yalnız dinlerken döner',
    (t) async {
      final voice = FakeVoiceDoorService(startStatus: VoiceStatus.listening);
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(voice.startCalls, 1, reason: 'açılışta otomatik dinleme başlar');
      expect(voice.isListening, isTrue);
      // Dinlerken nabız ticker'ı çalışır.
      expect(t.hasRunningAnimations, isTrue);

      await t.tap(find.text('Durdur'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(voice.stopCalls, greaterThanOrEqualTo(1));
      // Boşta: ticker kalmaz (modalın nabzı durdu).
      voice.notifyListeners();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Tekrar Dinle'), findsOneWidget);
      // Durum değişimi küre ve durum metni için tek seferlik belirme (Pop, 200 ms) başlatır: o sonlu
      // animasyon bitince durağan durumda ticker KALMAMALIDIR (iddia aynı: nabız durdu, süs döngüsü yok).
      await t.pump(const Duration(milliseconds: 400));
      expect(t.hasRunningAnimations, isFalse);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'VoiceControlModal: komut gönderildi (başarı) anında bir kez hafif haptik; sonra kendiliğinden kapanır',
    (t) async {
      final haptics = recordHaptics(t);
      final voice = FakeVoiceDoorService(
        startStatus: VoiceStatus.success,
        startFeedback: 'Ana kapı için açma komutu gönderildi.',
      );
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      // Dürüst dil (P1-15): başarı = komutun sunucuca kabulü; kapının açıldığı iddia edilmez.
      expect(find.text('Komut Gönderildi'), findsOneWidget);
      expect(find.text('Ana kapı için açma komutu gönderildi.'), findsOneWidget);
      expect(find.textContaining('Açıldı'), findsNothing);
      expect(find.textContaining('açıldı'), findsNothing);
      expect(
        haptics.where((h) => h.contains('lightImpact')),
        hasLength(1),
        reason: 'başarıya geçişte tek haptik',
      );
      // Aynı durumda tekrar bildirim ikinci haptik üretmez.
      voice.notifyListeners();
      await t.pump(const Duration(milliseconds: 100));
      expect(haptics.where((h) => h.contains('lightImpact')), hasLength(1));
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'VoiceControlModal: hareket azaltmada dinlerken de nabız çevrilmez',
    (t) async {
      final voice = FakeVoiceDoorService(startStatus: VoiceStatus.listening);
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
        reduce: true,
      );
      expect(voice.isListening, isTrue);
      expect(t.hasRunningAnimations, isFalse);
      expect(t.takeException(), isNull);
    },
  );
}
