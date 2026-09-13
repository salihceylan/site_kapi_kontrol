import 'dart:async';

import 'package:flutter/material.dart';

import 'package:site_kapi_kontrol/models/apartment_record.dart';

import 'package:site_kapi_kontrol/models/device_page.dart';

import 'package:site_kapi_kontrol/models/device_record.dart';

import 'package:site_kapi_kontrol/models/door_record.dart';

import 'package:site_kapi_kontrol/models/door_runtime_status.dart';

import 'package:site_kapi_kontrol/models/managed_user_account.dart';

import 'package:site_kapi_kontrol/models/managed_user_page.dart';

import 'package:site_kapi_kontrol/models/site_page.dart';

import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';

import 'package:site_kapi_kontrol/models/site_structure_record.dart';

import 'package:site_kapi_kontrol/models/subscription_request.dart';

import 'package:site_kapi_kontrol/models/subscription_request_page.dart';

import 'package:site_kapi_kontrol/models/user_role.dart';

import 'package:site_kapi_kontrol/models/user_session.dart';

import 'package:site_kapi_kontrol/services/auth_service.dart';

import 'package:site_kapi_kontrol/services/pdf_credentials_service.dart';

import 'package:site_kapi_kontrol/services/pdf_device_firmware_service.dart';

import 'package:site_kapi_kontrol/services/pdf_logs_service.dart';

import 'package:site_kapi_kontrol/services/quick_actions_service.dart';

import 'package:site_kapi_kontrol/services/voice_door_service.dart';

import 'package:site_kapi_kontrol/services/door_widget_service.dart';

import 'package:site_kapi_kontrol/styles/app_colors.dart';

import 'package:site_kapi_kontrol/styles/role_theme.dart';

import 'package:site_kapi_kontrol/ui/dialogs/apartment_resident_dialog.dart';

import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';

import 'package:site_kapi_kontrol/ui/dialogs/device_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/claim_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/replace_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';

import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_permissions_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_join_qr_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_residents_accordion_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/manage_join_requests_dialog.dart';

import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

import 'package:site_kapi_kontrol/ui/pages/wifi_provision_page.dart';

import 'package:site_kapi_kontrol/ui/views/bluetooth_wifi_view.dart';

import 'package:site_kapi_kontrol/ui/views/company_devices_view.dart';

import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';

import 'package:site_kapi_kontrol/ui/views/device_add_view.dart';

import 'package:site_kapi_kontrol/ui/views/managed_users_view.dart';
import 'package:site_kapi_kontrol/ui/views/all_users_view.dart';

import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/pending_site_approvals_view.dart';

import 'package:site_kapi_kontrol/ui/views/profile_view.dart';

import 'package:site_kapi_kontrol/ui/views/sites_view.dart';

import 'package:site_kapi_kontrol/ui/views/subscription_requests_view.dart';

import 'package:site_kapi_kontrol/ui/widgets/hands_free_settings_dialog.dart';

import 'package:site_kapi_kontrol/ui/widgets/site_security_policy_dialog.dart';

import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';



class HomePage extends StatefulWidget {

  const HomePage({

    super.key,

    required this.authService,

    this.quickActionsService,

    this.voiceDoorService,

  });



  final AuthService authService;

  final QuickActionsService? quickActionsService;

  final VoiceDoorService? voiceDoorService;



  @override

  State<HomePage> createState() => _HomePageState();

}



class _HomePageState extends State<HomePage> with WidgetsBindingObserver {

  SirketMenuItem _selectedMenu = SirketMenuItem.dashboard;

  Timer? _statusAutoRefreshTimer;



  // Profil Form

  final _profileFormKey = GlobalKey<FormState>();

  late final TextEditingController _profileFullNameController;

  late final TextEditingController _profileEmailController;

  late final TextEditingController _profilePhoneController;

  late final TextEditingController _profilePasswordController;

  bool _isSavingProfile = false;



  // Siteler & Hiyerarşi

  SitePage? _sitesPage;

  bool _isLoadingSites = false;

  SiteRecord? _selectedSite;

  SiteStructureRecord? _selectedSiteStructure;

  bool _isLoadingSiteStructure = false;

  final Set<int> _busyDeleteSites = <int>{};

  final Set<int> _busySiteApprovals = <int>{};

  final Set<int> _busyApartmentMails = <int>{};



  // Kapı Kontrol Paneli (Dashboard)

  SitePage? _doorControlSitesPage;

  bool _isLoadingDoorControlSites = false;

  SiteRecord? _doorControlSite;

  SiteStructureRecord? _doorControlStructure;

  bool _isLoadingDoorControlStructure = false;

  DoorRecord? _doorControlDoor;

  DoorRuntimeStatus? _doorRuntimeStatus;

  bool _isLoadingDoorStatus = false;

  String? _doorStatusError;

  bool _isOpeningDoor = false;

  bool _isPhoneOnWifi = false;

  bool _isDeviceLocalReachable = false;



  // Kullanıcı Yönetimi

  final Map<UserRole, ManagedUserPage> _managedPages = {};

  final Set<UserRole> _loadingRoles = <UserRole>{};

  final Set<int> _busyActivationUsers = <int>{};

  // Tüm Kullanıcılar Yönetimi (Directory)
  ManagedUserPage? _allUsersPage;
  bool _isLoadingAllUsers = false;
  UserRole? _allUsersRoleFilter;
  int _allUsersCurrentPage = 1;
  int _allUsersPageSize = 15;
  String? _allUsersSearchQuery;



  // Cihaz Yönetimi

  DevicePage? _companyDevicesPage;

  bool _isLoadingCompanyDevices = false;

  bool _isBroadcastingOtaCheck = false;



  // Abonelik & Onay Talepleri

  SubscriptionRequestPage? _subscriptionRequestsPage;

  bool _isLoadingSubscriptionRequests = false;

  final Set<int> _busySubscriptionRequests = <int>{};



  SitePage? _pendingSiteApprovalsPage;

  bool _isLoadingPendingSiteApprovals = false;

  bool _isResidentMode = false;

  bool get _canToggleDualMode {
    final session = widget.authService.session;
    if (session == null) return false;
    if (session.role == UserRole.superUser || session.role == UserRole.siteManager) return true;
    return (_doorControlSitesPage?.sites.isNotEmpty ?? false);
  }



  @override

  void initState() {

    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final session = widget.authService.session;

    _profileFullNameController = TextEditingController(

      text: session?.fullName ?? '',

    );

    _profileEmailController = TextEditingController(text: session?.email ?? '');

    _profilePhoneController = TextEditingController(

      text: session?.phoneNumber ?? '',

    );

    _profilePasswordController = TextEditingController();



    _loadInitialData();

    _startStatusAutoRefreshTimer();

  }



  @override

  void dispose() {

    WidgetsBinding.instance.removeObserver(this);

    _statusAutoRefreshTimer?.cancel();

    _profileFullNameController.dispose();

    _profileEmailController.dispose();

    _profilePhoneController.dispose();

    _profilePasswordController.dispose();

    super.dispose();

  }



  @override

  void didChangeAppLifecycleState(AppLifecycleState state) {

    if (state == AppLifecycleState.resumed) {

      if (_doorControlDoor != null) {

        _loadDoorRuntimeStatus(_doorControlDoor!.id, isBackgroundRefresh: true);

      }

    }

  }



  void _startStatusAutoRefreshTimer() {

    _statusAutoRefreshTimer?.cancel();

    _statusAutoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {

      if (!mounted) return;

      if (_doorControlDoor != null && !_isOpeningDoor) {

        _loadDoorRuntimeStatus(_doorControlDoor!.id, isBackgroundRefresh: true);

      }

    });

  }



  void _showMessage(String message) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),

    );

  }



  void _loadInitialData() {

    _loadDoorControlSites();

    _loadSites();

  }



  // --- Navigasyon & Menü ---

  bool _canAccessMenu(SirketMenuItem item, UserRole role) {

    switch (role) {

      case UserRole.superUser:

        return item != SirketMenuItem.abonelikTalepleri &&

            item != SirketMenuItem.siteOnayTalepleri &&

            item != SirketMenuItem.ellerSerbest;

      case UserRole.siteManager:

        return item == SirketMenuItem.dashboard ||

            item == SirketMenuItem.profilim ||

            item == SirketMenuItem.siteler ||

            item == SirketMenuItem.kayitliCihazlar ||

            item == SirketMenuItem.bluetoothWifiKur;

      case UserRole.apartmentOwner:
      case UserRole.individual:
        if (_canToggleDualMode && !_isResidentMode) {
          return item == SirketMenuItem.dashboard ||
              item == SirketMenuItem.profilim ||
              item == SirketMenuItem.siteler ||
              item == SirketMenuItem.kayitliCihazlar ||
              item == SirketMenuItem.bluetoothWifiKur;
        }
        return item == SirketMenuItem.dashboard ||
            item == SirketMenuItem.ellerSerbest;
    }

  }



  String _titleForMenu(SirketMenuItem item) {

    switch (item) {

      case SirketMenuItem.dashboard:

        return 'AHBU Panel';

      case SirketMenuItem.profilim:

        return 'Profilim';

      case SirketMenuItem.ellerSerbest:

        return 'Eller Serbest & Kestirmeler';

      case SirketMenuItem.abonelikTalepleri:

        return 'Yeni Abonelik Talepleri';

      case SirketMenuItem.siteOnayTalepleri:

        return 'Site Onay Talepleri';

      case SirketMenuItem.kullaniciYonetimi:

        return 'Kullanıcı Yönetimi';

      case SirketMenuItem.superUserYonetimi:

        return 'Süper Kullanıcı Yönetimi';

      case SirketMenuItem.siteYoneticileriYonetimi:

        return 'Site Yöneticileri Yönetimi';

      case SirketMenuItem.daireKullanicilariYonetimi:

        return 'Daire Sakinleri';

      case SirketMenuItem.siteler:

        return 'Site Yönetimi';

      case SirketMenuItem.cihazEkle:

        return 'Cihaz Kaydet';

      case SirketMenuItem.kayitliCihazlar:

        return 'Kayıtlı Cihazlar';

      case SirketMenuItem.bluetoothWifiKur:

        return 'Bluetooth ile Wi-Fi Kurulumu';

    }

  }



  void _selectMenu(SirketMenuItem item) {

    Navigator.of(context).pop();

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



    final session = widget.authService.session;

    if (session == null) return;



    switch (item) {

      case SirketMenuItem.dashboard:

        _loadDoorControlSites();

        break;

      case SirketMenuItem.siteler:

      case SirketMenuItem.daireKullanicilariYonetimi:

        _loadSites(force: true);

        break;

      case SirketMenuItem.kullaniciYonetimi:
        _loadAllUsers(force: true);
        break;

      case SirketMenuItem.superUserYonetimi:

        _loadManagedUsers(UserRole.superUser, force: true);

        break;

      case SirketMenuItem.siteYoneticileriYonetimi:

        _loadManagedUsers(UserRole.siteManager, force: true);

        break;

      case SirketMenuItem.kayitliCihazlar:

        _loadCompanyDevices(force: true);

        break;

      case SirketMenuItem.abonelikTalepleri:

        _loadSubscriptionRequests(force: true);

        break;

      case SirketMenuItem.siteOnayTalepleri:

        _loadPendingSiteApprovals(force: true);

        break;

      default:

        break;

    }

  }



  // --- API Yükleyicileri ---

  Future<void> _loadSites({

    int page = 1,

    bool force = false,

    int? preferredSiteId,

  }) async {

    if (_isLoadingSites && !force) return;

    setState(() => _isLoadingSites = true);

    try {

      final data = await widget.authService.listSites(page: page);

      if (!mounted) return;

      setState(() {

        _isLoadingSites = false;

        _sitesPage = data;

        if (data.sites.isNotEmpty) {

          if (preferredSiteId != null) {

            final target =

                data.sites.where((s) => s.id == preferredSiteId).firstOrNull;

            _selectSite(target ?? data.sites.first);

          } else if (_selectedSite == null ||

              !data.sites.any((s) => s.id == _selectedSite!.id)) {

            _selectSite(data.sites.first);

          }

        } else {

          _selectedSite = null;

          _selectedSiteStructure = null;

        }

      });

    } catch (e) {

      if (!mounted) return;

      setState(() => _isLoadingSites = false);

      if (force) {

        _showMessage(e.toString());

      }

    }

  }



  Future<void> _selectSite(SiteRecord site) async {

    setState(() {

      _selectedSite = site;

      _selectedSiteStructure = null;

      _isLoadingSiteStructure = true;

    });



    final (structure, error) = await widget.authService.getSiteStructure(

      siteCode: site.id,

    );

    if (!mounted) return;

    setState(() {

      _isLoadingSiteStructure = false;

      _selectedSiteStructure = structure;

    });

    if (error != null && structure == null) _showMessage(error);

  }



  Future<void> _loadDoorControlSites({int? preferredSiteId}) async {

    final session = widget.authService.session;

    if (session == null) return;



    if (session.role == UserRole.apartmentOwner) {

      setState(() => _isLoadingDoorControlStructure = true);

      final (doors, _) = await widget.authService.listMyDoors();

      if (!mounted) return;

      setState(() {

        _isLoadingDoorControlStructure = false;

        if (doors != null && doors.isNotEmpty) {

          final firstSiteName = doors.first.siteName;

          _doorControlStructure = SiteStructureRecord(

            site: SiteRecord(

              id: doors.first.siteCode,

              name: (firstSiteName != null && firstSiteName.isNotEmpty)

                  ? firstSiteName

                  : 'Site Kapısı',

              address: null,

              city: null,

              district: null,

              managerUserCode: session.id,

              managerName: session.fullName,

              mqttSiteId: 0,

              approvedAt: DateTime.now(),

              blockCount: 1,

              doorCount: doors.length,

              apartmentCount: 1,

              approvalStatus: 'approved',

              createdAt: DateTime.now(),

            ),

            doors: doors,

            blocks: const [],

            apartments: const [],

          );

          _selectDoorControlDoor(doors.first.id);

        }

      });

      if (doors != null) {

        _checkAndStartVoiceAssistance(doors);

      }

      return;

    }



    setState(() => _isLoadingDoorControlSites = true);

    try {

      final data = await widget.authService.listSites(page: 1, pageSize: 100);

      if (!mounted) return;

      setState(() {

        _isLoadingDoorControlSites = false;

        _doorControlSitesPage = data;

        if (data.sites.isNotEmpty) {

          final targetSiteId = preferredSiteId ??

              (_doorControlSite != null &&

                      data.sites.any((s) => s.id == _doorControlSite!.id)

                  ? _doorControlSite!.id

                  : data.sites.first.id);

          _selectDoorControlSite(targetSiteId);

        } else {

          _doorControlSite = null;

          _doorControlStructure = null;

          _doorControlDoor = null;

          _doorRuntimeStatus = null;

        }

      });

    } catch (_) {

      if (!mounted) return;

      setState(() => _isLoadingDoorControlSites = false);

    }

  }



  Future<void> _selectDoorControlSite(int siteId) async {

    final site = _doorControlSitesPage?.sites.firstWhere(

      (s) => s.id == siteId,

      orElse: () => _doorControlSitesPage!.sites.first,

    );

    setState(() {

      _doorControlSite = site;

      _doorControlStructure = null;

      _doorControlDoor = null;

      _doorRuntimeStatus = null;

      _isLoadingDoorControlStructure = true;

    });



    final (structure, _) = await widget.authService.getSiteStructure(

      siteCode: siteId,

    );

    if (!mounted) return;

    setState(() {

      _isLoadingDoorControlStructure = false;

      _doorControlStructure = structure;

      if (structure != null && structure.doors.isNotEmpty) {

        _selectDoorControlDoor(structure.doors.first.id);

      }

    });

    if (structure != null &&

        structure.doors.isNotEmpty &&

        widget.authService.session?.role == UserRole.apartmentOwner) {

      _checkAndStartVoiceAssistance(structure.doors);

    }

  }



  Future<void> _checkAndStartVoiceAssistance(List<DoorRecord> doors) async {

    final session = widget.authService.session;

    // YALNIZCA Daire Sakini (apartmentOwner) için ses motoru devrededir!

    if (session == null ||

        session.role != UserRole.apartmentOwner ||

        widget.voiceDoorService == null) {

      return;

    }



    if (doors.isEmpty) {

      await widget.voiceDoorService!.speak('Tanımlı bir kapı bulunamadı.');

      return;

    }



    final hasActiveDevice = doors.any(

      (d) =>

          d.assignedDeviceUid != null && d.assignedDeviceUid!.trim().isNotEmpty,

    );

    if (!hasActiveDevice) {

      await widget.voiceDoorService!.speak(

        'Kapılara henüz bir cihaz atanmamış.',

      );

      return;

    }



    // Cihaz atanmış ve kapı hazır: otomatik dinlemeyi başlat

    if (!widget.voiceDoorService!.isListening) {

      await widget.voiceDoorService!.startListening(candidateDoors: doors);

    }

  }



  void _selectDoorControlDoor(int doorId) {

    final door = _doorControlStructure?.doors.firstWhere(

      (d) => d.id == doorId,

      orElse: () => _doorControlStructure!.doors.first,

    );

    setState(() {

      _doorControlDoor = door;

      _doorRuntimeStatus = null;

    });

    if (door != null) {

      _loadDoorRuntimeStatus(door.id);

      final token = widget.authService.session?.token;

      final role = widget.authService.session?.role;

      if (token != null && (role == UserRole.siteManager || role == UserRole.apartmentOwner)) {

        final allDoors = _doorControlStructure?.doors ?? [door];

        final isOnline = (_doorRuntimeStatus?.mqttConnected == true) || _isDeviceLocalReachable;

        DoorWidgetService.instance.syncDoorsList(

          doors: allDoors,

          token: token,

          apiBaseUrl: widget.authService.api.baseUrl,

          selectedDoor: door,

          isSelectedDoorOnline: isOnline,

        );

      }

    }

  }



  Future<void> _loadDoorRuntimeStatus(

    int doorId, {

    bool isBackgroundRefresh = false,

  }) async {

    if (!isBackgroundRefresh) {

      setState(() {

        _isLoadingDoorStatus = true;

        _doorStatusError = null;

      });

    }



    try {

      final (status, error) = await widget.authService.getDoorRuntimeStatus(

        doorId: doorId,

      );

      if (!mounted || _doorControlDoor?.id != doorId) return;



      final isWifi = await widget.authService.isPhoneConnectedToLocalWifi();

      if (!mounted || _doorControlDoor?.id != doorId) return;



      final assignedUid = _doorControlDoor?.assignedDeviceUid?.trim();

      final hasUid = assignedUid != null && assignedUid.isNotEmpty;

      bool localReachable = false;

      if (status?.mqttConnected != true && isWifi && hasUid) {

        localReachable = await widget.authService.isDeviceReachableOnLocalWifi(

          assignedUid,

        );

      }



      if (!mounted || _doorControlDoor?.id != doorId) return;

      setState(() {

        _isPhoneOnWifi = isWifi;

        _isDeviceLocalReachable = localReachable;

        if (status != null) {

          _doorRuntimeStatus = status;

        }

        final canLocal = _doorControlDoor != null && localReachable;

        if (canLocal &&

            error != null &&

            (error.contains('Sunucuya') ||

                error.contains('Internet') ||

                error.contains('baglanilamadi'))) {

          _doorStatusError = null;

        } else {

          if (!isBackgroundRefresh || error == null) {

            _doorStatusError = error;

          }

        }



        final role = widget.authService.session?.role;

        final token = widget.authService.session?.token;

        if (token != null &&

            (role == UserRole.siteManager || role == UserRole.apartmentOwner) &&

            _doorControlDoor != null) {

          final allDoors = _doorControlStructure?.doors ?? [_doorControlDoor!];

          final isOnline = (status?.mqttConnected == true) || localReachable;

          DoorWidgetService.instance.syncDoorsList(

            doors: allDoors,

            token: token,

            apiBaseUrl: widget.authService.api.baseUrl,

            selectedDoor: _doorControlDoor,

            isSelectedDoorOnline: isOnline,

          );

        }

      });

    } catch (_) {

      // Background refresh hatalarında UI'ı bozma

    } finally {

      if (mounted && !isBackgroundRefresh) {

        setState(() {

          _isLoadingDoorStatus = false;

        });

      }

    }

  }



  Future<void> _openDoor() async {

    final door = _doorControlDoor;

    if (door == null || _isOpeningDoor) return;



    setState(() => _isOpeningDoor = true);

    final (status, error) = await widget.authService.openDoor(

      doorId: door.id,

      door: door,

    );

    if (!mounted) return;

    setState(() {

      _isOpeningDoor = false;

      if (status != null) {

        _doorRuntimeStatus = status;

        _doorStatusError = null;

      }

    });

    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Kapı açma komutu gönderildi.');

    }

  }



  Future<void> _loadManagedUsers(

    UserRole role, {

    int page = 1,

    bool force = false,

  }) async {

    if (_loadingRoles.contains(role) && !force) return;

    setState(() => _loadingRoles.add(role));

    try {

      final data = await widget.authService.listManagedUsers(

        role: role,

        page: page,

      );

      if (!mounted) return;

      setState(() {

        _loadingRoles.remove(role);

        _managedPages[role] = data;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() => _loadingRoles.remove(role));

      _showMessage(e.toString());

    }

  }

  Future<void> _loadAllUsers({
    UserRole? role,
    int page = 1,
    int pageSize = 15,
    String? search,
    bool force = false,
  }) async {
    final sanitizedRole = role == UserRole.superUser ? null : role;
    if (_isLoadingAllUsers && !force) return;
    _allUsersRoleFilter = sanitizedRole;
    _allUsersCurrentPage = page;
    _allUsersPageSize = pageSize;
    _allUsersSearchQuery = search;

    setState(() => _isLoadingAllUsers = true);
    try {
      final data = await widget.authService.listManagedUsers(
        role: sanitizedRole,
        excludeRole: UserRole.superUser,
        page: page,
        pageSize: pageSize,
        search: search,
      );
      if (!mounted) return;
      setState(() {
        _isLoadingAllUsers = false;
        _allUsersPage = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAllUsers = false);
      _showMessage(e.toString());
    }
  }

  Future<void> _updateDirectoryUser(
    ManagedUserAccount user,
    ManagedUserFormResult result,
  ) async {
    final error = await widget.authService.updateManagedUser(
      userCode: user.id,
      fullName: result.fullName,
      email: result.email,
      phoneNumber: result.phoneNumber.isEmpty ? null : result.phoneNumber,
      password: result.password.isEmpty ? null : result.password,
      isActive: result.isActive,
      role: result.role,
    );
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
    } else {
      _showMessage('Kullanıcı bilgileri güncellendi.');
      await _loadAllUsers(
        role: _allUsersRoleFilter,
        page: _allUsersCurrentPage,
        pageSize: _allUsersPageSize,
        search: _allUsersSearchQuery,
        force: true,
      );
      if (result.role != null) {
        _loadManagedUsers(result.role!, force: true);
      }
      _loadManagedUsers(user.role, force: true);
    }
  }

  Future<void> _toggleDirectoryUserActivation(
    ManagedUserAccount user,
    bool isActive,
  ) async {
    setState(() => _busyActivationUsers.add(user.id));
    final error = await widget.authService.setManagedUserActivation(
      userCode: user.id,
      isActive: isActive,
    );
    if (!mounted) return;
    setState(() => _busyActivationUsers.remove(user.id));
    if (error != null) {
      _showMessage(error);
    } else {
      _showMessage(isActive ? 'Kullanıcı aktif edildi.' : 'Kullanıcı pasif yapıldı.');
      await _loadAllUsers(
        role: _allUsersRoleFilter,
        page: _allUsersCurrentPage,
        pageSize: _allUsersPageSize,
        search: _allUsersSearchQuery,
        force: true,
      );
      _loadManagedUsers(user.role, force: true);
    }
  }

  Future<void> _deleteDirectoryUser(ManagedUserAccount user) async {
    final error = await widget.authService.deleteManagedUser(userCode: user.id);
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
    } else {
      _showMessage('Kullanıcı kalıcı olarak silindi.');
      await _loadAllUsers(
        role: _allUsersRoleFilter,
        page: _allUsersCurrentPage,
        pageSize: _allUsersPageSize,
        search: _allUsersSearchQuery,
        force: true,
      );
      _loadManagedUsers(user.role, force: true);
    }
  }

  Future<void> _loadCompanyDevices({int page = 1, bool force = false}) async {

    if (_isLoadingCompanyDevices && !force) return;

    setState(() => _isLoadingCompanyDevices = true);

    final (data, error) = await widget.authService.listCompanyDevices(

      page: page,

      pageSize: 10,

    );

    if (!mounted) return;

    setState(() {

      _isLoadingCompanyDevices = false;

      if (data != null) {

        _companyDevicesPage = data;

      }

    });

    if (error != null) _showMessage(error);

  }



  Future<void> _loadSubscriptionRequests({

    int page = 1,

    bool force = false,

  }) async {

    if (_isLoadingSubscriptionRequests && !force) return;

    setState(() => _isLoadingSubscriptionRequests = true);

    try {

      final data = await widget.authService.listSubscriptionRequests(

        page: page,

      );

      if (!mounted) return;

      setState(() {

        _isLoadingSubscriptionRequests = false;

        _subscriptionRequestsPage = data;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() => _isLoadingSubscriptionRequests = false);

      _showMessage(e.toString());

    }

  }



  Future<void> _loadPendingSiteApprovals({

    int page = 1,

    bool force = false,

  }) async {

    if (_isLoadingPendingSiteApprovals && !force) return;

    setState(() => _isLoadingPendingSiteApprovals = true);

    try {

      final data = await widget.authService.listSites(

        page: page,

        approvalStatus: 'pending',

      );

      if (!mounted) return;

      setState(() {

        _isLoadingPendingSiteApprovals = false;

        _pendingSiteApprovalsPage = data;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() => _isLoadingPendingSiteApprovals = false);

      _showMessage(e.toString());

    }

  }



  // --- Eylemler & Diyalog Tetikleyicileri ---

  Future<void> _openSiteDialog({SiteRecord? site}) async {

    final result = await SiteDialog.show(

      context,

      authService: widget.authService,

      site: site,

    );

    if (result == null) return;



    if (site == null) {

      final (createdSite, error) = await widget.authService.createSite(

        name: result.name,

        address: result.address.isEmpty ? null : result.address,

        city: result.city.isEmpty ? null : result.city,

        district: result.district.isEmpty ? null : result.district,

        blockApartmentCounts: result.blockApartmentCounts,

        doorCount: result.doorCount,

        managerUserCode: result.managerUserCode,

        managerUser: result.managerUser,

      );

      if (error != null) {

        _showMessage(error);

      } else {

        _showMessage('Site başarıyla oluşturuldu.');

        await _loadSites(force: true, preferredSiteId: createdSite?.id);

        await _loadDoorControlSites(preferredSiteId: createdSite?.id);

      }

    } else {

      final error = await widget.authService.updateSite(

        siteCode: site.id,

        name: result.name,

        address: result.address.isEmpty ? null : result.address,

        city: result.city.isEmpty ? null : result.city,

        district: result.district.isEmpty ? null : result.district,

        blockApartmentCounts: result.blockApartmentCounts,

        doorCount: result.doorCount,

        managerUserCode: result.managerUserCode,

      );

      if (error != null) {

        _showMessage(error);

      } else {

        _showMessage('Site güncellendi.');

        await _loadSites(force: true, preferredSiteId: site.id);

        await _loadDoorControlSites(preferredSiteId: site.id);

      }

    }

  }



  Future<void> _openSiteSecurityPolicyDialog(SiteRecord site) async {

    final result = await SiteSecurityPolicyDialog.show(

      context,

      site: site,

      authService: widget.authService,

    );

    if (result == true) {

      _showMessage('Güvenlik ve giriş politikaları güncellendi.');

      await _loadSites(force: true, preferredSiteId: site.id);

      await _loadDoorControlSites(preferredSiteId: site.id);

    }

  }



  Future<void> _deleteSite(SiteRecord site) async {
    final session = widget.authService.session;
    final isSuperUser = session?.role == UserRole.superUser;
    final hasManager = site.managerName != null && site.managerName!.trim().isNotEmpty;

    if (isSuperUser) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${site.name} Sitesini Sil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bu siteyi silmek için bir yöntem seçiniz:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.pop(ctx, 'email'),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mark_email_read_rounded, color: Color(0xFFDC2626), size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'E-Posta Kodu İle Doğrudan Sil',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF991B1B),
                                fontSize: 13.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Kayıtlı e-postanıza 6 haneli kod gelir ve site anında silinir.',
                              style: TextStyle(color: Color(0xFF7F1D1D), fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasManager) ...[
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.pop(ctx, 'manager_approval'),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.forward_to_inbox_rounded, color: Color(0xFFD97706), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Site Yöneticisinin Onayına Gönder',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF92400E),
                                  fontSize: 13.5,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Site yöneticisine onay bildirimi iletilir; yönetici onaylayınca silinir.',
                                style: TextStyle(color: Color(0xFFB45309), fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('İptal'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (choice == 'email') {
        return _deleteSiteWithEmailVerification(site);
      }
      if (choice != 'manager_approval') {
        return;
      }
    }

    if (!mounted) return;

    final String promptText;
    if (isSuperUser && hasManager) {
      promptText =
          '${site.name} sitesini silmek için site yöneticisinin onayı gerekecektir. Silme talebi oluşturulsun mu?';
    } else if (!isSuperUser) {
      promptText =
          '${site.name} sitesini silmek için Süper Kullanıcının onayı gerekecektir. Silme talebi oluşturulsun mu?';
    } else {
      promptText =
          '${site.name} sitesini ve bağlı tüm kapı/daire kayıtlarını kalıcı olarak silmek istediğinize emin misiniz?';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSuperUser && !hasManager ? 'Siteyi Kalıcı Olarak Sil' : 'Site Silme Talebi'),
        content: Text(promptText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSuperUser && !hasManager ? 'Sil' : 'Talebi İlet'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busyDeleteSites.add(site.id));
    final result = await widget.authService.deleteSite(siteCode: site.id);
    if (!mounted) return;

    setState(() {
      _busyDeleteSites.remove(site.id);
      if (result.deleted) {
        if (_selectedSite?.id == site.id) {
          _selectedSite = null;
          _selectedSiteStructure = null;
        }
        if (_doorControlSite?.id == site.id) {
          _doorControlSite = null;
          _doorControlStructure = null;
          _doorControlDoor = null;
          _doorRuntimeStatus = null;
        }
      }
    });

    if (result.error != null) {
      _showMessage(result.error!);
    } else {
      _showMessage(
        result.message ??
            (result.deleted ? 'Site silindi.' : 'Silme talebi iletildi.'),
      );
      await _loadSites(force: true);
      if (result.deleted) {
        await _loadDoorControlSites();
        if (session != null) {
          if (session.role == UserRole.superUser) {
            _loadManagedUsers(UserRole.apartmentOwner, force: true);
            _loadManagedUsers(UserRole.siteManager, force: true);
          } else if (session.role == UserRole.siteManager) {
            _loadManagedUsers(UserRole.apartmentOwner, force: true);
          }
        }
      }
    }
  }

  Future<void> _deleteSiteWithEmailVerification(SiteRecord site) async {
    setState(() => _busyDeleteSites.add(site.id));
    final reqRes = await widget.authService.requestSiteDeletionEmailCode(siteCode: site.id);
    if (!mounted) return;
    setState(() => _busyDeleteSites.remove(site.id));

    if (reqRes.error != null) {
      _showMessage(reqRes.error!);
      return;
    }

    final codeController = TextEditingController();
    String? localError;
    bool isResending = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'E-Posta Kodu İle Sil',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DİKKAT: "${site.name}" sitesi ve bağlı TÜM DAİRE KULLANICILARI, kapılar, cihazlar ve yetkiler kalıcı olarak silinecektir.',
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'E-posta adresinize (${reqRes.maskedEmail ?? "Süper Kullanıcı e-postası"}) 6 haneli silme güvenlik kodu gönderildi. Eminseniz kodu aşağıya giriniz:',
                          style: const TextStyle(
                            color: Color(0xFF7F1D1D),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: TextStyle(
                        letterSpacing: 8,
                        color: Colors.grey.shade400,
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red, width: 2),
                      ),
                    ),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      localError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: isResending
                          ? null
                          : () async {
                              setModalState(() => isResending = true);
                              final resend = await widget.authService.requestSiteDeletionEmailCode(
                                siteCode: site.id,
                              );
                              if (context.mounted) {
                                setModalState(() {
                                  isResending = false;
                                  if (resend.error != null) {
                                    localError = resend.error;
                                  } else {
                                    localError = 'Yeni kod e-posta adresinize gönderildi.';
                                  }
                                });
                              }
                            },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(isResending ? 'Gönderiliyor...' : 'Kodu Tekrar Gönder'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  final code = codeController.text.trim();
                  if (code.length != 6) {
                    setModalState(() => localError = 'Lütfen 6 haneli kodu eksiksiz giriniz.');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text(
                  'Onayla ve Kalıcı Olarak Sil',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final code = codeController.text.trim();
    setState(() => _busyDeleteSites.add(site.id));
    final confirmRes = await widget.authService.confirmSiteDeletionWithEmailCode(
      siteCode: site.id,
      code: code,
    );
    if (!mounted) return;
    setState(() => _busyDeleteSites.remove(site.id));

    if (confirmRes.error != null) {
      _showMessage(confirmRes.error!);
    } else {
      _showMessage(confirmRes.message ?? 'Site ve bağlı tüm kayıtlar silindi.');
      if (_selectedSite?.id == site.id) {
        setState(() {
          _selectedSite = null;
          _selectedSiteStructure = null;
        });
      }
      if (_doorControlSite?.id == site.id) {
        setState(() {
          _doorControlSite = null;
          _doorControlStructure = null;
          _doorControlDoor = null;
          _doorRuntimeStatus = null;
        });
      }
      await _loadSites(force: true);
      await _loadDoorControlSites();
      final session = widget.authService.session;
      if (session != null) {
        if (session.role == UserRole.superUser) {
          _loadManagedUsers(UserRole.apartmentOwner, force: true);
          _loadManagedUsers(UserRole.siteManager, force: true);
        } else if (session.role == UserRole.siteManager) {
          _loadManagedUsers(UserRole.apartmentOwner, force: true);
        }
      }
    }
  }

  Future<void> _approveDeleteSite(SiteRecord site) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Siteyi Kalıcı Olarak Sil'),
        content: Text(
          '${site.name} sitesi ve bağlı tüm kapı, cihaz ve daire kayıtları KALICI OLARAK silinecektir. Bu işlem geri alınamaz.\n\nSilme talebini onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla ve Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busyDeleteSites.add(site.id));
    final result = await widget.authService.approveSiteDeletion(siteCode: site.id);
    if (!mounted) return;

    setState(() {
      _busyDeleteSites.remove(site.id);
      if (_selectedSite?.id == site.id) {
        _selectedSite = null;
        _selectedSiteStructure = null;
      }
      if (_doorControlSite?.id == site.id) {
        _doorControlSite = null;
        _doorControlStructure = null;
        _doorControlDoor = null;
        _doorRuntimeStatus = null;
      }
    });

    if (result.error != null) {
      _showMessage(result.error!);
    } else {
      _showMessage(result.message ?? 'Site silindi.');
      await _loadSites(force: true);
      await _loadDoorControlSites();
      final session = widget.authService.session;
      if (session != null) {
        if (session.role == UserRole.superUser) {
          _loadManagedUsers(UserRole.apartmentOwner, force: true);
          _loadManagedUsers(UserRole.siteManager, force: true);
        } else if (session.role == UserRole.siteManager) {
          _loadManagedUsers(UserRole.apartmentOwner, force: true);
        }
      }
    }
  }

  Future<void> _rejectDeleteSite(SiteRecord site) async {
    final session = widget.authService.session;
    final isSuperUser = session?.role == UserRole.superUser;
    final isCaller = (isSuperUser && site.isPendingSiteManagerApproval) ||
        (!isSuperUser && site.isPendingSuperUserApproval);

    final actionTitle =
        isCaller ? 'Silme Talebini İptal Et' : 'Silme Talebini Reddet';
    final actionMessage = isCaller
        ? '${site.name} sitesi için oluşturduğunuz silme talebini iptal etmek istediğinize emin misiniz?'
        : '${site.name} sitesi için iletilen silme talebini reddetmek istediğinize emin misiniz?';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(actionTitle),
        content: Text(actionMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isCaller ? 'Talebi İptal Et' : 'Talebi Reddet'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busyDeleteSites.add(site.id));
    final result = await widget.authService.rejectSiteDeletion(siteCode: site.id);
    if (!mounted) return;

    setState(() => _busyDeleteSites.remove(site.id));

    if (result.error != null) {
      _showMessage(result.error!);
    } else {
      _showMessage(result.message ?? 'Silme talebi kaldırıldı.');
      await _loadSites(force: true);
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

    if (!mounted) return;

    setState(() => _busySiteApprovals.remove(siteCode));



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage(

        action == 'approve' ? 'Site onaylandı.' : 'Site reddedildi.',

      );

      _loadSites(force: true);

      _loadPendingSiteApprovals(force: true);

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

    if (!mounted) return;

    setState(() => _busySubscriptionRequests.remove(userCode));



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage(

        action == 'approve' ? 'Abonelik onaylandı.' : 'Abonelik reddedildi.',

      );

      _loadSubscriptionRequests(force: true);

    }

  }



  Future<void> _openApartmentResidentDialog(ApartmentRecord apartment) async {

    final result = await ApartmentResidentDialog.show(

      context,

      apartment: apartment,

    );

    if (result == null) return;



    final (updated, error) = await widget.authService.upsertApartmentResident(

      apartmentId: apartment.id,

      fullName: result.fullName,

      loginName: result.loginName,

      password: result.password,

      email: result.email.isEmpty ? null : result.email,

      phoneNumber: result.phoneNumber.isEmpty ? null : result.phoneNumber,

      isActive: result.isActive,

    );



    if (error != null) {

      _showMessage(error);

    } else if (updated != null) {

      _showMessage('Daire kullanıcısı güncellendi.');

      if (_selectedSite != null) {

        _selectSite(_selectedSite!);

      }

    }

  }



  Future<void> _deleteApartmentResident(ApartmentRecord apartment) async {

    final confirm = await showDialog<bool>(

      context: context,

      builder: (ctx) => AlertDialog(

        title: const Text('Daire Sakinini Sil / Sıfırla'),

        content: Text(

          '${apartment.label} dairesine ait ${apartment.residentFullName ?? ''} sakinini silmek ve daireyi boşa çıkarmak istediğinize emin misiniz?',

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('İptal'),

          ),

          ElevatedButton(

            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Sil / Sıfırla'),

          ),

        ],

      ),

    );

    if (confirm != true) return;



    final error = await widget.authService.deleteApartmentResident(

      apartmentId: apartment.id,

    );



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Daire sakini başarıyla silindi.');

      if (_selectedSite != null) {

        _selectSite(_selectedSite!);

      }

    }

  }



  Future<void> _sendApartmentCredentials(ApartmentRecord apartment) async {

    setState(() => _busyApartmentMails.add(apartment.id));

    final error = await widget.authService.sendApartmentCredentials(

      apartmentId: apartment.id,

    );

    if (!mounted) return;

    setState(() => _busyApartmentMails.remove(apartment.id));



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Giriş bilgileri e-posta olarak gönderildi.');

    }

  }



  Future<void> _assignDoorDevice(DoorRecord door) async {
    final result = await DoorDeviceDialog.show(
      context,
      door: door,
      initialDeviceUid: door.assignedDeviceUid ?? '',
      authService: widget.authService,
    );
    if (result == null) return;

    if (result.unassign) {
      try {
        await widget.authService.unassignDoorDevice(doorId: door.id);
        _showMessage('Cihaz kapıdan çıkarıldı (serbest bırakıldı).');
        if (_selectedSite != null) {
          _selectSite(_selectedSite!);
        }
        _loadDoorControlSites();
        _loadCompanyDevices(force: true);
      } catch (e) {
        _showMessage('Cihaz kapıdan çıkarılamadı: $e');
      }
      return;
    }

    if (result.deviceUid != null && result.deviceUid!.isNotEmpty) {
      final (_, error) = await widget.authService.assignDoorDevice(
        doorId: door.id,
        deviceUid: result.deviceUid!,
      );

      if (error != null) {
        _showMessage(error);
      } else {
        _showMessage('Cihaz kapıya atandı.');
        if (_selectedSite != null) {
          _selectSite(_selectedSite!);
        }
        _loadDoorControlSites();
        _loadCompanyDevices(force: true);
      }
    }
  }

  Future<void> _openDoorDialog({DoorRecord? door}) async {
    final site = _selectedSite;
    if (site == null) return;
    final structure = _selectedSiteStructure;
    final blocks = structure?.blocks ?? const <SiteBlockRecord>[];

    final availableDevices = await widget.authService.getAssignableDevices(siteCode: site.id);

    if (!mounted) return;
    final result = await DoorEditDialog.show(
      context,
      authService: widget.authService,
      siteCode: site.id,
      door: door,
      blocks: blocks,
      availableDevices: availableDevices,
    );

    if (result == true) {
      _showMessage(door == null ? 'Yeni kapı oluşturuldu.' : 'Kapı güncellendi.');
      _selectSite(site);
      _loadDoorControlSites();
    }
  }

  Future<void> _deleteDoor(DoorRecord door) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kapıyı Sil'),
        content: Text(
          '${door.doorName} kapısını silmek istediğinize emin misiniz?\nVarsa atanmış cihaz serbest kalacaktır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.authService.deleteDoor(doorId: door.id);
      _showMessage('Kapı silindi.');
      if (_selectedSite != null) {
        _selectSite(_selectedSite!);
      }
      _loadDoorControlSites();
    } catch (e) {
      _showMessage('Kapı silinemedi: $e');
    }
  }

  Future<void> _openClaimDeviceFlow() async {
    final success = await ClaimDeviceDialog.show(context, widget.authService);
    if (success == true) {
      await _loadCompanyDevices(force: true);
      await _loadDoorControlSites();
    }
  }

  Future<void> _openReplaceDeviceDialog(DoorRecord door) async {
    final success = await ReplaceDeviceDialog.show(
      context,
      door: door,
      authService: widget.authService,
    );
    if (success == true) {
      if (_selectedSite != null) {
        _selectSite(_selectedSite!);
      }
      await _loadDoorControlSites();
      await _loadCompanyDevices(force: true);
    }
  }

  Future<void> _openDoorPermissionsDialog(DoorRecord door) async {
    await DoorPermissionsDialog.show(
      context,
      door: door,
      authService: widget.authService,
    );
  }

  Future<void> _openSiteJoinQrDialog(SiteRecord site) async {
    await SiteJoinQrDialog.show(
      context,
      site: site,
      authService: widget.authService,
    );
  }

  Future<void> _openManageJoinRequestsDialog(SiteRecord site) async {
    await ManageJoinRequestsDialog.show(
      context,
      site: site,
      authService: widget.authService,
    );
  }

  Future<void> _openSiteResidentsAccordionDialog(SiteRecord site) async {
    await SiteResidentsAccordionDialog.show(
      context,
      site: site,
      authService: widget.authService,
    );
  }

  Future<void> _openDeviceRegistrationFlow() async {

    final scannedUid = await Navigator.of(

      context,

    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));

    if (scannedUid == null || scannedUid.isEmpty) return;

    _openManualDeviceRegistrationFlow(initialUid: scannedUid);

  }



  Future<void> _openManualDeviceRegistrationFlow({String? initialUid}) async {

    final result = await DeviceDialog.show(

      context,

      initialDeviceUid: initialUid,

    );

    if (result == null) return;



    final (device, error) = await widget.authService.createDevice(

      deviceUid: result.deviceUid,

      assignedUserCode: result.assignedUserCode,

      siteCode: result.siteCode,

    );



    if (error != null) {

      _showMessage(error);

    } else if (device != null) {
      _showMessage('Cihaz başarıyla kaydedildi.');
      _loadCompanyDevices(force: true);
      _loadSites(force: true);
      _loadDoorControlSites();
    }
  }

  Future<void> _editCompanyDevice(DeviceRecord device) async {
    final isSuperUser = widget.authService.session?.role == UserRole.superUser;
    final result = await DeviceEditDialog.show(
      context,
      device: device,
      isSuperUser: isSuperUser,
    );
    if (result == null) return;

    final (_, error) = await widget.authService.updateDevice(
      deviceId: device.id,
      assignedUserCode: result.assignedUserCode,
      siteCode: result.siteCode,
      gateName: result.gateName,
    );

    if (error != null) {
      _showMessage(error);
    } else {
      _showMessage('Cihaz güncellendi.');
      _loadCompanyDevices(force: true);
      _loadSites(force: true);
      _loadDoorControlSites();
    }
  }



  Future<void> _assignCompanyDeviceToDoor(DeviceRecord device) async {

    final sites = _sitesPage?.sites ?? const <SiteRecord>[];

    final selectedDoor = await DeviceDoorAssignDialog.show(

      context,

      authService: widget.authService,

      sites: sites,

      device: device,

    );

    if (selectedDoor == null) return;



    final (_, error) = await widget.authService.assignDoorDevice(

      doorId: selectedDoor.id,

      deviceUid: device.deviceUid,

    );



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Cihaz ${selectedDoor.doorName} kapısına atandı.');

      _loadCompanyDevices(force: true);

      _loadSites(force: true);

      _loadDoorControlSites();

    }

  }



  Future<void> _deleteCompanyDevice(DeviceRecord device) async {

    final confirm = await showDialog<bool>(

      context: context,

      builder: (ctx) => AlertDialog(

        title: const Text('Cihazı Sil'),

        content: Text(

          '${device.deviceUid} cihazını şirket hesabından silmek istediğinize emin misiniz?',

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('İptal'),

          ),

          ElevatedButton(

            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Sil'),

          ),

        ],

      ),

    );

    if (confirm != true) return;



    final error = await widget.authService.deleteDevice(deviceId: device.id);

    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Cihaz silindi.');

      _loadCompanyDevices(force: true);

      _loadSites(force: true);

      _loadDoorControlSites();

    }

  }



  Future<void> _broadcastOtaCheck() async {

    setState(() => _isBroadcastingOtaCheck = true);

    final (_, error) = await widget.authService.broadcastOtaCheck();

    if (!mounted) return;

    setState(() => _isBroadcastingOtaCheck = false);



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Tüm cihazlara OTA kontrol sinyali gönderildi.');

      _loadCompanyDevices(force: true);

    }

  }



  Future<void> _exportFirmwareReportPdf() async {

    final devices = _companyDevicesPage?.devices ?? const <DeviceRecord>[];

    if (devices.isEmpty) {

      _showMessage('Raporlanacak kayıtlı cihaz bulunamadı.');

      return;

    }



    try {

      _showMessage('Cihaz sürüm ve güncelleme raporu hazırlanıyor...');

      await PdfDeviceFirmwareService.printOrShareFirmwareReportPdf(

        devices: devices,

        userEmail: widget.authService.session?.email,

        latestTargetVersion: '2.0.0',

      );

    } catch (e) {

      _showMessage('PDF oluşturulurken hata oluştu: $e');

    }

  }



  Future<void> _openWifiProvision() async {

    Navigator.of(context).push(

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

    if (widget.authService.session?.role == UserRole.apartmentOwner) {

      _showMessage('Daire sakinleri profil bilgilerini güncelleyemez.');

      return;

    }

    if (!(_profileFormKey.currentState?.validate() ?? false)) return;



    setState(() => _isSavingProfile = true);

    final error = await widget.authService.updateMyProfile(

      fullName: _profileFullNameController.text.trim(),

      email: _profileEmailController.text.trim().toLowerCase(),

      phoneNumber: _profilePhoneController.text.trim().isEmpty

          ? null

          : _profilePhoneController.text.trim(),

      password: _profilePasswordController.text.trim().isEmpty

          ? null

          : _profilePasswordController.text.trim(),

    );



    if (!mounted) return;

    setState(() => _isSavingProfile = false);



    if (error != null) {

      _showMessage(error);

    } else {

      _profilePasswordController.clear();

      setState(() {});

      _showMessage('Profil bilgileri güncellendi.');

    }

  }



  Future<void> _openManagedUserDialog({

    required UserRole role,

    ManagedUserAccount? user,

  }) async {

    final roleTitle = switch (role) {

      UserRole.superUser => 'Süper Kullanıcı',

      UserRole.siteManager => 'Site Yöneticisi',

      UserRole.apartmentOwner => 'Daire Sakini',
      UserRole.individual => 'Bireysel Kullanıcı',
    };



    final result = await ManagedUserDialog.show(

      context,

      role: role,

      roleTitle: roleTitle,

      user: user,

      isSelf: user?.id == widget.authService.session?.id,

    );

    if (result == null) return;



    if (user == null) {

      final error = await widget.authService.createManagedUser(

        role: role,

        fullName: result.fullName,

        email: result.email,

        phoneNumber: result.phoneNumber.isEmpty ? null : result.phoneNumber,

        password: result.password,

        isActive: result.isActive,

      );

      if (error != null) {

        _showMessage(error);

      } else {

        _showMessage('$roleTitle oluşturuldu.');

        _loadManagedUsers(role, force: true);

      }

    } else {

      final error = await widget.authService.updateManagedUser(

        userCode: user.id,

        fullName: result.fullName,

        email: result.email,

        phoneNumber: result.phoneNumber.isEmpty ? null : result.phoneNumber,

        password: result.password.isEmpty ? null : result.password,

        isActive: result.isActive,

      );

      if (error != null) {

        _showMessage(error);

      } else {

        _showMessage('$roleTitle güncellendi.');

        _loadManagedUsers(role, force: true);

      }

    }

  }



  Future<void> _toggleUserActivation({

    required UserRole role,

    required ManagedUserAccount user,

    required bool value,

  }) async {

    setState(() => _busyActivationUsers.add(user.id));

    final error = await widget.authService.setManagedUserActivation(

      userCode: user.id,

      isActive: value,

    );

    if (!mounted) return;

    setState(() => _busyActivationUsers.remove(user.id));



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('Kullanıcı durumu güncellendi.');

      _loadManagedUsers(role, force: true);

    }

  }



  Future<void> _deleteManagedUser({

    required UserRole role,

    required ManagedUserAccount user,

  }) async {

    final roleTitle = switch (role) {

      UserRole.superUser => 'Süper Kullanıcı',

      UserRole.siteManager => 'Site Yöneticisi',

      UserRole.apartmentOwner => 'Daire Sakini',
      UserRole.individual => 'Bireysel Kullanıcı',
    };



    final confirm = await showDialog<bool>(

      context: context,

      builder: (ctx) => AlertDialog(

        title: Text('$roleTitle Sil'),

        content: Text(

          '${user.fullName} (${user.email}) adlı $roleTitle hesabını silmek istediğinize emin misiniz?',

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('İptal'),

          ),

          ElevatedButton(

            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Sil'),

          ),

        ],

      ),

    );

    if (confirm != true) return;



    final error = await widget.authService.deleteManagedUser(

      userCode: user.id,

    );



    if (error != null) {

      _showMessage(error);

    } else {

      _showMessage('$roleTitle silindi.');

      _loadManagedUsers(role, force: true);

      _loadSites(force: true);

    }

  }



  Future<void> _exportSiteCredentialsPdf(SiteRecord site) async {

    try {

      _showMessage('${site.name} kullanıcı ve şifre raporu hazırlanıyor...');

      final (structure, error) = await widget.authService.getSiteStructure(

        siteCode: site.id,

      );

      if (structure == null) {

        _showMessage(error ?? 'Site yapısı ve daireler alınamadı.');

        return;

      }



      await PdfCredentialsService.printOrShareSitePdf(

        structure: structure,

        companyName: 'GÜDE TEKNOLOJİ',

      );

    } catch (e) {

      _showMessage('PDF oluşturulurken hata oluştu: $e');

    }

  }



  Future<void> _exportDoorLogsPdf(SiteRecord site, DoorRecord door) async {

    try {

      _showMessage('${door.doorName} haftalık geçiş log raporu hazırlanıyor...');

      final now = DateTime.now();

      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final (logsPage, error) = await widget.authService.listDoorAccessLogs(

        siteCode: site.id,

        doorId: door.id,
        startDate: sevenDaysAgo,
        pageSize: 200,
      );

      if (logsPage == null || logsPage.logs.isEmpty) {
        _showMessage(
          error ??
              '${door.doorName} için son 7 güne ait kapı geçiş kaydı bulunamadı.',
        );
        return;
      }

      await PdfLogsService.printOrShareLogsPdf(
        logs: logsPage.logs,
        siteName: site.name,
        doorNameFilter: door.doorName,
        startDate: sevenDaysAgo,
        endDate: now,
      );
    } catch (e) {
      _showMessage('Geçiş raporu PDF oluşturulurken hata: $e');
    }
  }

  Future<void> _exportSiteLogsPdf(SiteRecord site) async {
    try {
      _showMessage('${site.name} haftalık geçiş log raporu hazırlanıyor...');
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final (logsPage, error) = await widget.authService.listDoorAccessLogs(
        siteCode: site.id,
        startDate: sevenDaysAgo,
        pageSize: 200,
      );



      if (logsPage == null || logsPage.logs.isEmpty) {

        _showMessage(

          error ??

              '${site.name} için son 7 güne ait kapı geçiş kaydı bulunamadı.',

        );

        return;

      }



      await PdfLogsService.printOrShareLogsPdf(

        logs: logsPage.logs,

        siteName: site.name,

        startDate: sevenDaysAgo,

        endDate: now,

      );

    } catch (e) {

      _showMessage('Geçiş raporu PDF oluşturulurken hata: $e');

    }

  }



  Future<void> _handleGlobalRefresh() async {
    final session = widget.authService.session;
    if (session == null) return;

    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
      case SirketMenuItem.ellerSerbest:
        await _loadDoorControlSites();
        if (_doorControlDoor != null) {
          await _loadDoorRuntimeStatus(_doorControlDoor!.id);
        }
        break;
      case SirketMenuItem.siteler:
      case SirketMenuItem.daireKullanicilariYonetimi:
        await _loadSites(force: true);
        if (_selectedSite != null) {
          await _selectSite(_selectedSite!);
        }
        break;
      case SirketMenuItem.kullaniciYonetimi:
        await _loadAllUsers(
          role: _allUsersRoleFilter,
          page: _allUsersCurrentPage,
          pageSize: _allUsersPageSize,
          search: _allUsersSearchQuery,
          force: true,
        );
        break;
      case SirketMenuItem.superUserYonetimi:
        await _loadManagedUsers(UserRole.superUser, force: true);
        break;
      case SirketMenuItem.siteYoneticileriYonetimi:
        await _loadManagedUsers(UserRole.siteManager, force: true);
        break;
      case SirketMenuItem.kayitliCihazlar:
        await _loadCompanyDevices(force: true);
        break;
      case SirketMenuItem.abonelikTalepleri:
        await _loadSubscriptionRequests(force: true);
        break;
      case SirketMenuItem.siteOnayTalepleri:
        await _loadPendingSiteApprovals(force: true);
        break;
      case SirketMenuItem.cihazEkle:
      case SirketMenuItem.bluetoothWifiKur:
      case SirketMenuItem.profilim:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = widget.authService.session!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titleForMenu(_selectedMenu),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${session.fullName} • ${_isResidentMode ? "Sakin Modu" : session.role.label}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? session.role.lightAccentColor : session.role.accentColor,
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.88),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.textDark,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        actions: [
          if (_canToggleDualMode)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isResidentMode = !_isResidentMode;
                    if (!_isResidentMode) {
                      _selectedMenu = SirketMenuItem.dashboard;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isResidentMode
                        ? const Color(0xFF2563EB).withValues(alpha: isDark ? 0.25 : 0.12)
                        : const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isResidentMode ? const Color(0xFF2563EB) : const Color(0xFF10B981),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isResidentMode ? Icons.admin_panel_settings_rounded : Icons.home_rounded,
                        size: 15,
                        color: _isResidentMode ? const Color(0xFF2563EB) : const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isResidentMode ? 'Yönetici Paneli' : 'Sakin Modu',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _isResidentMode
                              ? (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))
                              : (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (session.role != UserRole.superUser)
            IconButton(
              tooltip: 'Masaüstüne Widget Ekle',
              icon: Icon(
                Icons.widgets_outlined,
                color: isDark ? const Color(0xFF6EE7B7) : AppColors.emerald,
                size: 22,
              ),
              onPressed: () async {
                await DoorWidgetService.instance.requestPinWidget();
                _showMessage('Masaüstü widget ekleme isteği gönderildi.');
              },
            ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _handleGlobalRefresh,
          ),
          IconButton(
            tooltip: 'Çıkış Yap',
            icon: const Icon(Icons.logout_rounded, color: AppColors.roseLight, size: 22),
            onPressed: () => widget.authService.logout(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: YanMenu(
        fullName: session.fullName,
        userEmail: session.email,
        role: session.role,
        selectedItem: _selectedMenu,
        isResidentMode: _isResidentMode,
        canToggleMode: _canToggleDualMode,
        onToggleMode: () {
          Navigator.pop(context);
          setState(() {
            _isResidentMode = !_isResidentMode;
            if (!_isResidentMode) {
              _selectedMenu = SirketMenuItem.dashboard;
            }
          });
        },
        onSelect: _selectMenu,
        onLogout: () {
          Navigator.pop(context);
          widget.authService.logout();
        },
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 20.0;
            return RefreshIndicator(
              onRefresh: _handleGlobalRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(horizontalPadding),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: _buildContent(session),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

  }



  Widget _buildContent(UserSession session) {

    if (!_canAccessMenu(_selectedMenu, session.role)) {

      _selectedMenu = SirketMenuItem.dashboard;

    }



    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
      case SirketMenuItem.ellerSerbest:
        if (_isResidentMode ||
            ((session.role == UserRole.individual && (_doorControlSitesPage?.sites.isEmpty ?? true)) ||
            (session.role == UserRole.siteManager &&
                (_doorControlSitesPage?.sites.isEmpty ?? true) &&
                (_doorControlStructure?.doors.isEmpty ?? true)))) {
          return IndividualHomeView(
            session: session,
            authService: widget.authService,
            onRefreshAll: _loadInitialData,
          );
        }
        return DashboardView(

          session: session,

          sites: _doorControlSitesPage?.sites ?? const <SiteRecord>[],

          doors: _doorControlStructure?.doors ?? const <DoorRecord>[],

          selectedSite: _doorControlSite,

          selectedDoor: _doorControlDoor,

          runtimeStatus: _doorRuntimeStatus,

          isLoadingSites: _isLoadingDoorControlSites,

          isLoadingStructure: _isLoadingDoorControlStructure,

          isLoadingStatus: _isLoadingDoorStatus,

          isOpeningDoor: _isOpeningDoor,

          doorStatusError: _doorStatusError,

          canTryLocalDoorOpen:

              _doorControlDoor != null && _isDeviceLocalReachable,

          isPhoneOnWifi: _isPhoneOnWifi,

          onSelectSite: _selectDoorControlSite,

          onSelectDoor: _selectDoorControlDoor,

          onOpenDoor: _openDoor,

          onCreateGuestPass: () {

            if (_doorControlDoor != null) {

              CreateGuestPassDialog.show(

                context,

                door: _doorControlDoor!,

                authService: widget.authService,

                showMessage: _showMessage,

              );

            }

          },

          onDownloadCredentialsPdf: _doorControlSite != null

              ? () => _exportSiteCredentialsPdf(_doorControlSite!)

              : null,

          onDownloadLogsPdf: (_doorControlSite != null && _doorControlDoor != null)

              ? () => _exportDoorLogsPdf(_doorControlSite!, _doorControlDoor!)

              : (_doorControlSite != null

                  ? () => _exportSiteLogsPdf(_doorControlSite!)

                  : null),

          voiceDoorService: session.role == UserRole.apartmentOwner

              ? widget.voiceDoorService

              : null,

          authService: widget.authService,

        );



      case SirketMenuItem.profilim:

        if (session.role == UserRole.apartmentOwner) {

          return const SizedBox.shrink();

        }

        return ProfileView(

          session: session,

          formKey: _profileFormKey,

          fullNameController: _profileFullNameController,

          emailController: _profileEmailController,

          phoneController: _profilePhoneController,

          passwordController: _profilePasswordController,

          isSaving: _isSavingProfile,

          onSave: _saveProfile,

        );



      case SirketMenuItem.siteler:

      case SirketMenuItem.daireKullanicilariYonetimi:

        return SitesView(

          canManageSites:
              session.role == UserRole.superUser ||
              session.role == UserRole.siteManager,

          canManageApartmentUsers:

              session.role == UserRole.superUser ||

              session.role == UserRole.siteManager,

          canAssignDoorDevices:

              session.role == UserRole.superUser ||

              session.role == UserRole.siteManager,

          apartmentMode:

              _selectedMenu == SirketMenuItem.daireKullanicilariYonetimi,

          pageData: _sitesPage,

          sites: _sitesPage?.sites ?? const <SiteRecord>[],

          selectedSite: _selectedSite,

          selectedStructure: _selectedSiteStructure,

          isLoadingSites: _isLoadingSites,

          isLoadingStructure: _isLoadingSiteStructure,

          busyDeleteSites: _busyDeleteSites,

          busySiteApprovals: _busySiteApprovals,

          busyApartmentMails: _busyApartmentMails,

          onRefreshSites: () => _loadSites(force: true),

          onLoadPage: (page) => _loadSites(page: page),

          onOpenAddSite: () => _openSiteDialog(),

          onSelectSite: _selectSite,

          onEditSite: (site) => _openSiteDialog(site: site),

          onDeleteSite: _deleteSite,

          onApproveSite: (site) =>

              _resolveSiteApproval(siteCode: site.id, action: 'approve'),

          onRejectSite: (site) =>

              _resolveSiteApproval(siteCode: site.id, action: 'reject'),

          onEditApartmentResident: _openApartmentResidentDialog,

          onSendApartmentMail: _sendApartmentCredentials,

          onAssignDoorDevice: _assignDoorDevice,
          onOpenAddDoor: () => _openDoorDialog(),
          onEditDoor: (door) => _openDoorDialog(door: door),
          onDeleteDoor: _deleteDoor,
          onReplaceDevice: _openReplaceDeviceDialog,
          onManageDoorPermissions: _openDoorPermissionsDialog,
          onDeleteApartmentResident: _deleteApartmentResident,

          onConfigurePolicy: _openSiteSecurityPolicyDialog,

          onDownloadCredentialsPdf: _exportSiteCredentialsPdf,

          onDownloadLogsPdf: _exportSiteLogsPdf,

          onShowSiteJoinQr: _openSiteJoinQrDialog,
          onManageJoinRequests: _openManageJoinRequestsDialog,
          onShowResidentsAccordion: _openSiteResidentsAccordionDialog,
          isSuperUser: widget.authService.session?.role == UserRole.superUser,
          onApproveDeleteSite: _approveDeleteSite,
          onRejectDeleteSite: _rejectDeleteSite,
          onDeleteSiteWithEmail: _deleteSiteWithEmailVerification,
        );



      case SirketMenuItem.kullaniciYonetimi:
        return AllUsersView(
          session: session,
          pageData: _allUsersPage,
          users: _allUsersPage?.users ?? const <ManagedUserAccount>[],
          isLoading: _isLoadingAllUsers,
          busyActivationUsers: _busyActivationUsers,
          onLoadPage: ({role, page = 1, pageSize = 15, search}) => _loadAllUsers(
            role: role,
            page: page,
            pageSize: pageSize,
            search: search,
            force: true,
          ),
          onRefresh: () => _loadAllUsers(
            role: _allUsersRoleFilter,
            page: _allUsersCurrentPage,
            pageSize: _allUsersPageSize,
            search: _allUsersSearchQuery,
            force: true,
          ),
          onUpdateUser: _updateDirectoryUser,
          onToggleActivation: _toggleDirectoryUserActivation,
          onDeleteUser: _deleteDirectoryUser,
          onGetDatabaseHealth: widget.authService.getDatabaseHealth,
          onRunDatabaseCleanup: widget.authService.runDatabaseCleanup,
        );



      case SirketMenuItem.superUserYonetimi:

        return ManagedUsersView(

          role: UserRole.superUser,

          session: session,

          pageData: _managedPages[UserRole.superUser],

          users:

              _managedPages[UserRole.superUser]?.users ??

              const <ManagedUserAccount>[],

          loading: _loadingRoles.contains(UserRole.superUser),

          busyActivationUsers: _busyActivationUsers,

          onRefresh: () => _loadManagedUsers(UserRole.superUser, force: true),

          onLoadPage: (page) =>

              _loadManagedUsers(UserRole.superUser, page: page),

          onOpenAddDialog: () =>

              _openManagedUserDialog(role: UserRole.superUser),

          onToggleActivation: (user, val) => _toggleUserActivation(

            role: UserRole.superUser,

            user: user,

            value: val,

          ),

          onShowUserDetails: (user) =>

              _openManagedUserDialog(role: UserRole.superUser, user: user),

          onDeleteUser: (user) =>

              _deleteManagedUser(role: UserRole.superUser, user: user),

        );



      case SirketMenuItem.siteYoneticileriYonetimi:

        return ManagedUsersView(

          role: UserRole.siteManager,

          session: session,

          pageData: _managedPages[UserRole.siteManager],

          users:

              _managedPages[UserRole.siteManager]?.users ??

              const <ManagedUserAccount>[],

          loading: _loadingRoles.contains(UserRole.siteManager),

          busyActivationUsers: _busyActivationUsers,

          onRefresh: () => _loadManagedUsers(UserRole.siteManager, force: true),

          onLoadPage: (page) =>

              _loadManagedUsers(UserRole.siteManager, page: page),

          onOpenAddDialog: () =>

              _openManagedUserDialog(role: UserRole.siteManager),

          onToggleActivation: (user, val) => _toggleUserActivation(

            role: UserRole.siteManager,

            user: user,

            value: val,

          ),

          onShowUserDetails: (user) =>

              _openManagedUserDialog(role: UserRole.siteManager, user: user),

          onDeleteUser: (user) =>

              _deleteManagedUser(role: UserRole.siteManager, user: user),

        );



      case SirketMenuItem.cihazEkle:

        return DeviceAddView(

          onOpenQrRegistration: _openDeviceRegistrationFlow,

          onOpenManualRegistration: _openManualDeviceRegistrationFlow,

        );



      case SirketMenuItem.kayitliCihazlar:

        return CompanyDevicesView(

          pageData: _companyDevicesPage,

          devices: _companyDevicesPage?.devices ?? const <DeviceRecord>[],

          isSuperUser: session.role == UserRole.superUser,

          authService: widget.authService,

          isLoading: _isLoadingCompanyDevices,

          isBroadcastingOta: _isBroadcastingOtaCheck,

          onBroadcastOta: _broadcastOtaCheck,

          onRefresh: () => _loadCompanyDevices(force: true),

          onLoadPage: (page) => _loadCompanyDevices(page: page),

          onEditDevice: _editCompanyDevice,

          onAssignDeviceToDoor: _assignCompanyDeviceToDoor,

          onDeleteDevice: _deleteCompanyDevice,
          onDownloadFirmwareReportPdf: _exportFirmwareReportPdf,
          onRegisterNewDevice: _openClaimDeviceFlow,
        );



      case SirketMenuItem.bluetoothWifiKur:

        return BluetoothWifiView(onOpenWifiProvision: _openWifiProvision);



      case SirketMenuItem.abonelikTalepleri:

        return SubscriptionRequestsView(

          pageData: _subscriptionRequestsPage,

          requests:

              _subscriptionRequestsPage?.requests ??

              const <SubscriptionRequest>[],

          busyRequests: _busySubscriptionRequests,

          isLoading: _isLoadingSubscriptionRequests,

          onRefresh: () => _loadSubscriptionRequests(force: true),

          onLoadPage: (page) => _loadSubscriptionRequests(page: page),

          onApprove: (code) =>

              _resolveSubscriptionRequest(userCode: code, action: 'approve'),

          onReject: (code) =>

              _resolveSubscriptionRequest(userCode: code, action: 'reject'),

        );



      case SirketMenuItem.siteOnayTalepleri:

        return PendingSiteApprovalsView(

          pageData: _pendingSiteApprovalsPage,

          sites: _pendingSiteApprovalsPage?.sites ?? const <SiteRecord>[],

          busySiteApprovals: _busySiteApprovals,

          isLoading: _isLoadingPendingSiteApprovals,

          onRefresh: () => _loadPendingSiteApprovals(force: true),

          onLoadPage: (page) => _loadPendingSiteApprovals(page: page),

          onApprove: (siteCode) =>

              _resolveSiteApproval(siteCode: siteCode, action: 'approve'),

          onReject: (siteCode) =>

              _resolveSiteApproval(siteCode: siteCode, action: 'reject'),

        );

    }

  }

}

