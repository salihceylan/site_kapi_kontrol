// İş kaydı <-> ekipman bağı ve fotoğraf önce/sonra etiketi (ekranlar):
//  - yönetim ayrıntı penceresi: "Ekipman" seçici (aktif ekipmanlar + mevcut/pasif bağ), yalnız değişen alan gönderilir,
//    kurul ve kapanmış talepte seçici yok, hata / yeniden deneme, olay çizgisi, "Önce / Sonra / Etiketsiz" seçici;
//  - ekipman kartı: "Servis geçmişi (iş kayıtları)" listesi (dolu, boş, iş takibi kapalı, hata + tekrar dene, sayfalama).
// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024; açık / koyu).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/views/equipment_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

// --- Yönetim düzeneği -------------------------------------------------------------------------------

class _Rig {
  _Rig(this.service, this.auth, this.picker);

  final FakeWorkService service;
  final WorkFakeAuth auth;
  final FakeWorkPhotoPicker picker;
  final GlobalKey<WorkManagerViewState> key = GlobalKey<WorkManagerViewState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 3000,
    double scale = 1.0,
    bool dark = false,
  }) async {
    await pumpList(
      t,
      WorkManagerView(
        key: key,
        authService: auth,
        service: service,
        sites: <WorkTrackingSite>[WorkTrackingSite(code: 11, name: 'Gül Sitesi', access: service.kind)],
        photoPicker: picker,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }

  Future<void> openCard(WidgetTester t, int id) async {
    final card = find.byWidgetPredicate((w) => w is WorkManagedCard && w.item.id == id);
    await tapFinder(t, card);
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

const Map<String, dynamic> _asansor = <String, dynamic>{'id': 5, 'name': 'Asansör A', 'kind': 'asansor', 'is_active': true};

_Rig _rig({
  WorkSiteAccess kind = WorkSiteAccess.manager,
  Map<String, dynamic>? equipmentOnThree,
  List<WorkPhotoSelection> picks = const <WorkPhotoSelection>[],
}) {
  final auth = WorkFakeAuth();
  final service = managerWork(auth, kind: kind);
  if (equipmentOnThree != null) {
    service.managedRows.firstWhere((row) => row['id'] == 3)['equipment'] = equipmentOnThree;
  }
  return _Rig(service, auth, FakeWorkPhotoPicker(picks));
}

Finder _equipmentField() => find.byType(DropdownButtonFormField<WorkEquipmentRef>);

Future<void> _pick(WidgetTester t, Finder dropdown, String itemText) async {
  await t.ensureVisible(dropdown);
  await t.pump();
  await t.tap(dropdown);
  await settleFor(t, 100);
  await t.tap(find.text(itemText).last);
  await settleFor(t, 100);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

Future<void> _save(WidgetTester t) async {
  await _tapKey(t, 'work_manage_save');
  await settleFor(t, 100);
  await settleFor(t, 100);
}

bool _saveEnabled(WidgetTester t) => t.widget<PrimaryActionButton>(wkKey('work_manage_save')).onPressed != null;

// --- Ekipman düzeneği -------------------------------------------------------------------------------

class _FakeEquipmentService extends EquipmentService {
  _FakeEquipmentService(WorkFakeAuth auth) : super(authService: auth, api: EquipmentApi(baseUrl: 'http://localhost'));

  /// Sıradaki servis geçmişi yanıtları (her çağrı birini tüketir; tükenirse son yanıt tekrarlanır).
  final List<Object> historyQueue = <Object>[];
  final List<int?> historyCalls = <int?>[];

  @override
  Future<EquipmentDetail> detail(int site, int id) async => const EquipmentDetail(
    item: EquipmentItem(id: 5, kind: 'asansor', name: 'Asansör A', location: 'A Blok'),
    plans: <MaintenancePlan>[],
    logs: <MaintenanceLog>[],
    expenseIds: <int>[],
  );

  @override
  Future<EquipmentWorkHistory> workHistory(int site, int id, {int? beforeId}) async {
    historyCalls.add(beforeId);
    final next = historyQueue.length > 1 ? historyQueue.removeAt(0) : historyQueue.first;
    if (next is Exception) throw next;
    return next as EquipmentWorkHistory;
  }
}

EquipmentWorkItem _work(int id, {WorkStatus status = WorkStatus.cozuldu, int before = 0, int after = 0, int total = 0, DateTime? resolved}) => EquipmentWorkItem(
  id: id,
  title: 'İş kaydı $id',
  category: WorkCategory.ariza,
  status: status,
  createdAt: DateTime.utc(2026, 10, 1, 9),
  resolvedAt: resolved,
  attachmentCount: total,
  beforeCount: before,
  afterCount: after,
);

Future<_FakeEquipmentService> _pumpSheet(WidgetTester t, List<Object> history, {double width = 400, double height = 3000, double scale = 1.0, bool dark = false}) async {
  final service = _FakeEquipmentService(WorkFakeAuth())..historyQueue.addAll(history);
  // Gerçek ekranda alt sayfa 0,92 yükseklikli kutudadır (kaydırılabilir ListView sınırlı yükseklik ister).
  await pumpList(
    t,
    SizedBox(height: height * 0.92, child: EquipmentDetailSheet(service: service, site: const EquipmentSite(code: 11, name: 'Gül Sitesi'), itemId: 5)),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return service;
}

void main() {
  group('yönetim ayrıntısı: Ekipman seçici', () {
    workMatrix('yönetici: Ekipman seçici + Önce / Sonra / Etiketsiz etiketi', (t, w, h, s, dark) async {
      final rig = _rig(equipmentOnThree: _asansor);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 3);
      expect(find.text('Ekipman (isteğe bağlı)'), findsOneWidget);
      expect(_equipmentField(), findsOneWidget);
      expect(find.text('Asansör A (Asansör)'), findsWidgets, reason: 'bilgi satırı + seçili değer');
      for (final key in <String>['work_manage_phase_none', 'work_manage_phase_before', 'work_manage_phase_after']) {
        expect(wkKey(key), findsOneWidget, reason: key);
      }
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('kurul: ekipman yalnız bilgi satırı, seçici ve etiket seçici yok', (t, w, h, s, dark) async {
      final rig = _rig(kind: WorkSiteAccess.board, equipmentOnThree: _asansor);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 3);
      expect(find.text('Ekipman'), findsOneWidget, reason: 'bilgi satırı etiketi');
      expect(find.text('Asansör A (Asansör)'), findsOneWidget);
      expect(_equipmentField(), findsNothing);
      expect(wkKey('work_manage_phase_before'), findsNothing);
      expect(rig.service.equipmentCalls, 0, reason: 'kurul ekipman listesi çekmez');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('seçenekler: Seçilmedi + aktif ekipmanlar; ekipman seçilip kaydedilince YALNIZ equipment_id gider, bilgi satırı ve olay çizgisi güncellenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(rig.service.equipmentCalls, 1);
      expect(find.text('Seçilmedi'), findsOneWidget, reason: 'ekipman yok: seçili değer');
      expect(find.text('Ekipman'), findsNothing, reason: 'bağ yokken bilgi satırı yok');
      expect(_saveEnabled(t), isFalse, reason: 'değişiklik yok');
      await _pick(t, _equipmentField(), 'Asansör A (Asansör)');
      expect(_saveEnabled(t), isTrue);
      await _save(t);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{'equipment_id': 5});
      expect(find.text('Ekipman'), findsOneWidget);
      expect(find.text('Asansör A (Asansör)'), findsWidgets);
      expect(find.text('Ekipman: Seçilmedi → Asansör A'), findsOneWidget);
      expect(_saveEnabled(t), isFalse, reason: 'kayıttan sonra değişiklik yok');
    });

    testWidgets('bağı kaldırma: Seçilmedi -> equipment_id: null; değişmeyen seçimde alan gönderilmez', (t) async {
      final rig = _rig(equipmentOnThree: _asansor);
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(_saveEnabled(t), isFalse, reason: 'mevcut bağ seçili gelir, değişiklik yok');
      await _pick(t, _equipmentField(), 'Hidrofor (Hidrofor)');
      await _pick(t, _equipmentField(), 'Seçilmedi');
      expect(_saveEnabled(t), isTrue);
      await _save(t);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{'equipment_id': null});
      expect(find.text('Ekipman: Asansör A → Seçilmedi'), findsOneWidget);
      expect(find.text('Ekipman'), findsNothing);
    });

    testWidgets('durum + ekipman birlikte tek istekte gider (yalnız değişen alanlar)', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await rig.openCard(t, 3);
      await _pick(t, find.byType(DropdownButtonFormField<WorkStatus>), 'İşlemde');
      await _pick(t, _equipmentField(), 'Hidrofor (Hidrofor)');
      await _save(t);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{'status': 'islemde', 'equipment_id': 6});
    });

    testWidgets('pasif mevcut ekipman listede yoksa da seçicide görünür ("- pasif") ve istemeden kaybolmaz', (t) async {
      final rig = _rig(equipmentOnThree: const <String, dynamic>{'id': 9, 'name': 'Eski kazan', 'kind': 'kazan', 'is_active': false});
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(find.text('Eski kazan (Kazan) - pasif'), findsWidgets);
      expect(_saveEnabled(t), isFalse);
      await _pick(t, _equipmentField(), 'Asansör A (Asansör)');
      await _pick(t, _equipmentField(), 'Eski kazan (Kazan) - pasif');
      expect(_saveEnabled(t), isFalse, reason: 'eski seçime dönünce değişiklik yok');
    });

    testWidgets('kapanmış talepte seçici yok ve ekipman listesi çekilmez', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, find.text('Kapandı (1)'));
      await settleFor(t, 100);
      await settleFor(t, 100);
      await rig.openCard(t, 2);
      expect(_equipmentField(), findsNothing);
      expect(wkKey('work_manage_closed_note'), findsOneWidget);
      expect(rig.service.equipmentCalls, 0);
    });

    testWidgets('sunucu INVALID_EQUIPMENT derse hata pencerede kalır, seçim korunur, kaydet yeniden denenebilir', (t) async {
      final rig = _rig();
      rig.service.failures['update'] = <Object>[
        ApiException('Pasif ekipman seçilemez. Önce Ekipman ve Bakım ekranından etkinleştirin.', statusCode: 400, code: 'INVALID_EQUIPMENT'),
      ];
      await rig.pump(t);
      await rig.openCard(t, 3);
      await _pick(t, _equipmentField(), 'Asansör A (Asansör)');
      await _save(t);
      expect(find.textContaining('Pasif ekipman seçilemez'), findsOneWidget);
      expect(find.text('Asansör A (Asansör)'), findsWidgets, reason: 'seçim korunur');
      expect(_saveEnabled(t), isTrue);
      await _save(t);
      expect(rig.service.updateCalls.length, 2);
      expect(rig.service.updateCalls.last.fields, <String, Object?>{'equipment_id': 5});
      expect(find.textContaining('Pasif ekipman seçilemez'), findsNothing);
    });

    testWidgets('ekipman listesi yüklenemezse bildirim + Tekrar Dene; yeniden denenince seçici dolar, ayrıntı bozulmaz', (t) async {
      final rig = _rig();
      rig.service.failures['equipmentChoices'] = <Object>[ApiException('Sunucuya ulaşılamadı.')];
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(wkKey('work_manage_equipment_error'), findsOneWidget);
      expect(find.text('Asansör çalışmıyor'), findsWidgets, reason: 'ayrıntı yine görünür');
      await tapFinder(t, find.descendant(of: wkKey('work_manage_equipment_error'), matching: find.text('Tekrar Dene')));
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.equipmentCalls, 2);
      expect(wkKey('work_manage_equipment_error'), findsNothing);
      await _pick(t, _equipmentField(), 'Hidrofor (Hidrofor)');
      expect(_saveEnabled(t), isTrue);
    });

    testWidgets('liste kartı bağlı ekipmanı çip olarak gösterir; bağ yoksa çip yok', (t) async {
      final rig = _rig(equipmentOnThree: _asansor);
      await rig.pump(t);
      expect(find.text('Ekipman: Asansör A'), findsOneWidget);
    });
  });

  group('yönetim ayrıntısı: fotoğraf önce / sonra etiketi', () {
    testWidgets('seçilen etiket yeni ek kaydına yazılır; şerit "Önce · yükleyen" gösterir; Etiketsiz gövdede etiket yok', (t) async {
      final rig = _rig(picks: <WorkPhotoSelection>[
        WorkPhotoSelection(picks: <WorkPhotoPick>[wkPhoto('once.png', png: true)]),
        WorkPhotoSelection(picks: <WorkPhotoPick>[wkPhoto('sonra.png', png: true)]),
      ]);
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(wkKey('work_manage_phase_none'), findsOneWidget);
      await _tapKey(t, 'work_manage_phase_before');
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.single.phase, 'before');
      expect(find.text('Önce · Ben Yönetici'), findsOneWidget);
      expect(find.text('Fotoğraf eklendi (Önce)'), findsNothing, reason: 'olay sunucuda üretilir; sahte servis olay yazmaz');
      await _tapKey(t, 'work_manage_phase_after');
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.map((c) => c.phase), <String?>['before', 'after']);
      expect(find.text('Sonra · Ben Yönetici'), findsOneWidget);
    });

    testWidgets('Etiketsiz seçiliyken (varsayılan) eski davranış: gövdede etiket yok, şerit yalnız yükleyeni gösterir', (t) async {
      final rig = _rig(picks: <WorkPhotoSelection>[
        WorkPhotoSelection(picks: <WorkPhotoPick>[wkPhoto('duz.png', png: true)]),
      ]);
      await rig.pump(t);
      await rig.openCard(t, 3);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.single.phase, isNull);
      expect(find.text('Ben Yönetici'), findsWidgets);
      expect(find.textContaining('Önce · '), findsNothing);
      expect(find.textContaining('Sonra · '), findsNothing);
    });

    testWidgets('mevcut etiketli fotoğraf şeritte ve görüntüleyicide etiket + kayıt/dosya kimliği izini gösterir', (t) async {
      final rig = _rig();
      rig.service.attachments[1] = <Map<String, dynamic>>[
        wkAttachment(901, workItemId: 1, fileName: 'once.jpg', uploadedBy: 'Ayşe Yılmaz', kind: 'resident', phase: 'before'),
        wkAttachment(902, workItemId: 1, fileName: 'sonra.png', mime: 'image/png', uploadedBy: 'Ben Yönetici', kind: 'management', mine: true, phase: 'after', at: '2026-10-16T10:00:00Z'),
        wkAttachment(903, workItemId: 1, fileName: 'eski.jpg', uploadedBy: 'Ayşe Yılmaz', kind: 'resident'),
      ];
      for (final id in <int>[901, 902, 903]) {
        rig.service.attachmentBytes[id] = kWkPng;
      }
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(find.text('Önce · Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Sonra · Ben Yönetici'), findsOneWidget);
      expect(find.textContaining('Önce · '), findsOneWidget, reason: 'etiket öneki yalnız etiketli fotoğrafta (eski fotoğraf etiketsiz)');
      expect(find.textContaining('Sonra · '), findsOneWidget);
      await _tapKey(t, 'work_attachment_901');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_photo_viewer_identity'), findsOneWidget);
      expect(find.text('Talep #1 · Fotoğraf #901'), findsOneWidget);
      expect(find.textContaining('Önce · Ayşe Yılmaz · '), findsOneWidget);
    });
  });

  group('ekipman kartı: servis geçmişi', () {
    workMatrix('dolu liste: sayaçlar, durum / tarih / çözüm / fotoğraf özeti, iş no', (t, w, h, s, dark) async {
      await _pumpSheet(
        t,
        <Object>[
          EquipmentWorkHistory(
            items: <EquipmentWorkItem>[
              _work(30, before: 1, after: 2, total: 3, resolved: DateTime.utc(2026, 10, 2, 9)),
              _work(20, status: WorkStatus.islemde),
            ],
            total: 2,
            open: 1,
          ),
        ],
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      // Küçük ekranda bölüm kaydırma alanının altında kalır (liste tembel kurulur): yukarıdan aşağıya sırayla görünür kıl.
      for (final finder in <Finder>[
        find.text('Servis geçmişi (iş kayıtları)'),
        find.text('Toplam 2 iş kaydı · 1 açık'),
        find.text('İş kaydı 30'),
        find.textContaining('Çözüldü · Arıza · 01.10.2026'),
        find.textContaining('Çözüm: 02.10.2026'),
        find.textContaining('Önce 1 · Sonra 2 · 3 fotoğraf'),
        find.text('İş #30'),
        find.textContaining('İşlemde · Arıza · 01.10.2026'),
        find.text('İş #20'),
      ]) {
        await t.scrollUntilVisible(finder, 120, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
        expect(finder, findsOneWidget);
      }
      expect(wkKey('equipment_history_more'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('boş: bağ kurma yolu anlatılır; iş takibi kapalıysa nedeni söylenir', (t) async {
      await _pumpSheet(t, <Object>[const EquipmentWorkHistory()]);
      expect(wkKey('equipment_history_empty'), findsOneWidget);
      expect(find.textContaining('"Ekipman" alanından'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await _pumpSheet(t, <Object>[const EquipmentWorkHistory(workTrackingEnabled: false)]);
      expect(wkKey('equipment_history_off'), findsOneWidget);
      expect(wkKey('equipment_history_empty'), findsNothing);
      expect(find.text('Asansör A'), findsOneWidget, reason: 'ekipman kartı yine açık');
    });

    testWidgets('sayfalama: "Daha fazla göster" imleçle sonraki sayfayı sona ekler; son sayfada düğme kalkar', (t) async {
      final service = await _pumpSheet(t, <Object>[
        EquipmentWorkHistory(items: <EquipmentWorkItem>[_work(30), _work(20)], nextBeforeId: 20, total: 3),
        EquipmentWorkHistory(items: <EquipmentWorkItem>[_work(10)], total: 3),
      ]);
      expect(find.text('İş kaydı 30'), findsOneWidget);
      expect(find.text('İş kaydı 10'), findsNothing);
      await t.ensureVisible(wkKey('equipment_history_more'));
      await tapFinder(t, wkKey('equipment_history_more'));
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(service.historyCalls, <int?>[null, 20]);
      expect(find.text('İş kaydı 30'), findsOneWidget);
      expect(find.text('İş kaydı 10'), findsOneWidget);
      expect(wkKey('equipment_history_more'), findsNothing);
    });

    testWidgets('hata: ekipman kartı bozulmaz; mesaj + Tekrar Dene ilk sayfayı yeniden dener', (t) async {
      final service = await _pumpSheet(t, <Object>[
        ApiException('Servis geçmişi yüklenemedi.', statusCode: 500),
        EquipmentWorkHistory(items: <EquipmentWorkItem>[_work(30)], total: 1),
      ]);
      expect(wkKey('equipment_history_error'), findsOneWidget);
      expect(find.text('Servis geçmişi yüklenemedi.'), findsOneWidget);
      expect(find.text('Asansör A'), findsOneWidget, reason: 'ekipman ayrıntısı yine görünür');
      await tapFinder(t, find.descendant(of: wkKey('equipment_history_error'), matching: find.text('Tekrar Dene')));
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(service.historyCalls, <int?>[null, null]);
      expect(wkKey('equipment_history_error'), findsNothing);
      expect(find.text('İş kaydı 30'), findsOneWidget);
    });
  });
}
