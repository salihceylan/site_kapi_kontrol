import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Ek rol (Yönetim Kurulu / Denetçi, Görevli) kartı: kişi, e-posta, rol çipi ve "Rolü Kaldır" düğmesi.
///
/// [busy] iken düğme yerine ilerleme göstergesi çıkar (aynı boyut). [onRemove] null ise düğme
/// yoktur. Taşma: ad ve e-posta sarar (kırpılmaz), çip tek satır + elips.
class StaffRoleCard extends StatelessWidget {
  const StaffRoleCard({
    super.key,
    required this.record,
    this.busy = false,
    this.onRemove,
  });

  final StaffRoleRecord record;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final tone = record.roleType == StaffRoleType.boardMember
        ? AppTone.violet
        : AppTone.info;
    final name = record.fullName.trim().isEmpty ? record.email : record.fullName;

    return AppCard(
      padding: listCardPadding(context),
      child: Row(
        children: [
          InitialAvatar(name: name, tone: tone, gap: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: th.titleMedium),
                if (record.fullName.trim().isNotEmpty)
                  Text(
                    record.email,
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                const SizedBox(height: AppSpace.xs),
                StatusChip(
                  label: record.roleLabel,
                  tone: tone,
                  icon: Icons.badge_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          if (busy)
            const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Rolü Kaldır',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                Icons.person_remove_rounded,
                color: AppTone.danger.ink(p),
              ),
            ),
        ],
      ),
    );
  }
}
