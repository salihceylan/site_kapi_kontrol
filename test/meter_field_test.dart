// Sayaç saha okuması: değer seçimi, sıradaki daire, çevrimdışı kuyruk ve gönderim kuralları.
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

  @override
  Future<FieldReadingResult> postFieldReading(int siteCode, {required int meterId, required String date, required String value, String? photoBase64}) {
    calls.add(meterId);
    return behave(meterId, photoBase64);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

FieldMeter meter(int id, String apt, {String? last, String? date}) =>
    FieldMeter(id: id, kind: MeterKind.water, serialNo: 'S$id', apartmentLabel: apt, lastValue: last, lastDate: date);

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
  });
}
