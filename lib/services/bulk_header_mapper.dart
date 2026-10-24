// Başlık satırını bulma, sütun eşleme ve satırları sunucu biçimine çevirme (Platform Faz 2b).
//
// Katlama kuralı sunucudaki `foldText` ile aynıdır (Ç→c, Ğ→g, İ/I/ı→i, Ö→o, Ş→s, Ü→u, küçük harf) ve ek olarak
// noktalama / boşluk sadeleştirir. Başlık satırı = ilk 10 dolu satırda ≥ 2 tanınan sütun içeren ilk satır.
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';

/// Başlık / ad karşılaştırma metni: Türkçe katlama + küçük harf + harf-rakam dışı her şey tek boşluk.
String foldHeader(String value) {
  final out = StringBuffer();
  var pendingSpace = false;
  void emit(String s) {
    if (pendingSpace && out.isNotEmpty) out.write(' ');
    pendingSpace = false;
    out.write(s);
  }

  for (final rune in value.runes) {
    final mapped = _foldRune(rune);
    if (mapped == null) {
      pendingSpace = true;
    } else {
      emit(mapped);
    }
  }
  return out.toString();
}

String? _foldRune(int r) {
  // ASCII harf / rakam.
  if (r >= 0x61 && r <= 0x7A) return String.fromCharCode(r);
  if (r >= 0x41 && r <= 0x5A) return String.fromCharCode(r + 32);
  if (r >= 0x30 && r <= 0x39) return String.fromCharCode(r);
  switch (r) {
    case 0xC7 || 0xE7: // Ç ç
      return 'c';
    case 0x11E || 0x11F: // Ğ ğ
      return 'g';
    case 0x130 || 0x131 || 0xCE || 0xEE: // İ ı Î î
      return 'i';
    case 0xD6 || 0xF6: // Ö ö
      return 'o';
    case 0x15E || 0x15F: // Ş ş
      return 's';
    case 0xDC || 0xFC || 0xDB || 0xFB: // Ü ü Û û
      return 'u';
    case 0xC2 || 0xE2: // Â â
      return 'a';
    case 0xB2: // ²
      return '2';
    case 0xB3: // ³
      return '3';
    case 0x33A1: // ㎡
      return 'm2';
  }
  return null;
}

/// Spec sütunlarının tanınan adları (katlanmış) -> sütun anahtarı.
Map<String, String> headerLookup(ImportKindSpec spec) {
  final map = <String, String>{};
  for (final column in spec.columns) {
    for (final name in <String>[column.key, column.label, ...column.aliases]) {
      final folded = foldHeader(name);
      if (folded.isEmpty) continue;
      map.putIfAbsent(folded, () => column.key);
      // Boşluksuz biçim de tanınır: «DaireNo», «Eposta», «AdSoyad».
      map.putIfAbsent(folded.replaceAll(' ', ''), () => column.key);
    }
  }
  return map;
}

/// Bir satırın başlık olarak taşıdığı: sütun indeksi -> eşleşen anahtar.
Map<int, String> _recognized(SheetRow row, Map<String, String> lookup) {
  final out = <int, String>{};
  for (var i = 0; i < row.cells.length; i++) {
    final cell = row.cells[i];
    if (cell is! String) continue;
    final folded = foldHeader(cell);
    final key = lookup[folded] ?? lookup[folded.replaceAll(' ', '')];
    if (key != null) out[i] = key;
  }
  return out;
}

/// Eşleme durumu (değiştirilemez). [assignment]: her spec anahtarı -> kaynak sütun indeksi (null = eşlenmedi).
class ColumnMapping {
  const ColumnMapping({
    required this.headerRowIndex,
    required this.headerN,
    required this.headers,
    required this.assignment,
    this.conflicts = const <String, List<int>>{},
  });

  /// [SheetTable.rows] içindeki indeks.
  final int headerRowIndex;

  /// Başlık satırının dosyadaki numarası.
  final int headerN;

  /// Başlık hücreleri (sütun sırasıyla; boş hücre ''). Yalnız başlıktır, veri değil.
  final List<String> headers;
  final Map<String, int?> assignment;

  /// Birden çok sütunun aynı alana düştüğü, kullanıcının çözmesi gereken alanlar -> aday sütunlar.
  final Map<String, List<int>> conflicts;

  /// [key] alanını [column]'a bağlar (null: bağı kaldırır). Aynı kaynak sütun tek alana bağlanır: başka alandaki
  /// bağ kaldırılır.
  ColumnMapping assign(String key, int? column) {
    final next = Map<String, int?>.from(assignment);
    if (column != null) {
      for (final entry in next.entries.toList()) {
        if (entry.value == column && entry.key != key) next[entry.key] = null;
      }
    }
    next[key] = column;
    final nextConflicts = Map<String, List<int>>.from(conflicts)..remove(key);
    return ColumnMapping(
      headerRowIndex: headerRowIndex,
      headerN: headerN,
      headers: headers,
      assignment: next,
      conflicts: nextConflicts,
    );
  }

  /// Hangi alana bağlı değilse o sütun "yok sayılır" (başlığı dolu olanlar).
  List<int> ignoredColumns() {
    final used = assignment.values.whereType<int>().toSet();
    return <int>[
      for (var i = 0; i < headers.length; i++)
        if (headers[i].isNotEmpty && !used.contains(i)) i,
    ];
  }

  List<ImportColumn> missingRequired(ImportKindSpec spec) => <ImportColumn>[
    for (final column in spec.requiredColumns)
      if (assignment[column.key] == null) column,
  ];

  bool canProceed(ImportKindSpec spec) => conflicts.isEmpty && missingRequired(spec).isEmpty;

  int get mappedCount => assignment.values.whereType<int>().length;
}

/// Başlık araması sonucu.
class HeaderSearch {
  const HeaderSearch({required this.mapping, required this.recognizedCount});

  final ColumnMapping mapping;
  final int recognizedCount;
}

/// İlk [SheetLimits.headerSearchRows] dolu satırda ≥ 2 tanınan sütunlu ilk satırı bulur; yoksa null.
HeaderSearch? detectHeader(SheetTable table, ImportKindSpec spec) {
  final lookup = headerLookup(spec);
  final limit = table.rows.length < SheetLimits.headerSearchRows
      ? table.rows.length
      : SheetLimits.headerSearchRows;
  for (var r = 0; r < limit; r++) {
    final row = table.rows[r];
    final found = _recognized(row, lookup);
    // Aynı alana düşen sütunlar tanınan SAYISINI şişirmesin: farklı anahtar sayısı.
    if (found.values.toSet().length < 2) continue;
    final candidates = <String, List<int>>{};
    found.forEach((column, key) => (candidates[key] ??= <int>[]).add(column));
    final assignment = <String, int?>{for (final c in spec.columns) c.key: null};
    final conflicts = <String, List<int>>{};
    candidates.forEach((key, columns) {
      if (columns.length == 1) {
        assignment[key] = columns.first;
      } else {
        conflicts[key] = List<int>.unmodifiable(columns);
      }
    });
    final headers = <String>[
      for (final cell in row.cells) cell == null ? '' : '$cell',
    ];
    return HeaderSearch(
      mapping: ColumnMapping(
        headerRowIndex: r,
        headerN: row.n,
        headers: List<String>.unmodifiable(headers),
        assignment: assignment,
        conflicts: conflicts,
      ),
      recognizedCount: candidates.length,
    );
  }
  return null;
}

/// Seçilen tür dışında başlıklara DAHA ÇOK uyan bir tür var mı (yanlış tür seçimi uyarısı)? Puan = tanınan sütun
/// sayısı + (zorunlu sütunların hepsi tanındıysa 10).
ImportKind? suggestBetterKind(SheetTable table, ImportSpec spec, ImportKind selected) {
  final current = _kindScore(table, spec.of(selected));
  ImportKind? best;
  var bestScore = current.score;
  for (final entry in spec.kinds.entries) {
    if (entry.key == selected) continue;
    final other = _kindScore(table, entry.value);
    if (other.recognized >= 2 && other.score >= bestScore + 2) {
      best = entry.key;
      bestScore = other.score;
    }
  }
  return best;
}

({int recognized, int score}) _kindScore(SheetTable table, ImportKindSpec? spec) {
  if (spec == null) return (recognized: 0, score: 0);
  final found = detectHeader(table, spec);
  if (found == null) return (recognized: 0, score: 0);
  final ok = found.mapping.missingRequired(spec).isEmpty;
  return (recognized: found.recognizedCount, score: found.recognizedCount + (ok ? 10 : 0));
}

// --- Satırları sunucu biçimine çevirme ---------------------------------------------------------

/// Excel seri tarihini `YYYY-AA-GG` yapar; geçersizse null.
String? excelSerialToIso(double serial, {bool date1904 = false}) {
  if (!serial.isFinite || serial < 0 || serial >= 2958466) return null;
  final days = serial.floor();
  DateTime date;
  if (date1904) {
    date = DateTime.utc(1904, 1, 1).add(Duration(days: days));
  } else if (days >= 61) {
    date = DateTime.utc(1899, 12, 30).add(Duration(days: days));
  } else if (days >= 1 && days <= 59) {
    date = DateTime.utc(1899, 12, 31).add(Duration(days: days));
  } else {
    return null; // 0 ve 60 (1900-02-29 diye bir gün yok)
  }
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Sunucuya giden hücre değeri: metin | sonlu sayı | null.
Object? normalizeImportCell(Object? cell, ImportColumn column) {
  if (cell == null) return null;
  if (cell is String) {
    final t = cell.trim();
    return t.isEmpty ? null : t;
  }
  if (cell is SheetDateCell) {
    if (column.type == ImportColumnType.date) {
      final iso = excelSerialToIso(cell.serial, date1904: cell.date1904);
      // Çevrilemeyen tarih sayı olarak gider: sunucu `DATE_INVALID` der (sessizce yanlış tarih yazılmaz).
      return iso ?? _number(cell.serial);
    }
    return _number(cell.serial);
  }
  if (cell is num) return _number(cell);
  return null;
}

Object? _number(num value) {
  if (value is int) return value.abs() >= 1000000000000000 ? value.toString() : value;
  final d = value.toDouble();
  if (!d.isFinite) return null;
  // Sunucu |değer| ≥ 1e15 sayıyı gövde hatası (400) sayar ve TÜM isteği reddeder; metin olarak gönderilirse yalnız
  // o satır hata alır (örn. PHONE_INVALID / NUMBER_INVALID).
  if (d.abs() >= 1e15) return d.abs() < 1e21 ? d.toStringAsFixed(0) : d.toString();
  if (d == d.roundToDouble()) return d.toInt();
  return d;
}

class ExtractResult {
  const ExtractResult(this.rows, this.blankRows);

  final List<ImportRow> rows;
  final int blankRows;
}

/// Başlık satırından sonraki satırları eşlenmiş sütunlarla sunucu satırlarına çevirir. Tamamen boş satırlar
/// atılır. [maxRows] aşılırsa [SpreadsheetException].
ExtractResult extractImportRows(
  SheetTable table,
  ColumnMapping mapping,
  ImportKindSpec spec, {
  int maxRows = SheetLimits.maxDataRows,
}) {
  final fields = <(ImportColumn, int)>[
    for (final column in spec.columns)
      if (mapping.assignment[column.key] != null) (column, mapping.assignment[column.key]!),
  ];
  final rows = <ImportRow>[];
  var blank = 0;
  for (var r = mapping.headerRowIndex + 1; r < table.rows.length; r++) {
    final source = table.rows[r];
    final cells = <String, Object?>{};
    var any = false;
    for (final (column, index) in fields) {
      final value = index < source.cells.length ? normalizeImportCell(source.cells[index], column) : null;
      cells[column.key] = value;
      if (value != null) any = true;
    }
    if (!any) {
      blank++;
      continue;
    }
    final hasAdSoyad = fields.any((f) => f.$1.key == 'ad_soyad');
    final hasTelefon = fields.any((f) => f.$1.key == 'telefon');
    final hasPlaka = fields.any((f) => f.$1.key == 'plaka');
    final hasTutar = fields.any((f) => f.$1.key == 'tutar');

    if (hasAdSoyad && hasTelefon) {
      final hasPerson = cells['ad_soyad'] != null ||
          cells['telefon'] != null ||
          cells['e_posta'] != null ||
          cells['plaka'] != null;
      if (!hasPerson) {
        blank++;
        continue;
      }
    } else if (hasPlaka && !hasTelefon) {
      final hasVehicle = cells['plaka'] != null ||
          cells['ad_soyad'] != null ||
          cells['e_posta'] != null;
      if (!hasVehicle) {
        blank++;
        continue;
      }
    } else if (hasTutar) {
      final hasBalance = cells['tutar'] != null;
      if (!hasBalance) {
        blank++;
        continue;
      }
    }
    rows.add(ImportRow(n: source.n, cells: cells));
    if (rows.length > maxRows) {
      throw SpreadsheetException(
        'Bir seferde en çok ${_thousands(maxRows)} satır yüklenebilir. Dosyayı ${_thousands(maxRows)}\'er '
        'satırlık parçalara bölüp sırayla yükleyin (aynı kayıtlar tekrar yüklenirse değişiklik yapılmaz).',
        code: 'FILE_LIMIT',
      );
    }
  }
  if (table.truncated) {
    throw SpreadsheetException(
      'Dosyada ${_thousands(maxRows)} satırdan fazla veri var. Dosyayı ${_thousands(maxRows)}\'er '
      'satırlık parçalara bölüp sırayla yükleyin.',
      code: 'FILE_LIMIT',
    );
  }
  return ExtractResult(rows, blank);
}

String _thousands(int value) {
  final s = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}
