import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_manage_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// Bir sitenin yönetici duyuru listesi (Platform Faz 3a): durum süzgeci (Hepsi / Taslak / Zamanlanmış /
/// Yayında / Geri çekildi) + arama, sayfalı kartlar, "Yeni Duyuru" (yalnız yazma yetkisi olanda) ve
/// ayrıntı penceresi.
///
/// Hızlı art arda aramada ya da süzgeç değişiminde eski yanıt yenisini ezmez ([PagedLoader] jetonu).
/// Arama duraksayınca (350 ms) ya da klavyeden gönderilince çalışır. Her başarılı işlemden sonra liste
/// otomatik yenilenir. Sunucu sitesine göre kurulur: site değişince bu widget yeniden oluşturulur.
class AnnouncementsAdminList extends StatefulWidget {
  const AnnouncementsAdminList({super.key, required this.scope});

  final PeopleScope scope;

  @override
  State<AnnouncementsAdminList> createState() => AnnouncementsAdminListState();
}

class AnnouncementsAdminListState extends State<AnnouncementsAdminList> {
  static const List<(String, String)> _filters = <(String, String)>[
    ('all', 'Hepsi'),
    ('draft', 'Taslak'),
    ('scheduled', 'Zamanlanmış'),
    ('published', 'Yayında'),
    ('withdrawn', 'Geri çekildi'),
  ];

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String _status = 'all';
  String _lastSignature = '|all';

  // Form / ayrıntı penceresi çift dokunuşta iki kez açılmasın.
  bool _opening = false;

  late final PagedLoader<AnnouncementSummary> _loader = PagedLoader<AnnouncementSummary>(
    pageSize: 30,
    fetch: (offset, limit) async {
      final page = await widget.scope.authService.listAnnouncements(
        widget.scope.siteCode,
        status: _status,
        query: _query,
        limit: limit,
        offset: offset,
      );
      return (items: page.items, total: page.total);
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
    final signature = '$next|$_status';
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

  void _selectStatus(String status) {
    if (status == _status) return;
    _status = status;
    _applyFilters();
    setState(() {});
  }

  Future<void> _create() async {
    if (_opening) return;
    _opening = true;
    final AnnouncementFormResult? result;
    try {
      result = await AnnouncementFormDialog.show(
        context,
        scope: widget.scope,
        // İstek sunucuya ulaşmış olabilir (zaman aşımı, yinelenen içerik): form kapanırken liste tazelenir.
        onRefreshNeeded: () => unawaited(_loader.reload()),
      );
    } finally {
      _opening = false;
    }
    if (result == null || !mounted) return;
    AppSnack.show(context, result.message, kind: AppSnackKind.success);
    unawaited(_loader.reload());
  }

  Future<void> _open(AnnouncementSummary announcement) async {
    if (_opening) return;
    _opening = true;
    try {
      await AnnouncementManageDialog.show(
        context,
        scope: widget.scope,
        announcementId: announcement.id,
        initialTitle: announcement.title,
        onChanged: () => unawaited(_loader.reload()),
      );
    } finally {
      _opening = false;
    }
  }

  bool get _filtered => _query.isNotEmpty || _status != 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.scope.canWrite) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('announcement_create'),
            label: 'Yeni Duyuru',
            icon: Icons.add_rounded,
            onPressed: _create,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('announcements_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applyFilters(),
                decoration: InputDecoration(
                  labelText: 'Duyuru ara',
                  hintText: 'Başlık veya metinde ara',
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
              Text('Durum', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final (value, label) in _filters)
                    ChoiceChip(
                      key: ValueKey<String>('announcement_filter_$value'),
                      label: Text(label),
                      selected: _status == value,
                      onSelected: (_) => _selectStatus(value),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Duyurular',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<AnnouncementSummary>(
          loader: _loader,
          emptyIcon: Icons.campaign_rounded,
          emptyTitle: 'Henüz duyuru yok.',
          emptyMessage: widget.scope.canWrite
              ? 'Yeni Duyuru ile sakinlere ilk duyuruyu gönderebilirsiniz.'
              : null,
          filteredTitle: 'Bu arama ve süzgeç için duyuru bulunamadı.',
          filtered: _filtered,
          itemBuilder: (context, announcement) => AnnouncementAdminCard(
            announcement: announcement,
            onTap: () => _open(announcement),
          ),
        ),
      ],
    );
  }
}
