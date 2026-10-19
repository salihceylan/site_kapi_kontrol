// Firma ve Sözleşme Takibi: günlük hatırlatma işi (site yöneticilerine e-posta).
//
// Sözleşme: docs/PLATFORM_SOZLESMELER.md "Hatırlatmalar".
//  - Saatte bir tik; İstanbul saatiyle CONTRACT_REMINDER_HOUR (09:00) ve sonrasında çalışır. Süreçler arası TEK ÇALIŞAN: oturum düzeyi advisory kilit
//    (iki-int anahtar, sınıf "CNTR"; kullanıcı girdili hashtext anahtarlarından ayrı uzay). Kilit başka süreçteyse tik ATLANIR.
//  - Yalnız `contracts` modülü AÇIK sitelerde. Site başına günde EN ÇOK BİR e-posta: o gün (İstanbul) gönderilmiş hatırlatması olan site ertesi güne kalır.
//  - Kalemler: (a) `bitis`: end_date − remind_before_days <= bugün <= end_date; (b) `fesih_bildirim`: otomatik yenilenen sözleşmede
//    notice_deadline − 7 <= bugün <= notice_deadline (notice_deadline = end_date − notice_days). Yalnız `aktif` (feshedilmemiş) sözleşmeler.
//    İdempotans: contract_reminders UNIQUE (contract_id, kind, due_date); due_date = bitiş tarihi ya da fesih bildirimi son günü. Aynı hatırlatma iki kez gitmez;
//    tarih değişirse yeni hatırlatma doğar.
//  - Akış: kalemler satır olarak "talep edilir" (claimed_at = şimdi, sent_at NULL) -> COMMIT -> e-postalar alıcı başına AYRI gönderilir (yöneticiler birbirinin
//    adresini görmez); İLK başarılı gönderimden HEMEN sonra sent_at yazılır (süreç o anda ölse bile sonraki tik yeniden göndermez), tur sonunda recipients
//    yazılır. Hiçbiri gitmezse talep satırları silinir (sonraki tikte yeniden denenir).
//  - Yarıda kalan tur (süreç ölümü: gönderim ile sent_at yazımı arası): o günün gönderilmemiş talebi (claimed_at bugün) "gönderilmiş olabilir" sayılır, site o
//    gün yeniden e-posta ALMAZ; önceki günlerden kalan gönderilmemiş talepler tur başında silinir ve kalem ertesi gün yeniden denenir (en çok günde bir e-posta).
//  - KİLİT SIRASI: contract_reminders'a her yazma (talep, sent_at, recipients, silme) site başına kısa bir işlemdir ve İLK ifadesi
//    `SELECT 1 FROM sites ... FOR KEY SHARE`dir (diğer tüm yazıcılarla aynı sıra; site silme ile 40P01 olmaz). Site o arada silinmişse atlanır.
//  - Alıcılar: sitenin yöneticileri (site_manager_sites + etkin SITE_OWNER / SITE_ADMIN üyeliği); hesap etkin, silinmemiş, e-postası DOĞRULANMIŞ ve
//    dahili (uygulama içi) adres değil. Alıcı yoksa site atlanır (talep yazılmaz).
//  - İçerik: site adı, firma adı, sözleşme başlığı, bitiş tarihi / fesih bildirimi son günü. TUTAR YOK. Günlüğe yalnız sayılar yazılır (ad / adres yok).
//  - SMTP yapılandırılmamışsa iş hiç başlamaz (startContractReminders null döner); CONTRACT_REMINDERS_DISABLED=1 ya da ANNOUNCEMENT_SCHEDULER_DISABLED=1 ile kapalı.

import { pool } from '../db.js';
import { escapeHtml, isSmtpConfigured, sendPreparedEmail, singleLine } from '../mailer.js';
import { getModuleDefinition, MODULE_STATUS_AVAILABLE } from './catalog.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import { CONTRACTS_MODULE, NOTICE_REMINDER_LEAD_DAYS, istanbulToday, trDate } from './contracts_common.js';
import { diffDays, istanbulParts, istanbulToUtc } from './reservation_time.js';

/** "CNTR" (0x434E5452): süreçler arası tek çalışan için oturum advisory kilidinin birinci anahtarı; ikincisi iş numarası. */
export const CONTRACTS_LOCK_CLASS = 0x434e5452;
export const CONTRACTS_LOCK_JOBS = Object.freeze({ reminders: 1 });

export const CONTRACT_REMINDER_INTERVAL_MS = 60 * 60 * 1000;
export const CONTRACT_REMINDER_FIRST_DELAY_MS = 2 * 60 * 1000;
/** Gönderim saati (İstanbul): bu saatten önceki tikler bir şey göndermez. */
export const CONTRACT_REMINDER_HOUR = 9;
/** Bir e-postada listelenen en çok kalem; fazlası "ve N kalem daha" ile belirtilir (hepsi gönderilmiş sayılır). */
export const MAX_ITEMS_PER_EMAIL = 50;

/** Test / QA kancaları. */
export const contractReminderHooks = {
  now: () => new Date(),
  send: (message) => sendPreparedEmail(message),
  smtpConfigured: () => isSmtpConfigured(),
};

const RECIPIENT_PATTERN = /^[^\s@,;<>"()]+@[^\s@,;<>"()]+\.[^\s@,;<>"()]+$/;

// ---------------------------------------------------------------------------
// E-posta içeriği (SAF)
// ---------------------------------------------------------------------------

function dayPhrase(days) {
  if (days <= 0) return 'bugün';
  if (days === 1) return 'yarın';
  return `${days} gün sonra`;
}

/**
 * @param {{ to: string, siteName: string, today: string, items: Array<{ kind: 'bitis'|'fesih_bildirim', vendorName: string, title: string,
 *           endDate: string, dueDate: string }>, extraCount?: number }} input
 * @returns {{ to: string, subject: string, text: string, html: string }}
 */
export function buildContractReminderEmail({ to, siteName, today, items, extraCount = 0 }) {
  const recipient = String(to ?? '').trim();
  if (recipient.length > 254 || !RECIPIENT_PATTERN.test(recipient)) {
    const error = new Error('Gecersiz alici adresi.');
    error.code = 'INVALID_RECIPIENT';
    throw error;
  }
  const site = singleLine(siteName, 120) || 'Site';
  const subject = singleLine(`[${site}] Sözleşme hatırlatması`);
  const line = (item) => {
    const firm = singleLine(item.vendorName, 120);
    const title = singleLine(item.title, 160);
    const left = diffDays(today, item.dueDate);
    if (item.kind === 'fesih_bildirim') {
      return `${firm} - ${title}: fesih bildirimi için son gün ${trDate(item.dueDate)} (${dayPhrase(left)}); sözleşme ${trDate(item.endDate)} tarihinde kendiliğinden yenilenir.`;
    }
    return `${firm} - ${title}: sözleşme ${trDate(item.endDate)} tarihinde sona eriyor (${dayPhrase(left)}).`;
  };
  const ending = items.filter((item) => item.kind === 'bitis').map(line);
  const notice = items.filter((item) => item.kind === 'fesih_bildirim').map(line);
  const intro = `${site} için takip ettiğiniz sözleşmelerde yaklaşan tarihler var.`;
  const sections = [];
  if (notice.length > 0) sections.push(['Fesih bildirimi süresi dolmak üzere (otomatik yenilenen sözleşmeler)', notice]);
  if (ending.length > 0) sections.push(['Bitiş tarihi yaklaşan sözleşmeler', ending]);
  const extra = Math.max(0, Math.floor(Number(extraCount) || 0));
  const extraText = extra > 0 ? `Listede gösterilmeyen ${extra} hatırlatma daha var; tamamını uygulamadaki Sözleşmeler ekranında görebilirsiniz.` : '';
  const closing = 'Ayrıntılar ve sözleşmeyi yenileme ya da feshetme işlemleri için uygulamadaki Firma ve Sözleşme Takibi ekranını kullanabilirsiniz.';
  const footer = `Bu ileti ${site} için Firma ve Sözleşme Takibi modülü tarafından otomatik gönderildi ve yalnız site yöneticilerine iletilir. Her hatırlatma bir kez gönderilir.`;
  const text = [
    'Merhaba,',
    '',
    intro,
    ...sections.flatMap(([heading, lines]) => ['', `${heading}:`, ...lines.map((entry) => `- ${entry}`)]),
    ...(extraText ? ['', extraText] : []),
    '',
    closing,
    '',
    '--',
    footer,
  ].join('\n');
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <p style="color: #374151; font-size: 15px; margin: 0 0 12px 0;">Merhaba,</p>
      <p style="color: #374151; font-size: 15px; line-height: 1.6; margin: 0 0 12px 0;">${escapeHtml(intro)}</p>
      ${sections
        .map(
          ([heading, lines]) => `
      <p style="color: #111827; font-size: 15px; font-weight: 700; margin: 16px 0 8px 0;">${escapeHtml(heading)}</p>
      <ul style="color: #374151; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0; padding-left: 20px;">
        ${lines.map((entry) => `<li>${escapeHtml(entry)}</li>`).join('\n        ')}
      </ul>`,
        )
        .join('')}
      ${extraText ? `<p style="color: #374151; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0;">${escapeHtml(extraText)}</p>` : ''}
      <p style="color: #374151; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0;">${escapeHtml(closing)}</p>
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">${escapeHtml(footer)}</p>
    </div>
  `;
  return { to: recipient, subject, text, html };
}

// ---------------------------------------------------------------------------
// Tek çalışan kilidi
// ---------------------------------------------------------------------------

/** Oturum düzeyi advisory kilit: kilidi tutan bağlantı havuzdan ayrı tutulur; iş bitince açılıp iade edilir (açılamazsa bağlantı yok edilir). */
async function acquireRunnerLock(db) {
  const client = await db.connect();
  const onError = () => {};
  client.on('error', onError);
  const result = await client
    .query('SELECT pg_try_advisory_lock($1::int, $2::int) AS locked', [CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS.reminders])
    .catch((error) => {
      client.release(true);
      throw error;
    });
  if (result.rows?.[0]?.locked !== true) {
    client.off('error', onError);
    client.release();
    return null;
  }
  return {
    client,
    async release() {
      try {
        await client.query('SELECT pg_advisory_unlock($1::int, $2::int)', [CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS.reminders]);
        client.off('error', onError);
        client.release();
      } catch (_error) {
        client.release(true);
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Tur
// ---------------------------------------------------------------------------

/**
 * Site başına kısa yazma işlemi. İLK ifade `sites FOR KEY SHARE`: diğer tüm yazıcılarla aynı kilit sırası (site silme önce site satırını kilitler, sonra
 * hatırlatmaları CASCADE siler; biz de önce siteyi alırız -> döngü yok, 40P01 yok). Site yoksa (silinmiş) `work` çalışmaz ve null döner.
 */
async function withSiteTransaction(client, siteCode, work) {
  await client.query('BEGIN');
  try {
    const site = await client.query(`SELECT 1 FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!site.rows?.[0]) {
      await client.query('ROLLBACK');
      return null;
    }
    const result = await work();
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

/**
 * Önceki GÜNLERDEN kalan gönderilmemiş talepler (yarıda kalan tur): site başına kendi işleminde silinir, kalem bu turda yeniden denenir.
 * Bugünün gönderilmemiş talepleri SİLİNMEZ: gönderim ile sent_at yazımı arasında süreç ölmüş olabilir; site o gün yeniden e-posta almaz.
 */
async function releaseStaleClaims(client, dayStart) {
  const stale = await client.query(
    `SELECT DISTINCT site_code FROM contract_reminders WHERE sent_at IS NULL AND claimed_at < $1::TIMESTAMPTZ ORDER BY site_code`,
    [dayStart.toISOString()],
  );
  for (const row of stale.rows ?? []) {
    await withSiteTransaction(client, Number(row.site_code), () =>
      client.query(`DELETE FROM contract_reminders WHERE site_code = $1 AND sent_at IS NULL AND claimed_at < $2::TIMESTAMPTZ`, [Number(row.site_code), dayStart.toISOString()]),
    );
  }
}

/** Modülü açık, bugün (İstanbul) hatırlatma e-postası almamış ve bugün yarıda kalmış talebi olmayan siteler. */
async function candidateSites(db, dayStart) {
  const result = await db.query(
    `
      SELECT s.site_code, s.name
      FROM site_modules sm
      INNER JOIN sites s ON s.site_code = sm.site_code
      WHERE sm.module_code = $1 AND sm.enabled = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM contract_reminders r WHERE r.site_code = s.site_code AND COALESCE(r.sent_at, r.claimed_at) >= $2::TIMESTAMPTZ
        )
      ORDER BY s.site_code
    `,
    [CONTRACTS_MODULE, dayStart.toISOString()],
  );
  return result.rows ?? [];
}

/** Sitenin bugün vadesi gelen, henüz hatırlatılmamış kalemleri (due_date, id sırasıyla). */
async function dueItems(db, siteCode, day) {
  const result = await db.query(
    `
      SELECT c.id AS contract_id, c.title, v.name AS vendor_name, k.kind,
             to_char(k.due_date, 'YYYY-MM-DD') AS due_date, to_char(c.end_date, 'YYYY-MM-DD') AS end_date
      FROM site_contracts c
      INNER JOIN contract_vendors v ON v.id = c.vendor_id
      CROSS JOIN LATERAL (VALUES ('bitis'::TEXT, c.end_date), ('fesih_bildirim'::TEXT, c.end_date - c.notice_days)) AS k(kind, due_date)
      WHERE c.site_code = $1 AND c.status = 'aktif' AND c.end_date IS NOT NULL
        AND (
          (k.kind = 'bitis' AND c.end_date - c.remind_before_days <= $2::DATE AND $2::DATE <= c.end_date)
          OR (k.kind = 'fesih_bildirim' AND c.auto_renew = TRUE AND k.due_date - $3::INTEGER <= $2::DATE AND $2::DATE <= k.due_date)
        )
        AND NOT EXISTS (
          SELECT 1 FROM contract_reminders r WHERE r.contract_id = c.id AND r.kind = k.kind AND r.due_date = k.due_date
        )
      ORDER BY k.due_date, c.id, k.kind
    `,
    [siteCode, day, NOTICE_REMINDER_LEAD_DAYS],
  );
  return result.rows ?? [];
}

/** Sitenin yöneticilerinin gönderilebilir adresleri (etkin, silinmemiş, doğrulanmış, dahili olmayan; tekil). */
async function managerRecipients(db, siteCode) {
  const result = await db.query(
    `
      SELECT DISTINCT lower(u.email) AS email
      FROM users u
      WHERE u.user_code IN (
          SELECT manager_user_code FROM site_manager_sites WHERE site_code = $1
          UNION
          SELECT user_code FROM site_memberships WHERE site_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
        )
        AND u.is_active = TRUE AND u.deleted_at IS NULL AND u.email_verified = TRUE
        AND u.email IS NOT NULL AND u.email <> '' AND lower(u.email) NOT LIKE '%' || $2
      ORDER BY 1
    `,
    [siteCode, INTERNAL_EMAIL_SUFFIX],
  );
  return (result.rows ?? []).map((row) => row.email).filter((email) => RECIPIENT_PATTERN.test(email) && email.length <= 254);
}

/**
 * Kalemleri talep eder (claimed_at = tur saati, sent_at NULL); yalnız gerçekten eklenen (daha önce gönderilmemiş) satırları döndürür. withSiteTransaction İÇİNDE
 * çağrılır. Zaman damgaları DB NOW() yerine turun saatinden (`now`) yazılır: "bugün" kuralları (günde tek e-posta, eski talep) aynı saate göre işler.
 */
async function claimItems(db, siteCode, items, now) {
  const result = await db.query(
    `
      INSERT INTO contract_reminders (contract_id, site_code, kind, due_date, claimed_at)
      SELECT x.contract_id, $1, x.kind, x.due_date, $5::TIMESTAMPTZ
      FROM unnest($2::BIGINT[], $3::TEXT[], $4::DATE[]) AS x(contract_id, kind, due_date)
      ON CONFLICT (contract_id, kind, due_date) DO NOTHING
      RETURNING id, contract_id, kind, to_char(due_date, 'YYYY-MM-DD') AS due_date
    `,
    [siteCode, items.map((item) => item.contract_id), items.map((item) => item.kind), items.map((item) => item.due_date), now.toISOString()],
  );
  return result.rows ?? [];
}

const emptySummary = () => ({ skipped: null, sites: 0, emails: 0, failed_emails: 0, reminders: 0, errors: 0 });

/**
 * Tek hatırlatma turu. Hata fırlatmaz (sunucuyu düşürmez); özet döndürür. `now`: QA / test için saat.
 * @returns {Promise<{ skipped: string|null, sites: number, emails: number, failed_emails: number, reminders: number, errors: number }>}
 */
export async function runContractReminders({ now = contractReminderHooks.now(), db = pool, ignoreHour = false } = {}) {
  const summary = emptySummary();
  const definition = getModuleDefinition(CONTRACTS_MODULE);
  if (!definition || definition.status !== MODULE_STATUS_AVAILABLE) {
    summary.skipped = 'module_unavailable';
    return summary;
  }
  if (!contractReminderHooks.smtpConfigured()) {
    summary.skipped = 'smtp';
    return summary;
  }
  const parts = istanbulParts(now);
  if (!ignoreHour && parts.minuteOfDay < CONTRACT_REMINDER_HOUR * 60) {
    summary.skipped = 'hour';
    return summary;
  }
  const day = istanbulToday(now);
  let lock;
  try {
    lock = await acquireRunnerLock(db);
  } catch (error) {
    summary.errors += 1;
    // eslint-disable-next-line no-console
    console.error('[contracts] hatirlatma kilidi alinamadi:', error?.code || 'hata');
    return summary;
  }
  if (!lock) {
    summary.skipped = 'locked';
    return summary;
  }
  try {
    const client = lock.client;
    const dayStart = istanbulToUtc(day, 0);
    // Önceki günlerin yarıda kalan talepleri bu turda yeniden denenir; bugünküler o gün için "gönderilmiş olabilir" sayılır (candidateSites).
    await releaseStaleClaims(client, dayStart);
    const sites = await candidateSites(client, dayStart);
    for (const site of sites) {
      const siteCode = Number(site.site_code);
      try {
        const items = await dueItems(client, siteCode, day);
        if (items.length === 0) continue;
        const recipients = await managerRecipients(client, siteCode);
        if (recipients.length === 0) continue;
        const claimed = await withSiteTransaction(client, siteCode, () => claimItems(client, siteCode, items, now));
        // null: site o arada silindi; boş: kalemler başka yoldan işaretlenmiş
        if (!claimed || claimed.length === 0) continue;
        const claimedKeys = new Set(claimed.map((row) => `${row.contract_id}:${row.kind}:${row.due_date}`));
        const listed = items.filter((item) => claimedKeys.has(`${item.contract_id}:${item.kind}:${item.due_date}`));
        const shown = listed.slice(0, MAX_ITEMS_PER_EMAIL).map((item) => ({
          kind: item.kind,
          vendorName: item.vendor_name,
          title: item.title,
          endDate: item.end_date,
          dueDate: item.due_date,
        }));
        const ids = claimed.map((row) => Number(row.id));
        let sent = 0;
        let marked = false;
        let siteGone = false;
        for (const to of recipients) {
          try {
            await contractReminderHooks.send(buildContractReminderEmail({ to, siteName: site.name, today: day, items: shown, extraCount: listed.length - shown.length }));
            sent += 1;
          } catch (_error) {
            summary.failed_emails += 1;
            continue;
          }
          if (!marked) {
            // İLK başarılı gönderimden HEMEN sonra sent_at: süreç bundan sonra ölse bile sonraki tik bu kalemleri yeniden göndermez.
            const done = await withSiteTransaction(client, siteCode, () =>
              client.query(`UPDATE contract_reminders SET sent_at = $2::TIMESTAMPTZ WHERE id = ANY($1::BIGINT[]) AND sent_at IS NULL`, [ids, now.toISOString()]),
            );
            if (done === null) {
              siteGone = true; // site silindi (hatırlatmalar CASCADE gitti): kalan yöneticilere gönderilmez
              break;
            }
            marked = true;
          }
        }
        summary.emails += sent;
        if (siteGone) continue;
        if (sent > 0) {
          await withSiteTransaction(client, siteCode, () =>
            client.query(`UPDATE contract_reminders SET recipients = $2 WHERE id = ANY($1::BIGINT[])`, [ids, sent]),
          );
          summary.sites += 1;
          summary.reminders += ids.length;
        } else {
          // Hiçbir alıcıya gitmedi: talep geri alınır, sonraki tikte yeniden denenir.
          await withSiteTransaction(client, siteCode, () =>
            client.query(`DELETE FROM contract_reminders WHERE id = ANY($1::BIGINT[]) AND sent_at IS NULL`, [ids]),
          );
        }
      } catch (error) {
        summary.errors += 1;
        // eslint-disable-next-line no-console
        console.error('[contracts] site hatirlatma turu basarisiz:', error?.code || 'hata');
      }
    }
  } catch (error) {
    summary.errors += 1;
    // eslint-disable-next-line no-console
    console.error('[contracts] hatirlatma turu basarisiz:', error?.code || 'hata');
  } finally {
    await lock.release();
  }
  if (summary.emails > 0 || summary.failed_emails > 0) {
    // eslint-disable-next-line no-console
    console.log(`[contracts] hatirlatma: ${summary.sites} site, ${summary.emails} e-posta, ${summary.reminders} kalem, ${summary.failed_emails} basarisiz.`);
  }
  return summary;
}

// ---------------------------------------------------------------------------
// Zamanlayıcı
// ---------------------------------------------------------------------------

export function isContractRemindersDisabled(env = process.env) {
  const flag = (name) => ['1', 'true', 'yes'].includes(String(env[name] ?? '').trim().toLowerCase());
  return flag('CONTRACT_REMINDERS_DISABLED') || flag('ANNOUNCEMENT_SCHEDULER_DISABLED');
}

let intervalTimer = null;
let firstTimer = null;
let running = null;

/** Tek tur (süreç içinde üst üste binmez); hata fırlatmaz. */
export function runContractReminderTick(options) {
  if (!running) {
    running = runContractReminders(options)
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error('[contracts] hatirlatma tiki basarisiz:', error?.code || 'hata');
        return { ...emptySummary(), errors: 1 };
      })
      .finally(() => {
        running = null;
      });
  }
  return running;
}

/**
 * Saatlik zamanlayıcıyı başlatır (unref'li). Kapalıysa ya da SMTP yapılandırılmamışsa null döner (iş hiç çalışmaz).
 * @returns {{ stop: Function, intervalMs: number } | null}
 */
export function startContractReminders({ env = process.env, intervalMs = CONTRACT_REMINDER_INTERVAL_MS, firstDelayMs = CONTRACT_REMINDER_FIRST_DELAY_MS } = {}) {
  if (isContractRemindersDisabled(env) || intervalTimer) {
    return null;
  }
  if (!contractReminderHooks.smtpConfigured()) {
    // eslint-disable-next-line no-console
    console.log('[contracts] SMTP yapilandirilmamis: sozlesme hatirlatma e-postalari kapali.');
    return null;
  }
  intervalTimer = setInterval(() => void runContractReminderTick(), intervalMs);
  intervalTimer.unref?.();
  firstTimer = setTimeout(() => {
    firstTimer = null;
    void runContractReminderTick();
  }, Math.min(firstDelayMs, intervalMs));
  firstTimer.unref?.();
  return { stop: stopContractReminders, intervalMs };
}

export async function stopContractReminders() {
  if (intervalTimer) {
    clearInterval(intervalTimer);
    intervalTimer = null;
  }
  if (firstTimer) {
    clearTimeout(firstTimer);
    firstTimer = null;
  }
  if (running) {
    await running.catch(() => {});
  }
}
