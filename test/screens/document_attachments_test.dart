// Platform Faz 3b-A: duyuruya belge eki (docs/PLATFORM_BELGELER.md A12, A13) — seçim alanı (DocumentAttachmentField),
// seçici pencere (DocumentAttachPickerDialog), "Ekler" listesi (DocumentAttachmentsList), duyuru formu
// entegrasyonu (document_ids), yönetici ayrıntısı ve sakin okuma penceresi.
//
// Kurallar: yalnız `residents` kitlesindeki YAYINDAKİ belgeler seçilir; en çok 5; ekleme anında uyarı; modül
// kapalıysa alan çizilmez; `available:false` ek indirilemez ve "Artık kullanılamıyor" der.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_manage_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_read_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_attach_picker_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_attachment_field.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_attachments_list.dart';

import 'announcement_fixtures.dart';
import 'dialog_layout_harness.dart';
import 'document_fixtures.dart';
import 'list_fixtures.dart' show tapFinder;
import 'people_fixtures.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

DocumentAttachment _att(
  int id, {
  String title = 'Plan',
  bool available = true,
  int size = 1048576,
}) => DocumentAttachment(
  documentId: id,
  title: title,
  fileName: 'plan-$id.pdf',
  mimeType: 'application/pdf',
  sizeBytes: size,
  available: available,
);

/// Seçim alanını tutan basit sahne: değer durumu burada yaşar.
class _FieldHost extends StatefulWidget {
  const _FieldHost({
    required this.scope,
    required this.service,
    required this.initial,
    required this.onValue,
  });

  final PeopleScope scope;
  final FakeDocumentService service;
  final List<DocumentAttachment> initial;
  final void Function(List<DocumentAttachment>) onValue;

  @override
  State<_FieldHost> createState() => _FieldHostState();
}

class _FieldHostState extends State<_FieldHost> {
  late List<DocumentAttachment> value = widget.initial;

  @override
  Widget build(BuildContext context) => DocumentAttachmentField(
    scope: widget.scope,
    service: widget.service,
    value: value,
    onChanged: (next) {
      setState(() => value = next);
      widget.onValue(next);
    },
  );
}

FakeDocumentService _service(DocumentFakeAuth auth) {
  final service = seededDocuments(auth);
  // Duyuruya eklenebilir (sakin kitlesi, yayında) ikinci belge.
  service.docs[42] = FakeDoc(
    42,
    title: 'Otopark Planı',
    audience: 'residents',
    category: 'notice',
  );
  service.docs[43] = FakeDoc(
    43,
    title: 'Havuz Kuralları',
    audience: 'residents',
    category: 'regulation',
  );
  return service;
}

PeopleScope _scope(DocumentFakeAuth auth) => PeopleScope(
  authService: auth,
  siteCode: 11,
  siteName: 'Gül Sitesi',
  canWrite: true,
);

Future<List<DocumentAttachment>> _pumpField(
  WidgetTester t,
  FakeDocumentService service,
  DocumentFakeAuth auth, {
  List<DocumentAttachment> initial = const <DocumentAttachment>[],
  double width = 400,
  double height = 1400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final latest = <DocumentAttachment>[...initial];
  await openDialogAt(
    t,
    (context) => showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        content: SingleChildScrollView(
          child: _FieldHost(
            scope: _scope(auth),
            service: service,
            initial: initial,
            onValue: (next) => latest
              ..clear()
              ..addAll(next),
          ),
        ),
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  await settleFor(t);
  return latest;
}

void main() {
  group('seçim alanı', () {
    testWidgets(
      'available:false ek satırı "Artık kullanılamıyor" der (kaldırılabilir); ekran okuyucu da söyler',
      (t) async {
        final handle = t.ensureSemantics();
        final auth = DocumentFakeAuth();
        final service = _service(auth);
        final value = await _pumpField(
          t,
          service,
          auth,
          initial: <DocumentAttachment>[
            _att(42, title: 'Otopark Planı'),
            _att(43, title: 'Silinmiş Plan', available: false),
          ],
        );
        expect(_key('announcement_attachment_unavailable_43'), findsOneWidget);
        expect(_key('announcement_attachment_unavailable_42'), findsNothing);
        expect(find.text('Artık kullanılamıyor'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Ek: Silinmiş Plan, PDF, 1,0 MB. Artık kullanılamıyor',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Ek: Otopark Planı, PDF, 1,0 MB'),
          findsOneWidget,
        );
        // Kullanılamayan ek yine kaldırılabilir (yönetici temizleyebilir).
        await tapFinder(t, _key('announcement_remove_attachment_43'));
        await settleFor(t);
        expect(value.map((a) => a.documentId), <int>[42]);
        handle.dispose();
      },
    );

    layoutMatrix('kullanılamayan ek satırı taşmaz', (t, w, h, s, dark) async {
      final auth = DocumentFakeAuth();
      await _pumpField(
        t,
        _service(auth),
        auth,
        initial: <DocumentAttachment>[
          _att(
            43,
            title: 'Çok Uzun Adlı Silinmiş Havuz Kullanım Kuralları Belgesi',
            available: false,
          ),
        ],
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Artık kullanılamıyor'), findsOneWidget);
    });

    layoutMatrix('2 ek: satırlar, uyarı metni ve Belge Ekle', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      final service = _service(auth);
      await _pumpField(
        t,
        service,
        auth,
        initial: <DocumentAttachment>[
          _att(42, title: 'Otopark Planı'),
          _att(
            43,
            title:
                'Çok Uzun Adlı Havuz Kullanım Kuralları ve Güvenlik Yönergesi',
          ),
        ],
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Belge eki'), findsOneWidget);
      expect(find.text('Otopark Planı'), findsOneWidget);
      expect(
        find.textContaining('Bu belge duyurunun tüm alıcılarına açılır.'),
        findsOneWidget,
      );
      expect(find.text('Belge Ekle'), findsOneWidget);
    });

    testWidgets('modül KAPALI (403 MODULE_DISABLED): alan hiç çizilmez', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = _service(auth)
        ..listError = ApiException(
          'x',
          statusCode: 403,
          code: 'MODULE_DISABLED',
        );
      await _pumpField(t, service, auth);
      expect(_key('announcement_attachments_field'), findsNothing);
      expect(find.text('Belge eki'), findsNothing);
    });

    testWidgets('yetki yok (403 FORBIDDEN_ROLE): alan çizilmez', (t) async {
      final auth = DocumentFakeAuth();
      final service = _service(
        auth,
      )..listError = ApiException('x', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _pumpField(t, service, auth);
      expect(find.text('Belge eki'), findsNothing);
    });

    testWidgets(
      'geçici ağ hatası: alan görünür kalır (seçici hatayı gösterir)',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = _service(auth)
          ..listError = ApiException('Bağlantı koptu.');
        await _pumpField(t, service, auth);
        expect(find.text('Belge eki'), findsOneWidget);
      },
    );

    testWidgets(
      'yoklama yalnız sakin kitlesi + yayında belge ister (limit 1)',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = _service(auth);
        await _pumpField(t, service, auth);
        final probe = service.listCalls.first;
        expect(probe.status, 'active');
        expect(probe.audience, 'residents');
        expect(probe.limit, 1);
      },
    );

    testWidgets(
      'Belge Ekle -> seçici yalnız sakin kitlesindeki yayın belgelerini listeler',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = _service(auth);
        await _pumpField(t, service, auth);
        await tapFinder(t, _key('announcement_add_attachment'));
        await settleFor(t);
        await settleFor(t);
        // seeded: 41 (residents/active), 40 (board), 39 (managers), 38 (silinmiş) + 42, 43.
        expect(_key('document_attach_41'), findsOneWidget);
        expect(_key('document_attach_42'), findsOneWidget);
        expect(_key('document_attach_43'), findsOneWidget);
        expect(
          _key('document_attach_40'),
          findsNothing,
          reason: 'kurul belgesi eklenemez',
        );
        expect(
          _key('document_attach_39'),
          findsNothing,
          reason: 'yönetici belgesi eklenemez',
        );
        expect(
          _key('document_attach_38'),
          findsNothing,
          reason: 'silinmiş belge eklenemez',
        );
        expect(
          find.textContaining('Bu belge duyurunun tüm alıcılarına açılır.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'seç -> Ekle (N): satırlar eklenir, değer üst forma bildirilir',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = _service(auth);
        final value = await _pumpField(t, service, auth);
        await tapFinder(t, _key('announcement_add_attachment'));
        await settleFor(t);
        await settleFor(t);
        await tapFinder(t, _key('document_attach_42'));
        await tapFinder(t, _key('document_attach_43'));
        expect(find.text('Ekle (2)'), findsOneWidget);
        await tapFinder(t, _key('document_attach_confirm'));
        await settleFor(t);
        expect(value.map((a) => a.documentId).toSet(), <int>{42, 43});
        expect(find.text('Otopark Planı'), findsOneWidget);
        expect(find.text('Havuz Kuralları'), findsOneWidget);
        // Dosya türü / boyutu belgenin güncel sürümünden gelir.
        expect(find.text('PDF, 2,4 MB'), findsNWidgets(2));
      },
    );

    testWidgets(
      'ek kaldırılır; hiç ek kalmayınca uyarı yerine açıklama gelir',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = _service(auth);
        final value = await _pumpField(
          t,
          service,
          auth,
          initial: <DocumentAttachment>[_att(42, title: 'Otopark Planı')],
        );
        await tapFinder(t, _key('announcement_remove_attachment_42'));
        await settleFor(t);
        expect(value, isEmpty);
        expect(
          find.textContaining('İsterseniz Dosya Deposundaki'),
          findsOneWidget,
        );
        expect(find.textContaining('tüm alıcılarına açılır'), findsNothing);
      },
    );

    testWidgets('5 ek dolunca Belge Ekle kapanır ("En çok 5 belge")', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = _service(auth);
      await _pumpField(
        t,
        service,
        auth,
        initial: <DocumentAttachment>[
          for (var i = 1; i <= 5; i++) _att(100 + i, title: 'Ek $i'),
        ],
        height: 2400,
      );
      expect(find.text('En çok 5 belge'), findsOneWidget);
      expect(find.text('Belge Ekle'), findsNothing);
    });
  });

  group('seçici pencere', () {
    Future<List<DocumentSummary>?> open(
      WidgetTester t,
      FakeDocumentService service,
      DocumentFakeAuth auth, {
      Set<int> exclude = const <int>{},
      int max = 5,
      double width = 400,
      double height = 1200,
      double scale = 1.0,
      bool dark = false,
      void Function(List<DocumentSummary>?)? onResult,
    }) async {
      await openDialogAt(
        t,
        (context) async {
          final result = await DocumentAttachPickerDialog.show(
            context,
            scope: _scope(auth),
            service: service,
            excludeIds: exclude,
            maxSelectable: max,
          );
          onResult?.call(result);
        },
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      await settleFor(t);
      return null;
    }

    layoutMatrix('liste + uyarı + Ekle düğmesi', (t, w, h, s, dark) async {
      final auth = DocumentFakeAuth();
      await open(
        t,
        _service(auth),
        auth,
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Belge Ekle'), findsWidgets);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
      expect(find.text('Ekle'), findsOneWidget);
      expect(
        t.widget<ElevatedButton>(_key('document_attach_confirm')).onPressed,
        isNull,
        reason: 'seçim yokken kapalı',
      );
    });

    testWidgets(
      'seçim yokken pasif "Ekle"nin nedeni yazılır; seçince ipucu kalkar',
      (t) async {
        final auth = DocumentFakeAuth();
        await open(t, _service(auth), auth);
        expect(_key('document_attach_hint'), findsOneWidget);
        expect(
          find.text('Eklemek için en az bir belgeyi işaretleyin.'),
          findsOneWidget,
        );
        expect(
          t.widget<ElevatedButton>(_key('document_attach_confirm')).onPressed,
          isNull,
        );
        await tapFinder(t, _key('document_attach_41'));
        expect(_key('document_attach_hint'), findsNothing);
        expect(
          t.widget<ElevatedButton>(_key('document_attach_confirm')).onPressed,
          isNotNull,
        );
        await tapFinder(t, _key('document_attach_41'));
        expect(
          _key('document_attach_hint'),
          findsOneWidget,
          reason: 'seçim kaldırılınca ipucu döner',
        );
      },
    );

    testWidgets('zaten ekli belgeler listede çıkmaz', (t) async {
      final auth = DocumentFakeAuth();
      await open(t, _service(auth), auth, exclude: <int>{41});
      expect(_key('document_attach_41'), findsNothing);
      expect(_key('document_attach_42'), findsOneWidget);
    });

    testWidgets(
      'kalan kontenjan dolunca diğer satırlar kapanır; seçilen kaldırılabilir',
      (t) async {
        final auth = DocumentFakeAuth();
        await open(t, _service(auth), auth, max: 1);
        await tapFinder(t, _key('document_attach_41'));
        expect(find.text('En çok 1 belge seçilebilir.'), findsOneWidget);
        expect(
          t.widget<CheckboxListTile>(_key('document_attach_42')).onChanged,
          isNull,
        );
        expect(
          t.widget<CheckboxListTile>(_key('document_attach_41')).onChanged,
          isNotNull,
        );
        await tapFinder(t, _key('document_attach_41'));
        expect(
          t.widget<CheckboxListTile>(_key('document_attach_42')).onChanged,
          isNotNull,
        );
      },
    );

    testWidgets('Vazgeç: null döner', (t) async {
      final auth = DocumentFakeAuth();
      var called = false;
      List<DocumentSummary>? result = <DocumentSummary>[];
      await open(
        t,
        _service(auth),
        auth,
        onResult: (r) {
          called = true;
          result = r;
        },
      );
      await tapFinder(t, _key('document_attach_cancel'));
      await settleFor(t);
      expect(called, isTrue);
      expect(result, isNull);
    });

    testWidgets('arama sunucuya gider; sonuç yoksa arama için boş durum', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = _service(auth);
      await open(t, service, auth);
      await t.enterText(_key('document_attach_search'), 'havuz');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t);
      expect(service.listCalls.last.query, 'havuz');
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await t.enterText(_key('document_attach_search'), 'yokböyle');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t);
      expect(find.text('Bu arama için belge bulunamadı.'), findsOneWidget);
    });

    testWidgets(
      'belge hiç yokken yönlendirici boş durum; hata "belge yok" DEMEZ',
      (t) async {
        final auth = DocumentFakeAuth();
        final empty = FakeDocumentService(authService: auth);
        await open(t, empty, auth);
        expect(find.text('Eklenebilecek belge yok.'), findsOneWidget);
        // Yönerge menüdeki gerçek ekran adını söyler ("Belgeler" ekranı artık yok: Dosya Deposu).
        expect(find.textContaining('Dosya Deposu ekranından'), findsOneWidget);
        expect(find.textContaining('Belgeler ekranından'), findsNothing);
      },
    );

    testWidgets('hata: ileti + Tekrar Dene', (t) async {
      final auth = DocumentFakeAuth();
      final service = _service(auth)
        ..listError = ApiException('Bağlantı koptu.');
      await open(t, service, auth);
      expect(find.text('Bağlantı koptu.'), findsOneWidget);
      expect(find.text('Eklenebilecek belge yok.'), findsNothing);
      service.listError = null;
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
    });
  });

  group('Ekler listesi', () {
    Future<List<ShareParams>> pump(
      WidgetTester t,
      FakeDocumentService service,
      List<DocumentAttachment> attachments, {
      double width = 400,
      double height = 1200,
      double scale = 1.0,
      bool dark = false,
    }) async {
      final shared = <ShareParams>[];
      final sharer = DocumentFileSharer(
        shareFn: (p) async {
          shared.add(p);
          return const ShareResult('', ShareResultStatus.success);
        },
        cleanupDelay: Duration.zero,
        sweepStaleOnShare: false,
      );
      await openDialogAt(
        t,
        (context) => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            content: SingleChildScrollView(
              child: DocumentAttachmentsList(
                attachments: attachments,
                sharer: sharer,
                download: (a) =>
                    (onProgress, cancel) =>
                        service.downloadAnnouncementAttachment(
                          41,
                          a.documentId,
                          fallbackName: a.fileName,
                          onProgress: onProgress,
                          cancel: cancel,
                        ),
              ),
            ),
          ),
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      return shared;
    }

    layoutMatrix('kullanılabilir + kullanılamayan ek', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      await pump(
        t,
        _service(auth),
        <DocumentAttachment>[
          _att(42, title: 'Otopark Planı'),
          _att(43, title: 'Silinmiş Belge', available: false),
        ],
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Ekler (2)'), findsOneWidget);
      expect(find.text('Otopark Planı'), findsOneWidget);
      expect(find.text('Artık kullanılamıyor'), findsOneWidget);
      expect(_key('attachment_open_42'), findsOneWidget);
      expect(
        _key('attachment_open_43'),
        findsNothing,
        reason: 'kullanılamayan ek açılamaz',
      );
    });

    testWidgets('Aç / Kaydet: duyuru eki ucundan indirir ve paylaşır', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = _service(auth);
      final shared = await pump(t, service, <DocumentAttachment>[
        _att(42, title: 'Otopark Planı'),
      ]);
      await tapFinder(t, _key('attachment_open_42'));
      await settleFor(t);
      await settleFor(t);
      expect(service.attachmentDownloadCalls.single, (
        announcement: 41,
        document: 42,
      ));
      expect(shared, hasLength(1));
    });

    testWidgets('ek yoksa hiçbir şey çizilmez', (t) async {
      final auth = DocumentFakeAuth();
      await pump(t, _service(auth), const <DocumentAttachment>[]);
      expect(_key('announcement_attachments_list'), findsNothing);
    });

    testWidgets(
      'ekran okuyucu: "Ek: Plan, PDF, 1,0 MB" ve kullanılamayan ek uyarısı',
      (t) async {
        final handle = t.ensureSemantics();
        final auth = DocumentFakeAuth();
        await pump(t, _service(auth), <DocumentAttachment>[
          _att(42, title: 'Plan'),
          _att(43, title: 'Eski', available: false),
        ]);
        expect(find.bySemanticsLabel('Ek: Plan, PDF, 1,0 MB'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Ek: Eski, PDF, 1,0 MB. Artık kullanılamıyor'),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  });

  group('duyuru formu', () {
    PeopleScope scopeOf(AnnouncementFakeAuth auth) => PeopleScope(
      authService: auth,
      siteCode: 11,
      siteName: 'Gül Sitesi',
      canWrite: true,
    );

    Future<void> openForm(
      WidgetTester t,
      AnnouncementFakeAuth auth,
      FakeDocumentService service, {
      AnnouncementDetail? announcement,
      double width = 400,
      double height = 2000,
      double scale = 1.0,
      bool dark = false,
    }) async {
      await openDialogAt(
        t,
        (context) => AnnouncementFormDialog.show(
          context,
          scope: scopeOf(auth),
          announcement: announcement,
          documentService: service,
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
      await settleFor(t);
    }

    AnnouncementFakeAuth auth0() {
      final auth = AnnouncementFakeAuth.seeded();
      final seed = PeopleFakeAuth.seeded();
      auth.apartmentsJson.addAll(seed.apartmentsJson);
      return auth;
    }

    layoutMatrix('form: Belge eki bölümü başlık / metin altında', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = auth0();
      final service = _service(DocumentFakeAuth());
      await openForm(
        t,
        auth,
        service,
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Belge eki'), findsOneWidget);
      expect(_key('announcement_add_attachment'), findsOneWidget);
    });

    testWidgets('modül kapalıyken formda Belge eki bölümü yoktur', (t) async {
      final auth = auth0();
      final service = _service(DocumentFakeAuth())
        ..listError = ApiException(
          'x',
          statusCode: 403,
          code: 'MODULE_DISABLED',
        );
      await openForm(t, auth, service);
      expect(find.text('Belge eki'), findsNothing);
    });

    testWidgets('ekle + taslak kaydet: create çağrısı document_ids taşır', (
      t,
    ) async {
      final auth = auth0();
      final service = _service(DocumentFakeAuth());
      await openForm(t, auth, service);
      await t.enterText(_key('announcement_title'), 'Otopark duyurusu');
      await t.enterText(_key('announcement_body'), 'Plan ektedir.');
      await tapFinder(t, _key('announcement_add_attachment'));
      await settleFor(t);
      await settleFor(t);
      await tapFinder(t, _key('document_attach_42'));
      await tapFinder(t, _key('document_attach_confirm'));
      await settleFor(t);
      await tapFinder(t, find.text('Taslağı Kaydet'));
      await settleFor(t);
      await settleFor(t);
      expect(auth.announcementCreateCalls.single['document_ids'], <int>[42]);
    });

    testWidgets('ek seçilmediyse create document_ids göndermez', (t) async {
      final auth = auth0();
      final service = _service(DocumentFakeAuth());
      await openForm(t, auth, service);
      await t.enterText(_key('announcement_title'), 'Duyuru');
      await t.enterText(_key('announcement_body'), 'Metin');
      await tapFinder(t, find.text('Taslağı Kaydet'));
      await settleFor(t);
      await settleFor(t);
      expect(
        auth.announcementCreateCalls.single.containsKey('document_ids'),
        isFalse,
      );
    });

    testWidgets(
      'taslağı düzenle: mevcut ekler görünür; kaldırınca PATCH document_ids ile ek listesini değiştirir',
      (t) async {
        final auth = auth0();
        auth.rows[50] = annRow(50, title: 'Taslak', status: 'draft');
        auth.rows[50]!['attachments'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'document_id': 42,
            'title': 'Otopark Planı',
            'file_name': 'otopark.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 1048576,
            'available': true,
          },
        ];
        final detail = await auth.getAnnouncement(11, 50);
        expect(detail.attachments.single.documentId, 42);
        final service = _service(DocumentFakeAuth());
        await openForm(t, auth, service, announcement: detail);
        expect(find.text('Otopark Planı'), findsOneWidget);
        await tapFinder(t, _key('announcement_remove_attachment_42'));
        await tapFinder(t, find.text('Taslağı Kaydet'));
        await settleFor(t);
        await settleFor(t);
        final update = auth.announcementUpdateCalls.single;
        expect(update.fields['document_ids'], <int>[]);
      },
    );

    testWidgets('ekler değişmediyse PATCH document_ids göndermez', (t) async {
      final auth = auth0();
      auth.rows[50] = annRow(50, title: 'Taslak', status: 'draft');
      auth.rows[50]!['attachments'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'document_id': 42,
          'title': 'Otopark Planı',
          'available': true,
        },
      ];
      final detail = await auth.getAnnouncement(11, 50);
      final service = _service(DocumentFakeAuth());
      await openForm(t, auth, service, announcement: detail);
      await t.enterText(_key('announcement_title'), 'Yeni başlık');
      await tapFinder(t, find.text('Taslağı Kaydet'));
      await settleFor(t);
      await settleFor(t);
      expect(
        auth.announcementUpdateCalls.single.fields.containsKey('document_ids'),
        isFalse,
      );
    });

    testWidgets('yayınlanmış duyuruda ek bölümü düzenlenemez (kilitli panel)', (
      t,
    ) async {
      final auth = auth0();
      final detail = await auth.getAnnouncement(11, 41);
      final service = _service(DocumentFakeAuth());
      await openForm(t, auth, service, announcement: detail);
      expect(find.text('Belge eki'), findsNothing);
    });
  });

  group('duyuru ayrıntısı ve sakin okuma penceresi', () {
    testWidgets(
      'yönetici ayrıntısı: Ekler listesi; Aç / Kaydet yönetici ucundan indirir',
      (t) async {
        final auth = AnnouncementFakeAuth.seeded();
        auth.rows[41]!['attachments'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'document_id': 42,
            'title': 'Otopark Planı',
            'file_name': 'otopark.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 1048576,
            'available': true,
          },
          <String, dynamic>{
            'document_id': 43,
            'title': 'Silinmiş',
            'available': false,
          },
        ];
        final docs = _service(DocumentFakeAuth());
        await openDialogAt(
          t,
          (context) => showDialog<void>(
            context: context,
            builder: (_) => AnnouncementManageDialog(
              scope: PeopleScope(
                authService: auth,
                siteCode: 11,
                siteName: 'Gül Sitesi',
                canWrite: true,
              ),
              announcementId: 41,
              documentService: docs,
            ),
          ),
          width: 400,
          height: 2400,
          scale: 1.0,
          dark: false,
        );
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Ekler (2)'), findsOneWidget);
        expect(find.text('Artık kullanılamıyor'), findsOneWidget);
        await tapFinder(t, _key('attachment_open_42'));
        await settleFor(t);
        await settleFor(t);
        expect(docs.downloadCalls.single, (id: 42, version: null));
      },
    );

    testWidgets('sakin okuma penceresi: Ekler; indirme duyuru-eki ucundan', (
      t,
    ) async {
      final auth = AnnouncementFakeAuth(
        inbox: [
          annRow(77, title: 'Otopark', status: 'published')
            ..['site_code'] = 11
            ..['site_name'] = 'Gül Sitesi'
            ..['read_at'] = null
            ..['attachments'] = <Map<String, dynamic>>[
              <String, dynamic>{
                'document_id': 42,
                'title': 'Otopark Planı',
                'file_name': 'otopark.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 1048576,
                'available': true,
              },
            ],
        ],
      );
      final docs = _service(DocumentFakeAuth());
      await openDialogAt(
        t,
        (context) => showDialog<void>(
          context: context,
          builder: (_) => AnnouncementReadDialog(
            authService: auth,
            announcement: const ResidentAnnouncement(id: 77),
            documentService: docs,
          ),
        ),
        width: 400,
        height: 2000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Ekler (1)'), findsOneWidget);
      await tapFinder(t, _key('attachment_open_42'));
      await settleFor(t);
      await settleFor(t);
      expect(docs.attachmentDownloadCalls.single, (
        announcement: 77,
        document: 42,
      ));
    });
  });
}
