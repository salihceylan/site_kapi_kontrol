// Dağıtım tabanı VERİSİ (karar K5): tahakkuk (aidat / ek borç / gider payı) ve ısı payı aynı tabanlardan beslenir. Taban YÖNETİMİN açık seçimidir; kod hiçbir koşulda
// taban seçmez, veri eksikse sessizce başka tabana düşmez (eksik veri `missing` olarak raporlanır, karar yöneticide: veriyi tamamla ya da daireyi atla).
//
// Tabanlar (seçilebilir olanlar finance_distribution.SELECTABLE_DISTRIBUTIONS):
//   equal         her daire ağırlık 1 (VARSAYILAN)
//   fixed         daire başı sabit tutar (ağırlık yok)
//   category      kategori başına daire başı tutar
//   land_share    arsa payı (apartments.land_share_numerator / denominator)
//   person_count  dairedeki güncel kişi sayısı (aşağıdaki PERSON_COUNT_SQL)
// m² (alan) tabanı YOKTUR: daire alanı sistemde tutulmuyor (migration 078; AGENTS.md "m² geri eklenmez"). Alan verisi olmayan taban seçenek olarak sunulmaz.

/**
 * Dairedeki GÜNCEL kişi sayısı = Kişiler ekranındaki dairenin güncel (`is_current`) ilişki kayıtları (malik, kiracı, aile üyesi, sakin; hesapsız çocuk / yaşlı dahil).
 * Kayıt yoksa 0 döner ve daire "kişi sayısı tanımsız" (eksik veri) sayılır. Çağıran sorguda daire tablosu `a` takma adıyla bulunmalıdır.
 * Not: Site Yönetimi satırındaki "N kişi" (site_service.listSiteApartments `household_count`) kişi eşitlemesi çalışmamış sitede üyelik sayısına da bakar; faturalama bu
 * yedeğe DAYANMAZ (eşitleme bir yazmadır, finans işlemi içinde çalıştırılmaz): kişi kaydı olmayan daire eksik veri olarak görünür ve yönetici Kişiler ekranından tamamlar.
 */
export const PERSON_COUNT_SQL = `(SELECT COUNT(*)::INTEGER FROM apartment_residencies r WHERE r.apartment_id = a.id AND r.is_current = TRUE)`;
