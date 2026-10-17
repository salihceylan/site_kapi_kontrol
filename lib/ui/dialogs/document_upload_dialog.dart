// "Belge Yükle" ve "Yeni Sürüm Yükle" penceresi (docs/PLATFORM_BELGELER.md A3, A11, A13).
//
// Akış: dosya seç -> başlık / kategori / açıklama / KİTLE (varsayılan seçili DEĞİL) / hedef -> KVKK uyarısı ->
// Yükle -> ilerleme çubuğu + Vazgeç -> sonuç. Hata pencerenin içinde Türkçe ileti + "Tekrar Dene" olarak kalır
// (odak oraya taşınır); form değerleri korunur.
//
// - Ön doğrulama (uzantı / boş / kota / öğrenilmiş boyut sınırı) yalnız uyarır; SUNUCU esastır.
// - Çift gönderim: düğme yükleme sürerken kapalıdır; `idempotency_key` ile aynı form çift belge yaratmaz.
// - Yükleme sürerken geri tuşu / dışarı dokunma pencereyi kapatmaz (uyarı çıkar); "Vazgeç" bağlantıyı keser.
// - Doldurulmuş form yanlışlıkla kapanırsa kaybolmasın: kapatmadan önce onay istenir.
// - Dosya belleğe okunmaz: seçici diskten akış verir, HTTP katmanı soket hızında çeker.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/services/document_upload.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_form_fields.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_target_section.dart';

/// KVKK bilgilendirmesi (sözleşme A11; yükleme formunda ZORUNLU gösterilir).
const String kDocumentPrivacyNotice =
    'Belgede kişisel veri (T.C. kimlik no, IBAN, telefon, adres) varsa yalnız ilgili kitleye açın; '
    'gereksiz veriyi karartın.';

/// "n/120" sayacı: sınır aşılınca kırmızı + kalın; ekran okuyucu aşımı söyler.
Widget documentCounter(BuildContext context, int length, int max) {
  final p = context.palette;
  final over = length > max;
  return Semantics(
    liveRegion: over,
    label: over
        ? '$length karakter; en çok $max olabilir, sınır aşıldı'
        : '$length / $max karakter',
    child: ExcludeSemantics(
      child: Text(
        '$length/$max',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: over ? AppTone.danger.ink(p) : p.textSecondary,
          fontWeight: over ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
  );
}

class DocumentUploadDialog extends StatefulWidget {
  const DocumentUploadDialog({
    super.key,
    required this.scope,
    required this.service,
    this.picker = const FilePickerDocumentPicker(),
    this.usage,
    this.versionOf,
    this.onRefreshNeeded,
    this.initialSource,
  });

  final PeopleScope scope;
  final DocumentService service;
  final DocumentPicker picker;

  /// Liste yanıtındaki kota kullanımı (kalan alan ön doğrulamasında); bilinmiyorsa null.
  final DocumentUsage? usage;

  /// Dolu ise bu belgeye YENİ SÜRÜM yüklenir (başlık / kitle değişmez); null ise yeni belge.
  final DocumentSummary? versionOf;

  /// Sonuç belirsiz kaldığında (zaman aşımı, 5xx) çağrılır: belge oluşmuş olabilir, liste tazelensin.
  final VoidCallback? onRefreshNeeded;

  /// Önceden seçilmiş dosya (testler ve paylaşım girişi).
  final DocumentUploadSource? initialSource;

  static Future<DocumentSummary?> show(
    BuildContext context, {
    required PeopleScope scope,
    required DocumentService service,
    DocumentPicker picker = const FilePickerDocumentPicker(),
    DocumentUsage? usage,
    DocumentSummary? versionOf,
    VoidCallback? onRefreshNeeded,
    DocumentUploadSource? initialSource,
  }) {
    return showDialog<DocumentSummary>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentUploadDialog(
        scope: scope,
        service: service,
        picker: picker,
        usage: usage,
        versionOf: versionOf,
        onRefreshNeeded: onRefreshNeeded,
        initialSource: initialSource,
      ),
    );
  }

  @override
  State<DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<DocumentUploadDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _fileKey = GlobalKey();
  final GlobalKey _audienceKey = GlobalKey();
  final GlobalKey _targetKey = GlobalKey();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final FocusNode _submitFocus = FocusNode(
    debugLabel: 'document_upload_submit',
  );
  final RetryLock _retry = RetryLock();
  late final DocumentUploadController _upload = DocumentUploadController(
    service: widget.service,
    siteCode: widget.scope.siteCode,
    documentId: widget.versionOf?.id,
  )..addListener(_onUploadChanged);
  late final IdempotencyKeys _keys = sessionIdempotencyKeys(
    widget.service.authService,
    'doc',
  );

  DocumentUploadSource? _source;
  DocumentCategory _category = DocumentCategory.other;
  DocumentAudience? _audience;
  DocumentTargetSelection _target = const DocumentTargetSelection();
  String? _fileError;
  String? _fileWarning;
  String? _audienceError;
  String? _targetError;
  String? _error;
  bool _picking = false;
  bool _cancelling = false;
  bool _closing = false;
  DocumentUploadPhase _lastPhase = DocumentUploadPhase.idle;
  String? _lastSignature;

  bool get _isVersion => widget.versionOf != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSource;
    if (initial != null) _applySource(initial);
    final version = widget.versionOf;
    if (version != null) {
      _category = version.category;
    }
  }

  /// Seçilen dosyaların eklenti önbelleğindeki kopyaları (file_picker) bir kez silinir: yükleme bitince ve pencere
  /// kapanırken. Yükleme sürerken / yeniden denenebilirken ÇAĞRILMAZ (dosya hâlâ lazım).
  bool _pickerReleased = false;

  void _releasePicker() {
    if (_pickerReleased) return;
    _pickerReleased = true;
    unawaited(widget.picker.release());
  }

  @override
  void dispose() {
    _releasePicker();
    _upload
      ..removeListener(_onUploadChanged)
      ..dispose();
    _retry.dispose();
    _submitFocus.dispose();
    _title.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _source != null ||
      _title.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty ||
      _audience != null;

  // --- Yükleme durumu --------------------------------------------------------------------------

  void _onUploadChanged() {
    if (!mounted) return;
    final phase = _upload.phase;
    final previous = _lastPhase;
    _lastPhase = phase;
    if (phase != DocumentUploadPhase.preparing &&
        phase != DocumentUploadPhase.uploading &&
        phase != DocumentUploadPhase.finishing) {
      _cancelling = false;
    }
    setState(() {});
    if (phase == previous) return;
    switch (phase) {
      case DocumentUploadPhase.uploading:
        announcePolite(context, 'Yükleme başladı');
      case DocumentUploadPhase.done:
        final signature = _lastSignature;
        if (signature != null) _keys.clear(signature);
        announcePolite(context, 'Belge yüklendi');
        _releasePicker();
        _closing = true;
        popIfCurrent<DocumentSummary>(context, _upload.result);
      case DocumentUploadPhase.failed:
        _afterFailure();
      case DocumentUploadPhase.cancelled:
        announcePolite(
          context,
          _upload.cancelledLate
              ? 'Yükleme durduruldu; sunucu belgeyi kaydetmiş olabilir'
              : 'Yükleme iptal edildi',
        );
        // Geç iptal: istek sunucuda işlenmiş olabilir; liste tazelensin.
        if (_upload.outcomeUncertain) widget.onRefreshNeeded?.call();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _submitFocus.requestFocus();
        });
      case DocumentUploadPhase.idle:
      case DocumentUploadPhase.preparing:
      case DocumentUploadPhase.finishing:
        break;
    }
  }

  void _afterFailure() {
    final error = _upload.lastException;
    if (error != null) {
      _retry.lockIfRateLimited(error, () {
        if (mounted) setState(() {});
      });
    }
    if (_upload.outcomeUncertain) widget.onRefreshNeeded?.call();
    // Hata sonrası odak: yeniden-deneme düğmesine (klavye / ekran okuyucu kullanıcısı hatayı kaçırmasın).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _submitFocus.requestFocus();
    });
  }

  // --- Dosya seçimi ----------------------------------------------------------------------------

  Future<void> _pickFile() async {
    if (_picking || _upload.busy) return;
    _picking = true;
    setState(() => _fileError = null);
    DocumentUploadSource? picked;
    try {
      picked = await widget.picker.pick();
    } catch (_) {
      if (mounted) {
        setState(
          () => _fileError =
              'Dosya seçilemedi. Dosya erişim iznini kontrol edip tekrar deneyin.',
        );
      }
    } finally {
      _picking = false;
    }
    final source = picked;
    if (source == null || !mounted) return;
    setState(() => _applySource(source));
  }

  /// Seçilen dosyayı ön doğrular ve forma alır (başlık boşsa dosya adından önerilir).
  void _applySource(DocumentUploadSource source) {
    final problem = DocumentFileRules.validate(
      fileName: source.name,
      size: source.size,
      maxBytes: widget.service.learnedMaxFileBytes,
    );
    if (problem != null) {
      _fileError = problem;
      return;
    }
    _fileError = null;
    // Kota yalnız YUMUŞAK uyarıdır (kullanım bayat olabilir); dosya yine seçilir, sunucu karar verir.
    final usage = widget.usage;
    _fileWarning = DocumentFileRules.quotaWarning(
      size: source.size,
      remainingQuotaBytes: usage != null && usage.hasQuota
          ? usage.remainingBytes
          : null,
    );
    _source = source;
    _error = null;
    // Farklı dosya: önceki denemenin yükleme bileti geçersizdir.
    _upload.reset();
    if (!_isVersion && _title.text.trim().isEmpty) {
      final base = _titleFromFileName(source.name);
      if (base.isNotEmpty) _title.text = base;
    }
  }

  static String _titleFromFileName(String name) {
    var base = name.trim();
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return String.fromCharCodes(base.runes.take(kDocumentTitleMax));
  }

  // --- Gönderim --------------------------------------------------------------------------------

  String get _signature {
    final source = _source;
    return [
      widget.scope.siteCode,
      _title.text.trim(),
      _category.apiValue,
      _audience?.apiValue ?? '',
      if (_audience == DocumentAudience.residents)
        _target.toInput().toJson().toString(),
      _description.text.trim(),
      _note.text.trim(),
      source?.name ?? '',
      source?.size ?? 0,
    ].join('|');
  }

  bool _validateExtras() {
    var ok = true;
    String? fileError = _fileError;
    if (_source == null) {
      fileError = 'Yüklenecek dosyayı seçin.';
      ok = false;
    }
    String? audienceError;
    String? targetError;
    if (!_isVersion) {
      if (_audience == null) {
        audienceError = 'Belgeyi kimlerin görebileceğini seçin.';
        ok = false;
      } else if (_audience == DocumentAudience.residents) {
        targetError = _target.validate();
        if (targetError != null) ok = false;
      }
    }
    if (_fileError != null) ok = false;
    setState(() {
      _fileError = fileError;
      _audienceError = audienceError;
      _targetError = targetError;
    });
    return ok;
  }

  bool _revealExtras() {
    final candidates = <(String?, GlobalKey)>[
      (_fileError, _fileKey),
      (_audienceError, _audienceKey),
      (_targetError, _targetKey),
    ];
    for (final (error, key) in candidates) {
      final context = key.currentContext;
      if (error != null && context != null) {
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: 0.1,
        );
        return true;
      }
    }
    return false;
  }

  Future<void> _submit() async {
    if (_upload.busy || _retry.locked) return;
    final okFields = validateForm(
      _formKey,
      validateExtra: _validateExtras,
      revealExtra: _revealExtras,
    );
    if (!okFields) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final source = _source!;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    final signature = _signature;
    // Alınmış yükleme bileti, ONU OLUŞTURAN form değerlerine aittir (başlık, KİTLE, hedef, dosya...). Değerler
    // iptal / hata sonrasında değiştiyse eski bilet atılır: aksi hâlde belge ESKİ kitleyle yayınlanırdı.
    if (_upload.hasTicket && _lastSignature != signature) _upload.reset();
    _lastSignature = signature;
    if (_isVersion) {
      await _upload.run(source: source, note: _note.text);
      return;
    }
    final audience = _audience!;
    final request = DocumentCreateRequest(
      title: _title.text,
      description: _description.text,
      category: _category,
      audience: audience,
      target: audience == DocumentAudience.residents ? _target.toInput() : null,
      file: DocumentFileInput(
        name: source.name,
        size: source.size,
        contentType: DocumentFileRules.contentTypeOf(source.name),
      ),
      note: _note.text,
      idempotencyKey: _keys.keyFor(signature),
    );
    await _upload.run(source: source, create: request);
  }

  void _cancelUpload() {
    if (!_upload.busy || _cancelling) return;
    setState(() => _cancelling = true);
    _upload.cancel();
  }

  // --- Kapatma ---------------------------------------------------------------------------------

  Future<void> _requestClose() async {
    if (_closing) return;
    if (_upload.busy) {
      AppSnack.show(
        context,
        'Yükleme sürüyor. İptal etmek için Vazgeç düğmesini kullanın.',
        kind: AppSnackKind.warning,
      );
      return;
    }
    if (_dirty && !_upload.hasTicket) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) return;
    } else if (_upload.hasTicket) {
      // Bilet alındı ama yükleme tamamlanmadı: sunucuda bekleyen kayıt var; kapanınca liste tazelensin.
      widget.onRefreshNeeded?.call();
    }
    if (!mounted) return;
    _closing = true;
    popIfCurrent<DocumentSummary>(context);
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Yükleme iptal edilsin mi?',
        icon: Icons.help_outline_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('document_discard_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Düzenlemeye Dön'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('document_discard_confirm'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: const Text('Vazgeç ve Kapat'),
          ),
        ],
        child: Text(
          'Girdiğiniz bilgiler ve seçtiğiniz dosya silinecek.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    return result ?? false;
  }

  // --- Görünüm ---------------------------------------------------------------------------------

  String get _submitLabel {
    if (_upload.phase == DocumentUploadPhase.failed && _upload.canRetry) {
      return 'Tekrar Dene';
    }
    if (_upload.phase == DocumentUploadPhase.cancelled) {
      return 'Yüklemeyi Sürdür';
    }
    return _isVersion ? 'Sürümü Yükle' : 'Yükle';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _upload.busy;
    final title = _isVersion ? 'Yeni Sürüm Yükle' : 'Belge Yükle';
    final subtitle = _isVersion
        ? widget.versionOf!.title.trim()
        : (widget.scope.siteName.isEmpty ? null : widget.scope.siteName);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppDialog(
        title: title,
        subtitle: subtitle == null || subtitle.isEmpty ? null : subtitle,
        icon: _isVersion ? Icons.upgrade_rounded : Icons.upload_file_rounded,
        actions: busy
            ? [
                TextButton(
                  key: const ValueKey<String>('document_upload_cancel'),
                  onPressed: _cancelling ? null : _cancelUpload,
                  child: Text(_cancelling ? 'İptal ediliyor...' : 'Vazgeç'),
                ),
              ]
            : [
                TextButton(
                  key: const ValueKey<String>('document_upload_close'),
                  onPressed: () => unawaited(_requestClose()),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  key: const ValueKey<String>('document_upload_submit'),
                  focusNode: _submitFocus,
                  // Hız sınırı (429) sonrası kısa süre kilitli: art arda deneme yapılmasın.
                  onPressed: _retry.locked ? null : _submit,
                  child: Text(_submitLabel),
                ),
              ],
        child: busy ? _buildProgress(context) : _buildForm(context),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final source = _source;
    final phase = _upload.phase;
    final fraction = phase == DocumentUploadPhase.preparing
        ? null
        : _upload.fraction;
    final status = switch (phase) {
      DocumentUploadPhase.preparing => 'Sunucu dosyayı doğruluyor...',
      DocumentUploadPhase.finishing => 'Dosya gönderildi, sunucu kaydediyor...',
      _ =>
        '%${_upload.percent} · ${formatDocumentSize(_upload.sentBytes)} / ${formatDocumentSize(_upload.totalBytes)}',
    };
    return Column(
      key: const ValueKey<String>('document_upload_progress_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source != null) ...[
          Text(
            source.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: th.titleSmall,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Semantics(
          label: fraction == null
              ? 'Yükleme hazırlanıyor'
              : 'Yükleniyor, yüzde ${_upload.percent}',
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                key: const ValueKey<String>('document_upload_progress'),
                value: fraction,
                minHeight: 8,
                backgroundColor: p.surfaceMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          status,
          key: const ValueKey<String>('document_upload_status'),
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        // %100'den sonra (sunucu kaydederken) Vazgeç kaydı geri ALMAZ: dürüstçe söylenir.
        InlineNotice(
          key: const ValueKey<String>('document_upload_progress_note'),
          tone: phase == DocumentUploadPhase.finishing
              ? AppTone.warning
              : AppTone.info,
          message: phase == DocumentUploadPhase.finishing
              ? 'Dosya gönderildi, sunucu kaydediyor. Bu aşamada Vazgeçerseniz belge yine de kaydedilmiş olabilir.'
              : 'Yükleme sürerken uygulamayı kapatmayın. Vazgeç ile gönderimi durdurabilirsiniz.',
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final source = _source;
    final phase = _upload.phase;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phase == DocumentUploadPhase.failed && _upload.error != null)
            CrmFormError(
              key: const ValueKey<String>('document_upload_error'),
              message: _upload.error!,
              announce: true,
            )
          else if (phase == DocumentUploadPhase.cancelled)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: _upload.cancelledLate
                  ? InlineNotice(
                      key: const ValueKey<String>(
                        'document_upload_cancelled_late',
                      ),
                      tone: AppTone.warning,
                      message: _upload.error ?? '',
                    )
                  : const InlineNotice(
                      key: ValueKey<String>('document_upload_cancelled'),
                      tone: AppTone.info,
                      message:
                          'Yükleme iptal edildi. Dilerseniz yeniden başlatabilirsiniz.',
                    ),
            ),
          if (_error != null) CrmFormError(message: _error!),
          // --- Dosya ---
          KeyedSubtree(
            key: _fileKey,
            child: _FileField(
              source: source,
              error: _fileError,
              warning: _fileWarning,
              onPick: _pickFile,
              hint: _fileHint,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (!_isVersion) ...[
            TextFormField(
              key: const ValueKey<String>('document_upload_title'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: kDocumentTitleMax,
              // Sayaç ve doğrulama AYNI birimi (kod noktası; sunucu da öyle sayar) kullanır; sınırı aşan giriş
              // sessizce kırpılmaz: sayaç kırmızıya döner, doğrulayıcı hata verir.
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => documentCounter(
                    context,
                    _title.text.runes.length,
                    kDocumentTitleMax,
                  ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Başlık',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (value) {
                final length = (value ?? '').trim().runes.length;
                if (length < 1) return 'Başlık boş olamaz.';
                if (length > kDocumentTitleMax) {
                  return 'Başlık en çok $kDocumentTitleMax karakter olabilir.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpace.lg),
            DocumentCategoryField(
              value: _category,
              onChanged: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              key: const ValueKey<String>('document_upload_description'),
              controller: _description,
              minLines: 2,
              maxLines: 6,
              maxLength: kDocumentDescriptionMax,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => documentCounter(
                    context,
                    _description.text.runes.length,
                    kDocumentDescriptionMax,
                  ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Açıklama (isteğe bağlı)',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value ?? '').trim().runes.length > kDocumentDescriptionMax
                  ? 'Açıklama en çok $kDocumentDescriptionMax karakter olabilir.'
                  : null,
            ),
            const SizedBox(height: AppSpace.lg),
            KeyedSubtree(
              key: _audienceKey,
              child: DocumentAudienceField(
                value: _audience,
                errorText: _audienceError,
                onChanged: (audience) => setState(() {
                  _audience = audience;
                  _audienceError = null;
                  _targetError = null;
                }),
              ),
            ),
            if (_audience == DocumentAudience.residents) ...[
              const SizedBox(height: AppSpace.lg),
              KeyedSubtree(
                key: _targetKey,
                child: DocumentTargetSection(
                  scope: widget.scope,
                  value: _target,
                  errorText: _targetError,
                  onChanged: (value) => setState(() {
                    _target = value;
                    _targetError = null;
                  }),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
          ] else ...[
            Text(
              'Yeni sürüm yüklenince sakinler yalnız güncel sürümü indirir; önceki sürümler yöneticilerde kalır.',
              style: th.bodyMedium,
            ),
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              key: const ValueKey<String>('document_upload_note'),
              controller: _note,
              maxLength: kDocumentNoteMax,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => documentCounter(
                    context,
                    _note.text.runes.length,
                    kDocumentNoteMax,
                  ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Sürüm notu (isteğe bağlı)',
                helperText: 'Örn. "Madde 4 düzeltildi"',
                helperMaxLines: 2,
              ),
              validator: (value) =>
                  (value ?? '').trim().runes.length > kDocumentNoteMax
                  ? 'Not en çok $kDocumentNoteMax karakter olabilir.'
                  : null,
            ),
            const SizedBox(height: AppSpace.lg),
          ],
          DialogPanel(
            key: const ValueKey<String>('document_privacy_notice'),
            tone: AppTone.warning,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.privacy_tip_rounded,
                  size: 20,
                  color: AppTone.warning.ink(p),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    kDocumentPrivacyNotice,
                    style: th.bodyMedium?.copyWith(
                      color: AppTone.warning.ink(p),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dosya seçicinin altındaki ipucu: izinli türler ve (öğrenildiyse) boyut sınırı. Sınır bilinmiyorsa sayı
  /// UYDURULMAZ.
  String get _fileHint {
    final max = widget.service.learnedMaxFileBytes;
    final usage = widget.usage;
    final parts = <String>[
      DocumentFileRules.allowedLabel,
      if (max != null) 'en çok ${formatDocumentSize(max)}',
      if (usage != null && usage.hasQuota)
        'kalan alan ${formatDocumentSize(usage.remainingBytes)}',
    ];
    return parts.join(' · ');
  }
}

/// Dosya seçim alanı: seçilmemişken "Dosya Seç" düğmesi; seçilince ad + tür / boyut + "Değiştir".
class _FileField extends StatelessWidget {
  const _FileField({
    required this.source,
    required this.error,
    required this.warning,
    required this.onPick,
    required this.hint,
  });

  final DocumentUploadSource? source;
  final String? error;
  final String? warning;
  final VoidCallback onPick;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final source = this.source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source == null)
          PrimaryActionButton(
            key: const ValueKey<String>('document_upload_pick'),
            label: 'Dosya Seç',
            icon: Icons.attach_file_rounded,
            variant: AppButtonVariant.outline,
            onPressed: onPick,
          )
        else
          DialogPanel(
            key: const ValueKey<String>('document_upload_file'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  label:
                      'Seçilen dosya: ${source.name}, ${documentFileLabel('', source.size, source.name)}',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(source.name, style: th.titleSmall),
                        Text(
                          documentFileLabel('', source.size, source.name),
                          style: th.bodySmall?.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey<String>('document_upload_change'),
                    onPressed: onPick,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Dosyayı Değiştir'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpace.xs),
        Text(hint, style: th.bodySmall?.copyWith(color: p.textSecondary)),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                key: const ValueKey<String>('document_upload_file_error'),
                style: th.bodySmall?.copyWith(
                  color: AppTone.danger.ink(p),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (warning != null && error == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                warning!,
                key: const ValueKey<String>('document_upload_file_warning'),
                style: th.bodySmall?.copyWith(
                  color: AppTone.warning.ink(p),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
