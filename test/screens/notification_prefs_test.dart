// Platform Faz 3a: Profil -> "Bildirim Tercihleri" (NotificationPrefsSection).
//
// "E-posta ile duyuru al" anahtarı (kapalıyken normal duyurular e-postayla gelmez; ACİL duyurular her zaman
// gider) ve pasif "Telefon bildirimi — Yakında…". Yükleniyor / hata dürüsttür (varsayılan anahtar çizilmez),
// kayıt sürerken anahtar kilitli, başarısız kayıt eski değere döner ve hata görünür kalır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart' show AppTone;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/notification_prefs_section.dart';

import 'announcement_fixtures.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';

AnnouncementFakeAuth _auth() => AnnouncementFakeAuth(role: UserRole.apartmentOwner);

Future<void> _pump(
  WidgetTester t,
  AnnouncementFakeAuth auth, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpList(
    t,
    NotificationPrefsSection(authService: auth),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
}

const ValueKey<String> _emailKey = ValueKey<String>('notification_email_switch');
const ValueKey<String> _financeKey = ValueKey<String>('notification_finance_reminders_switch');

const String _financeSubtitle =
    'Aidat borcunuz için site yönetiminin gönderdiği hatırlatma e-postaları. Kapalıyken bu '
    'hatırlatmalar e-postayla gelmez; duyurular ve borç bilgileriniz uygulamada görünmeye devam eder.';

/// Duyuru anahtarının `Switch`'i (bölümde artık İKİ anahtar var: `find.byType(Switch)` tek başına belirsiz).
Finder get _emailSwitch => find.descendant(of: find.byKey(_emailKey), matching: find.byType(Switch));

Finder get _financeSwitchFinder => find.descendant(of: find.byKey(_financeKey), matching: find.byType(Switch));

Switch _switch(WidgetTester t) => t.widget<Switch>(_emailSwitch);

Switch _financeSwitch(WidgetTester t) => t.widget<Switch>(_financeSwitchFinder);

void main() {
  group('taşma matrisi', () {
    listMatrix('dolu: anahtar, açıklama, pasif "Telefon bildirimi — Yakında…"', (t, w, h, s, dark) async {
      await _pump(t, _auth(), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Bildirim Tercihleri'), findsOneWidget);
      expect(find.text('E-posta ile duyuru al'), findsOneWidget);
      expect(
        find.text(
          'Kapalıyken normal duyurular e-postayla gelmez. Acil duyuruların e-postası tercihinizden '
          'etkilenmez; uygulamada her zaman görünürler.',
        ),
        findsOneWidget,
      );
      expect(find.text('Telefon bildirimi'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2), reason: 'telefon bildirimi için anahtar yok');
      expect(find.text('Borç hatırlatma e-postaları'), findsOneWidget);
      expect(find.text(_financeSubtitle), findsOneWidget);
      expect(_switch(t).value, isTrue);
      expect(_financeSwitch(t).value, isTrue);
    });

    listMatrix('bastırılmış adres: kapalı anahtar + not + bilgi notu', (t, w, h, s, dark) async {
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSuppressionPersists = true;
      // Profil sayfasında bölüm kaydırılan sayfanın içindedir: burada da kaydırılabilir kabuk.
      await pumpList(
        t,
        SingleChildScrollView(child: NotificationPrefsSection(authService: auth)),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t, 100);
      expect(find.text('E-posta bildirimleri e-postadaki bağlantıyla durduruldu.'), findsOneWidget);
      await t.ensureVisible(_emailSwitch);
      await t.pump();
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(find.text('Bu adres için e-posta bildirimleri yönetici/destek ile açılabilir.'), findsOneWidget);
      expect(_switch(t).value, isFalse);
    });

    listMatrix('yükleniyor: iskelet, anahtar yok', (t, w, h, s, dark) async {
      final auth = _auth()..prefsGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    listMatrix('hata: anahtar ÇİZİLMEZ (yanlış değer göstermesin), Tekrar Dene', (t, w, h, s, dark) async {
      final auth = _auth()..prefsError = ApiException('Tercihler şu an alınamadı.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Tercihler şu an alınamadı.'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      auth.prefsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(Switch), findsNWidgets(2), reason: 'duyuru + borç hatırlatma anahtarı');
    });
  });

  group('davranış', () {
    testWidgets('anahtar sunucudaki değeri gösterir; kapatınca PUT gider ve değer kalıcı olur', (t) async {
      final auth = _auth()..prefsEmail = true;
      await _pump(t, auth);
      expect(_switch(t).value, isTrue);
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(auth.prefsSetCalls, <bool>[false]);
      expect(_switch(t).value, isFalse);
      expect(auth.prefsEmail, isFalse);

      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(auth.prefsSetCalls, <bool>[false, true]);
      expect(_switch(t).value, isTrue);
    });

    testWidgets('kayıt sürerken anahtar kilitli (çift dokunuş tek istek)', (t) async {
      final auth = _auth()..prefsSaveGate = Completer<void>();
      await _pump(t, auth);
      await t.tap(_emailSwitch);
      await t.pump();
      expect(auth.prefsSetCalls, <bool>[false]);
      expect(_switch(t).onChanged, isNull, reason: 'kayıt sürerken kilitli');
      await t.tap(_emailSwitch, warnIfMissed: false);
      await t.pump();
      expect(auth.prefsSetCalls.length, 1);
      auth.prefsSaveGate!.complete();
      await settleFor(t);
      expect(_switch(t).onChanged, isNotNull);
      expect(_switch(t).value, isFalse);
    });

    testWidgets('kayıt BAŞARISIZ olursa eski değere döner ve hata görünür kalır', (t) async {
      final auth = _auth()..prefsSaveError = ApiException('Tercih kaydedilemedi (deneme).');
      await _pump(t, auth);
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(_switch(t).value, isTrue, reason: 'sunucuya yazılamadı: eski değer');
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(auth.prefsEmail, isTrue);

      auth.prefsSaveError = null;
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsNothing);
      expect(_switch(t).value, isFalse);
    });

    testWidgets('bastırılmış adres (email_suppressed): anahtar KAPALI ve altında not; PUT gitmez, bilgi notu yok', (t) async {
      final auth = _auth()
        ..prefsEmail = true
        ..prefsSuppressed = true;
      await _pump(t, auth);
      expect(_switch(t).value, isFalse, reason: 'etkin değer false: bastırılmış adrese e-posta gitmez');
      expect(find.text('E-posta bildirimleri e-postadaki bağlantıyla durduruldu.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      expect(auth.prefsSetCalls, isEmpty);
    });

    testWidgets('bastırılmışken anahtarı AÇINCA PUT true gider, bastırma kalkar: anahtar açık kalır, not kaybolur', (t) async {
      final auth = _auth()..prefsSuppressed = true;
      await _pump(t, auth);
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(auth.prefsSetCalls, <bool>[true]);
      expect(_switch(t).value, isTrue);
      expect(find.text('E-posta bildirimleri e-postadaki bağlantıyla durduruldu.'), findsNothing);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      expect(find.byType(Switch), findsNWidgets(2), reason: 'duyuru + borç hatırlatma anahtarı');
      // Sunucu tarafında da kalktı: yeniden yüklenince açık.
      await t.state<NotificationPrefsSectionState>(find.byType(NotificationPrefsSection)).reload();
      await settleFor(t);
      expect(_switch(t).value, isTrue);
    });

    testWidgets('bastırılmışken AÇ -> yanıt HÂLÂ bastırılmış (dahili hesap adresi): anahtar kapalı kalır, hata değil BİLGİ notu', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSuppressionPersists = true;
      await _pump(t, auth);
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(auth.prefsSetCalls, <bool>[true]);
      expect(_switch(t).value, isFalse, reason: 'sunucu hâlâ bastırılmış: anahtar kapalı kalır');
      expect(find.text('E-posta bildirimleri e-postadaki bağlantıyla durduruldu.'), findsOneWidget);
      final info = find.byKey(const ValueKey<String>('notification_support_note'));
      expect(info, findsOneWidget);
      expect(
        find.descendant(of: info, matching: find.text('Bu adres için e-posta bildirimleri yönetici/destek ile açılabilir.')),
        findsOneWidget,
      );
      expect(t.widget<InlineNotice>(info).tone, AppTone.info, reason: 'hata tonu değil, bilgi tonu');
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing, reason: 'hata simgesi yok');
      // Anahtar tekrar kullanılabilir (kilitli değil).
      expect(_switch(t).onChanged, isNotNull);
      semantics.dispose();
    });

    testWidgets('bastırılmışken AÇ ama kayıt BAŞARISIZ: eski duruma döner (kapalı + not), hata görünür', (t) async {
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSaveError = ApiException('Tercih kaydedilemedi (deneme).');
      await _pump(t, auth);
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(_switch(t).value, isFalse);
      expect(find.text('E-posta bildirimleri e-postadaki bağlantıyla durduruldu.'), findsOneWidget);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      expect(auth.prefsSuppressed, isTrue);
    });

    testWidgets('eski sunucu (email_suppressed alanı yok): not hiç çıkmaz, mevcut davranış', (t) async {
      final auth = _auth()
        ..prefsLegacy = true
        ..prefsEmail = true;
      await _pump(t, auth);
      expect(_switch(t).value, isTrue);
      expect(find.textContaining('durduruldu'), findsNothing);
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(_switch(t).value, isFalse);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
    });

    testWidgets('hesap değişince (yeni servis) önceki hesabın tercihi sızmaz, yeniden yüklenir', (t) async {
      final first = _auth()..prefsEmail = false;
      final second = _auth()..prefsEmail = true;
      final host = ValueNotifier<AnnouncementFakeAuth>(first);
      addTearDown(host.dispose);
      await pumpList(
        t,
        ValueListenableBuilder<AnnouncementFakeAuth>(
          valueListenable: host,
          builder: (context, auth, _) => NotificationPrefsSection(authService: auth),
        ),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(_switch(t).value, isFalse);

      second.prefsGate = Completer<void>();
      host.value = second;
      await t.pump();
      expect(find.byType(Switch), findsNothing, reason: 'eski hesabın değeri gösterilmez');
      second.prefsGate!.complete();
      await settleFor(t);
      expect(_switch(t).value, isTrue);
    });

    testWidgets('kapanırken uçuştaki yanıt çökmez', (t) async {
      final auth = _auth()..prefsGate = Completer<void>();
      await _pump(t, auth);
      await t.pumpWidget(const SizedBox());
      auth.prefsGate!.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  // Faz 4b: aidat borç hatırlatma e-postası anahtarı (aidat borç e-postasının altbilgisi "Bildirim Tercihleri"ne
  // yönlendirir). Duyuru anahtarıyla AYNI kalıp: sürerken kilit, başarısızsa geri alma, jeton, bastırma notu.
  group('borç hatırlatma e-postaları', () {
    const suppressed = 'E-posta bildirimleri e-postadaki bağlantıyla durduruldu.';
    const support = 'Bu adres için e-posta bildirimleri yönetici/destek ile açılabilir.';

    listMatrix('dolu: ikinci anahtar, başlık ve açıklama çizilir; ikisi de açık', (t, w, h, s, dark) async {
      await _pump(t, _auth(), width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(_financeKey), findsOneWidget);
      expect(find.text('Borç hatırlatma e-postaları'), findsOneWidget);
      expect(find.text(_financeSubtitle), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      expect(_switch(t).value, isTrue);
      expect(_financeSwitch(t).value, isTrue);
      // Telefon bildirimi satırı ikinci anahtarın ARKASINDA kalmaz (sıra: duyuru, borç, telefon).
      final emailY = t.getTopLeft(find.byKey(_emailKey)).dy;
      final financeY = t.getTopLeft(find.byKey(_financeKey)).dy;
      expect(financeY, greaterThan(emailY));
      expect(t.getTopLeft(find.text('Telefon bildirimi')).dy, greaterThan(financeY));
    });

    listMatrix('iki anahtar da bastırılmış: ikisi kapalı, not BİR kez', (t, w, h, s, dark) async {
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSuppressionPersists = true;
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(_switch(t).value, isFalse);
      expect(_financeSwitch(t).value, isFalse);
      expect(find.text(suppressed), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_suppressed_note')), findsOneWidget);
      // Borç anahtarını aç: bastırma sürer -> bilgi notu (hata değil), anahtar kapalı, açık not hâlâ BİR kez.
      await t.ensureVisible(_financeSwitchFinder);
      await t.pump();
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(find.text(support), findsOneWidget);
      expect(find.text(suppressed), findsOneWidget);
      expect(_financeSwitch(t).value, isFalse);
    });

    listMatrix('borç hatırlatma kapalı + duyuru açık; kayıt hatası görünür', (t, w, h, s, dark) async {
      final auth = _auth()
        ..prefsFinance = false
        ..prefsSaveError = ApiException('Tercih kaydedilemedi (deneme).');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(_switch(t).value, isTrue);
      expect(_financeSwitch(t).value, isFalse);
      await t.ensureVisible(_financeSwitchFinder);
      await t.pump();
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(_financeSwitch(t).value, isFalse, reason: 'yazılamadı: eski değer');
    });

    // 640x360 x2,0 yatay (AGENTS.md kural 6): kaydırılan sayfa kabuğunda iki anahtar + bastırma notu + bilgi notu.
    for (final dark in const <bool>[false, true]) {
      final theme = dark ? 'koyu' : 'açık';
      testWidgets('yatay 640x360 x2,0 $theme tema: iki anahtar, taşma yok', (t) async {
        await _pump(t, _auth(), width: 640, height: 360, scale: 2.0, dark: dark);
        expect(find.byType(Switch), findsNWidgets(2));
        expect(find.text('Borç hatırlatma e-postaları'), findsOneWidget);
        expect(find.text(_financeSubtitle), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('yatay 640x360 x2,0 $theme tema: bastırılmış + bilgi notu, taşma yok', (t) async {
        final auth = _auth()
          ..prefsSuppressed = true
          ..prefsSuppressionPersists = true;
        await _pump(t, auth, width: 640, height: 360, scale: 2.0, dark: dark);
        expect(find.text(suppressed), findsOneWidget);
        await t.ensureVisible(_financeSwitchFinder);
        await t.pump();
        await t.tap(_financeSwitchFinder);
        await settleFor(t);
        expect(find.text(support), findsOneWidget);
        expect(find.text(suppressed), findsOneWidget);
        expect(find.byType(Switch), findsNWidgets(2));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('anahtar sunucudaki değeri gösterir (borç kapalı, duyuru açık) ve ikisi birbirinden bağımsızdır', (t) async {
      final auth = _auth()
        ..prefsEmail = true
        ..prefsFinance = false;
      await _pump(t, auth);
      expect(_switch(t).value, isTrue);
      expect(_financeSwitch(t).value, isFalse);
      expect(auth.prefsSetRequests, isEmpty, reason: 'yükleme PUT göndermez');
    });

    testWidgets('kapatınca PUT YALNIZ email_finance_reminders gider; duyuru anahtarı ve sunucu değeri değişmez', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(auth.prefsSetRequests, [(announcements: null, finance: false)]);
      expect(auth.prefsFinanceSetCalls, <bool>[false]);
      expect(auth.prefsSetCalls, isEmpty, reason: 'email_announcements gövdede yok');
      expect(_financeSwitch(t).value, isFalse);
      expect(_switch(t).value, isTrue, reason: 'duyuru anahtarı değişmedi');
      expect(auth.prefsFinance, isFalse);
      expect(auth.prefsEmail, isTrue);

      // Yeniden aç.
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(auth.prefsFinanceSetCalls, <bool>[false, true]);
      expect(_financeSwitch(t).value, isTrue);
    });

    testWidgets('iki anahtar birbirini ezmez: her kayıt yalnız kendi anahtarını gönderir, durum yeniden yüklemede de korunur', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder); // borç kapat
      await settleFor(t);
      await t.tap(_emailSwitch); // duyuru kapat
      await settleFor(t);
      expect(_switch(t).value, isFalse);
      expect(_financeSwitch(t).value, isFalse, reason: 'duyuruyu kapatmak borç tercihini geri açmaz');
      await t.tap(_financeSwitchFinder); // borç aç
      await settleFor(t);
      expect(_switch(t).value, isFalse, reason: 'borcu açmak duyuru tercihini açmaz');
      expect(_financeSwitch(t).value, isTrue);
      expect(auth.prefsSetRequests, [
        (announcements: null, finance: false),
        (announcements: false, finance: null),
        (announcements: null, finance: true),
      ]);
      await t.state<NotificationPrefsSectionState>(find.byType(NotificationPrefsSection)).reload();
      await settleFor(t);
      expect(_switch(t).value, isFalse);
      expect(_financeSwitch(t).value, isTrue);
      expect(auth.prefsEmail, isFalse);
      expect(auth.prefsFinance, isTrue);
    });

    testWidgets('kayıt sürerken İKİ anahtar da kilitli (çift dokunuş / çapraz dokunuş tek istek)', (t) async {
      final auth = _auth()..prefsSaveGate = Completer<void>();
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await t.pump();
      expect(auth.prefsSetRequests.length, 1);
      expect(_financeSwitch(t).onChanged, isNull, reason: 'kayıt sürerken kilitli');
      expect(_switch(t).onChanged, isNull, reason: 'öteki anahtar da kilitli: eşzamanlı kayıt yok');
      await t.tap(_financeSwitchFinder, warnIfMissed: false);
      await t.tap(_emailSwitch, warnIfMissed: false);
      await t.pump();
      expect(auth.prefsSetRequests.length, 1);
      auth.prefsSaveGate!.complete();
      await settleFor(t);
      expect(_financeSwitch(t).onChanged, isNotNull);
      expect(_switch(t).onChanged, isNotNull);
      expect(_financeSwitch(t).value, isFalse);
      expect(_switch(t).value, isTrue);
    });

    testWidgets('kayıt BAŞARISIZ olursa borç anahtarı eski değere döner, duyuru değişmez, hata görünür kalır', (t) async {
      final auth = _auth()..prefsSaveError = ApiException('Tercih kaydedilemedi (deneme).');
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(_financeSwitch(t).value, isTrue, reason: 'sunucuya yazılamadı: eski değer');
      expect(_switch(t).value, isTrue);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(auth.prefsFinance, isTrue);

      auth.prefsSaveError = null;
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsNothing);
      expect(_financeSwitch(t).value, isFalse);
      expect(auth.prefsFinance, isFalse);
    });

    testWidgets('bastırılmış adres: borç anahtarı KAPALI (duyuruyla birlikte), not BİR kez, PUT gitmez', (t) async {
      final auth = _auth()
        ..prefsFinance = true
        ..prefsSuppressed = true;
      await _pump(t, auth);
      expect(_financeSwitch(t).value, isFalse, reason: 'etkin değer false: bastırılmış adrese e-posta gitmez');
      expect(_switch(t).value, isFalse);
      expect(find.text(suppressed), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_suppressed_note')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      expect(auth.prefsSetRequests, isEmpty);
    });

    testWidgets('bastırılmışken borç anahtarını AÇINCA PUT yalnız finance:true gider, bastırma kalkar, not kaybolur', (t) async {
      final auth = _auth()..prefsSuppressed = true;
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(auth.prefsSetRequests, [(announcements: null, finance: true)]);
      expect(_financeSwitch(t).value, isTrue);
      expect(find.text(suppressed), findsNothing);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      // Bastırma ADRES düzeyindedir: kalkınca saklanan duyuru tercihi (açık) de etkinleşir; ekran sunucu
      // yanıtını olduğu gibi gösterir.
      expect(_switch(t).value, isTrue);
    });

    testWidgets('bastırılmışken borç AÇ -> yanıt HÂLÂ bastırılmış: anahtar kapalı kalır, hata değil BİLGİ notu', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSuppressionPersists = true;
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(auth.prefsSetRequests, [(announcements: null, finance: true)]);
      expect(_financeSwitch(t).value, isFalse, reason: 'sunucu hâlâ bastırılmış: anahtar kapalı kalır');
      expect(find.text(suppressed), findsOneWidget);
      final info = find.byKey(const ValueKey<String>('notification_support_note'));
      expect(info, findsOneWidget);
      expect(find.descendant(of: info, matching: find.text(support)), findsOneWidget);
      expect(t.widget<InlineNotice>(info).tone, AppTone.info, reason: 'hata tonu değil, bilgi tonu');
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing, reason: 'hata simgesi yok');
      expect(_financeSwitch(t).onChanged, isNotNull);
      semantics.dispose();
    });

    testWidgets('bastırılmışken borç AÇ ama kayıt BAŞARISIZ: eski duruma döner (kapalı + not), hata görünür', (t) async {
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSaveError = ApiException('Tercih kaydedilemedi (deneme).');
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(_financeSwitch(t).value, isFalse);
      expect(_switch(t).value, isFalse);
      expect(find.text(suppressed), findsOneWidget);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      expect(auth.prefsSuppressed, isTrue);
    });

    testWidgets('bilgi notu başka bir tercih kaydedilince kalkar', (t) async {
      final auth = _auth()
        ..prefsSuppressed = true
        ..prefsSuppressionPersists = true;
      await _pump(t, auth);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsOneWidget);
      auth.prefsSuppressionPersists = false;
      await t.tap(_emailSwitch);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('notification_support_note')), findsNothing);
      expect(_switch(t).value, isTrue);
    });

    testWidgets('eski sunucu (alan yok): borç anahtarı açık varsayılır; kapatınca istenen değer geçerli', (t) async {
      final auth = _auth()..prefsLegacy = true;
      await _pump(t, auth);
      expect(_financeSwitch(t).value, isTrue);
      expect(find.text(suppressed), findsNothing);
      await t.tap(_financeSwitchFinder);
      await settleFor(t);
      expect(auth.prefsSetRequests, [(announcements: null, finance: false)]);
      expect(_financeSwitch(t).value, isFalse);
    });

    testWidgets('hesap değişince önceki hesabın borç tercihi sızmaz', (t) async {
      final first = _auth()..prefsFinance = false;
      final second = _auth()..prefsFinance = true;
      final host = ValueNotifier<AnnouncementFakeAuth>(first);
      addTearDown(host.dispose);
      await pumpList(
        t,
        ValueListenableBuilder<AnnouncementFakeAuth>(
          valueListenable: host,
          builder: (context, auth, _) => NotificationPrefsSection(authService: auth),
        ),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(_financeSwitch(t).value, isFalse);

      second.prefsGate = Completer<void>();
      host.value = second;
      await t.pump();
      expect(find.byKey(_financeKey), findsNothing, reason: 'eski hesabın değeri gösterilmez');
      second.prefsGate!.complete();
      await settleFor(t);
      expect(_financeSwitch(t).value, isTrue);
    });

    testWidgets('anlam ağacı: iki anahtar da etiketli ve ekran okuyucuya açık', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(t, _auth());
      final labels = semanticLabels(t).join('\n');
      expect(labels, contains('E-posta ile duyuru al'));
      expect(labels, contains('Borç hatırlatma e-postaları'));
      semantics.dispose();
    });
  });
}
