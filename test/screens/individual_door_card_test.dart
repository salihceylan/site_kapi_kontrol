// FAZ 5 / A2-G4: IndividualDoorCard (bireysel kapı kartı) widget testleri.
//
// Eylem/rozet görünürlüğü (eski `_buildDoorCard` ile aynı metinler), dokunuşların doğru geri çağrıyı
// tetiklemesi (çevrimdışıyken de), kapı açma akışı (açılıyor -> başarı tiki -> geri), dokunma hedefi
// boyutları, kararlı durumda animasyon kalmaması ve AGENTS.md kural 6 taşma matrisi
// (320x640 x2,0 ve 360x640 x1,5; açık+koyu).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/widgets/individual_door_card.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

class _Calls {
  int open = 0;
  int scan = 0;
  int showQr = 0;
  int guest = 0;
}

Widget _card(
  DoorRecord door,
  _Calls calls, {
  bool isOpening = false,
  int successTick = 0,
}) {
  return IndividualDoorCard(
    door: door,
    isOpening: isOpening,
    successTick: successTick,
    onOpenDoor: () => calls.open++,
    onScanScreenQr: () => calls.scan++,
    onShowQr: () => calls.showQr++,
    onGuestPass: () => calls.guest++,
  );
}

/// Kartı sınırlı genişlikli (stretch) bir sütunda kurar.
Widget _app(
  Widget card, {
  bool dark = false,
  bool reduce = false,
  double scale = 1.0,
}) {
  return harnessApp(
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [card],
      ),
    ),
    dark: dark,
    reduce: reduce,
    scale: scale,
  );
}

Future<void> _setSize(
  WidgetTester t, {
  double width = 400,
  double height = 1200,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  group('görünürlük (eski kart ile aynı metinler)', () {
    testWidgets(
      'WROOM + QR okuyucu: QR eylemleri, misafir kodu ve "Uzaktan Aç"; "Kapıyı Aç" yok',
      (t) async {
        await _setSize(t);
        final calls = _Calls();
        await t.pumpWidget(_app(_card(g4Door(geofence: true), calls)));
        await t.pump(const Duration(milliseconds: 100));

        expect(find.text('Ana Giriş Kapısı'), findsOneWidget);
        expect(find.text('Güneş Sitesi'), findsOneWidget);
        expect(find.text('Çevrimiçi'), findsOneWidget);
        expect(find.text('Site Ortak Kapısı'), findsOneWidget);
        expect(find.text('Konum (50m)'), findsOneWidget);
        expect(find.text('Optik QR'), findsOneWidget);
        expect(find.text('%88'), findsOneWidget);
        expect(find.text('Kapı Ekranından QR Oku'), findsOneWidget);
        expect(find.text('Kapıya QR Göster'), findsOneWidget);
        expect(find.text('Misafir Kodu'), findsOneWidget);
        expect(find.text('Uzaktan Aç'), findsOneWidget);
        expect(find.text('Kapıyı Aç'), findsNothing);
      },
    );

    testWidgets(
      'C3 çevrimdışı: "Kapıyı Aç" + "Misafir Kodu"; QR eylemleri, Wi-Fi ve optik QR rozeti yok',
      (t) async {
        await _setSize(t);
        final door = g4Door(
          name: 'B Blok Giriş',
          scope: 'BLOCK',
          block: 'B Blok',
          hardware: 'esp32_c3',
          qrReader: false,
          online: false,
        );
        await t.pumpWidget(_app(_card(door, _Calls())));
        await t.pump(const Duration(milliseconds: 100));

        expect(find.text('B Blok Giriş'), findsOneWidget);
        expect(find.text('Güneş Sitesi • B Blok'), findsOneWidget);
        expect(find.text('B Blok Kapısı'), findsOneWidget);
        expect(find.text('Çevrimdışı'), findsOneWidget);
        expect(find.text('Kapıyı Aç'), findsOneWidget);
        expect(find.text('Misafir Kodu'), findsOneWidget);
        expect(find.text('Uzaktan Aç'), findsNothing);
        expect(find.text('Kapı Ekranından QR Oku'), findsNothing);
        expect(find.text('Kapıya QR Göster'), findsNothing);
        expect(find.text('Optik QR'), findsNothing);
        expect(
          find.text('%88'),
          findsNothing,
          reason: 'Wi-Fi rozeti yalnız çevrimiçi cihazda',
        );
      },
    );

    testWidgets('cihazsız kapı: "Cihaz Yok" rozeti', (t) async {
      await _setSize(t);
      final door = g4Door(
        deviceUid: null,
        hardware: null,
        qrReader: false,
        online: null,
      );
      await t.pumpWidget(_app(_card(door, _Calls())));
      await t.pump(const Duration(milliseconds: 100));

      expect(find.text('Cihaz Yok'), findsOneWidget);
      expect(find.text('Çevrimiçi'), findsNothing);
      expect(find.text('Çevrimdışı'), findsNothing);
    });

    testWidgets(
      'hiçbir yetkisi olmayan kapıda eylem alanı (düğme/ayırıcı) çizilmez',
      (t) async {
        await _setSize(t);
        final door = g4Door(
          hardware: 'esp32_c3',
          qrReader: false,
          remote: false,
          guest: false,
        );
        await t.pumpWidget(_app(_card(door, _Calls())));
        await t.pump(const Duration(milliseconds: 100));

        expect(find.byType(DoorOpenButton), findsNothing);
        expect(find.byType(PrimaryActionButton), findsNothing);
        expect(find.byType(Divider), findsNothing);
      },
    );
  });

  group('dokunuşlar', () {
    testWidgets('her eylem kendi geri çağrısını tetikler (çevrimiçi)', (
      t,
    ) async {
      await _setSize(t);
      final calls = _Calls();
      await t.pumpWidget(_app(_card(g4Door(), calls)));
      await t.pump(const Duration(milliseconds: 500));

      await t.tap(find.text('Uzaktan Aç'));
      await t.pump();
      await t.tap(find.text('Kapı Ekranından QR Oku'));
      await t.pump();
      await t.tap(find.text('Kapıya QR Göster'));
      await t.pump();
      await t.tap(find.text('Misafir Kodu'));
      await t.pump();

      expect((calls.open, calls.scan, calls.showQr, calls.guest), (1, 1, 1, 1));
    });

    testWidgets(
      'çevrimdışıyken de dokunuş geri çağrıyı çağırır (üst görünüm çevrimiçi bilgisini yeniden kontrol eder)',
      (t) async {
        await _setSize(t);
        final calls = _Calls();
        final door = g4Door(online: false);
        await t.pumpWidget(_app(_card(door, calls)));
        await t.pump(const Duration(milliseconds: 500));

        await t.tap(find.text('Uzaktan Aç'));
        await t.pump();
        await t.tap(find.text('Kapı Ekranından QR Oku'));
        await t.pump();
        await t.tap(find.text('Kapıya QR Göster'));
        await t.pump();

        expect((calls.open, calls.scan, calls.showQr), (1, 1, 1));
        // Çevrimdışı titremesi biter; ekran yerleşir.
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'komut sürerken "Kapı Açılıyor..." gösterilir ve ikinci dokunuş yok sayılır',
      (t) async {
        await _setSize(t);
        final calls = _Calls();
        final door = g4Door(hardware: 'esp32_c3', qrReader: false);
        await t.pumpWidget(_app(_card(door, calls, isOpening: true)));
        await t.pump(const Duration(milliseconds: 500));

        expect(find.text('Kapı Açılıyor...'), findsOneWidget);
        expect(find.text('Kapıyı Aç'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await t.tap(find.text('Kapı Açılıyor...'), warnIfMissed: false);
        await t.pump();
        expect(calls.open, 0);
      },
    );

    testWidgets('"Uzaktan Aç" komutu sürerken kısa etiket "Açılıyor..." olur', (
      t,
    ) async {
      await _setSize(t);
      await t.pumpWidget(_app(_card(g4Door(), _Calls(), isOpening: true)));
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('Açılıyor...'), findsOneWidget);
      expect(find.text('Uzaktan Aç'), findsNothing);
    });
  });

  group('başarı tiki (successTick)', () {
    testWidgets(
      'açılıyor -> başarı: "Gönderildi" + onay işareti, 1,4 sn sonra eski etiket',
      (t) async {
        await _setSize(t);
        final calls = _Calls();
        final door = g4Door(hardware: 'esp32_c3', qrReader: false);

        await t.pumpWidget(_app(_card(door, calls)));
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('Kapıyı Aç'), findsOneWidget);
        expect(find.text('Gönderildi'), findsNothing);

        // Komut başladı.
        await t.pumpWidget(_app(_card(door, calls, isOpening: true)));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Kapı Açılıyor...'), findsOneWidget);

        // Üst görünümün tek setState'i: komut bitti + başarı sayacı arttı.
        await t.pumpWidget(_app(_card(door, calls, successTick: 1)));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.text('Kapıyı Aç'), findsNothing);

        await t.pump(const Duration(milliseconds: 1500));
        expect(find.text('Gönderildi'), findsNothing);
        expect(find.text('Kapıyı Aç'), findsOneWidget);
      },
    );

    testWidgets('sayaç değişmeden (hata/iptal) başarı gösterilmez', (t) async {
      await _setSize(t);
      final door = g4Door(hardware: 'esp32_c3', qrReader: false);
      await t.pumpWidget(_app(_card(door, _Calls(), isOpening: true)));
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpWidget(_app(_card(door, _Calls())));
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('Gönderildi'), findsNothing);
      expect(find.text('Kapıyı Aç'), findsOneWidget);
    });
  });

  group('erişilebilirlik ve kararlılık', () {
    testWidgets(
      'dokunma hedefleri: kapı açma >= 52 dp, ikincil düğmeler >= 48 dp',
      (t) async {
        await _setSize(t);
        await t.pumpWidget(_app(_card(g4Door(), _Calls())));
        await t.pump(const Duration(milliseconds: 500));

        expect(
          t.getSize(find.byType(DoorOpenButton)).height,
          greaterThanOrEqualTo(52),
        );
        final buttons = find.byType(PrimaryActionButton);
        expect(buttons, findsNWidgets(3));
        for (var i = 0; i < 3; i++) {
          expect(t.getSize(buttons.at(i)).height, greaterThanOrEqualTo(48));
        }
      },
    );

    testWidgets(
      'kararlı durumda sonsuz animasyon yok: pumpAndSettle biter (nabız 3 tur sonra durur)',
      (t) async {
        await _setSize(t);
        await t.pumpWidget(_app(_card(g4Door(), _Calls())));
        await t.pumpAndSettle();
        expect(find.byType(StatusChip), findsWidgets);
      },
    );

    testWidgets('hareket azaltma: tek pump ile son görünüm', (t) async {
      await _setSize(t);
      await t.pumpWidget(_app(_card(g4Door(), _Calls()), reduce: true));
      await t.pump();
      expect(find.text('Uzaktan Aç'), findsOneWidget);
      expect(find.text('Çevrimiçi'), findsOneWidget);
    });

    testWidgets(
      'kapı adı ve konum uzun olsa da kırpılmaz (satıra sarar; test yazı tipi her harfi tam em genişliğinde çizer)',
      (t) async {
        await _setSize(t, width: 320, height: 900);
        final door = g4Door(
          name: 'Kuzey Cephe Otopark Giriş Kapısı',
          siteName: 'Yeşilvadi Sitesi',
          scope: 'BLOCK',
          block: 'C Blok',
        );
        await t.pumpWidget(_app(_card(door, _Calls())));
        await t.pump(const Duration(milliseconds: 500));

        expect(
          g4IsEllipsized(t, find.text('Kuzey Cephe Otopark Giriş Kapısı')),
          isFalse,
        );
        expect(
          g4IsEllipsized(t, find.text('Yeşilvadi Sitesi • C Blok')),
          isFalse,
        );
        expect(t.takeException(), isNull);

        // 1,5x yazıda kısa ad yine kırpılmaz.
        await t.pumpWidget(_app(_card(g4Door(), _Calls()), scale: 1.5));
        await t.pump(const Duration(milliseconds: 500));
        expect(g4IsEllipsized(t, find.text('Ana Giriş Kapısı')), isFalse);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('taşma matrisi', () {
    g4LayoutMatrix('kapı kartı (tüm eylemler)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final door = g4Door(
        name: 'Kuzey Cephe Otopark Giriş Kapısı',
        siteName: 'Yeşilvadi Konutları Doğu Etap Sitesi',
        scope: 'BLOCK',
        block: 'C Blok Zemin Kat',
        geofence: true,
      );
      await pumpAt(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_card(door, _Calls())],
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Uzaktan Aç'), findsOneWidget);
    });

    g4LayoutMatrix('kapı kartı (çevrimdışı, "Kapıyı Aç")', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final door = g4Door(hardware: 'esp32_c3', qrReader: false, online: false);
      await pumpAt(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_card(door, _Calls())],
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Kapıyı Aç'), findsOneWidget);
    });

    g4LayoutMatrix('kapı kartı (komut sürüyor)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final door = g4Door(hardware: 'esp32_c3', qrReader: false);
      await pumpAt(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_card(door, _Calls(), isOpening: true)],
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Kapı Açılıyor...'), findsOneWidget);
    });
  });
}
