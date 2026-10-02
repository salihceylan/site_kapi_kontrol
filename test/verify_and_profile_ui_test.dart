import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/pages/verify_email_code_page.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';

class _NoticeAuthService extends AuthService {
  _NoticeAuthService({this.notice, this.loginError})
      : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? notice;
  final String? loginError;
  int noticeReads = 0;

  @override
  String? takeSessionNotice() {
    noticeReads++;
    return noticeReads == 1 ? notice : null;
  }

  @override
  Future<String?> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    return loginError;
  }
}

class _RecordingAuthService extends AuthService {
  _RecordingAuthService() : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<String> verifiedCodes = <String>[];
  int resendCalls = 0;

  @override
  Future<String?> verifyIndividualCode({
    required String email,
    required String code,
  }) async {
    verifiedCodes.add(code);
    return 'Kod hatalı.';
  }

  @override
  Future<String?> resendIndividualCode({required String email}) async {
    resendCalls++;
    return null;
  }
}

void main() {
  group('VerifyEmailCodePage (6 haneli kod)', () {
    Future<_RecordingAuthService> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = _RecordingAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: VerifyEmailCodePage(authService: auth, email: 'ali@example.com'),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('alan en fazla 6 rakam kabul eder ve taşma yapmaz (320 px)', (tester) async {
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '12ab3456789');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '123456');
      expect(field.maxLength, 6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4 haneli kod reddedilir ve 6 hane istendiği söylenir', (tester) async {
      final auth = await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Hesabımı Doğrula'));
      await tester.pump();

      expect(
        find.text('Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz.'),
        findsOneWidget,
      );
      expect(auth.verifiedCodes, isEmpty, reason: 'eksik kod sunucuya gönderilmemeli');
      expect(tester.takeException(), isNull);
    });

    testWidgets('6 haneli kod sunucuya iletilir', (tester) async {
      final auth = await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '482913');
      await tester.tap(find.text('Hesabımı Doğrula'));
      await tester.pumpAndSettle();

      expect(auth.verifiedCodes, ['482913']);
      expect(find.text('Kod hatalı.'), findsOneWidget);
    });

    testWidgets('yeniden gönderme mesajı 6 haneli kodu anar (bekleme süresi dolunca)', (tester) async {
      final auth = await pumpPage(tester);

      // Sunucu 30 sn içindeki isteği sessizce yutar: bu sürede düğme pasiftir.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Kodu Tekrar Gönder'), findsOneWidget);

      await tester.tap(find.text('Kodu Tekrar Gönder'));
      await tester.pumpAndSettle();

      expect(auth.resendCalls, 1);
      // Kullanıcı varlığını ele vermeyen, teslimatı kesinmiş gibi yazmayan, her durumda aynı metin.
      expect(
        find.text(
          'Bu e-posta adresi için bekleyen bir doğrulama varsa yeni 6 haneli kod birkaç dakika içinde e-postanıza ulaşır. Ulaşmazsa spam klasörünü kontrol edin.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('kod yeniden gönderme: 30 sn geri sayım, düğme pasif, her başarıdan sonra yeniden başlar (320 px)',
        (tester) async {
      final auth = await pumpPage(tester);

      TextButton resendButton() => tester.widget<TextButton>(
            find.byWidgetPredicate((w) => w is TextButton),
          );

      // İlk açılış: kod az önce gönderildi -> geri sayım.
      expect(find.text('Kodu Tekrar Gönder (30 sn)'), findsOneWidget);
      expect(resendButton().onPressed, isNull);
      await tester.tap(find.text('Kodu Tekrar Gönder (30 sn)'), warnIfMissed: false);
      await tester.pump();
      expect(auth.resendCalls, 0, reason: 'bekleme süresinde istek gönderilmemeli');

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Kodu Tekrar Gönder (29 sn)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 29));
      expect(find.text('Kodu Tekrar Gönder'), findsOneWidget);
      expect(resendButton().onPressed, isNotNull);

      await tester.tap(find.text('Kodu Tekrar Gönder'));
      await tester.pumpAndSettle();
      expect(auth.resendCalls, 1);
      expect(find.text('Kodu Tekrar Gönder (30 sn)'), findsOneWidget,
          reason: 'başarılı istekten sonra bekleme süresi yeniden işler');
      expect(resendButton().onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('LoginPage oturum bildirimi ve kilit mesajı', () {
    testWidgets('sunucu tarafında sonlandırılan oturumun nedeni bir kez gösterilir (320 px)', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = _NoticeAuthService(
        notice:
            'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.',
      );
      await tester.pumpWidget(MaterialApp(home: LoginPage(authService: auth)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(
          'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.',
        ),
        findsOneWidget,
      );
      expect(auth.noticeReads, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LOGIN_LOCKED mesajı uzun olsa da taşmadan gösterilir', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = _NoticeAuthService(
        loginError: 'Çok fazla hatalı deneme yapıldı. 5 dakika sonra tekrar deneyin.',
      );
      await tester.pumpWidget(MaterialApp(home: LoginPage(authService: auth)));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'ali@example.com');
      await tester.enterText(fields.at(1), 'parola123');
      await tester.tap(find.text('Giriş Yap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Çok fazla hatalı deneme yapıldı. 5 dakika sonra tekrar deneyin.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ProfileView (C8 mevcut şifre)', () {
    final session = UserSession(
      id: 1,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: UserRole.individual,
      isActive: true,
      token: 't',
    );

    testWidgets('yeni şifre girilip mevcut şifre boşsa doğrulama hatası verir', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final formKey = GlobalKey<FormState>();
      final name = TextEditingController(text: 'Ali Veli');
      final email = TextEditingController(text: 'ali@example.com');
      final phone = TextEditingController();
      final password = TextEditingController();
      final current = TextEditingController();
      var saved = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileView(
                session: session,
                formKey: formKey,
                fullNameController: name,
                emailController: email,
                phoneController: phone,
                passwordController: password,
                currentPasswordController: current,
                isSaving: false,
                onSave: () {
                  if (formKey.currentState!.validate()) saved++;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Mevcut Şifre'), findsOneWidget);
      expect(find.text('Yeni Şifre (opsiyonel)'), findsOneWidget);

      // Şifre değişmiyorsa mevcut şifre zorunlu değildir.
      await tester.tap(find.text('Profili Kaydet'));
      await tester.pump();
      expect(saved, 1);

      // Yeni şifre yazılınca mevcut şifre zorunlu olur.
      await tester.enterText(find.widgetWithText(TextFormField, 'Yeni Şifre (opsiyonel)'), 'yeniSifre1');
      await tester.tap(find.text('Profili Kaydet'));
      await tester.pump();
      expect(saved, 1);
      expect(find.text('Şifre değiştirmek için mevcut şifrenizi girin.'), findsOneWidget);

      // Mevcut şifre girilince kayıt geçer.
      await tester.enterText(find.widgetWithText(TextFormField, 'Mevcut Şifre'), 'eskiSifre1');
      await tester.tap(find.text('Profili Kaydet'));
      await tester.pump();
      expect(saved, 2);
      expect(tester.takeException(), isNull);
    });
  });
}
