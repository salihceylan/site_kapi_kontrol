import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Daire satırı. "Daireler" kartının (tek yüzey) içinde düz satır olarak durur; satırlar arasındaki
/// `Divider`'ı üst öğe koyar (kart-içinde-kart kalktı). Dokununca açılır/kapanır.
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
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final apartment = widget.apartment;
    final hasResident = apartment.residentFullName != null &&
        apartment.residentFullName!.trim().isNotEmpty;
    final active =
        apartment.residentIsActive ?? (hasResident && apartment.isActive);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(expanded: _expanded), // Açık/kapalı durumu ekran okuyucuya bildirir (karta birleşir).
              Row(
                children: [
                  IconTile(
                    icon: Icons.home_rounded,
                    tone: hasResident ? AppTone.primary : AppTone.warning,
                    gap: AppSpace.md,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.xs,
                          children: [
                            Text(apartment.label, style: th.titleMedium),
                            StatusChip(
                              label: active ? 'Aktif' : 'Pasif',
                              tone: active ? AppTone.success : AppTone.danger,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          hasResident
                              ? 'Sakin: ${apartment.residentFullName}'
                              : 'Daire Boş / Sakin Yok',
                          style: hasResident
                              ? th.bodyMedium
                              : th.bodyMedium?.copyWith(
                                  color: AppTone.warning.ink(p),
                                  fontWeight: FontWeight.w600,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  ExpandChevron(expanded: _expanded),
                ],
              ),
              ExpandableSection(
                expanded: _expanded,
                child: _buildDetails(context, hasResident),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, bool hasResident) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final apartment = widget.apartment;
    final strong = th.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: p.text,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.md),
        const Divider(),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.lg,
          runSpacing: AppSpace.xs,
          children: [
            if ((apartment.residentLoginName ?? '').isNotEmpty)
              Text(
                'Kullanıcı Adı: ${apartment.residentLoginName}',
                style: strong,
              ),
            if ((apartment.residentPinCode ?? '').isNotEmpty)
              Text('Şifre (PIN): ${apartment.residentPinCode}', style: strong),
            if (apartment.residentUserCode != null)
              Text(
                'Kullanıcı ID: ${apartment.residentUserCode}',
                style: th.bodyMedium,
              ),
          ],
        ),
        if ((apartment.residentEmail ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text('E-posta: ${apartment.residentEmail}', style: th.bodyMedium),
        ],
        if ((apartment.residentPhoneNumber ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            'Telefon: ${apartment.residentPhoneNumber}',
            style: th.bodyMedium,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            if ((apartment.residentEmail ?? '').isNotEmpty)
              OutlinedButton.icon(
                onPressed: widget.sendingMail ? null : widget.onSendMail,
                style: tonalActionStyle(context),
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
              style: tonalActionStyle(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Düzenle'),
            ),
            if (hasResident && widget.onDelete != null)
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                style: dangerOutlineStyle(context),
                icon: const Icon(Icons.person_remove_outlined, size: 16),
                label: const Text('Sakini Sil'),
              ),
          ],
        ),
      ],
    );
  }
}
