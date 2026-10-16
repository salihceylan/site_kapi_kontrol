// Platform Faz 4a: "Borçlandır" ve "Ek Borç Ekle" penceresi (FinanceRunDialog).
//
// Akış: form -> ÖNİZLEME (hiçbir şey yazmaz; daire listesi, toplam, eksik veri) -> onay. Para bütünlüğü:
// önizlemedeki toplam / daire sayısı sunucuya bildirilir; PREVIEW_STALE'de önizleme OTOMATİK yenilenir;
// eksik verili daire "atla" işaretlenmeden onaylanmaz; zaten borçlandırılmış / kapalı dönemde onay yoktur;
// aynı onay yeniden denemesi AYNI idempotency_key'i kullanır; çift gönderim ve eski önizleme yanıtı korumaları.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_run_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show tapFinder, tapText;
import 'people_fixtures.dart';
import 'site_application_fixtures.dart' show captureAnnouncements;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

class _Out {
  FinanceRunOutcome? result;
  bool closed = false;
  int refreshes = 0;
}

PeopleScope _scope(FinanceFakeAuth auth) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);

Future<_Out> _open(
  WidgetTester t,
  FinanceFakeAuth auth, {
  FeeDefinition? definition,
  double width = 400,
  double height = 1400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out();
  await openDialogAt(
    t,
    (context) async {
      out.result = definition == null
          ? await FinanceRunDialog.showCharge(
              context,
              scope: _scope(auth),
              now: () => _now,
              onRefreshNeeded: () => out.refreshes++,
            )
          : await FinanceRunDialog.showDefinition(
              context,
              scope: _scope(auth),
              definition: definition,
              now: () => _now,
              onRefreshNeeded: () => out.refreshes++,
            );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return out;
}

FeeDefinition _def(FinanceFakeAuth auth, int id) => FeeDefinition.fromJson(auth.definitions[id]!);

Future<void> _enter(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await scrollTo(t, finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _preview(WidgetTester t) async {
  await _tapKey(t, 'finance_run_preview');
  await settleFor(t);
}

Future<void> _confirm(WidgetTester t) async {
  await _tapKey(t, 'finance_run_confirm');
  await settleFor(t);
}

String _label(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey<String>('finance_period_label'))).data!;

bool _confirmEnabled(WidgetTester t) =>
    t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_run_confirm'))).onPressed != null;

/// 120 daireli site (sayfalama testi).
FinanceFakeAuth _bigSite() {
  final auth = FinanceFakeAuth.seeded();
  auth.apartmentsJson.clear();
  for (var i = 1; i <= 120; i++) {
    auth.apartmentsJson[1000 + i] = pplApartmentJson(1000 + i, 'A Blok - $i');
  }
  return auth;
}

void main() {
  group('taşma matrisi', () {
    layoutMatrix('Borçlandır: dönem seçimi (form)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Borçlandır'), findsWidgets);
      expect(_label(t), 'Ekim 2026');
      expect(find.text('Son borçlandırılan dönem: Eylül 2026.'), findsOneWidget);
      await scrollTo(t, find.text('Önizle'));
    });

    layoutMatrix('Borçlandır: önizleme (liste, toplam)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1), width: w, height: h, scale: s, dark: dark);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_summary')), findsOneWidget);
      expect(find.text('3 daire'), findsOneWidget);
      expect(find.text('1.500,00 ₺'), findsWidgets);
      await scrollTo(t, find.text('Onayla ve Borçlandır'));
      expect(find.text('Onayla ve Borçlandır'), findsOneWidget);
    });

    layoutMatrix('Borçlandır: eksik veri uyarısı + zaten borçlandırılmış + kapalı dönem', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[3] = finDefinition(3, name: 'Arsa payı aidatı', distribution: 'land_share', amount: 10000000)
        ..closedPeriods.add('2026-10');
      await _open(t, auth, definition: _def(auth, 3), width: w, height: h, scale: s, dark: dark);
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_missing')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_run_closed')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_skip_missing')));
    });

    layoutMatrix('Ek Borç Ekle: form (eşit / kategori / hedef)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Ek Borç Ekle'), findsWidgets);
      await _tapKey(t, 'charge_spec_dist_category');
      await scrollTo(t, find.byKey(const ValueKey<String>('charge_spec_add_category')));
      await _tapKey(t, 'charge_spec_add_category');
      await _tapKey(t, 'finance_target_blocks');
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_add_block')));
      await scrollTo(t, find.text('Önizle'));
    });
  });

  group('Borçlandır: dönem seçimi', () {
    testWidgets('varsayılan dönem = son borçlandırmadan sonraki ay; ay düğmeleri sınırlara uyar', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      expect(_label(t), 'Ekim 2026');
      await _tapKey(t, 'finance_period_next');
      expect(_label(t), 'Kasım 2026');
      for (var i = 0; i < 11; i++) {
        await _tapKey(t, 'finance_period_next');
      }
      expect(_label(t), 'Ekim 2027', reason: 'en çok 12 ay ileri');
      expect(
        t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_period_next'))).onPressed,
        isNull,
      );
      for (var i = 0; i < 12; i++) {
        await _tapKey(t, 'finance_period_prev');
      }
      expect(_label(t), 'Ekim 2026');
      for (var i = 0; i < 9; i++) {
        await _tapKey(t, 'finance_period_prev');
      }
      expect(_label(t), 'Ocak 2026', reason: 'başlangıç döneminden önceye gidilmez');
      expect(
        t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_period_prev'))).onPressed,
        isNull,
      );
    });

    testWidgets('hiç borçlandırılmamış tanım: bugünün ayı (başlangıçtan sonraysa)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[4] = finDefinition(4, name: 'Yeni aidat', start: '2026-03');
      await _open(t, auth, definition: _def(auth, 4));
      expect(_label(t), 'Ekim 2026');
      expect(find.text('Bu tanım henüz borçlandırılmadı.'), findsOneWidget);
    });

    testWidgets('tek seferlik tanım: dönem yok, isteğe bağlı vade tarihi', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[5] = finDefinition(5, name: 'Boya', kind: 'one_time', distribution: 'equal', amount: 90000);
      await _open(t, auth, definition: _def(auth, 5));
      expect(find.byKey(const ValueKey<String>('finance_period_label')), findsNothing);
      expect(find.text('Tek Seferlik Borçlandır'), findsWidgets);
      await _enter(t, 'finance_run_due_date', '05.11.2026');
      await _preview(t);
      expect(auth.previewCalls.single['due_date'], DateTime(2026, 11, 5));
      expect(auth.previewCalls.single['period'], isNull);
    });
  });

  group('Borçlandır: önizleme ve onay', () {
    testWidgets('önizleme HİÇBİR ŞEY yazmaz; liste, toplam; onay beklenen değerleri ve anahtarı gönderir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final before = auth.ledger.length;
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      expect(auth.previewCalls.single['period'], '2026-10');
      expect(auth.ledger.length, before, reason: 'önizleme yazmaz');
      expect(find.text('3 daire'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('B Blok - 2'), findsOneWidget);
      expect(find.text('Malik öder'), findsOneWidget, reason: '301: malik öder');
      expect(find.text('Kiracı öder'), findsOneWidget, reason: '302: kiracı öder');
      expect(find.text('Malik ve kiracı'), findsOneWidget, reason: '303: varsayılan');
      expect(auth.postCalls, isEmpty);

      await _confirm(t);
      expect(auth.postCalls.length, 1);
      final call = auth.postCalls.single;
      expect(call['period'], '2026-10');
      expect(call['expected_total_minor'], 150000);
      expect(call['expected_apartment_count'], 3);
      expect(call['skip_missing'], false);
      expect((call['idempotency_key'] as String).isNotEmpty, isTrue);
      expect(out.closed, isTrue);
      expect(out.result!.message, 'Aylık aidat: 3 daireye toplam 1.500,00 ₺ borç yazıldı.');
      expect(auth.ledger.length, before + 3);
      expect(auth.ledger.where((e) => e['period'] == '2026-10' && e['definition_name'] == 'Aylık aidat').length, 4);
    });

    testWidgets('daire listesi sayfalıdır: ilk 50, "Daha fazla göster" 50 daha', (t) async {
      final auth = _bigSite();
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      expect(find.text('120 daire'), findsOneWidget);
      expect(find.text('A Blok - 50'), findsOneWidget);
      expect(find.text('A Blok - 51'), findsNothing, reason: 'ilk sayfa 50 satır');
      expect(find.text('Daha fazla göster (70)'), findsOneWidget);
      await _tapKey(t, 'finance_run_more');
      expect(find.text('A Blok - 100'), findsOneWidget);
      expect(find.text('A Blok - 101'), findsNothing);
      expect(find.text('Daha fazla göster (20)'), findsOneWidget);
      await _tapKey(t, 'finance_run_more');
      expect(find.text('A Blok - 120'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_run_more')), findsNothing);
    });

    // W2 (inceleme düzeltmesi): önceki test adı "yeni önizleme yeni anahtar üretir" idi ve her önizleme anahtarı
    // SIFIRLIYORDU; yanıtı kaybolan bir onaydan sonra "Geri -> Önizle -> Onayla" bu yüzden ÇİFT borçlandırırdı. Artık
    // anahtar form içeriğine bağlıdır ve önizlemeler arasında değişmez.
    testWidgets('Geri: forma döner; seçilen dönem korunur; yeni önizleme işlem anahtarını DEĞİŞTİRMEZ', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      await _tapKey(t, 'finance_period_next');
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_summary')), findsOneWidget);
      await _tapKey(t, 'finance_run_back');
      expect(find.byKey(const ValueKey<String>('finance_run_summary')), findsNothing);
      expect(_label(t), 'Kasım 2026');
      await _preview(t);
      expect(auth.previewCalls.length, 2);
      expect(auth.previewCalls.last['period'], '2026-11');
    });

    testWidgets('yazıldı ama yanıt kayboldu: Geri -> Önizle -> Onayla ÇİFT borç yazmaz (aynı anahtar)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..errorsAfterWrite.add(ApiException('Sunucuya ulaşılamadı.'));
      final before = auth.ledger.length;
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      // İstek sunucuda İŞLENDİ (3 satır yazıldı) ama yanıt kayboldu.
      expect(auth.ledger.length, before + 3);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      expect(out.closed, isFalse);

      await _tapKey(t, 'finance_run_back');
      await _preview(t);
      // Yenilenen önizleme artık "zaten borçlandırılmış" der ve onay kapalıdır: ikinci yazma denenemez.
      expect(find.byKey(const ValueKey<String>('finance_run_already_posted')), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
      expect(auth.postCalls.length, 1);
      expect(auth.ledger.length, before + 3, reason: 'çift kayıt yok');
    });

    testWidgets('zaten borçlandırılmış dönem: uyarı, onay AÇILMAZ', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      await _tapKey(t, 'finance_period_prev'); // Eylül: son borçlandırılan
      await _preview(t);
      expect(
        find.text('Bu tanım bu dönem için zaten borçlandırılmış. Aynı ay ikinci kez borçlandırılamaz.'),
        findsOneWidget,
      );
      expect(_confirmEnabled(t), isFalse);
      expect(auth.postCalls, isEmpty);
    });

    testWidgets('kapalı dönem: uyarı, onay AÇILMAZ', (t) async {
      final auth = FinanceFakeAuth.seeded()..closedPeriods.add('2026-10');
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_closed')), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
    });

    testWidgets('hedefte daire yok: "Borçlandırılacak daire bulunamadı" ve onay yok', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[6] = finDefinition(
          6,
          name: 'Boş hedef',
          targetType: 'apartments',
          apartmentIds: const <int>[9999],
        );
      await _open(t, auth, definition: _def(auth, 6));
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_empty')), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
    });
  });

  group('Borçlandır: eksik veri', () {
    FinanceFakeAuth withMissing() => FinanceFakeAuth.seeded()
      ..definitions[3] = finDefinition(3, name: 'Arsa payı aidatı', distribution: 'land_share', amount: 6000000);

    testWidgets('eksik verili daire listelenir, neden Türkçe; atla işaretlenmeden onay yok', (t) async {
      final auth = withMissing();
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      expect(find.text('1 dairenin bilgisi eksik'), findsOneWidget);
      expect(find.text('B Blok - 2: Arsa payı tanımlı değil.'), findsOneWidget);
      expect(find.text('2 daire'), findsOneWidget, reason: 'yalnız hesaplanabilen daireler borçlanır');
      expect(_confirmEnabled(t), isFalse);

      await _tapKey(t, 'finance_skip_missing');
      expect(_confirmEnabled(t), isTrue);
      await _confirm(t);
      expect(auth.postCalls.single['skip_missing'], true);
      expect(auth.postCalls.single['expected_apartment_count'], 2);
      // Toplam payların toplamı = tutar (en büyük kalan).
      final posted = auth.ledger.where((e) => e['definition_name'] == 'Arsa payı aidatı');
      expect(posted.fold<int>(0, (a, e) => a + (e['amount_minor'] as int)), 6000000);
    });

    testWidgets('atla seçeneği kapatılınca onay yeniden kapanır', (t) async {
      final auth = withMissing();
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      await _tapKey(t, 'finance_skip_missing');
      expect(_confirmEnabled(t), isTrue);
      await _tapKey(t, 'finance_skip_missing');
      expect(_confirmEnabled(t), isFalse);
    });
  });

  group('Borçlandır: PREVIEW_STALE, hata ve yeniden deneme', () {
    testWidgets('PREVIEW_STALE: önizleme OTOMATİK yenilenir, uyarı gösterilir; yeni onay yeni toplamla ve yeni anahtarla', (t) async {
      final auth = FinanceFakeAuth.seeded()..staleOnFirstPost = true;
      final before = auth.ledger.length;
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      expect(find.text('3 daire'), findsOneWidget);
      await _confirm(t);

      expect(auth.postCalls.length, 1);
      expect(auth.previewCalls.length, 2, reason: 'önizleme otomatik yenilendi');
      expect(out.closed, isFalse);
      expect(find.byKey(const ValueKey<String>('finance_run_notice')), findsOneWidget);
      // W4: eski ve yeni toplam birlikte yazılır; yeni önizleme gösterilir.
      expect(find.textContaining('Veriler değişti, önizleme yenilendi.'), findsOneWidget);
      expect(find.textContaining('Yeni toplam 2.000,00 ₺ (4 daire)'), findsOneWidget);
      expect(find.textContaining('önceki toplam 1.500,00 ₺ (3 daire) idi'), findsOneWidget);
      expect(find.text('4 daire'), findsOneWidget, reason: 'araya giren yeni daire görünür');
      expect(find.text('2.000,00 ₺'), findsWidgets);
      expect(auth.ledger.length, before, reason: 'bayat onayda hiçbir şey yazılmaz');

      await _confirm(t);
      expect(auth.postCalls.length, 2);
      expect(auth.postCalls[1]['expected_total_minor'], 200000);
      expect(auth.postCalls[1]['expected_apartment_count'], 4);
      expect(auth.postCalls[1]['expected_hash'], isNot(auth.postCalls[0]['expected_hash']),
          reason: 'onay YENİ önizlemenin özetini taşır');
      // W2: işlem anahtarı form içeriğine bağlıdır; önizleme yenilemesi onu değiştirmez (sunucu stale ile hiçbir şey
      // kaydetmediği için aynı anahtarla yeni onay güvenlidir).
      expect(auth.postCalls[1]['idempotency_key'], auth.postCalls[0]['idempotency_key']);
      expect(out.closed, isTrue);
      expect(auth.ledger.length, before + 4);
    });

    testWidgets('önizleme YENİLENİRKEN (PREVIEW_STALE sonrası) eski önizlemeyle onay verilemez', (t) async {
      final auth = FinanceFakeAuth.seeded()..staleOnFirstPost = true;
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      final slow = Completer<void>();
      auth.previewGates.add(slow); // ikinci (otomatik yenileme) önizlemesi yavaş
      await _tapKey(t, 'finance_run_confirm');
      expect(auth.postCalls.length, 1);
      expect(auth.previewCalls.length, 2);
      expect(_confirmEnabled(t), isFalse, reason: 'yenilenen önizleme gelene dek onay kapalı');
      await t.tap(find.byKey(const ValueKey<String>('finance_run_confirm')), warnIfMissed: false);
      await t.pump();
      expect(auth.postCalls.length, 1, reason: 'bayat önizlemeyle ikinci onay gönderilmez');
      slow.complete();
      await settleFor(t);
      expect(_confirmEnabled(t), isTrue);
      expect(find.text('4 daire'), findsOneWidget);
    });

    testWidgets('ağ hatası: sonuç belirsiz uyarısı; aynı onay AYNI anahtarla yeniden denenir; tek kayıt', (t) async {
      final auth = FinanceFakeAuth.seeded()..postError = ApiException('Sunucuya ulaşılamadı.');
      final before = auth.ledger.length;
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      expect(out.closed, isFalse);
      expect(_confirmEnabled(t), isTrue);

      auth.postError = null;
      await _confirm(t);
      expect(auth.postCalls.length, 2);
      expect(auth.postCalls[1]['idempotency_key'], auth.postCalls[0]['idempotency_key']);
      expect(out.closed, isTrue);
      expect(auth.ledger.length, before + 3, reason: 'aynı anahtar: tek borçlandırma');
    });

    testWidgets('ağ hatası sonrası pencere kapatılırsa çağıran listeyi tazeler', (t) async {
      final auth = FinanceFakeAuth.seeded()..postError = ApiException('Sunucuya ulaşılamadı.');
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(out.refreshes, 1);
    });

    testWidgets('PERIOD_ALREADY_POSTED (başka yönetici borçlandırdı): mesaj + önizleme yenilenir + liste tazelenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      // Araya giren başka yönetici aynı ayı borçlandırdı.
      auth.definitions[1]!['last_posted_period'] = '2026-10';
      await _confirm(t);
      expect(find.text(AuthApi.messageForErrorCode('PERIOD_ALREADY_POSTED')!), findsWidgets);
      expect(auth.previewCalls.length, 2);
      expect(_confirmEnabled(t), isFalse, reason: 'yenilenen önizleme "zaten borçlandırılmış" der');
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.refreshes, 1);
    });

    testWidgets('PERIOD_CLOSED: kapalı dönem mesajı, onay kapanır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      auth.closedPeriods.add('2026-10');
      await _confirm(t);
      expect(find.text(AuthApi.messageForErrorCode('PERIOD_CLOSED')!), findsWidgets);
      expect(_confirmEnabled(t), isFalse);
    });

    testWidgets('DEFINITION_INACTIVE: Türkçe hata, pencere açık, kapanırken liste tazelenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      auth.definitions[1]!['is_active'] = false;
      await _confirm(t);
      expect(find.text(AuthApi.messageForErrorCode('DEFINITION_INACTIVE')!), findsOneWidget);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsNothing);
      expect(out.closed, isFalse);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.refreshes, 1);
    });

    testWidgets('onay sürerken: düğme kilitli "Yazılıyor...", tek istek; geri tuşu ve Geri kapatmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..postGate = Completer<void>();
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _tapKey(t, 'finance_run_confirm');
      expect(find.text('Yazılıyor...'), findsOneWidget);
      expect(auth.postCalls.length, 1);
      await t.tap(find.text('Yazılıyor...'), warnIfMissed: false);
      await t.pump();
      expect(auth.postCalls.length, 1, reason: 'çift dokunuş ikinci istek göndermez');
      expect(t.widget<TextButton>(find.byKey(const ValueKey<String>('finance_run_back'))).onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(FinanceRunDialog), findsOneWidget);
      auth.postGate!.complete();
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(auth.postCalls.length, 1);
    });

    testWidgets('eski önizleme yanıtı: Geri ile formdan çıkıp yeniden önizlenince geç gelen ESKİ yanıt yenisini ezmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      // İlk önizleme (Ekim) yavaş.
      final slow = Completer<void>();
      auth.previewGates.add(slow);
      await _tapKey(t, 'finance_run_preview');
      expect(find.text('Hesaplanıyor...'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_run_summary')), findsNothing);
      slow.complete();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_run_summary')), findsOneWidget);

      // Geri, Kasım'a geç, yavaş ikinci önizleme sürerken tekrar Geri: önizleme gelse de form kalır.
      await _tapKey(t, 'finance_run_back');
      await _tapKey(t, 'finance_period_next');
      final slow2 = Completer<void>();
      auth.previewGates.add(slow2);
      await _tapKey(t, 'finance_run_preview');
      expect(find.text('Hesaplanıyor...'), findsOneWidget);
      slow2.complete();
      await settleFor(t);
      expect(_confirmEnabled(t), isTrue);
    });

    testWidgets('modül kapalı (403): Türkçe mesaj, önizleme gelmez', (t) async {
      final auth = FinanceFakeAuth.seeded()..moduleEnabled = false;
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      expect(find.text(AuthApi.messageForErrorCode('MODULE_DISABLED')!), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_run_summary')), findsNothing);
    });

    testWidgets('hız sınırı (429) onayda: mesaj, düğme geçici kilitli', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..postError = ApiException('x', statusCode: 429, retryAfterSeconds: 60);
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
    });
  });

  group('Ek Borç Ekle', () {
    testWidgets('boş gönderim: özet + alan hataları, sunucuya gidilmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _preview(t);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.text('Borç adını girin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(auth.chargePreviewCalls, isEmpty);
    });

    testWidgets('eşit bölüş: toplam tutar en büyük kalanla bölünür, payların toplamı tutara EŞİT', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _open(t, auth);
      await _enter(t, 'finance_charge_name', '  Asansör yenileme  ');
      await _tapKey(t, 'charge_spec_dist_equal');
      await _enter(t, 'charge_spec_amount', '100.000');
      expect(find.text('Girilen tutar: 100.000,00 ₺'), findsOneWidget);
      await _preview(t);
      expect(auth.chargePreviewCalls.single['name'], 'Asansör yenileme');
      expect(auth.chargePreviewCalls.single['distribution'], 'equal');
      expect(auth.chargePreviewCalls.single['amount_minor'], 10000000);
      expect(auth.chargePreviewCalls.single['target'], <String, dynamic>{'type': 'site'});
      expect(find.text('3 daire'), findsOneWidget);
      expect(find.text('33.333,34 ₺'), findsOneWidget, reason: 'kalan kuruş id sırasıyla ilk daireye');
      expect(find.text('33.333,33 ₺'), findsNWidgets(2));
      expect(auth.ledger.where((e) => e['definition_name'] == 'Asansör yenileme'), isEmpty);

      await _confirm(t);
      expect(auth.chargePostCalls.length, 1);
      expect(auth.chargePostCalls.single['expected_total_minor'], 10000000);
      expect(auth.chargePostCalls.single['expected_apartment_count'], 3);
      expect(out.result!.message, 'Ek borç yazıldı: 3 daire, toplam 100.000,00 ₺.');
      final posted = auth.ledger.where((e) => e['definition_name'] == 'Asansör yenileme').toList();
      expect(posted.length, 3);
      expect(posted.fold<int>(0, (a, e) => a + (e['amount_minor'] as int)), 10000000);
    });

    testWidgets('Geri: form değerleri KORUNUR', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'Boya');
      await _tapKey(t, 'charge_spec_dist_equal');
      await _enter(t, 'charge_spec_amount', '1.200,50');
      await _preview(t);
      await _tapKey(t, 'finance_run_back');
      expect(
        t.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey<String>('finance_charge_name')),
          matching: find.byType(TextField),
        )).controller!.text,
        'Boya',
      );
      expect(
        t.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey<String>('charge_spec_amount')),
          matching: find.byType(TextField),
        )).controller!.text,
        '1.200,50',
      );
    });

    testWidgets('arsa payı + eksik veri: atla ile yazılır; sabit tutar daire başına', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'Çatı');
      await _tapKey(t, 'charge_spec_dist_land_share');
      await _enter(t, 'charge_spec_amount', '60.000');
      await _preview(t);
      expect(find.text('B Blok - 2: Arsa payı tanımlı değil.'), findsOneWidget);
      expect(_confirmEnabled(t), isFalse);
      await _tapKey(t, 'finance_skip_missing');
      await _confirm(t);
      expect(auth.chargePostCalls.single['skip_missing'], true);
      expect(auth.chargePostCalls.single['distribution'], 'land_share');
      final posted = auth.ledger.where((e) => e['definition_name'] == 'Çatı').toList();
      expect(posted.length, 2);
      expect(posted.fold<int>(0, (a, e) => a + (e['amount_minor'] as int)), 6000000);
    });

    testWidgets('kategori: tutar alanı yerine kategori haritası; harita kuruş olarak gider', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'Su sayacı');
      await _tapKey(t, 'charge_spec_dist_category');
      expect(find.byKey(const ValueKey<String>('charge_spec_amount')), findsNothing);
      await _enter(t, 'charge_spec_category_name_0', '3+1');
      await _enter(t, 'charge_spec_category_amount_0', '750,50');
      await _tapKey(t, 'charge_spec_add_category');
      await _enter(t, 'charge_spec_category_name_1', '2+1');
      await _enter(t, 'charge_spec_category_amount_1', '500');
      await _preview(t);
      expect(auth.chargePreviewCalls.single['category_amounts'], <String, dynamic>{'3+1': 75050, '2+1': 50000});
      expect(auth.chargePreviewCalls.single.containsKey('amount_minor'), isFalse);
      // 303 kategorisiz: eksik veri.
      expect(find.text('B Blok - 2: Kategori tanımlı değil.'), findsOneWidget);
      expect(find.text('2 daire'), findsOneWidget);
    });

    testWidgets('kategori kuralları: yinelenen ad, boş ad / tutar, son satır silinince "en az bir kategori"', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'X');
      await _tapKey(t, 'charge_spec_dist_category');
      await _preview(t);
      expect(find.text('Kategori adını girin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);

      await _enter(t, 'charge_spec_category_name_0', '3+1');
      await _enter(t, 'charge_spec_category_amount_0', '100');
      await _tapKey(t, 'charge_spec_add_category');
      await _enter(t, 'charge_spec_category_name_1', ' 3+1 ');
      await _enter(t, 'charge_spec_category_amount_1', '200');
      await _preview(t);
      expect(find.text('Aynı kategori adı iki kez girilmiş.'), findsOneWidget);
      expect(auth.chargePreviewCalls, isEmpty);

      await _tapKey(t, 'charge_spec_category_remove_1');
      await _tapKey(t, 'charge_spec_category_remove_0');
      await _preview(t);
      expect(find.text('En az bir kategori ekleyin.'), findsOneWidget);
    });

    testWidgets('vade tarihi geçersizse reddedilir; geçerliyse gövdeye YYYY-AA-GG girer', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'Boya');
      await _tapKey(t, 'charge_spec_dist_equal');
      await _enter(t, 'charge_spec_amount', '300');
      await _enter(t, 'finance_run_due_date', '32.13.2026');
      await _preview(t);
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      expect(auth.chargePreviewCalls, isEmpty);
      await _enter(t, 'finance_run_due_date', '05.11.2026');
      await _preview(t);
      expect(auth.chargePreviewCalls.single['due_date'], '2026-11-05');
    });

    testWidgets('hedef blok seçimi boşsa "En az bir blok seçin."', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'Boya');
      await _tapKey(t, 'charge_spec_dist_equal');
      await _enter(t, 'charge_spec_amount', '300');
      await _tapKey(t, 'finance_target_blocks');
      await _preview(t);
      expect(find.text('En az bir blok seçin.'), findsOneWidget);
      expect(auth.chargePreviewCalls, isEmpty);
    });

    testWidgets('kapalı ay: sunucu reddi (PERIOD_CLOSED) Türkçe', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await _enter(t, 'finance_charge_name', 'Boya');
      await _tapKey(t, 'charge_spec_dist_equal');
      await _enter(t, 'charge_spec_amount', '300');
      await _preview(t);
      auth.closedPeriods.add('2026-10');
      await _confirm(t);
      expect(find.text(AuthApi.messageForErrorCode('PERIOD_CLOSED')!), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------------------------------
  // İnceleme düzeltmeleri (W2, W4, W7, W14, W17): para bütünlüğü ve erişilebilirlik.
  // ---------------------------------------------------------------------------------------------------

  /// Ek borç formunu doldurur: ad, eşit bölüş, toplam tutar (tüm site: 3 daire).
  Future<void> fillCharge(WidgetTester t, {String name = 'Asansör', String amount = '90'}) async {
    await _enter(t, 'finance_charge_name', name);
    await _tapKey(t, 'charge_spec_dist_equal');
    await _enter(t, 'charge_spec_amount', amount);
  }

  int chargeRows(FinanceFakeAuth auth, [String name = 'Asansör']) =>
      auth.ledger.where((e) => e['definition_name'] == name).length;

  Future<void> tapInDialog(WidgetTester t, String label) =>
      tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text(label)));

  group('W2: ek borç işlem anahtarı ve tekrar koruması', () {
    testWidgets('yazıldı ama yanıt kayboldu: Geri -> Önizle -> Onayla; önizleme "yakın zamanda yazıldı" der, '
        'uyarı penceresinde Vazgeç ÇİFT borç yazmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..errorsAfterWrite.add(ApiException('Sunucuya ulaşılamadı.'));
      final out = await _open(t, auth);
      await fillCharge(t);
      await _preview(t);
      await _confirm(t);
      expect(chargeRows(auth), 3, reason: 'istek sunucuda işlendi');
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);

      await _tapKey(t, 'finance_run_back');
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_duplicate')), findsOneWidget);
      await _confirm(t);
      expect(find.text('Aynı ek borç daha önce kaydedilmiş'), findsOneWidget);
      expect(
        find.textContaining('Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Önce daire hesaplarını kontrol edin.'),
        findsWidgets,
      );
      expect(auth.chargePostCalls.length, 1, reason: 'uyarı penceresi açıkken istek gönderilmez');
      await tapInDialog(t, 'Vazgeç');
      await settleFor(t);
      expect(auth.chargePostCalls.length, 1);
      expect(chargeRows(auth), 3, reason: 'çift borç yok');
      expect(out.closed, isFalse);
    });

    testWidgets('önizleme "yakın zamanda yazıldı" demese de Geri -> Önizle -> Onayla AYNI anahtarı gönderir: '
        'sunucu kaydı yeniden oynatır, çift borç yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..omitDuplicateHint = true
        ..errorsAfterWrite.add(ApiException('Sunucuya ulaşılamadı.'));
      final out = await _open(t, auth);
      await fillCharge(t);
      await _preview(t);
      await _confirm(t);
      expect(chargeRows(auth), 3);
      await _tapKey(t, 'finance_run_back');
      await _preview(t);
      await _confirm(t);
      expect(auth.chargePostCalls.length, 2);
      expect(auth.chargePostCalls[1]['idempotency_key'], auth.chargePostCalls[0]['idempotency_key']);
      expect(chargeRows(auth), 3, reason: 'aynı anahtar: kayıt yeniden oynatıldı, çift yazılmadı');
      expect(out.closed, isTrue);
    });

    testWidgets('form içeriği değişince YENİ anahtar; eski anahtar geri gelince aynı kalır (A -> B -> A)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..omitDuplicateHint = true
        ..postError = ApiException('Sunucuya ulaşılamadı.');
      await _open(t, auth);
      await fillCharge(t, amount: '90');
      await _preview(t);
      await _confirm(t); // A: yanıt yok
      await _tapKey(t, 'finance_run_back');
      await _enter(t, 'charge_spec_amount', '120');
      await _preview(t);
      await _confirm(t); // B
      await _tapKey(t, 'finance_run_back');
      await _enter(t, 'charge_spec_amount', '90');
      await _preview(t);
      await _confirm(t); // A yeniden
      final keys = auth.chargePostCalls.map((c) => c['idempotency_key']).toList();
      expect(keys.length, 3);
      expect(keys[1], isNot(keys[0]), reason: 'içerik değişti: yeni anahtar');
      expect(keys[2], keys[0], reason: 'A içeriği geri geldi: AYNI anahtar');
    });

    testWidgets('DUPLICATE_CHARGE (önizleme haber vermedi): uyarı penceresi + "Yine de ekle" '
        'allow_duplicate ve YENİ anahtarla yazar', (t) async {
      final auth = FinanceFakeAuth.seeded()..omitDuplicateHint = true;
      // Bir saat önce aynı ek borç yazılmış.
      await auth.postExtraCharge(
        11,
        const ExtraChargeInput(name: 'Asansör', distribution: FeeDistribution.equal, amountMinor: 9000),
        expectedTotalMinor: 9000,
        expectedApartmentCount: 3,
        idempotencyKey: 'onceki-kayit',
      );
      expect(chargeRows(auth), 3);
      final seeded = auth.chargePostCalls.length; // hazırlık çağrısı sayaca girer
      final out = await _open(t, auth);
      await fillCharge(t, amount: '90');
      await _preview(t);
      await _confirm(t);
      expect(auth.chargePostCalls.length, seeded + 1);
      expect(auth.chargePostCalls.last['allow_duplicate'], false);
      expect(find.text('Aynı ek borç daha önce kaydedilmiş'), findsOneWidget);
      expect(find.textContaining('Önceki kayıt:'), findsOneWidget, reason: 'önceki kaydın zamanı yazılır');
      expect(chargeRows(auth), 3);

      await tapInDialog(t, 'Yine de ekle');
      await settleFor(t);
      expect(auth.chargePostCalls.length, seeded + 2);
      expect(auth.chargePostCalls.last['allow_duplicate'], true);
      expect(
        auth.chargePostCalls.last['idempotency_key'],
        isNot(auth.chargePostCalls[seeded]['idempotency_key']),
        reason: '"Yine de ekle" YENİ işlem anahtarı kullanır',
      );
      expect(chargeRows(auth), 6, reason: 'bilinçli tekrar yazıldı');
      expect(out.closed, isTrue);
    });

    testWidgets('IDEMPOTENCY_CONFLICT: hesapları kontrol et uyarısı; sonraki deneme yeni anahtar alır', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..omitDuplicateHint = true
        ..postError = ApiException(
          AuthApi.messageForErrorCode('IDEMPOTENCY_CONFLICT')!,
          statusCode: 409,
          code: 'IDEMPOTENCY_CONFLICT',
        );
      final out = await _open(t, auth);
      await fillCharge(t);
      await _preview(t);
      await _confirm(t);
      expect(find.text(AuthApi.messageForErrorCode('IDEMPOTENCY_CONFLICT')!), findsOneWidget);
      expect(out.closed, isFalse);
      auth.postError = null;
      await _confirm(t);
      expect(auth.chargePostCalls.length, 2);
      expect(auth.chargePostCalls[1]['idempotency_key'], isNot(auth.chargePostCalls[0]['idempotency_key']));
    });

    testWidgets('aylık borçlandırma: yanıtı kayıp onaydan sonra Geri -> Önizle AYNI anahtarı korur', (t) async {
      final auth = FinanceFakeAuth.seeded()..postError = ApiException('Sunucuya ulaşılamadı.');
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      await _tapKey(t, 'finance_run_back');
      await _preview(t);
      await _confirm(t);
      expect(auth.postCalls.length, 2);
      expect(auth.postCalls[1]['idempotency_key'], auth.postCalls[0]['idempotency_key']);
    });
  });

  group('W4: PREVIEW_STALE, özet (hash) ve yeniden paylaştırma', () {
    FinanceFakeAuth withMissing() => FinanceFakeAuth.seeded()
      ..definitions[3] = finDefinition(3, name: 'Arsa payı aidatı', distribution: 'land_share', amount: 6000000);

    testWidgets('onay önizlemenin özetini (expected_hash) gönderir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      expect((auth.postCalls.single['expected_hash'] as String?)?.isNotEmpty, isTrue);
    });

    testWidgets('eski sunucu (preview_hash yok): onay hash göndermez, yeniden paylaştırma notu çıkmaz', (t) async {
      final auth = withMissing()..omitPreviewHash = true;
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_redistributed')), findsNothing);
      await _tapKey(t, 'finance_skip_missing');
      await _confirm(t);
      expect(auth.postCalls.single['expected_hash'], isNull);
    });

    testWidgets('toplam ve sayı AYNI kalsa da özet değişirse (paylar takas) sunucu PREVIEW_STALE der; '
        'önizleme güncel paylarla yenilenir', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..apartmentsJson[303] = pplApartmentJson(303, 'B Blok - 2', blockId: 2, shareN: 20, shareD: 1000)
        ..definitions[3] = finDefinition(3, name: 'Arsa payı aidatı', distribution: 'land_share', amount: 6000000);
      auth.apartmentsJson[301] = pplApartmentJson(301, 'A Blok - 5', shareN: 30, shareD: 1000, party: 'owner');
      auth.apartmentsJson[302] = pplApartmentJson(302, 'A Blok - 6', shareN: 50, shareD: 1000, party: 'tenant');
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      final before = auth.ledger.length;
      // Onaydan önce 301 ile 302'nin payları takas edilir: toplam (60.000 ₺) ve daire sayısı (3) değişmez.
      auth.beforeNextPost = () {
        final a = auth.apartmentsJson[301]!['land_share'];
        auth.apartmentsJson[301]!['land_share'] = auth.apartmentsJson[302]!['land_share'];
        auth.apartmentsJson[302]!['land_share'] = a;
      };
      await _confirm(t);
      expect(auth.postCalls.length, 1);
      expect(auth.ledger.length, before, reason: 'hiçbir şey yazılmadı');
      expect(find.textContaining('Veriler değişti, önizleme yenilendi.'), findsOneWidget);
      expect(auth.previewCalls.length, 2, reason: 'önizleme yenilendi');
    });

    testWidgets('yenileme BAŞARISIZ olursa "önizleme yenilendi" yazılmaz; hata + eski onay kapalı; '
        '"Önizlemeyi Yenile" ile düzelir', (t) async {
      final auth = FinanceFakeAuth.seeded()..staleOnFirstPost = true;
      final out = await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      auth.previewError = ApiException('Sunucuya ulaşılamadı.');
      await _confirm(t);
      expect(auth.postCalls.length, 1);
      expect(find.textContaining('önizleme yenilendi'), findsNothing);
      expect(find.text('Sunucuya ulaşılamadı.'), findsOneWidget);
      expect(_confirmEnabled(t), isFalse, reason: 'eski önizlemeyle onay kapalı');
      expect(find.byKey(const ValueKey<String>('finance_run_refresh')), findsOneWidget);
      expect(find.textContaining('Önizleme eskidi'), findsWidgets, reason: 'nedeni yazılır');

      // Eski önizlemeyle zorla onay denense bile istek gitmez.
      await t.tap(find.byKey(const ValueKey<String>('finance_run_confirm')), warnIfMissed: false);
      await t.pump();
      expect(auth.postCalls.length, 1);

      auth.previewError = null;
      await _tapKey(t, 'finance_run_refresh');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_run_refresh')), findsNothing);
      expect(find.textContaining('Yeni toplam 2.000,00 ₺ (4 daire)'), findsOneWidget);
      expect(_confirmEnabled(t), isTrue);
      await _confirm(t);
      expect(out.closed, isTrue);
    });

    testWidgets('redistributed: eksik bilgili daire sayısı ve yeniden paylaştırma notu ONAYDAN ÖNCE görünür', (t) async {
      final auth = withMissing();
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      expect(
        find.text('Eksik bilgili 1 daire hariç tutuldu; tutar kalan dairelere yeniden paylaştırılır.'),
        findsOneWidget,
      );
      expect(auth.postCalls, isEmpty, reason: 'henüz onay yok');
    });

    testWidgets('sabit tutarda (yeniden paylaştırılmaz) not çıkmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[4] = finDefinition(
          4,
          name: 'Kategorili',
          distribution: 'category',
          categories: <String, int>{'3+1': 75000},
        );
      await _open(t, auth, definition: _def(auth, 4));
      await _preview(t);
      expect(find.byKey(const ValueKey<String>('finance_run_missing')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_run_redistributed')), findsNothing);
    });
  });

  group('W7: gizli form alanı odaklanamaz', () {
    testWidgets('önizleme gösterilirken Offstage form odağa KAPALI; Geri ile geri açılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth);
      await fillCharge(t);
      await _preview(t);
      EditableText nameField() => t.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey<String>('finance_charge_name'), skipOffstage: false),
        matching: find.byType(EditableText, skipOffstage: false),
        skipOffstage: false,
      ));
      final hidden = nameField().focusNode;
      hidden.requestFocus();
      await t.pump();
      expect(hidden.hasFocus, isFalse, reason: 'gizli alan odak alamaz');

      await _tapKey(t, 'finance_run_back');
      final visible = nameField().focusNode;
      visible.requestFocus();
      await t.pump();
      expect(visible.hasFocus, isTrue, reason: 'form görünürken alan odak alır');
    });
  });

  group('W14 / W17: onay nedeni, daire etiketi, tutar okunuşu', () {
    testWidgets('onay pasifken NEDEN düğmeyle ilişkilendirilir (ipucu) ve ekranda yazılır', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[3] = finDefinition(3, name: 'Arsa payı aidatı', distribution: 'land_share', amount: 6000000);
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      expect(_confirmEnabled(t), isFalse);
      final reason = t.widget<Text>(find.byKey(const ValueKey<String>('finance_run_blocked_reason'))).data!;
      expect(reason, startsWith('Onaylamak için:'));
      expect(reason, contains('Eksik bilgili daireleri atla'));
      final handle = t.ensureSemantics();
      final data = t.getSemantics(find.byKey(const ValueKey<String>('finance_run_confirm')));
      expect(data.label, 'Onayla ve Borçlandır');
      expect(data.hint, contains('Eksik bilgili daireleri atla'));
      handle.dispose();
      // İşaretlenince neden satırı kalkar ve düğme açılır.
      await _tapKey(t, 'finance_skip_missing');
      expect(find.byKey(const ValueKey<String>('finance_run_blocked_reason')), findsNothing);
      expect(_confirmEnabled(t), isTrue);
    });

    testWidgets('eksik veri satırı blok adını da yazar', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[3] = finDefinition(3, name: 'Arsa payı aidatı', distribution: 'land_share', amount: 6000000);
      // Etiket yalnız "Daire 2", blok adı ayrı alanda (gerçek sunucu biçimi).
      auth.apartmentsJson[303] = <String, dynamic>{
        ...auth.apartmentsJson[303]!,
        'label': 'Daire 2',
        'block_name': 'B Blok',
      };
      await _open(t, auth, definition: _def(auth, 3));
      await _preview(t);
      expect(find.text('B Blok / Daire 2: Arsa payı tanımlı değil.'), findsOneWidget);
    });

    testWidgets('önizleme özeti TEK birleşik etiketle okunur (başlık / sayı / toplam iki kez okunmaz)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel('Önizleme. Dönem: Ekim 2026. 3 daire. Toplam borç: bin beş yüz lira'),
        findsOneWidget,
      );
      // Parça parça okunan eski etiketler artık ayrı düğüm değildir.
      expect(find.bySemanticsLabel('Toplam: bin beş yüz lira'), findsNothing);
      handle.dispose();
    });

    testWidgets('320x640 x2,0: önizleme satırında tutar daire adının altına iner, taşma yok', (t) async {
      final auth = _bigSite();
      await _open(t, auth, definition: _def(auth, 1), width: 320, height: 640, scale: 2.0);
      await _preview(t);
      expect(find.text('A Blok - 1'), findsOneWidget);
      expect(t.takeException(), isNull);
      final title = t.getTopLeft(find.text('A Blok - 1'));
      final amount = t.getTopLeft(find.text('500,00 ₺').first);
      expect(amount.dy, greaterThan(title.dy), reason: 'tutar alt satırda');
    });
  });

  group('klavye', () {
    testWidgets('klavye açıkken (320x640 x2,0) Ek Borç formu taşmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _open(t, auth, width: 320, height: 640, scale: 2.0);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await _enter(t, 'finance_charge_name', 'Boya');
      await _preview(t);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
  group('W4 / W11: duyuru ve teknik metin', () {
    testWidgets('PREVIEW_STALE sonrası yenilenen önizleme tutarlarla birlikte DUYURULUR (okunuşla)', (t) async {
      final announced = captureAnnouncements(t);
      final auth = FinanceFakeAuth.seeded()..staleOnFirstPost = true;
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      await settleFor(t);
      expect(
        announced.any((m) => m.startsWith('Veriler değişti, önizleme yenilendi.') && m.contains('iki bin lira (4 daire)')),
        isTrue,
        reason: announced.toString(),
      );
      expect(announced.any((m) => m.contains('₺')), isFalse, reason: 'duyuruda rakam yığını yok');
    });

    testWidgets('önizleme 502 (metinsiz): teknik metin yok, Türkçe yedek metin var', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..previewError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      expect(find.text('Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('502'), findsNothing);
    });

    testWidgets('onay 502 (metinsiz): Borçlandırma yedek metni + sonuç belirsiz ipucu', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..postError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _open(t, auth, definition: _def(auth, 1));
      await _preview(t);
      await _confirm(t);
      expect(find.textContaining('Borçlandırma yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      expect(find.textContaining('502'), findsNothing);
    });
  });
}
