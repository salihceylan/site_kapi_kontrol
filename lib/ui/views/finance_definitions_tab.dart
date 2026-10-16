import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_definition_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_run_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Tanımlar" sekmesi (Platform Faz 4a): aidat ve ek borç tanımları; tür ve durum süzgeci, "Yeni Tanım"
/// (yalnız yazma yetkisi olanda), kartta Borçlandır / Düzenle / Pasifleştir.
///
/// Kurul üyesi salt okur: ne "Yeni Tanım" ne kart eylemleri çizilir. Silme YOKTUR (pasifleştirme). Liste
/// sayfalı değildir (sunucu tüm tanımları verir). Yarış: eski yanıt yenisini ezmez (jeton); hata asla "tanım
/// yok" demez.
class FinanceDefinitionsTab extends StatefulWidget {
  const FinanceDefinitionsTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
    this.now,
  });

  final PeopleScope scope;

  /// Bir tanım eklenip borçlandırılınca / güncellenince çağrılır (özet ve öteki sekmeler tazelenir).
  final VoidCallback onDataChanged;
  final DateTime Function()? now;

  @override
  State<FinanceDefinitionsTab> createState() => FinanceDefinitionsTabState();
}

class FinanceDefinitionsTabState extends State<FinanceDefinitionsTab> {
  List<FeeDefinition> _items = const <FeeDefinition>[];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  String? _actionError;
  int _token = 0;
  FeeKind? _kind;
  bool? _active;
  int? _busyId;
  bool _opening = false;
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

  /// Listeyi yeniden çeker (mevcut liste yenileme sürerken ekranda kalır).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.scope.authService.listFeeDefinitions(
        widget.scope.siteCode,
        kind: _kind,
        active: _active,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _items = items;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Tanımlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  void _applyFilter(void Function() change) {
    setState(() {
      change();
      _items = const <FeeDefinition>[];
      _loadedOnce = false;
    });
    unawaited(reload());
  }

  void _afterChange(String? message) {
    widget.onDataChanged();
    if (!mounted) return;
    if (message != null) AppSnack.show(context, message, kind: AppSnackKind.success);
    unawaited(reload());
  }

  void _refreshOnly() {
    widget.onDataChanged();
    if (mounted) unawaited(reload());
  }

  Future<void> _create() async {
    if (_opening) return;
    _opening = true;
    final FinanceDefinitionOutcome? outcome;
    try {
      outcome = await FinanceDefinitionFormDialog.show(
        context,
        scope: widget.scope,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  Future<void> _edit(FeeDefinition definition) async {
    if (_opening) return;
    _opening = true;
    final FinanceDefinitionOutcome? outcome;
    try {
      outcome = await FinanceDefinitionFormDialog.show(
        context,
        scope: widget.scope,
        definition: definition,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  Future<void> _post(FeeDefinition definition) async {
    if (_opening) return;
    _opening = true;
    final FinanceRunOutcome? outcome;
    try {
      outcome = await FinanceRunDialog.showDefinition(
        context,
        scope: widget.scope,
        definition: definition,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  Future<void> _toggleActive(FeeDefinition definition) async {
    if (_busyId != null || _retry.locked || _opening) return;
    if (definition.isActive) {
      final confirmed = await confirmCrmAction(
        context,
        title: 'Tanımı pasifleştir',
        message:
            'Pasif tanım borçlandırılamaz. Geçmiş kayıtlar değişmez; tanımı istediğiniz zaman yeniden '
            'etkinleştirebilirsiniz.',
        confirmLabel: 'Pasifleştir',
        icon: Icons.pause_circle_outline_rounded,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _busyId = definition.id;
      _actionError = null;
    });
    try {
      await widget.scope.authService.updateFeeDefinition(
        widget.scope.siteCode,
        definition.id,
        <String, Object?>{'is_active': !definition.isActive},
      );
      if (!mounted) return;
      setState(() => _busyId = null);
      _afterChange(definition.isActive ? 'Tanım pasifleştirildi.' : 'Tanım etkinleştirildi.');
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _busyId = null;
        _actionError = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(
                e,
                'Tanım güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
                hint: kFinanceUncertainStateHint,
              );
      });
      // Belirsiz sonuç: tanımın gerçek durumu için liste yeniden okunur.
      if (financeOutcomeUncertain(e)) unawaited(reload());
    }
  }

  bool get _filtered => _kind != null || _active != null;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final Widget body;
    if (_items.isEmpty && (_loading || (!_loadedOnce && _error == null))) {
      body = const ListSkeleton(rows: 3);
    } else if (_items.isEmpty && _error != null) {
      body = InlineNotice(message: _error!, onRetry: reload);
    } else if (_items.isEmpty) {
      body = EmptyCard(
        icon: Icons.request_quote_rounded,
        title: _filtered ? 'Bu süzgeç için tanım bulunamadı.' : 'Henüz tanım yok.',
        message: _filtered || !_canWrite
            ? null
            : 'Yeni Tanım ile aylık aidat ya da tek seferlik borç tanımı ekleyebilirsiniz.',
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: reload),
            const SizedBox(height: AppSpace.md),
          ],
          for (final definition in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: FeeDefinitionCard(
                definition: definition,
                busy: _busyId == definition.id || _opening,
                onPost: _canWrite &&
                        definition.isActive &&
                        definition.isKnown &&
                        (definition.isRecurring || definition.neverPosted)
                    ? () => _post(definition)
                    : null,
                onEdit: _canWrite && definition.isKnown ? () => _edit(definition) : null,
                onToggleActive: _canWrite ? () => _toggleActive(definition) : null,
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_canWrite) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('finance_definition_create'),
            label: 'Yeni Tanım',
            icon: Icons.add_rounded,
            onPressed: _create,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tür', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('finance_kind_filter_all'),
                    label: const Text('Tümü'),
                    selected: _kind == null,
                    onSelected: (_) => _applyFilter(() => _kind = null),
                  ),
                  ChoiceChip(
                    key: const ValueKey<String>('finance_kind_filter_recurring'),
                    label: Text(FeeKind.recurring.label),
                    selected: _kind == FeeKind.recurring,
                    onSelected: (_) => _applyFilter(() => _kind = FeeKind.recurring),
                  ),
                  ChoiceChip(
                    key: const ValueKey<String>('finance_kind_filter_one_time'),
                    label: Text(FeeKind.oneTime.label),
                    selected: _kind == FeeKind.oneTime,
                    onSelected: (_) => _applyFilter(() => _kind = FeeKind.oneTime),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Text('Durum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('finance_active_filter_all'),
                    label: const Text('Hepsi'),
                    selected: _active == null,
                    onSelected: (_) => _applyFilter(() => _active = null),
                  ),
                  ChoiceChip(
                    key: const ValueKey<String>('finance_active_filter_active'),
                    label: const Text('Aktif'),
                    selected: _active == true,
                    onSelected: (_) => _applyFilter(() => _active = true),
                  ),
                  ChoiceChip(
                    key: const ValueKey<String>('finance_active_filter_passive'),
                    label: const Text('Pasif'),
                    selected: _active == false,
                    onSelected: (_) => _applyFilter(() => _active = false),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Tanımlar',
          count: _loadedOnce ? _items.length : null,
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
}
