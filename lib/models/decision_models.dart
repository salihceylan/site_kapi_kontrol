// Karar Defteri (`decision_book`) modelleri: yönetim kurulu, genel kurul ve denetim kurulu kararlarının kaydı.
//
// Kurallar (Anket / Ziyaretçi ile aynı): eksik ya da bozuk alan ÇÖKMEZ (güvenli varsayılan); bilinmeyen sabitler
// güvenli değere düşer; toplantı günü ("YYYY-AA-GG") saat dilimi kaydırılmadan TAKVİM GÜNÜ olarak okunur (gece yarısı
// UTC damgası yerel saate çevrilip bir önceki güne kaymaz). Karar metni günlüğe yazılmaz.
//
// Sakin görünümünde `status`, `visibility` ve `created_by_name` GELMEZ: sakin yalnız kesinleşmiş ve sakinlere açık
// kararları görür (bkz. [Decision.fromJson] `resident`).
import 'package:flutter/foundation.dart';

/// Karar Defteri'nin her ekranında ve PDF altbilgisinde gösterilen yasal not.
const String kDecisionLegalNotice =
    'Bu kayıt noter onaylı karar defterinin yerine geçmez; resmî karar defterine işlenmesi gerekir.';

int? _intOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

int _int(Object? raw, [int fallback = 0]) => _intOrNull(raw) ?? fallback;

String _text(Object? raw) => raw == null ? '' : raw.toString().trim();

String? _textOrNull(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : text;
}

DateTime? _instant(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString().trim())?.toLocal();
}

/// "2026-03-05" (ya da "2026-03-05T00:00:00.000Z") -> yerel 05.03.2026 (saat yok). Gerçek olmayan gün null.
DateTime? parseDecisionDay(Object? raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(_text(raw));
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Sunucuya gönderilen gün: "2026-03-05".
String decisionDayParam(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Toplantı türü (`meeting_type`). Bilinmeyen değer "Diğer" okunur.
enum DecisionMeetingType {
  yonetimKurulu('yonetim_kurulu', 'Yönetim Kurulu'),
  genelKurul('genel_kurul', 'Genel Kurul'),
  denetimKurulu('denetim_kurulu', 'Denetim Kurulu'),
  diger('diger', 'Diğer');

  const DecisionMeetingType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DecisionMeetingType fromApi(Object? value) {
    final normalized = _text(value).toLowerCase();
    for (final t in values) {
      if (t.apiValue == normalized) return t;
    }
    return diger;
  }
}

/// Oylama sonucu (`vote_result`). Bilinmeyen değer [unknown] ("Belirtilmemiş"); formda seçilemez.
enum DecisionVoteResult {
  kabul('kabul', 'Kabul edildi'),
  ret('ret', 'Reddedildi'),
  ertelendi('ertelendi', 'Ertelendi'),
  bilgi('bilgi', 'Bilgi notu'),
  unknown('', 'Belirtilmemiş');

  const DecisionVoteResult(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Formda seçilebilen sonuçlar.
  static const List<DecisionVoteResult> known = <DecisionVoteResult>[kabul, ret, ertelendi, bilgi];

  static DecisionVoteResult fromApi(Object? value) {
    final normalized = _text(value).toLowerCase();
    for (final r in known) {
      if (r.apiValue == normalized) return r;
    }
    return unknown;
  }
}

/// Kayıt durumu: taslak (düzenlenir, silinir) ya da kesin (numara almış, DEĞİŞMEZ).
enum DecisionStatus {
  taslak('taslak', 'Taslak'),
  kesin('kesin', 'Kesin'),
  unknown('unknown', 'Bilinmiyor');

  const DecisionStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DecisionStatus fromApi(Object? value) {
    final normalized = _text(value).toLowerCase();
    if (normalized == taslak.apiValue) return taslak;
    if (normalized == kesin.apiValue) return kesin;
    return unknown;
  }
}

/// Görünürlük: yalnız yönetim ya da sakinler de görür. Bilinmeyen değer "yalnız yönetim" (dar olan) okunur.
enum DecisionVisibility {
  yonetim('yonetim', 'Yalnız yönetim'),
  sakinler('sakinler', 'Sakinlere açık');

  const DecisionVisibility(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DecisionVisibility fromApi(Object? value) =>
      _text(value).toLowerCase() == sakinler.apiValue ? sakinler : yonetim;
}

/// Başka bir karara bağlantı (`superseded_by[]` öğesi ya da `supersedes_id` + `supersedes_label`).
@immutable
class DecisionRef {
  const DecisionRef({required this.id, this.numberLabel});

  final int id;

  /// "2026/5"; numarasız (taslak) bağlantıda null.
  final String? numberLabel;

  static List<DecisionRef> listFrom(Object? raw) => raw is List
      ? <DecisionRef>[
          for (final item in raw)
            if (item is Map && _int(item['id']) > 0)
              DecisionRef(id: _int(item['id']), numberLabel: _textOrNull(item['number_label'])),
        ]
      : const <DecisionRef>[];

  @override
  bool operator ==(Object other) => other is DecisionRef && other.id == id && other.numberLabel == numberLabel;

  @override
  int get hashCode => Object.hash(id, numberLabel);
}

/// "2026/5 sayılı kararla değiştirildi" (birden çoksa "2026/5, 2026/7 sayılı kararlarla değiştirildi"); numara
/// bilinmiyorsa "Yeni bir kararla değiştirildi"; bağlantı yoksa null.
String? decisionSupersededText(List<DecisionRef> refs) {
  if (refs.isEmpty) return null;
  final labels = <String>[for (final r in refs) if (r.numberLabel != null) r.numberLabel!];
  if (labels.isEmpty) return 'Yeni bir kararla değiştirildi';
  if (labels.length == 1) return '${labels.single} sayılı kararla değiştirildi';
  return '${labels.join(', ')} sayılı kararlarla değiştirildi';
}

/// Bir karar (yönetim ya da sakin görünümü).
@immutable
class Decision {
  const Decision({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.year = 0,
    this.decisionNo,
    this.numberLabel,
    this.meetingType = DecisionMeetingType.diger,
    this.meetingDate,
    this.title = '',
    this.body = '',
    this.attendees,
    this.voteResult = DecisionVoteResult.unknown,
    this.votesFor,
    this.votesAgainst,
    this.votesAbstain,
    this.visibility,
    this.status = DecisionStatus.unknown,
    this.supersedesId,
    this.supersedesLabel,
    this.supersededBy = const <DecisionRef>[],
    this.createdByName,
    this.finalizedByName,
    this.finalizedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int siteCode;

  /// Sakin listesinde birden çok site varken gösterilir (sunucu göndermezse boş).
  final String siteName;
  final int year;
  final int? decisionNo;

  /// "2026/3"; taslakta null.
  final String? numberLabel;
  final DecisionMeetingType meetingType;
  final DateTime? meetingDate;
  final String title;
  final String body;
  final String? attendees;
  final DecisionVoteResult voteResult;
  final int? votesFor;
  final int? votesAgainst;
  final int? votesAbstain;

  /// Yalnız yönetim görünümünde; sakinde null.
  final DecisionVisibility? visibility;
  final DecisionStatus status;
  final int? supersedesId;
  final String? supersedesLabel;
  final List<DecisionRef> supersededBy;
  final String? createdByName;
  final String? finalizedByName;
  final DateTime? finalizedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDraft => status == DecisionStatus.taslak;
  bool get isFinal => status == DecisionStatus.kesin;
  bool get isVisibleToResidents => visibility == DecisionVisibility.sakinler;
  bool get isSuperseded => supersededBy.isNotEmpty;
  bool get hasVoteCounts => votesFor != null || votesAgainst != null || votesAbstain != null;

  /// Gruplama yılı: sunucunun `year` alanı, yoksa toplantı yılı.
  int get effectiveYear => year > 0 ? year : (meetingDate?.year ?? 0);

  /// Kartta / başlıkta: "2026/3"; taslakta "Taslak"; numarası bilinmeyen kesin kayıtta "Numarasız".
  String get displayNumber => numberLabel ?? (isFinal ? 'Numarasız' : 'Taslak');

  /// "Kabul 5 · Ret 1 · Çekimser 0" (yalnız girilmiş sayılar); hiç yoksa null.
  String? get voteCountsText {
    if (!hasVoteCounts) return null;
    return <String>[
      if (votesFor != null) 'Kabul $votesFor',
      if (votesAgainst != null) 'Ret $votesAgainst',
      if (votesAbstain != null) 'Çekimser $votesAbstain',
    ].join(' · ');
  }

  String? get supersededText => decisionSupersededText(supersededBy);

  /// Değiştirdiği karar (bağlantı); yoksa null.
  DecisionRef? get supersedes =>
      supersedesId == null || supersedesId! <= 0 ? null : DecisionRef(id: supersedesId!, numberLabel: supersedesLabel);

  /// [resident] (sakin görünümü): `status` gelmez ve sakin yalnız KESİN kararları görür; görünürlük null kalır.
  factory Decision.fromJson(Map<String, dynamic> json, {bool resident = false}) {
    final meetingDate = parseDecisionDay(json['meeting_date']);
    final rawStatus = json['status'];
    final DecisionStatus status;
    if (rawStatus == null) {
      // Sakin görünümü (alan yok) ya da eski yanıt: numarası olan kayıt kesindir.
      status = resident || _textOrNull(json['number_label']) != null || _intOrNull(json['decision_no']) != null
          ? DecisionStatus.kesin
          : DecisionStatus.unknown;
    } else {
      status = DecisionStatus.fromApi(rawStatus);
    }
    final hasVisibility = !resident && json.containsKey('visibility');
    return Decision(
      id: _int(json['id']),
      siteCode: _int(json['site_code']),
      siteName: _text(json['site_name']),
      year: _int(json['year'], meetingDate?.year ?? 0),
      decisionNo: _intOrNull(json['decision_no']),
      numberLabel: _textOrNull(json['number_label']),
      meetingType: DecisionMeetingType.fromApi(json['meeting_type']),
      meetingDate: meetingDate,
      title: _text(json['title']),
      // Metin satır sonlarını korur (yalnız baştaki / sondaki boşluk atılır).
      body: json['body'] == null ? '' : json['body'].toString().trim(),
      attendees: _textOrNull(json['attendees']),
      voteResult: DecisionVoteResult.fromApi(json['vote_result']),
      votesFor: _intOrNull(json['votes_for']),
      votesAgainst: _intOrNull(json['votes_against']),
      votesAbstain: _intOrNull(json['votes_abstain']),
      visibility: hasVisibility ? DecisionVisibility.fromApi(json['visibility']) : null,
      status: status,
      supersedesId: _intOrNull(json['supersedes_id']),
      supersedesLabel: _textOrNull(json['supersedes_label']),
      supersededBy: DecisionRef.listFrom(json['superseded_by']),
      createdByName: resident ? null : _textOrNull(json['created_by_name']),
      finalizedByName: _textOrNull(json['finalized_by_name']),
      finalizedAt: _instant(json['finalized_at']),
      createdAt: _instant(json['created_at']),
      updatedAt: _instant(json['updated_at']),
    );
  }

  /// `{decision: {...}}` sarmalı ya da doğrudan karar nesnesi; tanınmazsa (id yok) null.
  static Decision? fromResponse(Object? raw, {bool resident = false}) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final inner = json['decision'];
    final decision = Decision.fromJson(inner is Map ? Map<String, dynamic>.from(inner) : json, resident: resident);
    return decision.id > 0 ? decision : null;
  }

  static List<Decision> listFrom(Object? raw, {bool resident = false}) => raw is List
      ? raw
            .whereType<Map>()
            .map((m) => Decision.fromJson(Map<String, dynamic>.from(m), resident: resident))
            .where((d) => d.id > 0)
            .toList(growable: false)
      : const <Decision>[];

  @override
  bool operator ==(Object other) =>
      other is Decision &&
      other.id == id &&
      other.siteCode == siteCode &&
      other.siteName == siteName &&
      other.year == year &&
      other.decisionNo == decisionNo &&
      other.numberLabel == numberLabel &&
      other.meetingType == meetingType &&
      other.meetingDate == meetingDate &&
      other.title == title &&
      other.body == body &&
      other.attendees == attendees &&
      other.voteResult == voteResult &&
      other.votesFor == votesFor &&
      other.votesAgainst == votesAgainst &&
      other.votesAbstain == votesAbstain &&
      other.visibility == visibility &&
      other.status == status &&
      other.supersedesId == supersedesId &&
      other.supersedesLabel == supersedesLabel &&
      listEquals(other.supersededBy, supersededBy) &&
      other.createdByName == createdByName &&
      other.finalizedByName == finalizedByName &&
      other.finalizedAt == finalizedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, numberLabel, status, title, updatedAt, finalizedAt, Object.hashAll(supersededBy));
}

/// Karar defteri sırası: karar numarası (küçükten büyüğe), numarasızlar sonda; sonra toplantı günü, sonra kimlik.
int compareDecisionsByNumber(Decision a, Decision b) {
  final an = a.decisionNo;
  final bn = b.decisionNo;
  if (an != null && bn != null && an != bn) return an.compareTo(bn);
  if (an != null && bn == null) return -1;
  if (an == null && bn != null) return 1;
  final ad = a.meetingDate;
  final bd = b.meetingDate;
  if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
  return a.id.compareTo(b.id);
}

/// Sonraki sayfanın imleci. Sözleşme `before_id` (yanıtta `next_before_id`) ister; sunucu opak `cursor` (yanıtta
/// `next_cursor`) da kullanabilir: hangi alan geldiyse sonraki istekte o parametre gönderilir.
@immutable
class DecisionCursor {
  const DecisionCursor.beforeId(int id) : param = 'before_id', value = '$id';

  const DecisionCursor.opaque(this.value) : param = 'cursor';

  /// Sorgu parametresi adı (`before_id` ya da `cursor`).
  final String param;
  final String value;

  Map<String, String> get query => <String, String>{param: value};

  /// Yanıttaki sonraki imleç (`next_cursor` öncelikli, sonra `next_before_id`); son sayfada null.
  static DecisionCursor? fromPage(Map<String, dynamic> json) {
    final cursor = _textOrNull(json['next_cursor']);
    if (cursor != null) return DecisionCursor.opaque(cursor);
    final before = _intOrNull(json['next_before_id']);
    if (before != null && before > 0) return DecisionCursor.beforeId(before);
    return null;
  }

  @override
  bool operator ==(Object other) => other is DecisionCursor && other.param == param && other.value == value;

  @override
  int get hashCode => Object.hash(param, value);

  @override
  String toString() => '$param=$value';
}

/// Liste sayfası: `{items, next_before_id | next_cursor, years}`.
@immutable
class DecisionPage {
  const DecisionPage({this.items = const <Decision>[], this.next, this.years = const <int>[]});

  final List<Decision> items;
  final DecisionCursor? next;

  /// Kaydı olan yıllar (yeniden eskiye, yinelenmesiz).
  final List<int> years;

  factory DecisionPage.fromJson(Map<String, dynamic> json, {bool resident = false}) {
    final rawYears = json['years'];
    final years = <int>{
      if (rawYears is List)
        for (final y in rawYears)
          if (_intOrNull(y) != null && _intOrNull(y)! > 0) _intOrNull(y)!,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return DecisionPage(
      items: Decision.listFrom(json['items'], resident: resident),
      next: DecisionCursor.fromPage(json),
      years: years,
    );
  }
}

/// Oluşturma / düzenleme formunun değeri (`POST` gövdesi; `PATCH` için [diff]).
@immutable
class DecisionInput {
  const DecisionInput({
    required this.meetingType,
    required this.meetingDate,
    required this.title,
    required this.body,
    this.attendees = '',
    required this.voteResult,
    this.votesFor,
    this.votesAgainst,
    this.votesAbstain,
    this.visibility = DecisionVisibility.yonetim,
    this.supersedesId,
  });

  // Sunucu sınırlarıyla aynı.
  static const int titleMax = 160;
  static const int bodyMax = 10000;
  static const int attendeesMax = 2000;
  static const int votesMax = 100000;

  /// Toplantı günü bugünden en çok bu kadar gün ileride olabilir.
  static const int meetingDateMaxAheadDays = 366;

  /// Toplantı günü bu yılın 1 Ocak'ından önce olamaz.
  static const int meetingDateMinYear = 1950;

  final DecisionMeetingType meetingType;
  final DateTime meetingDate;
  final String title;
  final String body;
  final String attendees;
  final DecisionVoteResult voteResult;
  final int? votesFor;
  final int? votesAgainst;
  final int? votesAbstain;
  final DecisionVisibility visibility;
  final int? supersedesId;

  String? get _attendees => attendees.trim().isEmpty ? null : attendees.trim();

  /// `POST /manager/sites/:siteCode/decisions` gövdesi (boş isteğe bağlı alanlar gönderilmez).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'meeting_type': meetingType.apiValue,
    'meeting_date': decisionDayParam(meetingDate),
    'title': title.trim(),
    'body': body.trim(),
    'attendees': ?_attendees,
    'vote_result': voteResult.apiValue,
    'votes_for': ?votesFor,
    'votes_against': ?votesAgainst,
    'votes_abstain': ?votesAbstain,
    'visibility': visibility.apiValue,
    'supersedes_id': ?supersedesId,
  };

  /// `PATCH` gövdesi: yalnız [original]'den DEĞİŞEN alanlar (temizlenen isteğe bağlı alan `null`). Değişiklik yoksa
  /// boş harita. Değiştirilen karar bağlantısı (`supersedes_id`) düzenlemede değişmez, gönderilmez.
  Map<String, Object?> diff(Decision original) {
    final out = <String, Object?>{};
    final full = toJson();
    if (original.meetingType != meetingType) out['meeting_type'] = full['meeting_type'];
    final day = original.meetingDate;
    if (day == null || decisionDayParam(day) != full['meeting_date']) out['meeting_date'] = full['meeting_date'];
    if (original.title != title.trim()) out['title'] = full['title'];
    if (original.body != body.trim()) out['body'] = full['body'];
    if ((original.attendees ?? '') != (_attendees ?? '')) out['attendees'] = _attendees;
    if (original.voteResult != voteResult) out['vote_result'] = full['vote_result'];
    if (original.votesFor != votesFor) out['votes_for'] = votesFor;
    if (original.votesAgainst != votesAgainst) out['votes_against'] = votesAgainst;
    if (original.votesAbstain != votesAbstain) out['votes_abstain'] = votesAbstain;
    if ((original.visibility ?? DecisionVisibility.yonetim) != visibility) out['visibility'] = full['visibility'];
    return out;
  }
}

/// Yönetim ekranındaki erişim türü: yönetici / süper yazar ve kesinleştirir; kurul SALT OKUR (taslaklar dahil).
enum DecisionSiteAccess { manager, board }

/// Yönetim ekranında listelenen site.
@immutable
class DecisionSite {
  const DecisionSite({required this.code, required this.name, this.access = DecisionSiteAccess.manager});

  final int code;
  final String name;
  final DecisionSiteAccess access;

  bool get canWrite => access == DecisionSiteAccess.manager;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is DecisionSite && other.code == code && other.name == name && other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}

/// Karar Defteri (`decision_book`) denetim eylemlerinin Türkçe başlığı; bilinmeyen eylemde null (zincirdeki sonraki
/// üretici dener). Karar başlığı / metni denetim kaydına yazılmaz.
String? decisionBookActionLabel(String action) {
  switch (action) {
    case 'board_decision.created':
      return 'Karar taslağı oluşturuldu';
    case 'board_decision.updated':
      return 'Karar taslağı düzenlendi';
    case 'board_decision.deleted':
      return 'Karar taslağı silindi';
    case 'board_decision.finalized':
      return 'Karar kesinleştirildi';
  }
  return null;
}
