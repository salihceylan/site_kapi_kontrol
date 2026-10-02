// FAZ 5 / A1b (i): kart yüzeyi, bölüm başlığı ve satır içi bildirim.
//
// - [AppCard]: tüm kart yüzeylerinin tek karşılığı. Opak yüzey + tek katman gölge (BackdropFilter,
//   Opacity, spread, çift gölge YOK); rol/ton şeridi 3 dp.
// - [SectionHeader]: başlık + sayaç rozeti + eylem. Başlık ve rozet KIRPILMAZ: sığmazsa alt satıra
//   iner; metinli eylem de başlığın altına düşer.
// - [InlineNotice]: form/hata/başarı kutusu (ikon + metin, >= 4,5:1, canlı bölge, "Tekrar Dene").
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kart yüzeyi.
///
/// Durumlar: varsayılan | hover/odak ([onTap] varsa `InkWell`: fare ve klavye) | [selected] (1,5 px
/// kenar + en az seviye 2 yükselti) | [tone] (uyarı/hata tonlu zemin ve kenar) | devre dışı
/// ([onTap] null: dokunulamaz; soluk içerik çağıranın işidir). Yükleme ve boş içerik kartın değil
/// `SkeletonBox`/`EmptyState`in işidir.
///
/// Taşma: [child]'a sabit yükseklik verilmez, kart içeriği kadar uzar. Dar kartta çağıran
/// `padding: EdgeInsets.all(AppSpace.md)` verir. Üst öğe sınırlı genişlikte olmalıdır (Column/ListView
/// çocuğu); gevşek genişlikte (örn. `Scaffold` gövdesi) kart içeriği kadar dardır.
///
/// Erişilebilirlik: [onTap] varsa düğme + dokunma eylemi, en az 48 dp yükseklik; [selected] varsa
/// "seçili". [semanticLabel] verilirse kartın birleşik özeti olarak içeriğin okunmasına EKLENİR (içerik
/// dışlanmaz: kart içindeki düğmeler erişilebilir kalır). Hareket azaltma: kart statiktir; seçili
/// durum geçişi (kenar/zemin) 200 ms sürer, hareket azaltmada anında olur.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.tone,
    this.accentBar,
    this.selected = false,
    this.level = 1,
    this.onTap,
    this.semanticLabel,
  }) : assert(level >= 1 && level <= 3, 'Yükselti seviyesi 1..3 olmalı');

  final Widget child;

  /// İç boşluk (varsayılan 16; dar kartta 12).
  final EdgeInsetsGeometry padding;

  /// Tonlu kart (örn. cihazsız site: warning, hata: danger): soluk ton zemini + ton kenarı.
  final AppTone? tone;

  /// Kartın üstünde 3 dp'lik şerit rengi (rol vurgusu: `role.tone.hue`). null ise şerit yok.
  final Color? accentBar;

  /// Seçili kart: 1,5 px birincil kenar ve en az seviye 2 yükselti.
  final bool selected;

  /// Yükselti 1..3 (1 kart, 2 seçili/birincil, 3 diyalog/sheet). Koyu temada daha açık yüzey.
  final int level;

  /// null ise kart dokunulamaz ve `InkWell` eklenmez.
  final VoidCallback? onTap;

  /// Kartın birleşik erişilebilirlik özeti (yalnız gerekirse).
  final String? semanticLabel;

  /// Seçili kart en az seviye 2 çizilir; daha yüksek seviye verilmişse düşürülmez.
  int get _effectiveLevel => selected && level < 2 ? 2 : level;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = this.tone;
    final bar = accentBar;
    final tap = onTap;
    final radius = BorderRadius.circular(AppRadius.lg);
    final lvl = _effectiveLevel;

    Widget body = Padding(padding: padding, child: child);
    if (bar != null) {
      // passthrough: sınırlar şeritsiz kartla birebir aynı iletilir (düzen şeride bağlı değişmez).
      body = Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 3,
            child: ColoredBox(color: bar),
          ),
        ],
      );
    }
    if (tap != null) {
      body = InkWell(
        onTap: tap,
        borderRadius: radius,
        child: ConstrainedBox(
          // Dokunma hedefi >= 44 dp: padding'siz küçük içerikte de.
          constraints: const BoxConstraints(minHeight: 48),
          child: body,
        ),
      );
    }

    return Semantics(
      container: true,
      button: tap != null ? true : null,
      selected: selected ? true : null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: p.shadow(lvl),
        ),
        child: Material(
          color: tone == null
              ? p.surfaceAt(lvl)
              : Color.alphaBlend(tone.tint(p), p.surface),
          clipBehavior: Clip.antiAlias,
          animationDuration: AppMotion.of(context, AppMotion.base),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              width: selected ? 1.5 : 1,
              color: selected
                  ? AppTone.primary.ink(p)
                  : (tone?.hue.withValues(alpha: 0.5) ?? p.border),
            ),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// Bölüm başlığı: [icon] + [title] + sayaç rozeti + [trailing] eylemi.
///
/// Başlık ve rozet bir arada akar (rozet başlığa sığmazsa onunla birlikte alt satıra iner); başlık
/// en çok 3 satır (büyük yazı + dar ekranda bile kırpılmaz), rozet hiçbir zaman kırpılmaz.
/// [trailing] genişliğin en çok %40'ını kaplıyorsa (1-2 `IconButton`, kısa metinli eylem) başlık
/// satırının SONUNDA, dikeyde ortalı durur ve başlık/rozet kalan genişliğe esner (gerekirse başlık
/// birkaç satıra, rozet altına iner); daha genişse (dar ekran + büyük yazıda metinli eylem)
/// başlığın ALTINA, sola hizalı düşer. Çağıranın `Wrap` vermesi gerekmez. [trailing]: en çok 2
/// `IconButton` (44 dp) ya da 1 `TextButton`.
///
/// Sayaç değişince [AnimatedCount] akar (hareket azaltmada anında). Erişilebilirlik: başlık ve
/// sayaç tek "başlık" düğümüdür ("başlık, 3 Kapı"); [trailing] ayrı ve erişilebilir kalır.
///
/// Sınırlı genişlikte (Column/ListView çocuğu ya da Expanded) tüm genişliği kaplar; sınırsız
/// genişlikte (yatay kaydırma) içeriği kadar geniştir. Yön soldan sağadır (LTR).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.countSuffix = '',
    this.icon,
    this.trailing,
  });

  final String title;

  /// Başlığın yanındaki sayaç rozeti (örn. kapı sayısı). null ise rozet yok.
  final int? count;

  /// Sayının arkasına eklenen sabit metin (örn. " Kapı").
  final String countSuffix;

  final IconData? icon;

  /// En çok 2 `IconButton` ya da 1 `TextButton`.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    const tone = AppTone.primary;
    final count = this.count;
    final trailing = this.trailing;

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: p.textSecondary),
          const SizedBox(width: AppSpace.sm),
        ],
        Flexible(
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: th.titleLarge,
          ),
        ),
      ],
    );

    final Widget titleBlock = count == null
        ? titleRow
        : Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              titleRow,
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.tint(p),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: AppSpace.xs / 2,
                  ),
                  child: AnimatedCount(
                    value: count,
                    suffix: countSuffix,
                    style: th.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tone.ink(p),
                    ),
                  ),
                ),
              ),
            ],
          );

    final header = Semantics(
      header: true,
      label: count == null ? title : '$title, $count$countSuffix',
      excludeSemantics: true,
      child: titleBlock,
    );

    return _HeaderFlow(children: [header, ?trailing]);
  }
}

/// [SectionHeader] düzeni: başlık bloğu (1. çocuk) + isteğe bağlı eylem (2. çocuk).
///
/// Eylem ÖNCE doğal (gevşek) boyutuyla ölçülür. Genişliğin en çok [_RenderHeaderFlow._inlineFraction]
/// oranını kaplıyorsa aynı satırda, sonda ve dikeyde ortalı durur; başlık bloğu kalan genişlikle
/// sınırlanır (başlık sarar, rozet altına iner). Aksi hâlde başlık tüm genişliği alır ve eylem
/// başlığın altına, sola hizalı yerleşir. `Row` (eylem geniş olunca başlığı ezer) ve `Wrap`
/// (doğal genişliğe bakıp simge düğmesini gereksiz yere alta atar) bu kararı veremez.
class _HeaderFlow extends MultiChildRenderObjectWidget {
  const _HeaderFlow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderFlow();
}

class _HeaderFlowParentData extends ContainerBoxParentData<RenderBox> {}

/// [_RenderHeaderFlow] yerleşim planı (gerçek ve kuru yerleşim aynı hesabı kullanır).
typedef _HeaderPlan = ({
  Size size,
  Offset lead,
  Offset trail,
  BoxConstraints leadConstraints,
});

class _RenderHeaderFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderFlowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderFlowParentData> {
  /// Eylem genişliğin en çok bu oranını kaplıyorsa başlıkla aynı satırda durur.
  static const double _inlineFraction = 0.4;

  /// Yan yana durumda başlık ile eylem arası, alt alta durumda iki satır arası boşluk.
  static const double _gap = AppSpace.sm;
  static const double _stackGap = AppSpace.xs;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderFlowParentData) {
      child.parentData = _HeaderFlowParentData();
    }
  }

  _HeaderPlan _plan(BoxConstraints constraints, ChildLayouter layoutChild) {
    final lead = firstChild!;
    final trail = childAfter(lead);
    final maxWidth = constraints.maxWidth;
    final bounded = maxWidth.isFinite;

    if (trail == null) {
      final leadConstraints = BoxConstraints(maxWidth: maxWidth);
      final leadSize = layoutChild(lead, leadConstraints);
      return (
        size: constraints.constrain(
          Size(bounded ? maxWidth : leadSize.width, leadSize.height),
        ),
        lead: Offset.zero,
        trail: Offset.zero,
        leadConstraints: leadConstraints,
      );
    }

    final trailSize = layoutChild(trail, BoxConstraints(maxWidth: maxWidth));
    if (!bounded || trailSize.width <= maxWidth * _inlineFraction) {
      final leadConstraints = BoxConstraints(
        maxWidth: bounded
            ? math.max(0.0, maxWidth - trailSize.width - _gap)
            : double.infinity,
      );
      final leadSize = layoutChild(lead, leadConstraints);
      final size = constraints.constrain(
        Size(
          bounded ? maxWidth : leadSize.width + _gap + trailSize.width,
          math.max(leadSize.height, trailSize.height),
        ),
      );
      return (
        size: size,
        lead: Offset(0, (size.height - leadSize.height) / 2),
        trail: Offset(
          size.width - trailSize.width,
          (size.height - trailSize.height) / 2,
        ),
        leadConstraints: leadConstraints,
      );
    }

    final leadConstraints = BoxConstraints(maxWidth: maxWidth);
    final leadSize = layoutChild(lead, leadConstraints);
    return (
      size: constraints.constrain(
        Size(maxWidth, leadSize.height + _stackGap + trailSize.height),
      ),
      lead: Offset.zero,
      trail: Offset(0, leadSize.height + _stackGap),
      leadConstraints: leadConstraints,
    );
  }

  @override
  void performLayout() {
    final plan = _plan(constraints, ChildLayoutHelper.layoutChild);
    size = plan.size;
    final lead = firstChild!;
    (lead.parentData! as _HeaderFlowParentData).offset = plan.lead;
    final trail = childAfter(lead);
    if (trail != null) {
      (trail.parentData! as _HeaderFlowParentData).offset = plan.trail;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _plan(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final plan = _plan(constraints, ChildLayoutHelper.dryLayoutChild);
    final base = firstChild!.getDryBaseline(plan.leadConstraints, baseline);
    return base == null ? null : base + plan.lead.dy;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final lead = firstChild!;
    final base = lead.getDistanceToActualBaseline(baseline);
    return base == null
        ? null
        : base + (lead.parentData! as _HeaderFlowParentData).offset.dy;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var width = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      width = math.max(width, c.getMinIntrinsicWidth(height));
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final lead = firstChild!;
    final trail = childAfter(lead);
    return lead.getMaxIntrinsicWidth(height) +
        (trail == null ? 0 : _gap + trail.getMaxIntrinsicWidth(height));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// Satır içi bildirim: hata/başarı/uyarı/bilgi kutusu (ikon + metin).
///
/// Soluk ton zemini (opak: arkasındaki yüzeyden bağımsız aynı renk) + ton kenarı + `ink` metin
/// (>= 4,5:1). Girişte [Pop] ile belirir; mesaj (ya da ton) değişince yeniden belirir. AYNI mesaj
/// art arda tekrarlanıyorsa yeniden belirmesi için çağıran bir `key` verir (örn. deneme sayacı).
/// [onRetry] verilirse "Tekrar Dene" düğmesi metnin ALTINDA hizalanır (dar ekranda yan yana değil;
/// en az 48 dp).
///
/// Erişilebilirlik: canlı bölge (mesaj değişince ekran okuyucu okur); renk tek başına anlam taşımaz
/// (ikon + metin). Metin kırpılmaz, sınırsız satıra sarar. Üst öğe sınırlı genişlikte olmalıdır.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.tone = AppTone.danger,
    this.onRetry,
    this.icon,
  });

  /// Gösterilen metin (mevcut hata/başarı cümleleri birebir geçer).
  final String message;

  /// danger (hata), success (başarı), warning (uyarı), info (bilgi).
  final AppTone tone;

  /// Verilirse "Tekrar Dene" düğmesi gösterilir.
  final VoidCallback? onRetry;

  /// Tonun varsayılan ikonunu değiştirir.
  final IconData? icon;

  static IconData _defaultIcon(AppTone tone) => switch (tone) {
    AppTone.danger => Icons.error_outline_rounded,
    AppTone.success => Icons.check_circle_outline_rounded,
    AppTone.warning => Icons.warning_amber_rounded,
    _ => Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final ink = tone.ink(p);
    final retry = onRetry;

    return Pop(
      key: ValueKey<String>('${tone.name}|$message'),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(tone.tint(p), p.surface),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: tone.hue.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon ?? _defaultIcon(tone), size: 20, color: ink),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: th.bodyMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (retry != null)
                        TextButton.icon(
                          onPressed: retry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Tekrar Dene'),
                          style: TextButton.styleFrom(
                            foregroundColor: ink,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(64, 48),
                            alignment: AlignmentDirectional.centerStart,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
