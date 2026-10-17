// Toplu yükleme (Faz 2b): veritabanı anlık görüntüsü. Sabit sayıda sorgu (satır sayısından bağımsız); tüm sorgular `site_code` ile sınırlıdır (IDOR yok).
//
// İndeksler: apartments(site_code) [idx_apartments_site_code], site_people(site_code, is_active, id) [idx_site_people_site],
// apartment_residencies(apartment_id, is_current) [idx_apartment_residencies_apartment; dairelerin kimlikleriyle aranır, tabloda site_code indeksi yok],
// users(user_code) [birincil anahtar], vehicles(site_code, plate) WHERE is_active [uq_vehicles_plate], ledger_entries(site_code, apartment_id, ...) [idx_ledger_entries_apartment].
// Sorgu sayısı: daireler 2 (blok, daire), kişiler/araçlar 5-6 (+ hesaplı kişi varsa kullanıcı sorgusu).

const num = (value) => (value === null || value === undefined ? null : Number(value));

export async function loadBlocksAndApartments(db, siteCode, { withFinance = false } = {}) {
  const blocks = await db.query(`SELECT id, block_name FROM site_blocks WHERE site_code = $1 ORDER BY sort_order, id`, [siteCode]);
  const apartments = await db.query(
    `
      SELECT a.id, a.block_id, a.unit_label, a.floor, a.category, a.gross_area_m2, a.net_area_m2,
             a.land_share_numerator, a.land_share_denominator, a.responsible_party,
             ${
               withFinance
                 ? 'EXISTS (SELECT 1 FROM ledger_entries l WHERE l.site_code = a.site_code AND l.apartment_id = a.id)'
                 : 'FALSE'
             } AS has_finance
      FROM apartments a
      WHERE a.site_code = $1
      ORDER BY a.id
    `,
    [siteCode],
  );
  return {
    blocks: blocks.rows.map((row) => ({ id: Number(row.id), name: row.block_name })),
    apartments: apartments.rows.map((row) => ({
      id: Number(row.id),
      blockId: Number(row.block_id),
      label: row.unit_label,
      floor: num(row.floor),
      category: row.category ?? null,
      gross: row.gross_area_m2 === null ? null : String(row.gross_area_m2),
      net: row.net_area_m2 === null ? null : String(row.net_area_m2),
      lsNum: num(row.land_share_numerator),
      lsDen: num(row.land_share_denominator),
      responsible: row.responsible_party ?? 'both',
      hasFinance: row.has_finance === true,
    })),
  };
}

/**
 * Tür için anlık görüntü. `apartments`: yalnız blok + daire (+ mali kayıt bayrağı). `people` / `vehicles`: + kişiler (pasifler dahil), güncel ilişkiler,
 * aktif araçlar.
 */
export async function loadSnapshot(db, siteCode, kind) {
  const base = await loadBlocksAndApartments(db, siteCode, { withFinance: kind === 'apartments' });
  if (kind === 'apartments') {
    return { ...base, people: [], residencies: [], vehicles: [] };
  }
  // Kişiler: önce yalnız site_people (idx_site_people_site), hesaplı olanların kullanıcı satırları ayrıca BİRİNCİL ANAHTARLA (users'ta Seq Scan yok).
  const people = await db.query(
    `
      SELECT sp.id, sp.user_code, sp.is_active, sp.full_name AS sp_name, sp.phone AS sp_phone, sp.email AS sp_email, sp.note
      FROM site_people sp
      WHERE sp.site_code = $1
    `,
    [siteCode],
  );
  const userCodes = [...new Set(people.rows.filter((row) => row.user_code !== null).map((row) => Number(row.user_code)))];
  const accounts = new Map();
  if (userCodes.length > 0) {
    const users = await db.query(`SELECT user_code, full_name, phone_number, email FROM users WHERE user_code = ANY($1::INTEGER[])`, [userCodes]);
    for (const row of users.rows) {
      accounts.set(Number(row.user_code), row);
    }
  }
  // Güncel ilişkiler: dairelerin kimlikleriyle (idx_apartment_residencies_apartment; tabloda site_code indeksi yok).
  const residencies = await db.query(
    `SELECT r.id, r.apartment_id, r.person_id, r.relation FROM apartment_residencies r WHERE r.apartment_id = ANY($1::BIGINT[]) AND r.is_current = TRUE`,
    [base.apartments.map((apartment) => apartment.id)],
  );
  const vehicles = await db.query(`SELECT id, person_id, plate FROM vehicles WHERE site_code = $1 AND is_active = TRUE`, [siteCode]);
  return {
    ...base,
    people: people.rows.map((row) => {
      const account = row.user_code === null ? null : accounts.get(Number(row.user_code)) ?? null;
      return {
        id: Number(row.id),
        userCode: row.user_code === null ? null : Number(row.user_code),
        isActive: row.is_active === true,
        spName: row.sp_name ?? null,
        spPhone: row.sp_phone ?? null,
        spEmail: row.sp_email ?? null,
        note: row.note ?? null,
        uName: account?.full_name ?? null,
        uPhone: account?.phone_number ?? null,
        uEmail: account?.email ?? null,
      };
    }),
    residencies: residencies.rows.map((row) => ({
      id: Number(row.id),
      apartmentId: Number(row.apartment_id),
      personId: Number(row.person_id),
      relation: row.relation,
    })),
    vehicles: vehicles.rows.map((row) => ({
      id: Number(row.id),
      personId: row.person_id === null ? null : Number(row.person_id),
      plate: row.plate,
    })),
  };
}
