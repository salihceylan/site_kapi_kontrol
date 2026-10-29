// Kiracı borcunun malike devri (karar K1) ve gecikmede öneri (karar K17) arayüzü: öneri şeridi (Daireler sekmesi), aday listesi penceresi,
// devir penceresi (önizleme + nedenli onay + geçmiş + geri alma) ve ekstredeki "Kiracı Borcunu Malike Devret" düğmesi. Sunucu davranışı
// sahte 4b API'sinde taklit edilir (finance_4b_fixtures.dart: bayat önizleme 409, devirden sonra listeden düşme, geri alma).
//
// Devir KENDİLİĞİNDEN olmaz: önizleme yazmaz, onay nedenlidir, işlem anahtarı veri imzasına bağlıdır, geçmişte izlenir, geri alınabilir.
// AGENTS.md kural 6: dört hücre (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) x açık / koyu tema.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_liability_candidates_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_liability_transfer_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_liability_banner.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';

final DateTime _now = DateTime.utc(2026, 10, 29, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Map<String, dynamic> _candidate(
  int id, {
  String unit = 'Daire 5',
  String? block = 'A Blok',
  String reason = 'overdue',
  bool hasOwner = true,
  int total = 150000,
  int items = 2,
}) => <String, dynamic>{
  'apartment_id': id,
  'unit_label': unit,
  'block_name': block,
  'reason': reason,
  'tenant_present': reason == 'overdue',
  'has_owner': hasOwner,
  'can_transfer': hasOwner,
  'item_count': items,
  'total_minor': total,
  'oldest_due_date': '2026-08-10',
};

void _setCandidates(FakeFinance4bApi f4, List<Map<String, dynamic>> items, {bool truncated = false}) {
  f4.liabilityCandidatesJson = <String, dynamic>{
    'items': items,
    'count': items.length,
    'total_minor': items.fold<int>(0, (sum, c) => sum + (c['total_minor'] as int)),
    'truncated': truncated,
  };
}

Map<String, dynamic> _preview(int id, {bool hasOwner = true, bool lateFee = true}) => <String, dynamic>{
  'apartment_id': id,
  'has_owner': hasOwner,
  'can_transfer': hasOwner,
  'items': <Map<String, dynamic>>[
    <String, dynamic>{'entry_id': 11, 'name': 'Ağustos aidatı', 'due_date': '2026-08-10', 'original_minor': 100000, 'remaining_minor': 50000, 'paid_minor': 50000, 'fund': 'operating'},
    <String, dynamic>{'entry_id': 12, 'name': 'Eylül aidatı', 'due_date': '2026-09-10', 'original_minor': 100000, 'remaining_minor': 100000, 'paid_minor': 0, 'fund': 'operating'},
  ],
  'excluded_late_fee': lateFee
      ? <Map<String, dynamic>>[
          <String, dynamic>{'entry_id': 13, 'name': 'Gecikme tazminatı', 'due_date': '2026-09-30', 'remaining_minor': 2500},
        ]
      : <Map<String, dynamic>>[],
  'item_count': 2,
  'total_minor': 150000,
  'preview_hash': 'c' * 64,
  'tenant_balance_minor': 152500,
  'owner_balance_minor': 0,
};

Map<String, dynamic> _row(
  int id,
  int apartmentId, {
  String kind = 'transfer',
  bool reversible = true,
  int? reversedBy,
  String reason = 'Kiracı taşındı, borç ödenmedi',
}) => <String, dynamic>{
  'id': id,
  'apartment_id': apartmentId,
  'kind': kind,
  'from_party': kind == 'transfer' ? 'tenant' : 'owner',
  'to_party': kind == 'transfer' ? 'owner' : 'tenant',
  'total_minor': 150000,
  'item_count': 2,
  'reason': reason,
  'reverses_transfer_id': null,
  'reversed_by_transfer_id': reversedBy,
  'created_by_name': 'Yönetici',
  'created_at': '2026-10-29T09:00:00.000Z',
  'reversible': reversible,
};

FinanceFakeAuth _auth({bool preview = true}) {
  final auth = FinanceFakeAuth.seeded();
  if (preview) auth.f4.liabilityPreviews[301] = _preview(301);
  return auth;
}

Future<void> _openTransfer(
  WidgetTester t,
  FinanceFakeAuth auth, {
  int apartmentId = 301,
  bool canWrite = true,
  double width = 420,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onChanged,
}) async {
  await openDialogAt(
    t,
    (context) => FinanceLiabilityTransferDialog.show(
      context,
      scope: _scope(auth, canWrite: canWrite),
      apartmentId: apartmentId,
      apartmentLabel: 'A Blok - 5',
      onChanged: onChanged,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  await settleFor(t);
}

Future<void> _openCandidates(
  WidgetTester t,
  FinanceFakeAuth auth, {
  double width = 420,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onChanged,
}) async {
  await openDialogAt(
    t,
    (context) => FinanceLiabilityCandidatesDialog.show(context, scope: _scope(auth), onChanged: onChanged),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  await settleFor(t);
}

Future<void> _tap(WidgetTester t, String key) async {
  await f4Tap(t, key);
  await settleFor(t);
}

bool _has(String key) => find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty;

Future<void> _approveWithReason(WidgetTester t, String reason) async {
  await f4Enter(t, 'finance_reason_text', reason);
  await _tap(t, 'finance_reason_confirm');
  await settleFor(t);
  await settleFor(t);
}

void main() {
  group('devir penceresi: önizleme', () {
    testWidgets('kalemler, toplam, ödenmiş kısım, tazminat istisnası ve hesap bakiyeleri; geçmiş boş; hiçbir şey yazılmaz', (t) async {
      final auth = _auth();
      await _openTransfer(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_liability_preview')), findsOneWidget);
      expect(find.text('2 borç kalemi'), findsOneWidget);
      expect(find.text('Devredilecek toplam: 1.500,00 ₺'), findsOneWidget);
      expect(find.textContaining('Ağustos aidatı • Vade 10.08.2026'), findsOneWidget);
      expect(find.text('500,00 ₺'), findsOneWidget, reason: 'kısmen ödenmiş kalemin devredilecek kalanı');
      expect(find.text('Ödenen 500,00 ₺ kiracıda kalır'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_liability_excluded')), findsOneWidget);
      expect(find.textContaining('Gecikme tazminatı devredilmez, kiracıda kalır: 1 kalem, 25,00 ₺.'), findsOneWidget);
      expect(find.textContaining('Kiracı hesabı:'), findsOneWidget);
      expect(find.text('Bu daire için devir kaydı yok.'), findsOneWidget);
      expect(auth.f4.writes, isEmpty, reason: 'önizleme yazmaz');
      expect(auth.f4.callCount('previewLiabilityTransfer'), 1);
      expect(auth.f4.callCount('listLiabilityTransfers'), 1);
    });

    testWidgets('devredilecek kalem yoksa açıklayıcı not; Malike Devret düğmesi hiç çıkmaz', (t) async {
      final auth = _auth(preview: false);
      await _openTransfer(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_liability_empty')), findsOneWidget);
      expect(find.text('Devredilecek, vadesi geçmiş ve ödenmemiş kiracı borcu yok.'), findsOneWidget);
      expect(_has('finance_liability_transfer_button'), isFalse);
    });

    testWidgets('malik kaydı yok: uyarı yazılır ve devir kapalıdır (düğmeye dokunmak onay açmaz)', (t) async {
      final auth = _auth(preview: false);
      auth.f4.liabilityPreviews[301] = _preview(301, hasOwner: false);
      await _openTransfer(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_liability_no_owner')), findsOneWidget);
      await _tap(t, 'finance_liability_transfer_button');
      expect(_has('finance_reason_text'), isFalse, reason: 'devredilemez: onay penceresi açılmaz');
      expect(auth.f4.writes, isEmpty);
    });

    testWidgets('önizleme okunamazsa asla "borç yok" denmez: neden yazılır, Tekrar Dene yeniden okur', (t) async {
      final auth = _auth();
      auth.f4.liabilityPreviewError = ApiException('Devir önizlemesi hazırlanamadı.', statusCode: 500, code: 'INTERNAL');
      await _openTransfer(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_liability_load_error')), findsOneWidget);
      expect(_has('finance_liability_preview'), isFalse);
      expect(find.text('Devredilecek, vadesi geçmiş ve ödenmemiş kiracı borcu yok.'), findsNothing);
      auth.f4.liabilityPreviewError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_liability_preview')), findsOneWidget);
    });

    testWidgets('kurul (salt okur): önizleme ve geçmiş görünür; Malike Devret ve Geri Al düğmeleri YOK', (t) async {
      final auth = _auth();
      auth.f4.liabilityHistory[301] = <Map<String, dynamic>>[_row(5, 301)];
      await _openTransfer(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_liability_preview')), findsOneWidget);
      expect(_has('finance_liability_history_5'), isTrue);
      expect(_has('finance_liability_transfer_button'), isFalse);
      expect(_has('finance_liability_reverse_5'), isFalse);
    });
  });

  group('devir penceresi: nedenli onay, iz, geri alma', () {
    testWidgets('onay: neden zorunlu; önizleme toplamı + özeti sunucuya gider; sonuç notu, geçmişte kayıt ve Geri Al; üst liste tazelenir', (t) async {
      final auth = _auth();
      var changed = 0;
      await _openTransfer(t, auth, onChanged: () => changed++);
      await _tap(t, 'finance_liability_transfer_button');
      expect(find.byKey(const ValueKey<String>('finance_reason_text')), findsOneWidget);
      expect(find.textContaining('2 borç kalemi, toplam 1.500,00 ₺'), findsOneWidget);

      // neden boş: gönderilmez
      await _tap(t, 'finance_reason_confirm');
      expect(find.text('Devir nedeni girin.'), findsOneWidget);
      expect(auth.f4.writes, isEmpty);

      await _approveWithReason(t, 'Kiracı taşındı, borç ödenmedi');
      final write = auth.f4.writes.single;
      expect(write['op'], 'createLiabilityTransfer');
      expect(write['apartment_id'], 301);
      expect(write['expected_total_minor'], 150000);
      expect(write['expected_hash'], 'c' * 64);
      expect(write['reason'], 'Kiracı taşındı, borç ödenmedi');
      expect((write['key'] as String).isNotEmpty, isTrue);
      expect(changed, 1);
      expect(_has('finance_reason_text'), isFalse, reason: 'başarıda onay penceresi kapanır');
      expect(find.textContaining('Borç malike devredildi: 1.500,00 ₺'), findsOneWidget);
      // yeniden okunan geçmiş: yeni kayıt, geri alınabilir; önizleme artık boş (devredilecek kalem kalmadı)
      expect(_has('finance_liability_history_1'), isTrue);
      expect(_has('finance_liability_reverse_1'), isTrue);
      expect(find.byKey(const ValueKey<String>('finance_liability_empty')), findsOneWidget);
    });

    testWidgets('bayat önizleme (409 LIABILITY_TRANSFER_CHANGED): hata onay penceresinde kalır, hiçbir şey yazılmaz; vazgeçince önizleme YENİDEN okunur', (t) async {
      final auth = _auth();
      auth.f4.liabilityCreateError = ApiException(
        'Kiracı borçları önizlemeden sonra değişti. Önizlemeyi yenileyip tekrar inceleyin.',
        statusCode: 409,
        code: 'LIABILITY_TRANSFER_CHANGED',
      );
      var changed = 0;
      await _openTransfer(t, auth, onChanged: () => changed++);
      await _tap(t, 'finance_liability_transfer_button');
      await _approveWithReason(t, 'Kiracı taşındı');
      expect(find.textContaining('önizlemeden sonra değişti'), findsOneWidget);
      expect(_has('finance_reason_text'), isTrue, reason: 'hata pencerede görünür, pencere açık kalır');
      expect(changed, 0);
      expect(auth.f4.callCount('previewLiabilityTransfer'), 1);

      await _tap(t, 'finance_reason_cancel');
      await settleFor(t);
      expect(auth.f4.callCount('previewLiabilityTransfer'), 2, reason: 'eskimiş önizleme otomatik yenilenir');
      expect(_has('finance_liability_history_1'), isFalse, reason: 'devir yazılmadı');
    });

    testWidgets('geri alma: Geri Al -> neden zorunlu -> ters kayıt; geçmişte "Geri alındı" ve geri alma kaydı; Geri Al düğmesi kalkar', (t) async {
      final auth = _auth();
      auth.f4.liabilityHistory[301] = <Map<String, dynamic>>[_row(7, 301)];
      var changed = 0;
      await _openTransfer(t, auth, onChanged: () => changed++);
      expect(_has('finance_liability_reverse_7'), isTrue);
      await _tap(t, 'finance_liability_reverse_7');
      expect(find.byKey(const ValueKey<String>('finance_reason_text')), findsOneWidget);
      await _tap(t, 'finance_reason_confirm');
      expect(find.text('Geri alma nedeni girin.'), findsOneWidget);
      expect(auth.f4.writes, isEmpty);

      await _approveWithReason(t, 'Yanlış daire');
      final write = auth.f4.writes.single;
      expect(write['op'], 'reverseLiabilityTransfer');
      expect(write['transfer_id'], 7);
      expect(write['reason'], 'Yanlış daire');
      expect(changed, 1);
      expect(find.text('Geri alındı'), findsOneWidget);
      expect(_has('finance_liability_reverse_7'), isFalse);
      expect(find.textContaining('Devir geri alındı.'), findsOneWidget);
      expect(find.textContaining('Geri alma • '), findsOneWidget, reason: 'geri alma ayrı bir kayıttır');
    });

    testWidgets('geri alınamayan devir: Geri Al çıkmaz, nedeni yazılır (ev sahibine ödeme girilmiş ya da kalemler başka devirle taşınmış)', (t) async {
      final auth = _auth();
      auth.f4.liabilityHistory[301] = <Map<String, dynamic>>[_row(9, 301, reversible: false)];
      await _openTransfer(t, auth);
      expect(_has('finance_liability_reverse_9'), isFalse);
      expect(find.byKey(const ValueKey<String>('finance_liability_stuck_9')), findsOneWidget);
      expect(find.textContaining('Bu devir artık geri alınamaz'), findsOneWidget);
    });

    testWidgets('geri alma reddedilirse (409) hata onay penceresinde görünür ve devir geçmişte olduğu gibi kalır', (t) async {
      final auth = _auth();
      auth.f4.liabilityHistory[301] = <Map<String, dynamic>>[_row(7, 301)];
      auth.f4.liabilityReverseError = ApiException(
        'Devirden sonra ev sahibi hesabına ödeme girilmiş; devir geri alınamaz.',
        statusCode: 409,
        code: 'LIABILITY_TRANSFER_OWNER_PAID',
      );
      await _openTransfer(t, auth);
      await _tap(t, 'finance_liability_reverse_7');
      await _approveWithReason(t, 'Yanlış daire');
      expect(find.textContaining('ev sahibi hesabına ödeme girilmiş'), findsOneWidget);
      expect(_has('finance_reason_text'), isTrue);
      await _tap(t, 'finance_reason_cancel');
      expect(find.text('Geri alındı'), findsNothing);
      expect(_has('finance_liability_reverse_7'), isTrue);
    });
  });

  group('aday listesi penceresi (K17)', () {
    testWidgets('daireler büyük tutar önce, neden rozeti ve toplam; daireye dokunmak devir penceresini açar; devirden sonra liste yenilenir ve daire düşer', (t) async {
      final auth = _auth();
      auth.f4.liabilityPreviews[302] = _preview(302);
      _setCandidates(auth.f4, <Map<String, dynamic>>[
        _candidate(301, unit: 'Daire 5'),
        _candidate(302, unit: 'Daire 6', reason: 'exited', total: 80000, items: 1),
      ]);
      var changed = 0;
      await _openCandidates(t, auth, onChanged: () => changed++);
      expect(find.text('2 daire'), findsOneWidget);
      expect(find.text('Toplam 2.300,00 ₺'), findsOneWidget);
      expect(find.text('Gecikmiş borç'), findsOneWidget);
      expect(find.text('Kiracı ayrıldı'), findsOneWidget);
      expect(find.text('A Blok / Daire 5'), findsOneWidget);
      expect(find.text('1.500,00 ₺'), findsOneWidget);

      await _tap(t, 'finance_liability_candidate_301');
      expect(find.text('Kiracı Borcunu Malike Devret'), findsOneWidget);
      await _tap(t, 'finance_liability_transfer_button');
      await _approveWithReason(t, 'Kiracı taşındı, borç ödenmedi');
      expect(auth.f4.writes.single['op'], 'createLiabilityTransfer');
      expect(changed, 1);

      // devir penceresini kapat -> aday listesi yeniden okunur; devredilen daire düşer
      await _tap(t, 'finance_liability_close');
      await settleFor(t);
      expect(_has('finance_liability_candidate_301'), isFalse);
      expect(_has('finance_liability_candidate_302'), isTrue);
      expect(find.text('1 daire'), findsOneWidget);
      expect(auth.f4.callCount('listLiabilityCandidates'), 2);
    });

    testWidgets('malik kaydı olmayan daire listelenir ama "Malik kaydı yok" ile işaretlenir ve nedeni yazılır', (t) async {
      final auth = _auth();
      _setCandidates(auth.f4, <Map<String, dynamic>>[_candidate(301, hasOwner: false)]);
      await _openCandidates(t, auth);
      expect(find.text('Malik kaydı yok'), findsOneWidget);
      expect(find.text('Devir için önce dairenin malik kaydını ekleyin.'), findsOneWidget);
    });

    testWidgets('liste kesilmişse açıkça yazılır; öneri yoksa bilgi notu; okunamazsa "öneri yok" DENMEZ', (t) async {
      final auth = _auth();
      _setCandidates(auth.f4, <Map<String, dynamic>>[_candidate(301)], truncated: true);
      await _openCandidates(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_liability_candidates_truncated')), findsOneWidget);
      await _tap(t, 'finance_liability_candidates_close');

      final empty = _auth();
      await _openCandidates(t, empty);
      expect(find.text('Malike devredilebilir gecikmiş kiracı borcu yok.'), findsOneWidget);
      await _tap(t, 'finance_liability_candidates_close');

      final broken = _auth();
      broken.f4.liabilityCandidatesError = ApiException('Devir önerileri yüklenemedi.', statusCode: 500, code: 'INTERNAL');
      await _openCandidates(t, broken);
      expect(find.byKey(const ValueKey<String>('finance_liability_candidates_error')), findsOneWidget);
      expect(find.text('Malike devredilebilir gecikmiş kiracı borcu yok.'), findsNothing);
    });
  });

  group('öneri şeridi (Daireler sekmesi)', () {
    Future<void> pumpBanner(WidgetTester t, FinanceFakeAuth auth, {bool canWrite = true, VoidCallback? onChanged}) async {
      await pumpAt(
        t,
        FinanceLiabilityBanner(scope: _scope(auth, canWrite: canWrite), onChanged: onChanged ?? () {}),
        width: 420,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await settleFor(t);
    }

    testWidgets('öneri varken sayı + toplam yazılır; Devri İncele aday listesini açar', (t) async {
      final auth = _auth();
      _setCandidates(auth.f4, <Map<String, dynamic>>[_candidate(301), _candidate(302, total: 50000)]);
      await pumpBanner(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_liability_banner')), findsOneWidget);
      expect(find.textContaining('2 dairede kiracının vadesi geçmiş'), findsOneWidget);
      expect(find.textContaining('toplam 2.000,00 ₺'), findsOneWidget);
      await _tap(t, 'finance_liability_banner_open');
      expect(find.text('Malike Devredilebilir Borçlar'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_liability_candidate_301')), findsOneWidget);
    });

    testWidgets('liste kesilmişse "En az N dairede" yazılır', (t) async {
      final auth = _auth();
      _setCandidates(auth.f4, <Map<String, dynamic>>[_candidate(301)], truncated: true);
      await pumpBanner(t, auth);
      expect(find.textContaining('En az 1 dairede'), findsOneWidget);
    });

    testWidgets('öneri yok / okunamıyor / kurul (salt okur): şerit çizilmez; kurulda öneri ucu hiç çağrılmaz', (t) async {
      final none = _auth();
      await pumpBanner(t, none);
      expect(_has('finance_liability_banner'), isFalse);

      final broken = _auth();
      _setCandidates(broken.f4, <Map<String, dynamic>>[_candidate(301)]);
      broken.f4.liabilityCandidatesError = ApiException('Devir önerileri yüklenemedi.', statusCode: 500, code: 'INTERNAL');
      await pumpBanner(t, broken);
      expect(_has('finance_liability_banner'), isFalse);

      final board = _auth();
      _setCandidates(board.f4, <Map<String, dynamic>>[_candidate(301)]);
      await pumpBanner(t, board, canWrite: false);
      expect(_has('finance_liability_banner'), isFalse);
      expect(board.f4.callCount('listLiabilityCandidates'), 0);
    });
  });

  group('hesap ekstresi düğmesi', () {
    Future<void> openAccount(WidgetTester t, FinanceFakeAuth auth, {int apartmentId = 301, bool canWrite = true}) async {
      await openDialogAt(
        t,
        (context) => FinanceAccountDialog.show(
          context,
          scope: _scope(auth, canWrite: canWrite),
          apartmentId: apartmentId,
          initialLabel: 'A Blok - 5',
          now: () => _now,
        ),
        width: 420,
        height: 2400,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await settleFor(t);
    }

    FinanceFakeAuth twoAccounts() {
      final auth = _auth();
      auth.twoAccountApartments.add(301);
      auth.currentTenantApartments.add(301);
      return auth;
    }

    testWidgets('kiracı hesabı olan dairede yöneticiye "Kiracı Borcunu Malike Devret" çıkar ve devir penceresini açar', (t) async {
      final auth = twoAccounts();
      await openAccount(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_account_liability_transfer')), findsOneWidget);
      await _tap(t, 'finance_account_liability_transfer');
      expect(find.byKey(const ValueKey<String>('finance_liability_preview')), findsOneWidget);
      expect(auth.f4.callCount('previewLiabilityTransfer'), 1);
    });

    testWidgets('tek hesaplı daire (kiracı hesabı yok) ve kurul üyesi için düğme YOK', (t) async {
      final single = twoAccounts();
      await openAccount(t, single, apartmentId: 302);
      expect(_has('finance_account_liability_transfer'), isFalse);

      final board = twoAccounts();
      await openAccount(t, board, canWrite: false);
      expect(_has('finance_account_liability_transfer'), isFalse);
    });
  });

  group('taşma matrisi', () {
    layoutMatrix('devir penceresi (önizleme + geçmiş + uzun neden)', (t, width, height, scale, dark) async {
      final auth = _auth();
      auth.f4.liabilityHistory[301] = <Map<String, dynamic>>[
        _row(3, 301, reason: 'Kiracı taşındı, borç aylardır ödenmedi; yönetim kurulu kararıyla ev sahibine devredilmesine karar verildi ve kayıt altına alındı.'),
        _row(2, 301, kind: 'reversal', reversible: false),
        _row(1, 301, reversible: false, reversedBy: 2),
      ];
      await _openTransfer(t, auth, width: width, height: height, scale: scale, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_liability_preview')), findsOneWidget);
      expect(_has('finance_liability_history_3'), isTrue);
    });

    layoutMatrix('aday listesi penceresi (kesilmiş liste, malikisiz daire)', (t, width, height, scale, dark) async {
      final auth = _auth();
      _setCandidates(
        auth.f4,
        <Map<String, dynamic>>[
          _candidate(301, unit: 'Daire 5'),
          _candidate(302, unit: 'Daire 6', reason: 'exited', total: 80000, items: 1, hasOwner: false),
          _candidate(303, unit: 'Çok uzun bir daire etiketi 12345', block: 'Güney Blok Kuzey Kanat', total: 123456789),
        ],
        truncated: true,
      );
      await _openCandidates(t, auth, width: width, height: height, scale: scale, dark: dark);
      expect(_has('finance_liability_candidate_303'), isTrue);
    });

    layoutMatrix('onay penceresi (devir nedeni)', (t, width, height, scale, dark) async {
      final auth = _auth();
      await _openTransfer(t, auth, width: width, height: height, scale: scale, dark: dark);
      await _tap(t, 'finance_liability_transfer_button');
      expect(_has('finance_reason_text'), isTrue);
    });
  });
}
