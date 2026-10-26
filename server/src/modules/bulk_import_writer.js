// Toplu yükleme (Faz 2b): planı veritabanına YAZAR. Çağıran, commit transaction'ını (kilitler dahil) yönetir; burada yalnız küme tabanlı ifadeler çalışır.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Commit akışı" adım 5): kişi kimlikleri `nextval` ile önceden ayrılır (RETURNING sırasına güvenilmez) -> kişi
// INSERT/UPDATE -> ilişki INSERT (origin='manual') / UPDATE -> araç INSERT -> toplu audit INSERT (SAVEPOINT'siz). Tüm değerler PARAMETRELİ JSON dizileriyle
// (jsonb_to_recordset) gider; SQL'e metin birleştirilmez. Sabit sayıda sorgu: parça boyutu 5000 (audit 10000) olduğundan 5000 satırlık dosya <= birkaç ifade.
// Beklenmeyen 23505 / 23503 (yarış) ya da beklenen satır sayısının tutmaması -> 409 PREVIEW_STALE (çağıran ROLLBACK yapar).
//
// Hesap açma (`provisionImportedResidents`) kişi/ilişki yazımından SONRA, aynı transaction'da çalışır ve YALNIZ bu çalıştırmada daire ilişkisi eklenen
// kişilerle sınırlıdır (applyPeopleOps `accountCandidates` döner). Her kişi kendi SAVEPOINT'inde işlenir; üyelik kuralı people_service.grantApartmentAccess'indir.

import { hashPassword } from '../security/password_hashing.js';
import { ensureUniqueLoginName, generateUniqueApartmentLoginName } from '../services/apartment_service.js';
import { generateInternalApartmentEmail } from '../utils/helpers.js';
import { PlatformError } from './errors.js';
import { grantApartmentAccess } from './people_service.js';
import { siteTiePredicate } from './people_sync_sql.js';
import { logResidenciesBulk } from './residency_log.js';

export const ENTITY_CHUNK = 5000;
export const AUDIT_CHUNK = 10000;

export const staleError = () => new PlatformError(409, 'PREVIEW_STALE', 'Veriler değişti. Önizleme yenilendi, tekrar inceleyin.');

function* chunksOf(list, size) {
  for (let index = 0; index < list.length; index += size) {
    yield list.slice(index, index + size);
  }
}

async function run(client, sql, params) {
  try {
    return await client.query(sql, params);
  } catch (error) {
    if (error?.code === '23505' || error?.code === '23503') {
      throw staleError();
    }
    throw error;
  }
}

/** Audit satırlarını toplu ekler (SAVEPOINT'siz). Her satır: { action, target_type, target_id, details }. */
export async function insertAudits(client, { siteCode, actor, rows }) {
  for (const part of chunksOf(rows, AUDIT_CHUNK)) {
    await client.query(
      `
        INSERT INTO audit_log (actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details)
        SELECT $2::INTEGER, $3::TEXT, $4::TEXT, v.action, $5::BIGINT, v.target_type, v.target_id, v.details
        FROM jsonb_to_recordset($1::jsonb) AS v(action text, target_type text, target_id text, details jsonb)
      `,
      [JSON.stringify(part), actor.userCode ?? null, actor.name ?? null, actor.role ?? null, siteCode],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Daireler
// ---------------------------------------------------------------------------------------------------------------

const APARTMENT_COLUMNS = Object.freeze([
  ['floor', 'floor', 'integer'],
  ['category', 'category', 'text'],
  ['land_share_numerator', 'ln', 'integer'],
  ['land_share_denominator', 'ld', 'integer'],
  ['responsible_party', 'rp', 'text'],
]);

export async function applyApartmentOps(client, { siteCode, ops, runId }) {
  const audits = [];
  const updates = ops.filter((op) => op.t === 'au');
  for (const part of chunksOf(updates, ENTITY_CHUNK)) {
    const rows = part.map((op) => {
      const row = { id: op.aptId };
      for (const [column, short] of APARTMENT_COLUMNS) {
        row[`set_${short}`] = Object.prototype.hasOwnProperty.call(op.set, column);
        row[short] = row[`set_${short}`] ? op.set[column] : null;
      }
      return row;
    });
    const recordset = ['id bigint', ...APARTMENT_COLUMNS.flatMap(([, short, type]) => [`set_${short} boolean`, `${short} ${type}`])].join(', ');
    const sets = APARTMENT_COLUMNS.map(([column, short]) => `${column} = CASE WHEN v.set_${short} THEN v.${short} ELSE a.${column} END`).join(',\n          ');
    const result = await run(
      client,
      `
        UPDATE apartments a
        SET ${sets}
        FROM jsonb_to_recordset($1::jsonb) AS v(${recordset})
        WHERE a.id = v.id AND a.site_code = $2
      `,
      [JSON.stringify(rows), siteCode],
    );
    if (Number(result.rowCount) !== part.length) {
      throw staleError();
    }
  }
  for (const op of updates) {
    audits.push({
      action: 'apartment.updated',
      target_type: 'apartment',
      target_id: String(op.aptId),
      details: { changes: op.changes, via: 'import', run_id: runId },
    });
  }
  return audits;
}

// ---------------------------------------------------------------------------------------------------------------
// Kişiler ve araçlar
// ---------------------------------------------------------------------------------------------------------------

/**
 * @param {{ siteCode: number, ops: object[], runId: number, today: string, actorUserCode: number|null }} input
 * @returns {Promise<{ audits: object[], idByRef: Map<string, number>, accountCandidates: object[] }>} audit satırları (henüz yazılmadı), ref -> site_people.id
 *   haritası (yeni kişiler ayrılan kimlikle, mevcutlar kendi kimliğiyle) ve hesap açılabilecek adaylar (bu çalıştırmada daire ilişkisi EKLENEN kişiler)
 */
export async function applyPeopleOps(client, { siteCode, ops, runId, today, actorUserCode }) {
  const newPeople = new Map();
  const existing = new Map();
  const residencyAdds = [];
  const residencyUpgrades = [];
  const vehicleAdds = [];
  const aggFor = (ref) => {
    const id = Number(ref.slice(1));
    let entry = existing.get(id);
    if (!entry) {
      entry = { id, reactivate: false, name: null, phone: null, fill_phone: null, fill_email: null, fill_note: null };
      existing.set(id, entry);
    }
    return entry;
  };

  for (const op of ops) {
    switch (op.t) {
      case 'pc':
        newPeople.set(op.ref, {
          ref: op.ref,
          n: op.n ?? null,
          name: op.name,
          phone: op.phone,
          email: op.email,
          note: op.note,
          password: op.password,
          loginName: op.loginName ?? null,
        });
        break;
      case 'pf':
        if (op.ref.startsWith('new:')) {
          newPeople.get(op.ref)[op.field] = op.value;
        } else {
          aggFor(op.ref)[`fill_${op.field}`] = op.value;
        }
        break;
      case 'pr': {
        const entry = aggFor(op.ref);
        entry.reactivate = true;
        entry.name = op.name;
        entry.phone = op.phone;
        break;
      }
      case 'ra':
        residencyAdds.push({
          ref: op.ref,
          n: op.n ?? null,
          aptId: op.aptId,
          relation: op.relation,
          moveIn: op.moveIn ?? today,
          password: op.password,
          loginName: op.loginName ?? null,
        });
        break;
      case 'ru':
        if (op.residencyId === null || op.residencyId === undefined) {
          // aynı dosyada önce eklenen (henüz yazılmamış) ilişkinin yükseltilmesi: ekleme işlemine birleştirilir
          const pending = residencyAdds.find((entry) => entry.ref === op.ref && entry.aptId === op.aptId);
          if (pending) pending.relation = op.to;
        } else {
          residencyUpgrades.push(op);
        }
        break;
      case 'va':
        vehicleAdds.push(op);
        break;
      default:
        break;
    }
  }

  const audits = [];
  const idByRef = new Map();

  // 1. yeni kişiler: kimlikler önceden ayrılır
  const created = [...newPeople.values()];
  if (created.length > 0) {
    const sequence = await client.query(
      `SELECT nextval(pg_get_serial_sequence('site_people', 'id')) AS id FROM generate_series(1, $1::INTEGER)`,
      [created.length],
    );
    created.forEach((person, index) => {
      idByRef.set(person.ref, Number(sequence.rows[index].id));
    });
    for (const part of chunksOf(created, ENTITY_CHUNK)) {
      const rows = part.map((person) => ({ id: idByRef.get(person.ref), full_name: person.name, phone: person.phone, email: person.email, note: person.note }));
      await run(
        client,
        `
          INSERT INTO site_people (id, site_code, user_code, full_name, phone, email, note, created_by)
          SELECT v.id, $2::BIGINT, NULL, v.full_name, v.phone, v.email, v.note, $3::INTEGER
          FROM jsonb_to_recordset($1::jsonb) AS v(id bigint, full_name text, phone text, email text, note text)
        `,
        [JSON.stringify(rows), siteCode, actorUserCode],
      );
    }
    for (const person of created) {
      audits.push({
        action: 'person.created',
        target_type: 'person',
        target_id: String(idByRef.get(person.ref)),
        details: { has_account: false, via: 'import', run_id: runId },
      });
    }
  }
  const personIdOf = (ref) => (ref.startsWith('new:') ? idByRef.get(ref) : Number(ref.slice(1)));

  // 2. mevcut (hesapsız) kişilerin boş alanları ve yeniden etkinleştirme
  const updates = [...existing.values()];
  for (const part of chunksOf(updates, ENTITY_CHUNK)) {
    const result = await run(
      client,
      `
        UPDATE site_people sp
        SET is_active = CASE WHEN v.reactivate THEN TRUE ELSE sp.is_active END,
            full_name = CASE WHEN v.reactivate AND v.name IS NOT NULL AND sp.user_code IS NULL THEN v.name ELSE sp.full_name END,
            phone = CASE
              WHEN v.reactivate AND v.phone IS NOT NULL AND sp.user_code IS NULL THEN v.phone
              WHEN sp.user_code IS NULL AND sp.phone IS NULL AND v.fill_phone IS NOT NULL THEN v.fill_phone
              ELSE sp.phone END,
            email = CASE WHEN sp.user_code IS NULL AND sp.email IS NULL AND v.fill_email IS NOT NULL THEN v.fill_email ELSE sp.email END,
            note = CASE WHEN sp.note IS NULL AND v.fill_note IS NOT NULL THEN v.fill_note ELSE sp.note END,
            updated_at = NOW()
        FROM jsonb_to_recordset($1::jsonb) AS v(id bigint, reactivate boolean, name text, phone text, fill_phone text, fill_email text, fill_note text)
        WHERE sp.id = v.id AND sp.site_code = $2::BIGINT
      `,
      [JSON.stringify(part), siteCode],
    );
    if (Number(result.rowCount) !== part.length) {
      throw staleError();
    }
  }
  for (const entry of updates) {
    const changes = [];
    if (entry.reactivate) {
      changes.push({ field: 'is_active', from: false, to: true });
      if (entry.name) changes.push({ field: 'full_name', changed: true });
    }
    if ((entry.reactivate && entry.phone) || entry.fill_phone) changes.push({ field: 'phone', changed: true });
    if (entry.fill_email) changes.push({ field: 'email', changed: true });
    if (entry.fill_note) changes.push({ field: 'note', changed: true });
    if (changes.length > 0) {
      audits.push({
        action: 'person.updated',
        target_type: 'person',
        target_id: String(entry.id),
        details: { changes, via: 'import', run_id: runId },
      });
    }
  }

  // 3. ilişkiler: yükseltmeler, sonra eklemeler (aynı daire için malik/kiracı çakışması planlayıcıda elenmiştir)
  for (const part of chunksOf(residencyUpgrades, ENTITY_CHUNK)) {
    const result = await run(
      client,
      `
        UPDATE apartment_residencies r
        SET relation = v.relation, origin = 'manual', updated_at = NOW()
        FROM jsonb_to_recordset($1::jsonb) AS v(id bigint, relation text)
        WHERE r.id = v.id AND r.site_code = $2::BIGINT AND r.is_current = TRUE AND r.relation = 'resident'
      `,
      [JSON.stringify(part.map((op) => ({ id: op.residencyId, relation: op.to }))), siteCode],
    );
    if (Number(result.rowCount) !== part.length) {
      throw staleError();
    }
    // ADLI KAYIT (residency_log): "sakin" -> malik / kiraci / aile yukseltmesi (rol degisimi), ayni transaction'da.
    await logResidenciesBulk(client, { ids: part.map((op) => op.residencyId), eventType: 'role_changed', actorUserCode });
  }
  for (const op of residencyUpgrades) {
    audits.push({
      action: 'residency.updated',
      target_type: 'person',
      target_id: String(personIdOf(op.ref)),
      details: {
        residency_id: op.residencyId,
        apartment_id: op.aptId,
        changes: [{ field: 'relation', from: op.from, to: op.to }],
        via: 'import',
        run_id: runId,
      },
    });
  }
  for (const part of chunksOf(residencyAdds, ENTITY_CHUNK)) {
    const inserted = await run(
      client,
      `
        INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin)
        SELECT $2::BIGINT, v.apartment_id, v.person_id, v.relation, TRUE, v.move_in_date, 'manual'
        FROM jsonb_to_recordset($1::jsonb) AS v(apartment_id bigint, person_id bigint, relation text, move_in_date date)
        RETURNING id, apartment_id, person_id, relation
      `,
      [
        JSON.stringify(part.map((entry) => ({ apartment_id: entry.aptId, person_id: personIdOf(entry.ref), relation: entry.relation, move_in_date: entry.moveIn }))),
        siteCode,
      ],
    );
    if (inserted.rows.length !== part.length) {
      throw staleError();
    }
    // ADLI KAYIT (residency_log): toplu yuklemeyle eklenen ilişkiler (tasinma / sakin kaydi).
    await logResidenciesBulk(client, { ids: inserted.rows.map((row) => row.id), eventType: 'moved_in', actorUserCode });
    for (const row of inserted.rows) {
      audits.push({
        action: 'residency.added',
        target_type: 'person',
        target_id: String(row.person_id),
        details: { residency_id: Number(row.id), apartment_id: Number(row.apartment_id), relation: row.relation, via: 'import', run_id: runId },
      });
    }
  }

  // 4. araçlar
  for (const part of chunksOf(vehicleAdds, ENTITY_CHUNK)) {
    const inserted = await run(
      client,
      `
        INSERT INTO vehicles (site_code, person_id, plate, plate_display, note)
        SELECT $2::BIGINT, v.person_id, v.plate, v.display, v.note
        FROM jsonb_to_recordset($1::jsonb) AS v(person_id bigint, plate text, display text, note text)
        RETURNING id, person_id, plate
      `,
      [
        JSON.stringify(part.map((entry) => ({ person_id: personIdOf(entry.ref), plate: entry.plate, display: entry.display, note: entry.note }))),
        siteCode,
      ],
    );
    if (inserted.rows.length !== part.length) {
      throw staleError();
    }
    for (const row of inserted.rows) {
      audits.push({
        action: 'vehicle.added',
        target_type: 'vehicle',
        target_id: String(row.id),
        details: { plate: row.plate, person_id: Number(row.person_id), via: 'import', run_id: runId },
      });
    }
  }

  // ref -> kişi kimliği (bu çalıştırmada adı geçen tüm kişiler) ve hesap adayları
  for (const op of ops) {
    if (typeof op.ref === 'string' && !idByRef.has(op.ref)) idByRef.set(op.ref, personIdOf(op.ref));
  }
  return { audits, idByRef, accountCandidates: collectAccountCandidates({ newPeople, residencyAdds, idByRef }) };
}

/**
 * Hesap adayları: BU çalıştırmada daire ilişkisi eklenen (yeni ya da hesapsız mevcut) kişiler; kişi başına TEK aday (kişi iki dairede
 * eklenmişse iki daire ilişkilenir, tek hesap açılır). Şifre / kullanıcı adı kişi kimliğine (ref) bağlı işlemlerden gelir: yeni kişide `pc`,
 * mevcut kişide ilk `ra`. Ad / e-posta / telefon ile eşleştirme YAPILMAZ.
 */
function collectAccountCandidates({ newPeople, residencyAdds, idByRef }) {
  const byRef = new Map();
  for (const add of residencyAdds) {
    let candidate = byRef.get(add.ref);
    if (!candidate) {
      const created = newPeople.get(add.ref) ?? null;
      candidate = {
        ref: add.ref,
        personId: idByRef.get(add.ref),
        n: created?.n ?? add.n ?? null,
        password: created ? created.password : add.password,
        loginName: created ? created.loginName : add.loginName,
        apartments: [],
      };
      byRef.set(add.ref, candidate);
    }
    if (!candidate.apartments.some((entry) => entry.aptId === add.aptId)) {
      candidate.apartments.push({ aptId: add.aptId, relation: add.relation });
    }
  }
  return [...byRef.values()];
}

// ---------------------------------------------------------------------------------------------------------------
// Devir bakiyesi (F4): her satır tek defter kaydı (charge, source_kind='opening', source_id=çalıştırma). Defter yalnız eklemelidir.
// ---------------------------------------------------------------------------------------------------------------

export async function applyOpeningOps(client, { siteCode, ops, runId, cutoverDate, actorUserCode }) {
  const adds = ops.filter((op) => op.t === 'ob');
  let total = 0;
  for (const part of chunksOf(adds, ENTITY_CHUNK)) {
    const rows = part.map((op) => ({ apt: op.aptId, account: op.account, minor: String(op.minor), due: op.due, note: op.desc }));
    const result = await run(
      client,
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, payer_party, account_party,
          source_kind, source_id, description, created_by
        )
        SELECT $2::BIGINT, v.apt, 'charge', v.minor::BIGINT, date_trunc('month', $3::DATE)::DATE, $3::DATE, v.due::DATE, 'Devir bakiyesi',
               v.account, v.account, 'opening', $4::BIGINT, v.note, $5::INTEGER
        FROM jsonb_to_recordset($1::jsonb) AS v(apt bigint, account text, minor text, due text, note text)
      `,
      [JSON.stringify(rows), siteCode, cutoverDate, runId, actorUserCode ?? null],
    );
    if (result.rowCount !== part.length) {
      throw staleError();
    }
    total += part.reduce((sum, op) => sum + op.minor, 0);
  }
  return { audits: [], total };
}


// ---------------------------------------------------------------------------------------------------------------
// Hesap açma (kullanıcı adı + başlangıç şifresi + daire üyeliği)
// ---------------------------------------------------------------------------------------------------------------

/** Başlangıç şifresi boşsa verilen değer. Bu değer için TEK özet paylaşılır (aşağıda). */
export const DEFAULT_ACCOUNT_PASSWORD = '1234';
/** Kullanıcı adı tabanı üst sınırı: LOGIN_NAME_MAX (40) - "_NN" benzersizlik eki payı. İstemci (generateUsernameFromFullName) AYNI sınırı kullanır. */
export const LOGIN_NAME_BASE_MAX = 36;
const HASH_CONCURRENCY = 4;

/**
 * Ad ya da yazılan kullanıcı adından kullanıcı adı tabanı: Türkçe harfler sadeleşir, küçük harf, [a-z0-9] dışındaki her öbek tek nokta, baş/son nokta
 * atılır, en çok 36 karakter. İstemci tarafındaki `generateUsernameFromFullName` ile AYNI kural (tablodaki ad = sunucunun kullanacağı ad; çakışmada
 * sunucu `_2`, `_3` ... ekler ve nihai adı sonuçta döner).
 */
export function slugifyLoginName(fullName, fallback = 'kullanici') {
  if (!fullName || typeof fullName !== 'string') return fallback;
  const trMap = {
    'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'I': 'i', 'İ': 'i',
    'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
  };
  let clean = fullName.replace(/[çÇğĞıIİöÖşŞüÜ]/g, (m) => trMap[m] || m).toLowerCase();
  clean = clean.replace(/[^a-z0-9]+/g, '.').replace(/^\.+|\.+$/g, '');
  if (clean.length > LOGIN_NAME_BASE_MAX) clean = clean.slice(0, LOGIN_NAME_BASE_MAX).replace(/\.+$/, '');
  return clean || fallback;
}

/** Sınırlı eşzamanlılıkla eşleme (sıra korunmaz; her öğe tam bir kez işlenir). */
async function mapLimit(items, limit, handler) {
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next;
      next += 1;
      await handler(items[index], index);
    }
  });
  await Promise.all(workers);
}

/** Planın işlemlerinden ref -> başlangıç şifresi (yeni kişide `pc`, hesapsız mevcut kişide ilk `ra`); yalnız daire ilişkisi eklenen kişiler. */
export function collectAccountPasswords(ops) {
  const withApartment = new Set(ops.filter((op) => op.t === 'ra').map((op) => op.ref));
  const out = new Map();
  for (const op of ops) {
    if ((op.t === 'pc' || op.t === 'ra') && withApartment.has(op.ref) && !out.has(op.ref)) {
      const password = typeof op.password === 'string' && op.password.trim() !== '' ? op.password.trim() : DEFAULT_ACCOUNT_PASSWORD;
      out.set(op.ref, password);
    }
  }
  return out;
}

/**
 * Şifre özetlerini TRANSACTION DIŞINDA, sınırlı eşzamanlılıkla hesaplar (bcrypt kişi başına ~60 ms: 1500 kişi transaction kilitlerini dakikalarca
 * tutardı). Varsayılan başlangıç şifresi ("1234", belgelenmiş geçici PIN; ilk girişte değiştirilmesi zorunlu) için TEK özet paylaşılır; özel
 * şifrelerin her biri kendi tuzuyla özetlenir.
 * @param {Map<string, string>} passwords ref -> düz şifre
 * @returns {Promise<Map<string, { password: string, hash: string }>>} ref -> { password, hash }
 */
export async function hashAccountPasswords(passwords, { concurrency = HASH_CONCURRENCY } = {}) {
  // Varsayılan şifre dahil her hesap kendi tuzuyla özetlenir: tek ortak özet, hangi hesapların şifresini hâlâ
  // değiştirmediğini veritabanında görünür kılardı.
  const out = new Map();
  await mapLimit([...passwords], concurrency, async ([ref, password]) => {
    out.set(ref, { password, hash: await hashPassword(password) });
  });
  return out;
}

class AccountSkip extends Error {
  constructor(code) {
    super(code);
    this.skipCode = code;
  }
}

export const ACCOUNT_SKIP_MESSAGES = Object.freeze({
  EMAIL_IN_USE: 'Bu e-posta başka bir hesaba ait; hesap açılmadı. Kişi kaydı yapıldı, hesabı kişi kartından açabilirsiniz.',
  ACCOUNT_ALREADY_LINKED: 'Bu hesap sitede zaten başka bir kişiye bağlı; hesap açılmadı. Kişi kaydı yapıldı.',
  ACCOUNT_FAILED: 'Hesap açılamadı (beklenmeyen veri sorunu). Kişi kaydı yapıldı, hesabı kişi kartından açabilirsiniz.',
});

/** Kişi başına SAVEPOINT içinde YUTULMAYAN hata sınıfları: bağlantı (08), geri alma/kilitlenme (40), kaynak (53), kilit zaman aşımı (55), operatör (57), sözdizimi/yetki (42). */
const FATAL_ERROR_CLASS = /^(08|40|42|53|55|57)/;

const RELATION_RANK = Object.freeze({ owner: 0, tenant: 1, resident: 2, family_member: 3 });

/** Aynı dairede önce malik, sonra kiracı admin olur (grantApartmentAccess ilk gelene admin verir): adaylar en iyi ilişkiye göre sıralanır. */
function rankOf(candidate) {
  return Math.min(...candidate.apartments.map((entry) => RELATION_RANK[entry.relation] ?? 2));
}

const realEmailOf = (value) => {
  if (typeof value !== 'string') return null;
  const text = value.trim().toLowerCase();
  return text !== '' && !text.endsWith('@ahbu.local') ? text : null;
};

async function provisionOne(client, { siteCode, candidate, person, apartmentInfo, hashFor }) {
  const apartments = [...candidate.apartments].sort((a, b) => a.aptId - b.aptId);
  const first = apartmentInfo.get(apartments[0].aptId) ?? {};
  const blockName = first.block_name || 'Blok';
  const email = realEmailOf(person.email);

  // 1. e-posta bir kullanıcıya aitse: YALNIZ bu sitede zaten bağı olan (siteTiePredicate), aktif, yönetici olmayan hesaba bağlanır
  let userCode = null;
  let loginName = null;
  let createdAccount = false;
  if (email) {
    const found = await client.query(
      `
        SELECT u.user_code, u.login_name,
               (u.deleted_at IS NULL AND u.role NOT IN ('super_user', 'site_manager') AND ${siteTiePredicate('u.user_code', '$2::BIGINT')}) AS linkable
        FROM users u
        WHERE LOWER(u.email) = $1
        LIMIT 1
      `,
      [email, Number(siteCode)],
    );
    const row = found.rows[0];
    if (row) {
      if (row.linkable !== true) throw new AccountSkip('EMAIL_IN_USE');
      userCode = Number(row.user_code);
      loginName = row.login_name ?? null;
    }
  }

  // 2. yeni hesap: kullanıcı adı (yazılan ya da addan; sunucuda benzersizleştirilir) + başlangıç şifresi
  if (userCode === null) {
    const rawDesired = candidate.loginName || person.full_name || null;
    const desired = rawDesired ? slugifyLoginName(rawDesired) : null;
    loginName = desired
      ? await ensureUniqueLoginName({ db: client, desiredLoginName: desired, siteCode: Number(siteCode) })
      : await generateUniqueApartmentLoginName({ db: client, blockName, sortOrder: Number(first.sort_order || 1), siteCode: Number(siteCode) });
    const internalEmail = generateInternalApartmentEmail({ loginName, apartmentId: apartments[0].aptId, siteCode: Number(siteCode) });
    const password = typeof candidate.password === 'string' && candidate.password.trim() !== '' ? candidate.password.trim() : DEFAULT_ACCOUNT_PASSWORD;
    const passwordHash = await hashFor(candidate.ref, password);
    const inserted = await client.query(
      `
        INSERT INTO users (full_name, email, login_name, role, is_active, email_verified, approval_status, phone_number, password_hash, must_change_password)
        VALUES ($1, $2, $3, 'apartment_owner', TRUE, TRUE, 'approved', $4, $5, TRUE)
        RETURNING user_code
      `,
      [person.full_name || `${blockName} Daire ${first.unit_label ?? ''}`.trim(), email ?? internalEmail, loginName, person.phone ?? null, passwordHash],
    );
    userCode = Number(inserted.rows[0].user_code);
    createdAccount = true;
  }

  // 3. kişiyi hesaba bağla (CRM kuralı: hesaplı kişide ad / telefon / e-posta users'tan okunur; siteTiePredicate bağlama kuralıyla aynı)
  const linked = await client.query(
    `
      UPDATE site_people sp
      SET user_code = $1, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW()
      WHERE sp.id = $2 AND sp.site_code = $3 AND sp.user_code IS NULL
        AND NOT EXISTS (SELECT 1 FROM site_people x WHERE x.site_code = sp.site_code AND x.user_code = $1)
    `,
    [userCode, candidate.personId, Number(siteCode)],
  );
  if (Number(linked.rowCount) !== 1) throw new AccountSkip('ACCOUNT_ALREADY_LINKED');

  // 4. daire erişimi: MEVCUT kural (daire kilidi, dairede tek admin, site düzeyi RESIDENT, sakin göstergesi)
  for (const entry of apartments) {
    await grantApartmentAccess(client, { siteCode: Number(siteCode), apartmentId: entry.aptId, userCode });
  }
  if (createdAccount) {
    // parolası yönetimce verilen hesap daire göstergesindeyse işaretlenir (ilk girişte parola değişimi)
    await client.query(
      `UPDATE apartments SET resident_pin_issued = TRUE, is_active = TRUE WHERE id = ANY($1::BIGINT[]) AND site_code = $2::BIGINT AND resident_user_code = $3`,
      [apartments.map((entry) => entry.aptId), Number(siteCode), userCode],
    );
  }
  return { loginName, userCode, status: createdAccount ? 'created' : 'linked' };
}

/**
 * Bu çalıştırmada daire ilişkisi EKLENEN kişiler için kullanıcı hesabı, daire üyeliği ve başlangıç şifresi oluşturur / bağlar.
 * Kapsam `accountCandidates` ile sınırlıdır (sitedeki diğer hesapsız sakinlere DOKUNULMAZ); kişi başına tek hesap; her kişi kendi SAVEPOINT'inde
 * işlenir: veri hatasında yalnız o kişi geri alınır ve `skipped` içinde bildirilir (transaction bozulmaz). Kilitlenme / kilit zaman aşımı /
 * bağlantı hataları YUTULMAZ (yukarı fırlar; commit geri alınır).
 * @param {{ siteCode: number, runId?: number, accountCandidates: object[], hashes?: Map<string, {password: string, hash: string}> }} input
 * @returns {Promise<{ created: number, linked: number, skipped: number, items: object[], skipped_items: object[], audits: object[] }>}
 *   `items` / `skipped_items` istemciye döner (satır no + NİHAİ kullanıcı adı / atlama nedeni); `audits` yalnız sunucu içindir (kişi verisi yok).
 */
export async function provisionImportedResidents(client, { siteCode, runId = null, accountCandidates, hashes = new Map() }) {
  const result = { created: 0, linked: 0, skipped: 0, items: [], skipped_items: [], audits: [] };
  const candidates = (accountCandidates ?? []).filter((candidate) => Number.isInteger(candidate.personId) && candidate.apartments.length > 0);
  if (!client || typeof client.query !== 'function' || candidates.length === 0) return result;

  // Kişi satırları kilit altında yeniden doğrulanır: hâlâ hesapsız (user_code IS NULL) ve aktif olanlar; id sırasıyla kilitlenir (kilitlenme riski yok)
  const people = new Map();
  const ids = candidates.map((candidate) => candidate.personId).sort((a, b) => a - b);
  for (const part of chunksOf(ids, ENTITY_CHUNK)) {
    const found = await client.query(
      `
        SELECT sp.id, sp.full_name, sp.email, sp.phone
        FROM site_people sp
        WHERE sp.id = ANY($1::BIGINT[]) AND sp.site_code = $2::BIGINT AND sp.user_code IS NULL AND sp.is_active = TRUE
        ORDER BY sp.id
        FOR UPDATE OF sp
      `,
      [part, Number(siteCode)],
    );
    for (const row of found.rows) people.set(Number(row.id), row);
  }
  const aptIds = [...new Set(candidates.flatMap((candidate) => candidate.apartments.map((entry) => entry.aptId)))];
  const apartmentInfo = new Map();
  for (const part of chunksOf(aptIds, ENTITY_CHUNK)) {
    const found = await client.query(
      `
        SELECT a.id, a.unit_label, a.sort_order, b.block_name
        FROM apartments a
        LEFT JOIN site_blocks b ON b.id = a.block_id
        WHERE a.id = ANY($1::BIGINT[]) AND a.site_code = $2::BIGINT
      `,
      [part, Number(siteCode)],
    );
    for (const row of found.rows) apartmentInfo.set(Number(row.id), row);
  }

  // transaction öncesi hesaplanmış özet yoksa (ya da şifre değiştiyse) burada hesaplanır; varsayılan şifrenin özeti paylaşılır
  let defaultHash = null;
  const hashFor = async (ref, password) => {
    const known = hashes.get(ref);
    if (known && known.password === password) return known.hash;
    if (password === DEFAULT_ACCOUNT_PASSWORD) {
      defaultHash = defaultHash ?? (await hashPassword(DEFAULT_ACCOUNT_PASSWORD));
      return defaultHash;
    }
    return hashPassword(password);
  };

  const ordered = candidates.filter((candidate) => people.has(candidate.personId)).sort((a, b) => rankOf(a) - rankOf(b) || a.personId - b.personId);
  for (const candidate of ordered) {
    await client.query('SAVEPOINT import_account');
    try {
      const outcome = await provisionOne(client, { siteCode, candidate, person: people.get(candidate.personId), apartmentInfo, hashFor });
      await client.query('RELEASE SAVEPOINT import_account');
      result[outcome.status] += 1;
      result.items.push({ n: candidate.n, login_name: outcome.loginName, status: outcome.status });
      result.audits.push({
        action: 'person.account_created',
        target_type: 'person',
        target_id: String(candidate.personId),
        details: { user_code: outcome.userCode, status: outcome.status, via: 'import', run_id: runId },
      });
    } catch (error) {
      if (!(error instanceof AccountSkip) && FATAL_ERROR_CLASS.test(String(error?.code ?? ''))) throw error;
      await client.query('ROLLBACK TO SAVEPOINT import_account');
      await client.query('RELEASE SAVEPOINT import_account');
      const code = error instanceof AccountSkip ? error.skipCode : 'ACCOUNT_FAILED';
      if (!(error instanceof AccountSkip)) {
        console.error('[provisionImportedResidents] kişi atlandı:', { sqlstate: error?.code ?? null, name: error?.name ?? null });
      }
      result.skipped += 1;
      result.skipped_items.push({ n: candidate.n, code, message: ACCOUNT_SKIP_MESSAGES[code] });
    }
  }
  return result;
}
