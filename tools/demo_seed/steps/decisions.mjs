// Karar Defteri (modul: decision_book): yonetim kurulu toplantilari (uc aylik) + yillik genel kurullar; numarali kesin kararlar.

import { addDays } from '../lib/util.mjs';

export async function seedDecisions(ctx) {
  const { q, rng, site, people, peopleResult, manager, TODAY } = ctx;
  const siteCode = site.code;
  const boardNames = peopleResult.board.map((b) => b.fullName);
  const adultsAll = people.filter((p) => p.age >= 18 && p.isAmir);
  const meetings = [];
  for (let y = 2023; y <= Number(TODAY.slice(0, 4)); y += 1) {
    meetings.push({ date: `${y}-03-${String(rng.int(14, 28)).padStart(2, '0')}`, type: 'genel_kurul', year: y });
    for (const [m, d] of [['01', 12], ['06', 14], ['09', 20], ['12', 10]]) meetings.push({ date: `${y}-${m}-${String(d + rng.int(0, 4)).padStart(2, '0')}`, type: 'yonetim_kurulu', year: y });
  }
  const dueYear = { 2023: 1500, 2024: 2400, 2025: 3500, 2026: 4800 };
  const decisionsFor = (m) => {
    const list = [];
    if (m.type === 'genel_kurul') {
      list.push({ title: `${m.year - 1} yılı faaliyet raporunun görüşülmesi`, body: `${m.year - 1} yılı faaliyet raporu okunmuş, gelir-gider tabloları görüşülmüş ve yönetimin ibrasına oybirliğiyle karar verilmiştir.`, vote: 'kabul', f: 10, a: 0 });
      list.push({ title: `${m.year} yılı işletme projesinin onaylanması`, body: `${m.year} yılı gider bütçesi (işletme projesi) görüşülmüş ve sunulan haliyle kabul edilmiştir.`, vote: 'kabul', f: 9, a: 1 });
      list.push({ title: `${m.year} yılı aylık aidat tutarının belirlenmesi`, body: `Artan gider kalemleri dikkate alınarak ${m.year} yılı için daire başına ortalama aylık aidat tutarı ${dueYear[m.year] ?? 5000} TL olarak belirlenmiştir. Ödeme günü her ayın 10'udur.`, vote: 'kabul', f: 8, a: 2 });
      if (m.year % 2 === 1) list.push({ title: 'Yönetim kurulu ve denetçi seçimi', body: 'Yönetim kurulu başkanı, iki üye ve denetçi gizli oyla seçilmiş; seçilen kişilere görev süresi boyunca yetki verilmiştir.', vote: 'kabul', f: 10, a: 0 });
      if (m.year === 2024) list.push({ title: 'Asansör modernizasyonu için katkı payı', body: 'Her iki asansörün kumanda ve kabin yenilemesi için toplam bedelin arsa payı yerine brüt alana göre dağıtılarak mal sahiplerinden tahsiline karar verilmiştir.', vote: 'kabul', f: 8, a: 2 });
      if (m.year === 2025) list.push({ title: 'Dış cephe boya ve onarım işi', body: 'Dış cephe boya ve onarım işinin ihale usulüyle yaptırılmasına, bedelin mal sahiplerinden katkı payı olarak tahsil edilmesine karar verilmiştir.', vote: 'kabul', f: 9, a: 1 });
    } else {
      const pool = [
        { title: 'Asansör bakım sözleşmesinin yenilenmesi', body: 'Mevcut asansör bakım firmasıyla sözleşmenin bir yıl uzatılmasına ve aylık bedelin güncellenmesine karar verilmiştir.', vote: 'kabul' },
        { title: 'Kazan dairesi yıllık bakımının yaptırılması', body: 'Kış öncesi kazan ve baca bakımının yetkili serviste yaptırılmasına karar verilmiştir.', vote: 'kabul' },
        { title: 'Bahçe düzenleme ve peyzaj çalışması', body: 'İlkbahar öncesi bahçe düzenlemesi için teklif alınmasına ve en uygun teklifle anlaşılmasına karar verilmiştir.', vote: 'kabul' },
        { title: 'Gecikmiş aidat borçlarının takibi', body: 'Üç aydan fazla gecikmiş borçlular için yazılı bildirim yapılmasına, ödeme planı talep edenlerle taksit görüşmesi yapılmasına karar verilmiştir.', vote: 'kabul' },
        { title: 'Güvenlik kamerası sisteminin genişletilmesi', body: 'Otopark girişine ek kamera takılmasının maliyetinin araştırılmasına karar verilmiştir.', vote: 'ertelendi' },
        { title: 'Toplantı salonu kullanım kuralları', body: 'Toplantı salonunun yalnızca yönetim onayıyla ve en çok iki saat kullanılabileceği kuralının uygulanmasına karar verilmiştir.', vote: 'kabul' },
        { title: 'Çatı yalıtımı onarımı', body: 'Çatıdaki sızıntı nedeniyle yalıtım onarımının acil olarak yaptırılmasına karar verilmiştir.', vote: 'kabul' },
        { title: 'Sigorta poliçelerinin yenilenmesi', body: 'DASK ve bina yangın sigortalarının mart ayında yenilenmesine, üç teklif alınmasına karar verilmiştir.', vote: 'kabul' },
        { title: 'Yedek akçe oluşturulması', body: 'Beklenmedik giderler için aylık gelirin küçük bir bölümünün yedek akçe olarak ayrılmasına karar verilmiştir.', vote: 'kabul' },
      ];
      const n = rng.int(2, 3);
      for (let i = 0; i < n; i += 1) list.push({ ...rng.pick(pool), f: 4, a: rng.chance(0.15) ? 1 : 0 });
    }
    return list;
  };
  const perYearNo = {};
  let count = 0;
  for (const m of meetings.sort((a, b) => a.date.localeCompare(b.date))) {
    if (m.date > TODAY) continue;
    const attendees = m.type === 'genel_kurul'
      ? adultsAll.filter((p) => p.moveIn <= m.date).slice(0, rng.int(7, 10)).map((p) => p.fullName).join(', ')
      : boardNames.join(', ');
    const seen = new Set();
    for (const d of decisionsFor(m)) {
      if (seen.has(d.title)) continue;
      seen.add(d.title);
      perYearNo[m.year] = (perYearNo[m.year] ?? 0) + 1;
      await q(
        `INSERT INTO board_decisions (site_code, year, decision_no, meeting_type, meeting_date, title, body, attendees, vote_result, votes_for, votes_against, votes_abstain, visibility, status, finalized_at, finalized_by, created_by, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5::DATE, $6, $7, $8, $9, $10, $11, 0, $12, 'kesin', $13::timestamptz, $14, $14, $13::timestamptz, $13::timestamptz)`,
        [
          siteCode, m.year, perYearNo[m.year], m.type, m.date, d.title, d.body, attendees, d.vote, d.vote === 'bilgi' ? null : d.f, d.vote === 'bilgi' ? null : d.a,
          m.type === 'genel_kurul' ? 'sakinler' : 'yonetim', `${addDays(m.date, 1)}T10:00:00+03:00`, manager.user_code,
        ],
      );
      count += 1;
    }
  }
  // iki taslak karar (guncel)
  for (const [title, body] of [
    ['Kış hazırlığı: kazan ve baca temizliği teklifleri', 'Üç servis firmasından teklif alınacaktır. Teklifler gelecek toplantıda görüşülecektir.'],
    ['Yeni yıl işletme projesi taslağı', '2027 yılı işletme projesi taslağı hazırlanmış, kurul üyelerine görüşe sunulmuştur.'],
  ]) {
    await q(
      `INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, attendees, vote_result, visibility, status, created_by, created_at, updated_at)
       VALUES ($1, $2, 'yonetim_kurulu', $3::DATE, $4, $5, $6, 'bilgi', 'yonetim', 'taslak', $7, $8::timestamptz, $8::timestamptz)`,
      [siteCode, Number(TODAY.slice(0, 4)), TODAY, title, body, boardNames.join(', '), manager.user_code, `${TODAY}T09:00:00+03:00`],
    );
    count += 1;
  }
  return { count };
}
