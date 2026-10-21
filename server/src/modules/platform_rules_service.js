// Kurallar tablosu servisi (karar G11; sözleşme docs/PLATFORM_KURALLAR.md): liste görünümü ve kısmi yazma.
//
//  - listRules(db, { siteCode, onDate, includeNames, canEdit })  -> { on_date, site, can_edit, groups, items }
//      Her kural: meta (ad, açıklama, tür, birim, sınır, varsayılan, sitede değişebilir mi, planlanabilir mi, kilit, çift, mevzuat notu) +
//      platform değeri + (site görünümünde, sitede değişebilen kuralda) site değeri + etkin değer + ileri tarihli (planlı) satırlar.
//      `includeNames: false` (site yöneticisi): değiştiren kişinin adı DÖNMEZ.
//  - updateRules({ body, actor, now }, db)  (yalnız süper kullanıcı; rota denetler)
//      Tek işlem: kurallar advisory kilidi -> işlemi yapan KEY SHARE -> (site kapsamı) site KEY SHARE -> satırlar -> INSERT -> audit -> COMMIT -> önbellek boşalır.
//      Kapsamın o tarihteki değeriyle AYNI değişiklik no-op'tur (satır ve audit yazılmaz). Isı payı çifti toplamı (100) etkili tarihte ve sonraki planlı
//      tarihlerde denetlenir. Audit KATIDIR: denetim satırı yazılamazsa değişiklik geri alınır. Audit ayrıntısı yalnız kapsam / tarih / eski ve yeni değer
//      (not metni yazılmaz).

import { pool } from '../db.js';
import { accountDeleted } from './account_common.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { normalizeFreeText } from './finance_common.js';
import { parsePositiveId, todayIso } from './people_common.js';
import { RULES, RULE_GROUPS, RULE_KEYS, invalidateRuleCache, resolveRuleFromRows, ruleOf, validateRuleChange } from './platform_rules.js';

/** Eşzamanlı yazmalar sıraya girsin (çift toplamı ve no-op denetimi yarışmasın). İki-int anahtar: sınıf "PRUL". */
export const RULES_LOCK_CLASS = 0x5052554c;
export const RULES_LOCK_JOB = 1;
export const MAX_CHANGES = 20;
export const NOTE_MAX = 200;
export const SCHEDULE_YEARS = 5;

const ROOT_KEYS = new Set(['site_code', 'valid_from', 'note', 'changes']);
const CHANGE_KEYS = new Set(['key', 'value', 'inherit']);

const LIST_ROWS_SQL = `
  SELECT
    v.id, v.rule_key, v.site_code, v.value, v.inherit, to_char(v.valid_from, 'YYYY-MM-DD') AS valid_from, v.note, v.created_at,
    u.full_name AS created_by_name
  FROM platform_rule_values v
  LEFT JOIN users u ON u.user_code = v.created_by
  WHERE v.rule_key = ANY($1::TEXT[]) AND (v.site_code IS NULL OR v.site_code = $2)
  ORDER BY v.rule_key, v.valid_from, v.id
`;

const INSERT_SQL = `
  INSERT INTO platform_rule_values (rule_key, site_code, value, inherit, valid_from, note, created_by)
  VALUES ($1, $2, $3::JSONB, $4, $5::DATE, $6, $7)
  RETURNING id
`;

const invalidBody = (message) => new PlatformError(400, 'INVALID_BODY', message);
const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
const validationFailed = (fields, codes) =>
  new PlatformError(400, 'VALIDATION_FAILED', 'Bazı kurallar geçersiz.', { fields: { ...fields }, rule_codes: { ...codes } });

/** 'YYYY-MM-DD' -> 'GG.AA.YYYY' (hata metinleri). */
const trDate = (iso) => `${iso.slice(8, 10)}.${iso.slice(5, 7)}.${iso.slice(0, 4)}`;

function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

const isPlatformRow = (row) => row.site_code === null || row.site_code === undefined;

/** Kapsam satırları arasından `onDate` itibarıyla geçerli (en yeni) satır ya da null. */
function scopeRowAt(rows, onDate, inScope) {
  let best = null;
  for (const row of rows) {
    if (!inScope(row) || row.valid_from > onDate) continue;
    if (best === null || row.valid_from > best.valid_from || (row.valid_from === best.valid_from && Number(row.id) > Number(best.id))) {
      best = row;
    }
  }
  return best;
}

// --- Görünüm -------------------------------------------------------------------------------------------------------------------------------

/**
 * Tek kuralın görünümü. `rows`: bu kuralın platform satırları + (verildiyse) tek sitenin satırları (LIST_ROWS_SQL biçimi).
 * @param {{ siteCode: number|null, onDate: string, includeNames: boolean }} options
 */
export function buildRuleItem(rule, rows, { siteCode = null, onDate, includeNames }) {
  const list = Array.isArray(rows) ? rows : [];
  const siteScoped = rule.siteOverridable && siteCode !== null && siteCode !== undefined;
  const inSite = (row) => !isPlatformRow(row) && Number(row.site_code) === Number(siteCode);
  const byId = new Map(list.map((row) => [Number(row.id), row]));
  const nameOf = (row) => (includeNames ? (row?.created_by_name ?? null) : null);

  const platform = resolveRuleFromRows(rule, list, { siteCode: null, onDate });
  const platformRow = platform.rowId === null ? null : byId.get(platform.rowId);
  const effective = resolveRuleFromRows(rule, list, { siteCode: siteScoped ? Number(siteCode) : null, onDate });

  let site = null;
  if (siteScoped) {
    const current = scopeRowAt(list, onDate, inSite);
    if (current && current.inherit !== true) {
      site = {
        value: effective.source === 'site' ? effective.value : null,
        valid_from: current.valid_from,
        note: current.note ?? null,
        updated_at: toIso(current.created_at),
        updated_by_name: nameOf(current),
      };
    }
  }

  const scheduled = list
    .filter((row) => row.valid_from > onDate && (isPlatformRow(row) || (siteScoped && inSite(row))))
    .sort((a, b) => (a.valid_from === b.valid_from ? Number(a.id) - Number(b.id) : a.valid_from < b.valid_from ? -1 : 1))
    .map((row) => ({
      scope: isPlatformRow(row) ? 'platform' : 'site',
      value: row.inherit === true ? null : row.value,
      inherit: row.inherit === true,
      valid_from: row.valid_from,
      note: row.note ?? null,
    }));

  return {
    key: rule.key,
    group: rule.group,
    label: rule.label,
    description: rule.description,
    type: rule.type,
    unit: rule.unit,
    nullable: rule.nullable,
    min: rule.min,
    max: rule.max,
    default: rule.defaultValue,
    site_overridable: rule.siteOverridable,
    schedulable: rule.schedulable,
    editable: rule.editable,
    locked_reason: rule.lockedReason,
    pair: rule.pair ? { key: rule.pair.key, sum: rule.pair.sum } : null,
    legal_note: rule.legalNote,
    platform: {
      value: platform.value,
      source: platform.source,
      valid_from: platform.validFrom,
      note: platformRow?.note ?? null,
      updated_at: toIso(platformRow?.created_at),
      updated_by_name: nameOf(platformRow),
    },
    site,
    effective: { value: effective.value, source: effective.source, valid_from: effective.validFrom },
    scheduled,
  };
}

async function loadRows(db, keys, siteCode) {
  const result = await db.query(LIST_ROWS_SQL, [keys, siteCode]);
  const byKey = new Map();
  for (const row of result.rows ?? []) {
    if (!byKey.has(row.rule_key)) byKey.set(row.rule_key, []);
    byKey.get(row.rule_key).push(row);
  }
  return byKey;
}

/** GET gövdesi (platform ya da site görünümü). Site yoksa 404 SITE_NOT_FOUND. */
export async function listRules(db, { siteCode = null, onDate = todayIso(), includeNames = false, canEdit = false } = {}) {
  let site = null;
  if (siteCode !== null && siteCode !== undefined) {
    const found = await db.query(`SELECT site_code, name FROM sites WHERE site_code = $1`, [siteCode]);
    const row = found.rows?.[0];
    if (!row) {
      throw siteNotFound();
    }
    site = { site_code: Number(row.site_code), site_name: row.name ?? null };
  }
  const byKey = await loadRows(db, [...RULE_KEYS], site ? site.site_code : null);
  return {
    on_date: onDate,
    site,
    can_edit: canEdit === true,
    groups: RULE_GROUPS,
    items: RULE_KEYS.map((key) => buildRuleItem(RULES[key], byKey.get(key) ?? [], { siteCode: site ? site.site_code : null, onDate, includeNames })),
  };
}

// --- Yazma gövdesi --------------------------------------------------------------------------------------------------------------------------

/** Gerçek takvim günü mü ('YYYY-MM-DD')? */
function isRealDate(text) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const probe = new Date(Date.UTC(year, month - 1, day));
  return probe.getUTCFullYear() === year && probe.getUTCMonth() === month - 1 && probe.getUTCDate() === day;
}

/**
 * PUT gövdesi -> { siteCode, validFrom, note, changes: [{ key, rule, value, inherit }] }.
 * Yapı hatası 400 INVALID_BODY; kural hataları TEK yanıtta 400 VALIDATION_FAILED (`fields`: anahtar -> Türkçe metin, `rule_codes`: anahtar -> kod).
 */
export function parseRulesPatch(body, { today }) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw invalidBody('Gövde bir nesne olmalıdır.');
  }
  for (const key of Object.keys(body)) {
    if (!ROOT_KEYS.has(key)) throw invalidBody('Bilinmeyen alan gönderildi.');
  }
  let siteCode = null;
  if (body.site_code !== undefined && body.site_code !== null) {
    siteCode = parsePositiveId(typeof body.site_code === 'number' ? body.site_code : String(body.site_code));
    if (siteCode === null) throw invalidBody('Site kodu geçersiz.');
  }
  let validFrom = today;
  if (body.valid_from !== undefined && body.valid_from !== null) {
    if (typeof body.valid_from !== 'string' || !isRealDate(body.valid_from)) {
      throw invalidBody('Geçerlilik tarihi YYYY-AA-GG biçiminde gerçek bir tarih olmalıdır.');
    }
    validFrom = body.valid_from;
  }
  const latest = `${Number(today.slice(0, 4)) + SCHEDULE_YEARS}${today.slice(4)}`;
  if (validFrom < today) throw invalidBody('Geçerlilik tarihi bugünden önce olamaz; geçmiş günlerin kuralı değiştirilmez.');
  if (validFrom > latest) throw invalidBody(`Geçerlilik tarihi en fazla ${SCHEDULE_YEARS} yıl ileride olabilir.`);
  // Projedeki serbest metin kuralı (finance_common.normalizeFreeText): NFC, kontrol / satır ayırıcı boşluğa, görünmez ve yön denetim karakterleri
  // (U+202A-202E, U+2066-2069, U+200B, U+FEFF ...) atılır, boşluk tekleşir; uzunluk kod noktasıyla (DB char_length ile aynı); boş -> null.
  const note = normalizeFreeText(body.note, { label: 'Not', max: NOTE_MAX });
  if (!Array.isArray(body.changes) || body.changes.length === 0) {
    throw invalidBody('En az bir kural değişikliği gönderin.');
  }
  if (body.changes.length > MAX_CHANGES) {
    throw invalidBody(`Bir seferde en çok ${MAX_CHANGES} kural değiştirilebilir.`);
  }
  const fields = Object.create(null);
  const codes = Object.create(null);
  const fail = (key, code, message) => {
    fields[key] = message;
    codes[key] = code;
  };
  const seen = new Set();
  const changes = [];
  for (const change of body.changes) {
    if (!change || typeof change !== 'object' || Array.isArray(change) || typeof change.key !== 'string' || Object.keys(change).some((k) => !CHANGE_KEYS.has(k))) {
      throw invalidBody('Kural değişikliği geçersiz: her değişiklik { key, value } ya da { key, inherit: true } olmalıdır.');
    }
    const key = change.key.slice(0, 80);
    if (seen.has(key)) {
      fail(key, 'RULE_DUPLICATE', 'Aynı kural bir istekte iki kez değiştirilemez.');
      continue;
    }
    seen.add(key);
    const rule = ruleOf(key);
    if (!rule) {
      fail(key, 'RULE_UNKNOWN', 'Bilinmeyen kural.');
      continue;
    }
    const result = validateRuleChange(rule, change, { siteScoped: siteCode !== null, future: validFrom > today });
    if (!result.ok) {
      fail(key, result.code, result.message);
      continue;
    }
    changes.push({ key, rule, value: result.value, inherit: result.inherit });
  }
  if (Object.keys(fields).length > 0) {
    throw validationFailed(fields, codes);
  }
  return { siteCode, validFrom, note, changes };
}

// --- Yazma ----------------------------------------------------------------------------------------------------------------------------------

/** İki değer (sayı / boolean / null) aynı mı? */
const sameValue = (a, b) => (a === null || a === undefined ? b === null || b === undefined : a === b);

/** Isı payı gibi çift kurallar: etkili tarihte ve sonraki her planlı tarihte (platform kapsamı) toplam `sum` olmalı. */
function pairErrors(changes, rowsByKey, validFrom) {
  const fields = Object.create(null);
  const codes = Object.create(null);
  const checked = new Set();
  for (const change of changes) {
    const { pair } = change.rule;
    if (!pair || checked.has(change.key)) continue;
    checked.add(change.key);
    checked.add(pair.key);
    const partner = RULES[pair.key];
    const own = rowsByKey.get(change.key) ?? [];
    const other = rowsByKey.get(pair.key) ?? [];
    const dates = [...new Set([validFrom, ...[...own, ...other].filter((row) => isPlatformRow(row) && row.valid_from > validFrom).map((row) => row.valid_from)])].sort();
    for (const date of dates) {
      const a = resolveRuleFromRows(change.rule, own, { onDate: date }).value;
      const b = resolveRuleFromRows(partner, other, { onDate: date }).value;
      if (a + b !== pair.sum) {
        fields[change.key] = `${change.rule.label} ile ${partner.label.toLowerCase()} toplamı ${pair.sum} olmalıdır (${trDate(date)} itibarıyla ${a} + ${b}). İkisini birlikte değiştirin.`;
        codes[change.key] = 'RULE_PAIR_MISMATCH';
        break;
      }
    }
  }
  return Object.keys(fields).length > 0 ? validationFailed(fields, codes) : null;
}

/**
 * PUT /admin/rules: kısmi yazma (yalnız süper kullanıcı). Dönüş: güncel görünüm (aynı kapsam) + `changed` (yazılan anahtarlar, istek sırasıyla).
 */
export async function updateRules({ body, actor, now = new Date() }, db = pool) {
  const today = todayIso(now);
  const input = parseRulesPatch(body, { today });
  const actorInfo = actorFromAuthUser(actor);
  const client = await db.connect();
  const changed = [];
  let committed = false;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1::int, $2::int)', [RULES_LOCK_CLASS, RULES_LOCK_JOB]);
    if (actorInfo.userCode !== null) {
      const found = await client.query('SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE', [actorInfo.userCode]);
      if (!found.rows?.[0]) throw accountDeleted();
    }
    if (input.siteCode !== null) {
      const site = await client.query(`SELECT site_code, name FROM sites WHERE site_code = $1 FOR KEY SHARE`, [input.siteCode]);
      if (!site.rows?.[0]) throw siteNotFound();
    }
    const keys = [...new Set(input.changes.flatMap((change) => (change.rule.pair ? [change.key, change.rule.pair.key] : [change.key])))];
    const rowsByKey = await loadRows(client, keys, input.siteCode);
    const scope = input.siteCode === null ? 'platform' : 'site';
    const inScope = (row) => (input.siteCode === null ? isPlatformRow(row) : !isPlatformRow(row) && Number(row.site_code) === input.siteCode);
    const writes = [];
    for (const change of input.changes) {
      const rows = rowsByKey.get(change.key) ?? [];
      const current = scopeRowAt(rows, input.validFrom, inScope);
      const currentInherit = current === null || current.inherit === true;
      if (currentInherit ? change.inherit : !change.inherit && sameValue(current.value, change.value)) {
        continue;
      }
      const inserted = await client.query(INSERT_SQL, [
        change.key,
        input.siteCode,
        change.inherit || change.value === null ? null : JSON.stringify(change.value),
        change.inherit,
        input.validFrom,
        input.note,
        actorInfo.userCode,
      ]);
      const id = String(inserted.rows[0].id);
      rows.push({ id, rule_key: change.key, site_code: input.siteCode === null ? null : String(input.siteCode), value: change.inherit ? null : change.value, inherit: change.inherit, valid_from: input.validFrom, note: input.note });
      rowsByKey.set(change.key, rows);
      writes.push({ change, from: currentInherit ? null : current.value });
    }
    if (input.siteCode === null) {
      const pairError = pairErrors(input.changes, rowsByKey, input.validFrom);
      if (pairError) throw pairError;
    }
    for (const { change, from } of writes) {
      const audited = await recordAudit(
        client,
        {
          actor: actorInfo,
          action: 'platform_rule.updated',
          siteCode: input.siteCode,
          targetType: 'platform_rule',
          targetId: change.key,
          details: { scope, valid_from: input.validFrom, from, to: change.inherit ? null : change.value, inherit: change.inherit },
        },
        { inTransaction: true },
      );
      if (!audited) {
        throw new Error('platform_rules: denetim kaydı yazılamadı');
      }
      changed.push(change.key);
    }
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) {
      await client.query('ROLLBACK').catch(() => {});
    }
    throw error;
  } finally {
    client.release();
  }
  if (changed.length > 0) {
    invalidateRuleCache();
  }
  const view = await listRules(db, { siteCode: input.siteCode, onDate: today, includeNames: true, canEdit: true });
  return { ...view, changed };
}
