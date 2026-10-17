import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
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
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Tedarikçi ekleme / düzenleme penceresi (Platform Faz 4b, Ö3). Kişisel veri minimumu: ad, vergi / TC kimlik no
/// (10-11 hane), telefon, kısa not. Silme YOK (pasifleştirme). Kurul bu pencereyi açamaz.
class FinanceSupplierFormDialog extends StatefulWidget {
  const FinanceSupplierFormDialog({super.key, required this.scope, this.supplier});

  final PeopleScope scope;
  final Supplier? supplier;

  static const int maxNameLength = 100;
  static const int maxPhoneLength = 20;
  static const int maxNoteLength = 200;

  /// Başarıda kaydedilen (oluşturulan / güncellenen) tedarikçiyi döndürür.
  static Future<Supplier?> show(BuildContext context, {required PeopleScope scope, Supplier? supplier}) {
    return showDialog<Supplier>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceSupplierFormDialog(scope: scope, supplier: supplier),
    );
  }

  @override
  State<FinanceSupplierFormDialog> createState() => _FinanceSupplierFormDialogState();
}

class _FinanceSupplierFormDialogState extends State<FinanceSupplierFormDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'supp';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final TextEditingController _taxId = TextEditingController(text: widget.supplier?.taxId ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.supplier?.note ?? '');
  late bool _active = widget.supplier?.isActive ?? true;

  bool get _editing => widget.supplier != null;

  @override
  void dispose() {
    disposeWrite();
    _name.dispose();
    _taxId.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    if (!validateForm(_formKey)) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final name = _name.text.trim();
    final taxId = _taxId.text.trim();
    final phone = _phone.text.trim();
    final note = _note.text.trim();
    final scope = widget.scope;
    if (_editing) {
      final s = widget.supplier!;
      final fields = <String, Object?>{
        if (name != s.name) 'name': name,
        if (taxId != (s.taxId ?? '')) 'tax_id': taxId.isEmpty ? null : taxId,
        if (phone != (s.phone ?? '')) 'phone': phone.isEmpty ? null : phone,
        if (note != (s.note ?? '')) 'note': note.isEmpty ? null : note,
        if (_active != s.isActive) 'is_active': _active,
      };
      if (fields.isEmpty) {
        setState(() => submitError = 'Değişiklik yapmadınız.');
        return;
      }
      await runWrite<Supplier>(
        signature: 'edit|${s.id}|$name|$taxId|$phone|$note|$_active',
        action: (_) => scope.f4Call(
          (api, t, site) => api.updateSupplier(token: t, siteCode: site, supplierId: s.id, fields: fields),
        ),
        onSuccess: (updated) => popIfCurrent(context, updated),
        failure: 'Tedarikçi güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      return;
    }
    // Oluşturma uçunda işlem anahtarı yoktur (sözleşme): ad tekilliği (aynı ad = çakışma) çift kaydı önler.
    await runWrite<Supplier>(
      signature: 'new|${name.toLowerCase()}|$taxId|$phone|$note',
      action: (_) => scope.f4Call(
        (api, t, site) => api.createSupplier(
          token: t,
          siteCode: site,
          name: name,
          taxId: taxId,
          phone: phone,
          note: note,
        ),
      ),
      onSuccess: (created) => popIfCurrent(context, created),
      failure: 'Tedarikçi eklenemedi. Tekrar denemeden önce tedarikçi listesini kontrol edin.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) => handleBlockedPop(didPop),
      child: AppDialog(
        title: _editing ? 'Tedarikçiyi Düzenle' : 'Tedarikçi Ekle',
        icon: Icons.storefront_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_supplier_submit'),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(message: submitError!),
              TextFormField(
                key: const ValueKey<String>('finance_supplier_name'),
                controller: _name,
                enabled: !submitting,
                textCapitalization: TextCapitalization.words,
                maxLength: FinanceSupplierFormDialog.maxNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_name.text), FinanceSupplierFormDialog.maxNameLength),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Tedarikçi adı', prefixIcon: Icon(Icons.storefront_rounded)),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (length < 1) return 'Tedarikçi adını girin.';
                  if (length > FinanceSupplierFormDialog.maxNameLength) {
                    return 'Ad en çok ${FinanceSupplierFormDialog.maxNameLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_supplier_tax'),
                controller: _taxId,
                enabled: !submitting,
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Vergi / T.C. kimlik no (isteğe bağlı)',
                  prefixIcon: Icon(Icons.badge_rounded),
                  helperText: '10 ya da 11 rakam.',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  return RegExp(r'^\d{10,11}$').hasMatch(text) ? null : 'Numara 10 ya da 11 rakam olmalı.';
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_supplier_phone'),
                controller: _phone,
                enabled: !submitting,
                keyboardType: TextInputType.phone,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(labelText: 'Telefon (isteğe bağlı)', prefixIcon: Icon(Icons.call_rounded)),
                validator: (value) => trimmedCodePoints(value ?? '') > FinanceSupplierFormDialog.maxPhoneLength
                    ? 'Telefon en çok ${FinanceSupplierFormDialog.maxPhoneLength} karakter olabilir.'
                    : null,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_supplier_note'),
                controller: _note,
                enabled: !submitting,
                minLines: 1,
                maxLines: 3,
                maxLength: FinanceSupplierFormDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_note.text), FinanceSupplierFormDialog.maxNoteLength),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) => trimmedCodePoints(value ?? '') > FinanceSupplierFormDialog.maxNoteLength
                    ? 'Not en çok ${FinanceSupplierFormDialog.maxNoteLength} karakter olabilir.'
                    : null,
              ),
              if (_editing)
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const ValueKey<String>('finance_supplier_active'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tedarikçi aktif'),
                    value: _active,
                    onChanged: submitting
                        ? null
                        : (v) => setState(() {
                            markDirty();
                            _active = v;
                          }),
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Yalnızca gerekli bilgileri girin. Kimlik numarası ve telefon kurul üyelerine gösterilmez.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seçici sonucu: tedarikçi ya da "tedarikçisiz".
class SupplierChoice {
  const SupplierChoice.none() : supplier = null;
  const SupplierChoice.of(Supplier this.supplier);

  final Supplier? supplier;
}

/// Gider formundaki tedarikçi seçici: arama (350 ms gecikmeli), "Tedarikçisiz" ve "Yeni tedarikçi ekle". Yalnız AKTİF
/// tedarikçiler listelenir. Liste hatası asla "tedarikçi yok" demez.
class FinanceSupplierPickerDialog extends StatefulWidget {
  const FinanceSupplierPickerDialog({super.key, required this.scope});

  final PeopleScope scope;

  static Future<SupplierChoice?> show(BuildContext context, {required PeopleScope scope}) {
    return showDialog<SupplierChoice>(
      context: context,
      builder: (_) => FinanceSupplierPickerDialog(scope: scope),
    );
  }

  @override
  State<FinanceSupplierPickerDialog> createState() => _FinanceSupplierPickerDialogState();
}

class _FinanceSupplierPickerDialogState extends State<FinanceSupplierPickerDialog> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String _last = '';
  bool _opening = false;

  late final PagedLoader<Supplier> _loader = PagedLoader<Supplier>(
    fetch: (offset, limit) async {
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listSuppliers(token: t, siteCode: s, query: _query, active: true, limit: limit, offset: offset),
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

  Future<void> _add() async {
    if (_opening) return;
    _opening = true;
    try {
      final created = await FinanceSupplierFormDialog.show(context, scope: widget.scope);
      if (created != null && mounted) popIfCurrent(context, SupplierChoice.of(created));
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppDialog(
      title: 'Tedarikçi Seç',
      icon: Icons.storefront_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_supplier_picker_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Vazgeç'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('finance_supplier_search'),
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
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_supplier_none'),
            label: 'Tedarikçisiz',
            icon: Icons.block_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: () => popIfCurrent(context, const SupplierChoice.none()),
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_supplier_add'),
            label: 'Yeni Tedarikçi Ekle',
            icon: Icons.add_business_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: widget.scope.canWrite ? _add : null,
          ),
          const SizedBox(height: AppSpace.md),
          CrmListBody<Supplier>(
            loader: _loader,
            emptyIcon: Icons.storefront_rounded,
            emptyTitle: 'Henüz tedarikçi eklenmemiş.',
            filteredTitle: 'Bu aramaya uyan tedarikçi bulunamadı.',
            filtered: _query.isNotEmpty,
            skeletonRows: 2,
            itemBuilder: (context, supplier) => AppCard(
              key: ValueKey<String>('finance_supplier_${supplier.id}'),
              padding: listCardPadding(context),
              onTap: () => popIfCurrent(context, SupplierChoice.of(supplier)),
              semanticLabel: 'Tedarikçi: ${supplier.name}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const IconTile(icon: Icons.storefront_rounded, gap: AppSpace.md),
                    Expanded(child: Text(supplier.name, style: th.titleSmall?.copyWith(color: p.text))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
