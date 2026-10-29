// Giriş ekranında "Deneme kodum var" (P2-27, karar K10): düğme, kod diyaloğu, biçimleme, doğrulama, hata gösterimi, başarıda kapanma, taşma.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';

import 'design/harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.result}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  /// null = başarı; metin = hata mesajı; Completer ile beklenen sonuç da verilebilir.
  final Future<String?> Function(String code)? result;
  final List<String> codes = <String>[];
  int logins = 0;

  @override
  String? takeSessionNotice() => null;

  @override
  Future<String?> loginWithTrialCode({required String code}) async {
    codes.add(code);
    final handler = result;
    return handler == null ? null : handler(code);
  }

  @override
  Future<String?> login({required String email, required String password, role}) async {
    logins += 1;
    return null;
  }
}

Future<void> _pumpLogin(WidgetTester t, _FakeAuth auth, {double width = 360, double height = 640, double scale = 1.0, bool dark = false}) {
  return pumpAt(
    t,
    SizedBox(width: width, height: height, child: LoginPage(authService: auth)),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
}

Future<void> _tapText(WidgetTester t, String text) async {
  final target = find.text(text);
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(target);
}

Finder get _dialogField => find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
Finder get _dialogSubmit => find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(ElevatedButton, 'Giriş Yap'));

Future<void> _openDialog(WidgetTester t) async {
  await _tapText(t, 'Deneme kodum var');
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('giriş ekranında "Deneme kodum var" düğmesi vardır; normal giriş öğeleri yerinde kalır', (t) async {
    await _pumpLogin(t, _FakeAuth());
    expect(find.text('Deneme kodum var'), findsOneWidget);
    expect(find.text('Telefonla giriş (SMS)'), findsOneWidget);
    expect(find.text('Giriş Yap'), findsOneWidget, reason: 'diyalog kapalıyken tek "Giriş Yap"');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('düğme diyaloğu açar: başlık, açıklama (72 saat, yalnız demo site), kod alanı', (t) async {
    await _pumpLogin(t, _FakeAuth());
    await _openDialog(t);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Deneme Kodu ile Giriş'), findsOneWidget);
    expect(find.textContaining('72 saat'), findsOneWidget);
    expect(find.textContaining('demo sitede'), findsOneWidget);
    expect(_dialogField, findsOneWidget);
    expect(find.text('Deneme kodu'), findsOneWidget);
    expect(find.text('XXXX-XXXX-XXXX'), findsOneWidget);
  });

  testWidgets('yazılan kod büyük harfe çevrilir ve tireyle gruplanır; gönderilen kod biçimlidir', (t) async {
    final auth = _FakeAuth();
    await _pumpLogin(t, auth);
    await _openDialog(t);
    await t.enterText(_dialogField, 'abcd efgh jkmn');
    await t.pump();
    expect(t.widget<TextFormField>(_dialogField).controller!.text, 'ABCD-EFGH-JKMN');
    await t.tap(_dialogSubmit);
    await t.pumpAndSettle();
    expect(auth.codes, ['ABCD-EFGH-JKMN']);
    expect(find.byType(AlertDialog), findsNothing, reason: 'başarıda diyalog kapanır');
    expect(auth.logins, 0, reason: 'parola girişi çağrılmaz');
  });

  testWidgets('eksik kod: doğrulama hatası, sunucuya gidilmez', (t) async {
    final auth = _FakeAuth();
    await _pumpLogin(t, auth);
    await _openDialog(t);
    await t.enterText(_dialogField, 'abcd-ef');
    await t.tap(_dialogSubmit);
    await t.pump();
    expect(find.text('Kod 12 karakterdir (XXXX-XXXX-XXXX).'), findsOneWidget);
    expect(auth.codes, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('sunucu reddederse (kullanılmış kod) mesaj diyalogda görünür, diyalog açık kalır, yeniden denenebilir', (t) async {
    var attempts = 0;
    final auth = _FakeAuth(
      result: (code) async {
        attempts += 1;
        return attempts == 1 ? 'Bu deneme kodu daha önce kullanılmış. Her kod yalnızca bir kez kullanılabilir.' : null;
      },
    );
    await _pumpLogin(t, auth);
    await _openDialog(t);
    await t.enterText(_dialogField, 'ABCDEFGHJKMN');
    await t.tap(_dialogSubmit);
    await t.pumpAndSettle();
    expect(find.textContaining('daha önce kullanılmış'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(_dialogSubmit);
    await t.pumpAndSettle();
    expect(auth.codes, ['ABCD-EFGH-JKMN', 'ABCD-EFGH-JKMN']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('gönderim sürerken düğmeler pasif (çift gönderim yok)', (t) async {
    final gate = Completer<String?>();
    final auth = _FakeAuth(result: (code) => gate.future);
    await _pumpLogin(t, auth);
    await _openDialog(t);
    await t.enterText(_dialogField, 'ABCDEFGHJKMN');
    await t.tap(_dialogSubmit);
    await t.pump();
    expect(t.widget<ElevatedButton>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ElevatedButton))).onPressed, isNull);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(auth.codes.length, 1);
    gate.complete(null);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('"İptal" diyaloğu kapatır, kod gönderilmez', (t) async {
    final auth = _FakeAuth();
    await _pumpLogin(t, auth);
    await _openDialog(t);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('İptal')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.codes, isEmpty);
  });

  for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('taşma yok: giriş ekranı + kod diyaloğu + uzun hata ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}', (t) async {
        final auth = _FakeAuth(
          result: (code) async =>
              'Çok fazla deneme kodu girişi yapıldı. Güvenlik nedeniyle biraz sonra tekrar denemeniz gerekiyor; bu süre dolmadan yeni giriş denemeleri kabul edilmeyecek.',
        );
        await _pumpLogin(t, auth, width: w, height: h, scale: s, dark: dark);
        expect(t.takeException(), isNull);
        await _openDialog(t);
        expect(t.takeException(), isNull);
        await t.enterText(_dialogField, 'ABCDEFGHJKMN');
        await t.tap(_dialogSubmit);
        await t.pumpAndSettle();
        expect(find.textContaining('Çok fazla deneme kodu'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }
}
