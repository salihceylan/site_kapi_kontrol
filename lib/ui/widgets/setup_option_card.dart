// FAZ 5 / A2-G4: "Site Sakini Girişi" ve "Yönetici & Cihaz Kurulumu" seçenek kartı.
//
// Bireysel ana görünümün ilk açılış kartları ile "Daireye Katıl & Cihaz Ekle" ekranındaki iki
// kart aynı kompozisyonu paylaşır; eskiden her biri ~150 satır iç içe Container/gradyan kopyasıydı.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Tonlu seçenek kartı: gradyan ikon karosu + başlık + rozet + açıklama + eylem.
///
/// Başlık ve rozet bir arada akar (`Wrap`): rozet başlığa sığmazsa başlığın ALTINA iner, başlık
/// kırpılmaz ("Sit…" sorunu). Eylem ([action]) çağıranın düğmesidir (`ElevatedButton`/
/// `PrimaryActionButton`); kartın altında tam genişlikte durur.
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

  /// Başlığın yanındaki kısa rozet metni ('Daireye Katıl', 'YÖNETİCİ'...).
  final String badge;

  final String description;

  /// Kartın altındaki eylem düğmesi.
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;

    return AppCard(
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: tone.gradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
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
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          action,
        ],
      ),
    );
  }
}
