// Banka dosyası yükleme ekranı: C-26 "güçlü eşleşmeleri de tek tek gözden geçir" seçeneği + K3 özet satırı. Ağ yok: sahte API.
//  - Seçenek varsayılan KAPALI; işaretlenmeden commit gövdesine review_each girmez (eski davranış aynen).
//  - İşaretlenince özet "kendiliğinden işlenmeyecek" der; commit review_each=true ile gider.
//  - K3: özet, İşletme + Fon borcu birlikte açık olduğu için otomatik işlenmeyecek satır sayısını yazar.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/services/bank_statement_reader.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bank_import_view.dart';

import 'screens/finance_4b_fixtures.dart';
import 'screens/finance_fixtures.dart';

class _ImportApi extends BankImportApi {
  _ImportApi({this.fundChoice = 0}) : super(baseUrl: 'http://localhost');

  final int fundChoice;
  final int recognized = 2;
  final commits = <Map<String, Object?>>[];

  @override
  Future<List<BankImportItem>> listImports({required String token, required int siteCode}) async => const <BankImportItem>[];

  @override
  Future<int> attentionCount({required String token, required int siteCode}) async => 0;

  @override
  Future<BankPreview> preview({
    required String token,
    required int siteCode,
    required int accountId,
    required BankFile file,
    required List<BankLine> lines,
    String? accountIban,
  }) async => BankPreview.fromJson(<String, dynamic>{
    'preview_hash': 'a' * 64,
    'summary': <String, dynamic>{'recognized': recognized, 'check': fundChoice, 'recognized_minor': 250000, 'fund_choice': fundChoice},
    'warnings': <String>[],
    'lines': <Map<String, dynamic>>[
      <String, dynamic>{'n': 1, 'outcome': 'recognized', 'match': <String, dynamic>{'method': 'ref', 'apartment_label': 'A Blok - 3'}, 'warnings': <String>[]},
    ],
  });

  @override
  Future<BankCommitResult> commit({
    required String token,
    required int siteCode,
    required int accountId,
    required BankFile file,
    required List<BankLine> lines,
    required String previewHash,
    required String idempotencyKey,
    String? accountIban,
    bool reviewEach = false,
  }) async {
    commits.add(<String, Object?>{'review_each': reviewEach, 'hash': previewHash});
    return BankCommitResult(posted: reviewEach ? 0 : recognized, linked: 0, attention: reviewEach ? recognized : 0, replayed: false);
  }
}

const String _mt940 = ':20:A\n:25:TR330006100519786457841326\n:61:2610020102C10,00NTRFNONREF\n:86:GUL-A2 aidat\n';

Future<_ImportApi> _open(WidgetTester t, {int fundChoice = 0}) async {
  final auth = FinanceFakeAuth.seeded();
  auth.f4.accounts.add(f4AccountJson(2, 'Ziraat Bankası', kind: 'bank', balance: 1200000, opening: 1000000));
  final api = _ImportApi(fundChoice: fundChoice);
  BankImportService.register(auth, BankImportService(authService: auth, api: api, tokenProvider: () => 'tok'));
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final scope = PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül', canWrite: true);
  await t.pumpWidget(
    MaterialApp(
      home: BankImportView(
        scope: scope,
        initialAccountId: 2,
        pickFile: () async => PickedBulkFile(name: 'ekstre.sta', readBytes: () async => Uint8List.fromList(utf8.encode(_mt940))),
      ),
    ),
  );
  await t.pumpAndSettle();
  // dosya cihazda (isolate) ayrıştırılır: gerçek zaman gerekir
  await t.tap(find.byKey(const ValueKey<String>('bank_pick_file')));
  await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
  await t.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('seçenek varsayılan KAPALI: özet "işlenecek" der; commit review_each OLMADAN gider (alan yok)', (t) async {
    final api = await _open(t);
    expect(find.byKey(const ValueKey<String>('bank_review_each_check')), findsOneWidget);
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey<String>('bank_review_each_check'))).value, isFalse);
    expect(find.text('Tanınan 2 satır (2.500,00 ₺) işlenecek'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('bank_commit')));
    await t.pumpAndSettle();
    expect(api.commits.single['review_each'], isFalse);
    expect(find.byKey(const ValueKey<String>('bank_done')), findsOneWidget);
    expect(find.textContaining('2 tahsilat işlendi'), findsOneWidget);
  });

  testWidgets('işaretlenince özet "kendiliğinden işlenmeyecek" der ve commit review_each=true ile gider; sonuç satırlar sizi bekliyor', (t) async {
    final api = await _open(t);
    await t.tap(find.byKey(const ValueKey<String>('bank_review_each_check')));
    await t.pumpAndSettle();
    expect(find.text('Tanınan 2 satır (2.500,00 ₺) kendiliğinden işlenmeyecek; tek tek onayınızı bekleyecek'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('bank_commit')));
    await t.pumpAndSettle();
    expect(api.commits.single['review_each'], isTrue);
    expect(find.textContaining('0 tahsilat işlendi'), findsOneWidget);
    expect(find.textContaining('2 satır sizi bekliyor'), findsOneWidget);
  });

  testWidgets('K3: İşletme + Fon borcu birlikte açık olduğu için otomatik işlenmeyecek satır sayısı özette yazılır', (t) async {
    await _open(t, fundChoice: 1);
    expect(find.textContaining('1 satırda dairenin İşletme ve Fon borcu birlikte açık: kendiliğinden işlenmez'), findsOneWidget);
  });

  testWidgets('K3 özet satırı borçlu daire yoksa görünmez', (t) async {
    await _open(t);
    expect(find.textContaining('İşletme ve Fon borcu birlikte açık'), findsNothing);
  });
}
