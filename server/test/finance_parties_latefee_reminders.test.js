// İki hesap (İP-1A): gecikme tazminatı planı (daire, HESAP) satırları ve borç hatırlatmada alıcı = hesabın sahibi (KATI sahte DB).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties" (iki hesap iki satır; both dairede kiracı hesabı borcu kiracıya gider, malike gitmez).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { computeLateFeePlan } from '../src/modules/finance_late_fee.js';
import * as reminders from '../src/modules/finance_reminders.js';

const { computeReminderPlan } = reminders;

// adres özeti (hashEmail) için sır: test ortamı
process.env.JWT_SECRET ||= 'finance-parties-test-secret-0123456789abcdef';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const day = (iso) => Math.round(Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10))) / 86400000);

function strictDb(handlers) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      const sql = norm(text);
      calls.push({ sql, params });
      for (const [pattern, fn] of handlers) {
        if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params) : fn;
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
    },
  };
}

describe('İP-1A gecikme tazminatı: hesap başına satır', () => {
  const settings = { late_fee_rate_bp: 500, late_fee_method: 'daily_30', late_fee_grace_days: 0, settings_version: 3 };
  const ledgerRow = (id, account, amount, due) => ({
    id: String(id), apartment_id: '7', kind: 'charge', amount: String(amount), entry_day: day(due) - 5, due_day: day(due), late_fee: false, reverses_entry_id: null, account_party: account,
  });
  const db = (rows) =>
    strictDb([
      [/FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 ORDER BY a\.id/, () => ok([{ id: '7', unit_label: 'Daire 7', block_name: 'A Blok', block_sort: 1, apt_sort: 7, responsible_party: 'both', is_active: true }])],
      [/FROM ledger_entries l LEFT JOIN fee_definitions fd ON fd\.id = l\.definition_id WHERE l\.site_code = \$1 AND l\.entry_date <= \$2::DATE ORDER BY l\.apartment_id, l\.id/, () => ok(rows)],
    ]);

  it('aynı dairenin iki hesabı da gecikmişse İKİ satır; her satır kendi hesabının mahsubuyla hesaplanır ve hesabını taşır', async () => {
    const plan = await computeLateFeePlan(db([ledgerRow(1, 'owner', 1000000, '2026-08-05'), ledgerRow(2, 'tenant', 500000, '2026-08-05')]), 1, { period: '2026-09-01', settings, excluded: [] });
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.accountParty]), [[7, 'owner'], [7, 'tenant']]);
    // borç oranlı: ev sahibi hesabındaki iki katı borç iki katı tazminat
    assert.equal(plan.lines[0].amount, plan.lines[1].amount * 2n);
    assert.equal(plan.total, plan.lines[0].amount + plan.lines[1].amount);
  });

  it('bir hesabın ödemesi diğer hesabın tazminat tabanını düşürmez; hesap özete girer', async () => {
    const pay = { id: '3', apartment_id: '7', kind: 'payment', amount: '-1000000', entry_day: day('2026-08-01'), due_day: null, late_fee: false, reverses_entry_id: null, account_party: 'tenant' };
    const plan = await computeLateFeePlan(db([ledgerRow(1, 'owner', 1000000, '2026-08-05'), pay]), 1, { period: '2026-09-01', settings, excluded: [] });
    assert.deepEqual(plan.lines.map((l) => l.accountParty), ['owner']);
    const sameAmountTenant = await computeLateFeePlan(db([ledgerRow(1, 'tenant', 1000000, '2026-08-05')]), 1, { period: '2026-09-01', settings, excluded: [] });
    assert.equal(sameAmountTenant.lines[0].amount, plan.lines[0].amount);
    assert.notEqual(sameAmountTenant.hash, plan.hash, 'hesap farklı -> özet farklı');
  });

  it('muaf daire iki hesabın tazminatını da atlar (waived hesap başına)', async () => {
    const plan = await computeLateFeePlan(db([ledgerRow(1, 'owner', 1000000, '2026-08-05'), ledgerRow(2, 'tenant', 500000, '2026-08-05')]), 1, { period: '2026-09-01', settings, excluded: [7] });
    assert.equal(plan.lines.length, 0);
    assert.deepEqual(plan.waived.map((w) => [w.apartment_id, w.account_party]), [[7, 'owner'], [7, 'tenant']]);
  });
});

describe('İP-1A borç hatırlatma: alıcı = hesabın sahibi', () => {
  const settings = { reminder_min_overdue_minor: 5000, reminder_min_days_overdue: 5, reminder_min_interval_days: 14, reminder_max_consecutive: 3 };
  const candidate = (account, overdue) => ({
    id: '7', account_party: account, unit_label: 'Daire 7', block_name: 'A Blok', block_sort: 1, apt_sort: 7, overdue: String(overdue), oldest_due: '2026-09-01',
    last_day: null, consecutive: 0, excluded: false,
  });
  // Varsayılan daire: borç sorumlusu "malik ve kiracı" (both), güncel kiracı var.
  const person = (id, relation, email, extra = {}) => ({
    apartment_id: '7', person_id: String(id), relation, has_tenant: true, responsible_party: 'both', has_responsible_person: false, account_kind: 'registered', verified: true,
    pref: true, email, ...extra,
  });
  const db = (candidates, recipients) =>
    strictDb([
      [/WITH items AS/, () => ok(candidates)],
      [/INNER JOIN apartment_residencies rr ON rr\.person_id = sp\.id AND rr\.is_current = TRUE/, () => ok(recipients)],
      [/FROM announcement_email_suppressions WHERE email_hash = ANY/, () => ok()],
      [/FROM finance_reminder_items WHERE email_hash = ANY/, () => ok()],
      [/SELECT COUNT\(\*\)::INTEGER AS used FROM finance_reminder_items/, () => ok([{ used: 0 }])],
    ]);
  const NOW = new Date('2026-10-21T09:00:00Z');

  it('both dairede borç KİRACI hesabındaysa ileti kiracıya gider; malik (salt okunur görür) ve ilişkisi belirtilmemiş sakin ilgili hesabın sahibiyse alır', async () => {
    const plan = await computeReminderPlan(
      db([candidate('tenant', 80000)], [person(1, 'owner', 'malik@ornek.test'), person(2, 'tenant', 'kiraci@ornek.test'), person(3, 'family_member', 'aile@ornek.test'), person(4, 'resident', 'sakin@ornek.test')]),
      1,
      { settings, tone: 'friendly', now: NOW },
    );
    assert.deepEqual(plan.pendingPersons.map((p) => p.personId), [2, 4]);
    assert.equal(plan.coveredApartments.length, 1);
    assert.equal(plan.coveredAccounts.length, 1);
    assert.equal(plan.totalOverdue, 80000n);
  });

  it('iki hesap da borçluysa iki sahibe ayrı ileti; daire sayısı 1, hesap sayısı 2, toplam iki hesabın gecikmişi', async () => {
    const plan = await computeReminderPlan(
      db([candidate('owner', 120000), candidate('tenant', 80000)], [person(1, 'owner', 'malik@ornek.test'), person(2, 'tenant', 'kiraci@ornek.test')]),
      1,
      { settings, tone: 'friendly', now: NOW },
    );
    assert.deepEqual(plan.pendingPersons.map((p) => [p.personId, p.accounts.get(7)]), [[1, 'owner'], [2, 'tenant']]);
    assert.equal(plan.coveredApartments.length, 1);
    assert.equal(plan.coveredAccounts.length, 2);
    assert.equal(plan.totalOverdue, 200000n);
    // sahibi olmayan hesap "alıcı yok" sayılır
    const orphan = await computeReminderPlan(db([candidate('owner', 120000)], [person(2, 'tenant', 'kiraci@ornek.test')]), 1, { settings, tone: 'friendly', now: NOW });
    assert.equal(orphan.pendingPersons.length, 0);
    assert.equal(orphan.excluded.no_recipient, 1);
  });

  it('inceleme (F2.05 korunur): sorumlu malik / kiracı ve o tarafın güncel kişisi varken belirtilmemiş sakine hatırlatma GİTMEZ; kişi yoksa (yedek) gider', async () => {
    // sorumlu kiracı, güncel kiracı var: borç kiracı hesabında -> yalnız kiracı (sakin hane üyesi olabilir)
    const tenantSide = { responsible_party: 'tenant', has_responsible_person: true };
    const plan = await computeReminderPlan(
      db([candidate('tenant', 80000)], [person(2, 'tenant', 'kiraci@ornek.test', tenantSide), person(4, 'resident', 'sakin@ornek.test', tenantSide)]),
      1,
      { settings, tone: 'friendly', now: NOW },
    );
    assert.deepEqual(plan.pendingPersons.map((p) => p.personId), [2]);
    // sorumlu malik, güncel malik var, kiracı yok: borç ev sahibi hesabında -> yalnız malik
    const ownerSide = { responsible_party: 'owner', has_responsible_person: true, has_tenant: false };
    const ownerPlan = await computeReminderPlan(
      db([candidate('owner', 90000)], [person(1, 'owner', 'malik@ornek.test', ownerSide), person(4, 'resident', 'sakin@ornek.test', ownerSide)]),
      1,
      { settings, tone: 'friendly', now: NOW },
    );
    assert.deepEqual(ownerPlan.pendingPersons.map((p) => p.personId), [1]);
    // sorumlu malik ama güncel malik YOK (yedek): belirtilmemiş sakin ev sahibi hesabının hatırlatmasını alır
    const fallback = { responsible_party: 'owner', has_responsible_person: false, has_tenant: false };
    const fallbackPlan = await computeReminderPlan(db([candidate('owner', 90000)], [person(4, 'resident', 'sakin@ornek.test', fallback)]), 1, { settings, tone: 'friendly', now: NOW });
    assert.deepEqual(fallbackPlan.pendingPersons.map((p) => p.personId), [4]);
  });

  it('ikinci inceleme: elden takip HESAP başınadır; önizleme öğeleri hesabı taşır (aynı daire iki öğe, ayırt edilebilir); eski etiket alanı aynen kalır', async () => {
    const atLimit = (account) => ({ ...candidate(account, 90000), consecutive: 3 });
    const plan = await computeReminderPlan(db([atLimit('owner'), atLimit('tenant')], [person(1, 'owner', 'malik@ornek.test'), person(2, 'tenant', 'kiraci@ornek.test')]), 1, {
      settings,
      tone: 'friendly',
      now: NOW,
    });
    assert.equal(typeof reminders.reminderPreviewBody, 'function', 'önizleme gövdesi dışa verilir (sınanabilir)');
    const body = reminders.reminderPreviewBody(plan, { smtp: true, blockers: [] });
    assert.equal(body.hand_follow_up_count, 2, 'hesap başına (daire 1)');
    assert.equal(body.excluded.consecutive, 2);
    assert.deepEqual(body.hand_follow_up_apartments, ['A Blok - Daire 7', 'A Blok - Daire 7'], 'eski istemci alanı değişmedi');
    assert.deepEqual(body.hand_follow_up_accounts, [
      { label: 'A Blok - Daire 7', account_party: 'owner' },
      { label: 'A Blok - Daire 7', account_party: 'tenant' },
    ]);
    assert.equal(body.person_count, 0);
  });
});
