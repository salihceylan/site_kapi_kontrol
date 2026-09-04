import 'package:flutter/material.dart';
import '../../models/door_record.dart';
import '../../models/door_runtime_status.dart';
import '../../models/site_record.dart';
import '../../services/voice_door_service.dart';
import '../../styles/app_colors.dart';
import '../../styles/app_decorations.dart';

class ResidentDoorRemoteCard extends StatelessWidget {
  const ResidentDoorRemoteCard({
    super.key,
    required this.selectedSite,
    required this.selectedDoor,
    required this.doors,
    required this.runtimeStatus,
    required this.isLoadingStatus,
    required this.isOpeningDoor,
    this.canTryLocalDoorOpen = false,
    this.isPhoneOnWifi = false,
    required this.onSelectDoor,
    required this.onOpenDoor,
    required this.onCreateGuestPass,
    this.voiceDoorService,
    required this.roleColor,
  });

  final SiteRecord? selectedSite;
  final DoorRecord? selectedDoor;
  final List<DoorRecord> doors;
  final DoorRuntimeStatus? runtimeStatus;
  final bool isLoadingStatus;
  final bool isOpeningDoor;
  final bool canTryLocalDoorOpen;
  final bool isPhoneOnWifi;
  final ValueChanged<int> onSelectDoor;
  final VoidCallback onOpenDoor;
  final VoidCallback onCreateGuestPass;
  final VoiceDoorService? voiceDoorService;
  final Color roleColor;

  @override
  Widget build(BuildContext context) {
    final isDeviceAssigned = selectedDoor?.assignedDeviceUid != null &&
        selectedDoor!.assignedDeviceUid!.trim().isNotEmpty;
    final isCloudOnline = runtimeStatus?.mqttConnected == true;
    final isLocalOnline = !isCloudOnline && canTryLocalDoorOpen;

    final commandEnabled = isDeviceAssigned &&
        (isCloudOnline || isLocalOnline) &&
        !isOpeningDoor &&
        !isLoadingStatus;

    String statusText;
    Color statusColor;
    if (!isDeviceAssigned) {
      statusText = 'Bu kapıya henüz cihaz atanmamış.';
      statusColor = AppColors.roseLight;
    } else if (isOpeningDoor) {
      statusText = 'Kapı tetikleniyor, lütfen bekleyin...';
      statusColor = const Color(0xFF93C5FD);
    } else if (isLoadingStatus) {
      statusText = 'Cihaz durumu kontrol ediliyor...';
      statusColor = AppColors.textMutedLight;
    } else if (isCloudOnline) {
      statusText = '🟢 Çevrimiçi - Kapıyı açmak için dokunun';
      statusColor = AppColors.emeraldLight;
    } else if (isLocalOnline) {
      statusText = '🟡 Yerel Ağda Aktif - Kapıyı açmak için dokunun';
      statusColor = AppColors.amberLight;
    } else {
      statusText = '🔴 Cihaz Çevrimdışı';
      statusColor = AppColors.roseLight;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: AppDecorations.glassCard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Üst Kapsül Rozet
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isLocalOnline
                      ? AppColors.amber.withValues(alpha: 0.18)
                      : AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isLocalOnline
                        ? AppColors.amber.withValues(alpha: 0.45)
                        : AppColors.primaryLight.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isLocalOnline
                          ? AppColors.amber.withValues(alpha: 0.2)
                          : AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLocalOnline ? Icons.wifi_rounded : Icons.sensors_rounded,
                      size: 14,
                      color: isLocalOnline ? AppColors.amberLight : const Color(0xFF93C5FD),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLocalOnline ? 'AHBU YEREL AĞ GEÇİŞ' : 'AHBU AKILLI GEÇİŞ',
                      style: TextStyle(
                        color: isLocalOnline
                            ? AppColors.amberLight
                            : const Color(0xFF93C5FD),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Site Adı
              Text(
                selectedSite?.name ?? (doors.isNotEmpty ? doors.first.doorName : 'Site Kapısı'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),

              // Kapı Adı
              Text(
                selectedDoor != null
                    ? '🚪 ${selectedDoor!.doorName}'
                    : 'Kapı Seçilmedi',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMutedLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),

              // Birden fazla kapı varsa: Hızlı Yatay Kapı Seçici
              if (doors.length > 1) ...[
                const SizedBox(height: 18),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final door in doors)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(door.doorName),
                            selected: selectedDoor?.id == door.id,
                            selectedColor: AppColors.primary,
                            backgroundColor: const Color(0x1AFFFFFF),
                            labelStyle: TextStyle(
                              color: selectedDoor?.id == door.id
                                  ? Colors.white
                                  : const Color(0xFFCBD5E1),
                              fontWeight: selectedDoor?.id == door.id
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              fontSize: 12.5,
                            ),
                            side: BorderSide(
                              color: selectedDoor?.id == door.id
                                  ? AppColors.accent
                                  : const Color(0x22FFFFFF),
                              width: selectedDoor?.id == door.id ? 1.5 : 1.0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                onSelectDoor(door.id);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 26),

              // DEV DAİRESEL DOKUNSAL KAPI AÇ BUTONU (180x180 px)
              GestureDetector(
                onTap: commandEnabled ? onOpenDoor : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: commandEnabled
                        ? (isLocalOnline
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                              )
                            : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                              ))
                        : const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          ),
                    boxShadow: commandEnabled
                        ? (isLocalOnline
                            ? const [
                                BoxShadow(
                                  color: Color(0x70F59E0B),
                                  blurRadius: 36,
                                  spreadRadius: 4,
                                  offset: Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Color(0x30FFFFFF),
                                  blurRadius: 8,
                                  offset: Offset(0, -3),
                                ),
                              ]
                            : const [
                                BoxShadow(
                                  color: Color(0x703B82F6),
                                  blurRadius: 36,
                                  spreadRadius: 4,
                                  offset: Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Color(0x30FFFFFF),
                                  blurRadius: 8,
                                  offset: Offset(0, -3),
                                ),
                              ])
                        : const [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                    border: Border.all(
                      color: commandEnabled
                          ? (isLocalOnline
                              ? const Color(0xFFFDE047)
                              : const Color(0xFF93C5FD))
                          : const Color(0x22FFFFFF),
                      width: 2.4,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: commandEnabled ? onOpenDoor : null,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isOpeningDoor) ...[
                              const SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'AÇILIYOR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ] else ...[
                              Icon(
                                commandEnabled
                                    ? (isLocalOnline
                                        ? Icons.wifi_rounded
                                        : Icons.lock_open_rounded)
                                    : Icons.lock_outline_rounded,
                                size: 50,
                                color: commandEnabled
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                commandEnabled
                                    ? (isLocalOnline
                                        ? 'YEREL AĞDAN AÇ'
                                        : 'KAPIYI AÇ')
                                    : (isDeviceAssigned ? 'ÇEVRİMDİŞI' : 'KAPALI'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: commandEnabled
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // Durum Mesajı
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              // IP Bilgisi Rozetleri (Yerel LAN & Genel WAN)
              if (runtimeStatus != null &&
                  ((runtimeStatus!.localIp != null && runtimeStatus!.localIp!.isNotEmpty) ||
                      (runtimeStatus!.publicIp != null && runtimeStatus!.publicIp!.isNotEmpty))) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (runtimeStatus!.localIp != null && runtimeStatus!.localIp!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x1A10B981),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x4010B981), width: 1),
                        ),
                        child: Text(
                          'Yerel IP: ${runtimeStatus!.localIp}',
                          style: const TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (runtimeStatus!.publicIp != null && runtimeStatus!.publicIp!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x1A3B82F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x403B82F6), width: 1),
                        ),
                        child: Text(
                          'Genel IP: ${runtimeStatus!.publicIp}',
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (voiceDoorService != null) ...[
          const SizedBox(height: 16),
          _buildVoiceLiveBanner(context, roleColor),
        ],
        const SizedBox(height: 16),
        // Kurye / Misafir Geçişi Butonu
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0x1A3B82F6), Color(0x101E293B)],
            ),
            border: Border.all(color: const Color(0x333B82F6), width: 1.2),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onCreateGuestPass,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.share_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '📦 Kurye / Misafir Geçiş Linki Oluştur',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFFF8FAFC),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Sesli Dinleme Canlı Banner'ı
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
            bannerBg = const Color(0x2A10B981);
            borderColor = AppColors.emerald;
            iconColor = AppColors.emeraldLight;
            bannerIcon = Icons.mic_rounded;
            title = '🎙️ Sesli Dinleme Aktif';
            subtitle = vService.recognizedWords.isNotEmpty
                ? '"${vService.recognizedWords}"'
                : 'Dinleniyor... "Kapıyı aç" diyebilirsiniz.';
            break;
          case VoiceStatus.processing:
            bannerBg = const Color(0x2A3B82F6);
            borderColor = AppColors.primaryLight;
            iconColor = const Color(0xFF93C5FD);
            bannerIcon = Icons.auto_awesome_rounded;
            title = '🤖 Komut Algılanıyor...';
            subtitle = '"${vService.recognizedWords}"';
            break;
          case VoiceStatus.success:
            bannerBg = const Color(0x2A10B981);
            borderColor = AppColors.emerald;
            iconColor = AppColors.emeraldLight;
            bannerIcon = Icons.lock_open_rounded;
            title = '🔓 Kapı Açılıyor!';
            subtitle = 'Sesli komut onaylandı, kapı tetikleniyor...';
            break;
          case VoiceStatus.error:
            bannerBg = const Color(0x2AEF4444);
            borderColor = AppColors.rose;
            iconColor = AppColors.roseLight;
            bannerIcon = Icons.error_outline_rounded;
            title = '⚠️ Sesli Komut Hatası';
            subtitle = vService.feedbackText.isNotEmpty ? vService.feedbackText : 'Bilinmeyen hata';
            break;
          case VoiceStatus.idle:
          case VoiceStatus.initializing:
            bannerBg = const Color(0xFF1E293B).withValues(alpha: 0.8);
            borderColor = const Color(0x22FFFFFF);
            iconColor = AppColors.textMutedLight;
            bannerIcon = Icons.mic_none_rounded;
            title = '🎙️ Sesli Kapı Açma';
            subtitle = 'Başlatmak için dokunun';
            break;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(bannerIcon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: iconColor.withValues(alpha: 0.15),
                ),
                onPressed: () {
                  if (isListening) {
                    vService.stopListening();
                  } else {
                    vService.startListening();
                  }
                },
                icon: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
