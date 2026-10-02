// FAZ 5 / A2-G2: ResidentDoorRemoteCard (sakin kumandası) tasarım yenileme testleri.
//
// - Taşma matrisi: 320x640 x2,0 ve 360x640 x1,5; açık + koyu; tüm durumlar (pumpAt).
// - Davranış korunur: düğme dokunuşu (kapı aç / uyarı / karekod), kapı çipleri, misafir geçişi,
//   e2e'nin bağlı olduğu etiketler ("KAPIYI AÇ", "YEREL AĞDAN AÇ", "QR KOD İLE AÇ"...).
// - Tasarım sözleşmesi: tek DoorOpenButton(circle), StatusChip, PrimaryActionButton(tonal), Pop,
//   ortak VoiceLiveBanner, yatay kaydırma YOK; kontrast >= 4,5:1; successTick.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_remote_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_live_banner.dart';

import '../design/harness.dart';
import 'g2_support.dart';

/// Sınanan kartı kurar. Varsayılan: bulutta çevrimiçi, kapı seçili; karekod + ekran + misafir açık.
Widget _card({
  DoorRecord? door,
  bool noDoor = false,
  DoorRuntimeStatus? status,
  bool noStatus = false,
  bool local = false,
  bool opening = false,
  bool loadingStatus = false,
  List<DoorRecord>? doors,
  G2FakeVoice? voice,
  VoidCallback? onOpenDoor,
  ValueChanged<int>? onSelectDoor,
  VoidCallback? onCreateGuestPass,
  int successTick = 0,
}) {
  final selected = noDoor ? null : (door ?? g2Door(qrReader: true));
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: ResidentDoorRemoteCard(
        selectedSite: null,
        selectedDoor: selected,
        doors: doors ?? (selected == null ? <DoorRecord>[] : [selected]),
        runtimeStatus: noDoor || noStatus ? null : (status ?? g2Runtime()),
        isLoadingStatus: loadingStatus,
        isOpeningDoor: opening,
        canTryLocalDoorOpen: local,
        onSelectDoor: onSelectDoor ?? (_) {},
        onOpenDoor: onOpenDoor ?? () {},
        onCreateGuestPass: onCreateGuestPass ?? () {},
        voiceDoorService: voice,
        roleColor: Colors.purple,
        successTick: successTick,
      ),
    ),
  );
}

List<DoorRecord> _threeDoors() => <DoorRecord>[
  g2Door(qrReader: true),
  g2Door(id: 8, name: 'Otopark Girişi', qrReader: true),
  g2Door(id: 9, name: 'Daire Sakinleri Kapısı ve Yaya Girişi', qrReader: true),
];

typedef _Scenario = ({String name, Widget Function() build});

final List<_Scenario> _scenarios = <_Scenario>[
  (
    name: 'bulutta çevrimiçi (3 kapı, IP rozetleri, sesli banner, 3 eylem)',
    build: () => _card(doors: _threeDoors(), voice: G2FakeVoice()),
  ),
  (
    name: 'yerel ağda aktif',
    build: () => _card(status: g2Runtime(online: false), local: true),
  ),
  (name: 'çevrimdışı', build: () => _card(status: g2Runtime(online: false))),
  (name: 'durum bilgisi yok', build: () => _card(noStatus: true)),
  (
    name: 'yalnız karekod, çevrimiçi',
    build: () => _card(door: g2Door(remote: false, qrReader: true)),
  ),
  (
    name: 'yalnız karekod, çevrimdışı',
    build: () => _card(
      door: g2Door(remote: false, qrReader: true),
      status: g2Runtime(online: false),
    ),
  ),
  (
    name: 'uzaktan açma kapalı, karekod da yok (çevrimiçi)',
    build: () => _card(door: g2Door(remote: false)),
  ),
  (name: 'kapı açılıyor', build: () => _card(opening: true)),
  (name: 'durum kontrol ediliyor', build: () => _card(loadingStatus: true)),
  (name: 'kapı seçilmedi', build: () => _card(noDoor: true)),
  (name: 'cihaz atanmamış', build: () => _card(door: g2Door(uid: null))),
  (
    name: 'çok uzun site ve kapı adları + uzun IP',
    build: () => _card(
      door: g2Door(
        name: 'Çok Uzun İsimli Ana Giriş Kapısı ve Otopark Bariyeri',
        siteName: 'Güneş Sitesi Çok Uzun İsimli Konutları 2. Etap Yeşilvadi',
        qrReader: true,
      ),
      doors: [
        g2Door(
          name: 'Çok Uzun İsimli Ana Giriş Kapısı ve Otopark Bariyeri',
          siteName: 'Güneş Sitesi Çok Uzun İsimli Konutları 2. Etap Yeşilvadi',
          qrReader: true,
        ),
        g2Door(id: 8, name: 'B', qrReader: true),
      ],
      status: g2Runtime(
        localIp: '192.168.100.200',
        publicIp: '2001:0db8:85a3:0000:0000:8a2e:0370:7334',
      ),
    ),
  ),
];

DoorOpenButton _button(WidgetTester t) =>
    t.widget<DoorOpenButton>(find.byType(DoorOpenButton));

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  group('taşma matrisi (320x640 x2,0 ve 360x640 x1,5; açık + koyu)', () {
    for (final s in _scenarios) {
      testWidgets(s.name, (t) async {
        for (final cell in kG2Cells) {
          for (final dark in const <bool>[false, true]) {
            await pumpAt(
              t,
              s.build(),
              width: cell.width,
              height: 640,
              scale: cell.scale,
              dark: dark,
            );
          }
        }
      });
    }
  });

  group('düğme: durum -> etiket, ikon, ton, dokunma (e2e etiketleri korunur)', () {
    testWidgets('bulutta çevrimiçi: KAPIYI AÇ (primary) dokununca onOpenDoor', (
      t,
    ) async {
      var opened = 0;
      final haptics = recordHaptics(t);
      await pumpAt(
        t,
        _card(onOpenDoor: () => opened++),
        width: 360,
        scale: 1.0,
      );
      expect(find.text('KAPIYI AÇ'), findsOneWidget);
      expect(_button(t).state, DoorOpenState.ready);
      expect(_button(t).tone, AppTone.primary);
      expect(_button(t).variant, DoorOpenVariant.circle);
      expect(_button(t).icon, Icons.lock_open_rounded);
      await t.tap(find.text('KAPIYI AÇ'));
      await t.pump();
      expect(opened, 1);
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(
        find.text('🟢 Çevrimiçi - Kapıyı açmak için dokunun'),
        findsOneWidget,
      );
    });

    testWidgets(
      'yerel ağda: YEREL AĞDAN AÇ (warning); üst rozet "AHBU YEREL AĞ GEÇİŞ"',
      (t) async {
        var opened = 0;
        await pumpAt(
          t,
          _card(
            status: g2Runtime(online: false),
            local: true,
            onOpenDoor: () => opened++,
          ),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('YEREL AĞDAN AÇ'), findsOneWidget);
        expect(_button(t).tone, AppTone.warning);
        expect(_button(t).icon, Icons.wifi_rounded);
        expect(find.text('AHBU YEREL AĞ GEÇİŞ'), findsOneWidget);
        expect(find.text('AHBU AKILLI GEÇİŞ'), findsNothing);
        expect(
          find.text('🟡 Yerel Ağda Aktif - Kapıyı açmak için dokunun'),
          findsOneWidget,
        );
        await t.tap(find.text('YEREL AĞDAN AÇ'));
        expect(opened, 1);
      },
    );

    testWidgets('bulutta çevrimiçi: üst rozet "AHBU AKILLI GEÇİŞ" (primary)', (
      t,
    ) async {
      await pumpAt(t, _card(), width: 360, scale: 1.0);
      expect(find.text('AHBU AKILLI GEÇİŞ'), findsOneWidget);
      final chip = t.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'AHBU AKILLI GEÇİŞ'),
      );
      expect(chip.tone, AppTone.primary);
    });

    testWidgets(
      'çevrimdışı: ÇEVRİMDİŞI, dokununca "çevrimdışı" uyarısı (AppSnack hata); kapı açılmaz',
      (t) async {
        var opened = 0;
        final haptics = recordHaptics(t);
        await pumpAt(
          t,
          _card(status: g2Runtime(online: false), onOpenDoor: () => opened++),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('ÇEVRİMDİŞI'), findsOneWidget);
        expect(_button(t).state, DoorOpenState.offline);
        expect(find.text('🔴 Cihaz Çevrimdışı'), findsOneWidget);

        await t.tap(find.text('ÇEVRİMDİŞI'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(opened, 0);
        expect(
          find.text(
            'A Blok Ana Giriş Kapısı şu an çevrimdışı. Cihaz internete bağlı olmadığından işlem yapılamaz.',
          ),
          findsOneWidget,
        );
        expect(
          haptics,
          contains('HapticFeedbackType.selectionClick'),
          reason: 'çevrimdışı dokunuşta hafif haptik + titreme',
        );
      },
    );

    testWidgets(
      'uzaktan açma kapalı + çevrimiçi: UZAKTAN KAPALI, dokunma hiçbir şey yapmaz',
      (t) async {
        var opened = 0;
        await pumpAt(
          t,
          _card(door: g2Door(remote: false), onOpenDoor: () => opened++),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('UZAKTAN KAPALI'), findsOneWidget);
        expect(_button(t).state, DoorOpenState.disabled);
        expect(_button(t).icon, Icons.block_rounded);
        await t.tap(find.text('UZAKTAN KAPALI'));
        await t.pump();
        expect(opened, 0);
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.text('🚫 Bu kapıda uzaktan açma yetkisi kapalıdır.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('cihaz atanmamış: KAPALI; durum cümlesi birebir', (t) async {
      await pumpAt(t, _card(door: g2Door(uid: null)), width: 360, scale: 1.0);
      expect(find.text('KAPALI'), findsOneWidget);
      expect(find.text('Bu kapıya henüz cihaz atanmamış.'), findsOneWidget);
    });

    testWidgets(
      'yalnız karekod + çevrimiçi: QR KOD İLE AÇ (success) dokununca karekod penceresi',
      (t) async {
        await pumpAt(
          t,
          _card(door: g2Door(remote: false, qrReader: true)),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('QR KOD İLE AÇ'), findsOneWidget);
        expect(_button(t).tone, AppTone.success);
        expect(_button(t).icon, Icons.qr_code_2_rounded);
        expect(
          find.text('📷 Bu sitede yalnızca QR Kod ile giriş aktiftir.'),
          findsOneWidget,
        );

        await t.tap(find.text('QR KOD İLE AÇ'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(DynamicQrPassModal), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'yalnız karekod + çevrimdışı: ÇEVRİMDİŞI, dokununca uyarı (karekod penceresi açılmaz)',
      (t) async {
        await pumpAt(
          t,
          _card(
            door: g2Door(remote: false, qrReader: true),
            status: g2Runtime(online: false),
          ),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('ÇEVRİMDİŞI'), findsOneWidget);
        await t.tap(find.text('ÇEVRİMDİŞI'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(DynamicQrPassModal), findsNothing);
        expect(find.textContaining('şu an çevrimdışı'), findsOneWidget);
      },
    );

    testWidgets(
      'komut sürerken: AÇILIYOR + aynı CircularProgressIndicator; dokunma yok; cümle "Kapı tetikleniyor"',
      (t) async {
        var opened = 0;
        await pumpAt(
          t,
          _card(opening: true, onOpenDoor: () => opened++),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('AÇILIYOR'), findsOneWidget);
        expect(find.text('KAPIYI AÇ'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(DoorOpenButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Kapı tetikleniyor, lütfen bekleyin...'),
          findsOneWidget,
        );
        await t.tap(find.text('AÇILIYOR'));
        await t.pump();
        expect(opened, 0);
      },
    );

    testWidgets(
      'kapı yokken "Kapı Seçilmedi"; site adı kapı kaydından gelir (kapı adı iki kez yazılmaz)',
      (t) async {
        await pumpAt(t, _card(noDoor: true), width: 360, scale: 1.0);
        expect(find.text('Kapı Seçilmedi'), findsOneWidget);
        expect(find.text('Site Kapısı'), findsOneWidget);

        await pumpAt(t, _card(), width: 360, scale: 1.0);
        expect(find.text('Güneş Sitesi'), findsOneWidget);
        expect(find.text('A Blok Ana Giriş Kapısı'), findsNothing);
        expect(find.text('🚪 A Blok Ana Giriş Kapısı'), findsOneWidget);
      },
    );
  });

  group('successTick (başarı tiki; bağlama A3\'te)', () {
    testWidgets(
      'artınca GÖNDERİLDİ, 1,4 sn sonra KAPIYI AÇ; varsayılan 0 sinyal sayılmaz',
      (t) async {
        final tick = ValueNotifier<int>(0);
        addTearDown(tick.dispose);
        await pumpAt(
          t,
          ValueListenableBuilder<int>(
            valueListenable: tick,
            builder: (context, value, _) => _card(successTick: value),
          ),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        tick.value = 1;
        await t.pump();
        await t.pump(const Duration(milliseconds: 250));
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        expect(find.text('KAPIYI AÇ'), findsNothing);
        await t.pump(const Duration(milliseconds: 1500));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('successTick varsayılanı 0', (t) async {
      await pumpAt(t, _card(), width: 360, scale: 1.0);
      expect(
        t
            .widget<ResidentDoorRemoteCard>(find.byType(ResidentDoorRemoteCard))
            .successTick,
        0,
      );
    });
  });

  group('kapı çipleri: yatay kaydırma yok, hiçbir kapı gizli kalmaz', () {
    testWidgets(
      'tek kapıda çip yok; çok kapıda Wrap + ChoiceChip (e2e kapı adına dokunur)',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        expect(find.byType(ChoiceChip), findsNothing);

        final ids = <int>[];
        await pumpAt(
          t,
          _card(doors: _threeDoors(), onSelectDoor: ids.add),
          width: 360,
          scale: 1.0,
        );
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(
          find.byWidgetPredicate(
            (w) => w is Scrollable && w.axis == Axis.horizontal,
          ),
          findsNothing,
          reason: 'eski yatay kaydırma kalktı',
        );
        for (final name in const <String>[
          'A Blok Ana Giriş Kapısı',
          'Otopark Girişi',
          'Daire Sakinleri Kapısı ve Yaya Girişi',
        ]) {
          expect(find.text(name), findsOneWidget, reason: name);
        }

        await t.tap(find.text('Otopark Girişi'));
        await t.pump();
        expect(ids, [8]);
        await t.tap(find.text('A Blok Ana Giriş Kapısı'));
        await t.pump();
        expect(ids, [8], reason: 'seçili çipe dokunmak yeniden seçim yapmaz');
      },
    );

    testWidgets('320 px x 2,0 yazıda da tüm çipler görünür ve ekran içinde', (
      t,
    ) async {
      await pumpAt(t, _card(doors: _threeDoors()), width: 320, scale: 2.0);
      for (final name in const <String>[
        'A Blok Ana Giriş Kapısı',
        'Otopark Girişi',
        'Daire Sakinleri Kapısı ve Yaya Girişi',
      ]) {
        final rect = t.getRect(find.text(name));
        expect(rect.left, greaterThanOrEqualTo(0), reason: name);
        expect(rect.right, lessThanOrEqualTo(320), reason: name);
      }
    });

    testWidgets(
      'seçili çip: dolu mavi + beyaz onay işareti; seçili olmayan: soluk yüzey',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          await pumpAt(
            t,
            _card(doors: _threeDoors()),
            width: 360,
            scale: 1.0,
            dark: dark,
          );
          final chips = t
              .widgetList<ChoiceChip>(find.byType(ChoiceChip))
              .toList();
          final selected = chips.firstWhere((c) => c.selected);
          final other = chips.firstWhere((c) => !c.selected);
          expect(selected.selectedColor, AppTone.primary.a);
          expect(
            selected.checkmarkColor,
            Colors.white,
            reason: 'onay işareti koyu gri DEĞİL (W6)',
          );
          expect(selected.labelStyle!.color, Colors.white);
          expect(
            g2Contrast(Colors.white, AppTone.primary.a),
            greaterThanOrEqualTo(4.5),
          );
          expect(other.backgroundColor, p.surfaceMuted);
          expect(
            g2Contrast(other.labelStyle!.color!, p.surfaceMuted),
            greaterThanOrEqualTo(4.5),
            reason: 'dark=$dark',
          );
        }
      },
    );
  });

  group('eylem düğmeleri (tonal) ve rozetler', () {
    testWidgets(
      'üç tonal düğme: etiketler birebir, tam genişlik, dokunma hedefi >= 48; misafir geçişi çalışır',
      (t) async {
        var guest = 0;
        await pumpAt(
          t,
          _card(onCreateGuestPass: () => guest++),
          width: 360,
          scale: 1.0,
        );
        final labels = <String>[
          '📲 Kapıya QR Göster',
          '📷 Kapı Ekranından QR Oku',
          '📦 Kurye / Misafir Geçiş Linki Oluştur',
        ];
        final buttons = t
            .widgetList<PrimaryActionButton>(find.byType(PrimaryActionButton))
            .toList();
        expect(buttons.map((b) => b.label), labels);
        expect(
          buttons.every((b) => b.variant == AppButtonVariant.tonal),
          isTrue,
        );
        expect(buttons.map((b) => b.tone), [
          AppTone.success,
          AppTone.info,
          AppTone.primary,
        ]);
        final width = t.getSize(find.byType(AppCard).first).width;
        for (final b in find.byType(PrimaryActionButton).evaluate()) {
          expect(b.size!.width, closeTo(width, 0.5));
          expect(b.size!.height, greaterThanOrEqualTo(48));
        }
        await t.ensureVisible(find.text(labels.last));
        await t.tap(find.text(labels.last));
        expect(guest, 1);
      },
    );

    testWidgets(
      'çevrimdışı iken QR düğmeleri nötr tonda kalır ve dokununca uyarı verir',
      (t) async {
        await pumpAt(
          t,
          _card(status: g2Runtime(online: false)),
          width: 360,
          scale: 1.0,
        );
        final buttons = t
            .widgetList<PrimaryActionButton>(find.byType(PrimaryActionButton))
            .toList();
        expect(buttons[0].tone, AppTone.neutral);
        expect(buttons[1].tone, AppTone.neutral);
        expect(
          buttons[2].tone,
          AppTone.primary,
          reason: 'misafir geçişi bağlantıya bağlı değil',
        );
        await t.ensureVisible(find.text('📲 Kapıya QR Göster'));
        await t.tap(find.text('📲 Kapıya QR Göster'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('şu an çevrimdışı'), findsOneWidget);
      },
    );

    testWidgets('yetkiye göre görünürlük: karekod/ekran/misafir', (t) async {
      await pumpAt(
        t,
        _card(door: g2Door(qr: false, target: 'esp32-c3', guestPass: false)),
        width: 360,
        scale: 1.0,
      );
      expect(find.byType(PrimaryActionButton), findsNothing);

      await pumpAt(
        t,
        _card(door: g2Door(qrReader: true, guestPass: false)),
        width: 360,
        scale: 1.0,
      );
      expect(find.text('📲 Kapıya QR Göster'), findsOneWidget);
      expect(find.text('📷 Kapı Ekranından QR Oku'), findsOneWidget);
      expect(find.text('📦 Kurye / Misafir Geçiş Linki Oluştur'), findsNothing);
    });

    testWidgets(
      'IP rozetleri: nötr StatusChip (yerel/genel); IP yoksa hiç gösterilmez',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        final local = t.widget<StatusChip>(
          find.widgetWithText(StatusChip, 'Yerel IP: 192.168.100.200'),
        );
        final public = t.widget<StatusChip>(
          find.widgetWithText(StatusChip, 'Genel IP: 85.105.20.34'),
        );
        expect(local.tone, AppTone.neutral);
        expect(public.tone, AppTone.neutral);

        await pumpAt(
          t,
          _card(status: g2Runtime(localIp: null, publicIp: '')),
          width: 360,
          scale: 1.0,
        );
        expect(find.textContaining('IP:'), findsNothing);
      },
    );

    testWidgets(
      'sesli banner: yalnız servis varken, ortak VoiceLiveBanner; sakin kartı aday kapı vermez',
      (t) async {
        final voice = G2FakeVoice();
        await pumpAt(t, _card(voice: voice), width: 360, scale: 1.0);
        expect(find.byType(VoiceLiveBanner), findsOneWidget);
        await t.tap(
          find.descendant(
            of: find.byType(VoiceLiveBanner),
            matching: find.byType(IconButton),
          ),
        );
        await t.pump();
        expect(voice.startCalls, [null]);

        await pumpAt(t, _card(), width: 360, scale: 1.0);
        expect(find.byType(VoiceLiveBanner), findsNothing);
      },
    );
  });

  group(
    'durum cümlesi: Pop (yalnız yeni cümle belirir), eski cümle hemen kalkar',
    () {
      testWidgets(
        'çevrimiçi -> çevrimdışı geçişinde tek cümle kalır (find.text çift sonuç vermez)',
        (t) async {
          final online = ValueNotifier<bool>(true);
          addTearDown(online.dispose);
          await pumpAt(
            t,
            ValueListenableBuilder<bool>(
              valueListenable: online,
              builder: (context, value, _) =>
                  _card(status: g2Runtime(online: value)),
            ),
            width: 360,
            scale: 1.0,
          );
          expect(
            find.text('🟢 Çevrimiçi - Kapıyı açmak için dokunun'),
            findsOneWidget,
          );
          online.value = false;
          await t.pump();
          expect(
            find.text('🟢 Çevrimiçi - Kapıyı açmak için dokunun'),
            findsNothing,
          );
          expect(find.text('🔴 Cihaz Çevrimdışı'), findsOneWidget);
          await t.pump(const Duration(milliseconds: 300));
          expect(find.text('🔴 Cihaz Çevrimdışı'), findsOneWidget);
        },
      );

      testWidgets('durum cümlesinin rengi ton ink\'idir', (t) async {
        for (final dark in const <bool>[false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          for (final c in <({Widget card, String text, AppTone tone})>[
            (
              card: _card(),
              text: '🟢 Çevrimiçi - Kapıyı açmak için dokunun',
              tone: AppTone.success,
            ),
            (
              card: _card(status: g2Runtime(online: false), local: true),
              text: '🟡 Yerel Ağda Aktif - Kapıyı açmak için dokunun',
              tone: AppTone.warning,
            ),
            (
              card: _card(status: g2Runtime(online: false)),
              text: '🔴 Cihaz Çevrimdışı',
              tone: AppTone.danger,
            ),
            (
              card: _card(opening: true),
              text: 'Kapı tetikleniyor, lütfen bekleyin...',
              tone: AppTone.primary,
            ),
            (
              card: _card(loadingStatus: true),
              text: 'Cihaz durumu kontrol ediliyor...',
              tone: AppTone.neutral,
            ),
            (
              card: _card(door: g2Door(remote: false, qrReader: true)),
              text: '📷 Bu sitede yalnızca QR Kod ile giriş aktiftir.',
              tone: AppTone.success,
            ),
          ]) {
            await pumpAt(t, c.card, width: 360, scale: 1.0, dark: dark);
            final color = g2TextColor(t, find.text(c.text));
            expect(color, c.tone.ink(p), reason: '${c.text} dark=$dark');
            expect(
              g2Contrast(color, p.surfaceAt(2)),
              greaterThanOrEqualTo(4.5),
              reason: '${c.text} dark=$dark',
            );
          }
        }
      });
    },
  );

  group('erişilebilirlik ve belirteçler', () {
    testWidgets(
      'büyük düğme tek anlamsal düğüm: etiket = görünen metin, etkin; daire >= 132 dp',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        expect(find.bySemanticsLabel('KAPIYI AÇ'), findsOneWidget);
        final size = t.getSize(find.byType(DoorOpenButton));
        expect(
          size.width,
          inInclusiveRange(
            DoorOpenButton.minCircleDiameter,
            DoorOpenButton.maxCircleDiameter,
          ),
        );
        expect(size.width, closeTo(size.height, 0.5));
        handle.dispose();
      },
    );

    testWidgets(
      'kart yüzeyi AppCard(seviye 2); başlık/kapı satırı tipografi ölçeğinden',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        expect(t.widget<AppCard>(find.byType(AppCard).first).level, 2);
        final th = Theme.of(t.element(find.byType(ResidentDoorRemoteCard)));
        final title = t.widget<Text>(find.text('Güneş Sitesi'));
        expect(title.style, th.textTheme.headlineMedium);
      },
    );

    testWidgets(
      'hareket azaltma açıkken tek pump son durumu verir (nabız/morph yok)',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0, reduce: true);
        await t.pumpAndSettle();
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
      },
    );
  });

  group(
    'geniş ekranlar (412 / 820 / 1100 px) ve yatay telefon (640x360); yazı 1,0',
    () {
      for (final s in _scenarios) {
        testWidgets(s.name, (t) async {
          for (final size in const <({double w, double h})>[
            (w: 412, h: 640),
            (w: 820, h: 1180),
            (w: 1100, h: 800),
            (w: 640, h: 360),
          ]) {
            for (final dark in const <bool>[false, true]) {
              await pumpAt(
                t,
                s.build(),
                width: size.w,
                height: size.h,
                scale: 1.0,
                dark: dark,
              );
            }
          }
        });
      }

      testWidgets('geniş ekranda daire çapı en çok 184 dp; kart tam genişlik', (
        t,
      ) async {
        await pumpAt(t, _card(), width: 1100, height: 800, scale: 1.0);
        final size = t.getSize(find.byType(DoorOpenButton));
        expect(size.width, DoorOpenButton.maxCircleDiameter);
        expect(
          t.getSize(find.byType(AppCard).first).width,
          closeTo(1100 - 32, 0.5),
        );
      });
    },
  );
}
