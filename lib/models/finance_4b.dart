import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmDate, crmInt, crmIntOrNull, crmText;

/// Platform Faz 4b (Finans devamı) ortak model yardımcıları ve ayarlar (sözleşme: docs/PLATFORM_FINANS_4B.md).
///
/// Kurallar 4a ile aynıdır: PARA tamsayı KURUŞTUR; zorunlu tutar alanı okunamazsa [FormatException] fırlar
/// (sessiz 0 YOK, ekran "veri işlenemedi" der, asla uydurma "0 / yok" göstermez). Bilinmeyen sayım değerleri
/// güvenli varsayılana düşer.

/// Zorunlu kuruş alanı: okunamazsa [FormatException].
int f4Minor(Map<String, dynamic> json, String key) {
  final value = financeMinor(json[key]);
  if (value == null) throw FormatException('Tutar alanı okunamadı: $key');
  return value;
}

/// İsteğe bağlı kuruş alanı: yok ya da null ise null; var ama bozuksa [FormatException] (sessiz null YOK).
int? f4MinorOrNull(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = financeMinor(json[key]);
  if (value == null) throw FormatException('Tutar alanı okunamadı: $key');
  return value;
}

/// Haritaya çevirir; harita değilse boş harita.
Map<String, dynamic> f4Map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

/// Nesne listesi; liste değilse boş.
List<T> f4List<T>(Object? raw, T Function(Map<String, dynamic> json) parse) {
  if (raw is! List) return const <Never>[];
  return List<T>.unmodifiable(
    raw.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))),
  );
}

bool f4Bool(Object? raw, {bool fallback = false}) => raw is bool ? raw : fallback;

bool? f4BoolOrNull(Object? raw) => raw is bool ? raw : null;

String f4Str(Object? raw, [String fallback = '']) => raw?.toString() ?? fallback;

int f4Int(Object? raw, [int fallback = 0]) => crmInt(raw, fallback);

int? f4IntOrNull(Object? raw) => crmIntOrNull(raw);

String? f4Text(Object? raw) => crmText(raw);

DateTime? f4Date(Object? raw) => crmDate(raw);

/// İlk dolu anahtarın değeri (sunucu alan adı varyantları için).
Object? f4First(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return value;
  }
  return null;
}

/// Oran (baz puan) -> "%5,00" (tamsayı aritmetiği).
String formatRateBp(int bp) {
  final whole = bp ~/ 100;
  final frac = (bp % 100).toString().padLeft(2, '0');
  return '%$whole,$frac';
}

/// Yüzde (baz puan, 10000 = %100) -> "%12,34". Negatif desteklenir.
String formatPercentBp(int bp) {
  final negative = bp < 0;
  final magnitude = bp.abs();
  final text = '%${magnitude ~/ 100},${(magnitude % 100).toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}

// --- Gecikme tazminatı yöntemi -------------------------------------------------------------------

/// Gün esası: aylık oran 30'a bölünür ya da ayın gerçek gün sayısına.
enum LateFeeMethod {
  daily30('daily_30', 'Aylık oran ÷ 30 gün'),
  dailyActual('daily_actual', 'Aylık oran ÷ ayın gerçek gün sayısı');

  const LateFeeMethod(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LateFeeMethod fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final method in values) {
        if (method.apiValue == normalized) return method;
      }
    }
    return daily30;
  }
}

// --- Ayarlar (GET/PUT …/finance/settings) --------------------------------------------------------

/// Gecikme tazminatı ayarları. [legalOk]: sistem bayrağı `finance.legal_ok` (hukuki onay); false iken özellik
/// site ayarı açık olsa da KULLANILAMAZ; null = sunucu bildirmedi (bilinmiyor, engellenmez, sunucu zorlar).
@immutable
class LateFeeSettings {
  const LateFeeSettings({
    this.enabled = false,
    this.rateBp = 500,
    this.maxRateBp = 500,
    this.method = LateFeeMethod.daily30,
    this.graceDays = 0,
    this.startPeriod,
    this.nextPeriod,
    this.voidableRunId,
    this.legalOk,
  });

  final bool enabled;
  final int rateBp;
  final int maxRateBp;
  final LateFeeMethod method;
  final int graceDays;
  final FinancePeriod? startPeriod;
  final FinancePeriod? nextPeriod;
  final int? voidableRunId;
  final bool? legalOk;

  /// Özellik şu an kullanılabilir mi (sistem bayrağı engellemiyor ve site ayarı açık)?
  bool get usable => enabled && legalOk != false;

  factory LateFeeSettings.fromJson(Map<String, dynamic> json, {bool? topLegalOk}) => LateFeeSettings(
    enabled: f4Bool(json['enabled']),
    rateBp: f4Int(json['rate_bp'], 500),
    maxRateBp: f4Int(json['max_rate_bp'], 500),
    method: LateFeeMethod.fromApi(json['method']),
    graceDays: f4Int(json['grace_days']),
    startPeriod: FinancePeriod.tryParse(json['start_period']),
    nextPeriod: FinancePeriod.tryParse(json['next_period']),
    voidableRunId: f4IntOrNull(json['voidable_run_id']),
    legalOk: f4BoolOrNull(json['legal_ok']) ?? topLegalOk,
  );
}

/// Borç hatırlatma ayarları.
@immutable
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.minOverdueMinor = 5000,
    this.minDaysOverdue = 5,
    this.minIntervalDays = 14,
    this.maxConsecutive = 3,
    this.smtpConfigured = true,
    this.legalOk,
  });

  final bool enabled;
  final int minOverdueMinor;
  final int minDaysOverdue;
  final int minIntervalDays;
  final int maxConsecutive;
  final bool smtpConfigured;
  final bool? legalOk;

  bool get usable => enabled && legalOk != false;

  factory ReminderSettings.fromJson(Map<String, dynamic> json, {bool? topLegalOk}) => ReminderSettings(
    enabled: f4Bool(json['enabled']),
    minOverdueMinor: f4MinorOrNull(json, 'min_overdue_minor') ?? 5000,
    minDaysOverdue: f4Int(json['min_days_overdue'], 5),
    minIntervalDays: f4Int(json['min_interval_days'], 14),
    maxConsecutive: f4Int(json['max_consecutive'], 3),
    smtpConfigured: f4Bool(json['smtp_configured'], fallback: true),
    legalOk: f4BoolOrNull(json['legal_ok']) ?? topLegalOk,
  );
}

/// `GET …/finance/settings`.
@immutable
class FinanceSettings {
  const FinanceSettings({
    required this.settingsVersion,
    this.receiptAutoIssue = true,
    this.lateFee = const LateFeeSettings(),
    this.reminders = const ReminderSettings(),
  });

  final int settingsVersion;
  final bool receiptAutoIssue;
  final LateFeeSettings lateFee;
  final ReminderSettings reminders;

  factory FinanceSettings.fromJson(Map<String, dynamic> json) {
    final version = financeMinor(json['settings_version']);
    if (version == null) throw const FormatException('Ayar sürümü okunamadı: settings_version');
    final top = f4BoolOrNull(json['legal_ok']);
    return FinanceSettings(
      settingsVersion: version,
      receiptAutoIssue: f4Bool(f4Map(json['receipts'])['auto_issue'], fallback: true),
      lateFee: LateFeeSettings.fromJson(f4Map(json['late_fee']), topLegalOk: top),
      reminders: ReminderSettings.fromJson(f4Map(json['reminders']), topLegalOk: top),
    );
  }
}

/// `PUT …/finance/settings` kısmi gövdesi: yalnız verilen (null olmayan) alanlar gönderilir.
@immutable
class FinanceSettingsPatch {
  const FinanceSettingsPatch({
    this.receiptAutoIssue,
    this.lateFeeEnabled,
    this.lateFeeRateBp,
    this.lateFeeMethod,
    this.lateFeeGraceDays,
    this.lateFeeStartPeriod,
    this.remindersEnabled,
    this.reminderMinOverdueMinor,
    this.reminderMinDaysOverdue,
    this.reminderMinIntervalDays,
    this.reminderMaxConsecutive,
  });

  final bool? receiptAutoIssue;
  final bool? lateFeeEnabled;
  final int? lateFeeRateBp;
  final LateFeeMethod? lateFeeMethod;
  final int? lateFeeGraceDays;
  final FinancePeriod? lateFeeStartPeriod;
  final bool? remindersEnabled;
  final int? reminderMinOverdueMinor;
  final int? reminderMinDaysOverdue;
  final int? reminderMinIntervalDays;
  final int? reminderMaxConsecutive;

  bool get isEmpty => toJson(0).length == 1;

  /// Sunucu gövdesi (GET yanıtının iç içe yapısını yansıtır).
  Map<String, dynamic> toJson(int expectedVersion) {
    final lateFee = <String, dynamic>{
      'enabled': ?lateFeeEnabled,
      'rate_bp': ?lateFeeRateBp,
      if (lateFeeMethod != null) 'method': lateFeeMethod!.apiValue,
      'grace_days': ?lateFeeGraceDays,
      if (lateFeeStartPeriod != null) 'start_period': lateFeeStartPeriod!.toApi(),
    };
    final reminders = <String, dynamic>{
      'enabled': ?remindersEnabled,
      'min_overdue_minor': ?reminderMinOverdueMinor,
      'min_days_overdue': ?reminderMinDaysOverdue,
      'min_interval_days': ?reminderMinIntervalDays,
      'max_consecutive': ?reminderMaxConsecutive,
    };
    return <String, dynamic>{
      'expected_settings_version': expectedVersion,
      if (receiptAutoIssue != null) 'receipts': <String, dynamic>{'auto_issue': receiptAutoIssue},
      if (lateFee.isNotEmpty) 'late_fee': lateFee,
      if (reminders.isNotEmpty) 'reminders': reminders,
    };
  }
}
