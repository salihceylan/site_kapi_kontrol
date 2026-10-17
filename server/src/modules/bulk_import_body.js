// Toplu yükleme (Faz 2b) istek gövdesi doğrulaması ve parmak izi. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Uçlar"). Sunucu istemciden gelen HER hücreyi güvenilmez sayar: anahtarlar spec beyaz listesinden olmalı
// (nesneler `Object.create(null)` ile kurulur, `__proto__`/`constructor` anahtarı reddedilir), değerler yalnız metin | sonlu sayı | null olabilir.

import { createHash } from 'node:crypto';
import { PlatformError } from './errors.js';
import { CELL_HARD_LIMIT, SPEC_VERSION, columnKeysOf, maxRows } from './bulk_import_spec.js';

const MAX_ABS_NUMBER = 1e15;
const MAX_LINE_NUMBER = 10_000_000;
export const IDEMPOTENCY_KEY_PATTERN = /^[a-z0-9-]{8,64}$/;
const HASH_PATTERN = /^[0-9a-f]{64}$/;

const invalid = (message) => new PlatformError(400, 'INVALID_BODY', message);

const isPlainObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

/** Anahtarları sıralı, kararlı JSON (parmak izi için). */
export function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalJson(entry)).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value === undefined ? null : value);
}

export const sha256 = (text) => createHash('sha256').update(text).digest('hex');

/**
 * Gövdeyi doğrular (preview ve commit ortak). Hata: PlatformError (400 INVALID_BODY / IMPORT_EMPTY / IMPORT_TOO_MANY_ROWS / ACK_REQUIRED, 409 IMPORT_SPEC_MISMATCH).
 * @returns {{ rows: { n: number, cells: object }[], allowOverwrite: boolean, strict: boolean, expectedHash: string|null,
 *             idempotencyKey: string|null, acknowledged: boolean }}
 */
export function validateImportBody(body, kind, { commit = false, env = process.env } = {}) {
  if (!isPlainObject(body)) {
    throw invalid('İstek gövdesi bir nesne olmalıdır.');
  }
  if (body.spec_version === undefined || body.spec_version === null) {
    throw invalid('spec_version zorunludur.');
  }
  if (body.spec_version !== SPEC_VERSION) {
    throw new PlatformError(409, 'IMPORT_SPEC_MISMATCH', 'Şablon sürümü uyuşmuyor. Uygulamayı güncelleyin.');
  }
  const rawRows = body.rows;
  if (!Array.isArray(rawRows)) {
    throw invalid('rows bir dizi olmalıdır.');
  }
  if (rawRows.length === 0) {
    throw new PlatformError(400, 'IMPORT_EMPTY', 'Yüklenecek satır yok.');
  }
  const limit = maxRows(env);
  if (rawRows.length > limit) {
    throw new PlatformError(400, 'IMPORT_TOO_MANY_ROWS', `Bir seferde en çok ${limit} satır yüklenebilir.`);
  }
  const allowed = columnKeysOf(kind);
  const rows = [];
  let previousN = 0;
  for (let index = 0; index < rawRows.length; index += 1) {
    const raw = rawRows[index];
    if (!isPlainObject(raw)) {
      throw invalid(`rows[${index}] bir nesne olmalıdır.`);
    }
    const { n, cells: rawCells } = raw;
    if (!Number.isSafeInteger(n) || n < 1 || n > MAX_LINE_NUMBER) {
      throw invalid(`rows[${index}].n geçersiz (satır numarası, 1 veya büyük tam sayı).`);
    }
    if (n <= previousN) {
      throw invalid(`rows[${index}].n artan ve tekil olmalıdır.`);
    }
    previousN = n;
    if (!isPlainObject(rawCells)) {
      throw invalid(`rows[${index}].cells bir nesne olmalıdır.`);
    }
    const cells = Object.create(null);
    for (const key of Object.keys(rawCells)) {
      if (!allowed.has(key)) {
        throw invalid(`rows[${index}].cells içinde bu tür için tanımsız bir sütun anahtarı var.`);
      }
      const value = rawCells[key];
      if (value === null) {
        cells[key] = null;
      } else if (typeof value === 'string') {
        if (Array.from(value).length > CELL_HARD_LIMIT) {
          throw invalid(`rows[${index}].cells.${key} çok uzun.`);
        }
        cells[key] = value;
      } else if (typeof value === 'number') {
        if (!Number.isFinite(value) || Math.abs(value) >= MAX_ABS_NUMBER) {
          throw invalid(`rows[${index}].cells.${key} geçerli bir sayı değil.`);
        }
        cells[key] = value;
      } else {
        throw invalid(`rows[${index}].cells.${key} metin, sayı ya da null olmalıdır.`);
      }
    }
    rows.push({ n, cells });
  }

  let allowOverwrite = false;
  if (body.allow_overwrite !== undefined && body.allow_overwrite !== null) {
    if (typeof body.allow_overwrite !== 'boolean') {
      throw invalid('allow_overwrite true veya false olmalıdır.');
    }
    allowOverwrite = body.allow_overwrite;
    if (allowOverwrite && kind !== 'apartments') {
      throw invalid('allow_overwrite yalnız daire yüklemesinde geçerlidir.');
    }
  }

  const result = { rows, allowOverwrite, strict: false, expectedHash: null, idempotencyKey: null, acknowledged: false };
  if (!commit) {
    return result;
  }
  if (typeof body.expected_hash !== 'string' || !HASH_PATTERN.test(body.expected_hash)) {
    throw invalid('expected_hash zorunludur (önizlemenin preview_hash değeri).');
  }
  if (typeof body.idempotency_key !== 'string' || !IDEMPOTENCY_KEY_PATTERN.test(body.idempotency_key)) {
    throw invalid('idempotency_key zorunludur (8-64 karakter; küçük harf, rakam, tire).');
  }
  if (body.strict !== undefined && body.strict !== null && typeof body.strict !== 'boolean') {
    throw invalid('strict true veya false olmalıdır.');
  }
  if (body.acknowledged !== undefined && body.acknowledged !== null && typeof body.acknowledged !== 'boolean') {
    throw invalid('acknowledged true veya false olmalıdır.');
  }
  result.expectedHash = body.expected_hash;
  result.idempotencyKey = body.idempotency_key;
  result.strict = body.strict === true;
  result.acknowledged = body.acknowledged === true;
  if ((kind === 'people' || kind === 'vehicles') && !result.acknowledged) {
    throw new PlatformError(
      400,
      'ACK_REQUIRED',
      'Kişi verilerini işlemek için gerekli yasal dayanağa sahip olduğunuzu onaylayın.',
    );
  }
  return result;
}

/**
 * İstek parmak izi = sha256(kind, spec_version, strict, allow_overwrite, kanonik rows). `expected_hash` parmak izine GİRMEZ.
 * Hücre değerleri yalnız karma içinde kullanılır, hiçbir yere yazılmaz.
 */
export function requestFingerprint({ kind, strict, allowOverwrite, rows }) {
  const canonicalRows = rows.map((row) => [row.n, Object.keys(row.cells).sort().map((key) => [key, row.cells[key]])]);
  return sha256(
    canonicalJson({ v: 1, kind, spec_version: SPEC_VERSION, strict: strict === true, allow_overwrite: allowOverwrite === true, rows: canonicalRows }),
  );
}
