import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:home_widget/home_widget.dart';

import 'package:http/http.dart' as http;

import 'package:site_kapi_kontrol/models/door_record.dart';



const String kDoorWidgetAndroid = 'DoorWidgetProvider';

const String kDoorWidgetIOS = 'DoorWidget';

const String kDoorWidgetAppGroup = 'group.com.gudeteknoloji.sitekapikontrol';



/// Headless background callback triggered by Home Screen Widget

@pragma('vm:entry-point')

Future<void> doorWidgetBackgroundCallback(Uri? uri) async {

  if (uri == null) return;

  final uriStr = uri.toString();



  // 1. Kapı Değiştirme (Sonraki Kapı: ▶)

  if (uriStr.contains('next_door')) {

    await _cycleDoor(step: 1);

    return;

  }



  // 2. Kapı Değiştirme (Önceki Kapı: ◀)

  if (uriStr.contains('prev_door')) {

    await _cycleDoor(step: -1);

    return;

  }



  // 3. Çevrimdışı Kapı Uyarısı

  if (uriStr.contains('door_offline_action')) {

    await HomeWidget.saveWidgetData<String>('door_status', 'Cihaz Çevrimdışı! ❌');

    await _refreshWidget();

    await Future.delayed(const Duration(seconds: 2));

    await HomeWidget.saveWidgetData<String>('door_status', 'Kapı Çevrimdışı');

    await _refreshWidget();

    return;

  }



  // 4. Kapı Açma Eylemi

  if (uriStr.contains('open_door_action')) {

    final isOnline = await HomeWidget.getWidgetData<bool>('is_online') ?? false;

    if (!isOnline) {

      await HomeWidget.saveWidgetData<String>('door_status', 'Kapı Çevrimdışı! ❌');

      await _refreshWidget();

      await Future.delayed(const Duration(seconds: 2));

      await HomeWidget.saveWidgetData<String>('door_status', 'Kapı Çevrimdışı');

      await _refreshWidget();

      return;

    }



    final doorId = await HomeWidget.getWidgetData<int>('door_id');

    final token = await HomeWidget.getWidgetData<String>('auth_token');

    final baseUrl = await HomeWidget.getWidgetData<String>('api_base_url');



    if (doorId == null || token == null || baseUrl == null || token.isEmpty || baseUrl.isEmpty) {

      await HomeWidget.saveWidgetData<String>('door_status', 'Giriş Yapın');

      await _refreshWidget();

      return;

    }



    // Durumu "Açılıyor... ⏳" yap

    await HomeWidget.saveWidgetData<String>('door_status', 'Açılıyor... ⏳');

    await _refreshWidget();



    try {

      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

      final targetUri = Uri.parse('$cleanBaseUrl/app/doors/$doorId/open');

      final response = await http.post(

        targetUri,

        headers: {

          'Authorization': 'Bearer $token',

          'Content-Type': 'application/json',

        },

      ).timeout(const Duration(seconds: 10));



      if (response.statusCode == 200 || response.statusCode == 202) {

        await HomeWidget.saveWidgetData<String>('door_status', 'Açıldı! ✅');

      } else {

        await HomeWidget.saveWidgetData<String>('door_status', 'Açılamadı ❌');

      }

    } catch (_) {

      await HomeWidget.saveWidgetData<String>('door_status', 'Hata / Çevrimdışı');

      await HomeWidget.saveWidgetData<bool>('is_online', false);

    }



    await _refreshWidget();



    // 3 saniye sonra normal durumuna geri dön

    await Future.delayed(const Duration(seconds: 3));

    final stillOnline = await HomeWidget.getWidgetData<bool>('is_online') ?? false;

    await HomeWidget.saveWidgetData<String>(

      'door_status',

      stillOnline ? 'Çevrimiçi / Hazır' : 'Kapı Çevrimdışı',

    );

    await _refreshWidget();

  }

}



Future<void> _cycleDoor({required int step}) async {

  final count = await HomeWidget.getWidgetData<int>('door_count') ?? 0;

  if (count <= 1) return;



  final currentIndex = await HomeWidget.getWidgetData<int>('current_door_index') ?? 0;

  final newIndex = (currentIndex + step + count) % count;



  final doorId = await HomeWidget.getWidgetData<int>('door_${newIndex}_id');

  final doorName = await HomeWidget.getWidgetData<String>('door_${newIndex}_name') ?? 'Kapı';

  final siteName = await HomeWidget.getWidgetData<String>('door_${newIndex}_site_name') ?? '';

  final token = await HomeWidget.getWidgetData<String>('auth_token');

  final baseUrl = await HomeWidget.getWidgetData<String>('api_base_url');



  if (doorId == null) return;



  // Yeni kapı bilgilerini aktif kapı olarak kaydet

  await HomeWidget.saveWidgetData<int>('current_door_index', newIndex);

  await HomeWidget.saveWidgetData<int>('door_id', doorId);

  await HomeWidget.saveWidgetData<String>('door_name', doorName);

  await HomeWidget.saveWidgetData<String>('site_name', siteName);

  await HomeWidget.saveWidgetData<String>('door_status', 'Denetleniyor...');

  await _refreshWidget();



  // Kapının canlı online durumunu sunucudan sorgula

  bool isOnline = false;

  if (token != null && baseUrl != null && token.isNotEmpty && baseUrl.isNotEmpty) {

    try {

      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

      final statusUri = Uri.parse('$cleanBaseUrl/app/doors/$doorId/status');

      final res = await http.get(

        statusUri,

        headers: {'Authorization': 'Bearer $token'},

      ).timeout(const Duration(seconds: 5));



      if (res.statusCode == 200) {

        final data = jsonDecode(res.body) as Map<String, dynamic>;

        final devStatus = data['device_status'] as Map<String, dynamic>?;

        final mqttConn = devStatus?['mqtt_connected'] as bool? ?? false;

        final bridgeConn = devStatus?['mqtt_bridge_connected'] as bool? ?? false;

        isOnline = mqttConn || bridgeConn;

        isOnline = mqttConn;

      }

    } catch (_) {

      isOnline = false;

    }

  }



  await HomeWidget.saveWidgetData<bool>('is_online', isOnline);

  await HomeWidget.saveWidgetData<String>(

    'door_status',

    isOnline ? 'Çevrimiçi / Hazır' : 'Kapı Çevrimdışı',

  );

  await _refreshWidget();

}



Future<void> _refreshWidget() async {

  await HomeWidget.updateWidget(

    name: kDoorWidgetAndroid,

    androidName: kDoorWidgetAndroid,

    iOSName: kDoorWidgetIOS,

  );

}



class DoorWidgetService {

  DoorWidgetService._();

  static final DoorWidgetService instance = DoorWidgetService._();



  Future<void> initialize() async {

    if (kIsWeb) return;

    try {

      await HomeWidget.setAppGroupId(kDoorWidgetAppGroup);

      await HomeWidget.registerInteractivityCallback(doorWidgetBackgroundCallback);

    } catch (e) {

      debugPrint('[DoorWidgetService] initialize error: $e');

    }

  }



  /// Senkronizasyon: Kullanıcının tanımlı tüm kapılarını widget belleğine yazar

  Future<void> syncDoorsList({

    required List<DoorRecord> doors,

    required String token,

    required String apiBaseUrl,

    DoorRecord? selectedDoor,

    bool? isSelectedDoorOnline,

  }) async {

    if (kIsWeb) return;

    if (doors.isEmpty) {

      await clearDoorData();

      return;

    }



    try {

      await HomeWidget.saveWidgetData<int>('door_count', doors.length);

      await HomeWidget.saveWidgetData<String>('auth_token', token);

      await HomeWidget.saveWidgetData<String>('api_base_url', apiBaseUrl);



      int activeIndex = 0;

      if (selectedDoor != null) {

        final idx = doors.indexWhere((d) => d.id == selectedDoor.id);

        if (idx >= 0) activeIndex = idx;

      }



      // Tüm kapıların meta bilgilerini listeye kaydet

      for (int i = 0; i < doors.length; i++) {

        final d = doors[i];

        await HomeWidget.saveWidgetData<int>('door_${i}_id', d.id);

        await HomeWidget.saveWidgetData<String>('door_${i}_name', d.doorName);

        await HomeWidget.saveWidgetData<String>('door_${i}_site_name', d.siteName ?? '');

      }



      final activeDoor = doors[activeIndex];
      final online = isSelectedDoorOnline ??
          (activeDoor.assignedDeviceUid != null && activeDoor.assignedDeviceUid!.isNotEmpty);

      final online = isSelectedDoorOnline ?? false;



      await HomeWidget.saveWidgetData<int>('current_door_index', activeIndex);

      await HomeWidget.saveWidgetData<int>('door_id', activeDoor.id);

      await HomeWidget.saveWidgetData<String>('door_name', activeDoor.doorName);

      await HomeWidget.saveWidgetData<String>('site_name', activeDoor.siteName ?? '');

      await HomeWidget.saveWidgetData<bool>('is_online', online);

      await HomeWidget.saveWidgetData<String>(

        'door_status',

        online ? 'Çevrimiçi / Hazır' : 'Kapı Çevrimdışı',

      );



      await _refreshWidget();

    } catch (e) {

      debugPrint('[DoorWidgetService] syncDoorsList error: $e');

    }

  }



  Future<void> clearDoorData() async {

    if (kIsWeb) return;

    try {

      await HomeWidget.saveWidgetData<int>('door_count', 0);

      await HomeWidget.saveWidgetData<int>('door_id', null);

      await HomeWidget.saveWidgetData<String>('door_name', 'Kapı Tanımlı Değil');

      await HomeWidget.saveWidgetData<String>('site_name', '');

      await HomeWidget.saveWidgetData<bool>('is_online', false);

      await HomeWidget.saveWidgetData<String>('door_status', 'Giriş Yapın');

      await HomeWidget.saveWidgetData<String>('auth_token', null);



      await _refreshWidget();

    } catch (e) {

      debugPrint('[DoorWidgetService] clearDoorData error: $e');

    }

  }



  Future<void> requestPinWidget() async {

    if (kIsWeb) return;

    try {

      await HomeWidget.requestPinWidget(

        androidName: kDoorWidgetAndroid,

      );

    } catch (e) {

      debugPrint('[DoorWidgetService] requestPinWidget error: $e');

    }

  }

}

