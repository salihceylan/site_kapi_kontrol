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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDevice
              ? AppColors.primarySoft.withValues(alpha: 0.3)
              : Colors.orange.shade200,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasDevice
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.meeting_room_outlined,
                  color: hasDevice
                      ? AppColors.primary
                      : Colors.orange.shade800,
                  size: 20,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDevice
                          ? 'Cihaz: ${door.assignedDeviceUid}'
                          : 'Cihaz atanmamış',
                      style: TextStyle(
                        color: hasDevice
                            ? AppColors.textMuted
                            : Colors.orange.shade800,
                        fontSize: 12.5,
                        fontWeight: hasDevice
                            ? FontWeight.normal
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: onAssignDevice,
                icon: const Icon(Icons.settings_input_component, size: 16),
                label: Text(hasDevice ? 'Değiştir' : 'Cihaz Ata'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
