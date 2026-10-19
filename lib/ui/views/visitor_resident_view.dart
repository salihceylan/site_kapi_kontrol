import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/visitor_log_parts.dart';

/// Sakin "Ziyaretçi ve Kargo" ekranı (`visitor_log` modülü): kendi dairesine ait kargo / ziyaretçi kayıtları.
/// Görülmemiş kayıtlar kalın + "Yeni" rozetiyle listelenir; kart açılınca ayrıntı penceresi çıkar ve kayıt
/// sunucuda "görüldü" (`POST /app/visitor-entries/:id/seen`) işaretlenir.
///
/// - Birden çok sitede ([sites] >= 2) site süzgeci çıkar ve kartlarda site adı görünür.
/// - Yarışlar: site değişimi sırasında eski imleçle gelen sayfa listeye eklenmez ([CursorLoader]); dispose sonrası
///   yanıt yok sayılır; HATA ASLA "kayıt yok" demez; boş durum yalnız gerçekten boşken çizilir.
/// - Modül kapalıysa (403 `MODULE_DISABLED`) liste yerine "bu site için kapalı" kartı çıkar.
/// - [onUnreadChanged]: bir kayıt görüldü işaretlenince çağrılır (çekmece rozeti sunucudan tazelenir).
/// - [VisitorResidentViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class VisitorResidentView extends StatefulWidget {
  const VisitorResidentView({
    super.key,
    required this.authService,
    this.service,
    this.sites = const <PeopleSite>[],
    this.onUnreadChanged,
  });

  final AuthService authService;
  final VisitorLogService? service;

  /// Sakinin kayıt görebileceği (modül açık) siteler.
  final List<PeopleSite> sites;
  final VoidCallback? onUnreadChanged;

  @override
  State<VisitorResidentView> createState() => VisitorResidentViewState();
}

class VisitorResidentViewState extends State<VisitorResidentView> {
  static const int _allSites = 0;

  int? _siteFilter;
  int _unread = 0;
  bool _moduleOff = false;
  String _lastSignature = '';
  final Set<int> _marking = <int>{};

  late VisitorLogService _service =
      widget.service ?? VisitorLogService(authService: widget.authService);

  late final CursorLoader<VisitorEntry> _loader = CursorLoader<VisitorEntry>(
    fetch: (before) async {
      final page = await _service.listMine(
        siteCode: _siteFilter,
        limit: 30,
        beforeId: before,
      );
      if (before == null) {
        _moduleOff = false;
        // Okunmamış sayısı hafif `summary` ucundan (hata olursa listeden sayılır; ekran çökmez).
        try {
          _unread = await _service.unreadCount();
        } catch (_) {
          _unread = page.items.where((e) => e.unread).length;
        }
      }
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (item) => item.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Kayıtlarınız yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(VisitorResidentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? VisitorLogService(authService: widget.authService);
    }
    // Süzgeçteki site artık listede yoksa süzgeç kalkar.
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  void _applyFilters() {
    final signature = '${_siteFilter ?? ''}';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _loader.reset();
    unawaited(_loader.reload());
  }

  Future<void> _open(VisitorEntry entry) async {
    if (entry.unread && !_marking.contains(entry.id)) {
      _marking.add(entry.id);
      // Görüldü işareti arka planda: pencere beklemeden açılır; hata sessizdir (bir sonraki açılışta yinelenir).
      unawaited(
        _service
            .markSeen(entry.id)
            .then((_) {
              if (!mounted) return;
              setState(() {
                _loader.items = <VisitorEntry>[
                  for (final item in _loader.items)
                    if (item.id == entry.id)
                      item.copyWith(residentSeenAt: DateTime.now())
                    else
                      item,
                ];
                if (_unread > 0) _unread -= 1;
              });
              widget.onUnreadChanged?.call();
            })
            .catchError((Object _) {})
            .whenComplete(() => _marking.remove(entry.id)),
      );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _VisitorDetailDialog(
        entry: entry,
        showSite: widget.sites.length > 1,
        onClose: () => popIfCurrent<void>(dialogContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    final hasSite = widget.sites.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(
          title: 'Ziyaretçi ve Kargo',
          icon: Icons.door_front_door_rounded,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Dairenize gelen kargo ve ziyaretçileri görevli kaydeder; burada görürsünüz. E-posta ve telefon bildirimi yakında.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        if (multiSite) ...[
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('visitor_resident_site_${_siteFilter ?? 0}'),
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
                setState(() => _siteFilter = next);
                _applyFilters();
              },
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_unread > 0 && !_moduleOff) ...[
          InlineNotice(
            key: const ValueKey<String>('visitor_unread_notice'),
            tone: AppTone.warning,
            icon: Icons.notifications_active_rounded,
            message: _unread == 1
                ? 'Görülmemiş 1 kaydınız var.'
                : 'Görülmemiş $_unread kaydınız var.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Kayıtlar',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_moduleOff)
          const EmptyCard(
            key: ValueKey<String>('visitor_module_off'),
            icon: Icons.door_front_door_outlined,
            tone: AppTone.warning,
            title: 'Ziyaretçi ve kargo kaydı bu site için kapalı.',
            message:
                'Yönetim bu özelliği açtığında dairenize gelen kargo ve ziyaretçileri buradan görürsünüz.',
          )
        else if (!hasSite)
          const EmptyCard(
            icon: Icons.door_front_door_outlined,
            title: 'Kayıt görebileceğiniz site yok.',
            message:
                'Ziyaretçi ve kargo kayıtları, bir siteye daire sakini olarak bağlandığınızda ve yönetim özelliği açtığında burada görünür.',
          )
        else
          CursorListBody<VisitorEntry>(
            loader: _loader,
            emptyIcon: Icons.door_front_door_outlined,
            emptyTitle: _siteFilter != null
                ? 'Bu sitede kaydınız yok.'
                : 'Henüz kaydınız yok.',
            emptyMessage: _siteFilter != null
                ? null
                : 'Dairenize kargo ya da ziyaretçi geldiğinde görevlinin kaydı burada görünür.',
            itemBuilder: (context, item) => VisitorResidentCard(
              key: ValueKey<String>('visitor_card_${item.id}'),
              entry: item,
              showSite: multiSite,
              onTap: () => unawaited(_open(item)),
            ),
          ),
      ],
    );
  }
}

/// Sakin ayrıntı penceresi: tür, ad, daire, durum, geliş / kapanış saati, firma ve not (görevli adları sakine
/// GÖSTERİLMEZ; sunucu zaten göndermez).
class _VisitorDetailDialog extends StatelessWidget {
  const _VisitorDetailDialog({
    required this.entry,
    required this.showSite,
    required this.onClose,
  });

  final VisitorEntry entry;
  final bool showSite;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final e = entry;
    final company = e.company?.trim() ?? '';
    final note = e.note?.trim() ?? '';
    final site = e.siteName.trim();
    Widget row(String label, String value, {String? key}) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: th.labelMedium?.copyWith(color: p.textSecondary)),
          Text(value, key: key == null ? null : ValueKey<String>(key), style: th.bodyLarge),
        ],
      ),
    );
    return AppDialog(
      title: e.kind.label,
      subtitle: e.displayName,
      icon: visitorKindIcon(e.kind),
      actions: [
        ElevatedButton(
          key: const ValueKey<String>('visitor_resident_detail_close'),
          onPressed: onClose,
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [VisitorStatusChip(e.status)],
          ),
          const SizedBox(height: AppSpace.md),
          row('Daire', e.placeText),
          if (showSite && site.isNotEmpty) row('Site', site),
          if (company.isNotEmpty)
            row(e.kind == VisitorKind.cargo ? 'Takip / ek bilgi' : 'Firma', company),
          if (e.arrivedAt != null)
            row('Geliş', formatIstanbulDateTime(e.arrivedAt)),
          if (e.completedAt != null)
            row('Kapanış', formatIstanbulDateTime(e.completedAt)),
          if (note.isNotEmpty) row('Not', note, key: 'visitor_resident_detail_note'),
        ],
      ),
    );
  }
}
