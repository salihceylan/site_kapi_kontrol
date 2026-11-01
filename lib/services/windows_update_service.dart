import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:url_launcher/url_launcher.dart';

class WindowsUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String downloadUrl;
  final String? notes;
  final bool mandatory;

  const WindowsUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    this.notes,
    this.mandatory = false,
  });
}

/// Windows masaüstü uygulaması için otomatik güncelleme ve sürüm kontrol servisi.
class WindowsUpdateService {
  WindowsUpdateService._();
  static final WindowsUpdateService instance = WindowsUpdateService._();

  bool _isChecking = false;
  bool _isUpdating = false;

  /// Yalnızca Windows masaüstü ortamında etkindir (Web ve mobil cihazlarda güvenle no-op döner).
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Sunucudaki Windows sürüm manifestini denetler.
  Future<WindowsUpdateInfo?> checkUpdate({String? customBaseUrl}) async {
    if (!isSupported) return null;

    try {
      final baseUrl = customBaseUrl ?? AppConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/api/windows/version');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        debugPrint('[WindowsUpdater] Sürüm denetimi başarısız: HTTP ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final latestVersion = (data['version'] ?? '1.0.0').toString();
      final latestBuild = int.tryParse((data['build_number'] ?? data['build'] ?? 1).toString()) ?? 1;
      final rawDownloadUrl = (data['download_url'] ?? '/download/windows').toString();
      final fullDownloadUrl = rawDownloadUrl.startsWith('http')
          ? rawDownloadUrl
          : '$baseUrl$rawDownloadUrl';
      final notes = data['notes']?.toString();
      final mandatory = data['mandatory'] == true;

      // Yerel uygulama sürümünü al
      String currentVersion = '1.0.0';
      int currentBuild = 1;
      try {
        final pkg = await PackageInfo.fromPlatform();
        currentVersion = pkg.version;
        currentBuild = int.tryParse(pkg.buildNumber) ?? 1;
      } catch (e) {
        debugPrint('[WindowsUpdater] PackageInfo okunamadı: $e');
      }

      final hasUpdate = _compareVersions(latestVersion, latestBuild, currentVersion, currentBuild);

      return WindowsUpdateInfo(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        downloadUrl: fullDownloadUrl,
        notes: notes,
        mandatory: mandatory,
      );
    } catch (e) {
      debugPrint('[WindowsUpdater] Güncelleme denetimi hatası: $e');
      return null;
    }
  }

  /// İki sürümü karşılaştırır.
  bool _compareVersions(String remoteVer, int remoteBuild, String localVer, int localBuild) {
    if (remoteBuild > localBuild) return true;
    final rParts = remoteVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lParts = localVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }

  /// Güncelleme kontrolünü tetikler ve gerekirse kullanıcıya diyalog sunar.
  Future<void> checkForUpdates(BuildContext context, {bool silent = false}) async {
    if (!isSupported || _isChecking || _isUpdating) return;
    if (silent && kDebugMode) return;
    _isChecking = true;

    try {
      final info = await checkUpdate();
      if (!context.mounted) return;

      if (info == null) {
        if (!silent) {
          AppSnack.show(
            context,
            'Güncelleme sunucusuna bağlanılamadı. Lütfen internet bağlantınızı kontrol edin.',
            kind: AppSnackKind.warning,
          );
        }
        return;
      }

      if (info.hasUpdate) {
        await _showUpdatePromptDialog(context, info);
      } else if (!silent) {
        AppSnack.show(
          context,
          'Uygulamanız güncel (v${info.currentVersion}). Yeni bir güncelleme bulunmuyor.',
          kind: AppSnackKind.info,
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  /// Yeni sürüm bulunduğunda açılan bilgilendirme ve onay diyaloğu.
  Future<void> _showUpdatePromptDialog(BuildContext context, WindowsUpdateInfo info) async {
    if (!context.mounted) return;

    await showDialog<bool>(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (dialogCtx) => PopScope(
        canPop: !info.mandatory,
        child: AppDialog(
          title: 'Yeni Sürüm Mevcut! (v${info.latestVersion})',
          icon: Icons.system_update_rounded,
          tone: AppTone.primary,
          actions: [
            if (!info.mandatory)
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Daha Sonra'),
              ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogCtx).pop(true);
                downloadAndApplyUpdate(context, info);
              },
              icon: const Icon(Icons.system_update_rounded, size: 18),
              label: const Text('Şimdi Güncelle'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sistem güncellendi. Yeni özelliklerin ve plaka tanıma motorunun kesintisiz çalışması için güncellemeyi yükleyin.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpace.sm),
              AppCard(
                tone: AppTone.info,
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mevcut Sürüm: v${info.currentVersion} (Derleme: ${info.currentBuild})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('Yeni Sürüm: v${info.latestVersion} (Derleme: ${info.latestBuild})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                    if (info.notes != null && info.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Yenilikler: ${info.notes}', style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Güncelleme paketini (%TEMP%) dizinine indirip arka planda uygulayarak uygulamayı yeniden başlatır.
  Future<void> downloadAndApplyUpdate(BuildContext context, WindowsUpdateInfo info) async {
    if (!isSupported || _isUpdating) return;
    _isUpdating = true;

    // İlerleme modalını göster
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Güncelleme paketi indiriliyor...');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AppDialog(
          title: 'Uygulama Güncelleniyor',
          icon: Icons.downloading_rounded,
          tone: AppTone.primary,
          actions: [
            TextButton(
              onPressed: () {
                // Tarayıcıdan manuel indirme alternatifi
                launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
                Navigator.of(dialogCtx).pop();
                _isUpdating = false;
              },
              child: const Text('Tarayıcı ile İndir'),
            ),
          ],
          child: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (ctx, progress, _) => ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (ctx, status, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: AppSpace.md),
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    progress > 0
                        ? '%${(progress * 100).toStringAsFixed(0)} tamamlandı'
                        : 'Bağlantı kuruluyor...',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('İndirme başarısız: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final updateZipFile = File('${tempDir.path}\\site_kapi_update.zip');
      final sink = updateZipFile.openWrite();

      int downloaded = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          progressNotifier.value = downloaded / contentLength;
          final mbDone = (downloaded / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          statusNotifier.value = 'İndiriliyor: $mbDone MB / $mbTotal MB';
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      statusNotifier.value = 'Güncelleme paketi hazırlanıyor...';
      progressNotifier.value = 1.0;

      // Uygulamanın kurulu olduğu klasör ve çalıştırılabilir dosya
      final currentExePath = Platform.resolvedExecutable;
      final appDir = File(currentExePath).parent.path;
      final currentPid = pid;

      // Updater batch betiği oluştur
      final updaterScriptFile = File('${tempDir.path}\\site_kapi_updater.bat');
      final batchContent = '''
@echo off
chcp 65001 >nul
echo ----------------------------------------------------
echo Site Yonetim & Kapi Kontrol Guncelleniyor...
echo Lutfen bekleyin, uygulama otomatik olarak acilacaktir.
echo ----------------------------------------------------

set APP_PID=$currentPid
set APP_DIR="$appDir"
set APP_EXE="$currentExePath"
set ZIP_PATH="${updateZipFile.path}"
set EXTRACT_DIR="${tempDir.path}\\site_kapi_extracted"

:: Uygulamanin kapanmasini bekle
:wait_app
tasklist /fi "PID eq %APP_PID%" 2>NUL | find "%APP_PID%" >NUL
if not errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto wait_app
)

timeout /t 1 /nobreak >nul

:: Yeni surumu temp klasore cikar
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%"
mkdir "%EXTRACT_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP_PATH%' -DestinationPath '%EXTRACT_DIR%' -Force"

:: Dosyalari uygulama dizinine tasi/kopyala
if exist "%EXTRACT_DIR%\\site_kapi_kontrol.exe" (
    xcopy "%EXTRACT_DIR%\\*" "%APP_DIR%\\" /s /e /y /q >nul
) else (
    for /d %%D in ("%EXTRACT_DIR%\\*") do (
        if exist "%%D\\site_kapi_kontrol.exe" (
            xcopy "%%D\\*" "%APP_DIR%\\" /s /e /y /q >nul
        )
    )
)

:: Temizlik yap
del "%ZIP_PATH%" >nul 2>&1
rmdir /s /q "%EXTRACT_DIR%" >nul 2>&1

:: Uygulamayi yeniden baslat
echo Guncelleme tamamlandi. Uygulama baslatiliyor...
start "" "%APP_EXE%"

:: Bu betigi sil ve cik
(goto) 2>nul & del "%~f0"
''';

      await updaterScriptFile.writeAsString(batchContent, encoding: utf8);

      statusNotifier.value = 'Uygulama yeniden başlatılıyor...';
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Batch dosyasını bağımsız süreç olarak çalıştır ve mevcut uygulamadan çık
      await Process.start(
        'cmd.exe',
        ['/c', updaterScriptFile.path],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e) {
      debugPrint('[WindowsUpdater] Güncelleme uygulama hatası: $e');
      _isUpdating = false;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        AppSnack.show(
          context,
          'Otomatik güncelleme uygulanamadı: $e. Tarayıcıdan indirmeyi deneyin.',
          kind: AppSnackKind.error,
        );
      }
    }
  }
}
