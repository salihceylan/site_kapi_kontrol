import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class DoorCard extends StatelessWidget {
  const DoorCard({
    super.key,
    required this.door,
    required this.onAssignDevice,
    this.onReplaceDevice,
    this.onEditDoor,
    this.onDeleteDoor,
    this.onManagePermissions,
  });

  final DoorRecord door;
  final VoidCallback onAssignDevice;
  final VoidCallback? onReplaceDevice;
  final VoidCallback? onEditDoor;
  final VoidCallback? onDeleteDoor;
  final VoidCallback? onManagePermissions;

  /// Donanım rozetinin tonu: WROOM = mor, C3 = mavi, diğer cihaz = yeşil, cihaz yok = uyarı.
  AppTone get _hardwareTone {
    if (door.isHardwareWroom) return AppTone.violet;
    if (door.isHardwareC3) return AppTone.primary;
    return door.hasDevice ? AppTone.success : AppTone.warning;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final hasDevice = door.assignedDeviceUid != null &&
        door.assignedDeviceUid!.trim().isNotEmpty;
    final hasMenu = (hasDevice && onReplaceDevice != null) ||
        onEditDoor != null ||
        onDeleteDoor != null ||
        onManagePermissions != null;
    final deviceTone = hasDevice ? _hardwareTone : AppTone.warning;
    final unitStyle = th.bodySmall;

    // Cihazsız kapı = uyarı tonlu kart (kapı kontrolü pasif). Tek eylem satırı: önceki "dar/geniş"
    // çift dal ve iki PopupMenu kopyası kalktı; satır sığmayınca sarar.
    return AppCard(
      tone: hasDevice ? null : AppTone.warning,
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: door.isHardwareWroom
                    ? Icons.developer_board_rounded
                    : Icons.meeting_room_rounded,
                tone: deviceTone,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        Text(door.doorName, style: th.titleMedium),
                        StatusChip(
                          label: door.accessScopeLabel,
                          tone: door.isBlockScope
                              ? AppTone.info
                              : AppTone.neutral,
                        ),
                        StatusChip(
                          label: door.hardwareBadgeText,
                          tone: deviceTone,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    if (hasDevice) ...[
                      Text(
                        'UID: ${door.assignedDeviceUid} • ${door.hardwareModelTitle}',
                        style: th.bodyMedium,
                      ),
                      if (door.assignedDeviceFirmwareVersion != null ||
                          door.assignedDeviceIsOnline != null ||
                          door.assignedDeviceLocalIp != null) ...[
                        const SizedBox(height: AppSpace.xs),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.xs,
                          children: [
                            if (door.assignedDeviceIsOnline != null)
                              StatusChip(
                                label: door.assignedDeviceIsOnline == true
                                    ? 'Online'
                                    : 'Offline',
                                tone: door.assignedDeviceIsOnline == true
                                    ? AppTone.success
                                    : AppTone.danger,
                                pulse: door.assignedDeviceIsOnline == true,
                              ),
                            if (door.assignedDeviceFirmwareVersion != null)
                              Text(
                                'v${door.assignedDeviceFirmwareVersion}',
                                style: unitStyle,
                              ),
                            if (door.assignedDeviceLocalIp != null)
                              Text(
                                'IP: ${door.assignedDeviceLocalIp}',
                                style: unitStyle,
                              ),
                          ],
                        ),
                      ],
                    ] else
                      Text(
                        'Cihaz atanmamış (Kapı kontrolü pasif)',
                        style: th.bodyMedium?.copyWith(
                          color: AppTone.warning.ink(p),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                ElevatedButton.icon(
                  onPressed: onAssignDevice,
                  style: tonalActionStyle(
                    context,
                    tone: hasDevice ? AppTone.primary : AppTone.warning,
                  ),
                  icon: const Icon(
                    Icons.settings_input_component_rounded,
                    size: 16,
                  ),
                  label: Text(hasDevice ? 'Değiştir' : 'Cihaz Ata'),
                ),
                if (hasMenu) _buildMenu(context, hasDevice),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context, bool hasDevice) {
    final p = context.palette;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: p.textSecondary),
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      onSelected: (val) {
        if (val == 'permissions') onManagePermissions?.call();
        if (val == 'replace') onReplaceDevice?.call();
        if (val == 'edit') onEditDoor?.call();
        if (val == 'delete') onDeleteDoor?.call();
      },
      itemBuilder: (ctx) {
        final mp = ctx.palette;
        return [
          if (onManagePermissions != null)
            PopupMenuItem(
              value: 'permissions',
              child: Row(
                children: [
                  Icon(
                    Icons.vpn_key_rounded,
                    size: 18,
                    color: AppTone.primary.ink(mp),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  const Flexible(child: Text('Kapı Yetkileri')),
                ],
              ),
            ),
          if (hasDevice && onReplaceDevice != null)
            PopupMenuItem(
              value: 'replace',
              child: Row(
                children: [
                  Icon(
                    Icons.published_with_changes_rounded,
                    size: 18,
                    color: AppTone.warning.ink(mp),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  const Flexible(child: Text('Arızalı Cihazı Değiştir')),
                ],
              ),
            ),
          if (onEditDoor != null)
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 18, color: mp.textSecondary),
                  const SizedBox(width: AppSpace.sm),
                  const Flexible(child: Text('Kapıyı Düzenle')),
                ],
              ),
            ),
          if (onDeleteDoor != null)
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppTone.danger.ink(mp),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(
                      'Kapıyı Sil',
                      style: TextStyle(color: AppTone.danger.ink(mp)),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
    );
  }
}
