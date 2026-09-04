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
    final site = widget.site;
    final isSelected = widget.selected;
    final hasManager =
        site.managerName != null && site.managerName!.trim().isNotEmpty;
    final approvalColor = site.approvalStatus == 'approved'
        ? AppColors.emeraldLight
        : (site.approvalStatus == 'rejected' ? AppColors.roseLight : AppColors.amberLight);

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
            color: isSelected
                ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                : const Color(0xFF1E293B).withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryLight
                  : const Color(0x22FFFFFF),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.25)
                    : const Color(0x30000000),
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
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.accent,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            letterSpacing: -0.2,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasManager
                              ? 'Yönetici: ${site.managerName}'
                              : 'Yönetici atanmamış',
                          style: TextStyle(
                            color: hasManager
                                ? AppColors.textMutedLight
                                : AppColors.amberLight,
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
                    color: AppColors.textMutedLight,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Color(0x1FFFFFFF), height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _buildChip('ID: ${site.id}'),
                    _buildChip('MQTT: ${site.mqttSiteId}'),
                    _buildChip('Blok: ${site.blockCount}'),
                    _buildChip('Daire: ${site.apartmentCount}'),
                    _buildChip('Kapı: ${site.doorCount}'),
                  ],
                ),
                if (site.managerUserCode != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Yönetici Kodu: ${site.managerUserCode}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
                if ((site.address ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Adres: ${site.address}',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
                  ),
                ],
                if ((site.city ?? '').isNotEmpty ||
                    (site.district ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Konum: ${site.city ?? '-'} / ${site.district ?? '-'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Kayıt: ${widget.formattedCreatedAt}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.approvalBusy || widget.deleteBusy)
                  const Center(child: CircularProgressIndicator())
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.onEdit != null)
                        OutlinedButton.icon(
                          onPressed: widget.onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Düzenle'),
                        ),
                      if (widget.onDelete != null)
                        OutlinedButton.icon(
                          onPressed: widget.onDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.roseLight,
                            side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Sil'),
                        ),
                      if (widget.onApprove != null)
                        FilledButton.icon(
                          onPressed: widget.onApprove,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('Onayla'),
                        ),
                      if (widget.onReject != null)
                        OutlinedButton.icon(
                          onPressed: widget.onReject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.roseLight,
                            side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
                          ),
                          icon: const Icon(Icons.block_outlined, size: 16),
                          label: const Text('Reddet'),
                        ),
                      if (widget.onDownloadPdf != null)
                        OutlinedButton.icon(
                          onPressed: widget.onDownloadPdf,
                          icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 16,
                            color: Color(0xFF93C5FD),
                          ),
                          label: const Text('Şifreleri İndir (PDF)'),
                        ),
                      if (widget.onDownloadLogsPdf != null)
                        OutlinedButton.icon(
                          onPressed: widget.onDownloadLogsPdf,
                          icon: const Icon(
                            Icons.assignment_outlined,
                            size: 16,
                            color: Color(0xFF60A5FA),
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

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}
