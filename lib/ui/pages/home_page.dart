import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/mqtt_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _pageSize = 10;

  late final MqttDoorService _doorService;
  SirketMenuItem _selectedMenu = SirketMenuItem.dashboard;

  final _profileFormKey = GlobalKey<FormState>();
  final _profileFullNameController = TextEditingController();
  final _profileEmailController = TextEditingController();
  final _profilePhoneController = TextEditingController();
  final _profilePasswordController = TextEditingController();
  bool _isSavingProfile = false;

  final Map<UserRole, ManagedUserPage> _managedPages = {};
  final Set<UserRole> _loadingRoles = <UserRole>{};
  final Set<int> _busyActivationUsers = <int>{};
  final Set<int> _busyDeleteUsers = <int>{};

  @override
  void initState() {
    super.initState();
    final session = widget.authService.session;
    if (session != null) {
      _profileFullNameController.text = session.fullName;
      _profileEmailController.text = session.email;
      _profilePhoneController.text = session.phoneNumber ?? '';
    }

    _doorService = MqttDoorService(
      host: mqttHost,
      port: mqttPort,
      username: mqttAppUser,
      password: mqttAppPassword,
      siteId: mqttSiteId,
      doorId: mqttDoorId,
    );
    _doorService.connect();
  }

  @override
  void dispose() {
    _profileFullNameController.dispose();
    _profileEmailController.dispose();
    _profilePhoneController.dispose();
    _profilePasswordController.dispose();
    _doorService.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  UserRole? _roleForMenu(SirketMenuItem item) {
    switch (item) {
      case SirketMenuItem.superUserYonetimi:
        return UserRole.superUser;
      case SirketMenuItem.siteYoneticileriYonetimi:
        return UserRole.siteManager;
      case SirketMenuItem.daireKullanicilariYonetimi:
        return UserRole.apartmentOwner;
      case SirketMenuItem.dashboard:
      case SirketMenuItem.profilim:
        return null;
    }
  }

  String _titleForMenu(SirketMenuItem item) {
    switch (item) {
      case SirketMenuItem.dashboard:
        return 'Sirket Paneli';
      case SirketMenuItem.profilim:
        return 'Profilim';
      case SirketMenuItem.superUserYonetimi:
        return 'Super User Yonetimi';
      case SirketMenuItem.siteYoneticileriYonetimi:
        return 'Site Yoneticileri Yonetimi';
      case SirketMenuItem.daireKullanicilariYonetimi:
        return 'Daire Kullanicilari Yonetimi';
    }
  }

  String _roleTitle(UserRole role) {
    switch (role) {
      case UserRole.superUser:
        return 'Super User';
      case UserRole.siteManager:
        return 'Site Yoneticisi';
      case UserRole.apartmentOwner:
        return 'Daire Kullanici';
    }
  }

  String _rolePlural(UserRole role) {
    switch (role) {
      case UserRole.superUser:
        return 'Super User Hesaplari';
      case UserRole.siteManager:
        return 'Site Yoneticileri';
      case UserRole.apartmentOwner:
        return 'Daire Kullanicilari';
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  void _selectMenu(SirketMenuItem item) {
    Navigator.pop(context);
    setState(() => _selectedMenu = item);
    final role = _roleForMenu(item);
    if (role != null) {
      _loadManagedUsers(role);
    }
  }

  Future<void> _loadManagedUsers(
    UserRole role, {
    bool force = false,
    int? page,
  }) async {
    if (_loadingRoles.contains(role)) {
      return;
    }

    final existing = _managedPages[role];
    final targetPage = page ?? existing?.page ?? 1;
    if (!force && existing != null && page == null) {
      return;
    }

    setState(() => _loadingRoles.add(role));
    try {
      final result = await widget.authService.listManagedUsers(
        role: role,
        page: targetPage,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() => _managedPages[role] = result);
    } on ApiException catch (e) {
      if (mounted) {
        _showMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('${_rolePlural(role)} alinamadi.');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingRoles.remove(role));
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!(_profileFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSavingProfile = true);
    final error = await widget.authService.updateMyProfile(
      fullName: _profileFullNameController.text.trim(),
      email: _profileEmailController.text.trim().toLowerCase(),
      phoneNumber: _profilePhoneController.text.trim(),
      password: _profilePasswordController.text.trim().isEmpty
          ? null
          : _profilePasswordController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    setState(() => _isSavingProfile = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    final session = widget.authService.session!;
    _profileFullNameController.text = session.fullName;
    _profileEmailController.text = session.email;
    _profilePhoneController.text = session.phoneNumber ?? '';
    _profilePasswordController.clear();
    setState(() {});
    _showMessage('Profil bilgileri guncellendi.');
  }

  Future<void> _openDoor() async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }

    final error = await _doorService.sendPulseCommand(requestedBy: session.email);
    if (!mounted) {
      return;
    }
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Kapi acma komutu gonderildi.');
  }

  Future<void> _openManagedUserDialog({
    required UserRole role,
    ManagedUserAccount? user,
  }) async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }

    final result = await showDialog<_ManagedUserFormResult>(
      context: context,
      builder: (dialogContext) => _ManagedUserDialog(
        role: role,
        roleTitle: _roleTitle(role),
        user: user,
        isSelf: user?.id == session.id,
      ),
    );

    if (result == null) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    final isEditing = user != null;
    final error = isEditing
        ? await widget.authService.updateManagedUser(
            userCode: user.id,
            fullName: result.fullName,
            email: result.email,
            password: result.password.isEmpty ? null : result.password,
            phoneNumber: result.phoneNumber,
            isActive: result.isActive,
          )
        : await widget.authService.createManagedUser(
            fullName: result.fullName,
            email: result.email,
            password: result.password,
            role: role,
            isActive: result.isActive,
            phoneNumber: result.phoneNumber,
          );

    if (!mounted) {
      return;
    }

    if (error != null) {
      _showMessage(error);
      return;
    }

    final targetPage = isEditing ? _managedPages[role]?.page ?? 1 : 1;
    await _loadManagedUsers(role, force: true, page: targetPage);
    if (!mounted) {
      return;
    }

    _showMessage(
      isEditing
          ? '${_roleTitle(role)} bilgisi guncellendi.'
          : '${_roleTitle(role)} hesabi olusturuldu.',
    );
  }

  Future<void> _toggleUserActivation({
    required UserRole role,
    required ManagedUserAccount user,
    required bool value,
  }) async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }
    if (session.id == user.id) {
      _showMessage('Kendi super user hesabinizi pasif yapamazsiniz.');
      return;
    }

    setState(() => _busyActivationUsers.add(user.id));
    final error = await widget.authService.setManagedUserActivation(
      userCode: user.id,
      isActive: value,
    );

    if (!mounted) {
      return;
    }

    setState(() => _busyActivationUsers.remove(user.id));
    if (error != null) {
      _showMessage(error);
      return;
    }

    final pageData = _managedPages[role];
    if (pageData != null) {
      final updatedUsers = pageData.users
          .map((item) => item.id == user.id ? item.copyWith(isActive: value) : item)
          .toList();
      setState(() {
        _managedPages[role] = pageData.copyWith(users: updatedUsers);
      });
    }

    _showMessage(
      value
          ? '${_roleTitle(role)} hesabi aktif edildi.'
          : '${_roleTitle(role)} hesabi pasif edildi.',
    );
  }

  Future<void> _deleteManagedUser({
    required UserRole role,
    required ManagedUserAccount user,
  }) async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }
    if (session.id == user.id) {
      _showMessage('Kendi hesabinizi silemezsiniz.');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${_roleTitle(role)} Sil'),
            content: Text(
              '${user.fullName} hesabini silmek istediginize emin misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgec'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sil'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() => _busyDeleteUsers.add(user.id));
    final error = await widget.authService.deleteManagedUser(userCode: user.id);

    if (!mounted) {
      return;
    }

    setState(() => _busyDeleteUsers.remove(user.id));
    if (error != null) {
      _showMessage(error);
      return;
    }

    final currentPage = _managedPages[role];
    final targetPage =
        currentPage != null && currentPage.users.length == 1 && currentPage.page > 1
            ? currentPage.page - 1
            : currentPage?.page ?? 1;

    await _loadManagedUsers(role, force: true, page: targetPage);
    if (!mounted) {
      return;
    }
    _showMessage('${_roleTitle(role)} hesabi silindi.');
  }

  Widget _buildDashboard(UserSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hos Geldiniz',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                session.fullName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 28,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sandwich menuden super user, site yoneticisi ve daire kullanicisi hesaplarini yonetebilirsiniz.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _doorService,
          builder: (context, _) {
            final connectionText = _doorService.connected
                ? 'Bagli'
                : _doorService.connecting
                    ? 'Baglaniyor'
                    : 'Bagli degil';
            final stateText = _doorService.doorLocked == null
                ? 'Bilinmiyor'
                : (_doorService.doorLocked! ? 'Kilitli' : 'Acik/Tetiklenmis');

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: AppDecorations.glassCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kapi Kontrol',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('MQTT: $connectionText'),
                  const SizedBox(height: 6),
                  Text('Kapi Durumu: $stateText'),
                  if (_doorService.lastUpdatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text('Son Guncelleme: ${_formatDate(_doorService.lastUpdatedAt)}'),
                  ],
                  if (_doorService.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _doorService.lastError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _doorService.commandEnabled ? _openDoor : null,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Kapi Ac'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildProfile(UserSession session) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.glassCard,
      child: Form(
        key: _profileFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kendi Bilgilerini Duzenle',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profileFullNameController,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
              validator: (value) => (value ?? '').trim().length < 3
                  ? 'Ad Soyad en az 3 karakter olmali.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profileEmailController,
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty || !text.contains('@')
                    ? 'Gecerli bir e-posta girin.'
                    : null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profilePhoneController,
              decoration: const InputDecoration(labelText: 'Telefon (opsiyonel)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profilePasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Yeni Sifre (opsiyonel)'),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isNotEmpty && text.length < 6
                    ? 'Sifre en az 6 karakter olmali.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingProfile ? null : _saveProfile,
                icon: _isSavingProfile
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isSavingProfile ? 'Kaydediliyor...' : 'Profili Kaydet',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Kullanici Kodu: ${session.id}'),
            if (session.createdAt != null) ...[
              const SizedBox(height: 4),
              Text('Kayit Tarihi: ${_formatDate(session.createdAt)}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManagedRoleScreen(UserRole role, UserSession session) {
    final pageData = _managedPages[role];
    final users = pageData?.users ?? const <ManagedUserAccount>[];
    final loading = _loadingRoles.contains(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rolePlural(role),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ekle, duzenle, sil ve aktivasyon ac/kapat islemleri bu ekrandan yapilir.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openManagedUserDialog(role: role),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text('Yeni ${_roleTitle(role)}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pageData == null
                          ? _rolePlural(role)
                          : '${_rolePlural(role)} (${pageData.total})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: loading
                        ? null
                        : () => _loadManagedUsers(role, force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (loading && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (users.isEmpty)
                Text('Kayitli ${_rolePlural(role).toLowerCase()} bulunamadi.')
              else ...[
                for (final user in users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ManagedUserCard(
                      user: user,
                      isSelf: user.id == session.id,
                      activationBusy: _busyActivationUsers.contains(user.id),
                      deleteBusy: _busyDeleteUsers.contains(user.id),
                      formattedCreatedAt: _formatDate(user.createdAt),
                      onActivationChanged: (value) => _toggleUserActivation(
                        role: role,
                        user: user,
                        value: value,
                      ),
                      onEdit: () => _openManagedUserDialog(role: role, user: user),
                      onDelete: () => _deleteManagedUser(role: role, user: user),
                    ),
                  ),
                if (pageData != null)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Sayfa ${pageData.page} / ${pageData.totalPages} | Toplam ${pageData.total}',
                      ),
                      OutlinedButton.icon(
                        onPressed: pageData.page > 1
                            ? () => _loadManagedUsers(
                                  role,
                                  force: true,
                                  page: pageData.page - 1,
                                )
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Onceki'),
                      ),
                      OutlinedButton.icon(
                        onPressed: pageData.page < pageData.totalPages
                            ? () => _loadManagedUsers(
                                  role,
                                  force: true,
                                  page: pageData.page + 1,
                                )
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Sonraki'),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(UserSession session) {
    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
        return _buildDashboard(session);
      case SirketMenuItem.profilim:
        return _buildProfile(session);
      case SirketMenuItem.superUserYonetimi:
        return _buildManagedRoleScreen(UserRole.superUser, session);
      case SirketMenuItem.siteYoneticileriYonetimi:
        return _buildManagedRoleScreen(UserRole.siteManager, session);
      case SirketMenuItem.daireKullanicilariYonetimi:
        return _buildManagedRoleScreen(UserRole.apartmentOwner, session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.authService.session!;
    return Scaffold(
      appBar: AppBar(title: Text(_titleForMenu(_selectedMenu))),
      drawer: YanMenu(
        fullName: session.fullName,
        userEmail: session.email,
        selectedItem: _selectedMenu,
        onSelect: _selectMenu,
        onLogout: () {
          Navigator.pop(context);
          widget.authService.logout();
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildContent(session),
      ),
    );
  }
}

class _ManagedUserCard extends StatelessWidget {
  const _ManagedUserCard({
    required this.user,
    required this.isSelf,
    required this.activationBusy,
    required this.deleteBusy,
    required this.formattedCreatedAt,
    required this.onActivationChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final ManagedUserAccount user;
  final bool isSelf;
  final bool activationBusy;
  final bool deleteBusy;
  final String formattedCreatedAt;
  final ValueChanged<bool> onActivationChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.infoCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  user.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(user.isActive ? 'Aktif' : 'Pasif'),
              const SizedBox(width: 8),
              activationBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch.adaptive(
                      value: user.isActive,
                      onChanged: isSelf ? null : onActivationChanged,
                    ),
            ],
          ),
          const SizedBox(height: 8),
          Text(user.email),
          const SizedBox(height: 4),
          Text('Kod: ${user.id}'),
          if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Telefon: ${user.phoneNumber}'),
          ],
          const SizedBox(height: 4),
          Text('Kayit Tarihi: $formattedCreatedAt'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Duzenle'),
              ),
              ElevatedButton.icon(
                onPressed: isSelf || deleteBusy ? null : onDelete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                icon: deleteBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                label: const Text('Sil'),
              ),
            ],
          ),
          if (isSelf) ...[
            const SizedBox(height: 8),
            const Text(
              'Kendi super user hesabiniza silme ve pasif etme kilidi uygulanir.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManagedUserDialog extends StatefulWidget {
  const _ManagedUserDialog({
    required this.role,
    required this.roleTitle,
    required this.user,
    required this.isSelf,
  });

  final UserRole role;
  final String roleTitle;
  final ManagedUserAccount? user;
  final bool isSelf;

  @override
  State<_ManagedUserDialog> createState() => _ManagedUserDialogState();
}

class _ManagedUserDialogState extends State<_ManagedUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late bool _isActive;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.user?.fullName ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _phoneController = TextEditingController(text: widget.user?.phoneNumber ?? '');
    _passwordController = TextEditingController();
    _isActive = widget.user?.isActive ?? (widget.role == UserRole.superUser);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _ManagedUserFormResult(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        phoneNumber: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing
            ? '${widget.roleTitle} Duzenle'
            : 'Yeni ${widget.roleTitle} Ekle',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'Ad Soyad en az 3 karakter olmali.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-posta'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    return text.isEmpty || !text.contains('@')
                        ? 'Gecerli bir e-posta girin.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon (opsiyonel)',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return null;
                    }
                    return RegExp(r'^\+?[0-9()\-\s]{10,20}$').hasMatch(text)
                        ? null
                        : 'Gecerli bir telefon numarasi girin.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isEditing
                        ? 'Yeni Sifre (opsiyonel)'
                        : 'Sifre',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (!_isEditing && text.length < 6) {
                      return 'Sifre en az 6 karakter olmali.';
                    }
                    if (_isEditing && text.isNotEmpty && text.length < 6) {
                      return 'Sifre en az 6 karakter olmali.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _isActive,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: Text(
                    _isActive
                        ? 'Kullanici giris yapabilir.'
                        : 'Kullanici giris yapamaz.',
                  ),
                  onChanged: widget.isSelf
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
                if (widget.isSelf)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Kendi super user hesabinizi burada pasif yapamazsiniz.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Iptal'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _ManagedUserFormResult {
  const _ManagedUserFormResult({
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.password,
    required this.isActive,
  });

  final String fullName;
  final String email;
  final String phoneNumber;
  final String password;
  final bool isActive;
}
