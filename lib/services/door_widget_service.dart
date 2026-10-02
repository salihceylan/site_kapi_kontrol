import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:home_widget/home_widget.dart';

import 'package:http/http.dart' as http;

import 'package:site_kapi_kontrol/config/app_config.dart';

import 'package:site_kapi_kontrol/models/door_record.dart';

const String kDoorWidgetAndroid = 'DoorWidgetProvider';

const String kDoorWidgetIOS = 'DoorWidget';

const String kDoorWidgetAppGroup = 'group.com.gudeteknoloji.sitekapikontrol';

/// Widget üzerinden iki "kapıyı aç" isteği arasındaki asgari süre.
const Duration kDoorWidgetMinOpenInterval = Duration(seconds: 2);

/// Widget açma isteğinin ağ zaman aşımı.
const Duration kDoorWidgetOpenTimeout = Duration(seconds: 10);

/// Widget'ın geçici durum metnini (Açıldı/Hata...) normale döndürme gecikmesi.
/// Testlerde kısaltılabilsin diye değiştirilebilir.
@visibleForTesting
Duration doorWidgetStatusRevertDelay = const Duration(seconds: 3);

/// Widget bellekte en fazla bu kadar kapı satırı (door_N_*) tutar; temizlikte
/// önceki sürümlerden kalmış artık anahtarları da süpürmek için kullanılır.
const int kDoorWidgetMaxStoredDoors = 32;

/// Widget üzerindeki düğmelerin (Kotlin tarafı `sitekapi://<host>`) tanınan eylemleri.
enum DoorWidgetAction { nextDoor, prevDoor, openDoor, doorOffline }

/// Widget PendingIntent URI'sini KATI doğrular: yalnızca `sitekapi://<bilinen_host>`
/// kabul edilir (yol, sorgu, parça, kullanıcı bilgisi, port içermemeli). Aksi halde
/// null döner ve çağrı yok sayılır.
@visibleForTesting
DoorWidgetAction? parseDoorWidgetUri(Uri? uri) {
  if (uri == null) return null;
  if (uri.scheme != 'sitekapi') return null;
  if (uri.hasQuery ||
      uri.hasFragment ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.path.isNotEmpty && uri.path != '/') return null;

  switch (uri.host) {
    case 'next_door':
      return DoorWidgetAction.nextDoor;
    case 'prev_door':
      return DoorWidgetAction.prevDoor;
    case 'open_door_action':
      return DoorWidgetAction.openDoor;
    case 'door_offline_action':
      return DoorWidgetAction.doorOffline;
    default:
      return null;
  }
}

/// Widget'a kaydedilmiş API adresini doğrular. Yalnızca https (veya derleme
/// zamanı `API_BASE_URL` ile birebir aynı geliştirme adresi) kabul edilir;
/// sonundaki `/` atılır. Geçersizse null.
@visibleForTesting
String? normalizeWidgetApiBase(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final base = trimmed.replaceAll(RegExp(r'/+$'), '');
  if (uri.scheme == 'https') return base;
  final configured = AppConfig.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (uri.scheme == 'http' && base == configured) return base;
  return null;
}

/// Açma isteği için in-flight koruması + asgari aralık.
class DoorWidgetOpenGuard {
  DoorWidgetOpenGuard({this.minInterval = kDoorWidgetMinOpenInterval});

  final Duration minInterval;
  bool _inFlight = false;
  DateTime? _lastStartedAt;

  bool get inFlight => _inFlight;

  /// Yeni bir deneme başlatılabiliyorsa true döner ve korumayı alır.
  bool tryBegin(DateTime now) {
    if (_inFlight) return false;
    final last = _lastStartedAt;
    if (last != null) {
      final delta = now.difference(last);
      if (!delta.isNegative && delta < minInterval) return false;
    }
    _inFlight = true;
    _lastStartedAt = now;
    return true;
  }

  void end() {
    _inFlight = false;
  }

  void reset() {
    _inFlight = false;
    _lastStartedAt = null;
  }
}

final DoorWidgetOpenGuard _openGuard = DoorWidgetOpenGuard();

@visibleForTesting
void resetDoorWidgetOpenGuard() => _openGuard.reset();

/// Açma isteğinin widget'a yansıyan sonucu.
class DoorWidgetOpenOutcome {
  const DoorWidgetOpenOutcome(
    this.status, {
    this.markOffline = false,
    this.revert = true,
  });

  /// Widget'ta gösterilecek kısa durum metni.
  final String status;

  /// Sunucu cihazın çevrimdışı olduğunu bildirdi (ağ hatası DEĞİL).
  final bool markOffline;

  /// Kısa süre sonra normal durum metnine dönülsün mü?
  final bool revert;
}

/// Sunucunun açma yanıtını widget durumuna çevirir (saf fonksiyon).
@visibleForTesting
DoorWidgetOpenOutcome mapDoorOpenResponse(int statusCode, String body) {
  if (statusCode == 200 || statusCode == 202) {
    return const DoorWidgetOpenOutcome('Açıldı! ✅');
  }
  String? code;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['code'] is String) {
      code = decoded['code'] as String;
    }
  } catch (_) {}

  switch (statusCode) {
    case 401:
      return const DoorWidgetOpenOutcome('Giriş Yapın', revert: false);
    case 403:
      if (code != null && code.toUpperCase().startsWith('GEOFENCE')) {
        return const DoorWidgetOpenOutcome('Konum için uygulamayı açın');
      }
      if (code == 'REMOTE_OPEN_DISABLED') {
        return const DoorWidgetOpenOutcome('Uzaktan açma kapalı ❌');
      }
      return const DoorWidgetOpenOutcome('Yetkiniz yok ❌');
    case 404:
      return const DoorWidgetOpenOutcome('Kapı bulunamadı ❌');
    case 409:
      return const DoorWidgetOpenOutcome(
        'Kapı çevrimdışı ❌',
        markOffline: true,
      );
    case 429:
      return const DoorWidgetOpenOutcome('Çok sık deneme, bekleyin');
  }
  if (statusCode >= 500) {
    return const DoorWidgetOpenOutcome('Sunucu hatası ❌');
  }
  return const DoorWidgetOpenOutcome('Açılamadı ❌');
}

/// Widget üzerinde aktif kapı olarak hangi indeksin gösterileceğini belirler.
///
/// Öncelik: (1) kullanıcı AÇIKÇA seçtiyse (`forceSelectDoor`) seçilen kapı,
/// (2) widget'ta daha önce aktif olan kapı (kapı kimliğiyle; liste sırası
/// değişse de doğru kapıda kalır), (3) uygulamanın bildirdiği seçili kapı, (4) 0.
@visibleForTesting
int resolveWidgetActiveIndex({
  required List<DoorRecord> doors,
  int? previousDoorId,
  DoorRecord? selectedDoor,
  bool forceSelectDoor = false,
}) {
  if (doors.isEmpty) return 0;

  if (forceSelectDoor && selectedDoor != null) {
    final idx = doors.indexWhere((d) => d.id == selectedDoor.id);
    if (idx >= 0) return idx;
  }

  if (previousDoorId != null) {
    final idx = doors.indexWhere((d) => d.id == previousDoorId);
    if (idx >= 0) return idx;
  }

  if (selectedDoor != null) {
    final idx = doors.indexWhere((d) => d.id == selectedDoor.id);
    if (idx >= 0) return idx;
  }

  return 0;
}

String _restingStatus(bool online) =>
    online ? 'Çevrimiçi / Hazır' : 'Kapı Çevrimdışı';

/// Headless background callback triggered by Home Screen Widget

@pragma('vm:entry-point')
Future<void> doorWidgetBackgroundCallback(Uri? uri) async {
  final action = parseDoorWidgetUri(uri);
  if (action == null) return;

  try {
    switch (action) {
      // 1. Kapı Değiştirme (Sonraki Kapı: ▶)
      case DoorWidgetAction.nextDoor:
        await _cycleDoor(step: 1);

      // 2. Kapı Değiştirme (Önceki Kapı: ◀)
      case DoorWidgetAction.prevDoor:
        await _cycleDoor(step: -1);

      // 3-4. Kapı Açma Eylemi. Çevrimdışı görünümde de deneme yapılır
      // (sunucu cihaz gerçekten çevrimdışıysa 409 döner); eski widget
      // örneklerinden gelebilecek `door_offline_action` da aynı yolu izler.
      case DoorWidgetAction.openDoor:
      case DoorWidgetAction.doorOffline:
        await _handleOpenAction();
    }
  } catch (e) {
    debugPrint('[DoorWidget] callback error: $e');
  }
}

Future<void> _handleOpenAction() async {
  if (!_openGuard.tryBegin(DateTime.now())) {
    // Önceki istek sürüyor ya da 2 sn'den sık dokunuldu: yok say.
    return;
  }

  var released = false;
  void release() {
    if (!released) {
      released = true;
      _openGuard.end();
    }
  }

  try {
    final outcome = await _performOpen();

    if (outcome.markOffline) {
      await HomeWidget.saveWidgetData<bool>('is_online', false);
      final index = await HomeWidget.getWidgetData<int>('current_door_index');
      if (index != null) {
        await HomeWidget.saveWidgetData<bool>('door_${index}_is_online', false);
      }
    }
    await HomeWidget.saveWidgetData<String>('door_status', outcome.status);
    await _refreshWidget();

    // Yeni dokunuşlar geçici durum metni beklenirken de değerlendirilebilsin.
    release();

    if (!outcome.revert) return;

    await Future.delayed(doorWidgetStatusRevertDelay);

    // Bu arada başka bir eylem durumu değiştirdiyse üzerine yazma.
    final current = await HomeWidget.getWidgetData<String>('door_status');
    if (current != outcome.status) return;

    final stillOnline =
        await HomeWidget.getWidgetData<bool>('is_online') ?? false;
    await HomeWidget.saveWidgetData<String>(
      'door_status',
      _restingStatus(stillOnline),
    );
    await _refreshWidget();
  } finally {
    release();
  }
}

Future<DoorWidgetOpenOutcome> _performOpen() async {
  final doorId = await HomeWidget.getWidgetData<int>('door_id');

  final token = await HomeWidget.getWidgetData<String>('auth_token');

  final baseUrl = await HomeWidget.getWidgetData<String>('api_base_url');

  final apiBase = normalizeWidgetApiBase(baseUrl);

  if (token == null || token.isEmpty || apiBase == null) {
    return const DoorWidgetOpenOutcome('Giriş Yapın', revert: false);
  }

  if (doorId == null || doorId <= 0) {
    return const DoorWidgetOpenOutcome('Kapı Tanımlı Değil', revert: false);
  }

  // Durumu "Açılıyor... ⏳" yap
  await HomeWidget.saveWidgetData<String>('door_status', 'Açılıyor... ⏳');
  await _refreshWidget();

  try {
    final response = await http
        .post(
          Uri.parse('$apiBase/app/doors/$doorId/open'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(kDoorWidgetOpenTimeout);

    if (response.statusCode == 401) {
      // Token geçersiz/iptal edildi (ör. parola değişti, hesap pasif): widget'ta TUTMA.
      // Uygulama açılıp oturum yenilenince yeniden yazılır; o ana dek aynı token ile tekrar tekrar
      // 401 alınmaz ve widget "Giriş Yapın" gösterir.
      await HomeWidget.saveWidgetData<String>(
        'auth_token',
        null,
        deleteFile: false,
      );
    }
    return mapDoorOpenResponse(response.statusCode, response.body);
  } catch (_) {
    // Geçici ağ hatası: is_online DEĞİŞTİRİLMEZ (kapı çevrimdışı sanılmasın).
    return const DoorWidgetOpenOutcome('Bağlantı hatası ❌');
  }
}

Future<void> _cycleDoor({required int step}) async {
  final count = await HomeWidget.getWidgetData<int>('door_count') ?? 0;

  if (count <= 1) return;

  final currentIndex =
      await HomeWidget.getWidgetData<int>('current_door_index') ?? 0;

  final newIndex = currentIndex + step;
  if (newIndex < 0 || newIndex >= count) return;

  final doorId = await HomeWidget.getWidgetData<int>('door_${newIndex}_id');

  final doorName =
      await HomeWidget.getWidgetData<String>('door_${newIndex}_name') ?? 'Kapı';

  final siteName =
      await HomeWidget.getWidgetData<String>('door_${newIndex}_site_name') ??
      '';

  final token = await HomeWidget.getWidgetData<String>('auth_token');

  final apiBase = normalizeWidgetApiBase(
    await HomeWidget.getWidgetData<String>('api_base_url'),
  );

  if (doorId == null) return;

  // Yeni kapı bilgilerini aktif kapı olarak kaydet
  await HomeWidget.saveWidgetData<int>('current_door_index', newIndex);
  await HomeWidget.saveWidgetData<int>('door_id', doorId);
  await HomeWidget.saveWidgetData<String>('door_name', doorName);
  await HomeWidget.saveWidgetData<String>('site_name', siteName);

  final canQr =
      await HomeWidget.getWidgetData<bool>('door_${newIndex}_can_qr') ?? false;
  await HomeWidget.saveWidgetData<bool>('can_qr', canQr);

  // Kapının önbellekteki online durumunu anında alarak tek seferde ve pürüzsüz geçiş yap (git-gel olmadan)
  final cachedOnline =
      await HomeWidget.getWidgetData<bool>('door_${newIndex}_is_online') ?? false;
  await HomeWidget.saveWidgetData<bool>('is_online', cachedOnline);
  await HomeWidget.saveWidgetData<String>(
    'door_status',
    _restingStatus(cachedOnline),
  );

  // Anında tek seferde güncelle - kullanıcı bekleme veya çift sıçrama hissetmez
  await _refreshWidget();

  // Arka planda sunucudan canlı durumu doğrula (farklıysa sessizce güncelle)
  if (token != null && token.isNotEmpty && apiBase != null) {
    try {
      final statusUri = Uri.parse('$apiBase/app/doors/$doorId/status');

      final res = await http
          .get(statusUri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final devStatus = data['device_status'] as Map<String, dynamic>?;
        final mqttConn = devStatus?['mqtt_connected'] as bool? ?? false;

        // Kullanıcı bu sırada başka kapıya geçtiyse eski kapının durumunu yazma.
        final activeNow = await HomeWidget.getWidgetData<int>('door_id');
        if (activeNow == doorId && mqttConn != cachedOnline) {
          await HomeWidget.saveWidgetData<bool>('is_online', mqttConn);
          await HomeWidget.saveWidgetData<bool>(
            'door_${newIndex}_is_online',
            mqttConn,
          );
          await HomeWidget.saveWidgetData<String>(
            'door_status',
            _restingStatus(mqttConn),
          );
          await _refreshWidget();
        }
      }
    } catch (_) {
      // Ağ hatasında mevcut durumu bozma
    }
  }
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

      await HomeWidget.registerInteractivityCallback(
        doorWidgetBackgroundCallback,
      );
    } catch (e) {
      debugPrint('[DoorWidgetService] initialize error: $e');
    }
  }

  /// Senkronizasyon: Kullanıcının tanımlı tüm kapılarını widget belleğine yazar.
  ///
  /// Aktif (widget'ta gösterilen) kapı kapı KİMLİĞİYLE korunur; liste sırası ya da
  /// uzunluğu değişse de kullanıcının seçtiği kapı kaymaz. Kullanıcı bir kapıyı
  /// açıkça seçtiyse çağıran `forceSelectDoor: true` vermelidir.
  Future<void> syncDoorsList({
    required List<DoorRecord> doors,
    required String token,
    required String apiBaseUrl,
    DoorRecord? selectedDoor,
    bool? isSelectedDoorOnline,
    bool forceSelectDoor = false,
  }) async {
    if (kIsWeb) return;

    if (doors.isEmpty) {
      await clearDoorData();
      return;
    }

    try {
      final previousCount =
          await HomeWidget.getWidgetData<int>('door_count') ?? 0;
      final previousDoorId = await HomeWidget.getWidgetData<int>('door_id');

      await HomeWidget.saveWidgetData<int>('door_count', doors.length);
      await HomeWidget.saveWidgetData<String>('auth_token', token);
      await HomeWidget.saveWidgetData<String>('api_base_url', apiBaseUrl);

      final activeIndex = resolveWidgetActiveIndex(
        doors: doors,
        previousDoorId: previousDoorId,
        selectedDoor: selectedDoor,
        forceSelectDoor: forceSelectDoor,
      );

      // Tüm kapıların meta bilgilerini listeye kaydet
      for (int i = 0; i < doors.length; i++) {
        final d = doors[i];
        final canQr = d.canOpenQr || d.hasPhysicalQrScanner || d.assignedDeviceQrReaderEnabled;
        final doorOnline = d.assignedDeviceIsOnline ?? false;
        await HomeWidget.saveWidgetData<int>('door_${i}_id', d.id);
        await HomeWidget.saveWidgetData<String>('door_${i}_name', d.doorName);
        await HomeWidget.saveWidgetData<String>(
          'door_${i}_site_name',
          d.siteName ?? '',
        );
        await HomeWidget.saveWidgetData<bool>('door_${i}_can_qr', canQr);
        await HomeWidget.saveWidgetData<bool>('door_${i}_is_online', doorOnline);
      }

      // Liste kısaldıysa artık kalan kapı satırlarını sil
      for (int i = doors.length; i < previousCount; i++) {
        await _removeDoorRow(i);
      }

      final activeDoor = doors[activeIndex];
      final online = (selectedDoor != null &&
              activeDoor.id == selectedDoor.id &&
              isSelectedDoorOnline != null)
          ? isSelectedDoorOnline
          : (activeDoor.assignedDeviceIsOnline ?? false);
      final activeCanQr = activeDoor.canOpenQr ||
          activeDoor.hasPhysicalQrScanner ||
          activeDoor.assignedDeviceQrReaderEnabled;

      await HomeWidget.saveWidgetData<int>('current_door_index', activeIndex);
      await HomeWidget.saveWidgetData<int>('door_id', activeDoor.id);
      await HomeWidget.saveWidgetData<String>('door_name', activeDoor.doorName);
      await HomeWidget.saveWidgetData<String>(
        'site_name',
        activeDoor.siteName ?? '',
      );
      await HomeWidget.saveWidgetData<bool>('is_online', online);
      await HomeWidget.saveWidgetData<bool>('can_qr', activeCanQr);
      await HomeWidget.saveWidgetData<String>('door_status', _restingStatus(online));

      await _refreshWidget();
    } catch (e) {
      debugPrint('[DoorWidgetService] syncDoorsList error: $e');
    }
  }

  static Future<void> _removeDoorRow(int index) async {
    for (final suffix in const ['id', 'name', 'site_name', 'can_qr', 'is_online']) {
      await HomeWidget.saveWidgetData<String>(
        'door_${index}_$suffix',
        null,
        deleteFile: false,
      );
    }
  }

  /// Çıkışta / kapı kalmayınca widget belleğini TAMAMEN temizler: oturum anahtarı,
  /// API adresi, aktif kapı/indeks, tüm `door_N_*` satırları. Widget'ın göstereceği
  /// hassas olmayan yer tutucu metinler ("Kapı Tanımlı Değil", "Giriş Yapın") kalır.
  Future<void> clearDoorData() async {
    if (kIsWeb) return;

    try {
      final storedCount =
          await HomeWidget.getWidgetData<int>('door_count') ?? 0;
      final rowCount = storedCount > kDoorWidgetMaxStoredDoors
          ? storedCount
          : kDoorWidgetMaxStoredDoors;

      // Hassas / yapısal anahtarları SİL
      for (final key in const [
        'auth_token',
        'api_base_url',
        'current_door_index',
        'door_id',
        'is_online',
        'can_qr',
      ]) {
        await HomeWidget.saveWidgetData<String>(key, null, deleteFile: false);
      }
      for (int i = 0; i < rowCount; i++) {
        await _removeDoorRow(i);
      }

      // Görünüm için yer tutucular
      await HomeWidget.saveWidgetData<int>('door_count', 0);
      await HomeWidget.saveWidgetData<String>(
        'door_name',
        'Kapı Tanımlı Değil',
      );
      await HomeWidget.saveWidgetData<String>('site_name', '');
      await HomeWidget.saveWidgetData<String>('door_status', 'Giriş Yapın');
      await _refreshWidget();
    } catch (e) {
      debugPrint('[DoorWidgetService] clearDoorData error: $e');
    }
  }

  /// Ana ekrana widget iğneleme isteği yalnızca mobilde (Android/iOS) anlamlıdır; masaüstü
  /// (Windows/Linux/macOS) ve web'de home_widget eklentisi yoktur ve istek sessizce boşa gider.
  static bool get supportsPinRequest {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> requestPinWidget() async {
    if (kIsWeb) return;

    try {
      await HomeWidget.requestPinWidget(androidName: kDoorWidgetAndroid);
    } catch (e) {
      debugPrint('[DoorWidgetService] requestPinWidget error: $e');
    }
  }
}
