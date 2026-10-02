import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class BluetoothWifiView extends StatelessWidget {
  const BluetoothWifiView({
    super.key,
    required this.onOpenWifiProvision,
  });

  final VoidCallback onOpenWifiProvision;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    const tone = AppTone.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: AppCard(
            padding: const EdgeInsets.all(22),
            // Hero: geniş ekranda (masaüstü/tablet) içerik ortada en çok 480 dp; düğme tüm karta yayılmaz.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero: ikon karosu + başlık (AppBar başlığıyla tekrarlanan metin küçük kalır) + eylem.
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tone.tint(p),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.lg),
                          child: ExcludeSemantics(
                            child: Icon(
                              Icons.bluetooth_searching_outlined,
                              size: 32,
                              color: tone.ink(p),
                            ),
                          ),
                        ),
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
                    const SizedBox(height: 14),
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
