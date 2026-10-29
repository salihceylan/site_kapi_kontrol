// Süper kullanıcı site kartı: "Hukuk onayı" anahtarı (Dalga K, sunucu: GET/PUT /admin/sites/:siteCode/finance-legal-gate).
//
// Anahtar YALNIZ süper kullanıcıda (ve hizmet verilince) görünür; kart açılınca GET ile durum okunur; değişiklik
// "Avukat onayı alındı mı?" onayından sonra PUT ile kaydedilir; vazgeçilirse PUT gitmez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_card.dart';

import 'list_fixtures.dart';

class _LegalAuth extends AuthService {
  _LegalAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));
}

class _FakeLegalGateApi extends Finance4bApi {
  _FakeLegalGateApi() : super(baseUrl: 'http://localhost');

  bool legalOk = false;
  final List<int> gets = <int>[];
  final List<({int siteCode, bool enabled})> puts = <({int siteCode, bool enabled})>[];

  @override
  Future<bool> getSiteLegalGate({required String token, required int siteCode}) async {
    gets.add(siteCode);
    return legalOk;
  }

  @override
  Future<bool> setSiteLegalGate({required String token, required int siteCode, required bool enabled}) async {
    puts.add((siteCode: siteCode, enabled: enabled));
    legalOk = enabled;
    return legalOk;
  }
}

Finance4bService _service(_FakeLegalGateApi api) =>
    Finance4bService(authService: _LegalAuth(), api: api, tokenProvider: () => 'test-token');

Future<void> _pumpCard(
  WidgetTester t, {
  required bool isSuperUser,
  Finance4bService? service,
}) async {
  await pumpList(
    t,
    SiteCard(
      site: fxSite(),
      selected: false,
      formattedCreatedAt: '01.10.2026 12:30',
      deleteBusy: false,
      approvalBusy: false,
      onTap: () {},
      isSuperUser: isSuperUser,
      legalGateService: service,
    ),
    width: 412,
    height: 900,
    scale: 1.0,
    dark: false,
  );
  await tapText(t, 'Yeşilvadi Sitesi'); // Kartı açar (detay bölümü).
}

void main() {
  const gateKey = ValueKey<String>('site_hukuk_onayi_anahtari');

  testWidgets('Anahtar yalnız süper kullanıcıda görünür; süper değilken ya da hizmet yokken GET bile gitmez', (t) async {
    final api = _FakeLegalGateApi();

    await _pumpCard(t, isSuperUser: false, service: _service(api));
    expect(find.byKey(gateKey), findsNothing);
    expect(find.text('Hukuk onayı (gecikme tazminatı/borç hatırlatma)'), findsNothing);

    await _pumpCard(t, isSuperUser: true);
    expect(find.byKey(gateKey), findsNothing);
    expect(api.gets, isEmpty);

    await _pumpCard(t, isSuperUser: true, service: _service(api));
    await t.pump();
    expect(find.byKey(gateKey), findsOneWidget);
    expect(find.text('Hukuk onayı (gecikme tazminatı/borç hatırlatma)'), findsOneWidget);
    expect(api.gets, <int>[fxSite().id]);
    expect(t.widget<SwitchListTile>(find.byKey(gateKey)).value, isFalse);
    expect(find.textContaining('Kapalı:'), findsOneWidget);
  });

  testWidgets('Açma: onay penceresi, Evet sonrası PUT(true) ve anahtar açılır; Vazgeç PUT göndermez', (t) async {
    final api = _FakeLegalGateApi();
    await _pumpCard(t, isSuperUser: true, service: _service(api));
    await t.pump();

    // Vazgeç: PUT yok, anahtar kapalı kalır.
    await t.ensureVisible(find.byKey(gateKey));
    await t.tap(find.byKey(gateKey));
    await t.pumpAndSettle();
    expect(find.text('Hukuk onayı açılsın mı?'), findsOneWidget);
    expect(find.textContaining('Avukat onayı alındı mı?'), findsOneWidget);
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(api.puts, isEmpty);
    expect(t.widget<SwitchListTile>(find.byKey(gateKey)).value, isFalse);

    // Onay: PUT(true) sahte servise gider, anahtar açılır, başarı bildirimi çıkar.
    await t.tap(find.byKey(gateKey));
    await t.pumpAndSettle();
    await t.tap(find.text('Evet, onay alındı'));
    await t.pumpAndSettle();
    expect(api.puts, <({int siteCode, bool enabled})>[(siteCode: fxSite().id, enabled: true)]);
    expect(t.widget<SwitchListTile>(find.byKey(gateKey)).value, isTrue);
    expect(find.text('Hukuk onayı açıldı.'), findsOneWidget);
    expect(find.textContaining('Açık:'), findsOneWidget);
  });
}
