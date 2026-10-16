import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';

/// Belge listesinin yükleme durumu.
enum LegalLoadStatus { loading, ready, error }

/// Bir formdaki (kayıt, site başvurusu) yasal onay kutusunun durumu.
///
/// Belge listesi sunucudan okunur; [context] (`register` | `site_application`) için `required_for`
/// listesinde olan belgeler gösterilir. Kurallar:
/// - Belgeler yüklenemediyse onay VERİLEMEZ ([blocksSubmit] true): sahte onay yok.
/// - Yükleme başarılı ve onay gerektiren belge yoksa kutu çıkmaz ve gönderim engellenmez.
/// - Belgeler yeniden yüklendiğinde (sürüm değiştiyse) önceki işaret kaldırılır: kullanıcı yeni sürümü
///   görmeden onaylamış sayılmaz.
class LegalConsentController extends ChangeNotifier {
  LegalConsentController({required this.api, required this.context});

  final LegalApi api;

  /// `required_for` değeri: [LegalContexts.register] ya da [LegalContexts.siteApplication].
  final String context;

  LegalLoadStatus _status = LegalLoadStatus.loading;
  String? _error;
  List<LegalDocumentSummary> _documents = const <LegalDocumentSummary>[];
  bool _accepted = false;
  bool _disposed = false;
  bool _inFlight = false;

  LegalLoadStatus get status => _status;

  /// Yükleme hatası iletisi (yalnız [status] `error` iken).
  String? get error => _error;

  /// Bu bağlamda onay gerektiren belgeler.
  List<LegalDocumentSummary> get documents => _documents;

  /// Kutu işaretli mi?
  bool get accepted => _accepted;

  /// Kutu gösterilecek mi? (yüklendi ve onay gerektiren belge var)
  bool get needsConsent => _status == LegalLoadStatus.ready && _documents.isNotEmpty;

  /// Formun gönder düğmesi kapalı mı?
  bool get blocksSubmit {
    switch (_status) {
      case LegalLoadStatus.loading:
      case LegalLoadStatus.error:
        return true;
      case LegalLoadStatus.ready:
        return _documents.isNotEmpty && !_accepted;
    }
  }

  /// [blocksSubmit] true iken kullanıcıya gösterilecek NEDEN metni; engel yoksa null.
  String? get blockReason {
    switch (_status) {
      case LegalLoadStatus.loading:
        return 'Belgeler yükleniyor; yüklenince devam edebilirsiniz.';
      case LegalLoadStatus.error:
        return 'Belgeler yüklenemediği için devam edilemiyor. "Yeniden dene" ile tekrar deneyin.';
      case LegalLoadStatus.ready:
        return needsConsent && !_accepted
            ? 'Devam etmek için belgeleri okuyup onay kutusunu işaretleyin.'
            : null;
    }
  }

  /// Gönderim gövdesindeki `accepted_documents`; onay yoksa boş liste.
  List<AcceptedDocument> get acceptedDocuments => needsConsent && _accepted
      ? <AcceptedDocument>[for (final d in _documents) d.toAccepted()]
      : const <AcceptedDocument>[];

  String _signature() => _documents.map((d) => '${d.id}@${d.version}').join('|');

  /// Belgeleri (yeniden) yükler. Sürerken ikinci çağrı yok sayılır. [showLoading] true ise daha önce
  /// yüklenmiş olsa bile yükleniyor durumuna geçer (hata o zaman açıkça gösterilir).
  Future<void> load({bool showLoading = false}) async {
    if (_inFlight || _disposed) return;
    _inFlight = true;
    final hadDocuments = _status == LegalLoadStatus.ready;
    if (!hadDocuments || showLoading) {
      _status = LegalLoadStatus.loading;
      _error = null;
      notifyListeners();
    }
    final before = _signature();
    try {
      final all = await api.listDocuments();
      final required = <LegalDocumentSummary>[
        for (final d in all)
          if (d.isRequiredFor(context)) d,
      ];
      _documents = required;
      _status = LegalLoadStatus.ready;
      _error = null;
      // Belge kümesi ya da sürümü değiştiyse eski işaret geçersizdir.
      if (_signature() != before || required.isEmpty) _accepted = false;
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail(LegalMessages.loadFailed);
    } finally {
      _inFlight = false;
    }
    if (!_disposed) notifyListeners();
  }

  void _fail(String message) {
    // İlk yükleme başarısızsa hata durumu; daha önce yüklenmişken yenileme başarısızsa eski liste ve
    // işaret korunur (kullanıcı gördüğünü onaylamış olur), ama hata durumu bildirilir.
    if (_status != LegalLoadStatus.ready) {
      _status = LegalLoadStatus.error;
      _documents = const <LegalDocumentSummary>[];
      _accepted = false;
    }
    _error = message;
  }

  /// Kutuyu işaretler/kaldırır. Belgeler yüklenmediyse hiçbir şey yapmaz (sahte onay yok).
  void setAccepted(bool value) {
    if (!needsConsent || _accepted == value) return;
    _accepted = value;
    notifyListeners();
  }

  /// Sunucu "belgeler güncellendi / onay gerekli" derse: işareti kaldırıp belgeleri yeniden okur.
  Future<void> reloadAfterRejection() {
    _accepted = false;
    notifyListeners();
    return load(showLoading: true);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
