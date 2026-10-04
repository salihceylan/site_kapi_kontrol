import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class SiteManagerPickerResult {
  const SiteManagerPickerResult({required this.manager});

  final ManagedUserAccount? manager;
}

class SiteManagerPickerPage extends StatefulWidget {
  const SiteManagerPickerPage({
    super.key,
    required this.authService,
    required this.selectedUserCode,
  });

  final AuthService authService;
  final int? selectedUserCode;

  @override
  State<SiteManagerPickerPage> createState() => _SiteManagerPickerPageState();
}

class _SiteManagerPickerPageState extends State<SiteManagerPickerPage> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  List<ManagedUserAccount> _managers = <ManagedUserAccount>[];
  int _page = 1;
  int _total = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  bool get _hasMore => _managers.length < _total;

  @override
  void initState() {
    super.initState();
    _loadManagers(page: 1, reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 120) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadManagers(page: _page + 1);
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadManagers(page: 1, reset: true);
    });
  }

  Future<void> _loadManagers({required int page, bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final query = _searchController.text.trim();
    try {
      final pageData = await widget.authService.listManagedUsers(
        role: UserRole.siteManager,
        page: page,
        pageSize: _pageSize,
        search: query.isEmpty ? null : query,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _page = pageData.page;
        _total = pageData.total;
        if (reset) {
          _managers = pageData.users;
        } else {
          _managers = [..._managers, ...pageData.users];
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = e.toString();
      });
    }
  }

  /// Yönetici satırı: tek dokunuşla seçilir ([AppCard] düğme); seçili satır birincil kenarlı + onay işaretli.
  Widget _managerTile(ManagedUserAccount manager) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isSelected = manager.id == widget.selectedUserCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        selected: isSelected,
        padding: const EdgeInsets.all(AppSpace.md),
        onTap: () => Navigator.of(
          context,
        ).pop(SiteManagerPickerResult(manager: manager)),
        child: Row(
          children: [
            // Rol tonu (site yöneticisi) anlam taşır; satırlarda parlak "hero" yok: 40 dp squircle.
            IconOrb(
              icon: Icons.manage_accounts_rounded,
              tone: UserRole.siteManager.tone,
              size: 40,
              shape: IconOrbShape.squircle,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    manager.fullName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${manager.email} ${manager.phoneNumber != null ? '• ${manager.phoneNumber}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: AppSpace.sm),
              Icon(Icons.check_circle_rounded, color: AppTone.primary.ink(p)),
            ],
          ],
        ),
      ),
    );
  }

  /// İlk yükleme: gerçek satırların iskeleti (yalnız yükleme süresince ağaçta; tek shimmer).
  Widget _buildSkeleton() {
    return ShimmerScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          0,
          AppSpace.lg,
          AppSpace.lg,
        ),
        children: const [
          _ManagerSkeletonRow(),
          _ManagerSkeletonRow(),
          _ManagerSkeletonRow(),
          _ManagerSkeletonRow(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildSkeleton();

    final error = _error;
    if (error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          AppSpace.lg,
        ),
        child: InlineNotice(
          message: error,
          onRetry: () => _loadManagers(page: 1, reset: true),
        ),
      );
    }

    if (_managers.isEmpty) {
      return const EmptyState(
        icon: Icons.manage_accounts_rounded,
        title: 'Kayıtlı site yöneticisi bulunamadı.',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      itemCount: _managers.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _managers.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _managerTile(_managers[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sayfa zemini kökte (lib/app.dart builder) tek kez boyanır: Scaffold ve AppBar şeffaf kalır.
    return Scaffold(
      appBar: AppBar(title: const Text('Site Yöneticisi Seç')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Ad, e-posta veya telefon ile ara...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _loadManagers(page: 1, reset: true);
                          },
                        )
                      : null,
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}

/// Yükleme iskeleti satırı: gerçek yönetici satırıyla aynı iskelet (40 dp rozet + iki metin satırı).
class _ManagerSkeletonRow extends StatelessWidget {
  const _ManagerSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: EdgeInsets.all(AppSpace.md),
        child: Row(
          children: [
            SkeletonBox(width: 40, height: 40, radius: AppRadius.sm),
            SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    child: SkeletonBox(height: 14),
                  ),
                  SizedBox(height: AppSpace.sm),
                  FractionallySizedBox(
                    widthFactor: 0.8,
                    child: SkeletonBox(height: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
