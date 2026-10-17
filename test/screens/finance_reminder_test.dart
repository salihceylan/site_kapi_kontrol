// Platform Faz 4b, Ö6: borç hatırlatma kartı, "Borç Hatırlat" penceresi (önizleme + onay), hatırlatma geçmişi ve muaf daireler.
//
// Pasif durumlar nedenini açıklar (hukuk onayı bekleniyor / bu sitede kapalı / ayarlar okunamadı); önizleme HİÇBİR ŞEY
// göndermez ve adres / ad göstermez; bayat önizleme otomatik yenilenir; SMTP yok / alıcı yok / günlük sınır onayı kapatır;
// aynı özetle yeniden deneme aynı işlem anahtarını kullanır (çift e-posta yok); kurul yalnız geçmişi okur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show AppCard;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reminder_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

int _opened = 0;
int _changed = 0;

FinanceFakeAuth _auth({bool enabled = true, bool? legalOk = true, bool smtp = true}) {
  final auth = FinanceFakeAuth.seeded();
  auth.f4.settingsJson = f4SettingsJson(version: 3, reminders: enabled, legalOk: legalOk, smtp: smtp);
  return auth;
}

Future<FinanceSettingsController> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  double width = 400,
  double height = 3000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final controller = FinanceSettingsController(_scope(auth, canWrite: canWrite));
  addTearDown(controller.dispose);
  unawaited(controller.load());
  _opened = 0;
  _changed = 0;
  await pumpList(
    t,
    FinanceReminderCard(
      scope: _scope(auth, canWrite: canWrite),
      settings: controller,
      onOpenSettings: () => _opened++,
      onDataChanged: () => _changed++,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return controller;
}

ElevatedButton _confirmButton(WidgetTester t) =>
    t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_reminder_confirm')));

Future<void> _openSend(WidgetTester t) async {
  await f4Tap(t, 'finance_reminder_send');
  await settleFor(t);
}

Future<void> _preview(WidgetTester t) async {
  await f4Tap(t, 'finance_reminder_preview');
  await settleFor(t);
}

Future<void> _sendConfirmed(WidgetTester t) async {
  await f4Tap(t, 'finance_reminder_confirm');
  await f4TapInDialog(t, 'Gönder');
  await settleFor(t);
}

Map<String, dynamic> _run(
  int id, {
  String status = 'active',
  String tone = 'friendly',
  int apartments = 4,
  int people = 5,
  Map<String, dynamic> stats = const <String, dynamic>{'sent': 2, 'pending': 3},
}) => <String, dynamic>{
  'id': id,
  'status': status,
  'tone': tone,
  'apartment_count': apartments,
  'person_count': people,
  'with_amount_count': 3,
  'stats': stats,
  'created_at': '2026-10-1${id % 10}T09:00:00Z',
};

void main() {
  group('kart: pasif durumlar ve görünüm', () {
    f4Matrix('hukuk onayı bekleniyor: neden yazılır; geçmiş yine okunabilir', (t, w, h, s, dark) async {
      final auth = _auth(legalOk: false);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_feature_legal')), findsOneWidget);
      expect(find.textContaining('Hukuk onayı bekleniyor'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_reminder_history')), findsOneWidget);
    });

    f4Matrix('site ayarı kapalı: "bu sitede kapalı" + Finans Ayarları yolu', (t, w, h, s, dark) async {
      final auth = _auth(enabled: false);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.textContaining('Borç hatırlatma bu sitede kapalı'), findsOneWidget);
      await f4Tap(t, 'finance_feature_open_settings');
      expect(_opened, 1);
    });

    f4Matrix('açık: ayar özeti + üç düğme', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_reminder_settings_line')), findsOneWidget);
      expect(find.text('En az 50,00 ₺ ve 5 gün gecikmiş borç • 14 günde bir • en çok 3 ardışık hatırlatma'), findsOneWidget);
      for (final key in const ['finance_reminder_send', 'finance_reminder_exclusions', 'finance_reminder_history']) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('SMTP yoksa kartta uyarı yazılır', (t) async {
      final auth = _auth(smtp: false);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_reminder_card_no_smtp')), findsOneWidget);
    });

    testWidgets('kurul: yalnız Geçmiş; gönderme ve muaf düğmesi yok', (t) async {
      final auth = _auth();
      await _pump(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exclusions')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_reminder_history')), findsOneWidget);
    });

    testWidgets('ayarlar okunamazsa "kapalı" DENMEZ: hata + Tekrar Dene; yükleniyorken iskelet', (t) async {
      final auth = _auth();
      auth.f4.settingsError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_feature_error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_feature_disabled')), findsNothing);
      auth.f4.settingsError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsOneWidget);
    });

    testWidgets('ayarlar yüklenirken iskelet', (t) async {
      final auth = _auth();
      auth.f4.settingsGate = Completer<void>();
      await _pump(t, auth);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_send')), findsNothing);
      auth.f4.settingsGate!.complete();
      await settleFor(t);
    });
  });

  group('Borç Hatırlat: ton, not, önizleme, onay', () {
    testWidgets('önizleme HİÇBİR ŞEY göndermez; sayılar ve hariç tutma nedenleri yazılır; ad / adres YOK', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(auth.f4.reminderSends, isEmpty);
      expect(auth.f4.callCount('previewReminders'), 1);
      expect(find.text('4 daire'), findsOneWidget);
      expect(find.text('5 kişi'), findsOneWidget);
      expect(find.text('3 kişiye tutarlı, 2 kişiye tutarsız ileti gider.'), findsOneWidget);
      expect(find.text('Toplam vadesi geçmiş: 4.567,00 ₺'), findsOneWidget);
      expect(find.text('Adresi olmayan kişi: 1'), findsOneWidget);
      expect(find.text('Tutarı eşiğin altında kalan daire: 2'), findsOneWidget);
      expect(find.text('Gecikme günü eşiğin altında kalan daire: 1'), findsOneWidget);
      expect(find.text('Muaf listesindeki daire: 1'), findsOneWidget);
      expect(find.text('Ardışık hatırlatma sınırına ulaşan daire: 0'), findsNothing, reason: 'sıfır satırlar yazılmaz');
      expect(find.byKey(const ValueKey<String>('finance_reminder_hand_follow_up')), findsOneWidget);
      expect(find.textContaining('(A Blok - 7, B Blok - 1)'), findsOneWidget, reason: 'elden takip daire etiketleri (ad / adres yok)');
      expect(find.textContaining('A Blok - 5, A Blok - 6 ...'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing, reason: 'e-posta adresi gösterilmez');
    });

    testWidgets('onay: ayrı onay penceresi; ton + özet gider; başarıda bildirim + üst ekran yenilenir', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openSend(t);
      await f4Tap(t, 'finance_reminder_tone_standard');
      await _preview(t);
      await f4Tap(t, 'finance_reminder_confirm');
      expect(find.text('Hatırlatmaları gönder'), findsOneWidget);
      expect(auth.f4.reminderSends, isEmpty, reason: 'ikinci onay beklenir');
      await f4TapInDialog(t, 'Vazgeç');
      expect(auth.f4.reminderSends, isEmpty);
      await _sendConfirmed(t);
      final call = auth.f4.reminderSends.single;
      expect(call['tone'], 'standard');
      expect(call['hash'], 'rm-base-standard');
      expect(call['apartments'], 4);
      expect(call['people'], 5);
      expect((call['key'] as String).length, lessThanOrEqualTo(64));
      expect(find.textContaining('Hatırlatma gönderimi başlatıldı: 5 kişi, 4 daire.'), findsOneWidget);
      expect(_changed, greaterThanOrEqualTo(1));
    });

    testWidgets('not gönderilir; 300 karakteri aşan not önizlemeyi engeller (istek yok)', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openSend(t);
      await f4Enter(t, 'finance_reminder_note', 'a' * 301);
      await _preview(t);
      expect(find.text('Not en çok 300 karakter olabilir.'), findsOneWidget);
      expect(auth.f4.callCount('previewReminders'), 0);
      await f4Enter(t, 'finance_reminder_note', 'Lütfen ödemenizi kontrol ediniz.');
      await _preview(t);
      await _sendConfirmed(t);
      expect(auth.f4.reminderSends.single['note'], 'Lütfen ödemenizi kontrol ediniz.');
    });

    testWidgets('PREVIEW_STALE: önizleme OTOMATİK yenilenir, eski + yeni sayılar yazılır, eski özetle gönderilmez', (t) async {
      final auth = _auth();
      auth.f4.reminderSendStaleOnce = true;
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      await _sendConfirmed(t);
      expect(auth.f4.reminderSends, hasLength(1), reason: 'bayat özetle ikinci gönderim denenmedi');
      expect(find.byKey(const ValueKey<String>('finance_reminder_notice')), findsOneWidget);
      expect(find.textContaining('Yeni sayılar: 4 daire, 6 kişi; önceki: 4 daire, 5 kişi'), findsOneWidget);
      await _sendConfirmed(t);
      expect(auth.f4.reminderSends, hasLength(2));
      expect(auth.f4.reminderSends[1]['people'], 6);
      expect(auth.f4.reminderSends[1]['hash'], isNot(auth.f4.reminderSends[0]['hash']));
      expect(auth.f4.reminderRuns, hasLength(1));
    });

    testWidgets('yenileme başarısızken eski özetle onay KAPALI; Önizlemeyi Yenile ile açılır', (t) async {
      final auth = _auth();
      auth.f4.reminderSendStaleOnce = true;
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      auth.f4.reminderPreviewError = ApiException('x', statusCode: 500);
      await _sendConfirmed(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_refresh')), findsOneWidget);
      expect(_confirmButton(t).onPressed, isNull);
      expect(find.byKey(const ValueKey<String>('finance_reminder_blocked_reason')), findsOneWidget);
      auth.f4.reminderPreviewError = null;
      await f4Tap(t, 'finance_reminder_refresh');
      await settleFor(t);
      expect(_confirmButton(t).onPressed, isNotNull);
    });

    testWidgets('günlük sınır (REMINDER_DAILY_LIMIT): onay kapalı, neden yazılır', (t) async {
      final auth = _auth();
      auth.f4.reminderPreviewJson = <String, dynamic>{...f4ReminderPreviewJson(), 'blockers': <String>['REMINDER_DAILY_LIMIT']};
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(find.text('Bugün zaten bir hatırlatma gönderildi. Günde en çok bir çalıştırma yapılabilir.'), findsOneWidget);
      expect(_confirmButton(t).onPressed, isNull);
    });

    testWidgets('SMTP yapılandırılmamış: önizlemede uyarı, onay kapalı', (t) async {
      final auth = _auth();
      auth.f4.reminderPreviewJson = f4ReminderPreviewJson(smtp: false);
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_no_smtp')), findsOneWidget);
      expect(_confirmButton(t).onPressed, isNull);
    });

    testWidgets('alıcı yok: açıklayıcı durum, onay kapalı', (t) async {
      final auth = _auth();
      auth.f4.reminderPreviewJson = <String, dynamic>{
        ...f4ReminderPreviewJson(),
        'apartment_count': 0,
        'person_count': 0,
        'with_amount_count': 0,
        'without_amount_count': 0,
        'hand_follow_up_count': 0,
        'sample_apartments': <String>[],
        'excluded': <String, dynamic>{},
        'no_address_count': 0,
      };
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_no_recipients')), findsOneWidget);
      expect(find.text('Hariç tutulan yok.'), findsOneWidget);
      expect(_confirmButton(t).onPressed, isNull);
    });

    testWidgets('önizleme hatası pencerede kalır; Geri formu açar', (t) async {
      final auth = _auth();
      auth.f4.reminderPreviewError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(find.text('Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_preview')), findsOneWidget);
    });

    testWidgets('R10: not bağlantı / alan adı / e-posta İÇEREMEZ (sunucu 400 verir): önizleme istenmeden Türkçe uyarı', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openSend(t);
      for (final bad in const ['Ayrıntı: www.odeme.com', 'Yaz: ben@site.org', 'https://x.test/odeme']) {
        await f4Enter(t, 'finance_reminder_note', bad);
        await _preview(t);
        expect(find.text('Not bağlantı, alan adı ya da e-posta adresi içeremez.'), findsOneWidget, reason: bad);
        expect(auth.f4.callCount('previewReminders'), 0, reason: bad);
      }
      await f4Enter(t, 'finance_reminder_note', 'Lütfen ödemenizi kontrol ediniz.');
      await _preview(t);
      expect(auth.f4.callCount('previewReminders'), 1);
    });

    testWidgets('REPORT_BUSY (503): "Yoğunluk var" + Tekrar Dene; otomatik yeniden deneme YOK', (t) async {
      final auth = _auth();
      auth.f4.reminderPreviewError = f4Coded('REPORT_BUSY', 503);
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(find.textContaining('Yoğunluk var, biraz sonra tekrar deneyin.'), findsOneWidget);
      expect(auth.f4.callCount('previewReminders'), 1);
      auth.f4.reminderPreviewError = null;
      await f4Tap(t, 'finance_reminder_preview_retry');
      await settleFor(t);
      expect(auth.f4.callCount('previewReminders'), 2);
      expect(find.byKey(const ValueKey<String>('finance_reminder_summary')), findsOneWidget);
    });

    testWidgets('LEGAL_APPROVAL_REQUIRED engeli açıklayıcı metinle gösterilir; onay kapalı', (t) async {
      final auth = _auth();
      auth.f4.reminderPreviewJson = <String, dynamic>{...f4ReminderPreviewJson(), 'blockers': <String>['LEGAL_APPROVAL_REQUIRED']};
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(find.text('Hukuk onayı bekleniyor. Borç hatırlatma onay tamamlanana dek kullanılamaz.'), findsOneWidget);
      expect(_confirmButton(t).onPressed, isNull);
    });

    testWidgets('yanıtı kaybolan gönderim: aynı özetle AYNI anahtar, çift e-posta yok, "daha önce başlatılmıştı" bildirimi', (t) async {
      final auth = _auth();
      auth.f4.reminderSendLoseResponse = true;
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      await _sendConfirmed(t);
      expect(find.textContaining('Gönderim başlamış olabilir'), findsOneWidget);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsNothing);
      await _sendConfirmed(t);
      final keys = auth.f4.reminderSends.map((c) => c['key']).toList();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1]);
      expect(auth.f4.reminderRuns, hasLength(1), reason: 'ikinci çalıştırma açılmadı');
      expect(find.textContaining('Bu hatırlatma daha önce başlatılmıştı'), findsOneWidget);
    });

    testWidgets('çift dokunuş: gönderim sürerken onay pasif, tek istek', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      auth.f4.reminderSendGate = Completer<void>();
      await f4Tap(t, 'finance_reminder_confirm');
      await f4TapInDialog(t, 'Gönder');
      await t.pump();
      expect(_confirmButton(t).onPressed, isNull, reason: 'işlem sürerken pasif');
      auth.f4.reminderSendGate!.complete();
      await settleFor(t);
      expect(auth.f4.reminderSends, hasLength(1));
    });

    testWidgets('429: ileti + onay geçici kilitli', (t) async {
      final auth = _auth();
      auth.f4.reminderSendError = ApiException('Çok fazla istek.', statusCode: 429, retryAfterSeconds: 5);
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      await _sendConfirmed(t);
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      expect(_confirmButton(t).onPressed, isNull);
      await t.pump(const Duration(seconds: 6));
      expect(_confirmButton(t).onPressed, isNotNull);
    });

    f4Matrix('pencere: form ve önizleme taşmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _openSend(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_note')), findsOneWidget);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_summary')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_reminder_confirm')));
    });

    testWidgets('ekran okuyucu: önizleme özeti tek cümle olarak okunur', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _pump(t, auth);
      await _openSend(t);
      await _preview(t);
      expect(
        find.bySemanticsLabel(RegExp('Önizleme. 4 daire. 5 kişi. 3 kişiye tutarlı ileti, 2 kişiye tutarsız ileti.')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('R14: kaydedilmemiş veri koruması (Vazgeç / geri tuşu)', () {
    testWidgets('Borç Hatırlat: yazılmış not varken Vazgeç / geri tuşu onay sorar; hiçbir şey gönderilmez', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_reminder_preview',
        open: () async => _openSend(t),
        edit: () async => f4Enter(t, 'finance_reminder_note', 'Lütfen ödemenizi kontrol ediniz.'),
      );
      expect(auth.f4.reminderSends, isEmpty);
    });
  });

  group('Hatırlatma Geçmişi', () {
    f4Matrix('çalıştırmalar: durum, sayılar ve iptal düğmesi (yalnız bekleyeni olan)', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.reminderRuns
        ..add(_run(69, stats: const <String, dynamic>{'sent': 5, 'failed': 1, 'no_address': 1}))
        ..add(_run(70, status: 'cancelled', stats: const <String, dynamic>{'sent': 1, 'cancelled': 2}))
        ..add(_run(71));
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4Tap(t, 'finance_reminder_history');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('reminder_run_71')), findsOneWidget);
      expect(find.text('Gönderiliyor'), findsOneWidget);
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(find.text('Tamamlandı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reminder_run_cancel_71')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reminder_run_cancel_70')), findsNothing);
      expect(find.byKey(const ValueKey<String>('reminder_run_cancel_69')), findsNothing);
      expect(find.text('Bekleyen: 3'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('boş geçmiş: açıklayıcı durum', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_history');
      await settleFor(t);
      expect(find.text('Henüz hatırlatma gönderilmedi.'), findsOneWidget);
    });

    testWidgets('hata: "gönderilmedi" yazılmaz, Tekrar Dene', (t) async {
      final auth = _auth();
      auth.f4.reminderRunsError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_history');
      await settleFor(t);
      expect(find.text('Henüz hatırlatma gönderilmedi.'), findsNothing);
      expect(find.text('Tekrar Dene'), findsWidgets);
    });

    testWidgets('kurul: iptal düğmesi yok, sayıları görür', (t) async {
      final auth = _auth();
      auth.f4.reminderRuns.add(_run(71));
      await _pump(t, auth, canWrite: false);
      await f4Tap(t, 'finance_reminder_history');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('reminder_run_71')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reminder_run_cancel_71')), findsNothing);
    });

    testWidgets('iptal: ayrı onay; bekleyenler iptal edilir, liste yenilenir, bildirim', (t) async {
      final auth = _auth();
      auth.f4.reminderRuns.add(_run(71));
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_history');
      await settleFor(t);
      await f4Tap(t, 'reminder_run_cancel_71');
      expect(find.text('Hatırlatmayı iptal et'), findsOneWidget);
      await f4TapInDialog(t, 'Vazgeç');
      expect(auth.f4.callCount('cancelReminderRun'), 0);
      await f4Tap(t, 'reminder_run_cancel_71');
      await f4TapInDialog(t, 'Bekleyenleri İptal Et');
      await settleFor(t);
      expect(auth.f4.callCount('cancelReminderRun'), 1);
      expect(auth.f4.reminderRuns.single['status'], 'cancelled');
      expect(find.byKey(const ValueKey<String>('reminder_run_cancel_71')), findsNothing);
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(_changed, greaterThanOrEqualTo(1));
    });

    testWidgets('iptal hatası pencerede Türkçe ileti olarak kalır', (t) async {
      final auth = _auth();
      auth.f4.reminderRuns.add(_run(71));
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_history');
      await settleFor(t);
      auth.f4.reminderRunsError = f4Coded('REMINDER_RUN_NOT_CANCELLABLE', 409);
      await f4Tap(t, 'reminder_run_cancel_71');
      await f4TapInDialog(t, 'Bekleyenleri İptal Et');
      await settleFor(t);
      // Çakışma kodunda liste yeniden okunur (sahte API aynı hatayı listeye de verir: ileti iki yerde görünebilir).
      expect(find.byKey(const ValueKey<String>('finance_reminder_runs_error')), findsOneWidget);
      expect(find.text('Bu hatırlatma çalıştırması iptal edilemez (zaten iptal edilmiş).'), findsWidgets);
    });
  });

  group('Muaf Daireler', () {
    testWidgets('boş liste: açıklayıcı durum', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_exclusions');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exclusions_empty')), findsOneWidget);
    });

    testWidgets('hata: "muaf daire yok" yazılmaz, Tekrar Dene', (t) async {
      final auth = _auth();
      auth.f4.reminderExclusionError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_exclusions');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exclusions_empty')), findsNothing);
      expect(find.text('Tekrar Dene'), findsWidgets);
    });

    testWidgets('ekleme: daire seç, neden yaz, ekle; liste yenilenir; muaf kaldır', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_exclusions');
      await settleFor(t);
      await f4Tap(t, 'finance_reminder_exclusion_pick');
      await settleFor(t);
      await t.tap(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')).first);
      await settleFor(t);
      await f4Enter(t, 'finance_reminder_exclusion_reason', 'Dava sürüyor');
      await f4Tap(t, 'finance_reminder_exclusion_add');
      await settleFor(t);
      expect(auth.f4.writes.where((w) => w['op'] == 'addReminderExclusion').single['apartment_id'], 303);
      expect(auth.f4.writes.where((w) => w['op'] == 'addReminderExclusion').single['reason'], 'Dava sürüyor');
      expect(find.byKey(const ValueKey<String>('reminder_exclusion_303')), findsOneWidget);
      expect(find.text('Dava sürüyor'), findsOneWidget);
      expect(_changed, greaterThanOrEqualTo(1));
      await f4Tap(t, 'reminder_exclusion_remove_303');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exclusions_empty')), findsOneWidget);
      expect(auth.f4.reminderExclusions, isEmpty);
    });

    testWidgets('neden 100 karakteri aşarsa eklenmez (istek yok)', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_exclusions');
      await settleFor(t);
      await f4Tap(t, 'finance_reminder_exclusion_pick');
      await settleFor(t);
      await t.tap(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')).first);
      await settleFor(t);
      await f4Enter(t, 'finance_reminder_exclusion_reason', 'a' * 101);
      await f4Tap(t, 'finance_reminder_exclusion_add');
      expect(find.text('Neden en çok 100 karakter olabilir.'), findsOneWidget);
      expect(auth.f4.callCount('addReminderExclusion'), 0);
    });

    testWidgets('ekleme hatası pencerede kalır, liste yeniden okunur', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4Tap(t, 'finance_reminder_exclusions');
      await settleFor(t);
      await f4Tap(t, 'finance_reminder_exclusion_pick');
      await settleFor(t);
      await t.tap(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')).first);
      await settleFor(t);
      auth.f4.reminderExclusionError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await f4Tap(t, 'finance_reminder_exclusion_add');
      await settleFor(t);
      expect(find.textContaining('Daire muaf listesine eklenemedi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reminder_exclusions_error')), findsOneWidget);
    });
  });
}
