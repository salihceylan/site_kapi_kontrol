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
import '../helpers/ui_helpers.dart';

class AdminDoorStatusCard extends StatefulWidget {
  const AdminDoorStatusCard({
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
  State<AdminDoorStatusCard> createState() => _AdminDoorStatusCardState();
}

class _AdminDoorStatusCardState extends State<AdminDoorStatusCard> {
  bool _isDetailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.glassCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kapı Kontrol & Telemetri',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16.5,
                  letterSpacing: -0.3,
                  color: AppColors.textLight,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, color: AppColors.accent, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Yönetim',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Site Seçimi Dropdown
          DropdownButtonFormField<int>(
            isExpanded: true,
            dropdownColor: const Color(0xFF1E293B),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            key: ValueKey('site_${widget.selectedSite?.id}_${widget.sites.length}'),
            initialValue: (widget.selectedSite != null && widget.sites.any((s) => s.id == widget.selectedSite!.id))
                ? widget.selectedSite!.id
                : (widget.sites.isNotEmpty ? widget.sites.first.id : null),
            decoration: const InputDecoration(
              labelText: 'Site Seçin',
              prefixIcon: Icon(Icons.apartment_rounded),
            ),
            items: [
              for (final site in widget.sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text(
                    '${site.name} (${site.id})',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
            onChanged: widget.isLoadingSites
                ? null
                : (value) {
                    if (value != null) {
                      widget.onSelectSite(value);
                    }
                  },
          ),
          const SizedBox(height: 14),
          // Kapı Seçimi Dropdown
          DropdownButtonFormField<int>(
            isExpanded: true,
            dropdownColor: const Color(0xFF1E293B),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            key: ValueKey('door_${widget.selectedDoor?.id}_${widget.doors.length}'),
            initialValue: (widget.selectedDoor != null && widget.doors.any((d) => d.id == widget.selectedDoor!.id))
                ? widget.selectedDoor!.id
                : (widget.doors.isNotEmpty ? widget.doors.first.id : null),
            decoration: const InputDecoration(
              labelText: 'Kapı Seçin',
              prefixIcon: Icon(Icons.sensor_door_rounded),
            ),
            items: [
              for (final door in widget.doors)
                DropdownMenuItem<int>(
                  value: door.id,
                  child: Text(
                    door.assignedDeviceUid == null
                        ? '${door.doorName} (Cihaz yok)'
                        : '${door.doorName} (${door.assignedDeviceUid})',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
            onChanged: (widget.isLoadingStructure || widget.doors.isEmpty)
                ? null
                : (value) {
                    if (value != null) {
                      widget.onSelectDoor(value);
                    }
                  },
          ),
          const SizedBox(height: 16),
          if (widget.voiceDoorService != null) ...[
            _buildVoiceLiveBanner(context, widget.session.role.accentColor),
            const SizedBox(height: 16),
          ],
          _buildStatus(context),
        ],
      ),
    );
  }

  Widget _buildVoiceLiveBanner(BuildContext context, Color roleColor) {
    final vService = widget.voiceDoorService!;
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
            bannerBg = const Color(0xFF0F172A).withValues(alpha: 0.6);
            borderColor = const Color(0x22FFFFFF);
            iconColor = AppColors.textMutedLight;
            bannerIcon = Icons.mic_none_rounded;
            title = '🎙️ Sesli Kapı Açma';
            subtitle = 'Başlatmak için dokunun';
            break;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(bannerIcon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                style: IconButton.styleFrom(backgroundColor: iconColor.withValues(alpha: 0.15)),
                onPressed: () {
                  if (isListening) {
                    vService.stopListening();
                  } else {
                    vService.startListening(candidateDoors: widget.doors);
                  }
                },
                icon: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: iconColor,
                  size: 18,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatus(BuildContext context) {
    if (widget.selectedDoor == null) {
      return const Text(
        'Kontrol etmek için önce siteyi, sonra o siteye ait kapıyı seçin.',
        style: TextStyle(color: AppColors.textMutedLight),
      );
    }

    if (widget.selectedDoor!.assignedDeviceUid == null ||
        widget.selectedDoor!.assignedDeviceUid!.trim().isEmpty) {
      return const Text(
        'Bu kapıya henüz cihaz atanmamış. Kapı açma komutu aktif olmaz.',
        style: TextStyle(color: AppColors.roseLight, fontWeight: FontWeight.w600),
      );
    }

    final isDeviceAssigned = widget.selectedDoor?.assignedDeviceUid != null &&
        widget.selectedDoor!.assignedDeviceUid!.trim().isNotEmpty;
    final isCloudOnline = widget.runtimeStatus?.mqttConnected == true;
    final isLocalOnline = !isCloudOnline && widget.canTryLocalDoorOpen;
    final isMqttBridgeConnected = widget.runtimeStatus?.mqttBridgeConnected == true;

    final connectionText = isMqttBridgeConnected
        ? 'Hazır (Bulut)'
        : 'Bağlantı Yok';
    final deviceOnlineText = isCloudOnline
        ? '🟢 Çevrimiçi (Bulut)'
        : (isLocalOnline
            ? '🟡 Yerel Ağda Aktif'
            : '🔴 Çevrimdışı');
    final stateText = isCloudOnline
        ? (widget.runtimeStatus?.doorLocked != null
            ? (widget.runtimeStatus!.doorLocked! ? 'Kapalı/Kilitli' : 'Açık')
            : 'Bilinmiyor')
        : (isLocalOnline ? 'Canlı (Yerel Ağ)' : 'Bilinmiyor (Çevrimdışı)');
    final signalText = isCloudOnline
        ? (widget.runtimeStatus?.wifiSignalPercent == null
            ? '-'
            : '%${widget.runtimeStatus!.wifiSignalPercent}'
                '${widget.runtimeStatus!.wifiRssi == null ? "" : " (${widget.runtimeStatus!.wifiRssi} dBm)"}')
        : '-';
    final canOperate = isCloudOnline || isLocalOnline;
    final commandEnabled = isDeviceAssigned &&
        canOperate &&
        !widget.isOpeningDoor &&
        !widget.isLoadingStatus;

    Color statusBgColor;
    Color statusBorderColor;
    Color statusTextColor;
    IconData statusIcon;

    if (isCloudOnline) {
      statusBgColor = const Color(0x2010B981);
      statusBorderColor = AppColors.emerald.withValues(alpha: 0.5);
      statusTextColor = AppColors.emeraldLight;
      statusIcon = Icons.cloud_done_rounded;
    } else if (isLocalOnline) {
      statusBgColor = const Color(0x20F59E0B);
      statusBorderColor = AppColors.amber.withValues(alpha: 0.5);
      statusTextColor = AppColors.amberLight;
      statusIcon = Icons.wifi_rounded;
    } else {
      statusBgColor = const Color(0x20EF4444);
      statusBorderColor = AppColors.rose.withValues(alpha: 0.5);
      statusTextColor = AppColors.roseLight;
      statusIcon = Icons.cloud_off_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Açılır / Kapanır Kayar Durum Çubuğu
        InkWell(
          onTap: () {
            setState(() {
              _isDetailsExpanded = !_isDetailsExpanded;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusBorderColor, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusTextColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    deviceOnlineText,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: statusTextColor,
                    ),
                  ),
                ),
                Text(
                  _isDetailsExpanded ? 'Gizle' : 'Detaylar',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMutedLight,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isDetailsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Açılır Kapanır Kayar Detay Paneli (Varsayılan Kapalı)
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x22FFFFFF), width: 1.0),
            ),
            child: Column(
              children: [
                _buildDetailRow('Cihaz UID', widget.selectedDoor!.assignedDeviceUid ?? '-'),
                _buildDetailRow('Sunucu MQTT', connectionText),
                _buildDetailRow('Kapı Durumu', stateText),
                _buildDetailRow(
                  'Yerel Ağ',
                  isLocalOnline
                      ? 'Aktif (Cihaz Ağda)'
                      : (widget.isPhoneOnWifi ? 'Wi-Fi Bağlı' : 'Wi-Fi Bağlı Değil'),
                ),
                _buildDetailRow(
                  'Yerel IP (LAN)',
                  widget.runtimeStatus?.localIp ?? (isLocalOnline ? 'Canlı Ağda' : '-'),
                ),
                _buildDetailRow('Genel IP (WAN)', widget.runtimeStatus?.publicIp ?? '-'),
                _buildDetailRow('Firmware', widget.runtimeStatus?.firmwareVersion ?? '-'),
                if (widget.session.role == UserRole.superUser)
                  _buildDetailRow('OTA Durumu', widget.runtimeStatus?.otaStatus ?? '-'),
                _buildDetailRow('Wi-Fi Gücü', signalText),
                if (widget.runtimeStatus?.lastSeenAt != null)
                  _buildDetailRow('Son Güncelleme', formatDateTime(widget.runtimeStatus!.lastSeenAt)),
              ],
            ),
          ),
          crossFadeState: _isDetailsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),

        if (widget.isLoadingStatus) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (widget.doorStatusError != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.doorStatusError!,
            style: const TextStyle(color: AppColors.roseLight, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 18),

        // Kapı Aç Butonu (Gradientli Lüks Buton)
        Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: commandEnabled
                ? (isLocalOnline
                    ? const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      ))
                : const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  ),
            boxShadow: commandEnabled
                ? [
                    BoxShadow(
                      color: isLocalOnline
                          ? const Color(0x60F59E0B)
                          : const Color(0x602563EB),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: commandEnabled ? widget.onOpenDoor : null,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLocalOnline ? Icons.wifi : Icons.lock_open_rounded,
                      color: commandEnabled ? Colors.white : AppColors.textMuted,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isOpeningDoor
                          ? 'Gönderiliyor...'
                          : (isCloudOnline
                              ? 'Kapı Aç'
                              : (isLocalOnline
                                  ? 'Kapı Aç (Yerel Wi-Fi)'
                                  : 'Cihaz Çevrimdışı')),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: commandEnabled ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Kurye / Misafir Geçişi Butonu
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCreateGuestPass,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Kurye / Misafir Geçişi Oluştur'),
          ),
        ),
        if (widget.onDownloadCredentialsPdf != null && widget.selectedSite != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onDownloadCredentialsPdf,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF93C5FD),
                side: const BorderSide(color: Color(0x403B82F6)),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text('📄 ${widget.selectedSite!.name} Giriş Şifreleri (PDF)'),
            ),
          ),
        ],
        if (widget.onDownloadLogsPdf != null && (widget.selectedDoor != null || widget.selectedSite != null)) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onDownloadLogsPdf,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF60A5FA),
                side: const BorderSide(color: Color(0x4060A5FA)),
              ),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: Text(
                widget.selectedDoor != null
                    ? '📊 ${widget.selectedDoor!.doorName} Geçiş Logları (PDF)'
                    : '📊 ${widget.selectedSite!.name} Geçiş Logları (PDF)',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textMutedLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFF8FAFC),
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
