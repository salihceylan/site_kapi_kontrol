import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

enum VoiceStatus {
  idle,
  initializing,
  listening,
  processing,
  success,
  error,
}

class VoiceDoorResult {
  final bool success;
  final String recognizedText;
  final DoorRecord? matchedDoor;
  final String feedbackMessage;

  const VoiceDoorResult({
    required this.success,
    required this.recognizedText,
    this.matchedDoor,
    required this.feedbackMessage,
  });
}

class VoiceDoorService extends ChangeNotifier {
  static const String _prefHandsFreeKey = 'hands_free_auto_listen';

  final AuthService _authService;
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  VoiceStatus _status = VoiceStatus.idle;
  String _recognizedWords = '';
  String _feedbackText = '';
  DoorRecord? _matchedDoor;
  bool _isSpeechAvailable = false;
  bool _ttsEnabled = true;
  bool _handsFreeAutoListen = true;
  bool _isProcessingCommand = false;
  DateTime? _lastCommandProcessedAt;
  List<DoorRecord>? _lastCandidateDoors;

  VoiceDoorService({required AuthService authService})
      : _authService = authService {
    if (!kIsWeb) {
      _initTts();
    }
    loadSettings();
  }

  VoiceStatus get status => _status;
  String get recognizedWords => _recognizedWords;
  String get feedbackText => _feedbackText;
  DoorRecord? get matchedDoor => _matchedDoor;
  bool get isListening => _status == VoiceStatus.listening;
  bool get isSpeechAvailable => _isSpeechAvailable;
  bool get ttsEnabled => _ttsEnabled;
  bool get handsFreeAutoListen => _handsFreeAutoListen;

  set ttsEnabled(bool value) {
    _ttsEnabled = value;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _handsFreeAutoListen = prefs.getBool(_prefHandsFreeKey) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setHandsFreeAutoListen(bool value) async {
    _handsFreeAutoListen = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefHandsFreeKey, value);
    } catch (_) {}
  }

  Future<void> _initTts() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _tts.setLanguage('tr-TR');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Ignored if platform doesn't support TTS
    }
  }

  Future<void> speak(String text) async {
    if (kIsWeb || !_ttsEnabled || text.trim().isEmpty) {
      return;
    }
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<bool> initializeSpeech() async {
    if (kIsWeb) {
      _isSpeechAvailable = false;
      return false;
    }
    if (_isSpeechAvailable) {
      return true;
    }
    _status = VoiceStatus.initializing;
    _feedbackText = 'Ses motoru başlatılıyor...';
    notifyListeners();

    try {
      _isSpeechAvailable = await _speech.initialize(
        onError: (val) {
          if (_status == VoiceStatus.listening && !_isProcessingCommand) {
            _status = VoiceStatus.error;
            _feedbackText = 'Ses algılanamadı (${val.errorMsg})';
            notifyListeners();
          }
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (_status == VoiceStatus.listening && !_isProcessingCommand) {
              final words = _recognizedWords.trim();
              _recognizedWords = '';
              if (words.isNotEmpty) {
                _processVoiceCommand(words, candidateDoors: _lastCandidateDoors);
              } else {
                _status = VoiceStatus.idle;
                _feedbackText = '';
                notifyListeners();
              }
            }
          }
        },
      );
    } catch (e) {
      _isSpeechAvailable = false;
      _status = VoiceStatus.error;
      _feedbackText = 'Ses motoru başlatılamadı.';
    }

    if (!_isSpeechAvailable) {
      _status = VoiceStatus.error;
      _feedbackText = 'Mikrofon veya ses tanıma izni alınamadı.';
    } else {
      _status = VoiceStatus.idle;
    }
    notifyListeners();
    return _isSpeechAvailable;
  }

  Future<void> startListening({List<DoorRecord>? candidateDoors}) async {
    if (candidateDoors != null && candidateDoors.isNotEmpty) {
      _lastCandidateDoors = candidateDoors;
    }

    if (_isProcessingCommand) {
      return;
    }

    if (!_isSpeechAvailable) {
      final ready = await initializeSpeech();
      if (!ready) {
        return;
      }
    }

    if (_speech.isListening) {
      await _speech.stop();
    }

    _recognizedWords = '';
    _feedbackText = 'Dinleniyor... "Kapıyı aç" diyebilirsiniz.';
    _matchedDoor = null;
    _status = VoiceStatus.listening;
    notifyListeners();

    try {
      String selectedLocaleId = 'tr_TR';
      try {
        final locales = await _speech.locales();
        final tr = locales
            .where((l) => l.localeId.toLowerCase().startsWith('tr'))
            .firstOrNull;
        if (tr != null) {
          selectedLocaleId = tr.localeId;
        }
      } catch (_) {}

      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: selectedLocaleId,
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;

          _recognizedWords = words;
          notifyListeners();

          if (result.finalResult && !_isProcessingCommand) {
            _recognizedWords = '';
            _speech.stop();
            _processVoiceCommand(
              words,
              candidateDoors: candidateDoors ?? _lastCandidateDoors,
            );
          }
        },
      );
    } catch (e) {
      _status = VoiceStatus.error;
      _feedbackText = 'Mikrofon başlatılırken hata oluştu.';
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    if (_status == VoiceStatus.listening && !_isProcessingCommand) {
      final words = _recognizedWords.trim();
      _recognizedWords = '';
      if (words.isNotEmpty) {
        _processVoiceCommand(words, candidateDoors: _lastCandidateDoors);
      } else {
        _status = VoiceStatus.idle;
        _feedbackText = '';
        notifyListeners();
      }
    }
  }

  Future<VoiceDoorResult> _processVoiceCommand(
    String rawCommand, {
    List<DoorRecord>? candidateDoors,
  }) async {
    final command = rawCommand.trim();
    if (command.isEmpty) {
      return const VoiceDoorResult(
        success: false,
        recognizedText: '',
        feedbackMessage: 'Ses algılanamadı.',
      );
    }

    if (_isProcessingCommand) {
      return const VoiceDoorResult(
        success: false,
        recognizedText: '',
        feedbackMessage: 'Komut zaten işleniyor.',
      );
    }

    final now = DateTime.now();
    if (_lastCommandProcessedAt != null &&
        now.difference(_lastCommandProcessedAt!).inSeconds < 5) {
      return const VoiceDoorResult(
        success: false,
        recognizedText: '',
        feedbackMessage: 'Komut yakın zamanda işlendi.',
      );
    }

    _isProcessingCommand = true;
    _lastCommandProcessedAt = now;
    _recognizedWords = '';

    try {
      if (_speech.isListening) {
        try {
          await _speech.stop();
        } catch (_) {}
      }

      _status = VoiceStatus.processing;
      _feedbackText = 'Komut işleniyor: "$command"...';
      notifyListeners();

      List<DoorRecord> doors =
          candidateDoors ?? _lastCandidateDoors ?? <DoorRecord>[];
      if (doors.isEmpty) {
        final (fetchedDoors, _) = await _authService.listMyDoors();
        if (fetchedDoors != null) {
          doors = fetchedDoors;
          _lastCandidateDoors = doors;
        }
      }

      if (doors.isEmpty) {
        const message = 'Tanımlı bir kapı bulunamadı.';
        _status = VoiceStatus.error;
        _feedbackText = message;
        notifyListeners();
        await speak(message);
        return VoiceDoorResult(
          success: false,
          recognizedText: command,
          feedbackMessage: message,
        );
      }

      final matched = matchDoorFromCommand(command, doors);
      if (matched == null) {
        const message =
            'Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin.';
        _status = VoiceStatus.error;
        _feedbackText = message;
        notifyListeners();
        await speak(message);
        return VoiceDoorResult(
          success: false,
          recognizedText: command,
          feedbackMessage: message,
        );
      }

      if (matched.assignedDeviceUid == null ||
          matched.assignedDeviceUid!.trim().isEmpty) {
        final message =
            '${matched.doorName} kapısına henüz aktif bir cihaz atanmamış.';
        _status = VoiceStatus.error;
        _feedbackText = message;
        notifyListeners();
        await speak(message);
        return VoiceDoorResult(
          success: false,
          recognizedText: command,
          matchedDoor: matched,
          feedbackMessage: message,
        );
      }

      _matchedDoor = matched;
      _feedbackText = '${matched.doorName} açılıyor...';
      notifyListeners();

      final (status, error) = await _authService.openDoor(
        doorId: matched.id,
        door: matched,
      );

      if (status != null && error == null) {
        _status = VoiceStatus.success;
        _feedbackText = '${matched.doorName} başarıyla açıldı.';
        notifyListeners();
        await speak('${matched.doorName} başarıyla açıldı.');
        return VoiceDoorResult(
          success: true,
          recognizedText: command,
          matchedDoor: matched,
          feedbackMessage: '${matched.doorName} açıldı.',
        );
      } else {
        final errorMsg =
            error ?? 'Kapı açılamadı. Cihaz bağlantısı çevrimdışı olabilir.';
        _status = VoiceStatus.error;
        _feedbackText = errorMsg;
        notifyListeners();
        await speak(errorMsg);
        return VoiceDoorResult(
          success: false,
          recognizedText: command,
          matchedDoor: matched,
          feedbackMessage: errorMsg,
        );
      }
    } finally {
      await Future.delayed(const Duration(seconds: 3));
      _isProcessingCommand = false;
    }
  }

  /// Doğal Türkçe ses komutunu kapılarla akıllı eşleştirir
  static DoorRecord? matchDoorFromCommand(
    String text,
    List<DoorRecord> availableDoors,
  ) {
    if (availableDoors.isEmpty) {
      return null;
    }

    final normalized = _normalizeTurkish(text);
    if (normalized.isEmpty) {
      return null;
    }

    // Tek kapı varsa ve kullanıcı "aç" / "kapı" diyorsa
    if (availableDoors.length == 1) {
      if (normalized.contains('ac') ||
          normalized.contains('kapi') ||
          normalized.contains('kapiyi') ||
          normalized.contains('kapi')) {
        return availableDoors.first;
      }
    }

    final extractedNumber = _extractDoorNumber(normalized);
    const stopWords = {
      'kapi',
      'kapisi',
      'kapiyi',
      'site',
      'sitesi',
      'ac',
      'aci',
      'acma',
      'lutfen',
      've',
      'ile',
      'bana',
      'biraz'
    };

    DoorRecord? bestDoor;
    int highestScore = 0;

    for (final door in availableDoors) {
      int score = 0;
      final doorNorm = _normalizeTurkish(door.doorName);

      // 1. Kapı index / sayı eşleşmesi
      if (extractedNumber != null) {
        if (door.doorIndex == extractedNumber) {
          score += 20;
        } else if (doorNorm.contains('$extractedNumber')) {
          score += 15;
        }
      }

      // 2. Tam veya parça isim geçişi
      if (doorNorm.isNotEmpty && normalized.contains(doorNorm)) {
        score += 30;
      }

      // 3. Özgül kelime eşleşmesi (stop words hariç)
      final doorWords = doorNorm.split(RegExp(r'\s+'));
      for (final word in doorWords) {
        if (word.length >= 3 &&
            !stopWords.contains(word) &&
            normalized.contains(word)) {
          score += 10;
        }
      }

      if (score > highestScore) {
        highestScore = score;
        bestDoor = door;
      }
    }

    if (bestDoor != null && highestScore > 0) {
      return bestDoor;
    }

    // Son çare: Kullanıcı genel "kapıyı aç" diyor
    if (normalized.contains('ac') || normalized.contains('kapi')) {
      return availableDoors.first;
    }

    return null;
  }

  static String _normalizeTurkish(String text) {
    return text
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r"[^\w\s]"), ' ')
        .trim();
  }

  static int? _extractDoorNumber(String text) {
    final digitMatch = RegExp(r'\b(\d+)\b').firstMatch(text);
    if (digitMatch != null) {
      return int.tryParse(digitMatch.group(1)!);
    }

    if (text.contains('bir') || text.contains('1')) return 1;
    if (text.contains('iki') || text.contains('2')) return 2;
    if (text.contains('uc') || text.contains('3')) return 3;
    if (text.contains('dort') || text.contains('4')) return 4;
    if (text.contains('bes') || text.contains('5')) return 5;
    if (text.contains('alti') || text.contains('6')) return 6;
    if (text.contains('yedi') || text.contains('7')) return 7;
    if (text.contains('sekiz') || text.contains('8')) return 8;
    if (text.contains('dokuz') || text.contains('9')) return 9;
    if (text.contains('on') || text.contains('10')) return 10;

    return null;
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
