// Ekipman ve Bakım > Teklifler: karşılaştırma tablosu (P2-10) ve onaylı teklif revizyonu / sürüm geçmişi (P2-9, K14).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; açık / koyu), karşılaştırma tablosu yalnız iki ve daha çok teklifte,
// "en düşük" / "en hızlı" yalnız sunucu işaretiyle, karışık KDV esası uyarısı, onaylı teklifte "tarihli fiyat" etiketi ve "Revizyon oluştur",
// bekleyen revizyonda onaylı sürüm özeti, salt okur kullanıcıda eylem yok, sürüm geçmişi, ve EquipmentView içinde uçtan uca form akışları
// (teklif ekle yeni alanlarla, açık teklifi düzenle, revizyon oluştur => reviseQuote gövdesi, revizyon kabulünde önceki kayıt onayı).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';
import 'package:site_kapi_kontrol/ui/views/equipment_quotes_panel.dart';
import 'package:site_kapi_kontrol/ui/views/equipment_view.dart';

import '../design/harness.dart' show pumpAt;
import 'list_fixtures.dart' show listMatrix, pumpList;

EquipmentQuote q(Map<String, dynamic> j) => EquipmentQuote.fromJson(<String, dynamic>{'topic': 'Asansör bakımı', 'vendor_name': 'Yıldız', 'amount_kurus': 320000, 'status': 'open', ...j});

/// Sunucunun liste yanıtına benzer örnek veri: kamera konusunda üç açık teklif (en düşük + en hızlı işaretli), asansör konusunda onaylı v1 + bekleyen v2.
List<EquipmentQuote> sample({bool mixed = false}) => <EquipmentQuote>[
  q(<String, dynamic>{'id': 1, 'topic': 'Kamera sistemi', 'vendor_name': 'Alfa', 'amount_kurus': 500000, 'delivery_days': 30, 'vat_included': false, 'valid_until': '2099-12-31', 'note': '8 kamera, kurulum dahil', 'basis_mixed': mixed}),
  q(<String, dynamic>{'id': 2, 'topic': 'Kamera sistemi', 'vendor_name': 'Beta', 'amount_kurus': 450000, 'delivery_days': 10, 'vat_included': mixed ? true : false, 'lowest': !mixed, 'fastest': true, 'basis_mixed': mixed}),
  q(<String, dynamic>{'id': 3, 'topic': 'Kamera sistemi', 'vendor_name': 'Gama', 'amount_kurus': 400000, 'valid_until': '2020-01-01', 'expired': true}),
  q(<String, dynamic>{
    'id': 12,
    'revision_no': 2,
    'previous_id': 11,
    'revision_reason': 'Ek parça ihtiyacı',
    'amount_kurus': 380000,
    'editable': true,
    'revisable': false,
    'version_count': 2,
    'approved_version': <String, dynamic>{'id': 11, 'revision_no': 1, 'amount_kurus': 320000, 'decided_at': '2026-10-24T09:00:00.000Z', 'accepted_as': 'contract', 'contract_id': 501},
  }),
];

EquipmentQuote acceptedQuote({bool revisable = true, bool history = false}) => q(<String, dynamic>{
  'id': 21,
  'topic': 'Hidrofor',
  'vendor_name': 'Delta',
  'amount_kurus': 150000,
  'status': 'accepted',
  'accepted_as': 'expense',
  'decided_at': '2026-10-24T09:00:00.000Z',
  'expense_id': 77,
  'editable': false,
  'revisable': revisable,
  if (history) ...<String, dynamic>{'revision_no': 3, 'previous_id': 20, 'version_count': 3, 'revision_reason': 'Zam'},
});

Widget panel(List<EquipmentQuote> quotes, {bool canWrite = true, List<String>? taps}) => EquipmentQuotesPanel(
  quotes: quotes,
  canWrite: canWrite,
  onAccept: (x) => taps?.add('accept:${x.id}'),
  onReject: (x) => taps?.add('reject:${x.id}'),
  onEdit: (x) => taps?.add('edit:${x.id}'),
  onRevise: (x) => taps?.add('revise:${x.id}'),
  onHistory: (x) => taps?.add('history:${x.id}'),
);

class _NoAuth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Yalnız Teklifler sekmesinin çağırdığı uçları taklit eden sahte hizmet; yazma çağrılarının gövdesini kaydeder.
class FakeQuotesService implements EquipmentService {
  FakeQuotesService(this.quotesList, {this.history, this.failRevise});

  List<EquipmentQuote> quotesList;
  final QuoteHistory? history;
  final ApiException? failRevise;
  final List<String> calls = <String>[];
  Map<String, Object?>? lastBody;

  @override
  Future<List<EquipmentItem>> list(int site) async => const <EquipmentItem>[];
  @override
  Future<List<MaintenancePlan>> due(int site) async => const <MaintenancePlan>[];
  @override
  Future<List<EquipmentQuote>> quotes(int site) async => quotesList;
  @override
  Future<EquipmentBreakdown> breakdown(int site) async =>
      const EquipmentBreakdown(from: '2026-01', to: '2026-12', items: <BreakdownRow>[], linkedMinor: 0, unlinkedMinor: 0, totalMinor: 0);
  @override
  Future<void> createQuote(int site, Map<String, Object?> body) async {
    calls.add('create');
    lastBody = body;
  }

  @override
  Future<void> updateQuote(int site, int id, Map<String, Object?> body) async {
    calls.add('update:$id');
    lastBody = body;
  }

  @override
  Future<void> reviseQuote(int site, int id, Map<String, Object?> body) async {
    calls.add('revise:$id');
    lastBody = body;
    if (failRevise != null) throw failRevise!;
  }

  @override
  Future<void> acceptQuote(int site, int id, Map<String, Object?> body) async {
    calls.add('accept:$id');
    lastBody = body;
  }

  @override
  Future<void> rejectQuote(int site, int id) async => calls.add('reject:$id');
  @override
  Future<QuoteHistory> quoteHistory(int site, int id) async {
    calls.add('history:$id');
    return history ?? QuoteHistory(items: quotesList, latestId: id);
  }

  @override
  Future<(List<PickOption>, List<PickOption>)> financeChoices(int site) async => (<PickOption>[const PickOption(1, 'Bakım')], <PickOption>[const PickOption(2, 'Kasa')]);
  @override
  Future<List<PickOption>> vendors(int site) async => <PickOption>[const PickOption(3, 'Delta A.Ş.')];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeQuotesService> pumpView(WidgetTester t, List<EquipmentQuote> quotes, {bool financeOn = true, bool canWrite = true, ApiException? failRevise}) async {
  final service = FakeQuotesService(quotes, failRevise: failRevise);
  await pumpAt(
    t,
    EquipmentView(
      authService: _NoAuth(),
      service: service,
      sites: <EquipmentSite>[EquipmentSite(code: 11, name: 'Gül Sitesi', canWrite: canWrite, financeOn: financeOn, contractsOn: true)],
    ),
    width: 900,
    height: 2600,
    scale: 1.0,
  );
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(find.widgetWithText(ChoiceChip, 'Teklifler'));
  await t.pump(const Duration(milliseconds: 300));
  return service;
}

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  group('saf yardımcılar', () {
    test('tarih, kuruş girişi ve sürüm farkı', () {
      expect(quoteDate('2026-10-24'), '24.10.2026');
      expect(quoteDate('2026-10-24T09:00:00.000Z'), '24.10.2026');
      expect(kurusToInput(320000), '3200,00');
      expect(kurusToInput(5), '0,05');
      expect(parseKurus(kurusToInput(123456)), 123456);
      expect(quoteDelta(60000), '+600,00 TL');
      expect(quoteDelta(-15000), '-150,00 TL');
      expect(quoteDelta(0), 'Tutar değişmedi');
    });
    test('durum etiketi ve tonu', () {
      expect(quoteStatusLabel(q(<String, dynamic>{'status': 'accepted', 'accepted_as': 'contract'})), 'Kabul: sözleşme');
      expect(quoteStatusLabel(q(<String, dynamic>{'status': 'accepted', 'accepted_as': 'expense'})), 'Kabul: gider');
      expect(quoteStatusLabel(q(<String, dynamic>{'status': 'rejected'})), 'Reddedildi');
      expect(quoteStatusLabel(q(<String, dynamic>{'status': 'rejected', 'revision_no': 2})), 'Revizyon reddedildi');
      expect(quoteStatusLabel(q(<String, dynamic>{'expired': true})), 'Süresi doldu');
      expect(quoteStatusLabel(q(<String, dynamic>{'revision_no': 2})), 'Revizyon: onay bekliyor');
      expect(quoteStatusLabel(q(<String, dynamic>{})), 'Açık');
    });
  });

  listMatrix('Teklifler paneli (tablo + kartlar + revizyon)', (t, width, height, scale, dark) async {
    await pumpList(t, panel(<EquipmentQuote>[...sample(), acceptedQuote(history: true)]), width: width, height: height, scale: scale, dark: dark);
    expect(find.byKey(const ValueKey<String>('quote_compare_table')), findsOneWidget);
    expect(find.text('Revizyon oluştur'), findsOneWidget);
  });

  listMatrix('Karışık KDV uyarısı', (t, width, height, scale, dark) async {
    await pumpList(t, panel(sample(mixed: true)), width: width, height: height, scale: scale, dark: dark);
    expect(find.byKey(const ValueKey<String>('quote_compare_mixed')), findsOneWidget);
  });

  group('karşılaştırma tablosu', () {
    testWidgets('yalnız iki ve daha çok teklifi olan konuda çıkar; satırlar ve işaretler görünür', (t) async {
      await pumpAt(t, panel(sample()), width: 600, height: 2400, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('quote_compare_table')), findsOneWidget, reason: 'yalnız Kamera konusu 3 teklifli; asansör tek teklif');
      for (final label in <String>['Firma', 'Tutar', 'KDV', 'Geçerlilik', 'Teslim süresi', 'Kapsam / not', 'Durum']) {
        expect(find.descendant(of: find.byKey(const ValueKey<String>('quote_compare_table')), matching: find.text(label)), findsOneWidget, reason: label);
      }
      final table = find.byKey(const ValueKey<String>('quote_compare_table'));
      expect(find.descendant(of: table, matching: find.text('En düşük')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('En hızlı')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('10 gün')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('4.500,00 TL')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('8 kamera, kurulum dahil')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.textContaining('(doldu)')), findsOneWidget, reason: 'süresi dolan teklif belirtilir');
      expect(find.byKey(const ValueKey<String>('quote_compare_mixed')), findsNothing);
      expect(find.textContaining('Kapsamlar farklı olabilir'), findsOneWidget);
    });

    testWidgets('karışık KDV esasında uyarı çıkar ve "en düşük" işareti yoktur', (t) async {
      await pumpAt(t, panel(sample(mixed: true)), width: 600, height: 2400, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('quote_compare_mixed')), findsOneWidget);
      expect(find.text('En düşük'), findsNothing);
      expect(find.textContaining('doğrudan kıyaslanamaz'), findsWidgets);
    });

    testWidgets('tek teklifli konuda tablo yok', (t) async {
      await pumpAt(t, panel(<EquipmentQuote>[acceptedQuote()]), width: 600, height: 1200, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('quote_compare_table')), findsNothing);
      expect(find.byKey(const ValueKey<String>('quote_card_21')), findsOneWidget);
    });

    testWidgets('boş liste bilgi kartı gösterir', (t) async {
      await pumpAt(t, panel(const <EquipmentQuote>[]), width: 600, height: 600, scale: 1.0);
      expect(find.textContaining('Henüz teklif yok'), findsOneWidget);
    });
  });

  group('onaylı teklif ve revizyon kartları', () {
    testWidgets('onaylı teklif: tarihli fiyat etiketi, Revizyon oluştur; açık teklif Düzenle / Reddet / Kabul et', (t) async {
      final taps = <String>[];
      await pumpAt(t, panel(<EquipmentQuote>[acceptedQuote(), q(<String, dynamic>{'id': 30, 'topic': 'Kapı', 'editable': true})], taps: taps), width: 600, height: 2000, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('quote_dated_price')), findsOneWidget);
      expect(find.textContaining('güncel fiyat sayılmaz'), findsOneWidget);
      expect(find.textContaining('24.10.2026'), findsWidgets);
      final accepted = find.byKey(const ValueKey<String>('quote_card_21'));
      expect(find.descendant(of: accepted, matching: find.text('Revizyon oluştur')), findsOneWidget);
      expect(find.descendant(of: accepted, matching: find.text('Kabul et')), findsNothing, reason: 'onaylı teklif yeniden kabul edilmez');
      expect(find.descendant(of: accepted, matching: find.text('Düzenle')), findsNothing, reason: 'onaylı teklif yerinde düzenlenmez');
      expect(find.descendant(of: accepted, matching: find.text('Reddet')), findsNothing);
      final open = find.byKey(const ValueKey<String>('quote_card_30'));
      for (final label in <String>['Düzenle', 'Reddet', 'Kabul et']) {
        expect(find.descendant(of: open, matching: find.text(label)), findsOneWidget, reason: label);
      }
      expect(find.descendant(of: open, matching: find.text('Revizyon oluştur')), findsNothing);
      await t.tap(find.descendant(of: accepted, matching: find.text('Revizyon oluştur')));
      await t.tap(find.descendant(of: open, matching: find.text('Düzenle')));
      await t.tap(find.descendant(of: open, matching: find.text('Reddet')));
      await t.tap(find.descendant(of: open, matching: find.text('Kabul et')));
      expect(taps, <String>['revise:21', 'edit:30', 'reject:30', 'accept:30']);
    });

    testWidgets('bekleyen revizyon: sürüm çipi, gerekçe, onaylı sürüm özeti ve geçmiş düğmesi', (t) async {
      final taps = <String>[];
      await pumpAt(t, panel(<EquipmentQuote>[sample().last], taps: taps), width: 600, height: 1600, scale: 1.0);
      expect(find.text('Sürüm 2'), findsOneWidget);
      expect(find.text('Revizyon: onay bekliyor'), findsOneWidget);
      expect(find.textContaining('Ek parça ihtiyacı'), findsOneWidget);
      final approved = find.byKey(const ValueKey<String>('quote_approved_version'));
      expect(approved, findsOneWidget);
      final text = t.widget<Text>(approved).data!;
      expect(text, contains('1. sürüm'));
      expect(text, contains('3.200,00 TL'));
      expect(text, contains('24.10.2026'));
      expect(text, contains('sözleşme olarak kayıtlı'));
      expect(text, contains('onaylı sürüm geçerlidir'));
      await t.tap(find.text('Sürüm geçmişi'));
      expect(taps, <String>['history:12']);
    });

    testWidgets('salt okur kullanıcı: yazma eylemi yok, sürüm geçmişi var', (t) async {
      final taps = <String>[];
      await pumpAt(t, panel(<EquipmentQuote>[acceptedQuote(history: true), q(<String, dynamic>{'id': 30, 'topic': 'Kapı', 'editable': true})], canWrite: false, taps: taps), width: 600, height: 2000, scale: 1.0);
      for (final label in <String>['Revizyon oluştur', 'Düzenle', 'Reddet', 'Kabul et']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text('Sürüm geçmişi'), findsOneWidget);
    });

    testWidgets('süresi dolan açık teklif: kabul yok, düzenle (tarihi uzatmak için) ve reddet var', (t) async {
      await pumpAt(t, panel(<EquipmentQuote>[q(<String, dynamic>{'id': 40, 'topic': 'Boya', 'valid_until': '2020-01-01', 'expired': true, 'editable': true})]), width: 600, height: 1200, scale: 1.0);
      expect(find.text('Kabul et'), findsNothing);
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Reddet'), findsOneWidget);
      expect(find.text('Süresi doldu'), findsOneWidget);
    });
  });

  group('sürüm geçmişi', () {
    QuoteHistory history() => QuoteHistory(
      items: <EquipmentQuote>[
        q(<String, dynamic>{'id': 11, 'status': 'accepted', 'accepted_as': 'contract', 'contract_id': 501, 'amount_kurus': 320000, 'decided_at': '2026-10-24T09:00:00.000Z', 'note': 'Kontrol + kontak seti'}),
        q(<String, dynamic>{'id': 12, 'status': 'rejected', 'revision_no': 2, 'previous_id': 11, 'revision_reason': 'Zam talebi', 'amount_kurus': 380000, 'decided_at': '2026-10-26T09:00:00.000Z'}),
        q(<String, dynamic>{'id': 13, 'revision_no': 3, 'previous_id': 12, 'revision_reason': 'Pazarlık sonrası', 'amount_kurus': 350000, 'delivery_days': 21}),
      ],
      latestId: 13,
      approvedId: 11,
    );

    testWidgets('tüm sürümler eskiden yeniye: fark, gerekçe, onaylı ve en son işareti, oluşan kayıt', (t) async {
      final service = FakeQuotesService(const <EquipmentQuote>[], history: history());
      await pumpAt(
        t,
        SizedBox(height: 1600, child: QuoteHistorySheet(service: service, site: const EquipmentSite(code: 11, name: 'Gül'), quote: q(<String, dynamic>{'id': 13, 'revision_no': 3}))),
        width: 600,
        height: 1700,
        scale: 1.0,
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(service.calls, <String>['history:13']);
      expect(find.text('Sürüm geçmişi'), findsOneWidget);
      for (final n in <String>['1. sürüm', '2. sürüm', '3. sürüm']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.text('Önceki sürüme göre: +600,00 TL'), findsOneWidget);
      expect(find.text('Önceki sürüme göre: -300,00 TL'), findsOneWidget);
      expect(find.textContaining('Zam talebi'), findsOneWidget);
      expect(find.textContaining('Pazarlık sonrası'), findsOneWidget);
      expect(find.text('Geçerli onaylı sürüm'), findsOneWidget);
      expect(find.text('En son sürüm'), findsOneWidget);
      expect(find.text('Oluşan kayıt: Sözleşme #501'), findsOneWidget);
      expect(find.text('Revizyon reddedildi'), findsOneWidget);
      expect(find.textContaining('teslim 21 gün'), findsOneWidget);
    });

    testWidgets('hata: mesaj ve Tekrar Dene; yüklenirken gösterge', (t) async {
      var attempts = 0;
      final service = _FailingHistory(() {
        attempts += 1;
        if (attempts == 1) throw ApiException('Sunucuya bağlanılamadı.');
        return history();
      });
      await pumpAt(
        t,
        SizedBox(height: 1600, child: QuoteHistorySheet(service: service, site: const EquipmentSite(code: 11, name: 'Gül'), quote: q(<String, dynamic>{'id': 13, 'revision_no': 3}))),
        width: 600,
        height: 1700,
        scale: 1.0,
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      await t.tap(find.text('Tekrar Dene'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('3. sürüm'), findsOneWidget);
    });
  });

  group('EquipmentView: formlar ve istekler', () {
    testWidgets('Teklifler sekmesi paneli gösterir; salt okur kullanıcıda Teklif ekle düğmesi yok', (t) async {
      await pumpView(t, sample(), canWrite: false);
      expect(find.byKey(const ValueKey<String>('quotes_panel')), findsOneWidget);
      expect(find.text('Teklif ekle'), findsNothing);
      expect(find.text('Revizyon oluştur'), findsNothing);
    });

    testWidgets('Teklif ekle: yeni alanlar formda ve gövdede (teslim süresi, KDV esası, kapsam / not)', (t) async {
      final service = await pumpView(t, const <EquipmentQuote>[]);
      await t.tap(find.text('Teklif ekle'));
      await t.pump(const Duration(milliseconds: 300));
      for (final label in <String>['Teslim süresi (gün)', 'Tutarın KDV esası (karşılaştırma için)', 'Kapsam / not (örn. kontrol + parça, garanti)']) {
        expect(find.textContaining(label), findsOneWidget, reason: label);
      }
      await t.enterText(field('Konu (aynı konudaki teklifler karşılaştırılır) *'), 'Asansör bakımı');
      await t.enterText(field('Firma *'), 'Yıldız');
      await t.enterText(field('Tutar (TL) *'), '3200,50');
      await t.enterText(field('Teslim süresi (gün)'), '14');
      await t.enterText(field('Kapsam / not (örn. kontrol + parça, garanti)'), 'Kontrol ve kontak seti');
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, <String>['create']);
      expect(service.lastBody, <String, Object?>{
        'topic': 'Asansör bakımı',
        'vendor_name': 'Yıldız',
        'amount_kurus': 320050,
        'delivery_days': 14,
        'note': 'Kontrol ve kontak seti',
      });
    });

    testWidgets('Teklif ekle: geçersiz teslim süresi istek göndermez', (t) async {
      final service = await pumpView(t, const <EquipmentQuote>[]);
      await t.tap(find.text('Teklif ekle'));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(field('Konu (aynı konudaki teklifler karşılaştırılır) *'), 'Konu');
      await t.enterText(field('Firma *'), 'Firma');
      await t.enterText(field('Tutar (TL) *'), '100');
      await t.enterText(field('Teslim süresi (gün)'), '5000');
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, isEmpty);
      expect(find.textContaining('0 ile 1095 gün'), findsOneWidget);
    });

    testWidgets('Açık teklifi düzenle: mevcut değerler dolu gelir, PATCH gövdesinde yeni tutar', (t) async {
      final service = await pumpView(t, <EquipmentQuote>[q(<String, dynamic>{'id': 30, 'topic': 'Kapı', 'amount_kurus': 100000, 'delivery_days': 7, 'editable': true})]);
      await t.tap(find.text('Düzenle'));
      await t.pump(const Duration(milliseconds: 300));
      expect((t.widget<TextField>(field('Tutar (TL) *')).controller!.text), '1000,00');
      expect((t.widget<TextField>(field('Teslim süresi (gün)')).controller!.text), '7');
      await t.enterText(field('Tutar (TL) *'), '900');
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, <String>['update:30']);
      expect(service.lastBody!['amount_kurus'], 90000);
      expect(service.lastBody!['delivery_days'], 7);
    });

    testWidgets('Revizyon oluştur: gerekçe zorunlu; gövdede yalnız değişen alanlar + reason', (t) async {
      final service = await pumpView(t, <EquipmentQuote>[acceptedQuote()]);
      await t.tap(find.text('Revizyon oluştur'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Revizyon oluştur (2. sürüm)'), findsOneWidget);
      // Gerekçesiz kaydetme: form uyarır, istek yok.
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, isEmpty);
      await t.enterText(field('Değişiklik gerekçesi (örn. ek parça ihtiyacı) *'), 'Ek parça ihtiyacı');
      await t.enterText(field('Yeni tutar (TL) *'), '1800,00');
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, <String>['revise:21']);
      expect(service.lastBody, <String, Object?>{'reason': 'Ek parça ihtiyacı', 'amount_kurus': 180000});
    });

    testWidgets('Revizyon oluştur: hiçbir alan değişmediyse istek gitmez', (t) async {
      final service = await pumpView(t, <EquipmentQuote>[acceptedQuote()]);
      await t.tap(find.text('Revizyon oluştur'));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(field('Değişiklik gerekçesi (örn. ek parça ihtiyacı) *'), 'Değişiklik yok');
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, isEmpty);
      expect(find.textContaining('en az bir alanı değiştirin'), findsOneWidget);
    });

    testWidgets('Revizyon oluştur: sunucu hatası (daha yeni sürüm) kullanıcıya Türkçe gösterilir', (t) async {
      final service = await pumpView(t, <EquipmentQuote>[acceptedQuote()], failRevise: ApiException('Bu teklifin daha yeni bir sürümü var. Listeyi yenileyip en son sürümle devam edin.', statusCode: 409, code: 'QUOTE_NOT_LATEST'));
      await t.tap(find.text('Revizyon oluştur'));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(field('Değişiklik gerekçesi (örn. ek parça ihtiyacı) *'), 'Zam');
      await t.enterText(field('Yeni tutar (TL) *'), '1700');
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 400));
      expect(service.calls, <String>['revise:21']);
      expect(find.textContaining('daha yeni bir sürümü var'), findsOneWidget);
    });

    testWidgets('Revizyon kabulü: önceki sürüm kayıtlıysa çift kayıt uyarısı; onayla acknowledge_previous gider, vazgeçince istek yok', (t) async {
      final revision = q(<String, dynamic>{
        'id': 51,
        'topic': 'Hidrofor',
        'vendor_name': 'Delta',
        'amount_kurus': 180000,
        'revision_no': 2,
        'previous_id': 21,
        'revision_reason': 'Zam',
        'editable': true,
        'approved_version': <String, dynamic>{'id': 21, 'revision_no': 1, 'amount_kurus': 150000, 'expense_id': 77, 'accepted_as': 'expense'},
      });
      final service = await pumpView(t, <EquipmentQuote>[revision]);
      await t.tap(find.text('Kabul et'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Önceki sürüm zaten kayıtlı'), findsOneWidget);
      expect(find.textContaining('AYRI bir kayıt oluşur'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pump(const Duration(milliseconds: 300));
      expect(service.calls, isEmpty);
      await t.tap(find.text('Kabul et'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Devam et'));
      await t.pump(const Duration(milliseconds: 300));
      // Sonraki adım: kabul biçimi seçimi (gider) ve gider bilgileri.
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 400));
      expect(service.calls, <String>['accept:51']);
      expect(service.lastBody!['acknowledge_previous'], isTrue);
      expect(service.lastBody!['as'], 'expense');
    });

    testWidgets('İlk sürüm teklifin kabulünde ek uyarı yoktur (acknowledge_previous gönderilmez)', (t) async {
      final service = await pumpView(t, <EquipmentQuote>[q(<String, dynamic>{'id': 60, 'topic': 'Kapı', 'editable': true})]);
      await t.tap(find.text('Kabul et'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Önceki sürüm zaten kayıtlı'), findsNothing);
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Kaydet'));
      await t.pump(const Duration(milliseconds: 400));
      expect(service.calls, <String>['accept:60']);
      expect(service.lastBody!.containsKey('acknowledge_previous'), isFalse);
    });
  });
}

class _FailingHistory implements EquipmentService {
  _FailingHistory(this.produce);

  final QuoteHistory Function() produce;

  @override
  Future<QuoteHistory> quoteHistory(int site, int id) async => produce();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
