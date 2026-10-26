// Kritik yetki olaylarının denetim kaydı (hesap, site yöneticisi, site silme, katılım başvurusu, kapı özel izni, cihaz sahipliği): Türkçe eylem
// etiketi, süzgeç satırı (kayıt etiketiyle AYNI), kart tonu ve hedef etiketi. Sunucu bu olayların ayrıntısına yalnız kimlik, sayı, rol kodu ve durum
// yazar; hedef etiketi hiçbir ad / e-posta göstermez.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/access_audit_label.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart' show AppTone;
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart' show AuditLogView;
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart' show auditToneOf;

void main() {
  const labels = <String, String>{
    'user.created': 'Kullanıcı hesabı oluşturuldu',
    'user.updated': 'Kullanıcı hesabı güncellendi',
    'user.role_changed': 'Kullanıcı rolü değiştirildi',
    'user.password_set': 'Kullanıcı için parola belirlendi',
    'user.activated': 'Kullanıcı hesabı etkinleştirildi',
    'user.deactivated': 'Kullanıcı hesabı pasifleştirildi',
    'user.deleted': 'Kullanıcı hesabı kalıcı silindi',
    'user.subscription_approved': 'Yönetici abonelik talebi onaylandı',
    'user.subscription_rejected': 'Yönetici abonelik talebi reddedildi',
    'site_manager.added': 'Site yöneticisi eklendi',
    'site_manager.invited': 'Site yöneticisi daveti gönderildi',
    'site_manager.invitation_revoked': 'Site yöneticisi daveti iptal edildi',
    'site_manager.removed': 'Site yöneticisi çıkarıldı',
    'site.deleted': 'Site silindi',
    'site.deletion_requested': 'Site silme talebi oluşturuldu',
    'site.deletion_cancelled': 'Site silme talebi iptal edildi',
    'site.deletion_code_locked': 'Site silme doğrulaması kilitlendi',
    'site.created': 'Site oluşturuldu',
    'site.approved': 'Site talebi onaylandı',
    'site.rejected': 'Site talebi reddedildi',
    'site.updated': 'Site bilgileri güncellendi',
    'apartment.resident_set': 'Daire hesabı tanımlandı',
    'apartment.resident_cleared': 'Daire hesabı sıfırlandı',
    'join_request.approved': 'Katılım başvurusu onaylandı',
    'join_request.rejected': 'Katılım başvurusu reddedildi',
    'door_permission.granted': 'Kapı özel izni verildi',
    'door_permission.denied': 'Kapı erişimi engellendi (özel izin)',
    'door_permission.removed': 'Kapı özel izni kaldırıldı',
    'door_permission.bulk_granted': 'Toplu kapı özel izni verildi',
    'door_permission.bulk_denied': 'Toplu kapı erişimi engellendi',
    'door_permission.bulk_removed': 'Toplu kapı özel izni kaldırıldı',
    'device.ownership_released': 'Cihaz sahipliği sıfırlandı',
  };

  AuditLogEntry entry(
    String action, {
    String? targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) =>
      AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': action,
        'target_type': targetType,
        'target_id': targetId,
        'details': details ?? <String, dynamic>{},
      });

  group('denetim kaydı etiketleri (yetki olayları)', () {
    test('her eylemin Türkçe etiketi vardır; kayıt etiketiyle süzgeç etiketi aynıdır ve süzgeç değerleri tekrarlanmaz', () {
      for (final item in labels.entries) {
        expect(accessAuditActionLabel(item.key), item.value, reason: item.key);
        expect(entry(item.key).actionLabel, item.value, reason: item.key);
        final filters = AuditLogView.actionFilters.where((f) => f.$1 == item.key).toList();
        expect(filters, hasLength(1), reason: 'süzgeç: ${item.key}');
        expect(filters.single.$2, item.value, reason: item.key);
      }
      final values = AuditLogView.actionFilters.map((f) => f.$1).toList();
      expect(values.toSet().length, values.length, reason: 'süzgeç değerleri tekrarlanmaz');
    });

    test('bilinmeyen eylem etiketsiz (null) ve kayıtta "Diğer işlem"; ham kod gösterilmez', () {
      expect(accessAuditActionLabel('user.xyz'), isNull);
      expect(accessAuditActionLabel('site.archived'), isNull);
      expect(entry('user.xyz').actionLabel, 'Diğer işlem');
      expect(entry('door_permission.xyz').actionLabel, 'Diğer işlem');
    });

    test('kart tonları: ekleme / onay success; yetki değişimi / engel / talep warning; kaldırma / iptal neutral; silme / ret danger; güncelleme info', () {
      for (final a in <String>[
        'user.created',
        'user.activated',
        'user.subscription_approved',
        'site_manager.added',
        'site_manager.invited',
        'join_request.approved',
        'door_permission.granted',
        'door_permission.bulk_granted',
      ]) {
        expect(auditToneOf(a), AppTone.success, reason: a);
      }
      for (final a in <String>[
        'user.deactivated',
        'user.role_changed',
        'user.password_set',
        'site.deletion_requested',
        'site.deletion_code_locked',
        'door_permission.denied',
        'door_permission.bulk_denied',
        'device.ownership_released',
      ]) {
        expect(auditToneOf(a), AppTone.warning, reason: a);
      }
      for (final a in <String>[
        'site_manager.invitation_revoked',
        'site_manager.removed',
        'site.deletion_cancelled',
        'door_permission.removed',
        'door_permission.bulk_removed',
      ]) {
        expect(auditToneOf(a), AppTone.neutral, reason: a);
      }
      for (final a in <String>['user.deleted', 'user.subscription_rejected', 'site.deleted', 'join_request.rejected']) {
        expect(auditToneOf(a), AppTone.danger, reason: a);
      }
      expect(auditToneOf('user.updated'), AppTone.info);
    });
  });

  group('hedef etiketi (yetki olayları)', () {
    test('kullanıcı: kod + rol adı; rol değişiminde "eski → yeni"; kapı izninde kapı numarası; bilinmeyen rol kodu olduğu gibi', () {
      expect(
        entry('user.created', targetType: 'user', targetId: '41', details: <String, dynamic>{'role': 'individual', 'is_active': false}).targetLabel,
        'Kullanıcı 41 • Bireysel Kullanıcı',
      );
      expect(
        entry('user.deleted', targetType: 'user', targetId: '41', details: <String, dynamic>{'role': 'site_manager'}).targetLabel,
        'Kullanıcı 41 • Site Yöneticisi',
      );
      expect(
        entry('user.role_changed', targetType: 'user', targetId: '41', details: <String, dynamic>{'old_role': 'site_manager', 'new_role': 'super_user'}).targetLabel,
        'Kullanıcı 41 • Site Yöneticisi → Süper Kullanıcı',
      );
      expect(
        entry('user.role_changed', targetType: 'user', targetId: '41', details: <String, dynamic>{'new_role': 'individual'}).targetLabel,
        'Kullanıcı 41 • ? → Bireysel Kullanıcı',
      );
      expect(entry('user.updated', targetType: 'user', targetId: '41', details: <String, dynamic>{'fields': <String>['full_name']}).targetLabel, 'Kullanıcı 41');
      expect(
        entry('site_manager.removed', targetType: 'user', targetId: '9', details: <String, dynamic>{'role': 'SITE_ADMIN', 'new_user_role': 'individual'}).targetLabel,
        'Kullanıcı 9 • Site Yöneticisi',
      );
      expect(
        entry('door_permission.granted', targetType: 'user', targetId: '77', details: <String, dynamic>{'door_id': 12, 'is_allowed': true}).targetLabel,
        'Kullanıcı 77 • Kapı #12',
      );
      expect(entry('user.created', targetType: 'user', targetId: '5', details: <String, dynamic>{'role': 'yeni_rol'}).targetLabel, 'Kullanıcı 5 • yeni_rol');
    });

    test('mevcut ek rol etiketleri değişmez', () {
      expect(
        entry('staff_role.assigned', targetType: 'user', targetId: '42', details: <String, dynamic>{'role': 'BOARD_MEMBER'}).targetLabel,
        'Kullanıcı 42 • Yönetim Kurulu / Denetçi',
      );
      expect(
        entry('staff_role.removed', targetType: 'user', targetId: '42', details: <String, dynamic>{'role': 'STAFF'}).targetLabel,
        'Kullanıcı 42 • Görevli',
      );
    });

    test('site, davet, başvuru, toplu kapı izni, cihaz: yalnız numara / sayı / rol; ad ve e-posta gösterilmez', () {
      expect(entry('site.deleted', targetType: 'site', targetId: '42', details: <String, dynamic>{'device_count': 2}).targetLabel, 'Site #42');
      expect(entry('site_manager.invited', targetType: 'site_manager_invitation', targetId: '412', details: <String, dynamic>{'expires_in_days': 7}).targetLabel, 'Davet #412');
      expect(
        entry('join_request.approved', targetType: 'join_request', targetId: '9', details: <String, dynamic>{'user_code': 77, 'apartment_id': 3, 'assigned_role': 'APARTMENT_ADMIN'}).targetLabel,
        'Başvuru #9 • Kullanıcı 77 • Daire Yöneticisi',
      );
      expect(
        entry('join_request.rejected', targetType: 'join_request', targetId: '9', details: <String, dynamic>{'user_code': 77, 'apartment_id': 3, 'has_reason': true}).targetLabel,
        'Başvuru #9 • Kullanıcı 77',
      );
      expect(
        entry('door_permission.bulk_granted', targetType: 'door', targetId: '12', details: <String, dynamic>{'door_id': 12, 'scope': 'block', 'count': 24}).targetLabel,
        'Kapı #12 • 24 kişi',
      );
      expect(entry('door_permission.bulk_removed', targetType: 'door', targetId: '12').targetLabel, 'Kapı #12');
      expect(entry('device.ownership_released', targetType: 'device', targetId: '3', details: <String, dynamic>{'previous_owner_id': 8}).targetLabel, 'Cihaz #3');
      expect(entry('site.deleted', targetType: 'site').targetLabel, isNull);
      expect(entry('site.deleted', targetType: 'site', targetId: '').targetLabel, isNull);
    });
  });
}
