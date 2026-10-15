import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_request_card.dart';

/// "Modül Talepleri" ekranı (yalnız süper kullanıcı, Platform Faz 1.1): site yöneticilerinin
/// gönderdiği modül talepleri; durum filtresi (Bekleyen / Onaylanan / Reddedilen / Tümü), kartlar,
/// "Onayla" ve "Reddet" (onay penceresi; reddetmede isteğe bağlı gerekçe), "Daha fazla yükle" ve
/// aşağı çekip yenileme.
///
/// Veriyi kendisi çeker; [ModuleRequestsViewState.reload] sayfa kabuğunun yenilemesinden de çağrılır.
/// Karardan sonra liste otomatik yeniden çekilir ve [onChanged] çağrılır (çekmece rozeti hemen
/// tazelenir). Yarış korumaları denetim kaydı ekranıyla aynıdır: yenileme / filtre değişimi sürmekte
/// olan "Daha fazla yükle"yi geçersiz kılar, düğme sıfırlanır; eski imleçle sayfa eklenmez.
class ModuleRequestsView extends StatefulWidget {
  const ModuleRequestsView({super.key, required this.authService, this.onChanged});

  final AuthService authService;

  /// Bir talep karara bağlanınca (başarı ya da hata) çağrılır.
  final VoidCallback? onChanged;

  /// Sayfa başına talep sayısı (sunucu varsayılanı).
  static const int pageSize = 50;

  /// Durum filtresi seçenekleri: (sunucu `status` değeri, görünen ad). İlki varsayılandır.
  static const List<(String, String)> statusFilters = <(String, String)>[
    (ModuleRequestStatus.pending, 'Bekleyen'),
    (ModuleRequestStatus.approved, 'Onaylanan'),
    (ModuleRequestStatus.rejected, 'Reddedilen'),
    ('all', 'Tümü'),
  ];

  @override
  State<ModuleRequestsView> createState() => ModuleRequestsViewState();
}

class ModuleRequestsViewState extends State<ModuleRequestsView> {
  String _status = ModuleRequestStatus.pending;
  List<ModuleRequest> _items = const <ModuleRequest>[];
  int? _nextBeforeId;
  int _pendingCount = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  final Set<int> _busy = <int>{};

  // Her yeniden yükleme / filtre değişimi `_moreToken`'ı da artırır: eski imleçli sayfa yok sayılır.
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

  /// İlk sayfayı yeniden çeker; ekranda mevcut liste yenileme sürerken kalır. Sürmekte olan "Daha
  /// fazla yükle" iptal edilir (sonucu yok sayılır, düğme sıfırlanır).
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
    try {
      final page = await widget.authService.listAdminModuleRequests(
        status: _status,
        limit: ModuleRequestsView.pageSize,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _nextBeforeId = page.nextBeforeId;
        _pendingCount = page.pendingCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = _messageOf(
          e,
          'Modül talepleri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
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
      final page = await widget.authService.listAdminModuleRequests(
        status: _status,
        limit: ModuleRequestsView.pageSize,
        beforeId: before,
      );
      if (!mounted || more != _moreToken) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items = <ModuleRequest>[
          ..._items,
          ...page.items.where((e) => !known.contains(e.id)),
        ];
        _nextBeforeId = page.nextBeforeId;
        _pendingCount = page.pendingCount;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || more != _moreToken) return;
      setState(() {
        _loadingMore = false;
        _moreError = _messageOf(e, 'Daha fazla talep yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  void _changeStatus(String value) {
    if (value == _status) return;
    setState(() {
      _status = value;
      _items = const <ModuleRequest>[];
      _nextBeforeId = null;
    });
    unawaited(reload());
  }

  // --- Karar ---------------------------------------------------------------------------------

  Future<void> _approve(ModuleRequest request) async {
    if (_busy.contains(request.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Talep Onaylansın mı?',
        icon: Icons.check_circle_outline,
        tone: AppTone.success,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: filledToneStyle(ctx, tone: AppTone.success),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Onayla'),
          ),
        ],
        child: Text(
          '"${request.moduleLabel}" modülü ${_siteOf(request)} için tanımlanacak ve '
          'site yöneticisi modülü kullanmaya başlayacak.',
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _decide(request, approve: true);
  }

  Future<void> _reject(ModuleRequest request) async {
    if (_busy.contains(request.id)) return;
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => _RejectDialog(
        moduleName: request.moduleLabel,
        siteLabel: _siteOf(request),
      ),
    );
    if (note == null || !mounted) return;
    await _decide(request, approve: false, note: note);
  }

  String _siteOf(ModuleRequest r) => r.siteName.trim().isEmpty
      ? 'Site ${r.siteCode}'
      : '${r.siteName} (${r.siteCode})';

  Future<void> _decide(ModuleRequest request, {required bool approve, String? note}) async {
    // Geri çağrı State'ten ÖNCE alınır: ekran kapansa da rozet sunucudan yeniden okunur.
    final onChanged = widget.onChanged;
    setState(() => _busy.add(request.id));
    try {
      await widget.authService.decideModuleRequest(request.id, approve, note: note);
      if (!mounted) return;
      AppSnack.show(
        context,
        approve ? 'Talep onaylandı. Modül siteye tanımlandı.' : 'Talep reddedildi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        _messageOf(e, 'İşlem tamamlanamadı. Sunucuya bağlanılamadı.'),
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy.remove(request.id));
        // Sonuç ne olursa olsun (örn. 409 REQUEST_NOT_PENDING) liste sunucudan yeniden okunur.
        unawaited(reload());
      }
      onChanged?.call();
    }
  }

  // --- Görünüm -------------------------------------------------------------------------------

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
        icon: Icons.inbox_rounded,
        title: _status == ModuleRequestStatus.pending
            ? 'Bekleyen modül talebi yok.'
            : 'Bu filtre için modül talebi yok.',
        message: 'Site yöneticileri bir modül talep ettiğinde burada görünür.',
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
                child: ModuleRequestCard(
                  request: _items[i],
                  showSite: true,
                  busy: _busy.contains(_items[i].id),
                  onApprove: _items[i].isPending ? () => unawaited(_approve(_items[i])) : null,
                  onReject: _items[i].isPending ? () => unawaited(_reject(_items[i])) : null,
                ),
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
        const PageHeaderCard(title: 'Modül Talepleri', icon: Icons.inbox_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Site yöneticileri modülleri kendileri açamaz; talep gönderirler. Onayladığınız modül '
          'ilgili siteye tanımlanır.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Talepler',
          count: _pendingCount > 0 ? _pendingCount : null,
          countSuffix: ' bekleyen',
          trailing: IconButton(
            onPressed: _loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: DropdownButtonFormField<String>(
            key: ValueKey<String>('module_requests_status_$_status'),
            isExpanded: true,
            initialValue: _status,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Durum filtresi',
              prefixIcon: Icon(Icons.filter_list_rounded),
            ),
            items: [
              for (final (value, label) in ModuleRequestsView.statusFilters)
                DropdownMenuItem<String>(
                  value: value,
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) _changeStatus(value);
            },
          ),
        ),
        const SizedBox(height: AppSpace.md),
        list,
      ],
    );
  }
}

/// Reddetme penceresi: isteğe bağlı gerekçe (en çok 500 karakter). "Vazgeç" `null`, "Reddet" gerekçe
/// metni (boş olabilir) döndürür.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.moduleName, required this.siteLabel});

  final String moduleName;
  final String siteLabel;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Talep Reddedilsin mi?',
      icon: Icons.cancel_outlined,
      tone: AppTone.danger,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          style: filledToneStyle(context, tone: AppTone.danger),
          onPressed: () => Navigator.of(context).pop(_noteController.text.trim()),
          child: const Text('Reddet'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.moduleName}" modülü için ${widget.siteLabel} talebi reddedilecek. '
            'İsterseniz site yöneticisine gösterilecek bir gerekçe yazabilirsiniz.',
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _noteController,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Gerekçe (isteğe bağlı)',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
