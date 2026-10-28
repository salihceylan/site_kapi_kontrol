// Geri bildirim formu (docs/PLATFORM_GERI_BILDIRIM.md, karar K11): ekran bağlamı (ad + rota + site) formda OTOMATİK görünür ve DEĞİŞTİRİLEMEZ, isteğe
// girer; metin doğrulaması; en çok 4 dosya (5 MB / toplam 20 MB) ve seçimde reddedilen dosyalar; gönderim hatasında metin korunur; kayıt açıldıktan sonra
// dosyalar sırayla yüklenir, kısmi başarısızlık DÜRÜSTÇE bildirilir ve yeniden denenir; doldurulmuş form kapanırken onay istenir; taşma matrisi
// (320x640 x2,0; 360x640 x1,5; yatay; tablet; açık / koyu).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/ui/dialogs/feedback_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;

import 'dialog_layout_harness.dart';
import 'work_fixtures.dart';

const FeedbackScreenContext _screen = FeedbackScreenContext(
  screenName: 'Talepler',
  screenRoute: 'menu/talepler',
  siteCode: 11,
  siteName: 'Gül Sitesi',
);

/// Ağsız sahte API: çağrıları kaydeder; hatalar testten sürülür.
class _FakeFeedbackApi extends FeedbackApi {
  _FakeFeedbackApi() : super(baseUrl: 'http://localhost');

  final List<FeedbackCreateRequest> created = <FeedbackCreateRequest>[];
  final List<({int feedback, int attachment, int size})> uploads = <({int feedback, int attachment, int size})>[];
  Object? createError;

  /// Ek kimliği -> bir kez fırlatılacak hata (yeniden denemede başarılı olur).
  final Map<int, Object> failOnce = <int, Object>{};
  Completer<void>? uploadGate;
  int _nextId = 7;

  @override
  Future<FeedbackRecord> create({required String token, required FeedbackCreateRequest request}) async {
    final error = createError;
    if (error != null) throw error;
    created.add(request);
    final id = _nextId++;
    return FeedbackRecord(
      id: id,
      siteCode: request.context.siteCode,
      siteName: request.context.siteName,
      userName: 'Sakin',
      role: 'resident',
      screenName: request.context.screenName,
      screenRoute: request.context.screenRoute,
      message: request.message,
      appVersion: request.appVersion,
      platform: request.platform,
      createdAt: DateTime(2026, 10, 28),
      attachments: <FeedbackAttachment>[
        for (var i = 0; i < request.attachments.length; i++)
          FeedbackAttachment(
            id: 100 + i,
            feedbackId: id,
            fileName: request.attachments[i].fileName,
            mimeType: request.attachments[i].mimeType,
            sizeBytes: request.attachments[i].sizeBytes,
            ready: false,
          ),
      ],
    );
  }

  @override
  Future<FeedbackAttachment> uploadAttachment({
    required String token,
    required int feedbackId,
    required int attachmentId,
    required Uint8List bytes,
  }) async {
    final gate = uploadGate;
    if (gate != null) await gate.future;
    final error = failOnce.remove(attachmentId);
    if (error != null) throw error;
    uploads.add((feedback: feedbackId, attachment: attachmentId, size: bytes.length));
    return FeedbackAttachment(
      id: attachmentId,
      feedbackId: feedbackId,
      fileName: 'x.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: bytes.length,
      ready: true,
    );
  }
}

class _Rig {
  _Rig([List<WorkPhotoSelection> picks = const <WorkPhotoSelection>[]])
    : picker = FakeWorkPhotoPicker(picks),
      api = _FakeFeedbackApi() {
    service = FeedbackService(authService: WorkFakeAuth(), api: api);
  }

  final FakeWorkPhotoPicker picker;
  final _FakeFeedbackApi api;
  late final FeedbackService service;
  FeedbackSendOutcome? outcome;
  bool closed = false;

  Future<void> open(
    WidgetTester t, {
    double width = 400,
    double height = 1400,
    double scale = 1.0,
    bool dark = false,
    FeedbackScreenContext screen = _screen,
  }) {
    return openDialogAt(
      t,
      (context) async {
        outcome = await FeedbackDialog.show(
          context,
          service: service,
          screenContext: screen,
          appVersion: '1.0.0+1',
          platform: 'android',
          picker: picker,
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

Finder _k(String key) => find.byKey(ValueKey<String>(key));

Future<void> _type(WidgetTester t, String text) async {
  await t.ensureVisible(_k('feedback_message'));
  await t.pump();
  await t.enterText(_k('feedback_message'), text);
  await t.pump();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.ensureVisible(_k(key));
  await t.pump();
  await t.tap(_k(key));
  await settleFor(t, 100);
  await settleFor(t, 100);
}

WorkPhotoSelection _picks(List<WorkPhotoPick> picks, {List<WorkPhotoPick> rejected = const <WorkPhotoPick>[]}) =>
    WorkPhotoSelection(picks: picks, rejected: rejected);

void main() {
  group('ekran bağlamı OTOMATİK eklenir ve değiştirilemez', () {
    testWidgets('form ekran adı + rota + siteyi gösterir; düzenlenebilir tek alan metindir', (t) async {
      final rig = _Rig();
      await rig.open(t);
      expect(t.widget<Text>(_k('feedback_context_name')).data, 'Talepler');
      expect(t.widget<Text>(_k('feedback_context_route')).data, 'menu/talepler');
      expect(t.widget<Text>(_k('feedback_context_site')).data, 'Site: Gül Sitesi');
      expect(find.text('Gönderildiği ekran (otomatik eklenir)'), findsOneWidget);
      // bağlam bir metin alanı DEĞİL: tek TextField geri bildirim metnidir
      expect(find.byType(TextField), findsOneWidget);
      expect(find.descendant(of: _k('feedback_context'), matching: find.byType(TextField)), findsNothing);
      // gizlilik: kimlerin göreceği açıkça yazılır
      expect(find.text(kFeedbackAudienceNote), findsOneWidget);
    });

    testWidgets('gönderilen istek ekran adı, rota, site, sürüm ve platformu taşır', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await _type(t, '  Menü karışık görünüyor.  ');
      await _tap(t, 'feedback_send');
      expect(rig.api.created, hasLength(1));
      final request = rig.api.created.single;
      expect(request.message, 'Menü karışık görünüyor.');
      expect(request.context.screenName, 'Talepler');
      expect(request.context.screenRoute, 'menu/talepler');
      expect(request.context.siteCode, 11);
      expect(request.appVersion, '1.0.0+1');
      expect(request.platform, 'android');
      expect(request.attachments, isEmpty);
      expect(rig.closed, isTrue);
      expect(rig.outcome!.record.screenRoute, 'menu/talepler');
      expect(rig.outcome!.allUploaded, isTrue);
    });

    testWidgets('siteye bağlı olmayan bağlam (süper kullanıcı / tüm siteler): site satırı ve site_code yok', (t) async {
      final rig = _Rig();
      await rig.open(t, screen: const FeedbackScreenContext(screenName: 'Panel', screenRoute: 'menu/dashboard'));
      expect(_k('feedback_context_site'), findsNothing);
      await _type(t, 'Merhaba');
      await _tap(t, 'feedback_send');
      expect(rig.api.created.single.context.siteCode, isNull);
      expect(rig.api.created.single.toJson().containsKey('site_code'), isFalse);
    });
  });

  group('metin doğrulaması ve gönderim hatası', () {
    testWidgets('boş metin gönderilmez: alan hatası görünür, sunucuya gidilmez', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await _tap(t, 'feedback_send');
      expect(find.text('Geri bildirim metni boş olamaz.'), findsOneWidget);
      expect(rig.api.created, isEmpty);
      expect(rig.closed, isFalse);
    });

    testWidgets('2000 karakter üstü reddedilir', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await _type(t, 'a' * 2001);
      await _tap(t, 'feedback_send');
      expect(find.textContaining('en çok 2000 karakter'), findsOneWidget);
      expect(rig.api.created, isEmpty);
    });

    testWidgets('sunucu reddederse (400/429) form açık kalır, metin korunur, sunucu iletisi görünür', (t) async {
      final rig = _Rig();
      rig.api.createError = ApiException('Bir saat içinde çok fazla geri bildirim gönderdiniz.', statusCode: 429, retryAfterSeconds: 3600);
      await rig.open(t);
      await _type(t, 'Önemli not');
      await _tap(t, 'feedback_send');
      expect(find.text('Bir saat içinde çok fazla geri bildirim gönderdiniz.'), findsOneWidget);
      expect(rig.closed, isFalse);
      expect(t.widget<TextFormField>(_k('feedback_message')).controller!.text, 'Önemli not');
      // 429: Gönder düğmesi Retry-After süresince kilitlenir
      expect(t.widget<ElevatedButton>(_k('feedback_send')).onPressed, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });

    testWidgets('doldurulmuş form kapatılırken onay istenir; "Yazmaya Dön" formu korur, "Vazgeç ve Kapat" kapatır', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await _type(t, 'Yarım kalan');
      await _tap(t, 'feedback_close');
      expect(find.text('Geri bildirim silinsin mi?'), findsOneWidget);
      await _tap(t, 'feedback_keep');
      expect(find.byType(FeedbackDialog), findsOneWidget);
      await _tap(t, 'feedback_close');
      await _tap(t, 'feedback_discard');
      expect(find.byType(FeedbackDialog), findsNothing);
      expect(rig.outcome, isNull);
      expect(rig.api.created, isEmpty);
    });

    testWidgets('boş form onaysız kapanır', (t) async {
      final rig = _Rig();
      await rig.open(t);
      await _tap(t, 'feedback_close');
      expect(find.byType(FeedbackDialog), findsNothing);
    });
  });

  group('dosyalar: en çok 4, dosya başı 5 MB, toplam 20 MB', () {
    testWidgets('seçilen dosyalar listelenir ve isteğe ad / tür / boyut olarak girer; kayıttan sonra sırayla yüklenir', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[wkPhoto('ekran1.jpg', size: 4096), wkPhoto('ekran2.png', size: 2048)]),
      ]);
      await rig.open(t);
      await _type(t, 'Görüntüler ekte');
      await _tap(t, 'feedback_photo_add');
      expect(rig.picker.calls, <int>[4], reason: 'en çok 4 dosya istenir');
      expect(t.widget<Text>(_k('feedback_photo_count')).data, '2/4');
      expect(find.text('ekran1.jpg'), findsOneWidget);
      expect(find.textContaining('/ 20 MB'), findsOneWidget);
      await _tap(t, 'feedback_send');
      final request = rig.api.created.single;
      expect(
        request.attachments.map((a) => (a.fileName, a.mimeType, a.sizeBytes)),
        <(String, String, int)>[('ekran1.jpg', 'image/jpeg', 4096), ('ekran2.png', 'image/png', 2048)],
      );
      expect(rig.api.uploads.map((u) => (u.feedback, u.attachment, u.size)), <(int, int, int)>[(7, 100, 4096), (7, 101, 2048)]);
      expect(rig.closed, isTrue);
      expect(rig.outcome!.uploaded, 2);
      expect(rig.outcome!.failed, 0);
      expect(rig.picker.releaseCalls, 1, reason: 'seçici kopyaları kapanırken silinir');
    });

    testWidgets('5 MB üstü dosya seçimde reddedilir, sebebiyle bildirilir ve yer DOLDURMAZ', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[wkPhoto('kucuk.jpg')], rejected: <WorkPhotoPick>[wkPhoto('dev.jpg', size: 6 * 1024 * 1024)]),
      ]);
      await rig.open(t);
      await _tap(t, 'feedback_photo_add');
      expect(t.widget<Text>(_k('feedback_photo_count')).data, '1/4');
      expect(find.textContaining('dev.jpg'), findsOneWidget);
      expect(find.textContaining('en fazla 5 MB'), findsWidgets);
    });

    testWidgets('dört dosya dolunca ekleme kapanır; kaldırınca yeniden açılır', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[for (var i = 0; i < 4; i++) wkPhoto('f$i.jpg', size: 1000 + i)]),
      ]);
      await rig.open(t);
      await _tap(t, 'feedback_photo_add');
      expect(t.widget<Text>(_k('feedback_photo_count')).data, '4/4');
      expect(find.text('Dosya sınırına ulaşıldı'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(_k('feedback_photo_add')).onPressed, isNull);
      await _tap(t, 'feedback_photo_remove_0');
      expect(t.widget<Text>(_k('feedback_photo_count')).data, '3/4');
      expect(find.text('Dosya Ekle'), findsOneWidget);
    });

    testWidgets('seçimde fazla dosya: yalnız kalan yer kadarı alınır (sınır uyarısı)', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[for (var i = 0; i < 5; i++) wkPhoto('g$i.jpg', size: 900 + i)]),
      ]);
      await rig.open(t);
      await _tap(t, 'feedback_photo_add');
      expect(t.widget<Text>(_k('feedback_photo_count')).data, '4/4');
      expect(find.textContaining('En fazla 4'), findsWidgets);
    });

    testWidgets('yükleme kısmen başarısız: kayıt alındı DÜRÜSTÇE bildirilir, Tekrar Dene yalnız eksiği yükler ve hepsi bitince kapanır', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[wkPhoto('a.jpg', size: 1500), wkPhoto('b.jpg', size: 2500)]),
      ]);
      rig.api.failOnce[101] = ApiException('Dosya yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.', statusCode: 500);
      await rig.open(t);
      await _type(t, 'Ekli');
      await _tap(t, 'feedback_photo_add');
      await _tap(t, 'feedback_send');
      expect(rig.closed, isFalse, reason: 'yüklenemeyen dosya varken sonuç gösterilir');
      expect(find.textContaining('Geri bildiriminiz alındı; 1 dosya yüklenemedi'), findsOneWidget);
      expect(rig.api.created, hasLength(1), reason: 'kayıt bir daha oluşturulmaz (çift kayıt yok)');
      expect(rig.api.uploads.map((u) => u.attachment), <int>[100]);
      expect(find.text('Yüklendi'), findsOneWidget);
      await _tap(t, 'feedback_upload_retry');
      expect(rig.api.created, hasLength(1));
      expect(rig.api.uploads.map((u) => u.attachment), <int>[100, 101], reason: 'yalnız eksik dosya yeniden gönderilir');
      expect(rig.closed, isTrue);
      expect(rig.outcome!.failed, 0);
      expect(rig.outcome!.uploaded, 2);
    });

    testWidgets('oturum / hız sınırı hatasında kalan dosyalar DENENMEZ; Kapat sonucu (kaç dosya yüklenemedi) döndürür', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[wkPhoto('a.jpg', size: 100), wkPhoto('b.jpg', size: 200), wkPhoto('c.jpg', size: 300)]),
      ]);
      rig.api.failOnce[100] = ApiException('Çok fazla dosya yükleme denemesi.', statusCode: 429, retryAfterSeconds: 60);
      await rig.open(t);
      await _type(t, 'Ekli');
      await _tap(t, 'feedback_photo_add');
      await _tap(t, 'feedback_send');
      expect(rig.api.uploads, isEmpty, reason: '429 sonrası kalan dosyalar boşuna denenmez');
      expect(find.textContaining('3 dosya yüklenemedi'), findsOneWidget);
      await _tap(t, 'feedback_upload_close');
      expect(rig.closed, isTrue);
      expect(rig.outcome!.uploaded, 0);
      expect(rig.outcome!.failed, 3);
      await t.pump(const Duration(seconds: 61));
    });

    testWidgets('yükleme sürerken kapatma yok; Vazgeç kalan dosyaları gönderilmez bırakır', (t) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[wkPhoto('a.jpg', size: 100), wkPhoto('b.jpg', size: 200)]),
      ]);
      rig.api.uploadGate = Completer<void>();
      await rig.open(t);
      await _type(t, 'Ekli');
      await _tap(t, 'feedback_photo_add');
      await _tap(t, 'feedback_send');
      expect(find.text('Dosyalar Yükleniyor'), findsOneWidget);
      expect(rig.closed, isFalse);
      await _tap(t, 'feedback_upload_cancel');
      rig.api.uploadGate!.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      // ilk dosya uçuştaydı ve tamamlandı; ikincisi iptal edildi
      expect(rig.api.uploads.map((u) => u.attachment), <int>[100]);
      expect(find.textContaining('1 dosya yüklenemedi'), findsOneWidget);
      await _tap(t, 'feedback_upload_close');
      expect(rig.outcome!.failed, 1);
    });
  });

  group('taşma matrisi', () {
    layoutMatrix('Geri bildirim formu', (t, w, h, s, dark) async {
      final rig = _Rig();
      await rig.open(t, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(FeedbackDialog), findsOneWidget);
    });

    layoutMatrix('Geri bildirim formu, dört dosya + uzun bağlam', (t, w, h, s, dark) async {
      final rig = _Rig(<WorkPhotoSelection>[
        _picks(<WorkPhotoPick>[for (var i = 0; i < 4; i++) wkPhoto('cok_uzun_bir_ekran_goruntusu_dosya_adi_$i.jpg', size: 3000 + i)]),
      ]);
      await rig.open(
        t,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        screen: const FeedbackScreenContext(
          screenName: 'Sözleşmeler ve firma takibi (yönetim görünümü)',
          screenRoute: 'menu/sozlesmeler:sakin',
          siteCode: 11,
          siteName: 'Çok Uzun Adlı Bir Sitenin Yönetim Kurulu Sitesi',
        ),
      );
      await _type(t, 'Uzun bir metin ' * 20);
      await _tap(t, 'feedback_photo_add');
      expect(t.widget<Text>(_k('feedback_photo_count')).data, '4/4');
    });
  });
}
