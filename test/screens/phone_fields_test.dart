// Telefon alanları (iş / iletişim): görevli rehber telefonu (sabit hat ya da cep, +90 + 10 hane).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/ui/dialogs/duty_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';

Future<DutyChoice?> Function() _open(WidgetTester t, {TeamDuty? current}) {
  DutyChoice? result;
  var closed = false;
  return () async {
    if (!closed) {
      closed = true;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await DutyDialog.show(context, personName: 'Ali', current: current),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
    }
    return result;
  };
}

void main() {
  testWidgets('görevli telefonu: +90 hazır, sabit hat yazılır ve +90XXXXXXXXXX gider; 1/6 ile başlayamaz', (t) async {
    final open = _open(t);
    await open();
    final phone = find.byType(TextField).last;
    expect(find.text(phoneFieldHintAny), findsOneWidget);
    await t.enterText(phone, '6121234567');
    expect(t.widget<TextField>(phone).controller!.text, '+90 ');
    await t.enterText(phone, '2121234567');
    expect(t.widget<TextField>(phone).controller!.text, '+90 212 123 45 67');
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    final choice = await open();
    expect(choice?.publicPhone, '+902121234567');
  });

  testWidgets('görevli telefonu: eksik numara kaydettirmez', (t) async {
    final open = _open(t);
    await open();
    await t.enterText(find.byType(TextField).last, '212123');
    await t.tap(find.byType(FilledButton).last);
    await t.pumpAndSettle();
    expect(find.text(phoneFormatErrorAny), findsOneWidget);
    expect(await open(), isNull);
  });
}
