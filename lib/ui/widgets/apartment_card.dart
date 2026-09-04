import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class ApartmentCard extends StatefulWidget {
  const ApartmentCard({
    super.key,
    required this.apartment,
    required this.onEdit,
    required this.onSendMail,
    required this.sendingMail,
    this.onDelete,
  });

  final ApartmentRecord apartment;
  final VoidCallback onEdit;
  final VoidCallback onSendMail;
  final bool sendingMail;
  final VoidCallback? onDelete;

  @override
  State<ApartmentCard> createState() => _ApartmentCardState();
}

class _ApartmentCardState extends State<ApartmentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final apartment = widget.apartment;
    final hasResident = apartment.residentFullName != null &&
        apartment.residentFullName!.trim().isNotEmpty;
    final active =
        apartment.residentIsActive ?? (hasResident && apartment.isActive);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasResident
                  ? const Color(0x333B82F6)
                  : const Color(0x33F59E0B),
              width: 1.2,
            ),
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
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: hasResident
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.amber.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.home_rounded,
                      color: hasResident ? AppColors.accent : AppColors.amberLight,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          apartment.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasResident
                              ? 'Sakin: ${apartment.residentFullName}'
                              : 'Daire Boş / Sakin Yok',
                          style: TextStyle(
                            color: hasResident
                                ? AppColors.textMutedLight
                                : AppColors.amberLight,
                            fontSize: 12,
                            fontWeight: hasResident
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.emerald.withValues(alpha: 0.15)
                          : AppColors.rose.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active
                            ? AppColors.emerald.withValues(alpha: 0.4)
                            : AppColors.rose.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      active ? 'Aktif' : 'Pasif',
                      style: TextStyle(
                        color: active ? AppColors.emeraldLight : AppColors.roseLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMutedLight,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Color(0x1FFFFFFF), height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if ((apartment.residentLoginName ?? '').isNotEmpty)
                      Text(
                        'Kullanıcı Adı: ${apartment.residentLoginName}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if ((apartment.residentPinCode ?? '').isNotEmpty)
                      Text(
                        'Şifre (PIN): ${apartment.residentPinCode}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (apartment.residentUserCode != null)
                      Text(
                        'Kullanıcı ID: ${apartment.residentUserCode}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                  ],
                ),
                if ((apartment.residentEmail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'E-posta: ${apartment.residentEmail}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
                if ((apartment.residentPhoneNumber ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Telefon: ${apartment.residentPhoneNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((apartment.residentEmail ?? '').isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: widget.sendingMail ? null : widget.onSendMail,
                        icon: widget.sendingMail
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.email_outlined, size: 16),
                        label: const Text('Bilgileri Gönder'),
                      ),
                    ElevatedButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Düzenle'),
                    ),
                    if (hasResident && widget.onDelete != null)
                      OutlinedButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.person_remove_outlined, size: 16, color: AppColors.roseLight),
                        label: const Text('Sakini Sil', style: TextStyle(color: AppColors.roseLight)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
                        ),
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
