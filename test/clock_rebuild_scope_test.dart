// FAZ 5 / P-d: DigitalClockWidget'ın saniyelik güncellemesi yalnız saat metnini yeniden kurar.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/widgets/digital_clock_widget.dart';

import 'support/rebuild_probe.dart';

const _session = UserSession(
  id: 1,
  fullName: 'Yönetici Ahmet Yılmaz',
  email: 'admin@example.com',
  loginName: 'admin',
  role: UserRole.superUser,
  isActive: true,
  token: 'test_token',
);

void main() {
  tearDown(RebuildProbe.stop);

  Widget host(DateTime Function() now, {double width = 360}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: DigitalClockWidget(session: _session, nowProvider: now)),
          ),
        ),
      );

  testWidgets('ÖLÇÜM: 5 saniyelik kullanımda yalnız saat metni yeniden kurulur', (tester) async {
    var now = DateTime(2026, 5, 1, 10, 0, 0);
    await tester.pumpWidget(host(() => now));
    await tester.pump();
    expect(find.text('10:00:00'), findsOneWidget);

    RebuildProbe.start();
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
    print(
      'ÖLÇÜM saat 5 sn: toplam yeniden kurma=${RebuildProbe.total}, '
      'DigitalClockWidget=${RebuildProbe.count(DigitalClockWidget)}, LayoutBuilder=${RebuildProbe.count(LayoutBuilder)}, '
      'Container=${RebuildProbe.count(Container)}, Column=${RebuildProbe.count(Column)}, '
      'Row=${RebuildProbe.count(Row)}, Text=${RebuildProbe.count(Text)}',
    );

    expect(find.text('10:00:05'), findsOneWidget, reason: 'saat metni her saniye güncellenir');
    expect(RebuildProbe.count(DigitalClockWidget), 0, reason: 'kart iskeleti yeniden kurulmaz');
    expect(RebuildProbe.count(LayoutBuilder), 0);
    expect(RebuildProbe.count(Container), 0);
    expect(RebuildProbe.count(Column), 0);
    expect(RebuildProbe.count(Row), 0);
    expect(RebuildProbe.count(Text), 5, reason: 'yalnız saat metni (saniyede bir)');
    expect(RebuildProbe.total, lessThanOrEqualTo(12));
  });

  testWidgets('gün değişince tarih metni de güncellenir (yalnız o anda)', (tester) async {
    var now = DateTime(2026, 5, 1, 23, 59, 57);
    await tester.pumpWidget(host(() => now));
    await tester.pump();
    expect(find.text('1 Mayıs 2026, Cuma'), findsOneWidget);

    RebuildProbe.start();
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('2 Mayıs 2026, Cumartesi'), findsOneWidget, reason: 'gece yarısından sonra tarih değişir');
    expect(find.text('00:00:02'), findsOneWidget);
    // 5 saat güncellemesi + 1 tarih güncellemesi.
    expect(RebuildProbe.count(Text), 6);
    expect(RebuildProbe.count(DigitalClockWidget), 0);
  });

  testWidgets('kartı üst widget yeniden kursa da görünüm aynıdır; taşma yok (320 px, 1.5x yazı)', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var now = DateTime(2026, 5, 1, 10, 0, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: DigitalClockWidget(session: _session, nowProvider: () => now),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Yönetici Ahmet Yılmaz'), findsOneWidget);
    expect(find.text('TSİ (UTC+3)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arka plana alınınca saat durur, dispose\'ta zamanlayıcı kalmaz', (tester) async {
    var now = DateTime(2026, 5, 1, 10, 0, 0);
    await tester.pumpWidget(host(() => now));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('10:00:00'), findsOneWidget, reason: 'arka planda güncelleme yok');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('10:00:30'), findsOneWidget, reason: 'ön plana dönünce hemen güncellenir');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    // Bekleyen Timer varsa flutter_test testi başarısız kılar.
  });
}
