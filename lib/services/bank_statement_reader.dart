// Banka ekstresi okuyucu (Dalga 2 / 2C): XLSX, CSV ve MT940 İSTEMCİDE ayrıştırılır (Karar C); sunucuya yalnız satır JSON'u gider.
// XLSX/CSV için mevcut güvenli okuyucular (XlsxReader, parseCsvText) kullanılır; sütun eşlemesi hesap başına profilde saklanır.
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:site_kapi_kontrol/services/bank_amount.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_text_decoder.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/services/mt940_parser.dart';

/// Bir yüklemede en çok satır (sunucu sınırıyla aynı).
const int bankMaxLines = 1500;

/// Başlık satırı bu kadar ilk satırda aranır.
const int bankHeaderSearchRows = 40;

enum BankFileKind { xlsx, csv, mt940 }

class BankLine {
  const BankLine({
    required this.n,
    required this.valueDate,
    required this.amountMinor,
    required this.description,
    this.counterpartyName,
    this.counterpartyIban,
    this.bankReference,
    this.balanceAfterMinor,
  });

  final int n;
  final String valueDate;
  final int amountMinor;
  final String description;
  final String? counterpartyName;
  final String? counterpartyIban;
  final String? bankReference;
  final int? balanceAfterMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'n': n,
    'value_date': valueDate,
    'amount_minor': amountMinor,
    'description': description,
    'counterparty_name': ?counterpartyName,
    'counterparty_iban': ?counterpartyIban,
    'bank_reference': ?bankReference,
    'balance_after_minor': ?balanceAfterMinor,
  };
}

/// Sütun eşlemesi (0 tabanlı sütun numaraları). Tutar ya tek sütun ([amount]) ya da ayrı [debit]/[credit] sütunlarıdır.
class BankMapping {
  const BankMapping({
    this.date,
    this.description,
    this.amount,
    this.debit,
    this.credit,
    this.indicator,
    this.balance,
    this.name,
    this.iban,
    this.reference,
  });

  final int? date;
  final int? description;
  final int? amount;
  final int? debit;
  final int? credit;
  final int? indicator;
  final int? balance;
  final int? name;
  final int? iban;
  final int? reference;

  bool get isComplete => date != null && (amount != null || debit != null || credit != null);

  BankMapping copyWith({
    int? Function()? date,
    int? Function()? description,
    int? Function()? amount,
    int? Function()? debit,
    int? Function()? credit,
    int? Function()? indicator,
    int? Function()? balance,
    int? Function()? name,
    int? Function()? iban,
    int? Function()? reference,
  }) => BankMapping(
    date: date != null ? date() : this.date,
    description: description != null ? description() : this.description,
    amount: amount != null ? amount() : this.amount,
    debit: debit != null ? debit() : this.debit,
    credit: credit != null ? credit() : this.credit,
    indicator: indicator != null ? indicator() : this.indicator,
    balance: balance != null ? balance() : this.balance,
    name: name != null ? name() : this.name,
    iban: iban != null ? iban() : this.iban,
    reference: reference != null ? reference() : this.reference,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'date': ?date,
    'description': ?description,
    'amount': ?amount,
    'debit': ?debit,
    'credit': ?credit,
    'indicator': ?indicator,
    'balance': ?balance,
    'name': ?name,
    'iban': ?iban,
    'reference': ?reference,
  };

  factory BankMapping.fromJson(Map<String, dynamic> json) {
    int? i(String k) => json[k] is int ? json[k] as int : null;
    return BankMapping(
      date: i('date'),
      description: i('description'),
      amount: i('amount'),
      debit: i('debit'),
      credit: i('credit'),
      indicator: i('indicator'),
      balance: i('balance'),
      name: i('name'),
      iban: i('iban'),
      reference: i('reference'),
    );
  }
}

/// Başlığı bulunmuş tablo (XLSX/CSV).
class BankTable {
  const BankTable({required this.headers, required this.rows, required this.signature, required this.guess, this.truncated = false});

  final List<String> headers;
  final List<SheetRow> rows;

  /// Katlanmış başlıkların birleşimi: kayıtlı profil bununla eşleşirse eşleme otomatiktir.
  final String signature;
  final BankMapping guess;
  final bool truncated;
}

class BankFile {
  const BankFile({required this.kind, required this.name, required this.size, required this.sha256, this.table, this.mt940});

  final BankFileKind kind;
  final String name;
  final int size;
  final String sha256;
  final BankTable? table;
  final Mt940Statement? mt940;
}

String bankFold(String value) {
  const from = 'çğıöşüÇĞİÖŞÜâîû';
  const to = 'cgiosuCGIOSUaiu';
  final buf = StringBuffer();
  for (final r in value.runes) {
    final ch = String.fromCharCode(r);
    final at = from.indexOf(ch);
    buf.write(at >= 0 ? to[at] : ch);
  }
  return buf.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

const Map<String, List<String>> _synonyms = <String, List<String>>{
  'date': ['tarih', 'islem tarihi', 'valor', 'valor tarihi', 'date'],
  'description': ['aciklama', 'islem aciklamasi', 'description', 'detay'],
  'amount': ['tutar', 'islem tutari', 'amount'],
  'debit': ['borc', 'cikan', 'debit'],
  'credit': ['alacak', 'giren', 'credit'],
  'indicator': ['b a', 'borc alacak', 'ba'],
  'balance': ['bakiye', 'balance'],
  'name': ['gonderen', 'karsi taraf', 'gonderen alici', 'unvan', 'ad soyad'],
  'iban': ['iban', 'karsi iban', 'gonderen iban'],
  'reference': ['dekont no', 'referans', 'dekont', 'islem no', 'reference'],
};

BankMapping guessMapping(List<String> headers) {
  int? find(String key) {
    final words = _synonyms[key]!;
    for (final w in words) {
      for (var i = 0; i < headers.length; i++) {
        if (bankFold(headers[i]) == w) return i;
      }
    }
    for (final w in words) {
      for (var i = 0; i < headers.length; i++) {
        final h = bankFold(headers[i]);
        if (h.isNotEmpty && h.contains(w) && w.length > 3) return i;
      }
    }
    return null;
  }

  final amount = find('amount');
  return BankMapping(
    date: find('date'),
    description: find('description'),
    amount: amount,
    debit: amount == null ? find('debit') : null,
    credit: amount == null ? find('credit') : null,
    indicator: find('indicator'),
    balance: find('balance'),
    name: find('name'),
    iban: find('iban'),
    reference: find('reference'),
  );
}

String _cellText(Object? cell) {
  if (cell == null) return '';
  if (cell is SheetDateCell) return '';
  if (cell is num) return cell == cell.roundToDouble() ? cell.toInt().toString() : cell.toString();
  return cell.toString();
}

/// Dosyayı okur. Hata durumunda [SpreadsheetException] ya da [Mt940Exception] (Türkçe ileti) fırlatır.
BankFile readBankFile(Uint8List bytes, String name) {
  if (bytes.isEmpty) throw const SpreadsheetException('Dosya boş.', code: 'FILE_EMPTY');
  final sha = crypto.sha256.convert(bytes).toString();
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    final reader = XlsxReader.open(bytes);
    if (reader.sheets.isEmpty) throw const SpreadsheetException('Çalışma kitabında sayfa yok.', code: 'FILE_EMPTY');
    final table = reader.readSheet(reader.sheets.first);
    return BankFile(kind: BankFileKind.xlsx, name: name, size: bytes.length, sha256: sha, table: _toBankTable(table));
  }
  final decoded = decodeSpreadsheetText(bytes);
  if (looksLikeMt940(decoded.text)) {
    return BankFile(kind: BankFileKind.mt940, name: name, size: bytes.length, sha256: sha, mt940: parseMt940(decoded.text));
  }
  final table = parseCsvText(decoded.text, encodingNote: decoded.note);
  return BankFile(kind: BankFileKind.csv, name: name, size: bytes.length, sha256: sha, table: _toBankTable(table));
}

BankTable _toBankTable(SheetTable table) {
  final limit = table.rows.length < bankHeaderSearchRows ? table.rows.length : bankHeaderSearchRows;
  var headerAt = -1;
  var best = 0;
  for (var i = 0; i < limit; i++) {
    final headers = table.rows[i].cells.map(_cellText).toList();
    final g = guessMapping(headers);
    final score = <Object?>[g.date, g.amount ?? g.debit ?? g.credit, g.description, g.balance].where((e) => e != null).length;
    if (g.isComplete && score > best) {
      best = score;
      headerAt = i;
    }
  }
  if (headerAt < 0) {
    // başlık bulunamadı: ilk dolu satırı başlık say, kullanıcı eşler
    if (table.rows.isEmpty) throw const SpreadsheetException('Dosyada satır bulunamadı.', code: 'FILE_EMPTY');
    headerAt = 0;
  }
  final headers = table.rows[headerAt].cells.map(_cellText).toList();
  final rows = table.rows.sublist(headerAt + 1);
  return BankTable(
    headers: headers,
    rows: rows,
    signature: headers.map(bankFold).join('|'),
    guess: guessMapping(headers),
    truncated: table.truncated,
  );
}

String? _dateOf(Object? cell) {
  if (cell == null) return null;
  DateTime? d;
  if (cell is SheetDateCell) {
    final base = cell.date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
    d = base.add(Duration(days: cell.serial.floor()));
  } else if (cell is String) {
    final s = cell.trim();
    final tr = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})').firstMatch(s);
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (tr != null) {
      d = DateTime.utc(int.parse(tr.group(3)!), int.parse(tr.group(2)!), int.parse(tr.group(1)!));
    } else if (iso != null) {
      d = DateTime.utc(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }
  }
  if (d == null) return null;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$m-$day';
}

int? _minorOf(Object? cell) {
  if (cell == null) return null;
  if (cell is num) return numToMinor(cell);
  if (cell is String) return parseAmountMinor(cell);
  return null;
}

class BankParseResult {
  const BankParseResult({required this.lines, required this.skipped, required this.errors, this.truncated = false});

  final List<BankLine> lines;

  /// Tarihi/tutarı okunamayan satır sayısı (toplam, açıklama satırları gibi).
  final int skipped;

  /// Tutarı tarihli ama okunamayan satırlar (kullanıcıya gösterilir): dosya satır numarası.
  final List<int> errors;
  final bool truncated;
}

/// Eşlemeyi uygular. Sütun numarası dışında kalan hücre boş sayılır.
BankParseResult applyBankMapping(BankTable table, BankMapping mapping) {
  Object? at(SheetRow row, int? col) => col == null || col < 0 || col >= row.cells.length ? null : row.cells[col];
  final lines = <BankLine>[];
  final errors = <int>[];
  var skipped = 0;
  for (final row in table.rows) {
    final date = _dateOf(at(row, mapping.date));
    if (date == null) {
      if (!row.isBlank) skipped += 1;
      continue;
    }
    int? amount;
    if (mapping.amount != null) {
      amount = _minorOf(at(row, mapping.amount));
      final ind = mapping.indicator == null ? null : bankFold(_cellText(at(row, mapping.indicator)));
      if (amount != null && ind != null && ind.isNotEmpty) {
        final debit = ind.startsWith('b') || ind.startsWith('d');
        amount = debit ? -amount.abs() : amount.abs();
      }
    } else {
      final credit = _minorOf(at(row, mapping.credit)) ?? 0;
      final debit = _minorOf(at(row, mapping.debit)) ?? 0;
      amount = credit.abs() - debit.abs();
    }
    if (amount == null) {
      errors.add(row.n);
      continue;
    }
    if (amount == 0) {
      skipped += 1;
      continue;
    }
    final desc = _cellText(at(row, mapping.description)).trim();
    final nameText = _cellText(at(row, mapping.name)).trim();
    final ibanText = _cellText(at(row, mapping.iban)).replaceAll(RegExp(r'\s'), '').toUpperCase();
    final ref = _cellText(at(row, mapping.reference)).trim();
    lines.add(
      BankLine(
        n: row.n,
        valueDate: date,
        amountMinor: amount,
        description: desc,
        counterpartyName: nameText.isEmpty ? null : nameText,
        counterpartyIban: ibanText.isEmpty ? null : ibanText,
        bankReference: ref.isEmpty ? null : ref,
        balanceAfterMinor: _minorOf(at(row, mapping.balance)),
      ),
    );
  }
  return BankParseResult(lines: lines, skipped: skipped, errors: errors, truncated: table.truncated);
}

BankParseResult bankLinesOfMt940(Mt940Statement s) {
  var n = 0;
  final lines = [
    for (final l in s.lines)
      BankLine(
        n: ++n,
        valueDate: l.valueDate,
        amountMinor: l.amountMinor,
        description: l.description,
        counterpartyName: l.counterpartyName,
        counterpartyIban: l.counterpartyIban,
        bankReference: l.bankReference,
      ),
  ];
  return BankParseResult(lines: lines, skipped: 0, errors: const <int>[]);
}

/// Sunucuya giden gövdenin dosya bölümü.
Map<String, dynamic> bankFileJson(BankFile f) => <String, dynamic>{'name': f.name, 'size': f.size, 'sha256': f.sha256};

