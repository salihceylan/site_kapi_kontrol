// FAZ 5 / P-f: uygulama logosu (1024x1024 PNG) giriş sayfasında 82 dp, çekmecede 52 dp gösterilir.
// Tam çözünürlükte çözmek ~4 MB bitmap + gereksiz raster demektir; görüntü boyutuna göre
// (logical px x devicePixelRatio) küçük çözülür. Görünüm aynı kalır.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

void main() {
  testWidgets('ÖLÇÜM: giriş sayfası logosu görüntü boyutuna göre çözülür (bellek)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')))),
    );
    // Görüntü gerçek kodlayıcıyla çözülsün (gerçek zaman).
    await tester.runAsync(() async {
      final logo = find.byType(Image);
      expect(logo, findsWidgets);
      for (final element in logo.evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image).first);
    final bytes = cache.currentSizeBytes;
    print('ÖLÇÜM logo: ImageCache ${(bytes / 1024).toStringAsFixed(0)} KB, sağlayıcı=${image.image.runtimeType}');

    // 82 dp x 3.0 = 246 px -> ~240 KB (RGBA); tam çözünürlük 1024x1024 = 4096 KB.
    expect(image.image, isA<ResizeImage>(), reason: 'logo görüntü boyutuna göre küçük çözülmeli');
    expect(bytes, lessThan(1024 * 1024), reason: 'tam çözünürlüklü (4 MB) bitmap önbellekte tutulmamalı');
    expect(find.text('AHBU Giriş'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('çekmece avatarı (52 dp) logoyu görüntü boyutuna göre çözer; menü görünümü aynı', (tester) async {
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
    expect(avatar.backgroundImage, isA<ResizeImage>());
    expect((avatar.backgroundImage! as ResizeImage).width, 156, reason: '52 dp x 3.0');
    expect(find.text('Ali Veli'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
