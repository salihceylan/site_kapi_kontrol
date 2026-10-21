import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Aylık gecikme tazminatı hesaplama ve onay penceresi (Platform Faz 4b, Ö2).
///
/// Akış: ay seç -> ÖNİZLEME (hiçbir şey yazmaz: toplam, daire sayısı, her dairenin tutarı ve "nasıl hesaplandı" dökümü,
/// muaf / pasif / sıfır tutarlı daireler, engeller) -> ayrı bir ONAY penceresi -> yaz.
///
/// Para bütünlüğü (4a ders kitabı):
/// - Tazminatı SUNUCU hesaplar; istemci tutarı yeniden hesaplamaz, yalnız dökümü gösterir.
/// - Onay, önizlemedeki toplam / daire sayısı / `preview_hash`'i bildirir; arada veri (ödeme, ayar, muaf liste) değişirse
///   sunucu 409 `PREVIEW_STALE` döner ve HİÇBİR ŞEY yazılmaz: önizleme OTOMATİK yenilenir, eski ve yeni toplam yazılır,
///   yenileme sürerken / başarısızken eski önizlemeyle onay KAPALIDIR. Muaf listesi değişince de önizleme eskir.
/// - Sunucu `can_post: false` dediyse (ay kapalı değil, ay bitmedi, zincir sırası, zaten yazılmış ...) onay kapalıdır ve
///   neden yönlendirici metinle söylenir ("Önce Eylül 2026 dönemini kapatın").
/// - `idempotency_key` işlem imzasına (ay + muaf kümesi + özet) bağlıdır; belirsiz sonuçtan sonra aynı imza = aynı anahtar.
/// - Tazminat OTOMATİK değildir: her ay açıkça önizlenip onaylanır.
class FinanceLateFeeDialog extends StatefulWidget {
  const FinanceLateFeeDialog({
    super.key,
    required this.scope,
    this.initialPeriod,
    this.now,
    this.onRefreshNeeded,
  });

  final PeopleScope scope;

  /// Sunucunun bildirdiği sıradaki ay (`next_period`); yoksa bir önceki ay.
  final FinancePeriod? initialPeriod;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int pageSize = 50;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    FinancePeriod? initialPeriod,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceLateFeeDialog(scope: scope, initialPeriod: initialPeriod, now: now, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceLateFeeDialog> createState() => _FinanceLateFeeDialogState();
}

class _FinanceLateFeeDialogState extends State<FinanceLateFeeDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'latefee';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting || _previewing || _asking;

  // Kaydedilmemiş veri: işaretlenmiş muaf daireler (ay seçimi ve önizleme yeniden üretilebilir).
  @override
  bool get hasUnsavedChanges => _excluded.isNotEmpty;

  late FinancePeriod _period = widget.initialPeriod ?? _currentPeriod.previous;
  LateFeePreview? _preview;
  final Set<int> _excluded = <int>{};

  // Önizlemenin hesaplandığı muaf kümesi: kullanıcı kümeyi değiştirince önizleme eskir.
  Set<int> _previewExcluded = <int>{};
  bool _previewing = false;
  bool _stale = false;
  LateFeePreview? _staleFrom;
  String? _notice;
  String? _previewError;
  bool _previewBusy = false; // REPORT_BUSY (503): önizleme yuvası dolu -> "Tekrar Dene" (otomatik yeniden deneme YOK)
  int _previewToken = 0;
  int _visible = FinanceLateFeeDialog.pageSize;
  bool _asking = false;
  // İP-1A: aynı dairenin iki hesabı iki satırdır: döküm satır anahtarıyla açılır ([LateFeeLine.lineKey]); muafiyet daire başınadır.
  final Set<String> _explained = <String>{};
  final RetryLock _previewRetry = RetryLock();

  FinancePeriod get _currentPeriod => FinancePeriod.of(istanbulNow(widget.now?.call()));

  bool get _excludedChanged => !(_excluded.length == _previewExcluded.length && _excluded.containsAll(_previewExcluded));

  @override
  void dispose() {
    ++_previewToken;
    _previewRetry.dispose();
    disposeWrite();
    super.dispose();
  }

  // --- Önizleme --------------------------------------------------------------------------------

  Future<void> _requestPreview({LateFeePreview? staleFrom}) async {
    if (_previewing || submitting || _previewRetry.locked) return;
    final token = ++_previewToken;
    final excluded = Set<int>.of(_excluded);
    setState(() {
      _previewing = true;
      _previewError = null;
      _previewBusy = false;
      _notice = null;
    });
    try {
      final preview = await widget.scope.f4Call(
        (api, t, s) => api.previewLateFee(token: t, siteCode: s, period: _period, excludedApartmentIds: excluded.toList()),
      );
      if (!mounted || token != _previewToken) return;
      String? notice;
      if (staleFrom != null) {
        notice =
            'Veriler değişti, önizleme yenilendi. Yeni toplam ${formatMinor(preview.totalMinor)} (${preview.apartmentCount} daire); '
            'önceki toplam ${formatMinor(staleFrom.totalMinor)} (${staleFrom.apartmentCount} daire) idi. Kontrol edip yeniden onaylayın.';
      }
      setState(() {
        _preview = preview;
        _previewExcluded = excluded;
        _previewing = false;
        _stale = false;
        _staleFrom = null;
        _visible = FinanceLateFeeDialog.pageSize;
        _notice = notice;
        _explained.clear();
      });
      announcePolite(
        context,
        notice != null
            ? spokenMoneyText(notice)
            : 'Önizleme hazır: ${preview.apartmentCount} daire, toplam ${moneySemanticLabel(preview.totalMinor)}.',
      );
    } catch (e) {
      if (!mounted || token != _previewToken) return;
      final limited = _previewRetry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _previewing = false;
        _previewBusy = hasErrorCode(e, 'REPORT_BUSY');
        _previewError = limited
            ? RetryLock.messageFor(e)
            : financeMessageOf(
                e,
                _stale
                    ? 'Önizleme yenilenemedi. İnternet bağlantınızı kontrol edip önizlemeyi yenileyin.'
                    : 'Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  void _backToForm() {
    if (submitting || _previewing) return;
    ++_previewToken;
    setState(() {
      _preview = null;
      _stale = false;
      _staleFrom = null;
      _notice = null;
      _previewError = null;
      submitError = null;
    });
  }

  void _toggleExcluded(int apartmentId, bool value) {
    setState(() {
      if (value) {
        _excluded.add(apartmentId);
      } else {
        _excluded.remove(apartmentId);
      }
    });
  }

  // --- Onay ------------------------------------------------------------------------------------

  bool _canConfirm(LateFeePreview p) =>
      p.canPost && !_stale && !_excludedChanged && (p.apartmentCount > 0 || p.empty) && p.previewHash != null;

  String? _blockedReason(LateFeePreview p) {
    if (_previewing) return 'Önizleme yenileniyor.';
    if (_stale) return 'Önizleme eskidi. Önce "Önizlemeyi Yenile" düğmesine basın.';
    if (_excludedChanged) return 'Muaf listesi değişti. Önce "Önizlemeyi Yenile" düğmesine basın.';
    if (!p.canPost) return 'Bu ay için tazminat şu an yazılamaz (aşağıdaki nedene bakın).';
    if (p.apartmentCount == 0 && !p.empty) return 'Tazminat yazılacak daire yok.';
    if (p.previewHash == null) return 'Önizleme özeti okunamadı. Önizlemeyi yenileyin.';
    return null;
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null || !_canConfirm(preview) || writeBlocked || _previewing || _asking) return;
    // Para yükleyen işlem: ikinci, açık onay.
    setState(() => _asking = true);
    final bool proceed;
    try {
      final empty = preview.empty;
      final text = empty
          ? '${_period.label} için tazminat doğuran daire yok. Ay "tazminat yok" olarak kaydedilir: hiçbir daireye borç '
                'yazılmaz ve sıra bir sonraki aya geçer. Yalnızca SON çalıştırma iptal edilebilir.'
          : '${_period.label} için ${preview.apartmentCount} daireye toplam ${formatMinor(preview.totalMinor)} gecikme '
                'tazminatı borç olarak yazılacak. Yazıldıktan sonra yalnızca SON çalıştırma iptal edilebilir.';
      proceed = await confirmCrmAction(
        context,
        title: empty ? 'Tazminat yok - ayı kaydet' : 'Gecikme tazminatını yaz',
        message: text,
        semanticMessage: spokenMoneyText(text),
        confirmLabel: empty ? 'Ayı Kaydet' : 'Yaz',
        icon: empty ? Icons.event_available_rounded : Icons.gavel_rounded,
        tone: empty ? AppTone.warning : AppTone.danger,
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
    if (!proceed || !mounted) return;
    final hash = preview.previewHash!;
    final excluded = _previewExcluded.toList()..sort();
    final recordEmpty = preview.empty;
    await runWrite<LateFeePostResult>(
      signature: 'late|${_period.toApi()}|${excluded.join(',')}|$hash|${recordEmpty ? 'empty' : 'rows'}',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.postLateFee(
          token: t,
          siteCode: s,
          period: _period,
          excludedApartmentIds: excluded,
          expectedTotalMinor: preview.totalMinor,
          expectedApartmentCount: preview.apartmentCount,
          expectedHash: hash,
          idempotencyKey: key,
          recordEmpty: recordEmpty,
        ),
      ),
      onSuccess: (result) {
        final total = result.run.totalMinor;
        popIfCurrent(
          context,
          FinanceWriteOutcome(
            result.run.empty
                ? '${_period.label} için "tazminat yok" olarak kaydedildi. Hiçbir daireye borç yazılmadı.'
                : 'Gecikme tazminatı yazıldı: ${_period.label}, ${result.run.apartmentCount} daire, toplam ${formatMinor(total)}.',
          ),
        );
      },
      failure: 'Gecikme tazminatı yazılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        final stale = hasErrorCode(e, 'PREVIEW_STALE');
        final stateChanged = stale ||
            hasErrorCode(e, 'LATE_FEE_PERIOD_NOT_CLOSED') ||
            hasErrorCode(e, 'LATE_FEE_PERIOD_NOT_ENDED') ||
            hasErrorCode(e, 'LATE_FEE_PERIOD_NOT_NEXT') ||
            hasErrorCode(e, 'LATE_FEE_ALREADY_POSTED') ||
            hasErrorCode(e, 'LATE_FEE_DISABLED');
        if (!stateChanged) return false;
        // Durum değişti: eski önizlemeyle onay kapanır, önizleme yeniden alınır (neden bildirimde).
        _stale = true;
        _staleFrom = preview;
        if (!stale) {
          _notice = financeMessageOf(e, 'Veriler değişti. Önizlemeyi kontrol edin.');
        }
        widget.onRefreshNeeded?.call();
        unawaited(Future<void>.microtask(() => _requestPreview(staleFrom: stale ? preview : null)));
        return true;
      },
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  // --- Görünüm ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final busy = submitting || _previewing || _asking;
    final canConfirm = preview != null && _canConfirm(preview) && !busy && !retry.locked;
    final blocked = preview == null ? null : _blockedReason(preview);
    Widget confirmButton = ElevatedButton(
      key: const ValueKey<String>('finance_latefee_confirm'),
      style: filledToneStyle(context),
      onPressed: canConfirm ? _confirm : null,
      child: Text(
        submitting
            ? (_preview?.empty == true ? 'Kaydediliyor...' : 'Yazılıyor...')
            : (_preview?.empty == true ? 'Ayı Kaydet' : 'Onayla ve Yaz'),
      ),
    );
    if (preview != null && !canConfirm && blocked != null && !busy) {
      confirmButton = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        label: preview.empty ? 'Ayı Kaydet' : 'Onayla ve Yaz',
        hint: blocked,
        child: Tooltip(message: blocked, excludeFromSemantics: true, child: confirmButton),
      );
    }
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Gecikme Tazminatı',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.gavel_rounded,
        actions: preview == null
            ? [
                TextButton(
                  onPressed: _previewing ? null : requestClose,
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  key: const ValueKey<String>('finance_latefee_preview'),
                  onPressed: (_previewing || _previewRetry.locked) ? null : () => _requestPreview(),
                  child: Text(_previewing ? 'Hesaplanıyor...' : 'Önizle'),
                ),
              ]
            : [
                TextButton(
                  onPressed: busy ? null : requestClose,
                  child: const Text('Vazgeç'),
                ),
                TextButton(
                  key: const ValueKey<String>('finance_latefee_back'),
                  onPressed: busy ? null : _backToForm,
                  child: const Text('Geri'),
                ),
                confirmButton,
              ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (submitError != null) FinanceSubmitError(message: submitError!),
            if (_previewError != null)
              FinanceSubmitError(
                message: _previewError!,
                action: _previewBusy
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey<String>('finance_latefee_preview_retry'),
                          onPressed: (_previewing || _previewRetry.locked)
                              ? null
                              : () => _requestPreview(staleFrom: _stale ? _staleFrom : null),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Tekrar Dene'),
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        ),
                      )
                    : null,
              ),
            if (preview == null) _buildForm(context) else _buildPreview(context, preview, blocked),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final current = _currentPeriod;
    final min = current.addMonths(-36);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tazminat; kapatılmış ve bitmiş bir ay için, ödenmemiş borçların gecikme gününe göre sunucuda hesaplanır. '
          'Önce önizleme gösterilir; onaylamadan hiçbir şey kaydedilmez.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(icon: Icons.calendar_month_rounded, title: 'Hesaplanacak ay'),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey<String>('finance_latefee_prev'),
                    tooltip: 'Önceki ay',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: (_previewing || _period <= min) ? null : () => setState(() => _period = _period.previous),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _period.label,
                        key: const ValueKey<String>('finance_latefee_period'),
                        textAlign: TextAlign.center,
                        style: th.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('finance_latefee_next'),
                    tooltip: 'Sonraki ay',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: (_previewing || _period >= current) ? null : () => setState(() => _period = _period.next),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              Text(
                widget.initialPeriod == null
                    ? 'Aylar sırayla hesaplanır; sıradaki ayı seçin.'
                    : 'Sunucunun bildirdiği sıradaki ay: ${widget.initialPeriod!.label}.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Önizle düğmesi hiçbir şey kaydetmez.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, LateFeePreview preview, String? blocked) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final shown = preview.lines.length < _visible ? preview.lines.length : _visible;
    final remaining = preview.lines.length - shown;
    final summary = [
      'Önizleme',
      'Dönem: ${(preview.period ?? _period).label}',
      '${preview.apartmentCount} daire',
      'Toplam tazminat: ${moneySemanticLabel(preview.totalMinor)}',
    ].join('. ');
    final showBlockedLine = blocked != null && !_previewing && (_stale || _excludedChanged);
    final window = preview.window;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null) ...[
          InlineNotice(
            key: const ValueKey<String>('finance_latefee_notice'),
            tone: AppTone.warning,
            message: _notice!,
            semanticsLabel: spokenMoneyText(_notice!),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          key: const ValueKey<String>('finance_latefee_summary'),
          child: Semantics(
            container: true,
            label: summary,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(icon: Icons.fact_check_rounded, title: 'Önizleme'),
                  const SizedBox(height: AppSpace.sm),
                  Text('Dönem: ${(preview.period ?? _period).label}', style: th.bodyMedium),
                  if (window.from != null && window.to != null)
                    Text(
                      'Hesap aralığı: ${formatCrmDate(window.from)} - ${formatCrmDate(window.to)} (${window.days} gün)',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  Text(
                    'Oran: ${formatRateBp(preview.params.rateBp)} aylık • ${preview.params.method.label} • ek gün: ${preview.params.graceDays}',
                    key: const ValueKey<String>('finance_latefee_params'),
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(_countText(preview), key: const ValueKey<String>('finance_latefee_count'), style: th.bodyMedium),
                  Text(
                    formatMinor(preview.totalMinor),
                    key: const ValueKey<String>('finance_latefee_total'),
                    style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text('Toplam tazminat', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        if (_stale && !_previewing || _excludedChanged && !_previewing) ...[
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('finance_latefee_refresh'),
              label: 'Önizlemeyi Yenile',
              icon: Icons.refresh_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: (submitting || _previewRetry.locked) ? null : () => _requestPreview(staleFrom: _stale ? _staleFrom : null),
            ),
          ),
        ],
        if (_previewing) ...[
          const SizedBox(height: AppSpace.md),
          const DialogLoadingNote(text: 'Önizleme yenileniyor...'),
        ],
        if (showBlockedLine) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Onaylamak için: $blocked',
            key: const ValueKey<String>('finance_latefee_blocked_reason'),
            style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
        for (final code in preview.blockers) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: ValueKey<String>('finance_latefee_blocker_$code'),
            tone: AppTone.warning,
            message: lateFeeBlockerMessage(code, expectedPeriod: preview.expectedPeriod, period: preview.period ?? _period),
          ),
        ],
        if (preview.blockers.isEmpty && !preview.canPost) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_latefee_cannot_post'),
            tone: AppTone.warning,
            message: 'Bu ay için tazminat şu an hesaplanamaz.',
          ),
        ],
        if (preview.empty) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_latefee_empty'),
            tone: AppTone.info,
            message: preview.canPost
                ? 'Bu ay için tazminat doğuran daire yok. "Ayı Kaydet" ile ay "tazminat yok" olarak kaydedilir ve sıra '
                      'bir sonraki aya geçer; kaydetmezseniz sonraki aylar hesaplanamaz.'
                : 'Bu ay için tazminat doğuran daire yok.',
          ),
        ],
        if (preview.zeroAmountCount > 0) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_latefee_zero'),
            tone: AppTone.info,
            message: '${preview.zeroAmountCount} dairenin tazminatı sıfır kuruşa yuvarlandığı için yazılmayacak.',
          ),
        ],
        if (preview.inactiveSkipped.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          DialogPanel(
            key: const ValueKey<String>('finance_latefee_inactive'),
            tone: AppTone.info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DialogSectionTitle(
                  icon: Icons.pause_circle_rounded,
                  title: '${preview.inactiveSkipped.length} pasif daire hesaplanmadı',
                  tone: AppTone.info,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(preview.inactiveSkipped.map((e) => e.label).join(', '), style: th.bodySmall),
              ],
            ),
          ),
        ],
        if (preview.waived.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          DialogPanel(
            key: const ValueKey<String>('finance_latefee_waived'),
            tone: AppTone.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DialogSectionTitle(
                  icon: Icons.do_not_disturb_on_rounded,
                  // İP-1A: muafiyet daire başınadır; iki hesabı da gecikmiş daire listede iki öğedir (her hesap için), sayı dairedir.
                  title: '${preview.waived.map((w) => w.apartmentId).toSet().length} daire muaf tutuldu',
                  subtitle: 'Bu ayın tazminatı bu dairelere KALICI olarak yazılmaz.',
                  tone: AppTone.warning,
                ),
                const SizedBox(height: AppSpace.sm),
                for (final w in preview.waived)
                  FinanceSpokenText(
                    _waivedText(w),
                    key: ValueKey<String>('finance_latefee_waived_${w.apartmentId}_${w.accountParty?.apiValue ?? 'daire'}'),
                    style: th.bodySmall,
                  ),
              ],
            ),
          ),
        ],
        if (preview.lines.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Semantics(header: true, container: true, child: Text('Daire listesi', style: th.titleSmall)),
          Text(
            'Bir daireyi bu ay muaf tutarsanız tazminat o daireye yazılmaz (önizlemeyi yenilemeniz gerekir).',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.xs),
          for (var i = 0; i < shown; i++) _lineTile(context, preview, preview.lines[i]),
          if (remaining > 0)
            Align(
              child: PrimaryActionButton(
                key: const ValueKey<String>('finance_latefee_more'),
                label: 'Daha fazla göster ($remaining)',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                onPressed: () => setState(() => _visible += FinanceLateFeeDialog.pageSize),
              ),
            ),
        ],
      ],
    );
  }

  /// "12 daire" ya da (İP-1A, aynı dairenin iki hesabı satırdaysa) "11 daire, 12 hesap": sunucunun `apartment_count`
  /// değeri satır (hesap) sayısıdır.
  static String _countText(LateFeePreview preview) {
    final apartments = preview.lines.map((line) => line.apartmentId).toSet().length;
    final perAccount = preview.lines.any((line) => line.accountParty != null);
    if (perAccount && apartments != preview.apartmentCount) return '$apartments daire, ${preview.apartmentCount} hesap';
    return '${preview.apartmentCount} daire';
  }

  /// Muaf öğe satırı: "A Blok - 5 (Kiracı hesabı): 23,45 ₺ (yazılmayacak)" (hesap adı yalnız sunucu verdiyse; İP-1A).
  static String _waivedText(LateFeeWaivedItem w) {
    final label = w.accountParty == null ? w.label : '${w.label} (${w.accountParty!.label})';
    return w.computedMinor == null ? label : '$label: ${formatMinor(w.computedMinor!)} (yazılmayacak)';
  }

  Widget _lineTile(BuildContext context, LateFeePreview preview, LateFeeLine line) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final title = financeApartmentTitle(line.blockName, line.label);
    final expanded = _explained.contains(line.lineKey);
    final excluded = _excluded.contains(line.apartmentId);
    final payer = line.payerParty;
    final account = line.accountParty;
    final semantic = '$title. ${account == null ? '' : '${account.label}. '}${payer == null ? '' : '${payerPartyLabel(payer)}. '}Tazminat: ${moneySemanticLabel(line.amountMinor)}.';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DialogPanel(
        key: ValueKey<String>('finance_latefee_line_${line.lineKey}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: semantic,
              child: ExcludeSemantics(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (account != null) Text(account.label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                        if (payer != null) Text(payerPartyLabel(payer), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                      ],
                    ),
                    Text(
                      formatMinor(line.amountMinor),
                      style: th.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: excluded ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                TextButton.icon(
                  key: ValueKey<String>('finance_latefee_explain_${line.lineKey}'),
                  onPressed: () => setState(() {
                    if (expanded) {
                      _explained.remove(line.lineKey);
                    } else {
                      _explained.add(line.lineKey);
                    }
                  }),
                  icon: Icon(expanded ? Icons.expand_less_rounded : Icons.help_outline_rounded, size: 18),
                  label: Text(expanded ? 'Dökümü gizle' : 'Nasıl hesaplandı?'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
                TextButton.icon(
                  key: ValueKey<String>('finance_latefee_waive_${line.lineKey}'),
                  onPressed: (submitting || _previewing) ? null : () => _toggleExcluded(line.apartmentId, !excluded),
                  icon: Icon(excluded ? Icons.undo_rounded : Icons.do_not_disturb_on_rounded, size: 18),
                  label: Text(excluded ? 'Muafiyeti kaldır' : 'Bu ay muaf tut'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
            ),
            if (expanded) LateFeeBreakdownText(line: line, params: preview.params, window: preview.window),
          ],
        ),
      ),
    );
  }
}

/// "Nasıl hesaplandı" dökümü: sunucunun verdiği değerler (tutar-gün toplamı, en yüksek gecikmiş tutar, dilimler) ve
/// ayar özeti. İstemci tutarı YENİDEN HESAPLAMAZ.
class LateFeeBreakdownText extends StatelessWidget {
  const LateFeeBreakdownText({super.key, required this.line, required this.params, required this.window});

  final LateFeeLine line;
  final LateFeeParams params;
  final LateFeeWindow window;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final lines = <String>[
      if (line.baseDayMinor != null)
        'Ay içinde gecikmiş tutarların gün toplamı: ${formatMinor(line.baseDayMinor!)} (tutar x gün).',
      if (line.peakOverdueMinor != null) 'Ay içindeki en yüksek gecikmiş tutar: ${formatMinor(line.peakOverdueMinor!)}.',
      'Oran: ${formatRateBp(params.rateBp)} aylık; ${params.method.label}; vadeye ek ${params.graceDays} gün.',
      if (window.days > 0) 'Hesap ayı ${window.days} gündür.',
      for (final s in line.breakdown)
        '${formatCrmDate(s.from)} - ${formatCrmDate(s.to)}: gecikmiş ${formatMinor(s.overdueMinor)}',
      'Tazminat bu değerlerden sunucuda hesaplanır: ${formatMinor(line.amountMinor)}. Tazminat kalemleri sonraki ayların hesabına katılmaz.',
    ];
    final label = spokenMoneyText(lines.join(' '));
    return Container(
      key: ValueKey<String>('finance_latefee_breakdown_${line.lineKey}'),
      margin: const EdgeInsets.only(top: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Semantics(
        container: true,
        label: label,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final text in lines) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(text, style: th.bodySmall))],
          ),
        ),
      ),
    );
  }
}
