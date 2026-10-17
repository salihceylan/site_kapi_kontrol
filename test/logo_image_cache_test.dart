// FAZ 5 / P-f -> Güde Teknoloji logosu: uygulama logosu artık VEKTÖR (lib/brand); eskiden 1024x1024 PNG giriş sayfasında
// 82 dp, çekmecede 52 dp gösteriliyor ve görüntü boyutuna göre küçük çözülüyordu. Vektör logo bitmap çözmez:
// ImageCache'e hiçbir şey girmez (bellek ~0), görünüm ise aynı kalır.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/brand/gude_logo_animated.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

void main() {
  testWidgets('ÖLÇÜM: giriş sayfası logosu vektördür; ImageCache boş kalır (bellek)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')))),
    );
    await tester.pump();

    print('ÖLÇÜM logo: ImageCache ${cache.currentSizeBytes} B, canlı görüntü=${cache.liveImageCount}');
    expect(find.byType(AnimatedGudeLogo), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'bitmap logo yok');
    expect(cache.currentSizeBytes, 0, reason: 'vektör logo bitmap çözmez');
    expect(cache.liveImageCount, 0);
    expect(find.text('Site ve Toplu Yaşam Yönetim Sistemi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('çekmece avatarı (52 dp) yaprak işaretini vektör çizer; bitmap çözülmez; menü görünümü aynı', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: YanMenu(
            fullName: 'Ali Veli',
            userEmail: 'ali@example.com',
            role: UserRole.individual,
            selectedItem: SirketMenuItem.dashboard,
            onSelect: (_) {},
            onLogout: () {},
          ),
          body: const SizedBox(),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
    expect(avatar.backgroundImage, isNull, reason: 'bitmap arka plan yok');
    expect(avatar.child, isA<AnimatedGudeLeafMark>());
    expect(tester.getSize(find.byType(AnimatedGudeLeafMark)), const Size(52, 52));
    expect(cache.currentSizeBytes, 0);
    expect(find.text('Ali Veli'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
