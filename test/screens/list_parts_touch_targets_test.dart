// Ortak düğme stilleri dokunma hedefi: tonalActionStyle / dangerOutlineStyle / filledToneStyle en az 48 dp
// yüksekliktedir (önceki 44 dp erişilebilirlik çıtasının altındaydı). Büyük yazıda da küçülmez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import '../design/harness.dart';

void main() {
  for (final scale in const [1.0, 2.0]) {
    testWidgets('ortak düğme stilleri >= 48 dp yükseklik (yazı x$scale), tek harfli etiketle bile', (t) async {
      await pumpAt(
        t,
        Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                key: const ValueKey<String>('tonal_elevated'),
                style: tonalActionStyle(context),
                onPressed: () {},
                child: const Text('A'),
              ),
              OutlinedButton(
                key: const ValueKey<String>('tonal_outlined'),
                style: tonalActionStyle(context),
                onPressed: () {},
                child: const Text('A'),
              ),
              OutlinedButton(
                key: const ValueKey<String>('danger'),
                style: dangerOutlineStyle(context),
                onPressed: () {},
                child: const Text('A'),
              ),
              ElevatedButton(
                key: const ValueKey<String>('filled'),
                style: filledToneStyle(context),
                onPressed: () {},
                child: const Text('A'),
              ),
            ],
          ),
        ),
        width: 360,
        height: 640,
        scale: scale,
      );
      for (final key in const ['tonal_elevated', 'tonal_outlined', 'danger', 'filled']) {
        final size = t.getSize(find.byKey(ValueKey<String>(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
    });
  }
}
