// Platform modül sistemi Faz 1: yönetim türü seçici (ManagementTypeSelector), SetupSiteDialog /
// SiteDialog entegrasyonu ve site kartındaki tür çipi.
//
// Faz 1: yalnız "Apartman ve Site" seçilebilir; diğer dördü "Yakında…" çipiyle devre dışıdır. Taşma:
// 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/management_type_selector.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_card.dart';

import 'dialog_layout_harness.dart';
import 'list_fixtures.dart';

class _SetupAuth extends AuthService {
  _SetupAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<String?> types = <String?>[];

  @override
  Future<Map<String, dynamic>> setupSite({
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>>? doors,
    int doorCount = 1,
    String? deviceUid,
    String? managementType,
  }) async {
    types.add(managementType);
    return <String, dynamic>{};
  }

  @override
  Future<ManagedUserPage> listManagedUsers({
    UserRole? role,
    UserRole? excludeRole,
    required int page,
    int pageSize = 10,
    String? search,
  }) async => const ManagedUserPage(users: [], total: 0, page: 1, pageSize: 100);
}

Finder get _radioOn => find.byIcon(Icons.radio_button_checked_rounded);
Finder get _radioOff => find.byIcon(Icons.radio_button_unchecked_rounded);

void main() {
  group('ManagementTypeSelector', () {
    listMatrix('5 tür: Apartman ve Site seçili, diğer dördü "Yakında…" ve devre dışı', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final changes = <ManagementType>[];
      await pumpList(
        t,
        ManagementTypeSelector(
          value: ManagementType.apartmentSite,
          onChanged: changes.add,
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );

      expect(find.text('Yönetim Türü'), findsOneWidget);
      for (final type in ManagementType.values) {
        expect(find.text(type.label), findsOneWidget, reason: type.label);
      }
      expect(_radioOn, findsOneWidget);
      expect(_radioOff, findsNWidgets(4));
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(4));

      // Devre dışı türe dokunmak seçimi değiştirmez.
      for (final label in <String>['Rezidans', 'İş Merkezi', 'Kooperatif', 'Alışveriş Merkezi']) {
        await t.ensureVisible(find.text(label));
        await t.tap(find.text(label));
        await t.pump();
      }
      expect(changes, isEmpty);

      // Seçilebilir türe dokunmak bildirir.
      await t.tap(find.text('Apartman ve Site'));
      await t.pump();
      expect(changes, <ManagementType>[ManagementType.apartmentSite]);
    });

    testWidgets('anlamsal ağaç: seçili tür "seçili", devre dışı türler "Yakında…" ve etkin değil', (t) async {
      final handle = t.ensureSemantics();
      await pumpList(
        t,
        ManagementTypeSelector(value: ManagementType.apartmentSite, onChanged: (_) {}),
        width: 400,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Apartman ve Site')),
        isSemantics(
          isSelected: true,
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          label: 'Apartman ve Site',
        ),
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Rezidans, Yakında…')),
        isSemantics(
          isSelected: false,
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
          label: 'Rezidans, Yakında…',
        ),
      );
      handle.dispose();
    });

    listMatrix('salt okunur (düzenleme): tek çip + açıklama, seçim satırı yok', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      await pumpList(
        t,
        const ManagementTypeSelector(
          value: ManagementType.residence,
          onChanged: null,
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.widgetWithText(StatusChip, 'Rezidans'), findsOneWidget);
      expect(find.text('Yönetim türü site kurulduktan sonra değiştirilemez.'), findsOneWidget);
      expect(_radioOn, findsNothing);
      expect(_radioOff, findsNothing);
      expect(find.text('Yakında…'), findsNothing);
    });
  });

  group('SetupSiteDialog', () {
    layoutMatrix('Site Adı ile İl arasında seçici, taşma yok', (t, w, h, s, dark) async {
      final auth = _SetupAuth();
      await openDialogAt(
        t,
        (context) => SetupSiteDialog.show(context, authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await scrollTo(t, find.text('Yönetim Türü'));
      expect(find.text('Apartman ve Site'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(4));

      // Sıra: Site Adı < Yönetim Türü < İl.
      final name = t.getTopLeft(find.widgetWithText(TextFormField, 'Site Adı *')).dy;
      final type = t.getTopLeft(find.text('Yönetim Türü')).dy;
      final city = t.getTopLeft(find.text('İl')).dy;
      expect(name, lessThan(type));
      expect(type, lessThan(city));
    });

    testWidgets('kurulum managementType olarak apartment_site iletir (devre dışı türe dokunmak etkisiz)', (t) async {
      final auth = _SetupAuth();
      await openDialogAt(
        t,
        (context) => SetupSiteDialog.show(context, authService: auth),
        width: 400,
        height: 1400,
        scale: 1.0,
        dark: false,
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Site Adı *'), 'Güneş Sitesi');
      await scrollTo(t, find.text('Kooperatif'));
      await t.tap(find.text('Kooperatif'));
      await t.pump();
      expect(_radioOn, findsOneWidget);

      await scrollTo(t, find.text('Site Kurulumunu Tamamla'));
      await t.tap(find.text('Site Kurulumunu Tamamla'));
      await settleFor(t, 800);
      expect(auth.types, <String?>['apartment_site']);
    });
  });

  group('SiteDialog', () {
    layoutMatrix('yeni site: seçici Site Adı ile İl arasında', (t, w, h, s, dark) async {
      await openDialogAt(
        t,
        (context) => SiteDialog.show(context, authService: _SetupAuth()),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await scrollTo(t, find.text('Yönetim Türü'));
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(4));
      final name = t.getTopLeft(find.widgetWithText(TextFormField, 'Site Adı')).dy;
      final type = t.getTopLeft(find.text('Yönetim Türü')).dy;
      final city = t.getTopLeft(find.text('İl (opsiyonel)')).dy;
      expect(name, lessThan(type));
      expect(type, lessThan(city));
    });

    testWidgets('yeni site: sonuç yönetim türünü taşır (apartment_site)', (t) async {
      SiteFormResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await SiteDialog.show(context, authService: _SetupAuth());
        },
        width: 400,
        height: 1400,
        scale: 1.0,
        dark: false,
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Site Adı'), 'Gül Sitesi');
      await scrollTo(t, find.text('Kaydet'));
      await t.tap(find.text('Kaydet'));
      await settleFor(t);
      expect(result, isNotNull);
      expect(result!.managementType, ManagementType.apartmentSite);
    });

    layoutMatrix('düzenleme: tür salt okunur çip, seçim satırı yok', (t, w, h, s, dark) async {
      final site = SiteRecord.fromJson(<String, dynamic>{
        'id': 101,
        'name': 'Güneş Sitesi',
        'block_count': 1,
        'apartment_count': 10,
        'door_count': 1,
        'approval_status': 'approved',
        'block_apartment_counts': <int>[10],
        'management_type': 'apartment_site',
        'management_type_label': 'Apartman ve Site',
      });
      await openDialogAt(
        t,
        (context) => SiteDialog.show(context, authService: _SetupAuth(), site: site),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await scrollTo(t, find.text('Yönetim Türü'));
      expect(find.widgetWithText(StatusChip, 'Apartman ve Site'), findsOneWidget);
      expect(_radioOn, findsNothing);
      expect(find.text('Yönetim türü site kurulduktan sonra değiştirilemez.'), findsOneWidget);
    });
  });

  group('SiteCard tür çipi', () {
    listMatrix('varsayılan site: "Apartman ve Site"; Rezidans etiketi sunucudan gelir', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final plain = fxSite();
      final residence = SiteRecord.fromJson(<String, dynamic>{
        'id': 5899864200,
        'name': 'Çok Uzun Adlı Rezidans Yaşam Merkezi Sitesi',
        'approval_status': 'approved',
        'management_type': 'residence',
        'management_type_label': 'Rezidans',
      });
      await pumpList(
        t,
        Column(
          children: [
            SiteCard(
              site: plain,
              selected: false,
              formattedCreatedAt: '01.10.2026 12:30',
              deleteBusy: false,
              approvalBusy: false,
              onTap: () {},
            ),
            const SizedBox(height: 12),
            SiteCard(
              site: residence,
              selected: false,
              formattedCreatedAt: '01.10.2026 12:30',
              deleteBusy: false,
              approvalBusy: false,
              onTap: () {},
            ),
          ],
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.widgetWithText(StatusChip, 'Apartman ve Site'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Rezidans'), findsOneWidget);
    });
  });
}
