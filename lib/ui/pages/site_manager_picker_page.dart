import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Site Yöneticisi Seç'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
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
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => _loadManagers(page: 1, reset: true),
                              child: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      )
                    : _managers.isEmpty
                        ? const Center(
                            child: Text(
                              'Kayıtlı site yöneticisi bulunamadı.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _managers.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _managers.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final manager = _managers[index];
                              final isSelected =
                                  manager.id == widget.selectedUserCode;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.black.withValues(alpha: 0.06),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        AppColors.primary.withValues(alpha: 0.12),
                                    child: Text(
                                      manager.fullName.trim().isEmpty
                                          ? '?'
                                          : manager.fullName.trim()[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    manager.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${manager.email} ${manager.phoneNumber != null ? '• ${manager.phoneNumber}' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: AppColors.primary,
                                        )
                                      : null,
                                  onTap: () => Navigator.of(context).pop(
                                    SiteManagerPickerResult(manager: manager),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

