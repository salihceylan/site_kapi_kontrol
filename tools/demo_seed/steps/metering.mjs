// Sayac Okuma ve Faturalandirma (modul: metering). Finans adimindan ONCE calisir: faturalandirma borclari deftere yazilir ve
// finans adiminin tahsilat planina dahil olur. Daire basi su sayaci + kalorimetre (isi); 47 aylik okuma; ceyreklik su faturalandirma.
// Sinir: sayac tablosu daire zorunlu oldugundan "ortak elektrik" sayaci modellenemez (raporda belirtilir).

import { addDays, addMonths, clampDay, daysInMonth, monthsBetween, noonIstanbul, ymOf } from '../lib/util.mjs';

const UNIT_PRICE_KURUS = { 2023: 1850, 2024: 2900, 2025: 4200, 2026: 5600 };
const WATER_SEASON = [0.95, 0.92, 0.95, 1.0, 1.05, 1.12, 1.18, 1.18, 1.08, 1.0, 0.96, 0.95];
const HEAT_KWH = [1500, 1300, 900, 380, 110, 30, 25, 25, 70, 380, 900, 1400]; // 100 m2 daire icin aylik kalorimetre

const lastDay = (ym) => clampDay(ym, daysInMonth(ym));

export async function seedMetering(ctx) {
  const { q, rng, site, apartments, peopleResult, manager, svc, TODAY, log, batchId } = ctx;
  const siteCode = site.code;
  const actor = { user_code: manager.user_code, full_name: manager.full_name, role: manager.role };
  const billingMod = await ctx.importServer('src/modules/metering_billing.js');
  const periodsYm = monthsBetween('2022-12', ymOf(addMonths(`${TODAY.slice(0, 7)}-01`, -1)));
  const readingDates = periodsYm.map(lastDay).filter((d) => d <= TODAY);

  // sayaclar
  const meters = [];
  for (const apt of apartments) {
    const code = `${apt.blockName.replace(/\s*Blok.*/i, '')}${apt.unitLabel.replace(/\D/g, '')}`;
    const members = peopleResult.peopleByApt.get(apt.id) ?? [];
    const headcount = members.filter((m) => m.role !== 'landlord').length || 4;
    for (const kind of ['water', 'heat']) {
      const serial = `${kind === 'water' ? 'SU' : 'KAL'}-${code}-${String(siteCode).slice(-4)}`;
      const r = await q(`INSERT INTO meters (site_code, apartment_id, kind, serial_no, is_active, created_by, created_at) VALUES ($1, $2, $3, $4, TRUE, $5, '2022-12-31T10:00:00+03:00') RETURNING id`, [
        siteCode, apt.id, kind, serial, manager.user_code,
      ]);
      meters.push({ id: Number(r.rows[0].id), kind, apt, headcount });
    }
  }
  // anormal tuketim: 2 daire (su kacagi / yuksek kullanim)
  const anomaly = new Map([
    [apartments[Math.min(2, apartments.length - 1)].id, { from: '2024-03', to: '2024-05', mult: 2.6 }],
    [apartments[Math.min(6, apartments.length - 1)].id, { from: '2025-08', to: '2026-10', mult: 2.1 }],
  ]);
  let readingCount = 0;
  for (const m of meters) {
    let cumulative = m.kind === 'water' ? rng.float(120, 400) : rng.float(2000, 9000);
    const rows = [];
    for (const d of readingDates) {
      const ym = d.slice(0, 7);
      const mi = Number(ym.slice(5, 7)) - 1;
      if (d !== readingDates[0]) {
        let usage;
        if (m.kind === 'water') {
          usage = m.headcount * 3.6 * WATER_SEASON[mi] * rng.float(0.88, 1.12);
          const a = anomaly.get(m.apt.id);
          if (a && ym >= a.from && ym <= a.to) usage *= a.mult;
        } else {
          usage = HEAT_KWH[mi] * ((m.apt.gross ?? 100) / 100) * rng.float(0.85, 1.15);
        }
        cumulative += usage;
      }
      rows.push([siteCode, m.id, d, Math.round(cumulative * 1000) / 1000, manager.user_code, `${d}T18:00:00+03:00`]);
    }
    for (const row of rows) {
      await q(`INSERT INTO meter_readings (site_code, meter_id, reading_date, value, source, created_by, created_at) VALUES ($1, $2, $3::DATE, $4, 'manual', $5, $6::timestamptz)`, row);
      readingCount += 1;
    }
  }
  log(`Sayac: ${meters.length} sayac, ${readingCount} okuma`);

  // ceyreklik su faturalandirma (finans acik ise)
  let billings = 0;
  if (ctx.enabled.finance) {
    const quarters = [];
    for (let y = 2023; y <= Number(TODAY.slice(0, 4)); y += 1) {
      for (const start of ['01', '04', '07', '10']) {
        const from = `${y}-${start}-01`;
        const toYm = ymOf(addMonths(from, 2));
        const to = lastDay(toYm);
        if (to > TODAY) continue;
        // kapanis okumasi (donem sonu) mevcut olmali
        if (!readingDates.includes(to)) continue;
        quarters.push({ from, to, y });
      }
    }
    for (const [i, qtr] of quarters.entries()) {
      const postDay = addDays(qtr.to, 6);
      const now = noonIstanbul(postDay > TODAY ? TODAY : postDay);
      const body = { kind: 'water', method: 'unit_price', period_from: qtr.from, period_to: qtr.to, unit_price_minor: UNIT_PRICE_KURUS[qtr.y], due_date: addDays(postDay > TODAY ? TODAY : postDay, 20), skip_missing: true };
      try {
        const preview = await billingMod.previewBilling({ siteCode, body, now });
        if (!preview.can_post) continue;
        await billingMod.postBilling({
          siteCode, actor, now,
          body: { ...body, expected_total_minor: preview.total_minor, expected_count: preview.apartment_count, expected_hash: preview.preview_hash, idempotency_key: `${batchId}:mb:${i}`.slice(0, 64) },
        });
        billings += 1;
      } catch (error) {
        log(`Su faturalandirma atlandi ${qtr.from}: ${error.code ?? ''} ${error.message}`);
      }
    }
    log(`Sayac faturalandirma: ${billings} ceyrek (su)`);
  }
  return { meters: meters.length, readings: readingCount, billings };
}
