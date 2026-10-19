// Ziyaretçi ve Kargo: yönetim / görevli ekranı (VisitorManagerView) + yeni kayıt formu; ROL MATRİSİ: yönetici ve
// görevli (yazar), yönetim kurulu (SALT OKUR: düğme yok).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu ayrımı (HATA ASLA "kayıt yok" demez), modül kapalı (+ Modüller düğmesi), sekmeler (Bekleyen /
// İçeride / Tümü), tür süzgeci, arama, site seçici, onaylı eylemler (Teslim edildi / Ayrıldı / İptal), 409 ve form.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/views/visitor_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/visitor_log_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'people_fixtures.dart' show pplApartmentJson;
import 'visitor_fixtures.dart';

const VisitorSite _gul = VisitorSite(code: 11, name: 'Gül Sitesi');
const VisitorSite _mavi = VisitorSite(code: 12, name: 'Mavi Park');

class _Rig {
  _Rig(this.service, this.auth);

  final FakeVisitorService service;
  final VisitorFakeAuth auth;
  final GlobalKey<VisitorManagerViewState> key = GlobalKey<VisitorManagerViewState>();
  int modulesOpened = 0;

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 3000,
    double scale = 1.0,
    bool dark = false,
    List<VisitorSite>? sites,
  }) async {
    await pumpList(
      t,
      VisitorManagerView(
        key: key,
        authService: auth,
        service: service,
        sites: sites ?? <VisitorSite>[VisitorSite(code: 11, name: 'Gül Sitesi', access: service.kind)],
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

_Rig _rig({VisitorSiteAccess kind = VisitorSiteAccess.manager, bool empty = false}) {
  final auth = VisitorFakeAuth();
  final service = seededVisitor(auth, kind: kind);
  if (empty) service.rows.clear();
  return _Rig(service, auth);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, vkKey(key));

List<int> _cardIds(WidgetTester t) => [
  for (final c in t.widgetList<VisitorManagedCard>(find.byType(VisitorManagedCard))) c.entry.id,
];

/// Verilen durumdaki durum çipi sayısı (eylem düğmesi etiketleriyle karışmaz).
int _chips(WidgetTester t, VisitorStatus status) =>
    t.widgetList<VisitorStatusChip>(find.byType(VisitorStatusChip)).where((c) => c.status == status).length;

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = vkKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

void main() {
  group('taşma matrisi', () {
    visitorMatrix('yönetici: bekleyen kargo listesi, çipler, eylem düğmeleri', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(_cardIds(t), <int>[3], reason: 'varsayılan sekme Bekleyen: yalnız bekleyen kargo');
      expect(find.text('Yurtiçi Kargo'), findsOneWidget);
      expect(find.text('Bekliyor'), findsWidgets);
      expect(find.text('Kaydeden: Kapıcı Hasan'), findsOneWidget);
      expect(vkKey('visitor_action_3_teslim_edildi'), findsOneWidget);
      expect(vkKey('visitor_action_3_iptal'), findsOneWidget);
      expect(vkKey('visitor_new_entry'), findsOneWidget);
      expect(vkKey('visitor_read_only_note'), findsNothing);
    });

    visitorMatrix('Tümü sekmesi: dört kayıt, kapanış ve kapatan çipleri', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'visitor_status_all');
      await settleFor(t, 100);
      expect(_cardIds(t), <int>[4, 3, 2, 1]);
      expect(_chips(t, VisitorStatus.teslimEdildi), 1);
      expect(_chips(t, VisitorStatus.iceride), 2);
      expect(find.text('Ortak alan'), findsOneWidget);
      expect(find.text('Kapatan: Kapıcı Hasan'), findsOneWidget);
    });

    visitorMatrix('kurul: salt okunur notu; eylem ve Yeni Kayıt yok', (t, w, h, s, dark) async {
      final rig = _rig(kind: VisitorSiteAccess.board);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(vkKey('visitor_read_only_note'), findsOneWidget);
      expect(vkKey('visitor_new_entry'), findsNothing);
      expect(find.byType(PrimaryActionButton), findsNothing);
      expect(_cardIds(t), <int>[3]);
    });

    visitorMatrix('boş / hata / modül kapalı ayrımı', (t, w, h, s, dark) async {
      final empty = _rig(empty: true);
      await empty.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Bekleyen kargo yok.'), findsOneWidget);

      final broken = _rig();
      broken.service.failures['listManaged'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await broken.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Bekleyen kargo yok.'), findsNothing, reason: 'hata ASLA "kayıt yok" demez');

      final off = _rig();
      off.service.failures['listManaged'] = <Object>[FakeVisitorService.moduleOff()];
      await off.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(vkKey('visitor_module_off'), findsOneWidget);
      expect(vkKey('visitor_open_modules'), findsOneWidget);
      expect(vkKey('visitor_new_entry'), findsNothing);
      expect(find.byType(VisitorManagedCard), findsNothing);
    });

    visitorMatrix('yeni kayıt formu: tür çipleri, daire seçici, sayaçlar', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      expect(find.text('Yeni Kayıt'), findsWidgets);
      expect(vkKey('visitor_form_kind_visitor'), findsOneWidget);
      expect(vkKey('visitor_form_apartment'), findsOneWidget);
      expect(vkKey('visitor_form_send'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    visitorMatrix('onay penceresi: taşma yok', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'visitor_action_3_teslim_edildi');
      await settleFor(t, 100);
      expect(vkKey('visitor_confirm_ok'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('liste', () {
    testWidgets('yüklenirken iskelet; sonra liste', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listManaged'] = <Completer<void>>[gate];
      await pumpList(
        t,
        VisitorManagerView(key: rig.key, authService: rig.auth, service: rig.service, sites: const <VisitorSite>[_gul]),
        width: 400, height: 3000, scale: 1.0, dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ListSkeleton), findsWidgets);
      expect(find.text('Bekleyen kargo yok.'), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byType(VisitorManagedCard), findsNWidgets(1));
    });

    testWidgets('modül kapalı: Modüller düğmesi geri çağrıyı çalıştırır', (t) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[FakeVisitorService.moduleOff()];
      await rig.pump(t);
      await _tapKey(t, 'visitor_open_modules');
      expect(rig.modulesOpened, 1);
    });

    testWidgets('sekmeler: Bekleyen -> İçeride -> Tümü; durum parametresi sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rig.service.listManagedCalls.last.status, 'bekliyor');
      expect(rig.service.listManagedCalls.last.limit, 50);
      await _tapKey(t, 'visitor_status_iceride');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.status, 'iceride');
      expect(_cardIds(t), <int>[4, 2]);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Haftalık temizlik için geldi.'), findsOneWidget);
      await _tapKey(t, 'visitor_status_all');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.status, isNull, reason: '"Tümü": durum parametresi yok');
      expect(find.byType(VisitorManagedCard), findsNWidgets(4));
    });

    testWidgets('tür süzgeci: yalnız o tür; boş süzgeç mesajı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_status_all');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_kind_visitor');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.kind, 'visitor');
      expect(_cardIds(t), <int>[4, 2]);
      await _tapKey(t, 'visitor_status_bekliyor');
      await settleFor(t, 100);
      expect(find.text('Bu süzgeç için kayıt bulunamadı.'), findsOneWidget);
      await _tapKey(t, 'visitor_kind_all');
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.kind, isNull);
      expect(_cardIds(t), <int>[3]);
    });

    testWidgets('arama: gecikmeli (350 ms) tek istek; ad / firma / daire eşleşir; temizleyince tüm liste', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_status_all');
      await settleFor(t, 100);
      final before = rig.service.listManagedCalls.length;
      await t.enterText(vkKey('visitor_search'), 'tem');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(vkKey('visitor_search'), 'temizlik');
      await t.pump(const Duration(milliseconds: 100));
      expect(rig.service.listManagedCalls.length, before, reason: 'yazarken istek yok');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.length, before + 1);
      expect(rig.service.listManagedCalls.last.query, 'temizlik');
      expect(_cardIds(t), <int>[2]);
      await tapFinder(t, find.byTooltip('Aramayı temizle'));
      await settleFor(t, 100);
      expect(_cardIds(t), <int>[4, 3, 2, 1]);
    });

    testWidgets('site seçici: seçilen sitenin listesi; eski sitenin kayıtları kalmaz', (t) async {
      final rig = _rig();
      rig.service.rows.add(vkEntry(50, name: 'Mavi kargo', site: 12));
      await rig.pump(t, sites: const <VisitorSite>[_gul, _mavi]);
      expect(_cardIds(t), <int>[3]);
      final dropdown = find.byType(DropdownButtonFormField<int>).first;
      await t.ensureVisible(dropdown);
      await t.pump();
      await t.tap(dropdown);
      await settleFor(t, 100);
      await t.tap(find.text('Mavi Park').last);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.site, 12);
      expect(_cardIds(t), <int>[50]);
    });

    testWidgets('görevli (STAFF): yazar; açıklama metni görevliye göre', (t) async {
      final rig = _rig(kind: VisitorSiteAccess.staff);
      await rig.pump(t);
      expect(vkKey('visitor_new_entry'), findsOneWidget);
      expect(vkKey('visitor_action_3_teslim_edildi'), findsOneWidget);
      expect(find.textContaining('Gelen kargoyu ve ziyaretçiyi kaydedin'), findsOneWidget);
      expect(vkKey('visitor_read_only_note'), findsNothing);
    });
  });

  group('eylemler', () {
    testWidgets('Teslim edildi: onay -> PATCH status; kayıt Bekleyen listesinden düşer', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_action_3_teslim_edildi');
      await settleFor(t, 100);
      expect(find.text('Teslim edildi olarak işaretle'), findsOneWidget);
      await _tapKey(t, 'visitor_confirm_keep');
      await settleFor(t, 100);
      expect(rig.service.updateCalls, isEmpty, reason: 'vazgeçilince istek yok');
      await _tapKey(t, 'visitor_action_3_teslim_edildi');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_confirm_ok');
      await settleFor(t, 100);
      await settleFor(t, 100);
      final call = rig.service.updateCalls.single;
      expect((call.site, call.id, call.status), (11, 3, VisitorStatus.teslimEdildi));
      expect(find.byType(VisitorManagedCard), findsNothing, reason: 'sekmeye uymayan kayıt düşer');
      expect(find.textContaining('olarak güncellendi'), findsOneWidget);
    });

    testWidgets('Ayrıldı: içerideki ziyaretçi kapanır; Tümü sekmesinde kart yerinde güncellenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_status_all');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_action_2_ayrildi');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_confirm_ok');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.updateCalls.single.status, VisitorStatus.ayrildi);
      expect(_cardIds(t), <int>[4, 3, 2, 1]);
      expect(_chips(t, VisitorStatus.ayrildi), 1);
      expect(vkKey('visitor_action_2_ayrildi'), findsNothing, reason: 'sonlanmış: geçiş yok');
      expect(vkKey('visitor_action_4_ayrildi'), findsOneWidget, reason: 'diğer ziyaretçi hâlâ içeride');
    });

    testWidgets('İptal: tehlike tonlu onay; iptal çağrısı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_action_3_iptal');
      await settleFor(t, 100);
      expect(find.text('Kayıt iptal edilsin mi?'), findsOneWidget);
      await _tapKey(t, 'visitor_confirm_ok');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.updateCalls.single.status, VisitorStatus.iptal);
    });

    testWidgets('409 INVALID_TRANSITION: düz Türkçe mesaj, liste sunucudan tazelenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['update'] = <Object>[FakeVisitorService.invalidTransition()];
      final before = rig.service.listManagedCalls.length;
      await _tapKey(t, 'visitor_action_3_teslim_edildi');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_confirm_ok');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.textContaining('değiştirilemez'), findsOneWidget);
      expect(rig.service.listManagedCalls.length, before + 1, reason: 'başkası kapatmış olabilir: yenilenir');
      expect(find.byType(VisitorManagedCard), findsOneWidget);
    });

    testWidgets('gönderim sürerken düğmeler kapalı (çift işlem yok)', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final gate = Completer<void>();
      rig.service.gates['update'] = <Completer<void>>[gate];
      await _tapKey(t, 'visitor_action_3_teslim_edildi');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_confirm_ok');
      await t.pump();
      expect(t.widget<PrimaryActionButton>(vkKey('visitor_action_3_teslim_edildi')).onPressed, isNull);
      expect(t.widget<PrimaryActionButton>(vkKey('visitor_action_3_iptal')).onPressed, isNull);
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.updateCalls.length, 1);
    });
  });

  group('yeni kayıt formu', () {
    testWidgets('boş gönderim: ad hatası + özet; istek yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_form_send');
      await settleFor(t, 100);
      expect(find.text('Bu alan boş olamaz.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('kargo kaydı: gövde doğru, 201 kayıt Bekleyen listesine gelir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _type(t, 'visitor_form_name', '  MNG Kargo  ');
      await _type(t, 'visitor_form_company', 'Takip 777');
      await _type(t, 'visitor_form_note', 'Kapıcıda');
      await _tapKey(t, 'visitor_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      final sent = rig.service.createCalls.single;
      expect(sent.site, 11);
      expect(sent.request.toJson(), <String, dynamic>{
        'kind': 'cargo',
        'visitor_name': 'MNG Kargo',
        'company': 'Takip 777',
        'note': 'Kapıcıda',
      });
      expect(vkKey('visitor_form_send'), findsNothing, reason: 'form kapandı');
      expect(find.text('Kargo kaydı açıldı (Bekliyor).'), findsOneWidget);
      expect(find.text('MNG Kargo'), findsOneWidget);
    });

    testWidgets('ziyaretçi kaydı: tür seçilir, daire seçilir, sekme İçeride olur', (t) async {
      final rig = _rig();
      rig.auth.apartmentsJson[301] = pplApartmentJson(301, 'A Blok - 5');
      await rig.pump(t);
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_form_kind_visitor');
      await settleFor(t, 100);
      expect(find.textContaining('"İçeride" olarak açılır'), findsOneWidget);
      await _tapKey(t, 'visitor_form_apartment');
      await settleFor(t, 100);
      await settleFor(t, 100);
      final picker = find.byType(AlertDialog).last;
      await tapFinder(t, find.descendant(of: picker, matching: find.textContaining('A Blok')).first);
      await settleFor(t, 100);
      expect(find.descendant(of: vkKey('visitor_form_apartment'), matching: find.textContaining('A Blok')), findsOneWidget);
      await _type(t, 'visitor_form_name', 'Veli Kaya');
      await _tapKey(t, 'visitor_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      final sent = rig.service.createCalls.single.request;
      expect(sent.kind, VisitorKind.visitor);
      expect(sent.apartmentId, isNotNull);
      expect(rig.service.listManagedCalls.last.status, 'iceride', reason: 'yeni kayıt kendi sekmesinde görünür');
      expect(find.text('Veli Kaya'), findsOneWidget);
    });

    testWidgets('gönderim hatası pencerede kalır, metin korunur; yeniden denemede başarı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['create'] = <Object>[
        ApiException('Seçilen daire bu sitede bulunamadı. Daireyi yeniden seçin.', statusCode: 404, code: 'APARTMENT_NOT_FOUND'),
      ];
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _type(t, 'visitor_form_name', 'PTT');
      await _tapKey(t, 'visitor_form_send');
      await settleFor(t, 100);
      expect(find.text('Seçilen daire bu sitede bulunamadı. Daireyi yeniden seçin.'), findsOneWidget);
      expect(find.descendant(of: vkKey('visitor_form_name'), matching: find.text('PTT')), findsOneWidget);
      await _tapKey(t, 'visitor_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createCalls.length, 2);
      expect(vkKey('visitor_form_send'), findsNothing);
    });

    testWidgets('çift gönderim: düğme kapanır, tek istek; geri tuşu gönderim sürerken kapatmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final gate = Completer<void>();
      rig.service.gates['create'] = <Completer<void>>[gate];
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _type(t, 'visitor_form_name', 'PTT');
      await _tapKey(t, 'visitor_form_send');
      expect(find.text('Kaydediliyor...'), findsOneWidget);
      await t.tap(vkKey('visitor_form_send'), warnIfMissed: false);
      await t.pump();
      expect(rig.service.createCalls.length, 1);
      expect(t.widget<ElevatedButton>(vkKey('visitor_form_send')).onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(vkKey('visitor_form_send'), findsOneWidget, reason: 'gönderim sürerken kapanmaz');
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 500);
      expect(vkKey('visitor_form_send'), findsNothing);
    });

    testWidgets('doldurulmuş form kapatılırken onay ister', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_form_close');
      await settleFor(t, 100);
      expect(vkKey('visitor_form_send'), findsNothing, reason: 'boş form onaysız kapanır');
      await _tapKey(t, 'visitor_new_entry');
      await settleFor(t, 100);
      await _type(t, 'visitor_form_name', 'Yarım');
      await _tapKey(t, 'visitor_form_close');
      await settleFor(t, 100);
      expect(find.text('Kayıt silinsin mi?'), findsOneWidget);
      await _tapKey(t, 'visitor_form_keep');
      await settleFor(t, 100);
      expect(vkKey('visitor_form_send'), findsOneWidget);
      await _tapKey(t, 'visitor_form_close');
      await settleFor(t, 100);
      await _tapKey(t, 'visitor_form_discard');
      await settleFor(t, 100);
      expect(vkKey('visitor_form_send'), findsNothing);
      expect(rig.service.createCalls, isEmpty);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('yönetim kartı tek birleşik etiket taşır', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Kargo: Yurtiçi Kargo\. Durum: Bekliyor\. Daire: A Blok / 5\..*Not: Büyük koli')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
