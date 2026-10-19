// Firma ve Sözleşme Takibi: yönetim ekranı (ContractsView: Sözleşmeler | Firmalar) + sözleşme / firma formları + ayrıntı
// penceresi; ROL MATRİSİ: yönetici (yazar), yönetim kurulu ve görevli (SALT OKUR: yazma düğmesi yok).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu) iki sekme ve
// pencereler için; yükleniyor / hata + Tekrar Dene / boş / modül kapalı ayrımı (HATA ASLA "kayıt yok" demez); özet
// kutularının süzgeç olarak çalışması; arama, kategori ve firma süzgeci; YALNIZ opak `cursor` ile sayfalama; ayrıntı (tutar Türkçe para biçimi, dönem, fesih son günü); onaylı Feshet / Yeniden etkinleştir;
// form doğrulaması (bitiş >= başlangıç, gün aralıkları, virgüllü tutar, firma seçimi); yalnız aktif firma seçici ve
// "Yeni firma" kısayolu; firma kartında tel: / mailto: ve pasife alma.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/ui/views/contracts_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'contract_fixtures.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;

class _Rig {
  _Rig(this.service, this.auth);

  final FakeContractService service;
  final ContractFakeAuth auth;
  final GlobalKey<ContractsViewState> key = GlobalKey<ContractsViewState>();
  final List<Uri> launched = <Uri>[];
  int modulesOpened = 0;

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 3000,
    double scale = 1.0,
    bool dark = false,
    List<ContractSite>? sites,
  }) async {
    await pumpList(
      t,
      ContractsView(
        key: key,
        authService: auth,
        service: service,
        sites: sites ??
            <ContractSite>[ContractSite(code: 11, name: 'Gül Sitesi', access: service.kind)],
        onOpenModules: () => modulesOpened++,
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
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

_Rig _rig({ContractSiteAccess kind = ContractSiteAccess.manager, bool empty = false}) {
  final auth = ContractFakeAuth();
  final service = seededContracts(auth, kind: kind);
  if (empty) {
    service.contracts.clear();
    service.vendors.clear();
  }
  return _Rig(service, auth);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, ctKey(key));

List<int> _cardIds(WidgetTester t) => <int>[
  for (final c in t.widgetList<ContractCard>(find.byType(ContractCard))) c.contract.id,
];

List<int> _vendorIds(WidgetTester t) => <int>[
  for (final c in t.widgetList<ContractVendorCard>(find.byType(ContractVendorCard))) c.vendor.id,
];

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = ctKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Finder _tileValue(String state, String value) =>
    find.descendant(of: ctKey('contract_summary_$state'), matching: find.text(value));

/// En üstteki penceredeki (seçici) metin.
Finder _inTopDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog).last, matching: find.text(text));

Future<void> _openVendorsTab(WidgetTester t) async {
  await _tapKey(t, 'contracts_tab_vendors');
  await settleFor(t, 100);
}

void main() {
  group('taşma matrisi', () {
    contractMatrix('yönetici: Sözleşmeler sekmesi (özet, kartlar, kalan gün, fesih son günü)', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(_cardIds(t), <int>[13, 12, 11, 15, 14], reason: 'bitiş tarihi artan; süresiz en sonda');
      expect(_tileValue('aktif', '2'), findsOneWidget);
      expect(_tileValue('yaklasiyor', '1'), findsOneWidget);
      expect(_tileValue('sona_erdi', '1'), findsOneWidget);
      expect(_tileValue('feshedildi', '1'), findsOneWidget);
      expect(find.text('Bitiş: 31.12.2026 · 73 gün kaldı'), findsOneWidget);
      expect(find.text('Bitiş: 05.11.2026 · 17 gün kaldı'), findsOneWidget);
      expect(find.text('Bitiş: 30.09.2026 · 19 gün önce bitti'), findsOneWidget);
      expect(find.text('Süresiz'), findsOneWidget);
      expect(find.text('Bitiş: 01.03.2027'), findsOneWidget, reason: 'feshedilmişte kalan gün yazılmaz');
      expect(find.text('Fesih bildirimi son günü: 01.12.2026'), findsOneWidget);
      expect(ctKey('contract_new'), findsOneWidget);
      expect(ctKey('contract_read_only_note'), findsNothing);
    });

    contractMatrix('yönetici: Firmalar sekmesi (iletişim bağlantıları, yazma düğmeleri)', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openVendorsTab(t);
      expect(_vendorIds(t), <int>[2, 3, 1]);
      expect(ctKey('contract_vendor_call_1'), findsOneWidget);
      expect(ctKey('contract_vendor_mail_1'), findsOneWidget);
      expect(ctKey('contract_vendor_mail_2'), findsNothing);
      expect(ctKey('contract_vendor_edit_1'), findsOneWidget);
      expect(ctKey('contract_vendor_toggle_3'), findsOneWidget);
      expect(find.descendant(of: ctKey('contract_vendor_card_3'), matching: find.text('Pasif')), findsOneWidget);
      expect(find.descendant(of: ctKey('contract_vendor_card_1'), matching: find.text('Aktif')), findsOneWidget);
      expect(find.text('Etkinleştir'), findsOneWidget);
      expect(find.text('2 sözleşme'), findsWidgets);
      expect(ctKey('contract_vendor_new'), findsOneWidget);
    });

    contractMatrix('kurul: salt okunur not; yazma düğmesi yok (iki sekme)', (t, w, h, s, dark) async {
      final rig = _rig(kind: ContractSiteAccess.board);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(ctKey('contract_read_only_note'), findsOneWidget);
      expect(ctKey('contract_new'), findsNothing);
      expect(_cardIds(t), hasLength(5));
      await _openVendorsTab(t);
      expect(ctKey('contract_vendor_new'), findsNothing);
      expect(ctKey('contract_vendor_edit_1'), findsNothing);
      expect(ctKey('contract_vendor_toggle_1'), findsNothing);
      expect(ctKey('contract_vendor_call_1'), findsOneWidget, reason: 'iletişim herkese açık');
    });

    contractMatrix('ayrıntı penceresi: tutar, dönem, fesih son günü, Feshet', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'contract_card_11');
      await settleFor(t, 100);
      expect(find.text('1.250,00 ₺'), findsOneWidget);
      expect(find.text('Aylık'), findsOneWidget);
      expect(find.text('01.12.2026'), findsOneWidget);
      expect(ctKey('contract_detail_terminate'), findsOneWidget);
      expect(ctKey('contract_detail_edit'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    contractMatrix('sözleşme formu: boş gönderimde alan hataları', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'contract_new');
      await settleFor(t, 100);
      expect(find.text('Yeni Sözleşme'), findsWidgets);
      await _tapKey(t, 'contract_form_send');
      await settleFor(t, 100);
      expect(find.text('Firma seçin.'), findsOneWidget);
      expect(find.text('Sözleşme başlığını girin.'), findsOneWidget);
      expect(rig.service.createContractCalls, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    contractMatrix('firma formu: alanlar ve kategori', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openVendorsTab(t);
      await _tapKey(t, 'contract_vendor_new');
      await settleFor(t, 100);
      expect(ctKey('contract_vendor_form_name'), findsOneWidget);
      expect(ctKey('contract_vendor_form_category'), findsOneWidget);
      expect(ctKey('contract_vendor_form_email'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Sözleşmeler sekmesi', () {
    testWidgets('yüklenirken iskelet; hata ASLA "kayıt yok" demez; Tekrar Dene listeyi getirir', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listContracts'] = <Completer<void>>[gate];
      rig.service.failures['listContracts'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await pumpList(
        t,
        ContractsView(
          key: rig.key,
          authService: rig.auth,
          service: rig.service,
          sites: const <ContractSite>[ContractSite(code: 11, name: 'Gül Sitesi')],
        ),
        width: 400,
        height: 3000,
        scale: 1.0,
        dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ListSkeleton), findsWidgets);
      gate.complete();
      await settleFor(t, 100);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Henüz sözleşme yok.'), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(_cardIds(t), hasLength(5));
    });

    testWidgets('boş: yönetici mesajı; modül kapalı: kart + Modüller düğmesi', (t) async {
      final empty = _rig(empty: true);
      await empty.pump(t);
      expect(find.text('Henüz sözleşme yok.'), findsOneWidget);

      final off = _rig();
      off.service.failures['listContracts'] = <Object>[FakeContractService.moduleOff()];
      await off.pump(t);
      expect(ctKey('contract_module_off'), findsOneWidget);
      expect(ctKey('contract_new'), findsNothing);
      await _tapKey(t, 'contract_open_modules');
      expect(off.modulesOpened, 1);
    });

    testWidgets('özet kutusu süzgeçtir: Bitişi yaklaşan -> yalnız o; yeniden dokununca tümü', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rig.service.listContractsCalls.last.state, 'all');
      expect(rig.service.listContractsCalls.last.limit, ContractListTabState.pageSize);
      await _tapKey(t, 'contract_summary_yaklasiyor');
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.state, 'yaklasiyor');
      expect(_cardIds(t), <int>[12]);
      expect(find.text('Bitişi yaklaşan'), findsWidgets);
      await _tapKey(t, 'contract_summary_yaklasiyor');
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.state, 'all');
      expect(_cardIds(t), hasLength(5));
    });

    testWidgets('arama (gecikmeli) ve kategori + firma süzgeci sunucuya gider; temizle', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _type(t, 'contract_search', 'kamera');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.query, 'kamera');
      expect(_cardIds(t), <int>[15]);

      await _tapKey(t, 'contract_filters_reset');
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.query, '');
      expect(_cardIds(t), hasLength(5));

      await tapFinder(t, ctKey('contract_category_filter_all'));
      await tapFinder(t, find.text('Güvenlik').last);
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.category, 'guvenlik');
      expect(_cardIds(t), <int>[12, 15]);

      await tapFinder(t, ctKey('contract_vendor_filter_0_3'));
      await tapFinder(t, find.text('Parlak Temizlik (pasif)').last);
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.vendorId, 3);
      expect(find.text('Bu süzgeç için sözleşme bulunamadı.'), findsOneWidget);
    });

    testWidgets('sayfalama: next_cursor aynen `cursor` olarak gider; "Daha fazla yükle"; süzgeç imleci sıfırlar', (t) async {
      final rig = _rig();
      for (var i = 0; i < 35; i++) {
        rig.service.contracts.add(
          ctContract(200 + i, title: 'Ek sözleşme $i', end: '2027-0${1 + i % 9}-1${i % 10}'),
        );
      }
      await rig.pump(t);
      expect(rig.service.listContractsCalls.last.cursor, isNull);
      expect(_cardIds(t), hasLength(30));
      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(_cardIds(t), hasLength(40));
      expect(rig.service.listContractsCalls.last.cursor, 'c30|all|');
      expect(find.text('Daha fazla yükle'), findsNothing);
      await _tapKey(t, 'contract_summary_aktif');
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.cursor, isNull, reason: 'süzgeç değişince ilk sayfa');
    });

    testWidgets('yarış: eski ilk sayfa yanıtı EN SON gelirse imleç tablosu bozulmaz; sonraki sayfa güncel süzgecin imleciyle', (t) async {
      final rig = _rig();
      for (var i = 0; i < 35; i++) {
        rig.service.contracts.add(
          ctContract(200 + i, title: 'Ek sözleşme $i', end: '2027-0${1 + i % 9}-1${i % 10}'),
        );
      }
      await rig.pump(t);
      expect(_cardIds(t), hasLength(30));

      // İki hızlı süzgeç değişimi: önce "Yürürlükte" (eski istek), hemen ardından süzgeç kaldırılır (yeni istek).
      final older = Completer<void>();
      final newer = Completer<void>();
      rig.service.gates['listContracts'] = <Completer<void>>[older, newer];
      await _tapKey(t, 'contract_summary_aktif');
      await _tapKey(t, 'contract_summary_aktif');
      final calls = rig.service.listContractsCalls;
      expect(<String>[calls[calls.length - 2].state, calls.last.state], <String>['aktif', 'all']);

      // Yeni yanıt önce, eski yanıt EN SON gelir.
      newer.complete();
      await settleFor(t, 100);
      older.complete();
      await settleFor(t, 100);
      expect(_cardIds(t), hasLength(30));
      expect(_cardIds(t), contains(13), reason: 'ekrandaki liste güncel (tümü) süzgecin listesidir');

      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(rig.service.listContractsCalls.last.state, 'all');
      expect(
        rig.service.listContractsCalls.last.cursor,
        'c30|all|',
        reason: 'eski (Yürürlükte) yanıtın imleci tabloya yazılmamalı',
      );
      expect(_cardIds(t), hasLength(40), reason: 'satır kaybı yok');
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('yarış: sonraki sayfa sürerken süzgeç değişirse eski sayfa yanıtı yeni listeye karışmaz', (t) async {
      final rig = _rig();
      for (var i = 0; i < 35; i++) {
        rig.service.contracts.add(
          ctContract(200 + i, title: 'Ek sözleşme $i', end: '2027-0${1 + i % 9}-1${i % 10}'),
        );
      }
      await rig.pump(t);
      final more = Completer<void>();
      rig.service.gates['listContracts'] = <Completer<void>>[more];
      await tapFinder(t, find.text('Daha fazla yükle'));
      await _tapKey(t, 'contract_summary_yaklasiyor');
      await settleFor(t, 100);
      expect(_cardIds(t), <int>[12]);
      more.complete();
      await settleFor(t, 100);
      expect(_cardIds(t), <int>[12], reason: 'eski "tümü" sayfası eklenmez');
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('ayrıntı: onaylı Feshet -> PATCH {status: feshedildi}; kart ve özet güncellenir; Yeniden etkinleştir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final summaries = rig.service.summaryCalls.length;
      await _tapKey(t, 'contract_card_11');
      await settleFor(t, 100);
      await _tapKey(t, 'contract_detail_terminate');
      await settleFor(t, 100);
      expect(find.text('Sözleşme feshedilsin mi?'), findsOneWidget);
      await _tapKey(t, 'contract_status_keep');
      await settleFor(t, 100);
      expect(rig.service.updateContractCalls, isEmpty, reason: 'Vazgeç: istek yok');

      await _tapKey(t, 'contract_detail_terminate');
      await settleFor(t, 100);
      await _tapKey(t, 'contract_status_ok');
      await settleFor(t, 100);
      expect(rig.service.updateContractCalls.single.body, <String, dynamic>{'status': 'feshedildi'});
      expect(ctKey('contract_detail_reactivate'), findsOneWidget);
      expect(ctKey('contract_detail_terminate'), findsNothing);

      await _tapKey(t, 'contract_detail_close');
      await settleFor(t, 100);
      final card = t.widget<ContractCard>(ctKey('contract_card_11'));
      expect(card.contract.state, ContractState.feshedildi);
      expect(rig.service.summaryCalls.length, greaterThan(summaries));

      await _tapKey(t, 'contract_card_15');
      await settleFor(t, 100);
      await _tapKey(t, 'contract_detail_reactivate');
      await settleFor(t, 100);
      expect(find.text('Sözleşme yeniden etkinleştirilsin mi?'), findsOneWidget);
      await _tapKey(t, 'contract_status_ok');
      await settleFor(t, 100);
      expect(rig.service.updateContractCalls.last.body, <String, dynamic>{'status': 'aktif'});
      expect(ctKey('contract_detail_terminate'), findsOneWidget);
    });

    testWidgets('kurul: ayrıntıda yazma düğmesi yok', (t) async {
      final rig = _rig(kind: ContractSiteAccess.board);
      await rig.pump(t);
      await _tapKey(t, 'contract_card_12');
      await settleFor(t, 100);
      expect(find.text('48.000,50 ₺'), findsOneWidget);
      expect(find.text('Yıllık'), findsOneWidget);
      expect(ctKey('contract_detail_edit'), findsNothing);
      expect(ctKey('contract_detail_terminate'), findsNothing);
      expect(ctKey('contract_detail_close'), findsOneWidget);
    });

    testWidgets('görevli: salt okunur görevli notu; yazma düğmesi yok', (t) async {
      final rig = _rig(kind: ContractSiteAccess.staff);
      await rig.pump(t);
      expect(
        find.text('Görevli olarak firmaları ve sözleşmeleri yalnızca görüntüleyebilirsiniz.'),
        findsOneWidget,
      );
      expect(ctKey('contract_new'), findsNothing);
      await _tapKey(t, 'contract_card_11');
      await settleFor(t, 100);
      expect(ctKey('contract_detail_terminate'), findsNothing);
    });

    testWidgets('düzenleme: yalnız değişen alan gönderilir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'contract_card_12');
      await settleFor(t, 100);
      await _tapKey(t, 'contract_detail_edit');
      await settleFor(t, 100);
      expect(find.text('Sözleşmeyi Düzenle'), findsOneWidget);
      await _type(t, 'contract_form_title', 'Güvenlik hizmeti (yenilendi)');
      await _tapKey(t, 'contract_form_send');
      await settleFor(t, 100);
      expect(rig.service.updateContractCalls.single.body, <String, dynamic>{
        'title': 'Güvenlik hizmeti (yenilendi)',
      });
      expect(find.text('Güvenlik hizmeti (yenilendi)'), findsWidgets);
    });
  });

  group('sözleşme formu', () {
    Future<_Rig> openForm(WidgetTester t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'contract_new');
      await settleFor(t, 100);
      return rig;
    }

    testWidgets('doğrulama: bitiş < başlangıç, gün aralıkları, negatif / 3 ondalık tutar', (t) async {
      final rig = await openForm(t);
      await _type(t, 'contract_form_title', 'Bahçe bakımı');
      await _type(t, 'contract_form_start', '01.11.2026');
      await _type(t, 'contract_form_end', '31.10.2026');
      await _type(t, 'contract_form_notice', '400');
      await _type(t, 'contract_form_remind', '181');
      await _type(t, 'contract_form_amount', '-5');
      await _tapKey(t, 'contract_form_send');
      await settleFor(t, 100);
      expect(find.text('Bitiş tarihi başlangıç tarihinden önce olamaz.'), findsOneWidget);
      expect(find.text('En çok 365 gün olabilir.'), findsOneWidget);
      expect(find.text('En çok 180 gün olabilir.'), findsOneWidget);
      expect(find.text('Tutar negatif olamaz.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);

      await _type(t, 'contract_form_amount', '12,345');
      await settleFor(t, 100);
      expect(find.text('Kuruş en çok 2 basamak olabilir (örn. 1.250,50).'), findsOneWidget);
      await _type(t, 'contract_form_notice', 'otuz');
      await settleFor(t, 100);
      expect(find.text('Gün sayısını yalnız rakamla girin (0-365).'), findsOneWidget);
      expect(rig.service.createContractCalls, isEmpty);
    });

    testWidgets('firma seçici yalnız AKTİF firmaları listeler; seçilen firmanın kategorisi gelir; kayıt gövdesi', (t) async {
      final rig = await openForm(t);
      await _tapKey(t, 'contract_form_vendor');
      await settleFor(t, 100);
      expect(rig.service.listVendorsCalls.last.active, ContractVendorFilter.active);
      expect(find.text('Firma Seç'), findsOneWidget);
      expect(_inTopDialog('Parlak Temizlik'), findsNothing, reason: 'pasif firma seçilemez');
      expect(_inTopDialog('Yıldız Asansör Bakım Ltd. Şti.'), findsOneWidget);
      await tapFinder(t, _inTopDialog('Kale Güvenlik Hizmetleri A.Ş.'));
      await settleFor(t, 100);
      expect(find.text('Güvenlik'), findsWidgets, reason: 'kategori firmadan geldi');

      await _type(t, 'contract_form_title', 'Gece güvenlik hizmeti');
      await _type(t, 'contract_form_start', '01.11.2026');
      await _type(t, 'contract_form_end', '31.10.2027');
      await _type(t, 'contract_form_amount', '1.250,50');
      await tapFinder(t, ctKey('contract_form_auto_renew'));
      await _tapKey(t, 'contract_form_send');
      await settleFor(t, 100);
      final body = rig.service.createContractCalls.single.draft.toCreateJson();
      expect(body, <String, dynamic>{
        'vendor_id': 2,
        'title': 'Gece güvenlik hizmeti',
        'category': 'guvenlik',
        'start_date': '2026-11-01',
        'end_date': '2027-10-31',
        'notice_days': 30,
        'remind_before_days': 30,
        'amount': '1250.50',
        'auto_renew': true,
      });
      expect(find.text('Sözleşme eklendi.'), findsOneWidget);
      expect(_cardIds(t), contains(101));
    });

    testWidgets('"Yeni firma" kısayolu firmayı açar ve seçer', (t) async {
      final rig = await openForm(t);
      await _tapKey(t, 'contract_form_new_vendor');
      await settleFor(t, 100);
      expect(find.text('Yeni Firma'), findsWidgets);
      await _type(t, 'contract_vendor_form_name', 'Mavi Havuz Bakım');
      await _tapKey(t, 'contract_vendor_form_send');
      await settleFor(t, 100);
      expect(rig.service.createVendorCalls.single.draft.toCreateJson(), <String, dynamic>{
        'name': 'Mavi Havuz Bakım',
        'category': 'diger',
      });
      expect(find.text('Mavi Havuz Bakım'), findsOneWidget, reason: 'formda seçili firma');
      expect(find.text('Firma seçin.'), findsNothing);
    });

    testWidgets('pasif firma hatası (409 VENDOR_INACTIVE) pencerede kalır, metinler korunur', (t) async {
      final rig = await openForm(t);
      rig.service.failures['createContract'] = <Object>[
        ApiException(
          ContractApi.contractErrorMessage('VENDOR_INACTIVE')!,
          statusCode: 409,
          code: 'VENDOR_INACTIVE',
        ),
      ];
      await _tapKey(t, 'contract_form_vendor');
      await settleFor(t, 100);
      await tapFinder(t, _inTopDialog('Kale Güvenlik Hizmetleri A.Ş.'));
      await settleFor(t, 100);
      await _type(t, 'contract_form_title', 'Kamera izleme');
      await _type(t, 'contract_form_start', '01.11.2026');
      await _tapKey(t, 'contract_form_send');
      await settleFor(t, 100);
      expect(
        find.text('Seçilen firma pasif. Başka bir firma seçin ya da firmayı Firmalar sekmesinden etkinleştirin.'),
        findsOneWidget,
      );
      expect(find.text('Başka bir firma seçin.'), findsOneWidget);
      expect(find.text('Kamera izleme'), findsOneWidget);
      expect(ctKey('contract_form_send'), findsOneWidget);
    });
  });

  group('Firmalar sekmesi', () {
    testWidgets('telefon tel:, e-posta mailto: ile açılır', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openVendorsTab(t);
      await _tapKey(t, 'contract_vendor_call_1');
      await _tapKey(t, 'contract_vendor_call_2');
      await _tapKey(t, 'contract_vendor_mail_1');
      expect(rig.launched, <Uri>[
        Uri(scheme: 'tel', path: '02125551234'),
        Uri(scheme: 'tel', path: '+905321112233'),
        Uri(scheme: 'mailto', path: 'destek.cok.uzun.adres@yildizasansor-bakim.com.tr'),
      ]);
    });

    testWidgets('durum süzgeci ve arama sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openVendorsTab(t);
      await _tapKey(t, 'contract_vendor_filter_passive');
      await settleFor(t, 100);
      expect(rig.service.listVendorsCalls.last.active, ContractVendorFilter.passive);
      expect(_vendorIds(t), <int>[3]);
      await _tapKey(t, 'contract_vendor_filter_all');
      await settleFor(t, 100);
      await _type(t, 'contract_vendor_search', 'ayşe');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t, 100);
      expect(rig.service.listVendorsCalls.last.query, 'ayşe');
      expect(_vendorIds(t), <int>[2]);
    });

    testWidgets('pasife al onaylıdır; etkinleştir doğrudan', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openVendorsTab(t);
      await _tapKey(t, 'contract_vendor_toggle_1');
      await settleFor(t, 100);
      expect(find.text('Firma pasife alınsın mı?'), findsOneWidget);
      await _tapKey(t, 'contract_vendor_confirm_ok');
      await settleFor(t, 100);
      expect(rig.service.updateVendorCalls.single.body, <String, dynamic>{'is_active': false});
      expect(t.widget<ContractVendorCard>(ctKey('contract_vendor_card_1')).vendor.isActive, isFalse);
      expect(find.text('Firma pasife alındı.'), findsOneWidget);

      await _tapKey(t, 'contract_vendor_toggle_3');
      await settleFor(t, 100);
      expect(find.text('Firma pasife alınsın mı?'), findsNothing);
      expect(rig.service.updateVendorCalls.last.body, <String, dynamic>{'is_active': true});
    });

    testWidgets('firma formu: doğrulama ve aynı ad (409) pencerede gösterilir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openVendorsTab(t);
      await _tapKey(t, 'contract_vendor_new');
      await settleFor(t, 100);
      await _type(t, 'contract_vendor_form_email', 'gecersiz@');
      await _type(t, 'contract_vendor_form_phone', 'abc');
      await _tapKey(t, 'contract_vendor_form_send');
      await settleFor(t, 100);
      expect(find.text('Firma adını girin.'), findsOneWidget);
      expect(find.text('Geçerli bir e-posta adresi girin (örn. destek@firma.com).'), findsOneWidget);
      expect(
        find.text('Telefonu rakamla girin; yalnız boşluk ve + ( ) - . / kullanılabilir (örn. 0212 555 12 34).'),
        findsOneWidget,
      );
      expect(rig.service.createVendorCalls, isEmpty);

      await _type(t, 'contract_vendor_form_email', '');
      await _type(t, 'contract_vendor_form_phone', '444 1 444');
      await _type(t, 'contract_vendor_form_name', 'parlak temizlik');
      await _tapKey(t, 'contract_vendor_form_send');
      await settleFor(t, 100);
      expect(rig.service.createVendorCalls, hasLength(1));
      expect(
        find.text('Bu adla kayıtlı bir firma zaten var. Farklı bir ad girin ya da mevcut firmayı kullanın.'),
        findsOneWidget,
      );
      expect(ctKey('contract_vendor_form_send'), findsOneWidget, reason: 'pencere açık kalır');
    });

    testWidgets('düzenleme: değişiklik yoksa istek gitmez; değişen alan gönderilir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openVendorsTab(t);
      await _tapKey(t, 'contract_vendor_edit_2');
      await settleFor(t, 100);
      expect(find.text('Firmayı Düzenle'), findsOneWidget);
      await _tapKey(t, 'contract_vendor_form_send');
      await settleFor(t, 100);
      expect(rig.service.updateVendorCalls, isEmpty);
      expect(find.text('Firmayı Düzenle'), findsNothing);

      await _tapKey(t, 'contract_vendor_edit_2');
      await settleFor(t, 100);
      await _type(t, 'contract_vendor_form_contact', '');
      await _type(t, 'contract_vendor_form_email', 'iletisim@kale.com.tr');
      await _tapKey(t, 'contract_vendor_form_send');
      await settleFor(t, 100);
      expect(rig.service.updateVendorCalls.single.body, <String, dynamic>{
        'contact_name': null,
        'email': 'iletisim@kale.com.tr',
      });
      expect(find.text('Firma güncellendi.'), findsOneWidget);
    });
  });
}
