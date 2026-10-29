// Sayaç saha ekranı (MeterFieldView): blok seçimi, çekilen / çekilmeyen listesi, yeniden çekim, sıçrama uyarısı onay akışı (K12) ve
// reddedilen kayıt rozeti. Kamera ve metin tanıma kapalıdır (elle giriş); sunucu ve cihaz kuyruğu sahtedir.
//
// Fotoğrafla sayaç okuma ekranı: "silmeyi biz yapmayız" (K6). Gönderim sonrası fotoğrafın telefondaki kopyası SİLİNMEZ; ekran bunu söyler ve kopyaları
// yalnız kullanıcı isterse ("Kopyaları sil") siler. Sunucu fotoğrafı almadıysa bu da bildirilir. AGENTS.md kural 6: dar ekran / koyu tema taşmaz.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/services/meter_field_queue.dart';
import 'package:site_kapi_kontrol/services/meter_ocr.dart';
import 'package:site_kapi_kontrol/ui/views/meter_field_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _Auth extends AuthService {
  _Auth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  UserSession? get session => const UserSession(id: 1, fullName: 'Görevli Kişi', email: 'g@x.com', loginName: null, role: UserRole.siteManager, isActive: true, token: 'tok');
}

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
  Future<List<FieldMeter>> listFieldMeters(int siteCode, {MeterKind? kind, String? date}) async => const <FieldMeter>[];

  @override
  Future<FieldReadingResult> postFieldReading(int siteCode, {required int meterId, required String date, required String value, String? photoBase64, bool? confirmJump, bool replace = false}) async {
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

typedef _Post = ({int meterId, String value, bool? confirmJump, bool replace});

class _FakeMeters implements MeterService {
  _FakeMeters(this.meters, {this.onPost});

  final List<FieldMeter> meters;
  final Future<FieldReadingResult> Function(_Post post)? onPost;
  final List<_Post> posts = <_Post>[];
  final List<String?> listedDates = <String?>[];

  @override
  Future<List<FieldMeter>> listFieldMeters(int siteCode, {MeterKind? kind, String? date}) async {
    listedDates.add(date);
    return meters;
  }

  @override
  Future<FieldReadingResult> postFieldReading(
    int siteCode, {
    required int meterId,
    required String date,
    required String value,
    String? photoBase64,
    bool? confirmJump,
    bool replace = false,
  }) async {
    final post = (meterId: meterId, value: value, confirmJump: confirmJump, replace: replace);
    posts.add(post);
    return onPost == null ? const FieldReadingResult(replayed: false, photoStorage: 'none') : onPost!(post);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

FieldMeter plain(int id, String block, String unit, {String? last, String? lastDate, String? previous, FieldJump? jump}) => FieldMeter(
  id: id,
  kind: MeterKind.water,
  serialNo: 'S$id',
  apartmentLabel: '$block - $unit',
  blockName: block,
  unitLabel: unit,
  lastValue: last,
  lastDate: lastDate,
  previousValue: previous,
  jump: jump,
);

/// Son 3 dönem tüketimi 9, 11, 10 (medyan 10); eşik 5 kat = 50; önceki (son) okuma 130 (20 Ekim).
FieldMeter jumpy(int id, String block, String unit) =>
    plain(id, block, unit, last: '130.000', lastDate: '2026-10-20', previous: '130.000', jump: const FieldJump(median: '10.000', limit: '50.000', factor: 5));

const ValueKey<String> _valueField = ValueKey<String>('reading_value');
const ValueKey<String> _confirmButton = ValueKey<String>('reading_confirm');

Future<MeterFieldQueue> _pumpField(WidgetTester tester, _FakeMeters service, {MeterFieldQueue? queue}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fieldQueue = queue ?? MeterFieldQueue(store: _MemoryStore());
  await tester.pumpWidget(
    MaterialApp(
      home: MeterFieldView(
        authService: _Auth(),
        siteCode: 7,
        siteName: 'Gül Sitesi',
        service: service,
        queue: fieldQueue,
        ocr: _NoOcr(),
        enableCamera: false,
        clock: () => DateTime(2026, 10, 28, 10),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fieldQueue;
}

Future<void> enterAndConfirm(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(_valueField), value);
  await tester.tap(find.byKey(_confirmButton));
  await tester.pumpAndSettle();
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
  testWidgets('liste istemi bugünün tarihiyle gider (sunucu önceki okumayı ve sıçrama tabanını bu tarihe göre hesaplar)', (tester) async {
    final service = _FakeMeters(<FieldMeter>[plain(1, 'A Blok', '1')]);
    await _pumpField(tester, service);
    expect(service.listedDates, <String?>['2026-10-28']);
  });

  testWidgets('kamera desteklenmeyen platformda (web, masaüstü) boş alan yerine kısa açıklama gösterilir', (tester) async {
    final service = _FakeMeters(<FieldMeter>[plain(1, 'A Blok', '1')]);
    await _pumpField(tester, service);
    expect(find.byKey(const ValueKey<String>('meter_no_camera_note')), findsOneWidget);
    expect(find.text('Bu cihazda fotoğrafla okuma yok; değeri elle yazın.'), findsOneWidget);
    expect(find.byKey(_valueField), findsOneWidget, reason: 'elle giriş alanı yerinde');
  });

  group('sıçrama uyarısı (K12)', () {
    testWidgets('eşik aşılınca sorulur; "Değeri düzelt" hiçbir şey kaydetmez, "Doğru, kaydet" onay bayrağıyla gönderir', (tester) async {
      final service = _FakeMeters(<FieldMeter>[jumpy(1, 'A Blok', '1'), plain(2, 'A Blok', '2')]);
      final queue = await _pumpField(tester, service);
      expect(find.text('Sıradaki: A Blok - 1'), findsOneWidget);

      await enterAndConfirm(tester, '181');
      expect(find.byKey(const ValueKey<String>('jump_dialog')), findsOneWidget);
      expect(find.text('Olağan dışı tüketim'), findsOneWidget);
      expect(find.textContaining('51 tüketim'), findsOneWidget, reason: '181 - 130');
      expect(find.textContaining('ortanca tüketimi 10'), findsOneWidget);
      expect(find.textContaining('5 katıdır (50)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('jump_fix')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('jump_dialog')), findsNothing);
      expect(service.posts, isEmpty);
      expect(await queue.items(), isEmpty);
      expect(find.text('Sıradaki: A Blok - 1'), findsOneWidget, reason: 'sıradaki daireye geçilmedi');
      expect(tester.widget<TextField>(find.byKey(_valueField)).controller?.text, '181', reason: 'girilen değer korunur, görevli düzeltebilir');

      await tester.tap(find.byKey(_confirmButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('jump_confirm')));
      await tester.pumpAndSettle();

      expect(service.posts, <_Post>[(meterId: 1, value: '181', confirmJump: true, replace: false)]);
      expect(find.text('Sıradaki: A Blok - 2'), findsOneWidget);
      expect(find.textContaining('1 okuma gönderildi'), findsOneWidget);
      expect(await queue.items(), isEmpty);
    });

    testWidgets('eşik altında (ve eşitlikte) uyarı çıkmaz; sunucuya confirm_jump:false gider (sunucu da denetler)', (tester) async {
      final service = _FakeMeters(<FieldMeter>[jumpy(1, 'A Blok', '1'), jumpy(2, 'A Blok', '2')]);
      await _pumpField(tester, service);
      await enterAndConfirm(tester, '180');
      expect(find.byKey(const ValueKey<String>('jump_dialog')), findsNothing, reason: 'tüketim 50 = eşik');
      await enterAndConfirm(tester, '140,5');
      expect(find.byKey(const ValueKey<String>('jump_dialog')), findsNothing);
      expect(service.posts, <_Post>[(meterId: 1, value: '180', confirmJump: false, replace: false), (meterId: 2, value: '140.5', confirmJump: false, replace: false)]);
    });

    testWidgets('önceki okumadan küçük değer engellenir (sunucuya gitmez)', (tester) async {
      final service = _FakeMeters(<FieldMeter>[jumpy(1, 'A Blok', '1')]);
      final queue = await _pumpField(tester, service);
      await enterAndConfirm(tester, '120');
      expect(find.textContaining('önceki okumadan (130) küçük olamaz'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('jump_dialog')), findsNothing);
      expect(service.posts, isEmpty);
      expect(await queue.items(), isEmpty);
    });

    testWidgets('taban yoksa (3 dönemden az veri) cihaz uyarmaz; sunucu uyarırsa okuma ONAY BEKLER, Bekleyen listesinden onaylanınca gider', (tester) async {
      final service = _FakeMeters(
        <FieldMeter>[plain(1, 'A Blok', '1', last: '130.000', lastDate: '2026-10-20', previous: '130.000')],
        onPost: (post) async => post.confirmJump == true
            ? const FieldReadingResult(replayed: false, photoStorage: 'none')
            : throw ApiException('Olağan dışı tüketim: bu okuma, son 3 dönemin ortanca tüketiminin 5 katından fazla.', statusCode: 409, code: 'READING_JUMP'),
      );
      final queue = await _pumpField(tester, service);

      await enterAndConfirm(tester, '999');
      expect(find.byKey(const ValueKey<String>('jump_dialog')), findsNothing);
      expect(service.posts.single.confirmJump, isFalse);
      expect(find.textContaining('1 okuma olağan dışı tüketim nedeniyle onayınızı bekliyor'), findsOneWidget);
      expect(find.text('Bekleyen: 1'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('pending_badge')), matching: find.text('1')), findsOneWidget, reason: 'kırmızı rozet: sorunlu kayıt sayısı');
      final waiting = (await queue.items()).single;
      expect(waiting.needsJumpConfirm, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('pending_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Değer doğruysa onaylayın; değilse düzeltin.'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey<String>('pending_confirm_${waiting.id}')));
      await tester.pumpAndSettle();

      expect(service.posts.last, (meterId: 1, value: '999', confirmJump: true, replace: false));
      expect(await queue.items(), isEmpty);
      expect(find.text('Bekleyen okuma yok.'), findsOneWidget);
    });
  });

  testWidgets('sunucunun reddettiği kayıt anında bildirilir ve üst çubukta kırmızı rozetle görünür', (tester) async {
    final service = _FakeMeters(
      <FieldMeter>[plain(1, 'A Blok', '1')],
      onPost: (post) async => throw ApiException('Okuma, önceki okumadan (130.000) küçük olamaz.', statusCode: 409, code: 'READING_OUT_OF_ORDER'),
    );
    final queue = await _pumpField(tester, service);
    await enterAndConfirm(tester, '50');
    expect(find.textContaining('1 okuma sunucuya kabul edilmedi'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('pending_badge')), matching: find.text('1')), findsOneWidget);
    final rejected = (await queue.items()).single;
    expect(rejected.error, contains('küçük olamaz'));
    expect(rejected.needsJumpConfirm, isFalse);
  });

  group('blok seçimi ve liste', () {
    final all = <FieldMeter>[
      plain(1, 'A Blok', '1', last: '10.000', lastDate: '2026-10-20'),
      plain(2, 'A Blok', '2', last: '20.000', lastDate: '2026-10-20'),
      plain(3, 'B Blok', '1', last: '30.000', lastDate: '2026-10-20'),
      plain(4, 'B Blok', '2', last: '40.000', lastDate: '2026-10-20'),
    ];

    testWidgets('blok seçilince sıradaki daire o bloktan gelir; sayaçlar blok başına sayılır', (tester) async {
      final service = _FakeMeters(all);
      await _pumpField(tester, service);
      expect(find.text('Tümü (0/4)'), findsOneWidget);
      expect(find.text('A Blok (0/2)'), findsOneWidget);
      expect(find.text('B Blok (0/2)'), findsOneWidget);
      expect(find.text('Sıradaki: A Blok - 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('block_chip_B Blok')));
      await tester.pumpAndSettle();
      expect(find.text('Sıradaki: B Blok - 1'), findsOneWidget);

      await enterAndConfirm(tester, '35');
      expect(service.posts.single.meterId, 3);
      expect(find.text('Sıradaki: B Blok - 2'), findsOneWidget);
      expect(find.text('B Blok (1/2)'), findsOneWidget);

      await enterAndConfirm(tester, '45');
      expect(find.textContaining('Okunacak daire kalmadı (2/2)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('block_chip_all')));
      await tester.pumpAndSettle();
      expect(find.text('Sıradaki: A Blok - 1'), findsOneWidget, reason: 'tüm bloklarda eksik olan A Blok 1');
      expect(find.text('Tümü (2/4)'), findsOneWidget);
    });

    testWidgets('tek blok varsa blok seçici çizilmez', (tester) async {
      final service = _FakeMeters(<FieldMeter>[plain(1, 'A Blok', '1'), plain(2, 'A Blok', '2')]);
      await _pumpField(tester, service);
      expect(find.byKey(const ValueKey<String>('block_chip_all')), findsNothing);
    });

    testWidgets('liste çekilmeyenleri ve çekilenleri ayırır; çekilen seçilince YENİDEN ÇEKİM başlar ve sunucuya replace:true gider', (tester) async {
      final service = _FakeMeters(<FieldMeter>[
        plain(1, 'A Blok', '1', last: '500.000', lastDate: '2026-10-28', previous: '130.000'),
        plain(2, 'A Blok', '2', last: '20.000', lastDate: '2026-10-20', previous: '20.000'),
      ]);
      final queue = await _pumpField(tester, service);
      expect(find.text('Sıradaki: A Blok - 2'), findsOneWidget, reason: 'bugün okunan daire geçilir');

      await tester.tap(find.byKey(const ValueKey<String>('meter_list_open')));
      await tester.pumpAndSettle();
      expect(find.text('Çekilmeyenler (1)'), findsOneWidget);
      expect(find.text('Çekilenler (1)'), findsOneWidget);
      expect(find.text('Çekildi (500)'), findsOneWidget);
      expect(find.text('Çekilmedi · son okuma 20'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('meter_row_1')), matching: find.text('Yeniden çek')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('meter_row_2')), matching: find.text('Çek')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('meter_pick_1')));
      await tester.pumpAndSettle();
      expect(find.text('Yeniden çekim: A Blok - 1'), findsOneWidget);
      expect(find.textContaining('bugünkü okumanın (500) yerine geçer'), findsOneWidget);
      expect(find.text('Onayla ve değiştir'), findsOneWidget);

      await enterAndConfirm(tester, '120');
      expect(find.textContaining('önceki okumadan (130) küçük olamaz'), findsOneWidget, reason: 'yeniden çekimin tabanı bugünkü okuma (500) değil, ondan önceki okuma (130)');
      expect(service.posts, isEmpty);

      await enterAndConfirm(tester, '140,5');
      expect(service.posts, <_Post>[(meterId: 1, value: '140.5', confirmJump: false, replace: true)]);
      expect(find.text('Sıradaki: A Blok - 2'), findsOneWidget, reason: 'yeniden çekimden sonra sıradaki eksiğe dönülür');
      expect(await queue.items(), isEmpty);
    });

    testWidgets('atlanan daire listede "Atlandı" görünür ve oradan geri çekilebilir; "Vazgeç" seçimi bırakır', (tester) async {
      final service = _FakeMeters(<FieldMeter>[plain(1, 'A Blok', '1'), plain(2, 'A Blok', '2')]);
      await _pumpField(tester, service);
      await tester.tap(find.byKey(const ValueKey<String>('reading_skip')));
      await tester.pumpAndSettle();
      expect(find.text('Sıradaki: A Blok - 2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('meter_list_open')));
      await tester.pumpAndSettle();
      expect(find.text('Atlandı'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('meter_pick_1')));
      await tester.pumpAndSettle();
      expect(find.text('Sıradaki: A Blok - 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('reading_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Sıradaki: A Blok - 2'), findsOneWidget);
    });

    testWidgets('gönderilmeyi bekleyen okuma listede sarı durumda görünür ve yeniden çekilince eskisinin yerine geçer', (tester) async {
      final service = _FakeMeters(
        <FieldMeter>[plain(1, 'A Blok', '1')],
        onPost: (post) async => throw ApiException('Sunucuya bağlanılamadı.'),
      );
      final queue = await _pumpField(tester, service);
      await enterAndConfirm(tester, '12');
      expect((await queue.items()).map((e) => e.value), <String>['12']);

      await tester.tap(find.byKey(const ValueKey<String>('meter_list_open')));
      await tester.pumpAndSettle();
      expect(find.text('Gönderilmeyi bekliyor (12)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('meter_pick_1')));
      await tester.pumpAndSettle();
      expect(find.text('Yeniden çekim: A Blok - 1'), findsOneWidget);
      await enterAndConfirm(tester, '13');

      final items = await queue.items();
      expect(items.map((e) => (e.value, e.replace)), <(String, bool)>[('13', true)], reason: 'eski bekleyen kayıt silindi, yenisi yeniden çekim işaretli');
    });
  });

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
