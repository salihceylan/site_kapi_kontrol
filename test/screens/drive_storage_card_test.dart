// Dosya Deposu > Google Drive kartı: "silmeyi biz yapmayız" (K6) yönetici uyarıları.
// Bekleyen / uzun süredir bekleyen dosya ve dolu bekleme alanı uyarı olarak görünür (hiçbiri silme demez), "Bekleyenleri şimdi gönder" bekleyenleri
// göndermeyi dener. Eski sunucu (uyarı alanı yok) kartı bozmaz. AGENTS.md kural 6: dar ekranda ve koyu temada taşma yok.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/ui/widgets/drive_storage_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

http.Response _json(Map<String, Object?> body) =>
    http.Response(jsonEncode(body), 200, headers: const <String, String>{'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _status({
  bool connected = true,
  int pending = 0,
  int overdue = 0,
  List<Map<String, String>>? warnings,
}) => <String, Object?>{
  'configured': true,
  'connected': connected,
  'status': connected ? 'connected' : 'error',
  'account_email': 'site@example.com',
  'last_error': connected ? null : 'Drive erişimi kaldırıldı',
  'stored_count': 4,
  'pending_count': pending,
  'pending_overdue_count': overdue,
  'warnings': ?warnings,
};

Future<List<String>> _pumpCard(
  WidgetTester t,
  Future<http.Response> Function(http.Request request, List<String> log) respond, {
  double width = 360,
  bool dark = false,
}) async {
  final log = <String>[];
  final api = DriveStorageApi(
    baseUrl: 'http://localhost',
    client: MockClient((request) {
      log.add('${request.method} ${request.url.path}');
      return respond(request, log);
    }),
  );
  await pumpList(
    t,
    DriveStorageCard(authService: PeopleFakeAuth(), siteCode: 11, api: api),
    width: width,
    height: 900,
    scale: 1.0,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return log;
}

void main() {
  group('DriveStorageStatus.fromJson', () {
    test('uyarılar, uzun süredir bekleyen sayısı okunur; metni boş uyarı atılır', () {
      final status = DriveStorageStatus.fromJson(<String, dynamic>{
        'configured': true,
        'connected': true,
        'status': 'connected',
        'pending_count': 3,
        'pending_overdue_count': 2,
        'warnings': <Object?>[
          <String, Object?>{'code': 'DRIVE_FILES_OVERDUE', 'message': '2 dosya 7 günden uzun süredir bekliyor.'},
          <String, Object?>{'code': 'X', 'message': '   '},
          'bozuk',
        ],
      });
      expect(status.pendingCount, 3);
      expect(status.pendingOverdueCount, 2);
      expect(status.warnings.map((w) => w.code), <String>['DRIVE_FILES_OVERDUE']);
    });

    test('eski sunucu (uyarı alanı yok): boş liste, sayı 0', () {
      final status = DriveStorageStatus.fromJson(<String, dynamic>{'configured': true, 'connected': false, 'status': 'disconnected'});
      expect(status.warnings, isEmpty);
      expect(status.pendingOverdueCount, 0);
    });

    test('flush sonucu', () {
      final result = DriveFlushResult.fromJson(<String, dynamic>{'sent': 2, 'waiting': 1, 'overdue': 1, 'expired': 0});
      expect((result.sent, result.waiting, result.overdue), (2, 1, 1));
    });
  });

  group('Drive kartı: bekleyen dosya uyarıları', () {
    testWidgets('bekleyen dosya: uyarı kutusu ve "şimdi gönder" görünür; metin SİLME demez', (t) async {
      await _pumpCard(
        t,
        (request, log) async => _json(
          _status(
            pending: 2,
            warnings: <Map<String, String>>[
              <String, String>{'code': 'DRIVE_FILES_WAITING', 'message': "2 dosya Drive'a gönderilmeyi bekliyor. Silinmez; bağlantı sağlanınca gönderilir."},
            ],
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('drive_warning_DRIVE_FILES_WAITING')), findsOneWidget);
      expect(find.textContaining('Silinmez'), findsOneWidget);
      expect(find.text('Bekleyenleri şimdi gönder'), findsOneWidget);
      expect(find.textContaining('Bekleyen: 2'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('uzun süredir bekleyen + dolu bekleme alanı: iki uyarı, dosyalar silinmedi bilgisi; koyu temada taşma yok', (t) async {
      await _pumpCard(
        t,
        dark: true,
        width: 320,
        (request, log) async => _json(
          _status(
            pending: 5,
            overdue: 5,
            warnings: <Map<String, String>>[
              <String, String>{'code': 'DRIVE_QUEUE_FULL', 'message': "Bekleme alanı doldu (%97). Drive'a gönderilemeyen dosyalar silinmez; alan boşalana kadar yeni dosya kabul edilmez. Drive bağlantısını yenileyip bekleyenleri gönderin."},
              <String, String>{'code': 'DRIVE_FILES_OVERDUE', 'message': "5 dosya 7 günden uzun süredir Drive'a gönderilemedi. Dosyalar silinmedi; Drive bağlantısı düzelince gönderilir."},
            ],
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('drive_warning_DRIVE_QUEUE_FULL')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('drive_warning_DRIVE_FILES_OVERDUE')), findsOneWidget);
      expect(find.textContaining('Dosyalar silinmedi'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('bağlantı koptuysa uyarı yine görünür ama "şimdi gönder" yoktur (gönderim bağlantı gerektirir)', (t) async {
      await _pumpCard(
        t,
        (request, log) async => _json(
          _status(
            connected: false,
            pending: 1,
            warnings: <Map<String, String>>[
              <String, String>{'code': 'DRIVE_FILES_WAITING', 'message': "1 dosya Drive'a gönderilmeyi bekliyor. Silinmez; bağlantı sağlanınca gönderilir."},
            ],
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('drive_warning_DRIVE_FILES_WAITING')), findsOneWidget);
      expect(find.text('Bekleyenleri şimdi gönder'), findsNothing);
      expect(find.text('Google Drive bağla'), findsOneWidget);
    });

    testWidgets('bekleyen yoksa uyarı ve gönder düğmesi yok; eski sunucu (uyarı alanı yok) kartı bozmaz', (t) async {
      await _pumpCard(t, (request, log) async => _json(_status()));
      expect(find.byKey(const ValueKey<String>('drive_storage_card')), findsOneWidget);
      expect(find.textContaining('Bekleyen: 0'), findsOneWidget);
      expect(find.text('Bekleyenleri şimdi gönder'), findsNothing);
      expect(find.byKey(const ValueKey<String>('drive_warning_DRIVE_FILES_WAITING')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('"Bekleyenleri şimdi gönder": POST /flush çağrılır, sonra durum yeniden çekilir', (t) async {
      var flushed = false;
      final log = await _pumpCard(t, (request, log) async {
        if (request.method == 'POST' && request.url.path.endsWith('/flush')) {
          flushed = true;
          return _json(<String, Object?>{'sent': 2, 'waiting': 0, 'overdue': 0, 'expired': 0});
        }
        return _json(
          flushed
              ? _status()
              : _status(
                  pending: 2,
                  warnings: <Map<String, String>>[
                    <String, String>{'code': 'DRIVE_FILES_WAITING', 'message': "2 dosya Drive'a gönderilmeyi bekliyor. Silinmez; bağlantı sağlanınca gönderilir."},
                  ],
                ),
        );
      });
      await t.tap(find.text('Bekleyenleri şimdi gönder'));
      await settleFor(t, 100);
      await settleFor(t, 400);
      expect(log.where((l) => l == 'POST /manager/sites/11/drive/flush'), hasLength(1));
      expect(log.where((l) => l == 'GET /manager/sites/11/drive').length, greaterThanOrEqualTo(2), reason: 'gönderimden sonra durum yenilenir');
      expect(find.byKey(const ValueKey<String>('drive_warning_DRIVE_FILES_WAITING')), findsNothing);
      expect(find.text('Bekleyenleri şimdi gönder'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });
}
