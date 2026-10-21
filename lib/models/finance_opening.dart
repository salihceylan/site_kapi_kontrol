// Devir bakiyesi yüklemeleri ve geri alma modelleri (F4; docs/PLATFORM_FINANS.md "Devir bakiyesi").
import 'package:flutter/foundation.dart';

int _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

/// `GET finance/opening-balances` içindeki bir yükleme.
@immutable
class OpeningRun {
  const OpeningRun({
    required this.id,
    required this.createdAt,
    required this.cutoverDate,
    required this.entryCount,
    required this.totalMinor,
    required this.reverted,
  });

  factory OpeningRun.fromJson(Map<String, dynamic> json) => OpeningRun(
    id: _int(json['id']),
    createdAt: DateTime.tryParse('${json['created_at']}'),
    cutoverDate: json['cutover_date'] is String ? json['cutover_date'] as String : null,
    entryCount: _int(json['entry_count']),
    totalMinor: _int(json['total_minor']),
    reverted: json['reverted'] == true,
  );

  final int id;
  final DateTime? createdAt;
  final String? cutoverDate;
  final int entryCount;
  final int totalMinor;
  final bool reverted;
}

/// Geri alma önizlemesi (`GET finance/opening-balances/:runId`).
@immutable
class OpeningRevertPreview {
  const OpeningRevertPreview({
    required this.run,
    required this.entriesToReverse,
    required this.totalMinor,
    required this.individuallyCancelled,
    required this.apartmentsWithLaterPayments,
    required this.lateFeeEntriesAfter,
  });

  factory OpeningRevertPreview.fromJson(Map<String, dynamic> json) {
    final run = json['run'];
    final revert = json['revert'];
    if (run is! Map || revert is! Map) throw const FormatException('Devir ayrıntısı okunamadı.');
    return OpeningRevertPreview(
      run: OpeningRun.fromJson(Map<String, dynamic>.from(run)),
      entriesToReverse: _int(revert['entries_to_reverse']),
      totalMinor: _int(revert['total_minor']),
      individuallyCancelled: _int(revert['individually_cancelled']),
      apartmentsWithLaterPayments: _int(revert['apartments_with_later_payments']),
      lateFeeEntriesAfter: _int(revert['late_fee_entries_after']),
    );
  }

  final OpeningRun run;
  final int entriesToReverse;
  final int totalMinor;
  final int individuallyCancelled;
  final int apartmentsWithLaterPayments;
  final int lateFeeEntriesAfter;
}
