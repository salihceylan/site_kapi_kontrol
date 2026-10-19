// İş Takibi fotoğraf ekleri — ikinci bağımsız inceleme (R2-3, R2-4) ve kota sözleşmesi:
// - seçilen fotoğraflar yüklemeden önce hazırlanırken "Fotoğraf hazırlanıyor..." (ayrıntı penceresi ve talep formu),
//   bu sırada ekleme / gönderme kapalı; ipucu "küçültülür; konum bilgisi silinir" der;
// - 409 LIMIT_REACHED yarış kilidi kalıcı değil: 30 sn sonra tek seferlik sessiz yenileme "Fotoğraf Ekle"yi açar
//   (sakin ve yönetim), yenileme başarısızsa bir kez daha denenir, pencere kapanınca zamanlayıcı iptal edilir;
// - (R3-2) talep formu seçim / hazırlık sürerken kapanmaz ("Vazgeç" kapalı, geri hareketi yok sayılır); seçim
//   sürerken pencere yok olursa seçici kopyaları yine silinir (release), seçim sonradan biterse bir kez daha.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];

const String _hint = 'Fotoğraflar yüklenmeden önce küçültülür; konum bilgisi silinir.';

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

WorkPhotoSelection _one(String name) => WorkPhotoSelection(picks: <WorkPhotoPick>[wkPhoto(name, png: true)]);

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

class _ResidentRig {
  _ResidentRig(this.service, this.picker);

  final FakeWorkService service;
  final FakeWorkPhotoPicker picker;

  Future<void> pump(WidgetTester t) async {
    await pumpList(
      t,
      WorkResidentView(authService: WorkFakeAuth(), service: service, sites: _oneSite, photoPicker: picker),
      width: 400,
      height: 1800,
      scale: 1.0,
      dark: false,
    );
    await _settle(t);
  }

  Future<void> openCard(WidgetTester t, int id) async {
    await tapFinder(t, find.byWidgetPredicate((w) => w is WorkResidentCard && w.item.id == id));
    await _settle(t);
  }
}

_ResidentRig _resident(List<WorkPhotoSelection> picks) =>
    _ResidentRig(residentWork(WorkFakeAuth()), FakeWorkPhotoPicker(picks));

class _ManagerRig {
  _ManagerRig(this.service, this.picker);

  final FakeWorkService service;
  final FakeWorkPhotoPicker picker;

  Future<void> pump(WidgetTester t) async {
    await pumpList(
      t,
      WorkManagerView(
        authService: WorkFakeAuth(),
        service: service,
        sites: <WorkTrackingSite>[WorkTrackingSite(code: 11, name: 'Gül Sitesi', access: service.kind)],
        photoPicker: picker,
      ),
      width: 400,
      height: 3000,
      scale: 1.0,
      dark: false,
    );
    await _settle(t);
  }

  Future<void> openCard(WidgetTester t, int id) async {
    await tapFinder(t, find.byWidgetPredicate((w) => w is WorkManagedCard && w.item.id == id));
    await _settle(t);
  }
}

_ManagerRig _manager(List<WorkPhotoSelection> picks) =>
    _ManagerRig(managerWork(WorkFakeAuth()), FakeWorkPhotoPicker(picks));

bool _addEnabled(WidgetTester t) =>
    t.widget<PrimaryActionButton>(wkKey('work_attachment_add')).onPressed != null;

ApiException _limitReached() =>
    ApiException(WorkAttachmentRules.limitMessage, statusCode: 409, code: 'LIMIT_REACHED');

/// Fotoğraf Ekle -> sunucu 409 LIMIT_REACHED (ekranda 2/4): yarış kilidi kurulur.
Future<void> _hitLimitRace(WidgetTester t, FakeWorkService service) async {
  service.failures['createAttachment'] = <Object>[_limitReached()];
  await _tapKey(t, 'work_attachment_add');
  await _settle(t);
  expect(find.textContaining(WorkAttachmentRules.limitBusyMessage), findsOneWidget);
  expect(find.text('2/4'), findsOneWidget);
  expect(_addEnabled(t), isFalse, reason: 'yarış kilidi');
}

void main() {
  group('hazırlama durumu (R2-3)', () {
    testWidgets('sakin ayrıntısı: ipucu; hazırlanırken "Fotoğraf hazırlanıyor..." ve Fotoğraf Ekle kapalı; sonra yüklenir',
        (t) async {
      final rig = _resident(<WorkPhotoSelection>[_one('buyuk.jpg')]);
      final gate = Completer<void>();
      rig.picker.prepareGate = gate;
      final handle = t.ensureSemantics();
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(find.textContaining(_hint), findsOneWidget);
      expect(wkKey('work_attachment_preparing'), findsNothing);

      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      expect(wkKey('work_attachment_preparing'), findsOneWidget);
      expect(find.text('Fotoğraf hazırlanıyor...'), findsOneWidget);
      expect(find.semantics.byLabel('Fotoğraf hazırlanıyor...'), findsOne);
      expect(_addEnabled(t), isFalse);
      expect(t.widget<TextButton>(wkKey('work_resident_detail_close')).onPressed, isNull, reason: 'seçim sürüyor');
      expect(rig.service.createAttachmentCalls, isEmpty);

      gate.complete();
      await _settle(t);
      expect(wkKey('work_attachment_preparing'), findsNothing);
      expect(rig.service.createAttachmentCalls.single.name, 'buyuk.jpg');
      expect(find.text('3/4'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('yönetim ayrıntısı: hazırlanırken gösterge, ardından yükleme', (t) async {
      final rig = _manager(<WorkPhotoSelection>[_one('servis.jpg')]);
      final gate = Completer<void>();
      rig.picker.prepareGate = gate;
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(find.textContaining(_hint), findsOneWidget);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      expect(wkKey('work_attachment_preparing'), findsOneWidget);
      expect(_addEnabled(t), isFalse);
      gate.complete();
      await _settle(t);
      expect(wkKey('work_attachment_preparing'), findsNothing);
      expect(rig.service.createAttachmentCalls.single.name, 'servis.jpg');
    });

    testWidgets('talep formu: ipucu; hazırlanırken gösterge, Fotoğraf Ekle ve Gönder kapalı; sonra liste', (t) async {
      final rig = _resident(<WorkPhotoSelection>[_one('kapi.jpg')]);
      final gate = Completer<void>();
      rig.picker.prepareGate = gate;
      await rig.pump(t);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      expect(find.textContaining(_hint), findsOneWidget);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      expect(wkKey('work_form_photo_preparing'), findsOneWidget);
      expect(find.text('Fotoğraf hazırlanıyor...'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(wkKey('work_form_photo_add')).onPressed, isNull);
      expect(t.widget<ElevatedButton>(wkKey('work_form_send')).onPressed, isNull);

      gate.complete();
      await settleFor(t, 100);
      expect(wkKey('work_form_photo_preparing'), findsNothing);
      expect(wkKey('work_form_photo_remove_0'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      expect(t.widget<ElevatedButton>(wkKey('work_form_send')).onPressed, isNotNull);
    });

    testWidgets('vazgeçilen seçimde (hazırlama başlamadı) gösterge çıkmaz', (t) async {
      final rig = _resident(const <WorkPhotoSelection>[]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      expect(wkKey('work_attachment_preparing'), findsNothing);
      expect(_addEnabled(t), isTrue);
    });
  });

  group('LIMIT_REACHED kilidi 30 sn sonra yenilenir (R2-4)', () {
    testWidgets('sakin: 30 sn dolmadan kapalı; sonra tek sessiz yenileme açar ve iletiyi kaldırır', (t) async {
      final rig = _resident(<WorkPhotoSelection>[_one('a.jpg')]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _hitLimitRace(t, rig.service);
      final loads = rig.service.getMineCalls.length;

      await t.pump(const Duration(seconds: 29));
      await settleFor(t, 100);
      expect(rig.service.getMineCalls.length, loads, reason: '30 sn dolmadı');
      expect(_addEnabled(t), isFalse);

      await t.pump(const Duration(seconds: 1));
      await _settle(t);
      expect(rig.service.getMineCalls.length, loads + 1, reason: 'tek sessiz yenileme');
      expect(_addEnabled(t), isTrue);
      expect(find.textContaining(WorkAttachmentRules.limitBusyMessage), findsNothing);

      // Tek seferlik: kilit açıldıktan sonra yeni yenileme yok.
      await t.pump(const Duration(seconds: 60));
      await _settle(t);
      expect(rig.service.getMineCalls.length, loads + 1);
    });

    testWidgets('sakin: sessiz yenileme başarısızsa kilit sürer, 30 sn sonra yeniden denenir', (t) async {
      final rig = _resident(<WorkPhotoSelection>[_one('a.jpg')]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _hitLimitRace(t, rig.service);
      final loads = rig.service.getMineCalls.length;
      rig.service.failures['getMine'] = <Object>[ApiException('Ağ hatası.', statusCode: 503)];

      await t.pump(const Duration(seconds: 30));
      await _settle(t);
      expect(rig.service.getMineCalls.length, loads + 1);
      expect(_addEnabled(t), isFalse, reason: 'yenileme başarısız: kilit sürer');

      await t.pump(const Duration(seconds: 30));
      await _settle(t);
      expect(rig.service.getMineCalls.length, loads + 2);
      expect(_addEnabled(t), isTrue);
    });

    testWidgets('yönetim: 30 sn sonra sessiz yenileme açar', (t) async {
      final rig = _manager(<WorkPhotoSelection>[_one('a.jpg')]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _hitLimitRace(t, rig.service);
      final loads = rig.service.getManagedCalls.length;
      await t.pump(const Duration(seconds: 30));
      await _settle(t);
      expect(rig.service.getManagedCalls.length, loads + 1);
      expect(_addEnabled(t), isTrue);
      expect(find.textContaining(WorkAttachmentRules.limitBusyMessage), findsNothing);
    });

    testWidgets('pencere kapanınca zamanlayıcı iptal edilir (bekleyen zamanlayıcı kalmaz)', (t) async {
      final rig = _resident(<WorkPhotoSelection>[_one('a.jpg')]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _hitLimitRace(t, rig.service);
      final loads = rig.service.getMineCalls.length;
      await _tapKey(t, 'work_resident_detail_close');
      await _settle(t);
      expect(find.byType(WorkAttachmentSection), findsNothing, reason: 'pencere kapandı');
      expect(rig.service.getMineCalls.length, loads);
      // 30 sn ilerletilmiyor: zamanlayıcı dispose'da iptal edilmeseydi test sonunda "A Timer is still pending" hatası
      // alınırdı.
    });

    testWidgets('yönetim: pencere kapanınca zamanlayıcı iptal edilir', (t) async {
      final rig = _manager(<WorkPhotoSelection>[_one('a.jpg')]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _hitLimitRace(t, rig.service);
      await _tapKey(t, 'work_manager_detail_close');
      await _settle(t);
      expect(find.byType(WorkAttachmentSection), findsNothing, reason: 'pencere kapandı');
    });
  });

  group('seçim sürerken kapatma ve seçici kopyaları (R3-2)', () {
    Future<_ResidentRig> openFormPicking(WidgetTester t, Completer<void> gate) async {
      final rig = _resident(<WorkPhotoSelection>[_one('kapi.jpg')]);
      rig.picker.prepareGate = gate;
      await rig.pump(t);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      expect(wkKey('work_form_photo_preparing'), findsOneWidget, reason: 'seçim / hazırlık sürüyor');
      return rig;
    }

    testWidgets('talep formu: seçim sürerken "Vazgeç" kapalı, geri hareketi yok sayılır; bitince ikisi de çalışır',
        (t) async {
      final gate = Completer<void>();
      await openFormPicking(t, gate);
      expect(t.widget<TextButton>(wkKey('work_form_close')).onPressed, isNull);
      await t.binding.handlePopRoute();
      // Kapanma geçişi bitecek kadar beklenir (kapansaydı form ağaçtan çıkmış olurdu).
      await settleFor(t, 600);
      expect(wkKey('work_form_send'), findsOneWidget, reason: 'form açık kaldı');
      expect(wkKey('work_form_discard'), findsNothing, reason: 'kapatma onayı da açılmadı');

      gate.complete();
      await settleFor(t, 100);
      expect(wkKey('work_form_photo_remove_0'), findsOneWidget);
      expect(t.widget<TextButton>(wkKey('work_form_close')).onPressed, isNotNull);
      await t.binding.handlePopRoute();
      await settleFor(t, 100);
      expect(wkKey('work_form_discard'), findsOneWidget, reason: 'fotoğraf eklendi: kapatma onayı sorulur');
    });

    testWidgets('talep formu: seçim sürerken pencere yok olursa release çağrılır; seçim sonradan biterse bir kez daha',
        (t) async {
      final gate = Completer<void>();
      final rig = await openFormPicking(t, gate);
      expect(rig.picker.releaseCalls, 0);
      await t.pumpWidget(const SizedBox());
      expect(rig.picker.releaseCalls, 1, reason: 'dispose: seçim sürüyordu');
      gate.complete();
      await t.pump();
      await t.pump();
      expect(rig.picker.releaseCalls, 2, reason: 'seçim bitti: sonradan oluşan kopyalar da silinir');
    });

    testWidgets('sakin ayrıntısı: seçim sürerken pencere yok olursa release çağrılır', (t) async {
      final rig = _resident(<WorkPhotoSelection>[_one('a.jpg')]);
      final gate = Completer<void>();
      rig.picker.prepareGate = gate;
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      expect(wkKey('work_attachment_preparing'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      expect(rig.picker.releaseCalls, 1);
      gate.complete();
      await t.pump();
      await t.pump();
      expect(rig.picker.releaseCalls, 2);
      expect(rig.service.createAttachmentCalls, isEmpty, reason: 'kapanan pencere yüklemez');
    });
  });
}
