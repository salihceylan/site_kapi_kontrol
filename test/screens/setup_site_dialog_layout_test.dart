// FAZ 5 / A2-G5: SetupSiteDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog`: başlık şeridi + onay düğmesi sabit, form tek kaydırma alanında; büyük yazıda blok/kapı
// satırları alt alta dizilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';

import 'dialog_layout_harness.dart';
import '../legal_fixtures.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;
  final List<String> setups = [];

  /// setupSite'a iletilen yönetim türleri (Platform modül sistemi Faz 1).
  final List<String?> types = [];

  @override
  Future<Map<String, dynamic>> setupSite({
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>>? doors,
    int doorCount = 1,
    String? deviceUid,
    String? managementType,
  }) async {
    setups.add('$name|${blocks.length}|${doors?.length}|$deviceUid');
    types.add(managementType);
    if (failWith != null) throw ApiException(failWith!);
    return <String, dynamic>{};
  }
}

/// Tooltip'i [prefix] ile başlayan silme düğmeleri (ipucu satır adını da taşır).
Finder _deleteButtons(String prefix) => find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip ?? '').startsWith(prefix),
);

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  String? deviceUid,
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) => openDialogAt(
  t,
  (context) =>
      SetupSiteDialog.show(context, authService: auth, deviceUid: deviceUid),
  width: width,
  height: height,
  scale: scale,
  dark: dark,
);

void main() {
  // Yasal belge uçları sahte: başvuruda onay gerektiren belge yok (DPA kutusu çıkmaz, gönderme açık kalır).
  setUp(() {
    LegalApi.debugDefaultFactory = () => FakeLegalServer(documents: <Map<String, dynamic>>[]).api;
  });
  tearDown(() => LegalApi.debugDefaultFactory = null);

  layoutMatrix('SetupSiteDialog (cihazlı kurulum: bloklar + kapılar)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(),
      deviceUid: 'ESP32_C3_ABCDEF1234567890',
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    expect(find.text('Bağlanacak Cihaz:'), findsOneWidget);
    expect(find.byType(PrimaryActionButton), findsOneWidget);

    // Blok ve kapı ekle: satırlar çoğalır (silme düğmeleri çıkar), taşma olmamalı.
    await scrollTo(t, find.text('Blok Ekle'));
    await t.tap(find.text('Blok Ekle'));
    await settleFor(t);
    await scrollTo(t, find.text('Kapı Ekle'));
    await t.tap(find.text('Kapı Ekle'));
    await settleFor(t);
    // Silme düğmeleri hangi satırı sildiklerini ipucunda söyler (ekran okuyucu etiketi de budur).
    expect(_deleteButtons('Bloğu sil: '), findsNWidgets(2));
    expect(_deleteButtons('Kapıyı sil: '), findsNWidgets(2));
    expect(find.byTooltip('Bloğu sil: A Blok'), findsOneWidget);
    expect(find.byTooltip('Kapıyı sil: Kapı 2'), findsOneWidget);
    await scrollTo(t, _deleteButtons('Kapıyı sil: ').last);

    // Boş site adıyla gönderim: doğrulama iletisi.
    await scrollTo(t, find.byType(PrimaryActionButton));
    await t.tap(find.byType(PrimaryActionButton));
    await settleFor(t);
    await scrollTo(t, find.text('Site adı zorunludur.'));
    expect(find.text('Site adı zorunludur.'), findsOneWidget);
  });

  layoutMatrix('SetupSiteDialog (sunucu hatası: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth(
      failWith:
          'Bu site adı zaten kayıtlı; lütfen farklı bir site adı girin ve yeniden deneyin.',
    );
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await t.enterText(
      find.widgetWithText(TextFormField, 'Site Adı *'),
      'Güneş Sitesi',
    );
    // Büyük yazıda onay düğmesi formun sonundadır: önce görünür alana kaydır.
    await scrollTo(t, find.byType(PrimaryActionButton));
    await t.tap(find.byType(PrimaryActionButton));
    await settleFor(t, 800);

    expect(auth.setups, ['Güneş Sitesi|1|1|null']);
    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.textContaining('Bu site adı zaten kayıtlı'), findsOneWidget);
  });

  testWidgets('SetupSiteDialog: başarıda kapanır', (t) async {
    final auth = _FakeAuth();
    await _open(t, auth, width: 400, height: 900, scale: 1.0, dark: false);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Site Adı *'),
      'Güneş Sitesi',
    );
    await t.tap(find.byType(PrimaryActionButton));
    await settleFor(t, 800);
    expect(auth.setups.length, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  // --- Görsel sözleşme (cilalı safir): R8 açılır liste, ikon rozetleri, kademeli giriş ---

  testWidgets(
    'SetupSiteDialog: il/ilçe listeleri R8 (yuvarlak köşe, yüzey rengi, 320 dp menü, yuvarlak ok)',
    (t) async {
      await _open(
        t,
        _FakeAuth(),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );

      final dropdowns = t
          .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .toList();
      expect(dropdowns, hasLength(2));
      for (final d in dropdowns) {
        expect(d.borderRadius, BorderRadius.circular(AppRadius.md));
        expect(d.dropdownColor, AppPalette.light.surface);
        expect(d.menuMaxHeight, 320);
        expect((d.icon! as Icon).icon, Icons.keyboard_arrow_down_rounded);
      }
    },
  );

  testWidgets(
    'SetupSiteDialog: cihaz paneli ve kapı satırı ikon rozetli; blok/kapı satırları kademeli girişle eklenir',
    (t) async {
      await _open(
        t,
        _FakeAuth(),
        deviceUid: 'ESP32_C3_ABCDEF1234567890',
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );

      // Başlık + cihaz paneli + kapı satırı rozetleri; atama durumu metni korunur.
      expect(find.byType(IconOrb), findsAtLeastNWidgets(3));
      expect(find.text("Kapı 1'e Atanacak"), findsOneWidget);

      // Başlangıçta 1 blok + 1 kapı satırı; eklenince satırlar da kademeli giriş sarmalayıcısındadır.
      expect(find.byType(StaggeredEntry), findsNWidgets(2));
      await scrollTo(t, find.text('Blok Ekle'));
      await t.tap(find.text('Blok Ekle'));
      await settleFor(t);
      await scrollTo(t, find.text('Kapı Ekle'));
      await t.tap(find.text('Kapı Ekle'));
      await settleFor(t);
      expect(find.byType(StaggeredEntry), findsNWidgets(4));
      expect(t.takeException(), isNull);
    },
  );
}
