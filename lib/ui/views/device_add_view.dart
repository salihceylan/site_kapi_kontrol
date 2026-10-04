import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_action_tile.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class DeviceAddView extends StatelessWidget {
  const DeviceAddView({
    super.key,
    required this.onOpenQrRegistration,
    required this.onOpenManualRegistration,
    this.title,
    this.qrTitle,
    this.qrDescription,
    this.qrButtonLabel,
    this.manualTitle,
    this.manualDescription,
    this.manualButtonLabel,
  });

  final VoidCallback onOpenQrRegistration;
  final VoidCallback onOpenManualRegistration;
  final String? title;
  final String? qrTitle;
  final String? qrDescription;
  final String? qrButtonLabel;
  final String? manualTitle;
  final String? manualDescription;
  final String? manualButtonLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero başlık kartı (AppCard seviye 2) + cilalı rozet; başlık SectionHeader (anlamsal başlık).
        SizedBox(
          width: double.infinity,
          child: PageHeaderCard(
            title: title ?? 'Şirket Veritabanına Cihaz Kaydet',
            icon: Icons.memory_rounded,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 680;
            final children = [
              DeviceActionTile(
                icon: Icons.qr_code_scanner_outlined,
                title: qrTitle ?? 'QR ile Şirket Veritabanına Kaydet',
                description: qrDescription ??
                    'Cihaz üzerindeki QR kodu okutur, Unique ID alanını otomatik doldurur ve şirket kayıt formunu açar.',
                buttonLabel: qrButtonLabel ?? 'QR Oku',
                onPressed: onOpenQrRegistration,
              ),
              DeviceActionTile(
                icon: Icons.edit_note_outlined,
                title: manualTitle ?? 'Unique ID ile Şirket Veritabanına Kaydet',
                description: manualDescription ??
                    'QR okunamıyorsa veya masaüstü sürümde çalışıyorsanız cihaz Unique ID bilgisini elle girerek şirket hesabına kayıt yapar.',
                buttonLabel: manualButtonLabel ?? 'Unique ID Gir',
                onPressed: onOpenManualRegistration,
              ),
            ];

            if (isCompact) {
              return Column(
                children: [
                  children[0],
                  const SizedBox(height: AppSpace.md),
                  children[1],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: AppSpace.md),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}
