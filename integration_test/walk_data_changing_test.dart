// !!! VERI DEGISTIREN AKISLAR (ayri ve acikca isaretli test) !!!
//
// Bu dosya yerel E2E veritabanina YENI KAYIT ekler (yeni bireysel kullanici + e-posta dogrulama).
// Yalniz bu test calisirken veriyi sifirlamaya hazir olun:
//   node <E2E>/backend/reset-db.mjs   (sonra simulatoru yeniden baslatin; bkz. E2E README)
//
// Calistirma (yalniz bu dosya; ~3 dk):
//   flutter test integration_test/walk_data_changing_test.dart -d windows \
//     --dart-define=API_BASE_URL=http://127.0.0.1:18080 \
//     --dart-define-from-file=<E2E>/dart_defines.json \
//     --dart-define=E2E_MAILS_DIR=<E2E>/mails
//
// Akis: Giris ekrani -> "Yeni Hesap Oluştur" -> form -> "Kayıt Ol" -> sahte SMTP kutusundan (E2E_MAILS_DIR)
// kodu oku -> "Hesabımı Doğrula" -> otomatik giris (bireysel panel) -> cikis.
// Uretime baglanmaz (E2eEnv.assertLocalApi). Kod/parola konsola yazilmaz.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_report.dart';

const String _mailsDir = String.fromEnvironment('E2E_MAILS_DIR');

/// Sahte SMTP kutusundan [email] adresine gelen EN SON postanin dogrulama kodunu bekleyip dondurur.
Future<String?> _waitForCode(String email, {Duration timeout = const Duration(seconds: 30)}) async {
  if (_mailsDir.isEmpty) return null;
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final dir = Directory(_mailsDir);
    if (dir.existsSync()) {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('-$email.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files.reversed) {
        try {
          final mail = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          final code = mail['code'];
          if (code is String && code.isNotEmpty) return code;
        } catch (_) {}
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

void main() {
  initE2eBinding();

  testWidgets(
    'VERI DEGISTIRIR: yeni bireysel kayit + e-posta dogrulama + ilk giris',
    (tester) async {
      await runE2e(
        tester,
        suite: 'walk_data_changing',
        body: (session) async {
          if (_mailsDir.isEmpty) {
            throw StateError('E2E_MAILS_DIR tanimli degil (--dart-define=E2E_MAILS_DIR=<E2E>/mails).');
          }
          final stamp = DateTime.now().millisecondsSinceEpoch;
          final email = 'e2e.yeni.$stamp@e2e.local';
          const password = 'E2eYeni!2345';

          await bootApp(tester);
          final combo = E2eCombo.parse('phone@1.0').first;
          await session.applyCombo(combo);
          session.userKey = 'yeni_kayit';
          final scenario = session.report.beginScenario(
            userKey: 'yeni_kayit',
            role: 'individual',
            preset: combo.preset.id,
            textScale: combo.textScale,
            mode: 'kayit',
          );
          session.scenario = scenario;

          Future<void> step(String name, Future<void> Function(E2eScreenContext c) body) async {
            final result = E2eScreenResult(name: name, index: scenario.screens.length + 1);
            scenario.screens.add(result);
            E2eRuntime.collector.beginScreen(name);
            E2eRuntime.screen = result;
            try {
              await body(E2eScreenContext(session, tester, result));
            } catch (e) {
              result.status = 'error';
              E2eRuntime.collector.note(kind: 'exception', message: 'Adim hatasi: $e');
            } finally {
              result.findings.addAll(E2eRuntime.collector.drain());
              E2eRuntime.screen = null;
              session.report.write();
            }
          }

          await step('kayit_formu', (c) async {
            await c.tap('Yeni Hesap Oluştur', exact: true);
            await c.settleUi();
            await c.shot('bos_form');
            await c.type('E2E', label: 'Ad'); // ilk eslesen: 'Ad' (Soyad'dan once)
            await c.type('Yeni Kullanici', label: 'Soyad');
            await c.type(email, label: 'E-Posta');
            await c.type(password, label: 'Şifre'); // ilk eslesen: 'Şifre' ('Şifre Tekrar'dan once)
            await c.type(password, label: 'Şifre Tekrar');
            await c.shot('dolu_form');
            // VERI DEGISTIREN: kullanici olusturur ve dogrulama e-postasi gonderir.
            // 'Kayıt Ol' sayfada iki kez geçer (başlık + düğme etiketi): gönderen düğme 2. eşleşmedir.
            await tapText(tester, 'Kayıt Ol', exact: true, index: 1, unsafe: true);
            await c.settleUi(min: const Duration(seconds: 2));
            await c.expect('E-Posta Doğrulama', wait: const Duration(seconds: 15));
            await c.shot('dogrulama_sayfasi');
          });

          await step('dogrulama', (c) async {
            final code = await _waitForCode(email);
            if (code == null) {
              E2eRuntime.collector.note(kind: 'expectation', message: 'Dogrulama e-postasi (kod) gelmedi');
              return;
            }
            await c.type(code, hint: '••••••');
            await c.shot('kod_girildi');
            // VERI DEGISTIREN: hesabi dogrular ve otomatik giris yapar.
            await tapText(tester, 'Hesabımı Doğrula', exact: true, unsafe: true);
            final home = await pumpUntilFound(tester, find.byType(HomePage), timeout: const Duration(seconds: 30));
            if (!home) {
              E2eRuntime.collector.note(kind: 'navigation', message: 'Dogrulama sonrasi ana sayfa acilmadi');
              return;
            }
            await c.settleUi(min: const Duration(seconds: 2));
            await c.shot('ilk_giris_panel');
            await c.scrollEnd();
          });

          await step('cikis', (c) async {
            await logout(tester);
            await c.shot('cikis_sonrasi');
          });
        },
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
