// Toplu yükleme şablonu (Platform Faz 2b).
//
// XLSX: `Daireler` sayfası sitenin MEVCUT blok / daire numaralarıyla ön dolu (`exports/apartments` zarfından),
// `Kişiler` ve `Araçlar` yalnız başlık satırı, `Açıklama` sayfası sütunları, kuralları, örnekleri ve ilişki
// sözlüğünü anlatır. CSV: seçilen türün başlık satırı (`;` + BOM); daire şablonu ön doludur. Veri sayfalarına
// ÖRNEK SATIR KONMAZ: yanlışlıkla yüklenmesin diye örnekler yalnız `Açıklama` sayfasındadır.
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_formatting.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';

const Map<String, String> _examples = <String, String>{
  'blok': 'A Blok',
  'daire_no': '5',
  'kat': '3',
  'tip': '3+1',
  'brut_m2': '125,5',
  'net_m2': '110',
  'arsa_payi_pay': '35',
  'arsa_payi_payda': '1000',
  'sorumlu': 'Malik',
  'ad_soyad': 'Ahmet Yılmaz',
  'telefon': '0 (555) 123 45 67',
  'e_posta': 'ahmet@ornek.com',
  'iliski': 'Malik',
  'giris_tarihi': '15.03.2021',
  'plaka': '34 ABC 123, 06 XY 789',
  'not': 'Kısa bir not',
  'hesap': 'Ev sahibi',
  'tutar': '1.250,50',
  'vade': '01.10.2026',
  'aciklama': 'Eski yazılımdan devir',
};

/// Şablon kitabına birlikte giren türler: klasik üçlü tek kitapta; «Hepsi bir arada» ve «Devir bakiyesi» ayrı dosyadır.
List<ImportKind> _groupOf(ImportKind kind) => switch (kind) {
  ImportKind.allInOne => const <ImportKind>[ImportKind.allInOne],
  ImportKind.openingBalances => const <ImportKind>[ImportKind.openingBalances],
  _ => const <ImportKind>[ImportKind.apartments, ImportKind.people, ImportKind.vehicles],
};

bool _prefillsApartments(ImportKind kind) =>
    kind == ImportKind.apartments || kind == ImportKind.allInOne || kind == ImportKind.openingBalances;

const Map<String, String> _relationLabels = <String, String>{
  'owner': 'Malik',
  'tenant': 'Kiracı',
  'family_member': 'Aile Üyesi',
  'resident': 'Sakin',
};

const Map<String, List<String>> _fallbackRelationWords = <String, List<String>>{
  'owner': <String>['malik', 'mal sahibi', 'ev sahibi'],
  'tenant': <String>['kiracı'],
  'family_member': <String>['aile', 'aile üyesi', 'eş', 'çocuk'],
  'resident': <String>['sakin', 'oturan', '(boş bırakılırsa)'],
};

const Map<String, String> _responsibleLabels = <String, String>{
  'owner': 'Malik',
  'tenant': 'Kiracı',
  'both': 'İkisi',
};

const Map<String, List<String>> _fallbackResponsibleWords = <String, List<String>>{
  'owner': <String>['Malik', 'Mal sahibi', 'Ev sahibi'],
  'tenant': <String>['Kiracı'],
  'both': <String>['İkisi', 'İkisi de', 'Her ikisi'],
};

const String _fileBase = 'toplu_yukleme_sablonu';

/// Şablonda gösterilmeyecek (kullanıcı isteğiyle gizlenen), ancak geriye dönük uyumluluk
/// kapsamında sistem ve parser tarafından desteklenmeye devam eden isteğe bağlı sütunlar.
const Set<String> kExcludedTemplateKeys = <String>{
  'brut_m2',
  'net_m2',
  'arsa_payi_pay',
  'arsa_payi_payda',
  'not',
};

String templateHeaderLabel(ImportColumn column) {
  return column.required ? '${column.label}*' : column.label;
}

XlsxColumn _templateColumn(ImportColumn column) {
  final XlsxFormat format;
  if (kTextFormattedKeys.contains(column.key)) {
    format = XlsxFormat.text;
  } else if (column.type == ImportColumnType.date) {
    format = XlsxFormat.date;
  } else {
    format = XlsxFormat.general;
  }
  return XlsxColumn(templateHeaderLabel(column), format: format, width: _width(column));
}

double _width(ImportColumn column) {
  final base = templateHeaderLabel(column).length + 4;
  final hint = switch (column.key) {
    'ad_soyad' => 24,
    'e_posta' => 26,
    'plaka' => 24,
    'telefon' => 20,
    'not' => 30,
    _ => 12,
  };
  return (base > hint ? base : hint).toDouble();
}

/// Zarf satırındaki değeri şablon sütununa eşler (anahtar, yoksa katlanmış etiket).
Map<String, int> _envelopeIndex(ExportEnvelope envelope, ImportKindSpec spec) {
  final index = <String, int>{};
  final byKey = <String, int>{};
  final byLabel = <String, int>{};
  for (var i = 0; i < envelope.columns.length; i++) {
    byKey[envelope.columns[i].key] = i;
    byLabel[foldHeader(envelope.columns[i].label)] = i;
  }
  for (final column in spec.columns) {
    final i = byKey[column.key] ?? byLabel[foldHeader(column.label)];
    if (i != null) index[column.key] = i;
  }
  return index;
}

/// Dolu şablon satırları (yalnız `apartments` + zarf varsa).
List<List<Object?>> _prefilledRows(ExportEnvelope? envelope, ImportKindSpec spec, List<ImportColumn> columns) {
  if (envelope == null) return const <List<Object?>>[];
  final index = _envelopeIndex(envelope, spec);
  // Anahtar sütunlar (blok, daire no) eşlenmediyse zarf bu şablona uymaz: ön doldurma yapılmaz.
  if (!index.containsKey('blok') || !index.containsKey('daire_no')) return const <List<Object?>>[];
  return <List<Object?>>[
    for (final row in envelope.rows)
      <Object?>[
        for (final column in columns)
          index.containsKey(column.key) ? _cellFor(column, envelope.columns[index[column.key]!], row[index[column.key]!]) : null,
      ],
  ];
}

Object? _cellFor(ImportColumn column, ExportColumn source, Object? value) {
  if (value == null) return null;
  if (column.type == ImportColumnType.number && value is num) return value;
  if (column.type == ImportColumnType.date) return value;
  if (value is num) return formatPlainNumber(value);
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

List<List<String>> _explanationRows(ImportSpec spec, {required String siteName, required List<ImportKind> group}) {
  final rows = <List<String>>[
    <String>['Toplu Yükleme Şablonu', '', '', ''],
    if (siteName.trim().isNotEmpty) <String>['Site', siteName.trim(), '', ''],
    <String>['', '', '', ''],
    <String>[
      'Nasıl kullanılır',
      'Doldurduğunuz sayfayı kaydedin; uygulamada Kişiler > Toplu Yükle ile yükleyin. İlk satır başlıktır, değiştirmeyin.',
      '',
      '',
    ],
    <String>[
      'Boş hücreler',
      'Boş bırakılan hücre mevcut bir değeri SİLMEZ. Dolu bir değer yalnız o alan boşsa yazılır.',
      '',
      '',
    ],
    <String>[
      'Tekrar yükleme',
      'Aynı dosyayı yeniden yüklemek güvenlidir: zaten kayıtlı satırlar «değişiklik yok» sayılır.',
      '',
      '',
    ],
    <String>[
      'Satır sınırı',
      'Bir seferde en çok ${spec.maxRows} satır yüklenir. Daha büyük dosyaları parçalara bölün.',
      '',
      '',
    ],
    <String>['', '', '', ''],
  ];
  for (final kind in group) {
    final kindSpec = spec.of(kind);
    if (kindSpec == null) continue;
    rows.add(<String>['${kind.label} sayfası', '', '', '']);
    rows.add(<String>['Sütun', 'Zorunlu mu?', 'Kural', 'Örnek']);
    for (final column in kindSpec.columns.where((c) => !kExcludedTemplateKeys.contains(c.key))) {
      final rule = <String>[
        if (column.hint != null) column.hint!,
        if (column.maxLength != null) 'En çok ${column.maxLength} karakter.',
      ].join(' ');
      rows.add(<String>[
        templateHeaderLabel(column),
        column.required ? 'Evet' : 'Hayır',
        rule,
        _examples[column.key] ?? '',
      ]);
    }
    rows.add(<String>['', '', '', '']);
  }
  if (group.contains(ImportKind.openingBalances)) {
    rows.add(<String>['Devir bakiyesi', 'Tutar TL olarak yazılır (1.250,50). Eksi (alacaklı) tutar desteklenmez. Hesap boşsa ev sahibi hesabına yazılır. Devir tarihini uygulamada seçersiniz.', '', '']);
    return rows;
  }
  rows.add(<String>['İlişki sözlüğü', '', '', '']);
  rows.add(<String>['İlişki', 'Kabul edilen sözcükler', '', '']);
  final words = spec.of(ImportKind.people)?.relationWords ?? spec.of(ImportKind.allInOne)?.relationWords ?? const <String, List<String>>{};
  final source = words.isEmpty ? _fallbackRelationWords : words;
  for (final entry in source.entries) {
    rows.add(<String>[_relationLabels[entry.key] ?? entry.key, entry.value.join(', '), '', '']);
  }
  rows.add(<String>['', '', '', '']);
  rows.add(<String>['Borç sorumlusu sözlüğü', '', '', '']);
  rows.add(<String>['Borç sorumlusu', 'Kabul edilen sözcükler', '', '']);
  final responsible = spec.of(ImportKind.apartments)?.responsibleWords ?? spec.of(ImportKind.allInOne)?.responsibleWords ?? const <String, List<String>>{};
  for (final entry in (responsible.isEmpty ? _fallbackResponsibleWords : responsible).entries) {
    rows.add(<String>[_responsibleLabels[entry.key] ?? entry.key, entry.value.join(', '), '', '']);
  }
  rows.add(<String>['', '', '', '']);
  rows.add(<String>[
    'Daire numarası',
    'Daire no\'yu «5», «05», «Daire 5» ya da «D5» biçiminde yazabilirsiniz. Daire sayısını artırmak için Site Yapısı ekranını kullanın.',
    '',
    '',
  ]);
  rows.add(<String>[
    'Plaka',
    'Bir hücreye en çok 5 plaka yazılır; virgül, noktalı virgül, / veya | ile ayırın.',
    '',
    '',
  ]);
  return rows;
}

/// Şablon dosyası.
///
/// [apartments]: sitenin mevcut daireleri (`exports/apartments` zarfı); null ise daire sayfası yalnız başlıktır.
RenderedFile buildImportTemplate({
  required ImportSpec spec,
  required ImportKind kind,
  required ExportFormat format,
  ExportEnvelope? apartments,
  String siteName = '',
}) {
  final kindSpec = spec.of(kind);
  if (kindSpec == null) throw ArgumentError('Şablonda ${kind.apiValue} türü yok.');
  final activeKindColumns = kindSpec.columns.where((c) => !kExcludedTemplateKeys.contains(c.key)).toList();
  if (format == ExportFormat.csv) {
    final rows = <List<String>>[
      <String>[for (final c in activeKindColumns) templateHeaderLabel(c)],
      if (_prefillsApartments(kind))
        for (final row in _prefilledRows(apartments, kindSpec, activeKindColumns))
          <String>[
            for (var i = 0; i < activeKindColumns.length; i++)
              row[i] == null
                  ? ''
                  : (row[i] is num ? formatPlainNumber(row[i]) : '${row[i]}'),
          ],
    ];
    return RenderedFile(
      bytes: csvBytes(rows),
      fileName: '${_fileBase}_${_asciiName(kind)}.csv',
      mimeType: ExportFormat.csv.mimeType,
      format: ExportFormat.csv,
    );
  }
  final order = <ImportKind>[kind, ..._groupOf(kind).where((k) => k != kind)];
  final sheets = <XlsxSheet>[];
  for (final k in order) {
    final s = spec.of(k);
    if (s == null) continue;
    final activeCols = s.columns.where((c) => !kExcludedTemplateKeys.contains(c.key)).toList();
    sheets.add(
      XlsxSheet(
        name: k.sheetName,
        columns: <XlsxColumn>[for (final c in activeCols) _templateColumn(c)],
        rows: _prefillsApartments(k) ? _prefilledRows(apartments, s, activeCols) : const <List<Object?>>[],
      ),
    );
  }
  sheets.add(
    XlsxSheet(
      name: 'Açıklama',
      freezeHeader: false,
      columns: const <XlsxColumn>[
        XlsxColumn('Bilgi', format: XlsxFormat.wrap, width: 26),
        XlsxColumn('Ayrıntı', format: XlsxFormat.wrap, width: 52),
        XlsxColumn('Kural', format: XlsxFormat.wrap, width: 52),
        XlsxColumn('Örnek', format: XlsxFormat.wrap, width: 26),
      ],
      rows: _explanationRows(spec, siteName: siteName, group: _groupOf(kind)),
    ),
  );
  return RenderedFile(
    bytes: buildXlsx(sheets),
    fileName: '$_fileBase.xlsx',
    mimeType: ExportFormat.xlsx.mimeType,
    format: ExportFormat.xlsx,
  );
}

String _asciiName(ImportKind kind) => switch (kind) {
  ImportKind.apartments => 'daireler',
  ImportKind.people => 'kisiler',
  ImportKind.vehicles => 'araclar',
  ImportKind.allInOne => 'hepsi_bir_arada',
  ImportKind.openingBalances => 'devir_bakiyesi',
};
