import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// HER ZAMAN site BAŞVURUSU yapan roller: bireysel kullanıcı, daire kullanıcısı ve site yöneticisi.
/// Bir site yöneticisi süper user'dan izin almadan yeni site oluşturamaz; talep süper user onayına düşer.
bool canApplyForSite(UserRole? role) =>
    role == UserRole.individual || role == UserRole.apartmentOwner || role == UserRole.siteManager;

/// Başvuru durumu (`GET .../mine`) izlenen roller: süper kullanıcı hariç tüm roller.
bool tracksSiteApplications(UserRole? role) =>
    role != UserRole.superUser;

/// Bu kullanıcı için "site kur / ekle" BAŞVURU akışı mı?
/// Süper kullanıcı dışındaki herkes (site yöneticisi dahil) süper kullanıcı onayına tabi başvuru akışını kullanır.
bool usesSiteApplicationFlow(UserRole? role, SiteApplicationTracker? tracker) =>
    role != UserRole.superUser;

/// Başvuru formu kapandıktan sonra durumu sunucudan okur: YALNIZ başvuru gönderildiyse (`applied`), zaten
/// bekleyen başvuru varsa (`alreadyPending`) ya da sonuç belirsizse (`uncertain`). Form hiçbir şey
/// göndermeden kapandıysa gereksiz `mine` çağrısı yapılmaz.
void syncApplicationsAfterForm(SiteApplicationTracker? tracker, SetupSiteOutcome? outcome) {
  if (tracker == null) return;
  switch (outcome) {
    case SetupSiteOutcome.applied:
    case SetupSiteOutcome.uncertain:
      unawaited(tracker.noteSubmitted());
    case SetupSiteOutcome.alreadyPending:
    case SetupSiteOutcome.applicationRequired:
      unawaited(tracker.noteChanged());
    case SetupSiteOutcome.created:
    case null:
      break;
  }
}

/// Site başvurusu formunu açar ([previous] verilirse "Yeniden başvur": önceki değerlerle). Form hangi
/// sonuçla kapanırsa kapansın başvuru gönderildiyse / zaten bekleyen varsa / sonuç belirsizse durum sunucudan
/// yeniden okunur ([tracker] verilmişse; bkz. [syncApplicationsAfterForm]).
Future<SetupSiteOutcome?> openSiteApplicationForm(
  BuildContext context, {
  required AuthService authService,
  SiteApplicationTracker? tracker,
  SiteApplication? previous,
  String? deviceUid,
}) async {
  final outcome = await SetupSiteDialog.show(
    context,
    authService: authService,
    mode: SetupSiteMode.application,
    prefill: previous,
    deviceUid: deviceUid,
  );
  syncApplicationsAfterForm(tracker, outcome);
  return outcome;
}

/// Cihaz sahiplenme sonrası bilgi metni. Cihaz sahiplenmek kullanıcıyı site yöneticisi YAPMAZ (rol
/// değişmez); yönetici olmak için "Site Kur" ile başvuru yapılır.
const String kDeviceAddedMessage =
    'Cihaz hesabınıza eklendi. Site yöneticisi olmak için Site Kur ile başvuru yapabilirsiniz.';

/// Cihaz hesaba eklendikten sonra (bireysel / daire kullanıcısı): bilgi penceresi + "Site Kur" eylemi.
///
/// "Site Kur" başvuru formunu eklenen cihaz seçili olarak açar ([openSiteApplicationForm]). Zaten bekleyen
/// bir başvuru varsa form önerilmez (sunucu 409 `APPLICATION_PENDING` döner): yalnız kısa bir ileti çıkar.
/// Rol burada DEĞİŞTİRİLMEZ ve yönetici görünümüne geçilmez.
Future<void> offerSiteApplicationAfterClaim(
  BuildContext context, {
  required AuthService authService,
  required String deviceUid,
  SiteApplicationTracker? tracker,
}) async {
  if (!context.mounted) return;
  if (tracker?.pending != null) {
    AppSnack.show(
      context,
      'Cihaz hesabınıza eklendi.',
      kind: AppSnackKind.success,
      replace: true,
    );
    return;
  }
  final goApply = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: 'Cihaz Eklendi',
      icon: Icons.check_circle_outline,
      tone: AppTone.success,
      actions: [
        TextButton(
          key: const ValueKey<String>('device_added_later'),
          onPressed: () => popIfCurrent(ctx, false),
          child: const Text('Daha Sonra'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('device_added_site_setup'),
          style: filledToneStyle(ctx, tone: AppTone.primary),
          onPressed: () => popIfCurrent(ctx, true),
          child: const Text('Site Kur'),
        ),
      ],
      child: Text(kDeviceAddedMessage, style: Theme.of(ctx).textTheme.bodyMedium),
    ),
  );
  if (goApply != true || !context.mounted) return;
  await openSiteApplicationForm(
    context,
    authService: authService,
    tracker: tracker,
    deviceUid: deviceUid,
  );
}
