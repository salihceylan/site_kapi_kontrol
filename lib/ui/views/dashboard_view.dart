import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/role_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

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
    required this.onSelectSite,
    required this.onSelectDoor,
    required this.onOpenDoor,
    required this.onCreateGuestPass,
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
  final ValueChanged<int> onSelectSite;
  final ValueChanged<int> onSelectDoor;
  final VoidCallback onOpenDoor;
  final VoidCallback onCreateGuestPass;

  @override
  Widget build(BuildContext context) {
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
        _buildDoorControlPanel(context),
      ],
    );
  }

  Widget _buildDoorControlPanel(BuildContext context) {
    Widget buildStatus() {
      if (selectedDoor == null) {
        return const Text(
          'Kontrol etmek için önce siteyi, sonra o siteye ait kapıyı seçin.',
          style: TextStyle(color: AppColors.textMuted),
        );
      }

      if (selectedDoor!.assignedDeviceUid == null ||
          selectedDoor!.assignedDeviceUid!.trim().isEmpty) {
        return const Text(
          'Bu kapıya henüz cihaz atanmamış. Kapı açma komutu aktif olmaz.',
          style: TextStyle(color: Colors.red),
        );
      }

      final connectionText = runtimeStatus == null
          ? 'Bilinmiyor'
          : runtimeStatus!.mqttBridgeConnected
              ? 'Hazır'
              : 'Hazır değil';
      final deviceOnlineText = runtimeStatus == null
          ? 'Bilinmiyor'
          : runtimeStatus!.mqttConnected
              ? 'Online'
              : 'Offline';
      final stateText = runtimeStatus?.doorLocked == null
          ? 'Bilinmiyor'
          : (runtimeStatus!.doorLocked! ? 'Kapalı/Kilitli' : 'Açık');
      final signalText = runtimeStatus?.wifiSignalPercent == null
          ? '-'
          : '%${runtimeStatus!.wifiSignalPercent}'
              '${runtimeStatus!.wifiRssi == null ? '' : ' (${runtimeStatus!.wifiRssi} dBm)'}';
      final commandEnabled =
          (runtimeStatus?.commandEnabled == true || canTryLocalDoorOpen) &&
              !isOpeningDoor;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cihaz: ${selectedDoor!.assignedDeviceUid}'),
          const SizedBox(height: 6),
          Text('Sunucu MQTT: $connectionText'),
          const SizedBox(height: 6),
          Text('Cihaz Bağlantısı: $deviceOnlineText'),
          const SizedBox(height: 6),
          Text('Kapı Durumu: $stateText'),
          const SizedBox(height: 6),
          Text(
            'Yerel Ağ Kontrolü: ${canTryLocalDoorOpen ? 'Hazır' : 'Hazır değil'}',
          ),
          const SizedBox(height: 6),
          Text('Firmware: ${runtimeStatus?.firmwareVersion ?? '-'}'),
          const SizedBox(height: 6),
          Text('OTA Durumu: ${runtimeStatus?.otaStatus ?? '-'}'),
          const SizedBox(height: 6),
          Text('Wi-Fi Gücü: $signalText'),
          if (runtimeStatus?.lastSeenAt != null) ...[
            const SizedBox(height: 6),
            Text('Son Güncelleme: ${formatDateTime(runtimeStatus!.lastSeenAt)}'),
          ],
          if (isLoadingStatus) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (doorStatusError != null) ...[
            const SizedBox(height: 8),
            Text(
              doorStatusError!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: commandEnabled ? onOpenDoor : null,
              icon: const Icon(Icons.lock_open),
              label: Text(isOpeningDoor ? 'Gönderiliyor' : 'Kapı Aç'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCreateGuestPass,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Kurye / Misafir Geçişi Oluştur'),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.glassCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kapı Aç / Kapat',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Önce siteyi seçin, sonra o siteye ait kapıyı seçin. Kapıya cihaz atanmış ve MQTT bağlantısı sağlıklıysa kapı açma komutu aktif olur.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: selectedSite?.id,
            decoration: const InputDecoration(labelText: 'Site seç'),
            items: [
              for (final site in sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text('${site.name} (${site.id})'),
                ),
            ],
            onChanged: isLoadingSites
                ? null
                : (value) {
                    if (value != null) {
                      onSelectSite(value);
                    }
                  },
          ),
          if (isLoadingSites) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selectedDoor?.id,
            decoration: const InputDecoration(labelText: 'Kapı seç'),
            items: [
              for (final door in doors)
                DropdownMenuItem<int>(
                  value: door.id,
                  child: Text(
                    '${door.doorName} - ${door.assignedDeviceUid ?? 'Cihaz yok'}',
                  ),
                ),
            ],
            onChanged: isLoadingStructure || doors.isEmpty
                ? null
                : (value) {
                    if (value != null) {
                      onSelectDoor(value);
                    }
                  },
          ),
          if (isLoadingStructure) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 14),
          buildStatus(),
        ],
      ),
    );
  }
}

