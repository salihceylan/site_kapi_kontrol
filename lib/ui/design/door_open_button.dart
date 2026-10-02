// FAZ 5 / A1b-(ii): TEK "kapıyı aç" bileşeni.
//
// "Kapıyı aç" eylemi uygulamada en az 5 ayrı görünümde (180 dp daire, mavi çubuk, mavi "Kapıyı Aç",
// turuncu "Uzaktan Aç" ...) ve her birinde ayrı yazılmış çevrimdışı/açılıyor hâlleriyle yaşıyordu.
// [DoorOpenButton] bunların tek karşılığıdır: daire (132-184 dp) ya da çubuk (>= 52 dp) görünümü,
// dört durum, açılıyor göstergesi, başarı tiki, haptik ve hareket azaltma desteği.
//
// Bu dosya YALNIZ görünüm/etkileşim taşır: hangi durumda olunduğunu ve tıklanınca ne olacağını
// çağıran belirler (mevcut türetim/akış aynen kalır).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [DoorOpenButton] durumu. Çağıranın MEVCUT durum türetiminin sonucudur (davranış değişmez):
/// `isOpeningDoor` -> [opening]; komut verilebiliyor -> [ready]; cihaza ulaşılamıyor -> [offline];
/// cihaz atanmamış/yetki yok -> [disabled].
enum DoorOpenState {
  /// Komut verilebilir: ton gradyanı + tek glow gölge. Dokununca `onPressed`.
  ready,

  /// Komut sürüyor: aynı `CircularProgressIndicator` + `openingLabel`. Dokunma kapalı.
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

/// TEK "kapıyı aç" bileşeni: daire (132-184 dp) | çubuk (>= 52 dp).
///
/// **Akış**: [DoorOpenState.ready] (gradyan + tek glow gölge) -> dokunma (orta şiddette haptik, ölçek
/// 0,96) -> [DoorOpenState.opening] (spinner + [openingLabel]) -> başarı sinyali ([successTick]
/// artar: onay işareti + success tonuna morph + hafif haptik) -> 1,4 sn sonra eski görünüme döner.
/// Çevrimdışı dokunuşta `selectionClick` haptiği + 240 ms yatay titreme + `onBlocked ?? onPressed`.
///
/// **Etiketler çağıranın MEVCUT metinleridir** ('KAPIYI AÇ', 'YEREL AĞDAN AÇ', 'QR KOD İLE AÇ',
/// 'ÇEVRİMDİŞI', 'UZAKTAN KAPALI', 'KAPALI'; açılıyor: 'AÇILIYOR' / 'Kapı Açılıyor...' /
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
/// titretmesin. Hareket azaltmada haptik kalır; titreme/beliriş/morph kalkar.
///
/// **Taşma**: daire içeriği `FittedBox(scaleDown)` içindedir (yazı ölçeği 2,0'da küçülür, taşmaz);
/// çubukta etiket `Flexible` + en çok 2 satırdır (erişilebilirlik etiketi her zaman tam metindir).
/// Daire kendi çapında yer kaplar (sığmıyorsa küçülür); sıkı genişlik verilirse ortalanır. Çubuk
/// SINIRLI genişlik ister (Row çocuğu olarak `Expanded` ile kullanın).
///
/// **Dokunma alanı**: daire varyantında yalnız dairenin İÇİ dokunmaya yanıt verir (kare köşeleri
/// boştur: kapı açma gibi kritik bir eylem saydam köşelere yanlışlıkla dokunmayla tetiklenmesin);
/// çubukta tüm dikdörtgen. Boyama kırpılmaz (glow gölgesi dışarı taşabilir).
///
/// **Erişilebilirlik**: tek anlamsal düğüm; etiket görünen metindir; `liveRegion` açılıyorken ve
/// başarıda (duyurulur). Etkin sayılan durumlar [DoorOpenState.ready] ve [DoorOpenState.offline]'dır
/// (ikisi de dokunmaya yanıt verir); açılıyor/devre dışı durumlarda dokunma eylemi YOKTUR.
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
  });

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

  /// Başarı gösteriminin süresi.
  static const Duration doneHold = Duration(milliseconds: 1400);

  /// Çevrimdışı titremenin süresi.
  static const Duration shakeDuration = Duration(milliseconds: 240);

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: DoorOpenButton.shakeDuration,
  );

  Timer? _doneTimer;

  /// Başarı gösterimi (tik + success tonu) sürüyor mu.
  bool _done = false;

  /// Başarı sinyali komut sürerken ([DoorOpenState.opening]) geldi; komut bitince gösterilecek.
  bool _successPending = false;

  /// İçerik (spinner/ikon/etiket) ilk değişimden sonra `Pop` ile belirir; ilk kurulumda
  /// beliriş yoktur (ekran açılışında düğme hareketlenmez).
  bool _animateContent = false;

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
    }
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    _shake.dispose();
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
    _doneTimer = Timer(DoorOpenButton.doneHold, () {
      if (!mounted) return;
      setState(() {
        _done = false;
        _animateContent = true;
      });
    });
  }

  void _tap() {
    switch (widget.state) {
      case DoorOpenState.ready:
        HapticFeedback.mediumImpact();
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: shape,
          onTap: tappable ? _tap : null,
          // Gradyan üstünde varsayılan dalga/odak neredeyse görünmez: dolguda beyaz, nötrde koyu.
          splashColor: (live ? Colors.white : p.textSecondary).withValues(
            alpha: live ? 0.24 : 0.14,
          ),
          highlightColor: (live ? Colors.white : p.textSecondary).withValues(
            alpha: live ? 0.10 : 0.06,
          ),
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
    );

    // Basma ölçeği (yalnız ready): daireyi de çubuğu da saran tek PressableScale.
    Widget pressable(Widget child) => PressableScale(
      scale: 0.96,
      enabled: s == DoorOpenState.ready,
      child: child,
    );

    final Widget body = circle
        ? LayoutBuilder(
            builder: (context, box) {
              // Çap: genişliğin yarısı, 132-184 dp; sığmıyorsa (sınırlı eksende) küçülür.
              var d = math.max(
                DoorOpenButton.minCircleDiameter,
                math.min(DoorOpenButton.maxCircleDiameter, box.maxWidth * 0.5),
              );
              if (box.maxWidth.isFinite) d = math.min(d, box.maxWidth);
              if (box.maxHeight.isFinite) d = math.min(d, box.maxHeight);
              return Align(
                widthFactor: 1,
                heightFactor: 1,
                child: SizedBox(
                  width: d,
                  height: d,
                  // Yalnız DOKUNMA alanı daire olur (kare köşeleri boş): kapı açma gibi kritik bir
                  // eylem saydam köşelere yanlışlıkla dokunmayla tetiklenmesin. Clip.none: boyama
                  // kırpılmaz (glow gölgesi dışarı taşar), katman/saveLayer maliyeti yok.
                  child: ClipOval(
                    clipBehavior: Clip.none,
                    child: pressable(face),
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
