// Ziyaretci ve Kargo (modul: visitor_log): ~150 kayit; kargo firmalari, kuryeler, ziyaretciler; bugun 3-4 bekleyen kargo.
// Bildirim e-postasi YOK (cargo_notify_log'a yazilmaz).

import { addDays, dayNo, isoOf } from '../lib/util.mjs';
import { MALE_NAMES, FEMALE_NAMES, SURNAMES } from '../lib/identity.mjs';

const CARRIERS = ['Hızlı Kargo (Demo)', 'Mavi Ekspres (Demo)', 'Anadolu Lojistik (Demo)', 'Yıldırım Teslimat (Demo)', 'Ekin Kurye (Demo)'];
const RELATIONS = ['Akraba ziyareti', 'Arkadaş ziyareti', 'Tamirci', 'Teknik servis', 'Yemek siparişi', 'Doktor muayenesi', 'Nakliyat', 'Ev hizmetleri'];

export async function seedVisitors(ctx) {
  const { q, rng, site, apartments, peopleResult, TODAY, START } = ctx;
  const siteCode = site.code;
  const recorder = peopleResult.staff.find((s) => s.duty === 'doorman') ?? peopleResult.staff[0];
  const startN = dayNo('2023-02-01');
  const endN = dayNo(addDays(TODAY, -1));
  let cargo = 0;
  let visitors = 0;
  for (let i = 0; i < 150; i += 1) {
    const dayIso = isoOf(Math.floor(rng.float(startN, endN)));
    const apt = apartments[rng.int(0, apartments.length - 1)];
    const moveIn = peopleResult.peopleByApt.get(apt.id)?.[0]?.moveIn ?? START;
    const day = dayIso < moveIn ? moveIn : dayIso;
    const hour = rng.int(9, 20);
    const arrived = `${day}T${String(hour).padStart(2, '0')}:${String(rng.int(0, 59)).padStart(2, '0')}:00+03:00`;
    const done = `${day}T${String(Math.min(23, hour + rng.int(0, 2))).padStart(2, '0')}:${String(rng.int(0, 59)).padStart(2, '0')}:30+03:00`;
    const isCargo = rng.chance(0.66);
    if (isCargo) {
      const company = rng.pick(CARRIERS);
      const courier = `${rng.pick(MALE_NAMES)} ${rng.pick(SURNAMES)}`;
      const cancelled = rng.chance(0.04);
      await q(
        `INSERT INTO visitor_entries (site_code, kind, apartment_id, visitor_name, company, note, status, arrived_at, completed_at, recorded_by, completed_by, resident_seen_at, created_at, updated_at)
         VALUES ($1, 'cargo', $2, $3, $4, $5, $6, $7::timestamptz, $8::timestamptz, $9, $9, $8::timestamptz, $7::timestamptz, $8::timestamptz)`,
        [siteCode, apt.id, courier, company, rng.pick(['Koli', 'Zarf', 'Büyük paket', 'Market siparişi', null]), cancelled ? 'iptal' : 'teslim_edildi', arrived, done, recorder.userCode],
      );
      cargo += 1;
    } else {
      const name = `${rng.pick(rng.chance(0.5) ? MALE_NAMES : FEMALE_NAMES)} ${rng.pick(SURNAMES)}`;
      await q(
        `INSERT INTO visitor_entries (site_code, kind, apartment_id, visitor_name, company, note, status, arrived_at, completed_at, recorded_by, completed_by, resident_seen_at, created_at, updated_at)
         VALUES ($1, 'visitor', $2, $3, NULL, $4, 'ayrildi', $5::timestamptz, $6::timestamptz, $7, $7, $6::timestamptz, $5::timestamptz, $6::timestamptz)`,
        [siteCode, apt.id, name, rng.pick(RELATIONS), arrived, done, recorder.userCode],
      );
      visitors += 1;
    }
  }
  // bugun bekleyen: 4 kargo + 1 icerideki ziyaretci
  const nowTs = (h, m) => `${TODAY}T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00+03:00`;
  for (let i = 0; i < 4; i += 1) {
    const apt = apartments[(i * 3 + 1) % apartments.length];
    await q(
      `INSERT INTO visitor_entries (site_code, kind, apartment_id, visitor_name, company, note, status, arrived_at, recorded_by, created_at, updated_at)
       VALUES ($1, 'cargo', $2, $3, $4, $5, 'bekliyor', $6::timestamptz, $7, $6::timestamptz, $6::timestamptz)`,
      [siteCode, apt.id, `${rng.pick(MALE_NAMES)} ${rng.pick(SURNAMES)}`, CARRIERS[i % CARRIERS.length], 'Kapıda teslim bekliyor', nowTs(9 + i, 10 + i * 7), recorder.userCode],
    );
    cargo += 1;
  }
  await q(
    `INSERT INTO visitor_entries (site_code, kind, apartment_id, visitor_name, note, status, arrived_at, recorded_by, created_at, updated_at)
     VALUES ($1, 'visitor', $2, $3, 'Akraba ziyareti', 'iceride', $4::timestamptz, $5, $4::timestamptz, $4::timestamptz)`,
    [siteCode, apartments[4 % apartments.length].id, `${rng.pick(FEMALE_NAMES)} ${rng.pick(SURNAMES)}`, nowTs(10, 2), recorder.userCode],
  );
  visitors += 1;
  return { cargo, visitors };
}
