// Komşu Panosu (`neighbor_board`) ilan modeli. Sunucu: server/src/modules/neighbor_board_routes.js.

/// İlan durumları (sunucuyla aynı kodlar).
class NeighborPostStatus {
  static const String pending = 'pending';
  static const String published = 'published';
  static const String rejected = 'rejected';
  static const String removed = 'removed';
  static const String withdrawn = 'withdrawn';

  static String label(String status) => switch (status) {
    pending => 'Onay bekliyor',
    published => 'Yayında',
    rejected => 'Reddedildi',
    removed => 'Kaldırıldı',
    withdrawn => 'Geri çekildi',
    _ => status,
  };
}

class NeighborPost {
  const NeighborPost({
    required this.id,
    required this.siteCode,
    required this.title,
    required this.body,
    required this.status,
    required this.authorName,
    this.createdAt,
    this.isMine = false,
    this.decisionNote,
    this.reportCount = 0,
    this.reportReasons = const <String>[],
  });

  final int id;
  final int siteCode;
  final String title;
  final String body;
  final String status;
  final String authorName;
  final DateTime? createdAt;
  final bool isMine;
  final String? decisionNote;
  final int reportCount;
  final List<String> reportReasons;

  factory NeighborPost.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final reasons = json['report_reasons'];
    final note = json['decision_note'];
    return NeighborPost(
      id: asInt(json['id']),
      siteCode: asInt(json['site_code']),
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      status: '${json['status'] ?? ''}',
      authorName: '${json['author_name'] ?? ''}',
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      isMine: json['is_mine'] == true,
      decisionNote: note is String && note.trim().isNotEmpty ? note.trim() : null,
      reportCount: asInt(json['report_count']),
      reportReasons: reasons is List ? <String>[for (final r in reasons) '$r'] : const <String>[],
    );
  }
}
