import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/reservation_booking_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/reservation_resident_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/concierge_resident_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

/// Sakin "Rezervasyon" ekranı (`reservation` modülü): ortak alanlar (alan -> gün -> boş saat -> rezervasyon),
/// "Rezervasyonlarım" (durum rozeti, yaklaşan / geçmiş, iptal süresi içinde iptal) ve "Konsiyerj" (talep aç / iptal).
///
/// - Birden çok sitede ([sites] >= 2) site süzgeci çıkar ve kartlarda site adı görünür.
/// - Yarışlar: süzgeç / site değişimi sırasında eski imleçle gelen sayfa listeye eklenmez ([CursorLoader]); HATA ASLA
///   "kayıt yok" demez (liste boşken hata + "Tekrar Dene"); modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart.
/// - Rol / kapasite / iptal süresi kararını sunucu verir; istemci 403 / 404 / 409 yanıtlarını düz Türkçe gösterir.
/// - Görülmemiş yönetim kararı / güncellemesi (`unread`) kartta "Yeni güncelleme" çipi + uyarı tonu, sekme etiketinde
///   sayı rozeti olarak görünür (İş Takibi ile aynı); karta dokununca ayrıntı açılır ve `seen` çağrılır (rozet söner).
/// - [ReservationResidentViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır (rozetleri de tazeler).
class ReservationResidentView extends StatefulWidget {
  const ReservationResidentView({
    super.key,
    required this.authService,
    this.service,
    this.sites = const <PeopleSite>[],
  });

  final AuthService authService;
  final ReservationService? service;

  /// Sakinin rezervasyon yapabileceği (modül açık) siteler.
  final List<PeopleSite> sites;

  @override
  State<ReservationResidentView> createState() => ReservationResidentViewState();
}

class ReservationResidentViewState extends State<ReservationResidentView> {
  static const int _allSites = 0;

  int _tab = 0;
  int? _siteFilter;

  /// Sekme rozetleri: görülmemiş kararı / güncellemesi olan kayıt sayısı (sunucu `unread_count`). Açılışta ve çekip
  /// yenilemede hafif sayaç isteğiyle, sekme açılınca liste yanıtıyla, görüldü işaretinde yerelde güncellenir.
  int _unreadReservations = 0;
  int _unreadConcierge = 0;
  int _countsSeq = 0;
  final GlobalKey _areasKey = GlobalKey();
  final GlobalKey _mineKey = GlobalKey();
  final GlobalKey _conciergeKey = GlobalKey();

  late ReservationService _service =
      widget.service ?? ReservationService(authService: widget.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshUnreadCounts());
  }

  @override
  void didUpdateWidget(ReservationResidentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    var refresh = false;
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? ReservationService(authService: widget.authService);
      refresh = true;
    }
    // Süzgeçteki site artık listede yoksa süzgeç kalkar.
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      refresh = true;
    }
    if (refresh) unawaited(_refreshUnreadCounts());
  }

  /// Etkin sekmenin listesini ve sekme rozetlerini yeniden çeker (sayfa kabuğunun çekip yenilemesi).
  Future<void> reload() async {
    final key = switch (_tab) {
      0 => _areasKey,
      1 => _mineKey,
      _ => _conciergeKey,
    };
    final state = key.currentState;
    await Future.wait<void>([
      if (state is ReservationReloadable)
        (state as ReservationReloadable).reload(),
      _refreshUnreadCounts(),
    ]);
  }

  /// Rozet sayaçlarını iki hafif liste isteğiyle tazeler. Hata sessizdir: rozet yardımcıdır, son bilinen değer kalır
  /// (sekme açılınca liste yanıtıyla eşitlenir). Eski yanıt (daha yeni bir tazeleme başladı, site süzgeci / servis
  /// değişti) uygulanmaz.
  Future<void> _refreshUnreadCounts() async {
    if (widget.sites.isEmpty) return;
    final seq = ++_countsSeq;
    final service = _service;
    final filter = _siteFilter;
    try {
      final counts = await service.unreadCounts(siteCode: filter);
      if (!mounted ||
          seq != _countsSeq ||
          !identical(service, _service) ||
          filter != _siteFilter) {
        return;
      }
      _setUnread(reservations: counts.reservations, concierge: counts.concierge);
    } catch (_) {
      // Rozet yardımcıdır; kullanıcıya hata gösterilmez.
    }
  }

  void _setUnread({int? reservations, int? concierge}) {
    if (!mounted) return;
    final nextReservations = reservations ?? _unreadReservations;
    final nextConcierge = concierge ?? _unreadConcierge;
    if (nextReservations == _unreadReservations &&
        nextConcierge == _unreadConcierge) {
      return;
    }
    setState(() {
      _unreadReservations = nextReservations;
      _unreadConcierge = nextConcierge;
    });
  }

  /// Sekme etiketi; okunmamış varsa yanında sayı rozeti (dar ekranda metin kısalır, rozet kalır).
  Widget _tabLabel(String text, int unread, String badgeKey) {
    if (unread <= 0) return Text(text);
    return Semantics(
      label: '$text, $unread yeni güncelleme',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(text)),
          const SizedBox(width: AppSpace.xs),
          ReservationUnreadBadge(key: ValueKey<String>(badgeKey), count: unread),
        ],
      ),
    );
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  void _onBooked(ReservationCreateResult result) {
    final pending = result.reservation.status == ReservationStatus.beklemede;
    AppSnack.show(
      context,
      result.replayed
          ? 'Bu rezervasyon zaten kayıtlıydı.'
          : (pending
                ? 'Rezervasyon talebiniz alındı. Yönetici onayı bekleniyor.'
                : 'Rezervasyonunuz onaylandı.'),
      kind: AppSnackKind.success,
    );
    // Yeni kayıt "Rezervasyonlarım > Yaklaşan" listesindedir.
    setState(() => _tab = 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(
          title: 'Rezervasyon',
          icon: Icons.event_available_rounded,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Ortak alanları ayırtın, rezervasyonlarınızı izleyin ve konsiyerj taleplerinizi iletin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        if (widget.sites.isEmpty)
          const EmptyCard(
            icon: Icons.event_busy_rounded,
            title: 'Rezervasyon yapabileceğiniz site yok.',
            message:
                'Rezervasyon ve konsiyerj, bir siteye daire sakini olarak bağlandığınızda ve yönetim özelliği açtığında burada görünür.',
          )
        else ...[
          if (multiSite) ...[
            AppCard(
              child: DropdownButtonFormField<int>(
                key: ValueKey<String>('rez_site_${_siteFilter ?? 0}'),
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
                  setState(() => _siteFilter = next);
                  unawaited(_refreshUnreadCounts());
                },
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final entry in <(int, String, String, int)>[
                (0, 'rez_tab_areas', 'Alanlar', 0),
                (1, 'rez_tab_mine', 'Rezervasyonlarım', _unreadReservations),
                (2, 'rez_tab_concierge', 'Konsiyerj', _unreadConcierge),
              ])
                ChoiceChip(
                  key: ValueKey<String>(entry.$2),
                  label: _tabLabel(entry.$3, entry.$4, '${entry.$2}_unread'),
                  selected: _tab == entry.$1,
                  onSelected: (_) => _selectTab(entry.$1),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          switch (_tab) {
            0 => _AreasTab(
              key: _areasKey,
              service: _service,
              siteFilter: _siteFilter,
              multiSite: multiSite,
              onBooked: _onBooked,
            ),
            1 => _MineTab(
              key: _mineKey,
              service: _service,
              siteFilter: _siteFilter,
              multiSite: multiSite,
              onUnreadCount: (count) => _setUnread(reservations: count),
            ),
            _ => ConciergeResidentTab(
              key: _conciergeKey,
              service: _service,
              sites: widget.sites,
              siteFilter: _siteFilter,
              onUnreadCount: (count) => _setUnread(concierge: count),
            ),
          },
        ],
      ],
    );
  }
}

/// "Alanlar" sekmesi: aktif ortak alanlar ve "Rezervasyon Yap".
class _AreasTab extends StatefulWidget {
  const _AreasTab({
    super.key,
    required this.service,
    required this.siteFilter,
    required this.multiSite,
    required this.onBooked,
  });

  final ReservationService service;
  final int? siteFilter;
  final bool multiSite;
  final ValueChanged<ReservationCreateResult> onBooked;

  @override
  State<_AreasTab> createState() => _AreasTabState();
}

class _AreasTabState extends State<_AreasTab> implements ReservationReloadable {
  bool _moduleOff = false;

  late final CursorLoader<ReservationArea> _loader = CursorLoader<ReservationArea>(
    fetch: (_) async {
      final areas = await widget.service.listAreas(siteCode: widget.siteFilter);
      _moduleOff = false;
      return (items: areas, next: null);
    },
    keyOf: (area) => area.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Alanlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(_AreasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteFilter != widget.siteFilter ||
        !identical(oldWidget.service, widget.service)) {
      _loader.reset();
      unawaited(_loader.reload());
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _loader.reload();

  Future<void> _book(ReservationArea area) async {
    final result = await ReservationBookingDialog.show(
      context,
      service: widget.service,
      area: area,
    );
    if (result == null || !mounted) return;
    widget.onBooked(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_moduleOff) return const ReservationModuleOffCard();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Ortak alanlar',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<ReservationArea>(
          loader: _loader,
          emptyIcon: Icons.meeting_room_rounded,
          emptyTitle: 'Rezervasyona açık alan yok.',
          emptyMessage: 'Yönetim bir ortak alan tanımladığında burada görünür.',
          itemBuilder: (context, area) => ReservationAreaCard(
            area: area,
            showSite: widget.multiSite,
            footer: PrimaryActionButton(
              key: ValueKey<String>('rez_book_${area.id}'),
              label: 'Rezervasyon Yap',
              icon: Icons.event_available_rounded,
              onPressed: () => unawaited(_book(area)),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Rezervasyonlarım" sekmesi: yaklaşan / geçmiş / tümü, ayrıntı (görüldü işareti) ve iptal. Süzgecin gizlediği okunmamış
/// karar varsa uyarı + "Tümünü göster".
class _MineTab extends StatefulWidget {
  const _MineTab({
    super.key,
    required this.service,
    required this.siteFilter,
    required this.multiSite,
    this.onUnreadCount,
  });

  final ReservationService service;
  final int? siteFilter;
  final bool multiSite;

  /// İlk sayfa gelince (sunucu `unread_count`) ya da görüldü işaretlenince okunmamış sayısı (sekme rozeti).
  final ValueChanged<int>? onUnreadCount;

  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> implements ReservationReloadable {
  String _scope = 'upcoming';
  bool _moduleOff = false;
  int _unread = 0;
  final Set<int> _cancelling = <int>{};

  /// İlk sayfa isteklerinin sırası: rozet sayacı yalnız EN SON ilk sayfa yanıtından ve istek anındaki site süzgeci hâlâ
  /// geçerliyse uygulanır (yükleyicinin belirteciyle aynı anlam). Site değişirken uçuştaki eski yanıt rozeti ezmez.
  int _firstPageSeq = 0;

  late final CursorLoader<ReservationRecord> _loader = CursorLoader<ReservationRecord>(
    fetch: (before) async {
      final filter = widget.siteFilter;
      final seq = before == null ? ++_firstPageSeq : _firstPageSeq;
      final page = await widget.service.listMine(
        siteCode: filter,
        scope: _scope,
        limit: 30,
        beforeId: before,
      );
      if (before == null) {
        _moduleOff = false;
        if (mounted && seq == _firstPageSeq && filter == widget.siteFilter) {
          _setUnread(page.unreadCount);
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
        'Rezervasyonlarınız yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(_MineTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteFilter != widget.siteFilter ||
        !identical(oldWidget.service, widget.service)) {
      _resetList();
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _loader.reload();

  void _resetList() {
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _selectScope(String scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _resetList();
  }

  void _setUnread(int count) {
    if (!mounted) return;
    setState(() => _unread = count);
    widget.onUnreadCount?.call(count);
  }

  /// Süzgeç "Tümü" değilken okunmamış sayısı listede görünen okunmamışlardan fazlaysa (reddedilen / yönetimce iptal
  /// edilen rezervasyon "Geçmiş"tedir) uyarı + "Tümünü göster" çizilir: rozet ancak kayıt açılınca söner.
  bool get _hiddenUnread =>
      _scope != 'all' &&
      _loader.loadedOnce &&
      _unread > _loader.items.where((record) => record.unread).length;

  /// Ayrıntı penceresi: açılışta okunmamış karar görüldü işaretlenir; pencere "değişti" derse yerel bayrak hemen söner
  /// (yenileme başarısız olsa da rozet kalmaz) ve liste sunucuyla eşitlenir.
  Future<void> _open(ReservationRecord record) async {
    final changed = await ReservationResidentDetailDialog.show(
      context,
      service: widget.service,
      record: record,
    );
    if (!changed || !mounted) return;
    if (record.unread) {
      _loader.updateItem(record.id, (old) => old.copyWith(unread: false));
      _setUnread(_unread > 0 ? _unread - 1 : 0);
    }
    unawaited(_loader.reload());
  }

  Future<void> _cancel(ReservationRecord record) async {
    if (_cancelling.contains(record.id)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Rezervasyon iptal edilsin mi?',
        icon: Icons.cancel_outlined,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('rez_cancel_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('rez_cancel_confirm'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: const Text('Rezervasyonu İptal Et'),
          ),
        ],
        child: Text(
          '${record.areaLabel}, ${reservationWhenText(record)} rezervasyonunuz iptal edilir ve saat başkalarına açılır.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _cancelling.add(record.id));
    try {
      await widget.service.cancelMine(record.id);
      if (!mounted) return;
      setState(() => _cancelling.remove(record.id));
      announcePolite(context, 'Rezervasyonunuz iptal edildi.');
      AppSnack.show(context, 'Rezervasyonunuz iptal edildi.', kind: AppSnackKind.success);
      unawaited(_loader.reload());
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling.remove(record.id));
      AppSnack.show(
        context,
        crmMessageOf(
          e,
          'Rezervasyon iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        ),
        kind: AppSnackKind.error,
      );
      // İptal süresi bu arada dolmuş ya da kayıt değişmiş olabilir: görünür durum sunucuyla eşitlenir.
      if (e is ApiException && (e.statusCode == 409 || e.statusCode == 404)) {
        unawaited(_loader.reload());
      }
    }
  }

  String get _emptyTitle => switch (_scope) {
    'past' => 'Geçmiş rezervasyonunuz yok.',
    'all' => 'Henüz rezervasyonunuz yok.',
    _ => 'Yaklaşan rezervasyonunuz yok.',
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    if (_moduleOff) return const ReservationModuleOffCard();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Zaman', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final entry in const <(String, String)>[
                    ('upcoming', 'Yaklaşan'),
                    ('past', 'Geçmiş'),
                    ('all', 'Tümü'),
                  ])
                    ChoiceChip(
                      key: ValueKey<String>('rez_scope_${entry.$1}'),
                      label: Text(entry.$2),
                      selected: _scope == entry.$1,
                      onSelected: (_) => _selectScope(entry.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_hiddenUnread) ...[
          ReservationHiddenUnreadNotice(
            key: const ValueKey<String>('rez_unread_hidden_notice'),
            actionKey: const ValueKey<String>('rez_unread_show_all'),
            message: '$_unread rezervasyonunuzda yeni güncelleme var.',
            onShowAll: () => _selectScope('all'),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Rezervasyonlarım',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<ReservationRecord>(
          loader: _loader,
          emptyIcon: Icons.event_available_rounded,
          emptyTitle: _emptyTitle,
          emptyMessage: _scope == 'upcoming'
              ? '"Alanlar" sekmesinden bir ortak alan seçerek rezervasyon yapabilirsiniz.'
              : null,
          itemBuilder: (context, record) => MyReservationCard(
            record: record,
            showSite: widget.multiSite,
            busy: _cancelling.contains(record.id),
            onCancel: () => unawaited(_cancel(record)),
            onTap: () => unawaited(_open(record)),
          ),
        ),
      ],
    );
  }
}
