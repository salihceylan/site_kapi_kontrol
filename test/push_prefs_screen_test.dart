// Telefon bildirimi (Faz 3b-B) — Profil -> Bildirim Tercihleri ekranı (B7/B8): push_available true olunca
// "Yakında…" yerine gerçek anahtar, başlık önizlemesi, sessiz saatler (saat seçici), cihazlarım, test bildirimi.
// Dürüst yükleme / hata / boş durumları; izin bağlam içinde; 320×640 ×2,0 yazı ölçeğinde taşma yok.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/services/push_store.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/notification_prefs_section.dart';
import 'package:site_kapi_kontrol/ui/widgets/push_prefs_panel.dart';

import 'push_fakes.dart';
import 'screens/announcement_fixtures.dart';
import 'screens/dialog_layout_harness.dart' show settleFor;
import 'screens/list_fixtures.dart';

/// E-posta tercihleri sahte servisten; `push_available` testten sürülür.
class _PushPrefsAuth extends AnnouncementFakeAuth {
  _PushPrefsAuth({this.pushAvailable = true}) : super(role: UserRole.apartmentOwner);

  bool pushAvailable;

  @override
  Future<NotificationPrefs> getNotificationPreferences() async {
    final base = await super.getNotificationPreferences();
    return NotificationPrefs(
      emailAnnouncements: base.emailAnnouncements,
      pushAnnouncements: base.pushAnnouncements,
      pushAvailable: pushAvailable,
      emailSuppressed: base.emailSuppressed,
    );
  }
}

const ValueKey<String> _announceKey = ValueKey<String>('push_announcements_switch');
const ValueKey<String> _previewKey = ValueKey<String>('push_preview_switch');
const ValueKey<String> _quietKey = ValueKey<String>('push_quiet_switch');

void main() {
  late PushEventLog events;
  late FakePushGateway gateway;
  late FakePushApi api;
  late PushService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    events = <String>[];
    gateway = FakePushGateway(events);
    api = FakePushApi(events);
    service = PushService(
      apiFactory: (_) => api,
      appVersion: () async => '1.0.0',
      observeLifecycle: false,
      cleanupRetryDelays: const <Duration>[], // ekran testlerinde bekleyen zamanlayıcı kalmasın
    );
  });

  tearDown(() async {
    await service.dispose();
    await gateway.close();
  });

  /// Bu cihaz kayıtlı + başka bir iPhone; sessiz saatler açık (en kalabalık görünüm).
  Future<_PushPrefsAuth> fullState() async {
    final auth = _PushPrefsAuth();
    await service.start(gateway);
    await service.enableOnThisDevice(auth);
    api
      ..prefs = const PushPreferences(available: true, quietEnabled: true, showPreview: true, deviceCount: 2)
      ..devices = <PushDevice>[
        ...api.devices,
        PushDevice(
          installId: 'diger-cihaz-0000-1111',
          platform: 'ios',
          appVersion: '0.9.0',
          lastSeenAt: DateTime.utc(2026, 10, 1, 8, 30),
        ),
      ];
    return auth;
  }

  Future<void> pumpSection(
    WidgetTester t,
    AuthService auth, {
    double width = 400,
    double height = 900,
    double scale = 1.0,
    bool dark = false,
  }) async {
    await pumpList(
      t,
      NotificationPrefsSection(authService: auth, pushService: service),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
  }

  Future<void> pumpPanel(WidgetTester t, AuthService auth, {PushTimePicker? pickTime}) async {
    await pumpList(
      t,
      PushPrefsPanel(authService: auth, pushService: service, pickTime: pickTime),
      width: 400,
      height: 900,
      scale: 1.0,
      dark: false,
    );
    await settleFor(t, 100);
  }

  bool switchValue(WidgetTester t, ValueKey<String> key) => t.widget<SwitchListTile>(find.byKey(key)).value;

  group('taşma matrisi', () {
    listMatrix('dolu: anahtarlar, sessiz saat düğmeleri, iki cihaz ("Bu cihaz"), test düğmesi', (t, w, h, s, dark) async {
      final auth = await fullState();
      await pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Telefon bildirimi'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNothing);
      expect(find.text('Bildirimde duyuru başlığını göster'), findsOneWidget);
      expect(find.text('Sessiz saatler'), findsOneWidget);
      expect(find.textContaining('Acil duyurular sessiz saatlerde de gelir.'), findsOneWidget);
      expect(find.text('Başlangıç: 23:00'), findsOneWidget);
      expect(find.text('Bitiş: 07:00'), findsOneWidget);
      expect(find.text('Cihazlarım'), findsOneWidget);
      expect(find.text('Android telefon'), findsOneWidget);
      expect(find.text('iPhone / iPad'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Bu cihaz'), findsOneWidget);
      expect(find.text('Test bildirimi gönder'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('push_device_status')), findsNothing, reason: 'her şey yolunda');
    });

    listMatrix('varsayılan (rıza yok): "Bu cihazda telefon bildirimi kapalı" + "Bu cihazda aç"', (t, w, h, s, dark) async {
      final auth = _PushPrefsAuth();
      gateway.permission = PushPermission.granted; // Android 12-: izin varsayılan açık, yine de kayıt YOK
      await service.start(gateway);
      await pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text(PushPrefsPanelState.disabledHereNote), findsOneWidget);
      expect(find.text('Bu cihazda aç'), findsOneWidget);
      expect(api.registers, isEmpty);
      expect(gateway.getTokenCalls, 0);
    });

    listMatrix('rıza var, izin yok: uyarı + "İzin ver" + "Telefon ayarlarını aç"', (t, w, h, s, dark) async {
      final auth = _PushPrefsAuth();
      await pushConsent(5);
      gateway.permission = PushPermission.denied;
      await service.start(gateway);
      await pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text(PushPrefsPanelState.noPermissionNote), findsOneWidget);
      expect(find.text('İzin ver'), findsOneWidget);
      expect(find.text('Telefon ayarlarını aç'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('push_devices_empty')), findsOneWidget);
    });

    listMatrix('yükleniyor: iskelet, anahtar yok', (t, w, h, s, dark) async {
      final auth = _PushPrefsAuth();
      api.prefsGate = Completer<void>();
      await pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('push_panel_loading')), findsOneWidget);
      expect(find.byKey(_announceKey), findsNothing);
      api.prefsGate!.complete();
      await settleFor(t);
    });

    listMatrix('hata: anahtar ÇİZİLMEZ, Tekrar Dene', (t, w, h, s, dark) async {
      final auth = _PushPrefsAuth();
      api.prefsError = ApiException('Telefon bildirimi şu an kullanılamıyor.');
      await pumpSection(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Telefon bildirimi şu an kullanılamıyor.'), findsOneWidget);
      expect(find.byKey(_announceKey), findsNothing);
      api.prefsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(_announceKey), findsOneWidget);
    });
  });

  group('davranış', () {
    testWidgets('push_available false: "Yakında…" kalır, panel yok, push uçları çağrılmaz', (t) async {
      final auth = _PushPrefsAuth(pushAvailable: false);
      await service.start(gateway);
      await pumpSection(t, auth);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsOneWidget);
      expect(find.byType(PushPrefsPanel), findsNothing);
      expect(api.prefsCalls, 0);
      expect(api.listCalls, 0);
    });

    testWidgets('"Telefon bildirimi" AÇILINCA izin bağlamda istenir, cihaz kaydedilir, sonra PUT', (t) async {
      final auth = _PushPrefsAuth();
      gateway
        ..permission = PushPermission.notDetermined
        ..permissionAfterRequest = PushPermission.granted;
      api.prefs = const PushPreferences(available: true, announcements: false);
      await service.start(gateway);
      await pumpSection(t, auth);
      expect(gateway.requestCalls, 0, reason: 'ekran açılınca izin SORULMAZ');
      expect(switchValue(t, _announceKey), isFalse);

      await tapFinder(t, find.byKey(_announceKey));
      await settleFor(t);
      expect(gateway.requestCalls, 1);
      expect(api.registers, hasLength(1));
      expect(api.updates, <Map<String, Object>>[
        <String, Object>{'push_announcements': true},
      ]);
      expect(switchValue(t, _announceKey), isTrue);
      expect(find.widgetWithText(StatusChip, 'Bu cihaz'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('push_device_status')), findsNothing);
      expect(
        find.text('Bu cihaz telefon bildirimi için kaydedildi.'),
        findsOneWidget,
        reason: 'açma sonucu tercih kaydından sonra da ekranda kalır',
      );
    });

    testWidgets('anahtarla açarken sunucu push kapalıysa uyarı tercih kaydından sonra da kalır', (t) async {
      final auth = _PushPrefsAuth();
      api.prefs = const PushPreferences(available: false, announcements: false);
      await service.start(gateway);
      await pumpPanel(t, auth);
      await tapFinder(t, find.byKey(_announceKey));
      await settleFor(t);
      expect(api.updates.single, <String, Object>{'push_announcements': true});
      expect(find.text('Telefon bildirimi şu an kullanılamıyor.'), findsOneWidget);
      expect(api.registers, isEmpty);
    });

    testWidgets('izin REDDEDİLİRSE hesap tercihi yine kaydedilir; "izin verilmedi" + İzin ver görünür', (t) async {
      final auth = _PushPrefsAuth();
      gateway
        ..permission = PushPermission.notDetermined
        ..permissionAfterRequest = PushPermission.denied;
      api.prefs = const PushPreferences(available: true, announcements: false);
      await service.start(gateway);
      await pumpSection(t, auth);
      await tapFinder(t, find.byKey(_announceKey));
      await settleFor(t);
      expect(api.registers, isEmpty);
      expect(api.updates.single, <String, Object>{'push_announcements': true});
      expect(find.text(PushPrefsPanelState.noPermissionNote), findsOneWidget);
      expect(find.text('İzin ver'), findsOneWidget);
    });

    testWidgets('KALICI ret: "Telefon ayarlarından izin verin" + ayarları açar', (t) async {
      final auth = _PushPrefsAuth();
      gateway.permission = PushPermission.permanentlyDenied;
      await service.start(gateway);
      await pumpSection(t, auth);
      expect(find.text(PushPrefsPanelState.settingsNote), findsOneWidget);
      expect(
        find.textContaining('İzin verdiğinizde bu cihaz telefon bildirimi için kaydedilir.'),
        findsOneWidget,
        reason: 'bilgilendirilmiş rıza',
      );
      expect(find.text('İzin ver'), findsNothing);
      expect(find.text('Bu cihazda aç'), findsNothing, reason: 'sistem bir daha sormaz: yalnız ayarlar');
      await tapText(t, 'Telefon ayarlarını aç');
      await settleFor(t);
      expect(gateway.settingsOpened, isTrue);
      expect(gateway.requestCalls, 0);
      expect(await PushLocalStore().isEnabledHere(5), isTrue, reason: 'ayarlara gitmek açık istektir (rıza)');
    });

    testWidgets('ayarlardan izin verip dönünce kayıt bitene dek "kaydediliyor", sonra kayıtlı (eski durum kalmaz)', (t) async {
      final auth = _PushPrefsAuth();
      await pushConsent(5);
      gateway.permission = PushPermission.permanentlyDenied;
      await service.start(gateway);
      await pumpSection(t, auth);
      expect(find.text(PushPrefsPanelState.settingsNote), findsOneWidget);

      gateway.permission = PushPermission.granted; // kullanıcı ayarlardan izin verdi
      api.registerGate = Completer<void>();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text(PushPrefsPanelState.notRegisteredNote), findsNothing);
      expect(find.text(PushPrefsPanelState.registeringNote), findsOneWidget);
      expect(find.text('Bu cihazı kaydet'), findsNothing);
      expect(api.registers, hasLength(1), reason: 'kayıt sürüyor');

      api.registerGate!.complete();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('push_device_status')), findsNothing);
      expect(find.widgetWithText(StatusChip, 'Bu cihaz'), findsOneWidget);
    });

    testWidgets('önceki oturumun jetonu silinemiyorsa dürüst "temizlenemedi" mesajı (bağlantı suçlanmaz)', (t) async {
      final auth = _PushPrefsAuth();
      await PushLocalStore().setPendingCleanup(true);
      gateway.deleteTokenError = Exception('FCM hatası');
      await service.start(gateway);
      await pumpSection(t, auth);
      await tapText(t, 'Bu cihazda aç');
      await settleFor(t);
      expect(find.text(PushPrefsPanelState.cleanupPendingNote), findsOneWidget);
      expect(api.registers, isEmpty);
    });

    testWidgets('kapatmak yalnız PUT false gönderir: izin istenmez, cihaz silinmez', (t) async {
      final auth = await fullState();
      await pumpSection(t, auth);
      events.clear();
      await tapFinder(t, find.byKey(_announceKey));
      await settleFor(t);
      expect(api.updates, <Map<String, Object>>[
        <String, Object>{'push_announcements': false},
      ]);
      expect(events, isEmpty);
      expect(switchValue(t, _announceKey), isFalse);
    });

    testWidgets('kayıt BAŞARISIZ: anahtar eski değere döner ve hata görünür; sürerken kilitli', (t) async {
      final auth = await fullState();
      await pumpSection(t, auth);
      api
        ..updateGate = Completer<void>()
        ..updateError = ApiException('Tercih kaydedilemedi (deneme).');
      await tapFinder(t, find.byKey(_previewKey));
      expect(t.widget<SwitchListTile>(find.byKey(_previewKey)).onChanged, isNull, reason: 'kayıt sürerken kilitli');
      api.updateGate!.complete();
      await settleFor(t);
      expect(switchValue(t, _previewKey), isTrue, reason: 'eski değer');
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(api.updates.single, <String, Object>{'push_show_preview': false});
    });

    testWidgets('sessiz saatler: aç -> PUT; saat seçilince PUT "HH:MM"; başlangıç = bitiş ise hata, PUT yok', (t) async {
      final auth = _PushPrefsAuth();
      await service.start(gateway);
      await service.enableOnThisDevice(auth);
      TimeOfDay next = const TimeOfDay(hour: 22, minute: 30);
      final helps = <String>[];
      await pumpPanel(
        t,
        auth,
        pickTime: (context, initial, help) async {
          helps.add('$help ${initial.hour}:${initial.minute}');
          return next;
        },
      );
      expect(find.byKey(const ValueKey<String>('push_quiet_start')), findsNothing);
      await tapFinder(t, find.byKey(_quietKey));
      await settleFor(t);
      expect(api.updates.last, <String, Object>{'push_quiet_enabled': true});

      await tapFinder(t, find.byKey(const ValueKey<String>('push_quiet_start')));
      await settleFor(t);
      expect(helps.last, 'Sessiz saat başlangıcı 23:0');
      expect(api.updates.last, <String, Object>{'push_quiet_start': '22:30'});
      expect(find.text('Başlangıç: 22:30'), findsOneWidget);

      next = const TimeOfDay(hour: 22, minute: 30);
      final before = api.updates.length;
      await tapFinder(t, find.byKey(const ValueKey<String>('push_quiet_end')));
      await settleFor(t);
      expect(api.updates.length, before, reason: 'başlangıç ile bitiş aynı olamaz');
      expect(find.text('Başlangıç ve bitiş saati aynı olamaz.'), findsOneWidget);
    });

    testWidgets('gerçek saat seçici Türkçe (başlık, Vazgeç, 24 saat); vazgeçince PUT yok', (t) async {
      final auth = _PushPrefsAuth();
      api.prefs = const PushPreferences(available: true, quietEnabled: true);
      await service.start(gateway);
      await pumpPanel(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('push_quiet_end')));
      await settleFor(t);
      expect(find.text('Sessiz saat bitişi'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.text('Tamam'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);
      expect(api.updates, isEmpty);
    });

    testWidgets('BU cihazı kaldır: onay -> DELETE + deleteToken; "kaldırıldı" notu ve "Bu cihazda aç"', (t) async {
      final auth = await fullState();
      await pumpSection(t, auth);
      final thisRow = find.ancestor(
        of: find.widgetWithText(StatusChip, 'Bu cihaz'),
        matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('push_device_')),
      );
      await tapFinder(t, find.descendant(of: thisRow, matching: find.text('Kaldır')));
      await settleFor(t);
      expect(find.text('Cihaz kaldırılsın mı?'), findsOneWidget);
      expect(find.textContaining('acil duyurular dahil'), findsOneWidget);
      events.clear();
      await t.tap(find.widgetWithText(ElevatedButton, 'Kaldır'));
      await settleFor(t);
      expect(events, <String>['delete:tok', 'deleteToken']);
      expect(find.text('Cihaz kaldırıldı.'), findsOneWidget);
      expect(find.text(PushPrefsPanelState.disabledHereNote), findsOneWidget);
      expect(find.text('Bu cihazda aç'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Bu cihaz'), findsNothing);
    });

    testWidgets('kaldırmada vazgeçilirse istek gitmez', (t) async {
      final auth = await fullState();
      await pumpSection(t, auth);
      await tapFinder(t, find.text('Kaldır').last);
      await settleFor(t);
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);
      expect(api.deletes, isEmpty);
    });

    testWidgets('test bildirimi: başarı notu; PUSH_UNAVAILABLE -> "Telefon bildirimi şu an kullanılamıyor."', (t) async {
      final auth = await fullState();
      api.testResult = const PushTestResult(sent: 2, failed: 0);
      await pumpSection(t, auth);
      await tapText(t, 'Test bildirimi gönder');
      await settleFor(t);
      expect(api.testCalls, 1);
      expect(find.textContaining('Test bildirimi gönderildi (2 cihaz).'), findsOneWidget);

      api.testError = ApiException(
        'Telefon bildirimi şu an kullanılamıyor.',
        statusCode: 503,
        code: 'PUSH_UNAVAILABLE',
      );
      await tapText(t, 'Test bildirimi gönder');
      await settleFor(t);
      expect(find.text('Telefon bildirimi şu an kullanılamıyor.'), findsOneWidget);
    });

    testWidgets('hiç cihaz yokken: dürüst boş durum ve test düğmesi pasif', (t) async {
      final auth = _PushPrefsAuth();
      gateway.permission = PushPermission.notDetermined;
      await service.start(gateway);
      await pumpSection(t, auth);
      expect(find.text(PushPrefsPanelState.emptyDevicesNote), findsOneWidget);
      final button = t.widget<OutlinedButton>(
        find.ancestor(of: find.text('Test bildirimi gönder'), matching: find.byWidgetPredicate((w) => w is OutlinedButton)),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('desteklenmeyen cihaz (masaüstü): bilgi notu; hesap tercihleri yine yönetilir, izin istenmez', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final auth = _PushPrefsAuth();
        api.prefs = const PushPreferences(available: true, announcements: false);
        await pumpSection(t, auth);
        expect(find.text(PushPrefsPanelState.unsupportedNote), findsOneWidget);
        await tapFinder(t, find.byKey(_announceKey));
        await settleFor(t);
        expect(api.updates.single, <String, Object>{'push_announcements': true});
        expect(gateway.requestCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('başlatma sürerken "hazırlanıyor"; bitince panel kendiliğinden tazelenir', (t) async {
      final auth = _PushPrefsAuth();
      service.markStarting();
      await pumpSection(t, auth);
      expect(find.text(PushPrefsPanelState.preparingNote), findsOneWidget);
      expect(find.byType(ListSkeleton), findsNothing);
      await service.start(gateway);
      await settleFor(t);
      expect(find.text(PushPrefsPanelState.preparingNote), findsNothing);
      expect(find.text(PushPrefsPanelState.disabledHereNote), findsOneWidget);
    });

    testWidgets('Firebase başlatılamadı (yapılandırma yok): "bu sürümde telefon bildirimi yok"', (t) async {
      final auth = _PushPrefsAuth();
      service.markStarting();
      await pumpSection(t, auth);
      service.markStartFailed();
      await settleFor(t);
      expect(find.text(PushPrefsPanelState.notConfiguredNote), findsOneWidget);
      expect(find.text(PushPrefsPanelState.preparingNote), findsNothing);
    });

    testWidgets('hesap değişince panel yeniden yüklenir; eski hesabın cihazları görünmez', (t) async {
      final first = await fullState();
      final second = _PushPrefsAuth();
      final host = ValueNotifier<AuthService>(first);
      addTearDown(host.dispose);
      await pumpList(
        t,
        ValueListenableBuilder<AuthService>(
          valueListenable: host,
          builder: (context, auth, _) => PushPrefsPanel(authService: auth, pushService: service),
        ),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(find.text('iPhone / iPad'), findsOneWidget);
      api
        ..prefsGate = Completer<void>()
        ..devices = <PushDevice>[];
      host.value = second;
      await t.pump();
      expect(find.text('iPhone / iPad'), findsNothing, reason: 'eski hesabın cihazı gösterilmez');
      expect(find.byKey(const ValueKey<String>('push_panel_loading')), findsOneWidget);
      api.prefsGate!.complete();
      await settleFor(t);
      expect(find.text(PushPrefsPanelState.emptyDevicesNote), findsOneWidget);
    });
  });
}
