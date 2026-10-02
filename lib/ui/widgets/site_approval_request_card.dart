import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class SiteApprovalRequestCard extends StatelessWidget {
  const SiteApprovalRequestCard({
    super.key,
    required this.site,
    required this.busy,
    required this.formattedCreatedAt,
    required this.onApprove,
    required this.onReject,
  });

  final SiteRecord site;
  final bool busy;
  final String formattedCreatedAt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.apartment_rounded,
                size: 40,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(site.name, style: th.titleMedium),
                    InfoChip('ID: ${site.id}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            '${site.blockCount} blok, ${site.apartmentCount} daire, ${site.doorCount} kapı',
            style: th.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          if ((site.managerName ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'Yönetici: ${site.managerName} (${site.managerUserCode ?? '-'})',
              style: th.bodyMedium,
            ),
          ],
          if ((site.address ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(site.address!, style: th.bodyMedium),
          ],
          if ((site.city ?? '').isNotEmpty || (site.district ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                '${site.city ?? '-'} / ${site.district ?? '-'}',
                style: th.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpace.xs),
          Text('Oluşturma: $formattedCreatedAt', style: th.bodySmall),
          const SizedBox(height: AppSpace.lg),
          busy
              ? Center(
                  // Koyu temada varsayılan birincil mavi kart yüzeyinde ~2,7:1 kalıyordu: ink tonu.
                  child: CircularProgressIndicator(
                    color: AppTone.primary.ink(p),
                  ),
                )
              : Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: onApprove,
                      style: filledToneStyle(context, tone: AppTone.success),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Onayla'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      style: dangerOutlineStyle(context),
                      icon: const Icon(Icons.block_outlined, size: 18),
                      label: const Text('Reddet'),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
