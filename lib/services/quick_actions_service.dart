import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import 'package:site_kapi_kontrol/models/door_record.dart';

class QuickActionsService {
  final QuickActions _quickActions = const QuickActions();
  void Function(String actionType)? onActionSelected;

  void initialize(void Function(String actionType) onAction) {
    if (kIsWeb) {
      return;
    }
    onActionSelected = onAction;
    try {
      // initialize() bir Future döndürür: eklenti yoksa (ör. Windows/Linux masaüstü)
      // MissingPluginException asenkron fırlar; yakalanmazsa "yakalanmamış istisna" olur.
      unawaited(
        _quickActions
            .initialize((String type) {
              onActionSelected?.call(type);
            })
            .catchError((Object e) {
              debugPrint('[QuickActions] initialize yok sayıldı: $e');
            }),
      );
    } catch (e) {
      debugPrint('[QuickActions] initialize yok sayıldı: $e');
    }
  }

  Future<void> updateDoorShortcuts(List<DoorRecord> doors) async {
    if (kIsWeb) {
      return;
    }

    final items = <ShortcutItem>[
      const ShortcutItem(
        type: 'voice_open',
        localizedTitle: '🎙️ Sesli Kapı Aç',
        icon: 'ic_launcher',
      ),
    ];

    final sortedDoors = List<DoorRecord>.from(doors)
      ..sort((a, b) => a.doorIndex.compareTo(b.doorIndex));

    for (final door in sortedDoors.take(3)) {
      items.add(
        ShortcutItem(
          type: 'open_door_${door.id}',
          localizedTitle: '🚪 ${door.doorName}',
          icon: 'ic_launcher',
        ),
      );
    }

    try {
      await _quickActions.setShortcutItems(items);
    } catch (_) {
      // Ignored on unsupported platforms (e.g. desktop/web)
    }
  }

  Future<void> clearShortcuts() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _quickActions.clearShortcutItems();
    } catch (_) {}
  }
}

