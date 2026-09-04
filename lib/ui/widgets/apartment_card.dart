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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.85)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasResident
                  ? (isDark ? const Color(0x333B82F6) : const Color(0xFFBFDBFE))
                  : (isDark ? const Color(0x33F59E0B) : const Color(0xFFFED7AA)),
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
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: hasResident
                          ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                          : AppColors.amber.withValues(alpha: isDark ? 0.2 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.home_rounded,
                      color: hasResident
                          ? (isDark ? AppColors.accentLight : AppColors.primary)
                          : (isDark ? AppColors.amberLight : const Color(0xFFD97706)),
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
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasResident
                              ? 'Sakin: ${apartment.residentFullName}'
                              : 'Daire Boş / Sakin Yok',
                          style: TextStyle(
                            color: hasResident
                                ? (isDark ? AppColors.textMutedLight : AppColors.textMuted)
                                : (isDark ? AppColors.amberLight : const Color(0xFFD97706)),
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
                        color: active
                            ? (isDark ? AppColors.emeraldLight : const Color(0xFF059669))
                            : (isDark ? AppColors.roseLight : AppColors.rose),
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
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(
                    color: isDark ? const Color(0x1FFFFFFF) : const Color(0x150F172A),
                    height: 1,
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if ((apartment.residentLoginName ?? '').isNotEmpty)
                      Text(
                        'Kullanıcı Adı: ${apartment.residentLoginName}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if ((apartment.residentPinCode ?? '').isNotEmpty)
                      Text(
                        'Şifre (PIN): ${apartment.residentPinCode}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (apartment.residentUserCode != null)
                      Text(
                        'Kullanıcı ID: ${apartment.residentUserCode}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                if ((apartment.residentEmail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'E-posta: ${apartment.residentEmail}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    ),
                  ),
                ],
                if ((apartment.residentPhoneNumber ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Telefon: ${apartment.residentPhoneNumber}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
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
