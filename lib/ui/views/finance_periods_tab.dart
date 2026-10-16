import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart' show CrmFormError;
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Dönemler" sekmesi (Platform Faz 4a): açık ay, kapalı aylar; "Ayı Kapat" (yazma yetkisi olanda) ve
/// "Yeniden Aç" (yalnız süper kullanıcı, yalnız EN SON kapatılan ay).
///
/// Kuralların kendisi sunucudadır. Aylar SIRAYLA kapanır ve bir ay kapatılınca ondan ÖNCEKİ TÜM aylar da
/// değiştirilemez olur; bu yüzden kapatılacak ay kullanıcıya SEÇTİRİLİR: sunucunun bildirdiği `closable`
/// listesinden (varsayılan "bir önceki ay", yoksa listenin ilki) ve onay penceresi "X kapatılınca X ve
/// öncesindeki tüm aylar değiştirilemez olur" der. `closable` boşsa "şu an kapatılabilecek dönem yok"
/// açıklanır; alan hiç gelmediyse (eski sunucu) eski davranışla açık ay kapatılır. Kurul üyesi salt okur.
///
/// Hata asla "kapalı ay yok" demez; eski yanıt yenisini ezmez (jeton). Eylem hatası eylemin yapıldığı
/// kartta görünür ve duyurulur. Liste yenilenemediyse (eski veri) kapat / yeniden aç düğmeleri pasiftir.
class FinancePeriodsTab extends StatefulWidget {
  const FinancePeriodsTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
    this.canReopen = false,
    this.now,
  });

  final PeopleScope scope;

  /// Bir ay kapatılıp açılınca çağrılır (özet ve öteki sekmeler tazelenir).
  final VoidCallback onDataChanged;

  /// Yalnız süper kullanıcı kapalı ayı yeniden açabilir.
  final bool canReopen;

  /// Şimdiki zaman (varsayılan kapatma ayı "bir önceki ay" için; testler içindir).
  final DateTime Function()? now;

  @override
  State<FinancePeriodsTab> createState() => FinancePeriodsTabState();
}

class FinancePeriodsTabState extends State<FinancePeriodsTab> {
  static const String _closeTarget = 'close';

  FinancePeriods? _periods;
  bool _loading = false;
  String? _error;

  // Son eylemin hatası, eylemin yapıldığı kartta gösterilir: [_actionTarget] 'close' ya da 'reopen_<ay>'.
  String? _actionError;
  String? _actionTarget;
  bool _busy = false;
  FinancePeriod? _busyReopen;
  FinancePeriod? _choice;
  int _token = 0;
  final RetryLock _retry = RetryLock();

  bool get _canWrite => widget.scope.canWrite;

  /// Liste yenilenemedi ama eski veri ekranda: eylemler pasif.
  bool get _stale => _error != null && _periods != null;

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
        _error = financeMessageOf(
          e,
          'Dönemler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Kapatılacak ay: `closable` varsa seçilen (listede kalıyorsa), yoksa "bir önceki ay", o da yoksa listenin
  /// ilki; `closable` boşsa null; alan hiç yoksa (eski sunucu) açık ay.
  FinancePeriod? _closeChoice(FinancePeriods periods) {
    final list = periods.closable;
    if (list == null) return periods.openPeriod;
    if (list.isEmpty) return null;
    final chosen = _choice;
    if (chosen != null && list.contains(chosen)) return chosen;
    final current = FinancePeriod.of(istanbulNow(widget.now?.call()));
    return list.contains(current.previous) ? current.previous : list.first;
  }

  Future<void> _close(FinancePeriod period) async {
    if (_busy || _retry.locked || _stale) return;
    final label = period.label;
    final confirmed = await confirmCrmAction(
      context,
      title: '$label ayını kapat',
      message:
          '$label kapatılınca $label ve öncesindeki tüm aylar değiştirilemez olur. Bu aylara yeni borç, '
          'tahsilat ya da ters kayıt eklenemez; düzeltmeler açık ayda ters kayıtla yapılır. Kapalı ayı '
          'yalnızca süper kullanıcı yeniden açabilir.',
      confirmLabel: 'Ayı Kapat',
      icon: Icons.lock_rounded,
    );
    if (!confirmed || !mounted) return;
    await _run(
      _closeTarget,
      () => widget.scope.authService.closeFinancePeriod(widget.scope.siteCode, period),
      success: '$label kapatıldı.',
      failure: 'Ay kapatılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  Future<void> _reopen(FinancePeriod period) async {
    if (_busy || _retry.locked || _stale) return;
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
      'reopen_${period.toApi()}',
      () => widget.scope.authService.reopenFinancePeriod(widget.scope.siteCode, period),
      success: '${period.label} yeniden açıldı.',
      failure: 'Ay yeniden açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      reopening: period,
    );
  }

  Future<void> _run(
    String target,
    Future<void> Function() action, {
    required String success,
    required String failure,
    FinancePeriod? reopening,
  }) async {
    setState(() {
      _busy = true;
      _busyReopen = reopening;
      _actionError = null;
      _actionTarget = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyReopen = null;
        _choice = null;
      });
      widget.onDataChanged();
      showFinanceSnack(context, success);
      unawaited(reload());
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _busy = false;
        _busyReopen = null;
        _actionTarget = target;
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
        body,
      ],
    );
  }

  Widget _buildLoaded(BuildContext context, FinancePeriods periods) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final open = periods.openPeriod;
    final newest = periods.items.isEmpty ? null : periods.items.first;
    final choice = _closeChoice(periods);
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
                container: true,
                child: Text(open?.label ?? 'Açık dönem bilinmiyor', style: th.titleMedium),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Açık dönemde borç, tahsilat ve düzeltme kaydedilir. Ay kapatılınca o aya kayıt eklenemez.',
                style: th.bodyMedium?.copyWith(color: p.textSecondary),
              ),
              if (_canWrite) ..._buildCloseControls(context, periods, choice),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(header: true, container: true, child: Text('Kapalı aylar', style: th.titleMedium)),
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

  /// Açık ay kartındaki kapatma denetimleri: ay seçici (varsa), açıklama, hata ve "Ayı Kapat" düğmesi.
  List<Widget> _buildCloseControls(BuildContext context, FinancePeriods periods, FinancePeriod? choice) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final list = periods.closable;
    final errorHere = _actionError != null && _actionTarget == _closeTarget;
    return [
      if (list != null && list.isEmpty) ...[
        const SizedBox(height: AppSpace.md),
        const InlineNotice(
          key: ValueKey<String>('finance_nothing_closable'),
          tone: AppTone.info,
          message:
              'Şu an kapatılabilecek dönem yok. Aylar sırayla kapatılır; gelecek ay kapatılamaz.',
        ),
      ],
      if (list != null && list.isNotEmpty && choice != null) ...[
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<FinancePeriod>(
          key: ValueKey<String>('finance_close_choice_${choice.toApi()}_${list.length}'),
          isExpanded: true,
          initialValue: choice,
          dropdownColor: p.surface,
          style: th.bodyMedium?.copyWith(color: p.text),
          decoration: const InputDecoration(
            labelText: 'Kapatılacak ay',
            prefixIcon: Icon(Icons.calendar_month_rounded),
          ),
          items: [
            for (final period in list)
              DropdownMenuItem<FinancePeriod>(value: period, child: Text(period.label)),
          ],
          onChanged: (_busy || _stale)
              ? null
              : (value) {
                  if (value != null) setState(() => _choice = value);
                },
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          '${choice.label} kapatılınca ${choice.label} ve öncesindeki tüm aylar değiştirilemez olur.',
          key: const ValueKey<String>('finance_close_hint'),
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
      if (errorHere) ...[
        const SizedBox(height: AppSpace.md),
        CrmFormError(
          key: const ValueKey<String>('finance_close_error'),
          message: _actionError!,
          announce: true,
        ),
      ],
      if (choice != null) ...[
        const SizedBox(height: AppSpace.md),
        PrimaryActionButton(
          key: const ValueKey<String>('finance_close_period'),
          label: 'Ayı Kapat',
          icon: Icons.lock_rounded,
          variant: AppButtonVariant.tonal,
          loading: _busy && _busyReopen == null,
          onPressed: (_busy || _retry.locked || _stale) ? null : () => _close(choice),
        ),
      ],
    ];
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
    final target = 'reopen_${item.period.toApi()}';
    final reopening = _busyReopen == item.period;
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
          if (_actionError != null && _actionTarget == target) ...[
            const SizedBox(height: AppSpace.sm),
            CrmFormError(
              key: ValueKey<String>('finance_reopen_error_${item.period.toApi()}'),
              message: _actionError!,
              announce: true,
            ),
          ],
          if (canReopen) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('finance_reopen_${item.period.toApi()}'),
                onPressed: (_busy || _retry.locked || _stale) ? null : () => _reopen(item.period),
                icon: reopening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(reopening ? 'Yeniden açılıyor...' : 'Yeniden Aç'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
