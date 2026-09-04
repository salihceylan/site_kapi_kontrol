import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class SiteCard extends StatefulWidget {
  const SiteCard({
    super.key,
    required this.site,
    required this.selected,
    required this.formattedCreatedAt,
    required this.deleteBusy,
    required this.approvalBusy,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onApprove,
    this.onReject,
    this.onDownloadPdf,
    this.onDownloadLogsPdf,
  });

  final SiteRecord site;
  final bool selected;
  final String formattedCreatedAt;
  final bool deleteBusy;
  final bool approvalBusy;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onDownloadPdf;
  final VoidCallback? onDownloadLogsPdf;

  @override
  State<SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<SiteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final site = widget.site;
    final isSelected = widget.selected;
    final hasManager =
        site.managerName != null && site.managerName!.trim().isNotEmpty;
    final approvalColor = site.approvalStatus == 'approved'
        ? (isDark ? AppColors.emeraldLight : const Color(0xFF059669))
        : (site.approvalStatus == 'rejected'
            ? (isDark ? AppColors.roseLight : AppColors.rose)
            : (isDark ? AppColors.amberLight : const Color(0xFFD97706)));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          widget.onTap();
          setState(() => _expanded = !_expanded);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? (isSelected
                    ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                    : const Color(0xFF1E293B).withValues(alpha: 0.75))
                : (isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.9)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.15)
                    : (isDark ? const Color(0x30000000) : const Color(0x080F172A)),
                blurRadius: isSelected ? 16 : 8,
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryLight.withValues(alpha: isDark ? 0.3 : 0.2),
                      ),
                    ),
                    child: Icon(
                      Icons.apartment_rounded,
                      color: isDark ? AppColors.accentLight : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            letterSpacing: -0.2,
                            color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasManager
                              ? 'Yönetici: ${site.managerName}'
                              : 'Yönetici atanmamış',
                          style: TextStyle(
                            color: hasManager
                                ? (isDark ? AppColors.textMutedLight : AppColors.textMuted)
                                : (isDark ? AppColors.amberLight : const Color(0xFFD97706)),
                            fontSize: 12.5,
                            fontWeight: hasManager
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (site.approvalStatus == 'pending')
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: approvalColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: approvalColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Onay Bekliyor',
                        style: TextStyle(
                          color: approvalColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                  ),
                ],
              ),
              if (_expanded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    color: isDark ? const Color(0x1FFFFFFF) : const Color(0x150F172A),
                    height: 1,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildChip(context, 'ID: ${site.id}'),
                    _buildChip(context, 'Oluşturulma: ${widget.formattedCreatedAt}'),
                    if (site.address != null && site.address!.isNotEmpty)
                      _buildChip(context, 'Adres: ${site.address}'),
                    if (site.city != null && site.city!.isNotEmpty)
                      _buildChip(context, 'Şehir: ${site.city}'),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.onApprove != null)
                      ElevatedButton.icon(
                        onPressed: widget.approvalBusy ? null : widget.onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Onayla'),
                      ),
                    if (widget.onReject != null)
                      OutlinedButton.icon(
                        onPressed: widget.approvalBusy ? null : widget.onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.roseLight,
                          side: const BorderSide(color: AppColors.rose),
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Reddet'),
                      ),
                    if (widget.onEdit != null)
                      OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Düzenle'),
                      ),
                    if (widget.onDelete != null)
                      OutlinedButton.icon(
                        onPressed: widget.deleteBusy ? null : widget.onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.roseLight,
                          side: const BorderSide(color: AppColors.rose),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Sil'),
                      ),
                    if (widget.onDownloadPdf != null)
                      OutlinedButton.icon(
                        onPressed: widget.onDownloadPdf,
                        icon: Icon(
                          Icons.key_outlined,
                          size: 16,
                          color: isDark ? const Color(0xFF93C5FD) : AppColors.primary,
                        ),
                        label: const Text('Şifreleri İndir (PDF)'),
                      ),
                    if (widget.onDownloadLogsPdf != null)
                      OutlinedButton.icon(
                        onPressed: widget.onDownloadLogsPdf,
                        icon: Icon(
                          Icons.assignment_outlined,
                          size: 16,
                          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF0284C7),
                        ),
                        label: const Text('Geçiş Raporu (PDF)'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        ),
      ),
    );
  }
}
