// "Platform Ayarları" ekranı (PlatformSettingsView, yalnız süper kullanıcı): GET/PUT /admin/platform-config.
//
// Taşma matrisi (320x640 x2,0, 360x640 x1,5, yatay, tablet; açık + koyu), yükleniyor / hata / dolu durumlar,
// KISMİ güncelleme (yalnız değişen alanlar), alan doğrulaması, riskli değişiklik onayı, kaydedilmemiş değişiklik
// uyarısı, sunucu alan hataları, çift gönderim kilidi, hız sınırı, klavye.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/account_platform_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/views/platform_settings_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'account_fixtures.dart';
import 'dialog_layout_harness.dart';
import 'list_fixtures.dart';

const Key _save = ValueKey<String>('platform_save');
const Key _revert = ValueKey<String>('platform_revert');
const Key _dirty = ValueKey<String>('platform_dirty_notice');
const Key _saved = ValueKey<String>('platform_saved_notice');
const Key _maintenance = ValueKey<String>('platform_maintenance_switch');
const Key _enforce = ValueKey<String>('platform_enforce_switch');

Key _f(String name) => ValueKey<String>('platform_$name');

class _Ctx {
  _Ctx(this.h, this.key, this.saved);

  final AccountHarness h;
  final GlobalKey<PlatformSettingsViewState> key;
  final List<int> saved;

  PlatformSettingsViewState get state => key.currentState!;
}

/// Kurulu uygulama sürümü sahtesi (varsayılan 1.2.0: örnek yapılandırmanın son sürümüyle aynı).
Future<String?> Function() _installedAs(String? version) => () async => version;

Future<_Ctx> _pump(
  WidgetTester t, {
  AccountHarness? harness,
  PlatformConfig? config,
  Future<String?> Function()? installed,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  final h = harness ?? AccountHarness(role: UserRole.superUser);
  h.api.config = config ?? acConfig();
  final key = GlobalKey<PlatformSettingsViewState>();
  final saved = <int>[];
  await pumpList(
    t,
    PlatformSettingsView(
      key: key,
      authService: h.auth,
      service: h.service,
      onSaved: () async => saved.add(1),
      installedVersion: installed ?? _installedAs('1.2.0'),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  return _Ctx(h, key, saved);
}

Future<void> _enter(WidgetTester t, String field, String text) async {
  await t.ensureVisible(find.byKey(_f(field)));
  await t.pump();
  await t.enterText(find.byKey(_f(field)), text);
  await t.pump();
}

String _text(WidgetTester t, String field) =>
    t.widget<TextField>(find.descendant(of: find.byKey(_f(field)), matching: find.byType(TextField))).controller!.text;

Future<void> _tapSave(WidgetTester t) async {
  await t.ensureVisible(find.byKey(_save));
  await t.pump();
  await t.tap(find.byKey(_save));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _tapSwitch(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pump();
  await t.tap(find.byKey(key));
  await t.pump();
}

bool _saveEnabled(WidgetTester t) => t.widget<PrimaryActionButton>(find.byKey(_save)).onPressed != null;

Finder _dialogButton(String label) => find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

void main() {
  group('taşma matrisi', () {
    accountLayoutMatrix('dolu form: üç bölüm, alanlar, anahtarlar, kaydet', (t, w, h, s, dark) async {
      await _pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Platform Ayarları'), findsOneWidget);
      expect(find.text('Uygulama Sürümü ve Bakım'), findsOneWidget);
      expect(find.text('Destek İletişim'), findsOneWidget);
      expect(find.text('Şirket ve Yasal Bilgiler'), findsOneWidget);
      expect(find.byKey(_f('latest_version')), findsOneWidget);
      expect(find.byKey(_f('contact_phone')), findsOneWidget);
      expect(find.byKey(_enforce), findsOneWidget);
      expect(find.byKey(_save), findsOneWidget);
    });

    accountLayoutMatrix('kaydedilmemiş değişiklik uyarısı + hatalı alanlar + özet', (t, w, h, s, dark) async {
      await _pump(t, width: w, height: h, scale: s, dark: dark);
      await _enter(t, 'latest_version', '1.2');
      await _enter(t, 'update_url_android', 'http://play.google.com');
      await _enter(t, 'email', 'gecersiz');
      await _enter(t, 'contact_phone', '123');
      await _tapSave(t);
      await settleFor(t);
      expect(find.byKey(_dirty), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.textContaining('1.2.3 biçiminde olmalı'), findsOneWidget);
    });

    accountLayoutMatrix('yükleniyor: iskelet, form yok', (t, w, h, s, dark) async {
      final harness = AccountHarness(role: UserRole.superUser)..api.configGate = Completer<void>();
      await _pump(t, harness: harness, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byKey(_save), findsNothing);
      expect(find.byKey(_f('latest_version')), findsNothing);
    });

    accountLayoutMatrix('hata: form ÇİZİLMEZ (boş alanlar "ayarsız" gibi görünmesin), Tekrar Dene', (t, w, h, s, dark) async {
      final harness = AccountHarness(role: UserRole.superUser)
        ..api.configError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _pump(t, harness: harness, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(_f('latest_version')), findsNothing);
      expect(find.byKey(_save), findsNothing);
      expect(find.byType(InlineNotice), findsOneWidget);
    });
  });

  group('yükleme ve gösterim', () {
    testWidgets('sunucudaki değerler alanlara ve anahtarlara yansır; kaydet / geri al pasif', (t) async {
      final c = await _pump(t, config: acConfig(maintenance: true, enforce: true));
      expect(c.h.api.configCalls, 1);
      expect(_text(t, 'min_supported_version'), '1.0.0');
      expect(_text(t, 'latest_version'), '1.2.0');
      expect(_text(t, 'email'), 'destek@gudeteknoloji.com.tr');
      expect(_text(t, 'mersis_no'), '0123456789012345');
      expect(t.widget<SwitchListTile>(find.byKey(_maintenance)).value, isTrue);
      expect(t.widget<SwitchListTile>(find.byKey(_enforce)).value, isTrue);
      expect(find.byKey(_dirty), findsNothing);
      expect(_saveEnabled(t), isFalse, reason: 'değişiklik yok');
      expect(t.widget<TextButton>(find.byKey(_revert)).onPressed, isNull);
    });

    testWidgets('ayarsız (boş) sunucu: boş alanlar ve kapalı anahtarlar (form çizilir)', (t) async {
      final c = await _pump(t, config: const PlatformConfig());
      expect(_text(t, 'latest_version'), '');
      expect(t.widget<SwitchListTile>(find.byKey(_enforce)).value, isFalse);
      expect(find.byKey(_save), findsOneWidget);
      expect(c.h.api.configCalls, 1);
    });

    testWidgets('hata -> Tekrar Dene -> form gelir', (t) async {
      final h = AccountHarness(role: UserRole.superUser)..api.configError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      final c = await _pump(t, harness: h);
      expect(find.byKey(_f('latest_version')), findsNothing);
      h.api.configError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      expect(c.h.api.configCalls, 2);
      expect(find.byKey(_f('latest_version')), findsOneWidget);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });

    testWidgets('yenileme başarısızsa eldeki form KORUNUR, hata + Tekrar Dene görünür', (t) async {
      final c = await _pump(t);
      c.h.api.configError = ApiException('Sunucuya bağlanılamadı.');
      await c.state.reload();
      await settleFor(t);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.byKey(_f('latest_version')), findsOneWidget);
      expect(_text(t, 'latest_version'), '1.2.0');
    });
  });

  group('kısmi güncelleme', () {
    testWidgets('yalnız DEĞİŞEN alan gönderilir; başarı bildirimi, kirli işaret kalkar, onSaved çağrılır', (t) async {
      final c = await _pump(t);
      await _enter(t, 'latest_version', '1.3.0');
      expect(find.byKey(_dirty), findsOneWidget);
      expect(_saveEnabled(t), isTrue);

      await _tapSave(t);
      await settleFor(t);

      expect(c.h.api.putPatches, hasLength(1));
      expect(c.h.api.putPatches.single, <String, Map<String, Object>>{
        'app': <String, Object>{'latest_version': '1.3.0'},
      });
      expect(find.byKey(_saved), findsOneWidget);
      expect(find.text('Ayarlar kaydedildi.'), findsOneWidget);
      expect(find.byKey(_dirty), findsNothing);
      expect(_saveEnabled(t), isFalse);
      expect(c.saved, hasLength(1), reason: 'uygulama yapılandırması tazelenir');
      expect(c.state.hasUnsavedChanges, isFalse);
    });

    testWidgets('birden çok bölümde değişiklik: iç içe ve yalnız değişenler; boş dize = ayarsız yap', (t) async {
      final c = await _pump(t);
      await _enter(t, 'hours', '');
      await _enter(t, 'company_name', ' Yeni Unvan A.Ş. ');
      await _tapSave(t);
      await settleFor(t);
      expect(c.h.api.putPatches.single, <String, Map<String, Object>>{
        'support': <String, Object>{'hours': ''},
        'legal': <String, Object>{'company_name': 'Yeni Unvan A.Ş.'},
      });
    });

    testWidgets('anahtar değişimi gönderilir (bakım modu kapatma: onay gerekmez)', (t) async {
      final c = await _pump(t, config: acConfig(maintenance: true));
      await _tapSwitch(t, _maintenance);
      expect(find.byKey(_dirty), findsOneWidget);
      await _tapSave(t);
      await settleFor(t);
      expect(find.byType(AlertDialog), findsNothing, reason: 'kapatmak riskli değil');
      expect(c.h.api.putPatches.single, <String, Map<String, Object>>{
        'app': <String, Object>{'maintenance_active': false},
      });
    });

    testWidgets('değişikliği geri alınca (eski değer) kirli işaret kalkar, kaydet pasifleşir', (t) async {
      await _pump(t);
      await _enter(t, 'latest_version', '9.9.9');
      expect(_saveEnabled(t), isTrue);
      await _enter(t, 'latest_version', '1.2.0');
      expect(find.byKey(_dirty), findsNothing);
      expect(_saveEnabled(t), isFalse);
    });

    testWidgets('"Değişiklikleri Geri Al" sunucudaki değerleri yeniden yazar ve doğrulama hatalarını siler', (t) async {
      final c = await _pump(t);
      await _enter(t, 'latest_version', '1.2');
      await _enter(t, 'email', 'gecersiz');
      await _tapSave(t);
      await settleFor(t);
      expect(find.textContaining('1.2.3 biçiminde olmalı'), findsOneWidget);

      await t.ensureVisible(find.byKey(_revert));
      await t.tap(find.byKey(_revert));
      await settleFor(t);
      expect(_text(t, 'latest_version'), '1.2.0');
      expect(_text(t, 'email'), 'destek@gudeteknoloji.com.tr');
      expect(find.byKey(_dirty), findsNothing);
      expect(find.textContaining('1.2.3 biçiminde olmalı'), findsNothing);
      expect(c.h.api.putPatches, isEmpty);
    });
  });

  group('doğrulama', () {
    testWidgets('geçersiz alanlar: Türkçe iletiler, sunucuya gidilmez, özet görünür', (t) async {
      final c = await _pump(t);
      await _enter(t, 'min_supported_version', '2.0');
      await _enter(t, 'latest_version', 'v1');
      await _enter(t, 'update_url_android', 'http://play.google.com');
      await _enter(t, 'update_url_ios', 'apps.apple.com');
      await _enter(t, 'email', 'a@b');
      await _enter(t, 'phone', '12');
      await _enter(t, 'web_url', 'https://exa mple.com');
      await _enter(t, 'company_name', '[x](http://a)');
      await _enter(t, 'mersis_no', '123');
      await _enter(t, 'kep_address', 'kep');
      await _enter(t, 'contact_email', 'x@y');
      await _enter(t, 'contact_phone', '1');
      await _tapSave(t);
      await settleFor(t);

      expect(c.h.api.putPatches, isEmpty);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.textContaining('En düşük desteklenen sürüm 1.2.3 biçiminde olmalı'), findsOneWidget);
      expect(find.textContaining('Son sürüm 1.2.3 biçiminde olmalı'), findsOneWidget);
      expect(find.textContaining('Android güncelleme bağlantısı https:// ile başlayan'), findsOneWidget);
      expect(find.textContaining('iOS güncelleme bağlantısı https:// ile başlayan'), findsOneWidget);
      expect(find.textContaining('Destek e-postası geçerli bir e-posta'), findsOneWidget);
      expect(find.textContaining('Destek telefonu geçerli bir telefon'), findsOneWidget);
      expect(find.textContaining('Şirket unvanı köşeli parantez'), findsOneWidget);
      expect(find.textContaining('MERSİS numarası 16 haneli'), findsOneWidget);
    });

    testWidgets('en düşük sürüm son sürümden büyük olamaz', (t) async {
      final c = await _pump(t);
      await _enter(t, 'min_supported_version', '3.0.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.text('En düşük desteklenen sürüm, son sürümden büyük olamaz.'), findsOneWidget);
      expect(c.h.api.putPatches, isEmpty);
    });

    testWidgets('ilk geçersiz alan odaklanır', (t) async {
      await _pump(t);
      await _enter(t, 'latest_version', '1.2');
      await _tapSave(t);
      await t.pump(const Duration(milliseconds: 300));
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      final editable = t.widget<EditableText>(
        find.descendant(of: find.byKey(_f('latest_version')), matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('sürüm alanı yalnız rakam ve nokta alır; çok satırlı alanlar satır sonu almaz', (t) async {
      await _pump(t);
      await _enter(t, 'latest_version', 'v1.2a.3b');
      expect(_text(t, 'latest_version'), '1.2.3');
      await _enter(t, 'company_address', 'Satır 1\nSatır 2');
      expect(_text(t, 'company_address'), 'Satır 1Satır 2');
      await _enter(t, 'mersis_no', '0123-abc 4567');
      expect(_text(t, 'mersis_no'), '0123 4567');
    });

    testWidgets('boş alan = ayarsız: doğrulamayı geçer ve ayarsız yapma isteği gider', (t) async {
      final c = await _pump(t);
      for (final f in <String>['update_url_android', 'email', 'phone', 'web_url', 'mersis_no', 'kep_address']) {
        await _enter(t, f, '');
      }
      await _tapSave(t);
      await settleFor(t);
      expect(c.h.api.putPatches, hasLength(1));
      expect((c.h.api.putPatches.single['app']!)['update_url_android'], '');
      expect((c.h.api.putPatches.single['legal']!)['mersis_no'], '');
    });
  });

  group('riskli değişiklik onayı', () {
    testWidgets('bakım modunu açmak: onay penceresi; Vazgeç -> istek yok; Kaydet -> istek', (t) async {
      final c = await _pump(t);
      await _tapSwitch(t, _maintenance);
      await _tapSave(t);
      await settleFor(t);
      expect(find.text('Bu değişiklikleri kaydet?'), findsOneWidget);
      expect(find.textContaining('Bakım modu AÇILACAK'), findsOneWidget);

      await t.tap(_dialogButton('Vazgeç'));
      await settleFor(t);
      expect(c.h.api.putPatches, isEmpty);
      expect(find.byKey(_dirty), findsOneWidget, reason: 'değişiklikler korunur');

      await _tapSave(t);
      await settleFor(t);
      await t.tap(_dialogButton('Kaydet'));
      await settleFor(t);
      expect(c.h.api.putPatches.single['app'], <String, Object>{'maintenance_active': true});
    });

    testWidgets('en düşük sürümü yükseltmek ve onayları zorunlu kılmak: ikisi de tek pencerede', (t) async {
      final c = await _pump(t);
      await _enter(t, 'min_supported_version', '1.1.0');
      await _tapSwitch(t, _enforce);
      await _tapSave(t);
      await settleFor(t);
      expect(find.textContaining('En düşük desteklenen sürüm 1.1.0 olacak'), findsOneWidget);
      expect(find.textContaining('Onaylar ZORUNLU kılınacak'), findsOneWidget);
      await t.tap(_dialogButton('Kaydet'));
      await settleFor(t);
      expect(c.h.api.putPatches, hasLength(1));
    });

    testWidgets('en düşük sürümü düşürmek / kaldırmak onay gerektirmez', (t) async {
      final c = await _pump(t);
      await _enter(t, 'min_supported_version', '0.9.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.h.api.putPatches, hasLength(1));
    });

    testWidgets('onay penceresi açıkken çift dokunuş ikinci pencere / ikinci istek üretmez', (t) async {
      final c = await _pump(t);
      await _tapSwitch(t, _enforce);
      await t.ensureVisible(find.byKey(_save));
      await t.tap(find.byKey(_save));
      await t.tap(find.byKey(_save), warnIfMissed: false);
      await settleFor(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(_dialogButton('Kaydet'));
      await settleFor(t);
      expect(c.h.api.putPatches, hasLength(1));
    });
  });

  group('sunucu hataları ve kilitler', () {
    testWidgets('400 VALIDATION_FAILED: alan altında sunucu iletisi, düzenleyince silinir, form korunur', (t) async {
      final c = await _pump(t);
      c.h.api.putError = ApiException(
        'Bazı alanlar geçersiz.',
        statusCode: 400,
        code: 'VALIDATION_FAILED',
        payload: <String, dynamic>{
          'fields': <String, dynamic>{'support.hours': 'en fazla 200 karakter olabilir.'},
        },
      );
      await _enter(t, 'hours', 'Hafta içi 09:00 - 18:00 (yeni)');
      await _tapSave(t);
      await settleFor(t);

      expect(find.text('En fazla 200 karakter olabilir.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(_text(t, 'hours'), 'Hafta içi 09:00 - 18:00 (yeni)');

      await _enter(t, 'hours', 'Her gün 09:00 - 18:00');
      await t.pump(const Duration(milliseconds: 500)); // hata metni solarak kalkar
      expect(find.text('En fazla 200 karakter olabilir.'), findsNothing);
    });

    testWidgets('INVALID_VERSION_RANGE alan hatası olarak en düşük sürüm altında görünür', (t) async {
      final c = await _pump(t);
      c.h.api.putError = ApiException(
        'Desteklenen en düşük sürüm, en son sürümden büyük olamaz.',
        statusCode: 400,
        code: 'INVALID_VERSION_RANGE',
        payload: <String, dynamic>{
          'fields': <String, dynamic>{'app.min_supported_version': 'en son sürümden büyük olamaz.'},
        },
      );
      await _enter(t, 'latest_version', '0.5.0');
      await _enter(t, 'min_supported_version', '0.4.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.text('En son sürümden büyük olamaz.'), findsOneWidget);
    });

    testWidgets('bilinmeyen alan anahtarı ya da alansız hata: genel ileti, form korunur', (t) async {
      final c = await _pump(t);
      c.h.api.putError = ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      await _enter(t, 'latest_version', '1.3.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.textContaining('Sunucuya bağlanılamadı'), findsOneWidget);
      expect(_text(t, 'latest_version'), '1.3.0');
      expect(find.byKey(_dirty), findsOneWidget);
      expect(_saveEnabled(t), isTrue, reason: 'tekrar denenebilir');

      c.h.api.putError = null;
      await _tapSave(t);
      await settleFor(t);
      expect(c.h.api.putPatches, hasLength(2));
      expect(find.text('Ayarlar kaydedildi.'), findsOneWidget);
      expect(find.textContaining('Sunucuya bağlanılamadı'), findsNothing);
    });

    testWidgets('kayıt sürerken: düğme yükleniyor, alanlar ve anahtarlar kilitli, çift dokunuş tek istek', (t) async {
      final c = await _pump(t);
      c.h.api.putGate = Completer<void>();
      await _enter(t, 'latest_version', '1.3.0');
      await _tapSave(t);
      await t.tap(find.byKey(_save), warnIfMissed: false);
      await t.pump();

      expect(c.h.api.putPatches, hasLength(1));
      expect(t.widget<PrimaryActionButton>(find.byKey(_save)).loading, isTrue);
      expect(_saveEnabled(t), isFalse);
      expect(
        t.widget<TextField>(find.descendant(of: find.byKey(_f('latest_version')), matching: find.byType(TextField))).enabled,
        isFalse,
      );
      expect(t.widget<SwitchListTile>(find.byKey(_enforce)).onChanged, isNull);
      expect(t.widget<TextButton>(find.byKey(_revert)).onPressed, isNull);

      c.h.api.putGate!.complete();
      await settleFor(t);
      expect(find.text('Ayarlar kaydedildi.'), findsOneWidget);
    });

    testWidgets('hız sınırı (429): ileti + Kaydet süre dolana dek kilitli', (t) async {
      final c = await _pump(t);
      c.h.api.putError = ApiException(
        'Çok fazla ayar değişikliği. Biraz sonra tekrar deneyin.',
        statusCode: 429,
        retryAfterSeconds: 20,
      );
      await _enter(t, 'latest_version', '1.3.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.text('Çok fazla ayar değişikliği. Biraz sonra tekrar deneyin.'), findsOneWidget);
      expect(_saveEnabled(t), isFalse);
      await t.pump(const Duration(seconds: 21));
      expect(_saveEnabled(t), isTrue);
    });

    testWidgets('oturum bitti (401) ileti gösterilir; yerel çıkış servis katmanında doğrulanır', (t) async {
      final c = await _pump(t);
      c.h.api.putError = SessionExpiredException();
      await _enter(t, 'latest_version', '1.3.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.text('Oturum süreniz doldu. Lütfen tekrar giriş yapın.'), findsOneWidget);
      expect(c.h.auth.forcedRefreshes, 1);
    });
  });

  group('kaydedilmemiş değişiklik uyarısı', () {
    testWidgets('confirmDiscard: temizken pencere yok (true); kirliyken Düzenlemeye Dön (false) / Değişiklikleri Sil (true)', (t) async {
      final c = await _pump(t);
      expect(await c.state.confirmDiscard(), isTrue);
      expect(find.byType(AlertDialog), findsNothing);

      await _enter(t, 'latest_version', '1.3.0');
      var result = Future<bool>.value(false);
      result = c.state.confirmDiscard();
      await settleFor(t);
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await t.tap(_dialogButton('Düzenlemeye Dön'));
      await settleFor(t);
      expect(await result, isFalse);
      expect(c.state.hasUnsavedChanges, isTrue);

      result = c.state.confirmDiscard();
      await settleFor(t);
      await t.tap(_dialogButton('Değişiklikleri Sil'));
      await settleFor(t);
      expect(await result, isTrue);
    });

    testWidgets('confirmDiscard yeniden-giriş: aynı karede iki çağrı TEK pencereyi ve sonucunu paylaşır; bitince yeni çağrı yeniden sorar', (t) async {
      final c = await _pump(t);
      await _enter(t, 'latest_version', '1.3.0');

      final first = c.state.confirmDiscard();
      final second = c.state.confirmDiscard();
      await settleFor(t);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'ikinci pencere açılmaz');
      await t.tap(_dialogButton('Düzenlemeye Dön'));
      await settleFor(t);
      expect(await first, isFalse);
      expect(await second, isFalse, reason: 'ikisi de aynı sonucu alır');

      final again = c.state.confirmDiscard();
      await settleFor(t);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'önceki bitti: yeni çağrı yeniden sorar');
      await t.tap(_dialogButton('Değişiklikleri Sil'));
      await settleFor(t);
      expect(await again, isTrue);
    });

    testWidgets('yenileme (reload) kirliyken onay ister: vazgeçince GET yok, onaylayınca sunucu değerleri gelir', (t) async {
      final c = await _pump(t);
      await _enter(t, 'latest_version', '1.3.0');

      unawaited(c.state.reload());
      await settleFor(t);
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await t.tap(_dialogButton('Düzenlemeye Dön'));
      await settleFor(t);
      expect(c.h.api.configCalls, 1);
      expect(_text(t, 'latest_version'), '1.3.0');

      unawaited(c.state.reload());
      await settleFor(t);
      await t.tap(_dialogButton('Değişiklikleri Sil'));
      await settleFor(t);
      expect(c.h.api.configCalls, 2);
      expect(_text(t, 'latest_version'), '1.2.0');
      expect(c.state.hasUnsavedChanges, isFalse);
    });

    testWidgets('temizken reload doğrudan yeniden çeker (pencere yok)', (t) async {
      final c = await _pump(t);
      await c.state.reload();
      await settleFor(t);
      expect(c.h.api.configCalls, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('kayıt sürerken reload yok sayılır', (t) async {
      final c = await _pump(t);
      c.h.api.putGate = Completer<void>();
      await _enter(t, 'latest_version', '1.3.0');
      await _tapSave(t);
      await c.state.reload();
      await t.pump();
      expect(c.h.api.configCalls, 1);
      c.h.api.putGate!.complete();
      await settleFor(t);
    });
  });

  group('düzeltmeler: bayat yanıt, kurulu sürüm, odak, sessiz pasiflik', () {
    testWidgets('yenileme sürerken alanlar, anahtarlar ve Kaydet KİLİTLİ; yanıt gelince açılır (bayat GET kaydedileni ezemez)', (t) async {
      final c = await _pump(t);
      final gate = Completer<void>();
      c.h.api.configGate = gate;
      unawaited(c.state.reload());
      await t.pump();
      await t.pump();

      expect(
        t.widget<TextField>(find.descendant(of: find.byKey(_f('latest_version')), matching: find.byType(TextField))).enabled,
        isFalse,
        reason: 'yenileme sürerken düzenlenemez',
      );
      expect(t.widget<SwitchListTile>(find.byKey(_maintenance)).onChanged, isNull);
      expect(t.widget<SwitchListTile>(find.byKey(_enforce)).onChanged, isNull);
      expect(_saveEnabled(t), isFalse);
      expect(t.widget<TextButton>(find.byKey(_revert)).onPressed, isNull);

      c.h.api.config = acConfig(latest: '1.3.0');
      gate.complete();
      await settleFor(t);
      expect(_text(t, 'latest_version'), '1.3.0');
      expect(c.h.api.putPatches, isEmpty);
      expect(
        t.widget<TextField>(find.descendant(of: find.byKey(_f('latest_version')), matching: find.byType(TextField))).enabled,
        isTrue,
      );
    });

    testWidgets('ilk tuş vuruşunda (kirli uyarısı belirirken) ve kayıttan sonraki ilk tuşta ODAK korunur: alan kartları yeniden kurulmaz', (t) async {
      final c = await _pump(t);
      final field = find.byKey(_f('hours'));
      await t.ensureVisible(field);
      await t.pump();
      await t.tap(field);
      await t.pump();
      EditableText editable() => t.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)));
      expect(editable().focusNode.hasPrimaryFocus, isTrue);
      final before = t.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));

      await t.enterText(field, 'Her gün 09:00 - 18:00');
      await t.pump();
      expect(find.byKey(_dirty), findsOneWidget, reason: 'üstte uyarı belirdi');
      expect(editable().focusNode.hasPrimaryFocus, isTrue, reason: 'odak ilk tuşta kaybolmaz');
      expect(identical(t.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText))), before), isTrue,
          reason: 'aynı alan nesnesi (yeniden kurulmadı)');

      // Kaydet -> başarı bildirimi belirir; sonraki ilk tuşta yine odak kaybolmaz.
      await _tapSave(t);
      await settleFor(t);
      expect(find.byKey(_saved), findsOneWidget);
      expect(c.h.api.putPatches, hasLength(1));
      // Kayıttan sonra: alan görünür yapılır, dokunulur (odak ALAN tarafından alınır) ve yazılır; yazarken alan
      // nesnesi değişmemeli (üstten ekleme + alttan çıkarma alan kartlarını yeniden kurmamalı). Odak iddiası
      // `enterText`in kendi odak vermesine dayanmaz: dokunuştan SONRA ve yazmadan ÖNCE odağı ölçeriz.
      await t.ensureVisible(field);
      await t.pump();
      await t.tap(field);
      await t.pump();
      final afterTap = t.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));
      expect(editable().focusNode.hasPrimaryFocus, isTrue, reason: 'dokunuşla odak alanda');
      await t.enterText(field, 'Başka saat');
      await t.pump();
      expect(find.byKey(_dirty), findsOneWidget, reason: 'üstte uyarı yeniden belirdi');
      expect(
        identical(t.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText))), afterTap),
        isTrue,
        reason: 'kayıttan sonra da ilk tuşta alan yeniden kurulmaz',
      );
      expect(editable().focusNode.hasPrimaryFocus, isTrue, reason: 'ilk tuştan sonra odak kaybolmaz');
    });

    testWidgets('kurulu sürümden YÜKSEK en düşük sürüm reddedilir (son sürüm boş olsa da); sunucuya gidilmez', (t) async {
      final c = await _pump(t, config: acConfig(latest: ''));
      await _enter(t, 'min_supported_version', '1.3.0');
      await _tapSave(t);
      await settleFor(t);
      expect(
        find.textContaining('En düşük desteklenen sürüm (1.3.0), bu uygulamanın sürümünden (1.2.0) yüksek olamaz'),
        findsOneWidget,
      );
      expect(find.textContaining('kendi uygulamanız da güncelleme ekranına düşer'), findsOneWidget);
      expect(c.h.api.putPatches, isEmpty);
      expect(find.byType(AlertDialog), findsNothing, reason: 'onay penceresine hiç gelinmez');
    });

    testWidgets('kurulu sürüme EŞİT en düşük sürüm kabul edilir ve risk notu kullanılan sürümü söyler', (t) async {
      final c = await _pump(t);
      await _enter(t, 'min_supported_version', '1.2.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.textContaining('En düşük desteklenen sürüm 1.2.0 olacak'), findsOneWidget);
      expect(find.textContaining('şu an kullandığınız sürüm: 1.2.0, etkilenmez'), findsOneWidget);
      await t.tap(_dialogButton('Kaydet'));
      await settleFor(t);
      expect(c.h.api.putPatches.single['app'], <String, Object>{'min_supported_version': '1.2.0'});
    });

    testWidgets('DEĞİŞMEMİŞ eski en düşük sürüm kurulu sürümden yüksek olsa da başka alanların kaydını engellemez', (t) async {
      final c = await _pump(t, config: acConfig(minVersion: '5.0.0', latest: '9.0.0'));
      await _enter(t, 'hours', 'Her gün 09:00 - 18:00');
      await _tapSave(t);
      await settleFor(t);
      expect(c.h.api.putPatches.single, <String, Map<String, Object>>{
        'support': <String, Object>{'hours': 'Her gün 09:00 - 18:00'},
      });
    });

    testWidgets('kurulu sürüm okunamazsa kurulu sürüm denetimi atlanır (reddedilmez; yalnız risk onayı gelir)', (t) async {
      final c = await _pump(t, config: acConfig(latest: ''), installed: _installedAs(null));
      await _enter(t, 'min_supported_version', '9.0.0');
      await _tapSave(t);
      await settleFor(t);
      expect(find.textContaining('bu uygulamanın sürümünden'), findsNothing);
      expect(find.text('Bu değişiklikleri kaydet?'), findsOneWidget);
      expect(find.textContaining('şu an kullandığınız sürüm'), findsNothing);
      await t.tap(_dialogButton('Kaydet'));
      await settleFor(t);
      expect(c.h.api.putPatches, hasLength(1));
    });

    testWidgets('değişiklik yokken Kaydet pasif ve NEDEN yazılı; değişiklik varken ipucu kalkar', (t) async {
      await _pump(t);
      expect(_saveEnabled(t), isFalse);
      expect(find.byKey(const ValueKey<String>('platform_no_changes')), findsOneWidget);
      expect(find.text('Kaydedilecek değişiklik yok.'), findsOneWidget);
      await _enter(t, 'latest_version', '1.3.0');
      expect(find.byKey(const ValueKey<String>('platform_no_changes')), findsNothing);
      await _enter(t, 'latest_version', '1.2.0');
      expect(find.byKey(const ValueKey<String>('platform_no_changes')), findsOneWidget);
    });

    testWidgets('değişiklik yokken son alanda Enter sessizce dönmez: ekran okuyucuya "Kaydedilecek değişiklik yok." duyurulur', (t) async {
      final messages = captureAnnouncements(t);
      final c = await _pump(t);
      await t.ensureVisible(find.byKey(_f('contact_phone')));
      await t.pump();
      await t.tap(find.byKey(_f('contact_phone')));
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleFor(t);
      expect(messages, contains('Kaydedilecek değişiklik yok.'));
      expect(c.h.api.putPatches, isEmpty);
    });

    testWidgets('GENEL (alan dışı) kayıt hatasından sonra odak hata kutusuna gelir; hata duyurulur', (t) async {
      final messages = captureAnnouncements(t);
      final c = await _pump(t);
      c.h.api.putError = ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      await _enter(t, 'latest_version', '1.3.0');
      await _tapSave(t);
      await settleFor(t);

      final focus = t.widget<Focus>(find.byKey(const ValueKey<String>('platform_save_error_focus')));
      expect(focus.focusNode!.hasPrimaryFocus, isTrue, reason: 'odak kökte kalmaz');
      expect(messages.any((m) => m.contains('Sunucuya bağlanılamadı')), isTrue);
    });

    testWidgets('sunucu ALAN hatasında odak ilgili alana gelir', (t) async {
      final c = await _pump(t);
      c.h.api.putError = ApiException(
        'Bazı alanlar geçersiz.',
        statusCode: 400,
        code: 'VALIDATION_FAILED',
        payload: <String, dynamic>{
          'fields': <String, dynamic>{'support.hours': 'en fazla 200 karakter olabilir.'},
        },
      );
      await _enter(t, 'hours', 'Her gün 09:00 - 18:00');
      await _tapSave(t);
      await settleFor(t);
      final editable = t.widget<EditableText>(
        find.descendant(of: find.byKey(_f('hours')), matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasPrimaryFocus, isTrue);
    });
  });

  group('klavye', () {
    testWidgets('320x640 x2,0 klavye açık: son alanda "bitti" kaydeder; taşma yok', (t) async {
      final c = await _pump(t, width: 320, height: 640, scale: 2.0);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await _enter(t, 'contact_phone', '+90 212 111 22 33');

      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleFor(t);
      expect(c.h.api.putPatches, hasLength(1));
      expect(c.h.api.putPatches.single['legal'], <String, Object>{'contact_phone': '+90 212 111 22 33'});
      expect(t.takeException(), isNull);
    });

    testWidgets('yatay telefon 640x360 + klavye: kaydet düğmesine kaydırılarak erişilir', (t) async {
      await _pump(t, width: 640, height: 360);
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetViewInsets);
      await _enter(t, 'latest_version', '1.3.0');
      await t.ensureVisible(find.byKey(_save));
      await t.pump();
      final rect = t.getRect(find.byKey(_save));
      expect(rect.bottom, lessThanOrEqualTo(360 + 0.5));
      expect(_saveEnabled(t), isTrue);
      expect(t.takeException(), isNull);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('bölüm başlıkları başlık anlamı taşır; alanlar etiketli', (t) async {
      await _pump(t);
      final handle = t.ensureSemantics();
      expect(find.bySemanticsLabel('Uygulama Sürümü ve Bakım'), findsWidgets);
      expect(find.bySemanticsLabel('Son sürüm'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Destek e-postası')), findsWidgets);
      handle.dispose();
    });
  });
}
