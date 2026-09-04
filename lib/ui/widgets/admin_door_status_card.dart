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

class AdminDoorStatusCard extends StatelessWidget {
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
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            isExpanded: true,
            key: ValueKey('site_${selectedSite?.id}_${sites.length}'),
            initialValue: (selectedSite != null && sites.any((s) => s.id == selectedSite!.id))
                ? selectedSite!.id
                : (sites.isNotEmpty ? sites.first.id : null),
            key: ValueKey('site_${widget.selectedSite?.id}_${widget.sites.length}'),
            initialValue: (widget.selectedSite != null && widget.sites.any((s) => s.id == widget.selectedSite!.id))
                ? widget.selectedSite!.id
                : (widget.sites.isNotEmpty ? widget.sites.first.id : null),
            decoration: const InputDecoration(labelText: 'Site seç'),
            items: [
              for (final site in sites)
              for (final site in widget.sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text(
                    '${site.name} (${site.id})',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
            ],
            onChanged: isLoadingSites
            onChanged: widget.isLoadingSites
                ? null
                : (value) {
                    if (value != null) {
                      onSelectSite(value);
                      widget.onSelectSite(value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            key: ValueKey('door_${selectedDoor?.id}_${doors.length}'),
            initialValue: (selectedDoor != null && doors.any((d) => d.id == selectedDoor!.id))
                ? selectedDoor!.id
                : (doors.isNotEmpty ? doors.first.id : null),
            key: ValueKey('door_${widget.selectedDoor?.id}_${widget.doors.length}'),
            initialValue: (widget.selectedDoor != null && widget.doors.any((d) => d.id == widget.selectedDoor!.id))
                ? widget.selectedDoor!.id
                : (widget.doors.isNotEmpty ? widget.doors.first.id : null),
            decoration: const InputDecoration(labelText: 'Kapı seç'),
            items: [
              for (final door in doors)
              for (final door in widget.doors)
                DropdownMenuItem<int>(
                  value: door.id,
                  child: Text(
                    door.assignedDeviceUid == null
                        ? '${door.doorName} (Cihaz yok)'
                        : '${door.doorName} (${door.assignedDeviceUid})',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
            ],
            onChanged: (isLoadingStructure || doors.isEmpty)
            onChanged: (widget.isLoadingStructure || widget.doors.isEmpty)
                ? null
                : (value) {
                    if (value != null) {
                      onSelectDoor(value);
                      widget.onSelectDoor(value);
                    }
                  },
          ),
          const SizedBox(height: 14),
          if (voiceDoorService != null) ...[
            _buildVoiceLiveBanner(context, session.role.accentColor),
          if (widget.voiceDoorService != null) ...[
            _buildVoiceLiveBanner(context, widget.session.role.accentColor),
            const SizedBox(height: 14),
          ],
          _buildStatus(context),
        ],
      ),
    );
  }

  Widget _buildVoiceLiveBanner(BuildContext context, Color roleColor) {
    final vService = voiceDoorService!;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.2),
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
                padding: const EdgeInsets.all(9),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                onPressed: () {
                  if (isListening) {
                    vService.stopListening();
                  } else {
                    vService.startListening(candidateDoors: doors);
                    vService.startListening(candidateDoors: widget.doors);
                  }
                },
                icon: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: iconColor,
                  size: 20,
                ),
                tooltip: isListening ? 'Durdur' : 'Tekrar Dinle',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatus(BuildContext context) {
    if (selectedDoor == null) {
    if (widget.selectedDoor == null) {
      return const Text(
        'Kontrol etmek için önce siteyi, sonra o siteye ait kapıyı seçin.',
        style: TextStyle(color: AppColors.textMuted),
      );
    }

    if (selectedDoor!.assignedDeviceUid == null ||
        selectedDoor!.assignedDeviceUid!.trim().isEmpty) {
    if (widget.selectedDoor!.assignedDeviceUid == null ||
        widget.selectedDoor!.assignedDeviceUid!.trim().isEmpty) {
      return const Text(
        'Bu kapıya henüz cihaz atanmamış. Kapı açma komutu aktif olmaz.',
        style: TextStyle(color: Colors.red),
      );
    }

    final isDeviceAssigned = selectedDoor?.assignedDeviceUid != null &&
        selectedDoor!.assignedDeviceUid!.trim().isNotEmpty;
    final isCloudOnline = runtimeStatus?.mqttConnected == true;
    final isLocalOnline = !isCloudOnline && canTryLocalDoorOpen;
    final isMqttBridgeConnected = runtimeStatus?.mqttBridgeConnected == true;
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
            ? '🟡 Yerel Ağda Aktif (İnternet Yok)'
            ? '🟡 Yerel Ağda Aktif'
            : '🔴 Çevrimdışı');
    final stateText = isCloudOnline
        ? (runtimeStatus?.doorLocked != null
            ? (runtimeStatus!.doorLocked! ? 'Kapalı/Kilitli' : 'Açık')
        ? (widget.runtimeStatus?.doorLocked != null
            ? (widget.runtimeStatus!.doorLocked! ? 'Kapalı/Kilitli' : 'Açık')
            : 'Bilinmiyor')
        : (isLocalOnline ? 'Canlı (Yerel Ağ)' : 'Bilinmiyor (Çevrimdışı)');
    final signalText = isCloudOnline
        ? (runtimeStatus?.wifiSignalPercent == null
        ? (widget.runtimeStatus?.wifiSignalPercent == null
            ? '-'
            : '%${runtimeStatus!.wifiSignalPercent}'
                '${runtimeStatus!.wifiRssi == null ? '' : ' (${runtimeStatus!.wifiRssi} dBm)'}')
            : '%${widget.runtimeStatus!.wifiSignalPercent}'
                '${widget.runtimeStatus!.wifiRssi == null ? '' : ' (${widget.runtimeStatus!.wifiRssi} dBm)'}')
        : '-';
    final canOperate = isCloudOnline || isLocalOnline;
    final commandEnabled = isDeviceAssigned &&
        canOperate &&
        !isOpeningDoor &&
        !isLoadingStatus;
        !widget.isOpeningDoor &&
        !widget.isLoadingStatus;

    Color statusBgColor;
    Color statusBorderColor;
    Color statusTextColor;
    IconData statusIcon;

    if (isCloudOnline) {
      statusBgColor = const Color(0xFFF0FDF4);
      statusBorderColor = const Color(0xFFBBF7D0);
      statusTextColor = const Color(0xFF15803D);
      statusIcon = Icons.cloud_done_rounded;
    } else if (isLocalOnline) {
      statusBgColor = const Color(0xFFFEFCE8);
      statusBorderColor = const Color(0xFFFEF08A);
      statusTextColor = const Color(0xFFA16207);
      statusIcon = Icons.wifi_rounded;
    } else {
      statusBgColor = const Color(0xFFFEF2F2);
      statusBorderColor = const Color(0xFFFECACA);
      statusTextColor = const Color(0xFFB91C1C);
      statusIcon = Icons.cloud_off_rounded;
    }

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
          'Yerel Ağ Kontrolü: ${isLocalOnline ? 'Aktif (Cihaz Ağda Bulundu)' : (isPhoneOnWifi ? 'Wi-Fi Bağlı (Cihaz Aranıyor)' : 'Wi-Fi Bağlı Değil')}',
        // Açılır / Kapanır Kayar Durum Çubuğu
        InkWell(
          onTap: () {
            setState(() {
              _isDetailsExpanded = !_isDetailsExpanded;
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusBorderColor, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusTextColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    deviceOnlineText,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: statusTextColor,
                    ),
                  ),
                ),
                Text(
                  _isDetailsExpanded ? 'Gizle' : 'Detaylar',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isDetailsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Yerel IP (LAN): ${runtimeStatus?.localIp ?? (isLocalOnline ? 'Canlı Ağda' : '-')}'),
        const SizedBox(height: 6),
        Text('Genel IP (WAN): ${runtimeStatus?.publicIp ?? '-'}'),
        const SizedBox(height: 6),
        Text('Firmware: ${runtimeStatus?.firmwareVersion ?? '-'}'),
        if (session.role == UserRole.superUser) ...[
          const SizedBox(height: 6),
          Text('OTA Durumu: ${runtimeStatus?.otaStatus ?? '-'}'),
        ],
        const SizedBox(height: 6),
        Text('Wi-Fi Gücü: $signalText'),
        if (runtimeStatus?.lastSeenAt != null) ...[
          const SizedBox(height: 6),
          Text('Son Güncelleme: ${formatDateTime(runtimeStatus!.lastSeenAt)}'),
        ],
        if (isLoadingStatus) ...[

        // Açılır Kapanır Kayar Detay Paneli
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
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
        if (doorStatusError != null) ...[
        if (widget.doorStatusError != null) ...[
          const SizedBox(height: 8),
          Text(
            doorStatusError!,
            widget.doorStatusError!,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: commandEnabled ? onOpenDoor : null,
            onPressed: commandEnabled ? widget.onOpenDoor : null,
            style: isLocalOnline && commandEnabled
                ? ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                  )
                : null,
            icon: Icon(isLocalOnline ? Icons.wifi : Icons.lock_open),
            label: Text(
              isOpeningDoor
              widget.isOpeningDoor
                  ? 'Gönderiliyor...'
                  : (isCloudOnline
                      ? 'Kapı Aç'
                      : (isLocalOnline
                          ? 'Kapı Aç (Yerel Wi-Fi)'
                          : 'Cihaz Çevrimdışı')),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCreateGuestPass,
            onPressed: widget.onCreateGuestPass,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Kurye / Misafir Geçişi Oluştur'),
          ),
        ),
        if (onDownloadCredentialsPdf != null && selectedSite != null) ...[
        if (widget.onDownloadCredentialsPdf != null && widget.selectedSite != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDownloadCredentialsPdf,
              onPressed: widget.onDownloadCredentialsPdf,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E3A8A),
                side: const BorderSide(color: Color(0xFF93C5FD)),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text('📄 ${selectedSite!.name} Giriş Şifreleri (PDF)'),
              label: Text('📄 ${widget.selectedSite!.name} Giriş Şifreleri (PDF)'),
            ),
          ),
        ],
        if (onDownloadLogsPdf != null && (selectedDoor != null || selectedSite != null)) ...[
        if (widget.onDownloadLogsPdf != null && (widget.selectedDoor != null || widget.selectedSite != null)) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDownloadLogsPdf,
              onPressed: widget.onDownloadLogsPdf,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0D47A1),
                side: const BorderSide(color: Color(0xFF60A5FA)),
              ),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: Text(
                selectedDoor != null
                    ? '📊 ${selectedDoor!.doorName} Geçiş Logları (PDF)'
                    : '📊 ${selectedSite!.name} Geçiş Logları (PDF)',
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
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

