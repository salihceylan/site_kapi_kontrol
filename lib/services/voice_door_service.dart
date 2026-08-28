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
  bool _handsFreeAutoListen = false;

  VoiceDoorService({required AuthService authService})
      : _authService = authService {
    _initTts();
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
      _handsFreeAutoListen = prefs.getBool(_prefHandsFreeKey) ?? false;
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
    if (!_ttsEnabled || text.trim().isEmpty) {
      return;
    }
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<bool> initializeSpeech() async {
    if (_isSpeechAvailable) {
      return true;
    }
    _status = VoiceStatus.initializing;
    notifyListeners();

    try {
      _isSpeechAvailable = await _speech.initialize(
        onError: (val) {
          _status = VoiceStatus.error;
          _feedbackText = 'Ses algılanamadı (${val.errorMsg})';
          notifyListeners();
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (_status == VoiceStatus.listening) {
              _processCurrentRecognizedWords();
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
    _feedbackText = 'Dinleniyor... "Site Kapısı 1\'i aç" diyebilirsiniz.';
    _matchedDoor = null;
    _status = VoiceStatus.listening;
    notifyListeners();

    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'tr_TR',
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
        ),
        onResult: (result) {
          _recognizedWords = result.recognizedWords;
          notifyListeners();
          if (result.finalResult) {
            _processVoiceCommand(_recognizedWords, candidateDoors: candidateDoors);
          }
        },
      );
    } catch (e) {
      _status = VoiceStatus.error;
      _feedbackText = 'Ses dinlenirken hata oluştu.';
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    if (_status == VoiceStatus.listening) {
      _processCurrentRecognizedWords();
    }
  }

  void _processCurrentRecognizedWords() {
    if (_recognizedWords.trim().isNotEmpty && _status == VoiceStatus.listening) {
      _processVoiceCommand(_recognizedWords);
    } else if (_status == VoiceStatus.listening) {
      _status = VoiceStatus.idle;
      _feedbackText = '';
      notifyListeners();
    }
  }

  Future<VoiceDoorResult> _processVoiceCommand(
    String rawCommand, {
    List<DoorRecord>? candidateDoors,
  }) async {
    _status = VoiceStatus.processing;
    _feedbackText = 'Komut işleniyor...';
    notifyListeners();

    if (rawCommand.trim().isEmpty) {
      const message = 'Ses algılanamadı.';
      _status = VoiceStatus.error;
      _feedbackText = message;
      notifyListeners();
      await speak(message);
      return const VoiceDoorResult(
        success: false,
        recognizedText: '',
        feedbackMessage: message,
      );
    }

    List<DoorRecord> doors = candidateDoors ?? <DoorRecord>[];
    if (doors.isEmpty) {
      final (fetchedDoors, _) = await _authService.listMyDoors();
      if (fetchedDoors != null) {
        doors = fetchedDoors;
      }
    }

    final matched = matchDoorFromCommand(rawCommand, doors);
    if (matched == null) {
      final message = doors.isEmpty
          ? 'Tanımlı bir kapı bulunamadı.'
          : 'Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin.';
      _status = VoiceStatus.error;
      _feedbackText = 'Anlaşılamadı';
      notifyListeners();
      await speak(message);
      return VoiceDoorResult(
        success: false,
        recognizedText: rawCommand,
        feedbackMessage: message,
      );
    }

    _matchedDoor = matched;
    _feedbackText = '${matched.doorName} açılıyor...';
    notifyListeners();
    await speak('${matched.doorName} açılıyor.');

    final (status, error) = await _authService.openDoor(
      doorId: matched.id,
      door: matched,
    );

    if (status != null && error == null) {
      _status = VoiceStatus.success;
      _feedbackText = '${matched.doorName} başarıyla açıldı.';
      notifyListeners();
      return VoiceDoorResult(
        success: true,
        recognizedText: rawCommand,
        matchedDoor: matched,
        feedbackMessage: '${matched.doorName} açıldı.',
      );
    } else {
      final errorMsg = error ?? 'Kapı açılamadı.';
      _status = VoiceStatus.error;
      _feedbackText = errorMsg;
      notifyListeners();
      await speak(errorMsg);
      return VoiceDoorResult(
        success: false,
        recognizedText: rawCommand,
        matchedDoor: matched,
        feedbackMessage: errorMsg,
      );
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
          normalized.contains('kapiyi')) {
        return availableDoors.first;
      }
    }

    final extractedNumber = _extractDoorNumber(normalized);
    const stopWords = {'kapi', 'kapisi', 'kapiyi', 'site', 'sitesi', 'ac', 'aci', 'acma', 'lutfen', 've', 'ile', 'bana', 'biraz'};

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
        if (word.length >= 3 && !stopWords.contains(word) && normalized.contains(word)) {
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
    // Rakamlar
    final digitMatch = RegExp(r'\b(\d+)\b').firstMatch(text);
    if (digitMatch != null) {
      return int.tryParse(digitMatch.group(1)!);
    }

    // Türkçe sayı kelimeleri
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
