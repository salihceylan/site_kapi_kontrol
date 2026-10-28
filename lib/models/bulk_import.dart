// Toplu yükleme ve dışa aktarma modelleri (Platform Faz 2b; sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md).
//
// Sunucu yanıtları savunmacı çözülür: eksik / tipi yanlış alan çökmeye değil varsayılana düşer, ama yapısal
// olarak bozuk bir yanıt (kinds yok, columns/rows eşleşmiyor) [FormatException] fırlatır ve çağıran bunu
// "yanıt okunamadı" olarak gösterir (yanlış "boş" sonuç üretilmez).
import 'package:flutter/foundation.dart';

/// Yükleme türü (`:kind`).
enum ImportKind {
  apartments('apartments', 'Daireler', 'Daireler'),
  people('people', 'Kişiler', 'Kişiler'),
  vehicles('vehicles', 'Araçlar', 'Araçlar'),
  // Dalga 2 (N6 / F4): sona eklenir (sıra numaraları ve tab indeksleri değişmesin).
  allInOne('all_in_one', 'Hepsi bir arada', 'Hepsi bir arada'),
  openingBalances('opening_balances', 'Devir bakiyesi', 'Devir bakiyesi');

  const ImportKind(this.apiValue, this.label, this.sheetName);

  /// URL parçası ve zarftaki `kind`.
  final String apiValue;

  /// Kullanıcıya gösterilen ad.
  final String label;

  /// Şablondaki / dosyadaki sayfa adı.
  final String sheetName;

  /// Kişi verisi işlenir: KVKK onayı (`acknowledged`) zorunlu (sözleşme Karar 19).
  bool get needsAcknowledgement => this != ImportKind.apartments && this != ImportKind.openingBalances;

  /// Devir bakiyesi: devir tarihi (`options.cutover_date`) ve onayda toplam tutar (`options.expected_total_minor`) gerekir.
  bool get isOpening => this == ImportKind.openingBalances;

  /// Daire ilişkisi eklenen kişilere kullanıcı hesabı açılan türler: önizleme tablosunda «Kullanıcı Adı» sütunu vardır.
  bool get createsAccounts => this == ImportKind.people || this == ImportKind.allInOne;

  /// `allow_overwrite` yalnız dairelerde geçerlidir.
  bool get supportsOverwrite => this == ImportKind.apartments || this == ImportKind.allInOne;

  static ImportKind? tryParse(Object? value) {
    if (value is! String) return null;
    for (final kind in values) {
      if (kind.apiValue == value.trim()) return kind;
    }
    return null;
  }
}

/// Spec sütun tipi.
enum ImportColumnType {
  text,
  number,
  date,
  enumeration;

  static ImportColumnType parse(Object? value) {
    switch (value) {
      case 'number':
        return ImportColumnType.number;
      case 'date':
        return ImportColumnType.date;
      case 'enum':
        return ImportColumnType.enumeration;
    }
    return ImportColumnType.text;
  }
}

/// `GET imports/spec` içindeki bir sütun.
@immutable
class ImportColumn {
  const ImportColumn({
    required this.key,
    required this.label,
    this.required = false,
    this.type = ImportColumnType.text,
    this.maxLength,
    this.aliases = const <String>[],
    this.hint,
    this.choices = const <String>[],
  });

  factory ImportColumn.fromJson(Map<String, dynamic> json) {
    final key = _string(json['key']);
    if (key == null || key.isEmpty) {
      throw const FormatException('Şablon sütununda anahtar yok.');
    }
    final aliases = json['aliases'];
    return ImportColumn(
      key: key,
      label: _string(json['label']) ?? key,
      required: json['required'] == true,
      type: ImportColumnType.parse(json['type']),
      maxLength: _int(json['max_length']),
      aliases: aliases is List
          ? <String>[
              for (final item in aliases)
                if (item is String && item.trim().isNotEmpty) item,
            ]
          : const <String>[],
      hint: _string(json['hint']),
      choices: _stringList(json['choices']),
    );
  }

  final String key;
  final String label;
  final bool required;
  final ImportColumnType type;
  final int? maxLength;
  final List<String> aliases;
  final String? hint;

  /// Seçim listesi sütunlarında (İlişki, Borç Sorumlusu, Hesap) izin verilen etiketler: şablonda Excel açılır listesi, önizleme tablosunda açılır
  /// liste olur. Eski sunucu göndermezse boştur (istemci yedek sözlüğünü kullanır; bkz. bulk_choices.dart).
  final List<String> choices;
}

/// Bir türün sütun şeması.
@immutable
class ImportKindSpec {
  const ImportKindSpec({
    required this.columns,
    this.relationWords = const <String, List<String>>{},
    this.responsibleWords = const <String, List<String>>{},
  });

  factory ImportKindSpec.fromJson(Map<String, dynamic> json) {
    final raw = json['columns'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Şablonda sütun yok.');
    }
    final columns = <ImportColumn>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is Map) {
        final column = ImportColumn.fromJson(Map<String, dynamic>.from(item));
        if (seen.add(column.key)) columns.add(column);
      }
    }
    if (columns.isEmpty) throw const FormatException('Şablonda sütun yok.');
    return ImportKindSpec(
      columns: List<ImportColumn>.unmodifiable(columns),
      relationWords: _relationWords(json['relation_words']),
      responsibleWords: _relationWords(json['responsible_words']),
    );
  }

  final List<ImportColumn> columns;

  /// Kanonik ilişki -> kabul edilen sözcükler (şablondaki "Açıklama" sayfası için). Biçim bilinmiyorsa boş.
  final Map<String, List<String>> relationWords;

  /// Kanonik borç sorumlusu (owner | tenant | both) -> kabul edilen sözcükler (yalnız daireler).
  final Map<String, List<String>> responsibleWords;

  ImportColumn? column(String key) {
    for (final column in columns) {
      if (column.key == key) return column;
    }
    return null;
  }

  List<ImportColumn> get requiredColumns => <ImportColumn>[
    for (final column in columns)
      if (column.required) column,
  ];
}

Map<String, List<String>> _relationWords(Object? raw) {
  if (raw is! Map) return const <String, List<String>>{};
  final out = <String, List<String>>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String) continue;
    if (value is List) {
      out[key] = <String>[
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    } else if (value is String && value.trim().isNotEmpty) {
      // {"malik": "owner"} biçimi: kanonik değer anahtar olur.
      out.putIfAbsent(value.trim(), () => <String>[]).add(key);
    }
  }
  return out;
}

/// `GET /manager/sites/:siteCode/imports/spec`.
@immutable
class ImportSpec {
  const ImportSpec({
    required this.specVersion,
    required this.kinds,
    this.maxRows = defaultMaxRows,
    this.maxBodyBytes = defaultMaxBodyBytes,
  });

  factory ImportSpec.fromJson(Map<String, dynamic> json) {
    final version = _int(json['spec_version']);
    if (version == null) throw const FormatException('Şablon sürümü yok.');
    final rawKinds = json['kinds'];
    if (rawKinds is! Map) throw const FormatException('Şablon türleri yok.');
    final kinds = <ImportKind, ImportKindSpec>{};
    for (final entry in rawKinds.entries) {
      final kind = ImportKind.tryParse(entry.key);
      final value = entry.value;
      if (kind == null || value is! Map) continue;
      kinds[kind] = ImportKindSpec.fromJson(Map<String, dynamic>.from(value));
    }
    if (kinds.isEmpty) throw const FormatException('Şablon türleri yok.');
    final maxRows = _int(json['max_rows']);
    final maxBody = _int(json['max_body_bytes']);
    return ImportSpec(
      specVersion: version,
      kinds: Map<ImportKind, ImportKindSpec>.unmodifiable(kinds),
      maxRows: maxRows != null && maxRows > 0 && maxRows <= defaultMaxRows ? maxRows : defaultMaxRows,
      maxBodyBytes: maxBody != null && maxBody > 0 ? maxBody : defaultMaxBodyBytes,
    );
  }

  static const int defaultMaxRows = 5000;
  static const int defaultMaxBodyBytes = 5 * 1024 * 1024;

  /// İstemcinin anladığı spec sürümü. Sunucu farklı sürüm isterse 409 `IMPORT_SPEC_MISMATCH` döner.
  static const int supportedVersion = 1;

  final int specVersion;
  final Map<ImportKind, ImportKindSpec> kinds;
  final int maxRows;
  final int maxBodyBytes;

  ImportKindSpec? of(ImportKind kind) => kinds[kind];
}

/// Dosyadan okunan, sunucuya gidecek tek satır. [n] = dosyadaki (Excel'de görünen) satır numarası.
@immutable
class ImportRow {
  const ImportRow({required this.n, required this.cells});

  final int n;

  /// Anahtar = spec anahtarı; değer = kırpılmış metin | sonlu sayı | null.
  final Map<String, Object?> cells;

  Map<String, Object?> toJson() => <String, Object?>{'n': n, 'cells': cells};
}

/// Önizleme / yükleme satır sorunu.
@immutable
class ImportIssue {
  const ImportIssue({
    required this.n,
    required this.severity,
    required this.code,
    required this.message,
    this.field,
  });

  factory ImportIssue.fromJson(Map<String, dynamic> json) => ImportIssue(
    n: _int(json['n']) ?? 0,
    severity: json['severity'] == 'warning' ? ImportSeverity.warning : ImportSeverity.error,
    field: _string(json['field']),
    code: _string(json['code']) ?? '',
    message: _string(json['message']) ?? '',
  );

  final int n;
  final ImportSeverity severity;
  final String? field;
  final String code;
  final String message;

  bool get isError => severity == ImportSeverity.error;
}

enum ImportSeverity { error, warning }

@immutable
class ImportTotals {
  const ImportTotals({
    this.rows = 0,
    this.ok = 0,
    this.unchanged = 0,
    this.error = 0,
    this.withWarnings = 0,
  });

  factory ImportTotals.fromJson(Object? raw) {
    final json = raw is Map ? raw : const <String, dynamic>{};
    return ImportTotals(
      rows: _int(json['rows']) ?? 0,
      ok: _int(json['ok']) ?? 0,
      unchanged: _int(json['unchanged']) ?? 0,
      error: _int(json['error']) ?? 0,
      withWarnings: _int(json['with_warnings']) ?? 0,
    );
  }

  final int rows;
  final int ok;
  final int unchanged;
  final int error;
  final int withWarnings;
}

@immutable
class ImportSample {
  const ImportSample({required this.n, required this.action, required this.summary});

  factory ImportSample.fromJson(Map<String, dynamic> json) => ImportSample(
    n: _int(json['n']) ?? 0,
    action: _string(json['action']) ?? '',
    summary: _string(json['summary']) ?? '',
  );

  final int n;
  final String action;
  final String summary;
}

/// Arsa payı toplam denetimi (`checks.land_share`). Biçim sözleşmede kesin tanımlı değildir; olası alanlar
/// savunmacı okunur ve engellemeyen bir bilgi satırı üretir.
@immutable
class LandShareCheck {
  const LandShareCheck({required this.message, required this.complete});

  /// Sunucunun gönderdiği ya da alanlardan kurulan metin ("1000/1000 ✓" / "987/1000: eksik olabilir").
  final String message;

  /// Toplam paydaya eşit mi (uyarı tonu için).
  final bool complete;

  static LandShareCheck? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      final text = raw.trim();
      return text.isEmpty ? null : LandShareCheck(message: text, complete: text.contains('✓'));
    }
    if (raw is! Map) return null;
    final sum = _int(raw['sum'] ?? raw['total'] ?? raw['pay_total'] ?? raw['sum_pay']);
    final denominator = _int(raw['denominator'] ?? raw['payda'] ?? raw['common_denominator']);
    final okFlag = raw['ok'] ?? raw['complete'] ?? raw['balanced'];
    final text = _string(raw['message']) ?? _string(raw['summary']);
    var complete = okFlag is bool ? okFlag : (sum != null && denominator != null && sum == denominator);
    String message;
    if (text != null) {
      message = text;
    } else if (sum != null && denominator != null) {
      complete = okFlag is bool ? okFlag : sum == denominator;
      message = complete ? '$sum/$denominator ✓' : '$sum/$denominator: eksik olabilir';
    } else {
      return null;
    }
    return LandShareCheck(message: message, complete: complete);
  }
}

/// Bir satırdan açılacak hesabın durumu.
enum AccountProposalStatus {
  /// Yeni hesap açılır; kullanıcı adını sistem seçmiştir, yönetici değiştirebilir.
  create,

  /// Kişi (ya da e-postası) mevcut bir hesaba ait: o hesaba bağlanır, kullanıcı adı SALT OKUNUR.
  existing,

  /// E-posta başka bir hesaba ait ve bağlanamaz: kişi yazılır, hesap AÇILMAZ.
  emailInUse,

  /// Aynı kişi dosyada başka bir satırda da var: tek hesap, ad ilk satırdadır (salt okunur).
  shared,

  /// Ad üretilemedi (beklenmeyen): hesap açılırken sunucu yedek ad verir.
  unavailable,

  /// Yöneticinin seçtiği ad sunucuca REDDEDİLDİ (geçersiz / bu sitede kayıtlı / dosyada tekrar): [AccountProposal.message] nedeni söyler; satır yazılmaz.
  rejected;

  static AccountProposalStatus parse(Object? value) => switch (value) {
    'new' => AccountProposalStatus.create,
    'existing' => AccountProposalStatus.existing,
    'email_in_use' => AccountProposalStatus.emailInUse,
    'shared' => AccountProposalStatus.shared,
    'rejected' => AccountProposalStatus.rejected,
    _ => AccountProposalStatus.unavailable,
  };
}

/// Önizleme tablosundaki «Kullanıcı Adı» hücresi: satır numarası + sistemin seçtiği (ya da yöneticinin verdiği) ad.
/// `POST imports/:kind/accounts` ve önizleme yanıtının `accounts` dizisi aynı biçimdedir.
@immutable
class AccountProposal {
  const AccountProposal({
    required this.n,
    required this.status,
    this.loginName,
    this.editable = false,
    this.custom = false,
    this.line,
    this.message,
  });

  factory AccountProposal.fromJson(Map<String, dynamic> json) => AccountProposal(
    n: _int(json['n']) ?? 0,
    status: AccountProposalStatus.parse(json['status']),
    loginName: _string(json['login_name']),
    editable: json['editable'] == true,
    custom: json['custom'] == true,
    line: _int(json['line']),
    message: _string(json['message']),
  );

  static List<AccountProposal> listFrom(Object? raw) {
    if (raw is! List) return const <AccountProposal>[];
    return List<AccountProposal>.unmodifiable(<AccountProposal>[
      for (final item in raw)
        if (item is Map) AccountProposal.fromJson(Map<String, dynamic>.from(item)),
    ]);
  }

  final int n;
  final AccountProposalStatus status;
  final String? loginName;

  /// Yönetici adı değiştirebilir (yalnız yeni hesaplarda).
  final bool editable;

  /// Ad yöneticinin seçtiği ad (sistem önerisi değil).
  final bool custom;

  /// `shared`: adı taşıyan ilk satır.
  final int? line;

  /// `rejected`: reddedilme nedeni (sunucu metni).
  final String? message;
}

/// `POST imports/login-names/check` yanıtı: yöneticinin yazdığı adın biçimi ve bu sitedeki kullanılabilirliği.
@immutable
class LoginNameCheck {
  const LoginNameCheck({required this.ok, required this.code, this.loginName, this.message, this.suggestion});

  factory LoginNameCheck.fromJson(Map<String, dynamic> json) => LoginNameCheck(
    ok: json['ok'] == true,
    code: _string(json['code']) ?? (json['ok'] == true ? 'OK' : 'INVALID'),
    loginName: _string(json['login_name']),
    message: _string(json['message']),
    suggestion: _string(json['suggestion']),
  );

  final bool ok;

  /// `OK`, `EMPTY`, `TOO_SHORT`, `TOO_LONG`, `CHARS`, `TAKEN`.
  final String code;

  /// Sunucunun normalleştirdiği ad (küçük harf, Türkçe harfler sadeleşmiş).
  final String? loginName;
  final String? message;

  /// Ad alınmışsa aynı tabandan ilk boş ad.
  final String? suggestion;
}

/// Mali kaydı olan dairelerde mali alan değişikliği özeti (`checks.finance_records`): satır uyarısı değil, önizlemede TEK bilgi satırı.
/// Yüklemeyi engellemez.
@immutable
class FinanceRecordsCheck {
  const FinanceRecordsCheck({required this.apartments, required this.message});

  /// Mali alanı (Borç Sorumlusu / Tip / Arsa Payı) değişen ve mali kaydı olan daire sayısı.
  final int apartments;

  /// Sunucunun gönderdiği özet cümle.
  final String message;

  static FinanceRecordsCheck? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final count = _int(raw['apartments']);
    if (count == null || count <= 0) return null;
    final text = _string(raw['message']) ??
        '$count dairenin mali kaydı var; Borç Sorumlusu / Tip / Arsa Payı değişiklikleri mevcut borçları değiştirmez, '
            'yalnız sonraki borçlandırmadan itibaren geçerlidir.';
    return FinanceRecordsCheck(apartments: count, message: text);
  }
}

/// `POST imports/:kind/preview` yanıtı.
@immutable
class ImportPreview {
  const ImportPreview({
    required this.kind,
    required this.specVersion,
    required this.previewHash,
    required this.totals,
    this.plan = const <String, int>{},
    this.issues = const <ImportIssue>[],
    this.samples = const <ImportSample>[],
    this.landShare,
    this.financeRecords,
    this.accounts = const <AccountProposal>[],
    this.accountsProvided = false,
    this.issuesTruncated = false,
  });

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    final hash = _string(json['preview_hash']);
    if (hash == null || hash.isEmpty) throw const FormatException('Önizleme özeti yok.');
    final totals = json['totals'];
    if (totals is! Map) throw const FormatException('Önizleme toplamları yok.');
    final kind = ImportKind.tryParse(json['kind']);
    if (kind == null) throw const FormatException('Önizleme türü yok.');
    final checks = json['checks'];
    return ImportPreview(
      kind: kind,
      specVersion: _int(json['spec_version']) ?? ImportSpec.supportedVersion,
      previewHash: hash,
      totals: ImportTotals.fromJson(totals),
      plan: _intMap(json['plan']),
      issues: _issues(json['issues']),
      samples: _samples(json['samples']),
      landShare: checks is Map ? LandShareCheck.tryParse(checks['land_share']) : null,
      financeRecords: checks is Map ? FinanceRecordsCheck.tryParse(checks['finance_records']) : null,
      accounts: AccountProposal.listFrom(json['accounts']),
      accountsProvided: json['accounts'] is List,
      issuesTruncated: json['issues_truncated'] == true,
    );
  }

  final ImportKind kind;
  final int specVersion;
  final String previewHash;
  final ImportTotals totals;
  final Map<String, int> plan;
  final List<ImportIssue> issues;
  final List<ImportSample> samples;
  final LandShareCheck? landShare;

  /// Mali kaydı olan dairelerde mali alan değişikliği özeti (yoksa null). Engellemez.
  final FinanceRecordsCheck? financeRecords;

  /// Hesap açılacak / bağlanacak satırlar ve sistemin seçtiği kullanıcı adları (kişi türlerinde; diğerlerinde boş).
  final List<AccountProposal> accounts;

  /// Yanıtta `accounts` alanı vardı (eski sunucu göndermez: tablodaki öneriler korunur).
  final bool accountsProvided;

  /// Sunucu yanıtı sınırlı tutmak için sorun listesini kesti (hatalar önce korunur); tam liste yoktur.
  final bool issuesTruncated;

  int get errorCount => totals.error;
  int get warningRows => totals.withWarnings;

  /// Sunucu satırları kabul etti ama uygulanacak hiçbir şey yok.
  bool get nothingToApply => totals.ok <= 0;
}

/// Onay penceresi / çip satırı için (etiket, sayı) çifti.
@immutable
class ImportStat {
  const ImportStat(this.label, this.count);

  final String label;
  final int count;
}

/// Plan anahtarlarının Türkçe etiketleri (yalnız sayısı sıfırdan büyük olanlar gösterilir).
const Map<String, String> kImportPlanLabels = <String, String>{
  'people_create': 'Yeni kişi',
  'people_link': 'Mevcut kişiye bağlanan',
  'people_reactivate': 'Yeniden etkinleştirilen kişi',
  'people_filled': 'Boş alanları doldurulan kişi',
  'residency_add': 'Eklenecek daire ilişkisi',
  'residency_upgrade': 'Türü güncellenecek ilişki',
  'residency_unchanged': 'Değişmeyen ilişki',
  'account_create': 'Hesap açılacak kişi',
  'vehicle_add': 'Eklenecek araç',
  'vehicle_unchanged': 'Değişmeyen araç',
  'apartment_update': 'Güncellenecek daire',
  'cells_set': 'Doldurulacak alan',
  'overwritten_cells': 'Üzerine yazılacak alan',
  'cells_kept': 'Farklı olduğu için korunan alan',
  'opening_add': 'Yazılacak devir kaydı',
  'opening_unchanged': 'Zaten yüklü devir kaydı',
  'opening_zero': 'Tutarı 0 olduğu için atlanan',
};

extension ImportPreviewStats on ImportPreview {
  /// Plan sayıları (sıfır olanlar atlanır; sözleşme sırası korunur).
  List<ImportStat> planStats() => <ImportStat>[
    for (final entry in kImportPlanLabels.entries)
      if ((plan[entry.key] ?? 0) > 0) ImportStat(entry.value, plan[entry.key]!),
  ];

  /// Önizleme çipleri: Eklenecek / Bağlanacak / Değişmeyecek / Hatalı / Uyarılı (türe göre anlamlı olanlar).
  List<ImportStat> chips() {
    switch (kind) {
      case ImportKind.apartments:
        return <ImportStat>[
          ImportStat('Güncellenecek', plan['apartment_update'] ?? totals.ok),
          ImportStat('Değişmeyecek', totals.unchanged),
          ImportStat('Hatalı', totals.error),
          ImportStat('Uyarılı', totals.withWarnings),
        ];
      case ImportKind.people:
        return <ImportStat>[
          ImportStat('Eklenecek', plan['people_create'] ?? 0),
          ImportStat('Bağlanacak', (plan['people_link'] ?? 0) + (plan['people_reactivate'] ?? 0)),
          ImportStat('Değişmeyecek', totals.unchanged),
          ImportStat('Hatalı', totals.error),
          ImportStat('Uyarılı', totals.withWarnings),
        ];
      case ImportKind.allInOne:
        return <ImportStat>[
          ImportStat('Eklenecek kişi', plan['people_create'] ?? 0),
          ImportStat('Güncellenecek daire', plan['apartment_update'] ?? 0),
          ImportStat('Değişmeyecek', totals.unchanged),
          ImportStat('Hatalı', totals.error),
          ImportStat('Uyarılı', totals.withWarnings),
        ];
      case ImportKind.openingBalances:
        return <ImportStat>[
          ImportStat('Yazılacak', plan['opening_add'] ?? totals.ok),
          ImportStat('Değişmeyecek', totals.unchanged),
          ImportStat('Hatalı', totals.error),
          ImportStat('Uyarılı', totals.withWarnings),
        ];
      case ImportKind.vehicles:
        return <ImportStat>[
          ImportStat('Eklenecek', plan['vehicle_add'] ?? totals.ok),
          ImportStat('Değişmeyecek', plan['vehicle_unchanged'] ?? totals.unchanged),
          ImportStat('Hatalı', totals.error),
          ImportStat('Uyarılı', totals.withWarnings),
        ];
    }
  }
}

/// 409 `PREVIEW_STALE` yanıtındaki güncel özet.
@immutable
class ImportStaleInfo {
  const ImportStaleInfo({this.previewHash, this.totals, this.plan = const <String, int>{}});

  factory ImportStaleInfo.fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return const ImportStaleInfo();
    return ImportStaleInfo(
      previewHash: _string(payload['preview_hash']),
      totals: payload['totals'] is Map ? ImportTotals.fromJson(payload['totals']) : null,
      plan: _intMap(payload['plan']),
    );
  }

  final String? previewHash;
  final ImportTotals? totals;
  final Map<String, int> plan;
}

/// `POST imports/:kind/commit` yanıtı (201 ya da replay 200).
@immutable
class ImportResult {
  const ImportResult({
    required this.replayed,
    required this.runId,
    required this.kind,
    required this.rowCount,
    required this.applied,
    required this.unchanged,
    required this.skipped,
    this.createdAt,
    this.counts = const <String, int>{},
    this.issues,
    this.issuesTruncated = false,
    this.accounts,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    final run = json['run'];
    final result = json['result'];
    if (run is! Map || result is! Map) throw const FormatException('Yükleme sonucu okunamadı.');
    final rows = result['rows'];
    final rowMap = rows is Map ? rows : const <String, dynamic>{};
    final rawIssues = result['issues'];
    return ImportResult(
      replayed: json['replayed'] == true,
      runId: _int(run['id']),
      kind: ImportKind.tryParse(run['kind']),
      rowCount: _int(run['row_count']) ?? 0,
      createdAt: DateTime.tryParse(_string(run['created_at']) ?? ''),
      applied: _int(rowMap['applied']) ?? 0,
      unchanged: _int(rowMap['unchanged']) ?? 0,
      skipped: _int(rowMap['skipped']) ?? 0,
      counts: _intMap(result['counts']),
      // `issues: null` = tekrar oynatma (satır ayrıntısı saklanmadı); boş liste = sorun yok.
      issues: rawIssues is List ? _issues(rawIssues) : null,
      issuesTruncated: result['issues_truncated'] == true,
      accounts: result['accounts'] is Map
          ? ImportAccountsResult.fromJson(Map<String, dynamic>.from(result['accounts'] as Map))
          : null,
    );
  }

  final bool replayed;
  final int? runId;
  final ImportKind? kind;
  final int rowCount;
  final DateTime? createdAt;
  final int applied;
  final int unchanged;
  final int skipped;
  final Map<String, int> counts;

  /// null: ayrıntı yok (replay).
  final List<ImportIssue>? issues;

  /// Sorun listesi kesildi.
  final bool issuesTruncated;

  /// Açılan / bağlanan kullanıcı hesapları (kişi yüklemelerinde; tekrar oynatmada ve diğer türlerde null).
  final ImportAccountsResult? accounts;
}

/// Toplu yüklemede açılan / bağlanan hesaplar: satır numarası + sunucunun verdiği NİHAİ kullanıcı adı.
@immutable
class ImportAccountsResult {
  const ImportAccountsResult({
    this.created = 0,
    this.linked = 0,
    this.skipped = 0,
    this.renamed = 0,
    this.items = const <ImportAccountItem>[],
    this.skippedItems = const <ImportAccountSkip>[],
  });

  factory ImportAccountsResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawSkipped = json['skipped_items'];
    return ImportAccountsResult(
      created: _int(json['created']) ?? 0,
      linked: _int(json['linked']) ?? 0,
      skipped: _int(json['skipped']) ?? 0,
      renamed: _int(json['renamed']) ?? 0,
      items: <ImportAccountItem>[
        if (rawItems is List)
          for (final item in rawItems)
            if (item is Map && _string(item['login_name']) != null)
              ImportAccountItem(
                n: _int(item['n']),
                loginName: _string(item['login_name'])!,
                linked: item['status'] == 'linked',
                requestedLoginName: _string(item['requested_login_name']),
              ),
      ],
      skippedItems: <ImportAccountSkip>[
        if (rawSkipped is List)
          for (final item in rawSkipped)
            if (item is Map)
              ImportAccountSkip(
                n: _int(item['n']),
                code: _string(item['code']) ?? '',
                message: _string(item['message']) ?? 'Hesap açılmadı.',
              ),
      ],
    );
  }

  /// Yeni açılan hesap sayısı.
  final int created;

  /// Sitede zaten bağı olan mevcut hesaba bağlanan kişi sayısı.
  final int linked;

  /// Hesabı açılamayan kişi sayısı (kişi kaydı yapıldı; hesap kişi kartından açılabilir).
  final int skipped;

  /// Önizlemede gösterilen kullanıcı adı yazım anında başkasına geçtiği için başka ad verilen hesap sayısı (nadir yarış).
  final int renamed;
  final List<ImportAccountItem> items;
  final List<ImportAccountSkip> skippedItems;

  bool get isEmpty => created == 0 && linked == 0 && skipped == 0;
}

/// Açılan / bağlanan tek hesap: dosyadaki satır no ve sunucudaki NİHAİ kullanıcı adı (çakışmada `_2` eki olabilir).
@immutable
class ImportAccountItem {
  const ImportAccountItem({required this.n, required this.loginName, this.linked = false, this.requestedLoginName});

  final int? n;
  final String loginName;

  /// Önizlemede gösterilen ad (yazım anında başkası aldıysa [loginName]'den farklıdır); yoksa null.
  final String? requestedLoginName;

  /// true: mevcut hesaba bağlandı (yeni hesap açılmadı, şifre değişmedi).
  final bool linked;
}

/// Hesabı açılmayan kişi: satır no, kod ve kullanıcıya gösterilecek neden.
@immutable
class ImportAccountSkip {
  const ImportAccountSkip({required this.n, required this.code, required this.message});

  final int? n;
  final String code;
  final String message;
}

// --- Dışa aktarma ------------------------------------------------------------------------------

/// Dosya biçimi (`format` yalnız denetim kaydı içindir; dosyayı istemci üretir).
enum ExportFormat {
  xlsx('xlsx', 'Excel (.xlsx)', 'xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  csv('csv', 'CSV (Excel uyumlu)', 'csv', 'text/csv');

  const ExportFormat(this.apiValue, this.label, this.extension, this.mimeType);

  final String apiValue;
  final String label;
  final String extension;
  final String mimeType;
}

/// Zarf sütun tipi.
enum ExportColumnType {
  text,
  number,
  date,

  /// TAMSAYI KURUŞ; çıktıda yalnız tamsayı/metin aritmetiğiyle 2 ondalık (kayan nokta YOK).
  money;

  static ExportColumnType parse(Object? value) {
    switch (value) {
      case 'number':
        return ExportColumnType.number;
      case 'date':
        return ExportColumnType.date;
      case 'money':
        return ExportColumnType.money;
    }
    return ExportColumnType.text;
  }
}

@immutable
class ExportColumn {
  const ExportColumn({
    required this.key,
    required this.label,
    this.type = ExportColumnType.text,
    this.scale,
  });

  factory ExportColumn.fromJson(Map<String, dynamic> json) {
    final label = _string(json['label']);
    final key = _string(json['key']) ?? label;
    if (key == null || label == null) throw const FormatException('Dışa aktarma sütunu eksik.');
    final scale = _int(json['scale']);
    return ExportColumn(
      key: key,
      label: label,
      type: ExportColumnType.parse(json['type']),
      scale: scale != null && scale >= 0 && scale <= 8 ? scale : null,
    );
  }

  final String key;
  final String label;
  final ExportColumnType type;

  /// `number` için ondalık basamak sayısı.
  final int? scale;
}

/// `GET exports/:kind` zarfı. Faz 4b aynı zarfı yeni `kind` değerleriyle kullanır; bu yüzden [kind] serbest
/// metindir (yalnız [ImportKind] değerleriyle sınırlı değildir).
@immutable
class ExportEnvelope {
  const ExportEnvelope({
    required this.kind,
    required this.filenameBase,
    required this.columns,
    required this.rows,
    this.specVersion = 1,
    this.generatedAt,
  });

  factory ExportEnvelope.fromJson(Map<String, dynamic> json) {
    final rawColumns = json['columns'];
    final rawRows = json['rows'];
    if (rawColumns is! List || rawColumns.isEmpty) {
      throw const FormatException('Dışa aktarma sütunları yok.');
    }
    if (rawRows is! List) throw const FormatException('Dışa aktarma satırları yok.');
    final columns = <ExportColumn>[
      for (final item in rawColumns)
        if (item is Map)
          ExportColumn.fromJson(Map<String, dynamic>.from(item))
        else
          throw const FormatException('Dışa aktarma sütunu bozuk.'),
    ];
    final rows = <List<Object?>>[];
    for (final item in rawRows) {
      if (item is! List || item.length != columns.length) {
        throw const FormatException('Dışa aktarma satırı sütunlarla uyuşmuyor.');
      }
      rows.add(List<Object?>.unmodifiable(item));
    }
    final declared = _int(json['row_count']);
    if (declared != null && declared != rows.length) {
      throw const FormatException('Dışa aktarma satır sayısı uyuşmuyor.');
    }
    return ExportEnvelope(
      kind: _string(json['kind']) ?? '',
      specVersion: _int(json['spec_version']) ?? 1,
      generatedAt: DateTime.tryParse(_string(json['generated_at']) ?? ''),
      filenameBase: _string(json['filename_base']) ?? 'dışa-aktarma',
      columns: List<ExportColumn>.unmodifiable(columns),
      rows: List<List<Object?>>.unmodifiable(rows),
    );
  }

  final String kind;
  final int specVersion;
  final DateTime? generatedAt;
  final String filenameBase;
  final List<ExportColumn> columns;
  final List<List<Object?>> rows;

  int get rowCount => rows.length;
}

/// Dışa aktarma süzgeçleri (liste uçlarıyla AYNI adlar). Yalnız dolu olanlar sorguya gider.
@immutable
class BulkExportFilters {
  const BulkExportFilters({
    this.query,
    this.status,
    this.relation,
    this.apartmentId,
    this.blockId,
    this.personId,
  });

  /// Arama metni (sunucuya `q` olarak gider; denetime YAZILMAZ, yalnız `has_q`).
  final String? query;

  /// `active|inactive|all`.
  final String? status;

  /// İlişki `apiValue`.
  final String? relation;
  final int? apartmentId;
  final int? blockId;
  final int? personId;

  bool get isEmpty =>
      (query ?? '').isEmpty &&
      (status == null || status == 'active') &&
      relation == null &&
      apartmentId == null &&
      blockId == null &&
      personId == null;

  Map<String, String> toQuery() => <String, String>{
    if ((query ?? '').trim().isNotEmpty) 'q': query!.trim(),
    if (status != null && status!.isNotEmpty) 'status': status!,
    if (relation != null && relation!.isNotEmpty) 'relation': relation!,
    if (apartmentId != null) 'apartment_id': '$apartmentId',
    if (blockId != null) 'block_id': '$blockId',
    if (personId != null) 'person_id': '$personId',
  };

  /// "Aktif kişiler, Malik, arama: «ahmet»" gibi okunur özet; hiç süzgeç yoksa "Tüm kayıtlar".
  String summary({required ImportKind kind, String? relationLabel, String? blockLabel}) {
    final parts = <String>[];
    if (kind == ImportKind.people) {
      switch (status) {
        case 'inactive':
          parts.add('Eski sakinler');
        case 'all':
          parts.add('Aktif ve eski kişiler');
        default:
          parts.add('Aktif kişiler');
      }
      if (relation != null) parts.add(relationLabel ?? relation!);
    }
    if (blockId != null) parts.add(blockLabel ?? 'Seçili blok');
    final q = (query ?? '').trim();
    if (q.isNotEmpty) parts.add('arama: «${q.length > 24 ? '${q.substring(0, 24)}…' : q}»');
    return parts.isEmpty ? 'Tüm kayıtlar' : parts.join(', ');
  }
}

// --- Ortak çözümleyiciler ---------------------------------------------------------------------

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return List<String>.unmodifiable(<String>[
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ]);
}

Map<String, int> _intMap(Object? raw) {
  if (raw is! Map) return const <String, int>{};
  final out = <String, int>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = _int(entry.value);
    if (key is String && value != null) out[key] = value;
  }
  return Map<String, int>.unmodifiable(out);
}

List<ImportIssue> _issues(Object? raw) {
  if (raw is! List) return const <ImportIssue>[];
  return List<ImportIssue>.unmodifiable(<ImportIssue>[
    for (final item in raw)
      if (item is Map) ImportIssue.fromJson(Map<String, dynamic>.from(item)),
  ]);
}

List<ImportSample> _samples(Object? raw) {
  if (raw is! List) return const <ImportSample>[];
  return List<ImportSample>.unmodifiable(<ImportSample>[
    for (final item in raw)
      if (item is Map) ImportSample.fromJson(Map<String, dynamic>.from(item)),
  ]);
}
