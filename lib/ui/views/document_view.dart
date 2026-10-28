import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/document_admin_view.dart';
import 'package:site_kapi_kontrol/ui/views/document_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Dosya Deposu" ekranı (Platform Faz 3b-A + D1; Belgeler ve Google Drive TEK modülde: `drive_storage`). Kullanıcının rolüne göre iki görünüm barındırır:
///
/// - **Yönetim** ([manageAllSites] / [manageSites] / [readOnlySites]): yönetici / süper kullanıcı: yükleme,
///   sürüm, düzenleme, silme, çöp kutusu; kurul üyesi aynı listeyi SALT OKUR.
/// - **Sakin** ([showResident] / [residentSites]): yalnız kendi kitlesinde olduğu belgeleri görür ve indirir.
///
/// İkisi birden varsa (yönetim kurulu üyesi olan sakin) üstte iki seçenek çıkar; tek görünüm varsa seçenek
/// çizilmez. Hiçbiri yoksa açıklayıcı boş durum gösterilir. Görevli (STAFF) için ekran yoktur (menüde çıkmaz).
/// [DocumentsViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class DocumentsView extends StatefulWidget {
  const DocumentsView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.manageSites = const <PeopleSite>[],
    this.showResident = false,
    this.residentSites = const <PeopleSite>[],
    this.onOpenModules,
    this.picker = const FilePickerDocumentPicker(),
    this.sharer,
  });

  final AuthService authService;
  final DocumentService? service;

  /// Süper kullanıcı: tüm onaylı siteler, yazma yetkisiyle.
  final bool manageAllSites;

  /// Yönetim görünümündeki siteler: `canWrite` true = yönetilen site, false = yalnız kurul üyesi (salt okur).
  final List<PeopleSite> manageSites;
  final bool showResident;
  final List<PeopleSite> residentSites;
  final VoidCallback? onOpenModules;
  final DocumentPicker picker;
  final DocumentFileSharer? sharer;

  @override
  State<DocumentsView> createState() => DocumentsViewState();
}

enum _Mode { manage, resident }

class DocumentsViewState extends State<DocumentsView> {
  _Mode? _chosen;
  final GlobalKey<DocumentAdminViewState> _adminKey =
      GlobalKey<DocumentAdminViewState>();
  final GlobalKey<DocumentResidentViewState> _residentKey =
      GlobalKey<DocumentResidentViewState>();

  late DocumentService _service =
      widget.service ?? DocumentService(authService: widget.authService);

  @override
  void initState() {
    super.initState();
    // Önceki oturumdan kalmış (süreç öldürüldüğü için silinememiş) geçici belge kopyalarını süpür; paylaşımda
    // olabilecek yeni kopyalara dokunmaz (yalnız 10 dakikadan eskiler). Hata fırlatmaz.
    unawaited(DocumentFileSharer.sweepAll(staleAfter: const Duration(minutes: 10)));
  }

  @override
  void didUpdateWidget(DocumentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? DocumentService(authService: widget.authService);
    }
  }

  bool get _hasManage => widget.manageAllSites || widget.manageSites.isNotEmpty;
  bool get _hasResident => widget.showResident;

  /// Gösterilen görünüm: seçilen hâlâ varsa o, yoksa yönetim, yoksa sakin.
  _Mode? get _mode {
    final chosen = _chosen;
    if (chosen == _Mode.manage && _hasManage) return _Mode.manage;
    if (chosen == _Mode.resident && _hasResident) return _Mode.resident;
    if (_hasManage) return _Mode.manage;
    if (_hasResident) return _Mode.resident;
    return null;
  }

  /// Çekip yenileme: görünen görünümün verisini yeniden çeker.
  Future<void> reload() async {
    switch (_mode) {
      case _Mode.manage:
        await (_adminKey.currentState?.reload() ?? Future<void>.value());
      case _Mode.resident:
        await (_residentKey.currentState?.reload() ?? Future<void>.value());
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final mode = _mode;
    final Widget content;
    switch (mode) {
      case _Mode.manage:
        content = DocumentAdminView(
          key: _adminKey,
          authService: widget.authService,
          service: _service,
          manageAllSites: widget.manageAllSites,
          sites: widget.manageSites,
          onOpenModules: widget.onOpenModules,
          picker: widget.picker,
          sharer: widget.sharer,
        );
      case _Mode.resident:
        content = DocumentResidentView(
          key: _residentKey,
          authService: widget.authService,
          service: _service,
          sites: widget.residentSites,
          sharer: widget.sharer,
        );
      case null:
        content = const EmptyCard(
          icon: Icons.folder_open_rounded,
          title: 'Belge bulunamadı.',
          message: 'Belgeler, bir siteye bağlı olduğunuzda burada görünür.',
        );
    }
    final description = switch (mode) {
      _Mode.manage =>
        'Yönetmelik, toplantı tutanağı ve sözleşme gibi belgeleri yükleyin; sakinlere, kurula ya da yalnız '
            'yöneticilere açın. Sitenin dosyalarını kendi Google Drive hesabınızda saklamak için en alttaki Google Drive bölümünü kullanın.',
      _Mode.resident =>
        'Yönetimin sizinle paylaştığı belgeleri buradan açabilir ya da kaydedebilirsiniz.',
      null => 'Sitenizin belgeleri ve dosyaları burada görünür.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Dosya Deposu', icon: Icons.folder_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(description, style: th.bodyMedium),
        const SizedBox(height: AppSpace.lg),
        if (_hasManage && _hasResident) ...[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('documents_mode_manage'),
                avatar: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Yönetim görünümü'),
                selected: mode == _Mode.manage,
                onSelected: (_) => setState(() => _chosen = _Mode.manage),
              ),
              ChoiceChip(
                key: const ValueKey<String>('documents_mode_resident'),
                avatar: const Icon(Icons.person_rounded, size: 18),
                label: const Text('Belgelerim'),
                selected: mode == _Mode.resident,
                onSelected: (_) => setState(() => _chosen = _Mode.resident),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        content,
      ],
    );
  }
}
