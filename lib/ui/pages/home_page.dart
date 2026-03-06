import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/super_user_account.dart';
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
  late final MqttDoorService _doorService;

  SirketMenuItem _selectedMenu = SirketMenuItem.dashboard;

  final _profileFormKey = GlobalKey<FormState>();
  final _profileFullNameController = TextEditingController();
  final _profileEmailController = TextEditingController();
  final _profilePhoneController = TextEditingController();
  final _profilePasswordController = TextEditingController();
  bool _isSavingProfile = false;

  final _superUserFormKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCreatingSuperUser = false;

  bool _loadingSuperUsers = false;
  bool _superUsersLoaded = false;
  List<SuperUserAccount> _superUsers = const [];

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

    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();

    _doorService.dispose();
    super.dispose();
  }

  void _selectMenu(SirketMenuItem item) {
    Navigator.pop(context);
    if (_selectedMenu == item) {
      return;
    }
    setState(() => _selectedMenu = item);
    if (item == SirketMenuItem.superUserYonetimi) {
      _loadSuperUsers(force: !_superUsersLoaded);
    }
  }

  String _titleByMenu(SirketMenuItem item) {
    switch (item) {
      case SirketMenuItem.dashboard:
        return 'Sirket Paneli';
      case SirketMenuItem.profilim:
        return 'Profilim';
      case SirketMenuItem.superUserYonetimi:
        return 'Super User Yonetimi';
    }
  }

  Future<void> _loadSuperUsers({bool force = false}) async {
    if (_loadingSuperUsers) {
      return;
    }
    if (!force && _superUsersLoaded) {
      return;
    }

    setState(() => _loadingSuperUsers = true);
    try {
      final users = await widget.authService.listSuperUsers();
      if (!mounted) {
        return;
      }
      setState(() {
        _superUsers = users;
        _superUsersLoaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Super user listesi alinamadi.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingSuperUsers = false);
      }
    }
  }

  Future<void> _openDoor() async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }

    final error = await _doorService.sendPulseCommand(
      requestedBy: session.email,
    );

    if (!mounted) {
      return;
    }

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kapi acma komutu gonderildi.')),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final session = widget.authService.session!;
    _profileFullNameController.text = session.fullName;
    _profileEmailController.text = session.email;
    _profilePhoneController.text = session.phoneNumber ?? '';
    _profilePasswordController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil bilgileri guncellendi.')),
    );
  }

  Future<void> _createSuperUser() async {
    if (!(_superUserFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isCreatingSuperUser = true);

    final error = await widget.authService.createSuperUser(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    setState(() => _isCreatingSuperUser = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    _fullNameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _passwordController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Yeni super user basariyla olusturuldu.')),
    );
    await _loadSuperUsers(force: true);
  }

  Future<void> _editSuperUser(SuperUserAccount user) async {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(text: user.fullName);
    final emailController = TextEditingController(text: user.email);
    final phoneController = TextEditingController(text: user.phoneNumber ?? '');
    final passwordController = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }
              setDialogState(() => saving = true);
              final error = await widget.authService.updateSuperUser(
                userCode: user.id,
                fullName: fullNameController.text.trim(),
                email: emailController.text.trim().toLowerCase(),
                phoneNumber: phoneController.text.trim(),
                password: passwordController.text.trim().isEmpty
                    ? null
                    : passwordController.text.trim(),
              );
              if (!mounted) {
                return;
              }
              setDialogState(() => saving = false);
              if (error != null) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(error)),
                );
                return;
              }
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop();
              await _loadSuperUsers(force: true);
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Super user bilgisi guncellendi.')),
              );
            }

            return AlertDialog(
              title: const Text('Super User Duzenle'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameController,
                        decoration: const InputDecoration(labelText: 'Ad Soyad'),
                        validator: (value) {
                          if ((value ?? '').trim().length < 3) {
                            return 'Ad Soyad en az 3 karakter olmali.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: 'E-posta'),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty || !text.contains('@')) {
                            return 'Gecerli bir e-posta girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Telefon (opsiyonel)',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return null;
                          }
                          if (!RegExp(r'^\+?[0-9()\-\s]{10,20}$').hasMatch(text)) {
                            return 'Gecerli bir telefon numarasi girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Yeni Sifre (opsiyonel)',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isNotEmpty && text.length < 6) {
                            return 'Sifre en az 6 karakter olmali.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Iptal'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
  }

  Future<void> _deleteSuperUser(SuperUserAccount user) async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }
    if (session.id == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendi hesabinizi silemezsiniz.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Super User Sil'),
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

    final error = await widget.authService.deleteSuperUser(userCode: user.id);
    if (!mounted) {
      return;
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Super user silindi.')),
    );
    await _loadSuperUsers(force: true);
  }

  String _doorStateText(bool? locked) {
    if (locked == null) {
      return 'Bilinmiyor';
    }
    return locked ? 'Kilitli' : 'Acik/Tetiklenmis';
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
              const SizedBox(height: 6),
              const Text('Super user yonetim paneli'),
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
            final stateText = _doorStateText(_doorService.doorLocked);

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
                    Text(
                      'Son Guncelleme: ${_doorService.lastUpdatedAt!.toLocal()}',
                    ),
                  ],
                  if (_doorService.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _doorService.lastError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_doorService.lastEvent != null &&
                      _doorService.lastEvent!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Son Event: ${_doorService.lastEvent}'),
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
              validator: (value) {
                if ((value ?? '').trim().length < 3) {
                  return 'Ad Soyad en az 3 karakter olmali.';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profileEmailController,
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty || !text.contains('@')) {
                  return 'Gecerli bir e-posta girin.';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profilePhoneController,
              decoration: const InputDecoration(
                labelText: 'Telefon (opsiyonel)',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) {
                  return null;
                }
                if (!RegExp(r'^\+?[0-9()\-\s]{10,20}$').hasMatch(text)) {
                  return 'Gecerli bir telefon numarasi girin.';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _profilePasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Sifre (opsiyonel)',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isNotEmpty && text.length < 6) {
                  return 'Sifre en az 6 karakter olmali.';
                }
                return null;
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
              Text('Kayit Tarihi: ${session.createdAt!.toLocal()}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuperUserYonetimi(UserSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: Form(
            key: _superUserFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yeni Super User Ekle',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                  validator: (value) {
                    if ((value ?? '').trim().length < 3) {
                      return 'Ad Soyad en az 3 karakter olmali.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-posta'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty || !text.contains('@')) {
                      return 'Gecerli bir e-posta girin.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
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
                    if (!RegExp(r'^\+?[0-9()\-\s]{10,20}$').hasMatch(text)) {
                      return 'Gecerli bir telefon numarasi girin.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Sifre'),
                  validator: (value) {
                    if ((value ?? '').trim().length < 6) {
                      return 'Sifre en az 6 karakter olmali.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isCreatingSuperUser ? null : _createSuperUser,
                    icon: _isCreatingSuperUser
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(
                      _isCreatingSuperUser
                          ? 'Olusturuluyor...'
                          : 'Super User Ekle',
                    ),
                  ),
                ),
              ],
            ),
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
                  const Expanded(
                    child: Text(
                      'Tum Super User Hesaplari',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadingSuperUsers
                        ? null
                        : () => _loadSuperUsers(force: true),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Yenile',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loadingSuperUsers)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_superUsers.isEmpty)
                const Text('Kayitli super user bulunamadi.')
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _superUsers.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 14),
                  itemBuilder: (context, index) {
                    final user = _superUsers[index];
                    final isSelf = user.id == session.id;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user.fullName),
                      subtitle: Text(
                        '${user.email}\nKod: ${user.id}${user.phoneNumber == null || user.phoneNumber!.isEmpty ? '' : '\nTel: ${user.phoneNumber}'}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _editSuperUser(user),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Duzenle',
                          ),
                          IconButton(
                            onPressed: isSelf ? null : () => _deleteSuperUser(user),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: isSelf
                                ? 'Kendi hesabinizi silemezsiniz'
                                : 'Sil',
                          ),
                        ],
                      ),
                    );
                  },
                ),
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
        return _buildSuperUserYonetimi(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.authService.session!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleByMenu(_selectedMenu)),
      ),
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
