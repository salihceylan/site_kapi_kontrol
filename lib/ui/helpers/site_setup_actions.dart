import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show ImportKind;
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_definition_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_opening_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/setup_screen_route.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/views/finance_view.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_controller.dart';

/// Kurulum sihirbazı adımlarının MEVCUT ekran ve formları açan eylemleri (P2-15).
///
/// Sihirbaz bu ekranları yeniden yazmaz: her eylem var olan pencereyi / sayfayı aynen açar, dönünce sihirbazın
/// denetleyicisini bilgilendirir ([SiteSetupController.noteChanged]); durum özeti sunucudan yeniden okunur ve adım
/// kendiliğinden tamamlanır. Kaydırma ve "aşağı çekip yenile" kabuğu ana sayfadakiyle aynıdır ([pushSetupScreen]).
abstract final class SiteSetupActions {
  /// Site kaydını düzenleme (ad, adres, il / ilçe, blok ve daire sayıları). Sunucu bunu YALNIZ süper kullanıcıya açar
  /// (`PATCH /manager/sites/:id` -> 403); yönetici için eylem sunulmaz, çağıran düğmeyi göstermez.
  static Future<void> editSite(BuildContext context, SiteSetupController c) async {
    final site = c.snapshot.structure?.site;
    if (site == null || !c.isSuperUser) return;
    final result = await SiteDialog.show(context, authService: c.authService, site: site);
    if (result == null || !context.mounted) return;
    final error = await c.authService.updateSite(
      siteCode: site.id,
      name: result.name,
      address: result.address.isEmpty ? null : result.address,
      city: result.city.isEmpty ? null : result.city,
      district: result.district.isEmpty ? null : result.district,
      blockApartmentCounts: result.blockApartmentCounts,
      doorCount: result.doorCount,
      managerUserCode: result.managerUserCode,
    );
    if (!context.mounted) return;
    if (error != null) {
      AppSnack.show(context, error, kind: AppSnackKind.error);
      return;
    }
    AppSnack.show(context, 'Site güncellendi.', kind: AppSnackKind.success);
    await c.noteChanged();
  }

  /// Excel / CSV ile toplu yükleme sihirbazı (mevcut «Toplu Yükle»): [kind] önseçili gelir (varsayılan «Hepsi bir
  /// arada»: daireler, sakinler ve araçlar tek dosyada).
  static Future<void> importFromExcel(
    BuildContext context,
    SiteSetupController c, {
    ImportKind kind = ImportKind.allInOne,
  }) async {
    final outcome = await BulkImportView.open(context, scope: c.scope, initialKind: kind);
    if (outcome?.changed == true) await c.noteChanged();
  }

  /// Kişiler ekranı (mevcut «Kişiler»): site ve sekme (0 Kişiler, 1 Daireler, 2 Araçlar) önseçili açılır.
  static Future<void> openPeople(BuildContext context, SiteSetupController c, {int tab = 0}) async {
    final key = GlobalKey<PeopleViewState>();
    var changed = false;
    await pushSetupScreen<void>(
      context,
      title: 'Kişiler',
      onRefresh: () async => key.currentState?.reload(),
      builder: (_) => PeopleView(
        key: key,
        authService: c.authService,
        manageSites: true,
        initialSiteCode: c.siteCode,
        initialTab: tab,
        onDataChanged: () => changed = true,
      ),
    );
    if (changed) await c.noteChanged();
  }

  /// Modüller ekranı (mevcut «Modüller»): site önseçili açılır. Temel modüller zaten açıktır; yönetici diğerlerini
  /// talep eder, süper kullanıcı doğrudan açar.
  static Future<void> openModules(BuildContext context, SiteSetupController c) async {
    final key = GlobalKey<ModulesViewState>();
    var changed = false;
    await pushSetupScreen<void>(
      context,
      title: 'Modüller',
      onRefresh: () async => key.currentState?.reload(),
      builder: (_) => ModulesView(
        key: key,
        authService: c.authService,
        initialSiteCode: c.siteCode,
        onModulesChanged: () => changed = true,
      ),
    );
    // Talep gönderme / açma-kapama sonucu ne olursa olsun durum yeniden okunur (modül listesi ve çipler).
    await (changed ? c.noteChanged() : c.refresh());
  }

  /// «Yeni Tanım» penceresi (mevcut aidat / ek borç tanımı formu).
  static Future<void> addFeeDefinition(BuildContext context, SiteSetupController c) async {
    final outcome = await FinanceDefinitionFormDialog.show(
      context,
      scope: c.scope,
      onRefreshNeeded: () => unawaited(c.noteChanged()),
    );
    if (outcome == null || !context.mounted) return;
    AppSnack.show(context, outcome.message, kind: AppSnackKind.success);
    await c.noteChanged();
  }

  /// Finans > Daireler > «Devir bakiyesi» penceresi (eski yazılımdan devreden borçlar, Excel ile).
  static Future<void> openOpeningBalances(BuildContext context, SiteSetupController c) async {
    var changed = false;
    await FinanceOpeningDialog.show(context, scope: c.scope, onChanged: () => changed = true);
    if (changed) await c.noteChanged();
  }

  /// Finans ekranı (mevcut «Finans»): site ve sekme (0 Daireler, 1 Tanımlar, 2 Dönemler ...) önseçili açılır.
  static Future<void> openFinance(BuildContext context, SiteSetupController c, {int tab = 1}) async {
    final key = GlobalKey<FinanceViewState>();
    await pushSetupScreen<void>(
      context,
      title: 'Finans',
      onRefresh: () async => key.currentState?.reload(),
      builder: (_) => FinanceView(
        key: key,
        authService: c.authService,
        manageAllSites: c.authService.session?.role == UserRole.superUser,
        sites: <PeopleSite>[PeopleSite(code: c.siteCode, name: c.scope.siteName, canWrite: true, terms: c.snapshot.terms)],
        canReopen: c.authService.session?.role == UserRole.superUser,
        initialSiteCode: c.siteCode,
        initialTab: tab,
      ),
    );
    // Finans ekranında tanım eklenmiş / borçlandırılmış olabilir: durum yeniden okunur (site listeleri etkilenmez).
    await c.refresh();
  }
}
