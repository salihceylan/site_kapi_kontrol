// Anket ve Oylama (modul: survey): 6 anket (4 kapali sonuclu, 2 acik); daire basina tek oy (oyu daire amiri verir).

import { addDays } from '../lib/util.mjs';

const SURVEYS = [
  { title: 'Asansör Yenileme Onayı', question: 'Asansörlerin modernizasyonu için katkı payı toplanmasını onaylıyor musunuz?', options: ['Evet, yenilensin', 'Hayır, bakımla devam edilsin', 'Kararsızım'], open: '2024-02-05', close: '2024-02-19', weights: [0.8, 0.1, 0.1], turnout: 0.9 },
  { title: 'Otopark Güvenlik Kamerası', question: 'Otopark girişine ek güvenlik kamerası takılmasına olumlu bakıyor musunuz?', options: ['Evet', 'Hayır', 'Fark etmez'], open: '2023-10-02', close: '2023-10-16', weights: [0.7, 0.1, 0.2], turnout: 0.8 },
  { title: 'Dış Cephe Boya Rengi', question: 'Dış cephe boya rengi için hangi seçeneği tercih edersiniz?', options: ['Krem', 'Açık gri', 'Toprak tonu', 'Beyaz'], open: '2025-03-03', close: '2025-03-17', weights: [0.4, 0.3, 0.2, 0.1], turnout: 0.9 },
  { title: 'Bahçede Çocuk Oyun Alanı', question: 'Bahçenin bir bölümüne çocuk oyun alanı yapılmasını destekliyor musunuz?', options: ['Evet', 'Hayır'], open: '2025-09-01', close: '2025-09-15', weights: [0.6, 0.4], turnout: 0.8 },
  { title: 'Kış Dönemi Isıtma Saatleri', question: 'Merkezi ısıtmanın kış dönemi çalışma saatleri hangi şekilde olsun?', options: ['06:00-23:00', '07:00-22:00', 'Gün boyu açık'], open: 'TODAY-6', close: 'TODAY+9', weights: [0.4, 0.4, 0.2], turnout: 0.5, openNow: true },
  { title: 'Toplantı Salonu Kullanım Ücreti', question: 'Toplantı salonunun özel etkinlikler için sembolik bir kullanım ücretiyle verilmesini uygun buluyor musunuz?', options: ['Evet', 'Hayır', 'Ücretsiz kalsın ama depozito alınsın'], open: 'TODAY-3', close: 'TODAY+12', weights: [0.3, 0.3, 0.4], turnout: 0.4, openNow: true },
];

export async function seedSurveys(ctx) {
  const { q, rng, site, peopleResult, manager, TODAY } = ctx;
  const heads = peopleResult.households.map((h) => h.members.find((m) => m.isAmir));
  let surveys = 0;
  let votes = 0;
  const results = [];
  for (const s of SURVEYS) {
    const resolve = (v) => (v.startsWith('TODAY') ? addDays(TODAY, Number(v.slice(5) || 0)) : v);
    const open = resolve(s.open);
    const close = resolve(s.close);
    const isOpen = s.openNow === true;
    const r = await q(
      `INSERT INTO surveys (site_code, title, question, options, status, target_type, anonymous, one_vote_per_apartment, closes_at, opened_at, closed_at, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4::jsonb, $5, 'site', TRUE, TRUE, $6::timestamptz, $7::timestamptz, $8::timestamptz, $9, $7::timestamptz, $7::timestamptz) RETURNING id`,
      [
        site.code, s.title, s.question, JSON.stringify(s.options), isOpen ? 'open' : 'closed', `${close}T23:59:00+03:00`, `${open}T09:00:00+03:00`,
        isOpen ? null : `${close}T23:59:00+03:00`, manager.user_code,
      ],
    );
    const id = Number(r.rows[0].id);
    surveys += 1;
    const tally = s.options.map(() => 0);
    for (const head of heads) {
      if (!head || head.moveIn > open || !rng.chance(s.turnout)) continue;
      const choice = rng.weighted(s.weights.map((w, i) => [i, w]));
      const day = addDays(open, rng.int(0, Math.max(0, Math.min(12, Math.round((new Date(isOpen ? TODAY : close) - new Date(open)) / 86400000)))));
      await q(`INSERT INTO survey_votes (survey_id, user_code, apartment_id, option_index, voted_at) VALUES ($1, NULL, $2, $3, $4::timestamptz)`, [id, head.aptId, choice, `${day}T${String(rng.int(9, 22)).padStart(2, '0')}:20:00+03:00`]);
      tally[choice] += 1;
      votes += 1;
    }
    results.push({ title: s.title, tally });
  }
  return { surveys, votes, results };
}
