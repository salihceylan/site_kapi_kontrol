import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Ağır CPU işlerini (büyük JSON çözümleme, PDF üretimi) UI izolesinden ayırır.
///
/// Üretimde [compute] (Isolate.run) kullanılır; web'de Flutter işi aynı izolede çalıştırır.
/// Giriş işlevi üst düzey/statik olmalı ve ileti yalnızca isolate'a gönderilebilir veri
/// (düz sınıflar, liste/harita, String, num, DateTime, Uint8List) içermelidir.
class BackgroundWork {
  BackgroundWork._();

  /// Bu boyuttan (bayt) küçük JSON gövdeleri UI izolesinde çözülür: isolate başlatma ve ileti
  /// kopyalama maliyeti küçük gövdelerin çözüm süresinden büyüktür.
  static const int jsonIsolateThresholdBytes = 64 * 1024;

  /// Test düzeneği: toplam arka plan işi sayısı (isolate'a gönderilen iş).
  @visibleForTesting
  static int debugRunCount = 0;

  /// Test düzeneği: true iken iş aynı izolede çalışır (FakeAsync altındaki widget testleri,
  /// gerçek isolate beklemez).
  @visibleForTesting
  static bool debugRunInline = false;

  /// [callback]'i [message] ile arka plan izolesinde çalıştırır; sonuç/hata çağırana döner.
  static Future<R> run<M, R>(
    ComputeCallback<M, R> callback,
    M message, {
    String? debugLabel,
  }) {
    debugRunCount++;
    if (debugRunInline) {
      return Future<R>.sync(() => callback(message));
    }
    return compute<M, R>(callback, message, debugLabel: debugLabel);
  }
}

/// [BackgroundWork.run] giriş işlevi: JSON metnini çözer (üst düzey: isolate'a gönderilebilir).
Object? decodeJsonText(String body) => jsonDecode(body);

/// [BackgroundWork.run] giriş işlevi: UTF-8 JSON baytlarını çözer. Bayt -> metin çevrimi de arka
/// planda yapılır (4 MB'lık yanıtta ana izolede ~15-25 ms'lik ek bir maliyetti).
Object? decodeJsonUtf8Bytes(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
