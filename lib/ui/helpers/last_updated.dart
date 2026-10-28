// P2-26: listelerde "Son güncelleme 14:32" metni. Saat HER ZAMAN İstanbul saatidir (cihaz saat dilimi yanlış olsa da sunucuyla
// aynı saat okunur: bkz. istanbul_time.dart).
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';

/// "Son güncelleme 14:32". Güncelleme BUGÜN değilse (uygulama gece boyunca açık kalmış) tarih de yazılır:
/// "Son güncelleme 27.10.2026 14:32"; böylece eski veri "az önce" gibi görünmez. [now] testler içindir.
String formatLastUpdated(DateTime at, {DateTime? now}) {
  final today = istanbulNow(now);
  final day = istanbulWallClock(at);
  final sameDay = day.year == today.year && day.month == today.month && day.day == today.day;
  final stamp = sameDay ? formatIstanbulTime(at) : formatIstanbulDateTime(at);
  return 'Son güncelleme $stamp';
}
