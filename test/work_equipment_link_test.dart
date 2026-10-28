// İş kaydı <-> ekipman bağı ve fotoğraf önce/sonra etiketi (docs/PLATFORM_IS_TAKIBI.md "Ekipman bağı" / "Fotoğraf etiketi",
// docs/PLATFORM_EKIPMAN.md "Servis geçmişi"): modeller (eski sunucu yanıtı güvenle okunur), API gövdeleri / yolları ve
// ekipmanın servis geçmişi sayfası. Ekran testleri: test/screens/work_equipment_link_test.dart.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart'
    show workAttachmentCaption, workAttachmentTag;
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart'
    show workEventTitle;

import 'screens/work_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
);

WorkTrackingApi _workApi(Future<http.Response> Function(http.Request request) handler) => WorkTrackingApi(
  baseUrl: '$_base/',
  client: MockClient(handler),
  readTimeout: const Duration(seconds: 5),
  writeTimeout: const Duration(seconds: 5),
);

EquipmentApi _equipmentApi(Future<http.Response> Function(http.Request request) handler) =>
    EquipmentApi(baseUrl: '$_base/', client: MockClient(handler));

Map<String, dynamic> _historyItem(int id, {String status = 'cozuldu', int before = 0, int after = 0, int total = 0}) =>
    <String, dynamic>{
      'id': id,
      'title': 'İş $id',
      'category': 'ariza',
      'status': status,
      'priority': 'normal',
      'created_at': '2026-10-01T09:00:00Z',
      'updated_at': '2026-10-02T09:00:00Z',
      'closed_at': null,
      'resolved_at': '2026-10-02T09:00:00Z',
      'attachment_count': total,
      'before_count': before,
      'after_count': after,
    };

void main() {
  group('WorkEquipmentRef', () {
    test('kimlikli satır okunur; pasif ekipman işaretlenir; kimliksiz / bozuk satır atılır', () {
      final list = WorkEquipmentRef.listFrom(<Object?>[
        <String, dynamic>{'id': 5, 'name': 'Asansör A', 'kind': 'asansor'},
        <String, dynamic>{'id': 6, 'name': 'Eski kazan', 'kind': 'kazan', 'is_active': false},
        <String, dynamic>{'name': 'kimliksiz'},
        <String, dynamic>{'id': 0, 'name': 'sıfır'},
        'metin',
        null,
      ]);
      expect(list.map((e) => e.id), <int>[5, 6]);
      expect(list[0].isActive, isTrue);
      expect(list[1].isActive, isFalse);
      expect(list[0].label, 'Asansör A');
      expect(const WorkEquipmentRef(id: 9).label, 'Ekipman', reason: 'adsız ekipman');
      expect(WorkEquipmentRef.listFrom('x'), isEmpty);
    });

    test('eşitlik kimlik + ad + tür + durumdur (açılır listede seçili değer eşleşsin)', () {
      expect(const WorkEquipmentRef(id: 5, name: 'A', kind: 'asansor'), const WorkEquipmentRef(id: 5, name: 'A', kind: 'asansor'));
      expect(const WorkEquipmentRef(id: 5, name: 'A') == const WorkEquipmentRef(id: 5, name: 'B'), isFalse);
    });
  });

  group('modeller: eski sunucu yanıtı güvenle okunur', () {
    test('talepte equipment yoksa / null ise bağ yok; varsa okunur', () {
      expect(WorkManagedItem.fromJson(wkManaged(1)).equipment, isNull);
      final old = wkManaged(1)..remove('equipment');
      expect(WorkManagedItem.fromJson(old).equipment, isNull, reason: 'eski sunucu alanı hiç göndermez');
      final linked = WorkManagedItem.fromJson(
        wkManaged(1, equipment: <String, dynamic>{'id': 5, 'name': 'Asansör A', 'kind': 'asansor', 'is_active': true}),
      );
      expect(linked.equipment, const WorkEquipmentRef(id: 5, name: 'Asansör A', kind: 'asansor'));
      final detail = WorkManagedDetail.fromJson(<String, dynamic>{
        'item': wkManaged(1, equipment: <String, dynamic>{'id': 6, 'name': 'Hidrofor', 'kind': 'hidrofor'}),
        'events': <Object>[],
      });
      expect(detail.item.equipment?.name, 'Hidrofor');
    });

    test('ek etiketi: before / after okunur, etiketsiz ve bilinmeyen değer null', () {
      expect(WorkAttachment.fromJson(wkAttachment(1, phase: 'before'))!.phase, WorkAttachmentPhase.before);
      expect(WorkAttachment.fromJson(wkAttachment(2, phase: 'AFTER'))!.phase, WorkAttachmentPhase.after);
      expect(WorkAttachment.fromJson(wkAttachment(3))!.phase, isNull);
      expect(WorkAttachment.fromJson(wkAttachment(4, phase: 'bogus'))!.phase, isNull);
      final old = wkAttachment(5)..remove('phase');
      expect(WorkAttachment.fromJson(old)!.phase, isNull, reason: 'eski sunucu alanı hiç göndermez');
      expect(WorkAttachmentPhase.before.label, 'Önce');
      expect(WorkAttachmentPhase.after.label, 'Sonra');
    });

    test('yeni ek gövdesi: etiket yalnız seçildiyse gönderilir (etiketsiz = eski gövde)', () {
      const plain = WorkAttachmentCreateRequest(fileName: ' a.jpg ', mimeType: 'IMAGE/JPEG', sizeBytes: 5);
      expect(plain.toJson(), <String, dynamic>{'file_name': 'a.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 5});
      const labeled = WorkAttachmentCreateRequest(fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 5, phase: WorkAttachmentPhase.after);
      expect(labeled.toJson()['phase'], 'after');
    });

    test('olay: equipment_changed tanınır; başlık ad etiketleriyle; eklenen fotoğraf başlığı etiketi taşır', () {
      final changed = WorkEvent.fromJson(wkEvent(1, type: 'equipment_changed', visibility: 'internal', actorKind: 'manager', from: '5', to: '6', fromLabel: 'Asansör A', toLabel: 'Hidrofor'));
      expect(changed.type, WorkEventType.equipmentChanged);
      expect(changed.internal, isTrue);
      expect(workEventTitle(changed), 'Ekipman: Asansör A → Hidrofor');
      final cleared = WorkEvent.fromJson(wkEvent(2, type: 'equipment_changed', visibility: 'internal', actorKind: 'manager', from: '5', fromLabel: 'Asansör A'));
      expect(workEventTitle(cleared), 'Ekipman: Asansör A → Seçilmedi');
      final linked = WorkEvent.fromJson(wkEvent(3, type: 'equipment_changed', visibility: 'internal', actorKind: 'manager', to: '5', toLabel: 'Asansör A'));
      expect(workEventTitle(linked), 'Ekipman: Seçilmedi → Asansör A');
      expect(workEventTitle(WorkEvent.fromJson(wkEvent(4, type: 'attachment_added', to: '9'))), 'Fotoğraf eklendi');
      expect(workEventTitle(WorkEvent.fromJson(wkEvent(5, type: 'attachment_added', from: 'before', to: '9'))), 'Fotoğraf eklendi (Önce)');
      expect(workEventTitle(WorkEvent.fromJson(wkEvent(6, type: 'attachment_added', from: 'sonra?', to: '9'))), 'Fotoğraf eklendi', reason: 'bilinmeyen etiket yok sayılır');
    });

    test('fotoğraf alt metni: etiket yükleyenin önüne gelir; sakin görünümünde yükleyen adı gösterilmez', () {
      final labeled = WorkAttachment.fromJson(wkAttachment(1, phase: 'before', uploadedBy: 'Ayşe Yılmaz'))!;
      expect(workAttachmentTag(labeled, showUploader: true), 'Önce · Ayşe Yılmaz');
      expect(workAttachmentTag(labeled, showUploader: false), 'Önce');
      final plain = WorkAttachment.fromJson(wkAttachment(2, uploadedBy: 'Ayşe Yılmaz'))!;
      expect(workAttachmentTag(plain, showUploader: true), 'Ayşe Yılmaz');
      expect(workAttachmentTag(plain, showUploader: false), isEmpty, reason: 'sakin + etiketsiz: eskisi gibi alt metin yok');
      expect(workAttachmentCaption(labeled, showUploader: true), startsWith('Önce · Ayşe Yılmaz · '));
      expect(workAttachmentCaption(plain, showUploader: true), startsWith('Ayşe Yılmaz · '));
    });
  });

  group('WorkTrackingApi', () {
    test('equipmentChoices: GET /manager/sites/:site/equipment?active=1; satırlar WorkEquipmentRef', () async {
      late http.Request seen;
      final api = _workApi((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[
            <String, dynamic>{'id': 5, 'kind': 'asansor', 'name': 'Asansör A', 'is_active': true, 'location': 'A Blok'},
            <String, dynamic>{'id': 6, 'kind': 'kazan', 'name': 'Kazan', 'is_active': true},
          ],
        });
      });
      final list = await api.equipmentChoices(token: 't', siteCode: 11);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/manager/sites/11/equipment');
      expect(seen.url.queryParameters, <String, String>{'active': '1'});
      expect(seen.headers['Authorization'], 'Bearer t');
      expect(list.map((e) => (e.id, e.name, e.kind)), <(int, String, String)>[(5, 'Asansör A', 'asansor'), (6, 'Kazan', 'kazan')]);
    });

    test('PATCH: equipment_id gönderilir ya da null (bağı kaldırır); INVALID_EQUIPMENT sunucu iletisiyle döner', () async {
      final bodies = <Map<String, dynamic>>[];
      var rejectNext = false;
      final api = _workApi((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (rejectNext) {
          return _json(400, <String, dynamic>{'error': 'Ekipman bu siteye ait değil ya da bulunamadı.', 'code': 'INVALID_EQUIPMENT'});
        }
        return _json(200, <String, dynamic>{
          'item': wkManaged(3, equipment: <String, dynamic>{'id': 5, 'name': 'Asansör A', 'kind': 'asansor'}),
          'events': <Object>[],
          'next_statuses': <Object>[],
        });
      });
      final linked = await api.updateManaged(token: 't', siteCode: 11, id: 3, fields: <String, Object?>{'equipment_id': 5});
      expect(linked.item.equipment?.id, 5);
      await api.updateManaged(token: 't', siteCode: 11, id: 3, fields: <String, Object?>{'equipment_id': null});
      expect(bodies, <Map<String, dynamic>>[
        <String, dynamic>{'equipment_id': 5},
        <String, dynamic>{'equipment_id': null},
      ]);
      rejectNext = true;
      await expectLater(
        api.updateManaged(token: 't', siteCode: 11, id: 3, fields: <String, Object?>{'equipment_id': 99}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'INVALID_EQUIPMENT')
              .having((e) => e.message, 'message', contains('Ekipman')),
        ),
      );
    });

    test('createAttachment: etiketli gövde phase taşır, etiketsiz gövde taşımaz; yanıttaki etiket okunur', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _workApi((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(201, <String, dynamic>{'attachment': wkAttachment(31, status: 'uploading', size: 5, phase: bodies.last['phase'] as String?)});
      });
      final labeled = await api.createAttachment(
        token: 't',
        siteCode: 11,
        id: 3,
        request: const WorkAttachmentCreateRequest(fileName: 'foto.jpg', mimeType: 'image/jpeg', sizeBytes: 5, phase: WorkAttachmentPhase.before),
      );
      final plain = await api.createAttachment(
        token: 't',
        siteCode: 11,
        id: 3,
        request: const WorkAttachmentCreateRequest(fileName: 'foto.jpg', mimeType: 'image/jpeg', sizeBytes: 5),
      );
      expect(bodies[0]['phase'], 'before');
      expect(bodies[1].containsKey('phase'), isFalse);
      expect(labeled.phase, WorkAttachmentPhase.before);
      expect(plain.phase, isNull);
    });
  });

  group('EquipmentApi servis geçmişi', () {
    test('workHistory: GET yol + sayfalama sorgusu; satırlar, sayaçlar ve imleç okunur', () async {
      late http.Request seen;
      final api = _equipmentApi((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'equipment': <String, dynamic>{'id': 5, 'kind': 'asansor', 'name': 'Asansör A', 'is_active': true},
          'work_tracking_enabled': true,
          'items': <Object>[_historyItem(30, before: 1, after: 2, total: 3), _historyItem(20, status: 'islemde')],
          'next_before_id': 20,
          'counts': <String, dynamic>{'total': 5, 'open': 2},
        });
      });
      final history = await api.workHistory('t', 11, 5, beforeId: 40, limit: 2);
      expect(seen.url.path, '/manager/sites/11/equipment/5/work-history');
      expect(seen.url.queryParameters, <String, String>{'limit': '2', 'before_id': '40'});
      expect(seen.headers['Authorization'], 'Bearer t');
      expect(history.workTrackingEnabled, isTrue);
      expect(history.items.map((e) => e.id), <int>[30, 20]);
      expect(history.items.first.status, WorkStatus.cozuldu);
      expect(history.items.first.category, WorkCategory.ariza);
      expect(history.items.first.resolvedAt, isNotNull);
      expect(history.items.first.photoSummary, 'Önce 1 · Sonra 2 · 3 fotoğraf');
      expect(history.items.last.photoSummary, isNull);
      expect(history.nextBeforeId, 20);
      expect((history.total, history.open), (5, 2));
    });

    test('ilk sayfada imleç gönderilmez; iş takibi kapalı yanıtı boş liste + bayrak; eski/bozuk satırlar atılır', () async {
      var closed = false;
      late http.Request seen;
      final api = _equipmentApi((request) async {
        seen = request;
        if (closed) {
          return _json(200, <String, dynamic>{'work_tracking_enabled': false, 'items': <Object>[], 'next_before_id': null, 'counts': <String, dynamic>{'total': 0, 'open': 0}});
        }
        return _json(200, <String, dynamic>{
          'items': <Object>[_historyItem(7), 'bozuk', <String, dynamic>{'title': 'kimliksiz'}],
        });
      });
      final first = await api.workHistory('t', 11, 5);
      expect(seen.url.queryParameters.containsKey('before_id'), isFalse);
      expect(first.items.map((e) => e.id), <int>[7]);
      expect(first.workTrackingEnabled, isTrue, reason: 'bayrak yoksa açık varsayılır');
      expect(first.nextBeforeId, isNull);
      closed = true;
      final off = await api.workHistory('t', 11, 5);
      expect(off.workTrackingEnabled, isFalse);
      expect(off.items, isEmpty);
    });

    test('sonraki sayfa sona eklenir: aynı kimlik iki kez girmez, imleç ve sayaçlar yeni sayfadan gelir', () {
      final first = EquipmentWorkHistory.fromJson(<String, dynamic>{
        'items': <Object>[_historyItem(30), _historyItem(20)],
        'next_before_id': 20,
        'counts': <String, dynamic>{'total': 3, 'open': 1},
      });
      final next = EquipmentWorkHistory.fromJson(<String, dynamic>{
        'items': <Object>[_historyItem(20), _historyItem(10)],
        'next_before_id': null,
        'counts': <String, dynamic>{'total': 3, 'open': 0},
      });
      final merged = first.append(next);
      expect(merged.items.map((e) => e.id), <int>[30, 20, 10]);
      expect(merged.nextBeforeId, isNull);
      expect((merged.total, merged.open), (3, 0));
    });

    test('hata: 404 NOT_FOUND ve 403 sunucu iletisiyle ApiException olur', () async {
      final api = _equipmentApi((request) async => _json(404, <String, dynamic>{'error': 'Ekipman bulunamadı ya da erişiminiz yok.', 'code': 'NOT_FOUND'}));
      try {
        await api.workHistory('t', 11, 99);
        fail('ApiException bekleniyordu');
      } on ApiException catch (e) {
        expect(e.statusCode, 404);
        expect(e.code, 'NOT_FOUND');
      }
    });
  });
}
