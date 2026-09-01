import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';

enum DeepLinkActionType {
  openDoorById,
  openDoorByIndex,
  openFirstDoor,
  triggerVoice,
}

class DeepLinkAction {
  final DeepLinkActionType type;
  final int? doorId;
  final int? doorIndex;

  const DeepLinkAction({
    required this.type,
    this.doorId,
    this.doorIndex,
  });
}

class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  void Function(DeepLinkAction action)? onAction;

  void initialize(void Function(DeepLinkAction action) handleAction) {
    if (kIsWeb) {
      return;
    }
    onAction = handleAction;

    try {
      // Check initial deep link
      _appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          _handleUri(uri);
        }
      }).catchError((_) {});

      // Listen to incoming deep links while app is in background/foreground
      _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
        _handleUri(uri);
      }, onError: (_) {});
    } catch (_) {}
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'sitekapi') {
      return;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == 'voice' || path.contains('voice')) {
      onAction?.call(const DeepLinkAction(type: DeepLinkActionType.triggerVoice));
      return;
    }

    if (host == 'open' || path.contains('open') || host.isEmpty) {
      final doorIdParam = uri.queryParameters['doorId'] ?? uri.queryParameters['id'];
      final doorIndexParam = uri.queryParameters['doorIndex'] ?? uri.queryParameters['index'] ?? uri.queryParameters['kapi'];

      if (doorIdParam != null && int.tryParse(doorIdParam) != null) {
        onAction?.call(
          DeepLinkAction(
            type: DeepLinkActionType.openDoorById,
            doorId: int.parse(doorIdParam),
          ),
        );
        return;
      }

      if (doorIndexParam != null && int.tryParse(doorIndexParam) != null) {
        onAction?.call(
          DeepLinkAction(
            type: DeepLinkActionType.openDoorByIndex,
            doorIndex: int.parse(doorIndexParam),
          ),
        );
        return;
      }

      // Default: Open the user's primary/first door
      onAction?.call(const DeepLinkAction(type: DeepLinkActionType.openFirstDoor));
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
