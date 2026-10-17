import 'dart:async';

import 'package:site_kapi_kontrol/brand/gude_logo_animated.dart';
import 'package:site_kapi_kontrol/ui/widgets/unread_announcement_card.dart';

/// Bütün widget testleri için ortak kurulum (flutter_test bunu `test/` altındaki her test dosyasından önce çalıştırır).
///
/// Güde logosunun ışık animasyonu sonsuz bir tekrarlayan denetleyicidir; `pumpAndSettle` hiç bitmezdi.
/// Bu yüzden `animate` verilmeyen logolar testlerde durağan çizilir. Animasyonu sınayan testler
/// `animate: true` verir ya da `GudeLogoAnimation.enabledByDefault`ı açıp geri alır ve `tester.pump(Duration)` kullanır.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GudeLogoAnimation.enabledByDefault = false;
  // "Yeni duyuru" kartının nabız animasyonu da sonsuzdur: testlerde durağan (vurgulu) çizilir.
  UnreadAnnouncementCard.pulseEnabledByDefault = false;
  await testMain();
}
