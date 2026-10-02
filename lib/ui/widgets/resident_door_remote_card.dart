import 'package:flutter/material.dart';
import '../../models/door_record.dart';
import '../../models/door_runtime_status.dart';
import '../../models/site_record.dart';
import '../../services/auth_service.dart';
import '../../services/geofence_service.dart';
import '../../services/voice_door_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/app_snack.dart';
import '../design/buttons.dart';
import '../design/door_open_button.dart';
import '../design/motion_widgets.dart';
import '../design/status_chip.dart';
import '../design/tokens.dart';
import '../pages/qr_scan_page.dart';
import 'dynamic_qr_pass_modal.dart';
import 'voice_live_banner.dart';

/// Büyük kapı düğmesine dokununca ne olacağı ([ResidentDoorUiState.tap] sonucu).
enum ResidentDoorTap {
  /// Hiçbir şey: kapı açılıyor ya da komut verilemiyor (yetki/cihaz/durum yükleniyor).
  none,

  /// Kapı açma komutu (`onOpenDoor`).
  openDoor,

  /// Dinamik karekodu göster (çevrimiçi/konum denetimi `_handleQrPass` içindedir).
  showQr,

  /// "Kapı şu an çevrimdışı" uyarısı.
  offlineWarning,
}

/// Sakin kartının türetilmiş durumu: büyük düğmenin durumu/etiketi/ikonu/tonu/dokunma eylemi ve durum
/// satırı. SAF'tır (widget ve BuildContext'ten bağımsız): iç içe üçlü ifadelerin yerini alır ve
/// `test/resident_door_ui_state_test.dart` ile eski davranışla eşdeğerliği sınanır.
@immutable
class ResidentDoorUiState {
  const ResidentDoorUiState({
    required this.hasDoor,
    required this.isDeviceAssigned,
    required this.canRemote,
    required this.canQr,
    required this.isCloudOnline,
    required this.canTryLocalDoorOpen,
    required this.isOpeningDoor,
    required this.isLoadingStatus,
  });

  /// Kartın girdilerinden (kapı kaydı + çalışma durumu + bayraklar) türetir.
  factory ResidentDoorUiState.of({
    required DoorRecord? door,
    required DoorRuntimeStatus? runtimeStatus,
    required bool canTryLocalDoorOpen,
    required bool isOpeningDoor,
    required bool isLoadingStatus,
  }) {
    return ResidentDoorUiState(
      hasDoor: door != null,
      isDeviceAssigned:
          door?.assignedDeviceUid != null && door!.assignedDeviceUid!.trim().isNotEmpty,
      canRemote: door?.canOpenRemote ?? true,
      canQr: door?.canOpenQr ?? false,
      isCloudOnline: runtimeStatus?.mqttConnected == true,
      canTryLocalDoorOpen: canTryLocalDoorOpen,
      isOpeningDoor: isOpeningDoor,
      isLoadingStatus: isLoadingStatus,
    );
  }

  final bool hasDoor;
  final bool isDeviceAssigned;
  final bool canRemote;
  final bool canQr;
  final bool isCloudOnline;
  final bool canTryLocalDoorOpen;
  final bool isOpeningDoor;
  final bool isLoadingStatus;

  /// Bulut çevrimdışı ama telefon cihazı yerel ağda görüyor ve yerel açma mümkün.
  bool get isLocalOnline => !isCloudOnline && canTryLocalDoorOpen;

  bool get isOnline => isCloudOnline || isLocalOnline;

  /// Uzaktan açma kapalı, karekod açık: büyük düğme karekod gösterir.
  bool get isQrOnly => hasDoor && !canRemote && canQr;

  bool get commandEnabled =>
      isDeviceAssigned && canRemote && isOnline && !isOpeningDoor && !isLoadingStatus;

  /// Büyük düğmeye dokununca olacak eylem.
  ///
  /// Açılırken dokunma yoktur. (Eski kodda yalnız-karekod kapıda komut sürerken dış `GestureDetector`
  /// karekod penceresini açıyordu; `DoorOpenState.opening` dokunmayı kabul etmediği için artık açmaz.)
  ResidentDoorTap get tap {
    if (isOpeningDoor) return ResidentDoorTap.none;
    if (isQrOnly) return isOnline ? ResidentDoorTap.showQr : ResidentDoorTap.offlineWarning;
    if (commandEnabled) return ResidentDoorTap.openDoor;
    return isOnline ? ResidentDoorTap.none : ResidentDoorTap.offlineWarning;
  }

  /// [DoorOpenButton] durumu: komut sürüyor -> opening; dokununca iş yapılıyor -> ready; cihaza
  /// ulaşılamıyor (dokununca uyarı) -> offline; dokunma yok -> disabled.
  DoorOpenState get buttonState {
    if (isOpeningDoor) return DoorOpenState.opening;
    return switch (tap) {
      ResidentDoorTap.openDoor || ResidentDoorTap.showQr => DoorOpenState.ready,
      ResidentDoorTap.offlineWarning => DoorOpenState.offline,
      ResidentDoorTap.none => DoorOpenState.disabled,
    };
  }

  /// Canlı düğmenin tonu: karekod = success, yerel ağ = warning, bulut = primary.
  AppTone get buttonTone =>
      isQrOnly ? AppTone.success : (isLocalOnline ? AppTone.warning : AppTone.primary);

  IconData get buttonIcon {
    if (isQrOnly) return Icons.qr_code_2_rounded;
    if (commandEnabled) {
      return isLocalOnline ? Icons.wifi_rounded : Icons.lock_open_rounded;
    }
    return canRemote ? Icons.lock_outline_rounded : Icons.block_rounded;
  }

  /// Açılmıyorken düğme etiketi (açılırken `DoorOpenButton.openingLabel` gösterilir).
  String get buttonLabel {
    if (isQrOnly) return isOnline ? 'QR KOD İLE AÇ' : 'ÇEVRİMDİŞI';
    if (commandEnabled) return isLocalOnline ? 'YEREL AĞDAN AÇ' : 'KAPIYI AÇ';
    if (!canRemote) return 'UZAKTAN KAPALI';
    return isDeviceAssigned ? 'ÇEVRİMDİŞI' : 'KAPALI';
  }

  /// Düğmenin altındaki durum cümlesi (cümleler ve emojiler eskisiyle birebir).
  String get statusText {
    if (!isDeviceAssigned) return 'Bu kapıya henüz cihaz atanmamış.';
    if (isOpeningDoor) return 'Kapı tetikleniyor, lütfen bekleyin...';
    if (isLoadingStatus) return 'Cihaz durumu kontrol ediliyor...';
    if (isQrOnly) return '📷 Bu sitede yalnızca QR Kod ile giriş aktiftir.';
    if (!canRemote) return '🚫 Bu kapıda uzaktan açma yetkisi kapalıdır.';
    if (isCloudOnline) return '🟢 Çevrimiçi - Kapıyı açmak için dokunun';
    if (isLocalOnline) return '🟡 Yerel Ağda Aktif - Kapıyı açmak için dokunun';
    return '🔴 Cihaz Çevrimdışı';
  }

  /// Durum cümlesinin tonu (`ink` rengiyle yazılır): sorun = danger, bekleme = primary, kontrol
  /// = neutral, karekod/çevrimiçi = success, yerel ağ = warning.
  AppTone get statusTone {
    if (!isDeviceAssigned) return AppTone.danger;
    if (isOpeningDoor) return AppTone.primary;
    if (isLoadingStatus) return AppTone.neutral;
    if (isQrOnly) return AppTone.success;
    if (!canRemote) return AppTone.danger;
    if (isCloudOnline) return AppTone.success;
    if (isLocalOnline) return AppTone.warning;
    return AppTone.danger;
  }

  @override
  bool operator ==(Object other) =>
      other is ResidentDoorUiState &&
      other.hasDoor == hasDoor &&
      other.isDeviceAssigned == isDeviceAssigned &&
      other.canRemote == canRemote &&
      other.canQr == canQr &&
      other.isCloudOnline == isCloudOnline &&
      other.canTryLocalDoorOpen == canTryLocalDoorOpen &&
      other.isOpeningDoor == isOpeningDoor &&
      other.isLoadingStatus == isLoadingStatus;

  @override
  int get hashCode => Object.hash(
    hasDoor,
    isDeviceAssigned,
    canRemote,
    canQr,
    isCloudOnline,
    canTryLocalDoorOpen,
    isOpeningDoor,
    isLoadingStatus,
  );
}

/// Daire sakini kumandası: site/kapı başlığı, tek büyük [DoorOpenButton], durum cümlesi, IP rozetleri
/// ve (yetkiye göre) karekod / ekran karekodu / misafir geçişi eylemleri.
///
/// Görünüm tasarım sistemine bağlıdır (`AppCard`, `StatusChip`, `DoorOpenButton`, `PrimaryActionButton`,
/// `Pop`, `VoiceLiveBanner`); durum türetimi [ResidentDoorUiState] içindedir ve davranış değişmedi.
class ResidentDoorRemoteCard extends StatelessWidget {
  const ResidentDoorRemoteCard({
    super.key,
    required this.selectedSite,
    required this.selectedDoor,
    required this.doors,
    required this.runtimeStatus,
    required this.isLoadingStatus,
    required this.isOpeningDoor,
    this.canTryLocalDoorOpen = false,
    this.isPhoneOnWifi = false,
    required this.onSelectDoor,
    required this.onOpenDoor,
    required this.onCreateGuestPass,
    this.voiceDoorService,
    this.authService,
    required this.roleColor,
    this.successTick = 0,
  });

  final SiteRecord? selectedSite;
  final DoorRecord? selectedDoor;
  final List<DoorRecord> doors;
  final DoorRuntimeStatus? runtimeStatus;
  final bool isLoadingStatus;
  final bool isOpeningDoor;
  final bool canTryLocalDoorOpen;
  final bool isPhoneOnWifi;
  final ValueChanged<int> onSelectDoor;
  final VoidCallback onOpenDoor;
  final VoidCallback onCreateGuestPass;
  final VoiceDoorService? voiceDoorService;
  final AuthService? authService;

  /// Rol rengi: API uyumluluğu için korunur; görünüm `AppTone` + palet ile çizilir.
  final Color roleColor;

  /// Kapı açma başarı sayacı: her ARTIŞTA büyük düğme başarı tikini gösterir (varsayılan 0 = bağlı
  /// değil). Ebeveyn komut hatasız bitince bir artırır; sıfırlamaya gerek yoktur.
  final int successTick;

  /// Başlıkta gösterilen site adı. Daire sakinleri site listesini göremediği için `selectedSite`
  /// çoğunlukla null'dır; bu durumda kapı kaydındaki site adı kullanılır (kapı adı iki kez yazılmasın).
  String get _siteTitle {
    final fromSite = selectedSite?.name.trim() ?? '';
    if (fromSite.isNotEmpty) return fromSite;
    final door = selectedDoor ?? (doors.isNotEmpty ? doors.first : null);
    final fromDoor = door?.siteName?.trim() ?? '';
    if (fromDoor.isNotEmpty) return fromDoor;
    return doors.isNotEmpty ? doors.first.doorName : 'Site Kapısı';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final door = selectedDoor;
    final status = runtimeStatus;
    final ui = ResidentDoorUiState.of(
      door: door,
      runtimeStatus: status,
      canTryLocalDoorOpen: canTryLocalDoorOpen,
      isOpeningDoor: isOpeningDoor,
      isLoadingStatus: isLoadingStatus,
    );
    final localIp = status?.localIp;
    final publicIp = status?.publicIp;
    final hasLocalIp = localIp != null && localIp.isNotEmpty;
    final hasPublicIp = publicIp != null && publicIp.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: AppCard(
            level: 2,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Üst kapsül rozet (büyük yazıda küçülür, kırpılmaz)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: StatusChip(
                    label: ui.isLocalOnline ? 'AHBU YEREL AĞ GEÇİŞ' : 'AHBU AKILLI GEÇİŞ',
                    tone: ui.isLocalOnline ? AppTone.warning : AppTone.primary,
                    icon: ui.isLocalOnline ? Icons.wifi_rounded : Icons.sensors_rounded,
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                // Site Adı
                Text(
                  _siteTitle,
                  textAlign: TextAlign.center,
                  style: th.headlineMedium,
                ),
                const SizedBox(height: AppSpace.xs),

                // Kapı Adı
                Text(
                  door != null ? '🚪 ${door.doorName}' : 'Kapı Seçilmedi',
                  textAlign: TextAlign.center,
                  style: th.titleMedium?.copyWith(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // Birden fazla kapı varsa: kapı seçici (kaydırma yok; sığmayanlar alt satıra iner)
                if (doors.length > 1) ...[
                  const SizedBox(height: AppSpace.lg),
                  _buildDoorChips(context),
                ],

                const SizedBox(height: AppSpace.xl),

                // TEK kapı açma düğmesi (daire; çap genişliğe göre 132-184 dp)
                DoorOpenButton(
                  key: const ValueKey<String>('resident_door_open_button'),
                  state: ui.buttonState,
                  label: ui.buttonLabel,
                  icon: ui.buttonIcon,
                  tone: ui.buttonTone,
                  successTick: successTick,
                  onPressed: ui.isQrOnly ? () => _handleQrPass(context) : onOpenDoor,
                  onBlocked: () => _showOfflineWarning(context),
                ),

                const SizedBox(height: AppSpace.lg),

                // Durum Mesajı (cümle değişince yalnız yeni cümle belirir)
                Pop(
                  key: ValueKey<String>(ui.statusText),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: Text(
                      ui.statusText,
                      textAlign: TextAlign.center,
                      style: th.bodyMedium?.copyWith(
                        color: ui.statusTone.ink(p),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                // IP Bilgisi Rozetleri (Yerel LAN & Genel WAN)
                if (hasLocalIp || hasPublicIp) ...[
                  const SizedBox(height: AppSpace.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      if (hasLocalIp)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: StatusChip(
                            label: 'Yerel IP: $localIp',
                            tone: AppTone.neutral,
                            icon: Icons.lan_rounded,
                          ),
                        ),
                      if (hasPublicIp)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: StatusChip(
                            label: 'Genel IP: $publicIp',
                            tone: AppTone.neutral,
                            icon: Icons.public_rounded,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (voiceDoorService != null) ...[
          const SizedBox(height: AppSpace.lg),
          _buildVoiceLiveBanner(context),
        ],
        // QR ile Giriş Butonu (Eğer bu kapıda/sitede QR aktifse)
        if (door?.canOpenQr == true) ...[
          const SizedBox(height: AppSpace.lg),
          PrimaryActionButton(
            label: '📲 Kapıya QR Göster',
            icon: Icons.qr_code_2_rounded,
            variant: AppButtonVariant.tonal,
            tone: ui.isOnline ? AppTone.success : AppTone.neutral,
            onPressed: ui.isOnline
                ? () => _handleQrPass(context)
                : () => _showOfflineWarning(context),
          ),
        ],
        // Ekrandaki Karekodu Tara Butonu (Yalnızca ekranlı cihaz takılı kapılarda görünür)
        if (door?.hasDisplay == true) ...[
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            label: '📷 Kapı Ekranından QR Oku',
            icon: Icons.qr_code_scanner_rounded,
            variant: AppButtonVariant.tonal,
            tone: ui.isOnline ? AppTone.info : AppTone.neutral,
            onPressed: ui.isOnline
                ? () => _handleScanScreenQr(context)
                : () => _showOfflineWarning(context),
          ),
        ],
        // Kurye / Misafir Geçişi Butonu (Eğer bu sitede izin verilmişse)
        if (door?.canCreateGuestPass == true) ...[
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            label: '📦 Kurye / Misafir Geçiş Linki Oluştur',
            icon: Icons.share_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: onCreateGuestPass,
          ),
        ],
      ],
    );
  }

  /// Kapı seçici: seçili kapı dolu mavi, diğerleri soluk yüzey (>= 4,5:1). Yatay kaydırma yok:
  /// sığmayan çipler alt satıra iner (hiçbir kapı gizli kalmaz).
  Widget _buildDoorChips(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [for (final door in doors) _buildDoorChip(context, door)],
    );
  }

  Widget _buildDoorChip(BuildContext context, DoorRecord door) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isSelected = selectedDoor?.id == door.id;
    return ChoiceChip(
      label: Text(door.doorName, maxLines: 2, overflow: TextOverflow.ellipsis),
      selected: isSelected,
      selectedColor: AppTone.primary.a,
      backgroundColor: p.surfaceMuted,
      checkmarkColor: Colors.white,
      labelStyle: th.bodyMedium?.copyWith(
        color: isSelected ? Colors.white : p.textSecondary,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected ? AppTone.primary.hue : p.border,
        width: isSelected ? 1.5 : 1.0,
      ),
      onSelected: (selected) {
        if (selected) {
          onSelectDoor(door.id);
        }
      },
    );
  }

  void _showOfflineWarning(BuildContext context) {
    AppSnack.show(
      context,
      '${selectedDoor?.doorName ?? "Kapı"} şu an çevrimdışı. Cihaz internete bağlı olmadığından işlem yapılamaz.',
      kind: AppSnackKind.error,
      duration: const Duration(seconds: 3),
      maxLines: 6,
    );
  }

  Future<void> _handleQrPass(BuildContext context) async {
    final isOnline = (runtimeStatus?.mqttConnected == true) || canTryLocalDoorOpen;
    if (!isOnline) {
      _showOfflineWarning(context);
      return;
    }

    final door = selectedDoor;
    if (door == null) return;

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

      if (!context.mounted) return;

      if (!result.allowed) {
        showDialog<void>(
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
            child: Text(result.errorMessage ?? 'Kapı çevresinde olmadığınız tespit edildi.'),
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => DynamicQrPassModal(door: door, authService: authService),
    );
  }

  Future<void> _handleScanScreenQr(BuildContext context) async {
    final isOnline = (runtimeStatus?.mqttConnected == true) || canTryLocalDoorOpen;
    if (!isOnline) {
      _showOfflineWarning(context);
      return;
    }

    final door = selectedDoor;
    if (door == null) return;

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          title: 'Kapı Ekranından QR Oku',
          instructionText: 'Cihazın 2.4" ekranındaki karekodu kameranıza gösterin.',
        ),
      ),
    );

    if (scanned == null || scanned.trim().isEmpty || !context.mounted) {
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
            Expanded(child: Text('Karekod doğrulanıyor, kapı açılıyor...')),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    final aService = authService;
    if (aService == null) return;

    // Konum zorunluysa AuthService konumu alır; alınamazsa istek gönderilmez ve neden gösterilir.
    final (result, error) = await aService.openDoorWithScannedQr(
      qrPayload: scanned.trim(),
      requireLocation: door.requiresLocationForQrScan,
    );

    if (!context.mounted) return;

    if (error != null) {
      showDialog<void>(
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
        '✅ $doorName açıldı! Geçişiniz kaydedildi.',
        kind: AppSnackKind.success,
        duration: const Duration(seconds: 3),
      );
      // scan-qr-open sunucuda kapıyı zaten açtı ve geçişi kaydetti: ikinci bir "kapı aç" komutu
      // (onOpenDoor) göndermek çift tetik/çift log üretir. Durum 3 sn'lik yoklamayla yenilenir.
    }
  }

  /// Sesli Dinleme Canlı Banner'ı: ortak [VoiceLiveBanner] (voice_live_banner.dart). Sakin kartı aday
  /// kapı vermez (`startListening()` ile aynı).
  Widget _buildVoiceLiveBanner(BuildContext context) {
    return VoiceLiveBanner(service: voiceDoorService!);
  }
}
