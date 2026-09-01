import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class CompanyDeviceCard extends StatefulWidget {
  const CompanyDeviceCard({
    super.key,
    required this.device,
    required this.isSuperUser,
    required this.onEdit,
    required this.onAssignToDoor,
    required this.onDelete,
  });

  final DeviceRecord device;
  final bool isSuperUser;
  final VoidCallback onEdit;
  final VoidCallback onAssignToDoor;
  final VoidCallback onDelete;

  @override
  State<CompanyDeviceCard> createState() => _CompanyDeviceCardState();
}

class _CompanyDeviceCardState extends State<CompanyDeviceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final siteText = device.siteName == null
        ? (device.siteCode == null ? '-' : 'Site ID: ${device.siteCode}')
        : '${device.siteName} (${device.siteCode ?? '-'})';
    final doorText = device.assignedDoorName ?? 'Kapı atanmamış';
    final userText = device.assignedUserCode?.toString() ?? '-';
    final dateText = formatDateTime(device.createdAt);
    final isOnline = device.mqttConnected == true;
    final onlineText = device.mqttConnected == null
        ? 'Bilinmiyor'
        : (isOnline ? 'Online' : 'Offline');
    final signalText = device.wifiSignalPercent == null
        ? '-'
        : '%${device.wifiSignalPercent}'
            '${device.wifiRssi == null ? '' : ' (${device.wifiRssi} dBm)'}';
    final lastSeenText = formatDateTime(device.lastSeenAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isOnline
                    ? Colors.green.shade200
                    : AppColors.primarySoft.withValues(alpha: 0.25),
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
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.memory_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.deviceUid,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Site: $siteText | Kapı: $doorText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        onlineText,
                        style: TextStyle(
                          color: isOnline ? Colors.green.shade800 : Colors.grey.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      Text('Kullanıcı ID: $userText', style: const TextStyle(fontSize: 12.5)),
                      Text('MQTT: ${device.mqttConfigured ? 'Hazır' : 'Eksik'}', style: const TextStyle(fontSize: 12.5)),
                      Text('Firmware: ${device.firmwareVersion ?? '-'}', style: const TextStyle(fontSize: 12.5)),
                      if (widget.isSuperUser)
                        Text('OTA Durumu: ${device.otaStatus ?? '-'}', style: const TextStyle(fontSize: 12.5)),
                      Text('Wi-Fi Gücü: $signalText', style: const TextStyle(fontSize: 12.5)),
                      Text('Son Görülme: $lastSeenText', style: const TextStyle(fontSize: 12.5)),
                      if ((device.mqttUsername ?? '').isNotEmpty)
                        Text('MQTT Kullanıcı: ${device.mqttUsername}', style: const TextStyle(fontSize: 12.5)),
                      Text('Kayıt: $dateText', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Düzenle'),
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.onAssignToDoor,
                        icon: const Icon(Icons.meeting_room_outlined, size: 16),
                        label: const Text('Kapıya Ata'),
                      ),
                      if (widget.isSuperUser)
                        OutlinedButton.icon(
                          onPressed: widget.onDelete,
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          label: const Text('Sil', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

