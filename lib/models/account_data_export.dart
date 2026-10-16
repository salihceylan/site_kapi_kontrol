// Kişisel veri dışa aktarma sonucu (docs/PLATFORM_SATISA_HAZIRLIK.md §1.5).
//
// `POST /me/data-export` yanıtı: `200`, `application/json; charset=utf-8`, `Content-Disposition: attachment;
// filename="kisisel-veri-<user_code>-<YYYYMMDD>.json"`. Gövde olduğu gibi dosyaya yazılır (yeniden
// biçimlendirilmez); istemci içeriği çözümleyip yorumlamaz.
import 'dart:typed_data';

/// İndirilen kişisel veri dosyası (bellekte). Kullanıcı kapatınca / ekran kapanınca atılır.
class AccountDataExport {
  const AccountDataExport({required this.bytes, required this.fileName});

  /// UTF-8 JSON baytları.
  final Uint8List bytes;

  /// Güvenli dosya adı (`kisisel-veri-….json`).
  final String fileName;

  int get sizeBytes => bytes.length;

  /// "12 KB" / "1,4 MB" gibi okunur boyut.
  String get sizeLabel => formatByteSize(bytes.length);
}

/// "532 B", "12 KB", "1,4 MB" (ondalık ayırıcı Türkçe virgül).
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return kb < 10 ? '${_oneDecimal(kb)} KB' : '${kb.round()} KB';
  }
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${_oneDecimal(mb)} MB' : '${mb.round()} MB';
}

String _oneDecimal(double value) => value.toStringAsFixed(1).replaceFirst('.', ',');

/// `Content-Disposition` başlığından dosya adını okur ve GÜVENLİ hâle getirir: dizin ayırıcılar, kontrol
/// karakterleri ve beklenmedik karakterler atılır, `.json` uzantısı garanti edilir. Başlık yoksa/geçersizse
/// [fallback] (`kisisel-veri-<YYYYMMDD>.json`) kullanılır.
String exportFileNameFrom(String? contentDisposition, {required String fallback}) {
  final header = contentDisposition;
  if (header != null && header.isNotEmpty) {
    String? raw;
    final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false)
        .firstMatch(header);
    if (star != null) {
      try {
        raw = Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {
        raw = null;
      }
    }
    raw ??= RegExp(r'filename\s*=\s*"([^"]*)"', caseSensitive: false).firstMatch(header)?.group(1);
    raw ??= RegExp(r'filename\s*=\s*([^;\s]+)', caseSensitive: false).firstMatch(header)?.group(1);
    final cleaned = _sanitizeFileName(raw);
    if (cleaned != null) return cleaned;
  }
  return _sanitizeFileName(fallback) ?? 'kisisel-veri.json';
}

String? _sanitizeFileName(String? raw) {
  if (raw == null) return null;
  // Yol bileşenlerini at (`../x`, `a\b`), yalnız güvenli karakterleri tut.
  var name = raw.split(RegExp(r'[\\/]')).last.trim();
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  name = name.replaceAll(RegExp(r'-{2,}'), '-');
  name = name.replaceAll(RegExp(r'^[.\-]+'), '');
  if (name.isEmpty) return null;
  if (name.length > 80) name = name.substring(name.length - 80);
  if (!name.toLowerCase().endsWith('.json')) name = '$name.json';
  return name;
}

/// Yedek dosya adı için tarih: `kisisel-veri-YYYYMMDD.json`.
String fallbackExportFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'kisisel-veri-${now.year.toString().padLeft(4, '0')}${two(now.month)}${two(now.day)}.json';
}
