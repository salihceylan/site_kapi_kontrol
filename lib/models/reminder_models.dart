import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/finance_4b.dart';

/// Borç hatırlatma modelleri (Platform Faz 4b, Ö6; sözleşme: docs/PLATFORM_FINANS_4B.md "Ö6").
///
/// Hatırlatma, bilgilendirme e-postasıdır (tanıtım değil). Önizleme adres / ad DÖNDÜRMEZ; çalıştırma
/// istatistiği alıcı adı / adresi içermez (kurul okuyabilir).

/// Hatırlatma notunda bağlantı / alan adı / e-posta benzeri içerik (kimlik avı riski): sunucu notu 400 ile REDDEDER; istemci aynı
/// kuralı gönderimden ÖNCE uygular (sunucudaki `NOTE_LINK_PATTERN` ile aynı).
final RegExp _reminderNoteLink = RegExp(
  r'(?:[a-z][a-z0-9+.-]*:\/\/|www\.|\S@\S|\b[a-z0-9-]+\.(?:com|net|org|info|biz|xyz|link|ly|me|co|io|ru|cn|top|tr)\b)',
  caseSensitive: false,
);

bool reminderNoteHasLink(String note) => _reminderNoteLink.hasMatch(note);

enum ReminderTone {
  friendly('friendly', 'Nazik hatırlatma', 'Daha yumuşak bir dil: "Merhaba, ..." diye başlar.'),
  standard('standard', 'Resmî hatırlatma', 'Aynı içerik, "Sayın site sakini" hitabıyla.');

  const ReminderTone(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;

  static ReminderTone fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final tone in values) {
        if (tone.apiValue == normalized) return tone;
      }
    }
    return friendly;
  }
}

/// Muafiyet listesi satırı (anlaşmazlık / dava altındaki daire).
@immutable
class ReminderExclusion {
  const ReminderExclusion({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.reason,
    this.createdAt,
  });

  final int apartmentId;
  final String label;
  final String? blockName;
  final String? reason;
  final DateTime? createdAt;

  factory ReminderExclusion.fromJson(Map<String, dynamic> json) {
    final apartment = f4Map(json['apartment']);
    return ReminderExclusion(
      apartmentId: f4Int(json['apartment_id'] ?? apartment['id']),
      label: f4Str(json['label'] ?? apartment['label']),
      blockName: f4Text(json['block_name'] ?? apartment['block_name']),
      reason: f4Text(json['reason']),
      createdAt: announcementInstant(json['created_at']),
    );
  }
}

/// Önizlemede hariç tutulma nedenlerine göre daire sayıları.
@immutable
class ReminderExcludedCounts {
  const ReminderExcludedCounts({
    this.amount = 0,
    this.days = 0,
    this.interval = 0,
    this.consecutive = 0,
    this.exclusion = 0,
    this.noRecipient = 0,
  });

  final int amount;
  final int days;
  final int interval;
  final int consecutive;
  final int exclusion;
  final int noRecipient;

  int get total => amount + days + interval + consecutive + exclusion + noRecipient;

  factory ReminderExcludedCounts.fromJson(Map<String, dynamic> json) => ReminderExcludedCounts(
    amount: f4Int(json['amount']),
    days: f4Int(json['days']),
    interval: f4Int(json['interval']),
    consecutive: f4Int(json['consecutive']),
    exclusion: f4Int(json['exclusion']),
    noRecipient: f4Int(json['no_recipient']),
  );
}

/// `POST reminders/preview` (YAZMAZ). Adres / ad DÖNMEZ.
@immutable
class ReminderPreview {
  const ReminderPreview({
    required this.apartmentCount,
    required this.personCount,
    this.withAmountCount = 0,
    this.withoutAmountCount = 0,
    this.noAddressCount = 0,
    this.skippedPrefCount = 0,
    this.duplicateCount = 0,
    this.cappedCount = 0,
    this.totalOverdueMinor,
    this.excluded = const ReminderExcludedCounts(),
    this.handFollowUpCount = 0,
    this.handFollowUpApartments = const <String>[],
    this.sampleApartments = const <String>[],
    this.smtpConfigured = true,
    this.previewHash,
    this.blockers = const <String>[],
  });

  final int apartmentCount;
  final int personCount;
  final int withAmountCount;
  final int withoutAmountCount;
  final int noAddressCount;
  final int skippedPrefCount;
  final int duplicateCount;
  final int cappedCount;
  final int? totalOverdueMinor;
  final ReminderExcludedCounts excluded;

  /// Ardışık hatırlatma sınırına ulaşan, "Elden takip" listesine düşen daire sayısı (e-posta GİTMEZ).
  final int handFollowUpCount;

  /// Elden takip listesindeki dairelerin etiketleri (en çok 20; yalnız daire etiketi, kişi adı / adres YOK).
  final List<String> handFollowUpApartments;
  final List<String> sampleApartments;
  final bool smtpConfigured;
  final String? previewHash;
  final List<String> blockers;

  /// Gönderilebilir alıcı var mı?
  bool get hasRecipients => personCount > 0;

  factory ReminderPreview.fromJson(Map<String, dynamic> json) => ReminderPreview(
    apartmentCount: f4Int(json['apartment_count']),
    personCount: f4Int(json['person_count']),
    withAmountCount: f4Int(json['with_amount_count']),
    withoutAmountCount: f4Int(json['without_amount_count']),
    noAddressCount: f4Int(json['no_address_count']),
    skippedPrefCount: f4Int(json['skipped_pref_count']),
    duplicateCount: f4Int(json['duplicate_count']),
    cappedCount: f4Int(json['capped_count']),
    totalOverdueMinor: f4MinorOrNull(json, 'total_overdue_minor'),
    excluded: ReminderExcludedCounts.fromJson(f4Map(json['excluded'])),
    handFollowUpCount: f4Int(json['hand_follow_up_count']),
    handFollowUpApartments: <String>[
      for (final s in (json['hand_follow_up_apartments'] is List ? json['hand_follow_up_apartments'] as List : const <Object?>[]))
        if (s != null && s.toString().trim().isNotEmpty) s.toString(),
    ],
    sampleApartments: <String>[
      for (final s in (json['sample_apartments'] is List ? json['sample_apartments'] as List : const <Object?>[]))
        if (s != null && s.toString().trim().isNotEmpty) s.toString(),
    ],
    smtpConfigured: f4Bool(json['smtp_configured'], fallback: true),
    previewHash: f4Text(json['preview_hash']),
    blockers: <String>[
      for (final b in (json['blockers'] is List ? json['blockers'] as List : const <Object?>[]))
        if (b != null) b.toString(),
    ],
  );
}

/// Çalıştırma istatistiği (alıcı sayıları; ad / adres YOK).
@immutable
class ReminderRunStats {
  const ReminderRunStats({
    this.pending = 0,
    this.sent = 0,
    this.failed = 0,
    this.noAddress = 0,
    this.skippedPref = 0,
    this.duplicate = 0,
    this.capped = 0,
    this.resolved = 0,
    this.cancelled = 0,
  });

  final int pending;
  final int sent;
  final int failed;
  final int noAddress;
  final int skippedPref;
  final int duplicate;
  final int capped;
  final int resolved;
  final int cancelled;

  int get total => pending + sent + failed + noAddress + skippedPref + duplicate + capped + resolved + cancelled;

  factory ReminderRunStats.fromJson(Map<String, dynamic> json) => ReminderRunStats(
    pending: f4Int(json['pending']),
    sent: f4Int(json['sent']),
    failed: f4Int(json['failed']),
    noAddress: f4Int(json['no_address']),
    skippedPref: f4Int(json['skipped_pref']),
    duplicate: f4Int(json['duplicate']),
    capped: f4Int(json['capped']),
    resolved: f4Int(json['resolved']),
    cancelled: f4Int(json['cancelled']),
  );
}

/// Hatırlatma çalıştırması.
@immutable
class ReminderRun {
  const ReminderRun({
    required this.id,
    this.status = 'active',
    this.tone = ReminderTone.friendly,
    this.note,
    this.apartmentCount = 0,
    this.personCount = 0,
    this.withAmountCount = 0,
    this.stats = const ReminderRunStats(),
    this.createdAt,
    this.cancelledAt,
  });

  final int id;

  /// `active` / `cancelled`.
  final String status;
  final ReminderTone tone;
  final String? note;
  final int apartmentCount;
  final int personCount;
  final int withAmountCount;
  final ReminderRunStats stats;
  final DateTime? createdAt;
  final DateTime? cancelledAt;

  bool get isCancelled => status == 'cancelled';

  /// İptal edilebilir mi? (Bekleyen satır var ve çalıştırma iptal edilmemiş.)
  bool get canCancel => !isCancelled && stats.pending > 0;

  factory ReminderRun.fromJson(Map<String, dynamic> json) {
    final statsSource = json['stats'] is Map ? f4Map(json['stats']) : json;
    return ReminderRun(
      id: f4Int(json['id']),
      status: f4Str(json['status'], 'active'),
      tone: ReminderTone.fromApi(json['tone']),
      note: f4Text(json['note']),
      apartmentCount: f4Int(json['apartment_count']),
      personCount: f4Int(json['person_count']),
      withAmountCount: f4Int(json['with_amount_count']),
      stats: ReminderRunStats.fromJson(statsSource),
      createdAt: announcementInstant(json['created_at']),
      cancelledAt: announcementInstant(json['cancelled_at']),
    );
  }
}

@immutable
class ReminderRunPage {
  const ReminderRunPage({this.items = const <ReminderRun>[], this.total = 0});

  final List<ReminderRun> items;
  final int total;

  factory ReminderRunPage.fromJson(Map<String, dynamic> json) {
    final items = f4List(json['items'], ReminderRun.fromJson);
    return ReminderRunPage(items: items, total: f4Int(json['total'], items.length));
  }
}

/// `POST reminders/send` yanıtı.
@immutable
class ReminderSendResult {
  const ReminderSendResult({required this.run, required this.created});

  final ReminderRun run;

  /// 201 = yeni çalıştırma, 200 = aynı anahtarla tekrar (kayıt döndü).
  final bool created;
}
