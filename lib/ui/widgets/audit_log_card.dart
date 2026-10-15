import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Eylem adına göre çip tonu: açma/atama -> success, kapatma -> warning, kaldırma -> neutral,
/// bilinmeyen -> info (kayıt yine görünür).
AppTone auditToneOf(String action) {
  switch (action) {
    case 'module.enabled':
    case 'staff_role.assigned':
    case 'module_request.approved':
      return AppTone.success;
    case 'module.disabled':
      return AppTone.warning;
    case 'staff_role.removed':
    case 'module_request.cancelled':
      return AppTone.neutral;
    case 'module_request.created':
      return AppTone.info;
    case 'module_request.rejected':
      return AppTone.danger;
    default:
      return AppTone.info;
  }
}

/// İşlemi yapanın okunur rol adı (sunucudaki `actor_role` değerinden).
String auditActorRoleLabel(String? role) {
  switch (role) {
    case 'super_user':
      return 'Süper Kullanıcı';
    case 'site_manager':
      return 'Site Yöneticisi';
    case 'apartment_owner':
      return 'Daire Sakini';
    case 'individual':
      return 'Bireysel Kullanıcı';
    default:
      return role ?? '';
  }
}

/// Denetim kaydı satırı: ne yapıldı (çip) + hedef, kim yaptı, hangi site, ne zaman.
/// Taşma: tüm metinler sarar, çip tek satır + elips.
class AuditLogCard extends StatelessWidget {
  const AuditLogCard({super.key, required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final target = entry.targetLabel;
    final actor = (entry.actorName ?? '').trim();
    final actorRole = auditActorRoleLabel(entry.actorRole);
    final who = actor.isEmpty
        ? (actorRole.isEmpty ? 'Sistem' : actorRole)
        : (actorRole.isEmpty ? actor : '$actor • $actorRole');
    final site = (entry.siteName ?? '').trim();

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(
            label: entry.actionLabel,
            tone: auditToneOf(entry.action),
            icon: Icons.history_rounded,
          ),
          if (target != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(target, style: th.titleMedium),
          ],
          const SizedBox(height: AppSpace.xs),
          Text(who, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          if (site.isNotEmpty)
            Text('Site: $site', style: th.bodyMedium?.copyWith(color: p.textSecondary))
          else if (entry.siteCode != null)
            Text(
              'Site kodu: ${entry.siteCode}',
              style: th.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          const SizedBox(height: AppSpace.xs),
          Text(formatDateTime(entry.createdAt), style: th.bodySmall),
        ],
      ),
    );
  }
}
