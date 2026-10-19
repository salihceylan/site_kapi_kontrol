// İş Takibi fotoğraf ekleri — bağımsız inceleme bulguları ve sunucu sözleşmesi değişiklikleri:
// - gizlilik: sakin görünümünde yükleyen adı yok ("Siz" / "Yönetim"; sunucu ad sızdırsa bile), ekran okuyucu dahil;
// - küçük görsel: tek düğüm, düğme + dokunma eylemi; "Yükleniyor" yalnız gönderilen kayıtta, diğer yarım kayıt
//   "Tamamlanmadı";
// - görüntüleyici: yakınken sayfa kaymaz, sayfa değişince yakınlık sıfırlanır, önceki / sonraki (48 dp, ipucu) ve ok
//   tuşları;
// - yönetici kapanmış talepte fotoğraf siler, görevli silemez;
// - 409 LIMIT_REACHED ama ekranda 4'ten az fotoğraf: açıklayıcı ileti ve "Fotoğraf Ekle" sonraki yüklemeye dek kapalı;
//   silme onayı eski iletiyi temizler;
// - 409 ATTACHMENT_QUOTA_EXCEEDED (kişi / site) iletileri;
// - geçersiz seçim yer doldurmaz;
// - bellek: pencere kapanınca çözülen görseller ImageCache'ten çıkar; 40 milyon pikseli aşan görsel hiç çözülmez;
// - web: bayt ilerlemesi yok (belirsiz çubuk);
// - talep önceden kayıtlıysa da (replayed) fotoğraf hatası bildirilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_attachment_upload.dart';
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

WorkPhotoSelection _selection(
  List<WorkPhotoPick> picks, {
  List<WorkPhotoPick> rejected = const <WorkPhotoPick>[],
}) => WorkPhotoSelection(picks: picks, rejected: rejected);

class _ResidentRig {
  _ResidentRig(this.service, this.auth, this.picker);

  final FakeWorkService service;
  final WorkFakeAuth auth;
  final FakeWorkPhotoPicker picker;

  Future<void> pump(WidgetTester t, {double width = 400, double height = 1800}) async {
    await pumpList(
      t,
      WorkResidentView(authService: auth, service: service, sites: _oneSite, photoPicker: picker),
      width: width,
      height: height,
      scale: 1.0,
      dark: false,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }

  Future<void> openCard(WidgetTester t, int id) async {
    await tapFinder(t, find.byWidgetPredicate((w) => w is WorkResidentCard && w.item.id == id));
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_ResidentRig _resident({List<WorkPhotoSelection> picks = const <WorkPhotoSelection>[]}) {
  final auth = WorkFakeAuth();
  return _ResidentRig(residentWork(auth), auth, FakeWorkPhotoPicker(picks));
}

class _ManagerRig {
  _ManagerRig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;

  Future<void> pump(WidgetTester t) async {
    await pumpList(
      t,
      WorkManagerView(
        authService: auth,
        service: service,
        sites: <WorkTrackingSite>[WorkTrackingSite(code: 11, name: 'Gül Sitesi', access: service.kind)],
        photoPicker: FakeWorkPhotoPicker(),
      ),
      width: 400,
      height: 3000,
      scale: 1.0,
      dark: false,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }

  Future<void> openCard(WidgetTester t, int id) async {
    await tapFinder(t, find.byWidgetPredicate((w) => w is WorkManagedCard && w.item.id == id));
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_ManagerRig _manager({WorkSiteAccess kind = WorkSiteAccess.manager}) {
  final auth = WorkFakeAuth();
  return _ManagerRig(managerWork(auth, kind: kind), auth);
}

Future<void> _openViewer(WidgetTester t, int attachmentId) async {
  await _tapKey(t, 'work_attachment_$attachmentId');
  await settleFor(t, 100);
  await settleFor(t, 100);
  expect(wkKey('work_photo_viewer'), findsOneWidget);
}

Future<void> _deleteInViewer(WidgetTester t) async {
  await _tapKey(t, 'work_photo_viewer_delete');
  await settleFor(t, 100);
  await _tapKey(t, 'work_photo_delete_confirm');
  await settleFor(t, 100);
  await settleFor(t, 100);
}

bool _addEnabled(WidgetTester t) =>
    t.widget<PrimaryActionButton>(wkKey('work_attachment_add')).onPressed != null;

void main() {
  group('gizlilik: sakin görünümünde yükleyen', () {
    testWidgets('kendi fotoğrafı "Siz", yönetiminki "Yönetim"; sunucu adı sızdırsa bile görevli adı ekranda ve ekran '
        'okuyucuda YOK', (t) async {
      final rig = _resident();
      rig.service.leakUploaderNames = true;
      final handle = t.ensureSemantics();
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(find.semantics.byLabel(RegExp(r'Fotoğraf: onarim\.png\. Yönetim · 16\.10\.2026 13:00\.')), findsOne);
      expect(find.semantics.byLabel(RegExp(r'Fotoğraf: sizinti\.jpg\. Siz · 15\.10\.2026 12:05\.')), findsOne);
      expect(find.semantics.byLabel(RegExp('Ben Yönetici')), findsNothing);
      expect(find.textContaining('Ben Yönetici'), findsNothing);
      await _openViewer(t, 902);
      expect(find.text('Yönetim · 16.10.2026 13:00'), findsOneWidget);
      expect(find.textContaining('Ben Yönetici'), findsNothing);
      expect(find.semantics.byLabel(RegExp('Ben Yönetici')), findsNothing);
      handle.dispose();
    });

    testWidgets('yönetim görünümü gerçek adı gösterir (şerit, görüntüleyici)', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(find.text('Ben Yönetici'), findsWidgets, reason: 'şeritte yükleyen adı');
      await _openViewer(t, 902);
      expect(find.text('Ben Yönetici · 16.10.2026 13:00'), findsOneWidget);
    });
  });

  group('küçük görsel', () {
    testWidgets('tek düğüm: düğme + dokunma eylemi; ekran okuyucu dokunuşu görüntüleyiciyi açar', (t) async {
      final rig = _resident();
      final handle = t.ensureSemantics();
      await rig.pump(t);
      await rig.openCard(t, 1);
      expect(
        t.getSemantics(wkKey('work_attachment_901')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      t.semantics.tap(find.semantics.byLabel(RegExp(r'Fotoğraf: sizinti\.jpg')));
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(wkKey('work_photo_viewer'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('yalnız gönderilen kayıt "Yükleniyor"; diğer yarım kayıt "Tamamlanmadı"', (t) async {
      final cache = WorkAttachmentImageCache((attachment) async => kWkPng);
      addTearDown(cache.dispose);
      await pumpList(
        t,
        WorkAttachmentStrip(
          attachments: const <WorkAttachment>[
            WorkAttachment(id: 1, fileName: 'gonderilen.jpg', status: WorkAttachmentStatus.uploading, uploadedByMe: true),
            WorkAttachment(id: 2, fileName: 'yarim.jpg', status: WorkAttachmentStatus.uploading, uploadedByMe: true),
          ],
          cache: cache,
          onOpen: (_) {},
          inFlightAttachmentId: 1,
        ),
        width: 400,
        height: 600,
        scale: 1.0,
        dark: false,
      );
      expect(find.text('Yükleniyor'), findsOneWidget);
      expect(find.text('Tamamlanmadı'), findsOneWidget);
    });
  });

  group('görüntüleyici', () {
    testWidgets('önceki / sonraki (48 dp, ipucu), ok tuşları; yakınken sayfa kaymaz; sayfa değişince yakınlık sıfırlanır',
        (t) async {
      final rig = _resident();
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _openViewer(t, 901);
      expect(find.text('Fotoğraf 1/2'), findsOneWidget);
      expect(find.byTooltip('Önceki fotoğraf'), findsOneWidget);
      expect(find.byTooltip('Sonraki fotoğraf'), findsOneWidget);
      expect(t.widget<IconButton>(wkKey('work_photo_viewer_previous')).onPressed, isNull, reason: 'ilk fotoğraf');
      final size = t.getSize(wkKey('work_photo_viewer_next'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      // Yakınlaştır: sayfa kaydırma kapanır, sürükleme sayfayı değiştirmez.
      final zoom = t.widget<InteractiveViewer>(find.byType(InteractiveViewer).first).transformationController!;
      zoom.value = Matrix4.diagonal3Values(2, 2, 1);
      await t.pump();
      expect(t.widget<PageView>(wkKey('work_photo_viewer_pages')).physics, isA<NeverScrollableScrollPhysics>());
      await t.drag(wkKey('work_photo_viewer_pages'), const Offset(-300, 0));
      await settleFor(t, 400);
      expect(find.text('Fotoğraf 1/2'), findsOneWidget, reason: 'yakınken sürükleme görseli kaydırır, sayfayı değil');

      // Sonraki düğmesi: sayfa değişir, önceki sayfanın yakınlığı sıfırlanır, kaydırma yeniden açılır.
      await tapFinder(t, find.byTooltip('Sonraki fotoğraf'));
      await settleFor(t, 400);
      expect(find.text('Fotoğraf 2/2'), findsOneWidget);
      expect(zoom.value.getMaxScaleOnAxis(), 1.0);
      expect(t.widget<PageView>(wkKey('work_photo_viewer_pages')).physics, isNull);
      expect(t.widget<IconButton>(wkKey('work_photo_viewer_next')).onPressed, isNull, reason: 'son fotoğraf');

      // Ok tuşları.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settleFor(t, 400);
      expect(find.text('Fotoğraf 1/2'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settleFor(t, 400);
      expect(find.text('Fotoğraf 2/2'), findsOneWidget);
    });
  });

  group('yetki: kapanmış talepte silme', () {
    testWidgets('yönetici KAPANMIŞ talepte fotoğraf siler; not metni bunu söyler', (t) async {
      final rig = _manager();
      rig.service.attachments[2] = <Map<String, dynamic>>[
        wkAttachment(905, workItemId: 2, fileName: 'eski.jpg', uploadedBy: 'Veli Kaya', kind: 'resident'),
      ];
      rig.service.attachmentBytes[905] = kWkPng;
      await rig.pump(t);
      await _tapKey(t, 'work_status_kapandi');
      await settleFor(t, 100);
      await rig.openCard(t, 2);
      expect(find.textContaining('gerekirse fotoğraflarını silebilirsiniz'), findsOneWidget);
      expect(wkKey('work_attachment_add'), findsNothing, reason: 'kapanmış talebe fotoğraf eklenmez');
      await _openViewer(t, 905);
      expect(wkKey('work_photo_viewer_delete'), findsOneWidget);
      await _deleteInViewer(t);
      expect(rig.service.deleteAttachmentCalls.single, (site: 11, id: 2, attId: 905));
      expect(find.text('0/4'), findsOneWidget);
    });

    testWidgets('görevli KAPANMIŞ talepte kendi fotoğrafını da silemez (Sil yok)', (t) async {
      final rig = _manager(kind: WorkSiteAccess.staff);
      rig.service.attachments[2] = <Map<String, dynamic>>[
        wkAttachment(905, workItemId: 2, fileName: 'eski.jpg', uploadedBy: 'Ben Yönetici', kind: 'management', mine: true),
      ];
      rig.service.attachmentBytes[905] = kWkPng;
      await rig.pump(t);
      await _tapKey(t, 'work_status_kapandi');
      await settleFor(t, 100);
      await rig.openCard(t, 2);
      expect(find.textContaining('yorum ve fotoğraf alamaz'), findsOneWidget);
      expect(find.textContaining('gerekirse fotoğraflarını silebilirsiniz'), findsNothing);
      await _openViewer(t, 905);
      expect(wkKey('work_photo_viewer_delete'), findsNothing);
    });
  });

  group('sınır ve kota', () {
    testWidgets('LIMIT_REACHED ama ekranda 4ten az fotoğraf: "başka bir fotoğraf yükleniyor olabilir", Fotoğraf Ekle '
        'kapalı; sonraki yükleme açar; silme onayı eski iletiyi temizler', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('a.jpg', png: true)]),
      ]);
      rig.service.failures['createAttachment'] = <Object>[
        ApiException(WorkAttachmentRules.limitMessage, statusCode: 409, code: 'LIMIT_REACHED'),
      ];
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.textContaining(WorkAttachmentRules.limitBusyMessage), findsOneWidget);
      expect(find.textContaining('En fazla 4 fotoğraf eklenebilir.'), findsNothing);
      expect(find.text('2/4'), findsOneWidget);
      expect(_addEnabled(t), isFalse, reason: 'sonraki yüklemeye dek kapalı');

      // Kendi fotoğrafını silmek: onay eski iletiyi temizler; silme sonrası tazeleme kilidi açar.
      await _openViewer(t, 901);
      await _deleteInViewer(t);
      expect(find.textContaining(WorkAttachmentRules.limitBusyMessage), findsNothing);
      expect(find.text('1/4'), findsOneWidget);
      expect(_addEnabled(t), isTrue);
    });

    testWidgets('kota: kişi ve site iletileri', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(<WorkPhotoPick>[wkPhoto('a.jpg', png: true)]),
        _selection(<WorkPhotoPick>[wkPhoto('b.jpg', png: true)]),
      ]);
      rig.service.quotaExceeded = 'user';
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.textContaining('Bu sitedeki fotoğraf kotanız doldu (en çok 200 MB).'), findsOneWidget);
      rig.service.quotaExceeded = 'site';
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.textContaining('Sitenin fotoğraf depolama alanı doldu; yönetime başvurun.'), findsOneWidget);
      expect(rig.service.uploadAttachmentCalls, isEmpty);
    });

    testWidgets('geçersiz seçim yer DOLDURMAZ: 2 boş yere 2 geçerli fotoğraf yüklenir, GIF ayrıca bildirilir', (t) async {
      final rig = _resident(picks: <WorkPhotoSelection>[
        _selection(
          <WorkPhotoPick>[wkPhoto('a.jpg', png: true), wkPhoto('b.jpg', png: true)],
          rejected: <WorkPhotoPick>[wkPhoto('c.gif')],
        ),
      ]);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await _tapKey(t, 'work_attachment_add');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createAttachmentCalls.length, 2);
      expect(find.text('4/4'), findsOneWidget);
      expect(find.textContaining('c.gif: Yalnız JPEG, PNG veya WebP; en fazla 5 MB.'), findsOneWidget);
      expect(find.textContaining('En fazla 4 fotoğraf eklenebilir.'), findsNothing);
    });
  });

  group('bellek', () {
    testWidgets('pencere kapanınca çözülen fotoğraflar ImageCache\'ten çıkarılır', (t) async {
      final imageCache = PaintingBinding.instance.imageCache;
      int entries() => imageCache.pendingImageCount + imageCache.currentSize + imageCache.liveImageCount;
      final rig = _resident();
      await rig.pump(t);
      final before = entries();
      await rig.openCard(t, 1);
      await settleFor(t, 100);
      expect(entries(), greaterThan(before), reason: 'küçük görseller ImageCache\'e girdi');
      await _tapKey(t, 'work_resident_detail_close');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(entries(), before);
    });

    testWidgets('40 milyon pikseli aşan görsel ÇÖZÜLMEZ: küçük görsel "Çok büyük", görüntüleyici açıklar', (t) async {
      final rig = _resident();
      rig.service.attachmentBytes[901] = wkPngHeader(width: 10000, height: 5000);
      await rig.pump(t);
      await rig.openCard(t, 1);
      await settleFor(t, 100);
      expect(find.text('Çok büyük'), findsOneWidget);
      await _openViewer(t, 901);
      expect(wkKey('work_photo_viewer_too_large'), findsOneWidget);
    });
  });

  group('web ve bildirim', () {
    testWidgets('web: bayt ilerlemesi yok; belirsiz çubuk ve "Fotoğraf gönderiliyor..."', (t) async {
      final service = residentWork(WorkFakeAuth());
      final gate = Completer<void>();
      service.gates['uploadAttachment'] = <Completer<void>>[gate];
      final c = WorkAttachmentUploadController(service: service, workItemId: 3, web: true);
      addTearDown(c.dispose);
      await pumpList(
        t,
        WorkUploadProgress(controller: c),
        width: 400,
        height: 600,
        scale: 1.0,
        dark: false,
      );
      final running = c.run(<WorkPhotoPick>[wkPhoto('a.jpg')]);
      await settleFor(t, 50);
      expect(c.progressKnown, isFalse);
      expect(find.text('Fotoğraf gönderiliyor...'), findsOneWidget);
      expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
      gate.complete();
      await settleFor(t, 100);
      final results = await running;
      expect(results.single.ok, isTrue);
    });

    test('talep önceden kayıtlıysa (replayed) da fotoğraf hatası bildirilir', () {
      final base = WorkCreateResult.fromJson(<String, dynamic>{'item': wkResident(7), 'replayed': true});
      expect(WorkResidentViewState.createdMessage(base), 'Bu talep zaten kayıtlıydı.');
      expect(
        WorkResidentViewState.createdMessage(base.withPhotoOutcome(uploaded: 1, failed: 2)),
        'Bu talep zaten kayıtlıydı, 2 fotoğraf yüklenemedi.',
      );
      expect(
        WorkResidentViewState.createdMessage(base.withPhotoOutcome(uploaded: 0, failed: 1, cancelled: true)),
        'Bu talep zaten kayıtlıydı, fotoğraf yükleme iptal edildi; 1 fotoğraf eklenmedi.',
      );
      final fresh = WorkCreateResult.fromJson(<String, dynamic>{'item': wkResident(8), 'replayed': false});
      expect(
        WorkResidentViewState.createdMessage(fresh.withPhotoOutcome(uploaded: 0, failed: 1)),
        'Talep oluşturuldu, 1 fotoğraf yüklenemedi.',
      );
    });
  });
}
