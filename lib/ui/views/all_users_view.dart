import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

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
      AppSnack.show(context, 'Kendi süper kullanıcı hesabınızı silemezsiniz.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Kullanıcıyı Sil',
        icon: Icons.delete_outline_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: filledToneStyle(ctx, tone: AppTone.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Sil'),
          ),
        ],
        child: Text(
          '"${user.fullName}" (#${user.id}) adlı kullanıcıyı kalıcı olarak silmek istediğinize emin misiniz?\n\n'
          'Kullanıcıya ait tüm yetkiler, kapı izinleri ve cihaz ilişkilendirmeleri temizlenecektir.',
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await widget.onDeleteUser(user);
    }
  }

  void _showUserDetailSheet(ManagedUserAccount user) {
    final isSelf = user.id == widget.session.id;
    final tone = user.role.tone;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final p = context.palette;
            final th = Theme.of(context).textTheme;
            final isActivationBusy = widget.busyActivationUsers.contains(user.id);
            // Dar ekran / büyük yazıda eylem düğmeleri alt alta (yan yana yarım genişlik harfleri böler).
            final stackActions =
                MediaQuery.sizeOf(context).width < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final edit = FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTone.primary.a,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _openEditDialog(user);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Düzenle'),
            );
            final delete = OutlinedButton.icon(
              style: dangerOutlineStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDeleteUser(user);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Sil'),
            );

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.md,
                  AppSpace.xl,
                  AppSpace.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tutamaç (Drag Handle)
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: AppSpace.lg),
                        decoration: BoxDecoration(
                          color: p.textMuted.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Kullanıcı Başlık (Avatar, Ad Soyad, E-Posta)
                    Row(
                      children: [
                        InitialAvatar(
                          name: user.fullName,
                          tone: tone,
                          radius: 26,
                          gap: AppSpace.md,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: AppSpace.sm,
                                runSpacing: AppSpace.xs,
                                children: [
                                  Text(user.fullName, style: th.titleLarge),
                                  if (isSelf)
                                    const StatusChip(
                                      label: 'Siz',
                                      tone: AppTone.primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(user.email, style: th.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    const Divider(),
                    const SizedBox(height: AppSpace.md),

                    // Detay Satırları
                    _buildDetailRow(context, 'Kullanıcı ID', '#${user.id}', Icons.tag_rounded),
                    _buildDetailRow(context, 'Rolü', user.role.label, Icons.shield_outlined, badgeTone: tone),
                    _buildDetailRow(
                      context,
                      'E-posta Onayı',
                      user.emailVerified ? 'Doğrulandı' : 'Doğrulanmadı',
                      user.emailVerified ? Icons.verified_rounded : Icons.pending_outlined,
                      badgeTone: user.emailVerified ? AppTone.success : AppTone.warning,
                    ),
                    if ((user.phoneNumber ?? '').isNotEmpty)
                      _buildDetailRow(context, 'Telefon', user.phoneNumber!, Icons.phone_rounded),
                    if (user.loginName != null && user.loginName!.isNotEmpty && user.loginName != user.email)
                      _buildDetailRow(context, 'Kullanıcı Adı', user.loginName!, Icons.account_box_outlined),
                    _buildDetailRow(context, 'Kayıt Tarihi', formatDateTime(user.createdAt), Icons.calendar_today_outlined),

                    // Aktif / Pasif Switch Satırı
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                      child: _SpreadRow(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.power_settings_new_rounded,
                                size: 18,
                                color: p.textSecondary,
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Flexible(
                                child: Text('Hesap Durumu', style: th.bodyMedium),
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
                                  activeThumbColor: AppTone.primary.a,
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

                    const SizedBox(height: AppSpace.lg),

                    // Aksiyon Butonları (Düzenle & Sil)
                    if (stackActions) ...[
                      edit,
                      if (!isSelf) ...[
                        const SizedBox(height: AppSpace.sm),
                        delete,
                      ],
                    ] else
                      Row(
                        children: [
                          Expanded(child: edit),
                          if (!isSelf) ...[
                            const SizedBox(width: AppSpace.md),
                            Expanded(child: delete),
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

  /// Detay satırı: soldaki ikon + başlık, sağdaki değer (ya da ton rozeti). Sığmazsa değer alta iner
  /// (büyük yazıda taşma yok).
  Widget _buildDetailRow(
    BuildContext context,
    String title,
    String value,
    IconData icon, {
    AppTone? badgeTone,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: _SpreadRow(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: p.textSecondary),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: Text(title, style: th.bodyMedium)),
            ],
          ),
          badgeTone != null
              ? StatusChip(label: value, tone: badgeTone)
              : Text(
                  value,
                  style: th.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
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

            final usersMap = healthData?['users'] as Map<String, dynamic>?;
            final structureMap = healthData?['structure'] as Map<String, dynamic>?;
            final devicesMap = healthData?['devices'] as Map<String, dynamic>?;
            final isClean = healthData?['isClean'] == true;
            final statusTone = isClean ? AppTone.success : AppTone.warning;
            final cleanNote = cleanSuccessMessage;

            final Widget body = isLoadingHealth
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpace.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : errorMessage != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                          child: InlineNotice(
                            message: 'Hata: $errorMessage',
                            tone: AppTone.danger,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Durum Rozeti
                            InlineNotice(
                              message: isClean
                                  ? 'Veritabanı temiz ve optimize durumda.'
                                  : 'Veritabanında atık kayıtlar veya temizlenecek öğeler var.',
                              tone: statusTone,
                              icon: isClean
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                            ),
                            const SizedBox(height: AppSpace.md),

                            // İstatistik Satırları
                            if (usersMap != null) ...[
                              _buildStatRow(context, 'Gerçek Kayıtlı Kullanıcı', '${usersMap['real'] ?? 0}', AppTone.primary),
                              _buildStatRow(context, 'Kukla / Sahte Kullanıcı', '${usersMap['dummy'] ?? 0}', usersMap['dummy'] == 0 ? AppTone.success : AppTone.danger),
                              _buildStatRow(context, 'Süper Kullanıcılar', '${usersMap['superUsers'] ?? 0}', AppTone.violet),
                              _buildStatRow(context, 'Site Yöneticileri', '${usersMap['siteManagers'] ?? 0}', AppTone.success),
                            ],
                            const Divider(height: AppSpace.lg),
                            if (structureMap != null) ...[
                              _buildStatRow(context, 'Kayıtlı Siteler', '${structureMap['sites'] ?? 0}', AppTone.primary),
                              _buildStatRow(context, 'Daireler & Kapılar', '${structureMap['apartments'] ?? 0} daire, ${structureMap['doors'] ?? 0} kapı', AppTone.primary),
                            ],
                            if (devicesMap != null) ...[
                              _buildStatRow(context, 'ESP32 Donanımları', '${devicesMap['online'] ?? 0} çevrimiçi / ${devicesMap['total'] ?? 0} kayıtlı', AppTone.warning),
                            ],

                            if (cleanNote != null) ...[
                              const SizedBox(height: AppSpace.md),
                              InlineNotice(
                                key: ValueKey<String>(cleanNote),
                                message: cleanNote,
                                tone: cleanNote.startsWith('Hata:')
                                    ? AppTone.danger
                                    : AppTone.success,
                              ),
                            ],
                          ],
                        );

            return AppDialog(
              title: 'Veritabanı Sağlığı & Bakım',
              icon: isClean ? Icons.verified_rounded : Icons.cleaning_services_rounded,
              tone: statusTone,
              actions: [
                TextButton(
                  onPressed: isCleaning ? null : () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
                ),
                ElevatedButton.icon(
                  style: filledToneStyle(context),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_delete_rounded, size: 18),
                  label: Text(isCleaning ? 'Temizleniyor...' : 'Çöp Temizliği Yap'),
                ),
              ],
              child: body,
            );
          },
        );
      },
    );
  }

  /// İstatistik satırı: başlık + ton rozeti. Sığmazsa rozet alta iner (taşma yok).
  Widget _buildStatRow(
    BuildContext context,
    String title,
    String value,
    AppTone tone,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: _SpreadRow(
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          InfoChip(value, tone: tone),
        ],
      ),
    );
  }

  Widget _roleChip(BuildContext context, String label, UserRole? role, AppTone tone) {
    final p = context.palette;
    final selected = _selectedRoleFilter == role;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _onRoleFilterSelected(role),
      selectedColor: Color.alphaBlend(tone.tint(p), p.surface),
      checkmarkColor: tone.ink(p),
      labelStyle: TextStyle(
        color: selected ? tone.ink(p) : p.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected ? tone.hue.withValues(alpha: 0.5) : p.border,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final displayUsers = widget.users.where((u) => u.role != UserRole.superUser).toList();
    final totalUsers = widget.pageData?.total ?? displayUsers.length;
    final totalPages = widget.pageData?.totalPages ?? 1;
    final hasFilter = _searchController.text.isNotEmpty || _selectedRoleFilter != null;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: p.border),
    );
    const buttonSize = BoxConstraints(minWidth: 44, minHeight: 44);
    final stackActions =
        MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
        MediaQuery.sizeOf(context).width < 340;
    final headerActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onGetDatabaseHealth != null) ...[
          IconButton.filledTonal(
            onPressed: _showDbMaintenanceDialog,
            icon: const Icon(Icons.cleaning_services_rounded, size: 20),
            tooltip: 'Veritabanı Sağlığı & Çöp Temizliği',
          ),
          const SizedBox(width: AppSpace.sm),
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // 1. ÜST BAŞLIK KARTI
          AppCard(
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  icon: Icons.manage_accounts_rounded,
                  title: 'Kullanıcı Yönetimi',
                  trailing: stackActions ? null : headerActions,
                ),
                // Büyük yazı / dar ekranda başlık ve eylemler yan yana sığmaz: eylemler başlığın altına
                // iner (başlık sözcük ortasından bölünmez).
                if (stackActions) ...[
                  const SizedBox(height: AppSpace.sm),
                  headerActions,
                ],
                const SizedBox(height: AppSpace.xs),
                Text('Toplam $totalUsers kayıtlı kullanıcı', style: th.bodyMedium),
                const SizedBox(height: AppSpace.lg),

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
                    fillColor: p.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                    border: fieldBorder,
                    enabledBorder: fieldBorder,
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                // ROL FİLTRE ÇİPLERİ (yatay kaydırma yok: sığmayan çip alta iner)
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    _roleChip(context, 'Tüm Roller', null, AppTone.primary),
                    _roleChip(context, 'Site Yöneticileri', UserRole.siteManager, UserRole.siteManager.tone),
                    _roleChip(context, 'Daire Sakinleri', UserRole.apartmentOwner, UserRole.apartmentOwner.tone),
                    _roleChip(context, 'Bireysel Kullanıcılar', UserRole.individual, UserRole.individual.tone),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),

          // 2. KULLANICI LİSTESİ ALANI
          if (widget.isLoading && displayUsers.isEmpty)
            const ListSkeleton()
          else if (displayUsers.isEmpty)
            EmptyCard(
              icon: Icons.person_search_rounded,
              title: 'Kullanıcı Bulunamadı',
              message: hasFilter
                  ? 'Arama kriterlerinize veya filtreye uygun kullanıcı kaydı bulunamadı.'
                  : 'Sistemde henüz kayıtlı kullanıcı bulunmuyor.',
              child: hasFilter
                  ? OutlinedButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        _onRoleFilterSelected(null);
                      },
                      icon: const Icon(Icons.clear_all_rounded),
                      label: const Text('Filtreleri Temizle'),
                    )
                  : null,
            )
          else
            for (var i = 0; i < displayUsers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: StaggeredEntry(
                  index: i,
                  child: _buildUserRow(context, displayUsers[i]),
                ),
              ),

          // 3. SAYFALAMA KONTROLLERİ (PAGINATION)
          if (displayUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpace.md),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                  spacing: AppSpace.md,
                  runSpacing: AppSpace.sm,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      children: [
                        Text(
                          'Sayfa $_currentPage / $totalPages (Toplam $totalUsers kişi)',
                          style: th.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                        DropdownButton<int>(
                          value: _pageSize,
                          underline: const SizedBox.shrink(),
                          icon: const Icon(Icons.arrow_drop_down, size: 18),
                          style: th.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTone.primary.ink(p),
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
                    Wrap(
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // İlk sayfa
                        IconButton.outlined(
                          constraints: buttonSize,
                          onPressed: _currentPage > 1 ? () => _changePage(1) : null,
                          icon: const Icon(Icons.first_page_rounded, size: 20),
                          tooltip: 'İlk Sayfa',
                        ),
                        // Önceki sayfa
                        IconButton.outlined(
                          constraints: buttonSize,
                          onPressed: _currentPage > 1 ? () => _changePage(_currentPage - 1) : null,
                          icon: const Icon(Icons.chevron_left_rounded, size: 20),
                          tooltip: 'Önceki Sayfa',
                        ),
                        // Sayfa göstergesi
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTone.primary.tint(p),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.md,
                                vertical: AppSpace.sm,
                              ),
                              child: Text(
                                '$_currentPage',
                                style: th.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTone.primary.ink(p),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Sonraki sayfa
                        IconButton.outlined(
                          constraints: buttonSize,
                          onPressed: _currentPage < totalPages ? () => _changePage(_currentPage + 1) : null,
                          icon: const Icon(Icons.chevron_right_rounded, size: 20),
                          tooltip: 'Sonraki Sayfa',
                        ),
                        // Son sayfa
                        IconButton.outlined(
                          constraints: buttonSize,
                          onPressed: _currentPage < totalPages ? () => _changePage(totalPages) : null,
                          icon: const Icon(Icons.last_page_rounded, size: 20),
                          tooltip: 'Son Sayfa',
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ),
            ),
        ],
    );
  }

  /// Kullanıcı satırı: dokununca detay alt sayfası açılır. Avatar rengi rol tonu.
  Widget _buildUserRow(BuildContext context, ManagedUserAccount user) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isSelf = user.id == widget.session.id;
    return AppCard(
      onTap: () => _showUserDetailSheet(user),
      padding: listCardPadding(context),
      child: Row(
        children: [
          InitialAvatar(
            name: user.fullName,
            tone: user.role.tone,
            gap: AppSpace.md,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: th.titleMedium,
                    ),
                    if (isSelf)
                      const StatusChip(label: 'Siz', tone: AppTone.primary),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  user.email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: th.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          ExcludeSemantics(
            child: Icon(
              Icons.chevron_right_rounded,
              color: p.textMuted,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soldaki ve sağdaki öğeyi iki uca yaslayan satır; sığmazsa sağdaki öğe alta iner (büyük yazıda
/// taşma yok). Tam genişlik kaplar (düz `Wrap` içeriğine sarılıp yaslamayı kaybederdi).
class _SpreadRow extends StatelessWidget {
  const _SpreadRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.sm,
        runSpacing: AppSpace.xs,
        children: children,
      ),
    );
  }
}
