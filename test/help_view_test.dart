// "Yardım ve Destek" ekranı (HelpView): rol bazlı "Nasıl yapılır", SSS, destek iletişimi (AppConfigService),
// "Hesabım ve verilerim", yasal belgeler, sürüm, ilk kullanım turunu yeniden açma.
//
// Durumlar: yükleniyor | hata (neden + "Yeniden dene"; "yakında"/"boş" DENMEZ) | veri | yok ("Destek bilgisi
// yakında"). Sahte sunucu: FakeLegalServer + MockClient ile AppConfigService.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/app_config_service.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/help_view.dart';
import 'package:site_kapi_kontrol/ui/views/legal_document_view.dart';
import 'package:site_kapi_kontrol/ui/views/onboarding_tour.dart';

import 'design/harness.dart';
import 'legal_fixtures.dart';

Map<String, dynamic> _config({
  String? email = 'destek@example.com',
  String? phone = '+90 212 555 00 11',
  String? hours = 'Hafta içi 09:00-18:00',
  String? web = 'https://destek.example.com/yardim',
}) => <String, dynamic>{
  'server_time': '2026-10-16T10:00:00.000Z',
  'min_supported_version': '1.0.0',
  'latest_version': '1.0.0',
  'maintenance': <String, dynamic>{'active': false, 'message': null},
  'support': <String, dynamic>{'email': email, 'phone': phone, 'hours': hours, 'web_url': web},
  'legal_enforced': false,
};

class _ConfigServer {
  _ConfigServer({Map<String, dynamic>? body}) : body = body ?? _config();

  Map<String, dynamic> body;
  int status = 200;
  Completer<void>? gate;
  int calls = 0;

  AppConfigService get service => AppConfigService(
    client: MockClient((request) async {
      calls++;
      await gate?.future;
      if (status != 200) {
        return http.Response(jsonEncode(<String, dynamic>{'error': 'x'}), status);
      }
      return http.Response(jsonEncode(body), 200, headers: <String, String>{'content-type': 'application/json'});
    }),
    baseUrl: 'https://api.example.test',
    timeout: const Duration(seconds: 3),
  );
}

class _Env {
  _Env({this.role = UserRole.individual, this.residentMode = false, this.userId, this.onOpenProfile}) {
    legal = FakeLegalServer();
    config = _ConfigServer();
  }

  final UserRole role;
  final bool residentMode;
  final int? userId;
  final VoidCallback? onOpenProfile;
  late FakeLegalServer legal;
  late _ConfigServer config;
  final List<Uri> launched = <Uri>[];
  bool launchResult = true;

  Widget view() => HelpView(
    role: role,
    residentMode: residentMode,
    userId: userId,
    legalApi: legal.api,
    configService: config.service,
    versionLoader: () async => '1.2.3 (45)',
    launcher: (uri) async {
      launched.add(uri);
      return launchResult;
    },
    onOpenProfile: onOpenProfile,
  );
}

Future<void> _pump(
  WidgetTester t,
  _Env env, {
  double width = 412,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(harnessApp(Builder(builder: (_) => const SizedBox.shrink()), scale: scale, dark: dark));
  await t.pumpWidget(_wrap(env, scale: scale, dark: dark));
  await t.pump();
  await t.pump(const Duration(milliseconds: 150));
}

Widget _wrap(_Env env, {double scale = 1.0, bool dark = false}) {
  // HelpView kendi Scaffold'unu getirir: harnessApp yerine doğrudan MaterialApp.
  return harnessAppPlain(env.view(), scale: scale, dark: dark);
}

Widget harnessAppPlain(Widget home, {double scale = 1.0, bool dark = false}) {
  final app = harnessApp(const SizedBox.shrink(), scale: scale, dark: dark) as MaterialApp;
  return MaterialApp(
    theme: app.theme,
    darkTheme: app.darkTheme,
    themeMode: app.themeMode,
    builder: app.builder,
    home: home,
  );
}

Future<void> _tapText(WidgetTester t, String text) async {
  final finder = find.text(text);
  await t.ensureVisible(finder.first);
  await t.pump(const Duration(milliseconds: 250));
  await t.tap(finder.first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('İçerik', () {
    testWidgets('bölümler ve rol bazlı konular: bireysel', (t) async {
      await _pump(t, _Env(role: UserRole.individual));
      expect(find.text('Yardım ve Destek'), findsOneWidget);
      for (final heading in const <String>[
        'Nasıl yapılır',
        'Sık sorulan sorular',
        'Destek',
        'Hesabım ve verilerim',
        'Yasal belgeler',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(find.text('Cihazımı hesabıma nasıl eklerim?'), findsOneWidget);
      expect(find.text('Site yöneticisi olmak için nasıl başvururum?'), findsOneWidget);
      expect(find.text('Kapıyı nasıl açarım?'), findsNothing, reason: 'bireysel kullanıcıda kapı yok');
      expect(find.text('Uygulama sürümü: 1.2.3 (45)'), findsOneWidget);
    });

    testWidgets('daire sakini / sakin modundaki yönetici / yönetici / süper kullanıcı kendi konularını görür', (t) async {
      for (final (env, expected, absent) in <(_Env, String, String)>[
        (_Env(role: UserRole.apartmentOwner), 'Kapıyı nasıl açarım?', 'Duyuru nasıl yayınlarım?'),
        (_Env(role: UserRole.siteManager, residentMode: true), 'Kapıyı nasıl açarım?', 'Duyuru nasıl yayınlarım?'),
        (_Env(role: UserRole.siteManager), 'Duyuru nasıl yayınlarım?', 'Kapıyı nasıl açarım?'),
        (_Env(role: UserRole.superUser), 'Kullanıcıları nasıl yönetirim?', 'Kapıyı nasıl açarım?'),
      ]) {
        await _pump(t, env);
        expect(find.text(expected), findsOneWidget, reason: '${env.role} ${env.residentMode}');
        expect(find.text(absent), findsNothing, reason: '${env.role} ${env.residentMode}');
      }
    });

    testWidgets('konuya dokunmak numaralı adımları ve notu açar; SSS cevabı açılır', (t) async {
      await _pump(t, _Env(role: UserRole.apartmentOwner));
      expect(find.textContaining('KAPIYI AÇ'), findsNothing, reason: 'kapalı konu içeriği ağaçta yok');
      await _tapText(t, 'Kapıyı nasıl açarım?');
      expect(find.textContaining('“KAPIYI AÇ” düğmesine dokunun'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      // Kapı "Kapılar" ekranındadır (Panel modül vitrinidir): ilk adım oraya götürür, not "Kapılar" yokluğunu anlatır.
      expect(find.textContaining('ekranındaki “Kapılar” kartına dokunun'), findsOneWidget);
      expect(find.textContaining('“Kapılar” kartı, menüde de “Kapılar” yoksa'), findsOneWidget);
      expect(find.textContaining('Panelde kapı kartı görünmüyorsa'), findsNothing);

      await _tapText(t, 'Şifremi unuttum, ne yapmalıyım?');
      expect(find.textContaining('“Şifremi Unuttum?” bağlantısına dokunun'), findsOneWidget);
    });

    testWidgets('her rol "Panel ekranında neler var?" konusunu görür; konu vitrini ve "Kapılar"ı anlatır', (t) async {
      for (final env in <_Env>[
        _Env(role: UserRole.apartmentOwner),
        _Env(role: UserRole.individual),
        _Env(role: UserRole.siteManager),
        _Env(role: UserRole.superUser),
      ]) {
        await _pump(t, env);
        expect(find.text('Panel ekranında neler var?'), findsOneWidget, reason: '${env.role}');
        await _tapText(t, 'Panel ekranında neler var?');
        expect(find.textContaining('ekranı modül vitrinidir'), findsOneWidget, reason: '${env.role}');
        expect(find.textContaining('“Kapılar”'), findsWidgets, reason: '${env.role}');
      }
    });
  });

  group('Destek iletişimi', () {
    testWidgets('yükleniyor -> veri: e-posta, telefon, saatler, web; eylemler doğru adresleri açar', (t) async {
      final env = _Env();
      env.config.gate = Completer<void>();
      await _pump(t, env);
      expect(find.text('Destek bilgisi yakında'), findsNothing, reason: 'yükleniyorken "yakında" denmez');
      expect(find.text('destek@example.com'), findsNothing);

      env.config.gate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('destek@example.com'), findsOneWidget);
      expect(find.text('+90 212 555 00 11'), findsOneWidget);
      expect(find.text('Hafta içi 09:00-18:00'), findsOneWidget);
      expect(find.text('destek.example.com'), findsOneWidget);

      await _tapText(t, 'E-posta gönder');
      await _tapText(t, 'Ara');
      await _tapText(t, 'Web sitesini aç');
      expect(env.launched.map((u) => u.toString()), <String>[
        'mailto:destek@example.com',
        'tel:+902125550011',
        'https://destek.example.com/yardim',
      ]);
    });

    testWidgets('uygulama açılamazsa değer panoya kopyalanır ve uyarı gösterilir', (t) async {
      final clipboard = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final env = _Env()..launchResult = false;
      await _pump(t, env);
      await _tapText(t, 'E-posta gönder');
      expect(clipboard, <String>['destek@example.com']);
      expect(find.text('Uygulama açılamadı; bilgi panoya kopyalandı.'), findsOneWidget);
    });

    testWidgets('Kopyala düğmesi', (t) async {
      final clipboard = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(t, _Env());
      await t.ensureVisible(find.text('Kopyala').first);
      await t.pump(const Duration(milliseconds: 250));
      await t.tap(find.text('Kopyala').first);
      await t.pump();
      expect(clipboard, <String>['destek@example.com']);
      expect(find.text('Panoya kopyalandı.'), findsOneWidget);
    });

    testWidgets('destek bilgisi tanımlı değilse "Destek bilgisi yakında" (hata değil)', (t) async {
      final env = _Env();
      env.config.body = _config(email: null, phone: null, hours: null, web: null);
      await _pump(t, env);
      expect(find.text('Destek bilgisi yakında'), findsOneWidget);
      expect(find.text('Yeniden dene'), findsNothing);
    });

    testWidgets('geçersiz değerler gösterilmez: boşluklu e-posta, http adres, harfli telefon', (t) async {
      final env = _Env();
      env.config.body = _config(email: 'a b@x.com', phone: 'ara beni', hours: null, web: 'http://insecure.example.com');
      await _pump(t, env);
      expect(find.text('Destek bilgisi yakında'), findsOneWidget);
      expect(find.text('E-posta gönder'), findsNothing);
      expect(find.text('Ara'), findsNothing);
      expect(find.text('Web sitesini aç'), findsNothing);
    });

    testWidgets('yapılandırma alınamadı: "yakında" DENMEZ; neden + "Yeniden dene"; düzelince veri gelir', (t) async {
      final env = _Env();
      env.config.status = 500;
      await _pump(t, env);
      expect(find.text('Destek bilgisi yakında'), findsNothing);
      expect(find.textContaining('Destek bilgisi alınamadı'), findsOneWidget);
      expect(find.text('Yeniden dene'), findsWidgets);

      env.config.status = 200;
      // Destek bölümündeki "Yeniden dene" (belge listesi ayrıca başarılı olduğundan tek buton kalır).
      await _tapText(t, 'Yeniden dene');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('destek@example.com'), findsOneWidget);
    });

    testWidgets('önbellekte bilgi varsa anında gösterilir (ağ gecikse bile)', (t) async {
      final env = _Env();
      final service = env.config.service;
      await service.load();
      env.config.gate = Completer<void>();
      t.view.physicalSize = const Size(412, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harnessAppPlain(
          HelpView(
            role: UserRole.individual,
            legalApi: env.legal.api,
            configService: service,
            versionLoader: () async => '1.0.0 (1)',
            launcher: (_) async => true,
          ),
        ),
      );
      await t.pump();
      expect(find.text('destek@example.com'), findsOneWidget);
      env.config.gate!.complete();
      await t.pump(const Duration(milliseconds: 200));
    });
  });

  group('Hesabım ve verilerim', () {
    testWidgets('bilgi metni Profilim\'e yönlendirir; düğme yalnız geri çağrı varken görünür', (t) async {
      await _pump(t, _Env());
      expect(find.textContaining('Profilim'), findsWidgets);
      expect(find.text('Profilim ekranına git'), findsNothing);
    });

    testWidgets('"Profilim ekranına git": ekran kapanır ve geri çağrı çalışır', (t) async {
      var opened = 0;
      final env = _Env(onOpenProfile: () => opened++);
      t.view.physicalSize = const Size(412, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harnessAppPlain(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => env.view())),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Aç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Yardım ve Destek'), findsOneWidget);
      await _tapText(t, 'Profilim ekranına git');
      await t.pump(const Duration(milliseconds: 500));
      expect(opened, 1);
      expect(find.text('Yardım ve Destek'), findsNothing);
    });
  });

  group('Yasal belgeler', () {
    testWidgets('liste: ad + sürüm + yürürlük; dokununca belge açılır (tek sayfa)', (t) async {
      final env = _Env();
      env.legal.contents['privacy'] = '# Gizlilik\n\nİçerik metni';
      await _pump(t, env);
      expect(find.byKey(const ValueKey<String>('help_legal_terms')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('help_legal_account_deletion')), findsOneWidget);
      expect(find.text('Sürüm: 2026-10-16 · Yürürlük: 16.10.2026'), findsWidgets);

      final tile = find.byKey(const ValueKey<String>('help_legal_privacy'));
      await t.ensureVisible(tile);
      await t.pump(const Duration(milliseconds: 250));
      final at = t.getCenter(tile);
      await t.tapAt(at);
      await t.tapAt(at);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(LegalDocumentView), findsOneWidget);
      expect(env.legal.where('GET', '/public/legal-documents/privacy'), hasLength(1));
    });

    testWidgets('liste yüklenemedi: "belge yok" DENMEZ; neden + "Yeniden dene"; düzelince liste gelir', (t) async {
      final env = _Env();
      env.legal.listStatus = 500;
      await _pump(t, env);
      expect(find.text('Şu an yayımlanmış bir belge yok.'), findsNothing);
      expect(find.byKey(const ValueKey<String>('help_legal_terms')), findsNothing);
      expect(find.text('Yeniden dene'), findsWidgets);

      env.legal.listStatus = 200;
      await _tapText(t, 'Yeniden dene');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey<String>('help_legal_terms')), findsOneWidget);
    });

    testWidgets('liste başarıyla boş: "Şu an yayımlanmış bir belge yok."', (t) async {
      final env = _Env();
      env.legal = FakeLegalServer(documents: <Map<String, dynamic>>[]);
      await _pump(t, env);
      expect(find.text('Şu an yayımlanmış bir belge yok.'), findsOneWidget);
    });
  });

  group('Sürüm ve tur', () {
    Future<void> pumpDefaultLoader(WidgetTester t) async {
      t.view.physicalSize = const Size(412, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final env = _Env();
      await t.pumpWidget(
        harnessAppPlain(
          HelpView(
            role: UserRole.individual,
            legalApi: env.legal.api,
            configService: env.config.service,
            launcher: (_) async => true,
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('platform sürüm bilgisi okunamazsa yapı sabitine düşer (varsayılan yükleyici)', (t) async {
      // package_info_plus kanalı hata verir (örn. eklenti yok): sürüm yine gösterilir.
      const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unavailable');
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      await pumpDefaultLoader(t);
      expect(find.text('Uygulama sürümü: v1.0.0 (Build 1)'), findsOneWidget);
    });

    testWidgets('sürüm package_info_plus ile okunur: sürüm (derleme)', (t) async {
      PackageInfo.setMockInitialValues(
        appName: 'AHBU',
        packageName: 'tr.test',
        version: '2.5.1',
        buildNumber: '42',
        buildSignature: '',
      );
      await pumpDefaultLoader(t);
      expect(find.text('Uygulama sürümü: 2.5.1 (42)'), findsOneWidget);
    });

    testWidgets('"Tanıtım turunu göster" turu açar; kapanınca "görüldü" işaretlenir', (t) async {
      final env = _Env(role: UserRole.apartmentOwner, userId: 77);
      await _pump(t, env);
      await _tapText(t, 'Tanıtım turunu göster');
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Kapınız cebinizde'), findsOneWidget);
      expect(find.text('Atla'), findsOneWidget);

      await t.tap(find.text('Atla'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Kapınız cebinizde'), findsNothing);
      expect(await OnboardingTour.hasSeen(77), isTrue);
    });
  });

  group('Taşma', () {
    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 2.0), // yatay + büyük yazı
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('tüm bölümler açıkken taşma yok (${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'})', (t) async {
          for (final role in UserRole.values) {
            final env = _Env(role: role, onOpenProfile: () {});
            await _pump(t, env, width: w, height: h, scale: s, dark: dark);
            expect(t.takeException(), isNull, reason: '$role');
            // Her konuyu aç (yalnız ilki değil): en uzun metinler de taşmaz. Dokunuştan sonra İKİ kare: ilki açılma
            // animasyonunu başlatır, ikincisi bitirir (tek `pump(süre)` içeriği 0 yükseklikte bırakırdı ve sonraki
            // konunun yeri kayardı).
            final topics = HelpContent.howToFor(HelpContent.audienceFor(role));
            for (final topic in topics) {
              final title = find.text(topic.title);
              await t.ensureVisible(title);
              await t.pump(const Duration(milliseconds: 250));
              expect(title.hitTestable(), findsOneWidget, reason: '$role ${topic.id}: başlık dokunulabilir');
              await t.tap(title);
              await t.pump();
              await t.pump(const Duration(milliseconds: 400));
              expect(t.takeException(), isNull, reason: '$role açık konu: ${topic.id}');
              expect(find.textContaining(topic.steps.first), findsWidgets, reason: '$role ${topic.id}: konu açıldı');
            }
          }
        });
      }
    }

    testWidgets('hata durumları (destek + belge) dar ve yatay büyük yazıda taşmaz', (t) async {
      for (final (w, h) in const <(double, double)>[(320, 640), (640, 360)]) {
        final env = _Env();
        env.config.status = 500;
        env.legal.listStatus = 500;
        await _pump(t, env, width: w, height: h, scale: 2.0);
        expect(t.takeException(), isNull, reason: '${w.toInt()}x${h.toInt()}');
        await t.ensureVisible(find.text('Yeniden dene').first);
        await t.pump();
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('AppBar başlığı "Yardım ve Destek" büyük yazıda kırpılmaz (iki satıra sarar, çubuk büyür)', (t) async {
      double contentHeight(RenderParagraph p) {
        final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: p.text.toPlainText().length));
        return boxes.map((b) => b.bottom).fold<double>(0, math.max);
      }

      for (final (w, s) in const <(double, double)>[(360, 2.0), (360, 1.5), (412, 2.0), (640, 2.0)]) {
        await _pump(t, _Env(), width: w, height: 800, scale: s);
        final title = t.renderObject<RenderParagraph>(
          find.descendant(of: find.byType(AppBar), matching: find.text('Yardım ve Destek')),
        );
        final bar = t.getSize(find.byType(AppBar)).height;
        expect(title.didExceedMaxLines, isFalse, reason: '${w.toInt()} x$s');
        expect(contentHeight(title), lessThanOrEqualTo(bar), reason: '${w.toInt()} x$s: başlık çubuktan taşmaz');
        if (w <= 412) {
          expect(bar, greaterThan(kToolbarHeight), reason: 'dar çubukta iki satır için yer açılır');
        }
      }
    });
  });
}
