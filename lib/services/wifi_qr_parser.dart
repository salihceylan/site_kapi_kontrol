import 'dart:convert';

class WifiQrCredentials {
  const WifiQrCredentials({
    required this.ssid,
    required this.password,
    this.authType = 'WPA',
    this.hidden = false,
  });

  final String ssid;
  final String password;
  final String authType;
  final bool hidden;

  static WifiQrCredentials? tryParse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Standard WIFI URI: WIFI:T:WPA;S:MyNetwork;P:MyPassword;H:false;;
    if (text.toLowerCase().startsWith('wifi:')) {
      final content = text.substring(5);
      String ssid = '';
      String password = '';
      String authType = 'WPA';
      bool hidden = false;

      final regex = RegExp(r'([A-Za-z]+):((?:\\;|[^;])*)');
      final matches = regex.allMatches(content);

      for (final match in matches) {
        final key = match.group(1)?.toUpperCase();
        var val = match.group(2) ?? '';
        // Unescape standard Wi-Fi QR characters: \;, \:, \\, \", \,
        val = val
            .replaceAll(r'\;', ';')
            .replaceAll(r'\:', ':')
            .replaceAll(r'\\', r'\')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\,', ',');

        if (key == 'S') {
          ssid = val;
        } else if (key == 'P') {
          password = val;
        } else if (key == 'T') {
          authType = val.toUpperCase();
        } else if (key == 'H') {
          hidden = val.toLowerCase() == 'true';
        }
      }

      if (ssid.isNotEmpty) {
        return WifiQrCredentials(
          ssid: ssid,
          password: password,
          authType: authType,
          hidden: hidden,
        );
      }
    }

    // 2. JSON format fallback e.g. {"ssid": "...", "password": "..."}
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(text) as Map<String, dynamic>;
        final dynamic rawSsid = json['ssid'] ?? json['SSID'];
        final dynamic rawPass =
            json['password'] ?? json['pass'] ?? json['key'] ?? '';
        if (rawSsid != null && rawSsid.toString().trim().isNotEmpty) {
          return WifiQrCredentials(
            ssid: rawSsid.toString().trim(),
            password: rawPass?.toString().trim() ?? '',
            authType: (json['type']?.toString() ?? 'WPA').toUpperCase(),
          );
        }
      } catch (_) {}
    }

    return null;
  }
}
