import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Kişi listesi kartı: ad, hesap / eski sakin rozeti, telefon, e-posta, ilişki
/// çipleri, daire etiketleri ve araç sayısı.
///
/// Kart yanında tekil işlem menüsü (düzenle, hesap tanımlama, şifre sıfırlama, davet, ilişik kesme)
/// ve çoklu seçim kipi (checkbox) destekler.
///
/// Ad soyadının altında veya sağındaki üç noktada kolayca hesap (kullanıcı adı ve geçici şifre)
/// tanımlama imkânı sunar.
class PersonCard extends StatelessWidget {
  const PersonCard({
    super.key,
    required this.person,
    required this.onTap,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onSelectChanged,
    this.onEdit,
    this.onPasswordReset,
    this.onInvite,
    this.onToggleActive,
    this.onProvisionAccount,
    this.onDirectResetPin,
  });

  final PersonSummary person;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isSelectionMode;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onPasswordReset;
  final VoidCallback? onInvite;
  final VoidCallback? onToggleActive;
  final VoidCallback? onProvisionAccount;
  final VoidCallback? onDirectResetPin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final phone = formatPhoneDisplay(person.phone);
    final email = person.email ?? '';
    final name = person.fullName.trim().isEmpty ? 'İsimsiz kişi' : person.fullName.trim();

    final hasAnyAction = onEdit != null ||
        onPasswordReset != null ||
        onInvite != null ||
        onToggleActive != null ||
        onProvisionAccount != null ||
        onDirectResetPin != null;

    return AppCard(
      padding: listCardPadding(context),
      onTap: isSelectionMode ? () => onSelectChanged?.call(!isSelected) : onTap,
      semanticLabel: 'Kişi kartı: $name',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSelectionMode) ...[
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.xs),
              child: Checkbox(
                value: isSelected,
                onChanged: onSelectChanged,
                activeColor: AppTone.primary.a,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
          InitialAvatar(
            name: name,
            tone: person.isActive ? AppTone.primary : AppTone.neutral,
            gap: AppSpace.md,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: th.titleMedium),
                if (person.isAdmin || person.hasAccount || !person.isActive) ...[
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (person.isAdmin)
                        const StatusChip(
                          label: 'Daire Admini',
                          tone: AppTone.warning,
                          icon: Icons.shield_rounded,
                        ),
                      if (person.hasAccount)
                        const StatusChip(
                          label: 'Hesabı var',
                          tone: AppTone.success,
                          icon: Icons.verified_user_rounded,
                        ),
                      if (!person.isActive)
                        const StatusChip(
                          label: 'Eski sakin',
                          tone: AppTone.neutral,
                          icon: Icons.history_rounded,
                        ),
                    ],
                  ),
                ],
                // Ad soyadın hemen altında: Hesapsız kişiye tek tıkla hesap tanımlama / şifre verme butonu
                if (!person.hasAccount && onProvisionAccount != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  OutlinedButton.icon(
                    onPressed: onProvisionAccount,
                    icon: const Icon(Icons.key_rounded, size: 14, color: Colors.teal),
                    label: const Text('Hesap Tanımla (Kullanıcı Adı / Şifre)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal.shade800,
                      side: BorderSide(color: Colors.teal.shade300),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ] else if (person.hasAccount && onDirectResetPin != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  OutlinedButton.icon(
                    onPressed: onDirectResetPin,
                    icon: const Icon(Icons.lock_reset_rounded, size: 14, color: Colors.orange),
                    label: const Text('Geçici Şifre / PIN Sıfırla'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(color: Colors.orange.shade300),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(phone, style: secondary),
                ],
                if (email.isNotEmpty) Text(email, style: secondary),
                if (person.relations.isNotEmpty ||
                    person.apartments.isNotEmpty ||
                    person.vehicleCount > 0) ...[
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      for (final relation in person.relations) RelationChip(relation),
                      for (final apartment in person.apartments)
                        InfoChip(
                          apartment.fullLabel,
                          tone: apartment.isAdmin ? AppTone.warning : null,
                        ),
                      if (person.vehicleCount > 0)
                        InfoChip('${person.vehicleCount} araç'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!isSelectionMode && hasAnyAction) ...[
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: p.textMuted, size: 22),
              tooltip: 'İşlemler',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: p.surface,
              onSelected: (action) {
                switch (action) {
                  case 'details':
                    onTap();
                  case 'provision_account':
                    onProvisionAccount?.call();
                  case 'direct_reset_pin':
                    onDirectResetPin?.call();
                  case 'edit':
                    onEdit?.call();
                  case 'reset_password':
                    onPasswordReset?.call();
                  case 'invite':
                    onInvite?.call();
                  case 'toggle_active':
                    onToggleActive?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'details',
                  child: Row(
                    children: [
                      Icon(Icons.person_search_rounded, size: 18),
                      SizedBox(width: AppSpace.sm),
                      Text('Detayları Gör'),
                    ],
                  ),
                ),
                if (!person.hasAccount && onProvisionAccount != null)
                  const PopupMenuItem<String>(
                    value: 'provision_account',
                    child: Row(
                      children: [
                        Icon(Icons.key_rounded, size: 18, color: Colors.teal),
                        SizedBox(width: AppSpace.sm),
                        Text('Hesap Tanımla (Kullanıcı Adı / Şifre)'),
                      ],
                    ),
                  ),
                if (person.hasAccount && onDirectResetPin != null)
                  PopupMenuItem<String>(
                    value: 'direct_reset_pin',
                    child: Row(
                      children: [
                        Icon(Icons.lock_reset_rounded, size: 18, color: Colors.orange.shade800),
                        const SizedBox(width: AppSpace.sm),
                        const Text('Geçici Şifre / PIN Sıfırla'),
                      ],
                    ),
                  ),
                if (onEdit != null)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: AppSpace.sm),
                        Text('Düzenle'),
                      ],
                    ),
                  ),
                if (person.hasAccount && onPasswordReset != null)
                  const PopupMenuItem<String>(
                    value: 'reset_password',
                    child: Row(
                      children: [
                        Icon(Icons.forward_to_inbox_rounded, size: 18, color: Colors.blue),
                        SizedBox(width: AppSpace.sm),
                        Text('Şifre Sıfırlama E-postası Gönder'),
                      ],
                    ),
                  ),
                if (!person.hasAccount && email.isNotEmpty && onInvite != null)
                  const PopupMenuItem<String>(
                    value: 'invite',
                    child: Row(
                      children: [
                        Icon(Icons.send_rounded, size: 18, color: Colors.green),
                        SizedBox(width: AppSpace.sm),
                        Text('Uygulamaya Davet Et'),
                      ],
                    ),
                  ),
                if (onToggleActive != null)
                  PopupMenuItem<String>(
                    value: 'toggle_active',
                    child: Row(
                      children: [
                        Icon(
                          person.isActive ? Icons.person_off_rounded : Icons.person_add_alt_1_rounded,
                          size: 18,
                          color: person.isActive ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(person.isActive ? 'İlişiği Kes (Pasife Al)' : 'Yeniden Etkinleştir'),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
