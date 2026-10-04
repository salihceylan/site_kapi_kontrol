import 'package:flutter/material.dart';
import '../../data/turkey_cities_districts.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/buttons.dart';
import '../design/icon_orb.dart';
import '../design/motion_widgets.dart';
import '../design/tokens.dart';
import 'large_dialog_parts.dart';

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

  /// Gönderimde kullanılacak blok adı (boş bırakılırsa başlangıç adı).
  String _effectiveBlockName(_BlockDraft b) {
    final typed = b.nameController.text.trim();
    return typed.isEmpty ? b.name : typed;
  }

  String _blockNameKey(_BlockDraft b) => _effectiveBlockName(b).toLowerCase();

  void _addBlock() {
    // Blok silinip yeniden eklenince varsayılan ad mevcut adlarla çakışmasın (sunucu yinelenen
    // blok adını 400 ile reddeder): kullanılmayan ilk "<harf> Blok" adı seçilir.
    final taken = _blocks.map(_blockNameKey).toSet();
    var nextIndex = _blocks.length;
    String defaultName;
    do {
      final charCode = 65 + (nextIndex % 26);
      final letter = String.fromCharCode(charCode);
      final suffix = nextIndex >= 26 ? '${(nextIndex ~/ 26) + 1}' : '';
      defaultName = '$letter$suffix Blok';
      nextIndex++;
    } while (taken.contains(defaultName.toLowerCase()));

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
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    // Büyük yazıda sabit başlık küçülür: alt başlık kaydırılan formun başına taşınır ve onay düğmesi
    // sabit satır yerine formun SONUNA alınır (içerik için yer kalsın).
    final compactHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final submitButton = PrimaryActionButton(
      label: _isLoading ? 'Site Kuruluyor...' : 'Site Kurulumunu Tamamla',
      icon: Icons.check_circle_rounded,
      loading: _isLoading,
      onPressed: _isLoading ? null : _submit,
    );
    final cities = turkeyCitiesAndDistricts.keys.toList();
    final districts = _selectedCity != null
        ? (turkeyCitiesAndDistricts[_selectedCity] ?? <String>[])
        : <String>[];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık ve İkon (+ sağ üstte kapatma; başlık düğmenin altına girmesin diye sağdan pay)
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 32),
                  child: AppDialogHeader(
                    title: 'Site Kurulum Sihirbazı',
                    subtitle: compactHeader ? null : 'Site Sahibi (SITE_OWNER) Yapılandırması',
                    icon: Icons.apartment_rounded,
                  ),
                ),
                PositionedDirectional(
                  top: AppSpace.sm,
                  end: AppSpace.sm,
                  child: IconButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Kapat',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),

            // Form İçeriği
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (compactHeader) ...[
                        Text('Site Sahibi (SITE_OWNER) Yapılandırması', style: th.bodySmall),
                        const SizedBox(height: AppSpace.md),
                      ],
                      // Hata Mesajı
                      if (_errorMessage != null) ...[
                        InlineNotice(message: _errorMessage!),
                        const SizedBox(height: AppSpace.lg),
                      ],

                      // Bağlanacak Cihaz Bilgi Kartı
                      if (widget.deviceUid != null) ...[
                        _buildDevicePanel(context),
                        const SizedBox(height: AppSpace.lg),
                      ],

                      // Site Adı
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Site Adı *',
                          hintText: 'Örn: Gül Sitesi',
                          prefixIcon: Icon(Icons.business_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Site adı zorunludur.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.md),

                      // İl & İlçe Seçimi
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedCity,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              dropdownColor: p.surface,
                              menuMaxHeight: 320,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded),
                              decoration: const InputDecoration(
                                labelText: 'İl',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedDistrict,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              dropdownColor: p.surface,
                              menuMaxHeight: 320,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded),
                              decoration: const InputDecoration(
                                labelText: 'İlçe',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                      const SizedBox(height: AppSpace.md),

                      // Açık Adres
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Açık Adres (İsteğe Bağlı)',
                          hintText: 'Mahalle, Cadde, Sokak No...',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpace.xl),

                      // Dinamik Bloklar ve Daireler Başlığı
                      SectionHeader(
                        title: 'Bloklar ve Daireler',
                        icon: Icons.apartment_rounded,
                        trailing: TextButton.icon(
                          onPressed: _addBlock,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Blok Ekle'),
                        ),
                      ),
                      Text(
                        'Her bloğun adını ve daire sayısını belirleyin',
                        style: th.bodySmall,
                      ),
                      const SizedBox(height: AppSpace.md),

                      // Blok Kartları Listesi (ilk 8 satır girişte kademeli belirir)
                      for (var idx = 0; idx < _blocks.length; idx++) ...[
                        if (idx > 0) const SizedBox(height: AppSpace.md),
                        StaggeredEntry(index: idx, child: _buildBlockRow(context, idx)),
                      ],
                      const SizedBox(height: AppSpace.xl),

                      // Dinamik Kapılar Başlığı
                      SectionHeader(
                        title: 'Kapılar',
                        icon: Icons.meeting_room_rounded,
                        trailing: TextButton.icon(
                          onPressed: _addDoor,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Kapı Ekle'),
                        ),
                      ),
                      Text(
                        'Sitenin kapılarını ve isimlerini belirleyin',
                        style: th.bodySmall,
                      ),
                      const SizedBox(height: AppSpace.md),

                      // Kapı Kartları Listesi (ilk 8 satır girişte kademeli belirir)
                      for (var idx = 0; idx < _doors.length; idx++) ...[
                        if (idx > 0) const SizedBox(height: AppSpace.sm),
                        StaggeredEntry(index: idx, child: _buildDoorRow(context, idx)),
                      ],
                      if (compactHeader) ...[
                        const SizedBox(height: AppSpace.xl),
                        submitButton,
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Onay Butonu (sabit; büyük yazıda formun sonunda)
            if (!compactHeader) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.xl),
                child: submitButton,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Bağlanacak cihaz" paneli: mor tonlu (cihaz) zemin, cilalı ikon rozeti, cihaz kimliği ve atama
  /// durumu. Büyük yazıda (>= 1,75x) rozet gizlenir.
  Widget _buildDevicePanel(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return DialogPanel(
      tone: AppTone.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!hideRowOrbs(context)) ...[
                const IconOrb(
                  icon: Icons.developer_board_rounded,
                  tone: AppTone.violet,
                  size: 40,
                  shape: IconOrbShape.squircle,
                ),
                const SizedBox(width: AppSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bağlanacak Cihaz:',
                      style: th.bodySmall?.copyWith(
                        color: AppTone.violet.ink(p),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.deviceUid!,
                      style: th.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          // Sarabilen hap: tek satırlı StatusChip büyük yazıda "Kapı 1'e Atan…" diye keserdi.
          const DialogMetaPill(
            'Kapı 1\'e Atanacak',
            tone: AppTone.success,
            icon: Icons.link_rounded,
          ),
        ],
      ),
    );
  }

  /// Tek blok satırı (blok adı + daire sayısı + sil): büyük yazı / dar kartta alanlar alt alta dizilir.
  Widget _buildBlockRow(BuildContext context, int idx) {
    final p = context.palette;
    final b = _blocks[idx];
    return DialogPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Büyük yazı / dar kartta alanlar alt alta dizilir (okunur genişlik).
          final stacked =
              MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
              constraints.maxWidth < 300;
          // Blok Adı
          final nameField = TextFormField(
            controller: b.nameController,
            decoration: const InputDecoration(
              labelText: 'Blok Adı',
              isDense: true,
              border: UnderlineInputBorder(),
            ),
            validator: (_) {
              final key = _blockNameKey(b);
              final sameCount =
                  _blocks.where((o) => _blockNameKey(o) == key).length;
              return sameCount > 1 ? 'Blok adı benzersiz olmalı.' : null;
            },
          );
          // Daire Sayısı
          final countField = TextFormField(
            controller: b.countController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daire Sayısı',
              isDense: true,
              border: UnderlineInputBorder(),
            ),
          );
          // Sil Butonu
          final deleteButton = _blocks.length > 1
              ? IconButton(
                  onPressed: () => _removeBlock(idx),
                  icon: Icon(Icons.delete_outline_rounded, color: AppTone.danger.ink(p), size: 20),
                  tooltip: 'Bloğu Sil',
                )
              : null;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                nameField,
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Expanded(child: countField),
                    ?deleteButton,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: nameField),
              const SizedBox(width: AppSpace.md),
              Expanded(flex: 2, child: countField),
              ?deleteButton,
            ],
          );
        },
      ),
    );
  }

  /// Tek kapı satırı: [kapı ikon rozeti] [kapı adı] [sil]. Büyük yazıda (>= 1,75x) rozet gizlenir.
  Widget _buildDoorRow(BuildContext context, int idx) {
    final p = context.palette;
    final d = _doors[idx];
    return DialogPanel(
      child: Row(
        children: [
          if (!hideRowOrbs(context)) ...[
            const IconOrb(
              icon: Icons.meeting_room_rounded,
              size: 32,
              shape: IconOrbShape.squircle,
            ),
            const SizedBox(width: AppSpace.md),
          ],
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
              icon: Icon(Icons.delete_outline_rounded, color: AppTone.danger.ink(p), size: 20),
              tooltip: 'Kapıyı Sil',
            ),
        ],
      ),
    );
  }
}
