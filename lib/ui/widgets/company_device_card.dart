import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class CompanyDeviceCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final siteText = device.siteName == null
        ? (device.siteCode == null ? '-' : 'Site ID: ${device.siteCode}')
        : '${device.siteName} (${device.siteCode ?? '-'})';
    final doorText = device.assignedDoorName ?? 'Kapı atanmamış';
    final userText = device.assignedUserCode?.toString() ?? '-';
    final dateText = formatDateTime(device.createdAt);
    final onlineText = device.mqttConnected == null
        ? 'Bilinmiyor'
        : (device.mqttConnected! ? 'Online' : 'Offline');
    final signalText = device.wifiSignalPercent == null
        ? '-'
        : '%${device.wifiSignalPercent}'
            '${device.wifiRssi == null ? '' : ' (${device.wifiRssi} dBm)'}';
    final lastSeenText = formatDateTime(device.lastSeenAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: AppDecorations.glassCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.deviceUid,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text('Site: $siteText'),
            const SizedBox(height: 6),
            Text('Kapı: $doorText'),
            const SizedBox(height: 6),
            Text('Kullanıcı ID: $userText'),
            const SizedBox(height: 6),
            Text(
              'MQTT Kimliği: ${device.mqttConfigured ? 'Hazır' : 'Eksik'}',
            ),
            const SizedBox(height: 6),
            Text('Cihaz Bağlantısı: $onlineText'),
            const SizedBox(height: 6),
            Text('Firmware: ${device.firmwareVersion ?? '-'}'),
            const SizedBox(height: 6),
            Text('OTA Durumu: ${device.otaStatus ?? '-'}'),
            const SizedBox(height: 6),
            Text('Wi-Fi Gücü: $signalText'),
            const SizedBox(height: 6),
            Text('Son Görülme: $lastSeenText'),
            if ((device.mqttUsername ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('MQTT Kullanıcı: ${device.mqttUsername}'),
            ],
            const SizedBox(height: 6),
            Text('Kayıt Tarihi: $dateText'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Düzenle'),
                ),
                ElevatedButton.icon(
                  onPressed: onAssignToDoor,
                  icon: const Icon(Icons.meeting_room_outlined),
                  label: const Text('Kapıya Ata'),
                ),
                if (isSuperUser)
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Sil'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
