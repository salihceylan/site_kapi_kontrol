// Platform Faz 3b-A: belge düzenleme penceresi (DocumentEditDialog). Yalnız DEĞİŞEN alanlar gider; değişiklik yoksa
// istek yapılmadan kapanır; kitle değişikliği hedefi doğru taşır; hata pencerede kalır; çift gönderim ve
// kaydedilmemiş değişiklik korunur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/document_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'document_fixtures.dart';
import 'list_fixtures.dart' show tapFinder;

class _Rig {
  _Rig({this.id = 41}) : auth = DocumentFakeAuth() {
    service = seededDocuments(auth);
  }

  final DocumentFakeAuth auth;
  late final FakeDocumentService service;
  final int id;
  DocumentDetail? result;
  bool closed = false;
  int refresh = 0;

  PeopleScope get scope => PeopleScope(
    authService: auth,
    siteCode: 11,
    siteName: 'Gül Sitesi',
    canWrite: true,
  );

  Future<void> open(
    WidgetTester t, {
    double width = 400,
    double height = 1800,
    double scale = 1.0,
    bool dark = false,
  }) async {
    final detail = await service.getManaged(11, id);
    return openDialogAt(
      t,
      (context) async {
        result = await DocumentEditDialog.show(
          context,
          scope: scope,
          service: service,
          document: detail,
          onRefreshNeeded: () => refresh++,
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

Future<void> _tap(WidgetTester t, String key) => tapFinder(t, _key(key));

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = _key(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

/// Pencereyi açar ve ilk kareyi bekler.
Future<_Rig> _open(WidgetTester t, {int id = 41}) async {
  final rig = _Rig(id: id);
  await rig.open(t);
  await settleFor(t);
  return rig;
}

void main() {
  group('yayındaki duyuruya ekli belgede kitle değişikliği (DOCUMENT_IN_USE onayı)', () {
    Future<_Rig> openAttached(WidgetTester t, {int attached = 2}) async {
      final rig = _Rig();
      rig.service.docs[41]!.attachedAnnouncements = <int>[
        for (var i = 0; i < attached; i++) 100 + i,
      ];
      await rig.open(t);
      await settleFor(t);
      return rig;
    }

    testWidgets(
      'sakinlerden çıkarmadan ÖNCE uyarı görünür; sakinlerde kalınca görünmez',
      (t) async {
        final rig = await openAttached(t);
        expect(_key('document_edit_detach_warning'), findsNothing);
        expect(find.textContaining('2 duyuruya ekli'), findsOneWidget);
        await _tap(t, 'document_edit_audience_board');
        expect(_key('document_edit_detach_warning'), findsOneWidget);
        expect(
          find.textContaining(
            'taslak ve zamanlanmış duyurulardan ek çıkarılır',
          ),
          findsOneWidget,
        );
        await _tap(t, 'document_edit_audience_residents');
        expect(_key('document_edit_detach_warning'), findsNothing);
        expect(rig.service.updateCalls, isEmpty);
      },
    );

    testWidgets(
      '409 DOCUMENT_IN_USE -> onay penceresi -> "Yine de Değiştir" confirm:true ile yeniden dener',
      (t) async {
        final rig = await openAttached(t);
        await _tap(t, 'document_edit_audience_managers');
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);

        expect(find.text('Belge duyurularda kullanılıyor'), findsOneWidget);
        expect(
          find.textContaining('2 yayındaki duyuruya ekli'),
          findsOneWidget,
        );
        expect(find.textContaining('erişemez'), findsWidgets);
        expect(rig.service.updateCalls, hasLength(1));
        expect(rig.service.updateCalls.single.confirm, isFalse);
        expect(rig.closed, isFalse);

        await _tap(t, 'document_edit_inuse_confirm');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.updateCalls, hasLength(2));
        expect(rig.service.updateCalls.last.confirm, isTrue);
        expect(rig.service.updateCalls.last.fields, <String, Object?>{
          'audience': 'managers',
        });
        expect(rig.service.docs[41]!.audience, 'managers');
        expect(rig.service.docs[41]!.attachedAnnouncements, isEmpty);
        expect(rig.closed, isTrue);
      },
    );

    testWidgets(
      'onay penceresinde Vazgeç: ikinci istek yok, hata yok, form açık ve odak Kaydet düğmesinde',
      (t) async {
        final rig = await openAttached(t, attached: 1);
        await _tap(t, 'document_edit_audience_board');
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(
          find.textContaining('1 yayındaki duyuruya ekli'),
          findsOneWidget,
        );
        await _tap(t, 'document_edit_inuse_cancel');
        await settleFor(t);
        await settleFor(t);

        expect(rig.service.updateCalls, hasLength(1));
        expect(rig.closed, isFalse);
        expect(
          find.byType(InlineNotice),
          findsNWidgets(2),
          reason: 'yalnız bilgi notu + ön uyarı; hata kutusu yok',
        );
        expect(find.text('Lütfen işaretli alanları düzeltin.'), findsNothing);
        expect(
          t
              .widget<ElevatedButton>(_key('document_edit_save'))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(
          t.widget<ElevatedButton>(_key('document_edit_save')).onPressed,
          isNotNull,
        );

        // Çıkmaz yok: kitle eski haline getirilince değişiklik kalmaz ve kapanır.
        await _tap(t, 'document_edit_audience_residents');
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        expect(rig.service.updateCalls, hasLength(1));
        expect(rig.closed, isTrue);
      },
    );

    testWidgets(
      'onay sonrası ikinci istek hata verirse ileti pencerede kalır; yeniden Kaydet yine onay ister',
      (t) async {
        final rig = await openAttached(t);
        await _tap(t, 'document_edit_audience_board');
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        // İkinci istek (confirm:true) ağ hatasıyla düşer.
        rig.service.writeError = ApiException('Bağlantı koptu.');
        await _tap(t, 'document_edit_inuse_confirm');
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Bağlantı koptu.'), findsOneWidget);
        expect(rig.closed, isFalse);
        expect(rig.service.docs[41]!.attachedAnnouncements, isNotEmpty);

        rig.service.writeError = null;
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Belge duyurularda kullanılıyor'), findsOneWidget);
        await _tap(t, 'document_edit_inuse_confirm');
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.service.docs[41]!.audience, 'board');
      },
    );

    testWidgets(
      'duyuruya ekli değilse onay penceresi çıkmaz (tek istek, confirm yok)',
      (t) async {
        final rig = await openAttached(t, attached: 0);
        await _tap(t, 'document_edit_audience_board');
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Belge duyurularda kullanılıyor'), findsNothing);
        expect(rig.service.updateCalls.single.confirm, isFalse);
        expect(rig.closed, isTrue);
      },
    );

    testWidgets('sakinlerde kalıp yalnız hedefi daraltmak onay istemez', (
      t,
    ) async {
      final rig = await openAttached(t);
      await tapFinder(t, find.byTooltip('A hedeften çıkar'));
      await tapFinder(t, _key('document_target_site'));
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Belge duyurularda kullanılıyor'), findsNothing);
      expect(
        rig.service.updateCalls.single.fields.containsKey('audience'),
        isFalse,
      );
      expect(rig.closed, isTrue);
    });

    layoutMatrix('onay penceresi ve ön uyarı taşmaz', (t, w, h, s, dark) async {
      final rig = _Rig();
      rig.service.docs[41]!.attachedAnnouncements = <int>[7, 8];
      await rig.open(t, width: w, height: h, scale: s, dark: dark);
      await settleFor(t);
      await _tap(t, 'document_edit_audience_managers');
      expect(_key('document_edit_detach_warning'), findsOneWidget);
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Belge duyurularda kullanılıyor'), findsOneWidget);
      expect(find.text('Yine de Değiştir'), findsOneWidget);
    });
  });

  group('yatay telefon (640x360 x2,0)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets('düzenleme formu taşmaz (${dark ? 'koyu' : 'açık'})', (
        t,
      ) async {
        final rig = _Rig();
        await rig.open(t, width: 640, height: 360, scale: 2.0, dark: dark);
        await settleFor(t);
        expect(find.text('Belgeyi Düzenle'), findsOneWidget);
        expect(find.text('Kaydet'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('taşma matrisi', () {
    layoutMatrix(
      'düzenleme formu: alanlar belge değerleriyle dolu, kitle ve hedef görünür',
      (t, w, h, s, dark) async {
        final rig = _Rig();
        await rig.open(t, width: w, height: h, scale: s, dark: dark);
        await settleFor(t);

        expect(find.text('Belgeyi Düzenle'), findsOneWidget);
        expect(
          (t.widget<TextFormField>(
            _key('document_edit_title'),
          )).controller!.text,
          'Site Yönetmeliği',
        );
        expect(
          (t.widget<TextFormField>(
            _key('document_edit_description'),
          )).controller!.text,
          'Güncel site yönetmeliği.',
        );
        expect(_key('document_edit_audience_residents'), findsOneWidget);
        expect(find.text('A'), findsOneWidget, reason: 'seçili blok çipi');
        expect(find.text('Kaydet'), findsOneWidget);
        expect(
          find.textContaining('Kitle değişikliği anında geçerlidir'),
          findsOneWidget,
        );
      },
    );
  });

  group('gönderim', () {
    testWidgets('değişiklik yoksa istek yapılmadan kapanır', (t) async {
      final rig = await _open(t);
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      expect(rig.service.updateCalls, isEmpty);
      expect(rig.closed, isTrue);
      expect(rig.result, isNull);
    });

    testWidgets('yalnız başlık değişti: yalnız title gider', (t) async {
      final rig = await _open(t);
      await _type(t, 'document_edit_title', '  Yeni Başlık ');
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{
        'title': 'Yeni Başlık',
      });
      expect(rig.closed, isTrue);
      expect(rig.result?.title, 'Yeni Başlık');
    });

    testWidgets('kategori ve açıklama değişti', (t) async {
      final rig = await _open(t);
      await _tap(t, 'document_edit_category_contract');
      await _type(t, 'document_edit_description', 'Yeni açıklama');
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{
        'category': 'contract',
        'description': 'Yeni açıklama',
      });
    });

    testWidgets(
      'sakinlerden yöneticilere: yalnız audience gider (hedef gönderilmez)',
      (t) async {
        final rig = await _open(t);
        await _tap(t, 'document_edit_audience_managers');
        expect(
          find.byKey(const ValueKey<String>('document_target_site')),
          findsNothing,
          reason: 'hedef bölümü kalkar',
        );
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.updateCalls.single.fields, <String, Object?>{
          'audience': 'managers',
        });
      },
    );

    testWidgets(
      'yöneticilerden sakinlere: audience + target (Tüm site) gider',
      (t) async {
        final rig = await _open(t, id: 39);
        await _tap(t, 'document_edit_audience_residents');
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.updateCalls.single.fields, <String, Object?>{
          'audience': 'residents',
          'target': <String, dynamic>{'type': 'site'},
        });
      },
    );

    testWidgets('hedef değişti (blok çıkarıldı -> Tüm site): target gider', (
      t,
    ) async {
      final rig = await _open(t);
      await tapFinder(t, find.byTooltip('A hedeften çıkar'));
      await tapFinder(t, _key('document_target_site'));
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      await settleFor(t);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{
        'target': <String, dynamic>{'type': 'site'},
      });
    });

    testWidgets('boş başlık gönderilemez', (t) async {
      final rig = await _open(t);
      await _type(t, 'document_edit_title', '   ');
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      expect(find.text('Başlık boş olamaz.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(rig.service.updateCalls, isEmpty);
    });

    testWidgets(
      'blok hedefi boşaltılırsa "En az bir blok seçin." (istek yok)',
      (t) async {
        final rig = await _open(t);
        await tapFinder(t, find.byTooltip('A hedeften çıkar'));
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        expect(find.text('En az bir blok seçin.'), findsOneWidget);
        expect(rig.service.updateCalls, isEmpty);
      },
    );

    testWidgets(
      'gönderim sürerken ikinci istek gitmez; düğme "Kaydediliyor..."',
      (t) async {
        final rig = await _open(t);
        await _type(t, 'document_edit_title', 'Başka');
        final gate = Completer<void>();
        rig.service.writeGates.add(gate);
        await _tap(t, 'document_edit_save');
        await t.pump();
        expect(find.text('Kaydediliyor...'), findsOneWidget);
        expect(
          t.widget<ElevatedButton>(_key('document_edit_save')).onPressed,
          isNull,
        );
        expect(
          t.widget<TextButton>(_key('document_edit_close')).onPressed,
          isNull,
        );
        gate.complete();
        await settleFor(t);
        await settleFor(t);
        expect(rig.service.updateCalls, hasLength(1));
      },
    );

    testWidgets(
      'hata pencerede kalır, odak Kaydet düğmesinde; yeniden denenebilir',
      (t) async {
        final rig = await _open(t);
        await _type(t, 'document_edit_title', 'Başka');
        rig.service.writeError = ApiException(
          'Sunucu şu anda yanıt veremiyor (503). Lütfen biraz sonra tekrar deneyin.',
          statusCode: 503,
        );
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(find.textContaining('yanıt veremiyor'), findsOneWidget);
        expect(rig.closed, isFalse);
        expect(
          t
              .widget<ElevatedButton>(_key('document_edit_save'))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(
          find.text('Başka'),
          findsOneWidget,
          reason: 'girilen değer korunur',
        );

        rig.service.writeError = null;
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.service.updateCalls, hasLength(2));
      },
    );

    testWidgets(
      'belge başka yerden silindi (404): liste tazelenir ve ileti gösterilir',
      (t) async {
        final rig = await _open(t);
        await _type(t, 'document_edit_title', 'Başka');
        rig.service.docs.remove(41);
        await _tap(t, 'document_edit_save');
        await settleFor(t);
        await settleFor(t);
        expect(
          find.text('Belge bulunamadı ya da erişiminiz yok.'),
          findsOneWidget,
        );
        expect(rig.refresh, 1);
      },
    );

    testWidgets('429: Kaydet geçici kilitlenir', (t) async {
      final rig = await _open(t);
      await _type(t, 'document_edit_title', 'Başka');
      rig.service.writeError = ApiException(
        'Çok fazla istek gönderildi. 30 saniye sonra tekrar deneyin.',
        statusCode: 429,
        retryAfterSeconds: 30,
      );
      await _tap(t, 'document_edit_save');
      await settleFor(t);
      await settleFor(t);
      expect(
        t.widget<ElevatedButton>(_key('document_edit_save')).onPressed,
        isNull,
      );
      await t.pump(const Duration(seconds: 31));
      expect(
        t.widget<ElevatedButton>(_key('document_edit_save')).onPressed,
        isNotNull,
      );
    });
  });

  group('kaydedilmemiş değişiklik', () {
    testWidgets('değişiklik yoksa Vazgeç doğrudan kapatır', (t) async {
      final rig = await _open(t);
      await _tap(t, 'document_edit_close');
      await settleFor(t);
      expect(rig.closed, isTrue);
    });

    testWidgets(
      'değişiklik varken Vazgeç onay ister; "Düzenlemeye Dön" korur, "Vazgeç ve Kapat" atar',
      (t) async {
        final rig = await _open(t);
        await _type(t, 'document_edit_title', 'Başka');
        await _tap(t, 'document_edit_close');
        await settleFor(t);
        expect(find.text('Değişiklikler silinsin mi?'), findsOneWidget);
        await _tap(t, 'document_edit_keep');
        await settleFor(t);
        expect(rig.closed, isFalse);
        expect(find.text('Başka'), findsOneWidget);

        await t.binding.handlePopRoute();
        await settleFor(t);
        expect(
          find.text('Değişiklikler silinsin mi?'),
          findsOneWidget,
          reason: 'geri tuşu da onay ister',
        );
        await _tap(t, 'document_edit_discard');
        await settleFor(t);
        expect(rig.closed, isTrue);
        expect(rig.service.updateCalls, isEmpty);
      },
    );
  });
}
