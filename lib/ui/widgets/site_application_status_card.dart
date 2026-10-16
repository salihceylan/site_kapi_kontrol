import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';

/// Bireysel ana ekranın (ve "Daireye Katıl & Cihaz Ekle" ekranının) üstündeki SİTE BAŞVURUSU durum kartı
/// (Platform: site başvurusu). Durum [SiteApplicationTracker]dan gelir; kart yalnız onun görünümüdür.
///
/// - Bekleyen: "Site başvurunuz inceleniyor" (site adı, yapı, tarih) + onaylı "Başvuruyu iptal et".
/// - Reddedildi: gerekçe + "Yeniden başvur" (formu önceki değerlerle açar).
/// - İptal edildi: kısa kart + "Yeniden başvur".
/// - Onaylandı (yakın zamanda): oturum/rol yenilenir; yenileme sürerken / başarısız olursa "Hesabı yenile".
/// - Durum ALINAMADIYSA: hata + "Tekrar Dene" (ASLA "başvuru yok" denmez). Önceki durum varken yoklama
///   hatası kartı silmez; altına uyarı eklenir.
///
/// Çift dokunuş korumaları: iptal / yeniden başvur / hesabı yenile sürerken düğmeler kilitlidir. Zamanlar
/// İstanbul saatiyle gösterilir.
class SiteApplicationStatusCard extends StatefulWidget {
  const SiteApplicationStatusCard({
    super.key,
    required this.tracker,
    required this.onReapply,
    this.onRefreshAccount,
  });

  final SiteApplicationTracker tracker;

  /// "Yeniden başvur": başvuru formunu önceki değerlerle açar.
  final Future<void> Function(SiteApplication previous) onReapply;

  /// Onaylanmış ama rolü henüz yenilenmemiş hesap için elle yenileme (oturum + ekran).
  final Future<void> Function()? onRefreshAccount;

  @override
  State<SiteApplicationStatusCard> createState() => _SiteApplicationStatusCardState();
}

class _SiteApplicationStatusCardState extends State<SiteApplicationStatusCard> {
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(SiteApplication application) => _guarded(() async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Başvuru iptal edilsin mi?',
      message:
          '"${application.siteNameLabel}" site başvurunuz iptal edilecek. Daha sonra yeniden başvurabilirsiniz.',
      confirmLabel: 'Başvuruyu İptal Et',
      icon: Icons.cancel_outlined,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    final cancelled = await widget.tracker.cancelPending();
    if (!mounted) return;
    if (cancelled != null) {
      AppSnack.show(context, 'Başvurunuz iptal edildi.', kind: AppSnackKind.success);
    }
  });

  Future<void> _reapply(SiteApplication application) =>
      _guarded(() => widget.onReapply(application));

  Future<void> _refreshAccount() {
    final refresh = widget.onRefreshAccount;
    if (refresh == null) return Future<void>.value();
    return _guarded(refresh);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tracker,
      builder: (context, _) {
        final tracker = widget.tracker;
        if (!tracker.hasLoaded) {
          final error = tracker.error;
          if (error == null) return const SizedBox.shrink();
          // Durum bilinmiyor: "başvuru yok" DEMEZ.
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: InlineNotice(message: error, onRetry: () => unawaited(tracker.refresh())),
          );
        }
        final latest = tracker.latest;
        if (latest == null) return const SizedBox.shrink();
        final Widget card;
        if (latest.isPending) {
          card = _buildPending(context, tracker, latest);
        } else if (latest.isRejected) {
          card = _buildRejected(context, tracker, latest);
        } else if (latest.isCancelled) {
          card = _buildCancelled(context, tracker, latest);
        } else if (latest.isApproved && _recentlyDecided(latest)) {
          card = _buildApproved(context, tracker, latest);
        } else {
          return const SizedBox.shrink();
        }
        return Padding(padding: const EdgeInsets.only(bottom: AppSpace.lg), child: card);
      },
    );
  }

  static bool _recentlyDecided(SiteApplication a) {
    final decided = a.decidedAt;
    if (decided == null) return true;
    return DateTime.now().difference(decided) < SiteApplicationTracker.approvalWindow;
  }

  // --- Kart gövdeleri ---------------------------------------------------------------------------

  Widget _frame(
    BuildContext context, {
    required AppTone tone,
    required IconData icon,
    required String title,
    required SiteApplication application,
    required List<Widget> children,
  }) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      tone: tone,
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: icon, tone: tone, gap: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: th.titleMedium),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    SiteApplicationStatusChip(application),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _summaryLines(BuildContext context, SiteApplication a) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    return [
      Text(a.siteNameLabel, style: th.titleSmall),
      const SizedBox(height: AppSpace.xs),
      Text(a.structureLabel, style: secondary),
      if (a.createdAt != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text('Başvuru: ${formatIstanbulDateTime(a.createdAt)}', style: th.bodySmall),
      ],
    ];
  }

  Widget _buildPending(BuildContext context, SiteApplicationTracker tracker, SiteApplication a) {
    final th = Theme.of(context).textTheme;
    final cancelling = tracker.cancelling;
    return _frame(
      context,
      tone: AppTone.warning,
      icon: Icons.hourglass_top_rounded,
      title: 'Site başvurunuz inceleniyor',
      application: a,
      children: [
        ..._summaryLines(context, a),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Süper kullanıcı onayladığında site yöneticisi olacaksınız. Durum otomatik güncellenir.',
          style: th.bodyMedium,
        ),
        if (tracker.cancelError != null) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(message: tracker.cancelError!),
        ],
        if (tracker.error != null) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            message: tracker.error!,
            tone: AppTone.warning,
            onRetry: () => unawaited(tracker.refresh()),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        OutlinedButton.icon(
          key: const ValueKey<String>('site_application_cancel'),
          onPressed: (_busy || cancelling) ? null : () => unawaited(_cancel(a)),
          style: dangerOutlineStyle(context),
          icon: cancelling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cancel_outlined, size: 18),
          label: Text(cancelling ? 'İptal ediliyor...' : 'Başvuruyu iptal et'),
        ),
      ],
    );
  }

  Widget _buildRejected(BuildContext context, SiteApplicationTracker tracker, SiteApplication a) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final reason = a.decisionNote;
    return _frame(
      context,
      tone: AppTone.danger,
      icon: Icons.cancel_rounded,
      title: 'Site başvurunuz reddedildi',
      application: a,
      children: [
        ..._summaryLines(context, a),
        const SizedBox(height: AppSpace.sm),
        Text(
          reason == null ? 'Gerekçe belirtilmedi.' : 'Gerekçe: $reason',
          style: th.bodyMedium?.copyWith(color: p.text),
        ),
        if (a.decidedAt != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text('Karar: ${formatIstanbulDateTime(a.decidedAt)}', style: th.bodySmall),
        ],
        const SizedBox(height: AppSpace.md),
        _reapplyButton(a),
      ],
    );
  }

  Widget _buildCancelled(BuildContext context, SiteApplicationTracker tracker, SiteApplication a) {
    final th = Theme.of(context).textTheme;
    return _frame(
      context,
      tone: AppTone.neutral,
      icon: Icons.undo_rounded,
      title: 'Site başvurunuzu iptal ettiniz',
      application: a,
      children: [
        ..._summaryLines(context, a),
        const SizedBox(height: AppSpace.sm),
        Text('İsterseniz yeniden başvurabilirsiniz.', style: th.bodyMedium),
        const SizedBox(height: AppSpace.md),
        _reapplyButton(a),
      ],
    );
  }

  Widget _buildApproved(BuildContext context, SiteApplicationTracker tracker, SiteApplication a) {
    final th = Theme.of(context).textTheme;
    final canRefresh = widget.onRefreshAccount != null;
    return _frame(
      context,
      tone: AppTone.success,
      icon: Icons.check_circle_rounded,
      title: 'Site başvurunuz onaylandı',
      application: a,
      children: [
        ..._summaryLines(context, a),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Siteniz kuruldu. Hesabınız site yöneticisi olarak güncelleniyor; ekran kendiliğinden yenilenir.',
          style: th.bodyMedium,
        ),
        if (canRefresh) ...[
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            key: const ValueKey<String>('site_application_refresh_account'),
            onPressed: _busy ? null : () => unawaited(_refreshAccount()),
            style: tonalActionStyle(context, tone: AppTone.success),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Hesabı yenile'),
          ),
        ],
      ],
    );
  }

  Widget _reapplyButton(SiteApplication a) {
    return ElevatedButton.icon(
      key: const ValueKey<String>('site_application_reapply'),
      onPressed: _busy ? null : () => unawaited(_reapply(a)),
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Yeniden başvur'),
    );
  }
}
