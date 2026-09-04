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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.85)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x30000000) : const Color(0x080F172A),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.apartment_rounded,
                  color: isDark ? AppColors.accentLight : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  site.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  'ID: ${site.id}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${site.blockCount} blok, ${site.apartmentCount} daire, ${site.doorCount} kapı',
            style: TextStyle(
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((site.managerName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Yönetici: ${site.managerName} (${site.managerUserCode ?? '-'})',
              style: TextStyle(
                color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
          if ((site.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              site.address!,
              style: TextStyle(
                color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
          if ((site.city ?? '').isNotEmpty || (site.district ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${site.city ?? '-'} / ${site.district ?? '-'}',
                style: TextStyle(
                  color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Oluşturma: $formattedCreatedAt',
            style: TextStyle(
              color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
              fontSize: 12,
            ),
          ),
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
