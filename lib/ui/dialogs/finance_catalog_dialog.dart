import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_supplier_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Gider kategorileri ve tedarikçileri yönetimi (Platform Faz 4b, Ö3). Silme YOK: kategori ve tedarikçi
/// pasifleştirilir (geçmiş giderler kayıt anındaki adı taşır). Kurul yalnız okur (ekleme / düzenleme düğmesi yok;
/// tedarikçinin vergi no / telefon / notu sunucuda zaten gizlidir).
class FinanceCatalogDialog extends StatefulWidget {
  const FinanceCatalogDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceCatalogDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceCatalogDialog> createState() => _FinanceCatalogDialogState();
}

class _FinanceCatalogDialogState extends State<FinanceCatalogDialog> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Kategori ve Tedarikçiler',
      icon: Icons.category_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_catalog_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('finance_catalog_tab_categories'),
                avatar: const Icon(Icons.sell_rounded, size: 18),
                label: const Text('Kategoriler'),
                selected: _section == 0,
                onSelected: (_) => setState(() => _section = 0),
              ),
              ChoiceChip(
                key: const ValueKey<String>('finance_catalog_tab_suppliers'),
                avatar: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text('Tedarikçiler'),
                selected: _section == 1,
                onSelected: (_) => setState(() => _section = 1),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (_section == 0)
            _CategoriesSection(scope: widget.scope, onChanged: widget.onChanged)
          else
            _SuppliersSection(scope: widget.scope, onChanged: widget.onChanged),
        ],
      ),
    );
  }
}

// --- Kategoriler -----------------------------------------------------------------------------

class _CategoriesSection extends StatefulWidget {
  const _CategoriesSection({required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  @override
  State<_CategoriesSection> createState() => _CategoriesSectionState();
}

class _CategoriesSectionState extends State<_CategoriesSection> with FinanceWriteMixin {
  @override
  String get keyPrefix => 'cat';

  @override
  Object? get keyOwner => widget.scope.authService;

  final TextEditingController _name = TextEditingController();
  List<ExpenseCategory>? _items;
  bool _loading = true;
  String? _error;
  String? _nameError;
  int _token = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    disposeWrite();
    _name.dispose();
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
      final items = await widget.scope.f4Call((api, t, s) => api.listExpenseCategories(token: t, siteCode: s));
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
        _error = financeMessageOf(e, 'Kategoriler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _add() async {
    if (writeBlocked) return;
    final name = _name.text.trim();
    final length = trimmedCodePoints(name);
    if (length < 1 || length > 60) {
      setState(() => _nameError = length < 1 ? 'Kategori adını girin.' : 'Ad en çok 60 karakter olabilir.');
      return;
    }
    setState(() => _nameError = null);
    await runWrite<ExpenseCategory>(
      signature: 'cat|${name.toLowerCase()}',
      action: (_) => widget.scope.f4Call((api, t, s) => api.createExpenseCategory(token: t, siteCode: s, name: name)),
      onSuccess: (_) {
        _name.clear();
        widget.onChanged?.call();
        unawaited(_load());
      },
      failure: 'Kategori eklenemedi. Tekrar denemeden önce listeyi kontrol edin.',
    );
  }

  Future<void> _edit(ExpenseCategory category) async {
    if (_opening) return;
    _opening = true;
    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CategoryEditDialog(scope: widget.scope, category: category),
      );
      if (changed == true && mounted) {
        widget.onChanged?.call();
        unawaited(_load());
      }
    } finally {
      _opening = false;
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
      list = const EmptyCard(icon: Icons.sell_rounded, title: 'Henüz kategori yok.');
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: DialogPanel(
                key: ValueKey<String>('finance_category_${c.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: th.titleSmall),
                          Wrap(
                            spacing: AppSpace.xs,
                            children: [
                              if (c.isSystem) const DialogMetaPill('Hazır kategori', icon: Icons.verified_rounded),
                              if (!c.isActive)
                                const DialogMetaPill('Pasif', tone: AppTone.neutral, icon: Icons.pause_circle_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.scope.canWrite)
                      IconButton(
                        key: ValueKey<String>('finance_category_edit_${c.id}'),
                        tooltip: '${c.name} kategorisini düzenle',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: _opening ? null : () => _edit(c),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.scope.canWrite) ...[
          if (submitError != null) FinanceSubmitError(message: submitError!),
          TextField(
            key: const ValueKey<String>('finance_category_name'),
            controller: _name,
            enabled: !submitting,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              labelText: 'Yeni kategori adı',
              prefixIcon: const Icon(Icons.sell_rounded),
              errorText: _nameError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_category_add'),
            label: 'Kategori Ekle',
            icon: Icons.add_rounded,
            variant: AppButtonVariant.tonal,
            expand: false,
            loading: submitting,
            onPressed: writeBlocked ? null : _add,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Row(
          children: [
            Expanded(
              child: Semantics(header: true, container: true, child: Text('Kategoriler', style: th.titleMedium)),
            ),
            IconButton(
              tooltip: 'Yenile',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Text(
          'Silinmez: kullanılmayan kategori pasifleştirilir. Geçmiş giderler kayıt anındaki adı korur.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        list,
      ],
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  const _CategoryEditDialog({required this.scope, required this.category});

  final PeopleScope scope;
  final ExpenseCategory category;

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> with FinanceWriteMixin {
  @override
  String get keyPrefix => 'cat-e';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.category.name);
  late bool _active = widget.category.isActive;

  @override
  void dispose() {
    disposeWrite();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    if (!validateForm(_formKey)) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final name = _name.text.trim();
    final fields = <String, Object?>{
      if (name != widget.category.name) 'name': name,
      if (_active != widget.category.isActive) 'is_active': _active,
    };
    if (fields.isEmpty) {
      setState(() => submitError = 'Değişiklik yapmadınız.');
      return;
    }
    await runWrite<ExpenseCategory>(
      signature: 'edit|${widget.category.id}|$name|$_active',
      action: (_) => widget.scope.f4Call(
        (api, t, s) => api.updateExpenseCategory(token: t, siteCode: s, categoryId: widget.category.id, fields: fields),
      ),
      onSuccess: (_) => popIfCurrent(context, true),
      failure: 'Kategori güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !submitting,
      child: AppDialog(
        title: 'Kategoriyi Düzenle',
        icon: Icons.sell_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : () => popIfCurrent(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_category_save'),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(message: submitError!),
              TextFormField(
                key: const ValueKey<String>('finance_category_edit_name'),
                controller: _name,
                enabled: !submitting,
                maxLength: 60,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_name.text), 60),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Kategori adı', prefixIcon: Icon(Icons.sell_rounded)),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (length < 1) return 'Kategori adını girin.';
                  if (length > 60) return 'Ad en çok 60 karakter olabilir.';
                  return null;
                },
              ),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey<String>('finance_category_active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kategori aktif'),
                  subtitle: const Text('Pasif kategoriye yeni gider yazılamaz.'),
                  value: _active,
                  onChanged: submitting ? null : (v) => setState(() => _active = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Tedarikçiler ----------------------------------------------------------------------------

class _SuppliersSection extends StatefulWidget {
  const _SuppliersSection({required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  @override
  State<_SuppliersSection> createState() => _SuppliersSectionState();
}

class _SuppliersSectionState extends State<_SuppliersSection> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String _last = '';
  bool _opening = false;

  late final PagedLoader<Supplier> _loader = PagedLoader<Supplier>(
    fetch: (offset, limit) async {
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listSuppliers(token: t, siteCode: s, query: _query, limit: limit, offset: offset),
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (s) => s.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Tedarikçiler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  void _apply() {
    _timer?.cancel();
    final next = _search.text.trim();
    if (next == _last && (_loader.loading || (_loader.loadedOnce && _loader.error == null))) return;
    _last = next;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  Future<void> _open({Supplier? supplier}) async {
    if (_opening) return;
    _opening = true;
    try {
      final saved = await FinanceSupplierFormDialog.show(context, scope: widget.scope, supplier: supplier);
      if (saved != null && mounted) {
        widget.onChanged?.call();
        showFinanceSnack(context, supplier == null ? 'Tedarikçi eklendi: ${saved.name}.' : 'Tedarikçi güncellendi: ${saved.name}.');
        unawaited(_loader.reload());
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey<String>('finance_catalog_supplier_search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) {
            _timer?.cancel();
            _timer = Timer(const Duration(milliseconds: 350), _apply);
            setState(() {});
          },
          onSubmitted: (_) => _apply(),
          decoration: const InputDecoration(labelText: 'Tedarikçi ara', prefixIcon: Icon(Icons.search_rounded)),
        ),
        if (widget.scope.canWrite) ...[
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_catalog_supplier_add'),
            label: 'Tedarikçi Ekle',
            icon: Icons.add_business_rounded,
            variant: AppButtonVariant.tonal,
            expand: false,
            onPressed: () => _open(),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        CrmListBody<Supplier>(
          loader: _loader,
          emptyIcon: Icons.storefront_rounded,
          emptyTitle: 'Henüz tedarikçi eklenmemiş.',
          filteredTitle: 'Bu aramaya uyan tedarikçi bulunamadı.',
          filtered: _query.isNotEmpty,
          skeletonRows: 2,
          itemBuilder: (context, s) => DialogPanel(
            key: ValueKey<String>('finance_catalog_supplier_${s.id}'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: th.titleSmall),
                      if (s.taxId != null) Text('Vergi / T.C. no: ${s.taxId}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                      if (s.phone != null) Text(s.phone!, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                      if (!s.isActive) const DialogMetaPill('Pasif', tone: AppTone.neutral, icon: Icons.pause_circle_rounded),
                    ],
                  ),
                ),
                if (widget.scope.canWrite)
                  IconButton(
                    key: ValueKey<String>('finance_catalog_supplier_edit_${s.id}'),
                    tooltip: '${s.name} tedarikçisini düzenle',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _opening ? null : () => _open(supplier: s),
                    icon: const Icon(Icons.edit_rounded),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
