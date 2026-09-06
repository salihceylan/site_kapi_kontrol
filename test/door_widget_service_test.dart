import 'package:flutter_test/flutter_test.dart';

import 'package:site_kapi_kontrol/models/door_record.dart';

import 'package:site_kapi_kontrol/services/door_widget_service.dart';



void main() {

  TestWidgetsFlutterBinding.ensureInitialized();



  group('DoorWidgetService Tests', () {

    test('Service instance is singleton', () {

      final s1 = DoorWidgetService.instance;

      final s2 = DoorWidgetService.instance;

      expect(identical(s1, s2), isTrue);

    });



    test('Widget constants are defined properly', () {

      expect(kDoorWidgetAndroid, 'DoorWidgetProvider');

      expect(kDoorWidgetIOS, 'DoorWidget');

      expect(kDoorWidgetAppGroup, isNotEmpty);

    });



    test('syncDoorsList accepts multiple doors and syncs without errors', () async {

      final door1 = DoorRecord(

        id: 1,

        siteCode: 1,

        siteName: 'Güneş Sitesi',

        doorName: 'Ana Giriş Kapısı',

        doorIndex: 1,

        isActive: true,

        assignedDeviceId: 1,

        assignedDeviceUid: 'UID123',

        mqttSiteId: 1,

        createdAt: DateTime.now(),

      );

      final door2 = DoorRecord(

        id: 2,

        siteCode: 1,

        siteName: 'Güneş Sitesi',

        doorName: 'Otopark Kapısı',

        doorIndex: 2,

        isActive: true,

        assignedDeviceId: 2,

        assignedDeviceUid: 'UID456',

        mqttSiteId: 1,

        createdAt: DateTime.now(),

      );



      // On non-Android runtime (test environment), HomeWidget gracefully catches missing platform channel

      await expectLater(

        DoorWidgetService.instance.syncDoorsList(

          doors: [door1, door2],

          token: 'mock_jwt_token',

          apiBaseUrl: 'http://localhost:3000',

          selectedDoor: door1,

          isSelectedDoorOnline: true,

        ),

        completes,

      );

    });



    test('requestPinWidget completes cleanly', () async {

      await expectLater(

        DoorWidgetService.instance.requestPinWidget(),

        completes,

      );

    });



    test('clearDoorData completes cleanly', () async {

      await expectLater(

        DoorWidgetService.instance.clearDoorData(),

        completes,

      );

    });



    test('doorWidgetBackgroundCallback ignores null or unrelated URIs safely', () async {

      await expectLater(

        doorWidgetBackgroundCallback(null),

        completes,

      );

      await expectLater(

        doorWidgetBackgroundCallback(Uri.parse('sitekapi://other_action')),

        completes,

      );

    });

  });

}

