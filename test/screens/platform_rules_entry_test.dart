// "Kurallar" giriş kartı (PlatformRulesEntryCard): Platform Ayarları (süper kullanıcı, platform geneli, değiştirir) ve Modüller (seçili site; yönetici salt
// okunur, süper kullanıcı siteye özel) ekranlarında görünür, ağ isteği yapmaz, dokununca kurallar sayfasını doğru uçla açar; dar ekranda taşmaz.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/platform_rules_api.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/views/platform_rules_view.dart';
import 'package:site_kapi_kontrol/ui/views/platform_settings_view.dart';

import '../fixtures/platform_rules_fixtures.dart';
import 'account_fixtures.dart';
import 'list_fixtures.dart';
import 'modules_fixtures.dart';

const Key _entry = ValueKey<String>('platform_rules_entry');
const Key _open = ValueKey<String>('platform_rules_open');

/// Kurallar sayfasının kendi kurduğu servise sahte HTTP istemcisi verir; gelen istekleri kaydeder.
List<Uri> _installRulesApi() {
  final seen = <Uri>[];
  PlatformRulesService.debugApiFactory = (auth) => PlatformRulesApi(
    baseUrl: 'http://localhost',
    client: MockClient((request) async {
      seen.add(request.url);
      final siteCode = request.url.pathSegments.length > 2 && request.url.pathSegments[0] == 'manager'
          ? int.parse(request.url.pathSegments[2])
          : int.tryParse(request.url.queryParameters['site_code'] ?? '');
      final body = prRulesJson(siteCode: siteCode, siteName: siteCode == null ? null : 'Gül Sitesi', canEdit: request.url.path.startsWith('/admin'));
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});
    }),
  );
  addTearDown(() => PlatformRulesService.debugApiFactory = null);
  return seen;
}

Future<void> _tapOpen(WidgetTester t) async {
  await t.ensureVisible(find.byKey(_open));
  await t.pump();
  await t.tap(find.byKey(_open));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Platform Ayarları (süper kullanıcı)', () {
    testWidgets('kart görünür, ağ isteği yapmaz; "Kuralları Aç" platform geneli kurallar sayfasını (admin ucu, site yok) açar', (t) async {
      final seen = _installRulesApi();
      final h = AccountHarness(role: UserRole.superUser);
      h.api.config = acConfig();
      await pumpList(
        t,
        PlatformSettingsView(authService: h.auth, service: h.service, onSaved: () async {}, installedVersion: () async => '1.2.0'),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(_entry), findsOneWidget);
      expect(find.text('Kuralları Aç'), findsOneWidget);
      expect(find.textContaining('denetim kaydına yazılır'), findsOneWidget);
      expect(seen, isEmpty, reason: 'kart kendi başına istek yapmaz');
      expect(find.text('Uygulama Sürümü ve Bakım'), findsOneWidget, reason: 'mevcut form yerinde');
      await _tapOpen(t);
      expect(find.byType(PlatformRulesScreen), findsOneWidget);
      expect(seen.map((u) => u.toString()), <String>['http://localhost/admin/rules']);
      expect(find.text('Platform geneli'), findsOneWidget);
    });

    for (final (width, height, scale) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('kart ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: taşma yok', (t) async {
          final h = AccountHarness(role: UserRole.superUser);
          h.api.config = acConfig();
          await pumpList(
            t,
            PlatformSettingsView(authService: h.auth, service: h.service, onSaved: () async {}, installedVersion: () async => '1.2.0'),
            width: width,
            height: height,
            scale: scale,
            dark: dark,
          );
          await t.pump(const Duration(milliseconds: 100));
          await t.ensureVisible(find.byKey(_open));
          await t.pump();
          expect(find.byKey(_entry), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('Modüller (seçili site)', () {
    Future<ModulesFakeAuth> pumpModules(WidgetTester t, UserRole role, {double width = 400, double height = 1400, double scale = 1.0, bool dark = false}) async {
      final auth = ModulesFakeAuth(
        fixtureRole: role,
        states: {11: mdState(11, 'Gül Sitesi', superView: role == UserRole.superUser), 12: mdState(12, 'Mavi Park', superView: role == UserRole.superUser)},
      );
      await pumpList(t, ModulesView(authService: auth), width: width, height: height, scale: scale, dark: dark);
      await t.pump();
      await t.pump();
      return auth;
    }

    testWidgets('site yöneticisi: "Kuralları Görüntüle" seçili sitenin salt okunur kurallarını yönetici ucuyla açar', (t) async {
      final seen = _installRulesApi();
      await pumpModules(t, UserRole.siteManager);
      expect(find.byKey(_entry), findsOneWidget);
      expect(find.text('Kuralları Görüntüle'), findsOneWidget);
      expect(find.textContaining('Yalnızca görüntülenir'), findsOneWidget);
      expect(seen, isEmpty);
      await _tapOpen(t);
      expect(seen.map((u) => u.path), <String>['/manager/sites/11/rules']);
      expect(find.text('Değiştir'), findsNothing);
      expect(find.textContaining('yalnızca sistem yöneticisi değiştirebilir'), findsOneWidget);
    });

    testWidgets('süper kullanıcı: "Kuralları Aç" seçili sitenin site görünümünü admin ucuyla açar (siteye özel değer)', (t) async {
      final seen = _installRulesApi();
      await pumpModules(t, UserRole.superUser);
      expect(find.text('Kuralları Aç'), findsOneWidget);
      await _tapOpen(t);
      expect(seen.map((u) => u.toString()), <String>['http://localhost/admin/rules?site_code=11']);
      expect(find.byKey(const ValueKey<String>('rule_edit_forecast.default_increase_bp')), findsOneWidget);
    });

    testWidgets('320x640 x2,0 koyu: Modüller ekranının sonundaki kart taşmaz', (t) async {
      await pumpModules(t, UserRole.siteManager, width: 320, height: 640, scale: 2.0, dark: true);
      await t.ensureVisible(find.byKey(_open));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
