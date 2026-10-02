// FAZ 5 / A2-G5: sesli kapı alt sayfası testlerinin ortak sahte servisi.
//
// Gerçek konuşma motoru/platform kanalı yoktur. Bu dosya `_test.dart` ile bitmediği için kendi
// başına test olarak çalışmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';

/// Durumu elle sürülen sahte servis. [startStatus] verilirse `startListening` bu duruma geçer
/// (alt sayfa açılışta otomatik dinleme başlatır).
class FakeVoiceDoorService extends ChangeNotifier implements VoiceDoorService {
  FakeVoiceDoorService({this.startStatus, this.startFeedback = ''});

  final VoiceStatus? startStatus;
  final String startFeedback;
  VoiceStatus _status = VoiceStatus.idle;
  String _feedback = '';
  bool _tts = true;
  bool _autoListen = true;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  VoiceStatus get status => _status;

  @override
  String get recognizedWords => '';

  @override
  String get feedbackText => _feedback;

  @override
  bool get isListening => _status == VoiceStatus.listening;

  @override
  bool get ttsEnabled => _tts;

  @override
  set ttsEnabled(bool value) {
    _tts = value;
    notifyListeners();
  }

  @override
  bool get handsFreeAutoListen => _autoListen;

  @override
  Future<void> setHandsFreeAutoListen(bool value) async {
    _autoListen = value;
    notifyListeners();
  }

  @override
  Future<void> startListening({List<DoorRecord>? candidateDoors}) async {
    startCalls++;
    final next = startStatus;
    if (next != null) {
      _status = next;
      _feedback = startFeedback;
      notifyListeners();
    }
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    _status = VoiceStatus.idle;
    _feedback = '';
    // Servis dispose sırasında da çağrılır: dinleyici bildirimi güvenli değildir.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
