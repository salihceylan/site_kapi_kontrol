// Platform Faz 3b-A: "Belge Yükle" / "Yeni Sürüm Yükle" penceresi (DocumentUploadDialog).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; açık / koyu), form doğrulamaları
// (kitle seçilmeden gönderilemez, dosya / boyut / uzantı ön denetimi), iki adımlı akış (ilerleme çubuğu, iptal,
// hata + yeniden deneme, bilet yeniden kullanımı), çift gönderim, kaydedilmemiş form koruması, klavye ve ekran
// okuyucu. Sunucu esastır: ön doğrulama yalnız uyarır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_upload_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'document_fixtures.dart';
import 'list_fixtures.dart' show tapFinder;

const String _kvkk =
    'Belgede kişisel veri (T.C. kimlik no, IBAN, telefon, adres) varsa yalnız ilgili kitleye açın; gereksiz veriyi karartın.';

class _Rig {
  _Rig({
    this.versionOf,
    this.usage,
    this.initial,
    List<DocumentUploadSource?> picks = const <DocumentUploadSource?>[],
  }) : auth = DocumentFakeAuth(),
       picker = FakeDocumentPicker(picks);

  final DocumentFakeAuth auth;
  late final FakeDocumentService service = FakeDocumentService(
    authService: auth,
  );
  final FakeDocumentPicker picker;
  final DocumentSummary? versionOf;
  final DocumentUsage? usage;
  final DocumentUploadSource? initial;
  DocumentSummary? result;
  bool closed = false;
  int refreshCalls = 0;

  PeopleScope get scope => PeopleScope(
    authService: auth,
    siteCode: 11,
    siteName: 'Gül Sitesi',
    canWrite: true,
  );

  Future<void> open(
    WidgetTester t, {
    double width = 400,
    double height = 1200,
    double scale = 1.0,
    bool dark = false,
  }) {
    return openDialogAt(
      t,
      (context) async {
        result = await DocumentUploadDialog.show(
          context,
          scope: scope,
          service: service,
          picker: picker,
          usage: usage,
          versionOf: versionOf,
          initialSource: initial,
          onRefreshNeeded: () => refreshCalls++,
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

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = _key(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _tap(WidgetTester t, String key) async {
  await tapFinder(t, _key(key));
}

/// Formu doldurur: dosya seç, başlık, kitle (Yalnız yöneticiler) — gönderime hazır.
Future<void> _fill(
  WidgetTester t,
  _Rig rig, {
  String title = 'Site Yönetmeliği',
}) async {
  await _tap(t, 'document_upload_pick');
  await settleFor(t);
  await _type(t, 'document_upload_title', title);
  await _tap(t, 'document_upload_audience_managers');
}

void main() {
  group('eklenti önbelleği temizliği (seçici release, R12 P1-2)', () {
    testWidgets(
      'başarılı yüklemeden sonra seçici kopyaları BİR kez temizlenir',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        expect(rig.picker.releaseCalls, 0, reason: 'dosya hâlâ lazım');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(
          rig.picker.releaseCalls,
          1,
          reason: 'done + dispose tek temizlik',
        );
      },
    );

    testWidgets(
      'hata sonrası yeniden denenebilirken temizlenmez; pencere kapanınca temizlenir',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        rig.service.uploadError = ApiException('Bağlantı koptu.');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        expect(
          rig.picker.releaseCalls,
          0,
          reason: 'Tekrar Dene aynı dosyayı yeniden okuyacak',
        );
        await _tap(t, 'document_upload_close');
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.picker.releaseCalls, 1);
      },
    );

    testWidgets(
      'dosya seçilip form kapatılırsa (yükleme hiç başlamadı) kopya temizlenir',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        await _tap(t, 'document_upload_close');
        await settleFor(t);
        await _tap(t, 'document_discard_confirm');
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.picker.releaseCalls, 1);
      },
    );

    testWidgets(
      'onay penceresinde "Düzenlemeye Dön" denince (dosya hâlâ lazım) temizlenmez',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        await _tap(t, 'document_upload_close');
        await settleFor(t);
        await _tap(t, 'document_discard_keep');
        await settleFor(t);
        expect(rig.closed, isFalse);
        expect(rig.picker.releaseCalls, 0);
      },
    );
  });

  group('geç iptal: gövde gitti, sunucu kaydediyor (%100)', () {
    Future<(_Rig, Completer<void>)> toFinishing(
      WidgetTester t, {
      double width = 400,
      double height = 1200,
      double scale = 1.0,
      bool dark = false,
    }) async {
      final rig = _Rig(picks: [fakeSource('a.pdf', size: 4000)]);
      await rig.open(t, width: width, height: height, scale: scale, dark: dark);
      await _fill(t, rig);
      final gate = Completer<void>();
      rig.service.uploadFinalGates.add(gate);
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      await settleFor(t);
      return (rig, gate);
    }

    testWidgets('finishing aşamasında not DÜRÜSTTÜR: Vazgeç kaydı geri almaz', (
      t,
    ) async {
      final (rig, gate) = await toFinishing(t);
      expect(
        find.text('Dosya gönderildi, sunucu kaydediyor...'),
        findsOneWidget,
      );
      expect(_key('document_upload_progress_note'), findsOneWidget);
      expect(
        find.textContaining(
          'Bu aşamada Vazgeçerseniz belge yine de kaydedilmiş olabilir',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('istediğiniz an iptal'), findsNothing);
      expect(_key('document_upload_cancel'), findsOneWidget);
      expect(rig.closed, isFalse);
    });

    testWidgets(
      'yükleme sürerken (%100 öncesi) not iptali vaat eder; geç uyarı yok',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf', size: 4000)]);
        await rig.open(t);
        await _fill(t, rig);
        final hold = Completer<void>();
        rig.service.uploadGates
          ..add(Completer<void>()..complete())
          ..add(hold);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(
          find.textContaining('Vazgeç ile gönderimi durdurabilirsiniz'),
          findsOneWidget,
        );
        expect(
          find.textContaining('yine de kaydedilmiş olabilir'),
          findsNothing,
        );
        hold.complete();
        await settleFor(t);
        await settleFor(t);
      },
    );

    testWidgets(
      'geç iptal: "iptal edildi" DEĞİL, sonuç belirsiz uyarısı; liste tazelenir; Yüklemeyi Sürdür tek belge bırakır',
      (t) async {
        final (rig, gate) = await toFinishing(t);
        rig.service.serverCompletesOnLateCancel =
            true; // sunucu isteği yine de işledi
        await _tap(t, 'document_upload_cancel');
        gate.complete();
        await settleFor(t);
        await settleFor(t);

        expect(_key('document_upload_cancelled_late'), findsOneWidget);
        expect(_key('document_upload_cancelled'), findsNothing);
        expect(
          find.textContaining('sunucu belgeyi kaydetmiş olabilir'),
          findsOneWidget,
        );
        expect(find.text('Yükleme iptal edildi.'), findsNothing);
        expect(
          rig.refreshCalls,
          greaterThanOrEqualTo(1),
          reason: 'liste tazelenir',
        );
        expect(rig.closed, isFalse);
        expect(find.text('Yüklemeyi Sürdür'), findsOneWidget);
        expect(
          t
              .widget<ElevatedButton>(_key('document_upload_submit'))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        // Sunucuda belge gerçekten kaydedilmiş.
        expect(rig.service.docs.values.single.status, 'active');

        // Sürdür: sunucu "zaten tamamlandı" der; istemci başarı sayar, ÇİFT sürüm / belge yok.
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.service.createCalls, hasLength(1));
        expect(rig.service.docs, hasLength(1));
        expect(rig.service.docs.values.single.versions, hasLength(1));
        expect(rig.result?.id, rig.service.docs.keys.single);
      },
    );

    testWidgets(
      'geç iptal ama sunucu işlemedi: Yüklemeyi Sürdür belgeyi tamamlar',
      (t) async {
        final (rig, gate) = await toFinishing(t);
        await _tap(t, 'document_upload_cancel');
        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(_key('document_upload_cancelled_late'), findsOneWidget);
        expect(rig.service.docs.values.single.status, 'pending');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.service.docs.values.single.status, 'active');
        expect(rig.service.createCalls, hasLength(1));
      },
    );

    for (final cell in const <(double, double, double)>[
      (320, 640, 2.0),
      (640, 360, 2.0),
    ]) {
      testWidgets(
        'finishing paneli ve geç iptal uyarısı taşmaz (${cell.$1.toInt()}x${cell.$2.toInt()} x${cell.$3})',
        (t) async {
          final (rig, gate) = await toFinishing(
            t,
            width: cell.$1,
            height: cell.$2,
            scale: cell.$3,
          );
          expect(t.takeException(), isNull);
          await _tap(t, 'document_upload_cancel');
          gate.complete();
          await settleFor(t);
          await settleFor(t);
          expect(_key('document_upload_cancelled_late'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  });

  group('taşma matrisi (form)', () {
    layoutMatrix(
      'boş form: dosya, başlık, kategori, kitle (seçili değil), KVKK kutusu',
      (t, w, h, s, dark) async {
        final rig = _Rig();
        await rig.open(t, width: w, height: h, scale: s, dark: dark);

        expect(find.text('Belge Yükle'), findsWidgets);
        expect(_key('document_upload_pick'), findsOneWidget);
        expect(find.text('Başlık'), findsOneWidget);
        expect(find.text('Kimler görebilir?'), findsOneWidget);
        for (final audience in const ['residents', 'board', 'managers']) {
          expect(_key('document_upload_audience_$audience'), findsOneWidget);
        }
        expect(
          find.text(_kvkk),
          findsOneWidget,
          reason: 'KVKK bilgilendirmesi ZORUNLU gösterilir',
        );
        expect(find.text('Yükle'), findsOneWidget);
        expect(find.text('Vazgeç'), findsOneWidget);
        expect(find.text('PDF, JPG, PNG, DOCX veya XLSX'), findsOneWidget);
      },
    );

    layoutMatrix(
      'doldurulmuş form: sakin kitlesi + bloklar hedefi + seçili dosya',
      (t, w, h, s, dark) async {
        final rig = _Rig(
          picks: [
            fakeSource(
              'Çok Uzun Adlı Site Yönetmeliği Son Hâli Düzeltilmiş.pdf',
            ),
          ],
        );
        await rig.open(t, width: w, height: h, scale: s, dark: dark);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        await _tap(t, 'document_upload_audience_residents');
        await tapFinder(t, _key('document_target_blocks'));

        expect(_key('document_upload_file'), findsOneWidget);
        expect(_key('document_add_block'), findsOneWidget);
        expect(find.text('Tüm site'), findsOneWidget);
        expect(find.text('Bloklar'), findsOneWidget);
        expect(find.text('Daireler'), findsOneWidget);
      },
    );
  });

  group('yatay telefon (640x360 x2,0)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets('form + ilerleme paneli taşmaz (${dark ? 'koyu' : 'açık'})', (
        t,
      ) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t, width: 640, height: 360, scale: 2.0, dark: dark);
        await _fill(t, rig);
        final gate = Completer<void>();
        rig.service.uploadGates.add(gate);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(_key('document_upload_progress_panel'), findsOneWidget);
        expect(t.takeException(), isNull);
        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
      });
    }
  });

  group('doğrulamalar', () {
    testWidgets(
      'boş gönderim: dosya, başlık ve kitle hataları; sunucuya gidilmez',
      (t) async {
        final rig = _Rig();
        await rig.open(t);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);

        expect(find.text('Yüklenecek dosyayı seçin.'), findsOneWidget);
        expect(find.text('Başlık boş olamaz.'), findsOneWidget);
        expect(
          find.text('Belgeyi kimlerin görebileceğini seçin.'),
          findsOneWidget,
        );
        expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
        expect(rig.service.createCalls, isEmpty);
        expect(rig.closed, isFalse);
      },
    );

    testWidgets(
      'kitle seçilmeden gönderilemez (dosya ve başlık tamam olsa da)',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        await _type(t, 'document_upload_title', 'Tutanak');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(
          find.text('Belgeyi kimlerin görebileceğini seçin.'),
          findsOneWidget,
        );
        expect(rig.service.createCalls, isEmpty);

        await _tap(t, 'document_upload_audience_board');
        expect(
          find.text('Belgeyi kimlerin görebileceğini seçin.'),
          findsNothing,
          reason: 'seçince hata kalkar',
        );
      },
    );

    testWidgets(
      'sakin kitlesi + Bloklar/Daireler hedefi: en az bir öğe seçilmeli',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        await _type(t, 'document_upload_title', 'Duyuru');
        await _tap(t, 'document_upload_audience_residents');
        await tapFinder(t, _key('document_target_blocks'));
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(find.text('En az bir blok seçin.'), findsOneWidget);
        expect(rig.service.createCalls, isEmpty);

        await tapFinder(t, _key('document_target_apartments'));
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(find.text('En az bir daire seçin.'), findsOneWidget);
      },
    );

    testWidgets('desteklenmeyen uzantı (.exe) seçilemez; ileti Türkçe', (
      t,
    ) async {
      final rig = _Rig(picks: [fakeSource('virus.exe')]);
      await rig.open(t);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      expect(_key('document_upload_file'), findsNothing);
      expect(
        find.text(
          'Bu dosya türü desteklenmiyor. PDF, JPG, PNG, DOCX veya XLSX yükleyin.',
        ),
        findsOneWidget,
      );
      expect(
        _key('document_upload_pick'),
        findsOneWidget,
        reason: 'seçim geri alınır, yeniden seçilebilir',
      );
    });

    testWidgets('boş dosya seçilemez', (t) async {
      final rig = _Rig(picks: [fakeSource('bos.pdf', size: 0)]);
      await rig.open(t);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      expect(find.textContaining('Seçilen dosya boş'), findsOneWidget);
    });

    testWidgets(
      'öğrenilmiş boyut sınırı aşılırsa ön uyarı (sunucu yine esastır)',
      (t) async {
        final rig = _Rig(
          picks: [fakeSource('buyuk.pdf', size: 11 * 1024 * 1024)],
        );
        rig.service.learnedMaxFileBytes = 10 * 1024 * 1024;
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        expect(
          find.text(
            'Dosya çok büyük (11 MB). En fazla 10 MB yükleyebilirsiniz.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'sınır bilinmiyorsa ipucunda sayı UYDURULMAZ; kalan alan kotadan gelir',
      (t) async {
        final rig = _Rig(
          usage: const DocumentUsage(
            usedBytes: 100 * 1024 * 1024,
            quotaBytes: 200 * 1024 * 1024,
          ),
        );
        await rig.open(t);
        expect(
          find.text('PDF, JPG, PNG, DOCX veya XLSX · kalan alan 100 MB'),
          findsOneWidget,
        );
        expect(find.textContaining('en çok'), findsNothing);
      },
    );

    testWidgets(
      'kalan kota yetmiyorsa YUMUŞAK uyarı: dosya yine seçilir, sunucu karar verir',
      (t) async {
        final rig = _Rig(
          usage: const DocumentUsage(
            usedBytes: 199 * 1024 * 1024,
            quotaBytes: 200 * 1024 * 1024,
          ),
          picks: [fakeSource('a.pdf', size: 2 * 1024 * 1024)],
        );
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        expect(_key('document_upload_file_warning'), findsOneWidget);
        expect(
          find.textContaining('Site belge alanı yetmeyebilir'),
          findsOneWidget,
        );
        expect(
          _key('document_upload_file'),
          findsOneWidget,
          reason: 'bayat kullanım dosyayı reddettirmez',
        );
        expect(_key('document_upload_file_error'), findsNothing);
        await _type(t, 'document_upload_title', 'Büyük belge');
        await _tap(t, 'document_upload_audience_managers');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        expect(
          rig.service.createCalls,
          hasLength(1),
          reason: 'sunucuya gidilir',
        );
      },
    );

    testWidgets('başlık 120 karakteri aşarsa kırpılmaz, hata verir', (t) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      await _type(t, 'document_upload_title', 'x' * 121);
      expect(find.text('Başlık en çok 120 karakter olabilir.'), findsOneWidget);
      await _tap(t, 'document_upload_audience_board');
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets(
      'dosya seçilince başlık dosya adından önerilir (kullanıcı değiştirebilir)',
      (t) async {
        final rig = _Rig(picks: [fakeSource('Site_Yonetmeligi_2026.pdf')]);
        await rig.open(t);
        await _tap(t, 'document_upload_pick');
        await settleFor(t);
        final field = t.widget<TextFormField>(_key('document_upload_title'));
        expect(field.controller!.text, 'Site Yonetmeligi 2026');
      },
    );

    testWidgets(
      'önceden seçilmiş dosya (initialSource) forma alınır ve başlık önerilir',
      (t) async {
        final rig = _Rig(initial: fakeSource('Plan_2026.pdf'));
        await rig.open(t);
        expect(_key('document_upload_file'), findsOneWidget);
        expect(_key('document_upload_pick'), findsNothing);
        expect(
          (t.widget<TextFormField>(
            _key('document_upload_title'),
          )).controller!.text,
          'Plan 2026',
        );
      },
    );

    testWidgets('dosya seçici hata verirse Türkçe ileti (kilitlenmez)', (
      t,
    ) async {
      final rig = _Rig();
      rig.picker.error = StateError('izin yok');
      await rig.open(t);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      expect(find.textContaining('Dosya seçilemedi'), findsOneWidget);
      rig.picker.error = null;
      rig.picker.queue.add(fakeSource('a.pdf'));
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      expect(_key('document_upload_file'), findsOneWidget);
    });
  });

  group('yükleme akışı', () {
    testWidgets(
      'mutlu yol: iki adım, ilerleme, sonuç döner; istek alanları doğru',
      (t) async {
        final rig = _Rig(picks: [fakeSource('yonetmelik.pdf', size: 4096)]);
        await rig.open(t);
        await _fill(t, rig);
        await _tap(t, 'document_upload_category_regulation');
        await _type(t, 'document_upload_description', ' Güncel yönetmelik ');

        final gate = Completer<void>();
        rig.service.uploadGates
          ..add(Completer<void>()..complete())
          ..add(gate); // %25 sonra %50'de bekler
        await _tap(t, 'document_upload_submit');
        await settleFor(t);

        expect(_key('document_upload_progress_panel'), findsOneWidget);
        expect(find.text('%25 · 1,0 KB / 4,0 KB'), findsOneWidget);
        expect(
          find.text('Yükle'),
          findsNothing,
          reason: 'ilerlerken form düğmeleri yok',
        );
        expect(_key('document_upload_cancel'), findsOneWidget);
        expect(rig.service.createCalls, hasLength(1));
        final request = rig.service.createCalls.single;
        expect(request.title, 'Site Yönetmeliği');
        expect(request.category, DocumentCategory.regulation);
        expect(request.audience, DocumentAudience.managers);
        expect(request.target, isNull, reason: 'hedef yalnız sakin kitlesinde');
        expect(request.description, ' Güncel yönetmelik ');
        expect(request.file.name, 'yonetmelik.pdf');
        expect(request.file.size, 4096);
        expect(request.file.contentType, 'application/pdf');
        expect(request.idempotencyKey, startsWith('doc-'));

        gate.complete();
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(
          rig.result?.id,
          request.idempotencyKey.isEmpty ? -1 : rig.service.docs.keys.single,
        );
        expect(rig.service.docs.values.single.status, 'active');
        expect(rig.service.uploadCalls, 1);
      },
    );

    testWidgets('sakin kitlesi blok hedefiyle: istekte target.block_ids', (
      t,
    ) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      await _type(t, 'document_upload_title', 'Blok duyurusu');
      await _tap(t, 'document_upload_audience_residents');
      await tapFinder(t, _key('document_target_blocks'));
      await tapFinder(t, _key('document_add_block'));
      await settleFor(t);
      await tapFinder(t, find.text('A Blok'));
      await settleFor(t);
      expect(
        find.text('A Blok'),
        findsOneWidget,
        reason: 'seçilen blok çip olarak görünür',
      );
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      await settleFor(t);
      final request = rig.service.createCalls.single;
      expect(request.audience, DocumentAudience.residents);
      expect(request.target?.type, DocumentTargetType.blocks);
      expect(request.target?.blockIds, <int>[1]);
    });

    testWidgets('çift dokunuş: tek create, tek yükleme', (t) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t);
      await _fill(t, rig);
      final gate = Completer<void>();
      rig.service.createGates.add(gate);
      final submit = _key('document_upload_submit');
      await t.ensureVisible(submit);
      await t.pump();
      await t.tap(submit);
      await t.pump();
      // Düğme kalktı (ilerleme paneli); ikinci dokunuş mümkün değil, ama doğrudan da denenir.
      expect(submit, findsNothing);
      gate.complete();
      await settleFor(t);
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.createCalls, hasLength(1));
      expect(rig.service.uploadCalls, 1);
    });

    testWidgets(
      'adım 1 sürerken "Sunucu doğruluyor", Vazgeç adım 2 öncesi iptal eder',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        final gate = Completer<void>();
        rig.service.createGates.add(gate);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(find.text('Sunucu dosyayı doğruluyor...'), findsOneWidget);
        await _tap(t, 'document_upload_cancel');
        expect(find.text('İptal ediliyor...'), findsOneWidget);
        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.uploadCalls, 0, reason: 'adım 2 hiç başlamadı');
        expect(_key('document_upload_cancelled'), findsOneWidget);
        expect(rig.closed, isFalse);
      },
    );

    testWidgets(
      'iptal: form korunur, "Yüklemeyi Sürdür" aynı bileti yeniden kullanır',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf', size: 4000)]);
        await rig.open(t);
        await _fill(t, rig);
        final hold = Completer<void>();
        rig.service.uploadGates
          ..add(Completer<void>()..complete())
          ..add(hold);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        expect(find.text('%25 · 1000 B / 3,9 KB'), findsOneWidget);
        await _tap(t, 'document_upload_cancel');
        hold.complete();
        await settleFor(t);
        await settleFor(t);

        expect(_key('document_upload_cancelled'), findsOneWidget);
        expect(
          _key('document_upload_file'),
          findsOneWidget,
          reason: 'seçilen dosya korunur',
        );
        expect(find.text('Site Yönetmeliği'), findsOneWidget);
        expect(find.text('Yüklemeyi Sürdür'), findsOneWidget);

        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(
          rig.service.createCalls,
          hasLength(1),
          reason: 'bilet yeniden kullanıldı, yeni belge oluşmadı',
        );
        expect(rig.service.uploadCalls, 2);
        expect(rig.closed, isTrue);
      },
    );

    testWidgets(
      'iptal sonrası KİTLE değiştirilirse eski bilet atılır: belge ESKİ kitleyle yayınlanmaz',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf', size: 4000)]);
        await rig.open(t);
        await _fill(t, rig); // kitle: yalnız yöneticiler
        final hold = Completer<void>();
        rig.service.uploadGates
          ..add(Completer<void>()..complete())
          ..add(hold);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await _tap(t, 'document_upload_cancel');
        hold.complete();
        await settleFor(t);
        await settleFor(t);
        expect(_key('document_upload_cancelled'), findsOneWidget);

        // Kullanıcı kitleyi sakinlere çevirir ve devam eder.
        await _tap(t, 'document_upload_audience_residents');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(
          rig.service.createCalls,
          hasLength(2),
          reason: 'yeni bilet: yeni kitle',
        );
        expect(
          rig.service.createCalls.last.audience,
          DocumentAudience.residents,
        );
        expect(
          rig.service.createCalls.last.idempotencyKey,
          isNot(rig.service.createCalls.first.idempotencyKey),
          reason:
              'farklı veri farklı anahtar: eski isteğin sonucu yeniyle karışmaz',
        );
        expect(rig.closed, isTrue);
        final published = rig.service.docs.values
            .where((d) => d.status == 'active')
            .single;
        expect(published.audience, 'residents');
      },
    );

    testWidgets(
      'iptal sonrası değişiklik YOKSA aynı bilet sürdürülür (tek create)',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf', size: 4000)]);
        await rig.open(t);
        await _fill(t, rig);
        final hold = Completer<void>();
        rig.service.uploadGates
          ..add(Completer<void>()..complete())
          ..add(hold);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await _tap(t, 'document_upload_cancel');
        hold.complete();
        await settleFor(t);
        await settleFor(t);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.createCalls, hasLength(1));
      },
    );

    testWidgets(
      'yükleme hatası: ileti pencerede, Tekrar Dene aynı bileti kullanır, odak düğmede',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        rig.service.uploadError = ApiException(
          'Yükleme sırasında bağlantı koptu. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);

        expect(
          _key('document_upload_error'),
          findsOneWidget,
          reason: 'hata kutusu (CrmFormError)',
        );
        expect(find.textContaining('bağlantı koptu'), findsOneWidget);
        expect(find.text('Tekrar Dene'), findsOneWidget);
        final focus = (t.widget<ElevatedButton>(
          _key('document_upload_submit'),
        )).focusNode!;
        expect(
          focus.hasFocus,
          isTrue,
          reason: 'hata sonrası odak yeniden-deneme düğmesine gelir',
        );
        expect(rig.closed, isFalse);

        rig.service.uploadError = null;
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(
          rig.service.createCalls,
          hasLength(1),
          reason: 'adım 1 yinelenmedi',
        );
        expect(rig.closed, isTrue);
      },
    );

    testWidgets(
      'sunucu içeriği reddederse (415) ileti gösterilir; başka dosya seçilince yeni bilet alınır',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf'), fakeSource('b.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        rig.service.uploadError = ApiException(
          'Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.',
          statusCode: 415,
          code: 'DOCUMENT_CONTENT_MISMATCH',
        );
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        expect(
          find.text('Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.'),
          findsOneWidget,
        );
        expect(
          find.text('Yükle'),
          findsOneWidget,
          reason: 'içerik reddi yeniden denemeyle düzelmez: normal etiket',
        );

        rig.service.uploadError = null;
        await _tap(t, 'document_upload_change');
        await settleFor(t);
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.service.uploadSizes, hasLength(2));
      },
    );

    testWidgets(
      'adım 1 sonucu belirsiz (500): aynı idempotency_key ile yeniden denenir, liste tazelenir',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        rig.service.createError = ApiException(
          'Sunucu şu anda yanıt veremiyor (500). Lütfen biraz sonra tekrar deneyin.',
          statusCode: 500,
        );
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        expect(find.textContaining('yanıt veremiyor'), findsOneWidget);
        expect(
          rig.refreshCalls,
          1,
          reason: 'belge oluşmuş olabilir: liste tazelenir',
        );
        final firstKey = rig.service.createCalls.single.idempotencyKey;

        rig.service.createError = null;
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.createCalls, hasLength(2));
        expect(
          rig.service.createCalls.last.idempotencyKey,
          firstKey,
          reason: 'çift belge oluşmaz',
        );
        expect(rig.service.docs, hasLength(1));
        expect(rig.closed, isTrue);
      },
    );

    testWidgets('429 hız sınırı: gönder düğmesi geçici kilitlenir', (t) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t);
      await _fill(t, rig);
      rig.service.createError = ApiException(
        'Çok fazla istek gönderildi. 30 saniye sonra tekrar deneyin.',
        statusCode: 429,
        retryAfterSeconds: 30,
      );
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      await settleFor(t);
      expect(find.textContaining('30 saniye sonra'), findsOneWidget);
      expect(
        t.widget<ElevatedButton>(_key('document_upload_submit')).onPressed,
        isNull,
      );
      // Süre dolunca düğme açılır.
      await t.pump(const Duration(seconds: 31));
      expect(
        t.widget<ElevatedButton>(_key('document_upload_submit')).onPressed,
        isNotNull,
      );
    });
  });

  group('kapatma ve kaydedilmemiş durum', () {
    testWidgets('temiz form doğrudan kapanır', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await _tap(t, 'document_upload_close');
      await settleFor(t);
      expect(rig.closed, isTrue);
      expect(rig.result, isNull);
    });

    testWidgets(
      'doldurulmuş form: onay istenir; "Düzenlemeye Dön" korur, "Vazgeç ve Kapat" kapatır',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        await _tap(t, 'document_upload_close');
        await settleFor(t);
        expect(find.text('Yükleme iptal edilsin mi?'), findsOneWidget);
        expect(rig.closed, isFalse);

        await _tap(t, 'document_discard_keep');
        await settleFor(t);
        expect(rig.closed, isFalse);
        expect(
          find.text('Site Yönetmeliği'),
          findsOneWidget,
          reason: 'girilen bilgiler korunur',
        );

        await _tap(t, 'document_upload_close');
        await settleFor(t);
        await _tap(t, 'document_discard_confirm');
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.result, isNull);
      },
    );

    testWidgets('geri tuşu da onay ister (doldurulmuş form)', (t) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t);
      await _fill(t, rig);
      await t.binding.handlePopRoute();
      await settleFor(t);
      expect(find.text('Yükleme iptal edilsin mi?'), findsOneWidget);
      expect(rig.closed, isFalse);
    });

    testWidgets('yükleme sürerken geri tuşu pencereyi kapatmaz; uyarı çıkar', (
      t,
    ) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t);
      await _fill(t, rig);
      final hold = Completer<void>();
      rig.service.uploadGates.add(hold);
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      await t.binding.handlePopRoute();
      await settleFor(t);
      expect(rig.closed, isFalse);
      expect(_key('document_upload_progress_panel'), findsOneWidget);
      expect(find.textContaining('Yükleme sürüyor'), findsWidgets);
      hold.complete();
      await settleFor(t);
      await settleFor(t);
    });

    testWidgets(
      'bilet alınmış ama bitmemiş yükleme kapanınca liste tazelenir',
      (t) async {
        final rig = _Rig(picks: [fakeSource('a.pdf')]);
        await rig.open(t);
        await _fill(t, rig);
        rig.service.uploadError = ApiException('Bağlantı koptu.');
        await _tap(t, 'document_upload_submit');
        await settleFor(t);
        await settleFor(t);
        await _tap(t, 'document_upload_close');
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(
          rig.refreshCalls,
          greaterThanOrEqualTo(1),
          reason: 'sunucuda bekleyen kayıt var',
        );
      },
    );
  });

  group('yeni sürüm', () {
    DocumentSummary target() => const DocumentSummary(
      id: 41,
      title: 'Site Yönetmeliği',
      category: DocumentCategory.regulation,
      audience: DocumentAudience.residents,
      status: DocumentStatus.active,
    );

    testWidgets('başlık / kitle alanı yok; not var; createVersion çağrılır', (
      t,
    ) async {
      final rig = _Rig(versionOf: target(), picks: [fakeSource('v3.pdf')]);
      rig.service.docs[41] = FakeDoc(41);
      await rig.open(t);
      expect(find.text('Yeni Sürüm Yükle'), findsOneWidget);
      expect(_key('document_upload_title'), findsNothing);
      expect(find.text('Kimler görebilir?'), findsNothing);
      expect(_key('document_upload_note'), findsOneWidget);
      expect(find.text(_kvkk), findsOneWidget);

      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      await _type(t, 'document_upload_note', 'Madde 5 düzeltildi');
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      await settleFor(t);
      await settleFor(t);

      expect(rig.service.versionCalls.single.id, 41);
      expect(rig.service.versionCalls.single.note, 'Madde 5 düzeltildi');
      expect(rig.service.createCalls, isEmpty);
      expect(rig.closed, isTrue);
      expect(rig.service.docs[41]!.versions.map((v) => v.no), <int>[1, 2]);
    });

    testWidgets('yalnız dosya zorunlu: dosya seçilmeden gönderilemez', (
      t,
    ) async {
      final rig = _Rig(versionOf: target());
      await rig.open(t);
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      expect(find.text('Yüklenecek dosyayı seçin.'), findsOneWidget);
      expect(rig.service.versionCalls, isEmpty);
    });
  });

  group('klavye ve erişilebilirlik', () {
    testWidgets('klavye açıkken "Yükle" düğmesi görünür kalır (320x640)', (
      t,
    ) async {
      final rig = _Rig(picks: [fakeSource('a.pdf')]);
      await rig.open(t, width: 320, height: 640, scale: 2.0);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final rect = t.getRect(_key('document_upload_submit'));
      expect(
        rect.bottom,
        lessThanOrEqualTo(640 - 280 + 0.5),
        reason: 'düğme klavyenin üstünde',
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(t.takeException(), isNull);
    });

    testWidgets('kitle seçenekleri radyo grubu olarak okunur ve "seçili" der', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final rig = _Rig();
      await rig.open(t);
      await _tap(t, 'document_upload_audience_board');
      final selected = t.getSemantics(_key('document_upload_audience_board'));
      expect(selected.label, contains('Yönetim kurulu'));
      // ignore: deprecated_member_use
      expect(selected.hasFlag(SemanticsFlag.isSelected), isTrue);
      final other = t.getSemantics(_key('document_upload_audience_managers'));
      // ignore: deprecated_member_use
      expect(other.hasFlag(SemanticsFlag.isSelected), isFalse);
      handle.dispose();
    });

    testWidgets('seçilen dosya ekran okuyucuya "PDF, 2 KB" olarak okunur', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final rig = _Rig(picks: [fakeSource('rapor.pdf', size: 2048)]);
      await rig.open(t);
      await _tap(t, 'document_upload_pick');
      await settleFor(t);
      expect(
        find.bySemanticsLabel('Seçilen dosya: rapor.pdf, PDF, 2,0 KB'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('ilerleme çubuğu yüzdeyi söyler', (t) async {
      final handle = t.ensureSemantics();
      final rig = _Rig(picks: [fakeSource('a.pdf', size: 4000)]);
      await rig.open(t);
      await _fill(t, rig);
      final hold = Completer<void>();
      rig.service.uploadGates
        ..add(Completer<void>()..complete())
        ..add(Completer<void>()..complete())
        ..add(hold);
      await _tap(t, 'document_upload_submit');
      await settleFor(t);
      expect(find.bySemanticsLabel('Yükleniyor, yüzde 50'), findsOneWidget);
      hold.complete();
      await settleFor(t);
      await settleFor(t);
      handle.dispose();
    });
  });
}
