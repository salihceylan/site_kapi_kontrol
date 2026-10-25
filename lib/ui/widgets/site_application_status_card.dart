import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';

/// Bireysel ana ekranın (ve "Daireye Katıl" ile yönetici panosunun) üstündeki SİTE BAŞVURUSU
/// durum kartı (Platform: site başvurusu). Durum [SiteApplicationTracker]dan gelir; kart yalnız onun görünümüdür.
///
/// - Bekleyen: "Site başvurunuz inceleniyor" (site adı, tarih, "Başvuruyu iptal et" onaylı).
/// - Reddedildi: gerekçe + "Yeniden başvur" (formu önceki değerlerle açar).
/// - İptal edildi: kısa kart + "Yeniden başvur".
/// - Onaylandı ([showApproved] true iken, rol henüz değişmediyse): oturum/rol yenilenirken "Hesabı yenile".
///   Yenileme sonrası rol hâlâ değişmediyse kart kaldırılır (`consumeApproval`).
/// - Durum sunucudan tanınmayan bir değerse: kısıtlı kart ("Durum bilinmiyor"), hiçbir eylem sunulmaz.
/// - HATA HER DURUMDA görünür: durum hiç alınamadıysa hata + "Tekrar Dene" (asla "başvuru yok" denmez); önceki
///   durum varken yenileme hatası kartın üstüne uyarı olarak eklenir (boş / reddedildi / iptal kartları dahil).
///   Gönderilen başvuru doğrulanamadıysa "Başvurunuz alındı, ancak durum yenilenemedi" bilgisi çıkar.
///
/// Çift dokunuş korumaları: iptal / yeniden başvur / hesabı yenile sürerken düğmeler kilitlidir. Zamanlar
/// İstanbul saatiyle gösterilir.
class SiteApplicationStatusCard extends StatefulWidget {
  const SiteApplicationStatusCard({
    super.key,
    required this.tracker,
    required this.onReapply,
    this.onRefreshAccount,
    this.showApproved = true,
    this.showLoadFailure = true,
    this.showReapplyOnRejected = false,
  });

  final SiteApplicationTracker tracker;

  /// "Yeniden başvur": başvuru formunu önceki değerlerle açar.
  final Future<void> Function(SiteApplication previous) onReapply;

  /// Onaylanmış ama rolü henüz yenilenmemiş hesap için elle yenileme (oturum + ekran).
  final Future<void> Function()? onRefreshAccount;

  /// Onaylandı kartı gösterilsin mi? Yalnız rolü hâlâ başvuran olan hesap için anlamlıdır; site yöneticisinde
  /// (başvurusu onaylanmış) "güncelleniyor" kartı yanıltır.
  final bool showApproved;

  /// Durum HİÇ alınamadığında hata gösterilsin mi? Site yöneticisi panosunda (başvuru gerekli mi belirsiz)
  /// kapatılır: anlık "Site Ekle" çalışmaya devam eder ve sunucu yine de 409 ile yönlendirir.
  final bool showLoadFailure;

  /// Reddedilen başvuruda "Yeniden başvur" düğmesi gösterilsin mi? Panelde (vitrin, bireysel ana ekran)
  /// gereksiz kalabalığı önlemek için false'tur; "Yeni Site" / "Katılım ve Kurulum" gibi başvuru ekranlarında açılabilir.
  final bool showReapplyOnRejected;

  @override
  State<SiteApplicationStatusCard> createState() => _SiteApplicationStatusCardState();
}

class _SiteApplicationStatusCardState extends State<SiteApplicationStatusCard> {
  bool _busy = false;

  /// Kartın başlığı: kart değişince (örn. bekleyen -> iptal edildi) odak buraya taşınır; iptal düğmesi
  /// kaybolunca klavye / ekran okuyucu bağlamı kaybolmaz.
  final FocusNode _titleFocus = FocusNode(debugLabel: 'site_application_card_title');

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

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
      // Düğme kaybolur: odak yeni kartın başlığına taşınır ve değişiklik duyurulur.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _titleFocus.requestFocus();
        announcePolite(context, 'Başvurunuz iptal edildi.');
      });
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
        final children = <Widget>[];

        final notice = _buildNotice(tracker);
        if (notice != null) children.add(notice);

        if (tracker.hasLoaded) {
          final card = _buildCard(context, tracker);
          if (card != null) children.add(card);
        }
        if (children.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.md),
                children[i],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Hata / belirsizlik bildirimi (her durumda; kartın ÜSTÜNDE).
  Widget? _buildNotice(SiteApplicationTracker tracker) {
    final error = tracker.error;
    if (tracker.awaitingConfirmation) {
      return error == null
          ? const InlineNotice(
              tone: AppTone.info,
              icon: Icons.sync_rounded,
              message: 'Başvurunuz alındı. Başvuru durumu kontrol ediliyor...',
            )
          : InlineNotice(
              tone: AppTone.warning,
              message:
                  'Başvurunuz alındı, ancak durum yenilenemedi. Kısa süre sonra yeniden denenecek; '
                  'isterseniz şimdi deneyebilirsiniz.',
              onRetry: () => unawaited(tracker.refresh()),
            );
    }
    if (error == null) return null;
    if (!tracker.hasLoaded) {
      // Durum bilinmiyor: "başvuru yok" DEMEZ.
      return widget.showLoadFailure
          ? InlineNotice(message: error, onRetry: () => unawaited(tracker.refresh()))
          : null;
    }
    return InlineNotice(
      tone: AppTone.warning,
      message: '$error Gösterilen başvuru bilgisi eski olabilir.',
      onRetry: () => unawaited(tracker.refresh()),
    );
  }

  Widget? _buildCard(BuildContext context, SiteApplicationTracker tracker) {
    final latest = tracker.latest;
    if (latest == null) return null;
    if (latest.isPending) return _buildPending(context, tracker, latest);
    if (latest.isRejected) {
      if (tracker.isRejectedConsumed(latest.id)) {
        return null;
      }
      return _buildRejected(context, tracker, latest);
    }
    if (latest.isCancelled) {
      if (tracker.isCancelledConsumed(latest.id)) {
        return null;
      }
      return _buildCancelled(context, tracker, latest);
    }
    if (latest.isApproved) {
      if (!widget.showApproved || tracker.isApprovalConsumed(latest.id) || !_recentlyDecided(latest)) {
        return null;
      }
      return _buildApproved(context, latest);
    }
    return _buildUnknown(context, latest);
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
                    Focus(
                      focusNode: _titleFocus,
                      child: Semantics(
                        header: true,
                        child: Text(title, style: th.titleMedium),
                      ),
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
          label: Semantics(
            liveRegion: cancelling,
            child: Text(cancelling ? 'İptal ediliyor...' : 'Başvuruyu iptal et'),
          ),
        ),
      ],
    );
  }

  Widget _buildRejected(BuildContext context, SiteApplicationTracker tracker, SiteApplication a) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final reason = a.decisionNote;
    final canReapply = widget.showReapplyOnRejected;
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
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey<String>('site_application_dismiss_rejected'),
              onPressed: _busy ? null : () => _dismissRejected(a),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Anladım'),
            ),
            if (canReapply) _reapplyButton(a),
          ],
        ),
      ],
    );
  }

  void _dismissRejected(SiteApplication a) {
    widget.tracker.consumeRejected(a.id);
    announcePolite(context, 'Bildirim kapatıldı.');
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
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey<String>('site_application_dismiss_cancelled'),
              onPressed: _busy ? null : () => _dismissCancelled(a),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Kapat'),
            ),
            _reapplyButton(a),
          ],
        ),
      ],
    );
  }

  void _dismissCancelled(SiteApplication a) {
    widget.tracker.consumeCancelled(a.id);
    announcePolite(context, 'Bildirim kapatıldı.');
  }

  Widget _buildApproved(BuildContext context, SiteApplication a) {
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
            // Meşgulken etiket değişir ve canlı bölge olarak duyurulur (spinner tek başına anlam taşımaz).
            label: Semantics(
              liveRegion: _busy,
              child: Text(_busy ? 'Hesap yenileniyor...' : 'Hesabı yenile'),
            ),
          ),
        ],
      ],
    );
  }

  /// Tanınmayan / eksik durum: kısıtlı görünüm; hiçbir eylem (iptal, yeniden başvur) sunulmaz.
  Widget _buildUnknown(BuildContext context, SiteApplication a) {
    final th = Theme.of(context).textTheme;
    return _frame(
      context,
      tone: AppTone.neutral,
      icon: Icons.help_outline_rounded,
      title: 'Site başvurunuz',
      application: a,
      children: [
        ..._summaryLines(context, a),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Başvurunuzun durumu anlaşılamadı. Güncellemek için aşağı çekip yenileyin.',
          style: th.bodyMedium,
        ),
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
