import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_action_tile.dart';

class DeviceAddView extends StatelessWidget {
  const DeviceAddView({
    super.key,
    required this.onOpenQrRegistration,
    required this.onOpenManualRegistration,
  });

  final VoidCallback onOpenQrRegistration;
  final VoidCallback onOpenManualRegistration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard,
          child: const Text(
            'Şirket Veritabanına Cihaz Kaydet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 680;
            final children = [
              DeviceActionTile(
                icon: Icons.qr_code_scanner_outlined,
                title: 'QR ile Şirket Veritabanına Kaydet',
                description:
                    'Cihaz üzerindeki QR kodu okutur, Unique ID alanını otomatik doldurur ve şirket kayıt formunu açar.',
                buttonLabel: 'QR Oku',
                onPressed: onOpenQrRegistration,
              ),
              DeviceActionTile(
                icon: Icons.edit_note_outlined,
                title: 'Unique ID ile Şirket Veritabanına Kaydet',
                description:
                    'QR okunamıyorsa veya masaüstü sürümde çalışıyorsanız cihaz Unique ID bilgisini elle girerek şirket hesabına kayıt yapar.',
                buttonLabel: 'Unique ID Gir',
                onPressed: onOpenManualRegistration,
              ),
            ];

            if (isCompact) {
              return Column(
                children: [
                  children[0],
                  const SizedBox(height: 12),
                  children[1],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 12),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}

