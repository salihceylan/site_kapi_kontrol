// İş Takibi "Rapor" sekmesi (lib/ui/views/work_report_tab.dart + WorkManagerView kapısı): dönem ön ayarları,
// özel aralık doğrulaması (biçim, sıra, en çok 366 gün), özet kartları, görevli / kategori dökümleri, boş ve hata
// durumları, yenileme ve ROL KAPISI (yönetici + kurul görür; görevli ve diğerleri için sekme HİÇ çizilmez).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_report_tab.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

const WorkTrackingSite _gul = WorkTrackingSite(code: 11, name: 'Gül Sitesi');

/// 19.10.2026 11:00 İstanbul (UTC 08:00).
DateTime _now() => DateTime.utc(2026, 10, 19, 8);

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = wkKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

class _Rig {
  _Rig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;
  final GlobalKey<WorkReportTabState> key = GlobalKey<WorkReportTabState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 3000,
    double scale = 1.0,
    bool dark = false,
    WorkTrackingSite site = _gul,
  }) async {
    await pumpList(
      t,
      WorkReportTab(key: key, service: service, site: site, now: _now),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({WorkSiteAccess kind = WorkSiteAccess.manager}) {
  final auth = WorkFakeAuth();
  return _Rig(managerWork(auth, kind: kind), auth);
}

class _ViewRig {
  _ViewRig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;
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

_ViewRig _view(WorkSiteAccess kind) {
  final auth = WorkFakeAuth();
  return _ViewRig(managerWork(auth, kind: kind), auth);
}

void main() {
  group('taşma matrisi', () {
    workMatrix('dolu rapor: özet kartları, görevli dökümü, kategori satırları', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(wkKey('work_report_view'), findsOneWidget);
      expect(find.text('Açılan'), findsOneWidget);
      // Geniş ekranda görevli tablosunun başlığında da geçer.
      expect(find.text('Gecikmiş'), findsWidgets);
      expect(find.text('Ort. çözüm süresi'), findsOneWidget);
      expect(find.text('1 gün 6 sa'), findsOneWidget, reason: '30,4 saat');
      expect(find.text('20 sa'), findsOneWidget, reason: 'medyan');
      expect(find.text('Mehmet Usta'), findsOneWidget);
      expect(find.text('Atanmamış'), findsOneWidget);
      expect(find.text('Arıza'), findsOneWidget);
      expect(find.textContaining('01.10.2026 – 19.10.2026'), findsOneWidget);
      expect(find.textContaining('Hesaplanma: 19.10.2026 14:02'), findsOneWidget, reason: 'İstanbul saati');
    });

    workMatrix('özel aralık alanları ve boş durum', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.reportJson = wkReportJson(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19), empty: true);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(wkKey('work_report_empty'), findsOneWidget);
      expect(find.text('Bu aralıkta talep hareketi yok.'), findsOneWidget);
      await _tapKey(t, 'work_report_preset_custom');
      await settleFor(t, 100);
      expect(wkKey('work_report_from'), findsOneWidget);
      expect(wkKey('work_report_to'), findsOneWidget);
      expect(wkKey('work_report_apply'), findsOneWidget);
    });

    workMatrix('yönetim ekranı: Rapor sekmesi (yönetici)', (t, w, h, s, dark) async {
      final rig = _view(WorkSiteAccess.manager);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'work_tab_report');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_report_view'), findsOneWidget);
      expect(find.text('Mehmet Usta'), findsOneWidget);
    });
  });

  group('dönem', () {
    testWidgets('varsayılan Bu ay; Son 30 gün ve Son 90 gün sorguları takvim gününe göre', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rig.service.reportCalls.single.site, 11);
      expect(rig.service.reportCalls.single.from, DateTime(2026, 10, 1));
      expect(rig.service.reportCalls.single.to, DateTime(2026, 10, 19));
      await _tapKey(t, 'work_report_preset_last_30');
      await settleFor(t, 100);
      expect(rig.service.reportCalls.last.from, DateTime(2026, 9, 20));
      expect(rig.service.reportCalls.last.to, DateTime(2026, 10, 19));
      await _tapKey(t, 'work_report_preset_last_90');
      await settleFor(t, 100);
      expect(rig.service.reportCalls.last.from, DateTime(2026, 7, 22));
      expect(rig.service.reportCalls.length, 3);
      expect(find.textContaining('22.07.2026 – 19.10.2026'), findsOneWidget);
      // Aynı ön ayara yeniden dokunmak istek üretmez.
      await _tapKey(t, 'work_report_preset_last_90');
      await settleFor(t, 100);
      expect(rig.service.reportCalls.length, 3);
    });

    testWidgets('özel aralık: alan hatası, sıra hatası, 366 gün sınırı; geçerli aralık sorguya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'work_report_preset_custom');
      await settleFor(t, 100);
      expect(rig.service.reportCalls.length, 1, reason: 'özel aralık seçilince hemen istek yok');
      // Alanlar mevcut aralıkla dolu gelir.
      expect(find.descendant(of: wkKey('work_report_from'), matching: find.text('01.10.2026')), findsOneWidget);

      await _type(t, 'work_report_from', '31022026');
      await _tapKey(t, 'work_report_apply');
      await settleFor(t, 100);
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      expect(rig.service.reportCalls.length, 1);

      await _type(t, 'work_report_from', '20102026');
      await _type(t, 'work_report_to', '01102026');
      await _tapKey(t, 'work_report_apply');
      await settleFor(t, 100);
      expect(find.text('Başlangıç tarihi bitiş tarihinden sonra olamaz.'), findsOneWidget);
      expect(rig.service.reportCalls.length, 1);

      await _type(t, 'work_report_from', '01012025');
      await _type(t, 'work_report_to', '19102026');
      await _tapKey(t, 'work_report_apply');
      await settleFor(t, 100);
      expect(find.text('Aralık en çok 366 gün olabilir.'), findsOneWidget);
      expect(rig.service.reportCalls.length, 1);

      // Tam 366 gün (iki uç dahil) kabul edilir.
      await _type(t, 'work_report_from', '19102025');
      await _type(t, 'work_report_to', '19102026');
      await _tapKey(t, 'work_report_apply');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_report_range_error'), findsNothing);
      expect(rig.service.reportCalls.length, 2);
      expect(rig.service.reportCalls.last.from, DateTime(2025, 10, 19));
      expect(rig.service.reportCalls.last.to, DateTime(2026, 10, 19));
    });

    testWidgets('boş alan: "Tarih girin"; istek yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'work_report_preset_custom');
      await settleFor(t, 100);
      await _type(t, 'work_report_to', '');
      await _tapKey(t, 'work_report_apply');
      await settleFor(t, 100);
      expect(find.text('Tarih girin (GG.AA.YYYY).'), findsOneWidget);
      expect(rig.service.reportCalls.length, 1);
    });

    testWidgets('yenileme ön ayarlı dönemi BUGÜNE göre yeniden hesaplar (ay dönümü); özel aralık korunur', (t) async {
      final rig = _rig();
      // İstanbul 31.10.2026 23:00.
      var now = DateTime.utc(2026, 10, 31, 20);
      await pumpList(
        t,
        WorkReportTab(key: rig.key, service: rig.service, site: _gul, now: () => now),
        width: 400,
        height: 3000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t, 100);
      expect(rig.service.reportCalls.last.from, DateTime(2026, 10, 1));
      expect(rig.service.reportCalls.last.to, DateTime(2026, 10, 31));
      // Sekme açıkken gece yarısı geçti: İstanbul 01.11.2026 09:00.
      now = DateTime.utc(2026, 11, 1, 6);
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      expect(rig.service.reportCalls.last.from, DateTime(2026, 11, 1));
      expect(rig.service.reportCalls.last.to, DateTime(2026, 11, 1));
      expect(find.textContaining('01.11.2026 – 01.11.2026'), findsOneWidget);

      // Özel aralık yenilemede DEĞİŞMEZ.
      await _tapKey(t, 'work_report_preset_custom');
      await settleFor(t, 100);
      await _type(t, 'work_report_from', '01092026');
      await _type(t, 'work_report_to', '30092026');
      await _tapKey(t, 'work_report_apply');
      await settleFor(t, 100);
      now = DateTime.utc(2026, 12, 5, 6);
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      expect(rig.service.reportCalls.last.from, DateTime(2026, 9, 1));
      expect(rig.service.reportCalls.last.to, DateTime(2026, 9, 30));
    });
  });

  group('durumlar', () {
    testWidgets('yüklenirken iskelet; hata "hareket yok" DEMEZ; Tekrar Dene raporu getirir', (t) async {
      final rig = _rig();
      rig.service.failures['report'] = <Object>[ApiException('Rapor alınamadı.')];
      await rig.pump(t);
      expect(wkKey('work_report_error'), findsOneWidget);
      expect(find.text('Rapor alınamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(wkKey('work_report_empty'), findsNothing);
      expect(find.text('Açılan'), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_report_error'), findsNothing);
      expect(find.text('Açılan'), findsOneWidget);
      expect(rig.service.reportCalls.length, 2);
    });

    testWidgets('yenileme hatası eski raporu silmez (hata kutusuyla kalır); Yenile / reload() yeniden çeker', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['report'] = <Object>[ApiException('Yenilenemedi.')];
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      expect(find.text('Yenilenemedi.'), findsOneWidget);
      expect(find.text('Açılan'), findsOneWidget);
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t, 100);
      expect(find.text('Yenilenemedi.'), findsNothing);
      expect(rig.service.reportCalls.length, 3);
    });

    testWidgets('görevli dökümü boşken açıklama; dar ekranda kartlar, geniş ekranda tablo', (t) async {
      final rig = _rig();
      rig.service.reportJson = wkReportJson(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19))
        ..['by_assignee'] = <Object>[];
      await rig.pump(t);
      expect(wkKey('work_report_assignees_empty'), findsOneWidget);
      expect(find.text('Arıza'), findsOneWidget, reason: 'kategori dökümü yine çizilir');

      final wide = _rig();
      await wide.pump(t, width: 820, height: 1400);
      expect(wkKey('work_report_assignee_table'), findsOneWidget);
      expect(find.text('%33'), findsOneWidget);
      expect(find.text('%75'), findsOneWidget);
      expect(find.text('2 gün 4 sa'), findsOneWidget);

      final narrow = _rig();
      await narrow.pump(t, width: 360, height: 3000);
      expect(wkKey('work_report_assignee_table'), findsNothing);
      expect(find.text('Zamanında: %33'), findsOneWidget);
      expect(find.text('Ort. süre: 2 gün 4 sa'), findsOneWidget);
    });

    testWidgets('yüklenirken Uygula kapalı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'work_report_preset_custom');
      await settleFor(t, 100);
      expect(t.widget<PrimaryActionButton>(wkKey('work_report_apply')).onPressed, isNotNull);
    });
  });

  group('rol kapısı (fail-closed)', () {
    testWidgets('görevli: Rapor sekmesi HİÇ çizilmez, rapor isteği yapılmaz', (t) async {
      final rig = _view(WorkSiteAccess.staff);
      await rig.pump(t);
      expect(wkKey('work_tab_report'), findsNothing);
      expect(wkKey('work_tab_list'), findsNothing);
      expect(find.text('Rapor'), findsNothing);
      expect(wkKey('work_report_view'), findsNothing);
      expect(rig.service.reportCalls, isEmpty);
      expect(wkKey('work_search'), findsOneWidget, reason: 'liste olduğu gibi');
    });

    testWidgets('yönetici: sekme var; Rapor seçilince rapor çekilir, liste gizlenir; Talepler geri getirir', (t) async {
      final rig = _view(WorkSiteAccess.manager);
      await rig.pump(t);
      expect(wkKey('work_tab_report'), findsOneWidget);
      expect(rig.service.reportCalls, isEmpty, reason: 'sekme açılmadan istek yok');
      await _tapKey(t, 'work_tab_report');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_report_view'), findsOneWidget);
      expect(wkKey('work_search'), findsNothing);
      expect(rig.service.reportCalls.single.site, 11);
      // Sayfa kabuğunun yenilemesi rapor sekmesini de yeniler.
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.reportCalls.length, 2);
      await _tapKey(t, 'work_tab_list');
      await settleFor(t, 100);
      expect(wkKey('work_report_view'), findsNothing);
      expect(wkKey('work_search'), findsOneWidget);
    });

    testWidgets('kurul: sekme var ve rapor görünür (salt okunur notu korunur)', (t) async {
      final rig = _view(WorkSiteAccess.board);
      await rig.pump(t);
      expect(wkKey('work_tab_report'), findsOneWidget);
      await _tapKey(t, 'work_tab_report');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_report_view'), findsOneWidget);
      expect(find.text('Mehmet Usta'), findsOneWidget);
      expect(wkKey('work_read_only_note'), findsOneWidget);
    });

    testWidgets('sunucu 403 verirse (sahte görevli raporu): hata kutusu, "hareket yok" yok', (t) async {
      final rig = _rig(kind: WorkSiteAccess.staff);
      await rig.pump(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(wkKey('work_report_empty'), findsNothing);
    });
  });
}
