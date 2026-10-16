import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_application_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';

/// "Site Başvuruları" ekranı (yalnız süper kullanıcı, Platform: site başvurusu): bireysel kullanıcıların
/// site kurma başvuruları; durum süzgeci (Bekleyen / Onaylanan / Reddedilen / İptal edilen / Tümü), arama
/// (site adı, şehir, başvuran adı / e-postası), sayfalı kartlar ve ayrıntı penceresi (onay / red orada).
///
/// "Abonelik Talepleri"nden (site yöneticisi KAYDI onayı) farklıdır ve ona dokunmaz.
///
/// Yarış korumaları [PagedLoader]ındır: hızlı art arda arama ya da süzgeç değişiminde eski yanıt yenisini
/// ezmez; yenileme sürmekte olan "Daha fazla yükle"yi geçersiz kılar; sayfa kapanınca gelen yanıt yok
/// sayılır. Hata ASLA "başvuru yok" demez (hata + "Tekrar Dene"). Arama duraksayınca (350 ms) ya da
/// klavyeden gönderilince çalışır. Karardan sonra liste otomatik yenilenir ve [onChanged] çağrılır
/// (çekmece rozeti sunucudan yeniden okunur).
class SiteApplicationsView extends StatefulWidget {
  const SiteApplicationsView({super.key, required this.authService, this.onChanged});

  final AuthService authService;

  /// Bir başvuru karara bağlanınca (ya da durum uyuşmazlığı görülünce) çağrılır.
  final VoidCallback? onChanged;

  /// Sayfa başına başvuru sayısı (sunucu varsayılanı).
  static const int pageSize = 30;

  /// Durum süzgeci seçenekleri: (sunucu `status` değeri, görünen ad). İlki varsayılandır.
  static const List<(String, String)> statusFilters = <(String, String)>[
    (SiteApplicationStatus.pending, 'Bekleyen'),
    (SiteApplicationStatus.approved, 'Onaylanan'),
    (SiteApplicationStatus.rejected, 'Reddedilen'),
    (SiteApplicationStatus.cancelled, 'İptal edilen'),
    ('all', 'Tümü'),
  ];

  @override
  State<SiteApplicationsView> createState() => SiteApplicationsViewState();
}

class SiteApplicationsViewState extends State<SiteApplicationsView> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String _status = SiteApplicationStatus.pending;
  String _lastSignature = '|${SiteApplicationStatus.pending}';

  // Ayrıntı penceresi çift dokunuşta iki kez açılmasın.
  bool _opening = false;

  late final PagedLoader<SiteApplication> _loader = PagedLoader<SiteApplication>(
    pageSize: SiteApplicationsView.pageSize,
    fetch: (offset, limit) async {
      final page = await widget.authService.listAdminSiteApplications(
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
    errorFallback: 'Site başvuruları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla başvuru yüklenemedi. Tekrar deneyin.',
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
    // Aynı sorgu (Enter + gecikme sayacı, aynı süzgeci yeniden seçme) tekrar çağrılmaz.
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

  Future<void> _open(SiteApplication application) async {
    if (_opening) return;
    _opening = true;
    final SiteApplicationDecisionResult? result;
    try {
      result = await SiteApplicationDetailDialog.show(
        context,
        authService: widget.authService,
        applicationId: application.id,
        initialTitle: application.siteName,
        onChanged: () {
          widget.onChanged?.call();
          if (mounted) unawaited(_loader.reload());
        },
      );
    } finally {
      _opening = false;
    }
    if (result == null || !mounted) return;
    // Liste ve rozet, karar anında `onChanged` ile zaten tazelendi; burada yalnız sonuç iletisi gösterilir.
    AppSnack.show(context, result.message, kind: AppSnackKind.success);
  }

  bool get _filtered => _query.isNotEmpty || _status != SiteApplicationStatus.pending;

  /// Süzgeç / arama açıkken boş sonuç başlığı.
  String get _emptyFilteredTitle {
    if (_query.isNotEmpty) return 'Bu arama için başvuru bulunamadı.';
    switch (_status) {
      case SiteApplicationStatus.approved:
        return 'Onaylanan başvuru yok.';
      case SiteApplicationStatus.rejected:
        return 'Reddedilen başvuru yok.';
      case SiteApplicationStatus.cancelled:
        return 'İptal edilen başvuru yok.';
      default:
        return 'Henüz site başvurusu yok.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final pendingFilter = _status == SiteApplicationStatus.pending && _query.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Site Başvuruları', icon: Icons.domain_add_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Bireysel kullanıcılar site kurmak için başvurur. Onayladığınızda site kurulur ve '
          'başvuran site yöneticisi olur.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('site_applications_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                maxLength: 100,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    null,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applyFilters(),
                decoration: InputDecoration(
                  labelText: 'Başvuru ara',
                  hintText: 'Site adı, şehir, başvuran adı veya e-postası',
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
              Text('Durum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final (value, label) in SiteApplicationsView.statusFilters)
                    ChoiceChip(
                      key: ValueKey<String>('site_application_filter_$value'),
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
          title: 'Başvurular',
          count: _loader.loadedOnce ? _loader.total : null,
          countSuffix: pendingFilter ? ' bekleyen' : '',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<SiteApplication>(
          loader: _loader,
          emptyIcon: Icons.inbox_rounded,
          emptyTitle: 'Bekleyen site başvurusu yok.',
          emptyMessage: 'Bireysel kullanıcılar site kurmak için başvurduğunda burada görünür.',
          filteredTitle: _emptyFilteredTitle,
          filtered: _filtered,
          itemBuilder: (context, application) => SiteApplicationAdminCard(
            application: application,
            onTap: () => _open(application),
          ),
        ),
      ],
    );
  }
}
