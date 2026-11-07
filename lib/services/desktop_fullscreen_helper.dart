import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Masaüstü (Windows Win32 kenarlıksız tam ekran) ve mobil (immersiveSticky) için
/// güvenli tam ekran pencere geçiş yardımcısı.
class DesktopFullscreenHelper {
  DesktopFullscreenHelper._();

  static const MethodChannel _channel = MethodChannel('site_kapi_kontrol/window');
  static bool _isFullscreen = false;

  static bool get isFullscreen => _isFullscreen;

  static bool get _isTestEnv =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static Future<bool> setFullscreen(bool fullscreen) async {
    if (_isTestEnv) {
      _isFullscreen = fullscreen;
      return _isFullscreen;
    }
    if (kIsWeb) {
      _isFullscreen = fullscreen;
      return _isFullscreen;
    }
    try {
      if (Platform.isWindows) {
        final res = await _channel.invokeMethod<bool>('setFullscreen', fullscreen);
        _isFullscreen = res ?? fullscreen;
        return _isFullscreen;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(
          fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
        _isFullscreen = fullscreen;
        return _isFullscreen;
      }
    } catch (_) {
      _isFullscreen = fullscreen;
    }
    return _isFullscreen;
  }

  static Future<bool> enterFullscreen() => setFullscreen(true);
  static Future<bool> exitFullscreen() => setFullscreen(false);
  static Future<bool> toggleFullscreen() => setFullscreen(!_isFullscreen);
}
