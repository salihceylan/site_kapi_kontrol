import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/submit_join_request_dialog.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_application_flow.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/claim_device_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';
import 'package:site_kapi_kontrol/ui/widgets/individual_apartment_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/individual_door_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/join_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/setup_option_card.dart';

class IndividualHomeView extends StatefulWidget {
  const IndividualHomeView({
    super.key,
    required this.session,
    required this.authService,
    required this.onRefreshAll,
    this.applications,
    this.onRefreshAccount,
    this.canAddDevice = false,
  });

  final UserSession session;
  final AuthService authService;
  final VoidCallback onRefreshAll;

  /// Site başvurusu durumu (Platform: site başvurusu). YALNIZ bireysel / daire kullanıcısına verilir: null
  /// iken başvuru kartı ve "Site Kurmak İçin Başvur" eylemi hiç görünmez (eski ekran birebir aynıdır).
  final SiteApplicationTracker? applications;

  /// Onaylanmış başvuruda rolü elle yenileme ("Hesabı yenile").
  final Future<void> Function()? onRefreshAccount;

  /// "Cihaz Ekle" düğmeleri görünsün mü? Yalnız site yöneticisi (Geçiş Kontrol modülü açık sitede) ya da süper kullanıcı cihaz
  /// ekleyebilir (bkz. [canAddDevice]); varsayılan false: bireysel / daire kullanıcısı cihaz ekleyemez, mevcut cihazları listelenir.
  final bool canAddDevice;

  @override
  State<IndividualHomeView> createState() => IndividualHomeViewState();
}

class IndividualHomeViewState extends State<IndividualHomeView>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _claimedDevices = [];
  List<JoinRequestRecord> _myRequests = [];
  List<MyApartmentRecord> _myApartments = [];
  List<DoorRecord> _myDoors = [];
  final Set<int> _openingDoorIds = {};
  // Kapı başına başarılı "aç" sayısı: DoorOpenButton'un başarı tikini (successTick) tetikler.
  final Map<int, int> _doorOpenTicks = {};
  // Kapı çevrimiçi bilgisinin periyodik tazelenmesi (15 sn): uygulama arka plandayken ya da bu
  // görünüm opak bir sayfanın altındayken ağ isteği yapmaz, ardışık hatada üstel geri çekilir
  // (tavan 30 sn) ve her tur öncekinin bitmesini bekler (üst üste binmez).
  late final AdaptivePoller _doorsPoller = AdaptivePoller(
    interval: const Duration(seconds: 15),
    isActive: _isRefreshActive,
    poll: _pollDoors,
  );
  bool _isLoading = true;
  String? _errorMessage;
  int? _selectedSiteCode;

  // Site kurma / başvuru formu çift dokunuşta iki kez açılmasın.
  bool _openingSetup = false;

  Map<int, String> get _availableSites {
    final map = <int, String>{};
    for (final door in _myDoors) {
      if (door.siteName != null && door.siteName!.isNotEmpty) {
        map[door.siteCode] = door.siteName!;
      }
    }
    for (final apt in _myApartments) {
      if (apt.siteName.isNotEmpty) {
        map[apt.siteCode] = apt.siteName;
      }
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadAll();
    // Kapı çevrimiçi bilgisi (Kural 7: uygulamayı kapatıp açmadan güncel kalmalı) periyodik tazelenir.
    _doorsPoller.start();
    // Başvuru durumu: hiç yüklenmediyse / eskiyse okunur (bekleyen varken tracker kendisi yoklar).
    unawaited(widget.applications?.ensureLoaded());
  }

  @override
  void didUpdateWidget(IndividualHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Başvuru takipçisi değişti ya da rol değişti (örn. bireysel <-> daire kullanıcısı): açık ekran durumu
    // yeniden yükler (aynı takipçi nesnesi olsa bile; tazelik kuralı gereksiz çağrıyı önler).
    if (oldWidget.applications != widget.applications ||
        oldWidget.session.role != widget.session.role) {
      unawaited(widget.applications?.ensureLoaded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doorsPoller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Arka planda geçen süre boyunca bayatlamış olabilir: hemen tazele, sonra 15 sn'lik düzen.
      _doorsPoller.resetBackoff();
      _doorsPoller.start(immediately: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _doorsPoller.stop();
    }
  }

  /// Tazeleme şu an gerekli mi? Uygulama ön planda ve bu görünüm opak bir sayfanın altında değil.
  bool _isRefreshActive() {
    if (!mounted) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return false;
    return TickerMode.getValuesNotifier(context).value.enabled;
  }

  /// Yoklama turu: true başarılı, false hata (geri çekilme), null atlandı.
  Future<bool?> _pollDoors() async {
    if (!mounted) return null;
    return _loadDoors();
  }

  /// Kapının güncel (çevrimiçi) kaydını döndürür. Önbellekteki durum çevrimdışı gösteriyorsa bu
  /// bilgi bayat olabilir: kapı listesi bir kez tazelenir; hâlâ çevrimdışıysa uyarı gösterilip
  /// null döner (kararı sunucu verir; cihaz bu arada bağlandıysa kullanıcı elle yenilemek zorunda kalmaz).
  Future<DoorRecord?> _requireOnlineDoor(DoorRecord door) async {
    var current = door;
    if (current.assignedDeviceIsOnline != true) {
      await _loadDoors();
      if (!mounted) return null;
      current = _myDoors.firstWhere((d) => d.id == door.id, orElse: () => door);
    }
    if (current.assignedDeviceIsOnline != true) {
      _showOfflineDoorWarning(current);
      return null;
    }
    return current;
  }

  Future<void> loadAll() async {
    await Future.wait([
      _loadDoors(),
      _loadDevices(),
      _loadRequests(),
      _loadApartments(),
    ]);
  }

  Future<void> _loadDevices() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final devices = await widget.authService.getMyClaimedDevices();
      if (!mounted) return;
      setState(() {
        _claimedDevices = devices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Cihazlar yüklenirken bir sorun oluştu.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRequests() async {
    final (list, _) = await widget.authService.getMyJoinRequests();
    if (!mounted) return;
    if (list != null) {
      setState(() => _myRequests = list);
    }
  }

  Future<void> _loadApartments() async {
    final (list, _) = await widget.authService.getMyApartments();
    if (!mounted) return;
    if (list != null) {
      setState(() => _myApartments = list);
    }
  }

  /// Kapı listesini yükler; true = liste alındı (hata değil). Yoklama sonucu ekrandakiyle aynıysa
  /// görünüm yeniden kurulmaz (kapı kayıtları alan alan karşılaştırılır).
  Future<bool> _loadDoors() async {
    // Masaüstü widget senkronu AuthService.listMyDoors içinde (tek kaynak) yapılır;
    // liste boşsa widget da orada temizlenir.
    final (doors, _) = await widget.authService.listMyDoors();
    if (!mounted) return false;
    if (doors == null) return false;
    if (_sameDoors(_myDoors, doors)) {
      _myDoors = doors;
    } else {
      setState(() => _myDoors = doors);
    }
    return true;
  }

  static bool _sameDoors(List<DoorRecord> a, List<DoorRecord> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].hasSameFieldsAs(b[i])) return false;
    }
    return true;
  }

  void _showOfflineDoorWarning(DoorRecord door) {
    if (!mounted) return;
    AppSnack.show(
      context,
      '${door.doorName} şu an çevrimdışı. Cihaz internete bağlı olmadığından işlem yapılamaz.',
      kind: AppSnackKind.error,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _handleOpenDoor(DoorRecord requestedDoor) async {
    if (_openingDoorIds.contains(requestedDoor.id)) return;
    final door = await _requireOnlineDoor(requestedDoor);
    if (door == null || !mounted || _openingDoorIds.contains(door.id)) return;

    setState(() => _openingDoorIds.add(door.id));
    final (status, error) = await widget.authService.openDoor(
      doorId: door.id,
      door: door,
    );
    if (!mounted) return;
    setState(() {
      _openingDoorIds.remove(door.id);
      // Başarı sinyali: DoorOpenButton tikini ve success tonuna geçişi tetikler (sayaç sıfırlanmaz).
      if (error == null) {
        _doorOpenTicks[door.id] = (_doorOpenTicks[door.id] ?? 0) + 1;
      }
    });

    if (error != null) {
      AppSnack.show(context, error, kind: AppSnackKind.error);
    } else {
      AppSnack.show(
        context,
        '"${door.doorName}" kapısı açılıyor...',
        kind: AppSnackKind.success,
      );
    }
  }

  Future<void> _openQrModal(DoorRecord requestedDoor) async {
    final door = await _requireOnlineDoor(requestedDoor);
    if (door == null || !mounted) return;

    if (door.requireGeofence) {
      AppSnack.show(
        context,
        'Konum kontrol ediliyor...',
        duration: const Duration(seconds: 1),
      );

      final result = await GeofenceService.instance.verifyWithinGeofence(
        targetLat: door.geofenceLatitude,
        targetLng: door.geofenceLongitude,
        radiusMeters: door.geofenceRadiusMeters,
      );

      if (!mounted) return;

      if (!result.allowed) {
        showDialog(
          context: context,
          builder: (ctx) => AppDialog(
            title: 'Konum Hatası',
            icon: Icons.location_off_outlined,
            tone: AppTone.danger,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Anladım'),
              ),
            ],
            child: Text(
              result.errorMessage ?? 'Kapı çevresinde olmadığınız tespit edildi.',
            ),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DynamicQrPassModal(
        door: door,
        authService: widget.authService,
      ),
    );
  }

  Future<void> _handleScanScreenQr(DoorRecord requestedDoor) async {
    final door = await _requireOnlineDoor(requestedDoor);
    if (door == null || !mounted) return;

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          title: 'Kapı Ekranından QR Oku',
          instructionText: 'Cihazın 2.4" ekranındaki karekodu kameranıza gösterin.',
        ),
      ),
    );

    if (scanned == null || scanned.trim().isEmpty || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Karekod doğrulanıyor, kapı açılıyor...'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Konum zorunluysa AuthService konumu alır; alınamazsa istek gönderilmez ve neden gösterilir.
    final (result, error) = await widget.authService.openDoorWithScannedQr(
      qrPayload: scanned.trim(),
      requireLocation: door.requiresLocationForQrScan,
    );

    if (!mounted) return;

    if (error != null) {
      showDialog(
        context: context,
        builder: (ctx) => AppDialog(
          title: 'Geçiş Reddedildi',
          icon: Icons.error_outline_rounded,
          tone: AppTone.danger,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tamam'),
            ),
          ],
          child: Text(error),
        ),
      );
    } else {
      final doorName = result?['door_name'] ?? door.doorName;
      AppSnack.show(
        context,
        '✅ "$doorName" kapısı açıldı!',
        kind: AppSnackKind.success,
      );
      // Canlı yenileme (Kural 7)
      await loadAll();
      widget.onRefreshAll();
    }
  }

  void _openGuestPassDialog(DoorRecord door) {
    CreateGuestPassDialog.show(
      context,
      door: door,
      authService: widget.authService,
      showMessage: (msg) {
        if (!mounted) return;
        AppSnack.show(context, msg);
      },
    );
  }

  Future<void> _confirmRemoveMember(MyApartmentRecord apt, ApartmentMemberRecord member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Üyeyi Çıkar',
        icon: Icons.person_remove_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('İptal'),
          ),
          FilledButton(
            // Ön plan da verilir: sade temada ana eylem metni koyu temada koyudur (mercan üstünde 3,80:1 kalırdı).
            style: FilledButton.styleFrom(backgroundColor: AppTone.danger.a, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Çıkar'),
          ),
        ],
        child: Text('${member.fullName} isimli sakin "${apt.fullDisplayName}" dairesinden çıkarılsın mı?'),
      ),
    );

    if (confirm == true) {
      final (ok, msg) = await widget.authService.removeApartmentMember(
        apt.apartmentId,
        member.userCode,
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        msg ?? (ok ? 'Üye çıkarıldı.' : 'İşlem başarısız.'),
        kind: ok ? AppSnackKind.success : AppSnackKind.error,
      );
      if (ok) {
        await _loadApartments();
      }
    }
  }

  Future<void> _openClaimDialog() async {
    final claimedUid = await ClaimDeviceDialog.show(context, widget.authService);
    if (!mounted) return;
    if (claimedUid != null && claimedUid.isNotEmpty) {
      await loadAll();
      widget.onRefreshAll();
      if (!mounted) return;
      final role = widget.authService.session?.role ?? widget.session.role;
      if (canApplyForSite(role)) {
        // Cihaz sahiplenmek kullanıcıyı site yöneticisi YAPMAZ (rol değişmez): bilgi + "Site Kur" eylemi.
        if (_openingSetup) return;
        _openingSetup = true;
        try {
          await offerSiteApplicationAfterClaim(
            context,
            authService: widget.authService,
            deviceUid: claimedUid,
            tracker: widget.applications,
          );
        } finally {
          _openingSetup = false;
        }
        return;
      }
      // Yönetici / süper kullanıcı: eski akış, kullanıcıyı doğrudan Site Kurulum Sihirbazı'na yönlendir
      await _openSetupSite(claimedUid);
    }
  }

  Future<void> _openJoinSiteDialog() async {
    final success = await SubmitJoinRequestDialog.show(
      context,
      authService: widget.authService,
    );
    if (!mounted) return;
    if (success == true) {
      await loadAll();
      widget.onRefreshAll();
    }
  }

  /// Site kurma formu (cihazlı akış): rol bireysel / daire kullanıcısıysa BAŞVURU, yönetici / süper
  /// kullanıcıysa anlık kurulum ([SetupSiteDialog.modeFor]).
  Future<void> _openSetupSite([String? uid]) async {
    if (_openingSetup) return;
    _openingSetup = true;
    try {
      final result = await SetupSiteDialog.show(
        context,
        authService: widget.authService,
        deviceUid: uid,
      );
      if (!mounted) return;
      if (result == SetupSiteOutcome.created) {
        AppSnack.show(
          context,
          'Site ve bloklar başarıyla kuruldu!',
          kind: AppSnackKind.success,
          duration: const Duration(seconds: 3),
        );
        widget.onRefreshAll();
      } else {
        // Başvuru gönderildi / zaten bekleyen var / sonuç belirsiz: durum sunucudan okunur.
        syncApplicationsAfterForm(widget.applications, result);
      }
    } finally {
      _openingSetup = false;
    }
  }

  /// "Site Kurmak İçin Başvur" / "Yeniden başvur": başvuru formunu açar ([previous] ile önceki değerlerle).
  Future<void> _openApplicationForm([SiteApplication? previous]) async {
    if (_openingSetup) return;
    _openingSetup = true;
    try {
      await openSiteApplicationForm(
        context,
        authService: widget.authService,
        tracker: widget.applications,
        previous: previous,
      );
    } finally {
      _openingSetup = false;
    }
  }

  /// Site filtre çipleri: yatay kaydırma yerine `Wrap` (çip gizlenmez, büyük yazıda alt satıra iner).
  Widget _buildSiteFilterBar() {
    final sites = _availableSites;
    if (sites.length < 2) return const SizedBox.shrink();

    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final totalDoorCount = _myDoors.length;
    final totalAptCount = _myApartments.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.domain_rounded, size: 16, color: p.textMuted),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Site Seçimi / Filtre',
                  style: th.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              _SiteFilterChip(
                label: 'Tüm Siteler',
                count: totalDoorCount + totalAptCount,
                isSelected: _selectedSiteCode == null,
                onTap: () => setState(() => _selectedSiteCode = null),
              ),
              for (final entry in sites.entries)
                _SiteFilterChip(
                  label: entry.value,
                  count:
                      _myDoors.where((d) => d.siteCode == entry.key).length +
                      _myApartments.where((a) => a.siteCode == entry.key).length,
                  isSelected: _selectedSiteCode == entry.key,
                  onTap: () => setState(() => _selectedSiteCode = entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    // Bir kişi bireysel kullanıcıdan daire kullanıcılığına veya yöneticiliğe geçtiği zaman
    // panelindeki "Daireye Katıl" ve "Site Kurulumu" kartları
    // panelde görünmez; sandwich menüdeki "Daireye Katıl" menüsünden erişilir.
    // Başvuru akışında (applications != null: bireysel / daire kullanıcısı) cihaz sahiplenmek kullanıcıyı
    // yönetici yapmaz; cihazı olan kişi de "Site Kur" ile başvurabilmelidir: cihaz kartları gizlemez.
    final hasTransitioned = widget.session.role == UserRole.siteManager ||
        widget.session.role == UserRole.superUser ||
        widget.session.role == UserRole.apartmentOwner ||
        (_claimedDevices.isNotEmpty && widget.applications == null) ||
        _myApartments.isNotEmpty;
    if (hasTransitioned) {
      return const SizedBox.shrink();
    }

    final hasNoContent = _myApartments.isEmpty &&
        _myDoors.isEmpty &&
        _claimedDevices.isEmpty &&
        _myRequests.isEmpty;
    final firstIndex = hasNoContent ? 1 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasNoContent) ...[
          const StaggeredEntry(index: 0, child: _WelcomeCard()),
          const SizedBox(height: AppSpace.lg),
        ],

        // 1. KART: SİTE SAKİNİ KARTI (üstte; zümrüt/başarı tonu)
        StaggeredEntry(
          index: firstIndex,
          child: SetupOptionCard(
            tone: AppTone.success,
            icon: Icons.key_rounded,
            title: 'Site Sakini Girişi',
            badge: 'HIZLI KATILIM',
            description:
                'Yöneticinizin verdiği katılım QR kodunu okutarak dairenize hemen bağlanın.',
            action: PrimaryActionButton(
              label: 'Site Sakini Olarak Devam Et',
              icon: Icons.qr_code_scanner_rounded,
              tone: AppTone.success,
              onPressed: _openJoinSiteDialog,
            ),
          ),
        ),

        // Cihaz ekleme (yalnız canAddDevice true ise: site kurulumu Kapılar altında değil, Site Hizmetleri altındadır)
        if (widget.canAddDevice) ...[
          const SizedBox(height: AppSpace.lg),
          StaggeredEntry(
            index: firstIndex + 1,
            child: SetupOptionCard(
              tone: AppTone.primary,
              icon: Icons.add_to_photos_rounded,
              title: 'Cihaz',
              badge: 'CİHAZ',
              description: 'Yeni cihazınızı kutu QR koduyla hesabınıza ekleyin.',
              action: PrimaryActionButton(
                label: 'Cihaz Ekle',
                icon: Icons.add_to_photos_rounded,
                tone: AppTone.primary,
                onPressed: _openClaimDialog,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Listedeki her öğe için TEKİL anahtar: aynı kimlik tekrarlanırsa (bozuk/yinelenen sunucu kaydı)
  /// sonrakilere `#n` eklenir. Aynı üst öğenin altında yinelenen anahtar çerçeve hatasıdır; kimliği
  /// olan öğelerin durumu (başarı tiki, giriş animasyonu) yine kimliğe göre korunur.
  static List<ValueKey<String>> _uniqueKeys(Iterable<String> ids) {
    final seen = <String, int>{};
    final keys = <ValueKey<String>>[];
    for (final id in ids) {
      final count = seen[id] = (seen[id] ?? -1) + 1;
      keys.add(ValueKey<String>(count == 0 ? id : '$id#$count'));
    }
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    final sites = _availableSites;
    if (_selectedSiteCode != null && !sites.containsKey(_selectedSiteCode)) {
      _selectedSiteCode = null;
    }

    final displayedDoors = _selectedSiteCode == null
        ? _myDoors
        : _myDoors.where((d) => d.siteCode == _selectedSiteCode).toList();

    final displayedApartments = _selectedSiteCode == null
        ? _myApartments
        : _myApartments.where((a) => a.siteCode == _selectedSiteCode).toList();
    final doorKeys = _uniqueKeys(displayedDoors.map((d) => 'door-${d.id}'));
    final apartmentKeys = _uniqueKeys(
      displayedApartments.map((a) => 'apartment-${a.apartmentId}'),
    );
    final requestKeys = _uniqueKeys(_myRequests.map((r) => 'request-${r.id}'));
    final deviceKeys = _uniqueKeys(
      _claimedDevices.map((d) => 'device-${d['device_uid']}'),
    );

    // İlk yükleme: hiçbir bölüm gelmediyse içerik yerine iskelet. Yenilemede (içerik varken) mevcut
    // liste kalır ve alttaki küçük yükleme göstergesi sürer.
    final hasContent = _myDoors.isNotEmpty ||
        _myApartments.isNotEmpty ||
        _claimedDevices.isNotEmpty ||
        _myRequests.isNotEmpty;
    final showSkeleton = _isLoading && !hasContent;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Site başvurusu durumu (bekleyen / reddedildi / iptal / onaylandı): yalnız bireysel ve daire
          // kullanıcısında; durum alınamazsa hata + "Tekrar Dene" (asla "başvuru yok" denmez).
          if (widget.applications != null)
            SiteApplicationStatusCard(
              tracker: widget.applications!,
              onReapply: _openApplicationForm,
              onRefreshAccount: widget.onRefreshAccount,
              // Onaylandı kartı ve durum-alınamadı hatası yalnız her zaman başvuran olan rollerde; yönetici
              // panosunda (başvuru gerekli mi belirsiz) sessiz kalır.
              showApproved: canApplyForSite(widget.session.role),
              showLoadFailure: canApplyForSite(widget.session.role),
            ),

          // Site Switcher / Filtre Çipleri
          _buildSiteFilterBar(),

          if (showSkeleton) const _HomeSkeleton(),

          // 0. Yetkili Kapılarım Bölümü (Aşama 10 & 13)
          if (displayedDoors.isNotEmpty) ...[
            SectionHeader(
              title: 'Yetkili Kapılarım',
              count: displayedDoors.length,
              countSuffix: ' Kapı',
              trailing: IconButton(
                onPressed: _loadDoors,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Kapıları Yenile',
              ),
            ),
            const SizedBox(height: AppSpace.md),
            for (final (index, door) in displayedDoors.indexed)
              StaggeredEntry(
                key: doorKeys[index],
                index: index,
                child: IndividualDoorCard(
                  door: door,
                  isOpening: _openingDoorIds.contains(door.id),
                  successTick: _doorOpenTicks[door.id] ?? 0,
                  onOpenDoor: () => _handleOpenDoor(door),
                  onScanScreenQr: () => _handleScanScreenQr(door),
                  onShowQr: () => _openQrModal(door),
                  onGuestPass: () => _openGuestPassDialog(door),
                ),
              ),
            const SizedBox(height: AppSpace.lg),
          ],

          // Seçili sitede kapı yoksa bilgilendirme
          if (_selectedSiteCode != null &&
              displayedDoors.isEmpty &&
              _myDoors.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpace.lg),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: EmptyState.compact(
                  icon: Icons.info_outline_rounded,
                  title: 'Bu sitede size tanımlı aktif bir kapı bulunmuyor.',
                  tone: AppTone.neutral,
                ),
              ),
            ),

          // 1. Kayıtlı Dairelerim Bölümü
          if (displayedApartments.isNotEmpty) ...[
            SectionHeader(
              title: displayedApartments.length > 1
                  ? 'Kayıtlı Dairelerim'
                  : 'Kayıtlı Dairem',
              trailing: IconButton(
                onPressed: _loadApartments,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Daireleri Yenile',
              ),
            ),
            const SizedBox(height: AppSpace.md),
            for (final (index, apt) in displayedApartments.indexed)
              StaggeredEntry(
                key: apartmentKeys[index],
                index: index,
                child: IndividualApartmentCard(
                  apartment: apt,
                  onRemoveMember: (member) => _confirmRemoveMember(apt, member),
                ),
              ),
            const SizedBox(height: AppSpace.lg),
          ],

          // Hızlı İşlemler: Cihaz Ekle & Site Kur / Siteye Katıl (ilk yüklemede iskelet gösterilir)
          if (!showSkeleton) _buildQuickActions(),

          // Yükleniyor Göstergesi (yenileme: mevcut içerik varken)
          if (_isLoading && !showSkeleton)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          // Katılım Başvurularım (Varsa)
          if (_myRequests.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xl),
            SectionHeader(
              title: 'Katılım Başvurularım',
              trailing: IconButton(
                onPressed: _loadRequests,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Yenile',
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final (index, req) in _myRequests.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: StaggeredEntry(
                  key: requestKeys[index],
                  index: index,
                  child: JoinRequestCard(
                    title: req.siteName ?? 'Site #${req.siteCode}',
                    status: JoinRequestCard.statusOf(req),
                    details: [
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          if ((req.blockName ?? '').isNotEmpty)
                            Text(req.blockName!, style: th.bodySmall),
                          Text(
                            req.unitLabel ?? 'Daire ?',
                            style: th.bodySmall?.copyWith(
                              color: p.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '• ${formatDateTimeOrUnknown(req.createdAt)}',
                            style: th.bodySmall,
                          ),
                        ],
                      ),
                      if (req.isRejected &&
                          (req.rejectionReason ?? '').isNotEmpty)
                        Text(
                          'Gerekçe: ${req.rejectionReason!}',
                          style: th.bodySmall?.copyWith(
                            color: AppTone.danger.ink(p),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],

          // Sahiplenilen Cihazlar: Sadece kullanıcı cihaz sahiplenmişse görünür
          if (_claimedDevices.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xl),
            SectionHeader(
              title: 'Sahiplendiğim Cihazlar (${_claimedDevices.length})',
              trailing: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.canAddDevice)
                    TextButton.icon(
                      onPressed: _openClaimDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Cihaz Ekle'),
                    ),
                  IconButton(
                    onPressed: _loadDevices,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'Yenile',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),

            // Hata Mesajı
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: InlineNotice(message: _errorMessage!),
              ),

            // Cihaz Kartları Listesi
            for (final (index, dev) in _claimedDevices.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: StaggeredEntry(
                  key: deviceKeys[index],
                  index: index,
                  child: _ClaimedDeviceCard(
                    device: dev,
                    onSetupSite: _openSetupSite,
                    tracker: widget.applications,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Site Kurulumu" kartının eylemleri (başvuru akışı): birincil "Site Kurmak İçin Başvur"
/// (bekleyen başvuru varken "Başvurunuz İnceleniyor", durum bilinmezken de pasif; [SiteApplyCta]), ikincil
/// "Cihaz Ekle" (YALNIZ [onClaimDevice] verilirse: site yöneticisi / süper) ve
/// "Abonelikle hemen site aç — Yakında…" pasif satırı. Düğme etiketleri sarar; kırpılmaz.
class _SiteApplyActions extends StatelessWidget {
  const _SiteApplyActions({
    required this.tracker,
    required this.onApply,
    this.onClaimDevice,
  });

  final SiteApplicationTracker tracker;
  final Future<void> Function() onApply;
  final VoidCallback? onClaimDevice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SiteApplyCta(tracker: tracker, onApply: onApply),
        if (onClaimDevice != null) ...[
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const ValueKey<String>('site_application_claim_device'),
            onPressed: onClaimDevice,
            style: tonalActionStyle(context),
            icon: const Icon(Icons.add_to_photos_rounded, size: 20),
            label: const Text('Cihaz Ekle', textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        const SiteSubscriptionComingSoonRow(),
      ],
    );
  }
}

/// Site filtre çipi: seçili = birincil ton zemini + kenar; en az 44 dp yükseklik; sayaç rozeti.
class _SiteFilterChip extends StatelessWidget {
  const _SiteFilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    const tone = AppTone.primary;
    final ink = tone.ink(p);
    final radius = BorderRadius.circular(AppRadius.md);

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected
            ? Color.alphaBlend(tone.tint(p), p.surface)
            : p.surface,
        clipBehavior: Clip.antiAlias,
        animationDuration: AppMotion.of(context, AppMotion.base),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: isSelected ? ink : p.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          // Dokunma hedefi >= 44 dp: kenarlık Material şeklinde olduğundan InkWell tüm çipi kaplar.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.apartment_rounded,
                      size: 16,
                      color: isSelected ? ink : p.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: th.bodyMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected ? p.text : p.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected ? tone.tint(p) : p.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm,
                        vertical: 1,
                      ),
                      child: Text(
                        '$count',
                        style: th.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? ink : p.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// İlk açılışta (hiç içerik yokken) karşılama kartı.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    const tone = AppTone.primary;

    return AppCard(
      child: Row(
        children: [
          const IconOrb(
            icon: Icons.waving_hand_rounded,
            tone: tone,
            size: 48,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Hoş Geldiniz!', style: th.titleLarge),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Başlamak için size uygun seçeneğe dokunun:',
                  style: th.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// İlk yükleme iskeleti: iki kapı kartı yer tutucusu (tek paylaşılan shimmer; yükleme bitince kalkar).
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_DoorCardSkeleton(), _DoorCardSkeleton()],
      ),
    );
  }
}

class _DoorCardSkeleton extends StatelessWidget {
  const _DoorCardSkeleton();

  @override
  Widget build(BuildContext context) {
    // Yüklenen kartın düzenini taklit eder (solda yuvarlak düğme, sağda ad/konum/rozetler, altta iki
    // eylem çubuğu): içerik gelince yer değiştirme zıplaması olmaz.
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SkeletonBox(width: 116, height: 116, radius: AppRadius.pill),
                SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: SkeletonBox(height: 18),
                      ),
                      SizedBox(height: AppSpace.sm),
                      FractionallySizedBox(
                        widthFactor: 0.45,
                        child: SkeletonBox(height: 12),
                      ),
                      SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.sm,
                        children: [
                          SkeletonBox(
                            width: 84,
                            height: 28,
                            radius: AppRadius.pill,
                          ),
                          SkeletonBox(
                            width: 108,
                            height: 28,
                            radius: AppRadius.pill,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpace.md),
            SkeletonBox(height: 48, radius: AppRadius.md),
            SizedBox(height: AppSpace.sm),
            SkeletonBox(height: 48, radius: AppRadius.md),
          ],
        ),
      ),
    );
  }
}

/// Cihaz kartındaki "Siteyi Kur" düğmesi. Başvuran rolde bekleyen başvuru varken ya da başvuru durumu
/// bilinmezken pasiftir; nedeni ipucu ve ekran okuyucu ipucuyla söylenir.
class _SetupSiteButton extends StatelessWidget {
  const _SetupSiteButton({required this.uid, required this.onSetupSite, this.tracker});

  final String uid;
  final ValueChanged<String> onSetupSite;
  final SiteApplicationTracker? tracker;

  Widget _button(VoidCallback? onPressed) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.apartment_rounded, size: 16),
    label: const Text('Siteyi Kur'),
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tracker = this.tracker;
    if (tracker == null) return _button(() => onSetupSite(uid));
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final reason = siteApplyDisabledReason(tracker.applyAvailability);
        if (reason == null) return _button(() => onSetupSite(uid));
        return Tooltip(
          message: reason,
          child: Semantics(hint: reason, child: _button(null)),
        );
      },
    );
  }
}

/// "Sahiplendiğim Cihazlar" listesindeki bir cihaz kartı.
class _ClaimedDeviceCard extends StatelessWidget {
  const _ClaimedDeviceCard({required this.device, required this.onSetupSite, this.tracker});

  final Map<String, dynamic> device;

  /// Başvuru takipçisi (başvuran roller): bekleyen başvuru varken ya da durum bilinmezken "Siteyi Kur"
  /// pasiftir (neden ipucuyla söylenir). Null: eski davranış.
  final SiteApplicationTracker? tracker;

  /// "Siteyi Kur" düğmesi: cihaz UID'si ile site kurulum sihirbazını açar.
  final ValueChanged<String> onSetupSite;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final uid = device['device_uid']?.toString() ?? '-';
    final hw = device['hardware_type']?.toString() ?? 'esp32_wroom';
    final isWroom = hw.toLowerCase().contains('wroom');
    final claimedAt =
        device['claimed_at']?.toString() ?? device['created_at']?.toString();
    final siteCode = device['site_code'];
    final tone = isWroom ? AppTone.violet : AppTone.primary;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Satır: İkon, Cihaz UID ve donanım modeli
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconOrb(
                icon: Icons.developer_board_rounded,
                tone: tone,
                size: 44,
                shape: IconOrbShape.squircle,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uid,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: th.titleMedium?.copyWith(letterSpacing: 0.5),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: ExcludeSemantics(
                            child: Icon(
                              Icons.memory_rounded,
                              size: 14,
                              color: p.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isWroom
                                ? 'ESP32-WROOM-32E Röle Kartı'
                                : 'ESP32-C3 Süper Mini',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          const Wrap(
            children: [
              StatusChip(
                label: 'Sahiplenildi',
                tone: AppTone.success,
                icon: Icons.check_circle_rounded,
              ),
            ],
          ),

          // 3. Satır: Kayıt Tarihi & Durum / Site Kur Butonu (Asla Taşmaz)
          if (claimedAt != null) ...[
            const SizedBox(height: AppSpace.md),
            const Divider(),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Kayıt: ${claimedAt.substring(0, claimedAt.length >= 16 ? 16 : claimedAt.length).replaceAll('T', ' ')}',
                  style: th.bodySmall,
                ),
                if (siteCode != null)
                  StatusChip(label: 'Site: $siteCode', tone: AppTone.success)
                else
                  _SetupSiteButton(uid: uid, onSetupSite: onSetupSite, tracker: tracker),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
