import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';

enum DeepLinkActionType {
  openDoorById,
  openDoorByIndex,
  openFirstDoor,
  triggerVoice,
  showQrForDoor,
}

class DeepLinkAction {
  final DeepLinkActionType type;
  final int? doorId;
  final int? doorIndex;

  /// Çok-siteli kullanıcıda kapıyı netleştirmek için (isteğe bağlı).
  final int? siteCode;

  const DeepLinkAction({
    required this.type,
    this.doorId,
    this.doorIndex,
    this.siteCode,
  });

  /// Bu eylem bir kapıyı AÇAR mı? (kullanıcı onayı gerektirir)
  bool get opensDoor =>
      type == DeepLinkActionType.openDoorById ||
      type == DeepLinkActionType.openDoorByIndex ||
      type == DeepLinkActionType.openFirstDoor;
}

/// Bir deep link eyleminin kullanıcının kapılarıyla eşleşme durumu.
enum DeepLinkDoorStatus {
  /// Tek ve net kapı bulundu.
  found,

  /// Kapı kullanıcının kapıları arasında yok.
  notFound,

  /// Birden çok kapı uyuyor (örn. farklı sitelerde aynı kapı numarası).
  ambiguous,

  /// "İlk kapıyı aç" istendi ama kullanıcının birden çok kapısı var.
  multipleDoors,
}

class DeepLinkDoorResolution {
  const DeepLinkDoorResolution(
    this.status, {
    this.door,
    this.candidates = const <DoorRecord>[],
  });

  final DeepLinkDoorStatus status;
  final DoorRecord? door;
  final List<DoorRecord> candidates;
}

/// Deep link eylemini kullanıcının KENDİ kapıları içinde doğrular. Dışarıdan gelen
/// bir doorId/doorIndex asla doğrudan açılmaz; kapı kullanıcının listesinde olmalı.
class DeepLinkDoorResolver {
  const DeepLinkDoorResolver._();

  static DeepLinkDoorResolution resolve(
    DeepLinkAction action,
    List<DoorRecord> doors,
  ) {
    // siteCode verildiyse yalnızca o sitenin kapıları değerlendirilir.
    final scoped = action.siteCode == null
        ? doors
        : doors.where((d) => d.siteCode == action.siteCode).toList();

    if (scoped.isEmpty) {
      return const DeepLinkDoorResolution(DeepLinkDoorStatus.notFound);
    }

    switch (action.type) {
      case DeepLinkActionType.openDoorById:
      case DeepLinkActionType.showQrForDoor:
        final id = action.doorId;
        if (id == null) {
          return const DeepLinkDoorResolution(DeepLinkDoorStatus.notFound);
        }
        return _fromMatches(scoped.where((d) => d.id == id).toList());
      case DeepLinkActionType.openDoorByIndex:
        final index = action.doorIndex;
        if (index == null) {
          return const DeepLinkDoorResolution(DeepLinkDoorStatus.notFound);
        }
        return _fromMatches(scoped.where((d) => d.doorIndex == index).toList());
      case DeepLinkActionType.openFirstDoor:
        // "İlk kapı" varsayımı yalnızca TEK kapı varsa geçerlidir.
        if (scoped.length == 1) {
          return DeepLinkDoorResolution(
            DeepLinkDoorStatus.found,
            door: scoped.first,
          );
        }
        return DeepLinkDoorResolution(
          DeepLinkDoorStatus.multipleDoors,
          candidates: List<DoorRecord>.of(scoped),
        );
      case DeepLinkActionType.triggerVoice:
        return const DeepLinkDoorResolution(DeepLinkDoorStatus.notFound);
    }
  }

  static DeepLinkDoorResolution _fromMatches(List<DoorRecord> matches) {
    if (matches.isEmpty) {
      return const DeepLinkDoorResolution(DeepLinkDoorStatus.notFound);
    }
    if (matches.length == 1) {
      return DeepLinkDoorResolution(
        DeepLinkDoorStatus.found,
        door: matches.first,
      );
    }
    return DeepLinkDoorResolution(
      DeepLinkDoorStatus.ambiguous,
      candidates: matches,
    );
  }
}

class _PendingAction {
  _PendingAction(this.action, this.queuedAt);

  final DeepLinkAction action;
  final DateTime queuedAt;
}

class DeepLinkService {
  /// Aynı bağlantının ardışık gelişi (getInitialLink + uriLinkStream çakışması,
  /// çift dokunuş) bu süre içinde TEK kez işlenir.
  static const Duration duplicateWindow = Duration(seconds: 2);

  /// Oturum hazır olmadan kuyruğa alınan eylemin geçerlilik süresi.
  static const Duration pendingMaxAge = Duration(seconds: 60);

  static const int _maxPending = 3;
  static const int _maxUriLength = 512;
  static const int _maxId = 2147483647;
  static const Set<String> _knownTargets = {'voice', 'qr', 'open'};

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  void Function(DeepLinkAction action)? onAction;

  bool _ready = false;
  final List<_PendingAction> _pending = <_PendingAction>[];
  String? _lastHandledUri;
  DateTime? _lastHandledAt;

  @visibleForTesting
  int get pendingCount => _pending.length;

  bool get isReady => _ready;

  void initialize(void Function(DeepLinkAction action) handleAction) {
    if (kIsWeb) {
      return;
    }
    onAction = handleAction;
    _linkSubscription?.cancel();
    _linkSubscription = null;

    try {
      // Check initial deep link.
      // NOT: app_links 6.x ilk bağlantıyı akışa da yazar (onListen); iki yoldan gelen
      // aynı bağlantı handleUri içindeki yinelenen-bağlantı penceresiyle teke indirilir.
      _appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          handleUri(uri);
        }
      }).catchError((_) {});

      // Listen to incoming deep links while app is in background/foreground
      _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
        handleUri(uri);
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Oturum (auth başlatma) hazır olduğunda çağrılır; o ana dek gelen eylemler
  /// kuyruktan (süresi dolmamışsa) sırayla işlenir.
  void markReady({DateTime? now}) {
    _ready = true;
    final at = now ?? DateTime.now();
    final queued = List<_PendingAction>.of(_pending);
    _pending.clear();
    for (final item in queued) {
      if (at.difference(item.queuedAt) <= pendingMaxAge) {
        onAction?.call(item.action);
      }
    }
  }

  /// Eylemi hazır durumdaysa hemen, değilse kuyruğa alarak iletir
  /// (kısayol/quick action gibi uri dışı kaynaklar da kullanabilir).
  void dispatch(DeepLinkAction action, {DateTime? now}) {
    if (!_ready) {
      _pending.add(_PendingAction(action, now ?? DateTime.now()));
      while (_pending.length > _maxPending) {
        _pending.removeAt(0);
      }
      return;
    }
    onAction?.call(action);
  }

  void clearPending() {
    _pending.clear();
  }

  /// Gelen URI'yi işler: yinelenenleri eler, ayrıştırır, hazır değilse kuyruğa alır.
  @visibleForTesting
  void handleUri(Uri uri, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final key = uri.toString();
    final lastAt = _lastHandledAt;
    if (_lastHandledUri == key &&
        lastAt != null &&
        !at.difference(lastAt).isNegative &&
        at.difference(lastAt) < duplicateWindow) {
      return;
    }
    _lastHandledUri = key;
    _lastHandledAt = at;

    final action = parseUri(uri);
    if (action == null) {
      return;
    }
    dispatch(action, now: at);
  }

  static int? _parsePositiveInt(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (!RegExp(r'^\d{1,10}$').hasMatch(trimmed)) return null;
    final value = int.tryParse(trimmed);
    if (value == null || value <= 0 || value > _maxId) return null;
    return value;
  }

  static String? _firstParam(Uri uri, List<String> names) {
    for (final name in names) {
      if (uri.queryParameters.containsKey(name)) {
        return uri.queryParameters[name];
      }
    }
    return null;
  }

  static bool _hasAnyParam(Uri uri, List<String> names) {
    return names.any(uri.queryParameters.containsKey);
  }

  /// `sitekapi://` URI'sini bir eyleme çevirir; tanınmayan / geçersiz parametreli
  /// bağlantılar için null döner (geçersiz kapı parametresi ASLA "ilk kapıyı aç"a
  /// dönüşmez).
  @visibleForTesting
  static DeepLinkAction? parseUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'sitekapi') {
      return null;
    }
    if (uri.toString().length > _maxUriLength) {
      return null;
    }

    var target = uri.host.toLowerCase();
    final firstSegment =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.first.toLowerCase() : '';
    if (!_knownTargets.contains(target) && _knownTargets.contains(firstSegment)) {
      target = firstSegment;
    }
    // "sitekapi://" / "sitekapi:///" gibi çıplak bağlantı (eski davranış: kapıyı aç).
    final isBare = target.isEmpty && firstSegment.isEmpty;

    const doorIdNames = ['doorId', 'id'];
    const doorIndexNames = ['doorIndex', 'index', 'kapi'];
    const siteNames = ['siteCode', 'site_code', 'site'];

    if (target == 'voice') {
      return const DeepLinkAction(type: DeepLinkActionType.triggerVoice);
    }

    final hasSiteParam = _hasAnyParam(uri, siteNames);
    final siteCode = _parsePositiveInt(_firstParam(uri, siteNames));
    if (hasSiteParam && siteCode == null) {
      return null;
    }

    if (target == 'qr') {
      final doorId = _parsePositiveInt(_firstParam(uri, doorIdNames));
      if (doorId == null) {
        return null;
      }
      return DeepLinkAction(
        type: DeepLinkActionType.showQrForDoor,
        doorId: doorId,
        siteCode: siteCode,
      );
    }

    if (target == 'open' || isBare) {
      if (_hasAnyParam(uri, doorIdNames)) {
        final doorId = _parsePositiveInt(_firstParam(uri, doorIdNames));
        if (doorId == null) {
          return null;
        }
        return DeepLinkAction(
          type: DeepLinkActionType.openDoorById,
          doorId: doorId,
          siteCode: siteCode,
        );
      }

      if (_hasAnyParam(uri, doorIndexNames)) {
        final doorIndex = _parsePositiveInt(_firstParam(uri, doorIndexNames));
        if (doorIndex == null) {
          return null;
        }
        return DeepLinkAction(
          type: DeepLinkActionType.openDoorByIndex,
          doorIndex: doorIndex,
          siteCode: siteCode,
        );
      }

      // Default: kullanıcının TEK kapısı varsa onu aç (çok kapıda kullanıcıya sorulur)
      return DeepLinkAction(
        type: DeepLinkActionType.openFirstDoor,
        siteCode: siteCode,
      );
    }

    return null;
  }

  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _pending.clear();
    onAction = null;
  }
}
