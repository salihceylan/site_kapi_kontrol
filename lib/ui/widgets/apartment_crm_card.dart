import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Daire alanlarının kısa çipleri: kat, kategori, brüt / net m², arsa payı. Bilinmeyen alan çizilmez.
List<String> apartmentFactLabels(ApartmentSummary apartment) {
  return <String>[
    if (apartment.floor != null) 'Kat ${apartment.floor}',
    if (apartment.category != null) apartment.category!,

    if (apartment.landShare != null) 'Arsa payı ${apartment.landShare!.label}',
  ];
}

/// Daire listesi kartı (Platform Faz 2a): daire etiketi, alan çipleri, güncel malik ve kiracı, sakin
/// sayısı. Dokununca daire kartı açılır ([onTap]).
///
/// Taşma: tüm metinler sarar; çipler `Wrap` içindedir. Büyük yazıda (>= 1,75x) ikon karosu `IconTile`
/// tarafından kendiliğinden gizlenir (kod koşulsuz çizer, gizlemeyi bileşen yapar).
class ApartmentCrmCard extends StatelessWidget {
  const ApartmentCrmCard({super.key, required this.apartment, required this.onTap});

  final ApartmentSummary apartment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final facts = apartmentFactLabels(apartment);
    final owner = apartment.owner;
    final tenant = apartment.tenant;

    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: 'Daire kartı: ${apartment.fullLabel}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: Icons.apartment_rounded, gap: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(apartment.fullLabel, style: th.titleMedium),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [for (final fact in facts) InfoChip(fact)],
                  ),
                ],
                const SizedBox(height: AppSpace.sm),
                Text(
                  owner == null
                      ? 'Malik: kayıtlı değil'
                      : 'Malik: ${crmPersonName(owner.fullName)}',
                  style: secondary,
                ),
                Text(
                  tenant == null
                      ? 'Kiracı: kayıtlı değil'
                      : 'Kiracı: ${crmPersonName(tenant.fullName)}',
                  style: secondary,
                ),
                Text('${apartment.residentCount} güncel sakin', style: secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
