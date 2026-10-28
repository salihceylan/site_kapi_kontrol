// Geri bildirim: ana kabuk (HomePage) entegrasyonu (P1-14, karar K11). Giriş iki yerde: çekmece ("Yardım ve Destek"in altında "Geri bildirim") ve sağ
// üstteki dişliden açılan Ayarlar paneli ("Geri bildirim gönder"). Form açılırken EKRAN BAĞLAMI (ekran adı + rota + site) otomatik eklenir ve ekran
// değişince değişir; gönderilen istek bu bağlamı taşır. "Gelen geri bildirimler" yalnız süper kullanıcıda ve site yöneticisinde görünür (sunucu ayrıca 403).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/dialogs/feedback_dialog.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/feedback_inbox_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../support/menu_nav.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'people_fixtures.dart';

class _HomeAuth extends PeopleFakeAuth {
  _HomeAuth({super.role});

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

http.Response _json(int status, Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// Sahte sunucu: geri bildirim uçları ve (Talepler ekranı için) boş iş takibi listeleri; tüm istekler kaydedilir.
class _Server {
  final List<http.Request> requests = <http.Request>[];

  http.Response handle(http.Request request) {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'POST' && path == '/app/feedback') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json(201, <String, dynamic>{
        'feedback': <String, dynamic>{
          'id': 1,
          'site_code': body['site_code'],
          'user_code': 5,
          'user_name': 'Ben',
          'role': 'site_manager',
          'screen_name': body['screen_name'],
          'screen_route': body['screen_route'],
          'message': body['message'],
          'created_at': '2026-10-28T10:00:00.000Z',
          'attachments': <Object>[],
        },
      });
    }
    if (path.endsWith('/feedback')) {
      return _json(200, <String, dynamic>{'items': <Object>[], 'next_cursor': null});
    }
    if (path.startsWith('/manager/')) {
      return _json(200, <String, dynamic>{'items': <Object>[], 'next_before_id': null, 'counts': <String, dynamic>{}});
    }
    return _json(200, <String, dynamic>{'items': <Object>[], 'next_before_id': null, 'unread_updates': 0});
  }

  List<http.Request> get feedbackRequests => requests.where((r) => r.url.path.contains('feedback')).toList();
}

late _Server _server;

MySiteModules _my(String role, {bool work = true, int code = 11, String name = 'Gül Sitesi'}) => MySiteModules(
  siteCode: code,
  siteName: name,
  role: role,
  modules: <String, bool>{'door_control': true, 'work_tracking': work},
  doorAccess: !(role == 'staff' || role == 'board_member'),
);

Future<ModuleAccess> _access(List<MySiteModules> Function() sites, {bool superUser = false}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
    isSuperUser: () => superUser,
  );
  await access.refresh();
  addTearDown(access.dispose);
  return access;
}

AnnouncementNotifier _quietNotifier() => AnnouncementNotifier(
  fetchSummary: () async => throw StateError('yok'),
  fetchInbox: () async => throw StateError('yok'),
  fetchAnnouncement: (id) async => throw StateError('yok'),
  isEligible: () => false,
);

Future<void> _pumpHome(WidgetTester t, _HomeAuth auth, {ModuleAccess? access}) async {
  t.view.physicalSize = const Size(400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier();
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Finder _k(String key) => find.byKey(ValueKey<String>(key));

Future<void> _tapDrawerFeedback(WidgetTester t) async {
  await openMenuDrawer(t);
  final tile = _k('yan_menu_geri_bildirim');
  await t.ensureVisible(tile);
  await t.pump();
  await t.tap(tile);
  await settleFor(t, 100);
  await settleFor(t, 300);
}

void main() {
  setUp(() {
    _server = _Server();
    FeedbackService.debugApiFactory = (auth) => FeedbackApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
    WorkTrackingService.debugApiFactory = (auth) => WorkTrackingApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() {
    FeedbackService.debugApiFactory = null;
    WorkTrackingService.debugApiFactory = null;
  });

  group('giriş noktaları (her ekrandan erişim)', () {
    testWidgets('çekmece: "Geri bildirim", "Yardım ve Destek"in HEMEN altında ve "Çıkış Yap"ın üstünde', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await openMenuDrawer(t);
      final help = t.getTopLeft(_k('yan_menu_yardim')).dy;
      final feedback = t.getTopLeft(_k('yan_menu_geri_bildirim')).dy;
      final logout = t.getTopLeft(_k('yan_menu_cikis')).dy;
      expect(feedback, greaterThan(help));
      expect(feedback, lessThan(logout));
      expect(find.descendant(of: find.byType(YanMenu), matching: find.text('Geri bildirim')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Ayarlar paneli (sağ üst dişli): "Geri bildirim gönder" herkeste; "Gelen geri bildirimler" yalnız yönetici ve süper kullanıcıda', (t) async {
      Future<(bool, bool)> panelEntries(_HomeAuth auth, ModuleAccess access) async {
        await _pumpHome(t, auth, access: access);
        await openSettingsPanel(t);
        final send = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Geri bildirim gönder'));
        final inbox = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Gelen geri bildirimler'));
        final result = (send.evaluate().isNotEmpty, inbox.evaluate().isNotEmpty);
        await _disposeHome(t);
        return result;
      }

      expect(
        await panelEntries(_HomeAuth(), await _access(() => <MySiteModules>[_my('manager')])),
        (true, true),
        reason: 'site yöneticisi',
      );
      expect(
        await panelEntries(_HomeAuth(role: UserRole.superUser), await _access(() => <MySiteModules>[], superUser: true)),
        (true, true),
        reason: 'süper kullanıcı',
      );
      expect(
        await panelEntries(_HomeAuth(role: UserRole.apartmentOwner), await _access(() => <MySiteModules>[_my('resident')])),
        (true, false),
        reason: 'sakin',
      );
      expect(
        await panelEntries(_HomeAuth(role: UserRole.apartmentOwner), await _access(() => <MySiteModules>[_my('board_member')])),
        (true, false),
        reason: 'kurul üyesi',
      );
    });
  });

  group('ekran bağlamı otomatik eklenir', () {
    testWidgets('Panel: ekran adı "Panel", rota "menu/dashboard", site "Gül Sitesi"; gönderilen istek bu bağlamı taşır', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _tapDrawerFeedback(t);
      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(t.widget<Text>(_k('feedback_context_name')).data, 'Panel');
      expect(t.widget<Text>(_k('feedback_context_route')).data, 'menu/dashboard');
      expect(t.widget<Text>(_k('feedback_context_site')).data, 'Site: Gül Sitesi');
      await t.enterText(_k('feedback_message'), 'Panel çok iyi');
      await t.pump();
      await t.tap(_k('feedback_send'));
      await settleFor(t, 100);
      await settleFor(t, 300);
      final sent = _server.feedbackRequests.single;
      expect(sent.method, 'POST');
      expect(sent.url.path, '/app/feedback');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['screen_name'], 'Panel');
      expect(body['screen_route'], 'menu/dashboard');
      expect(body['site_code'], 11);
      expect(body['message'], 'Panel çok iyi');
      expect(body['platform'], isNotNull);
      expect(find.byType(FeedbackDialog), findsNothing);
      expect(find.text('Geri bildiriminiz gönderildi. Teşekkür ederiz.'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('ekran değişince bağlam değişir: "Talepler" ekranındayken ad "Talepler", rota "menu/talepler"', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await tapMenuEntry(t, 'Talepler');
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Talepler')), findsOneWidget);
      await _tapDrawerFeedback(t);
      expect(t.widget<Text>(_k('feedback_context_name')).data, 'Talepler');
      expect(t.widget<Text>(_k('feedback_context_route')).data, 'menu/talepler');
      await _disposeHome(t);
    });

    testWidgets('Ayarlar panelinden de açılır; çok siteli kullanıcıda "Tüm siteler" iken site bağlamı YOK', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager'), _my('manager', code: 12, name: 'Ay Sitesi')]);
      await _pumpHome(t, auth, access: access);
      await openSettingsPanel(t);
      final entry = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Geri bildirim gönder'));
      await t.ensureVisible(entry);
      await t.pump();
      await t.tap(entry);
      await settleFor(t, 100);
      await settleFor(t, 300);
      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(t.widget<Text>(_k('feedback_context_name')).data, 'Panel');
      expect(_k('feedback_context_site'), findsNothing, reason: 'iki site var ve biri seçili değil');
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: site bağlamı yok', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _tapDrawerFeedback(t);
      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(_k('feedback_context_site'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('gelen geri bildirimler (yönetici / sahip)', () {
    testWidgets('site yöneticisi: KENDİ sitesinin ucu (/manager/sites/11/feedback)', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await openSettingsPanel(t);
      final entry = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Gelen geri bildirimler'));
      await t.ensureVisible(entry);
      await t.pump();
      await t.tap(entry);
      await settleFor(t, 100);
      await settleFor(t, 300);
      expect(find.byType(FeedbackInboxPage), findsOneWidget);
      expect(_server.feedbackRequests.map((r) => r.url.path), <String>['/manager/sites/11/feedback']);
      expect(find.text('Henüz geri bildirim yok.'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: tüm kayıtlar (/admin/feedback)', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await openSettingsPanel(t);
      final entry = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Gelen geri bildirimler'));
      await t.ensureVisible(entry);
      await t.pump();
      await t.tap(entry);
      await settleFor(t, 100);
      await settleFor(t, 300);
      expect(find.byType(FeedbackInboxPage), findsOneWidget);
      expect(_server.feedbackRequests.map((r) => r.url.path), <String>['/admin/feedback']);
      await _disposeHome(t);
    });
  });
}
