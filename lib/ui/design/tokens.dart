// FAZ 5 / A0: tasarım sistemi tokenları ("Cilalı Safir").
//
// Bu dosya yalnız DEĞER taşır (boşluk, yarıçap, hareket, palet, ton, tipografi); davranış yoktur.
// Mevcut `AppColors`, `role_theme.dart` ve `AppDecorations` silinmedi: bunların üstüne ek ve
// onların içinde kullanılan tek kaynaktır. Metin/zemin çiftlerinin tamamı WCAG >= 4,5:1 olacak
// biçimde seçildi ve `test/design/contrast_test.dart` ile doğrulanır (hakem o testtir).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';

/// Boşluk ölçeği (dp). Yeni satırlarda yalnız bu değerler kullanılır.
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Köşe yarıçapı ölçeği.
///
/// sm: rozet/küçük kutu • md: düğme/girdi • lg: kart • xl: diyalog/sheet/çekmece • pill: hap.
abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// Hareket dili: süreler ve eğriler.
///
/// Her süre [of] üzerinden geçer: `MediaQuery.disableAnimations` açıkken sıfırdır.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve standard = Curves.fastOutSlowIn;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve exit = Curves.easeInCubic;

  /// Kullanıcı "hareketi azalt" istediyse true. MediaQuery yoksa false (düz test ağaçları).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Hareket azaltma açıkken [Duration.zero], değilse [duration].
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Tema duyarlı renk paleti (ThemeExtension). `context.palette` ile okunur.
///
/// Sözleşme: [text], [textSecondary] ve [textMuted] renklerinin her biri [surface], [surfaceMuted] ve [background]
/// üzerinde (koyuda ayrıca [surfaceAt] 2-3. seviyelerinde) en az 4,5:1 kontrast verir.
///
/// **Sade stil (karar G6 + G7, sözleşme 2.3)**: sayfa zemini [background] (düz, ışıma yok); kart [surface] + 1 px
/// [border], gölgesiz; gövde metni [textSecondary], başlık [text]; ana onay düğmesi ve kritik uyarı [action] / [critical]
/// (düz: cila, degrade, gölge yok); mavi yalnız [link] ve [focusRing]; durum noktaları [statusOk], [statusWarn],
/// [statusCrit] (zemin boyanmaz). Açık temanın değerleri beyaz etiketin değişkenleridir ([AppShowcaseColors]).
/// Kontrast tablosu: `test/design/sade_style_test.dart` ve `docs/TASARIM_DILI.md`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette._(
    this.isDark,
    this.surface,
    this.surfaceMuted,
    this.border,
    this.text,
    this.textSecondary,
    this.textMuted, {
    required this.background,
    required this.action,
    required this.onAction,
    required this.link,
    required this.focusRing,
    required this.statusOk,
    required this.statusWarn,
    required this.statusCrit,
    required this.critical,
    required this.onCritical,
    required this.criticalBorder,
  });

  final bool isDark;

  /// Kart/diyalog/girdi yüzeyi.
  final Color surface;

  /// Soluk iç yüzey (devre dışı zemin, iskelet tabanı, grup içi kutu, ikon rozeti).
  final Color surfaceMuted;

  /// Kart/ayırıcı kenarı ve ikincil düğmenin çerçevesi. Metin rengi DEĞİLDİR.
  final Color border;

  /// Ana metin (başlık).
  final Color text;

  /// İkincil metin (varsayılan gövde metni; sade stilde ikonlar da bu renktedir).
  final Color textSecondary;

  /// Etiket/ipucu metni. Açıkta #5F6F85: surface, surfaceMuted ve #F8FAFC üzerinde >= 4,5:1.
  final Color textMuted;

  /// Sayfa zemini: DÜZ renk (açıkta #F8FAFC "ana zemin", koyuda #0F172A); üstünde ışıma yoktur.
  final Color background;

  /// Ana onay düğmesinin zemini (açıkta #0F172A; koyuda #F8FAFC: koyu zeminde en yüksek karşıtlık). Düz çizilir.
  final Color action;

  /// [action] üstündeki metin ve ikon (açık / koyu temada >= 4,5:1; ölçüm 17,06:1).
  final Color onAction;

  /// Bağlantı metni (mavi yalnız burada ve [focusRing]'de). Yüzeylerde >= 4,5:1.
  final Color link;

  /// Klavye odak halkası (mavi). Yanındaki yüzeye >= 3:1.
  final Color focusRing;

  /// Durum noktası: tamam (zümrüt #10B981). Metnin solunda; zemin boyanmaz.
  final Color statusOk;

  /// Durum noktası: bekliyor (kehribar #F59E0B).
  final Color statusWarn;

  /// Durum noktası: kritik (mercan #E11D48 = [AppTone.danger] `hue` ve `a`).
  final Color statusCrit;

  /// Kritik uyarı kutusu (yalnız eylem isteyen yer: dikkat barı, ödenecek borç). Açıkta #0F172A; koyuda zeminden
  /// ayrışan lacivert #172554 (+ [criticalBorder]).
  final Color critical;

  /// [critical] üstündeki metin.
  final Color onCritical;

  /// [critical] kutusunun kenarı: açıkta ince #1E293B, koyuda kutuya ve zemine >= 3:1 mavi (#3B82F6).
  final Color criticalBorder;

  static const AppPalette light = AppPalette._(
    false,
    AppShowcaseColors.card,
    Color(0xFFF1F5F9),
    AppShowcaseColors.cardBorder,
    Color(0xFF0F172A),
    AppShowcaseColors.text,
    Color(0xFF5F6F85),
    background: AppShowcaseColors.background,
    action: AppShowcaseColors.focus,
    onAction: AppShowcaseColors.onFocus,
    link: Color(0xFF1D4ED8),
    focusRing: Color(0xFF1D4ED8),
    statusOk: AppShowcaseColors.statusOk,
    statusWarn: AppShowcaseColors.statusWarn,
    statusCrit: AppShowcaseColors.statusCrit,
    critical: AppShowcaseColors.focus,
    onCritical: AppShowcaseColors.onFocus,
    criticalBorder: AppShowcaseColors.focusBorder,
  );

  static const AppPalette dark = AppPalette._(
    true,
    Color(0xFF1E293B),
    Color(0xFF0F172A),
    Color(0x24FFFFFF),
    Color(0xFFF8FAFC),
    Color(0xFFCBD5E1),
    Color(0xFF94A3B8),
    background: Color(0xFF0F172A),
    action: Color(0xFFF8FAFC),
    onAction: Color(0xFF0F172A),
    link: Color(0xFF93C5FD),
    focusRing: Color(0xFF93C5FD),
    statusOk: AppShowcaseColors.statusOk,
    statusWarn: AppShowcaseColors.statusWarn,
    statusCrit: AppShowcaseColors.statusCrit,
    critical: AppShowcaseColors.focusDark,
    onCritical: AppShowcaseColors.onFocus,
    criticalBorder: Color(0xFF3B82F6),
  );

  /// Yükselti 1..3 için yüzey rengi. Koyu temada yükselti = daha açık yüzey (beyaz %3 x (seviye-1));
  /// açıkta yüzey sabittir (yükseltiyi gölge verir).
  Color surfaceAt(int level) {
    assert(level >= 1 && level <= 3, 'Yükselti seviyesi 1..3 olmalı');
    return isDark
        ? Color.alphaBlend(
            Color.fromRGBO(255, 255, 255, 0.03 * (level - 1)),
            surface,
          )
        : surface;
  }

  static const List<List<BoxShadow>> _lightShadows = <List<BoxShadow>>[
    <BoxShadow>[
      BoxShadow(color: Color(0x0D0F172A), blurRadius: 6, offset: Offset(0, 2)),
    ],
    <BoxShadow>[
      BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4)),
    ],
    <BoxShadow>[
      BoxShadow(color: Color(0x1F0F172A), blurRadius: 16, offset: Offset(0, 6)),
    ],
  ];

  static const List<List<BoxShadow>> _darkShadows = <List<BoxShadow>>[
    <BoxShadow>[
      BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 2)),
    ],
    <BoxShadow>[
      BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
    <BoxShadow>[
      BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 6)),
    ],
  ];

  /// Yükselti gölgesi (3 seviye): tek katman, blur <= 16, spread yok.
  /// 1 = kart • 2 = seçili/birincil • 3 = diyalog/sheet. Değişmez (const) liste döner.
  List<BoxShadow> shadow(int level) {
    assert(level >= 1 && level <= 3, 'Yükselti seviyesi 1..3 olmalı');
    return (isDark ? _darkShadows : _lightShadows)[level - 1];
  }

  @override
  AppPalette copyWith({
    bool? isDark,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
    Color? background,
    Color? action,
    Color? onAction,
    Color? link,
    Color? focusRing,
    Color? statusOk,
    Color? statusWarn,
    Color? statusCrit,
    Color? critical,
    Color? onCritical,
    Color? criticalBorder,
  }) {
    return AppPalette._(
      isDark ?? this.isDark,
      surface ?? this.surface,
      surfaceMuted ?? this.surfaceMuted,
      border ?? this.border,
      text ?? this.text,
      textSecondary ?? this.textSecondary,
      textMuted ?? this.textMuted,
      background: background ?? this.background,
      action: action ?? this.action,
      onAction: onAction ?? this.onAction,
      link: link ?? this.link,
      focusRing: focusRing ?? this.focusRing,
      statusOk: statusOk ?? this.statusOk,
      statusWarn: statusWarn ?? this.statusWarn,
      statusCrit: statusCrit ?? this.statusCrit,
      critical: critical ?? this.critical,
      onCritical: onCritical ?? this.onCritical,
      criticalBorder: criticalBorder ?? this.criticalBorder,
    );
  }

  /// Açık <-> koyu geçişinde (AnimatedTheme) renkler gerçekten ara değerlenir.
  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette._(
      t < 0.5 ? isDark : other.isDark,
      Color.lerp(surface, other.surface, t)!,
      Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      Color.lerp(border, other.border, t)!,
      Color.lerp(text, other.text, t)!,
      Color.lerp(textSecondary, other.textSecondary, t)!,
      Color.lerp(textMuted, other.textMuted, t)!,
      background: Color.lerp(background, other.background, t)!,
      action: Color.lerp(action, other.action, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
      link: Color.lerp(link, other.link, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      statusOk: Color.lerp(statusOk, other.statusOk, t)!,
      statusWarn: Color.lerp(statusWarn, other.statusWarn, t)!,
      statusCrit: Color.lerp(statusCrit, other.statusCrit, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
      onCritical: Color.lerp(onCritical, other.onCritical, t)!,
      criticalBorder: Color.lerp(criticalBorder, other.criticalBorder, t)!,
    );
  }
}

extension AppPaletteX on BuildContext {
  /// Temanın [AppPalette]'i. Uzantısız (düz `MaterialApp`) ağaçlarda parlaklığa göre varsayılan.
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}

/// Anlamsal ton: [hue] tint/kenar/rol rengi • [a]->[b] dolgu gradyanı (üstünde BEYAZ metin) •
/// [ink] metin/ikon rengi (açıkta 700-800, koyuda 300 seviyesi).
///
/// Kontrast sözleşmesi (testle doğrulanır): beyaz, [a] ve [b] üzerinde >= 4,5:1; [ink] hem yüzeyde
/// hem kendi tint'i ([tint]) üstünde >= 4,5:1; yüzey olarak surface, surfaceMuted ve sayfa zemini
/// (#F8FAFC / koyuda zemin tonları) sayılır. Açık temada success/warning ink'i bir kademe (800)
/// koyudur: tint'li soluk yüzeylerde (surfaceMuted, #F8FAFC) warning 700 seviyesi eşiğin altında
/// (4,2-4,4:1), success 700 seviyesi ise eşikte (4,51:1) kalıyordu.
enum AppTone {
  /// Bulut/birincil eylem • süper kullanıcı rolü.
  primary(
    Color(0xFF3B82F6),
    Color(0xFF2563EB),
    Color(0xFF1D4ED8),
    Color(0xFF1D4ED8),
    Color(0xFF93C5FD),
  ),

  /// Çevrimiçi/başarı/QR • site yöneticisi rolü.
  success(
    Color(0xFF10B981),
    Color(0xFF047857),
    Color(0xFF065F46),
    Color(0xFF065F46),
    Color(0xFF6EE7B7),
  ),

  /// Yerel ağ/uyarı/bekliyor.
  warning(
    Color(0xFFF59E0B),
    Color(0xFFB45309),
    Color(0xFF92400E),
    Color(0xFF92400E),
    Color(0xFFFCD34D),
  ),

  /// Ekran QR, bilgi.
  info(
    Color(0xFF0EA5E9),
    Color(0xFF0369A1),
    Color(0xFF075985),
    Color(0xFF0369A1),
    Color(0xFF7DD3FC),
  ),

  /// Çevrimdışı/hata/silme. Sade stilin "mercan" tonu (karar G7): hue = dolgu = #E11D48 (kritik durum noktası, vitrin ve
  /// çekmece rozeti noktası); dolgu sonu ve açık ink #BE123C, koyu ink #FDA4AF.
  danger(
    Color(0xFFE11D48),
    Color(0xFFE11D48),
    Color(0xFFBE123C),
    Color(0xFFBE123C),
    Color(0xFFFDA4AF),
  ),

  /// Daire kullanıcısı/bireysel rolü.
  violet(
    Color(0xFFA855F7),
    Color(0xFF7E22CE),
    Color(0xFF6B21A8),
    Color(0xFF7E22CE),
    Color(0xFFD8B4FE),
  ),

  /// Nötr/bilinmeyen/cihaz yok.
  neutral(
    Color(0xFF64748B),
    Color(0xFF475569),
    Color(0xFF334155),
    Color(0xFF475569),
    Color(0xFFCBD5E1),
  );

  const AppTone(this.hue, this.a, this.b, this.inkLight, this.inkDark);

  /// Canlı ton: kenar, tint ve rol vurgusu (role_theme.dart `accentColor` ile aynı). METİN için değil.
  final Color hue;

  /// Dolgu gradyanı başlangıcı (üstüne beyaz metin).
  final Color a;

  /// Dolgu gradyanı sonu (üstüne beyaz metin).
  final Color b;

  /// Açık temada metin/ikon rengi.
  final Color inkLight;

  /// Koyu temada metin/ikon rengi.
  final Color inkDark;

  static final List<LinearGradient> _gradients =
      List<LinearGradient>.unmodifiable(<LinearGradient>[
        for (final tone in values)
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[tone.a, tone.b],
          ),
      ]);

  /// [a] -> [b] sol-üstten sağ-alta dolgu gradyanı (beyaz metin >= 4,5:1). Ton başına tek örnek.
  LinearGradient get gradient => _gradients[index];

  /// Metin/ikon rengi: açıkta koyu (700-800), koyuda açık (300).
  Color ink(AppPalette p) => p.isDark ? inkDark : inkLight;

  /// Soluk zemin: [hue] açıkta %12, koyuda %16 saydamlıkla (yüzey üstüne bindirilir).
  Color tint(AppPalette p) => hue.withValues(alpha: p.isDark ? 0.16 : 0.12);

  /// Sade stil (karar G7): durum tonu mu (tamam / bekliyor / kritik)? Yalnız bu üç ton renkli işaret (nokta, simge,
  /// dolu düğme, kart kenarı) taşır; öteki tonlar (birincil, bilgi, mor, nötr) nötr görünür: mavi yalnız bağlantı ve odak
  /// halkasındadır.
  bool get isStatus => this == success || this == warning || this == danger;

  /// Durum noktasının rengi: durum tonlarında tonun canlı rengi (#10B981 / #F59E0B / #E11D48), ötekilerde nötr gri.
  Color get dot => isStatus ? hue : neutral.hue;

  /// Simge (ikon) rengi: durum tonlarında [ink], ötekilerde gövde metni rengi (sade stilde "normal metin ve ikon").
  Color sign(AppPalette p) => isStatus ? ink(p) : p.textSecondary;
}

/// Rol -> ton köprüsü. `role.tone.hue == role.accentColor` (role_theme.dart) sözleşmesi testle doğrulanır.
extension RoleTone on UserRole {
  AppTone get tone => switch (this) {
    UserRole.superUser => AppTone.primary,
    UserRole.siteManager => AppTone.success,
    UserRole.apartmentOwner || UserRole.individual => AppTone.violet,
  };
}

/// Sade stilin ("sade": işverenin komutlar.txt renk tablosu, karar G6 + G7) renk değişkenleri. Beyaz etiket teması bu
/// beş değişkeni değiştirir: [background] (ana zemin), [card] + [cardBorder] (kart ve ince çerçevesi; gölge yok),
/// [text] (normal metin ve ikon), [focus] (kritik odak kutusu ve ana düğme) ve durum noktaları ([statusOk],
/// [statusWarn], [statusCrit]: arka planı boyamaz, metnin soluna küçük nokta). Altındakiler bunlardan türeyen yardımcılardır.
///
/// Değerler AÇIK tema içindir ve [AppPalette.light]'ın sade alanları bunlardan okunur (tek kaynak): uygulamanın tamamı
/// (İP-1C'den beri) bu renklerdedir; Panel vitrini ayrıca doğrudan kullanır. Koyu temada vitrin kart / metin için
/// [AppPalette.dark]'ı, odak kutusu için [focusDark] + [AppTone.primary] kenarını kullanır. Kontrastlar
/// `test/screens/module_showcase_view_test.dart` ve `test/design/sade_style_test.dart` ile doğrulanır.
abstract final class AppShowcaseColors {
  /// Ana zemin (kırık beyaz / buz grisi): açık temada vitrin sayfasının DÜZ zemini.
  static const Color background = Color(0xFFF8FAFC);

  /// Kart yüzeyi (saf beyaz).
  static const Color card = Color(0xFFFFFFFF);

  /// Kartın ince çerçevesi (gölge yerine).
  static const Color cardBorder = Color(0xFFE2E8F0);

  /// Normal metin ve ikon (yumuşak antrasit).
  static const Color text = Color(0xFF475569);

  /// Kritik odak (gece kömürü): yalnız eylem isteyen kutu (ödenecek borç, dikkat barı) ve ana düğme.
  static const Color focus = Color(0xFF0F172A);

  /// Durum noktaları: zümrüt (tamam) / kehribar (bekliyor) / mercan (kritik).
  static const Color statusOk = Color(0xFF10B981);
  static const Color statusWarn = Color(0xFFF59E0B);
  static const Color statusCrit = Color(0xFFE11D48);

  /// Odak kutusu ve koyu düğme üstündeki metin (ana zemin rengi).
  static const Color onFocus = background;

  /// Odak kutusu üstündeki ikincil metin.
  static const Color onFocusMuted = Color(0xFFCBD5E1);

  /// Açık temada odak kutusunun ince kenarı.
  static const Color focusBorder = Color(0xFF1E293B);

  /// Koyu temada odak kutusu: koyu sayfa zemininden (#0F172A -> #020617) ayrışan lacivert; kenarı
  /// [AppTone.primary] `hue` (zemine ve kutuya >= 3:1).
  static const Color focusDark = Color(0xFF172554);
}

/// Tipografi ölçeği: yalnız mevcut temada tanımlı yuvalar (label* dokunulmaz: buton varsayılanları).
///
/// Yeni kodda `fontSize` literal'i yazma; en küçük punto 11. `bodyMedium` (varsayılan metin) artık
/// textSecondary: açık temada eski textMuted'e göre kontrast yüksek.
TextTheme appTextTheme(AppPalette p) => TextTheme(
  // hero / sayfa başlığı
  headlineMedium: TextStyle(
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: p.text,
  ),
  // kart / diyalog / AppBar başlığı
  titleLarge: TextStyle(
    fontSize: 18,
    height: 1.30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: p.text,
  ),
  // alt başlık / öğe adı
  titleMedium: TextStyle(
    fontSize: 15.5,
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: p.text,
  ),
  bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: p.text),
  bodyMedium: TextStyle(fontSize: 13.5, height: 1.40, color: p.textSecondary),
  // etiket / ipucu
  bodySmall: TextStyle(fontSize: 12, height: 1.35, color: p.textMuted),
);
