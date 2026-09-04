import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/widgets/company_device_card.dart';

class CompanyDevicesView extends StatelessWidget {
  const CompanyDevicesView({
    super.key,
    required this.pageData,
    required this.devices,
    required this.isSuperUser,
    required this.isLoading,
    required this.isBroadcastingOta,
    required this.onBroadcastOta,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onEditDevice,
    required this.onAssignDeviceToDoor,
    required this.onDeleteDevice,
    this.onDownloadFirmwareReportPdf,
  });

  final DevicePage? pageData;
  final List<DeviceRecord> devices;
  final bool isSuperUser;
  final bool isLoading;
  final bool isBroadcastingOta;
  final VoidCallback onBroadcastOta;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadPage;
  final ValueChanged<DeviceRecord> onEditDevice;
  final ValueChanged<DeviceRecord> onAssignDeviceToDoor;
  final ValueChanged<DeviceRecord> onDeleteDevice;
  final VoidCallback? onDownloadFirmwareReportPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Şirket Hesabına Kayıtlı Cihazlar',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isSuperUser) ...[
                    ElevatedButton.icon(
                      onPressed: isBroadcastingOta ||
                              isLoading ||
                              (pageData?.total ?? 0) == 0
                          ? null
                          : onBroadcastOta,
                      icon: const Icon(Icons.system_update_alt),
                      label: Text(
                        isBroadcastingOta
                            ? 'Gönderiliyor...'
                            : 'Tümüne OTA Kontrolü',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: (pageData?.total ?? 0) == 0
                          ? null
                          : onDownloadFirmwareReportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Sürüm Raporu (PDF)'),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: isLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isLoading)
          const LinearProgressIndicator()
        else if (devices.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard(context),
            child: const Text('Şirket hesabına kayıtlı cihaz bulunamadı.'),
          )
        else
          ...devices.map(
            (device) => CompanyDeviceCard(
              device: device,
              isSuperUser: isSuperUser,
              onEdit: () => onEditDevice(device),
              onAssignToDoor: () => onAssignDeviceToDoor(device),
              onDelete: () => onDeleteDevice(device),
            ),
          ),
        if (pageData != null && pageData!.totalPages > 1) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Sayfa ${pageData!.page} / ${pageData!.totalPages} | Toplam ${pageData!.total}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              OutlinedButton(
                onPressed: pageData!.page > 1 && !isLoading
                    ? () => onLoadPage(pageData!.page - 1)
                    : null,
                child: const Icon(Icons.chevron_left),
              ),
              OutlinedButton(
                onPressed: pageData!.page < pageData!.totalPages && !isLoading
                    ? () => onLoadPage(pageData!.page + 1)
                    : null,
                child: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

