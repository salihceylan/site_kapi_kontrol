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
    final hasDevice = door.assignedDeviceUid != null &&
        door.assignedDeviceUid!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasDevice
              ? const Color(0x333B82F6)
              : const Color(0x33F59E0B),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 10,
            offset: Offset(0, 4),
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
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.amber.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.meeting_room_rounded,
                      color: hasDevice ? AppColors.accent : AppColors.amberLight,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasDevice
                              ? 'Cihaz: ${door.assignedDeviceUid}'
                              : 'Cihaz atanmamış',
                          style: TextStyle(
                            color: hasDevice
                                ? AppColors.textMutedLight
                                : AppColors.amberLight,
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
