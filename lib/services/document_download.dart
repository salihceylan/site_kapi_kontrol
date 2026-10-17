// Belge indirme hedefleri (docs/PLATFORM_BELGELER.md A8) ve dosya adı yardımcıları.
//
// İndirme gövdesi BELLEĞE toplanmaz: parçalar doğrudan geçici dosyaya yazılır ([TempFileDocumentSink]); bellek
// sabit kalır. Web'de dosya sistemi yoktur: gövde bellekte tutulur ([MemoryDocumentSink]; en çok birkaç on MB).
//
// Geçici klasör adı `kisisel_veri_belge_` ile başlar. Bu önek bilerek `AccountExportSharer`ın süpürdüğü
// `kisisel_veri_` önekinin altındadır: hesap silinince `LocalDataWiper` (yerel temizlik) belge kopyalarını da
// siler (test: test/document_download_test.dart bu bağı korur). Belge kişisel veri taşıyabilir.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// İndirilmiş belge: geçici dosya (mobil / masaüstü) ya da bellek (web).
@immutable
class DownloadedDocument {
  const DownloadedDocument({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.path,
    this.bytes,
    this.directoryPath,
  });

  /// Paylaşım ve kaydetmede görünen güvenli dosya adı.
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// Geçici dosyanın yolu; web'de null.
  final String? path;

  /// Bellekteki baytlar (web); dosya varsa null.
  final Uint8List? bytes;

  /// Silinecek geçici klasör; yoksa null.
  final String? directoryPath;
}

/// İndirme hedefi: parçalar sırayla eklenir; [finish] başarıyı, [abort] kısmi veriyi atmayı bildirir.
abstract class DocumentSink {
  Future<void> add(List<int> chunk);

  /// Tüm veri yazıldı: [DownloadedDocument] döner.
  Future<DownloadedDocument> finish();

  /// Yarıda kesildi (hata, iptal, boyut aşımı): kısmi veri silinir. Hata fırlatmaz.
  Future<void> abort();
}

/// Yanıt başlıkları okunduktan SONRA hedef açar (dosya adı başlıktan gelir).
typedef DocumentSinkFactory =
    Future<DocumentSink> Function({
      required String fileName,
      required String mimeType,
      int? expectedLength,
    });

/// Platforma göre varsayılan hedef: web'de bellek, diğerlerinde geçici dosya.
Future<DocumentSink> defaultDocumentSink({
  required String fileName,
  required String mimeType,
  int? expectedLength,
}) {
  if (kIsWeb) {
    return Future<DocumentSink>.value(
      MemoryDocumentSink(fileName: fileName, mimeType: mimeType),
    );
  }
  return TempFileDocumentSink.open(fileName: fileName, mimeType: mimeType);
}

/// Bellek hedefi (web ve testler).
class MemoryDocumentSink implements DocumentSink {
  MemoryDocumentSink({required this.fileName, required this.mimeType});

  final String fileName;
  final String mimeType;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  Future<void> add(List<int> chunk) async => _builder.add(chunk);

  @override
  Future<DownloadedDocument> finish() async {
    final data = _builder.takeBytes();
    return DownloadedDocument(
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: data.length,
      bytes: data,
    );
  }

  @override
  Future<void> abort() async => _builder.clear();
}

/// Geçici dosya hedefi: `<kök>/kisisel_veri_belge_XXXX/<ad>`; yazma bellek şişirmez (düzenli `flush`).
class TempFileDocumentSink implements DocumentSink {
  TempFileDocumentSink._(
    this._dir,
    this._file,
    this._sink,
    this.fileName,
    this.mimeType,
  );

  /// Geçici klasör adı öneki (bkz. dosya başlığındaki not).
  static const String dirPrefix = 'kisisel_veri_belge_';

  /// Bu süreçte kullanılan geçici klasörler ([DocumentFileSharer.sweepAll] bunlara dokunmaz).
  static final Set<String> livePaths = <String>{};

  /// `flush` aralığı: bu kadar bayt birikince diske itilir.
  static const int _flushEvery = 256 * 1024;

  final Directory _dir;
  final File _file;
  final IOSink _sink;
  final String fileName;
  final String mimeType;
  int _written = 0;
  int _pending = 0;
  bool _closed = false;

  static Future<TempFileDocumentSink> open({
    required String fileName,
    required String mimeType,
    Directory? root,
  }) async {
    final base = root ?? Directory.systemTemp;
    final dir = await base.createTemp(dirPrefix);
    livePaths.add(dir.path);
    try {
      // Çağıran adı zaten temizlemiş olmalı; yine de yola dizin ayırıcı / üst dizin girmesin (savunma).
      final safeName = safeDocumentFileName(fileName);
      final file = File('${dir.path}${Platform.pathSeparator}$safeName');
      return TempFileDocumentSink._(
        dir,
        file,
        file.openWrite(),
        safeName,
        mimeType,
      );
    } catch (_) {
      livePaths.remove(dir.path);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> add(List<int> chunk) async {
    if (_closed) return;
    _sink.add(chunk);
    _written += chunk.length;
    _pending += chunk.length;
    if (_pending >= _flushEvery) {
      _pending = 0;
      await _sink.flush();
    }
  }

  @override
  Future<DownloadedDocument> finish() async {
    _closed = true;
    await _sink.flush();
    await _sink.close();
    return DownloadedDocument(
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: _written,
      path: _file.path,
      directoryPath: _dir.path,
    );
  }

  @override
  Future<void> abort() async {
    _closed = true;
    try {
      await _sink.close();
    } catch (_) {}
    await deleteDirectory(_dir.path);
  }

  /// Geçici klasörü siler (en iyi çaba) ve canlı listeden çıkarır.
  static Future<void> deleteDirectory(String? path) async {
    if (path == null) return;
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Uygulama önbelleği sistem tarafından da temizlenir.
    } finally {
      livePaths.remove(path);
    }
  }
}

// --- Dosya adı --------------------------------------------------------------------------------

/// Dosya adını paylaşım / disk için GÜVENLİ hâle getirir: dizin ayırıcıları ve kontrol karakterleri atılır,
/// yasak karakterler `_` olur, uzunluk sınırlanır (uzantı korunur). Boş sonuçta [fallback].
String safeDocumentFileName(String? raw, {String fallback = 'belge'}) {
  var name = (raw ?? '').trim();
  // Yalnız SON parça: `../../x` -> `x`.
  final slash = name.lastIndexOf(RegExp(r'[\\/]'));
  if (slash >= 0) name = name.substring(slash + 1);
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    final isControl =
        rune < 0x20 || rune == 0x7F || (rune >= 0x80 && rune < 0xA0);
    final isBidi =
        (rune >= 0x202A && rune <= 0x202E) ||
        (rune >= 0x2066 && rune <= 0x2069) ||
        rune == 0x200E ||
        rune == 0x200F ||
        rune == 0x061C ||
        (rune >= 0x200B && rune <= 0x200D) ||
        rune == 0xFEFF;
    if (isControl || isBidi) continue;
    final ch = String.fromCharCode(rune);
    buffer.write('<>:"|?*'.contains(ch) ? '_' : ch);
  }
  name = buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  while (name.endsWith('.') || name.endsWith(' ')) {
    name = name.substring(0, name.length - 1);
  }
  if (name.isEmpty || name == '.' || name == '..') return fallback;
  const maxRunes = 100;
  if (name.runes.length > maxRunes) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 6 ? name.substring(dot) : '';
    final base = name.substring(0, ext.isEmpty ? name.length : dot);
    final keep = maxRunes - ext.runes.length;
    name = '${String.fromCharCodes(base.runes.take(keep > 1 ? keep : 1))}$ext';
  }
  return name;
}

/// `Content-Disposition` başlığından dosya adı (RFC 6266 / 5987: `filename*` önceliklidir); yoksa null.
String? fileNameFromContentDisposition(String? header) {
  if (header == null || header.isEmpty) return null;
  final star = RegExp(
    r"filename\*\s*=\s*([^';]*)'[^';]*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (star != null) {
    final charset = (star.group(1) ?? '').trim().toLowerCase();
    final encoded = star.group(2)!.trim();
    try {
      final bytes = <int>[];
      for (var i = 0; i < encoded.length; i++) {
        final c = encoded[i];
        if (c == '%' && i + 2 < encoded.length) {
          final hex = encoded.substring(i + 1, i + 3);
          final value = int.tryParse(hex, radix: 16);
          if (value != null) {
            bytes.add(value);
            i += 2;
            continue;
          }
        }
        bytes.addAll(utf8.encode(c));
      }
      final decoded = charset == 'iso-8859-1' || charset == 'latin1'
          ? latin1.decode(bytes)
          : utf8.decode(bytes, allowMalformed: true);
      if (decoded.trim().isNotEmpty) return decoded.trim();
    } catch (_) {
      // Bozuk kodlama: düz `filename` denenir.
    }
  }
  final plain = RegExp(
    r'filename\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]+))',
    caseSensitive: false,
  ).firstMatch(header);
  if (plain != null) {
    final value = (plain.group(1) ?? plain.group(2) ?? '').replaceAllMapped(
      RegExp(r'\\(.)'),
      (m) => m.group(1)!,
    );
    if (value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
