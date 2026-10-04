// Küçük/orta diyalogların ortak görsel parçaları: DialogToggleTile, DialogInfoRow, dialogLargeText.
//
// Sözleşmeler: taşma yok (320/360/412/820 dp x yazı 1,0/1,5/2,0 x açık/koyu), kararlı durumda ticker
// yok, hareket azaltmada anında geçiş, tek anlamsal düğüm (açık/kapalı durumu), büyük yazıda süs
// rozeti yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

import '../design/harness.dart';

/// Diyalog içeriği genişliğinde (AppDialog ile aynı hesap) tam genişlikli sınama alanı.
Widget _inDialogWidth(Widget child) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.all(AppSpace.lg),
    child: SizedBox(width: dialogWidthForScreen(context), child: child),
  ),
);

Widget _toggleHost(ValueNotifier<bool> value, {bool enabled = true}) {
  return ValueListenableBuilder<bool>(
    valueListenable: value,
    builder: (context, on, _) => DialogToggleTile(
      title: 'Hesap Aktif',
      subtitle: on ? 'Kullanıcı giriş yapabilir.' : 'Kullanıcı giriş yapamaz.',
      value: on,
      onChanged: enabled ? (v) => value.value = v : null,
      onIcon: Icons.how_to_reg_rounded,
      offIcon: Icons.person_off_rounded,
    ),
  );
}

void main() {
  group('dialogLargeText', () {
    Future<bool> read(WidgetTester t, double scale) async {
      late bool result;
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) {
              result = dialogLargeText(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('1,3 ve altı normal, üstü büyük yazıdır', (t) async {
      expect(await read(t, 1.0), isFalse);
      expect(await read(t, 1.3), isFalse);
      expect(await read(t, 1.5), isTrue);
      expect(await read(t, 2.0), isTrue);
    });
  });

  group('DialogToggleTile', () {
    testWidgets('dokununca değişir; rozet durumu anlatır (açık: success, kapalı: neutral)', (
      t,
    ) async {
      final value = ValueNotifier<bool>(true);
      addTearDown(value.dispose);
      await pumpAt(t, _inDialogWidth(_toggleHost(value)), width: 360, scale: 1.0);

      IconOrb orb() => t.widget<IconOrb>(find.byType(IconOrb));
      expect(orb().icon, Icons.how_to_reg_rounded);
      expect(orb().tone, AppTone.success);
      expect(orb().size, 40);
      expect(orb().shape, IconOrbShape.squircle);
      expect(find.text('Kullanıcı giriş yapabilir.'), findsOneWidget);

      await t.tap(find.text('Hesap Aktif'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(value.value, isFalse);
      expect(find.byType(IconOrb), findsOneWidget, reason: 'eski rozet solma sonunda kalkar');
      expect(orb().icon, Icons.person_off_rounded);
      expect(orb().tone, AppTone.neutral);
      expect(find.text('Kullanıcı giriş yapamaz.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('özel ikon/ton verilebilir (kapalı: warning)', (t) async {
      await pumpAt(
        t,
        _inDialogWidth(
          DialogToggleTile(
            title: 'E-Posta Doğrulandı',
            subtitle: 'E-posta henüz doğrulanmamış.',
            value: false,
            onChanged: (_) {},
            onIcon: Icons.mark_email_read_rounded,
            offIcon: Icons.mark_email_unread_rounded,
            offTone: AppTone.warning,
          ),
        ),
        width: 360,
        scale: 1.0,
      );
      final orb = t.widget<IconOrb>(find.byType(IconOrb));
      expect(orb.icon, Icons.mark_email_unread_rounded);
      expect(orb.tone, AppTone.warning);
    });

    testWidgets('büyük yazıda (2,0) rozet bırakılır, metin ve anahtar kalır', (t) async {
      final value = ValueNotifier<bool>(true);
      addTearDown(value.dispose);
      await pumpAt(t, _inDialogWidth(_toggleHost(value)), width: 320, scale: 2.0);
      expect(find.byType(IconOrb), findsNothing);
      expect(find.text('Hesap Aktif'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('anlamsal ağaç: tek düğüm, başlık + alt başlık, açık/kapalı durumu', (t) async {
      final handle = t.ensureSemantics();
      final value = ValueNotifier<bool>(true);
      addTearDown(value.dispose);
      await pumpAt(t, _inDialogWidth(_toggleHost(value)), width: 360, scale: 1.0);

      final node = t.getSemantics(find.text('Hesap Aktif'));
      expect(node, isSemantics(hasToggledState: true, isToggled: true, hasEnabledState: true, isEnabled: true));
      final label = node.getSemanticsData().label;
      expect(label, contains('Hesap Aktif'));
      expect(label, contains('Kullanıcı giriş yapabilir.'));

      await t.tap(find.text('Hesap Aktif'));
      await t.pump();
      expect(
        t.getSemantics(find.text('Hesap Aktif')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      handle.dispose();
    });

    testWidgets('onChanged null ise satır devre dışıdır ve dokunuş değiştirmez', (t) async {
      final handle = t.ensureSemantics();
      final value = ValueNotifier<bool>(true);
      addTearDown(value.dispose);
      await pumpAt(t, _inDialogWidth(_toggleHost(value, enabled: false)), width: 360, scale: 1.0);

      expect(
        t.getSemantics(find.text('Hesap Aktif')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      await t.tap(find.text('Hesap Aktif'), warnIfMissed: false);
      await t.pump();
      expect(value.value, isTrue);
      handle.dispose();
    });

    testWidgets('kararlı durumda ticker yok; hareket azaltmada geçiş anında', (t) async {
      final value = ValueNotifier<bool>(true);
      addTearDown(value.dispose);
      await pumpAt(t, _inDialogWidth(_toggleHost(value)), width: 360, scale: 1.0);
      expect(t.binding.transientCallbackCount, 0);

      await t.tap(find.text('Hesap Aktif'));
      await t.pump();
      // Rozet solması (200 ms), anahtar ve mürekkep dalgası bitene kadar.
      await t.pump(const Duration(seconds: 1));
      expect(t.binding.transientCallbackCount, 0, reason: 'geçiş bitince ticker kalmaz');

      // Hareket azaltma: süre sıfır; zaman ilerletmeden tek rozet kalır.
      await pumpAt(t, _inDialogWidth(_toggleHost(value)), width: 360, scale: 1.0, reduce: true);
      await t.tap(find.text('Hesap Aktif'));
      await t.pump();
      await t.pump();
      expect(find.byType(IconOrb), findsOneWidget);
      expect(t.widget<IconOrb>(find.byType(IconOrb)).icon, Icons.how_to_reg_rounded);
    });

    testWidgets('taşma yok: tüm genişlik x yazı ölçeği x tema matrisi', (t) async {
      await forEachHarnessCell((width, scale, dark) async {
        final value = ValueNotifier<bool>(false);
        addTearDown(value.dispose);
        await pumpAt(
          t,
          _inDialogWidth(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toggleHost(value),
                const SizedBox(height: AppSpace.md),
                DialogToggleTile(
                  title: 'E-Posta Doğrulandı ve çok uzun bir başlık metni',
                  subtitle:
                      'E-posta henüz doğrulanmamış; kullanıcı doğrulama bağlantısını açana kadar bekler.',
                  value: true,
                  onChanged: (_) {},
                  onIcon: Icons.mark_email_read_rounded,
                  offIcon: Icons.mark_email_unread_rounded,
                ),
              ],
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(find.byType(DialogToggleTile), findsNWidgets(2));
      });
    });
  });

  group('DialogInfoRow', () {
    testWidgets('rozet 40 dp squircle; başlık, alt satır ve rozetler görünür', (t) async {
      await pumpAt(
        t,
        _inDialogWidth(
          const DialogInfoRow(
            icon: Icons.apartment_rounded,
            tone: AppTone.info,
            title: 'Güneş Sitesi',
            subtitle: 'Kadıköy',
            chips: [
              StatusChip(label: 'ESP32-C3', tone: AppTone.primary),
              StatusChip(label: 'Online', tone: AppTone.success),
            ],
          ),
        ),
        width: 360,
        scale: 1.0,
      );
      final orb = t.widget<IconOrb>(find.byType(IconOrb));
      expect(orb.size, 40);
      expect(orb.shape, IconOrbShape.squircle);
      expect(orb.tone, AppTone.info);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(find.text('Kadıköy'), findsOneWidget);
      expect(find.byType(StatusChip), findsNWidgets(2));
    });

    testWidgets('kısa başlık rozete dikeyde ortalanır', (t) async {
      await pumpAt(
        t,
        _inDialogWidth(
          const DialogInfoRow(icon: Icons.meeting_room_rounded, title: 'Kapı: A'),
        ),
        width: 360,
        scale: 1.0,
      );
      final orbRect = t.getRect(find.byType(IconOrb));
      final textRect = t.getRect(find.text('Kapı: A'));
      expect(textRect.center.dy, closeTo(orbRect.center.dy, 1.0));
    });

    testWidgets('büyük yazıda rozet yok, metin ve rozetler (chip) kalır', (t) async {
      await pumpAt(
        t,
        _inDialogWidth(
          const DialogInfoRow(
            icon: Icons.apartment_rounded,
            title: 'Güneş Sitesi',
            chips: [StatusChip(label: 'İstanbul / Kadıköy', tone: AppTone.info)],
          ),
        ),
        width: 320,
        scale: 2.0,
      );
      expect(find.byType(IconOrb), findsNothing);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(find.byType(StatusChip), findsOneWidget);
    });

    testWidgets('anlamsal ağaç: başlık tek etiket olarak okunur (rozet etikete karışmaz)', (t) async {
      final handle = t.ensureSemantics();
      await pumpAt(
        t,
        _inDialogWidth(
          const DialogInfoRow(icon: Icons.apartment_rounded, title: 'Güneş Sitesi'),
        ),
        width: 360,
        scale: 1.0,
      );
      expect(
        t.getSemantics(find.text('Güneş Sitesi')).getSemanticsData().label,
        'Güneş Sitesi',
      );
      handle.dispose();
    });

    testWidgets('taşma yok: tüm genişlik x yazı ölçeği x tema matrisi (uzun başlık + rozetler)', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          _inDialogWidth(
            const DialogInfoRow(
              icon: Icons.phonelink_erase_rounded,
              tone: AppTone.danger,
              title:
                  'Eski (Arızalı) Cihaz: ESP32_C3_ARIZALI_CIHAZ_0001_ÇOK_UZUN_BİR_SERİ_NUMARASI',
              subtitle: 'Alt satır da uzun bir açıklama metni olabilir ve satıra sarar.',
              chips: [
                StatusChip(label: 'ESP32-WROOM', tone: AppTone.violet, icon: Icons.memory_rounded),
                StatusChip(label: 'Çok uzun bir durum rozeti etiketi', tone: AppTone.warning),
              ],
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(find.byType(DialogInfoRow), findsOneWidget);
      });
    });
  });
}
