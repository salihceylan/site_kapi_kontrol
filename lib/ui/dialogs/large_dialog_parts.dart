// "Büyük diyalog" içerikleri (site, kapı yetkileri, sakinler, talepler, cihaz) için ortak görünüm
// parçaları. Hepsi `lib/ui/design` bileşenleri ve tokenları üzerine kuruludur: ham renk ve yeni punto
// yoktur, sabit genişlikli metin kutusu yoktur, dinamik metin sarar ya da elips olur (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Büyük yazı (>= 1,75x): satır başındaki dekoratif ikon rozetleri gizlenir; metne ~52 dp daha yer kalır
/// (320 dp x 2,0 ölçekte ad, rozet ve etiketler kırpılmadan sığar). Rozet süstür: ekran okuyucuya zaten
/// kapalıdır, anlam yanındaki metindedir.
bool hideRowOrbs(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= 1.75;

/// Diyalog içinde bir grubu çerçeveleyen panel: soluk iç yüzey + ince kenar. Üst öğenin genişliğini kaplar
/// (`Column` çocuğu olarak kullanın); içeriğe sabit yükseklik verilmez.
///
/// Sade stil (İP-1C, karar G6 + G7): zemin her tonda soluk iç yüzeydir (BOYANMAZ); [tone] durum tonuysa (tamam,
/// bekliyor, kritik) yalnız kenar tonun %40'ıdır, öteki tonlarda (birincil, bilgi, mor, nötr) palet kenarı: mavi
/// yalnız bağlantı ve odakta. Anlam panelin içindeki metinde ve simgededir.
class DialogPanel extends StatelessWidget {
  const DialogPanel({
    super.key,
    required this.child,
    this.tone,
    this.padding = const EdgeInsets.all(AppSpace.md),
  });

  final Widget child;

  /// null: nötr soluk yüzey; dolu: aynı zemin, durum tonlarında ton kenarı (uyarı / hata / tamam grupları).
  final AppTone? tone;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = this.tone;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: tone != null && tone.isStatus ? tone.hue.withValues(alpha: 0.4) : p.border,
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Panel/bölüm başlığı: 32 dp düz ikon rozeti ([IconOrb]) + küçük başlık (+ alt metin).
///
/// Başlık ve alt metin kalan genişliğe sarar (kırpılmaz). Üst öğe sınırlı genişlikte olmalıdır.
class DialogSectionTitle extends StatelessWidget {
  const DialogSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = AppTone.primary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Rozet tonu (anlamsal: rol/durum). Her başlığa parlak ton koymayın.
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    return Row(
      children: [
        IconOrb(
          icon: icon,
          tone: tone,
          size: 32,
          shape: IconOrbShape.squircle,
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: th.titleMedium),
              if (subtitle != null) Text(subtitle, style: th.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Küçük bilgi hapı (blok adı, daire etiketi, toplam sayı, uzun durum cümlesi): metin KIRPILMAZ,
/// sığmayınca satırlara sarar. Kısa durum etiketleri için `StatusChip` kullanılır (tek satır + elips);
/// bu hap üstverinin ve uzun cümlelerin yeridir. `Wrap` içinde ya da sütun çocuğu olarak kullanın.
///
/// Sade stil (İP-1C, karar G7; `InfoChip` ile aynı kural): zemin her tonda nötr soluk kutudur (soluk yüzey + palet
/// kenarı, BOYANMAZ); [tone] yalnız metni ve simgeyi renklendirir ([AppTone.sign]: durum tonlarında `ink`, öteki
/// tonlarda gövde metni rengi). Metin soluk yüzeyde >= 4,5:1.
class DialogMetaPill extends StatelessWidget {
  const DialogMetaPill(
    this.label, {
    super.key,
    this.tone,
    this.icon,
    this.minWidth = 0,
  });

  final String label;

  /// null: nötr soluk hap (başlık metni); dolu: aynı zemin, metin ve simge tonun işaret renginde (>= 4,5:1).
  final AppTone? tone;

  /// Metnin başındaki küçük simge (renk tek başına anlam taşımasın diye).
  final IconData? icon;

  /// En küçük genişlik (aynı sütundaki hapların hizası için); içerik büyükse genişler.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = this.tone;
    final icon = this.icon;
    final ink = tone == null ? p.text : tone.sign(p);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: ink),
                const SizedBox(width: AppSpace.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// İkincil eylem için "çerçeveli" düğme stili: `OutlinedButton.styleFrom` yerine VERİLİR (düğme tipi ve etiketin
/// satır sarma davranışı değişmez; `PrimaryActionButton` etiketi 2 satırda keser). En az 48 dp yükseklik.
///
/// Sade stil (İP-1C, karar G6; `tonalActionStyle` ile aynı kural): yüzey zemin + 1 px palet kenarı + başlık metni
/// (durum tonlarında tonun `ink` rengi, >= 4,5:1); zemin ton BOYANMAZ, mavi zemin / metin yok.
ButtonStyle dialogTonalButtonStyle(
  BuildContext context, {
  AppTone tone = AppTone.primary,
}) {
  final p = context.palette;
  return OutlinedButton.styleFrom(
    foregroundColor: tone.isStatus ? tone.ink(p) : p.text,
    backgroundColor: p.surface,
    disabledForegroundColor: p.textSecondary,
    disabledBackgroundColor: p.surfaceMuted,
    minimumSize: const Size(0, 48),
    side: BorderSide(color: p.border),
  );
}

/// Küçük bir alanın yüklenme göstergesi: tek satırlık iskelet + açıklama metni. Yalnız yükleme
/// sürerken ağaçta durmalıdır (paylaşılan tek shimmer; kapsam ağaçtan çıkınca ticker durur).
class DialogLoadingNote extends StatelessWidget {
  const DialogLoadingNote({super.key, required this.text});

  /// Mevcut yükleme metni ("Yöneticiler yükleniyor..." vb.) birebir geçer.
  final String text;

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SkeletonBox(height: 48, radius: AppRadius.sm),
          const SizedBox(height: AppSpace.sm),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Liste yükleme iskeleti: [rows] panel satırı (rozet + iki metin satırı) + isteğe bağlı açıklama.
/// Yalnız yükleme sürerken ağaçta durmalıdır (paylaşılan tek shimmer).
class DialogRowsSkeleton extends StatelessWidget {
  const DialogRowsSkeleton({super.key, this.rows = 3, this.caption});

  final int rows;

  /// Mevcut yükleme metni (örn. "Kapı yetkileri yükleniyor...") birebir geçer; null ise yok.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final caption = this.caption;
    return ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            DialogPanel(
              child: Row(
                children: [
                  const SkeletonBox(width: 40, height: 40, radius: AppRadius.sm),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        FractionallySizedBox(
                          widthFactor: 0.6,
                          alignment: Alignment.centerLeft,
                          child: SkeletonBox(),
                        ),
                        SizedBox(height: AppSpace.sm),
                        FractionallySizedBox(
                          widthFactor: 0.4,
                          alignment: Alignment.centerLeft,
                          child: SkeletonBox(height: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
