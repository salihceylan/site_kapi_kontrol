// WorkAttachmentUploadController (lib/services/work_attachment_upload.dart): sıralı iki adımlı yükleme (üstveri
// `POST` + ham gövde `PUT`), ilerleme, iptal, hata eşlemesi (talep başına sınır, kapanmış talep, tür / boyut, 429,
// ağ), kalan fotoğrafları durduran hatalar, kayıt yeniden kullanımı ve yeniden deneme (ekransız).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_attachment_upload.dart';

import 'screens/work_fixtures.dart';

FakeWorkService _service() => residentWork(WorkFakeAuth());

/// Zaman aşımı kısıcısını (120 ms) atlatan saat: her çağrıda 200 ms ilerler.
DateTime Function() _fastClock() {
  var now = DateTime(2026, 10, 19, 10);
  return () {
    now = now.add(const Duration(milliseconds: 200));
    return now;
  };
}

WorkAttachmentUploadController _controller(
  FakeWorkService service, {
  int id = 3,
  int? site,
}) => WorkAttachmentUploadController(
  service: service,
  workItemId: id,
  siteCode: site,
  now: _fastClock(),
);

Future<void> _tick([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('mutlu yol: iki fotoğraf sırayla (adım 1 + adım 2); her başarıda onUploaded; sonuç ready; done', () async {
    final service = _service();
    final c = _controller(service);
    final phases = <WorkUploadPhase>[];
    c.addListener(() => phases.add(c.phase));
    final uploaded = <WorkAttachment>[];
    final results = await c.run(
      <WorkPhotoPick>[wkPhoto('bir.jpg', size: 4096), wkPhoto('iki.png', size: 1024)],
      onUploaded: uploaded.add,
    );
    expect(results.length, 2);
    expect(results.every((r) => r.ok), isTrue);
    expect(results.map((r) => r.attachment!.status), everyElement(WorkAttachmentStatus.ready));
    expect(uploaded.map((a) => a.fileName), <String>['bir.jpg', 'iki.png']);
    expect(service.createAttachmentCalls.map((x) => (x.name, x.mime, x.size)), <(String, String, int)>[
      ('bir.jpg', 'image/jpeg', 4096),
      ('iki.png', 'image/png', 1024),
    ]);
    expect(service.createAttachmentCalls.every((x) => x.site == null && x.id == 3), isTrue, reason: 'sakin yolu');
    expect(service.uploadAttachmentCalls.map((x) => x.size), <int>[4096, 1024]);
    expect(service.attachments[3]!.map((a) => a['status']), everyElement('ready'));
    expect(c.phase, WorkUploadPhase.done);
    expect(c.uploadedCount, 2);
    expect(c.failedCount, 0);
    expect(c.error, isNull);
    expect(phases, containsAllInOrder(<WorkUploadPhase>[WorkUploadPhase.preparing, WorkUploadPhase.uploading, WorkUploadPhase.done]));
    expect(c.busy, isFalse);
    c.dispose();
  });

  test('yönetim yolu: siteCode dolu gider', () async {
    final service = managerWork(WorkFakeAuth());
    final c = _controller(service, id: 3, site: 11);
    final results = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    expect(results.single.ok, isTrue);
    expect(service.createAttachmentCalls.single.site, 11);
    expect(service.uploadAttachmentCalls.single.site, 11);
    c.dispose();
  });

  test('ilerleme: yüzde adım adım artar, %100 sonrası finishing; index / total', () async {
    final service = _service()..uploadSteps = 4;
    final c = _controller(service);
    final percents = <int>[];
    final seenIndex = <(int, int)>{};
    c.addListener(() {
      if (c.phase == WorkUploadPhase.uploading || c.phase == WorkUploadPhase.finishing) {
        percents.add(c.percent);
      }
      seenIndex.add((c.index, c.total));
    });
    await c.run(<WorkPhotoPick>[wkPhoto('a.jpg', size: 4000)]);
    expect(percents, containsAllInOrder(<int>[25, 50, 75, 100]));
    expect(seenIndex, contains((1, 1)));
    expect(c.fraction, 1.0);
    c.dispose();
  });

  test('ön doğrulama: desteklenmeyen uzantı sunucuya hiç gitmez; diğer fotoğraf yüklenir', () async {
    final service = _service();
    final c = _controller(service);
    final results = await c.run(<WorkPhotoPick>[wkPhoto('hareketli.gif'), wkPhoto('a.jpg')]);
    expect(results[0].ok, isFalse);
    expect(results[0].error, WorkAttachmentRules.typeAndSizeMessage);
    expect(results[0].canRetry, isFalse);
    expect(results[1].ok, isTrue);
    expect(service.createAttachmentCalls.length, 1);
    expect(c.phase, WorkUploadPhase.failed);
    expect(c.failedCount, 1);
    expect(c.canRetry, isFalse);
    c.dispose();
  });

  test('409 LIMIT_REACHED: "En fazla 4 fotoğraf eklenebilir."; kalanlar DENENMEDEN aynı nedenle başarısız', () async {
    final service = _service();
    // 1 numaralı talepte zaten 2 fotoğraf var: 2 tane daha sığar.
    final c = _controller(service, id: 1);
    final results = await c.run(
      <WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg'), wkPhoto('c.jpg'), wkPhoto('d.jpg')],
    );
    expect(results.map((r) => r.ok), <bool>[true, true, false, false]);
    expect(results[2].error, 'En fazla 4 fotoğraf eklenebilir.');
    expect(results[3].error, 'En fazla 4 fotoğraf eklenebilir.');
    expect(results[3].canRetry, isFalse);
    expect(service.createAttachmentCalls.length, 3, reason: 'dördüncü fotoğraf için istek atılmaz');
    expect(c.uploadedCount, 2);
    expect(c.failedCount, 2);
    expect(c.error, 'En fazla 4 fotoğraf eklenebilir.');
    c.dispose();
  });

  test('409 INVALID_STATE: "Kapanmış talebe fotoğraf eklenemez."; yeniden denenemez', () async {
    final service = _service();
    final c = _controller(service, id: 2); // kapandı
    final results = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg')]);
    expect(results.map((r) => r.error), everyElement('Kapanmış talebe fotoğraf eklenemez.'));
    expect(results.every((r) => !r.canRetry), isTrue);
    expect(service.createAttachmentCalls.length, 1);
    expect(c.canRetry, isFalse);
    c.dispose();
  });

  test('413 / 415 tür-boyut reddi: tek metin, yeniden denenemez; sıradaki fotoğraf yine denenir', () async {
    final service = _service();
    service.failures['createAttachment'] = <Object>[
      ApiException(WorkAttachmentRules.typeAndSizeMessage, statusCode: 413, code: 'FILE_TOO_LARGE'),
    ];
    final c = _controller(service);
    final results = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg')]);
    expect(results[0].error, 'Yalnız JPEG, PNG veya WebP; en fazla 5 MB.');
    expect(results[0].canRetry, isFalse);
    expect(results[1].ok, isTrue);
    expect(service.createAttachmentCalls.length, 2);
    c.dispose();
  });

  test('429: sunucu süre metni; kalanlar da aynı iletiyle; yeniden denenebilir; lastException hız sınırı', () async {
    final service = _service();
    service.failures['createAttachment'] = <Object>[
      ApiException(
        'Çok fazla fotoğraf işlemi yapıldı. 2 dakika sonra tekrar deneyin.',
        statusCode: 429,
        retryAfterSeconds: 120,
      ),
    ];
    final c = _controller(service);
    final results = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg')]);
    expect(results.map((r) => r.error), everyElement('Çok fazla fotoğraf işlemi yapıldı. 2 dakika sonra tekrar deneyin.'));
    expect(results.every((r) => r.canRetry), isTrue);
    expect(service.createAttachmentCalls.length, 1, reason: 'ikinci fotoğraf denenmez');
    expect((c.lastException as ApiException).isRateLimited, isTrue);
    expect(c.retryablePhotos.length, 2);
    c.dispose();
  });

  test('ağ hatası adım 2: kayıt korunur; yeniden denemede AYNI kayda PUT (adım 1 yinelenmez); başarı', () async {
    final service = _service();
    service.failures['uploadAttachment'] = <Object>[ApiException('Fotoğraf yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.')];
    final c = _controller(service);
    final first = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    expect(first.single.ok, isFalse);
    expect(first.single.canRetry, isTrue);
    expect(c.phase, WorkUploadPhase.failed);
    expect(service.createAttachmentCalls.length, 1);
    final attId = service.uploadAttachmentCalls.single.attId;

    final retry = await c.retryFailed();
    expect(retry.single.ok, isTrue);
    expect(service.createAttachmentCalls.length, 1, reason: 'adım 1 yinelenmez');
    expect(service.uploadAttachmentCalls.map((x) => x.attId), <int>[attId, attId]);
    expect(c.phase, WorkUploadPhase.done);
    expect(c.uploadedCount, 1);
    c.dispose();
  });

  test('404 WORK_ATTACHMENT_NOT_FOUND / 410 UPLOAD_EXPIRED adım 2: kayıt atılır, yeniden denenebilir; YENİ kayıt açılır', () async {
    final service = _service();
    service.failures['uploadAttachment'] = <Object>[
      FakeWorkService.attachmentNotFound(),
      ApiException('Yükleme süresi doldu. Tekrar deneyin.', statusCode: 410, code: 'UPLOAD_EXPIRED'),
    ];
    final c = _controller(service);
    final photo = wkPhoto('a.jpg');
    final first = await c.run(<WorkPhotoPick>[photo]);
    expect(first.single.ok, isFalse);
    expect(first.single.canRetry, isTrue, reason: 'fotoğraf sağlam: yeni kayıtla denenebilir');
    expect(first.single.error, contains('bulunamadı'));
    final firstRecord = service.uploadAttachmentCalls[0].attId;
    final expired = await c.retryFailed();
    expect(expired.single.error, 'Yükleme süresi doldu. Tekrar deneyin.');
    expect(expired.single.canRetry, isTrue);
    final expiredRecord = service.uploadAttachmentCalls[1].attId;
    expect(expiredRecord, isNot(firstRecord));
    await _tick(3);
    expect(
      service.deleteAttachmentCalls.map((x) => x.attId),
      <int>[expiredRecord],
      reason: 'süresi dolan kayıt sessizce silinir; zaten olmayan (404) kayıt silinmeye çalışılmaz',
    );
    final again = await c.retryFailed();
    expect(again.single.ok, isTrue);
    expect(service.createAttachmentCalls.length, 3, reason: 'her ret sonrası eski kayıt kullanılmaz');
    expect(c.failedCount, 0);
    c.dispose();
  });

  test('409 ATTACHMENT_QUOTA_EXCEEDED: kalanlar DENENMEDEN aynı iletiyle; yeniden denenemez', () async {
    final service = _service()..quotaExceeded = 'user';
    final c = _controller(service);
    final results = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg')]);
    expect(results.map((r) => r.error), everyElement(WorkAttachmentRules.quotaMessage(site: false)));
    expect(results.every((r) => !r.canRetry), isTrue);
    expect(service.createAttachmentCalls.length, 1, reason: 'ikinci fotoğraf için istek atılmaz');
    c.dispose();
  });

  test('içerik gönderilirken inFlightAttachmentId o kaydın kimliğidir; bitince null', () async {
    final service = _service();
    final gate = Completer<void>();
    service.gates['uploadMid'] = <Completer<void>>[gate];
    final c = _controller(service);
    expect(c.inFlightAttachmentId, isNull);
    final running = c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    var guard = 0;
    while (service.uploadAttachmentCalls.isEmpty && guard++ < 50) {
      await _tick();
    }
    expect(c.inFlightAttachmentId, service.uploadAttachmentCalls.single.attId);
    gate.complete();
    await running;
    expect(c.inFlightAttachmentId, isNull);
    c.dispose();
  });

  test('web: ilerleme bilinmez (fraction null); iptal BELİRSİZ sayılır, kayıt silinmez', () async {
    final service = _service();
    final gate = Completer<void>();
    service.gates['uploadMid'] = <Completer<void>>[gate];
    final c = WorkAttachmentUploadController(service: service, workItemId: 3, now: _fastClock(), web: true);
    expect(c.progressKnown, isFalse);
    final running = c.run(<WorkPhotoPick>[wkPhoto('a.jpg', size: 4000)]);
    var guard = 0;
    while (service.uploadAttachmentCalls.isEmpty && guard++ < 50) {
      await _tick();
    }
    await _tick(3);
    expect(c.fraction, isNull, reason: 'belirsiz çubuk');
    c.cancel();
    gate.complete();
    await running;
    expect(c.phase, WorkUploadPhase.cancelled);
    await c.discardPending();
    expect(service.deleteAttachmentCalls, isEmpty, reason: 'web iptalinde gövdenin gidip gitmediği bilinmez');
    c.dispose();
  });

  test('409 UPLOAD_ALREADY_COMPLETED: yanıtı kaybolan önceki deneme BAŞARI sayılır (hazır ek, onUploaded)', () async {
    final service = _service();
    // İlk PUT sunucuda tamamlandı ama yanıt kayboldu (zaman aşımı).
    service.failures['uploadAttachment'] = <Object>[ApiException('Sunucu yanıt vermedi.')];
    final c = _controller(service);
    final photo = wkPhoto('a.jpg');
    await c.run(<WorkPhotoPick>[photo]);
    expect(c.failedCount, 1);
    final attId = service.uploadAttachmentCalls.single.attId;
    service.attachments[3]!.single['status'] = 'ready';
    final uploaded = <WorkAttachment>[];
    final retry = await c.retryFailed(onUploaded: uploaded.add);
    expect(retry.single.ok, isTrue);
    expect(retry.single.attachment!.id, attId);
    expect(retry.single.attachment!.isReady, isTrue);
    expect(uploaded.single.id, attId);
    expect(c.phase, WorkUploadPhase.done);
    expect(c.failedCount, 0);
    expect(service.deleteAttachmentCalls, isEmpty);
    c.dispose();
  });

  test('415 içerik reddi adım 2: yarım kayıt HEMEN silinir (4 sınırı dolmasın); yeniden denenemez', () async {
    final service = _service();
    service.failures['uploadAttachment'] = <Object>[
      ApiException('Fotoğraf bozuk ya da türü dosya uzantısıyla uyuşmuyor. Başka bir fotoğraf seçin.', statusCode: 415, code: 'ATTACHMENT_CONTENT_MISMATCH'),
    ];
    final c = _controller(service);
    final results = await c.run(<WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg')]);
    await _tick(3);
    expect(results[0].ok, isFalse);
    expect(results[0].canRetry, isFalse);
    expect(results[0].error, contains('bozuk'));
    expect(results[1].ok, isTrue, reason: 'içerik reddi kalanları durdurmaz');
    final rejectedId = service.createAttachmentCalls.isEmpty ? -1 : service.uploadAttachmentCalls.first.attId;
    expect(service.deleteAttachmentCalls.single.attId, rejectedId);
    expect(service.attachments[3]!.map((a) => a['id']), isNot(contains(rejectedId)));
    expect(c.canRetry, isFalse);
    c.dispose();
  });

  test('iptal: uçuştaki fotoğraf kesilir, kalanlar gönderilmez; discardPending gövdesi gitmemiş kaydı siler', () async {
    final service = _service();
    final gate = Completer<void>();
    service.gates['uploadMid'] = <Completer<void>>[gate];
    final c = _controller(service);
    final photos = <WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg'), wkPhoto('c.jpg')];
    final running = c.run(photos);
    // İlk fotoğrafın gövdesi gitmeye başlayana dek bekle.
    var guard = 0;
    while (service.uploadAttachmentCalls.isEmpty && guard++ < 50) {
      await _tick();
    }
    expect(c.busy, isTrue);
    expect(identical(c.current, photos[0]), isTrue);
    expect(c.isQueued(photos[2]), isTrue);
    c.cancel();
    gate.complete();
    final results = await running;
    expect(results.map((r) => r.cancelled), <bool>[true, true, true]);
    expect(results.every((r) => r.canRetry), isTrue);
    expect(service.createAttachmentCalls.length, 1);
    expect(service.attachments[3]!.single['status'], 'uploading', reason: 'içerik gitmedi');
    expect(c.phase, WorkUploadPhase.cancelled);
    expect(c.error, 'Yükleme iptal edildi.');
    expect(c.busy, isFalse);
    expect(c.current, isNull);
    expect(c.isQueued(photos[2]), isFalse);
    await c.discardPending();
    expect(service.deleteAttachmentCalls.length, 1);
    expect(service.attachments[3], isEmpty, reason: 'gövdesi gitmemiş yarım kayıt silindi');
    await c.discardPending();
    expect(service.deleteAttachmentCalls.length, 1, reason: 'ikinci çağrı etkisiz');
    c.dispose();
  });

  test('sonucu BELİRSİZ kayıt (ağ hatası) discardPending ile SİLİNMEZ (sunucuda tamamlanmış olabilir)', () async {
    final service = _service();
    service.failures['uploadAttachment'] = <Object>[ApiException('Sunucu yanıt vermedi.')];
    final c = _controller(service);
    await c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    expect(c.failedCount, 1);
    await c.discardPending();
    expect(service.deleteAttachmentCalls, isEmpty);
    c.dispose();
  });

  test('turlar arası dürüst sayım: kesin ret + yeniden denenen başarı -> failedCount 1 kalır; resultFor güncel', () async {
    final service = _service();
    service.failures['uploadAttachment'] = <Object>[ApiException('Kopuk.')];
    final c = _controller(service);
    final gif = wkPhoto('hareketli.gif');
    final ok = wkPhoto('a.jpg');
    await c.run(<WorkPhotoPick>[gif, ok]);
    expect(c.failedCount, 2);
    expect(c.retryablePhotos, <WorkPhotoPick>[ok]);
    await c.retryFailed();
    expect(c.results.length, 1, reason: 'son tur yalnız yeniden deneneni içerir');
    expect(c.failedCount, 1, reason: 'GIF hâlâ yüklenmedi: "hepsi yüklendi" denmez');
    expect(c.phase, WorkUploadPhase.failed);
    expect(c.isUploaded(ok), isTrue);
    expect(c.isUploaded(gif), isFalse);
    expect(c.resultFor(gif)!.error, WorkAttachmentRules.typeAndSizeMessage);
    expect(c.error, WorkAttachmentRules.typeAndSizeMessage);
    expect(c.canRetry, isFalse);
    c.dispose();
  });

  test('UPLOAD_BUSY (503) ve UPLOAD_IN_PROGRESS: kayıt korunur, yeniden denemede AYNI kayıt', () async {
    final service = _service();
    service.failures['uploadAttachment'] = <Object>[
      ApiException('Sunucu şu anda çok sayıda yükleme alıyor.', statusCode: 503, code: 'UPLOAD_BUSY', retryAfterSeconds: 5),
      ApiException('Bu fotoğrafın yüklemesi zaten sürüyor.', statusCode: 409, code: 'UPLOAD_IN_PROGRESS'),
    ];
    final c = _controller(service);
    await c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    expect(c.canRetry, isTrue);
    await c.retryFailed();
    expect(c.canRetry, isTrue);
    await c.retryFailed();
    expect(c.failedCount, 0);
    expect(service.createAttachmentCalls.length, 1);
    expect(service.uploadAttachmentCalls.map((x) => x.attId).toSet().length, 1);
    c.dispose();
  });

  test('sürerken ikinci run yok sayılır; dispose sonrası yanıt yok sayılır', () async {
    final service = _service();
    final gate = Completer<void>();
    service.gates['createAttachment'] = <Completer<void>>[gate];
    final c = _controller(service);
    final running = c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    await _tick();
    expect(await c.run(<WorkPhotoPick>[wkPhoto('b.jpg')]), isEmpty);
    c.dispose();
    gate.complete();
    final results = await running;
    expect(results, isEmpty, reason: 'dispose sonrası sonuç yazılmaz');
    expect(service.uploadAttachmentCalls, isEmpty, reason: 'adım 2 başlatılmaz');
  });

  test('reset: son tur sonuçları atılır, yüklenenler listesi korunur; boş liste çalışmaz', () async {
    final service = _service();
    final c = _controller(service);
    await c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
    expect(c.results.length, 1);
    c.reset();
    expect(c.results, isEmpty);
    expect(c.phase, WorkUploadPhase.idle);
    expect(c.uploadedCount, 1);
    expect(await c.run(const <WorkPhotoPick>[]), isEmpty);
    expect(c.phase, WorkUploadPhase.idle);
    c.dispose();
  });
}
