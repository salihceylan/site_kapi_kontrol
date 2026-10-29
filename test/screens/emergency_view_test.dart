// Acil durum ekranı (P2-24, karar K13): 112 büyük düğmesi, yangın ve asansör arızası hızlı düğmeleri, KURU MOD (arama kanalı yoksa /
// başlatılamıyorsa numaralar + adres kopyalanabilir metin, SAHTE "arandı" YOK), adres DOĞRU siteden, bakım firması ipucu / düzenleme, ağ
// hatasında 112'nin etkilenmemesi ve dar ekranda büyük yazıda taşma yok.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/services/emergency_dialer.dart';
import 'package:site_kapi_kontrol/ui/views/emergency_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

const EmergencySite _gul = EmergencySite(
  siteCode: 11,
  siteName: 'Gül Sitesi',
  address: 'Atatürk Mah. 12. Sok. No: 5',
  city: 'İstanbul',
  district: 'Kadıköy',
  elevatorFirmName: 'Yıldız Asansör',
  elevatorFirmPhone: '0212 555 12 34',
  canEdit: true,
);
const EmergencySite _lale = EmergencySite(
  siteCode: 22,
  siteName: 'Lale Sitesi',
  address: 'Cumhuriyet Mah. 3. Cad. No: 9',
  city: 'Ankara',
  district: 'Çankaya',
);
const String _gulAddress = 'Atatürk Mah. 12. Sok. No: 5, Kadıköy / İstanbul';
const String _laleAddress = 'Cumhuriyet Mah. 3. Cad. No: 9, Çankaya / Ankara';

/// Sahte sunucu servisi: çağrılar kaydedilir; yanıtlar testten sürülür.
class _FakeService extends EmergencyService {
  _FakeService({List<EmergencySite>? sites})
    : sites = sites ?? <EmergencySite>[_gul],
      super(authService: PeopleFakeAuth());

  List<EmergencySite> sites;
  Object? listError;
  Object? saveError;
  int listCalls = 0;

  /// Doluysa yanıt tamamlanana dek bekler (yükleniyor durumunu sınamak için).
  Completer<void>? gate;
  final List<({int site, String? name, String? phone})> saves = <({int site, String? name, String? phone})>[];

  @override
  Future<List<EmergencySite>> listSites() async {
    listCalls++;
    await gate?.future;
    final error = listError;
    if (error != null) throw error;
    return List<EmergencySite>.of(sites);
  }

  @override
  Future<({String? name, String? phone})> saveElevatorFirm(int siteCode, {String? name, String? phone}) async {
    saves.add((site: siteCode, name: name, phone: phone));
    final error = saveError;
    if (error != null) throw error;
    return (name: name, phone: phone);
  }
}

/// Sahte arama kanalı.
class _FakeChannel implements EmergencyCallChannel {
  _FakeChannel({this.may = true, this.probeResult = true, this.outcome = EmergencyDialOutcome.opened});

  bool may;
  bool probeResult;
  EmergencyDialOutcome outcome;
  int probes = 0;
  final List<String> dialed = <String>[];

  @override
  bool get mayBeAvailable => may;

  @override
  Future<bool> probe() async {
    probes++;
    return probeResult;
  }

  @override
  Future<EmergencyDialOutcome> dial(String number) async {
    dialed.add(number);
    return outcome;
  }
}

final RegExp _fakeCallClaim = RegExp('arandı|aranıyor|arama yapıldı|çağrı yapıldı', caseSensitive: false);

/// Ekrandaki tüm metinler (Text + SelectableText).
List<String> _texts(WidgetTester t) => <String>[
  for (final w in t.widgetList<Text>(find.byType(Text)))
    if ((w.data ?? w.textSpan?.toPlainText()) case final String s) s,
  for (final w in t.widgetList<SelectableText>(find.byType(SelectableText)))
    if ((w.data ?? w.textSpan?.toPlainText()) case final String s) s,
];

void _expectNoFakeCallClaim(WidgetTester t) {
  final offenders = _texts(t).where(_fakeCallClaim.hasMatch).toList();
  expect(offenders, isEmpty, reason: 'sahte "arandı" iddiası: $offenders');
}

String _selectable(WidgetTester t, String key) => t.widget<SelectableText>(find.byKey(ValueKey<String>(key))).data!;

List<String> _mockClipboard(WidgetTester t) {
  final clipboard = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return clipboard;
}

Future<void> _pump(
  WidgetTester t, {
  required _FakeService service,
  required _FakeChannel channel,
  int? preferred,
  bool allowEdit = true,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpList(
    t,
    EmergencyView(authService: service.authService, service: service, channel: channel, preferredSiteCode: preferred, allowEdit: allowEdit),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

/// Düğmeye dokunur. Önceki bildirim (SnackBar) alttaki düğmeyi örtebildiğinden önce kaldırılır.
Future<void> _tapKey(WidgetTester t, String key) async {
  final messenger = ScaffoldMessenger.maybeOf(t.element(find.byType(Scaffold).first));
  messenger?.clearSnackBars();
  messenger?.removeCurrentSnackBar();
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await tapFinder(t, find.byKey(ValueKey<String>(key)));
}

void main() {
  group('kuru mod: arama kanalı yok', () {
    testWidgets('112 için arama düğmesi YOK; numara ve "Numarayı kopyala" var; açıklayıcı uyarı; sahte "arandı" yok', (t) async {
      final clipboard = _mockClipboard(t);
      final channel = _FakeChannel(may: false);
      await _pump(t, service: _FakeService(), channel: channel);

      expect(find.byKey(const ValueKey<String>('emergency_dry_banner')), findsOneWidget);
      expect(find.textContaining('Bu cihazdan arama başlatılamıyor'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_call_112')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_copy_112')), findsOneWidget);
      expect(find.text('112'), findsWidgets);
      // Kanal bu platformda hiç olamıyorsa "Tekrar Dene" önerilmez ve platforma sorulmaz.
      expect(find.text('Tekrar Dene'), findsNothing);
      expect(channel.probes, 0);
      expect(channel.dialed, isEmpty);

      await _tapKey(t, 'emergency_copy_112');
      expect(clipboard, <String>['112']);
      expect(find.text('112 numarası panoya kopyalandı.'), findsOneWidget);
      _expectNoFakeCallClaim(t);
    });

    testWidgets('yangın: 112 + adres + sorular metin olarak; arama düğmesi yok; kopyalanan metin numara ve DOĞRU adresi taşır', (t) async {
      final clipboard = _mockClipboard(t);
      await _pump(t, service: _FakeService(), channel: _FakeChannel(may: false));

      await _tapKey(t, 'emergency_quick_fire');
      expect(find.byKey(const ValueKey<String>('emergency_panel_fire')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_call_112_panel')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_copy_112_panel')), findsOneWidget);
      expect(_selectable(t, 'emergency_say_line'), '"Yangın var."');
      expect(_selectable(t, 'emergency_site_name'), 'Gül Sitesi');
      expect(_selectable(t, 'emergency_address'), _gulAddress);
      expect(find.textContaining('Yangın nerede?'), findsOneWidget);
      expect(find.textContaining('asansör kullanmayın'), findsOneWidget);

      await _tapKey(t, 'emergency_copy_script');
      expect(clipboard.single, startsWith('ACİL DURUM - YANGIN'));
      expect(clipboard.single, contains('Aranacak numara: 112'));
      expect(clipboard.single, contains('Site: Gül Sitesi'));
      expect(clipboard.single, contains('Adres: $_gulAddress'));
      expect(find.text('Bilgiler panoya kopyalandı.'), findsOneWidget);

      await _tapKey(t, 'emergency_copy_address');
      expect(clipboard.last, 'Gül Sitesi\n$_gulAddress');
      _expectNoFakeCallClaim(t);
    });

    testWidgets('asansör: bakım firması telefonu metin + kopyala; firma için arama düğmesi yok; 112 de yalnız kopyalanır', (t) async {
      final clipboard = _mockClipboard(t);
      await _pump(t, service: _FakeService(), channel: _FakeChannel(may: false));

      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.byKey(const ValueKey<String>('emergency_call_firm')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_112_panel')), findsNothing);
      expect(find.text('Yıldız Asansör'), findsOneWidget);
      expect(find.text('0212 555 12 34'), findsOneWidget);
      await _tapKey(t, 'emergency_copy_firm');
      expect(clipboard.single, '0212 555 12 34');
      await _tapKey(t, 'emergency_copy_script');
      expect(clipboard.last, contains('Asansör bakım firması: Yıldız Asansör, 0212 555 12 34'));
      expect(clipboard.last, contains('Mahsur kalan kişide tehlike varsa: 112'));
      _expectNoFakeCallClaim(t);
    });
  });

  group('arama kanalı var', () {
    testWidgets('112: arama düğmesi telefon uygulamasını açar; mesaj "açıldı" der, "arandı" DEMEZ; kuru moda geçilmez', (t) async {
      final channel = _FakeChannel();
      await _pump(t, service: _FakeService(), channel: channel);
      expect(channel.probes, 1);
      expect(find.byKey(const ValueKey<String>('emergency_dry_banner')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_copy_112')), findsNothing);

      await _tapKey(t, 'emergency_call_112');
      expect(channel.dialed, <String>['112']);
      expect(find.text('Telefon uygulaması açıldı. Aramayı orada başlatın.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_dry_banner')), findsNothing);
      _expectNoFakeCallClaim(t);
    });

    testWidgets('arama başlatılamazsa kuru moda geçilir: uyarı, numara metni ve kopyala; "arandı" iddiası yok', (t) async {
      for (final outcome in <EmergencyDialOutcome>[EmergencyDialOutcome.failed, EmergencyDialOutcome.unavailable]) {
        final channel = _FakeChannel(outcome: outcome);
        await _pump(t, service: _FakeService(), channel: channel);
        await _tapKey(t, 'emergency_call_112');
        expect(channel.dialed, <String>['112'], reason: outcome.name);
        expect(find.text('Arama başlatılamadı. 112 numarasını başka bir telefondan arayın.'), findsOneWidget, reason: outcome.name);
        expect(find.byKey(const ValueKey<String>('emergency_dry_banner')), findsOneWidget, reason: outcome.name);
        expect(find.byKey(const ValueKey<String>('emergency_call_112')), findsNothing, reason: outcome.name);
        expect(find.byKey(const ValueKey<String>('emergency_copy_112')), findsOneWidget, reason: outcome.name);
        expect(find.text('Telefon uygulaması açıldı. Aramayı orada başlatın.'), findsNothing);
        _expectNoFakeCallClaim(t);
      }
    });

    testWidgets('yoklama başarısızsa (telefonsuz tablet) açılışta kuru mod; "Tekrar Dene" yeniden yoklar ve kanal gelince arama düğmesi döner', (t) async {
      final channel = _FakeChannel(probeResult: false);
      await _pump(t, service: _FakeService(), channel: channel);
      expect(channel.probes, 1);
      expect(find.byKey(const ValueKey<String>('emergency_dry_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_call_112')), findsNothing);

      channel.probeResult = true;
      await tapText(t, 'Tekrar Dene');
      expect(channel.probes, 2);
      expect(find.byKey(const ValueKey<String>('emergency_dry_banner')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_112')), findsOneWidget);
    });

    testWidgets('yangın: panel içindeki 112 düğmesi de aynı kanaldan çağırır', (t) async {
      final channel = _FakeChannel();
      await _pump(t, service: _FakeService(), channel: channel);
      await _tapKey(t, 'emergency_quick_fire');
      await _tapKey(t, 'emergency_call_112_panel');
      expect(channel.dialed, <String>['112']);
    });

    testWidgets('asansör: bakım firmasını arar (firmanın kayıtlı telefonu), 112 ayrı bir karttır; ikisi karışmaz', (t) async {
      final channel = _FakeChannel();
      await _pump(t, service: _FakeService(), channel: channel);
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.text('Asansör bakım firması'), findsOneWidget);
      expect(find.text('Yıldız Asansör'), findsOneWidget);
      await _tapKey(t, 'emergency_call_firm');
      expect(channel.dialed, <String>['0212 555 12 34']);
      await _tapKey(t, 'emergency_call_112_panel');
      expect(channel.dialed, <String>['0212 555 12 34', '112']);
      expect(find.textContaining('Hangi blok ve hangi asansör?'), findsOneWidget);
      expect(find.textContaining('kapıyı zorlamayın'), findsOneWidget);
    });

    testWidgets('hızlı düğmeler: aynı düğmeye yeniden dokunmak genel ekrana döner; farklı düğme paneli değiştirir', (t) async {
      await _pump(t, service: _FakeService(), channel: _FakeChannel());
      expect(find.byKey(const ValueKey<String>('emergency_panel_general')), findsOneWidget);
      await _tapKey(t, 'emergency_quick_fire');
      expect(find.byKey(const ValueKey<String>('emergency_panel_fire')), findsOneWidget);
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.byKey(const ValueKey<String>('emergency_panel_elevator')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_panel_fire')), findsNothing);
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.byKey(const ValueKey<String>('emergency_panel_general')), findsOneWidget);
    });
  });

  group('adres DOĞRU siteden', () {
    testWidgets('tek site: seçici yok, kendi adresi', (t) async {
      await _pump(t, service: _FakeService(sites: <EmergencySite>[_lale]), channel: _FakeChannel());
      expect(find.text('Hangi site için?'), findsNothing);
      expect(_selectable(t, 'emergency_site_name'), 'Lale Sitesi');
      expect(_selectable(t, 'emergency_address'), _laleAddress);
      expect(find.textContaining('Atatürk Mah.'), findsNothing);
    });

    testWidgets('iki site: ilk site açılır; seçici ile diğerine geçince adres ve kopyalanan metin ONUNKİ olur, öncekinin hiçbir izi kalmaz', (t) async {
      final clipboard = _mockClipboard(t);
      await _pump(t, service: _FakeService(sites: <EmergencySite>[_gul, _lale]), channel: _FakeChannel());
      expect(find.text('Hangi site için?'), findsOneWidget);
      expect(_selectable(t, 'emergency_address'), _gulAddress);

      await tapText(t, 'Gül Sitesi');
      await tapFinder(t, find.text('Lale Sitesi').last);
      expect(_selectable(t, 'emergency_site_name'), 'Lale Sitesi');
      expect(_selectable(t, 'emergency_address'), _laleAddress);
      expect(find.text(_gulAddress), findsNothing);

      await _tapKey(t, 'emergency_quick_fire');
      await _tapKey(t, 'emergency_copy_script');
      expect(clipboard.single, contains('Site: Lale Sitesi'));
      expect(clipboard.single, contains(_laleAddress));
      expect(clipboard.single, isNot(contains('Gül Sitesi')));
      expect(clipboard.single, isNot(contains('Atatürk')));
    });

    testWidgets('çekmecedeki site seçimi (preferredSiteCode) başlangıç sitesini belirler; sonradan değişince ekran uyar', (t) async {
      final service = _FakeService(sites: <EmergencySite>[_gul, _lale]);
      final channel = _FakeChannel();
      await _pump(t, service: service, channel: channel, preferred: 22);
      expect(_selectable(t, 'emergency_address'), _laleAddress);

      await pumpList(
        t,
        EmergencyView(authService: service.authService, service: service, channel: channel, preferredSiteCode: 11, allowEdit: true),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(_selectable(t, 'emergency_address'), _gulAddress);
    });

    testWidgets('asansör firması da siteye özeldir: ikinci sitede firma yok -> ipucu, birinci sitedeki firma görünmez', (t) async {
      await _pump(t, service: _FakeService(sites: <EmergencySite>[_gul, _lale]), channel: _FakeChannel(), preferred: 22);
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.text('Yıldız Asansör'), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_firm')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_firm_hint')), findsOneWidget);
    });

    testWidgets('adres kayıtlı değil: dürüst ipucu (yöneticiye ekleme yolu, diğerlerine "kendiniz söyleyin"); adres kopyala düğmesi yok', (t) async {
      const empty = EmergencySite(siteCode: 33, siteName: 'Boş Site', canEdit: true);
      await _pump(t, service: _FakeService(sites: <EmergencySite>[empty]), channel: _FakeChannel());
      expect(find.byKey(const ValueKey<String>('emergency_address')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_copy_address')), findsNothing);
      expect(find.textContaining('“Site Yönetimi” ekranından adresi ekleyin'), findsOneWidget);
      expect(_selectable(t, 'emergency_site_name'), 'Boş Site');

      await _pump(t, service: _FakeService(sites: <EmergencySite>[empty]), channel: _FakeChannel(), allowEdit: false);
      expect(find.textContaining('Adresi kendiniz söyleyin ve site yönetiminden adresin eklenmesini isteyin'), findsOneWidget);
      expect(find.textContaining('Site Yönetimi'), findsNothing);
    });

    testWidgets('hiç sitesi olmayan kullanıcı (bireysel): 112 ve içerik çalışır, adres uydurulmaz', (t) async {
      final clipboard = _mockClipboard(t);
      final channel = _FakeChannel();
      await _pump(t, service: _FakeService(sites: <EmergencySite>[]), channel: channel);
      expect(find.textContaining('Bağlı olduğunuz bir site yok'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_site_name')), findsNothing);
      await _tapKey(t, 'emergency_call_112');
      expect(channel.dialed, <String>['112']);
      await _tapKey(t, 'emergency_quick_fire');
      await _tapKey(t, 'emergency_copy_script');
      expect(clipboard.single, contains('Adres: kayıtlı değil, adresi kendiniz söyleyin'));
    });
  });

  group('asansör bakım firması (site ayarı)', () {
    const noFirm = EmergencySite(siteCode: 11, siteName: 'Gül Sitesi', address: 'Atatürk Mah.', canEdit: true);

    testWidgets('firma yok + yönetici: yöneticiye ipucu ve "Bakım firmasını ekle"; 112 yine verilir', (t) async {
      await _pump(t, service: _FakeService(sites: <EmergencySite>[noFirm]), channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.textContaining('Asansör bakım firmasının telefonu kayıtlı değil. Ekleyin'), findsOneWidget);
      expect(find.text('Bakım firmasını ekle'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_call_firm')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_112_panel')), findsOneWidget);
      _expectNoFakeCallClaim(t);
    });

    testWidgets('firma yok + sakin / kurul / sakin modundaki yönetici: "yönetimden isteyin", düzenleme düğmesi YOK', (t) async {
      for (final (site, allowEdit) in <(EmergencySite, bool)>[
        (noFirm.withElevatorFirm(), false), // yönetici ama sakin modunda
        (const EmergencySite(siteCode: 11, siteName: 'Gül Sitesi'), true), // can_edit false (sakin, kurul, görevli)
      ]) {
        await _pump(t, service: _FakeService(sites: <EmergencySite>[site]), channel: _FakeChannel(), allowEdit: allowEdit);
        await _tapKey(t, 'emergency_quick_elevator');
        expect(find.textContaining('henüz eklenmemiş. Site yönetiminden isteyin'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('emergency_edit_firm')), findsNothing);
        expect(find.byKey(const ValueKey<String>('emergency_call_112_panel')), findsOneWidget);
      }
    });

    testWidgets('site bilgisi alınamadıysa "kayıtlı değil" DENMEZ (bilinmiyor); sitesiz kullanıcıya yönetimden öğrenmesi söylenir', (t) async {
      final failing = _FakeService()..listError = ApiException('Sunucuya bağlanılamadı.');
      await _pump(t, service: failing, channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.textContaining('Asansör bakım firması bilgisi alınamadı'), findsOneWidget);
      expect(find.textContaining('henüz eklenmemiş'), findsNothing);
      expect(find.textContaining('kayıtlı değil. Ekleyin'), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_112_panel')), findsOneWidget);

      await _pump(t, service: _FakeService(sites: <EmergencySite>[]), channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.textContaining('Asansör bakım firmasını sitenizin yönetiminden öğrenin'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_edit_firm')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_112_panel')), findsOneWidget);
    });

    testWidgets('firma var: yalnız yönetici modundaki yönetici "düzenle" görür', (t) async {
      await _pump(t, service: _FakeService(), channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.byKey(const ValueKey<String>('emergency_edit_firm')), findsOneWidget);

      await _pump(t, service: _FakeService(), channel: _FakeChannel(), allowEdit: false);
      await _tapKey(t, 'emergency_quick_elevator');
      expect(find.byKey(const ValueKey<String>('emergency_edit_firm')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_firm')), findsOneWidget);
    });

    testWidgets('yönetici firmayı ekler: sunucuya iki alan gider, kart anında görünür, bildirim "kaydedildi" der', (t) async {
      final service = _FakeService(sites: <EmergencySite>[noFirm]);
      await _pump(t, service: service, channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      await _tapKey(t, 'emergency_edit_firm');
      expect(find.byType(AlertDialog), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey<String>('emergency_firm_name')), 'Yıldız Asansör');
      await t.enterText(find.byKey(const ValueKey<String>('emergency_firm_phone')), '444 1 234');
      await tapFinder(t, find.byKey(const ValueKey<String>('emergency_firm_save')));
      expect(service.saves.single, (site: 11, name: 'Yıldız Asansör', phone: '444 1 234'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Asansör bakım firması kaydedildi.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_call_firm')), findsOneWidget);
      expect(find.text('Yıldız Asansör'), findsOneWidget);
      expect(find.text('444 1 234'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_firm_hint')), findsNothing);
    });

    testWidgets('ad yazılıp telefon boş bırakılırsa pencere açık kalır ve hata gösterir; hiçbir şey kaydedilmez', (t) async {
      final service = _FakeService(sites: <EmergencySite>[noFirm]);
      await _pump(t, service: service, channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      await _tapKey(t, 'emergency_edit_firm');
      await t.enterText(find.byKey(const ValueKey<String>('emergency_firm_name')), 'Yıldız Asansör');
      await tapFinder(t, find.byKey(const ValueKey<String>('emergency_firm_save')));
      expect(find.text('Firma adını yazdıysanız telefonunu da yazın.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(service.saves, isEmpty);
    });

    testWidgets('firmayı kaldır: iki alan null gider, ipucu geri gelir', (t) async {
      final service = _FakeService();
      await _pump(t, service: service, channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      await _tapKey(t, 'emergency_edit_firm');
      await tapFinder(t, find.byKey(const ValueKey<String>('emergency_firm_remove')));
      expect(service.saves.single, (site: 11, name: null, phone: null));
      expect(find.text('Asansör bakım firması kaldırıldı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_call_firm')), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_firm_hint')), findsOneWidget);
    });

    testWidgets('kayıt hatası: sunucu mesajı gösterilir, firma değişmez', (t) async {
      final service = _FakeService()..saveError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _pump(t, service: service, channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      await _tapKey(t, 'emergency_edit_firm');
      await t.enterText(find.byKey(const ValueKey<String>('emergency_firm_name')), 'Başka Firma');
      await tapFinder(t, find.byKey(const ValueKey<String>('emergency_firm_save')));
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Yıldız Asansör'), findsOneWidget);
      expect(find.text('Başka Firma'), findsNothing);
    });

    testWidgets('vazgeçmek hiçbir şey göndermez', (t) async {
      final service = _FakeService();
      await _pump(t, service: service, channel: _FakeChannel());
      await _tapKey(t, 'emergency_quick_elevator');
      await _tapKey(t, 'emergency_edit_firm');
      await tapText(t, 'Vazgeç');
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.saves, isEmpty);
    });
  });

  group('ağ hatası', () {
    testWidgets('site bilgisi alınamazsa 112 ETKİLENMEZ; hata + "Tekrar Dene"; düzelince adres gelir', (t) async {
      final service = _FakeService()..listError = ApiException('Sunucuya bağlanılamadı.');
      final channel = _FakeChannel();
      await _pump(t, service: service, channel: channel);
      expect(find.byKey(const ValueKey<String>('emergency_load_error')), findsOneWidget);
      expect(find.textContaining('112 aramanız bundan etkilenmez'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_address')), findsNothing);
      expect(find.textContaining('Site adresi alınamadı. Adresi kendiniz söyleyin.'), findsOneWidget);
      await _tapKey(t, 'emergency_call_112');
      expect(channel.dialed, <String>['112']);

      service.listError = null;
      await tapText(t, 'Tekrar Dene');
      expect(find.byKey(const ValueKey<String>('emergency_load_error')), findsNothing);
      expect(_selectable(t, 'emergency_address'), _gulAddress);
    });

    testWidgets('yenileme başarısızsa son bilinen bilgi korunur ve bunu söyler', (t) async {
      final service = _FakeService();
      final key = GlobalKey<EmergencyViewState>();
      await pumpList(
        t,
        EmergencyView(key: key, authService: service.authService, service: service, channel: _FakeChannel()),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(_selectable(t, 'emergency_address'), _gulAddress);

      service.listError = ApiException('Sunucuya bağlanılamadı.');
      await key.currentState!.reload();
      await settleFor(t);
      expect(_selectable(t, 'emergency_address'), _gulAddress);
      expect(find.textContaining('son alınan bilgiler gösteriliyor'), findsOneWidget);
    });

    testWidgets('ilk yüklemede "yükleniyor" der, "adres yok" demez', (t) async {
      final service = _FakeService()..gate = Completer<void>();
      await pumpList(
        t,
        EmergencyView(authService: service.authService, service: service, channel: _FakeChannel()),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      // Sunucu yanıtı henüz gelmedi: adres "yükleniyor" der, "kayıtlı değil" DEMEZ; 112 yine kullanılabilir.
      expect(find.text('Site adresi yükleniyor...'), findsOneWidget);
      expect(find.textContaining('kayıtlı değil'), findsNothing);
      expect(find.byKey(const ValueKey<String>('emergency_call_112')), findsOneWidget);

      service.gate!.complete();
      await settleFor(t);
      expect(find.text('Site adresi yükleniyor...'), findsNothing);
      expect(_selectable(t, 'emergency_address'), _gulAddress);
    });
  });

  group('taşma yok (AGENTS.md kural 6)', () {
    for (final dry in <bool>[false, true]) {
      listMatrix('acil durum ${dry ? 'kuru mod' : 'arama kanalı var'}', (t, width, height, scale, dark) async {
        final service = _FakeService(sites: <EmergencySite>[_gul, _lale]);
        await pumpList(
          t,
          EmergencyView(authService: service.authService, service: service, channel: _FakeChannel(may: !dry), allowEdit: true),
          width: width,
          height: height,
          scale: scale,
          dark: dark,
        );
        await settleFor(t);
        for (final key in <String>['emergency_quick_fire', 'emergency_quick_elevator']) {
          await _tapKey(t, key);
          await settleFor(t);
        }
        await _tapKey(t, 'emergency_edit_firm');
        await settleFor(t);
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    }

    listMatrix('acil durum: firma yok, hata ve adres yok durumları', (t, width, height, scale, dark) async {
      final service = _FakeService(sites: <EmergencySite>[const EmergencySite(siteCode: 1, siteName: 'Çok Uzun Adlı Büyük Toplu Konut Sitesi Yönetimi', canEdit: true)])
        ..listError = ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      await pumpList(
        t,
        EmergencyView(authService: service.authService, service: service, channel: _FakeChannel(probeResult: false), allowEdit: true),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      await _tapKey(t, 'emergency_quick_elevator');
      await settleFor(t);
      service.listError = null;
      await tapText(t, 'Tekrar Dene');
    });
  });
}
