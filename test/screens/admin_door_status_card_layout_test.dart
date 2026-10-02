// FAZ 5 / A2-G2: AdminDoorStatusCard (yönetici kapı kontrol kartı) tasarım yenileme testleri.
//
// - Taşma matrisi: 320x640 x2,0 ve 360x640 x1,5; açık + koyu; tüm durumlar (pumpAt).
// - Davranış korunur: kapı aç/komut sürerken/çevrimdışı, Detaylar aç-kapa, misafir geçişi, karekod,
//   sesli banner, e2e'nin bağlı olduğu metinler/etiketler.
// - Tasarım sözleşmesi: tek DoorOpenButton(bar), StatusChip(pulse), AppCard(tone), EmptyState,
//   InlineNotice, SkeletonBox; AnimatedCrossFade KORUNUR; kontrast >= 4,5:1; successTick.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/admin_door_status_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_logs_accordion.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_live_banner.dart';

import '../design/harness.dart';
import 'g2_support.dart';

/// Sınanan kartı kurar. Varsayılan: bulutta çevrimiçi, kapı seçili, her şey yüklü.
Widget _card({
  UserRole role = UserRole.superUser,
  DoorRecord? door,
  bool noDoor = false,
  DoorRuntimeStatus? status,
  bool noStatus = false,
  bool local = false,
  bool opening = false,
  bool loadingStatus = false,
  bool loadingSites = false,
  bool loadingStructure = false,
  String? error,
  G2FakeVoice? voice,
  G2LogsAuth? auth,
  VoidCallback? onOpenDoor,
  VoidCallback? onCreateGuestPass,
  int successTick = 0,
  List<DoorRecord>? doors,
}) {
  final selected = noDoor ? null : (door ?? g2Door(qrReader: true));
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: AdminDoorStatusCard(
        session: g2Session(role: role),
        sites: [g2Site()],
        doors: doors ?? (selected == null ? <DoorRecord>[] : [selected]),
        selectedSite: g2Site(),
        selectedDoor: selected,
        runtimeStatus: noDoor || noStatus ? null : (status ?? g2Runtime()),
        isLoadingSites: loadingSites,
        isLoadingStructure: loadingStructure,
        isLoadingStatus: loadingStatus,
        isOpeningDoor: opening,
        doorStatusError: error,
        canTryLocalDoorOpen: local,
        onSelectSite: (_) {},
        onSelectDoor: (_) {},
        onOpenDoor: onOpenDoor ?? () {},
        onCreateGuestPass: onCreateGuestPass ?? () {},
        voiceDoorService: voice,
        authService: auth,
        successTick: successTick,
      ),
    ),
  );
}

typedef _Scenario = ({
  String name,
  Widget Function() build,
  Future<void> Function(WidgetTester t)? after,
});

final List<_Scenario> _scenarios = <_Scenario>[
  (name: 'bulutta çevrimiçi', build: () => _card(), after: null),
  (
    name: 'bulutta çevrimiçi + sesli banner + durum hatası + yükleniyor çubuğu',
    build: () => _card(
      voice: G2FakeVoice(),
      error: 'Cihaz durumu alınamadı. Lütfen tekrar deneyin.',
      loadingStatus: true,
    ),
    after: null,
  ),
  (
    name: 'yerel ağda aktif',
    build: () => _card(status: g2Runtime(online: false), local: true),
    after: null,
  ),
  (
    name: 'çevrimdışı',
    build: () => _card(status: g2Runtime(online: false)),
    after: null,
  ),
  (
    name: 'durum bilgisi yok (çevrimdışı)',
    build: () => _card(noStatus: true),
    after: null,
  ),
  (name: 'kapı açılıyor', build: () => _card(opening: true), after: null),
  (
    name: 'kapı seçilmedi (ipucu)',
    build: () => _card(noDoor: true),
    after: null,
  ),
  (
    name: 'ilk yükleme (iskelet)',
    build: () => _card(noDoor: true, loadingSites: true),
    after: null,
  ),
  (
    name: 'cihaz atanmamış',
    build: () => _card(door: g2Door(uid: null)),
    after: null,
  ),
  (
    name: 'misafir geçişi kapalı, karekod yok',
    build: () => _card(door: g2Door(guestPass: false)),
    after: null,
  ),
  (
    name: 'Detaylar açık (süper kullanıcı: OTA satırı)',
    build: () => _card(),
    after: (t) async {
      await t.tap(find.text('Detaylar'));
      await t.pump(const Duration(milliseconds: 450));
    },
  ),
  (
    name: 'Detaylar açık + günlükler açık (uzun adlar)',
    build: () => _card(
      role: UserRole.siteManager,
      auth: G2LogsAuth(pages: [g2LogPage(count: 4)]),
      door: g2Door(
        qrReader: true,
        name: 'Çok Uzun İsimli Ana Giriş Kapısı ve Otopark Bariyeri',
      ),
    ),
    after: (t) async {
      await t.tap(find.text('Detaylar'));
      await t.pump(const Duration(milliseconds: 450));
      await t.ensureVisible(find.textContaining('Geçiş Logları'));
      await t.tap(find.textContaining('Geçiş Logları'));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 700));
    },
  ),
];

void main() {
  setUp(() {
    // Karekod modalı (flutter_tts) bazı testlerde açılır: kanal çağrılarını sessizce yanıtla.
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
            final after = s.after;
            if (after != null) {
              await after(t);
              expect(
                t.takeException(),
                isNull,
                reason:
                    '${s.name}: ${g2CellLabel(cell.width, cell.scale, dark)}',
              );
            }
          }
        }
      });
    }
  });

  group('e2e ve mevcut testlerin bağlı olduğu metinler/etiketler korunur', () {
    testWidgets('açılır liste etiketleri, durum metinleri, düğme etiketleri', (
      t,
    ) async {
      await pumpAt(t, _card(), width: 360, scale: 1.0);
      expect(find.text('Site Seçin'), findsOneWidget);
      expect(find.text('Kapı Seçin'), findsOneWidget);
      expect(
        find.text('🟢 Çevrimiçi (Bulut)'),
        findsOneWidget,
        reason: 'home_polling_test: tek Text',
      );
      expect(find.text('Detaylar'), findsOneWidget);
      expect(find.text('Kapı Aç'), findsOneWidget);
      expect(find.text('Kurye / Misafir Geçişi Oluştur'), findsOneWidget);
      expect(find.text('📲 Giriş QR Kodu Göster'), findsOneWidget);
      expect(find.textContaining('Geçiş Logları'), findsOneWidget);

      await pumpAt(
        t,
        _card(status: g2Runtime(online: false), local: true),
        width: 360,
        scale: 1.0,
      );
      expect(find.text('🟡 Yerel Ağda Aktif'), findsOneWidget);
      expect(find.text('Kapı Aç (Yerel Wi-Fi)'), findsOneWidget);

      await pumpAt(
        t,
        _card(status: g2Runtime(online: false)),
        width: 360,
        scale: 1.0,
      );
      expect(find.text('🔴 Çevrimdışı'), findsOneWidget);
      expect(find.text('Cihaz Çevrimdışı'), findsOneWidget);
    });

    testWidgets(
      'kapı yokken ipucu cümlesi; cihaz yokken uyarı cümlesi (birebir)',
      (t) async {
        await pumpAt(t, _card(noDoor: true), width: 360, scale: 1.0);
        expect(
          find.text(
            'Kontrol etmek için önce siteyi, sonra o siteye ait kapıyı seçin.',
          ),
          findsOneWidget,
        );
        expect(find.byType(EmptyState), findsOneWidget);
        expect(find.byType(DoorOpenButton), findsNothing);

        await pumpAt(t, _card(door: g2Door(uid: null)), width: 360, scale: 1.0);
        expect(
          find.text(
            'Bu kapıya henüz cihaz atanmamış. Kapı açma komutu aktif olmaz.',
          ),
          findsOneWidget,
        );
        expect(find.byType(InlineNotice), findsOneWidget);
        // Eski davranış: cihaz yoksa kapı aç / misafir / günlük bölümü hiç gösterilmez.
        expect(find.byType(DoorOpenButton), findsNothing);
        expect(find.byType(DoorLogsAccordion), findsNothing);
      },
    );
  });

  group('kapı aç (tek DoorOpenButton, bar)', () {
    testWidgets('hazır: dokununca onOpenDoor çağrılır; orta şiddette haptik', (
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
      final button = t.widget<DoorOpenButton>(find.byType(DoorOpenButton));
      expect(button.variant, DoorOpenVariant.bar);
      expect(button.state, DoorOpenState.ready);
      expect(button.tone, AppTone.primary);
      expect(button.label, 'Kapı Aç');

      await t.tap(find.text('Kapı Aç'));
      await t.pump();
      expect(opened, 1);
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
    });

    testWidgets(
      'yerel ağda: warning tonu, Wi-Fi simgesi, etiket "Kapı Aç (Yerel Wi-Fi)"',
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
        final button = t.widget<DoorOpenButton>(find.byType(DoorOpenButton));
        expect(button.tone, AppTone.warning);
        expect(button.icon, Icons.wifi);
        expect(button.state, DoorOpenState.ready);
        await t.tap(find.text('Kapı Aç (Yerel Wi-Fi)'));
        expect(opened, 1);
      },
    );

    testWidgets('çevrimdışı: devre dışı (dokunma yok, titreme/uyarı yok)', (
      t,
    ) async {
      var opened = 0;
      await pumpAt(
        t,
        _card(status: g2Runtime(online: false), onOpenDoor: () => opened++),
        width: 360,
        scale: 1.0,
      );
      final button = t.widget<DoorOpenButton>(find.byType(DoorOpenButton));
      expect(
        button.state,
        DoorOpenState.disabled,
        reason: 'yönetici kartında çevrimdışı dokunuşta iş yapılmaz',
      );
      await t.tap(find.text('Cihaz Çevrimdışı'));
      await t.pump();
      expect(opened, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
      'komut sürerken: opening, "Gönderiliyor..." + aynı CircularProgressIndicator, dokunma yok',
      (t) async {
        var opened = 0;
        await pumpAt(
          t,
          _card(opening: true, onOpenDoor: () => opened++),
          width: 360,
          scale: 1.0,
        );
        final button = t.widget<DoorOpenButton>(find.byType(DoorOpenButton));
        expect(button.state, DoorOpenState.opening);
        expect(find.text('Gönderiliyor...'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DoorOpenButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        await t.tap(find.text('Gönderiliyor...'));
        await t.pump();
        expect(opened, 0);
      },
    );

    testWidgets(
      'durum yüklenirken devre dışı + ince ilerleme çubuğu (yenilemede kart kalır)',
      (t) async {
        await pumpAt(t, _card(loadingStatus: true), width: 360, scale: 1.0);
        expect(
          t.widget<DoorOpenButton>(find.byType(DoorOpenButton)).state,
          DoorOpenState.disabled,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          find.text('🟢 Çevrimiçi (Bulut)'),
          findsOneWidget,
          reason: 'mevcut durum yenileme sırasında kalır',
        );
      },
    );

    testWidgets(
      'successTick artınca "Gönderildi" tiki gösterilir, 1,4 sn sonra "Kapı Aç"a döner',
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
        expect(find.text('Kapı Aç'), findsOneWidget);
        expect(
          find.text('Gönderildi'),
          findsNothing,
          reason: 'ilk kurulumdaki değer sinyal sayılmaz',
        );

        tick.value = 1;
        await t.pump();
        await t.pump(const Duration(milliseconds: 250));
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(find.text('Kapı Aç'), findsNothing);

        await t.pump(const Duration(milliseconds: 1500));
        expect(find.text('Gönderildi'), findsNothing);
        expect(find.text('Kapı Aç'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('successTick varsayılanı 0: hiç tik gösterilmez', (t) async {
      await pumpAt(t, _card(), width: 360, scale: 1.0);
      expect(
        t
            .widget<AdminDoorStatusCard>(find.byType(AdminDoorStatusCard))
            .successTick,
        0,
      );
      await t.pump(const Duration(seconds: 3));
      expect(find.text('Gönderildi'), findsNothing);
    });
  });

  group('Detaylar (AnimatedCrossFade KORUNUR)', () {
    testWidgets(
      'dokununca açılır/kapanır; metin Detaylar <-> Gizle; satırlar eksiksiz',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        AnimatedCrossFade fade() =>
            t.widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade).first);
        expect(fade().crossFadeState, CrossFadeState.showFirst);
        expect(fade().duration, AppMotion.base, reason: '200 ms');
        expect(fade().sizeCurve, AppMotion.standard);

        await t.tap(find.text('Detaylar'));
        await t.pump(const Duration(milliseconds: 300));
        expect(fade().crossFadeState, CrossFadeState.showSecond);
        expect(find.text('Gizle'), findsOneWidget);
        expect(find.text('Detaylar'), findsNothing);
        for (final label in const <String>[
          'Cihaz UID',
          'Donanım Modeli',
          'Donanım Hedefi',
          'Sunucu MQTT',
          'Kapı Durumu',
          'Yerel Ağ',
          'Yerel IP (LAN)',
          'Genel IP (WAN)',
          'Firmware',
          'OTA Durumu',
          'Wi-Fi Gücü',
          'Son Güncelleme',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('Hazır (Bulut)'), findsOneWidget);
        expect(find.text('Kapalı/Kilitli'), findsOneWidget);
        expect(find.text('%78 (-52 dBm)'), findsOneWidget);
        expect(find.text('192.168.100.200'), findsOneWidget);

        await t.tap(find.text('Gizle'));
        await t.pump(const Duration(milliseconds: 300));
        expect(fade().crossFadeState, CrossFadeState.showFirst);
        expect(find.text('Detaylar'), findsOneWidget);
      },
    );

    testWidgets(
      'hareket azaltmada Detaylar aç/kapa tek pump ile (AnimatedSize sıfır süre hatası yok)',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0, reduce: true);
        await t.tap(find.text('Detaylar'));
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
        expect(
          t
              .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade).first)
              .crossFadeState,
          CrossFadeState.showSecond,
        );
        await t.tap(find.text('Gizle'));
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
        expect(
          t
              .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade).first)
              .crossFadeState,
          CrossFadeState.showFirst,
        );
        await t.pumpAndSettle();
      },
    );

    testWidgets('OTA satırı yalnız süper kullanıcıda', (t) async {
      await pumpAt(
        t,
        _card(role: UserRole.siteManager),
        width: 360,
        scale: 1.0,
      );
      expect(find.text('OTA Durumu'), findsNothing);
    });

    testWidgets('durum çubuğu tam genişlik, tonlu AppCard ve tek StatusChip', (
      t,
    ) async {
      for (final c in <({String name, Widget card, AppTone tone, bool pulse})>[
        (name: 'bulut', card: _card(), tone: AppTone.success, pulse: true),
        (
          name: 'yerel',
          card: _card(status: g2Runtime(online: false), local: true),
          tone: AppTone.warning,
          pulse: false,
        ),
        (
          name: 'çevrimdışı',
          card: _card(status: g2Runtime(online: false)),
          tone: AppTone.danger,
          pulse: false,
        ),
      ]) {
        await pumpAt(t, c.card, width: 360, scale: 1.0);
        // find.ancestor en yakın atadan başlar: ilk AppCard = durum çubuğu (dıştaki ana karttır).
        final bar = find
            .ancestor(of: find.text('Detaylar'), matching: find.byType(AppCard))
            .first;
        expect(t.widget<AppCard>(bar).tone, c.tone, reason: c.name);
        expect(t.widget<AppCard>(bar).onTap, isNotNull);
        final chip = t.widget<StatusChip>(
          find.descendant(of: bar, matching: find.byType(StatusChip)),
        );
        expect(chip.tone, c.tone, reason: c.name);
        expect(
          chip.pulse,
          c.pulse,
          reason: '${c.name}: nabız yalnız bulutta çevrimiçi',
        );
        // Tam genişlik: durum çubuğu ana kartın iç genişliğine eşit (açılır listelerle aynı hizada).
        final dropdown = find.byType(DropdownButtonFormField<int>).first;
        expect(
          t.getSize(bar).width,
          closeTo(t.getSize(dropdown).width, 0.5),
          reason: c.name,
        );
      }
    });

    testWidgets(
      'nabız 3 turdan sonra durur: pumpAndSettle biter (kararlı durumda ticker yok)',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        await t.pumpAndSettle();
      },
    );
  });

  group('eylemler', () {
    testWidgets(
      'misafir geçişi: görünür, dokununca onCreateGuestPass; site kapatırsa gizli',
      (t) async {
        var guest = 0;
        await pumpAt(
          t,
          _card(onCreateGuestPass: () => guest++),
          width: 360,
          scale: 1.0,
        );
        await t.ensureVisible(find.text('Kurye / Misafir Geçişi Oluştur'));
        await t.tap(find.text('Kurye / Misafir Geçişi Oluştur'));
        expect(guest, 1);

        await pumpAt(
          t,
          _card(door: g2Door(guestPass: false)),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('Kurye / Misafir Geçişi Oluştur'), findsNothing);
      },
    );

    testWidgets(
      'karekod: yalnız karekod okuyuculu kapıda; dokununca modal açılır',
      (t) async {
        await pumpAt(
          t,
          _card(door: g2Door(qrReader: false)),
          width: 360,
          scale: 1.0,
        );
        expect(find.text('📲 Giriş QR Kodu Göster'), findsNothing);

        await pumpAt(t, _card(), width: 360, scale: 1.0);
        await t.ensureVisible(find.text('📲 Giriş QR Kodu Göster'));
        await t.tap(find.text('📲 Giriş QR Kodu Göster'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(DynamicQrPassModal), findsOneWidget);
        expect(find.text('Yetkilendirme servisi bulunamadı.'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'düğmeler ikincil (tonal) ve tam genişlik; kapı aç tek dolu (gradyan) düğme',
      (t) async {
        await pumpAt(t, _card(), width: 360, scale: 1.0);
        final cardWidth = t.getSize(find.byType(DoorOpenButton)).width;
        expect(cardWidth, greaterThan(250));
        for (final label in const <String>[
          'Kurye / Misafir Geçişi Oluştur',
          '📲 Giriş QR Kodu Göster',
        ]) {
          final box = find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first;
          expect(t.getSize(box).width, closeTo(cardWidth, 0.5), reason: label);
          expect(
            t.getSize(box).height,
            greaterThanOrEqualTo(48),
            reason: '$label: dokunma hedefi',
          );
        }
        expect(
          t.getSize(find.byType(DoorOpenButton)).height,
          greaterThanOrEqualTo(52),
        );
      },
    );

    testWidgets(
      'sesli banner: tek ortak VoiceLiveBanner; başlatırken bu kartın kapıları aday olur',
      (t) async {
        final voice = G2FakeVoice();
        final door = g2Door(qrReader: true);
        await pumpAt(
          t,
          _card(
            voice: voice,
            doors: [
              door,
              g2Door(id: 8, name: 'Otopark'),
            ],
          ),
          width: 360,
          scale: 1.0,
        );
        expect(find.byType(VoiceLiveBanner), findsOneWidget);
        expect(find.text('🎙️ Sesli Kapı Açma'), findsOneWidget);

        await t.tap(
          find.descendant(
            of: find.byType(VoiceLiveBanner),
            matching: find.byType(IconButton),
          ),
        );
        await t.pump();
        expect(voice.startCalls, hasLength(1));
        expect(voice.startCalls.single!.map((d) => d.doorName), [
          'A Blok Ana Giriş Kapısı',
          'Otopark',
        ]);
      },
    );

    testWidgets('sesli servis yoksa banner yok', (t) async {
      await pumpAt(t, _card(), width: 360, scale: 1.0);
      expect(find.byType(VoiceLiveBanner), findsNothing);
    });
  });

  group('durumlar: iskelet, boş durum, uyarı', () {
    testWidgets('ilk yüklemede iskelet ("Yükleniyor"), yükleme bitince ipucu', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpAt(
        t,
        _card(noDoor: true, loadingSites: true),
        width: 360,
        scale: 1.0,
      );
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNWidgets(3));
      expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      // Parıltı kapalı (durağan iskelet): site/kapı değişirken yükleme uzasa da pumpAndSettle biter
      // (home_page_state_test'in tuttuğu yükleme senaryosu).
      await t.pumpAndSettle();

      await pumpAt(t, _card(noDoor: true), width: 360, scale: 1.0);
      expect(find.byType(ShimmerScope), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'iskelet yalnız kapı yokken: kapı seçiliyken yükleme bayrakları iskelet çıkarmaz',
      (t) async {
        await pumpAt(
          t,
          _card(loadingSites: true, loadingStructure: true),
          width: 360,
          scale: 1.0,
        );
        expect(find.byType(ShimmerScope), findsNothing);
      },
    );

    testWidgets(
      'durum hatası InlineNotice (tehlike tonu) olarak ve cümle birebir görünür',
      (t) async {
        await pumpAt(
          t,
          _card(error: 'Sunucu yanıt vermedi, tekrar deneyin.'),
          width: 360,
          scale: 1.0,
        );
        expect(
          find.text('Sunucu yanıt vermedi, tekrar deneyin.'),
          findsOneWidget,
        );
        expect(
          t.widget<InlineNotice>(find.byType(InlineNotice)).tone,
          AppTone.danger,
        );
      },
    );
  });

  group('kontrast >= 4,5:1 (açık ve koyu tema)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'durum çubuğu, "Detaylar", ipucu ve hata metinleri ${dark ? 'koyu' : 'açık'} temada',
        (t) async {
          final p = dark ? AppPalette.dark : AppPalette.light;
          for (final c
              in <({String name, Widget card, AppTone tone, String label})>[
                (
                  name: 'bulut',
                  card: _card(),
                  tone: AppTone.success,
                  label: '🟢 Çevrimiçi (Bulut)',
                ),
                (
                  name: 'yerel',
                  card: _card(status: g2Runtime(online: false), local: true),
                  tone: AppTone.warning,
                  label: '🟡 Yerel Ağda Aktif',
                ),
                (
                  name: 'çevrimdışı',
                  card: _card(status: g2Runtime(online: false)),
                  tone: AppTone.danger,
                  label: '🔴 Çevrimdışı',
                ),
              ]) {
            await pumpAt(t, c.card, width: 360, scale: 1.0, dark: dark);
            // Çubuk zemini (AppCard tonlu): yüzey + ton tint'i; rozet zemini bunun üstüne bir tint daha.
            final bg = g2Over(c.tone.tint(p), p.surface);
            expect(
              g2TextColor(t, find.text('Detaylar')),
              p.textSecondary,
              reason: c.name,
            );
            expect(
              g2Contrast(p.textSecondary, bg),
              greaterThanOrEqualTo(4.5),
              reason: '${c.name} Detaylar',
            );
            final chipInk = g2TextColor(t, find.text(c.label));
            expect(chipInk, c.tone.ink(p), reason: c.name);
            expect(
              g2Contrast(chipInk, g2Over(c.tone.tint(p), bg)),
              greaterThanOrEqualTo(4.5),
              reason: '${c.name} rozet',
            );
          }

          await pumpAt(
            t,
            _card(noDoor: true),
            width: 360,
            scale: 1.0,
            dark: dark,
          );
          final hint = find.text(
            'Kontrol etmek için önce siteyi, sonra o siteye ait kapıyı seçin.',
          );
          expect(
            g2Contrast(g2TextColor(t, hint), p.surfaceAt(2)),
            greaterThanOrEqualTo(4.5),
            reason: 'ipucu',
          );

          await pumpAt(
            t,
            _card(error: 'Cihaz durumu alınamadı.'),
            width: 360,
            scale: 1.0,
            dark: dark,
          );
          final err = find.text('Cihaz durumu alınamadı.');
          final errBg = g2Over(AppTone.danger.tint(p), p.surface);
          expect(
            g2Contrast(g2TextColor(t, err), errBg),
            greaterThanOrEqualTo(4.5),
            reason: 'hata metni',
          );
        },
      );
    }
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
              final after = s.after;
              if (after != null) {
                await after(t);
                expect(
                  t.takeException(),
                  isNull,
                  reason: '${s.name}: ${size.w}x${size.h} koyu=$dark',
                );
              }
            }
          }
        });
      }
    },
  );
}
