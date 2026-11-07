import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

/// IP kameralar için donanım hızlandırmalı RTSP akış adresi üretici ve önbelleği.
///
/// - Küçük kart ve ızgara görünümlerinde (`preferSubStream: true`) alt akışı (örn. Hikvision `102` - 640x360 @ 20-25 FPS)
///   önceliklendirerek anında açılış ve düşük CPU/ağ tüketimi sağlar.
/// - Tam ekran görünümde (`preferSubStream: false`) ana akışı (örn. Hikvision `101` - 1080p Full HD @ 20-25 FPS) önceliklendirir.
/// - Kullanıcının formda ayrı girdiği kullanıcı adı ve şifreyi RTSP adresine güvenli biçimde enjekte eder.
class PlateCameraRtspHelper {
  PlateCameraRtspHelper._();

  static final Map<String, String> _workingRtspCache = <String, String>{};

  static String _cacheKey(PlateCameraRow camera, {required bool preferSubStream}) =>
      '${camera.id}_${camera.host.trim()}_${camera.port ?? 0}_${preferSubStream ? 'sub' : 'main'}';

  static void recordWorkingUrl(
    PlateCameraRow camera,
    String url, {
    required bool preferSubStream,
  }) {
    _workingRtspCache[_cacheKey(camera, preferSubStream: preferSubStream)] = url;
  }

  static void invalidateWorkingUrl(
    PlateCameraRow camera, {
    required bool preferSubStream,
  }) {
    _workingRtspCache.remove(_cacheKey(camera, preferSubStream: preferSubStream));
  }

  /// Kameranın olası RTSP portunu döndürür (80 veya 8000 girilmişse standart RTSP 554 portuna çevirir).
  static int resolveRtspPort(PlateCameraRow camera) {
    final custom = (camera.rtspUrl ?? '').trim();
    if (custom.toLowerCase().startsWith('rtsp://') || custom.toLowerCase().startsWith('rtsps://')) {
      final parsed = Uri.tryParse(custom);
      if (parsed != null && parsed.hasPort && parsed.port > 0) {
        return parsed.port;
      }
    }
    final p = camera.port;
    if (p == null || p <= 0 || p == 80 || p == 443 || p == 8000 || p == 8080 || p == 37777 || p == 8899) {
      return 554;
    }
    return p;
  }

  /// Kimlik bilgilerini RTSP URI içerisine enjekte eder.
  static String _injectAuth(Uri uri, CameraCredentials? cred, String? fallbackUsername) {
    if (uri.userInfo.isNotEmpty) return uri.toString();
    final user = (cred?.user ?? fallbackUsername ?? '').trim();
    final pass = cred?.pass ?? '';
    if (user.isEmpty) return uri.toString();
    final encodedUser = Uri.encodeComponent(user);
    final encodedPass = pass.isNotEmpty ? ':${Uri.encodeComponent(pass)}' : '';
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    final pathPart = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    final queryPart = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.scheme}://$encodedUser$encodedPass@${uri.host}$portPart$pathPart$queryPart';
  }

  /// Hikvision ana/alt kanal dönüşümü (101 <-> 102).
  static String? _swapHikvisionChannel(String rtspUrl, {required bool toSubStream}) {
    final fromPattern = toSubStream
        ? RegExp(r'(/Streaming/Channels/)101\b', caseSensitive: false)
        : RegExp(r'(/Streaming/Channels/)102\b', caseSensitive: false);
    if (!fromPattern.hasMatch(rtspUrl)) return null;
    final swapped = rtspUrl.replaceFirstMapped(
      fromPattern,
      (m) => '${m.group(1)}${toSubStream ? '102' : '101'}',
    );
    // Alt akışta Profile_1 sorgusu bazı Hikvision sürümlerinde 404 verebileceği için sadeleştirilmiş kopya üretilir.
    if (toSubStream) {
      final uri = Uri.tryParse(swapped);
      if (uri != null && uri.hasQuery) {
        final portPart = uri.hasPort ? ':${uri.port}' : '';
        final authPart = uri.userInfo.isNotEmpty ? '${uri.userInfo}@' : '';
        return '${uri.scheme}://$authPart${uri.host}$portPart${uri.path}';
      }
    }
    return swapped;
  }

  /// Kamera için denenecek RTSP adreslerini öncelik sırasıyla döndürür.
  static List<String> buildCandidateUrls(
    PlateCameraRow camera, {
    bool preferSubStream = false,
  }) {
    final out = <String>[];
    void addUnique(String? u) {
      if (u == null || u.trim().isEmpty) return;
      if (!out.contains(u)) out.add(u);
    }

    final cached = _workingRtspCache[_cacheKey(camera, preferSubStream: preferSubStream)];
    addUnique(cached);

    final cred = PlateCameraSnapshot.resolveCredentials(camera);
    final host = camera.host.trim();
    final rtspPort = resolveRtspPort(camera);
    final custom = (camera.rtspUrl ?? '').trim();

    if (custom.toLowerCase().startsWith('rtsp://') || custom.toLowerCase().startsWith('rtsps://')) {
      final parsed = Uri.tryParse(custom);
      if (parsed != null && parsed.host.isNotEmpty) {
        final authedCustom = _injectAuth(parsed, cred, camera.username);
        if (preferSubStream) {
          final subVariant = _swapHikvisionChannel(authedCustom, toSubStream: true);
          addUnique(subVariant);
          addUnique(authedCustom);
        } else {
          final mainVariant = _swapHikvisionChannel(authedCustom, toSubStream: false);
          addUnique(mainVariant);
          addUnique(authedCustom);
          final subFallback = _swapHikvisionChannel(authedCustom, toSubStream: true);
          addUnique(subFallback);
        }
      }
    }

    if (host.isNotEmpty) {
      String makeUrl(String path) {
        final uri = Uri(
          scheme: 'rtsp',
          host: host,
          port: rtspPort,
          path: path.startsWith('/') ? path : '/$path',
        );
        final raw = _injectAuth(uri, cred, camera.username);
        return raw;
      }

      final hikSub = makeUrl('/Streaming/Channels/102');
      final hikMain = makeUrl('/Streaming/Channels/101');
      final dahuaSub = '${makeUrl('/cam/realmonitor')}?channel=1&subtype=1';
      final dahuaMain = '${makeUrl('/cam/realmonitor')}?channel=1&subtype=0';
      final onvifSub = makeUrl('/stream2');
      final onvifMain = makeUrl('/stream1');

      final brand = camera.brand.toLowerCase();
      if (brand.contains('dahua')) {
        if (preferSubStream) {
          addUnique(dahuaSub);
          addUnique(dahuaMain);
        } else {
          addUnique(dahuaMain);
          addUnique(dahuaSub);
        }
      }

      if (preferSubStream) {
        addUnique(hikSub);
        addUnique(hikMain);
        addUnique(dahuaSub);
        addUnique(onvifSub);
        addUnique(onvifMain);
      } else {
        addUnique(hikMain);
        addUnique(hikSub);
        addUnique(dahuaMain);
        addUnique(onvifMain);
        addUnique(onvifSub);
      }
    }

    return out;
  }
}
