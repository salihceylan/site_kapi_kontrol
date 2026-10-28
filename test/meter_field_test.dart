// Sayaç saha okuması: değer seçimi, sıradaki daire, blok, çevrimdışı kuyruk ve gönderim kuralları, sıçrama uyarısı (K12) ve yeniden çekim.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/services/meter_field_queue.dart';

class _MemoryStore implements MeterFieldStore {
  List<PendingMeterReading> items = <PendingMeterReading>[];
  final Map<String, Uint8List> photos = <String, Uint8List>{};

  @override
  Future<List<PendingMeterReading>> load() async => List<PendingMeterReading>.of(items);
  @override
  Future<void> save(List<PendingMeterReading> next) async => items = List<PendingMeterReading>.of(next);
  @override
  Future<String?> writePhoto(String id, Uint8List bytes) async {
    photos['mem/$id'] = bytes;
    return 'mem/$id';
  }

  @override
  Future<Uint8List?> readPhoto(String path) async => photos[path];
  @override
  Future<void> deletePhoto(String path) async => photos.remove(path);
}

class _FakeService implements MeterService {
  _FakeService(this.behave);

  final Future<FieldReadingResult> Function(int meterId, String? photo) behave;
  final List<int> calls = <int>[];

  /// Her gönderimin (sayaç, değer, confirm_jump, replace) bilgisi.
  final List<({int meterId, String value, bool? confirmJump, bool replace})> sent = <({int meterId, String value, bool? confirmJump, bool replace})>[];

  @override
  Future<FieldReadingResult> postFieldReading(
    int siteCode, {
    required int meterId,
    required String date,
    required String value,
    String? photoBase64,
    bool? confirmJump,
    bool replace = false,
  }) {
    calls.add(meterId);
    sent.add((meterId: meterId, value: value, confirmJump: confirmJump, replace: replace));
    return behave(meterId, photoBase64);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

FieldMeter meter(int id, String apt, {String? last, String? date}) =>
    FieldMeter(id: id, kind: MeterKind.water, serialNo: 'S$id', apartmentLabel: apt, lastValue: last, lastDate: date);

/// Son 3 dönem tüketimi 9, 11, 10 (medyan 10); eşik 5 kat = 50; son okuma 130.
FieldMeter jumpMeter({int id = 1, String label = 'A Blok - 1'}) => FieldMeter(
  id: id,
  kind: MeterKind.water,
  serialNo: 'S$id',
  apartmentLabel: label,
  lastValue: '130.000',
  lastDate: '2026-10-20',
  previousValue: '130.000',
  previousDate: '2026-10-20',
  jump: const FieldJump(median: '10.000', limit: '50.000', factor: 5),
);

const FieldReadingResult ok = FieldReadingResult(replayed: false, photoStorage: 'server');

void main() {
  group('değer seçimi', () {
    test('en uzun rakam dizisi alınır, virgül noktaya döner', () {
      expect(pickMeterValue('M3\n00123,456\n12'), '00123.456');
      expect(pickMeterValue('Qn 1.5  004512'), '004512');
    });
    test('son okumadan küçük adaylar elenir; hiç aday yoksa null', () {
      expect(pickMeterValue('0100 0250', lastValue: '200'), '0250');
      expect(pickMeterValue('abc'), isNull);
    });
    test('normalizeReadingValue biçimi doğrular', () {
      expect(normalizeReadingValue(' 1 234,5 '), '1234.5');
      expect(normalizeReadingValue('1,2345'), isNull);
      expect(normalizeReadingValue('-3'), isNull);
    });
  });

  test('sıradaki daire: bugün okunan, onaylanan ve atlanan geçilir', () {
    final all = <FieldMeter>[meter(1, 'A - 1', date: '2026-10-21'), meter(2, 'A - 2'), meter(3, 'A - 3'), meter(4, 'A - 4')];
    expect(nextFieldMeter(all, today: '2026-10-21')?.id, 2);
    expect(nextFieldMeter(all, today: '2026-10-21', done: <int>{2}, skipped: <int>{3})?.id, 4);
    expect(nextFieldMeter(all, today: '2026-10-21', done: <int>{2, 3, 4}), isNull);
  });

  group('kuyruk', () {
    test('internet yokken okuma ve fotoğraf cihazda kalır, gelince gider ve temizlenir', () async {
      final store = _MemoryStore();
      final queue = MeterFieldQueue(store: store);
      await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-21', value: '12.5', photo: Uint8List.fromList(<int>[1, 2, 3]));
      await queue.enqueue(siteCode: 7, meter: meter(2, 'A - 2'), date: '2026-10-21', value: '30');

      final down = _FakeService((_, _) async => throw ApiException('Sunucuya bağlanılamadı.'));
      final offline = await queue.flush(down);
      expect(offline.offline, isTrue);
      expect(offline.remaining, 2);
      expect(down.calls, <int>[1], reason: 'ilk hatada durur');
      expect(store.photos, hasLength(1));

      String? sentPhoto;
      final up = _FakeService((_, photo) async {
        sentPhoto ??= photo;
        return ok;
      });
      final online = await queue.flush(up);
      expect(online.sent, 2);
      expect(online.remaining, 0);
      expect(sentPhoto, isNotNull);
      expect(store.photos, isEmpty);
    });

    test('sunucunun kalıcı reddi kayda yazılır, kalanlar gider; düzeltilince yeniden denenir', () async {
      final store = _MemoryStore();
      final queue = MeterFieldQueue(store: store);
      await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-21', value: '5');
      await queue.enqueue(siteCode: 7, meter: meter(2, 'A - 2'), date: '2026-10-21', value: '9');
      final service = _FakeService((id, _) async => id == 1 ? throw ApiException('Okuma, önceki okumadan küçük olamaz.', statusCode: 409, code: 'READING_OUT_OF_ORDER') : ok);
      final report = await queue.flush(service);
      expect((report.sent, report.rejected, report.remaining, report.offline), (1, 1, 1, false));
      final rejected = (await queue.items()).single;
      expect(rejected.error, contains('küçük'));

      service.calls.clear();
      await queue.flush(service);
      expect(service.calls, isEmpty, reason: 'reddedilen düzeltilene dek denenmez');

      await queue.correct(rejected.id, '50');
      final okService = _FakeService((_, _) async => ok);
      final again = await queue.flush(okService);
      expect(again.sent, 1);
      expect(again.remaining, 0);
    });

    test('5xx ve 429 geçicidir (kayıt kalır)', () async {
      for (final status in <int>[500, 503, 429]) {
        final store = _MemoryStore();
        final queue = MeterFieldQueue(store: store);
        await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-21', value: '5');
        final report = await queue.flush(_FakeService((_, _) async => throw ApiException('x', statusCode: status)));
        expect(report.offline, isTrue, reason: '$status');
        expect((await queue.items()).single.error, isNull);
      }
    });

    test('kuyruk JSON gidiş-dönüşü ve silme', () async {
      final store = _MemoryStore();
      final queue = MeterFieldQueue(store: store);
      final item = await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-21', value: '5', photo: Uint8List(2));
      final back = PendingMeterReading.tryFromJson(item.toJson());
      expect(back?.value, '5');
      expect(back?.photoPath, item.photoPath);
      await queue.remove(item.id);
      expect(await queue.items(), isEmpty);
      expect(store.photos, isEmpty);
    });

    test('olağan dışı tüketim (READING_JUMP) engel değil: onay bekler, kalanlar gider; onaylanınca confirm_jump ile gider', () async {
      final store = _MemoryStore();
      final queue = MeterFieldQueue(store: store);
      await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-28', value: '500');
      await queue.enqueue(siteCode: 7, meter: meter(2, 'A - 2'), date: '2026-10-28', value: '30');
      final service = _FakeService((id, _) async => id == 1 ? throw ApiException('Olağan dışı tüketim.', statusCode: 409, code: 'READING_JUMP') : ok);

      final report = await queue.flush(service);
      expect((report.sent, report.rejected, report.jumpPending, report.remaining, report.offline), (1, 1, 1, 1, false));
      final waiting = (await queue.items()).single;
      expect(waiting.needsJumpConfirm, isTrue);
      expect(waiting.errorCode, 'READING_JUMP');
      expect(service.sent.first.confirmJump, isFalse, reason: 'yeni istemci her gönderimde sıçrama denetimi ister');

      service.sent.clear();
      await queue.flush(service);
      expect(service.sent, isEmpty, reason: 'onaylanana dek yeniden denenmez');

      await queue.confirmJump(waiting.id);
      final confirmed = (await queue.items()).single;
      expect(confirmed.error, isNull);
      expect(confirmed.errorCode, isNull);
      expect(confirmed.jumpConfirmed, isTrue);
      final accepting = _FakeService((_, _) async => ok);
      final again = await queue.flush(accepting);
      expect((again.sent, again.remaining), (1, 0));
      expect(accepting.sent.single.confirmJump, isTrue);
      expect(accepting.sent.single.value, '500');
    });

    test('değer düzeltilirse önceki sıçrama onayı geçersizdir; yeniden çekim bayrağı sunucuya gider', () async {
      final queue = MeterFieldQueue(store: _MemoryStore());
      final item = await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-28', value: '500', replace: true, jumpConfirmed: true);
      expect(item.replace, isTrue);
      await queue.correct(item.id, '501');
      final fixed = (await queue.items()).single;
      expect((fixed.value, fixed.jumpConfirmed, fixed.replace), ('501', false, true));
      final service = _FakeService((_, _) async => ok);
      await queue.flush(service);
      expect(service.sent.single, (meterId: 1, value: '501', confirmJump: false, replace: true));
    });

    test('eski sürümden kalan kuyruk kaydı (yeni alanlar yok) okunur ve gönderilir', () async {
      final old = PendingMeterReading.tryFromJson(<String, Object?>{'id': 'a', 'site': 7, 'meter': 1, 'apt': 'A - 1', 'kind': 'Su', 'date': '2026-10-21', 'value': '12.5'});
      expect(old, isNotNull);
      expect((old!.replace, old.jumpConfirmed, old.errorCode, old.needsJumpConfirm), (false, false, null, false));
      final json = old.copyWith(error: 'x', errorCode: 'READING_JUMP').toJson();
      expect(json['code'], 'READING_JUMP');
      expect(PendingMeterReading.tryFromJson(json)?.needsJumpConfirm, isTrue);
      expect(old.toJson().containsKey('replace'), isFalse, reason: 'varsayılanlar yazılmaz');
    });

    test('gönderim turu sürerken araya giren yeni okuma kaybolmaz', () async {
      final store = _MemoryStore();
      final queue = MeterFieldQueue(store: store);
      await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-28', value: '5');
      final gate = Completer<FieldReadingResult>();
      final service = _FakeService((_, _) => gate.future);
      final flushing = queue.flush(service);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.calls, <int>[1], reason: 'ilk okuma gönderimde (yanıt bekleniyor)');

      await queue.enqueue(siteCode: 7, meter: meter(2, 'A - 2'), date: '2026-10-28', value: '9');
      gate.complete(ok);
      final report = await flushing;
      expect(report.sent, 1);
      final left = await queue.items();
      expect(left.map((e) => e.meterId), <int>[2], reason: 'yeni okuma tur sonunda ezilmedi');
    });

    test('tur sürerken silinen kayıt gönderilmez', () async {
      final store = _MemoryStore();
      final queue = MeterFieldQueue(store: store);
      final first = await queue.enqueue(siteCode: 7, meter: meter(1, 'A - 1'), date: '2026-10-28', value: '5');
      await queue.enqueue(siteCode: 7, meter: meter(2, 'A - 2'), date: '2026-10-28', value: '9');
      final gate = Completer<FieldReadingResult>();
      final service = _FakeService((id, _) => id == 1 ? gate.future : Future<FieldReadingResult>.value(ok));
      final flushing = queue.flush(service);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final second = (await queue.items()).last;
      await queue.remove(second.id);
      gate.complete(ok);
      await flushing;
      expect(service.calls, <int>[1], reason: 'silinen ikinci kayıt gönderilmedi');
      expect(first.meterId, 1);
      expect(await queue.items(), isEmpty);
    });
  });

  group('sayı biçimleri', () {
    test('parseMilli: en çok 3 ondalık, kayan nokta yok', () {
      expect(parseMilli('130.000'), 130000);
      expect(parseMilli('12.5'), 12500);
      expect(parseMilli('0.001'), 1);
      expect(parseMilli('99999999999.999'), 99999999999999);
      expect(parseMilli('1.2345'), isNull);
      expect(parseMilli('-1'), isNull);
      expect(parseMilli('abc'), isNull);
      expect(parseMilli(null), isNull);
    });

    test('ekran metni: sondaki sıfırlar atılır, ayraç virgül', () {
      expect(formatMilli(24000), '24');
      expect(formatMilli(1234500), '1234,5');
      expect(formatMilli(1), '0,001');
      expect(formatMeterNumber('130.000'), '130');
      expect(formatMeterNumber('99.050'), '99,05');
      expect(formatMeterNumber('belli değil'), 'belli değil');
    });
  });

  group('blok', () {
    test('sunucu alanı yoksa etiketten türetilir; bloksuz sayaç boş blok verir', () {
      expect(meter(1, 'A Blok - 13').block, 'A Blok');
      expect(meter(1, 'A Blok - 13').unit, '13');
      expect(meter(1, 'Daire 7').block, '');
      expect(meter(1, 'Daire 7').unit, 'Daire 7');
      const withServer = FieldMeter(id: 1, kind: MeterKind.water, serialNo: 'S', apartmentLabel: 'A Blok - 13', blockName: 'B Blok', unitLabel: '5');
      expect((withServer.block, withServer.unit), ('B Blok', '5'));
    });

    test('fieldBlocks: listedeki sırayla, yinelenmez, bloksuz girmez', () {
      final all = <FieldMeter>[meter(1, 'A Blok - 1'), meter(2, 'A Blok - 2'), meter(3, 'B Blok - 1'), meter(4, 'Daire 9'), meter(5, 'C Blok - 1')];
      expect(fieldBlocks(all), <String>['A Blok', 'B Blok', 'C Blok']);
      expect(fieldBlocks(const <FieldMeter>[]), isEmpty);
    });

    test('sıradaki daire blokla sınırlanır', () {
      final all = <FieldMeter>[meter(1, 'A Blok - 1', date: '2026-10-21'), meter(2, 'A Blok - 2'), meter(3, 'B Blok - 1'), meter(4, 'B Blok - 2')];
      final b = <FieldMeter>[for (final m in all) if (m.block == 'B Blok') m];
      expect(nextFieldMeter(b, today: '2026-10-21')?.id, 3);
      expect(nextFieldMeter(b, today: '2026-10-21', done: <int>{3}, skipped: <int>{4}), isNull);
    });
  });

  group('sunucu yanıtı (geriye uyum)', () {
    test('yeni alanlar okunur: blok, önceki okuma, sıçrama tabanı', () {
      final list = FieldMeter.listFrom(<String, dynamic>{
        'items': <Object?>[
          <String, Object?>{
            'id': 4,
            'kind': 'water',
            'serial_no': 'S4',
            'apartment_label': 'A Blok - 1',
            'last_reading': <String, Object?>{'value': '130.000', 'date': '2026-10-20'},
            'block_name': 'A Blok',
            'unit_label': '1',
            'previous_reading': <String, Object?>{'value': '130.000', 'date': '2026-10-20'},
            'jump': <String, Object?>{'median': '10.000', 'limit': '50.000', 'factor': 5},
          },
        ],
        'jump_factor': 5,
      });
      final m = list.single;
      expect((m.block, m.unit, m.previousValue, m.previousDate), ('A Blok', '1', '130.000', '2026-10-20'));
      expect((m.jump?.median, m.jump?.limit, m.jump?.factor), ('10.000', '50.000', 5));
    });

    test('ESKİ sunucu (yeni alan yok): taban null, blok etiketten; bozuk jump nesnesi yok sayılır', () {
      final list = FieldMeter.listFrom(<String, dynamic>{
        'items': <Object?>[
          <String, Object?>{'id': 1, 'kind': 'water', 'serial_no': 'S1', 'apartment_label': 'A Blok - 1', 'last_reading': <String, Object?>{'value': '5.000', 'date': '2026-10-20'}},
          <String, Object?>{'id': 2, 'kind': 'water', 'serial_no': 'S2', 'apartment_label': 'B Blok - 1', 'jump': 'bozuk', 'previous_reading': 5},
        ],
      });
      expect(list.map((m) => m.block), <String>['A Blok', 'B Blok']);
      expect(list.every((m) => m.jump == null && m.previousValue == null), isTrue);
    });
  });

  group('sıçrama uyarısı (K12) ve sıra denetimi', () {
    test('tüketim eşiği AŞARSA uyarır: 130 -> 181 (tüketim 51 > 50); eşitlik ve altı uyarmaz', () {
      final finding = checkJump(jumpMeter(), '181');
      expect(finding, isNotNull);
      expect((finding!.consumption, finding.median, finding.limit, finding.factor), (51000, 10000, 50000, 5));
      expect(checkJump(jumpMeter(), '180'), isNull, reason: 'tüketim 50 = eşik');
      expect(checkJump(jumpMeter(), '140.5'), isNull);
      expect(checkJump(jumpMeter(), '130'), isNull, reason: 'tüketim 0');
    });

    test('3 dönemden az veri (taban yok), önceki okuma yok ya da değer önceki okumadan küçük: uyarı yok', () {
      expect(checkJump(meter(1, 'A - 1', last: '130', date: '2026-10-20'), '9999'), isNull, reason: 'sunucu taban göndermedi');
      const noPrevious = FieldMeter(id: 1, kind: MeterKind.water, serialNo: 'S', apartmentLabel: 'A - 1', jump: FieldJump(median: '10.000', limit: '50.000', factor: 5));
      expect(checkJump(noPrevious, '9999'), isNull);
      expect(checkJump(jumpMeter(), '100'), isNull, reason: 'önceki okumadan küçük: uyarı değil, sıra hatası');
      expect(checkJump(jumpMeter(), 'abc'), isNull);
    });

    test('K sunucudan gelir: 3 kat eşiğinde aynı değer uyarır', () {
      const strict = FieldMeter(
        id: 1,
        kind: MeterKind.water,
        serialNo: 'S',
        apartmentLabel: 'A - 1',
        previousValue: '130.000',
        jump: FieldJump(median: '10.000', limit: '30.000', factor: 3),
      );
      expect(checkJump(strict, '161')?.factor, 3);
      expect(checkJump(strict, '160'), isNull);
    });

    test('değer önceki okumadan küçükse engellenir; yeniden çekimde taban, bugünkü okuma değil önceki okumadır', () {
      expect(belowPreviousReading(jumpMeter(), '129', retake: false), '130.000');
      expect(belowPreviousReading(jumpMeter(), '130', retake: false), isNull);
      // Eski sunucu: son okuma var, önceki okuma ayrı gelmez.
      final legacy = meter(1, 'A - 1', last: '500', date: '2026-10-28');
      expect(belowPreviousReading(legacy, '400', retake: false), '500');
      expect(belowPreviousReading(legacy, '400', retake: true), isNull, reason: 'son okuma = değiştirilecek bugünkü okuma');
      // Yeni sunucu: bugünkü okuma 500, ondan önceki 130.
      final fresh = FieldMeter(
        id: 1,
        kind: MeterKind.water,
        serialNo: 'S',
        apartmentLabel: 'A - 1',
        lastValue: '500.000',
        lastDate: '2026-10-28',
        previousValue: '130.000',
        previousDate: '2026-10-20',
      );
      expect(belowPreviousReading(fresh, '129', retake: true), '130.000');
      expect(belowPreviousReading(fresh, '140', retake: true), isNull);
    });
  });
}
