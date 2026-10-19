// Sözleşme formu (Firma ve Sözleşme Takibi): yeni sözleşme (`POST .../contracts`) ya da düzenleme (`PATCH`, yalnız
// değişen alanlar; temizlenen bitiş / tutar / dönem / not `null` gider).
//
// - Firma seçici yalnız AKTİF firmaları listeler; "Yeni firma" kısayolu firma formunu açar ve yeni firmayı seçer.
// - Tarihler "GG.AA.YYYY" metnidir ([DateInputFormatter]; uygulamada Türkçe tarih seçici yoktur). Bitiş boşsa
//   sözleşme süresizdir; doluysa başlangıçtan önce olamaz.
// - Fesih bildirimi 0..365, hatırlatma 0..180 gün; tutar sıfır ya da pozitif, virgül ondalık ("1.250,50").
// - Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Hata pencerenin
//   içinde kalır, metinler korunur; 429'da düğme `Retry-After` süresince kilitlenir. Doldurulmuş form yanlışlıkla
//   kapanırsa onay istenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/contract_vendor_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/contract_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show formatMinor;
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Yeni sözleşmede alanların başlangıç değerleri (gün).
const int kContractDefaultNoticeDays = 30;
const int kContractDefaultRemindDays = 30;

class ContractFormDialog extends StatefulWidget {
  const ContractFormDialog({
    super.key,
    required this.service,
    required this.siteCode,
    this.contract,
  });

  final ContractService service;
  final int siteCode;

  /// Düzenlenecek sözleşme; null ise yeni sözleşme.
  final Contract? contract;

  /// Başarıda sunucunun döndürdüğü sözleşmeyle kapanır; vazgeçilirse ya da değişiklik yoksa null.
  static Future<Contract?> show(
    BuildContext context, {
    required ContractService service,
    required int siteCode,
    Contract? contract,
  }) {
    return showDialog<Contract>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ContractFormDialog(
        service: service,
        siteCode: siteCode,
        contract: contract,
      ),
    );
  }

  @override
  State<ContractFormDialog> createState() => _ContractFormDialogState();
}

class _ContractFormDialogState extends State<ContractFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _vendorKey = GlobalKey();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'contract_form_send');
  final RetryLock _retry = RetryLock();

  late final Contract? _original = widget.contract;
  late int? _vendorId = _original?.vendorId;
  late String? _vendorName = _original?.displayVendor;
  String? _vendorError;

  late final TextEditingController _title = TextEditingController(
    text: _original?.title ?? '',
  );
  late final TextEditingController _start = TextEditingController(
    text: formatDateField(_original?.startDate),
  );
  late final TextEditingController _end = TextEditingController(
    text: formatDateField(_original?.endDate),
  );
  late final TextEditingController _notice = TextEditingController(
    text: '${_original?.noticeDays ?? kContractDefaultNoticeDays}',
  );
  late final TextEditingController _remind = TextEditingController(
    text: '${_original?.remindBeforeDays ?? kContractDefaultRemindDays}',
  );
  late final TextEditingController _amount = TextEditingController(
    text: _original?.amountMinor == null
        ? ''
        : formatMinor(_original!.amountMinor!, symbol: false),
  );
  late final TextEditingController _note = TextEditingController(
    text: _original?.note ?? '',
  );

  late ContractCategory _category = _original?.category ?? ContractCategory.diger;

  /// Kullanıcı kategoriyi kendisi seçti mi? Seçmediyse firma seçilince firmanın kategorisi gelir.
  late bool _categoryTouched = _original != null;
  late ContractPeriod? _period = _original?.period;
  late bool _autoRenew = _original?.autoRenew ?? false;

  bool _submitting = false;
  bool _closing = false;
  bool _dateRejected = false;
  String? _error;

  bool get _editing => _original != null;

  @override
  void dispose() {
    _retry.dispose();
    _sendFocus.dispose();
    _title.dispose();
    _start.dispose();
    _end.dispose();
    _notice.dispose();
    _remind.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Form geçerliyse taslak; değilse null.
  ContractDraft? _draft() {
    final vendorId = _vendorId;
    final start = parseDateField(_start.text);
    final notice = parseContractDayCount(_notice.text, max: kContractNoticeDaysMax);
    final remind = parseContractDayCount(_remind.text, max: kContractRemindDaysMax);
    if (vendorId == null || start == null || notice == null || remind == null) {
      return null;
    }
    return ContractDraft(
      vendorId: vendorId,
      title: _title.text,
      category: _category,
      startDate: start,
      endDate: parseDateField(_end.text),
      noticeDays: notice,
      remindBeforeDays: remind,
      amountMinor: contractAmountFromField(_amount.text),
      period: _period,
      autoRenew: _autoRenew,
      note: _note.text,
    );
  }

  bool get _dirty {
    final original = _original;
    if (original == null) {
      return _vendorId != null ||
          _title.text.trim().isNotEmpty ||
          _start.text.trim().isNotEmpty ||
          _end.text.trim().isNotEmpty ||
          _amount.text.trim().isNotEmpty ||
          _note.text.trim().isNotEmpty ||
          _notice.text.trim() != '$kContractDefaultNoticeDays' ||
          _remind.text.trim() != '$kContractDefaultRemindDays' ||
          _period != null ||
          _autoRenew;
    }
    final draft = _draft();
    // Geçersiz (yarım) giriş de değişikliktir.
    return draft == null || draft.toPatchJson(original).isNotEmpty;
  }

  void _onDateRejected() {
    if (_dateRejected || !mounted) return;
    setState(() => _dateRejected = true);
  }

  void _selectVendor(ContractVendor vendor) {
    setState(() {
      _vendorId = vendor.id;
      _vendorName = vendor.displayName;
      _vendorError = null;
      if (!_categoryTouched) _category = vendor.category;
    });
  }

  Future<void> _pickVendor() async {
    if (_submitting) return;
    final picked = await CrmPickerDialog.show<ContractVendor>(
      context,
      CrmPickerDialog<ContractVendor>(
        title: 'Firma Seç',
        icon: Icons.business_rounded,
        searchLabel: 'Firma ara',
        emptyTitle: 'Aktif firma bulunamadı.',
        fetch: (query, offset, limit) async {
          // Firma listesi sayfasızdır: ilk çağrı hepsini getirir.
          if (offset > 0) return (items: const <ContractVendor>[], total: 0);
          final items = await widget.service.listVendors(
            widget.siteCode,
            active: ContractVendorFilter.active,
            query: query,
          );
          final active = items.where((v) => v.isActive).toList();
          return (items: active, total: active.length);
        },
        keyOf: (vendor) => vendor.id,
        titleOf: (vendor) => vendor.displayName,
        subtitleOf: (vendor) {
          final contact = vendor.contactName?.trim() ?? '';
          return contact.isEmpty
              ? vendor.category.label
              : '${vendor.category.label} • $contact';
        },
      ),
    );
    if (picked == null || !mounted) return;
    _selectVendor(picked);
  }

  Future<void> _newVendor() async {
    if (_submitting) return;
    final created = await ContractVendorFormDialog.show(
      context,
      service: widget.service,
      siteCode: widget.siteCode,
    );
    if (created == null || !mounted) return;
    _selectVendor(created);
  }

  bool _validateVendor() {
    final ok = _vendorId != null;
    setState(() => _vendorError = ok ? null : 'Firma seçin.');
    return ok;
  }

  bool _revealVendor() {
    final target = _vendorKey.currentContext;
    if (_vendorError == null || target == null) return false;
    Scrollable.ensureVisible(target, alignment: 0.15, duration: Duration.zero);
    return true;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(
      _formKey,
      validateExtra: _validateVendor,
      // Firma alanı formun en üstündedir: önce o görünür kılınır.
      reveal: (formContext) {
        if (!_revealVendor()) revealFirstInvalidField(formContext);
      },
    )) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final draft = _draft();
    if (draft == null) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final original = _original;
    final patch = original == null ? null : draft.toPatchJson(original);
    if (original != null && patch!.isEmpty) {
      // Değişiklik yok: istek gönderilmez.
      _closing = true;
      popIfCurrent<Contract>(context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final saved = original == null
          ? await widget.service.createContract(widget.siteCode, draft)
          : await widget.service.updateContract(widget.siteCode, original.id, patch!);
      if (!mounted) return;
      _closing = true;
      popIfCurrent<Contract>(context, saved);
    } catch (e) {
      if (!mounted) return;
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        if (e is ApiException &&
            (e.code == 'VENDOR_INACTIVE' || e.code == 'VENDOR_NOT_FOUND')) {
          _vendorError = 'Başka bir firma seçin.';
        }
        _error = crmMessageOf(
          e,
          'Sözleşme kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendFocus.requestFocus();
      });
    }
  }

  Future<void> _requestClose() async {
    if (_closing || _submitting) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Değişiklikler silinsin mi?',
          icon: Icons.help_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('contract_form_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Yazmaya Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('contract_form_discard'),
              onPressed: () => popIfCurrent(dialogContext, true),
              child: const Text('Vazgeç ve Kapat'),
            ),
          ],
          child: Text(
            'Yazdıklarınız kaydedilmedi.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }
    _closing = true;
    popIfCurrent<Contract>(context);
  }

  InputCounterWidgetBuilder _counter(TextEditingController controller, int max) =>
      (context, {required currentLength, required isFocused, maxLength}) =>
          characterCounter(context, trimmedCodePoints(controller.text), max);

  Widget _dateField({
    required String key,
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    String? helper,
    IconData icon = Icons.event_rounded,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      key: ValueKey<String>(key),
      controller: controller,
      enabled: !_submitting,
      keyboardType: TextInputType.number,
      inputFormatters: [DateInputFormatter(onRejected: _onDateRejected)],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (value) {
        if (_dateRejected) _dateRejected = false;
        onChanged?.call(value);
        setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: 'GG.AA.YYYY',
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }

  Widget _dayField({
    required String key,
    required TextEditingController controller,
    required String label,
    required int max,
    required String helper,
    required IconData icon,
  }) {
    return TextFormField(
      key: ValueKey<String>(key),
      controller: controller,
      enabled: !_submitting,
      keyboardType: TextInputType.number,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'gün',
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: Icon(icon),
      ),
      validator: (v) => contractDayCountError(v, max: max),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppDialog(
        title: _editing ? 'Sözleşmeyi Düzenle' : 'Yeni Sözleşme',
        subtitle: 'Firma, süre ve hatırlatma bilgileri',
        icon: Icons.handshake_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('contract_form_close'),
            onPressed: _submitting ? null : () => unawaited(_requestClose()),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('contract_form_send'),
            focusNode: _sendFocus,
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!, announce: true),
              KeyedSubtree(
                key: _vendorKey,
                child: CrmPickerField(
                  key: const ValueKey<String>('contract_form_vendor'),
                  label: 'Firma',
                  icon: Icons.business_rounded,
                  value: _vendorName,
                  placeholder: 'Firma seçilmedi',
                  errorText: _vendorError,
                  enabled: !_submitting,
                  onTap: () => unawaited(_pickVendor()),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey<String>('contract_form_new_vendor'),
                  onPressed: _submitting ? null : () => unawaited(_newVendor()),
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: const Text('Yeni firma'),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextFormField(
                key: const ValueKey<String>('contract_form_title'),
                controller: _title,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kContractTitleMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: _counter(_title, kContractTitleMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Sözleşme başlığı',
                  hintText: 'Örn. Asansör yıllık bakım sözleşmesi',
                  prefixIcon: Icon(Icons.description_rounded),
                ),
                validator: (v) => contractRequiredText(
                  v,
                  kContractTitleMax,
                  emptyMessage: 'Sözleşme başlığını girin.',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<ContractCategory>(
                key: ValueKey<String>('contract_form_category_${_category.apiValue}'),
                isExpanded: true,
                initialValue: _category,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(contractCategoryIcon(_category)),
                ),
                items: [
                  for (final category in ContractCategory.values)
                    DropdownMenuItem<ContractCategory>(
                      value: category,
                      child: Text(
                        category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _category = value;
                          _categoryTouched = true;
                        });
                      },
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Süre', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              _dateField(
                key: 'contract_form_start',
                controller: _start,
                label: 'Başlangıç tarihi',
                // Bitiş alanı dokunulmuşsa (onUserInteraction) yeniden çizimde başlangıca göre kendiliğinden denetlenir.
                validator: contractStartDateError,
              ),
              const SizedBox(height: AppSpace.md),
              _dateField(
                key: 'contract_form_end',
                controller: _end,
                label: 'Bitiş tarihi (isteğe bağlı)',
                helper: 'Boş bırakılırsa sözleşme süresiz sayılır.',
                icon: Icons.event_available_rounded,
                validator: (v) => contractEndDateError(v, _start.text),
              ),
              if (_dateRejected) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Tarih en çok 8 rakamdır (GG.AA.YYYY).',
                  key: const ValueKey<String>('contract_form_date_rejected'),
                  style: th.bodySmall?.copyWith(color: AppTone.warning.ink(p)),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              _dayField(
                key: 'contract_form_notice',
                controller: _notice,
                label: 'Fesih bildirim süresi',
                max: kContractNoticeDaysMax,
                helper: 'Bitişten kaç gün önce fesih bildirilmeli (0-$kContractNoticeDaysMax).',
                icon: Icons.gavel_rounded,
              ),
              const SizedBox(height: AppSpace.md),
              _dayField(
                key: 'contract_form_remind',
                controller: _remind,
                label: 'Hatırlatma',
                max: kContractRemindDaysMax,
                helper: 'Bitişten kaç gün önce hatırlatılsın (0-$kContractRemindDaysMax).',
                icon: Icons.notifications_active_rounded,
              ),
              const SizedBox(height: AppSpace.xs),
              SwitchListTile(
                key: const ValueKey<String>('contract_form_auto_renew'),
                contentPadding: EdgeInsets.zero,
                value: _autoRenew,
                onChanged: _submitting ? null : (value) => setState(() => _autoRenew = value),
                title: const Text('Otomatik yenilenir'),
                subtitle: const Text(
                  'Fesih bildirimi süresi içinde bildirilmezse sözleşme kendiliğinden uzar.',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text('Ücret', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              MoneyFormField(
                key: const ValueKey<String>('contract_form_amount_box'),
                fieldKey: const ValueKey<String>('contract_form_amount'),
                controller: _amount,
                label: 'Tutar (isteğe bağlı)',
                required: false,
                allowZero: true,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<ContractPeriod?>(
                key: const ValueKey<String>('contract_form_period'),
                isExpanded: true,
                initialValue: _period,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Ödeme dönemi',
                  prefixIcon: Icon(Icons.repeat_rounded),
                ),
                items: [
                  const DropdownMenuItem<ContractPeriod?>(
                    value: null,
                    child: Text('Belirtilmedi', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  for (final period in ContractPeriod.values)
                    DropdownMenuItem<ContractPeriod?>(
                      value: period,
                      child: Text(period.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _submitting ? null : (value) => setState(() => _period = value),
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('contract_form_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kContractNoteMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: _counter(_note, kContractNoteMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
                validator: (v) => contractOptionalText(v, kContractNoteMax),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
