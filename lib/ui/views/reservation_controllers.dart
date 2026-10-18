// Rezervasyon ve Konsiyerj pencerelerinin denetleyicileri. Ekran yalnız çizer; boş saat yükleme, seçim kuralları,
// rezervasyon gönderimi, karar verme ve konsiyerj durum güncellemesi ile hata sınıflandırması burada durur (birim
// testi ekransız yapılır).
//
// Kurallar:
// - Rol / yetki / kapasite kararını SUNUCU verir; denetleyici 403 / 404 / 409 yanıtlarını düz Türkçe mesaja çevirip
//   durum bayraklarına ([moduleClosed], [gone], [areaClosed]) işler. Yazma istekleri otomatik yeniden DENENMEZ.
// - Yarış: her yükleme `_token` ile numaralanır; eski yanıt yeni durumu ezmez. [dispose] sonrası yanıt yok sayılır.
// - Yazma hatasında seçimler ve metin KORUNUR (çağıran yeniden dener; idempotency anahtarı serviste aynı kalır).
// - Gün / saat hesabı İstanbul takvimiyle yapılır ([istanbulNow]); cihazın saat dilimi kullanılmaz.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;

int _clampInt(int value, int low, int high) =>
    value < low ? low : (value > high ? high : value);

const String _slotsFallback =
    'Boş saatler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';

/// Boş saat seçimi ve rezervasyon gönderimi (sakin "Rezervasyon Yap" penceresi).
///
/// Boş saatler 7 günlük pencerelerle gelir ([windowDays]); pencere 0 sunucunun varsayılanıdır (bugün ...), sonraki
/// pencereler İstanbul bugününden 7'şer gün ileridir. Seçim: gün -> başlangıç dilimi -> dilim sayısı. Seçilebilirlik
/// yalnız kolaylıktır (dolu dilim pasif, ardışık boş dilim sayısı kadar süre); asıl denetimi sunucu yapar ve
/// çakışma (409) olursa boş saatler yeniden çekilir.
class ReservationBookingController extends ChangeNotifier {
  ReservationBookingController({
    required this.service,
    required this.area,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReservationService service;
  final ReservationArea area;
  final DateTime Function() _clock;

  static const int windowDays = 7;

  ReservationAvailability? availability;
  int windowIndex = 0;

  bool loading = false;
  bool busy = false;

  /// Boş saatler yüklenemedi ("Tekrar Dene" çizilir).
  String? loadError;

  /// Son gönderimin hatası (form içinde gösterilir).
  String? actionError;

  /// Son hata nesnesi (çağıran 429 için `RetryLock` kurar).
  Object? lastError;

  /// 403 `MODULE_DISABLED`: modül bu site için kapatılmış.
  bool moduleClosed = false;

  /// 404 `AREA_NOT_FOUND` / 409 `AREA_INACTIVE`: alan artık rezerve edilemez.
  bool areaClosed = false;

  ReservationCreateResult? created;

  /// Seçili gün ("YYYY-MM-DD"), o günün dilim sırası ve dilim sayısı.
  String? selectedDate;
  int? selectedSlot;
  int slotCount = 1;

  int _token = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    ++_token;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // --- Pencere ---

  String _windowStart(int index) {
    final wall = istanbulNow(_clock());
    return crmDateParam(DateTime.utc(wall.year, wall.month, wall.day + windowDays * index));
  }

  /// Sorgunun `from` değeri; ilk pencerede null (sunucu "bugün" kullanır).
  String? get windowFrom => windowIndex == 0 ? null : _windowStart(windowIndex);

  bool get hasPreviousWindow => windowIndex > 0;

  /// Sonraki pencerenin ilk günü rezerve edilebilir son günü aşmıyorsa true.
  bool get hasNextWindow {
    final until = availability?.bookableUntil;
    if (until == null) return false;
    return _windowStart(windowIndex + 1).compareTo(until) <= 0;
  }

  Future<void> goToWindow(int delta) async {
    final next = windowIndex + delta;
    if (busy || next < 0 || next == windowIndex) return;
    windowIndex = next;
    selectedDate = null;
    selectedSlot = null;
    actionError = null;
    notifyListeners();
    await load();
  }

  void _classify(Object error) {
    if (error is ApiException) {
      if (error.code == 'MODULE_DISABLED') moduleClosed = true;
      if (error.code == 'AREA_NOT_FOUND' || error.code == 'AREA_INACTIVE') {
        areaClosed = true;
      }
    }
  }

  /// Boş saatleri çeker. [silent] true: yükleme göstergesi / hata kutusu açılmaz (çakışma sonrası tazeleme).
  Future<void> load({bool silent = false}) async {
    final token = ++_token;
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      final result = await service.availability(area.id, from: windowFrom);
      if (_disposed || token != _token) return;
      availability = result;
      loading = false;
      loadError = null;
      moduleClosed = false;
      areaClosed = false;
      _reconcileSelection();
      notifyListeners();
    } catch (e) {
      if (_disposed || token != _token) return;
      _classify(e);
      loading = false;
      if (!silent) loadError = crmMessageOf(e, _slotsFallback);
      lastError = e;
      notifyListeners();
    }
  }

  // --- Seçim ---

  List<AvailabilityDay> get days => availability?.days ?? const <AvailabilityDay>[];

  AvailabilityDay? get selectedDay {
    final date = selectedDate;
    if (date == null) return null;
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }

  List<AvailabilitySlot> get daySlots =>
      selectedDay?.slots ?? const <AvailabilitySlot>[];

  /// [index]'ten başlayan ardışık (bitişik) boş dilim sayısı.
  int maxRunFrom(int index) {
    final slots = daySlots;
    if (index < 0 || index >= slots.length) return 0;
    var run = 0;
    for (var i = index; i < slots.length; i++) {
      if (!slots[i].available) break;
      if (i > index && slots[i - 1].end != slots[i].start) break;
      run++;
    }
    return run;
  }

  /// [index]'teki dilim başlangıç olarak seçilebilir mi (boş ve en az `min_slots` ardışık boş dilim var)?
  bool isSelectable(int index) {
    final slots = daySlots;
    if (index < 0 || index >= slots.length) return false;
    return slots[index].available && maxRunFrom(index) >= area.minSlots;
  }

  /// [index]'ten başlayan seçilebilir en büyük dilim sayısı (`max_slots` ile sınırlı).
  int maxCountFrom(int index) => math.min(area.maxSlots, maxRunFrom(index));

  void _reconcileSelection() {
    final all = days;
    if (selectedDate != null && !all.any((day) => day.date == selectedDate)) {
      selectedDate = null;
      selectedSlot = null;
    }
    if (selectedDate == null && all.isNotEmpty) {
      var pick = all.first;
      for (final day in all) {
        if (day.slots.any((slot) => slot.available)) {
          pick = day;
          break;
        }
      }
      selectedDate = pick.date;
      selectedSlot = null;
    }
    final slot = selectedSlot;
    if (slot != null) {
      if (!isSelectable(slot)) {
        selectedSlot = null;
      } else {
        slotCount = _clampInt(slotCount, area.minSlots, math.max(area.minSlots, maxCountFrom(slot)));
      }
    }
  }

  void selectDate(String date) {
    if (busy || date == selectedDate) return;
    selectedDate = date;
    selectedSlot = null;
    actionError = null;
    notifyListeners();
  }

  void selectSlot(int index) {
    if (busy || !isSelectable(index)) return;
    selectedSlot = index;
    slotCount = _clampInt(area.minSlots, 1, math.max(1, maxCountFrom(index)));
    actionError = null;
    notifyListeners();
  }

  void setSlotCount(int count) {
    final slot = selectedSlot;
    if (busy || slot == null) return;
    final max = math.max(area.minSlots, maxCountFrom(slot));
    slotCount = _clampInt(count, area.minSlots, max);
    notifyListeners();
  }

  AvailabilitySlot? get startSlot {
    final slot = selectedSlot;
    final slots = daySlots;
    if (slot == null || slot < 0 || slot >= slots.length) return null;
    return slots[slot];
  }

  AvailabilitySlot? get endSlot {
    final slot = selectedSlot;
    final slots = daySlots;
    if (slot == null) return null;
    final last = slot + slotCount - 1;
    if (last < 0 || last >= slots.length) return null;
    return slots[last];
  }

  /// "20.10.2026 Salı · 18:00-20:00 (2 dilim, 2 saat)"; seçim yoksa null.
  String? get summary {
    final day = selectedDay;
    final start = startSlot;
    final end = endSlot;
    if (day == null || start == null || end == null) return null;
    final minutes = area.slotMinutes * slotCount;
    return '${day.longLabel} · ${start.start}-${end.end} ($slotCount dilim, ${reservationDurationText(minutes)})';
  }

  ReservationCreateRequest? buildRequest(String note) {
    final day = selectedDay;
    final start = startSlot;
    if (day == null || start == null) return null;
    return ReservationCreateRequest(
      siteCode: area.siteCode,
      areaId: area.id,
      date: day.date,
      start: start.start,
      slots: slotCount,
      note: note,
    );
  }

  /// Rezervasyonu gönderir. Başarıda true ([created] dolar). Hata durumunda seçim korunur; 409'da (dolu, saat dışı,
  /// limit ...) boş saatler sessizce tazelenir ve artık seçilemeyen dilim seçimden düşer.
  Future<bool> submit(String note) async {
    if (busy) return false;
    final request = buildRequest(note);
    if (request == null) {
      actionError = 'Önce bir gün ve saat seçin.';
      notifyListeners();
      return false;
    }
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final result = await service.createReservation(request);
      if (_disposed) return true;
      created = result;
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      _classify(e);
      busy = false;
      lastError = e;
      actionError = crmMessageOf(
        e,
        'Rezervasyon kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      notifyListeners();
      if (e is ApiException && e.statusCode == 409) unawaited(load(silent: true));
      return false;
    }
  }
}

/// Yönetim kararı (onay / ret / iptal) gönderimi.
class ReservationDecisionController extends ChangeNotifier {
  ReservationDecisionController({
    required this.service,
    required this.siteCode,
    required this.reservation,
  });

  final ReservationService service;
  final int siteCode;
  final ReservationRecord reservation;

  bool busy = false;
  String? actionError;
  Object? lastError;
  bool moduleClosed = false;

  /// 404: rezervasyon artık yok / erişim yok.
  bool gone = false;

  /// Liste yeniden çekilmeli (karar verildi ya da kayıt başkasınca değişti).
  bool changed = false;

  ReservationDecisionResult? result;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// [action]: `approve | reject | cancel`. Ret ve iptalde [note] (gerekçe) zorunludur. Başarıda true.
  Future<bool> submit(String action, String note) async {
    if (busy) return false;
    final trimmed = note.trim();
    if (action != 'approve' && trimmed.isEmpty) {
      actionError = 'Gerekçe zorunludur.';
      notifyListeners();
      return false;
    }
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final decided = await service.decide(
        siteCode,
        reservation.id,
        action: action,
        note: trimmed.isEmpty ? null : trimmed,
      );
      if (_disposed) return true;
      result = decided;
      changed = true;
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      if (e is ApiException) {
        if (e.code == 'MODULE_DISABLED') moduleClosed = true;
        if (e.statusCode == 404) gone = true;
        // 404 / 409: kayıt başkasınca değişmiş olabilir; liste kapanışta yenilenir.
        if (e.statusCode == 404 || e.statusCode == 409) changed = true;
      }
      busy = false;
      lastError = e;
      actionError = crmMessageOf(
        e,
        'Karar kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      notifyListeners();
      return false;
    }
  }
}

/// Yönetim konsiyerj talebi ayrıntısı (yönetici / görevli / kurul): yükleme, durum ilerletme, sakine görünür not.
class ConciergeManageController extends ChangeNotifier {
  ConciergeManageController({
    required this.service,
    required this.siteCode,
    required this.canWrite,
    required ConciergeRecord initial,
  }) : request = initial;

  final ReservationService service;
  final int siteCode;

  /// Yazma düğmeleri çizilir mi (kurul: false). Yetkinin tek kaynağı yine sunucudur.
  final bool canWrite;

  ConciergeRecord request;
  List<ConciergeStatus> nextStatuses = const <ConciergeStatus>[];

  bool loading = false;
  bool loaded = false;
  bool busy = false;
  String? loadError;
  String? actionError;
  Object? lastError;
  bool moduleClosed = false;
  bool gone = false;
  bool changed = false;

  int _token = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    ++_token;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _classify(Object error) {
    if (error is ApiException) {
      if (error.code == 'MODULE_DISABLED') moduleClosed = true;
      if (error.statusCode == 404 || error.code == 'CONCIERGE_NOT_FOUND') {
        gone = true;
        changed = true;
      }
    }
  }

  void _apply(ConciergeDetail detail) {
    request = detail.request;
    nextStatuses = detail.nextStatuses;
    loaded = true;
    gone = false;
    moduleClosed = false;
  }

  Future<void> load({bool silent = false}) async {
    final token = ++_token;
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      final detail = await service.getManagedRequest(siteCode, request.id);
      if (_disposed || token != _token) return;
      _apply(detail);
      loading = false;
      loadError = null;
      notifyListeners();
    } catch (e) {
      if (_disposed || token != _token) return;
      _classify(e);
      loading = false;
      if (!silent) {
        loadError = crmMessageOf(
          e,
          'Talep yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      }
      lastError = e;
      notifyListeners();
    }
  }

  /// Durum ve / veya sakine görünür not güncellemesi. [status] null: durum değişmez. [noteChanged] true: [note]
  /// gönderilir (boş ya da null = notu sil). Başarıda true.
  Future<bool> save({
    ConciergeStatus? status,
    bool noteChanged = false,
    String? note,
  }) async {
    if (busy) return false;
    final fields = <String, Object?>{};
    if (status != null && status != ConciergeStatus.unknown) {
      fields['status'] = status.apiValue;
    }
    if (noteChanged) {
      final trimmed = note?.trim() ?? '';
      fields['note'] = trimmed.isEmpty ? null : trimmed;
    }
    if (fields.isEmpty) return false;
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final detail = await service.updateManagedRequest(siteCode, request.id, fields);
      if (_disposed) return true;
      _apply(detail);
      changed = true;
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      _classify(e);
      busy = false;
      lastError = e;
      actionError = crmMessageOf(
        e,
        'Talep güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      notifyListeners();
      // 409 (kapandı / geçersiz geçiş): izin verilen geçişler ve durum sunucuyla eşitlenir.
      if (e is ApiException && e.statusCode == 409) {
        changed = true;
        unawaited(load(silent: true));
      }
      return false;
    }
  }
}
