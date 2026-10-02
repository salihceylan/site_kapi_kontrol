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

/// Sesli komutun kapıyla eşleşme durumu.
enum DoorMatchStatus {
  /// Tek ve net bir kapı bulundu.
  matched,

  /// Komutta "aç" fiili yok (örn. yalnızca kapı adı / alakasız cümle).
  noOpenIntent,

  /// Ters niyet: "kapat", "kilitle", "açma" gibi.
  reverseIntent,

  /// Birden çok kapı eşit derecede uyuyor ya da hangi kapı olduğu söylenmedi.
  ambiguous,

  /// Söylenen şey kullanıcının kapıları arasında yok.
  notFound,

  /// Kullanıcının kapısı yok.
  noDoors,
}

class DoorMatchResult {
  const DoorMatchResult(
    this.status, {
    this.door,
    this.candidates = const <DoorRecord>[],
  });

  final DoorMatchStatus status;
  final DoorRecord? door;

  /// `ambiguous` durumunda kullanıcıya sorulabilecek aday kapılar.
  final List<DoorRecord> candidates;

  bool get isMatch => status == DoorMatchStatus.matched && door != null;
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

  /// Oturum her kapandığında artar; eski oturumdan kalan asenkron işler sonucu yok sayar.
  int _sessionEpoch = 0;
  bool _disposed = false;

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

  @visibleForTesting
  List<DoorRecord>? get debugLastCandidateDoors => _lastCandidateDoors;

  set ttsEnabled(bool value) {
    _ttsEnabled = value;
    notifyListeners();
  }

  /// Oturum kapanınca çağrılır: önceki kullanıcıya ait kapı listesini, eşleşmeyi
  /// ve konuşma durumunu temizler (kullanıcı değişince eski kapılar kullanılmasın).
  /// `handsFreeAutoListen` gibi cihaz tercihleri korunur.
  void clearSession() {
    _sessionEpoch++;
    _lastCandidateDoors = null;
    _lastCommandProcessedAt = null;
    _matchedDoor = null;
    _recognizedWords = '';
    _feedbackText = '';
    _isProcessingCommand = false;
    _status = VoiceStatus.idle;
    if (!kIsWeb) {
      try {
        unawaited(_speech.stop().catchError((_) {}));
      } catch (_) {}
      try {
        unawaited(_tts.stop().catchError((_) {}));
      } catch (_) {}
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _handsFreeAutoListen = prefs.getBool(_prefHandsFreeKey) ?? true;
      if (!_disposed) {
        notifyListeners();
      }
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
    final epoch = _sessionEpoch;

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
        if (epoch != _sessionEpoch) {
          // Oturum bu sırada kapandı: eski kullanıcının kapılarını saklama/kullanma.
          return const VoiceDoorResult(
            success: false,
            recognizedText: '',
            feedbackMessage: 'Oturum kapandı.',
          );
        }
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

      final resolution = resolveDoorFromCommand(command, doors);
      if (!resolution.isMatch) {
        // Belirsiz / ters niyetli / anlaşılamayan komutta kapı ASLA açılmaz.
        final message = _messageForUnmatched(resolution);
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
      final matched = resolution.door!;

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

      if (epoch != _sessionEpoch) {
        return const VoiceDoorResult(
          success: false,
          recognizedText: '',
          feedbackMessage: 'Oturum kapandı.',
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

  static String _messageForUnmatched(DoorMatchResult resolution) {
    switch (resolution.status) {
      case DoorMatchStatus.reverseIntent:
        return 'Kapıyı kapatma veya kilitleme komutu desteklenmiyor. Açmak için "kapıyı aç" deyin.';
      case DoorMatchStatus.ambiguous:
        final names = resolution.candidates
            .take(3)
            .map((d) => d.doorName.trim())
            .where((n) => n.isNotEmpty)
            .toList();
        final suffix = names.isEmpty ? '' : ' (${names.join(', ')})';
        return 'Hangi kapıyı açmamı istersiniz?$suffix Örneğin "1. kapıyı aç" veya kapının adını söyleyin.';
      case DoorMatchStatus.notFound:
        return 'Bu isimde bir kapı bulunamadı. Lütfen kapının adını veya numarasını söyleyin.';
      case DoorMatchStatus.noDoors:
        return 'Tanımlı bir kapı bulunamadı.';
      case DoorMatchStatus.noOpenIntent:
      case DoorMatchStatus.matched:
        return 'Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin.';
    }
  }

  /// Doğal Türkçe ses komutunu kapılarla eşleştirir; yalnızca TEK ve net eşleşmede
  /// kapı döndürür (aksi halde null). Ayrıntı için [resolveDoorFromCommand].
  static DoorRecord? matchDoorFromCommand(
    String text,
    List<DoorRecord> availableDoors,
  ) {
    final result = resolveDoorFromCommand(text, availableDoors);
    return result.isMatch ? result.door : null;
  }

  // "aç" fiilinin (normalize edilmiş) kelime-sınırlı biçimleri. Alt dize eşleşmesi
  // YOKTUR: "acil", "bacak", "arac" gibi kelimeler "ac" sayılmaz.
  static const Set<String> _openVerbs = {
    'ac',
    'acin',
    'acsana',
    'acsan',
    'acsaniz',
    'acar',
    'acarmisin',
    'acarmisiniz',
    'acabilir',
    'acabilirmisin',
    'acalim',
  };

  static const Set<String> _reverseWords = {
    'kapa',
    'dur',
    'durdur',
    'iptal',
    'vazgec',
    'vazgectim',
    'hayir',
    'degil',
    'yapma',
    'istemiyorum',
    'istemem',
  };

  static const Set<String> _fillerWords = {
    'lutfen',
    'bana',
    'hemen',
    'simdi',
    'hadi',
    'haydi',
    'ya',
    'misin',
    'misiniz',
  };

  static const Set<String> _stopWords = {
    'kapi',
    'kapisi',
    'kapiyi',
    'kapisini',
    'kapiya',
    'site',
    'sitesi',
    'sitenin',
    'ac',
    'aci',
    'acma',
    'lutfen',
    've',
    'ile',
    'bana',
    'biraz',
  };

  static const Map<String, int> _numberWords = {
    'bir': 1,
    'birinci': 1,
    'iki': 2,
    'ikinci': 2,
    'uc': 3,
    'ucuncu': 3,
    'dort': 4,
    'dorduncu': 4,
    'bes': 5,
    'besinci': 5,
    'alti': 6,
    'altinci': 6,
    'yedi': 7,
    'yedinci': 7,
    'sekiz': 8,
    'sekizinci': 8,
    'dokuz': 9,
    'dokuzuncu': 9,
    'on': 10,
    'onuncu': 10,
  };

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Sesli komutu ayrıntılı çözer. Güvenlik kuralları:
  ///  * Komutta kelime-sınırlı bir "aç" fiili olmalı;
  ///  * "kapat/kilitle/açma/kapatma" gibi ters niyetler REDDEDİLİR;
  ///  * Eşleşme belirsiz ya da birden çok kapıya eşit uyuyorsa AÇILMAZ;
  ///  * "İlk kapı" varsayımı yalnızca kullanıcının TEK kapısı varsa geçerlidir.
  static DoorMatchResult resolveDoorFromCommand(
    String text,
    List<DoorRecord> availableDoors,
  ) {
    if (availableDoors.isEmpty) {
      return const DoorMatchResult(DoorMatchStatus.noDoors);
    }

    final normalized = _normalizeTurkish(text);
    if (normalized.isEmpty) {
      return const DoorMatchResult(DoorMatchStatus.noOpenIntent);
    }
    final tokens =
        normalized.split(_whitespace).where((t) => t.isNotEmpty).toList();

    // 1. Ters niyet / olumsuzlama
    for (final token in tokens) {
      if (token.startsWith('kapat') ||
          token.startsWith('kilit') ||
          token.startsWith('kapama') ||
          token.startsWith('acma') || // açma, açmayın, açmasın, açmak...
          _reverseWords.contains(token)) {
        return const DoorMatchResult(DoorMatchStatus.reverseIntent);
      }
    }

    // 2. "aç" fiili şart
    if (!tokens.any(_openVerbs.contains)) {
      return const DoorMatchResult(DoorMatchStatus.noOpenIntent);
    }

    // 3. Kapılara puan ver
    final extractedNumber = _extractDoorNumber(tokens);

    final scores = List<int>.filled(availableDoors.length, 0);
    for (int index = 0; index < availableDoors.length; index++) {
      final door = availableDoors[index];
      int score = 0;
      final doorNorm = _normalizeTurkish(door.doorName);
      final doorTokens =
          doorNorm.split(_whitespace).where((t) => t.isNotEmpty).toList();

      // 3a. Kapı index / sayı eşleşmesi
      if (extractedNumber != null) {
        if (door.doorIndex == extractedNumber) {
          score += 20;
        } else if (doorTokens.contains('$extractedNumber')) {
          score += 15;
        }
      }

      // 3b. Tam kapı adı (kelime sınırlı; son kelime ek alabilir: "ön kapıyı")
      if (doorTokens.isNotEmpty && _containsPhrase(tokens, doorTokens)) {
        score += 30;
      }

      // 3c. Özgül kelime eşleşmesi (stop words hariç)
      for (final word in doorTokens) {
        if (_isSpecificWord(word) && _commandHasWord(tokens, word)) {
          score += 10;
        }
      }

      // 3d. Site adı (çok-siteli kullanıcıda aynı adlı kapıları ayırmak için)
      final siteNorm = _normalizeTurkish(door.siteName ?? '');
      for (final word in siteNorm.split(_whitespace)) {
        if (_isSpecificWord(word) && _commandHasWord(tokens, word)) {
          score += 5;
        }
      }

      scores[index] = score;
    }

    int highest = 0;
    for (final score in scores) {
      if (score > highest) highest = score;
    }

    if (highest > 0) {
      final top = <DoorRecord>[
        for (int i = 0; i < availableDoors.length; i++)
          if (scores[i] == highest) availableDoors[i],
      ];
      if (top.length == 1) {
        return DoorMatchResult(DoorMatchStatus.matched, door: top.first);
      }
      // Eşit puan: hangisi olduğu belirsiz -> AÇMA, sor.
      return DoorMatchResult(DoorMatchStatus.ambiguous, candidates: top);
    }

    // 4. Hiçbir kapı adı/numarası söylenmedi. Genel "kapıyı aç" ya da yalnız "aç".
    final mentionsDoorNoun = tokens.any(_isDoorNoun);
    final onlyVerb = tokens.every(
      (t) => _openVerbs.contains(t) || _fillerWords.contains(t),
    );

    if (mentionsDoorNoun || onlyVerb) {
      if (availableDoors.length == 1) {
        // Son çare "ilk kapı" YALNIZCA tek kapı varsa.
        return DoorMatchResult(
          DoorMatchStatus.matched,
          door: availableDoors.first,
        );
      }
      return DoorMatchResult(
        DoorMatchStatus.ambiguous,
        candidates: List<DoorRecord>.of(availableDoors),
      );
    }

    // Kapıyla ilgisiz bir şey açılmak isteniyor ("pencereyi aç").
    return const DoorMatchResult(DoorMatchStatus.notFound);
  }

  static bool _isDoorNoun(String token) {
    return token.startsWith('kapi') ||
        token == 'bariyer' ||
        token == 'bariyeri' ||
        token == 'giris' ||
        token == 'girisi' ||
        token == 'cikis' ||
        token == 'cikisi' ||
        token == 'garaj' ||
        token == 'garaji' ||
        token == 'otopark' ||
        token == 'otoparki';
  }

  /// [phrase] kelimeleri [tokens] içinde ardışık geçiyor mu? Son kelime (en çok
  /// 5 harflik) ek alabilir: "garaj kapısı" ~ "garaj kapısını".
  static bool _containsPhrase(List<String> tokens, List<String> phrase) {
    if (phrase.isEmpty || tokens.length < phrase.length) return false;
    for (int start = 0; start + phrase.length <= tokens.length; start++) {
      var matches = true;
      for (int i = 0; i < phrase.length; i++) {
        final token = tokens[start + i];
        final word = phrase[i];
        final isLast = i == phrase.length - 1;
        final ok = token == word ||
            (isLast &&
                int.tryParse(word) == null && // sayılar ek almaz ("1" != "10")
                word.length >= 2 &&
                token.startsWith(word) &&
                token.length - word.length <= 5);
        if (!ok) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  static bool _isSpecificWord(String word) {
    return word.length >= 3 && !_stopWords.contains(word);
  }

  /// Komut kelimelerinden biri [word] ya da onun ekli (en çok 5 harf) biçimi mi?
  static bool _commandHasWord(List<String> tokens, String word) {
    for (final token in tokens) {
      if (token == word) return true;
      if (token.startsWith(word) && token.length - word.length <= 5) {
        return true;
      }
    }
    return false;
  }

  static String _normalizeTurkish(String text) {
    return text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('̇', '')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('û', 'u')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  /// Komuttaki kapı numarasını bulur. Rakamlar her zaman sayıdır; yazıyla
  /// sayılar ("bir", "iki"...) yalnızca bağlamdan kapı numarası olduğu belliyse
  /// (kapı kelimesinden sonra / "numaralı" öncesi / ek ayrılması) sayılır; böylece
  /// "bir kapı aç" ya da "ön kapı" ("on kapi") yanlışlıkla 1/10 sayılmaz.
  static int? _extractDoorNumber(List<String> tokens) {
    const suffixSplits = {'i', 'e', 'a', 'u', 'yi', 'ye', 'ya', 'nin', 'in', 'un'};
    final digitsOnly = RegExp(r'^\d{1,4}$');

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (digitsOnly.hasMatch(token)) {
        return int.tryParse(token);
      }
      final value = _numberWords[token];
      if (value == null) continue;

      if (token.endsWith('inci') ||
          token.endsWith('ncu') ||
          token == 'dorduncu' ||
          token == 'ucuncu') {
        return value; // sıra sayıları ("birinci", "ikinci") açıkça kapı numarasıdır
      }

      final prev = i > 0 ? tokens[i - 1] : '';
      final next = i + 1 < tokens.length ? tokens[i + 1] : '';
      final afterDoorNoun = prev.startsWith('kapi');
      final beforeNumara = next.startsWith('numara') || next == 'no';
      final beforeSuffix = suffixSplits.contains(next) && !_isDoorNoun(prev);
      if (afterDoorNoun || beforeNumara || beforeSuffix) {
        return value;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      unawaited(_speech.stop().catchError((_) {}));
    } catch (_) {}
    try {
      unawaited(_tts.stop().catchError((_) {}));
    } catch (_) {}
    super.dispose();
  }
}
