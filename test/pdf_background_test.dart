// FAZ 5 / P-a: PDF raporlarının arka plan izolesinde üretilmesi.
//
// Ağ gerektirmez: yazı tipleri [PdfFontSet] ile verilir (Helvetica yedeği ya da Flutter SDK'sındaki
// Roboto TTF dosyaları). Ölçüm satırları gerçek sayılarla test çıktısına yazdırılır.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';
import 'package:site_kapi_kontrol/services/pdf_credentials_service.dart';
import 'package:site_kapi_kontrol/services/pdf_device_firmware_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';
import 'package:site_kapi_kontrol/services/pdf_logs_service.dart';

List<DoorAccessLogRecord> _logs(int n) => <DoorAccessLogRecord>[
      for (var i = 0; i < n; i++)
        DoorAccessLogRecord(
          id: i,
          siteCode: 1,
          doorName: 'Ana Kapı',
          userName: 'Kullanıcı ${i % 50}',
          userRole: 'apartment_owner',
          apartmentLabel: 'A / ${i % 40}',
          triggerType: i % 3 == 0 ? 'cloud_app' : (i % 3 == 1 ? 'guest_pass' : 'voice'),
          openedAt: DateTime(2026, 5, 1).add(Duration(minutes: i)),
        ),
    ];

SiteStructureRecord _structure(int siteId, int apartments) => SiteStructureRecord.fromJson({
      'site': {'id': siteId, 'name': 'Güneş Sitesi $siteId', 'city': 'Ankara', 'district': 'Çankaya'},
      'blocks': [
        {'id': 1, 'site_code': siteId, 'block_name': 'A Blok'},
      ],
      'apartments': [
        for (var i = 0; i < apartments; i++)
          {
            'id': siteId * 1000 + i,
            'site_code': siteId,
            'block_id': 1,
            'block_name': 'A Blok',
            'unit_label': 'Daire ${i + 1}',
            'resident_full_name': 'Şükrü Öğretmen $i',
            'resident_login_name': 'sakin$i',
            'resident_pin_code': '${1000 + i}',
            'resident_is_active': i.isEven,
          },
      ],
      'doors': <dynamic>[],
    });

List<DeviceRecord> _devices(int n) => <DeviceRecord>[
      for (var i = 0; i < n; i++)
        DeviceRecord.fromJson({
          'id': i + 1,
          'device_uid': 'AABBCC${i.toString().padLeft(6, '0')}',
          'hardware_target': i.isEven ? 'esp32-c3' : 'esp32-wroom',
          'firmware_version': i % 4 == 0 ? '4.2.0' : '4.1.0',
          'mqtt_connected': i % 3 != 0,
          'site_name': 'Güneş Sitesi',
          'assigned_door_name': 'Kapı ${i + 1}',
        }),
    ];

/// PDF sayfa sayısı (sayfa ağacındaki /Count).
int _pageCount(Uint8List pdf) {
  final text = latin1.decode(pdf);
  final match = RegExp(r'/Type/Pages/Kids\[[^\]]*\]/Count (\d+)').firstMatch(text);
  expect(match, isNotNull, reason: 'sayfa ağacı bulunamadı');
  return int.parse(match!.group(1)!);
}

void expectValidPdf(Uint8List bytes) {
  expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  expect(latin1.decode(bytes.sublist(bytes.length - 8)), contains('%%EOF'));
}

/// Flutter SDK'sındaki Roboto TTF'leri (varsa); yoksa null (TTF'ye özgü testler atlanır).
PdfFontSet? _sdkRoboto() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return null;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final regular = File('$dir/roboto-regular.ttf');
  final bold = File('$dir/roboto-bold.ttf');
  final medium = File('$dir/roboto-medium.ttf');
  if (!regular.existsSync() || !bold.existsSync() || !medium.existsSync()) return null;
  return PdfFontSet(
    regular: regular.readAsBytesSync(),
    bold: bold.readAsBytesSync(),
    medium: medium.readAsBytesSync(),
  );
}

class _LoopLag {
  _LoopLag() {
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = _clock.elapsedMicroseconds;
      final gap = now - _last;
      if (gap > _maxGapMicros) _maxGapMicros = gap;
      _last = now;
    });
  }

  final Stopwatch _clock = Stopwatch();
  late final Timer _timer;
  int _last = 0;
  int _maxGapMicros = 0;

  double get maxGapMs => _maxGapMicros / 1000.0;

  void stop() => _timer.cancel();
}

/// Testlerin varsayılan yazı tipleri: Roboto (varsa; Türkçe karakterler uyarı üretmez), yoksa Helvetica.
final PdfFontSet _fonts = _sdkRoboto() ?? PdfFontSet.helvetica;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BackgroundWork.debugRunCount = 0;
    BackgroundWork.debugRunInline = false;
  });

  group('PdfFontSet', () {
    test('bayt yoksa Helvetica yedeği, bayt varsa gömülü TTF kurulur', () {
      expect(PdfFontSet.helvetica.resolve().regular, isA<pw.Font>());
      expect(PdfFontSet.helvetica.resolve().regular, isNot(isA<pw.TtfFont>()));

      final roboto = _sdkRoboto();
      if (roboto == null) {
        markTestSkipped('Flutter SDK Roboto dosyaları bulunamadı');
        return;
      }
      final fonts = roboto.resolve();
      expect(fonts.regular, isA<pw.TtfFont>());
      expect(fonts.bold, isA<pw.TtfFont>());
      // Her çözümleme yeni nesneler üretir (belge başına bir kez çağrılmalı).
      expect(identical(roboto.resolve().regular, fonts.regular), isFalse);
    });
  });

  group('geçiş günlüğü PDF', () {
    test('arka plan izolesinde geçerli bir PDF üretir', () async {
      final bytes = await PdfLogsService.generateLogsPdf(
        logs: _logs(120),
        siteName: 'Güneş Sitesi',
        doorNameFilter: 'Ana Kapı',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 8),
        fonts: _fonts,
      );
      expect(BackgroundWork.debugRunCount, 1);
      expectValidPdf(bytes);
      expect(_pageCount(bytes), greaterThan(1));
    });

    test('ana izole (inline) yolu ile aynı sayfa sayısını üretir; boş liste de çalışır', () async {
      final logs = _logs(150);
      final viaIsolate = await PdfLogsService.generateLogsPdf(logs: logs, fonts: _fonts);
      BackgroundWork.debugRunInline = true;
      final viaInline = await PdfLogsService.generateLogsPdf(logs: logs, fonts: _fonts);
      expect(_pageCount(viaIsolate), _pageCount(viaInline));

      final empty = await PdfLogsService.generateLogsPdf(logs: const <DoorAccessLogRecord>[], fonts: _fonts);
      expectValidPdf(empty);
    });

    test('üretim hatası eskisi gibi çağırana aynı tür/mesajla ulaşır (>20 sayfa sınırı)', () async {
      // pw.MultiPage varsayılan 20 sayfa sınırı: eski (ana izole) davranış da bu istisnaydı.
      await expectLater(
        PdfLogsService.generateLogsPdf(logs: _logs(900), fonts: _fonts),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('more than 20 pages')),
        ),
      );
      BackgroundWork.debugRunInline = true;
      await expectLater(
        PdfLogsService.generateLogsPdf(logs: _logs(900), fonts: _fonts),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('more than 20 pages')),
        ),
      );
    });

    test('Türkçe karakterli TTF ile de üretilir (gömülü yazı tipi)', () async {
      final roboto = _sdkRoboto();
      if (roboto == null) {
        markTestSkipped('Flutter SDK Roboto dosyaları bulunamadı');
        return;
      }
      final bytes = await PdfLogsService.generateLogsPdf(
        logs: _logs(40),
        siteName: 'ÇĞİÖŞÜ çğıöşü Sitesi',
        fonts: roboto,
      );
      expectValidPdf(bytes);
      // Gömülü TrueType yazı tipi: Type0 (CID) bileşik yazı tipi nesnesi.
      expect(latin1.decode(bytes), contains('/Subtype/Type0'));
    });
  });

  group('giriş bilgileri ve firmware PDF', () {
    test('tek site giriş bilgileri PDF arka planda üretilir', () async {
      final bytes = await PdfCredentialsService.generateSiteCredentialsPdf(
        structure: _structure(1, 60),
        companyName: 'GÜDE TEKNOLOJİ',
        fonts: _fonts,
      );
      expect(BackgroundWork.debugRunCount, 1);
      expectValidPdf(bytes);
      expect(_pageCount(bytes), greaterThanOrEqualTo(1));
    });

    test('toplu (çok siteli) giriş bilgileri PDF: her site en az bir sayfa', () async {
      final bytes = await PdfCredentialsService.generateMultiSiteCredentialsPdf(
        structures: [_structure(1, 10), _structure(2, 10), _structure(3, 10)],
        fonts: _fonts,
      );
      expect(BackgroundWork.debugRunCount, 1);
      expectValidPdf(bytes);
      expect(_pageCount(bytes), greaterThanOrEqualTo(3));
    });

    test('firmware raporu PDF arka planda üretilir', () async {
      final bytes = await PdfDeviceFirmwareService.generateFirmwareReportPdf(
        devices: _devices(80),
        userEmail: 'yonetici@example.com',
        fonts: _fonts,
      );
      expect(BackgroundWork.debugRunCount, 1);
      expectValidPdf(bytes);
      expect(_pageCount(bytes), greaterThanOrEqualTo(1));
    });
  });

  test('ÖLÇÜM: ~300 satırlık günlük raporunda ana izolenin bloklanması (inline -> arka plan)', () async {
    final fonts = _sdkRoboto() ?? PdfFontSet.helvetica;
    final logs = _logs(300);

    Future<({double gapMs, int wallMs, int bytes})> run(bool inline) async {
      BackgroundWork.debugRunInline = inline;
      final lag = _LoopLag();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final clock = Stopwatch()..start();
      final bytes = await PdfLogsService.generateLogsPdf(logs: logs, fonts: fonts, siteName: 'Ölçüm');
      clock.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      lag.stop();
      return (gapMs: lag.maxGapMs, wallMs: clock.elapsedMilliseconds, bytes: bytes.length);
    }

    await run(true); // ısınma (JIT)
    final inline = await run(true);
    final background = await run(false);
    print(
      'ÖLÇÜM 300 satır: inline ana izole en uzun boşluk ${inline.gapMs.toStringAsFixed(0)} ms '
      '(toplam ${inline.wallMs} ms) -> arka plan ${background.gapMs.toStringAsFixed(0)} ms '
      '(toplam ${background.wallMs} ms), PDF ${inline.bytes} B',
    );
    expect(background.gapMs, lessThan(inline.gapMs));
    expect(background.bytes, closeTo(inline.bytes.toDouble(), inline.bytes * 0.02));
  });
}
