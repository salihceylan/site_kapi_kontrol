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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              color: isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.85)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline
                    ? AppColors.emerald.withValues(alpha: 0.4)
                    : (isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0)),
                width: isOnline ? 1.4 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? const Color(0x30000000) : const Color(0x080F172A),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
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
                            color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.memory_rounded,
                            color: isDark ? AppColors.accentLight : AppColors.primary,
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
                              color: isOnline
                                  ? (isDark ? AppColors.emeraldLight : const Color(0xFF059669))
                                  : (isDark ? AppColors.roseLight : AppColors.rose),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                width: 2,
                              ),
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
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Site: $siteText | Kapı: $doorText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
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
                            : (isDark ? const Color(0x20FFFFFF) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOnline
                              ? AppColors.emerald.withValues(alpha: 0.4)
                              : (isDark ? const Color(0x20FFFFFF) : const Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Text(
                        onlineText,
                        style: TextStyle(
                          color: isOnline
                              ? (isDark ? AppColors.emeraldLight : const Color(0xFF059669))
                              : (isDark ? AppColors.textMutedLight : AppColors.textMuted),
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
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                      size: 20,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      color: isDark ? const Color(0x1FFFFFFF) : const Color(0x150F172A),
                      height: 1,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildChip(context, 'Kullanıcı ID: $userText'),
                      _buildChip(context, 'MQTT: ${device.mqttConfigured ? "Hazır" : "Eksik"}'),
                      _buildChip(context, 'Firmware: ${device.firmwareVersion ?? "-"}'),
                      if (widget.isSuperUser)
                        _buildChip(context, 'OTA Durumu: ${device.otaStatus ?? "-"}'),
                      _buildChip(context, 'Wi-Fi Gücü: $signalText'),
                      _buildChip(context, 'Yerel IP: ${device.localIp ?? "-"}'),
                      _buildChip(context, 'Genel IP: ${device.publicIp ?? "-"}'),
                      _buildChip(context, 'Son Görülme: $lastSeenText'),
                      if ((device.mqttUsername ?? '').isNotEmpty)
                        _buildChip(context, 'MQTT Kullanıcı: ${device.mqttUsername}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kayıt: $dateText',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    ),
                  ),
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

  Widget _buildChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        ),
      ),
    );
  }
}
