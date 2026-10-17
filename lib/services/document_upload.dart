// İki adımlı belge yükleme akışının durum makinesi (docs/PLATFORM_BELGELER.md A3).
//
// Adım 1: üstveri + dosya bildirimi (`POST`), sunucu OKUR-DOĞRULAR ve yükleme tanımı döner.
// Adım 2: ham gövde akışı (`PUT`), ilerleme + iptal.
//
// Yeniden deneme kuralları:
// - Adım 1 sonucu BELİRSİZSE (zaman aşımı, 5xx) aynı `idempotency_key` ile yeniden gönderilir: çift belge olmaz.
// - Adım 1 başarılı, adım 2 ağ hatasıyla yarıda kaldıysa YALNIZ adım 2 yinelenir (aynı bilet); bilet süresi
//   dolduysa ya da sunucu bileti reddettiyse (404 / 409 `INVALID_STATE`) adım 1 baştan yapılır.
// - Sunucu içeriği reddettiyse (415, 413, 400 ...) yeniden deneme AYNI dosyayla işe yaramaz: durum `failed` ve
//   [canRetry] false (kullanıcı başka dosya seçer).
// - 409 `UPLOAD_ALREADY_COMPLETED` başarıdır (önceki deneme sunucuda tamamlanmıştı).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';

enum DocumentUploadPhase {
  /// Henüz başlamadı (form).
  idle,

  /// Adım 1: sunucu dosyayı / kotayı doğruluyor.
  preparing,

  /// Adım 2: baytlar gönderiliyor.
  uploading,

  /// Gövde gitti, sunucu yanıtı bekleniyor.
  finishing,

  /// Tamamlandı.
  done,

  /// Hata (ileti [DocumentUploadController.error]).
  failed,

  /// Kullanıcı iptal etti.
  cancelled,
}

class DocumentUploadController extends ChangeNotifier {
  DocumentUploadController({
    required this.service,
    required this.siteCode,
    this.documentId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DocumentService service;
  final int siteCode;

  /// Dolu ise yeni SÜRÜM yüklenir (`POST .../:id/versions`); null ise yeni belge.
  final int? documentId;
  final DateTime Function() _now;

  DocumentUploadPhase _phase = DocumentUploadPhase.idle;
  int _sent = 0;
  int _total = 0;
  String? _error;
  bool _canRetry = false;
  DocumentSummary? _result;
  DocumentUploadTicket? _ticket;
  DocumentCancelToken? _cancel;
  bool _disposed = false;
  int _lastNotifiedPercent = -1;
  DateTime _lastNotifiedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _outcomeUncertain = false;
  bool _cancelledLate = false;
  Object? _lastException;

  DocumentUploadPhase get phase => _phase;
  int get sentBytes => _sent;
  int get totalBytes => _total;
  String? get error => _error;

  /// Son hatanın kendisi (429 kilidi gibi koda göre kararlar için); hata yoksa null.
  Object? get lastException => _lastException;

  /// Adım 1 başarıyla bitti, yükleme tanımı elde: yeniden deneme yalnız adım 2'yi yineler.
  bool get hasTicket => _ticket != null;

  /// Aynı dosyayla yeniden denemek anlamlı mı?
  bool get canRetry => _canRetry;
  DocumentSummary? get result => _result;

  /// Adım 1 sonucu belirsiz kaldı: belge oluşmuş olabilir (liste yenilenmeli).
  bool get outcomeUncertain => _outcomeUncertain;

  /// İptal, gövde tamamen gönderildikten SONRA (sunucu kaydederken) yapıldı: belge yine de kaydedilmiş olabilir.
  bool get cancelledLate => _cancelledLate;

  bool get busy =>
      _phase == DocumentUploadPhase.preparing ||
      _phase == DocumentUploadPhase.uploading ||
      _phase == DocumentUploadPhase.finishing;

  /// 0..1 ilerleme; toplam bilinmiyorsa null.
  double? get fraction => _total <= 0 ? null : (_sent / _total).clamp(0.0, 1.0);

  /// Yüzde (0..100).
  int get percent => _total <= 0 ? 0 : ((_sent * 100) ~/ _total).clamp(0, 100);

  /// Yüklemeyi (ya da yeniden denemeyi) çalıştırır. [create] yeni belge isteğidir (sürüm yüklemede null);
  /// [file] ile [create.file] aynı dosyayı tanımlamalıdır. Sonuç [phase] / [result] / [error] ile okunur.
  Future<void> run({
    required DocumentUploadSource source,
    DocumentCreateRequest? create,
    String? note,
  }) async {
    if (busy || _disposed) return;
    final cancel = DocumentCancelToken();
    _cancel = cancel;
    _error = null;
    _lastException = null;
    _canRetry = false;
    _cancelledLate = false;
    _sent = 0;
    _total = source.size;
    _lastNotifiedPercent = -1;
    _setPhase(DocumentUploadPhase.preparing);
    try {
      var ticket = _ticket;
      final expired =
          ticket?.upload.expiresAt != null &&
          !ticket!.upload.expiresAt!.isAfter(_now());
      if (ticket == null || expired) {
        ticket = null;
        _ticket = null;
        final file = DocumentFileInput(
          name: source.name,
          size: source.size,
          contentType: DocumentFileRules.contentTypeOf(source.name),
        );
        ticket = documentId == null
            ? await service.createDocument(siteCode, create!)
            : await service.createVersion(
                siteCode,
                documentId!,
                file,
                note: note,
              );
        _outcomeUncertain = false;
        if (_disposed) return;
        _ticket = ticket;
      }
      if (cancel.isCancelled) throw const DocumentTransferCancelled();
      _total = ticket.upload.size > 0 ? ticket.upload.size : source.size;
      _setPhase(DocumentUploadPhase.uploading);
      final summary = await service.uploadContent(
        ticket.upload,
        source,
        cancel: cancel,
        onProgress: _onProgress,
      );
      if (_disposed) return;
      _result = summary.id > 0 ? summary : ticket.document;
      _sent = _total;
      _ticket = null;
      _outcomeUncertain = false;
      _cancelledLate = false;
      _setPhase(DocumentUploadPhase.done);
    } on DocumentTransferCancelled {
      if (_disposed) return;
      // Gövde tamamen gönderildikten sonra (finishing) bağlantıyı kesmek sunucunun isteği işlemesini ENGELLEMEZ:
      // "iptal edildi" demek yanıltıcı olur. Sonuç belirsiz sayılır; aynı bilet yeniden gönderilirse sunucu
      // 409 UPLOAD_ALREADY_COMPLETED ile durumu söyler (başarı sayılır).
      _cancelledLate = _phase == DocumentUploadPhase.finishing;
      if (_cancelledLate) {
        _outcomeUncertain = true;
        _error =
            'Yükleme durduruldu ama sunucu belgeyi kaydetmiş olabilir. "Yüklemeyi Sürdür" ile durumu '
            'kontrol edebilir ya da listeyi yenileyebilirsiniz.';
      } else {
        _error = 'Yükleme iptal edildi.';
      }
      _canRetry = true;
      _setPhase(DocumentUploadPhase.cancelled);
    } catch (e) {
      if (_disposed) return;
      _fail(e);
    } finally {
      _cancel = null;
    }
  }

  void _fail(Object e) {
    _lastException = e;
    final message = e is ApiException
        ? e.message
        : 'Yükleme tamamlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
    final apiError = e is ApiException ? e : null;
    final uncertain =
        apiError == null ||
        apiError.statusCode == null ||
        apiError.isServerError;
    // Adım 1'de bilet yoksa ve sonuç belirsizse belge oluşmuş olabilir.
    if (_ticket == null && uncertain) _outcomeUncertain = true;
    // Bilet ancak sunucu AÇIKÇA reddettiyse atılır (süre dolumu, durum değişimi); geçici hatada korunur.
    final status = apiError?.statusCode;
    final code = apiError?.code;
    final ticketUnusable =
        status == 404 ||
        status == 410 ||
        code == 'INVALID_STATE' ||
        code == 'DOCUMENT_VERSION_NOT_FOUND' ||
        code == 'UPLOAD_EXPIRED';
    if (ticketUnusable) _ticket = null;
    // İçerik / kota / yetki reddi aynı dosyayla düzelmez; ağ, 5xx, 429, UPLOAD_BUSY yinelenebilir.
    // UPLOAD_IN_PROGRESS: aynı sürüme başka bir gönderim sürüyor (önceki denemenin zaman aşımı); bilet korunur,
    // sonra yeniden denendiğinde sunucu 409 UPLOAD_ALREADY_COMPLETED (başarı) ya da sonucu söyler.
    _canRetry =
        uncertain ||
        status == 429 ||
        code == 'UPLOAD_BUSY' ||
        code == 'UPLOAD_PENDING_LIMIT' ||
        code == 'UPLOAD_IN_PROGRESS' ||
        ticketUnusable;
    // Aynı dosyayla düzelmeyecek bir ret (içerik / kota / yetki): bilet atılır, yeniden deneme baştan başlar.
    if (!_canRetry) _ticket = null;
    _error = message;
    _setPhase(DocumentUploadPhase.failed);
  }

  void _onProgress(int sent, int total) {
    if (_disposed) return;
    _sent = sent;
    _total = total;
    final percent = percentOf(sent, total);
    final now = _now();
    final due =
        percent != _lastNotifiedPercent &&
        (percent == 100 ||
            now.difference(_lastNotifiedAt) >=
                const Duration(milliseconds: 120));
    if (!due) return;
    _lastNotifiedPercent = percent;
    _lastNotifiedAt = now;
    if (percent >= 100 && _phase == DocumentUploadPhase.uploading) {
      _phase = DocumentUploadPhase.finishing;
    }
    notifyListeners();
  }

  static int percentOf(int sent, int total) =>
      total <= 0 ? 0 : ((sent * 100) ~/ total).clamp(0, 100);

  /// Çalışan yüklemeyi iptal eder (adım 2'de bağlantı kapanır; adım 1'de yanıt yok sayılır).
  void cancel() {
    _cancel?.cancel();
  }

  void _setPhase(DocumentUploadPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  /// Formu yeniden açar (ör. başka dosya seçmek için): hata ve bilet atılır.
  void reset() {
    if (busy) return;
    final unchanged =
        _phase == DocumentUploadPhase.idle &&
        _error == null &&
        _ticket == null &&
        _result == null &&
        _sent == 0 &&
        _total == 0;
    if (unchanged) return;
    _phase = DocumentUploadPhase.idle;
    _error = null;
    _lastException = null;
    _canRetry = false;
    _cancelledLate = false;
    _ticket = null;
    _result = null;
    _sent = 0;
    _total = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
