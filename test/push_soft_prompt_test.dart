// Telefon bildirimi (Faz 3b-B, B8) — Duyurular ekranındaki "telefon bildirimini aç" yumuşak istem kartı ve
// açıklama cümlesi. Kart YALNIZ şu koşulların hepsinde görünür: push_available, bu cihaz push alabilir, bu cihazda
// açılmamış, izin kalıcı reddedilmemiş, kullanıcı kapatmamış (kalıcı). "Aç" açık rızadır (izin + kayıt).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/services/push_store.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/push_soft_prompt_card.dart';

import 'push_fakes.dart';
import 'screens/announcement_fixtures.dart';
import 'screens/dialog_layout_harness.dart' show settleFor;
import 'screens/list_fixtures.dart';

const ValueKey<String> _card = ValueKey<String>('push_soft_prompt');

void main() {
  late PushEventLog events;
  late FakePushGateway gateway;
  late FakePushApi api;
  late PushService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    events = <String>[];
    gateway = FakePushGateway(events, permission: PushPermission.notDetermined)
      ..permissionAfterRequest = PushPermission.granted;
    api = FakePushApi(events);
    service = PushService(apiFactory: (_) => api, appVersion: () async => '1.0.0', observeLifecycle: false);
  });

  tearDown(() async {
    PushService.debugInstance = null;
    await service.dispose();
    await gateway.close();
  });

  AnnouncementFakeAuth auth() => AnnouncementFakeAuth(role: UserRole.apartmentOwner);

  Future<void> pumpCard(
    WidgetTester t,
    AnnouncementFakeAuth a, {
    double width = 400,
    double height = 900,
    double scale = 1.0,
    bool dark = false,
  }) async {
    await pumpList(
      t,
      PushSoftPromptCard(authService: a, pushService: service),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
  }

  listMatrix('kart: başlık, açıklama, "Aç" ve "Şimdi değil"', (t, w, h, s, dark) async {
    await service.start(gateway);
    await pumpCard(t, auth(), width: w, height: h, scale: s, dark: dark);
    expect(find.byKey(_card), findsOneWidget);
    expect(find.text(PushSoftPromptCardState.title), findsOneWidget);
    expect(find.text('Aç'), findsOneWidget);
    expect(find.text('Şimdi değil'), findsOneWidget);
    expect(gateway.requestCalls, 0, reason: 'kart görünmesi izin İSTEMEZ');
    expect(api.registers, isEmpty);
  });

  testWidgets('"Aç": izin bağlamda istenir, cihaz kaydedilir, rıza işaretlenir; sonuç yazılır, "Kapat" gizler', (t) async {
    await service.start(gateway);
    final a = auth();
    await pumpCard(t, a);
    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_enable')));
    await settleFor(t);
    expect(gateway.requestCalls, 1);
    expect(api.registers, hasLength(1));
    expect(await PushLocalStore().isEnabledHere(5), isTrue);
    expect(find.text('Telefon bildirimleri bu cihazda açıldı.'), findsOneWidget);
    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_close')));
    await settleFor(t);
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('"Aç" ama izin reddedildi: dürüst uyarı, kayıt yok', (t) async {
    gateway.permissionAfterRequest = PushPermission.denied;
    await service.start(gateway);
    await pumpCard(t, auth());
    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_enable')));
    await settleFor(t);
    expect(api.registers, isEmpty);
    expect(find.textContaining('Bildirim izni verilmedi.'), findsOneWidget);
  });

  testWidgets('"Aç" sonrası izin KALICI reddedildi: bilgilendirme + "Telefon ayarlarını aç" ayarları açar (rıza kalır)', (t) async {
    gateway.permissionAfterRequest = PushPermission.permanentlyDenied;
    await service.start(gateway);
    final a = auth();
    service.attach(a); // ana sayfadaki gibi (ön plana dönüş kaydı oturumla yapılır)
    addTearDown(() => service.detach(a));
    await pumpCard(t, a);
    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_enable')));
    await settleFor(t);
    expect(api.registers, isEmpty);
    expect(
      find.textContaining('İzin verdiğinizde bu cihaz telefon bildirimi için kaydedilir.'),
      findsOneWidget,
    );
    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_settings')));
    await settleFor(t);
    expect(gateway.settingsOpened, isTrue);
    expect(await PushLocalStore().isEnabledHere(5), isTrue);

    // Kullanıcı ayarlardan izin verip döndü: kayıt kendiliğinden yapılır.
    gateway.permission = PushPermission.granted;
    service.onAppResumed();
    await settleFor(t);
    expect(api.registers, hasLength(1));
  });

  testWidgets('"Şimdi değil": kart kapanır ve bu kullanıcı için KALICI (yeniden kurulunca da görünmez)', (t) async {
    await service.start(gateway);
    final a = auth();
    await pumpCard(t, a);
    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_dismiss')));
    await settleFor(t);
    expect(find.byKey(_card), findsNothing);
    await t.pumpWidget(const SizedBox());
    await pumpCard(t, a);
    expect(find.byKey(_card), findsNothing);
    expect(gateway.requestCalls, 0);
  });

  testWidgets('görünmez: push kapalı / kalıcı ret / zaten açık / gateway yok / alıcı olmayan rol', (t) async {
    // Gateway yok (web / masaüstü / Firebase başlatılamadı).
    await pumpCard(t, auth());
    expect(find.byKey(_card), findsNothing);

    await service.start(gateway);
    api.prefs = const PushPreferences(available: false);
    await t.pumpWidget(const SizedBox());
    await pumpCard(t, auth());
    expect(find.byKey(_card), findsNothing, reason: 'push_available false');

    final fresh = PushService(apiFactory: (_) => api, observeLifecycle: false);
    addTearDown(fresh.dispose);
    api.prefs = const PushPreferences(available: true);
    gateway.permission = PushPermission.permanentlyDenied;
    await fresh.start(gateway);
    await t.pumpWidget(const SizedBox());
    await pumpList(t, PushSoftPromptCard(authService: auth(), pushService: fresh), width: 400, height: 900, scale: 1, dark: false);
    await settleFor(t, 100);
    expect(find.byKey(_card), findsNothing, reason: 'kalıcı ret');

    gateway.permission = PushPermission.notDetermined;
    await pushConsent(5);
    await t.pumpWidget(const SizedBox());
    await pumpList(t, PushSoftPromptCard(authService: auth(), pushService: fresh), width: 400, height: 900, scale: 1, dark: false);
    await settleFor(t, 100);
    expect(find.byKey(_card), findsNothing, reason: 'bu cihazda zaten açık');

    await t.pumpWidget(const SizedBox());
    await pumpList(
      t,
      PushSoftPromptCard(authService: AnnouncementFakeAuth(role: UserRole.superUser), pushService: fresh),
      width: 400,
      height: 900,
      scale: 1,
      dark: false,
    );
    await settleFor(t, 100);
    expect(find.byKey(_card), findsNothing, reason: 'süper kullanıcı alıcı değil');
  });

  testWidgets('Duyurular (gelen kutusu): kart görünür; açıklama bu cihazın durumuna göre "gelmez" / "gelir"', (t) async {
    PushService.debugInstance = service;
    await service.start(gateway);
    final a = auth();
    await pumpList(
      t,
      AnnouncementsView(authService: a, showInbox: true),
      width: 400,
      height: 1400,
      scale: 1.0,
      dark: false,
    );
    await settleFor(t);
    expect(find.byKey(_card), findsOneWidget);
    expect(find.textContaining('uygulama kapalıyken bu cihaza telefon bildirimi gelmez.'), findsOneWidget);

    await tapFinder(t, find.byKey(const ValueKey<String>('push_prompt_enable')));
    await settleFor(t);
    expect(service.activeHere.value, isTrue);
    expect(
      find.textContaining("uygulama kapalıyken bu cihaza telefon bildirimi gelir (Bildirim Tercihleri'nize göre)."),
      findsOneWidget,
    );
    expect(find.textContaining('telefon bildirimi gelmez'), findsNothing);

    // Sunucu push'u kapandı (tercihler okunurken öğrenildi): "gelir" iddiası geri çekilir.
    api.prefs = const PushPreferences(available: false);
    await service.getPreferences(a);
    await settleFor(t);
    expect(find.textContaining('uygulama kapalıyken bu cihaza telefon bildirimi gelmez.'), findsOneWidget);
  });

  testWidgets('Duyurular yönetim görünümünde kart yok', (t) async {
    PushService.debugInstance = service;
    await service.start(gateway);
    await pumpList(
      t,
      AnnouncementsView(authService: AnnouncementFakeAuth.seeded(), manageSites: true),
      width: 400,
      height: 1400,
      scale: 1.0,
      dark: false,
    );
    await settleFor(t);
    expect(find.byKey(_card), findsNothing);
    expect(api.prefsCalls, 0);
  });
}
