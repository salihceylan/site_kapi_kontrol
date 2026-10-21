import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/helpers/list_export.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/contract_vendor_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/contract_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dış uygulamada bir adres açar (`tel:`, `mailto:`); açılamazsa false.
typedef ContractLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// "Firmalar" sekmesi: arama + Tümü / Aktif / Pasif süzgeci, firma kartları (telefona dokununca arama, e-postaya
/// dokununca e-posta uygulaması). Yazma yetkisi olana "Yeni Firma", "Düzenle", "Pasife al" (onaylı) / "Etkinleştir".
///
/// Firma listesi sunucuda sayfasızdır (`{items}`); tek istekte gelir. HATA ASLA "firma yok" demez.
class ContractVendorsTab extends StatefulWidget {
  const ContractVendorsTab({
    super.key,
    required this.service,
    required this.site,
    required this.canWrite,
    this.onOpenModules,
    this.launcher,
  });

  final ContractService service;
  final ContractSite site;
  final bool canWrite;
  final VoidCallback? onOpenModules;
  final ContractLauncher? launcher;

  @override
  State<ContractVendorsTab> createState() => ContractVendorsTabState();
}

class ContractVendorsTabState extends State<ContractVendorsTab>
    implements ContractReloadable {
  ContractVendorFilter _filter = ContractVendorFilter.all;
  String _query = '';
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  bool _moduleOff = false;
  final Set<int> _busy = <int>{};

  late final PagedLoader<ContractVendor> _loader = PagedLoader<ContractVendor>(
    fetch: (offset, limit) async {
      // Sayfasız uç: ilk çağrı tüm firmaları getirir.
      if (offset > 0) return (items: const <ContractVendor>[], total: offset);
      final items = await widget.service.listVendors(
        widget.site.code,
        active: _filter,
        query: _query,
      );
      _moduleOff = false;
      return (items: items, total: items.length);
    },
    keyOf: (item) => item.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Firmalar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: (error, fallback) {
      if (error is ApiException && error.code == 'MODULE_DISABLED') {
        _moduleOff = true;
      }
      return crmMessageOf(error, fallback);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void didUpdateWidget(ContractVendorsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        !identical(oldWidget.service, widget.service)) {
      _timer?.cancel();
      _search.clear();
      _query = '';
      _filter = ContractVendorFilter.all;
      _moduleOff = false;
      _busy.clear();
      _resetList();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _loader.reload();

  void _resetList() {
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _resetList();
  }

  void _applySearch() {
    _timer?.cancel();
    final next = _search.text.trim();
    if (next == _query && _loader.loadedOnce && _loader.error == null) return;
    _setFilter(() => _query = next);
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applySearch);
    setState(() {});
  }

  bool get _filtered => _query.isNotEmpty || _filter != ContractVendorFilter.all;

  bool _fits(ContractVendor vendor) => switch (_filter) {
    ContractVendorFilter.all => true,
    ContractVendorFilter.active => vendor.isActive,
    ContractVendorFilter.passive => !vendor.isActive,
  };

  /// Güncellenen firma listede yerine konur; süzgece artık uymuyorsa düşer.
  void _replace(ContractVendor updated) {
    final fits = _fits(updated);
    setState(() {
      final before = _loader.items.length;
      _loader.items = <ContractVendor>[
        for (final item in _loader.items)
          if (item.id != updated.id)
            item
          else if (fits)
            updated,
      ];
      _loader.total -= before - _loader.items.length;
    });
  }

  Future<void> _create() async {
    final created = await ContractVendorFormDialog.show(
      context,
      service: widget.service,
      siteCode: widget.site.code,
    );
    if (created == null || !mounted) return;
    AppSnack.show(context, 'Firma eklendi.', kind: AppSnackKind.success);
    unawaited(_loader.reload());
  }

  Future<void> _edit(ContractVendor vendor) async {
    final saved = await ContractVendorFormDialog.show(
      context,
      service: widget.service,
      siteCode: widget.site.code,
      vendor: vendor,
    );
    if (saved == null || !mounted) return;
    _replace(saved);
    AppSnack.show(context, 'Firma güncellendi.', kind: AppSnackKind.success);
  }

  Future<void> _toggleActive(ContractVendor vendor) async {
    if (_busy.contains(vendor.id)) return;
    final deactivate = vendor.isActive;
    if (deactivate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Firma pasife alınsın mı?',
          icon: Icons.pause_circle_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('contract_vendor_confirm_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('contract_vendor_confirm_ok'),
              onPressed: () => popIfCurrent(dialogContext, true),
              child: const Text('Pasife al'),
            ),
          ],
          child: Text(
            '"${vendor.displayName}" yeni sözleşmelerde seçilemez; mevcut sözleşmeleri etkilenmez. '
            'Daha sonra yeniden etkinleştirebilirsiniz.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy.add(vendor.id));
    try {
      final updated = await widget.service.setVendorActive(
        widget.site.code,
        vendor.id,
        !deactivate,
      );
      if (!mounted) return;
      _replace(updated);
      AppSnack.show(
        context,
        deactivate ? 'Firma pasife alındı.' : 'Firma etkinleştirildi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Firma güncellenemedi. Lütfen tekrar deneyin.'),
        kind: AppSnackKind.error,
      );
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 409)) {
        unawaited(_loader.reload());
      }
    } finally {
      if (mounted) setState(() => _busy.remove(vendor.id));
    }
  }

  Future<void> _launch(Uri uri, String fallbackText) async {
    final opened = await (widget.launcher ?? _defaultLauncher)(uri);
    if (opened || !mounted) return;
    // Açılamadı (uygun uygulama yok): değer panoya kopyalanır, kullanıcı elle kullanabilir.
    await Clipboard.setData(ClipboardData(text: fallbackText));
    if (!mounted) return;
    AppSnack.show(
      context,
      'Uygulama açılamadı; bilgi panoya kopyalandı.',
      kind: AppSnackKind.warning,
    );
  }

  VoidCallback? _callAction(ContractVendor vendor) {
    final phone = vendor.phone?.trim() ?? '';
    final dial = contractDialable(phone);
    if (dial == null) return null;
    return () => unawaited(_launch(Uri(scheme: 'tel', path: dial), phone));
  }

  VoidCallback? _emailAction(ContractVendor vendor) {
    final email = vendor.email?.trim() ?? '';
    if (email.isEmpty) return null;
    return () => unawaited(_launch(Uri(scheme: 'mailto', path: email), email));
  }

  @override
  Widget build(BuildContext context) {
    if (_moduleOff) {
      return ContractModuleOffCard(onOpenModules: widget.onOpenModules);
    }
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canWrite) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton.icon(
              key: const ValueKey<String>('contract_vendor_new'),
              onPressed: () => unawaited(_create()),
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Yeni Firma'),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('contract_vendor_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applySearch(),
                decoration: InputDecoration(
                  labelText: 'Firma ara',
                  hintText: 'Ad, yetkili veya telefon',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _applySearch();
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text('Durum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final entry in const <(ContractVendorFilter, String, String)>[
                    (ContractVendorFilter.all, 'all', 'Tümü'),
                    (ContractVendorFilter.active, 'active', 'Aktif'),
                    (ContractVendorFilter.passive, 'passive', 'Pasif'),
                  ])
                    ChoiceChip(
                      key: ValueKey<String>('contract_vendor_filter_${entry.$2}'),
                      label: Text(entry.$3),
                      selected: _filter == entry.$1,
                      onSelected: (_) {
                        if (_filter == entry.$1) return;
                        _setFilter(() => _filter = entry.$1);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Firmalar',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[ListExportButton(enabled: _loader.items.isNotEmpty, source: localExportSource(label: 'Firmalar', filenameBase: 'firmalar', headers: <String>['Firma', 'Kategori', 'Yetkili', 'Telefon', 'E-posta', 'Sözleşme sayısı', 'Durum'], rows: () => <List<Object?>>[for (final f in _loader.items) [f.name, f.category.label, f.contactName, f.phone, f.email, f.contractCount, f.isActive ? 'Aktif' : 'Pasif']])), IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          )]),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<ContractVendor>(
          loader: _loader,
          emptyIcon: Icons.business_outlined,
          emptyTitle: 'Henüz firma yok.',
          filtered: _filtered,
          filteredTitle: 'Bu süzgeç için firma bulunamadı.',
          emptyMessage: _filtered
              ? null
              : (widget.canWrite
                    ? 'Hizmet aldığınız firmaları "Yeni Firma" ile ekleyin; sözleşmeler bu firmalara bağlanır.'
                    : 'Yönetici bir firma eklediğinde burada görünür.'),
          itemBuilder: (context, vendor) => ContractVendorCard(
            key: ValueKey<String>('contract_vendor_card_${vendor.id}'),
            vendor: vendor,
            canWrite: widget.canWrite,
            busy: _busy.contains(vendor.id),
            onCall: _callAction(vendor),
            onEmail: _emailAction(vendor),
            onEdit: () => unawaited(_edit(vendor)),
            onToggleActive: () => unawaited(_toggleActive(vendor)),
          ),
        ),
      ],
    );
  }
}
