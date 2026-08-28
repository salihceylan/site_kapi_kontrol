import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.infoCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  site.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text('ID: ${site.id}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${site.blockCount} blok, ${site.apartmentCount} daire, ${site.doorCount} kapı',
          ),
          if ((site.managerName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Yönetici: ${site.managerName} (${site.managerUserCode ?? '-'})',
            ),
          ],
          if ((site.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(site.address!),
          ],
          if ((site.city ?? '').isNotEmpty || (site.district ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${site.city ?? '-'} / ${site.district ?? '-'}'),
            ),
          const SizedBox(height: 6),
          Text('Oluşturma Tarihi: $formattedCreatedAt'),
          const SizedBox(height: 12),
          busy
              ? const Center(child: CircularProgressIndicator())
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Onayla'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
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

