import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_audit_log.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_audit_log_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart' show PeopleSite;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_audit_log_card.dart';

/// Dönem ön ayarı. "Tümü" tarih süzgeci YOKTUR.
enum SiteAuditPeriod {
  all('all', 'Tümü'),
  today('today', 'Bugün'),
  last7('last_7', 'Son 7 gün'),
  last30('last_30', 'Son 30 gün'),
  custom('custom', 'Özel aralık');

  const SiteAuditPeriod(this.key, this.label);

  final String key;
  final String label;
}

/// Yönetim "İşlem Kayıtları" ekranı (site yöneticisi): kendi sitesinde yapılan işlemlerin değiştirilemez listesi
/// (kim, ne zaman, ne yaptı), site / işlem türü / dönem süzgeci, "Daha fazla yükle" ve aşağı çekip yenileme.
///
/// - Kayıtlar yeniden eskiye `id DESC` sıralıdır; sonraki sayfa `before_id` ile istenir ve listenin SONUNA eklenir (aynı
///   id iki kez gösterilmez). Süzgeç ve site değişimi listeyi sıfırlar; devam sayfası ilk sayfanın süzgeciyle istenir.
/// - Tarihler İstanbul gününe göre süzülür (ikisi de dahil); özel aralık GG.AA.YYYY metin alanlarıyla girilir (uygulamada
///   Türkçe takvim yerelleştirmesi yoktur, bkz. `ui/helpers/date_input.dart`). Alanlardan biri boş bırakılabilir.
/// - Yarış: her yükleme / süzgeç değişimi `_token`'ı, her "Daha fazla yükle" `_moreToken`'ı artırır; eski yanıt listeye
///   eklenmez. HATA asla "kayıt yok" demez (boş durum yalnız sunucu gerçekten boş sayfa verince çizilir).
/// - Kişisel veri: sunucu kullanıcı kodu / e-posta / telefon / parola göndermez; ekran yalnız gelen alanları çizer.
class SiteAuditLogView extends StatefulWidget {
  const SiteAuditLogView({
    super.key,
    required this.authService,
    required this.sites,
    this.service,
    this.now,
  });

  final AuthService authService;

  /// Yöneticisi olunan siteler (boşsa ekran "yönettiğiniz site yok" der). Birden fazlaysa site seçici çizilir.
  final List<PeopleSite> sites;

  /// Testler için; verilmezse oturumdaki servis.
  final SiteAuditLogService? service;

  /// Şimdi (testler içindir); verilmezse cihaz saati (İstanbul duvar saatine çevrilir).
  final DateTime Function()? now;

  @override
  State<SiteAuditLogView> createState() => SiteAuditLogViewState();
}

class SiteAuditLogViewState extends State<SiteAuditLogView> {
  /// "Tümü" işlem türü seçeneğinin değeri (DropdownButton boş metni de ayrı bir değer olarak tutar).
  static const String _allCategories = '';

  late final SiteAuditLogService _service =
      widget.service ?? SiteAuditLogService(authService: widget.authService);
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fromField = TextEditingController();
  final TextEditingController _toField = TextEditingController();

  PeopleSite? _site;
  String? _category;
  SiteAuditPeriod _period = SiteAuditPeriod.all;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _rangeError;

  // Ekrandaki listenin süzgeci (son yükleme anındaki değerler): "Daha fazla yükle" bunu kullanır, boş durum bunu okur.
  int? _activeSite;
  DateTime? _activeFrom;
  DateTime? _activeTo;
  String? _activeCategory;

  List<SiteAuditEntry> _items = const <SiteAuditEntry>[];
  int? _nextBeforeId;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  int _token = 0;
  int _moreToken = 0;

  @override
  void initState() {
    super.initState();
    _site = widget.sites.isEmpty ? null : widget.sites.first;
    unawaited(reload());
  }

  @override
  void didUpdateWidget(SiteAuditLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _site;
    if (current != null && widget.sites.any((s) => s.code == current.code)) return;
    final next = widget.sites.isEmpty ? null : widget.sites.first;
    if (next?.code == current?.code) return;
    _site = next;
    _items = const <SiteAuditEntry>[];
    _nextBeforeId = null;
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    ++_moreToken;
    _fromField.dispose();
    _toField.dispose();
    super.dispose();
  }

  /// Bugün (İstanbul takvim günü).
  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// Dönemin (başlangıç, bitiş) takvim günleri; "Tümü"de ikisi de null.
  (DateTime?, DateTime?) _rangeOf(SiteAuditPeriod period) {
    final today = _today();
    return switch (period) {
      SiteAuditPeriod.all => (null, null),
      SiteAuditPeriod.today => (today, today),
      SiteAuditPeriod.last7 => (DateTime(today.year, today.month, today.day - 6), today),
      SiteAuditPeriod.last30 => (DateTime(today.year, today.month, today.day - 29), today),
      SiteAuditPeriod.custom => (_customFrom, _customTo),
    };
  }

  /// İlk sayfayı yeniden çeker (yenile düğmesi ve sayfa kabuğunun aşağı çekip yenilemesi); ekranda mevcut liste
  /// yenileme sürerken kalır. Ön ayarlı dönem BUGÜNE göre yeniden hesaplanır. Sürmekte olan "Daha fazla yükle" iptal edilir.
  Future<void> reload() async {
    if (!mounted) return;
    final site = _site;
    if (site == null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _items = const <SiteAuditEntry>[];
        _nextBeforeId = null;
        _error = null;
        _moreError = null;
      });
      return;
    }
    final token = ++_token;
    ++_moreToken;
    final (from, to) = _rangeOf(_period);
    final category = _category;
    setState(() {
      _activeSite = site.code;
      _activeFrom = from;
      _activeTo = to;
      _activeCategory = category;
      _loading = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
    try {
      final page = await _service.list(site.code, from: from, to: to, category: category, limit: siteAuditPageSize);
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
        _error = crmMessageOf(e, 'İşlem kayıtları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBeforeId;
    final site = _activeSite;
    if (before == null || site == null || _loadingMore || _loading) return;
    final more = ++_moreToken;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await _service.list(
        site,
        from: _activeFrom,
        to: _activeTo,
        category: _activeCategory,
        limit: siteAuditPageSize,
        beforeId: before,
      );
      // Bu arada yenileme / süzgeç değişimi oldu: eski imleçle gelen sayfa eklenmez (bayrağı yeni yükleme zaten sıfırladı).
      if (!mounted || more != _moreToken) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items = <SiteAuditEntry>[..._items, ...page.items.where((e) => !known.contains(e.id))];
        _nextBeforeId = page.nextBeforeId;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || more != _moreToken) return;
      setState(() {
        _loadingMore = false;
        _moreError = crmMessageOf(e, 'Daha fazla kayıt yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  void _applyFilter(VoidCallback change) {
    setState(() {
      change();
      _items = const <SiteAuditEntry>[];
      _nextBeforeId = null;
    });
    unawaited(reload());
  }

  void _selectSite(int code) {
    if (code == _site?.code) return;
    final next = widget.sites.where((s) => s.code == code).firstOrNull;
    if (next == null) return;
    _applyFilter(() => _site = next);
  }

  void _selectCategory(String value) {
    final next = value == _allCategories ? null : value;
    if (next == _category) return;
    _applyFilter(() => _category = next);
  }

  void _selectPeriod(SiteAuditPeriod period) {
    if (period == _period) return;
    if (period == SiteAuditPeriod.custom) {
      // Özel aralık "Uygula"ya kadar yüklemeyi değiştirmez; alanlar son uygulanan değerle açılır.
      setState(() {
        _period = period;
        _rangeError = null;
        _fromField.text = formatDateField(_customFrom);
        _toField.text = formatDateField(_customTo);
      });
      return;
    }
    _applyFilter(() {
      _period = period;
      _rangeError = null;
    });
  }

  /// Özel aralık: alanlar boş ya da geçerli tarih; en az biri dolu; başlangıç <= bitiş; yıl 2000 ve sonrası (sunucu sınırı).
  void _applyCustom() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() => _rangeError = null);
      return;
    }
    final from = parseDateField(_fromField.text);
    final to = parseDateField(_toField.text);
    String? error;
    if (from == null && to == null) {
      error = 'En az bir tarih girin (GG.AA.YYYY).';
    } else if (from != null && to != null && from.isAfter(to)) {
      error = 'Başlangıç tarihi bitiş tarihinden sonra olamaz.';
    } else if ((from != null && from.year < 2000) || (to != null && to.year < 2000)) {
      error = 'Tarih 2000 ve sonrası olmalıdır.';
    }
    setState(() => _rangeError = error);
    if (error != null) return;
    FocusScope.of(context).unfocus();
    _applyFilter(() {
      _customFrom = from;
      _customTo = to;
    });
  }

  bool get _filtered => _activeCategory != null || _activeFrom != null || _activeTo != null;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey<String>('site_audit_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'İşlem Kayıtları', icon: Icons.fact_check_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Sitenizde yapılan yönetim işlemlerinin değiştirilemez kaydı: kim, ne zaman, ne yaptı. Parola ve iletişim bilgileri kayıtta yer almaz.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Kayıtlar',
          trailing: IconButton(
            onPressed: (_loading || _site == null) ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.isEmpty)
          const EmptyCard(
            key: ValueKey<String>('site_audit_no_site'),
            icon: Icons.apartment_rounded,
            title: 'Yönettiğiniz bir site yok.',
            message: 'İşlem kayıtları, yöneticisi olduğunuz sitelerde listelenir.',
          )
        else ...[
          _filterCard(context),
          const SizedBox(height: AppSpace.md),
          _list(context),
        ],
      ],
    );
  }

  Widget _filterCard(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final custom = _period == SiteAuditPeriod.custom;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.sites.length > 1) ...[
            DropdownButtonFormField<int>(
              key: ValueKey<String>('site_audit_site_${_site?.code}_${widget.sites.length}'),
              isExpanded: true,
              initialValue: _site?.code,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(labelText: 'Site', prefixIcon: Icon(Icons.apartment_rounded)),
              items: [
                for (final site in widget.sites)
                  DropdownMenuItem<int>(
                    value: site.code,
                    child: Text(site.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _selectSite(value);
              },
            ),
            const SizedBox(height: AppSpace.md),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey<String>('site_audit_category_${_category ?? ''}'),
            isExpanded: true,
            initialValue: _category ?? _allCategories,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(labelText: 'İşlem türü', prefixIcon: Icon(Icons.bolt_rounded)),
            items: [
              const DropdownMenuItem<String>(
                value: _allCategories,
                child: Text('Tümü', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              for (final category in siteAuditCategories)
                DropdownMenuItem<String>(
                  value: category.key,
                  child: Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) _selectCategory(value);
            },
          ),
          const SizedBox(height: AppSpace.md),
          Text('Dönem', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final period in SiteAuditPeriod.values)
                ChoiceChip(
                  key: ValueKey<String>('site_audit_period_${period.key}'),
                  label: Text(period.label),
                  selected: _period == period,
                  onSelected: (_) => _selectPeriod(period),
                ),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: AppSpace.md),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey<String>('site_audit_from'),
                    controller: _fromField,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: const [DateInputFormatter()],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Başlangıç',
                      hintText: 'GG.AA.YYYY',
                      prefixIcon: Icon(Icons.event_rounded),
                    ),
                    validator: validateDateField,
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    key: const ValueKey<String>('site_audit_to'),
                    controller: _toField,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: const [DateInputFormatter()],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _applyCustom(),
                    decoration: const InputDecoration(
                      labelText: 'Bitiş',
                      hintText: 'GG.AA.YYYY',
                      prefixIcon: Icon(Icons.event_available_rounded),
                    ),
                    validator: validateDateField,
                  ),
                  if (_rangeError != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    InlineNotice(key: const ValueKey<String>('site_audit_range_error'), message: _rangeError!),
                  ],
                  const SizedBox(height: AppSpace.md),
                  PrimaryActionButton(
                    key: const ValueKey<String>('site_audit_apply'),
                    label: 'Uygula',
                    icon: Icons.check_rounded,
                    variant: AppButtonVariant.tonal,
                    onPressed: _loading ? null : _applyCustom,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text('Tarihlerden biri boş bırakılabilir; iki tarih de dahildir (İstanbul saati).', style: th.bodySmall),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_loading && _items.isEmpty) {
      // İlk yükleme, süzgeç değişimi ve hata sonrası "Tekrar Dene": iskelet (boş durum yanıp sönmez).
      return const ListSkeleton(rows: 3);
    }
    if (_error != null && _items.isEmpty) {
      return InlineNotice(key: const ValueKey<String>('site_audit_error'), message: _error!, onRetry: reload);
    }
    if (_items.isEmpty) {
      return EmptyCard(
        key: const ValueKey<String>('site_audit_empty'),
        icon: Icons.history_rounded,
        title: _filtered ? 'Bu filtre için işlem kaydı yok.' : 'Henüz işlem kaydı yok.',
        message: 'Modül, rol, kişi ve daire, finans, duyuru ve belge işlemleri burada listelenir.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(key: const ValueKey<String>('site_audit_error'), message: _error!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: StaggeredEntry(index: i, child: SiteAuditLogCard(entry: _items[i])),
          ),
        if (_moreError != null) ...[
          InlineNotice(key: const ValueKey<String>('site_audit_more_error'), message: _moreError!, onRetry: _loadMore),
          const SizedBox(height: AppSpace.md),
        ],
        if (_nextBeforeId != null)
          Align(
            alignment: Alignment.center,
            child: PrimaryActionButton(
              key: const ValueKey<String>('site_audit_more'),
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
}
