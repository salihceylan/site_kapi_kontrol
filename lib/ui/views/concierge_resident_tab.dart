import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/concierge_request_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/concierge_resident_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

/// Sakin "Konsiyerj" sekmesi: kendi talepleri (durum rozeti, yönetim notu), "Yeni Talep" formu, ayrıntı penceresi ve
/// kendi `yeni` talebini iptal. Görülmemiş yönetim güncellemesi (`unread`) "Yeni güncelleme" çipi + uyarı tonuyla
/// gösterilir; karta dokununca ayrıntı açılır ve `seen` çağrılır (rozet söner; İş Takibi ile aynı akış). Süzgecin
/// gizlediği okunmamış talep varsa (ör. tamamlanan talep "Açık"ta yok) uyarı + "Tümünü göster".
///
/// Yarışlar: süzgeç / site değişimi sırasında eski imleçle gelen sayfa listeye eklenmez ([CursorLoader]); HATA ASLA
/// "talep yok" demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar. İptal sürerken düğme yükleniyor
/// gösterir ve çift tıklama yok sayılır; 404 / 409 sonrası liste sunucuyla eşitlenir.
class ConciergeResidentTab extends StatefulWidget {
  const ConciergeResidentTab({
    super.key,
    required this.service,
    required this.sites,
    this.siteFilter,
    this.onUnreadCount,
  });

  final ReservationService service;

  /// Talep açılabilecek (modül açık) siteler.
  final List<PeopleSite> sites;
  final int? siteFilter;

  /// İlk sayfa gelince (sunucu `unread_count`) ya da görüldü işaretlenince okunmamış sayısı (sekme rozeti).
  final ValueChanged<int>? onUnreadCount;

  @override
  State<ConciergeResidentTab> createState() => ConciergeResidentTabState();
}

class ConciergeResidentTabState extends State<ConciergeResidentTab>
    implements ReservationReloadable {
  String _status = 'open';
  bool _moduleOff = false;
  int _unread = 0;
  final Set<int> _cancelling = <int>{};

  /// İlk sayfa isteklerinin sırası: rozet sayacı yalnız EN SON ilk sayfa yanıtından ve istek anındaki site süzgeci hâlâ
  /// geçerliyse uygulanır (yükleyicinin belirteciyle aynı anlam). Site değişirken uçuştaki eski yanıt rozeti ezmez.
  int _firstPageSeq = 0;

  late final CursorLoader<ConciergeRecord> _loader = CursorLoader<ConciergeRecord>(
    fetch: (before) async {
      final filter = widget.siteFilter;
      final seq = before == null ? ++_firstPageSeq : _firstPageSeq;
      final page = await widget.service.listMyRequests(
        siteCode: filter,
        status: _status,
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
        'Talepleriniz yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(ConciergeResidentTab oldWidget) {
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

  void _selectStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _resetList();
  }

  void _setUnread(int count) {
    if (!mounted) return;
    setState(() => _unread = count);
    widget.onUnreadCount?.call(count);
  }

  /// Süzgeç "Tümü" değilken okunmamış sayısı listede görünen okunmamışlardan fazlaysa (tamamlanan / iptal edilen talep
  /// "Açık"ta görünmez) uyarı + "Tümünü göster" çizilir: rozet ancak kayıt açılınca söner.
  bool get _hiddenUnread =>
      _status != 'all' &&
      _loader.loadedOnce &&
      _unread > _loader.items.where((record) => record.unread).length;

  /// Ayrıntı penceresi: açılışta okunmamış güncelleme görüldü işaretlenir; pencere "değişti" derse yerel bayrak hemen
  /// söner (yenileme başarısız olsa da rozet kalmaz) ve liste sunucuyla eşitlenir.
  Future<void> _open(ConciergeRecord record) async {
    final changed = await ConciergeResidentDetailDialog.show(
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

  Future<void> _create() async {
    final result = await ConciergeRequestFormDialog.show(
      context,
      service: widget.service,
      sites: widget.sites,
      initialSiteCode: widget.siteFilter,
    );
    if (result == null || !mounted) return;
    AppSnack.show(
      context,
      result.replayed
          ? 'Bu talep zaten kayıtlıydı.'
          : 'Talebiniz alındı. Durumunu buradan takip edebilirsiniz.',
      kind: AppSnackKind.success,
    );
    // Yeni talep "Açık" listesindedir: kapanan süzgecinde görünmezdi.
    if (_status == 'closed') {
      _selectStatus('open');
    } else {
      unawaited(_loader.reload());
    }
  }

  Future<void> _cancel(ConciergeRecord record) async {
    if (_cancelling.contains(record.id)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Talep iptal edilsin mi?',
        icon: Icons.cancel_outlined,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('cnc_cancel_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('cnc_cancel_confirm'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: const Text('Talebi İptal Et'),
          ),
        ],
        child: Text(
          '${record.category.label} talebiniz iptal edilir ve işleme alınmaz. Bu işlem geri alınamaz.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _cancelling.add(record.id));
    try {
      await widget.service.cancelMyRequest(record.id);
      if (!mounted) return;
      setState(() => _cancelling.remove(record.id));
      announcePolite(context, 'Talebiniz iptal edildi.');
      AppSnack.show(context, 'Talebiniz iptal edildi.', kind: AppSnackKind.success);
      unawaited(_loader.reload());
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling.remove(record.id));
      AppSnack.show(
        context,
        crmMessageOf(e, 'Talep iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'),
        kind: AppSnackKind.error,
      );
      // Talep bu arada ilerlemiş ya da kalkmış olabilir: görünür durum sunucuyla eşitlenir.
      if (e is ApiException && (e.statusCode == 409 || e.statusCode == 404)) {
        unawaited(_loader.reload());
      }
    }
  }

  String get _emptyTitle => switch (_status) {
    'closed' => 'Kapanmış talebiniz yok.',
    'all' => 'Henüz konsiyerj talebiniz yok.',
    _ => 'Açık konsiyerj talebiniz yok.',
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    if (_moduleOff) return const ReservationModuleOffCard();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paket teslimi, misafir hazırlığı, temizlik ya da taşıma gibi isteklerinizi görevlilere iletin; durumunu buradan izleyin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        PrimaryActionButton(
          key: const ValueKey<String>('cnc_new_request'),
          label: 'Yeni Talep',
          icon: Icons.add_rounded,
          onPressed: widget.sites.isEmpty ? null : () => unawaited(_create()),
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Durum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final entry in const <(String, String)>[
                    ('open', 'Açık'),
                    ('closed', 'Kapanan'),
                    ('all', 'Tümü'),
                  ])
                    ChoiceChip(
                      key: ValueKey<String>('cnc_status_${entry.$1}'),
                      label: Text(entry.$2),
                      selected: _status == entry.$1,
                      onSelected: (_) => _selectStatus(entry.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_hiddenUnread) ...[
          ReservationHiddenUnreadNotice(
            key: const ValueKey<String>('cnc_unread_hidden_notice'),
            actionKey: const ValueKey<String>('cnc_unread_show_all'),
            message: '$_unread talebinizde yeni güncelleme var.',
            onShowAll: () => _selectStatus('all'),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Taleplerim',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<ConciergeRecord>(
          loader: _loader,
          emptyIcon: Icons.room_service_rounded,
          emptyTitle: _emptyTitle,
          emptyMessage: _status == 'open'
              ? 'Bir isteğiniz olduğunda "Yeni Talep" ile görevlilere iletebilirsiniz.'
              : null,
          itemBuilder: (context, record) => ConciergeCard(
            record: record,
            showSite: multiSite,
            onTap: () => unawaited(_open(record)),
            footer: record.canCancel
                ? PrimaryActionButton(
                    key: ValueKey<String>('cnc_cancel_${record.id}'),
                    label: 'Talebi İptal Et',
                    icon: Icons.cancel_outlined,
                    tone: AppTone.danger,
                    variant: AppButtonVariant.outline,
                    loading: _cancelling.contains(record.id),
                    onPressed: _cancelling.contains(record.id)
                        ? null
                        : () => unawaited(_cancel(record)),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
