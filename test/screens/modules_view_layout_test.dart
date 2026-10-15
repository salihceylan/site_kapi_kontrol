// Platform modül sistemi Faz 1: "Modüller" ekranı (ModulesView) + "Ek roller" bölümü.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata /
// dolu durumlar taşmaz. Kural 7: işlemden sonra veri yeniden çekilir, yenile düğmesi ve
// `reload()` (aşağı çekip yenileme) çalışır. Geçiş Kontrol KAPATILIRKEN önce onay penceresi çıkar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
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

void main() {
  group('taşma matrisi', () {
    listMatrix('dolu görünüm (8 modül + 2 ek rol)', (t, w, h, s, dark) async {
      await _pump(t, _fullAuth(), width: w, height: h, scale: s, dark: dark);

      expect(find.text('Modüller'), findsOneWidget);
      expect(find.text('Site Modülleri'), findsOneWidget);
      expect(find.text('Geçiş Kontrol (AHBU)'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget,
          reason: 'yalnız açılıp kapatılabilen modülde anahtar var');
      expect(find.widgetWithText(StatusChip, 'Açık'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(5));
      expect(find.widgetWithText(StatusChip, 'Her sitede açık'), findsNWidgets(2));
      expect(find.text('Ek Roller'), findsOneWidget);
      expect(find.byType(StaffRoleCard), findsNWidgets(2));
      expect(find.byTooltip('Rolü Kaldır'), findsNWidgets(2));
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(find.textContaining('Yönetim Kurulu / Denetçi'), findsWidgets);
    });

    listMatrix('Geçiş Kontrol kapalı: çip "Kapalı"', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      );
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.widgetWithText(StatusChip, 'Kapalı'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Açık'), findsNothing);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
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

    listMatrix('boş durumlar: ek rol yok', (t, w, h, s, dark) async {
      await _pump(t, ModulesFakeAuth(), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Ek rol atanmamış.'), findsOneWidget);
      expect(find.text('Rol Ekle'), findsOneWidget);
    });

    listMatrix('yükleniyor: siteler', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()..sitesGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    listMatrix('yükleniyor: modüller ve ek roller (site seçici görünür)', (
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
      expect(find.byType(ListSkeleton), findsNWidgets(2));
      expect(find.byType(Switch), findsNothing);
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

    listMatrix('hata: modüller ve ek roller yüklenemedi', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()
        ..modulesError = ApiException('Bu site üzerinde yönetim yetkiniz bulunmuyor.')
        ..rolesError = ApiException('Ek roller yüklenemedi (500).');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsNWidgets(2));
      expect(find.text('Bu site üzerinde yönetim yetkiniz bulunmuyor.'), findsOneWidget);
      expect(find.text('Ek roller yüklenemedi (500).'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('Geçiş Kontrol kapatma onayı', () {
    testWidgets('kapatırken önce onay penceresi (uyarı metni sunucudakiyle aynı); Vazgeç çağrı yapmaz', (t) async {
      final auth = _fullAuth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));

      await tapFinder(t, find.byType(Switch));
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Geçiş Kontrol Kapatılsın mı?'), findsOneWidget);
      expect(find.text(_doorWarning), findsOneWidget);

      await tapText(t, 'Vazgeç');
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.setCalls, isEmpty);
      expect(changed, isEmpty);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('Kapat -> confirm:true ile istek, çip "Kapalı", otomatik yeniden çekme, onModulesChanged', (t) async {
      final auth = _fullAuth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      final readsBefore = auth.getModulesCalls.length;

      await tapFinder(t, find.byType(Switch));
      await tapText(t, 'Kapat');
      await settleFor(t);

      expect(auth.setCalls, hasLength(1));
      expect(auth.setCalls.single.site, 11);
      expect(auth.setCalls.single.code, 'door_control');
      expect(auth.setCalls.single.enabled, isFalse);
      expect(auth.setCalls.single.confirm, isTrue);
      expect(find.widgetWithText(StatusChip, 'Kapalı'), findsOneWidget);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Geçiş Kontrol (AHBU) kapatıldı.'), findsOneWidget);
      expect(changed, hasLength(1));
      expect(auth.getModulesCalls.length, readsBefore + 1,
          reason: 'işlem sonrası modül durumu otomatik yeniden çekilir');
    });

    testWidgets('açarken onay GEREKMEZ (confirm:false)', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      );
      await _pump(t, auth);

      await tapFinder(t, find.byType(Switch));
      await settleFor(t);

      expect(find.byType(AppDialog), findsNothing);
      expect(auth.setCalls.single.enabled, isTrue);
      expect(auth.setCalls.single.confirm, isFalse);
      expect(find.widgetWithText(StatusChip, 'Açık'), findsOneWidget);
      expect(find.text('Geçiş Kontrol (AHBU) açıldı.'), findsOneWidget);
    });

    testWidgets('sunucu hatası: Türkçe mesaj gösterilir, anahtar eski değerde kalır', (t) async {
      final auth = _fullAuth()
        ..setError = ApiException('Bu modül kapatılamaz.', statusCode: 400, code: 'MODULE_NOT_TOGGLEABLE');
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));

      await tapFinder(t, find.byType(Switch));
      await tapText(t, 'Kapat');
      await settleFor(t);

      expect(find.text('Bu modül kapatılamaz.'), findsOneWidget);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(changed, hasLength(1),
          reason: 'hata/zaman aşımı olsa da menü süzgeci sunucudan yeniden okunur');
    });

    testWidgets('sunucu onay isterse (409 MODULE_CONFIRM_REQUIRED) sunucu metniyle onay sorulur ve onayda yeniden denenir', (t) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      )..demandConfirm = true;
      await _pump(t, auth);

      await tapFinder(t, find.byType(Switch)); // açmaya çalış: ilk istek confirm:false
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

  group('Ek roller', () {
    testWidgets('rol ekle: doğrulama -> atama -> liste yeniden çekilir', (t) async {
      final auth = ModulesFakeAuth();
      await _pump(t, auth);
      final readsBefore = auth.listRolesCalls.length;

      await tapText(t, 'Rol Ekle');
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Ek Rol Ata'), findsOneWidget);

      // Boş gönderim: doğrulama iletileri.
      await tapText(t, 'Ata');
      expect(find.text('E-posta zorunludur.'), findsOneWidget);
      expect(find.text('Bir rol seçin.'), findsOneWidget);
      expect(auth.assignCalls, isEmpty);

      await t.enterText(find.widgetWithText(TextFormField, 'E-posta'), 'gecersiz');
      await tapText(t, 'Ata');
      expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);

      await t.enterText(
        find.widgetWithText(TextFormField, 'E-posta'),
        '  selin@ornek.com ',
      );
      await tapFinder(t, find.byType(DropdownButtonFormField<StaffRoleType>));
      await tapFinder(t, find.text('Görevli').last);
      await tapText(t, 'Ata');
      await settleFor(t);

      expect(auth.assignCalls, hasLength(1));
      expect(auth.assignCalls.single.site, 11);
      expect(auth.assignCalls.single.email, 'selin@ornek.com');
      expect(auth.assignCalls.single.role, 'STAFF');
      expect(find.byType(AppDialog), findsNothing);
      expect(find.text('Ek rol atandı.'), findsOneWidget);
      expect(auth.listRolesCalls.length, readsBefore + 1);
      expect(find.byType(StaffRoleCard), findsOneWidget);
      expect(find.text('Görevli'), findsWidgets);
    });

    testWidgets('sunucu reddi (USER_NOT_FOUND): pencerede Türkçe hata, pencere açık kalır', (t) async {
      final auth = ModulesFakeAuth()
        ..assignError = ApiException(
          'Bu e-posta ile kayıtlı hesap yok.',
          statusCode: 404,
          code: 'USER_NOT_FOUND',
        );
      await _pump(t, auth);

      await tapText(t, 'Rol Ekle');
      await t.enterText(find.widgetWithText(TextFormField, 'E-posta'), 'yok@ornek.com');
      await tapFinder(t, find.byType(DropdownButtonFormField<StaffRoleType>));
      await tapFinder(t, find.text('Yönetim Kurulu / Denetçi').last);
      await tapText(t, 'Ata');
      await settleFor(t);

      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu e-posta ile kayıtlı hesap yok.'), findsOneWidget);
      expect(auth.assignCalls.single.role, 'BOARD_MEMBER');

      // Düzeltilip yeniden denenebilir.
      auth.assignError = null;
      await tapText(t, 'Ata');
      await settleFor(t);
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.assignCalls, hasLength(2));
    });

    testWidgets('İptal pencereyi kapatır, atama yapılmaz', (t) async {
      final auth = ModulesFakeAuth();
      await _pump(t, auth);
      await tapText(t, 'Rol Ekle');
      await tapText(t, 'İptal');
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.assignCalls, isEmpty);
    });

    testWidgets('rol kaldır: onay -> istek -> liste yeniden çekilir; Vazgeç istek yapmaz', (t) async {
      final auth = _fullAuth();
      await _pump(t, auth);
      expect(find.byType(StaffRoleCard), findsNWidgets(2));
      final readsBefore = auth.listRolesCalls.length;

      await tapFinder(t, find.byTooltip('Rolü Kaldır'));
      expect(find.text('Rol Kaldırılsın mı?'), findsOneWidget);
      expect(find.textContaining('dairesindeki yetkileriyle kalır'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(auth.removeCalls, isEmpty);

      await tapFinder(t, find.byTooltip('Rolü Kaldır'));
      await tapText(t, 'Kaldır');
      await settleFor(t);

      expect(auth.removeCalls.single, (site: 11, user: 41));
      expect(find.text('Ek rol kaldırıldı.'), findsOneWidget);
      expect(auth.listRolesCalls.length, readsBefore + 1);
      expect(find.byType(StaffRoleCard), findsOneWidget);
    });

    testWidgets('kaldırma hatası: mesaj gösterilir, satır kalır', (t) async {
      final auth = _fullAuth()
        ..removeError = ApiException('Bu kişide kurul veya görevli rolü yok.');
      await _pump(t, auth);
      await tapFinder(t, find.byTooltip('Rolü Kaldır'));
      await tapText(t, 'Kaldır');
      await settleFor(t);
      expect(find.text('Bu kişide kurul veya görevli rolü yok.'), findsOneWidget);
      expect(find.byType(StaffRoleCard), findsNWidgets(2));
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
      expect(auth.listRolesCalls, <int>[11]);

      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      expect(find.text('Gül Sitesi (11)'), findsWidgets);
      expect(find.text('Mavi Park (12)'), findsOneWidget);
      expect(find.text('Bekleyen (13)'), findsNothing);
    });

    testWidgets('başka site seçilince o sitenin modülleri ve rolleri çekilir', (t) async {
      final auth = _fullAuth();
      await _pump(t, auth);
      expect(find.byType(StaffRoleCard), findsNWidgets(2));

      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park (12)'));
      await settleFor(t);

      expect(auth.getModulesCalls.last, 12);
      expect(auth.listRolesCalls.last, 12);
      expect(find.byType(StaffRoleCard), findsNothing,
          reason: 'önceki sitenin rolleri yeni sitede gösterilmez');
      expect(find.text('Ek rol atanmamış.'), findsOneWidget);
    });

    testWidgets('yenile düğmesi ve reload() siteleri, modülleri ve rolleri yeniden çeker', (t) async {
      final auth = _fullAuth();
      final key = await _pump(t, auth);
      expect(auth.listSitesCalls, 1);
      expect(auth.getModulesCalls, hasLength(1));

      await tapFinder(t, find.byTooltip('Yenile'));
      expect(auth.listSitesCalls, 2);
      expect(auth.getModulesCalls, hasLength(2));
      expect(auth.listRolesCalls, hasLength(2));

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
      expect(find.byType(Switch), findsOneWidget);
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
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('ek rol listesi boşken yenileme hatası "Ek rol atanmamış." diye gizlenmez; Tekrar Dene çalışır', (t) async {
      final auth = ModulesFakeAuth();
      await _pump(t, auth);
      expect(find.text('Ek rol atanmamış.'), findsOneWidget);

      auth.rolesError = ApiException('Ek roller yüklenemedi (500).');
      await tapFinder(t, find.byTooltip('Yenile'));
      expect(find.text('Ek roller yüklenemedi (500).'), findsOneWidget);
      expect(find.text('Ek rol atanmamış.'), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.rolesError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Ek roller yüklenemedi (500).'), findsNothing);
      expect(find.text('Ek rol atanmamış.'), findsOneWidget);
    });

    testWidgets('site değişirken önceki sitenin işlem sonrası tazelemesi yeni sitenin yüklemesini ezmez (iskelette kalmaz)', (t) async {
      final auth = _fullAuth();
      await _pump(t, auth);

      // 1) A sitesinde Geçiş Kontrol'ü kapat; istek sürerken beklet.
      auth.setGate = Completer<void>();
      await tapFinder(t, find.byType(Switch));
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
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(ListSkeleton), findsNothing);
    });

    testWidgets('işlem sürerken ekran kapansa da menü süzgeci için onModulesChanged çağrılır', (t) async {
      final auth = _fullAuth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      auth.setGate = Completer<void>();
      await tapFinder(t, find.byType(Switch));
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
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(ListSkeleton), findsNothing);
    });
  });
}
