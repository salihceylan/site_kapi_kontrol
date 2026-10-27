// Firma formu (Firma ve Sözleşme Takibi): yeni firma (`POST .../contract-vendors`) ya da düzenleme (`PATCH`, yalnız
// değişen alanlar). Ad ve kategori zorunlu; yetkili, telefon, e-posta, vergi no ve not isteğe bağlı.
//
// Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Hata pencerenin
// içinde kalır, metinler korunur; 429'da düğme `Retry-After` süresince kilitlenir. Doldurulmuş form yanlışlıkla
// kapanırsa onay istenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/contract_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

class ContractVendorFormDialog extends StatefulWidget {
  const ContractVendorFormDialog({
    super.key,
    required this.service,
    required this.siteCode,
    this.vendor,
    this.initialName = '',
  });

  final ContractService service;
  final int siteCode;

  /// Düzenlenecek firma; null ise yeni firma.
  final ContractVendor? vendor;

  /// Yeni firmada ad alanının başlangıç metni.
  final String initialName;

  /// Başarıda sunucunun döndürdüğü firmayla kapanır; vazgeçilirse ya da değişiklik yoksa null.
  static Future<ContractVendor?> show(
    BuildContext context, {
    required ContractService service,
    required int siteCode,
    ContractVendor? vendor,
    String initialName = '',
  }) {
    return showDialog<ContractVendor>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ContractVendorFormDialog(
        service: service,
        siteCode: siteCode,
        vendor: vendor,
        initialName: initialName,
      ),
    );
  }

  @override
  State<ContractVendorFormDialog> createState() => _ContractVendorFormDialogState();
}

class _ContractVendorFormDialogState extends State<ContractVendorFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'contract_vendor_form_send');
  final RetryLock _retry = RetryLock();
  late final TextEditingController _name = TextEditingController(
    text: widget.vendor?.name ?? widget.initialName,
  );
  late final TextEditingController _contact = TextEditingController(
    text: widget.vendor?.contactName ?? '',
  );
  // Boşsa boş (444 gibi kısa numara da yazılabilsin); numara "+90 XXX XXX XX XX" gruplu, eski serbest kayıt olduğu gibi.
  late final TextEditingController _phone = TextEditingController(
    text: servicePhoneInitial(widget.vendor?.phone),
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.vendor?.email ?? '',
  );
  late final TextEditingController _tax = TextEditingController(
    text: widget.vendor?.taxNo ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.vendor?.note ?? '',
  );
  late ContractCategory _category =
      widget.vendor?.category ?? ContractCategory.diger;
  bool _submitting = false;
  bool _closing = false;
  String? _error;

  bool get _editing => widget.vendor != null;

  @override
  void dispose() {
    _retry.dispose();
    _sendFocus.dispose();
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _tax.dispose();
    _note.dispose();
    super.dispose();
  }

  ContractVendorDraft get _draft => ContractVendorDraft(
    name: _name.text,
    category: _category,
    contactName: _contact.text,
    phone: servicePhoneForSave(_phone.text, stored: widget.vendor?.phone) ?? '',
    email: _email.text,
    taxNo: _tax.text,
    note: _note.text,
  );

  bool get _dirty {
    final original = widget.vendor;
    if (original != null) return _draft.toPatchJson(original).isNotEmpty;
    return _name.text.trim() != widget.initialName.trim() ||
        _contact.text.trim().isNotEmpty ||
        _phone.text.trim().isNotEmpty ||
        _email.text.trim().isNotEmpty ||
        _tax.text.trim().isNotEmpty ||
        _note.text.trim().isNotEmpty ||
        _category != ContractCategory.diger;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final original = widget.vendor;
    final patch = original == null ? null : _draft.toPatchJson(original);
    if (original != null && patch!.isEmpty) {
      // Değişiklik yok: istek gönderilmez.
      _closing = true;
      popIfCurrent<ContractVendor>(context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final saved = original == null
          ? await widget.service.createVendor(widget.siteCode, _draft)
          : await widget.service.updateVendor(widget.siteCode, original.id, patch!);
      if (!mounted) return;
      _closing = true;
      popIfCurrent<ContractVendor>(context, saved);
    } catch (e) {
      if (!mounted) return;
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Firma kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
              key: const ValueKey<String>('contract_vendor_form_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Yazmaya Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('contract_vendor_form_discard'),
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
    popIfCurrent<ContractVendor>(context);
  }

  InputCounterWidgetBuilder _counter(TextEditingController controller, int max) =>
      (context, {required currentLength, required isFocused, maxLength}) =>
          characterCounter(context, trimmedCodePoints(controller.text), max);

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
        title: _editing ? 'Firmayı Düzenle' : 'Yeni Firma',
        subtitle: 'Hizmet aldığınız firmanın bilgileri',
        icon: Icons.business_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('contract_vendor_form_close'),
            onPressed: _submitting ? null : () => unawaited(_requestClose()),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('contract_vendor_form_send'),
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
              TextFormField(
                key: const ValueKey<String>('contract_vendor_form_name'),
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                maxLength: kVendorNameMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: _counter(_name, kVendorNameMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Firma adı',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
                validator: (v) => contractRequiredText(
                  v,
                  kVendorNameMax,
                  emptyMessage: 'Firma adını girin.',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<ContractCategory>(
                key: const ValueKey<String>('contract_vendor_form_category'),
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
                        if (value != null) setState(() => _category = value);
                      },
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('contract_vendor_form_contact'),
                controller: _contact,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                maxLength: kVendorContactMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: _counter(_contact, kVendorContactMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Yetkili kişi (isteğe bağlı)',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (v) => contractOptionalText(v, kVendorContactMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('contract_vendor_form_phone'),
                controller: _phone,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                inputFormatters: const [ServicePhoneInputFormatter()],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Telefon (isteğe bağlı)',
                  hintText: phoneFieldHintAny,
                  helperText: 'Sabit hat ya da cep: +90 XXX XXX XX XX. 444 gibi kısa numaralar olduğu gibi yazılır.',
                  helperMaxLines: 3,
                  prefixIcon: Icon(Icons.call_rounded),
                ),
                // Dokunulmamış eski kayıt (serbest biçim) kaydetmeyi engellemez.
                validator: (v) => validateServicePhoneInput(v, stored: widget.vendor?.phone),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('contract_vendor_form_email'),
                controller: _email,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'E-posta (isteğe bağlı)',
                  hintText: 'destek@firma.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (v) => contractVendorEmailError(v, max: kVendorEmailMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('contract_vendor_form_tax'),
                controller: _tax,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Vergi numarası (isteğe bağlı)',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                validator: (v) => contractVendorTaxNoError(v, max: kVendorTaxNoMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('contract_vendor_form_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kVendorNoteMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: _counter(_note, kVendorNoteMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
                validator: (v) => contractOptionalText(v, kVendorNoteMax),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
