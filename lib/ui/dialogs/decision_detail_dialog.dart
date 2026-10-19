// Karar ayrıntısı: tam metin, oy sayıları, katılanlar, kesinleştiren / zaman, değiştirdiği karar bağlantısı (dokununca o
// karar açılır) ve "X sayılı kararla değiştirildi" bağlantıları.
//
// Yönetim görünümünde ([site] verilir) yazabilen kullanıcı TASLAKTA: Düzenle, Sil (onaylı), Kesinleştir (güçlü onay:
// "Okudum, anladım" işaretlenmeden düğme açılmaz); KESİN kararda: "Düzeltme kararı yaz". Kurul ve sakin SALT OKUR.
// Sakin görünümü ([site] null) `GET /app/decisions/:id` ile okur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/decision_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatCrmDate;
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/decision_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Kesinleştirme uyarısı (birebir metin).
const String kDecisionFinalizeWarning =
    'Kesinleşen karar numara alır ve bir daha değiştirilemez ya da silinemez. Düzeltme gerekirse yeni bir karar yazılır.';

/// Ayrıntı penceresinin sonucu: liste yenilenmeli mi ([changed]) ve "Düzeltme kararı yaz" seçildiyse düzeltilecek
/// karar ([correctionOf]; çağıran yeni karar formunu `supersedes_id` dolu açar).
@immutable
class DecisionDetailOutcome {
  const DecisionDetailOutcome({this.changed = false, this.correctionOf});

  final bool changed;
  final Decision? correctionOf;
}

/// Güçlü kesinleştirme onayı: uyarı metni + "Okudum, anladım" işareti; işaretlenmeden "Kesinleştir" kapalıdır.
Future<bool> confirmDecisionFinalize(BuildContext context, Decision decision) async {
  var acknowledged = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AppDialog(
        key: const ValueKey<String>('decision_finalize_dialog'),
        title: 'Kararı kesinleştir',
        subtitle: decision.title,
        icon: Icons.verified_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('decision_finalize_cancel'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('decision_finalize_confirm'),
            style: filledToneStyle(dialogContext, tone: AppTone.warning),
            onPressed: acknowledged ? () => popIfCurrent(dialogContext, true) : null,
            child: const Text('Kesinleştir'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const InlineNotice(
              key: ValueKey<String>('decision_finalize_warning'),
              tone: AppTone.warning,
              icon: Icons.lock_outline_rounded,
              message: kDecisionFinalizeWarning,
            ),
            const SizedBox(height: AppSpace.md),
            CheckboxListTile(
              key: const ValueKey<String>('decision_finalize_ack'),
              value: acknowledged,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Okudum, anladım: bu karar artık değiştirilemeyecek.'),
              onChanged: (v) => setState(() => acknowledged = v ?? false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

class DecisionDetailDialog extends StatefulWidget {
  const DecisionDetailDialog({
    super.key,
    required this.service,
    required this.id,
    this.site,
    this.initial,
    this.clock,
  });

  final DecisionBookService service;
  final int id;

  /// Yönetim görünümü: kararın sitesi (yazma yetkisi buradan). Sakin görünümünde null.
  final DecisionSite? site;

  /// Listeden gelen kayıt (ayrıntı yüklenirken gösterilir); bağlantıdan açılınca null.
  final Decision? initial;

  /// Test düzeneği (form için şimdiki an).
  final DateTime Function()? clock;

  static Future<DecisionDetailOutcome?> show(
    BuildContext context, {
    required DecisionBookService service,
    required int id,
    DecisionSite? site,
    Decision? initial,
    DateTime Function()? clock,
  }) {
    return showDialog<DecisionDetailOutcome>(
      context: context,
      builder: (_) => DecisionDetailDialog(service: service, id: id, site: site, initial: initial, clock: clock),
    );
  }

  @override
  State<DecisionDetailDialog> createState() => _DecisionDetailDialogState();
}

class _DecisionDetailDialogState extends State<DecisionDetailDialog> {
  Decision? _decision;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  bool get _manager => widget.site != null;
  bool get _canWrite => widget.site?.canWrite ?? false;

  @override
  void initState() {
    super.initState();
    _decision = widget.initial;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final site = widget.site;
      final decision = site != null
          ? await widget.service.getManaged(site.code, widget.id)
          : await widget.service.getMine(widget.id);
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Karar yüklenemedi. Lütfen tekrar deneyin.');
      });
    }
  }

  void _close([Decision? correctionOf]) {
    popIfCurrent(context, DecisionDetailOutcome(changed: _changed, correctionOf: correctionOf));
  }

  /// Bağlantılı kararı (değiştirdiği / değiştiren) üstte açar.
  Future<void> _openLinked(int id) async {
    final outcome = await DecisionDetailDialog.show(
      context,
      service: widget.service,
      id: id,
      site: widget.site,
      clock: widget.clock,
    );
    if (!mounted || outcome == null) return;
    if (outcome.changed) _changed = true;
    if (outcome.correctionOf != null) _close(outcome.correctionOf);
  }

  void _onWriteError(Object e) {
    AppSnack.show(context, crmMessageOf(e, 'İşlem yapılamadı. Lütfen tekrar deneyin.'), kind: AppSnackKind.error);
    if (e is ApiException && (e.code == 'DECISION_FINAL' || e.code == 'DECISION_NOT_FOUND')) {
      // Başkası kesinleştirmiş ya da silmiş olabilir: ayrıntı ve liste tazelenir.
      _changed = true;
      unawaited(_load());
    }
  }

  Future<void> _edit(Decision decision) async {
    final site = widget.site;
    if (site == null || _busy) return;
    final updated = await DecisionFormDialog.show(
      context,
      service: widget.service,
      site: site,
      initial: decision,
      clock: widget.clock,
    );
    if (!mounted) return;
    if (updated == null) {
      // Kaydedilmedi (vazgeçildi ya da hata): başkası değiştirmiş olabilir, ayrıntı tazelenir.
      unawaited(_load());
      return;
    }
    setState(() {
      _decision = updated;
      _changed = true;
    });
    AppSnack.show(context, 'Taslak güncellendi.', kind: AppSnackKind.success);
  }

  Future<void> _delete(Decision decision) async {
    final site = widget.site;
    if (site == null || _busy) return;
    final ok = await confirmCrmAction(
      context,
      title: 'Taslağı sil',
      message: '"${decision.title}" taslağı kalıcı olarak silinir.',
      confirmLabel: 'Sil',
      icon: Icons.delete_outline_rounded,
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.delete(site.code, decision.id);
      if (!mounted) return;
      _changed = true;
      AppSnack.show(context, 'Taslak silindi.', kind: AppSnackKind.success);
      setState(() => _busy = false);
      _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _onWriteError(e);
    }
  }

  /// Toplantı günü bugünden (İstanbul) sonra mı? Sunucu böyle bir taslağı kesinleştirmez (409
  /// `DECISION_MEETING_IN_FUTURE`): onay penceresi açılmadan söylenir.
  bool _meetingInFuture(Decision decision) {
    final day = decision.meetingDate;
    if (day == null) return false;
    final now = istanbulNow(widget.clock?.call());
    return day.isAfter(DateTime(now.year, now.month, now.day));
  }

  Future<void> _finalize(Decision decision) async {
    final site = widget.site;
    if (site == null || _busy) return;
    if (_meetingInFuture(decision)) {
      AppSnack.show(
        context,
        '${DecisionBookApi.decisionErrorMessage('DECISION_MEETING_IN_FUTURE')} Toplantıdan sonra kesinleştirin ya da tarihi düzeltin.',
        kind: AppSnackKind.error,
      );
      return;
    }
    final ok = await confirmDecisionFinalize(context, decision);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.service.finalize(site.code, decision.id);
      if (!mounted) return;
      setState(() {
        _decision = updated;
        _changed = true;
        _busy = false;
      });
      AppSnack.show(
        context,
        updated.numberLabel == null ? 'Karar kesinleşti.' : 'Karar kesinleşti: ${updated.numberLabel}.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _onWriteError(e);
    }
  }

  Widget _section(BuildContext context, String title, Widget child) {
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: th.titleSmall)),
          const SizedBox(height: AppSpace.xs),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final d = _decision;
    final actions = <Widget>[
      TextButton(
        key: const ValueKey<String>('decision_detail_close'),
        onPressed: _busy ? null : () => _close(),
        child: const Text('Kapat'),
      ),
      if (_canWrite && d != null && !_loading && d.isDraft) ...[
        TextButton(
          key: const ValueKey<String>('decision_action_delete'),
          onPressed: _busy ? null : () => unawaited(_delete(d)),
          child: const Text('Sil'),
        ),
        TextButton(
          key: const ValueKey<String>('decision_action_edit'),
          onPressed: _busy ? null : () => unawaited(_edit(d)),
          child: const Text('Düzenle'),
        ),
        FilledButton(
          key: const ValueKey<String>('decision_action_finalize'),
          onPressed: _busy ? null : () => unawaited(_finalize(d)),
          child: const Text('Kesinleştir'),
        ),
      ],
      if (_canWrite && d != null && !_loading && d.isFinal)
        FilledButton.tonal(
          key: const ValueKey<String>('decision_action_correction'),
          onPressed: _busy ? null : () => _close(d),
          child: const Text('Düzeltme kararı yaz'),
        ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: AppDialog(
        key: const ValueKey<String>('decision_detail'),
        title: d == null || d.title.isEmpty ? 'Karar' : d.title,
        subtitle: d == null ? null : (d.isFinal ? 'Karar ${d.displayNumber}' : 'Taslak karar'),
        icon: Icons.gavel_rounded,
        actions: actions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              InlineNotice(
                key: const ValueKey<String>('decision_detail_error'),
                message: _error!,
                tone: AppTone.danger,
                onRetry: _load,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (d == null)
              (_loading ? const ListSkeleton(rows: 2) : const SizedBox.shrink())
            else ...[
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  DecisionNumberChip(decision: d),
                  DecisionVoteChip(result: d.voteResult),
                  if (_manager && d.isVisibleToResidents) const DecisionResidentsMarker(),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Toplantı: ${d.meetingType.label} · ${formatCrmDate(d.meetingDate)}',
                style: th.bodyMedium,
              ),
              if (_loading) ...[
                const SizedBox(height: AppSpace.sm),
                const LinearProgressIndicator(key: ValueKey<String>('decision_detail_loading')),
              ],
              if (d.supersededText != null) ...[
                const SizedBox(height: AppSpace.md),
                InlineNotice(
                  key: const ValueKey<String>('decision_detail_superseded'),
                  tone: AppTone.warning,
                  icon: Icons.swap_horiz_rounded,
                  message: '${d.supersededText}.',
                ),
                for (final ref in d.supersededBy)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: ValueKey<String>('decision_open_ref_${ref.id}'),
                      onPressed: _busy ? null : () => unawaited(_openLinked(ref.id)),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(ref.numberLabel == null ? 'Yeni kararı aç' : 'Kararı aç: ${ref.numberLabel}'),
                    ),
                  ),
              ],
              if (d.supersedes != null) ...[
                const SizedBox(height: AppSpace.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey<String>('decision_open_supersedes'),
                    onPressed: _busy ? null : () => unawaited(_openLinked(d.supersedes!.id)),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: Text(
                      d.supersedes!.numberLabel == null
                          ? 'Değiştirdiği kararı aç'
                          : 'Değiştirdiği karar: ${d.supersedes!.numberLabel}',
                    ),
                  ),
                ),
              ],
              _section(
                context,
                'Karar metni',
                SelectableText(
                  d.body.isEmpty ? '-' : d.body,
                  key: const ValueKey<String>('decision_detail_body'),
                  style: th.bodyMedium,
                ),
              ),
              _section(
                context,
                'Oylama',
                Text(
                  d.voteCountsText == null ? d.voteResult.label : '${d.voteResult.label} · ${d.voteCountsText}',
                  key: const ValueKey<String>('decision_detail_votes'),
                  style: th.bodyMedium,
                ),
              ),
              if (d.attendees != null)
                _section(
                  context,
                  'Katılanlar',
                  Text(d.attendees!, key: const ValueKey<String>('decision_detail_attendees'), style: th.bodyMedium),
                ),
              const SizedBox(height: AppSpace.lg),
              if (_manager && d.createdByName != null)
                Text('Yazan: ${d.createdByName}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              if (d.isFinal && (d.finalizedByName != null || d.finalizedAt != null))
                Text(
                  'Kesinleştiren: ${<String>[?d.finalizedByName, if (d.finalizedAt != null) formatIstanbulDateTime(d.finalizedAt)].join(' · ')}',
                  key: const ValueKey<String>('decision_detail_finalized'),
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              if (_manager && d.isDraft)
                Text(
                  'Taslak: kesinleştirilene kadar numara almaz ve sakinlere görünmez.',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
            ],
            const SizedBox(height: AppSpace.md),
            const DecisionLegalNote(),
          ],
        ),
      ),
    );
  }
}
