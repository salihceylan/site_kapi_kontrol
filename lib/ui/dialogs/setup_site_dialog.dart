import 'package:flutter/material.dart';
import '../../data/turkey_cities_districts.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../../styles/app_colors.dart';

class _BlockDraft {
  _BlockDraft({required this.name, required this.apartmentCount})
      : nameController = TextEditingController(text: name),
        countController = TextEditingController(text: apartmentCount.toString());

  String name;
  int apartmentCount;
  final TextEditingController nameController;
  final TextEditingController countController;

  void dispose() {
    nameController.dispose();
    countController.dispose();
  }
}

class _DoorDraft {
  _DoorDraft({required this.name})
      : nameController = TextEditingController(text: name);

  String name;
  final TextEditingController nameController;

  void dispose() {
    nameController.dispose();
  }
}

class SetupSiteDialog extends StatefulWidget {
  const SetupSiteDialog({
    super.key,
    required this.authService,
    this.deviceUid,
  });

  final AuthService authService;
  final String? deviceUid;

  static Future<bool?> show(
    BuildContext context, {
    required AuthService authService,
    String? deviceUid,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SetupSiteDialog(
        authService: authService,
        deviceUid: deviceUid,
      ),
    );
  }

  @override
  State<SetupSiteDialog> createState() => _SetupSiteDialogState();
}

class _SetupSiteDialogState extends State<SetupSiteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;

  String? _selectedCity;
  String? _selectedDistrict;

  final List<_BlockDraft> _blocks = [];
  final List<_DoorDraft> _doors = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addressController = TextEditingController();

    // Başlangıçta 1 blok ve 1 kapı ekle
    _blocks.add(_BlockDraft(name: 'A Blok', apartmentCount: 10));
    _doors.add(_DoorDraft(name: 'Ana Giriş Kapısı'));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    for (final b in _blocks) {
      b.dispose();
    }
    for (final d in _doors) {
      d.dispose();
    }
    super.dispose();
  }

  void _addBlock() {
    final nextIndex = _blocks.length;
    final charCode = 65 + (nextIndex % 26);
    final letter = String.fromCharCode(charCode);
    final suffix = nextIndex >= 26 ? '${(nextIndex ~/ 26) + 1}' : '';
    final defaultName = '$letter$suffix Blok';

    setState(() {
      _blocks.add(_BlockDraft(name: defaultName, apartmentCount: 10));
    });
  }

  void _removeBlock(int index) {
    if (_blocks.length <= 1) return;
    setState(() {
      final removed = _blocks.removeAt(index);
      removed.dispose();
    });
  }

  void _addDoor() {
    final nextIndex = _doors.length + 1;
    setState(() {
      _doors.add(_DoorDraft(name: 'Kapı $nextIndex'));
    });
  }

  void _removeDoor(int index) {
    if (_doors.length <= 1) return;
    setState(() {
      final removed = _doors.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final blockPayload = _blocks.map((b) {
      final bName = b.nameController.text.trim();
      final count = int.tryParse(b.countController.text.trim()) ?? 10;
      return {
        'name': bName.isEmpty ? b.name : bName,
        'apartmentCount': count < 1 ? 1 : count,
      };
    }).toList();

    final doorsPayload = _doors.asMap().entries.map((entry) {
      final idx = entry.key;
      final d = entry.value;
      final dName = d.nameController.text.trim();
      return {
        'name': dName.isEmpty ? 'Kapı ${idx + 1}' : dName,
        'doorIndex': idx + 1,
      };
    }).toList();

    try {
      await widget.authService.setupSite(
        name: _nameController.text.trim(),
        city: _selectedCity,
        district: _selectedDistrict,
        address: _addressController.text.trim(),
        blocks: blockPayload,
        doors: doorsPayload,
        doorCount: doorsPayload.length,
        deviceUid: widget.deviceUid,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Site kurulumu sırasında bir hata oluştu.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cities = turkeyCitiesAndDistricts.keys.toList();
    final districts = _selectedCity != null
        ? (turkeyCitiesAndDistricts[_selectedCity] ?? <String>[])
        : <String>[];

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık ve İkon
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Site Kurulum Sihirbazı',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? AppColors.textLight : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Site Sahibi (SITE_OWNER) Yapılandırması',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textMuted : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Kapat',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Form İçeriği
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Hata Mesajı
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Bağlanacak Cihaz Bilgi Kartı
                        if (widget.deviceUid != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.developer_board_rounded, color: Colors.purple, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Bağlanacak Cihaz:',
                                        style: TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        widget.deviceUid!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Kapı 1\'e Atanacak',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Site Adı
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Site Adı *',
                            hintText: 'Örn: Gül Sitesi',
                            prefixIcon: const Icon(Icons.business_rounded),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Site adı zorunludur.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // İl & İlçe Seçimi
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedCity,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'İl',
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedCity = val;
                                    _selectedDistrict = null;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedDistrict,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'İlçe',
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                items: districts.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: _selectedCity == null
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _selectedDistrict = val;
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Açık Adres
                        TextFormField(
                          controller: _addressController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Açık Adres (İsteğe Bağlı)',
                            hintText: 'Mahalle, Cadde, Sokak No...',
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Dinamik Bloklar ve Daireler Başlığı
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bloklar ve Daireler',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? AppColors.textLight : AppColors.textDark,
                                    ),
                                  ),
                                  Text(
                                    'Her bloğun adını ve daire sayısını belirleyin',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? AppColors.textMuted : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addBlock,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Blok Ekle'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Blok Kartları Listesi
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _blocks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (ctx, idx) {
                            final b = _blocks[idx];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Blok Adı
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: b.nameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Blok Adı',
                                        isDense: true,
                                        border: UnderlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Daire Sayısı
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: b.countController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Daire Sayısı',
                                        isDense: true,
                                        border: UnderlineInputBorder(),
                                      ),
                                    ),
                                  ),

                                  // Sil Butonu
                                  if (_blocks.length > 1)
                                    IconButton(
                                      onPressed: () => _removeBlock(idx),
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                      tooltip: 'Bloğu Sil',
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Dinamik Kapılar Başlığı
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kapılar',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? AppColors.textLight : AppColors.textDark,
                                    ),
                                  ),
                                  Text(
                                    'Sitenin kapılarını ve isimlerini belirleyin',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? AppColors.textMuted : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addDoor,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Kapı Ekle'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Kapı Kartları Listesi
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _doors.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final d = _doors[idx];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.meeting_room_outlined,
                                    size: 20,
                                    color: isDark ? AppColors.textMuted : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: d.nameController,
                                      decoration: InputDecoration(
                                        labelText: 'Kapı ${idx + 1} Adı',
                                        hintText: 'Örn: Ana Giriş, Blok Girişi, Otopark...',
                                        isDense: true,
                                        border: const UnderlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  if (_doors.length > 1)
                                    IconButton(
                                      onPressed: () => _removeDoor(idx),
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                      tooltip: 'Kapıyı Sil',
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Onay Butonu
              Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x352563EB),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _isLoading ? null : _submit,
                    child: Center(
                      child: _isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Site Kuruluyor...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Site Kurulumunu Tamamla',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
