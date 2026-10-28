// P2-26: AppBar'daki belirgin "Yenile" eylemi (RefreshActionButton).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/refresh_status.dart';
import 'package:site_kapi_kontrol/ui/widgets/refresh_action_button.dart';

import 'harness.dart';

Widget _host(RefreshStatus status, VoidCallback onPressed) => Align(
      alignment: Alignment.topRight,
      child: RefreshActionButton(status: status, onPressed: onPressed),
    );

Finder get _button => find.descendant(of: find.byType(RefreshActionButton), matching: find.byType(IconButton));

void main() {
  testWidgets('boşta: yenile simgesi, araç ipucu "Yenile", dokunma hedefi >= 44 dp, dokununca onPressed çağrılır', (t) async {
    final status = RefreshStatus();
    addTearDown(status.dispose);
    var taps = 0;
    await t.pumpWidget(harnessApp(_host(status, () => taps++)));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Yenile'), findsOneWidget);
    expect(t.getSize(_button).width, greaterThanOrEqualTo(44));
    expect(t.getSize(_button).height, greaterThanOrEqualTo(44));
    await t.tap(_button);
    expect(taps, 1);
  });

  testWidgets('görünüm: açık ve koyu temada soluk yüzey + 1 px palet kenarı, yuvarlak (çıplak simge değil)', (t) async {
    final status = RefreshStatus();
    addTearDown(status.dispose);
    for (final dark in <bool>[false, true]) {
      final p = dark ? AppPalette.dark : AppPalette.light;
      await t.pumpWidget(harnessApp(_host(status, () {}), dark: dark));
      await t.pumpAndSettle();
      final style = t.widget<IconButton>(_button).style!;
      expect(style.backgroundColor!.resolve(<WidgetState>{}), p.surfaceMuted, reason: 'dark=$dark');
      final shape = style.shape!.resolve(<WidgetState>{}) as CircleBorder;
      expect(shape.side.color, p.border, reason: 'dark=$dark');
      expect(shape.side.width, 1);
      expect(t.widget<Icon>(find.byIcon(Icons.refresh_rounded)).size, 22);
    }
  });

  testWidgets('yenileme sürerken: ilerleme göstergesi, düğme pasif; bitince simge geri gelir ve düğme yeniden etkin olur', (t) async {
    final status = RefreshStatus();
    addTearDown(status.dispose);
    var taps = 0;
    await t.pumpWidget(harnessApp(_host(status, () => taps++)));
    await t.pumpAndSettle();

    final gate = Completer<void>();
    final run = status.run(() => gate.future);
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(t.widget<IconButton>(_button).onPressed, isNull);
    await t.tap(_button, warnIfMissed: false);
    expect(taps, 0, reason: 'sürerken dokunuş alınmaz');

    gate.complete();
    await run;
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await t.tap(_button);
    expect(taps, 1);
  });

  testWidgets('ekran okuyucu: ad "Yenile"; başarılı yenilemeden sonra ipucu "Son güncelleme HH:mm"', (t) async {
    final handle = t.ensureSemantics();
    final status = RefreshStatus();
    addTearDown(status.dispose);
    await t.pumpWidget(harnessApp(_host(status, () {})));
    await t.pumpAndSettle();
    var node = t.getSemantics(_button);
    expect(node.label, 'Yenile');
    expect(node.hint, isEmpty, reason: 'hiç yenileme olmadan ipucu yok');
    expect(node.value, isEmpty);
    expect(node, isSemantics(isButton: true, isEnabled: true, hasEnabledState: true, hasTapAction: true));

    await status.run(() async {});
    await t.pumpAndSettle();
    node = t.getSemantics(_button);
    expect(node.label, 'Yenile');
    expect(node.hint, matches(RegExp(r'^Son güncelleme \d{2}:\d{2}$')));

    final gate = Completer<void>();
    final run = status.run(() => gate.future);
    await t.pump();
    node = t.getSemantics(_button);
    expect(node.value, 'Yenileniyor');
    expect(node.hint, isEmpty, reason: 'sürerken ipucu yok');
    expect(node, isSemantics(isButton: true, isEnabled: false, hasEnabledState: true, hasTapAction: false));
    gate.complete();
    await run;
    await t.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('taşmaz: 320 dp x2,0 açık ve koyu', (t) async {
    final status = RefreshStatus();
    addTearDown(status.dispose);
    for (final dark in <bool>[false, true]) {
      await pumpAt(t, SizedBox(width: double.infinity, child: _host(status, () {})), width: 320, scale: 2.0, dark: dark);
    }
  });
}
