// Platform Faz 4b: Finans Ayarları penceresi (makbuz otomatik, gecikme tazminatı, borç hatırlatma).
//
// Kısmi kaydetme + `expected_settings_version`; SETTINGS_STALE güncel ayarı yükler ve formu yeniden kurar;
// sistem bayrağı (`legal_ok`) kapalıyken tazminat / hatırlatma AÇILAMAZ; oran sistem sınırını aşamaz; başlangıç ayı
// zorunlu ve aktif çalıştırma varken kilitli; çift dokunuş tek istek; 429 düğmeyi geçici kilitler.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_settings_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);

class _Out {
  bool? saved;
}

FinanceFakeAuth _auth({
  int version = 2,
  bool lateFee = false,
  bool? legalOk,
  bool reminders = false,
  bool smtp = true,
  String? startPeriod,
  int? voidableRunId,
}) {
  final auth = FinanceFakeAuth.seeded();
  auth.f4.settingsJson = f4SettingsJson(
    version: version,
    lateFee: lateFee,
    legalOk: legalOk,
    reminders: reminders,
    smtp: smtp,
    startPeriod: startPeriod,
    voidableRunId: voidableRunId,
  );
  return auth;
}

Future<(FinanceSettingsController, _Out)> _open(
  WidgetTester t,
  FinanceFakeAuth auth, {
  double width = 400,
  double height = 1800,
  double scale = 1.0,
  bool dark = false,
}) async {
  final controller = FinanceSettingsController(_scope(auth));
  addTearDown(controller.dispose);
  unawaited(controller.load());
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  final out = _Out();
  await openDialogAt(
    t,
    (context) async {
      out.saved = await FinanceSettingsDialog.show(context, scope: _scope(auth), controller: controller, now: () => _now);
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  return (controller, out);
}

Future<void> _save(WidgetTester t) async {
  await f4Tap(t, 'finance_settings_submit');
  await settleFor(t);
}

ElevatedButton _submitButton(WidgetTester t) => t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_settings_submit')));

void main() {
  group('görünüm ve sınırlar', () {
    f4Matrix('her bölüm açık: makbuz, tazminat alanları, hatırlatma alanları taşmadan sığar', (t, w, h, s, dark) async {
      final auth = _auth(lateFee: true, reminders: true, legalOk: true, startPeriod: '2026-08-01');
      await _open(t, auth, width: w, height: h, scale: s, dark: dark);
      for (final key in const [
        'finance_settings_auto_receipt',
        'finance_settings_late_enabled',
        'finance_settings_rate',
        'finance_settings_method_daily_30',
        'finance_settings_method_daily_actual',
        'finance_settings_grace',
        'finance_settings_start',
        'finance_settings_reminders_enabled',
        'finance_settings_min_overdue',
        'finance_settings_min_days',
        'finance_settings_min_interval',
        'finance_settings_max_consecutive',
        'finance_settings_submit',
      ]) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    f4Matrix('hukuk onayı bekleniyor: iki bildirim; kapalı anahtarlar açılamaz', (t, w, h, s, dark) async {
      final auth = _auth(legalOk: false);
      await _open(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_settings_late_legal')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_settings_reminder_legal')), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('finance_settings_late_enabled'))).onChanged, isNull);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('finance_settings_reminders_enabled'))).onChanged, isNull);
      // Makbuz anahtarı bayraktan etkilenmez.
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('finance_settings_auto_receipt'))).onChanged, isNotNull);
    });

    testWidgets('bayrak kapalı ama site ayarı zaten açık: kapatmaya izin verilir (açık özellik kilitli kalmaz)', (t) async {
      final auth = _auth(lateFee: true, legalOk: false, startPeriod: '2026-08-01');
      await _open(t, auth);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('finance_settings_late_enabled'))).onChanged, isNotNull);
    });

    testWidgets('bayrak bilinmiyorsa (sunucu bildirmedi) engellenmez; uydurma hukuk metni yok', (t) async {
      final auth = _auth();
      await _open(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_settings_late_legal')), findsNothing);
      expect(find.text('Hukuk onayı bekleniyor'), findsNothing);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('finance_settings_late_enabled'))).onChanged, isNotNull);
    });

    testWidgets('SMTP yapılandırılmamış: bildirim yazılır', (t) async {
      final auth = _auth(smtp: false);
      await _open(t, auth);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_settings_smtp')));
      expect(find.byKey(const ValueKey<String>('finance_settings_smtp')), findsOneWidget);
    });

    testWidgets('tazminat / hatırlatma kapalıyken ilgili alanlar GİZLİ', (t) async {
      final auth = _auth();
      await _open(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_settings_rate')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_settings_min_days')), findsNothing);
      await f4Tap(t, 'finance_settings_late_enabled');
      expect(find.byKey(const ValueKey<String>('finance_settings_rate')), findsOneWidget);
    });
  });

  group('kaydetme', () {
    testWidgets('değişiklik yoksa uyarı verir, istek ATILMAZ', (t) async {
      final auth = _auth();
      await _open(t, auth);
      await _save(t);
      expect(find.text('Değişiklik yapmadınız.'), findsOneWidget);
      expect(auth.f4.settingsUpdates, isEmpty);
    });

    testWidgets('yalnız değişen alan gider (kısmi) + beklenen sürüm; denetleyici güncellenir; pencere true ile kapanır', (t) async {
      final auth = _auth(version: 7);
      final (controller, out) = await _open(t, auth);
      await f4Tap(t, 'finance_settings_auto_receipt');
      await _save(t);
      final body = auth.f4.settingsUpdates.single;
      expect(body['expected_settings_version'], 7);
      expect(body['receipts'], <String, dynamic>{'auto_issue': false});
      expect(body.containsKey('late_fee'), isFalse);
      expect(body.containsKey('reminders'), isFalse);
      expect(out.saved, isTrue);
      expect(controller.settings!.settingsVersion, 8);
      expect(controller.settings!.receiptAutoIssue, isFalse);
      expect(find.text('Finans Ayarları'), findsNothing, reason: 'pencere kapandı');
    });

    testWidgets('tazminat: oran, gün esası, ek gün, başlangıç ayı ve hatırlatma değerleri birlikte gider', (t) async {
      final auth = _auth(lateFee: true, reminders: true, legalOk: true);
      await _open(t, auth);
      await f4Enter(t, 'finance_settings_rate', '4,5');
      await f4Tap(t, 'finance_settings_method_daily_actual');
      await f4Enter(t, 'finance_settings_grace', '3');
      await f4Tap(t, 'finance_settings_start_pick');
      await f4Enter(t, 'finance_settings_min_overdue', '75,50');
      await f4Enter(t, 'finance_settings_min_days', '7');
      await f4Enter(t, 'finance_settings_min_interval', '10');
      await f4Enter(t, 'finance_settings_max_consecutive', '2');
      await _save(t);
      final body = auth.f4.settingsUpdates.single;
      expect(body['late_fee'], <String, dynamic>{
        'rate_bp': 450,
        'method': 'daily_actual',
        'grace_days': 3,
        'start_period': '2026-09',
      });
      expect(body['reminders'], <String, dynamic>{
        'min_overdue_minor': 7550,
        'min_days_overdue': 7,
        'min_interval_days': 10,
        'max_consecutive': 2,
      });
    });

    testWidgets('oran sistem sınırını (%5,00) aşamaz; geçersiz oran reddedilir; istek yok', (t) async {
      final auth = _auth(lateFee: true, legalOk: true, startPeriod: '2026-08-01');
      await _open(t, auth);
      await f4Enter(t, 'finance_settings_rate', '6');
      await _save(t);
      expect(find.text('Oran %5,00 sistem sınırını aşamaz.'), findsOneWidget);
      await f4Enter(t, 'finance_settings_rate', 'abc');
      await _save(t);
      expect(find.text('Oranı yüzde olarak girin (örn. 5 ya da 4,5).'), findsOneWidget);
      expect(auth.f4.settingsUpdates, isEmpty);
    });

    testWidgets('sayı aralıkları: ek gün 0-90, hatırlatma günü 1-120, aralık 7-90, sınır 1-6', (t) async {
      final auth = _auth(lateFee: true, reminders: true, legalOk: true, startPeriod: '2026-08-01');
      await _open(t, auth);
      await f4Enter(t, 'finance_settings_grace', '91');
      await f4Enter(t, 'finance_settings_min_days', '0');
      await f4Enter(t, 'finance_settings_min_interval', '3');
      await f4Enter(t, 'finance_settings_max_consecutive', '7');
      await _save(t);
      expect(find.text('Ek gün 0 ile 90 arasında olmalı.'), findsOneWidget);
      expect(find.text('Değer 1 ile 120 arasında olmalı.'), findsOneWidget);
      expect(find.text('Değer 7 ile 90 arasında olmalı.'), findsOneWidget);
      expect(find.text('Değer 1 ile 6 arasında olmalı.'), findsOneWidget);
      expect(auth.f4.settingsUpdates, isEmpty);
    });

    testWidgets('hatırlatma eşiği 1,00 ₺ altına inemez (sunucu sınırı); istek yok; tutar ekran okuyucuda okunuşla', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth(reminders: true, legalOk: true);
      await _open(t, auth);
      await f4Enter(t, 'finance_settings_min_overdue', '0,50');
      await _save(t);
      expect(find.text('En az vadesi geçmiş tutar en az 1,00 ₺ olmalıdır.'), findsOneWidget);
      await t.pump();
      f4ExpectSpokenMoney(t); // R14: hata iletisi ve ipucu "1,00 ₺" yığını değil lira olarak okunur
      handle.dispose();
      expect(auth.f4.settingsUpdates, isEmpty);
      await f4Enter(t, 'finance_settings_min_overdue', '1,00');
      await _save(t);
      expect((auth.f4.settingsUpdates.single['reminders'] as Map)['min_overdue_minor'], 100);
    });

    testWidgets('tazminat açılırken başlangıç ayı zorunlu: seçilmeden kaydedilmez', (t) async {
      final auth = _auth(legalOk: true);
      await _open(t, auth);
      await f4Tap(t, 'finance_settings_late_enabled');
      await _save(t);
      expect(find.text('Tazminat için ilk hesaplanacak ayı (başlangıç ayı) seçin.'), findsOneWidget);
      expect(auth.f4.settingsUpdates, isEmpty);
      await f4Tap(t, 'finance_settings_start_pick');
      expect(find.text('Eylül 2026'), findsOneWidget, reason: 'önerilen: bir önceki ay');
      await f4Tap(t, 'finance_settings_start_prev');
      expect(find.text('Ağustos 2026'), findsOneWidget);
      await _save(t);
      final body = auth.f4.settingsUpdates.single;
      expect((body['late_fee'] as Map)['enabled'], isTrue);
      expect((body['late_fee'] as Map)['start_period'], '2026-08');
    });

    testWidgets('aktif çalıştırma varken başlangıç ayı KİLİTLİ (açıklama + oklar pasif)', (t) async {
      final auth = _auth(lateFee: true, legalOk: true, startPeriod: '2026-08-01', voidableRunId: 40);
      await _open(t, auth);
      expect(find.text('Aktif bir tazminat çalıştırması var; başlangıç ayı değiştirilemez.'), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_settings_start_prev'))).onPressed, isNull);
      expect(t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_settings_start_next'))).onPressed, isNull);
    });

    testWidgets('çift dokunuş: tek istek', (t) async {
      final auth = _auth();
      await _open(t, auth);
      await f4Tap(t, 'finance_settings_auto_receipt');
      final submit = find.byKey(const ValueKey<String>('finance_settings_submit'));
      await t.ensureVisible(submit);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(submit);
      await t.tap(submit, warnIfMissed: false);
      await settleFor(t);
      expect(auth.f4.settingsUpdates, hasLength(1));
    });
  });

  group('R14: kaydedilmemiş veri koruması (Vazgeç / geri tuşu)', () {
    testWidgets('ayarlar: bir anahtar değişince Vazgeç / geri tuşu onay sorar; kayıt isteği yok', (t) async {
      final auth = _auth();
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_settings_submit',
        open: () async {
          await _open(t, auth);
        },
        edit: () async => f4Tap(t, 'finance_settings_auto_receipt'),
      );
      expect(auth.f4.settingsUpdates, isEmpty);
    });
  });

  group('hatalar', () {
    testWidgets('SETTINGS_STALE: güncel ayar yüklenir, form yeniden kurulur, bildirim çıkar; yeniden kaydetmek yeni sürümle gider', (t) async {
      final auth = _auth(lateFee: true, legalOk: true, startPeriod: '2026-08-01');
      await _open(t, auth);
      // Başkası ayarı değiştirdi: sürüm 3, oran %4,00.
      auth.f4.settingsJson = <String, dynamic>{
        ...auth.f4.settingsJson,
        'settings_version': 3,
        'late_fee': <String, dynamic>{...(auth.f4.settingsJson['late_fee'] as Map).cast<String, dynamic>(), 'rate_bp': 400},
      };
      await f4Tap(t, 'finance_settings_auto_receipt');
      await _save(t);
      expect(find.byKey(const ValueKey<String>('finance_settings_stale')), findsOneWidget);
      expect(find.textContaining('Güncel ayarlar yüklendi'), findsWidgets);
      final rate = t.widget<TextFormField>(find.byKey(const ValueKey<String>('finance_settings_rate')));
      expect(rate.controller!.text, '4,00', reason: 'form güncel ayarla yeniden kuruldu');
      // Makbuz anahtarı güncel (açık) değere döndü: yeniden kapatıp kaydet.
      await f4Tap(t, 'finance_settings_auto_receipt');
      await _save(t);
      final last = auth.f4.settingsUpdates.last;
      expect(last['expected_settings_version'], 3);
      expect(auth.f4.settingsUpdates, hasLength(2));
      expect(auth.f4.settingsJson['settings_version'], 4);
    });

    testWidgets('R13 P2-10: SETTINGS_STALE sonrası güncel ayarlar YÜKLENEMEZSE sessiz kalınmaz (neden yazılır)', (t) async {
      final auth = _auth();
      await _open(t, auth);
      auth.f4.settingsJson = <String, dynamic>{...auth.f4.settingsJson, 'settings_version': 3};
      await f4Tap(t, 'finance_settings_auto_receipt');
      // Kaydet 409 SETTINGS_STALE alır; ardından güncel ayarı okuma da başarısız olur.
      auth.f4.settingsError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await _save(t);
      expect(find.textContaining('güncel ayarlar şu an yüklenemedi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_settings_stale')), findsNothing);
      auth.f4.settingsError = null;
    });

    testWidgets('ağ hatası: pencere açık kalır, Türkçe ileti; yeniden deneme çalışır', (t) async {
      final auth = _auth();
      auth.f4.settingsUpdateError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      final (_, out) = await _open(t, auth);
      await f4Tap(t, 'finance_settings_auto_receipt');
      await _save(t);
      expect(find.textContaining('Ayarlar kaydedilemedi'), findsOneWidget);
      expect(find.textContaining('Ayarlar kaydedilmiş olabilir'), findsOneWidget);
      expect(find.textContaining('çift kayıt'), findsNothing);
      expect(out.saved, isNull);
      auth.f4.settingsUpdateError = null;
      await _save(t);
      expect(out.saved, isTrue);
    });

    testWidgets('429: ileti + Kaydet geçici kilitli; süre dolunca açılır', (t) async {
      final auth = _auth();
      auth.f4.settingsUpdateError = ApiException('Çok fazla istek.', statusCode: 429, retryAfterSeconds: 5);
      await _open(t, auth);
      await f4Tap(t, 'finance_settings_auto_receipt');
      await _save(t);
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNull);
      await t.pump(const Duration(seconds: 6));
      expect(_submitButton(t).onPressed, isNotNull);
    });

    testWidgets('ekran okuyucu: oran alanı etiketli; kayıt hatası canlı bölge olarak duyurulur', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth(lateFee: true, legalOk: true, startPeriod: '2026-08-01');
      await _open(t, auth);
      expect(find.bySemanticsLabel(RegExp('Aylık oran')), findsWidgets);
      await _save(t);
      expect(find.text('Değişiklik yapmadınız.'), findsOneWidget);
      handle.dispose();
    });
  });
}
