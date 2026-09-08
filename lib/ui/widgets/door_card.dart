import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class DoorCard extends StatelessWidget {
  const DoorCard({
    super.key,
    required this.door,
    required this.onAssignDevice,
  });

  final DoorRecord door;
  final VoidCallback onAssignDevice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDevice = door.assignedDeviceUid != null &&
        door.assignedDeviceUid!.trim().isNotEmpty;

    Color badgeBgColor(bool isDark) {
      if (door.isHardwareWroom) {
        return (isDark ? const Color(0xFF7C3AED) : const Color(0xFF8B5CF6)).withValues(alpha: isDark ? 0.25 : 0.12);
      } else if (door.isHardwareC3) {
        return (isDark ? AppColors.primary : AppColors.primaryLight).withValues(alpha: isDark ? 0.25 : 0.12);
      } else if (hasDevice) {
        return AppColors.emerald.withValues(alpha: isDark ? 0.25 : 0.12);
      }
      return AppColors.amber.withValues(alpha: isDark ? 0.25 : 0.12);
    }

    Color badgeTextColor(bool isDark) {
      if (door.isHardwareWroom) {
        return isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
      } else if (door.isHardwareC3) {
        return isDark ? const Color(0xFF93C5FD) : AppColors.primary;
      } else if (hasDevice) {
        return isDark ? AppColors.emeraldLight : AppColors.emerald;
      }
      return isDark ? AppColors.amberLight : const Color(0xFFD97706);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.85)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasDevice
              ? (isDark ? const Color(0x333B82F6) : const Color(0xFFBFDBFE))
              : (isDark ? const Color(0x33F59E0B) : const Color(0xFFFED7AA)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x30000000) : const Color(0x080F172A),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hasDevice
                          ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                          : AppColors.amber.withValues(alpha: isDark ? 0.2 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      door.isHardwareWroom ? Icons.developer_board_rounded : Icons.meeting_room_rounded,
                      color: hasDevice
                          ? (door.isHardwareWroom
                              ? (isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED))
                              : (isDark ? AppColors.accentLight : AppColors.primary))
                          : (isDark ? AppColors.amberLight : const Color(0xFFD97706)),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              door.doorName,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: badgeBgColor(isDark),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: badgeTextColor(isDark).withValues(alpha: 0.35),
                                  width: 0.9,
                                ),
                              ),
                              child: Text(
                                door.hardwareBadgeText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: badgeTextColor(isDark),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (hasDevice) ...[
                          Text(
                            'UID: ${door.assignedDeviceUid} • ${door.hardwareModelTitle}',
                            style: TextStyle(
                              color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (door.assignedDeviceFirmwareVersion != null || door.assignedDeviceIsOnline != null || door.assignedDeviceLocalIp != null) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (door.assignedDeviceIsOnline != null) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: door.assignedDeviceIsOnline == true ? AppColors.emeraldLight : AppColors.rose,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    door.assignedDeviceIsOnline == true ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: door.assignedDeviceIsOnline == true
                                          ? (isDark ? AppColors.emeraldLight : const Color(0xFF059669))
                                          : (isDark ? AppColors.roseLight : AppColors.rose),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (door.assignedDeviceFirmwareVersion != null) ...[
                                  Text(
                                    'v${door.assignedDeviceFirmwareVersion}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (door.assignedDeviceLocalIp != null) ...[
                                  Text(
                                    'IP: ${door.assignedDeviceLocalIp}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ] else ...[
                          Text(
                            'Cihaz atanmamış (Kapı kontrolü pasif)',
                            style: TextStyle(
                              color: isDark ? AppColors.amberLight : const Color(0xFFD97706),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isNarrow) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: onAssignDevice,
                      icon: const Icon(Icons.settings_input_component_rounded, size: 16),
                      label: Text(hasDevice ? 'Değiştir' : 'Cihaz Ata'),
                    ),
                  ],
                ],
              ),
              if (isNarrow) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAssignDevice,
                    icon: const Icon(Icons.settings_input_component_rounded, size: 16),
                    label: Text(hasDevice ? 'Değiştir' : 'Cihaz Ata'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
