import 'package:flutter/material.dart';
import '../../data/turkey_cities_districts.dart';
import '../../models/managed_user_account.dart';
import '../../models/site_record.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../styles/app_colors.dart';
import '../helpers/ui_helpers.dart';
import '../pages/site_manager_picker_page.dart';

class SiteFormResult {
  const SiteFormResult({
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    required this.blockApartmentCounts,
    required this.doorCount,
    required this.managerUserCode,
    this.managerUser,
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
  late final TextEditingController _blockCountController;
  late final TextEditingController _doorCountController;

  String? _selectedCity;
  String? _selectedDistrict;

  final List<TextEditingController> _blockApartmentControllers = [];
  int? _selectedManagerUserCode;
  ManagedUserAccount? _selectedManager;
  List<ManagedUserAccount> _siteManagers = [];
  bool _isLoadingManagers = false;

  bool get _isEditing => widget.site != null;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _nameController = TextEditingController(text: site?.name ?? '');
    _addressController = TextEditingController(text: site?.address ?? '');
    final initialCity = (site?.city ?? '').trim();
    final initialDistrict = (site?.district ?? '').trim();
    _selectedCity = initialCity.isNotEmpty ? initialCity : null;
    _selectedDistrict = initialDistrict.isNotEmpty ? initialDistrict : null;

    final initialBlockCount = site?.blockCount ?? 1;
    _blockCountController = TextEditingController(
      text: initialBlockCount.toString(),
    );
    _doorCountController = TextEditingController(
      text: (site?.doorCount ?? 1).toString(),
    );

    _selectedManagerUserCode = site?.managerUserCode;

    // Var olan daire sayılarını yükle veya varsayılan 10 ata
    if (site != null && site.blockApartmentCounts.isNotEmpty) {
      for (final count in site.blockApartmentCounts) {
        _blockApartmentControllers.add(
          TextEditingController(text: count.toString()),
        );
      }
    } else {
      for (var i = 0; i < initialBlockCount; i++) {
        _blockApartmentControllers.add(
          TextEditingController(text: '10'),
        );
      }
    }

    _syncBlockControllers();
    if (!_isEditing) {
      _loadSiteManagers();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _blockCountController.dispose();
    _doorCountController.dispose();
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
    final safeCount = blockCount.clamp(1, 50);

    while (_blockApartmentControllers.length < safeCount) {
      _blockApartmentControllers.add(
        TextEditingController(text: '10'),
      );
    }
    while (_blockApartmentControllers.length > safeCount) {
      _blockApartmentControllers.removeLast().dispose();
    }
  }

  int get _calculatedTotalApartments {
    int total = 0;
    for (final c in _blockApartmentControllers) {
      total += int.tryParse(c.text.trim()) ?? 0;
    }
    return total;
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

    final doorCount = int.parse(_doorCountController.text.trim());
    final blockApartmentCounts = _blockApartmentControllers
        .map((c) => int.tryParse(c.text.trim()) ?? 1)
        .toList();

    Navigator.of(context).pop(
      SiteFormResult(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        city: _selectedCity ?? '',
        district: _selectedDistrict ?? '',
        blockApartmentCounts: blockApartmentCounts,
        doorCount: doorCount,
        managerUserCode: _selectedManagerUserCode,
        managerUser: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(_isEditing ? 'Site Düzenle' : 'Yeni Site Ekle'),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedCity != null &&
                                turkeyCityNames.contains(_selectedCity)
                            ? _selectedCity
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'İl (opsiyonel)',
                        ),
                        items: [
                          for (final city in turkeyCityNames)
                            DropdownMenuItem<String>(
                              value: city,
                              child: Text(
                                city,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedCity = value;
                            _selectedDistrict = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('district_$_selectedCity'),
                        isExpanded: true,
                        initialValue: (_selectedCity != null &&
                                _selectedDistrict != null &&
                                getDistrictsForCity(_selectedCity)
                                    .contains(_selectedDistrict))
                            ? _selectedDistrict
                            : null,
                        decoration: InputDecoration(
                          labelText: 'İlçe (opsiyonel)',
                          hintText: _selectedCity == null
                              ? 'Önce İl'
                              : 'İlçe Seçin',
                        ),
                        items: [
                          if (_selectedCity != null)
                            for (final district in getDistrictsForCity(_selectedCity))
                              DropdownMenuItem<String>(
                                value: district,
                                child: Text(
                                  district,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                        ],
                        onChanged: _selectedCity == null
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedDistrict = value;
                                });
                              },
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
                          prefixIcon: Icon(Icons.apartment_rounded, size: 18),
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _doorCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Kapı Sayısı',
                          prefixIcon: Icon(Icons.sensor_door_outlined, size: 18),
                        ),
                        validator: (value) {
                          final val = int.tryParse((value ?? '').trim());
                          return val == null || val < 1
                              ? 'En az 1 kapı olmalı.'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // BLOKLARA GÖRE DAİRE SAYILARI LİSTESİ
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '🏢 Blok Daireleri',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Toplam: $_calculatedTotalApartments Daire',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Her blok için daire sayısını girin:',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 10),
                      for (var i = 0; i < _blockApartmentControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 72,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '${blockLabelFromIndex(i)} Blok',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _blockApartmentControllers[i],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Daire Sayısı',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                  ),
                                  onChanged: (_) => setState(() {}),
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
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(14),
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
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Site Yöneticisi',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_isLoadingManagers)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Yöneticiler yükleniyor...', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFB8D7F7),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person_outline,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedManager == null
                                          ? 'Yönetici Atanmadı'
                                          : '${_selectedManager!.fullName} (${_selectedManager!.email})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_selectedManager != null)
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedManager = null;
                                          _selectedManagerUserCode = null;
                                        });
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.clear,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _selectExistingManager,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              icon: const Icon(Icons.person_search, size: 16),
                              label: const Text('Yönetici Seç / Değiştir', style: TextStyle(fontSize: 12.5)),
                            ),
                          ],
                        ),
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
        ElevatedButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Güncelle' : 'Kaydet'),
        ),
      ],
    );
  }
}
