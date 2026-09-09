import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';

class BluetoothWifiView extends StatelessWidget {
  const BluetoothWifiView({
    super.key,
    required this.onOpenWifiProvision,
  });

  final VoidCallback onOpenWifiProvision;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardTitleColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textDark;

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
              Text(
                'Bluetooth ile Wi-Fi Kur',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: cardTitleColor,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onOpenWifiProvision,
                  icon: const Icon(Icons.bluetooth_searching_outlined),
                  label: const Text('Bluetooth ile Wi-Fi Kurulumunu Aç'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

