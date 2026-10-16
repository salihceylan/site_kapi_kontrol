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
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
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

Switch _switch(WidgetTester t) => t.widget<Switch>(find.byType(Switch));

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
      expect(find.byType(Switch), findsOneWidget, reason: 'telefon bildirimi için anahtar yok');
      expect(_switch(t).value, isTrue);
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
      expect(find.byType(Switch), findsOneWidget);
    });
  });

  group('davranış', () {
    testWidgets('anahtar sunucudaki değeri gösterir; kapatınca PUT gider ve değer kalıcı olur', (t) async {
      final auth = _auth()..prefsEmail = true;
      await _pump(t, auth);
      expect(_switch(t).value, isTrue);
      await t.tap(find.byType(Switch));
      await settleFor(t);
      expect(auth.prefsSetCalls, <bool>[false]);
      expect(_switch(t).value, isFalse);
      expect(auth.prefsEmail, isFalse);

      await t.tap(find.byType(Switch));
      await settleFor(t);
      expect(auth.prefsSetCalls, <bool>[false, true]);
      expect(_switch(t).value, isTrue);
    });

    testWidgets('kayıt sürerken anahtar kilitli (çift dokunuş tek istek)', (t) async {
      final auth = _auth()..prefsSaveGate = Completer<void>();
      await _pump(t, auth);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(auth.prefsSetCalls, <bool>[false]);
      expect(_switch(t).onChanged, isNull, reason: 'kayıt sürerken kilitli');
      await t.tap(find.byType(Switch), warnIfMissed: false);
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
      await t.tap(find.byType(Switch));
      await settleFor(t);
      expect(_switch(t).value, isTrue, reason: 'sunucuya yazılamadı: eski değer');
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsOneWidget);
      expect(auth.prefsEmail, isTrue);

      auth.prefsSaveError = null;
      await t.tap(find.byType(Switch));
      await settleFor(t);
      expect(find.text('Tercih kaydedilemedi (deneme).'), findsNothing);
      expect(_switch(t).value, isFalse);
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
}
