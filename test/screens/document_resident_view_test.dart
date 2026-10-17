// Platform Faz 3b-A: sakin "Belgeler" ekranı (DocumentResidentView).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; açık / koyu), yükleniyor / hata / boş /
// dolu ayrımı (HATA ASLA "belge yok" demez), kategori süzgeci + arama + site süzgeci, imleçli sayfalama,
// "Güncellendi" çipi, Aç / Kaydet (indir -> paylaş), çift dokunma ve ekran okuyucu etiketleri.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart'
    show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/document_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'document_fixtures.dart';
import 'list_fixtures.dart';

class _Rig {
  _Rig(this.service, this.auth)
    : sharer = DocumentFileSharer(
        shareFn: (params) async {
          shared.add(params);
          return const ShareResult('', ShareResultStatus.success);
        },
        cleanupDelay: Duration.zero,
        sweepStaleOnShare: false,
      );

  final FakeDocumentService service;
  final DocumentFakeAuth auth;
  final DocumentFileSharer sharer;
  static final List<ShareParams> shared = <ShareParams>[];
  final GlobalKey<DocumentResidentViewState> key =
      GlobalKey<DocumentResidentViewState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<PeopleSite> sites = const <PeopleSite>[],
  }) async {
    shared.clear();
    await pumpList(
      t,
      DocumentResidentView(
        key: key,
        authService: auth,
        service: service,
        sites: sites,
        sharer: sharer,
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

_Rig _rig({int count = 3}) {
  final auth = DocumentFakeAuth();
  return _Rig(residentDocuments(auth, count: count), auth);
}

Finder _open(int id) => find.byKey(ValueKey<String>('document_open_$id'));

void main() {
  group('taşma matrisi', () {
    listMatrix(
      'dolu liste: kategori çipi, açıklama, "Güncellendi", dosya türü / boyutu, Aç / Kaydet',
      (t, w, h, s, dark) async {
        final rig = _rig();
        await rig.pump(t, width: w, height: h, scale: s, dark: dark);

        expect(find.byType(DocumentResidentCard), findsNWidgets(3));
        final order = [
          for (final card in t.widgetList<DocumentResidentCard>(
            find.byType(DocumentResidentCard),
          ))
            card.document.id,
        ];
        expect(order, <int>[3, 2, 1]);
        expect(find.text('Birinci belgenin açıklaması.'), findsOneWidget);
        expect(
          find.text('Güncellendi'),
          findsOneWidget,
          reason: 'yalnız 2 sürümlü belge',
        );
        expect(
          find.text('PDF, 1,0 MB'),
          findsNWidgets(2),
          reason: 'belge 1 (1 MB) ve belge 2 güncel sürüm (1 MB)',
        );
        expect(find.text('Aç / Kaydet'), findsNWidgets(3));
        expect(find.text('Belge 3'), findsOneWidget);
      },
    );

    listMatrix('boş: gerçekten boşken açıklayıcı durum', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      final rig = _Rig(FakeDocumentService(authService: auth), auth);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);

      expect(find.text('Henüz belge yok.'), findsOneWidget);
      expect(
        find.text('Yönetimin sizinle paylaştığı belgeler burada görünür.'),
        findsOneWidget,
      );
    });

    listMatrix('hata: "belge yok" DENMEZ; Tekrar Dene', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final rig = _rig();
      rig.service.mineError = ApiException(
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);

      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz belge yok.'), findsNothing);
      expect(find.byType(EmptyCard), findsNothing);
    });

    listMatrix('çoklu site: site süzgeci + kartlarda site adı', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final rig = _rig();
      await rig.pump(
        t,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        sites: const <PeopleSite>[
          PeopleSite(code: 11, name: 'Gül Sitesi'),
          PeopleSite(code: 12, name: 'Mavi Park'),
        ],
      );
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(
        find.text('Gül Sitesi'),
        findsNWidgets(3),
        reason: 'üç kartta site adı',
      );
    });
  });

  group('yatay telefon (640x360 x2,0)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets('dolu liste taşmaz (${dark ? 'koyu' : 'açık'})', (t) async {
        final rig = _rig();
        await rig.pump(t, width: 640, height: 360, scale: 2.0, dark: dark);
        expect(find.byType(DocumentResidentCard), findsNWidgets(3));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('yükleme ve süzgeç', () {
    testWidgets('ilk yükleme sürerken iskelet; boş durum çizilmez', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.listGates.add(gate);
      await rig.pump(t);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz belge yok.'), findsNothing);
      gate.complete();
      await settleFor(t);
      expect(find.byType(DocumentResidentCard), findsNWidgets(3));
    });

    testWidgets('Tekrar Dene listeyi getirir', (t) async {
      final rig = _rig();
      rig.service.mineError = ApiException('Bağlantı koptu.');
      await rig.pump(t);
      rig.service.mineError = null;
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byType(DocumentResidentCard), findsNWidgets(3));
    });

    testWidgets(
      'kategori süzgeci sunucuya gider; süzgeçli boş sonuç farklı ileti verir',
      (t) async {
        final rig = _rig(count: 2);
        await rig.pump(t);
        await tapFinder(
          t,
          find.byKey(const ValueKey<String>('document_category_contract')),
        );
        await settleFor(t);
        expect(rig.service.mineCalls.last.category, 'contract');
        expect(
          find.text('Bu arama ve süzgeç için belge bulunamadı.'),
          findsOneWidget,
        );
        expect(find.text('Henüz belge yok.'), findsNothing);
        await tapFinder(
          t,
          find.byKey(const ValueKey<String>('document_category_notice')),
        );
        await settleFor(t);
        expect(find.byType(DocumentResidentCard), findsOneWidget);
        expect(find.text('Belge 2'), findsOneWidget);
      },
    );

    testWidgets('arama: 350 ms duraksama; art arda yazılan tek istek', (
      t,
    ) async {
      final rig = _rig();
      await rig.pump(t);
      final before = rig.service.mineCalls.length;
      final field = find.byKey(const ValueKey<String>('documents_search'));
      await t.enterText(field, 'Bel');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(field, 'Belge 2');
      expect(rig.service.mineCalls.length, before);
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t);
      expect(rig.service.mineCalls.length, before + 1);
      expect(rig.service.mineCalls.last.query, 'Belge 2');
      expect(find.byType(DocumentResidentCard), findsOneWidget);
    });

    testWidgets(
      'imleçli sayfalama: before_id ile sonraki sayfa; yinelenen kayıt eklenmez',
      (t) async {
        final rig = _rig(count: 35);
        await rig.pump(t, height: 12000);
        expect(find.byType(DocumentResidentCard), findsNWidgets(30));
        expect(find.text('Daha fazla yükle'), findsOneWidget);
        await tapFinder(t, find.text('Daha fazla yükle'));
        await settleFor(t);
        expect(find.byType(DocumentResidentCard), findsNWidgets(35));
        expect(
          rig.service.mineCalls.last.before,
          6,
          reason: 'önceki sayfanın son id\'si (id DESC imleci)',
        );
        expect(find.text('Daha fazla yükle'), findsNothing);
      },
    );

    testWidgets('site süzgeci site_code gönderir ve listeyi sıfırlar', (
      t,
    ) async {
      final rig = _rig();
      rig.service.docs[1]!.siteCode = 12;
      await rig.pump(
        t,
        sites: const <PeopleSite>[
          PeopleSite(code: 11, name: 'Gül Sitesi'),
          PeopleSite(code: 12, name: 'Mavi Park'),
        ],
      );
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park').last);
      await settleFor(t);
      expect(rig.service.mineCalls.last.site, 12);
      expect(find.byType(DocumentResidentCard), findsOneWidget);
    });
  });

  group('Aç / Kaydet', () {
    testWidgets(
      'indirir ve paylaşım menüsüne verir; düğme indirme sürerken kapalı',
      (t) async {
        final rig = _rig();
        await rig.pump(t);
        final gate = Completer<void>();
        rig.service.downloadGates.add(gate);
        await tapFinder(t, _open(2));
        await settleFor(t);
        expect(find.text('Belge indiriliyor'), findsOneWidget);
        expect(find.text('Belge 2'), findsWidgets);
        expect(_Rig.shared, isEmpty);
        // Arkadaki kartın düğmesi yükleniyor durumunda.
        final button = t.widget<PrimaryActionButton>(_open(2));
        expect(button.loading, isTrue);

        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.mineDownloadCalls, <int>[2]);
        expect(_Rig.shared, hasLength(1));
        expect(_Rig.shared.single.fileNameOverrides, <String>[
          'belge-2-v2.pdf',
        ]);
        expect(t.widget<PrimaryActionButton>(_open(2)).loading, isFalse);
      },
    );

    testWidgets(
      'indirme hatası: pencerede Türkçe ileti + Tekrar Dene; paylaşım yok',
      (t) async {
        final rig = _rig();
        await rig.pump(t);
        rig.service.downloadError = ApiException(
          'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.',
          statusCode: 500,
          code: 'DOCUMENT_FILE_MISSING',
        );
        await tapFinder(t, _open(1));
        await settleFor(t);
        await settleFor(t);
        expect(
          find.text(
            'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.',
          ),
          findsOneWidget,
        );
        expect(_Rig.shared, isEmpty);
        await tapFinder(
          t,
          find.byKey(const ValueKey<String>('document_download_cancel')),
        );
        await settleFor(t);
        expect(find.text('Belge indirilemedi'), findsNothing);
      },
    );

    testWidgets('belge bu arada kaldırıldı (404): ileti + liste yenilenir', (
      t,
    ) async {
      final rig = _rig();
      await rig.pump(t);
      final before = rig.service.mineCalls.length;
      rig.service.docs.remove(3);
      await tapFinder(t, _open(3));
      await settleFor(t);
      await settleFor(t);
      expect(
        find.text('Belge bulunamadı ya da erişiminiz yok.'),
        findsOneWidget,
      );
      await tapFinder(
        t,
        find.byKey(const ValueKey<String>('document_download_cancel')),
      );
      await settleFor(t);
      expect(
        rig.service.mineCalls.length,
        greaterThan(before),
        reason: 'liste güncel hâle geldi',
      );
      expect(find.text('Belge 3'), findsNothing);
    });

    testWidgets('Vazgeç: paylaşım menüsü açılmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final gate = Completer<void>();
      rig.service.downloadGates.add(gate);
      await tapFinder(t, _open(1));
      await settleFor(t);
      await tapFinder(
        t,
        find.byKey(const ValueKey<String>('document_download_cancel')),
      );
      gate.complete();
      await settleFor(t);
      await settleFor(t);
      expect(_Rig.shared, isEmpty);
      expect(t.widget<PrimaryActionButton>(_open(1)).loading, isFalse);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('kart tek birleşik etiket taşır ("PDF, 1,0 MB", Güncellendi)', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final rig = _rig();
      await rig.pump(t);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Belge: Belge 2\. Bilgilendirme\. Güncellendi\. PDF, 1,0 MB\.',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Aç / Kaydet düğmesi 48 dp ve etiketi var (320x640 x2,0)', (
      t,
    ) async {
      final rig = _rig();
      await rig.pump(t, width: 320, height: 640, scale: 2.0);
      expect(t.getSize(_open(1)).height, greaterThanOrEqualTo(48));
      expect(find.text('Aç / Kaydet'), findsWidgets);
    });
  });
}
