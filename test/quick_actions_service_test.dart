import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/quick_actions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuickActionsService (eklenti yok: Windows/Linux masaüstü)', () {
    test(
      'initialize: MissingPluginException yakalanmamış asenkron hataya dönüşmez',
      () async {
        final uncaught = <Object>[];
        await runZonedGuarded(() async {
          QuickActionsService().initialize((_) {});
          // Platform kanalı yanıtı (MissingPluginException) asenkron gelir.
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }, (error, stack) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );

    test('updateDoorShortcuts / clearShortcuts eklenti yokken sessizce biter', () async {
      final service = QuickActionsService();
      await service.updateDoorShortcuts(const []);
      await service.clearShortcuts();
    });
  });
}
