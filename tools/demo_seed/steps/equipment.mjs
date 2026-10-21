// Ekipman ve Bakim (modul: equipment): 10 ekipman, bakim planlari, gecmis bakim kayitlari, yaklasan kontroller, gider baglantilari.
// Finans giderine ekipman bagi (equipment_expense_links) ve bakim kaydi -> gider (expense_id) finans adiminin gider kimlikleriyle kurulur.

import { addMonths, addDays } from '../lib/util.mjs';

const ITEMS = [
  { key: 'lift1', kind: 'asansor', name: 'Asansör A Blok', location: 'A Blok merdiven boşluğu', serial: 'AS-A-0412', installed: '2012-06-01', vendor: 0 },
  { key: 'lift2', kind: 'asansor', name: 'Asansör B Blok', location: 'B Blok merdiven boşluğu', serial: 'AS-B-0413', installed: '2012-06-01', vendor: 0 },
  { key: 'boiler', kind: 'kazan', name: 'Merkezi Kalorifer Kazanı', location: 'Kazan dairesi', serial: 'KZ-2018-77', installed: '2018-10-01', vendor: 4 },
  { key: 'hydro', kind: 'hidrofor', name: 'Hidrofor Grubu', location: 'Bodrum pompa odası', serial: 'HD-2019-12', installed: '2019-03-15', vendor: 4 },
  { key: 'genset', kind: 'jenerator', name: 'Acil Durum Jeneratörü', location: 'Bahçe jeneratör kabini', serial: 'JN-2017-03', installed: '2017-09-01', vendor: 4 },
  { key: 'fire', kind: 'yangin_algilama', name: 'Yangın Algılama Sistemi', location: 'Tüm ortak alanlar', serial: 'YA-2016-1', installed: '2016-05-20', vendor: 4 },
  { key: 'intercom', kind: 'interkom', name: 'Görüntülü İnterkom Sistemi', location: 'Giriş ve daireler', serial: 'IK-2020-8', installed: '2020-02-10', vendor: 6 },
  { key: 'cctv', kind: 'kamera_sistemi', name: 'Güvenlik Kamera Sistemi', location: 'Giriş, otopark, bahçe', serial: 'KM-2021-5', installed: '2021-11-01', vendor: 6 },
  { key: 'barrier', kind: 'bariyer', name: 'Otopark Bariyeri', location: 'Otopark girişi', serial: 'BR-2019-2', installed: '2019-08-01', vendor: 4 },
  { key: 'pump2', kind: 'yangin_pompasi', name: 'Yangın Pompası', location: 'Bodrum', serial: 'YP-2016-4', installed: '2016-05-20', vendor: 4 },
];
// [ekipman, baslik, aralik ay, yasal, ilk uygulama ay (2023-01 sonrasi), maliyet TL]
const PLANS = [
  ['lift1', 'Aylık asansör bakımı', 1, false, '2023-01-12', 875],
  ['lift2', 'Aylık asansör bakımı', 1, false, '2023-01-12', 875],
  ['lift1', 'Yıllık periyodik kontrol (etiket)', 12, true, '2023-05-20', 1800],
  ['boiler', 'Kazan ve baca yıllık bakımı', 12, true, '2023-10-14', 3500],
  ['hydro', 'Hidrofor basınç ve pompa kontrolü', 6, false, '2023-04-10', 900],
  ['genset', 'Jeneratör yük testi ve bakım', 3, false, '2023-02-08', 750],
  ['fire', 'Yangın algılama sistem kontrolü', 6, true, '2023-03-15', 1200],
  ['intercom', 'İnterkom genel kontrolü', 12, false, '2023-06-20', 600],
  ['cctv', 'Kamera sistemi temizlik ve kayıt kontrolü', 12, false, '2023-09-05', 700],
  ['barrier', 'Bariyer mekanik bakımı', 6, false, '2023-05-02', 650],
  ['pump2', 'Yangın pompası test çalıştırması', 3, true, '2023-02-20', 500],
];
const EQUIP_KEY_ALIASES = { liftMaint: 'lift1', liftCheck: 'lift1', boilerMaint: 'boiler' };

export async function seedEquipment(ctx) {
  const { q, rng, site, manager, TODAY, finance, contracts } = ctx;
  const siteCode = site.code;
  const ids = new Map();
  // tedarikci kimlikleri: contract_vendors (varsa) adlarindan
  const vendors = (await q(`SELECT id, name FROM contract_vendors WHERE site_code = $1 ORDER BY id`, [siteCode])).rows;
  for (const it of ITEMS) {
    const vendor = vendors[it.vendor] ?? null;
    const r = await q(
      `INSERT INTO equipment_items (site_code, kind, name, location, vendor_id, serial_no, installed_on, note, is_active, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7::DATE, $8, TRUE, $9, '2023-01-20T10:00:00+03:00', '2023-01-20T10:00:00+03:00') RETURNING id`,
      [siteCode, it.kind, it.name, it.location, vendor ? Number(vendor.id) : null, it.serial, it.installed, 'Demo ekipman kaydı (sahte veri).', manager.user_code],
    );
    ids.set(it.key, Number(r.rows[0].id));
  }
  // gider baglantilari
  const refs = finance?.expenseRefs ?? [];
  const byKeyMonthly = new Map();
  let links = 0;
  for (const ref of refs) {
    const equipKey = ref.equip ? EQUIP_KEY_ALIASES[ref.equip] ?? ref.equip : null;
    if (!equipKey || !ids.has(equipKey)) continue;
    await q(`INSERT INTO equipment_expense_links (expense_id, site_code, equipment_id, created_by, created_at) VALUES ($1, $2, $3, $4, $5::timestamptz) ON CONFLICT DO NOTHING`, [ref.id, siteCode, ids.get(equipKey), manager.user_code, `${ref.date}T16:00:00+03:00`]);
    links += 1;
    if (ref.equip === 'liftMaint') byKeyMonthly.set(ref.date.slice(0, 7), ref);
  }
  // planlar ve bakim kayitlari
  let planCount = 0;
  let logCount = 0;
  const upcoming = [];
  for (const [equipKey, title, interval, legal, first, cost] of PLANS) {
    const equipmentId = ids.get(equipKey);
    let cursor = first;
    const dates = [];
    while (cursor <= TODAY) {
      dates.push(cursor);
      cursor = addMonths(cursor, interval);
    }
    const nextDue = cursor;
    const lastDone = dates[dates.length - 1] ?? null;
    const p = await q(
      `INSERT INTO equipment_plans (site_code, equipment_id, title, interval_months, legal, next_due, last_done, is_active, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6::DATE, $7::DATE, TRUE, '2023-01-20T10:30:00+03:00', $8::timestamptz) RETURNING id`,
      [siteCode, equipmentId, title, interval, legal, nextDue, lastDone, `${lastDone ?? '2023-01-20'}T12:00:00+03:00`],
    );
    const planId = Number(p.rows[0].id);
    planCount += 1;
    upcoming.push({ title, nextDue });
    for (const d of dates) {
      const month = d.slice(0, 7);
      const linked = title.startsWith('Aylık asansör') && equipKey === 'lift1' ? byKeyMonthly.get(month) : null;
      const amount = linked ? linked.amountMinor : Math.round(cost * 100 * (1 + (Number(d.slice(0, 4)) - 2023) * 0.5) * rng.float(0.95, 1.1));
      await q(
        `INSERT INTO equipment_maintenance_logs (site_code, equipment_id, plan_id, done_on, vendor_name, cost_kurus, expense_id, note, created_by, created_at)
         VALUES ($1, $2, $3, $4::DATE, $5, $6, $7, $8, $9, $10::timestamptz)`,
        [siteCode, equipmentId, planId, d, vendors[ITEMS.find((i) => i.key === equipKey).vendor]?.name ?? null, amount, linked ? linked.id : null, rng.pick(['Bakım tamamlandı.', 'Kontrol yapıldı, sorun yok.', 'Yağlama ve ayar yapıldı.', 'Rutin kontrol tamamlandı.']), manager.user_code, `${d}T17:00:00+03:00`],
      );
      logCount += 1;
    }
  }
  return { items: ITEMS.length, plans: planCount, logs: logCount, links, upcoming, addDays, contracts: !!contracts };
}
