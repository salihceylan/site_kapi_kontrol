// P2-21 / P2-26 yardımcıları: "bağlı değil" ayrımı, liste yükleyicilerinin errorOffline + lastLoadedAt alanları ve genel
// yenilemenin durumu (RefreshStatus).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/connectivity_error.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/refresh_status.dart';

/// dart:io'nun SocketException'ı web derlemesinde yok: istemci tür adıyla tanır (bu sınıf aynı adı taşır).
class SocketException implements Exception {
  const SocketException();
}

void main() {
  group('isConnectivityError: bağlı değil mi, hata mı?', () {
    test('taşıma hataları bağlı değildir: zaman aşımı, istemci hatası, soket', () {
      expect(isConnectivityError(TimeoutException('x')), isTrue);
      expect(isConnectivityError(http.ClientException('Connection closed')), isTrue);
      expect(isConnectivityError(const SocketException()), isTrue);
    });

    test('hizmet katmanının durum kodsuz taşıma mesajları (gerçek metinler) bağlı değildir', () {
      const messages = <String>[
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
        'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
        'Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin.',
        'Sunucu yanıt vermedi, tekrar deneyin.',
        'Sunucu zamanında yanıt vermedi. İşlem tamamlanmış olabilir; listeyi yenileyip kontrol edin.',
        'Sunucu yanıt vermedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        'İnternet bağlantısı yok (Modem internete bağlı değil).',
        'SSL baglantisi kurulurken hata olustu.',
      ];
      for (final message in messages) {
        expect(isConnectivityError(ApiException(message)), isTrue, reason: message);
      }
    });

    test('sunucu bir durum koduyla YANIT verdiyse bağlantı vardır: hatadır (502/503/504 hariç)', () {
      for (final status in <int>[400, 401, 403, 404, 409, 422, 429, 500]) {
        expect(
          isConnectivityError(ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.', statusCode: status)),
          isFalse,
          reason: 'durum $status',
        );
      }
      for (final status in <int>[502, 503, 504]) {
        expect(isConnectivityError(ApiException('Sunucu şu anda yanıt veremiyor ($status).', statusCode: status)), isTrue,
            reason: 'durum $status ağ geçidi / bakım: ulaşılamıyor');
      }
    });

    test('araya giren katman (proxy / WAF / captive portal) ulaşılamıyor demektir', () {
      expect(isConnectivityError(ApiException('Beklenmeyen', statusCode: 403, fromIntermediary: true)), isTrue);
    });

    test('iş hataları ve programlama hataları bağlı değil DEĞİLDİR', () {
      expect(isConnectivityError(ApiException('Bu işlem için yetkiniz yok.')), isFalse);
      expect(isConnectivityError(ApiException('Duyuru verisi işlenemedi.')), isFalse);
      expect(isConnectivityError(StateError('hata')), isFalse);
      expect(isConnectivityError(const FormatException('x')), isFalse);
      expect(isConnectivityError(ArgumentError('x')), isFalse);
      expect(isConnectivityError(null), isFalse);
    });
  });

  group('PagedLoader: errorOffline + lastLoadedAt', () {
    late DateTime now;
    late List<PagedResult<int>> pages;
    late Object? failure;

    PagedLoader<int> make() => PagedLoader<int>(
          fetch: (offset, limit) async {
            final error = failure;
            if (error != null) throw error;
            return pages.removeAt(0);
          },
          keyOf: (i) => i,
          notify: () {},
          isAlive: () => true,
          clock: () => now,
        );

    setUp(() {
      now = DateTime.utc(2026, 10, 28, 11, 32);
      pages = <PagedResult<int>>[(items: <int>[1, 2], total: 2), (items: <int>[1, 2, 3], total: 3)];
      failure = null;
    });

    test('başarılı yükleme lastLoadedAt\'i yazar; yeniden yükleme saati ilerletir', () async {
      final loader = make();
      expect(loader.lastLoadedAt, isNull);
      await loader.reload();
      expect(loader.lastLoadedAt, now);
      expect(loader.errorOffline, isFalse);
      now = now.add(const Duration(minutes: 5));
      await loader.reload();
      expect(loader.lastLoadedAt, now);
    });

    test('ağ hatası: errorOffline true, eski kayıtlar ve eski saat korunur; sunucu hatası: errorOffline false', () async {
      final loader = make();
      await loader.reload();
      final first = loader.lastLoadedAt;

      failure = ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      now = now.add(const Duration(minutes: 5));
      await loader.reload();
      expect(loader.error, 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      expect(loader.errorOffline, isTrue);
      expect(loader.items, <int>[1, 2], reason: 'yenileme hatası eski listeyi silmez');
      expect(loader.lastLoadedAt, first, reason: 'başarısız yenileme saati ilerletmez');

      failure = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403);
      await loader.reload();
      expect(loader.errorOffline, isFalse);
      expect(loader.error, 'Bu işlem için yetkiniz yok.');

      failure = null;
      await loader.reload();
      expect(loader.error, isNull);
      expect(loader.errorOffline, isFalse, reason: 'başarılı yükleme bayrağı temizler');
    });

    test('reset: eski kayıtlarla birlikte saat ve bayraklar da silinir (süzgeç değişince eski saat gösterilmez)', () async {
      final loader = make();
      await loader.reload();
      loader.reset();
      expect(loader.lastLoadedAt, isNull);
      expect(loader.errorOffline, isFalse);
      expect(loader.items, isEmpty);
    });

    test('daha fazla yükle hatası: moreErrorOffline ayrı izlenir', () async {
      final loader = make();
      pages = <PagedResult<int>>[(items: <int>[1, 2], total: 5)];
      await loader.reload();
      expect(loader.hasMore, isTrue);
      failure = TimeoutException('x');
      await loader.loadMore();
      expect(loader.moreError, isNotNull);
      expect(loader.moreErrorOffline, isTrue);
      expect(loader.errorOffline, isFalse, reason: 'ilk sayfa hatası değil');
      failure = null;
      pages = <PagedResult<int>>[(items: <int>[3], total: 5)];
      await loader.loadMore();
      expect(loader.moreError, isNull);
      expect(loader.moreErrorOffline, isFalse);
    });
  });

  group('CursorLoader: errorOffline + lastLoadedAt', () {
    test('başarı saati yazar, ağ hatası errorOffline yapar, reset ikisini de siler', () async {
      var now = DateTime.utc(2026, 10, 28, 11, 32);
      Object? failure;
      final loader = CursorLoader<int>(
        fetch: (before) async {
          final error = failure;
          if (error != null) throw error;
          return (items: <int>[1], next: null);
        },
        keyOf: (i) => i,
        notify: () {},
        isAlive: () => true,
        clock: () => now,
      );
      await loader.reload();
      expect(loader.lastLoadedAt, now);
      expect(loader.errorOffline, isFalse);

      failure = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      now = now.add(const Duration(hours: 1));
      await loader.reload();
      expect(loader.errorOffline, isTrue);
      expect(loader.lastLoadedAt, DateTime.utc(2026, 10, 28, 11, 32));

      loader.reset();
      expect(loader.lastLoadedAt, isNull);
      expect(loader.errorOffline, isFalse);
    });
  });

  group('RefreshStatus', () {
    test('çalışırken refreshing true; başarıyla bitince revision artar ve saat yazılır', () async {
      final at = DateTime.utc(2026, 10, 28, 11, 32);
      final status = RefreshStatus(clock: () => at);
      final gate = Completer<void>();
      var notifications = 0;
      status.addListener(() => notifications++);

      final run = status.run(() => gate.future);
      expect(status.refreshing, isTrue);
      expect(status.revision, 0);
      expect(status.lastRefreshedAt, isNull);

      gate.complete();
      await run;
      expect(status.refreshing, isFalse);
      expect(status.revision, 1);
      expect(status.lastRefreshedAt, at);
      expect(notifications, 2, reason: 'başlangıç + bitiş');
    });

    test('sürerken ikinci çağrı yeni tur BAŞLATMAZ, sürenin sonucunu bekler', () async {
      final status = RefreshStatus();
      final gate = Completer<void>();
      var calls = 0;
      final first = status.run(() {
        calls++;
        return gate.future;
      });
      final second = status.run(() {
        calls++;
        return Future<void>.value();
      });
      expect(calls, 1);
      gate.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(calls, 1);
      expect(status.revision, 1);

      await status.run(() async => calls++);
      expect(calls, 2, reason: 'bitince yeni tur başlayabilir');
      expect(status.revision, 2);
    });

    test('hata: çağırana iletilir, refreshing false olur, revision ve saat değişmez', () async {
      final status = RefreshStatus();
      await expectLater(status.run(() async => throw StateError('yenileme patladı')), throwsStateError);
      expect(status.refreshing, isFalse);
      expect(status.revision, 0);
      expect(status.lastRefreshedAt, isNull);
      await status.run(() async {});
      expect(status.revision, 1);
    });

    test('dispose sonrası biten yenileme bildirim göndermez (hata yok)', () async {
      final status = RefreshStatus();
      final gate = Completer<void>();
      final run = status.run(() => gate.future);
      status.dispose();
      gate.complete();
      await run;
    });
  });
}
