// Yasal belge onayları: kayıt akışlarında `accepted_documents` doğrulaması / zorunluluk, user_consents yazımı, GET/POST /me/consents.
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.4).
//
// ZORUNLULUK: platform_settings `legal.enforce_consents` açıksa VE belge `complete` ise, bağlama (register | site_application) uygun
// `required_for` belgelerinin GÜNCEL sürümü gövdede yoksa -> 400 CONSENT_REQUIRED { missing: [...] }. Varsayılan KAPALI (eski istemciler çalışır).
// Zorunluluk kapalıyken: yalnız bilinen, tamamlanmış, onay istenen (required_for dolu) belgelerin GÜNCEL sürümü kaydedilir; eski / bilinmeyen
// girdiler sessizce atlanır (kayıt akışı bozulmaz; kullanıcı sonra `pending` olarak görür).
//
// BEKLEYEN KAYIT: /auth/register-individual hesabı e-posta kodu girilene dek AÇMAZ. Onaylar pending_registrations.accepted_documents'ta
// bekler ([{id, version, accepted_at}]) ve hesap GERÇEKTEN oluşurken AYNI işlemde user_consents'a yazılır (membership_service.js).

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { legalDir, loadLegalFiles, resolveDocuments } from './legal_documents.js';
import { parseFlag, readPlatformConfig } from './platform_config_service.js';

export const CONSENT_CONTEXTS = Object.freeze(['register', 'site_application']);
export const MAX_ACCEPTED_DOCUMENTS = 20;
export const CONSENT_LIST_LIMIT = 200;

const ID_RE = /^[a-z][a-z0-9_]{1,39}$/;
const VERSION_RE = /^[0-9A-Za-z._-]{1,40}$/;
const PENDING_MAX_AGE_MS = 3 * 24 * 60 * 60 * 1000;

const invalidAccepted = (message) => new PlatformError(400, 'INVALID_ACCEPTED_DOCUMENTS', message);

/**
 * İstek gövdesindeki `accepted_documents` değerini doğrular: yok/null -> []; dizi değilse, 20'den uzunsa ya da öğe {id, version} dizgesi
 * değilse 400 INVALID_ACCEPTED_DOCUMENTS. Aynı belge birden çok kez gelirse ilki geçerlidir.
 * @returns {Array<{id: string, version: string}>}
 */
export function normalizeAcceptedDocuments(raw) {
  if (raw === undefined || raw === null) {
    return [];
  }
  if (!Array.isArray(raw)) {
    throw invalidAccepted('accepted_documents bir dizi olmalıdır.');
  }
  if (raw.length > MAX_ACCEPTED_DOCUMENTS) {
    throw invalidAccepted(`En fazla ${MAX_ACCEPTED_DOCUMENTS} belge onaylanabilir.`);
  }
  const entries = [];
  const seen = new Set();
  for (const item of raw) {
    const id = typeof item?.id === 'string' ? item.id.trim() : '';
    const version = typeof item?.version === 'string' ? item.version.trim() : '';
    if (!ID_RE.test(id) || !VERSION_RE.test(version)) {
      throw invalidAccepted('Her onay {id, version} biçiminde olmalıdır.');
    }
    if (!seen.has(id)) {
      seen.add(id);
      entries.push({ id, version });
    }
  }
  return entries;
}

/**
 * Çözümlenmiş belgeler (yer tutucu dolu, complete hesaplı) + yasal ayarlar. Ayar okunamazsa hata YUKARI gider (zorunluluk akışında sessiz
 * "kapalı" kabul edilmez).
 */
export async function loadLegalState({ db = pool, dir = legalDir() } = {}) {
  const config = await readPlatformConfig(db);
  const rawDocs = await loadLegalFiles(dir);
  return { docs: resolveDocuments(rawDocs, config.legal), legal: config.legal };
}

/** Zorunluluk açık mı? (legal.enforce_consents) */
export const isEnforced = (legal) => parseFlag(legal?.enforce_consents);

/** Bu bağlamda onay İSTENEN (tamamlanmış, required_for içinde bağlam olan) belgeler. */
export const requiredDocuments = (docs, context) => docs.filter((doc) => doc.complete && doc.required_for.includes(context));

/**
 * Kayıt / başvuru akışı için `accepted_documents` çözümü. Zorunluluk açıkken eksik/eski belge varsa 400 CONSENT_REQUIRED.
 * @returns {Promise<{ records: Array<{id: string, version: string}>, enforced: boolean }>} records: yazılacak (güncel sürüm, bilinen) onaylar
 */
export async function resolveAcceptedDocuments({ raw, context, state = null, db = pool, dir = legalDir() }) {
  const entries = normalizeAcceptedDocuments(raw);
  const { docs, legal } = state ?? (await loadLegalState({ db, dir }));
  const enforced = isEnforced(legal);
  const acceptedVersion = new Map(entries.map((entry) => [entry.id, entry.version]));
  if (enforced) {
    const missing = requiredDocuments(docs, context)
      .filter((doc) => acceptedVersion.get(doc.id) !== doc.version)
      .map((doc) => doc.id);
    if (missing.length > 0) {
      throw new PlatformError(400, 'CONSENT_REQUIRED', 'Devam etmek için yasal belgeleri onaylamanız gerekir.', { missing });
    }
  }
  const byId = new Map(docs.map((doc) => [doc.id, doc]));
  const records = entries.filter((entry) => {
    const doc = byId.get(entry.id);
    return doc && doc.complete && doc.required_for.length > 0 && doc.version === entry.version;
  });
  return { records, enforced };
}

/** Bekleyen kayıtta saklanan JSON değeri. */
export function pendingConsentsJson(records, now = new Date()) {
  if (!records || records.length === 0) {
    return null;
  }
  const acceptedAt = now.toISOString();
  return JSON.stringify(records.map((record) => ({ id: record.id, version: record.version, accepted_at: acceptedAt })));
}

/**
 * pending_registrations.accepted_documents (JSONB) -> güvenli kayıt listesi. Bozuk / süresi geçmiş / geleceğe ait zamanlar temizlenir
 * (hesap açılışı asla bozuk veri yüzünden başarısız olmaz).
 * @returns {Array<{id: string, version: string, accepted_at: string}>}
 */
export function sanitizeStoredConsents(stored, now = new Date()) {
  let value = stored;
  if (typeof value === 'string') {
    try {
      value = JSON.parse(value);
    } catch (_error) {
      return [];
    }
  }
  if (!Array.isArray(value)) {
    return [];
  }
  const records = [];
  const seen = new Set();
  for (const item of value.slice(0, MAX_ACCEPTED_DOCUMENTS)) {
    const id = typeof item?.id === 'string' ? item.id : '';
    const version = typeof item?.version === 'string' ? item.version : '';
    if (!ID_RE.test(id) || !VERSION_RE.test(version) || seen.has(id)) {
      continue;
    }
    seen.add(id);
    let at = new Date(item?.accepted_at);
    if (Number.isNaN(at.getTime()) || at.getTime() > now.getTime() || now.getTime() - at.getTime() > PENDING_MAX_AGE_MS) {
      at = now;
    }
    records.push({ id, version, accepted_at: at.toISOString() });
  }
  return records;
}

/**
 * Onayları user_consents'a yazar (aynı belge + sürüm zaten varsa sessizce atlanır). `db`: pool ya da transaction client'ı. Hesap oluşturan
 * işlemin İÇİNDE çağrılırsa onay yazımı hesapla birlikte işlenir / geri alınır.
 * @param {Array<{id: string, version: string, accepted_at?: string}>} records
 * @returns {Promise<number>} yeni yazılan satır sayısı
 */
export async function recordConsents(db, userCode, records, source) {
  if (!records || records.length === 0) {
    return 0;
  }
  const now = new Date().toISOString();
  const result = await db.query(
    `
      INSERT INTO user_consents (user_code, document_id, version, accepted_at, source)
      SELECT $1::int, d.document_id, d.version, d.accepted_at, $5::text
      FROM unnest($2::text[], $3::text[], $4::timestamptz[]) AS d(document_id, version, accepted_at)
      ON CONFLICT (user_code, document_id, version) DO NOTHING
    `,
    [userCode, records.map((r) => r.id), records.map((r) => r.version), records.map((r) => r.accepted_at ?? now), source],
  );
  return result.rowCount ?? 0;
}

/** Kullanıcının onayları (yeniden eskiye, en çok 200). */
export async function listUserConsents(userCode, db = pool) {
  const result = await db.query(
    `
      SELECT document_id, version, accepted_at
      FROM user_consents
      WHERE user_code = $1
      ORDER BY accepted_at DESC, id DESC
      LIMIT ${CONSENT_LIST_LIMIT}
    `,
    [userCode],
  );
  return (result.rows ?? []).map((row) => ({
    document_id: row.document_id,
    version: row.version,
    accepted_at: row.accepted_at instanceof Date ? row.accepted_at.toISOString() : new Date(row.accepted_at).toISOString(),
  }));
}

/**
 * Bekleyen (onaylanması gereken) belgeler: tamamlanmış ve onay istenen belgelerden GÜNCEL sürümü onaylanmamış olanlar. Kayıt (`register`)
 * belgeleri her hesap için; yalnız site başvurusu (`site_application`) belgeleri ise kullanıcı o belgeyi daha önce onaylamışsa (sürüm
 * yenilenmiş demektir) bekleyen sayılır: site kurmayan sıradan bir sakine ek sözleşme dayatılmaz.
 */
export function computePending(docs, consents) {
  const accepted = new Set(consents.map((c) => `${c.document_id}\u0000${c.version}`));
  const everAccepted = new Set(consents.map((c) => c.document_id));
  return docs
    .filter((doc) => doc.complete && doc.required_for.length > 0)
    .filter((doc) => !accepted.has(`${doc.id}\u0000${doc.version}`))
    .filter((doc) => doc.required_for.includes('register') || everAccepted.has(doc.id))
    .map((doc) => ({ id: doc.id, title: doc.title, version: doc.version }));
}

/** GET /me/consents (ve POST yanıtı): { consents, pending }. */
export async function getConsentState(userCode, { db = pool, state = null } = {}) {
  const legalState = state ?? (await loadLegalState({ db }));
  const consents = await listUserConsents(userCode, db);
  return { consents, pending: computePending(legalState.docs, consents) };
}

/**
 * POST /me/consents: { documents: [{id, version}] }. Hepsi ya da hiçbiri: bilinmeyen / onay istenmeyen belge 400, tamamlanmamış belge
 * 409 DOCUMENT_INCOMPLETE, güncel olmayan sürüm 409 CONSENT_VERSION_STALE. Başarıda güncel { consents, pending }.
 */
export async function acceptDocuments({ userCode, documents, db = pool }) {
  if (!Array.isArray(documents) || documents.length === 0) {
    throw new PlatformError(400, 'INVALID_BODY', 'documents boş olmayan bir dizi olmalıdır.');
  }
  const entries = normalizeAcceptedDocuments(documents);
  const state = await loadLegalState({ db });
  const byId = new Map(state.docs.map((doc) => [doc.id, doc]));
  const stale = [];
  for (const entry of entries) {
    const doc = byId.get(entry.id);
    if (!doc || doc.required_for.length === 0) {
      throw new PlatformError(400, 'DOCUMENT_NOT_ACCEPTABLE', 'Bu belge için onay istenmez ya da belge bulunamadı.', { document_id: entry.id });
    }
    if (!doc.complete) {
      throw new PlatformError(409, 'DOCUMENT_INCOMPLETE', 'Bu belge henüz yayına hazır değil.', { document_id: entry.id });
    }
    if (doc.version !== entry.version) {
      stale.push({ id: doc.id, current_version: doc.version });
    }
  }
  if (stale.length > 0) {
    throw new PlatformError(409, 'CONSENT_VERSION_STALE', 'Belge güncellendi; güncel sürümü okuyup yeniden onaylayın.', { stale });
  }
  await recordConsents(db, userCode, entries, 'in_app');
  return getConsentState(userCode, { db, state });
}

/**
 * Site başvurusu kancası (site_application_service.createSiteApplication): onay denetimi başvuru işleminin İÇİNDE (aynı client) yapılır,
 * yazım da aynı işlemde. Servis bu modülü bilmez; rota kancayı parametre olarak verir.
 */
export const siteApplicationConsents = {
  check: (db, raw) => resolveAcceptedDocuments({ raw, context: 'site_application', db }),
  record: (db, userCode, plan) => recordConsents(db, userCode, plan.records, 'site_application'),
};
