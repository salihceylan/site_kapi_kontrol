// Yeni talep formu (docs/PLATFORM_IS_TAKIBI.md `POST /app/work-items`): kategori, konum, başlık, açıklama, "acil"
// işareti ve en çok 4 fotoğraf (JPEG / PNG / WebP, her biri 5 MB).
//
// Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Aynı veriyle
// yeniden gönderimde servis AYNI `idempotency_key`i kullanır (yanıtı kaybolan istek çift talep açmaz); veri
// değişince anahtar yenilenir. Hata pencerenin içinde kalır, metinler korunur (odak "Gönder"e döner); 429'da düğme
// `Retry-After` süresince kilitlenir. Doldurulmuş form yanlışlıkla kapanırsa onay istenir.
//
// Fotoğraflar talep AÇILDIKTAN SONRA sırayla yüklenir (ilerleme + Vazgeç). Talep açıldıysa form bir daha
// gönderilmez; yüklenemeyen fotoğraf DÜRÜSTÇE bildirilir ("Talep oluşturuldu, 1 fotoğraf yüklenemedi"), yeniden
// denenebilir ve pencere sonuçla kapanır (liste yine de yenilenir).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_attachment_upload.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

class WorkItemFormDialog extends StatefulWidget {
  const WorkItemFormDialog({
    super.key,
    required this.service,
    required this.sites,
    this.initialSiteCode,
    this.picker = const FilePickerWorkPhotoPicker(),
  });

  final WorkTrackingService service;

  /// Talep açılabilecek (modül açık) siteler; en az bir tane.
  final List<PeopleSite> sites;
  final int? initialSiteCode;

  /// Fotoğraf seçici (testlerde sahte).
  final WorkPhotoPicker picker;

  /// Başarıda sunucunun döndürdüğü kayıtla (ve fotoğraf sonucuyla) kapanır; vazgeçilirse null.
  static Future<WorkCreateResult?> show(
    BuildContext context, {
    required WorkTrackingService service,
    required List<PeopleSite> sites,
    int? initialSiteCode,
    WorkPhotoPicker picker = const FilePickerWorkPhotoPicker(),
  }) {
    return showDialog<WorkCreateResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkItemFormDialog(
        service: service,
        sites: sites,
        initialSiteCode: initialSiteCode,
        picker: picker,
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

  final List<WorkPhotoPick> _photos = <WorkPhotoPick>[];
  String? _photoError;
  bool _picking = false;
  bool _pickedAny = false;

  /// Seçilen fotoğrafların önizlemeleri: form kapanınca / fotoğraf kaldırılınca ImageCache'ten çıkarılır.
  final WorkImageProviders _previewImages = WorkImageProviders();

  /// Talep AÇILDI: form bir daha gönderilmez; fotoğraflar bu talebe yüklenir.
  WorkCreateResult? _created;
  WorkAttachmentUploadController? _upload;

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
    _upload?.removeListener(_onUploadChanged);
    _upload?.dispose();
    if (_pickedAny) unawaited(widget.picker.release());
    _previewImages.dispose();
    _retry.dispose();
    _sendFocus.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _photos.isNotEmpty;

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

  // --- Fotoğraflar ---

  Future<void> _pickPhotos() async {
    if (_submitting || _picking) return;
    final remaining = kWorkAttachmentMax - _photos.length;
    if (remaining <= 0) return;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    WorkPhotoSelection selection;
    try {
      selection = await widget.picker.pick(maxCount: remaining);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _photoError = 'Fotoğraf seçilemedi. Tekrar deneyin.';
      });
      return;
    }
    if (!mounted) return;
    _pickedAny = true;
    // Geçersiz seçimler yer doldurmaz; her biri nedeniyle ayrı satırda bildirilir.
    final split = workSplitSelection(selection, remaining: remaining);
    setState(() {
      _picking = false;
      _photos.addAll(split.valid);
      _photoError = split.notes.isEmpty ? null : split.notes.join('\n');
    });
  }

  void _removePhoto(int index) {
    if (_submitting || index < 0 || index >= _photos.length) return;
    final removed = _photos[index];
    setState(() {
      _photos.removeAt(index);
      _photoError = null;
    });
    _previewImages.evictBytes(removed.bytes);
  }

  void _onUploadChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked || _created != null) return;
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
    final WorkCreateResult result;
    try {
      result = await widget.service.createItem(request);
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
      return;
    }
    if (!mounted) return;
    final photos = List<WorkPhotoPick>.of(_photos);
    if (photos.isEmpty) {
      _closing = true;
      popIfCurrent<WorkCreateResult>(context, result);
      return;
    }
    // Talep açıldı: form artık gönderilmez; fotoğraflar sırayla yüklenir.
    _created = result;
    final upload = WorkAttachmentUploadController(
      service: widget.service,
      workItemId: result.item.id,
    )..addListener(_onUploadChanged);
    setState(() {
      _upload = upload;
      _submitting = false;
    });
    await upload.run(photos);
    if (!mounted) return;
    _afterUpload();
  }

  void _afterUpload() {
    final upload = _upload;
    if (upload == null) return;
    if (upload.failedCount == 0) {
      _finish();
      return;
    }
    final error = upload.lastException;
    if (error != null) {
      _retry.lockIfRateLimited(error, () {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  Future<void> _retryUpload() async {
    final upload = _upload;
    if (upload == null || upload.busy || _retry.locked) return;
    await upload.retryFailed();
    if (!mounted) return;
    _afterUpload();
  }

  /// Fotoğraf aşaması bitti: içeriği kesin gitmemiş yarım kayıtlar silinir (talep başına 4 sınırını doldurmasın)
  /// ve pencere talep + fotoğraf sonucuyla kapanır.
  void _finish() {
    final created = _created;
    final upload = _upload;
    if (created == null || upload == null || upload.busy || _closing) return;
    _closing = true;
    unawaited(upload.discardPending());
    popIfCurrent<WorkCreateResult>(
      context,
      created.withPhotoOutcome(
        uploaded: upload.uploadedCount,
        failed: upload.failedCount,
        cancelled: upload.phase == WorkUploadPhase.cancelled,
      ),
    );
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    final upload = _upload;
    if (upload != null) {
      // Talep zaten açıldı: yükleme sürerken kapanmaz; bitince sonuçla kapanır.
      if (!upload.busy) _finish();
      return;
    }
    if (_submitting) return;
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
    final upload = _upload;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: upload == null
          ? AppDialog(
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
                  onPressed: (_submitting || _retry.locked || _picking) ? null : _submit,
                  child: Text(_submitting ? 'Gönderiliyor...' : 'Gönder'),
                ),
              ],
              child: _buildForm(context),
            )
          : AppDialog(
              title: upload.busy ? 'Fotoğraflar Yükleniyor' : 'Fotoğraf Yükleme Sonucu',
              subtitle: 'Talebiniz kaydedildi',
              icon: Icons.photo_library_outlined,
              actions: upload.busy
                  ? [
                      TextButton(
                        key: const ValueKey<String>('work_form_upload_cancel'),
                        onPressed: upload.cancel,
                        child: const Text('Vazgeç'),
                      ),
                    ]
                  : [
                      TextButton(
                        key: const ValueKey<String>('work_form_upload_close'),
                        onPressed: _finish,
                        child: const Text('Kapat'),
                      ),
                      if (upload.canRetry)
                        ElevatedButton(
                          key: const ValueKey<String>('work_form_upload_retry'),
                          onPressed: _retry.locked ? null : () => unawaited(_retryUpload()),
                          child: const Text('Tekrar Dene'),
                        ),
                    ],
              child: _buildUploadStage(context, upload),
            ),
    );
  }

  Widget _buildUploadStage(BuildContext context, WorkAttachmentUploadController upload) {
    final failed = upload.failedCount;
    final cancelled = upload.phase == WorkUploadPhase.cancelled;
    final InlineNotice notice;
    if (upload.busy) {
      notice = const InlineNotice(
        key: ValueKey<String>('work_form_upload_notice'),
        tone: AppTone.success,
        icon: Icons.check_circle_outline_rounded,
        message: 'Talebiniz kaydedildi. Fotoğraflar talebe ekleniyor...',
      );
    } else if (failed == 0) {
      notice = const InlineNotice(
        key: ValueKey<String>('work_form_upload_notice'),
        tone: AppTone.success,
        icon: Icons.check_circle_outline_rounded,
        message: 'Talebiniz kaydedildi ve fotoğraflar eklendi.',
      );
    } else {
      notice = InlineNotice(
        key: const ValueKey<String>('work_form_upload_notice'),
        tone: AppTone.warning,
        message: cancelled
            ? 'Talebiniz kaydedildi; fotoğraf yükleme iptal edildi, $failed fotoğraf eklenmedi.'
            : 'Talebiniz kaydedildi; $failed fotoğraf yüklenemedi. Talep ayrıntısından yeniden ekleyebilirsiniz.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        notice,
        const SizedBox(height: AppSpace.md),
        if (upload.busy) ...[
          WorkUploadProgress(controller: upload, keyPrefix: 'work_form_upload'),
          const SizedBox(height: AppSpace.md),
        ],
        _PhotoOutcomeList(photos: _photos, upload: upload),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final apartments = _apartments;
    final photoFull = _photos.length >= kWorkAttachmentMax;
    return Form(
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
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Fotoğraf (isteğe bağlı)', style: th.titleSmall),
              Text(
                '${_photos.length}/$kWorkAttachmentMax',
                key: const ValueKey<String>('work_form_photo_count'),
                style: th.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Sorunu gösteren en fazla $kWorkAttachmentMax fotoğraf ekleyebilirsiniz; JPEG, PNG veya WebP, her biri en fazla 5 MB. '
            'Fotoğraflar talep gönderildikten sonra yüklenir.',
            style: th.bodySmall,
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            WorkPickedPhotoList(
              photos: _photos,
              onRemove: _removePhoto,
              images: _previewImages,
              enabled: !_submitting,
            ),
          ],
          if (_photoError != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(
              key: const ValueKey<String>('work_form_photo_error'),
              message: _photoError!,
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('work_form_photo_add'),
            label: photoFull ? 'Fotoğraf sınırına ulaşıldı' : 'Fotoğraf Ekle',
            icon: Icons.add_a_photo_outlined,
            variant: AppButtonVariant.tonal,
            onPressed: (_submitting || _picking || photoFull)
                ? null
                : () => unawaited(_pickPhotos()),
          ),
        ],
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

/// Yükleme aşamasında fotoğraf başına durum satırı: yüklendi / yüklenemedi (neden) / sırada / yükleniyor.
class _PhotoOutcomeList extends StatelessWidget {
  const _PhotoOutcomeList({required this.photos, required this.upload});

  final List<WorkPhotoPick> photos;
  final WorkAttachmentUploadController upload;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < photos.length; i++)
          Builder(
            builder: (context) {
              final photo = photos[i];
              // Fotoğrafın EN SON sonucu (turlar arası; kimlik eşlemesi): yeniden denemede de durum doğru kalır.
              final result = upload.resultFor(photo);
              final IconData icon;
              final AppTone tone;
              final String status;
              if (upload.isQueued(photo)) {
                final inFlight = identical(upload.current, photo);
                icon = inFlight ? Icons.cloud_upload_outlined : Icons.schedule_rounded;
                tone = inFlight ? AppTone.primary : AppTone.neutral;
                status = inFlight ? 'Yükleniyor...' : 'Sırada';
              } else if (result == null) {
                icon = Icons.schedule_rounded;
                tone = AppTone.neutral;
                status = 'Yüklenmedi';
              } else if (result.ok) {
                icon = Icons.check_circle_outline_rounded;
                tone = AppTone.success;
                status = 'Yüklendi';
              } else {
                icon = result.cancelled
                    ? Icons.stop_circle_outlined
                    : Icons.error_outline_rounded;
                tone = result.cancelled ? AppTone.neutral : AppTone.danger;
                status = result.error ?? 'Yüklenemedi';
              }
              return Padding(
                padding: EdgeInsets.only(bottom: i == photos.length - 1 ? 0 : AppSpace.sm),
                child: Semantics(
                  container: true,
                  label: '${photo.name}: $status',
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: tone.ink(p)),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                photo.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: th.bodyMedium?.copyWith(color: p.text),
                              ),
                              Text(
                                status,
                                style: th.bodySmall?.copyWith(color: tone.ink(p)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
