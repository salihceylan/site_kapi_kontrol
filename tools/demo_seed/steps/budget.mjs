// Isletme Projesi / Butce (modul: budget): 2023-2026 kesin projeler, 2027 teblig edilmis proje (itiraz suresi acik).
// Kalem tutarlari gerceklesen giderlerin ~%95-112'si. Servis akisi: createProject -> replaceItems -> notifyProject -> finalizeProject.

import { addDays, noonIstanbul } from '../lib/util.mjs';

export async function seedBudget(ctx) {
  const { q, rng, site, manager, TODAY, log } = ctx;
  const siteCode = site.code;
  const actor = { user_code: manager.user_code, full_name: manager.full_name, role: manager.role };
  const svc = await ctx.importServer('src/modules/budget_service.js');
  const actualRows = (
    await q(
      `SELECT to_char(expense_date, 'YYYY') AS y, category_id, SUM(amount_minor)::BIGINT AS total
       FROM expenses WHERE site_code = $1 AND id NOT IN (SELECT expense_id FROM expense_voids) GROUP BY 1, 2`,
      [siteCode],
    )
  ).rows;
  const byYear = new Map();
  for (const r of actualRows) {
    if (!byYear.has(r.y)) byYear.set(r.y, new Map());
    byYear.get(r.y).set(Number(r.category_id), Number(r.total));
  }
  const thisYear = TODAY.slice(0, 4);
  const monthsElapsed = Number(TODAY.slice(5, 7)) - 1 + Number(TODAY.slice(8, 10)) / 31;
  const annualize = (v) => Math.round((v * 12) / monthsElapsed);
  const projects = [];
  const plan = (year, baseMap, factorLo, factorHi, growth = 1) =>
    [...baseMap.entries()].map(([categoryId, actual]) => ({ category_id: categoryId, annual_minor: Math.round((actual * growth * rng.float(factorLo, factorHi)) / 100) * 100 }));

  const specs = [
    { year: 2023, create: '2022-12-05', notify: '2022-12-12', finalize: '2023-01-05' },
    { year: 2024, create: '2023-12-04', notify: '2023-12-11', finalize: '2024-01-04' },
    { year: 2025, create: '2024-12-03', notify: '2024-12-10', finalize: '2025-01-03' },
    { year: 2026, create: '2025-12-02', notify: '2025-12-09', finalize: '2026-01-05' },
  ];
  for (const s of specs) {
    const actualMap = byYear.get(String(s.year)) ?? new Map();
    const base = s.year === Number(thisYear) ? new Map([...actualMap.entries()].map(([k, v]) => [k, annualize(v)])) : actualMap;
    if (base.size === 0) continue;
    const created = await svc.createProject({ siteCode, actor, now: noonIstanbul(s.create), body: { year: s.year, title: `${s.year} Yılı İşletme Projesi`, note: 'Genel kurul onayına sunulan yıllık gider bütçesi (demo).' } });
    const id = created.id ?? created.project?.id;
    await svc.replaceItems({ siteCode, rawId: id, actor, body: { items: plan(s.year, base, 0.95, 1.12) } });
    await svc.notifyProject({ siteCode, rawId: id, actor, now: noonIstanbul(s.notify), body: { notified_at: s.notify } });
    await svc.finalizeProject({ siteCode, rawId: id, actor, now: noonIstanbul(s.finalize) });
    projects.push({ year: s.year, status: 'kesin', id });
  }
  // 2027 taslagi: bu yilin yillandirilmis gideri x artis; teblig edildi, itiraz suresi sureyor
  const base2026 = new Map([...(byYear.get(thisYear) ?? new Map()).entries()].map(([k, v]) => [k, annualize(v)]));
  if (base2026.size > 0) {
    const nextYear = Number(thisYear) + 1;
    const draftDay = addDays(TODAY, -10);
    const created = await svc.createProject({ siteCode, actor, now: noonIstanbul(draftDay), body: { year: nextYear, title: `${nextYear} Yılı İşletme Projesi (taslak)`, note: 'Yönetim kurulu önerisi; itiraz süresi sürüyor.' } });
    const id = created.id ?? created.project?.id;
    await svc.replaceItems({ siteCode, rawId: id, actor, body: { items: plan(nextYear, base2026, 1.25, 1.5) } });
    const notified = addDays(TODAY, -5);
    await svc.notifyProject({ siteCode, rawId: id, actor, now: noonIstanbul(notified), body: { notified_at: notified } });
    projects.push({ year: nextYear, status: 'teblig', id });
  }
  log(`Isletme projesi: ${projects.map((p) => `${p.year}:${p.status}`).join(', ')}`);
  return { projects };
}
