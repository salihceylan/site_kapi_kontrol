import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Kişi listesi kartı (Platform Faz 2a): ad, hesap / eski sakin rozeti, telefon, e-posta, ilişki
/// çipleri, daire etiketleri ve araç sayısı. Dokununca kişi kartı açılır ([onTap]).
///
/// Taşma: tüm metinler sarar (kırpılmaz); çipler `Wrap` içindedir. Büyük yazıda (>= 1,75x) avatar
/// `InitialAvatar` tarafından kendiliğinden gizlenir (kod koşulsuz çizer, gizlemeyi bileşen yapar).
class PersonCard extends StatelessWidget {
  const PersonCard({super.key, required this.person, required this.onTap});

  final PersonSummary person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final phone = formatPhoneDisplay(person.phone);
    final email = person.email ?? '';
    final name = person.fullName.trim().isEmpty ? 'İsimsiz kişi' : person.fullName.trim();

    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: 'Kişi kartı: $name',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                if (person.hasAccount || !person.isActive) ...[
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
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
                        InfoChip(apartment.fullLabel),
                      if (person.vehicleCount > 0)
                        InfoChip('${person.vehicleCount} araç'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
