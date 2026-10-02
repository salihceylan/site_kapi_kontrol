// FAZ 5 / A2-G3: Siteler / Site Daireleri ekranı (SitesView, SiteCard, DoorCard, ApartmentCard).
//
// AGENTS.md kural 6: taşma YOK (320x640 x2,0 ve 360x640 x1,5; açık + koyu tema). Davranış: eylem
// düğmeleri GÖRÜNÜR kalır (menüye taşınmaz), kapalı kartın içeriği ağaçta yoktur, yenile/sayfalama
// geri çağrıları değişmedi. Kart-içinde-kart yok (tek yüzey).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/sites_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_card.dart';

import 'list_fixtures.dart';

const String _longName =
    'Onay Bekleyen Site (E2E) Uzun Adlı Konut Yapı Kooperatifi';

SitesView _view({
  List<String>? log,
  bool loading = false,
  bool apartmentMode = false,
  bool superUser = true,
  List<SiteRecord>? sites,
  SitePage? page,
  SiteStructureRecord? structure,
  SiteManagersData? managers,
  Set<int> busyDelete = const <int>{},
  Set<int> busyApprovals = const <int>{},
  Set<int> busyMails = const <int>{},
}) {
  final l = log ?? <String>[];
  final list = sites ?? fxSites();
  return SitesView(
    canManageSites: true,
    canManageApartmentUsers: true,
    canAssignDoorDevices: true,
    apartmentMode: apartmentMode,
    pageData: loading ? null : (page ?? fxSitePage(list, total: list.length)),
    sites: loading ? const <SiteRecord>[] : list,
    selectedSite: list.isEmpty ? null : list.first,
    selectedStructure: loading ? null : (structure ?? fxStructure()),
    isLoadingSites: loading,
    isLoadingStructure: loading,
    busyDeleteSites: busyDelete,
    busySiteApprovals: busyApprovals,
    busyApartmentMails: busyMails,
    onRefreshSites: () => l.add('refresh'),
    onLoadPage: (p) => l.add('page:$p'),
    onOpenAddSite: () => l.add('addSite'),
    onSelectSite: (s) => l.add('select:${s.id}'),
    onEditSite: (s) => l.add('edit:${s.id}'),
    onDeleteSite: (s) => l.add('delete:${s.id}'),
    onApproveSite: (s) => l.add('approve:${s.id}'),
    onRejectSite: (s) => l.add('reject:${s.id}'),
    onEditApartmentResident: (a) => l.add('editApt:${a.id}'),
    onSendApartmentMail: (a) => l.add('mailApt:${a.id}'),
    onAssignDoorDevice: (d) => l.add('assign:${d.id}'),
    siteManagersData: loading ? null : (managers ?? fxManagers()),
    isLoadingManagers: loading,
    onInviteSiteManager: () => l.add('invite'),
    onRemoveSiteManager: (m) => l.add('removeMgr:${m.userCode}'),
    onRevokeSiteManagerInvitation: (i) => l.add('revoke:${i.id}'),
    onOpenAddDoor: () => l.add('addDoor'),
    onEditDoor: (d) => l.add('editDoor:${d.id}'),
    onDeleteDoor: (d) => l.add('deleteDoor:${d.id}'),
    onReplaceDevice: (d) => l.add('replace:${d.id}'),
    onManageDoorPermissions: (d) => l.add('perm:${d.id}'),
    onDeleteApartmentResident: (a) => l.add('delApt:${a.id}'),
    onConfigurePolicy: (s) => l.add('policy:${s.id}'),
    onDownloadCredentialsPdf: (s) => l.add('pdf:${s.id}'),
    onDownloadLogsPdf: (s) => l.add('logsPdf:${s.id}'),
    onShowSiteJoinQr: (s) => l.add('qr:${s.id}'),
    onManageJoinRequests: (s) => l.add('joinReq:${s.id}'),
    onShowResidentsAccordion: (s) => l.add('residents:${s.id}'),
    isSuperUser: superUser,
    onApproveDeleteSite: (s) => l.add('approveDelete:${s.id}'),
    onRejectDeleteSite: (s) => l.add('rejectDelete:${s.id}'),
    onDeleteSiteWithEmail: (s) => l.add('emailDelete:${s.id}'),
  );
}

void main() {
  group('SitesView taşma matrisi', () {
    listMatrix('tam sayfa: liste, özet, yöneticiler, daireler, kapılar', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(t, _view(), width: w, height: h, scale: scale, dark: dark);
      for (final text in const <String>[
        'Siteler',
        'Yeni Site',
        'Site Listesi (3)',
        'Yeşilvadi Sitesi',
        _longName,
        'Mavi Park Evleri',
        'Silme Onayı',
        'Onay Bekliyor',
        'Yönetici atanmamış',
        'Site Kodu: 5899864115',
        'MQTT Site ID: 9261',
        'Site Yöneticileri (2)',
        'Bekleyen Davetler (1)',
        'Yönetici Davet Et',
        'Daireler',
        '3 Daire',
        'Kapılar',
        'Yeni Kapı',
        'Cihaz atanmamış (Kapı kontrolü pasif)',
        'Online',
        'Offline',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'metin korunmalı: $text');
      }
      // Kart-içinde-kart yok: hiçbir AppCard başka bir AppCard'ın içinde değil.
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(AppCard),
        ),
        findsNothing,
      );
      // Her kapı kartında TEK menü (önceki dar/geniş çift dalı kalktı).
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ShimmerScope), findsNothing);
    });

    listMatrix(
      'kartlar açılır: site, daire akordiyonu, daire satırı, kapı menüsü',
      (t, w, h, scale, dark) async {
        final log = <String>[];
        await pumpList(
          t,
          _view(log: log),
          width: w,
          height: h,
          scale: scale,
          dark: dark,
        );
        // Kapalı kartın eylemleri ağaçta YOK.
        expect(find.text('Giriş & Güvenlik Politikaları'), findsNothing);
        expect(find.text('Onayla'), findsNothing);

        // Onay bekleyen site: karar + yönetim + yıkıcı eylemler GÖRÜNÜR.
        await tapText(t, _longName);
        expect(log, contains('select:5899864116'));
        for (final text in const <String>[
          'Onayla',
          'Reddet',
          'Giriş & Güvenlik Politikaları',
          'Düzenle',
          'Geçiş Raporu (PDF)',
          'Site Katılım QR',
          'Katılım Talepleri',
          'Sil',
          'E-Posta Koduyla Sil',
          'ID: 5899864116',
        ]) {
          expect(find.text(text), findsWidgets, reason: 'açık kart: $text');
        }

        // Silme onayı bekleyen site: uyarı kutusu + üç karar düğmesi.
        await tapText(t, 'Mavi Park Evleri');
        expect(find.textContaining('ONAYINIZ bekleniyor'), findsOneWidget);
        expect(find.text('Silmeyi Onayla'), findsOneWidget);
        expect(find.text('Talebi Reddet'), findsOneWidget);
        expect(find.text('E-Posta Kodu İle Hemen Sil'), findsOneWidget);

        // Daireler akordiyonu -> daire satırı.
        await tapText(t, 'Daireler');
        expect(find.byType(ApartmentCard), findsNWidgets(3));
        await tapText(t, 'A Blok / Daire 1');
        expect(find.text('Bilgileri Gönder'), findsOneWidget);
        expect(find.text('Sakini Sil'), findsOneWidget);
        expect(find.textContaining('Kullanıcı Adı: sakin1'), findsOneWidget);

        // Kapı menüsü: tek menü, dört öğe, seçim geri çağrıyı çağırır.
        await tapFinder(t, find.byIcon(Icons.more_vert_rounded));
        for (final item in const <String>[
          'Kapı Yetkileri',
          'Arızalı Cihazı Değiştir',
          'Kapıyı Düzenle',
          'Kapıyı Sil',
        ]) {
          expect(find.text(item), findsOneWidget, reason: item);
        }
        await tapText(t, 'Kapıyı Düzenle');
        expect(log, contains('editDoor:1'));
      },
    );

    listMatrix('iskelet ve boş durumlar', (t, w, h, scale, dark) async {
      await pumpList(
        t,
        _view(loading: true),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      // Yüklenirken çıplak spinner yerine iskelet; tek paylaşılan shimmer kapsamı yok, bölge başına bir.
      expect(find.byType(ShimmerScope), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Site Listesi'), findsOneWidget);

      await pumpList(
        t,
        _view(
          sites: const <SiteRecord>[],
          page: null,
          structure: fxStructure(apartments: const [], doors: const []),
          managers: fxManagers(invitation: false),
        ),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Kayıtlı site bulunamadı.'), findsOneWidget);
      expect(find.text('Bu site için kapı kaydı bulunamadı.'), findsOneWidget);
      expect(find.text('Kayıtlı daire bulunmuyor'), findsOneWidget);
      expect(find.byType(ShimmerScope), findsNothing);
    });
  });

  group('SitesView davranış', () {
    testWidgets('başlık ve eylem metinleri: Siteler / Site Daireleri', (
      t,
    ) async {
      await pumpList(
        t,
        _view(),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(find.text('Siteler'), findsOneWidget);
      expect(find.text('Site Daireleri'), findsNothing);
      await pumpList(
        t,
        _view(apartmentMode: true),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(find.text('Site Daireleri'), findsOneWidget);
      expect(find.text('Siteler'), findsNothing);
    });

    testWidgets('Yeni Site / Yeni Kapı / Yönetici Davet Et geri çağrıları', (
      t,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapText(t, 'Yeni Site');
      await tapText(t, 'Yeni Kapı');
      await tapText(t, 'Yönetici Davet Et');
      expect(log, <String>['addSite', 'addDoor', 'invite']);
      // Yeni Site / Yeni Kapı / Davet düğmeleri en az 44 dp yüksekliktedir.
      for (final text in const <String>[
        'Yeni Site',
        'Yeni Kapı',
        'Yönetici Davet Et',
      ]) {
        final button = find.ancestor(
          of: find.text(text),
          matching: find.byType(ElevatedButton),
        );
        expect(
          t.getSize(button).height,
          greaterThanOrEqualTo(44),
          reason: text,
        );
      }
    });

    testWidgets(
      'yenile: yüklenirken devre dışı, aksi hâlde geri çağrıyı çağırır',
      (t) async {
        final log = <String>[];
        await pumpList(
          t,
          _view(log: log),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        final refresh = find.widgetWithIcon(IconButton, Icons.refresh);
        expect(refresh, findsOneWidget);
        await tapFinder(t, refresh);
        expect(log, contains('refresh'));

        await pumpList(
          t,
          SitesView(
            canManageSites: true,
            canManageApartmentUsers: true,
            canAssignDoorDevices: true,
            apartmentMode: false,
            pageData: null,
            sites: const <SiteRecord>[],
            selectedSite: null,
            selectedStructure: null,
            isLoadingSites: true,
            isLoadingStructure: false,
            busyDeleteSites: const <int>{},
            busySiteApprovals: const <int>{},
            busyApartmentMails: const <int>{},
            onRefreshSites: () => log.add('refresh-loading'),
            onLoadPage: (_) {},
            onOpenAddSite: () {},
            onSelectSite: (_) {},
            onEditSite: (_) {},
            onDeleteSite: (_) {},
            onApproveSite: (_) {},
            onRejectSite: (_) {},
            onEditApartmentResident: (_) {},
            onSendApartmentMail: (_) {},
            onAssignDoorDevice: (_) {},
          ),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        final loadingRefresh = t.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.refresh),
        );
        expect(loadingRefresh.onPressed, isNull);
      },
    );

    testWidgets('sayfalama: 44 dp düğmeler, ipuçları, sınırlarda devre dışı', (
      t,
    ) async {
      final log = <String>[];
      final sites = fxSites();
      await pumpList(
        t,
        _view(
          log: log,
          sites: sites,
          page: fxSitePage(sites, total: 25, page: 2),
        ),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(find.text('Sayfa 2 / 3 | Toplam 25'), findsOneWidget);
      for (final tip in const <String>['Önceki sayfa', 'Sonraki sayfa']) {
        final size = t.getSize(find.byTooltip(tip));
        expect(size.width, greaterThanOrEqualTo(44), reason: tip);
        expect(size.height, greaterThanOrEqualTo(44), reason: tip);
      }
      await tapFinder(t, find.byTooltip('Önceki sayfa'));
      await tapFinder(t, find.byTooltip('Sonraki sayfa'));
      expect(log, <String>['page:1', 'page:3']);

      // İlk sayfada "önceki", son sayfada "sonraki" devre dışı.
      await pumpList(
        t,
        _view(sites: sites, page: fxSitePage(sites, total: 25, page: 1)),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(
        t
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      await pumpList(
        t,
        _view(sites: sites, page: fxSitePage(sites, total: 25, page: 3)),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(
        t
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('eylem geri çağrıları: onay, red, sil, düzenle, daire, kapı', (
      t,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapText(t, _longName);
      await tapText(t, 'Onayla');
      await tapText(t, 'Reddet');
      await tapText(t, 'Giriş & Güvenlik Politikaları');
      await tapText(t, 'Geçiş Raporu (PDF)');
      await tapText(t, 'Düzenle');
      await tapText(t, 'Sil');
      await tapText(t, 'E-Posta Koduyla Sil');
      expect(
        log,
        containsAllInOrder(<String>[
          'select:5899864116',
          'approve:5899864116',
          'reject:5899864116',
          'policy:5899864116',
          'logsPdf:5899864116',
          'edit:5899864116',
          'delete:5899864116',
          'emailDelete:5899864116',
        ]),
      );

      log.clear();
      await tapText(t, 'Daireler');
      await tapText(t, 'A Blok / Daire 1');
      await tapText(t, 'Bilgileri Gönder');
      await tapText(t, 'Sakini Sil');
      expect(log, <String>['mailApt:1', 'delApt:1']);

      log.clear();
      // Kapı 3 cihazsız: "Cihaz Ata"; kapı 1 cihazlı: "Değiştir".
      await tapText(t, 'Cihaz Ata');
      await tapText(t, 'Değiştir');
      expect(log, <String>['assign:3', 'assign:1']);
    });

    testWidgets(
      'kapalı kartın içeriği ağaçta yoktur; kapanınca animasyon bitince kalkar',
      (t) async {
        await pumpList(
          t,
          _view(),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.text('Geçiş Raporu (PDF)'), findsNothing);
        await tapText(t, 'Yeşilvadi Sitesi');
        expect(find.text('Geçiş Raporu (PDF)'), findsOneWidget);
        // Kapanırken içerik daralarak görünür kalır, animasyon bitince ağaçtan kalkar.
        await t.tap(find.text('Yeşilvadi Sitesi').first);
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        expect(find.text('Geçiş Raporu (PDF)'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Geçiş Raporu (PDF)'), findsNothing);
      },
    );

    testWidgets(
      'erişilebilirlik: kartın açık/kapalı durumu anlamsal olarak bildirilir',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpList(
          t,
          _view(),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        final card = find.byType(SiteCard).first;
        expect(
          t.getSemantics(card),
          isSemantics(hasExpandedState: true, isExpanded: false),
        );
        await tapText(t, 'Yeşilvadi Sitesi');
        expect(
          t.getSemantics(card),
          isSemantics(hasExpandedState: true, isExpanded: true),
        );
        handle.dispose();
      },
    );

    testWidgets('hareket azaltma: tek kare sonra son durum (anında açılır)', (
      t,
    ) async {
      await pumpList(
        t,
        _view(),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
        reduce: true,
      );
      await t.tap(find.text('Yeşilvadi Sitesi').first);
      await t.pump();
      expect(find.text('Geçiş Raporu (PDF)'), findsOneWidget);
      expect(t.getSize(find.text('Geçiş Raporu (PDF)')).height, greaterThan(0));
    });

    testWidgets('meşgul durumlar: onay/silme/posta düğmeleri devre dışı', (
      t,
    ) async {
      await pumpList(
        t,
        _view(
          busyApprovals: const <int>{5899864116},
          busyDelete: const <int>{5899864117, 5899864116},
          busyMails: const <int>{1},
        ),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapText(t, _longName);
      OutlinedButton outlined(String label) => t.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
      );
      ElevatedButton elevated(String label) => t.widget<ElevatedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(elevated('Onayla').onPressed, isNull);
      expect(outlined('Reddet').onPressed, isNull);
      expect(outlined('Sil').onPressed, isNull);
      expect(outlined('E-Posta Koduyla Sil').onPressed, isNull);
    });

    testWidgets('yönetici satırları: kaldır ve davet iptal geri çağrıları', (
      t,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      // Kurucu yönetici kaldırılamaz: yalnız ikinci yöneticide düğme var.
      expect(find.byTooltip('Yöneticiliği Kaldır'), findsOneWidget);
      await tapFinder(t, find.byTooltip('Yöneticiliği Kaldır'));
      await tapText(t, 'İptal Et');
      expect(log, <String>['removeMgr:64212', 'revoke:1']);
    });
  });

  group('SitesView kontrast (G: kontrast düzeltme noktaları)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'uyarı ve yıkıcı metinler >= 4,5:1 (${dark ? 'koyu' : 'açık'})',
        (t) async {
          await pumpList(
            t,
            _view(),
            width: 360,
            height: 800,
            scale: 1,
            dark: dark,
          );
          final p = dark ? AppPalette.dark : AppPalette.light;
          // "Yönetici atanmamış": uyarı ink'i (eski amber/#D97706 zeminde ~3:1 idi).
          final unassigned = t.widget<Text>(find.text('Yönetici atanmamış'));
          expect(unassigned.style!.color, AppTone.warning.ink(p));
          expect(
            contrastRatio(unassigned.style!.color!, p.surface),
            greaterThanOrEqualTo(4.5),
          );

          // "Sil": eski roseLight metin (açıkta ~2,8:1) yerine danger ink.
          await tapText(t, 'Yeşilvadi Sitesi');
          final del = t.widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Sil'),
              matching: find.byType(OutlinedButton),
            ),
          );
          final fg = del.style!.foregroundColor!.resolve(<WidgetState>{})!;
          expect(fg, AppTone.danger.ink(p));
          expect(contrastRatio(fg, p.surface), greaterThanOrEqualTo(4.5));

          // Onayla: beyaz metin, koyu success zemin (>= 4,5:1).
          await tapText(t, _longName);
          final approve = t.widget<ElevatedButton>(
            find.ancestor(
              of: find.text('Onayla'),
              matching: find.byType(ElevatedButton),
            ),
          );
          final bg = approve.style!.backgroundColor!.resolve(<WidgetState>{})!;
          expect(bg, AppTone.success.a);
          expect(contrastRatio(Colors.white, bg), greaterThanOrEqualTo(4.5));
        },
      );
    }
  });

  group('SiteCard / DoorCard / ApartmentCard tek başına', () {
    testWidgets(
      'DoorCard: cihazsız kapı uyarı tonlu AppCard, cihazlı kapı değil',
      (t) async {
        Future<void> pumpDoor(Widget w) =>
            pumpList(t, w, width: 360, height: 800, scale: 1, dark: false);
        await pumpDoor(
          DoorCard(
            door: fxDoor(3, name: 'Yaya Kapısı'),
            onAssignDevice: () {},
          ),
        );
        expect(t.widget<AppCard>(find.byType(AppCard)).tone, AppTone.warning);
        await pumpDoor(
          DoorCard(
            door: fxDoor(
              1,
              uid: '240AC4E2E001',
              target: 'esp32-wroom',
              online: true,
            ),
            onAssignDevice: () {},
          ),
        );
        expect(t.widget<AppCard>(find.byType(AppCard)).tone, isNull);
        // Menü yok: eylem satırında yalnız "Değiştir".
        expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
        expect(find.text('Değiştir'), findsOneWidget);
      },
    );

    testWidgets(
      'SiteCard: seçili kart AppCard.selected, yalnız seçili kartta',
      (t) async {
        Future<void> pumpCard({required bool selected}) => pumpList(
          t,
          SiteCard(
            site: fxSite(),
            selected: selected,
            formattedCreatedAt: '01.10.2026 12:30',
            deleteBusy: false,
            approvalBusy: false,
            onTap: () {},
          ),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        await pumpCard(selected: true);
        expect(t.widget<AppCard>(find.byType(AppCard)).selected, isTrue);
        await pumpCard(selected: false);
        expect(t.widget<AppCard>(find.byType(AppCard)).selected, isFalse);
      },
    );
  });

  group('SitesView geniş ekran ve yatay', () {
    testWidgets(
      '820x640 ve 900x400 (yatay), 1,0x/1,5x, açık/koyu: taşma yok; başlık satırı yan yana',
      (t) async {
        for (final (w, h) in const <(double, double)>[(820, 640), (900, 400)]) {
          for (final scale in const <double>[1.0, 1.5]) {
            for (final dark in const <bool>[false, true]) {
              await pumpList(
                t,
                _view(),
                width: w,
                height: h,
                scale: scale,
                dark: dark,
              );
              // Geniş ekranda (>= 680) "Yeni Site" başlığın SAĞINDA, aynı satırda durur.
              final title = t.getRect(find.text('Siteler'));
              final button = t.getRect(find.text('Yeni Site'));
              expect(button.left, greaterThanOrEqualTo(title.right));
              expect(
                (button.center.dy - title.center.dy).abs(),
                lessThan(title.height + button.height),
              );
              await tapText(t, 'Yeşilvadi Sitesi');
              expect(
                find.text('Giriş & Güvenlik Politikaları'),
                findsOneWidget,
              );
              expect(t.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
