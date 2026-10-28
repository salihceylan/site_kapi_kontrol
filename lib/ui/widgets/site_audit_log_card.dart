import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_audit_log.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart' show auditToneOf;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "İşlem kayıtları" satırı (site yöneticisi): ne yapıldı (çip) + hedef, kim yaptı, kategori, ne zaman (İstanbul saati).
///
/// Kişisel veri asgari: kullanıcı kodu, e-posta, telefon, parola yoktur (sunucu göndermez). Taşma: çip tek satır + elips,
/// tüm metinler sarar. Süper kullanıcı ekranındaki `AuditLogCard`'dan farkı: site satırı yoktur (liste tek siteye aittir) ve
/// zaman İstanbul saatiyle yazılır (tarih süzgeci de İstanbul günüdür).
class SiteAuditLogCard extends StatelessWidget {
  const SiteAuditLogCard({super.key, required this.entry});

  final SiteAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final target = entry.targetLabel;
    final category = (entry.categoryLabel ?? '').trim();
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(label: entry.title, tone: auditToneOf(entry.action), icon: Icons.history_rounded),
          if (target != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(target, style: th.titleMedium),
          ],
          const SizedBox(height: AppSpace.xs),
          Text(entry.actorLine, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          if (category.isNotEmpty)
            Text(category, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          const SizedBox(height: AppSpace.xs),
          Text(formatIstanbulDateTime(entry.createdAt), style: th.bodySmall),
        ],
      ),
    );
  }
}
