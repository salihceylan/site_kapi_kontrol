// Firma ve Sozlesme Takibi (modul: contracts): 8 firma, gecmis ve guncel sozlesmeler, 2 yakinda biten.
// E-POSTA YOK: hatirlatma zamanlayicisi sitenin yoneticisine e-posta atar; bu yuzden hatirlatma penceresi acilacak (veya acilmis) her kalem
// icin contract_reminders satiri onceden "gonderildi" olarak yazilir (sent_at dolu, alici 0) - zamanlayici ayni kalemi tekrar talep etmez.

import { addDays } from '../lib/util.mjs';

const VENDORS = [
  ['Mavi Asansör Bakım Ltd. Şti. (Demo)', 'asansor', 'Servis Müdürü Bora Sezer'],
  ['Kalkan Güvenlik Hizmetleri (Demo)', 'guvenlik', 'Operasyon Sorumlusu Nihat Aral'],
  ['Berrak Temizlik Hizmetleri (Demo)', 'temizlik', 'Saha Şefi Dilara Ünal'],
  ['Yeşil Vadi Peyzaj (Demo)', 'bahce', 'Peyzaj Mimarı Okan Toprak'],
  ['Isıtek Kazan Servisi (Demo)', 'teknik_bakim', 'Teknik Servis Metin Aydemir'],
  ['Güven Sigorta Aracılık (Demo)', 'sigorta', 'Acente Sorumlusu Ayten Çınar'],
  ['Netbağ İletişim ve İnterkom (Demo)', 'yazilim', 'Müşteri Temsilcisi Kerem Aslan'],
  ['Temiz Dünya İlaçlama (Demo)', 'diger', 'Teknik Uzman Sibel Özer'],
];

export async function seedContracts(ctx) {
  const { q, rng, site, manager, TODAY } = ctx;
  const siteCode = site.code;
  const vendorIds = [];
  for (const [i, [name, category, contact]] of VENDORS.entries()) {
    const r = await q(
      `INSERT INTO contract_vendors (site_code, name, category, contact_name, phone, note, is_active, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, TRUE, $7, '2023-01-05T10:00:00+03:00', '2023-01-05T10:00:00+03:00') RETURNING id`,
      [siteCode, name, category, contact, `+90500000${String(40 + i).padStart(2, '0')}${String(10 + i * 3).padStart(2, '0')}`, 'Demo firma kaydı (sahte veri).', manager.user_code],
    );
    vendorIds.push(Number(r.rows[0].id));
  }
  // [vendor index, baslik, kategori, baslangic, bitis, bildirim gunu, hatirlatma gunu, tutar TL, donem, otomatik yenileme, durum]
  const contracts = [
    [0, 'Asansör aylık bakım sözleşmesi (2023)', 'asansor', '2023-01-01', '2023-12-31', 30, 30, 900, 'aylik', false, 'aktif'],
    [0, 'Asansör aylık bakım sözleşmesi', 'asansor', '2024-01-01', '2027-06-30', 60, 45, 1750, 'aylik', true, 'aktif'],
    [1, 'Güvenlik ve danışma hizmeti', 'guvenlik', '2025-04-01', '2027-03-31', 60, 60, 12500, 'aylik', true, 'aktif'],
    [2, 'Temizlik hizmeti (ilk dönem)', 'temizlik', '2023-01-01', '2025-08-31', 30, 30, 900, 'aylik', false, 'aktif'],
    [2, 'Temizlik hizmeti', 'temizlik', '2025-09-01', '2027-08-31', 45, 30, 2900, 'aylik', true, 'aktif'],
    [3, 'Bahçe ve peyzaj bakımı', 'bahce', '2024-12-06', addDays(TODAY, 44), 30, 30, 1100, 'aylik', false, 'aktif'],
    [4, 'Kazan dairesi bakım sözleşmesi', 'teknik_bakim', '2026-01-01', '2026-12-31', 60, 60, 24000, 'yillik', true, 'aktif'],
    [5, 'DASK ve bina yangın sigortası', 'sigorta', '2026-03-01', '2027-02-28', 30, 45, 15500, 'yillik', true, 'aktif'],
    [6, 'İnterkom ve ortak internet hizmeti', 'yazilim', '2024-06-01', '2027-05-31', 30, 30, 650, 'aylik', false, 'aktif'],
    [7, 'Periyodik ilaçlama hizmeti', 'diger', '2025-11-16', addDays(TODAY, 24), 15, 30, 700, 'aylik', false, 'aktif'],
    [1, 'Eski güvenlik sözleşmesi (fesih)', 'guvenlik', '2023-01-01', '2025-03-31', 30, 30, 8200, 'aylik', false, 'feshedildi'],
  ];
  let reminders = 0;
  for (const [vi, title, category, start, end, notice, remind, amount, period, auto, status] of contracts) {
    const r = await q(
      `INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, end_date, notice_days, remind_before_days, amount, currency, period, auto_renew, status, terminated_at, note, created_by, updated_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5::DATE, $6::DATE, $7, $8, $9, 'TRY', $10, $11, $12, $13::timestamptz, $14, $15, $15, $16::timestamptz, $16::timestamptz) RETURNING id`,
      [
        siteCode, vendorIds[vi], title, category, start, end, notice, remind, amount, period, auto, status,
        status === 'feshedildi' ? `${end}T12:00:00+03:00` : null, 'Demo sözleşme (sahte veri).', manager.user_code, `${start}T10:00:00+03:00`,
      ],
    );
    const id = Number(r.rows[0].id);
    if (status === 'aktif' && end >= TODAY) {
      await q(`INSERT INTO contract_reminders (contract_id, site_code, kind, due_date, claimed_at, sent_at, recipients) VALUES ($1, $2, 'bitis', $3::DATE, NOW(), NOW(), 0) ON CONFLICT DO NOTHING`, [id, siteCode, end]);
      reminders += 1;
      if (auto) {
        await q(`INSERT INTO contract_reminders (contract_id, site_code, kind, due_date, claimed_at, sent_at, recipients) VALUES ($1, $2, 'fesih_bildirim', ($3::DATE - $4::INTEGER), NOW(), NOW(), 0) ON CONFLICT DO NOTHING`, [id, siteCode, end, notice]);
        reminders += 1;
      }
    }
  }
  return { vendors: vendorIds.length, contracts: contracts.length, reminders, rng };
}
