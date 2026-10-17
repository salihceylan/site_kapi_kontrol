// Platform Faz 3b-A: belge ayrıntı penceresi (DocumentDetailDialog) — yönetici, kurul ve silinmiş görünümleri,
// Aç / Kaydet (indir -> paylaş), sürümler, yeni sürüm, düzenleme, silme (DOCUMENT_IN_USE ikinci onayı), geri
// yükleme ve kalıcı silme.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5 (+ yatay ve tablet), açık + koyu tema; yükleniyor / hata /
// dolu durumlar taşmaz. Hata ASLA "belge yok" demez; eylemler çift dokunuşa karşı korunur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/document_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'document_fixtures.dart';
import 'list_fixtures.dart' show tapFinder;

class _Rig {
  _Rig({
    this.canWrite = true,
    bool board = false,
    int id = 41,
    this.picks = const [],
  }) : auth = DocumentFakeAuth() {
    service = seededDocuments(auth, board: board);
    sharer = DocumentFileSharer(
      shareFn: (params) async {
        shared.add(params);
        return const ShareResult('', ShareResultStatus.success);
      },
      cleanupDelay: Duration.zero,
      sweepStaleOnShare: false,
    );
    documentId = id;
  }

  final DocumentFakeAuth auth;
  late final FakeDocumentService service;
  late final DocumentFileSharer sharer;
  late final int documentId;
  final bool canWrite;
  final List<dynamic> picks;
  final List<ShareParams> shared = <ShareParams>[];
  String? message;
  bool closed = false;
  int changed = 0;
  late final FakeDocumentPicker picker = FakeDocumentPicker(
    <dynamic>[...picks].cast(),
  );

  PeopleScope get scope => PeopleScope(
    authService: auth,
    siteCode: 11,
    siteName: 'Gül Sitesi',
    canWrite: canWrite,
  );

  Future<void> open(
    WidgetTester t, {
    double width = 400,
    double height = 1800,
    double scale = 1.0,
    bool dark = false,
  }) {
    return openDialogAt(
      t,
      (context) async {
        message = await DocumentDetailDialog.show(
          context,
          scope: scope,
          service: service,
          documentId: documentId,
          initialTitle: 'Liste başlığı',
          picker: picker,
          sharer: sharer,
          usage: const DocumentUsage(
            usedBytes: 1000,
            quotaBytes: 200 * 1024 * 1024,
          ),
          onChanged: () => changed++,
        );
        closed = true;
      },
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
  }

  Future<void> loaded(
    WidgetTester t, {
    double width = 400,
    double height = 1800,
    double scale = 1.0,
    bool dark = false,
  }) async {
    await open(t, width: width, height: height, scale: scale, dark: dark);
    await settleFor(t);
    await settleFor(t);
  }
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _tap(WidgetTester t, String key) => tapFinder(t, _key(key));

void main() {
  group('yatay telefon (640x360 x2,0)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'yönetici ayrıntısı ve silinmiş görünüm taşmaz (${dark ? 'koyu' : 'açık'})',
        (t) async {
          final rig = _Rig();
          await rig.loaded(t, width: 640, height: 360, scale: 2.0, dark: dark);
          expect(find.text('Aç / Kaydet'), findsOneWidget);
          expect(t.takeException(), isNull);
          final deleted = _Rig(id: 38);
          await deleted.loaded(
            t,
            width: 640,
            height: 360,
            scale: 2.0,
            dark: dark,
          );
          expect(find.text('Geri Yükle'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  });

  group('taşma matrisi', () {
    layoutMatrix('yönetici: yayındaki belge (bilgiler, eylemler, sürümler)', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final rig = _Rig();
      await rig.loaded(t, width: w, height: h, scale: s, dark: dark);

      expect(find.text('Site Yönetmeliği'), findsWidgets);
      expect(find.text('Kitle: A Blok'), findsOneWidget);
      expect(find.text('Güncel site yönetmeliği.'), findsOneWidget);
      expect(find.text('Aç / Kaydet'), findsOneWidget);
      expect(find.text('Yeni Sürüm Yükle'), findsOneWidget);
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      expect(find.text('Sürümler'), findsOneWidget);
      expect(find.text('v2 (güncel)'), findsOneWidget);
      expect(find.text('v1'), findsOneWidget);
      expect(
        find.text('Madde 4 düzeltildi'),
        findsNothing,
        reason: 'not "Not: ..." biçiminde',
      );
      expect(find.text('Not: Madde 4 düzeltildi'), findsOneWidget);
      expect(find.text('2 duyuruya ekli'), findsNothing);
    });

    layoutMatrix(
      'yönetici: silinmiş belge (Geri Yükle, Kalıcı Sil, kalan gün)',
      (t, w, h, s, dark) async {
        final rig = _Rig(id: 38);
        await rig.loaded(t, width: w, height: h, scale: s, dark: dark);

        expect(find.text('Geri Yükle'), findsOneWidget);
        expect(find.text('Kalıcı Sil'), findsOneWidget);
        expect(
          find.text('Silindi · 12 gün sonra kalıcı silinir'),
          findsOneWidget,
        );
        expect(find.text('Yeni Sürüm Yükle'), findsNothing);
        expect(find.text('Düzenle'), findsNothing);
      },
    );

    layoutMatrix(
      'kurul: salt okur (yazma düğmesi, yükleyen adı, sürüm silme yok)',
      (t, w, h, s, dark) async {
        final rig = _Rig(canWrite: false, board: true, id: 40);
        await rig.loaded(t, width: w, height: h, scale: s, dark: dark);

        expect(find.text('Aç / Kaydet'), findsOneWidget);
        expect(find.text('Yeni Sürüm Yükle'), findsNothing);
        expect(find.text('Düzenle'), findsNothing);
        expect(find.text('Sil'), findsNothing);
        expect(find.textContaining('Yükleyen'), findsNothing);
        expect(
          find.textContaining('yalnızca görüntüleyebilirsiniz'),
          findsOneWidget,
        );
      },
    );

    layoutMatrix('yükleniyor ve hata durumları', (t, w, h, s, dark) async {
      final rig = _Rig();
      final gate = Completer<void>();
      rig.service.detailGates.add(gate);
      await rig.open(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Belge yükleniyor...'), findsOneWidget);
      expect(
        find.text('Liste başlığı'),
        findsOneWidget,
        reason: 'yüklenirken liste başlığı görünür',
      );
      rig.service.detailError = ApiException('Sunucuya bağlanılamadı.');
      gate.complete();
      await settleFor(t);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(
        find.text('Aç / Kaydet'),
        findsNothing,
        reason: 'hata durumunda boş / sahte belge çizilmez',
      );
    });
  });

  group('yükleme ve hata', () {
    testWidgets('Tekrar Dene ayrıntıyı getirir', (t) async {
      final rig = _Rig();
      rig.service.detailError = ApiException('Bağlantı koptu.');
      await rig.loaded(t);
      expect(find.text('Bağlantı koptu.'), findsOneWidget);
      rig.service.detailError = null;
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.text('Aç / Kaydet'), findsOneWidget);
    });

    testWidgets(
      'belge bulunamadı (404): iletisi gösterilir ve liste tazelenir',
      (t) async {
        final rig = _Rig(id: 999);
        await rig.loaded(t);
        expect(
          find.text('Belge bulunamadı ya da erişiminiz yok.'),
          findsOneWidget,
        );
        expect(rig.changed, 1);
      },
    );
  });

  group('Aç / Kaydet', () {
    testWidgets(
      'indirir, ilerleme penceresi kapanır, paylaşım menüsü açılır; geçici kopya bellekte',
      (t) async {
        final rig = _Rig();
        await rig.loaded(t);
        final gate = Completer<void>();
        rig.service.downloadGates.add(gate);
        await _tap(t, 'document_detail_open');
        await settleFor(t);
        expect(find.text('Belge indiriliyor'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('document_download_progress')),
          findsOneWidget,
        );
        expect(rig.shared, isEmpty);

        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Belge indiriliyor'), findsNothing);
        expect(rig.service.downloadCalls.single, (id: 41, version: null));
        expect(rig.shared, hasLength(1));
        expect(rig.shared.single.fileNameOverrides, <String>[
          'yonetmelik-v2.pdf',
        ]);
        expect(rig.shared.single.files!.single.mimeType, 'application/pdf');
      },
    );

    testWidgets('eski sürümü indirir (version parametresi)', (t) async {
      final rig = _Rig();
      await rig.loaded(t);
      await _tap(t, 'document_version_download_1');
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.downloadCalls.single, (id: 41, version: 1));
      expect(rig.shared.single.fileNameOverrides, <String>[
        'yonetmelik-v1.pdf',
      ]);
    });

    testWidgets(
      'indirme hatası: ileti pencerede, Tekrar Dene (odakta) başarılı olunca paylaşır',
      (t) async {
        final rig = _Rig();
        await rig.loaded(t);
        rig.service.downloadError = ApiException(
          'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.',
          statusCode: 500,
          code: 'DOCUMENT_FILE_MISSING',
        );
        await _tap(t, 'document_detail_open');
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Belge indirilemedi'), findsOneWidget);
        expect(
          find.text(
            'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.',
          ),
          findsOneWidget,
        );
        expect(rig.shared, isEmpty);
        final retry = t.widget<ElevatedButton>(_key('document_download_retry'));
        expect(
          retry.autofocus,
          isTrue,
          reason: 'hata sonrası odak yeniden-deneme düğmesine',
        );

        rig.service.downloadError = null;
        await _tap(t, 'document_download_retry');
        await settleFor(t);
        await settleFor(t);
        expect(rig.shared, hasLength(1));
        expect(rig.service.downloadCalls, hasLength(2));
      },
    );

    testWidgets('Vazgeç: indirme iptal edilir, paylaşım menüsü AÇILMAZ', (
      t,
    ) async {
      final rig = _Rig();
      await rig.loaded(t);
      final gate = Completer<void>();
      rig.service.downloadGates.add(gate);
      await _tap(t, 'document_detail_open');
      await settleFor(t);
      await _tap(t, 'document_download_cancel');
      gate.complete();
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Belge indiriliyor'), findsNothing);
      expect(rig.shared, isEmpty);
      expect(rig.closed, isFalse, reason: 'ayrıntı penceresi açık kalır');
    });

    testWidgets(
      'indirme sürerken ayrıntı penceresi eylemleri kilitlidir (çift dokunuş)',
      (t) async {
        final rig = _Rig();
        await rig.loaded(t);
        final gate = Completer<void>();
        rig.service.downloadGates.add(gate);
        await _tap(t, 'document_detail_open');
        await settleFor(t);
        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.downloadCalls, hasLength(1));
      },
    );
  });

  group('silme', () {
    testWidgets(
      'onaylı yumuşak silme: pencere mesajla kapanır, liste tazelenir',
      (t) async {
        final rig = _Rig();
        await rig.loaded(t);
        await _tap(t, 'document_detail_delete');
        await settleFor(t);
        expect(find.text('Belge silinsin mi?'), findsOneWidget);
        await _tap(t, 'document_confirm_ok');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.deleteCalls.single, (id: 41, confirm: false));
        expect(rig.service.docs[41]!.status, 'deleted');
        expect(rig.closed, isTrue);
        expect(
          rig.message,
          'Belge silindi. Silinenler listesinden geri yükleyebilirsiniz.',
        );
        expect(rig.changed, greaterThanOrEqualTo(1));
      },
    );

    testWidgets('onay penceresinde Vazgeç: hiçbir istek yapılmaz', (t) async {
      final rig = _Rig();
      await rig.loaded(t);
      await _tap(t, 'document_detail_delete');
      await settleFor(t);
      await _tap(t, 'document_confirm_cancel');
      await settleFor(t);
      expect(rig.service.deleteCalls, isEmpty);
      expect(rig.closed, isFalse);
    });

    testWidgets(
      'yayındaki duyuruya ekli (DOCUMENT_IN_USE): ikinci açık onay, sonra confirm:true',
      (t) async {
        final rig = _Rig();
        rig.service.inUseAttachments = 2;
        await rig.loaded(t);
        await _tap(t, 'document_detail_delete');
        await settleFor(t);
        await _tap(t, 'document_confirm_ok');
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Belge duyurularda kullanılıyor'), findsOneWidget);
        expect(find.textContaining('2 yayındaki duyuruya'), findsOneWidget);
        expect(
          rig.service.docs[41]!.status,
          'active',
          reason: 'ikinci onaydan önce silinmedi',
        );

        await _tap(t, 'document_confirm_ok');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.deleteCalls, [
          (id: 41, confirm: false),
          (id: 41, confirm: true),
        ]);
        expect(rig.service.docs[41]!.status, 'deleted');
        expect(rig.message, contains('duyurularda artık kullanılamıyor'));
      },
    );

    testWidgets('ikinci onayda vazgeçilirse belge silinmez', (t) async {
      final rig = _Rig();
      rig.service.inUseAttachments = 1;
      await rig.loaded(t);
      await _tap(t, 'document_detail_delete');
      await settleFor(t);
      await _tap(t, 'document_confirm_ok');
      await settleFor(t);
      await settleFor(t);
      await _tap(t, 'document_confirm_cancel');
      await settleFor(t);
      expect(rig.service.deleteCalls, hasLength(1));
      expect(rig.service.docs[41]!.status, 'active');
      expect(rig.closed, isFalse);
      expect(
        find.byType(InlineNotice),
        findsNothing,
        reason: 'vazgeçmek hata değildir',
      );
    });

    testWidgets(
      'silme hatası pencerede kalır (odak ve ileti); belge listede kalır',
      (t) async {
        final rig = _Rig();
        rig.service.writeError = ApiException(
          'Sunucu meşgul. Biraz sonra tekrar deneyin.',
          statusCode: 503,
          code: 'UPLOAD_BUSY',
        );
        await rig.loaded(t);
        await _tap(t, 'document_detail_delete');
        await settleFor(t);
        await _tap(t, 'document_confirm_ok');
        await settleFor(t);
        await settleFor(t);
        expect(
          find.text('Sunucu meşgul. Biraz sonra tekrar deneyin.'),
          findsOneWidget,
        );
        expect(rig.closed, isFalse);
        // Sonra tekrar dener.
        rig.service.writeError = null;
        await _tap(t, 'document_detail_delete');
        await settleFor(t);
        await _tap(t, 'document_confirm_ok');
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
      },
    );

    testWidgets('çift dokunuş: yazma sürerken ikinci istek gitmez', (t) async {
      final rig = _Rig();
      await rig.loaded(t);
      final gate = Completer<void>();
      rig.service.writeGates.add(gate);
      await _tap(t, 'document_detail_delete');
      await settleFor(t);
      await _tap(t, 'document_confirm_ok');
      await settleFor(t);
      // Silme sürerken tüm eylemler kilitli.
      final deleteButton = find.byKey(
        const ValueKey<String>('document_detail_delete'),
      );
      await t.tap(deleteButton, warnIfMissed: false);
      await t.pump();
      gate.complete();
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.deleteCalls, hasLength(1));
    });
  });

  group('çöp kutusu', () {
    testWidgets('geri yükleme', (t) async {
      final rig = _Rig(id: 38);
      await rig.loaded(t);
      await _tap(t, 'document_detail_restore');
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.restoreCalls, <int>[38]);
      expect(rig.service.docs[38]!.status, 'active');
      expect(rig.message, 'Belge geri yüklendi.');
      expect(rig.closed, isTrue);
    });

    testWidgets('kalıcı silme onay ister ve belgeyi kaldırır', (t) async {
      final rig = _Rig(id: 38);
      await rig.loaded(t);
      await _tap(t, 'document_detail_purge');
      await settleFor(t);
      expect(find.text('Kalıcı olarak silinsin mi?'), findsOneWidget);
      expect(rig.service.purgeCalls, isEmpty);
      await _tap(t, 'document_confirm_ok');
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.purgeCalls, <int>[38]);
      expect(rig.service.docs.containsKey(38), isFalse);
      expect(rig.message, 'Belge kalıcı olarak silindi.');
    });

    testWidgets(
      'bayat durum (INVALID_STATE): ileti + ayrıntı ve liste tazelenir',
      (t) async {
        final rig = _Rig(id: 38);
        await rig.loaded(t);
        rig.service.docs[38]!.status = 'active'; // başka yerden geri yüklenmiş
        await _tap(t, 'document_detail_restore');
        await settleFor(t);
        await settleFor(t);
        expect(
          find.text(
            'Belgenin durumu değişmiş. Listeyi yenileyip tekrar deneyin.',
          ),
          findsOneWidget,
        );
        expect(rig.changed, greaterThanOrEqualTo(1));
        expect(
          find.text('Yeni Sürüm Yükle'),
          findsOneWidget,
          reason: 'ayrıntı yeniden okundu: artık yayında',
        );
      },
    );
  });

  group('sürümler', () {
    testWidgets(
      'sürüm silme onaylıdır; son kalan sürüm silinemez (düğme yok)',
      (t) async {
        final rig = _Rig();
        await rig.loaded(t);
        await _tap(t, 'document_version_delete_1');
        await settleFor(t);
        expect(find.text('v1 sürümü silinsin mi?'), findsOneWidget);
        await _tap(t, 'document_confirm_ok');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.deleteVersionCalls.single, (id: 41, no: 1));
        expect(find.text('v1 sürümü silindi.'), findsOneWidget);
        expect(
          _key('document_version_delete_2'),
          findsNothing,
          reason: 'tek sürüm kaldı: silinemez',
        );
        expect(_key('document_version_delete_1'), findsNothing);
      },
    );

    testWidgets(
      'yeni sürüm: yükleme penceresi açılır, bitince bildirim ve liste tazelenir',
      (t) async {
        final rig = _Rig(picks: [fakeSource('v3.pdf', size: 1000)]);
        await rig.loaded(t);
        await _tap(t, 'document_detail_new_version');
        await settleFor(t);
        expect(find.text('Yeni Sürüm Yükle'), findsWidgets);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.versionCalls.single.id, 41);
        expect(
          find.text(
            'Yeni sürüm yüklendi. Sakinler artık güncel sürümü indirir.',
          ),
          findsOneWidget,
        );
        expect(rig.changed, greaterThanOrEqualTo(1));
        expect(find.text('v3 (güncel)'), findsOneWidget);
      },
    );
  });

  group('düzenleme', () {
    testWidgets(
      'Düzenle -> başlık değişir -> yalnız değişen alan gider; bildirim ve yenileme',
      (t) async {
        final rig = _Rig();
        await rig.loaded(t);
        await _tap(t, 'document_detail_edit');
        await settleFor(t);
        final field = _key('document_edit_title');
        await t.enterText(field, 'Yeni Yönetmelik');
        await t.pump();
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.updateCalls.single.fields, <String, Object?>{
          'title': 'Yeni Yönetmelik',
        });
        expect(find.text('Belge güncellendi.'), findsOneWidget);
        expect(rig.changed, greaterThanOrEqualTo(1));
      },
    );
  });

  group('erişilebilirlik', () {
    testWidgets('sürüm satırı tek birleşik etiket taşır ("PDF, 2,4 MB")', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final rig = _Rig();
      await rig.loaded(t);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'v2 \(güncel\)\. yonetmelik-v2\.pdf, PDF, 2,4 MB.*Not: Madde 4 düzeltildi',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('yıkıcı eylem düğmeleri en az 48 dp', (t) async {
      final rig = _Rig();
      await rig.loaded(t, width: 320, height: 640, scale: 2.0);
      final delete = t.getSize(_key('document_detail_delete'));
      expect(delete.height, greaterThanOrEqualTo(48));
      final versionDelete = t.getSize(_key('document_version_delete_1'));
      expect(versionDelete.height, greaterThanOrEqualTo(48));
    });
  });
}
