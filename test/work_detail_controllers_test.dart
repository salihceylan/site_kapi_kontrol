// İş Takibi ayrıntı denetleyicileri (lib/ui/views/work_detail_controllers.dart): yükleme, "görüldü" işareti,
// yorum, iptal, güncelleme ve hata sınıflandırması (ekransız).
//
// Kurallar: 404 -> gone, 403 MODULE_DISABLED -> moduleClosed, 409 -> sunucuyla eşitleme; çift gönderim yok sayılır;
// yazma hatasında liste yeniden çekilmez ve metin korunur (çağıran); dispose sonrası yanıt yok sayılır; kurul
// atanabilir kişileri çekmez.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/views/work_detail_controllers.dart';

import 'screens/work_fixtures.dart';

WorkResidentDetailController _resident(FakeWorkService service, int id) =>
    WorkResidentDetailController(
      service: service,
      initial: WorkResidentItem.fromJson(service.residentRows.firstWhere((r) => r['id'] == id)),
    );

WorkManagerDetailController _manager(
  FakeWorkService service,
  int id, {
  bool canWrite = true,
}) => WorkManagerDetailController(
  service: service,
  siteCode: 11,
  canWrite: canWrite,
  initial: WorkManagedItem.fromJson(service.managedRows.firstWhere((r) => r['id'] == id)),
);

void main() {
  group('sakin denetleyicisi', () {
    test('yükleme: olaylar gelir; okunmamışsa seen çağrılır ve liste yenilenmeli işaretlenir', () async {
      final service = residentWork(WorkFakeAuth());
      final c = _resident(service, 3);
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.loaded, isTrue);
      expect(c.events.map((e) => e.type), contains(WorkEventType.created));
      expect(service.seenCalls, <int>[3]);
      expect(c.item.unread, isFalse);
      expect(c.changed, isTrue, reason: 'rozet söndü: liste yenilenmeli');
      c.dispose();
    });

    test('okunmamış değilse seen çağrılmaz ve değişiklik yok', () async {
      final service = residentWork(WorkFakeAuth());
      final c = _resident(service, 1);
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(service.seenCalls, isEmpty);
      expect(c.changed, isFalse);
      expect(c.events.any((e) => e.internal), isFalse, reason: 'iç not sakine gelmez');
      c.dispose();
    });

    test('seen başarısız olsa da ekran bozulmaz (sessiz)', () async {
      final service = residentWork(WorkFakeAuth());
      service.failures['seen'] = <Object>[ApiException('x', statusCode: 500)];
      final c = _resident(service, 3);
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.loaded, isTrue);
      expect(c.loadError, isNull);
      expect(c.item.unread, isTrue);
      c.dispose();
    });

    test('404 -> gone; 403 MODULE_DISABLED -> moduleClosed; genel hata -> loadError, tekrar dene yüklenir', () async {
      final service = residentWork(WorkFakeAuth());
      final c = _resident(service, 1);
      service.failures['getMine'] = <Object>[FakeWorkService.notFound()];
      await c.load();
      expect(c.gone, isTrue);
      expect(c.changed, isTrue);

      service.failures['getMine'] = <Object>[FakeWorkService.moduleOff()];
      await c.load();
      expect(c.moduleClosed, isTrue);

      service.failures['getMine'] = <Object>[ApiException('Bağlantı yok.')];
      await c.load();
      expect(c.loadError, 'Bağlantı yok.');
      expect(c.loaded, isFalse);

      await c.load();
      expect(c.loadError, isNull);
      expect(c.loaded, isTrue);
      expect(c.gone, isFalse);
      expect(c.moduleClosed, isFalse);
      c.dispose();
    });

    test('yorum: olay çizgiye eklenir; çift gönderim yok sayılır; hata metni korur', () async {
      final service = residentWork(WorkFakeAuth());
      final c = _resident(service, 1);
      await c.load();
      final gate = Completer<void>();
      service.gates['comment'] = <Completer<void>>[gate];
      final first = c.comment('Merhaba');
      expect(c.busy, isTrue);
      expect(await c.comment('İkinci'), isFalse, reason: 'sürerken ikinci gönderim yok');
      gate.complete();
      expect(await first, isTrue);
      expect(service.commentMineCalls.map((x) => x.body), <String>['Merhaba']);
      expect(c.events.last.body, 'Merhaba');
      expect(c.busy, isFalse);
      expect(c.changed, isTrue);

      service.failures['comment'] = <Object>[
        ApiException('Çok sık deneme.', statusCode: 429, retryAfterSeconds: 30),
      ];
      expect(await c.comment('Tekrar'), isFalse);
      expect(c.actionError, 'Çok sık deneme.');
      expect((c.lastError as ApiException).isRateLimited, isTrue);
      expect(c.events.length, 3, reason: 'başarısız yorum eklenmez');
      c.dispose();
    });

    test('kapanmış talebe yorum: 409 mesajı gösterilir ve durum sunucuyla eşitlenir', () async {
      final service = residentWork(WorkFakeAuth());
      final c = _resident(service, 1);
      await c.load();
      // Yönetim bu arada talebi kapattı.
      service.residentRows.firstWhere((r) => r['id'] == 1)
        ..['status'] = 'kapandi'
        ..['can_comment'] = false;
      expect(await c.comment('Geç kaldım'), isFalse);
      expect(c.actionError, contains('kapandığı'));
      await Future<void>.delayed(Duration.zero);
      expect(c.item.status, WorkStatus.kapandi);
      expect(c.item.canComment, isFalse);
      c.dispose();
    });

    test('iptal: yeni talep iptal olur, durum çizgisi tazelenir; işlemdeki talep iptal edilemez (409)', () async {
      final service = residentWork(WorkFakeAuth());
      final c = _resident(service, 3);
      await c.load();
      expect(await c.cancel(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(c.item.status, WorkStatus.iptal);
      expect(c.item.canCancel, isFalse);
      expect(c.events.last.type, WorkEventType.statusChanged);
      expect(service.cancelCalls, <int>[3]);

      final processing = _resident(service, 1);
      await processing.load();
      expect(await processing.cancel(), isFalse);
      expect(processing.actionError, contains('değiştirilemez'));
      c.dispose();
      processing.dispose();
    });

    test('dispose sonrası gelen yanıt yok sayılır', () async {
      final service = residentWork(WorkFakeAuth());
      final gate = Completer<void>();
      service.gates['getMine'] = <Completer<void>>[gate];
      final c = _resident(service, 1);
      final loading = c.load();
      c.dispose();
      gate.complete();
      await loading;
      expect(c.loaded, isFalse);
    });
  });

  group('yönetim denetleyicisi', () {
    test('yükleme: next_statuses sunucudan; atanabilir kişiler yalnız yazma yetkisinde çekilir', () async {
      final service = managerWork(WorkFakeAuth());
      final c = _manager(service, 3);
      await c.load();
      await c.loadAssignees();
      expect(c.nextStatuses, <WorkStatus>[WorkStatus.islemde, WorkStatus.beklemede, WorkStatus.cozuldu, WorkStatus.iptal]);
      expect(c.events.any((e) => e.internal), isTrue, reason: 'yönetim iç notları görür');
      expect(c.assignees.length, 2);
      expect(c.assigneesLoaded, isTrue);

      final board = managerWork(WorkFakeAuth(), kind: WorkSiteAccess.board);
      final bc = _manager(board, 3, canWrite: false);
      await bc.load();
      await bc.loadAssignees();
      expect(board.assigneeCalls, 0, reason: 'kurul atanabilir listeyi çekmez');
      expect(bc.nextStatuses, isEmpty);
      expect(bc.events.any((e) => e.internal), isFalse, reason: 'kurul iç notu görmez');
      expect(bc.item.requester.phone, isNull);
      c.dispose();
      bc.dispose();
    });

    test('güncelleme: yalnız verilen alanlar gider; yanıt durumu ve geçişleri yeniler', () async {
      final service = managerWork(WorkFakeAuth());
      final c = _manager(service, 3);
      await c.load();
      expect(
        await c.save(<String, Object?>{'status': 'islemde', 'assigned_to': 9, 'due_date': '2026-10-30'}),
        isTrue,
      );
      expect(service.updateCalls.single.fields, <String, Object?>{
        'status': 'islemde',
        'assigned_to': 9,
        'due_date': '2026-10-30',
      });
      expect(c.item.status, WorkStatus.islemde);
      expect(c.item.assignedTo?.userCode, 9);
      expect(c.item.dueDate, DateTime(2026, 10, 30));
      expect(c.nextStatuses, isNot(contains(WorkStatus.yeni)));
      expect(c.changed, isTrue);
      expect(await c.save(const <String, Object?>{}), isFalse, reason: 'boş değişiklik istek yapmaz');
      expect(service.updateCalls.length, 1);
      c.dispose();
    });

    test('409 INVALID_TRANSITION: düz Türkçe mesaj; durum sunucuyla eşitlenir; 403 kurul', () async {
      final service = managerWork(WorkFakeAuth());
      final c = _manager(service, 3);
      await c.load();
      // Başka yönetici talebi bu arada çözdü; yerel geçiş listesi eskiydi.
      expect(await c.save(<String, Object?>{'status': 'kapandi'}), isFalse);
      expect(c.actionError, contains('değiştirilemez'));
      expect(c.busy, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(c.loaded, isTrue, reason: 'eşitleme sessiz yüklenir');

      final board = managerWork(WorkFakeAuth(), kind: WorkSiteAccess.board);
      final bc = _manager(board, 3, canWrite: true);
      await bc.load();
      expect(await bc.save(<String, Object?>{'priority': 'acil'}), isFalse);
      expect(bc.actionError, 'Bu işlem için yetkiniz yok.');
      c.dispose();
      bc.dispose();
    });

    test('kapanmış talep: 409 WORK_ITEM_CLOSED; görevli başkasının talebini göremez (404 -> gone)', () async {
      final service = managerWork(WorkFakeAuth());
      final closed = _manager(service, 2);
      await closed.load();
      expect(closed.nextStatuses, isEmpty);
      expect(await closed.save(<String, Object?>{'priority': 'acil'}), isFalse);
      expect(closed.actionError, contains('kapandığı'));

      final staff = managerWork(WorkFakeAuth(), kind: WorkSiteAccess.staff);
      final other = _manager(staff, 4); // Mehmet Usta'ya atanmış
      await other.load();
      expect(other.gone, isTrue);
      expect(other.changed, isTrue);
      closed.dispose();
      other.dispose();
    });

    test('yorum: iç / herkese açık ayrımı sunucuya gider; olay çizgiye eklenir', () async {
      final service = managerWork(WorkFakeAuth());
      final c = _manager(service, 3);
      await c.load();
      expect(await c.comment('İç not', internal: true), isTrue);
      expect(await c.comment('Sakine açık', internal: false), isTrue);
      expect(service.commentManagedCalls.map((x) => x.internal), <bool>[true, false]);
      expect(c.events.last.internal, isFalse);
      expect(c.events[c.events.length - 2].internal, isTrue);
      service.failures['commentManaged'] = <Object>[
        ApiException('Bu talebe daha fazla yorum eklenemez.', statusCode: 409, code: 'WORK_ITEM_COMMENT_LIMIT'),
      ];
      expect(await c.comment('Fazla', internal: true), isFalse);
      expect(c.actionError, 'Bu talebe daha fazla yorum eklenemez.');
      c.dispose();
    });

    test('atanabilir kişiler hatası ekranı bozmaz; yeniden denenince dolar', () async {
      final service = managerWork(WorkFakeAuth());
      final c = _manager(service, 3);
      service.failures['assignees'] = <Object>[ApiException('Liste alınamadı.')];
      await c.loadAssignees();
      expect(c.assigneesError, 'Liste alınamadı.');
      expect(c.assigneesLoaded, isFalse);
      await c.loadAssignees();
      expect(c.assigneesError, isNull);
      expect(c.assigneesLoaded, isTrue);
      c.dispose();
    });

    test('fotoğraf uyarıları (100): ayrıntıdan gelir; yükleme yanıtındakiler birleşir; uyarısız yükleme silmez; silinen fotoğrafın uyarısı kalkar; sunucu esastır', () async {
      final service = managerWork(WorkFakeAuth());
      service.photoWarnings[1] = <Map<String, dynamic>>[wkPhotoWarning(902)];
      final c = _manager(service, 1);
      expect(c.photoWarnings, isEmpty, reason: 'yüklenmeden uyarı yok');
      await c.load();
      expect(c.photoWarnings.map((w) => w.attachmentId), <int>[902]);

      // yükleme tamamlandı ve sunucu yeni fotoğraf için uyarı verdi
      c.addAttachment(
        WorkAttachment.fromJson(<String, dynamic>{
          'attachment': wkAttachment(903, workItemId: 1),
          'photo_warnings': <Object>[wkPhotoWarning(903, code: 'photo_reused', severity: 'info', message: 'Aynı konumda.')],
        })!,
      );
      expect(c.photoWarnings.map((w) => w.attachmentId), <int>[902, 903]);
      // aynı fotoğraf için yeni yanıt eskisini ezer
      c.addAttachment(
        WorkAttachment.fromJson(<String, dynamic>{
          'attachment': wkAttachment(903, workItemId: 1),
          'photo_warnings': <Object>[wkPhotoWarning(903, code: 'photo_reused_other_location')],
        })!,
      );
      expect(c.photoWarnings.where((w) => w.attachmentId == 903).map((w) => w.code), <String>['photo_reused_other_location']);
      // uyarısız yükleme mevcut uyarıları silmez
      c.addAttachment(WorkAttachment.fromJson(wkAttachment(904, workItemId: 1))!);
      expect(c.photoWarnings.length, 2);

      // silme: o fotoğrafın uyarısı kalkar
      final target = c.attachments.firstWhere((a) => a.id == 902);
      expect(await c.deleteAttachment(target), isTrue);
      expect(c.photoWarnings.map((w) => w.attachmentId), <int>[903]);

      // yeniden yükleme: sunucu esastır
      service.photoWarnings[1] = <Map<String, dynamic>>[];
      await c.load(silent: true);
      expect(c.photoWarnings, isEmpty);
      c.dispose();
    });

    test('güncelleme (PATCH) yanıtı da uyarıları taşır (ayrıntı yanıtıyla aynı biçim)', () async {
      final service = managerWork(WorkFakeAuth());
      service.photoWarnings[1] = <Map<String, dynamic>>[wkPhotoWarning(901)];
      final c = _manager(service, 1);
      await c.load();
      expect(await c.save(<String, Object?>{'priority': 'dusuk'}), isTrue);
      expect(c.photoWarnings.map((w) => w.attachmentId), <int>[901]);
      c.dispose();
    });
  });
}
