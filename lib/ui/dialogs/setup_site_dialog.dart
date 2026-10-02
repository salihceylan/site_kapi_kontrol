import 'package:flutter/material.dart';
import '../../data/turkey_cities_districts.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/buttons.dart';
import '../design/tokens.dart';

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                        const SizedBox(height: 12),
                      ],
                      // Hata Mesajı
                      if (_errorMessage != null) ...[
                        InlineNotice(message: _errorMessage!),
                        const SizedBox(height: 16),
                      ],

                      // Bağlanacak Cihaz Bilgi Kartı
                      if (widget.deviceUid != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTone.violet.tint(p),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTone.violet.hue.withValues(alpha: 0.4)),
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.developer_board_rounded, color: AppTone.violet.ink(p), size: 20),
                                  const SizedBox(width: 10),
                                  Flexible(
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
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTone.success.tint(p),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Kapı 1\'e Atanacak',
                                  style: th.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppTone.success.ink(p),
                                  ),
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
                      const SizedBox(height: 14),

                      // İl & İlçe Seçimi
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedCity,
                              isExpanded: true,
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedDistrict,
                              isExpanded: true,
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
                      const SizedBox(height: 14),

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
                      const SizedBox(height: 20),

                      // Dinamik Bloklar ve Daireler Başlığı
                      SectionHeader(
                        title: 'Bloklar ve Daireler',
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
                              color: p.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: p.border),
                            ),
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
                                      const SizedBox(height: 8),
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
                                    const SizedBox(width: 14),
                                    Expanded(flex: 2, child: countField),
                                    ?deleteButton,
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Dinamik Kapılar Başlığı
                      SectionHeader(
                        title: 'Kapılar',
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
                              color: p.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: p.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.meeting_room_outlined,
                                  size: 20,
                                  color: p.textSecondary,
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
                                    icon: Icon(Icons.delete_outline_rounded, color: AppTone.danger.ink(p), size: 20),
                                    tooltip: 'Kapıyı Sil',
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (compactHeader) ...[
                        const SizedBox(height: 20),
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
}
