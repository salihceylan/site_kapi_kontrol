/// Kritik yetki olaylarının (hesap, site yöneticisi, site silme, katılım başvurusu, kapı özel izni, cihaz sahipliği) denetim eylemlerinin
/// Türkçe başlığı; bilinmeyen eylemde null (zincirdeki sonraki üretici dener). Sunucu bu olayların ayrıntısına yalnız kimlik, sayı, rol kodu ve
/// durum yazar: ad, e-posta, telefon, parola ve serbest metin kayda GİRMEZ.
String? accessAuditActionLabel(String action) {
  switch (action) {
    // Kullanıcı hesabı (süper kullanıcı işlemleri)
    case 'user.created':
      return 'Kullanıcı hesabı oluşturuldu';
    case 'user.updated':
      return 'Kullanıcı hesabı güncellendi';
    case 'user.role_changed':
      return 'Kullanıcı rolü değiştirildi';
    case 'user.password_set':
      return 'Kullanıcı için parola belirlendi';
    case 'user.activated':
      return 'Kullanıcı hesabı etkinleştirildi';
    case 'user.deactivated':
      return 'Kullanıcı hesabı pasifleştirildi';
    case 'user.deleted':
      return 'Kullanıcı hesabı kalıcı silindi';
    case 'user.subscription_approved':
      return 'Yönetici abonelik talebi onaylandı';
    case 'user.subscription_rejected':
      return 'Yönetici abonelik talebi reddedildi';
    // Site yöneticisi ve site silme
    case 'site_manager.added':
      return 'Site yöneticisi eklendi';
    case 'site_manager.invited':
      return 'Site yöneticisi daveti gönderildi';
    case 'site_manager.invitation_revoked':
      return 'Site yöneticisi daveti iptal edildi';
    case 'site_manager.removed':
      return 'Site yöneticisi çıkarıldı';
    case 'site.deleted':
      return 'Site silindi';
    case 'site.deletion_requested':
      return 'Site silme talebi oluşturuldu';
    case 'site.deletion_cancelled':
      return 'Site silme talebi iptal edildi';
    case 'site.deletion_code_locked':
      return 'Site silme doğrulaması kilitlendi';
    // Site ve daire hesabı (süper kullanıcı işlemleri)
    case 'site.created':
      return 'Site oluşturuldu';
    case 'site.approved':
      return 'Site talebi onaylandı';
    case 'site.rejected':
      return 'Site talebi reddedildi';
    case 'site.updated':
      return 'Site bilgileri güncellendi';
    case 'apartment.resident_set':
      return 'Daire hesabı tanımlandı';
    case 'apartment.resident_cleared':
      return 'Daire hesabı sıfırlandı';
    // Katılım başvurusu
    case 'join_request.approved':
      return 'Katılım başvurusu onaylandı';
    case 'join_request.rejected':
      return 'Katılım başvurusu reddedildi';
    // Kapı özel izni
    case 'door_permission.granted':
      return 'Kapı özel izni verildi';
    case 'door_permission.denied':
      return 'Kapı erişimi engellendi (özel izin)';
    case 'door_permission.removed':
      return 'Kapı özel izni kaldırıldı';
    case 'door_permission.bulk_granted':
      return 'Toplu kapı özel izni verildi';
    case 'door_permission.bulk_denied':
      return 'Toplu kapı erişimi engellendi';
    case 'door_permission.bulk_removed':
      return 'Toplu kapı özel izni kaldırıldı';
    // Cihaz sahipliği
    case 'device.ownership_released':
      return 'Cihaz sahipliği sıfırlandı';
  }
  return null;
}
