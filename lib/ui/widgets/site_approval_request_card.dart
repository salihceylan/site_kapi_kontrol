import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

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
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.apartment_rounded, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  site.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFFF8FAFC),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ID: ${site.id}',
                  style: const TextStyle(color: AppColors.textMutedLight, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${site.blockCount} blok, ${site.apartmentCount} daire, ${site.doorCount} kapı',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if ((site.managerName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Yönetici: ${site.managerName} (${site.managerUserCode ?? '-'})',
              style: const TextStyle(color: AppColors.textMutedLight, fontSize: 12.5),
            ),
          ],
          if ((site.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(site.address!, style: const TextStyle(color: AppColors.textMutedLight, fontSize: 12.5)),
          ],
          if ((site.city ?? '').isNotEmpty || (site.district ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${site.city ?? '-'} / ${site.district ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          const SizedBox(height: 4),
          Text('Oluşturma: $formattedCreatedAt', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 14),
          busy
              ? const Center(child: CircularProgressIndicator())
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Onayla'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.roseLight,
                        side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
                      ),
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
