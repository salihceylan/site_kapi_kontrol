import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_card.dart';

/// Talep durumuna göre çip tonu ve simgesi (renk tek başına anlam taşımaz: etiket de farklıdır).
({AppTone tone, IconData icon}) moduleRequestStatusStyle(String status) {
  switch (status) {
    case ModuleRequestStatus.approved:
      return (tone: AppTone.success, icon: Icons.check_circle_rounded);
    case ModuleRequestStatus.rejected:
      return (tone: AppTone.danger, icon: Icons.cancel_rounded);
    case ModuleRequestStatus.cancelled:
      return (tone: AppTone.neutral, icon: Icons.undo_rounded);
    default:
      return (tone: AppTone.warning, icon: Icons.hourglass_top_rounded);
  }
}

/// Modül talebi kartı (Platform Faz 1.1): durum, modül, [showSite] iken site, isteyen, not, tarih ve
/// (karara bağlanmışsa) karar bilgisi. [onApprove] / [onReject] verilirse (süper kullanıcı, bekleyen
/// talep) "Onayla" ve "Reddet" düğmeleri çıkar; [busy] iken yerlerine ilerleme göstergesi gelir.
///
/// Taşma: tüm metinler sarar (kırpılmaz), çip tek satır + elips, düğmeler `Wrap` içindedir.
class ModuleRequestCard extends StatelessWidget {
  const ModuleRequestCard({
    super.key,
    required this.request,
    this.showSite = false,
    this.busy = false,
    this.onApprove,
    this.onReject,
  });

  final ModuleRequest request;
  final bool showSite;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final style = moduleRequestStatusStyle(request.status);
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final site = request.siteName.trim().isEmpty
        ? 'Site ${request.siteCode}'
        : '${request.siteName} (${request.siteCode})';
    // Geri çekilen talepte "karar veren" yazılmaz (sunucu geri çekenin adını decided_by'a koyar);
    // yalnız tarih gösterilir.
    final cancelled = request.status == ModuleRequestStatus.cancelled;
    final decided = !request.isPending && request.decidedAt != null;
    final hasActions = request.isPending && (onApprove != null || onReject != null);

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: moduleIconOf(request.moduleCode),
                tone: style.tone,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.moduleLabel, style: th.titleMedium),
                    const SizedBox(height: AppSpace.xs),
                    StatusChip(
                      label: request.statusLabel,
                      tone: style.tone,
                      icon: style.icon,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (showSite) Text('Site: $site', style: secondary),
          if ((request.requestedByName ?? '').isNotEmpty)
            Text('İsteyen: ${request.requestedByName}', style: secondary),
          if ((request.note ?? '').isNotEmpty)
            Text('Not: ${request.note}', style: secondary),
          const SizedBox(height: AppSpace.xs),
          Text(formatDateTime(request.createdAt), style: th.bodySmall),
          if (decided) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              cancelled
                  ? '${request.statusLabel} • ${formatDateTime(request.decidedAt)}'
                  : '${request.statusLabel}: ${(request.decidedByName ?? '').isEmpty ? '-' : request.decidedByName}'
                        ' • ${formatDateTime(request.decidedAt)}',
              style: secondary,
            ),
            if (!cancelled && (request.decisionNote ?? '').isNotEmpty)
              Text('Gerekçe: ${request.decisionNote}', style: secondary),
          ],
          if (hasActions) ...[
            const SizedBox(height: AppSpace.md),
            if (busy)
              const SizedBox(
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  if (onApprove != null)
                    ElevatedButton.icon(
                      onPressed: withLightHaptic(onApprove),
                      style: filledToneStyle(context, tone: AppTone.success),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Onayla'),
                    ),
                  if (onReject != null)
                    OutlinedButton.icon(
                      onPressed: onReject,
                      style: dangerOutlineStyle(context),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Reddet'),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
