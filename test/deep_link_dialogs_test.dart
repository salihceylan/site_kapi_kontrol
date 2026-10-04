import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/app.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

DoorRecord _door(int id, String name, String site) {
  return DoorRecord(
    id: id,
    siteCode: 1,
    siteName: site,
    doorName: name,
    doorIndex: id,
    isActive: true,
    assignedDeviceId: id,
    assignedDeviceUid: 'AABBCCDDEE0$id',
    mqttSiteId: 1,
    createdAt: null,
  );
}

const String _veryLongName =
    'Çok Uzun Bir Kapı Adı Örneği Blok A Giriş Çıkış Otopark Bariyeri Yan Kapısı Numara 12345';
const String _veryLongSite =
    'Gerçekten Çok Uzun İsimli Bir Site Yönetimi Konut Yapı Kooperatifi Sitesi';

Future<void> _pumpWithButton(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required Future<void> Function(BuildContext context) onTap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => onTap(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('DoorOpenConfirmDialog', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long door/site names do not overflow (text scale $scale, 320x480)',
          (tester) async {
        bool? result;
        await _pumpWithButton(
          tester,
          size: const Size(320, 480),
          textScale: scale,
          onTap: (context) async {
            result = await showDialog<bool>(
              context: context,
              builder: (_) => DoorOpenConfirmDialog(
                door: _door(1, _veryLongName, _veryLongSite),
              ),
            );
          },
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Kapı açılsın mı?'), findsOneWidget);
        expect(find.text('Vazgeç'), findsOneWidget);
        expect(find.text('Kapıyı Aç'), findsOneWidget);

        await tester.tap(find.text('Kapıyı Aç'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
      });
    }

    testWidgets('cancel returns false and dismissing returns null', (tester) async {
      bool? result = true;
      await _pumpWithButton(
        tester,
        size: const Size(400, 800),
        textScale: 1.0,
        onTap: (context) async {
          result = await showDialog<bool>(
            context: context,
            builder: (_) => DoorOpenConfirmDialog(
              door: _door(1, 'Ana Kapı', 'Güneş Sitesi'),
            ),
          );
        },
      );
      expect(find.text('Ana Kapı'), findsOneWidget);
      expect(find.text('Güneş Sitesi'), findsOneWidget);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('premium görünüm: cilalı rozetli başlık + uyarı kutusu (metinler aynı)', (
      tester,
    ) async {
      await _pumpWithButton(
        tester,
        size: const Size(400, 800),
        textScale: 1.0,
        onTap: (context) async {
          await showDialog<bool>(
            context: context,
            builder: (_) => DoorOpenConfirmDialog(
              door: _door(1, 'Ana Kapı', 'Güneş Sitesi'),
            ),
          );
        },
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      final orb = tester.widget<IconOrb>(find.byType(IconOrb));
      expect(orb.icon, Icons.lock_open_rounded);
      expect(orb.tone, AppTone.warning);
      final notice = tester.widget<InlineNotice>(find.byType(InlineNotice));
      expect(notice.tone, AppTone.warning);
      expect(
        notice.message,
        'Bu işlem bir bağlantı veya kısayol üzerinden başlatıldı. '
        'Yalnızca siz başlattıysanız onaylayın.',
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
    });
  });

  group('DoorChooserDialog', () {
    testWidgets('many long candidates stay scrollable without overflow', (tester) async {
      DoorRecord? picked;
      final candidates = [
        for (var i = 1; i <= 12; i++) _door(i, '$_veryLongName $i', _veryLongSite),
      ];
      await _pumpWithButton(
        tester,
        size: const Size(320, 480),
        textScale: 2.0,
        onTap: (context) async {
          picked = await showDialog<DoorRecord>(
            context: context,
            builder: (_) => DoorChooserDialog(candidates: candidates),
          );
        },
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Hangi kapı açılsın?'), findsOneWidget);

      await tester.tap(find.textContaining('$_veryLongName 1').first);
      await tester.pumpAndSettle();
      expect(picked?.id, 1);
    });

    testWidgets('premium görünüm: her aday dokunulabilir kart + rozet; seçilen kapı döner', (
      tester,
    ) async {
      DoorRecord? picked;
      await _pumpWithButton(
        tester,
        size: const Size(400, 800),
        textScale: 1.0,
        onTap: (context) async {
          picked = await showDialog<DoorRecord>(
            context: context,
            builder: (_) => DoorChooserDialog(
              candidates: [_door(1, 'Ana Kapı', 'A'), _door(2, 'Otopark', 'A')],
            ),
          );
        },
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      // Başlık rozeti + aday başına bir rozet; her aday bir AppCard (dokunulabilir).
      expect(find.byType(IconOrb), findsNWidgets(3));
      expect(find.byType(AppCard), findsNWidgets(2));
      await tester.tap(find.text('Otopark'));
      await tester.pumpAndSettle();
      expect(picked?.id, 2);
    });

    testWidgets('cancel option returns null', (tester) async {
      DoorRecord? picked = _door(99, 'x', 'y');
      await _pumpWithButton(
        tester,
        size: const Size(400, 800),
        textScale: 1.0,
        onTap: (context) async {
          picked = await showDialog<DoorRecord>(
            context: context,
            builder: (_) => DoorChooserDialog(
              candidates: [_door(1, 'Ana Kapı', 'A'), _door(2, 'Otopark', 'A')],
            ),
          );
        },
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });
  });
}
