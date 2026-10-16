import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import '../../data/turkey_cities_districts.dart';
import '../../models/management_type.dart';
import '../../models/site_application.dart';
import '../../models/user_role.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/buttons.dart';
import '../design/icon_orb.dart';
import '../design/motion_widgets.dart';
import '../design/tokens.dart';
import '../helpers/dialog_guard.dart';
import '../helpers/form_validation.dart';
import '../helpers/paged_loader.dart';
import '../helpers/retry_lock.dart';
import '../widgets/crm_parts.dart';
import '../widgets/management_type_selector.dart';
import '../widgets/site_application_parts.dart';
import 'large_dialog_parts.dart';

/// Site kurma formunun çalışma biçimi.
enum SetupSiteMode {
  /// ANLIK kurulum (`POST /membership/setup-site`): site yöneticisi "Site Ekle" ve süper kullanıcı.
  instant,

  /// Süper kullanıcı onayına gidecek BAŞVURU (`POST /membership/site-applications`): bireysel / daire
  /// kullanıcısı. JetPass cihazı şart DEĞİLDİR (isteğe bağlı).
  application,
}

/// Formun sonucu: site kuruldu (anlık) ya da başvuru gönderildi.
enum SetupSiteOutcome { created, applied }

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

/// Site kurma / site başvurusu formu (Platform: site başvurusu).
///
/// - [SetupSiteMode.instant]: eski "Site Kurulum Sihirbazı" (site yöneticisi ve süper kullanıcı; anlık).
/// - [SetupSiteMode.application]: bireysel / daire kullanıcısı için BAŞVURU formu. Cihaz isteğe bağlıdır
///   (cihazı yoksa "Cihaz sonra eklenebilir" notu); başarıda "Başvurunuz alındı..." iletisi aynı pencerede
///   gösterilir. [prefill] verilirse ("Yeniden başvur") form önceki değerlerle açılır.
///
/// [mode] verilmezse oturumun rolünden türetilir: bireysel / daire kullanıcısı = başvuru, diğerleri anlık.
///
/// Doğrulama hataları ilk geçersiz alana kaydırır ve özet gösterir; gönderim sürerken çift dokunuş ve geri
/// tuşu etkisizdir; hız sınırında (429) düğme geçici kilitlenir. Sunucu hata metni pencerenin içinde
/// gösterilir (alan adı jargonu `AuthApi` katmanında temizlenir).
class SetupSiteDialog extends StatefulWidget {
  const SetupSiteDialog({
    super.key,
    required this.authService,
    this.deviceUid,
    this.mode,
    this.prefill,
  });

  final AuthService authService;

  /// Önceden seçilmiş cihaz (cihaz sahiplenme akışından gelir).
  final String? deviceUid;

  /// null ise oturumun rolünden türetilir ([modeFor]).
  final SetupSiteMode? mode;

  /// "Yeniden başvur": önceki başvurunun değerleri.
  final SiteApplication? prefill;

  // Sunucu sınırları (`normalizeSetupSiteInput`): istemci aynı kuralı baştan uygular.
  static const int maxNameLength = 120;
  static const int maxLabelLength = 60;
  static const int maxAddressLength = 300;
  static const int maxNoteLength = 500;
  static const int maxBlocks = 100;
  static const int maxDoors = 100;
  static const int maxApartments = 5000;

  /// Oturumun rolüne göre varsayılan çalışma biçimi: bireysel / daire kullanıcısı başvurur; site
  /// yöneticisi ve süper kullanıcı anlık kurar (oturum yoksa eski davranış: anlık).
  static SetupSiteMode modeFor(AuthService authService) {
    final role = authService.session?.role;
    return role == UserRole.individual || role == UserRole.apartmentOwner
        ? SetupSiteMode.application
        : SetupSiteMode.instant;
  }

  static Future<SetupSiteOutcome?> show(
    BuildContext context, {
    required AuthService authService,
    String? deviceUid,
    SetupSiteMode? mode,
    SiteApplication? prefill,
  }) {
    return showDialog<SetupSiteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SetupSiteDialog(
        authService: authService,
        deviceUid: deviceUid,
        mode: mode,
        prefill: prefill,
      ),
    );
  }

  @override
  State<SetupSiteDialog> createState() => _SetupSiteDialogState();
}

class _SetupSiteDialogState extends State<SetupSiteDialog> {
  /// Cihaz seçicide "cihaz bağlama" seçeneğinin değeri.
  static const String _noDevice = '';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _noteController;
  final RetryLock _retry = RetryLock();

  late final SetupSiteMode _mode = widget.mode ?? SetupSiteDialog.modeFor(widget.authService);

  String? _selectedCity;
  String? _selectedDistrict;

  // Yönetim türü (Faz 1: yalnız Apartman ve Site seçilebilir; sunucuya management_type olarak gider).
  ManagementType _managementType = ManagementType.apartmentSite;

  final List<_BlockDraft> _blocks = [];
  final List<_DoorDraft> _doors = [];
  bool _submitting = false;
  String? _error;
  SetupSiteOutcome? _outcome;

  // Başvuru modunda isteğe bağlı cihaz seçimi.
  List<String> _deviceUids = <String>[];
  bool _devicesLoading = false;
  String _selectedDevice = _noDevice;
  int _deviceVersion = 0;

  bool get _isApplication => _mode == SetupSiteMode.application;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    _nameController = TextEditingController(text: prefill?.siteName ?? '');
    _addressController = TextEditingController(text: prefill?.address ?? '');
    _noteController = TextEditingController(text: prefill?.note ?? '');

    if (prefill != null) {
      final city = prefill.city;
      if (city != null && turkeyCitiesAndDistricts.containsKey(city)) {
        _selectedCity = city;
        final district = prefill.district;
        if (district != null && (turkeyCitiesAndDistricts[city] ?? const <String>[]).contains(district)) {
          _selectedDistrict = district;
        }
      }
      final type = ManagementType.fromApi(prefill.managementType);
      if (type.selectable) _managementType = type;
      for (final block in prefill.blocks.take(SetupSiteDialog.maxBlocks)) {
        _blocks.add(
          _BlockDraft(
            name: block.name.isEmpty ? 'Blok ${_blocks.length + 1}' : block.name,
            apartmentCount: block.apartmentCount < 1 ? 1 : block.apartmentCount,
          ),
        );
      }
      for (final door in prefill.doors.take(SetupSiteDialog.maxDoors)) {
        _doors.add(_DoorDraft(name: door.name.isEmpty ? 'Kapı ${_doors.length + 1}' : door.name));
      }
    }
    // Başlangıçta 1 blok ve 1 kapı ekle
    if (_blocks.isEmpty) _blocks.add(_BlockDraft(name: 'A Blok', apartmentCount: 10));
    if (_doors.isEmpty) _doors.add(_DoorDraft(name: 'Ana Giriş Kapısı'));

    if (_isApplication) {
      _selectedDevice = widget.deviceUid ?? _noDevice;
      if (widget.deviceUid != null) _deviceUids = <String>[widget.deviceUid!];
      unawaited(_loadDevices());
    }
  }

  @override
  void dispose() {
    _retry.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    for (final b in _blocks) {
      b.dispose();
    }
    for (final d in _doors) {
      d.dispose();
    }
    super.dispose();
  }

  /// Hesaba bağlı, henüz bir siteye atanmamış cihazları çeker (başvuruda isteğe bağlı seçim). Hata olursa
  /// seçim gizli kalır ve başvuru cihazsız yapılabilir ("Cihaz sonra eklenebilir").
  Future<void> _loadDevices() async {
    setState(() => _devicesLoading = true);
    List<String> uids = <String>[];
    try {
      final devices = await widget.authService.getMyClaimedDevices();
      uids = <String>[
        for (final d in devices)
          if (d['site_code'] == null && (d['device_uid']?.toString() ?? '').isNotEmpty)
            d['device_uid'].toString(),
      ];
    } catch (_) {
      // Cihaz listesi alınamadı: cihazsız başvuru yine mümkündür.
    }
    if (!mounted) return;
    setState(() {
      _devicesLoading = false;
      final explicit = widget.deviceUid;
      if (explicit != null && !uids.contains(explicit)) uids = <String>[explicit, ...uids];
      _deviceUids = uids;
      // "Yeniden başvur": önceki cihaz hâlâ uygunsa seçili gelir; değilse sessizce cihazsız.
      final preferred = widget.deviceUid ?? widget.prefill?.deviceUid;
      if (_selectedDevice == _noDevice && preferred != null && uids.contains(preferred)) {
        _selectedDevice = preferred;
      } else if (_selectedDevice != _noDevice && !uids.contains(_selectedDevice)) {
        _selectedDevice = _noDevice;
      }
      _deviceVersion++;
    });
  }

  /// Gönderimde kullanılacak blok adı (boş bırakılırsa başlangıç adı).
  String _effectiveBlockName(_BlockDraft b) {
    final typed = b.nameController.text.trim();
    return typed.isEmpty ? b.name : typed;
  }

  String _blockNameKey(_BlockDraft b) => _effectiveBlockName(b).toLowerCase();

  void _addBlock() {
    if (_blocks.length >= SetupSiteDialog.maxBlocks) return;
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
    if (_doors.length >= SetupSiteDialog.maxDoors) return;
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

  /// Daire sayısı alanı: 1..5000 tam sayı (sunucu aynı aralığı uygular; boş / geçersiz değer sessizce
  /// düzeltilmez).
  String? _validateApartmentCount(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 1 || parsed > SetupSiteDialog.maxApartments) {
      return 'Daire sayısı 1 ile ${SetupSiteDialog.maxApartments} arasında olmalı.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(_formKey)) {
      // Özet bildirimi (canlı bölge) + ilk geçersiz alana kaydırma / odak (validateForm).
      setState(() => _error = kFixFieldsMessage);
      return;
    }

    final blockPayload = _blocks.map((b) {
      final bName = b.nameController.text.trim();
      return {
        'name': bName.isEmpty ? b.name : bName,
        'apartmentCount': int.parse(b.countController.text.trim()),
      };
    }).toList();

    final total = blockPayload.fold<int>(0, (sum, b) => sum + (b['apartmentCount'] as int));
    if (total > SetupSiteDialog.maxApartments) {
      setState(() {
        _error = 'Toplam daire sayısı en fazla ${SetupSiteDialog.maxApartments} olabilir.';
      });
      return;
    }

    final doorsPayload = _doors.asMap().entries.map((entry) {
      final idx = entry.key;
      final d = entry.value;
      final dName = d.nameController.text.trim();
      return {
        'name': dName.isEmpty ? 'Kapı ${idx + 1}' : dName,
        'doorIndex': idx + 1,
      };
    }).toList();

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_isApplication) {
        await widget.authService.createSiteApplication(
          name: _nameController.text.trim(),
          city: _selectedCity,
          district: _selectedDistrict,
          address: _addressController.text.trim(),
          blocks: blockPayload,
          doors: doorsPayload,
          doorCount: doorsPayload.length,
          deviceUid: _selectedDevice == _noDevice ? null : _selectedDevice,
          managementType: _managementType.apiValue,
          note: _noteController.text,
        );
        if (!mounted) return;
        // Başarı iletisi aynı pencerede gösterilir; "Tamam" ile (ya da geri tuşuyla) kapanır.
        setState(() {
          _submitting = false;
          _outcome = SetupSiteOutcome.applied;
        });
        return;
      }
      await widget.authService.setupSite(
        name: _nameController.text.trim(),
        city: _selectedCity,
        district: _selectedDistrict,
        address: _addressController.text.trim(),
        blocks: blockPayload,
        doors: doorsPayload,
        doorCount: doorsPayload.length,
        deviceUid: widget.deviceUid,
        managementType: _managementType.apiValue,
      );

      if (!mounted) return;
      popIfCurrent(context, SetupSiteOutcome.created);
    } on ApiException catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      // Rol eskimiş olabilir (zaten yönetici / başvuru gerekli): oturum sunucudan yenilenir.
      if (e.code == 'ALREADY_SITE_MANAGER' || e.code == 'APPLICATION_REQUIRED') {
        unawaited(widget.authService.refreshSession(force: true));
      }
      setState(() {
        _error = limited ? RetryLock.messageFor(e) : crmMessageOf(e, _failureFallback);
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _failureFallback;
        _submitting = false;
      });
    }
  }

  String get _failureFallback => _isApplication
      ? 'Başvuru gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
      : 'Site kurulumu sırasında bir hata oluştu.';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    // Büyük yazıda sabit başlık küçülür: alt başlık kaydırılan formun başına taşınır ve onay düğmesi
    // sabit satır yerine formun SONUNA alınır (içerik için yer kalsın).
    final compactHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final submitted = _outcome == SetupSiteOutcome.applied;
    final subtitle = _isApplication
        ? 'Onaydan sonra site yöneticisi olursunuz'
        : 'Site Sahibi (SITE_OWNER) Yapılandırması';
    final submitButton = PrimaryActionButton(
      key: const ValueKey<String>('setup_site_submit'),
      label: _submitting
          ? (_isApplication ? 'Gönderiliyor...' : 'Site Kuruluyor...')
          : (_isApplication ? 'Başvuruyu Gönder' : 'Site Kurulumunu Tamamla'),
      icon: _isApplication ? Icons.send_rounded : Icons.check_circle_rounded,
      loading: _submitting,
      // Gönderim sürerken ve hız sınırı (429) sonrası kısa süre kilitli: art arda deneme yapılmasın.
      onPressed: (_submitting || _retry.locked) ? null : _submit,
    );
    final cities = turkeyCitiesAndDistricts.keys.toList();
    final districts = _selectedCity != null
        ? (turkeyCitiesAndDistricts[_selectedCity] ?? <String>[])
        : <String>[];

    return PopScope(
      // Gönderim sürerken geri tuşu pencereyi kapatmaz; başvuru gönderildiyse sonuçla kapanır.
      canPop: !_submitting && !submitted,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && submitted && !_submitting) popIfCurrent(context, _outcome);
      },
      child: Dialog(
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
                      title: _isApplication ? 'Site Başvurusu' : 'Site Kurulum Sihirbazı',
                      subtitle: compactHeader ? null : subtitle,
                      icon: _isApplication ? Icons.domain_add_rounded : Icons.apartment_rounded,
                    ),
                  ),
                  PositionedDirectional(
                    top: AppSpace.sm,
                    end: AppSpace.sm,
                    child: IconButton(
                      onPressed: _submitting ? null : () => popIfCurrent(context, _outcome),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Kapat',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                ],
              ),
              const Divider(height: 1),

              if (submitted)
                Flexible(child: _buildSuccess(context))
              else ...[
                // Form İçeriği
                Expanded(
                  child: Form(
                    key: _formKey,
                    // Düzeltilen alanın hatası kendiliğinden kalkar (yalnız gönderimde değil).
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (compactHeader) ...[
                            Text(subtitle, style: th.bodySmall),
                            const SizedBox(height: AppSpace.md),
                          ],
                          // Hata Mesajı (kaydırılmış formda görünür konuma gelir)
                          if (_error != null) CrmFormError(message: _error!),

                          if (_isApplication) ...[
                            const InlineNotice(
                              tone: AppTone.info,
                              message:
                                  'Başvurunuz süper kullanıcı tarafından incelenir. Onaylandığında siteniz '
                                  'kurulur ve siz site yöneticisi olursunuz.',
                            ),
                            const SizedBox(height: AppSpace.lg),
                            _buildDeviceSection(context),
                            const SizedBox(height: AppSpace.lg),
                          ] else if (widget.deviceUid != null) ...[
                            // Bağlanacak Cihaz Bilgi Kartı
                            _buildDevicePanel(context),
                            const SizedBox(height: AppSpace.lg),
                          ],

                          // Site Adı
                          TextFormField(
                            controller: _nameController,
                            enabled: !_submitting,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Site Adı *',
                              hintText: 'Örn: Gül Sitesi',
                              prefixIcon: Icon(Icons.business_rounded),
                            ),
                            validator: (val) {
                              final name = (val ?? '').trim();
                              if (name.isEmpty) return 'Site adı zorunludur.';
                              if (name.length > SetupSiteDialog.maxNameLength) {
                                return 'Site adı en çok ${SetupSiteDialog.maxNameLength} karakter olabilir.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpace.md),

                          // Yönetim Türü (Site Adı ile İl arasında)
                          ManagementTypeSelector(
                            value: _managementType,
                            onChanged: (type) => setState(() => _managementType = type),
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
                                  onChanged: _submitting
                                      ? null
                                      : (val) {
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
                                  onChanged: (_selectedCity == null || _submitting)
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
                            enabled: !_submitting,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Açık Adres (İsteğe Bağlı)',
                              hintText: 'Mahalle, Cadde, Sokak No...',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                            validator: (val) => (val ?? '').trim().length > SetupSiteDialog.maxAddressLength
                                ? 'Adres en çok ${SetupSiteDialog.maxAddressLength} karakter olabilir.'
                                : null,
                          ),
                          const SizedBox(height: AppSpace.xl),

                          // Dinamik Bloklar ve Daireler Başlığı
                          SectionHeader(
                            title: 'Bloklar ve Daireler',
                            icon: Icons.apartment_rounded,
                            trailing: TextButton.icon(
                              onPressed: (_submitting || _blocks.length >= SetupSiteDialog.maxBlocks)
                                  ? null
                                  : _addBlock,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Blok Ekle'),
                            ),
                          ),
                          Text(
                            _blocks.length >= SetupSiteDialog.maxBlocks
                                ? 'En fazla ${SetupSiteDialog.maxBlocks} blok eklenebilir.'
                                : 'Her bloğun adını ve daire sayısını belirleyin',
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
                              onPressed: (_submitting || _doors.length >= SetupSiteDialog.maxDoors)
                                  ? null
                                  : _addDoor,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Kapı Ekle'),
                            ),
                          ),
                          Text(
                            _doors.length >= SetupSiteDialog.maxDoors
                                ? 'En fazla ${SetupSiteDialog.maxDoors} kapı eklenebilir.'
                                : 'Sitenin kapılarını ve isimlerini belirleyin',
                            style: th.bodySmall,
                          ),
                          const SizedBox(height: AppSpace.md),

                          // Kapı Kartları Listesi (ilk 8 satır girişte kademeli belirir)
                          for (var idx = 0; idx < _doors.length; idx++) ...[
                            if (idx > 0) const SizedBox(height: AppSpace.sm),
                            StaggeredEntry(index: idx, child: _buildDoorRow(context, idx)),
                          ],

                          if (_isApplication) ...[
                            const SizedBox(height: AppSpace.xl),
                            // Süper kullanıcıya iletilecek isteğe bağlı not.
                            TextFormField(
                              key: const ValueKey<String>('site_application_note'),
                              controller: _noteController,
                              enabled: !_submitting,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: SetupSiteDialog.maxNoteLength,
                              // Sınırı aşan giriş (yapıştırma) sessizce kırpılmaz: sayaç ve hata gösterilir.
                              maxLengthEnforcement: MaxLengthEnforcement.none,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Not (İsteğe Bağlı)',
                                hintText: 'Süper kullanıcıya iletmek istediğiniz bilgi',
                                alignLabelWithHint: true,
                              ),
                              validator: (val) => (val ?? '').trim().length > SetupSiteDialog.maxNoteLength
                                  ? 'Not en çok ${SetupSiteDialog.maxNoteLength} karakter olabilir.'
                                  : null,
                            ),
                            const SizedBox(height: AppSpace.lg),
                            // Ödeme altyapısı hazır değil: pasif satır.
                            const SiteSubscriptionComingSoonRow(),
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
            ],
          ),
        ),
      ),
    );
  }

  /// Başvuru gönderildi iletisi (aynı pencerede). Metinler sarar; "Tamam" sonuçla kapatır.
  Widget _buildSuccess(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hideRowOrbs(context)) ...[
            const Center(
              child: IconOrb(
                icon: Icons.check_rounded,
                tone: AppTone.success,
                size: 56,
                glow: true,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
          ],
          Semantics(
            header: true,
            liveRegion: true,
            child: Text('Başvurunuz alındı.', style: th.titleLarge),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Süper kullanıcı onayladığında site yöneticisi olacaksınız.',
            key: const ValueKey<String>('setup_site_success_message'),
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Başvurunuzun durumunu ana ekrandan izleyebilir, onaylanmadan önce iptal edebilirsiniz.',
            style: th.bodySmall,
          ),
          const SizedBox(height: AppSpace.xl),
          PrimaryActionButton(
            key: const ValueKey<String>('setup_site_done'),
            label: 'Tamam',
            icon: Icons.check_rounded,
            onPressed: () => popIfCurrent(context, _outcome),
          ),
        ],
      ),
    );
  }

  /// Başvuruda isteğe bağlı cihaz bölümü: cihaz yoksa "Cihaz sonra eklenebilir" notu, varsa seçici.
  Widget _buildDeviceSection(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final Widget body;
    if (_devicesLoading && _deviceUids.isEmpty) {
      body = const DialogLoadingNote(text: 'Cihazlarınız yükleniyor...');
    } else if (_deviceUids.isEmpty) {
      body = Text(
        'Hesabınıza bağlı cihaz yok. Cihaz sonra eklenebilir; cihazınız yoksa da başvuru yapabilirsiniz.',
        style: th.bodyMedium,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey<String>('site_application_device_$_deviceVersion'),
            initialValue: _selectedDevice,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppRadius.md),
            dropdownColor: context.palette.surface,
            menuMaxHeight: 320,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            decoration: const InputDecoration(
              labelText: 'Bağlanacak cihaz (isteğe bağlı)',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: _noDevice,
                child: Text('Cihaz bağlama', overflow: TextOverflow.ellipsis),
              ),
              for (final uid in _deviceUids)
                DropdownMenuItem<String>(
                  value: uid,
                  child: Text(uid, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _selectedDevice = value ?? _noDevice),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            _selectedDevice == _noDevice
                ? 'Cihaz sonra eklenebilir.'
                : 'Onaylanırsa bu cihaz 1. kapıya bağlanır (cihaz hâlâ hesabınızdaysa).',
            style: th.bodySmall,
          ),
        ],
      );
    }
    return DialogPanel(
      tone: AppTone.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(
            icon: Icons.developer_board_rounded,
            title: 'Cihaz (isteğe bağlı)',
            tone: AppTone.violet,
          ),
          const SizedBox(height: AppSpace.md),
          body,
        ],
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
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Blok Adı',
              isDense: true,
              border: UnderlineInputBorder(),
            ),
            validator: (_) {
              final typed = b.nameController.text.trim();
              if (typed.length > SetupSiteDialog.maxLabelLength) {
                return 'Blok adı en çok ${SetupSiteDialog.maxLabelLength} karakter olabilir.';
              }
              final key = _blockNameKey(b);
              final sameCount =
                  _blocks.where((o) => _blockNameKey(o) == key).length;
              return sameCount > 1 ? 'Blok adı benzersiz olmalı.' : null;
            },
          );
          // Daire Sayısı
          final countField = TextFormField(
            controller: b.countController,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daire Sayısı',
              isDense: true,
              border: UnderlineInputBorder(),
            ),
            validator: _validateApartmentCount,
          );
          // Sil Butonu
          final deleteButton = _blocks.length > 1
              ? IconButton(
                  onPressed: _submitting ? null : () => _removeBlock(idx),
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
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: 'Kapı ${idx + 1} Adı',
                hintText: 'Örn: Ana Giriş, Blok Girişi, Otopark...',
                isDense: true,
                border: const UnderlineInputBorder(),
              ),
              validator: (val) => (val ?? '').trim().length > SetupSiteDialog.maxLabelLength
                  ? 'Kapı adı en çok ${SetupSiteDialog.maxLabelLength} karakter olabilir.'
                  : null,
            ),
          ),
          if (_doors.length > 1)
            IconButton(
              onPressed: _submitting ? null : () => _removeDoor(idx),
              icon: Icon(Icons.delete_outline_rounded, color: AppTone.danger.ink(p), size: 20),
              tooltip: 'Kapıyı Sil',
            ),
        ],
      ),
    );
  }
}
