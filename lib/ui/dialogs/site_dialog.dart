import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/turkey_cities_districts.dart';
import '../../models/managed_user_account.dart';
import '../../models/management_type.dart';
import '../../models/site_record.dart';
import '../../models/site_structure_record.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/motion_widgets.dart';
import '../design/tokens.dart';
import '../helpers/ui_helpers.dart';
import '../pages/site_manager_picker_page.dart';
import '../widgets/management_type_selector.dart';
import 'large_dialog_parts.dart';

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
    this.managementType = ManagementType.apartmentSite,
  });

  final String name;
  final String address;
  final String city;
  final String district;
  final List<int> blockApartmentCounts;
  final int doorCount;
  final int? managerUserCode;
  final Map<String, dynamic>? managerUser;

  /// Seçilen yönetim türü (yalnız yeni sitede anlamlıdır; mevcut sitede tür değiştirilemez).
  final ManagementType managementType;
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

  // Yönetim türü: yeni sitede seçilebilir (Faz 1: yalnız Apartman ve Site); düzenlemede salt okunur.
  ManagementType _managementType = ManagementType.apartmentSite;

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
    _managementType = site?.managementType ?? ManagementType.apartmentSite;
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
    HapticFeedback.lightImpact();

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
        managementType: _managementType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

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
            const SizedBox(height: AppSpace.md),
            // Yönetim Türü (Site Adı ile İl arasında): düzenlemede salt okunur.
            ManagementTypeSelector(
              value: _managementType,
              onChanged: _isEditing
                  ? null
                  : (type) => setState(() => _managementType = type),
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Adres (opsiyonel)',
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    dropdownColor: p.surface,
                    menuMaxHeight: 320,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('district_$_selectedCity'),
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    dropdownColor: p.surface,
                    menuMaxHeight: 320,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
            const SizedBox(height: AppSpace.md),
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
                const SizedBox(width: AppSpace.sm),
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
            const SizedBox(height: AppSpace.lg),
            _buildBlocksPanel(context),
            const SizedBox(height: AppSpace.lg),
            _buildManagerPanel(context),
          ],
        ),
      ),
    );
  }

  /// Bloklara göre daire sayıları paneli: başlık + toplam hapı + (yükleniyor | hata | blok satırları).
  Widget _buildBlocksPanel(BuildContext context) {
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DialogSectionTitle(
            icon: Icons.apartment_rounded,
            title: 'Blok Daireleri',
            subtitle: 'Her blok için daire sayısını girin:',
          ),
          if (!_structureCountsPending) ...[
            const SizedBox(height: AppSpace.sm),
            DialogMetaPill(
              'Toplam: $_calculatedTotalApartments Daire',
              tone: AppTone.primary,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          if (_isLoadingStructureCounts)
            const DialogLoadingNote(text: 'Mevcut daire sayıları okunuyor...')
          else if (_structureCountsError != null)
            InlineNotice(
              message:
                  '$_structureCountsError Mevcut daire sayıları okunmadan kayıt yapılamaz (daireler yanlışlıkla silinmesin).',
              onRetry: _retryStructureCounts,
            )
          else
            for (var i = 0; i < _blockApartmentControllers.length; i++)
              _buildBlockRow(context, i),
        ],
      ),
    );
  }

  /// Tek blok satırı: blok etiketi hapı + daire sayısı alanı. Büyük yazıda etiket alanın üstüne alınır
  /// (yan yana iki parça okunur genişlik bırakmaz). İlk 8 satır girişte kademeli belirir.
  Widget _buildBlockRow(BuildContext context, int i) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final label = DialogMetaPill(
      '${blockLabelFromIndex(i)} Blok',
      tone: AppTone.primary,
      minWidth: 64,
    );
    final field = TextFormField(
      controller: _blockApartmentControllers[i],
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Daire Sayısı',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          vertical: AppSpace.md,
          horizontal: AppSpace.md,
        ),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        final val = int.tryParse((value ?? '').trim());
        return val == null || val < 1 ? 'En az 1 daire olmalı.' : null;
      },
    );
    return StaggeredEntry(
      index: i,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  // Alanın yüzen etiketi kutunun üstüne taşar: hap ile çakışmasın.
                  const SizedBox(height: AppSpace.md),
                  field,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpace.md - AppSpace.xs / 2,
                    ),
                    child: label,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: field),
                ],
              ),
      ),
    );
  }

  /// Site yöneticisi paneli: başlık (rol tonu: site yöneticisi = success) + seçili yönetici kutusu +
  /// ikincil "seç / değiştir" eylemi.
  Widget _buildManagerPanel(BuildContext context) {
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(
            icon: Icons.manage_accounts_rounded,
            title: 'Site Yöneticisi',
            tone: AppTone.success,
          ),
          const SizedBox(height: AppSpace.md),
          if (_isLoadingManagers)
            const DialogLoadingNote(text: 'Yöneticiler yükleniyor...')
          else ...[
            _buildManagerTile(context),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton.icon(
              onPressed: _selectExistingManager,
              style: dialogTonalButtonStyle(context),
              icon: const Icon(Icons.person_search, size: 16),
              label: const Text('Yönetici Seç / Değiştir'),
            ),
          ],
        ],
      ),
    );
  }

  /// Seçili yönetici kutusu: atanmadıysa nötr, atandıysa rol tonlu (success) + temizle düğmesi.
  Widget _buildManagerTile(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final manager = _selectedManager;
    final tone = manager == null ? AppTone.neutral : AppTone.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: manager == null ? p.border : tone.hue.withValues(alpha: 0.4),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.md),
          child: Row(
            children: [
              Icon(Icons.person_outline, color: tone.ink(p), size: 20),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Text(
                    manager == null
                        ? 'Yönetici Atanmadı'
                        : '${manager.fullName} (${manager.email})',
                    style: th.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (manager != null)
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
                )
              else
                const SizedBox(width: AppSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}
