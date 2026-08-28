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
  });

  final ApartmentRecord apartment;
  final VoidCallback onEdit;
  final VoidCallback onSendMail;
  final bool sendingMail;

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
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasResident
                  ? AppColors.primarySoft.withValues(alpha: 0.3)
                  : Colors.orange.shade200,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: hasResident
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.home_outlined,
                      color: hasResident
                          ? AppColors.primary
                          : Colors.orange.shade800,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          apartment.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasResident
                              ? 'Sakin: ${apartment.residentFullName}'
                              : 'Daire Boş / Sakin Yok',
                          style: TextStyle(
                            color: hasResident
                                ? AppColors.textMuted
                                : Colors.orange.shade800,
                            fontSize: 12,
                            fontWeight: hasResident
                                ? FontWeight.normal
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      active ? 'Aktif' : 'Pasif',
                      style: TextStyle(
                        color: active
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
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
                          color: AppColors.textDark,
                        ),
                      ),
                    if ((apartment.residentPinCode ?? '').isNotEmpty)
                      Text(
                        'Şifre (PIN): ${apartment.residentPinCode}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                    if (apartment.residentUserCode != null)
                      Text(
                        'Kullanıcı ID: ${apartment.residentUserCode}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                if ((apartment.residentEmail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'E-posta: ${apartment.residentEmail}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if ((apartment.residentPhoneNumber ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Telefon: ${apartment.residentPhoneNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
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
