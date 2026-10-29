// Acil durum akışı servisi (107): çağıranın bağlı olduğu sitelerin acil durum bilgisi (adres + asansör bakım firması) ve yöneticinin
// asansör bakım firması kaydı.
//
// Sözleşme: docs/PLATFORM_ACIL_DURUM.md. Çekirdek özellik: modül kapısı YOKTUR (acil durumda kapalı bir modül yüzünden bilgi gizlenmez).
// Kapsam: site listesi `module_service.MY_SITES_SQL` ile AYNIDIR (istemcinin "benim sitelerim" listesi: yönetici, kurul, görevli, sakin). Başka sitenin
// adresi ya da firması ASLA dönmez. Süper kullanıcı: boş liste (site bağı yoktur). Hata yanıtları bilgi sızdırmaz.

import { pool } from '../db.js';
import { cleanText, clipChars } from '../utils/safe_text.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { MY_SITES_SQL } from './module_service.js';

export const FIRM_NAME_MAX = 120;
export const FIRM_PHONE_MIN = 3;
export const FIRM_PHONE_MAX = 32;

/** Yönetici rütbesi (MY_SITES_SQL: manager 4 > kurul 3 > görevli 2 > sakin 1). */
const MANAGER_RANK = 4;

/** Sitelerin adres ve asansör bakım firması bilgisi; kayıt yoksa firma alanları NULL. $1 = site kodları (BIGINT[]). */
export const SITE_EMERGENCY_SQL = `
  SELECT s.site_code, s.address, s.city, s.district, e.elevator_firm_name, e.elevator_firm_phone
  FROM sites s
  LEFT JOIN site_emergency_info e ON e.site_code = s.site_code
  WHERE s.site_code = ANY($1::BIGINT[])
`;

const UPSERT_SQL = `
  INSERT INTO site_emergency_info (site_code, elevator_firm_name, elevator_firm_phone)
  VALUES ($1, $2, $3)
  ON CONFLICT (site_code) DO UPDATE
  SET elevator_firm_name = EXCLUDED.elevator_firm_name,
      elevator_firm_phone = EXCLUDED.elevator_firm_phone,
      updated_at = NOW()
`;

const DELETE_SQL = `DELETE FROM site_emergency_info WHERE site_code = $1`;

const positiveInt = (value) => {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
};

const invalidField = (field, message) => new PlatformError(400, 'INVALID_FIELD', message, { field });

/** Boş / yok -> null; aksi halde boşlukları teke indirilmiş, görünmez karakterleri atılmış kısa metin. Metin dışı değer 400. */
export function normalizeFirmName(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('elevator_firm_name', 'Firma adı metin olmalıdır.');
  const text = clipChars(cleanText(value).replace(/\s+/g, ' '), FIRM_NAME_MAX + 1);
  if (text === '') return null;
  if (Array.from(text).length > FIRM_NAME_MAX) {
    throw invalidField('elevator_firm_name', `Firma adı en çok ${FIRM_NAME_MAX} karakter olabilir.`);
  }
  return text;
}

/**
 * Telefon: rakam, boşluk ve + ( ) - . ; 3-15 hane (kısa numara "444 1 234" ve +90 numaraları). Boş / yok -> null.
 * Rakam dışı harf, çok uzun ya da çok kısa değer 400. Kayıtlı değer yazıldığı gibidir (boşluklar teke indirilir): arama sırasında
 * istemci yalnız rakam ve + bırakır.
 */
export function normalizeFirmPhone(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('elevator_firm_phone', 'Telefon metin olmalıdır.');
  const text = cleanText(value).replace(/\s+/g, ' ').trim();
  if (text === '') return null;
  if (text.length < FIRM_PHONE_MIN || text.length > FIRM_PHONE_MAX) {
    throw invalidField('elevator_firm_phone', `Telefon ${FIRM_PHONE_MIN}-${FIRM_PHONE_MAX} karakter olmalıdır.`);
  }
  if (!/^\+?[0-9()\-\s.]+$/.test(text)) {
    throw invalidField('elevator_firm_phone', 'Telefon yalnız rakam, boşluk ve + ( ) - . içerebilir.');
  }
  const digits = text.replace(/\D/g, '');
  if (digits.length < 3 || digits.length > 15) {
    throw invalidField('elevator_firm_phone', 'Telefon 3-15 rakamdan oluşmalıdır.');
  }
  return text;
}

/**
 * PUT gövdesi: iki alan da YERİNE yazılır (gönderilmeyen alan temizlenir); ikisi de hiç gönderilmezse 400 (boş gövdeyle kazara silme olmaz).
 * Firma adı yazılıp telefon boş bırakılırsa 400 (telefonsuz firma acil durumda işe yaramaz). İkisi de boşsa kayıt silinir.
 * @returns {{ name: string|null, phone: string|null }}
 */
export function parseEmergencyInfoBody(body) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  if (!('elevator_firm_name' in input) && !('elevator_firm_phone' in input)) {
    throw new PlatformError(400, 'INVALID_BODY', 'Asansör bakım firması adı ve telefonu gönderilmelidir.');
  }
  const name = normalizeFirmName(input.elevator_firm_name);
  const phone = normalizeFirmPhone(input.elevator_firm_phone);
  if (name !== null && phone === null) {
    throw invalidField('elevator_firm_phone', 'Firma adını yazdıysanız telefonunu da yazın.');
  }
  return { name, phone };
}

const textOrNull = (value) => {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text === '' ? null : text;
};

/**
 * GET /app/emergency: çağıranın bağlı olduğu (onaylı) siteler için { sites: [{ site_code, site_name, address, city, district,
 * elevator_firm_name, elevator_firm_phone, can_edit }] }. `can_edit`: o sitenin yöneticisi (kurul / görevli / sakin değil).
 */
export async function listEmergencySites(authUser, db = pool) {
  if (authUser?.role === 'super_user') return { sites: [] };
  const userCode = positiveInt(authUser?.user_code ?? authUser?.userCode ?? authUser?.id);
  if (userCode === null) return { sites: [] };
  const linked = await db.query(MY_SITES_SQL, [userCode]);
  const linkedRows = linked.rows ?? [];
  if (linkedRows.length === 0) return { sites: [] };
  const codes = linkedRows.map((row) => Number(row.site_code));
  const details = await db.query(SITE_EMERGENCY_SQL, [codes]);
  const byCode = new Map((details.rows ?? []).map((row) => [Number(row.site_code), row]));
  return {
    sites: linkedRows.map((row) => {
      const code = Number(row.site_code);
      const info = byCode.get(code) ?? {};
      return {
        site_code: code,
        site_name: textOrNull(row.site_name) ?? '',
        address: textOrNull(info.address),
        city: textOrNull(info.city),
        district: textOrNull(info.district),
        elevator_firm_name: textOrNull(info.elevator_firm_name),
        elevator_firm_phone: textOrNull(info.elevator_firm_phone),
        can_edit: Number(row.rank) === MANAGER_RANK,
      };
    }),
  };
}

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch {
    // yut
  }
}

/** PUT /manager/sites/:siteCode/emergency: asansör bakım firmasını yazar (ikisi de boşsa kaydı siler) ve denetim kaydı düşer. Yetki rotada denetlenir. */
export async function saveElevatorFirm({ siteCode, input, actor }) {
  const code = positiveInt(siteCode);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  const { name, phone } = input;
  const cleared = name === null && phone === null;
  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    if (cleared) {
      await client.query(DELETE_SQL, [code]);
    } else {
      await client.query(UPSERT_SQL, [code, name, phone]);
    }
    await recordAudit(
      client,
      {
        actor: actorFromAuthUser(actor),
        action: 'emergency.info_updated',
        siteCode: code,
        targetType: 'site',
        targetId: String(code),
        details: { elevator_firm: cleared ? 'cleared' : 'set' },
      },
      { inTransaction: true },
    );
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) await rollbackQuietly(client);
    throw error;
  } finally {
    client.release();
  }
  return { site_code: code, elevator_firm_name: name, elevator_firm_phone: phone };
}
