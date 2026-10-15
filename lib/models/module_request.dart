import 'package:flutter/foundation.dart';

/// Modül talebi durumları (`module_requests.status`).
abstract final class ModuleRequestStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String cancelled = 'cancelled';
}

/// Site yöneticisinin bir modül için süper kullanıcıya ilettiği talep (Platform Faz 1.1).
///
/// Satın alma sistemi yapılana kadar yönetici modülü kendi açmaz, TALEP eder; süper kullanıcı
/// onaylarsa modül siteye tanımlanır. Sunucu gövdesi: `{ id, site_code, site_name, module_code,
/// module_name, status, note, requested_by_name, created_at, decided_by_name, decided_at,
/// decision_note }`.
@immutable
class ModuleRequest {
  const ModuleRequest({
    required this.id,
    required this.siteCode,
    required this.moduleCode,
    this.siteName = '',
    this.moduleName = '',
    this.status = ModuleRequestStatus.pending,
    this.note,
    this.requestedByName,
    this.createdAt,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final String moduleCode;
  final String moduleName;

  /// `pending`, `approved`, `rejected` ya da `cancelled`.
  final String status;
  final String? note;
  final String? requestedByName;
  final DateTime? createdAt;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionNote;

  bool get isPending => status == ModuleRequestStatus.pending;

  /// Okunur durum adı; bilinmeyen değerde ham değer (kayıt kaybolmaz).
  String get statusLabel {
    switch (status) {
      case ModuleRequestStatus.pending:
        return 'Bekliyor';
      case ModuleRequestStatus.approved:
        return 'Onaylandı';
      case ModuleRequestStatus.rejected:
        return 'Reddedildi';
      case ModuleRequestStatus.cancelled:
        return 'Geri çekildi';
      default:
        return status;
    }
  }

  /// Modül adı yoksa kodu gösterir.
  String get moduleLabel => moduleName.trim().isEmpty ? moduleCode : moduleName;

  factory ModuleRequest.fromJson(Map<String, dynamic> json) {
    int asInt(Object? raw) {
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    String? text(Object? raw) {
      if (raw == null) return null;
      final value = raw.toString().trim();
      return value.isEmpty ? null : value;
    }

    DateTime? date(Object? raw) =>
        raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();

    return ModuleRequest(
      id: asInt(json['id']),
      siteCode: asInt(json['site_code']),
      siteName: json['site_name']?.toString() ?? '',
      moduleCode: json['module_code']?.toString() ?? '',
      moduleName: json['module_name']?.toString() ?? '',
      status: json['status']?.toString() ?? ModuleRequestStatus.pending,
      note: text(json['note']),
      requestedByName: text(json['requested_by_name']),
      createdAt: date(json['created_at']),
      decidedByName: text(json['decided_by_name']),
      decidedAt: date(json['decided_at']),
      decisionNote: text(json['decision_note']),
    );
  }
}

/// `GET /admin/module-requests` sayfası: `id DESC` satırlar, sonraki sayfa için `before_id` ve
/// süzgeçten bağımsız toplam bekleyen sayısı (`pending_count`; çekmece rozeti).
@immutable
class ModuleRequestPage {
  const ModuleRequestPage({
    this.items = const <ModuleRequest>[],
    this.nextBeforeId,
    this.pendingCount = 0,
  });

  final List<ModuleRequest> items;
  final int? nextBeforeId;
  final int pendingCount;

  bool get hasMore => nextBeforeId != null;

  factory ModuleRequestPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final next = json['next_before_id'];
    final pending = json['pending_count'];
    return ModuleRequestPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => ModuleRequest.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <ModuleRequest>[],
      nextBeforeId: next is num
          ? next.toInt()
          : (next == null ? null : int.tryParse(next.toString())),
      pendingCount: pending is num
          ? pending.toInt()
          : (int.tryParse(pending?.toString() ?? '') ?? 0),
    );
  }
}
