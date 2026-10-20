// İP-1C (karar G6 + G7): sade tasarım dilinin sözleşmesi.
//
// - `AppPalette` sade alanları (sözleşme 2.3): sayfa zemini, ana eylem ve üstündeki metin, bağlantı, odak halkası, durum
//   noktaları, kritik uyarı kutusu. Açık değerler vitrinin beyaz etiket değişkenleriyle (`AppShowcaseColors`) TEK kaynaktır.
// - Kontrast tablosu (docs/TASARIM_DILI.md ile aynı satırlar): metin >= 4,5:1; ana düğme metni >= 4,5:1; ana düğme, bağlantı
//   halkası, odak halkası ve durum noktası (ya da kenarı) yanındaki yüzeye >= 3:1.
// - Tehlike tonu #E11D48 ailesi; durum tonu kuralı (yalnız tamam / bekliyor / kritik renkli işaret taşır).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// WCAG 2.x kontrast oranı; saydam ön plan opak [background] üzerine bindirilir.
double contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const AppPalette _light = AppPalette.light;
const AppPalette _dark = AppPalette.dark;

/// Kontrast tablosunun bir satırı: (ad, ön plan, zemin, en az oran).
typedef _Row = (String, Color, Color, double);

List<_Row> contrastTable(AppPalette p) {
  final surfaces = <String, Color>{
    'sayfa': p.background,
    'kart': p.surface,
    'soluk yüzey': p.surfaceMuted,
    if (p.isDark) 'kart seviye 3': p.surfaceAt(3),
  };
  return <_Row>[
    for (final s in surfaces.entries) ...[
      ('başlık metni / ${s.key}', p.text, s.value, 4.5),
      ('gövde metni / ${s.key}', p.textSecondary, s.value, 4.5),
      ('etiket metni / ${s.key}', p.textMuted, s.value, 4.5),
      ('bağlantı / ${s.key}', p.link, s.value, 4.5),
      ('odak halkası / ${s.key}', p.focusRing, s.value, 3.0),
    ],
    ('ana düğme metni / ana düğme', p.onAction, p.action, 4.5),
    ('ana düğme / sayfa', p.action, p.background, 3.0),
    ('ana düğme / kart', p.action, p.surface, 3.0),
    ('kritik kutu metni / kritik kutu', p.onCritical, p.critical, 4.5),
    // Koyu temada kutu zemine yakın (lacivert / gece mavisi): ayrımı kenar verir (vitrinle aynı kural).
    if (p.isDark) ('kritik kutu kenarı / kritik kutu', p.criticalBorder, p.critical, 3.0),
    ('kritik kutu ${p.isDark ? 'kenarı ' : ''}/ sayfa', p.isDark ? p.criticalBorder : p.critical, p.background, 3.0),
    ('kritik nokta / kart', p.statusCrit, p.surface, 3.0),
    ('kritik nokta / soluk yüzey', p.statusCrit, p.surfaceMuted, 3.0),
  ];
}

void main() {
  group('AppPalette: sade alanlar (sözleşme 2.3)', () {
    test('açık tema değerleri', () {
      expect(_light.background, const Color(0xFFF8FAFC));
      expect(_light.surface, const Color(0xFFFFFFFF));
      expect(_light.border, const Color(0xFFE2E8F0));
      expect(_light.textSecondary, const Color(0xFF475569));
      expect(_light.text, const Color(0xFF0F172A));
      expect(_light.action, const Color(0xFF0F172A));
      expect(_light.onAction, const Color(0xFFF8FAFC));
      expect(_light.link, const Color(0xFF1D4ED8));
      expect(_light.focusRing, const Color(0xFF1D4ED8));
      expect(_light.statusOk, const Color(0xFF10B981));
      expect(_light.statusWarn, const Color(0xFFF59E0B));
      expect(_light.statusCrit, const Color(0xFFE11D48));
      expect(_light.critical, const Color(0xFF0F172A));
      expect(_light.onCritical, const Color(0xFFF8FAFC));
      expect(_light.criticalBorder, const Color(0xFF1E293B));
    });

    test('koyu tema değerleri (ana düğme açık zemin + koyu metin)', () {
      expect(_dark.background, const Color(0xFF0F172A));
      expect(_dark.surface, const Color(0xFF1E293B));
      expect(_dark.action, const Color(0xFFF8FAFC));
      expect(_dark.onAction, const Color(0xFF0F172A));
      expect(_dark.link, const Color(0xFF93C5FD));
      expect(_dark.focusRing, const Color(0xFF93C5FD));
      expect(_dark.statusOk, const Color(0xFF10B981));
      expect(_dark.statusWarn, const Color(0xFFF59E0B));
      expect(_dark.statusCrit, const Color(0xFFE11D48));
      expect(_dark.critical, const Color(0xFF172554));
      expect(_dark.onCritical, const Color(0xFFF8FAFC));
      expect(_dark.criticalBorder, const Color(0xFF3B82F6));
    });

    test('açık değerler vitrinin beyaz etiket değişkenleriyle TEK kaynak (AppShowcaseColors)', () {
      expect(_light.background, AppShowcaseColors.background);
      expect(_light.surface, AppShowcaseColors.card);
      expect(_light.border, AppShowcaseColors.cardBorder);
      expect(_light.textSecondary, AppShowcaseColors.text);
      expect(_light.action, AppShowcaseColors.focus);
      expect(_light.onAction, AppShowcaseColors.onFocus);
      expect(_light.statusOk, AppShowcaseColors.statusOk);
      expect(_light.statusWarn, AppShowcaseColors.statusWarn);
      expect(_light.statusCrit, AppShowcaseColors.statusCrit);
      expect(_light.critical, AppShowcaseColors.focus);
      expect(_light.criticalBorder, AppShowcaseColors.focusBorder);
      expect(_dark.critical, AppShowcaseColors.focusDark);
    });

    test('mavi yalnız bağlantı ve odak halkasında: bağlantı / odak = birincil tonun ink rengi', () {
      for (final p in const [_light, _dark]) {
        expect(p.link, AppTone.primary.ink(p));
        expect(p.focusRing, AppTone.primary.ink(p));
        expect(p.action.computeLuminance(), isNot(closeTo(AppTone.primary.a.computeLuminance(), 0.05)));
      }
    });

    test('copyWith ve lerp yeni alanları taşır', () {
      final c = _light.copyWith(action: const Color(0xFF123456), background: const Color(0xFF654321));
      expect(c.action, const Color(0xFF123456));
      expect(c.background, const Color(0xFF654321));
      expect(c.onAction, _light.onAction);
      expect(c.statusCrit, _light.statusCrit);
      final mid = _light.lerp(_dark, 0.5);
      expect(mid.action, Color.lerp(_light.action, _dark.action, 0.5));
      expect(mid.background, Color.lerp(_light.background, _dark.background, 0.5));
      expect(mid.link, Color.lerp(_light.link, _dark.link, 0.5));
      expect(mid.critical, Color.lerp(_light.critical, _dark.critical, 0.5));
      expect(_light.lerp(_dark, 1).focusRing, _dark.focusRing);
    });
  });

  group('AppTone: tehlike tonu #E11D48 ve durum tonu kuralı (G7)', () {
    test('tehlike tonu mercan ailesi: hue = dolgu = #E11D48, dolgu sonu ve açık ink #BE123C, koyu ink #FDA4AF', () {
      expect(AppTone.danger.hue, const Color(0xFFE11D48));
      expect(AppTone.danger.a, const Color(0xFFE11D48));
      expect(AppTone.danger.b, const Color(0xFFBE123C));
      expect(AppTone.danger.inkLight, const Color(0xFFBE123C));
      expect(AppTone.danger.inkDark, const Color(0xFFFDA4AF));
    });

    test('kritik nokta = tehlike hue = tehlike dolgusu (vitrin ve çekmece rozetinin noktası AppTone.danger.a)', () {
      for (final p in const [_light, _dark]) {
        expect(AppTone.danger.hue, p.statusCrit);
        expect(AppTone.danger.a, p.statusCrit);
        expect(AppTone.success.hue, p.statusOk);
        expect(AppTone.warning.hue, p.statusWarn);
      }
    });

    test('yalnız tamam / bekliyor / kritik durum tonudur', () {
      expect(
        AppTone.values.where((t) => t.isStatus).toSet(),
        <AppTone>{AppTone.success, AppTone.warning, AppTone.danger},
      );
    });

    test('nokta rengi: durum tonlarında tonun canlı rengi, ötekilerde nötr gri (mavi / mor nokta yok)', () {
      expect(AppTone.success.dot, const Color(0xFF10B981));
      expect(AppTone.warning.dot, const Color(0xFFF59E0B));
      expect(AppTone.danger.dot, const Color(0xFFE11D48));
      for (final t in const [AppTone.primary, AppTone.info, AppTone.violet, AppTone.neutral]) {
        expect(t.dot, AppTone.neutral.hue, reason: t.name);
      }
    });

    test('simge rengi: durum tonlarında ink, ötekilerde gövde metni rengi (>= 4,5:1 yüzeylerde)', () {
      for (final p in const [_light, _dark]) {
        for (final t in AppTone.values) {
          expect(t.sign(p), t.isStatus ? t.ink(p) : p.textSecondary, reason: '${t.name} dark=${p.isDark}');
          for (final bg in [p.surface, p.surfaceMuted, p.background]) {
            expect(contrast(t.sign(p), bg), greaterThanOrEqualTo(4.5), reason: '${t.name} dark=${p.isDark}');
          }
        }
      }
    });

    test('nötr nokta yüzeylerde >= 3:1; açık temada tamam ve bekliyor noktası 3:1 altında (kenar gerekir)', () {
      for (final p in const [_light, _dark]) {
        for (final bg in [p.surface, p.background]) {
          expect(contrast(AppTone.neutral.hue, bg), greaterThanOrEqualTo(3.0));
          expect(contrast(AppTone.danger.dot, bg), greaterThanOrEqualTo(3.0));
        }
      }
      expect(contrast(AppTone.success.dot, _light.surface), lessThan(3.0));
      expect(contrast(AppTone.warning.dot, _light.surface), lessThan(3.0));
      expect(contrast(AppTone.success.a, _light.surface), greaterThanOrEqualTo(3.0));
      expect(contrast(AppTone.warning.a, _light.surface), greaterThanOrEqualTo(3.0));
    });
  });

  group('kontrast tablosu (docs/TASARIM_DILI.md)', () {
    for (final (name, p) in const [('açık', _light), ('koyu', _dark)]) {
      for (final (row, fg, bg, min) in contrastTable(p)) {
        test('$name: $row >= $min', () {
          final r = contrast(fg, bg);
          expect(r, greaterThanOrEqualTo(min), reason: 'oran=${r.toStringAsFixed(2)}');
        });
      }
    }
  });
}
