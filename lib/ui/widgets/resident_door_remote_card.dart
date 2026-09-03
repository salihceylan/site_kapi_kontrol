import 'package:flutter/material.dart';
import '../../models/door_record.dart';
import '../../models/door_runtime_status.dart';
import '../../models/site_record.dart';
import '../../services/voice_door_service.dart';
import '../../styles/app_colors.dart';

class ResidentDoorRemoteCard extends StatelessWidget {
  const ResidentDoorRemoteCard({
    super.key,
    required this.selectedSite,
    required this.selectedDoor,
    required this.doors,
    required this.runtimeStatus,
    required this.isLoadingStatus,
    required this.isOpeningDoor,
    required this.canTryLocalDoorOpen,
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
    final isLocalReady = canTryLocalDoorOpen;

    final commandEnabled = isDeviceAssigned &&
        (isCloudOnline || isLocalReady) &&
        !isOpeningDoor &&
        !isLoadingStatus;

    String statusText;
    Color statusColor;
    if (!isDeviceAssigned) {
      statusText = 'Bu kapıya henüz cihaz atanmamış.';
      statusColor = const Color(0xFFF87171);
    } else if (isOpeningDoor) {
      statusText = 'Kapı açılıyor, lütfen bekleyin...';
      statusColor = const Color(0xFF93C5FD);
    } else if (isLoadingStatus) {
      statusText = 'Cihaz durumu kontrol ediliyor...';
      statusColor = const Color(0xFF94A3B8);
    } else if (isCloudOnline) {
      statusText = '🟢 Online (Bulut) - Kapıyı açmak için dokunun';
      statusColor = const Color(0xFF4ADE80);
    } else if (isLocalReady) {
      statusText = '🟡 Yerel Ağda Aktif (İnternetsiz Wi-Fi) - Kapıyı açmak için dokunun';
      statusColor = const Color(0xFFFBBF24);
    } else {
      statusText = '🔴 Cihaz Çevrimdışı (Offline) - Kapı açılamaz';
      statusColor = const Color(0xFFF87171);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF1E293B),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
            border: Border.all(color: const Color(0x28FFFFFF), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // AHBU Rozeti
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x333B82F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x663B82F6)),
                ),
                child: const Text(
                  'AHBU AKILLI GEÇİŞ',
                  style: TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Site Adı
              Text(
                selectedSite?.name ?? (doors.isNotEmpty ? doors.first.doorName : 'Site Kapısı'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
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
                  color: Color(0xFF94A3B8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Birden fazla kapı varsa: Hızlı Yatay Kapı Seçici
              if (doors.length > 1) ...[
                const SizedBox(height: 16),
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
                            selectedColor: const Color(0xFF2563EB),
                            backgroundColor: const Color(0x1FFFFFFF),
                            labelStyle: TextStyle(
                              color: selectedDoor?.id == door.id
                                  ? Colors.white
                                  : const Color(0xFFCBD5E1),
                              fontWeight: selectedDoor?.id == door.id
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 12.5,
                            ),
                            side: BorderSide(
                              color: selectedDoor?.id == door.id
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0x33FFFFFF),
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

              const SizedBox(height: 24),

              // DEV DAİRESEL KAPI AÇ BUTONU (170x170 px)
              GestureDetector(
                onTap: commandEnabled ? onOpenDoor : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: commandEnabled
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF334155), Color(0xFF1E293B)],
                          ),
                    boxShadow: commandEnabled
                        ? const [
                            BoxShadow(
                              color: Color(0x662563EB),
                              blurRadius: 28,
                              offset: Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Color(0x22FFFFFF),
                              blurRadius: 6,
                              offset: Offset(0, -2),
                            ),
                          ]
                        : [],
                    border: Border.all(
                      color: commandEnabled
                          ? const Color(0x8060A5FA)
                          : const Color(0x22FFFFFF),
                      width: 2,
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
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'AÇILIYOR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ] else ...[
                              Icon(
                                commandEnabled
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_outline_rounded,
                                size: 46,
                                color: commandEnabled
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                commandEnabled ? 'KAPIYI AÇ' : 'KAPALI',
                                style: TextStyle(
                                  color: commandEnabled
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
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

              const SizedBox(height: 20),

              // Durum Mesajı
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
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
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              side: BorderSide(color: Colors.grey.shade300, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
            ),
            onPressed: onCreateGuestPass,
            icon: const Icon(Icons.share_rounded, color: AppColors.primary, size: 20),
            label: const Text(
              '📦 Kurye / Misafir Geçiş Linki Oluştur',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.primary,
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
            bannerBg = const Color(0xFFE8F5E9);
            borderColor = Colors.green.shade400;
            iconColor = Colors.green.shade700;
            bannerIcon = Icons.mic;
            title = '🎙️ Sesli Dinleme Aktif';
            subtitle = vService.recognizedWords.isNotEmpty
                ? '"${vService.recognizedWords}"'
                : 'Dinleniyor... "Kapıyı aç" diyebilirsiniz.';
            break;
          case VoiceStatus.processing:
            bannerBg = const Color(0xFFE3F2FD);
            borderColor = Colors.blue.shade400;
            iconColor = Colors.blue.shade700;
            bannerIcon = Icons.auto_awesome;
            title = '🤖 Komut Algılanıyor...';
            subtitle = '"${vService.recognizedWords}"';
            break;
          case VoiceStatus.success:
            bannerBg = const Color(0xFFE8F5E9);
            borderColor = Colors.green.shade600;
            iconColor = Colors.green.shade800;
            bannerIcon = Icons.lock_open_rounded;
            title = '🔓 Kapı Açılıyor!';
            subtitle = 'Sesli komut onaylandı, kapı tetikleniyor...';
            break;
          case VoiceStatus.error:
            bannerBg = const Color(0xFFFFEBEE);
            borderColor = Colors.red.shade300;
            iconColor = Colors.red.shade700;
            bannerIcon = Icons.error_outline_rounded;
            title = '⚠️ Sesli Komut Hatası';
            subtitle = vService.feedbackText.isNotEmpty ? vService.feedbackText : 'Bilinmeyen hata';
            break;
          case VoiceStatus.idle:
          case VoiceStatus.initializing:
            bannerBg = const Color(0xFFF8FAFC);
            borderColor = Colors.grey.shade300;
            iconColor = Colors.grey.shade600;
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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Icon(bannerIcon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: iconColor.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  if (isListening) {
                    vService.stopListening();
                  } else {
                    vService.startListening();
                  }
                },
                icon: Icon(
                  isListening ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                  color: iconColor,
                  size: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
