// Dekont bildirimi (geçici kabul) modelleri (Dalga 2 / 2B; sözleşme: docs/PLATFORM_FINANS_DEKONT.md).
//
// Bildirim deftere YAZILMAZ: yönetici onaylayınca tahsilat (ve makbuz) dekont tarihiyle oluşur; iptalde neden sakine gösterilir.

String? _s(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
int _i(Object? v, [int fallback = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);
DateTime? _d(Object? v) => DateTime.tryParse(_s(v) ?? '');
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) map) =>
    v is List ? <T>[for (final e in v) if (e is Map) map(Map<String, dynamic>.from(e))] : <T>[];

/// Bildirimin durumu (sunucu: uploading | pending | approved | rejected | withdrawn).
enum NoticeStatus {
  uploading,
  pending,
  approved,
  rejected,
  withdrawn;

  static NoticeStatus parse(Object? v) => NoticeStatus.values.firstWhere((s) => s.name == v, orElse: () => NoticeStatus.pending);

  String get label => switch (this) {
    NoticeStatus.uploading => 'Yükleniyor',
    NoticeStatus.pending => 'İnceleniyor',
    NoticeStatus.approved => 'Onaylandı',
    NoticeStatus.rejected => 'İptal edildi',
    NoticeStatus.withdrawn => 'Geri çekildi',
  };
}

/// İptal nedenleri (sunucu kodu -> sakine gösterilen kısa ad).
const Map<String, String> kNoticeRejectReasons = <String, String>{
  'not_received': 'Ödeme hesaba ulaşmadı',
  'amount_mismatch': 'Tutar uyuşmuyor',
  'wrong_apartment': 'Yanlış daire',
  'duplicate': 'Daha önce kaydedilmiş',
  'unreadable': 'Dekont okunamadı',
  'other': 'Diğer',
};

/// Ödeme yöntemi etiketleri (elden giriş).
const Map<String, String> kNoticeMethods = <String, String>{'transfer': 'Havale / EFT', 'cash': 'Nakit', 'cheque': 'Çek'};

class PaymentNotice {
  const PaymentNotice({
    required this.id,
    required this.siteCode,
    required this.apartmentId,
    this.apartmentLabel = '',
    this.accountParty = 'owner',
    this.origin = 'resident_app',
    this.status = NoticeStatus.pending,
    required this.amountMinor,
    required this.paidOn,
    this.method = 'transfer',
    this.senderName,
    this.senderIban,
    this.description,
    this.note,
    this.hasFile = false,
    this.displayName,
    this.mimeType,
    this.sizeBytes,
    this.submittedAt,
    this.decidedAt,
    this.rejectReasonCode,
    this.rejectReasonText,
    this.rejectNote,
    this.ledgerEntryId,
    this.linkedExisting = false,
    this.unseenDecision = false,
  });

  factory PaymentNotice.fromJson(Map<String, dynamic> j) => PaymentNotice(
    id: _i(j['id']),
    siteCode: _i(j['site_code']),
    apartmentId: _i(j['apartment_id']),
    apartmentLabel: _s(j['apartment_label']) ?? '',
    accountParty: _s(j['account_party']) ?? 'owner',
    origin: _s(j['origin']) ?? 'resident_app',
    status: NoticeStatus.parse(j['status']),
    amountMinor: _i(j['amount_minor']),
    paidOn: _d(j['paid_on']) ?? DateTime.now(),
    method: _s(j['method']) ?? 'transfer',
    senderName: _s(j['sender_name']),
    senderIban: _s(j['sender_iban']),
    description: _s(j['description']),
    note: _s(j['note']),
    hasFile: j['has_file'] == true,
    displayName: _s(j['display_name']),
    mimeType: _s(j['mime_type']),
    sizeBytes: j['size_bytes'] == null ? null : _i(j['size_bytes']),
    submittedAt: _d(j['submitted_at'])?.toLocal(),
    decidedAt: _d(j['decided_at'])?.toLocal(),
    rejectReasonCode: _s(j['reject_reason_code']),
    rejectReasonText: _s(j['reject_reason_text']),
    rejectNote: _s(j['reject_note']),
    ledgerEntryId: j['ledger_entry_id'] == null ? null : _i(j['ledger_entry_id']),
    linkedExisting: j['linked_existing'] == true,
    unseenDecision: j['unseen_decision'] == true,
  );

  final int id;
  final int siteCode;
  final int apartmentId;
  final String apartmentLabel;
  final String accountParty;
  final String origin;
  final NoticeStatus status;
  final int amountMinor;
  final DateTime paidOn;
  final String method;
  final String? senderName;
  final String? senderIban;
  final String? description;
  final String? note;
  final bool hasFile;
  final String? displayName;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? submittedAt;
  final DateTime? decidedAt;
  final String? rejectReasonCode;
  final String? rejectReasonText;
  final String? rejectNote;
  final int? ledgerEntryId;
  final bool linkedExisting;
  final bool unseenDecision;

  bool get isPending => status == NoticeStatus.pending;
  bool get isPdf => mimeType == 'application/pdf';
  bool get fromManager => origin == 'manager';
  String get accountLabel => accountParty == 'tenant' ? 'Kiracı hesabı' : 'Ev sahibi hesabı';
}

/// Sakinin kendi bildirimleri (`GET /app/my-finance/payment-notices`).
class MyNotices {
  const MyNotices({this.items = const <PaymentNotice>[], this.pendingTotalMinor = 0, this.unseenCount = 0});

  factory MyNotices.fromJson(Map<String, dynamic> j) => MyNotices(
    items: _list(j['items'], PaymentNotice.fromJson),
    pendingTotalMinor: _i(j['pending_total_minor']),
    unseenCount: _i(j['unseen_count']),
  );

  final List<PaymentNotice> items;
  final int pendingTotalMinor;
  final int unseenCount;
}

/// Yönetici listesi (`GET .../finance/payment-notices`).
class NoticePage {
  const NoticePage({this.items = const <PaymentNotice>[], this.hasMore = false, this.counts = const <String, int>{}});

  factory NoticePage.fromJson(Map<String, dynamic> j) {
    final counts = <String, int>{};
    final raw = j['counts'];
    if (raw is Map) raw.forEach((k, v) => counts['$k'] = _i(v));
    return NoticePage(items: _list(j['items'], PaymentNotice.fromJson), hasMore: j['has_more'] == true, counts: counts);
  }

  final List<PaymentNotice> items;
  final bool hasMore;
  final Map<String, int> counts;
}

/// Dikkat sayacı (2F ana sayfa kartı ve "Dekontlar" sekmesi rozeti).
class NoticeAttention {
  const NoticeAttention({this.count = 0, this.totalMinor = 0});

  factory NoticeAttention.fromJson(Map<String, dynamic> j) {
    final a = j['attention'];
    final m = a is Map ? Map<String, dynamic>.from(a) : j;
    return NoticeAttention(count: _i(m['count']), totalMinor: _i(m['total_minor']));
  }

  final int count;
  final int totalMinor;
}

class NoticeWarning {
  const NoticeWarning({required this.code, required this.level, this.message = ''});

  factory NoticeWarning.fromJson(Map<String, dynamic> j) =>
      NoticeWarning(code: _s(j['code']) ?? '', level: _s(j['level']) ?? 'info', message: _s(j['message']) ?? '');

  final String code;
  final String level;
  final String message;

  /// Önemli uyarı: onaylamadan önce yöneticinin açıkça işaretlemesi gerekir.
  bool get strong => level == 'strong';
}

class NoticePerson {
  const NoticePerson({required this.name, this.relation = ''});

  final String name;
  final String relation;

  String get relationLabel => switch (relation) {
    'owner' => 'Ev sahibi',
    'tenant' => 'Kiracı',
    'family_member' => 'Aile üyesi',
    _ => 'Sakin',
  };
}

class NoticeRecentPayment {
  const NoticeRecentPayment({required this.id, required this.date, required this.amountMinor, this.accountParty = 'owner'});

  final int id;
  final DateTime? date;
  final int amountMinor;
  final String accountParty;
}

/// Karşılaştırma ekranı verisi: bildirim + daire bilgisi + uyarılar.
class NoticeDetail {
  const NoticeDetail({
    required this.notice,
    this.people = const <NoticePerson>[],
    this.ownerBalanceMinor = 0,
    this.tenantBalanceMinor = 0,
    this.recent = const <NoticeRecentPayment>[],
    this.warnings = const <NoticeWarning>[],
  });

  factory NoticeDetail.fromJson(Map<String, dynamic> j) {
    final apt = j['apartment'] is Map ? Map<String, dynamic>.from(j['apartment'] as Map) : <String, dynamic>{};
    final balances = apt['balances'] is Map ? Map<String, dynamic>.from(apt['balances'] as Map) : <String, dynamic>{};
    int balanceOf(String k) => balances[k] is Map ? _i((balances[k] as Map)['balance_minor']) : 0;
    return NoticeDetail(
      notice: PaymentNotice.fromJson(Map<String, dynamic>.from(j['notice'] as Map)),
      people: _list(apt['people'], (m) => NoticePerson(name: _s(m['name']) ?? 'İsimsiz', relation: _s(m['relation']) ?? '')),
      ownerBalanceMinor: balanceOf('owner'),
      tenantBalanceMinor: balanceOf('tenant'),
      recent: _list(
        apt['recent_payments'],
        (m) => NoticeRecentPayment(id: _i(m['id']), date: _d(m['entry_date']), amountMinor: _i(m['amount_minor']), accountParty: _s(m['account_party']) ?? 'owner'),
      ),
      warnings: _list(j['warnings'], NoticeWarning.fromJson),
    );
  }

  final PaymentNotice notice;
  final List<NoticePerson> people;
  final int ownerBalanceMinor;
  final int tenantBalanceMinor;
  final List<NoticeRecentPayment> recent;
  final List<NoticeWarning> warnings;

  List<NoticeWarning> get strongWarnings => <NoticeWarning>[for (final w in warnings) if (w.strong) w];
}

/// Oluşturma sonucu: kayıt + (dosya gerekiyorsa) yükleme yolu.
class NoticeCreated {
  const NoticeCreated({required this.notice, this.uploadPath});

  factory NoticeCreated.fromJson(Map<String, dynamic> j) => NoticeCreated(
    notice: PaymentNotice.fromJson(Map<String, dynamic>.from(j['notice'] as Map)),
    uploadPath: j['upload'] is Map ? _s((j['upload'] as Map)['path']) : null,
  );

  final PaymentNotice notice;
  final String? uploadPath;
}

/// Toplu işlem satırı.
class NoticeBulkResult {
  const NoticeBulkResult({required this.id, required this.ok, this.code, this.message});

  final int id;
  final bool ok;
  final String? code;
  final String? message;
}

List<NoticeBulkResult> parseBulkResults(Map<String, dynamic> j) => _list(
  j['results'],
  (m) => NoticeBulkResult(id: _i(m['id']), ok: m['ok'] == true, code: _s(m['code']), message: _s(m['message'])),
);

/// Uyarı kodları için yerel Türkçe metin (sunucu metni yoksa).
String noticeWarningText(NoticeWarning w) {
  if (w.message.isNotEmpty) return w.message;
  return switch (w.code) {
    'REFERENCE_OTHER_APARTMENT' => 'Açıklamadaki referans kodu başka bir daireye ait.',
    'SAME_FILE_OTHER_NOTICE' => 'Aynı dosya başka bir bildirimde de var.',
    'POSSIBLE_DUPLICATE' => 'Yakın tarihte aynı tutarda tahsilat ya da bekleyen bildirim var.',
    'NAME_MISMATCH' => 'Gönderen adı dairedeki kişilerle eşleşmiyor.',
    'OVERPAYMENT' => 'Tutar hesabın borcundan fazla.',
    'OLD_DATE' => 'Ödeme tarihi 60 günden eski.',
    _ => 'Uyarı',
  };
}

/// Dosya adı için kısa boyut metni ("2,4 MB").
String noticeSizeText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
