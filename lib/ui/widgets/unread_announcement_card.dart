import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Sakin Panel'inin en üstündeki "Yeni duyuru" kartı: en yeni OKUNMAMIŞ (acil olmayan) duyurunun başlığı, kısa
/// özeti ve "Oku" eylemi; birden çok okunmamış varsa "+N duyuru daha" Duyurular ekranına gider.
///
/// Dikkat çekme (SINIRLI, gölgesiz): 2 dp kenar çerçevesi ile "Yeni duyuru" önündeki nokta, [blinkDuration] (4,8 sn)
/// boyunca 3 kez soluk renkten ana eylem rengine yanıp söner (tur ~1,9 sn = ~0,5 Hz; WCAG 2.3.1'in 3 Hz sınırının
/// çok altı, 2.2.2'nin 5 sn sınırının altı), sonra DURAĞAN vurgulu kalır (sonsuz efekt yok; TASARIM_DILI §2). Duyuru
/// kimliği değişince ya da kart yeniden kurulunca yeniden başlar. `MediaQuery.disableAnimationsOf` açıkken ya da
/// [pulse] false iken doğrudan durağan vurgulu çizilir.
///
/// Erişilebilirlik: kart canlı bölge değildir; kapsayıcının etiketi `Yeni duyuru: başlık`, "Oku" ve
/// "+N duyuru daha" odaklanabilir düğmelerdir. Renk tek başına anlam taşımaz (simge + "Yeni duyuru" metni).
class UnreadAnnouncementCard extends StatefulWidget {
  const UnreadAnnouncementCard({
    super.key,
    required this.announcement,
    required this.onOpen,
    this.moreCount = 0,
    this.onOpenAll,
    this.pulse,
  });

  /// Yanıp sönmenin toplam süresi (3 tepe); bitince durağan vurgu.
  static const Duration blinkDuration = Duration(milliseconds: 4800);

  /// Yanıp sönme sayısı (tepe): 3. tepe durağan hâl olarak kalır.
  static const int blinkCount = 3;

  final ResidentAnnouncement announcement;

  /// "Oku": duyuruyu açar (okundu yazılınca kart kalkar).
  final VoidCallback onOpen;

  /// Kartta gösterilmeyen okunmamış duyuru sayısı; 0 ise "+N duyuru daha" çıkmaz.
  final int moreCount;

  /// "+N duyuru daha": Duyurular ekranına gider.
  final VoidCallback? onOpenAll;

  /// false ise yanıp sönmeden durağan vurgulu çizilir (null = açık).
  final bool? pulse;

  @override
  State<UnreadAnnouncementCard> createState() => _UnreadAnnouncementCardState();
}

class _UnreadAnnouncementCardState extends State<UnreadAnnouncementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: UnreadAnnouncementCard.blinkDuration,
  );
  bool _started = false;

  bool _wantsMotion(BuildContext context) =>
      (widget.pulse ?? true) && !MediaQuery.disableAnimationsOf(context);

  /// Yanıp sönmeyi baştan başlatır (hareket istenmiyorsa doğrudan durağan vurgu).
  void _restart() {
    if (_wantsMotion(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _restart();
    } else if (!_wantsMotion(context) && _controller.isAnimating) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(UnreadAnnouncementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.id != widget.announcement.id) _restart();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 (soluk) .. 1 (vurgulu). Yarım tur kaydırılmış kosinüs: 3 tepe verir ve tam 1'de biter (durağan vurgu ile sürekli).
  double _intensity() {
    final t = _controller.value;
    if (t >= 1) return 1;
    return 0.5 - 0.5 * math.cos(2 * math.pi * (UnreadAnnouncementCard.blinkCount - 0.5) * t);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final a = widget.announcement;
    final title = a.title.trim().isEmpty ? 'Başlıksız duyuru' : a.title.trim();
    final preview = a.previewOrBody.trim();

    return Semantics(
      container: true,
      label: 'Yeni duyuru: $title',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final accent = Color.lerp(p.border, p.action, _intensity())!;
          return Material(
            key: const ValueKey<String>('unread_announcement_card_surface'),
            color: p.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: accent, width: 2),
            ),
            child: Padding(
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
                              decoration: BoxDecoration(shape: BoxShape.circle, color: p.surfaceMuted),
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(Icons.campaign_rounded, size: 20, color: p.textSecondary),
                              ),
                            ),
                            const SizedBox(width: AppSpace.sm),
                            DecoratedBox(
                              key: const ValueKey<String>('unread_announcement_dot'),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                              child: const SizedBox(width: 8, height: 8),
                            ),
                            const SizedBox(width: AppSpace.xs),
                            Expanded(
                              child: Text(
                                'Yeni duyuru',
                                style: th.labelLarge?.copyWith(
                                  color: p.text,
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
            ),
          );
        },
      ),
    );
  }
}
