import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart';

/// Kişi / daire / araç değişiklik geçmişi (Platform Faz 2a, F2.11): kim, ne zaman, neyi değiştirdi.
/// Yönetici ve kurul üyesi okur; kayıtlar yalnız eklenir. Sayfalıdır ("Daha fazla yükle", `before_id`).
class HistoryDialog extends StatefulWidget {
  const HistoryDialog({
    super.key,
    required this.scope,
    required this.targetType,
    required this.targetId,
    required this.title,
  });

  final PeopleScope scope;

  /// `person`, `apartment` ya da `vehicle`.
  final String targetType;
  final int targetId;
  final String title;

  static const int pageSize = 30;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required String targetType,
    required int targetId,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => HistoryDialog(
        scope: scope,
        targetType: targetType,
        targetId: targetId,
        title: title,
      ),
    );
  }

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  List<HistoryItem> _items = const <HistoryItem>[];
  int? _nextBeforeId;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadedOnce = false;
  String? _error;
  String? _moreError;

  // Yenileme `_token`'ı ve `_moreToken`'ı, "Daha fazla" yalnız `_moreToken`'ı artırır: eski imleçle gelen
  // sayfa yeni listeye eklenmez.
  int _token = 0;
  int _moreToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    ++_moreToken;
    super.dispose();
  }

  Future<HistoryPage> _fetch({int? beforeId}) {
    return widget.scope.authService.listHistory(
      widget.scope.siteCode,
      targetType: widget.targetType,
      targetId: widget.targetId,
      limit: HistoryDialog.pageSize,
      beforeId: beforeId,
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_token;
    ++_moreToken;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
    try {
      final page = await _fetch();
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _nextBeforeId = page.nextBeforeId;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Geçmiş yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBeforeId;
    if (before == null || _loading || _loadingMore) return;
    final more = ++_moreToken;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await _fetch(beforeId: before);
      if (!mounted || more != _moreToken) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items = <HistoryItem>[
          ..._items,
          ...page.items.where((e) => !known.contains(e.id)),
        ];
        _nextBeforeId = page.nextBeforeId;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || more != _moreToken) return;
      setState(() {
        _loadingMore = false;
        _moreError = crmMessageOf(e, 'Daha fazla kayıt yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final Widget body;
    if (_items.isEmpty && (_loading || (_error == null && !_loadedOnce))) {
      body = const DialogRowsSkeleton(rows: 2, caption: 'Geçmiş yükleniyor...');
    } else if (_items.isEmpty && _error != null) {
      body = InlineNotice(message: _error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = Text('Henüz geçmiş kaydı yok.', style: th.bodyMedium);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: _load),
            const SizedBox(height: AppSpace.md),
          ],
          for (final item in _items) ...[
            _HistoryRow(item: item),
            const SizedBox(height: AppSpace.sm),
          ],
          if (_moreError != null) ...[
            InlineNotice(message: _moreError!, onRetry: _loadMore),
            const SizedBox(height: AppSpace.sm),
          ],
          if (_nextBeforeId != null)
            Align(
              alignment: Alignment.center,
              child: PrimaryActionButton(
                label: 'Daha fazla yükle',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: _loadingMore,
                onPressed: (_loadingMore || _loading) ? null : _loadMore,
              ),
            ),
        ],
      );
    }
    return AppDialog(
      title: 'Geçmiş',
      subtitle: widget.title,
      icon: Icons.history_rounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final actor = (item.actorName ?? '').trim();
    final actorRole = auditActorRoleLabel(item.actorRole);
    final who = item.isAutomatic
        ? 'Sistem tarafından'
        : actor.isEmpty
        ? (actorRole.isEmpty ? 'Sistem' : actorRole)
        : (actorRole.isEmpty ? actor : '$actor • $actorRole');
    final relation = ResidencyRelation.tryParse(item.details['relation']);
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: item.actionLabel,
              tone: auditToneOf(item.action),
              icon: Icons.history_rounded,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(who, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          Text(formatDateTime(item.createdAt), style: th.bodySmall),
          if (relation != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text('İlişki: ${relation.label}', style: th.bodyMedium),
          ],
          for (final change in item.changes) ...[
            const SizedBox(height: AppSpace.xs),
            Text(change.summary, style: th.bodyMedium),
          ],
        ],
      ),
    );
  }
}
