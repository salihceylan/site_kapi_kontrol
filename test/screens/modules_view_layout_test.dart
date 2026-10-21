// Platform modül sistemi Faz 1: "Modüller" ekranı (ModulesView) + "Ek roller" bölümü.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata /
// dolu durumlar taşmaz. Kural 7: işlemden sonra veri yeniden çekilir, yenile düğmesi ve
// `reload()` (aşağı çekip yenileme) çalışır. Geçiş Kontrol KAPATILIRKEN önce onay penceresi çıkar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/staff_role_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'modules_fixtures.dart';

const String _doorWarning =
    'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?';

Future<GlobalKey<ModulesViewState>> _pump(
  WidgetTester t,
  ModulesFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onChanged,
}) async {
  final key = GlobalKey<ModulesViewState>();
  await pumpList(
    t,
    ModulesView(key: key, authService: auth, onModulesChanged: onChanged),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  // Ek roller bölümü ([StaffRolesSection]) kendi verisini siteler gelip bölüm kurulunca çeker: bir kare daha.
  await t.pump();
  await t.pump();
  return key;
}

ModulesFakeAuth _fullAuth() => ModulesFakeAuth(
  roles: <int, List<StaffRoleRecord>>{
    11: <StaffRoleRecord>[
      mdRole(41, 'Selin Aydın', 'selin.aydin.cok.uzun.bir.eposta@ornek-alan-adi.com.tr'),
      mdRole(42, 'Kemal Bireysel Çok Uzun Bir Soyadı Olan Görevli', 'kemal@ornek.com', role: 'STAFF'),
    ],
  },
);

/// Site yöneticisi oturumu: modüller `can_toggle: false`, bekleyen talepler [pendingDoor] ile.
ModulesFakeAuth _managerAuth({
  bool door = false,
  bool pendingDoor = false,
  List<ModuleRequest>? requests,
}) {
  final auth = ModulesFakeAuth(
    fixtureRole: UserRole.siteManager,
    states: <int, SiteModulesState>{
      11: mdState(
        11,
        'Gül Sitesi',
        door: door,
        superView: false,
        requests: <String, String>{if (pendingDoor) 'door_control': 'pending'},
      ),
      12: mdState(12, 'Mavi Park', superView: false),
    },
  );
  auth.siteRequests[11] =
      requests ??
      <ModuleRequest>[
        if (pendingDoor)
          mdRequest(31, moduleCode: 'door_control', moduleName: 'Geçiş Kontrol (SmartKeyPass)'),
      ];
  return auth;
}

/// Modül kartı başlığını içeren kartın düğmesi (kartlar arasında karışmasın).
Finder _inDialog(Finder f) => find.descendant(of: find.byType(AppDialog), matching: f);

void main() {
  group('site yöneticisi görünümü: anahtar YOK, talep akışı (Faz 1.1)', () {
    listMatrix('talepli görünüm: durum çipleri, düğmeler, Modül Taleplerim', (t, w, h, s, dark) async {
      final auth = _managerAuth(
        door: false,
        pendingDoor: true,
        requests: <ModuleRequest>[
          mdRequest(31, moduleCode: 'door_control', moduleName: 'Geçiş Kontrol (SmartKeyPass)'),
          mdRequest(
            30,
            status: 'rejected',
            decidedBy: 'Çok Uzun Adlı Süper Yönetici Hesabı Sahibi',
            decisionNote: 'Paket kapsamında değil; lütfen satış temsilcinizle görüşün.',
          ),
          mdRequest(29, status: 'approved', decidedBy: 'Süper Yönetici', note: null),
        ],
      );
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);

      expect(doorModuleSwitch, findsNothing, reason: 'site yöneticisinde anahtar yok');
      expect(find.widgetWithText(StatusChip, 'Talep gönderildi'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(5));
      expect(find.widgetWithText(StatusChip, 'Her sitede açık'), findsNWidgets(2));
      expect(find.text('Talebi Geri Çek'), findsOneWidget);
      expect(find.text('Modül Talep Et'), findsNothing);
      expect(find.text('Modül Taleplerim'), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsNWidgets(3));
      expect(find.widgetWithText(StatusChip, 'Bekliyor'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Reddedildi'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Onaylandı'), findsOneWidget);
      expect(find.textContaining('Gerekçe: Paket kapsamında değil'), findsOneWidget);
    });

    listMatrix('talepsiz görünüm: "Tanımlı değil" + Modül Talep Et; boş talep listesi', (t, w, h, s, dark) async {
      await _pump(t, _managerAuth(door: false), width: w, height: h, scale: s, dark: dark);
      expect(doorModuleSwitch, findsNothing);
      expect(find.widgetWithText(StatusChip, 'Tanımlı değil'), findsOneWidget);
      expect(find.text('Modül Talep Et'), findsOneWidget);
      expect(find.text('Talebi Geri Çek'), findsNothing);
      expect(find.text('Henüz modül talebiniz yok.'), findsOneWidget);
    });

    testWidgets('Geçiş Kontrol tanımlıysa çip "Tanımlı"; kapatma/talep düğmesi yok', (t) async {
      await _pump(t, _managerAuth(door: true));
      expect(find.widgetWithText(StatusChip, 'Tanımlı'), findsOneWidget);
      expect(doorModuleSwitch, findsNothing);
      expect(find.text('Modül Talep Et'), findsNothing);
      expect(find.text('Talebi Geri Çek'), findsNothing);
      expect(find.widgetWithText(StatusChip, 'Açık'), findsNothing,
          reason: 'yönetici "Açık/Kapalı" değil "Tanımlı" görür');
    });

    testWidgets('eski sunucu (can_toggle yok, toggleable true) olsa da yönetici anahtar görmez; talepler istenmez süper kullanıcıda', (t) async {
      // mdState superView:true -> can_toggle: true (yönetici oturumunda bile anahtar çıkmamalı).
      final auth = ModulesFakeAuth(fixtureRole: UserRole.siteManager);
      await _pump(t, auth);
      expect(doorModuleSwitch, findsNothing);

      final superAuth = ModulesFakeAuth();
      await _pump(t, superAuth);
      expect(doorModuleSwitch, findsOneWidget);
      expect(superAuth.listRequestCalls, isEmpty, reason: 'süper kullanıcı için talep listesi çekilmez');
      expect(find.text('Modül Taleplerim'), findsNothing);
      expect(find.text('Modül Talep Et'), findsNothing);
    });

    testWidgets('süper kullanıcı: bekleyen talebi olan modülde "Bekleyen talep var" çipi; anahtar korunur', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{
          11: mdState(11, 'Gül Sitesi', door: false, requests: <String, String>{'door_control': 'pending'}),
        },
      );
      await _pump(t, auth);
      expect(find.widgetWithText(StatusChip, 'Kapalı'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Bekleyen talep var'), findsOneWidget);
      expect(doorModuleSwitch, findsOneWidget);
    });

    testWidgets('enabled, request_status\'tan ÖNCELİKLİDİR: açık modülde "Talep gönderildi" / düğme gösterilmez', (t) async {
      final auth = ModulesFakeAuth(
        fixtureRole: UserRole.siteManager,
        states: <int, SiteModulesState>{
          // Süper kullanıcı doğrudan açtı; bekleyen talep sunucuda henüz kapanmadı.
          11: mdState(
            11,
            'Gül Sitesi',
            door: true,
            superView: false,
            requests: <String, String>{'door_control': 'pending'},
          ),
        },
      );
      await _pump(t, auth);
      expect(find.widgetWithText(StatusChip, 'Tanımlı'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Talep gönderildi'), findsNothing);
      expect(find.text('Talebi Geri Çek'), findsNothing);
      expect(find.text('Modül Talep Et'), findsNothing);
    });

    testWidgets('talep düğmesi yalnız toggleable modülde: yakında / çekirdek modüllerde hiç çıkmaz (tek düğme)', (t) async {
      await _pump(t, _managerAuth(door: false));
      expect(find.text('Modül Talep Et'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(5));
    });

    testWidgets('süper kullanıcı kapalı modülde KENDİNE talep açmaz: düğme yok, anahtar var', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      );
      await _pump(t, auth);
      expect(find.text('Modül Talep Et'), findsNothing);
      expect(find.text('Talebi Geri Çek'), findsNothing);
      expect(find.widgetWithText(StatusChip, 'Kapalı'), findsOneWidget);
      expect(doorModuleSwitch, findsOneWidget);
    });

    testWidgets('Modül Talep Et: not alanlı pencere -> talep gider (not kırpılır) -> çip ve liste güncellenir', (t) async {
      final auth = _managerAuth(door: false);
      await _pump(t, auth);
      final readsBefore = auth.getModulesCalls.length;

      await tapText(t, 'Modül Talep Et');
      expect(find.byType(AppDialog), findsOneWidget);
      expect(_inDialog(find.text('Modül Talep Et')), findsOneWidget);
      expect(_inDialog(find.byType(TextField)), findsOneWidget);
      expect(find.text('Not (isteğe bağlı)'), findsOneWidget);

      await t.enterText(find.byType(TextField), '  Kapı sistemi için gerekli  ');
      await tapText(t, 'Talep Gönder');
      await settleFor(t);

      expect(auth.createCalls, hasLength(1));
      expect(auth.createCalls.single.site, 11);
      expect(auth.createCalls.single.code, 'door_control');
      expect(auth.createCalls.single.note, '  Kapı sistemi için gerekli  ',
          reason: 'kırpma AuthApi katmanında yapılır; istemci notu olduğu gibi iletir');
      expect(find.byType(AppDialog), findsNothing);
      expect(find.text('Modül talebiniz gönderildi.'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Talep gönderildi'), findsOneWidget);
      expect(find.text('Talebi Geri Çek'), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsOneWidget);
      expect(auth.getModulesCalls.length, greaterThan(readsBefore),
          reason: 'işlem sonrası modül durumu otomatik yeniden çekilir');
      expect(auth.listRequestCalls.length, greaterThan(1));
    });

    testWidgets('notsuz talep de gider; İptal talep göndermez', (t) async {
      final auth = _managerAuth(door: false);
      await _pump(t, auth);
      await tapText(t, 'Modül Talep Et');
      await tapText(t, 'İptal');
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.createCalls, isEmpty);

      await tapText(t, 'Modül Talep Et');
      await tapText(t, 'Talep Gönder');
      await settleFor(t);
      expect(auth.createCalls.single.note, '');
    });

    testWidgets('sunucu reddi (MODULE_REQUEST_PENDING): pencerede Türkçe hata, açık kalır; kapatınca durum yeniden okunur', (t) async {
      final auth = _managerAuth(door: false)
        ..createError = ApiException(
          'Bu modül için bekleyen bir talebiniz var.',
          statusCode: 409,
          code: 'MODULE_REQUEST_PENDING',
        );
      await _pump(t, auth);
      final readsBefore = auth.getModulesCalls.length;

      await tapText(t, 'Modül Talep Et');
      await tapText(t, 'Talep Gönder');
      await settleFor(t);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu modül için bekleyen bir talebiniz var.'), findsOneWidget);

      await tapText(t, 'İptal');
      await settleFor(t);
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.getModulesCalls.length, greaterThan(readsBefore));
    });

    testWidgets('Talebi Geri Çek: onay -> istek -> çip "Tanımlı değil", talep "Geri çekildi"; Vazgeç istek yapmaz', (t) async {
      final auth = _managerAuth(door: false, pendingDoor: true);
      await _pump(t, auth);

      await tapText(t, 'Talebi Geri Çek');
      expect(find.text('Talep Geri Çekilsin mi?'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(auth.cancelCalls, isEmpty);

      await tapText(t, 'Talebi Geri Çek');
      await tapText(t, 'Geri Çek');
      await settleFor(t);
      expect(auth.cancelCalls.single, (site: 11, id: 31));
      expect(find.text('Talep geri çekildi.'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Tanımlı değil'), findsOneWidget);
      expect(find.text('Modül Talep Et'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Geri çekildi'), findsOneWidget);
    });

    testWidgets('geri çekme hatası (REQUEST_NOT_PENDING): mesaj gösterilir, durum yeniden okunur', (t) async {
      final auth = _managerAuth(door: false, pendingDoor: true)
        ..cancelError = ApiException(
          'Bu talep artık bekleyen durumda değil.',
          statusCode: 409,
          code: 'REQUEST_NOT_PENDING',
        );
      await _pump(t, auth);
      final readsBefore = auth.getModulesCalls.length;
      await tapText(t, 'Talebi Geri Çek');
      await tapText(t, 'Geri Çek');
      await settleFor(t);
      expect(find.text('Bu talep artık bekleyen durumda değil.'), findsOneWidget);
      expect(auth.getModulesCalls.length, greaterThan(readsBefore));
    });

    testWidgets('liste bayatsa (talep listede yok) geri çekilmez: "Talep bulunamadı." ve yeniden okuma', (t) async {
      final auth = _managerAuth(door: false, pendingDoor: true, requests: <ModuleRequest>[]);
      await _pump(t, auth);
      await tapText(t, 'Talebi Geri Çek');
      await tapText(t, 'Geri Çek');
      await settleFor(t);
      expect(auth.cancelCalls, isEmpty);
      expect(find.text('Talep bulunamadı.'), findsOneWidget);
    });

    testWidgets('talep listesi hatası: InlineNotice + Tekrar Dene; modül kartları etkilenmez', (t) async {
      final auth = _managerAuth(door: false)
        ..requestsError = ApiException('Modül talepleri yüklenemedi (500).');
      await _pump(t, auth);
      expect(find.text('Modül talepleri yüklenemedi (500).'), findsOneWidget);
      expect(find.text('Modül Talep Et'), findsOneWidget);
      expect(find.text('Henüz modül talebiniz yok.'), findsNothing);

      auth.requestsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Modül talepleri yüklenemedi (500).'), findsNothing);
      expect(find.text('Henüz modül talebiniz yok.'), findsOneWidget);
    });

    testWidgets('yalnız son 10 talep listelenir', (t) async {
      final auth = _managerAuth(
        door: false,
        requests: <ModuleRequest>[
          for (var i = 20; i > 0; i--) mdRequest(i, status: 'cancelled'),
        ],
      );
      await _pump(t, auth);
      expect(find.byType(ModuleRequestCard), findsNWidgets(10));
    });

    testWidgets('yönetici açıklama metni ve süper kullanıcı açıklama metni', (t) async {
      await _pump(t, _managerAuth());
      expect(find.textContaining('talep gönderebilirsiniz'), findsOneWidget);
      await _pump(t, ModulesFakeAuth());
      expect(find.textContaining('açıp kapatabilirsiniz'), findsOneWidget);
    });
  });

  group('taşma matrisi', () {
    listMatrix('dolu görünüm (8 modül + 2 ek rol)', (t, w, h, s, dark) async {
      await _pump(t, _fullAuth(), width: w, height: h, scale: s, dark: dark);

      expect(find.text('Modüller'), findsOneWidget);
      expect(find.text('Site Modülleri'), findsOneWidget);
      expect(find.text('Geçiş Kontrol (SmartKeyPass)'), findsOneWidget);
      expect(doorModuleSwitch, findsOneWidget,
          reason: 'yalnız açılıp kapatılabilen modülde anahtar var');
      expect(find.widgetWithText(StatusChip, 'Açık'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(5));
      expect(find.widgetWithText(StatusChip, 'Her sitede açık'), findsNWidgets(2));
      // Ek roller 058'den beri Kişiler > Kadro sekmesinde: Modüller'de yalnız yönlendirme kartı var.
      expect(find.text('Yönetim Kadrosu'), findsOneWidget);
      expect(find.byType(StaffRoleCard), findsNothing);
      expect(find.byTooltip('Yenile'), findsOneWidget);
    });

    listMatrix('Geçiş Kontrol kapalı: çip "Kapalı"', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      );
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.widgetWithText(StatusChip, 'Kapalı'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Açık'), findsNothing);
      expect(t.widget<Switch>(doorModuleSwitch).value, isFalse);
    });

    listMatrix('boş durumlar: onaylı site yok', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth(
        sites: <SiteRecord>[mdSite(11, 'Onay Bekleyen', approval: 'pending')],
      );
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Yönetilecek onaylı site bulunamadı.'), findsOneWidget);
      expect(auth.getModulesCalls, isEmpty);
    });

    listMatrix('yönetim kadrosu yönlendirme kartı', (t, w, h, s, dark) async {
      await _pump(t, ModulesFakeAuth(), width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('team_redirect_card')), findsOneWidget);
      expect(find.textContaining('Görev ver'), findsOneWidget);
    });

    listMatrix('yükleniyor: siteler', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()..sitesGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(doorModuleSwitch, findsNothing);
    });

    listMatrix('yükleniyor: modüller (site seçici görünür)', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth()
        ..modulesGate = Completer<void>()
        ..rolesGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site Seçin'), findsOneWidget);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(doorModuleSwitch, findsNothing);
    });

    listMatrix('hata: siteler yüklenemedi (InlineNotice + Tekrar Dene)', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth()
        ..listSitesError = ApiException('Sunucu geçici olarak yanıt vermiyor (503). Lütfen biraz sonra tekrar deneyin.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.textContaining('Sunucu geçici olarak yanıt vermiyor'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });

    listMatrix('hata: modüller yüklenemedi', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()
        ..modulesError = ApiException('Bu site üzerinde yönetim yetkiniz bulunmuyor.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu site üzerinde yönetim yetkiniz bulunmuyor.'), findsOneWidget);
      expect(doorModuleSwitch, findsNothing);
    });
  });

  group('Geçiş Kontrol kapatma onayı', () {
    testWidgets('kapatırken önce onay penceresi (uyarı metni sunucudakiyle aynı); Vazgeç çağrı yapmaz', (t) async {
      final auth = _fullAuth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));

      await tapFinder(t, doorModuleSwitch);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Geçiş Kontrol Kapatılsın mı?'), findsOneWidget);
      expect(find.text(_doorWarning), findsOneWidget);

      await tapText(t, 'Vazgeç');
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.setCalls, isEmpty);
      expect(changed, isEmpty);
      expect(t.widget<Switch>(doorModuleSwitch).value, isTrue);
    });

    testWidgets('Kapat -> confirm:true ile istek, çip "Kapalı", otomatik yeniden çekme, onModulesChanged', (t) async {
      final auth = _fullAuth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      final readsBefore = auth.getModulesCalls.length;

      await tapFinder(t, doorModuleSwitch);
      await tapText(t, 'Kapat');
      await settleFor(t);

      expect(auth.setCalls, hasLength(1));
      expect(auth.setCalls.single.site, 11);
      expect(auth.setCalls.single.code, 'door_control');
      expect(auth.setCalls.single.enabled, isFalse);
      expect(auth.setCalls.single.confirm, isTrue);
      expect(find.widgetWithText(StatusChip, 'Kapalı'), findsOneWidget);
      expect(t.widget<Switch>(doorModuleSwitch).value, isFalse);
      expect(find.text('Geçiş Kontrol (SmartKeyPass) kapatıldı.'), findsOneWidget);
      expect(changed, hasLength(1));
      expect(auth.getModulesCalls.length, readsBefore + 1,
          reason: 'işlem sonrası modül durumu otomatik yeniden çekilir');
    });

    testWidgets('açarken onay GEREKMEZ (confirm:false)', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      );
      await _pump(t, auth);

      await tapFinder(t, doorModuleSwitch);
      await settleFor(t);

      expect(find.byType(AppDialog), findsNothing);
      expect(auth.setCalls.single.enabled, isTrue);
      expect(auth.setCalls.single.confirm, isFalse);
      expect(find.widgetWithText(StatusChip, 'Açık'), findsOneWidget);
      expect(find.text('Geçiş Kontrol (SmartKeyPass) açıldı.'), findsOneWidget);
    });

    testWidgets('sunucu hatası: Türkçe mesaj gösterilir, anahtar eski değerde kalır', (t) async {
      final auth = _fullAuth()
        ..setError = ApiException('Bu modül kapatılamaz.', statusCode: 400, code: 'MODULE_NOT_TOGGLEABLE');
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));

      await tapFinder(t, doorModuleSwitch);
      await tapText(t, 'Kapat');
      await settleFor(t);

      expect(find.text('Bu modül kapatılamaz.'), findsOneWidget);
      expect(t.widget<Switch>(doorModuleSwitch).value, isTrue);
      expect(changed, hasLength(1),
          reason: 'hata/zaman aşımı olsa da menü süzgeci sunucudan yeniden okunur');
    });

    testWidgets('sunucu onay isterse (409 MODULE_CONFIRM_REQUIRED) sunucu metniyle onay sorulur ve onayda yeniden denenir', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      )..demandConfirm = true;
      await _pump(t, auth);

      await tapFinder(t, doorModuleSwitch); // açmaya çalış: ilk istek confirm:false
      expect(auth.setCalls.single.confirm, isFalse);
      expect(find.text('Onay Gerekli'), findsOneWidget);
      expect(find.text(_doorWarning), findsOneWidget);

      await tapText(t, 'Onayla');
      await settleFor(t);
      expect(auth.setCalls, hasLength(2));
      expect(auth.setCalls.last.confirm, isTrue);
      expect(find.widgetWithText(StatusChip, 'Açık'), findsOneWidget);
    });
  });

  group('Site seçici ve yenileme', () {
    testWidgets('yalnız onaylı siteler listelenir; ilk site seçilir ve verisi çekilir', (t) async {
      final auth = ModulesFakeAuth(
        sites: <SiteRecord>[
          mdSite(11, 'Gül Sitesi'),
          mdSite(13, 'Bekleyen', approval: 'pending'),
          mdSite(12, 'Mavi Park'),
        ],
      );
      await _pump(t, auth);
      expect(auth.getModulesCalls, <int>[11]);
      expect(auth.listRolesCalls, isEmpty, reason: 'ek roller artık Kadro sekmesinde');

      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      expect(find.text('Gül Sitesi (11)'), findsWidgets);
      expect(find.text('Mavi Park (12)'), findsOneWidget);
      expect(find.text('Bekleyen (13)'), findsNothing);
    });

    testWidgets('başka site seçilince o sitenin modülleri çekilir', (t) async {
      final auth = _fullAuth();
      await _pump(t, auth);

      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park (12)'));
      await settleFor(t);

      expect(auth.getModulesCalls.last, 12);
    });

    testWidgets('yenile düğmesi ve reload() siteleri, modülleri ve rolleri yeniden çeker', (t) async {
      final auth = _fullAuth();
      final key = await _pump(t, auth);
      expect(auth.listSitesCalls, 1);
      expect(auth.getModulesCalls, hasLength(1));

      await tapFinder(t, find.byTooltip('Yenile'));
      expect(auth.listSitesCalls, 2);
      expect(auth.getModulesCalls, hasLength(2));
      expect(auth.listRolesCalls, isEmpty);

      await key.currentState!.reload(); // RefreshIndicator'ın çağırdığı yol
      await settleFor(t);
      expect(auth.listSitesCalls, 3);
      expect(auth.getModulesCalls, hasLength(3));
    });

    testWidgets('hata sonrası Tekrar Dene yeniden dener ve içerik gelir', (t) async {
      final auth = ModulesFakeAuth()
        ..listSitesError = ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
      await _pump(t, auth);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.listSitesError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Tekrar Dene'), findsNothing);
      expect(doorModuleSwitch, findsOneWidget);
    });

    testWidgets('site listesi hatasından sonra Tekrar Dene sürerken iskelet gösterilir (yanıltıcı boş durum yanıp sönmez)', (t) async {
      final auth = ModulesFakeAuth()
        ..listSitesError = ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
      await _pump(t, auth);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.listSitesError = null;
      auth.sitesGate = Completer<void>();
      await tapText(t, 'Tekrar Dene');
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Yönetilecek onaylı site bulunamadı.'), findsNothing);
      expect(find.byType(InlineNotice), findsNothing);

      auth.sitesGate!.complete();
      await settleFor(t);
      expect(doorModuleSwitch, findsOneWidget);
    });

    testWidgets('site değişirken önceki sitenin işlem sonrası tazelemesi yeni sitenin yüklemesini ezmez (iskelette kalmaz)', (t) async {
      final auth = _fullAuth();
      await _pump(t, auth);

      // 1) A sitesinde Geçiş Kontrol'ü kapat; istek sürerken beklet.
      auth.setGate = Completer<void>();
      await tapFinder(t, doorModuleSwitch);
      await tapText(t, 'Kapat');
      expect(auth.setCalls, hasLength(1));

      // 2) İşlem sürerken B sitesine geç; B'nin modül yanıtı henüz gelmedi.
      auth.modulesGate = Completer<void>();
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park (12)'));
      expect(auth.getModulesCalls.last, 12);
      final readsBefore = auth.getModulesCalls.length;

      // 3) A'nın işlemi biter (eski kod burada A'yı yeniden çekip B'nin jetonunu geçersiz kılıyordu).
      auth.setGate!.complete();
      await settleFor(t);
      expect(auth.getModulesCalls.length, readsBefore,
          reason: 'başka siteye geçildiyse eski sitenin tazelemesi başlatılmaz');

      // 4) B'nin yanıtı gelir: içerik görünür, iskelette kalmaz.
      auth.modulesGate!.complete();
      await settleFor(t);
      expect(doorModuleSwitch, findsOneWidget);
      expect(find.byType(ListSkeleton), findsNothing);
    });

    testWidgets('işlem sürerken ekran kapansa da menü süzgeci için onModulesChanged çağrılır', (t) async {
      final auth = _fullAuth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      auth.setGate = Completer<void>();
      await tapFinder(t, doorModuleSwitch);
      await tapText(t, 'Kapat');

      await t.pumpWidget(const SizedBox()); // ekran kapandı
      auth.setGate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(changed, hasLength(1), reason: 'sunucu durumu değişmiş olabilir: süzgeç tazelenmeli');
    });

    testWidgets('yenilemede mevcut içerik ekranda kalır (iskelet açılmaz)', (t) async {
      final auth = _fullAuth();
      await _pump(t, auth);
      auth.modulesGate = Completer<void>();
      await tapFinder(t, find.byTooltip('Yenile'));
      expect(doorModuleSwitch, findsOneWidget);
      expect(find.byType(ListSkeleton), findsNothing);
    });
  });
}
