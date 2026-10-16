/// Yasal belge modelleri (docs/PLATFORM_SATISA_HAZIRLIK.md §1.4).
///
/// Ayrıştırma hata fırlatmaz: sunucudan gelen eksik/null/beklenmeyen türdeki alanlar güvenli
/// varsayılana düşer. Kimliği ya da sürümü olmayan bir belge/onay ATLANIR (sahte onay üretilmez).
library;

/// Belgenin hangi bağlamda onay gerektirdiğini belirten `required_for` değerleri.
abstract final class LegalContexts {
  /// Hesap kaydı (bireysel kayıt, daire sahibi kaydı, site yöneticisi kaydı).
  static const String register = 'register';

  /// Site başvurusu (veri işleme sözleşmesi).
  static const String siteApplication = 'site_application';
}

/// Bilinen belge kimlikleri.
abstract final class LegalDocumentIds {
  static const String terms = 'terms';
  static const String privacy = 'privacy';
  static const String kvkkNotice = 'kvkk_notice';
  static const String dpa = 'dpa';
  static const String accountDeletion = 'account_deletion';
}

/// Sunucu hata kodlarına karşılık gelen kullanıcı iletileri (kayıt/onay akışları).
abstract final class LegalMessages {
  /// 400 `CONSENT_REQUIRED`.
  static const String consentRequired =
      'Devam etmek için güncel kullanım koşullarını, gizlilik politikasını ve KVKK metnini '
      'okuyup onaylamanız gerekiyor. Belgeleri açıp kutuyu yeniden işaretleyin.';

  /// 409 `CONSENT_VERSION_STALE`.
  static const String consentVersionStale =
      'Belgeler güncellendi. Güncel metinleri okuyup onay kutusunu yeniden işaretleyin.';

  /// 400 `DOCUMENT_NOT_ACCEPTABLE`: belge artık onay gerektirmiyor / bilinmiyor.
  static const String documentNotAcceptable =
      'Bu belge için onay gerekmiyor ya da belge değişti. Sayfayı yenileyip tekrar deneyin.';

  /// 409 `DOCUMENT_INCOMPLETE`: belge henüz tamamlanmadığı için onaylanamıyor.
  static const String documentIncomplete =
      'Bu belge henüz tamamlanmadığı için onaylanamıyor. Biraz sonra tekrar deneyin.';

  /// 400 `INVALID_ACCEPTED_DOCUMENTS`.
  static const String invalidAcceptedDocuments =
      'Onay bilgisi geçersiz. Belgeleri yeniden açıp tekrar deneyin.';

  /// Onay gönderilemedi (ağ / beklenmeyen hata ya da sunucu boş ileti verdi).
  static const String consentSubmitFailed =
      'Onayınız gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  /// Belge listesi/metni alınamadı (sahte onay verilmez).
  static const String loadFailed =
      'Belgeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
}

/// Belge özeti: `GET /public/legal-documents` öğesi.
class LegalDocumentSummary {
  const LegalDocumentSummary({
    required this.id,
    required this.title,
    required this.version,
    this.effectiveDate,
    this.requiredFor = const <String>[],
    this.complete = true,
  });

  final String id;
  final String title;

  /// Belge sürümü (değiştikçe yeniden onay istenir). Onay gövdesinde aynen geri gönderilir.
  final String version;

  /// Yürürlük tarihi (sunucu metni, örn. `2026-10-16`); yoksa null.
  final String? effectiveDate;

  /// `register` | `site_application` | boş.
  final List<String> requiredFor;

  /// false: belgedeki yer tutucular (`[……]`) henüz doldurulmamıştır.
  final bool complete;

  bool isRequiredFor(String context) => requiredFor.contains(context);

  AcceptedDocument toAccepted() => AcceptedDocument(id: id, version: version);

  /// Geçerli kimlik+sürüm yoksa null (o belge listeden atlanır).
  static LegalDocumentSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _stringKeyed(raw);
    final id = _text(json['id']);
    final version = _text(json['version']);
    if (id == null || version == null) return null;
    return LegalDocumentSummary(
      id: id,
      title: _text(json['title']) ?? id,
      version: version,
      effectiveDate: _text(json['effective_date']),
      requiredFor: _textList(json['required_for']),
      // Alan yoksa belge tamam sayılır (sunucu `complete:false` ile açıkça uyarır).
      complete: json['complete'] is bool ? json['complete'] as bool : true,
    );
  }
}

/// Belge metni: `GET /public/legal-documents/:id`.
class LegalDocument {
  const LegalDocument({required this.summary, required this.contentMd});

  final LegalDocumentSummary summary;

  /// İzinli Markdown alt kümesinde metin (başlık, paragraf, liste, kalın, https bağlantı).
  final String contentMd;

  String get id => summary.id;
  String get title => summary.title;
  String get version => summary.version;

  static LegalDocument? tryParse(Object? raw) {
    final summary = LegalDocumentSummary.tryParse(raw);
    if (summary == null || raw is! Map) return null;
    final content = raw['content_md'];
    return LegalDocument(summary: summary, contentMd: content is String ? content : '');
  }
}

/// Onaylanan belge (kayıt/başvuru/onay gövdesindeki `accepted_documents` öğesi).
class AcceptedDocument {
  const AcceptedDocument({required this.id, required this.version});

  final String id;
  final String version;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'version': version};

  @override
  bool operator ==(Object other) =>
      other is AcceptedDocument && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() => 'AcceptedDocument($id@$version)';
}

/// Kullanıcının verdiği onay kaydı: `GET /me/consents` -> `consents[]`.
class ConsentRecord {
  const ConsentRecord({required this.documentId, required this.version, this.acceptedAt});

  final String documentId;
  final String version;
  final DateTime? acceptedAt;

  static ConsentRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _stringKeyed(raw);
    final id = _text(json['document_id']);
    final version = _text(json['version']);
    if (id == null || version == null) return null;
    final at = _text(json['accepted_at']);
    return ConsentRecord(
      documentId: id,
      version: version,
      acceptedAt: at == null ? null : DateTime.tryParse(at),
    );
  }
}

/// Onay bekleyen belge: `GET /me/consents` -> `pending[]`.
class PendingConsent {
  const PendingConsent({required this.id, required this.title, required this.version});

  final String id;
  final String title;
  final String version;

  AcceptedDocument toAccepted() => AcceptedDocument(id: id, version: version);

  static PendingConsent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _stringKeyed(raw);
    final id = _text(json['id']);
    final version = _text(json['version']);
    if (id == null || version == null) return null;
    return PendingConsent(id: id, title: _text(json['title']) ?? id, version: version);
  }
}

/// `GET /me/consents` yanıtı.
class MyConsents {
  const MyConsents({this.consents = const <ConsentRecord>[], this.pending = const <PendingConsent>[]});

  final List<ConsentRecord> consents;
  final List<PendingConsent> pending;

  factory MyConsents.fromJson(Map<String, dynamic> json) {
    return MyConsents(
      consents: _parseList(json['consents'], ConsentRecord.tryParse),
      pending: _parseList(json['pending'], PendingConsent.tryParse),
    );
  }
}

/// `POST /me/consents` yanıtı: kaydedilen onaylar ve (sunucu gönderiyorsa) hâlâ onay bekleyen belgeler.
/// [pending] null: yanıtta `pending` alanı yok (eski sunucu); boş liste: bekleyen kalmadı.
class ConsentAcceptResult {
  const ConsentAcceptResult({this.consents = const <ConsentRecord>[], this.pending});

  final List<ConsentRecord> consents;
  final List<PendingConsent>? pending;

  factory ConsentAcceptResult.fromJson(Map<String, dynamic> json) {
    return ConsentAcceptResult(
      consents: _parseList(json['consents'], ConsentRecord.tryParse),
      pending: json['pending'] is List ? _parseList(json['pending'], PendingConsent.tryParse) : null,
    );
  }
}

List<T> _parseList<T>(Object? raw, T? Function(Object?) parse) {
  if (raw is! List) return <T>[];
  return <T>[
    for (final item in raw)
      if (parse(item) case final T parsed) parsed,
  ];
}

Map<String, dynamic> _stringKeyed(Map raw) =>
    raw.map((key, value) => MapEntry(key.toString(), value));

String? _text(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num) return value.toString();
  return null;
}

List<String> _textList(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

/// Belge listesini çözer; tanınmayan öğeler atlanır.
List<LegalDocumentSummary> parseLegalDocumentList(Object? raw) =>
    _parseList(raw, LegalDocumentSummary.tryParse);
