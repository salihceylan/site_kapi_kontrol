// Testler için küçük PDF metin çıkarıcı (yalnız `pdf` paketinin ürettiği, akışları SIKIŞTIRILMAMIŞ belgeler).
//
// Neden: PDF görsel olarak bu ortamda çizilemez; makbuz / rapor metninin ve Türkçe harflerin gerçekten belgeye
// yazıldığı yazı tipi eşlemesinden (ToUnicode) okunarak doğrulanır. `PdfFinanceService.debugCompress = false`
// ile üretilmelidir. Alt küme glif kimlikleri belgeden belgeye değişir; bu yüzden her yazı tipinin kendi
// ToUnicode çizelgesi kullanılır.
import 'dart:convert';
import 'dart:typed_data';

/// Sayfalardaki metin parçalarını (kelime başına bir `BT..ET` bloğu) belge sırasıyla döndürür.
List<String> extractPdfTextRuns(Uint8List bytes) {
  final text = latin1.decode(bytes);
  // Yazı tipi adı (F6) -> ToUnicode nesne numarası.
  final fontToUnicode = <String, int>{};
  for (final m in RegExp(r'/Subtype/Type0/Name/(F\d+)/.*?/ToUnicode (\d+) 0 R').allMatches(text)) {
    fontToUnicode[m.group(1)!] = int.parse(m.group(2)!);
  }
  final maps = <String, Map<int, int>>{};
  fontToUnicode.forEach((font, objectNo) {
    final start = text.indexOf(RegExp('(^|\n)$objectNo 0 obj'));
    if (start < 0) return;
    final end = text.indexOf('endobj', start);
    final body = text.substring(start, end < 0 ? text.length : end);
    final map = <int, int>{};
    for (final block in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(body)) {
      for (final pair in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(block.group(1)!)) {
        map[int.parse(pair.group(1)!, radix: 16)] = int.parse(pair.group(2)!, radix: 16);
      }
    }
    for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(body)) {
      for (final t in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(block.group(1)!)) {
        final a = int.parse(t.group(1)!, radix: 16);
        final b = int.parse(t.group(2)!, radix: 16);
        final u = int.parse(t.group(3)!, radix: 16);
        for (var i = a; i <= b; i++) {
          map[i] = u + i - a;
        }
      }
    }
    maps[font] = map;
  });
  final runs = <String>[];
  for (final m in RegExp(r'BT /(F\d+) [\d.]+ Tf.*?\[(.*?)\]TJ ET', dotAll: true).allMatches(text)) {
    final map = maps[m.group(1)!];
    if (map == null) continue;
    final buffer = StringBuffer();
    for (final hex in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(m.group(2)!)) {
      final digits = hex.group(1)!;
      for (var i = 0; i + 4 <= digits.length; i += 4) {
        final unit = map[int.parse(digits.substring(i, i + 4), radix: 16)];
        buffer.writeCharCode(unit ?? 0xFFFD);
      }
    }
    runs.add(buffer.toString());
  }
  return runs;
}

/// Parçaları boşlukla birleştirir ("Makbuz No: MK-2026-000123" gibi aramalar için).
String extractPdfText(Uint8List bytes) => extractPdfTextRuns(bytes).join(' ');

/// ToUnicode çizelgesinde geçen bütün karakterler.
Set<int> pdfMappedCodePoints(Uint8List bytes) {
  final text = extractPdfText(bytes);
  return text.runes.toSet();
}
