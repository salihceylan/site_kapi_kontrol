import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

/// IP kameradan tek kare (JPEG) çekme yardımcıları. Marka bağımsızdır: kameranın verdiği HTTP anlık kare
/// adreslerini sırayla dener, çalışanı hatırlar. Canlı video ızgarası ve plaka motoru aynı adres listesini kullanır.
class PlateCameraSnapshot {
  PlateCameraSnapshot._();

  /// Kamera kimliğine veya adresine göre son başarılı çalışan anlık kare adresi önbelleği.
  static final Map<String, Uri> _workingUriCache = <String, Uri>{};

  static String _cacheKey(PlateCameraRow camera) =>
      '${camera.id}_${camera.host.trim()}_${camera.port ?? 0}';

  static Uri? cachedUriFor(PlateCameraRow camera) =>
      _workingUriCache[_cacheKey(camera)] ??
      (camera.id > 0 ? _workingUriCache['id_${camera.id}'] : null);

  /// MJPEG / video akış yolları tek kare değildir; `toBytes()` ile okunursa bitmez. Aday listesinden çıkarılır.
  static bool _isStreamPath(String path) {
    final p = path.toLowerCase();
    return p.contains('mjpeg') || p.endsWith('/video') || p.endsWith('/stream') || p.contains('.mjpg');
  }

  /// Kamera için denenecek anlık kare adresleri (öncelik sırasıyla).
  static List<Uri> candidates(PlateCameraRow camera) {
    final host = camera.host.trim();
    final port = camera.port;
    // 554 RTSP portudur; HTTP anlık kare orada sunulmaz -> 8080/80'e düş.
    final httpPort = (port == null || port == 554) ? 8080 : port;
    final loopbackPort = (port != null && port != 554 && port != 80) ? port : 8080;

    final out = <Uri>[];
    void addUnique(Uri u) {
      if (!out.contains(u)) out.add(u);
    }

    // 1. Önbellekte çalışan adres varsa ilk sıraya koy
    final cached = cachedUriFor(camera);
    if (cached != null) {
      addUnique(cached);
    }

    // 2. HTTPS Web tarayıcısında (kIsWeb) 192.168.x.x adresleri Mixed-Content nedeniyle engellenir;
    // W3C Secure Context olan 127.0.0.1 / localhost adreslerini en başa koy ki 0ms gecikmeyle bağlansın.
    if (kIsWeb) {
      addUnique(Uri.parse('http://127.0.0.1:$loopbackPort/snapshot.jpg'));
      addUnique(Uri.parse('http://localhost:$loopbackPort/snapshot.jpg'));
    }

    final custom = (camera.rtspUrl ?? '').trim();
    if (custom.startsWith('http://') || custom.startsWith('https://')) {
      final u = Uri.tryParse(custom);
      if (u != null && !_isStreamPath(u.path)) addUnique(u);
    }

    const snapshotPaths = <String>[
      '/snapshot.jpg',
      '/onvif/snapshot',
      '/ISAPI/Streaming/channels/101/picture',
      '/cgi-bin/snapshot.cgi',
    ];

    if (host.isNotEmpty) {
      final base = 'http://$host:$httpPort';
      for (final path in snapshotPaths) {
        addUnique(Uri.parse('$base$path'));
      }
      if (httpPort != 80) {
        addUnique(Uri.parse('http://$host:80/snapshot.jpg'));
      }
      if (httpPort != 8080) {
        addUnique(Uri.parse('http://$host:8080/snapshot.jpg'));
      }
    }

    // Aynı bilgisayarda çalışan yerel kamera yayın sunucusu geri-düşüşü
    if (host != '127.0.0.1' && host != 'localhost') {
      addUnique(Uri.parse('http://127.0.0.1:$loopbackPort/snapshot.jpg'));
      addUnique(Uri.parse('http://localhost:$loopbackPort/snapshot.jpg'));
    }

    return out;
  }

  static Map<String, String> _headers(PlateCameraRow camera) {
    final user = (camera.username ?? '').trim();
    if (user.isEmpty || !camera.hasPassword) return const <String, String>{};
    return <String, String>{'Authorization': 'Basic ${base64Encode(utf8.encode('$user:'))}'};
  }

  /// [uri] adresinden tek kare çeker. JPEG değilse ya da çok küçükse hata döner.
  static Future<SnapshotResult> fetch(
    http.Client client,
    PlateCameraRow camera,
    Uri uri, {
    Duration timeout = const Duration(milliseconds: 900),
    bool fetchPlateFallback = false,
  }) async {
    final key = _cacheKey(camera);
    try {
      final res = await client.get(uri, headers: _headers(camera)).timeout(timeout);
      if (res.statusCode == 401 || res.statusCode == 403) {
        return SnapshotResult.failure('Kamera kimlik doğrulaması istiyor (HTTP ${res.statusCode}).');
      }
      if (res.statusCode != 200) return SnapshotResult.failure('HTTP ${res.statusCode}');
      final bytes = res.bodyBytes;
      final isJpeg = bytes.length > 500 && bytes[0] == 0xFF && bytes[1] == 0xD8;
      if (!isJpeg) return SnapshotResult.failure('Yanıt bir JPEG kare değil.');

      String? plate = res.headers['x-plate'];
      String? cleanPlate = (plate == null || plate.trim().isEmpty || plate.trim().toLowerCase() == 'none')
          ? null
          : plate.trim();

      if (cleanPlate == null && fetchPlateFallback && !res.headers.containsKey('x-plate')) {
        cleanPlate = await _queryLastPlateApi(client, uri);
      }

      _workingUriCache[key] = uri;
      if (camera.id > 0) {
        _workingUriCache['id_${camera.id}'] = uri;
      }
      return SnapshotResult.success(bytes, plate: cleanPlate, sourceUri: uri);
    } on TimeoutException {
      if (_workingUriCache[key] == uri) _workingUriCache.remove(key);
      if (camera.id > 0 && _workingUriCache['id_${camera.id}'] == uri) {
        _workingUriCache.remove('id_${camera.id}');
      }
      return SnapshotResult.failure('Zaman aşımı');
    } catch (_) {
      if (_workingUriCache[key] == uri) _workingUriCache.remove(key);
      if (camera.id > 0 && _workingUriCache['id_${camera.id}'] == uri) {
        _workingUriCache.remove('id_${camera.id}');
      }
      return SnapshotResult.failure('Bağlanılamadı');
    }
  }

  static Future<String?> _queryLastPlateApi(http.Client client, Uri snapshotUri) async {
    try {
      final apiUri = snapshotUri.replace(path: '/api/last_plate', query: null);
      final res = await client.get(apiUri).timeout(const Duration(milliseconds: 350));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['plate'] != null) {
          final p = data['plate'].toString().trim();
          if (p.isNotEmpty && p.toLowerCase() != 'none') return p;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Adayları sırayla dener; ilk çalışan adresi ve kareyi döndürür.
  static Future<(Uri?, SnapshotResult)> discover(
    http.Client client,
    PlateCameraRow camera, {
    bool fetchPlateFallback = false,
  }) async {
    final cached = cachedUriFor(camera);
    if (cached != null) {
      final fast = await fetch(
        client,
        camera,
        cached,
        timeout: const Duration(milliseconds: 650),
        fetchPlateFallback: fetchPlateFallback,
      );
      if (fast.ok) return (cached, fast);
    }

    SnapshotResult last = SnapshotResult.failure('Kamera adresi yok');
    for (final uri in candidates(camera)) {
      if (uri == cached) continue;
      final r = await fetch(client, camera, uri, fetchPlateFallback: fetchPlateFallback);
      if (r.ok) return (uri, r);
      last = r;
      if (r.error != null && r.error!.startsWith('Kamera kimlik')) break;
    }
    return (null, last);
  }
}

class SnapshotResult {
  SnapshotResult.success(Uint8List this.bytes, {this.plate, this.sourceUri}) : error = null;
  SnapshotResult.failure(String this.error)
      : bytes = null,
        plate = null,
        sourceUri = null;

  final Uint8List? bytes;
  final String? plate;
  final Uri? sourceUri;
  final String? error;
  bool get ok => bytes != null;
}
