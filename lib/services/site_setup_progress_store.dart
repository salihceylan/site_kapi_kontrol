import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';

/// Site kurulum sihirbazı ilerlemesinin cihazdaki kaydı (P2-15: "yarım kalan kurulum devam eder").
///
/// - Kayıt KULLANICI başına tek anahtardadır ([keyFor]); içinde site başına bir ilerleme tutulur (süper kullanıcı ve
///   çok siteli yönetici her siteyi ayrı ayrı kurabilir). En çok [maxEntries] site tutulur, en eski güncellenen düşer.
/// - Yalnız yerel tercihlerdir (site adı ve adım adları; kişisel veri yok): hesap silinince `LocalDataWiper` tüm
///   `SharedPreferences` anahtarlarını zaten siler.
/// - Depolama okunamaz / yazılamazsa (özel pencere, engelli site verisi) sessizce "kayıt yok" davranılır; sihirbaz
///   yine çalışır, yalnız yarım kalan kurulum hatırlanmaz.
/// - Okuma-değiştirme-yazma işlemleri sıraya alınır: art arda gelen kayıtlar birbirini ezmez.
/// - Her değişiklik [changes] ile duyurulur (Panel hatırlatma kartı kendini tazeler).
class SiteSetupProgressStore extends ChangeNotifier {
  SiteSetupProgressStore({Future<SharedPreferences> Function()? preferences, DateTime Function()? now})
    : _preferences = preferences ?? SharedPreferences.getInstance,
      _now = now ?? DateTime.now;

  /// Uygulama genelinde ortak örnek (ekranlar ayrı örnek kurmaz). Üretimde hiç değiştirilmez; widget testleri her
  /// test öncesinde YENİSİNİ atar: kayıtlar bir sıraya (`_tail`) bağlıdır ve bitmiş bir testin sahte-zamanlı
  /// bölgesinde yarım kalan işlem sonraki testin kaydını sonsuza dek bekletirdi.
  static SiteSetupProgressStore shared = SiteSetupProgressStore();

  static const int maxEntries = 20;

  static String keyFor(int userId) => 'site_setup_wizard_v1_$userId';

  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;

  /// Sıranın sonu. İLK kullanımda, çağıranın bölgesinde (zone) kurulur: depo başka bir bölgede (örn. testin `setUp`ı) hazır
  /// bir `Future` ile başlarsa sıraya bağlanan işler o bölgenin mikro-görev kuyruğuna düşerdi.
  Future<void>? _tail;

  /// Kayıt değişti (kaydet / sil). Dinleyen yeniden okur.
  Listenable get changes => this;

  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = (_tail ?? Future<void>.value()).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<List<SiteSetupProgress>> _read(int userId) async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(keyFor(userId));
      if (raw == null || raw.isEmpty) return <SiteSetupProgress>[];
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['items'] : null;
      if (list is! List) return <SiteSetupProgress>[];
      final items = <SiteSetupProgress>[];
      for (final item in list) {
        final progress = SiteSetupProgress.fromJson(item);
        if (progress != null && !items.any((e) => e.siteCode == progress.siteCode)) items.add(progress);
      }
      return items;
    } catch (_) {
      return <SiteSetupProgress>[];
    }
  }

  Future<bool> _write(int userId, List<SiteSetupProgress> items) async {
    try {
      final prefs = await _preferences();
      final sorted = [...items]
        ..sort((a, b) {
          final left = a.updatedAt?.millisecondsSinceEpoch ?? 0;
          final right = b.updatedAt?.millisecondsSinceEpoch ?? 0;
          return right.compareTo(left);
        });
      final kept = sorted.take(maxEntries).toList(growable: false);
      if (kept.isEmpty) {
        await prefs.remove(keyFor(userId));
      } else {
        await prefs.setString(
          keyFor(userId),
          jsonEncode(<String, Object?>{'v': 1, 'items': <Map<String, Object?>>[for (final item in kept) item.toJson()]}),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kullanıcının tüm siteleri için kayıtlı ilerleme (en son güncellenen önce).
  Future<List<SiteSetupProgress>> loadAll(int userId) {
    return _serial(() async {
      final items = await _read(userId);
      items.sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));
      return items;
    });
  }

  /// Bir sitenin kayıtlı ilerlemesi; yoksa null.
  Future<SiteSetupProgress?> load(int userId, int siteCode) {
    return _serial(() async {
      for (final item in await _read(userId)) {
        if (item.siteCode == siteCode) return item;
      }
      return null;
    });
  }

  /// İlerlemeyi kaydeder (aynı siteninkini değiştirir). Zaman damgası yoksa şimdi eklenir.
  Future<void> save(int userId, SiteSetupProgress progress) {
    return _serial(() async {
      final stamped = progress.updatedAt == null ? progress.copyWith(updatedAt: _now()) : progress;
      final items = await _read(userId);
      final next = <SiteSetupProgress>[
        for (final item in items)
          if (item.siteCode != stamped.siteCode) item,
        stamped,
      ];
      if (await _write(userId, next)) notifyListeners();
    });
  }

  /// Sitenin kaydı YOKSA ilk kaydı açar ve açılırsa true döner (var olanı değiştirmez). Site yeni kurulduğunda ya da
  /// başvurusu onaylandığında Panel hatırlatmasını başlatmak için çağrılır.
  Future<bool> ensure(int userId, int siteCode, {String siteName = ''}) {
    return _serial(() async {
      final items = await _read(userId);
      if (items.any((item) => item.siteCode == siteCode)) return false;
      final created = SiteSetupProgress(siteCode: siteCode, siteName: siteName, updatedAt: _now());
      if (await _write(userId, <SiteSetupProgress>[...items, created])) {
        notifyListeners();
        return true;
      }
      return false;
    });
  }

  Future<void> remove(int userId, int siteCode) {
    return _serial(() async {
      final items = await _read(userId);
      final next = <SiteSetupProgress>[
        for (final item in items)
          if (item.siteCode != siteCode) item,
      ];
      if (next.length == items.length) return;
      if (await _write(userId, next)) notifyListeners();
    });
  }

  /// Hatırlatılması gereken en son kurulum (bitmemiş, kapatılmamış); yoksa null.
  Future<SiteSetupProgress?> nextUnfinished(int userId) async {
    for (final item in await loadAll(userId)) {
      if (item.needsAttention) return item;
    }
    return null;
  }
}
