import 'package:flutter/material.dart';
import 'dart:async';

import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Başvuru durumuna göre çip tonu ve simgesi (renk tek başına anlam taşımaz: etiket ve simge de farklıdır).
({AppTone tone, IconData icon}) siteApplicationStatusStyle(String status) {
  switch (status) {
    case SiteApplicationStatus.approved:
      return (tone: AppTone.success, icon: Icons.check_circle_rounded);
    case SiteApplicationStatus.rejected:
      return (tone: AppTone.danger, icon: Icons.cancel_rounded);
    case SiteApplicationStatus.cancelled:
      return (tone: AppTone.neutral, icon: Icons.undo_rounded);
    case SiteApplicationStatus.pending:
      return (tone: AppTone.warning, icon: Icons.hourglass_top_rounded);
    default:
      return (tone: AppTone.neutral, icon: Icons.help_outline_rounded);
  }
}

/// Başvuru durum rozeti.
class SiteApplicationStatusChip extends StatelessWidget {
  const SiteApplicationStatusChip(this.application, {super.key});

  final SiteApplication application;

  @override
  Widget build(BuildContext context) {
    final style = siteApplicationStatusStyle(application.status);
    return StatusChip(label: application.statusLabel, tone: style.tone, icon: style.icon);
  }
}

/// "Başvur" eylemi PASİF olduğunda NEDEN metni (tooltip + ekran okuyucu ipucu); hazırsa null.
String? siteApplyDisabledReason(SiteApplyAvailability availability) {
  switch (availability) {
    case SiteApplyAvailability.ready:
      return null;
    case SiteApplyAvailability.pending:
      return 'Zaten bekleyen bir site başvurunuz var. Sonucunu bekleyin ya da başvuruyu iptal edin.';
    case SiteApplyAvailability.checking:
      return 'Başvuru durumu kontrol ediliyor. Birkaç saniye sonra tekrar deneyin.';
    case SiteApplyAvailability.unknown:
      return 'Başvuru durumu alınamadı. Üstteki "Tekrar Dene" ile yeniden deneyin.';
  }
}

/// "Site Kurmak İçin Başvur" eylemi: durum biliniyor ve bekleyen yokken etkin; bekleyen başvuru varken
/// ("Başvurunuz İnceleniyor"), durum kontrol edilirken ya da ALINAMADIYKEN pasif, nedeni tooltip ve ekran okuyucu
/// ipucuyla söylenir. Tek anahtar: `site_application_apply`.
class SiteApplyCta extends StatelessWidget {
  const SiteApplyCta({super.key, required this.tracker, required this.onApply});

  final SiteApplicationTracker tracker;
  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final availability = tracker.applyAvailability;
        final reason = siteApplyDisabledReason(availability);
        final (IconData icon, String label) = switch (availability) {
          SiteApplyAvailability.ready => (Icons.domain_add_rounded, 'Site Kurmak İçin Başvur'),
          SiteApplyAvailability.pending => (Icons.hourglass_top_rounded, 'Başvurunuz İnceleniyor'),
          SiteApplyAvailability.checking => (Icons.sync_rounded, 'Durum Kontrol Ediliyor...'),
          SiteApplyAvailability.unknown => (Icons.sync_problem_rounded, 'Başvuru Durumu Alınamadı'),
        };
        final button = ElevatedButton.icon(
          key: const ValueKey<String>('site_application_apply'),
          onPressed: reason == null ? () => unawaited(onApply()) : null,
          icon: Icon(icon, size: 20),
          label: Text(label, textAlign: TextAlign.center),
        );
        if (reason == null) return button;
        return Tooltip(
          message: reason,
          child: Semantics(hint: reason, child: button),
        );
      },
    );
  }
}

/// "Abonelikle hemen site aç — Yakında…" PASİF satırı (ödeme altyapısı hazır değil; bugün hiçbir etkisi
/// yoktur). Dokunulamaz; ekran okuyucu "soluk düğme" olarak okur. Metin sarar, kırpılmaz.
class SiteSubscriptionComingSoonRow extends StatelessWidget {
  const SiteSubscriptionComingSoonRow({super.key});

  /// Satırın metni (testler ve ekranlar için tek kaynak).
  static const String label = 'Abonelikle hemen site aç — Yakında…';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: false,
      label: 'Abonelikle hemen site aç, yakında',
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: p.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 20, color: p.textSecondary),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: th.bodyMedium?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Süper kullanıcı listesi kartı: durum, site adı, başvuran, blok/daire/kapı sayısı, tarih ve (karara
/// bağlanmışsa) karar bilgisi. Dokununca ayrıntı penceresi açılır ([onTap]); onay/red YALNIZ ayrıntıdadır
/// (listeden yanlışlıkla onaylanmaz). Metinler sarar; çipler `Wrap` içindedir.
class SiteApplicationAdminCard extends StatelessWidget {
  const SiteApplicationAdminCard({super.key, required this.application, required this.onTap});

  final SiteApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final a = application;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final name = a.siteNameLabel;
    final applicant = a.applicantLabel;
    final created = a.createdAt == null ? null : formatIstanbulDateTime(a.createdAt);
    final decided = !a.isPending && a.decidedAt != null
        ? '${a.statusLabel}: ${formatIstanbulDateTime(a.decidedAt)}'
        : null;
    final semantic = StringBuffer('Site başvurusu: $name. ${a.statusLabel}.');
    semantic.write(' Başvuran: $applicant.');
    semantic.write(' ${a.structureLabel}.');
    if (created != null) semantic.write(' Başvuru zamanı: $created.');
    if (decided != null) semantic.write(' $decided.');

    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                SiteApplicationStatusChip(a),
                if (a.hasDevice) const InfoChip('Cihazlı'),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text('Başvuran: $applicant', style: secondary),
            const SizedBox(height: AppSpace.xs),
            Text(a.structureLabel, style: secondary),
            if (a.locationLabel != null) Text(a.locationLabel!, style: secondary),
            const SizedBox(height: AppSpace.xs),
            if (created != null) Text('Başvuru: $created', style: th.bodySmall),
            if (decided != null) Text(decided, style: th.bodySmall),
          ],
        ),
      ),
    );
  }
}
