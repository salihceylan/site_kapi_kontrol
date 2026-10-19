// İş Takibi fotoğraf ekleri (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri"): yeni talep formunda fotoğraf seçimi ve
// talep sonrası sıralı yükleme (kısmi başarısızlık DÜRÜSTÇE bildirilir), sakin / yönetim ayrıntısındaki şerit,
// tam ekran görüntüleyici (yakınlaştırma, Sil), ekleme / silme yetkileri (sakin: kendi fotoğrafı; yönetici: hepsi;
// görevli: kendininki; kurul: HİÇBİRİ) ve liste kartındaki fotoğraf sayısı çipi.
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), ön doğrulama
// (tür / boyut / sınır), sunucu hataları (409 sınır / kapalı, 429 kilidi), iptal ve yeniden deneme.
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

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = wkKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

WorkPhotoSelection _selection(List<WorkPhotoPick> picks, {int dropped = 0}) =>
    WorkPhotoSelection(picks: picks, droppedCount: dropped);

// --- Sakin düzeneği -------------------------------------------------------------------------------

class _ResidentRig {
  _ResidentRig(this.service, this.auth, this.picker);

  final FakeWorkService service;
  final WorkFakeAuth auth;
  final FakeWorkPhotoPicker picker;
  final GlobalKey<WorkResidentViewState> key = GlobalKey<WorkResidentViewState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
  }) async {
    await pumpList(
      t,
      WorkResidentView(
        key: key,
        authService: auth,
        service: service,
        sites: _oneSite,
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
    final card = find.byWidgetPredicate((w) => w is WorkResidentCard && w.item.id == id);
    await tapFinder(t, card);
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_ResidentRig _resident({List<WorkPhotoSelection> picks = const <WorkPhotoSelection>[]}) {
  final auth = WorkFakeAuth();
  return _ResidentRig(residentWork(auth), auth, FakeWorkPhotoPicker(picks));
}

// --- Yönetim düzeneği -----------------------------------------------------------------------------

class _ManagerRig {
  _ManagerRig(this.service, this.auth, this.picker);

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

_ManagerRig _manager({
  WorkSiteAccess kind = WorkSiteAccess.manager,
  List<WorkPhotoSelection> picks = const <WorkPhotoSelection>[],
}) {
  final auth = WorkFakeAuth();
  return _ManagerRig(managerWork(auth, kind: kind), auth, FakeWorkPhotoPicker(picks));
}

Future<void> _openViewer(WidgetTester t, int attachmentId) async {
  await _tapKey(t, 'work_attachment_$attachmentId');
  await settleFor(t, 100);
  await settleFor(t, 100);
  expect(wkKey('work_photo_viewer'), findsOneWidget);
}

Future<void> _closeViewer(WidgetTester t) async {
  await _tapKey(t, 'work_photo_viewer_close');
  await settleFor(t, 100);
  await settleFor(t, 100);
  expect(wkKey('work_photo_viewer'), findsNothing);
}

bool _addEnabled(WidgetTester t) =>
    t.widget<PrimaryActionButton>(wkKey('work_attachment_add')).onPressed != null;

void main() {
  group('taşma matrisi', () {
    workMatrix('sakin ayrıntısı: fotoğraf şeridi (2/4), Fotoğraf Ekle', (t, w, h, s, dark) async {
      final rig = _resident();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 1);
      expect(find.text('Fotoğraflar'), findsOneWidget);
      expect(find.text('2/4'), findsOneWidget);
      expect(wkKey('work_attachment_901'), findsOneWidget);
      expect(wkKey('work_attachment_902'), findsOneWidget);
      expect(wkKey('work_attachment_add'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('görüntüleyici: tam ekran, başlık, yakınlaştırma, alt metin', (t, w, h, s, dark) async {
      final rig = _resident();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 1);
      await _openViewer(t, 901);
      expect(find.text('Fotoğraf 1/2'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);
      expect(find.textContaining('sizinti.jpg'), findsOneWidget);
      expect(wkKey('work_photo_viewer_delete'), findsOneWidget, reason: 'sakinin kendi fotoğrafı');
      await _closeViewer(t);
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('yönetim ayrıntısı: yükleyen adları, şerit, Fotoğraf Ekle', (t, w, h, s, dark) async {
      final rig = _manager();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 1);
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('Ben Yönetici'), findsWidgets, reason: 'yükleyen adı şeritte');
      expect(wkKey('work_attachment_add'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('yeni talep formu: seçilen fotoğraf listesi', (t, w, h, s, dark) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('bir.jpg', png: true), wkPhoto('iki.png', png: true)]),
      ]);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      expect(find.text('2/4'), findsOneWidget);
      expect(wkKey('work_form_photo_remove_0'), findsOneWidget);
      expect(wkKey('work_form_photo_remove_1'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('liste kartı', () {
    testWidgets('fotoğraf sayısı çipi yalnız attachment_count > 0 iken (sakin ve yönetim)', (t) async {
      final resident = _resident();
      await resident.pump(t);
      expect(find.text('2 fotoğraf'), findsOneWidget, reason: 'yalnız 1 numaralı talepte');
      final handle = t.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp(r'Talep: Çatı sızıntısı\..* 2 fotoğraf\.')), findsOneWidget);
      handle.dispose();

      final manager = _manager();
      await manager.pump(t);
      expect(find.text('2 fotoğraf'), findsOneWidget);
      expect(find.byType(WorkPhotoCountChip), findsOneWidget);
    });
  });

  group('sakin ayrıntısı', () {
    testWidgets('kendi fotoğrafını siler (onaylı); yönetimin fotoğrafında Sil yok; sayaç düşer; liste yenilenir', (t) async {
      final rig = _resident();
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      expect(rig.service.downloadAttachmentCalls.map((c) => c.attId), containsAll(<int>[901, 902]), reason: 'küçük görseller belirteçli GET ile iner');
      await _openViewer(t, 902);
      expect(wkKey('work_photo_viewer_delete'), findsNothing, reason: 'yönetimin fotoğrafı silinemez');
      await _closeViewer(t);

      await _openViewer(t, 901);
      await _tapKey(t, 'work_photo_viewer_delete');
      await settleFor(t, 100);
      expect(find.text('Fotoğraf silinsin mi?'), findsOneWidget);
      await _tapKey(t, 'work_photo_delete_keep');
      await settleFor(t, 100);
      expect(rig.service.deleteAttachmentCalls, isEmpty);
      await _tapKey(t, 'work_photo_viewer_delete');
      await settleFor(t, 100);
      await _tapKey(t, 'work_photo_delete_confirm');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.deleteAttachmentCalls.single, (site: null, id: 1, attId: 901));
      expect(wkKey('work_photo_viewer'), findsNothing, reason: 'görüntüleyici kapandı');
      expect(wkKey('work_attachment_901'), findsNothing);
      expect(find.text('1/4'), findsOneWidget);
      await _tapKey(t, 'work_resident_detail_close');
      await settleFor(t, 100);
      expect(find.text('1 fotoğraf'), findsOneWidget, reason: 'liste yenilendi: çip güncel');
    });

    testWidgets('Fotoğraf Ekle: seçim -> sıralı yükleme (sakin yolu) -> şerit anında güncellenir (3/4)', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('yeni.jpg', png: true)]),
      ]);
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.picker.calls, <int>[2], reason: 'kalan yer kadar seçim istenir');
      expect(rig.service.createAttachmentCalls.single.site, isNull);
      expect(rig.service.createAttachmentCalls.single.id, 1);
      expect(rig.service.createAttachmentCalls.single.name, 'yeni.jpg');
      expect(rig.service.createAttachmentCalls.single.mime, 'image/png', reason: 'tür içerik imzasından (PNG), uzantıdan önce');
      expect(rig.service.uploadAttachmentCalls.single.size, kWkPng.length);
      expect(find.text('3/4'), findsOneWidget);
      expect(wkKey('work_attachment_903'), findsOneWidget);
      expect(wkKey('work_attachment_error'), findsNothing);
      expect(find.text('Fotoğraf eklendi'), findsOneWidget, reason: 'ayrıntı sessizce eşitlendi: olay çizgisinde');
      await _tapKey(t, 'work_resident_detail_close');
      await settleFor(t, 100);
      expect(rig.picker.releaseCalls, 1, reason: 'seçici önbelleği pencere kapanınca temizlenir');
      expect(find.text('3 fotoğraf'), findsOneWidget);
    });

    testWidgets('yarım kalmış KENDİ kaydı (uploading): şeritte yer tutar, indirilmez; görüntüleyicide açıklama + Sil; '
        'silinince yer açılır', (t) async {
      final rig = _resident();
      rig.service.attachments[1]!.add(
        wkAttachment(903, fileName: 'yarim.jpg', status: 'uploading', mine: true),
      );
      await rig.pump(t, height: 1800);
      expect(find.text('2 fotoğraf'), findsOneWidget, reason: 'liste sayacı yalnız hazır fotoğrafları sayar');
      await rig.openCard(t, 1);
      expect(find.text('3/4'), findsOneWidget);
      expect(find.text('Tamamlanmadı'), findsOneWidget, reason: 'şu an gönderilmeyen yarım kayıt');
      expect(find.text('Yükleniyor'), findsNothing);
      expect(rig.service.downloadAttachmentCalls.map((c) => c.attId), isNot(contains(903)));
      await _openViewer(t, 903);
      expect(wkKey('work_photo_viewer_incomplete'), findsOneWidget);
      await _tapKey(t, 'work_photo_viewer_delete');
      await settleFor(t, 100);
      await _tapKey(t, 'work_photo_delete_confirm');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.deleteAttachmentCalls.single.attId, 903);
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('Fotoğraf kaldırıldı'), findsNothing, reason: 'tamamlanmamış kayıt olaysız kalkar');
    });

    testWidgets('küçük görsel indirilemedi: yeniden çizimde istek YİNELENMEZ; görüntüleyicide Tekrar Dene düzeltir', (t) async {
      final rig = _resident();
      rig.service.failures['downloadAttachment'] = <Object>[ApiException('Sunucu yanıt vermedi.')];
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      int callsFor(int id) => rig.service.downloadAttachmentCalls.where((c) => c.attId == id).length;
      expect(find.text('Açılamadı'), findsOneWidget);
      expect(callsFor(901), 1);
      // Pencereyi yeniden çizdiren bir eylem (boş seçim): başarısız küçük görsel yeniden istenmez.
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(callsFor(901), 1);
      await _openViewer(t, 901);
      expect(find.text('Fotoğraf alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      await tapFinder(t, find.text('Tekrar Dene').last);
      await settleFor(t, 100);
      expect(callsFor(901), 2);
      expect(find.text('Fotoğraf alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsNothing);
      await _closeViewer(t);
      expect(find.text('Açılamadı'), findsNothing, reason: 'görüntüleyici kapanınca küçük görsel önbellekten tazelendi');
      expect(callsFor(901), 2);
    });

    testWidgets('sınır: 4 fotoğrafta Fotoğraf Ekle yok; kapanmış talepte şerit var ama ekleme / silme yok', (t) async {
      final rig = _resident();
      rig.service.attachments[1]!.addAll(<Map<String, dynamic>>[
        wkAttachment(903, fileName: 'uc.jpg', mine: true),
        wkAttachment(904, fileName: 'dort.jpg', mine: true),
      ]);
      rig.service.attachmentBytes[903] = kWkPng;
      rig.service.attachmentBytes[904] = kWkPng;
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      expect(find.text('4/4'), findsOneWidget);
      expect(wkKey('work_attachment_add'), findsNothing);
      await _tapKey(t, 'work_resident_detail_close');
      await settleFor(t, 100);

      rig.service.attachments[2] = <Map<String, dynamic>>[wkAttachment(905, workItemId: 2, mine: true)];
      rig.service.attachmentBytes[905] = kWkPng;
      await _tapKey(t, 'work_status_all');
      await settleFor(t, 100);
      await rig.openCard(t, 2);
      expect(wkKey('work_attachment_905'), findsOneWidget);
      expect(wkKey('work_attachment_add'), findsNothing);
      await _openViewer(t, 905);
      expect(wkKey('work_photo_viewer_delete'), findsNothing, reason: 'kapanmış talepte silme yok');
      await _closeViewer(t);
    });

    testWidgets('ön doğrulama: GIF ve 5 MB üstü sunucuya gitmez; ileti dosya adıyla; sınır aşımı uyarısı', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(
          <WorkPhotoPick>[wkPhoto('hareketli.gif'), WorkPhotoPick.oversized(name: 'dev.jpg', size: 6 * 1024 * 1024)],
          dropped: 1,
        ),
      ]);
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls, isEmpty);
      expect(find.textContaining('hareketli.gif: Yalnız JPEG, PNG veya WebP; en fazla 5 MB.'), findsOneWidget);
      expect(find.textContaining('dev.jpg: Fotoğraf çok büyük'), findsOneWidget);
      expect(find.textContaining('En fazla 4 fotoğraf eklenebilir.'), findsOneWidget);
      expect(find.text('2/4'), findsOneWidget);
    });

    testWidgets('sunucu reddi dürüstçe: 1 fotoğraf yüklendi, 1 fotoğraf yüklenemedi (sınır); 429 kilidi', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('a.jpg', png: true), wkPhoto('b.jpg', png: true)]),
        _selection(<WorkPhotoPick>[wkPhoto('c.jpg', png: true)]),
      ]);
      rig.service.failures['createAttachment'] = <Object>[
        ApiException('Yalnız JPEG, PNG veya WebP; en fazla 5 MB.', statusCode: 415, code: 'UNSUPPORTED_MEDIA_TYPE'),
      ];
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.text('3/4'), findsOneWidget, reason: 'ikinci fotoğraf yüklendi');
      expect(find.text('Yalnız JPEG, PNG veya WebP; en fazla 5 MB.'), findsOneWidget);
      expect(_addEnabled(t), isTrue);

      rig.service.failures['createAttachment'] = <Object>[
        ApiException('Çok fazla fotoğraf işlemi yapıldı. 2 dakika sonra tekrar deneyin.', statusCode: 429, retryAfterSeconds: 120),
      ];
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.text('Çok fazla fotoğraf işlemi yapıldı. 2 dakika sonra tekrar deneyin.'), findsOneWidget);
      expect(_addEnabled(t), isFalse, reason: '429: düğme kilitli');
      await _tapKey(t, 'work_resident_detail_close');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('yükleme sürerken Kapat kapalı ve geri tuşu kapatmaz; Vazgeç iptal eder, tamamlanan kalır', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('a.jpg', png: true), wkPhoto('b.jpg', png: true)]),
      ]);
      final gate = Completer<void>();
      rig.service.gates['uploadMid'] = <Completer<void>>[gate];
      await rig.pump(t, height: 1800);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      expect(wkKey('work_attachment_upload_progress'), findsOneWidget);
      expect(find.text('Fotoğraf 1/2 yükleniyor...'), findsOneWidget);
      expect(t.widget<TextButton>(wkKey('work_resident_detail_close')).onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Talep Ayrıntısı'), findsOneWidget, reason: 'yükleme sürerken kapanmaz');
      await _tapKey(t, 'work_attachment_upload_cancel');
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.length, 1, reason: 'ikinci fotoğraf hiç başlamaz');
      expect(find.textContaining('2 fotoğraf yüklenemedi. Yükleme iptal edildi.'), findsOneWidget);
      expect(find.text('2/4'), findsOneWidget);
      expect(t.widget<TextButton>(wkKey('work_resident_detail_close')).onPressed, isNotNull);
    });
  });

  group('yönetim ayrıntısı', () {
    testWidgets('yönetici: yükleyen adı; HER fotoğrafı silebilir; yönetim yolu (siteCode) ile ekler', (t) async {
      final rig = _manager(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('yonetici.webp', png: true)]),
      ]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(find.textContaining('Ayşe Yılmaz'), findsWidgets);
      await _openViewer(t, 901);
      expect(wkKey('work_photo_viewer_delete'), findsOneWidget, reason: 'sakinin fotoğrafını da siler');
      expect(find.textContaining('Ayşe Yılmaz · 15.10.2026 12:05'), findsOneWidget, reason: 'yükleyen + İstanbul saati');
      await _closeViewer(t);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.single.site, 11);
      expect(rig.service.createAttachmentCalls.single.mime, 'image/png', reason: 'içerik PNG: uzantı (.webp) değil imza esas');
      expect(rig.service.uploadAttachmentCalls.single.site, 11);
      expect(find.text('3/4'), findsOneWidget);
      expect(rig.service.downloadAttachmentCalls.every((c) => c.site == 11), isTrue);
      expect(find.text('Fotoğraf eklendi'), findsOneWidget, reason: 'yönetim olay çizgisinde de görünür');
    });

    testWidgets('görevli: yalnız kendi yüklediğini siler', (t) async {
      final rig = _manager(kind: WorkSiteAccess.staff);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _openViewer(t, 901);
      expect(wkKey('work_photo_viewer_delete'), findsNothing, reason: 'sakinin fotoğrafı');
      await _closeViewer(t);
      await _openViewer(t, 902);
      expect(wkKey('work_photo_viewer_delete'), findsOneWidget, reason: 'kendi yüklediği');
      await _tapKey(t, 'work_photo_viewer_delete');
      await settleFor(t, 100);
      await _tapKey(t, 'work_photo_delete_confirm');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.deleteAttachmentCalls.single, (site: 11, id: 1, attId: 902));
      expect(find.text('1/4'), findsOneWidget);
    });

    testWidgets('kurul (SALT OKUR): şerit görünür, Fotoğraf Ekle YOK, görüntüleyicide Sil YOK', (t) async {
      final rig = _manager(kind: WorkSiteAccess.board);
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(wkKey('work_attachment_901'), findsOneWidget);
      expect(wkKey('work_attachment_902'), findsOneWidget);
      expect(wkKey('work_attachment_add'), findsNothing);
      expect(find.text('Fotoğraf Ekle'), findsNothing);
      await _openViewer(t, 902);
      expect(wkKey('work_photo_viewer_delete'), findsNothing);
      await _closeViewer(t);
      expect(rig.service.createAttachmentCalls, isEmpty);
      expect(rig.service.deleteAttachmentCalls, isEmpty);
    });

    testWidgets('silme hatası (403): fotoğraf kalır, ileti görünür', (t) async {
      final rig = _manager();
      rig.service.failures['deleteAttachment'] = <Object>[FakeWorkService.forbidden()];
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _openViewer(t, 901);
      await _tapKey(t, 'work_photo_viewer_delete');
      await settleFor(t, 100);
      await _tapKey(t, 'work_photo_delete_confirm');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_attachment_901'), findsOneWidget);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
    });
  });

  group('yeni talep formu', () {
    testWidgets('fotoğraf seç (2), birini kaldır, gönder: talep açılır, SONRA fotoğraf yüklenir; başarı bildirimi', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('bir.jpg', png: true), wkPhoto('iki.png', png: true)]),
      ]);
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      expect(rig.picker.calls, <int>[4]);
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('bir.jpg'), findsOneWidget);
      await _tapKey(t, 'work_form_photo_remove_0');
      await settleFor(t, 100);
      expect(find.text('1/4'), findsOneWidget);
      expect(find.text('bir.jpg'), findsNothing);
      await _type(t, 'work_form_title', 'Musluk akıyor');
      await _type(t, 'work_form_description', 'Mutfak musluğu damlatıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createCalls.length, 1);
      final newId = rig.service.residentRows.last['id'] as int;
      expect(rig.service.createAttachmentCalls.single.id, newId, reason: 'fotoğraf yeni talebe yüklenir');
      expect(rig.service.createAttachmentCalls.single.name, 'iki.png');
      expect(rig.service.attachments[newId]!.single['status'], 'ready');
      expect(wkKey('work_form_send'), findsNothing, reason: 'form kapandı');
      expect(find.textContaining('Talebiniz alındı'), findsOneWidget);
      expect(find.text('1 fotoğraf'), findsOneWidget, reason: 'listede fotoğraf çipi');
      expect(rig.picker.releaseCalls, 1);
    });

    testWidgets('kısmi başarısızlık DÜRÜSTÇE: sonuç ekranı (Kapat / Tekrar Dene); Kapat -> "1 fotoğraf yüklenemedi"', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('bir.jpg', png: true), wkPhoto('iki.jpg', png: true)]),
      ]);
      rig.service.failures['uploadAttachment'] = <Object>[
        ApiException('Fotoğraf yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'),
      ];
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Kapı');
      await _type(t, 'work_form_description', 'Gıcırdıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.text('Fotoğraf Yükleme Sonucu'), findsOneWidget);
      expect(find.textContaining('1 fotoğraf yüklenemedi'), findsOneWidget);
      expect(find.text('Yüklendi'), findsOneWidget);
      expect(find.text('Fotoğraf yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(wkKey('work_form_upload_retry'), findsOneWidget);
      expect(wkKey('work_form_send'), findsNothing, reason: 'form bir daha gönderilmez');
      await _tapKey(t, 'work_form_upload_close');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createCalls.length, 1, reason: 'talep bir kez açıldı');
      expect(find.text('Talep oluşturuldu, 1 fotoğraf yüklenemedi.'), findsOneWidget);
    });

    testWidgets('kısmi başarısızlıkta Tekrar Dene: yalnız başarısız fotoğraf aynı kayda yeniden gider; başarıda kapanır', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('bir.jpg', png: true), wkPhoto('iki.jpg', png: true)]),
      ]);
      rig.service.failures['uploadAttachment'] = <Object>[ApiException('Kopuk bağlantı.')];
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Kapı');
      await _type(t, 'work_form_description', 'Gıcırdıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      final failedAttId = rig.service.uploadAttachmentCalls.first.attId;
      await _tapKey(t, 'work_form_upload_retry');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.length, 2, reason: 'yeniden denemede adım 1 yinelenmez');
      expect(rig.service.uploadAttachmentCalls.map((c) => c.attId).where((id) => id == failedAttId).length, 2);
      expect(wkKey('work_form_upload_close'), findsNothing, reason: 'hepsi yüklendi: pencere kapandı');
      expect(find.textContaining('Talebiniz alındı'), findsOneWidget);
      expect(find.text('2 fotoğraf'), findsWidgets);
    });

    testWidgets('yükleme sürerken geri tuşu kapatmaz; Vazgeç -> iptal bildirimi ile kapanış', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('bir.jpg', png: true)]),
      ]);
      final gate = Completer<void>();
      rig.service.gates['uploadMid'] = <Completer<void>>[gate];
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Kapı');
      await _type(t, 'work_form_description', 'Gıcırdıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      expect(find.text('Fotoğraflar Yükleniyor'), findsOneWidget);
      expect(wkKey('work_form_upload_progress'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Fotoğraflar Yükleniyor'), findsOneWidget, reason: 'yükleme sürerken kapanmaz');
      await _tapKey(t, 'work_form_upload_cancel');
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.textContaining('fotoğraf yükleme iptal edildi'), findsOneWidget);
      await _tapKey(t, 'work_form_upload_close');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.text('Talep oluşturuldu, fotoğraf yükleme iptal edildi; 1 fotoğraf eklenmedi.'), findsOneWidget);
      expect(rig.service.createCalls.length, 1);
    });

    testWidgets('sınır: 4 fotoğrafta düğme kapalı; fazlası uyarılır; ön doğrulama iletisi', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(
          <WorkPhotoPick>[wkPhoto('a.jpg'), wkPhoto('b.jpg'), wkPhoto('c.jpg'), wkPhoto('d.jpg'), wkPhoto('e.gif')],
          dropped: 1,
        ),
      ]);
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      expect(find.text('4/4'), findsOneWidget);
      expect(find.textContaining('e.gif: Yalnız JPEG, PNG veya WebP; en fazla 5 MB.'), findsOneWidget);
      expect(find.textContaining('En fazla 4 fotoğraf eklenebilir.'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(wkKey('work_form_photo_add')).onPressed, isNull);
      expect(find.text('Fotoğraf sınırına ulaşıldı'), findsOneWidget);
      // Fotoğraf seçimi formu "dolu" sayar: kapatırken onay istenir.
      await _tapKey(t, 'work_form_close');
      await settleFor(t, 100);
      expect(find.text('Talep silinsin mi?'), findsOneWidget);
      await _tapKey(t, 'work_form_discard');
      await settleFor(t, 100);
      expect(wkKey('work_form_send'), findsNothing);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('seçici hatası pencerede kalır; fotoğrafsız gönderim eskisi gibi kapanır', (t) async {
      final rig = _resident();
      rig.picker.error = StateError('seçici yok');
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_photo_add');
      await settleFor(t, 100);
      expect(find.text('Fotoğraf seçilemedi. Tekrar deneyin.'), findsOneWidget);
      await _type(t, 'work_form_title', 'Otopark ışığı');
      await _type(t, 'work_form_description', 'Yanmıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls, isEmpty);
      expect(wkKey('work_form_send'), findsNothing);
      expect(find.textContaining('Talebiniz alındı'), findsOneWidget);
    });
  });
}
