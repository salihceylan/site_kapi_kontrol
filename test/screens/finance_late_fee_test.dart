// Platform Faz 4b, Ö2: gecikme tazminatı bölümü (Dönemler sekmesi), hesaplama penceresi (önizleme + onay), çalıştırma
// satırları ve son çalıştırmanın iptali.
//
// Pasif durumlar (hukuk onayı bekleniyor / site ayarı kapalı) nedenini açıklar; önizleme hiçbir şey yazmaz; bayat
// önizleme (PREVIEW_STALE) otomatik yenilenir ve eski onayla yazılmaz; muaf listesi değişince önizleme eskir; engeller
// yönlendirici metinle söylenir; çift dokunuş / işlem anahtarı; yalnız SON çalıştırma iptal edilir; kurul salt okur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_late_fee_section.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

int _settingsOpened = 0;
int _changed = 0;

FinanceFakeAuth _auth({bool enabled = true, bool? legalOk, int version = 2}) {
  final auth = FinanceFakeAuth.seeded();
  auth.f4.settingsJson = f4SettingsJson(
    version: version,
    lateFee: enabled,
    legalOk: legalOk,
    startPeriod: '2026-08-01',
    nextPeriod: '2026-09',
  );
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
  _settingsOpened = 0;
  _changed = 0;
  await pumpList(
    t,
    FinanceLateFeeSection(
      scope: _scope(auth, canWrite: canWrite),
      settings: controller,
      onOpenSettings: () => _settingsOpened++,
      onDataChanged: () => _changed++,
      now: () => _now,
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

ElevatedButton _confirmButton(WidgetTester t) => t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_latefee_confirm')));

Future<void> _openCalc(WidgetTester t) async {
  await f4Tap(t, 'finance_latefee_calculate');
  await settleFor(t);
}

Future<void> _preview(WidgetTester t) async {
  await f4Tap(t, 'finance_latefee_preview');
  await settleFor(t);
}

void main() {
  group('pasif durumlar (neden açıklanır)', () {
    f4Matrix('hukuk onayı bekleniyor (sistem bayrağı kapalı, site ayarı açık)', (t, w, h, s, dark) async {
      final auth = _auth(legalOk: false);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_feature_legal')), findsOneWidget);
      expect(find.text('Hukuk onayı bekleniyor'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_calculate')), findsNothing, reason: 'hesaplanamaz');
      expect(auth.f4.callCount('listLateFeeRuns'), 0, reason: 'kapalı özellik için geçmiş istenmez');
    });

    f4Matrix('site ayarı kapalı: "bu sitede kapalı" + Finans Ayarları yolu', (t, w, h, s, dark) async {
      final auth = _auth(enabled: false);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_feature_disabled')), findsOneWidget);
      expect(find.text('Gecikme tazminatı bu sitede kapalı'), findsOneWidget);
      await f4Tap(t, 'finance_feature_open_settings');
      expect(_settingsOpened, 1);
    });

    testWidgets('kurul: kapalıyken ayar yolu verilmez, nedeni okur', (t) async {
      final auth = _auth(enabled: false);
      await _pump(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_feature_disabled')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_feature_open_settings')), findsNothing);
      expect(find.text('Site yönetimi ayarlardan açtığında burada görünür.'), findsOneWidget);
    });

    testWidgets('ayarlar okunamazsa "kapalı" DENMEZ: hata + Tekrar Dene; yenilenince bölüm açılır', (t) async {
      final auth = _auth();
      auth.f4.settingsError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_feature_error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_feature_disabled')), findsNothing);
      auth.f4.settingsError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_status')), findsOneWidget);
    });

    testWidgets('ayarlar yüklenirken iskelet', (t) async {
      final auth = _auth();
      auth.f4.settingsGate = Completer<void>();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_latefee_status')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_feature_disabled')), findsNothing);
      auth.f4.settingsGate!.complete();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_status')), findsOneWidget);
    });
  });

  group('açık özellik: durum kartı ve geçmiş', () {
    f4Matrix('durum kartı + çalıştırma geçmişi (geçerli ve iptal edilmiş)', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.lateRuns
        ..add(<String, dynamic>{
          'id': 41,
          'period': '2026-08',
          'status': 'voided',
          'total_minor': 10000,
          'apartment_count': 2,
          'params': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0},
          'posted_at': '2026-09-02T09:00:00Z',
          'voided_at': '2026-09-03T09:00:00Z',
        })
        ..add(<String, dynamic>{
          'id': 42,
          'period': '2026-08',
          'status': 'active',
          'total_minor': 12000,
          'net_total_minor': 11000,
          'apartment_count': 3,
          'waived_count': 1,
          'params': <String, dynamic>{'rate_bp': 450, 'method': 'daily_actual', 'grace_days': 3},
          'posted_at': '2026-09-04T09:00:00Z',
          'posted_by_name': 'Yönetici',
        });
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_latefee_status')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('latefee_run_42')), findsOneWidget);
      expect(find.text('Sıradaki ay: Eylül 2026'), findsOneWidget);
      expect(find.text('Oran %5,00 aylık • Aylık oran ÷ 30 gün • vadeye ek 0 gün'), findsOneWidget);
      expect(find.textContaining('Net (iptal edilen kalemler düşülmüş): 110,00 ₺'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('latefee_run_void_42')), findsOneWidget, reason: 'yalnız son aktif çalıştırma');
      expect(find.byKey(const ValueKey<String>('latefee_run_void_41')), findsNothing);
    });

    testWidgets('geçmiş hatası: "çalıştırma yok" yazılmaz, Tekrar Dene', (t) async {
      final auth = _auth();
      auth.f4.lateRunsError = ApiException('x', statusCode: 500);
      await _pump(t, auth);
      expect(find.text('Henüz gecikme tazminatı hesaplanmadı.'), findsNothing);
      expect(find.text('Tekrar Dene'), findsWidgets);
    });

    testWidgets('boş geçmiş: açıklayıcı durum', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(find.text('Henüz gecikme tazminatı hesaplanmadı.'), findsOneWidget);
    });

    testWidgets('kurul: Hesapla / Ayarlar / İptal düğmesi yok; satırları görebilir', (t) async {
      final auth = _auth();
      auth.f4.lateRuns.add(<String, dynamic>{
        'id': 42,
        'period': '2026-08',
        'status': 'active',
        'total_minor': 12000,
        'apartment_count': 3,
        'params': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0},
      });
      await _pump(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_latefee_calculate')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_latefee_settings')), findsNothing);
      expect(find.byKey(const ValueKey<String>('latefee_run_void_42')), findsNothing);
      await f4Tap(t, 'latefee_run_lines_42');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_run_line_301')), findsOneWidget);
    });

    testWidgets('satırlar: nasıl hesaplandı dökümü; hata "satır yok" demez', (t) async {
      final auth = _auth();
      auth.f4.lateRuns.add(<String, dynamic>{
        'id': 42,
        'period': '2026-08',
        'status': 'active',
        'total_minor': 12345,
        'apartment_count': 2,
        'params': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0},
      });
      await _pump(t, auth);
      await f4Tap(t, 'latefee_run_lines_42');
      await settleFor(t);
      await f4Tap(t, 'finance_latefee_run_explain_301');
      expect(find.textContaining('gün toplamı: 12.000,00 ₺ (tutar x gün)'), findsOneWidget);
    });
  });

  group('Hesapla: önizleme ve onay', () {
    testWidgets('sunucunun bildirdiği sıradaki ay açılır; ay düğmeleri; önizleme HİÇBİR ŞEY yazmaz', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      expect(find.text('Eylül 2026'), findsWidgets);
      expect(find.text('Sunucunun bildirdiği sıradaki ay: Eylül 2026.'), findsOneWidget);
      await _preview(t);
      expect(auth.f4.latePreviewCalls.single['period'], '2026-09');
      expect(auth.f4.callCount('postLateFee'), 0);
      expect(find.byKey(const ValueKey<String>('finance_latefee_total')), findsOneWidget);
      expect(find.text('123,45 ₺'), findsOneWidget);
      expect(find.text('2 daire'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_params')), findsOneWidget);
      expect(find.textContaining('Hesap aralığı: 01.09.2026 - 30.09.2026 (30 gün)'), findsOneWidget);
    });

    testWidgets('her satırda "nasıl hesaplandı" dökümü sunucu değerlerinden (istemci yeniden hesaplamaz)', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_explain_301');
      expect(find.textContaining('gün toplamı: 12.000,00 ₺ (tutar x gün)'), findsOneWidget);
      expect(find.textContaining('en yüksek gecikmiş tutar: 500,00 ₺'), findsOneWidget);
      expect(find.textContaining('Tazminat bu değerlerden sunucuda hesaplanır: 100,00 ₺'), findsOneWidget);
      await f4Tap(t, 'finance_latefee_explain_301');
      expect(find.byKey(const ValueKey<String>('finance_latefee_breakdown_301')), findsNothing);
    });

    testWidgets('onay: ayrı onay penceresi; toplam + daire sayısı + özet gider; başarıda bildirim ve geçmiş yenilenir', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_confirm');
      expect(find.text('Gecikme tazminatını yaz'), findsOneWidget);
      expect(auth.f4.callCount('postLateFee'), 0, reason: 'ikinci onay beklenir');
      await f4TapInDialog(t, 'Vazgeç');
      expect(auth.f4.callCount('postLateFee'), 0);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      final call = auth.f4.latePostCalls.single;
      expect(call['period'], '2026-09');
      expect(call['total'], 12345);
      expect(call['count'], 2);
      expect((call['hash'] as String).startsWith('lf-'), isTrue);
      expect((call['key'] as String).length, lessThanOrEqualTo(64));
      expect(find.textContaining('Gecikme tazminatı yazıldı: Eylül 2026, 2 daire, toplam 123,45 ₺.'), findsOneWidget);
      expect(_changed, greaterThanOrEqualTo(1));
      expect(find.byKey(const ValueKey<String>('latefee_run_40')), findsOneWidget);
    });

    testWidgets('can_post: false -> onay KAPALI; yönlendirici engel metni ("Önce Eylül 2026 dönemini kapatın")', (t) async {
      final auth = _auth();
      auth.f4.latePreviewJson = f4LatePreviewJson(canPost: false, blockers: <String>['LATE_FEE_PERIOD_NOT_CLOSED']);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.text('Önce Eylül 2026 dönemini kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır.'), findsOneWidget);
      expect(
        _confirmButton(t).onPressed,
        isNull,
      );
      expect(auth.f4.callCount('postLateFee'), 0);
    });

    testWidgets('zincir sırası: LATE_FEE_PERIOD_NOT_NEXT beklenen ayı söyler', (t) async {
      final auth = _auth();
      auth.f4.latePreviewJson = <String, dynamic>{
        ...f4LatePreviewJson(canPost: false, blockers: <String>['LATE_FEE_PERIOD_NOT_NEXT']),
        'expected_period': '2026-08',
      };
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.textContaining('Sıradaki ay: Ağustos 2026'), findsOneWidget);
    });

    testWidgets('PREVIEW_STALE: önizleme OTOMATİK yenilenir, eski + yeni toplam yazılır, eski özetle tekrar yazılmaz', (t) async {
      final auth = _auth();
      auth.f4.latePostStaleOnce = true;
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      expect(auth.f4.latePostCalls, hasLength(1), reason: 'bayat önizlemeyle ikinci yazma denenmedi');
      expect(find.byKey(const ValueKey<String>('finance_latefee_notice')), findsOneWidget);
      expect(find.textContaining('Yeni toplam 130,45 ₺ (2 daire); önceki toplam 123,45 ₺ (2 daire) idi'), findsOneWidget);
      // Yeniden onay yeni özetle gider.
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      expect(auth.f4.latePostCalls, hasLength(2));
      expect(auth.f4.latePostCalls[1]['total'], 13045);
      expect(auth.f4.latePostCalls[1]['hash'], isNot(auth.f4.latePostCalls[0]['hash']));
      expect(auth.f4.lateRuns, hasLength(1));
    });

    testWidgets('yenileme sürerken / başarısızken eski önizlemeyle onay KAPALI', (t) async {
      final auth = _auth();
      auth.f4.latePostStaleOnce = true;
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      auth.f4.latePreviewError = ApiException('x', statusCode: 500);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_refresh')), findsOneWidget);
      final confirm = _confirmButton(t);
      expect(confirm.onPressed, isNull);
      expect(find.byKey(const ValueKey<String>('finance_latefee_blocked_reason')), findsOneWidget);
      auth.f4.latePreviewError = null;
      await f4Tap(t, 'finance_latefee_refresh');
      await settleFor(t);
      final again = _confirmButton(t);
      expect(again.onPressed, isNotNull);
    });

    testWidgets('muaf tutma: satır üstü çizilir, önizleme eskir; yenilenince toplam düşer; post muaf kimlikleri gönderir', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_waive_302');
      expect(find.byKey(const ValueKey<String>('finance_latefee_refresh')), findsOneWidget);
      final stale = _confirmButton(t);
      expect(stale.onPressed, isNull, reason: 'muaf listesi değişti: önce önizleme yenilenmeli');
      await f4Tap(t, 'finance_latefee_refresh');
      await settleFor(t);
      expect(auth.f4.latePreviewCalls.last['excluded'], <int>[302]);
      expect(find.text('100,00 ₺'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_latefee_waived')), findsOneWidget);
      f4ExpectSpokenMoney(t); // R14: "A Blok - 6: 23,45 ₺ (yazılmayacak)" satırı lira olarak okunur
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      expect(auth.f4.latePostCalls.single['excluded'], <int>[302]);
      expect(auth.f4.latePostCalls.single['total'], 10000);
      handle.dispose();
    });

    testWidgets('çift dokunuş: yazma sürerken ikinci istek yok; belirsiz sonuçtan sonra aynı özetle AYNI anahtar', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      auth.f4.latePostError = ApiException('x', statusCode: 502);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      auth.f4.latePostError = null;
      auth.f4.latePostGate = Completer<void>();
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await t.pump();
            expect(_confirmButton(t).onPressed, isNull, reason: 'işlem sürerken pasif');
      auth.f4.latePostGate!.complete();
      await settleFor(t);
      final keys = auth.f4.latePostCalls.map((c) => c['key']).toList();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1]);
      expect(auth.f4.lateRuns, hasLength(1));
    });

    testWidgets('sıfır tutarlı / pasif daire bildirimleri; boş plan', (t) async {
      final auth = _auth();
      auth.f4.latePreviewJson = <String, dynamic>{
        ...f4LatePreviewJson(),
        'lines': <dynamic>[],
        'total_minor': 0,
        'apartment_count': 0,
        'zero_amount_count': 2,
        'inactive_skipped': <Map<String, dynamic>>[
          <String, dynamic>{'apartment_id': 303, 'label': 'B Blok - 2'},
        ],
      };
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_zero')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_inactive')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_empty')), findsOneWidget);
    });

    testWidgets('önizleme hatası pencerede kalır; Geri formu açar', (t) async {
      final auth = _auth();
      auth.f4.latePreviewError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.text('Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_latefee_preview')), findsOneWidget);
    });

    f4Matrix('hesaplama penceresi: form ve önizleme taşmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _openCalc(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_period')), findsOneWidget);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_summary')), findsOneWidget);
      await f4Tap(t, 'finance_latefee_explain_301');
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_latefee_confirm')));
    });

    testWidgets('ekran okuyucu: toplam tutar "yüz yirmi üç lira kırk beş kuruş" okunur', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.bySemanticsLabel(RegExp('Toplam tazminat: yüz yirmi üç lira kırk beş kuruş')), findsOneWidget);
      handle.dispose();
    });
  });

  group('boş ay: "tazminat yok" işareti (record_empty)', () {
    void emptyMonth(FinanceFakeAuth auth, {List<String> blockers = const <String>[]}) {
      auth.f4.latePreviewJson = <String, dynamic>{
        ...f4LatePreviewJson(canPost: blockers.isEmpty, blockers: blockers),
        'lines': <Object?>[],
        'total_minor': 0,
        'apartment_count': 0,
      };
    }

    testWidgets('önizleme "empty": açıklama + "Ayı Kaydet"; onay metni; record_empty:true, beklenen 0/0 ve önizleme özeti gider', (t) async {
      final auth = _auth();
      emptyMonth(auth);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_latefee_empty')), findsOneWidget);
      expect(find.textContaining('"tazminat yok" olarak kaydedilir'), findsWidgets);
      expect(_confirmButton(t).onPressed, isNotNull, reason: 'engel yok: ay kaydedilebilir');
      expect(find.text('Ayı Kaydet'), findsWidgets);
      await f4Tap(t, 'finance_latefee_confirm');
      expect(find.text('Tazminat yok - ayı kaydet'), findsOneWidget);
      expect(auth.f4.callCount('postLateFee'), 0, reason: 'ikinci onay beklenir');
      await f4TapInDialog(t, 'Ayı Kaydet');
      await settleFor(t);
      final call = auth.f4.latePostCalls.single;
      expect(call['record_empty'], isTrue);
      expect(call['total'], 0);
      expect(call['count'], 0);
      expect((call['hash'] as String).startsWith('lf-'), isTrue);
      expect(find.textContaining('"tazminat yok" olarak kaydedildi'), findsOneWidget);
      // Geçmiş: işaret etiketi; satırlar düğmesi yok; son çalıştırma olarak iptal edilebilir.
      expect(find.text('Tazminat yok (işaret)'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('latefee_run_lines_40')), findsNothing);
      expect(find.byKey(const ValueKey<String>('latefee_run_void_40')), findsOneWidget);
    });

    testWidgets('işaret çalıştırması da normal çalıştırma gibi iptal edilir (metin: ters çevrilecek borç yok)', (t) async {
      final auth = _auth();
      emptyMonth(auth);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Ayı Kaydet');
      await settleFor(t);
      await f4Tap(t, 'latefee_run_void_40');
      expect(find.textContaining('Ters çevrilecek borç yoktur'), findsOneWidget);
      await f4Enter(t, 'finance_reason_text', 'Yanlış ay');
      await f4Tap(t, 'finance_reason_confirm');
      await settleFor(t);
      expect(auth.f4.lateRuns.single['status'], 'voided');
    });

    testWidgets('boş ama başka engel var (ay kapalı değil): onay KAPALI, engel metni yazılır', (t) async {
      final auth = _auth();
      emptyMonth(auth, blockers: <String>['LATE_FEE_PERIOD_NOT_CLOSED']);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(_confirmButton(t).onPressed, isNull);
      expect(find.textContaining('dönemini kapatın'), findsOneWidget);
      expect(auth.f4.callCount('postLateFee'), 0);
    });

    testWidgets('önizlemeden sonra aya satır çıktı: sunucu PREVIEW_STALE -> önizleme yenilenir, "Onayla ve Yaz"a döner, işaret YAZILMAZ', (t) async {
      final auth = _auth();
      emptyMonth(auth);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      // Araya ödeme girmiş gibi: satırlar belirdi.
      auth.f4.latePreviewJson = f4LatePreviewJson();
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Ayı Kaydet');
      await settleFor(t);
      expect(auth.f4.latePostCalls, hasLength(1));
      expect(auth.f4.lateRuns, isEmpty, reason: 'işaret yazılmadı');
      expect(find.byKey(const ValueKey<String>('finance_latefee_notice')), findsOneWidget);
      expect(find.text('Onayla ve Yaz'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_latefee_empty')), findsNothing);
    });
  });

  group('R14: kaydedilmemiş veri koruması (Vazgeç / geri tuşu)', () {
    testWidgets('Hesapla: muaf işaretlenmişse Vazgeç / geri tuşu onay sorar; hiçbir şey yazılmaz', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_latefee_confirm',
        open: () async {
          await _openCalc(t);
          await _preview(t);
        },
        edit: () async => f4Tap(t, 'finance_latefee_waive_302'),
      );
      expect(auth.f4.latePostCalls, isEmpty);
    });

    testWidgets('muaf işaretlenmemişse (yalnız ay seçimi) onay SORULMAZ: kolayca yeniden üretilebilir', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4TapInDialog(t, 'Vazgeç');
      expect(find.text('Değişiklikler silinsin mi?'), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_latefee_confirm')), findsNothing);
    });
  });

  group('REPORT_BUSY (503): yoğunluk iletisi + Tekrar Dene (otomatik yeniden deneme YOK)', () {
    testWidgets('tazminat önizlemesi', (t) async {
      final auth = _auth();
      auth.f4.latePreviewError = f4Coded('REPORT_BUSY', 503);
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      expect(find.textContaining('Yoğunluk var, biraz sonra tekrar deneyin.'), findsOneWidget);
      expect(auth.f4.latePreviewCalls, hasLength(1), reason: 'otomatik yeniden deneme yok');
      auth.f4.latePreviewError = null;
      await f4Tap(t, 'finance_latefee_preview_retry');
      await settleFor(t);
      expect(auth.f4.latePreviewCalls, hasLength(2));
      expect(find.byKey(const ValueKey<String>('finance_latefee_total')), findsOneWidget);
    });
  });

  group('son çalıştırmanın iptali', () {
    testWidgets('R15: tazminat iptali — aynı neden AYNI anahtar; neden değişince YENİ anahtar', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      await f4Tap(t, 'latefee_run_void_40');
      auth.f4.latePostError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await f4Enter(t, 'finance_reason_text', 'Yanlış oran');
      await f4Tap(t, 'finance_reason_confirm');
      await f4Tap(t, 'finance_reason_confirm');
      await f4Enter(t, 'finance_reason_text', 'Yanlış ay');
      await f4Tap(t, 'finance_reason_confirm');
      final keys = auth.f4.writes.where((w) => w['op'] == 'voidLateFeeRun').map((w) => w['key']).toList();
      expect(keys, hasLength(3));
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
    });

    testWidgets('neden zorunlu; iptalden sonra çalıştırma "İptal edildi"; sıradaki ay yeniden hesaplanabilir', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await _openCalc(t);
      await _preview(t);
      await f4Tap(t, 'finance_latefee_confirm');
      await f4TapInDialog(t, 'Yaz');
      await settleFor(t);
      await f4Tap(t, 'latefee_run_void_40');
      await f4Tap(t, 'finance_reason_confirm');
      expect(find.text('Neden girin.'), findsOneWidget);
      await f4Enter(t, 'finance_reason_text', 'Yanlış oran');
      await f4Tap(t, 'finance_reason_confirm');
      await settleFor(t);
      expect(auth.f4.lateRuns.single['status'], 'voided');
      expect(find.text('İptal edildi'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('latefee_run_void_40')), findsNothing);
    });

    testWidgets('LATE_FEE_RUN_NOT_VOIDABLE Türkçe, pencere açık', (t) async {
      final auth = _auth();
      auth.f4.lateRuns.add(<String, dynamic>{
        'id': 41,
        'period': '2026-07',
        'status': 'active',
        'total_minor': 10,
        'apartment_count': 1,
        'params': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0},
      });
      await _pump(t, auth);
      auth.f4.lateRuns.add(<String, dynamic>{
        'id': 42,
        'period': '2026-08',
        'status': 'active',
        'total_minor': 10,
        'apartment_count': 1,
        'params': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0},
      });
      // Arayüz 41'i son sanıyor (liste eski); sunucu 42 son diyor.
      await f4Tap(t, 'latefee_run_void_41');
      await f4Enter(t, 'finance_reason_text', 'Neden');
      await f4Tap(t, 'finance_reason_confirm');
      expect(find.text('Bu çalıştırma iptal edilemiyor: yalnızca son (aktif) tazminat çalıştırması iptal edilir; başka bir yönetici zaten iptal etmiş olabilir. Listeyi yenileyip kontrol edin.'), findsOneWidget);
    });
  });
}
