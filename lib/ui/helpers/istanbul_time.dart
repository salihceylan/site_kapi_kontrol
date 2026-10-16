/// Türkiye saati (İstanbul, UTC+3). Türkiye 2016'dan beri yaz saati uygulamıyor, fark sabittir.
///
/// Duyuru zamanları (yayın zamanı, yayınlanma, okunma) HER ZAMAN İstanbul saatiyle gösterilir ve girilir:
/// cihazın saat dilimi yanlış ya da yurt dışında olsa bile sunucuyla aynı saat okunur. Bu yüzden
/// `DateTime.toLocal()` KULLANILMAZ; an her zaman UTC'ye çevrilip 3 saat eklenir.
const Duration istanbulUtcOffset = Duration(hours: 3);

String _two(int value) => value.toString().padLeft(2, '0');

/// [instant]'ın İstanbul duvar saatini taşıyan UTC işaretli tarih (alanları İstanbul saatidir).
DateTime istanbulWallClock(DateTime instant) => instant.toUtc().add(istanbulUtcOffset);

/// Şimdi, İstanbul duvar saatiyle ([now] testler içindir).
DateTime istanbulNow([DateTime? now]) => istanbulWallClock(now ?? DateTime.now());

/// "05.03.2024"; an yoksa "-".
String formatIstanbulDate(DateTime? instant) {
  if (instant == null) return '-';
  final w = istanbulWallClock(instant);
  return '${_two(w.day)}.${_two(w.month)}.${w.year.toString().padLeft(4, '0')}';
}

/// "14:30"; an yoksa "-".
String formatIstanbulTime(DateTime? instant) {
  if (instant == null) return '-';
  final w = istanbulWallClock(instant);
  return '${_two(w.hour)}:${_two(w.minute)}';
}

/// "05.03.2024 14:30"; an yoksa "-".
String formatIstanbulDateTime(DateTime? instant) {
  if (instant == null) return '-';
  return '${formatIstanbulDate(instant)} ${formatIstanbulTime(instant)}';
}

/// İstanbul duvar saatindeki [date] günü ve [hour]:[minute] saatinin gerçek anı (UTC).
DateTime istanbulInstantOf(DateTime date, int hour, int minute) =>
    DateTime.utc(date.year, date.month, date.day, hour, minute).subtract(istanbulUtcOffset);

/// [instant]'ın İstanbul duvar saatinden TAKVİM olarak bir yıl sonraki gerçek an (Şubat 29 -> 1 Mart,
/// sunucudaki `setFullYear(+1)` ile aynı). Zamanlama üst sınırı (en çok 1 yıl sonra) için.
DateTime istanbulCalendarYearAfter(DateTime instant) {
  final w = istanbulWallClock(instant);
  return DateTime.utc(w.year + 1, w.month, w.day, w.hour, w.minute, w.second, w.millisecond)
      .subtract(istanbulUtcOffset);
}
