// Platform Faz 3b-A: belge indirme ilerleme penceresi (DocumentDownloadDialog / showDocumentDownload).
// Taşma matrisi, ilerleme metni, geri tuşu = iptal, hata + Tekrar Dene (odak), bilinmeyen hata Türkçe.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_download_dialog.dart';

import 'dialog_layout_harness.dart';
import 'list_fixtures.dart' show tapFinder;

class _Rig {
  final List<Completer<void>> gates = <Completer<void>>[];
  Object? error;
  int calls = 0;
  int? total = 1000;
  bool cancelSeen = false;
  DownloadedDocument? result;
  bool closed = false;
  DocumentCancelToken? token;
  int progressStep = 400;

  Future<DownloadedDocument> download(
    void Function(int received, int? total) onProgress,
    DocumentCancelToken cancel,
  ) async {
    calls++;
    token = cancel;
    onProgress(progressStep, total);
    if (gates.isNotEmpty) {
      final gate = gates.removeAt(0);
      await gate.future;
    }
    if (cancel.isCancelled) {
      cancelSeen = true;
      throw const DocumentTransferCancelled();
    }
    final failure = error;
    if (failure != null) throw failure;
    return const DownloadedDocument(
      fileName: 'a.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1000,
    );
  }

  Future<void> open(
    WidgetTester t, {
    double width = 400,
    double height = 800,
    double scale = 1.0,
    bool dark = false,
  }) {
    return openDialogAt(
      t,
      (context) async {
        result = await showDocumentDownload(
          context,
          title: 'Site Yönetmeliği',
          download: download,
        );
        closed = true;
      },
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
  }
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  group('yatay telefon (640x360 x2,0)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'ilerleme ve hata görünümü taşmaz (${dark ? 'koyu' : 'açık'})',
        (t) async {
          final rig = _Rig()..gates.add(Completer<void>());
          await rig.open(t, width: 640, height: 360, scale: 2.0, dark: dark);
          await settleFor(t);
          expect(find.text('Vazgeç'), findsOneWidget);
          expect(t.takeException(), isNull);
          final failing = _Rig()..error = ApiException('Bağlantı koptu.');
          await failing.open(
            t,
            width: 640,
            height: 360,
            scale: 2.0,
            dark: dark,
          );
          await settleFor(t);
          await settleFor(t);
          expect(find.text('Tekrar Dene'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  });

  group('taşma matrisi', () {
    layoutMatrix('ilerleme: yüzde, boyut ve Vazgeç', (t, w, h, s, dark) async {
      final rig = _Rig()..gates.add(Completer<void>());
      await rig.open(t, width: w, height: h, scale: s, dark: dark);
      await settleFor(t);
      expect(find.text('Belge indiriliyor'), findsOneWidget);
      expect(find.text('Site Yönetmeliği'), findsOneWidget);
      expect(find.text('%40 · 400 B / 1000 B'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsNothing);
    });

    layoutMatrix('hata: Türkçe ileti, Tekrar Dene ve Kapat', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final rig = _Rig()
        ..error = ApiException(
          'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.',
          statusCode: 500,
        );
      await rig.open(t, width: w, height: h, scale: s, dark: dark);
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Belge indirilemedi'), findsOneWidget);
      expect(
        find.text('Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.'),
        findsOneWidget,
      );
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Kapat'), findsOneWidget);
    });
  });

  group('akış', () {
    testWidgets(
      'toplam bilinmiyorsa "Hazırlanıyor..." / alınan boyut; çubuk belirsiz',
      (t) async {
        final rig = _Rig()
          ..total = null
          ..progressStep = 0
          ..gates.add(Completer<void>());
        await rig.open(t);
        await settleFor(t);
        expect(find.text('Hazırlanıyor...'), findsOneWidget);
        expect(
          t
              .widget<LinearProgressIndicator>(
                _key('document_download_progress'),
              )
              .value,
          isNull,
        );
      },
    );

    testWidgets('tamamlanınca pencere belgeyle kapanır', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await settleFor(t);
      await settleFor(t);
      expect(rig.closed, isTrue);
      expect(rig.result?.fileName, 'a.pdf');
      expect(find.text('Belge indiriliyor'), findsNothing);
    });

    testWidgets(
      'geri tuşu = iptal: belirteç iptal edilir, pencere null ile kapanır',
      (t) async {
        final gate = Completer<void>();
        final rig = _Rig()..gates.add(gate);
        await rig.open(t);
        await settleFor(t);
        await t.binding.handlePopRoute();
        expect(rig.token!.isCancelled, isTrue);
        expect(
          rig.closed,
          isFalse,
          reason: 'indirme iptali fark edilene dek pencere açık',
        );
        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.result, isNull);
      },
    );

    testWidgets('Vazgeç: iptal edilir ve pencere null ile kapanır', (t) async {
      final gate = Completer<void>();
      final rig = _Rig()..gates.add(gate);
      await rig.open(t);
      await settleFor(t);
      await tapFinder(t, _key('document_download_cancel'));
      gate.complete();
      await settleFor(t);
      await settleFor(t);
      expect(rig.cancelSeen, isTrue);
      expect(rig.closed, isTrue);
      expect(rig.result, isNull);
    });

    testWidgets(
      'hata -> Tekrar Dene (odakta) -> başarı: aynı pencere belgeyle kapanır',
      (t) async {
        final rig = _Rig()..error = ApiException('Bağlantı koptu.');
        await rig.open(t);
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Bağlantı koptu.'), findsOneWidget);
        expect(
          t.widget<ElevatedButton>(_key('document_download_retry')).autofocus,
          isTrue,
        );
        rig.error = null;
        await tapFinder(t, _key('document_download_retry'));
        await settleFor(t);
        await settleFor(t);
        expect(rig.calls, 2);
        expect(rig.closed, isTrue);
        expect(rig.result, isNotNull);
      },
    );

    testWidgets('hata sonrası Kapat: null döner', (t) async {
      final rig = _Rig()..error = ApiException('Bağlantı koptu.');
      await rig.open(t);
      await settleFor(t);
      await settleFor(t);
      await tapFinder(t, _key('document_download_cancel'));
      await settleFor(t);
      expect(rig.closed, isTrue);
      expect(rig.result, isNull);
    });

    testWidgets('bilinmeyen hata türü: genel Türkçe ileti, jargon yok', (
      t,
    ) async {
      final rig = _Rig()..error = StateError('iç');
      await rig.open(t);
      await settleFor(t);
      await settleFor(t);
      expect(
        find.textContaining('Belge indirilemedi. İnternet bağlantınızı'),
        findsOneWidget,
      );
      expect(find.textContaining('StateError'), findsNothing);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('ilerleme çubuğu yüzdeyi söyler', (t) async {
      final handle = t.ensureSemantics();
      final rig = _Rig()..gates.add(Completer<void>());
      await rig.open(t);
      await settleFor(t);
      expect(find.bySemanticsLabel('İndiriliyor, yüzde 40'), findsOneWidget);
      handle.dispose();
    });
  });
}
