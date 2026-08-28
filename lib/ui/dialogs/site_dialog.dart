import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/pages/site_manager_picker_page.dart';

class SiteFormResult {
  const SiteFormResult({
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    required this.blockApartmentCounts,
    required this.doorCount,
    required this.managerUserCode,
    required this.managerUser,
  });

  final String name;
  final String address;
  final String city;
  final String district;
  final List<int> blockApartmentCounts;
  final int doorCount;
  final int? managerUserCode;
  final Map<String, dynamic>? managerUser;
}

class SiteDialog extends StatefulWidget {
  const SiteDialog({
    super.key,
    required this.authService,
    this.site,
  });

  final AuthService authService;
  final SiteRecord? site;

  static Future<SiteFormResult?> show(
    BuildContext context, {
    required AuthService authService,
    SiteRecord? site,
  }) {
    return showDialog<SiteFormResult>(
      context: context,
      builder: (_) => SiteDialog(
        authService: authService,
        site: site,
      ),
    );
  }

  @override
  State<SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<SiteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _districtController;
  late final TextEditingController _blockCountController;
  late final TextEditingController _apartmentCountController;
  late final TextEditingController _doorCountController;
  late final TextEditingController _managerFullNameController;
  late final TextEditingController _managerEmailController;
  late final TextEditingController _managerPhoneController;
  late final TextEditingController _managerPasswordController;

  final List<TextEditingController> _blockApartmentControllers = [];
  bool _customBlockApartments = false;
  int? _selectedManagerUserCode;
  ManagedUserAccount? _selectedManager;
  bool _createNewManager = false;
  List<ManagedUserAccount> _siteManagers = [];
  bool _isLoadingManagers = false;

  bool get _isEditing => widget.site != null;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _nameController = TextEditingController(text: site?.name ?? '');
    _addressController = TextEditingController(text: site?.address ?? '');
    _cityController = TextEditingController(text: site?.city ?? '');
    _districtController = TextEditingController(text: site?.district ?? '');
    _blockCountController = TextEditingController(
      text: (site?.blockCount ?? 1).toString(),
    );
    _apartmentCountController = TextEditingController(
      text: (site?.apartmentCount ?? 1).toString(),
    );
    _doorCountController = TextEditingController(
      text: (site?.doorCount ?? 1).toString(),
    );
    _managerFullNameController = TextEditingController();
    _managerEmailController = TextEditingController();
    _managerPhoneController = TextEditingController();
    _managerPasswordController = TextEditingController();

    _selectedManagerUserCode = site?.managerUserCode;
    _syncBlockControllers();
    if (!_isEditing) {
      _loadSiteManagers();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _blockCountController.dispose();
    _apartmentCountController.dispose();
    _doorCountController.dispose();
    _managerFullNameController.dispose();
    _managerEmailController.dispose();
    _managerPhoneController.dispose();
    _managerPasswordController.dispose();
    for (final controller in _blockApartmentControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSiteManagers() async {
    setState(() => _isLoadingManagers = true);
    try {
      final pageData = await widget.authService.listManagedUsers(
        role: UserRole.siteManager,
        page: 1,
        pageSize: 100,
      );
      if (!mounted) return;
      setState(() {
        _isLoadingManagers = false;
        _siteManagers = pageData.users;
        if (_selectedManagerUserCode != null) {
          _selectedManager = _siteManagers
              .where((u) => u.id == _selectedManagerUserCode)
              .firstOrNull;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingManagers = false);
    }
  }

  void _syncBlockControllers() {
    final blockCount = int.tryParse(_blockCountController.text.trim()) ?? 1;
    final defaultAptCount =
        int.tryParse(_apartmentCountController.text.trim()) ?? 1;

    while (_blockApartmentControllers.length < blockCount) {
      _blockApartmentControllers.add(
        TextEditingController(text: defaultAptCount.toString()),
      );
    }
    while (_blockApartmentControllers.length > blockCount) {
      _blockApartmentControllers.removeLast().dispose();
    }
  }

  Future<void> _selectExistingManager() async {
    final result = await Navigator.of(context).push<SiteManagerPickerResult>(
      MaterialPageRoute(
        builder: (_) => SiteManagerPickerPage(
          authService: widget.authService,
          selectedUserCode: _selectedManagerUserCode,
        ),
      ),
    );

    if (!mounted || result == null) return;
    setState(() {
      _selectedManager = result.manager;
      _selectedManagerUserCode = result.manager?.id;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final blockCount = int.parse(_blockCountController.text.trim());
    final defaultApt = int.parse(_apartmentCountController.text.trim());
    final doorCount = int.parse(_doorCountController.text.trim());

    List<int> blockApartmentCounts;
    if (_customBlockApartments) {
      blockApartmentCounts = _blockApartmentControllers
          .map((c) => int.tryParse(c.text.trim()) ?? defaultApt)
          .toList();
    } else {
      blockApartmentCounts = List.filled(blockCount, defaultApt);
    }

    Map<String, dynamic>? managerUserData;
    if (!_isEditing && _createNewManager) {
      managerUserData = {
        'fullName': _managerFullNameController.text.trim(),
        'email': _managerEmailController.text.trim().toLowerCase(),
        'phoneNumber': _managerPhoneController.text.trim().isEmpty
            ? null
            : _managerPhoneController.text.trim(),
        'password': _managerPasswordController.text.trim(),
      };
    }

    Navigator.of(context).pop(
      SiteFormResult(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
        blockApartmentCounts: blockApartmentCounts,
        doorCount: doorCount,
        managerUserCode: _createNewManager ? null : _selectedManagerUserCode,
        managerUser: managerUserData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(_isEditing ? 'Site Düzenle' : 'Yeni Site Ekle'),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Site Adı'),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'Site adı en az 2 karakter olmalı.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Adres (opsiyonel)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(
                          labelText: 'İl (opsiyonel)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _districtController,
                        decoration: const InputDecoration(
                          labelText: 'İlçe (opsiyonel)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _blockCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Blok Sayısı',
                        ),
                        onChanged: (_) => setState(_syncBlockControllers),
                        validator: (value) {
                          final val = int.tryParse((value ?? '').trim());
                          return val == null || val < 1
                              ? 'En az 1 blok olmalı.'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _apartmentCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Daire Sayısı / Blok',
                        ),
                        onChanged: (_) => setState(_syncBlockControllers),
                        validator: (value) {
                          final val = int.tryParse((value ?? '').trim());
                          return val == null || val < 1
                              ? 'En az 1 daire olmalı.'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _doorCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Site Kapı Sayısı',
                  ),
                  validator: (value) {
                    final val = int.tryParse((value ?? '').trim());
                    return val == null || val < 1
                        ? 'En az 1 kapı olmalı.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _customBlockApartments,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bloklara Göre Farklı Daire Sayısı'),
                  onChanged: (val) => setState(() => _customBlockApartments = val),
                ),
                if (_customBlockApartments) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < _blockApartmentControllers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextFormField(
                        controller: _blockApartmentControllers[i],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '${blockLabelFromIndex(i)} Daire Sayısı',
                        ),
                        validator: (value) {
                          final val = int.tryParse((value ?? '').trim());
                          return val == null || val < 1
                              ? 'Geçersiz daire sayısı.'
                              : null;
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFB8D7F7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.manage_accounts_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Site Yöneticisi',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!_isEditing) ...[
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Listeden Seç'),
                              icon: Icon(Icons.people_outline, size: 16),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Yeni Oluştur'),
                              icon: Icon(Icons.person_add_outlined, size: 16),
                            ),
                          ],
                          selected: {_createNewManager},
                          onSelectionChanged: (set) =>
                              setState(() => _createNewManager = set.first),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!_createNewManager) ...[
                        if (_isLoadingManagers)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Yöneticiler yükleniyor...'),
                              ],
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFB8D7F7),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _selectedManager?.fullName ??
                                                widget.site?.managerName ??
                                                'Yönetici Seçilmedi',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectedManager?.email ??
                                                'Siteye bir yönetici atayabilirsiniz.',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _selectExistingManager,
                                icon: const Icon(Icons.search),
                                label: Text(
                                  _selectedManagerUserCode == null
                                      ? 'Site Yöneticisi Seç'
                                      : 'Site Yöneticisini Değiştir',
                                ),
                              ),
                              if (_selectedManagerUserCode != null)
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    _selectedManagerUserCode = null;
                                    _selectedManager = null;
                                  }),
                                  icon: const Icon(
                                    Icons.link_off_outlined,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Yönetici atamasını kaldır',
                                  ),
                                ),
                            ],
                          ),
                      ] else ...[
                        TextFormField(
                          controller: _managerFullNameController,
                          decoration: const InputDecoration(
                            labelText: 'Site Yöneticisi Ad Soyad',
                          ),
                          validator: (value) => (value ?? '').trim().length < 3
                              ? 'Ad Soyad en az 3 karakter olmalı.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _managerEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Site Yöneticisi E-posta',
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            return text.isEmpty || !text.contains('@')
                                ? 'Geçerli bir e-posta girin.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _managerPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Site Yöneticisi Telefon (opsiyonel)',
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            return RegExp(r'^\+?[0-9()\-\s]{10,20}$')
                                    .hasMatch(text)
                                ? null
                                : 'Geçerli bir telefon numarası girin.';
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _managerPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Site Yöneticisi Şifre',
                          ),
                          validator: (value) => (value ?? '').trim().length < 6
                              ? 'Şifre en az 6 karakter olmalı.'
                              : null,
                        ),
                      ],
                    ],
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
          child: const Text('İptal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}
