import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Tek bir karede tespit edilen ve doğrulanan Türk plakası sonucu.
class PlateDetectionResult {
  const PlateDetectionResult({
    required this.plate,
    required this.canonicalPlate,
    required this.confidence,
    required this.normalizedBox,
    required this.sourceAspectRatio,
  });

  /// Biçimlendirilmiş plaka (örn. `34 NBL 304`).
  final String plate;

  /// Boşluksuz kanonik plaka (örn. `34NBL304`).
  final String canonicalPlate;

  /// Birleşik tespit + OCR güven skoru (`0.0 .. 1.0`).
  final double confidence;

  /// Kaynak kare içindeki normalize sınırlayıcı kutu (`0.0 .. 1.0`).
  final Rect normalizedBox;

  /// Kaynak karenin en/boy oranı (`width / height`, tipik olarak `16 / 9`).
  final double sourceAspectRatio;
}

/// Uygulama içi (native C++ ONNX Runtime) gerçek zamanlı plaka tespit ve okuma servisi.
///
/// - **Aşama 1 (Tespit):** `plate_detector_yolov9t_384.onnx` (`[1, 3, 384, 384]` float32 NCHW)
/// - **Aşama 2 (OCR):** `plate_ocr_cct_s_v2.onnx` (`[1, 64, 128, 3]` uint8 NHWC RGB)
/// - Tüm JPEG çözme, yeniden boyutlandırma, kırpma ve eğik plaka düzeltme işlemleri kalıcı bir arka plan
///   `Isolate` içinde yürütülür; 30/60 FPS GPU RTSP video akışını asla yavaşlatmaz.
class PlateOnnxRecognizer {
  PlateOnnxRecognizer._();
  static final PlateOnnxRecognizer instance = PlateOnnxRecognizer._();

  static const String _detectorAsset = 'assets/models/plate_detector_yolov9t_384.onnx';
  static const String _ocrAsset = 'assets/models/plate_ocr_cct_s_v2.onnx';

  @visibleForTesting
  static const String ocrAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_';

  static const int _detInputSize = 384;
  static const int _ocrWidth = 128;
  static const int _ocrHeight = 64;
  static const int _ocrMaxSlots = 10;
  static const int _ocrVocabSize = 37;

  OrtSession? _detSession;
  OrtSession? _ocrSession;
  Future<bool>? _initFuture;
  bool _permanentlyDisabled = false;
  bool _detectBusy = false;

  _PlateImageWorker? _worker;

  static bool get isSupported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isAndroid ||
        Platform.isIOS;
  }

  /// Modelleri ve arka plan piksel işleme izolatını hazırlar.
  Future<bool> ensureInitialized() {
    if (!isSupported || _permanentlyDisabled) return Future<bool>.value(false);
    if (_detSession != null && _ocrSession != null && _worker != null) {
      return Future<bool>.value(true);
    }
    return _initFuture ??= _doInitialize();
  }

  Future<bool> _doInitialize() async {
    try {
      final ort = OnnxRuntime();
      final options = OrtSessionOptions(
        intraOpNumThreads: 2,
        interOpNumThreads: 1,
        useArena: true,
      );
      _detSession ??= await ort.createSessionFromAsset(_detectorAsset, options: options);
      _ocrSession ??= await ort.createSessionFromAsset(_ocrAsset, options: options);
      _worker ??= await _PlateImageWorker.spawn();
      debugPrint('[PlateOnnxRecognizer] Yerel ONNX plaka tespit ve OCR modelleri hazır.');
      return true;
    } catch (e) {
      debugPrint('[PlateOnnxRecognizer] ONNX başlatma hatası: $e');
      _initFuture = null;
      // Platform kanalının hiç bulunmadığı ortamlarda sürekli tekrar denemeyi önle
      if (e.toString().contains('MissingPluginException')) {
        _permanentlyDisabled = true;
      }
      return false;
    }
  }

  /// Verilen JPEG karesi içinde plaka arar; geçerli bir Türk plakası bulursa kutu ve metni döndürür.
  Future<PlateDetectionResult?> detect(Uint8List jpegBytes) async {
    if (_detectBusy || jpegBytes.length < 512) return null;
    final ready = await ensureInitialized();
    if (!ready) return null;

    final detSession = _detSession;
    final ocrSession = _ocrSession;
    final worker = _worker;
    if (detSession == null || ocrSession == null || worker == null) return null;

    _detectBusy = true;
    try {
      final prep = await worker.prepareDetectorInput(jpegBytes);
      if (prep == null) return null;

      final imgW = prep.width;
      final imgH = prep.height;
      if (imgW <= 0 || imgH <= 0) return null;

      final boxes = await _runDetector(detSession, prep.nchwFloat32, imgW, imgH);
      if (boxes.isEmpty) return null;

      PlateDetectionResult? bestResult;
      double bestScore = -1.0;

      // En yüksek güvenli ilk 3 plaka adayını incele
      final limit = math.min(boxes.length, 3);
      for (var i = 0; i < limit; i++) {
        final box = boxes[i];
        final bw = box.x2 - box.x1;
        final bh = box.y2 - box.y1;
        final isTiltedCandidate = bw > 0 && (bh / bw) > 0.36;

        // Önce standart kırpma; başarısızsa genişletilmiş ve eğim düzeltmeli (deskew) adaylar
        final attempts = <(double pad, double angle)>[
          (0.06, 0.0),
          (0.15, 0.0),
          if (isTiltedCandidate) (0.10, 24.0),
          if (isTiltedCandidate) (0.10, -24.0),
        ];

        for (final (padRatio, angleDeg) in attempts) {
          final cropRgb = await worker.cropForOcr(
            x1: box.x1,
            y1: box.y1,
            x2: box.x2,
            y2: box.y2,
            padRatio: padRatio,
            angleDeg: angleDeg,
          );
          if (cropRgb == null || cropRgb.length != _ocrWidth * _ocrHeight * 3) {
            continue;
          }

          final (rawPlate, ocrProb) = await _runOcr(ocrSession, cropRgb);
          if (rawPlate.isEmpty) continue;

          final formatted = formatTrPlate(rawPlate);
          if (formatted == null) continue;

          final combinedConf = ((box.confidence * 0.45) + (ocrProb * 0.55)).clamp(0.0, 1.0);
          final canonical = formatted.replaceAll(' ', '');
          final normRect = Rect.fromLTRB(
            (box.x1 / imgW).clamp(0.0, 1.0),
            (box.y1 / imgH).clamp(0.0, 1.0),
            (box.x2 / imgW).clamp(0.0, 1.0),
            (box.y2 / imgH).clamp(0.0, 1.0),
          );

          final candidate = PlateDetectionResult(
            plate: formatted,
            canonicalPlate: canonical,
            confidence: combinedConf,
            normalizedBox: normRect,
            sourceAspectRatio: imgW / imgH,
          );

          // İlk denemede yüksek güvenle geçerli Türk plakası okunduysa anında dön
          if (ocrProb >= 0.72 && angleDeg == 0.0) {
            return candidate;
          }

          if (combinedConf > bestScore) {
            bestScore = combinedConf;
            bestResult = candidate;
          }
          // Bu kutu için geçerli plaka bulundu, aynı kutuda diğer açıları denemeye gerek yok
          break;
        }
      }

      return bestResult;
    } catch (e) {
      debugPrint('[PlateOnnxRecognizer] Kare analiz hatası: $e');
      return null;
    } finally {
      try {
        await worker.clearActiveFrame();
      } catch (_) {}
      _detectBusy = false;
    }
  }

  Future<List<PlateRawBox>> _runDetector(
    OrtSession session,
    Float32List nchwData,
    int origW,
    int origH,
  ) async {
    OrtValue? inputTensor;
    Map<String, OrtValue>? outputs;
    try {
      inputTensor = await OrtValue.fromList(
        nchwData,
        const <int>[1, 3, _detInputSize, _detInputSize],
      );
      final inputName = session.inputNames.isNotEmpty ? session.inputNames.first : 'images';
      outputs = await session.run(<String, OrtValue>{inputName: inputTensor});
      if (outputs.isEmpty) return const <PlateRawBox>[];

      final outTensor = outputs[session.outputNames.firstOrNull ?? 'output0'] ?? outputs.values.first;
      final flat = await outTensor.asFlattenedList();
      return parseYoloOutput(flat, origW: origW, origH: origH);
    } finally {
      if (outputs != null) {
        for (final v in outputs.values) {
          try {
            await v.dispose();
          } catch (_) {}
        }
      }
      if (inputTensor != null) {
        try {
          await inputTensor.dispose();
        } catch (_) {}
      }
    }
  }

  Future<(String, double)> _runOcr(OrtSession session, Uint8List nhwcRgb) async {
    OrtValue? inputTensor;
    Map<String, OrtValue>? outputs;
    try {
      inputTensor = await OrtValue.fromList(
        nhwcRgb,
        const <int>[1, _ocrHeight, _ocrWidth, 3],
      );
      final inputName = session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
      outputs = await session.run(<String, OrtValue>{inputName: inputTensor});
      if (outputs.isEmpty) return ('', 0.0);

      final outTensor = outputs[session.outputNames.firstOrNull ?? 'plate'] ?? outputs.values.first;
      final flat = await outTensor.asFlattenedList();
      return decodeOcrLogits(flat);
    } finally {
      if (outputs != null) {
        for (final v in outputs.values) {
          try {
            await v.dispose();
          } catch (_) {}
        }
      }
      if (inputTensor != null) {
        try {
          await inputTensor.dispose();
        } catch (_) {}
      }
    }
  }

  /// YOLOv9t NMS-sonrası `[N, 7]` düz çıktısını ayrıştırır ve güven skoruna göre sıralar.
  @visibleForTesting
  static List<PlateRawBox> parseYoloOutput(
    List<dynamic> flat, {
    required int origW,
    required int origH,
    double minConfidence = 0.14,
  }) {
    if (flat.length < 7 || origW <= 0 || origH <= 0) return const <PlateRawBox>[];
    final scaleX = origW / _detInputSize;
    final scaleY = origH / _detInputSize;
    final rowCount = flat.length ~/ 7;
    final results = <PlateRawBox>[];

    for (var i = 0; i < rowCount; i++) {
      final base = i * 7;
      final conf = (flat[base + 6] as num).toDouble();
      if (conf < minConfidence) continue;

      final rx1 = (flat[base + 1] as num).toDouble() * scaleX;
      final ry1 = (flat[base + 2] as num).toDouble() * scaleY;
      final rx2 = (flat[base + 3] as num).toDouble() * scaleX;
      final ry2 = (flat[base + 4] as num).toDouble() * scaleY;

      final x1 = rx1.clamp(0.0, origW.toDouble());
      final y1 = ry1.clamp(0.0, origH.toDouble());
      final x2 = rx2.clamp(0.0, origW.toDouble());
      final y2 = ry2.clamp(0.0, origH.toDouble());

      if ((x2 - x1) < 16.0 || (y2 - y1) < 7.0) continue;
      results.add(PlateRawBox(x1: x1, y1: y1, x2: x2, y2: y2, confidence: conf));
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results;
  }

  /// CCT-S `[1, 10, 37]` logit çıktısını karakter dizisine ve ortalama olasılığa çözümler.
  @visibleForTesting
  static (String, double) decodeOcrLogits(List<dynamic> flat) {
    if (flat.length < _ocrMaxSlots * _ocrVocabSize) return ('', 0.0);

    final sb = StringBuffer();
    double probSum = 0.0;
    int charCount = 0;

    for (var slot = 0; slot < _ocrMaxSlots; slot++) {
      final offset = slot * _ocrVocabSize;
      var bestIdx = 0;
      var maxLogit = (flat[offset] as num).toDouble();
      for (var c = 1; c < _ocrVocabSize; c++) {
        final v = (flat[offset + c] as num).toDouble();
        if (v > maxLogit) {
          maxLogit = v;
          bestIdx = c;
        }
      }

      // Softmax olasılığı (sayısal kararlı)
      var expSum = 0.0;
      for (var c = 0; c < _ocrVocabSize; c++) {
        expSum += math.exp((flat[offset + c] as num).toDouble() - maxLogit);
      }
      final prob = expSum > 0 ? (1.0 / expSum) : 0.0;

      final ch = ocrAlphabet[bestIdx];
      if (ch != '_') {
        sb.write(ch);
        probSum += prob;
        charCount++;
      }
    }

    if (charCount == 0) return ('', 0.0);
    return (sb.toString(), probSum / charCount);
  }

  /// Ham OCR çıktısını Türk plaka standardına (`01..81` + `1..3 harf` + `2..5 rakam`) göre doğrular,
  /// yaygın OCR karakter karışıklıklarını (`0<->O`, `1<->I`, `8<->B`, `5<->S`, `2<->Z`, `6<->G`)
  /// en az düzeltme maliyetiyle giderir ve `34 NBL 304` biçiminde döndürür.
  static String? formatTrPlate(String raw) {
    final trMap = <String, String>{
      'Ç': 'C',
      'Ğ': 'G',
      'İ': 'I',
      'Ö': 'O',
      'Ş': 'S',
      'Ü': 'U',
    };
    var clean = raw.toUpperCase();
    trMap.forEach((k, v) => clean = clean.replaceAll(k, v));
    clean = clean.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length < 6) return null;

    String? bestFormatted;
    int bestCost = 999;

    // Sol mavi "TR" şeridinden sızabilecek 1-2 karakteri de tolere etmek için pencere taraması
    final maxTrim = math.min(2, clean.length - 6);
    for (var start = 0; start <= maxTrim; start++) {
      final maxLen = math.min(8, clean.length - start);
      for (var len = maxLen; len >= 6; len--) {
        final sub = clean.substring(start, start + len);
        final trimPenalty = start + (clean.length - start - len);
        final match = _matchTrCandidate(sub);
        if (match == null) continue;
        final (formatted, subsCost) = match;
        final totalCost = subsCost * 2 + trimPenalty * 3;
        if (totalCost < bestCost) {
          bestCost = totalCost;
          bestFormatted = formatted;
          if (totalCost == 0) return bestFormatted;
        }
      }
    }

    return bestFormatted;
  }

  static (String, int)? _matchTrCandidate(String s) {
    if (s.length < 6 || s.length > 8) return null;

    final c0 = _asDigit(s[0]);
    final c1 = _asDigit(s[1]);
    if (c0 == null || c1 == null) return null;

    final cityStr = '${c0.$1}${c1.$1}';
    final cityCode = int.tryParse(cityStr);
    if (cityCode == null || cityCode < 1 || cityCode > 81) return null;
    final citySubs = c0.$2 + c1.$2;

    final rem = s.substring(2); // uzunluk 4..6
    (String, int)? best;

    // Türkiye'de 3 ve 2 harfli plakalar en yaygın seri olduğu için eşit düzeltme sayısında önceliklidir
    for (final letterLen in const <int>[3, 2, 1]) {
      final digitLen = rem.length - letterLen;
      if (digitLen < 2 || digitLen > 5) continue;
      if (letterLen + digitLen > 6) continue;
      // 1 harfli plakalarda en az 3-4 rakam, 3 harfli plakalarda 2-3 rakam kuralı
      if (letterLen == 1 && digitLen < 3) continue;
      if (letterLen == 3 && digitLen > 3) continue;

      var subs = citySubs;
      final lettersBuf = StringBuffer();
      var valid = true;

      for (var i = 0; i < letterLen; i++) {
        final conv = _asLetter(rem[i]);
        if (conv == null) {
          valid = false;
          break;
        }
        lettersBuf.write(conv.$1);
        subs += conv.$2;
      }
      if (!valid) continue;

      final digitsBuf = StringBuffer();
      for (var i = letterLen; i < rem.length; i++) {
        final conv = _asDigit(rem[i]);
        if (conv == null) {
          valid = false;
          break;
        }
        digitsBuf.write(conv.$1);
        subs += conv.$2;
      }
      if (!valid || subs > 2) continue;

      final formatted = '$cityStr ${lettersBuf.toString()} ${digitsBuf.toString()}';
      if (best == null || subs < best.$2) {
        best = (formatted, subs);
        if (subs == 0) return best;
      }
    }

    return best;
  }

  static (String, int)? _asDigit(String ch) {
    final code = ch.codeUnitAt(0);
    if (code >= 48 && code <= 57) return (ch, 0);
    return switch (ch) {
      'O' || 'Q' || 'D' => ('0', 1),
      'I' || 'L' => ('1', 1),
      'Z' => ('2', 1),
      'S' => ('5', 1),
      'G' => ('6', 1),
      'B' => ('8', 1),
      _ => null,
    };
  }

  static (String, int)? _asLetter(String ch) {
    final code = ch.codeUnitAt(0);
    if (code >= 65 && code <= 90) return (ch, 0);
    return switch (ch) {
      '0' => ('O', 1),
      '1' => ('I', 1),
      '2' => ('Z', 1),
      '5' => ('S', 1),
      '6' => ('G', 1),
      '8' => ('B', 1),
      _ => null,
    };
  }
}

class PlateRawBox {
  const PlateRawBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
}

class _DetectorPrepOutput {
  const _DetectorPrepOutput({
    required this.width,
    required this.height,
    required this.nchwFloat32,
  });

  final int width;
  final int height;
  final Float32List nchwFloat32;
}

/// Ana UI izolatını hiçbir piksel döngüsüyle meşgul etmeyen kalıcı arka plan görüntü işçisi.
class _PlateImageWorker {
  _PlateImageWorker._(this._isolate, this._sendPort, this._receivePort) {
    _receivePort.listen(_onMessage);
  }

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final Map<int, Completer<List<dynamic>?>> _pending = <int, Completer<List<dynamic>?>>{};
  int _nextId = 1;

  static Future<_PlateImageWorker> spawn() async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn<_WorkerBootstrap>(
      _workerEntryPoint,
      _WorkerBootstrap(readyPort.sendPort),
      debugName: 'PlateOnnxImageWorker',
    );
    final sendPort = await readyPort.first as SendPort;
    readyPort.close();
    final replyPort = ReceivePort();
    sendPort.send(replyPort.sendPort);
    return _PlateImageWorker._(isolate, sendPort, replyPort);
  }

  void _onMessage(dynamic raw) {
    if (raw is! List || raw.isEmpty) return;
    final id = raw[0] as int;
    final completer = _pending.remove(id);
    completer?.complete(raw);
  }

  Future<_DetectorPrepOutput?> prepareDetectorInput(Uint8List jpegBytes) async {
    final id = _nextId++;
    final completer = Completer<List<dynamic>?>();
    _pending[id] = completer;
    _sendPort.send(<dynamic>[
      id,
      0,
      TransferableTypedData.fromList(<Uint8List>[jpegBytes]),
    ]);
    final res = await completer.future;
    if (res == null || res.length < 4 || res[1] == null) return null;
    final w = res[1] as int;
    final h = res[2] as int;
    final rawBytes = (res[3] as TransferableTypedData).materialize().asUint8List();
    final floatView = rawBytes.buffer.asFloat32List(
      rawBytes.offsetInBytes,
      rawBytes.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    return _DetectorPrepOutput(width: w, height: h, nchwFloat32: floatView);
  }

  Future<Uint8List?> cropForOcr({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double padRatio,
    required double angleDeg,
  }) async {
    final id = _nextId++;
    final completer = Completer<List<dynamic>?>();
    _pending[id] = completer;
    _sendPort.send(<dynamic>[id, 1, x1, y1, x2, y2, padRatio, angleDeg]);
    final res = await completer.future;
    if (res == null || res.length < 2 || res[1] == null) return null;
    return (res[1] as TransferableTypedData).materialize().asUint8List();
  }

  Future<void> clearActiveFrame() async {
    final id = _nextId++;
    final completer = Completer<List<dynamic>?>();
    _pending[id] = completer;
    _sendPort.send(<dynamic>[id, 2]);
    await completer.future;
  }

  void dispose() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _WorkerBootstrap {
  const _WorkerBootstrap(this.handshakePort);
  final SendPort handshakePort;
}

void _workerEntryPoint(_WorkerBootstrap boot) {
  final commandPort = ReceivePort();
  boot.handshakePort.send(commandPort.sendPort);

  SendPort? replyPort;
  img.Image? activeImage;
  const int detSize = 384;
  const int planeSize = detSize * detSize;
  const double inv255 = 1.0 / 255.0;

  commandPort.listen((dynamic message) {
    if (message is SendPort) {
      replyPort = message;
      return;
    }
    final out = replyPort;
    if (out == null || message is! List || message.length < 2) return;

    final reqId = message[0] as int;
    final cmd = message[1] as int;

    try {
      if (cmd == 0) {
        final jpegBytes = (message[2] as TransferableTypedData).materialize().asUint8List();
        final decoded = img.decodeJpg(jpegBytes) ?? img.decodeImage(jpegBytes);
        if (decoded == null || decoded.width < 32 || decoded.height < 32) {
          activeImage = null;
          out.send(<dynamic>[reqId, null]);
          return;
        }
        activeImage = decoded;

        final resized = img.copyResize(
          decoded,
          width: detSize,
          height: detSize,
          interpolation: img.Interpolation.linear,
        );
        final rgb = resized.getBytes(order: img.ChannelOrder.rgb);
        final floatBuf = Float32List(3 * planeSize);
        var srcIdx = 0;
        for (var i = 0; i < planeSize; i++) {
          floatBuf[i] = rgb[srcIdx] * inv255;
          floatBuf[planeSize + i] = rgb[srcIdx + 1] * inv255;
          floatBuf[planeSize * 2 + i] = rgb[srcIdx + 2] * inv255;
          srcIdx += 3;
        }

        out.send(<dynamic>[
          reqId,
          decoded.width,
          decoded.height,
          TransferableTypedData.fromList(<Uint8List>[floatBuf.buffer.asUint8List()]),
        ]);
      } else if (cmd == 1) {
        final src = activeImage;
        if (src == null) {
          out.send(<dynamic>[reqId, null]);
          return;
        }
        final x1 = (message[2] as num).toDouble();
        final y1 = (message[3] as num).toDouble();
        final x2 = (message[4] as num).toDouble();
        final y2 = (message[5] as num).toDouble();
        final padRatio = (message[6] as num).toDouble();
        final angleDeg = (message[7] as num).toDouble();

        final bw = x2 - x1;
        final bh = y2 - y1;
        if (bw < 8 || bh < 4) {
          out.send(<dynamic>[reqId, null]);
          return;
        }

        img.Image cropped;
        if (angleDeg.abs() < 0.5) {
          final padX = bw * padRatio;
          final padY = bh * (padRatio * 1.15);
          final cx1 = (x1 - padX).floor().clamp(0, src.width - 2);
          final cy1 = (y1 - padY).floor().clamp(0, src.height - 2);
          final cx2 = (x2 + padX).ceil().clamp(cx1 + 2, src.width);
          final cy2 = (y2 + padY).ceil().clamp(cy1 + 2, src.height);
          cropped = img.copyCrop(src, x: cx1, y: cy1, width: cx2 - cx1, height: cy2 - cy1);
        } else {
          final cx = (x1 + x2) * 0.5;
          final cy = (y1 + y2) * 0.5;
          final diag = math.sqrt(bw * bw + bh * bh);
          final half = (diag * 0.65).ceil();
          final px1 = (cx - half).floor().clamp(0, src.width - 2);
          final py1 = (cy - half).floor().clamp(0, src.height - 2);
          final px2 = (cx + half).ceil().clamp(px1 + 2, src.width);
          final py2 = (cy + half).ceil().clamp(py1 + 2, src.height);
          final patch = img.copyCrop(src, x: px1, y: py1, width: px2 - px1, height: py2 - py1);
          final rotated = img.copyRotate(
            patch,
            angle: angleDeg,
            interpolation: img.Interpolation.linear,
          );
          final bandW = (diag * (1.0 + padRatio)).round().clamp(4, rotated.width);
          final bandH = (diag * 0.34).round().clamp(4, rotated.height);
          final bx = ((rotated.width - bandW) ~/ 2).clamp(0, rotated.width - bandW);
          final by = ((rotated.height - bandH) ~/ 2).clamp(0, rotated.height - bandH);
          cropped = img.copyCrop(rotated, x: bx, y: by, width: bandW, height: bandH);
        }

        final resizedCrop = img.copyResize(
          cropped,
          width: 128,
          height: 64,
          interpolation: img.Interpolation.linear,
        );
        final rgbBytes = Uint8List.fromList(resizedCrop.getBytes(order: img.ChannelOrder.rgb));
        out.send(<dynamic>[
          reqId,
          TransferableTypedData.fromList(<Uint8List>[rgbBytes]),
        ]);
      } else if (cmd == 2) {
        activeImage = null;
        out.send(<dynamic>[reqId, true]);
      } else {
        out.send(<dynamic>[reqId, null]);
      }
    } catch (_) {
      activeImage = null;
      out.send(<dynamic>[reqId, null]);
    }
  });
}
