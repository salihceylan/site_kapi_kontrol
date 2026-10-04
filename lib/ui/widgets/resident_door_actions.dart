// Daire sakininin kapı eylemleri (kapıya QR göster, kapı ekranından QR oku, çevrimdışı uyarısı).
//
// Eskiden `ResidentDoorRemoteCard` içinde özel yöntemlerdi. Sade sakin ekranında bu eylemler karttan
// çekmece menüye taşındığından, kart ve ana sayfa AYNI mantığı kullansın diye buraya alındı:
// mantık, metinler ve sıralama eskisiyle birebir aynıdır.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';

/// Daire sakini kapı eylemleri. Hepsi statiktir; durum çağıranda kalır.
abstract final class ResidentDoorActions {
  /// "Kapıya QR Göster" görünür mü (kapıda QR ile açma yetkisi var).
  static bool canShowQr(DoorRecord? door) => door?.canOpenQr == true;

  /// "Kapı Ekranından QR Oku" görünür mü (yalnız ekranlı cihaz takılı kapılarda).
  static bool canScanScreenQr(DoorRecord? door) => door?.hasDisplay == true;

  /// "Kurye / Misafir Geçiş Linki Oluştur" görünür mü (sitede izin verilmişse).
  static bool canCreateGuestPass(DoorRecord? door) =>
      door?.canCreateGuestPass == true;

  /// Cihaz çevrimdışıyken kısa uyarı.
  static void showOfflineWarning(BuildContext context, DoorRecord? door) {
    AppSnack.show(
      context,
      '${door?.doorName ?? "Kapı"} şu an çevrimdışı. Cihaz internete bağlı olmadığından işlem yapılamaz.',
      kind: AppSnackKind.error,
      duration: const Duration(seconds: 3),
      maxLines: 6,
    );
  }

  /// Dinamik karekodu gösterir (çevrimiçi/konum denetimiyle). [isOnline]: bulut çevrimiçi ya da
  /// yerel ağda erişilebilir.
  static Future<void> showQrPass(
    BuildContext context, {
    required DoorRecord? door,
    required bool isOnline,
    required AuthService? authService,
  }) async {
    if (!isOnline) {
      showOfflineWarning(context, door);
      return;
    }
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
            child: Text(
              result.errorMessage ?? 'Kapı çevresinde olmadığınız tespit edildi.',
            ),
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => DynamicQrPassModal(door: door, authService: authService),
    );
  }

  /// Kapı ekranındaki karekodu okutup kapıyı açar (sunucuda açma + geçiş kaydı yapılır).
  static Future<void> scanScreenQr(
    BuildContext context, {
    required DoorRecord? door,
    required bool isOnline,
    required AuthService? authService,
  }) async {
    if (!isOnline) {
      showOfflineWarning(context, door);
      return;
    }
    if (door == null) return;

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          title: 'Kapı Ekranından QR Oku',
          instructionText:
              'Cihazın 2.4" ekranındaki karekodu kameranıza gösterin.',
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
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
      // göndermek çift tetik/çift log üretir. Durum 3 sn'lik yoklamayla yenilenir.
    }
  }
}
