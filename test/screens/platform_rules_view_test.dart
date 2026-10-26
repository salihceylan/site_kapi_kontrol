// "Kurallar" sayfası (PlatformRulesScreen) ve "Kuralı değiştir" penceresi (PlatformRuleDialog): süper kullanıcı (platform geneli ve site kapsamı),
// site yöneticisi (salt okunur), düzenleme akışı (doğrulama, çift kural, tarih, sunucu reddi, üst düzeye dön), yükleme hatası, taşma matrisi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/platform_rule.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/platform_rules_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/platform_rule_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/platform_rules_view.dart';

import '../fixtures/platform_rules_fixtures.dart';

class _Auth extends AuthService {
  _Auth(this.role) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;

  @override
  UserSession? get session => UserSession(id: 1, fullName: 'Süper Kişi', email: 's@x.com', loginName: null, role: role, isActive: true, token: 'tok');
}

typedef _Update = ({List<PlatformRuleChange> changes, int? siteCode, String? validFrom, String? note});

class _FakeRules extends PlatformRulesService {
  _FakeRules({UserRole role = UserRole.superUser}) : super(authService: _Auth(role), api: PlatformRulesApi(baseUrl: 'http://localhost'));

  final List<int?> adminCalls = <int?>[];
  final List<int> siteCalls = <int>[];
  final List<_Update> updates = <_Update>[];
  Object? failList;
  Object? failUpdate;
  int lateFeeMax = 400;

  /// Verilirse yazma yanıtı bu tamamlanana dek bekler (kayıt sürerken davranış).
  Completer<void>? holdUpdate;

  Map<String, dynamic> _json({int? siteCode, required bool canEdit}) =>
      prRulesJson(siteCode: siteCode, siteName: siteCode == null ? null : 'Gül Sitesi', canEdit: canEdit, lateFeeMax: lateFeeMax);

  @override
  Future<PlatformRulesView> listAdmin({int? siteCode}) async {
    adminCalls.add(siteCode);
    if (failList != null) throw failList!;
    return PlatformRulesView.fromJson(_json(siteCode: siteCode, canEdit: true));
  }

  @override
  Future<PlatformRulesView> listForSite(int siteCode) async {
    siteCalls.add(siteCode);
    if (failList != null) throw failList!;
    return PlatformRulesView.fromJson(_json(siteCode: siteCode, canEdit: false));
  }

  @override
  Future<PlatformRulesView> update({required List<PlatformRuleChange> changes, int? siteCode, String? validFrom, String? note}) async {
    updates.add((changes: changes, siteCode: siteCode, validFrom: validFrom, note: note));
    if (holdUpdate != null) await holdUpdate!.future;
    if (failUpdate != null) throw failUpdate!;
    final late = changes.where((c) => c.key == 'finance.late_fee.monthly_bp_max');
    if (late.isNotEmpty && late.first.value is int) lateFeeMax = late.first.value! as int;
    return PlatformRulesView.fromJson(<String, dynamic>{
      ..._json(siteCode: siteCode, canEdit: true),
      'changed': <String>[for (final c in changes) c.key],
    });
  }
}

Future<_FakeRules> _pump(
  WidgetTester t, {
  _FakeRules? fake,
  bool canEdit = true,
  int? siteCode,
  double width = 420,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  final rules = fake ?? _FakeRules(role: canEdit ? UserRole.superUser : UserRole.siteManager);
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: PlatformRulesScreen(authService: rules.authService, service: rules, canEdit: canEdit, siteCode: siteCode, siteName: siteCode == null ? null : 'Gül Sitesi'),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  return rules;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _card(String key) => find.byKey(ValueKey<String>('rule_$key'));
Finder _value(String key) => find.byKey(ValueKey<String>('rule_value_$key'));
String? _valueText(WidgetTester t, String key) => t.widget<Text>(_value(key)).data;
Finder _edit(String key) => find.byKey(ValueKey<String>('rule_edit_$key'));
Finder _inDialog(Finder f) => find.descendant(of: find.byType(AppDialog), matching: f);
const Key _dialogValue = ValueKey<String>('rule_dialog_value');
const Key _dialogSave = ValueKey<String>('rule_dialog_save');

Future<void> _openEdit(WidgetTester t, String key) async {
  await t.scrollUntilVisible(_edit(key), 300, scrollable: find.byType(Scrollable).first);
  await t.pump();
  await t.tap(_edit(key));
  await _settle(t);
  expect(find.byType(PlatformRuleDialog), findsOneWidget);
}

Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(find.byKey(_dialogSave));
  await t.pump();
  await t.tap(find.byKey(_dialogSave));
  await _settle(t);
}

String _text(WidgetTester t, Key key) =>
    t.widget<TextField>(find.descendant(of: find.byKey(key), matching: find.byType(TextField))).controller!.text;

void main() {
  group('süper kullanıcı, platform geneli', () {
    testWidgets('kapsam kartı, 5 grup, değer + kaynak, sınır, varsayılan, değiştiren ve not, planlı değer, kilitli kural, 14 "Değiştir"', (t) async {
      final rules = await _pump(t);
      expect(rules.adminCalls, <int?>[null]);
      expect(find.text('Kurallar'), findsOneWidget, reason: 'sayfa başlığı');
      expect(find.text('Platform geneli'), findsOneWidget);
      expect(find.textContaining('Yasal üst sınırlar'), findsOneWidget);
      expect(_valueText(t, 'finance.late_fee.monthly_bp_max'), '%4,00');
      final late = _card('finance.late_fee.monthly_bp_max');
      for (final text in <String>['Platform değeri', 'Sınır: %0,00 ile %5,00 arasında', 'Varsayılan: %5,00', '21.10.2026 tarihinden beri geçerli', 'Son değiştiren: Süper Kişi (21.10.2026)', 'Not: Kurul kararı']) {
        expect(find.descendant(of: late, matching: find.text(text)), findsOneWidget, reason: text);
      }
      expect(find.descendant(of: late, matching: find.textContaining('Mevzuat notu: KMK 634')), findsOneWidget);
      for (final group in <String>['Finans', 'İşletme projesi (bütçe)', 'Isınma gideri payı', 'Gelecek yıl tahmini', 'Saklama süreleri']) {
        await t.scrollUntilVisible(find.text(group), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text(group), findsOneWidget, reason: group);
      }
      await t.scrollUntilVisible(_card('budget.objection_days'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: _card('budget.objection_days'), matching: find.text('Planlı: 20.11.2026 tarihinden itibaren 10 gün')), findsOneWidget);
      await t.scrollUntilVisible(_card('retention.enforce'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: _card('retention.enforce'), matching: find.textContaining('avukat onayına kadar')), findsOneWidget);
      expect(_edit('retention.enforce'), findsNothing, reason: 'kilitli kural değiştirilemez');
      expect(_valueText(t, 'retention.decision_book_days'), 'Süresiz');
      expect(_valueText(t, 'retention.enforce'), 'Kapalı');
      var editButtons = 0;
      for (final key in <String>[
        'finance.late_fee.monthly_bp_max', 'budget.provisional_max_days', 'budget.objection_days', 'heat.measured_share_pct', 'heat.area_share_pct',
        'forecast.default_increase_bp', 'retention.finance_days', 'retention.contact_after_moveout_days', 'retention.door_logs_days', 'retention.visitor_logs_days',
        'retention.work_photos_after_close_days', 'retention.announcements_days', 'retention.audit_days', 'retention.decision_book_days',
      ]) {
        await t.scrollUntilVisible(_card(key), 300, scrollable: find.byType(Scrollable).first);
        if (_edit(key).evaluate().isNotEmpty) editButtons++;
      }
      expect(editButtons, 14);
    });

    testWidgets('gecikme üst sınırı: sınır dışı değer kaydedilmez; geçerli değer (yüzde metni) baz puan olarak gider, tarih yok (planlanamaz), kart ve bildirim güncellenir', (t) async {
      final rules = await _pump(t);
      await _openEdit(t, 'finance.late_fee.monthly_bp_max');
      expect(_inDialog(find.text('Gecikme tazminatı aylık üst sınırı')), findsOneWidget);
      expect(_text(t, _dialogValue), '4,00');
      expect(find.byKey(const ValueKey<String>('rule_dialog_date')), findsNothing);
      expect(_inDialog(find.textContaining('bugünden geçerli olur')), findsOneWidget);
      expect(_inDialog(find.textContaining('bu sınırı aşamaz')), findsOneWidget);
      await t.enterText(find.byKey(_dialogValue), '6');
      await _save(t);
      expect(_inDialog(find.text('Değer %0,00 ile %5,00 arasında olmalıdır.')), findsOneWidget);
      expect(rules.updates, isEmpty);
      await t.enterText(find.byKey(_dialogValue), '3,5');
      await t.enterText(find.byKey(const ValueKey<String>('rule_dialog_note')), '  Kurul kararı 12  ');
      await _save(t);
      expect(rules.updates, hasLength(1));
      final update = rules.updates.single;
      expect(update.changes.map((c) => c.toJson()).toList(), <Map<String, Object?>>[<String, Object?>{'key': 'finance.late_fee.monthly_bp_max', 'value': 350}]);
      expect(update.siteCode, isNull);
      expect(update.validFrom, isNull);
      expect(update.note, 'Kurul kararı 12');
      expect(find.byType(PlatformRuleDialog), findsNothing);
      expect(_valueText(t, 'finance.late_fee.monthly_bp_max'), '%3,50');
      expect(find.text('Kural kaydedildi.'), findsOneWidget);
    });

    testWidgets('ısı payı çifti: eşin değeri toplamdan hesaplanır ve BİRLİKTE gönderilir; ileri tarih YYYY-AA-GG olarak gider; geçmiş tarih reddedilir', (t) async {
      final rules = await _pump(t);
      await _openEdit(t, 'heat.measured_share_pct');
      await t.enterText(find.byKey(_dialogValue), '60');
      await t.pump();
      expect(_inDialog(find.text('Isınma gideri: alan payı: %40 (toplam 100).')), findsOneWidget);
      final date = find.byKey(const ValueKey<String>('rule_dialog_date'));
      expect(_text(t, const ValueKey<String>('rule_dialog_date')), '21.10.2026');
      await t.enterText(date, '20.10.2026');
      await _save(t);
      expect(_inDialog(find.text('Geçerlilik tarihi bugünden önce olamaz.')), findsOneWidget);
      expect(rules.updates, isEmpty);
      await t.enterText(date, '01.12.2026');
      await _save(t);
      final update = rules.updates.single;
      expect(update.changes.map((c) => c.toJson()).toList(), <Map<String, Object?>>[
        <String, Object?>{'key': 'heat.measured_share_pct', 'value': 60},
        <String, Object?>{'key': 'heat.area_share_pct', 'value': 40},
      ]);
      expect(update.validFrom, '2026-12-01');
    });

    testWidgets('sunucu reddi (VALIDATION_FAILED) pencerede kuralın alan metniyle gösterilir; pencere açık kalır, değer korunur', (t) async {
      final rules = await _pump(t)
        ..failUpdate = ApiException(
          'Bazı kurallar geçersiz.',
          statusCode: 400,
          code: 'VALIDATION_FAILED',
          payload: <String, dynamic>{
            'fields': <String, String>{'budget.objection_days': 'İşletme projesine itiraz süresi: 1 ile 30 arasında bir tam sayı olmalıdır (gün).'},
          },
        );
      await _openEdit(t, 'budget.objection_days');
      await t.enterText(find.byKey(_dialogValue), '9');
      await _save(t);
      expect(rules.updates, hasLength(1));
      expect(find.byType(PlatformRuleDialog), findsOneWidget);
      expect(_inDialog(find.text('İşletme projesine itiraz süresi: 1 ile 30 arasında bir tam sayı olmalıdır (gün).')), findsOneWidget);
      expect(_text(t, _dialogValue), '9');
      await t.tap(find.byKey(const ValueKey<String>('rule_dialog_cancel')));
      await _settle(t);
      expect(find.byType(PlatformRuleDialog), findsNothing);
    });

    testWidgets('kayıt sürerken geri tuşu pencereyi KAPATMAZ (sonuç kaybolmaz); yanıt gelince pencere kapanır ve kart güncellenir', (t) async {
      final rules = await _pump(t);
      final pending = Completer<void>();
      rules.holdUpdate = pending;
      await _openEdit(t, 'finance.late_fee.monthly_bp_max');
      await t.enterText(find.byKey(_dialogValue), '3');
      await t.ensureVisible(find.byKey(_dialogSave));
      await t.pump();
      await t.tap(find.byKey(_dialogSave));
      await t.pump();
      expect(rules.updates, hasLength(1), reason: 'istek gönderildi, yanıt bekleniyor');
      await t.binding.handlePopRoute();
      await _settle(t);
      expect(find.byType(PlatformRuleDialog), findsOneWidget, reason: 'kayıt sürerken geri tuşu pencereyi kapatmamalı');
      pending.complete();
      await _settle(t);
      expect(find.byType(PlatformRuleDialog), findsNothing);
      expect(_valueText(t, 'finance.late_fee.monthly_bp_max'), '%3,00');
      expect(find.text('Kural kaydedildi.'), findsOneWidget);
    });

    testWidgets('süresiz kural: "Süresiz" anahtarı açıkken değer alanı kapalı ve null değer gider', (t) async {
      final rules = await _pump(t);
      await _openEdit(t, 'retention.decision_book_days');
      final field = t.widget<TextField>(find.descendant(of: find.byKey(_dialogValue), matching: find.byType(TextField)));
      expect(field.enabled, isFalse, reason: 'şu an süresiz');
      await _save(t);
      expect(rules.updates.single.changes.single.toJson(), <String, Object?>{'key': 'retention.decision_book_days', 'value': null});
    });
  });

  group('süper kullanıcı, site kapsamı', () {
    testWidgets('admin ucu site koduyla; sitede değişemeyen kural "Platform genelinden değiştirilir"; siteye özel değer ve "Platform değerini kullan"', (t) async {
      final rules = await _pump(t, siteCode: 11);
      expect(rules.adminCalls, <int?>[11]);
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(_edit('finance.late_fee.monthly_bp_max'), findsNothing);
      expect(find.byKey(const ValueKey<String>('rule_platform_only_finance.late_fee.monthly_bp_max')), findsOneWidget);
      await t.scrollUntilVisible(_card('forecast.default_increase_bp'), 300, scrollable: find.byType(Scrollable).first);
      final forecast = _card('forecast.default_increase_bp');
      expect(find.descendant(of: forecast, matching: find.text('%25,00')), findsOneWidget);
      expect(find.descendant(of: forecast, matching: find.text('Bu siteye özel')), findsOneWidget);
      expect(find.descendant(of: forecast, matching: find.text('Platform değeri: %0,00')), findsOneWidget);
      await _openEdit(t, 'forecast.default_increase_bp');
      expect(_inDialog(find.text('Site: Gül Sitesi')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('rule_dialog_inherit')));
      await t.pump();
      await _save(t);
      final update = rules.updates.single;
      expect(update.siteCode, 11);
      expect(update.changes.single.toJson(), <String, Object?>{'key': 'forecast.default_increase_bp', 'inherit': true});
    });
  });

  group('site yöneticisi', () {
    testWidgets('salt okunur: site ucu, "Değiştir" yok, değiştirenin adı yok, açıklama yöneticiye göre', (t) async {
      final rules = await _pump(t, canEdit: false, siteCode: 11);
      expect(rules.siteCalls, <int>[11]);
      expect(rules.adminCalls, isEmpty);
      expect(find.textContaining('yalnızca sistem yöneticisi değiştirebilir'), findsOneWidget);
      expect(find.text('Değiştir'), findsNothing);
      expect(find.textContaining('Son değiştiren'), findsNothing);
      expect(find.byKey(const ValueKey<String>('rule_platform_only_finance.late_fee.monthly_bp_max')), findsNothing);
      expect(_valueText(t, 'finance.late_fee.monthly_bp_max'), '%4,00');
    });

    testWidgets('site görünümünde planlı PLATFORM değeri kapsamıyla yazılır ("platform geneli"); platform görünümünde ek yok', (t) async {
      await _pump(t, canEdit: false, siteCode: 11);
      await t.scrollUntilVisible(_card('budget.objection_days'), 300, scrollable: find.byType(Scrollable).first);
      expect(
        find.descendant(of: _card('budget.objection_days'), matching: find.text('Planlı: 20.11.2026 tarihinden itibaren 10 gün (platform geneli)')),
        findsOneWidget,
      );
    });
  });

  group('yükleme hatası', () {
    testWidgets('hata "kural yok" demez: ileti + Tekrar Dene; yeniden denemede liste gelir', (t) async {
      final fake = _FakeRules()..failList = ApiException('Kurallar yüklenemedi.', statusCode: 500);
      await _pump(t, fake: fake);
      expect(find.byKey(const ValueKey<String>('rules_load_error')), findsOneWidget);
      expect(find.text('Kurallar yüklenemedi.'), findsOneWidget);
      expect(_card('finance.late_fee.monthly_bp_max'), findsNothing);
      fake.failList = null;
      await t.tap(find.text('Tekrar Dene'));
      await _settle(t);
      expect(_card('finance.late_fee.monthly_bp_max'), findsOneWidget);
      expect(fake.adminCalls, hasLength(2));
    });
  });

  group('taşma matrisi', () {
    for (final (width, height, scale) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('sayfa ve pencere ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: taşma yok', (t) async {
          await _pump(t, width: width, height: height, scale: scale, dark: dark);
          await t.scrollUntilVisible(_card('retention.enforce'), 400, scrollable: find.byType(Scrollable).first);
          expect(t.takeException(), isNull);
          await t.scrollUntilVisible(_card('heat.measured_share_pct'), -400, scrollable: find.byType(Scrollable).first);
          await _openEdit(t, 'heat.measured_share_pct');
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}
