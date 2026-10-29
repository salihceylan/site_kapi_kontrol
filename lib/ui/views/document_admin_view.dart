import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/document_admin_list.dart';
import 'package:site_kapi_kontrol/ui/widgets/drive_storage_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Yönetici "Dosya Deposu" ekranının gövdesi (Platform Faz 3b-A + D1, tek modül `drive_storage`): site seçici + (yazma
/// yetkisi varsa) sitenin Google Drive bağlantısı ([DriveStorageCard], ÜSTTE) + Belgeler listesi ([DocumentAdminList];
/// kota çubuğu YOK: dosyalar yalnız Drive'dadır, Drive bağlı değilse yükleme pasiftir).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yazma yetkisi vardır.
/// - [sites]: açıkça verilen siteler (`GET /app/my-modules`: `drive_storage` modülü AÇIK olan yönetilen siteler
///   yazma, kurul üyesi olunan siteler salt okunur). Menü kapısı ve site listesi HomePage'dedir; sunucu yine de
///   her çağrıda yetkiyi ve modül durumunu doğrular (403 `FORBIDDEN_ROLE` / `MODULE_DISABLED`).
/// - Kurul üyesi (canWrite false) SALT OKUR: hiçbir yazma düğmesi çizilmez, "yalnızca görüntüleyebilirsiniz" notu
///   gösterilir ve yönetici belgeleri sunucudan zaten gelmez.
///
/// Site değişince liste durumu atılır (eski sitenin yanıtı yeni sitenin ekranına yazılamaz). Veriyi kendisi
/// çeker; [DocumentAdminViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden de çağrılır.
class DocumentAdminView extends StatefulWidget {
  const DocumentAdminView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <PeopleSite>[],
    this.onOpenModules,
    this.picker = const FilePickerDocumentPicker(),
    this.sharer,
  });

  final AuthService authService;

  /// Belge servisi; verilmezse oturumdan kurulur (testlerde sahte verilir).
  final DocumentService? service;
  final bool manageAllSites;
  final List<PeopleSite> sites;
  final VoidCallback? onOpenModules;
  final DocumentPicker picker;
  final DocumentFileSharer? sharer;

  @override
  State<DocumentAdminView> createState() => DocumentAdminViewState();
}

class DocumentAdminViewState extends State<DocumentAdminView> {
  List<PeopleSite> _sites = const <PeopleSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;

  /// Seçili sitenin Google Drive bağlantısı (Drive kartı bildirir): false iken "Belge Yükle" pasiftir; null = bilinmiyor.
  bool? _driveConnected;

  late DocumentService _service =
      widget.service ?? DocumentService(authService: widget.authService);

  // Site değişince yenilenir: eski sitenin liste durumu (ve uçuştaki yanıtları) atılır.
  GlobalKey<DocumentAdminListState> _listKey =
      GlobalKey<DocumentAdminListState>();

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(DocumentAdminView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? DocumentService(authService: widget.authService);
    }
    if (oldWidget.manageAllSites != widget.manageAllSites ||
        !listEquals(oldWidget.sites, widget.sites)) {
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_sitesToken;
    super.dispose();
  }

  PeopleSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  /// Siteleri ve görünen listeyi yeniden çeker (mevcut ekran yenileme sürerken korunur).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <PeopleSite>[];
      if (widget.manageAllSites) {
        // Süper kullanıcıda site sayısı 100'ü aşabilir: onaylı siteler sayfa sayfa toplanır (üst sınır 50
        // sayfa), seçici ilk 100 siteyle sınırlı kalmaz.
        var pageNo = 1;
        var fetched = 0;
        while (true) {
          final page = await widget.authService.listSites(
            page: pageNo,
            pageSize: 100,
            approvalStatus: 'approved',
          );
          for (final site in page.sites) {
            if (site.isApproved && !merged.any((m) => m.code == site.id)) {
              merged.add(
                PeopleSite(code: site.id, name: site.name, canWrite: true),
              );
            }
          }
          fetched += page.sites.length;
          if (page.sites.isEmpty || fetched >= page.total || pageNo >= 50) {
            break;
          }
          if (!mounted || token != _sitesToken) return;
          pageNo++;
        }
      }
      for (final site in widget.sites) {
        if (!merged.any((m) => m.code == site.code)) merged.add(site);
      }
      if (!mounted || token != _sitesToken) return;
      final keep = _siteCode != null && merged.any((s) => s.code == _siteCode);
      final next = keep
          ? _siteCode
          : (merged.isEmpty ? null : merged.first.code);
      final siteChanged = next != _siteCode;
      final previous = _site;
      setState(() {
        _sites = merged;
        _loadingSites = false;
        _sitesLoadedOnce = true;
        if (siteChanged) _resetList(next);
      });
      // Aynı site: ekrandaki liste yeniden çekilir. Yetki değiştiyse (ör. kurul üyeliği yönetime döndü) liste
      // durumu atılır.
      final current = _site;
      if (!siteChanged && current != null) {
        if (previous != null && previous.canWrite != current.canWrite) {
          setState(() => _resetList(current.code));
        } else {
          unawaited(_listKey.currentState?.reload() ?? Future<void>.value());
        }
      }
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = crmMessageOf(
          e,
          'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  void _resetList(int? siteCode) {
    _siteCode = siteCode;
    _listKey = GlobalKey<DocumentAdminListState>();
  }

  /// Seçicide yalnız site adı görünür (site kodu teknik bir ifadedir). Aynı ad birden çok sitede varsa
  /// ayırt etmek için sıra numarası eklenir ("Gül Sitesi (2)").
  String _siteLabel(PeopleSite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() => _resetList(code));
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) {
        return const ListSkeleton(rows: 2);
      }
      if (_sitesError != null) {
        return InlineNotice(message: _sitesError!, onRetry: reload);
      }
      return const EmptyCard(
        icon: Icons.apartment_rounded,
        title: 'Kayıtlı site bulunamadı.',
        message:
            'Dosya Deposu modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, PeopleSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final scope = PeopleScope(
      authService: widget.authService,
      siteCode: site.code,
      siteName: site.name,
      canWrite: site.canWrite,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sitesError != null) ...[
          InlineNotice(message: _sitesError!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        if (_sites.length > 1)
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>(
                'documents_site_${site.code}_${_sites.length}',
              ),
              isExpanded: true,
              initialValue: site.code,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(
                labelText: 'Site',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              items: [
                for (final s in _sites)
                  DropdownMenuItem<int>(
                    value: s.code,
                    // Uzun ad satırda kısalır; tam ad uzun basınca tooltip'te görünür (ekran okuyucu zaten tam
                    // metni okur).
                    child: Tooltip(
                      message: _siteLabel(s),
                      child: Text(
                        _siteLabel(s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _selectSite(value);
              },
            ),
          )
        else
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [InfoChip(site.label)],
          ),
        const SizedBox(height: AppSpace.md),
        if (!site.canWrite) ...[
          const InlineNotice(
            key: ValueKey<String>('documents_read_only_note'),
            tone: AppTone.info,
            icon: Icons.visibility_rounded,
            message:
                'Yönetim kurulu üyesi olarak belgeleri yalnızca görüntüleyebilirsiniz. Yalnız yöneticilere açık '
                'belgeler görünmez.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // Google Drive bağlantısı Belgeler ile aynı modülün parçasıdır: yalnız yönetim (yazma) yetkisinde; kurul üyesi görmez.
        // Görünüş sırası: Drive kartı ÜSTTE, belge listesi ALTTA. Sunucu depolama kotası YOKTUR: dosyalar yalnız sitenin Drive'ındadır;
        // Drive bağlı değilse "Belge Yükle" pasiftir.
        if (site.canWrite) ...[
          DriveStorageCard(
            key: ValueKey<String>('documents_drive_${site.code}'),
            authService: widget.authService,
            siteCode: site.code,
            onConnectedChanged: (connected) {
              if (mounted && connected != _driveConnected) setState(() => _driveConnected = connected);
            },
          ),
          const SizedBox(height: AppSpace.xl),
        ],
        DocumentAdminList(
          key: _listKey,
          scope: scope,
          service: _service,
          picker: widget.picker,
          sharer: widget.sharer,
          onOpenModules: widget.onOpenModules,
          driveConnected: site.canWrite ? _driveConnected : null,
        ),
      ],
    );
  }
}
