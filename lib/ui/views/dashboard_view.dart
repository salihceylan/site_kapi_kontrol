import 'package:flutter/material.dart';
import '../../models/door_record.dart';
import '../../models/door_runtime_status.dart';
import '../../models/site_record.dart';
import '../../models/user_role.dart';
import '../../models/user_session.dart';
import '../../services/voice_door_service.dart';
import '../../styles/app_colors.dart';
import '../../styles/app_decorations.dart';
import '../../styles/role_theme.dart';
import '../widgets/admin_door_status_card.dart';
import '../widgets/resident_door_remote_card.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.session,
    required this.sites,
    required this.doors,
    required this.selectedSite,
    required this.selectedDoor,
    required this.runtimeStatus,
    required this.isLoadingSites,
    required this.isLoadingStructure,
    required this.isLoadingStatus,
    required this.isOpeningDoor,
    required this.doorStatusError,
    required this.canTryLocalDoorOpen,
    this.isPhoneOnWifi = false,
    required this.onSelectSite,
    required this.onSelectDoor,
    required this.onOpenDoor,
    required this.onCreateGuestPass,
    this.onDownloadCredentialsPdf,
    this.onDownloadLogsPdf,
    this.voiceDoorService,
  });

  final UserSession session;
  final List<SiteRecord> sites;
  final List<DoorRecord> doors;
  final SiteRecord? selectedSite;
  final DoorRecord? selectedDoor;
  final DoorRuntimeStatus? runtimeStatus;
  final bool isLoadingSites;
  final bool isLoadingStructure;
  final bool isLoadingStatus;
  final bool isOpeningDoor;
  final String? doorStatusError;
  final bool canTryLocalDoorOpen;
  final bool isPhoneOnWifi;
  final ValueChanged<int> onSelectSite;
  final ValueChanged<int> onSelectDoor;
  final VoidCallback onOpenDoor;
  final VoidCallback onCreateGuestPass;
  final VoidCallback? onDownloadCredentialsPdf;
  final VoidCallback? onDownloadLogsPdf;
  final VoiceDoorService? voiceDoorService;

  @override
  Widget build(BuildContext context) {
    // SADECE Daire Sakini için Modern Karanlık Akıllı Kumanda Modülü
    if (session.role == UserRole.apartmentOwner) {
      return ResidentDoorRemoteCard(
        selectedSite: selectedSite,
        selectedDoor: selectedDoor,
        doors: doors,
        runtimeStatus: runtimeStatus,
        isLoadingStatus: isLoadingStatus,
        isOpeningDoor: isOpeningDoor,
        canTryLocalDoorOpen: canTryLocalDoorOpen,
        isPhoneOnWifi: isPhoneOnWifi,
        onSelectDoor: onSelectDoor,
        onOpenDoor: onOpenDoor,
        onCreateGuestPass: onCreateGuestPass,
        voiceDoorService: voiceDoorService,
        roleColor: session.role.accentColor,
      );
    }

    // Süper Kullanıcı ve Site Yöneticisi için Klasik Yönetim Paneli
    final dashboardDescription = switch (session.role) {
      UserRole.superUser =>
        'Tüm kullanıcıları, siteleri, cihazları ve kapı erişimlerini yönetebilirsiniz.',
      UserRole.siteManager =>
        'Yetkili olduğunuz siteleri, cihazları ve kapıları yönetebilirsiniz.',
      UserRole.apartmentOwner =>
        'Yetkili olduğunuz kapıları görüp kapı açma komutu verebilirsiniz.',
    };
    final roleColor = session.role.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hoş Geldiniz',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                session.fullName,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(dashboardDescription),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  backgroundColor: roleColor.withValues(alpha: 0.12),
                  side: BorderSide(color: roleColor.withValues(alpha: 0.35)),
                  avatar: Icon(Icons.verified_user_outlined, color: roleColor),
                  label: Text(
                    session.role.label,
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminDoorStatusCard(
          session: session,
          sites: sites,
          doors: doors,
          selectedSite: selectedSite,
          selectedDoor: selectedDoor,
          runtimeStatus: runtimeStatus,
          isLoadingSites: isLoadingSites,
          isLoadingStructure: isLoadingStructure,
          isLoadingStatus: isLoadingStatus,
          isOpeningDoor: isOpeningDoor,
          doorStatusError: doorStatusError,
          canTryLocalDoorOpen: canTryLocalDoorOpen,
          isPhoneOnWifi: isPhoneOnWifi,
          onSelectSite: onSelectSite,
          onSelectDoor: onSelectDoor,
          onOpenDoor: onOpenDoor,
          onCreateGuestPass: onCreateGuestPass,
          onDownloadCredentialsPdf: onDownloadCredentialsPdf,
          onDownloadLogsPdf: onDownloadLogsPdf,
          voiceDoorService: voiceDoorService,
        ),
      ],
    );
  }
}
