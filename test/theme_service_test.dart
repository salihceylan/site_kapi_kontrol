// Tema tercihi: sistem (varsayılan) / aydınlık / karanlık; cihazda saklanır (SharedPreferences).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('varsayılan: sistem teması (mevcut davranış korunur)', () async {
    final service = ThemeService();
    expect(service.mode, ThemeMode.system);
    await service.load();
    expect(service.mode, ThemeMode.system);
  });

  test('load: kayıtlı değerler okunur (dark / light)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeService.storageKey: 'dark',
    });
    final dark = ThemeService();
    await dark.load();
    expect(dark.mode, ThemeMode.dark);

    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeService.storageKey: 'light',
    });
    final light = ThemeService();
    await light.load();
    expect(light.mode, ThemeMode.light);
  });

  test('load: bilinmeyen / bozuk değer sistem temasına döner (çökmez)', () async {
    for (final raw in <String>['', 'mavi', 'DARK ', '1']) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ThemeService.storageKey: raw,
      });
      final service = ThemeService();
      await service.load();
      expect(service.mode, ThemeMode.system, reason: 'ham değer: "$raw"');
    }
  });

  test('setMode: değeri saklar ve değişince bir kez bildirir; aynı değer bildirmez', () async {
    final service = ThemeService();
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.setMode(ThemeMode.dark);
    expect(service.mode, ThemeMode.dark);
    expect(notifications, 1);
    expect((await SharedPreferences.getInstance()).getString(ThemeService.storageKey), 'dark');

    await service.setMode(ThemeMode.dark);
    expect(notifications, 1, reason: 'aynı değer yeniden bildirilmemeli');
  });

  test('kalıcılık: yeni örnek, son seçimi load ile geri okur', () async {
    final first = ThemeService();
    await first.setMode(ThemeMode.light);
    final second = ThemeService();
    expect(second.mode, ThemeMode.system, reason: 'load edilene dek varsayılan');
    await second.load();
    expect(second.mode, ThemeMode.light);
  });

  test('toggle: görünen tema koyuysa aydınlığa, aydınlıksa karanlığa geçer', () async {
    final service = ThemeService();
    await service.toggle(Brightness.light);
    expect(service.mode, ThemeMode.dark);
    await service.toggle(Brightness.dark);
    expect(service.mode, ThemeMode.light);
  });

  test('toggle: sistem modundayken de GÖRÜNEN temanın tersi seçilir', () async {
    final service = ThemeService();
    expect(service.mode, ThemeMode.system);
    await service.toggle(Brightness.dark); // sistem koyu görünüyor
    expect(service.mode, ThemeMode.light);
  });
}
