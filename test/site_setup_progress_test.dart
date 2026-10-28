// Site kurulum sihirbazı ilerleme modeli ve cihazdaki kaydı (P2-15: "yarım kalan kurulum devam eder").
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';

void main() {
  group('SiteSetupProgress modeli', () {
    test('yeni ilerleme boştur: ilk adım, hiçbir şey tamam değil, dikkat ister', () {
      const progress = SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi');
      expect(progress.current, SiteSetupStep.siteInfo);
      expect(progress.doneCount, 0);
      expect(progress.isComplete, isFalse);
      expect(progress.needsAttention, isTrue);
      expect(progress.firstOpen, SiteSetupStep.siteInfo);
      expect(progress.started, isFalse);
    });

    test('markDone adımı tamamlar ve atlananlardan çıkarır', () {
      var progress = const SiteSetupProgress(siteCode: 11);
      progress = progress.markSkipped(SiteSetupStep.people);
      expect(progress.isSkipped(SiteSetupStep.people), isTrue);
      progress = progress.markDone(SiteSetupStep.people);
      expect(progress.isDone(SiteSetupStep.people), isTrue);
      expect(progress.isSkipped(SiteSetupStep.people), isFalse);
      expect(progress.skipped, isEmpty);
    });

    test('tamamlanmış adım atlanmış SAYILMAZ', () {
      final progress = const SiteSetupProgress(siteCode: 11).markDone(SiteSetupStep.blocks).markSkipped(SiteSetupStep.blocks);
      expect(progress.isDone(SiteSetupStep.blocks), isTrue);
      expect(progress.isSkipped(SiteSetupStep.blocks), isFalse);
    });

    test('firstOpen: önce dokunulmamış ilk adım, sonra atlanan ilk adım, hepsi tamamsa null', () {
      var progress = const SiteSetupProgress(siteCode: 11)
          .markDone(SiteSetupStep.siteInfo)
          .markDone(SiteSetupStep.blocks)
          .markSkipped(SiteSetupStep.apartments);
      expect(progress.firstOpen, SiteSetupStep.people, reason: 'dokunulmamış adım atlanandan önce gelir');
      progress = progress
          .markDone(SiteSetupStep.people)
          .markDone(SiteSetupStep.modules)
          .markDone(SiteSetupStep.finance);
      expect(progress.firstOpen, SiteSetupStep.apartments, reason: 'yalnız atlanan kaldı');
      progress = progress.markDone(SiteSetupStep.apartments);
      expect(progress.firstOpen, isNull);
      expect(progress.isComplete, isTrue);
      expect(progress.needsAttention, isFalse);
    });

    test('bitmiş ya da kapatılmış kurulum dikkat istemez; reopened geri açar', () {
      final progress = const SiteSetupProgress(siteCode: 11);
      expect(progress.markFinished().needsAttention, isFalse);
      expect(progress.markDismissed().needsAttention, isFalse);
      expect(progress.markFinished().markDismissed().reopened().needsAttention, isTrue);
    });

    test('adım sırası: after / before uçlarda null', () {
      expect(SiteSetupProgress.before(SiteSetupStep.siteInfo), isNull);
      expect(SiteSetupProgress.after(SiteSetupStep.finance), isNull);
      expect(SiteSetupProgress.after(SiteSetupStep.siteInfo), SiteSetupStep.blocks);
      expect(SiteSetupProgress.before(SiteSetupStep.finance), SiteSetupStep.modules);
      expect(SiteSetupProgress.stepCount, SiteSetupStep.values.length);
    });

    test('JSON gidiş-dönüş tüm alanları korur', () {
      final at = DateTime.utc(2026, 10, 28, 12, 30);
      final progress = SiteSetupProgress(
        siteCode: 11,
        siteName: 'Gül Sitesi',
        current: SiteSetupStep.people,
        done: const {SiteSetupStep.siteInfo, SiteSetupStep.blocks},
        skipped: const {SiteSetupStep.modules},
        started: true,
        finished: false,
        dismissed: true,
        updatedAt: at,
      );
      final restored = SiteSetupProgress.fromJson(jsonDecode(jsonEncode(progress.toJson())));
      expect(restored, isNotNull);
      expect(restored!.siteCode, 11);
      expect(restored.siteName, 'Gül Sitesi');
      expect(restored.current, SiteSetupStep.people);
      expect(restored.done, {SiteSetupStep.siteInfo, SiteSetupStep.blocks});
      expect(restored.skipped, {SiteSetupStep.modules});
      expect(restored.started, isTrue);
      expect(restored.dismissed, isTrue);
      expect(restored.updatedAt!.toUtc(), at);
    });

    test('bozuk kayıt savunmacı ayrıştırılır: site kodu yoksa null, bilinmeyen adımlar yok sayılır', () {
      expect(SiteSetupProgress.fromJson('x'), isNull);
      expect(SiteSetupProgress.fromJson(<String, Object?>{'name': 'x'}), isNull);
      expect(SiteSetupProgress.fromJson(<String, Object?>{'site': 0}), isNull);
      final parsed = SiteSetupProgress.fromJson(<String, Object?>{
        'site': '12',
        'step': 'gelecekteki_adim',
        'done': <Object?>['people', 'gelecekteki_adim', 7],
        'skipped': 'yanlis',
        'at': 'dun',
      });
      expect(parsed, isNotNull);
      expect(parsed!.siteCode, 12);
      expect(parsed.current, SiteSetupStep.siteInfo, reason: 'bilinmeyen adım ilk adıma düşer');
      expect(parsed.done, {SiteSetupStep.people});
      expect(parsed.skipped, isEmpty);
      expect(parsed.updatedAt, isNull);
    });
  });

  group('SiteSetupProgressStore', () {
    late SiteSetupProgressStore store;
    var clockTick = 0;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      clockTick = 0;
      store = SiteSetupProgressStore(now: () => DateTime.utc(2026, 10, 28, 9).add(Duration(minutes: clockTick++)));
    });

    test('kaydedilen ilerleme aynı kullanıcı ve sitede geri okunur; başka kullanıcıda görünmez', () async {
      await store.save(5, const SiteSetupProgress(siteCode: 11, siteName: 'Gül', current: SiteSetupStep.finance, started: true));
      final loaded = await store.load(5, 11);
      expect(loaded, isNotNull);
      expect(loaded!.current, SiteSetupStep.finance);
      expect(loaded.started, isTrue);
      expect(loaded.updatedAt, isNotNull, reason: 'zaman damgası yoksa kayıtta eklenir');
      expect(await store.load(5, 12), isNull);
      expect(await store.load(6, 11), isNull);
    });

    test('aynı siteyi yeniden kaydetmek değiştirir, çoğaltmaz', () async {
      await store.save(5, const SiteSetupProgress(siteCode: 11));
      await store.save(5, const SiteSetupProgress(siteCode: 11, current: SiteSetupStep.modules));
      final all = await store.loadAll(5);
      expect(all, hasLength(1));
      expect(all.single.current, SiteSetupStep.modules);
    });

    test('ensure: kayıt yoksa açar (true), varsa dokunmaz (false)', () async {
      expect(await store.ensure(5, 11, siteName: 'Gül'), isTrue);
      await store.save(5, (await store.load(5, 11))!.copyWith(current: SiteSetupStep.people, started: true));
      expect(await store.ensure(5, 11, siteName: 'Başka'), isFalse);
      final loaded = (await store.load(5, 11))!;
      expect(loaded.current, SiteSetupStep.people, reason: 'var olan ilerleme ezilmez');
      expect(loaded.siteName, 'Gül');
    });

    test('nextUnfinished: bitmiş ve kapatılmış kurulum hatırlatılmaz, en son güncellenen önce gelir', () async {
      await store.save(5, const SiteSetupProgress(siteCode: 1, siteName: 'Eski'));
      await store.save(5, const SiteSetupProgress(siteCode: 2, siteName: 'Bitti', finished: true));
      await store.save(5, const SiteSetupProgress(siteCode: 3, siteName: 'Kapalı', dismissed: true));
      await store.save(5, const SiteSetupProgress(siteCode: 4, siteName: 'Yeni'));
      final next = await store.nextUnfinished(5);
      expect(next?.siteCode, 4, reason: 'en son güncellenen bitmemiş kurulum');
      await store.remove(5, 4);
      expect((await store.nextUnfinished(5))?.siteCode, 1);
      await store.remove(5, 1);
      expect(await store.nextUnfinished(5), isNull);
    });

    test('bozuk saklama içeriği "kayıt yok" sayılır ve sonraki kayıt onu onarır', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{SiteSetupProgressStore.keyFor(5): '{bozuk'});
      expect(await store.loadAll(5), isEmpty);
      await store.save(5, const SiteSetupProgress(siteCode: 11));
      expect((await store.loadAll(5)).single.siteCode, 11);
    });

    test('en çok maxEntries site tutulur: en eski güncellenen düşer', () async {
      for (var site = 1; site <= SiteSetupProgressStore.maxEntries + 3; site++) {
        await store.save(5, SiteSetupProgress(siteCode: site));
      }
      final all = await store.loadAll(5);
      expect(all, hasLength(SiteSetupProgressStore.maxEntries));
      expect(all.any((e) => e.siteCode == 1), isFalse, reason: 'en eski kayıt düştü');
      expect(all.any((e) => e.siteCode == SiteSetupProgressStore.maxEntries + 3), isTrue);
    });

    test('art arda ve eşzamanlı kayıtlar birbirini ezmez', () async {
      await Future.wait(<Future<void>>[
        for (var site = 1; site <= 6; site++) store.save(5, SiteSetupProgress(siteCode: site, siteName: 'S$site')),
      ]);
      final all = await store.loadAll(5);
      expect(all.map((e) => e.siteCode).toSet(), {1, 2, 3, 4, 5, 6});
    });

    test('değişiklik dinleyicilere bildirilir (kaydet, ensure, sil)', () async {
      var notified = 0;
      store.addListener(() => notified++);
      await store.save(5, const SiteSetupProgress(siteCode: 11));
      await store.ensure(5, 12);
      await store.remove(5, 11);
      expect(notified, 3);
      await store.ensure(5, 12); // zaten var: bildirim yok
      await store.remove(5, 99); // yok: bildirim yok
      expect(notified, 3);
    });
  });
}
