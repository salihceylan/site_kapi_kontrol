// FAZ 5 / A2-G4: bireysel ana görünümün kapı kartı.
//
// `IndividualHomeView._buildDoorCard` (~720 satır iç içe üçlü/gradyan, 5 kopya düğme) ayrı bir
// widget'a çıkarıldı. İki katman:
//  - [IndividualDoorCardModel]: DOKUNMA/GÖRÜNÜRLÜK türetimi (saf Dart; hangi düğme görünür, "kapıyı aç"
//    hangi durumda, cihaz/kapsam rozetleri). Eski koşullar BİREBİR korunur; kendi birim testi vardır.
//  - [IndividualDoorCard]: yalnız görünüm. Kapı açma tek `DoorOpenButton` (çubuk); QR/misafir eylemleri
//    ikincil (tonal) düğmeler. Davranış (kapıyı açma, QR modalı, konum) üst görünümde kalır.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kartta gösterilen "kapıyı aç" eyleminin türü (aynı anda en çok biri görünür).
enum IndividualDoorOpenKind {
  /// Kapıda uzaktan açma yetkisi yok (ya da yalnız QR ile açılır): düğme gösterilmez.
  none,

  /// "Kapıyı Aç": kapıda ekran ve QR okuyucu YOK; kapı açmanın tek yolu budur.
  main,

  /// "Uzaktan Aç": kapıda ekran ya da QR okuyucu VAR; uzaktan açma ek bir yoldur.
  remote,
}

/// Cihazın (röle kartı) kapıdaki durumu.
enum IndividualDoorDeviceStatus {
  /// Kapıya cihaz atanmamış.
  noDevice,

  /// Cihaz çevrimiçi.
  online,

  /// Cihaz atanmış ama çevrimdışı.
  offline,
}

/// Kapı kartının eylem ve rozet TÜRETİMİ (sunum modeli).
///
/// Eski `_buildDoorCard` koşullarının birebir karşılığıdır:
///  - "Kapı Ekranından QR Oku": `door.hasDisplay`
///  - "Kapıya QR Göster": `door.canShowQrCode`
///  - "Misafir Kodu": `door.canCreateGuestPass`
///  - "Kapıyı Aç": `!hasDisplay && !canShowQrCode && canOpenRemote && !isQrOnly`
///  - "Uzaktan Aç": `canOpenRemote && !isQrOnly && (hasDisplay || canShowQrCode)`
///  - kapı açma durumu: komut sürüyorsa opening; cihaz çevrimiçiyse ready; aksi hâlde offline (dokunuş
///    eskisi gibi çevrimiçi bilgisini yeniden kontrol eden akışı çağırır: davranış değişmez).
@immutable
class IndividualDoorCardModel {
  const IndividualDoorCardModel._({
    required this.isOpening,
    required this.isOnline,
    required this.deviceStatus,
    required this.deviceStatusLabel,
    required this.deviceStatusTone,
    required this.scopeLabel,
    required this.scopeIcon,
    required this.scopeTone,
    required this.showScanScreenQr,
    required this.showShowQr,
    required this.showGuestPass,
    required this.openKind,
    required this.openState,
  });

  /// [door] kaydından ve "komut sürüyor mu" bilgisinden kartı türetir.
  factory IndividualDoorCardModel.of(
    DoorRecord door, {
    required bool isOpening,
  }) {
    final uid = door.assignedDeviceUid;
    final isAssigned = uid != null && uid.isNotEmpty;
    final isOnline = door.assignedDeviceIsOnline == true;

    final IndividualDoorDeviceStatus status;
    final String statusLabel;
    final AppTone statusTone;
    if (!isAssigned) {
      status = IndividualDoorDeviceStatus.noDevice;
      statusLabel = 'Cihaz Yok';
      statusTone = AppTone.neutral;
    } else if (isOnline) {
      status = IndividualDoorDeviceStatus.online;
      statusLabel = 'Çevrimiçi';
      statusTone = AppTone.success;
    } else {
      status = IndividualDoorDeviceStatus.offline;
      statusLabel = 'Çevrimdışı';
      statusTone = AppTone.danger;
    }

    final String scopeLabel;
    final IconData scopeIcon;
    final AppTone scopeTone;
    if (door.accessScope == 'BLOCK') {
      final block = door.blockName;
      scopeLabel = block != null && block.isNotEmpty
          ? '$block Kapısı'
          : 'Blok Kapısı';
      scopeIcon = Icons.apartment_rounded;
      scopeTone = AppTone.primary;
    } else if (door.accessScope == 'CUSTOM') {
      scopeLabel = 'Özel İzinli Kapı';
      scopeIcon = Icons.vpn_key_rounded;
      scopeTone = AppTone.violet;
    } else {
      scopeLabel = 'Site Ortak Kapısı';
      scopeIcon = Icons.public_rounded;
      scopeTone = AppTone.info;
    }

    final hasQrPath = door.hasDisplay || door.canShowQrCode;
    final canRemoteOpen = door.canOpenRemote && !door.isQrOnly;
    final IndividualDoorOpenKind openKind;
    if (!canRemoteOpen) {
      openKind = IndividualDoorOpenKind.none;
    } else if (hasQrPath) {
      openKind = IndividualDoorOpenKind.remote;
    } else {
      openKind = IndividualDoorOpenKind.main;
    }

    return IndividualDoorCardModel._(
      isOpening: isOpening,
      isOnline: isOnline,
      deviceStatus: status,
      deviceStatusLabel: statusLabel,
      deviceStatusTone: statusTone,
      scopeLabel: scopeLabel,
      scopeIcon: scopeIcon,
      scopeTone: scopeTone,
      showScanScreenQr: door.hasDisplay,
      showShowQr: door.canShowQrCode,
      showGuestPass: door.canCreateGuestPass,
      openKind: openKind,
      openState: isOpening
          ? DoorOpenState.opening
          : (isOnline ? DoorOpenState.ready : DoorOpenState.offline),
    );
  }

  /// "Kapıyı aç" komutu şu an sürüyor.
  final bool isOpening;

  /// Cihaz çevrimiçi bilgisi (`assignedDeviceIsOnline == true`): düğme tonlarını/durumunu ve Wi-Fi
  /// rozetini belirler (eski `isOnline` ile aynı; cihaz atanmamışsa "Cihaz Yok" etiketi ayrıdır).
  final bool isOnline;

  final IndividualDoorDeviceStatus deviceStatus;

  /// Cihaz durum rozeti metni: 'Cihaz Yok' / 'Çevrimiçi' / 'Çevrimdışı'.
  final String deviceStatusLabel;
  final AppTone deviceStatusTone;

  /// Kapsam rozeti metni ('Site Ortak Kapısı', 'A Blok Kapısı', 'Özel İzinli Kapı').
  final String scopeLabel;
  final IconData scopeIcon;
  final AppTone scopeTone;

  /// "Kapı Ekranından QR Oku" görünür mü.
  final bool showScanScreenQr;

  /// "Kapıya QR Göster" görünür mü.
  final bool showShowQr;

  /// "Misafir Kodu" görünür mü.
  final bool showGuestPass;

  final IndividualDoorOpenKind openKind;

  /// [DoorOpenButton] durumu ([openKind] none ise anlamsızdır).
  final DoorOpenState openState;

  /// Karta en az bir eylem düğmesi konur mu.
  bool get hasActions =>
      openKind != IndividualDoorOpenKind.none ||
      showScanScreenQr ||
      showShowQr ||
      showGuestPass;

  /// [DoorOpenButton] etiketi (mevcut metinler).
  String get openLabel =>
      openKind == IndividualDoorOpenKind.main ? 'Kapıyı Aç' : 'Uzaktan Aç';

  /// [DoorOpenButton] açılıyor etiketi (mevcut metinler).
  String get openingLabel => openKind == IndividualDoorOpenKind.main
      ? 'Kapı Açılıyor...'
      : 'Açılıyor...';
}

/// Bireysel kullanıcının "Yetkili Kapılarım" kartı.
///
/// Sunum: kapı adı + konum, rozet satırı (cihaz durumu [nabızlı], kapsam, konum koruması, optik QR,
/// Wi-Fi sinyali) ve eylemler. Birincil eylem tek dolu düğmedir ([DoorOpenButton]); QR ve misafir
/// eylemleri tonal düğmelerdir (çevrimdışıyken nötr ton: dokunuş yine çevrimiçi bilgisini yeniden
/// kontrol eder). [successTick] her başarılı kapı açmada bir artar (başarı tiki).
///
/// Taşma: kapı adı 3, konum 2 satıra sarar; rozetler `Wrap`; düğme etiketleri 2 satıra sarar. Üst öğe
/// sınırlı genişlikte olmalıdır (Column çocuğu).
class IndividualDoorCard extends StatelessWidget {
  const IndividualDoorCard({
    super.key,
    required this.door,
    required this.isOpening,
    required this.onOpenDoor,
    required this.onScanScreenQr,
    required this.onShowQr,
    required this.onGuestPass,
    this.successTick = 0,
  });

  final DoorRecord door;

  /// Bu kapı için "aç" komutu sürüyor.
  final bool isOpening;

  /// Bu kapıdaki başarılı açma sayısı (her artışta başarı tiki gösterilir).
  final int successTick;

  final VoidCallback onOpenDoor;
  final VoidCallback onScanScreenQr;
  final VoidCallback onShowQr;
  final VoidCallback onGuestPass;

  @override
  Widget build(BuildContext context) {
    final m = IndividualDoorCardModel.of(door, isOpening: isOpening);
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final block = door.blockName;
    final location =
        '${door.siteName ?? 'Site'}${block != null && block.isNotEmpty ? ' • $block' : ''}';

    final actions = <Widget>[
      if (m.openKind != IndividualDoorOpenKind.none)
        DoorOpenButton(
          key: const ValueKey<String>('individual_door_open'),
          variant: DoorOpenVariant.bar,
          state: m.openState,
          label: m.openLabel,
          openingLabel: m.openingLabel,
          doneLabel: 'Gönderildi',
          icon: Icons.lock_open_rounded,
          onPressed: onOpenDoor,
          successTick: successTick,
        ),
      if (m.showScanScreenQr)
        PrimaryActionButton(
          label: 'Kapı Ekranından QR Oku',
          icon: Icons.qr_code_scanner_rounded,
          tone: m.isOnline ? AppTone.info : AppTone.neutral,
          variant: AppButtonVariant.tonal,
          onPressed: onScanScreenQr,
        ),
      if (m.showShowQr)
        PrimaryActionButton(
          label: 'Kapıya QR Göster',
          icon: Icons.qr_code_2_rounded,
          tone: m.isOnline ? AppTone.success : AppTone.neutral,
          variant: AppButtonVariant.tonal,
          onPressed: onShowQr,
        ),
      if (m.showGuestPass)
        PrimaryActionButton(
          label: 'Misafir Kodu',
          icon: Icons.person_add_alt_1_rounded,
          tone: AppTone.violet,
          variant: AppButtonVariant.tonal,
          onPressed: onGuestPass,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: m.scopeTone.gradient,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        Icons.meeting_room_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          door.doorName,
                          style: th.titleLarge,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: ExcludeSemantics(
                              child: Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: p.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: Text(
                              location,
                              style: th.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                StatusChip(
                  label: m.deviceStatusLabel,
                  tone: m.deviceStatusTone,
                  pulse: m.deviceStatus == IndividualDoorDeviceStatus.online,
                ),
                StatusChip(
                  label: m.scopeLabel,
                  tone: m.scopeTone,
                  icon: m.scopeIcon,
                ),
                if (door.requireGeofence)
                  StatusChip(
                    label: 'Konum (${door.geofenceRadiusMeters}m)',
                    tone: AppTone.info,
                    icon: Icons.near_me_rounded,
                  ),
                if (door.canShowQrCode)
                  const StatusChip(
                    label: 'Optik QR',
                    tone: AppTone.success,
                    icon: Icons.qr_code_scanner_rounded,
                  ),
                if (door.assignedDeviceWifiSignalPercent != null && m.isOnline)
                  StatusChip(
                    label: '%${door.assignedDeviceWifiSignalPercent}',
                    tone: AppTone.neutral,
                    icon: Icons.wifi_rounded,
                  ),
              ],
            ),
            if (m.hasActions) ...[
              const SizedBox(height: AppSpace.md),
              const Divider(),
              const SizedBox(height: AppSpace.md),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.sm),
                actions[i],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
