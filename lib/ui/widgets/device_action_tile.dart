import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Cihaz eylem kartı: 56 dp cilalı daire [IconOrb] (glow'lu, dekoratif) + başlık + açıklama + tam
/// genişlikte `ElevatedButton`. Kart başlık ve açıklamayı tek anlamsal düğüm olarak okutur, düğme ayrıdır.
class DeviceActionTile extends StatelessWidget {
  const DeviceActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Kart satırın/sütunun tüm genişliğini kaplar (eski Container(width: double.infinity) gibi).
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconOrb(icon: icon, size: 56, glow: true),
            const SizedBox(height: AppSpace.md),
            Text(title, style: textTheme.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text(description, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
