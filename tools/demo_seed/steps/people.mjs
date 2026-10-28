// Kisiler ve Daireler: hesaplar, daire uyelikleri, CRM kayitlari, yonetim kurulu, gorevliler, araclar, rehber.
// Modul: people (cekirdek) + directory (rehber; yalniz acikken).

import { addDays, addMonths } from '../lib/util.mjs';
import {
  BOY_NAMES, ELDER_FEMALE, ELDER_MALE, FEMALE_NAMES, GIRL_NAMES, MALE_NAMES, SURNAMES, displayPhone, emailOf, fakePhone, fakePlate, generatePassword, uniqueUsername,
} from '../lib/identity.mjs';
import { trackUpdate } from '../lib/registry.mjs';

const ROLE_LABEL = { owner: 'Malik', tenant: 'Kiracı', family_member: 'Aile', staff: 'Görevli' };

export async function seedPeople(ctx) {
  const { q, rng, site, apartments, manager, batchId, hashPassword, log } = ctx;
  const siteCode = site.code;
  const takenUsernames = new Set();
  const existing = await q(`SELECT lower(login_name) AS n FROM users WHERE login_name IS NOT NULL`);
  for (const row of existing.rows) takenUsernames.add(row.n);
  const takenSurnames = new Set();
  let phoneCounter = 100;
  const credentials = [];
  const plates = new Set();

  // --- daire ozellikleri (kat, arsa payi, kategori) ----------------------------------------------------------------------
  // Daire alani (m2) sistemde TUTULMAZ (migration 078 sutunlari kalici dusurdu): ne okunur ne yazilir. Arsa payini ve isi
  // tuketimini gercekci dagitmak icin oda tipine gore dairenin GORELI buyuklugu (birimsiz agirlik; 100 puan = kalorimetre
  // tablosundaki referans daire) uretilir; yalniz bellekte (apt.sizeWeight) kalir, veritabanina YAZILMAZ.
  const kinds = apartments.map((_, i) => ['2+1', '3+1', '3+1', '4+1', '3+1', '2+1', '3+1', '4+1', '2+1', '3+1'][i % 10]);
  const sizeRangeOf = { '2+1': [88, 96], '3+1': [112, 128], '4+1': [142, 156] };
  const sizeWeights = apartments.map((_, i) => Math.round(rng.float(...sizeRangeOf[kinds[i]])));
  const totalSizeWeight = sizeWeights.reduce((s, v) => s + v, 0);
  let usedShare = 0;
  const perBlockCounter = new Map();
  for (const [i, apt] of apartments.entries()) {
    const n = (perBlockCounter.get(apt.blockId) ?? 0) + 1;
    perBlockCounter.set(apt.blockId, n);
    const sizeWeight = sizeWeights[i];
    // Arsa payi (1000 uzerinden) dairenin goreli buyuklugune oranli; son daire kalani alir (toplam tam 1000). Aidat ve ek borclar bu paya gore dagitilir.
    const num = i === apartments.length - 1 ? 1000 - usedShare : Math.round((sizeWeight / totalSizeWeight) * 1000);
    usedShare += num;
    const update = {
      floor: apt.floor ?? ((n - 1) % 5) + 1,
      shareNum: apt.shareNum ?? num,
      shareDen: apt.shareDen ?? 1000,
      category: apt.category ?? kinds[i],
    };
    await trackUpdate({ query: q }, batchId, 'apartments', 'id = $1', [apt.id]);
    await q(
      `UPDATE apartments SET floor = $2, land_share_numerator = $3, land_share_denominator = $4, category = $5 WHERE id = $1`,
      [apt.id, update.floor, update.shareNum, update.shareDen, update.category],
    );
    Object.assign(apt, { floor: update.floor, sizeWeight, shareNum: update.shareNum, shareDen: update.shareDen, category: update.category });
  }

  // --- hane senaryolari -------------------------------------------------------------------------------------------------
  const count = apartments.length;
  const tenantCount = Math.max(1, Math.round(count * 0.3));
  const tenantIdx = new Set(rng.shuffle(apartments.map((_, i) => i)).slice(0, tenantCount));
  // Tasinma tarihi: yarisi site kuruldugundan beri (2019-2022), kalani son 1-3 yilda.
  const veteranCount = Math.ceil(count / 2);
  const veteranIdx = new Set(rng.shuffle(apartments.map((_, i) => i)).slice(0, veteranCount));
  const lateDates = ['2023-05-15', '2023-11-01', '2024-03-10', '2024-09-20', '2025-02-01', '2025-07-15', '2025-10-05', '2026-03-01'];
  const lateQueue = rng.shuffle(lateDates);

  const newUser = async ({ fullName, createdAt, phone }) => {
    const username = uniqueUsername(fullName, takenUsernames);
    const password = generatePassword(12);
    const passwordHash = await hashPassword(password);
    const email = emailOf(username);
    const r = await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, phone_number, password_hash, login_name, created_at, updated_at)
       VALUES ($1, $2, 'individual', TRUE, TRUE, 'approved', $3, $4, $5, $6::timestamptz, $6::timestamptz) RETURNING user_code`,
      [fullName, email, phone, passwordHash, username, createdAt],
    );
    const userCode = Number(r.rows[0].user_code);
    await q(
      `INSERT INTO notification_preferences (user_code, email_announcements, push_announcements, email_finance_reminders) VALUES ($1, FALSE, FALSE, FALSE)`,
      [userCode],
    );
    return { userCode, username, password, email };
  };

  const newPerson = async ({ userCode, active = true, fullName = null, phone = null, note = null, createdAt }) => {
    const r = await q(
      `INSERT INTO site_people (site_code, user_code, full_name, phone, email, note, is_active, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, NULL, $5, $6, $7, $8::timestamptz, $8::timestamptz) RETURNING id`,
      [siteCode, userCode, userCode ? null : fullName, userCode ? null : phone, note, active, manager.user_code, createdAt],
    );
    return Number(r.rows[0].id);
  };

  const people = [];
  const households = [];
  const peopleByApt = new Map();

  for (const [i, apt] of apartments.entries()) {
    const isTenantApt = tenantIdx.has(i);
    const moveIn = veteranIdx.has(i) ? `${rng.int(2019, 2022)}-${String(rng.int(1, 12)).padStart(2, '0')}-${String(rng.int(1, 28)).padStart(2, '0')}` : lateQueue.pop() ?? '2024-06-01';
    const isVeteran = veteranIdx.has(i);
    let surname = rng.pick(SURNAMES);
    for (let guard = 0; guard < 40 && takenSurnames.has(surname); guard += 1) surname = rng.pick(SURNAMES);
    takenSurnames.add(surname);
    const headMale = rng.chance(0.6);
    const headAge = rng.int(36, 56);
    const spouseAge = headAge + rng.int(-5, 3);
    const kidsCount = isTenantApt ? rng.int(1, 2) : rng.int(1, 2);
    const withElder = isTenantApt ? false : kidsCount === 1 ? true : rng.chance(0.45);
    const members = [];
    members.push({ role: 'head', male: headMale, age: headAge, relation: isTenantApt ? 'tenant' : 'owner' });
    members.push({ role: 'spouse', male: !headMale, age: spouseAge, relation: 'family_member' });
    for (let k = 0; k < kidsCount; k += 1) {
      const male = rng.chance(0.5);
      members.push({ role: 'child', male, age: rng.int(5, 24), relation: 'family_member' });
    }
    if (withElder) {
      const male = rng.chance(0.4);
      members.push({ role: 'elder', male, age: rng.int(62, 80), relation: 'family_member' });
    }
    let landlord = null;
    if (isTenantApt) {
      let landlordSurname = rng.pick(SURNAMES);
      for (let guard = 0; guard < 40 && takenSurnames.has(landlordSurname); guard += 1) landlordSurname = rng.pick(SURNAMES);
      takenSurnames.add(landlordSurname);
      landlord = { role: 'landlord', male: rng.chance(0.65), age: rng.int(55, 72), relation: 'owner', surname: landlordSurname };
    }
    // ad ata
    const usedGiven = new Set();
    const nameFor = (m) => {
      const pool = m.role === 'child' ? (m.male ? BOY_NAMES : GIRL_NAMES) : m.role === 'elder' ? (m.male ? ELDER_MALE : ELDER_FEMALE) : m.male ? MALE_NAMES : FEMALE_NAMES;
      let given = rng.pick(pool);
      for (let guard = 0; guard < 20 && usedGiven.has(given); guard += 1) given = rng.pick(pool);
      usedGiven.add(given);
      return `${given} ${m.surname ?? surname}`;
    };
    const all = landlord ? [...members, landlord] : members;
    const ownerAptCreatedAt = `${moveIn}T10:00:00+03:00`;
    const household = [];
    const prevResident = !isVeteran && !isTenantApt; // yeni tasinan malik: oncesinde baska malik oturmus
    let prevPersonId = null;
    if (prevResident) {
      const prevName = `${rng.pick([...MALE_NAMES, ...FEMALE_NAMES])} ${rng.pick(SURNAMES)}`;
      const prevEnd = addDays(moveIn, -rng.int(10, 40));
      prevPersonId = await newPerson({ userCode: null, active: false, fullName: prevName, phone: fakePhone(phoneCounter++), note: 'Önceki malik (demo)', createdAt: `${addMonths(prevEnd, -30)}T10:00:00+03:00` });
      await q(
        `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, move_out_date, origin, created_at)
         VALUES ($1, $2, $3, 'owner', FALSE, $4, $5, 'manual', $6::timestamptz)`,
        [siteCode, apt.id, prevPersonId, addMonths(prevEnd, -30), prevEnd, `${addMonths(prevEnd, -30)}T10:00:00+03:00`],
      );
    }
    for (const m of all) {
      const fullName = nameFor(m);
      const phone = m.age >= 16 || m.role === 'child' ? fakePhone(phoneCounter++) : fakePhone(phoneCounter++);
      const memberMoveIn = m.role === 'landlord' ? `${rng.int(2016, 2021)}-${String(rng.int(1, 12)).padStart(2, '0')}-${String(rng.int(1, 28)).padStart(2, '0')}` : moveIn;
      const createdAt = m.role === 'landlord' ? `${memberMoveIn}T10:00:00+03:00` : ownerAptCreatedAt;
      const account = await newUser({ fullName, createdAt, phone });
      const personId = await newPerson({ userCode: account.userCode, createdAt });
      const isHead = m.role === 'head';
      // Aile uyeleri icin tasinma tarihi ayni; ebeveyn kisilerine mal sahibi/kiraci iliskisi.
      await q(
        `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin, created_at)
         VALUES ($1, $2, $3, $4, TRUE, $5, 'manual', $6::timestamptz)`,
        [siteCode, apt.id, personId, m.relation, memberMoveIn, createdAt],
      );
      if (m.role !== 'landlord') {
        await q(
          `INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active, created_at, updated_at) VALUES ($1, $2, $3, TRUE, $4::timestamptz, $4::timestamptz)`,
          [apt.id, account.userCode, isHead ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER', createdAt],
        );
      }
      await q(
        `INSERT INTO site_memberships (site_code, user_code, role, is_active, created_at, updated_at) VALUES ($1, $2, 'RESIDENT', TRUE, $3::timestamptz, $3::timestamptz)`,
        [siteCode, account.userCode, createdAt],
      );
      if (isHead) {
        await q(`UPDATE apartments SET resident_user_code = $1 WHERE id = $2 AND resident_user_code IS NULL`, [account.userCode, apt.id]);
      }
      const person = {
        ...account,
        personId,
        fullName,
        phone,
        aptId: apt.id,
        aptIndex: i,
        label: apt.label,
        blockName: apt.blockName,
        unitLabel: apt.unitLabel,
        role: m.role,
        relation: m.relation,
        isAmir: isHead,
        male: m.male,
        age: m.age,
        moveIn: memberMoveIn,
        group: 'resident',
      };
      people.push(person);
      household.push(person);
      credentials.push({
        group: 'daire',
        block: apt.blockName,
        unit: apt.unitLabel,
        apartmentLabel: apt.label,
        fullName,
        roleLabel: m.role === 'landlord' ? 'Malik (dışarıda oturur)' : m.relation === 'owner' ? 'Malik' : m.relation === 'tenant' ? 'Kiracı' : 'Aile üyesi',
        isAmir: isHead,
        username: account.username,
        password: account.password,
        email: account.email,
        phone: displayPhone(phone),
      });
    }
    households.push({ aptId: apt.id, aptIndex: i, isTenantApt, moveIn, surname, members: household });
    peopleByApt.set(apt.id, household);
    apt.responsibleParty = isTenantApt && rng.chance(0.5) ? 'tenant' : apt.responsibleParty;
    apt.isTenantApt = isTenantApt;
    apt.moveIn = moveIn;
    apt.tenantSince = isTenantApt ? moveIn : null;
    await q(`UPDATE apartments SET responsible_party = $2 WHERE id = $1`, [apt.id, apt.responsibleParty]);
  }
  log(`Kisiler: ${people.length} sakin hesabi, ${households.length} hane (kiraci daire: ${[...tenantIdx].length})`);

  // --- araclar (daire basi 0-2) -----------------------------------------------------------------------------------------
  let vehicleCount = 0;
  const vehicles = [];
  for (const h of households) {
    const adults = h.members.filter((m) => m.role === 'head' || m.role === 'spouse');
    const n = rng.weighted([[0, 2], [1, 5], [2, 3]]);
    for (let k = 0; k < n; k += 1) {
      let plate = fakePlate(rng);
      while (plates.has(plate.normalized)) plate = fakePlate(rng);
      plates.add(plate.normalized);
      const owner = adults[k % adults.length];
      const r = await q(
        `INSERT INTO vehicles (site_code, person_id, apartment_id, plate, plate_display, note, is_active, created_at) VALUES ($1, $2, $3, $4, $5, $6, TRUE, $7::timestamptz) RETURNING id`,
        [siteCode, owner.personId, h.aptId, plate.normalized, plate.display, k === 0 ? 'Ana araç' : 'İkinci araç', `${owner.moveIn}T11:00:00+03:00`],
      );
      vehicles.push({ id: Number(r.rows[0].id), plate: plate.normalized, display: plate.display, aptId: h.aptId, personId: owner.personId, owner: owner.fullName });
      vehicleCount += 1;
    }
  }
  log(`Araclar: ${vehicleCount}`);

  // --- yonetim kurulu (farkli dairelerden 4 yetiskin) ---------------------------------------------------------------------
  const boardSpec = [
    { duty: 'board_member', title: 'Yönetim Kurulu Başkanı', label: 'Yönetim Kurulu Başkanı' },
    { duty: 'board_member', title: 'Yönetim Kurulu Üyesi', label: 'Yönetim Kurulu Üyesi' },
    { duty: 'board_member', title: 'Yönetim Kurulu Üyesi', label: 'Yönetim Kurulu Üyesi' },
    { duty: 'auditor', title: 'Denetçi', label: 'Denetçi' },
  ];
  const candidateHouseholds = households.filter((h) => !h.isTenantApt || rng.chance(0.3));
  const boardHouseholds = rng.shuffle(candidateHouseholds).slice(0, boardSpec.length);
  const board = [];
  for (const [idx, spec] of boardSpec.entries()) {
    const h = boardHouseholds[idx];
    const adult = h.members.find((m) => m.role === 'head');
    await q(
      `INSERT INTO site_team_duties (site_code, person_id, duty, title, public_phone, show_in_directory, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, TRUE, $6, $7::timestamptz, $7::timestamptz)`,
      [siteCode, adult.personId, spec.duty, spec.title, adult.phone, manager.user_code, '2023-01-10T10:00:00+03:00'],
    );
    await q(`UPDATE site_memberships SET role = 'BOARD_MEMBER', updated_at = NOW() WHERE site_code = $1 AND user_code = $2 AND role = 'RESIDENT'`, [siteCode, adult.userCode]);
    adult.board = spec.label;
    board.push({ ...adult, title: spec.title });
    const cred = credentials.find((c) => c.username === adult.username);
    if (cred) cred.boardRole = spec.label;
  }

  // --- gorevliler (daireden bagimsiz hesaplar) ------------------------------------------------------------------------------
  const staffSpec = [
    { given: 'Ramazan', surname: 'Eren', duty: 'doorman', title: 'Kapıcı', since: '2022-09-01' },
    { given: 'Tahsin', surname: 'Ergin', duty: 'technical', title: 'Teknik Görevli', since: '2023-02-15' },
    { given: 'Gizem', surname: 'Altın', duty: 'reception', title: 'Danışma Görevlisi', since: '2024-04-01' },
  ];
  const staff = [];
  for (const s of staffSpec) {
    const fullName = `${s.given} ${s.surname}`;
    const phone = fakePhone(phoneCounter++);
    const createdAt = `${s.since}T09:00:00+03:00`;
    const account = await newUser({ fullName, createdAt, phone });
    const personId = await newPerson({ userCode: account.userCode, createdAt });
    await q(
      `INSERT INTO site_memberships (site_code, user_code, role, is_active, created_at, updated_at) VALUES ($1, $2, 'STAFF', TRUE, $3::timestamptz, $3::timestamptz)`,
      [siteCode, account.userCode, createdAt],
    );
    await q(
      `INSERT INTO site_team_duties (site_code, person_id, duty, title, public_phone, show_in_directory, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, TRUE, $6, $7::timestamptz, $7::timestamptz)`,
      [siteCode, personId, s.duty, s.title, phone, manager.user_code, createdAt],
    );
    staff.push({ ...account, personId, fullName, phone, duty: s.duty, title: s.title, group: 'staff' });
    credentials.push({
      group: 'gorevli', apartmentLabel: '-', fullName, roleLabel: s.title, isAmir: false, username: account.username, password: account.password,
      email: account.email, phone: displayPhone(phone),
    });
  }
  log(`Yonetim kurulu: ${board.length}, gorevli: ${staff.length}`);

  // --- rehber (faydali telefonlar) -------------------------------------------------------------------------------------------
  let directoryCount = 0;
  if (ctx.enabled.directory) {
    const contacts = [
      ['Ambulans', '112', 'emergency', 'Acil sağlık'],
      ['İtfaiye', '110', 'emergency', 'Yangın ve kurtarma'],
      ['Polis İmdat', '155', 'emergency', null],
      ['Jandarma', '156', 'emergency', null],
      ['Elektrik Arıza', '186', 'utility', 'Dağıtım şirketi arıza hattı'],
      ['Su Arıza', '185', 'utility', 'Belediye su idaresi'],
      ['Doğalgaz Acil', '187', 'utility', 'Gaz kaçağı ve arıza'],
      ['Site Yönetimi', displayPhone(fakePhone(phoneCounter++)), 'management', 'Hafta içi 09:00-18:00'],
      ['Kapıcı', displayPhone(staff[0].phone), 'management', 'Gündüz görevlisi'],
      ['Asansör Bakım Firması', displayPhone(fakePhone(phoneCounter++)), 'service', 'Arıza bildirimi 7/24'],
      ['Kazan Bakım Servisi', displayPhone(fakePhone(phoneCounter++)), 'service', null],
      ['Çilingir', displayPhone(fakePhone(phoneCounter++)), 'other', null],
    ];
    for (const [idx, [label, phone, category, note]] of contacts.entries()) {
      await q(
        `INSERT INTO site_directory_contacts (site_code, label, phone, note, category, sort_order, created_by, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())`,
        [siteCode, label, phone, note, category, idx, manager.user_code],
      );
      directoryCount += 1;
    }
  }

  return { people, households, peopleByApt, board, staff, vehicles, credentials, directoryCount, apartments };
}
