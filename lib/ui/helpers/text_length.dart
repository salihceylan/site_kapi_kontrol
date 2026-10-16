import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Metnin KIRPILMIŞ uzunluğu, Unicode KOD NOKTASI olarak. Sunucu serbest metin sınırlarını (başvuru notu
/// 500, karar notu / gerekçe 300) kod noktasıyla sayar (`Array.from(text).length`); UTF-16 birimi
/// (`String.length`) emojili metni yanlış reddeder. Sayaç, doğrulayıcı ve düğme AYNI metni (kırpılmış)
/// ve AYNI birimi kullanmalıdır.
int trimmedCodePoints(String text) => text.trim().runes.length;

/// [text]'in ilk [max] kod noktası (sunucunun arama metnini kesmesiyle aynı).
String firstCodePoints(String text, int max) {
  final runes = text.runes;
  if (runes.length <= max) return text;
  return String.fromCharCodes(runes.take(max));
}

/// "n/500" sayacı: sınır aşılınca kırmızı + kalın; ekran okuyucu aşımı söyler. `TextField.buildCounter` ve
/// `maxLengthEnforcement: none` ile kullanılır (sessiz kırpma yok).
Widget characterCounter(BuildContext context, int length, int max) {
  final p = context.palette;
  final over = length > max;
  return Semantics(
    liveRegion: over,
    label: over
        ? '$length karakter; en çok $max olabilir, sınır aşıldı'
        : '$length / $max karakter',
    child: ExcludeSemantics(
      child: Text(
        '$length/$max',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: over ? AppTone.danger.ink(p) : p.textSecondary,
          fontWeight: over ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
  );
}
