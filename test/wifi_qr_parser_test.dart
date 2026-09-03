import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/wifi_qr_parser.dart';

void main() {
  group('WifiQrCredentials Parser Tests', () {
    test('parses standard WPA wifi QR code', () {
      const qr = 'WIFI:T:WPA;S:SuperOnline_5G;P:SecretPass123;H:false;;';
      final creds = WifiQrCredentials.tryParse(qr);

      expect(creds, isNotNull);
      expect(creds!.ssid, 'SuperOnline_5G');
      expect(creds.password, 'SecretPass123');
      expect(creds.authType, 'WPA');
      expect(creds.hidden, isFalse);
    });

    test('parses wifi QR with different field order', () {
      const qr = 'WIFI:S:Home_Network;P:MySafePass;T:WPA2;;';
      final creds = WifiQrCredentials.tryParse(qr);

      expect(creds, isNotNull);
      expect(creds!.ssid, 'Home_Network');
      expect(creds.password, 'MySafePass');
      expect(creds.authType, 'WPA2');
    });

    test('parses open wifi with no password', () {
      const qr = 'WIFI:T:nopass;S:Cafe_Free_Wifi;;';
      final creds = WifiQrCredentials.tryParse(qr);

      expect(creds, isNotNull);
      expect(creds!.ssid, 'Cafe_Free_Wifi');
      expect(creds.password, '');
      expect(creds.authType, 'NOPASS');
    });

    test('handles escaped characters properly in SSID and password', () {
      const qr = r'WIFI:T:WPA;S:My\;Ssid\:Special;P:P\@ss\;word\\123;;';
      final creds = WifiQrCredentials.tryParse(qr);

      expect(creds, isNotNull);
      expect(creds!.ssid, 'My;Ssid:Special');
      expect(creds.password, r'P\@ss;word\123');
    });

    test('parses JSON format wifi QR', () {
      const qr = '{"ssid": "Office_Guest", "password": "guestPassword2026"}';
      final creds = WifiQrCredentials.tryParse(qr);

      expect(creds, isNotNull);
      expect(creds!.ssid, 'Office_Guest');
      expect(creds.password, 'guestPassword2026');
    });

    test('returns null for non-wifi strings', () {
      expect(WifiQrCredentials.tryParse(''), isNull);
      expect(WifiQrCredentials.tryParse('B86D72A172E0'), isNull);
      expect(WifiQrCredentials.tryParse('https://example.com'), isNull);
      expect(WifiQrCredentials.tryParse(null), isNull);
    });
  });
}

