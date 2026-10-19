// Yeni ziyaretçi / kargo kaydı formu (docs/PLATFORM_ZIYARETCI_KARGO.md `POST .../visitor-entries`): tür seçimi,
// daire seçici (crm_pickers; isteğe bağlı, ortak alan ziyaretçisi dairesiz açılır), ad (kargoda firma / gönderen),
// firma ve not.
//
// Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Hata pencerenin
// içinde kalır, metinler korunur (odak "Kaydet"e döner); 429'da düğme `Retry-After` süresince kilitlenir.
// Doldurulmuş form yanlışlıkla kapanırsa onay istenir. Başlangıç durumunu SUNUCU hesaplar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/visitor_log_parts.dart';

class VisitorEntryFormDialog extends StatefulWidget {
  const VisitorEntryFormDialog({
    super.key,
    required this.service,
    required this.scope,
    this.initialKind = VisitorKind.cargo,
  });

  final VisitorLogService service;

  /// Kaydın açılacağı site (daire seçici bu kapsamda arar).
  final PeopleScope scope;
  final VisitorKind initialKind;

  /// Başarıda sunucunun döndürdüğü kayıtla kapanır; vazgeçilirse null.
  static Future<VisitorEntry?> show(
    BuildContext context, {
    required VisitorLogService service,
    required PeopleScope scope,
    VisitorKind initialKind = VisitorKind.cargo,
  }) {
    return showDialog<VisitorEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VisitorEntryFormDialog(
        service: service,
        scope: scope,
        initialKind: initialKind,
      ),
    );
  }

  @override
  State<VisitorEntryFormDialog> createState() => _VisitorEntryFormDialogState();
}

class _VisitorEntryFormDialogState extends State<VisitorEntryFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'visitor_form_send');
  final RetryLock _retry = RetryLock();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _company = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late VisitorKind _kind = widget.initialKind;
  ApartmentSummary? _apartment;
  bool _submitting = false;
  bool _closing = false;
  String? _error;

  @override
  void dispose() {
    _retry.dispose();
    _sendFocus.dispose();
    _name.dispose();
    _company.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _company.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty ||
      _apartment != null;

  Future<void> _pickApartment() async {
    if (_submitting) return;
    final picked = await showApartmentPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    setState(() => _apartment = picked);
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final request = VisitorCreateRequest(
      kind: _kind,
      visitorName: _name.text,
      apartmentId: _apartment?.id,
      company: _company.text,
      note: _note.text,
    );
    try {
      final entry = await widget.service.create(widget.scope.siteCode, request);
      if (!mounted) return;
      _closing = true;
      popIfCurrent<VisitorEntry>(context, entry);
    } catch (e) {
      if (!mounted) return;
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Kayıt gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
          title: 'Kayıt silinsin mi?',
          icon: Icons.help_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('visitor_form_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Yazmaya Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('visitor_form_discard'),
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
    popIfCurrent<VisitorEntry>(context);
  }

  Widget _counter(TextEditingController controller, int max) => Builder(
    builder: (context) =>
        visitorCounter(context, controller.text.runes.length, max),
  );

  String? _lengthValidator(String? value, int max, {bool required = false}) {
    final length = (value ?? '').trim().runes.length;
    if (required && length < 1) return 'Bu alan boş olamaz.';
    if (length > max) return 'En çok $max karakter olabilir.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final cargo = _kind == VisitorKind.cargo;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppDialog(
        title: 'Yeni Kayıt',
        subtitle: 'Ziyaretçi veya kargo girişi',
        icon: Icons.door_front_door_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('visitor_form_close'),
            onPressed: _submitting ? null : () => unawaited(_requestClose()),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('visitor_form_send'),
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
              if (_error != null)
                CrmFormError(message: _error!, announce: true),
              Text('Tür', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final kind in VisitorKind.values)
                    ChoiceChip(
                      key: ValueKey<String>('visitor_form_kind_${kind.apiValue}'),
                      avatar: Icon(visitorKindIcon(kind), size: 18),
                      label: Text(kind.label),
                      selected: _kind == kind,
                      onSelected: _submitting
                          ? null
                          : (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                cargo
                    ? 'Kargo "Bekliyor" olarak açılır; sakin aldığında "Teslim edildi" yapın.'
                    : 'Ziyaretçi "İçeride" olarak açılır; çıkışta "Ayrıldı" yapın.',
                style: th.bodySmall,
              ),
              const SizedBox(height: AppSpace.lg),
              CrmPickerField(
                key: const ValueKey<String>('visitor_form_apartment'),
                label: 'Daire (isteğe bağlı)',
                icon: Icons.apartment_rounded,
                value: _apartment?.fullLabel,
                placeholder: 'Ortak alan / daire seçilmedi',
                enabled: !_submitting,
                onTap: () => unawaited(_pickApartment()),
                onClear: () => setState(() => _apartment = null),
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('visitor_form_name'),
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                maxLength: kVisitorNameMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => _counter(_name, kVisitorNameMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: cargo ? 'Kargo firması / gönderen' : 'Ziyaretçi adı',
                  prefixIcon: Icon(visitorKindIcon(_kind)),
                ),
                validator: (v) =>
                    _lengthValidator(v, kVisitorNameMax, required: true),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('visitor_form_company'),
                controller: _company,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                maxLength: kVisitorCompanyMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => _counter(_company, kVisitorCompanyMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: cargo
                      ? 'Takip no / ek bilgi (isteğe bağlı)'
                      : 'Firma (isteğe bağlı)',
                  prefixIcon: const Icon(Icons.business_rounded),
                ),
                validator: (v) => _lengthValidator(v, kVisitorCompanyMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('visitor_form_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kVisitorNoteMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => _counter(_note, kVisitorNoteMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
                validator: (v) => _lengthValidator(v, kVisitorNoteMax),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
