// Duyuruya eklenecek belgeleri seçme penceresi (docs/PLATFORM_BELGELER.md A12): aynı sitenin YAYINDAKİ ve
// kitlesi "Sakinler" olan belgeleri (yönetici / kurul belgesi duyuruya eklenemez) arama ile listeler; en çok
// kalan kontenjan kadar seçilir. Seçilenler ekleme anında uyarı metniyle birlikte döner.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// Duyuru başına en çok ek sayısı (sözleşme A12).
const int kAnnouncementMaxAttachments = 5;

/// Eklemede gösterilen uyarı (sözleşme A12): belgenin kendi hedefi daha dar olsa bile alıcılar indirir.
const String kAttachmentAudienceWarning =
    'Bu belge duyurunun tüm alıcılarına açılır.';

class DocumentAttachPickerDialog extends StatefulWidget {
  const DocumentAttachPickerDialog({
    super.key,
    required this.scope,
    required this.service,
    this.excludeIds = const <int>{},
    this.maxSelectable = kAnnouncementMaxAttachments,
  });

  final PeopleScope scope;
  final DocumentService service;

  /// Zaten eklenmiş belgeler (listede çıkmaz).
  final Set<int> excludeIds;

  /// Bu pencerede en çok seçilebilecek belge sayısı (kalan kontenjan).
  final int maxSelectable;

  static Future<List<DocumentSummary>?> show(
    BuildContext context, {
    required PeopleScope scope,
    required DocumentService service,
    Set<int> excludeIds = const <int>{},
    int maxSelectable = kAnnouncementMaxAttachments,
  }) {
    return showDialog<List<DocumentSummary>>(
      context: context,
      builder: (_) => DocumentAttachPickerDialog(
        scope: scope,
        service: service,
        excludeIds: excludeIds,
        maxSelectable: maxSelectable,
      ),
    );
  }

  @override
  State<DocumentAttachPickerDialog> createState() =>
      _DocumentAttachPickerDialogState();
}

class _DocumentAttachPickerDialogState
    extends State<DocumentAttachPickerDialog> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  final Map<int, DocumentSummary> _selected = <int, DocumentSummary>{};

  late final PagedLoader<DocumentSummary>
  _loader = PagedLoader<DocumentSummary>(
    pageSize: 30,
    fetch: (offset, limit) async {
      final page = await widget.service.listManaged(
        widget.scope.siteCode,
        status: 'active',
        audience: 'residents',
        query: _query,
        limit: limit,
        offset: offset,
      );
      return (
        items: page.items
            .where((d) => !widget.excludeIds.contains(d.id))
            .toList(),
        total: page.total,
      );
    },
    keyOf: (d) => d.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Belgeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  void _runSearch() {
    _timer?.cancel();
    final next = _search.text.trim();
    if (next == _query && _loader.loadedOnce && _loader.error == null) return;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _runSearch);
    setState(() {});
  }

  void _toggle(DocumentSummary document, bool selected) {
    setState(() {
      if (selected) {
        if (_selected.length < widget.maxSelectable) {
          _selected[document.id] = document;
        }
      } else {
        _selected.remove(document.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final full = _selected.length >= widget.maxSelectable;
    return AppDialog(
      title: 'Belge Ekle',
      subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
      icon: Icons.attach_file_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('document_attach_cancel'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('document_attach_confirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => popIfCurrent<List<DocumentSummary>>(
                  context,
                  _selected.values.toList(growable: false),
                ),
          child: Text(
            _selected.isEmpty ? 'Ekle' : 'Ekle (${_selected.length})',
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InlineNotice(
            tone: AppTone.info,
            message:
                '$kAttachmentAudienceWarning Yalnız sakinlere açık, yayındaki belgeler eklenebilir.',
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey<String>('document_attach_search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (_) => _runSearch(),
            decoration: const InputDecoration(
              labelText: 'Belge ara',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          // "Ekle" seçim yokken pasiftir: nedeni söylenir (ekran okuyucu da okur).
          if (_selected.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                'Eklemek için en az bir belgeyi işaretleyin.',
                key: const ValueKey<String>('document_attach_hint'),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (full)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                'En çok ${widget.maxSelectable} belge seçilebilir.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          CrmListBody<DocumentSummary>(
            loader: _loader,
            emptyIcon: Icons.folder_open_rounded,
            emptyTitle: 'Eklenebilecek belge yok.',
            emptyMessage:
                'Dosya Deposu ekranından kitlesi "Sakinler" olan bir belge yükleyin; sonra duyuruya ekleyebilirsiniz.',
            filteredTitle: 'Bu arama için belge bulunamadı.',
            filtered: _query.isNotEmpty,
            itemBuilder: (context, document) {
              final selected = _selected.containsKey(document.id);
              final version = document.currentVersion;
              final fileLine = version == null
                  ? document.category.label
                  : '${document.category.shortLabel} · '
                        '${documentFileLabel(version.mimeType, version.sizeBytes, version.fileName)}';
              return AppCard(
                padding: EdgeInsets.zero,
                selected: selected,
                child: CheckboxListTile(
                  key: ValueKey<String>('document_attach_${document.id}'),
                  value: selected,
                  onChanged: (selected || !full)
                      ? (value) => _toggle(document, value ?? false)
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    document.title.trim().isEmpty
                        ? 'Başlıksız belge'
                        : document.title.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(fileLine),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
