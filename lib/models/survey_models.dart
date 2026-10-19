// Anket ve Oylama (survey) modelleri: sözleşme docs/PLATFORM_ANKET.md (F11.01).
//
// Kurallar (Rezervasyon / İş Takibi ile aynı): eksik ya da bozuk alan ÇÖKMEZ (güvenli varsayılan); bilinmeyen
// sabitler `unknown` olur; yüzdeler TAMSAYI hesaplanır (kayan nokta yok); oy içeriği günlüğe yazılmaz.
import 'package:flutter/foundation.dart';

int _int(Object? raw, [int fallback = 0]) {
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

int? _intOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

String _text(Object? raw) => raw == null ? '' : raw.toString().trim();

DateTime? _date(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

List<int> _ints(Object? raw) => raw is List
    ? <int>[for (final v in raw) if (_intOrNull(v) != null) _intOrNull(v)!]
    : const <int>[];

List<String> _strings(Object? raw) =>
    raw is List ? <String>[for (final v in raw) _text(v)] : const <String>[];

/// Anket durumu (`status` / `effective_status`). Süresi geçmiş `open` anket sunucuda `closed` gibi okunur.
enum SurveyStatus {
  draft('draft', 'Taslak'),
  open('open', 'Açık'),
  closed('closed', 'Kapalı'),
  unknown('unknown', 'Bilinmiyor');

  const SurveyStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static const List<SurveyStatus> known = <SurveyStatus>[draft, open, closed];

  static SurveyStatus fromApi(Object? value) {
    final normalized = _text(value).toLowerCase();
    for (final s in known) {
      if (s.apiValue == normalized) return s;
    }
    return unknown;
  }
}

/// Hedef kitle türü.
enum SurveyTargetType {
  site('site', 'Tüm site'),
  blocks('blocks', 'Bloklar'),
  apartments('apartments', 'Daireler');

  const SurveyTargetType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static SurveyTargetType fromApi(Object? value) {
    final normalized = _text(value).toLowerCase();
    for (final t in values) {
      if (t.apiValue == normalized) return t;
    }
    return site;
  }
}

/// Tamsayı yüzde: `count * 100 ~/ total` (toplam 0 ise 0). Yuvarlama yok; toplam 100'ü aşmaz.
int surveyPercent(int count, int total) {
  if (total <= 0 || count <= 0) return 0;
  final p = (count * 100) ~/ total;
  return p > 100 ? 100 : p;
}

/// Sonuçlar: seçenek başına sayı, toplam oy, kitle büyüklüğü (sakin görünümünde `eligible_count` gelmez = 0).
@immutable
class SurveyResults {
  const SurveyResults({
    this.counts = const <int>[],
    this.totalVotes = 0,
    this.eligibleCount = 0,
  });

  final List<int> counts;
  final int totalVotes;
  final int eligibleCount;

  int countAt(int index) => index >= 0 && index < counts.length ? counts[index] : 0;

  int percentAt(int index) => surveyPercent(countAt(index), totalVotes);

  /// Katılım yüzdesi (kitle bilinmiyorsa null).
  int? get participationPercent =>
      eligibleCount <= 0 ? null : surveyPercent(totalVotes, eligibleCount);

  static SurveyResults? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return SurveyResults(
      counts: _ints(json['counts']),
      totalVotes: _int(json['total_votes']),
      eligibleCount: _int(json['eligible_count']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SurveyResults &&
      listEquals(other.counts, counts) &&
      other.totalVotes == totalVotes &&
      other.eligibleCount == eligibleCount;

  @override
  int get hashCode => Object.hash(Object.hashAll(counts), totalVotes, eligibleCount);
}

/// Hedef (`target{type, block_ids, apartment_ids, labels[]}`).
@immutable
class SurveyTarget {
  const SurveyTarget({
    this.type = SurveyTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
    this.labels = const <String>[],
  });

  final SurveyTargetType type;
  final List<int> blockIds;
  final List<int> apartmentIds;
  final List<String> labels;

  static SurveyTarget fromJson(Object? raw) {
    if (raw is! Map) return const SurveyTarget();
    final json = Map<String, dynamic>.from(raw);
    return SurveyTarget(
      type: SurveyTargetType.fromApi(json['type']),
      blockIds: _ints(json['block_ids']),
      apartmentIds: _ints(json['apartment_ids']),
      labels: _strings(json['labels']).where((l) => l.isNotEmpty).toList(growable: false),
    );
  }

  /// "Tüm site" / "Bloklar: A, B" / "Daireler: 3 daire".
  String get summary => switch (type) {
    SurveyTargetType.site => 'Tüm site',
    SurveyTargetType.blocks =>
      labels.isEmpty ? 'Bloklar (${blockIds.length})' : 'Bloklar: ${labels.join(', ')}',
    SurveyTargetType.apartments =>
      labels.isEmpty ? '${apartmentIds.length} daire' : 'Daireler: ${labels.join(', ')}',
  };
}

/// Yönetim liste öğesi (`Summary`).
@immutable
class SurveySummary {
  const SurveySummary({
    required this.id,
    this.title = '',
    this.status = SurveyStatus.unknown,
    this.effectiveStatus = SurveyStatus.unknown,
    this.targetType = SurveyTargetType.site,
    this.anonymous = true,
    this.oneVotePerApartment = false,
    this.closesAt,
    this.openedAt,
    this.closedAt,
    this.totalVotes = 0,
    this.eligibleCount = 0,
    this.createdAt,
    this.createdByName,
  });

  final int id;
  final String title;
  final SurveyStatus status;

  /// Süresi geçmiş `open` anket `closed` okunur; ekran bunu gösterir, eylem kuralları [status] ile yürür.
  final SurveyStatus effectiveStatus;
  final SurveyTargetType targetType;
  final bool anonymous;
  final bool oneVotePerApartment;
  final DateTime? closesAt;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final int totalVotes;
  final int eligibleCount;
  final DateTime? createdAt;
  final String? createdByName;

  bool get isDraft => status == SurveyStatus.draft;
  bool get isOpen => status == SurveyStatus.open;
  bool get isClosed => status == SurveyStatus.closed;

  /// Süresi dolmuş ama kapatılmamış açık anket.
  bool get isExpired => isOpen && effectiveStatus == SurveyStatus.closed;

  /// Yayınla (draft -> open).
  bool get canPublish => isDraft;

  /// Kapat (open -> closed).
  bool get canClose => isOpen;

  /// Sil (yalnız taslak).
  bool get canDelete => isDraft;

  factory SurveySummary.fromJson(Map<String, dynamic> json) {
    final status = SurveyStatus.fromApi(json['status']);
    return SurveySummary(
      id: _int(json['id']),
      title: _text(json['title']),
      status: status,
      effectiveStatus: json['effective_status'] == null
          ? status
          : SurveyStatus.fromApi(json['effective_status']),
      targetType: SurveyTargetType.fromApi(json['target_type']),
      anonymous: json['anonymous'] is bool ? json['anonymous'] as bool : true,
      oneVotePerApartment: json['one_vote_per_apartment'] == true,
      closesAt: _date(json['closes_at']),
      openedAt: _date(json['opened_at']),
      closedAt: _date(json['closed_at']),
      totalVotes: _int(json['total_votes']),
      eligibleCount: _int(json['eligible_count']),
      createdAt: _date(json['created_at']),
      createdByName: _text(json['created_by_name']).isEmpty ? null : _text(json['created_by_name']),
    );
  }

  static List<SurveySummary> listFrom(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((m) => SurveySummary.fromJson(Map<String, dynamic>.from(m)))
            .where((s) => s.id > 0)
            .toList(growable: false)
      : const <SurveySummary>[];
}

/// Yönetim ayrıntısı (`Detail` = Summary + soru, seçenekler, sonuç, hedef).
@immutable
class SurveyDetail {
  const SurveyDetail({
    required this.summary,
    this.question = '',
    this.options = const <String>[],
    this.results = const SurveyResults(),
    this.target = const SurveyTarget(),
  });

  final SurveySummary summary;
  final String question;
  final List<String> options;
  final SurveyResults results;
  final SurveyTarget target;

  int get id => summary.id;

  factory SurveyDetail.fromJson(Map<String, dynamic> json) => SurveyDetail(
    summary: SurveySummary.fromJson(json),
    question: _text(json['question']),
    options: _strings(json['options']),
    results: SurveyResults.fromJson(json['results']) ?? const SurveyResults(),
    target: SurveyTarget.fromJson(json['target']),
  );
}

/// Yönetim listesi: `{items, total}` (sayfa / kaydırma).
@immutable
class SurveyListPage {
  const SurveyListPage({this.items = const <SurveySummary>[], this.total = 0});

  final List<SurveySummary> items;
  final int total;

  factory SurveyListPage.fromJson(Map<String, dynamic> json) => SurveyListPage(
    items: SurveySummary.listFrom(json['items']),
    total: _int(json['total']),
  );
}

/// Oy veren (yalnız `anonymous=false` anketlerde, yönetici / süper).
@immutable
class SurveyVoter {
  const SurveyVoter({
    this.userCode,
    this.fullName = '',
    this.apartmentLabel = '',
    this.optionIndex = -1,
    this.votedAt,
  });

  final int? userCode;
  final String fullName;
  final String apartmentLabel;
  final int optionIndex;
  final DateTime? votedAt;

  String get displayName => fullName.isEmpty ? 'Silinmiş hesap' : fullName;

  factory SurveyVoter.fromJson(Map<String, dynamic> json) => SurveyVoter(
    userCode: _intOrNull(json['user_code']),
    fullName: _text(json['full_name']),
    apartmentLabel: _text(json['apartment_label']),
    optionIndex: _int(json['option_index'], -1),
    votedAt: _date(json['voted_at']),
  );
}

@immutable
class SurveyVoterPage {
  const SurveyVoterPage({this.items = const <SurveyVoter>[], this.total = 0});

  final List<SurveyVoter> items;
  final int total;

  factory SurveyVoterPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return SurveyVoterPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((m) => SurveyVoter.fromJson(Map<String, dynamic>.from(m)))
                .toList(growable: false)
          : const <SurveyVoter>[],
      total: _int(json['total']),
    );
  }
}

/// Sakin liste öğesi (`GET /app/surveys` ve `/app/surveys/:id`).
@immutable
class SurveyResidentItem {
  const SurveyResidentItem({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.title = '',
    this.question = '',
    this.options = const <String>[],
    this.effectiveStatus = SurveyStatus.unknown,
    this.closesAt,
    this.myVote,
    this.results,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final String title;
  final String question;
  final List<String> options;
  final SurveyStatus effectiveStatus;
  final DateTime? closesAt;

  /// Verdiğim oyun seçenek sırası; oy vermediysem null.
  final int? myVote;

  /// Sonuç yalnız oy verdikten sonra ya da anket kapanınca gelir; aksi halde null.
  final SurveyResults? results;

  bool get isOpen => effectiveStatus == SurveyStatus.open;
  bool get hasVoted => myVote != null;

  /// Oy verilebilir: açık ve henüz oy vermemiş.
  bool get canVote => isOpen && !hasVoted;

  /// Sonuç çubukları çizilir mi?
  bool get showsResults => results != null && (hasVoted || !isOpen);

  factory SurveyResidentItem.fromJson(Map<String, dynamic> json) => SurveyResidentItem(
    id: _int(json['id']),
    siteCode: _int(json['site_code']),
    siteName: _text(json['site_name']),
    title: _text(json['title']),
    question: _text(json['question']),
    options: _strings(json['options']),
    effectiveStatus: SurveyStatus.fromApi(json['effective_status'] ?? json['status']),
    closesAt: _date(json['closes_at']),
    myVote: _intOrNull(json['my_vote']),
    results: SurveyResults.fromJson(json['results']),
  );

  SurveyResidentItem copyWith({int? myVote, SurveyResults? results, SurveyStatus? effectiveStatus}) =>
      SurveyResidentItem(
        id: id,
        siteCode: siteCode,
        siteName: siteName,
        title: title,
        question: question,
        options: options,
        effectiveStatus: effectiveStatus ?? this.effectiveStatus,
        closesAt: closesAt,
        myVote: myVote ?? this.myVote,
        results: results ?? this.results,
      );
}

/// Sakin listesi: `{items, next_before_id}`.
@immutable
class SurveyResidentPage {
  const SurveyResidentPage({this.items = const <SurveyResidentItem>[], this.nextBeforeId});

  final List<SurveyResidentItem> items;
  final int? nextBeforeId;

  factory SurveyResidentPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return SurveyResidentPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((m) => SurveyResidentItem.fromJson(Map<String, dynamic>.from(m)))
                .where((s) => s.id > 0)
                .toList(growable: false)
          : const <SurveyResidentItem>[],
      nextBeforeId: _intOrNull(json['next_before_id']),
    );
  }
}

/// `POST /manager/sites/:siteCode/surveys` gövdesi.
@immutable
class SurveyCreateRequest {
  const SurveyCreateRequest({
    required this.title,
    required this.question,
    required this.options,
    this.targetType = SurveyTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
    this.anonymous = true,
    this.oneVotePerApartment = false,
    this.closesAt,
    this.publishNow = false,
  });

  static const int titleMax = 120;
  static const int questionMax = 1000;
  static const int optionMax = 80;
  static const int minOptions = 2;
  static const int maxOptions = 10;
  static const int maxTargetItems = 500;

  final String title;
  final String question;
  final List<String> options;
  final SurveyTargetType targetType;
  final List<int> blockIds;
  final List<int> apartmentIds;
  final bool anonymous;
  final bool oneVotePerApartment;
  final DateTime? closesAt;
  final bool publishNow;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title.trim(),
    'question': question.trim(),
    'options': <String>[for (final o in options) o.trim()],
    'target': <String, dynamic>{
      'type': targetType.apiValue,
      if (targetType == SurveyTargetType.blocks) 'block_ids': blockIds,
      if (targetType == SurveyTargetType.apartments) 'apartment_ids': apartmentIds,
    },
    'anonymous': anonymous,
    'one_vote_per_apartment': oneVotePerApartment,
    'closes_at': closesAt?.toUtc().toIso8601String(),
    'publish': publishNow ? 'now' : 'draft',
  };
}

/// Yönetim ekranındaki erişim türü: yönetici / süper yazar; kurul SALT OKUR (oy verenleri de göremez).
enum SurveySiteAccess { manager, board }

/// Yönetim ekranında listelenen site.
@immutable
class SurveySite {
  const SurveySite({required this.code, required this.name, this.access = SurveySiteAccess.manager});

  final int code;
  final String name;
  final SurveySiteAccess access;

  bool get canWrite => access == SurveySiteAccess.manager;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is SurveySite && other.code == code && other.name == name && other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}
