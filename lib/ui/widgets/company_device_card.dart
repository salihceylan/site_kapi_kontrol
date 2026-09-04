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
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline
                    ? AppColors.emerald.withValues(alpha: 0.4)
                    : const Color(0x22FFFFFF),
                width: isOnline ? 1.4 : 1.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x30000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
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
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.memory_rounded,
                            color: AppColors.accent,
                            size: 22,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: isOnline ? AppColors.emeraldLight : AppColors.roseLight,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF1E293B), width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.deviceUid,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF8FAFC),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Site: $siteText | Kapı: $doorText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.emerald.withValues(alpha: 0.15)
                            : const Color(0x20FFFFFF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOnline
                              ? AppColors.emerald.withValues(alpha: 0.4)
                              : const Color(0x20FFFFFF),
                        ),
                      ),
                      child: Text(
                        onlineText,
                        style: TextStyle(
                          color: isOnline ? AppColors.emeraldLight : AppColors.textMutedLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMutedLight,
                      size: 20,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: Color(0x1FFFFFFF), height: 1),
                  ),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _buildChip('Kullanıcı ID: $userText'),
                      _buildChip('MQTT: ${device.mqttConfigured ? "Hazır" : "Eksik"}'),
                      _buildChip('Firmware: ${device.firmwareVersion ?? "-"}'),
                      if (widget.isSuperUser)
                        _buildChip('OTA Durumu: ${device.otaStatus ?? "-"}'),
                      _buildChip('Wi-Fi Gücü: $signalText'),
                      _buildChip('Yerel IP: ${device.localIp ?? "-"}'),
                      _buildChip('Genel IP: ${device.publicIp ?? "-"}'),
                      _buildChip('Son Görülme: $lastSeenText'),
                      if ((device.mqttUsername ?? '').isNotEmpty)
                        _buildChip('MQTT Kullanıcı: ${device.mqttUsername}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Kayıt: $dateText', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 14),
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
                          icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.roseLight),
                          label: const Text('Sil', style: TextStyle(color: AppColors.roseLight)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
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

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}
