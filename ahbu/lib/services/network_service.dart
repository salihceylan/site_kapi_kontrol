import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ahbu/config/app_config.dart';

class NetworkService extends ChangeNotifier {
  NetworkService({this.enabled = true});

  final bool enabled;

  bool _isReady = false;
  bool _isChecking = false;
  bool _hasInternet = true;

  bool get isReady => _isReady;
  bool get isChecking => _isChecking;
  bool get hasInternet => _hasInternet;

  Future<void> initialize() async {
    if (!enabled) {
      _isReady = true;
      _hasInternet = true;
      notifyListeners();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (!enabled || _isChecking) {
      return;
    }

    _isChecking = true;
    notifyListeners();

    final hasInternet = await _probeInternet();
    _hasInternet = hasInternet;
    _isChecking = false;
    _isReady = true;
    notifyListeners();
  }

  Future<bool> _probeInternet() async {
    final urls = <Uri>[
      Uri.parse('$apiBaseUrl/health'),
      Uri.parse('https://clients3.google.com/generate_204'),
    ];

    for (final uri in urls) {
      try {
        final response = await http
            .get(uri, headers: const {'Cache-Control': 'no-cache'})
            .timeout(const Duration(seconds: 5));
        if (response.statusCode >= 200 && response.statusCode < 400) {
          return true;
        }
      } catch (_) {
        // Fallback URL deneriz.
      }
    }

    return false;
  }
}
