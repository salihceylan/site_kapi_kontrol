import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_glyphs/phosphor_glyphs.dart';
import 'package:site_kapi_kontrol/brand/brand_scope.dart';
import 'package:site_kapi_kontrol/brand/brand_theme.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/resident_tabs.dart';

Map<String, dynamic> _json({String text = '#0F172A', String accent = '#1D4ED8', String? name = 'Yıldız Yönetim'}) => <String, dynamic>{
      'source': 'company',
      'display_name': name,
      'colors': <String, String>{'primary': '#7C2D12', 'accent': accent, 'background': '#FFF7ED', 'surface': '#FFFFFF', 'text': text},
      'logo_data': null,
    };

void main() {
  test('geçerli gövde ayrıştırılır; ad ve kapsam okunur', () {
    final t = BrandTheme.tryParse(_json())!;
    expect(t.displayName, 'Yıldız Yönetim');
    expect(t.source, 'company');
    expect(hexOf(t.primary), '#7C2D12');
    expect(t.onPrimary, Colors.white);
  });

  test('bozuk renk, eksik alan ve okunaksız çift varsayılana düşer (null)', () {
    expect(BrandTheme.tryParse(null), isNull);
    expect(BrandTheme.tryParse(<String, dynamic>{'colors': <String, String>{}}), isNull);
    expect(BrandTheme.tryParse(_json(text: 'kırmızı')), isNull);
    expect(BrandTheme.tryParse(_json(text: '#E5E7EB')), isNull);
    expect(BrandTheme.tryParse(_json(accent: '#E5E7EB')), isNull);
  });

  test('palet: 5 renk ana tokenlara bağlanır, yazı katmanları okunaklı kalır', () {
    final t = BrandTheme.tryParse(_json())!;
    final p = t.lightPalette();
    expect(p.action, t.primary);
    expect(p.onAction, Colors.white);
    expect(p.link, t.accent);
    expect(p.background, t.background);
    expect(p.surface, t.surface);
    for (final c in <Color>[p.text, p.textSecondary, p.textMuted]) {
      expect(contrastRatio(c, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(c, p.background), greaterThanOrEqualTo(4.5));
    }
    expect(p.statusCrit, AppPalette.light.statusCrit);
  });

  test('AppTheme.light(varsayılan) önceki gibi; marka paleti temaya geçer', () {
    expect(AppTheme.light(), AppTheme.light());
    final t = BrandTheme.tryParse(_json())!;
    final themed = AppTheme.light(t.lightPalette());
    expect(themed.extension<AppPalette>()!.action, t.primary);
    expect(themed.colorScheme.primary, t.primary);
    expect(AppTheme.light().extension<AppPalette>()!.action, AppPalette.light.action);
  });

  test('toJson renkleri #RRGGBB verir; logo yalnız istenince', () {
    final t = BrandTheme.tryParse(_json())!;
    expect((t.toJson()['colors'] as Map)['accent'], '#1D4ED8');
    expect(t.toJson().containsKey('logo_data'), isFalse);
    expect(t.toJson(includeLogo: true).containsKey('logo_data'), isTrue);
  });

  testWidgets('BrandBar: marka yoksa boş, adı varsa adı gösterir', (tester) async {
    final controller = BrandThemeController();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: BrandThemeScope(controller: controller, child: const Scaffold(body: BrandBar())),
    ));
    expect(find.byKey(const ValueKey<String>('brand_bar')), findsNothing);
    controller.set(BrandTheme.tryParse(_json()));
    await tester.pump();
    expect(find.text('Yıldız Yönetim'), findsOneWidget);
  });

  test('alt çubuk sekmeleri Phosphor ikonları kullanır', () {
    expect(ResidentTab.ozet.icon, PhosphorIconsRegular.squaresFour);
    expect(ResidentTab.kapi.selectedIcon, PhosphorIconsRegular.doorOpen);
  });
}
