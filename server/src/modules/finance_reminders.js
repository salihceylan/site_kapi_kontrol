// Borç hatırlatma (Faz 4b Ö6): uygunluk, önizleme (YAZMAZ), onaylı gönderim (kuyruğa alma), çalıştırma istatistiği / iptali, muafiyet listesi.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö6". Varsayılan KAPALI + sistem düzeyinde hukuk onayı bayrağına bağlı. Bayat borç koruması ve gönderim kuyruk işçisindedir
// (finance_reminder_queue.js). İKİ HESAP (İP-1A): uygunluk (eşik, gecikme günü) HESAP başına (her hesabın kendi mahsubu); hatırlatma hesabın SAHİBİNE gider
// (finance_parties.visiblePartyOfRelation: kiracı hesabı -> kiracı, ev sahibi hesabı -> malik; ilişkisi belirtilmemiş sakin dairede güncel kiracı varsa kiracı
// hesabının, yoksa ev sahibi hesabının sahibidir, ANCAK yalnız sorumlu both iken ya da sorumlu tarafın güncel kişisi yokken: Borcum ile aynı); both dairede
// malik kiracı hesabı için hatırlatma ALMAZ. Sıklık kayıtları (finance_reminder_apartments) daire başınadır
// (temkinli); ardışık sayaç hesabın son tahsilatına göre. AŞAĞIDAKİ 4b metni (responsible_party kuralı) İP-1A ile DEĞİŞTİ:
// (eski) KİME: 4a "Borcum" görünürlük kuralının AYNISI: owner -> güncel malik; tenant -> kiracı; both ->
// malik + kiracı + resident; eşleşen kişi yoksa güvenli yedek; family_member ASLA. Kişi başına TEK ileti (≤ 20 daire). Adres = Faz 2 "etkin iletişim e-postası"
// (dahili daire hesabı adresi sayılmaz); aynı kanonik adres bir çalıştırmada TEK kez (duplicate); bastırılmış / tercihi kapalı -> skipped_pref; adres başına 7 günde en çok 1
// hatırlatma (capped); site günlük sınırı FINANCE_REMINDER_MAX_PER_DAY_PER_SITE (300). Uygunluk (daire): etkin, muaf değil, M1 gecikmiş borç >= eşik, en eski ödenmemiş
// kalemin gecikmesi >= gün eşiği, son hatırlatmadan beri >= aralık, son tahsilattan beri ardışık hatırlatma < sınır (sonrası "elden takip": e-posta GİTMEZ).
// KOORDİNATÖR KARARI Q4: tutar YALNIZ doğrulanmış gerçek hesap e-postasına (hesaplı + users.email_verified); diğerlerine tutarsız metin.
// GİZLİLİK: yanıtlar ad / adres DÖNMEZ; log / audit'e ad, adres yazılmaz.
// KİLİT SIRASI: sites KEY SHARE -> finance_post -> apartments (id sırasıyla KEY SHARE) -> users -> finans satırları.

import { pool } from '../db.js';
import { isSmtpConfigured } from '../mailer.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  dayNumber,
  emailNotConfigured,
  fingerprintOf,
  noReminderRecipients,
  objectOf,
  present,
  queryInt,
  reminderDailyLimit,
  reminderRunNotCancellable,
  reminderRunNotFound,
  remindersDisabled,
  legalApprovalRequired,
  sha256Hex,
} from './finance_4b_common.js';
import { cleanReminderNote, noteHasLink, REMINDER_TONES } from './finance_reminder_mail.js';
import { apartmentNotFound, idempotencyConflict, invalidBody, normalizeFreeText, parseIdempotencyKey, previewStale, today } from './finance_common.js';
import { m1Ctes } from './finance_m1.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { accountPartySql, currentTenantSql, responsiblePersonSql, visiblePartyOfRelation } from './finance_parties.js';
import { withReportSnapshot } from './finance_reports.js';
import { loadEffectiveSettings, readLegalOk } from './finance_settings.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { canonicalAddress, hashEmail, hashEmailAll } from './announcement_email_security.js';
import { deliverableEmailSql } from './announcement_recipients.js';
import { ACCOUNT_KIND_SQL, apartmentLabel, parsePositiveId, toIso } from './people_common.js';
import { CONTACT_EMAIL_SQL, PERSON_FROM } from './people_service.js';

export const REMINDER_MAX_APARTMENTS_PER_PERSON = 20;

// İki hesap (İP-1A): defter satırının (takma ad `l`) hesabı, dairenin (takma ad `a`) güncel kiracısı ve borç sorumlusu tarafın güncel kişisi.
const LEDGER_ACCOUNT = accountPartySql('l');
const CURRENT_TENANT = currentTenantSql('a');
const RESPONSIBLE_PERSON = responsiblePersonSql('a');
export const REMINDER_PER_ADDRESS_DAYS = 7;
export const REMINDER_ITEM_STATUSES = Object.freeze(['pending', 'sent', 'failed', 'no_address', 'skipped_pref', 'duplicate', 'capped', 'resolved', 'cancelled']);

/** Site günlük sınırı (env FINANCE_REMINDER_MAX_PER_DAY_PER_SITE; geçersizse 300). */
export function reminderDailyCap(env = process.env) {
  const raw = Number(env.FINANCE_REMINDER_MAX_PER_DAY_PER_SITE);
  return Number.isSafeInteger(raw) && raw >= 0 && String(env.FINANCE_REMINDER_MAX_PER_DAY_PER_SITE ?? '').trim() !== '' ? raw : 300;
}

// --- Gövde ayrıştırma ----------------------------------------------------------------------------------------------------------------------

function parseTone(value) {
  if (!REMINDER_TONES.includes(value)) {
    throw invalidBody('Ton geçersiz (nazik veya resmî).');
  }
  return value;
}

export function parseReminderPreview(body) {
  return { tone: parseTone(objectOf(body).tone) };
}

export function parseReminderSend(body) {
  const input = objectOf(body);
  const apartmentCount = input.expected_apartment_count;
  const personCount = input.expected_person_count;
  for (const [value, label] of [[apartmentCount, 'daire'], [personCount, 'kişi']]) {
    if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 100000) {
      throw invalidBody(`Beklenen ${label} sayısı geçersiz.`);
    }
  }
  if (typeof input.expected_hash !== 'string' || !/^[0-9a-f]{64}$/.test(input.expected_hash)) {
    throw invalidBody('Önizleme özeti (expected_hash) zorunludur; önizlemeyi yenileyin.');
  }
  const note = normalizeFreeText(input.note, { label: 'Not', max: 300 });
  if (noteHasLink(note)) {
    throw invalidBody('Not bağlantı, alan adı ya da e-posta adresi içeremez.');
  }
  return {
    tone: parseTone(input.tone),
    note,
    expectedHash: input.expected_hash,
    expectedApartmentCount: apartmentCount,
    expectedPersonCount: personCount,
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export const reminderFingerprint = (input) => fingerprintOf({ v: 1, kind: 'reminder_send', tone: input.tone, note: cleanReminderNote(input.note) });

// --- Plan -------------------------------------------------------------------------------------------------------------------------------

/** Aday anahtarı: (daire, hesap). */
export const candidateKey = (apartmentId, accountParty) => `${apartmentId}:${accountParty}`;

/**
 * Etkin daireler için M1 gecikmiş borç + uygunluk verileri (T = bugün). İki hesap (İP-1A): aday (daire, HESAP) başınadır (`accountParty`); mahsup hesap içinde.
 * Aralık (`lastDay`) daire başına hatırlatma kayıtlarından; ardışık sayaç hesabın son tahsilatından sonraki daire hatırlatmalarıdır (temkinli).
 */
export async function loadCandidateApartments(db, siteCode, todayIso, apartmentIds = null) {
  const filter = apartmentIds === null ? '' : ' AND l.apartment_id = ANY($3::BIGINT[])';
  const result = await db.query(
    `
      WITH ${m1Ctes('$1', '$2', filter)},
      sums AS (
        SELECT rem.apartment_id, rem.account_party,
               COALESCE(SUM(rem.r) FILTER (WHERE rem.due <= $2::DATE), 0) AS overdue,
               MIN(rem.due) FILTER (WHERE rem.r > 0 AND rem.due <= $2::DATE) AS oldest_due
        FROM rem GROUP BY rem.apartment_id, rem.account_party
      ),
      lastpay AS (
        SELECT l.apartment_id, ${LEDGER_ACCOUNT} AS account_party, MAX(l.entry_date) AS last_pay
        FROM ledger_entries l
        WHERE l.site_code = $1 AND l.kind = 'payment' AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id)${filter}
        GROUP BY 1, 2
      ),
      hist AS (
        SELECT s.apartment_id, s.account_party,
               (MAX((fa.reminded_at AT TIME ZONE 'Europe/Istanbul')::DATE) - DATE '1970-01-01') AS last_day,
               COUNT(*) FILTER (WHERE lp.last_pay IS NULL OR (fa.reminded_at AT TIME ZONE 'Europe/Istanbul')::DATE > lp.last_pay)::INTEGER AS consecutive
        FROM sums s
        INNER JOIN finance_reminder_apartments fa ON fa.site_code = $1 AND fa.apartment_id = s.apartment_id
        LEFT JOIN lastpay lp ON lp.apartment_id = s.apartment_id AND lp.account_party = s.account_party
        GROUP BY s.apartment_id, s.account_party
      )
      SELECT a.id, s.account_party, a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort, s.overdue::TEXT AS overdue,
             to_char(s.oldest_due, 'YYYY-MM-DD') AS oldest_due, h.last_day, COALESCE(h.consecutive, 0) AS consecutive, (x.apartment_id IS NOT NULL) AS excluded
      FROM sums s
      INNER JOIN apartments a ON a.id = s.apartment_id
      INNER JOIN site_blocks b ON b.id = a.block_id
      LEFT JOIN hist h ON h.apartment_id = a.id AND h.account_party = s.account_party
      LEFT JOIN finance_reminder_exclusions x ON x.site_code = $1 AND x.apartment_id = a.id
      WHERE a.site_code = $1 AND a.is_active = TRUE AND s.overdue > 0
      ORDER BY b.sort_order, a.sort_order, a.id, s.account_party
    `,
    apartmentIds === null ? [siteCode, todayIso] : [siteCode, todayIso, apartmentIds],
  );
  return (result.rows ?? []).map((row) => ({
    id: Number(row.id),
    accountParty: row.account_party === 'tenant' ? 'tenant' : 'owner',
    label: apartmentLabel(row.block_name, row.unit_label),
    overdue: toBigInt(row.overdue),
    oldestDue: row.oldest_due,
    lastDay: row.last_day === null || row.last_day === undefined ? null : Number(row.last_day),
    consecutive: Number(row.consecutive),
    excluded: row.excluded === true,
  }));
}

/** Eşik koşulları (daire): ilk başarısız neden ya da null (uygun). */
export function failingReason(apartment, thresholds, todayDay) {
  if (apartment.excluded) return 'exclusion';
  if (apartment.overdue < BigInt(thresholds.min_overdue_minor)) return 'amount';
  if (apartment.oldestDue === null || todayDay - dayNumber(apartment.oldestDue) < thresholds.min_days_overdue) return 'days';
  if (apartment.lastDay !== null && todayDay - apartment.lastDay < thresholds.min_interval_days) return 'interval';
  if (apartment.consecutive >= thresholds.max_consecutive) return 'consecutive';
  return null;
}

export const thresholdsOf = (settings) => ({
  min_overdue_minor: settings.reminder_min_overdue_minor,
  min_days_overdue: settings.reminder_min_days_overdue,
  min_interval_days: settings.reminder_min_interval_days,
  max_consecutive: settings.reminder_max_consecutive,
});

/**
 * Hesap sahibi alıcılar (İP-1A): kişinin daireDEKİ güncel ilişkisinden kendi hesabı (`account_party`; finance_parties.visiblePartyOfRelation: Borcum
 * görünümüyle AYNI kural; ilişkisi belirtilmemiş sakin yalnız sorumlu both iken ya da sorumlu tarafın güncel kişisi yokken); aile üyesi yok.
 * Gönderim anında da kullanılır (finance_reminder_queue.js): kişi o dairede HÂLÂ güncel ve hatırlatılan hesabın sahibi mi.
 */
export async function loadRecipientRows(db, siteCode, apartmentIds) {
  const result = await db.query(
    `
      SELECT rr.apartment_id, sp.id AS person_id, rr.relation, ${CURRENT_TENANT} AS has_tenant, a.responsible_party, ${RESPONSIBLE_PERSON} AS has_responsible_person,
             ${ACCOUNT_KIND_SQL} AS account_kind, COALESCE(u.email_verified, FALSE) AS verified, COALESCE(np.email_finance_reminders, TRUE) AS pref,
             ${deliverableEmailSql(CONTACT_EMAIL_SQL)} AS email
      ${PERSON_FROM}
      INNER JOIN apartment_residencies rr ON rr.person_id = sp.id AND rr.is_current = TRUE
      INNER JOIN apartments a ON a.id = rr.apartment_id AND a.site_code = sp.site_code
      LEFT JOIN notification_preferences np ON np.user_code = sp.user_code
      WHERE sp.site_code = $1 AND sp.is_active = TRUE AND rr.apartment_id = ANY($2::BIGINT[])
        AND (u.user_code IS NULL OR u.deleted_at IS NULL)
        AND rr.relation <> 'family_member'
      ORDER BY sp.id, rr.apartment_id
    `,
    [siteCode, apartmentIds],
  );
  const out = [];
  for (const row of result.rows ?? []) {
    const accountParty = visiblePartyOfRelation(row.relation, {
      hasCurrentTenant: row.has_tenant === true,
      responsibleParty: row.responsible_party,
      hasResponsiblePerson: row.has_responsible_person === true,
    });
    if (accountParty !== null) {
      out.push({ ...row, account_party: accountParty });
    }
  }
  return out;
}

async function suppressedHashes(db, hashes) {
  if (hashes.length === 0) {
    return new Set();
  }
  const result = await db.query(`SELECT email_hash FROM announcement_email_suppressions WHERE email_hash = ANY($1::TEXT[])`, [hashes]);
  return new Set((result.rows ?? []).map((row) => row.email_hash));
}

async function recentlyRemindedHashes(db, hashes) {
  if (hashes.length === 0) {
    return new Set();
  }
  const result = await db.query(
    `SELECT DISTINCT email_hash FROM finance_reminder_items WHERE email_hash = ANY($1::TEXT[]) AND email_status = 'sent' AND sent_at > NOW() - make_interval(days => $2::INTEGER)`,
    [hashes, REMINDER_PER_ADDRESS_DAYS],
  );
  return new Set((result.rows ?? []).map((row) => row.email_hash));
}

async function usedToday(db, siteCode, todayIso) {
  const result = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS used FROM finance_reminder_items i INNER JOIN finance_reminder_runs r ON r.id = i.run_id
      WHERE r.site_code = $1 AND r.run_on = $2::DATE AND i.email_status IN ('pending', 'sent')
    `,
    [siteCode, todayIso],
  );
  return Number(result.rows[0].used);
}

/**
 * Hatırlatma planı. lock: yazma yolunda aday dairelerin satırları id sırasıyla FOR KEY SHARE kilitlenir.
 * @returns {Promise<object>} { apartments, excluded, handFollowUp, persons, counts, hash, totalOverdue, sample }
 */
export async function computeReminderPlan(db, siteCode, { settings, tone, now = new Date(), lock = false }) {
  const todayIso = today(now);
  const todayDay = dayNumber(todayIso);
  const thresholds = thresholdsOf(settings);
  let candidates = await loadCandidateApartments(db, siteCode, todayIso);
  if (lock && candidates.length > 0) {
    const locked = await db.query(`SELECT id FROM apartments WHERE site_code = $1 AND id = ANY($2::BIGINT[]) AND is_active = TRUE ORDER BY id FOR KEY SHARE`, [
      siteCode,
      [...new Set(candidates.map((c) => c.id))],
    ]);
    const stillActive = new Set((locked.rows ?? []).map((row) => Number(row.id)));
    candidates = candidates.filter((c) => stillActive.has(c.id));
  }
  const excluded = { amount: 0, days: 0, interval: 0, consecutive: 0, exclusion: 0, no_recipient: 0 };
  const handFollowUp = [];
  const eligible = [];
  for (const apartment of candidates) {
    const reason = failingReason(apartment, thresholds, todayDay);
    if (reason === null) {
      eligible.push(apartment);
    } else {
      excluded[reason] += 1;
      if (reason === 'consecutive') {
        handFollowUp.push(apartment);
      }
    }
  }
  // İki hesap (İP-1A): aday (daire, hesap); alıcı yalnız o hesabın sahibi. Kişinin bir dairede tek hesabı vardır (kendi hesabı).
  const byApartment = new Map(eligible.map((candidate) => [candidateKey(candidate.id, candidate.accountParty), candidate]));
  const recipients = eligible.length === 0 ? [] : await loadRecipientRows(db, siteCode, [...new Set(eligible.map((a) => a.id))]);
  const personMap = new Map();
  const covered = new Set();
  for (const row of recipients) {
    const key = candidateKey(Number(row.apartment_id), row.account_party);
    if (!byApartment.has(key)) {
      continue; // kişinin hesabı bu dairede uygun aday değil (ör. both dairede malik, borç kiracı hesabında)
    }
    const personId = Number(row.person_id);
    let person = personMap.get(personId);
    if (!person) {
      person = {
        personId,
        apartmentIds: [],
        accounts: new Map(),
        accountKind: row.account_kind,
        verified: row.verified === true,
        pref: row.pref !== false,
        email: row.email ?? null,
      };
      personMap.set(personId, person);
    }
    person.apartmentIds.push(Number(row.apartment_id));
    person.accounts.set(Number(row.apartment_id), row.account_party);
  }
  const persons = [...personMap.values()].sort((a, b) => a.personId - b.personId);
  for (const person of persons) {
    person.apartmentIds = [...new Set(person.apartmentIds)].sort((a, b) => a - b).slice(0, REMINDER_MAX_APARTMENTS_PER_PERSON);
    person.hash = person.email === null ? null : hashEmail(person.email);
  }
  const hashes = [...new Set(persons.filter((p) => p.hash !== null).map((p) => p.hash))];
  const allSaltHashes = [...new Set(persons.filter((p) => p.email !== null).flatMap((p) => hashEmailAll(p.email)))];
  const suppressed = await suppressedHashes(db, allSaltHashes);
  const recent = await recentlyRemindedHashes(db, hashes);
  const allowance = Math.max(0, reminderDailyCap() - (await usedToday(db, siteCode, todayIso)));
  const seen = new Set();
  let used = 0;
  const counts = { pending: 0, no_address: 0, skipped_pref: 0, duplicate: 0, capped: 0, with_amount: 0 };
  for (const person of persons) {
    person.hasAccount = person.accountKind !== 'none';
    person.withAmount = person.accountKind === 'registered' && person.verified && person.email !== null;
    if (person.email === null) {
      person.status = 'no_address';
    } else if (hashEmailAll(person.email).some((h) => suppressed.has(h)) || (person.hasAccount && person.pref === false)) {
      person.status = 'skipped_pref';
    } else if (seen.has(person.hash)) {
      person.status = 'duplicate';
    } else if (recent.has(person.hash) || used >= allowance) {
      person.status = 'capped';
      seen.add(person.hash);
    } else {
      person.status = 'pending';
      seen.add(person.hash);
      used += 1;
      for (const id of person.apartmentIds) {
        covered.add(candidateKey(id, person.accounts.get(id)));
      }
    }
    counts[person.status] += 1;
    if (person.status === 'pending' && person.withAmount) {
      counts.with_amount += 1;
    }
  }
  for (const candidate of eligible) {
    const hasAnyPerson = persons.some((person) => person.apartmentIds.includes(candidate.id) && person.accounts.get(candidate.id) === candidate.accountParty);
    if (!hasAnyPerson) {
      excluded.no_recipient += 1;
    }
  }
  const pendingPersons = persons.filter((person) => person.status === 'pending');
  // Kapsanan hesaplar (daire, hesap); daire sayısı / aralık kaydı daire başınadır.
  const coveredAccounts = eligible.filter((candidate) => covered.has(candidateKey(candidate.id, candidate.accountParty)));
  const coveredApartments = [];
  const seenApartments = new Set();
  for (const candidate of coveredAccounts) {
    if (!seenApartments.has(candidate.id)) {
      seenApartments.add(candidate.id);
      coveredApartments.push(candidate);
    }
  }
  let totalOverdue = 0n;
  for (const candidate of coveredAccounts) {
    totalOverdue += candidate.overdue;
  }
  const hash = sha256Hex(
    `v1|${tone}|${JSON.stringify(thresholds)}|${pendingPersons
      .map((p) => `${p.personId}:${p.apartmentIds.map((id) => `${id}${p.accounts.get(id) === 'tenant' ? 't' : 'o'}`).join('.')}:${p.withAmount ? 1 : 0}`)
      .join(',')}`,
  );
  return {
    todayIso,
    thresholds,
    excluded,
    handFollowUp,
    persons,
    pendingPersons,
    coveredApartments,
    coveredAccounts,
    counts,
    hash,
    totalOverdue,
    byApartment,
  };
}

/**
 * Önizleme gövdesi (YAZMAZ; adres / ad DÖNMEZ). İki hesap (İP-1A): hariç tutma ve elden takip sayıları HESAP başınadır; ikinci inceleme:
 * `hand_follow_up_accounts` elden takip öğelerini hesabıyla verir (aynı dairenin iki hesabı iki öğe; eski `hand_follow_up_apartments` yalnız etiket).
 */
export function reminderPreviewBody(plan, { smtp, blockers }) {
  return {
    apartment_count: plan.coveredApartments.length,
    person_count: plan.pendingPersons.length,
    with_amount_count: plan.counts.with_amount,
    without_amount_count: plan.pendingPersons.length - plan.counts.with_amount,
    no_address_count: plan.counts.no_address,
    skipped_pref_count: plan.counts.skipped_pref,
    duplicate_count: plan.counts.duplicate,
    capped_count: plan.counts.capped,
    total_overdue_minor: minorToNumber(plan.totalOverdue),
    // İki hesap (İP-1A): kapsanan hesap sayısı (aynı dairenin iki hesabı iki sayılır; apartment_count daire başınadır)
    account_count: plan.coveredAccounts.length,
    excluded: plan.excluded,
    hand_follow_up_count: plan.handFollowUp.length,
    hand_follow_up_apartments: plan.handFollowUp.slice(0, 20).map((apartment) => apartment.label),
    hand_follow_up_accounts: plan.handFollowUp.slice(0, 20).map((candidate) => ({ label: candidate.label, account_party: candidate.accountParty })),
    sample_apartments: plan.coveredApartments.slice(0, 20).map((apartment) => apartment.label),
    smtp_configured: smtp,
    preview_hash: plan.hash,
    blockers,
    can_send: blockers.length === 0,
  };
}

async function gateBlockers(db, siteCode, settings, plan, todayIso) {
  const blockers = [];
  if (!settings.reminders_enabled) blockers.push('REMINDERS_DISABLED');
  if (!(await readLegalOk(db))) blockers.push('LEGAL_APPROVAL_REQUIRED');
  if (!isSmtpConfigured()) blockers.push('EMAIL_NOT_CONFIGURED');
  const dup = await db.query(`SELECT 1 FROM finance_reminder_runs WHERE site_code = $1 AND run_on = $2::DATE AND status = 'active' LIMIT 1`, [siteCode, todayIso]);
  if (dup.rows?.[0]) blockers.push('REMINDER_DAILY_LIMIT');
  if (plan.pendingPersons.length === 0) blockers.push('NO_REMINDER_RECIPIENTS');
  return blockers;
}

/** POST reminders/preview (YAZMAZ; adres / ad DÖNMEZ). */
export async function previewReminders({ siteCode, body, now = new Date() }, db = pool) {
  const input = parseReminderPreview(body);
  // Ağır hesap: eşzamanlılık yuvası ('preview'), tek anlık görüntü + statement_timeout (R10 P2-9).
  return withReportSnapshot(
    siteCode,
    async (client) => {
      const settings = await loadEffectiveSettings(client, siteCode);
      const plan = await computeReminderPlan(client, siteCode, { settings, tone: input.tone, now });
      const blockers = await gateBlockers(client, siteCode, settings, plan, plan.todayIso);
      return reminderPreviewBody(plan, { smtp: isSmtpConfigured(), blockers });
    },
    db,
    { slot: 'preview' },
  );
}

// --- Gönderim (kuyruğa alma) ---------------------------------------------------------------------------------------------------------

const RUN_STATS_SQL = `
  COALESCE((SELECT jsonb_object_agg(s.email_status, s.n) FROM (SELECT i.email_status, COUNT(*)::INTEGER AS n FROM finance_reminder_items i WHERE i.run_id = r.id GROUP BY i.email_status) s), '{}'::jsonb) AS stats
`;
const RUN_SELECT = `
  SELECT r.id, r.status, r.tone, r.apartment_count, r.person_count, r.with_amount_count, r.params, r.created_at, r.cancelled_at, r.request_fingerprint,
         cu.full_name AS created_by_name, ${RUN_STATS_SQL}
  FROM finance_reminder_runs r LEFT JOIN users cu ON cu.user_code = r.created_by
`;

function mapRun(row) {
  const stats = Object.fromEntries(REMINDER_ITEM_STATUSES.map((status) => [status, Number(row.stats?.[status] ?? 0)]));
  return {
    id: Number(row.id),
    status: row.status,
    tone: row.tone,
    apartment_count: Number(row.apartment_count),
    person_count: Number(row.person_count),
    with_amount_count: Number(row.with_amount_count),
    params: row.params,
    stats,
    created_at: toIso(row.created_at),
    cancelled_at: toIso(row.cancelled_at),
    created_by_name: row.created_by_name ?? null,
  };
}

async function findRunByKey(db, siteCode, key) {
  const result = await db.query(`${RUN_SELECT} WHERE r.site_code = $1 AND r.idempotency_key = $2`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** POST reminders/send -> { replayed, run }. */
export async function sendReminders({ siteCode, body, actor, now = new Date() }) {
  const input = parseReminderSend(body);
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = reminderFingerprint(input);
  return withFinanceTransaction(siteCode, async (client) => {
    const replay = await findRunByKey(client, siteCode, input.idempotencyKey);
    if (replay) {
      if (replay.request_fingerprint !== fingerprint) {
        throw idempotencyConflict();
      }
      return { replayed: true, run: mapRun(replay) };
    }
    const settings = await loadEffectiveSettings(client, siteCode);
    if (!settings.reminders_enabled) throw remindersDisabled();
    if (!(await readLegalOk(client))) throw legalApprovalRequired();
    if (!isSmtpConfigured()) throw emailNotConfigured();
    const todayIso = today(now);
    const daily = await client.query(`SELECT 1 FROM finance_reminder_runs WHERE site_code = $1 AND run_on = $2::DATE AND status = 'active' LIMIT 1`, [siteCode, todayIso]);
    if (daily.rows?.[0]) throw reminderDailyLimit();
    const plan = await computeReminderPlan(client, siteCode, { settings, tone: input.tone, now, lock: true });
    if (plan.pendingPersons.length === 0) {
      throw noReminderRecipients();
    }
    if (plan.hash !== input.expectedHash || plan.coveredApartments.length !== input.expectedApartmentCount || plan.pendingPersons.length !== input.expectedPersonCount) {
      throw previewStale({ apartment_count: plan.coveredApartments.length, person_count: plan.pendingPersons.length, preview_hash: plan.hash });
    }
    await lockActorRow(client, actorInfo);
    const params = { ...plan.thresholds, settings_version: settings.settings_version };
    const inserted = await client.query(
      `
        INSERT INTO finance_reminder_runs (site_code, tone, note, params, apartment_count, person_count, with_amount_count, preview_hash, idempotency_key, request_fingerprint, run_on, created_by)
        VALUES ($1, $2, $3, $4::JSONB, $5, $6, $7, $8, $9, $10, $11::DATE, $12)
        RETURNING id
      `,
      [
        siteCode,
        input.tone,
        cleanReminderNote(input.note),
        JSON.stringify(params),
        plan.coveredApartments.length,
        plan.pendingPersons.length,
        plan.counts.with_amount,
        plan.hash,
        input.idempotencyKey,
        fingerprint,
        todayIso,
        actorInfo.userCode,
      ],
    );
    const runId = Number(inserted.rows[0].id);
    const persons = plan.persons;
    await client.query(
      `
        INSERT INTO finance_reminder_items (run_id, person_id, apartment_ids, with_amount, has_account, email, email_hash, email_status)
        SELECT $1, t.person_id, t.apartment_ids::BIGINT[], t.with_amount, t.has_account, NULLIF(t.email, ''), NULLIF(t.email_hash, ''), t.status
        FROM unnest($2::BIGINT[], $3::TEXT[], $4::BOOLEAN[], $5::BOOLEAN[], $6::TEXT[], $7::TEXT[], $8::TEXT[]) AS t(person_id, apartment_ids, with_amount, has_account, email, email_hash, status)
        ORDER BY t.person_id
      `,
      [
        runId,
        persons.map((p) => String(p.personId)),
        persons.map((p) => `{${p.apartmentIds.join(',')}}`),
        persons.map((p) => p.status === 'pending' && p.withAmount),
        persons.map((p) => p.hasAccount),
        persons.map((p) => (p.status === 'pending' ? p.email : '')),
        persons.map((p) => (p.status === 'pending' ? p.hash : '')),
        persons.map((p) => p.status),
      ],
    );
    await client.query(
      `INSERT INTO finance_reminder_apartments (site_code, apartment_id, run_id, reminded_at) SELECT $1, t.id, $2, NOW() FROM unnest($3::BIGINT[]) AS t(id) ORDER BY t.id`,
      [siteCode, runId, plan.coveredApartments.map((apartment) => String(apartment.id))],
    );
    await recordFinanceAudit(client, actor, 'finance.reminder.sent', siteCode, runId, {
      tone: input.tone,
      apartment_count: plan.coveredApartments.length,
      person_count: plan.pendingPersons.length,
      with_amount_count: plan.counts.with_amount,
      no_address_count: plan.counts.no_address,
      skipped_pref_count: plan.counts.skipped_pref,
      duplicate_count: plan.counts.duplicate,
      capped_count: plan.counts.capped,
    });
    const row = await client.query(`${RUN_SELECT} WHERE r.id = $1`, [runId]);
    return { replayed: false, run: mapRun(row.rows[0]) };
  });
}

// --- Çalıştırmalar --------------------------------------------------------------------------------------------------------------------------

/** GET reminders/runs -> { items, total } (alıcı adı / adres YOK). */
export async function listReminderRuns(siteCode, query = {}, db = pool) {
  const limit = queryInt(query.limit, { min: 1, max: 100, fallback: 20 });
  const offset = queryInt(query.offset, { min: 0, max: 100000, fallback: 0 });
  const total = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM finance_reminder_runs WHERE site_code = $1`, [siteCode]);
  const result = await db.query(`${RUN_SELECT} WHERE r.site_code = $1 ORDER BY r.id DESC LIMIT $2 OFFSET $3`, [siteCode, limit, offset]);
  return { items: (result.rows ?? []).map(mapRun), total: Number(total.rows[0].n) };
}

export async function getReminderRun(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw reminderRunNotFound();
  }
  const result = await db.query(`${RUN_SELECT} WHERE r.id = $1 AND r.site_code = $2`, [id, siteCode]);
  if (!result.rows?.[0]) {
    throw reminderRunNotFound();
  }
  return { run: mapRun(result.rows[0]) };
}

/** POST reminders/runs/:id/cancel: talep edilmemiş pending satırlar cancelled; yoldakiler sonuçlanır; hiç gönderilmemiş dairelerin aralık kayıtları silinir. */
export async function cancelReminderRun({ siteCode, rawId, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw reminderRunNotFound();
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const run = await client.query(`SELECT id, status FROM finance_reminder_runs WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    if (!run.rows?.[0]) {
      throw reminderRunNotFound();
    }
    if (run.rows[0].status !== 'active') {
      throw reminderRunNotCancellable();
    }
    // Satırlar (run_id, person_id) SIRASIYLA kilitlenir: kuyruk işçisi talep ve sonuç yazımında aynı sırayı kullanır (çok satırlı UPDATE'lerin sıra farkı 40P01 üretmesin).
    const cancelled = await client.query(
      `
        WITH locked AS (
          SELECT run_id, person_id FROM finance_reminder_items
          WHERE run_id = $1 AND email_status = 'pending' AND email_claimed_at IS NULL
          ORDER BY run_id, person_id
          FOR UPDATE
        )
        UPDATE finance_reminder_items i SET email_status = 'cancelled', email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
        FROM locked l WHERE i.run_id = l.run_id AND i.person_id = l.person_id
      `,
      [id],
    );
    await client.query(
      `
        DELETE FROM finance_reminder_apartments fa
        WHERE fa.run_id = $1 AND NOT EXISTS (
          SELECT 1 FROM finance_reminder_items i WHERE i.run_id = $1 AND i.email_status IN ('sent', 'pending') AND fa.apartment_id = ANY(i.apartment_ids)
        )
      `,
      [id],
    );
    await client.query(`UPDATE finance_reminder_runs SET status = 'cancelled', cancelled_by = $2, cancelled_at = NOW() WHERE id = $1 AND status = 'active'`, [id, actorInfo.userCode]);
    await recordFinanceAudit(client, actor, 'finance.reminder.cancelled', siteCode, id, { cancelled_count: Number(cancelled.rowCount ?? 0) });
    const row = await client.query(`${RUN_SELECT} WHERE r.id = $1`, [id]);
    return { run: mapRun(row.rows[0]) };
  });
}

// --- Muafiyet listesi ---------------------------------------------------------------------------------------------------------------------

/** GET reminders/exclusions -> { items: [{ apartment_id, label, reason, created_at }] }. */
export async function listExclusions(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT x.apartment_id, a.unit_label, b.block_name, x.reason, x.created_at
      FROM finance_reminder_exclusions x INNER JOIN apartments a ON a.id = x.apartment_id INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE x.site_code = $1 ORDER BY b.sort_order, a.sort_order, a.id
    `,
    [siteCode],
  );
  return {
    items: (result.rows ?? []).map((row) => ({ apartment_id: Number(row.apartment_id), label: apartmentLabel(row.block_name, row.unit_label), reason: row.reason ?? null, created_at: toIso(row.created_at) })),
  };
}

/** PUT reminders/exclusions/:apartmentId { reason? }. */
export async function addExclusion({ siteCode, rawApartmentId, body, actor }) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw apartmentNotFound();
  }
  const reason = normalizeFreeText(objectOf(body).reason, { label: 'Neden', max: 100 });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const apartment = await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [apartmentId, siteCode]);
    if (!apartment.rows?.[0]) {
      throw apartmentNotFound();
    }
    await lockActorRow(client, actorInfo);
    const result = await client.query(
      `
        INSERT INTO finance_reminder_exclusions (site_code, apartment_id, reason, created_by) VALUES ($1, $2, $3, $4)
        ON CONFLICT (site_code, apartment_id) DO UPDATE SET reason = EXCLUDED.reason
        RETURNING (xmax = 0) AS inserted
      `,
      [siteCode, apartmentId, reason, actorInfo.userCode],
    );
    if (result.rows[0].inserted === true) {
      await recordFinanceAudit(client, actor, 'finance.reminder.exclusion_added', siteCode, apartmentId, {});
    }
    return { apartment_id: apartmentId, excluded: true };
  });
}

/** DELETE reminders/exclusions/:apartmentId (idempotent). */
export async function removeExclusion({ siteCode, rawApartmentId, actor }) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw apartmentNotFound();
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const removed = await client.query(`DELETE FROM finance_reminder_exclusions WHERE site_code = $1 AND apartment_id = $2`, [siteCode, apartmentId]);
    if (removed.rowCount > 0) {
      await recordFinanceAudit(client, actor, 'finance.reminder.exclusion_removed', siteCode, apartmentId, {});
    }
    return { apartment_id: apartmentId, excluded: false };
  });
}

void present;
void canonicalAddress;
