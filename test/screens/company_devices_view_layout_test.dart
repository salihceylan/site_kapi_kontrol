// FAZ 5 / A2-G3: Şirket Cihaz Envanteri (CompanyDevicesView, CompanyDeviceCard).
//
// AGENTS.md kural 6: taşma YOK (320x640 x2,0 ve 360x640 x1,5; açık + koyu tema). Davranış: ilk
// yüklemede iskelet, yenilemede mevcut liste + ince çubuk; eylem düğmeleri GÖRÜNÜR; nabız 3 tur sonra
// durur (kararlı durumda sürekli animasyon yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/company_devices_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/company_device_card.dart';

import 'list_fixtures.dart';

CompanyDevicesView _view({
  List<String>? log,
  bool superUser = true,
  bool loading = false,
  bool broadcasting = false,
  List<DeviceRecord>? devices,
  DevicePage? page,
  bool register = true,
}) {
  final l = log ?? <String>[];
  final list = devices ?? fxDevices();
  return CompanyDevicesView(
    pageData: page ?? fxDevicePage(list, total: 25),
    devices: list,
    isSuperUser: superUser,
    isLoading: loading,
    isBroadcastingOta: broadcasting,
    onBroadcastOta: () => l.add('ota'),
    onRefresh: () => l.add('refresh'),
    onLoadPage: (p) => l.add('page:$p'),
    onEditDevice: (d) => l.add('edit:${d.id}'),
    onAssignDeviceToDoor: (d) => l.add('assign:${d.id}'),
    onDeleteDevice: (d) => l.add('delete:${d.id}'),
    onDownloadFirmwareReportPdf: () => l.add('pdf'),
    onRegisterNewDevice: register ? () => l.add('register') : null,
    onToggleDefect: (d) => l.add('defect:${d.id}'),
    onReleaseOwnership: (d) => l.add('release:${d.id}'),
  );
}

void main() {
  group('CompanyDevicesView taşma matrisi', () {
    listMatrix('tam liste: eylem satırı, gruplar, kartlar, sayfalama', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(t, _view(), width: w, height: h, scale: scale, dark: dark);
      for (final text in const <String>[
        'Tümüne OTA Kontrolü',
        'Sürüm Raporu (PDF)',
        'Atama Bekleyen Cihazlar (2)',
        'Kapıya Atanmış Cihazlar (1)',
        '7CDFA1E2E004',
        '1CDA72A172E0',
        '240AC4E2E001',
        'KAPI ATANMAMIŞ',
        'ARIZALI',
        'Online',
        'Offline',
        'Bilinmiyor',
        'ESP32-WROOM',
        'Sayfa 1 / 3 | Toplam 25',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'metin korunmalı: $text');
      }
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(find.byType(CompanyDeviceCard), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    listMatrix('kartlar açılır: çipler ve görünür eylemler', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Düzenle'), findsNothing);
      await tapText(t, '7CDFA1E2E004');
      for (final text in const <String>[
        'Kullanıcı ID: 4242',
        'Sahip: Ayşe Yılmaz',
        'Arıza Nedeni: Röle kartı yanıt vermiyor',
        'MQTT: Hazır',
        'Firmware: 3.0.3',
        'Model: ESP32-C3',
        'OTA Durumu: Güncel',
        'Wi-Fi Gücü: %82 (-58 dBm)',
        'Yerel IP: 192.168.1.105',
        'Genel IP: 88.250.10.20',
        'MQTT Kullanıcı: device_7CDFA1E2E004',
        'Düzenle',
        'Kapıya Ata',
        'Arızayı Kaldır',
        'Depoya Al',
        'Sil',
      ]) {
        expect(find.text(text), findsOneWidget, reason: 'açık kart: $text');
      }
      await tapText(t, 'Düzenle');
      await tapText(t, 'Kapıya Ata');
      await tapText(t, 'Arızayı Kaldır');
      await tapText(t, 'Depoya Al');
      await tapText(t, 'Sil');
      expect(log, <String>[
        'edit:2',
        'assign:2',
        'defect:2',
        'release:2',
        'delete:2',
      ]);
    });

    listMatrix('iskelet, yenileme çubuğu, boş durumlar, kayıt düğmesi', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      // İlk yükleme: liste boş + yükleniyor -> iskelet (spinner/çubuk yok).
      await pumpList(
        t,
        _view(loading: true, devices: const <DeviceRecord>[]),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Yenileme: mevcut liste kalır, üstte ince çubuk.
      await pumpList(
        t,
        _view(loading: true),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.byType(ShimmerScope), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CompanyDeviceCard), findsNWidgets(3));

      // Boş: süper kullanıcı yönlendirme metni; değilse "Yeni Cihaz Kaydet".
      await pumpList(
        t,
        _view(devices: const <DeviceRecord>[]),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(
        find.text('Şirket hesabına kayıtlı cihaz bulunamadı.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Yeni cihaz eklemek için sol menüdeki "Şirket Cihazı Kaydet" bölümünü kullanabilirsiniz.',
        ),
        findsOneWidget,
      );
      expect(find.text('Yeni Cihaz Kaydet'), findsNothing);
      await pumpList(
        t,
        _view(superUser: false, devices: const <DeviceRecord>[]),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Yeni Cihaz Kaydet'), findsOneWidget);
      expect(find.text('Tümüne OTA Kontrolü'), findsNothing);

      // Süper olmayan kullanıcı, dolu liste: alttaki tam genişlik kayıt düğmesi.
      await pumpList(
        t,
        _view(superUser: false),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(
        find.text('Yeni Cihaz Kaydet (Kutu QR / Seri No)'),
        findsOneWidget,
      );
      expect(find.text('Sürüm Raporu (PDF)'), findsNothing);
    });
  });

  group('CompanyDevicesView davranış', () {
    testWidgets(
      'üst eylemler: OTA, PDF, yenile; yüklenirken/boşken devre dışı',
      (t) async {
        final log = <String>[];
        await pumpList(
          t,
          _view(log: log),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        await tapText(t, 'Tümüne OTA Kontrolü');
        await tapText(t, 'Sürüm Raporu (PDF)');
        await tapFinder(t, find.byTooltip('Yenile'));
        expect(log, <String>['ota', 'pdf', 'refresh']);

        await pumpList(
          t,
          _view(broadcasting: true),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.text('Gönderiliyor...'), findsOneWidget);
        expect(
          t
              .widget<ElevatedButton>(
                find.ancestor(
                  of: find.text('Gönderiliyor...'),
                  matching: find.byType(ElevatedButton),
                ),
              )
              .onPressed,
          isNull,
        );

        await pumpList(
          t,
          _view(loading: true),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(
          t
              .widget<ElevatedButton>(
                find.ancestor(
                  of: find.text('Tümüne OTA Kontrolü'),
                  matching: find.byType(ElevatedButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          t
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.refresh),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'sayfalama: yalnız birden çok sayfada; yüklenirken düğmeler kapalı',
      (t) async {
        final log = <String>[];
        final devices = fxDevices();
        await pumpList(
          t,
          _view(
            log: log,
            devices: devices,
            page: fxDevicePage(devices, total: 25, page: 2),
          ),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.text('Sayfa 2 / 3 | Toplam 25'), findsOneWidget);
        await tapFinder(t, find.byTooltip('Önceki sayfa'));
        await tapFinder(t, find.byTooltip('Sonraki sayfa'));
        expect(log, <String>['page:1', 'page:3']);

        // Tek sayfa: sayfalama gösterilmez.
        await pumpList(
          t,
          _view(devices: devices, page: fxDevicePage(devices, total: 3)),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.byTooltip('Önceki sayfa'), findsNothing);

        // Yüklenirken sayfa düğmeleri devre dışı.
        await pumpList(
          t,
          _view(
            loading: true,
            devices: devices,
            page: fxDevicePage(devices, total: 25, page: 2),
          ),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(
          t
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_left),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'kararlı durumda sürekli animasyon yok: nabız 3 tur sonra durur',
      (t) async {
        await pumpList(
          t,
          _view(),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        // Çevrimiçi cihaz nabız atar (StatusChip.pulse); pumpAndSettle bitmelidir.
        expect(
          t
              .widgetList<StatusChip>(find.byType(StatusChip))
              .where((c) => c.pulse)
              .length,
          1,
        );
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        expect(t.binding.hasScheduledFrame, isFalse);
      },
    );

    testWidgets('kapısız cihaz uyarı tonlu kart; kapıya atanmış cihaz tonsuz', (
      t,
    ) async {
      await pumpList(
        t,
        _view(),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      final tones = t
          .widgetList<AppCard>(find.byType(AppCard))
          .where((c) => c.onTap != null)
          .map((c) => c.tone)
          .toList();
      expect(tones, <AppTone?>[AppTone.warning, AppTone.warning, null]);
    });

    testWidgets('süper olmayan kullanıcıda yıkıcı/ileri eylemler yok', (
      t,
    ) async {
      await pumpList(
        t,
        _view(superUser: false),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapText(t, '240AC4E2E001');
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Kapıya Ata'), findsOneWidget);
      expect(find.text('Sil'), findsNothing);
      expect(find.text('Depoya Al'), findsNothing);
      expect(find.text('Arızalı İşaretle'), findsNothing);
      expect(find.textContaining('OTA Durumu'), findsNothing);
    });
  });

  group('CompanyDevicesView kontrast', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        '"Sil", uyarı metni ve kayıt düğmesi >= 4,5:1 (${dark ? 'koyu' : 'açık'})',
        (t) async {
          await pumpList(
            t,
            _view(),
            width: 360,
            height: 800,
            scale: 1,
            dark: dark,
          );
          final p = dark ? AppPalette.dark : AppPalette.light;
          await tapText(t, '7CDFA1E2E004');
          // Kapısız kart uyarı tonlu: zemin = surface üstüne warning tint.
          final cardBg = Color.alphaBlend(AppTone.warning.tint(p), p.surface);
          final del = t.widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Sil'),
              matching: find.byType(OutlinedButton),
            ),
          );
          final fg = del.style!.foregroundColor!.resolve(<WidgetState>{})!;
          expect(fg, AppTone.danger.ink(p));
          expect(contrastRatio(fg, cardBg), greaterThanOrEqualTo(4.5));

          // "Kapıya Ata": kapısız cihazda warning dolgu üstünde beyaz (eski #D97706 + beyaz ~3,2:1).
          final assign = t.widget<ElevatedButton>(
            find.ancestor(
              of: find.text('Kapıya Ata'),
              matching: find.byType(ElevatedButton),
            ),
          );
          final bg = assign.style!.backgroundColor!.resolve(<WidgetState>{})!;
          expect(bg, AppTone.warning.a);
          expect(contrastRatio(Colors.white, bg), greaterThanOrEqualTo(4.5));

          // "Kapı: Kapı atanmamış" vurgusu uyarı ink'i, kart zemininde.
          final rich = t.widget<Text>(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Text &&
                      w.textSpan != null &&
                      w.textSpan!.toPlainText().contains('Kapı atanmamış'),
                )
                .first,
          );
          final span = (rich.textSpan! as TextSpan).children!.last as TextSpan;
          expect(span.style!.color, AppTone.warning.ink(p));
          expect(
            contrastRatio(span.style!.color!, cardBg),
            greaterThanOrEqualTo(4.5),
          );
        },
      );
    }
  });

  group('CompanyDevicesView geniş ekran ve yatay', () {
    testWidgets('820x640 ve 900x400 (yatay), 1,0x/1,5x, açık/koyu: taşma yok', (
      t,
    ) async {
      for (final (w, h) in const <(double, double)>[(820, 640), (900, 400)]) {
        for (final scale in const <double>[1.0, 1.5]) {
          for (final dark in const <bool>[false, true]) {
            await pumpList(
              t,
              _view(),
              width: w,
              height: h,
              scale: scale,
              dark: dark,
            );
            await tapText(t, '7CDFA1E2E004');
            expect(find.text('Düzenle'), findsOneWidget);
            expect(t.takeException(), isNull);
          }
        }
      }
    });
  });
}
