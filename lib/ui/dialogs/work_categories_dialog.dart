// İş Takibi talep kategorileri yönetimi (100, P2-11): site yöneticisi kategori ekler, yeniden adlandırır, pasife alır /
// yeniden etkinleştirir ve kullanılmamış özel kategoriyi siler. KULLANILMIŞ kategori silinmez, PASİFE alınır (eski talepler
// kategorisini korur). Varsayılan dört kategori ("Hazır kategori") silinmez. Yetkinin tek kaynağı sunucudur (yazma yalnız
// yönetici / süper); bu pencere yalnız onlara açılır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Sunucu sınırı: kategori adı en çok 60 karakter, sitede en çok 40 kategori.
const int kWorkCategoryLabelMax = 60;

class WorkCategoriesDialog extends StatefulWidget {
  const WorkCategoriesDialog({super.key, required this.service, required this.site});

  final WorkTrackingService service;
  final WorkTrackingSite site;

  /// Pencere kapanınca, kategoriler DEĞİŞTİYSE true (çağıran liste / süzgeci yeniler).
  static Future<bool> show(
    BuildContext context, {
    required WorkTrackingService service,
    required WorkTrackingSite site,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkCategoriesDialog(service: service, site: site),
    );
    return changed == true;
  }

  @override
  State<WorkCategoriesDialog> createState() => _WorkCategoriesDialogState();
}

class _WorkCategoriesDialogState extends State<WorkCategoriesDialog> {
  final TextEditingController _name = TextEditingController();
  final RetryLock _retry = RetryLock();

  List<WorkCategoryOption>? _items;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _loadError;
  String? _nameError;
  String? _actionError;
  String? _notice;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await widget.service.categories(widget.site.code);
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
        _loadError = crmMessageOf(e, 'Kategoriler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  /// Yazma işlemi: tek seferde bir işlem; başarıda liste yeniden çekilir ve çağıran bilgilendirilir.
  Future<void> _run(Future<String?> Function() action, String failure) async {
    if (_busy || _retry.locked) return;
    setState(() {
      _busy = true;
      _actionError = null;
      _notice = null;
    });
    try {
      final notice = await action();
      if (!mounted) return;
      _changed = true;
      setState(() {
        _busy = false;
        _notice = notice;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      final locked = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _busy = false;
        _actionError = locked ? RetryLock.messageFor(e) : crmMessageOf(e, failure);
      });
      // Yarışta başka biri değiştirdiyse (404 / 409) liste sunucuyla eşitlenir; ağ hatasında liste olduğu gibi kalır.
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 409)) unawaited(_load());
    }
  }

  String? _validate(String raw) {
    final length = trimmedCodePoints(raw);
    if (length < 1) return 'Kategori adını girin.';
    if (length > kWorkCategoryLabelMax) return 'Ad en çok $kWorkCategoryLabelMax karakter olabilir.';
    return null;
  }

  Future<void> _add() async {
    final error = _validate(_name.text);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    setState(() => _nameError = null);
    final label = _name.text.trim();
    await _run(() async {
      final created = await widget.service.createCategory(widget.site.code, label);
      _name.clear();
      return '“${created.label}” eklendi. Sakinler talep açarken bu kategoriyi seçebilir.';
    }, 'Kategori eklenemedi. Tekrar denemeden önce listeyi kontrol edin.');
  }

  Future<void> _rename(WorkCategoryOption category) async {
    if (_busy) return;
    final label = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: category.label),
    );
    if (label == null || !mounted || label == category.label) return;
    await _run(() async {
      final updated = await widget.service.updateCategory(widget.site.code, category.id, label: label);
      return 'Kategori “${updated.label}” olarak güncellendi.';
    }, 'Kategori adı değiştirilemedi. Tekrar deneyin.');
  }

  Future<void> _toggle(WorkCategoryOption category) async {
    if (_busy) return;
    final activate = !category.isActive;
    await _run(() async {
      final updated = await widget.service.updateCategory(widget.site.code, category.id, isActive: activate);
      return activate
          ? '“${updated.label}” yeniden etkinleştirildi.'
          : '“${updated.label}” pasife alındı; yeni taleplerde seçilemez, eski talepler korunur.';
    }, 'Kategori güncellenemedi. Tekrar deneyin.');
  }

  Future<void> _delete(WorkCategoryOption category) async {
    if (_busy) return;
    final used = category.isUsed;
    final confirmed = await confirmCrmAction(
      context,
      title: used ? 'Kategori pasife alınsın mı?' : 'Kategori silinsin mi?',
      message: used
          ? '“${category.label}” ${category.itemCount} talepte kullanıldığı için silinemez; pasife alınır. Eski talepler bu kategoriyi korur, yeni taleplerde seçilemez.'
          : '“${category.label}” kalıcı olarak silinecek. Hiçbir talepte kullanılmamıştır.',
      confirmLabel: used ? 'Pasife Al' : 'Sil',
      icon: used ? Icons.pause_circle_rounded : Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      final result = await widget.service.deleteCategory(widget.site.code, category.id);
      final name = result.category?.label ?? category.label;
      return result.deleted
          ? '“${category.label}” silindi.'
          : '“$name” kullanıldığı için silinmedi, pasife alındı. Eski talepler bu kategoriyi korur.';
    }, 'Kategori silinemedi. Tekrar deneyin.');
  }

  void _close() => popIfCurrent<bool>(context, _changed);

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final items = _items;
    final Widget list;
    if (items == null) {
      list = _loading || _loadError == null
          ? const ListSkeleton(rows: 3)
          : InlineNotice(key: const ValueKey<String>('work_categories_error'), message: _loadError!, onRetry: _load);
    } else if (items.isEmpty) {
      list = const EmptyCard(icon: Icons.category_rounded, title: 'Henüz kategori yok.');
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final category in items) _row(context, category)],
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AppDialog(
        title: 'Talep Kategorileri',
        subtitle: widget.site.label,
        icon: Icons.category_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('work_categories_close'),
            onPressed: _close,
            child: const Text('Kapat'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sakinler talep açarken bu listeden seçer. Kullanılmış bir kategori silinmez, pasife alınır; eski talepler kategorisini korur.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            if (_actionError != null) ...[
              InlineNotice(key: const ValueKey<String>('work_categories_action_error'), message: _actionError!),
              const SizedBox(height: AppSpace.sm),
            ],
            if (_notice != null) ...[
              InlineNotice(
                key: const ValueKey<String>('work_categories_notice'),
                tone: AppTone.success,
                message: _notice!,
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            TextField(
              key: const ValueKey<String>('work_categories_name'),
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => unawaited(_add()),
              decoration: InputDecoration(
                labelText: 'Yeni kategori adı',
                hintText: 'Örn. Su kaçağı',
                prefixIcon: const Icon(Icons.sell_rounded),
                errorText: _nameError,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('work_categories_add'),
              label: 'Kategori Ekle',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: _busy,
              onPressed: _busy || _retry.locked ? null : () => unawaited(_add()),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(child: Semantics(header: true, container: true, child: Text('Kategoriler', style: th.titleMedium))),
                IconButton(
                  key: const ValueKey<String>('work_categories_refresh'),
                  tooltip: 'Yenile',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _loading || _busy ? null : () => unawaited(_load()),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            list,
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WorkCategoryOption c) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final count = c.itemCount ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DialogPanel(
        key: ValueKey<String>('work_category_row_${c.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.label,
                    style: th.titleSmall?.copyWith(color: c.isActive ? null : p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (c.isSystem) const DialogMetaPill('Hazır kategori', icon: Icons.verified_rounded),
                      if (!c.isActive)
                        const DialogMetaPill('Pasif', tone: AppTone.neutral, icon: Icons.pause_circle_rounded),
                      if (c.itemCount != null) DialogMetaPill(count == 0 ? 'Kullanılmadı' : '$count talep'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey<String>('work_category_edit_${c.id}'),
              tooltip: '${c.label} kategorisini yeniden adlandır',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _busy ? null : () => unawaited(_rename(c)),
              icon: const Icon(Icons.edit_rounded),
            ),
            IconButton(
              key: ValueKey<String>('work_category_toggle_${c.id}'),
              tooltip: c.isActive ? '${c.label} kategorisini pasife al' : '${c.label} kategorisini etkinleştir',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _busy ? null : () => unawaited(_toggle(c)),
              icon: Icon(c.isActive ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            ),
            if (!c.isSystem)
              IconButton(
                key: ValueKey<String>('work_category_delete_${c.id}'),
                tooltip: c.isUsed ? '${c.label} kategorisi kullanıldı; pasife alınır' : '${c.label} kategorisini sil',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _busy ? null : () => unawaited(_delete(c)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// Kategori adı girişi (yeniden adlandırma). Boş ya da 60 karakteri aşan ad kabul edilmez; vazgeçilirse null.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final length = trimmedCodePoints(_controller.text);
    if (length < 1) {
      setState(() => _error = 'Kategori adını girin.');
      return;
    }
    if (length > kWorkCategoryLabelMax) {
      setState(() => _error = 'Ad en çok $kWorkCategoryLabelMax karakter olabilir.');
      return;
    }
    popIfCurrent<String>(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Kategoriyi Yeniden Adlandır',
      icon: Icons.edit_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('work_category_rename_cancel'),
          onPressed: () => popIfCurrent<String>(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('work_category_rename_save'),
          onPressed: _submit,
          child: const Text('Kaydet'),
        ),
      ],
      child: TextField(
        key: const ValueKey<String>('work_category_rename_field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Kategori adı',
          prefixIcon: const Icon(Icons.sell_rounded),
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}
