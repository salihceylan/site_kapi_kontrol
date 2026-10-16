import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Denetim Kaydı" ekranı (yalnız süper kullanıcı): yönetim işlemlerinin değiştirilemez listesi
/// (tarih, kim, ne, site), site ve eylem filtresi, "Daha fazla yükle" ve aşağı çekip yenileme.
///
/// Kayıtlar yeniden eskiye `id DESC` sıralıdır; sonraki sayfa `before_id` ile istenir ve listenin
/// SONUNA eklenir (aynı id iki kez gösterilmez). Veriyi kendisi çeker; [AuditLogViewState.reload]
/// sayfa kabuğunun aşağı çekip yenilemesinden de çağrılır.
class AuditLogView extends StatefulWidget {
  const AuditLogView({super.key, required this.authService});

  final AuthService authService;

  /// Sayfa başına kayıt sayısı (sunucu varsayılanı).
  static const int pageSize = 50;

  /// Eylem filtresi seçenekleri: (sunucu `action` değeri, görünen ad). İlk seçenek "Tümü"dür.
  static const List<(String?, String)> actionFilters = <(String?, String)>[
    (null, 'Tümü'),
    ('module.enabled', 'Modül açıldı'),
    ('module.disabled', 'Modül kapatıldı'),
    ('staff_role.assigned', 'Rol verildi'),
    ('staff_role.removed', 'Rol kaldırıldı'),
    ('module_request.created', 'Talep oluşturuldu'),
    ('module_request.approved', 'Talep onaylandı'),
    ('module_request.rejected', 'Talep reddedildi'),
    ('module_request.cancelled', 'Talep geri çekildi'),
    ('person.created', 'Kişi eklendi'),
    ('person.updated', 'Kişi güncellendi'),
    ('person.deactivated', 'Kişi pasifleştirildi'),
    ('residency.added', 'İlişki eklendi'),
    ('residency.updated', 'İlişki güncellendi'),
    ('residency.ended', 'Taşındı'),
    ('apartment.updated', 'Daire güncellendi'),
    ('vehicle.added', 'Araç eklendi'),
    ('vehicle.removed', 'Araç kaldırıldı'),
    ('apartment.deleted', 'Daire silindi'),
    ('site_application.created', 'Site başvurusu yapıldı'),
    ('site_application.approved', 'Site başvurusu onaylandı'),
    ('site_application.rejected', 'Site başvurusu reddedildi'),
    ('site_application.cancelled', 'Site başvurusu iptal edildi'),
    ('platform_settings.updated', 'Platform ayarı güncellendi'),
  ];

  @override
  State<AuditLogView> createState() => AuditLogViewState();
}

class AuditLogViewState extends State<AuditLogView> {
  /// "Tüm siteler" seçeneğinin değeri (gerçek site kodları pozitiftir).
  static const int _allSites = 0;

  /// "Tümü" eylem seçeneğinin değeri (DropdownButton boş metni de ayrı bir değer olarak tutar).
  static const String _allActions = '';

  List<AuditLogEntry> _items = const <AuditLogEntry>[];
  int? _nextBeforeId;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;

  List<SiteRecord> _sites = const <SiteRecord>[];
  int? _siteFilter;
  String? _actionFilter;

  // Yarış koruması: her yeniden yükleme / süzgeç değişimi `_token`'ı, her "Daha fazla yükle"
  // `_moreToken`'ı artırır; yeniden yükleme `_moreToken`'ı da artırır. Eski imleçle gelen sayfa
  // (yenileme / süzgeç değişiminden önce başlamış) listeye eklenmez ve düğme durumunu bozmaz.
  int _token = 0;
  int _moreToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  String _messageOf(Object error, String fallback) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return fallback;
  }

  /// İlk sayfayı (ve site filtresi listesini) yeniden çeker; ekranda mevcut liste yenileme sürerken
  /// kalır. Sürmekte olan "Daha fazla yükle" iptal edilir (sonucu yok sayılır, düğme sıfırlanır).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    ++_moreToken;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
    final sitesFuture = _loadSites();
    try {
      final page = await widget.authService.listAuditLog(
        siteCode: _siteFilter,
        action: _actionFilter,
        limit: AuditLogView.pageSize,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _nextBeforeId = page.nextBeforeId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = _messageOf(
          e,
          'Denetim kaydı yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
    await sitesFuture;
  }

  /// Site filtresi listesi: hata olursa filtre gizli kalır (kayıtlar yine listelenir).
  Future<void> _loadSites() async {
    try {
      final page = await widget.authService.listSites(page: 1, pageSize: 100);
      if (!mounted) return;
      setState(() => _sites = page.sites);
    } catch (_) {
      // Filtre olmadan devam.
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBeforeId;
    if (before == null || _loadingMore || _loading) return;
    final more = ++_moreToken;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.authService.listAuditLog(
        siteCode: _siteFilter,
        action: _actionFilter,
        limit: AuditLogView.pageSize,
        beforeId: before,
      );
      // Bu arada yenileme / filtre değişimi oldu: eski imleçle gelen sayfa eklenmez (bayrağı yeni
      // yükleme zaten sıfırladı).
      if (!mounted || more != _moreToken) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items = <AuditLogEntry>[
          ..._items,
          ...page.items.where((e) => !known.contains(e.id)),
        ];
        _nextBeforeId = page.nextBeforeId;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || more != _moreToken) return;
      setState(() {
        _loadingMore = false;
        _moreError = _messageOf(
          e,
          'Daha fazla kayıt yüklenemedi. Tekrar deneyin.',
        );
      });
    }
  }

  void _changeSite(int value) {
    final next = value == _allSites ? null : value;
    if (next == _siteFilter) return;
    _applyFilter(() => _siteFilter = next);
  }

  void _changeAction(String value) {
    final next = value == _allActions ? null : value;
    if (next == _actionFilter) return;
    _applyFilter(() => _actionFilter = next);
  }

  void _applyFilter(VoidCallback change) {
    setState(() {
      change();
      _items = const <AuditLogEntry>[];
      _nextBeforeId = null;
    });
    unawaited(reload());
  }

  bool get _filtered => _siteFilter != null || _actionFilter != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    final Widget list;
    if (_loading && _items.isEmpty) {
      // İlk yükleme, filtre değişimi ve hata sonrası "Tekrar Dene": iskelet (boş durum yanıp sönmez).
      list = const ListSkeleton(rows: 3);
    } else if (_error != null && _items.isEmpty) {
      list = InlineNotice(message: _error!, onRetry: reload);
    } else if (_items.isEmpty) {
      list = EmptyCard(
        icon: Icons.history_rounded,
        title: _filtered
            ? 'Bu filtre için denetim kaydı yok.'
            : 'Henüz denetim kaydı yok.',
        message: 'Modül ve ek rol işlemleri burada listelenir.',
      );
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: reload),
            const SizedBox(height: AppSpace.md),
          ],
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: StaggeredEntry(
                index: i,
                child: AuditLogCard(entry: _items[i]),
              ),
            ),
          if (_moreError != null) ...[
            InlineNotice(message: _moreError!, onRetry: _loadMore),
            const SizedBox(height: AppSpace.md),
          ],
          if (_nextBeforeId != null)
            Align(
              alignment: Alignment.center,
              child: PrimaryActionButton(
                label: 'Daha fazla yükle',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: _loadingMore,
                // Yenileme sürerken eski imleçle yeni sayfa istenmez.
                onPressed: (_loadingMore || _loading) ? null : _loadMore,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Denetim Kaydı', icon: Icons.fact_check_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Yönetim işlemleri (modül açma/kapama, ek rol atama) değiştirilemez bir kayıt olarak tutulur.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Kayıtlar',
          trailing: IconButton(
            onPressed: _loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey<String>('audit_action_${_actionFilter ?? ''}'),
                isExpanded: true,
                initialValue: _actionFilter ?? _allActions,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Eylem filtresi',
                  prefixIcon: Icon(Icons.bolt_rounded),
                ),
                items: [
                  for (final (value, label) in AuditLogView.actionFilters)
                    DropdownMenuItem<String>(
                      value: value ?? _allActions,
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _changeAction(value);
                },
              ),
              if (_sites.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('audit_site_${_siteFilter}_${_sites.length}'),
                  isExpanded: true,
                  initialValue: _siteFilter ?? _allSites,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(
                    labelText: 'Site filtresi',
                    prefixIcon: Icon(Icons.filter_list_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: _allSites,
                      child: Text('Tüm siteler', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    for (final site in _sites)
                      DropdownMenuItem<int>(
                        value: site.id,
                        child: Text(
                          '${site.name} (${site.id})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _changeSite(value);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        list,
      ],
    );
  }
}
