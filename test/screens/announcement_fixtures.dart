// Platform Faz 3a (Duyuru ve Bildirim): ekran / pencere testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (server/src/modules/announcement_*.js): kayıtlar bellekte tutulur,
// yanıtlar sunucunun gerçek JSON biçiminde üretilip modellerle ayrıştırılır; listeler süzgeç / arama /
// sayfalama (limit-offset ve before_id imleci) uygular; yazmalar kaydı değiştirir ve sunucu kurallarını
// (yayınlanmış duyuruda yalnız başlık/metin, INVALID_STATE, NO_RECIPIENTS, zamanlama aralığı, kurulda
// alıcı adı yok) aynı Türkçe mesajlarla uygular. Yarış testleri için her çağrı kuyruktaki bir kapıyı
// bekleyebilir (yanıt çağrı ANINDA hesaplanır, kapı açılınca teslim edilir).
import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';

import 'people_fixtures.dart';

/// Bir alıcı satırı (sunucudaki `announcement_recipients` + kişi).
Map<String, dynamic> annRecipient(
  int personId,
  String name, {
  List<String> apartments = const <String>['A Blok - 5'],
  bool account = true,
  DateTime? readAt,
  String emailStatus = 'none',
}) => <String, dynamic>{
  'person_id': personId,
  'full_name': name,
  'apartments': apartments,
  'has_account': account,
  'read_at': readAt,
  'email_status': emailStatus,
};

/// Sunucudaki bir duyuru satırı.
Map<String, dynamic> annRow(
  int id, {
  String title = 'Asansör bakımı',
  String body = 'Yarın 10:00-12:00 arası asansör hizmet vermeyecek.',
  String importance = 'normal',
  String status = 'published',
  String targetType = 'site',
  List<int> blockIds = const <int>[],
  List<int> apartmentIds = const <int>[],
  List<String> labels = const <String>['Tüm site'],
  bool sendEmail = false,
  DateTime? publishAt,
  DateTime? publishedAt,
  DateTime? editedAt,
  int editCount = 0,
  DateTime? createdAt,
  String createdBy = 'Site Yöneticisi',
  List<Map<String, dynamic>>? recipients,
}) {
  final published = status == 'published' || status == 'withdrawn';
  return <String, dynamic>{
    'id': id,
    'title': title,
    'body': body,
    'importance': importance,
    'status': status,
    'target_type': targetType,
    'block_ids': List<int>.of(blockIds),
    'apartment_ids': List<int>.of(apartmentIds),
    'labels': List<String>.of(labels),
    'send_email': sendEmail,
    'publish_at': publishAt,
    'published_at': publishedAt ?? (published ? DateTime.utc(2026, 10, 15, 21, 30) : null),
    'edited_at': editedAt,
    'edit_count': editCount,
    'created_at': createdAt ?? DateTime.utc(2026, 10, 15, 20),
    'created_by_name': createdBy,
    'recipients': recipients ?? (published ? _defaultRecipients() : <Map<String, dynamic>>[]),
  };
}

List<Map<String, dynamic>> _defaultRecipients() => <Map<String, dynamic>>[
  annRecipient(1, 'Ayşe Yılmaz', readAt: DateTime.utc(2026, 10, 16, 5, 15), emailStatus: 'sent'),
  annRecipient(2, 'Mehmet Demir', apartments: const <String>['A Blok - 6']),
  annRecipient(3, 'Zeynep Kaya', apartments: const <String>['B Blok - 2'], account: false),
];

String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

/// Sakin gelen kutusundaki bir satır (sunucudaki `mapInboxRow` + tam kayıt alanları).
Map<String, dynamic> inboxRow(
  int id, {
  String title = 'Su kesintisi',
  String body = 'Yarın 09:00-13:00 arası su kesintisi olacaktır. Lütfen önlem alın.',
  String importance = 'normal',
  int siteCode = 11,
  String siteName = 'Gül Sitesi',
  DateTime? publishedAt,
  DateTime? editedAt,
  bool read = false,
  String status = 'published',
}) => <String, dynamic>{
  'id': id,
  'site_code': siteCode,
  'site_name': siteName,
  'title': title,
  'body': body,
  'importance': importance,
  'published_at': publishedAt ?? DateTime.utc(2026, 10, 16, 8).add(Duration(minutes: id)),
  'edited_at': editedAt,
  'read_at': read ? DateTime.utc(2026, 10, 16, 9) : null,
  'status': status,
};

/// Duyuru ve Bildirim uçları için sahte servis (Kişi ve Daire Kayıtları sahtesinin üstüne kurulur:
/// site listesi, blok yapısı, daire seçici ve oturum oradan gelir).
class AnnouncementFakeAuth extends PeopleFakeAuth {
  AnnouncementFakeAuth({
    super.role,
    super.sites,
    super.blocks,
    List<Map<String, dynamic>>? announcements,
    List<Map<String, dynamic>>? inbox,
  }) : rows = <int, Map<String, dynamic>>{
         for (final row in announcements ?? <Map<String, dynamic>>[]) row['id'] as int: row,
       },
       inboxRows = inbox ?? <Map<String, dynamic>>[];

  /// Standart veri: yayında (okunma 1/3), taslak, zamanlanmış ve geri çekilmiş duyuru.
  factory AnnouncementFakeAuth.seeded({UserRole role = UserRole.siteManager}) {
    final auth = AnnouncementFakeAuth(role: role);
    auth.rows[41] = annRow(
      41,
      title: 'Asansör bakımı',
      importance: 'urgent',
      sendEmail: true,
      publishedAt: DateTime.utc(2026, 10, 15, 21, 30),
      editedAt: DateTime.utc(2026, 10, 16, 6),
      editCount: 1,
    );
    auth.rows[40] = annRow(
      40,
      title: 'Aidat hatırlatması',
      body: 'Ekim ayı aidatı ayın 20\'sine kadar ödenmelidir.',
      status: 'draft',
      targetType: 'blocks',
      blockIds: const <int>[1],
      labels: const <String>['A Blok'],
    );
    auth.rows[39] = annRow(
      39,
      title: 'Bahçe düzenlemesi',
      body: 'Bahçe düzenlemesi hafta sonu yapılacaktır.',
      status: 'scheduled',
      publishAt: DateTime.utc(2026, 11, 20, 11, 30),
    );
    auth.rows[38] = annRow(
      38,
      title: 'Yanlış duyuru',
      status: 'withdrawn',
      publishedAt: DateTime.utc(2026, 10, 10, 9),
    );
    return auth;
  }

  /// Sunucudaki duyurular (yönetici tarafı).
  final Map<int, Map<String, dynamic>> rows;

  /// Sakin gelen kutusu (yalnız bu kullanıcının alıcı olduğu duyurular).
  final List<Map<String, dynamic>> inboxRows;

  /// Önizleme yanıtı ve yayın anındaki kitle (`recipients`).
  Map<String, dynamic> audience = <String, dynamic>{
    'people': 48,
    'apartments': 30,
    'with_account': 40,
    'with_email': 44,
    'without_email': 4,
  };
  List<Map<String, dynamic>> audienceRecipients = _defaultRecipients();

  /// Kurul üyesi gibi davranır: alıcılar ve önizleme 403 döner, yanıtlarda oluşturan adı yoktur ve KÜÇÜK HEDEFTE
  /// (1-4 alıcı) okunma / e-posta sayıları `null`dır (sunucu `redactForBoard` ile aynı).
  bool boardReadOnly = false;

  /// true: eski sunucu — `target.blocks` / `target.apartments` (kimlikle eşleşen EKLEMELİ listeler) yoktur.
  bool legacyTarget = false;

  /// Sunucunun saati (zamanlama doğrulaması).
  DateTime Function() clock = DateTime.now;

  /// Gönderim sürerken davranış: dolu ise her yazma kapıyı bekler.
  Completer<void>? announcementWriteGate;
  Object? announcementWriteError;
  Object? announcementListError;
  Object? announcementDetailError;
  Object? recipientsError;
  Object? previewError;

  final List<Completer<void>> announcementListGates = <Completer<void>>[];
  final List<Completer<void>> recipientsGates = <Completer<void>>[];
  Completer<void>? announcementDetailGate;
  Completer<void>? previewGate;

  // --- Çağrı kayıtları -------------------------------------------------------------------------
  final List<({int site, String? status, String? query, int limit, int offset})> announcementListCalls =
      <({int site, String? status, String? query, int limit, int offset})>[];
  final List<int> announcementGetCalls = <int>[];
  final List<({int id, String? read, String? query, int limit, int offset})> recipientCalls =
      <({int id, String? read, String? query, int limit, int offset})>[];
  final List<({Map<String, dynamic> target, bool sendEmail})> previewCalls =
      <({Map<String, dynamic> target, bool sendEmail})>[];
  final List<Map<String, Object?>> announcementCreateCalls = <Map<String, Object?>>[];
  final List<({int id, Map<String, Object?> fields})> announcementUpdateCalls =
      <({int id, Map<String, Object?> fields})>[];
  final List<int> announcementPublishCalls = <int>[];
  final List<int> announcementWithdrawCalls = <int>[];
  final List<int> announcementDeleteCalls = <int>[];

  // --- Sakin tarafı -----------------------------------------------------------------------------
  Object? inboxError;
  Object? myDetailError;
  Object? readError;
  Object? readAllError;
  Object? summaryError;
  Object? prefsError;
  Object? prefsSaveError;
  bool prefsEmail = true;

  /// Saklanan borç hatırlatma e-postası tercihi (sunucu `email_finance_reminders`; etkin değer bastırmayla birlikte).
  bool prefsFinance = true;

  /// Adres e-postadaki "abonelikten çık" bağlantısıyla bastırılmış (sunucu `email_suppressed`).
  bool prefsSuppressed = false;

  /// true: dahili daire hesabının iletişim adresi — kullanıcı açsa da bastırma kalkmaz.
  bool prefsSuppressionPersists = false;

  /// true: eski sunucu — yanıtta `email_suppressed` alanı yoktur.
  bool prefsLegacy = false;
  final List<Completer<void>> inboxGates = <Completer<void>>[];
  Completer<void>? myDetailGate;
  Completer<void>? readGate;
  Completer<void>? prefsGate;
  Completer<void>? prefsSaveGate;
  /// Gelen kutusu yanıtındaki isteğe bağlı `retention_days` (null: alan yok).
  int? retentionDays;
  final List<({int limit, int? before, int? site})> inboxCalls = <({int limit, int? before, int? site})>[];
  final List<int> myDetailCalls = <int>[];
  final List<int> readCalls = <int>[];
  final List<int?> readAllCalls = <int?>[];
  int summaryCalls = 0;
  int prefsGetCalls = 0;
  /// `email_announcements` değeri içeren PUT'lar (yalnız o anahtar verilmişse).
  final List<bool> prefsSetCalls = <bool>[];

  /// `email_finance_reminders` değeri içeren PUT'lar (yalnız o anahtar verilmişse).
  final List<bool> prefsFinanceSetCalls = <bool>[];

  /// Her PUT'ta VERİLEN anahtarlar (verilmeyen null): hangi anahtarların gövdeye girdiğini doğrular.
  final List<({bool? announcements, bool? finance})> prefsSetRequests = <({bool? announcements, bool? finance})>[];

  Future<void> _gate(List<Completer<void>> queue) async {
    if (queue.isEmpty) return;
    await queue.removeAt(0).future;
  }

  /// Gerçek istemci gibi: kod için Türkçe karşılık varsa o, yoksa sunucunun kendi metni.
  ApiException _coded(String code, int status, [String? serverText]) => ApiException(
    AuthApi.messageForErrorCode(code) ?? serverText ?? code,
    statusCode: status,
    code: code,
  );

  ApiException _notFound() => _coded('ANNOUNCEMENT_NOT_FOUND', 404);

  ApiException _invalidBody(String message) =>
      ApiException(message, statusCode: 400, code: 'INVALID_BODY');

  // --- Sunucu biçiminde JSON üreticileri -------------------------------------------------------

  List<Map<String, dynamic>> _recipientsOf(Map<String, dynamic> row) =>
      (row['recipients'] as List).cast<Map<String, dynamic>>();

  /// Kurul + 1-4 alıcı: sunucu okunma / e-posta sayılarını gizler.
  bool _hiddenForBoard(Map<String, dynamic> row) {
    final count = _recipientsOf(row).length;
    return boardReadOnly && count >= 1 && count < 5;
  }

  Map<String, dynamic> _summaryJson(Map<String, dynamic> row) {
    final recipients = _recipientsOf(row);
    final body = row['body'] as String;
    return <String, dynamic>{
      'id': row['id'],
      'title': row['title'],
      'body_preview': body.length > 160 ? '${body.substring(0, 159)}…' : body,
      'importance': row['importance'],
      'status': row['status'],
      'target_type': row['target_type'],
      'publish_at': _iso(row['publish_at'] as DateTime?),
      'published_at': _iso(row['published_at'] as DateTime?),
      'edited_at': _iso(row['edited_at'] as DateTime?),
      'send_email': row['send_email'],
      'recipient_count': recipients.length,
      'read_count': _hiddenForBoard(row) ? null : recipients.where((r) => r['read_at'] != null).length,
      'created_at': _iso(row['created_at'] as DateTime?),
      'created_by_name': boardReadOnly ? null : row['created_by_name'],
    };
  }

  Map<String, dynamic> _detailJson(Map<String, dynamic> row) {
    final recipients = _recipientsOf(row);
    final hidden = _hiddenForBoard(row);
    final read = recipients.where((r) => r['read_at'] != null).length;
    final counts = <String, int>{
      'sent': 0,
      'failed': 0,
      'no_address': 0,
      'skipped_pref': 0,
      'capped': 0,
      'duplicate': 0,
      'pending': 0,
    };
    var requested = 0;
    for (final r in recipients) {
      final status = r['email_status'] as String;
      if (status != 'none' && counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
        requested++;
      }
    }
    return <String, dynamic>{
      ..._summaryJson(row),
      'body': row['body'],
      'target': <String, dynamic>{
        'type': row['target_type'],
        'block_ids': row['block_ids'],
        'apartment_ids': row['apartment_ids'],
        'labels': row['labels'],
        if (!legacyTarget) ...<String, dynamic>{
          'blocks': <Map<String, dynamic>>[
            for (final id in row['block_ids'] as List<int>)
              <String, dynamic>{'id': id, 'name': _blockName(id)},
          ],
          'apartments': <Map<String, dynamic>>[
            for (final id in row['apartment_ids'] as List<int>)
              <String, dynamic>{'id': id, 'label': _apartmentLabel(id)},
          ],
        },
      },
      'stats': hidden
          ? <String, dynamic>{
              'recipients': recipients.length,
              'read': null,
              'unread': null,
              'email': <String, dynamic>{
                'requested': null,
                for (final key in counts.keys) key: null,
              },
            }
          : <String, dynamic>{
              'recipients': recipients.length,
              'read': read,
              'unread': recipients.length - read,
              'email': <String, dynamic>{'requested': requested, ...counts},
            },
      'edit_count': row['edit_count'],
      // Belge ekleri (Faz 3b-A): satırda `attachments` varsa sunucu gibi döner.
      if (row['attachments'] != null) 'attachments': row['attachments'],
    };
  }

  String _blockName(int id) {
    for (final b in blocks) {
      if (b.id == id) return b.name;
    }
    return 'Blok $id';
  }

  String _apartmentLabel(int id) => (apartmentsJson[id]?['label'] as String?) ?? 'Daire $id';

  AnnouncementDetail _detail(Map<String, dynamic> row) => AnnouncementDetail.fromJson(_detailJson(row));

  // --- Yönetici uçları -------------------------------------------------------------------------

  @override
  Future<AnnouncementPage> listAnnouncements(
    int siteCode, {
    String? status,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    announcementListCalls.add((site: siteCode, status: status, query: query, limit: limit, offset: offset));
    final q = (query ?? '').trim().toLowerCase();
    final filtered = rows.values.where((row) {
      if (status != null && status != 'all' && row['status'] != status) return false;
      if (q.isEmpty) return true;
      return (row['title'] as String).toLowerCase().contains(q) ||
          (row['body'] as String).toLowerCase().contains(q);
    }).toList();
    bool open(Map<String, dynamic> row) => row['status'] == 'draft' || row['status'] == 'scheduled';
    DateTime when(Map<String, dynamic> row) =>
        (row['published_at'] as DateTime?) ?? (row['created_at'] as DateTime);
    filtered.sort((a, b) {
      if (open(a) != open(b)) return open(a) ? -1 : 1;
      final byTime = when(b).compareTo(when(a));
      return byTime != 0 ? byTime : (b['id'] as int).compareTo(a['id'] as int);
    });
    final page = filtered.skip(offset).take(maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!));
    final result = AnnouncementPage(
      items: [for (final row in page) AnnouncementSummary.fromJson(_summaryJson(row))],
      total: totalOverride ?? filtered.length,
    );
    await _gate(announcementListGates);
    final error = announcementListError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<AnnouncementDetail> getAnnouncement(int siteCode, int announcementId) async {
    announcementGetCalls.add(announcementId);
    final row = rows[announcementId];
    final snapshot = row == null ? null : _detail(row);
    final gate = announcementDetailGate;
    if (gate != null) await gate.future;
    final error = announcementDetailError;
    if (error != null) throw error;
    if (snapshot == null) throw _notFound();
    return snapshot;
  }

  @override
  Future<AnnouncementRecipientPage> listAnnouncementRecipients(
    int siteCode,
    int announcementId, {
    String? read,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    recipientCalls.add((id: announcementId, read: read, query: query, limit: limit, offset: offset));
    if (boardReadOnly) throw _coded('FORBIDDEN_ROLE', 403);
    final row = rows[announcementId];
    if (row == null) throw _notFound();
    final q = (query ?? '').trim().toLowerCase();
    final filtered = _recipientsOf(row).where((r) {
      if (read == 'true' && r['read_at'] == null) return false;
      if (read == 'false' && r['read_at'] != null) return false;
      if (q.isEmpty) return true;
      return (r['full_name'] as String).toLowerCase().contains(q) ||
          (r['apartments'] as List).any((a) => (a as String).toLowerCase().contains(q));
    }).toList();
    final page = filtered.skip(offset).take(maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!));
    final result = AnnouncementRecipientPage.fromJson(<String, dynamic>{
      'items': [
        for (final r in page) <String, dynamic>{...r, 'read_at': _iso(r['read_at'] as DateTime?)},
      ],
      'total': filtered.length,
    });
    await _gate(recipientsGates);
    final error = recipientsError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<AudiencePreview> previewAnnouncementAudience(
    int siteCode,
    AnnouncementTargetInput target, {
    bool sendEmail = false,
  }) async {
    previewCalls.add((target: target.toJson(), sendEmail: sendEmail));
    if (boardReadOnly) throw _coded('FORBIDDEN_ROLE', 403);
    final gate = previewGate;
    if (gate != null) await gate.future;
    final error = previewError;
    if (error != null) throw error;
    return AudiencePreview.fromJson(audience);
  }

  Future<void> _writeWait() async {
    final gate = announcementWriteGate;
    if (gate != null) await gate.future;
    final error = announcementWriteError;
    if (error != null) throw error;
  }

  /// Belge eki satırları (başlık sahte: "Belge N").
  static List<Map<String, dynamic>> _attachmentRows(List<int> ids) => <Map<String, dynamic>>[
    for (final id in ids)
      <String, dynamic>{
        'document_id': id,
        'title': 'Belge $id',
        'file_name': 'belge-$id.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 1048576,
        'available': true,
      },
  ];

  static String _normalize(String text) => text.trim().replaceAll(RegExp(r'[ \t]+'), ' ');

  void _validateText(String title, String body) {
    if (_normalize(title).isEmpty) throw _invalidBody('Başlık boş olamaz.');
    if (_normalize(title).runes.length > 120) throw _invalidBody('Başlık en fazla 120 karakter olabilir.');
    if (body.trim().isEmpty) throw _invalidBody('Duyuru metni boş olamaz.');
    if (body.trim().runes.length > 5000) throw _invalidBody('Duyuru metni en fazla 5000 karakter olabilir.');
  }

  void _validateSchedule(DateTime at) {
    final now = clock().toUtc();
    if (at.difference(now) < const Duration(minutes: 1)) {
      throw _coded('INVALID_SCHEDULE', 400, 'Yayın zamanı en az 1 dakika sonrası olmalıdır.');
    }
    if (at.isAfter(istanbulCalendarYearAfter(now))) {
      throw _coded('INVALID_SCHEDULE', 400, 'Yayın zamanı en fazla 1 yıl sonrası olabilir.');
    }
  }

  void _publishRow(Map<String, dynamic> row) {
    final status = row['status'] as String;
    if (status != 'draft' && status != 'scheduled') {
      throw _coded(
        'INVALID_STATE',
        409,
        status == 'published' ? 'Duyuru zaten yayınlanmış.' : 'Geri çekilen duyuru yeniden yayınlanamaz.',
      );
    }
    if (audienceRecipients.isEmpty) throw _coded('NO_RECIPIENTS', 409);
    row['status'] = 'published';
    row['published_at'] = clock().toUtc();
    row['publish_at'] = null;
    row['recipients'] = [
      for (final r in audienceRecipients) <String, dynamic>{...r, 'read_at': null},
    ];
  }

  @override
  Future<AnnouncementDetail> createAnnouncement(
    int siteCode, {
    required String title,
    required String body,
    required AnnouncementTargetInput target,
    AnnouncementImportance importance = AnnouncementImportance.normal,
    bool sendEmail = false,
    String publish = 'draft',
    DateTime? publishAt,
    List<int>? documentIds,
  }) async {
    announcementCreateCalls.add(<String, Object?>{
      'title': title,
      'body': body,
      'target': target.toJson(),
      'importance': importance.apiValue,
      'send_email': sendEmail,
      'publish': publish,
      'publish_at': publishAt,
      'document_ids': ?documentIds,
    });
    await _writeWait();
    _validateText(title, body);
    if (publish == 'schedule') {
      if (publishAt == null) throw _coded('INVALID_SCHEDULE', 400, 'Zamanlı yayın için yayın zamanı gerekli.');
      _validateSchedule(publishAt.toUtc());
    }
    final id = (rows.keys.isEmpty ? 0 : rows.keys.reduce((a, b) => a > b ? a : b)) + 1;
    final row = annRow(
      id,
      title: _normalize(title),
      body: body.trim(),
      importance: importance.apiValue,
      status: publish == 'schedule' ? 'scheduled' : 'draft',
      targetType: target.type.apiValue,
      blockIds: target.blockIds,
      apartmentIds: target.apartmentIds,
      labels: switch (target.type) {
        AnnouncementTargetType.site => const <String>['Tüm site'],
        AnnouncementTargetType.blocks => [for (final b in target.blockIds) _blockName(b)],
        AnnouncementTargetType.apartments => [for (final a in target.apartmentIds) _apartmentLabel(a)],
      },
      sendEmail: sendEmail,
      publishAt: publish == 'schedule' ? publishAt!.toUtc() : null,
      createdAt: clock().toUtc(),
    );
    if (documentIds != null && documentIds.isNotEmpty) row['attachments'] = _attachmentRows(documentIds);
    rows[id] = row;
    if (publish == 'now') {
      try {
        _publishRow(row);
      } catch (_) {
        rows.remove(id);
        rethrow;
      }
    }
    return _detail(row);
  }

  @override
  Future<AnnouncementDetail> updateAnnouncement(
    int siteCode,
    int announcementId,
    Map<String, Object?> fields,
  ) async {
    announcementUpdateCalls.add((id: announcementId, fields: Map<String, Object?>.of(fields)));
    await _writeWait();
    final row = rows[announcementId];
    if (row == null) throw _notFound();
    final status = row['status'] as String;
    if (status == 'withdrawn') {
      throw _coded('INVALID_STATE', 409, 'Geri çekilen duyuru düzenlenemez.');
    }
    final publishNow = fields['publish'] == 'now';
    final rest = Map<String, Object?>.of(fields)..remove('publish');
    if (status == 'published' && (publishNow || rest.keys.any((k) => k != 'title' && k != 'body'))) {
      throw _coded('INVALID_STATE', 409, 'Yayınlanmış duyuruda yalnız başlık ve metin değiştirilebilir.');
    }
    // Sunucu gibi: `publish: 'now'` düzenlemeyle AYNI işlemde yayınlar; yayın başarısız olursa (örn. kitle
    // yok) düzenleme de geri alınır (yarım kalmış durum yok).
    final backup = Map<String, dynamic>.of(row);
    try {
      _applyFields(row, rest);
      if (publishNow) _publishRow(row);
    } catch (_) {
      row
        ..clear()
        ..addAll(backup);
      rethrow;
    }
    return _detail(row);
  }

  void _applyFields(Map<String, dynamic> row, Map<String, Object?> fields) {
    final status = row['status'] as String;
    _validateText(
      (fields['title'] as String?) ?? row['title'] as String,
      (fields['body'] as String?) ?? row['body'] as String,
    );
    var edited = false;
    if (fields.containsKey('title')) {
      final next = _normalize(fields['title']! as String);
      edited = edited || next != row['title'];
      row['title'] = next;
    }
    if (fields.containsKey('body')) {
      final next = (fields['body']! as String).trim();
      edited = edited || next != row['body'];
      row['body'] = next;
    }
    if (status == 'published') {
      if (edited) {
        row['edited_at'] = clock().toUtc();
        row['edit_count'] = (row['edit_count'] as int) + 1;
      }
      return;
    }
    if (fields.containsKey('document_ids')) {
      row['attachments'] = _attachmentRows((fields['document_ids']! as List).cast<int>());
    }
    if (fields.containsKey('importance')) row['importance'] = fields['importance'];
    if (fields.containsKey('send_email')) row['send_email'] = fields['send_email'];
    if (fields.containsKey('target')) {
      final target = fields['target']! as Map<String, dynamic>;
      row['target_type'] = target['type'];
      row['block_ids'] = List<int>.of((target['block_ids'] as List?)?.cast<int>() ?? const <int>[]);
      row['apartment_ids'] = List<int>.of((target['apartment_ids'] as List?)?.cast<int>() ?? const <int>[]);
      row['labels'] = switch (target['type']) {
        'blocks' => [for (final b in row['block_ids'] as List<int>) _blockName(b)],
        'apartments' => [for (final a in row['apartment_ids'] as List<int>) _apartmentLabel(a)],
        _ => const <String>['Tüm site'],
      };
    }
    if (fields.containsKey('publish_at')) {
      final raw = fields['publish_at'];
      if (raw == null) {
        row['publish_at'] = null;
        row['status'] = 'draft';
      } else {
        final at = DateTime.parse(raw as String).toUtc();
        _validateSchedule(at);
        row['publish_at'] = at;
        row['status'] = 'scheduled';
      }
    }
  }

  @override
  Future<AnnouncementDetail> publishAnnouncement(int siteCode, int announcementId) async {
    announcementPublishCalls.add(announcementId);
    await _writeWait();
    final row = rows[announcementId];
    if (row == null) throw _notFound();
    _publishRow(row);
    return _detail(row);
  }

  @override
  Future<AnnouncementDetail> withdrawAnnouncement(int siteCode, int announcementId) async {
    announcementWithdrawCalls.add(announcementId);
    await _writeWait();
    final row = rows[announcementId];
    if (row == null) throw _notFound();
    if (row['status'] != 'published') {
      throw _coded('INVALID_STATE', 409, 'Yalnız yayındaki duyuru geri çekilebilir.');
    }
    row['status'] = 'withdrawn';
    return _detail(row);
  }

  @override
  Future<void> deleteAnnouncement(int siteCode, int announcementId) async {
    announcementDeleteCalls.add(announcementId);
    await _writeWait();
    final row = rows[announcementId];
    if (row == null) throw _notFound();
    if (row['status'] != 'draft' && row['status'] != 'scheduled') {
      throw _coded('INVALID_STATE', 409, 'Yayınlanmış duyuru silinemez; geri çekebilirsiniz.');
    }
    rows.remove(announcementId);
  }

  // --- Sakin uçları ----------------------------------------------------------------------------

  List<Map<String, dynamic>> get _visibleInbox {
    final visible = inboxRows.where((r) => r['status'] == 'published').toList();
    visible.sort((a, b) {
      final byTime = (b['published_at'] as DateTime).compareTo(a['published_at'] as DateTime);
      return byTime != 0 ? byTime : (b['id'] as int).compareTo(a['id'] as int);
    });
    return visible;
  }

  Map<String, dynamic> _inboxJson(Map<String, dynamic> row, {required bool full}) {
    final body = row['body'] as String;
    return <String, dynamic>{
      'id': row['id'],
      'site_code': row['site_code'],
      'site_name': row['site_name'],
      'title': row['title'],
      if (full) 'body': body else 'body_preview': body.length > 160 ? '${body.substring(0, 159)}…' : body,
      'importance': row['importance'],
      'published_at': _iso(row['published_at'] as DateTime?),
      'edited_at': _iso(row['edited_at'] as DateTime?),
      'is_read': row['read_at'] != null,
      if (full) 'read_at': _iso(row['read_at'] as DateTime?),
      if (full && row['attachments'] != null) 'attachments': row['attachments'],
    };
  }

  @override
  Future<ResidentAnnouncementPage> listMyAnnouncements({
    int limit = 30,
    int? beforeId,
    int? siteCode,
  }) async {
    inboxCalls.add((limit: limit, before: beforeId, site: siteCode));
    var visible = _visibleInbox;
    if (siteCode != null) visible = visible.where((r) => r['site_code'] == siteCode).toList();
    if (beforeId != null) {
      final cursor = visible.indexWhere((r) => r['id'] == beforeId);
      visible = cursor < 0 ? <Map<String, dynamic>>[] : visible.sublist(cursor + 1);
    }
    final size = maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!);
    final page = visible.take(size).toList();
    final result = ResidentAnnouncementPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _inboxJson(r, full: false)],
      'next_before_id': visible.length > size && page.isNotEmpty ? page.last['id'] : null,
      if (retentionDays != null) 'retention_days': retentionDays,
    });
    await _gate(inboxGates);
    final error = inboxError;
    if (error != null) throw error;
    return result;
  }

  Map<String, dynamic>? _inboxById(int id) {
    for (final row in inboxRows) {
      if (row['id'] == id && row['status'] == 'published') return row;
    }
    return null;
  }

  @override
  Future<ResidentAnnouncement> getMyAnnouncement(int announcementId) async {
    myDetailCalls.add(announcementId);
    final row = _inboxById(announcementId);
    final snapshot = row == null ? null : ResidentAnnouncement.fromJson(_inboxJson(row, full: true));
    final gate = myDetailGate;
    if (gate != null) await gate.future;
    final error = myDetailError;
    if (error != null) throw error;
    if (snapshot == null) throw _notFound();
    return snapshot;
  }

  @override
  Future<DateTime?> markAnnouncementRead(int announcementId) async {
    readCalls.add(announcementId);
    final gate = readGate;
    if (gate != null) await gate.future;
    final error = readError;
    if (error != null) throw error;
    final row = _inboxById(announcementId);
    if (row == null) throw _notFound();
    row['read_at'] ??= DateTime.utc(2026, 10, 16, 9);
    return row['read_at'] as DateTime;
  }

  @override
  Future<int> markAllAnnouncementsRead({int? siteCode}) async {
    readAllCalls.add(siteCode);
    final error = readAllError;
    if (error != null) throw error;
    var marked = 0;
    for (final row in inboxRows) {
      if (row['status'] != 'published' || row['read_at'] != null) continue;
      if (siteCode != null && row['site_code'] != siteCode) continue;
      row['read_at'] = DateTime.utc(2026, 10, 16, 9);
      marked++;
    }
    return marked;
  }

  @override
  Future<NotificationSummary> getNotificationSummary() async {
    summaryCalls++;
    final error = summaryError;
    if (error != null) throw error;
    final visible = _visibleInbox;
    final unread = visible.where((r) => r['read_at'] == null).toList();
    return NotificationSummary.fromJson(<String, dynamic>{
      'unread_announcements': unread.length,
      'unread_urgent': unread.where((r) => r['importance'] == 'urgent').length,
      'latest_announcement_id': visible.isEmpty ? null : visible.first['id'],
      'latest_published_at': visible.isEmpty ? null : _iso(visible.first['published_at'] as DateTime?),
      'server_time': _iso(clock()),
    });
  }

  /// Sunucunun `email_announcements` = saklanan tercih VE bastırılmamış kuralı.
  Map<String, dynamic> _prefsJson() => <String, dynamic>{
    'email_announcements': prefsEmail && !prefsSuppressed,
    'push_announcements': true,
    'push_available': false,
    if (!prefsLegacy) 'email_suppressed': prefsSuppressed,
    if (!prefsLegacy) 'email_finance_reminders': prefsFinance && !prefsSuppressed,
  };

  @override
  Future<NotificationPrefs> getNotificationPreferences() async {
    prefsGetCalls++;
    final gate = prefsGate;
    if (gate != null) await gate.future;
    final error = prefsError;
    if (error != null) throw error;
    return NotificationPrefs.fromJson(_prefsJson());
  }

  @override
  Future<NotificationPrefs> setNotificationPreferences({
    bool? emailAnnouncements,
    bool? emailFinanceReminders,
  }) async {
    if (emailAnnouncements == null && emailFinanceReminders == null) {
      throw ArgumentError('En az bir e-posta tercihi verilmelidir.');
    }
    prefsSetRequests.add((announcements: emailAnnouncements, finance: emailFinanceReminders));
    if (emailAnnouncements != null) prefsSetCalls.add(emailAnnouncements);
    if (emailFinanceReminders != null) prefsFinanceSetCalls.add(emailFinanceReminders);
    final gate = prefsSaveGate;
    if (gate != null) await gate.future;
    final error = prefsSaveError;
    if (error != null) throw error;
    if (emailAnnouncements != null) prefsEmail = emailAnnouncements;
    if (emailFinanceReminders != null) prefsFinance = emailFinanceReminders;
    // Açmak, gerçek hesap e-postasının bastırmasını kaldırır; dahili hesap adresinde kalkmaz.
    final opened = emailAnnouncements == true || emailFinanceReminders == true;
    if (opened && prefsSuppressed && !prefsSuppressionPersists) prefsSuppressed = false;
    return NotificationPrefs.fromJson(
      _prefsJson(),
      fallbackEmail: emailAnnouncements,
      fallbackFinance: emailFinanceReminders,
    );
  }
}

/// Anlam ağacındaki (ekran okuyucunun göreceği) tüm düğüm etiketleri. Üst düğüme BİRLEŞMİŞ düğümler ayrıca
/// sayılmaz; [WidgetTester.ensureSemantics] açıkken çağrılmalıdır.
List<String> semanticLabels(WidgetTester t) {
  final root = t.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) {
      final label = node.getSemanticsData().label;
      if (label.isNotEmpty) labels.add(label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return labels;
}
