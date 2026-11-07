import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

class CameraCredentials {
  const CameraCredentials({required this.user, required this.pass});
  final String user;
  final String pass;
}

class _DigestChallenge {
  _DigestChallenge({
    required this.realm,
    required this.nonce,
    this.qop,
    this.opaque,
  });

  final String realm;
  final String nonce;
  final String? qop;
  final String? opaque;
  int nc = 0;
}

/// IP kameradan tek kare (JPEG) çekme yardımcıları. Marka bağımsızdır: kameranın verdiği HTTP anlık kare
/// adreslerini sırayla dener, çalışanı hatırlar. Canlı video ızgarası ve plaka motoru aynı adres listesini kullanır.
class PlateCameraSnapshot {
  PlateCameraSnapshot._();

  /// Kamera kimliğine veya adresine göre son başarılı çalışan anlık kare adresi önbelleği.
  static final Map<String, Uri> _workingUriCache = <String, Uri>{};

  /// Bilinen yerel kamera kimlik bilgileri önbelleği (host -> credentials).
  static final Map<String, CameraCredentials> _credentials = <String, CameraCredentials>{
    '192.168.1.64': const CameraCredentials(user: 'admin', pass: 'gude2134'),
  };

  /// Kamera başına etkin Digest kimlik doğrulama oturumu.
  static final Map<String, _DigestChallenge> _activeChallenges = <String, _DigestChallenge>{};

  /// Aynı anda aynı adrese atılan mükerrer HTTP isteklerini tekilleştirir (25 FPS akıcılık için).
  static final Map<Uri, Future<SnapshotResult>> _inFlightFetches = <Uri, Future<SnapshotResult>>{};

  /// Kamera kaydedilirken girilen parolayı yerel belleğe işler.
  static void recordCredentials({
    required String host,
    String? username,
    String? password,
    int? cameraId,
  }) {
    final h = host.trim();
    final u = (username ?? '').trim();
    final p = password ?? '';
    if (h.isNotEmpty && p.isNotEmpty) {
      final cred = CameraCredentials(user: u.isNotEmpty ? u : 'admin', pass: p);
      _credentials[h] = cred;
      if (cameraId != null && cameraId > 0) {
        _credentials['id_$cameraId'] = cred;
      }
    }
  }

  static CameraCredentials? resolveCredentials(PlateCameraRow camera) {
    if (camera.id > 0 && _credentials.containsKey('id_${camera.id}')) {
      return _credentials['id_${camera.id}'];
    }
    final host = camera.host.trim();
    if (host.isNotEmpty && _credentials.containsKey(host)) {
      return _credentials[host];
    }
    final custom = (camera.rtspUrl ?? '').trim();
    if (custom.isNotEmpty) {
      final parsed = Uri.tryParse(custom);
      if (parsed != null && parsed.userInfo.isNotEmpty) {
        final parts = parsed.userInfo.split(':');
        final u = parts[0];
        final p = parts.length > 1 ? parts.sublist(1).join(':') : '';
        if (p.isNotEmpty) {
          final cred = CameraCredentials(user: u, pass: p);
          if (host.isNotEmpty) _credentials[host] = cred;
          return cred;
        }
      }
    }
    final user = (camera.username ?? '').trim();
    if (user.isNotEmpty && host.isNotEmpty && _credentials.containsKey(host)) {
      return _credentials[host];
    }
    return null;
  }

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
    // 554 RTSP portudur; HTTP anlık kare orada sunulmaz -> standart web portu 80'e düş.
    final httpPort = (port == null || port == 554) ? 80 : port;
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

    // 2. Yerel RTSP AI Köprüsü (127.0.0.1:8080 / localhost:8080):
    // RTSP kamerayı bellekte 25 FPS'te tutar, YOLOv9-t + FastPlateOCR ile plakayı okur (X-Plate)
    // ve 1.5ms'de yanıt verir (kameranın 533ms süren dahili CGI uç noktasındaki donmaları tamamen önler).
    addUnique(Uri.parse('http://127.0.0.1:$loopbackPort/snapshot.jpg'));
    addUnique(Uri.parse('http://localhost:$loopbackPort/snapshot.jpg'));

    final custom = (camera.rtspUrl ?? '').trim();
    if (custom.startsWith('http://') || custom.startsWith('https://')) {
      final u = Uri.tryParse(custom);
      if (u != null && !_isStreamPath(u.path)) addUnique(u);
    }

    const snapshotPaths = <String>[
      '/ISAPI/Streaming/channels/101/picture',
      '/snapshot.jpg',
      '/onvif/snapshot',
      '/cgi-bin/snapshot.cgi',
    ];

    if (host.isNotEmpty) {
      final base = 'http://$host:$httpPort';
      for (final path in snapshotPaths) {
        addUnique(Uri.parse('$base$path'));
      }
      if (httpPort != 80) {
        for (final path in snapshotPaths) {
          addUnique(Uri.parse('http://$host:80$path'));
        }
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

  static String? _extractDigestParam(String header, String param) {
    final reg = RegExp('$param="?([^",]+)"?', caseSensitive: false);
    final match = reg.firstMatch(header);
    return match?.group(1);
  }

  static String _md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

  static String _buildDigestHeader({
    required String method,
    required Uri uri,
    required String username,
    required String password,
    required _DigestChallenge challenge,
  }) {
    challenge.nc++;
    final ncStr = challenge.nc.toRadixString(16).padLeft(8, '0');
    final cnonce = '0a4f113b';
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

    final ha1 = _md5Hex('$username:${challenge.realm}:$password');
    final ha2 = _md5Hex('$method:$path');

    final qop = challenge.qop;
    String response;
    final buffer = StringBuffer('Digest username="$username", realm="${challenge.realm}", nonce="${challenge.nonce}", uri="$path"');

    if (qop != null && qop.toLowerCase().contains('auth')) {
      response = _md5Hex('$ha1:${challenge.nonce}:$ncStr:$cnonce:auth:$ha2');
      buffer.write(', qop=auth, nc=$ncStr, cnonce="$cnonce", response="$response"');
    } else {
      response = _md5Hex('$ha1:${challenge.nonce}:$ha2');
      buffer.write(', response="$response"');
    }

    if (challenge.opaque != null && challenge.opaque!.isNotEmpty) {
      buffer.write(', opaque="${challenge.opaque}"');
    }
    return buffer.toString();
  }

  static Map<String, String> _headers(PlateCameraRow camera, Uri uri) {
    final cred = resolveCredentials(camera);
    final user = (cred?.user ?? camera.username ?? '').trim();
    final pass = cred?.pass ?? '';

    // Aktif bir Digest challenge varsa doğrudan Digest dene
    final challenge = _activeChallenges[uri.host];
    if (challenge != null && user.isNotEmpty && pass.isNotEmpty) {
      final digest = _buildDigestHeader(
        method: 'GET',
        uri: uri,
        username: user,
        password: pass,
        challenge: challenge,
      );
      return <String, String>{'Authorization': digest};
    }

    if (user.isEmpty) return const <String, String>{};
    return <String, String>{'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}'};
  }

  /// [uri] adresinden tek kare çeker. JPEG değilse ya da çok küçükse hata döner.
  static Future<SnapshotResult> fetch(
    http.Client client,
    PlateCameraRow camera,
    Uri uri, {
    Duration timeout = const Duration(milliseconds: 900),
    bool fetchPlateFallback = false,
  }) {
    final existing = _inFlightFetches[uri];
    if (existing != null) return existing;
    final fut = _doFetch(
      client,
      camera,
      uri,
      timeout: timeout,
      fetchPlateFallback: fetchPlateFallback,
    );
    _inFlightFetches[uri] = fut;
    return fut.whenComplete(() => _inFlightFetches.remove(uri));
  }

  static Future<SnapshotResult> _doFetch(
    http.Client client,
    PlateCameraRow camera,
    Uri uri, {
    required Duration timeout,
    required bool fetchPlateFallback,
  }) async {
    final key = _cacheKey(camera);
    try {
      http.Response res = await client.get(uri, headers: _headers(camera, uri)).timeout(timeout);

      // Hikvision ve diğer IP kameralar için HTTP Digest kimlik doğrulama el sıkışması
      if (res.statusCode == 401 && (res.headers['www-authenticate'] ?? '').toLowerCase().contains('digest')) {
        final authHeader = res.headers['www-authenticate']!;
        final realm = _extractDigestParam(authHeader, 'realm') ?? '';
        final nonce = _extractDigestParam(authHeader, 'nonce') ?? '';
        final qop = _extractDigestParam(authHeader, 'qop');
        final opaque = _extractDigestParam(authHeader, 'opaque');

        if (realm.isNotEmpty && nonce.isNotEmpty) {
          final challenge = _DigestChallenge(
            realm: realm,
            nonce: nonce,
            qop: qop,
            opaque: opaque,
          );
          _activeChallenges[uri.host] = challenge;

          final cred = resolveCredentials(camera);
          final user = (cred?.user ?? camera.username ?? '').trim();
          final pass = cred?.pass ?? '';

          if (user.isNotEmpty && pass.isNotEmpty) {
            final digestHeader = _buildDigestHeader(
              method: 'GET',
              uri: uri,
              username: user,
              password: pass,
              challenge: challenge,
            );
            res = await client.get(uri, headers: <String, String>{'Authorization': digestHeader}).timeout(timeout);
          }
        }
      }

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
    final failedAuthorities = <String>{};
    for (final uri in candidates(camera)) {
      if (uri == cached) continue;
      if (failedAuthorities.contains(uri.authority)) continue;
      final r = await fetch(client, camera, uri, fetchPlateFallback: fetchPlateFallback);
      if (r.ok) return (uri, r);
      last = r;
      if (r.error != null && r.error!.startsWith('Kamera kimlik')) break;
      if (r.error == 'Zaman aşımı' || r.error == 'Bağlanılamadı') {
        failedAuthorities.add(uri.authority);
      }
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
