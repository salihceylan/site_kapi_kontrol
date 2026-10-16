import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Dönemler" sekmesi (Platform Faz 4a): açık ay, kapalı aylar; "Ayı Kapat" (yazma yetkisi olanda) ve
/// "Yeniden Aç" (yalnız süper kullanıcı, yalnız EN SON kapatılan ay).
///
/// Kuralların kendisi sunucudadır: aylar SIRAYLA kapanır, gelecek ay kapatılamaz (409 `PERIOD_NOT_CLOSABLE`).
/// Kapatılacak ay sunucunun bildirdiği açık aydır (uygulama kendi başına ay hesaplamaz). Kurul üyesi salt okur.
/// Hata asla "kapalı ay yok" demez; eski yanıt yenisini ezmez (jeton).
class FinancePeriodsTab extends StatefulWidget {
  const FinancePeriodsTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
    this.canReopen = false,
  });

  final PeopleScope scope;

  /// Bir ay kapatılıp açılınca çağrılır (özet ve öteki sekmeler tazelenir).
  final VoidCallback onDataChanged;

  /// Yalnız süper kullanıcı kapalı ayı yeniden açabilir.
  final bool canReopen;

  @override
  State<FinancePeriodsTab> createState() => FinancePeriodsTabState();
}

class FinancePeriodsTabState extends State<FinancePeriodsTab> {
  FinancePeriods? _periods;
  bool _loading = false;
  String? _error;
  String? _actionError;
  bool _busy = false;
  int _token = 0;
  final RetryLock _retry = RetryLock();

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final periods = await widget.scope.authService.getFinancePeriods(widget.scope.siteCode);
      if (!mounted || token != _token) return;
      setState(() {
        _periods = periods;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Dönemler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _close(FinancePeriod period) async {
    if (_busy || _retry.locked) return;
    final confirmed = await confirmCrmAction(
      context,
      title: '${period.label} ayını kapat',
      message:
          'Kapatılan aya yeni borç, tahsilat ya da ters kayıt eklenemez; düzeltmeler açık ayda ters kayıtla '
          'yapılır. Aylar sırayla kapanır. Kapalı ayı yalnızca sistem yöneticisi yeniden açabilir.',
      confirmLabel: 'Ayı Kapat',
      icon: Icons.lock_rounded,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => widget.scope.authService.closeFinancePeriod(widget.scope.siteCode, period),
      success: '${period.label} kapatıldı.',
      failure: 'Ay kapatılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  Future<void> _reopen(FinancePeriod period) async {
    if (_busy || _retry.locked) return;
    final confirmed = await confirmCrmAction(
      context,
      title: '${period.label} ayını yeniden aç',
      message:
          'Bu aya yeniden kayıt eklenebilir. Yalnızca en son kapatılan ay açılabilir. Devam edilsin mi?',
      confirmLabel: 'Yeniden Aç',
      icon: Icons.lock_open_rounded,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => widget.scope.authService.reopenFinancePeriod(widget.scope.siteCode, period),
      success: '${period.label} yeniden açıldı.',
      failure: 'Ay yeniden açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    required String failure,
  }) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onDataChanged();
      AppSnack.show(context, success, kind: AppSnackKind.success);
      unawaited(reload());
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _busy = false;
        _actionError = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(e, failure, hint: kFinanceUncertainStateHint);
      });
      // Durum değişmiş olabilir (başka yönetici kapattı ya da sonuç belirsiz): liste yeniden okunur.
      unawaited(reload());
    }
  }

  @override
  Widget build(BuildContext context) {
    final periods = _periods;
    final Widget body;
    if (periods == null) {
      body = _loading || _error == null
          ? const ListSkeleton(rows: 2)
          : InlineNotice(message: _error!, onRetry: reload);
    } else {
      body = _buildLoaded(context, periods);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Dönemler',
          trailing: IconButton(
            onPressed: _loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_actionError != null) ...[
          InlineNotice(message: _actionError!),
          const SizedBox(height: AppSpace.md),
        ],
        body,
      ],
    );
  }

  Widget _buildLoaded(BuildContext context, FinancePeriods periods) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final open = periods.openPeriod;
    final newest = periods.items.isEmpty ? null : periods.items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(message: _error!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          key: const ValueKey<String>('finance_open_period'),
          padding: listCardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: const [
                  DialogMetaPill('Açık', tone: AppTone.success, icon: Icons.lock_open_rounded),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Semantics(
                header: true,
                child: Text(open?.label ?? 'Açık dönem bilinmiyor', style: th.titleMedium),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Açık dönemde borç, tahsilat ve düzeltme kaydedilir. Ay kapatılınca o aya kayıt eklenemez.',
                style: th.bodyMedium?.copyWith(color: p.textSecondary),
              ),
              if (_canWrite && open != null) ...[
                const SizedBox(height: AppSpace.md),
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_close_period'),
                  label: 'Ayı Kapat',
                  icon: Icons.lock_rounded,
                  variant: AppButtonVariant.tonal,
                  loading: _busy,
                  onPressed: (_busy || _retry.locked) ? null : () => _close(open),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(header: true, child: Text('Kapalı aylar', style: th.titleMedium)),
        const SizedBox(height: AppSpace.sm),
        if (periods.items.isEmpty)
          const EmptyCard(
            icon: Icons.lock_open_rounded,
            title: 'Henüz kapatılmış ay yok.',
          )
        else
          for (final item in periods.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: _closedCard(context, item, isNewest: identical(item, newest)),
            ),
      ],
    );
  }

  Widget _closedCard(BuildContext context, ClosedPeriod item, {required bool isNewest}) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final by = item.closedByName;
    final canReopen = widget.canReopen && isNewest;
    final detail = <String>[
      if (item.closedAt != null) 'Kapatıldı: ${formatIstanbulDateTime(item.closedAt)}',
      if (by != null) 'Kapatan: $by',
    ];
    return AppCard(
      key: ValueKey<String>('finance_closed_${item.period.toApi()}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: 'Kapalı ay: ${item.period.label}. ${detail.join('. ')}',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DialogMetaPill('Kapalı', tone: AppTone.neutral, icon: Icons.lock_rounded),
                  const SizedBox(height: AppSpace.sm),
                  Text(item.period.label, style: th.titleMedium),
                  for (final line in detail)
                    Text(line, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
          if (canReopen) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('finance_reopen_${item.period.toApi()}'),
                onPressed: (_busy || _retry.locked) ? null : () => _reopen(item.period),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Yeniden Aç'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
