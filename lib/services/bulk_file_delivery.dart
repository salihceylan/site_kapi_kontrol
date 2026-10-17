// Üretilen dosyayı (dışa aktarma, şablon, hata raporu) kullanıcıya verir (Platform Faz 2b).
//
// - Web ve masaüstü (Windows / macOS / Linux): "Kaydet" iletişim kutusu (`FilePicker.saveFile`). Linux'ta
//   share_plus dosya paylaşmaz; web'de saveFile indirmeye düşer.
// - Mobil (Android / iOS): paylaşım sayfası (`share_plus`).
//
// Dışa aktarılan dosya KİŞİSEL VERİ içerir. Mobilde paylaşım için kendi geçici klasörümüze yazılır ve paylaşım
// bitince klasör silinir (AccountExportSharer ile aynı tasarım): share_plus bellekteki dosyayı UUID'li bir alt
// klasöre yazar ve SİLMEZ. Silme [cleanupDelay] kadar ertelenir (alıcı uygulama dosyayı hâlâ okuyor olabilir) ve her
// yeni paylaşımda süresi dolmuş eski klasörler süpürülür.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';

/// Ekranların kullandığı arayüz (testlerde sahte uygulanır).
abstract class BulkFileDelivery {
  /// [file]'ı kullanıcıya verir. iPad / masaüstünde açılır pencerenin bağlanacağı yer [sharePositionOrigin]'dir.
  Future<ExportShareOutcome> deliver(RenderedFile file, {Rect? sharePositionOrigin, String subject});
}

class BulkFileSharer implements BulkFileDelivery {
  BulkFileSharer({
    Future<ShareResult> Function(ShareParams params)? shareFn,
    Future<Uri?> Function({required String fileName, required Uint8List bytes, required String mimeType})? saveFn,
    Future<Directory> Function()? tempRoot,
    Duration? cleanupDelay,
    Duration staleAfter = const Duration(minutes: 10),
    bool? useSaveDialog,
    bool? useTempFile,
    Future<void> Function()? purgeCaches,
    bool? isWeb,
  }) : _share = shareFn ?? SharePlus.instance.share,
       _purge = purgeCaches ?? (() => purgeLocalSharedCaches(pickerCache: false)),
       _save = saveFn ?? _defaultSave,
       _tempRoot = tempRoot ?? (() async => Directory.systemTemp),
       _cleanupDelay = cleanupDelay ?? _defaultCleanupDelay(),
       _staleAfter = staleAfter,
       _useSaveDialog = useSaveDialog ?? platformUsesSaveDialog,
       _useTempFile = useTempFile ?? !kIsWeb,
       _isWeb = isWeb ?? kIsWeb;

  static const String _dirPrefix = 'toplu_dosya_';

  static final Set<String> _livePaths = <String>{};
  static final Map<String, Timer> _timers = <String, Timer>{};

  /// Testler için: bekleyen gecikmeli silme sayısı.
  @visibleForTesting
  static int get pendingCleanupCount => _timers.length;

  /// Bu platformda «Kaydet» iletişim kutusu mu kullanılır (web / masaüstü), yoksa paylaşım sayfası mı (mobil)?
  static bool get platformUsesSaveDialog {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static Future<Uri?> _defaultSave({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) => FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);

  /// Önceki paylaşımlardan kalan `toplu_dosya_*` geçici klasörlerini siler (Android sistem süreci zamanlayıcı
  /// çalışmadan öldürürse dosya diskte kalır). Hesap silinince ([includeLive] true) bu süreçte bilinenler de
  /// silinir. Hata fırlatmaz.
  static Future<void> sweepAll({
    Duration staleAfter = Duration.zero,
    Directory? root,
    bool includeLive = false,
  }) async {
    if (kIsWeb) return;
    if (includeLive) {
      final known = <String>{..._livePaths, ..._timers.keys};
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      for (final path in known) {
        await _delete(Directory(path));
      }
    }
    try {
      final limit = DateTime.now().subtract(staleAfter);
      await for (final entity in (root ?? Directory.systemTemp).list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
        if (!name.startsWith(_dirPrefix) || _livePaths.contains(entity.path)) continue;
        try {
          if (staleAfter == Duration.zero || (await entity.stat()).modified.isBefore(limit)) {
            await entity.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  final Future<ShareResult> Function(ShareParams params) _share;

  /// Geçici klasör silindikten sonra eklentinin ikinci kopyasını (share_plus önbelleği) siler.
  final Future<void> Function() _purge;
  final Future<Uri?> Function({required String fileName, required Uint8List bytes, required String mimeType}) _save;
  final Future<Directory> Function() _tempRoot;
  final Duration _cleanupDelay;
  final Duration _staleAfter;
  final bool _useSaveDialog;
  final bool _useTempFile;
  final bool _isWeb;

  static Duration _defaultCleanupDelay() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return Duration.zero;
    return const Duration(minutes: 2);
  }

  @override
  Future<ExportShareOutcome> deliver(
    RenderedFile file, {
    Rect? sharePositionOrigin,
    String subject = 'Dosya',
  }) async {
    if (_useSaveDialog) {
      final uri = await _save(fileName: file.fileName, bytes: file.bytes, mimeType: file.mimeType);
      // Web'de `saveFile` Blob indirmesi yapar ve HER ZAMAN null döner (kullanıcı vazgeçmiş olamaz): başarı say.
      if (uri == null && _isWeb) return ExportShareOutcome.shared;
      return uri == null ? ExportShareOutcome.dismissed : ExportShareOutcome.shared;
    }
    Directory? dir;
    XFile xfile;
    if (_useTempFile) {
      try {
        final root = await _tempRoot();
        await sweepAll(staleAfter: _staleAfter, root: root);
        dir = await root.createTemp(_dirPrefix);
        _livePaths.add(dir.path);
        final target = File('${dir.path}${Platform.pathSeparator}${file.fileName}');
        await target.writeAsBytes(file.bytes, flush: true);
        xfile = XFile(target.path, mimeType: file.mimeType, name: file.fileName);
      } catch (_) {
        await _delete(dir);
        dir = null;
        xfile = XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.fileName);
      }
    } else {
      xfile = XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.fileName);
    }
    try {
      final result = await _share(
        ShareParams(
          files: <XFile>[xfile],
          subject: subject,
          fileNameOverrides: <String>[file.fileName],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      switch (result.status) {
        case ShareResultStatus.success:
          return ExportShareOutcome.shared;
        case ShareResultStatus.dismissed:
          return ExportShareOutcome.dismissed;
        case ShareResultStatus.unavailable:
          return ExportShareOutcome.unknown;
      }
    } finally {
      await _scheduleDelete(dir);
    }
  }

  /// Gecikme sıfırsa silmeyi BEKLER; değilse zamanlar.
  Future<void> _scheduleDelete(Directory? dir) async {
    if (dir == null) return;
    if (_cleanupDelay == Duration.zero) {
      await _delete(dir);
      await _purgeQuietly();
    } else {
      final path = dir.path;
      _timers[path]?.cancel();
      _timers[path] = Timer(_cleanupDelay, () {
        _timers.remove(path);
        // Başka bir paylaşım hâlâ bekliyorsa eklenti önbelleğine dokunulmaz: alıcı uygulama onun kopyasını okuyor olabilir.
        unawaited(_delete(dir).then((_) async {
          if (_timers.isEmpty) await _purgeQuietly();
        }));
      });
    }
  }

  Future<void> _purgeQuietly() async {
    try {
      await _purge();
    } catch (_) {
      // En iyi çaba.
    }
  }

  static Future<void> _delete(Directory? dir) async {
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // En iyi çaba: uygulama önbelleği sistem tarafından da temizlenir.
    } finally {
      _livePaths.remove(dir.path);
    }
  }
}
