import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Eşlenmemiş tahsilatları hesaplara toplu eşleme (Platform Faz 4b, Ö4). Hesap tanımlanmadan önce kaydedilmiş
/// tahsilatlar yönteme göre (nakit / havale / çek) seçilen hesaba işlenir.
///
/// Akış: yöntem -> hesap eşlemesi -> ÖNİZLEME (adet, toplam, yönteme göre kırılım; HİÇBİR ŞEY YAZMAZ) -> onay.
/// Önizleme ile onay arasında veri değişirse sunucu 409 `PREVIEW_STALE` döner: önizleme OTOMATİK yenilenir, eski ve yeni
/// toplam yazılır, yenileme sürerken / başarısızken eski önizlemeyle onay KAPALIDIR. Kapalı aydaki tahsilatlar
/// eşlenemez (sunucu atlar ve ay kapatma o kısım için engellenir).
class FinanceAssignDialog extends StatefulWidget {
  const FinanceAssignDialog({super.key, required this.scope, required this.accounts, this.onRefreshNeeded});

  final PeopleScope scope;

  /// Aktif hesaplar.
  final List<CashAccount> accounts;
  final VoidCallback? onRefreshNeeded;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    required List<CashAccount> accounts,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceAssignDialog(scope: scope, accounts: accounts, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceAssignDialog> createState() => _FinanceAssignDialogState();
}

class _FinanceAssignDialogState extends State<FinanceAssignDialog> with FinanceWriteMixin {
  @override
  String get keyPrefix => 'assign';

  @override
  Object? get keyOwner => widget.scope.authService;

  late final Map<PaymentMethod, int?> _map = <PaymentMethod, int?>{
    for (final method in PaymentMethod.values) method: _suggest(method),
  };
  AssignPreview? _preview;
  Map<String, int>? _frozenMap;
  bool _previewing = false;
  bool _stale = false;
  AssignPreview? _staleFrom;
  String? _notice;
  String? _previewError;
  int _previewToken = 0;
  final RetryLock _previewRetry = RetryLock();

  int? _suggest(PaymentMethod method) {
    final wanted = method == PaymentMethod.cash ? CashAccountKind.cash : CashAccountKind.bank;
    for (final a in widget.accounts) {
      if (a.kind == wanted) return a.id;
    }
    return widget.accounts.isEmpty ? null : widget.accounts.first.id;
  }

  @override
  void dispose() {
    ++_previewToken;
    _previewRetry.dispose();
    disposeWrite();
    super.dispose();
  }

  Map<String, int> _currentMap() => <String, int>{
    for (final e in _map.entries)
      if (e.value != null) e.key.apiValue: e.value!,
  };

  Future<void> _requestPreview({AssignPreview? staleFrom}) async {
    if (_previewing || submitting || _previewRetry.locked) return;
    final map = _frozenMap ?? _currentMap();
    if (map.length != PaymentMethod.values.length) {
      setState(() => _previewError = 'Her yöntem için bir hesap seçin.');
      return;
    }
    final token = ++_previewToken;
    setState(() {
      _previewing = true;
      _previewError = null;
      _notice = null;
    });
    try {
      final preview = await widget.scope.f4Call(
        (api, t, s) => api.previewAssignPayments(token: t, siteCode: s, accountByMethod: map),
      );
      if (!mounted || token != _previewToken) return;
      String? notice;
      if (staleFrom != null) {
        notice =
            'Veriler değişti, önizleme yenilendi. Yeni toplam ${formatMinor(preview.totalMinor)} (${preview.count} tahsilat); '
            'önceki toplam ${formatMinor(staleFrom.totalMinor)} (${staleFrom.count} tahsilat) idi. Kontrol edip yeniden onaylayın.';
      }
      setState(() {
        _preview = preview;
        _frozenMap = map;
        _previewing = false;
        _stale = false;
        _staleFrom = null;
        _notice = notice;
      });
      announcePolite(
        context,
        notice != null
            ? spokenMoneyText(notice)
            : 'Önizleme hazır: ${preview.count} tahsilat, toplam ${moneySemanticLabel(preview.totalMinor)}.',
      );
    } catch (e) {
      if (!mounted || token != _previewToken) return;
      final limited = _previewRetry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _previewing = false;
        _previewError = limited
            ? RetryLock.messageFor(e)
            : financeMessageOf(e, 'Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  void _back() {
    if (submitting) return;
    ++_previewToken;
    setState(() {
      _preview = null;
      _frozenMap = null;
      _previewing = false;
      _stale = false;
      _staleFrom = null;
      _notice = null;
      _previewError = null;
      submitError = null;
    });
  }

  Future<void> _confirm() async {
    final preview = _preview;
    final map = _frozenMap;
    if (preview == null || map == null || _stale || _previewing || preview.count == 0) return;
    final hash = preview.previewHash;
    if (hash == null) {
      setState(() => submitError = 'Önizleme özeti okunamadı. Önizlemeyi yenileyin.');
      return;
    }
    await runWrite<AssignResult>(
      signature: 'assign|${map.entries.map((e) => '${e.key}:${e.value}').join(',')}|$hash',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.commitAssignPayments(
          token: t,
          siteCode: s,
          accountByMethod: map,
          expectedCount: preview.count,
          expectedTotalMinor: preview.totalMinor,
          expectedHash: hash,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (result) {
        final skipped = result.skippedClosedCount > 0
            ? ' ${result.skippedClosedCount} tahsilat kapalı ayda olduğu için eşlenmedi.'
            : '';
        popIfCurrent(
          context,
          FinanceWriteOutcome(
            '${result.count} tahsilat hesaplara eşlendi (toplam ${formatMinor(result.totalMinor)}).$skipped',
          ),
        );
      },
      failure: 'Eşleme yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        if (!hasErrorCode(e, 'PREVIEW_STALE')) return false;
        // Önizleme eskidi: eski önizlemeyle onay kapanır, önizleme yeniden alınır (eski toplam bildirimde yazılır).
        _stale = true;
        _staleFrom = preview;
        unawaited(Future<void>.microtask(() => _requestPreview(staleFrom: preview)));
        return true;
      },
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  String _methodText(String method) {
    final parsed = PaymentMethod.tryParse(method);
    return parsed?.label ?? method;
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final preview = _preview;
    final canConfirm = preview != null && !_stale && !_previewing && !submitting && !retry.locked && preview.count > 0;
    // Pasif "Onayla ve Eşle" düğmesinin NEDENİ ekran okuyucuya da söylenir (R14).
    final String? confirmWhyDisabled = (preview == null || submitting || canConfirm)
        ? null
        : _previewing
        ? 'Önizleme yenileniyor.'
        : _stale
        ? 'Veriler değişti. Önce önizlemeyi yenileyin.'
        : retry.locked
        ? 'Çok sık deneme yapıldı. Birkaç saniye bekleyin.'
        : 'Eşlenecek tahsilat yok.';
    return PopScope(
      canPop: !submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Tahsilatları Hesaplara Eşle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.account_tree_rounded,
        actions: preview == null
            ? [
                TextButton(
                  onPressed: _previewing ? null : () => popIfCurrent(context),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  key: const ValueKey<String>('finance_assign_preview'),
                  onPressed: (_previewing || _previewRetry.locked) ? null : () => _requestPreview(),
                  child: Text(_previewing ? 'Hesaplanıyor...' : 'Önizle'),
                ),
              ]
            : [
                TextButton(
                  onPressed: (submitting || _previewing) ? null : () => popIfCurrent(context),
                  child: const Text('Vazgeç'),
                ),
                TextButton(
                  key: const ValueKey<String>('finance_assign_back'),
                  onPressed: (submitting || _previewing) ? null : _back,
                  child: const Text('Geri'),
                ),
                MergeSemantics(
                  child: Semantics(
                    hint: confirmWhyDisabled,
                    child: ElevatedButton(
                      key: const ValueKey<String>('finance_assign_confirm'),
                      style: filledToneStyle(context),
                      onPressed: canConfirm ? _confirm : null,
                      child: Text(submitting ? 'Eşleniyor...' : 'Onayla ve Eşle'),
                    ),
                  ),
                ),
              ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (submitError != null) FinanceSubmitError(message: submitError!),
            if (_previewError != null) FinanceSubmitError(message: _previewError!),
            if (preview == null) ...[
              Text(
                'Hesap tanımlanmadan önce kaydedilmiş tahsilatlar, ödeme yöntemine göre seçtiğiniz hesaba işlenir. '
                'Önce önizleme gösterilir; onaylamadan hiçbir şey kaydedilmez.',
                style: th.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              for (final method in PaymentMethod.values) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('finance_assign_${method.apiValue}'),
                  isExpanded: true,
                  initialValue: _map[method],
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: InputDecoration(
                    labelText: '${method.label} tahsilatlar',
                    prefixIcon: const Icon(Icons.account_balance_rounded),
                  ),
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem<int>(
                        value: a.id,
                        child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _previewing ? null : (v) => setState(() => _map[method] = v),
                ),
                const SizedBox(height: AppSpace.md),
              ],
            ] else ...[
              if (_notice != null) ...[
                InlineNotice(
                  key: const ValueKey<String>('finance_assign_notice'),
                  tone: AppTone.warning,
                  message: _notice!,
                  semanticsLabel: spokenMoneyText(_notice!),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              DialogPanel(
                key: const ValueKey<String>('finance_assign_summary'),
                child: Semantics(
                  container: true,
                  label: 'Önizleme. ${preview.count} tahsilat. Toplam: ${moneySemanticLabel(preview.totalMinor)}.',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DialogSectionTitle(icon: Icons.fact_check_rounded, title: 'Önizleme'),
                        const SizedBox(height: AppSpace.sm),
                        Text('${preview.count} tahsilat', key: const ValueKey<String>('finance_assign_count'), style: th.bodyMedium),
                        Text(
                          formatMinor(preview.totalMinor),
                          key: const ValueKey<String>('finance_assign_total'),
                          style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        for (final row in preview.byMethod)
                          Text(
                            '${_methodText(row.method)}: ${row.count} tahsilat, ${formatMinor(row.totalMinor)}',
                            style: th.bodySmall?.copyWith(color: p.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (preview.skippedTotal > 0) ...[
                const SizedBox(height: AppSpace.md),
                InlineNotice(
                  key: const ValueKey<String>('finance_assign_skipped'),
                  tone: AppTone.info,
                  message: [
                    'Şu tahsilatlar bu işlemle eşlenmeyecek:',
                    if (preview.skippedClosedPeriod > 0) '${preview.skippedClosedPeriod} tahsilat kapalı ayda (kapalı aya kayıt eklenemez).',
                    if (preview.skippedBeforeOpening > 0) '${preview.skippedBeforeOpening} tahsilat seçilen hesabın açılış tarihinden önce.',
                    if (preview.skippedNoAccount > 0) '${preview.skippedNoAccount} tahsilatın yöntemi için hesap seçilmedi.',
                  ].join(' '),
                ),
              ],
              if (preview.count == 0) ...[
                const SizedBox(height: AppSpace.md),
                const InlineNotice(
                  key: ValueKey<String>('finance_assign_empty'),
                  tone: AppTone.info,
                  message: 'Eşlenecek tahsilat yok.',
                ),
              ],
              if (_stale && !_previewing) ...[
                const SizedBox(height: AppSpace.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PrimaryActionButton(
                    key: const ValueKey<String>('finance_assign_refresh'),
                    label: 'Önizlemeyi Yenile',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: () => _requestPreview(staleFrom: _staleFrom),
                  ),
                ),
              ],
              if (_previewing) ...[
                const SizedBox(height: AppSpace.md),
                const DialogLoadingNote(text: 'Önizleme yenileniyor...'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
