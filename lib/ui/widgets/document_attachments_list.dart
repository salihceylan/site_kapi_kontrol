// Duyurunun "Ekler" listesi (yönetici ayrıntısı ve sakin okuma penceresi; docs/PLATFORM_BELGELER.md A12, A13).
//
// Her satır: tür simgesi + başlık + "PDF, 2,4 MB" + "Aç / Kaydet" (belge geçici dosyaya AKIŞLA indirilir ve
// paylaşım menüsüne verilir). `available == false` (belge silinmiş ya da modül kapalı): satır soluk ve düğme yok,
// "Artık kullanılamıyor" yazar. İndirme çift dokunuşa karşı korunur (tek seferde bir indirme).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_download_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';

/// Bir eki indiren çağrı (rol / uç noktaya göre çağıran verir).
typedef DocumentAttachmentDownload =
    DocumentDownloadCall Function(DocumentAttachment attachment);

class DocumentAttachmentsList extends StatefulWidget {
  const DocumentAttachmentsList({
    super.key,
    required this.attachments,
    required this.download,
    this.sharer,
  });

  final List<DocumentAttachment> attachments;
  final DocumentAttachmentDownload download;
  final DocumentFileSharer? sharer;

  @override
  State<DocumentAttachmentsList> createState() =>
      _DocumentAttachmentsListState();
}

class _DocumentAttachmentsListState extends State<DocumentAttachmentsList> {
  int? _busyId;

  Future<void> _open(
    DocumentAttachment attachment,
    BuildContext buttonContext,
  ) async {
    if (_busyId != null) return;
    setState(() => _busyId = attachment.documentId);
    try {
      await downloadAndShareDocument(
        context,
        title: attachment.title,
        originContext: buttonContext,
        sharer: widget.sharer,
        download: widget.download(attachment),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.attachments;
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey<String>('announcement_attachments_list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DialogSectionTitle(
          icon: Icons.attach_file_rounded,
          title: 'Ekler (${attachments.length})',
          tone: AppTone.info,
        ),
        const SizedBox(height: AppSpace.sm),
        for (final attachment in attachments) ...[
          _AttachmentTile(
            attachment: attachment,
            busy: _busyId == attachment.documentId,
            disabled: _busyId != null,
            onOpen: (buttonContext) =>
                unawaited(_open(attachment, buttonContext)),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.busy,
    required this.disabled,
    required this.onOpen,
  });

  final DocumentAttachment attachment;
  final bool busy;
  final bool disabled;
  final void Function(BuildContext buttonContext) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final a = attachment;
    final title = a.title.trim().isEmpty ? 'Belge' : a.title.trim();
    final detail = a.sizeBytes > 0 ? a.fileLabel : null;
    final semantic =
        'Ek: $title${detail == null ? '' : ', $detail'}${a.available ? '' : '. Artık kullanılamıyor'}';
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic,
            child: ExcludeSemantics(
              child: Opacity(
                opacity: a.available ? 1 : 0.6,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      documentKindIcon(a.kind),
                      size: 22,
                      color: documentKindTone(a.kind).ink(p),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: th.titleSmall),
                          if (detail != null)
                            Text(
                              detail,
                              style: th.bodySmall?.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          if (!a.available)
                            Text(
                              'Artık kullanılamıyor',
                              key: ValueKey<String>(
                                'attachment_unavailable_${a.documentId}',
                              ),
                              style: th.bodySmall?.copyWith(
                                color: AppTone.warning.ink(p),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (a.available)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Builder(
                builder: (buttonContext) => TextButton.icon(
                  key: ValueKey<String>('attachment_open_${a.documentId}'),
                  onPressed: disabled ? null : () => onOpen(buttonContext),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Aç / Kaydet'),
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Liste kartlarında "N ek" çipi için kısa metin.
String attachmentCountLabel(int count) => '$count ek';
