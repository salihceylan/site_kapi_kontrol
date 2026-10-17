// CSV okuyucu ve yazıcı (Platform Faz 2b). Kendi RFC 4180 uygulamamız: `csv` paketi bilinçli olarak EKLENMEDİ
// (docs/PLATFORM_TOPLU_ISLEMLER.md Karar 2).
//
// Okuyucu: ayırıcı ilk 20 kayıtta `;` `,` TAB `|` içinden tutarlı sütun sayısı vereni seçer (eşitlikte `;`);
// `sep=;` ilk satırı ayırıcıyı belirler ve atlanır; tırnak içinde satır sonu ve `""`; CR / LF / CRLF; boş kayıtlar
// atlanır ama satır numarası korunur; kapanmamış tırnak DÜRÜST hata verir (kalan satırlar sessizce tek hücreye
// yutulmaz).
import 'dart:convert';
import 'dart:typed_data';

import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';

const List<String> _delimiterCandidates = <String>[';', ',', '\t', '|'];

class _Scan {
  _Scan(this.rows, this.truncated, this.counts);

  final List<SheetRow> rows;
  final bool truncated;

  /// Her dolu kaydın sütun sayısı (ayırıcı sezgisi için).
  final List<int> counts;
}

/// Tek geçişli CSV tarayıcı. [strict] true iken kapanmamış tırnak ve fazla sütun hata verir; sezgi taramasında
/// false'tur (eldeki kayıtlar döner).
_Scan _scan(
  String text,
  int start,
  String delimiter, {
  required int maxRecords,
  required int maxColumns,
  required bool strict,
  int? maxChars,
}) {
  final delim = delimiter.codeUnitAt(0);
  final end = maxChars == null || start + maxChars > text.length ? text.length : start + maxChars;
  final rows = <SheetRow>[];
  final counts = <int>[];
  var truncated = false;

  var fields = <String?>[];
  final buffer = StringBuffer();
  var quoted = false;
  var inQuotes = false;
  var recordHasContent = false;
  var recordNo = 0;

  void endField() {
    final raw = buffer.toString();
    buffer.clear();
    quoted = false;
    final value = raw.trim();
    fields.add(value.isEmpty ? null : value);
  }

  // Dolu kaydı ekler; sınır aşılırsa true döner (okuma durur).
  bool endRecord() {
    endField();
    recordNo++;
    recordHasContent = false;
    var last = fields.length;
    while (last > 0 && fields[last - 1] == null) {
      last--;
    }
    final current = fields;
    fields = <String?>[];
    if (last == 0) return false; // boş kayıt: atlanır, numara sayılır
    if (last > maxColumns) {
      if (strict) {
        throw const SpreadsheetException(
          'Tabloda 40\'tan fazla sütun var. Gereksiz sütunları silip yeniden yükleyin.',
          code: 'FILE_LIMIT',
        );
      }
    }
    final cells = List<Object?>.generate(
      last,
      (i) => current[i] == null ? null : _cap(current[i]!),
      growable: false,
    );
    counts.add(last);
    rows.add(SheetRow(recordNo, cells));
    if (rows.length > maxRecords) {
      truncated = true;
      return true;
    }
    return false;
  }

  var i = start;
  while (i < end) {
    final c = text.codeUnitAt(i);
    if (inQuotes) {
      if (c == 0x22) {
        if (i + 1 < end && text.codeUnitAt(i + 1) == 0x22) {
          buffer.writeCharCode(0x22);
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      buffer.writeCharCode(c);
      i++;
      continue;
    }
    if (c == 0x22 && buffer.isEmpty && !quoted) {
      inQuotes = true;
      quoted = true;
      recordHasContent = true;
      i++;
      continue;
    }
    if (c == delim) {
      endField();
      recordHasContent = true;
      i++;
      continue;
    }
    if (c == 0x0D || c == 0x0A) {
      if (c == 0x0D && i + 1 < end && text.codeUnitAt(i + 1) == 0x0A) i++;
      i++;
      if (endRecord()) return _Scan(rows.sublist(0, maxRecords), true, counts);
      continue;
    }
    buffer.writeCharCode(c);
    recordHasContent = true;
    i++;
  }
  if (inQuotes) {
    if (strict) {
      throw SpreadsheetException(
        'CSV dosyasında kapanmamış tırnak işareti var (satır ${recordNo + 1}). Dosyayı açıp tırnakları kontrol edin.',
      );
    }
    // Sezgi taraması: eldeki kayıt yok sayılır.
    return _Scan(rows, truncated, counts);
  }
  if (recordHasContent || buffer.isNotEmpty || fields.isNotEmpty) {
    if (endRecord()) return _Scan(rows.sublist(0, maxRecords), true, counts);
  }
  return _Scan(rows, truncated, counts);
}

String _cap(String value) =>
    value.length > SheetLimits.cellTextCap ? value.substring(0, SheetLimits.cellTextCap) : value;

/// `sep=X` ilk satırı: (ayırıcı, atlanacak karakter sayısı) ya da null.
(String, int)? _sepDirective(String text) {
  if (text.length < 5) return null;
  if (text.substring(0, 4).toLowerCase() != 'sep=') return null;
  final char = text[4];
  if (!_delimiterCandidates.contains(char)) return null;
  var i = 5;
  while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
    i++;
  }
  if (i < text.length) {
    if (text[i] == '\r') {
      i++;
      if (i < text.length && text[i] == '\n') i++;
    } else if (text[i] == '\n') {
      i++;
    } else {
      return null; // "sep=;abc" gibi: yönerge değil
    }
  }
  return (char, i);
}

/// Ayırıcıyı ilk 20 kayıttan seçer.
String sniffCsvDelimiter(String text, {int start = 0}) {
  String best = ';';
  var bestConsistent = 0;
  var bestColumns = 0;
  for (final candidate in _delimiterCandidates) {
    final scan = _scan(
      text,
      start,
      candidate,
      maxRecords: 20,
      maxColumns: 1 << 20,
      strict: false,
      maxChars: 64 * 1024,
    );
    final counts = scan.counts.take(20).toList();
    if (counts.isEmpty) continue;
    final histogram = <int, int>{};
    for (final c in counts) {
      histogram[c] = (histogram[c] ?? 0) + 1;
    }
    var modeColumns = 0;
    var modeCount = 0;
    histogram.forEach((columns, count) {
      if (count > modeCount || (count == modeCount && columns > modeColumns)) {
        modeColumns = columns;
        modeCount = count;
      }
    });
    if (modeColumns < 2) continue;
    if (modeCount > bestConsistent || (modeCount == bestConsistent && modeColumns > bestColumns)) {
      best = candidate;
      bestConsistent = modeCount;
      bestColumns = modeColumns;
    }
  }
  return best;
}

/// CSV metnini okur. Kapanmamış tırnak ve sütun sınırı aşımı [SpreadsheetException] fırlatır; satır sınırı
/// aşımı [SheetTable.truncated] ile bildirilir (çağıran kullanıcıya açık ileti verir).
SheetTable parseCsvText(
  String text, {
  String? encodingNote,
  int maxRecords = SheetLimits.maxRecords,
  int maxColumns = SheetLimits.maxColumns,
}) {
  var start = 0;
  String? delimiter;
  final directive = _sepDirective(text);
  if (directive != null) {
    delimiter = directive.$1;
    start = directive.$2;
  }
  delimiter ??= sniffCsvDelimiter(text, start: start);
  final scan = _scan(
    text,
    start,
    delimiter,
    maxRecords: maxRecords,
    maxColumns: maxColumns,
    strict: true,
  );
  return SheetTable(
    rows: List<SheetRow>.unmodifiable(scan.rows),
    truncated: scan.truncated,
    encodingNote: encodingNote,
    delimiter: delimiter,
  );
}

// --- Yazıcı ------------------------------------------------------------------------------------

/// Hücreyi CSV alanına çevirir: `;`, `"`, CR/LF içeren ya da baş/son boşluklu hücre `"…"` içine alınır
/// (`"` -> `""`). Formül kaçışı BURADA yapılmaz ([escapeCsvFormula] önce uygulanır).
String csvEncodeCell(String value, {String delimiter = ';'}) {
  if (value.isEmpty) return '';
  final needsQuote =
      value.contains(delimiter) ||
      value.contains('"') ||
      value.contains('\r') ||
      value.contains('\n') ||
      value.startsWith(' ') ||
      value.endsWith(' ') ||
      value.startsWith('\t') ||
      value.endsWith('\t');
  if (!needsQuote) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Satırlardan CSV baytları: UTF-8 + BOM, ayırıcı `;`, satır sonu CRLF. [rows] hücreleri HAZIR metindir.
Uint8List csvBytes(List<List<String>> rows, {String delimiter = ';'}) {
  final out = StringBuffer();
  for (final row in rows) {
    out.write(row.map((cell) => csvEncodeCell(cell, delimiter: delimiter)).join(delimiter));
    out.write('\r\n');
  }
  final body = utf8.encode(out.toString());
  final bytes = Uint8List(body.length + 3);
  bytes[0] = 0xEF;
  bytes[1] = 0xBB;
  bytes[2] = 0xBF;
  bytes.setRange(3, bytes.length, body);
  return bytes;
}
