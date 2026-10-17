// Belge üstverisi düzenleme penceresi (docs/PLATFORM_BELGELER.md A7 `PATCH`): başlık, açıklama, kategori, kitle ve
// hedef. Dosya değişmez (yeni dosya için "Yeni Sürüm Yükle"). Yalnız DEĞİŞEN alanlar gönderilir; değişiklik
// yoksa istek yapılmadan kapanır. Kitle değişikliği ANINDA geçerlidir (pencerede söylenir).
//
// Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Hata
// pencerenin içinde kalır (odak "Kaydet"e döner); doldurulmuş form yanlışlıkla kapanırsa onay istenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_upload_dialog.dart'
    show documentCounter;
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_form_fields.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_target_section.dart';

class DocumentEditDialog extends StatefulWidget {
  const DocumentEditDialog({
    super.key,
    required this.scope,
    required this.service,
    required this.document,
    this.onRefreshNeeded,
  });

  final PeopleScope scope;
  final DocumentService service;
  final DocumentDetail document;

  /// Belge başka yerden değişmiş / silinmiş (404 / `INVALID_STATE`): pencere kapansa da çağıran tazelesin.
  final VoidCallback? onRefreshNeeded;

  /// Başarıda güncel ayrıntıyla kapanır; değişiklik yoksa ya da vazgeçilirse null.
  static Future<DocumentDetail?> show(
    BuildContext context, {
    required PeopleScope scope,
    required DocumentService service,
    required DocumentDetail document,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<DocumentDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentEditDialog(
        scope: scope,
        service: service,
        document: document,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  @override
  State<DocumentEditDialog> createState() => _DocumentEditDialogState();
}

class _DocumentEditDialogState extends State<DocumentEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _audienceKey = GlobalKey();
  final GlobalKey _targetKey = GlobalKey();
  final FocusNode _saveFocus = FocusNode(debugLabel: 'document_edit_save');
  final RetryLock _retry = RetryLock();
  late final TextEditingController _title = TextEditingController(
    text: widget.document.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.document.description,
  );
  late DocumentCategory _category = widget.document.category;
  late DocumentAudience _audience =
      widget.document.audience == DocumentAudience.unknown
      ? DocumentAudience.managers
      : widget.document.audience;
  late DocumentTargetSelection _target = DocumentTargetSelection.fromTarget(
    widget.document.target,
  );
  // Açılıştaki hedef (karşılaştırma için); `late final = _target` tembel değerlendirilir ve değişmiş hedefi alırdı.
  late final DocumentTargetSelection _initialTarget =
      DocumentTargetSelection.fromTarget(widget.document.target);

  bool _submitting = false;
  bool _closing = false;
  String? _error;
  String? _targetError;

  DocumentDetail get _initial => widget.document;

  @override
  void dispose() {
    _retry.dispose();
    _saveFocus.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Gönderilecek alanlar (yalnız değişenler); boşsa değişiklik yok.
  Map<String, Object?> _changedFields() {
    final fields = <String, Object?>{};
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (title != _initial.title.trim()) fields['title'] = title;
    if (description != _initial.description.trim()) {
      fields['description'] = description;
    }
    if (_category != _initial.category) fields['category'] = _category.apiValue;
    final audienceChanged = _audience != _initial.audience;
    if (audienceChanged) fields['audience'] = _audience.apiValue;
    if (_audience == DocumentAudience.residents &&
        (audienceChanged || !_target.sameAs(_initialTarget))) {
      fields['target'] = _target.toInput().toJson();
    }
    return fields;
  }

  bool get _dirty => _changedFields().isNotEmpty;

  bool _validateExtras() {
    final targetError = _audience == DocumentAudience.residents
        ? _target.validate()
        : null;
    setState(() => _targetError = targetError);
    return targetError == null;
  }

  bool _revealExtras() {
    final context = _targetKey.currentContext;
    if (_targetError != null && context != null) {
      Scrollable.ensureVisible(
        context,
        duration: Duration.zero,
        alignment: 0.1,
      );
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
    final fields = _changedFields();
    if (fields.isEmpty) {
      // Değişiklik yok: sunucuya gitmeden kapanır.
      _closing = true;
      popIfCurrent<DocumentDetail>(context);
      return;
    }
    FocusScope.of(context).unfocus();
    await _send(fields, confirm: false);
  }

  /// PATCH gönderir. Belge `residents` kitlesinden çıkarılırken YAYINDAKİ bir duyuruya ekliyse sunucu 409
  /// `DOCUMENT_IN_USE` döner: onay penceresi çıkar, onaylanırsa `confirm:true` ile yeniden gönderilir (çıkmaz
  /// kalmaz; vazgeçilirse form olduğu gibi açık kalır, hata gösterilmez).
  Future<void> _send(
    Map<String, Object?> fields, {
    required bool confirm,
  }) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final updated = await widget.service.updateDocument(
        widget.scope.siteCode,
        _initial.id,
        fields,
        confirm: confirm,
      );
      if (!mounted) return;
      _closing = true;
      popIfCurrent<DocumentDetail>(
        context,
        // Yanıtta ayrıntı eksikse (yalnız özet) eldeki alanlarla birleştirilmiş bir ayrıntı yerine id'li ayrıntı
        // döner; çağıran ayrıntıyı sunucudan yeniden okur.
        updated.id > 0 ? updated : _initial,
      );
    } catch (e) {
      if (!confirm && e is ApiException && e.code == 'DOCUMENT_IN_USE') {
        if (!mounted) return;
        setState(() => _submitting = false);
        final count = e.payload?['attachments_count'];
        final go = await _confirmDetach(count is num ? count.toInt() : null);
        if (!mounted) return;
        if (go) return _send(fields, confirm: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _saveFocus.requestFocus();
        });
        return;
      }
      if (e is ApiException &&
          (e.statusCode == 404 || e.code == 'INVALID_STATE')) {
        widget.onRefreshNeeded?.call();
      }
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : crmMessageOf(
                e,
                'Belge kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
      // Hata sonrası odak Kaydet düğmesine (klavye / ekran okuyucu kullanıcısı hatayı kaçırmasın).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveFocus.requestFocus();
      });
    }
  }

  Future<bool> _confirmDetach(int? count) async {
    final countText = (count ?? 0) > 0
        ? '$count yayındaki duyuruya'
        : 'yayındaki duyurulara';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Belge duyurularda kullanılıyor',
        icon: Icons.warning_amber_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('document_edit_inuse_cancel'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('document_edit_inuse_confirm'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: const Text('Yine de Değiştir'),
          ),
        ],
        child: Text(
          'Bu belge $countText ekli. Kitleyi sakinlerden çıkarırsanız duyuru alıcıları ekine erişemez; '
          'taslak ve zamanlanmış duyurulardan ek çıkarılır. Yine de değiştirilsin mi?',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    return result ?? false;
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
              key: const ValueKey<String>('document_edit_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Düzenlemeye Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('document_edit_discard'),
              onPressed: () => popIfCurrent(dialogContext, true),
              child: const Text('Vazgeç ve Kapat'),
            ),
          ],
          child: Text(
            'Yaptığınız değişiklikler kaydedilmedi.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }
    _closing = true;
    popIfCurrent<DocumentDetail>(context);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppDialog(
        title: 'Belgeyi Düzenle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.edit_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('document_edit_close'),
            onPressed: _submitting ? null : () => unawaited(_requestClose()),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('document_edit_save'),
            focusNode: _saveFocus,
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
              TextFormField(
                key: const ValueKey<String>('document_edit_title'),
                controller: _title,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kDocumentTitleMax,
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
                keyPrefix: 'document_edit_category_',
                enabled: !_submitting,
                value: _category,
                onChanged: (category) => setState(() => _category = category),
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('document_edit_description'),
                controller: _description,
                enabled: !_submitting,
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
                  keyPrefix: 'document_edit_audience_',
                  enabled: !_submitting,
                  value: _audience,
                  onChanged: (audience) => setState(() {
                    _audience = audience;
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
                    enabled: !_submitting,
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
              InlineNotice(
                tone: AppTone.info,
                message:
                    'Kitle değişikliği anında geçerlidir. Dosyayı değiştirmek için "Yeni Sürüm Yükle"yi kullanın.',
                key: const ValueKey<String>('document_edit_note'),
              ),
              if (_initial.attachedAnnouncements.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                if (_initial.audience == DocumentAudience.residents &&
                    _audience != DocumentAudience.residents)
                  const InlineNotice(
                    key: ValueKey<String>('document_edit_detach_warning'),
                    tone: AppTone.warning,
                    message:
                        'Bu belge duyurulara ekli. Kitleyi sakinlerden çıkarırsanız duyuru alıcıları ekine '
                        'erişemez; taslak ve zamanlanmış duyurulardan ek çıkarılır.',
                  )
                else
                  Text(
                    'Bu belge ${_initial.attachedAnnouncements.length} duyuruya ekli; duyurunun alıcıları ekini yine indirebilir.',
                    style: th.bodySmall,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
