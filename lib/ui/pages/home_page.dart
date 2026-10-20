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

import 'package:site_kapi_kontrol/services/door_panel_requests.dart';

import 'package:site_kapi_kontrol/styles/app_colors.dart';

import 'package:site_kapi_kontrol/styles/role_theme.dart';

import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_actions.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_control_modal.dart';
import 'package:site_kapi_kontrol/ui/design/theme_toggle_button.dart';

import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'package:site_kapi_kontrol/ui/dialogs/apartment_pin_dialogs.dart';
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

import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';

import 'package:site_kapi_kontrol/services/module_access.dart';

import 'package:site_kapi_kontrol/ui/helpers/module_menu.dart';

import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/views/client_errors_view.dart';
import 'package:site_kapi_kontrol/ui/views/help_view.dart';
import 'package:site_kapi_kontrol/ui/views/platform_settings_view.dart';

import 'package:site_kapi_kontrol/ui/views/module_requests_view.dart';

import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_read_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_view.dart';
import 'package:site_kapi_kontrol/ui/views/document_view.dart';
import 'package:site_kapi_kontrol/ui/views/finance_view.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_resident_view.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_resident_view.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/ui/views/survey_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/survey_resident_view.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/ui/views/decision_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/decision_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/unread_announcement_card.dart';

import 'package:site_kapi_kontrol/ui/widgets/door_control_disabled_card.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_application_flow.dart';
import 'package:site_kapi_kontrol/ui/views/site_applications_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';
import 'package:site_kapi_kontrol/ui/views/visitor_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/visitor_resident_view.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/ui/views/contracts_view.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';



class HomePage extends StatefulWidget {

  const HomePage({

    super.key,

    required this.authService,

    this.quickActionsService,

    this.voiceDoorService,

    this.moduleAccess,

    this.announcementNotifier,

    this.doorPanelRequests,

  });

  /// Kapılar sayfasına girişten sonra sayfanın dokunuş ALMADIĞI süre: sayfa geçişi (200 ms) + kısa pay. Vitrindeki
  /// karta / hızlı "Kapıyı aç"a hızlı ikinci dokunuş, henüz görünmeyen KAPIYI AÇ düğmesine düşmesin (kazara kapı
  /// açılmaz). Kapı açma işlevi değişmez.
  static const Duration doorEntryGuard = Duration(milliseconds: 500);



  final AuthService authService;

  final QuickActionsService? quickActionsService;

  final VoiceDoorService? voiceDoorService;

  /// Platform modül sistemi: hangi modüllerin açık olduğu. Verilmezse sayfa kendi örneğini kurar
  /// (`getMyModules`; süper kullanıcıda her şey açık) ve sayfayla birlikte kapatır. Testler için.
  final ModuleAccess? moduleAccess;

  /// Platform Faz 3a: duyuru bildirim durumu (okunmamış rozeti, acil şerit, "yeni duyuru" olayları).
  /// Verilmezse sayfa kendi örneğini kurar (`getNotificationSummary` yoklaması) ve sayfayla birlikte
  /// kapatır. Testler için.
  final AnnouncementNotifier? announcementNotifier;

  /// Uygulama dışından (Android kapı widget'ı, kısayol, kapıyla ilgili derin bağlantı) gelen "Kapılar sayfasını aç"
  /// isteği: bekleyen istek kurulumda, yenisi gelince hemen uygulanır (kapı AÇMAZ). Geçiş Kontrol kapalıysa ya da
  /// kullanıcının kapı erişimi yoksa vitrinde kalınır.
  final DoorPanelRequests? doorPanelRequests;



  @override

  State<HomePage> createState() => _HomePageState();

}



class _HomePageState extends State<HomePage> with WidgetsBindingObserver {

  SirketMenuItem _selectedMenu = SirketMenuItem.dashboard;

  // Platform modül sistemi (Faz 1): menü/panel süzgeci. Girişten sonra, genel yenilemede ve kısa
  // aralıklı (AdaptivePoller) `getMyModules` ile tazelenir; hata/ilk yüklemede her şey açık sayılır.
  late final ModuleAccess _moduleAccess = widget.moduleAccess ??
      ModuleAccess(
        fetch: () => widget.authService.getMyModules(),
        isSuperUser: () => widget.authService.session?.role == UserRole.superUser,
        isActive: _isModulePollingActive,
        // Süper kullanıcı: çekmecedeki "Modül Talepleri" rozeti için bekleyen sayı aynı yoklamayla.
        fetchPendingCount: () async => (await widget.authService
                .listAdminModuleRequests(status: 'pending', limit: 1))
            .pendingCount,
        // Süper kullanıcı: çekmecedeki "Site Başvuruları" rozeti (hafif `summary` ucu), aynı yoklamayla.
        fetchPendingApplicationCount: () =>
            widget.authService.getAdminSiteApplicationsPendingCount(),
      );
  final GlobalKey<ModulesViewState> _modulesViewKey = GlobalKey<ModulesViewState>();
  final GlobalKey<ModuleRequestsViewState> _moduleRequestsViewKey =
      GlobalKey<ModuleRequestsViewState>();
  final GlobalKey<SiteApplicationsViewState> _siteApplicationsViewKey =
      GlobalKey<SiteApplicationsViewState>();

  // Site başvurusu (site yöneticisi olma): bireysel / daire kullanıcısının KENDİ başvurusunun durumu. Ekranlar
  // açılınca yüklenir; bekleyen başvuru varken ön planda ~30 sn'de bir yoklanır (bekleyen yokken zamanlayıcı
  // yoktur). Onaylanınca oturum / rol sunucudan yenilenir ve kullanıcı yönetici görünümüne geçer.
  late final SiteApplicationTracker _siteApplications = SiteApplicationTracker(
    fetch: () => widget.authService.getMySiteApplications(),
    cancel: (id) => widget.authService.cancelSiteApplication(id),
    isActive: _isModulePollingActive,
    // Başvuranlar ve site yöneticisi izlenir (sahip bağı olmayan yönetici de başvurabilir); süper kullanıcıda
    // `mine` ÇAĞRILMAZ.
    isEligible: () => tracksSiteApplications(widget.authService.session?.role),
  );
  StreamSubscription<SiteApplication>? _siteApplicationApprovals;

  // Yönetici panosunun başvuru kartı / "Yeni Site" kipi takipçinin şu imzasına bağlıdır; imza değişince sayfa
  // yeniden kurulur (başka durumlarda takipçi yalnız kendi görünümlerini tazeler).
  String _applicationsSignature = '';
  final GlobalKey<AuditLogViewState> _auditLogViewKey = GlobalKey<AuditLogViewState>();
  final GlobalKey<PlatformSettingsViewState> _platformSettingsKey =
      GlobalKey<PlatformSettingsViewState>();
  final GlobalKey<ClientErrorsViewState> _clientErrorsKey = GlobalKey<ClientErrorsViewState>();
  final GlobalKey<PeopleViewState> _peopleViewKey = GlobalKey<PeopleViewState>();
  final GlobalKey<AnnouncementsViewState> _announcementsKey =
      GlobalKey<AnnouncementsViewState>();
  final GlobalKey<FinanceViewState> _financeViewKey = GlobalKey<FinanceViewState>();
  final GlobalKey<MyFinanceViewState> _myFinanceViewKey = GlobalKey<MyFinanceViewState>();
  final GlobalKey<DocumentsViewState> _documentsKey = GlobalKey<DocumentsViewState>();
  final GlobalKey<WorkManagerViewState> _workManagerKey = GlobalKey<WorkManagerViewState>();
  final GlobalKey<WorkResidentViewState> _workResidentKey = GlobalKey<WorkResidentViewState>();
  final GlobalKey<ReservationManagerViewState> _reservationManagerKey = GlobalKey<ReservationManagerViewState>();
  final GlobalKey<ReservationResidentViewState> _reservationResidentKey = GlobalKey<ReservationResidentViewState>();
  final GlobalKey<SurveyManagerViewState> _surveyManagerKey = GlobalKey<SurveyManagerViewState>();
  final GlobalKey<SurveyResidentViewState> _surveyResidentKey = GlobalKey<SurveyResidentViewState>();
  final GlobalKey<DecisionManagerViewState> _decisionManagerKey = GlobalKey<DecisionManagerViewState>();
  final GlobalKey<DecisionResidentViewState> _decisionResidentKey = GlobalKey<DecisionResidentViewState>();
  final GlobalKey<VisitorManagerViewState> _visitorManagerKey = GlobalKey<VisitorManagerViewState>();
  final GlobalKey<VisitorResidentViewState> _visitorResidentKey = GlobalKey<VisitorResidentViewState>();
  final GlobalKey<ContractsViewState> _contractsKey = GlobalKey<ContractsViewState>();

  // Ziyaretçi ve Kargo: sakin çekmece rozeti (`GET /app/visitor-entries/summary`), duyuru kalıbındaki gibi
  // AdaptivePoller ile (ön planda ~60 sn; `visitor_log` modülü açık sitesi olmayan kullanıcıda ağ isteği yok).
  int _visitorUnread = 0;
  bool _visitorBadgeWasEligible = false;
  late final VisitorLogService _visitorBadgeService =
      VisitorLogService(authService: widget.authService);
  late final AdaptivePoller _visitorBadgePoller = AdaptivePoller(
    interval: const Duration(seconds: 60),
    isActive: _isModulePollingActive,
    poll: _pollVisitorUnread,
  );

  // Platform Faz 3a: duyuru bildirimi. `getNotificationSummary` AdaptivePoller ile (ön planda ~20 sn;
  // arka planda ya da uygun olmayan rolde ağ isteği yok) yoklanır; yeni duyuru olayı SnackBar'a, okunmamış
  // acil duyuru Panel'in üstündeki kırmızı şeride dönüşür.
  late final AnnouncementNotifier _announcements = widget.announcementNotifier ??
      AnnouncementNotifier(
        fetchSummary: () => widget.authService.getNotificationSummary(),
        fetchInbox: () => widget.authService.listMyAnnouncements(limit: 30),
        fetchAnnouncement: (id) => widget.authService.getMyAnnouncement(id),
        isActive: _isModulePollingActive,
        isEligible: _isAnnouncementPollingEligible,
      );
  StreamSubscription<AnnouncementAlert>? _announcementAlerts;
  String _lastDoorModuleSignature = '';
  UserRole? _lastSeenRole;

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

  final Set<int> _busyApartmentPins = <int>{};



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
  // Panel = modül vitrini: borç özeti (sakin) aşağı çekip yenilemeyle tazelenir.
  final GlobalKey<ModuleShowcaseViewState> _showcaseKey = GlobalKey<ModuleShowcaseViewState>();

  // Çekmece açık mı (Scaffold.onDrawerChanged)? Açıkken geri tuşu ÖNCE çekmeceyi kapatır: PopScope geri tuşuna izin verir
  // ve çekmecenin yerel geçmişi pop'u karşılar (sayfa değişmez). Yalnız PopScope'u yeniden kurar.
  final ValueNotifier<bool> _drawerOpen = ValueNotifier<bool>(false);

  // Kapılar sayfasına girişten sonra kısa süre ([HomePage.doorEntryGuard]) sayfa dokunuş almaz: bkz. [_armDoorEntryGuard].
  final ValueNotifier<bool> _doorEntryGuard = ValueNotifier<bool>(false);
  Timer? _doorEntryGuardTimer;

  // Gövde kaydırma alanının içeriği (kaydırma konumuna buradan ulaşılır) ve son çizilen sayfa: sayfa değişince kaydırma
  // en üste alınır ([_jumpBodyToTop]).
  final GlobalKey _bodyContentKey = GlobalKey();
  String? _bodyScrollPage;

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

    _initModuleAccess();

    _initAnnouncements();

    _siteApplicationApprovals = _siteApplications.approvals.listen(_onSiteApplicationApproved);

    _siteApplications.addListener(_onSiteApplicationsChanged);

    // Site yöneticisi: oturum açılırken `mine` BİR kez okunur (`requires_application`: anlık "Site Ekle" mi,
    // başvuru mu?). Bireysel / daire kullanıcısında ekranlar açılırken okunur; süper kullanıcıda hiç okunmaz.
    if (session?.role == UserRole.siteManager) {
      unawaited(_siteApplications.ensureLoaded());
    }



    _loadInitialData();

    _startStatusAutoRefreshTimer();

    // Widget / kısayol / derin bağlantıdan "Kapılar sayfasını aç": soğuk açılışta bekleyen istek ilk karede uygulanır.
    widget.doorPanelRequests?.addListener(_onDoorPanelRequested);
    if (widget.doorPanelRequests?.isPending ?? false) _onDoorPanelRequested();

  }



  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doorPanelRequests != widget.doorPanelRequests) {
      oldWidget.doorPanelRequests?.removeListener(_onDoorPanelRequested);
      widget.doorPanelRequests?.addListener(_onDoorPanelRequested);
      if (widget.doorPanelRequests?.isPending ?? false) _onDoorPanelRequested();
    }
  }



  @override

  void dispose() {

    WidgetsBinding.instance.removeObserver(this);

    widget.doorPanelRequests?.removeListener(_onDoorPanelRequested);

    _doorEntryGuardTimer?.cancel();

    _doorEntryGuard.dispose();

    _drawerOpen.dispose();

    _statusPoller.dispose();

    _disposeAnnouncements();

    unawaited(_siteApplicationApprovals?.cancel());

    _siteApplications.removeListener(_onSiteApplicationsChanged);

    _siteApplications.dispose();

    _disposeModuleAccess();

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
      // Arka plandayken modül değişmiş olabilir (yönetici kapattı/açtı): ön plana dönüşte hemen çek.
      _moduleAccess.resetBackoff();
      unawaited(_moduleAccess.refresh());
      // Arka plandayken yeni duyuru gelmiş olabilir: ön plana dönüşte hemen çek.
      _announcements.resetBackoff();
      unawaited(_announcements.refresh());
      // Arka plandayken yeni kargo / ziyaretçi kaydı gelmiş olabilir: sakin rozeti hemen tazelenir.
      _refreshVisitorBadge();
      // Arka plandayken başvuru karara bağlanmış olabilir: bekleyen başvuru biliniyorsa hemen oku.
      if (_siteApplications.pending != null) {
        _siteApplications.resetBackoff();
        unawaited(_siteApplications.refresh());
      }
      unawaited(_loadSuperDoorModule());
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

  /// Kapı paneli (DashboardView: durum, kapı aç) şu an ekranda mı? "Panel" artık modül vitrinidir; kapı paneli
  /// "Kapılar" öğesinin arkasındadır, durum yoklaması yalnız orada çalışır.
  bool get _isDoorPanelVisible {
    final session = widget.authService.session;
    if (session == null) return false;
    final menu = _canAccessMenu(_selectedMenu, session.role)
        ? _selectedMenu
        : SirketMenuItem.dashboard;
    if (menu != SirketMenuItem.kapilar && menu != SirketMenuItem.ellerSerbest) {
      return false;
    }
    // Geçiş Kontrol kapalıyken Panel'de kapı kartı yoktur: durum yoklaması da gerekmez.
    if (!_showsIndividualHome(session) && _isDoorControlClosed(session)) {
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



  // --- Platform modül sistemi ---

  /// Modül yoklaması şu an gerekli mi? Uygulama ön planda ve bu sayfa opak bir sayfanın altında değil.
  bool _isModulePollingActive() {
    if (!mounted) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return false;
    return TickerMode.getValuesNotifier(context).value.enabled;
  }

  void _initModuleAccess() {
    _moduleAccess.addListener(_onModulesChanged);
    widget.authService.addListener(_onAuthChanged);
    _lastDoorModuleSignature = _doorModuleSignature();
    _lastSeenRole = widget.authService.session?.role;
    unawaited(_moduleAccess.refresh());
    _moduleAccess.start();
  }

  void _disposeModuleAccess() {
    _moduleAccess.removeListener(_onModulesChanged);
    widget.authService.removeListener(_onAuthChanged);
    if (widget.moduleAccess == null) {
      _moduleAccess.dispose();
    } else {
      _moduleAccess.stop();
    }
  }

  /// Oturum değişimi: çıkışta modül durumu temizlenir, rol değişince (örn. cihaz sahiplenip site
  /// yöneticisi olma) yeniden çekilir.
  void _onAuthChanged() {
    final session = widget.authService.session;
    if (session == null) {
      _lastSeenRole = null;
      _moduleAccess.clear();
      _announcements.clear();
      _siteApplications.clear();
      return;
    }
    if (_lastSeenRole != session.role) {
      final previousRole = _lastSeenRole;
      _lastSeenRole = session.role;
      unawaited(_moduleAccess.refresh());
      // Rol değişti (örn. site başvurusu onaylandı): yeni rolün Panel verisi (siteler / kapılar) yeniden
      // okunur. Başvuru durumu: izlenmeyen role (süper kullanıcı) geçildiyse atılır; yönetici <-> başvuran
      // geçişinde (onay) `requires_application` değişir, yeniden okunur; bireysel <-> daire kullanıcısı aynı
      // kullanıcıdır, durum korunur (açık ekranlar kendi `didUpdateWidget`inde tazeler).
      if (!tracksSiteApplications(session.role)) {
        _siteApplications.clear();
      } else if (previousRole == UserRole.siteManager || session.role == UserRole.siteManager) {
        unawaited(_siteApplications.refresh());
      }
      _loadInitialData();
      // Rol değişince alıcı olma durumu değişebilir: eski duyuru durumu atılır, yeniden okunur.
      _announcements.clear();
      unawaited(_announcements.refresh());
    }
  }

  /// Takipçi değişti: yalnız YÖNETİCİ panosu etkilenir (başvuru kartı, "Yeni Site" kipi). İmza değişmedikçe
  /// (örn. yalnız yükleniyor göstergesi) sayfa yeniden kurulmaz.
  void _onSiteApplicationsChanged() {
    if (!mounted || widget.authService.session?.role != UserRole.siteManager) return;
    final latest = _siteApplications.latest;
    final signature =
        '${_siteApplications.requiresApplication}|${_siteApplications.pending?.id}|${latest?.id}|${latest?.status}';
    if (signature == _applicationsSignature) return;
    _applicationsSignature = signature;
    setState(() {});
  }

  /// Modül durumu değişti: menü/panel yeniden kurulur; kapıyla ilgili site kümesi değiştiyse Panel
  /// verisi (site listesi ve seçili site) yeniden çekilir.
  void _onModulesChanged() {
    if (!mounted || widget.authService.session == null) return;
    setState(() {});
    _kickAnnouncements();
    final signature = _doorModuleSignature();
    if (signature != _lastDoorModuleSignature) {
      _lastDoorModuleSignature = signature;
      unawaited(_loadDoorControlSites());
    }
  }

  /// Geçiş Kontrol'ü KAPALI sitelerin kodları (sıralı, virgüllü); süzgeç yoksa boş.
  String _doorModuleSignature() {
    final result = _moduleAccess.isFiltering ? _moduleAccess.result : null;
    if (result == null) return '';
    final off = result.doorAccessSites
        .where((s) => !s.isEnabled(PlatformModuleCodes.doorControl))
        .map((s) => s.siteCode)
        .toList()
      ..sort();
    return off.join(',');
  }

  /// Menüden gizlenecek öğeler: Geçiş Kontrol bağlı olunan TÜM sitelerde kapalıyken kapı öğeleri; daire sakini rolünde
  /// kapı erişimi olan sitesi ve kapısı olmayan hesapta da (yalnız görevli / kurul / site üyeliği bağı). Kapı listesi
  /// doluysa ([_hasResidentSignal]) kapı öğeleri kalır. Bkz. [hiddenMenuItemsFor].
  Set<SirketMenuItem> _hiddenMenuItems(UserRole role) =>
      hiddenMenuItemsFor(role, _moduleAccess, hasDoors: _hasResidentSignal);

  /// Çekmecede görünen öğeler (rol listesi + ek öğeler - gizlenenler). ÇEKMECE de Panel vitrini de bu listeyi kullanır:
  /// görünürlük kuralı tek yerde ([YanMenu.visibleItems]) olduğundan kapalı bir modül vitrinde de asla görünmez.
  List<SirketMenuItem> _visibleMenuItems(UserSession session) => YanMenu.visibleItems(
        role: session.role,
        isResidentMode: _isResidentMode,
        canToggleMode: _canToggleDualMode,
        additionalItems: _extraMenuItems(session.role),
        hiddenItems: _hiddenMenuItems(session.role),
      );

  /// Çekmece ve vitrin rozet sayıları (aynı harita): bekleyen modül talebi / site başvurusu (süper kullanıcı),
  /// okunmamış duyuru ve görülmemiş ziyaretçi kaydı (sakin).
  Map<SirketMenuItem, int> _menuBadgeCounts(UserSession session) => <SirketMenuItem, int>{
        if (session.role == UserRole.superUser)
          SirketMenuItem.modulTalepleri: _moduleAccess.pendingRequestCount ?? 0,
        if (session.role == UserRole.superUser)
          SirketMenuItem.siteBasvurulari: _moduleAccess.pendingApplicationCount ?? 0,
        if (_hasAnnouncementInbox(session.role))
          SirketMenuItem.duyurular: _announcements.unreadCount,
        if (_visitorResidentSites(session.role).isNotEmpty)
          SirketMenuItem.ziyaretcilerim: _visitorUnread,
      };

  /// Rozetin ekran okuyucu sözcüğü ("3 okunmamış"); verilmeyen öğede "bekleyen".
  static const Map<SirketMenuItem, String> _menuBadgeNouns = <SirketMenuItem, String>{
    SirketMenuItem.duyurular: 'okunmamış',
    SirketMenuItem.ziyaretcilerim: 'görülmemiş',
  };

  // --- Kişi ve Daire Kayıtları (Faz 2a) ---

  /// Yönettiği (ya da süper kullanıcıda tüm) siteler için yazma yetkisi: süper kullanıcı ve site
  /// yöneticisi (yönetici modunda).
  bool _canManagePeople(UserRole role) =>
      role == UserRole.superUser ||
      (role == UserRole.siteManager && !_isResidentMode);

  /// Kurul üyesi olunan siteler (salt okunur Kişiler erişimi).
  List<PeopleSite> _boardPeopleSites() => <PeopleSite>[
        for (final site in _moduleAccess.boardMemberSites)
          PeopleSite(code: site.siteCode, name: site.siteName),
      ];

  /// Kişiler ekranına erişim: yönetim yetkisi ya da en az bir sitede kurul üyeliği. Görevli (STAFF) ve
  /// sıradan sakin erişemez.
  bool _canAccessPeople(UserRole role) =>
      _canManagePeople(role) || _moduleAccess.boardMemberSites.isNotEmpty;

  /// Rolün kendi menü listesinde olmayan ek öğeler: kurul üyesine "Kişiler"; alıcısı olabilecek rollere
  /// (daire sakini, yönetici / süper kullanıcı, kurul üyesi) "Duyurular".
  Set<SirketMenuItem> _extraMenuItems(UserRole role) => <SirketMenuItem>{
        // Kapı paneli ("Panel" artık vitrin): her rolde; Geçiş Kontrol kapalıyken ve daire sakini rolünde kapı erişimi /
        // kapısı yokken [_hiddenMenuItems] gizler.
        SirketMenuItem.kapilar,
        if (_moduleAccess.boardMemberSites.isNotEmpty) SirketMenuItem.kisiler,
        if (_canAccessAnnouncements(role)) SirketMenuItem.duyurular,
        if (_canAccessFinance(role)) SirketMenuItem.finans,
        if (_hasFinanceInbox(role)) SirketMenuItem.borcum,
        if (_canAccessDocuments(role)) SirketMenuItem.belgeler,
        if (_canAccessWorkManage(role)) SirketMenuItem.talepler,
        if (_workResidentSites(role).isNotEmpty) SirketMenuItem.taleplerim,
        if (_canAccessReservationManage(role)) SirketMenuItem.rezervasyonlar,
        if (_reservationResidentSites(role).isNotEmpty) SirketMenuItem.rezervasyon,
        if (_canAccessSurveyManage(role)) SirketMenuItem.anketler,
        if (_surveyResidentSites(role).isNotEmpty) SirketMenuItem.anket,
        if (_canAccessDecisionManage(role)) SirketMenuItem.kararDefteri,
        if (_decisionResidentSites(role).isNotEmpty) SirketMenuItem.kararlar,
        if (_canAccessVisitorManage(role)) SirketMenuItem.ziyaretciKayitlari,
        if (_visitorResidentSites(role).isNotEmpty) SirketMenuItem.ziyaretcilerim,
        if (_canAccessContracts(role)) SirketMenuItem.sozlesmeler,
      };

  // --- Belgeler (Faz 3b-A) ---

  /// Belgeler ekranının YÖNETİM görünümündeki siteler: `documents` modülü AÇIK olan yönetilen siteler (yazma;
  /// yalnız yönetici modunda) ve kurul üyesi olunan siteler (salt okunur). Süper kullanıcıda boştur (ekran tüm
  /// siteleri çeker). FAIL-OPEN YOK: modül verisi hiç gelmediyse hiçbir site yoktur ve menü AÇILMAZ; sitede
  /// `documents` kodu yoksa modül KAPALI sayılır (katalog varsayılanı). Sunucu her çağrıda yetkiyi ve modül
  /// durumunu yine doğrular.
  List<PeopleSite> _documentManageSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <PeopleSite>[];
    final canManage = _canManagePeople(role);
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.documents))
          if (site.role == 'manager' && canManage)
            PeopleSite(code: site.siteCode, name: site.siteName, canWrite: true)
          else if (site.isBoardMember)
            PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// Belgeler ekranının SAKİN görünümündeki siteler: alıcısı olabilecek ve `documents` modülü AÇIK siteler.
  /// Yalnız daire sakini ve sakin modundaki yönetici için; süper kullanıcı, bireysel kullanıcı ve yalnız-görevli
  /// bağ için boş. Modül verisi yokken (fail-open) boştur.
  List<PeopleSite> _documentResidentSites(UserRole role) {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return const <PeopleSite>[];
      case UserRole.siteManager:
        if (!_isResidentMode) return const <PeopleSite>[];
      case UserRole.apartmentOwner:
        break;
    }
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.documents))
          PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// "Belgeler" menüsü: süper kullanıcı ya da `documents` modülü açık bir sitede yönetici / kurul üyesi / sakin.
  /// Görevli (STAFF) ve bireysel kullanıcı için yoktur.
  bool _canAccessDocuments(UserRole role) =>
      role == UserRole.superUser ||
      _documentManageSites(role).isNotEmpty ||
      _documentResidentSites(role).isNotEmpty;

  // --- İş Takibi (arıza, bakım, talep) ---

  /// "Talepler" (yönetim) ekranındaki siteler: `work_tracking` modülü AÇIK olan siteler. Yönetici (yönetici modunda)
  /// yazar; görevli (STAFF) kendine atanmış / atanmamış talepleri yazar; kurul üyesi SALT OKUR. Süper kullanıcıda
  /// boştur (ekran tüm siteleri çeker). FAIL-OPEN YOK: modül verisi hiç gelmediyse hiçbir site yoktur ve menü
  /// AÇILMAZ; sitede `work_tracking` kodu yoksa modül KAPALI sayılır (katalog varsayılanı). Sunucu yine de her
  /// çağrıda yetkiyi ve modül durumunu doğrular.
  List<WorkTrackingSite> _workManageSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <WorkTrackingSite>[];
    final canManage = _canManagePeople(role);
    return <WorkTrackingSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.workTracking))
          if (site.role == 'manager' && canManage)
            WorkTrackingSite(code: site.siteCode, name: site.siteName)
          else if (site.role == 'staff')
            WorkTrackingSite(code: site.siteCode, name: site.siteName, access: WorkSiteAccess.staff)
          else if (site.isBoardMember)
            WorkTrackingSite(code: site.siteCode, name: site.siteName, access: WorkSiteAccess.board),
    ];
  }

  /// "Taleplerim" (sakin) ekranındaki siteler: alıcısı olabilecek ve `work_tracking` modülü AÇIK siteler. Yalnız
  /// daire sakini ve sakin modundaki yönetici için; süper kullanıcı, bireysel kullanıcı ve yalnız-görevli bağ için
  /// boş. Modül verisi yokken (fail-open) boştur.
  List<PeopleSite> _workResidentSites(UserRole role) {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return const <PeopleSite>[];
      case UserRole.siteManager:
        if (!_isResidentMode) return const <PeopleSite>[];
      case UserRole.apartmentOwner:
        break;
    }
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.workTracking))
          PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// "Talepler" menüsü: süper kullanıcı ya da `work_tracking` modülü açık bir sitede yönetici / görevli / kurul üyesi.
  bool _canAccessWorkManage(UserRole role) =>
      role == UserRole.superUser || _workManageSites(role).isNotEmpty;

  // --- Rezervasyon ve Konsiyerj ---

  /// "Rezervasyonlar" (yönetim) ekranındaki siteler: `reservation` modülü AÇIK olan siteler. Yönetici (yönetici
  /// modunda) alan tanımlar ve karar verir; görevli (STAFF) karar verir; kurul üyesi SALT OKUR. Süper kullanıcıda
  /// boştur (ekran tüm siteleri çeker). FAIL-OPEN YOK: modül verisi hiç gelmediyse hiçbir site yoktur ve menü
  /// AÇILMAZ; sitede `reservation` kodu yoksa modül KAPALI sayılır (katalog varsayılanı). Sunucu yine de her
  /// çağrıda yetkiyi ve modül durumunu doğrular.
  List<ReservationSite> _reservationManageSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <ReservationSite>[];
    final canManage = _canManagePeople(role);
    return <ReservationSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.reservation))
          if (site.role == 'manager' && canManage)
            ReservationSite(code: site.siteCode, name: site.siteName)
          else if (site.role == 'staff')
            ReservationSite(code: site.siteCode, name: site.siteName, access: ReservationSiteAccess.staff)
          else if (site.isBoardMember)
            ReservationSite(code: site.siteCode, name: site.siteName, access: ReservationSiteAccess.board),
    ];
  }

  /// "Rezervasyon" (sakin) ekranındaki siteler: alıcısı olabilecek ve `reservation` modülü AÇIK siteler. Yalnız daire
  /// sakini ve sakin modundaki yönetici için; süper kullanıcı, bireysel kullanıcı ve yalnız-görevli bağ için boş.
  /// Modül verisi yokken (fail-open) boştur.
  List<PeopleSite> _reservationResidentSites(UserRole role) {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return const <PeopleSite>[];
      case UserRole.siteManager:
        if (!_isResidentMode) return const <PeopleSite>[];
      case UserRole.apartmentOwner:
        break;
    }
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.reservation))
          PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// "Rezervasyonlar" menüsü: süper kullanıcı ya da `reservation` modülü açık bir sitede yönetici / görevli / kurul üyesi.
  bool _canAccessReservationManage(UserRole role) =>
      role == UserRole.superUser || _reservationManageSites(role).isNotEmpty;

  // --- Anket ve Oylama (F11.01) ---

  /// "Anket ve Oylama" (yönetim) ekranındaki siteler: `survey` modülü AÇIK siteler. Yönetici (yönetici modunda) yazar;
  /// kurul üyesi SALT OKUR (oy verenleri göremez); görevli ve sakin GÖREMEZ. Süper kullanıcıda boştur (ekran tüm
  /// siteleri çeker). FAIL-OPEN YOK: modül verisi yoksa site yoktur; `survey` kodu yoksa modül KAPALI sayılır.
  List<SurveySite> _surveyManageSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <SurveySite>[];
    final canManage = _canManagePeople(role);
    return <SurveySite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.survey))
          if (site.role == 'manager' && canManage)
            SurveySite(code: site.siteCode, name: site.siteName)
          else if (site.isBoardMember)
            SurveySite(code: site.siteCode, name: site.siteName, access: SurveySiteAccess.board),
    ];
  }

  /// "Anketler" (sakin) ekranındaki siteler: alıcısı olabilecek ve `survey` modülü AÇIK siteler (Rezervasyon kuralı).
  List<PeopleSite> _surveyResidentSites(UserRole role) {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return const <PeopleSite>[];
      case UserRole.siteManager:
        if (!_isResidentMode) return const <PeopleSite>[];
      case UserRole.apartmentOwner:
        break;
    }
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.survey))
          PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// "Anket ve Oylama" menüsü: süper kullanıcı ya da `survey` modülü açık bir sitede yönetici / kurul üyesi.
  bool _canAccessSurveyManage(UserRole role) =>
      role == UserRole.superUser || _surveyManageSites(role).isNotEmpty;

  // --- Karar Defteri ---

  /// "Karar Defteri" (yönetim) ekranındaki siteler: `decision_book` modülü AÇIK siteler. Yönetici (yönetici modunda)
  /// yazar ve kesinleştirir; kurul üyesi taslaklar dahil SALT OKUR; görevli ve sakin GÖREMEZ. Süper kullanıcıda boştur
  /// (ekran tüm siteleri çeker). FAIL-OPEN YOK: modül verisi yoksa site yoktur; `decision_book` kodu yoksa modül KAPALI
  /// sayılır. Sunucu yine de her çağrıda yetkiyi ve modül durumunu doğrular.
  List<DecisionSite> _decisionManageSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <DecisionSite>[];
    final canManage = _canManagePeople(role);
    return <DecisionSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.decisionBook))
          if (site.role == 'manager' && canManage)
            DecisionSite(code: site.siteCode, name: site.siteName)
          else if (site.isBoardMember)
            DecisionSite(code: site.siteCode, name: site.siteName, access: DecisionSiteAccess.board),
    ];
  }

  /// "Kararlar" (sakin) ekranındaki siteler: alıcısı olabilecek ve `decision_book` modülü AÇIK siteler (Anket kuralı).
  List<PeopleSite> _decisionResidentSites(UserRole role) {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return const <PeopleSite>[];
      case UserRole.siteManager:
        if (!_isResidentMode) return const <PeopleSite>[];
      case UserRole.apartmentOwner:
        break;
    }
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.decisionBook))
          PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// "Karar Defteri" menüsü: süper kullanıcı ya da `decision_book` modülü açık bir sitede yönetici / kurul üyesi.
  bool _canAccessDecisionManage(UserRole role) =>
      role == UserRole.superUser || _decisionManageSites(role).isNotEmpty;

  // --- Ziyaretçi ve Kargo (F11.03) ---

  /// "Ziyaretçi ve Kargo" (yönetim / görevli) ekranındaki siteler: `visitor_log` modülü AÇIK olan siteler. Yönetici
  /// (yönetici modunda) ve görevli (STAFF: kapıcı / güvenlik) kayıt girer ve kapatır; kurul üyesi SALT OKUR. Süper
  /// kullanıcıda boştur (ekran tüm siteleri çeker). FAIL-OPEN YOK: modül verisi hiç gelmediyse hiçbir site yoktur ve
  /// menü AÇILMAZ; sitede `visitor_log` kodu yoksa modül KAPALI sayılır (katalog varsayılanı). Sunucu yine de her
  /// çağrıda yetkiyi ve modül durumunu doğrular.
  List<VisitorSite> _visitorManageSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <VisitorSite>[];
    final canManage = _canManagePeople(role);
    return <VisitorSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.visitorLog))
          if (site.role == 'manager' && canManage)
            VisitorSite(code: site.siteCode, name: site.siteName)
          else if (site.role == 'staff')
            VisitorSite(code: site.siteCode, name: site.siteName, access: VisitorSiteAccess.staff)
          else if (site.isBoardMember)
            VisitorSite(code: site.siteCode, name: site.siteName, access: VisitorSiteAccess.board),
    ];
  }

  /// "Ziyaretçi ve Kargo" (sakin) ekranındaki siteler: alıcısı olabilecek ve `visitor_log` modülü AÇIK siteler.
  /// Yalnız daire sakini ve sakin modundaki yönetici için; süper kullanıcı, bireysel kullanıcı ve yalnız-görevli bağ
  /// için boş. Modül verisi yokken (fail-open) boştur.
  List<PeopleSite> _visitorResidentSites(UserRole role) {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return const <PeopleSite>[];
      case UserRole.siteManager:
        if (!_isResidentMode) return const <PeopleSite>[];
      case UserRole.apartmentOwner:
        break;
    }
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.visitorLog))
          PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// Yönetim menüsü: süper kullanıcı ya da `visitor_log` modülü açık bir sitede yönetici / görevli / kurul üyesi.
  bool _canAccessVisitorManage(UserRole role) =>
      role == UserRole.superUser || _visitorManageSites(role).isNotEmpty;

  // --- Firma ve Sözleşme Takibi ---

  /// "Sözleşmeler" ekranındaki siteler: `contracts` modülü AÇIK siteler. Yönetici (yönetici modunda) yazar; kurul üyesi
  /// ve görevli (STAFF) SALT OKUR; sakin GÖREMEZ. Süper kullanıcıda boştur (ekran tüm siteleri çeker). FAIL-OPEN YOK:
  /// modül verisi hiç gelmediyse site yoktur ve menü AÇILMAZ; `contracts` kodu yoksa modül KAPALI sayılır. Sunucu yine
  /// de her çağrıda yetkiyi ve modül durumunu doğrular.
  List<ContractSite> _contractSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <ContractSite>[];
    final canManage = _canManagePeople(role);
    return <ContractSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.contracts))
          if (site.role == 'manager' && canManage)
            ContractSite(code: site.siteCode, name: site.siteName)
          else if (site.isBoardMember)
            ContractSite(code: site.siteCode, name: site.siteName, access: ContractSiteAccess.board)
          else if (site.role == 'staff')
            ContractSite(code: site.siteCode, name: site.siteName, access: ContractSiteAccess.staff),
    ];
  }

  /// "Sözleşmeler" menüsü: süper kullanıcı ya da `contracts` modülü açık bir sitede yönetici / kurul üyesi / görevli.
  bool _canAccessContracts(UserRole role) =>
      role == UserRole.superUser || _contractSites(role).isNotEmpty;

  /// Sakin rozeti bir turu: modül açık sitesi olmayan kullanıcıda ağ isteği yok (rozet sıfırlanır); hata geri
  /// çekilir. Sayı değişmedikçe sayfa yeniden kurulmaz.
  Future<bool?> _pollVisitorUnread() async {
    final role = widget.authService.session?.role;
    if (role == null || _visitorResidentSites(role).isEmpty) {
      if (_visitorUnread != 0 && mounted) setState(() => _visitorUnread = 0);
      return null;
    }
    try {
      final unread = await _visitorBadgeService.unreadCount();
      if (!mounted) return null;
      if (unread != _visitorUnread) setState(() => _visitorUnread = unread);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _initVisitorBadge() {
    _visitorBadgePoller.start(immediately: true);
    _visitorBadgeWasEligible = false;
  }

  void _disposeVisitorBadge() => _visitorBadgePoller.dispose();

  /// Rozeti hemen tazeler (kayıt görüldü işaretlendi, ön plana dönüldü, çekip yenilendi).
  void _refreshVisitorBadge() {
    _visitorBadgePoller.resetBackoff();
    _visitorBadgePoller.pollNow();
  }

  /// Alıcılık değişince (modül açıldı / rol çözümlendi) yoklama aralığını beklemeden bir kez tazeler.
  void _kickVisitorBadge() {
    final role = widget.authService.session?.role;
    final eligible = role != null && _visitorResidentSites(role).isNotEmpty;
    if (eligible != _visitorBadgeWasEligible) _refreshVisitorBadge();
    _visitorBadgeWasEligible = eligible;
  }

  // --- Aidat ve Finans (Faz 4a) ---

  /// Finans ekranında listelenen siteler: `finance` modülü AÇIK olan yönetilen siteler (yazma; yalnız yönetici
  /// modunda) ve kurul üyesi olunan siteler (salt okunur). Süper kullanıcıda boştur (ekran tüm siteleri çeker).
  ///
  /// FAIL-OPEN YOK: modül verisi hiç gelmediyse (`!isFiltering`) hiçbir site yoktur ve menü AÇILMAZ; sitede
  /// `finance` kodu yoksa modül KAPALI sayılır (katalog varsayılanı). Sunucu yine de her çağrıda yetkiyi ve
  /// modül durumunu doğrular.
  List<PeopleSite> _financeSites(UserRole role) {
    if (role == UserRole.superUser || !_moduleAccess.isFiltering) return const <PeopleSite>[];
    final canManage = _canManagePeople(role);
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (site.isEnabled(PlatformModuleCodes.finance))
          if (site.role == 'manager' && canManage)
            PeopleSite(code: site.siteCode, name: site.siteName, canWrite: true)
          else if (site.isBoardMember)
            PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  /// "Finans" menüsü: süper kullanıcı ya da `finance` modülü açık bir sitede yönetici / kurul üyesi.
  bool _canAccessFinance(UserRole role) =>
      role == UserRole.superUser || _financeSites(role).isNotEmpty;

  /// "Borcum" menüsü (sakin): alıcısı olabilecek ve `finance` modülü AÇIK bir siteye bağlı daire sakini ya da
  /// sakin modundaki yönetici. Süper kullanıcı ve bireysel kullanıcı için yoktur; modül verisi yokken
  /// (fail-open) AÇILMAZ.
  bool _hasFinanceInbox(UserRole role) {
    if (!_moduleAccess.isFiltering) return false;
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return false;
      case UserRole.siteManager:
        if (!_isResidentMode) return false;
      case UserRole.apartmentOwner:
        break;
    }
    return _moduleAccess.result!.sites.any(
      (site) => _isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.finance),
    );
  }

  // --- Duyuru ve Bildirim (Faz 3a) ---

  /// Yazma yetkisi (duyuru oluşturma / yayınlama): süper kullanıcı ve site yöneticisi (yönetici modunda).
  bool _canManageAnnouncements(UserRole role) => _canManagePeople(role);

  /// Bu sitede duyuru ALABİLİR mi? `my-modules` sitede kişinin EN YÜKSEK rolünü verir: aynı sitede hem görevli
  /// (STAFF) hem sakin olan kullanıcı "staff" görünür ama `door_access` TRUE gelir. Yalnız-görevli bağda
  /// (kapı erişimi yok) alıcı sayılmaz. Menü, rozet, yoklama, şerit, tercih bölümü ve site süzgeci HEP bu
  /// tek yardımcıyı kullanır.
  static bool _isRecipientSite(MySiteModules site) => site.role != 'staff' || site.doorAccess;

  /// Sakin sinyali: kapı erişimi olan kapılar yüklendi (yalnız-görevli hesapta kapı olmaz). `my-modules` hiç
  /// gelmezse (ağ hatası) daire sakini varsayımı YALNIZ bu sinyal varken yapılır.
  bool get _hasResidentSignal => _doorControlStructure?.doors.isNotEmpty ?? false;

  /// Kullanıcı en az bir sitede duyuru ALABİLİR mi? Rol çözümlenene dek (`my-modules` yüklenmedi) alıcı
  /// SAYILMAZ: yalnız-görevli hesap ilk yoklamayı atmasın, menüyü görmesin. Modül verisi gelince kesinleşir;
  /// hiç gelmezse yalnız [_hasResidentSignal] ile sakin varsayılır.
  bool _hasResidentSite() {
    if (_moduleAccess.isFiltering) {
      return _moduleAccess.result!.sites.any(_isRecipientSite);
    }
    return _hasResidentSignal;
  }

  /// Gelen kutusu (sakin görünümü): daire sakini ve sakin modundaki yönetici. Süper kullanıcı ve bireysel
  /// kullanıcı alıcı olamaz.
  bool _hasAnnouncementInbox(UserRole role) {
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return false;
      case UserRole.siteManager:
        return _isResidentMode;
      case UserRole.apartmentOwner:
        return _hasResidentSite();
    }
  }

  /// "Duyurular" menü öğesine erişim: yönetim yetkisi, kurul üyeliği (salt okunur) ya da gelen kutusu.
  /// Görevli (STAFF) ve bireysel kullanıcı için yoktur.
  bool _canAccessAnnouncements(UserRole role) =>
      _canManageAnnouncements(role) ||
      _moduleAccess.boardMemberSites.isNotEmpty ||
      _hasAnnouncementInbox(role);

  /// Duyuru bildirimi yoklanır mı / tercih bölümü gösterilir mi? Yönetici modundaki site yöneticisi de kendi
  /// dairesi için alıcı olabilir; süper kullanıcı, bireysel kullanıcı ve yalnız-görevli hesap alıcı değildir.
  bool _receivesAnnouncements(UserRole role) {
    switch (role) {
      case UserRole.superUser:
      case UserRole.individual:
        return false;
      case UserRole.siteManager:
        return true;
      case UserRole.apartmentOwner:
        return _hasResidentSite();
    }
  }

  bool _isAnnouncementPollingEligible() {
    final session = widget.authService.session;
    return session != null && _receivesAnnouncements(session.role);
  }

  /// Sakinin duyuru alabileceği siteler (birden çoksa gelen kutusunda site süzgeci çıkar).
  List<PeopleSite> _announcementInboxSites() {
    if (!_moduleAccess.isFiltering) return const <PeopleSite>[];
    return <PeopleSite>[
      for (final site in _moduleAccess.result!.sites)
        if (_isRecipientSite(site)) PeopleSite(code: site.siteCode, name: site.siteName),
    ];
  }

  // Alıcılık yoklama aralığını beklemeden başlasın: rol çözümlenince (my-modules / kapılar yüklenince) bir kez.
  bool _announcementsWereEligible = false;

  void _kickAnnouncements() {
    final eligible = _isAnnouncementPollingEligible();
    if (eligible && !_announcementsWereEligible) {
      _announcements.resetBackoff();
      unawaited(_announcements.refresh());
    }
    _announcementsWereEligible = eligible;
    _kickVisitorBadge();
  }

  void _initAnnouncements() {
    _announcementAlerts = _announcements.alerts.listen(_onAnnouncementAlert);
    _announcements.addListener(_onAnnouncementsChanged);
    _announcements.start(immediately: true);
    _announcementsWereEligible = _isAnnouncementPollingEligible();
    _initPush();
    _initVisitorBadge();
  }

  void _disposeAnnouncements() {
    unawaited(_announcementAlerts?.cancel());
    _announcements.removeListener(_onAnnouncementsChanged);
    if (widget.announcementNotifier == null) {
      _announcements.dispose();
    } else {
      _announcements.stop();
    }
    _disposePush();
    _disposeVisitorBadge();
  }

  // --- Telefon bildirimi (Faz 3b-B) ---

  // Uygulama genelindeki örnek (yalnız Android/iOS'ta ve Firebase başlatıldıysa etkin; değilse hiçbir şey yapmaz).
  late final PushService _push = PushService.instance;
  StreamSubscription<int>? _pushForeground;
  StreamSubscription<void>? _pushTests;

  /// Çıkış / hesap değişimi kancası ve kayıt tazeleme bağlanır; ön planda gelen bildirim özeti HEMEN tazeler
  /// (sistem bildirimi gösterilmez); ön planda gelen TEST bildirimi uygulama içinde söylenir; bildirime dokunma,
  /// ana sayfa ilk kez çizilince duyuruyu açar.
  void _initPush() {
    _push.attach(widget.authService);
    _pushForeground = _push.foregroundAnnouncements.listen((_) => unawaited(_announcements.notePush()));
    _pushTests = _push.foregroundTests.listen((_) {
      if (!mounted || widget.authService.session == null) return;
      AppSnack.show(context, 'Test bildirimi bu cihaza ulaştı.', kind: AppSnackKind.success);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _push.bindAnnouncementOpener(_openAnnouncementFromPush);
    });
  }

  void _disposePush() {
    unawaited(_pushForeground?.cancel());
    unawaited(_pushTests?.cancel());
    _push.unbindAnnouncementOpener(_openAnnouncementFromPush);
    _push.detach(widget.authService);
  }

  /// Telefon bildirimine dokunuldu (arka plan / kapalıyken; numara beyaz listeden geçti). Olay bir kare kurulurken
  /// gelebilir: pencere bir sonraki karede, merkezi menü kapısından ([_openAnnouncement]) açılır.
  void _openAnnouncementFromPush(int id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openAnnouncement(id);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Rozet / acil şerit değişti: menü ve Panel yeniden kurulur.
  void _onAnnouncementsChanged() {
    if (!mounted || widget.authService.session == null) return;
    setState(() {});
  }

  /// Yeni duyuru (uygulama açıkken, <= ~20 sn yoklamayla): uygulama içi bildirim. "Aç" duyuruyu açar.
  void _onAnnouncementAlert(AnnouncementAlert alert) {
    if (!mounted || widget.authService.session == null) return;
    final title = (alert.title ?? '').trim();
    AppSnack.show(
      context,
      title.isEmpty ? 'Yeni duyuru var.' : 'Yeni duyuru: $title',
      kind: alert.urgent ? AppSnackKind.warning : AppSnackKind.info,
      // Kuyruğa girer: ekrandaki başka bildirimi ("kapı açılamadı" gibi hataları) silmez. Acil duyuru
      // bildirimi uzun kalır ("Aç" eylemiyle).
      duration: Duration(seconds: alert.urgent ? 20 : 8),
      // Eylemli SnackBar Flutter'da süre dolsa da kalır ve sıradaki mesajları sonsuza dek engeller: süre
      // dolunca kapansın (kalıcı olan, gövdenin üstündeki acil şerittir).
      persist: false,
      action: SnackBarAction(
        label: 'Aç',
        onPressed: () => _openAnnouncement(alert.announcementId),
      ),
    );
  }

  // Duyuru penceresi çift dokunuşta iki kez açılmasın.
  bool _openingAnnouncement = false;

  // Şerit / bildirimden gelindi: Duyurular ekranı (yönetici modundaki yönetici dahil) GELEN KUTUSUYLA açılır.
  bool _forceAnnouncementInbox = false;

  /// Okuma penceresini açar (şerit, bildirim ve Panel'deki "Yeni duyuru" kartı ortak kullanır). Okununca rozet, şerit
  /// ve kart güncellenir; duyuru bu arada geri çekildiyse (404) liste yenilenir.
  void _showAnnouncementReadDialog(ResidentAnnouncement announcement) {
    if (!mounted || _openingAnnouncement) return;
    _openingAnnouncement = true;
    void refreshAfterChange() {
      unawaited(_announcements.refresh());
      unawaited(_announcementsKey.currentState?.reload() ?? Future<void>.value());
    }

    unawaited(
      AnnouncementReadDialog.show(
        context,
        authService: widget.authService,
        announcement: announcement,
        onRead: (updated) {
          _announcements.noteRead(updated.id, urgent: updated.isUrgent);
          refreshAfterChange();
        },
        onGone: refreshAfterChange,
      ).whenComplete(() => _openingAnnouncement = false),
    );
  }

  /// Duyuruyu açar (şerit ya da bildirimden). Duyurular ekranı DOĞRUDAN gelen kutusu görünümüyle açılır
  /// (yönetici modundaki yönetici ve kurul üyesinde de; yönetim görünümü seçici ile ayrıdır) ve numara
  /// biliniyorsa okuma penceresi de açılır; okununca rozet ve şerit güncellenir.
  void _openAnnouncement(int? id, {ResidentAnnouncement? known}) {
    final session = widget.authService.session;
    if (!mounted || session == null) return;
    void showReadDialog() {
      if (id == null) return;
      _showAnnouncementReadDialog(known ?? ResidentAnnouncement(id: id));
    }

    if (_receivesAnnouncements(session.role)) {
      // Menü değişimi korumalı kapıdan geçer: Platform Ayarları'nda kaydedilmemiş değişiklik varken önce sorulur;
      // vazgeçilirse ekranda kalınır ve duyuru penceresi açılmaz (şerit duruyor, kaydedince yeniden dokunulur).
      _requestMenuChange(SirketMenuItem.duyurular, () {
        if (!mounted) return;
        if (_selectedMenu != SirketMenuItem.duyurular) _jumpBodyToTop();
        setState(() {
          _forceAnnouncementInbox = true;
          _selectedMenu = SirketMenuItem.duyurular;
        });
        showReadDialog();
      });
      return;
    }
    showReadDialog();
  }

  /// Kalıcı kırmızı şerit: okunmamış ACİL duyuru kaldığı sürece kaydırılan içeriğin DIŞINDA, gövdenin
  /// en üstünde sabit durur ve (Duyurular ekranının kendisi hariç) TÜM menülerde görünür; dokununca duyuruyu
  /// açar, okununca kalkar. Gövde `Column` her zaman vardır ve şerit yuvası her zaman bir çocuktur
  /// (şeritsiz hâl boş `SizedBox`): şerit gelip giderken içerik alt ağacı yeniden kurulmaz (Panel durumu,
  /// kapı kartları, saat animasyonu korunur).
  Widget _urgentBannerSlot(UserSession session) {
    final menu = _canAccessMenu(_selectedMenu, session.role)
        ? _selectedMenu
        : SirketMenuItem.dashboard;
    final visible = _announcements.hasUnreadUrgent &&
        _receivesAnnouncements(session.role) &&
        menu != SirketMenuItem.duyurular;
    if (!visible) return const SizedBox.shrink();
    final urgent = _announcements.urgentAnnouncement;
    final horizontal = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, AppSpace.sm, horizontal, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: UrgentAnnouncementBanner(
            count: _announcements.unreadUrgent,
            title: urgent?.title,
            onTap: () => _openAnnouncement(urgent?.id, known: urgent),
          ),
        ),
      ),
    );
  }

  /// Sakin Panel'inin en üstündeki "Yeni duyuru" kartı: en yeni okunmamış (acil OLMAYAN) duyuru; acil olanlar kırmızı
  /// şeritte gösterilir ve burada tekrarlanmaz. Okununca kalkar (duyuru Duyurular ekranında durur). Veri, mevcut
  /// duyuru yoklamasından ([AnnouncementNotifier]) gelir; ek yoklama yoktur. Yuva her zaman bir çocuktur (kartsız
  /// hâl boş `SizedBox`): kart gelip giderken Panel alt ağacı yeniden kurulmaz.
  Widget _unreadAnnouncementCardSlot(UserSession session) {
    final item = _announcements.cardAnnouncement;
    if (item == null || !_hasAnnouncementInbox(session.role)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: UnreadAnnouncementCard(
        announcement: item,
        moreCount: _announcements.cardMoreCount,
        onOpen: () => _showAnnouncementReadDialog(item),
        onOpenAll: () => _openAnnouncement(null),
        // Vitrin (sakin ferahlık kuralı): gölgesiz düz yüzey, nabız yok.
        flat: true,
      ),
    );
  }

  /// Panel'de seçilebilen siteler: yalnız Geçiş Kontrol modülü AÇIK olanlar.
  List<SiteRecord> _doorControlSelectableSites(List<SiteRecord> sites) {
    if (!_moduleAccess.isFiltering) return sites;
    return sites
        .where((s) => _moduleAccess.isEnabled(s.id, PlatformModuleCodes.doorControl))
        .toList(growable: false);
  }

  /// Süper kullanıcının Panel'de gördüğü sitelerin Geçiş Kontrol durumu (site kodu -> açık mı).
  /// Yalnız bilinen siteler vardır; bilinmeyen site "açık" sayılır (fail-open).
  final Map<int, bool> _superDoorEnabled = <int, bool>{};

  /// Süper kullanıcı için seçili (ya da [siteId]) sitenin Geçiş Kontrol durumunu çeker.
  Future<void> _loadSuperDoorModule([int? siteId]) async {
    if (widget.authService.session?.role != UserRole.superUser) return;
    final id = siteId ?? _doorControlSite?.id;
    if (id == null) return;
    try {
      final state = await widget.authService.getSiteModules(id);
      if (!mounted) return;
      final enabled = state.module(PlatformModuleCodes.doorControl)?.enabled;
      if (enabled != null && _superDoorEnabled[id] != enabled) {
        setState(() => _superDoorEnabled[id] = enabled);
      }
    } catch (_) {
      // Durum öğrenilemedi: kapı kartları gösterilmeye devam eder (sunucu zaten reddeder).
    }
  }

  /// Geçiş Kontrol kapalı mı? Süper olmayan kullanıcıda: bağlı olduğu ve gerçek kapı erişimi olan
  /// TÜM sitelerde kapalı. Süper kullanıcıda: Panel'de seçili sitede kapalı.
  bool _isDoorControlClosed(UserSession session) {
    if (session.role == UserRole.superUser) {
      final site = _doorControlSite;
      return site != null && _superDoorEnabled[site.id] == false;
    }
    return _moduleAccess.isDisabledEverywhere(PlatformModuleCodes.doorControl);
  }

  // --- Navigasyon & Menü ---

  bool _canAccessMenu(SirketMenuItem item, UserRole role) {
    // Modül süzgeci: Geçiş Kontrol kapalıyken kapıyla ilgili öğeler menüde de erişimde de yoktur.
    if (_hiddenMenuItems(role).contains(item)) {
      return false;
    }
    if (item == SirketMenuItem.katilimVeKurulum) {
      return true;
    }

    // Kapılar (kapı paneli): her rolde erişilir; Geçiş Kontrol kapalıyken ve daire sakininde kapı erişimi / kapısı
    // yokken yukarıdaki süzgeç zaten eler.
    if (item == SirketMenuItem.kapilar) {
      return true;
    }

    // Kişiler: yönetim yetkisi ya da kurul üyeliği (salt okunur); görevli ve sakin için yok.
    if (item == SirketMenuItem.kisiler) {
      return _canAccessPeople(role);
    }

    // Duyurular: yönetim yetkisi, kurul üyeliği (salt okunur) ya da gelen kutusu; görevli (STAFF) ve
    // bireysel kullanıcı için yok.
    if (item == SirketMenuItem.duyurular) {
      return _canAccessAnnouncements(role);
    }

    // Finans / Borcum: `finance` modülü açık siteye bağlı yönetici, kurul (salt okunur) ya da sakin; modül
    // kapalıyken ya da modül verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.finans) {
      return _canAccessFinance(role);
    }
    if (item == SirketMenuItem.borcum) {
      return _hasFinanceInbox(role);
    }

    // Belgeler: `documents` modülü açık siteye bağlı yönetici, kurul (salt okunur) ya da sakin; modül kapalıyken
    // ya da modül verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.belgeler) {
      return _canAccessDocuments(role);
    }

    // İş Takibi: `work_tracking` modülü açık siteye bağlı yönetici / görevli / kurul (Talepler) ya da sakin
    // (Taleplerim); modül kapalıyken ya da modül verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.talepler) {
      return _canAccessWorkManage(role);
    }
    if (item == SirketMenuItem.taleplerim) {
      return _workResidentSites(role).isNotEmpty;
    }

    // Rezervasyon ve Konsiyerj: `reservation` modülü açık siteye bağlı yönetici / görevli / kurul (Rezervasyonlar) ya da
    // sakin (Rezervasyon); modül kapalıyken ya da modül verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.rezervasyonlar) {
      return _canAccessReservationManage(role);
    }
    if (item == SirketMenuItem.rezervasyon) {
      return _reservationResidentSites(role).isNotEmpty;
    }
    // Anket ve Oylama: `survey` modülü açık siteye bağlı yönetici / kurul (Anket ve Oylama) ya da sakin (Anketler).
    if (item == SirketMenuItem.anketler) {
      return _canAccessSurveyManage(role);
    }
    if (item == SirketMenuItem.anket) {
      return _surveyResidentSites(role).isNotEmpty;
    }
    // Karar Defteri: `decision_book` modülü açık siteye bağlı yönetici / kurul (Karar Defteri) ya da sakin (Kararlar);
    // görevli, modül kapalıyken ya da modül verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.kararDefteri) {
      return _canAccessDecisionManage(role);
    }
    if (item == SirketMenuItem.kararlar) {
      return _decisionResidentSites(role).isNotEmpty;
    }

    // Ziyaretçi ve Kargo: `visitor_log` modülü açık siteye bağlı yönetici / görevli / kurul (yönetim ekranı) ya da
    // sakin; modül kapalıyken ya da modül verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.ziyaretciKayitlari) {
      return _canAccessVisitorManage(role);
    }
    if (item == SirketMenuItem.ziyaretcilerim) {
      return _visitorResidentSites(role).isNotEmpty;
    }

    // Sözleşmeler: `contracts` modülü açık siteye bağlı yönetici / kurul / görevli; sakin, modül kapalıyken ya da modül
    // verisi yokken erişim YOKTUR.
    if (item == SirketMenuItem.sozlesmeler) {
      return _canAccessContracts(role);
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

            (item == SirketMenuItem.moduller && !_isResidentMode) ||

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

        return 'Panel';

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
        if (currentRole == UserRole.individual) return 'Cihaz Ekle';
        return 'Cihaz Kaydet';

      case SirketMenuItem.kayitliCihazlar:
        final currentRole = widget.authService.session?.role;
        if (currentRole == UserRole.superUser) return 'Şirket Cihaz Envanteri';
        return 'Kayıtlı Cihazlar';

      case SirketMenuItem.bluetoothWifiKur:

        return 'Bluetooth ile Wi-Fi Kurulumu';

      case SirketMenuItem.moduller:
        return 'Modüller';

      case SirketMenuItem.denetimKaydi:
        return 'Denetim Kaydı';

      case SirketMenuItem.modulTalepleri:
        return 'Modül Talepleri';

      case SirketMenuItem.kisiler:
        return 'Kişiler';

      case SirketMenuItem.duyurular:
        return 'Duyurular';

      case SirketMenuItem.finans:
        return 'Finans';

      case SirketMenuItem.borcum:
        return 'Borcum';

      case SirketMenuItem.belgeler:
        return 'Belgeler';

      case SirketMenuItem.talepler:
        return 'Talepler';

      case SirketMenuItem.taleplerim:
        return 'Taleplerim';

      case SirketMenuItem.rezervasyonlar:
        return 'Rezervasyonlar';

      case SirketMenuItem.rezervasyon:
        return 'Rezervasyon';

      case SirketMenuItem.siteBasvurulari:
        return 'Site Başvuruları';

      case SirketMenuItem.platformAyarlari:
        return 'Platform Ayarları';

      case SirketMenuItem.istemciHatalari:
        return 'İstemci Hataları';

      case SirketMenuItem.anketler:
        return 'Anket ve Oylama';

      case SirketMenuItem.anket:
        return 'Anketler';

      case SirketMenuItem.kararDefteri:
        return 'Karar Defteri';

      case SirketMenuItem.kararlar:
        return 'Kararlar';

      case SirketMenuItem.ziyaretciKayitlari:
        return 'Ziyaretçi ve Kargo';

      case SirketMenuItem.ziyaretcilerim:
        // Yönetim öğesinden ayrı başlık: kurul üyesinde ikisi birden görünür (bkz. YanMenu).
        return 'Ziyaretçilerim';

      case SirketMenuItem.sozlesmeler:
        return 'Sözleşmeler';

      case SirketMenuItem.kapilar:
        return 'Kapılar';

    }

  }



  /// "Yerel Ağda Aktif" yalnızca cihaz yerelde görünüyorsa VE yerel açma gerçekten mümkünse (kapı
  /// politikası izin veriyor + sunucudan alınmış geçerli token var).
  bool get _canTryLocalDoorOpenNow =>
      _doorControlDoor != null &&
      _isDeviceLocalReachable &&
      widget.authService.canTryLocalDoorOpen(_doorControlDoor!);

  /// Sade daire sakini ekranından kaldırılan komutların çekmecedeki karşılıkları ("Panel"in altında).
  /// Yalnız kapı paneli sakin kartıyla çiziliyorsa ve ilgili yetki/cihaz varsa görünür; hepsi eski
  /// kart düğmeleriyle AYNI mantığı çalıştırır ([ResidentDoorActions]).
  List<YanMenuAction> _residentExtraActions(UserSession session) {
    if (session.role != UserRole.apartmentOwner || _showsIndividualHome(session)) {
      return const <YanMenuAction>[];
    }
    // Geçiş Kontrol modülü kapalıyken ya da "Kapılar" gizliyken (kapı erişimi / kapısı olmayan hesap) kapı komutları
    // (QR, misafir geçişi, sesli açma) da yoktur.
    if (_isDoorControlClosed(session) || !_canAccessMenu(SirketMenuItem.kapilar, session.role)) {
      return const <YanMenuAction>[];
    }
    final door = _doorControlDoor;
    final isOnline =
        _doorRuntimeStatus?.mqttConnected == true || _canTryLocalDoorOpenNow;
    final voice = widget.voiceDoorService;
    // Çekmece kapanır, sonra eylem çalışır (diğer menü öğeleriyle aynı).
    VoidCallback act(VoidCallback action) => () {
      Navigator.of(context).pop();
      action();
    };
    return <YanMenuAction>[
      if (voice != null)
        YanMenuAction(
          icon: Icons.mic_rounded,
          title: 'Sesli Kapı Açma',
          onTap: act(() => VoiceControlModal.show(context, voiceService: voice)),
        ),
      if (ResidentDoorActions.canShowQr(door))
        YanMenuAction(
          icon: Icons.qr_code_2_rounded,
          title: 'Kapıya QR Göster',
          onTap: act(
            () => ResidentDoorActions.showQrPass(
              context,
              door: door,
              isOnline: isOnline,
              authService: widget.authService,
            ),
          ),
        ),
      if (ResidentDoorActions.canScanScreenQr(door))
        YanMenuAction(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Kapı Ekranından QR Oku',
          onTap: act(
            () => ResidentDoorActions.scanScreenQr(
              context,
              door: door,
              isOnline: isOnline,
              authService: widget.authService,
            ),
          ),
        ),
      if (ResidentDoorActions.canCreateGuestPass(door))
        YanMenuAction(
          icon: Icons.share_rounded,
          title: 'Kurye / Misafir Geçiş Linki Oluştur',
          onTap: act(
            () => CreateGuestPassDialog.show(
              context,
              door: door!,
              authService: widget.authService,
              showMessage: _showMessage,
            ),
          ),
        ),
    ];
  }

  /// Çekmeceden "Yardım ve Destek": çekmece kapanır, ekran yeni sayfa olarak açılır. Ekrandaki "Profilim
  /// ekranına git" sayfayı kapatıp menüyü Profilim'e alır.
  void _openHelp() {
    Navigator.of(context).pop();
    _openHelpPage();
  }

  /// Yardım ekranını açar (çekmece açık değilse de çalışır: Panel vitrinindeki "Yardım ve Destek" düğmesi).
  void _openHelpPage() {
    final session = widget.authService.session;
    if (session == null) return;
    unawaited(
      HelpView.open(
        context,
        role: session.role,
        residentMode: _isResidentMode,
        userId: session.id,
        onOpenProfile: () => _goToMenu(SirketMenuItem.profilim),
      ),
    );
  }

  /// Menü değişiminin TEK korumalı kapısı: çekmece, Yardım'dan "Profilim'e git", acil duyuru şeridi, mod geçişi,
  /// başvuru onayı ve "Modüller'e git" hep buradan geçer. Platform Ayarları'nda kaydedilmemiş değişiklik varken
  /// başka menüye çıkılacaksa önce onay istenir: onaylanırsa [apply] çalışır, vazgeçilirse ekranda kalınır.
  /// [apply] menüyü [setState] içinde değiştirir ve gerekirse [mounted] denetimini kendisi yapar.
  void _requestMenuChange(SirketMenuItem target, VoidCallback apply) {
    final leaving = _platformSettingsKey.currentState;
    if (_selectedMenu == SirketMenuItem.platformAyarlari &&
        target != SirketMenuItem.platformAyarlari &&
        leaving != null &&
        leaving.hasUnsavedChanges) {
      // Yeniden-giriş koruması: onay penceresi açıkken gelen ikinci istek (aynı karede erişilebilirlik eylemi,
      // klavye ya da programatik çağrı; ikinci İŞARETÇİYİ Navigator zaten soğurur) yok sayılır; aksi hâlde iki pencere
      // açılır ve `apply` (örn. mod geçişi, bir TOGGLE) iki kez çalışıp geri çevrilirdi. Vazgeç / onaydan sonra
      // sıfırlanır.
      if (_menuGuardOpen) return;
      _menuGuardOpen = true;
      unawaited(
        leaving
            .confirmDiscard()
            .then((discard) {
              if (discard && mounted) apply();
            })
            .whenComplete(() => _menuGuardOpen = false),
      );
      return;
    }
    apply();
  }

  /// Menü kapısının onay penceresi açık mı ([_requestMenuChange]).
  bool _menuGuardOpen = false;

  /// [target] menüsüne korumalı geçiş (yalnız menü seçimi değişir).
  void _goToMenu(SirketMenuItem target) {
    _requestMenuChange(target, () {
      if (!mounted) return;
      if (_selectedMenu != target) {
        if (target == SirketMenuItem.kapilar) _armDoorEntryGuard();
        _jumpBodyToTop();
      }
      setState(() => _selectedMenu = target);
    });
  }

  /// Gövde kaydırmasını en üste alır. Sayfa değişmeden HEMEN ÖNCE çağrılır: yeni sayfa ilk karesinden en üstten çizilir
  /// (eski sayfanın konumu yeni sayfaya taşınmaz). Kaydırma alanı henüz yoksa ya da zaten en üstteyse bir şey yapmaz.
  void _jumpBodyToTop() {
    final content = _bodyContentKey.currentContext;
    final position = content == null ? null : Scrollable.maybeOf(content)?.position;
    if (position == null || !position.hasPixels || position.pixels == 0) return;
    position.jumpTo(0);
  }

  /// Kapılar sayfasına girerken sayfa [HomePage.doorEntryGuard] boyunca dokunuş ALMAZ: vitrindeki "Kapılar" kartına ya
  /// da hızlı "Kapıyı aç"a hızlı ikinci dokunuş, sayfa geçişi sürerken aynı noktaya gelen KAPIYI AÇ düğmesine düşüp
  /// kullanıcı paneli görmeden kapıyı açmasın. Kapı açma işlevine dokunulmaz; yalnız gövdedeki küçük dinleyici
  /// ([_doorEntryGuard]) yeniden kurulur (sayfa, kapı paneli, Scaffold kurulmaz).
  void _armDoorEntryGuard() {
    _doorEntryGuardTimer?.cancel();
    _doorEntryGuard.value = true;
    _doorEntryGuardTimer = Timer(HomePage.doorEntryGuard, () {
      _doorEntryGuardTimer = null;
      _doorEntryGuard.value = false;
    });
  }

  /// Widget / kısayol / derin bağlantı "Kapılar sayfasını aç" dedi ([HomePage.doorPanelRequests]): bir sonraki karede
  /// uygulanır (olay bir kare kurulurken de gelebilir).
  void _onDoorPanelRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDoorPanelRequest());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Bekleyen isteği tüketir: Kapılar'a erişim varsa oraya çekmeceden seçmekle AYNI korumalı yoldan geçilir; Geçiş
  /// Kontrol kapalıysa ya da kapı erişimi yoksa vitrinde kalınır. Kapı AÇILMAZ.
  void _applyDoorPanelRequest() {
    final requests = widget.doorPanelRequests;
    final session = widget.authService.session;
    if (!mounted || requests == null || session == null || !requests.take()) return;
    if (_selectedMenu == SirketMenuItem.kapilar || !_canAccessMenu(SirketMenuItem.kapilar, session.role)) return;
    _openMenuItem(SirketMenuItem.kapilar);
  }

  /// "Sakin Modu / Yönetici Paneli" geçişi (AppBar hapı ve çekmece): yönetici paneline dönüşte menü Panel'e alınır.
  void _toggleResidentMode() {
    _requestMenuChange(SirketMenuItem.dashboard, () {
      if (!mounted) return;
      _jumpBodyToTop();
      setState(() {
        _isResidentMode = !_isResidentMode;
        if (!_isResidentMode) {
          _selectedMenu = SirketMenuItem.dashboard;
        }
      });
      // Sakin modunda ziyaretçi rozeti alıcılığı değişir: yoklama aralığını (60 sn) beklemeden tazelenir.
      _kickVisitorBadge();
    });
  }

  void _selectMenu(SirketMenuItem item) {

    Navigator.of(context).pop();

    _openMenuItem(item);

  }

  /// Menü öğesini açar: çekmeceden seçmeyle de Panel vitrinindeki karta dokunmayla da AYNI gezinme (çekmeceyi kapatmak
  /// çağıranın işidir: [_selectMenu]).
  void _openMenuItem(SirketMenuItem item) {

    // Çekmeceden seçim: şeritten gelen "doğrudan gelen kutusu" isteği biter.
    _forceAnnouncementInbox = false;

    if (item == SirketMenuItem.ellerSerbest) {

      if (widget.voiceDoorService != null) {

        HandsFreeSettingsDialog.show(

          context,

          voiceDoorService: widget.voiceDoorService!,

        );

      }

      return;

    }



    // Platform Ayarları'nda kaydedilmemiş değişiklik varken başka ekrana geçmeden önce onay istenir.
    _requestMenuChange(item, () => _applyMenuSelection(item));
  }

  void _applyMenuSelection(SirketMenuItem item) {
    if (_selectedMenu != item) {
      if (item == SirketMenuItem.kapilar) _armDoorEntryGuard();
      _jumpBodyToTop();
    }
    setState(() => _selectedMenu = item);



    final session = widget.authService.session;

    if (session == null) return;



    switch (item) {

      case SirketMenuItem.dashboard:
      case SirketMenuItem.kapilar:

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

      // Sakin sinyali (kapı erişimi) geldi: duyuru yoklaması modül verisini beklemeden de başlayabilir.
      _kickAnnouncements();

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

        // Yalnız Geçiş Kontrol modülü AÇIK siteler Panel'de seçilebilir (kapalı site listede yoktur).
        final selectable = _doorControlSelectableSites(data.sites);
        if (selectable.isNotEmpty) {
          siteToSelect = preferredSiteId ??
              (_doorControlSite != null &&
                      selectable.any((s) => s.id == _doorControlSite!.id)
                  ? _doorControlSite!.id
                  : selectable.first.id);
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
    final sites = _doorControlSelectableSites(
      _doorControlSitesPage?.sites ?? const <SiteRecord>[],
    );
    if (sites.isEmpty) return;

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

    // Süper kullanıcıda modül durumu my-modules'tan gelmez: seçili sitenin Geçiş Kontrol durumu çekilir.
    unawaited(_loadSuperDoorModule(site.id));

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

    // Geçiş Kontrol modülü kapalıysa kapı listesi sunucuda boşaltılır: "Tanımlı bir kapı bulunamadı."
    // diye her Panel açılışında konuşmak yanıltıcıdır. Sessizce dön, sürmekte olan dinlemeyi durdur
    // ve eski kapı listesini sesli komut servisinden temizle.
    if (_isDoorControlClosed(session)) {
      await _silenceVoiceForClosedModule();
      return;
    }

    // Kullanıcı Eller Serbest ayarlarında otomatik dinlemeyi kapattıysa hiçbir şey yapma.
    if (!widget.voiceDoorService!.handsFreeAutoListen) {
      return;
    }

    if (doors.isEmpty) {
      // Modül durumu henüz gelmediyse (açılış yarışı) önce onu bekle: kapalıysa konuşma.
      if (!_moduleAccess.isLoaded) {
        await _moduleAccess.refresh();
        if (!mounted) return;
        if (_isDoorControlClosed(session)) {
          await _silenceVoiceForClosedModule();
          return;
        }
      }
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

  Future<void> _silenceVoiceForClosedModule() async {
    final voice = widget.voiceDoorService;
    if (voice == null) return;
    voice.updateCandidateDoors(const <DoorRecord>[]);
    if (voice.isListening) {
      await voice.stopListening();
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
      // Sahip bağı olan yönetici için "Site Ekle" ANLIK kalır. Sunucu `requires_application: true` derse
      // (sahip bağı olmayan yönetici) aynı form BAŞVURU kipinde açılır. Bilgi yoksa (alan eksik / okunamadı)
      // anlık kip denenir; sunucu 409 `APPLICATION_REQUIRED` derse form başvuru kipine geçer (çıkmaz yok).
      await _siteApplications.ensureLoaded();
      if (!mounted) return;
      if (usesSiteApplicationFlow(UserRole.siteManager, _siteApplications)) {
        await openSiteApplicationForm(
          context,
          authService: widget.authService,
          tracker: _siteApplications,
        );
        return;
      }
      final created = await SetupSiteDialog.show(
        context,
        authService: widget.authService,
        mode: SetupSiteMode.instant,
      );
      if (created == SetupSiteOutcome.created) {
        await _loadSites(force: true);
        // Yeni sitenin modül durumu (varsayılanlar) hemen alınır.
        unawaited(_moduleAccess.refresh());
      } else {
        // Form başvuru kipine geçtiyse (APPLICATION_REQUIRED) ya da başvuru gönderildiyse durum yeniden okunur.
        syncApplicationsAfterForm(_siteApplications, created);
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

        managementType: result.managementType.apiValue,

      );

      if (error != null) {

        _showMessage(error);

      } else {

        _showMessage('Site başarıyla oluşturuldu.');

        await _loadSites(force: true, preferredSiteId: createdSite?.id);

        await _loadDoorControlSites(preferredSiteId: createdSite?.id);

        unawaited(_moduleAccess.refresh());

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



    final (updated, pinIssue, error) = await widget.authService.upsertApartmentResident(

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

      // Yeni daire hesabı: PIN yalnız bu yanıtta gelir (sunucu saklamaz) -> bir kez gösterilir.
      if (pinIssue != null && mounted) {
        await ApartmentPinIssuedDialog.show(context, pinIssue);
      }

      if (!mounted) return;

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



  /// "PIN'i Sıfırla": onaydan sonra yeni PIN üretilir; PIN sunucuda saklanmadığı için yalnız burada bir kez
  /// gösterilir (e-posta varsa sunucu ayrıca bir kez gönderir).
  Future<void> _resetApartmentPin(ApartmentRecord apartment) async {
    final confirmed = await confirmApartmentPinReset(
      context,
      apartment: apartment,
      isSuper: widget.authService.session?.role == UserRole.superUser,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyApartmentPins.add(apartment.id));
    final (issue, error) = await widget.authService.resetApartmentPin(
      apartmentId: apartment.id,
    );
    if (!mounted) return;
    setState(() => _busyApartmentPins.remove(apartment.id));
    if (error != null || issue == null) {
      _showMessage(error ?? "PIN sıfırlanamadı.");
      return;
    }
    await ApartmentPinIssuedDialog.show(context, issue);
    if (!mounted) return;
    if (_selectedSite != null) {
      _selectSite(_selectedSite!);
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
      // Cihaz sahiplenmek bireysel / daire kullanıcısını site yöneticisi YAPMAZ (rol değişmez): bilgi
      // metni + "Site Kur" (başvuru) eylemi sunulur; yönetici görünümüne geçiş beklenmez.
      if (usesSiteApplicationFlow(widget.authService.session?.role, _siteApplications)) {
        await offerSiteApplicationAfterClaim(
          context,
          authService: widget.authService,
          deviceUid: claimedUid,
          tracker: _siteApplications,
        );
        return;
      }
      final hasSites = _doorControlSitesPage?.sites.isNotEmpty ?? false;
      if (!hasSites) {
        // Yönetici / süper kullanıcı: anlık site kurulum sihirbazı.
        final result = await SetupSiteDialog.show(
          context,
          authService: widget.authService,
          deviceUid: claimedUid,
        );
        if (result == SetupSiteOutcome.created) {
          _loadInitialData();
        } else if (result == SetupSiteOutcome.applied) {
          unawaited(_siteApplications.noteChanged());
        }
      }
    }
  }

  /// Başvuru ONAYLANDI (yoklama ya da ön plana dönüş): oturum / rol sunucudan yenilenir (yerelde TAHMİN
  /// EDİLMEZ), Panel verisi okunur ve kullanıcı sayfa yenilenmeden yönetici görünümüne geçer.
  Future<void> _onSiteApplicationApproved(SiteApplication application) async {
    if (!mounted) return;
    final before = widget.authService.session?.role;
    await _refreshAccountAfterApproval(application);
    if (!mounted) return;
    final role = widget.authService.session?.role;
    if (role == UserRole.siteManager) {
      _goToMenu(SirketMenuItem.dashboard);
      AppSnack.show(
        context,
        before == UserRole.siteManager
            ? 'Site başvurunuz onaylandı. Siteniz kuruldu.'
            : 'Site başvurunuz onaylandı. Artık site yöneticisisiniz.',
        kind: AppSnackKind.success,
      );
    }
  }

  /// Oturum bilgisini (rol dahil) sunucudan zorla yeniler. Rol değiştiyse [_onAuthChanged] Panel verisini
  /// ve modülleri TEK kez yeniden okur (burada ikinci kez okunmaz); rol değişmediyse (örn. yönetici ek site
  /// başvurusu onaylandı) burada okunur. Yenileme BAŞARILI olduğu halde rol hâlâ başvuran rolündeyse
  /// onaylı kartı yanıltıcıdır (yöneticilik sonradan alınmış olabilir): kart kaldırılır ve olay tüketilmiş
  /// sayılır; yenileme BAŞARISIZSA kart "Hesabı yenile" ile kalır.
  Future<void> _refreshAccountAfterApproval([SiteApplication? approved]) async {
    final auth = widget.authService;
    final roleBefore = auth.session?.role;
    final verifiedBefore = auth.sessionVerifiedAt;
    await auth.refreshSession(force: true);
    if (!mounted) return;
    final roleAfter = auth.session?.role;
    if (roleAfter != roleBefore) return; // _onAuthChanged yeniden okudu.
    _loadInitialData();
    unawaited(_moduleAccess.refresh());
    final verifiedAfter = auth.sessionVerifiedAt;
    final verified = verifiedAfter != null &&
        (verifiedBefore == null || verifiedAfter.isAfter(verifiedBefore));
    final latest = approved ?? _siteApplications.latest;
    if (verified && latest != null && latest.isApproved && canApplyForSite(roleAfter)) {
      _siteApplications.consumeApproval(latest.id);
    }
  }

  /// "Yeniden başvur" (yönetici panosundaki başvuru kartı).
  Future<void> _reapplySiteApplication(SiteApplication previous) async {
    await openSiteApplicationForm(
      context,
      authService: widget.authService,
      tracker: _siteApplications,
      previous: previous,
    );
  }

  /// Bu oturumun başvuru takipçisi: başvuranlarda her zaman; site yöneticisinde yalnız başvuru gerekliyse
  /// (`requires_application`) ya da bekleyen başvuru varsa; diğerlerinde null (kart / başvuru eylemi yok).
  SiteApplicationTracker? _applicationsFor(UserSession session) {
    if (canApplyForSite(session.role)) return _siteApplications;
    if (session.role == UserRole.siteManager &&
        (_siteApplications.requiresApplication == true || _siteApplications.pending != null)) {
      return _siteApplications;
    }
    return null;
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

    // Modül durumu her genel yenilemede tazelenir (menü/panel süzgeci güncel kalır).
    final modulesRefresh = _moduleAccess.refresh();
    // Başvuru durumu (başvuranlar ve site yöneticisi): elle yenilemede sunucudan okunur.
    if (tracksSiteApplications(session.role)) unawaited(_siteApplications.refresh());

    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
        // Vitrin: sakin borç özeti tazelenir; bekleyen sayılar zaten yukarıdaki modül yenilemesiyle gelir. Kart
        // rozetleri (okunmamış duyuru, görülmemiş ziyaretçi / kargo kaydı) ve "Yeni duyuru" kartı da yoklama aralığı
        // beklenmeden tazelenir (ikisi de kendi uygunluk denetimini yapar: uygun değilse ağ isteği yok). Kapı verisi
        // (siteler / kapılar: sesli komut adayları, çekmecedeki kapı komutları, Kapılar sayfası) eskisi gibi yenilenir.
        _announcements.resetBackoff();
        unawaited(_announcements.refresh());
        _refreshVisitorBadge();
        await _loadDoorControlSites();
        await _showcaseKey.currentState?.reload();
        await _individualHomeKey.currentState?.loadAll();
        break;
      case SirketMenuItem.kapilar:
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
      case SirketMenuItem.moduller:
        await _modulesViewKey.currentState?.reload();
        break;
      case SirketMenuItem.denetimKaydi:
        await _auditLogViewKey.currentState?.reload();
        break;
      case SirketMenuItem.platformAyarlari:
        await _platformSettingsKey.currentState?.reload();
        break;
      case SirketMenuItem.istemciHatalari:
        await _clientErrorsKey.currentState?.reload();
        break;
      case SirketMenuItem.anketler:
        await _surveyManagerKey.currentState?.reload();
        break;
      case SirketMenuItem.anket:
        await _surveyResidentKey.currentState?.reload();
        break;
      case SirketMenuItem.kararDefteri:
        await _decisionManagerKey.currentState?.reload();
        break;
      case SirketMenuItem.kararlar:
        await _decisionResidentKey.currentState?.reload();
        break;
      case SirketMenuItem.modulTalepleri:
        await _moduleRequestsViewKey.currentState?.reload();
        break;
      case SirketMenuItem.siteBasvurulari:
        await _siteApplicationsViewKey.currentState?.reload();
        break;
      case SirketMenuItem.kisiler:
        await _peopleViewKey.currentState?.reload();
        break;
      case SirketMenuItem.duyurular:
        _announcements.resetBackoff();
        unawaited(_announcements.refresh());
        await _announcementsKey.currentState?.reload();
        break;
      case SirketMenuItem.finans:
        await _financeViewKey.currentState?.reload();
        break;
      case SirketMenuItem.borcum:
        await _myFinanceViewKey.currentState?.reload();
        break;
      case SirketMenuItem.belgeler:
        await _documentsKey.currentState?.reload();
        break;
      case SirketMenuItem.talepler:
        await _workManagerKey.currentState?.reload();
        break;
      case SirketMenuItem.taleplerim:
        await _workResidentKey.currentState?.reload();
        break;
      case SirketMenuItem.rezervasyonlar:
        await _reservationManagerKey.currentState?.reload();
        break;
      case SirketMenuItem.rezervasyon:
        await _reservationResidentKey.currentState?.reload();
        break;
      case SirketMenuItem.ziyaretciKayitlari:
        await _visitorManagerKey.currentState?.reload();
        break;
      case SirketMenuItem.ziyaretcilerim:
        await _visitorResidentKey.currentState?.reload();
        _refreshVisitorBadge();
        break;
      case SirketMenuItem.sozlesmeler:
        await _contractsKey.currentState?.reload();
        break;
      case SirketMenuItem.katilimVeKurulum:
      case SirketMenuItem.cihazEkle:
      case SirketMenuItem.bluetoothWifiKur:
      case SirketMenuItem.profilim:
        break;
    }
    // Modül isteği çekip yenilemeyi BEKLETMEZ: arka planda biter (yavaş ağda gösterge takılmaz);
    // sonuç gelince ModuleAccess dinleyicileri menüyü/paneli tazeler.
    unawaited(modulesRefresh);
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
        onTap: _toggleResidentMode,
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
    // Tema geçiş düğmesi yalnız ThemeScope varsa çizilir (uygulama kökü); yoksa (tek başına kurulum) yer ayrılmaz.
    final hasThemeToggle = ThemeScope.maybeOf(context) != null;
    // Ekrandaki ("etkin") sayfa: erişimi kalkan öğe (örn. kurul üyeliği biten "Kişiler", Finans'ı kapanan "Borcum",
    // sakin moduna geçince "Modüller") bir kare bile kalmaz, içerik gibi Panel'e düşer. AppBar başlığı, çekmecedeki seçim
    // ve geri tuşu kararı HEP bunu kullanır (ham [_selectedMenu] değil): vitrine düşülünce ilk geri basışı boşa gitmez.
    final effectiveMenu =
        _canAccessMenu(_selectedMenu, session.role) ? _selectedMenu : SirketMenuItem.dashboard;

    return Scaffold(
      backgroundColor: Colors.transparent,
      onDrawerChanged: (open) => _drawerOpen.value = open,
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
        // Premium başlık sayfası: rol tonunun sol-üstten yumuşak yıkaması (statik, tek gradyan).
        flexibleSpace: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  session.role.tone.hue.withValues(alpha: isDark ? 0.20 : 0.13),
                  session.role.tone.hue.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
        actions: [
          if (_canToggleDualMode)
            _buildModeToggle(
              context,
              // Hapın genişlik payı: yanındaki 44-48 dp'lik düğmeler (yenile, çıkış, [widget], [tema]).
              otherActions: (showWidgetAction ? 3 : 2) + (hasThemeToggle ? 1 : 0),
            ),
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
          // Aydınlık / karanlık tema geçişi (44 dp, diğer eylem düğmeleriyle aynı boyut ve yoğunluk).
          const ThemeToggleButton(iconSize: 20),
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
            child: Row(
              children: [
                // Avatar rozeti (rol tonu): 34 dp, iki satırlık metin bloğundan alçaktır, başlık
                // yüksekliği değişmez. Dekoratif; kimlik bilgisi yanındaki metindedir.
                IconOrb(
                  icon: Icons.person_rounded,
                  tone: session.role.tone,
                  size: 34,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // Erişimi kalkan öğe (örn. kurul üyeliği biten "Kişiler") başlıkta bir kare bile
                        // kalmaz: içerik gibi Panel'e düşer.
                        _titleForMenu(effectiveMenu),
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
              ],
            ),
          ),
        ),
      ),
      drawer: YanMenu(
        extraActions: _residentExtraActions(session),

        hiddenItems: _hiddenMenuItems(session.role),

        additionalItems: _extraMenuItems(session.role),

        badgeCounts: _menuBadgeCounts(session),
        badgeNouns: _menuBadgeNouns,
        fullName: session.fullName,
        userEmail: session.email,
        role: session.role,
        selectedItem: effectiveMenu,
        isResidentMode: _isResidentMode,
        canToggleMode: _canToggleDualMode,
        onToggleMode: () {
          Navigator.pop(context);
          _toggleResidentMode();
        },
        onSelect: _selectMenu,
        onOpenHelp: _openHelp,
        onLogout: () {
          Navigator.pop(context);
          widget.authService.logout();
        },
      ),
      // Geri tuşu: bir modül sayfasındayken Panel vitrinine döner (uygulamadan çıkmaz); vitrindeyken eskisi gibi çıkar.
      // Çekmece AÇIKKEN geri tuşu önce çekmeceyi kapatır, sayfa değişmez: PopScope rota yerel geçmişinden ÖNCE
      // değerlendirildiği için ([ModalRoute.popDisposition]) çekmece açıkken pop'a izin verilir; pop'u çekmecenin
      // yerel geçmişi karşılar (route kapanmaz, onPopInvokedWithResult çağrılmaz). Karar ekrandaki etkin sayfayla verilir.
      body: ValueListenableBuilder<bool>(
        valueListenable: _drawerOpen,
        builder: (context, drawerOpen, child) => PopScope(
          canPop: drawerOpen || effectiveMenu == SirketMenuItem.dashboard,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _goToMenu(SirketMenuItem.dashboard);
          },
          child: child!,
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _urgentBannerSlot(session),
              Expanded(child: _buildScrollBody(session)),
            ],
          ),
        ),
      ),
    );

  }



  /// Kaydırılan sayfa gövdesi (aşağı çek yenile + ortalanmış, en çok 1100 dp içerik).
  ///
  /// Sayfa (menü ya da Sakin / Yönetici modu) değişince kaydırma EN ÜSTTEN başlar ([_jumpBodyToTop]): vitrinde aşağı
  /// kaydırıp bir karta dokununca modül sayfası ortadan açılmaz, geri dönülen vitrin de baştan başlar. Kaydırma görünümü
  /// sayfa başına YENİDEN YARATILMAZ (anahtar yok): GlobalKey'li görünümler (vitrin, bireysel ana ekran) aynı karede
  /// başka bir kaydırma alanına taşınırsa anlam ağacı (semantics) bozuluyordu; görünüm birincil kaydırma alanı olarak
  /// kalır (iOS durum çubuğuna dokununca başa dönme). Yoklamayla yeniden kurulumda konum korunur.
  Widget _buildScrollBody(UserSession session) {
    final page = _canAccessMenu(_selectedMenu, session.role) ? _selectedMenu : SirketMenuItem.dashboard;
    final pageKey = '${page.name}-$_isResidentMode';
    if (_bodyScrollPage != null && _bodyScrollPage != pageKey) {
      // Olay işleyicileri sayfayı değiştirmeden ÖNCE başa alır; erişimi düşen sayfanın kurulumda Panel'e düşmesi gibi
      // yollarda konum bir sonraki karede sıfırlanır (giriş solması sürerken, görünmeden).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpBodyToTop();
      });
    }
    _bodyScrollPage = pageKey;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 20.0;
        return RefreshIndicator(
          onRefresh: _handleGlobalRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(horizontalPadding, 10.0, horizontalPadding, 56.0),
            child: Align(
              key: _bodyContentKey,
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
    );
  }



  /// Sayfa gövdesi: menü (ya da Sakin/Yönetici modu) değişince YALNIZ yeni içerik kısa bir solma + hafif
  /// kayma ile gelir ([PageEntry]); eski içerik hemen kalkar. `AnimatedSwitcher` bilerek KULLANILMAZ:
  /// iki görünüm aynı anda ağaçta kalır (GlobalKey çakışması, testlerde çift sonuç). Anahtar, erişimsiz
  /// menüyü panele çeviren [_buildContentView] çalıştıktan SONRA okunur. Yoklamayla yeniden kurulumda
  /// anahtar aynı kalır: animasyon yeniden başlamaz.
  Widget _buildContent(UserSession session) {
    final view = _buildContentView(session);
    // Başvurusu gereken (sahip bağı olmayan) site yöneticisinin Site Yönetimi'nde başvuru durumu kartı (bekleyen /
    // reddedildi / iptal) görünür; Panel vitrininde kartı vitrin kendisi çizer. Yuva her zaman bir Column
    // çocuğudur: kart gelip giderken asıl görünümün durumu korunur.
    final managerView = session.role == UserRole.siteManager &&
        !_isResidentMode &&
        _selectedMenu == SirketMenuItem.siteler &&
        !_showsIndividualHome(session);
    Widget child = view;
    if (managerView) {
      final tracker = _applicationsFor(session);
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tracker == null
              ? const SizedBox.shrink()
              : SiteApplicationStatusCard(
                  tracker: tracker,
                  onReapply: _reapplySiteApplication,
                  showApproved: false,
                  showLoadFailure: false,
                ),
          view,
        ],
      );
    }
    // Kapılar sayfasına girişte kısa süre dokunuş yutulur ([_armDoorEntryGuard]); yalnız bu küçük dinleyici kurulur.
    final doorPage = _selectedMenu == SirketMenuItem.kapilar;
    return PageEntry(
      key: ValueKey<String>('${_selectedMenu.name}-$_isResidentMode'),
      child: ValueListenableBuilder<bool>(
        valueListenable: _doorEntryGuard,
        builder: (context, guarded, page) => IgnorePointer(
          key: const ValueKey<String>('kapilar_giris_korumasi'),
          ignoring: guarded && doorPage,
          child: page,
        ),
        child: child,
      ),
    );
  }

  /// Sakin selamlamasının site satırı: alıcısı olduğu sitelerin adı (modül verisinden); veri yoksa kapı listesindeki
  /// site adı. Bilinmiyorsa null.
  String? _residentSiteName() {
    final names = <String>[
      if (_moduleAccess.isFiltering)
        for (final site in _moduleAccess.result!.sites)
          if (_isRecipientSite(site) && site.siteName.trim().isNotEmpty) site.siteName.trim(),
    ];
    if (names.isEmpty) {
      final fallback = _doorControlStructure?.site.name.trim();
      if (fallback != null && fallback.isNotEmpty && fallback != 'Site Kapısı') names.add(fallback);
    }
    if (names.isEmpty) return null;
    return names.length == 1 ? names.first : '${names.first} +${names.length - 1} site';
  }

  /// Bireysel ana ekran (kapılar, kayıtlı daireler, katılım başvuruları, cihazlar, hızlı işlemler). Geçiş Kontrol
  /// kapalıyken kapı dışı bölümleri ERİŞİLEBİLİR kalır; en üste kısa bir bilgi eklenir.
  Widget _buildIndividualHome(UserSession session) {
    final individualHome = IndividualHomeView(
      key: _individualHomeKey,
      session: session,
      authService: widget.authService,
      onRefreshAll: _loadInitialData,
      // Site başvurusu kartı / formu bireysel ve daire kullanıcısına, ayrıca başvurusu gereken (sahip bağı
      // olmayan) site yöneticisine açılır.
      applications: _applicationsFor(session),
      onRefreshAccount: () => _refreshAccountAfterApproval(),
    );
    if (_isDoorControlClosed(session)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DoorControlDisabledCard(compact: true),
          const SizedBox(height: AppSpace.lg),
          individualHome,
        ],
      );
    }
    return individualHome;
  }

  /// Sakin vitrininin borç özetinin kapsadığı siteler: alıcısı olunan ve `finance` modülü AÇIK sitelerin kodları (Borcum
  /// menüsüyle aynı kural, [_hasFinanceInbox]). Küme değişince vitrin özeti yeniden okur ve kapanan sitenin tutarını
  /// göstermez.
  Set<int> _debtSiteCodes() => <int>{
        if (_moduleAccess.isFiltering)
          for (final site in _moduleAccess.result!.sites)
            if (_isRecipientSite(site) && site.isEnabled(PlatformModuleCodes.finance)) site.siteCode,
      };

  /// Sakin vitrininde hızlı işlem olabilecek öğeler. Daire bağı gerektirenler ("Arıza bildir" = Taleplerim, "Ziyaretçi
  /// ve kargo" = Ziyaretçilerim) yalnız daire bağı OLABİLEN bir sitede verilir: my-modules `door_access` aktif daire
  /// üyeliği (ya da kapı izni) olan sitede true, yalnız kurul / görevli / site üyeliği bağında false. Sunucu dairesi
  /// olmayanın talebini reddeder; dairesiz kurul üyesi ve yalnız site üyesi bu iki kısayolu görmez (kart ve çekmece öğesi
  /// eski kuralıyla durur). Tam ayrım (kapı izni olan dairesiz kullanıcı) için sunucuda ayrı bir "dairesi var" alanı
  /// gerekir.
  Set<SirketMenuItem> _quickActionItems() {
    bool apartmentSite(String code) =>
        _moduleAccess.isFiltering &&
        _moduleAccess.result!.sites.any((site) => site.doorAccess && site.isEnabled(code));
    return <SirketMenuItem>{
      SirketMenuItem.kapilar,
      SirketMenuItem.belgeler,
      if (apartmentSite(PlatformModuleCodes.workTracking)) SirketMenuItem.taleplerim,
      if (apartmentSite(PlatformModuleCodes.visitorLog)) SirketMenuItem.ziyaretcilerim,
    };
  }

  /// Vitrinin "Ziyaretçi kodu" hızlı işlemi: çekmecedeki "Kurye / Misafir Geçiş Linki Oluştur" ile AYNI akış ve AYNI
  /// koşul ([_residentExtraActions]: daire sakini, Geçiş Kontrol açık, "Kapılar" erişilebilir, seçili kapıda misafir
  /// geçişine izin var). Süreli geçiş linki üretir; kapı AÇMAZ ve kapı durumu yoklaması gerektirmez. Koşul yoksa null.
  VoidCallback? _guestPassAction(UserSession session) {
    final door = _doorControlDoor;
    if (session.role != UserRole.apartmentOwner ||
        _showsIndividualHome(session) ||
        _isDoorControlClosed(session) ||
        !_canAccessMenu(SirketMenuItem.kapilar, session.role) ||
        door == null ||
        !ResidentDoorActions.canCreateGuestPass(door)) {
      return null;
    }
    return () => CreateGuestPassDialog.show(
          context,
          door: door,
          authService: widget.authService,
          showMessage: _showMessage,
        );
  }

  /// Panel = MODÜL VİTRİNİ. Kartlar çekmecenin AYNI öğe listesinden türetilir ([_visibleMenuItems]); karta dokunmak
  /// çekmeceden seçmekle aynı gezinmedir ([_openMenuItem]). Kapı paneli "Kapılar" kartının arkasındadır.
  ///
  /// Bireysel ana ekranın (dairelerim, katılım başvurularım, cihazlarım) tek yolu "Kapılar" öğesidir; Geçiş Kontrol
  /// KAPALIyken o öğe vitrinde de çekmecede de yoktur. Bu bölümler kaybolmasın diye (kapı kartı olmadan) vitrinin
  /// altında gösterilir ve başvuru durumu kartını o çizer (vitrin ikinci kez çizmez).
  Widget _buildShowcase(UserSession session) {
    final audience = showcaseAudience(
      role: session.role,
      isResidentMode: _isResidentMode,
      canToggleMode: _canToggleDualMode,
    );
    final embedIndividualHome = _showsIndividualHome(session) && _isDoorControlClosed(session);
    final applications = embedIndividualHome ? null : _applicationsFor(session);
    final resident = audience == ShowcaseAudience.resident;
    final showcase = ModuleShowcaseView(
      key: _showcaseKey,
      session: session,
      audience: audience,
      menuItems: _visibleMenuItems(session),
      badgeCounts: _menuBadgeCounts(session),
      badgeNouns: _menuBadgeNouns,
      onOpen: _openMenuItem,
      fetchMyFinance: resident ? widget.authService.getMyFinance : null,
      residentSiteName: resident ? _residentSiteName() : null,
      applications: applications,
      onReapply: applications == null ? null : _reapplySiteApplication,
      onRefreshAccount: () => _refreshAccountAfterApproval(),
      applicantRole: canApplyForSite(session.role),
      belowHero: resident ? _unreadAnnouncementCardSlot(session) : null,
      onOpenHelp: _openHelpPage,
      debtSiteCodes: resident ? _debtSiteCodes() : null,
      quickActionItems: resident ? _quickActionItems() : null,
      onCreateGuestPass: resident ? _guestPassAction(session) : null,
    );
    if (!embedIndividualHome) return showcase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        showcase,
        const SizedBox(height: AppSpace.xl),
        _buildIndividualHome(session),
      ],
    );
  }

  Widget _buildContentView(UserSession session) {

    if (!_canAccessMenu(_selectedMenu, session.role)) {

      _selectedMenu = SirketMenuItem.dashboard;

    }



    switch (_selectedMenu) {
      case SirketMenuItem.dashboard:
        return _buildShowcase(session);

      case SirketMenuItem.kapilar:
      case SirketMenuItem.ellerSerbest:
        if (_showsIndividualHome(session)) {
          return _buildIndividualHome(session);
        }
        // Geçiş Kontrol modülü kapalı (bağlı olunan tüm sitelerde; süper kullanıcıda seçili sitede):
        // kapı kartları yerine bilgi kartı.
        if (_isDoorControlClosed(session)) {
          final canManage =
              session.role == UserRole.superUser ||
              (session.role == UserRole.siteManager && !_isResidentMode);
          return DoorControlDisabledCard(
            onOpenModules: canManage
                ? () => _goToMenu(SirketMenuItem.moduller)
                : null,
          );
        }
        _renderedDoorPanel = _DoorPanelSnapshot.of(this);
        return DashboardView(

          session: session,

          sites: _doorControlSelectableSites(
            _doorControlSitesPage?.sites ?? const <SiteRecord>[],
          ),

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
          canTryLocalDoorOpen: _canTryLocalDoorOpenNow,

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
          return ResidentProfileView(
            session: session,
            authService: widget.authService,
            showNotificationPrefs: _receivesAnnouncements(session.role),
          );

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

          authService: widget.authService,

          showNotificationPrefs: _receivesAnnouncements(session.role),

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

          busyApartmentPins: _busyApartmentPins,

          onRefreshSites: () => _loadSites(force: true),

          onLoadPage: (page) => _loadSites(page: page),

          onOpenAddSite: () => _openSiteDialog(),

          addSiteLabel: usesSiteApplicationFlow(session.role, _siteApplications)
              ? 'Site Başvurusu'
              : 'Yeni Site',

          onSelectSite: _selectSite,

          onEditSite: (site) => _openSiteDialog(site: site),

          onDeleteSite: _deleteSite,

          onApproveSite: (site) =>

              _resolveSiteApproval(siteCode: site.id, action: 'approve'),

          onRejectSite: (site) =>

              _resolveSiteApproval(siteCode: site.id, action: 'reject'),

          onEditApartmentResident: _openApartmentResidentDialog,

          onResetApartmentPin: _resetApartmentPin,

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

      case SirketMenuItem.moduller:
        return ModulesView(
          key: _modulesViewKey,
          authService: widget.authService,
          onModulesChanged: () {
            unawaited(_moduleAccess.refresh());
            unawaited(_loadSuperDoorModule());
          },
        );

      case SirketMenuItem.denetimKaydi:
        return AuditLogView(
          key: _auditLogViewKey,
          authService: widget.authService,
        );

      case SirketMenuItem.platformAyarlari:
        return PlatformSettingsView(
          key: _platformSettingsKey,
          authService: widget.authService,
        );

      case SirketMenuItem.istemciHatalari:
        return ClientErrorsView(
          key: _clientErrorsKey,
          authService: widget.authService,
        );

      case SirketMenuItem.anketler:
        return SurveyManagerView(
          key: _surveyManagerKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _surveyManageSites(session.role),
          onOpenModules: _canManagePeople(session.role) ? () => _goToMenu(SirketMenuItem.moduller) : null,
        );

      case SirketMenuItem.anket:
        return SurveyResidentView(
          key: _surveyResidentKey,
          authService: widget.authService,
          sites: _surveyResidentSites(session.role),
        );

      case SirketMenuItem.kararDefteri:
        return DecisionManagerView(
          key: _decisionManagerKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _decisionManageSites(session.role),
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role) ? () => _goToMenu(SirketMenuItem.moduller) : null,
        );

      case SirketMenuItem.kararlar:
        return DecisionResidentView(
          key: _decisionResidentKey,
          authService: widget.authService,
          sites: _decisionResidentSites(session.role),
        );

      case SirketMenuItem.modulTalepleri:
        return ModuleRequestsView(
          key: _moduleRequestsViewKey,
          authService: widget.authService,
          // Karardan sonra çekmece rozeti (bekleyen sayı) sunucudan hemen yeniden okunur.
          onChanged: () => unawaited(_moduleAccess.refresh()),
        );

      case SirketMenuItem.siteBasvurulari:
        return SiteApplicationsView(
          key: _siteApplicationsViewKey,
          authService: widget.authService,
          // Karardan sonra çekmece rozeti (bekleyen sayı) sunucudan hemen yeniden okunur.
          onChanged: () => unawaited(_moduleAccess.refresh()),
        );

      case SirketMenuItem.kisiler:
        return PeopleView(
          key: _peopleViewKey,
          authService: widget.authService,
          manageSites: _canManagePeople(session.role),
          readOnlySites: _boardPeopleSites(),
        );

      case SirketMenuItem.duyurular:
        return AnnouncementsView(
          key: _announcementsKey,
          authService: widget.authService,
          manageSites: _canManageAnnouncements(session.role),
          readOnlySites: _boardPeopleSites(),
          showInbox: _hasAnnouncementInbox(session.role) || _forceAnnouncementInbox,
          inboxSites: _announcementInboxSites(),
          notifier: _announcements,
          preferInbox: _forceAnnouncementInbox,
        );

      case SirketMenuItem.finans:
        return FinanceView(
          key: _financeViewKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _financeSites(session.role),
          canReopen: session.role == UserRole.superUser,
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role)
              ? () => _goToMenu(SirketMenuItem.moduller)
              : null,
        );

      case SirketMenuItem.borcum:
        return MyFinanceView(key: _myFinanceViewKey, authService: widget.authService);

      case SirketMenuItem.belgeler:
        return DocumentsView(
          key: _documentsKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          manageSites: _documentManageSites(session.role),
          showResident: _documentResidentSites(session.role).isNotEmpty,
          residentSites: _documentResidentSites(session.role),
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role)
              ? () => _goToMenu(SirketMenuItem.moduller)
              : null,
        );

      case SirketMenuItem.talepler:
        return WorkManagerView(
          key: _workManagerKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _workManageSites(session.role),
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role)
              ? () => _goToMenu(SirketMenuItem.moduller)
              : null,
        );

      case SirketMenuItem.taleplerim:
        return WorkResidentView(
          key: _workResidentKey,
          authService: widget.authService,
          sites: _workResidentSites(session.role),
        );

      case SirketMenuItem.rezervasyonlar:
        return ReservationManagerView(
          key: _reservationManagerKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _reservationManageSites(session.role),
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role)
              ? () => _goToMenu(SirketMenuItem.moduller)
              : null,
        );

      case SirketMenuItem.rezervasyon:
        return ReservationResidentView(
          key: _reservationResidentKey,
          authService: widget.authService,
          sites: _reservationResidentSites(session.role),
        );

      case SirketMenuItem.ziyaretciKayitlari:
        return VisitorManagerView(
          key: _visitorManagerKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _visitorManageSites(session.role),
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role)
              ? () => _goToMenu(SirketMenuItem.moduller)
              : null,
        );

      case SirketMenuItem.ziyaretcilerim:
        return VisitorResidentView(
          key: _visitorResidentKey,
          authService: widget.authService,
          sites: _visitorResidentSites(session.role),
          // Kayıt görüldü işaretlenince çekmece rozeti sunucudan hemen tazelenir.
          onUnreadChanged: _refreshVisitorBadge,
        );

      case SirketMenuItem.sozlesmeler:
        return ContractsView(
          key: _contractsKey,
          authService: widget.authService,
          manageAllSites: session.role == UserRole.superUser,
          sites: _contractSites(session.role),
          // Modül kapalıysa Modüller ekranına yönlendirir (süper kullanıcı açar, yönetici talep eder).
          onOpenModules: _canManagePeople(session.role)
              ? () => _goToMenu(SirketMenuItem.moduller)
              : null,
        );

      case SirketMenuItem.katilimVeKurulum:
        return JoinAndSetupView(
          authService: widget.authService,
          session: session,
          onOpenClaimDevice: _openClaimDeviceFlow,
          onOpenJoinSite: _openJoinRequestFlow,
          onRefreshAll: _loadInitialData,
          applications: _applicationsFor(session),
          onRefreshAccount: () => _refreshAccountAfterApproval(),
        );

      case SirketMenuItem.cihazEkle:
        if (session.role == UserRole.individual) {
          return DeviceAddView(
            title: 'Cihaz Ekle',
            qrTitle: 'Kutu QR Kodunu Okut',
            qrDescription:
                'Cihaz ambalaj kutusundaki QR kodu kameraya göstererek cihazı hesabınıza bağlayın. Site yöneticisi olmak için Site Kur ile başvuru yapabilirsiniz.',
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
