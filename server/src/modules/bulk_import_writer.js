// Toplu yükleme (Faz 2b): planı veritabanına YAZAR. Çağıran, commit transaction'ını (kilitler dahil) yönetir; burada yalnız küme tabanlı ifadeler çalışır.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Commit akışı" adım 5): kişi kimlikleri `nextval` ile önceden ayrılır (RETURNING sırasına güvenilmez) -> kişi
// INSERT/UPDATE -> ilişki INSERT (origin='manual') / UPDATE -> araç INSERT -> toplu audit INSERT (SAVEPOINT'siz). Tüm değerler PARAMETRELİ JSON dizileriyle
// (jsonb_to_recordset) gider; SQL'e metin birleştirilmez. Sabit sayıda sorgu: parça boyutu 5000 (audit 10000) olduğundan 5000 satırlık dosya <= birkaç ifade.
// Beklenmeyen 23505 / 23503 (yarış) ya da beklenen satır sayısının tutmaması -> 409 PREVIEW_STALE (çağıran ROLLBACK yapar).

import { PlatformError } from './errors.js';

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
  ['gross_area_m2', 'gross', 'numeric'],
  ['net_area_m2', 'net', 'numeric'],
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
 * @returns {Promise<object[]>} audit satırları (henüz yazılmadı)
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
        newPeople.set(op.ref, { ref: op.ref, name: op.name, phone: op.phone, email: op.email, note: op.note });
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
        residencyAdds.push({ ref: op.ref, aptId: op.aptId, relation: op.relation, moveIn: op.moveIn ?? today });
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
  return audits;
}
