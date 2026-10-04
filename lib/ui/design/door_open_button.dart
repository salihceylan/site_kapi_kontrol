// FAZ 5 / A1b-(ii): TEK "kapıyı aç" bileşeni.
//
// "Kapıyı aç" eylemi uygulamada en az 5 ayrı görünümde (180 dp daire, mavi çubuk, mavi "Kapıyı Aç",
// turuncu "Uzaktan Aç" ...) ve her birinde ayrı yazılmış çevrimdışı/açılıyor hâlleriyle yaşıyordu.
// [DoorOpenButton] bunların tek karşılığıdır: daire (132-184 dp) ya da çubuk (>= 52 dp) görünümü,
// dört durum, açılıyor göstergesi, başarı tiki, haptik ve hareket azaltma desteği.
//
// Bu dosya YALNIZ görünüm/etkileşim taşır: hangi durumda olunduğunu ve tıklanınca ne olacağını
// çağıran belirler (mevcut türetim/akış aynen kalır).
//
// PREMIUM GÖRÜNÜM: yüzey `Gloss` ile cilalıdır (hacim, alt gölge, kenar ışığı, özel parıltı) ve
// canlılık OLAYLARLA gelir: basış -> halka dalgası; komut sürerken sonar halkaları; başarı -> ışıltı
// süpürmesi + patlama halkası + kıvılcımlar; cihaz yeniden kullanılabilir olunca -> ışıltı. Hepsi
// SONLUDUR (sonsuz boşta animasyon yoktur: `pumpAndSettle` biter, pil harcanmaz); açılıyor sonarı
// yalnız komut sürerken döner ve durum bitince durur. Hareket azaltmada efektlerin hiçbiri çalışmaz.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [DoorOpenButton] durumu. Çağıranın MEVCUT durum türetiminin sonucudur (davranış değişmez):
/// `isOpeningDoor` -> [opening]; komut verilebiliyor -> [ready]; cihaza ulaşılamıyor -> [offline];
/// cihaz atanmamış/yetki yok -> [disabled].
enum DoorOpenState {
  /// Komut verilebilir: ton gradyanı + tek glow gölge. Dokununca `onPressed`.
  ready,

  /// Komut sürüyor: aynı `CircularProgressIndicator` + `openingLabel` (+ dışa yayılan sonar
  /// halkaları). Dokunma kapalı.
  ///
  /// Spinner işlevsel bir göstergedir ve sürekli döner: bu durumda `pumpAndSettle` bitmez
  /// (testlerde `pump(Duration)` kullanın).
  opening,

  /// Cihaza ulaşılamıyor: nötr (soluk) görünüm. Dokununca titrer ve `onBlocked ?? onPressed`
  /// çağrılır (sakin kartında uyarı, bireysel görünümde yeniden-kontrol akışı).
  ///
  /// Çevrimdışıyken HİÇBİR şey yapılmasını istemiyorsanız (örn. yönetici kartı) [disabled] verin.
  offline,

  /// Cihaz yok/yetki yok: nötr (soluk) görünüm. Dokunma hiçbir şey yapmaz.
  disabled,
}

/// [DoorOpenButton] biçimi.
enum DoorOpenVariant {
  /// Dairesel dev düğme (çap: kullanılabilir genişliğin yarısı, 132-184 dp arası).
  circle,

  /// Tam genişlikli çubuk (en az 52 dp yüksekliğinde; etiket gerekirse 2 satıra sarar).
  bar,
}

/// Tek seferlik efekt türü (hangi halka/kıvılcım kümesi çizilir).
enum _DoorFx { none, tap, success, wake }

/// TEK "kapıyı aç" bileşeni: daire (132-184 dp) | çubuk (>= 52 dp).
///
/// **Akış**: [DoorOpenState.ready] (cilalı gradyan + tek glow gölge) -> dokunma (orta şiddette haptik,
/// ölçek 0,96, halka dalgası) -> [DoorOpenState.opening] (spinner + [openingLabel] + sonar halkaları)
/// -> başarı sinyali ([successTick] artar: onay işareti + success tonuna morph + ışıltı + patlama
/// halkası + kıvılcımlar + hafif haptik) -> 1,4 sn sonra eski görünüme döner.
/// Çevrimdışı dokunuşta `selectionClick` haptiği + 240 ms yatay titreme + `onBlocked ?? onPressed`.
///
/// **Etiketler çağıranın MEVCUT metinleridir** ('KAPIYI AÇ', 'YEREL AĞDAN AÇ', 'QR KOD İLE AÇ',
/// 'ÇEVRİMDIŞI', 'UZAKTAN KAPALI', 'KAPALI'; açılıyor: 'AÇILIYOR' / 'Kapı Açılıyor...' /
/// 'Gönderiliyor...'). Yeni tek metin [doneLabel] (varsayılan 'GÖNDERİLDİ'; çubukta çağıran
/// 'Gönderildi' verir).
///
/// **Ton**: [AppTone.primary] = bulut, [AppTone.warning] = yerel ağ, [AppTone.success] = yalnız QR.
/// Nötr (çevrimdışı/devre dışı) görünüm tondan bağımsızdır.
///
/// **Başarı sinyali**: `successTick` her ARTTIĞINDA (herhangi bir değişimde) başarı gösterilir;
/// ebeveyn sayacı sıfırlamaz. Ebeveynin bildiği başarıda (örn. `error == null`) sayaç bir artırılır.
/// Sinyal komut hâlâ [DoorOpenState.opening] iken gelirse gösterim komut bitince başlar; yeni bir
/// komut başlarsa süren gösterim biter. İlk kurulumdaki değer sinyal sayılmaz.
///
/// **Haptik** yalnız onay anında verilir (parmak kalkınca/Enter), basış anında değil: kaydırma
/// titretmesin. Hareket azaltmada haptik kalır; titreme/beliriş/morph/efektler kalkar.
///
/// **Taşma**: daire içeriği `FittedBox(scaleDown)` içindedir (yazı ölçeği 2,0'da küçülür, taşmaz);
/// çubukta etiket `Flexible` + en çok 2 satırdır (erişilebilirlik etiketi her zaman tam metindir).
/// Daire kendi çapında yer kaplar (sığmıyorsa küçülür); sıkı genişlik verilirse ortalanır. Çubuk
/// SINIRLI genişlik ister (Row çocuğu olarak `Expanded` ile kullanın).
///
/// **Dokunma alanı**: daire varyantında yalnız dairenin İÇİ dokunmaya yanıt verir (kare köşeleri
/// boştur: kapı açma gibi kritik bir eylem saydam köşelere yanlışlıkla dokunmayla tetiklenmesin);
/// çubukta tüm dikdörtgen. Boyama kırpılmaz (glow gölgesi ve efekt halkaları dışarı taşabilir);
/// efekt katmanları dokunmayı yutmaz.
///
/// **Erişilebilirlik**: tek anlamsal düğüm; etiket görünen metindir; `liveRegion` açılıyorken ve
/// başarıda (duyurulur). Etkin sayılan durumlar [DoorOpenState.ready] ve [DoorOpenState.offline]'dır
/// (ikisi de dokunmaya yanıt verir); açılıyor/devre dışı durumlarda dokunma eylemi YOKTUR. Efektler
/// dekoratiftir; yüksek karşıtlık modunda cila kapanır.
class DoorOpenButton extends StatefulWidget {
  const DoorOpenButton({
    super.key,
    required this.state,
    required this.label,
    required this.icon,
    this.onPressed,
    this.onBlocked,
    this.tone = AppTone.primary,
    this.variant = DoorOpenVariant.circle,
    this.openingLabel = 'AÇILIYOR',
    this.doneLabel = 'GÖNDERİLDİ',
    this.successTick = 0,
    this.diameter,
  }) : assert(
         diameter == null || diameter >= 96,
         'Daire çapı en az 96 dp olmalı (etiket/ikon sığmaz)',
       );

  /// Güncel durum.
  final DoorOpenState state;

  /// [DoorOpenState.ready], [DoorOpenState.offline] ve [DoorOpenState.disabled] iken etiket.
  final String label;

  /// [DoorOpenState.opening] iken etiket.
  final String openingLabel;

  /// Başarı gösteriminde ([successTick] artınca) etiket.
  final String doneLabel;

  /// Başarı ve açılıyor dışındaki durumlarda ikon.
  final IconData icon;

  /// [DoorOpenState.ready] iken tıklanınca çağrılır.
  final VoidCallback? onPressed;

  /// [DoorOpenState.offline] iken tıklanınca çağrılır; null ise [onPressed] çağrılır.
  final VoidCallback? onBlocked;

  /// Canlı durumların rengi.
  final AppTone tone;

  /// Daire veya çubuk.
  final DoorOpenVariant variant;

  /// Başarı sinyal sayacı: her artışta tik + success morph + hafif haptik. Varsayılan 0.
  final int successTick;

  /// Daire varyantı için sabit çap (dp, en az 96): kompakt kartlarda (örn. yan yana düzen).
  /// null (varsayılan) ise çap genişliğin yarısıdır (132-184 dp). Sığmıyorsa yine küçülür.
  final double? diameter;

  /// Başarı gösteriminin süresi.
  static const Duration doneHold = Duration(milliseconds: 1400);

  /// Çevrimdışı titremenin süresi.
  static const Duration shakeDuration = Duration(milliseconds: 240);

  /// Basış halka dalgasının süresi.
  static const Duration tapFxDuration = Duration(milliseconds: 520);

  /// Başarı patlamasının (halka + kıvılcımlar) süresi.
  static const Duration successFxDuration = Duration(milliseconds: 900);

  /// Cihaz yeniden kullanılabilir olunca halka süresi.
  static const Duration wakeFxDuration = Duration(milliseconds: 650);

  /// Işıltı süpürmesinin süresi (başarı ve "yeniden hazır" anında).
  static const Duration sweepDuration = Duration(milliseconds: 650);

  /// Komut sürerken sonar halkalarının bir turu.
  static const Duration sonarPeriod = Duration(milliseconds: 1400);

  /// Basılıyken ölçek.
  static const double pressScale = 0.96;

  /// Daire çapı alt sınırı (dp).
  static const double minCircleDiameter = 132;

  /// Daire çapı üst sınırı (dp).
  static const double maxCircleDiameter = 184;

  /// Çubuk en az yüksekliği (dp).
  static const double minBarHeight = 52;

  /// Çevrimdışı/devre dışı (nötr) zemin gradyanı: soluk yüzey -> yüzey kenarı, canlı tonlarla aynı
  /// çapraz yönde (durum geçişi yumuşak morph olur).
  ///
  /// Koyu temada `border` yarı saydam beyazdır; gradyanın ucu yüzeyin üstüne bindirilmiş OPAK
  /// renktir (saydam uçlu gradyan Skia'da ortada parlak bir bant üretir). `textSecondary` iki
  /// ucunda da en az 4,5:1 kontrastlıdır.
  static LinearGradient neutralGradient(AppPalette p) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [p.surfaceMuted, Color.alphaBlend(p.border, p.surface)],
  );

  @override
  State<DoorOpenButton> createState() => _DoorOpenButtonState();
}

class _DoorOpenButtonState extends State<DoorOpenButton>
    with TickerProviderStateMixin {
  /// Canlı yüzeydeki beyaz içerik (ikon + etiket) için ince gölge: cilalı zeminde okunaklılık.
  static const List<Shadow> _contentShadows = <Shadow>[
    Shadow(color: Color(0x47000000), blurRadius: 4, offset: Offset(0, 1.5)),
  ];

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: DoorOpenButton.shakeDuration,
  );

  /// Tek seferlik halka/kıvılcım efekti (türü [_fxKind]). Bitince ticker kalmaz.
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: DoorOpenButton.successFxDuration,
  );

  /// Tek seferlik ışıltı süpürmesi (başarı, yeniden hazır, çubukta basış).
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: DoorOpenButton.sweepDuration,
  );

  /// Komut sürerken dönen sonar halkaları. YALNIZ [DoorOpenState.opening] iken çalışır.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: DoorOpenButton.sonarPeriod,
  );

  late final Listenable _fxListenable = Listenable.merge(<Listenable>[
    _ring,
    _pulse,
  ]);

  _DoorFx _fxKind = _DoorFx.none;

  /// Klavye/odak halkası: dairenin dışında net bir halka (WCAG 2.4.7). Yalnız etkin durumda odaklanır.
  bool _focused = false;

  Timer? _doneTimer;

  /// Başarı gösterimi (tik + success tonu) sürüyor mu.
  bool _done = false;

  /// Başarı sinyali komut sürerken ([DoorOpenState.opening]) geldi; komut bitince gösterilecek.
  bool _successPending = false;

  /// İçerik (spinner/ikon/etiket) ilk değişimden sonra `Pop` ile belirir; ilk kurulumda
  /// beliriş yoktur (ekran açılışında düğme hareketlenmez).
  bool _animateContent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(DoorOpenButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tickChanged = widget.successTick != oldWidget.successTick;
    if (widget.state != oldWidget.state) _animateContent = true;
    if (widget.state == DoorOpenState.opening) {
      // Yeni komut başladı: önceki başarı gösterimi biter; sinyal komut sürerken geldiyse bekler.
      _clearDone();
      if (tickChanged) _successPending = true;
    } else if (tickChanged || _successPending) {
      _showDone();
    } else if (widget.state == DoorOpenState.ready &&
        (oldWidget.state == DoorOpenState.offline ||
            oldWidget.state == DoorOpenState.disabled)) {
      // Cihaz yeniden kullanılabilir oldu: kısa bir ışıltı "hazır" olduğunu duyurur.
      _play(_DoorFx.wake);
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    _shake.dispose();
    _ring.dispose();
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _clearDone() {
    _doneTimer?.cancel();
    _doneTimer = null;
    _done = false;
  }

  /// `didUpdateWidget` içinden çağrılır (ardından build gelir): `setState` gerekmez.
  void _showDone() {
    _successPending = false;
    HapticFeedback.lightImpact();
    _doneTimer?.cancel();
    _animateContent = true;
    _done = true;
    _play(_DoorFx.success);
    _doneTimer = Timer(DoorOpenButton.doneHold, () {
      if (!mounted) return;
      setState(() {
        _done = false;
        _animateContent = true;
      });
    });
  }

  /// Sonar halkaları yalnız komut sürerken ve hareket azaltma kapalıyken döner.
  void _syncPulse() {
    final run =
        widget.state == DoorOpenState.opening && !AppMotion.reduced(context);
    if (run) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  /// Tek seferlik efekti başlatır (hareket azaltmada hiçbir şey yapmaz).
  void _play(_DoorFx kind) {
    if (AppMotion.reduced(context)) return;
    _fxKind = kind;
    final circle = widget.variant == DoorOpenVariant.circle;
    _ring.duration = switch (kind) {
      _DoorFx.tap => DoorOpenButton.tapFxDuration,
      _DoorFx.success => DoorOpenButton.successFxDuration,
      _DoorFx.wake => DoorOpenButton.wakeFxDuration,
      _DoorFx.none => DoorOpenButton.tapFxDuration,
    };
    // Halka/kıvılcım yalnız dairede çizilir; çubukta aynı geri bildirimi ışıltı verir.
    if (circle) _ring.forward(from: 0);
    if (kind != _DoorFx.tap || !circle) _sweep.forward(from: 0);
  }

  void _tap() {
    switch (widget.state) {
      case DoorOpenState.ready:
        HapticFeedback.mediumImpact();
        _play(_DoorFx.tap);
        widget.onPressed?.call();
      case DoorOpenState.offline:
        HapticFeedback.selectionClick();
        if (!AppMotion.reduced(context)) _shake.forward(from: 0);
        (widget.onBlocked ?? widget.onPressed)?.call();
      case DoorOpenState.opening || DoorOpenState.disabled:
        break;
    }
  }

  /// Yatay titreme: 3 salınım, genlik 6 dp'den 0'a sönümlenir.
  double _shakeDx() =>
      math.sin(_shake.value * math.pi * 6) * 6 * (1 - _shake.value);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.state;
    final circle = widget.variant == DoorOpenVariant.circle;
    final opening = s == DoorOpenState.opening;
    final done = _done && !opening;
    final live = done || opening || s == DoorOpenState.ready;
    final tappable = s == DoorOpenState.ready || s == DoorOpenState.offline;
    final tone = done ? AppTone.success : widget.tone;
    final fg = live ? Colors.white : p.textSecondary;
    final label = done
        ? widget.doneLabel
        : (opening ? widget.openingLabel : widget.label);
    final ShapeBorder shape = circle
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          );
    final List<Shadow>? shadows = live ? _contentShadows : null;

    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: circle ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fg,
        fontSize: circle ? 15 : 16,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
        shadows: shadows,
      ),
    );
    final glyph = opening
        ? SizedBox(
            width: circle ? 44 : 22,
            height: circle ? 44 : 22,
            child: CircularProgressIndicator(
              strokeWidth: circle ? 4 : 2.5,
              color: fg,
            ),
          )
        : Icon(
            done ? Icons.check_rounded : widget.icon,
            size: circle ? 48 : 22,
            color: fg,
            shadows: shadows,
          );
    Widget content = Flex(
      direction: circle ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: AppSpace.sm, height: AppSpace.sm),
        // Daire içeriği FittedBox içinde (sınırsız ana eksen): Flexible yalnız çubukta.
        circle ? text : Flexible(child: text),
      ],
    );
    if (_animateContent) {
      // Yalnız YENİ içerik belirir; eski içerik hemen kalkar (find.text çift sonuç vermez).
      content = Pop(key: ValueKey<String>('${s.name}|$done'), child: content);
    }

    final face = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      decoration: ShapeDecoration(
        shape: shape,
        shadows: live
            ? [
                BoxShadow(
                  color: tone.a.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : p.shadow(1),
        gradient: live ? tone.gradient : DoorOpenButton.neutralGradient(p),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // Cila: zeminin ÜSTÜNDE, mürekkep dalgasının ve içeriğin ALTINDA (dokunmayı yutmaz).
          Positioned.fill(
            child: Gloss(
              shape: circle ? GlossShape.circle : GlossShape.rounded,
              radius: AppRadius.md,
              strength: live ? 1.0 : 0.55,
              sweep: _sweep,
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: shape,
              onTap: tappable ? _tap : null,
              onFocusChange: (focused) {
                if (focused != _focused) setState(() => _focused = focused);
              },
              // Gradyan üstünde varsayılan dalga/odak neredeyse görünmez: dolguda beyaz, nötrde koyu.
              splashColor: (live ? Colors.white : p.textSecondary).withValues(
                alpha: live ? 0.24 : 0.14,
              ),
              highlightColor: (live ? Colors.white : p.textSecondary)
                  .withValues(alpha: live ? 0.10 : 0.06),
              hoverColor: (live ? Colors.white : p.textSecondary).withValues(
                alpha: live ? 0.10 : 0.06,
              ),
              focusColor: (live ? Colors.white : p.textSecondary).withValues(
                alpha: live ? 0.22 : 0.14,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Center(
                  child: circle
                      ? FittedBox(fit: BoxFit.scaleDown, child: content)
                      : content,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Basma ölçeği (yalnız ready): daireyi de çubuğu da saran tek PressableScale.
    Widget pressable(Widget child) => PressableScale(
      scale: DoorOpenButton.pressScale,
      enabled: s == DoorOpenState.ready,
      child: child,
    );

    final Widget body = circle
        ? LayoutBuilder(
            builder: (context, box) {
              // Çap: [diameter] verildiyse o; yoksa genişliğin yarısı, 132-184 dp. Sığmıyorsa
              // (sınırlı eksende) küçülür.
              var d =
                  widget.diameter ??
                  math.max(
                    DoorOpenButton.minCircleDiameter,
                    math.min(
                      DoorOpenButton.maxCircleDiameter,
                      box.maxWidth * 0.5,
                    ),
                  );
              if (box.maxWidth.isFinite) d = math.min(d, box.maxWidth);
              if (box.maxHeight.isFinite) d = math.min(d, box.maxHeight);
              return Align(
                widthFactor: 1,
                heightFactor: 1,
                child: SizedBox(
                  width: d,
                  height: d,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Aura: tonun yumuşak, geniş ışıması (durağan; tek bulanık daire, katman
                      // önbellekte). Ton değişince (bulut -> başarı) 200 ms'de renk geçişi yapar.
                      if (live)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: TweenAnimationBuilder<Color?>(
                                tween: ColorTween(end: tone.a),
                                duration: AppMotion.of(context, AppMotion.base),
                                curve: AppMotion.standard,
                                builder: (context, color, _) => CustomPaint(
                                  painter: _AuraPainter(
                                    color: color ?? tone.a,
                                    dark: p.isDark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Efekt halkaları (sonar, basış dalgası, patlama): dairenin DIŞINA yayılır,
                      // dokunmayı yutmaz, kendi katmanında yeniden boyanır.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _HaloPainter(
                                repaint: _fxListenable,
                                ring: _ring,
                                pulse: _pulse,
                                kind: () => _fxKind,
                                hue: tone.hue,
                                focused: _focused && tappable,
                                // Odak halkası zeminde >= 3:1: açıkta koyu uç, koyuda açık uç.
                                focusColor: p.isDark ? tone.inkDark : tone.a,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Yalnız DOKUNMA alanı daire olur (kare köşeleri boş): kapı açma gibi kritik
                      // bir eylem saydam köşelere yanlışlıkla dokunmayla tetiklenmesin. Clip.none:
                      // boyama kırpılmaz (glow gölgesi dışarı taşar), katman/saveLayer maliyeti yok.
                      ClipOval(
                        clipBehavior: Clip.none,
                        child: pressable(face),
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        : pressable(
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: double.infinity,
                minHeight: DoorOpenButton.minBarHeight,
              ),
              child: face,
            ),
          );

    return Semantics(
      container: true,
      button: true,
      enabled: tappable,
      liveRegion: opening || done,
      label: label,
      onTap: tappable ? _tap : null,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _shake,
        child: body,
        builder: (context, child) =>
            Transform.translate(offset: Offset(_shakeDx(), 0), child: child),
      ),
    );
  }
}

/// Dairenin arkasındaki yumuşak renkli ışıma (aura). Dekoratiftir, durağandır.
///
/// Tek `MaskFilter.blur` dairesi: çağıran `RepaintBoundary` içinde olduğundan yalnız renk/tema
/// değişince yeniden boyanır (efektler sürerken yeniden boyanmaz).
class _AuraPainter extends CustomPainter {
  const _AuraPainter({required this.color, required this.dark});

  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = size.center(Offset(0, d * 0.05));
    canvas.drawCircle(
      c,
      d * 0.46,
      Paint()
        ..color = color.withValues(alpha: dark ? 0.42 : 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * 0.11),
    );
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.color != color || old.dark != dark;
}

/// Dairenin dışına yayılan efekt halkaları ve kıvılcımlar (dekoratif).
///
/// - **sonar** ([DoorOpenState.opening]): iki halka yarım tur arayla dışa yayılıp solar;
/// - **tap**: basış anında iki halka dalgası;
/// - **success**: tek büyük patlama halkası + sekiz kıvılcım (4 köşeli yıldız);
/// - **wake**: yumuşak tek halka.
/// Hiçbiri durağanken çizilmez; yalnız ilgili animasyon sürerken karede yeniden boyanır.
class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required Listenable repaint,
    required this.ring,
    required this.pulse,
    required this.kind,
    required this.hue,
    required this.focused,
    required this.focusColor,
  }) : super(repaint: repaint);

  final AnimationController ring;
  final AnimationController pulse;
  final _DoorFx Function() kind;
  final Color hue;

  /// Klavye odağı var mı + halka rengi.
  final bool focused;
  final Color focusColor;

  /// Kıvılcım sayısı.
  static const int _sparks = 8;

  void _ring(
    Canvas canvas,
    Offset c,
    double r,
    double progress, {
    required double reach,
    required double widthFrom,
    required double widthTo,
    required double alpha,
  }) {
    if (alpha <= 0.004) return;
    final e = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      r + r * reach * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = widthFrom + (widthTo - widthFrom) * e
        ..color = hue.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  void _star(Canvas canvas, Offset at, double size, Color color) {
    final path = Path()
      ..moveTo(at.dx, at.dy - size)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + size, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + size)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - size, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - size)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;

    // Klavye odağı: dairenin dışında 2,5 dp'lik net halka (aura/halkalardan bağımsız).
    if (focused) {
      canvas.drawCircle(
        c,
        r + 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = focusColor,
      );
    }

    // Sonar: komut sürerken sürekli (yalnız sürerken ticker var).
    if (pulse.isAnimating) {
      for (var k = 0; k < 2; k++) {
        final phase = (pulse.value + k / 2) % 1.0;
        _ring(
          canvas,
          c,
          r,
          phase,
          reach: 0.34,
          widthFrom: 3,
          widthTo: 1,
          alpha: 0.42 * (1 - phase),
        );
      }
    }

    if (!ring.isAnimating) return;
    final t = ring.value;
    switch (kind()) {
      case _DoorFx.tap:
        _ring(
          canvas,
          c,
          r,
          t,
          reach: 0.30,
          widthFrom: 3,
          widthTo: 1,
          alpha: 0.55 * (1 - t),
        );
        final t2 = ((t - 0.18) / 0.82).clamp(0.0, 1.0);
        _ring(
          canvas,
          c,
          r,
          t2,
          reach: 0.30,
          widthFrom: 2.5,
          widthTo: 0.8,
          alpha: 0.35 * (1 - t2),
        );
      case _DoorFx.success:
        _ring(
          canvas,
          c,
          r,
          t / 0.8,
          reach: 0.46,
          widthFrom: 4,
          widthTo: 1,
          alpha: 0.60 * (1 - (t / 0.8).clamp(0.0, 1.0)),
        );
        final e = Curves.easeOutCubic.transform(t);
        final fade = (1 - t).clamp(0.0, 1.0);
        for (var i = 0; i < _sparks; i++) {
          final angle = (i / _sparks) * 2 * math.pi + math.pi / _sparks;
          final dist = r * (1.04 + 0.52 * e);
          final at = c + Offset(math.cos(angle), math.sin(angle)) * dist;
          final big = i.isEven;
          _star(
            canvas,
            at,
            (big ? 5.5 : 3.5) * (1 - 0.55 * t),
            (big ? hue : AppTone.success.inkDark).withValues(alpha: fade),
          );
        }
      case _DoorFx.wake:
        _ring(
          canvas,
          c,
          r,
          t,
          reach: 0.26,
          widthFrom: 2.5,
          widthTo: 1,
          alpha: 0.40 * (1 - t),
        );
      case _DoorFx.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.hue != hue || old.focused != focused || old.focusColor != focusColor;
}
