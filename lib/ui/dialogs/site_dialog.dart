import 'package:flutter/material.dart';
import '../../data/turkey_cities_districts.dart';
import '../../models/managed_user_account.dart';
import '../../models/site_record.dart';
import '../../models/site_structure_record.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/tokens.dart';
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

/// Sitenin gerçek blok başına daire sayıları (sunucunun "değişiklik yok" kabul ettiği değerler):
/// bloklar sıra numarasına göre, her blokta o bloğa bağlı daire adedi. Daire listesi boşsa
/// sunucuda saklanan dizi kullanılır.
List<int> siteBlockApartmentCountsFromStructure(SiteStructureRecord structure) {
  final blocks = structure.blocks.toList()
    ..sort((a, b) {
      final bySort = a.sortOrder.compareTo(b.sortOrder);
      return bySort != 0 ? bySort : a.id.compareTo(b.id);
    });
  final derived = <int>[
    for (final block in blocks)
      structure.apartments.where((a) => a.blockId == block.id).length,
  ];
  if (derived.any((count) => count > 0)) return derived;
  return structure.site.blockApartmentCounts;
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

  // Liste kaydı blok daire sayılarını taşımıyorsa (eski sunucu / boş dizi) gerçek sayılar
  // yapı ucundan okunur; okunana dek "Güncelle" kapalıdır.
  bool _isLoadingStructureCounts = false;
  String? _structureCountsError;

  bool get _isEditing => widget.site != null;

  bool get _structureCountsPending =>
      _isLoadingStructureCounts || _structureCountsError != null;

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
    } else if (site!.blockApartmentCounts.isEmpty && site.isApproved) {
      // Onaylı sitede "blok başına 10 daire" uydurulup PATCH edilirse sunucu fazla daireleri
      // (ve bağlı sakin üyeliklerini) siler: gerçek sayılar okunmadan kayıt yapılamaz.
      _isLoadingStructureCounts = true;
      _loadStructureCounts();
    }
  }

  Future<void> _loadStructureCounts() async {
    final site = widget.site;
    if (site == null) return;
    final (structure, error) = await widget.authService.getSiteStructure(
      siteCode: site.id,
    );
    if (!mounted) return;
    final counts = structure == null
        ? const <int>[]
        : siteBlockApartmentCountsFromStructure(structure);
    setState(() {
      _isLoadingStructureCounts = false;
      if (counts.isEmpty) {
        _structureCountsError = error ?? 'Mevcut daire sayıları okunamadı.';
        return;
      }
      _structureCountsError = null;
      while (_blockApartmentControllers.length > counts.length) {
        _blockApartmentControllers.removeLast().dispose();
      }
      for (var i = 0; i < counts.length; i++) {
        if (i < _blockApartmentControllers.length) {
          _blockApartmentControllers[i].text = counts[i].toString();
        } else {
          _blockApartmentControllers.add(
            TextEditingController(text: counts[i].toString()),
          );
        }
      }
      _blockCountController.text = counts.length.toString();
    });
  }

  void _retryStructureCounts() {
    setState(() {
      _isLoadingStructureCounts = true;
      _structureCountsError = null;
    });
    _loadStructureCounts();
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
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return AppDialog(
      title: _isEditing ? 'Site Düzenle' : 'Yeni Site Ekle',
      icon: Icons.location_city_rounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _structureCountsPending ? null : _submit,
          child: Text(_isEditing ? 'Güncelle' : 'Kaydet'),
        ),
      ],
      child: Form(
        key: _formKey,
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
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '🏢 Blok Daireleri',
                        style: th.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                      if (!_structureCountsPending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTone.primary.tint(p),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            'Toplam: $_calculatedTotalApartments Daire',
                            style: th.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTone.primary.ink(p),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Her blok için daire sayısını girin:',
                    style: th.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingStructureCounts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mevcut daire sayıları okunuyor...',
                              style: th.bodySmall?.copyWith(color: p.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_structureCountsError != null)
                    InlineNotice(
                      message:
                          '$_structureCountsError Mevcut daire sayıları okunmadan kayıt yapılamaz (daireler yanlışlıkla silinmesin).',
                      onRetry: _retryStructureCounts,
                    )
                  else
                  for (var i = 0; i < _blockApartmentControllers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 72,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: BoxDecoration(
                              color: AppTone.primary.tint(p),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTone.primary.hue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '${blockLabelFromIndex(i)} Blok',
                              textAlign: TextAlign.center,
                              style: th.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTone.primary.ink(p),
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
                color: AppTone.primary.tint(p),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTone.primary.hue.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.manage_accounts_outlined,
                        color: AppTone.primary.ink(p),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Site Yöneticisi',
                          style: th.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingManagers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Yöneticiler yükleniyor...',
                              style: th.bodySmall?.copyWith(color: p.textSecondary),
                            ),
                          ),
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
                            color: p.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTone.primary.hue.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                color: AppTone.primary.ink(p),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedManager == null
                                      ? 'Yönetici Atanmadı'
                                      : '${_selectedManager!.fullName} (${_selectedManager!.email})',
                                  style: th.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: p.text,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_selectedManager != null)
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedManager = null;
                                      _selectedManagerUserCode = null;
                                    });
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                  icon: Icon(
                                    Icons.clear,
                                    size: 18,
                                    color: AppTone.danger.ink(p),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: _selectExistingManager,
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text('Yönetici Seç / Değiştir'),
                        ),
                      ],
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
