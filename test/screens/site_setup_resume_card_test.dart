// Panel "Site kurulumunuz yarım kaldı" kartı (P2-15): yalnız cihazda kaydı olan bitmemiş kurulum için çizilir; ağ isteği
// yapmaz; kayıt değişince kendini tazeler; "Şimdilik gizle" kapatır; taşma matrisi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_setup_resume_card.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart' show settleFor;

const int _user = 5;
const String _longSite = 'Çok Uzun Adlı Konut Yapı Kooperatifi Gül Bahçesi Sitesi Yönetimi Kurulu Sitesi';

final Finder _card = find.byKey(const ValueKey<String>('site_setup_resume_card'));

class _Taps {
  final List<(int, String)> opened = <(int, String)>[];
}

Future<void> _pump(
  WidgetTester t,
  SiteSetupProgressStore store,
  _Taps taps, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpAt(
    t,
    SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SiteSetupResumeCard(
          userId: _user,
          store: store,
          onResume: (siteCode, siteName) => taps.opened.add((siteCode, siteName)),
        ),
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  late SiteSetupProgressStore store;
  late _Taps taps;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = SiteSetupProgressStore();
    taps = _Taps();
  });

  testWidgets('kayıt yoksa HİÇBİR ŞEY çizilmez (kart da boşluk da)', (t) async {
    await _pump(t, store, taps);
    expect(_card, findsNothing);
    expect(find.byType(SiteSetupResumeCard), findsOneWidget);
    expect(t.getSize(find.byType(SiteSetupResumeCard)).height, 0);
  });

  testWidgets('yarım kalan kurulum: ilerleme kayıttan okunur; «Kuruluma devam et» siteyi ve adı verir', (t) async {
    await store.save(
      _user,
      const SiteSetupProgress(
        siteCode: 11,
        siteName: 'Gül Sitesi',
        started: true,
        done: {SiteSetupStep.siteInfo, SiteSetupStep.blocks},
        current: SiteSetupStep.apartments,
      ),
    );
    await _pump(t, store, taps);
    expect(find.text('Site kurulumunuz yarım kaldı'), findsOneWidget);
    expect(find.text('Gül Sitesi · 2 / 6 adım tamam'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('site_setup_resume_open')));
    await t.pump();
    expect(taps.opened, <(int, String)>[(11, 'Gül Sitesi')]);
  });

  testWidgets('sihirbaz hiç açılmadıysa yönlendirici metin ve «Kuruluma başla»', (t) async {
    await store.ensure(_user, 11, siteName: 'Gül Sitesi');
    await _pump(t, store, taps);
    expect(find.text('Site kurulumunu tamamlayın'), findsOneWidget);
    expect(find.text('Gül Sitesi hazır. Kişileri, modülleri ve finansı birkaç adımda tamamlayın.'), findsOneWidget);
    expect(find.text('Kuruluma başla'), findsOneWidget);
  });

  testWidgets('kayıt kart açıkken değişirse kart kendini tazeler (görünür / kaybolur)', (t) async {
    await _pump(t, store, taps);
    expect(_card, findsNothing);
    await store.save(_user, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true));
    await settleFor(t, 100);
    await settleFor(t, 100);
    expect(_card, findsOneWidget, reason: 'kurulum kaydı sonradan açıldı (örn. başvuru onaylandı)');
    await store.save(_user, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true, finished: true));
    await settleFor(t, 100);
    await settleFor(t, 100);
    expect(_card, findsNothing, reason: 'kurulum bitti: hatırlatma kalkar');
  });

  testWidgets('«Şimdilik gizle» kartı kapatır ve kayıt kalıcıdır; başka kullanıcının kaydı görünmez', (t) async {
    await store.save(99, const SiteSetupProgress(siteCode: 7, siteName: 'Başkasının', started: true));
    await store.save(_user, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true));
    await _pump(t, store, taps);
    expect(find.textContaining('Başkasının'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('site_setup_resume_dismiss')));
    await settleFor(t, 100);
    await settleFor(t, 100);
    expect(_card, findsNothing);
    expect((await store.load(_user, 11))?.dismissed, isTrue);
    expect((await store.load(99, 7))?.dismissed, isFalse, reason: 'başka kullanıcının kaydı değişmez');
  });

  testWidgets('en son güncellenen bitmemiş kurulum gösterilir; o kapanınca bir önceki gelir', (t) async {
    await store.save(_user, const SiteSetupProgress(siteCode: 1, siteName: 'Eski Site', started: true));
    await store.save(_user, const SiteSetupProgress(siteCode: 2, siteName: 'Yeni Site', started: true));
    await _pump(t, store, taps);
    expect(find.textContaining('Yeni Site'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('site_setup_resume_dismiss')));
    await settleFor(t, 100);
    await settleFor(t, 100);
    expect(find.textContaining('Eski Site'), findsOneWidget);
  });

  for (final (w, h, scale) in const <(double, double, double)>[
    (320.0, 640.0, 2.0),
    (360.0, 640.0, 1.5),
    (640.0, 360.0, 1.0),
    (820.0, 1180.0, 1.0),
  ]) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('uzun site adı taşmaz: ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}', (t) async {
        await store.save(
          _user,
          const SiteSetupProgress(siteCode: 11, siteName: _longSite, started: true, done: {SiteSetupStep.siteInfo}),
        );
        await _pump(t, store, taps, width: w, height: h, scale: scale, dark: dark);
        expect(_card, findsOneWidget);
        expect(t.takeException(), isNull);
        // Sihirbaz hiç açılmadıysa metin farklı ve daha uzundur.
        await store.save(_user, const SiteSetupProgress(siteCode: 12, siteName: _longSite));
        await settleFor(t, 100);
        await settleFor(t, 100);
        expect(t.takeException(), isNull);
      });
    }
  }
}
