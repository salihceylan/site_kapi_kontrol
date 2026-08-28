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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bluetooth ile Wi-Fi Kur',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kayıtlı Wi-Fi bilgisi olmayan cihazlar Bluetooth üzerinden bulunabilir olur. Bu ekrandan cihaza bağlanıp kullanacağı Wi-Fi adını ve şifresini gönderebilirsiniz.',
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
        const SizedBox(height: 12),
        const Text(
          'Wi-Fi bilgisi doğruysa cihaz bilgileri kaydeder, yeniden başlar ve internete bağlandıktan sonra Bluetooth kapanır. Wi-Fi değişecekse cihazdaki reset düğmesine 3 saniye basın; bilgiler silinir ve Bluetooth tekrar bulunabilir olur.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
