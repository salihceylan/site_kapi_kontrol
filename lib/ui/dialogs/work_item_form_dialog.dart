// Yeni talep formu (docs/PLATFORM_IS_TAKIBI.md `POST /app/work-items`): kategori, konum, başlık, açıklama ve "acil"
// işareti. Fotoğraf / dosya eki bu sürümde YOK.
//
// Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Aynı veriyle
// yeniden gönderimde servis AYNI `idempotency_key`i kullanır (yanıtı kaybolan istek çift talep açmaz); veri
// değişince anahtar yenilenir. Hata pencerenin içinde kalır, metinler korunur (odak "Gönder"e döner); 429'da düğme
// `Retry-After` süresince kilitlenir. Doldurulmuş form yanlışlıkla kapanırsa onay istenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

class WorkItemFormDialog extends StatefulWidget {
  const WorkItemFormDialog({
    super.key,
    required this.service,
    required this.sites,
    this.initialSiteCode,
  });

  final WorkTrackingService service;

  /// Talep açılabilecek (modül açık) siteler; en az bir tane.
  final List<PeopleSite> sites;
  final int? initialSiteCode;

  /// Başarıda sunucunun döndürdüğü kayıtla kapanır; vazgeçilirse null.
  static Future<WorkCreateResult?> show(
    BuildContext context, {
    required WorkTrackingService service,
    required List<PeopleSite> sites,
    int? initialSiteCode,
  }) {
    return showDialog<WorkCreateResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkItemFormDialog(
        service: service,
        sites: sites,
        initialSiteCode: initialSiteCode,
      ),
    );
  }

  @override
  State<WorkItemFormDialog> createState() => _WorkItemFormDialogState();
}

class _WorkItemFormDialogState extends State<WorkItemFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _apartmentKey = GlobalKey();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'work_form_send');
  final RetryLock _retry = RetryLock();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  late int _siteCode = _initialSite();
  WorkCategory _category = WorkCategory.ariza;
  WorkLocationType _location = WorkLocationType.ortakAlan;
  bool _urgent = false;

  List<WorkApartmentChoice>? _apartments;
  bool _apartmentsLoading = false;
  String? _apartmentsError;
  int? _apartmentId;
  String? _apartmentFieldError;
  int _apartmentsToken = 0;

  bool _submitting = false;
  bool _closing = false;
  String? _error;

  int _initialSite() {
    final wanted = widget.initialSiteCode;
    if (wanted != null && widget.sites.any((s) => s.code == wanted)) {
      return wanted;
    }
    return widget.sites.first.code;
  }

  @override
  void dispose() {
    ++_apartmentsToken;
    _retry.dispose();
    _sendFocus.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text.trim().isNotEmpty || _description.text.trim().isNotEmpty;

  Future<void> _loadApartments() async {
    final token = ++_apartmentsToken;
    final siteCode = _siteCode;
    setState(() {
      _apartmentsLoading = true;
      _apartmentsError = null;
      _apartments = null;
      _apartmentId = null;
    });
    try {
      final list = await widget.service.myApartments(siteCode);
      if (!mounted || token != _apartmentsToken) return;
      setState(() {
        _apartments = list;
        _apartmentsLoading = false;
        // Tek dairesi olan sakinde seçim otomatiktir.
        _apartmentId = list.length == 1 ? list.first.id : null;
      });
    } catch (e) {
      if (!mounted || token != _apartmentsToken) return;
      setState(() {
        _apartmentsLoading = false;
        _apartmentsError = crmMessageOf(
          e,
          'Daireleriniz yüklenemedi. Tekrar deneyin.',
        );
      });
    }
  }

  void _selectLocation(WorkLocationType type) {
    if (type == _location || _submitting) return;
    setState(() {
      _location = type;
      _apartmentFieldError = null;
    });
    if (type == WorkLocationType.daire && _apartments == null) {
      unawaited(_loadApartments());
    }
  }

  void _selectSite(int code) {
    if (code == _siteCode || _submitting) return;
    setState(() {
      _siteCode = code;
      _apartments = null;
      _apartmentId = null;
      _apartmentsError = null;
      _apartmentFieldError = null;
    });
    ++_apartmentsToken;
    if (_location == WorkLocationType.daire) unawaited(_loadApartments());
  }

  bool _validateExtras() {
    String? error;
    if (_location == WorkLocationType.daire) {
      final list = _apartments;
      if (_apartmentsLoading) {
        error = 'Daireleriniz yükleniyor. Biraz bekleyin.';
      } else if (list != null && list.length > 1 && _apartmentId == null) {
        error = 'Talebin ilgili olduğu daireyi seçin.';
      }
    }
    setState(() => _apartmentFieldError = error);
    return error == null;
  }

  bool _revealExtras() {
    final context = _apartmentKey.currentContext;
    if (_apartmentFieldError != null && context != null) {
      Scrollable.ensureVisible(context, duration: Duration.zero, alignment: 0.1);
      return true;
    }
    return false;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(
      _formKey,
      validateExtra: _validateExtras,
      revealExtra: _revealExtras,
    )) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final request = WorkCreateRequest(
      siteCode: _siteCode,
      category: _category,
      locationType: _location,
      title: _title.text,
      description: _description.text,
      apartmentId: _location == WorkLocationType.daire ? _apartmentId : null,
      urgent: _urgent,
    );
    try {
      final result = await widget.service.createItem(request);
      if (!mounted) return;
      _closing = true;
      popIfCurrent<WorkCreateResult>(context, result);
    } catch (e) {
      if (!mounted) return;
      // 429: düğme `Retry-After` süresince kilitlenir (metin sunucudan: "30 dakika sonra tekrar deneyin").
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Talep gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      // Hata sonrası odak Gönder düğmesine (klavye / ekran okuyucu kullanıcısı hatayı kaçırmasın).
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
          title: 'Talep silinsin mi?',
          icon: Icons.help_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('work_form_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Yazmaya Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('work_form_discard'),
              onPressed: () => popIfCurrent(dialogContext, true),
              child: const Text('Vazgeç ve Kapat'),
            ),
          ],
          child: Text(
            'Yazdıklarınız gönderilmedi.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }
    _closing = true;
    popIfCurrent<WorkCreateResult>(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final apartments = _apartments;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppDialog(
        title: 'Yeni Talep',
        subtitle: 'Arıza, bakım, şikayet veya öneri',
        icon: Icons.add_task_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('work_form_close'),
            onPressed: _submitting ? null : () => unawaited(_requestClose()),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('work_form_send'),
            focusNode: _sendFocus,
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'Gönderiliyor...' : 'Gönder'),
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
              if (widget.sites.length > 1) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('work_form_site_$_siteCode'),
                  isExpanded: true,
                  initialValue: _siteCode,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(
                    labelText: 'Site',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                  items: [
                    for (final site in widget.sites)
                      DropdownMenuItem<int>(
                        value: site.code,
                        child: Text(
                          site.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) _selectSite(value);
                        },
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              DropdownButtonFormField<WorkCategory>(
                key: const ValueKey<String>('work_form_category'),
                isExpanded: true,
                initialValue: _category,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(Icons.category_rounded),
                ),
                items: [
                  for (final category in WorkCategory.values)
                    DropdownMenuItem<WorkCategory>(
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
              Text('Konum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final type in WorkLocationType.values)
                    ChoiceChip(
                      key: ValueKey<String>('work_form_location_${type.apiValue}'),
                      label: Text(
                        type == WorkLocationType.daire ? 'Dairem' : 'Ortak alan',
                      ),
                      selected: _location == type,
                      onSelected: _submitting ? null : (_) => _selectLocation(type),
                    ),
                ],
              ),
              if (_location == WorkLocationType.daire) ...[
                const SizedBox(height: AppSpace.md),
                KeyedSubtree(
                  key: _apartmentKey,
                  child: _apartmentSection(context, apartments),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('work_form_title'),
                controller: _title,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kWorkTitleMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => workCounter(
                      context,
                      _title.text.runes.length,
                      kWorkTitleMax,
                    ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  hintText: 'Örn. B blok asansörü çalışmıyor',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (length < 1) return 'Başlık boş olamaz.';
                  if (length > kWorkTitleMax) {
                    return 'Başlık en çok $kWorkTitleMax karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('work_form_description'),
                controller: _description,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 8,
                maxLength: kWorkDescriptionMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => workCounter(
                      context,
                      _description.text.runes.length,
                      kWorkDescriptionMax,
                    ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Sorunu ve ne zamandır sürdüğünü yazın',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (length < 1) return 'Açıklama boş olamaz.';
                  if (length > kWorkDescriptionMax) {
                    return 'Açıklama en çok $kWorkDescriptionMax karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.sm),
              SwitchListTile(
                key: const ValueKey<String>('work_form_urgent'),
                contentPadding: EdgeInsets.zero,
                value: _urgent,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _urgent = value),
                title: const Text('Acil durum'),
                subtitle: const Text(
                  'Güvenlik riski ya da bekleyemeyecek bir arıza varsa işaretleyin.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apartmentSection(
    BuildContext context,
    List<WorkApartmentChoice>? apartments,
  ) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    if (_apartmentsLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daireleriniz yükleniyor...', style: th.bodyMedium),
          if (_apartmentFieldError != null)
            Text(
              _apartmentFieldError!,
              style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p)),
            ),
        ],
      );
    }
    if (_apartmentsError != null) {
      return InlineNotice(
        key: const ValueKey<String>('work_form_apartments_error'),
        message: _apartmentsError!,
        onRetry: _loadApartments,
      );
    }
    if (apartments == null) return const SizedBox.shrink();
    if (apartments.isEmpty) {
      return const InlineNotice(
        key: ValueKey<String>('work_form_apartments_empty'),
        tone: AppTone.info,
        message:
            'Bu sitede kayıtlı daireniz görünmüyor; talep "Daire" konumuyla, daire belirtilmeden gönderilir.',
      );
    }
    if (apartments.length == 1) {
      return Text(
        'Daire: ${apartments.first.label}',
        key: const ValueKey<String>('work_form_apartment_single'),
        style: th.bodyMedium,
      );
    }
    return DropdownButtonFormField<int>(
      key: ValueKey<String>('work_form_apartment_${_apartmentId ?? 0}'),
      isExpanded: true,
      initialValue: _apartmentId,
      dropdownColor: p.surface,
      style: th.bodyMedium?.copyWith(color: p.text),
      decoration: InputDecoration(
        labelText: 'Daire',
        prefixIcon: const Icon(Icons.door_front_door_rounded),
        errorText: _apartmentFieldError,
      ),
      items: [
        for (final apartment in apartments)
          DropdownMenuItem<int>(
            value: apartment.id,
            child: Text(
              apartment.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _submitting
          ? null
          : (value) => setState(() {
              _apartmentId = value;
              _apartmentFieldError = null;
            }),
    );
  }
}
