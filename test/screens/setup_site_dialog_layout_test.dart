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
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';

import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;
  final List<String> setups = [];

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
  }) async {
    setups.add('$name|${blocks.length}|${doors?.length}|$deviceUid');
    if (failWith != null) throw ApiException(failWith!);
    return <String, dynamic>{};
  }
}

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
    expect(find.byTooltip('Bloğu Sil'), findsNWidgets(2));
    expect(find.byTooltip('Kapıyı Sil'), findsNWidgets(2));
    await scrollTo(t, find.byTooltip('Kapıyı Sil').last);

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
}
