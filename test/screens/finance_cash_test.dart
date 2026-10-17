// Platform Faz 4b, Ö4: "Kasa" sekmesi ve hesap pencereleri (hesap ekle / düzenle, aktarım, düzeltme, mutabakat, toplu
// eşleme, hareketler, aktarım geçmişi) ile tahsilat penceresindeki hesap seçimi.
//
// Taşma matrisi x açık-koyu; yükleniyor / hata / boş / dolu; kurul salt okur; hata asla "hesap yok / bakiye 0"
// demez; çift dokunuş; işlem anahtarı (aynı veri = aynı anahtar); bayat önizleme / mutabakat; ekran okuyucu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_cash_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

FinanceFakeAuth _auth({bool seed = true}) {
  final auth = FinanceFakeAuth.seeded();
  if (seed) {
    auth.f4.accounts
      ..add(f4AccountJson(1, 'Nakit Kasa', balance: 250050, opening: 100000))
      ..add(f4AccountJson(2, 'Ziraat Bankası', kind: 'bank', balance: 1200000, opening: 1000000));
  }
  return auth;
}

int _changed = 0;

Future<GlobalKey<FinanceCashTabState>> _pumpTab(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  double width = 400,
  double height = 2000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<FinanceCashTabState>();
  _changed = 0;
  await pumpList(
    t,
    FinanceCashTab(key: key, scope: _scope(auth, canWrite: canWrite), onDataChanged: () => _changed++, now: () => _now),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

void main() {
  group('Kasa sekmesi: taşma matrisi', () {
    f4Matrix('dolu: toplam, eşlenmemiş uyarısı, eksi bakiye uyarısı, kartlar, düğmeler', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.accounts.add(f4AccountJson(3, 'Eski Hesap', active: false, balance: -5000));
      auth.f4.unassignedCount = 3;
      auth.f4.unassignedTotal = 150000;
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(CashAccountCard), findsNWidgets(3));
      expect(find.byKey(const ValueKey<String>('finance_cash_total')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_unassigned')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_negative')), findsOneWidget);
      expect(find.text('Pasif hesaplar'), findsOneWidget);
      for (final key in const [
        'finance_cash_add',
        'finance_cash_transfer',
        'finance_cash_transfers',
        'finance_cash_assign',
        'cash_open_1',
        'cash_adjust_1',
        'cash_reconcile_1',
        'cash_edit_1',
      ]) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    f4Matrix('yükleniyor: iskelet; "hesap yok" yazılmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.accountsGate = Completer<void>();
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_empty')), findsNothing);
      expect(find.byType(CashAccountCard), findsNothing);
      auth.f4.accountsGate!.complete();
      await settleFor(t);
    });

    f4Matrix('hata: InlineNotice + Tekrar Dene; tutar / "hesap yok" yok', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.accountsError = ApiException('x', statusCode: 500);
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_empty')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_cash_total')), findsNothing);
    });

    f4Matrix('boş: açıklayıcı durum ve Hesap Ekle', (t, w, h, s, dark) async {
      final auth = _auth(seed: false);
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_cash_empty')), findsOneWidget);
      expect(find.text('Henüz kasa ya da banka hesabı yok.'), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_cash_add')));
    });

    f4Matrix('kurul: salt okur (yazma düğmesi yok), hareket ve geçmiş açılabilir', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.unassignedCount = 1;
      auth.f4.unassignedTotal = 1000;
      await _pumpTab(t, auth, canWrite: false, width: w, height: h, scale: s, dark: dark);
      for (final key in const [
        'finance_cash_add',
        'finance_cash_transfer',
        'finance_cash_assign',
        'cash_adjust_1',
        'cash_reconcile_1',
        'cash_edit_1',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
      await scrollTo(t, find.byKey(const ValueKey<String>('cash_open_1')));
      expect(find.byKey(const ValueKey<String>('cash_open_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_transfers')), findsOneWidget);
    });
  });

  group('Kasa sekmesi: yükleme ve yenileme', () {
    testWidgets('tutarlar sunucudan; toplam kuruştan biçimlenir', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      expect(find.text('14.500,50 ₺'), findsOneWidget, reason: 'toplam 2.500,50 + 12.000,00');
      expect(find.text('2.500,50 ₺'), findsOneWidget);
      expect(find.text('12.000,00 ₺'), findsOneWidget);
      expect(find.text('2 hesap'), findsOneWidget);
    });

    testWidgets('yenileme başarısız olursa ESKİ tutarlar gösterilmez', (t) async {
      final auth = _auth();
      final key = await _pumpTab(t, auth);
      expect(find.byType(CashAccountCard), findsNWidgets(2));
      auth.f4.accountsError = ApiException('x', statusCode: 500);
      unawaited(key.currentState!.reload());
      await settleFor(t);
      expect(find.byType(CashAccountCard), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      auth.f4.accountsError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(CashAccountCard), findsNWidgets(2));
    });

    testWidgets('eski/yavaş yanıt yenisini ezmez', (t) async {
      final auth = _auth();
      final key = await _pumpTab(t, auth);
      final slow = Completer<void>();
      auth.f4.accountsGate = slow;
      unawaited(key.currentState!.reload()); // yavaş: eski veriyle (2 hesap) bekler
      await t.pump();
      auth.f4.accountsGate = null;
      auth.f4.accounts.add(f4AccountJson(9, 'Yeni Hesap', balance: 100));
      unawaited(key.currentState!.reload()); // hızlı: 3 hesap
      await settleFor(t);
      expect(find.byType(CashAccountCard), findsNWidgets(3));
      slow.complete();
      await settleFor(t);
      expect(find.byType(CashAccountCard), findsNWidgets(3), reason: 'eski yanıt (2 hesap) yenisini ezmedi');
    });

    testWidgets('ekran okuyucu: hesap kartı tutarı okunuşla (bin iki yüz ... lira) tek etiketle okur', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _pumpTab(t, auth);
      expect(
        find.bySemanticsLabel(RegExp('Kasa: Nakit Kasa.*iki bin beş yüz lira elli kuruş')),
        findsOneWidget,
        reason: 'ad + durum + bakiye (okunuşla) TEK birleşik etiket',
      );
      handle.dispose();
    });
  });

  group('Hesap ekle / düzenle', () {
    testWidgets('boş gönderim doğrulanır; ad ve açılış tarihi zorunlu', (t) async {
      final auth = _auth(seed: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Tap(t, 'finance_account_submit');
      expect(find.text('Hesap adını girin.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(auth.f4.callCount('createAccount'), 0);
    });

    testWidgets('banka hesabı eklenir: açılış kuruşa çevrilir, anahtar gider, liste yenilenir, bildirim', (t) async {
      final auth = _auth(seed: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Enter(t, 'finance_account_name', '  Ziraat Bankası ');
      await f4Tap(t, 'finance_account_kind_bank');
      await f4Enter(t, 'finance_account_opening', '1.250,50');
      await f4Enter(t, 'finance_account_note', 'Aidat hesabı');
      await f4Tap(t, 'finance_account_submit');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'createAccount');
      expect(write['name'], 'Ziraat Bankası');
      expect(write['kind'], 'bank');
      expect(write['opening_balance_minor'], 125050);
      expect(write['note'], 'Aidat hesabı');
      expect((write['key'] as String).length, lessThanOrEqualTo(64));
      expect(find.text('Hesap eklendi: Ziraat Bankası.'), findsOneWidget);
      expect(find.byType(CashAccountCard), findsOneWidget);
      expect(_changed, 1, reason: 'üst ekran bilgilendirildi');
    });

    testWidgets('açılış boşsa 0 gider; gelecek tarih reddedilir', (t) async {
      final auth = _auth(seed: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Enter(t, 'finance_account_name', 'Kasa');
      await f4Enter(t, 'finance_account_opening_date_group', '01.01.2099');
      await f4Tap(t, 'finance_account_submit');
      expect(find.text('Açılış tarihi bugünden ileri olamaz.'), findsOneWidget);
      expect(auth.f4.callCount('createAccount'), 0);
    });

    testWidgets('ACCOUNT_NAME_TAKEN: Türkçe mesaj, pencere açık kalır', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Enter(t, 'finance_account_name', 'nakit kasa');
      await f4Tap(t, 'finance_account_submit');
      expect(find.text('Bu adla başka bir hesap var. Farklı bir ad seçin.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_account_submit')), findsOneWidget);
    });

    testWidgets('belirsiz sonuçtan sonra AYNI veriyle yeniden deneme AYNI anahtarı kullanır (çift hesap yok)', (t) async {
      final auth = _auth(seed: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Enter(t, 'finance_account_name', 'Kasa');
      auth.f4.accountWriteError = ApiException('x', statusCode: 502);
      await f4Tap(t, 'finance_account_submit');
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      auth.f4.accountWriteError = null;
      await f4Tap(t, 'finance_account_submit');
      await settleFor(t);
      final keys = auth.f4.writes.where((w) => w['op'] == 'createAccount').map((w) => w['key']).toList();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1]);
      expect(auth.f4.accounts, hasLength(1));
    });

    testWidgets('çift dokunuş: gönderim sürerken ikinci istek yok', (t) async {
      final auth = _auth(seed: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Enter(t, 'finance_account_name', 'Kasa');
      auth.f4.accountWriteGate = Completer<void>();
      final submit = find.byKey(const ValueKey<String>('finance_account_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await t.pump();
      await t.tap(submit, warnIfMissed: false);
      await t.pump();
      expect(auth.f4.callCount('createAccount'), 1);
      auth.f4.accountWriteGate!.complete();
      await settleFor(t);
      expect(auth.f4.callCount('createAccount'), 1);
    });

    testWidgets('R13 P2-12: açılış bakiyesi EKSİ girilebilir (kredili hesap): tutar işareti sunucuya gider', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth(seed: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      f4ExpectSpokenMoney(t); // R14: açılış alanı ipucunda "0,00 ₺" yığını yok
      await f4Enter(t, 'finance_account_name', 'Kredili Hesap');
      await f4Enter(t, 'finance_account_opening', '1.250,50');
      await f4Tap(t, 'finance_account_opening_negative');
      await f4Tap(t, 'finance_account_submit');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'createAccount');
      expect(write['opening_balance_minor'], -125050);
      handle.dispose();
    });

    testWidgets('pasifleştirme uyarısındaki bakiye ekran okuyucuda lira olarak okunur (R13 P2-12)', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_edit_1');
      await f4Tap(t, 'finance_account_active');
      expect(find.bySemanticsLabel(RegExp('Bu hesabın bakiyesi iki bin beş yüz lira elli kuruş')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('düzenleme: değişiklik yoksa uyarı; pasifleştirmede bakiye uyarısı; yalnız değişen alanlar gider', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_edit_1');
      await f4Tap(t, 'finance_account_submit');
      expect(find.text('Değişiklik yapmadınız.'), findsOneWidget);
      await f4Tap(t, 'finance_account_active');
      expect(find.byKey(const ValueKey<String>('finance_account_deactivate_warning')), findsOneWidget);
      expect(find.textContaining('2.500,50 ₺'), findsWidgets);
      await f4Tap(t, 'finance_account_submit');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'updateAccount');
      expect(write['is_active'], false);
      expect(write.containsKey('name'), isFalse);
      expect(find.text('Hesap pasifleştirildi: Nakit Kasa.'), findsOneWidget);
    });
  });

  group('Aktarım', () {
    testWidgets('tek aktif hesapla Aktarım Yap pasif; ipucu görünür', (t) async {
      final auth = _auth(seed: false);
      auth.f4.accounts.add(f4AccountJson(1, 'Kasa'));
      await _pumpTab(t, auth);
      final button = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_cash_transfer')));
      expect(button.onPressed, isNull);
      expect(find.byKey(const ValueKey<String>('finance_cash_transfer_hint')), findsOneWidget);
    });

    Future<void> pickAccount(WidgetTester t, String key, String name) async {
      await f4Tap(t, key);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text(name).last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
    }

    testWidgets('aynı hesap seçilemez; boş alanlar doğrulanır', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfer');
      await f4Tap(t, 'finance_transfer_submit');
      expect(find.text('Çıkış hesabı seçin.'), findsOneWidget);
      expect(find.text('Giriş hesabı seçin.'), findsOneWidget);
      await pickAccount(t, 'finance_transfer_from', 'Nakit Kasa');
      await pickAccount(t, 'finance_transfer_to', 'Nakit Kasa');
      expect(find.text('Çıkış ve giriş hesabı aynı olamaz.'), findsOneWidget);
      await f4Enter(t, 'finance_transfer_amount', '100');
      await f4Tap(t, 'finance_transfer_submit');
      expect(auth.f4.callCount('createTransfer'), 0);
    });

    testWidgets('aktarım: iki hesap bakiyesi güncellenir; kuruşa kesin; mesajda yön; bakiye aşımı uyarısı', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfer');
      await pickAccount(t, 'finance_transfer_from', 'Nakit Kasa');
      await pickAccount(t, 'finance_transfer_to', 'Ziraat Bankası');
      expect(find.text('Bakiye: 2.500,50 ₺'), findsOneWidget, reason: 'çıkış hesabı bakiyesi');
      await f4Enter(t, 'finance_transfer_amount', '3.000,00');
      expect(find.byKey(const ValueKey<String>('finance_transfer_exceeds')), findsOneWidget, reason: 'bakiyeyi aşıyor');
      await f4Enter(t, 'finance_transfer_amount', '1.000,25');
      expect(find.byKey(const ValueKey<String>('finance_transfer_exceeds')), findsNothing);
      await f4Enter(t, 'finance_transfer_description', 'Bankaya yatırma');
      await f4Tap(t, 'finance_transfer_submit');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'createTransfer');
      expect(write['from'], 1);
      expect(write['to'], 2);
      expect(write['amount_minor'], 100025);
      expect(write['date'], '2026-10-16');
      expect(find.text('Aktarım yapıldı: 1.000,25 ₺ (Nakit Kasa → Ziraat Bankası).'), findsOneWidget);
      expect(find.text('1.500,25 ₺'), findsOneWidget, reason: 'çıkış hesabı yeni bakiye (2.500,50 - 1.000,25)');
      expect(find.text('13.000,25 ₺'), findsOneWidget, reason: 'giriş hesabı yeni bakiye');
    });

    testWidgets('PERIOD_CLOSED Türkçe mesajla pencerede kalır', (t) async {
      final auth = _auth();
      auth.f4.closedMonths.add('2026-10');
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfer');
      await pickAccount(t, 'finance_transfer_from', 'Nakit Kasa');
      await pickAccount(t, 'finance_transfer_to', 'Ziraat Bankası');
      await f4Enter(t, 'finance_transfer_amount', '10');
      await f4Tap(t, 'finance_transfer_submit');
      expect(find.textContaining('Bu dönem kapatılmış'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_transfer_submit')), findsOneWidget);
    });

    testWidgets('geçmiş: aktarım iptali nedenle yapılır (ters hareketler), iptal edilen "İptal edildi" olur', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfer');
      await pickAccount(t, 'finance_transfer_from', 'Nakit Kasa');
      await pickAccount(t, 'finance_transfer_to', 'Ziraat Bankası');
      await f4Enter(t, 'finance_transfer_amount', '100');
      await f4Tap(t, 'finance_transfer_submit');
      await settleFor(t);
      await f4Tap(t, 'finance_cash_transfers');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('transfer_700')), findsOneWidget);
      await f4Tap(t, 'transfer_void_700');
      await f4Tap(t, 'finance_reason_confirm');
      expect(find.text('Neden girin.'), findsOneWidget);
      await f4Enter(t, 'finance_reason_text', 'Yanlış hesap');
      await f4Tap(t, 'finance_reason_confirm');
      await settleFor(t);
      expect(auth.f4.callCount('voidTransfer'), 1);
      expect(find.text('İptal edildi'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('transfer_void_700')), findsNothing);
    });

    testWidgets('R13 P2-4: sonucu belirsiz aktarım -> pencere kapatılıp AYNI verilerle yeniden açılınca AYNI işlem anahtarı (çift aktarım yok)', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      auth.f4.accountWriteError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      Future<void> fill() async {
        await f4Tap(t, 'finance_cash_transfer');
        await pickAccount(t, 'finance_transfer_from', 'Nakit Kasa');
        await pickAccount(t, 'finance_transfer_to', 'Ziraat Bankası');
        await f4Enter(t, 'finance_transfer_amount', '100');
        await f4Tap(t, 'finance_transfer_submit');
      }
      await fill();
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      await f4TapInDialog(t, 'Vazgeç');
      auth.f4.accountWriteError = null;
      await fill();
      await settleFor(t);
      final keys = auth.f4.writes.where((w) => w['op'] == 'createTransfer').map((w) => w['key']).toList();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1], reason: 'oturum boyunca aynı imza = aynı anahtar');
      expect(auth.f4.transfers, hasLength(1));
    });

    testWidgets('R13 P2-9: aktarım iptali sonucu belirsiz kalıp pencere kapanınca geçmiş listesi TAZELENİR (iptal yazılmış olabilir)', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfer');
      await pickAccount(t, 'finance_transfer_from', 'Nakit Kasa');
      await pickAccount(t, 'finance_transfer_to', 'Ziraat Bankası');
      await f4Enter(t, 'finance_transfer_amount', '100');
      await f4Tap(t, 'finance_transfer_submit');
      await settleFor(t);
      await f4Tap(t, 'finance_cash_transfers');
      await settleFor(t);
      final before = auth.f4.callCount('listTransfers');
      await f4Tap(t, 'transfer_void_700');
      await f4Enter(t, 'finance_reason_text', 'Yanlış hesap');
      auth.f4.accountWriteError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await f4Tap(t, 'finance_reason_confirm');
      await settleFor(t);
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      auth.f4.accountWriteError = null;
      await f4Tap(t, 'finance_reason_cancel');
      await settleFor(t);
      expect(auth.f4.callCount('listTransfers'), greaterThan(before), reason: 'liste yeniden okundu');
    });

    testWidgets('geçmiş: hata asla "aktarım yok" demez', (t) async {
      final auth = _auth();
      auth.f4.transfersError = ApiException('x', statusCode: 500);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfers');
      await settleFor(t);
      expect(find.text('Henüz hesaplar arası aktarım yapılmamış.'), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });
  });

  group('Düzeltme hareketi', () {
    testWidgets('yön ve neden zorunlu; "Diğer"de not zorunlu; boş tutar reddedilir', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_adjust_1');
      await f4Tap(t, 'finance_adjust_submit');
      expect(find.text('Düzeltmenin yönünü seçin (giriş ya da çıkış).'), findsOneWidget);
      expect(find.text('Düzeltme nedenini seçin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      await f4Tap(t, 'finance_adjust_out');
      await f4Tap(t, 'finance_adjust_reason_other');
      await f4Enter(t, 'finance_adjust_amount', '15');
      await f4Tap(t, 'finance_adjust_submit');
      expect(find.text('"Diğer" nedeninde açıklama notu zorunludur.'), findsOneWidget);
      expect(auth.f4.callCount('adjustAccount'), 0);
    });

    testWidgets('çıkış yönü EKSİ tutar yazar; yeni bakiye önizlemesi; sonuç bildirimi', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_adjust_1');
      await f4Tap(t, 'finance_adjust_out');
      await f4Enter(t, 'finance_adjust_amount', '15,50');
      expect(find.text('Bakiye: 2.500,50 ₺ → 2.485,00 ₺'), findsOneWidget);
      await f4Tap(t, 'finance_adjust_reason_bank_fee');
      await f4Tap(t, 'finance_adjust_submit');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'adjustAccount');
      expect(write['amount_minor'], -1550);
      expect(write['reason'], 'bank_fee');
      expect(find.textContaining('Düzeltme yazıldı: -15,50 ₺ (Banka masrafı)'), findsOneWidget);
      expect(find.text('2.485,00 ₺'), findsOneWidget);
    });

    testWidgets('giriş yönü ARTI yazar; pasif hesapta düğme kapalı', (t) async {
      final auth = _auth();
      auth.f4.accounts.add(f4AccountJson(3, 'Pasif', active: false));
      await _pumpTab(t, auth);
      final passive = t.widget<TextButton>(find.byKey(const ValueKey<String>('cash_adjust_3')));
      expect(passive.onPressed, isNull);
      await f4Tap(t, 'cash_adjust_2');
      await f4Tap(t, 'finance_adjust_in');
      await f4Enter(t, 'finance_adjust_amount', '5');
      await f4Tap(t, 'finance_adjust_reason_bank_interest');
      await f4Tap(t, 'finance_adjust_submit');
      await settleFor(t);
      expect(auth.f4.writes.firstWhere((w) => w['op'] == 'adjustAccount')['amount_minor'], 500);
    });
  });

  group('R15: işlem anahtarı AYNI gövde için yaşar (farklı neden / not = YENİ anahtar)', () {
    List<Object?> keysOf(FinanceFakeAuth auth, String op) => auth.f4.writes.where((w) => w['op'] == op).map((w) => w['key']).toList();

    Future<void> pickAccountR15(WidgetTester t, String key, String name) async {
      await f4Tap(t, key);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text(name).last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
    }

    testWidgets('düzeltme hareketi: aynı veri AYNI anahtar; not ya da neden değişince YENİ anahtar', (t) async {
      final auth = _auth();
      auth.f4.accountWriteError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_adjust_1');
      await f4Tap(t, 'finance_adjust_out');
      await f4Enter(t, 'finance_adjust_amount', '15');
      await f4Tap(t, 'finance_adjust_reason_bank_fee');
      await f4Tap(t, 'finance_adjust_submit');
      await f4Tap(t, 'finance_adjust_submit'); // aynı veri
      await f4Enter(t, 'finance_adjust_note', 'Şubat masrafı');
      await f4Tap(t, 'finance_adjust_submit'); // not değişti
      await f4Tap(t, 'finance_adjust_reason_bank_interest');
      await f4Tap(t, 'finance_adjust_submit'); // neden değişti
      final keys = keysOf(auth, 'adjustAccount');
      expect(keys, hasLength(4));
      expect(keys[1], keys[0], reason: 'aynı gövde: aynı anahtar');
      expect(keys[2], isNot(keys[0]), reason: 'not değişti: yeni anahtar');
      expect(keys[3], isNot(keys[2]), reason: 'neden değişti: yeni anahtar');
      expect(keys[3], isNot(keys[0]));
    });

    testWidgets('aktarım iptali: aynı neden AYNI anahtar; neden değişince YENİ anahtar', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_transfer');
      await pickAccountR15(t, 'finance_transfer_from', 'Nakit Kasa');
      await pickAccountR15(t, 'finance_transfer_to', 'Ziraat Bankası');
      await f4Enter(t, 'finance_transfer_amount', '100');
      await f4Tap(t, 'finance_transfer_submit');
      await settleFor(t);
      await f4Tap(t, 'finance_cash_transfers');
      await settleFor(t);
      await f4Tap(t, 'transfer_void_700');
      auth.f4.accountWriteError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await f4Enter(t, 'finance_reason_text', 'Yanlış hesap');
      await f4Tap(t, 'finance_reason_confirm');
      await f4Tap(t, 'finance_reason_confirm');
      await f4Enter(t, 'finance_reason_text', 'Yanlış tutar');
      await f4Tap(t, 'finance_reason_confirm');
      final keys = keysOf(auth, 'voidTransfer');
      expect(keys, hasLength(3));
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
    });
  });

  group('Mutabakat', () {
    testWidgets('hesaplanan bakiye taze okunur; fark canlı gösterilir; tutuyorsa "Fark yok"', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      expect(find.byKey(const ValueKey<String>('finance_reconcile_computed')), findsOneWidget);
      expect(find.text('2.500,50 ₺'), findsWidgets);
      await f4Enter(t, 'finance_reconcile_statement', '2.450,50');
      expect(find.text('Fark: -50,00 ₺ (ekstre sistemden az)'), findsOneWidget);
      await f4Enter(t, 'finance_reconcile_statement', '2.500,50');
      expect(find.text('Fark yok: bakiye ekstreyle tutuyor.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reconcile_adjust')), findsNothing, reason: 'fark yoksa düzeltme seçeneği yok');
    });

    testWidgets('fark düzeltilmeden kaydedilir: mesaj "düzeltilmedi", beklenen hesaplanan bakiye gider', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      await f4Enter(t, 'finance_reconcile_statement', '2.400,50');
      await f4Tap(t, 'finance_reconcile_submit');
      await settleFor(t);
      final call = auth.f4.reconcileCalls.single;
      expect(call['statement'], 240050);
      expect(call['expected'], 250050);
      expect(call['adjust'], isNull);
      expect(find.textContaining('düzeltilmedi; raporlarda uyarı olarak görünür'), findsOneWidget);
    });

    testWidgets('fark düzeltme hareketi olarak yazılır: neden zorunlu; hesap bakiyesi ekstreye eşitlenir', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      await f4Enter(t, 'finance_reconcile_statement', '2.400,50');
      await f4Tap(t, 'finance_reconcile_adjust');
      await f4Tap(t, 'finance_reconcile_submit');
      expect(find.text('Düzeltme nedenini seçin.'), findsOneWidget);
      await f4Tap(t, 'finance_reconcile_reason_cash_count');
      await f4Tap(t, 'finance_reconcile_submit');
      await settleFor(t);
      expect(auth.f4.reconcileCalls.single['adjust'], 'cash_count');
      expect(find.textContaining('düzeltme hareketiyle giderildi'), findsOneWidget);
      expect(find.text('2.400,50 ₺'), findsWidgets);
    });

    testWidgets('RECONCILIATION_STALE: yeni hesaplanan bakiye gösterilir, ESKİ farkla yazılmaz; yeniden onayda yeni anahtar', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      await f4Enter(t, 'finance_reconcile_statement', '2.500,50');
      auth.f4.reconcileStaleOnce = true;
      await f4Tap(t, 'finance_reconcile_submit');
      expect(find.byKey(const ValueKey<String>('finance_reconcile_stale')), findsOneWidget);
      expect(find.textContaining('Güncel hesaplanan bakiye 2.525,50 ₺'), findsOneWidget);
      expect(find.text('Fark: -25,00 ₺ (ekstre sistemden az)'), findsOneWidget, reason: 'fark yeni bakiyeyle yeniden hesaplandı');
      expect(auth.f4.accounts.first['last_reconciliation'], isNull, reason: 'eski farkla mutabakat yazılmadı');
      await f4Tap(t, 'finance_reconcile_submit');
      await settleFor(t);
      expect(auth.f4.reconcileCalls, hasLength(2));
      expect(auth.f4.reconcileCalls[1]['expected'], 252550);
      expect(auth.f4.reconcileCalls[0]['key'], isNot(auth.f4.reconcileCalls[1]['key']));
    });

    testWidgets('R15: STALE yanıtındaki computed_balance_minor önceki mutabakatın düzeltmesini içerir: güncel değerle fark 0, ikinci kez düzeltilmez', (t) async {
      final auth = _auth();
      auth.f4.reconcileStaleDeltaMinor = 10000; // önceki (eski tarihli) mutabakatın +100,00 ₺ düzeltmesi hesaplanan bakiyeye girdi
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      await f4Enter(t, 'finance_reconcile_statement', '2.600,50');
      expect(find.text('Fark: +100,00 ₺ (ekstre sistemden fazla)'), findsOneWidget);
      await f4Tap(t, 'finance_reconcile_adjust');
      await f4Tap(t, 'finance_reconcile_reason_cash_count');
      auth.f4.reconcileStaleOnce = true;
      await f4Tap(t, 'finance_reconcile_submit');
      expect(find.textContaining('Güncel hesaplanan bakiye 2.600,50 ₺'), findsOneWidget);
      expect(find.text('Fark yok: bakiye ekstreyle tutuyor.'), findsOneWidget, reason: 'güncel değerle fark sıfır');
      expect(find.byKey(const ValueKey<String>('finance_reconcile_adjust')), findsNothing, reason: 'düzeltilecek fark kalmadı');
      expect(auth.f4.movements.values.expand((l) => l).where((m) => m['kind'] == 'adjustment'), isEmpty, reason: 'eski farkla ikinci düzeltme yazılmadı');
      await f4Tap(t, 'finance_reconcile_submit');
      await settleFor(t);
      expect(auth.f4.reconcileCalls, hasLength(2));
      expect(auth.f4.reconcileCalls[1]['expected'], 260050);
      expect(auth.f4.reconcileCalls[1]['adjust'], isNull);
      expect(auth.f4.movements.values.expand((l) => l).where((m) => m['kind'] == 'adjustment'), isEmpty);
      expect(find.textContaining('bakiyesi ekstreyle tutuyor'), findsOneWidget);
    });

    testWidgets('R15: RECONCILIATION_ORDER: sunucu iletisi + "Yalnız kayıt olarak gir"; onaydan sonra düzeltmesiz, YENİ anahtarla yazılır', (t) async {
      final auth = _auth();
      auth.f4.reconcileOrderConflict = true;
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      await f4Enter(t, 'finance_reconcile_statement', '2.400,50');
      await f4Tap(t, 'finance_reconcile_adjust');
      await f4Tap(t, 'finance_reconcile_reason_cash_count');
      await f4Tap(t, 'finance_reconcile_submit');
      await settleFor(t);
      expect(find.textContaining('Daha yeni tarihli bir mutabakatın düzeltmesi var'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reconcile_record_only')), findsOneWidget);
      expect(find.textContaining('düzeltilmez ve raporlarda uyarı olarak görünür'), findsOneWidget);
      expect(auth.f4.reconcileCalls, hasLength(1));
      expect(auth.f4.reconcileCalls[0]['adjust'], 'cash_count');

      // Onay penceresi: farkın düzeltilmeyeceği açıkça söylenir; vazgeçilirse hiçbir şey gönderilmez.
      await f4Tap(t, 'finance_reconcile_record_only');
      expect(find.text('Fark düzeltilmeden kaydedilsin mi?'), findsOneWidget);
      expect(find.textContaining('DÜZELTİLMEYECEK'), findsOneWidget);
      await f4TapInDialog(t, 'Vazgeç');
      expect(auth.f4.reconcileCalls, hasLength(1));
      expect(find.byKey(const ValueKey<String>('finance_reconcile_record_only')), findsOneWidget);

      await f4Tap(t, 'finance_reconcile_record_only');
      await f4TapInDialog(t, 'Yalnız Kayıt Olarak Gir');
      await settleFor(t);
      expect(auth.f4.reconcileCalls, hasLength(2));
      expect(auth.f4.reconcileCalls[1]['adjust'], isNull, reason: 'aynı veri, düzeltme OLMADAN');
      expect(auth.f4.reconcileCalls[1]['statement'], 240050);
      expect(auth.f4.reconcileCalls[1]['key'], isNot(auth.f4.reconcileCalls[0]['key']), reason: 'yeni işlem anahtarı');
      expect(find.textContaining('düzeltilmedi; raporlarda uyarı olarak görünür'), findsOneWidget);
      expect(auth.f4.accounts.first['balance_minor'], 250050, reason: 'bakiye değişmedi (düzeltme yazılmadı)');
    });

    testWidgets('bakiye okunamazsa mutabakat yapılamaz: hata + Tekrar Dene, Kaydet pasif', (t) async {
      final auth = _auth();
      final key = await _pumpTab(t, auth);
      auth.f4.accountsError = ApiException('x', statusCode: 500);
      await f4Tap(t, 'cash_reconcile_1');
      expect(key.currentState, isNotNull);
      expect(find.byKey(const ValueKey<String>('finance_reconcile_load_error')), findsOneWidget);
      final submit = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_reconcile_submit')));
      expect(submit.onPressed, isNull);
    });

    testWidgets('eksi ekstre bakiyesi anahtarı işareti çevirir', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_reconcile_1');
      await f4Enter(t, 'finance_reconcile_statement', '100');
      await f4Tap(t, 'finance_reconcile_negative');
      await f4Tap(t, 'finance_reconcile_submit');
      await settleFor(t);
      expect(auth.f4.reconcileCalls.single['statement'], -10000);
    });
  });

  group('R14: kaydedilmemiş veri koruması (Vazgeç / geri tuşu)', () {
    Future<void> pickAccount(WidgetTester t, String key, String name) async {
      await f4Tap(t, key);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text(name).last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
    }

    testWidgets('aktarım', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_transfer_submit',
        open: () async {
          await f4Tap(t, 'finance_cash_transfer');
          await settleFor(t);
        },
        edit: () async => pickAccount(t, 'finance_transfer_from', 'Nakit Kasa'),
      );
      expect(auth.f4.callCount('createTransfer'), 0);
    });

    testWidgets('düzeltme hareketi', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_adjust_submit',
        open: () async {
          await f4Tap(t, 'cash_adjust_1');
          await settleFor(t);
        },
        edit: () async => f4Tap(t, 'finance_adjust_out'),
      );
    });

    testWidgets('mutabakat', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_reconcile_submit',
        open: () async {
          await f4Tap(t, 'cash_reconcile_1');
          await settleFor(t);
        },
        edit: () async => f4Enter(t, 'finance_reconcile_statement', '100'),
      );
    });

    testWidgets('hesap ekle', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_account_submit',
        open: () async {
          await f4Tap(t, 'finance_cash_add');
          await settleFor(t);
        },
        edit: () async => f4Enter(t, 'finance_account_name', 'Yeni Kasa'),
      );
    });

    testWidgets('tahsilat', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_payment_submit',
        open: () async {
          await openDialogAt(
            t,
            (context) => FinancePaymentDialog.show(context, scope: _scope(auth), apartmentId: 301, apartmentLabel: 'A Blok - 5', now: () => _now),
            width: 400,
            height: 1100,
            scale: 1.0,
            dark: false,
          );
          await settleFor(t);
        },
        edit: () async => f4Enter(t, 'finance_payment_amount', '100'),
      );
    });

    testWidgets('gönderim sürerken geri tuşu pencereyi KAPATMAZ ve onay da sormaz', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_add');
      await f4Enter(t, 'finance_account_name', 'Yeni Kasa');
      auth.f4.accountWriteGate = Completer<void>();
      await f4Tap(t, 'finance_account_submit');
      await t.pump();
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 450));
      expect(find.text('Değişiklikler silinsin mi?'), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_account_submit')), findsOneWidget);
      auth.f4.accountWriteGate!.complete();
      await settleFor(t);
    });
  });

  group('Toplu eşleme', () {
    testWidgets('önizle -> onayla: adet ve toplam gösterilir, kayıt toplam + özetle gider, uyarı kalkar', (t) async {
      final auth = _auth();
      auth.f4.unassignedCount = 2;
      auth.f4.unassignedTotal = 150000;
      auth.f4.assignPreviewResult = const AssignPreview(
        count: 2,
        totalMinor: 150000,
        previewHash: 'h1',
        byMethod: [AssignMethodRow(method: 'cash', count: 1, totalMinor: 100000), AssignMethodRow(method: 'transfer', count: 1, totalMinor: 50000)],
      );
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_assign');
      await f4Tap(t, 'finance_assign_preview');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_assign_total')), findsOneWidget);
      expect(find.text('1.500,00 ₺'), findsWidgets);
      expect(find.text('Nakit: 1 tahsilat, 1.000,00 ₺'), findsOneWidget);
      await f4Tap(t, 'finance_assign_confirm');
      await settleFor(t);
      final commit = auth.f4.writes.firstWhere((w) => w['op'] == 'commitAssignPayments');
      expect(commit['count'], 2);
      expect(commit['total'], 150000);
      expect(commit['hash'], 'h1');
      expect(find.textContaining('2 tahsilat hesaplara eşlendi (toplam 1.500,00 ₺)'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_unassigned')), findsNothing);
    });

    testWidgets('PREVIEW_STALE: önizleme otomatik yenilenir, eski + yeni toplam yazılır, YENİDEN onay gerekir', (t) async {
      final auth = _auth();
      auth.f4.unassignedCount = 2;
      auth.f4.unassignedTotal = 150000;
      auth.f4.assignPreviewResult = const AssignPreview(count: 2, totalMinor: 150000, previewHash: 'h1');
      auth.f4.assignStaleOnce = true;
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_assign');
      await f4Tap(t, 'finance_assign_preview');
      await settleFor(t);
      await f4Tap(t, 'finance_assign_confirm');
      await settleFor(t);
      expect(auth.f4.callCount('commitAssignPayments'), 1, reason: 'bayat önizlemeyle ikinci yazma denenmedi');
      expect(find.byKey(const ValueKey<String>('finance_assign_notice')), findsOneWidget);
      expect(find.textContaining('Yeni toplam 1.510,00 ₺ (3 tahsilat); önceki toplam 1.500,00 ₺ (2 tahsilat) idi'), findsOneWidget);
      expect(auth.f4.assignPreviewResult.previewHash, 'h1x');
      // Yeni önizlemeyle onay: yeni özet gider.
      await f4Tap(t, 'finance_assign_confirm');
      await settleFor(t);
      final hashes = auth.f4.assignCommits.map((c) => c['hash']).toList();
      expect(hashes, <Object?>['h1', 'h1x']);
    });

    testWidgets('eşlenmeyecek tahsilatlar nedenleriyle bildirilir (kapalı ay / açılıştan önce / hesap seçilmemiş)', (t) async {
      final auth = _auth();
      auth.f4.unassignedCount = 6;
      auth.f4.unassignedTotal = 600000;
      auth.f4.assignPreviewResult = const AssignPreview(
        count: 2,
        totalMinor: 150000,
        previewHash: 'h1',
        skippedClosedPeriod: 3,
        skippedBeforeOpening: 1,
        skippedNoAccount: 4,
      );
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_assign');
      await f4Tap(t, 'finance_assign_preview');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_assign_skipped')), findsOneWidget);
      expect(find.textContaining('3 tahsilat kapalı ayda'), findsOneWidget);
      expect(find.textContaining('1 tahsilat seçilen hesabın açılış tarihinden önce'), findsOneWidget);
      expect(find.textContaining('4 tahsilatın yöntemi için hesap seçilmedi'), findsOneWidget);
    });

    test('AssignPreview.fromJson sunucunun skipped alanını okur', () {
      final p = AssignPreview.fromJson(<String, dynamic>{
        'count': 2,
        'total_minor': 100,
        'preview_hash': 'x',
        'skipped': <String, dynamic>{'before_opening': 1, 'closed_period': 2, 'no_account': 3},
      });
      expect((p.skippedBeforeOpening, p.skippedClosedPeriod, p.skippedNoAccount, p.skippedTotal), (1, 2, 3, 6));
      expect(AssignPreview.fromJson(<String, dynamic>{'count': 0, 'total_minor': 0}).skippedTotal, 0);
    });

    testWidgets('eşlenecek tahsilat yoksa onay kapalı', (t) async {
      final auth = _auth();
      auth.f4.unassignedCount = 1;
      auth.f4.unassignedTotal = 100;
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_assign');
      await f4Tap(t, 'finance_assign_preview');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_assign_empty')), findsOneWidget);
      final confirm = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_assign_confirm')));
      expect(confirm.onPressed, isNull);
    });

    testWidgets('R14: pasif "Onayla ve Eşle" düğmesinin nedeni ekran okuyucuya söylenir (hint)', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      auth.f4.unassignedCount = 1;
      auth.f4.unassignedTotal = 100;
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_assign');
      await f4Tap(t, 'finance_assign_preview');
      await settleFor(t);
      expect(t.getSemantics(find.byKey(const ValueKey<String>('finance_assign_confirm'))).hint, contains('Eşlenecek tahsilat yok.'));
      handle.dispose();
    });

    testWidgets('önizleme hatası pencerede kalır', (t) async {
      final auth = _auth();
      auth.f4.unassignedCount = 1;
      auth.f4.unassignedTotal = 100;
      auth.f4.assignPreviewError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_cash_assign');
      await f4Tap(t, 'finance_assign_preview');
      await settleFor(t);
      expect(find.textContaining('Önizleme alınamadı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_assign_preview')), findsOneWidget);
    });
  });

  group('Hareketler', () {
    f4Matrix('hareket penceresi: bakiye, ters hareket, eksi bakiye uyarısı taşmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.accounts[0]['balance_minor'] = -2500;
      auth.f4.movements[1] = [
        <String, dynamic>{'id': 1, 'kind': 'opening', 'amount_minor': 100000, 'movement_date': '2026-01-01'},
        <String, dynamic>{'id': 2, 'kind': 'expense', 'amount_minor': -102500, 'movement_date': '2026-10-02', 'label': 'Asansör bakım faturası', 'reversed_by_movement_id': 3},
        <String, dynamic>{'id': 3, 'kind': 'reversal', 'amount_minor': 102500, 'movement_date': '2026-10-03', 'reverses_movement_id': 2},
        <String, dynamic>{'id': 4, 'kind': 'adjustment', 'amount_minor': -2500, 'movement_date': '2026-10-04', 'reason_code': 'bank_fee', 'note': 'Havale masrafı'},
      ];
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4Tap(t, 'cash_open_1');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_movements_header')), findsOneWidget);
      expect(find.text('-25,00 ₺'), findsWidgets);
      expect(find.byType(MovementTile), findsNWidgets(4));
      expect(find.textContaining('Bakiye eksiye düşmüş'), findsOneWidget);
      expect(find.text('Banka masrafı'), findsOneWidget);
    });

    testWidgets('hata: "hareket yok" yazılmaz, bakiye başlığı gösterilmez', (t) async {
      final auth = _auth();
      auth.f4.movementsError = ApiException('x', statusCode: 500);
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_open_1');
      await settleFor(t);
      expect(find.text('Bu hesapta henüz hareket yok.'), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_movements_header')), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });

    testWidgets('boş hesap: "Bu hesapta henüz hareket yok."; sayfalama imleçle', (t) async {
      final auth = _auth();
      auth.f4.movementPageSize = 2;
      auth.f4.movements[1] = [
        for (var i = 1; i <= 3; i++)
          <String, dynamic>{'id': i, 'kind': 'collection', 'amount_minor': 100 * i, 'movement_date': '2026-10-0$i'},
      ];
      await _pumpTab(t, auth);
      await f4Tap(t, 'cash_open_2');
      await settleFor(t);
      expect(find.text('Bu hesapta henüz hareket yok.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('finance_movements_close')));
      await settleFor(t);
      await f4Tap(t, 'cash_open_1');
      await settleFor(t);
      expect(find.byType(MovementTile), findsNWidgets(2));
      await f4TapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(MovementTile), findsNWidgets(3));
    });
  });

  group('Tahsilat penceresi: hesap seçimi', () {
    Future<void> openPayment(WidgetTester t, FinanceFakeAuth auth, {int? apartmentId = 301, double width = 400, double height = 1100, double scale = 1.0, bool dark = false}) async {
      await openDialogAt(
        t,
        (context) => FinancePaymentDialog.show(
          context,
          scope: _scope(auth),
          apartmentId: apartmentId,
          apartmentLabel: 'A Blok - 5',
          now: () => _now,
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);
    }

    f4Matrix('hesap seçicili tahsilat penceresi taşmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.accounts.add(f4AccountJson(3, 'Çok Uzun Adlı Şube Kasası ve Banka Hesabı', kind: 'bank'));
      await openPayment(t, auth, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.text('Hesap').first);
      expect(find.byKey(const ValueKey<String>('finance_payment_account_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_account_3')), findsOneWidget);
    });

    testWidgets('hesap yoksa seçici çizilmez ve eski (4a) yol kullanılır', (t) async {
      final auth = _auth(seed: false);
      await openPayment(t, auth);
      expect(find.text('Hesap'), findsNothing);
      await f4Enter(t, 'finance_payment_amount', '100');
      await f4Tap(t, 'finance_method_cash');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.paymentCalls, hasLength(1), reason: '4a yolu');
      expect(auth.f4.paymentCalls, isEmpty);
    });

    testWidgets('iki hesap: seçilmeden gönderilemez; yönteme göre ÖNERİ (nakit -> kasa, havale -> banka)', (t) async {
      final auth = _auth();
      await openPayment(t, auth);
      await f4Enter(t, 'finance_payment_amount', '100');
      await f4Tap(t, 'finance_payment_submit');
      expect(find.text('Tahsilatın gireceği hesabı seçin.'), findsOneWidget);
      expect(auth.f4.paymentCalls, isEmpty);
      await f4Tap(t, 'finance_method_cash');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_1'))).selected, isTrue);
      await f4Tap(t, 'finance_method_transfer');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_2'))).selected, isTrue);
      // Kullanıcı kendisi seçtiyse yöntem değişimi seçimi bozmaz.
      await f4Tap(t, 'finance_payment_account_1');
      await f4Tap(t, 'finance_method_cheque');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_1'))).selected, isTrue);
    });

    testWidgets('hesap seçimli tahsilat: account_id gider, makbuz sonuca eklenir, hesap bakiyesi artar', (t) async {
      final auth = _auth();
      FinancePaymentOutcome? outcome;
      await openDialogAt(
        t,
        (context) async {
          outcome = await FinancePaymentDialog.show(context, scope: _scope(auth), apartmentId: 301, apartmentLabel: 'A Blok - 5', now: () => _now);
        },
        width: 400,
        height: 1100,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await f4Enter(t, 'finance_payment_amount', '1.250,50');
      await f4Tap(t, 'finance_method_transfer');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      final call = auth.f4.paymentCalls.single;
      expect(call['account_id'], 2);
      expect(call['amount_minor'], 125050);
      expect(call['method'], 'transfer');
      expect(outcome!.result.receipt!.number, 'MK-2026-000077');
      expect(auth.f4.accounts[1]['balance_minor'], 1200000 + 125050);
    });

    testWidgets('tek aktif hesap ön seçilir; pasif hesap listelenmez', (t) async {
      final auth = _auth(seed: false);
      auth.f4.accounts
        ..add(f4AccountJson(1, 'Kasa'))
        ..add(f4AccountJson(2, 'Eski', active: false));
      await openPayment(t, auth);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_1'))).selected, isTrue);
      expect(find.byKey(const ValueKey<String>('finance_payment_account_2')), findsNothing);
    });

    testWidgets('hesap listesi okunamazsa uyarı + Tekrar Dene; gönderim sunucu ACCOUNT_REQUIRED derse hesaplar yeniden okunur', (t) async {
      final auth = _auth();
      auth.f4.accountsError = ApiException('x', statusCode: 500);
      await openPayment(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_payment_accounts_error')), findsOneWidget);
      auth.f4.accountsError = null;
      await f4TapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_payment_account_1')), findsOneWidget);
    });

    Future<void> openCorrection(WidgetTester t, FinanceFakeAuth auth) async {
      final entry = auth.ledger.firstWhere((e) => e['id'] == 4);
      await openDialogAt(
        t,
        (context) => FinancePaymentDialog.show(
          context,
          scope: _scope(auth),
          apartmentId: 302,
          apartmentLabel: 'A Blok - 6',
          correcting: _entry(entry),
          now: () => _now,
        ),
        width: 400,
        height: 1300,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
    }

    testWidgets('R13 P2-2: düzeltmede hesap İSTEĞE BAĞLI görünür; seçilmezse 4a düzeltme yolu (eski ödemenin hesabı)', (t) async {
      final auth = _auth();
      await openCorrection(t, auth);
      expect(find.text('Hesap'), findsOneWidget);
      expect(find.textContaining('İsteğe bağlı: eski tahsilat bir hesaba işlenmişse'), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_1'))).selected, isFalse);
      await f4Tap(t, 'finance_method_cash');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.correctCalls, hasLength(1));
      expect(auth.f4.correctPaymentCalls, isEmpty);
    });

    testWidgets('R13 P2-2: eski ödeme hesaba eşlenmemişse sunucu ACCOUNT_REQUIRED der -> seçim zorunlu olur, hesap gövdede gider', (t) async {
      final auth = _auth();
      await openCorrection(t, auth);
      await f4Tap(t, 'finance_method_cash');
      auth.paymentError = f4Coded('ACCOUNT_REQUIRED', 409);
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(find.textContaining('tahsilat için bir hesap seçin'), findsWidgets);
      auth.paymentError = null;
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(find.text('Tahsilatın gireceği hesabı seçin.'), findsOneWidget, reason: 'artık zorunlu');
      expect(auth.f4.correctPaymentCalls, isEmpty);
      await f4Tap(t, 'finance_payment_account_2');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.f4.correctPaymentCalls.single['account_id'], 2);
      expect(auth.f4.correctPaymentCalls.single['entry_id'], 4);
    });

    testWidgets('R13 P2-3: tahsilat tarihi tüm hesapların açılışından ÖNCEyse hesap sorulmaz ve 4a yolu kullanılır', (t) async {
      final auth = _auth(seed: false);
      auth.f4.accounts
        ..add(f4AccountJson(1, 'Nakit Kasa', openingDate: '2026-10-01'))
        ..add(f4AccountJson(2, 'Ziraat', kind: 'bank', openingDate: '2026-10-01'));
      await openPayment(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_payment_account_1')), findsOneWidget, reason: 'bugün (16.10) hesaplar açık');
      await f4Enter(t, 'finance_payment_date', '15.09.2026');
      expect(find.byKey(const ValueKey<String>('finance_payment_account_1')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_payment_before_opening')), findsOneWidget);
      await f4Enter(t, 'finance_payment_amount', '100');
      await f4Tap(t, 'finance_method_cash');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.paymentCalls, hasLength(1), reason: '4a yolu: hesapsız');
      expect(auth.f4.paymentCalls, isEmpty);
    });

    testWidgets('R13 P2-3: tarih açılıştan sonraya alınınca seçici geri gelir; seçili hesap açılıştan önceki tarihe geçince bırakılır', (t) async {
      final auth = _auth(seed: false);
      auth.f4.accounts
        ..add(f4AccountJson(1, 'Eski Kasa', openingDate: '2026-01-01'))
        ..add(f4AccountJson(2, 'Yeni Banka', kind: 'bank', openingDate: '2026-10-01'));
      await openPayment(t, auth);
      await f4Tap(t, 'finance_method_transfer');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_2'))).selected, isTrue);
      await f4Enter(t, 'finance_payment_date', '15.09.2026');
      expect(find.byKey(const ValueKey<String>('finance_payment_account_2')), findsNothing, reason: 'açılış 01.10');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_payment_account_1'))).selected, isTrue, reason: 'tek kullanılabilir hesap ön seçilir');
      await f4Enter(t, 'finance_payment_date', '16.10.2026');
      expect(find.byKey(const ValueKey<String>('finance_payment_account_2')), findsOneWidget);
    });

    testWidgets('yeni sunucu kuralı: TÜM hesaplar pasifse uyarı yazılır; sunucunun Türkçe iletisi (ACCOUNT_INACTIVE) olduğu gibi gösterilir', (t) async {
      final auth = _auth(seed: false);
      auth.f4.accounts
        ..add(f4AccountJson(1, 'Eski Kasa', active: false))
        ..add(f4AccountJson(2, 'Eski Banka', kind: 'bank', active: false));
      auth.paymentError = ApiException(
        'Tüm kasa ve banka hesapları pasif. Tahsilat girmek için önce bir hesabı yeniden etkinleştirin.',
        statusCode: 409,
        code: 'ACCOUNT_INACTIVE',
      );
      await openPayment(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_payment_accounts_inactive')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_payment_account_1')), findsNothing);
      await f4Enter(t, 'finance_payment_amount', '100');
      await f4Tap(t, 'finance_method_cash');
      await f4Tap(t, 'finance_payment_submit');
      await settleFor(t);
      expect(find.textContaining('Tüm kasa ve banka hesapları pasif. Tahsilat girmek için'), findsWidgets);
    });
  });
}

LedgerEntry _entry(Map<String, dynamic> row) => LedgerEntry.fromJson(<String, dynamic>{...row, 'reversed_by_entry_id': null});
