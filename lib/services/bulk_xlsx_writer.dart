// XLSX yazıcı (Platform Faz 2b). Kendi uygulamamız (`excel` paketi EKLENMEZ; Karar 2).
//
// Kurallar (docs/PLATFORM_TOPLU_ISLEMLER.md "İstemci üretici kuralları"):
// - Tüm metin hücreleri `t="inlineStr"`: formül olarak yorumlanamaz, bu yüzden XLSX'te `'` kaçışı EKLENMEZ.
// - Başlık kalın + dondurulmuş; `telefon / plaka / blok / daire_no` gibi sütunlar metin biçimli (`@`) tanımlanabilir.
// - Tarih gerçek tarih hücresi (`gg.aa.yyyy`), sayı gerçek sayı, para tamsayı kuruştan yalnız metin aritmetiğiyle.
// - Sayfa adı ≤ 31 karakter ve `[]:*?/\` içermez; XML'de geçersiz karakterler atılır.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:site_kapi_kontrol/services/bulk_cell_safety.dart';
import 'package:site_kapi_kontrol/services/bulk_formatting.dart';

/// Sütun / hücre biçimi.
enum XlsxFormat { general, text, date, integer, decimal, money, wrap }

/// Para hücresi: [minor] tamsayı kuruş.
class XlsxMoney {
  const XlsxMoney(this.minor);

  final Object minor;
}

class XlsxColumn {
  const XlsxColumn(this.header, {this.format = XlsxFormat.general, this.scale = 2, this.width});

  final String header;
  final XlsxFormat format;

  /// [XlsxFormat.decimal] için ondalık basamak sayısı.
  final int scale;

  /// Karakter cinsinden genişlik; null ise içerikten kestirilir.
  final double? width;
}

class XlsxSheet {
  const XlsxSheet({
    required this.name,
    required this.columns,
    required this.rows,
    this.freezeHeader = true,
  });

  final String name;
  final List<XlsxColumn> columns;

  /// Hücre değerleri: `String` | `int` | `double` | `DateTime` | ISO tarih metni (tarih sütununda) | [XlsxMoney] | null.
  final List<List<Object?>> rows;
  final bool freezeHeader;
}

class _Styles {
  // Sabit stil dizinleri.
  static const int general = 0;
  static const int header = 1;
  static const int text = 2;
  static const int date = 3;
  static const int integer = 4;
  static const int money = 5;
  static const int wrap = 6;
  static const int decimal2 = 7;

  final List<int> _extraScales = <int>[];

  int decimal(int scale) {
    final s = scale.clamp(0, 8);
    if (s == 0) return integer;
    if (s == 2) return decimal2;
    var i = _extraScales.indexOf(s);
    if (i < 0) {
      _extraScales.add(s);
      i = _extraScales.length - 1;
    }
    return 8 + i;
  }

  int forColumn(XlsxColumn column) {
    switch (column.format) {
      case XlsxFormat.general:
        return general;
      case XlsxFormat.text:
        return text;
      case XlsxFormat.date:
        return date;
      case XlsxFormat.integer:
        return integer;
      case XlsxFormat.decimal:
        return decimal(column.scale);
      case XlsxFormat.money:
        return money;
      case XlsxFormat.wrap:
        return wrap;
    }
  }

  String xml() {
    final custom = StringBuffer();
    // 164: gg.aa.yyyy; 165+: 0.0, 0.000...
    custom.write('<numFmt numFmtId="164" formatCode="dd\\.mm\\.yyyy"/>');
    for (var i = 0; i < _extraScales.length; i++) {
      custom.write('<numFmt numFmtId="${165 + i}" formatCode="0.${'0' * _extraScales[i]}"/>');
    }
    final xfs = StringBuffer()
      ..write('<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>')
      ..write(
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
        'applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>',
      )
      ..write('<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>')
      ..write('<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>')
      ..write('<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>')
      ..write('<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>')
      ..write(
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1">'
        '<alignment vertical="top" wrapText="1"/></xf>',
      )
      ..write('<xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>');
    for (var i = 0; i < _extraScales.length; i++) {
      xfs.write('<xf numFmtId="${165 + i}" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>');
    }
    final count = 8 + _extraScales.length;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="${1 + _extraScales.length}">$custom</numFmts>'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFE8EEF7"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left/><right/><top/><bottom style="thin"><color auto="1"/></bottom><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="$count">$xfs</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }
}

String _columnLetters(int index) {
  var n = index + 1;
  final out = <int>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    out.add(0x41 + r);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(out.reversed);
}

/// Sayfaları XLSX baytlarına çevirir.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) throw ArgumentError('En az bir sayfa gerekir.');
  final styles = _Styles();
  final usedNames = <String>{};
  final sheetNames = <String>[];
  for (final sheet in sheets) {
    var name = sanitizeSheetName(sheet.name);
    var suffix = 2;
    while (!usedNames.add(name.toLowerCase())) {
      final tail = ' ($suffix)';
      final base = name.length + tail.length > 31 ? name.substring(0, 31 - tail.length) : name;
      name = '$base$tail';
      suffix++;
    }
    sheetNames.add(name);
  }
  final sheetXml = <String>[
    for (var i = 0; i < sheets.length; i++) _sheetXml(sheets[i], styles, selected: i == 0),
  ];

  final archive = Archive();
  void add(String name, String content) {
    archive.add(ArchiveFile.bytes(name, utf8.encode(content)));
  }

  final overrides = StringBuffer();
  for (var i = 0; i < sheets.length; i++) {
    overrides.write(
      '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    );
  }
  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '$overrides</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/></Relationships>',
  );
  final sheetTags = StringBuffer();
  final rels = StringBuffer();
  for (var i = 0; i < sheets.length; i++) {
    sheetTags.write('<sheet name="${escapeXml(sheetNames[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    rels.write(
      '<Relationship Id="rId${i + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet${i + 1}.xml"/>',
    );
  }
  rels.write(
    '<Relationship Id="rId${sheets.length + 1}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="24000" windowHeight="12000"/></bookViews>'
        '<sheets>$sheetTags</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>',
  );
  add('xl/styles.xml', styles.xml());
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', sheetXml[i]);
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

String _sheetXml(XlsxSheet sheet, _Styles styles, {required bool selected}) {
  final columns = sheet.columns;
  final out = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  final lastCol = columns.isEmpty ? 0 : columns.length - 1;
  final lastRow = sheet.rows.length + 1;
  out.write('<dimension ref="A1:${_columnLetters(lastCol)}$lastRow"/>');
  out.write('<sheetViews><sheetView workbookViewId="0"${selected ? ' tabSelected="1"' : ''}>');
  if (sheet.freezeHeader) {
    out.write(
      '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>',
    );
  }
  out.write('</sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>');

  // Sütun genişlikleri ve sütun stilleri.
  out.write('<cols>');
  for (var c = 0; c < columns.length; c++) {
    final column = columns[c];
    final width = column.width ?? _estimateWidth(column, sheet.rows, c);
    final style = styles.forColumn(column);
    out.write(
      '<col min="${c + 1}" max="${c + 1}" width="${width.toStringAsFixed(1)}" customWidth="1"'
      '${style == _Styles.general ? '' : ' style="$style"'}/>',
    );
  }
  out.write('</cols><sheetData>');

  // Başlık.
  out.write('<row r="1" ht="22" customHeight="1">');
  for (var c = 0; c < columns.length; c++) {
    out.write(_inlineCell('${_columnLetters(c)}1', columns[c].header, _Styles.header));
  }
  out.write('</row>');

  for (var r = 0; r < sheet.rows.length; r++) {
    final rowNo = r + 2;
    final row = sheet.rows[r];
    out.write('<row r="$rowNo">');
    for (var c = 0; c < columns.length && c < row.length; c++) {
      final cell = _cellXml('${_columnLetters(c)}$rowNo', row[c], columns[c], styles);
      if (cell != null) out.write(cell);
    }
    out.write('</row>');
  }
  out.write('</sheetData>');
  out.write('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>');
  out.write('</worksheet>');
  return out.toString();
}

double _estimateWidth(XlsxColumn column, List<List<Object?>> rows, int index) {
  var longest = column.header.length;
  final sample = rows.length < 200 ? rows.length : 200;
  for (var r = 0; r < sample; r++) {
    final row = rows[r];
    if (index >= row.length) continue;
    final v = row[index];
    final len = v is String ? v.length : (v == null ? 0 : 12);
    if (len > longest) longest = len;
  }
  return (longest + 3).clamp(10, 50).toDouble();
}

String _inlineCell(String ref, String text, int style) {
  final styleAttr = style == 0 ? '' : ' s="$style"';
  return '<c r="$ref" t="inlineStr"$styleAttr><is><t xml:space="preserve">${escapeXml(text)}</t></is></c>';
}

String? _cellXml(String ref, Object? value, XlsxColumn column, _Styles styles) {
  if (value == null) return null;
  final columnStyle = styles.forColumn(column);
  if (value is XlsxMoney) {
    final text = formatMoneyMinor(value.minor, separator: '.');
    if (text == null) return null;
    return '<c r="$ref" s="${_Styles.money}"><v>$text</v></c>';
  }
  if (value is DateTime ||
      (value is String && column.format == XlsxFormat.date && parseIsoDate(value) != null)) {
    final serial = excelSerialOf(value);
    if (serial != null) return '<c r="$ref" s="${_Styles.date}"><v>$serial</v></c>';
    // Excel 1900-03-01 öncesi tarihi gösteremez: okunur metin olarak yazılır.
    final text = formatTurkishDate(value);
    return text == null ? null : _inlineCell(ref, text, _Styles.text);
  }
  if (value is num) {
    if (value is double && !value.isFinite) return null;
    final style = switch (column.format) {
      XlsxFormat.integer || XlsxFormat.decimal || XlsxFormat.money => columnStyle,
      _ => _Styles.general,
    };
    final text = formatPlainNumber(value, separator: '.');
    final styleAttr = style == 0 ? '' : ' s="$style"';
    return '<c r="$ref"$styleAttr><v>$text</v></c>';
  }
  if (value is bool) return _inlineCell(ref, value ? 'Evet' : 'Hayır', columnStyle);
  final text = '$value';
  if (text.isEmpty) return null;
  final style = switch (column.format) {
    XlsxFormat.text || XlsxFormat.wrap => columnStyle,
    _ => _Styles.general,
  };
  return _inlineCell(ref, text, style);
}
