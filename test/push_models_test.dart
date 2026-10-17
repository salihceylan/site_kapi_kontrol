// Telefon bildirimi (Faz 3b-B) modelleri ve cihaz deposu: yük beyaz listesi, "HH:MM", hoşgörülü çözümleme,
// kurulum kimliği (UUID v4, çökme raporundan AYRI anahtar), kayıt damgası (jeton değil özet), "bu cihazda kapalı".
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/push_gateway.dart';
import 'package:site_kapi_kontrol/services/push_store.dart';

void main() {
  group('yük beyaz listesi', () {
    test('yalnız type=announcement ve pozitif tamsayı (baştaki sıfır yok, ≤ 15 hane) kabul edilir', () {
      expect(pushAnnouncementIdOf(<String, Object?>{'type': 'announcement', 'announcement_id': '7'}), 7);
      expect(pushAnnouncementIdOf(<String, Object?>{'type': 'announcement', 'announcement_id': 12}), 12);
      expect(
        pushAnnouncementIdOf(<String, Object?>{'type': 'announcement', 'announcement_id': '999999999999999'}),
        999999999999999,
      );
      for (final bad in <Object?>['0', '-1', '007', '1.5', '1e3', ' 7', '7 ', '', '1234567890123456', 0, -4, 7.0, null]) {
        expect(
          pushAnnouncementIdOf(<String, Object?>{'type': 'announcement', 'announcement_id': bad}),
          isNull,
          reason: 'geçersiz numara: $bad',
        );
      }
      expect(pushAnnouncementIdOf(<String, Object?>{'type': 'payment', 'announcement_id': '7'}), isNull);
      expect(pushAnnouncementIdOf(<String, Object?>{'announcement_id': '7'}), isNull);
      expect(const PushMessage(<String, Object?>{'type': 'announcement', 'announcement_id': '3'}).announcementId, 3);
      const test = PushMessage(<String, Object?>{'type': 'test', 'announcement_id': '3'});
      expect(test.isTest, isTrue);
      expect(test.announcementId, isNull, reason: 'test bildirimi yönlendirmez');
    });
  });

  group('saat', () {
    test('"HH:MM" çözümleme ve yazma', () {
      expect(parsePushClock('23:00'), 1380);
      expect(parsePushClock('7:05'), 425);
      expect(parsePushClock('00:00'), 0);
      expect(parsePushClock('23:59'), 1439);
      for (final bad in <Object?>['24:00', '12:60', '1200', 'ab:cd', '', null, -1, 1440]) {
        expect(parsePushClock(bad), isNull, reason: '$bad');
      }
      expect(parsePushClock(420), 420);
      expect(formatPushClock(1380), '23:00');
      expect(formatPushClock(425), '07:05');
      expect(formatPushClock(5000), '23:59');
    });
  });

  group('PushPreferences', () {
    test('alan yoksa güvenli varsayılan: push kapalı/yok, normal duyuru açık, önizleme KAPALI, 23:00–07:00', () {
      final prefs = PushPreferences.fromJson(<String, dynamic>{'email_announcements': true});
      expect(prefs.available, isFalse);
      expect(prefs.announcements, isTrue);
      expect(prefs.showPreview, isFalse);
      expect(prefs.quietEnabled, isFalse);
      expect(prefs.quietStart, 1380);
      expect(prefs.quietEnd, 420);
      expect(prefs.deviceCount, 0);
    });

    test('yanlış tipli alan yedeğe düşer; yama yalnız verilen anahtarları yazar', () {
      final prefs = PushPreferences.fromJson(<String, dynamic>{
        'push_available': 'true',
        'push_announcements': 1,
        'push_quiet': <String, Object?>{'enabled': 'evet', 'start': '25:00', 'end': '06:30'},
        'push_devices': -2,
      }, fallback: const PushPreferences(available: true, quietEnabled: true));
      expect(prefs.available, isTrue);
      expect(prefs.announcements, isTrue);
      expect(prefs.quietEnabled, isTrue);
      expect(prefs.quietStart, 1380);
      expect(prefs.quietEnd, 390);
      expect(prefs.deviceCount, 0);
      expect(const PushPreferencesPatch(quietEnd: 390).toJson(), <String, Object>{'push_quiet_end': '06:30'});
      expect(const PushPreferencesPatch().isEmpty, isTrue);
      expect(const PushPreferencesPatch(showPreview: true).applyTo(prefs).showPreview, isTrue);
    });

    test('test sonucu negatif sayıları sıfırlar', () {
      final r = PushTestResult.fromJson(<String, dynamic>{'sent': -1, 'failed': '2'});
      expect(r.sent, 0);
      expect(r.failed, 2);
    });
  });

  group('platform kapısı', () {
    test('yalnız Android ve iOS; web ve masaüstünde HAYIR', () {
      expect(pushPlatformSupported(isWeb: false, platform: TargetPlatform.android), isTrue);
      expect(pushPlatformSupported(isWeb: false, platform: TargetPlatform.iOS), isTrue);
      expect(pushPlatformSupported(isWeb: true, platform: TargetPlatform.android), isFalse);
      for (final p in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(pushPlatformSupported(isWeb: false, platform: p), isFalse, reason: '$p');
      }
    });
  });

  group('PushLocalStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{'crash_reporter.install_id': 'c-1'}));

    test('kurulum kimliği: UUID v4, kalıcı, çökme raporu kimliğinden AYRI anahtar; okuma ÜRETMEZ', () async {
      final store = PushLocalStore();
      expect(await store.readInstallId(), isNull);
      final id = await store.installId();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(id, isNot('c-1'));
      expect(PushLocalStore.installIdKey, isNot('crash_reporter.install_id'));
      expect(await PushLocalStore().installId(), id, reason: 'yeni örnek aynı kimliği okur');
      expect(store.cachedInstallId, id);
    });

    test('kayıt damgası jeton DEĞİL özet taşır; bozuk kayıt yok sayılır', () async {
      final store = PushLocalStore();
      final at = DateTime(2026, 10, 17, 9);
      await store.writeStamp(
        PushRegistrationStamp(userId: 5, tokenHash: 'abc', notificationsEnabled: true, at: at),
      );
      final stamp = (await store.readStamp())!;
      expect(stamp.userId, 5);
      expect(stamp.tokenHash, 'abc');
      expect(stamp.at, at);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PushLocalStore.stampKey, '{bozuk');
      expect(await store.readStamp(), isNull);
      await store.clearStamp();
      expect(prefs.getString(PushLocalStore.stampKey), isNull);
    });

    test('"bu cihazda açık" (açık rıza) varsayılan KAPALI ve kullanıcı başınadır; kart kapatma da', () async {
      final store = PushLocalStore();
      expect(await store.isEnabledHere(5), isFalse);
      await store.setEnabledHere(5, true);
      expect(await store.isEnabledHere(5), isTrue);
      expect(await store.isEnabledHere(6), isFalse);
      await store.setEnabledHere(5, false);
      expect(await store.isEnabledHere(5), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PushLocalStore.enabledKey), isNull);
      expect(await store.isPromptDismissed(5), isFalse);
      await store.setPromptDismissed(5);
      expect(await store.isPromptDismissed(5), isTrue);
      expect(await store.isPromptDismissed(6), isFalse);
    });

    test('bekleyen FCM temizliği işareti ve başarısız deneme sayacı', () async {
      final store = PushLocalStore();
      expect(await store.hasPendingCleanup(), isFalse);
      expect(await store.pendingCleanupFailures(), 0);
      await store.setPendingCleanup(true);
      expect(await PushLocalStore().hasPendingCleanup(), isTrue);
      expect(await store.recordCleanupFailure(), 1);
      expect(await store.recordCleanupFailure(), 2);
      await store.setPendingCleanup(true);
      expect(await store.pendingCleanupFailures(), 2, reason: 'yeniden işaretlemek sayacı sıfırlamaz');
      await store.setPendingCleanup(false);
      expect(await store.hasPendingCleanup(), isFalse);
      expect(await store.pendingCleanupFailures(), 0);
    });

    test('yerel temizlik kurulum kimliğini silerse (bellekte eskisi olsa da) YENİSİ üretilip yazılır', () async {
      final store = PushLocalStore();
      final first = await store.installId();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PushLocalStore.installIdKey); // LocalDataWiper
      expect(store.cachedInstallId, first, reason: 'çıkıştaki eski kaydın silinmesi için son bilinen değer');
      expect(await store.readInstallId(), isNull, reason: 'okuma üretmez');
      final second = await store.installId();
      expect(second, isNot(first));
      expect(prefs.getString(PushLocalStore.installIdKey), second);
      expect(store.cachedInstallId, second);
    });
  });
}
