import 'package:flutter/foundation.dart';

// Kurallar tablosu (karar G11; docs/PLATFORM_KURALLAR.md): `GET /admin/rules`, `GET /manager/sites/:siteCode/rules`, `PUT /admin/rules`.
//
// Değerler sunucudan ham gelir (baz puan, yüzde, gün, boolean, null = süresiz); biçimleme ve giriş ayrıştırma burada TAM SAYI ile yapılır
// (kayan nokta yok). Yanıt savunmacı okunur: eksik ya da bozuk alan güvenli varsayılana düşer, liste öğesi nesne değilse atlanır.

/// Kural değerinin türü.
enum PlatformRuleType { integer, boolean }

/// Tam sayı kuralın birimi.
enum PlatformRuleUnit { basisPoints, percent, days, none }

/// Değerin geldiği yer: siteye özel değer, platform değeri ya da koddaki varsayılan.
enum PlatformRuleSource { site, platform, fallback }

Map<String, dynamic>? _map(Object? raw) => raw is Map<String, dynamic> ? raw : (raw is Map ? Map<String, dynamic>.from(raw) : null);

String _text(Object? raw) => raw is String ? raw : '';

String? _textOrNull(Object? raw) => raw is String && raw.trim().isNotEmpty ? raw : null;

int? _intOrNull(Object? raw) => raw is int ? raw : (raw is num && raw == raw.roundToDouble() ? raw.toInt() : null);

/// Kural değeri: yalnız tam sayı, boolean ya da null (metin / ondalık sayı değer sayılmaz).
Object? _ruleValue(Object? raw) => raw is bool ? raw : _intOrNull(raw);

PlatformRuleSource _sourceOf(Object? raw) => switch (raw) {
  'site' => PlatformRuleSource.site,
  'platform' => PlatformRuleSource.platform,
  _ => PlatformRuleSource.fallback,
};

PlatformRuleUnit _unitOf(Object? raw) => switch (raw) {
  'bp' => PlatformRuleUnit.basisPoints,
  'pct' => PlatformRuleUnit.percent,
  'days' => PlatformRuleUnit.days,
  _ => PlatformRuleUnit.none,
};

/// Bir kapsamdaki değer (platform, site ya da etkin).
@immutable
class PlatformRuleValue {
  const PlatformRuleValue({
    this.value,
    this.source = PlatformRuleSource.fallback,
    this.validFrom,
    this.note,
    this.updatedAt,
    this.updatedByName,
  });

  /// Tam sayı, boolean ya da null (süresiz / bilinmiyor).
  final Object? value;
  final PlatformRuleSource source;

  /// 'YYYY-MM-DD' (varsayılanda null).
  final String? validFrom;
  final String? note;
  final DateTime? updatedAt;

  /// Yalnız süper kullanıcı görünümünde dolu.
  final String? updatedByName;

  factory PlatformRuleValue.fromJson(Map<String, dynamic>? json, {PlatformRuleSource? source}) {
    final data = json ?? const <String, dynamic>{};
    final updated = data['updated_at'];
    return PlatformRuleValue(
      value: _ruleValue(data['value']),
      source: source ?? _sourceOf(data['source']),
      validFrom: _textOrNull(data['valid_from']),
      note: _textOrNull(data['note']),
      updatedAt: updated is String ? DateTime.tryParse(updated) : null,
      updatedByName: _textOrNull(data['updated_by_name']),
    );
  }
}

/// İleri tarihli (planlı) değer.
@immutable
class PlatformRuleScheduled {
  const PlatformRuleScheduled({required this.isSite, required this.value, required this.inherit, required this.validFrom, this.note});

  /// true: siteye özel planlı değer; false: platform değeri.
  final bool isSite;
  final Object? value;

  /// true: o tarihten itibaren üst düzeydeki değere dönülür.
  final bool inherit;
  final String validFrom;
  final String? note;

  static PlatformRuleScheduled? tryParse(Object? raw) {
    final data = _map(raw);
    final validFrom = _textOrNull(data?['valid_from']);
    if (data == null || validFrom == null) return null;
    return PlatformRuleScheduled(
      isSite: data['scope'] == 'site',
      value: _ruleValue(data['value']),
      inherit: data['inherit'] == true,
      validFrom: validFrom,
      note: _textOrNull(data['note']),
    );
  }
}

/// Toplamı sabit olması gereken kural çifti (ör. ısı payı %70 + %30 = 100).
@immutable
class PlatformRulePair {
  const PlatformRulePair({required this.key, required this.sum});

  final String key;
  final int sum;
}

/// Tek kural: meta + değerler.
@immutable
class PlatformRule {
  const PlatformRule({
    required this.key,
    required this.group,
    required this.label,
    this.description = '',
    this.type = PlatformRuleType.integer,
    this.unit = PlatformRuleUnit.none,
    this.nullable = false,
    this.min,
    this.max,
    this.defaultValue,
    this.siteOverridable = false,
    this.schedulable = true,
    this.editable = true,
    this.lockedReason,
    this.pair,
    this.legalNote = '',
    this.platform = const PlatformRuleValue(),
    this.site,
    this.effective = const PlatformRuleValue(),
    this.scheduled = const <PlatformRuleScheduled>[],
  });

  final String key;
  final String group;
  final String label;
  final String description;
  final PlatformRuleType type;
  final PlatformRuleUnit unit;

  /// true: null (süresiz) geçerli bir değerdir.
  final bool nullable;
  final int? min;
  final int? max;
  final Object? defaultValue;

  /// true: siteye özel değer verilebilir (çoğu kural yalnız platform genelidir).
  final bool siteOverridable;

  /// false: ileri tarihli planlanamaz, değişiklik bugünden geçerli olur.
  final bool schedulable;

  /// false: kilitli (ör. otomatik silme avukat onayına kadar).
  final bool editable;
  final String? lockedReason;
  final PlatformRulePair? pair;
  final String legalNote;
  final PlatformRuleValue platform;

  /// Siteye özel geçerli değer (site görünümünde ve varsa).
  final PlatformRuleValue? site;
  final PlatformRuleValue effective;
  final List<PlatformRuleScheduled> scheduled;

  bool get isInteger => type == PlatformRuleType.integer;

  /// Kural bu kapsamda değiştirilebilir mi (yetki ayrıca: yalnız süper kullanıcı).
  bool editableIn({required bool siteScope}) => editable && (!siteScope || siteOverridable);

  static PlatformRule? tryParse(Object? raw) {
    final data = _map(raw);
    final key = _textOrNull(data?['key']);
    if (data == null || key == null) return null;
    final pair = _map(data['pair']);
    final pairKey = _textOrNull(pair?['key']);
    final pairSum = _intOrNull(pair?['sum']);
    final site = _map(data['site']);
    final scheduled = data['scheduled'];
    return PlatformRule(
      key: key,
      group: _text(data['group']),
      label: _textOrNull(data['label']) ?? key,
      description: _text(data['description']),
      type: data['type'] == 'bool' ? PlatformRuleType.boolean : PlatformRuleType.integer,
      unit: _unitOf(data['unit']),
      nullable: data['nullable'] == true,
      min: _intOrNull(data['min']),
      max: _intOrNull(data['max']),
      defaultValue: _ruleValue(data['default']),
      siteOverridable: data['site_overridable'] == true,
      schedulable: data['schedulable'] != false,
      editable: data['editable'] != false,
      lockedReason: _textOrNull(data['locked_reason']),
      pair: pairKey != null && pairSum != null ? PlatformRulePair(key: pairKey, sum: pairSum) : null,
      legalNote: _text(data['legal_note']),
      platform: PlatformRuleValue.fromJson(_map(data['platform'])),
      site: site == null ? null : PlatformRuleValue.fromJson(site, source: PlatformRuleSource.site),
      effective: PlatformRuleValue.fromJson(_map(data['effective'])),
      scheduled: scheduled is List
          ? <PlatformRuleScheduled>[for (final entry in scheduled) ?PlatformRuleScheduled.tryParse(entry)]
          : const <PlatformRuleScheduled>[],
    );
  }
}

/// Kural grubu (ekrandaki bölüm).
@immutable
class PlatformRuleGroup {
  const PlatformRuleGroup({required this.code, required this.label});

  final String code;
  final String label;
}

/// Liste yanıtı (platform ya da site görünümü). Yazma yanıtı ayrıca [changed] taşır.
@immutable
class PlatformRulesView {
  const PlatformRulesView({
    required this.onDate,
    this.siteCode,
    this.siteName,
    this.canEdit = false,
    this.groups = const <PlatformRuleGroup>[],
    this.items = const <PlatformRule>[],
    this.changed = const <String>[],
  });

  /// Görünümün tarihi ('YYYY-MM-DD', İstanbul bugünü).
  final String onDate;
  final int? siteCode;
  final String? siteName;
  final bool canEdit;
  final List<PlatformRuleGroup> groups;
  final List<PlatformRule> items;

  /// Yazmada gerçekten değişen kural anahtarları (no-op değişiklikler yoktur).
  final List<String> changed;

  bool get isSiteScope => siteCode != null;

  PlatformRule? byKey(String key) {
    for (final item in items) {
      if (item.key == key) return item;
    }
    return null;
  }

  List<PlatformRule> itemsIn(String group) => <PlatformRule>[for (final item in items) if (item.group == group) item];

  factory PlatformRulesView.fromJson(Map<String, dynamic> json) {
    final site = _map(json['site']);
    final groups = json['groups'];
    final items = json['items'];
    final changed = json['changed'];
    return PlatformRulesView(
      onDate: _text(json['on_date']),
      siteCode: _intOrNull(site?['site_code']),
      siteName: _textOrNull(site?['site_name']),
      canEdit: json['can_edit'] == true,
      groups: groups is List
          ? <PlatformRuleGroup>[
              for (final entry in groups)
                if (_textOrNull(_map(entry)?['code']) case final code?)
                  PlatformRuleGroup(code: code, label: _textOrNull(_map(entry)?['label']) ?? code),
            ]
          : const <PlatformRuleGroup>[],
      items: items is List ? <PlatformRule>[for (final entry in items) ?PlatformRule.tryParse(entry)] : const <PlatformRule>[],
      changed: changed is List ? <String>[for (final entry in changed) if (entry is String) entry] : const <String>[],
    );
  }
}

/// Tek kural değişikliği (`PUT /admin/rules` gövdesindeki `changes[]` öğesi).
@immutable
class PlatformRuleChange {
  const PlatformRuleChange({required this.key, required this.value}) : inherit = false;

  /// "Üst düzeydeki değere dön" (site -> platform, platform -> varsayılan).
  const PlatformRuleChange.inherit(this.key) : value = null, inherit = true;

  final String key;
  final Object? value;
  final bool inherit;

  Map<String, Object?> toJson() => inherit ? <String, Object?>{'key': key, 'inherit': true} : <String, Object?>{'key': key, 'value': value};
}

// --- Biçimleme ---------------------------------------------------------------------------------------------------------------------------

String _grouped(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Baz puan -> "%5,00" (tam sayı aritmetiği).
String formatBasisPoints(int bp) => '%${_grouped(bp ~/ 100)},${(bp % 100).toString().padLeft(2, '0')}';

String _formatInteger(PlatformRule rule, int value) => switch (rule.unit) {
  PlatformRuleUnit.basisPoints => formatBasisPoints(value),
  PlatformRuleUnit.percent => '%$value',
  PlatformRuleUnit.days => value >= 365 && value % 365 == 0 ? '${_grouped(value)} gün (${value ~/ 365} yıl)' : '${_grouped(value)} gün',
  PlatformRuleUnit.none => _grouped(value),
};

/// Kural değerinin ekrandaki metni: "%5,00", "%70", "3.650 gün (10 yıl)", "Süresiz", "Açık" / "Kapalı"; anlamsız değer "-".
String formatRuleValue(PlatformRule rule, Object? value) {
  if (rule.type == PlatformRuleType.boolean) {
    return value is bool ? (value ? 'Açık' : 'Kapalı') : '-';
  }
  if (value == null) return rule.nullable ? 'Süresiz' : '-';
  return value is int ? _formatInteger(rule, value) : '-';
}

/// Sınır metni: "%0,00 ile %5,00 arasında", "30 ile 3.650 gün arasında"; boolean / sınırsız kuralda boş.
String formatRuleRange(PlatformRule rule) {
  final min = rule.min;
  final max = rule.max;
  if (!rule.isInteger || min == null || max == null) return '';
  return switch (rule.unit) {
    PlatformRuleUnit.basisPoints => '${formatBasisPoints(min)} ile ${formatBasisPoints(max)} arasında',
    PlatformRuleUnit.percent => '%$min ile %$max arasında',
    PlatformRuleUnit.days => '${_grouped(min)} ile ${_grouped(max)} gün arasında',
    PlatformRuleUnit.none => '${_grouped(min)} ile ${_grouped(max)} arasında',
  };
}

/// 'YYYY-MM-DD' -> 'GG.AA.YYYY'; yoksa ya da biçimsizse "-".
String formatRuleDate(String? iso) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso ?? '');
  if (match == null) return '-';
  return '${match.group(3)}.${match.group(2)}.${match.group(1)}';
}

/// Değerin kaynağı için ekrandaki etiket.
String ruleSourceLabel(PlatformRuleSource source) => switch (source) {
  PlatformRuleSource.site => 'Bu siteye özel',
  PlatformRuleSource.platform => 'Platform değeri',
  PlatformRuleSource.fallback => 'Varsayılan',
};

// --- Giriş -------------------------------------------------------------------------------------------------------------------------------

final RegExp _percentInput = RegExp(r'^(\d{1,3})(?:[.,](\d{1,2}))?$');
final RegExp _integerInput = RegExp(r'^\d{1,6}$');

/// Alan metni -> tam sayı değer (baz puan kuralında yüzde metni: "4,50" -> 450). Biçim bozuksa null; sınır ayrıca denetlenir.
int? parseRuleInput(PlatformRule rule, String text) {
  var value = text.trim();
  switch (rule.unit) {
    case PlatformRuleUnit.basisPoints:
      if (value.startsWith('%')) value = value.substring(1).trim();
      final match = _percentInput.firstMatch(value);
      if (match == null) return null;
      final whole = int.parse(match.group(1)!);
      final fraction = (match.group(2) ?? '').padRight(2, '0');
      return whole * 100 + int.parse(fraction);
    case PlatformRuleUnit.percent:
      if (value.startsWith('%')) value = value.substring(1).trim();
      return _integerInput.hasMatch(value) ? int.parse(value) : null;
    case PlatformRuleUnit.days:
    case PlatformRuleUnit.none:
      final compact = value.replaceAll('.', '').replaceAll(' ', '');
      return _integerInput.hasMatch(compact) ? int.parse(compact) : null;
  }
}

/// Alan doğrulaması (Türkçe); geçerliyse null.
String? validateRuleInput(PlatformRule rule, String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return 'Bir değer girin.';
  final parsed = parseRuleInput(rule, value);
  if (parsed == null) {
    return switch (rule.unit) {
      PlatformRuleUnit.basisPoints => 'Oranı yüzde olarak girin (örn. 4,50).',
      PlatformRuleUnit.percent => 'Yüzdeyi tam sayı olarak girin.',
      _ => 'Gün sayısını tam sayı olarak girin.',
    };
  }
  final min = rule.min;
  final max = rule.max;
  if ((min != null && parsed < min) || (max != null && parsed > max)) {
    return 'Değer ${formatRuleRange(rule)} olmalıdır.';
  }
  return null;
}

/// Alanın başlangıç metni (baz puan kuralında yüzde: 450 -> "4,50").
String ruleInputText(PlatformRule rule, Object? value) {
  if (value is! int) return '';
  return rule.unit == PlatformRuleUnit.basisPoints ? formatBasisPoints(value).substring(1).replaceAll('.', '') : '$value';
}

// --- Denetim kaydı -----------------------------------------------------------------------------------------------------------------------

/// Kural anahtarı -> ekrandaki ad (denetim kaydında; sunucu kayıt defteriyle aynı adlar).
const Map<String, String> kPlatformRuleLabels = <String, String>{
  'finance.late_fee.monthly_bp_max': 'Gecikme tazminatı aylık üst sınırı',
  'budget.provisional_max_days': 'Geçici işletme projesi en uzun süresi',
  'budget.objection_days': 'İşletme projesine itiraz süresi',
  'heat.measured_share_pct': 'Isınma gideri: ölçüme göre pay',
  'heat.area_share_pct': 'Isınma gideri: alana göre pay',
  'forecast.default_increase_bp': 'Gelecek yıl tahmini: varsayılan artış oranı',
  'retention.finance_days': 'Mali kayıtlar',
  'retention.contact_after_moveout_days': 'Taşınan kişinin iletişim bilgileri',
  'retention.door_logs_days': 'Kapı geçiş kayıtları',
  'retention.visitor_logs_days': 'Ziyaretçi ve kargo kayıtları',
  'retention.work_photos_after_close_days': 'İş takibi fotoğrafları (talep kapandıktan sonra)',
  'retention.announcements_days': 'Duyurular',
  'retention.audit_days': 'Denetim kaydı',
  'retention.residency_log_days': 'Daire sakini adli kaydı',
  'retention.decision_book_days': 'Karar defteri',
  'retention.enforce': 'Otomatik silme',
};

/// Denetim kaydı eylem etiketi (kural eylemi değilse null).
String? platformRuleActionLabel(String action) => action == 'platform_rule.updated' ? 'Kural değeri güncellendi' : null;

/// Denetim kaydı hedefi: "Kural adı • Platform geneli" / "Kural adı • Site"; bilinmeyen anahtar "Kural".
String platformRuleTargetLabel(String? key, Map<String, dynamic> details) {
  final name = kPlatformRuleLabels[key] ?? 'Kural';
  return details['scope'] == 'site' ? '$name • Site' : '$name • Platform geneli';
}
