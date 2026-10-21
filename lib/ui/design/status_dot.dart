// İP-1C (karar G7, sözleşme 2.3): durum noktası + metin.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Sade stilin durum gösterimi: metnin solunda küçük nokta; zemin ve çerçeve BOYANMAZ.
///
/// Nokta rengi [AppTone.dot]: tamam #10B981, bekliyor #F59E0B, kritik #E11D48; öteki tonlar (birincil, bilgi, mor, nötr)
/// nötr gri (#64748B). Açık temada noktası yüzeye 3:1'i tutmayan tonlarda (tamam 2,54:1, bekliyor 2,15:1) 1 dp koyu kenar
/// ([edgeOf]: tonun `a` rengi, >= 5:1) noktanın sınırını seçtirir; renk işverenin rengidir. Anlam metindedir (renk tek
/// başına anlam taşımaz).
///
/// Metin `bodySmall` + kalın, gövde metni renginde ([AppPalette.textSecondary], >= 4,5:1). Varsayılan tek satır + elips
/// ([maxLines] 1); `maxLines: null` sarar (uzun durum cümlesi). Taşma: sabit genişlik yoktur; sınırlı genişlikte (`Wrap`,
/// `Row` içinde `Flexible`) kullanın. Erişilebilirlik: ekran okuyucu metni okur, nokta dışlanır; dokunulamaz. Durağandır
/// (nabız gerekiyorsa `StatusChip(pulse: true)`). Dalga 2 ve sonrasındaki yeni ekranlar durum için bunu kullanır.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.maxLines = 1,
    this.style,
  });

  final String label;

  /// Durum tonu: [AppTone.success] tamam, [AppTone.warning] bekliyor, [AppTone.danger] kritik; diğerleri nötr.
  final AppTone tone;

  /// Metnin en çok satırı (null: sınırsız, sarar).
  final int? maxLines;

  /// Metin stilinin üstüne eklenecek ayarlar (ör. daha büyük punto). Renk verilmezse gövde metni rengi kalır.
  final TextStyle? style;

  /// Noktanın çapı (dp).
  static const double size = 8;

  /// Noktayı ve ikonu hizalayan baş kutusunun kenarı (dp): `StatusChip` ile aynı hizada durur.
  static const double leadExtent = 14;

  /// [tone] noktasının kenarı: açık temada nokta yüzeye 3:1'i tutmuyorsa tonun `a` rengi, değilse null.
  static Color? edgeOf(AppTone tone, AppPalette p) {
    if (p.isDark) return null;
    return _contrast(tone.dot, p.surface) < 3.0 ? tone.a : null;
  }

  /// Yalnız nokta (8 dp): özel satırlar ve `StatusChip` için tek çizim.
  static BoxDecoration decorationOf(AppTone tone, AppPalette p) {
    final edge = edgeOf(tone, p);
    return BoxDecoration(
      shape: BoxShape.circle,
      color: tone.dot,
      border: edge == null ? null : Border.all(color: edge),
    );
  }

  static double _contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    final textStyle = base.copyWith(fontWeight: FontWeight.w700, color: p.textSecondary).merge(style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: maxLines == 1 ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: leadExtent,
            height: leadExtent,
            child: Center(
              child: DecoratedBox(
                decoration: decorationOf(tone, p),
                child: const SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(
            label,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}
