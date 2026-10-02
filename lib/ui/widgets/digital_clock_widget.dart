import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../design/app_card.dart';
import '../design/status_chip.dart';
import '../design/tokens.dart';

class DigitalClockWidget extends StatefulWidget {
  const DigitalClockWidget({
    super.key,
    required this.session,
    this.showUserInfo = true,
    this.nowProvider = DateTime.now,
  });

  final UserSession session;
  final bool showUserInfo;

  /// Şimdiki zaman kaynağı (testlerde sanal saat verilir; üretimde sistem saati).
  final DateTime Function() nowProvider;

  @override
  State<DigitalClockWidget> createState() => _DigitalClockWidgetState();
}

class _DigitalClockWidgetState extends State<DigitalClockWidget>
    with WidgetsBindingObserver {
  // Saniyelik güncelleme yalnız bu iki dinleyiciyi (saat metni, tarih metni) yeniden kurar; kart
  // iskeleti (dekorasyon, gölge, kullanıcı satırı) her saniye yeniden kurulmaz. Tarih yalnız gün
  // değişince bildirir (ValueNotifier eşit değeri yayınlamaz).
  late final ValueNotifier<String> _timeText;
  late final ValueNotifier<String> _dateText;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = widget.nowProvider();
    _timeText = ValueNotifier<String>(_formatTime(now));
    _dateText = ValueNotifier<String>(_formatTurkishDate(now));
    _startTimer();
  }

  void _tick() {
    if (!mounted) return;
    final now = widget.nowProvider();
    _timeText.value = _formatTime(now);
    _dateText.value = _formatTurkishDate(now);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _timeText.dispose();
    _dateText.dispose();
    super.dispose();
  }

  String _formatTurkishDate(DateTime dt) {
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar'
    ];
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
    ];

    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '${dt.day} $monthName ${dt.year}, $dayName';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: saniyelik metin güncellemesi ve sayfa kaydırması kartın gölgeli
    // katmanını birbirine yeniden çizdirmez.
    return RepaintBoundary(child: _buildCard(context));
  }

  // Üst satır yerleşimi için doğal genişlik tahminleri (dp; yazı ölçeğiyle büyür): saat bloğu =
  // simge karosu 34 + boşluk 8 + 8 monospace hane; rozet = bayrak + rozet dolgusu/ikon + etiket.
  static const double _timeBlockBase = 42;
  static const double _timeTextWidth = 122;
  static const double _badgeBase = 42;
  static const double _badgeTextWidth = 97;

  /// Tek satıra sığması için saat bloğunun en çok bu orana (%85) kadar küçülmesi kabul edilir.
  static const double _minInlineShrink = 0.85;

  /// Saat + saat dilimi rozeti. Yan yana en çok ~%15 küçülerek sığıyorsa tek satır (kompakt); sığmıyorsa
  /// (büyük yazı / dar ekran) rozet alt satıra iner ve saat okunaklı kalır. Düzen kararı yalnız
  /// kısıtlar/yazı ölçeği değişince yeniden verilir (saniyelik güncellemede değil).
  Widget _buildTopRow(BuildContext context, Widget timeBlock, Widget zoneBadge) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final timeWidth = _timeBlockBase + _timeTextWidth * scale;
        final badgeWidth = _badgeBase + _badgeTextWidth * scale;
        final shrink = (constraints.maxWidth - AppSpace.sm - badgeWidth) / timeWidth;
        if (constraints.hasBoundedWidth && shrink >= _minInlineShrink) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: timeBlock),
              ),
              const SizedBox(width: AppSpace.sm),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
                child: zoneBadge,
              ),
            ],
          );
        }
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [timeBlock, zoneBadge],
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final tone = widget.session.role.tone;
    // Saat: dijital görünüm için monospace + sabit genişlikli (tabular) rakamlar; gölge yok.
    final timeStyle = th.headlineMedium?.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      fontFamily: 'monospace',
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Dijital Saat (FittedBox ile taşmaya karşı tam koruma). Yalnız saat metni her saniye yeniden
    // kurulur (kendi RepaintBoundary'sinde).
    final timeBlock = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTone.info.tint(p),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Icon(
                Icons.access_time_filled_rounded,
                color: AppTone.info.ink(p),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          RepaintBoundary(
            child: ValueListenableBuilder<String>(
              valueListenable: _timeText,
              builder: (context, timeStr, _) => Text(timeStr, style: timeStyle),
            ),
          ),
        ],
      ),
    );

    // Canlı Saat Bölgesi Rozeti (bayrak emojisi + bilgi tonlu rozet)
    final zoneBadge = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🇹🇷 ', style: th.bodySmall),
          const StatusChip(
            label: 'TSİ (UTC+3)',
            tone: AppTone.info,
            icon: Icons.public_rounded,
          ),
        ],
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        // Rol kimliği: renkli çerçeve yerine 3 dp üst şerit (metin rengi ayrıca `ink` ile okunur).
        accentBar: tone.hue,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst Satır: Dijital Saat & Canlı Zaman Dilimi Rozeti
            _buildTopRow(context, timeBlock, zoneBadge),
            const SizedBox(height: AppSpace.sm),

            // Tarih Satırı (Türkçe)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: p.textSecondary,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ValueListenableBuilder<String>(
                        valueListenable: _dateText,
                        builder: (context, dateStr, _) => Text(
                          dateStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: th.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (widget.showUserInfo) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Divider(height: 1),
              ),
              // Kullanıcı Bilgisi ve Rolü: ad/rol satırı ikincil ağırlıkta; sığmazsa rol alt satıra iner
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: tone.tint(p),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.xs),
                          child: Icon(
                            Icons.person_rounded,
                            color: tone.ink(p),
                            size: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Flexible(
                        child: Text(
                          widget.session.fullName,
                          style: th.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  StatusChip(
                    label: widget.session.role.label,
                    tone: tone,
                    icon: Icons.shield_outlined,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
