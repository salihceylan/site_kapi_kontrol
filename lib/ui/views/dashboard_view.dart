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
  final ValueChanged<int> onSelectSite;
  final ValueChanged<int> onSelectDoor;
  final VoidCallback onOpenDoor;
  final VoidCallback onCreateGuestPass;
  final VoidCallback? onDownloadCredentialsPdf;
  final VoidCallback? onDownloadLogsPdf;
  final VoiceDoorService? voiceDoorService;

  @override
  Widget build(BuildContext context) {
    // SADECE Daire Sakini için Modern Karanlık Akıllı Kumanda
    if (session.role == UserRole.apartmentOwner) {
      return _buildResidentDashboard(context);
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
        _buildDoorControlPanel(context),
      ],
    );
  }

  /// SADECE Daire Sakini için Özel Tasarlanmış "Akıllı Kapı Kumandası"
  Widget _buildResidentDashboard(BuildContext context) {
    final isDeviceAssigned = selectedDoor?.assignedDeviceUid != null &&
        selectedDoor!.assignedDeviceUid!.trim().isNotEmpty;
    final isCloudOnline = runtimeStatus?.mqttConnected == true;
    final canUseLocal = canTryLocalDoorOpen;

    final commandEnabled = isDeviceAssigned &&
        (isCloudOnline || canUseLocal) &&
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
    } else if (canUseLocal) {
      statusText = '🔴 Cihaz Çevrimdışı (Yerel Ağdan Açmayı Deneyin)';
      statusColor = const Color(0xFFF87171);
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
          _buildVoiceLiveBanner(context, session.role.accentColor),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  /// Yönetici ve Süper Kullanıcı için Klasik Yönetim & Kapı Kontrol Paneli
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

      final isDeviceAssigned = selectedDoor?.assignedDeviceUid != null &&
          selectedDoor!.assignedDeviceUid!.trim().isNotEmpty;
      final isCloudOnline = runtimeStatus?.mqttConnected == true;
      final canUseLocal = canTryLocalDoorOpen;

      final isMqttBridgeConnected = runtimeStatus?.mqttBridgeConnected == true;

      final connectionText = isMqttBridgeConnected
          ? 'Hazır (Bulut)'
          : 'Bağlantı Yok';
      final deviceOnlineText = isCloudOnline
          ? '🟢 Online (Bulut)'
          : (runtimeStatus == null
              ? 'Bilinmiyor'
              : '🔴 Çevrimdışı (Offline)');
      final stateText = isCloudOnline
          ? (runtimeStatus?.doorLocked != null
              ? (runtimeStatus!.doorLocked! ? 'Kapalı/Kilitli' : 'Açık')
              : 'Bilinmiyor')
          : 'Bilinmiyor (Cihaz Çevrimdışı)';
      final signalText = isCloudOnline
          ? (runtimeStatus?.wifiSignalPercent == null
              ? '-'
              : '%${runtimeStatus!.wifiSignalPercent}'
                  '${runtimeStatus!.wifiRssi == null ? '' : ' (${runtimeStatus!.wifiRssi} dBm)'}')
          : (runtimeStatus?.wifiSignalPercent == null
              ? '-'
              : '%${runtimeStatus!.wifiSignalPercent} (Son Sinyal)');

      final commandEnabled = isDeviceAssigned &&
          (isCloudOnline || canUseLocal) &&
          !isOpeningDoor &&
          !isLoadingStatus;

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
            'Yerel Ağ Kontrolü: ${canTryLocalDoorOpen ? 'Hazır (Yedek Yetki Var)' : 'Kayıt Yok'}',
          ),
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
          if (onDownloadCredentialsPdf != null && selectedSite != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDownloadCredentialsPdf,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A8A),
                  side: const BorderSide(color: Color(0xFF93C5FD)),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text('📄 ${selectedSite!.name} Giriş Şifreleri (PDF)'),
              ),
            ),
          ],
          if (onDownloadLogsPdf != null && (selectedDoor != null || selectedSite != null)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDownloadLogsPdf,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D47A1),
                  side: const BorderSide(color: Color(0xFF60A5FA)),
                ),
                icon: const Icon(Icons.assignment_outlined, size: 18),
                label: Text(
                  selectedDoor != null
                      ? '📊 ${selectedDoor!.doorName} Geçiş Logları (PDF)'
                      : '📊 ${selectedSite!.name} Geçiş Logları (PDF)',
                ),
              ),
            ),
          ],
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
            isExpanded: true,
            key: ValueKey('site_${selectedSite?.id}_${sites.length}'),
            initialValue: (selectedSite != null && sites.any((s) => s.id == selectedSite!.id))
                ? selectedSite!.id
                : (sites.isNotEmpty ? sites.first.id : null),
            decoration: const InputDecoration(labelText: 'Site seç'),
            items: [
              for (final site in sites)
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
            isExpanded: true,
            key: ValueKey('door_${selectedDoor?.id}_${doors.length}'),
            initialValue: (selectedDoor != null && doors.any((d) => d.id == selectedDoor!.id))
                ? selectedDoor!.id
                : (doors.isNotEmpty ? doors.first.id : null),
            decoration: const InputDecoration(labelText: 'Kapı seç'),
            items: [
              for (final door in doors)
                DropdownMenuItem<int>(
                  value: door.id,
                  child: Text(
                    '${door.doorName} - ${door.assignedDeviceUid ?? 'Cihaz yok'}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
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
