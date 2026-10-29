// Talep fotoğraflarının iki adımlı yüklemesi (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri"): her fotoğraf için
// adım 1 üstveri bildirimi (`POST .../attachments`, kayıt `uploading`), adım 2 ham gövde (`PUT .../content`).
//
// Fotoğraflar SIRAYLA gider. Bir fotoğrafın hatası ötekileri durdurmaz; ama sonraki fotoğrafların da kesin
// reddedileceği hatalarda (talep başına sınır, kapanmış talep, yetki, talep yok, 429, modül kapalı) kalanlar
// DENENMEDEN aynı nedenle başarısız sayılır. Sonuç fotoğraf başına tutulur ve turlar arasında birikir: yeniden
// denemeden sonra da kaç fotoğrafın eklenemediği DÜRÜSTÇE bilinir ([failedCount]).
//
// Yeniden deneme ve kayıt temizliği (DocumentUploadController ile aynı ilkeler):
// - Adım 1 başarılı, adım 2 yarıda kaldıysa AYNI ek kaydına yeniden gönderilir (çift kayıt olmaz). 409
//   `UPLOAD_ALREADY_COMPLETED` BAŞARIDIR (önceki denemenin yanıtı kaybolmuştu). 410 `UPLOAD_EXPIRED` / 404 kayıt yok:
//   kayıt atılır, yeniden denemede yeni kayıt açılır.
// - Sunucu içeriği KESİN reddettiyse (413 / 415 / 400 boyut uyuşmazlığı) yarım kayıt hemen silinir (talep başına 4
//   sınırını boşuna doldurmasın) ve aynı fotoğrafla yeniden denenmez.
// - Sonucu BELİRSİZ kayıt (ağ hatası, 5xx, gövde gittikten sonra iptal) silinmez: sunucuda tamamlanmış olabilir
//   (silmek başarılı fotoğrafı yok ederdi). Tamamlanmamışsa sunucu bakımı 2 saatte kaldırır; sahibi ayrıntıdan siler.
// - Mutasyonlar otomatik yeniden DENENMEZ; yeniden deneme kullanıcı kararıdır ([retryFailed]).
// - İptal yalnız uçuştaki fotoğrafı keser; tamamlananlar sunucuda kalır.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart'
    show DocumentCancelToken, DocumentTransferCancelled;
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';

enum WorkUploadPhase {
  /// Henüz başlamadı.
  idle,

  /// Adım 1: sunucu üstveriyi doğruluyor (kayıt açılıyor).
  preparing,

  /// Adım 2: baytlar gönderiliyor.
  uploading,

  /// Gövde gitti, sunucu yanıtı bekleniyor.
  finishing,

  /// Tüm fotoğraflar yüklendi.
  done,

  /// En az bir fotoğraf yüklenemedi ([WorkAttachmentUploadController.failures]).
  failed,

  /// Kullanıcı iptal etti (tamamlananlar sunucuda kaldı).
  cancelled,
}

/// Bir fotoğrafın yükleme sonucu.
@immutable
class WorkPhotoUploadResult {
  const WorkPhotoUploadResult({
    required this.photo,
    this.attachment,
    this.error,
    this.canRetry = false,
    this.cancelled = false,
  });

  final WorkPhotoPick photo;

  /// Başarıda sunucunun döndürdüğü hazır (`ready`) ek.
  final WorkAttachment? attachment;

  /// Başarısızsa kullanıcıya gösterilecek Türkçe metin.
  final String? error;

  /// Aynı fotoğrafla yeniden denemek anlamlı mı (ağ / 5xx / 429 / süre dolumu / iptal)?
  final bool canRetry;

  /// Kullanıcı iptal ettiği için gönderilmedi.
  final bool cancelled;

  bool get ok => attachment != null;
}

/// Adım 1'i bitmiş ama içeriği tamamlanmamış kayıt. [uncertain]: son denemenin sonucu belirsiz (sunucuda
/// tamamlanmış olabilir); böyle kayıt istemcice SİLİNMEZ.
class _PendingRecord {
  _PendingRecord(this.id);

  final int id;
  bool uncertain = false;
}

const String _genericUploadMessage =
    'Fotoğraf yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
const String _cancelledMessage = 'Yükleme iptal edildi.';

class WorkAttachmentUploadController extends ChangeNotifier {
  WorkAttachmentUploadController({
    required this.service,
    required this.workItemId,
    this.siteCode,
    DateTime Function()? now,
    bool? web,
  }) : _now = now ?? DateTime.now,
       _web = web ?? kIsWeb;

  final WorkTrackingService service;
  final int workItemId;

  /// null: sakin yolu (`/app/...`); dolu: yönetim yolu (`/manager/sites/:siteCode/...`).
  final int? siteCode;
  final DateTime Function() _now;

  /// Web: tarayıcı gövdeyi tek seferde gönderir; bayt ilerlemesi bilinmez (yanıta dek belirsiz çubuk) ve iptal edilen
  /// gönderimin sonucu belirsiz sayılır.
  final bool _web;

  WorkUploadPhase _phase = WorkUploadPhase.idle;
  int _index = 0;
  int _total = 0;
  int _sent = 0;
  int _totalBytes = 0;
  Object? _lastException;
  List<WorkPhotoUploadResult> _results = const <WorkPhotoUploadResult>[];
  final List<WorkAttachment> _uploaded = <WorkAttachment>[];

  /// Fotoğraf -> EN SON sonucu (turlar arasında birikir; kimlik eşlemesi: aynı ad / boyutlu iki fotoğraf ayrıdır).
  final Map<WorkPhotoPick, WorkPhotoUploadResult> _latest =
      Map<WorkPhotoPick, WorkPhotoUploadResult>.identity();

  /// Fotoğraf -> içeriği gitmemiş kayıt (yeniden deneme aynı kaydı kullanır).
  final Map<WorkPhotoPick, _PendingRecord> _pending =
      Map<WorkPhotoPick, _PendingRecord>.identity();

  /// Bu turda sırası henüz gelmemiş ya da işlenmekte olan fotoğraflar ve işlenen fotoğraf.
  final Set<WorkPhotoPick> _queued = Set<WorkPhotoPick>.identity();
  WorkPhotoPick? _current;
  DocumentCancelToken? _cancel;
  bool _disposed = false;
  int _lastNotifiedPercent = -1;
  DateTime _lastNotifiedAt = DateTime.fromMillisecondsSinceEpoch(0);

  WorkUploadPhase get phase => _phase;

  /// Yeni açılan ek kayıtlarına yazılacak "önce / sonra" etiketi (null: etiketsiz). Ekran, fotoğraf seçilmeden ÖNCE
  /// seçili etiketi buraya koyar; zaten açılmış (yarım) kayıtlar etiketini değiştirmez.
  WorkAttachmentPhase? photoPhase;

  /// Sıradaki fotoğrafın numarası (1'den başlar) ve bu turdaki toplam.
  int get index => _index;
  int get total => _total;
  int get sentBytes => _sent;
  int get totalBytes => _totalBytes;

  /// Son hatanın kendisi (429 kilidi gibi koda göre kararlar için).
  Object? get lastException => _lastException;

  /// Son turun sonuçları (fotoğraf sırasıyla).
  List<WorkPhotoUploadResult> get results => _results;

  /// Fotoğrafın en son sonucu; hiç denenmediyse null.
  WorkPhotoUploadResult? resultFor(WorkPhotoPick photo) => _latest[photo];

  /// Fotoğraf (herhangi bir turda) yüklendi mi?
  bool isUploaded(WorkPhotoPick photo) => _latest[photo]?.ok ?? false;

  /// Fotoğraf bu turda sırada ya da işleniyor mu ([current] işlenendir)?
  bool isQueued(WorkPhotoPick photo) => _queued.contains(photo);

  /// Şu an işlenen fotoğraf; yoksa null.
  WorkPhotoPick? get current => _current;

  /// Şu an içeriği gönderilen ek kaydının kimliği (şeritte "Yükleniyor" yalnız bu kayıtta yazar); yoksa null.
  int? get inFlightAttachmentId {
    final photo = _current;
    if (!busy || photo == null) return null;
    return _pending[photo]?.id;
  }

  /// Bayt ilerlemesi biliniyor mu (web'de bilinmez).
  bool get progressKnown => !_web;

  /// Tüm turlarda başarıyla yüklenen ekler.
  List<WorkAttachment> get uploaded => List<WorkAttachment>.unmodifiable(_uploaded);
  int get uploadedCount => _uploaded.length;

  /// Şu an yüklenmemiş durumda olan fotoğrafların son sonuçları (iptal dahil; turlar arası).
  List<WorkPhotoUploadResult> get failures => <WorkPhotoUploadResult>[
    for (final result in _latest.values)
      if (!result.ok) result,
  ];

  int get failedCount => failures.length;

  /// İlk yüklenemeyen fotoğrafın iletisi; yoksa null.
  String? get error {
    final failed = failures;
    return failed.isEmpty ? null : failed.first.error;
  }

  /// Yeniden denenebilecek fotoğraflar (ağ / 5xx / 429 / süre dolumu / iptal).
  List<WorkPhotoPick> get retryablePhotos => <WorkPhotoPick>[
    for (final result in failures)
      if (result.canRetry) result.photo,
  ];

  bool get canRetry => retryablePhotos.isNotEmpty;

  bool get busy =>
      _phase == WorkUploadPhase.preparing ||
      _phase == WorkUploadPhase.uploading ||
      _phase == WorkUploadPhase.finishing;

  /// 0..1 ilerleme (sıradaki fotoğraf); toplam ya da ilerleme bilinmiyorsa (web) null: belirsiz çubuk.
  double? get fraction => !progressKnown || _totalBytes <= 0
      ? null
      : (_sent / _totalBytes).clamp(0.0, 1.0);

  int get percent =>
      _totalBytes <= 0 ? 0 : ((_sent * 100) ~/ _totalBytes).clamp(0, 100);

  /// [photos]'ı sırayla yükler; her başarıda [onUploaded] çağrılır (ekran listeyi anında günceller). Sonuçlar
  /// [results] / [failures] / [phase] ile de okunur. Sürerken ikinci çağrı yok sayılır (boş liste döner).
  Future<List<WorkPhotoUploadResult>> run(
    List<WorkPhotoPick> photos, {
    void Function(WorkAttachment attachment)? onUploaded,
  }) async {
    if (busy || _disposed || photos.isEmpty) {
      return const <WorkPhotoUploadResult>[];
    }
    final cancel = DocumentCancelToken();
    _cancel = cancel;
    final results = <WorkPhotoUploadResult>[];
    _results = results;
    _lastException = null;
    _total = photos.length;
    _index = 0;
    _sent = 0;
    _totalBytes = 0;
    String? fatal;
    var fatalRetry = false;
    var cancelled = false;
    _queued
      ..clear()
      ..addAll(photos);

    void record(WorkPhotoUploadResult result) {
      results.add(result);
      _latest[result.photo] = result;
      _queued.remove(result.photo);
      if (identical(_current, result.photo)) _current = null;
    }

    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (cancel.isCancelled) {
        cancelled = true;
        record(
          WorkPhotoUploadResult(
            photo: photo,
            error: _cancelledMessage,
            canRetry: true,
            cancelled: true,
          ),
        );
        continue;
      }
      if (fatal != null) {
        record(
          WorkPhotoUploadResult(photo: photo, error: fatal, canRetry: fatalRetry),
        );
        continue;
      }
      final precheck = photo.validationError;
      if (precheck != null) {
        // Sunucuya hiç gitmez: aynı dosyayla düzelmez.
        record(WorkPhotoUploadResult(photo: photo, error: precheck));
        continue;
      }
      _index = i + 1;
      _current = photo;
      _sent = 0;
      _totalBytes = photo.size;
      _lastNotifiedPercent = -1;
      _setPhase(WorkUploadPhase.preparing);
      var pending = _pending[photo];
      try {
        if (pending == null) {
          final created = await service.createAttachment(
            siteCode: siteCode,
            id: workItemId,
            request: WorkAttachmentCreateRequest(
              fileName: photo.name,
              mimeType: photo.mimeType,
              sizeBytes: photo.size,
              phase: photoPhase,
            ),
          );
          if (_disposed) return results;
          pending = _PendingRecord(created.id);
          _pending[photo] = pending;
        }
        if (cancel.isCancelled) throw const DocumentTransferCancelled();
        _setPhase(WorkUploadPhase.uploading);
        WorkAttachment ready;
        try {
          ready = await service.uploadAttachment(
            siteCode: siteCode,
            id: workItemId,
            attachmentId: pending.id,
            source: photo.source,
            cancel: cancel,
            onProgress: _onProgress,
          );
        } on ApiException catch (e) {
          if (e.code != 'UPLOAD_ALREADY_COMPLETED') rethrow;
          // Önceki deneme sunucuda tamamlanmıştı (yanıtı kaybolmuştu): başarı. Ayrıntılar sonraki tazelemede gelir.
          ready = WorkAttachment(
            id: pending.id,
            workItemId: workItemId,
            fileName: photo.name,
            mimeType: photo.mimeType,
            sizeBytes: photo.size,
            status: WorkAttachmentStatus.ready,
            phase: photoPhase,
            uploadedByMe: true,
          );
        }
        if (_disposed) return results;
        _pending.remove(photo);
        _uploaded.add(ready);
        _sent = _totalBytes;
        record(WorkPhotoUploadResult(photo: photo, attachment: ready));
        onUploaded?.call(ready);
      } on DocumentTransferCancelled {
        if (_disposed) return results;
        cancelled = true;
        // Gövde tamamen gittikten SONRA (finishing) kesmek sunucunun kaydetmesini engellemez: sonuç belirsiz. Web'de
        // gövdenin ne kadarının gittiği bilinmez: her iptal belirsizdir (kayıt silinmez).
        pending?.uncertain = _web || _phase == WorkUploadPhase.finishing;
        record(
          WorkPhotoUploadResult(
            photo: photo,
            error: _cancelledMessage,
            canRetry: true,
            cancelled: true,
          ),
        );
      } catch (e) {
        if (_disposed) return results;
        final outcome = _classify(e, photo, pending);
        record(outcome.result);
        if (outcome.stopsRest) {
          fatal = outcome.result.error;
          fatalRetry = outcome.result.canRetry;
        }
      }
    }

    _cancel = null;
    _queued.clear();
    _current = null;
    _setPhase(
      cancelled
          ? WorkUploadPhase.cancelled
          : (failedCount > 0 ? WorkUploadPhase.failed : WorkUploadPhase.done),
    );
    return List<WorkPhotoUploadResult>.unmodifiable(results);
  }

  /// Yeniden denenebilir olanları yeniden yükler.
  Future<List<WorkPhotoUploadResult>> retryFailed({
    void Function(WorkAttachment attachment)? onUploaded,
  }) => run(retryablePhotos, onUploaded: onUploaded);

  ({WorkPhotoUploadResult result, bool stopsRest}) _classify(
    Object e,
    WorkPhotoPick photo,
    _PendingRecord? pending,
  ) {
    _lastException = e;
    final api = e is ApiException ? e : null;
    final status = api?.statusCode;
    final code = (api?.code ?? '').toUpperCase();
    final message = api != null && api.message.trim().isNotEmpty
        ? api.message
        : _genericUploadMessage;
    final expired = status == 410 || code == 'UPLOAD_EXPIRED';
    final recordMissing =
        (status == 404 && code == 'WORK_ATTACHMENT_NOT_FOUND') || expired;
    // Sunucu içeriği işlemedi (hız sınırı / meşgul / aynı kayda başka gönderim sürüyor): kayıt korunur.
    final notProcessed =
        status == 429 || code == 'UPLOAD_BUSY' || code == 'UPLOAD_IN_PROGRESS';
    // Sonuç belirsiz (ağ, zaman aşımı, 5xx): sunucuda tamamlanmış olabilir.
    final uncertain =
        !notProcessed && (api == null || status == null || api.isServerError);
    final retryable = uncertain || notProcessed || recordMissing;
    // İçerik KESİN reddedildi (kayıt `uploading` kaldı): aynı fotoğrafla düzelmez, yarım kayıt hemen silinir.
    final contentRejected =
        pending != null &&
        (status == 413 || status == 415 || code == 'ATTACHMENT_SIZE_MISMATCH');
    final itemClosed = code == 'INVALID_STATE' || code == 'WORK_ITEM_CLOSED';
    if (pending != null) {
      if (contentRejected || expired) {
        // Kesin ret ya da süresi dolmuş kayıt: sessizce silinir; yeniden denemede YENİ kayıt açılır.
        _pending.remove(photo);
        unawaited(_deleteQuietly(pending.id));
      } else if (recordMissing || itemClosed || !retryable) {
        // Kayıt yok / kullanılamaz: yeniden denemede yeni kayıt açılır (kapalı talepte zaten denenmez).
        _pending.remove(photo);
      } else {
        // UPLOAD_IN_PROGRESS: önceki gönderim sunucuda sürüyor olabilir (tamamlanabilir): belirsiz sayılır.
        pending.uncertain = uncertain || code == 'UPLOAD_IN_PROGRESS';
      }
    }
    // Kalan fotoğraflar da aynı nedenle reddedilir: boşuna denenmez.
    final itemGone = status == 404 && !recordMissing;
    final stopsRest =
        status == 401 ||
        status == 403 ||
        itemGone ||
        status == 429 ||
        code == 'LIMIT_REACHED' ||
        code == 'ATTACHMENT_QUOTA_EXCEEDED' ||
        itemClosed ||
        code == 'MODULE_DISABLED';
    return (
      result: WorkPhotoUploadResult(
        photo: photo,
        error: message,
        canRetry: retryable,
      ),
      stopsRest: stopsRest,
    );
  }

  Future<void> _deleteQuietly(int attachmentId) async {
    try {
      await service.deleteAttachment(
        siteCode: siteCode,
        id: workItemId,
        attachmentId: attachmentId,
      );
    } catch (_) {
      // En iyi çaba: silinemeyen yarım kaydı sunucu bakımı 2 saatte kaldırır.
    }
  }

  /// Akış biterken (pencere kapanırken ya da yeni seçimden önce) içeriği KESİN gitmemiş yarım kayıtları siler
  /// (talep başına 4 sınırını doldurmasın). Sonucu belirsiz kayıtlara dokunulmaz (tamamlanmış olabilir). Sürerken
  /// etkisizdir; hata fırlatmaz.
  Future<void> discardPending() async {
    if (busy || _pending.isEmpty) return;
    final safe = <int>[
      for (final record in _pending.values)
        if (!record.uncertain) record.id,
    ];
    _pending.clear();
    for (final id in safe) {
      await _deleteQuietly(id);
    }
  }

  void _onProgress(int sent, int total) {
    if (_disposed) return;
    _sent = sent;
    _totalBytes = total;
    final percent = this.percent;
    final now = _now();
    final due =
        percent != _lastNotifiedPercent &&
        (percent == 100 ||
            now.difference(_lastNotifiedAt) >=
                const Duration(milliseconds: 120));
    if (!due) return;
    _lastNotifiedPercent = percent;
    _lastNotifiedAt = now;
    if (percent >= 100 && _phase == WorkUploadPhase.uploading) {
      _phase = WorkUploadPhase.finishing;
    }
    notifyListeners();
  }

  /// Uçuştaki yüklemeyi keser; kalan fotoğraflar gönderilmez (tamamlananlar sunucuda kalır).
  void cancel() {
    _cancel?.cancel();
  }

  void _setPhase(WorkUploadPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  /// Yeni bir seçim için sonuçları atar (sürerken etkisiz). Yüklenenler listesi korunur; yarım kayıtlar önce
  /// [discardPending] ile temizlenmelidir (burada yalnız takipten düşer).
  void reset() {
    if (busy) return;
    _phase = WorkUploadPhase.idle;
    _results = const <WorkPhotoUploadResult>[];
    _latest.clear();
    _pending.clear();
    _queued.clear();
    _current = null;
    _lastException = null;
    _index = 0;
    _total = 0;
    _sent = 0;
    _totalBytes = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
