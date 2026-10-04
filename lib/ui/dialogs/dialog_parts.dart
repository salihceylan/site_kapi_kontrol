// Küçük/orta diyalogların ortak görsel parçaları ("Cilalı Safir").
//
// - [DialogToggleTile]: anahtarlı ayar satırı (kart zemini + durum renkli [IconOrb] + `Switch`).
// - [DialogInfoRow]: [IconOrb] (40 dp squircle) + başlık + isteğe bağlı alt satır + rozet satırı.
// - [dialogLargeText]: büyük yazıda süs rozetini bırakma kuralı.
//
// Bu dosya yalnız GÖRÜNÜM taşır: davranış, metin ve anlamsal ağaç çağıranın verdiği `Switch`/`Text`
// değerlerinden gelir; rozetler dekoratiftir (anlamsal ağaçta yok).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Yazı ölçeği 1,3'ü aşıyor mu? Diyalog içeriği dar (260-420 dp) olduğundan büyük yazıda süs rozetleri
/// bırakılır: metin sütunu 40 dp + boşluk kadar genişler, satırlar daha az kırılır.
bool dialogLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;

/// Anahtarlı ayar satırı: soluk kart zemini, ince kenar, solda durum rozeti, sağda `Switch`.
///
/// Rozet durumu anlatır (tek başına anlam taşımaz; başlık ve alt başlık metni zaten durumu söyler):
/// açıkken [onIcon] + [onTone] (varsayılan success), kapalıyken [offIcon] + [offTone] (varsayılan
/// neutral); geçiş 200 ms solmayla olur (hareket azaltmada anında). [dialogLargeText] iken rozet yok.
///
/// Altta `SwitchListTile.adaptive` olduğundan tüm satır dokunma hedefidir, anlamsal düğüm tektir
/// ("başlık, alt başlık", açık/kapalı durumu) ve [onChanged] null ise satır devre dışıdır.
class DialogToggleTile extends StatelessWidget {
  const DialogToggleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onIcon,
    required this.offIcon,
    this.onTone = AppTone.success,
    this.offTone = AppTone.neutral,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// null ise satır devre dışıdır.
  final ValueChanged<bool>? onChanged;

  /// Açıkken rozet ikonu / tonu.
  final IconData onIcon;
  final AppTone onTone;

  /// Kapalıyken rozet ikonu / tonu.
  final IconData offIcon;
  final AppTone offTone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      tileColor: p.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: p.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      secondary: dialogLargeText(context)
          ? null
          : AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.base),
              child: IconOrb(
                key: ValueKey<bool>(value),
                icon: value ? onIcon : offIcon,
                tone: value ? onTone : offTone,
                size: 40,
                shape: IconOrbShape.squircle,
              ),
            ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

/// Bilgi satırı: [IconOrb] (40 dp squircle) + [title] + isteğe bağlı [subtitle] + [chips] satırı.
///
/// Kısa başlıkta metin rozete dikeyde ortalanır; alt satır/rozet varsa üstten akar. Satır içeriği
/// kadar geniştir (`Row` min + `Flexible`): yan yana bir eylemle `Wrap` içinde de kullanılabilir.
/// Taşma: başlık en çok [titleMaxLines] satır (+ elips), rozetler `Wrap` ile alt satıra iner;
/// [dialogLargeText] iken rozet bırakılır. Üst öğe sınırlı genişlikte olmalıdır.
class DialogInfoRow extends StatelessWidget {
  const DialogInfoRow({
    super.key,
    required this.icon,
    required this.title,
    this.tone = AppTone.primary,
    this.titleStyle,
    this.subtitle,
    this.chips = const <Widget>[],
    this.titleMaxLines = 3,
  });

  final IconData icon;
  final AppTone tone;
  final String title;

  /// null ise `titleMedium`.
  final TextStyle? titleStyle;
  final String? subtitle;

  /// Başlığın altında akan rozetler (genellikle `StatusChip`).
  final List<Widget> chips;
  /// null: sınırsız (metin yine `Flexible` içinde sarar).
  final int? titleMaxLines;

  /// Rozet yüksekliği: kısa metin bu yüksekliğe göre ortalanır.
  static const double _orb = 40;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!dialogLargeText(context)) ...[
          IconOrb(
            icon: icon,
            tone: tone,
            size: _orb,
            shape: IconOrbShape.squircle,
          ),
          const SizedBox(width: AppSpace.md),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _orb),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              heightFactor: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle ?? th.titleMedium,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs),
                      child: Text(subtitle, style: th.bodyMedium),
                    ),
                  if (chips.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.sm),
                      child: Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: chips,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
