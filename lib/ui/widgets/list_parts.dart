// FAZ 5 / A2-G3: liste ekranlarının (site, kullanıcı, cihaz, talep) ortak parçaları.
//
// Aynı desen 6 dosyada kopyalanmasın diye burada toplandı: sayfa başlık kartı, genişleyen kart gövdesi
// + dönen ok, bilgi çipi, sayfalama çubuğu, baş harf avatarı, ikon karosu, liste iskeleti, boş durum
// kartı ve eylem düğmesi stilleri. Hepsi `lib/ui/design` bileşenleri ve tokenları üzerine kurulur:
// ham renk yoktur, her süre `AppMotion.of` üzerinden geçer (hareket azaltmada anında).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Büyük yazı (>= 1,75x): dekoratif karo/avatar gizlenir, metne ~56 dp daha yer kalır (320 dp x 2,0
/// ölçekte çip etiketleri ve başlıklar kırpılmadan sığar). Anlam taşımayan süstür: ekran okuyucuya
/// zaten kapalıdır.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= 1.75;

/// Kart iç boşluğu: dar ekranda 12, normalde 16 (taşma güvenliği).
EdgeInsets listCardPadding(BuildContext context) => EdgeInsets.all(
  MediaQuery.sizeOf(context).width < 360 ? AppSpace.md : AppSpace.lg,
);

/// Sayfa başlık kartı: [title] + isteğe bağlı birincil eylem ([action], genellikle `ElevatedButton.icon`).
///
/// Dar ekranda (< 680) eylem başlığın altında tam genişlikte, geniş ekranda sağda durur. Başlık
/// kırpılmaz (en çok 3 satır). Kartın tek dolu düğmesi eylemdir.
class PageHeaderCard extends StatelessWidget {
  const PageHeaderCard({super.key, required this.title, this.action});

  final String title;

  /// null ise yalnız başlık gösterilir.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final compact = MediaQuery.sizeOf(context).width < 680;
    final Widget content;
    if (action == null) {
      content = SectionHeader(title: title);
    } else if (compact) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          const SizedBox(height: AppSpace.md),
          SizedBox(width: double.infinity, child: action),
        ],
      );
    } else {
      content = Row(
        children: [
          Expanded(child: SectionHeader(title: title)),
          const SizedBox(width: AppSpace.md),
          action,
        ],
      );
    }
    return AppCard(child: content);
  }
}

/// Genişleyen/daralan kart gövdesi.
///
/// [expanded] false iken [child] ağaçta YOKTUR (kapalı kartın metinleri/düğmeleri bulunamaz: testler
/// ve e2e kartın açık olup olmadığını buradan anlar); true olunca yükseklik 200 ms'de açılır, kapanırken
/// içerik görünür kalarak daralır ve animasyon bitince ağaçtan kalkar. Hareket azaltmada anında.
class ExpandableSection extends StatelessWidget {
  const ExpandableSection({
    super.key,
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: expanded ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      child: child,
      builder: (context, t, child) {
        if (t <= 0 && !expanded) return const SizedBox(width: double.infinity);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t.clamp(0.0, 1.0),
            child: SizedBox(width: double.infinity, child: child),
          ),
        );
      },
    );
  }
}

/// Açılır kartın sağındaki ok: [expanded] iken yarım tur döner (200 ms). Dekoratiftir.
class ExpandChevron extends StatelessWidget {
  const ExpandChevron({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.standard,
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: context.palette.textSecondary,
        ),
      ),
    );
  }
}

/// Bilgi çipi ("Kullanıcı ID: 5", "Yerel IP: ..."): [tone] null ise nötr soluk kutu, doluysa tonlu.
///
/// Metin KIRPILMAZ, sığmayınca satırlara sarar (çok uzun tek sözcük de karakterden bölünür); sabit
/// genişlik yoktur: `Wrap` içinde kullanın. Kontrast: nötr çip `textSecondary` (>= 4,5:1), tonlu çip
/// `ink` (>= 4,5:1).
class InfoChip extends StatelessWidget {
  const InfoChip(this.label, {super.key, this.tone});

  final String label;
  final AppTone? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = this.tone;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone == null
            ? p.surfaceMuted
            : Color.alphaBlend(tone.tint(p), p.surface),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: tone == null ? p.border : tone.hue.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: tone == null ? p.textSecondary : tone.ink(p),
          ),
        ),
      ),
    );
  }
}

/// Sayfalama çubuğu: "Sayfa 1 / 3 | Toplam 25" metni + önceki/sonraki simge düğmeleri (44 dp, ipucu
/// "Önceki sayfa" / "Sonraki sayfa"). [onPrevious]/[onNext] null ise düğme devre dışıdır. Dar ekranda
/// düğmeler metnin altına iner (`Wrap`).
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    const size = BoxConstraints(minWidth: 44, minHeight: 44);
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(
              onPressed: onPrevious,
              tooltip: 'Önceki sayfa',
              constraints: size,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: AppSpace.sm),
            IconButton.outlined(
              onPressed: onNext,
              tooltip: 'Sonraki sayfa',
              constraints: size,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

/// Baş harfli yuvarlak avatar; rengi [tone] (rol/durum). Büyük yazıda büyümez (CircleAvatar
/// yazı ölçeğini kapatır): daire sabit [radius] kalır; çok büyük yazıda (>= 1,75x) gizlenir.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    required this.tone,
    this.radius = 20,
    this.gap = 0,
  });

  final String name;
  final AppTone tone;
  final double radius;

  /// Avatarın sağındaki boşluk (avatarla birlikte gizlenir).
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (isLargeText(context)) return const SizedBox.shrink();
    final p = context.palette;
    final trimmed = name.trim();
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.only(right: gap),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Color.alphaBlend(tone.tint(p), p.surface),
          child: Text(
            trimmed.isEmpty ? '?' : trimmed[0].toUpperCase(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: tone.ink(p),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kart başındaki ton zeminli yuvarlak ikon karosu (dekoratif, [size] x [size]); büyük yazıda gizlenir.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.tone = AppTone.primary,
    this.size = 44,
    this.iconSize = 22,
    this.gap = 0,
  });

  final IconData icon;
  final AppTone tone;
  final double size;
  final double iconSize;

  /// Karonun sağındaki boşluk (karoyla birlikte gizlenir).
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (isLargeText(context)) return const SizedBox.shrink();
    final p = context.palette;
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.only(right: gap),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone.tint(p),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(icon, size: iconSize, color: tone.ink(p)),
            ),
          ),
        ),
      ),
    );
  }
}

/// İlk yükleme iskeleti: [rows] kart satırı (avatar + iki metin satırı). Yalnız yükleme sürerken
/// ağaçta durmalıdır (tek paylaşılan shimmer kontrolcüsü, `ShimmerScope`). [inCard] true ise satırlar
/// kart çizmez (zaten bir kartın içinde kullanılır).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 3, this.inCard = false});

  final int rows;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    Widget row() => Row(
      children: [
        const SkeletonBox(width: 44, height: 44, radius: AppRadius.pill),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: 0.6,
                alignment: Alignment.centerLeft,
                child: const SkeletonBox(),
              ),
              const SizedBox(height: AppSpace.sm),
              FractionallySizedBox(
                widthFactor: 0.4,
                alignment: Alignment.centerLeft,
                child: const SkeletonBox(height: 12),
              ),
            ],
          ),
        ),
      ],
    );

    return ShimmerScope(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : AppSpace.md),
              child: inCard
                  ? row()
                  : SizedBox(
                      width: double.infinity,
                      child: AppCard(child: row()),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Boş liste durumu kartı: ikon karosu + [title] (+ [message]) tek kartta, ortalı.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = AppTone.primary,
    this.child,
  });

  final IconData icon;
  final String title;
  final String? message;
  final AppTone tone;

  /// Metnin altına konan eylem (örn. tema düğmesi); null ise yok.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(icon: icon, title: title, message: message, tone: tone),
            if (child != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpace.lg,
                  right: AppSpace.lg,
                  bottom: AppSpace.xl,
                ),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

/// İkincil (yönetim) eylemi: ton zeminli düğme. `ElevatedButton/OutlinedButton/FilledButton`'ın
/// `style:`'ına verilir; düğme tipi (test bulucuları) değişmez. En az 44 dp yükseklik.
ButtonStyle tonalActionStyle(
  BuildContext context, {
  AppTone tone = AppTone.primary,
}) {
  final p = context.palette;
  return OutlinedButton.styleFrom(
    foregroundColor: tone.ink(p),
    backgroundColor: Color.alphaBlend(tone.tint(p), p.surface),
    disabledForegroundColor: p.textSecondary,
    disabledBackgroundColor: p.surfaceMuted,
    elevation: 0,
    minimumSize: const Size(0, 44),
  ).copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? p.border
            : tone.hue.withValues(alpha: 0.35),
      ),
    ),
  );
}

/// Yıkıcı eylem (sil, reddet, iptal): danger kenarlı, `ink` metinli çerçeveli düğme.
ButtonStyle dangerOutlineStyle(BuildContext context) {
  final p = context.palette;
  const tone = AppTone.danger;
  return OutlinedButton.styleFrom(
    foregroundColor: tone.ink(p),
    disabledForegroundColor: p.textSecondary,
    minimumSize: const Size(0, 44),
  ).copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? p.border
            : tone.hue.withValues(alpha: 0.5),
        width: 1.2,
      ),
    ),
  );
}

/// Dolu eylem (onayla, kaydet, sil onayı): ton gradyanının koyu ucu zemin, beyaz metin (>= 4,5:1);
/// devre dışıyken palet nötrü (önceki sürümde devre dışı dolu düğme etkin gibi görünüyordu).
ButtonStyle filledToneStyle(
  BuildContext context, {
  AppTone tone = AppTone.primary,
}) {
  final p = context.palette;
  return ElevatedButton.styleFrom(
    backgroundColor: tone.a,
    foregroundColor: Colors.white,
    disabledBackgroundColor: p.border,
    disabledForegroundColor: p.textSecondary,
    // Düz dolgu: tema gölgesi (mavi, yükselti 2-4) tonlu düğmede yanlış renkli halka çiziyordu.
    elevation: 0,
    shadowColor: Colors.transparent,
    minimumSize: const Size(0, 44),
  );
}
