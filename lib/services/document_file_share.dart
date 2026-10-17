// İndirilmiş belgeyi paylaşım / "ile aç" menüsüne verir (share_plus) ve geçici kopyayı siler.
//
// Belge zaten geçici klasöre akışla yazılmıştır ([TempFileDocumentSink]); burada yalnız paylaşım ve temizlik
// yapılır. Silme zamanı AccountExportSharer ile aynı gerekçeyle ertelenir: Android'de alıcı uygulama dosyayı hâlâ
// okurken silmek yüklemeyi / eki bozar; iOS'ta paylaşım yaprağı kapanınca alıcı kopyayı almıştır.
// Süreç öldürülürse zamanlayıcı çalışmaz: bir sonraki paylaşımda ve hesap silinince (önek, bkz.
// document_download.dart) eski klasörler süpürülür.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';

/// Paylaşım sonucu (arayüz için sadeleştirilmiş).
enum DocumentShareOutcome {
  /// Kullanıcı bir paylaşım / kaydetme / aç eylemi seçti.
  shared,

  /// Kullanıcı paylaşım menüsünü kapattı.
  dismissed,

  /// Platform sonucu bildirmiyor (Android'in çoğu sürümü): menü açıldı, sonuç bilinmiyor.
  unknown,
}

class DocumentFileSharer {
  DocumentFileSharer({
    Future<ShareResult> Function(ShareParams params)? shareFn,
    Duration? cleanupDelay,
    Duration staleAfter = const Duration(minutes: 10),
    bool sweepStaleOnShare = true,
    Future<void> Function()? purgeSharedCaches,
  }) : _share = shareFn ?? SharePlus.instance.share,
       _cleanupDelay = cleanupDelay ?? _defaultCleanupDelay(),
       _staleAfter = staleAfter,
       _sweepStaleOnShare = sweepStaleOnShare,
       _purgeSharedCaches =
           purgeSharedCaches ?? (() => purgeLocalSharedCaches(pickerCache: false));

  /// Zamanlanmış (gecikmeli) silmeler: klasör yolu -> zamanlayıcı.
  static final Map<String, Timer> _timers = <String, Timer>{};

  /// Testler için: bekleyen gecikmeli silme sayısı.
  @visibleForTesting
  static int get pendingCleanupCount => _timers.length;

  final Future<ShareResult> Function(ShareParams params) _share;
  final Duration _cleanupDelay;
  final Duration _staleAfter;

  /// Her paylaşımda önceki oturumlardan kalan eski klasörler süpürülür (testlerde gerçek dosya sistemine
  /// çıkmamak için kapatılabilir).
  final bool _sweepStaleOnShare;

  /// Gecikmeli silme süresi dolunca eklenti (share_plus) önbelleğini de siler: share_plus Android'de dosya yolunu
  /// `<önbellek>/share_plus` altına İKİNCİ kez kopyalar ve bu klasörü yalnız sonraki paylaşımın başında temizler;
  /// belge (sözleşme: T.C. / IBAN olabilir) orada kalmasın. Picker önbelleğine DOKUNMAZ (yükleme sürüyor olabilir).
  final Future<void> Function() _purgeSharedCaches;

  static Duration _defaultCleanupDelay() {
    // iOS: paylaşım yaprağı alıcı kopyayı aldıktan sonra kapanır; hemen silinebilir.
    if (defaultTargetPlatform == TargetPlatform.iOS) return Duration.zero;
    return const Duration(minutes: 2);
  }

  /// Önceki oturumlardan kalan `kisisel_veri_belge_*` klasörlerini siler (en iyi çaba, hata fırlatmaz).
  /// [includeLive] true: bu süreçte kullanılanlar ve bekleyen zamanlayıcılar da (hesap silme).
  static Future<void> sweepAll({
    Duration staleAfter = Duration.zero,
    Directory? root,
    bool includeLive = false,
  }) async {
    if (kIsWeb) return;
    if (includeLive) {
      final known = <String>{
        ...TempFileDocumentSink.livePaths,
        ..._timers.keys,
      };
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      for (final path in known) {
        await TempFileDocumentSink.deleteDirectory(path);
      }
    }
    try {
      final limit = DateTime.now().subtract(staleAfter);
      await for (final entity in (root ?? Directory.systemTemp).list(
        followLinks: false,
      )) {
        if (entity is! Directory) continue;
        final name =
            entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
        if (!name.startsWith(TempFileDocumentSink.dirPrefix) ||
            TempFileDocumentSink.livePaths.contains(entity.path)) {
          continue;
        }
        try {
          if (staleAfter == Duration.zero ||
              (await entity.stat()).modified.isBefore(limit)) {
            await entity.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// [document]'i paylaşım menüsüyle sunar. iPad / masaüstünde açılır pencerenin bağlanacağı yer
  /// [sharePositionOrigin]'dir (düğmenin ekran dikdörtgeni). Paylaşım bitince (ya da hata verince) geçici
  /// klasör silinmek üzere zamanlanır.
  Future<DocumentShareOutcome> share(
    DownloadedDocument document, {
    Rect? sharePositionOrigin,
  }) async {
    try {
      await _sweepStale();
      final path = document.path;
      final file = path != null
          ? XFile(path, mimeType: document.mimeType, name: document.fileName)
          : XFile.fromData(
              document.bytes!,
              mimeType: document.mimeType,
              name: document.fileName,
            );
      final result = await _share(
        ShareParams(
          files: <XFile>[file],
          fileNameOverrides: <String>[document.fileName],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      switch (result.status) {
        case ShareResultStatus.success:
          return DocumentShareOutcome.shared;
        case ShareResultStatus.dismissed:
          return DocumentShareOutcome.dismissed;
        case ShareResultStatus.unavailable:
          return DocumentShareOutcome.unknown;
      }
    } finally {
      await scheduleDelete(document);
    }
  }

  /// Belgenin geçici klasörünü siler (gecikme sıfırsa BEKLER; değilse zamanlar). Paylaşmadan vazgeçilen
  /// (iptal / hata) indirmeler için de çağrılır.
  Future<void> scheduleDelete(DownloadedDocument document) async {
    final dir = document.directoryPath;
    if (dir == null) return;
    if (_cleanupDelay == Duration.zero) {
      await TempFileDocumentSink.deleteDirectory(dir);
    } else {
      _timers[dir]?.cancel();
      _timers[dir] = Timer(_cleanupDelay, () {
        _timers.remove(dir);
        unawaited(_expire(dir));
      });
    }
  }

  /// Süresi dolan geçici klasörü siler; BAŞKA bekleyen silme (yani süren başka bir paylaşım) yoksa share_plus
  /// önbelleğini de temizler (ikinci bir paylaşımın kopyasını alıcı okurken silmemek için). Hata fırlatmaz.
  Future<void> _expire(String dir) async {
    await TempFileDocumentSink.deleteDirectory(dir);
    if (_timers.isNotEmpty) return;
    try {
      await _purgeSharedCaches();
    } catch (_) {
      // En iyi çaba.
    }
  }

  Future<void> _sweepStale() async {
    if (_sweepStaleOnShare) await sweepAll(staleAfter: _staleAfter);
  }
}
