// Sayfa bağlamlı "Geri bildirim" (docs/PLATFORM_GERI_BILDIRIM.md, karar K11): modeller ve sınırlar.
//
// Sınırlar sunucuyla aynıdır ve sunucuda da doğrulanır (aşım 400): en çok 4 dosya, dosya başı 5 MB, toplam 20 MB, metin en çok 2000 karakter. Ekran bağlamı
// (ekran adı + rota) formda OTOMATİK eklenir; kullanıcı değiştiremez, yalnız görür. Rol ve site ilişkisi sunucuda türetilir.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart' show formatDocumentSize;

/// Bir geri bildirime en çok dosya.
const int kFeedbackAttachmentMax = 4;

/// Dosya başı üst sınır (5 MB).
const int kFeedbackAttachmentMaxBytes = 5 * 1024 * 1024;

/// Toplam üst sınır (20 MB).
const int kFeedbackTotalMaxBytes = 20 * 1024 * 1024;

/// Metin üst sınırı (kod noktası).
const int kFeedbackMessageMax = 2000;

/// Formun üstünde gösterilen, gönderim kapsamını anlatan gizlilik metni (KVKK şeffaflığı).
const String kFeedbackAudienceNote =
    'Geri bildiriminiz site yönetimi ve platform ekibi tarafından görülebilir. '
    'Ad ve rolünüzle birlikte kaydedilir; parola, kart ya da kişisel belge eklemeyin.';

/// Formun gönderim bağlamı (otomatik): hangi ekrandayken ve hangi sitede gönderildiği.
@immutable
class FeedbackScreenContext {
  const FeedbackScreenContext({
    required this.screenName,
    required this.screenRoute,
    this.siteCode,
    this.siteName,
  });

  /// Kullanıcının gördüğü ekran adı (ör. "Talepler").
  final String screenName;

  /// Makine okunur rota (ör. `menu/talepler`; harf, rakam ve `_ . : / -`).
  final String screenRoute;

  /// Bağlı site (biliniyorsa); sunucu gönderenin bu siteyle ilişkisini doğrular.
  final int? siteCode;

  /// Formda gösterilen site adı (isteğe bağlı).
  final String? siteName;
}

/// `POST /app/feedback` gövdesi.
@immutable
class FeedbackCreateRequest {
  const FeedbackCreateRequest({
    required this.message,
    required this.context,
    this.appVersion,
    this.platform,
    this.attachments = const <FeedbackAttachmentSpec>[],
  });

  final String message;
  final FeedbackScreenContext context;
  final String? appVersion;
  final String? platform;
  final List<FeedbackAttachmentSpec> attachments;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'message': message,
    'screen_name': context.screenName,
    'screen_route': context.screenRoute,
    if (context.siteCode != null) 'site_code': context.siteCode,
    if (appVersion != null && appVersion!.isNotEmpty) 'app_version': appVersion,
    if (platform != null && platform!.isNotEmpty) 'platform': platform,
    if (attachments.isNotEmpty)
      'attachments': <Map<String, dynamic>>[for (final a in attachments) a.toJson()],
  };
}

/// Bildirilen ek: ad, tür ve boyut (içerik ayrı `PUT` ile gider).
@immutable
class FeedbackAttachmentSpec {
  const FeedbackAttachmentSpec({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String fileName;
  final String mimeType;
  final int sizeBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'file_name': fileName,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
  };
}

/// Sunucudaki ek kaydı.
@immutable
class FeedbackAttachment {
  const FeedbackAttachment({
    required this.id,
    required this.feedbackId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.ready,
  });

  final int id;
  final int feedbackId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// İçerik yüklendi (görüntülenebilir).
  final bool ready;

  static FeedbackAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = _asInt(json['id']);
    final feedbackId = _asInt(json['feedback_id']);
    if (id == null || feedbackId == null) return null;
    return FeedbackAttachment(
      id: id,
      feedbackId: feedbackId,
      fileName: _asString(json['file_name']) ?? 'dosya',
      mimeType: _asString(json['mime_type']) ?? 'image/jpeg',
      sizeBytes: _asInt(json['size_bytes']) ?? 0,
      ready: json['status'] == 'ready',
    );
  }
}

/// Sunucudaki geri bildirim kaydı (gönderim yanıtı ve yönetici / sahip listesi).
@immutable
class FeedbackRecord {
  const FeedbackRecord({
    required this.id,
    required this.siteCode,
    required this.siteName,
    required this.userName,
    required this.role,
    required this.screenName,
    required this.screenRoute,
    required this.message,
    required this.appVersion,
    required this.platform,
    required this.createdAt,
    required this.attachments,
  });

  final int id;
  final int? siteCode;
  final String? siteName;
  final String userName;
  final String role;
  final String screenName;
  final String screenRoute;
  final String message;
  final String? appVersion;
  final String? platform;
  final DateTime? createdAt;
  final List<FeedbackAttachment> attachments;

  /// Sunucudaki rol anahtarının Türkçe karşılığı.
  String get roleLabel => feedbackRoleLabel(role);

  static FeedbackRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = _asInt(json['id']);
    if (id == null) return null;
    final attachments = <FeedbackAttachment>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is List) {
      for (final item in rawAttachments) {
        final parsed = FeedbackAttachment.fromJson(item);
        if (parsed != null) attachments.add(parsed);
      }
    }
    final createdAtRaw = _asString(json['created_at']);
    return FeedbackRecord(
      id: id,
      siteCode: _asInt(json['site_code']),
      siteName: _asString(json['site_name']),
      userName: _asString(json['user_name']) ?? 'Silinmiş Kullanıcı',
      role: _asString(json['role']) ?? '',
      screenName: _asString(json['screen_name']) ?? '',
      screenRoute: _asString(json['screen_route']) ?? '',
      message: _asString(json['message']) ?? '',
      appVersion: _asString(json['app_version']),
      platform: _asString(json['platform']),
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw)?.toLocal(),
      attachments: List<FeedbackAttachment>.unmodifiable(attachments),
    );
  }
}

/// Liste sayfası: kayıtlar + sonraki sayfanın imleci (yoksa null).
@immutable
class FeedbackPage {
  const FeedbackPage({required this.items, required this.nextCursor});

  final List<FeedbackRecord> items;
  final int? nextCursor;

  static FeedbackPage fromJson(Map<String, dynamic> json) {
    final items = <FeedbackRecord>[];
    final raw = json['items'];
    if (raw is List) {
      for (final item in raw) {
        final parsed = FeedbackRecord.fromJson(item);
        if (parsed != null) items.add(parsed);
      }
    }
    return FeedbackPage(items: items, nextCursor: _asInt(json['next_cursor']));
  }
}

/// Gönderimin sonucu: kayıt + eklerin kaçı yüklendi / yüklenemedi.
@immutable
class FeedbackSendOutcome {
  const FeedbackSendOutcome({
    required this.record,
    this.uploaded = 0,
    this.failed = 0,
  });

  final FeedbackRecord record;
  final int uploaded;
  final int failed;

  bool get allUploaded => failed == 0;
}

/// Sunucudaki rol anahtarlarının Türkçe karşılıkları (bilinmeyen anahtar olduğu gibi gösterilmez, genel ad verilir).
String feedbackRoleLabel(String role) => switch (role) {
  'super_user' => 'Süper kullanıcı',
  'site_manager' => 'Site yöneticisi',
  'site_owner' => 'Site sahibi',
  'site_admin' => 'Site yöneticisi',
  'board_member' => 'Kurul üyesi',
  'staff' => 'Görevli',
  'resident' => 'Sakin',
  'apartment_owner' => 'Daire sakini',
  'individual' => 'Bireysel kullanıcı',
  _ => 'Kullanıcı',
};

/// İstemci tarafı sınır denetimleri (sunucu aynılarını 400 ile doğrular).
abstract final class FeedbackRules {
  /// Seçilen dosyaların toplam boyutu.
  static int totalBytes(Iterable<int> sizes) => sizes.fold<int>(0, (sum, size) => sum + size);

  /// [candidate] baytlık dosya eklenirse toplam 20 MB'ı aşar mı? Aşarsa Türkçe ileti, aksi null.
  static String? checkAddition({required Iterable<int> existingSizes, required int candidate}) {
    if (candidate > kFeedbackAttachmentMaxBytes) {
      return 'Dosya çok büyük (${formatDocumentSize(candidate)}). Her dosya en fazla 5 MB olabilir.';
    }
    if (existingSizes.length >= kFeedbackAttachmentMax) {
      return 'En fazla $kFeedbackAttachmentMax dosya eklenebilir.';
    }
    if (totalBytes(existingSizes) + candidate > kFeedbackTotalMaxBytes) {
      return 'Dosyaların toplam boyutu en fazla 20 MB olabilir.';
    }
    return null;
  }

  /// Metin denetimi (kod noktası): boşsa / uzunsa Türkçe ileti, aksi null.
  static String? checkMessage(String? value) {
    final length = (value ?? '').trim().runes.length;
    if (length < 1) return 'Geri bildirim metni boş olamaz.';
    if (length > kFeedbackMessageMax) {
      return 'Geri bildirim en çok $kFeedbackMessageMax karakter olabilir.';
    }
    return null;
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _asString(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
