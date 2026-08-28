import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
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
  final ValueChanged<int> onSelectSite;
  final ValueChanged<int> onSelectDoor;
  final VoidCallback onOpenDoor;
  final VoidCallback onCreateGuestPass;
  final VoiceDoorService? voiceDoorService;

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
        if (voiceDoorService != null) ...[
          const SizedBox(height: 16),
          _buildVoiceLiveBanner(context, roleColor),
        ],
        const SizedBox(height: 16),
        _buildDoorControlPanel(context),
      ],
    );
  }

  Widget _buildVoiceLiveBanner(BuildContext context, Color roleColor) {
    final vService = voiceDoorService!;
    return AnimatedBuilder(
      animation: vService,
      builder: (context, _) {
        final status = vService.status;
        final isListening = vService.isListening;

        Color bannerBg;
        Color borderColor;
        Color iconColor;
        IconData bannerIcon;
        String title;
        String subtitle;

        switch (status) {
          case VoiceStatus.listening:
            bannerBg = const Color(0xFFE8F5E9);
            borderColor = Colors.green.shade400;
            iconColor = Colors.green.shade700;
            bannerIcon = Icons.mic;
            title = '🎙️ Sesli Dinleme Aktif';
            subtitle = vService.recognizedWords.isNotEmpty
                ? '"${vService.recognizedWords}"'
                : 'Dinleniyor... "Kapıyı aç" veya "1. kapıyı aç" diyebilirsiniz.';
            break;
          case VoiceStatus.processing:
            bannerBg = const Color(0xFFE3F2FD);
            borderColor = Colors.blue.shade400;
            iconColor = Colors.blue.shade700;
            bannerIcon = Icons.hourglass_top_rounded;
            title = 'Komut İşleniyor...';
            subtitle = vService.feedbackText;
            break;
          case VoiceStatus.success:
            bannerBg = const Color(0xFFE8F5E9);
            borderColor = Colors.green.shade500;
            iconColor = Colors.green.shade800;
            bannerIcon = Icons.check_circle_outline_rounded;
            title = 'Başarılı';
            subtitle = vService.feedbackText;
            break;
          case VoiceStatus.error:
            bannerBg = const Color(0xFFFFF3E0);
            borderColor = Colors.orange.shade400;
            iconColor = Colors.orange.shade800;
            bannerIcon = Icons.info_outline_rounded;
            title = 'Sesli Komut Bildirimi';
            subtitle = vService.feedbackText;
            break;
          case VoiceStatus.initializing:
            bannerBg = const Color(0xFFF3E5F5);
            borderColor = Colors.purple.shade300;
            iconColor = Colors.purple.shade700;
            bannerIcon = Icons.mic_none_outlined;
            title = 'Ses Motoru Başlatılıyor...';
            subtitle = 'Mikrofon hazırlanıyor...';
            break;
          case VoiceStatus.idle:
            bannerBg = Colors.white;
            borderColor = AppColors.primarySoft.withValues(alpha: 0.25);
            iconColor = roleColor;
            bannerIcon = Icons.mic_none_outlined;
            title = 'Sesli Komut Hazır';
            subtitle = 'Dokunarak sesli dinlemeyi tekrar başlatabilirsiniz.';
            break;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(bannerIcon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () {
                  if (isListening) {
                    vService.stopListening();
                  } else {
                    vService.startListening(candidateDoors: doors);
                  }
                },
                icon: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: iconColor,
                ),
                tooltip: isListening ? 'Durdur' : 'Tekrar Dinle',
              ),
            ],
          ),
        );
      },
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
