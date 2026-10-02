import 'package:flutter/material.dart';
import '../../models/door_record.dart';
import '../../models/door_runtime_status.dart';
import '../../models/site_record.dart';
import '../../models/user_role.dart';
import '../../models/user_session.dart';
import '../../services/auth_service.dart';
import '../../services/voice_door_service.dart';
import '../design/app_card.dart';
import '../design/buttons.dart';
import '../design/door_open_button.dart';
import '../design/empty_state.dart';
import '../design/skeleton.dart';
import '../design/status_chip.dart';
import '../design/tokens.dart';
import '../helpers/ui_helpers.dart';
import 'door_logs_accordion.dart';
import 'dynamic_qr_pass_modal.dart';
import 'voice_live_banner.dart';

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
    this.authService,
    this.successTick = 0,
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
  final AuthService? authService;

  /// Kapı açma başarı sayacı: her ARTIŞTA "Kapı Aç" düğmesi başarı tikini gösterir (varsayılan 0 =
  /// bağlı değil). Ebeveyn komut hatasız bitince bir artırır; sıfırlamaya gerek yoktur.
  final int successTick;

  @override
  State<AdminDoorStatusCard> createState() => _AdminDoorStatusCardState();
}

class _AdminDoorStatusCardState extends State<AdminDoorStatusCard> {
  bool _isDetailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final fieldStyle = th.bodyMedium?.copyWith(color: p.text);
    final itemStyle = th.bodyMedium?.copyWith(
      color: p.text,
      fontWeight: FontWeight.w600,
    );

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        level: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Kapı Kontrol & Telemetri',
              trailing: StatusChip(
                label: 'Yönetim',
                tone: AppTone.primary,
                icon: Icons.tune_rounded,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            // Site Seçimi Dropdown
            DropdownButtonFormField<int>(
              isExpanded: true,
              dropdownColor: p.surface,
              style: fieldStyle,
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
                      style: itemStyle,
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
            const SizedBox(height: AppSpace.md),
            // Kapı Seçimi Dropdown
            DropdownButtonFormField<int>(
              isExpanded: true,
              dropdownColor: p.surface,
              style: fieldStyle,
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
                          : '${door.doorName} • ${door.hardwareBadgeText} (${door.assignedDeviceUid})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: itemStyle,
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
            const SizedBox(height: AppSpace.lg),
            if (widget.voiceDoorService != null) ...[
              _buildVoiceLiveBanner(context),
              const SizedBox(height: AppSpace.lg),
            ],
            _buildStatus(context),
          ],
        ),
      ),
    );
  }

  /// Sesli dinleme canlı banner'ı: ortak [VoiceLiveBanner]; dinlemeyi başlatırken bu kartın kapı
  /// listesini aday olarak verir (eski davranış).
  Widget _buildVoiceLiveBanner(BuildContext context) {
    return VoiceLiveBanner(
      service: widget.voiceDoorService!,
      candidateDoors: widget.doors,
    );
  }

  Widget _buildStatus(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final door = widget.selectedDoor;
    if (door == null) {
      // İlk yükleme sürerken ipucu yerine iskelet; yükleme bitince ipucu.
      if (widget.isLoadingSites || widget.isLoadingStructure) {
        return const _StatusSkeleton();
      }
      return const EmptyState.compact(
        icon: Icons.touch_app_rounded,
        title: 'Kontrol etmek için önce siteyi, sonra o siteye ait kapıyı seçin.',
      );
    }

    if (door.assignedDeviceUid == null || door.assignedDeviceUid!.trim().isEmpty) {
      return const InlineNotice(
        message: 'Bu kapıya henüz cihaz atanmamış. Kapı açma komutu aktif olmaz.',
      );
    }

    final isDeviceAssigned = door.assignedDeviceUid != null &&
        door.assignedDeviceUid!.trim().isNotEmpty;
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

    // Durum tonu: bulut çevrimiçi = success, yerel ağ = warning, çevrimdışı = danger.
    final AppTone statusTone;
    final IconData statusIcon;
    if (isCloudOnline) {
      statusTone = AppTone.success;
      statusIcon = Icons.cloud_done_rounded;
    } else if (isLocalOnline) {
      statusTone = AppTone.warning;
      statusIcon = Icons.wifi_rounded;
    } else {
      statusTone = AppTone.danger;
      statusIcon = Icons.cloud_off_rounded;
    }
    final toggleStyle = th.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: p.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Açılır / Kapanır Kayar Durum Çubuğu (tam genişlik)
        SizedBox(
          width: double.infinity,
          child: AppCard(
            tone: statusTone,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.sm,
            ),
            onTap: () {
              setState(() {
                _isDetailsExpanded = !_isDetailsExpanded;
              });
            },
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                StatusChip(
                  label: deviceOnlineText,
                  tone: statusTone,
                  icon: statusIcon,
                  pulse: isCloudOnline,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_isDetailsExpanded ? 'Gizle' : 'Detaylar', style: toggleStyle),
                    const SizedBox(width: AppSpace.xs),
                    AnimatedRotation(
                      turns: _isDetailsExpanded ? 0.5 : 0.0,
                      duration: AppMotion.of(context, AppMotion.base),
                      curve: AppMotion.standard,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
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
            margin: const EdgeInsets.only(top: AppSpace.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
            decoration: BoxDecoration(
              color: p.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: p.border),
            ),
            child: Column(
              children: [
                _buildDetailRow(context, 'Cihaz UID', door.assignedDeviceUid ?? '-'),
                if (door.hasDevice) ...[
                  _buildDetailRow(context, 'Donanım Modeli', door.hardwareModelTitle),
                  _buildDetailRow(context, 'Donanım Hedefi', door.hardwareBadgeText),
                ],
                _buildDetailRow(context, 'Sunucu MQTT', connectionText),
                _buildDetailRow(context, 'Kapı Durumu', stateText),
                _buildDetailRow(
                  context,
                  'Yerel Ağ',
                  isLocalOnline
                      ? 'Aktif (Cihaz Ağda)'
                      : (widget.isPhoneOnWifi ? 'Wi-Fi Bağlı' : 'Wi-Fi Bağlı Değil'),
                ),
                _buildDetailRow(
                  context,
                  'Yerel IP (LAN)',
                  widget.runtimeStatus?.localIp ?? (isLocalOnline ? 'Canlı Ağda' : '-'),
                ),
                _buildDetailRow(context, 'Genel IP (WAN)', widget.runtimeStatus?.publicIp ?? '-'),
                _buildDetailRow(context, 'Firmware', widget.runtimeStatus?.firmwareVersion ?? '-'),
                if (widget.session.role == UserRole.superUser)
                  _buildDetailRow(context, 'OTA Durumu', widget.runtimeStatus?.displayOtaStatus ?? '-'),
                _buildDetailRow(context, 'Wi-Fi Gücü', signalText),
                if (widget.runtimeStatus?.lastSeenAt != null)
                  _buildDetailRow(context, 'Son Güncelleme', formatDateTime(widget.runtimeStatus!.lastSeenAt)),
              ],
            ),
          ),
          crossFadeState: _isDetailsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: _foldDuration(context),
          sizeCurve: AppMotion.standard,
        ),

        if (widget.isLoadingStatus) ...[
          const SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: const LinearProgressIndicator(minHeight: 4),
          ),
        ],
        if (widget.doorStatusError != null) ...[
          const SizedBox(height: AppSpace.sm),
          InlineNotice(message: widget.doorStatusError!),
        ],
        const SizedBox(height: AppSpace.lg),

        // Kapı Aç: tek DoorOpenButton (komut sürerken spinner, başarıda tik)
        DoorOpenButton(
          key: const ValueKey<String>('admin_door_open_button'),
          variant: DoorOpenVariant.bar,
          state: widget.isOpeningDoor
              ? DoorOpenState.opening
              : (commandEnabled ? DoorOpenState.ready : DoorOpenState.disabled),
          label: isCloudOnline
              ? 'Kapı Aç'
              : (isLocalOnline ? 'Kapı Aç (Yerel Wi-Fi)' : 'Cihaz Çevrimdışı'),
          openingLabel: 'Gönderiliyor...',
          doneLabel: 'Gönderildi',
          icon: isLocalOnline ? Icons.wifi : Icons.lock_open_rounded,
          tone: isLocalOnline ? AppTone.warning : AppTone.primary,
          successTick: widget.successTick,
          onPressed: widget.onOpenDoor,
        ),
        const SizedBox(height: AppSpace.md),
        // Kurye / Misafir Geçişi Butonu (site misafir geçişini kapattıysa link açılışta reddedileceği
        // için gösterilmez; diğer kartlarla aynı kural)
        if (door.canCreateGuestPass)
          PrimaryActionButton(
            label: 'Kurye / Misafir Geçişi Oluştur',
            icon: Icons.share_outlined,
            variant: AppButtonVariant.tonal,
            onPressed: widget.onCreateGuestPass,
          ),
        if (door.canShowQrCode) ...[
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            label: '📲 Giriş QR Kodu Göster',
            icon: Icons.qr_code_2_rounded,
            variant: AppButtonVariant.tonal,
            tone: AppTone.success,
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => DynamicQrPassModal(
                  door: door,
                  authService: widget.authService,
                ),
              );
            },
          ),
        ],

        const SizedBox(height: AppSpace.md),
        DoorLogsAccordion(
          selectedSite: widget.selectedSite,
          selectedDoor: door,
          authService: widget.authService,
          onDownloadPdf: widget.onDownloadLogsPdf,
          isOpeningDoor: widget.isOpeningDoor,
        ),
      ],
    );
  }

  /// Akordiyon/detay panelinin katlanma süresi: 200 ms; hareket azaltmada 1 ms. SIFIR süre
  /// KULLANILMAZ: `AnimatedCrossFade` içindeki `AnimatedSize` süre sıfırken kendi `performLayout`'u
  /// içinde yeniden yerleşim ister (Flutter assert'i: "RenderAnimatedSize was mutated in its own
  /// performLayout"); 1 ms görsel olarak anındadır.
  static Duration _foldDuration(BuildContext context) =>
      AppMotion.reduced(context) ? const Duration(milliseconds: 1) : AppMotion.base;

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: th.bodySmall?.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            flex: 3,
            child: Text(
              value,
              style: th.bodySmall?.copyWith(
                color: p.text,
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

/// Kapı/site seçilene kadar (ilk yükleme) durum bölgesinin iskeleti.
///
/// Parıltı (shimmer) KAPALI ([ShimmerScope.active] false): site/kapı değişirken yükleme uzun sürebilir
/// ve kapı paneli başka kodla/testlerle (`pumpAndSettle`) birlikte yaşar; sonsuz animasyon yerine
/// durağan yer tutucu çizilir. Ekran okuyucu "Yükleniyor" der.
class _StatusSkeleton extends StatelessWidget {
  const _StatusSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Yükleniyor',
      child: const ShimmerScope(
        active: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 48, radius: AppRadius.lg),
            SizedBox(height: AppSpace.lg),
            SkeletonBox(height: 52, radius: AppRadius.md),
            SizedBox(height: AppSpace.md),
            SkeletonBox(height: 48, radius: AppRadius.md),
          ],
        ),
      ),
    );
  }
}
