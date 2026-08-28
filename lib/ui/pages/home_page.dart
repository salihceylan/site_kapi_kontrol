import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/quick_actions_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/role_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';
import 'package:site_kapi_kontrol/ui/pages/wifi_provision_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/hands_free_settings_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_control_modal.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

double _dialogWidthForScreen(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return math.min(420, math.max(280, screenWidth - 48));
}

String _blockLabelFromIndex(int index) {
  var current = index + 1;
  var label = '';
  while (current > 0) {
    current -= 1;
    label = '${String.fromCharCode(65 + (current % 26))}$label';
    current = current ~/ 26;
  }
  return '$label Blok';
}

List<int> _distributeApartmentCounts({
  required int blockCount,
  required int apartmentCount,
}) {
  final totalBlocks = blockCount > 0 ? blockCount : 1;
  var remainingApartments = apartmentCount < 0 ? 0 : apartmentCount;
  final counts = <int>[];

  for (var index = 0; index < totalBlocks; index += 1) {
    final blocksLeft = totalBlocks - index;
    final targetForBlock = blocksLeft <= 0
        ? 0
        : (remainingApartments / blocksLeft).ceil();
    counts.add(targetForBlock);
    remainingApartments -= targetForBlock;
  }

  return counts;
}

List<int> _siteBlockApartmentCounts({
  SiteRecord? site,
  SiteStructureRecord? structure,
}) {
  if (site == null && structure == null) {
    return const <int>[1];
  }
  if (structure != null && structure.blocks.isNotEmpty) {
    return structure.blocks.map((block) {
      return structure.apartments
          .where((apartment) => apartment.blockId == block.id)
          .length;
    }).toList();
  }

  return _distributeApartmentCounts(
    blockCount: site?.blockCount ?? 1,
    apartmentCount: site?.apartmentCount ?? 0,
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.authService,
    this.voiceDoorService,
    this.quickActionsService,
  });

  final AuthService authService;
  final VoiceDoorService? voiceDoorService;
  final QuickActionsService? quickActionsService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _pageSize = 10;

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
  SitePage? _sitesPage;
  SiteRecord? _selectedSite;
  SiteStructureRecord? _selectedSiteStructure;
  bool _isLoadingSites = false;
  bool _isLoadingSiteStructure = false;
  final Set<int> _busyDeleteSites = <int>{};
  final Set<int> _busyApartments = <int>{};
  final Set<int> _busyDoors = <int>{};
  SubscriptionRequestPage? _subscriptionRequestsPage;
  bool _isLoadingSubscriptionRequests = false;
  final Set<int> _busySubscriptionRequests = <int>{};
  SitePage? _pendingSiteApprovalsPage;
  bool _isLoadingPendingSiteApprovals = false;
  final Set<int> _busySiteApprovals = <int>{};
  SitePage? _doorControlSitesPage;
  SiteRecord? _doorControlSite;
  SiteStructureRecord? _doorControlStructure;
  DoorRecord? _doorControlDoor;
  DoorRuntimeStatus? _doorRuntimeStatus;
  Timer? _doorStatusTimer;
  bool _isLoadingDoorStatus = false;
  bool _isOpeningDoor = false;
  String? _doorStatusError;
  bool _isLoadingDoorControlSites = false;
  bool _isLoadingDoorControlStructure = false;
  DevicePage? _companyDevicesPage;
  bool _isLoadingCompanyDevices = false;
  bool _isBroadcastingOtaCheck = false;

  @override
  void initState() {
    super.initState();
    final session = widget.authService.session;
    if (session != null) {
      _profileFullNameController.text = session.fullName;
      _profileEmailController.text = session.email;
      _profilePhoneController.text = session.phoneNumber ?? '';
    }

    _loadDoorControlSites();
  }

  @override
  void dispose() {
    _profileFullNameController.dispose();
    _profileEmailController.dispose();
    _profilePhoneController.dispose();
    _profilePasswordController.dispose();
    _stopDoorStatusTimer();
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
        return null;
      case SirketMenuItem.abonelikTalepleri:
      case SirketMenuItem.siteOnayTalepleri:
      case SirketMenuItem.siteler:
      case SirketMenuItem.cihazEkle:
      case SirketMenuItem.kayitliCihazlar:
      case SirketMenuItem.bluetoothWifiKur:
      case SirketMenuItem.dashboard:
      case SirketMenuItem.profilim:
      case SirketMenuItem.ellerSerbest:
        return null;
    }
  }

  String _titleForMenu(SirketMenuItem item) {
    switch (item) {
      case SirketMenuItem.dashboard:
        return 'AHBU Panel';
      case SirketMenuItem.profilim:
        return 'Profilim';
      case SirketMenuItem.abonelikTalepleri:
        return 'Yeni Abonelik Talepleri';
      case SirketMenuItem.siteOnayTalepleri:
        return 'Site Onay Talepleri';
      case SirketMenuItem.superUserYonetimi:
        return 'Super User Yonetimi';
      case SirketMenuItem.siteYoneticileriYonetimi:
        return 'Site Yoneticileri Yonetimi';
      case SirketMenuItem.daireKullanicilariYonetimi:
        return 'Daire Kullanicilari Yonetimi';
      case SirketMenuItem.siteler:
        return 'Site Yonetimi';
      case SirketMenuItem.cihazEkle:
        return 'Sirket Veritabanina Cihaz Kaydet';
      case SirketMenuItem.kayitliCihazlar:
        return 'Sirket Hesabina Kayitli Cihazlar';
      case SirketMenuItem.bluetoothWifiKur:
        return 'Bluetooth ile Wi-Fi Kur';
      case SirketMenuItem.ellerSerbest:
        return 'Eller Serbest & Kestirmeler';
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

  bool _useCompactSectionLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 760;
  }

  bool _canAccessMenu(SirketMenuItem item, UserRole role) {
    switch (role) {
      case UserRole.superUser:
        return const {
          SirketMenuItem.dashboard,
          SirketMenuItem.profilim,
          SirketMenuItem.ellerSerbest,
          SirketMenuItem.superUserYonetimi,
          SirketMenuItem.siteYoneticileriYonetimi,
          SirketMenuItem.daireKullanicilariYonetimi,
          SirketMenuItem.siteler,
          SirketMenuItem.cihazEkle,
          SirketMenuItem.kayitliCihazlar,
          SirketMenuItem.bluetoothWifiKur,
        }.contains(item);
      case UserRole.siteManager:
        return const {
          SirketMenuItem.dashboard,
          SirketMenuItem.profilim,
          SirketMenuItem.ellerSerbest,
          SirketMenuItem.siteler,
          SirketMenuItem.kayitliCihazlar,
          SirketMenuItem.bluetoothWifiKur,
        }.contains(item);
      case UserRole.apartmentOwner:
        return const {
          SirketMenuItem.dashboard,
          SirketMenuItem.profilim,
          SirketMenuItem.ellerSerbest,
        }.contains(item);
    }
  }

  ThemeData _themeForRole(BuildContext context, UserRole role) {
    final base = Theme.of(context);
    final accent = role.accentColor;
    final colorScheme = base.colorScheme.copyWith(
      primary: accent,
      secondary: role.lightAccentColor,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: accent),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(backgroundColor: accent),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }

  void _selectMenu(SirketMenuItem item) {
    final sessionRole = widget.authService.session?.role;
    if (sessionRole != null && !_canAccessMenu(item, sessionRole)) {
      Navigator.pop(context);
      _showMessage('Bu menu icin yetkiniz yok.');
      return;
    }
    Navigator.pop(context);
    if (item == SirketMenuItem.ellerSerbest) {
      if (widget.voiceDoorService != null) {
        HandsFreeSettingsDialog.show(
          context,
          voiceDoorService: widget.voiceDoorService!,
        );
      }
      return;
    }
    setState(() => _selectedMenu = item);
    if (item == SirketMenuItem.kayitliCihazlar) {
      _loadCompanyDevices(force: true);
    }
    final role = _roleForMenu(item);
    if (role != null) {
      _loadManagedUsers(role);
      return;
    }
    if (item == SirketMenuItem.abonelikTalepleri) {
      _loadSubscriptionRequests();
      return;
    }
    if (item == SirketMenuItem.siteOnayTalepleri) {
      _loadPendingSiteApprovals();
      return;
    }
    if (
      item == SirketMenuItem.siteler ||
      item == SirketMenuItem.daireKullanicilariYonetimi
    ) {
      _loadSites();
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

  Future<void> _loadSites({bool force = false, int? page}) async {
    if (_isLoadingSites) {
      return;
    }

    final targetPage = page ?? _sitesPage?.page ?? 1;
    if (!force && _sitesPage != null && page == null) {
      return;
    }

    setState(() => _isLoadingSites = true);
    try {
      final result = await widget.authService.listSites(
        page: targetPage,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      final nextSelectedSite =
          result.sites.where((site) => site.id == _selectedSite?.id).isNotEmpty
          ? result.sites.where((site) => site.id == _selectedSite?.id).first
          : (result.sites.isNotEmpty ? result.sites.first : null);
      setState(() {
        _sitesPage = result;
        _selectedSite = nextSelectedSite;
      });
      if (nextSelectedSite != null) {
        await _loadSiteStructure(nextSelectedSite.id, force: true);
      } else {
        setState(() => _selectedSiteStructure = null);
      }
    } on ApiException catch (e) {
      if (mounted) {
        _showMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Site listesi alinamadi.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSites = false);
      }
    }
  }

  Future<void> _loadSiteStructure(int siteCode, {bool force = false}) async {
    if (_isLoadingSiteStructure) {
      return;
    }
    if (!force && _selectedSiteStructure?.site.id == siteCode) {
      return;
    }

    setState(() => _isLoadingSiteStructure = true);
    final (structure, error) = await widget.authService.getSiteStructure(
      siteCode: siteCode,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLoadingSiteStructure = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (structure == null) {
      _showMessage('Site yapisi alinamadi.');
      return;
    }

    setState(() {
      _selectedSite = structure.site;
      _selectedSiteStructure = structure;
    });
  }

  Future<void> _loadDoorControlSites({bool force = false}) async {
    if (_isLoadingDoorControlSites) {
      return;
    }
    if (!force && _doorControlSitesPage != null) {
      return;
    }

    setState(() => _isLoadingDoorControlSites = true);
    try {
      final session = widget.authService.session;
      if (session?.role == UserRole.apartmentOwner) {
        final (doors, error) = await widget.authService.listMyDoors();
        if (!mounted) {
          return;
        }
        if (error != null) {
          _showMessage(error);
          return;
        }

        final accessibleDoors = doors ?? const <DoorRecord>[];
        final sitesById = <int, SiteRecord>{};
        final doorsBySite = <int, List<DoorRecord>>{};
        for (final door in accessibleDoors) {
          sitesById.putIfAbsent(
            door.siteCode,
            () => SiteRecord(
              id: door.siteCode,
              name: door.siteName ?? 'Site ${door.siteCode}',
              address: null,
              city: null,
              district: null,
              blockCount: 0,
              apartmentCount: 0,
              doorCount: 0,
              approvalStatus: 'approved',
              approvedAt: null,
              mqttSiteId: door.mqttSiteId ?? 0,
              managerUserCode: null,
              managerName: null,
              createdAt: null,
            ),
          );
          doorsBySite.putIfAbsent(door.siteCode, () => <DoorRecord>[]).add(door);
        }

        final sites = sitesById.values.toList()
          ..sort((left, right) => left.name.compareTo(right.name));
        final selected = sites.isNotEmpty ? sites.first : null;
        setState(() {
          _doorControlSitesPage = SitePage(
            sites: sites,
            total: sites.length,
            page: 1,
            pageSize: sites.length,
          );
          _doorControlSite = selected;
          _doorControlStructure = selected == null
              ? null
              : SiteStructureRecord(
                  site: selected,
                  blocks: const [],
                  apartments: const [],
                  doors: doorsBySite[selected.id] ?? const <DoorRecord>[],
                );
          _doorControlDoor = _doorControlStructure?.doors.isNotEmpty == true
              ? _doorControlStructure!.doors.first
              : null;
        });
        if (_doorControlDoor != null) {
          _startDoorStatusPolling(_doorControlDoor!);
        }
        if (widget.quickActionsService != null) {
          widget.quickActionsService!.updateDoorShortcuts(accessibleDoors);
        }
        if (widget.voiceDoorService?.handsFreeAutoListen == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _openVoiceControlModal();
            }
          });
        }
        return;
      }

      final sites = <SiteRecord>[];
      var page = 1;
      var total = 0;
      var pageSize = 50;

      while (true) {
        final result = await widget.authService.listSites(
          page: page,
          pageSize: pageSize,
        );
        sites.addAll(result.sites);
        total = result.total;
        pageSize = result.pageSize;
        if (page >= result.totalPages) {
          break;
        }
        page += 1;
      }

      if (!mounted) {
        return;
      }

      SiteRecord? selected = sites.isNotEmpty ? sites.first : null;
      if (_doorControlSite != null) {
        selected = null;
        for (final site in sites) {
          if (site.id == _doorControlSite!.id) {
            selected = site;
            break;
          }
        }
      }

      setState(() {
        _doorControlSitesPage = SitePage(
          sites: sites,
          total: total,
          page: 1,
          pageSize: pageSize,
        );
        _doorControlSite = selected;
      });

      if (selected != null) {
        await _loadDoorControlStructure(selected.id, force: true);
      }
      if (widget.voiceDoorService?.handsFreeAutoListen == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openVoiceControlModal();
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        _showMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Kapi kontrol site listesi alinamadi.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDoorControlSites = false);
      }
    }
  }

  Future<void> _loadCompanyDevices({int page = 1, bool force = false}) async {
    if (_isLoadingCompanyDevices) {
      return;
    }
    if (!force && _companyDevicesPage != null && _companyDevicesPage!.page == page) {
      return;
    }

    setState(() => _isLoadingCompanyDevices = true);
    final (devices, error) = await widget.authService.listCompanyDevices(
      page: page,
      pageSize: _pageSize,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingCompanyDevices = false;
      if (error == null) {
        _companyDevicesPage = devices;
      }
    });

    if (error != null) {
      _showMessage(error);
    }
  }

  Future<List<SiteRecord>> _loadAllSitesForPicker() async {
    final sites = <SiteRecord>[];
    var page = 1;
    while (true) {
      final result = await widget.authService.listSites(
        page: page,
        pageSize: 100,
      );
      sites.addAll(result.sites);
      if (page >= result.totalPages) {
        break;
      }
      page += 1;
    }
    return sites;
  }

  Future<void> _editCompanyDevice(DeviceRecord device) async {
    final result = await showDialog<_DeviceEditResult>(
      context: context,
      builder: (dialogContext) => _DeviceEditDialog(
        device: device,
        isSuperUser: widget.authService.session?.role == UserRole.superUser,
      ),
    );
    if (result == null) {
      return;
    }

    final updateResult = await widget.authService.updateDevice(
      deviceId: device.id,
      assignedUserCode: result.assignedUserCode,
      siteCode: result.siteCode,
      gateName: result.gateName,
    );
    final error = updateResult.$2;
    if (!mounted) {
      return;
    }
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Cihaz guncellendi.');
    await _loadCompanyDevices(page: _companyDevicesPage?.page ?? 1, force: true);
  }

  Future<void> _deleteCompanyDevice(DeviceRecord device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cihazi Sil'),
        content: Text(
          '${device.deviceUid} cihazini silmek istiyor musunuz? Varsa kapi atamasi da kaldirilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Iptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final error = await widget.authService.deleteDevice(deviceId: device.id);
    if (!mounted) {
      return;
    }
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Cihaz silindi.');
    await _loadCompanyDevices(page: _companyDevicesPage?.page ?? 1, force: true);
  }

  Future<void> _broadcastOtaCheckToAllDevices() async {
    final total = _companyDevicesPage?.total ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tum Cihazlara OTA Kontrolu'),
        content: Text(
          'Kayitli $total cihaza kendinizi guncelleyin kontrol komutu gonderilecek. '
          'Manifest kapaliysa cihazlar guncelleme indirmez. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgec'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Gonder'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _isBroadcastingOtaCheck = true);
    final (result, error) = await widget.authService.broadcastOtaCheck();
    if (!mounted) {
      return;
    }
    setState(() => _isBroadcastingOtaCheck = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    final requested = result?['requested'] as int? ?? 0;
    final sent = result?['sent'] as int? ?? 0;
    final jobId = result?['job_id'];
    final failed = result?['failed'] as List<dynamic>? ?? const <dynamic>[];
    _showMessage(
      'OTA kontrol komutu gonderildi. Is No: ${jobId ?? '-'}, hedef: $requested, basarili: $sent, hata: ${failed.length}.',
    );
  }

  Future<void> _assignCompanyDeviceToDoor(DeviceRecord device) async {
    List<SiteRecord> sites;
    try {
      sites = await _loadAllSitesForPicker();
    } catch (_) {
      if (mounted) {
        _showMessage('Site listesi alinamadi.');
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final door = await showDialog<DoorRecord>(
      context: context,
      builder: (dialogContext) => _DeviceDoorAssignDialog(
        authService: widget.authService,
        sites: sites,
        device: device,
      ),
    );
    if (door == null) {
      return;
    }

    final assignResult = await widget.authService.assignDoorDevice(
      doorId: door.id,
      deviceUid: device.deviceUid,
    );
    final error = assignResult.$2;
    if (!mounted) {
      return;
    }
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('${device.deviceUid} cihazi ${door.doorName} kapisina atandi.');
    await _loadCompanyDevices(page: _companyDevicesPage?.page ?? 1, force: true);
  }

  Future<void> _loadDoorControlStructure(
    int siteCode, {
    bool force = false,
  }) async {
    if (_isLoadingDoorControlStructure) {
      return;
    }
    if (!force && _doorControlStructure?.site.id == siteCode) {
      return;
    }

    setState(() {
      _isLoadingDoorControlStructure = true;
      _doorControlDoor = null;
      _clearDoorRuntimeStatus();
    });

    final (structure, error) = await widget.authService.getSiteStructure(
      siteCode: siteCode,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLoadingDoorControlStructure = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (structure == null) {
      _showMessage('Kapi kontrol site yapisi alinamadi.');
      return;
    }

    setState(() {
      _doorControlSite = structure.site;
      _doorControlStructure = structure;
    });
  }

  Future<void> _selectDoorControlSite(int siteCode) async {
    SiteRecord? site;
    for (final item in _doorControlSitesPage?.sites ?? const <SiteRecord>[]) {
      if (item.id == siteCode) {
        site = item;
        break;
      }
    }
    if (site == null) {
      return;
    }

    setState(() {
      _doorControlSite = site;
      _doorControlStructure = null;
      _doorControlDoor = null;
      _clearDoorRuntimeStatus();
    });

    if (widget.authService.session?.role == UserRole.apartmentOwner) {
      final (doors, error) = await widget.authService.listMyDoors();
      if (!mounted) {
        return;
      }
      if (error != null) {
        _showMessage(error);
        return;
      }
      final siteDoors = (doors ?? const <DoorRecord>[])
          .where((door) => door.siteCode == site!.id)
          .toList();
      setState(() {
        _doorControlStructure = SiteStructureRecord(
          site: site!,
          blocks: const [],
          apartments: const [],
          doors: siteDoors,
        );
        _doorControlDoor = siteDoors.isNotEmpty ? siteDoors.first : null;
      });
      if (_doorControlDoor != null) {
        _startDoorStatusPolling(_doorControlDoor!);
      }
      return;
    }

    await _loadDoorControlStructure(site.id, force: true);
  }

  void _selectDoorControlDoor(int doorId) {
    DoorRecord? door;
    for (final item in _doorControlStructure?.doors ?? const <DoorRecord>[]) {
      if (item.id == doorId) {
        door = item;
        break;
      }
    }
    if (door == null) {
      return;
    }
    final selectedDoor = door;

    setState(() {
      _doorControlDoor = selectedDoor;
      _doorRuntimeStatus = null;
      _doorStatusError = null;
    });
    _startDoorStatusPolling(selectedDoor);
  }

  void _clearDoorRuntimeStatus() {
    _stopDoorStatusTimer();
    _doorRuntimeStatus = null;
    _doorStatusError = null;
    _isLoadingDoorStatus = false;
    _isOpeningDoor = false;
  }

  void _stopDoorStatusTimer() {
    _doorStatusTimer?.cancel();
    _doorStatusTimer = null;
  }

  void _startDoorStatusPolling(DoorRecord door) {
    _stopDoorStatusTimer();
    if (door.assignedDeviceUid == null || door.assignedDeviceUid!.trim().isEmpty) {
      return;
    }
    _refreshDoorRuntimeStatus(showLoading: true);
    _doorStatusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshDoorRuntimeStatus();
    });
  }

  Future<void> _refreshDoorRuntimeStatus({bool showLoading = false}) async {
    final door = _doorControlDoor;
    if (door == null ||
        door.assignedDeviceUid == null ||
        door.assignedDeviceUid!.trim().isEmpty) {
      return;
    }
    if (_isLoadingDoorStatus) {
      return;
    }

    if (showLoading && mounted) {
      setState(() => _isLoadingDoorStatus = true);
    } else {
      _isLoadingDoorStatus = true;
    }

    final (status, error) = await widget.authService.getDoorRuntimeStatus(
      doorId: door.id,
    );
    if (!mounted) {
      return;
    }
    if (_doorControlDoor?.id != door.id) {
      setState(() => _isLoadingDoorStatus = false);
      return;
    }

    setState(() {
      _isLoadingDoorStatus = false;
      if (status != null) {
        _doorRuntimeStatus = status;
        _doorStatusError = null;
      } else {
        _doorStatusError = error;
      }
    });
  }

  Future<void> _selectSite(SiteRecord site) async {
    setState(() {
      _selectedSite = site;
    });
    await _loadSiteStructure(site.id, force: true);
  }

  Future<void> _loadSubscriptionRequests({
    bool force = false,
    int? page,
  }) async {
    if (_isLoadingSubscriptionRequests) {
      return;
    }

    final targetPage = page ?? _subscriptionRequestsPage?.page ?? 1;
    if (!force && _subscriptionRequestsPage != null && page == null) {
      return;
    }

    setState(() => _isLoadingSubscriptionRequests = true);
    try {
      final result = await widget.authService.listSubscriptionRequests(
        page: targetPage,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() => _subscriptionRequestsPage = result);
    } on ApiException catch (e) {
      if (mounted) {
        _showMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Abonelik talepleri alinamadi.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSubscriptionRequests = false);
      }
    }
  }

  Future<void> _resolveSubscriptionRequest({
    required int userCode,
    required String action,
  }) async {
    setState(() => _busySubscriptionRequests.add(userCode));
    final error = await widget.authService.resolveSubscriptionRequest(
      userCode: userCode,
      action: action,
    );

    if (!mounted) {
      return;
    }

    setState(() => _busySubscriptionRequests.remove(userCode));
    if (error != null) {
      _showMessage(error);
      return;
    }

    final currentPage = _subscriptionRequestsPage;
    final targetPage =
        currentPage != null &&
            currentPage.requests.length == 1 &&
            currentPage.page > 1
        ? currentPage.page - 1
        : currentPage?.page ?? 1;
    await _loadSubscriptionRequests(force: true, page: targetPage);
    if (!mounted) {
      return;
    }

    _showMessage(
      action == 'approve'
          ? 'Abonelik talebi onaylandi.'
          : 'Abonelik talebi reddedildi.',
    );
  }

  Future<void> _loadPendingSiteApprovals({
    bool force = false,
    int? page,
  }) async {
    if (_isLoadingPendingSiteApprovals) {
      return;
    }

    final targetPage = page ?? _pendingSiteApprovalsPage?.page ?? 1;
    if (!force && _pendingSiteApprovalsPage != null && page == null) {
      return;
    }

    setState(() => _isLoadingPendingSiteApprovals = true);
    try {
      final result = await widget.authService.listSites(
        page: targetPage,
        pageSize: _pageSize,
        approvalStatus: 'pending',
      );
      if (!mounted) {
        return;
      }
      setState(() => _pendingSiteApprovalsPage = result);
    } on ApiException catch (e) {
      if (mounted) {
        _showMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Site onay talepleri alinamadi.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPendingSiteApprovals = false);
      }
    }
  }

  Future<void> _resolveSiteApproval({
    required int siteCode,
    required String action,
  }) async {
    setState(() => _busySiteApprovals.add(siteCode));
    final error = await widget.authService.resolveSiteApproval(
      siteCode: siteCode,
      action: action,
    );

    if (!mounted) {
      return;
    }

    setState(() => _busySiteApprovals.remove(siteCode));
    if (error != null) {
      _showMessage(error);
      return;
    }

    final currentPage = _pendingSiteApprovalsPage;
    final targetPage =
        currentPage != null &&
            currentPage.sites.length == 1 &&
            currentPage.page > 1
        ? currentPage.page - 1
        : currentPage?.page ?? 1;
    await _loadPendingSiteApprovals(force: true, page: targetPage);
    await _loadSites(force: true, page: _sitesPage?.page ?? 1);
    if (!mounted) {
      return;
    }

    _showMessage(
      action == 'approve'
          ? 'Site talebi onaylandi.'
          : 'Site talebi reddedildi.',
    );
  }

  Future<void> _openSiteDialog({SiteRecord? site}) async {
    final result = await showDialog<_SiteFormResult>(
      context: context,
      builder: (dialogContext) => _SiteDialog(
        authService: widget.authService,
        site: site,
        structure: site != null && _selectedSiteStructure?.site.id == site.id
            ? _selectedSiteStructure
            : null,
      ),
    );

    if (result == null) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    final isEditing = site != null;
    final error = isEditing
        ? await widget.authService.updateSite(
            siteCode: site.id,
            name: result.name,
            address: result.address,
            city: result.city,
            district: result.district,
            blockApartmentCounts: result.blockApartmentCounts,
            doorCount: result.doorCount,
            managerUserCode: result.managerUserCode,
          )
        : await widget.authService.createSite(
            name: result.name,
            address: result.address,
            city: result.city,
            district: result.district,
            blockApartmentCounts: result.blockApartmentCounts,
            doorCount: result.doorCount,
            managerUserCode: result.managerUserCode,
            managerUser: result.managerUser,
          );

    if (!mounted) {
      return;
    }

    if (error != null) {
      _showMessage(error);
      return;
    }

    final targetPage = isEditing ? _sitesPage?.page ?? 1 : 1;
    await _loadSites(force: true, page: targetPage);
    if (!mounted) {
      return;
    }

    if (isEditing) {
      await _loadSiteStructure(site.id, force: true);
    }

    _showMessage(isEditing ? 'Site guncellendi.' : 'Site olusturuldu.');
  }

  Future<void> _deleteSite(SiteRecord site) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Site Sil'),
            content: Text(
              '${site.name} kaydini silmek istediginize emin misiniz?',
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

    setState(() => _busyDeleteSites.add(site.id));
    final error = await widget.authService.deleteSite(siteCode: site.id);
    if (!mounted) {
      return;
    }

    setState(() => _busyDeleteSites.remove(site.id));
    if (error != null) {
      _showMessage(error);
      return;
    }

    final currentPage = _sitesPage;
    final targetPage =
        currentPage != null &&
            currentPage.sites.length == 1 &&
            currentPage.page > 1
        ? currentPage.page - 1
        : currentPage?.page ?? 1;
    await _loadSites(force: true, page: targetPage);
    if (!mounted) {
      return;
    }
    if (_selectedSite?.id == site.id) {
      setState(() {
        _selectedSite = null;
        _selectedSiteStructure = null;
      });
    }
    _showMessage('Site silindi.');
  }

  Future<void> _openApartmentResidentDialog(ApartmentRecord apartment) async {
    final result = await showDialog<_ApartmentResidentFormResult>(
      context: context,
      builder: (dialogContext) =>
          _ApartmentResidentDialog(apartment: apartment),
    );

    if (result == null) {
      return;
    }

    setState(() => _busyApartments.add(apartment.id));
    final (updatedApartment, error) = await widget.authService
        .upsertApartmentResident(
          apartmentId: apartment.id,
          fullName: result.fullName,
          loginName: result.loginName,
          password: result.password,
          email: result.email,
          phoneNumber: result.phoneNumber,
          isActive: result.isActive,
        );

    if (!mounted) {
      return;
    }

    setState(() => _busyApartments.remove(apartment.id));
    if (error != null) {
      _showMessage(error);
      return;
    }

    if (updatedApartment != null && _selectedSite != null) {
      await _loadSiteStructure(_selectedSite!.id, force: true);
    }
    if (!mounted) {
      return;
    }
    _showMessage('Daire kullanicisi kaydedildi.');
  }

  Future<void> _sendApartmentCredentials(ApartmentRecord apartment) async {
    setState(() => _busyApartments.add(apartment.id));
    final error = await widget.authService.sendApartmentCredentials(
      apartmentId: apartment.id,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busyApartments.remove(apartment.id));
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Daire giris bilgileri e-posta ile gonderildi.');
  }

  Future<void> _assignDoorDevice(DoorRecord door) async {
    final scannedUid = await Navigator.of(
      context,
    ).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScanPage(
          accentColor: widget.authService.session?.role.accentColor,
        ),
      ),
    );

    if (!mounted || scannedUid == null || scannedUid.trim().isEmpty) {
      return;
    }

    final result = await showDialog<_DoorDeviceAssignResult>(
      context: context,
      builder: (dialogContext) =>
          _DoorDeviceDialog(door: door, initialDeviceUid: scannedUid),
    );

    if (result == null) {
      return;
    }

    setState(() => _busyDoors.add(door.id));
    final (updatedDoor, error) = await widget.authService.assignDoorDevice(
      doorId: door.id,
      deviceUid: result.deviceUid,
    );

    if (!mounted) {
      return;
    }

    setState(() => _busyDoors.remove(door.id));
    if (error != null) {
      if (error.contains('sirket hesabinda kayitli degil')) {
        _showMessage(
          'Cihaz once Sirket Veritabanina Cihaz Kaydet menusunden kaydedilmeli.',
        );
      } else {
        _showMessage(error);
      }
      return;
    }

    if (updatedDoor != null && _selectedSite != null) {
      await _loadSiteStructure(_selectedSite!.id, force: true);
    }
    if (!mounted) {
      return;
    }
    _showMessage('Kapi cihazi guncellendi.');
  }

  Future<void> _openDeviceRegistrationFlow() async {
    final scannedUid = await Navigator.of(
      context,
    ).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScanPage(
          accentColor: widget.authService.session?.role.accentColor,
        ),
      ),
    );

    if (!mounted || scannedUid == null || scannedUid.trim().isEmpty) {
      return;
    }

    final result = await showDialog<_DeviceFormResult>(
      context: context,
      builder: (dialogContext) => _DeviceDialog(initialDeviceUid: scannedUid),
    );

    if (result == null) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    final (device, error) = await widget.authService.createDevice(
      deviceUid: result.deviceUid,
      assignedUserCode: result.assignedUserCode,
      siteCode: result.siteCode,
    );

    if (!mounted) {
      return;
    }

    if (error != null) {
      _showMessage(error);
      return;
    }

    _showMessage('Cihaz ${device?.deviceUid ?? result.deviceUid} kaydedildi.');
  }

  Future<void> _openManualDeviceRegistrationFlow() async {
    final result = await showDialog<_DeviceFormResult>(
      context: context,
      builder: (dialogContext) => const _DeviceDialog(initialDeviceUid: ''),
    );

    if (result == null) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    final (device, error) = await widget.authService.createDevice(
      deviceUid: result.deviceUid,
      assignedUserCode: result.assignedUserCode,
      siteCode: result.siteCode,
    );

    if (!mounted) {
      return;
    }

    if (error != null) {
      _showMessage(error);
      return;
    }

    _showMessage('Cihaz ${device?.deviceUid ?? result.deviceUid} kaydedildi.');
  }

  Future<void> _openWifiProvisionFlow() async {
    await Navigator.of(
      context,
    ).push<void>(
      MaterialPageRoute(
        builder: (_) => WifiProvisionPage(
          authService: widget.authService,
          accentColor: widget.authService.session?.role.accentColor,
          surfaceColor: widget.authService.session?.role.surfaceColor,
        ),
      ),
    );
  }

  Future<void> openDeviceAddFlow() async {
    final _DeviceToolAction?
    action = await showModalBottomSheet<_DeviceToolAction>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_outlined),
                title: const Text('QR ile Sirket Veritabanina Kaydet'),
                subtitle: const Text(
                  'Cihaz Unique ID bilgisini okuyup sirket hesabina kaydeder.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_DeviceToolAction.registerDevice),
              ),
              ListTile(
                leading: const Icon(Icons.bluetooth_searching_outlined),
                title: const Text('Bluetooth ile Wi-Fi Kur'),
                subtitle: const Text(
                  'Kurulmamıs cihaza yakin Wi-Fi bilgisini gonderir.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_DeviceToolAction.provisionWifi),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == _DeviceToolAction.registerDevice) {
      await _openDeviceRegistrationFlow();
      return;
    }

    await Navigator.of(
      context,
    ).push<void>(
      MaterialPageRoute(
        builder: (_) => WifiProvisionPage(
          authService: widget.authService,
          accentColor: widget.authService.session?.role.accentColor,
          surfaceColor: widget.authService.session?.role.surfaceColor,
        ),
      ),
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
    final door = _doorControlDoor;
    if (door == null || _isOpeningDoor) {
      return;
    }

    setState(() => _isOpeningDoor = true);
    final (status, error) = await widget.authService.openDoor(
      doorId: door.id,
      door: door,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isOpeningDoor = false;
      if (status != null) {
        _doorRuntimeStatus = status;
        _doorStatusError = null;
      }
    });
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
          .map(
            (item) =>
                item.id == user.id ? item.copyWith(isActive: value) : item,
          )
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

    final confirmed =
        await showDialog<bool>(
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

    final error = await widget.authService.deleteManagedUser(userCode: user.id);

    if (!mounted) {
      return;
    }

    if (error != null) {
      _showMessage(error);
      return;
    }

    final currentPage = _managedPages[role];
    final targetPage =
        currentPage != null &&
            currentPage.users.length == 1 &&
            currentPage.page > 1
        ? currentPage.page - 1
        : currentPage?.page ?? 1;

    await _loadManagedUsers(role, force: true, page: targetPage);
    if (!mounted) {
      return;
    }
    _showMessage('${_roleTitle(role)} hesabi silindi.');
  }

  Future<void> _showManagedUserDetails({
    required UserRole role,
    required ManagedUserAccount user,
    required UserSession session,
  }) async {
    final isSelf = user.id == session.id;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(user.fullName),
        content: SizedBox(
          width: _dialogWidthForScreen(dialogContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kod: ${user.id}'),
              const SizedBox(height: 8),
              Text('E-posta: ${user.email}'),
              if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Telefon: ${user.phoneNumber}'),
              ],
              const SizedBox(height: 8),
              Text('Durum: ${user.isActive ? 'Aktif' : 'Pasif'}'),
              const SizedBox(height: 8),
              Text('Kayit Tarihi: ${_formatDate(user.createdAt)}'),
              if (isSelf) ...[
                const SizedBox(height: 12),
                const Text(
                  'Kendi super user hesabiniza silme ve pasif etme kilidi uygulanir.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openManagedUserDialog(role: role, user: user);
            },
            child: const Icon(Icons.edit_outlined, size: 18),
          ),
          ElevatedButton(
            onPressed: isSelf
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _deleteManagedUser(role: role, user: user);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(UserSession session) {
    final dashboardDescription = switch (session.role) {
      UserRole.superUser =>
        'Tum kullanicilari, siteleri, cihazlari ve kapi erisimlerini yonetebilirsiniz.',
      UserRole.siteManager =>
        'Yetkili oldugunuz siteleri, cihazlari ve kapilari yonetebilirsiniz.',
      UserRole.apartmentOwner =>
        'Yetkili oldugunuz kapilari gorup kapi acma komutu verebilirsiniz.',
    };
    final roleColor = session.role.accentColor;

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
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(dashboardDescription),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  backgroundColor: roleColor.withValues(alpha: 0.12),
                  side: BorderSide(color: roleColor.withValues(alpha: 0.35)),
                  avatar: Icon(Icons.verified_user_outlined, color: roleColor),
                  label: Text(
                    session.role.label,
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildDoorControlPanel(),
      ],
    );
  }

  Widget _buildDoorControlPanel() {
    final sites = _doorControlSitesPage?.sites ?? const <SiteRecord>[];
    final doors = _doorControlStructure?.doors ?? const <DoorRecord>[];
    final selectedDoor = _doorControlDoor;
    final runtimeStatus = _doorRuntimeStatus;

    Widget buildStatus() {
      if (selectedDoor == null) {
        return const Text(
          'Kontrol etmek icin once siteyi, sonra o siteye ait kapiyi secin.',
          style: TextStyle(color: AppColors.textMuted),
        );
      }

      if (selectedDoor.assignedDeviceUid == null ||
          selectedDoor.assignedDeviceUid!.trim().isEmpty) {
        return const Text(
          'Bu kapiya henuz cihaz atanmamis. Kapi acma komutu aktif olmaz.',
          style: TextStyle(color: Colors.red),
        );
      }

      final connectionText = runtimeStatus == null
          ? 'Bilinmiyor'
          : runtimeStatus.mqttBridgeConnected
          ? 'Hazir'
          : 'Hazir degil';
      final deviceOnlineText = runtimeStatus == null
          ? 'Bilinmiyor'
          : runtimeStatus.mqttConnected
          ? 'Online'
          : 'Offline';
      final stateText = runtimeStatus?.doorLocked == null
          ? 'Bilinmiyor'
          : (runtimeStatus!.doorLocked! ? 'Kapali/Kilitli' : 'Acik');
      final signalText = runtimeStatus?.wifiSignalPercent == null
          ? '-'
          : '%${runtimeStatus!.wifiSignalPercent}'
                '${runtimeStatus.wifiRssi == null ? '' : ' (${runtimeStatus.wifiRssi} dBm)'}';
      final localCommandAvailable = widget.authService.canTryLocalDoorOpen(
        selectedDoor,
      );
      final commandEnabled =
          (runtimeStatus?.commandEnabled == true || localCommandAvailable) &&
          !_isOpeningDoor;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cihaz: ${selectedDoor.assignedDeviceUid}'),
          const SizedBox(height: 6),
          Text('Sunucu MQTT: $connectionText'),
          const SizedBox(height: 6),
          Text('Cihaz Baglantisi: $deviceOnlineText'),
          const SizedBox(height: 6),
          Text('Kapi Durumu: $stateText'),
          const SizedBox(height: 6),
          Text(
            'Yerel Ag Kontrolu: ${localCommandAvailable ? 'Hazir' : 'Hazir degil'}',
          ),
          const SizedBox(height: 6),
          Text('Firmware: ${runtimeStatus?.firmwareVersion ?? '-'}'),
          const SizedBox(height: 6),
          Text('OTA Durumu: ${runtimeStatus?.otaStatus ?? '-'}'),
          const SizedBox(height: 6),
          Text('Wi-Fi Gucu: $signalText'),
          if (runtimeStatus?.lastSeenAt != null) ...[
            const SizedBox(height: 6),
            Text('Son Guncelleme: ${_formatDate(runtimeStatus!.lastSeenAt)}'),
          ],
          if (_isLoadingDoorStatus) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_doorStatusError != null) ...[
            const SizedBox(height: 8),
            Text(
              _doorStatusError!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: commandEnabled ? _openDoor : null,
              icon: const Icon(Icons.lock_open),
              label: Text(_isOpeningDoor ? 'Gonderiliyor' : 'Kapi Ac'),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.glassCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kapi Ac / Kapat',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Once siteyi secin, sonra o siteye ait kapiyi secin. Kapiya cihaz atanmis ve MQTT baglantisi saglikliysa kapi acma komutu aktif olur.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _doorControlSite?.id,
            decoration: const InputDecoration(labelText: 'Site sec'),
            items: [
              for (final site in sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text('${site.name} (${site.id})'),
                ),
            ],
            onChanged: _isLoadingDoorControlSites
                ? null
                : (value) {
                    if (value != null) {
                      _selectDoorControlSite(value);
                    }
                  },
          ),
          if (_isLoadingDoorControlSites) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selectedDoor?.id,
            decoration: const InputDecoration(labelText: 'Kapi sec'),
            items: [
              for (final door in doors)
                DropdownMenuItem<int>(
                  value: door.id,
                  child: Text(
                    '${door.doorName} - ${door.assignedDeviceUid ?? 'Cihaz yok'}',
                  ),
                ),
            ],
            onChanged: _isLoadingDoorControlStructure || doors.isEmpty
                ? null
                : (value) {
                    if (value != null) {
                      _selectDoorControlDoor(value);
                    }
                  },
          ),
          if (_isLoadingDoorControlStructure) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 14),
          buildStatus(),
        ],
      ),
    );
  }

  Widget _buildDeviceAddScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sirket Veritabanina Cihaz Kaydet',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Cihazin Unique ID bilgisini QR koddan okuyarak veya masaustu kullanimda elle yazarak sirket veritabanina kaydedebilirsiniz.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 680;
            final children = [
              _DeviceActionTile(
                icon: Icons.qr_code_scanner_outlined,
                title: 'QR ile Sirket Veritabanina Kaydet',
                description:
                    'Cihaz uzerindeki QR kodu okutur, Unique ID alanini otomatik doldurur ve sirket kayit formunu acar.',
                buttonLabel: 'QR Oku',
                onPressed: _openDeviceRegistrationFlow,
              ),
              _DeviceActionTile(
                icon: Icons.edit_note_outlined,
                title: 'Unique ID ile Sirket Veritabanina Kaydet',
                description:
                    'QR okunamiyorsa veya masaustu surumde calisiyorsaniz cihaz Unique ID bilgisini elle girerek sirket hesabina kayit yapar.',
                buttonLabel: 'Unique ID Gir',
                onPressed: _openManualDeviceRegistrationFlow,
              ),
            ];

            if (isCompact) {
              return Column(
                children: [
                  children[0],
                  const SizedBox(height: 12),
                  children[1],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 12),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCompanyDevicesScreen() {
    final pageData = _companyDevicesPage;
    final devices = pageData?.devices ?? const <DeviceRecord>[];

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
                'Sirket Hesabina Kayitli Cihazlar',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sirket veritabanina kaydedilmis cihazlari, atandiklari site ve kapi bilgileriyle birlikte gorebilirsiniz.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        _isBroadcastingOtaCheck ||
                            _isLoadingCompanyDevices ||
                            (pageData?.total ?? 0) == 0
                        ? null
                        : _broadcastOtaCheckToAllDevices,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(
                      _isBroadcastingOtaCheck
                          ? 'Gonderiliyor'
                          : 'Tumune OTA Kontrolu',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: _isLoadingCompanyDevices
                        ? null
                        : () => _loadCompanyDevices(
                            page: pageData?.page ?? 1,
                            force: true,
                          ),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoadingCompanyDevices)
          const LinearProgressIndicator()
        else if (devices.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard,
            child: const Text('Sirket hesabina kayitli cihaz bulunamadi.'),
          )
        else
          ...devices.map(_buildCompanyDeviceCard),
        if (pageData != null && pageData.totalPages > 1) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sayfa ${pageData.page} / ${pageData.totalPages} | Toplam ${pageData.total}',
                ),
              ),
              TextButton(
                onPressed: pageData.page > 1 && !_isLoadingCompanyDevices
                    ? () => _loadCompanyDevices(page: pageData.page - 1)
                    : null,
                child: const Text('Onceki'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed:
                    pageData.page < pageData.totalPages &&
                        !_isLoadingCompanyDevices
                    ? () => _loadCompanyDevices(page: pageData.page + 1)
                    : null,
                child: const Text('Sonraki'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCompanyDeviceCard(DeviceRecord device) {
    final isSuperUser = widget.authService.session?.role == UserRole.superUser;
    final siteText = device.siteName == null
        ? (device.siteCode == null ? '-' : 'Site ID: ${device.siteCode}')
        : '${device.siteName} (${device.siteCode ?? '-'})';
    final doorText = device.assignedDoorName ?? 'Kapi atanmamis';
    final userText = device.assignedUserCode?.toString() ?? '-';
    final dateText = device.createdAt == null
        ? '-'
        : _formatDate(device.createdAt);
    final onlineText = device.mqttConnected == null
        ? 'Bilinmiyor'
        : (device.mqttConnected! ? 'Online' : 'Offline');
    final signalText = device.wifiSignalPercent == null
        ? '-'
        : '%${device.wifiSignalPercent}'
              '${device.wifiRssi == null ? '' : ' (${device.wifiRssi} dBm)'}';
    final lastSeenText = device.lastSeenAt == null
        ? '-'
        : _formatDate(device.lastSeenAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: AppDecorations.glassCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.deviceUid,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text('Site: $siteText'),
            const SizedBox(height: 6),
            Text('Kapi: $doorText'),
            const SizedBox(height: 6),
            Text('Kullanici ID: $userText'),
            const SizedBox(height: 6),
            Text(
              'MQTT Kimligi: ${device.mqttConfigured ? 'Hazir' : 'Eksik'}',
            ),
            const SizedBox(height: 6),
            Text('Cihaz Baglantisi: $onlineText'),
            const SizedBox(height: 6),
            Text('Firmware: ${device.firmwareVersion ?? '-'}'),
            const SizedBox(height: 6),
            Text('OTA Durumu: ${device.otaStatus ?? '-'}'),
            const SizedBox(height: 6),
            Text('Wi-Fi Gucu: $signalText'),
            const SizedBox(height: 6),
            Text('Son Gorulme: $lastSeenText'),
            if ((device.mqttUsername ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('MQTT Kullanici: ${device.mqttUsername}'),
            ],
            const SizedBox(height: 6),
            Text('Kayit Tarihi: $dateText'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _editCompanyDevice(device),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Duzenle'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _assignCompanyDeviceToDoor(device),
                  icon: const Icon(Icons.meeting_room_outlined),
                  label: const Text('Kapiya Ata'),
                ),
                if (isSuperUser)
                  OutlinedButton.icon(
                    onPressed: () => _deleteCompanyDevice(device),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Sil'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothWifiScreen() {
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
                'Bluetooth ile Wi-Fi Kur',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kayitli Wi-Fi bilgisi olmayan cihazlar Bluetooth uzerinden bulunabilir olur. Bu ekrandan cihaza baglanip kullanacagi Wi-Fi adini ve sifresini gonderebilirsiniz.',
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openWifiProvisionFlow,
                  icon: const Icon(Icons.bluetooth_searching_outlined),
                  label: const Text('Bluetooth ile Wi-Fi Kurulumunu Ac'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Wi-Fi bilgisi dogruysa cihaz bilgileri kaydeder, yeniden baslar ve internete baglandiktan sonra Bluetooth kapanir. Wi-Fi degisecekse cihazdaki reset dugmesine 3 saniye basin; bilgiler silinir ve Bluetooth tekrar bulunabilir olur.',
          style: TextStyle(color: AppColors.textMuted),
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
              decoration: const InputDecoration(
                labelText: 'Telefon (opsiyonel)',
              ),
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

  Widget _buildSitesScreen() {
    final session = widget.authService.session;
    final canManageSites = session?.role == UserRole.superUser;
    final canManageApartmentUsers = session?.role == UserRole.superUser;
    final canAssignDoorDevices =
        session?.role == UserRole.superUser ||
        session?.role == UserRole.siteManager;
    final pageData = _sitesPage;
    final sites = pageData?.sites ?? const <SiteRecord>[];
    final compact = _useCompactSectionLayout(context);
    final structure = _selectedSiteStructure;
    final apartmentMode =
        _selectedMenu == SirketMenuItem.daireKullanicilariYonetimi;
    final sitesDescription = canManageSites
        ? 'Site, blok, daire, otomatik kapi yapisi ve site yoneticisini burada yonetirsiniz.'
        : 'Yetkili oldugunuz siteleri, kapi cihaz atamalarini ve cihaz durumlarini burada gorursunuz.';
    final apartmentsDescription = canManageApartmentUsers
        ? 'Bir site secin. Daire kullanicilari yalnizca secili site altinda listelenir.'
        : 'Yetkili oldugunuz sitelerin daire ve kapi yapisini gorursunuz.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apartmentMode ? 'Site Daireleri' : 'Siteler',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                      const SizedBox(height: 8),
                      Text(
                        apartmentMode ? apartmentsDescription : sitesDescription,
                    ),
                    const SizedBox(height: 12),
                    if (canManageSites) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _openSiteDialog(),
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Yeni Site'),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            apartmentMode ? 'Site Daireleri' : 'Siteler',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            apartmentMode
                                ? apartmentsDescription
                                : sitesDescription,
                          ),
                        ],
                      ),
                    ),
                    if (canManageSites) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _openSiteDialog(),
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Yeni Site'),
                      ),
                    ],
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
                          ? 'Site Listesi'
                          : 'Site Listesi (${pageData.total})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoadingSites
                        ? null
                        : () => _loadSites(force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_isLoadingSites && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (sites.isEmpty)
                const Text('Kayitli site bulunamadi.')
              else ...[
                for (final site in sites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SiteCard(
                      site: site,
                      selected: _selectedSite?.id == site.id,
                      formattedCreatedAt: _formatDate(site.createdAt),
                      deleteBusy: _busyDeleteSites.contains(site.id),
                      approvalBusy: _busySiteApprovals.contains(site.id),
                      onTap: () => _selectSite(site),
                      onEdit: canManageSites
                          ? () => _openSiteDialog(site: site)
                          : null,
                      onDelete: canManageSites ? () => _deleteSite(site) : null,
                      onApprove: canManageSites && site.approvalStatus == 'pending'
                          ? () => _resolveSiteApproval(
                              siteCode: site.id,
                              action: 'approve',
                            )
                          : null,
                      onReject: canManageSites && site.approvalStatus == 'pending'
                          ? () => _resolveSiteApproval(
                              siteCode: site.id,
                              action: 'reject',
                            )
                          : null,
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
                      OutlinedButton(
                        onPressed: pageData.page > 1
                            ? () => _loadSites(
                                force: true,
                                page: pageData.page - 1,
                              )
                            : null,
                        child: const Icon(Icons.chevron_left),
                      ),
                      OutlinedButton(
                        onPressed: pageData.page < pageData.totalPages
                            ? () => _loadSites(
                                force: true,
                                page: pageData.page + 1,
                              )
                            : null,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoadingSiteStructure && structure == null)
          const Center(child: CircularProgressIndicator())
        else if (structure != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard,
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        structure.site.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Site Kodu: ${structure.site.id}'),
                      Text('MQTT Site ID: ${structure.site.mqttSiteId}'),
                      Text('Blok: ${structure.site.blockCount}'),
                      Text('Daire: ${structure.site.apartmentCount}'),
                      Text('Kapi: ${structure.site.doorCount}'),
                      if ((structure.site.managerName ?? '').isNotEmpty)
                        Text(
                          'Yonetici: ${structure.site.managerName} (${structure.site.managerUserCode ?? '-'})',
                        ),
                      if ((structure.site.address ?? '').isNotEmpty)
                        Text('Adres: ${structure.site.address}'),
                      const SizedBox(height: 12),
                      if (canManageSites) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openSiteDialog(site: structure.site),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Siteyi Duzenle'),
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              structure.site.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                Text('Site Kodu: ${structure.site.id}'),
                                Text(
                                  'MQTT Site ID: ${structure.site.mqttSiteId}',
                                ),
                                Text('Blok: ${structure.site.blockCount}'),
                                Text('Daire: ${structure.site.apartmentCount}'),
                                Text('Kapi: ${structure.site.doorCount}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if ((structure.site.managerName ?? '').isNotEmpty)
                              Text(
                                'Yonetici: ${structure.site.managerName} (${structure.site.managerUserCode ?? '-'})',
                              ),
                            if ((structure.site.address ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Adres: ${structure.site.address}'),
                              ),
                          ],
                        ),
                      ),
                      if (canManageSites) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openSiteDialog(site: structure.site),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Siteyi Duzenle'),
                        ),
                      ],
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
                const Text(
                  'Daireler',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                if (structure.apartments.isEmpty)
                  const Text('Bu site icin daire kaydi bulunamadi.')
                else
                  for (final apartment in structure.apartments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ApartmentCard(
                        apartment: apartment,
                        busy: _busyApartments.contains(apartment.id),
                        onTap: canManageApartmentUsers
                            ? () => _openApartmentResidentDialog(apartment)
                            : null,
                        onSendCredentials:
                            !canManageApartmentUsers || apartment.residentEmail == null
                            ? null
                            : () => _sendApartmentCredentials(apartment),
                      ),
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
                const Text(
                  'Kapilar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                if (structure.doors.isEmpty)
                  const Text('Bu site icin kapi kaydi bulunamadi.')
                else
                  for (final door in structure.doors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DoorCard(
                        door: door,
                        busy: _busyDoors.contains(door.id),
                        onAssign: canAssignDoorDevices
                            ? () => _assignDoorDevice(door)
                            : null,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubscriptionRequestsScreen() {
    final pageData = _subscriptionRequestsPage;
    final requests = pageData?.requests ?? const <SubscriptionRequest>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yeni Abonelik Talepleri',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Mail dogrulamasini tamamlayan site yoneticileri burada onay bekler.',
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
                          ? 'Bekleyen Talepler'
                          : 'Bekleyen Talepler (${pageData.total})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoadingSubscriptionRequests
                        ? null
                        : () => _loadSubscriptionRequests(force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_isLoadingSubscriptionRequests && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (requests.isEmpty)
                const Text('Dogrulanmis yeni abonelik talebi yok.')
              else ...[
                for (final request in requests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SubscriptionRequestCard(
                      request: request,
                      busy: _busySubscriptionRequests.contains(request.id),
                      formattedCreatedAt: _formatDate(request.createdAt),
                      onApprove: () => _resolveSubscriptionRequest(
                        userCode: request.id,
                        action: 'approve',
                      ),
                      onReject: () => _resolveSubscriptionRequest(
                        userCode: request.id,
                        action: 'reject',
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Sayfa ${pageData?.page ?? 1} / ${pageData?.totalPages ?? 1} | Toplam ${pageData?.total ?? 0}',
                    ),
                    OutlinedButton(
                      onPressed: (pageData?.page ?? 1) > 1
                          ? () => _loadSubscriptionRequests(
                              force: true,
                              page: (pageData?.page ?? 1) - 1,
                            )
                          : null,
                      child: const Icon(Icons.chevron_left),
                    ),
                    OutlinedButton(
                      onPressed:
                          (pageData?.page ?? 1) < (pageData?.totalPages ?? 1)
                          ? () => _loadSubscriptionRequests(
                              force: true,
                              page: (pageData?.page ?? 1) + 1,
                            )
                          : null,
                      child: const Icon(Icons.chevron_right),
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

  Widget _buildPendingSiteApprovalsScreen() {
    final pageData = _pendingSiteApprovalsPage;
    final sites = pageData?.sites ?? const <SiteRecord>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Site Onay Talepleri',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Site yoneticilerinin olusturdugu siteler burada sirket onayi bekler.',
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
                          ? 'Bekleyen Siteler'
                          : 'Bekleyen Siteler (${pageData.total})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoadingPendingSiteApprovals
                        ? null
                        : () => _loadPendingSiteApprovals(force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_isLoadingPendingSiteApprovals && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (sites.isEmpty)
                const Text('Bekleyen site onay talebi yok.')
              else ...[
                for (final site in sites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SiteApprovalRequestCard(
                      site: site,
                      busy: _busySiteApprovals.contains(site.id),
                      formattedCreatedAt: _formatDate(site.createdAt),
                      onApprove: () => _resolveSiteApproval(
                        siteCode: site.id,
                        action: 'approve',
                      ),
                      onReject: () => _resolveSiteApproval(
                        siteCode: site.id,
                        action: 'reject',
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Sayfa ${pageData?.page ?? 1} / ${pageData?.totalPages ?? 1} | Toplam ${pageData?.total ?? 0}',
                    ),
                    OutlinedButton(
                      onPressed: (pageData?.page ?? 1) > 1
                          ? () => _loadPendingSiteApprovals(
                              force: true,
                              page: (pageData?.page ?? 1) - 1,
                            )
                          : null,
                      child: const Icon(Icons.chevron_left),
                    ),
                    OutlinedButton(
                      onPressed:
                          (pageData?.page ?? 1) < (pageData?.totalPages ?? 1)
                          ? () => _loadPendingSiteApprovals(
                              force: true,
                              page: (pageData?.page ?? 1) + 1,
                            )
                          : null,
                      child: const Icon(Icons.chevron_right),
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

  Widget _buildManagedRoleScreen(UserRole role, UserSession session) {
    final pageData = _managedPages[role];
    final users = pageData?.users ?? const <ManagedUserAccount>[];
    final loading = _loadingRoles.contains(role);
    final compact = _useCompactSectionLayout(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: compact
              ? Column(
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openManagedUserDialog(role: role),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text('Yeni ${_roleTitle(role)}'),
                      ),
                    ),
                  ],
                )
              : Row(
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
                      onActivationChanged: (value) => _toggleUserActivation(
                        role: role,
                        user: user,
                        value: value,
                      ),
                      onTap: () => _showManagedUserDetails(
                        role: role,
                        user: user,
                        session: session,
                      ),
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
                      OutlinedButton(
                        onPressed: pageData.page > 1
                            ? () => _loadManagedUsers(
                                role,
                                force: true,
                                page: pageData.page - 1,
                              )
                            : null,
                        child: const Icon(Icons.chevron_left),
                      ),
                      OutlinedButton(
                        onPressed: pageData.page < pageData.totalPages
                            ? () => _loadManagedUsers(
                                role,
                                force: true,
                                page: pageData.page + 1,
                              )
                            : null,
                        child: const Icon(Icons.chevron_right),
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
    if (!_canAccessMenu(_selectedMenu, session.role)) {
      _selectedMenu = SirketMenuItem.dashboard;
    }

    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
        return _buildDashboard(session);
      case SirketMenuItem.profilim:
        return _buildProfile(session);
      case SirketMenuItem.abonelikTalepleri:
        return _buildSubscriptionRequestsScreen();
      case SirketMenuItem.siteOnayTalepleri:
        return _buildPendingSiteApprovalsScreen();
      case SirketMenuItem.superUserYonetimi:
        return _buildManagedRoleScreen(UserRole.superUser, session);
      case SirketMenuItem.siteYoneticileriYonetimi:
        return _buildManagedRoleScreen(UserRole.siteManager, session);
      case SirketMenuItem.daireKullanicilariYonetimi:
        return _buildSitesScreen();
      case SirketMenuItem.siteler:
        return _buildSitesScreen();
      case SirketMenuItem.cihazEkle:
        return _buildDeviceAddScreen();
      case SirketMenuItem.kayitliCihazlar:
        return _buildCompanyDevicesScreen();
      case SirketMenuItem.bluetoothWifiKur:
        return _buildBluetoothWifiScreen();
      case SirketMenuItem.ellerSerbest:
        return _buildDashboard(session);
    }
  }

  Future<void> _logout() async {
    await widget.authService.logout();
  }

  void _openVoiceControlModal() {
    if (widget.voiceDoorService == null) {
      return;
    }
    List<DoorRecord>? candidateDoors;
    if (_doorControlStructure?.doors.isNotEmpty == true) {
      candidateDoors = _doorControlStructure!.doors;
    } else if (_selectedSiteStructure?.doors.isNotEmpty == true) {
      candidateDoors = _selectedSiteStructure!.doors;
    }
    VoiceControlModal.show(
      context,
      voiceService: widget.voiceDoorService!,
      candidateDoors: candidateDoors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.authService.session!;
    final roleColor = session.role.accentColor;
    return Theme(
      data: _themeForRole(context, session.role),
      child: Scaffold(
        backgroundColor: session.role.surfaceColor,
        appBar: AppBar(
          title: Text(_titleForMenu(_selectedMenu)),
          backgroundColor: roleColor,
          actions: [
            IconButton(
              tooltip: 'Cikis yap',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ),
        drawer: YanMenu(
          fullName: session.fullName,
          userEmail: session.email,
          role: session.role,
          selectedItem: _selectedMenu,
          onSelect: _selectMenu,
          onLogout: () {
            Navigator.pop(context);
            _logout();
          },
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth < 600 ? 16.0 : 20.0;
              return SingleChildScrollView(
                padding: EdgeInsets.all(horizontalPadding),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: _buildContent(session),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeviceActionTile extends StatelessWidget {
  const _DeviceActionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.glassCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 30),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagedUserCard extends StatefulWidget {
  const _ManagedUserCard({
    required this.user,
    required this.isSelf,
    required this.activationBusy,
    required this.onTap,
    required this.onActivationChanged,
  });

  final ManagedUserAccount user;
  final bool isSelf;
  final bool activationBusy;
  final VoidCallback onTap;
  final ValueChanged<bool> onActivationChanged;

  @override
  State<_ManagedUserCard> createState() => _ManagedUserCardState();
}

class _ManagedUserCardState extends State<_ManagedUserCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: user.isActive
                  ? AppColors.primarySoft.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      user.fullName.trim().isEmpty
                          ? '?'
                          : user.fullName.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.role.label,
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
                  const SizedBox(width: 8),
                  widget.activationBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch.adaptive(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          value: user.isActive,
                          activeTrackColor: AppColors.primary,
                          onChanged:
                              widget.isSelf ? null : widget.onActivationChanged,
                        ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Kod: ${user.id}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textDark,
                      ),
                    ),
                    if ((user.loginName ?? '').isNotEmpty)
                      Text(
                        'Kullanıcı: ${user.loginName}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                    Text(
                      'E-posta: ${user.email}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textDark,
                      ),
                    ),
                    if ((user.phoneNumber ?? '').isNotEmpty)
                      Text(
                        'Telefon: ${user.phoneNumber}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: widget.onTap,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Düzenle'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteCard extends StatefulWidget {
  const _SiteCard({
    required this.site,
    required this.selected,
    required this.formattedCreatedAt,
    required this.deleteBusy,
    required this.approvalBusy,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onApprove,
    this.onReject,
  });

  final SiteRecord site;
  final bool selected;
  final String formattedCreatedAt;
  final bool deleteBusy;
  final bool approvalBusy;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  State<_SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<_SiteCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _SiteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final approvalColor = switch (site.approvalStatus) {
      'pending' => Colors.orange.shade700,
      'rejected' => Colors.red.shade700,
      _ => Colors.green.shade700,
    };
    final hasManager = (site.managerName ?? '').trim().isNotEmpty;
    final isSelected = widget.selected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() => _expanded = !_expanded);
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.primarySoft.withValues(alpha: 0.25),
              width: isSelected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.shadowDark
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: isSelected ? 14 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ana Başlık Satırı (Kompakt: Sadece Site İsmi & Varsa Yönetici)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasManager
                              ? 'Yönetici: ${site.managerName}'
                              : 'Yönetici atanmamış',
                          style: TextStyle(
                            color: hasManager
                                ? AppColors.textMuted
                                : Colors.orange.shade800,
                            fontSize: 12.5,
                            fontWeight: hasManager
                                ? FontWeight.normal
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (site.approvalStatus == 'pending')
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: approvalColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Onay Bekliyor',
                        style: TextStyle(
                          color: approvalColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),

              // Tıklanınca Açılan Ayrıntılar
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text('ID: ${site.id}', style: const TextStyle(fontSize: 12.5)),
                    Text(
                      'MQTT Site ID: ${site.mqttSiteId}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'Blok: ${site.blockCount}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'Daire: ${site.apartmentCount}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'Kapı: ${site.doorCount}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
                if (site.managerUserCode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Yönetici Kodu: ${site.managerUserCode}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if (site.address != null && site.address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Adres: ${site.address}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if ((site.city ?? '').isNotEmpty ||
                    (site.district ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Konum: ${site.city ?? '-'} / ${site.district ?? '-'}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Kayıt Tarihi: ${widget.formattedCreatedAt}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                if (site.approvalStatus == 'pending' &&
                    (widget.onApprove != null || widget.onReject != null)) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: widget.approvalBusy ? null : widget.onApprove,
                        icon: widget.approvalBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Onayla'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.approvalBusy ? null : widget.onReject,
                        icon: const Icon(Icons.block_outlined, size: 18),
                        label: const Text('Reddet'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.onEdit != null || widget.onDelete != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.onEdit != null)
                        OutlinedButton.icon(
                          onPressed: widget.onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Düzenle'),
                        ),
                      if (widget.onDelete != null)
                        ElevatedButton.icon(
                          onPressed: widget.deleteBusy ? null : widget.onDelete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                          ),
                          icon: widget.deleteBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Sil'),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ApartmentCard extends StatefulWidget {
  const _ApartmentCard({
    required this.apartment,
    required this.busy,
    required this.onTap,
    required this.onSendCredentials,
  });

  final ApartmentRecord apartment;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onSendCredentials;

  @override
  State<_ApartmentCard> createState() => _ApartmentCardState();
}

class _ApartmentCardState extends State<_ApartmentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final apartment = widget.apartment;
    final hasResident = (apartment.residentFullName ?? '').trim().isNotEmpty;
    final active = apartment.residentIsActive ?? apartment.isActive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasResident
                  ? AppColors.primarySoft.withValues(alpha: 0.3)
                  : Colors.orange.shade200,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: hasResident
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.home_outlined,
                      color: hasResident
                          ? AppColors.primary
                          : Colors.orange.shade800,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          apartment.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasResident
                              ? 'Sakin: ${apartment.residentFullName}'
                              : 'Daire Boş / Sakin Yok',
                          style: TextStyle(
                            color: hasResident
                                ? AppColors.textMuted
                                : Colors.orange.shade800,
                            fontSize: 12,
                            fontWeight: hasResident
                                ? FontWeight.normal
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      active ? 'Aktif' : 'Pasif',
                      style: TextStyle(
                        color: active
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if ((apartment.residentLoginName ?? '').isNotEmpty)
                      Text(
                        'Kullanıcı Adı: ${apartment.residentLoginName}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                    if ((apartment.residentPinCode ?? '').isNotEmpty)
                      Text(
                        'PIN Kodu: ${apartment.residentPinCode}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                    if ((apartment.residentEmail ?? '').isNotEmpty)
                      Text(
                        'E-posta: ${apartment.residentEmail}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                    if ((apartment.residentPhoneNumber ?? '').isNotEmpty)
                      Text(
                        'Telefon: ${apartment.residentPhoneNumber}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.onSendCredentials != null && hasResident)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                        onPressed: widget.busy ? null : widget.onSendCredentials,
                        icon: const Icon(Icons.mail_outline, size: 16),
                        label: const Text('Mail Gönder'),
                      ),
                    if (widget.onTap != null) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                        onPressed: widget.busy ? null : widget.onTap,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(hasResident ? 'Düzenle' : 'Sakin Ata'),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DoorCard extends StatefulWidget {
  const _DoorCard({
    required this.door,
    required this.busy,
    required this.onAssign,
  });

  final DoorRecord door;
  final bool busy;
  final VoidCallback? onAssign;

  @override
  State<_DoorCard> createState() => _DoorCardState();
}

class _DoorCardState extends State<_DoorCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final door = widget.door;
    final hasDevice = door.assignedDeviceUid != null &&
        door.assignedDeviceUid!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasDevice
                  ? AppColors.primarySoft.withValues(alpha: 0.3)
                  : Colors.orange.shade200,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.door_front_door_outlined,
                    color: hasDevice ? AppColors.primary : Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      door.doorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: hasDevice
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasDevice ? 'Cihaz Atandı' : 'Cihaz Yok',
                      style: TextStyle(
                        color: hasDevice
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cihaz UID: ${door.assignedDeviceUid ?? 'Atanmadı'}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Kapı İndeksi: ${door.doorIndex}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (widget.onAssign != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: widget.onAssign,
                        icon: const Icon(
                          Icons.qr_code_scanner_outlined,
                          size: 16,
                        ),
                        label: Text(
                          hasDevice ? 'Cihaz Değiştir' : 'Cihaz Ata',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteApprovalRequestCard extends StatelessWidget {
  const _SiteApprovalRequestCard({
    required this.site,
    required this.busy,
    required this.formattedCreatedAt,
    required this.onApprove,
    required this.onReject,
  });

  final SiteRecord site;
  final bool busy;
  final String formattedCreatedAt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.infoCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  site.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text('ID: ${site.id}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${site.blockCount} blok, ${site.apartmentCount} daire, ${site.doorCount} kapi',
          ),
          if ((site.managerName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Yonetici: ${site.managerName} (${site.managerUserCode ?? '-'})',
            ),
          ],
          if ((site.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(site.address!),
          ],
          if ((site.city ?? '').isNotEmpty || (site.district ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${site.city ?? '-'} / ${site.district ?? '-'}'),
            ),
          const SizedBox(height: 6),
          Text('Olusturma Tarihi: $formattedCreatedAt'),
          const SizedBox(height: 12),
          busy
              ? const Center(child: CircularProgressIndicator())
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Onayla'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.block_outlined, size: 18),
                      label: const Text('Reddet'),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _SubscriptionRequestCard extends StatelessWidget {
  const _SubscriptionRequestCard({
    required this.request,
    required this.busy,
    required this.formattedCreatedAt,
    required this.onApprove,
    required this.onReject,
  });

  final SubscriptionRequest request;
  final bool busy;
  final String formattedCreatedAt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.infoCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.fullName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(request.email),
          const SizedBox(height: 4),
          Text('Kod: ${request.id}'),
          if (request.phoneNumber != null &&
              request.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Telefon: ${request.phoneNumber}'),
          ],
          const SizedBox(height: 4),
          Text('Talep Tarihi: $formattedCreatedAt'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reddet'),
              ),
              ElevatedButton.icon(
                onPressed: busy ? null : onApprove,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Onayla'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({
    required this.authService,
    required this.site,
    this.structure,
  });

  final AuthService authService;
  final SiteRecord? site;
  final SiteStructureRecord? structure;

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _districtController;
  late final TextEditingController _blockCountController;
  late final TextEditingController _doorCountController;
  late final TextEditingController _managerFullNameController;
  late final TextEditingController _managerEmailController;
  late final TextEditingController _managerPhoneController;
  late final TextEditingController _managerPasswordController;
  final List<TextEditingController> _blockApartmentControllers =
      <TextEditingController>[];
  late bool _createNewManager;
  List<ManagedUserAccount> _siteManagers = <ManagedUserAccount>[];
  bool _isLoadingManagers = true;
  int? _selectedManagerUserCode;
  ManagedUserAccount? _selectedManager;

  bool get _isEditing => widget.site != null;

  @override
  void initState() {
    super.initState();
    final initialBlockApartmentCounts = _siteBlockApartmentCounts(
      site: widget.site,
      structure: widget.structure,
    );
    _nameController = TextEditingController(text: widget.site?.name ?? '');
    _addressController = TextEditingController(
      text: widget.site?.address ?? '',
    );
    _cityController = TextEditingController(text: widget.site?.city ?? '');
    _districtController = TextEditingController(
      text: widget.site?.district ?? '',
    );
    _blockCountController = TextEditingController(
      text: '${initialBlockApartmentCounts.length}',
    );
    _doorCountController = TextEditingController(
      text: '${widget.site?.doorCount ?? 1}',
    );
    _selectedManagerUserCode = widget.site?.managerUserCode;
    _managerFullNameController = TextEditingController();
    _managerEmailController = TextEditingController();
    _managerPhoneController = TextEditingController();
    _managerPasswordController = TextEditingController();
    _createNewManager = false;
    _syncBlockApartmentControllers(
      initialBlockApartmentCounts.length,
      seedCounts: initialBlockApartmentCounts,
    );
    _blockCountController.addListener(_handleBlockCountChanged);
    _loadManagers();
  }

  Future<void> _loadManagers() async {
    try {
      final page = await widget.authService.listManagedUsers(
        role: UserRole.siteManager,
        page: 1,
        pageSize: 20,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _siteManagers = page.users;
        for (final manager in page.users) {
          if (manager.id == _selectedManagerUserCode) {
            _selectedManager = manager;
            break;
          }
        }
        _isLoadingManagers = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingManagers = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _blockCountController.removeListener(_handleBlockCountChanged);
    _blockCountController.dispose();
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

  void _handleBlockCountChanged() {
    final blockCount = int.tryParse(_blockCountController.text.trim());
    if (blockCount == null ||
        blockCount <= 0 ||
        blockCount == _blockApartmentControllers.length) {
      return;
    }
    setState(() {
      _syncBlockApartmentControllers(blockCount);
    });
  }

  void _syncBlockApartmentControllers(
    int targetCount, {
    List<int>? seedCounts,
  }) {
    final counts =
        seedCounts ??
        _blockApartmentControllers
            .map((controller) => int.tryParse(controller.text.trim()) ?? 1)
            .toList();

    while (_blockApartmentControllers.length < targetCount) {
      _blockApartmentControllers.add(TextEditingController());
    }
    while (_blockApartmentControllers.length > targetCount) {
      _blockApartmentControllers.removeLast().dispose();
    }

    for (var index = 0; index < _blockApartmentControllers.length; index += 1) {
      final value = index < counts.length ? counts[index] : 1;
      _blockApartmentControllers[index].text = '$value';
    }
  }

  List<int> get _blockApartmentCounts => _blockApartmentControllers
      .map((controller) => int.tryParse(controller.text.trim()) ?? 0)
      .toList();

  String get _selectedManagerTitle {
    if (_selectedManagerUserCode == null) {
      return 'Yonetici atanmamis';
    }
    return _selectedManager?.fullName ??
        widget.site?.managerName ??
        'Mevcut yonetici';
  }

  String get _selectedManagerSubtitle {
    if (_selectedManagerUserCode == null) {
      return 'Bu siteye henuz site yoneticisi bagli degil.';
    }
    final manager = _selectedManager;
    if (manager != null) {
      return '${manager.email} - Kod: ${manager.id}';
    }
    return 'Kod: $_selectedManagerUserCode';
  }

  Future<void> _selectExistingManager() async {
    final result = await Navigator.of(context).push<_SiteManagerPickerResult>(
      MaterialPageRoute(
        builder: (_) => _SiteManagerPickerPage(
          authService: widget.authService,
          selectedUserCode: _selectedManagerUserCode,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _selectedManagerUserCode = result.manager?.id;
      _selectedManager = result.manager;
      if (result.manager != null &&
          !_siteManagers.any((manager) => manager.id == result.manager!.id)) {
        _siteManagers = <ManagedUserAccount>[result.manager!, ..._siteManagers];
      }
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _SiteFormResult(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
        blockApartmentCounts: _blockApartmentCounts,
        doorCount: int.parse(_doorCountController.text.trim()),
        managerUserCode: _createNewManager ? null : _selectedManagerUserCode,
        managerUser: _createNewManager
            ? {
                'full_name': _managerFullNameController.text.trim(),
                'email': _managerEmailController.text.trim().toLowerCase(),
                'phone_number': _managerPhoneController.text.trim(),
                'password': _managerPasswordController.text.trim(),
                'is_active': true,
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalApartments = _blockApartmentCounts.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(_isEditing ? 'Site Duzenle' : 'Yeni Site Ekle'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Site Adi'),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'Site adi en az 2 karakter olmali.'
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
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'Il (opsiyonel)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(
                    labelText: 'Ilce (opsiyonel)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _blockCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Blok Sayisi'),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    return parsed == null || parsed <= 0
                        ? 'Blok sayisi pozitif tamsayi olmali.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFB8D7F7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Blok Daire Dagilimi',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (
                        var index = 0;
                        index < _blockApartmentControllers.length;
                        index += 1
                      ) ...[
                        Text(
                          _blockLabelFromIndex(index),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _blockApartmentControllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Daire Sayisi',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse((value ?? '').trim());
                            return parsed == null || parsed <= 0
                                ? 'Her blokta en az 1 daire olmali.'
                                : null;
                          },
                        ),
                        if (index != _blockApartmentControllers.length - 1)
                          const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Toplam Daire: $totalApartments',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _doorCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Otomatik Kapi Sayisi',
                  ),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    return parsed == null || parsed <= 0
                        ? 'Kapi sayisi pozitif tamsayi olmali.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
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
                            'Site Yoneticisi',
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
                              label: Text('Listeden Sec'),
                              icon: Icon(Icons.people_outline, size: 16),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Yeni Olustur'),
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
                                Text('Yoneticiler yukleniyor...'),
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
                                            _selectedManagerTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectedManagerSubtitle,
                                            maxLines: 2,
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
                                      ? 'Site Yoneticisi Sec'
                                      : 'Site Yoneticisini Degistir',
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
                                  label: const Text('Yonetici atamasini kaldir'),
                                ),
                            ],
                          ),
                        if (!_isLoadingManagers && _siteManagers.isEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Kayitli site yoneticisi bulunamadi. Bu ekranda "Yeni Olustur" secenegiyle yeni yonetici acabilirsiniz.',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ],
                      ] else ...[
                        TextFormField(
                          controller: _managerFullNameController,
                          decoration: const InputDecoration(
                            labelText: 'Site Yoneticisi Ad Soyad',
                          ),
                          validator: (value) => (value ?? '').trim().length < 3
                              ? 'Ad Soyad en az 3 karakter olmali.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _managerEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Site Yoneticisi E-posta',
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            return text.isEmpty || !text.contains('@')
                                ? 'Gecerli bir e-posta girin.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _managerPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Site Yoneticisi Telefon (opsiyonel)',
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
                          controller: _managerPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Site Yoneticisi Sifre',
                          ),
                          validator: (value) => (value ?? '').trim().length < 6
                              ? 'Sifre en az 6 karakter olmali.'
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
          child: const Text('Iptal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

class _SiteManagerPickerResult {
  const _SiteManagerPickerResult({required this.manager});

  final ManagedUserAccount? manager;
}

class _SiteManagerPickerPage extends StatefulWidget {
  const _SiteManagerPickerPage({
    required this.authService,
    required this.selectedUserCode,
  });

  final AuthService authService;
  final int? selectedUserCode;

  @override
  State<_SiteManagerPickerPage> createState() => _SiteManagerPickerPageState();
}

class _SiteManagerPickerPageState extends State<_SiteManagerPickerPage> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  List<ManagedUserAccount> _managers = <ManagedUserAccount>[];
  int _page = 1;
  int _total = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  bool get _hasMore => _managers.length < _total;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadManagers(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadManagers(reset: true);
    });
  }

  void _handleScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 180) {
      _loadManagers();
    }
  }

  Future<void> _loadManagers({bool reset = false}) async {
    if (_isLoading || _isLoadingMore) {
      return;
    }
    final nextPage = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _isLoading = true;
        _error = null;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final result = await widget.authService.listManagedUsers(
        role: UserRole.siteManager,
        page: nextPage,
        pageSize: _pageSize,
        search: _searchController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _page = result.page;
        _total = result.total;
        _managers = reset
            ? result.users
            : <ManagedUserAccount>[..._managers, ...result.users];
        _isLoading = false;
        _isLoadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Site yoneticileri alinamadi.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _select(ManagedUserAccount? manager) {
    Navigator.of(context).pop(_SiteManagerPickerResult(manager: manager));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Site Yoneticisi Sec')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Ad, e-posta veya kod ile ara',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayi temizle',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            _loadManagers(reset: true);
                          },
                        ),
                ),
                onChanged: _handleSearchChanged,
                onSubmitted: (_) => _loadManagers(reset: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () => _select(null),
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('Yonetici atamadan devam et'),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadManagers(reset: true),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildManagerList(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagerList(Color accent) {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _loadManagers(reset: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ],
      );
    }

    if (_managers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [Text('Eslesen site yoneticisi bulunamadi.')],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _managers.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _managers.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final manager = _managers[index];
        final selected = manager.id == widget.selectedUserCode;
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? accent : const Color(0xFFD6E8F8),
            ),
          ),
          tileColor: selected ? accent.withValues(alpha: 0.08) : Colors.white,
          leading: CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.12),
            foregroundColor: accent,
            child: Text(
              manager.fullName.isEmpty ? '?' : manager.fullName[0].toUpperCase(),
            ),
          ),
          title: Text(
            manager.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${manager.email}\nKod: ${manager.id}${manager.isActive ? '' : ' - Pasif'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: selected
              ? Icon(Icons.check_circle, color: accent)
              : const Icon(Icons.chevron_right),
          onTap: () => _select(manager),
        );
      },
    );
  }
}

class _DeviceDialog extends StatefulWidget {
  const _DeviceDialog({required this.initialDeviceUid});

  final String initialDeviceUid;

  @override
  State<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<_DeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceUidController;
  final _assignedUserCodeController = TextEditingController();
  final _siteCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deviceUidController = TextEditingController(text: widget.initialDeviceUid);
  }

  @override
  void dispose() {
    _deviceUidController.dispose();
    _assignedUserCodeController.dispose();
    _siteCodeController.dispose();
    super.dispose();
  }

  int? _parseOptionalInt(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _DeviceFormResult(
        deviceUid: _deviceUidController.text.trim().toUpperCase(),
        assignedUserCode: _parseOptionalInt(_assignedUserCodeController.text),
        siteCode: _parseOptionalInt(_siteCodeController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Sirket Veritabani Cihaz Kaydi'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _deviceUidController,
                  decoration: const InputDecoration(
                    labelText: 'Cihaz Unique ID',
                    hintText: 'Ornek: 1CDA72A172E0',
                    helperText:
                        'Bu Unique ID sirket veritabanina kaydedilecek.',
                  ),
                  validator: (value) => (value ?? '').trim().length < 6
                      ? 'Cihaz unique id en az 6 karakter olmali.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _assignedUserCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kullanici ID (opsiyonel)',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return null;
                    }
                    return int.tryParse(text) == null
                        ? 'Kullanici ID sayisal olmali.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _siteCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Site ID (opsiyonel)',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return null;
                    }
                    return int.tryParse(text) == null
                        ? 'Site ID sayisal olmali.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kullanici ID ve Site ID alanlarini bos birakabilirsiniz.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
        ElevatedButton(onPressed: _submit, child: const Text('Cihazi Kaydet')),
      ],
    );
  }
}

class _ApartmentResidentDialog extends StatefulWidget {
  const _ApartmentResidentDialog({required this.apartment});

  final ApartmentRecord apartment;

  @override
  State<_ApartmentResidentDialog> createState() =>
      _ApartmentResidentDialogState();
}

class _ApartmentResidentDialogState extends State<_ApartmentResidentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _loginNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.apartment.residentFullName ?? '',
    );
    _loginNameController = TextEditingController(
      text: widget.apartment.residentLoginName ?? '',
    );
    _emailController = TextEditingController(
      text: widget.apartment.residentEmail ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.apartment.residentPinCode ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.apartment.residentPhoneNumber ?? '',
    );
    _isActive = widget.apartment.residentIsActive ?? widget.apartment.isActive;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _loginNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _ApartmentResidentFormResult(
        fullName: _fullNameController.text.trim(),
        loginName: _loginNameController.text.trim().toLowerCase(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('Daire Kullanici Ayari - ${widget.apartment.label}'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
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
                  controller: _loginNameController,
                  decoration: const InputDecoration(labelText: 'Kullanici Adi'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.length < 3) {
                      return 'Kullanici adi en az 3 karakter olmali.';
                    }
                    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)
                        ? null
                        : 'Sadece harf, rakam, nokta, alt cizgi ve tire kullanin.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Daire Sakini E-postasi',
                    helperText: 'Mail gonderimi icin opsiyonel.',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return null;
                    }
                    return text.contains('@') ? null : 'Gecerli e-posta girin.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Sifre'),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      RegExp(r'^\d{4}$').hasMatch((value ?? '').trim())
                      ? null
                      : 'PIN 4 haneli sayisal olmali.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      final randomPin = (1000 + (math.Random().nextInt(9000)))
                          .toString();
                      _passwordController.text = randomPin;
                    },
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('Rastgele PIN'),
                  ),
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
                SwitchListTile.adaptive(
                  value: _isActive,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: Text(
                    _isActive
                        ? 'Daire kullanicisi giris yapabilir.'
                        : 'Daire kullanicisi askida kalir.',
                  ),
                  onChanged: (value) => setState(() => _isActive = value),
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
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

class _DoorDeviceDialog extends StatefulWidget {
  const _DoorDeviceDialog({required this.door, required this.initialDeviceUid});

  final DoorRecord door;
  final String initialDeviceUid;

  @override
  State<_DoorDeviceDialog> createState() => _DoorDeviceDialogState();
}

class _DoorDeviceDialogState extends State<_DoorDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceUidController;

  @override
  void initState() {
    super.initState();
    _deviceUidController = TextEditingController(text: widget.initialDeviceUid);
  }

  @override
  void dispose() {
    _deviceUidController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _DoorDeviceAssignResult(
        deviceUid: _deviceUidController.text.trim().toUpperCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.door.doorName} - Cihaz Ata'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _deviceUidController,
                  decoration: const InputDecoration(labelText: 'Cihaz Unique ID'),
                  validator: (value) => (value ?? '').trim().length < 6
                      ? 'Cihaz unique id en az 6 karakter olmali.'
                      : null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mevcut cihaz: ${widget.door.assignedDeviceUid ?? 'Atanmadi'}',
                    style: const TextStyle(
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
        ElevatedButton(onPressed: _submit, child: const Text('Ata')),
      ],
    );
  }
}

class _DeviceEditDialog extends StatefulWidget {
  const _DeviceEditDialog({
    required this.device,
    required this.isSuperUser,
  });

  final DeviceRecord device;
  final bool isSuperUser;

  @override
  State<_DeviceEditDialog> createState() => _DeviceEditDialogState();
}

class _DeviceEditDialogState extends State<_DeviceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _assignedUserCodeController;
  late final TextEditingController _siteCodeController;
  late final TextEditingController _gateNameController;

  @override
  void initState() {
    super.initState();
    _assignedUserCodeController = TextEditingController(
      text: widget.device.assignedUserCode?.toString() ?? '',
    );
    _siteCodeController = TextEditingController(
      text: widget.device.siteCode?.toString() ?? '',
    );
    _gateNameController = TextEditingController(
      text: widget.device.gateName ?? '',
    );
  }

  @override
  void dispose() {
    _assignedUserCodeController.dispose();
    _siteCodeController.dispose();
    _gateNameController.dispose();
    super.dispose();
  }

  int? _parseOptionalInt(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text);
  }

  String? _validateOptionalInt(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text) == null ? '$label sayisal olmali.' : null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _DeviceEditResult(
        assignedUserCode: widget.isSuperUser
            ? _parseOptionalInt(_assignedUserCodeController.text)
            : widget.device.assignedUserCode,
        siteCode: _parseOptionalInt(_siteCodeController.text),
        gateName: _gateNameController.text.trim().isEmpty
            ? null
            : _gateNameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.device.deviceUid} - Duzenle'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isSuperUser) ...[
                  TextFormField(
                    controller: _assignedUserCodeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kullanici ID (opsiyonel)',
                    ),
                    validator: (value) =>
                        _validateOptionalInt(value, 'Kullanici ID'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _siteCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Site ID (opsiyonel)',
                  ),
                  validator: (value) => _validateOptionalInt(value, 'Site ID'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gateNameController,
                  decoration: const InputDecoration(
                    labelText: 'Kapi Etiketi (opsiyonel)',
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
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

class _DeviceDoorAssignDialog extends StatefulWidget {
  const _DeviceDoorAssignDialog({
    required this.authService,
    required this.sites,
    required this.device,
  });

  final AuthService authService;
  final List<SiteRecord> sites;
  final DeviceRecord device;

  @override
  State<_DeviceDoorAssignDialog> createState() =>
      _DeviceDoorAssignDialogState();
}

class _DeviceDoorAssignDialogState extends State<_DeviceDoorAssignDialog> {
  SiteRecord? _selectedSite;
  SiteStructureRecord? _structure;
  DoorRecord? _selectedDoor;
  bool _loadingDoors = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedSite = widget.sites.isEmpty ? null : widget.sites.first;
    if (_selectedSite != null) {
      _loadDoors(_selectedSite!.id);
    }
  }

  Future<void> _loadDoors(int siteCode) async {
    setState(() {
      _loadingDoors = true;
      _structure = null;
      _selectedDoor = null;
      _error = null;
    });
    final (structure, error) = await widget.authService.getSiteStructure(
      siteCode: siteCode,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingDoors = false;
      _structure = structure;
      _selectedDoor = structure?.doors.isEmpty ?? true
          ? null
          : structure!.doors.first;
      _error = error;
    });
  }

  void _submit() {
    final door = _selectedDoor;
    if (door == null) {
      return;
    }
    Navigator.of(context).pop(door);
  }

  @override
  Widget build(BuildContext context) {
    final doors = _structure?.doors ?? const <DoorRecord>[];
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.device.deviceUid} - Kapiya Ata'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selectedSite?.id,
                decoration: const InputDecoration(labelText: 'Site'),
                items: [
                  for (final site in widget.sites)
                    DropdownMenuItem<int>(
                      value: site.id,
                      child: Text('${site.name} (${site.id})'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  final site = widget.sites.firstWhere((item) => item.id == value);
                  setState(() => _selectedSite = site);
                  _loadDoors(site.id);
                },
              ),
              const SizedBox(height: 12),
              if (_loadingDoors)
                const LinearProgressIndicator()
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<int>(
                  initialValue: _selectedDoor?.id,
                  decoration: const InputDecoration(labelText: 'Kapi'),
                  items: [
                    for (final door in doors)
                      DropdownMenuItem<int>(
                        value: door.id,
                        child: Text(
                          '${door.doorName} - ${door.assignedDeviceUid ?? 'Bos'}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    final door = doors.firstWhere((item) => item.id == value);
                    setState(() => _selectedDoor = door);
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Iptal'),
        ),
        ElevatedButton(
          onPressed: _selectedDoor == null || _loadingDoors ? null : _submit,
          child: const Text('Ata'),
        ),
      ],
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
    _fullNameController = TextEditingController(
      text: widget.user?.fullName ?? '',
    );
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _phoneController = TextEditingController(
      text: widget.user?.phoneNumber ?? '',
    );
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        _isEditing
            ? '${widget.roleTitle} Duzenle'
            : 'Yeni ${widget.roleTitle} Ekle',
      ),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
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
                    labelText: _isEditing ? 'Yeni Sifre (opsiyonel)' : 'Sifre',
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
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
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

class _SiteFormResult {
  const _SiteFormResult({
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

class _DeviceFormResult {
  const _DeviceFormResult({
    required this.deviceUid,
    required this.assignedUserCode,
    required this.siteCode,
  });

  final String deviceUid;
  final int? assignedUserCode;
  final int? siteCode;
}

class _DeviceEditResult {
  const _DeviceEditResult({
    required this.assignedUserCode,
    required this.siteCode,
    required this.gateName,
  });

  final int? assignedUserCode;
  final int? siteCode;
  final String? gateName;
}

enum _DeviceToolAction { registerDevice, provisionWifi }

class _ApartmentResidentFormResult {
  const _ApartmentResidentFormResult({
    required this.fullName,
    required this.loginName,
    required this.email,
    required this.password,
    required this.phoneNumber,
    required this.isActive,
  });

  final String fullName;
  final String loginName;
  final String email;
  final String password;
  final String phoneNumber;
  final bool isActive;
}

class _DoorDeviceAssignResult {
  const _DoorDeviceAssignResult({required this.deviceUid});

  final String deviceUid;
}
