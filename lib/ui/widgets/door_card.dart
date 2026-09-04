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
                      Icons.meeting_room_rounded,
                      color: hasDevice
                          ? (isDark ? AppColors.accentLight : AppColors.primary)
                          : (isDark ? AppColors.amberLight : const Color(0xFFD97706)),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          door.doorName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasDevice
                              ? 'Cihaz: ${door.assignedDeviceUid}'
                              : 'Cihaz atanmamış',
                          style: TextStyle(
                            color: hasDevice
                                ? (isDark ? AppColors.textMutedLight : AppColors.textMuted)
                                : (isDark ? AppColors.amberLight : const Color(0xFFD97706)),
                            fontSize: 12.5,
                            fontWeight: hasDevice
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
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
