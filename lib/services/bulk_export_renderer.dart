// `ExportEnvelope` -> CSV / XLSX dosyası (Platform Faz 2b). Biçimlendirme ve formül kaçışı TEK yerdedir
// (sözleşme Karar 13); Faz 4b finans raporları aynı üreticiyi kullanır.
//
// CSV: UTF-8 + BOM, ayırıcı `;`, satır sonu CRLF, sayı ondalık VİRGÜL ve binlik ayırıcısız, tarih `GG.AA.YYYY`,
// boş = boş hücre, ilk satır başlık, metin hücreler formül kaçışlı. XLSX: bkz. bulk_xlsx_writer.dart.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_cell_safety.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_formatting.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';

/// Kullanıcıya verilecek hazır dosya.
class RenderedFile {
  const RenderedFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.format,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final ExportFormat format;
}

/// Metin sütunları: Excel'in sayıya çevirmemesi için XLSX'te metin biçimli (`@`) tanımlanır.
const Set<String> kTextFormattedKeys = <String>{'telefon', 'plaka', 'blok', 'daire_no'};

const String _fallbackBase = 'dosya';

/// Dosya adı gövdesini güvenli ASCII yapar: Türkçe harfler katlanır, diğer her şey `_` olur, en çok 80 karakter.
String safeFileBase(String base) {
  const from = 'ÇĞİÖŞÜçğıöşü';
  const to = 'CGIOSUcgiosu';
  final out = StringBuffer();
  for (final rune in base.runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    final mapped = i >= 0 ? to[i] : ch;
    if (RegExp(r'^[A-Za-z0-9._-]$').hasMatch(mapped)) {
      out.write(mapped);
    } else {
      out.write('_');
    }
  }
  var s = out.toString().replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  if (s.length > 80) s = s.substring(0, 80);
  return s.isEmpty ? _fallbackBase : s;
}

/// Zarfı [format] dosyasına çevirir.
RenderedFile renderExport(ExportEnvelope envelope, ExportFormat format, {String? sheetName}) {
  final base = safeFileBase(envelope.filenameBase);
  switch (format) {
    case ExportFormat.csv:
      return RenderedFile(
        bytes: _renderCsv(envelope),
        fileName: '$base.csv',
        mimeType: format.mimeType,
        format: format,
      );
    case ExportFormat.xlsx:
      return RenderedFile(
        bytes: _renderXlsx(envelope, sheetName: sheetName ?? envelope.kind),
        fileName: '$base.xlsx',
        mimeType: format.mimeType,
        format: format,
      );
  }
}

/// Büyük zarfları (20.000 satıra kadar) arayüzü dondurmamak için ayrı isolate'ta üretir; küçükler satır içi.
Future<RenderedFile> renderExportAsync(
  ExportEnvelope envelope,
  ExportFormat format, {
  String? sheetName,
  int inlineLimit = 1500,
}) {
  if (envelope.rowCount <= inlineLimit) {
    return Future<RenderedFile>.value(renderExport(envelope, format, sheetName: sheetName));
  }
  return compute(_renderEntry, (envelope, format, sheetName));
}

RenderedFile _renderEntry((ExportEnvelope, ExportFormat, String?) args) =>
    renderExport(args.$1, args.$2, sheetName: args.$3);

// --- CSV --------------------------------------------------------------------------------------

String csvCellText(ExportColumn column, Object? value) {
  if (value == null) return '';
  switch (column.type) {
    case ExportColumnType.number:
      final text = formatPlainNumber(value, scale: column.scale);
      return text.isEmpty ? escapeCsvFormula('$value') : text;
    case ExportColumnType.date:
      return formatTurkishDate(value) ?? escapeCsvFormula('$value');
    case ExportColumnType.money:
      return formatMoneyMinor(value) ?? escapeCsvFormula('$value');
    case ExportColumnType.text:
      if (value is bool) return value ? 'Evet' : 'Hayır';
      return escapeCsvFormula('$value');
  }
}

Uint8List _renderCsv(ExportEnvelope envelope) {
  final rows = <List<String>>[
    <String>[for (final c in envelope.columns) escapeCsvFormula(c.label)],
    for (final row in envelope.rows)
      <String>[for (var i = 0; i < envelope.columns.length; i++) csvCellText(envelope.columns[i], row[i])],
  ];
  return csvBytes(rows);
}

// --- XLSX -------------------------------------------------------------------------------------

Uint8List _renderXlsx(ExportEnvelope envelope, {required String sheetName}) {
  final columns = <XlsxColumn>[
    for (final c in envelope.columns)
      XlsxColumn(
        c.label,
        format: switch (c.type) {
          ExportColumnType.text => kTextFormattedKeys.contains(c.key) ? XlsxFormat.text : XlsxFormat.general,
          ExportColumnType.number => (c.scale ?? 0) > 0 ? XlsxFormat.decimal : XlsxFormat.general,
          ExportColumnType.date => XlsxFormat.date,
          ExportColumnType.money => XlsxFormat.money,
        },
        scale: c.scale ?? 2,
      ),
  ];
  final rows = <List<Object?>>[];
  for (final row in envelope.rows) {
    rows.add(<Object?>[
      for (var i = 0; i < envelope.columns.length; i++) _xlsxValue(envelope.columns[i], row[i]),
    ]);
  }
  return buildXlsx(<XlsxSheet>[XlsxSheet(name: sheetName, columns: columns, rows: rows)]);
}

Object? _xlsxValue(ExportColumn column, Object? value) {
  if (value == null) return null;
  switch (column.type) {
    case ExportColumnType.number:
      if (value is num) return value;
      return num.tryParse('$value'.trim().replaceAll(',', '.')) ?? '$value';
    case ExportColumnType.date:
      return parseIsoDate(value) != null ? value : '$value';
    case ExportColumnType.money:
      return formatMoneyMinor(value) != null ? XlsxMoney(value) : '$value';
    case ExportColumnType.text:
      return value is String ? value : '$value';
  }
}

// --- Hata raporu ------------------------------------------------------------------------------

/// Satır sorunları raporu (CSV: satır;alan;kod;ileti). Hücre DEĞERİ eklenmez; sunucu iletisi en çok 40 karakterlik
/// değer yankılayabilir, bu yüzden her hücre formül kaçışından geçer.
RenderedFile renderIssueReport(
  List<ImportIssue> issues,
  ImportKind kind, {
  Map<String, String> fieldLabels = const <String, String>{},
  DateTime? now,
}) {
  final stamp = _stamp(now ?? DateTime.now());
  final rows = <List<String>>[
    <String>['Satır', 'Alan', 'Kod', 'İleti'],
    for (final issue in issues)
      <String>[
        '${issue.n}',
        escapeCsvFormula(fieldLabels[issue.field] ?? issue.field ?? ''),
        escapeCsvFormula(issue.code),
        escapeCsvFormula(issue.message),
      ],
  ];
  return RenderedFile(
    bytes: csvBytes(rows),
    fileName: 'hata_raporu_${kind.apiValue}_$stamp.csv',
    mimeType: ExportFormat.csv.mimeType,
    format: ExportFormat.csv,
  );
}

String _stamp(DateTime now) {
  final u = now.toUtc().add(const Duration(hours: 3));
  return '${u.year.toString().padLeft(4, '0')}${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}';
}
