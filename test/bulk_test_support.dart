// Toplu yükleme testlerinin ortak düzeneği (Platform Faz 2b). `_test.dart` ile bitmediği için kendi başına koşmaz.
//
// Sunucu uçları SAHTE yanıtlarla (fixture) sürülür: sözleşme docs/PLATFORM_TOPLU_ISLEMLER.md.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';

Map<String, dynamic> _col(
  String key,
  String label, {
  bool required = false,
  String type = 'text',
  int? maxLength,
  List<String> aliases = const <String>[],
  String? hint,
}) => <String, dynamic>{
  'key': key,
  'label': label,
  'required': required,
  'type': type,
  'max_length': ?maxLength,
  'aliases': aliases,
  'hint': ?hint,
};

/// `GET imports/spec` örnek yanıtı (sözleşme "Şablon ve sütun sözleşmesi").
Map<String, dynamic> specJson({int version = 1}) => <String, dynamic>{
  'spec_version': version,
  'max_rows': 5000,
  'max_body_bytes': 5242880,
  'kinds': <String, dynamic>{
    'apartments': <String, dynamic>{
      'columns': <Map<String, dynamic>>[
        _col('blok', 'Blok', required: true, aliases: ['Blok Adı', 'Blok No'], hint: 'A, A Blok ya da Blok A'),
        _col('daire_no', 'Daire No', required: true, aliases: ['Daire', 'Kapı No', 'No'], hint: '5, 05, Daire 5'),
        _col('kat', 'Kat', type: 'number', hint: 'Zemin, bodrum ya da sayı'),
        _col('tip', 'Tip', maxLength: 40, aliases: ['Daire Tipi', 'Kategori']),
        _col('arsa_payi_pay', 'Arsa Payı (Pay)', type: 'number'),
        _col('arsa_payi_payda', 'Arsa Payı (Payda)', type: 'number'),
        _col('sorumlu', 'Borç Sorumlusu', type: 'enum', aliases: ['Sorumlu']),
      ],
    },
    'people': <String, dynamic>{
      'columns': <Map<String, dynamic>>[
        _col('ad_soyad', 'Ad Soyad', required: true, maxLength: 100, aliases: ['Adı Soyadı', 'İsim', 'Ad']),
        _col('telefon', 'Telefon', aliases: ['Tel', 'Cep Telefonu', 'GSM']),
        _col('e_posta', 'E-posta', aliases: ['E-Mail', 'Mail']),
        _col('blok', 'Blok', aliases: ['Blok Adı']),
        _col('daire_no', 'Daire No', aliases: ['Daire', 'Kapı No']),
        _col('iliski', 'İlişki', type: 'enum', aliases: ['Iliski', 'Tür']),
        _col('giris_tarihi', 'Giriş Tarihi', type: 'date', aliases: ['Taşınma Tarihi', 'Giris']),
        _col('plaka', 'Plaka', aliases: ['Plakalar', 'Araç Plakası']),
        _col('not', 'Not', maxLength: 500, aliases: ['Notlar']),
      ],
      'relation_words': <String, dynamic>{
        'owner': ['malik', 'mal sahibi', 'ev sahibi'],
        'tenant': ['kiracı', 'kiraci'],
        'family_member': ['aile', 'aile üyesi', 'eş', 'çocuk'],
        'resident': ['sakin', 'oturan'],
      },
    },
    'vehicles': <String, dynamic>{
      'columns': <Map<String, dynamic>>[
        _col('plaka', 'Plaka', required: true, aliases: ['Araç Plakası']),
        _col('e_posta', 'E-posta', aliases: ['E-Mail']),
        _col('blok', 'Blok'),
        _col('daire_no', 'Daire No', aliases: ['Daire']),
        _col('ad_soyad', 'Ad Soyad', aliases: ['İsim']),
        _col('not', 'Not'),
      ],
    },
  },
};

ImportSpec testSpec() => ImportSpec.fromJson(specJson());

/// Örnek önizleme özeti (sha256 hex uzunluğunda).
final String kTestHash = 'a' * 64;

/// Önizleme örnek yanıtı.
Map<String, dynamic> previewJson({
  String kind = 'people',
  String? hash,
  int rows = 4,
  int ok = 2,
  int unchanged = 1,
  int error = 1,
  int warnings = 1,
  List<Map<String, dynamic>>? issues,
  Map<String, dynamic>? plan,
  Object? landShare,
}) => <String, dynamic>{
  'kind': kind,
  'spec_version': 1,
  'preview_hash': hash ?? kTestHash,
  'totals': <String, dynamic>{
    'rows': rows,
    'ok': ok,
    'unchanged': unchanged,
    'error': error,
    'with_warnings': warnings,
  },
  'plan': plan ??
      <String, dynamic>{
        'people_create': 1,
        'people_link': 1,
        'people_reactivate': 0,
        'people_filled': 0,
        'residency_add': 2,
        'residency_upgrade': 0,
        'residency_unchanged': 1,
        'vehicle_add': 1,
        'vehicle_unchanged': 0,
      },
  'issues': issues ??
      <Map<String, dynamic>>[
        <String, dynamic>{
          'n': 3,
          'severity': 'error',
          'field': 'e_posta',
          'code': 'EMAIL_INVALID',
          'message': 'E-posta biçimi geçersiz.',
        },
        <String, dynamic>{
          'n': 4,
          'severity': 'warning',
          'field': 'plaka',
          'code': 'PLATE_INVALID',
          'message': 'Plaka biçimi geçersiz, atlandı.',
        },
      ],
  'samples': <Map<String, dynamic>>[
    <String, dynamic>{'n': 2, 'action': 'create', 'summary': 'Ahmet Yılmaz → A Blok - Daire 3 (Malik)'},
  ],
  'checks': <String, dynamic>{'land_share': landShare},
};

/// Commit yanıtı (201).
Map<String, dynamic> commitJson({bool replayed = false, bool withIssues = true}) => <String, dynamic>{
  'replayed': replayed,
  'run': <String, dynamic>{
    'id': 41,
    'kind': 'people',
    'created_at': '2026-10-16T10:00:00.000Z',
    'row_count': 4,
  },
  'result': <String, dynamic>{
    'rows': <String, dynamic>{'applied': 2, 'unchanged': 1, 'skipped': 1},
    'counts': <String, dynamic>{'people_create': 1, 'people_link': 1},
    'issues': withIssues
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'n': 3,
              'severity': 'error',
              'field': 'e_posta',
              'code': 'EMAIL_INVALID',
              'message': 'E-posta biçimi geçersiz.',
            },
          ]
        : null,
  },
};

/// Dışa aktarma zarfı örneği (kişiler).
Map<String, dynamic> envelopeJson({String kind = 'people', List<List<Object?>>? rows}) => <String, dynamic>{
  'kind': kind,
  'spec_version': 1,
  'generated_at': '2026-10-16T10:00:00.000Z',
  'filename_base': 'kisiler_gul-sitesi_20261016',
  'columns': <Map<String, dynamic>>[
    <String, dynamic>{'key': 'ad_soyad', 'label': 'Ad Soyad', 'type': 'text'},
    <String, dynamic>{'key': 'telefon', 'label': 'Telefon', 'type': 'text'},
    <String, dynamic>{'key': 'giris_tarihi', 'label': 'Giriş Tarihi', 'type': 'date'},
    <String, dynamic>{'key': 'brut_m2', 'label': 'Brüt m²', 'type': 'number', 'scale': 2},
    <String, dynamic>{'key': 'borc', 'label': 'Borç', 'type': 'money'},
  ],
  'rows': rows ??
      <List<Object?>>[
        <Object?>['Ahmet Yılmaz', '0 (555) 123 45 67', '2021-03-15', 125.5, 125050],
        <Object?>['=HYPERLINK("x")', null, null, 100, -5],
      ],
  'row_count': (rows ?? <int>[1, 2]).length,
};

/// Daire zarfı (şablon ön doldurma için).
Map<String, dynamic> apartmentsEnvelopeJson() => <String, dynamic>{
  'kind': 'apartments',
  'spec_version': 1,
  'generated_at': '2026-10-16T10:00:00.000Z',
  'filename_base': 'daireler_gul-sitesi_20261016',
  'columns': <Map<String, dynamic>>[
    <String, dynamic>{'key': 'blok', 'label': 'Blok', 'type': 'text'},
    <String, dynamic>{'key': 'daire_no', 'label': 'Daire No', 'type': 'text'},
    <String, dynamic>{'key': 'kat', 'label': 'Kat', 'type': 'number'},
    <String, dynamic>{'key': 'tip', 'label': 'Tip', 'type': 'text'},
    <String, dynamic>{'key': 'brut_m2', 'label': 'Brüt m²', 'type': 'number', 'scale': 2},
    <String, dynamic>{'key': 'malik', 'label': 'Malik', 'type': 'text'},
  ],
  'rows': <List<Object?>>[
    <Object?>['A Blok', '1', 0, '2+1', 95.5, 'Ali Veli'],
    <Object?>['A Blok', '2', 1, null, null, null],
    <Object?>['B Blok', '1', 0, '3+1', 120, null],
  ],
  'row_count': 3,
};

// --- XLSX düzeneği -----------------------------------------------------------------------------

/// Verilen parçalardan (yol -> içerik) zip kurar.
Uint8List zipOf(Map<String, String> parts, {bool compress = true}) {
  final archive = Archive();
  parts.forEach((name, content) {
    final bytes = utf8.encode(content);
    if (compress) {
      archive.add(ArchiveFile.bytes(name, bytes));
    } else {
      archive.add(ArchiveFile.noCompress(name, bytes.length, bytes));
    }
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const String _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _rns = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// Elle yazılmış, üretici biçimini taklit eden küçük XLSX. [sheetXml]: `<sheetData>` DIŞINDAKİ gövde dahil tam
/// `<worksheet>` içeriği değil, yalnız `<row>…</row>` dizisi.
Uint8List handMadeXlsx({
  required Object rows,
  String sharedStrings = '',
  String? styles,
  String sheetName = 'Sayfa1',
  bool date1904 = false,
  String sheetState = '',
  List<(String name, Object rows)> extraSheets = const <(String, Object)>[],
  Map<String, String> extraParts = const <String, String>{},
}) {
  final allSheets = <(String, Object)>[(sheetName, rows), ...extraSheets];
  final sheetTags = StringBuffer();
  final rels = StringBuffer();
  final parts = <String, String>{};
  for (var i = 0; i < allSheets.length; i++) {
    final state = i == 0 ? sheetState : '';
    sheetTags.write('<sheet name="${allSheets[i].$1}" sheetId="${i + 1}"$state r:id="rId${i + 1}"/>');
    rels.write(
      '<Relationship Id="rId${i + 1}" Type="$_rns/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
    );
    parts['xl/worksheets/sheet${i + 1}.xml'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="$_ns" xmlns:r="$_rns"><sheetData>${_rowsText(allSheets[i].$2)}</sheetData></worksheet>';
  }
  parts['[Content_Types].xml'] =
      '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="xml" ContentType="application/xml"/></Types>';
  parts['xl/workbook.xml'] =
      '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="$_ns" xmlns:r="$_rns">'
      '${date1904 ? '<workbookPr date1904="1"/>' : ''}<sheets>$sheetTags</sheets></workbook>';
  parts['xl/_rels/workbook.xml.rels'] =
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>';
  if (sharedStrings.isNotEmpty) {
    parts['xl/sharedStrings.xml'] = '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="$_ns">$sharedStrings</sst>';
  }
  if (styles != null) parts['xl/styles.xml'] = styles;
  parts.addAll(extraParts);
  return zipOf(parts);
}

/// Excel TR'nin yazdığı türden stil tablosu: 1 = gg.aa.yyyy tarihi, 2 = sayı (0,00), 3 = yerleşik 14 (tarih).
const String dateStyles =
    '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="$_ns">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd\\.mm\\.yyyy"/></numFmts>'
    '<cellStyleXfs count="1"><xf numFmtId="0"/></cellStyleXfs>'
    '<cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="2"/><xf numFmtId="14"/></cellXfs>'
    '</styleSheet>';

String _rowsText(Object rows) => rows is List ? rows.join() : '$rows';

String sharedStringsOf(List<String> values) =>
    values.map((v) => '<si><t>${_x(v)}</t></si>').join();

String _x(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// `<c>` hücresi (paylaşılan metin indeksi).
String sCell(String ref, int index) => '<c r="$ref" t="s"><v>$index</v></c>';

String nCell(String ref, num value, {int style = 0}) =>
    '<c r="$ref"${style == 0 ? '' : ' s="$style"'}><v>$value</v></c>';

String iCell(String ref, String text) =>
    '<c r="$ref" t="inlineStr"><is><t>${_x(text)}</t></is></c>';

String row(int n, List<String> cells) => '<row r="$n">${cells.join()}</row>';

/// Zip içindeki TÜM yerel başlık ve merkezi dizin kayıtlarında "açılmış boyut" alanını [size] yapar (sahte bomba).
Uint8List forgeUncompressedSize(Uint8List zip, int size) {
  final out = Uint8List.fromList(zip);
  final data = ByteData.sublistView(out);
  for (var i = 0; i + 4 <= out.length; i++) {
    final sig = data.getUint32(i, Endian.little);
    if (sig == 0x04034b50 && i + 26 <= out.length) {
      data.setUint32(i + 22, size, Endian.little);
    } else if (sig == 0x02014b50 && i + 28 <= out.length) {
      data.setUint32(i + 24, size, Endian.little);
    }
  }
  return out;
}

// --- Süre ölçümü ------------------------------------------------------------------------------

/// [body]'yi [runs] kez çalıştırıp (en küçük süre ms, son sonuç) döner. Eşzamanlı yükte (diğer test süreçleri,
/// CI) tek ölçümün gürültüsünü ayıklar: gerçek yavaşlık HER denemede görünür, geçici CPU çekişmesi görünmez.
(int, T) bestOfMillis<T>(T Function() body, {int runs = 3}) {
  var best = 1 << 30;
  late T result;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    result = body();
    sw.stop();
    if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
  }
  return (best, result);
}

/// [bestOfMillis]'in eşzamansız hâli.
Future<(int, T)> bestOfMillisAsync<T>(Future<T> Function() body, {int runs = 3}) async {
  var best = 1 << 30;
  late T result;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    result = await body();
    sw.stop();
    if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
  }
  return (best, result);
}

/// Merkezi dizin başlıklarında (46 baytlık `PK\x01\x02` kayıtları) alan yamar; yalnız verilen alanlar değişir.
/// Sahte "sembolik bağ", "zip64" ve "desteklenmeyen sıkıştırma" dosyaları kurmak içindir.
Uint8List forgeCentralHeaders(
  Uint8List zip, {
  int? madeBy,
  int? method,
  int? compressedSize,
  int? uncompressedSize,
  int? externalAttributes,
  int? eocdEntryCount,
}) {
  final out = Uint8List.fromList(zip);
  final data = ByteData.sublistView(out);
  for (var i = 0; i + 46 <= out.length; i++) {
    final sig = data.getUint32(i, Endian.little);
    if (sig == 0x02014b50) {
      if (madeBy != null) data.setUint16(i + 4, madeBy, Endian.little);
      if (method != null) data.setUint16(i + 10, method, Endian.little);
      if (compressedSize != null) data.setUint32(i + 20, compressedSize, Endian.little);
      if (uncompressedSize != null) data.setUint32(i + 24, uncompressedSize, Endian.little);
      if (externalAttributes != null) data.setUint32(i + 38, externalAttributes, Endian.little);
    } else if (sig == 0x06054b50 && eocdEntryCount != null && i + 22 <= out.length) {
      data.setUint16(i + 8, eocdEntryCount, Endian.little);
      data.setUint16(i + 10, eocdEntryCount, Endian.little);
    }
  }
  return out;
}
