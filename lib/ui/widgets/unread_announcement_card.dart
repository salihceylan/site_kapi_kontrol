import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Sakin Panel'inin en üstündeki "Yeni duyuru" kartı: en yeni OKUNMAMIŞ (acil olmayan) duyurunun başlığı, kısa
/// özeti ve "Oku" eylemi; birden çok okunmamış varsa "+N duyuru daha" Duyurular ekranına gider.
///
/// Dikkat çekme: kartın çevresindeki parıltı yumuşakça nabız atar (saydamlık + yayılım; yarım tur [pulseHalfPeriod],
/// tam tur ~3 sn = 0,33 Hz; saniyede 3'ten çok yanıp sönen sert flaş YOK). `MediaQuery.disableAnimationsOf` açıkken,
/// [pulse] false iken ya da [pulseEnabledByDefault] kapalıyken (widget testleri) hareketsiz, VURGULU çizilir.
///
/// Erişilebilirlik: kart canlı bölge değildir; kapsayıcının etiketi `Yeni duyuru: başlık`, "Oku" ve
/// "+N duyuru daha" odaklanabilir düğmelerdir. Renk tek başına anlam taşımaz (simge + "Yeni duyuru" metni).
///
/// [flat] (Panel modül vitrini): gölgesiz düz yüzey + ince çerçeve, nabız / parıltı YOK (vitrinin "sakin ferahlık"
/// kuralı: göz koyu odak kutusundan hareketli karta kaymasın). İçerik ve düğmeler aynıdır; varsayılan (false) eski
/// görünümdür.
class UnreadAnnouncementCard extends StatefulWidget {
  const UnreadAnnouncementCard({
    super.key,
    required this.announcement,
    required this.onOpen,
    this.moreCount = 0,
    this.onOpenAll,
    this.pulse,
    this.flat = false,
  });

  /// Nabız animasyonunun varsayılanı. Uygulamada açıktır; sonsuz animasyon `pumpAndSettle`ı bitirmediği için
  /// `test/flutter_test_config.dart` bunu kapatır (animasyonu sınayan testler `pulse: true` verir).
  static bool pulseEnabledByDefault = true;

  /// Parıltının tek yönlü (sönükten parlağa) süresi; tam tur bunun iki katıdır.
  static const Duration pulseHalfPeriod = Duration(milliseconds: 1500);

  final ResidentAnnouncement announcement;

  /// "Oku": duyuruyu açar (okundu yazılınca kart kalkar).
  final VoidCallback onOpen;

  /// Kartta gösterilmeyen okunmamış duyuru sayısı; 0 ise "+N duyuru daha" çıkmaz.
  final int moreCount;

  /// "+N duyuru daha": Duyurular ekranına gider.
  final VoidCallback? onOpenAll;

  /// null ise [pulseEnabledByDefault].
  final bool? pulse;

  /// Düz vitrin görünümü: gölge, ton zemini ve nabız yok (bkz. sınıf açıklaması).
  final bool flat;

  @override
  State<UnreadAnnouncementCard> createState() => _UnreadAnnouncementCardState();
}

class _UnreadAnnouncementCardState extends State<UnreadAnnouncementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: UnreadAnnouncementCard.pulseHalfPeriod,
    value: 1,
  );

  bool _wantsMotion(BuildContext context) =>
      !widget.flat &&
      (widget.pulse ?? UnreadAnnouncementCard.pulseEnabledByDefault) &&
      !MediaQuery.disableAnimationsOf(context);

  void _sync() {
    if (_wantsMotion(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 1; // durağan ama vurgulu
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(UnreadAnnouncementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final a = widget.announcement;
    final title = a.title.trim().isEmpty ? 'Başlıksız duyuru' : a.title.trim();
    final preview = a.previewOrBody.trim();
    const tone = AppTone.primary;

    final content = Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık satırı: ekran okuyucuya kapsayıcı etiketi okunur (iki kez okunmaz).
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: tone.tint(p)),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(Icons.campaign_rounded, size: 20, color: tone.ink(p)),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Yeni duyuru',
                        style: th.labelLarge?.copyWith(
                          color: tone.ink(p),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  title,
                  key: const ValueKey<String>('unread_announcement_title'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: th.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey<String>('unread_announcement_open'),
                onPressed: widget.onOpen,
                icon: const Icon(Icons.drafts_rounded, size: 18),
                label: const Text('Oku'),
              ),
              if (widget.moreCount > 0 && widget.onOpenAll != null)
                TextButton(
                  key: const ValueKey<String>('unread_announcement_more'),
                  onPressed: widget.onOpenAll,
                  child: Text('+${widget.moreCount} duyuru daha'),
                ),
            ],
          ),
        ],
      ),
    );

    if (widget.flat) {
      // Vitrin: düz yüzey + ince çerçeve; gölge, ton yıkaması ve nabız yok.
      return Semantics(
        container: true,
        label: 'Yeni duyuru: $title',
        child: Material(
          key: const ValueKey<String>('unread_announcement_card_surface'),
          color: p.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: p.border),
          ),
          child: content,
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Yeni duyuru: $title',
      child: AnimatedBuilder(
        animation: _controller,
        child: AppCard(
          key: const ValueKey<String>('unread_announcement_card_surface'),
          tone: tone,
          level: 2,
          padding: EdgeInsets.zero,
          child: content,
        ),
        builder: (context, child) {
          final v = Curves.easeInOut.transform(_controller.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: tone.hue.withValues(alpha: 0.14 + 0.38 * v),
                  blurRadius: 4 + 12 * v,
                  spreadRadius: 2 * v,
                ),
              ],
            ),
            child: child,
          );
        },
      ),
    );
  }
}
