import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class AllUsersView extends StatefulWidget {
  const AllUsersView({
    super.key,
    required this.session,
    required this.pageData,
    required this.users,
    required this.isLoading,
    required this.busyActivationUsers,
    required this.onLoadPage,
    required this.onRefresh,
    required this.onUpdateUser,
    required this.onToggleActivation,
    required this.onDeleteUser,
    this.onGetDatabaseHealth,
    this.onRunDatabaseCleanup,
  });

  final UserSession session;
  final ManagedUserPage? pageData;
  final List<ManagedUserAccount> users;
  final bool isLoading;
  final Set<int> busyActivationUsers;
  final Future<void> Function({
    UserRole? role,
    int page,
    int pageSize,
    String? search,
  }) onLoadPage;
  final VoidCallback onRefresh;
  final Future<void> Function(ManagedUserAccount user, ManagedUserFormResult result) onUpdateUser;
  final Future<void> Function(ManagedUserAccount user, bool isActive) onToggleActivation;
  final Future<void> Function(ManagedUserAccount user) onDeleteUser;
  final Future<Map<String, dynamic>> Function()? onGetDatabaseHealth;
  final Future<Map<String, dynamic>> Function()? onRunDatabaseCleanup;

  @override
  State<AllUsersView> createState() => _AllUsersViewState();
}

class _AllUsersViewState extends State<AllUsersView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  UserRole? _selectedRoleFilter;
  int _pageSize = 15;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    if (widget.pageData == null && !widget.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchData();
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _currentPage = 1;
      _fetchData();
    });
  }

  void _onClearSearch() {
    _searchController.clear();
    _currentPage = 1;
    _fetchData();
  }

  void _onRoleFilterSelected(UserRole? role) {
    if (_selectedRoleFilter == role) return;
    setState(() {
      _selectedRoleFilter = role;
      _currentPage = 1;
    });
    _fetchData();
  }

  void _onPageSizeChanged(int size) {
    if (_pageSize == size) return;
    setState(() {
      _pageSize = size;
      _currentPage = 1;
    });
    _fetchData();
  }

  void _changePage(int newPage) {
    setState(() => _currentPage = newPage);
    _fetchData();
  }

  void _fetchData() {
    final query = _searchController.text.trim();
    widget.onLoadPage(
      role: _selectedRoleFilter,
      page: _currentPage,
      pageSize: _pageSize,
      search: query.isNotEmpty ? query : null,
    );
  }

  Future<void> _openEditDialog(ManagedUserAccount user) async {
    final isSelf = user.id == widget.session.id;
    final result = await ManagedUserDialog.show(
      context,
      role: user.role,
      roleTitle: user.role.label,
      user: user,
      isSelf: isSelf,
      allowRoleSelection: true,
    );
    if (result == null || !mounted) return;
    await widget.onUpdateUser(user, result);
  }

  Future<void> _confirmDeleteUser(ManagedUserAccount user) async {
    if (user.id == widget.session.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendi süper kullanıcı hesabınızı silemezsiniz.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanıcıyı Sil'),
        content: Text(
          '"${user.fullName}" (#${user.id}) adlı kullanıcıyı kalıcı olarak silmek istediğinize emin misiniz?\n\n'
          'Kullanıcıya ait tüm yetkiler, kapı izinleri ve cihaz ilişkilendirmeleri temizlenecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.onDeleteUser(user);
    }
  }

  void _showUserDetailSheet(ManagedUserAccount user) {
    final isSelf = user.id == widget.session.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleColor = _getRoleColor(user.role, isDark);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isActivationBusy = widget.busyActivationUsers.contains(user.id);

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tutamaç (Drag Handle)
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Kullanıcı Başlık (Avatar, Ad Soyad, E-Posta)
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: roleColor.withValues(alpha: isDark ? 0.25 : 0.15),
                          child: Text(
                            user.fullName.trim().isEmpty ? '?' : user.fullName.trim()[0].toUpperCase(),
                            style: TextStyle(
                              color: roleColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user.fullName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                        color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                                      ),
                                    ),
                                  ),
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Siz',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.email,
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // Detay Satırları
                    _buildDetailRow('Kullanıcı ID', '#${user.id}', Icons.tag_rounded, isDark),
                    _buildDetailRow('Rolü', user.role.label, Icons.shield_outlined, isDark, badgeColor: roleColor),
                    _buildDetailRow(
                      'E-posta Onayı',
                      user.emailVerified ? 'Doğrulandı' : 'Doğrulanmadı',
                      user.emailVerified ? Icons.verified_rounded : Icons.pending_outlined,
                      isDark,
                      badgeColor: user.emailVerified ? AppColors.emerald : Colors.amber,
                    ),
                    if ((user.phoneNumber ?? '').isNotEmpty)
                      _buildDetailRow('Telefon', user.phoneNumber!, Icons.phone_rounded, isDark),
                    if (user.loginName != null && user.loginName!.isNotEmpty && user.loginName != user.email)
                      _buildDetailRow('Kullanıcı Adı', user.loginName!, Icons.account_box_outlined, isDark),
                    _buildDetailRow('Kayıt Tarihi', formatDateTime(user.createdAt), Icons.calendar_today_outlined, isDark),

                    // Aktif / Pasif Switch Satırı
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.power_settings_new_rounded, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Text(
                                'Hesap Durumu',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          isActivationBusy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Switch.adaptive(
                                  value: user.isActive,
                                  activeThumbColor: AppColors.primary,
                                  onChanged: isSelf
                                      ? null
                                      : (val) async {
                                          Navigator.pop(ctx);
                                          await widget.onToggleActivation(user, val);
                                        },
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Aksiyon Butonları (Düzenle & Sil)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openEditDialog(user);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Düzenle'),
                          ),
                        ),
                        if (!isSelf) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmDeleteUser(user);
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('Sil'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String title, String value, IconData icon, bool isDark, {Color? badgeColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Flexible(
            child: badgeColor != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  )
                : Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDbMaintenanceDialog() async {
    if (widget.onGetDatabaseHealth == null || widget.onRunDatabaseCleanup == null) {
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        bool isCleaning = false;
        Map<String, dynamic>? healthData;
        bool isLoadingHealth = true;
        String? errorMessage;
        String? cleanSuccessMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void loadHealth() async {
              try {
                final data = await widget.onGetDatabaseHealth!();
                if (ctx.mounted) {
                  setDialogState(() {
                    healthData = data;
                    isLoadingHealth = false;
                  });
                }
              } catch (e) {
                if (ctx.mounted) {
                  setDialogState(() {
                    errorMessage = e.toString();
                    isLoadingHealth = false;
                  });
                }
              }
            }

            if (isLoadingHealth && healthData == null && errorMessage == null) {
              loadHealth();
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final usersMap = healthData?['users'] as Map<String, dynamic>?;
            final structureMap = healthData?['structure'] as Map<String, dynamic>?;
            final devicesMap = healthData?['devices'] as Map<String, dynamic>?;
            final isClean = healthData?['isClean'] == true;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              actionsPadding: const EdgeInsets.all(16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isClean ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isClean ? Icons.verified_rounded : Icons.cleaning_services_rounded,
                      color: isClean ? Colors.green : Colors.orange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Veritabanı Sağlığı & Bakım',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: isLoadingHealth
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : errorMessage != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'Hata: $errorMessage',
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Durum Rozeti
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (isClean ? Colors.green : Colors.orange).withValues(alpha: isDark ? 0.2 : 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: (isClean ? Colors.green : Colors.orange).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isClean ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                        color: isClean ? Colors.green : Colors.orange,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isClean
                                              ? 'Veritabanı temiz ve optimize durumda.'
                                              : 'Veritabanında atık kayıtlar veya temizlenecek öğeler var.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isClean
                                                ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                                                : (isDark ? Colors.orange.shade300 : Colors.orange.shade800),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // İstatistik Kartları
                                if (usersMap != null) ...[
                                  _buildStatRow('Gerçek Kayıtlı Kullanıcı', '${usersMap['real'] ?? 0}', Colors.blue),
                                  _buildStatRow('Kukla / Sahte Kullanıcı', '${usersMap['dummy'] ?? 0}', usersMap['dummy'] == 0 ? Colors.green : Colors.red),
                                  _buildStatRow('Süper Kullanıcılar', '${usersMap['superUsers'] ?? 0}', Colors.purple),
                                  _buildStatRow('Site Yöneticileri', '${usersMap['siteManagers'] ?? 0}', Colors.teal),
                                ],
                                const Divider(height: 16),
                                if (structureMap != null) ...[
                                  _buildStatRow('Kayıtlı Siteler', '${structureMap['sites'] ?? 0}', Colors.indigo),
                                  _buildStatRow('Daireler & Kapılar', '${structureMap['apartments'] ?? 0} daire, ${structureMap['doors'] ?? 0} kapı', Colors.indigo),
                                ],
                                if (devicesMap != null) ...[
                                  _buildStatRow('ESP32 Donanımları', '${devicesMap['online'] ?? 0} çevrimiçi / ${devicesMap['total'] ?? 0} kayıtlı', Colors.amber),
                                ],

                                if (cleanSuccessMessage != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      cleanSuccessMessage!,
                                      style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: isCleaning ? null : () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isCleaning || isLoadingHealth
                      ? null
                      : () async {
                          setDialogState(() {
                            isCleaning = true;
                            cleanSuccessMessage = null;
                          });
                          try {
                            final res = await widget.onRunDatabaseCleanup!();
                            final totalCleaned = res['totalCleaned'] ?? 0;
                            final newHealth = await widget.onGetDatabaseHealth!();
                            if (ctx.mounted) {
                              setDialogState(() {
                                isCleaning = false;
                                healthData = newHealth;
                                cleanSuccessMessage = 'Temizlik tamamlandı: Toplam $totalCleaned adet gereksiz/süresi dolmuş kayıt temizlendi.';
                              });
                            }
                            widget.onRefresh();
                          } catch (e) {
                            if (ctx.mounted) {
                              setDialogState(() {
                                isCleaning = false;
                                cleanSuccessMessage = 'Hata: $e';
                              });
                            }
                          }
                        },
                  icon: isCleaning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_delete_rounded, size: 18),
                  label: Text(isCleaning ? 'Temizleniyor...' : 'Çöp Temizliği Yap'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatRow(String title, String value, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Color _getRoleColor(UserRole role, bool isDark) {
    switch (role) {
      case UserRole.superUser:
        return isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
      case UserRole.siteManager:
        return isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
      case UserRole.apartmentOwner:
        return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
      case UserRole.individual:
        return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayUsers = widget.users.where((u) => u.role != UserRole.superUser).toList();
    final totalUsers = widget.pageData?.total ?? displayUsers.length;
    final totalPages = widget.pageData?.totalPages ?? 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // 1. ÜST BAŞLIK KARTI
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.manage_accounts_rounded, color: AppColors.primary, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kullanıcı Yönetimi',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Toplam $totalUsers kayıtlı kullanıcı',
                            style: TextStyle(
                              color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onGetDatabaseHealth != null) ...[
                      IconButton.filledTonal(
                        onPressed: _showDbMaintenanceDialog,
                        icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                        tooltip: 'Veritabanı Sağlığı & Çöp Temizliği',
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton.filledTonal(
                      onPressed: widget.isLoading ? null : () => _fetchData(),
                      icon: widget.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      tooltip: 'Listeyi Yenile',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ARAMA ALANI (FİLTRE)
                TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {});
                    _onSearchChanged(val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Kişi adı, e-posta, kullanıcı kodu veya kullanıcı adı...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: _onClearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0x1FFFFFFF) : Colors.grey.shade300,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0x1FFFFFFF) : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ROL FİLTRE ÇİPLERİ
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Tüm Roller'),
                        selected: _selectedRoleFilter == null,
                        onSelected: (_) => _onRoleFilterSelected(null),
                        selectedColor: AppColors.primary.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Site Yöneticileri'),
                        selected: _selectedRoleFilter == UserRole.siteManager,
                        onSelected: (_) => _onRoleFilterSelected(UserRole.siteManager),
                        selectedColor: _getRoleColor(UserRole.siteManager, isDark).withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Daire Sakinleri'),
                        selected: _selectedRoleFilter == UserRole.apartmentOwner,
                        onSelected: (_) => _onRoleFilterSelected(UserRole.apartmentOwner),
                        selectedColor: _getRoleColor(UserRole.apartmentOwner, isDark).withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Bireysel Kullanıcılar'),
                        selected: _selectedRoleFilter == UserRole.individual,
                        onSelected: (_) => _onRoleFilterSelected(UserRole.individual),
                        selectedColor: _getRoleColor(UserRole.individual, isDark).withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. KULLANICI LİSTESİ ALANI
          if (widget.isLoading && displayUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (displayUsers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: AppDecorations.glassCard(context),
              child: Column(
                children: [
                  Icon(
                    Icons.person_search_rounded,
                    size: 56,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Kullanıcı Bulunamadı',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchController.text.isNotEmpty || _selectedRoleFilter != null
                        ? 'Arama kriterlerinize veya filtreye uygun kullanıcı kaydı bulunamadı.'
                        : 'Sistemde henüz kayıtlı kullanıcı bulunmuyor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty || _selectedRoleFilter != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        _onRoleFilterSelected(null);
                      },
                      icon: const Icon(Icons.clear_all_rounded),
                      label: const Text('Filtreleri Temizle'),
                    ),
                  ],
                ],
              ),
            )
          else
            ...displayUsers.map((user) {
              final isSelf = user.id == widget.session.id;
              final roleColor = _getRoleColor(user.role, isDark);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.9) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? const Color(0x20000000) : const Color(0x060F172A),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _showUserDetailSheet(user),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: roleColor.withValues(alpha: isDark ? 0.25 : 0.15),
                            child: Text(
                              user.fullName.trim().isEmpty ? '?' : user.fullName.trim()[0].toUpperCase(),
                              style: TextStyle(
                                color: roleColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        user.fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                    if (isSelf) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Siz',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

          // 3. SAYFALAMA KONTROLLERİ (PAGINATION)
          if (displayUsers.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(14),
              decoration: AppDecorations.glassCard(context),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        'Sayfa $_currentPage / $totalPages (Toplam $totalUsers kişi)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _pageSize,
                        underline: const SizedBox.shrink(),
                        icon: const Icon(Icons.arrow_drop_down, size: 18),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.accentLight : AppColors.primary,
                        ),
                        items: const [
                          DropdownMenuItem(value: 15, child: Text('15 / sf')),
                          DropdownMenuItem(value: 25, child: Text('25 / sf')),
                          DropdownMenuItem(value: 50, child: Text('50 / sf')),
                        ],
                        onChanged: (val) {
                          if (val != null) _onPageSizeChanged(val);
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // İlk sayfa
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        onPressed: _currentPage > 1 ? () => _changePage(1) : null,
                        icon: const Icon(Icons.first_page_rounded, size: 20),
                        tooltip: 'İlk Sayfa',
                      ),
                      const SizedBox(width: 4),
                      // Önceki sayfa
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        onPressed: _currentPage > 1 ? () => _changePage(_currentPage - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        tooltip: 'Önceki Sayfa',
                      ),
                      const SizedBox(width: 8),
                      // Sayfa göstergesi
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_currentPage',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sonraki sayfa
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        onPressed: _currentPage < totalPages ? () => _changePage(_currentPage + 1) : null,
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        tooltip: 'Sonraki Sayfa',
                      ),
                      const SizedBox(width: 4),
                      // Son sayfa
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        onPressed: _currentPage < totalPages ? () => _changePage(totalPages) : null,
                        icon: const Icon(Icons.last_page_rounded, size: 20),
                        tooltip: 'Son Sayfa',
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
    );
  }
}
