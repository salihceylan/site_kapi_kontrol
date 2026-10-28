// Site kurulum sihirbazı denetleyicisi (P2-15): adım geçişleri, yarım kalma / devam, dürüst hata durumu.
//
// Kurallar: "Devam" yalnız tamamlanmış (ya da durumu okunamayan / yalnız onay isteyen) adımda, "Atla" tamamlanmamış
// adımda; sunucudan gözlenen tamamlanma ilerlemeye işlenir ve geri alınmaz; hata "yok" DEMEZ.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_controller.dart';

import 'finance_fixtures.dart' show finDefinition;
import 'people_fixtures.dart';
import 'site_setup_fixtures.dart';

const int _userId = 5; // pplSession: yönetici 5, süper kullanıcı 1

SiteSetupController _controller(
  SetupWizardFakeAuth auth,
  SiteSetupProgressStore store, {
  int? userId,
  String siteName = 'Gül Sitesi',
}) {
  return SiteSetupController(
    authService: auth,
    siteCode: auth.siteCode,
    userId: userId ?? auth.session!.id,
    siteName: siteName,
    store: store,
    now: () => DateTime.utc(2026, 10, 28, 10),
  );
}

void main() {
  late SiteSetupProgressStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = SiteSetupProgressStore();
  });

  group('açılış ve durum', () {
    test('yeni kurulmuş site: site, blok ve daire adımları sunucu verisinden tamamdır; ilk açık adım Kişiler', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      expect(c.started, isTrue);
      expect(c.loading, isFalse);
      expect(c.statusOf(SiteSetupStep.siteInfo), SiteSetupStatus.done);
      expect(c.statusOf(SiteSetupStep.blocks), SiteSetupStatus.done);
      expect(c.statusOf(SiteSetupStep.apartments), SiteSetupStatus.done);
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.open);
      expect(c.statusOf(SiteSetupStep.modules), SiteSetupStatus.open);
      expect(c.statusOf(SiteSetupStep.finance), SiteSetupStatus.open);
      expect(c.current, SiteSetupStep.people, reason: 'ilk açılışta sıradaki yapılacak adımdan başlar');
      expect(c.showingSummary, isFalse);
      expect(c.snapshot.blockCount, 2);
      expect(c.snapshot.apartmentCount, 6);
      expect(c.snapshot.peopleCount, 0);
      expect(c.snapshot.feeDefinitionCount, 0);
      expect(c.snapshot.openPeriodLabel, isNotNull, reason: 'açık dönem bilgi amaçlı okunur');
      c.dispose();
    });

    test('ilk açılış ilerlemeyi hemen kaydeder (started + kalınan adım)', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      await Future<void>.delayed(Duration.zero);
      final saved = await store.load(_userId, 11);
      expect(saved, isNotNull);
      expect(saved!.started, isTrue);
      expect(saved.current, SiteSetupStep.people);
      expect(saved.done, containsAll(<SiteSetupStep>[SiteSetupStep.siteInfo, SiteSetupStep.blocks, SiteSetupStep.apartments]));
      c.dispose();
    });

    test('kişi, aidat tanımı olan site: Kişiler ve Finans da sunucudan tamam sayılır', () async {
      final auth = SetupWizardFakeAuth()
        ..peopleJson[1] = pplPersonJson(1, 'Ayşe Yılmaz')
        ..definitions[1] = finDefinition(1);
      final c = _controller(auth, store);
      await c.start();
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.done);
      expect(c.statusOf(SiteSetupStep.finance), SiteSetupStatus.done);
      expect(c.current, SiteSetupStep.modules, reason: 'yalnız modül onayı kaldı');
      c.dispose();
    });

    test('yönetici olmayan rol sihirbazı kullanamaz', () async {
      final auth = SetupWizardFakeAuth(role: UserRole.apartmentOwner);
      final c = _controller(auth, store);
      expect(c.isAllowed, isFalse);
      c.dispose();
      expect(_controller(SetupWizardFakeAuth(), store).isAllowed, isTrue);
      expect(_controller(SetupWizardFakeAuth.superUser(), store).isAllowed, isTrue);
    });

    test('yönetim türü terimleri sunucudan gelir (Kat / Ofis)', () async {
      final auth = SetupWizardFakeAuth(
        managementType: 'business_center',
        typeLabel: 'İş Merkezi',
        managementTerms: <String, dynamic>{'unit': 'Ofis', 'unit_plural': 'Ofisler', 'block': 'Kat', 'block_plural': 'Katlar', 'fee': 'Ortak gider'},
      );
      final c = _controller(auth, store);
      await c.start();
      expect(c.snapshot.terms.unitPlural, 'Ofisler');
      expect(c.snapshot.terms.blockPlural, 'Katlar');
      expect(c.snapshot.terms.fee, 'Ortak gider');
      c.dispose();
    });
  });

  group('adım geçişleri', () {
    test('Devam yalnız tamamlanmış adımda, Atla tamamlanmamış adımda vardır', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      expect(c.current, SiteSetupStep.people);
      expect(c.canContinue, isFalse, reason: 'kimse eklenmedi: önce yap ya da atla');
      expect(c.canSkip, isTrue);
      c.goTo(SiteSetupStep.blocks);
      expect(c.canContinue, isTrue, reason: 'tamamlanmış adım');
      expect(c.canSkip, isFalse, reason: 'tamamlanmış adım atlanmaz');
      c.dispose();
    });

    test('Devam sıradaki adıma geçirir ve kalınan adım kaydedilir', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      c.goTo(SiteSetupStep.siteInfo);
      c.next();
      expect(c.current, SiteSetupStep.blocks);
      c.next();
      expect(c.current, SiteSetupStep.apartments);
      await Future<void>.delayed(Duration.zero);
      expect((await store.load(_userId, 11))!.current, SiteSetupStep.apartments);
      c.dispose();
    });

    test('tamamlanmamış adımda Devam hiçbir şey yapmaz', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      expect(c.current, SiteSetupStep.people);
      c.next();
      expect(c.current, SiteSetupStep.people);
      expect(c.progress.isDone(SiteSetupStep.people), isFalse);
      c.dispose();
    });

    test('Atla adımı atlandı işaretler ve sıradakine geçer; atlanan adım "Atlandı" kalır', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      c.skip();
      expect(c.current, SiteSetupStep.modules);
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.skipped);
      expect(c.progress.isDone(SiteSetupStep.people), isFalse);
      c.dispose();
    });

    test('Modüller adımı yalnız onay ister: Devam etkindir ve adımı tamamlar', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      c.goTo(SiteSetupStep.modules);
      expect(c.statusOf(SiteSetupStep.modules), SiteSetupStatus.open);
      expect(c.canContinue, isTrue, reason: 'temel modüller zaten açık; yapılacak zorunlu iş yok');
      c.next();
      expect(c.statusOf(SiteSetupStep.modules), SiteSetupStatus.done);
      expect(c.current, SiteSetupStep.finance);
      c.dispose();
    });

    test('son adımdan sonra özet açılır; Geri özetten son adıma döner', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      c.goTo(SiteSetupStep.finance);
      expect(c.isLast, isTrue);
      c.skip();
      expect(c.showingSummary, isTrue);
      expect(c.statusOf(SiteSetupStep.finance), SiteSetupStatus.skipped);
      c.back();
      expect(c.showingSummary, isFalse);
      expect(c.current, SiteSetupStep.finance);
      c.dispose();
    });

    test('Geri bir önceki adıma döner; ilk adımda yerinde kalır', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      c.goTo(SiteSetupStep.apartments);
      c.back();
      expect(c.current, SiteSetupStep.blocks);
      c.back();
      expect(c.current, SiteSetupStep.siteInfo);
      expect(c.isFirst, isTrue);
      c.back();
      expect(c.current, SiteSetupStep.siteInfo);
      c.dispose();
    });

    test('atlanan adım sonradan tamamlanınca atlananlardan çıkar (kişi eklendi, durum yenilendi)', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      c.skip();
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.skipped);
      auth.peopleJson[1] = pplPersonJson(1, 'Ayşe Yılmaz');
      await c.noteChanged();
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.done);
      expect(c.progress.skipped, isNot(contains(SiteSetupStep.people)));
      expect(c.dataChanged, isTrue, reason: 'çağıran sihirbaz kapanınca listeleri tazeler');
      c.dispose();
    });

    test('bir kez tamam gözlenen adım veri azalsa da geri açılmaz', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      expect(c.statusOf(SiteSetupStep.blocks), SiteSetupStatus.done);
      auth.blockCount = 0;
      await c.refresh();
      expect(c.snapshot.blockCount, 0);
      expect(c.statusOf(SiteSetupStep.blocks), SiteSetupStatus.done);
      c.dispose();
    });
  });

  group('yarım kalma ve devam', () {
    test('kapatılıp yeniden açılan sihirbaz kalınan adımdan, atlananlarla birlikte sürer', () async {
      final auth = SetupWizardFakeAuth();
      final first = _controller(auth, store);
      await first.start();
      first.skip(); // Kişiler atlandı -> Modüller
      first.next(); // Modüller onaylandı -> Finans
      expect(first.current, SiteSetupStep.finance);
      await Future<void>.delayed(Duration.zero);
      first.dispose(); // kullanıcı çıktı

      final second = _controller(auth, store);
      await second.start();
      expect(second.current, SiteSetupStep.finance, reason: 'kalınan adımdan devam');
      expect(second.statusOf(SiteSetupStep.people), SiteSetupStatus.skipped);
      expect(second.statusOf(SiteSetupStep.modules), SiteSetupStatus.done);
      expect(second.showingSummary, isFalse);
      second.dispose();
    });

    test('kullanıcı geri dönüp bir adımda kaldıysa o adımdan devam eder (ilk açık adıma atlamaz)', () async {
      final auth = SetupWizardFakeAuth();
      final first = _controller(auth, store);
      await first.start();
      first.goTo(SiteSetupStep.blocks);
      await Future<void>.delayed(Duration.zero);
      first.dispose();
      final second = _controller(auth, store);
      await second.start();
      expect(second.current, SiteSetupStep.blocks);
      second.dispose();
    });

    test('Panel hatırlatması için açılan ilk kayıt (started=false) sihirbazı sıradaki yapılacak adımdan başlatır', () async {
      final auth = SetupWizardFakeAuth();
      await store.ensure(_userId, 11, siteName: 'Gül Sitesi');
      final c = _controller(auth, store);
      await c.start();
      expect(c.current, SiteSetupStep.people, reason: 'kayıtlı ilk adım (Site bilgileri) tamam; ilk açık adım');
      c.dispose();
    });

    test('başka cihazda yapılan iş sayılır: kayıt eski olsa da sunucu verisi tamamlananı işler', () async {
      final auth = SetupWizardFakeAuth()..peopleJson[1] = pplPersonJson(1, 'Ayşe Yılmaz');
      await store.save(_userId, const SiteSetupProgress(siteCode: 11, current: SiteSetupStep.people, started: true));
      final c = _controller(auth, store);
      await c.start();
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.done);
      expect(c.current, SiteSetupStep.people, reason: 'kalınan yer korunur; Devam ile sürer');
      expect(c.canContinue, isTrue);
      c.dispose();
    });

    test('bitirilen kurulum yeniden açılınca özet gösterilir; reopen ilk açık adıma döner', () async {
      final auth = SetupWizardFakeAuth();
      final first = _controller(auth, store);
      await first.start();
      await first.finish();
      expect(first.progress.finished, isTrue);
      expect((await store.load(_userId, 11))!.finished, isTrue);
      expect((await store.nextUnfinished(_userId)), isNull, reason: 'Panel hatırlatması kalkar');
      first.dispose();

      final second = _controller(auth, store);
      await second.start();
      expect(second.showingSummary, isTrue);
      second.reopen();
      expect(second.showingSummary, isFalse);
      expect(second.progress.finished, isFalse);
      expect(second.current, SiteSetupStep.people);
      second.dispose();
    });

    test('her adımı tamam olan kurulum doğrudan özetle açılır', () async {
      final auth = SetupWizardFakeAuth()
        ..peopleJson[1] = pplPersonJson(1, 'Ayşe Yılmaz')
        ..definitions[1] = finDefinition(1);
      await store.save(
        _userId,
        const SiteSetupProgress(siteCode: 11, done: {SiteSetupStep.modules}, started: true, current: SiteSetupStep.finance),
      );
      final c = _controller(auth, store);
      await c.start();
      expect(c.progress.isComplete, isTrue);
      expect(c.showingSummary, isTrue);
      c.dispose();
    });
  });

  group('dürüst hata durumu', () {
    test('site yapısı okunamazsa üç adım "durum alınamadı" olur; tamam SAYILMAZ, Devam kilitlenmez', () async {
      final auth = SetupWizardFakeAuth()..structureError = 'Bu islem icin site yonetim yetkisi gerekir.';
      final c = _controller(auth, store);
      await c.start();
      expect(c.snapshot.structure, isNull);
      expect(c.snapshot.structureError, isNotNull);
      for (final step in <SiteSetupStep>[SiteSetupStep.siteInfo, SiteSetupStep.blocks, SiteSetupStep.apartments]) {
        expect(c.statusOf(step), SiteSetupStatus.unknown, reason: step.name);
        expect(c.progress.isDone(step), isFalse, reason: 'hata adımı kendiliğinden tamamlamaz');
      }
      c.goTo(SiteSetupStep.blocks);
      expect(c.canContinue, isTrue, reason: 'durumu okunamayan adımda kullanıcı kilitlenmez');
      expect(c.canSkip, isTrue);
      c.dispose();
    });

    test('kişi sayısı okunamazsa "0 kişi" DENMEZ: sayı null, adım bilinmiyor', () async {
      final auth = SetupWizardFakeAuth()..peopleError = ApiException('Kişiler alınamadı.', statusCode: 500);
      final c = _controller(auth, store);
      await c.start();
      expect(c.snapshot.peopleCount, isNull);
      expect(c.snapshot.peopleError, 'Kişiler alınamadı.');
      expect(c.statusOf(SiteSetupStep.people), SiteSetupStatus.unknown);
      c.dispose();
    });

    test('modül ve aidat hataları yalnız kendi adımlarını etkiler; "Tekrar Dene" (refresh) onarır', () async {
      final auth = SetupWizardFakeAuth()
        ..modulesError = ApiException('Modüller alınamadı.', statusCode: 500)
        ..definitionsError = ApiException('Tanımlar alınamadı.', statusCode: 500);
      final c = _controller(auth, store);
      await c.start();
      expect(c.statusOf(SiteSetupStep.modules), SiteSetupStatus.unknown);
      expect(c.statusOf(SiteSetupStep.finance), SiteSetupStatus.unknown);
      expect(c.statusOf(SiteSetupStep.blocks), SiteSetupStatus.done, reason: 'başka adımlar etkilenmez');
      auth
        ..modulesError = null
        ..definitionsError = null;
      await c.refresh();
      expect(c.statusOf(SiteSetupStep.modules), SiteSetupStatus.open);
      expect(c.statusOf(SiteSetupStep.finance), SiteSetupStatus.open);
      c.dispose();
    });

    test('art arda yenilemede en son başlayan yükleme kazanır ve yükleme göstergesi kapanır', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      await c.start();
      final first = c.refresh();
      auth.blockCount = 4;
      final second = c.refresh();
      await Future.wait(<Future<void>>[first, second]);
      expect(c.loading, isFalse);
      expect(c.snapshot.blockCount, 4);
      c.dispose();
    });

    test('dispose sonrası gelen yanıt yok sayılır (hata fırlatmaz)', () async {
      final auth = SetupWizardFakeAuth();
      final c = _controller(auth, store);
      final starting = c.start();
      c.dispose();
      await starting;
      expect(c.started, isFalse);
    });
  });
}
