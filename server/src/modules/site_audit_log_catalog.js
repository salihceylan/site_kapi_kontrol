// Site yöneticisinin "İşlem kayıtları" ekranı: eylem katalogu (kategori + Türkçe başlık) ve görünürlük kuralı.
//
// Sözleşme: docs/PLATFORM_ISLEM_KAYITLARI.md. DB'ye dokunmaz; saf veri + küçük saf yardımcılar (birim testlenir).
//
// GİZLİLİK İLKESİ (varsayılan KAPALI): yöneticiye YALNIZ bir kategorinin öneki / tam adıyla eşleşen ve GİZLİ listede
// olmayan eylemler gösterilir. Kataloğa girmeyen yeni bir eylem (başka bir dalgada eklenen modül dahil) yönetici
// listesinde görünmez; görünür olması için bu dosyaya bilinçli olarak eklenmelidir. Gizli liste her zaman önceliklidir.
//
// Süper kullanıcının tüm siteleri gören denetim ekranı (GET /admin/audit-log) bu katalogdan ETKİLENMEZ.

/**
 * Kategori = filtre seçeneği ("İşlem türü"). `prefixes` noktayla biten eylem aileleri ("finance."), `actions` tam adlardır.
 * Sıra, ekrandaki açılır listenin sırasıdır.
 */
export const SITE_AUDIT_CATEGORIES = Object.freeze([
  Object.freeze({ key: 'modules', label: 'Modüller', prefixes: Object.freeze(['module.', 'module_request.']), actions: Object.freeze([]) }),
  Object.freeze({
    key: 'roles',
    label: 'Yetki ve roller',
    prefixes: Object.freeze(['staff_role.', 'site_manager.', 'team.', 'join_request.']),
    actions: Object.freeze([]),
  }),
  Object.freeze({
    key: 'access',
    label: 'Kapı ve geçiş',
    prefixes: Object.freeze(['door_permission.', 'access_card.', 'plate.', 'device.']),
    actions: Object.freeze([]),
  }),
  Object.freeze({
    key: 'people',
    label: 'Kişi ve daire kayıtları',
    prefixes: Object.freeze(['person.', 'residency.', 'apartment.', 'apartment_mgmt.', 'vehicle.', 'directory.', 'people.', 'import.']),
    actions: Object.freeze(['export']),
  }),
  Object.freeze({ key: 'finance', label: 'Aidat ve finans', prefixes: Object.freeze(['finance.', 'budget.', 'metering.']), actions: Object.freeze([]) }),
  Object.freeze({ key: 'announcements', label: 'Duyurular', prefixes: Object.freeze(['announcement.']), actions: Object.freeze([]) }),
  Object.freeze({ key: 'documents', label: 'Dosya deposu', prefixes: Object.freeze(['document.', 'drive.']), actions: Object.freeze([]) }),
  Object.freeze({
    key: 'services',
    label: 'Site hizmetleri',
    prefixes: Object.freeze([
      'work_item.',
      'reservation.',
      'reservation_area.',
      'concierge.',
      'survey.',
      'visitor_entry.',
      'board_decision.',
      'contract.',
      'contract_vendor.',
      'equipment.',
      'quote.',
      'cctv.',
      'annual_report.',
      'neighbor_board.',
    ]),
    actions: Object.freeze([]),
  }),
  Object.freeze({
    key: 'settings',
    label: 'Site ayarları',
    prefixes: Object.freeze(['site.', 'brand_theme.', 'management_company.', 'platform_rule.', 'emergency.']),
    actions: Object.freeze([]),
  }),
]);

export const SITE_AUDIT_CATEGORY_KEYS = Object.freeze(SITE_AUDIT_CATEGORIES.map((category) => category.key));

/**
 * Yöneticiye ASLA gösterilmeyen eylemler (kategorilerden önceliklidir).
 *  - residency_log.*: adli kayıt görüntüleme / dökümü (resmî talep gizliliği; yalnız süper kullanıcı okur).
 *  - safety_request.*, access_suspension.*: sakinin GİZLİ güvenlik talebi ve kapı erişimi askıya alma
 *    (docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md: talep eden ve haneye bildirim gitmez).
 *  - apartment_mgmt.person_search, search_visibility_changed: sakinin kişi arama / aranabilirlik tercihi (kişisel).
 *  - account.*, user.*: hesap silme / dışa aktarma ve süper kullanıcının hesap yönetimi (siteye bağlı değildir).
 *  - platform_config.*, platform_settings.*, subscription.*, site_application.*: platform düzeyi işlemler.
 */
export const SITE_AUDIT_HIDDEN_PREFIXES = Object.freeze([
  'residency_log.',
  'safety_request.',
  'access_suspension.',
  'account.',
  'user.',
  'platform_config.',
  'platform_settings.',
  'subscription.',
  'site_application.',
]);

export const SITE_AUDIT_HIDDEN_ACTIONS = Object.freeze(['apartment_mgmt.person_search', 'apartment_mgmt.search_visibility_changed']);

/** Eylem -> Türkçe başlık. Kategoride olup burada olmayan eylem "<Kategori> işlemi" başlığı alır. */
export const SITE_AUDIT_LABELS = Object.freeze({
  // Modüller
  'module.enabled': 'Modül açıldı',
  'module.disabled': 'Modül kapatıldı',
  'module_request.created': 'Modül talebi oluşturuldu',
  'module_request.approved': 'Modül talebi onaylandı',
  'module_request.rejected': 'Modül talebi reddedildi',
  'module_request.cancelled': 'Modül talebi geri çekildi',

  // Yetki ve roller
  'staff_role.assigned': 'Ek rol atandı',
  'staff_role.removed': 'Ek rol kaldırıldı',
  'site_manager.added': 'Site yöneticisi eklendi',
  'site_manager.invited': 'Site yöneticisi daveti gönderildi',
  'site_manager.invitation_revoked': 'Site yöneticisi daveti iptal edildi',
  'site_manager.removed': 'Site yöneticisi çıkarıldı',
  'team.duty_assigned': 'Görev atandı',
  'team.duty_ended': 'Görev sona erdi',
  'join_request.approved': 'Katılım başvurusu onaylandı',
  'join_request.rejected': 'Katılım başvurusu reddedildi',

  // Kapı ve geçiş
  'door_permission.granted': 'Kapı özel izni verildi',
  'door_permission.denied': 'Kapı erişimi engellendi (özel izin)',
  'door_permission.removed': 'Kapı özel izni kaldırıldı',
  'door_permission.bulk_granted': 'Toplu kapı özel izni verildi',
  'door_permission.bulk_denied': 'Toplu kapı erişimi engellendi',
  'door_permission.bulk_removed': 'Toplu kapı özel izni kaldırıldı',
  'access_card.created': 'Geçiş kartı tanımlandı',
  'access_card.revoked': 'Geçiş kartı iptal edildi',
  'plate.permit_created': 'Misafir plakası izni verildi',
  'plate.permit_revoked': 'Misafir plakası izni iptal edildi',
  'plate.blacklist_added': 'Plaka kara listeye eklendi',
  'plate.blacklist_removed': 'Plaka kara listeden çıkarıldı',
  'plate.settings_changed': 'Plaka kapı ayarı değişti',
  'plate.auto_open': 'Plakayla otomatik açma kaydı',
  'device.ownership_released': 'Cihaz sahipliği sıfırlandı',

  // Kişi ve daire kayıtları
  'person.created': 'Kişi eklendi',
  'person.updated': 'Kişi bilgisi güncellendi',
  'person.deactivated': 'Kişi pasifleştirildi',
  'person.account_created': 'Kişi için hesap açıldı',
  'person.account_password_reset': 'Kişinin hesap parolası sıfırlandı',
  'person.password_reset_sent': 'Parola sıfırlama bağlantısı gönderildi',
  'person.pin_reset': "Kişinin PIN'i sıfırlandı",
  'person.invitation_sent': 'Uygulama daveti gönderildi',
  'person.invitation_revoked': 'Uygulama daveti iptal edildi',
  'person.invitation_declined': 'Uygulama daveti reddedildi',
  'person.invitation_accepted': 'Uygulama daveti kabul edildi',
  'residency.added': 'İlişki eklendi',
  'residency.updated': 'İlişki güncellendi',
  'residency.ended': 'Taşındı',
  'apartment.updated': 'Daire bilgisi güncellendi',
  'apartment.deleted': 'Daire silindi',
  'apartment.pin_reset': "Daire PIN'i sıfırlandı",
  'apartment.resident_set': 'Daire hesabı tanımlandı',
  'apartment.resident_cleared': 'Daire hesabı sıfırlandı',
  'apartment.admin_tenant_enforced': 'Daire yöneticisi kuralı uygulandı',
  'apartment.owner_added': 'Daireye malik eklendi',
  'apartment.owner_removed': 'Daireden malik çıkarıldı',
  'apartment.account_holder_changed': 'Daire hesap muhatabı değişti',
  'apartment_mgmt.tenant_added': 'Kiracı eklendi',
  'apartment_mgmt.tenant_invited': 'Kiracı davet edildi',
  'apartment_mgmt.tenant_invite_accepted': 'Kiracı daveti kabul edildi',
  'apartment_mgmt.tenant_exit': 'Kiracı daireden ayrıldı',
  'apartment_mgmt.family_added': 'Aile üyesi eklendi',
  'apartment_mgmt.family_invited': 'Aile üyesi davet edildi',
  'apartment_mgmt.family_invite_accepted': 'Aile üyesi daveti kabul edildi',
  'apartment_mgmt.family_removed': 'Aile üyesi çıkarıldı',
  'apartment_mgmt.proxy_created': 'Vekalet verildi',
  'apartment_mgmt.proxy_revoked': 'Vekalet kaldırıldı',
  'apartment_mgmt.owner_recorded': 'Daire sahibi kaydedildi',
  'apartment_mgmt.member_removal_requested': 'Üye çıkarma talebi oluşturuldu',
  'apartment_mgmt.member_removal_approved': 'Üye çıkarma talebi onaylandı',
  'apartment_mgmt.member_left': 'Üye daireden ayrıldı',
  'apartment_mgmt.disconnect_requested': 'Bağ kesme talebi oluşturuldu',
  'apartment_mgmt.disconnect_approved': 'Bağ kesme talebi onaylandı',
  'apartment_mgmt.management_delegated': 'Daire yönetimi devredildi',
  'apartment_mgmt.admin_changed_by_manager': 'Daire yöneticisi site yönetimince değiştirildi',
  'vehicle.added': 'Araç eklendi',
  'vehicle.removed': 'Araç kaldırıldı',
  'vehicle.updated': 'Araç bilgisi güncellendi',
  'directory.contact_created': 'Rehber kişisi eklendi',
  'directory.contact_updated': 'Rehber kişisi güncellendi',
  'directory.contact_deleted': 'Rehber kişisi silindi',
  'import.committed': 'Toplu yükleme yapıldı',
  'export': 'Veri dışa aktarıldı',

  // Aidat ve finans
  'finance.definition.created': 'Aidat tanımı eklendi',
  'finance.definition.updated': 'Aidat tanımı güncellendi',
  'finance.definition.deactivated': 'Aidat tanımı pasifleştirildi',
  'finance.run.posted': 'Aidat borçlandırıldı',
  'finance.charge.posted': 'Ek borç yazıldı',
  'finance.payment.recorded': 'Tahsilat kaydedildi',
  'finance.payment.settings_changed': 'Ödeme ayarları değişti',
  'finance.payment.bank_details_changed': 'Banka bilgileri değişti',
  'finance.payments.assigned': 'Tahsilatlar hesaba eşlendi',
  'finance.entry.reversed': 'Mali kayıt iptal edildi',
  'finance.entry.corrected': 'Tahsilat düzeltildi',
  'finance.period.closed': 'Mali dönem kapatıldı',
  'finance.period.reopened': 'Mali dönem yeniden açıldı',
  'finance.settings.updated': 'Finans ayarları güncellendi',
  'finance.receipt.issued': 'Makbuz düzenlendi',
  'finance.receipt.printed': 'Makbuz basımı kaydedildi',
  'finance.receipt.cancelled': 'Makbuz iptal edildi',
  'finance.latefee.posted': 'Gecikme tazminatı yazıldı',
  'finance.latefee.voided': 'Gecikme tazminatı iptal edildi',
  'finance.account.created': 'Kasa / banka hesabı eklendi',
  'finance.account.updated': 'Kasa / banka hesabı güncellendi',
  'finance.account.adjusted': 'Hesap düzeltmesi yapıldı',
  'finance.transfer.created': 'Hesaplar arası aktarım yapıldı',
  'finance.transfer.voided': 'Hesaplar arası aktarım iptal edildi',
  'finance.fund_transfer.created': 'Kasalar arası aktarım yapıldı',
  'finance.fund_transfer.reversed': 'Kasalar arası aktarım ters çevrildi',
  'finance.reconciliation.recorded': 'Banka / kasa kontrolü kaydedildi',
  'finance.expense.created': 'Gider eklendi',
  'finance.expense.corrected': 'Gider düzeltildi',
  'finance.expense.voided': 'Gider iptal edildi',
  'finance.expense.nature_set': 'Gider niteliği belirlendi',
  'finance.expense.document_attached': 'Gider belgesi eklendi',
  'finance.expense.document_removed': 'Gider belgesi kaldırıldı',
  'finance.category.created': 'Gider kategorisi eklendi',
  'finance.category.updated': 'Gider kategorisi güncellendi',
  'finance.supplier.created': 'Tedarikçi eklendi',
  'finance.supplier.updated': 'Tedarikçi güncellendi',
  'finance.report.debtor_list': 'Borçlu listesi görüntülendi',
  'finance.report.viewed': 'Rapor görüntülendi',
  'finance.reminder.sent': 'Borç hatırlatma gönderildi',
  'finance.reminder.cancelled': 'Borç hatırlatma iptal edildi',
  'finance.reminder.exclusion_added': 'Daire hatırlatmadan muaf tutuldu',
  'finance.reminder.exclusion_removed': 'Hatırlatma muafiyeti kaldırıldı',
  'finance.payment_notice.approved': 'Ödeme bildirimi onaylandı',
  'finance.payment_notice.rejected': 'Ödeme bildirimi reddedildi',
  'finance.payment_notice.linked': 'Ödeme bildirimi tahsilatla eşleştirildi',
  'finance.payment_notice.manual_created': 'Ödeme bildirimi elle girildi',
  'finance.payment_notice.file_viewed': 'Ödeme bildirimi dosyası görüntülendi',
  'finance.bank_import.created': 'Banka ekstresi yüklendi',
  'finance.bank_import.reverted': 'Banka ekstresi geri alındı',
  'finance.bank_line.assigned': 'Banka satırı hesaba atandı',
  'finance.bank_line.classified': 'Banka satırı sınıflandırıldı',
  'finance.bank_line.linked': 'Banka satırı eşleştirildi',
  'finance.bank_line.unclassified': 'Banka satırının sınıfı kaldırıldı',
  'finance.opening.imported': 'Açılış bakiyeleri yüklendi',
  'finance.opening.reverted': 'Açılış bakiyeleri geri alındı',
  'finance.legal_gate.updated': 'Finans hukuk onayı bayrağı güncellendi',
  'budget.create': 'Bütçe projesi oluşturuldu',
  'budget.update': 'Bütçe projesi güncellendi',
  'budget.items': 'Bütçe kalemleri güncellendi',
  'budget.notify': 'Bütçe taslağı sakinlere bildirildi',
  'budget.revert': 'Bütçe taslağa geri alındı',
  'budget.finalize': 'Bütçe kesinleştirildi',
  'budget.delete': 'Bütçe projesi silindi',
  'metering.meter.created': 'Sayaç eklendi',
  'metering.meter.updated': 'Sayaç güncellendi',
  'metering.reading.added': 'Sayaç okuması eklendi',
  'metering.reading.deleted': 'Sayaç okuması silindi',
  'metering.reading.imported': 'Sayaç okumaları yüklendi',
  'metering.reading.retaken': 'Sayaç okuması yeniden çekildi',
  'metering.reading.jump_confirmed': 'Sayaç okuması sıçrama onayıyla kaydedildi',
  'metering.billing.posted': 'Sayaç faturalandırıldı',

  // Duyurular
  'announcement.created': 'Duyuru oluşturuldu',
  'announcement.updated': 'Duyuru düzenlendi',
  'announcement.scheduled': 'Duyuru zamanlandı',
  'announcement.published': 'Duyuru yayınlandı',
  'announcement.withdrawn': 'Duyuru geri çekildi',
  'announcement.deleted': 'Duyuru silindi',
  'announcement.publish_skipped': 'Duyuru yayını atlandı',
  'announcement.publish_failed': 'Duyuru yayını tamamlanamadı',

  // Dosya deposu
  'document.created': 'Belge yüklendi',
  'document.version_added': 'Belge sürümü eklendi',
  'document.updated': 'Belge düzenlendi',
  'document.deleted': 'Belge silindi',
  'document.restored': 'Belge geri yüklendi',
  'document.purged': 'Belge kalıcı silindi',
  'document.version_deleted': 'Belge sürümü silindi',
  'document.attached': 'Belge duyuruya eklendi',
  'document.detached': 'Belge duyurudan çıkarıldı',
  'drive.connected': 'Google Drive bağlandı',
  'drive.disconnected': 'Google Drive bağlantısı kesildi',
  'drive.file_uploaded': 'Drive deposuna dosya yüklendi',

  // Site hizmetleri
  'work_item.created': 'Talep açıldı',
  'work_item.status_changed': 'Talep durumu değişti',
  'work_item.updated': 'Talep güncellendi',
  'work_item.assigned': 'Talep atandı',
  'work_item.commented': 'Talebe yorum eklendi',
  'work_item.cancelled': 'Talep iptal edildi',
  'work_item.attachment_added': 'Talebe fotoğraf eklendi',
  'work_item.attachment_removed': 'Talepten fotoğraf kaldırıldı',
  'reservation.created': 'Rezervasyon oluşturuldu',
  'reservation.approved': 'Rezervasyon onaylandı',
  'reservation.rejected': 'Rezervasyon reddedildi',
  'reservation.cancelled': 'Rezervasyon iptal edildi',
  'reservation_area.created': 'Rezervasyon alanı eklendi',
  'reservation_area.updated': 'Rezervasyon alanı güncellendi',
  'concierge.created': 'Konsiyerj talebi oluşturuldu',
  'concierge.updated': 'Konsiyerj talebi güncellendi',
  'concierge.cancelled': 'Konsiyerj talebi iptal edildi',
  'survey.created': 'Anket oluşturuldu',
  'survey.updated': 'Anket güncellendi',
  'survey.opened': 'Anket yayınlandı',
  'survey.closed': 'Anket kapatıldı',
  'survey.deleted': 'Anket silindi',
  'visitor_entry.created': 'Ziyaretçi / kargo kaydı açıldı',
  'visitor_entry.updated': 'Ziyaretçi / kargo kaydı güncellendi',
  'board_decision.created': 'Karar taslağı oluşturuldu',
  'board_decision.updated': 'Karar taslağı düzenlendi',
  'board_decision.deleted': 'Karar taslağı silindi',
  'board_decision.finalized': 'Karar kesinleştirildi',
  'contract_vendor.created': 'Firma eklendi',
  'contract_vendor.updated': 'Firma güncellendi',
  'contract.created': 'Sözleşme eklendi',
  'contract.updated': 'Sözleşme güncellendi',
  'equipment.created': 'Ekipman eklendi',
  'equipment.updated': 'Ekipman güncellendi',
  'equipment.plan_created': 'Bakım planı eklendi',
  'equipment.plan_updated': 'Bakım planı güncellendi',
  'equipment.maintenance_logged': 'Bakım kaydı eklendi',
  'equipment.expense_linked': 'Ekipman bir gidere bağlandı',
  'equipment.expense_unlinked': 'Ekipman-gider bağlantısı kaldırıldı',
  'quote.created': 'Teklif eklendi',
  'quote.updated': 'Teklif güncellendi',
  'quote.revised': 'Teklif yeni sürümle değiştirildi',
  'quote.accepted': 'Teklif kabul edildi',
  'quote.rejected': 'Teklif reddedildi',
  'cctv.camera_created': 'Kamera eklendi',
  'cctv.camera_updated': 'Kamera güncellendi',
  'cctv.camera_deleted': 'Kamera silindi',
  'cctv.snapshot_viewed': 'Kamera anlık görüntüsü izlendi',
  'cctv.clip_opened': 'Kamera kaydı açıldı',
  'annual_report.save': 'Faaliyet raporu taslağı kaydedildi',

  // Site ayarları
  'site.created': 'Site oluşturuldu',
  'site.approved': 'Site onaylandı',
  'site.rejected': 'Site talebi reddedildi',
  'site.updated': 'Site bilgileri güncellendi',
  'site.deleted': 'Site silindi',
  'site.deletion_requested': 'Site silme talebi oluşturuldu',
  'site.deletion_cancelled': 'Site silme talebi iptal edildi',
  'site.deletion_code_locked': 'Site silme doğrulaması kilitlendi',
  'brand_theme.saved': 'Marka teması kaydedildi',
  'brand_theme.reset': 'Marka teması sıfırlandı',
  'management_company.created': 'Yönetim firması oluşturuldu',
  'management_company.updated': 'Yönetim firması güncellendi',
  'management_company.site_linked': 'Site yönetim firmasına bağlandı',
  'management_company.site_unlinked': 'Site yönetim firmasından ayrıldı',
  'management_company.member_added': 'Yönetim firmasına üye eklendi',
  'management_company.member_removed': 'Yönetim firmasından üye çıkarıldı',
  'platform_rule.updated': 'Kural değeri güncellendi',
  'emergency.info_updated': 'Acil durum bilgisi güncellendi',
});

/** `people.bulk_*` ailesi (eylem adı istekten gelir): tek başlık. */
const BULK_PEOPLE_PREFIX = 'people.bulk_';
const BULK_PEOPLE_LABEL = 'Toplu kişi işlemi';

/** LIKE desenindeki özel karakterleri (\ % _) kaçırır; deseni sonda `%` ile öneke çevirir. */
export function likePrefixPattern(prefix) {
  return `${String(prefix).replace(/[\\%_]/g, (char) => `\\${char}`)}%`;
}

function matchesCategory(category, action) {
  return category.actions.includes(action) || category.prefixes.some((prefix) => action.startsWith(prefix));
}

/** Eylem yöneticiye hiçbir koşulda gösterilmez mi? */
export function isHiddenAction(action) {
  const text = String(action ?? '');
  return SITE_AUDIT_HIDDEN_ACTIONS.includes(text) || SITE_AUDIT_HIDDEN_PREFIXES.some((prefix) => text.startsWith(prefix));
}

/** Eylemin kategorisi; gizli ya da kataloğa girmeyen eylemde null. */
export function categoryOfAction(action) {
  const text = String(action ?? '');
  if (text === '' || isHiddenAction(text)) {
    return null;
  }
  return SITE_AUDIT_CATEGORIES.find((category) => matchesCategory(category, text)) ?? null;
}

/** Eylem yöneticiye gösterilebilir mi (kategoride ve gizli değil)? */
export function isVisibleToManager(action) {
  return categoryOfAction(action) !== null;
}

/** Kategori anahtarından kategori (yoksa null). */
export function categoryByKey(key) {
  return SITE_AUDIT_CATEGORIES.find((category) => category.key === key) ?? null;
}

/**
 * Eylemin yönetici başlığı: bilinen eylemde tablodaki başlık; kategoride ama tabloda olmayan eylemde
 * "<Kategori> işlemi"; kataloğa girmeyen eylemde null (satır zaten listelenmez).
 */
export function actionLabelOf(action) {
  const text = String(action ?? '');
  if (Object.hasOwn(SITE_AUDIT_LABELS, text)) {
    return SITE_AUDIT_LABELS[text];
  }
  const category = categoryOfAction(text);
  if (category === null) {
    return null;
  }
  if (text.startsWith(BULK_PEOPLE_PREFIX)) {
    return BULK_PEOPLE_LABEL;
  }
  return `${category.label} işlemi`;
}

/**
 * SQL parametreleri: görünür eylemleri seçen LIKE desenleri / tam adlar ve gizli olanlar.
 * `categoryKey` verilirse yalnız o kategorinin eylemleri "görünür" sayılır.
 */
export function visibilityParams(categoryKey = null) {
  const categories = categoryKey === null ? SITE_AUDIT_CATEGORIES : [categoryByKey(categoryKey)].filter(Boolean);
  return {
    includeLike: categories.flatMap((category) => category.prefixes.map(likePrefixPattern)),
    includeExact: categories.flatMap((category) => [...category.actions]),
    excludeLike: SITE_AUDIT_HIDDEN_PREFIXES.map(likePrefixPattern),
    excludeExact: [...SITE_AUDIT_HIDDEN_ACTIONS],
  };
}
