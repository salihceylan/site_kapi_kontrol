import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';

/// Gecikme tazminatı modelleri (Platform Faz 4b, Ö2; sözleşme: docs/PLATFORM_FINANS_4B.md "Ö2").
///
/// Tazminat OTOMATİK değildir: yönetici onaylı, önizlemeli, aylık ve zincirli bir toplu işlemdir. Hesabı SUNUCU
/// yapar; istemci tutarı yeniden HESAPLAMAZ, yalnız sunucunun döktüğü değerleri (gecikmiş tutar x gün) gösterir.

/// Hesaplanan ayın pencere bilgisi.
@immutable
class LateFeeWindow {
  const LateFeeWindow({this.from, this.to, this.days = 0});

  final DateTime? from;
  final DateTime? to;
  final int days;

  factory LateFeeWindow.fromJson(Map<String, dynamic> json) =>
      LateFeeWindow(from: f4Date(json['from']), to: f4Date(json['to']), days: f4Int(json['days']));
}

/// Çalıştırmanın ayar anlık görüntüsü (`params`).
@immutable
class LateFeeParams {
  const LateFeeParams({
    this.rateBp = 0,
    this.method = LateFeeMethod.daily30,
    this.graceDays = 0,
    this.settingsVersion,
  });

  final int rateBp;
  final LateFeeMethod method;
  final int graceDays;
  final int? settingsVersion;

  factory LateFeeParams.fromJson(Map<String, dynamic> json) => LateFeeParams(
    rateBp: f4Int(json['rate_bp']),
    method: LateFeeMethod.fromApi(json['method']),
    graceDays: f4Int(json['grace_days']),
    settingsVersion: f4IntOrNull(json['settings_version']),
  );
}

/// Gecikmiş tutar dilimi: `from..to` günlerinde `overdue_minor` gecikmiş (döküm).
@immutable
class OverdueSegment {
  const OverdueSegment({this.from, this.to, required this.overdueMinor});

  final DateTime? from;
  final DateTime? to;
  final int overdueMinor;

  factory OverdueSegment.fromJson(Map<String, dynamic> json) =>
      OverdueSegment(from: f4Date(json['from']), to: f4Date(json['to']), overdueMinor: f4Minor(json, 'overdue_minor'));
}

/// Önizleme / çalıştırma satırı: bir dairenin tazminatı ve "nasıl hesaplandı" bilgisi.
@immutable
class LateFeeLine {
  const LateFeeLine({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.payerParty,
    required this.amountMinor,
    this.baseDayMinor,
    this.peakOverdueMinor,
    this.breakdown = const <OverdueSegment>[],
    this.reversed = false,
    this.accountParty,
  });

  final int apartmentId;
  final String label;
  final String? blockName;

  /// Satırın hesabı (İP-1A: aynı dairenin iki hesabı gecikmişse iki satır olur); eski sunucuda null.
  final AccountParty? accountParty;
  /// Kim öder (önizlemede var; çalıştırma satırlarında sunucu göndermez -> null, uydurma değer yazılmaz).
  final ResponsibleParty? payerParty;
  final int amountMinor;

  /// Gecikmiş tutar x gün toplamı (kuruş·gün).
  final int? baseDayMinor;

  /// Ay içindeki en yüksek gecikmiş tutar.
  final int? peakOverdueMinor;
  final List<OverdueSegment> breakdown;

  /// Çalıştırma satırlarında: bu kalem sonradan (4a ters kayıtla) iptal edilmiş (sunucu `reversed`).
  final bool reversed;

  factory LateFeeLine.fromJson(Map<String, dynamic> json) => LateFeeLine(
    apartmentId: f4Int(json['apartment_id']),
    label: f4Str(json['label'] ?? json['apartment_label']),
    blockName: f4Text(json['block_name']),
    payerParty: json['payer_party'] == null ? null : ResponsibleParty.fromApi(json['payer_party']),
    amountMinor: f4Minor(json, 'amount_minor'),
    baseDayMinor: f4MinorOrNull(json, 'base_day_minor'),
    peakOverdueMinor: f4MinorOrNull(json, 'peak_overdue_minor'),
    breakdown: f4List(json['breakdown'], OverdueSegment.fromJson),
    reversed: f4Bool(json['reversed']),
    accountParty: AccountParty.tryParse(json['account_party']),
  );
}

/// Muaf tutulan daire (hesaplanan tutar yazılmaz).
@immutable
class LateFeeWaivedItem {
  const LateFeeWaivedItem({required this.apartmentId, this.label = '', this.computedMinor});

  final int apartmentId;
  final String label;
  final int? computedMinor;

  factory LateFeeWaivedItem.fromJson(Map<String, dynamic> json) => LateFeeWaivedItem(
    apartmentId: f4Int(json['apartment_id']),
    label: f4Str(json['label']),
    computedMinor: f4MinorOrNull(json, 'computed_minor'),
  );
}

/// Pasif olduğu için hesaplanmayan daire.
@immutable
class LateFeeSkippedItem {
  const LateFeeSkippedItem({required this.apartmentId, this.label = ''});

  final int apartmentId;
  final String label;

  factory LateFeeSkippedItem.fromJson(Map<String, dynamic> json) =>
      LateFeeSkippedItem(apartmentId: f4Int(json['apartment_id']), label: f4Str(json['label']));
}

/// `POST …/late-fee/preview` (YAZMAZ).
@immutable
class LateFeePreview {
  const LateFeePreview({
    this.period,
    this.expectedPeriod,
    this.window = const LateFeeWindow(),
    this.params = const LateFeeParams(),
    required this.totalMinor,
    required this.apartmentCount,
    this.lines = const <LateFeeLine>[],
    this.waived = const <LateFeeWaivedItem>[],
    this.inactiveSkipped = const <LateFeeSkippedItem>[],
    this.zeroAmountCount = 0,
    this.previewHash,
    this.canPost = false,
    this.blockers = const <String>[],
    this.empty = false,
  });

  final FinancePeriod? period;
  final FinancePeriod? expectedPeriod;
  final LateFeeWindow window;
  final LateFeeParams params;
  final int totalMinor;
  final int apartmentCount;
  final List<LateFeeLine> lines;
  final List<LateFeeWaivedItem> waived;
  final List<LateFeeSkippedItem> inactiveSkipped;
  final int zeroAmountCount;
  final String? previewHash;

  /// Sunucu "yazılabilir" dedi mi (engel yok)? Onay yalnız true iken açılır.
  final bool canPost;
  final List<String> blockers;

  /// Bu ayda tazminat doğuran daire YOK (kimse geç ödememiş / hepsi muaf): ay "tazminat yok" işaretiyle (`record_empty`)
  /// geçilir; aksi halde zincir bu ayda takılır. Engel yoksa `canPost` true'dur.
  final bool empty;

  factory LateFeePreview.fromJson(Map<String, dynamic> json) {
    final lines = f4List(json['lines'], LateFeeLine.fromJson);
    return LateFeePreview(
      period: FinancePeriod.tryParse(json['period']),
      expectedPeriod: FinancePeriod.tryParse(json['expected_period']),
      window: LateFeeWindow.fromJson(f4Map(json['window'])),
      params: LateFeeParams.fromJson(f4Map(json['settings'])),
      totalMinor: f4Minor(json, 'total_minor'),
      apartmentCount: json['apartment_count'] == null ? lines.length : f4Int(json['apartment_count']),
      lines: lines,
      waived: f4List(json['waived'], LateFeeWaivedItem.fromJson),
      inactiveSkipped: f4List(json['inactive_skipped'], LateFeeSkippedItem.fromJson),
      zeroAmountCount: f4Int(json['zero_amount_count']),
      previewHash: f4Text(json['preview_hash']),
      canPost: f4Bool(json['can_post']),
      blockers: <String>[
        for (final b in (json['blockers'] is List ? json['blockers'] as List : const <Object?>[]))
          if (b != null) b.toString(),
      ],
      empty: f4Bool(json['empty']),
    );
  }
}

/// Tazminat çalıştırması.
@immutable
class LateFeeRun {
  const LateFeeRun({
    required this.id,
    this.period,
    this.status = 'active',
    required this.totalMinor,
    this.netTotalMinor,
    this.apartmentCount = 0,
    this.waivedCount = 0,
    this.params = const LateFeeParams(),
    this.postedAt,
    this.postedByName,
    this.voidedAt,
    this.voidedByName,
    this.empty = false,
  });

  final int id;
  final FinancePeriod? period;

  /// `active` / `voided`.
  final String status;
  final int totalMinor;

  /// Kalem bazlı ters kayıtlar düşülmüş (türetilmiş); yoksa null.
  final int? netTotalMinor;
  final int apartmentCount;
  final int waivedCount;
  final LateFeeParams params;
  final DateTime? postedAt;
  final String? postedByName;
  final DateTime? voidedAt;
  final String? voidedByName;

  /// "Tazminat yok" işaret çalıştırması: tutarsız ve satırsız; zincirin bu ayı geçtiğini kaydeder (normal çalıştırma gibi
  /// iptal edilebilir, ters çevrilecek kalem yoktur).
  final bool empty;

  bool get isVoided => status == 'voided';

  factory LateFeeRun.fromJson(Map<String, dynamic> json) => LateFeeRun(
    id: f4Int(json['id']),
    period: FinancePeriod.tryParse(json['period']),
    status: f4Str(json['status'], 'active'),
    totalMinor: f4Minor(json, 'total_minor'),
    netTotalMinor: f4MinorOrNull(json, 'net_total_minor'),
    apartmentCount: f4Int(json['apartment_count']),
    waivedCount: f4Int(json['waived_count']),
    params: LateFeeParams.fromJson(f4Map(json['params'])),
    postedAt: announcementInstant(json['posted_at']),
    postedByName: f4Text(json['posted_by_name']),
    voidedAt: announcementInstant(json['voided_at']),
    voidedByName: f4Text(json['voided_by_name']),
    empty: json['empty'] == null ? f4Int(json['apartment_count']) == 0 : f4Bool(json['empty']),
  );
}

/// `GET …/late-fee/runs`.
@immutable
class LateFeeRunPage {
  const LateFeeRunPage({
    this.items = const <LateFeeRun>[],
    this.total = 0,
    this.nextPeriod,
    this.voidableRunId,
  });

  final List<LateFeeRun> items;
  final int total;
  final FinancePeriod? nextPeriod;
  final int? voidableRunId;

  factory LateFeeRunPage.fromJson(Map<String, dynamic> json) {
    final items = f4List(json['items'], LateFeeRun.fromJson);
    return LateFeeRunPage(
      items: items,
      total: f4Int(json['total'], items.length),
      nextPeriod: FinancePeriod.tryParse(json['next_period']),
      voidableRunId: f4IntOrNull(json['voidable_run_id']),
    );
  }
}

/// `GET …/late-fee/runs/:id/lines`.
@immutable
class LateFeeLinePage {
  const LateFeeLinePage({this.items = const <LateFeeLine>[], this.total = 0});

  final List<LateFeeLine> items;
  final int total;

  factory LateFeeLinePage.fromJson(Map<String, dynamic> json) {
    final items = f4List(json['items'], LateFeeLine.fromJson);
    return LateFeeLinePage(items: items, total: f4Int(json['total'], items.length));
  }
}

/// `POST …/late-fee/post` yanıtı.
@immutable
class LateFeePostResult {
  const LateFeePostResult({required this.run, this.entriesCount = 0});

  final LateFeeRun run;
  final int entriesCount;

  factory LateFeePostResult.fromJson(Map<String, dynamic> json) {
    final run = json['run'];
    if (run is! Map) throw const FormatException('Çalıştırma okunamadı: run');
    return LateFeePostResult(
      run: LateFeeRun.fromJson(Map<String, dynamic>.from(run)),
      entriesCount: f4Int(json['entries_count']),
    );
  }
}

/// `POST …/late-fee/runs/:id/void` yanıtı.
@immutable
class LateFeeVoidResult {
  const LateFeeVoidResult({required this.run, this.reversedCount = 0, this.reversedTotalMinor});

  final LateFeeRun run;
  final int reversedCount;
  final int? reversedTotalMinor;

  factory LateFeeVoidResult.fromJson(Map<String, dynamic> json) {
    final run = json['run'];
    if (run is! Map) throw const FormatException('Çalıştırma okunamadı: run');
    return LateFeeVoidResult(
      run: LateFeeRun.fromJson(Map<String, dynamic>.from(run)),
      reversedCount: f4Int(json['reversed_count']),
      reversedTotalMinor: f4MinorOrNull(json, 'reversed_total_minor'),
    );
  }
}

/// Sakin açıklaması: `GET /app/my-finance/entries/:entryId/late-fee`.
@immutable
class LateFeeExplanation {
  const LateFeeExplanation({
    this.period,
    this.rateBp = 0,
    this.method = LateFeeMethod.daily30,
    this.graceDays = 0,
    required this.amountMinor,
    this.baseDayMinor,
    this.segments = const <OverdueSegment>[],
  });

  final FinancePeriod? period;
  final int rateBp;
  final LateFeeMethod method;
  final int graceDays;
  final int amountMinor;
  final int? baseDayMinor;
  final List<OverdueSegment> segments;

  factory LateFeeExplanation.fromJson(Map<String, dynamic> json) => LateFeeExplanation(
    period: FinancePeriod.tryParse(json['period']),
    rateBp: f4Int(json['rate_bp']),
    method: LateFeeMethod.fromApi(json['method']),
    graceDays: f4Int(json['grace_days']),
    amountMinor: f4Minor(json, 'amount_minor'),
    baseDayMinor: f4MinorOrNull(json, 'base_day_minor'),
    segments: f4List(json['segments'], OverdueSegment.fromJson),
  );
}

/// Önizleme engeli kodu -> Türkçe (yönlendirici).
String lateFeeBlockerMessage(String code, {FinancePeriod? expectedPeriod, FinancePeriod? period}) {
  switch (code) {
    case 'LATE_FEE_DISABLED':
      return 'Gecikme tazminatı bu site için kapalı. Ayarlar bölümünden açın.';
    case 'LATE_FEE_NOT_CONFIGURED':
      return 'İlk hesaplanacak ay (başlangıç ayı) belirlenmemiş. Ayarlar bölümünden seçin.';
    case 'LATE_FEE_PERIOD_NOT_CLOSED':
      final label = period?.label ?? 'Bu';
      return 'Önce $label dönemini kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır.';
    case 'LATE_FEE_PERIOD_NOT_ENDED':
      return 'Bu ay henüz bitmedi. Tazminat yalnızca bitmiş ay için hesaplanır.';
    case 'LATE_FEE_PERIOD_NOT_NEXT':
      return expectedPeriod == null
          ? 'Tazminat aylar sırayla hesaplanır; sıradaki ayı seçin.'
          : 'Tazminat aylar sırayla hesaplanır. Sıradaki ay: ${expectedPeriod.label}.';
    case 'LATE_FEE_ALREADY_POSTED':
      return 'Bu ay için tazminat zaten yazılmış. Değiştirmek için önce son çalıştırmayı iptal edin.';
    case 'NOTHING_TO_POST':
      return 'Bu ay için tazminat doğuran daire yok.';
    case 'LEGAL_APPROVAL_REQUIRED':
      return 'Hukuk onayı bekleniyor. Gecikme tazminatı onay tamamlanana dek kullanılamaz.';
    default:
      return 'Bu ay için tazminat şu an hesaplanamaz.';
  }
}
