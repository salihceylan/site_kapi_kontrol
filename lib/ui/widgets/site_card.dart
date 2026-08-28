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
        ? Colors.green
        : (site.approvalStatus == 'rejected' ? Colors.red : Colors.orange);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          widget.onTap();
          setState(() => _expanded = !_expanded);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primarySoft.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.primarySoft.withValues(alpha: 0.25),
              width: isSelected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.shadowDark
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: isSelected ? 14 : 6,
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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasManager
                              ? 'Yönetici: ${site.managerName}'
                              : 'Yönetici atanmamış',
                          style: TextStyle(
                            color: hasManager
                                ? AppColors.textMuted
                                : Colors.orange.shade800,
                            fontSize: 12.5,
                            fontWeight: hasManager
                                ? FontWeight.normal
                                : FontWeight.w500,
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
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: approvalColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Onay Bekliyor',
                        style: TextStyle(
                          color: approvalColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text('ID: ${site.id}', style: const TextStyle(fontSize: 12.5)),
                    Text(
                      'MQTT Site ID: ${site.mqttSiteId}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'Blok: ${site.blockCount}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'Daire: ${site.apartmentCount}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'Kapı: ${site.doorCount}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
                if (site.managerUserCode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Yönetici Kodu: ${site.managerUserCode}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if ((site.address ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Adres: ${site.address}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
                if ((site.city ?? '').isNotEmpty ||
                    (site.district ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Konum: ${site.city ?? '-'} / ${site.district ?? '-'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
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
                const SizedBox(height: 12),
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
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Sil'),
                        ),
                      if (widget.onApprove != null)
                        FilledButton.icon(
                          onPressed: widget.onApprove,
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('Onayla'),
                        ),
                      if (widget.onReject != null)
                        OutlinedButton.icon(
                          onPressed: widget.onReject,
                          icon: const Icon(Icons.block_outlined, size: 16),
                          label: const Text('Reddet'),
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
}
