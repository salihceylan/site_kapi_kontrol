// Toplu yükleme (Faz 2b): KİŞİLER ve ARAÇLAR planlayıcıları. Saf: DB/ağ bağımsız (girdi: doğrulanmış satırlar + veritabanı anlık görüntüsü).
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Eşleşme / yinelenen kayıt politikası"). Satırlar SANAL bir durum üzerinde sırayla işlenir (mevcut kişiler + bu
// dosyada önceki satırlarla oluşan kişiler/ilişkiler/plakalar): böylece dosya içi yinelemeler, çelişkiler ve plaka çakışmaları doğal olarak yakalanır ve
// plan, veritabanındaki gerçek durumla birebir tutarlı kalır. Bir satır HATA verirse hiçbir etkisi sanal duruma da işlenmez (yarım satır yazılmaz).
//
// Mevcut kişi kuralları: hesaplı kişinin alanlarına dokunulmaz; hesapsız kişinin DOLU alanı ezilmez (yalnız boşlar dolar); hesaplı kişiye YENİ daire eklenmez;
// pasif kişi yalnız e-posta ile bulunur ve yeniden etkinleştirilir. Telefon TEK BAŞINA eşleştirme anahtarı DEĞİLDİR (yalnız e-posta ve daire yokken ad ile birlikte).

import { foldText } from './people_common.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import {
  readDate,
  readEmail,
  readName,
  readPhone,
  readPlates,
  readRelation,
  readText,
} from './bulk_import_parsers.js';
import { addIssue, buildLocator, completeRow, finalizePlan, newRowResult } from './bulk_import_plan_common.js';

const RELATION_TR = Object.freeze({ owner: 'Malik', tenant: 'Kiracı', family_member: 'Aile Üyesi', resident: 'Sakin' });

const nameKey = (name) => foldText(name ?? '').replace(/\s+/g, ' ').trim();
const lower = (value) => (typeof value === 'string' && value.trim() !== '' ? value.trim().toLowerCase() : null);

function loosePhone(value) {
  if (value === null || value === undefined) return null;
  const digits = String(value).replace(/\D/g, '');
  if (digits === '') return null;
  let rest = digits;
  if (rest.startsWith('90') && rest.length === 12) rest = rest.slice(2);
  else if (rest.startsWith('0') && rest.length === 11) rest = rest.slice(1);
  return rest.length === 10 ? `+90${rest}` : `?${digits}`;
}

function addToList(map, key, value) {
  const list = map.get(key);
  if (list) list.push(value);
  else map.set(key, [value]);
}

function setHolder(state, aptId, relation, key) {
  if (relation !== 'owner' && relation !== 'tenant') return;
  const holders = state.holders.get(aptId) ?? { owner: null, tenant: null };
  holders[relation] = key;
  state.holders.set(aptId, holders);
}

/** Dairede bu ilişki (malik/kiracı) başka birinde mi? `key` kendisi ise uygun. */
function relationAvailable(state, aptId, relation, key) {
  if (relation !== 'owner' && relation !== 'tenant') return true;
  const holder = state.holders.get(aptId)?.[relation] ?? null;
  return holder === null || holder === key;
}

/**
 * Sanal durum. snapshot.people: { id, userCode, isActive, spName, spPhone, spEmail, note, uName, uPhone, uEmail };
 * snapshot.residencies (yalnız güncel): { id, apartmentId, personId, relation }; snapshot.vehicles (yalnız aktif): { id, personId, plate }.
 */
export function buildPeopleState(snapshot) {
  const state = {
    persons: new Map(),
    byEmail: new Map(),
    byApt: new Map(),
    byName: new Map(),
    holders: new Map(),
    plateOwner: new Map(),
    touched: new Map(),
  };
  const ordered = [...snapshot.people].sort((a, b) => (a.isActive === b.isActive ? a.id - b.id : a.isActive ? -1 : 1));
  for (const person of ordered) {
    const hasUser = person.userCode !== null && person.userCode !== undefined;
    const accountName = typeof person.uName === 'string' && person.uName.trim() !== '' ? person.uName : null;
    const accountPhone = typeof person.uPhone === 'string' && person.uPhone.trim() !== '' ? person.uPhone : null;
    const accountEmail = lower(person.uEmail);
    const contactEmail = !hasUser
      ? lower(person.spEmail)
      : accountEmail !== null && !accountEmail.endsWith(INTERNAL_EMAIL_SUFFIX)
        ? accountEmail
        : lower(person.spEmail);
    const vp = {
      key: `p${person.id}`,
      id: Number(person.id),
      isNew: false,
      active: person.isActive === true,
      protectedAccount: hasUser,
      name: (hasUser ? accountName : null) ?? person.spName ?? null,
      phone: loosePhone((hasUser ? accountPhone : null) ?? person.spPhone),
      email: contactEmail,
      note: person.note ?? null,
      residencies: new Map(),
    };
    state.persons.set(vp.key, vp);
    for (const email of new Set([lower(person.spEmail), accountEmail].filter((value) => value !== null))) {
      addToList(state.byEmail, email, vp);
    }
    if (vp.active && vp.name) {
      addToList(state.byName, nameKey(vp.name), vp);
    }
  }
  for (const residency of snapshot.residencies) {
    const vp = state.persons.get(`p${residency.personId}`);
    if (!vp) continue;
    const aptId = Number(residency.apartmentId);
    vp.residencies.set(aptId, { id: Number(residency.id), relation: residency.relation, isNew: false });
    const set = state.byApt.get(aptId) ?? new Set();
    set.add(vp);
    state.byApt.set(aptId, set);
    setHolder(state, aptId, residency.relation, vp.key);
  }
  for (const vehicle of snapshot.vehicles) {
    state.plateOwner.set(vehicle.plate, {
      key: vehicle.personId === null || vehicle.personId === undefined ? 'p?' : `p${vehicle.personId}`,
      source: 'db',
    });
  }
  return state;
}

/** Satır HATASIZ tamamlandığında işlemleri sanal duruma işler. */
function applyOps(state, ops) {
  for (const op of ops) {
    switch (op.t) {
      case 'pc': {
        const vp = {
          key: op.ref,
          id: null,
          isNew: true,
          active: true,
          protectedAccount: false,
          name: op.name,
          phone: op.phone,
          email: op.email,
          note: op.note,
          residencies: new Map(),
        };
        state.persons.set(vp.key, vp);
        if (vp.email) addToList(state.byEmail, vp.email, vp);
        addToList(state.byName, nameKey(vp.name), vp);
        break;
      }
      case 'pf': {
        const vp = state.persons.get(op.ref);
        if (op.field === 'phone') vp.phone = op.value;
        else if (op.field === 'email') {
          vp.email = op.value;
          addToList(state.byEmail, op.value, vp);
        } else vp.note = op.value;
        break;
      }
      case 'pr': {
        const vp = state.persons.get(op.ref);
        vp.active = true;
        if (op.name) vp.name = op.name;
        if (op.phone) vp.phone = op.phone;
        if (vp.name) addToList(state.byName, nameKey(vp.name), vp);
        break;
      }
      case 'ra': {
        const vp = state.persons.get(op.ref);
        vp.residencies.set(op.aptId, { id: null, relation: op.relation, isNew: true });
        const set = state.byApt.get(op.aptId) ?? new Set();
        set.add(vp);
        state.byApt.set(op.aptId, set);
        setHolder(state, op.aptId, op.relation, vp.key);
        break;
      }
      case 'ru': {
        const vp = state.persons.get(op.ref);
        const entry = vp.residencies.get(op.aptId);
        entry.relation = op.to;
        setHolder(state, op.aptId, op.to, vp.key);
        break;
      }
      case 'va':
        state.plateOwner.set(op.plate, { key: op.ref, source: 'file' });
        break;
      default:
        break;
    }
  }
}

/**
 * Plaka işleme (kişiler ve araçlar için ortak). `severityForSkipped`: atlanan plaka sorunlarının önemi.
 * @returns {{ added: number, unchanged: number, skipped: string[] }} atlanan sorunların sonuçtaki dizinleri döner
 */
function planPlates({ result, kind, state, ref, plates, invalid, note }) {
  let added = 0;
  let unchanged = 0;
  const skippedAt = [];
  for (const raw of invalid) {
    addIssue(result, kind, 'PLATE_INVALID', 'plaka', { value: raw }, 'warning');
    skippedAt.push(result.issues.length - 1);
  }
  for (const { plate, display } of plates) {
    const owner = state.plateOwner.get(plate);
    if (!owner) {
      result.ops.push({ t: 'va', ref, plate, display, note: note ?? null });
      added += 1;
    } else if (owner.key === ref) {
      unchanged += 1;
    } else {
      addIssue(result, kind, owner.source === 'db' ? 'PLATE_EXISTS' : 'PLATE_DUP_IN_FILE', 'plaka', { value: display }, 'warning');
      skippedAt.push(result.issues.length - 1);
    }
  }
  return { added, unchanged, skippedAt };
}

function summarize(name, aptLabel, relation, plateCount) {
  let text = name ?? '';
  if (aptLabel) text += ` → ${aptLabel} (${RELATION_TR[relation ?? 'resident']})`;
  if (plateCount > 0) text += ` + ${plateCount} plaka`;
  return text;
}

// ===============================================================================================================
// KİŞİLER
// ===============================================================================================================

/**
 * @param {{ rows: { n: number, cells: object }[], snapshot: object, today: string }} input
 */
export function planPeople({ rows, snapshot, today }) {
  const KIND = 'people';
  const locator = buildLocator(snapshot);
  const state = buildPeopleState(snapshot);
  const counts = {
    people_create: 0,
    people_link: 0,
    people_reactivate: 0,
    people_filled: 0,
    residency_add: 0,
    residency_upgrade: 0,
    residency_unchanged: 0,
    vehicle_add: 0,
    vehicle_unchanged: 0,
  };
  const linked = new Set();
  const filled = new Set();
  const results = [];

  for (const row of rows) {
    const cells = row.cells;
    // Ön doldurulmuş şablonda yalnızca blok ve daire kalmış, hiçbir kişi verisi girilmemişse boş satır sayıp atla
    const hasPerson = Boolean(
      (cells.ad_soyad !== null && cells.ad_soyad !== undefined && String(cells.ad_soyad).trim() !== '') ||
      (cells.telefon !== null && cells.telefon !== undefined && String(cells.telefon).trim() !== '') ||
      (cells.e_posta !== null && cells.e_posta !== undefined && String(cells.e_posta).trim() !== '') ||
      (cells.plaka !== null && cells.plaka !== undefined && String(cells.plaka).trim() !== '')
    );
    if (!hasPerson) continue;

    const result = newRowResult(row.n);
    const issue = (code, field, ctx, severity) => addIssue(result, KIND, code, field, ctx, severity);
    const local = { residencyUnchanged: 0, vehicleUnchanged: 0, linkedKey: null, touch: null };
    let targetSig = '';

    const nameR = readName(cells.ad_soyad);
    if (nameR.error) issue(nameR.error, 'ad_soyad', { ...nameR, value: cells.ad_soyad });
    else if (nameR.value === null) issue('REQUIRED', 'ad_soyad');
    const phoneR = readPhone(cells.telefon);
    if (phoneR.error) issue(phoneR.error, 'telefon', { ...phoneR, value: cells.telefon });
    const emailR = readEmail(cells.e_posta);
    if (emailR.error) issue(emailR.error, 'e_posta', { ...emailR, value: cells.e_posta });
    const blockR = readText(cells.blok, { forbidSigned: true, max: 60 });
    if (blockR.error) issue(blockR.error, 'blok', blockR);
    const numberR = readText(cells.daire_no, { max: 30 });
    if (numberR.error) issue(numberR.error, 'daire_no', numberR);
    const noteR = readText(cells.not, { multiline: true, max: 500 });
    if (noteR.error) issue(noteR.error, 'not', noteR);
    const platesR = readPlates(cells.plaka);
    if (platesR.error) issue(platesR.error, 'plaka', platesR);

    const email = emailR.value ?? null;
    const phone = phoneR.value ?? null;
    const name = nameR.value ?? null;
    const note = noteR.value ?? null;

    let apartment = null;
    let fileRelation = null;
    let moveIn = null;
    const hasBlock = blockR.value !== null && blockR.value !== undefined;
    const hasNumber = numberR.value !== null && numberR.value !== undefined;
    if (hasBlock !== hasNumber && !blockR.error && !numberR.error) {
      issue('APARTMENT_REQUIRED', 'daire_no');
    } else if (hasBlock && hasNumber) {
      const resolved = locator.resolve(blockR.value, numberR.value);
      if (resolved.error === 'BLOCK_NOT_FOUND') issue('BLOCK_NOT_FOUND', 'blok', { value: blockR.value, blocks: locator.blockNames });
      else if (resolved.error === 'BLOCK_AMBIGUOUS') issue('BLOCK_AMBIGUOUS', 'blok', { value: blockR.value });
      else if (resolved.error === 'APARTMENT_NOT_FOUND') issue('APARTMENT_NOT_FOUND', 'daire_no', { value: `${resolved.block.name} - ${numberR.value}` });
      else apartment = resolved.apartment;
      const relationR = readRelation(cells.iliski);
      if (relationR.error) issue(relationR.error, 'iliski', { ...relationR, value: cells.iliski });
      else fileRelation = relationR.value && relationR.value !== 'resident' ? relationR.value : null;
      const dateR = readDate(cells.giris_tarihi, today);
      if (dateR.error) issue(dateR.error, 'giris_tarihi', { ...dateR, value: cells.giris_tarihi });
      else {
        moveIn = dateR.value;
        for (const code of dateR.warnings ?? []) issue(code, 'giris_tarihi', { value: dateR.value });
      }
    }

    if (!result.hasError && email === null && apartment === null && phone === null) {
      issue('NO_IDENTIFIER', 'e_posta');
    }

    const finish = () => {
      completeRow(result, targetSig);
      if (!result.hasError) {
        applyOps(state, result.ops);
        for (const op of result.ops) {
          if (op.t === 'pc') counts.people_create += 1;
          else if (op.t === 'pr') counts.people_reactivate += 1;
          else if (op.t === 'ra') counts.residency_add += 1;
          else if (op.t === 'ru') counts.residency_upgrade += 1;
          else if (op.t === 'va') counts.vehicle_add += 1;
          else if (op.t === 'pf' && !op.ref.startsWith('new:')) filled.add(op.ref);
        }
        counts.residency_unchanged += local.residencyUnchanged;
        counts.vehicle_unchanged += local.vehicleUnchanged;
        if (local.linkedKey) linked.add(local.linkedKey);
        if (local.touch && !state.touched.has(local.touch.key)) state.touched.set(local.touch.key, local.touch);
      }
      results.push(result);
    };

    if (result.hasError) {
      finish();
      continue;
    }

    // --- eşleşme: e-posta -> (daire + ad) -> (ad + telefon; e-posta ve daire yokken) ---------------------------
    const wantedName = nameKey(name);
    let target = null;
    if (email !== null) {
      target = state.byEmail.get(email)?.[0] ?? null;
    }
    if (target === null && apartment !== null) {
      const found = [];
      for (const vp of state.byApt.get(apartment.id) ?? []) {
        if (!vp.active || nameKey(vp.name) !== wantedName) continue;
        if (email !== null && vp.email !== null && vp.email !== email) continue;
        if (phone !== null && vp.phone !== null && vp.phone !== phone) continue;
        found.push(vp);
      }
      if (found.length > 1) {
        issue('PERSON_AMBIGUOUS', 'ad_soyad');
        finish();
        continue;
      }
      target = found[0] ?? null;
    }
    if (target === null && email === null && apartment === null) {
      const found = (state.byName.get(wantedName) ?? []).filter((vp) => vp.active && vp.phone !== null && vp.phone === phone);
      if (found.length > 1) {
        issue('PERSON_AMBIGUOUS', 'ad_soyad');
        finish();
        continue;
      }
      target = found[0] ?? null;
    }

    const aptLabel = apartment ? locator.labelOfApartment(apartment) : null;
    const relationForNew = fileRelation ?? 'resident';
    let summaryRelation = fileRelation;

    if (target === null) {
      // ---- yeni (hesapsız) kişi
      const ref = `new:${row.n}`;
      targetSig = `new|${apartment?.id ?? ''}`;
      if (apartment !== null && !relationAvailable(state, apartment.id, relationForNew, ref)) {
        issue('RELATION_TAKEN', 'iliski');
        finish();
        continue;
      }
      result.ops.push({ t: 'pc', ref, name, phone, email, note });
      if (apartment !== null) {
        result.ops.push({ t: 'ra', ref, aptId: apartment.id, relation: relationForNew, moveIn });
        summaryRelation = relationForNew;
        local.touch = { key: `${ref}|${apartment.id}`, n: row.n, relation: fileRelation };
      }
      const plateStats = planPlates({ result, kind: KIND, state, ref, plates: platesR.plates ?? [], invalid: platesR.invalid ?? [], note: null });
      local.vehicleUnchanged += plateStats.unchanged;
      result.action = 'create';
      result.summary = summarize(name, aptLabel, summaryRelation, plateStats.added);
      finish();
      continue;
    }

    // ---- mevcut kişi (veritabanından ya da dosyada önceki satırdan)
    const ref = target.key;
    targetSig = `${ref}|${apartment?.id ?? ''}`;
    if (!target.isNew) local.linkedKey = ref;

    if (!target.active) {
      issue('REACTIVATE_PERSON', null, {}, 'warning');
      result.ops.push({ t: 'pr', ref, name: target.protectedAccount ? null : name, phone: target.protectedAccount ? null : phone });
    }

    let conflict = false;
    if (apartment !== null) {
      const touchedKey = `${ref}|${apartment.id}`;
      const earlier = state.touched.get(touchedKey);
      if (earlier) {
        if (fileRelation !== null && earlier.relation !== null && fileRelation !== earlier.relation) {
          issue('CONFLICTING_ROWS', 'iliski', { line: earlier.n });
          conflict = true;
        } else {
          issue('DUPLICATE_IN_FILE', null, { line: earlier.n }, 'warning');
        }
      }
      if (!conflict) {
        const current = target.residencies.get(apartment.id);
        if (!current) {
          if (target.protectedAccount && !target.isNew) {
            issue('ACCOUNT_NEW_APARTMENT', null, {}, 'warning');
          } else if (!relationAvailable(state, apartment.id, relationForNew, ref)) {
            issue('RELATION_TAKEN', 'iliski');
          } else {
            result.ops.push({ t: 'ra', ref, aptId: apartment.id, relation: relationForNew, moveIn });
            summaryRelation = relationForNew;
          }
        } else if (current.relation === 'resident' && fileRelation !== null) {
          if (!relationAvailable(state, apartment.id, fileRelation, ref)) {
            issue('RELATION_TAKEN', 'iliski');
          } else {
            result.ops.push({ t: 'ru', ref, aptId: apartment.id, residencyId: current.id, from: 'resident', to: fileRelation });
            summaryRelation = fileRelation;
          }
        } else {
          summaryRelation = current.relation;
          if (fileRelation !== null && current.relation !== fileRelation) {
            issue('RELATION_DIFFERS', 'iliski', {}, 'warning');
          } else {
            local.residencyUnchanged += 1;
          }
        }
      }
    }

    if (conflict || result.hasError) {
      finish();
      continue;
    }

    // hesapsız kişinin BOŞ alanları dosyadan dolar (dolu alana dokunulmaz); hesaplı kişiye dokunulmaz
    if (!target.protectedAccount) {
      const reactivatingWithPhone = !target.active && phone !== null;
      if (phone !== null && target.phone === null && !reactivatingWithPhone) {
        result.ops.push({ t: 'pf', ref, field: 'phone', value: phone });
      }
      if (email !== null && target.email === null) {
        result.ops.push({ t: 'pf', ref, field: 'email', value: email });
      }
      if (note !== null && target.note === null) {
        result.ops.push({ t: 'pf', ref, field: 'note', value: note });
      }
    }

    const plateStats = planPlates({ result, kind: KIND, state, ref, plates: platesR.plates ?? [], invalid: platesR.invalid ?? [], note: null });
    local.vehicleUnchanged += plateStats.unchanged;

    if (apartment !== null) {
      local.touch = { key: `${ref}|${apartment.id}`, n: row.n, relation: fileRelation };
    }
    const hasAdd = result.ops.some((op) => op.t === 'ra' || op.t === 'va');
    result.action = result.ops.length === 0 ? 'unchanged' : hasAdd ? 'link' : 'update';
    result.summary = summarize(name ?? target.name, aptLabel, summaryRelation, plateStats.added);
    finish();
  }

  counts.people_link = linked.size;
  counts.people_filled = filled.size;
  return finalizePlan({ kind: KIND, results, counts });
}

// ===============================================================================================================
// ARAÇLAR
// ===============================================================================================================

/**
 * @param {{ rows: { n: number, cells: object }[], snapshot: object, today?: string }} input
 */
export function planVehicles({ rows, snapshot }) {
  const KIND = 'vehicles';
  const locator = buildLocator(snapshot);
  const state = buildPeopleState(snapshot);
  const counts = { vehicle_add: 0, vehicle_unchanged: 0, people_link: 0 };
  const linked = new Set();
  const results = [];

  for (const row of rows) {
    const cells = row.cells;
    // Ön doldurulmuş şablonda yalnızca blok ve daire kalmış, hiçbir araç/plaka verisi girilmemişse boş satır sayıp atla
    const hasVehicle = Boolean(
      (cells.plaka !== null && cells.plaka !== undefined && String(cells.plaka).trim() !== '') ||
      (cells.e_posta !== null && cells.e_posta !== undefined && String(cells.e_posta).trim() !== '') ||
      (cells.ad_soyad !== null && cells.ad_soyad !== undefined && String(cells.ad_soyad).trim() !== '')
    );
    if (!hasVehicle) continue;

    const result = newRowResult(row.n);
    const issue = (code, field, ctx, severity) => addIssue(result, KIND, code, field, ctx, severity);
    const local = { vehicleUnchanged: 0, linkedKey: null };
    let targetSig = '';

    const platesR = readPlates(cells.plaka);
    if (platesR.error) issue(platesR.error, 'plaka', platesR);
    else if ((platesR.plates ?? []).length === 0 && (platesR.invalid ?? []).length === 0) issue('PLATE_REQUIRED', 'plaka');
    const emailR = readEmail(cells.e_posta);
    if (emailR.error) issue(emailR.error, 'e_posta', { ...emailR, value: cells.e_posta });
    const blockR = readText(cells.blok, { forbidSigned: true, max: 60 });
    if (blockR.error) issue(blockR.error, 'blok', blockR);
    const numberR = readText(cells.daire_no, { max: 30 });
    if (numberR.error) issue(numberR.error, 'daire_no', numberR);
    const nameR = readName(cells.ad_soyad);
    if (nameR.error) issue(nameR.error, 'ad_soyad', { ...nameR, value: cells.ad_soyad });
    const noteR = readText(cells.not, { multiline: true, max: 500 });
    if (noteR.error) issue(noteR.error, 'not', noteR);

    const email = emailR.value ?? null;
    const hasBlock = blockR.value !== null && blockR.value !== undefined;
    const hasNumber = numberR.value !== null && numberR.value !== undefined;
    let apartment = null;
    if (hasBlock !== hasNumber && !blockR.error && !numberR.error) {
      issue('APARTMENT_REQUIRED', 'daire_no');
    } else if (hasBlock && hasNumber) {
      const resolved = locator.resolve(blockR.value, numberR.value);
      if (resolved.error === 'BLOCK_NOT_FOUND') issue('BLOCK_NOT_FOUND', 'blok', { value: blockR.value, blocks: locator.blockNames });
      else if (resolved.error === 'BLOCK_AMBIGUOUS') issue('BLOCK_AMBIGUOUS', 'blok', { value: blockR.value });
      else if (resolved.error === 'APARTMENT_NOT_FOUND') issue('APARTMENT_NOT_FOUND', 'daire_no', { value: `${resolved.block.name} - ${numberR.value}` });
      else apartment = resolved.apartment;
    }

    const finish = () => {
      completeRow(result, targetSig);
      if (!result.hasError) {
        applyOps(state, result.ops);
        for (const op of result.ops) {
          if (op.t === 'va') counts.vehicle_add += 1;
        }
        counts.vehicle_unchanged += local.vehicleUnchanged;
        if (local.linkedKey) linked.add(local.linkedKey);
      }
      results.push(result);
    };

    if (result.hasError) {
      finish();
      continue;
    }

    // --- sahibi bul: önce e-posta; yoksa daire (tek sakin ise o, çoksa ad_soyad) -------------------------------
    let target = null;
    if (email !== null) {
      target = (state.byEmail.get(email) ?? []).find((vp) => vp.active) ?? null;
    }
    if (target === null && apartment !== null) {
      const residents = [...(state.byApt.get(apartment.id) ?? [])].filter((vp) => vp.active);
      if (residents.length === 1) {
        target = residents[0];
      } else if (residents.length > 1) {
        const wanted = nameR.value ? nameKey(nameR.value) : null;
        const named = wanted === null ? [] : residents.filter((vp) => nameKey(vp.name) === wanted);
        if (wanted === null || named.length > 1) {
          issue('PERSON_AMBIGUOUS', 'ad_soyad');
          finish();
          continue;
        }
        target = named[0] ?? null;
      }
    }
    if (target === null) {
      issue('PERSON_NOT_FOUND', email !== null ? 'e_posta' : 'daire_no');
      finish();
      continue;
    }

    const ref = target.key;
    targetSig = `${ref}|${apartment?.id ?? ''}`;
    local.linkedKey = ref;
    const stats = planPlates({ result, kind: KIND, state, ref, plates: platesR.plates ?? [], invalid: platesR.invalid ?? [], note: noteR.value ?? null });
    local.vehicleUnchanged += stats.unchanged;
    // Her plaka atlandıysa ve satırda eklenecek/mevcut plaka yoksa uyarılar HATAYA yükseltilir (satırdan hiçbir şey yüklenmedi).
    if (stats.added + stats.unchanged === 0 && stats.skippedAt.length > 0) {
      for (const index of stats.skippedAt) {
        result.issues[index].severity = 'error';
      }
      result.hasError = true;
    }
    result.action = result.ops.length > 0 ? 'link' : 'unchanged';
    result.summary = `${(platesR.plates ?? []).map((entry) => entry.display).join(', ')} → ${target.name ?? ''}`.trim();
    finish();
  }

  counts.people_link = linked.size;
  return finalizePlan({ kind: KIND, results, counts });
}
