import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/helpers/list_export.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_upload_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Bir sitenin yönetici belge listesi (Platform Faz 3b-A): kategori süzgeci + arama + durum (Yayında /
/// Silinenler), kota çubuğu, sayfalı kartlar, "Belge Yükle" (yalnız yazma yetkisi olanda) ve ayrıntı penceresi.
///
/// - Hızlı art arda aramada ya da süzgeç değişiminde eski yanıt yenisini ezmez ([PagedLoader] jetonu). Arama
///   duraksayınca (350 ms) ya da klavyeden gönderilince çalışır.
/// - Hata ASLA "belge yok" demez: liste boşken hata varsa hata + "Tekrar Dene" çizilir; ilk yükleme bitmeden boş
///   durum çizilmez. Modül kapalıysa (403 `MODULE_DISABLED`) liste yerine açıklayıcı kart çıkar.
/// - Kurul üyesi ([PeopleScope.canWrite] false) SALT OKUR: yükleme düğmesi, kota ve "Silinenler" yoktur.
/// - Her başarılı işlemden sonra liste otomatik yenilenir. Sunucu sitesine göre kurulur: site değişince bu widget
///   yeniden oluşturulur.
class DocumentAdminList extends StatefulWidget {
  const DocumentAdminList({
    super.key,
    required this.scope,
    required this.service,
    this.picker = const FilePickerDocumentPicker(),
    this.sharer,
    this.onOpenModules,
  });

  final PeopleScope scope;
  final DocumentService service;
  final DocumentPicker picker;
  final DocumentFileSharer? sharer;

  /// Modül kapalı kartındaki "Modüller" düğmesi (yalnız modülü açabilen / talep edebilen kullanıcıya verilir).
  final VoidCallback? onOpenModules;

  @override
  State<DocumentAdminList> createState() => DocumentAdminListState();
}

class DocumentAdminListState extends State<DocumentAdminList> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String? _category;
  String _status = 'active';
  String _lastSignature = '||active';
  DocumentUsage? _usage;
  bool _moduleOff = false;

  // Yükleme / ayrıntı pencereleri çift dokunuşta iki kez açılmasın.
  bool _opening = false;

  late final PagedLoader<DocumentSummary>
  _loader = PagedLoader<DocumentSummary>(
    pageSize: 30,
    fetch: (offset, limit) async {
      try {
        final page = await widget.service.listManaged(
          widget.scope.siteCode,
          category: _category,
          status: _status,
          query: _query,
          limit: limit,
          offset: offset,
        );
        if (mounted) {
          _usage = page.usage ?? _usage;
          _moduleOff = false;
        }
        return (items: page.items, total: page.total);
      } on ApiException catch (e) {
        if (e.code == 'MODULE_DISABLED' && mounted) _moduleOff = true;
        rethrow;
      }
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

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|${_category ?? ''}|$_status';
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

  void _selectStatus(String status) {
    if (status == _status) return;
    _status = status;
    _applyFilters();
    setState(() {});
  }

  Future<void> _upload() async {
    if (_opening) return;
    _opening = true;
    final DocumentSummary? result;
    try {
      result = await DocumentUploadDialog.show(
        context,
        scope: widget.scope,
        service: widget.service,
        picker: widget.picker,
        usage: _usage,
        // İstek sunucuya ulaşmış olabilir (zaman aşımı, yarım kalan yükleme): form kapanırken liste tazelenir.
        onRefreshNeeded: () => unawaited(_loader.reload()),
      );
    } finally {
      _opening = false;
    }
    if (result == null || !mounted) return;
    AppSnack.show(context, 'Belge yüklendi.', kind: AppSnackKind.success);
    unawaited(_loader.reload());
  }

  Future<void> _open(DocumentSummary document) async {
    if (_opening) return;
    _opening = true;
    String? message;
    try {
      message = await DocumentDetailDialog.show(
        context,
        scope: widget.scope,
        service: widget.service,
        documentId: document.id,
        initialTitle: document.title,
        usage: _usage,
        picker: widget.picker,
        sharer: widget.sharer,
        onChanged: () {
          if (mounted) unawaited(_loader.reload());
        },
      );
    } finally {
      _opening = false;
    }
    if (message != null && mounted) {
      AppSnack.show(context, message, kind: AppSnackKind.success);
    }
  }

  bool get _filtered => _query.isNotEmpty || _category != null;

  @override
  Widget build(BuildContext context) {
    if (_moduleOff) return _buildModuleOff(context);
    final canWrite = widget.scope.canWrite;
    final deletedView = _status == 'deleted';
    final usage = _usage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canWrite) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('document_create'),
            label: 'Belge Yükle',
            icon: Icons.upload_file_rounded,
            onPressed: _upload,
          ),
          const SizedBox(height: AppSpace.md),
          if (usage != null && usage.hasQuota) ...[
            AppCard(child: DocumentUsageBar(usage: usage)),
            const SizedBox(height: AppSpace.md),
          ],
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
              Text('Kategori', style: Theme.of(context).textTheme.titleSmall),
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
              if (canWrite) ...[
                const SizedBox(height: AppSpace.md),
                Text('Durum', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    ChoiceChip(
                      key: const ValueKey<String>('document_status_active'),
                      avatar: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('Yayında'),
                      selected: !deletedView,
                      onSelected: (_) => _selectStatus('active'),
                    ),
                    ChoiceChip(
                      key: const ValueKey<String>('document_status_deleted'),
                      avatar: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Silinenler'),
                      selected: deletedView,
                      onSelected: (_) => _selectStatus('deleted'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: deletedView ? 'Silinen belgeler' : 'Belgeler',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[ListExportButton(enabled: _loader.items.isNotEmpty, source: localExportSource(label: 'Belgeler', filenameBase: 'belgeler', headers: <String>['Belge', 'Kategori', 'Durum', 'Sürüm', 'İndirme', 'Yükleyen', 'Güncelleme'], rows: () => <List<Object?>>[for (final x in _loader.items) [x.title, x.category.label, x.status.label, x.versionCount, x.downloadCount, x.uploadedByName, exportDate(x.updatedAt ?? x.createdAt)]])), IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          )]),
        ),
        if (deletedView) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Silinen belgeler bir süre sonra kalıcı olarak silinir. Süre dolmadan geri yükleyebilirsiniz.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        CrmListBody<DocumentSummary>(
          loader: _loader,
          emptyIcon: deletedView
              ? Icons.delete_outline_rounded
              : Icons.folder_open_rounded,
          emptyTitle: deletedView ? 'Silinmiş belge yok.' : 'Henüz belge yok.',
          emptyMessage: deletedView
              ? null
              : (canWrite
                    ? 'Belge Yükle ile yönetmelik, tutanak ya da sözleşme gibi ilk belgeyi ekleyebilirsiniz.'
                    : null),
          filteredTitle: 'Bu arama ve süzgeç için belge bulunamadı.',
          filtered: _filtered,
          itemBuilder: (context, document) => DocumentAdminCard(
            document: document,
            showUploader: canWrite,
            onTap: () => _open(document),
          ),
        ),
      ],
    );
  }

  Widget _buildModuleOff(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('documents_module_off'),
      icon: Icons.folder_off_rounded,
      tone: AppTone.warning,
      title: 'Dosya Deposu bu site için kapalı.',
      message:
          'Modül açılınca yönetmelik, tutanak ve sözleşme gibi belgeler burada görünür.',
      child: widget.onOpenModules == null
          ? null
          : Column(
              children: [
                Text(
                  'Modüller ekranından açabilir ya da talep edebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: th.bodyMedium,
                ),
                const SizedBox(height: AppSpace.md),
                PrimaryActionButton(
                  key: const ValueKey<String>('documents_open_modules'),
                  label: 'Modüller',
                  icon: Icons.extension_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: widget.onOpenModules,
                ),
              ],
            ),
    );
  }
}
