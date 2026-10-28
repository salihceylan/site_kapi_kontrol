// Toplu yükleme: kullanıcı adı / e-posta VAR-YOK soruları için SİTE KAPSAMI.
//
// Sorun (güvenlik denetimi 2026-10-28, authz-modules-1): önizleme / öneri / tek ad denetimi uçları `users` tablosunu site bağı OLMADAN sorguluyordu; herhangi bir site
// yöneticisi, sistemdeki HER hesabın kullanıcı adının ve kayıtlı e-postasının var olup olmadığını (ve «_N» önerisiyle varyasyonları) sayabiliyordu. Sayım, varsayılan başlangıç
// şifresiyle («1234», ekip kararı) hedefli şifre denemesinin maliyetini sıfırlıyordu.
//
// Kural: yöneticiye gösterilen HER var/yok yanıtı (önizleme, hesap önerisi, tek ad denetimi, plan satır hatası) yalnız BU SİTENİN yöneticisinin zaten görebildiği hesapları
// kapsar. Başka sitedeki bir ad / e-posta «yok» gibi davranır (kullanılabilir). Gerçek çakışma (aynı sitedeki hesap) doğru raporlanmaya devam eder.
// `users.login_name` ve `users.email` sistem genelinde TEKİL kaldığı için kesin ad / e-posta denetimi YAZIM anında, sistem genelinde yapılır (bulk_import_writer.js);
// orada çıkan fark yöneticiye yalnız onay sonucunda (nihai ad, `requested_login_name`, `skipped_items`) bildirilir; önizlemede ASLA.

/**
 * «Bu sitenin yöneticisinin zaten görebildiği hesap» SQL koşulu. Üç kaynak (pasif / eski kayıtlar DAHİL; yönetici bunları kişi kartlarında ve geçmişte görür):
 *   1. `site_people.user_code` — sitenin kişi (CRM) kaydına bağlı hesap,
 *   2. `apartment_memberships` — sitenin dairesinde (şimdi ya da eskiden) üyeliği olan hesap,
 *   3. `apartments.resident_user_code` — sitenin dairesinde sakin göstergesi olan hesap.
 *
 * BİLİNÇLİ OLARAK YOK: `site_manager_sites` (yöneticilik) ve `site_memberships` (SITE_ADMIN / BOARD_MEMBER / STAFF rolü). Bunlar yöneticinin KENDİSİNİN başkasının hesabına
 * tek taraflı verebildiği bağlardır (örn. kayıtlı bir e-postaya yönetici daveti hemen yetki yazar): kapsama girselerdi, kötü niyetli bir yönetici hedef hesabı önce kendi
 * sitesine «çekip» sonra var/yok sorusunu o hesap için yanıtlatabilirdi. Aynı gerekçeyle `siteTiePredicate` (people_sync_sql.js) da yalnız daire bağlarını sayar.
 *
 * Koşul `users` tablosunun [userExpr] ifadesi (kullanıcı kodu) ile kullanılır; [siteExpr] site kodu SQL ifadesidir (örn. '$2::BIGINT'). Kullanılan indeksler:
 * uq_site_people_user (site_code, user_code), idx_apt_memberships_user, idx_apartments_resident_user_code. Koşul yalnız ad / e-posta ile ELENMİŞ az sayıda satırda çalışır.
 * @param {string} userExpr kullanıcı kodu SQL ifadesi (ör. 'u.user_code')
 * @param {string} siteExpr site kodu SQL ifadesi (ör. '$2::BIGINT')
 */
export function siteVisibleUserSql(userExpr, siteExpr) {
  return `(
    EXISTS (SELECT 1 FROM site_people vis_sp WHERE vis_sp.site_code = ${siteExpr} AND vis_sp.user_code = ${userExpr})
    OR EXISTS (
      SELECT 1 FROM apartment_memberships vis_am
      INNER JOIN apartments vis_a ON vis_a.id = vis_am.apartment_id
      WHERE vis_am.user_code = ${userExpr} AND vis_a.site_code = ${siteExpr}
    )
    OR EXISTS (SELECT 1 FROM apartments vis_r WHERE vis_r.resident_user_code = ${userExpr} AND vis_r.site_code = ${siteExpr})
  )`;
}

/**
 * Sorgu kapsamı için site kodu. Eksik / geçersiz kod sessizce «kapsamsız» (sistem geneli) sorguya DÜŞMEZ: hata fırlatır (yeni bir çağıran kapsamı unutup
 * sayım açığını geri getiremesin).
 * @returns {number}
 */
export function requireScopeSite(siteCode) {
  const code = Number(siteCode);
  if (!Number.isSafeInteger(code) || code <= 0) {
    throw new TypeError('Kullanıcı adı / e-posta denetimi için geçerli bir site kodu gerekir (kapsamsız sorgu yapılmaz).');
  }
  return code;
}
