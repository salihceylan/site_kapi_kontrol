// Ziyaretçi ve Kargo ekranlarının ortak parçaları (docs/PLATFORM_ZIYARETCI_KARGO.md): tür ikonu, durum çipi,
// yönetim kartı (onaylı eylem düğmeleriyle) ve sakin kartı (okunmamış: kalın + rozet).
//
// Kurallar (İş Takibi ile aynı): metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız renkle
// verilmez (etiket + ikon); kartın TEK birleşik ekran okuyucu etiketi vardır; dokunma hedefleri en az 48 dp; ham
// renk yok. Ziyaretçi adı / firma / not günlüğe yazılmaz.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

IconData visitorKindIcon(VisitorKind kind) => switch (kind) {
  VisitorKind.cargo => Icons.local_shipping_rounded,
  VisitorKind.visitor => Icons.person_pin_circle_rounded,
};

AppTone visitorStatusTone(VisitorStatus status) => switch (status) {
  VisitorStatus.bekliyor => AppTone.warning,
  VisitorStatus.iceride => AppTone.primary,
  VisitorStatus.teslimEdildi => AppTone.success,
  VisitorStatus.ayrildi => AppTone.neutral,
  VisitorStatus.iptal => AppTone.danger,
  VisitorStatus.unknown => AppTone.neutral,
};

IconData visitorStatusIcon(VisitorStatus status) => switch (status) {
  VisitorStatus.bekliyor => Icons.inventory_2_outlined,
  VisitorStatus.iceride => Icons.meeting_room_rounded,
  VisitorStatus.teslimEdildi => Icons.check_circle_outline_rounded,
  VisitorStatus.ayrildi => Icons.logout_rounded,
  VisitorStatus.iptal => Icons.cancel_outlined,
  VisitorStatus.unknown => Icons.help_outline_rounded,
};

/// Durum çipi: ikon + etiket.
class VisitorStatusChip extends StatelessWidget {
  const VisitorStatusChip(this.status, {super.key});

  final VisitorStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    tone: visitorStatusTone(status),
    icon: visitorStatusIcon(status),
  );
}

/// "Yeni" çipi (sakin listesi: görülmemiş kayıt).
class VisitorUnreadChip extends StatelessWidget {
  const VisitorUnreadChip({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip(
    label: 'Yeni',
    tone: AppTone.warning,
    icon: Icons.fiber_new_rounded,
  );
}

/// "n/max" sayacı (aşımda kırmızı + kalın; ekran okuyucu aşımı söyler).
Widget visitorCounter(BuildContext context, int length, int max) {
  final p = context.palette;
  final over = length > max;
  return Semantics(
    liveRegion: over,
    label: over
        ? '$length karakter; en çok $max olabilir, sınır aşıldı'
        : '$length / $max karakter',
    child: ExcludeSemantics(
      child: Text(
        '$length/$max',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: over ? AppTone.danger.ink(p) : p.textSecondary,
          fontWeight: over ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// Yönetim / görevli listesi kartı: tür ikonu, ad, daire, saat, durum çipi ve (yazma yetkisi varsa) sunucunun
/// izin verdiği geçiş düğmeleri ([entry.nextStatuses]); kurulda düğme çizilmez.
class VisitorManagedCard extends StatelessWidget {
  const VisitorManagedCard({
    super.key,
    required this.entry,
    required this.canWrite,
    required this.onAction,
    this.busy = false,
  });

  final VisitorEntry entry;
  final bool canWrite;
  final bool busy;
  final void Function(VisitorStatus next) onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final e = entry;
    final company = e.company?.trim() ?? '';
    final note = e.note?.trim() ?? '';
    final recorded = e.recordedByName?.trim() ?? '';
    final completed = e.completedByName?.trim() ?? '';
    final semantic = StringBuffer(
      '${e.kind.label}: ${e.displayName}. Durum: ${e.status.label}. Daire: ${e.placeText}.',
    );
    if (company.isNotEmpty) semantic.write(' Firma: $company.');
    if (e.arrivedAt != null) {
      semantic.write(' Geliş: ${formatIstanbulDateTime(e.arrivedAt)}.');
    }
    if (e.completedAt != null) {
      semantic.write(' Kapanış: ${formatIstanbulDateTime(e.completedAt)}.');
    }
    if (note.isNotEmpty) semantic.write(' Not: $note.');
    final actions = canWrite ? e.nextStatuses : const <VisitorStatus>[];
    return AppCard(
      padding: listCardPadding(context),
      semanticLabel: semantic.toString(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(
                  icon: visitorKindIcon(e.kind),
                  tone: visitorStatusTone(e.status),
                  gap: AppSpace.md,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          VisitorStatusChip(e.status),
                          InfoChip(e.kind.label),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        e.displayName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: th.titleMedium,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        company.isEmpty
                            ? e.placeText
                            : '${e.placeText} · $company',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: th.bodyMedium?.copyWith(color: p.textSecondary),
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          note,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: th.bodySmall?.copyWith(color: p.textSecondary),
                        ),
                      ],
                      const SizedBox(height: AppSpace.sm),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          if (e.arrivedAt != null)
                            InfoChip(
                              'Geliş: ${formatIstanbulDateTime(e.arrivedAt)}',
                            ),
                          if (e.completedAt != null)
                            InfoChip(
                              'Kapanış: ${formatIstanbulTime(e.completedAt)}',
                            ),
                          if (recorded.isNotEmpty) InfoChip('Kaydeden: $recorded'),
                          if (completed.isNotEmpty) InfoChip('Kapatan: $completed'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final next in actions)
                  PrimaryActionButton(
                    key: ValueKey<String>('visitor_action_${e.id}_${next.apiValue}'),
                    label: next.actionLabel,
                    icon: visitorStatusIcon(next),
                    variant: next == VisitorStatus.iptal
                        ? AppButtonVariant.outline
                        : AppButtonVariant.tonal,
                    tone: next == VisitorStatus.iptal
                        ? AppTone.danger
                        : visitorStatusTone(next),
                    expand: false,
                    onPressed: busy ? null : () => onAction(next),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Sakin listesi kartı: okunmamış kayıt kalın + "Yeni" rozeti; dokununca ([onTap]) görüldü işaretlenir.
class VisitorResidentCard extends StatelessWidget {
  const VisitorResidentCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.showSite = false,
  });

  final VisitorEntry entry;
  final VoidCallback onTap;
  final bool showSite;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final e = entry;
    final company = e.company?.trim() ?? '';
    final note = e.note?.trim() ?? '';
    final site = e.siteName.trim();
    final semantic = StringBuffer(
      '${e.kind.label}: ${e.displayName}. Durum: ${e.status.label}. Daire: ${e.placeText}.',
    );
    if (e.unread) semantic.write(' Yeni, henüz görülmedi.');
    if (company.isNotEmpty) semantic.write(' Firma: $company.');
    if (showSite && site.isNotEmpty) semantic.write(' $site.');
    if (e.arrivedAt != null) {
      semantic.write(' Geliş: ${formatIstanbulDateTime(e.arrivedAt)}.');
    }
    if (note.isNotEmpty) semantic.write(' Not: $note.');
    final weight = e.unread ? FontWeight.w800 : null;
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      tone: e.unread ? AppTone.warning : null,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: visitorKindIcon(e.kind),
              tone: visitorStatusTone(e.status),
              gap: AppSpace.md,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      VisitorStatusChip(e.status),
                      if (e.unread) const VisitorUnreadChip(),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    e.displayName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium?.copyWith(fontWeight: weight),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    company.isEmpty
                        ? '${e.kind.label} · ${e.placeText}'
                        : '${e.kind.label} · $company · ${e.placeText}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.bodyMedium?.copyWith(
                      color: p.textSecondary,
                      fontWeight: weight,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (showSite && site.isNotEmpty) InfoChip(site),
                      if (e.arrivedAt != null)
                        InfoChip('Geliş: ${formatIstanbulDateTime(e.arrivedAt)}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
