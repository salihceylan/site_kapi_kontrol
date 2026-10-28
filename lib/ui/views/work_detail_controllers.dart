// İş Takibi ayrıntı pencerelerinin denetleyicileri (sakin ve yönetim). Ekran yalnız çizer; yükleme, "görüldü"
// işareti, yorum, iptal ve güncelleme akışları ve hata sınıflandırması burada durur (birim testi ekransız yapılır).
//
// Kurallar:
// - Rol / yetki kararını SUNUCU verir; denetleyici 403 / 404 / 409 yanıtlarını düz Türkçe mesaja çevirip durum
//   bayraklarına ([moduleClosed], [gone]) işler. Yazma istekleri otomatik yeniden DENENMEZ.
// - Yarış: her yükleme `_token` ile numaralanır; eski yanıt yeni durumu ezmez. [dispose] sonrası yanıt yok sayılır.
// - Yazma hatasında metin ve seçimler KORUNUR (çağıran yeniden dener; idempotency anahtarı serviste aynı kalır).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;

const String _loadFallback =
    'Talep yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';

List<WorkEvent> _mergeEvents(List<WorkEvent> events, WorkEvent added) {
  final merged = <WorkEvent>[
    for (final event in events)
      if (event.id != added.id) event,
    added,
  ]..sort((a, b) => a.id.compareTo(b.id));
  return List<WorkEvent>.unmodifiable(merged);
}

List<WorkAttachment> _mergeAttachments(
  List<WorkAttachment> attachments,
  WorkAttachment added,
) {
  final merged = <WorkAttachment>[
    for (final attachment in attachments)
      if (attachment.id != added.id) attachment,
    added,
  ]..sort((a, b) => a.id.compareTo(b.id));
  return List<WorkAttachment>.unmodifiable(merged);
}

List<WorkAttachment> _withoutAttachment(List<WorkAttachment> attachments, int id) =>
    List<WorkAttachment>.unmodifiable(attachments.where((a) => a.id != id));

/// Yükleme yanıtındaki uyarılar ayrıntıdakilerin yerine geçer (aynı fotoğrafın eski uyarısı atılır); uyarısız yükleme
/// mevcut listeyi değiştirmez.
List<WorkPhotoWarning> _mergeWarnings(List<WorkPhotoWarning> warnings, WorkAttachment added) {
  if (added.photoWarnings.isEmpty) return warnings;
  return List<WorkPhotoWarning>.unmodifiable(<WorkPhotoWarning>[
    for (final warning in warnings)
      if (warning.attachmentId != added.id) warning,
    ...added.photoWarnings,
  ]);
}

List<WorkPhotoWarning> _withoutWarningsOf(List<WorkPhotoWarning> warnings, int attachmentId) =>
    List<WorkPhotoWarning>.unmodifiable(warnings.where((w) => w.attachmentId != attachmentId));

const String _deleteFallback =
    'Fotoğraf silinemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';

/// Sakin talep ayrıntısı: yükleme (+ "görüldü"), fotoğraf ekleri, yorum, kendi `yeni` talebini iptal.
class WorkResidentDetailController extends ChangeNotifier {
  WorkResidentDetailController({
    required this.service,
    required WorkResidentItem initial,
  }) : item = initial;

  final WorkTrackingService service;

  WorkResidentItem item;
  List<WorkEvent> events = const <WorkEvent>[];
  List<WorkAttachment> attachments = const <WorkAttachment>[];

  bool loading = false;
  bool loaded = false;
  bool busy = false;

  /// Ayrıntı yüklenemedi (özet kart yine görünür; "Tekrar Dene" çizilir).
  String? loadError;

  /// Son yazma isteğinin hatası (form içinde gösterilir).
  String? actionError;

  /// Fotoğraf silme hatası (ek bölümünde gösterilir).
  String? attachmentError;

  /// Son hata nesnesi (çağıran 429 için `RetryLock` kurar).
  Object? lastError;

  /// 403 `MODULE_DISABLED`: modül bu site için kapatılmış.
  bool moduleClosed = false;

  /// 404: talep artık yok / erişim yok (liste yenilenmeli).
  bool gone = false;

  /// Liste yeniden çekilmeli (durum, yorum, görüldü ya da iptal değişti).
  bool changed = false;

  /// Başarılı her ayrıntı yüklemesinde artar (ekran "bir sonraki yüklemeye dek" kararlarını buna bağlar).
  int loadGeneration = 0;

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
      if (error.statusCode == 404 || error.code == 'WORK_ITEM_NOT_FOUND') {
        gone = true;
        changed = true;
      }
    }
  }

  /// Ayrıntıyı çeker. [silent] true: yükleme göstergesi / hata kutusu açılmaz (eylem sonrası tazeleme).
  Future<void> load({bool silent = false}) async {
    final token = ++_token;
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      final detail = await service.getMine(item.id);
      if (_disposed || token != _token) return;
      final wasUnread = detail.item.unread;
      item = detail.item;
      events = detail.events;
      attachments = detail.attachments;
      loadGeneration++;
      loaded = true;
      loading = false;
      loadError = null;
      gone = false;
      moduleClosed = false;
      notifyListeners();
      if (wasUnread) unawaited(_markSeen());
    } catch (e) {
      if (_disposed || token != _token) return;
      _classify(e);
      loading = false;
      if (!silent) loadError = crmMessageOf(e, _loadFallback);
      lastError = e;
      notifyListeners();
    }
  }

  /// "Görüldü" işareti: başarısızlık sessizdir (yalnız rozet kalır; sonraki açılışta yeniden denenir).
  Future<void> _markSeen() async {
    try {
      await service.markSeen(item.id);
      if (_disposed) return;
      item = item.copyWith(unread: false);
      changed = true;
      notifyListeners();
    } catch (_) {
      // Görüldü işareti yardımcıdır; kullanıcıya hata gösterilmez.
    }
  }

  /// Herkese açık yorum ekler. Başarıda true. Talep bu arada kapandıysa ayrıntı tazelenir.
  Future<bool> comment(String text) async {
    if (busy) return false;
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final event = await service.commentMine(item.id, text);
      if (_disposed) return true;
      events = _mergeEvents(events, event);
      changed = true;
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      _failAction(e, 'Yorum kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      return false;
    }
  }

  /// Kendi `yeni` talebini iptal eder. Başarıda true.
  Future<bool> cancel() async {
    if (busy) return false;
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final updated = await service.cancelMine(item.id);
      if (_disposed) return true;
      item = updated;
      changed = true;
      busy = false;
      notifyListeners();
      // Durum olayı sunucuda eklendi: çizgi tazelenir (hata sessiz).
      unawaited(load(silent: true));
      return true;
    } catch (e) {
      if (_disposed) return false;
      _failAction(e, 'Talep iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      return false;
    }
  }

  void _failAction(Object error, String fallback) {
    _classify(error);
    busy = false;
    lastError = error;
    actionError = crmMessageOf(error, fallback);
    notifyListeners();
    // Durum değişmiş olabilir (409 kapandı / geçersiz geçiş): görünür durum sunucuyla eşitlenir.
    if (error is ApiException && error.statusCode == 409) {
      unawaited(load(silent: true));
    }
  }

  // --- Fotoğraf ekleri ---

  /// Talep açıkken ve sınırın altındayken fotoğraf eklenebilir (sunucu yine de doğrular).
  bool get canAddAttachment =>
      loaded && !item.status.isTerminal && attachments.length < kWorkAttachmentMax;

  /// Sakin yalnız KENDİ yüklediği fotoğrafı, talep açıkken siler.
  bool canDeleteAttachment(WorkAttachment attachment) =>
      loaded && attachment.uploadedByMe && !item.status.isTerminal;

  /// Yüklenen ek listeye girer (aynı kimlik varsa yenisi geçer); liste yenilenmeli işaretlenir.
  void addAttachment(WorkAttachment attachment) {
    attachments = _mergeAttachments(attachments, attachment);
    item = item.copyWith(attachmentCount: _readyCount(attachments));
    attachmentError = null;
    changed = true;
    notifyListeners();
  }

  /// Fotoğrafı siler. Başarıda true. 404 ek yok (`WORK_ATTACHMENT_NOT_FOUND`): yerelden düşer ve durum sunucuyla
  /// sessizce eşitlenir; talep yok (`WORK_ITEM_NOT_FOUND`): [gone].
  Future<bool> deleteAttachment(WorkAttachment attachment) async {
    if (busy) return false;
    busy = true;
    attachmentError = null;
    notifyListeners();
    try {
      await service.deleteAttachment(id: item.id, attachmentId: attachment.id);
      if (_disposed) return true;
      _removeAttachment(attachment.id);
      busy = false;
      changed = true;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      busy = false;
      lastError = e;
      attachmentError = crmMessageOf(e, _deleteFallback);
      if (_attachmentGone(e)) {
        _removeAttachment(attachment.id);
        changed = true;
        unawaited(load(silent: true));
      } else {
        _classify(e);
        if (e is ApiException && e.statusCode == 409) unawaited(load(silent: true));
      }
      notifyListeners();
      return false;
    }
  }

  void _removeAttachment(int id) {
    attachments = _withoutAttachment(attachments, id);
    item = item.copyWith(attachmentCount: _readyCount(attachments));
  }
}

/// `attachment_count` yalnız HAZIR fotoğrafları sayar (sunucu ile aynı).
int _readyCount(List<WorkAttachment> attachments) =>
    attachments.where((a) => a.isReady).length;

/// 404 eki gösterir (talep değil): ek zaten silinmiş.
bool _attachmentGone(Object error) =>
    error is ApiException &&
    error.statusCode == 404 &&
    error.code != 'WORK_ITEM_NOT_FOUND';

/// Yönetim talep ayrıntısı (yönetici / görevli / kurul): yükleme, atanabilir kişiler, güncelleme, yorum, fotoğraf
/// ekleri.
class WorkManagerDetailController extends ChangeNotifier {
  WorkManagerDetailController({
    required this.service,
    required this.siteCode,
    required this.canWrite,
    required WorkManagedItem initial,
    this.access = WorkSiteAccess.manager,
  }) : item = initial;

  final WorkTrackingService service;
  final int siteCode;

  /// Yazma düğmeleri çizilir mi (kurul: false). Yetkinin tek kaynağı yine sunucudur.
  final bool canWrite;

  /// Erişim türü: yönetici her fotoğrafı, görevli yalnız kendi yüklediğini siler; kurul hiçbirini.
  final WorkSiteAccess access;

  WorkManagedItem item;
  List<WorkEvent> events = const <WorkEvent>[];
  List<WorkStatus> nextStatuses = const <WorkStatus>[];
  List<WorkAssignee> assignees = const <WorkAssignee>[];

  /// Talebe bağlanabilecek aktif ekipmanlar ("Ekipman" seçicisi; yalnız yazma yetkisinde yüklenir).
  List<WorkEquipmentRef> equipment = const <WorkEquipmentRef>[];
  List<WorkAttachment> attachments = const <WorkAttachment>[];

  /// Fotoğraf yeniden kullanım uyarıları (yalnız uyarı; sunucudan: ayrıntı + yükleme yanıtı).
  List<WorkPhotoWarning> photoWarnings = const <WorkPhotoWarning>[];

  bool loading = false;
  bool loaded = false;
  bool busy = false;
  bool assigneesLoaded = false;
  bool equipmentLoaded = false;
  String? loadError;
  String? assigneesError;
  String? equipmentError;
  String? actionError;

  /// Fotoğraf silme hatası (ek bölümünde gösterilir).
  String? attachmentError;
  Object? lastError;
  bool moduleClosed = false;
  bool gone = false;
  bool changed = false;

  /// Başarılı her ayrıntı yüklemesinde / güncellemesinde artar (ekran "bir sonraki yüklemeye dek" kararları için).
  int loadGeneration = 0;

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
      if (error.statusCode == 404 || error.code == 'WORK_ITEM_NOT_FOUND') {
        gone = true;
        changed = true;
      }
    }
  }

  void _apply(WorkManagedDetail detail) {
    item = detail.item;
    events = detail.events;
    nextStatuses = detail.nextStatuses;
    attachments = detail.attachments;
    photoWarnings = detail.photoWarnings;
    loadGeneration++;
    loaded = true;
    gone = false;
    moduleClosed = false;
  }

  // --- Fotoğraf ekleri ---

  /// Yazma yetkisi varken, talep açıkken ve sınırın altındayken fotoğraf eklenebilir (kurul: asla).
  bool get canAddAttachment =>
      canWrite &&
      loaded &&
      !item.status.isTerminal &&
      attachments.length < kWorkAttachmentMax;

  /// Yönetici / süper her fotoğrafı, KAPANMIŞ ya da iptal edilmiş talepte de siler; görevli yalnız kendi yüklediğini ve
  /// yalnız açık talepte (kapalıda sunucu 409 `INVALID_STATE`); kurul hiçbirini.
  bool canDeleteAttachment(WorkAttachment attachment) {
    if (!canWrite || !loaded) return false;
    if (access == WorkSiteAccess.manager) return true;
    return attachment.uploadedByMe && !item.status.isTerminal;
  }

  void addAttachment(WorkAttachment attachment) {
    attachments = _mergeAttachments(attachments, attachment);
    photoWarnings = _mergeWarnings(photoWarnings, attachment);
    attachmentError = null;
    changed = true;
    notifyListeners();
  }

  /// Fotoğrafı siler. Başarıda true. 404 ek yok (`WORK_ATTACHMENT_NOT_FOUND`): yerelden düşer ve durum sunucuyla
  /// sessizce eşitlenir; talep yok / görünmüyor (`WORK_ITEM_NOT_FOUND`): [gone].
  Future<bool> deleteAttachment(WorkAttachment attachment) async {
    if (busy) return false;
    busy = true;
    attachmentError = null;
    notifyListeners();
    try {
      await service.deleteAttachment(
        siteCode: siteCode,
        id: item.id,
        attachmentId: attachment.id,
      );
      if (_disposed) return true;
      attachments = _withoutAttachment(attachments, attachment.id);
      photoWarnings = _withoutWarningsOf(photoWarnings, attachment.id);
      busy = false;
      changed = true;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      busy = false;
      lastError = e;
      attachmentError = crmMessageOf(e, _deleteFallback);
      if (_attachmentGone(e)) {
        attachments = _withoutAttachment(attachments, attachment.id);
        photoWarnings = _withoutWarningsOf(photoWarnings, attachment.id);
        changed = true;
        unawaited(load(silent: true));
      } else {
        _classify(e);
        if (e is ApiException && e.statusCode == 409) unawaited(load(silent: true));
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> load({bool silent = false}) async {
    final token = ++_token;
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      final detail = await service.getManaged(siteCode, item.id);
      if (_disposed || token != _token) return;
      _apply(detail);
      loading = false;
      loadError = null;
      notifyListeners();
    } catch (e) {
      if (_disposed || token != _token) return;
      _classify(e);
      loading = false;
      if (!silent) loadError = crmMessageOf(e, _loadFallback);
      lastError = e;
      notifyListeners();
    }
  }

  /// Atanabilir kişileri çeker (yalnız yazma yetkisinde). Hata ekranı bozmaz: atama listesi boş kalır ve
  /// "Tekrar Dene" için [assigneesError] dolar.
  Future<void> loadAssignees() async {
    if (!canWrite) return;
    try {
      final list = await service.assignees(siteCode);
      if (_disposed) return;
      assignees = list;
      assigneesLoaded = true;
      assigneesError = null;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      assigneesError = crmMessageOf(
        e,
        'Atanabilir kişiler yüklenemedi. Tekrar deneyin.',
      );
      notifyListeners();
    }
  }

  /// Talebe bağlanabilecek aktif ekipmanları çeker (yalnız yazma yetkisinde). Hata ekranı bozmaz: seçici yalnız
  /// "Seçilmedi" (ve varsa mevcut ekipman) ile kalır ve "Tekrar Dene" için [equipmentError] dolar.
  Future<void> loadEquipment() async {
    if (!canWrite) return;
    try {
      final list = await service.equipmentChoices(siteCode);
      if (_disposed) return;
      equipment = list;
      equipmentLoaded = true;
      equipmentError = null;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      equipmentError = crmMessageOf(
        e,
        'Ekipman listesi yüklenemedi. Tekrar deneyin.',
      );
      notifyListeners();
    }
  }

  /// Durum / öncelik / atama / hedef tarih / ekipman güncellemesi ([fields] yalnız değişenleri taşır). Başarıda true.
  Future<bool> save(Map<String, Object?> fields) async {
    if (busy || fields.isEmpty) return false;
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final detail = await service.updateManaged(siteCode, item.id, fields);
      if (_disposed) return true;
      _apply(detail);
      changed = true;
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      _failAction(e, 'Talep güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      return false;
    }
  }

  /// Yorum ekler: [internal] true iç not (yalnız yönetim), false sakine görünür. Başarıda true.
  Future<bool> comment(String text, {required bool internal}) async {
    if (busy) return false;
    busy = true;
    actionError = null;
    notifyListeners();
    try {
      final event = await service.commentManaged(
        siteCode,
        item.id,
        text,
        internal: internal,
      );
      if (_disposed) return true;
      events = _mergeEvents(events, event);
      changed = true;
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      _failAction(e, 'Yorum kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      return false;
    }
  }

  void _failAction(Object error, String fallback) {
    _classify(error);
    busy = false;
    lastError = error;
    actionError = crmMessageOf(error, fallback);
    notifyListeners();
    // 409 (geçersiz geçiş / kapandı): izin verilen geçişler ve durum sunucuyla eşitlenir.
    if (error is ApiException && error.statusCode == 409) {
      unawaited(load(silent: true));
    }
  }
}
