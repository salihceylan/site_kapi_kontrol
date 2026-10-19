import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_pin_dialogs.dart'
    show kApartmentPinNeedsSuper;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Daire satırındaki PIN notu (KVKK m.12: sunucu PIN'i saklamaz, liste PIN taşımaz).
const String kApartmentPinOnceNotice =
    'PIN yalnız oluşturulurken bir kez gösterilir; unutulduysa yenileyin.';

/// Daire satırı. "Daireler" kartının (tek yüzey) içinde düz satır olarak durur; satırlar arasındaki
/// `Divider`'ı üst öğe koyar (kart-içinde-kart kalktı). Dokununca açılır/kapanır.
class ApartmentCard extends StatefulWidget {
  const ApartmentCard({
    super.key,
    required this.apartment,
    required this.onEdit,
    this.onResetPin,
    this.resettingPin = false,
    this.isSuperUser = false,
    this.onDelete,
  });

  final ApartmentRecord apartment;
  final VoidCallback onEdit;

  /// "PIN'i Sıfırla" (yalnız dahili daire hesabında ve yetkili rolde verilir). Yeni PIN bir kez gösterilir.
  final VoidCallback? onResetPin;
  final bool resettingPin;

  /// Sakin şifresini kendisi belirlemişse ([ApartmentRecord.residentPinIssued] false) PIN'i yalnız süper kullanıcı
  /// sıfırlayabilir; yöneticide düğme devre dışıdır ve [kApartmentPinNeedsSuper] açıklaması gösterilir.
  final bool isSuperUser;
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
                  // Dolu daire = mor (daire kullanıcısı rolü), boş daire = uyarı: ton anlam taşır.
                  IconTile(
                    icon: Icons.home_rounded,
                    tone: hasResident ? AppTone.violet : AppTone.warning,
                    size: 40,
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
    // PIN sunucuda SAKLANMAZ: yalnız "verildi" durumu gösterilir; PIN'in kendisi hiçbir zaman burada yazmaz.
    final pinResettable = hasResident && apartment.residentPinResettable;
    // Sakin şifresini kendisi belirlemiş: yalnız süper kullanıcı sıfırlayabilir (sunucu yöneticiye 409 verir).
    final needsSuper =
        pinResettable && !apartment.residentPinIssued && !widget.isSuperUser;
    final showPinState =
        hasResident &&
        (apartment.residentPinIssued || apartment.residentPinResettable);

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
            if (showPinState)
              Text(
                apartment.residentPinIssued
                    ? 'Şifre (PIN): yönetim verdi'
                    : 'Şifre (PIN): sakin kendisi belirledi',
                style: strong,
              ),
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
        if (pinResettable) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            tone: AppTone.info,
            icon: needsSuper
                ? Icons.lock_person_outlined
                : Icons.lock_outline_rounded,
            message: needsSuper
                ? kApartmentPinNeedsSuper
                : kApartmentPinOnceNotice,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            if (pinResettable && widget.onResetPin != null)
              OutlinedButton.icon(
                onPressed: widget.resettingPin || needsSuper
                    ? null
                    : widget.onResetPin,
                style: tonalActionStyle(context, tone: AppTone.warning),
                icon: widget.resettingPin
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset_rounded, size: 16),
                label: const Text("PIN'i Sıfırla"),
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
