// FAZ 5 / A2-G4: ProfileView ("Profilim") ve ResidentProfileView taşma ve davranış testleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema (pumpAt). Çözülen bulgu: devre dışı
// e-posta alanının yardım metni kırpılıyordu ("E-posta adresi güvenlik ned…"). Doğrulama akışı, alan
// etiketleri ve "Profili Kaydet" düğmesi (E2E turu bunlara metinle bağlıdır) aynı kalır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

const UserSession _session = UserSession(
  token: 'tok',
  id: 1,
  fullName: 'Elif Şahin',
  email: 'elif.sahin@e2e.local',
  loginName: 'elif',
  role: UserRole.individual,
  isActive: true,
);

const UserSession _resident = UserSession(
  token: 'tok',
  id: 81,
  fullName: 'Ali Veli',
  email: 'a1.sakin.1.101@ahbu.local',
  loginName: 'a1.sakin',
  role: UserRole.apartmentOwner,
  isActive: true,
  phoneNumber: '+90 532 000 00 01',
);

class _Form {
  _Form({String name = 'Elif Şahin'})
    : fullName = TextEditingController(text: name),
      email = TextEditingController(text: 'elif.sahin@e2e.local'),
      phone = TextEditingController(),
      password = TextEditingController(),
      current = TextEditingController();

  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController fullName;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController password;
  final TextEditingController current;
  int saves = 0;

  Widget view({bool isSaving = false}) => ProfileView(
    session: _session,
    formKey: key,
    fullNameController: fullName,
    emailController: email,
    phoneController: phone,
    passwordController: password,
    currentPasswordController: current,
    isSaving: isSaving,
    onSave: () {
      if (key.currentState!.validate()) saves++;
    },
  );
}

Future<void> _tapVisible(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
}

void main() {
  group('ProfileView taşma matrisi', () {
    g4LayoutMatrix('form (varsayılan)', (t, width, height, scale, dark) async {
      final form = _Form();
      await pumpAt(
        t,
        form.view(),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Kendi Bilgilerini Düzenle'), findsOneWidget);
      expect(find.text('Ad Soyad'), findsOneWidget);
      expect(find.text('E-posta (Değiştirilemez)'), findsOneWidget);
      expect(
        find.text('E-posta adresi güvenlik nedeniyle değiştirilemez'),
        findsOneWidget,
      );
      expect(find.text('Telefon (opsiyonel)'), findsOneWidget);
      expect(find.text('Mevcut Şifre'), findsOneWidget);
      expect(
        find.text('Şifrenizi değiştirmek için zorunludur'),
        findsOneWidget,
      );
      expect(find.text('Yeni Şifre (opsiyonel)'), findsOneWidget);
      expect(find.text('Profili Kaydet'), findsOneWidget);
    });

    g4LayoutMatrix(
      'doğrulama hataları görünür (kısa ad, yeni şifre + mevcut şifre yok)',
      (t, width, height, scale, dark) async {
        final form = _Form(name: 'ab');
        form.password.text = 'yeni';
        await pumpAt(
          t,
          form.view(),
          width: width,
          height: height,
          scale: scale,
          dark: dark,
        );

        await _tapVisible(t, find.text('Profili Kaydet'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        expect(find.text('Ad Soyad en az 3 karakter olmalı.'), findsOneWidget);
        expect(
          find.text('Şifre değiştirmek için mevcut şifrenizi girin.'),
          findsOneWidget,
        );
        expect(find.text('Şifre en az 6 karakter olmalı.'), findsOneWidget);
        expect(form.saves, 0);
      },
    );

    g4LayoutMatrix('kaydediliyor (düğme devre dışı + gösterge)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final form = _Form();
      await pumpAt(
        t,
        form.view(isSaving: true),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Kaydediliyor...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    });
  });

  group('ResidentProfileView taşma matrisi', () {
    g4LayoutMatrix('salt okunur hesap bilgileri', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        const ResidentProfileView(session: _resident),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Hesap Bilgilerim'), findsOneWidget);
      expect(find.text('Ali Veli'), findsOneWidget);
      expect(find.text('a1.sakin'), findsOneWidget);
      expect(find.text('+90 532 000 00 01'), findsOneWidget);
      expect(find.text(UserRole.apartmentOwner.label), findsOneWidget);
      expect(find.textContaining('site yöneticiniz'), findsOneWidget);
    });

    g4LayoutMatrix('telefonsuz/kullanıcı adsız sakin: yalnız mevcut satırlar', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      const bare = UserSession(
        token: 'tok',
        id: 82,
        fullName: 'Veli Can',
        email: 'v@ahbu.local',
        loginName: null,
        role: UserRole.apartmentOwner,
        isActive: true,
      );
      await pumpAt(
        t,
        const ResidentProfileView(session: bare),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Veli Can'), findsOneWidget);
      expect(find.text('Kullanıcı Adı'), findsNothing);
      expect(find.text('Telefon'), findsNothing);
    });
  });

  group('davranış ve erişilebilirlik', () {
    testWidgets(
      'mevcut doğrulama akışı: yeni şifre + mevcut şifre yok -> hata; mevcut şifre girilince kayıt geçer',
      (t) async {
        final form = _Form();
        await pumpAt(t, form.view(), width: 360, scale: 1.0, height: 1400);

        await t.tap(find.text('Profili Kaydet'));
        await t.pump();
        expect(
          form.saves,
          1,
          reason: 'şifre değişmiyorsa mevcut şifre zorunlu değil',
        );

        await t.enterText(
          find.widgetWithText(TextFormField, 'Yeni Şifre (opsiyonel)'),
          'yeniSifre1',
        );
        await t.tap(find.text('Profili Kaydet'));
        await t.pump();
        expect(form.saves, 1);
        expect(
          find.text('Şifre değiştirmek için mevcut şifrenizi girin.'),
          findsOneWidget,
        );

        await t.enterText(
          find.widgetWithText(TextFormField, 'Mevcut Şifre'),
          'eskiSifre1',
        );
        await t.tap(find.text('Profili Kaydet'));
        await t.pump();
        expect(form.saves, 2);
      },
    );

    testWidgets(
      'e-posta alanı devre dışı ve okunur: metin ikincil renk, yardım metni 2 satıra kadar sarar (kırpılmaz)',
      (t) async {
        final form = _Form();
        // 412 px: test yazı tipi (her harf tam em) yardım metnini 2 satırda sığdırır.
        await pumpAt(t, form.view(), width: 412, scale: 1.0, height: 1800);

        final emailField = t.widget<TextField>(
          find.widgetWithText(TextField, 'E-posta (Değiştirilemez)'),
        );
        expect(emailField.enabled, isFalse);
        expect(emailField.style!.color, AppPalette.light.textSecondary);
        expect(
          emailField.decoration!.helperMaxLines,
          2,
          reason: 'eski tek satır sınırı yardım metnini kırpıyordu',
        );
        expect(
          g4IsEllipsized(
            t,
            find.text('E-posta adresi güvenlik nedeniyle değiştirilemez'),
          ),
          isFalse,
        );

        // Mevcut şifre alanının yardım metni de aynı (mevcut) sınırı korur.
        final current = t.widget<TextField>(
          find.widgetWithText(TextField, 'Mevcut Şifre'),
        );
        expect(current.decoration!.helperMaxLines, 2);
      },
    );

    testWidgets(
      'koyu temada devre dışı e-posta alanı da okunur (ikincil renk koyu zeminde)',
      (t) async {
        final form = _Form();
        await pumpAt(
          t,
          form.view(),
          width: 360,
          scale: 1.0,
          height: 1800,
          dark: true,
        );

        final emailField = t.widget<TextField>(
          find.widgetWithText(TextField, 'E-posta (Değiştirilemez)'),
        );
        expect(emailField.style!.color, AppPalette.dark.textSecondary);
        expect(emailField.decoration!.fillColor, AppPalette.dark.surfaceMuted);
      },
    );

    testWidgets(
      'kaydet düğmesi ElevatedButton olarak kalır; kayıt sürerken gösterge, bitince simge',
      (t) async {
        final form = _Form();
        await pumpAt(t, form.view(), width: 360, scale: 1.0, height: 1400);
        expect(
          find.widgetWithText(ElevatedButton, 'Profili Kaydet'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.save_outlined), findsOneWidget);

        await pumpAt(
          t,
          form.view(isSaving: true),
          width: 360,
          scale: 1.0,
          height: 1400,
        );
        expect(find.byIcon(Icons.save_outlined), findsNothing);
        expect(
          find.widgetWithText(ElevatedButton, 'Kaydediliyor...'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'kart başlığı anlamsal başlık bayrağını taşır (ProfileView ve ResidentProfileView)',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(t, _Form().view(), width: 360, scale: 1.0, height: 1400);
        expect(
          t.getSemantics(find.text('Kendi Bilgilerini Düzenle')),
          isSemantics(isHeader: true),
        );

        await pumpAt(
          t,
          const ResidentProfileView(session: _resident),
          width: 360,
          scale: 1.0,
          height: 900,
        );
        expect(
          t.getSemantics(find.text('Hesap Bilgilerim')),
          isSemantics(isHeader: true),
        );
        handle.dispose();
      },
    );
  });
}
