import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_download_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';

/// Sakin "Dosya Deposu" ekranı (Platform Faz 3b-A; Belgelerim): yalnız KENDİ kitlesinde olduğu, `drive_storage` modülü açık
/// sitelerdeki belgeler. Kategori süzgeci, arama, imleçli sayfalama (`before_id`), "Güncellendi" çipi ve
/// "Aç / Kaydet" (geçici dosyaya akışla indirip paylaşım menüsüne verir).
///
/// - Birden çok sitede ([sites] >= 2) site süzgeci çıkar ve kartlarda site adı görünür.
/// - Yarışlar: süzgeç / arama / site değişimi sırasında eski imleçle gelen sayfa listeye eklenmez
///   ([CursorLoader]); dispose sonrası yanıt yok sayılır; HATA ASLA "belge yok" demez (liste boşken hata +
///   "Tekrar Dene"), boş durum yalnız gerçekten boşken çizilir.
/// - Bir belge indirilirken o kartın düğmesi kapalıdır (çift dokunma); indirilen belge bu arada silindiyse
///   (404) liste yenilenir.
class DocumentResidentView extends StatefulWidget {
  const DocumentResidentView({
    super.key,
    required this.authService,
    this.service,
    this.sites = const <PeopleSite>[],
    this.sharer,
  });

  final AuthService authService;
  final DocumentService? service;

  /// Sakinin belge alabileceği (modül açık) siteler; süzgeç yalnız 2 ve üstünde çıkar.
  final List<PeopleSite> sites;
  final DocumentFileSharer? sharer;

  @override
  State<DocumentResidentView> createState() => DocumentResidentViewState();
}

class DocumentResidentViewState extends State<DocumentResidentView> {
  static const int _allSites = 0;

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String? _category;
  int? _siteFilter;
  String _lastSignature = '||';
  int? _busyId;

  late DocumentService _service =
      widget.service ?? DocumentService(authService: widget.authService);

  late final CursorLoader<ResidentDocument>
  _loader = CursorLoader<ResidentDocument>(
    fetch: (before) async {
      final page = await _service.listMine(
        siteCode: _siteFilter,
        category: _category,
        query: _query,
        limit: 30,
        beforeId: before,
      );
      return (items: page.items, next: page.nextBeforeId);
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
  void didUpdateWidget(DocumentResidentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? DocumentService(authService: widget.authService);
    }
    // Süzgeçte olan site artık listede yoksa süzgeç kalkar.
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|${_category ?? ''}|${_siteFilter ?? ''}';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _selectCategory(String? category) {
    if (category == _category) return;
    _category = category;
    _applyFilters();
    setState(() {});
  }

  Future<void> _open(
    ResidentDocument document,
    BuildContext buttonContext,
  ) async {
    if (_busyId != null) return;
    setState(() => _busyId = document.id);
    try {
      await downloadAndShareDocument(
        context,
        title: document.title,
        originContext: buttonContext,
        sharer: widget.sharer,
        download: (onProgress, cancel) async {
          try {
            return await _service.downloadMine(
              document.id,
              fallbackName: document.fileName.isEmpty
                  ? 'belge'
                  : document.fileName,
              onProgress: onProgress,
              cancel: cancel,
            );
          } on ApiException catch (e) {
            // Belge bu arada kaldırıldı / kitleden çıkıldı: liste güncel hâle gelsin.
            if (e.code == 'DOCUMENT_NOT_FOUND' && mounted) {
              unawaited(_loader.reload());
            }
            rethrow;
          }
        },
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  bool get _filtered =>
      _query.isNotEmpty || _category != null || _siteFilter != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (multiSite) ...[
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>(
                'documents_resident_site_${_siteFilter ?? 0}',
              ),
              isExpanded: true,
              initialValue: _siteFilter ?? _allSites,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(
                labelText: 'Site',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: _allSites,
                  child: Text(
                    'Tüm siteler',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final s in widget.sites)
                  DropdownMenuItem<int>(
                    value: s.code,
                    child: Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                final next = value == _allSites ? null : value;
                if (next == _siteFilter) return;
                _siteFilter = next;
                _applyFilters();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('documents_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applyFilters(),
                decoration: InputDecoration(
                  labelText: 'Belge ara',
                  hintText: 'Başlık, açıklama veya dosya adı',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _applyFilters();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text('Kategori', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('document_category_all'),
                    label: const Text('Hepsi'),
                    selected: _category == null,
                    onSelected: (_) => _selectCategory(null),
                  ),
                  for (final category in DocumentCategory.values)
                    ChoiceChip(
                      key: ValueKey<String>(
                        'document_category_${category.apiValue}',
                      ),
                      label: Text(category.shortLabel),
                      selected: _category == category.apiValue,
                      onSelected: (_) => _selectCategory(category.apiValue),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Belgeler',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<ResidentDocument>(
          loader: _loader,
          showLastUpdated: true,
          emptyIcon: Icons.folder_open_rounded,
          emptyTitle: _filtered
              ? 'Bu arama ve süzgeç için belge bulunamadı.'
              : 'Henüz belge yok.',
          emptyMessage: _filtered
              ? null
              : 'Yönetimin sizinle paylaştığı belgeler burada görünür.',
          itemBuilder: (context, document) => Builder(
            builder: (cardContext) => DocumentResidentCard(
              document: document,
              showSite: multiSite,
              busy: _busyId == document.id,
              onOpen: () => unawaited(_open(document, cardContext)),
            ),
          ),
        ),
      ],
    );
  }
}
