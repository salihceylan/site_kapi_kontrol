import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';

/// Katılım başvurularının kapatılma (dismiss/consumed) durumunu yerel hafızada ([SharedPreferences]) saklar.
/// Bir başvuru onaylandığında veya reddedildiğinde sakin "Anladım" diyerek kartı kapattığında bir daha ekranda gösterilmez.
class JoinRequestTracker {
  static const String prefsKey = 'consumed_join_request_ids';
  static Set<int>? _memoryConsumed;

  static Future<Set<int>> loadConsumed() async {
    if (_memoryConsumed != null) return _memoryConsumed!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(prefsKey) ?? <String>[];
      _memoryConsumed = list.map(int.tryParse).whereType<int>().toSet();
    } catch (_) {
      _memoryConsumed = <int>{};
    }
    return _memoryConsumed!;
  }

  static bool isConsumed(int id) {
    return _memoryConsumed?.contains(id) ?? false;
  }

  static Future<void> consume(int id) async {
    final set = await loadConsumed();
    set.add(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, set.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  static List<JoinRequestRecord> filterVisible(List<JoinRequestRecord> list) {
    final set = _memoryConsumed;
    if (set == null) return list;
    return list.where((r) => !set.contains(r.id)).toList();
  }
}
