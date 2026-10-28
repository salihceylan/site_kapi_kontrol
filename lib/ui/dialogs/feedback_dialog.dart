// Sayfa bağlamlı "Geri bildirim" formu (docs/PLATFORM_GERI_BILDIRIM.md, karar K11): her ekrandan açılır; ekran adı ve rota formda OTOMATİK eklenir
// (kullanıcı değiştiremez, yalnız görür). Metin + en çok 4 dosya (JPEG / PNG / WebP; dosya başı 5 MB, toplam 20 MB).
//
// Dosyalar seçilirken iş takibindeki fotoğraf hazırlığından geçer ([WorkPhotoPicker]): uzun kenar en çok 2560 piksele küçültülür, JPEG olarak yeniden
// kodlanır, EXIF (GPS konumu dahil) silinir. Sınırlar istemcide de denetlenir; sunucu aynılarını 400 ile doğrular.
//
// Gönderim iki adımlıdır: önce kayıt (metin + bağlam + ek üstverisi), sonra her dosya sırayla yüklenir. Kayıt yapıldıktan sonra form bir daha gönderilmez
// (çift kayıt olmaz); yüklenemeyen dosya DÜRÜSTÇE bildirilir ("Geri bildiriminiz alındı, 1 dosya yüklenemedi"), yeniden denenebilir ve pencere sonuçla kapanır.
// Gönderim sürerken geri tuşu pencereyi kapatmaz; doldurulmuş form yanlışlıkla kapanırsa onay istenir. Metin ve dosya adı günlüğe yazılmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/document_models.dart' show formatDocumentSize;
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart' show workCounter;

/// Bir ekin yükleme durumu.
enum _PhotoPhase { queued, uploading, done, failed }

class _PhotoState {
  _PhotoState(this.phase, [this.error]);

  final _PhotoPhase phase;
  final String? error;
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    super.key,
    required this.service,
    required this.screenContext,
    this.appVersion,
    this.platform,
    this.picker = const FilePickerWorkPhotoPicker(),
  });

  final FeedbackService service;

  /// Otomatik eklenen ekran bağlamı (ekran adı + rota + site).
  final FeedbackScreenContext screenContext;
  final String? appVersion;
  final String? platform;

  /// Fotoğraf seçici (testlerde sahte).
  final WorkPhotoPicker picker;

  /// Gönderilirse sonuçla (kayıt + yüklenen / yüklenemeyen dosya sayısı) kapanır; vazgeçilirse null.
  static Future<FeedbackSendOutcome?> show(
    BuildContext context, {
    required FeedbackService service,
    required FeedbackScreenContext screenContext,
    String? appVersion,
    String? platform,
    WorkPhotoPicker picker = const FilePickerWorkPhotoPicker(),
  }) {
    return showDialog<FeedbackSendOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FeedbackDialog(
        service: service,
        screenContext: screenContext,
        appVersion: appVersion,
        platform: platform,
        picker: picker,
      ),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'feedback_send');
  final RetryLock _retry = RetryLock();
  final TextEditingController _message = TextEditingController();

  final List<WorkPhotoPick> _photos = <WorkPhotoPick>[];
  String? _photoError;
  bool _picking = false;
  bool _preparing = false;
  bool _pickedAny = false;
  final WorkImageProviders _previewImages = WorkImageProviders();

  bool _submitting = false;
  bool _closing = false;
  String? _error;

  /// Kayıt AÇILDI: form bir daha gönderilmez; dosyalar bu kayda yüklenir.
  FeedbackRecord? _record;
  final Map<WorkPhotoPick, _PhotoState> _states = Map<WorkPhotoPick, _PhotoState>.identity();
  bool _uploading = false;
  bool _cancelUpload = false;

  @override
  void dispose() {
    if (_pickedAny) unawaited(widget.picker.release());
    _previewImages.dispose();
    _retry.dispose();
    _sendFocus.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _dirty => _message.text.trim().isNotEmpty || _photos.isNotEmpty;

  int get _totalBytes => FeedbackRules.totalBytes(_photos.map((p) => p.size));

  // --- Dosyalar ---

  Future<void> _pickPhotos() async {
    if (_submitting || _picking || _record != null) return;
    final remaining = kFeedbackAttachmentMax - _photos.length;
    if (remaining <= 0) return;
    // Seçici kopyaları (Android önbelleği) seçim sürerken pencere kapansa da silinsin: bayrak beklemeden ÖNCE.
    _pickedAny = true;
    final picker = widget.picker;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    WorkPhotoSelection selection;
    try {
      selection = await picker.pick(
        maxCount: remaining,
        onPreparing: () {
          if (mounted) setState(() => _preparing = true);
        },
      );
    } catch (_) {
      if (!mounted) {
        unawaited(picker.release());
        return;
      }
      setState(() {
        _picking = false;
        _preparing = false;
        _photoError = 'Dosya seçilemedi. Tekrar deneyin.';
      });
      return;
    }
    if (!mounted) {
      unawaited(picker.release());
      return;
    }
    // Geçersiz seçimler yer doldurmaz; her biri nedeniyle ayrı satırda bildirilir. Toplam 20 MB sınırı seçimde de uygulanır.
    final split = workSplitSelection(selection, remaining: remaining);
    final notes = <String>[...split.notes];
    final accepted = <WorkPhotoPick>[];
    final sizes = _photos.map((p) => p.size).toList();
    for (final pick in split.valid) {
      final problem = FeedbackRules.checkAddition(existingSizes: sizes, candidate: pick.size);
      if (problem != null) {
        notes.add('${pick.name}: $problem');
        continue;
      }
      accepted.add(pick);
      sizes.add(pick.size);
    }
    setState(() {
      _picking = false;
      _preparing = false;
      _photos.addAll(accepted);
      _photoError = notes.isEmpty ? null : notes.join('\n');
    });
  }

  void _removePhoto(int index) {
    if (_submitting || _record != null || index < 0 || index >= _photos.length) return;
    final removed = _photos[index];
    setState(() {
      _photos.removeAt(index);
      _photoError = null;
    });
    _previewImages.evictBytes(removed.bytes);
  }

  // --- Gönderim ---

  Future<void> _submit() async {
    if (_submitting || _retry.locked || _record != null) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final request = FeedbackCreateRequest(
      message: _message.text.trim(),
      context: widget.screenContext,
      appVersion: widget.appVersion,
      platform: widget.platform,
      attachments: <FeedbackAttachmentSpec>[
        for (final photo in _photos)
          FeedbackAttachmentSpec(
            fileName: photo.name,
            mimeType: photo.mimeType,
            sizeBytes: photo.size,
          ),
      ],
    );
    final FeedbackRecord record;
    try {
      record = await widget.service.send(request);
    } catch (e) {
      if (!mounted) return;
      // 429: düğme `Retry-After` süresince kilitlenir (metin sunucudan).
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Geri bildirim gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendFocus.requestFocus();
      });
      return;
    }
    if (!mounted) return;
    if (_photos.isEmpty) {
      _closing = true;
      popIfCurrent<FeedbackSendOutcome>(context, FeedbackSendOutcome(record: record));
      return;
    }
    // Kayıt açıldı: form artık gönderilmez; dosyalar sırayla yüklenir.
    setState(() {
      _record = record;
      _submitting = false;
      for (final photo in _photos) {
        _states[photo] = _PhotoState(_PhotoPhase.queued);
      }
    });
    await _uploadAll();
  }

  /// Yüklenmemiş dosyaları sırayla yükler. Sonraki dosyaların da kesin reddedileceği hatalarda (oturum, yetki, hız sınırı) kalanlar DENENMEZ.
  Future<void> _uploadAll() async {
    final record = _record;
    if (record == null || _uploading) return;
    setState(() {
      _uploading = true;
      _cancelUpload = false;
    });
    String? fatal;
    for (var i = 0; i < _photos.length; i++) {
      final photo = _photos[i];
      if (_states[photo]?.phase == _PhotoPhase.done) continue;
      if (!mounted) return;
      if (_cancelUpload) {
        setState(() => _states[photo] = _PhotoState(_PhotoPhase.failed, 'Yükleme iptal edildi.'));
        continue;
      }
      if (fatal != null) {
        setState(() => _states[photo] = _PhotoState(_PhotoPhase.failed, fatal));
        continue;
      }
      if (i >= record.attachments.length) {
        setState(() => _states[photo] = _PhotoState(_PhotoPhase.failed, 'Dosya kaydı açılamadı.'));
        continue;
      }
      setState(() => _states[photo] = _PhotoState(_PhotoPhase.uploading));
      try {
        await widget.service.upload(
          feedbackId: record.id,
          attachmentId: record.attachments[i].id,
          bytes: photo.bytes,
        );
        if (!mounted) return;
        setState(() => _states[photo] = _PhotoState(_PhotoPhase.done));
      } catch (e) {
        if (!mounted) return;
        if (e is ApiException && e.code == 'UPLOAD_ALREADY_COMPLETED') {
          // Önceki deneme sunucuda tamamlanmıştı (yanıtı kaybolmuştu): başarı.
          setState(() => _states[photo] = _PhotoState(_PhotoPhase.done));
          continue;
        }
        final message = crmMessageOf(e, 'Dosya yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        _retry.lockIfRateLimited(e, () {
          if (mounted) setState(() {});
        });
        setState(() => _states[photo] = _PhotoState(_PhotoPhase.failed, message));
        if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 429 || e.code == 'ACCOUNT_DELETED')) {
          fatal = message;
        }
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (_failedCount == 0) _finish();
  }

  int get _failedCount => _photos.where((p) => _states[p]?.phase != _PhotoPhase.done).length;

  /// Dosya aşaması bitti (hepsi yüklendi ya da kullanıcı sonucu görüp kapattı): kayıt + sonuç sayılarıyla kapanır.
  void _finish() {
    final record = _record;
    if (record == null || _uploading || _closing) return;
    _closing = true;
    popIfCurrent<FeedbackSendOutcome>(
      context,
      FeedbackSendOutcome(record: record, uploaded: _photos.length - _failedCount, failed: _failedCount),
    );
  }

  Future<void> _retryUpload() async {
    if (_uploading || _retry.locked) return;
    await _uploadAll();
  }

  Future<void> _requestClose() async {
    if (_closing || _picking) return;
    if (_record != null) {
      // Kayıt zaten açıldı: yükleme sürerken kapanmaz; bitince sonuçla kapanır.
      if (!_uploading) _finish();
      return;
    }
    if (_submitting) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Geri bildirim silinsin mi?',
          icon: Icons.help_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('feedback_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Yazmaya Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('feedback_discard'),
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
    popIfCurrent<FeedbackSendOutcome>(context);
  }

  // --- Görünüm ---

  @override
  Widget build(BuildContext context) {
    final record = _record;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: record == null
          ? AppDialog(
              title: 'Geri Bildirim',
              subtitle: 'Görüş, öneri ya da sorununuzu iletin',
              icon: Icons.rate_review_outlined,
              actions: [
                TextButton(
                  key: const ValueKey<String>('feedback_close'),
                  onPressed: (_submitting || _picking) ? null : () => unawaited(_requestClose()),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  key: const ValueKey<String>('feedback_send'),
                  focusNode: _sendFocus,
                  onPressed: (_submitting || _retry.locked || _picking) ? null : _submit,
                  child: Text(_submitting ? 'Gönderiliyor...' : 'Gönder'),
                ),
              ],
              child: _buildForm(context),
            )
          : AppDialog(
              title: _uploading ? 'Dosyalar Yükleniyor' : 'Dosya Yükleme Sonucu',
              subtitle: 'Geri bildiriminiz alındı',
              icon: Icons.photo_library_outlined,
              actions: _uploading
                  ? [
                      TextButton(
                        key: const ValueKey<String>('feedback_upload_cancel'),
                        onPressed: () => setState(() => _cancelUpload = true),
                        child: const Text('Vazgeç'),
                      ),
                    ]
                  : [
                      TextButton(
                        key: const ValueKey<String>('feedback_upload_close'),
                        onPressed: _finish,
                        child: const Text('Kapat'),
                      ),
                      if (_failedCount > 0)
                        ElevatedButton(
                          key: const ValueKey<String>('feedback_upload_retry'),
                          onPressed: _retry.locked ? null : () => unawaited(_retryUpload()),
                          child: const Text('Tekrar Dene'),
                        ),
                    ],
              child: _buildUploadStage(context),
            ),
    );
  }

  Widget _buildUploadStage(BuildContext context) {
    final failed = _failedCount;
    final InlineNotice notice;
    if (_uploading) {
      notice = const InlineNotice(
        key: ValueKey<String>('feedback_upload_notice'),
        tone: AppTone.success,
        icon: Icons.check_circle_outline_rounded,
        message: 'Geri bildiriminiz alındı. Dosyalar ekleniyor...',
      );
    } else if (failed == 0) {
      notice = const InlineNotice(
        key: ValueKey<String>('feedback_upload_notice'),
        tone: AppTone.success,
        icon: Icons.check_circle_outline_rounded,
        message: 'Geri bildiriminiz alındı ve dosyalar eklendi.',
      );
    } else {
      notice = InlineNotice(
        key: const ValueKey<String>('feedback_upload_notice'),
        tone: AppTone.warning,
        message: 'Geri bildiriminiz alındı; $failed dosya yüklenemedi. Tekrar deneyebilir ya da dosyasız kapatabilirsiniz.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        notice,
        const SizedBox(height: AppSpace.md),
        for (var i = 0; i < _photos.length; i++)
          _PhotoStatusRow(
            photo: _photos[i],
            state: _states[_photos[i]] ?? _PhotoState(_PhotoPhase.queued),
            last: i == _photos.length - 1,
          ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final photoFull = _photos.length >= kFeedbackAttachmentMax;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) CrmFormError(message: _error!, announce: true),
          _ScreenContextCard(screen: widget.screenContext),
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('feedback_audience_note'),
            tone: AppTone.info,
            message: kFeedbackAudienceNote,
          ),
          const SizedBox(height: AppSpace.lg),
          TextFormField(
            key: const ValueKey<String>('feedback_message'),
            controller: _message,
            enabled: !_submitting,
            minLines: 4,
            maxLines: 10,
            maxLength: kFeedbackMessageMax,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                workCounter(context, _message.text.runes.length, kFeedbackMessageMax),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Geri bildiriminiz',
              hintText: 'Ne gördünüz, neyi beğendiniz ya da neyi değiştirmek istersiniz?',
              alignLabelWithHint: true,
            ),
            validator: FeedbackRules.checkMessage,
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Ekran görüntüsü / fotoğraf (isteğe bağlı)', style: th.titleSmall),
              Text(
                '${_photos.length}/$kFeedbackAttachmentMax',
                key: const ValueKey<String>('feedback_photo_count'),
                style: th.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'En fazla $kFeedbackAttachmentMax dosya; her biri en çok 5 MB, toplam en çok 20 MB (JPEG, PNG veya WebP). '
            '$kWorkPhotoPrepareHint',
            key: const ValueKey<String>('feedback_photo_hint'),
            style: th.bodySmall,
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            WorkPickedPhotoList(
              photos: _photos,
              onRemove: _removePhoto,
              images: _previewImages,
              enabled: !_submitting,
              keyPrefix: 'feedback_photo',
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Toplam ${formatDocumentSize(_totalBytes)} / 20 MB',
              key: const ValueKey<String>('feedback_photo_total'),
              style: th.bodySmall,
            ),
          ],
          if (_preparing) ...[
            const SizedBox(height: AppSpace.sm),
            const WorkPhotoPreparing(keyPrefix: 'feedback_photo'),
          ],
          if (_photoError != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(
              key: const ValueKey<String>('feedback_photo_error'),
              message: _photoError!,
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('feedback_photo_add'),
            label: photoFull ? 'Dosya sınırına ulaşıldı' : 'Dosya Ekle',
            icon: Icons.add_a_photo_outlined,
            variant: AppButtonVariant.tonal,
            onPressed: (_submitting || _picking || photoFull) ? null : () => unawaited(_pickPhotos()),
          ),
        ],
      ),
    );
  }
}

/// Otomatik eklenen ekran bağlamı: kullanıcı değiştiremez, yalnız görür.
class _ScreenContextCard extends StatelessWidget {
  const _ScreenContextCard({required this.screen});

  final FeedbackScreenContext screen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final siteName = screen.siteName;
    final label =
        'Geri bildirim şu ekranla birlikte gönderilir: ${screen.screenName}'
        '${siteName == null ? '' : '; site: $siteName'}';
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: const ValueKey<String>('feedback_context'),
          decoration: BoxDecoration(
            color: p.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: p.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.screenshot_monitor_rounded, size: 20, color: p.textSecondary),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gönderildiği ekran (otomatik eklenir)', style: th.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        screen.screenName,
                        key: const ValueKey<String>('feedback_context_name'),
                        style: th.titleSmall?.copyWith(color: p.text),
                      ),
                      Text(
                        screen.screenRoute,
                        key: const ValueKey<String>('feedback_context_route'),
                        style: th.bodySmall,
                      ),
                      if (siteName != null)
                        Text(
                          'Site: $siteName',
                          key: const ValueKey<String>('feedback_context_site'),
                          style: th.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yükleme aşamasında dosya başına durum satırı: yüklendi / yüklenemedi (neden) / sırada / yükleniyor.
class _PhotoStatusRow extends StatelessWidget {
  const _PhotoStatusRow({required this.photo, required this.state, required this.last});

  final WorkPhotoPick photo;
  final _PhotoState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final IconData icon;
    final AppTone tone;
    final String status;
    switch (state.phase) {
      case _PhotoPhase.queued:
        icon = Icons.schedule_rounded;
        tone = AppTone.neutral;
        status = 'Sırada';
      case _PhotoPhase.uploading:
        icon = Icons.cloud_upload_outlined;
        tone = AppTone.primary;
        status = 'Yükleniyor...';
      case _PhotoPhase.done:
        icon = Icons.check_circle_outline_rounded;
        tone = AppTone.success;
        status = 'Yüklendi';
      case _PhotoPhase.failed:
        icon = Icons.error_outline_rounded;
        tone = AppTone.danger;
        status = state.error ?? 'Yüklenemedi';
    }
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpace.sm),
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
                    Text(status, style: th.bodySmall?.copyWith(color: tone.ink(p))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
