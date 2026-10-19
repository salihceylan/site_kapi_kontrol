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
    case 'person.created':
    case 'residency.added':
    case 'vehicle.added':
    case 'announcement.created':
    case 'announcement.published':
    case 'site_application.approved':
    case 'finance.definition.created':
    case 'finance.run.posted':
    case 'finance.charge.posted':
    case 'finance.payment.recorded':
    case 'finance.receipt.issued':
    case 'finance.latefee.posted':
    case 'finance.account.created':
    case 'finance.transfer.created':
    case 'finance.expense.created':
    case 'finance.expense.document_attached':
    case 'finance.category.created':
    case 'finance.supplier.created':
    case 'finance.reminder.sent':
    case 'document.created':
    case 'document.version_added':
    case 'document.restored':
    case 'document.attached':
      return AppTone.success;
    case 'module.disabled':
    case 'person.deactivated':
    case 'apartment.deleted':
    case 'apartment.pin_reset':
    case 'announcement.withdrawn':
    case 'finance.definition.deactivated':
    case 'finance.entry.reversed':
    case 'finance.period.closed':
    case 'finance.receipt.cancelled':
    case 'finance.latefee.voided':
    case 'finance.transfer.voided':
    case 'finance.expense.voided':
    case 'finance.legal_gate.updated':
    case 'document.deleted':
    case 'document.version_deleted':
    case 'document.detached':
      return AppTone.warning;
    case 'staff_role.removed':
    case 'module_request.cancelled':
    case 'residency.ended':
    case 'vehicle.removed':
    case 'announcement.deleted':
    case 'site_application.cancelled':
    case 'finance.expense.document_removed':
    case 'finance.reminder.cancelled':
    case 'finance.reminder.exclusion_removed':
      return AppTone.neutral;
    case 'module_request.created':
    case 'announcement.updated':
    case 'announcement.scheduled':
    case 'site_application.created':
    case 'platform_settings.updated':
    case 'finance.definition.updated':
    case 'finance.entry.corrected':
    case 'finance.period.reopened':
    case 'finance.settings.updated':
    case 'finance.receipt.printed':
    case 'finance.account.updated':
    case 'finance.account.adjusted':
    case 'finance.reconciliation.recorded':
    case 'finance.payments.assigned':
    case 'finance.expense.corrected':
    case 'finance.category.updated':
    case 'finance.supplier.updated':
    case 'finance.report.debtor_list':
    case 'finance.reminder.exclusion_added':
    case 'document.updated':
      return AppTone.info;
    case 'module_request.rejected':
    case 'site_application.rejected':
    case 'document.purged':
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
    case 'system':
      return 'Sistem';
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
        : (actorRole.isEmpty || actorRole == actor ? actor : '$actor • $actorRole');
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
