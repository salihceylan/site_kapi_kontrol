// Duyuru formundaki "Belge eki" alanı (docs/PLATFORM_BELGELER.md A12, A13): seçilen belgeler (en çok 5), "Belge
// Ekle" ve ekleme anı uyarısı. `documents` modülü sitede KAPALIYSA (ya da yetki yoksa) alan hiç çizilmez: açılışta
// bir kez yoklanır (`GET .../documents?limit=1`).
//
// Denetimli bileşen: seçimi üst form tutar; bu widget yalnız çizer ve değişiklikleri bildirir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_attach_picker_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

class DocumentAttachmentField extends StatefulWidget {
  const DocumentAttachmentField({
    super.key,
    required this.scope,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.service,
  });

  final PeopleScope scope;
  final List<DocumentAttachment> value;
  final ValueChanged<List<DocumentAttachment>> onChanged;
  final bool enabled;

  /// Belge servisi; verilmezse oturumdan kurulur (testlerde sahte verilir).
  final DocumentService? service;

  @override
  State<DocumentAttachmentField> createState() =>
      _DocumentAttachmentFieldState();
}

class _DocumentAttachmentFieldState extends State<DocumentAttachmentField> {
  late final DocumentService _service =
      widget.service ?? DocumentService(authService: widget.scope.authService);

  /// null: yoklanıyor; true: alan gösterilir; false: modül kapalı / yetki yok.
  bool? _available;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  Future<void> _probe() async {
    try {
      await _service.listManaged(
        widget.scope.siteCode,
        status: 'active',
        audience: 'residents',
        limit: 1,
      );
      if (mounted) setState(() => _available = true);
    } on ApiException catch (e) {
      // Modül kapalı ya da yetki yok: alan gizlenir. Ağ hatası gibi geçici durumlarda alan görünür kalır
      // (seçici hatayı kendisi gösterir ve yeniden denenebilir).
      final hide =
          e.code == 'MODULE_DISABLED' ||
          e.code == 'FORBIDDEN_ROLE' ||
          e.code == 'FORBIDDEN_SITE' ||
          e.isForbidden;
      if (mounted) setState(() => _available = !hide);
    } catch (_) {
      if (mounted) setState(() => _available = true);
    }
  }

  Future<void> _add() async {
    if (_picking || !widget.enabled) return;
    _picking = true;
    List<DocumentSummary>? picked;
    try {
      picked = await DocumentAttachPickerDialog.show(
        context,
        scope: widget.scope,
        service: _service,
        excludeIds: {for (final a in widget.value) a.documentId},
        maxSelectable: kAnnouncementMaxAttachments - widget.value.length,
      );
    } finally {
      _picking = false;
    }
    final documents = picked;
    if (documents == null || documents.isEmpty || !mounted) return;
    final next = <DocumentAttachment>[
      ...widget.value,
      for (final d in documents)
        if (!widget.value.any((a) => a.documentId == d.id))
          DocumentAttachment(
            documentId: d.id,
            title: d.title,
            fileName: d.currentVersion?.fileName ?? '',
            mimeType: d.currentVersion?.mimeType ?? '',
            sizeBytes: d.currentVersion?.sizeBytes ?? 0,
          ),
    ];
    widget.onChanged(
      next.take(kAnnouncementMaxAttachments).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    // Mevcut ek varsa (taslağı düzenleme) modül yoklaması bitmeden de gösterilir.
    if (_available != true && value.isEmpty) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final full = value.length >= kAnnouncementMaxAttachments;
    return Padding(
      // Alt boşluk alanın kendisindedir: alan gizliyken (modül kapalı) forma boş aralık eklenmez.
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        key: const ValueKey<String>('announcement_attachments_field'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Belge eki', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          if (value.isEmpty)
            Text(
              'İsterseniz Belgeler modülündeki bir belgeyi duyuruya ekleyebilirsiniz (en çok '
              '$kAnnouncementMaxAttachments).',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            )
          else ...[
            for (final attachment in value)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: _AttachmentRow(
                  attachment: attachment,
                  onRemove: widget.enabled
                      ? () => widget.onChanged(
                          value
                              .where(
                                (a) => a.documentId != attachment.documentId,
                              )
                              .toList(),
                        )
                      : null,
                ),
              ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '$kAttachmentAudienceWarning E-postaya dosya eklenmez; alıcılar belgeyi uygulamadan açar.',
              key: const ValueKey<String>('announcement_attachments_warning'),
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('announcement_add_attachment'),
            label: full
                ? 'En çok $kAnnouncementMaxAttachments belge'
                : 'Belge Ekle',
            icon: Icons.attach_file_rounded,
            variant: AppButtonVariant.outline,
            onPressed: (widget.enabled && !full) ? _add : null,
          ),
        ],
      ),
    );
  }
}

/// Seçilen ek satırı: tür simgesi + başlık + "PDF, 2,4 MB" + ✕ (en az 48x48 dp).
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment, required this.onRemove});

  final DocumentAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final title = attachment.title.trim().isEmpty
        ? 'Belge'
        : attachment.title.trim();
    final detail = attachment.sizeBytes > 0 ? attachment.fileLabel : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              label:
                  'Ek: $title${detail == null ? '' : ', $detail'}'
                  '${attachment.available ? '' : '. Artık kullanılamıyor'}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpace.md,
                    top: AppSpace.sm,
                    bottom: AppSpace.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: th.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          style: th.bodySmall?.copyWith(color: p.textSecondary),
                        ),
                      // Belge silinmiş ya da modül kapalı (sunucu `available:false`): yönetici bilsin; ek yine
                      // kaldırılabilir.
                      if (!attachment.available)
                        Text(
                          'Artık kullanılamıyor',
                          key: ValueKey<String>(
                            'announcement_attachment_unavailable_${attachment.documentId}',
                          ),
                          style: th.bodySmall?.copyWith(
                            color: AppTone.warning.ink(p),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey<String>(
              'announcement_remove_attachment_${attachment.documentId}',
            ),
            tooltip: '$title ekini kaldır',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
