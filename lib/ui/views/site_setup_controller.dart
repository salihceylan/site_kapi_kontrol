// Site kurulum sihirbazının durum makinesi (P2-15). Arayüzden bağımsızdır, birim testlenir.
//
// Sihirbaz MEVCUT ekranları yeniden yazmaz; adım kabuğudur. Bu denetleyici iki şeyi tutar:
// 1) sunucudan okunan durum özeti ([SiteSetupSnapshot]): sitenin bloğu / dairesi / kişisi / aidat tanımı var mı;
// 2) kullanıcının ilerlemesi ([SiteSetupProgress], [SiteSetupProgressStore] ile cihazda saklanır): kalınan adım,
//    tamamlananlar, atlananlar. "Yarım kalan kurulum devam eder": sihirbaz yeniden açılınca kalınan adımdan sürer.
//
// Kurallar:
// - HATA DÜRÜSTTÜR: bir parça yüklenemediyse o adım "durum alınamadı" olur; ASLA "yok / 0" gösterilmez ve adım
//   kendiliğinden tamam sayılmaz.
// - Sunucu verisinden GÖZLENEN tamamlanma ilerlemeye işlenir (başka cihazda yapılan iş de sayılır); bir kez tamam
//   gözlenen adım sonradan veri azalsa da geri alınmaz (yöneticinin tamamladığı adım yeniden açılmaz).
// - "Devam" yalnız tamamlanmış (ya da durumu bilinmeyen / yalnız onay isteyen) adımda, "Atla" tamamlanmamış adımda
//   vardır: atlanan adım özette "Atlandı" olarak kalır ve sonradan tamamlanabilir.
// - Yarış koruması: her yükleme bir sıra numarası alır; eski yanıt yenisini ezmez; dispose sonrası yanıt yok sayılır.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Bir adımın görünür durumu.
enum SiteSetupStatus {
  /// Tamamlandı (onaylandı ya da sunucu verisinden gözlendi).
  done,

  /// Kullanıcı atladı.
  skipped,

  /// Henüz yapılmadı.
  open,

  /// Durum sunucudan okunamadı (hata); "yok" DENMEZ.
  unknown,
}

/// Sihirbazın sunucudan okuduğu özet. Her parça AYRI yüklenir ve AYRI hata taşır.
@immutable
class SiteSetupSnapshot {
  const SiteSetupSnapshot({
    this.structure,
    this.structureError,
    this.peopleCount,
    this.peopleError,
    this.modules,
    this.modulesError,
    this.feeDefinitionCount,
    this.openPeriodLabel,
    this.financeError,
  });

  /// Site + bloklar + daireler + kapılar.
  final SiteStructureRecord? structure;
  final String? structureError;

  /// Aktif kişi sayısı.
  final int? peopleCount;
  final String? peopleError;

  /// Sitenin modül durumu (temel modüller `core`, önerilenler `recommended`).
  final SiteModulesState? modules;
  final String? modulesError;

  /// Aktif aidat / ek borç tanımı sayısı.
  final int? feeDefinitionCount;

  /// Kayıt eklenebilen açık dönemin etiketi (okunamadıysa null; bilgi amaçlıdır, hata sayılmaz).
  final String? openPeriodLabel;
  final String? financeError;

  /// Sitenin yönetim türü terimleri; okunamadıysa varsayılan.
  ManagementTerms get terms => structure?.site.managementTerms ?? ManagementTerms.defaults;

  int? get blockCount => structure?.blocks.length;
  int? get apartmentCount => structure?.apartments.length;

  /// Adım için sunucu verisinden tamamlanma bilgisi: true / false; veri okunamadıysa ya da adım sunucudan
  /// türetilemiyorsa (modüller: temel modüller her sitede zaten açıktır) null.
  bool? derivedDone(SiteSetupStep step) {
    switch (step) {
      case SiteSetupStep.siteInfo:
        return structure?.site.name.trim().isNotEmpty;
      case SiteSetupStep.blocks:
        return blockCount == null ? null : blockCount! > 0;
      case SiteSetupStep.apartments:
        return apartmentCount == null ? null : apartmentCount! > 0;
      case SiteSetupStep.people:
        return peopleCount == null ? null : peopleCount! > 0;
      case SiteSetupStep.modules:
        return null;
      case SiteSetupStep.finance:
        return feeDefinitionCount == null ? null : feeDefinitionCount! > 0;
    }
  }

  /// Adımın verisi okunamadıysa hata iletisi.
  String? errorOf(SiteSetupStep step) => switch (step) {
    SiteSetupStep.siteInfo || SiteSetupStep.blocks || SiteSetupStep.apartments => structureError,
    SiteSetupStep.people => peopleError,
    SiteSetupStep.modules => modulesError,
    SiteSetupStep.finance => financeError,
  };
}

class SiteSetupController extends ChangeNotifier {
  SiteSetupController({
    required this.authService,
    required this.siteCode,
    required this.userId,
    this.siteName = '',
    SiteSetupProgressStore? store,
    DateTime Function()? now,
  }) : store = store ?? SiteSetupProgressStore.shared,
       _now = now ?? DateTime.now,
       progress = SiteSetupProgress(siteCode: siteCode, siteName: siteName);

  final AuthService authService;
  final int siteCode;
  final int userId;
  final String siteName;
  final SiteSetupProgressStore store;
  final DateTime Function() _now;

  /// Kalınan adım, tamamlananlar, atlananlar (cihazda saklanır).
  SiteSetupProgress progress;

  SiteSetupSnapshot snapshot = const SiteSetupSnapshot();

  /// İlk yükleme (kayıt + sunucu özeti) bitti.
  bool started = false;

  /// Sunucu özeti okunuyor.
  bool loading = false;

  /// Özet ekranı (son adımdan sonra ya da bitmiş kurulumun yeniden açılışı) gösteriliyor.
  bool showingSummary = false;

  /// Bir alt akışta kayıtlar değişti (çağıran sihirbaz kapanınca listeleri tazeler).
  bool dataChanged = false;

  bool _disposed = false;
  bool _starting = false;
  int _loadToken = 0;

  /// Süren yükleme sayısı ([loading] = sayı > 0).
  int _active = 0;

  /// Yalnız site yöneticisi ve süper kullanıcı kurulum yapar.
  bool get isAllowed {
    final role = authService.session?.role;
    return role == UserRole.superUser || role == UserRole.siteManager;
  }

  bool get isSuperUser => authService.session?.role == UserRole.superUser;

  SiteSetupStep get current => progress.current;

  /// İlk adım mı / son adım mı.
  bool get isFirst => SiteSetupProgress.before(current) == null;
  bool get isLast => SiteSetupProgress.after(current) == null;

  /// Alt akışların (toplu yükleme, aidat tanımı, modüller ...) bağlamı. Sihirbaz yazma yetkisi olanlara açıktır.
  PeopleScope get scope => PeopleScope(
    authService: authService,
    siteCode: siteCode,
    siteName: snapshot.structure?.site.name ?? progress.siteName,
    canWrite: true,
    terms: snapshot.terms,
  );

  /// Kullanıcıya görünen site adı.
  String get displayName {
    final fromServer = snapshot.structure?.site.name.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    return progress.siteName.trim().isEmpty ? 'İsimsiz site' : progress.siteName.trim();
  }

  SiteSetupStatus statusOf(SiteSetupStep step) {
    if (progress.isDone(step)) return SiteSetupStatus.done;
    if (progress.isSkipped(step)) return SiteSetupStatus.skipped;
    if (snapshot.errorOf(step) != null) return SiteSetupStatus.unknown;
    return SiteSetupStatus.open;
  }

  /// "Devam" etkin mi: adım tamam, durumu okunamıyor (kullanıcı kilitlenmesin) ya da yalnız onay isteyen adım
  /// (modüller: temel modüller zaten açık, isteğe bağlı olanlar talep edilir; yapılacak zorunlu iş yok).
  bool get canContinue {
    if (loading && !started) return false;
    final status = statusOf(current);
    return status == SiteSetupStatus.done ||
        status == SiteSetupStatus.unknown ||
        current == SiteSetupStep.modules;
  }

  /// "Atla" yalnız tamamlanmamış adımda vardır.
  bool get canSkip => !progress.isDone(current);

  // --- Yaşam döngüsü ------------------------------------------------------------------------

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_loadToken;
    super.dispose();
  }

  /// Kayıtlı ilerlemeyi ve sunucu özetini okur; kalınan adımdan sürer. Bir kez çağrılır.
  Future<void> start() async {
    if (started || _starting) return;
    _starting = true;
    _active++;
    loading = true;
    notifyListeners();
    final stored = await store.load(userId, siteCode);
    if (_disposed) return;
    var next = stored ?? SiteSetupProgress(siteCode: siteCode, siteName: siteName, updatedAt: _now());
    if (siteName.trim().isNotEmpty && next.siteName.trim().isEmpty) next = next.copyWith(siteName: siteName);
    progress = next;
    await _loadSnapshot();
    if (_disposed) return;
    // Kalınan adım: sihirbaz bu site için önceden AÇILMIŞSA kaldığı yer; ilk açılışta sıradaki yapılacak adım.
    final step = progress.started ? progress.current : (progress.firstOpen ?? SiteSetupStep.siteInfo);
    // Bitmiş (ya da her adımı tamam) kurulum yeniden açılırsa özet gösterilir; adımlara oradan dönülür.
    final summary = progress.finished || progress.firstOpen == null;
    progress = progress.copyWith(current: step, started: true, updatedAt: _now());
    showingSummary = summary;
    started = true;
    _active--;
    loading = _active > 0;
    notifyListeners();
    _persist();
  }

  /// Sunucu özetini yeniden okur (alt akıştan dönünce, "Yenile", "Tekrar Dene"). Üst üste çağrılar güvenlidir:
  /// en son başlayan yükleme kazanır.
  Future<void> refresh() async {
    if (_disposed) return;
    _active++;
    loading = true;
    notifyListeners();
    await _loadSnapshot();
    if (_disposed) return;
    _active--;
    loading = _active > 0;
    notifyListeners();
    _persist();
  }

  /// Bir alt akışta kayıtlar değişti (ya da değişmiş olabilir): sihirbaz kapanınca çağıran tazeler; özet yenilenir.
  Future<void> noteChanged() {
    dataChanged = true;
    return refresh();
  }

  Future<void> _loadSnapshot() async {
    final token = ++_loadToken;
    final structureFuture = _guard<SiteStructureRecord>(() async {
      final (structure, error) = await authService.getSiteStructure(siteCode: siteCode);
      if (structure == null) throw StateError(error ?? 'Site bilgisi alınamadı.');
      return structure;
    });
    final peopleFuture = _guard<int>(() async {
      final page = await authService.listPeople(siteCode, status: 'active', limit: 1);
      return page.total;
    });
    final modulesFuture = _guard<SiteModulesState>(() => authService.getSiteModules(siteCode));
    final feesFuture = _guard<int>(() async {
      final items = await authService.listFeeDefinitions(siteCode, active: true);
      return items.length;
    });
    final periodFuture = _guard<String?>(() async {
      final periods = await authService.getFinancePeriods(siteCode);
      return periods.openPeriod?.label;
    });
    final structure = await structureFuture;
    final people = await peopleFuture;
    final modules = await modulesFuture;
    final fees = await feesFuture;
    final period = await periodFuture;
    if (_disposed || token != _loadToken) return;
    snapshot = SiteSetupSnapshot(
      structure: structure.value,
      structureError: structure.error == null ? null : _message(structure.error!, 'Site bilgileri alınamadı.'),
      peopleCount: people.value,
      peopleError: people.error == null ? null : _message(people.error!, 'Kişi sayısı alınamadı.'),
      modules: modules.value,
      modulesError: modules.error == null ? null : _message(modules.error!, 'Modüller alınamadı.'),
      feeDefinitionCount: fees.value,
      openPeriodLabel: period.value,
      financeError: fees.error == null ? null : _message(fees.error!, 'Aidat tanımları alınamadı.'),
    );
    _reconcile();
  }

  static String _message(Object error, String fallback) {
    if (error is StateError) return error.message.toString();
    return crmMessageOf(error, '$fallback İnternet bağlantınızı kontrol edip tekrar deneyin.');
  }

  /// Sunucudan gözlenen tamamlanmayı ilerlemeye işler (geri alınmaz).
  void _reconcile() {
    var next = progress;
    for (final step in SiteSetupStep.values) {
      if (snapshot.derivedDone(step) == true) next = next.markDone(step);
    }
    if (next != progress) progress = next.copyWith(updatedAt: _now());
  }

  Future<({T? value, Object? error})> _guard<T>(Future<T> Function() action) async {
    try {
      return (value: await action(), error: null);
    } catch (error) {
      return (value: null, error: error);
    }
  }

  // --- Gezinme -------------------------------------------------------------------------------

  void _set(SiteSetupProgress next, {bool? summary}) {
    progress = next.copyWith(updatedAt: _now());
    if (summary != null) showingSummary = summary;
    notifyListeners();
    _persist();
  }

  /// Belirli bir adıma gider (özetten "Aç" ya da başlıktan).
  void goTo(SiteSetupStep step) {
    _set(progress.moveTo(step), summary: false);
  }

  /// "Devam": adımı onaylar (yalnız onay isteyen adımda) ve sıradakine geçer; son adımda özete düşer.
  void next() {
    if (!canContinue) return;
    var updated = progress;
    if (current == SiteSetupStep.modules && !updated.isDone(current)) updated = updated.markDone(current);
    final following = SiteSetupProgress.after(current);
    if (following == null) {
      _set(updated, summary: true);
    } else {
      _set(updated.moveTo(following), summary: false);
    }
  }

  /// "Atla": tamamlanmamış adımı atlandı yapar ve sıradakine geçer; son adımda özete düşer.
  void skip() {
    if (!canSkip) return;
    final updated = progress.markSkipped(current);
    final following = SiteSetupProgress.after(current);
    if (following == null) {
      _set(updated, summary: true);
    } else {
      _set(updated.moveTo(following), summary: false);
    }
  }

  /// "Geri": önceki adıma döner; özetten son adıma döner.
  void back() {
    if (showingSummary) {
      _set(progress.moveTo(SiteSetupStep.values.last), summary: false);
      return;
    }
    final previous = SiteSetupProgress.before(current);
    if (previous == null) return;
    _set(progress.moveTo(previous), summary: false);
  }

  /// Adımı elle tamamlandı yapar (örn. kullanıcı "bunu başka yerde yaptım" der).
  void markDone(SiteSetupStep step) {
    _set(progress.markDone(step));
  }

  /// "Kurulumu bitir": ilerleme bitti olarak saklanır (Panel hatırlatması kalkar). Atlananlar özette kalır.
  Future<void> finish() async {
    progress = progress.markFinished(at: _now());
    showingSummary = true;
    notifyListeners();
    await store.save(userId, progress);
  }

  /// Bitmiş / kapatılmış kurulumu yeniden açar ve ilk tamamlanmamış adıma gider.
  void reopen() {
    final reopened = progress.reopened();
    _set(reopened.moveTo(reopened.firstOpen ?? SiteSetupStep.siteInfo), summary: false);
  }

  void _persist() {
    unawaited(store.save(userId, progress));
  }
}
