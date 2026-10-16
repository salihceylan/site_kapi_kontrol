// Kişisel veri dosyasını paylaşım menüsüne verir (share_plus) ve geçici kopyayı siler.
//
// Neden kendi geçici dosyamız: share_plus bellekteki dosyayı (XFile.fromData) UUID'li bir alt klasöre yazar ve
// SİLMEZ (sistemin temizlemesine bırakır). Dosya kişisel veri içerir; bu yüzden önce kendi geçici klasörümüze
// yazılır, paylaşım bitince klasör silinir. Geçici klasör açılamazsa (web, izinsiz dizin) bellekten paylaşılır.
//
// Silme zamanı: paylaşım penceresi kapanır kapanmaz silmek, Android'de alıcı uygulama dosyayı hâlâ okurken
// (arka planda yükleme / ek) dosyayı kaybettirebilir. Bu yüzden silme [cleanupDelay] kadar ertelenir ve her yeni
// paylaşımda süresi dolmuş eski klasörler de süpürülür.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';

/// Paylaşım sonucu (arayüz için sadeleştirilmiş).
enum ExportShareOutcome {
  /// Kullanıcı bir paylaşım / kaydetme eylemi seçti.
  shared,

  /// Kullanıcı paylaşım menüsünü kapattı.
  dismissed,

  /// Platform sonucu bildirmiyor (Android'in çoğu sürümü, masaüstü): menü açıldı, sonuç bilinmiyor.
  unknown,
}

class AccountExportSharer {
  AccountExportSharer({
    Future<ShareResult> Function(ShareParams params)? shareFn,
    Future<Directory> Function()? tempRoot,
    Duration? cleanupDelay,
    Duration staleAfter = const Duration(minutes: 10),
    bool? useTempFile,
  }) : _share = shareFn ?? SharePlus.instance.share,
       _tempRoot = tempRoot ?? (() async => Directory.systemTemp),
       _cleanupDelay = cleanupDelay ?? _defaultCleanupDelay(),
       _staleAfter = staleAfter,
       _useTempFile = useTempFile ?? !kIsWeb;

  static const String _dirPrefix = 'kisisel_veri_';

  /// Bu süreçte kullanılan / silinmesi zamanlanmış geçici klasörler: [sweepAll] bunlara dokunmaz (alıcı uygulama
  /// dosyayı hâlâ okuyor olabilir; kendi zamanlayıcıları siler).
  static final Set<String> _livePaths = <String>{};

  /// Zamanlanmış (gecikmeli) silmeler: klasör yolu -> zamanlayıcı. [sweepAll] `includeLive` ile bunları iptal eder.
  static final Map<String, Timer> _timers = <String, Timer>{};

  /// Testler için: bekleyen gecikmeli silme sayısı.
  @visibleForTesting
  static int get pendingCleanupCount => _timers.length;

  /// Önceki paylaşımlardan kalan `kisisel_veri_*` geçici klasörlerini siler. Android sistem süreci 2 dakika dolmadan
  /// öldürürse silme zamanlayıcısı hiç çalışmaz ve kişisel veri dosyası diskte kalır; bu yardımcı hesap silinince
  /// ([LocalDataWiper.wipe], [staleAfter] sıfır, [includeLive] true) ve "Gizlilik ve Veri" bölümü açılınca çağrılır.
  ///
  /// [includeLive] false (varsayılan): bu süreçte hâlâ kullanılan / silinmesi zamanlanmış klasörler atlanır (alıcı
  /// uygulama dosyayı okuyor olabilir; kendi zamanlayıcıları siler). [includeLive] true: onlar da silinir ve bekleyen
  /// silme zamanlayıcıları İPTAL edilir; yalnız hesap silindiğinde kullanılır (alıcıyı beklemenin anlamı yok, dosya
  /// kişisel veri taşır ve hesap artık olmadığından "Gizlilik ve Veri" süpürmesi bir daha çalışmaz). Hata fırlatmaz.
  static Future<void> sweepAll({
    Duration staleAfter = Duration.zero,
    Directory? root,
    bool includeLive = false,
  }) async {
    if (kIsWeb) return;
    if (includeLive) {
      // Kök dizinden bağımsız: bu süreçte bildiğimiz her klasör (zamanlayıcılı ya da paylaşımı süren) silinir.
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
  final Future<Directory> Function() _tempRoot;
  final Duration _cleanupDelay;

  /// Süpürmede silinecek klasör yaşı.
  final Duration _staleAfter;
  final bool _useTempFile;

  static Duration _defaultCleanupDelay() {
    // iOS: paylaşım yaprağı alıcı kopyayı aldıktan sonra kapanır; hemen silinebilir.
    if (defaultTargetPlatform == TargetPlatform.iOS) return Duration.zero;
    return const Duration(minutes: 2);
  }

  /// [export] dosyasını paylaşım menüsüyle sunar. iPad / masaüstünde açılır pencerenin bağlanacağı yer
  /// [sharePositionOrigin]'dir (düğmenin ekran dikdörtgeni).
  Future<ExportShareOutcome> share(
    AccountDataExport export, {
    Rect? sharePositionOrigin,
    String subject = 'Kişisel veri dosyam',
  }) async {
    Directory? dir;
    XFile file;
    if (_useTempFile) {
      try {
        final root = await _tempRoot();
        await _sweep(root);
        dir = await root.createTemp(_dirPrefix);
        _livePaths.add(dir.path);
        final target = File('${dir.path}${Platform.pathSeparator}${export.fileName}');
        await target.writeAsBytes(export.bytes, flush: true);
        file = XFile(target.path, mimeType: 'application/json', name: export.fileName);
      } catch (_) {
        await _delete(dir);
        dir = null;
        file = _memoryFile(export);
      }
    } else {
      file = _memoryFile(export);
    }

    try {
      final result = await _share(
        ShareParams(
          files: <XFile>[file],
          subject: subject,
          fileNameOverrides: <String>[export.fileName],
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

  XFile _memoryFile(AccountDataExport export) => XFile.fromData(
    export.bytes,
    mimeType: 'application/json',
    name: export.fileName,
  );

  /// Gecikme sıfırsa silmeyi BEKLER (belirleyici: çağıran döndüğünde klasör gitmiştir); değilse zamanlar.
  Future<void> _scheduleDelete(Directory? dir) async {
    if (dir == null) return;
    if (_cleanupDelay == Duration.zero) {
      await _delete(dir);
    } else {
      final path = dir.path;
      _timers[path]?.cancel();
      _timers[path] = Timer(_cleanupDelay, () {
        _timers.remove(path);
        unawaited(_delete(dir));
      });
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

  /// Önceki paylaşımlardan (uygulama kapanmış / zamanlayıcı çalışmamış) kalan süresi dolmuş klasörleri siler.
  Future<void> _sweep(Directory root) => sweepAll(staleAfter: _staleAfter, root: root);
}
