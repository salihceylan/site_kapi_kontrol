import 'dart:async';

import 'package:flutter/material.dart';

import 'package:site_kapi_kontrol/models/apartment_record.dart';

import 'package:site_kapi_kontrol/models/device_page.dart';

import 'package:site_kapi_kontrol/models/device_record.dart';

import 'package:site_kapi_kontrol/models/door_access_log_record.dart';

import 'package:site_kapi_kontrol/models/door_record.dart';

import 'package:site_kapi_kontrol/models/door_runtime_status.dart';

import 'package:site_kapi_kontrol/models/managed_user_account.dart';

import 'package:site_kapi_kontrol/models/managed_user_page.dart';

import 'package:site_kapi_kontrol/models/site_page.dart';

import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';

import 'package:site_kapi_kontrol/models/site_structure_record.dart';

import 'package:site_kapi_kontrol/models/subscription_request.dart';

import 'package:site_kapi_kontrol/models/subscription_request_page.dart';

import 'package:site_kapi_kontrol/models/user_role.dart';

import 'package:site_kapi_kontrol/models/user_session.dart';

import 'package:site_kapi_kontrol/services/adaptive_poller.dart';

import 'package:site_kapi_kontrol/services/auth_service.dart';

import 'package:site_kapi_kontrol/services/pdf_credentials_service.dart';

import 'package:site_kapi_kontrol/services/pdf_device_firmware_service.dart';

import 'package:site_kapi_kontrol/services/pdf_logs_service.dart';

import 'package:site_kapi_kontrol/services/quick_actions_service.dart';

import 'package:site_kapi_kontrol/services/voice_door_service.dart';

import 'package:site_kapi_kontrol/services/door_widget_service.dart';

import 'package:site_kapi_kontrol/styles/app_colors.dart';

import 'package:site_kapi_kontrol/styles/role_theme.dart';

import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';

import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'package:site_kapi_kontrol/ui/dialogs/apartment_resident_dialog.dart';

import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';

import 'package:site_kapi_kontrol/ui/dialogs/device_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/claim_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/replace_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';

import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/invite_site_manager_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_permissions_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_join_qr_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_residents_accordion_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/manage_join_requests_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/submit_join_request_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/join_and_setup_view.dart';

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

  // Kapı durumu yoklaması (3 sn): yalnız kapı paneli görünürken ve uygulama ön plandayken ağ
  // isteği yapar; ardışık hatada üstel geri çekilir (tavan 30 sn), başarıda 3 sn'ye döner.
  late final AdaptivePoller _statusPoller = AdaptivePoller(
    interval: const Duration(seconds: 3),
    isActive: _isStatusPollingActive,
    poll: _pollDoorStatus,
  );

  // Yoklama sonuçları kapı panelini (DashboardView) tüm sayfayı yeniden kurmadan günceller:
  // sayaç artınca yalnız gövdedeki ValueListenableBuilder yeniden kurulur.
  final ValueNotifier<int> _doorPanelRevision = ValueNotifier<int>(0);

  // Ekrana en son kurulan kapı panelinin değerleri: yoklama sonucu bununla aynıysa yeniden kurulmaz.
  _DoorPanelSnapshot? _renderedDoorPanel;

  // Durum yoklamalarında üst üste binmeyi önleyen sayaç (in-flight koruması).
  int _statusRefreshesInFlight = 0;

  // Çok-siteli yarışları önleyen istek jetonları: her yeni istek jetonu artırır,
  // eski isteğin geç gelen yanıtı yeni seçimi ezmez.
  int _sitesRequestToken = 0;
  int _siteSelectionToken = 0;
  int _siteManagersToken = 0;
  int _doorControlSitesToken = 0;
  int _doorControlResidentToken = 0;
  int _doorControlSiteToken = 0;



  // Profil Form

  final _profileFormKey = GlobalKey<FormState>();

  late final TextEditingController _profileFullNameController;

  late final TextEditingController _profileEmailController;

  late final TextEditingController _profilePhoneController;

  late final TextEditingController _profilePasswordController;

  late final TextEditingController _profileCurrentPasswordController;

  bool _isSavingProfile = false;



  // Siteler & Hiyerarşi

  SitePage? _sitesPage;

  bool _isLoadingSites = false;

  SiteRecord? _selectedSite;

  SiteStructureRecord? _selectedSiteStructure;

  bool _isLoadingSiteStructure = false;

  SiteManagersData? _selectedSiteManagersData;

  bool _isLoadingSiteManagers = false;

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

  // Kapı açma komutu BAŞARIYLA gönderilince artar: kapı kartlarındaki DoorOpenButton'un başarı tikini
  // (successTick) tetikler. Sıfırlama gerekmez; yalnız artış anlamlıdır.
  int _doorOpenOkTick = 0;

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
  final GlobalKey<IndividualHomeViewState> _individualHomeKey = GlobalKey<IndividualHomeViewState>();

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

    _profileCurrentPasswordController = TextEditingController();



    _loadInitialData();

    _startStatusAutoRefreshTimer();

  }



  @override

  void dispose() {

    WidgetsBinding.instance.removeObserver(this);

    _statusPoller.dispose();

    _doorPanelRevision.dispose();

    _profileFullNameController.dispose();

    _profileEmailController.dispose();

    _profilePhoneController.dispose();

    _profilePasswordController.dispose();

    _profileCurrentPasswordController.dispose();

    super.dispose();

  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // C11: hesap pasifleştirilmiş/rolü değişmiş olabilir; sunucudaki /me ile eşitle.
      unawaited(widget.authService.refreshSession());
      _startStatusAutoRefreshTimer();
      if (_doorControlDoor != null) {
        _loadDoorRuntimeStatus(_doorControlDoor!.id, isBackgroundRefresh: true);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _statusPoller.stop();
    }
  }



  void _startStatusAutoRefreshTimer() {
    // Ön plana dönüş / ilk açılış: geri çekilme sıfırlanır, ilk tur 3 sn sonra (ön plana dönüşte
    // anlık yenileme didChangeAppLifecycleState içinde ayrıca yapılır).
    _statusPoller.resetBackoff();
    _statusPoller.start();
  }

  /// Durum yoklaması şu an gerekli mi? Kapı paneli ekranda olmalı, uygulama ön planda, bu sayfa
  /// opak bir sayfanın altında kalmamış (TickerMode kapalı değil) ve kapı açma sürmüyor olmalı.
  bool _isStatusPollingActive() {
    if (!mounted) return false;
    if (_doorControlDoor == null || _isOpeningDoor) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return false;
    if (!TickerMode.getValuesNotifier(context).value.enabled) return false;
    return _isDoorPanelVisible;
  }

  /// Çok kullanıcılı/rol akışlarında "bireysel ana ekran" (IndividualHomeView) gösterilen durum.
  /// [_buildContent] ile yoklama aynı koşulu paylaşır.
  bool _showsIndividualHome(UserSession session) {
    return _isResidentMode ||
        ((session.role == UserRole.individual &&
                (_doorControlSitesPage?.sites.isEmpty ?? true)) ||
            (session.role == UserRole.siteManager &&
                (_doorControlSitesPage?.sites.isEmpty ?? true) &&
                (_doorControlStructure?.doors.isEmpty ?? true)));
  }

  /// Kapı paneli (DashboardView: durum, kapı aç) şu an ekranda mı?
  bool get _isDoorPanelVisible {
    final session = widget.authService.session;
    if (session == null) return false;
    final menu = _canAccessMenu(_selectedMenu, session.role)
        ? _selectedMenu
        : SirketMenuItem.dashboard;
    if (menu != SirketMenuItem.dashboard && menu != SirketMenuItem.ellerSerbest) {
      return false;
    }
    return !_showsIndividualHome(session);
  }

  /// Yoklama turu: true başarılı, false hata (geri çekilme), null atlandı.
  Future<bool?> _pollDoorStatus() async {
    final door = _doorControlDoor;
    if (!mounted || door == null || _isOpeningDoor) return null;
    return _loadDoorRuntimeStatus(door.id, isBackgroundRefresh: true);
  }



  void _showMessage(String message) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),

    );

  }



  void _loadInitialData() {

    _loadDoorControlSites();

    // /manager/sites yalnızca site yöneticisi / süper kullanıcı içindir: bireysel kullanıcı ve
    // daire sakini her açılışta boşuna 403 (+ yetki sorgusu) almasın. "Siteler" menüsü açılınca
    // liste zaten force ile yüklenir.
    final role = widget.authService.session?.role;
    if (role == UserRole.siteManager || role == UserRole.superUser) {
      _loadSites();
    }

  }



  // --- Navigasyon & Menü ---

  bool _canAccessMenu(SirketMenuItem item, UserRole role) {
    if (item == SirketMenuItem.katilimVeKurulum) {
      return true;
    }

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
            item == SirketMenuItem.cihazEkle ||
            item == SirketMenuItem.profilim ||
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

      case SirketMenuItem.katilimVeKurulum:
        return 'Daireye Katıl & Cihaz Ekle';

      case SirketMenuItem.cihazEkle:
        final currentRole = widget.authService.session?.role;
        if (currentRole == UserRole.superUser) return 'Şirket Cihazı Kaydet';
        if (currentRole == UserRole.individual) return 'Yönetici Olarak Cihaz Ekle';
        return 'Cihaz Kaydet';

      case SirketMenuItem.kayitliCihazlar:
        final currentRole = widget.authService.session?.role;
        if (currentRole == UserRole.superUser) return 'Şirket Cihaz Envanteri';
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
    if (!mounted) return;
    if (_isLoadingSites && !force) return;

    final requestToken = ++_sitesRequestToken;
    setState(() => _isLoadingSites = true);

    try {
      final data = await widget.authService.listSites(page: page);

      // Daha yeni bir yükleme başladıysa bu (eski) yanıt yok sayılır.
      if (!mounted || requestToken != _sitesRequestToken) return;

      SiteRecord? siteToSelect;
      var refreshManagersOnly = false;

      setState(() {
        _isLoadingSites = false;
        _sitesPage = data;

        if (data.sites.isEmpty) {
          _selectedSite = null;
          _selectedSiteStructure = null;
          _selectedSiteManagersData = null;
          return;
        }

        final current = _selectedSite;
        final currentInList = current == null
            ? null
            : data.sites.where((s) => s.id == current.id).firstOrNull;

        if (preferredSiteId != null) {
          siteToSelect =
              data.sites.where((s) => s.id == preferredSiteId).firstOrNull ??
                  data.sites.first;
        } else if (currentInList == null) {
          siteToSelect = data.sites.first;
        } else {
          // Seçili nesneyi yeni listedeki kayıtla DEĞİŞTİR: güncelleme sonrası eski alanlar
          // (politika, ad vb.) ekranda kalmasın.
          _selectedSite = currentInList;
          refreshManagersOnly = true;
        }
      });

      if (siteToSelect != null) {
        unawaited(_selectSite(siteToSelect!));
      } else if (refreshManagersOnly && _selectedSite != null) {
        unawaited(_loadSiteManagers(_selectedSite!.id));
      }
    } catch (e) {
      if (!mounted || requestToken != _sitesRequestToken) return;

      setState(() => _isLoadingSites = false);

      if (force) {
        _showMessage(e.toString());
      }
    }
  }

  Future<void> _loadSiteManagers(int siteCode) async {
    if (!mounted) return;
    final token = ++_siteManagersToken;
    setState(() => _isLoadingSiteManagers = true);
    try {
      final managersData = await widget.authService.getSiteManagers(siteCode);
      if (!mounted || token != _siteManagersToken) return;
      if (_selectedSite?.id != siteCode) {
        // Bu arada başka bir site seçildi/silindi: eski sitenin yöneticileri gösterilmez.
        setState(() => _isLoadingSiteManagers = false);
        return;
      }
      setState(() {
        _selectedSiteManagersData = managersData;
        _isLoadingSiteManagers = false;
      });
    } catch (_) {
      if (!mounted || token != _siteManagersToken) return;
      setState(() => _isLoadingSiteManagers = false);
    }
  }

  Future<void> _selectSite(SiteRecord site) async {
    if (!mounted) return;
    final token = ++_siteSelectionToken;
    setState(() {
      _selectedSite = site;
      _selectedSiteStructure = null;
      _selectedSiteManagersData = null;
      _isLoadingSiteStructure = true;
      _isLoadingSiteManagers = true;
    });

    unawaited(_loadSiteManagers(site.id));

    final (structure, error) = await widget.authService.getSiteStructure(
      siteCode: site.id,
    );

    if (!mounted || token != _siteSelectionToken) return;
    if (_selectedSite?.id != site.id) {
      setState(() => _isLoadingSiteStructure = false);
      return;
    }

    setState(() {
      _isLoadingSiteStructure = false;
      _selectedSiteStructure = structure;
    });

    if (error != null && structure == null) _showMessage(error);
  }

  Future<void> _loadDoorControlSites({int? preferredSiteId}) async {
    if (!mounted) return;
    final session = widget.authService.session;

    if (session == null) return;

    final isResident = session.role == UserRole.apartmentOwner ||
        _isResidentMode ||
        (session.role == UserRole.individual && !_canToggleDualMode);

    if (isResident) {
      final residentToken = ++_doorControlResidentToken;
      setState(() => _isLoadingDoorControlStructure = true);
      // Masaüstü widget senkronu (ve boş listede temizlik) AuthService.listMyDoors içinde yapılır.
      final (doors, _) = await widget.authService.listMyDoors();

      if (!mounted || residentToken != _doorControlResidentToken) return;

      int? doorToSelect;
      setState(() {
        _isLoadingDoorControlStructure = false;

        if (doors == null) {
          return; // Hata: mevcut görünümü koru.
        }

        if (doors.isEmpty) {
          // Hiç kapı kalmadıysa eski kapı/durum ekranda kalmasın.
          _doorControlStructure = null;
          _doorControlDoor = null;
          _doorRuntimeStatus = null;
          return;
        }

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

        final current = _doorControlDoor;
        doorToSelect = (current != null && doors.any((d) => d.id == current.id))
            ? current.id
            : doors.first.id;
      });

      if (doorToSelect != null) {
        _selectDoorControlDoor(doorToSelect!, keepStatus: true);
      }

      if (doors != null) {
        unawaited(_checkAndStartVoiceAssistance(doors));
      }

      return;
    }

    final sitesToken = ++_doorControlSitesToken;
    setState(() => _isLoadingDoorControlSites = true);

    try {
      final data = await widget.authService.listSites(page: 1, pageSize: 100);

      if (!mounted || sitesToken != _doorControlSitesToken) return;

      int? siteToSelect;
      setState(() {
        _isLoadingDoorControlSites = false;
        _doorControlSitesPage = data;

        if (data.sites.isNotEmpty) {
          siteToSelect = preferredSiteId ??
              (_doorControlSite != null &&
                      data.sites.any((s) => s.id == _doorControlSite!.id)
                  ? _doorControlSite!.id
                  : data.sites.first.id);
        } else {
          _doorControlSite = null;
          _doorControlStructure = null;
          _doorControlDoor = null;
          _doorRuntimeStatus = null;
        }
      });

      if (siteToSelect != null) {
        unawaited(_selectDoorControlSite(siteToSelect!));
      }

      // Masaüstü widget için TEK kaynak: kullanıcının erişebildiği kapılar (listMyDoors).
      // Çağrı widget'ı senkronlar; liste boşsa widget temizlenir.
      unawaited(widget.authService.listMyDoors());
    } catch (_) {
      if (!mounted || sitesToken != _doorControlSitesToken) return;

      setState(() => _isLoadingDoorControlSites = false);
    }
  }

  Future<void> _selectDoorControlSite(int siteId) async {
    if (!mounted) return;
    final sites = _doorControlSitesPage?.sites;
    if (sites == null || sites.isEmpty) return;

    final site = sites.firstWhere(
      (s) => s.id == siteId,
      orElse: () => sites.first,
    );

    final token = ++_doorControlSiteToken;

    setState(() {
      _doorControlSite = site;
      _doorControlStructure = null;
      _doorControlDoor = null;
      _doorRuntimeStatus = null;
      _isLoadingDoorControlStructure = true;
    });

    final (structure, _) = await widget.authService.getSiteStructure(
      siteCode: site.id,
    );

    if (!mounted || token != _doorControlSiteToken) return;
    if (_doorControlSite?.id != site.id) {
      // Bu arada site değişti ya da silindi: eski sitenin yapısı uygulanmaz.
      setState(() => _isLoadingDoorControlStructure = false);
      return;
    }

    int? doorToSelect;
    setState(() {
      _isLoadingDoorControlStructure = false;
      _doorControlStructure = structure;

      if (structure != null && structure.doors.isNotEmpty) {
        doorToSelect = structure.doors.first.id;
      }
    });

    if (doorToSelect != null) {
      _selectDoorControlDoor(doorToSelect!);
    }

    if (structure != null &&
        structure.doors.isNotEmpty &&
        widget.authService.session?.role == UserRole.apartmentOwner) {
      unawaited(_checkAndStartVoiceAssistance(structure.doors));
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

    // Kullanıcı Eller Serbest ayarlarında otomatik dinlemeyi kapattıysa hiçbir şey yapma.
    if (!widget.voiceDoorService!.handsFreeAutoListen) {
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

  /// [userInitiated]: kullanıcı arayüzden açıkça seçtiyse widget'ın aktif kapısı da buna çekilir.
  /// [keepStatus]: aynı kapı yeniden seçiliyorsa (yenileme) mevcut durumu koruyup arka planda yeniler.
  void _selectDoorControlDoor(
    int doorId, {
    bool userInitiated = false,
    bool keepStatus = false,
  }) {
    final doors = _doorControlStructure?.doors;
    if (doors == null || doors.isEmpty) return;

    final door = doors.firstWhere(
      (d) => d.id == doorId,
      orElse: () => doors.first,
    );
    final sameDoor = _doorControlDoor?.id == door.id;
    final preserveStatus = keepStatus && sameDoor && _doorRuntimeStatus != null;

    setState(() {
      _doorControlDoor = door;
      if (!preserveStatus) {
        _doorRuntimeStatus = null;
      }
    });

    unawaited(_loadDoorRuntimeStatus(door.id, isBackgroundRefresh: preserveStatus));

    if (userInitiated) {
      widget.authService.selectWidgetDoor(door);
    }
  }

  /// Kapı durumunu yükler. Dönüş (yoklama zamanlayıcısı için): true = durum alındı ya da cihaza
  /// yerel ağdan ulaşılabiliyor, false = bulut da yerel ağ da başarısız (geri çekilme),
  /// null = tur atlandı/yok sayıldı (başka yoklama sürüyor, kapı değişti, sayfa kapandı).
  Future<bool?> _loadDoorRuntimeStatus(
    int doorId, {
    bool isBackgroundRefresh = false,
  }) async {
    if (!mounted) return null;
    // Önceki yoklama bitmeden arka plan yoklaması başlatılmaz (yavaş ağda istek yığılmaz).
    if (isBackgroundRefresh && _statusRefreshesInFlight > 0) return null;
    _statusRefreshesInFlight++;

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

      if (!mounted || _doorControlDoor?.id != doorId) return null;

      final isWifi = await widget.authService.isPhoneConnectedToLocalWifi();

      if (!mounted || _doorControlDoor?.id != doorId) return null;

      final assignedUid = _doorControlDoor?.assignedDeviceUid?.trim();

      final hasUid = assignedUid != null && assignedUid.isNotEmpty;

      bool localReachable = false;

      if (status?.mqttConnected != true && isWifi && hasUid) {
        localReachable = await widget.authService.isDeviceReachableOnLocalWifi(
          assignedUid,
        );
      }

      if (!mounted || _doorControlDoor?.id != doorId) return null;

      // Arka plan yoklamasında tüm sayfa yerine yalnız kapı paneli güncellenir ve görünür bir
      // değişiklik yoksa hiçbir şey yeniden kurulmaz; kullanıcı eylemlerinde (yükleme) sayfa kurulur.
      _updateDoorPanel(() {
        _isPhoneOnWifi = isWifi;

        _isDeviceLocalReachable = localReachable;

        if (status != null) {
          _doorRuntimeStatus = status;
        } else if (isBackgroundRefresh && !localReachable) {
          // Sunucu hata döndürdü VE yerel ağda da erişilemiyor → offline olarak işaretle
          if (_doorRuntimeStatus != null) {
            _doorRuntimeStatus = _doorRuntimeStatus!.copyWithOffline();
          }
        }

        // Yerelden gerçekten açılabiliyorsa (cihaz yerelde görünüyor + kapı politikası + geçerli
        // token) ve hata BULUT ERİŞİLEMEZLİĞİ ise (ağ/zaman aşımı/5xx/proxy; hata metnine değil
        // hata türüne bağlı) durum hatası gizlenir. Sunucunun iş hataları (403/404 vb.) gösterilir.
        final canLocal = _doorControlDoor != null &&
            localReachable &&
            widget.authService.canTryLocalDoorOpen(_doorControlDoor!);

        if (canLocal &&
            error != null &&
            widget.authService.isDoorStatusCloudUnreachable(doorId)) {
          _doorStatusError = null;
        } else {
          if (!isBackgroundRefresh || error == null) {
            _doorStatusError = error;
          }
        }
      }, scoped: isBackgroundRefresh);
      return status != null || localReachable;
    } catch (_) {
      // Background refresh hatalarında UI'ı bozma
      return false;
    } finally {
      _statusRefreshesInFlight--;
      if (mounted && !isBackgroundRefresh && _doorControlDoor?.id == doorId) {
        setState(() {
          _isLoadingDoorStatus = false;
        });
      }
    }
  }

  /// Kapı paneli alanlarını ([_doorRuntimeStatus], yükleme/hata/Wi-Fi bayrakları) günceller.
  ///
  /// [scoped] false ise klasik `setState` (tüm sayfa). [scoped] true (3 sn'lik arka plan yoklaması)
  /// ise sayfa yeniden kurulmaz: alanlar değişir ve panel ekrandaysa YALNIZ gövdedeki
  /// [_doorPanelRevision] dinleyicisi yeniden kurulur; sonuç öncekiyle aynıysa hiçbir şey kurulmaz.
  /// Panel ekranda değilse alanlar bir sonraki `build`'de okunur.
  void _updateDoorPanel(VoidCallback mutate, {required bool scoped}) {
    if (!mounted) return;
    if (!scoped) {
      setState(mutate);
      return;
    }
    mutate();
    if (!_isDoorPanelVisible) return;
    final shown = _renderedDoorPanel;
    if (shown != null && _DoorPanelSnapshot.of(this).sameAs(shown)) return;
    _doorPanelRevision.value++;
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

      // Başarı sinyali: "açılıyor" -> "hazır" geçişiyle AYNI karede gelir (düğme tikini gösterir).
      if (error == null) _doorOpenOkTick++;

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
      // Yalnızca yönetici anahtarı değiştirdiyse gönderilir (değişmediyse sunucuya dokunulmaz).
      emailVerified: result.emailVerified == user.emailVerified ? null : result.emailVerified,
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
    if (site == null && widget.authService.session?.role == UserRole.siteManager) {
      final created = await SetupSiteDialog.show(
        context,
        authService: widget.authService,
      );
      if (created == true) {
        await _loadSites(force: true);
      }
      return;
    }

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

  Future<void> _openInviteSiteManagerDialog() async {
    final site = _selectedSite;
    if (site == null) return;
    final invited = await InviteSiteManagerDialog.show(
      context,
      authService: widget.authService,
      siteCode: site.id,
      siteName: site.name,
    );
    if (invited == true) {
      await _loadSiteManagers(site.id);
    }
  }

  Future<void> _removeSiteManager(SiteManagerRecord mgr) async {
    final site = _selectedSite;
    if (site == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yönetici Yetkisini Kaldır'),
        content: Text(
          '${mgr.fullName} (${mgr.email}) kullanıcısının bu sitedeki yöneticilik yetkisini kaldırmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yetkiyi Kaldır'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final (success, message) = await widget.authService.removeSiteManager(
      site.id,
      mgr.userCode.toString(),
    );

    if (!mounted) return;

    if (success) {
      _showMessage(message ?? 'Yönetici yetkisi kaldırıldı.');
      await _loadSiteManagers(site.id);
    } else {
      _showMessage(message ?? 'Yetki kaldırılırken bir hata oluştu.');
    }
  }

  Future<void> _revokeSiteManagerInvitation(
    SiteManagerInvitationRecord inv,
  ) async {
    final site = _selectedSite;
    if (site == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daveti İptal Et'),
        content: Text(
          '${inv.email} adresine gönderilen yönetici davetini iptal etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Daveti İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final (success, message) =
        await widget.authService.revokeSiteManagerInvitation(
      site.id,
      inv.id,
    );

    if (!mounted) return;

    if (success) {
      _showMessage(message ?? 'Davet iptal edildi.');
      await _loadSiteManagers(site.id);
    } else {
      _showMessage(message ?? 'Davet iptal edilirken bir hata oluştu.');
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
    final claimedUid = await ClaimDeviceDialog.show(context, widget.authService);
    if (claimedUid != null && claimedUid.isNotEmpty) {
      await _loadCompanyDevices(force: true);
      await _loadDoorControlSites();
      if (!mounted) return;
      final hasSites = _doorControlSitesPage?.sites.isNotEmpty ?? false;
      if (!hasSites) {
        final result = await SetupSiteDialog.show(
          context,
          authService: widget.authService,
          deviceUid: claimedUid,
        );
        if (result == true) {
          _loadInitialData();
        }
      }
    }
  }

  Future<void> _openJoinRequestFlow() async {
    final success = await SubmitJoinRequestDialog.show(
      context,
      authService: widget.authService,
    );
    if (success == true) {
      _loadInitialData();
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

  Future<void> _toggleDeviceDefect(DeviceRecord device) async {
    if (device.isDefective) {
      final (ok, msg) = await widget.authService.setDeviceDefectStatus(
        deviceId: device.id,
        isDefective: false,
      );
      if (mounted) {
        _showMessage(msg ?? (ok ? 'Arıza kaydı kaldırıldı.' : 'İşlem başarısız.'));
        if (ok) _loadCompanyDevices(force: true);
      }
      return;
    }

    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cihazı Arızalı Olarak İşaretle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${device.deviceUid} cihazı için arıza kaydı oluşturulsun mu?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Arıza Nedeni (İsteğe bağlı)',
                hintText: 'Örn: Röle çekmiyor, Wi-Fi kopuyor...',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arızalı İşaretle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final (ok, msg) = await widget.authService.setDeviceDefectStatus(
        deviceId: device.id,
        isDefective: true,
        defectiveReason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
      );
      if (mounted) {
        _showMessage(msg ?? (ok ? 'Cihaz arızalı olarak işaretlendi.' : 'İşlem başarısız.'));
        if (ok) _loadCompanyDevices(force: true);
      }
    }
  }

  Future<void> _releaseDeviceOwnership(DeviceRecord device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cihazı Depoya Al'),
        content: Text(
          '${device.deviceUid} cihazının kapı ve sahip atamaları kaldırılarak cihaz serbest depoya alınacaktır.\n\nEmin misiniz?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Depoya Al', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final (ok, msg) = await widget.authService.releaseDeviceOwnership(deviceId: device.id);
      if (mounted) {
        _showMessage(msg ?? (ok ? 'Cihaz sahipliği sıfırlandı ve depoya alındı.' : 'İşlem başarısız.'));
        if (ok) {
          _loadCompanyDevices(force: true);
          _loadSites(force: true);
          _loadDoorControlSites();
        }
      }
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

      currentPassword: _profileCurrentPasswordController.text.isEmpty

          ? null

          : _profileCurrentPasswordController.text,

    );



    if (!mounted) return;

    setState(() => _isSavingProfile = false);



    if (error != null) {

      _showMessage(error);

    } else {

      _profilePasswordController.clear();

      _profileCurrentPasswordController.clear();

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

        emailVerified: result.emailVerified == user.emailVerified ? null : result.emailVerified,

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



  /// Haftalık rapor için logları SAYFA SAYFA çeker (sunucu sayfa başına en fazla 200 kayıt
  /// döndürür). Güvenlik sınırı: en fazla [_logPdfMaxPages] sayfa.
  static const int _logPdfPageSize = 200;
  static const int _logPdfMaxPages = 25;

  Future<({List<DoorAccessLogRecord> logs, String? error, bool truncated})>
      _fetchLogsForPdf({
    required int siteCode,
    int? doorId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final all = <DoorAccessLogRecord>[];
    String? error;
    var truncated = false;

    for (var page = 1; page <= _logPdfMaxPages; page++) {
      final (logPage, err) = await widget.authService.listDoorAccessLogs(
        siteCode: siteCode,
        doorId: doorId,
        startDate: startDate,
        endDate: endDate,
        page: page,
        pageSize: _logPdfPageSize,
      );
      if (logPage == null) {
        error = err;
        break;
      }
      all.addAll(logPage.logs);
      if (logPage.logs.isEmpty || page >= logPage.totalPages) {
        break;
      }
      if (page == _logPdfMaxPages) {
        truncated = true;
      }
    }
    return (logs: all, error: error, truncated: truncated);
  }

  Future<void> _exportDoorLogsPdf(SiteRecord site, DoorRecord door) async {
    try {
      _showMessage('${door.doorName} haftalık geçiş log raporu hazırlanıyor...');

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final result = await _fetchLogsForPdf(
        siteCode: site.id,
        doorId: door.id,
        startDate: sevenDaysAgo,
        endDate: now,
      );

      if (result.logs.isEmpty) {
        _showMessage(
          result.error ??
              '${door.doorName} için son 7 güne ait kapı geçiş kaydı bulunamadı.',
        );
        return;
      }
      if (result.error != null) {
        _showMessage('Bazı kayıtlar alınamadı; rapor eksik olabilir.');
      } else if (result.truncated) {
        _showMessage('Çok sayıda kayıt var; rapor en yeni kayıtlarla sınırlandırıldı.');
      }

      await PdfLogsService.printOrShareLogsPdf(
        logs: result.logs,
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

      final result = await _fetchLogsForPdf(
        siteCode: site.id,
        startDate: sevenDaysAgo,
        endDate: now,
      );

      if (result.logs.isEmpty) {
        _showMessage(
          result.error ??
              '${site.name} için son 7 güne ait kapı geçiş kaydı bulunamadı.',
        );
        return;
      }
      if (result.error != null) {
        _showMessage('Bazı kayıtlar alınamadı; rapor eksik olabilir.');
      } else if (result.truncated) {
        _showMessage('Çok sayıda kayıt var; rapor en yeni kayıtlarla sınırlandırıldı.');
      }

      await PdfLogsService.printOrShareLogsPdf(
        logs: result.logs,
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
        await _individualHomeKey.currentState?.loadAll();
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
      case SirketMenuItem.katilimVeKurulum:
      case SirketMenuItem.cihazEkle:
      case SirketMenuItem.bluetoothWifiKur:
      case SirketMenuItem.profilim:
        break;
    }
  }

  /// AppBar eylem düğmesi: 44 dp dokunma hedefi. `visualDensity` açıkça standart: masaüstünde varsayılan
  /// `compact` yoğunluğu hedefi 36 dp'ye indirirdi.
  Widget _appBarAction({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
    );
  }

  /// AppBar'daki "Sakin Modu / Yönetici Paneli" hapı (çift modlu roller): dokunma hedefi en az 44 dp.
  /// Dar ekranda (< 400 dp) ya da büyük yazıda (> 1.3x) yalnız ikon gösterilir (etiket Tooltip + Semantics
  /// ile korunur); etiketli hâl, kalan genişliği aşarsa üç nokta ile kısalır (taşma yok).
  /// [otherActions]: hapın yanındaki 48 dp'lik düğme sayısı (genişlik payı hesabı için).
  Widget _buildModeToggle(BuildContext context, {required int otherActions}) {
    final p = context.palette;
    final tone = _isResidentMode ? AppTone.primary : AppTone.success;
    final ink = tone.ink(p);
    final label = _isResidentMode ? 'Yönetici Paneli' : 'Sakin Modu';
    final width = MediaQuery.sizeOf(context).width;
    final iconOnly = width < 400 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
    // Hapa ayrılabilecek en büyük genişlik: ekran - menü düğmesi (48) - öteki eylemler (48'er) - boşluklar.
    final maxWidth = (width - 48 - otherActions * 48 - 6 - 16).clamp(44.0, double.infinity).toDouble();

    Widget pill = Material(
      color: tone.tint(p),
      shape: StadiumBorder(side: BorderSide(color: tone.hue, width: 1.2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          setState(() {
            _isResidentMode = !_isResidentMode;
            if (!_isResidentMode) {
              _selectedMenu = SirketMenuItem.dashboard;
            }
          });
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 44, minHeight: 44, maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : AppSpace.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isResidentMode ? Icons.admin_panel_settings_rounded : Icons.home_rounded,
                  size: iconOnly ? 20 : 16,
                  color: ink,
                ),
                if (!iconOnly) ...[
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // container: hap ekran okuyucuda AppBar düğümüne karışmasın, kendi düğümü (düğme + etiket) olsun.
    pill = iconOnly
        ? Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Semantics(container: true, button: true, label: label, child: pill),
          )
        : Semantics(container: true, button: true, child: pill);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      child: pill,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = widget.authService.session!;
    final palette = context.palette;
    // Alt başlık bloğu (başlık 18 + alt satır 12 punto) yazı ölçeğiyle büyür; AppBar yüksekliği de aynı
    // oranda artar (aksi hâlde araç çubuğu sıkışır ve 44 dp'lik eylem düğmeleri küçülür). Satır
    // yüksekliği AÇIKÇA 1,2'dir (aşağıdaki iki Text): verilmezse Material'in varsayılan metin stilinden
    // (temada bodyMedium.height = 1,4) miras kalır ve blok ölçek 1,0'da bile 50 dp'yi aşardı.
    // Yükseklik = alt boşluk 12 + aralık 2 + yuvarlama payı 2 + 1,2 x (ölçekli 18 + ölçekli 12): metin
    // motoru her satırın ascent/descent değerini tam sayıya yuvarlar (satır başına en çok ~1 dp sapma).
    final textScaler = MediaQuery.textScalerOf(context);
    final bottomHeight = 16 + 1.2 * (textScaler.scale(18) + textScaler.scale(12));
    final showWidgetAction = session.role != UserRole.superUser && DoorWidgetService.supportsPinRequest;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 0,
        leadingWidth: 48,
        title: null,
        elevation: 0,
        // Kaydırınca başlık bandı M3 yüzey tonuyla griye dönmesin (tema ile de aynı değer).
        scrolledUnderElevation: 0,
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
            _buildModeToggle(context, otherActions: showWidgetAction ? 3 : 2),
          // Widget iğneleme yalnızca mobilde çalışır; masaüstünde "gönderildi" mesajı yanıltıcı olurdu.
          if (showWidgetAction)
            _appBarAction(
              tooltip: 'Masaüstüne Widget Ekle',
              icon: Icon(
                Icons.widgets_outlined,
                color: AppTone.success.ink(palette),
                size: 20,
              ),
              onPressed: () async {
                await DoorWidgetService.instance.requestPinWidget();
                _showMessage('Masaüstü widget ekleme isteği gönderildi.');
              },
            ),
          _appBarAction(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _handleGlobalRefresh,
          ),
          _appBarAction(
            tooltip: 'Çıkış Yap',
            icon: Icon(Icons.logout_rounded, color: AppTone.danger.ink(palette), size: 20),
            onPressed: () => widget.authService.logout(),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(bottomHeight),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _titleForMenu(_selectedMenu),
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.fullName} • ${_isResidentMode ? "Sakin Modu" : session.role.label}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: session.role.tone.ink(palette),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
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
                padding: EdgeInsets.fromLTRB(horizontalPadding, 10.0, horizontalPadding, 56.0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    // RepaintBoundary: SingleChildScrollView içeriği her kaydırma karesinde baştan boyanır;
                    // yüzlerce daire/kullanıcı kartlı sayfalarda bu kare başına binlerce boyama demekti.
                    // Sınır sayesinde içerik önbellekteki katman olarak kaydırılır.
                    child: RepaintBoundary(
                      // Kapı durumu yoklaması yalnız bu dinleyiciyi yeniden kurar (Scaffold/AppBar/Drawer değil).
                      child: ValueListenableBuilder<int>(
                        valueListenable: _doorPanelRevision,
                        builder: (context, _, _) =>
                            _buildContent(widget.authService.session ?? session),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

  }



  /// Sayfa gövdesi: menü (ya da Sakin/Yönetici modu) değişince YALNIZ yeni içerik kısa bir solma + hafif
  /// kayma ile gelir ([PageEntry]); eski içerik hemen kalkar. `AnimatedSwitcher` bilerek KULLANILMAZ:
  /// iki görünüm aynı anda ağaçta kalır (GlobalKey çakışması, testlerde çift sonuç). Anahtar, erişimsiz
  /// menüyü panele çeviren [_buildContentView] çalıştıktan SONRA okunur. Yoklamayla yeniden kurulumda
  /// anahtar aynı kalır: animasyon yeniden başlamaz.
  Widget _buildContent(UserSession session) {
    final view = _buildContentView(session);
    return PageEntry(
      key: ValueKey<String>('${_selectedMenu.name}-$_isResidentMode'),
      child: view,
    );
  }

  Widget _buildContentView(UserSession session) {

    if (!_canAccessMenu(_selectedMenu, session.role)) {

      _selectedMenu = SirketMenuItem.dashboard;

    }



    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
      case SirketMenuItem.ellerSerbest:
        if (_showsIndividualHome(session)) {
          return IndividualHomeView(
            key: _individualHomeKey,
            session: session,
            authService: widget.authService,
            onRefreshAll: _loadInitialData,
          );
        }
        _renderedDoorPanel = _DoorPanelSnapshot.of(this);
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

          successTick: _doorOpenOkTick,

          doorStatusError: _doorStatusError,

          // "Yerel Ağda Aktif" yalnızca cihaz yerelde görünüyorsa VE yerel açma gerçekten
          // mümkünse (kapı politikası izin veriyor + sunucudan alınmış geçerli token var).
          canTryLocalDoorOpen: _doorControlDoor != null &&
              _isDeviceLocalReachable &&
              widget.authService.canTryLocalDoorOpen(_doorControlDoor!),

          isPhoneOnWifi: _isPhoneOnWifi,

          onSelectSite: _selectDoorControlSite,

          onSelectDoor: (doorId) =>
              _selectDoorControlDoor(doorId, userInitiated: true),

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

          // Sakin profilini güncelleyemez: boş sayfa yerine salt okunur hesap bilgileri.
          return ResidentProfileView(session: session);

        }

        return ProfileView(

          session: session,

          formKey: _profileFormKey,

          fullNameController: _profileFullNameController,

          emailController: _profileEmailController,

          phoneController: _profilePhoneController,

          passwordController: _profilePasswordController,

          currentPasswordController: _profileCurrentPasswordController,

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
          siteManagersData: _selectedSiteManagersData,
          isLoadingManagers: _isLoadingSiteManagers,
          onInviteSiteManager: _openInviteSiteManagerDialog,
          onRemoveSiteManager: _removeSiteManager,
          onRevokeSiteManagerInvitation: _revokeSiteManagerInvitation,
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

      case SirketMenuItem.katilimVeKurulum:
        return JoinAndSetupView(
          authService: widget.authService,
          session: session,
          onOpenClaimDevice: _openClaimDeviceFlow,
          onOpenJoinSite: _openJoinRequestFlow,
          onRefreshAll: _loadInitialData,
        );

      case SirketMenuItem.cihazEkle:
        if (session.role == UserRole.individual) {
          return DeviceAddView(
            title: 'Yönetici Olarak Cihaz Ekle',
            qrTitle: 'Kutu QR Kodunu Okut',
            qrDescription:
                'Cihaz ambalaj kutusundaki QR kodu kameraya göstererek cihazı hesabınıza bağlayın ve yeni site kurulumunu başlatın.',
            qrButtonLabel: 'QR Kodunu Okut',
            manualTitle: 'Seri No / UID ile Cihaz Ekle',
            manualDescription:
                'Kamera kullanamıyorsanız kutu üzerindeki Seri No veya UID kodunu elle girerek cihazı bağlayın.',
            manualButtonLabel: 'Seri No Gir',
            onOpenQrRegistration: _openClaimDeviceFlow,
            onOpenManualRegistration: _openClaimDeviceFlow,
          );
        }
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
          onToggleDefect: _toggleDeviceDefect,
          onReleaseOwnership: _releaseDeviceOwnership,
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

/// Ekrandaki kapı panelinin (DashboardView) yoklamayla değişebilen değerlerinin anlık görüntüsü.
/// Arka plan yoklaması sonucu ekrandakiyle aynıysa panel yeniden kurulmaz.
class _DoorPanelSnapshot {
  _DoorPanelSnapshot.of(_HomePageState state)
      : status = state._doorRuntimeStatus,
        isLoadingStatus = state._isLoadingDoorStatus,
        statusError = state._doorStatusError,
        isOpeningDoor = state._isOpeningDoor,
        isPhoneOnWifi = state._isPhoneOnWifi,
        canTryLocalDoorOpen = state._doorControlDoor != null &&
            state._isDeviceLocalReachable &&
            state.widget.authService.canTryLocalDoorOpen(state._doorControlDoor!);

  final DoorRuntimeStatus? status;
  final bool isLoadingStatus;
  final String? statusError;
  final bool isOpeningDoor;
  final bool isPhoneOnWifi;
  final bool canTryLocalDoorOpen;

  bool sameAs(_DoorPanelSnapshot other) {
    final a = status;
    final b = other.status;
    final sameStatus = identical(a, b) || (a != null && b != null && a.hasSameFieldsAs(b));
    return sameStatus &&
        isLoadingStatus == other.isLoadingStatus &&
        statusError == other.statusError &&
        isOpeningDoor == other.isOpeningDoor &&
        isPhoneOnWifi == other.isPhoneOnWifi &&
        canTryLocalDoorOpen == other.canTryLocalDoorOpen;
  }
}
