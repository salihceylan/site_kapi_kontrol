import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart' show showApartmentPicker;
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Hatırlatma geçmişi (Platform Faz 4b, Ö6): çalıştırmalar ve alıcı SAYILARI (gönderilen, bekleyen, başarısız, adresi yok,
/// tercih nedeniyle atlanan, tekrar, sınıra takılan, güncel olmadığı için gönderilmeyen, iptal). Alıcı adı / adresi YOKTUR
/// (kurul da okuyabilir). Yazma yetkisi olan, bekleyen iletisi olan çalıştırmayı iptal edebilir (yoldaki iletiler sonuçlanır).
class FinanceReminderRunsDialog extends StatefulWidget {
  const FinanceReminderRunsDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceReminderRunsDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceReminderRunsDialog> createState() => _FinanceReminderRunsDialogState();
}

class _FinanceReminderRunsDialogState extends State<FinanceReminderRunsDialog> {
  final IdempotencyKeys _keys = IdempotencyKeys('remind-c');
  final RetryLock _retry = RetryLock();
  bool _busy = false;
  int? _busyRun;
  String? _actionError;

  late final PagedLoader<ReminderRun> _loader = PagedLoader<ReminderRun>(
    fetch: (offset, limit) async {
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listReminderRuns(token: t, siteCode: s, limit: limit, offset: offset),
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (r) => r.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    pageSize: 20,
    errorFallback: 'Hatırlatma geçmişi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _retry.dispose();
    _loader.dispose();
    super.dispose();
  }

  Future<void> _cancel(ReminderRun run) async {
    if (_busy || _retry.locked) return;
    final ok = await confirmCrmAction(
      context,
      title: 'Hatırlatmayı iptal et',
      message:
          'Henüz gönderilmemiş (bekleyen) iletiler iptal edilir. Yolda olan iletiler sonuçlanır; zaten gönderilenler geri '
          'alınamaz.',
      confirmLabel: 'Bekleyenleri İptal Et',
      icon: Icons.cancel_schedule_send_rounded,
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    final signature = 'cancel|${run.id}';
    final key = _keys.keyFor(signature);
    setState(() {
      _busy = true;
      _busyRun = run.id;
      _actionError = null;
    });
    try {
      await widget.scope.f4Call(
        (api, t, s) => api.cancelReminderRun(token: t, siteCode: s, runId: run.id, idempotencyKey: key),
      );
      _keys.clear(signature);
      if (!mounted) return;
      widget.onChanged?.call();
      showFinanceSnack(context, 'Bekleyen hatırlatmalar iptal edildi.');
      setState(() {
        _busy = false;
        _busyRun = null;
      });
      unawaited(_loader.reload());
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      if (hasErrorCode(e, 'IDEMPOTENCY_CONFLICT') || hasErrorCode(e, 'REMINDER_RUN_NOT_CANCELLABLE')) {
        _keys.clear(signature);
        unawaited(_loader.reload());
      }
      setState(() {
        _busy = false;
        _busyRun = null;
        _actionError = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(e, 'Hatırlatma iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Hatırlatma Geçmişi',
      icon: Icons.history_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_reminder_runs_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_actionError != null) FinanceSubmitError(key: const ValueKey<String>('finance_reminder_runs_error'), message: _actionError!),
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, container: true, child: Text('Çalıştırmalar', style: th.titleMedium)),
              ),
              IconButton(
                tooltip: 'Yenile',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _loader.loading ? null : () => unawaited(_loader.reload()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          CrmListBody<ReminderRun>(
            loader: _loader,
            emptyIcon: Icons.mark_email_read_rounded,
            emptyTitle: 'Henüz hatırlatma gönderilmedi.',
            skeletonRows: 2,
            itemBuilder: (context, run) => _RunTile(
              run: run,
              busy: _busy,
              busyThis: _busyRun == run.id,
              onCancel: widget.scope.canWrite && run.canCancel ? () => _cancel(run) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, required this.busy, required this.busyThis, this.onCancel});

  final ReminderRun run;
  final bool busy;
  final bool busyThis;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final r = run;
    final s = r.stats;
    final lines = <(String, int)>[
      ('Gönderilen', s.sent),
      ('Bekleyen', s.pending),
      ('Başarısız', s.failed),
      ('Adresi olmayan', s.noAddress),
      ('Tercih nedeniyle atlanan', s.skippedPref),
      ('Tekrar adres', s.duplicate),
      ('Sınıra takılan', s.capped),
      ('Güncel olmadığı için gönderilmeyen', s.resolved),
      ('İptal edilen', s.cancelled),
    ].where((e) => e.$2 > 0).toList();
    final semantic = StringBuffer('Hatırlatma: ${formatIstanbulDateTime(r.createdAt)}. ${r.tone.label}. ');
    semantic.write('${r.apartmentCount} daire, ${r.personCount} kişi.');
    for (final l in lines) {
      semantic.write(' ${l.$1}: ${l.$2}.');
    }
    return DialogPanel(
      key: ValueKey<String>('reminder_run_${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      DialogMetaPill(
                        r.isCancelled ? 'İptal edildi' : (s.pending > 0 ? 'Gönderiliyor' : 'Tamamlandı'),
                        tone: r.isCancelled ? AppTone.neutral : (s.pending > 0 ? AppTone.info : AppTone.success),
                        icon: r.isCancelled
                            ? Icons.block_rounded
                            : (s.pending > 0 ? Icons.schedule_send_rounded : Icons.check_circle_rounded),
                      ),
                      DialogMetaPill(r.tone.label, icon: Icons.mail_rounded),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(formatIstanbulDateTime(r.createdAt), style: th.titleSmall),
                  Text('${r.apartmentCount} daire • ${r.personCount} kişi', style: th.bodyMedium),
                  for (final l in lines)
                    Text('${l.$1}: ${l.$2}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('reminder_run_cancel_${r.id}'),
                onPressed: busy ? null : onCancel,
                icon: busyThis
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_schedule_send_rounded, size: 18),
                label: Text(busyThis ? 'İptal ediliyor...' : 'Bekleyenleri iptal et'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTone.danger.ink(p)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Muaf daireler (anlaşmazlık / dava altındaki daireler; Ö6): listeyi gösterir, daire ekler (neden ≤ 100) ve kaldırır.
/// Muaf daireye hatırlatma GİTMEZ. Yalnız yazma yetkisi olan açar.
class FinanceReminderExclusionsDialog extends StatefulWidget {
  const FinanceReminderExclusionsDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static const int maxReasonLength = 100;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceReminderExclusionsDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceReminderExclusionsDialog> createState() => _FinanceReminderExclusionsDialogState();
}

class _FinanceReminderExclusionsDialogState extends State<FinanceReminderExclusionsDialog> {
  List<ReminderExclusion>? _items;
  bool _loading = true;
  String? _error;
  int _token = 0;
  bool _busy = false;
  String? _actionError;
  final TextEditingController _reason = TextEditingController();
  ({int id, String label})? _picked;
  String? _reasonError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.scope.f4Call((api, t, s) => api.listReminderExclusions(token: t, siteCode: s));
      if (!mounted || token != _token) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _items = null;
        _error = financeMessageOf(e, 'Muaf daireler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    final apartment = await showApartmentPicker(context, widget.scope);
    if (apartment == null || !mounted) return;
    setState(() => _picked = (id: apartment.id, label: apartment.fullLabel));
  }

  Future<void> _add() async {
    final apartment = _picked;
    if (_busy || apartment == null) return;
    final reason = _reason.text.trim();
    if (trimmedCodePoints(reason) > FinanceReminderExclusionsDialog.maxReasonLength) {
      setState(() => _reasonError = 'Neden en çok ${FinanceReminderExclusionsDialog.maxReasonLength} karakter olabilir.');
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
      _reasonError = null;
    });
    try {
      await widget.scope.f4Call(
        (api, t, s) => api.addReminderExclusion(token: t, siteCode: s, apartmentId: apartment.id, reason: reason),
      );
      if (!mounted) return;
      widget.onChanged?.call();
      _reason.clear();
      setState(() {
        _busy = false;
        _picked = null;
      });
      unawaited(_load());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = financeWriteMessage(
          e,
          'Daire muaf listesine eklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          hint: kFinanceUncertainStateHint,
        );
      });
      unawaited(_load());
    }
  }

  Future<void> _remove(ReminderExclusion item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await widget.scope.f4Call(
        (api, t, s) => api.removeReminderExclusion(token: t, siteCode: s, apartmentId: item.apartmentId),
      );
      if (!mounted) return;
      widget.onChanged?.call();
      setState(() => _busy = false);
      unawaited(_load());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = financeWriteMessage(
          e,
          'Daire muaf listesinden çıkarılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          hint: kFinanceUncertainStateHint,
        );
      });
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final items = _items;
    final Widget list;
    if (items == null) {
      list = _loading || _error == null
          ? const ListSkeleton(rows: 2)
          : InlineNotice(message: _error!, onRetry: _load);
    } else if (items.isEmpty) {
      list = const EmptyCard(
        key: ValueKey<String>('finance_reminder_exclusions_empty'),
        icon: Icons.do_not_disturb_off_rounded,
        title: 'Muaf daire yok.',
      );
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: DialogPanel(
                key: ValueKey<String>('reminder_exclusion_${item.apartmentId}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(financeApartmentTitle(item.blockName, item.label), style: th.titleSmall),
                          if (item.reason != null) Text(item.reason!, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey<String>('reminder_exclusion_remove_${item.apartmentId}'),
                      tooltip: '${item.label} dairesini muaf listesinden çıkar',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: _busy ? null : () => _remove(item),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return AppDialog(
      title: 'Hatırlatmadan Muaf Daireler',
      icon: Icons.do_not_disturb_on_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_reminder_exclusions_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Anlaşmazlık ya da dava altındaki daireleri buraya ekleyin; muaf dairelere borç hatırlatması gönderilmez.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          if (_actionError != null) FinanceSubmitError(key: const ValueKey<String>('finance_reminder_exclusions_error'), message: _actionError!),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_reminder_exclusion_pick'),
            label: _picked == null ? 'Daire Seç' : _picked!.label,
            icon: Icons.apartment_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: _busy ? null : _pick,
          ),
          if (_picked != null) ...[
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey<String>('finance_reminder_exclusion_reason'),
              controller: _reason,
              enabled: !_busy,
              maxLength: FinanceReminderExclusionsDialog.maxReasonLength,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => characterCounter(
                context,
                trimmedCodePoints(_reason.text),
                FinanceReminderExclusionsDialog.maxReasonLength,
              ),
              onChanged: (_) => setState(() => _reasonError = null),
              decoration: InputDecoration(
                labelText: 'Neden (isteğe bağlı)',
                prefixIcon: const Icon(Icons.notes_rounded),
                errorText: _reasonError,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_reminder_exclusion_add'),
              label: 'Muaf Listesine Ekle',
              icon: Icons.add_rounded,
              loading: _busy,
              onPressed: _busy ? null : _add,
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Semantics(header: true, container: true, child: Text('Muaf daireler', style: th.titleMedium)),
          const SizedBox(height: AppSpace.sm),
          list,
        ],
      ),
    );
  }
}
