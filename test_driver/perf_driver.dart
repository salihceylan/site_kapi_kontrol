// ignore_for_file: avoid_print
//
// FAZ 5 / P: `flutter drive` sürücüsü. integration_test/perf_frames_test.dart'ın `reportData`
// ile döndürdüğü kare süresi özetini JSON dosyasına yazar ve kısa bir tablo basar.
//
//   flutter drive --profile -d windows \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_frames_test.dart ...
//
// Çıktı dizini: PERF_OUT ortam değişkeni (yoksa build/perf). Dosya: perf_frames.json.

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    timeout: const Duration(minutes: 20),
    // Gezinti kısmen başarısız olsa bile toplanan kare süreleri yine yazılsın.
    writeResponseOnFailure: true,
    responseDataCallback: (Map<String, dynamic>? data) async {
      final summary = data?['perf_frames'];
      if (summary == null) {
        print('PERF~ sürücü: perf_frames verisi gelmedi (test hata verdi mi?).');
        return;
      }
      final out = Platform.environment['PERF_OUT'] ?? 'build${Platform.pathSeparator}perf';
      final dir = Directory(out)..createSync(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}perf_frames.json');
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
      print('PERF> sürücü yazdı: ${file.path}');

      final phases = (summary as Map<String, dynamic>)['phases'] as Map<String, dynamic>? ?? const {};
      print('aşama                      kare   build p50/p90/p99 (ms)   raster p50/p90/p99 (ms)   jank');
      phases.forEach((name, value) {
        final p = value as Map<String, dynamic>;
        final b = p['build_ms'] as Map<String, dynamic>;
        final r = p['raster_ms'] as Map<String, dynamic>;
        final j = p['jank'] as Map<String, dynamic>;
        String three(Map<String, dynamic> m) => '${m['p50']}/${m['p90']}/${m['p99']}';
        print(
          '${name.padRight(26)} ${'${p['frames']}'.padLeft(5)}   '
          '${three(b).padRight(24)} ${three(r).padRight(25)} ${((j['ratio'] as num) * 100).toStringAsFixed(1)}%',
        );
      });
    },
  );
}
