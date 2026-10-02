// FAZ 5 / A2-G2: DashboardView (saat + kapı kartı) testleri.
//
// - Taşma matrisi: 320x640 x2,0 ve 360x640 x1,5; açık + koyu; yönetici ve sakin görünümü.
// - Rol eşlemesi: daire sakini -> ResidentDoorRemoteCard; diğer roller -> AdminDoorStatusCard.
// - successTick (varsayılan 0) kartlardaki "kapıyı aç" düğmesine iletilir (bağlama A3'te).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/admin_door_status_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/digital_clock_widget.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_remote_card.dart';

import '../design/harness.dart';
import 'g2_support.dart';

Widget _dashboard({
  UserRole role = UserRole.superUser,
  int successTick = 0,
  bool online = true,
  bool opening = false,
  VoidCallback? onOpenDoor,
  G2FakeVoice? voice,
}) {
  final door = g2Door(qrReader: true);
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: DashboardView(
        session: g2Session(role: role, fullName: 'Cenk Güde'),
        sites: [g2Site()],
        doors: [door],
        selectedSite: g2Site(),
        selectedDoor: door,
        runtimeStatus: g2Runtime(online: online),
        isLoadingSites: false,
        isLoadingStructure: false,
        isLoadingStatus: false,
        isOpeningDoor: opening,
        doorStatusError: null,
        canTryLocalDoorOpen: false,
        onSelectSite: (_) {},
        onSelectDoor: (_) {},
        onOpenDoor: onOpenDoor ?? () {},
        onCreateGuestPass: () {},
        voiceDoorService: voice,
        successTick: successTick,
      ),
    ),
  );
}

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
    for (final role in <UserRole>[
      UserRole.superUser,
      UserRole.siteManager,
      UserRole.apartmentOwner,
    ]) {
      testWidgets('rol: ${role.name}', (t) async {
        for (final cell in kG2Cells) {
          for (final dark in const <bool>[false, true]) {
            await pumpAt(
              t,
              _dashboard(role: role, voice: G2FakeVoice()),
              width: cell.width,
              height: 640,
              scale: cell.scale,
              dark: dark,
            );
          }
        }
      });
    }

    testWidgets('çevrimdışı ve komut sürerken', (t) async {
      for (final cell in kG2Cells) {
        for (final dark in const <bool>[false, true]) {
          await pumpAt(
            t,
            _dashboard(online: false),
            width: cell.width,
            height: 640,
            scale: cell.scale,
            dark: dark,
          );
          await pumpAt(
            t,
            _dashboard(role: UserRole.apartmentOwner, opening: true),
            width: cell.width,
            height: 640,
            scale: cell.scale,
            dark: dark,
          );
        }
      }
    });
  });

  group('rol eşlemesi ve düzen', () {
    testWidgets(
      'daire sakini: saat + sakin kumandası; yönetici/süper: saat + yönetim kartı',
      (t) async {
        await pumpAt(
          t,
          _dashboard(role: UserRole.apartmentOwner),
          width: 360,
          scale: 1.0,
        );
        expect(find.byType(DigitalClockWidget), findsOneWidget);
        expect(find.byType(ResidentDoorRemoteCard), findsOneWidget);
        expect(find.byType(AdminDoorStatusCard), findsNothing);

        for (final role in <UserRole>[
          UserRole.superUser,
          UserRole.siteManager,
        ]) {
          await pumpAt(t, _dashboard(role: role), width: 360, scale: 1.0);
          expect(find.byType(DigitalClockWidget), findsOneWidget);
          expect(
            find.byType(AdminDoorStatusCard),
            findsOneWidget,
            reason: role.name,
          );
          expect(find.byType(ResidentDoorRemoteCard), findsNothing);
        }
      },
    );

    testWidgets(
      'saat ile kapı kartı arası 16 dp (AppSpace.lg); ikisi de tam genişlik',
      (t) async {
        for (final role in <UserRole>[
          UserRole.apartmentOwner,
          UserRole.superUser,
        ]) {
          await pumpAt(t, _dashboard(role: role), width: 360, scale: 1.0);
          final clock = t.getRect(find.byType(DigitalClockWidget));
          final card = t.getRect(
            find.byType(
              role == UserRole.apartmentOwner
                  ? ResidentDoorRemoteCard
                  : AdminDoorStatusCard,
            ),
          );
          expect(card.top - clock.bottom, AppSpace.lg, reason: role.name);
          expect(clock.width, closeTo(360 - 32, 0.5));
          expect(card.width, closeTo(360 - 32, 0.5));
        }
      },
    );
  });

  group('successTick (kapı açma başarısı) kartlara iletilir; varsayılan 0', () {
    testWidgets('varsayılan 0: iki kartta da tik yok', (t) async {
      await pumpAt(
        t,
        _dashboard(role: UserRole.apartmentOwner),
        width: 360,
        scale: 1.0,
      );
      expect(
        t
            .widget<ResidentDoorRemoteCard>(find.byType(ResidentDoorRemoteCard))
            .successTick,
        0,
      );
      await pumpAt(t, _dashboard(), width: 360, scale: 1.0);
      expect(
        t
            .widget<AdminDoorStatusCard>(find.byType(AdminDoorStatusCard))
            .successTick,
        0,
      );
    });

    for (final c in <({UserRole role, String ready, String done})>[
      (role: UserRole.apartmentOwner, ready: 'KAPIYI AÇ', done: 'GÖNDERİLDİ'),
      (role: UserRole.superUser, ready: 'Kapı Aç', done: 'Gönderildi'),
      (role: UserRole.siteManager, ready: 'Kapı Aç', done: 'Gönderildi'),
    ]) {
      testWidgets(
        '${c.role.name}: sayaç artınca "${c.done}", 1,4 sn sonra "${c.ready}"',
        (t) async {
          final tick = ValueNotifier<int>(0);
          addTearDown(tick.dispose);
          await pumpAt(
            t,
            ValueListenableBuilder<int>(
              valueListenable: tick,
              builder: (context, value, _) =>
                  _dashboard(role: c.role, successTick: value),
            ),
            width: 360,
            scale: 1.0,
          );
          expect(find.text(c.ready), findsOneWidget);
          expect(
            t.widget<DoorOpenButton>(find.byType(DoorOpenButton)).successTick,
            0,
          );

          tick.value = 1;
          await t.pump();
          await t.pump(const Duration(milliseconds: 250));
          expect(
            t.widget<DoorOpenButton>(find.byType(DoorOpenButton)).successTick,
            1,
          );
          expect(find.text(c.done), findsOneWidget);

          await t.pump(const Duration(milliseconds: 1500));
          expect(find.text(c.ready), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  });

  group('tıklama davranışı değişmez', () {
    testWidgets(
      'sakin: büyük düğme onOpenDoor; yönetici: "Kapı Aç" onOpenDoor',
      (t) async {
        var opened = 0;
        await pumpAt(
          t,
          _dashboard(role: UserRole.apartmentOwner, onOpenDoor: () => opened++),
          width: 360,
          scale: 1.0,
        );
        await t.tap(find.text('KAPIYI AÇ'));
        expect(opened, 1);

        await pumpAt(
          t,
          _dashboard(onOpenDoor: () => opened++),
          width: 360,
          scale: 1.0,
        );
        await t.tap(find.text('Kapı Aç'));
        expect(opened, 2);
      },
    );
  });

  group(
    'geniş ekranlar (412 / 820 / 1100 px) ve yatay telefon (640x360); yazı 1,0',
    () {
      for (final role in <UserRole>[
        UserRole.superUser,
        UserRole.siteManager,
        UserRole.apartmentOwner,
      ]) {
        testWidgets('rol: ${role.name}', (t) async {
          for (final size in const <({double w, double h})>[
            (w: 412, h: 640),
            (w: 820, h: 1180),
            (w: 1100, h: 800),
            (w: 640, h: 360),
          ]) {
            for (final dark in const <bool>[false, true]) {
              await pumpAt(
                t,
                _dashboard(role: role, voice: G2FakeVoice()),
                width: size.w,
                height: size.h,
                scale: 1.0,
                dark: dark,
              );
            }
          }
        });
      }
    },
  );
}
