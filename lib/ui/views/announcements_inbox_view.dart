import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_read_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';

/// Sakin "Duyurular" gelen kutusu (Platform Faz 3a): kronolojik liste (`published_at DESC`), okunmamış
/// nokta + kalın başlık, acil rozeti, aşağı çek yenile ([AnnouncementsInboxViewState.reload]), "Daha fazla
/// yükle" (`next_before_id` imleci) ve "Tümünü okundu yap".
///
/// - Duyuruyu açınca tam metin görünür ve okundu yazılır ([AnnouncementReadDialog]); yazım başarısızsa
///   duyuru listede okunmamış kalır.
/// - Birden çok siteye bağlı sakinde ([sites] >= 2) site süzgeci çıkar (`site_code`); "Tümünü okundu yap"
///   o süzgece uyar.
/// - [notifier] verilirse okuma/tümünü okundu işlemleri çekmece rozetini ve Panel'deki acil şeridi hemen
///   günceller.
///
/// Yarışlar: site süzgeci değişimi / yenileme sırasında eski imleçle gelen sayfa listeye eklenmez
/// ([CursorLoader]); dispose sonrası yanıt yok sayılır; hata asla "duyuru yok" demez.
class AnnouncementsInboxView extends StatefulWidget {
  const AnnouncementsInboxView({
    super.key,
    required this.authService,
    this.notifier,
    this.sites = const <PeopleSite>[],
  });

  final AuthService authService;
  final AnnouncementNotifier? notifier;

  /// Sakinin duyuru alabileceği siteler (süzgeç yalnız 2 ve üstünde çıkar).
  final List<PeopleSite> sites;

  @override
  State<AnnouncementsInboxView> createState() => AnnouncementsInboxViewState();
}

class AnnouncementsInboxViewState extends State<AnnouncementsInboxView> {
  static const int _allSites = 0;

  int? _siteFilter;
  String _lastSignature = 'null';
  bool _markingAll = false;
  final RetryLock _retry = RetryLock();
  String? _actionError;

  late final CursorLoader<ResidentAnnouncement> _loader = CursorLoader<ResidentAnnouncement>(
    fetch: (before) async {
      final page = await widget.authService.listMyAnnouncements(
        limit: 30,
        beforeId: before,
        siteCode: _siteFilter,
      );
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (a) => a.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Duyurular yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
    final summary = widget.notifier?.summary;
    if (summary != null) {
      _latestSeeded = true;
      _knownLatest = summary.latestSignature;
    }
    widget.notifier?.addListener(_onNotifier);
  }

  @override
  void didUpdateWidget(AnnouncementsInboxView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notifier, widget.notifier)) {
      oldWidget.notifier?.removeListener(_onNotifier);
      widget.notifier?.addListener(_onNotifier);
    }
    // Süzgeçte olan site artık listede yoksa süzgeç kalkar.
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      _applyFilter();
    }
  }

  @override
  void dispose() {
    widget.notifier?.removeListener(_onNotifier);
    _retry.dispose();
    _loader.dispose();
    super.dispose();
  }

  /// Sunucu özeti yeni bir "en son duyuru" bildirdiyse liste de yenilenir (sayfa yenilemeden çalışır).
  String? _knownLatest;
  bool _latestSeeded = false;

  void _onNotifier() {
    final summary = widget.notifier?.summary;
    if (summary != null) {
      final latest = summary.latestSignature;
      if (!_latestSeeded) {
        _latestSeeded = true;
        _knownLatest = latest;
      } else if (latest != _knownLatest) {
        _knownLatest = latest;
        if (!_loader.loading) unawaited(_loader.reload());
      }
    }
    if (mounted) setState(() {});
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  void _applyFilter() {
    final signature = '$_siteFilter';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _loader.reset();
    unawaited(_loader.reload());
  }

  Future<void> _open(ResidentAnnouncement announcement) {
    return AnnouncementReadDialog.show(
      context,
      authService: widget.authService,
      announcement: announcement,
      onRead: (updated) {
        if (!mounted) return;
        _loader.updateItem(updated.id, (old) => old.copyWith(isRead: true));
        widget.notifier?.noteRead(updated.id, urgent: updated.isUrgent);
        unawaited(widget.notifier?.refresh() ?? Future<bool?>.value(null));
      },
      onGone: () {
        if (mounted) unawaited(_loader.reload());
        unawaited(widget.notifier?.refresh() ?? Future<bool?>.value(null));
      },
    );
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _retry.locked) return;
    setState(() {
      _markingAll = true;
      _actionError = null;
    });
    final filter = _siteFilter;
    try {
      final marked = await widget.authService.markAllAnnouncementsRead(siteCode: filter);
      if (!mounted) return;
      // Yazım sunucuda tamamlandı: yüklü liste de okundu görünür (ardından sunucudan tazelenir).
      _loader.updateAll((old) => old.isRead ? old : old.copyWith(isRead: true));
      widget.notifier?.noteAllRead(allSites: filter == null);
      unawaited(widget.notifier?.refresh() ?? Future<bool?>.value(null));
      setState(() => _markingAll = false);
      // Yazım sırasında süren eski bir yenilemenin yanıtı okunmamış görüntüyü geri getirmesin: sunucudan tazele.
      unawaited(_loader.reload());
      AppSnack.show(
        context,
        marked > 0 ? '$marked duyuru okundu olarak işaretlendi.' : 'Okunmamış duyuru yok.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _markingAll = false;
        _actionError = limited
            ? RetryLock.messageFor(e)
            : crmMessageOf(
                e,
                'Duyurular okundu yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  int get _unreadLoaded => _loader.items.where((a) => !a.isRead).length;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final unread = widget.notifier?.unreadCount ?? _unreadLoaded;
    final multiSite = widget.sites.length > 1;
    // Okunmamış duyuru varsa (sunucu sayısı ya da yüklü liste) düğme etkindir.
    final hasUnread = unread > 0 || _unreadLoaded > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (multiSite) ...[
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('announcements_inbox_site_${_siteFilter ?? 0}'),
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
                  child: Text('Tüm siteler', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                for (final s in widget.sites)
                  DropdownMenuItem<int>(
                    value: s.code,
                    child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                final next = value == _allSites ? null : value;
                if (next == _siteFilter) return;
                _siteFilter = next;
                _applyFilter();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Gelen duyurular',
          count: unread > 0 ? unread : null,
          countSuffix: ' okunmamış',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PrimaryActionButton(
          key: const ValueKey<String>('announcements_mark_all'),
          label: 'Tümünü okundu yap',
          icon: Icons.done_all_rounded,
          variant: AppButtonVariant.tonal,
          loading: _markingAll,
          onPressed: (_markingAll || _retry.locked || !hasUnread) ? null : _markAllRead,
        ),
        const SizedBox(height: AppSpace.md),
        if (_actionError != null) ...[
          InlineNotice(message: _actionError!),
          const SizedBox(height: AppSpace.md),
        ],
        CursorListBody<ResidentAnnouncement>(
          loader: _loader,
          emptyIcon: Icons.campaign_rounded,
          emptyTitle: 'Henüz duyuru yok.',
          emptyMessage: 'Yönetimin size gönderdiği duyurular burada görünür.',
          itemBuilder: (context, announcement) => AnnouncementInboxCard(
            announcement: announcement,
            showSite: multiSite,
            onTap: () => _open(announcement),
          ),
        ),
      ],
    );
  }
}
