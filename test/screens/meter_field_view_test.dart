// Fotoğrafla sayaç okuma ekranı: "silmeyi biz yapmayız" (K6). Gönderim sonrası fotoğrafın telefondaki kopyası SİLİNMEZ; ekran bunu söyler ve kopyaları
// yalnız kullanıcı isterse ("Kopyaları sil") siler. Sunucu fotoğrafı almadıysa bu da bildirilir. AGENTS.md kural 6: dar ekran / koyu tema taşmaz.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/services/meter_field_queue.dart';
import 'package:site_kapi_kontrol/services/meter_ocr.dart';
import 'package:site_kapi_kontrol/ui/views/meter_field_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

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
  @override
  Future<List<String>> listPhotos() async => photos.keys.toList();
}

class _FakeService implements MeterService {
  _FakeService(this.photoStorage);

  final String photoStorage;
  int posted = 0;

  @override
  Future<List<FieldMeter>> listFieldMeters(int siteCode, {MeterKind? kind}) async => const <FieldMeter>[];

  @override
  Future<FieldReadingResult> postFieldReading(int siteCode, {required int meterId, required String date, required String value, String? photoBase64}) async {
    posted++;
    return FieldReadingResult(replayed: false, photoStorage: photoStorage);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoOcr implements MeterOcr {
  @override
  Future<String?> recognize(String imagePath) async => null;
  @override
  Future<void> close() async {}
}

const FieldMeter _meter = FieldMeter(id: 1, kind: MeterKind.water, serialNo: 'S1', apartmentLabel: 'A - 1');

Future<(_MemoryStore, MeterFieldQueue, _FakeService)> _pump(
  WidgetTester t, {
  String photoStorage = 'server',
  double width = 360,
  bool dark = false,
}) async {
  final store = _MemoryStore();
  final queue = MeterFieldQueue(store: store);
  await queue.enqueue(siteCode: 7, meter: _meter, date: '2026-10-21', value: '12.5', photo: Uint8List.fromList(<int>[1, 2, 3]));
  final service = _FakeService(photoStorage);
  // Ekran tam sayfa Scaffold'dur (uygulamada sınırlı yükseklikte kurulur); test düzeneği içeriği kaydırılabilir sardığı için yükseklik verilir.
  await pumpList(
    t,
    SizedBox(
      height: 760,
      child: MeterFieldView(
        authService: PeopleFakeAuth(),
        siteCode: 7,
        siteName: 'Gül Sitesi',
        service: service,
        queue: queue,
        ocr: _NoOcr(),
        enableCamera: false,
        clock: () => DateTime(2026, 10, 21, 10),
      ),
    ),
    width: width,
    height: 800,
    scale: 1.0,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return (store, queue, service);
}

void main() {
  testWidgets('gönderim sonrası: "kopyası silinmedi, isterseniz siz silebilirsiniz" notu; kopya kendiliğinden SİLİNMEZ', (t) async {
    final (store, _, service) = await _pump(t);
    expect(service.posted, 1);
    expect(find.textContaining('1 okuma gönderildi.'), findsOneWidget);
    expect(find.textContaining('Fotoğrafların telefonunuzdaki kopyası silinmedi'), findsOneWidget);
    expect(find.textContaining('isterseniz siz silebilirsiniz'), findsOneWidget);
    expect(store.photos, hasLength(1), reason: 'uygulama kopyayı kendiliğinden silmedi');
    expect(find.byKey(const ValueKey<String>('meter_kept_copies')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('kopyaları yalnız kullanıcı siler: "Kalsın" hiçbir şeyi silmez, "Kopyaları sil" siler ve düğme kaybolur', (t) async {
    final (store, _, _) = await _pump(t);
    await t.tap(find.byKey(const ValueKey<String>('meter_kept_copies')));
    await settleFor(t, 100);
    await settleFor(t, 300);
    expect(find.text('Telefondaki fotoğraf kopyaları'), findsOneWidget);
    expect(find.textContaining('kendiliğinden silmez'), findsOneWidget);

    await t.tap(find.text('Kalsın'));
    await settleFor(t, 100);
    await settleFor(t, 300);
    expect(store.photos, hasLength(1));
    expect(find.byKey(const ValueKey<String>('meter_kept_copies')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('meter_kept_copies')));
    await settleFor(t, 100);
    await settleFor(t, 300);
    await t.tap(find.text('Kopyaları sil'));
    await settleFor(t, 100);
    await settleFor(t, 300);
    expect(store.photos, isEmpty);
    expect(find.textContaining('1 fotoğraf kopyası telefondan silindi.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('meter_kept_copies')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sunucu fotoğrafı almadıysa ("none") bildirilir: kopyası telefonunuzda duruyor', (t) async {
    final (store, _, _) = await _pump(t, photoStorage: 'none', dark: true, width: 320);
    expect(find.textContaining('fotoğrafı sunucuya ulaşmadı'), findsOneWidget);
    expect(find.textContaining('kopyası telefonunuzda duruyor'), findsOneWidget);
    expect(store.photos, hasLength(1));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
