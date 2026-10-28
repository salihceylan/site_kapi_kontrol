// P2-26: "Çıkış Yap" onay penceresi (confirmLogout). Çıkış yalnız açık onayla yapılır: "Vazgeç", pencere dışına dokunma
// ve geri tuşu hep "çıkma" demektir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/logout_confirm_dialog.dart';

import '../design/harness.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final List<bool> answers = <bool>[];

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () async => answers.add(await confirmLogout(context)),
          child: const Text('çık'),
        ),
      );
}

Future<_ProbeState> _open(WidgetTester t, {bool dark = false, double scale = 1.0}) async {
  await t.pumpWidget(harnessApp(const _Probe(), dark: dark, scale: scale));
  await t.pumpAndSettle();
  await t.tap(find.text('çık'));
  await t.pumpAndSettle();
  return t.state<_ProbeState>(find.byType(_Probe));
}

void main() {
  testWidgets('içerik: başlık, açıklama, çıkış ikonu; "Vazgeç" ve mercan "Çıkış Yap" düğmeleri', (t) async {
    await _open(t);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
    expect(find.text('Bu cihazdaki oturumunuz kapatılacak. Tekrar kullanmak için yeniden giriş yapmanız gerekir.'), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.byIcon(Icons.logout_rounded)), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Vazgeç')), findsOneWidget);
    final confirm = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Çıkış Yap'));
    // Yıkıcı onay: durum tonlu dolu düğme (tehlike zemini + beyaz metin).
    final style = confirm.style!;
    expect(style.backgroundColor!.resolve(<WidgetState>{}), AppTone.danger.a);
    expect(style.foregroundColor!.resolve(<WidgetState>{}), Colors.white);
  });

  testWidgets('Çıkış Yap = true; pencere kapanır', (t) async {
    final probe = await _open(t);
    await t.tap(find.widgetWithText(ElevatedButton, 'Çıkış Yap'));
    await t.pumpAndSettle();
    expect(probe.answers, <bool>[true]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Vazgeç = false', (t) async {
    final probe = await _open(t);
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(probe.answers, <bool>[false]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('pencere dışına dokunmak onay SAYILMAZ (false)', (t) async {
    final probe = await _open(t);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(probe.answers, <bool>[false]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('geri tuşu pencereyi kapatır ve onay SAYILMAZ (false)', (t) async {
    final probe = await _open(t);
    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(probe.answers, <bool>[false]);
  });

  testWidgets('çift dokunuş yalnız bir cevap üretir', (t) async {
    final probe = await _open(t);
    final confirm = find.widgetWithText(ElevatedButton, 'Çıkış Yap');
    await t.tap(confirm);
    await t.tap(confirm, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(probe.answers, <bool>[true]);
  });

  testWidgets('ekran okuyucu: başlık başlık düğümüdür; iki eylem düğmedir', (t) async {
    final handle = t.ensureSemantics();
    await _open(t);
    expect(t.getSemantics(find.text('Çıkış yapılsın mı?')), isSemantics(label: 'Çıkış yapılsın mı?', isHeader: true));
    expect(t.getSemantics(find.text('Vazgeç')), isSemantics(label: 'Vazgeç', isButton: true, hasTapAction: true));
    expect(t.getSemantics(find.widgetWithText(ElevatedButton, 'Çıkış Yap')), isSemantics(label: 'Çıkış Yap', isButton: true, hasTapAction: true));
    handle.dispose();
  });

  for (final (width, scale) in const <(double, double)>[(320, 2.0), (360, 1.5), (820, 1.0)]) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('taşmaz: ${width.toInt()} dp x$scale ${dark ? 'koyu' : 'açık'}', (t) async {
        t.view.physicalSize = Size(width, 640);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await _open(t, dark: dark, scale: scale);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(t.takeException(), isNull);
        final buttons = t.getRect(find.widgetWithText(ElevatedButton, 'Çıkış Yap'));
        expect(buttons.height, greaterThanOrEqualTo(44));
        expect(buttons.right, lessThanOrEqualTo(width));
      });
    }
  }
}
