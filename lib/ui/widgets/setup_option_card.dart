// FAZ 5 / A2-G4: "Site Sakini Girişi" ve "Yönetici & Cihaz Kurulumu" seçenek kartı.
//
// Bireysel ana görünümün ilk açılış kartları ile "Daireye Katıl & Cihaz Ekle" ekranındaki iki
// kart aynı kompozisyonu paylaşır; eskiden her biri ~150 satır iç içe Container/gradyan kopyasıydı.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Tonlu seçenek kartı: cilalı hero ikon rozeti + başlık + rozet + açıklama + eylem.
///
/// Hero kart: `AppCard(level: 2, tone)` (ton zemini + tonun sol-üst yıkaması) ve 56 dp daire [IconOrb]
/// (glow'lu). Rozet dekoratiftir; anlamı başlık ve açıklama taşır. Büyük yazıda (>= 1,75x) rozet metnin
/// ÜSTÜNE geçer (yan yana yer kalmaz; başlık tam genişliği alır).
///
/// Başlık ve rozet bir arada akar (`Wrap`): rozet başlığa sığmazsa başlığın ALTINA iner, başlık
/// kırpılmaz ("Sit…" sorunu). Eylem ([action]) çağıranın düğmesidir (`ElevatedButton`/
/// `PrimaryActionButton`; en az 48 dp); kartın altında tam genişlikte durur, dokunma geri çağrısı
/// çağıranındır (kartın kendisi dokunulmaz: tek etkileşimli öğe eylemdir).
///
/// [tone]: success (site sakini) ya da primary (yönetici). Üst öğe sınırlı genişlikte olmalıdır.
class SetupOptionCard extends StatelessWidget {
  const SetupOptionCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    required this.badge,
    required this.description,
    required this.action,
  });

  final AppTone tone;
  final IconData icon;
  final String title;

  /// Başlığın yanındaki kısa rozet metni ('Daireye Katıl', 'BAŞVURU'...).
  final String badge;

  final String description;

  /// Kartın altındaki eylem düğmesi.
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final orb = IconOrb(icon: icon, tone: tone, size: 56, glow: true);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: th.titleLarge),
            ),
            StatusChip(label: badge, tone: tone),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(description, style: th.bodyMedium),
      ],
    );

    return AppCard(
      tone: tone,
      level: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isLargeText(context))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [orb, const SizedBox(height: AppSpace.md), texts],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                orb,
                const SizedBox(width: AppSpace.md),
                Expanded(child: texts),
              ],
            ),
          const SizedBox(height: AppSpace.lg),
          action,
        ],
      ),
    );
  }
}
