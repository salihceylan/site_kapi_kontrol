// E2E altyapisinin (integration_test/support) hata toplayicisini dogrular: "0 tasma" sonucunun yanlis
// negatif olmadigindan emin olmak icin gercek bir RenderFlex tasmasinin yakalanip siniflandirildigini
// gosterir.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_driver.dart' show foldText, E2ePolicy;
import '../integration_test/support/e2e_report.dart';

void main() {
  testWidgets('E2eCollector RenderFlex tasmasini "overflow" olarak yakalar (testi cokertmez)', (tester) async {
    final collector = E2eCollector()..install();
    addTearDown(collector.uninstall);
    collector.beginScreen('deneme_ekrani');

    tester.view.physicalSize = const Size(300, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Container(width: 400, height: 20, color: Colors.red),
              Container(width: 400, height: 20, color: Colors.blue),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final findings = collector.drain();
    expect(findings.any((f) => f.kind == 'overflow'), isTrue, reason: 'taşma yakalanmalı');
    final overflow = findings.firstWhere((f) => f.kind == 'overflow');
    expect(overflow.screen, 'deneme_ekrani');
    expect(overflow.message, contains('overflowed'));
    // Toplayici FlutterError.onError'i devraldigi icin test cokmez.
    expect(tester.takeException(), isNull);
  });

  group('E2ePolicy (guvenli-dokunma politikasi)', () {
    test('yikici etiketler engellenir', () {
      for (final label in <String>[
        'Sil',
        'Kalıcı Sil',
        'Pasife Al',
        'Reddet',
        'İptal Et',
        'Kaldır',
        'Yeniden Başlat',
        'Sıfırla',
        'Depoya Al',
        'Kapıdan Çıkar',
        'Onayla',
        'Kabul Et',
        'Çıkış Yap',
        'Çöp Temizliği Yap',
        'Sürüm Raporu (PDF)',
        'Tümüne OTA Kontrolü',
        'Bilgileri Gönder',
      ]) {
        expect(E2ePolicy.check(label, inDialog: false), isNotNull, reason: label);
      }
    });

    test('guvenli acici/kapatici etiketler serbesttir', () {
      for (final label in <String>[
        'Düzenle',
        'Yeni Site',
        'Yönetici Davet Et',
        'Vazgeç',
        'İptal',
        'Kapat',
        'Detaylar',
        'Kapı Aç',
        'Giriş QR Kodu Göster',
        'Kurye / Misafir Geçişi Oluştur',
      ]) {
        expect(E2ePolicy.check(label, inDialog: false), isNull, reason: label);
      }
    });

    test('diyalog icinde veri degistiren onay dugmeleri engellenir', () {
      for (final label in <String>['Kaydet', 'Oluştur', 'Gönder', 'Davet Et', 'Güncelle', 'Evet', 'Sahiplen']) {
        expect(E2ePolicy.check(label, inDialog: true), isNotNull, reason: label);
      }
      expect(E2ePolicy.check('Vazgeç', inDialog: true), isNull);
    });

    test('foldText aksan ve buyuk-kucuk harf duyarsizdir', () {
      expect(foldText('Süper Kullanıcı Yönetimi'), foldText('SUPER KULLANICI YONETIMI'));
      expect(foldText('İPTAL'), 'iptal');
    });
  });
}
