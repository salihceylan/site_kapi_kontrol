import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class BluetoothWifiView extends StatelessWidget {
  const BluetoothWifiView({
    super.key,
    required this.onOpenWifiProvision,
  });

  final VoidCallback onOpenWifiProvision;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          // Hero kart (AppCard seviye 2): ekranın tek odağı.
          child: AppCard(
            level: 2,
            padding: const EdgeInsets.all(AppSpace.xl),
            // Hero: geniş ekranda (masaüstü/tablet) içerik ortada en çok 480 dp; düğme tüm karta yayılmaz.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero: cilalı daire rozet (72 dp, glow'lu; dekoratif) + başlık (AppBar başlığıyla
                    // tekrarlanan metin küçük kalır) + eylem.
                    const Center(
                      child: IconOrb(
                        icon: Icons.bluetooth_searching_outlined,
                        size: 72,
                        glow: true,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Semantics(
                      header: true,
                      child: Text(
                        'Bluetooth ile Wi-Fi Kur',
                        textAlign: TextAlign.center,
                        style: th.titleMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    ElevatedButton.icon(
                      onPressed: onOpenWifiProvision,
                      icon: const Icon(Icons.bluetooth_searching_outlined),
                      label: const Text(
                        'Bluetooth ile Wi-Fi Kurulumunu Aç',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
