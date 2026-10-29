import 'package:flutter/foundation.dart';

/// Site kurulum sihirbazının adımları (P2-15). Sıra sabittir: ilerleme kaydı adımı DİZİNLE değil ADIYLA saklar, bu
/// yüzden ileride araya adım eklenirse eski kayıtlar bozulmaz.
enum SiteSetupStep {
  /// Site adı, yönetim türü, il / ilçe, adres.
  siteInfo,

  /// Blok adları ve blok başına daire sayıları.
  blocks,

  /// Daire kayıtları (kat, tip, arsa payı ...).
  apartments,

  /// Kişiler (Excel'den yükle ya da tek tek).
  people,

  /// Modül seçimi (temel modüller her sitede açıktır).
  modules,

  /// Finans açılışı (aidat tanımı, devir bakiyesi).
  finance;

  /// Kullanıcıya görünen varsayılan başlık (site türüne göre terimler ekranda değişir: Blok -> Kat, Daire -> Ofis).
  String get label => switch (this) {
    SiteSetupStep.siteInfo => 'Site bilgileri',
    SiteSetupStep.blocks => 'Bloklar',
    SiteSetupStep.apartments => 'Daireler',
    SiteSetupStep.people => 'Kişiler',
    SiteSetupStep.modules => 'Modüller',
    SiteSetupStep.finance => 'Finans açılışı',
  };

  /// Saklanan ad -> adım; bilinmeyen / bozuk değerde null (eski ya da bozuk kayıt sessizce yok sayılır).
  static SiteSetupStep? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final step in values) {
      if (step.name == raw) return step;
    }
    return null;
  }
}

/// Bir sitenin kurulum sihirbazındaki ilerlemesi (P2-15): hangi adımda kalındı, hangileri tamam, hangileri atlandı.
///
/// DEĞİŞMEZ değerdir; her işlem yeni nesne döner. Saklama [SiteSetupProgressStore]'dadır (cihazda, kullanıcı ve site
/// başına). `done` kümesi hem kullanıcının onayladığı hem sunucu verisinden GÖZLENEN tamamlanmışları içerir
/// (örn. sitede blok varsa "Bloklar" tamam): böylece başka cihazda yapılan iş de sayılır ve Panel hatırlatması
/// ağ isteği yapmadan "3 / 6 adım" diyebilir.
@immutable
class SiteSetupProgress {
  const SiteSetupProgress({
    required this.siteCode,
    this.siteName = '',
    this.current = SiteSetupStep.siteInfo,
    this.done = const <SiteSetupStep>{},
    this.skipped = const <SiteSetupStep>{},
    this.started = false,
    this.finished = false,
    this.dismissed = false,
    this.updatedAt,
  });

  final int siteCode;

  /// Hatırlatma kartında gösterilen site adı (kayıt anındaki ad).
  final String siteName;

  /// Kalınan adım.
  final SiteSetupStep current;

  /// Tamamlanan adımlar (onaylanan ya da sunucu verisinden gözlenen).
  final Set<SiteSetupStep> done;

  /// Kullanıcının "Atla" dediği adımlar (tamamlanınca buradan çıkar).
  final Set<SiteSetupStep> skipped;

  /// Sihirbaz sayfası bu site için en az bir kez açıldı. Hatırlatma için açılan ilk kayıt (site yeni kuruldu ya da
  /// başvurusu onaylandı) henüz AÇILMAMIŞTIR: ilk açılışta kalınan adım kayıttan değil, sıradaki yapılacak
  /// adımdan başlar.
  final bool started;

  /// Sihirbaz sonuna kadar yürütüldü ("Kurulumu bitir").
  final bool finished;

  /// Kullanıcı hatırlatmayı kapattı; sihirbaz yine de elle açılabilir.
  final bool dismissed;

  final DateTime? updatedAt;

  static const int stepCount = 6;

  bool isDone(SiteSetupStep step) => done.contains(step);
  bool isSkipped(SiteSetupStep step) => skipped.contains(step) && !done.contains(step);

  /// Tamamlanmış ya da bilerek atlanmış (kullanıcı bu adım için karar verdi).
  bool isSettled(SiteSetupStep step) => isDone(step) || skipped.contains(step);

  int get doneCount => SiteSetupStep.values.where(isDone).length;

  /// Her adım tamam (atlanan yok).
  bool get isComplete => SiteSetupStep.values.every(isDone);

  /// Sihirbazın kullanıcıya hâlâ önerilmesi gereken hâli (hatırlatma kartı bunu kullanır).
  bool get needsAttention => !finished && !dismissed && !isComplete;

  /// Sıradaki yapılacak adım: önce hiç dokunulmamış ilk adım, sonra atlanan ilk adım; hepsi tamamsa null.
  SiteSetupStep? get firstOpen {
    for (final step in SiteSetupStep.values) {
      if (!isSettled(step)) return step;
    }
    for (final step in SiteSetupStep.values) {
      if (!isDone(step)) return step;
    }
    return null;
  }

  /// Adım sırası bir adım ileri (son adımda null).
  static SiteSetupStep? after(SiteSetupStep step) {
    final next = step.index + 1;
    return next < SiteSetupStep.values.length ? SiteSetupStep.values[next] : null;
  }

  /// Adım sırası bir adım geri (ilk adımda null).
  static SiteSetupStep? before(SiteSetupStep step) {
    final previous = step.index - 1;
    return previous >= 0 ? SiteSetupStep.values[previous] : null;
  }

  SiteSetupProgress copyWith({
    String? siteName,
    SiteSetupStep? current,
    Set<SiteSetupStep>? done,
    Set<SiteSetupStep>? skipped,
    bool? started,
    bool? finished,
    bool? dismissed,
    DateTime? updatedAt,
  }) {
    return SiteSetupProgress(
      siteCode: siteCode,
      siteName: siteName ?? this.siteName,
      current: current ?? this.current,
      done: done ?? this.done,
      skipped: skipped ?? this.skipped,
      started: started ?? this.started,
      finished: finished ?? this.finished,
      dismissed: dismissed ?? this.dismissed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Kalınan adımı değiştirir.
  SiteSetupProgress moveTo(SiteSetupStep step, {DateTime? at}) =>
      copyWith(current: step, updatedAt: at);

  /// Adımı tamamlandı yapar (atlanmışsa atlanandan çıkar).
  SiteSetupProgress markDone(SiteSetupStep step, {DateTime? at}) {
    if (done.contains(step) && !skipped.contains(step)) return this;
    return copyWith(
      done: <SiteSetupStep>{...done, step},
      skipped: <SiteSetupStep>{...skipped}..remove(step),
      updatedAt: at,
    );
  }

  /// Adımı atlandı yapar (tamamlanmış bir adım atlanmış SAYILMAZ).
  SiteSetupProgress markSkipped(SiteSetupStep step, {DateTime? at}) {
    if (done.contains(step) || skipped.contains(step)) return this;
    return copyWith(skipped: <SiteSetupStep>{...skipped, step}, updatedAt: at);
  }

  SiteSetupProgress markFinished({DateTime? at}) => copyWith(finished: true, updatedAt: at);

  /// Bitmiş / kapatılmış sihirbazı yeniden etkinleştirir (kullanıcı elle açtığında).
  SiteSetupProgress reopened({DateTime? at}) => copyWith(finished: false, dismissed: false, updatedAt: at);

  SiteSetupProgress markDismissed({DateTime? at}) => copyWith(dismissed: true, updatedAt: at);

  Map<String, Object?> toJson() => <String, Object?>{
    'site': siteCode,
    'name': siteName,
    'step': current.name,
    'done': <String>[for (final step in SiteSetupStep.values) if (done.contains(step)) step.name],
    'skipped': <String>[for (final step in SiteSetupStep.values) if (skipped.contains(step)) step.name],
    'started': started,
    'finished': finished,
    'dismissed': dismissed,
    'at': updatedAt?.toUtc().toIso8601String(),
  };

  /// Savunmacı ayrıştırma: site kodu yoksa null (kayıt kullanılamaz); öteki bozuk alanlar varsayılana düşer.
  static SiteSetupProgress? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final site = raw['site'];
    final siteCode = site is num ? site.toInt() : int.tryParse('$site');
    if (siteCode == null || siteCode <= 0) return null;
    Set<SiteSetupStep> steps(Object? list) => <SiteSetupStep>{
      if (list is List)
        for (final item in list)
          if (SiteSetupStep.tryParse(item) != null) SiteSetupStep.tryParse(item)!,
    };
    final name = raw['name'];
    final at = raw['at'];
    return SiteSetupProgress(
      siteCode: siteCode,
      siteName: name is String ? name : '',
      current: SiteSetupStep.tryParse(raw['step']) ?? SiteSetupStep.siteInfo,
      done: steps(raw['done']),
      skipped: steps(raw['skipped']),
      started: raw['started'] == true,
      finished: raw['finished'] == true,
      dismissed: raw['dismissed'] == true,
      updatedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SiteSetupProgress &&
      other.siteCode == siteCode &&
      other.siteName == siteName &&
      other.current == current &&
      setEquals(other.done, done) &&
      setEquals(other.skipped, skipped) &&
      other.started == started &&
      other.finished == finished &&
      other.dismissed == dismissed &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    siteCode,
    siteName,
    current,
    Object.hashAllUnordered(done),
    Object.hashAllUnordered(skipped),
    started,
    finished,
    dismissed,
    updatedAt,
  );
}
