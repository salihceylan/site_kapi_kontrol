import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_connectivity_logs_accordion.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// OTA durum metni ([DeviceRecord.displayOtaStatus]) -> ton: Güncel = başarı, İndiriliyor = bilgi,
/// Beklemede = uyarı, Hata = hata; bilinmeyen/boş durum nötr (ton yok).
AppTone? otaStatusTone(String displayStatus) => switch (displayStatus) {
  'Güncel' => AppTone.success,
  'İndiriliyor' => AppTone.info,
  'Beklemede' => AppTone.warning,
  'Hata' => AppTone.danger,
  _ => null,
};

/// Cihaz durum rozeti: normalde [StatusChip]; büyük yazıda (>= 1,75x) etiket tek satır + elips
/// olduğundan kırpılırdı ("KAPI ATANMA…"), bu yüzden aynı tonda sarmalanan düz metin gösterilir
/// (liste ekranındaki grup başlığıyla aynı kural). Metin her iki durumda da aynıdır.
class _DeviceBadge extends StatelessWidget {
  const _DeviceBadge({
    required this.label,
    required this.tone,
    this.icon,
    this.pulse = false,
  });

  final String label;
  final AppTone tone;
  final IconData? icon;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    if (!isLargeText(context)) {
      return StatusChip(label: label, tone: tone, icon: icon, pulse: pulse);
    }
    return Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: tone.ink(context.palette),
      ),
    );
  }
}

class CompanyDeviceCard extends StatefulWidget {
  const CompanyDeviceCard({
    super.key,
    required this.device,
    required this.isSuperUser,
    this.authService,
    required this.onEdit,
    required this.onAssignToDoor,
    required this.onDelete,
    this.onToggleDefect,
    this.onReleaseOwnership,
  });

  final DeviceRecord device;
  final bool isSuperUser;
  final AuthService? authService;
  final VoidCallback onEdit;
  final VoidCallback onAssignToDoor;
  final VoidCallback onDelete;
  final VoidCallback? onToggleDefect;
  final VoidCallback? onReleaseOwnership;

  @override
  State<CompanyDeviceCard> createState() => _CompanyDeviceCardState();
}

class _CompanyDeviceCardState extends State<CompanyDeviceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final device = widget.device;
    final isAssigned = device.assignedDoorId != null && device.assignedDoorId != 0;
    final siteText = device.siteName == null
        ? (device.siteCode == null ? '-' : 'Site ID: ${device.siteCode}')
        : '${device.siteName} (${device.siteCode ?? '-'})';
    final doorText = isAssigned
        ? (device.assignedDoorName ?? 'Kapı #${device.assignedDoorId}')
        : 'Kapı atanmamış';
    final isOnline = device.mqttConnected == true;
    final onlineText = device.mqttConnected == null
        ? 'Bilinmiyor'
        : (isOnline ? 'Online' : 'Offline');
    final hardware = device.hardwareTarget;
    // Süper kullanıcıya listede yalnız dikkat gerektiren OTA durumu (indiriliyor/beklemede/hata)
    // rozet olur; "Güncel" ve bilinmeyen durum ayrıntıda kalır.
    final otaStatus = device.displayOtaStatus;
    final otaTone = otaStatusTone(otaStatus);
    final AppTone? otaChipTone =
        widget.isSuperUser && otaTone != null && otaTone != AppTone.success
        ? otaTone
        : null;

    // Tek yüzey: kart AppCard'dır; kapısız cihaz uyarı tonlu. Durum rozetleri UID'nin altında akar
    // (sağ sütunda sıkışmaz); çevrimiçi rozet nabız atar ve durur. Soldaki cilalı rozet kapıya
    // atanmış (birincil) / atama bekleyen (uyarı) cihazı ayırır; üst hizalıdır (rozetler alta sarınca
    // ortada yüzmez).
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        tone: isAssigned ? null : AppTone.warning,
        padding: listCardPadding(context),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(expanded: _expanded), // Açık/kapalı durumu ekran okuyucuya bildirir (karta birleşir).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isLargeText(context)) ...[
                  IconOrb(
                    icon: !isAssigned
                        ? Icons.door_sliding_outlined
                        : Icons.memory_rounded,
                    tone: !isAssigned ? AppTone.warning : AppTone.primary,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpace.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.deviceUid, style: th.titleMedium),
                      const SizedBox(height: AppSpace.xs),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          _DeviceBadge(
                            label: onlineText,
                            tone: device.mqttConnected == null
                                ? AppTone.neutral
                                : (isOnline ? AppTone.success : AppTone.danger),
                            pulse: isOnline,
                          ),
                          if (hardware != null && hardware.isNotEmpty)
                            _DeviceBadge(
                              label: hardware.toUpperCase(),
                              tone: hardware == 'esp32-wroom'
                                  ? AppTone.violet
                                  : AppTone.primary,
                            ),
                          if (!isAssigned)
                            const _DeviceBadge(
                              label: 'KAPI ATANMAMIŞ',
                              tone: AppTone.warning,
                            ),
                          if (device.isDefective)
                            const _DeviceBadge(
                              label: 'ARIZALI',
                              tone: AppTone.danger,
                              icon: Icons.warning_amber_rounded,
                            ),
                          if (otaChipTone != null)
                            _DeviceBadge(
                              label: 'OTA: $otaStatus',
                              tone: otaChipTone,
                              icon: otaChipTone == AppTone.danger
                                  ? Icons.error_outline_rounded
                                  : Icons.system_update_alt_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Site: $siteText | Kapı: '),
                            TextSpan(
                              text: doorText,
                              style: !isAssigned
                                  ? TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTone.warning.ink(p),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        style: th.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                ExpandChevron(expanded: _expanded),
              ],
            ),
            ExpandableSection(
              expanded: _expanded,
              child: _buildDetails(context, isAssigned),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, bool isAssigned) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final device = widget.device;
    final userText = device.assignedUserCode?.toString() ?? '-';
    final dateText = formatDateTime(device.createdAt);
    final signalText = device.wifiSignalPercent == null
        ? '-'
        : '%${device.wifiSignalPercent}'
              '${device.wifiRssi == null ? '' : ' (${device.wifiRssi} dBm)'}';
    final lastSeenText = formatDateTime(device.lastSeenAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.md),
        const Divider(),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            InfoChip('Kullanıcı ID: $userText'),
            if ((device.ownerFullName ?? device.ownerEmail ?? '').isNotEmpty)
              InfoChip('Sahip: ${device.ownerFullName ?? device.ownerEmail}'),
            if (device.isDefective)
              InfoChip(
                'Arıza Nedeni: ${device.defectiveReason ?? "Belirtilmedi"}',
              ),
            InfoChip('MQTT: ${device.mqttConfigured ? "Hazır" : "Eksik"}'),
            // Sürüm ve OTA durumu tonlu: bilinen sürüm birincil, OTA durumu anlamına göre (güncel =
            // başarı, indiriliyor = bilgi, beklemede = uyarı, hata = hata) gözden hemen okunur.
            InfoChip(
              'Firmware: ${device.firmwareVersion ?? "-"}',
              tone: device.firmwareVersion == null ? null : AppTone.primary,
            ),
            InfoChip('Model: ${device.hardwareTarget?.toUpperCase() ?? "Bilinmiyor"}'),
            if (device.hasHardwareMismatch)
              InfoChip(
                'Kayıtlı Tür: ${DeviceRecord.normalizeHardwareTarget(device.hardwareType)?.toUpperCase()} (cihaz bildirimiyle uyuşmuyor)',
                tone: AppTone.warning,
              ),
            if (widget.isSuperUser)
              InfoChip(
                'OTA Durumu: ${device.displayOtaStatus}',
                tone: otaStatusTone(device.displayOtaStatus),
              ),
            InfoChip('Wi-Fi Gücü: $signalText'),
            InfoChip('Yerel IP: ${device.localIp ?? "-"}'),
            InfoChip('Genel IP: ${device.publicIp ?? "-"}'),
            InfoChip('Son Görülme: $lastSeenText'),
            if ((device.mqttUsername ?? '').isNotEmpty)
              InfoChip('MQTT Kullanıcı: ${device.mqttUsername}'),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        // Kapısız cihazda kart uyarı tonlu: textMuted yerine ikincil metin (>= 4,5:1).
        Text(
          'Kayıt: $dateText',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onEdit,
              style: tonalActionStyle(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Düzenle'),
            ),
            ElevatedButton.icon(
              style: !isAssigned
                  ? filledToneStyle(context, tone: AppTone.warning)
                  : tonalActionStyle(context),
              onPressed: widget.onAssignToDoor,
              icon: const Icon(Icons.meeting_room_outlined, size: 16),
              label: const Text('Kapıya Ata'),
            ),
            if (widget.isSuperUser && widget.onToggleDefect != null)
              OutlinedButton.icon(
                onPressed: widget.onToggleDefect,
                style: tonalActionStyle(
                  context,
                  tone: device.isDefective ? AppTone.success : AppTone.warning,
                ),
                icon: Icon(
                  device.isDefective
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  size: 16,
                ),
                label: Text(
                  device.isDefective ? 'Arızayı Kaldır' : 'Arızalı İşaretle',
                ),
              ),
            if (widget.isSuperUser &&
                widget.onReleaseOwnership != null &&
                (device.assignedDoorId != null || device.hasOwner))
              OutlinedButton.icon(
                onPressed: widget.onReleaseOwnership,
                style: tonalActionStyle(context, tone: AppTone.neutral),
                icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                label: const Text('Depoya Al'),
              ),
            if (widget.isSuperUser)
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                style: dangerOutlineStyle(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Sil'),
              ),
          ],
        ),
        if (widget.isSuperUser && widget.authService != null) ...[
          const SizedBox(height: AppSpace.lg),
          DeviceConnectivityLogsAccordion(
            device: widget.device,
            authService: widget.authService!,
          ),
        ],
      ],
    );
  }
}
