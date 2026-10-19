// İş Takibi (arıza, bakım, talep): ekran / pencere / denetleyici testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (docs/PLATFORM_IS_TAKIBI.md): satırlar bellekte sunucunun gerçek JSON biçiminde
// tutulur ve modellerle ayrıştırılır; sakin listesi `open|closed|all` + `before_id` imleci uygular; yönetim listesi
// durum / kategori / öncelik / atanan / arama süzgeci ve sayaçlar verir; kurul iç olayları, telefonu ve kullanıcı
// kodunu GÖRMEZ; görevli yalnız kendine atanmış ya da atanmamış talepleri görür; geçişler sunucu tablosundan gelir
// (INVALID_TRANSITION / WORK_ITEM_CLOSED / FORBIDDEN_ROLE). Hata ve yarış testleri için her çağrı kuyruktaki bir
// hataya ya da kapıya takılabilir.
import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart'
    show DocumentCancelToken, DocumentTransferCancelled;
import 'package:site_kapi_kontrol/services/document_picker.dart'
    show DocumentUploadSource;
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';

import 'people_fixtures.dart';

/// Sahte kimlik doğrulama (yalnız servise `authService` olarak verilir).
class WorkFakeAuth extends PeopleFakeAuth {
  WorkFakeAuth({super.role});
}

/// Görevli / yönetici olarak oturum açmış kullanıcının kodu.
const int kWorkSelfCode = 7;

const Map<String, List<String>> kWorkTransitions = <String, List<String>>{
  'yeni': <String>['islemde', 'beklemede', 'cozuldu', 'iptal'],
  'islemde': <String>['beklemede', 'cozuldu', 'iptal'],
  'beklemede': <String>['islemde', 'cozuldu', 'iptal'],
  'cozuldu': <String>['kapandi', 'islemde'],
  'kapandi': <String>[],
  'iptal': <String>[],
};

bool _terminal(Object? status) => status == 'kapandi' || status == 'iptal';

/// Sakin görünümündeki talep (`MyItem`).
Map<String, dynamic> wkResident(
  int id, {
  String title = 'Asansör çalışmıyor',
  String description = 'B blok asansörü iki gündür kapalı.',
  String status = 'yeni',
  String category = 'ariza',
  String location = 'ortak_alan',
  bool urgent = false,
  bool unread = false,
  bool hasAssignee = false,
  int site = 11,
  String siteName = 'Gül Sitesi',
  String? dueDate,
  String? apartmentLabel,
}) {
  final terminal = _terminal(status);
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'site_name': siteName,
    'category': category,
    'location_type': location,
    'title': title,
    'description': description,
    'status': status,
    'urgent': urgent,
    'apartment': apartmentLabel == null
        ? null
        : <String, dynamic>{'id': 301, 'label': apartmentLabel},
    'block': null,
    'has_assignee': hasAssignee,
    'due_date': dueDate,
    'created_at': '2026-10-15T09:00:00Z',
    'updated_at': '2026-10-16T10:30:00Z',
    'closed_at': terminal ? '2026-10-16T10:30:00Z' : null,
    'unread': unread,
    'can_cancel': status == 'yeni',
    'can_comment': !terminal,
  };
}

/// Yönetim görünümündeki talep (`Item`).
Map<String, dynamic> wkManaged(
  int id, {
  String title = 'Asansör çalışmıyor',
  String description = 'B blok asansörü iki gündür kapalı.',
  String status = 'yeni',
  String priority = 'normal',
  String category = 'ariza',
  String location = 'ortak_alan',
  bool residentUrgent = false,
  String requester = 'Ayşe Yılmaz',
  String? phone = '+905551112233',
  int? assignedCode,
  String? assignedName,
  int site = 11,
  String? dueDate,
}) {
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'category': category,
    'location_type': location,
    'title': title,
    'description': description,
    'status': status,
    'priority': priority,
    'resident_urgent': residentUrgent,
    'apartment': null,
    'block': <String, dynamic>{'id': 2, 'name': 'B Blok'},
    'requester': <String, dynamic>{
      'user_code': 4001,
      'name': requester,
      'phone': phone,
    },
    'assigned_to': assignedCode == null
        ? null
        : <String, dynamic>{'user_code': assignedCode, 'name': assignedName},
    'due_date': dueDate,
    'created_at': '2026-10-15T09:00:00Z',
    'updated_at': '2026-10-16T10:30:00Z',
    'closed_at': _terminal(status) ? '2026-10-16T10:30:00Z' : null,
  };
}

/// Olay (yönetim biçimiyle saklanır; sakin / kurul çıktısında sunucu gibi sadeleştirilir).
Map<String, dynamic> wkEvent(
  int id, {
  String type = 'comment',
  String visibility = 'public',
  String actorKind = 'resident',
  String actorName = 'Ayşe Yılmaz',
  String? from,
  String? to,
  String? body,
  String? fromLabel,
  String? toLabel,
  String at = '2026-10-15T09:00:00Z',
}) {
  return <String, dynamic>{
    'id': id,
    'type': type,
    'visibility': visibility,
    'actor_kind': actorKind,
    'actor': <String, dynamic>{'user_code': 4001, 'name': actorName},
    'from': from,
    'to': to,
    'body': body,
    if (type == 'assigned') 'from_label': fromLabel,
    if (type == 'assigned') 'to_label': toLabel,
    'created_at': at,
  };
}

/// Geçerli 1x1 PNG (67 bayt): sahte sunucunun içerik yanıtı ve seçilen fotoğraf baytları.
final Uint8List kWkPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Fotoğraf eki satırı (sunucunun YÖNETİM görünümü biçimi: gerçek yükleyen adı; sakin görünümünü sahte servis
/// üretir). [kind]: `resident` (talebi açan sakin) | `management`.
Map<String, dynamic> wkAttachment(
  int id, {
  int workItemId = 1,
  String fileName = 'ariza.jpg',
  String mime = 'image/jpeg',
  int size = 204800,
  String status = 'ready',
  String uploadedBy = 'Ayşe Yılmaz',
  String kind = 'resident',
  bool mine = false,
  String at = '2026-10-15T09:05:00Z',
}) {
  return <String, dynamic>{
    'id': id,
    'work_item_id': workItemId,
    'file_name': fileName,
    'mime_type': mime,
    'size_bytes': size,
    'status': status,
    'uploaded_by_kind': kind,
    'uploaded_by_name': uploadedBy,
    'uploaded_by_me': mine,
    'created_at': at,
  };
}

/// Rapor gövdesi (`GET .../work-items/report`); [empty] true: hareketsiz dönem.
Map<String, dynamic> wkReportJson({
  required DateTime from,
  required DateTime to,
  bool empty = false,
}) {
  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (empty) {
    return <String, dynamic>{
      'from': day(from),
      'to': day(to),
      'generated_at': '2026-10-19T11:02:00Z',
      'totals': <String, dynamic>{
        'opened': 0,
        'resolved': 0,
        'closed': 0,
        'cancelled': 0,
        'open_now': 0,
        'overdue_now': 0,
        'avg_resolution_hours': null,
        'median_resolution_hours': null,
      },
      'by_assignee': <Object>[],
      'by_category': <Object>[],
    };
  }
  return <String, dynamic>{
    'from': day(from),
    'to': day(to),
    'generated_at': '2026-10-19T11:02:00Z',
    'totals': <String, dynamic>{
      'opened': 12,
      'resolved': 7,
      'closed': 5,
      'cancelled': 1,
      'open_now': 4,
      'overdue_now': 2,
      'avg_resolution_hours': 30.4,
      'median_resolution_hours': 20,
    },
    'by_assignee': <Object>[
      <String, dynamic>{
        'user_code': kWorkSelfCode,
        'name': 'Ben Yönetici',
        'open_now': 1,
        'overdue_now': 0,
        'resolved': 4,
        'avg_resolution_hours': 12.5,
        'on_time_rate': 0.75,
      },
      <String, dynamic>{
        'user_code': 9,
        'name': 'Mehmet Usta',
        'open_now': 2,
        'overdue_now': 2,
        'resolved': 3,
        'avg_resolution_hours': 52,
        'on_time_rate': 0.333,
      },
      <String, dynamic>{
        'user_code': null,
        'name': 'Atanmamış',
        'open_now': 1,
        'overdue_now': 0,
        'resolved': 0,
        'avg_resolution_hours': null,
        'on_time_rate': null,
      },
    ],
    'by_category': <Object>[
      <String, dynamic>{'category': 'ariza', 'opened': 8, 'resolved': 5},
      <String, dynamic>{'category': 'bakim', 'opened': 3, 'resolved': 2},
      <String, dynamic>{'category': 'diger', 'opened': 1, 'resolved': 0},
    ],
  };
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _u32(int value) => <int>[(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];

List<int> _pngChunk(String type, List<int> data) {
  final typed = <int>[...type.codeUnits, ...data];
  return <int>[..._u32(data.length), ...typed, ..._u32(_crc32(typed))];
}

/// [width] x [height] BİLDİREN geçerli PNG başlığı (IHDR + küçük IDAT + IEND): boyut çözmeden okunur; piksel verisi
/// gerçek değildir (bellek bombası korumasının testleri için).
Uint8List wkPngHeader({required int width, required int height}) => Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ..._pngChunk('IHDR', <int>[..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]),
  ..._pngChunk('IDAT', <int>[0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]),
  ..._pngChunk('IEND', const <int>[]),
]);

/// Uzantıya uyan içerik imzalı [size] baytlık içerik (JPEG `FF D8 FF`, PNG imzası, `RIFF....WEBP`, GIF `GIF89a`;
/// tanınmayan uzantıda imzasız sıfırlar). Çözülebilir görsel DEĞİLDİR (yalnız tür / boyut denetimleri için).
Uint8List wkImageBytes(String name, {int size = 2048}) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  final header = switch (ext) {
    'jpg' || 'jpeg' => <int>[0xFF, 0xD8, 0xFF, 0xE0],
    'png' => <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    'webp' => <int>[0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
    'gif' => <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
    _ => const <int>[],
  };
  final bytes = Uint8List(size < header.length ? header.length : size);
  bytes.setRange(0, header.length, header);
  return bytes;
}

/// Seçilen fotoğraf: uzantısına uyan içerik imzalı [size] bayt; [png] true ise gerçek 1x1 PNG ([kWkPng]: tür içerikten
/// anlaşılır, adı ne olursa olsun `image/png`).
WorkPhotoPick wkPhoto(String name, {int size = 2048, bool png = false}) =>
    WorkPhotoPick(name: name, bytes: png ? kWkPng : wkImageBytes(name, size: size));

/// Fotoğraf seçici sahtesi: sıradaki seçimi verir (ya da vazgeçer / hata fırlatır).
class FakeWorkPhotoPicker implements WorkPhotoPicker {
  FakeWorkPhotoPicker([List<WorkPhotoSelection> queue = const <WorkPhotoSelection>[]])
    : queue = List<WorkPhotoSelection>.of(queue);

  final List<WorkPhotoSelection> queue;
  Object? error;

  /// Her çağrının `maxCount` değeri.
  final List<int> calls = <int>[];
  int releaseCalls = 0;

  /// Verilirse seçim "hazırlanıyor" aşamasında (`onPreparing` çağrıldıktan sonra) bu kapı açılana dek bekler.
  Completer<void>? prepareGate;

  @override
  Future<WorkPhotoSelection> pick({required int maxCount, void Function()? onPreparing}) async {
    calls.add(maxCount);
    final failure = error;
    if (failure != null) throw failure;
    final gate = prepareGate;
    if (gate != null) {
      onPreparing?.call();
      await gate.future;
    }
    return queue.isEmpty ? const WorkPhotoSelection() : queue.removeAt(0);
  }

  @override
  Future<void> release() async => releaseCalls++;
}

/// Hata ya da yarış için kuyruğa konan sahte servis.
class FakeWorkService extends WorkTrackingService {
  FakeWorkService({required super.authService, this.kind = WorkSiteAccess.manager})
    : super(api: WorkTrackingApi(baseUrl: 'http://localhost'));

  /// Yönetim görünümündeki rol: manager | staff | board.
  WorkSiteAccess kind;

  final List<Map<String, dynamic>> residentRows = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> managedRows = <Map<String, dynamic>>[];
  final Map<int, List<Map<String, dynamic>>> events =
      <int, List<Map<String, dynamic>>>{};
  List<WorkApartmentChoice> apartments = const <WorkApartmentChoice>[
    WorkApartmentChoice(id: 301, label: 'A Blok / 5'),
  ];
  List<WorkAssignee> assigneeList = const <WorkAssignee>[
    WorkAssignee(userCode: kWorkSelfCode, name: 'Ben Yönetici', role: 'manager'),
    WorkAssignee(userCode: 9, name: 'Mehmet Usta', role: 'staff'),
  ];

  // --- Çağrı kayıtları ---
  final List<({int? site, String status, int? before, int limit})>
  listMineCalls = [];
  final List<WorkCreateRequest> createCalls = [];
  final List<int> getMineCalls = [];
  final List<int> seenCalls = [];
  final List<int> cancelCalls = [];
  final List<({int id, String body})> commentMineCalls = [];
  final List<int> apartmentCalls = [];
  final List<
    ({
      int site,
      String? status,
      String? category,
      String? priority,
      String? assigned,
      String? query,
      int? before,
    })
  >
  listManagedCalls = [];
  final List<int> getManagedCalls = [];
  final List<({int site, int id, Map<String, Object?> fields})> updateCalls =
      [];
  final List<({int site, int id, String body, bool internal})>
  commentManagedCalls = [];
  int assigneeCalls = 0;

  // --- Fotoğraf ekleri ve rapor ---
  /// Talep kimliği -> ek satırları (sunucu biçimi).
  final Map<int, List<Map<String, dynamic>>> attachments =
      <int, List<Map<String, dynamic>>>{};

  /// Ek kimliği -> içerik baytları (`GET .../content`).
  final Map<int, Uint8List> attachmentBytes = <int, Uint8List>{};

  /// Rapor gövdesi; null ise [wkReportJson] ile üretilir.
  Map<String, dynamic>? reportJson;

  /// Yükleme ilerleme adımı sayısı.
  int uploadSteps = 4;

  /// true: sakin görünümünde yönetimin fotoğrafına GERÇEK ad yazılır (hatalı sunucu benzetimi; arayüz yine "Yönetim"
  /// göstermelidir). Varsayılan sunucu gibi "Yönetim".
  bool leakUploaderNames = false;

  /// `user` | `site`: ekleme 409 `ATTACHMENT_QUOTA_EXCEEDED` ile reddedilir.
  String? quotaExceeded;

  final List<({int? site, int id, String name, String mime, int size})>
  createAttachmentCalls = [];
  final List<({int? site, int id, int attId, int size})> uploadAttachmentCalls = [];
  final List<({int? site, int id, int attId})> downloadAttachmentCalls = [];
  final List<({int? site, int id, int attId})> deleteAttachmentCalls = [];
  final List<({int site, DateTime from, DateTime to})> reportCalls = [];

  // --- Sürücüler ---
  /// İşlem adı -> sıradaki hatalar (her çağrı birini fırlatır).
  final Map<String, List<Object>> failures = <String, List<Object>>{};

  /// İşlem adı -> sıradaki kapılar (çağrı kapı açılana dek bekler).
  final Map<String, List<Completer<void>>> gates =
      <String, List<Completer<void>>>{};

  Future<void> _enter(String op) async {
    final gate = gates[op];
    if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
    final failure = failures[op];
    if (failure != null && failure.isNotEmpty) throw failure.removeAt(0);
  }

  static ApiException notFound() => ApiException(
    'Talep bulunamadı ya da erişiminiz yok.',
    statusCode: 404,
    code: 'WORK_ITEM_NOT_FOUND',
  );

  static ApiException moduleOff() => ApiException(
    'İş takibi bu site için kapalı.',
    statusCode: 403,
    code: 'MODULE_DISABLED',
  );

  static ApiException forbidden() => ApiException(
    'Bu işlem için yetkiniz yok.',
    statusCode: 403,
    code: 'FORBIDDEN_ROLE',
  );

  static ApiException attachmentNotFound() => ApiException(
    'Fotoğraf bulunamadı. Silinmiş olabilir; ekranı yenileyin.',
    statusCode: 404,
    code: 'WORK_ATTACHMENT_NOT_FOUND',
  );

  /// Sunucu `attachment_count`: yalnız HAZIR fotoğraflar.
  int _attachmentCount(int workItemId) => (attachments[workItemId] ?? const <Map<String, dynamic>>[])
      .where((a) => a['status'] == 'ready')
      .length;

  /// Ayrıntıdaki ekler (sunucu gibi): hazır ekler + çağıranın KENDİ tamamlanmamış yüklemeleri.
  Iterable<Map<String, dynamic>> _visibleAttachments(int workItemId) =>
      (attachments[workItemId] ?? const <Map<String, dynamic>>[]).where(
        (a) => a['status'] == 'ready' || a['uploaded_by_me'] == true,
      );

  /// Sakin görünümündeki ek satırı (sunucu WA-SEC-1): kendi eklemediği fotoğrafta yükleyen adı "Yönetim".
  List<Map<String, dynamic>> _residentAttachments(int workItemId) => [
    for (final a in _visibleAttachments(workItemId))
      <String, dynamic>{
        ...a,
        if (a['uploaded_by_me'] != true && !leakUploaderNames) 'uploaded_by_name': 'Yönetim',
      },
  ];

  List<Map<String, dynamic>> _managerAttachments(int workItemId) => [
    for (final a in _visibleAttachments(workItemId)) Map<String, dynamic>.of(a),
  ];

  /// Herkese açık ek olayı (sunucu: `attachment_added` to = ek kimliği, `attachment_removed` from = ek kimliği).
  void _attachmentEvent(int workItemId, int? siteCode, String type, int attachmentId) {
    final list = events[workItemId] ??= <Map<String, dynamic>>[];
    list.add(
      wkEvent(
        7000 + list.length,
        type: type,
        actorKind: siteCode == null ? 'resident' : 'manager',
        actorName: siteCode == null ? 'Ayşe Yılmaz' : 'Ben Yönetici',
        from: type == 'attachment_removed' ? '$attachmentId' : null,
        to: type == 'attachment_added' ? '$attachmentId' : null,
        at: '2026-10-19T10:05:00Z',
      ),
    );
  }

  Map<String, dynamic> _residentView(Map<String, dynamic> row) => <String, dynamic>{
    ...row,
    'attachment_count': _attachmentCount(row['id'] as int),
  };

  Map<String, dynamic>? _row(List<Map<String, dynamic>> rows, int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  int _nextId() {
    var max = 100;
    for (final row in [...residentRows, ...managedRows]) {
      if ((row['id'] as int) > max) max = row['id'] as int;
    }
    return max + 1;
  }

  // --- Sakin ---

  @override
  Future<WorkResidentPage> listMine({
    int? siteCode,
    String status = 'all',
    int limit = 30,
    int? beforeId,
  }) async {
    listMineCalls.add((site: siteCode, status: status, before: beforeId, limit: limit));
    await _enter('listMine');
    final scoped = residentRows
        .where((r) => siteCode == null || r['site_code'] == siteCode)
        .toList();
    final filtered =
        scoped.where((r) {
          if (status == 'all') return true;
          return status == 'open' ? !_terminal(r['status']) : _terminal(r['status']);
        }).toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final from = beforeId == null
        ? filtered
        : filtered.where((r) => (r['id'] as int) < beforeId).toList();
    final page = from.take(limit).toList();
    return WorkResidentPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _residentView(r)],
      'next_before_id': from.length > limit ? page.last['id'] : null,
      'unread_updates': scoped.where((r) => r['unread'] == true).length,
    });
  }

  @override
  Future<WorkCreateResult> createItem(WorkCreateRequest request) async {
    createCalls.add(request);
    await _enter('create');
    final id = _nextId();
    final row = wkResident(
      id,
      title: request.title.trim(),
      description: request.description.trim(),
      category: request.category.apiValue,
      location: request.locationType.apiValue,
      urgent: request.urgent,
      site: request.siteCode,
      apartmentLabel: request.apartmentId == null ? null : 'A Blok / 5',
    );
    residentRows.add(row);
    events[id] = <Map<String, dynamic>>[
      wkEvent(1000 + id, type: 'created', to: 'yeni'),
    ];
    return WorkCreateResult.fromJson(<String, dynamic>{
      'item': Map<String, dynamic>.of(row),
      'replayed': false,
    });
  }

  List<Map<String, dynamic>> _publicEvents(int id) => [
    for (final e in events[id] ?? const <Map<String, dynamic>>[])
      if (e['visibility'] == 'public')
        <String, dynamic>{
          for (final entry in e.entries)
            if (entry.key != 'actor' &&
                entry.key != 'from_label' &&
                entry.key != 'to_label')
              entry.key: entry.value,
          'actor_kind': e['actor_kind'] == 'resident' ? 'resident' : 'management',
        },
  ];

  @override
  Future<WorkResidentDetail> getMine(int id) async {
    getMineCalls.add(id);
    await _enter('getMine');
    final row = _row(residentRows, id);
    if (row == null) throw notFound();
    return WorkResidentDetail.fromJson(<String, dynamic>{
      'item': _residentView(row),
      'events': _publicEvents(id),
      'attachments': _residentAttachments(id),
    });
  }

  @override
  Future<WorkResidentItem> cancelMine(int id) async {
    cancelCalls.add(id);
    await _enter('cancel');
    final row = _row(residentRows, id);
    if (row == null) throw notFound();
    if (row['status'] != 'yeni') {
      throw ApiException(
        'Talebin durumu bu şekilde değiştirilemez.',
        statusCode: 409,
        code: 'INVALID_TRANSITION',
      );
    }
    row
      ..['status'] = 'iptal'
      ..['can_cancel'] = false
      ..['can_comment'] = false;
    (events[id] ??= <Map<String, dynamic>>[]).add(
      wkEvent(2000 + id, type: 'status_changed', from: 'yeni', to: 'iptal'),
    );
    return WorkResidentItem.fromJson(Map<String, dynamic>.of(row));
  }

  @override
  Future<WorkEvent> commentMine(int id, String body) async {
    commentMineCalls.add((id: id, body: body));
    await _enter('comment');
    final row = _row(residentRows, id);
    if (row == null) throw notFound();
    if (row['can_comment'] != true) {
      throw ApiException(
        'Bu talep kapandığı için değiştirilemez.',
        statusCode: 409,
        code: 'WORK_ITEM_CLOSED',
      );
    }
    final event = wkEvent(3000 + (events[id]?.length ?? 0), body: body.trim());
    (events[id] ??= <Map<String, dynamic>>[]).add(event);
    return WorkEvent.fromJson(event);
  }

  @override
  Future<void> markSeen(int id) async {
    seenCalls.add(id);
    await _enter('seen');
    _row(residentRows, id)?['unread'] = false;
  }

  @override
  Future<List<WorkApartmentChoice>> myApartments(int siteCode) async {
    apartmentCalls.add(siteCode);
    await _enter('apartments');
    return apartments;
  }

  // --- Yönetim ---

  bool _visibleToKind(Map<String, dynamic> row) {
    if (kind != WorkSiteAccess.staff) return true;
    final assigned = row['assigned_to'];
    return assigned == null ||
        (assigned is Map && assigned['user_code'] == kWorkSelfCode);
  }

  Map<String, dynamic> _managerView(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row);
    if (kind == WorkSiteAccess.board) {
      final requester = row['requester'] as Map;
      copy['requester'] = <String, dynamic>{'name': requester['name']};
    }
    copy['attachment_count'] = _attachmentCount(row['id'] as int);
    return copy;
  }

  @override
  Future<WorkManagedPage> listManaged(
    int siteCode, {
    String? status,
    String? category,
    String? priority,
    String? assigned,
    String? query,
    int limit = 30,
    int? beforeId,
  }) async {
    listManagedCalls.add((
      site: siteCode,
      status: status,
      category: category,
      priority: priority,
      assigned: assigned,
      query: query,
      before: beforeId,
    ));
    await _enter('listManaged');
    final scoped = managedRows
        .where((r) => r['site_code'] == siteCode && _visibleToKind(r))
        .toList();
    final q = (query ?? '').trim().toLowerCase();
    final filtered =
        scoped.where((r) {
          if (status != null && status.isNotEmpty) {
            final s = r['status'];
            final ok = status == 'open' ? !_terminal(s) : status.split(',').contains(s);
            if (!ok) return false;
          }
          if (category != null && r['category'] != category) return false;
          if (priority != null && r['priority'] != priority) return false;
          final a = r['assigned_to'];
          if (assigned == 'none' && a != null) return false;
          if (assigned == 'me' && !(a is Map && a['user_code'] == kWorkSelfCode)) {
            return false;
          }
          if (q.isNotEmpty &&
              !'${r['title']} ${r['description']}'.toLowerCase().contains(q)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final from = beforeId == null
        ? filtered
        : filtered.where((r) => (r['id'] as int) < beforeId).toList();
    final page = from.take(limit).toList();
    final counts = <String, int>{
      for (final s in kWorkTransitions.keys)
        s: scoped.where((r) => r['status'] == s).length,
    };
    return WorkManagedPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _managerView(r)],
      'next_before_id': from.length > limit ? page.last['id'] : null,
      'counts': counts,
    });
  }

  WorkManagedDetail _detail(Map<String, dynamic> row) {
    final id = row['id'] as int;
    final all = events[id] ?? const <Map<String, dynamic>>[];
    final board = kind == WorkSiteAccess.board;
    return WorkManagedDetail.fromJson(<String, dynamic>{
      'item': _managerView(row),
      'events': board
          ? _publicEvents(id)
          : [for (final e in all) Map<String, dynamic>.of(e)],
      'next_statuses': board
          ? const <String>[]
          : kWorkTransitions[row['status']] ?? const <String>[],
      'attachments': _managerAttachments(id),
    });
  }

  @override
  Future<WorkManagedDetail> getManaged(int siteCode, int id) async {
    getManagedCalls.add(id);
    await _enter('getManaged');
    final row = _row(managedRows, id);
    if (row == null || row['site_code'] != siteCode || !_visibleToKind(row)) {
      throw notFound();
    }
    return _detail(row);
  }

  @override
  Future<WorkManagedDetail> updateManaged(
    int siteCode,
    int id,
    Map<String, Object?> fields,
  ) async {
    updateCalls.add((site: siteCode, id: id, fields: Map.of(fields)));
    await _enter('update');
    final row = _row(managedRows, id);
    if (row == null || row['site_code'] != siteCode || !_visibleToKind(row)) {
      throw notFound();
    }
    if (kind == WorkSiteAccess.board) {
      throw ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
    }
    if (_terminal(row['status'])) {
      throw ApiException(
        'Bu talep kapandığı ya da iptal edildiği için değiştirilemez.',
        statusCode: 409,
        code: 'WORK_ITEM_CLOSED',
      );
    }
    final list = events[id] ??= <Map<String, dynamic>>[];
    var next = 5000 + list.length;
    final status = fields['status'];
    if (status != null) {
      if (!(kWorkTransitions[row['status']] ?? const <String>[]).contains(status)) {
        throw ApiException(
          'Talebin durumu bu şekilde değiştirilemez.',
          statusCode: 409,
          code: 'INVALID_TRANSITION',
        );
      }
      list.add(wkEvent(next++, type: 'status_changed', actorKind: 'manager', actorName: 'Ben Yönetici', from: '${row['status']}', to: '$status'));
      row['status'] = status;
    }
    if (fields.containsKey('priority')) {
      list.add(wkEvent(next++, type: 'priority_changed', visibility: 'internal', actorKind: 'manager', actorName: 'Ben Yönetici', from: '${row['priority']}', to: '${fields['priority']}'));
      row['priority'] = fields['priority'];
    }
    if (fields.containsKey('assigned_to')) {
      final code = fields['assigned_to'];
      final target = code == null
          ? null
          : assigneeList.firstWhere((a) => a.userCode == code);
      list.add(wkEvent(next++, type: 'assigned', visibility: 'internal', actorKind: 'manager', actorName: 'Ben Yönetici', fromLabel: (row['assigned_to'] as Map?)?['name'] as String?, toLabel: target?.name));
      row['assigned_to'] = target == null
          ? null
          : <String, dynamic>{'user_code': target.userCode, 'name': target.name};
    }
    if (fields.containsKey('due_date')) {
      list.add(wkEvent(next++, type: 'due_date_changed', actorKind: 'manager', actorName: 'Ben Yönetici', from: row['due_date'] as String?, to: fields['due_date'] as String?));
      row['due_date'] = fields['due_date'];
    }
    return _detail(row);
  }

  @override
  Future<WorkEvent> commentManaged(
    int siteCode,
    int id,
    String body, {
    required bool internal,
  }) async {
    commentManagedCalls.add((site: siteCode, id: id, body: body, internal: internal));
    await _enter('commentManaged');
    final row = _row(managedRows, id);
    if (row == null || row['site_code'] != siteCode || !_visibleToKind(row)) {
      throw notFound();
    }
    if (kind == WorkSiteAccess.board) {
      throw ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
    }
    final list = events[id] ??= <Map<String, dynamic>>[];
    final event = wkEvent(
      6000 + list.length,
      visibility: internal ? 'internal' : 'public',
      actorKind: 'manager',
      actorName: 'Ben Yönetici',
      body: body.trim(),
    );
    list.add(event);
    return WorkEvent.fromJson(event);
  }

  @override
  Future<List<WorkAssignee>> assignees(int siteCode) async {
    assigneeCalls++;
    await _enter('assignees');
    // Görevli yalnız kendini görür.
    return kind == WorkSiteAccess.staff
        ? <WorkAssignee>[assigneeList.first]
        : assigneeList;
  }

  // --- Fotoğraf ekleri ---

  /// Son verilen ek kimliği: sunucu dizisi gibi ARTAR, silinen kimlik yeniden verilmez.
  int _lastAttachmentId = 900;

  int _nextAttachmentId() {
    var max = _lastAttachmentId;
    for (final list in attachments.values) {
      for (final a in list) {
        if ((a['id'] as int) > max) max = a['id'] as int;
      }
    }
    return _lastAttachmentId = max + 1;
  }

  Map<String, dynamic>? _attachmentRow(int workItemId, int attachmentId) {
    for (final a in attachments[workItemId] ?? const <Map<String, dynamic>>[]) {
      if (a['id'] == attachmentId) return a;
    }
    return null;
  }

  Map<String, dynamic> _workRowFor(int? siteCode, int id) {
    final row = siteCode == null ? _row(residentRows, id) : _row(managedRows, id);
    if (row == null) throw notFound();
    if (siteCode != null && (row['site_code'] != siteCode || !_visibleToKind(row))) {
      throw notFound();
    }
    return row;
  }

  @override
  Future<WorkAttachment> createAttachment({
    int? siteCode,
    required int id,
    required WorkAttachmentCreateRequest request,
  }) async {
    createAttachmentCalls.add((
      site: siteCode,
      id: id,
      name: request.fileName,
      mime: request.mimeType,
      size: request.sizeBytes,
    ));
    await _enter('createAttachment');
    final row = _workRowFor(siteCode, id);
    if (siteCode != null && kind == WorkSiteAccess.board) throw forbidden();
    if (_terminal(row['status'])) {
      throw ApiException(
        WorkAttachmentRules.closedMessage,
        statusCode: 409,
        code: 'INVALID_STATE',
      );
    }
    final list = attachments[id] ??= <Map<String, dynamic>>[];
    if (list.length >= kWorkAttachmentMax) {
      throw ApiException(
        WorkAttachmentRules.limitMessage,
        statusCode: 409,
        code: 'LIMIT_REACHED',
      );
    }
    final quota = quotaExceeded;
    if (quota != null) {
      final site = quota == 'site';
      throw ApiException(
        WorkAttachmentRules.quotaMessage(site: site, windowDays: site ? null : 30),
        statusCode: 409,
        code: 'ATTACHMENT_QUOTA_EXCEEDED',
        payload: <String, dynamic>{
          'quota': quota,
          'quota_bytes': 200 * 1024 * 1024,
          if (!site) 'window_days': 30,
        },
      );
    }
    if (!WorkAttachmentRules.allowedMimeTypes.contains(request.mimeType)) {
      throw ApiException(
        WorkAttachmentRules.typeAndSizeMessage,
        statusCode: 415,
        code: 'ATTACHMENT_TYPE_NOT_ALLOWED',
      );
    }
    if (request.sizeBytes <= 0 || request.sizeBytes > kWorkAttachmentMaxBytes) {
      throw ApiException(
        WorkAttachmentRules.typeAndSizeMessage,
        statusCode: 413,
        code: 'ATTACHMENT_TOO_LARGE',
      );
    }
    final attachment = wkAttachment(
      _nextAttachmentId(),
      workItemId: id,
      fileName: request.fileName,
      mime: request.mimeType,
      size: request.sizeBytes,
      status: 'uploading',
      uploadedBy: siteCode == null ? 'Ayşe Yılmaz' : 'Ben Yönetici',
      kind: siteCode == null ? 'resident' : 'management',
      mine: true,
      at: '2026-10-19T10:00:00Z',
    );
    list.add(attachment);
    return WorkAttachment.fromJson(attachment)!;
  }

  @override
  Future<WorkAttachment> uploadAttachment({
    int? siteCode,
    required int id,
    required int attachmentId,
    required DocumentUploadSource source,
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    uploadAttachmentCalls.add((site: siteCode, id: id, attId: attachmentId, size: source.size));
    await _enter('uploadAttachment');
    final row = _attachmentRow(id, attachmentId);
    if (row == null) throw attachmentNotFound();
    if (row['status'] == 'ready') {
      throw ApiException('Fotoğraf zaten yüklenmiş.', statusCode: 409, code: 'UPLOAD_ALREADY_COMPLETED');
    }
    if (_terminal(_workRowFor(siteCode, id)['status'])) {
      throw ApiException(WorkAttachmentRules.closedMessage, statusCode: 409, code: 'INVALID_STATE');
    }
    for (var i = 1; i <= uploadSteps; i++) {
      if (cancel != null && cancel.isCancelled) throw const DocumentTransferCancelled();
      onProgress?.call(source.size * i ~/ uploadSteps, source.size);
      await Future<void>.delayed(Duration.zero);
      // Ortada bir kapı: testler bu sırada iptal eder.
      if (i == 2) {
        final gate = gates['uploadMid'];
        if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
      }
    }
    if (cancel != null && cancel.isCancelled) throw const DocumentTransferCancelled();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.open()) {
      builder.add(chunk);
    }
    row['status'] = 'ready';
    attachmentBytes[attachmentId] = builder.takeBytes();
    _attachmentEvent(id, siteCode, 'attachment_added', attachmentId);
    return WorkAttachment.fromJson(row)!;
  }

  @override
  Future<Uint8List> downloadAttachment({
    int? siteCode,
    required int id,
    required int attachmentId,
  }) async {
    downloadAttachmentCalls.add((site: siteCode, id: id, attId: attachmentId));
    await _enter('downloadAttachment');
    final bytes = attachmentBytes[attachmentId];
    final row = _attachmentRow(id, attachmentId);
    // Sunucu yalnız HAZIR eki verir.
    if (bytes == null || row == null || row['status'] != 'ready') throw attachmentNotFound();
    return bytes;
  }

  @override
  Future<void> deleteAttachment({
    int? siteCode,
    required int id,
    required int attachmentId,
  }) async {
    deleteAttachmentCalls.add((site: siteCode, id: id, attId: attachmentId));
    await _enter('deleteAttachment');
    final item = _workRowFor(siteCode, id);
    final list = attachments[id];
    final index = list?.indexWhere((a) => a['id'] == attachmentId) ?? -1;
    if (list == null || index < 0) throw attachmentNotFound();
    if (siteCode != null && kind == WorkSiteAccess.board) throw forbidden();
    // Sakin ve görevli yalnız kendi yüklediğini siler; yönetici hepsini.
    final mine = list[index]['uploaded_by_me'] == true;
    if (!mine && (siteCode == null || kind == WorkSiteAccess.staff)) {
      throw ApiException(
        'Bu fotoğrafı yalnız ekleyen kişi ya da yönetici silebilir.',
        statusCode: 403,
        code: 'FORBIDDEN_ROLE',
      );
    }
    // Yönetici / süper kapanmış talepte de siler; görevli ve sakin 409 INVALID_STATE alır.
    final managerDelete = siteCode != null && kind == WorkSiteAccess.manager;
    if (_terminal(item['status']) && !managerDelete) {
      throw ApiException('Kapanmış talepteki fotoğraf silinemez.', statusCode: 409, code: 'INVALID_STATE');
    }
    final wasReady = list[index]['status'] == 'ready';
    list.removeAt(index);
    attachmentBytes.remove(attachmentId);
    // Hazır ek silinince herkese açık olay; tamamlanmamış kayıt olaysız kalkar (sunucu gibi).
    if (wasReady) _attachmentEvent(id, siteCode, 'attachment_removed', attachmentId);
  }

  // --- Rapor ---

  @override
  Future<WorkReport> report(
    int siteCode, {
    required DateTime from,
    required DateTime to,
  }) async {
    reportCalls.add((site: siteCode, from: from, to: to));
    await _enter('report');
    if (kind == WorkSiteAccess.staff) throw forbidden();
    return WorkReport.fromJson(reportJson ?? wkReportJson(from: from, to: to));
  }
}

/// Üç sakin talebi: yeni (güncelleme var), işlemde, kapandı.
FakeWorkService residentWork(WorkFakeAuth auth, {int count = 3}) {
  final service = FakeWorkService(authService: auth);
  final rows = <Map<String, dynamic>>[
    wkResident(1, title: 'Çatı sızıntısı', status: 'islemde', hasAssignee: true),
    wkResident(2, title: 'Lamba yanmıyor', status: 'kapandi', category: 'bakim'),
    wkResident(3, title: 'Asansör çalışmıyor', unread: true, urgent: true),
  ];
  service.residentRows.addAll(rows.take(count));
  for (final row in service.residentRows) {
    final id = row['id'] as int;
    service.events[id] = <Map<String, dynamic>>[
      wkEvent(id * 10, type: 'created', to: 'yeni'),
      if (row['status'] == 'islemde')
        wkEvent(id * 10 + 1, type: 'status_changed', actorKind: 'manager', from: 'yeni', to: 'islemde', actorName: 'Ben Yönetici'),
      if (row['status'] == 'islemde')
        wkEvent(id * 10 + 2, visibility: 'internal', actorKind: 'manager', actorName: 'Ben Yönetici', body: 'Gizli iç not'),
      if (row['unread'] == true)
        wkEvent(id * 10 + 3, body: 'Teknisyen yarın gelecek.', actorKind: 'manager', actorName: 'Ben Yönetici'),
    ];
  }
  // İşlemdeki talepte iki fotoğraf: biri sakinin (silebilir), biri yönetimin (silemez).
  if (count >= 1) seedWorkAttachments(service, residentSelf: true);
  return service;
}

/// 1 numaralı talebe iki hazır fotoğraf ekler: 901 sakinin, 902 yönetimin. [residentSelf] true ise "ben" sakindir
/// (901 benim), false ise "ben" yöneticidir (902 benim).
void seedWorkAttachments(FakeWorkService service, {required bool residentSelf}) {
  service.attachments[1] = <Map<String, dynamic>>[
    wkAttachment(901, workItemId: 1, fileName: 'sizinti.jpg', uploadedBy: 'Ayşe Yılmaz', kind: 'resident', mine: residentSelf),
    wkAttachment(902, workItemId: 1, fileName: 'onarim.png', mime: 'image/png', size: 98304, uploadedBy: 'Ben Yönetici', kind: 'management', mine: !residentSelf, at: '2026-10-16T10:00:00Z'),
  ];
  service.attachmentBytes[901] = kWkPng;
  service.attachmentBytes[902] = kWkPng;
}

/// Yönetim: yeni (acil), işlemde (atanmış, hedef tarihli), çözüldü, kapandı.
FakeWorkService managerWork(
  WorkFakeAuth auth, {
  WorkSiteAccess kind = WorkSiteAccess.manager,
}) {
  final service = FakeWorkService(authService: auth, kind: kind);
  service.managedRows.addAll(<Map<String, dynamic>>[
    wkManaged(1, title: 'Çatı sızıntısı', status: 'islemde', priority: 'acil', assignedCode: kWorkSelfCode, assignedName: 'Ben Yönetici', dueDate: '2026-10-25'),
    wkManaged(2, title: 'Lamba yanmıyor', status: 'kapandi', category: 'bakim', priority: 'dusuk', requester: 'Veli Kaya'),
    wkManaged(3, title: 'Asansör çalışmıyor', residentUrgent: true),
    wkManaged(4, title: 'Bahçe kapısı gıcırdıyor', status: 'cozuldu', category: 'bakim', assignedCode: 9, assignedName: 'Mehmet Usta'),
  ]);
  for (final row in service.managedRows) {
    final id = row['id'] as int;
    service.events[id] = <Map<String, dynamic>>[
      wkEvent(id * 10, type: 'created', to: 'yeni', actorName: '${(row['requester'] as Map)['name']}'),
      wkEvent(id * 10 + 1, visibility: 'internal', actorKind: 'manager', actorName: 'Ben Yönetici', body: 'Firmayı aradım, yarın gelecekler.'),
      wkEvent(id * 10 + 2, actorKind: 'manager', actorName: 'Ben Yönetici', body: 'Talebiniz alındı.'),
    ];
  }
  seedWorkAttachments(service, residentSelf: false);
  return service;
}

/// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024@1.0).
const List<(double, double, double)> kWorkCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalıdır.
void workMatrix(
  String name,
  Future<void> Function(
    WidgetTester t,
    double width,
    double height,
    double scale,
    bool dark,
  )
  body,
) {
  for (final (width, height, scale) in kWorkCells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        '$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok',
        (t) async {
          await body(t, width, height, scale, dark);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

/// [Key] ile kısa bulucu.
Finder wkKey(String key) => find.byKey(ValueKey<String>(key));
