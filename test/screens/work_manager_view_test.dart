// İş Takibi: yönetim "Talepler" ekranı (WorkManagerView) + yönetim ayrıntı penceresi; ROL MATRİSİ: yönetici (yazar),
// görevli (kendine atanmış / atanmamış), yönetim kurulu (SALT OKUR: düğme yok, iç not ve telefon görünmez).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu ayrımı, modül kapalı (+ Modüller düğmesi), süzgeçler (durum / kategori / öncelik / atanan /
// arama), site seçici, güncelleme (yalnız değişen alanlar), 409 hataları, yorum (iç / herkese açık) ve kapanmış talep.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

const WorkTrackingSite _gul = WorkTrackingSite(code: 11, name: 'Gül Sitesi');
const WorkTrackingSite _mavi = WorkTrackingSite(code: 12, name: 'Mavi Park');

class _Rig {
  _Rig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;
  final GlobalKey<WorkManagerViewState> key = GlobalKey<WorkManagerViewState>();
  int modulesOpened = 0;

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 3000,
    double scale = 1.0,
    bool dark = false,
    List<WorkTrackingSite>? sites,
  }) async {
    final access = switch (service.kind) {
      WorkSiteAccess.manager => WorkSiteAccess.manager,
      WorkSiteAccess.staff => WorkSiteAccess.staff,
      WorkSiteAccess.board => WorkSiteAccess.board,
    };
    await pumpList(
      t,
      WorkManagerView(
        key: key,
        authService: auth,
        service: service,
        sites: sites ?? <WorkTrackingSite>[WorkTrackingSite(code: 11, name: 'Gül Sitesi', access: access)],
        onOpenModules: () => modulesOpened++,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({WorkSiteAccess kind = WorkSiteAccess.manager, bool empty = false}) {
  final auth = WorkFakeAuth();
  final service = managerWork(auth, kind: kind);
  if (empty) {
    service.managedRows.clear();
    service.events.clear();
  }
  return _Rig(service, auth);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

Future<void> _type(WidgetTester t, Finder field, String text) async {
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _pick(WidgetTester t, Finder dropdown, String itemText) async {
  await t.ensureVisible(dropdown);
  await t.pump();
  await t.tap(dropdown);
  await settleFor(t, 100);
  await t.tap(find.text(itemText).last);
  await settleFor(t, 100);
}

List<int> _cardIds(WidgetTester t) => [
  for (final c in t.widgetList<WorkManagedCard>(find.byType(WorkManagedCard))) c.item.id,
];

Future<void> _openCard(WidgetTester t, int id) async {
  final card = find.byWidgetPredicate((w) => w is WorkManagedCard && w.item.id == id);
  await tapFinder(t, card);
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Finder _priorityField() => find.byType(DropdownButtonFormField<WorkPriority>);
Finder _statusField() => find.byType(DropdownButtonFormField<WorkStatus>);
Finder _assigneeField() => find.byType(DropdownButtonFormField<int>);
Finder _dueField() => find.widgetWithText(TextFormField, 'Hedef tarih (isteğe bağlı)');

void main() {
  group('taşma matrisi', () {
    workMatrix('yönetici listesi: durum / öncelik / atanan / hedef tarih / sayaçlı süzgeç', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(_cardIds(t), <int>[4, 3, 1], reason: 'açık talepler, id azalan; kapanan yok');
      expect(find.text('Öncelik: Acil'), findsOneWidget);
      expect(find.text('Sakin: acil'), findsOneWidget);
      expect(find.text('Atanan: Ben Yönetici'), findsOneWidget);
      expect(find.text('Atanmamış'), findsOneWidget);
      expect(find.text('Hedef: 25.10.2026'), findsOneWidget);
      expect(find.text('Açık (3)'), findsOneWidget);
      expect(find.text('Yeni (1)'), findsOneWidget);
      expect(find.text('Kapandı (1)'), findsOneWidget);
      expect(wkKey('work_read_only_note'), findsNothing);
    });

    workMatrix('kurul listesi: salt okunur notu; iletişim yok', (t, w, h, s, dark) async {
      final rig = _rig(kind: WorkSiteAccess.board);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(wkKey('work_read_only_note'), findsOneWidget);
      expect(find.textContaining('yalnızca görüntüleyebilirsiniz'), findsOneWidget);
      expect(_cardIds(t), <int>[4, 3, 1]);
    });

    workMatrix('boş / hata / modül kapalı ayrımı', (t, w, h, s, dark) async {
      final empty = _rig(empty: true);
      await empty.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Açık talep yok.'), findsOneWidget);

      final broken = _rig();
      broken.service.failures['listManaged'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await broken.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Açık talep yok.'), findsNothing, reason: 'hata ASLA "talep yok" demez');

      final off = _rig();
      off.service.failures['listManaged'] = <Object>[FakeWorkService.moduleOff()];
      await off.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(wkKey('work_module_off'), findsOneWidget);
      expect(wkKey('work_open_modules'), findsOneWidget);
      expect(find.byType(WorkManagedCard), findsNothing);
    });
  });

  group('liste', () {
    testWidgets('yüklenirken iskelet; sonra liste', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listManaged'] = <Completer<void>>[gate];
      await pumpList(
        t,
        WorkManagerView(key: rig.key, authService: rig.auth, service: rig.service, sites: const <WorkTrackingSite>[_gul]),
        width: 400, height: 3000, scale: 1.0, dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ListSkeleton), findsWidgets);
      expect(find.text('Açık talep yok.'), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byType(WorkManagedCard), findsNWidgets(3));
    });

    testWidgets('modül kapalı: Modüller düğmesi geri çağrıyı çalıştırır; onOpenModules yoksa düğme yok', (t) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[FakeWorkService.moduleOff()];
      await rig.pump(t);
      await _tapKey(t, 'work_open_modules');
      expect(rig.modulesOpened, 1);
    });

    testWidgets('durum çipi: yalnız o durum istenir (sayaçla birlikte)', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rig.service.listManagedCalls.last.status, 'open');
      await _tapKey(t, 'work_status_kapandi');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.status, 'kapandi');
      expect(_cardIds(t), <int>[2]);
      await _tapKey(t, 'work_status_all');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.status, isNull, reason: '"Tümü": durum parametresi yok');
      expect(find.byType(WorkManagedCard), findsNWidgets(4));
    });

    testWidgets('kategori / öncelik / atanan süzgeçleri sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _pick(t, find.byKey(const ValueKey<String>('work_filter_category_')), 'Bakım');
      expect(rig.service.listManagedCalls.last.category, 'bakim');
      expect(_cardIds(t), <int>[4]);
      await _pick(t, find.byKey(const ValueKey<String>('work_filter_category_bakim')), 'Tüm kategoriler');
      await _pick(t, find.byKey(const ValueKey<String>('work_filter_priority_')), 'Acil');
      expect(rig.service.listManagedCalls.last.priority, 'acil');
      expect(_cardIds(t), <int>[1]);
      await _pick(t, find.byKey(const ValueKey<String>('work_filter_assigned_')), 'Atanmamış olanlar');
      expect(rig.service.listManagedCalls.last.assigned, 'none');
      expect(find.text('Bu süzgeç için talep bulunamadı.'), findsOneWidget);
    });

    testWidgets('arama: gecikmeli (350 ms) tek istek; temizleyince tüm liste', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final before = rig.service.listManagedCalls.length;
      await t.enterText(wkKey('work_search'), 'asan');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(wkKey('work_search'), 'asansör çalışmıyor');
      await t.pump(const Duration(milliseconds: 100));
      expect(rig.service.listManagedCalls.length, before, reason: 'yazarken istek yok');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.length, before + 1);
      expect(rig.service.listManagedCalls.last.query, 'asansör çalışmıyor');
      expect(_cardIds(t), <int>[3]);
      await tapFinder(t, find.byTooltip('Aramayı temizle'));
      await settleFor(t, 100);
      expect(_cardIds(t), <int>[4, 3, 1]);
    });

    testWidgets('site seçici: seçilen sitenin listesi; eski sitenin kayıtları kalmaz', (t) async {
      final rig = _rig();
      rig.service.managedRows.add(wkManaged(50, title: 'Mavi sitede talep', site: 12));
      await rig.pump(t, sites: const <WorkTrackingSite>[_gul, _mavi]);
      expect(_cardIds(t), <int>[4, 3, 1]);
      await _pick(t, find.byType(DropdownButtonFormField<int>).first, 'Mavi Park');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.site, 12);
      expect(_cardIds(t), <int>[50]);
    });

    testWidgets('görevli: yalnız kendine atanmış ya da atanmamış talepler; açıklama metni', (t) async {
      final rig = _rig(kind: WorkSiteAccess.staff);
      await rig.pump(t);
      expect(_cardIds(t), <int>[3, 1], reason: 'başkasına atanmış (4) görünmez');
      expect(find.textContaining('Size atanan ve henüz kimseye atanmamış'), findsOneWidget);
      expect(wkKey('work_read_only_note'), findsNothing);
    });

    testWidgets('kurul: iletişim ve iç not hiçbir yerde yok; kartlar yine tıklanır', (t) async {
      final rig = _rig(kind: WorkSiteAccess.board);
      await rig.pump(t);
      expect(find.textContaining('+9055'), findsNothing);
      expect(find.byType(WorkManagedCard), findsNWidgets(3));
    });
  });

  group('ayrıntı: yönetici', () {
    testWidgets('bilgiler, iletişim, iç not "İç" etiketiyle; atanabilir kişiler çekilir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      expect(find.text('Talep Ayrıntısı'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('+905551112233'), findsOneWidget);
      expect(find.text('Firmayı aradım, yarın gelecekler.'), findsOneWidget);
      expect(find.text('İç'), findsOneWidget);
      expect(find.text('Talebi yönet'), findsOneWidget);
      expect(rig.service.assigneeCalls, 1);
      expect(rig.service.getManagedCalls, <int>[3]);
    });

    testWidgets('değişiklik yokken Kaydet kapalı; yalnız öncelik değişince yalnız priority gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      expect(t.widget<PrimaryActionButton>(wkKey('work_manage_save')).onPressed, isNull);
      await _pick(t, _priorityField(), 'Acil');
      expect(t.widget<PrimaryActionButton>(wkKey('work_manage_save')).onPressed, isNotNull);
      await _tapKey(t, 'work_manage_save');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{'priority': 'acil'});
      expect(find.text('Öncelik: Normal → Acil'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(wkKey('work_manage_save')).onPressed, isNull, reason: 'kaydedildi: bekleyen değişiklik yok');
    });

    testWidgets('durum + atama + hedef tarih birlikte; sunucu geçişleri sunar', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      await _pick(t, _statusField(), 'İşlemde');
      await _pick(t, _assigneeField(), 'Mehmet Usta (Görevli)');
      await _type(t, _dueField(), '25102026');
      await _tapKey(t, 'work_manage_save');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{
        'status': 'islemde',
        'assigned_to': 9,
        'due_date': '2026-10-25',
      });
      expect(find.text('Durum: Yeni → İşlemde'), findsOneWidget);
      expect(find.text('Atama: Atanmamış → Mehmet Usta'), findsOneWidget);
      expect(find.text('Hedef tarih: yok → 25.10.2026'), findsOneWidget);
    });

    testWidgets('geçersiz hedef tarih: istek gitmez, alan hatası görünür', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      await _type(t, _dueField(), '31022026');
      await _pick(t, _priorityField(), 'Düşük');
      await _tapKey(t, 'work_manage_save');
      await settleFor(t, 100);
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      expect(rig.service.updateCalls, isEmpty);
    });

    testWidgets('409 INVALID_TRANSITION: pencere açık, düz Türkçe mesaj, seçim korunur; yeniden denemede başarı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      rig.service.failures['update'] = <Object>[
        ApiException(
          'Talebin durumu bu şekilde değiştirilemez. Talep başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin.',
          statusCode: 409,
          code: 'INVALID_TRANSITION',
        ),
      ];
      await _pick(t, _priorityField(), 'Acil');
      await _tapKey(t, 'work_manage_save');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.textContaining('değiştirilemez'), findsOneWidget);
      expect(find.text('Talep Ayrıntısı'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(wkKey('work_manage_save')).onPressed, isNotNull, reason: 'seçim korunur');
      await _tapKey(t, 'work_manage_save');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.updateCalls.length, 2);
      expect(find.textContaining('değiştirilemez'), findsNothing);
    });

    testWidgets('kapanmış talep: yönetim formu ve yorum kutusu yok; açıklayıcı not', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'work_status_kapandi');
      await settleFor(t, 100);
      await _openCard(t, 2);
      expect(wkKey('work_manage_closed_note'), findsOneWidget);
      expect(wkKey('work_manage_save'), findsNothing);
      expect(wkKey('work_manage_comment_send'), findsNothing);
      expect(find.text('Firmayı aradım, yarın gelecekler.'), findsOneWidget, reason: 'geçmiş yine okunur');
    });

    testWidgets('yorum: iç not varsayılan; "Sakine görünür" seçilince ipucu değişir ve internal=false gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      expect(find.text('İç not yalnız yönetimde görünür; talebi açan sakin göremez.'), findsOneWidget);
      await _type(t, wkKey('work_manage_comment_field'), 'Usta çağrıldı');
      await _tapKey(t, 'work_manage_comment_send');
      await settleFor(t, 100);
      await _tapKey(t, 'work_manage_comment_public');
      await settleFor(t, 100);
      expect(find.text('Bu yorumu talebi açan sakin de görür.'), findsOneWidget);
      await _type(t, wkKey('work_manage_comment_field'), 'Yarın geliyoruz');
      await _tapKey(t, 'work_manage_comment_send');
      await settleFor(t, 100);
      expect(rig.service.commentManagedCalls.map((c) => (c.body, c.internal)), <(String, bool)>[
        ('Usta çağrıldı', true),
        ('Yarın geliyoruz', false),
      ]);
      expect(find.text('Usta çağrıldı'), findsOneWidget);
      expect(find.text('Yarın geliyoruz'), findsOneWidget);
    });

    testWidgets('yorum hatası (200 yorum sınırı): metin korunur, mesaj düz Türkçe', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openCard(t, 3);
      rig.service.failures['commentManaged'] = <Object>[
        ApiException('Bu talebe daha fazla yorum eklenemez.', statusCode: 409, code: 'WORK_ITEM_COMMENT_LIMIT'),
      ];
      await _type(t, wkKey('work_manage_comment_field'), 'Son yorum');
      await _tapKey(t, 'work_manage_comment_send');
      await settleFor(t, 100);
      expect(find.text('Bu talebe daha fazla yorum eklenemez.'), findsOneWidget);
      expect(find.descendant(of: wkKey('work_manage_comment_field'), matching: find.text('Son yorum')), findsOneWidget);
    });

    testWidgets('talep artık görünmüyor (404): düz Türkçe uyarı, yönetim formu yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['getManaged'] = <Object>[FakeWorkService.notFound()];
      await _openCard(t, 3);
      expect(wkKey('work_detail_gone'), findsOneWidget);
      expect(wkKey('work_manage_save'), findsNothing);
    });

    testWidgets('modül ayrıntı açılırken kapatılmış (403): kapalı notu', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['getManaged'] = <Object>[FakeWorkService.moduleOff()];
      await _openCard(t, 3);
      expect(wkKey('work_detail_module_off'), findsOneWidget);
    });
  });

  group('ayrıntı: görevli', () {
    testWidgets('atanabilir liste yalnız kendisi (sunucu); başkasına atama seçeneği yok', (t) async {
      final rig = _rig(kind: WorkSiteAccess.staff);
      await rig.pump(t);
      await _openCard(t, 3);
      await t.ensureVisible(_assigneeField());
      await t.pump();
      await t.tap(_assigneeField());
      await settleFor(t, 100);
      expect(find.text('Mehmet Usta (Görevli)'), findsNothing);
      expect(find.text('Ben Yönetici (Yönetici)'), findsWidgets);
      await t.tap(find.text('Ben Yönetici (Yönetici)').last);
      await settleFor(t, 100);
      await _tapKey(t, 'work_manage_save');
      await settleFor(t, 100);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{'assigned_to': kWorkSelfCode});
    });
  });

  group('ayrıntı: yönetim kurulu (SALT OKUR)', () {
    testWidgets('düğme yok; salt okunur notu; telefon, kullanıcı kodu ve iç not görünmez; atanabilir liste çekilmez', (t) async {
      final rig = _rig(kind: WorkSiteAccess.board);
      await rig.pump(t);
      await _openCard(t, 3);
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: wkKey('work_read_only_note')), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Telefon'), findsNothing);
      expect(find.text('+905551112233'), findsNothing);
      expect(find.text('Firmayı aradım, yarın gelecekler.'), findsNothing, reason: 'iç not sunucudan gelmez');
      expect(find.text('Talebi yönet'), findsNothing);
      expect(wkKey('work_manage_save'), findsNothing);
      expect(wkKey('work_manage_comment_send'), findsNothing);
      expect(find.descendant(of: dialog, matching: find.byType(PrimaryActionButton)), findsNothing);
      expect(rig.service.assigneeCalls, 0);
      expect(rig.service.updateCalls, isEmpty);
      // Herkese açık olay kurulda da görünür.
      expect(find.text('Talebiniz alındı.'), findsOneWidget);
    });
  });

  group('ayrıntı pencereleri: taşma matrisi', () {
    workMatrix('yönetici: tüm alanlar, olay çizgisi, yorum kutusu', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openCard(t, 1);
      expect(find.text('Talep Ayrıntısı'), findsOneWidget);
      expect(wkKey('work_manage_save'), findsOneWidget);
      expect(find.text('Hedef tarih'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('kurul: salt okunur ayrıntı', (t, w, h, s, dark) async {
      final rig = _rig(kind: WorkSiteAccess.board);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openCard(t, 1);
      expect(find.text('Talep Ayrıntısı'), findsOneWidget);
      expect(wkKey('work_manage_save'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('erişilebilirlik', () {
    testWidgets('yönetim kartı tek birleşik etiket taşır', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Talep: Çatı sızıntısı\. Durum: İşlemde\. Öncelik: Acil\..*Atanan: Ben Yönetici\. Hedef tarih: 25\.10\.2026\.')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}

