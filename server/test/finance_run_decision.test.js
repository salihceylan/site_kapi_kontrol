// Demirbaş / Fon tahakkukunun dayanağı (K2, P1-2): Karar Defteri modülü AÇIK sitede karar seçimi, KAPALI sitede serbest metin gerekçe ZORUNLU.
// DB'siz, KATI sahte veritabanı (bilinmeyen SQL hata verir). Gerçek PostgreSQL: scripts/qa_finance_run_decision_section.mjs (qa_platform_pg.mjs "run_decision").
//  - Saf kural (decideRunDecision) ve gövde ayrıştırma (parseRunDecisionInput) matrisi.
//  - postCharge / postDefinition: modül açık + kararsız -> 400 DECISION_REQUIRED; kapalı + gerekçesiz -> 400 DECISION_REASON_REQUIRED; hiçbir şey yazılmaz.
//  - Başarı yolu: karar kimliği / gerekçe fee_runs INSERT'ine gider; yanıt run.decision karar numarasını taşır; denetim kaydında gerekçe METNİ yoktur.
//  - İdempotans: aynı anahtar + farklı karar = 409 IDEMPOTENCY_CONFLICT; aynı istek tekrarı dayanağıyla birlikte aynı kaydı döndürür.
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { postCharge, postDefinition, previewCharge, previewDefinition } = await import('../src/modules/finance_service.js');
const { chargeRequestFingerprint, parseChargeInput, parseRunDecisionInput, postRequestFingerprint } = await import('../src/modules/finance_common.js');
const { decideRunDecision, decisionAuditDetails, describeDecisionRequirement, resolveRunDecision } = await import('../src/modules/finance_run_decision.js');

const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const NOW = new Date('2026-10-28T09:00:00Z');
const MANAGER = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const codeOf = (status, code) => (error) => error.statusCode === status && error.code === code;

// --------------------------------------------------------------------------------------------------------------------------------------------------
// Saf kurallar
// --------------------------------------------------------------------------------------------------------------------------------------------------

describe('decideRunDecision: dayanak kuralı matrisi', () => {
  const rule = (fund, moduleEnabled, decisionId, decisionReason) => decideRunDecision({ fund, moduleEnabled, decisionId, decisionReason });

  it('Fon (capital) + modül AÇIK: karar zorunlu; yalnız gerekçe yetmez (400 DECISION_REQUIRED)', () => {
    assert.throws(() => rule('capital', true, null, null), codeOf(400, 'DECISION_REQUIRED'));
    assert.throws(() => rule('capital', true, null, 'Kurul kararı gereği'), codeOf(400, 'DECISION_REQUIRED'));
    assert.deepEqual(rule('capital', true, 5, null), { kind: 'decision' });
    assert.deepEqual(rule('capital', true, 5, 'Ek not'), { kind: 'decision' });
  });

  it('Fon (capital) + modül KAPALI: gerekçe zorunlu (400 DECISION_REASON_REQUIRED); karar kimliği gönderilirse 400 DECISION_MODULE_OFF (sessizce yok sayılmaz)', () => {
    assert.throws(() => rule('capital', false, null, null), codeOf(400, 'DECISION_REASON_REQUIRED'));
    assert.throws(() => rule('capital', false, 5, null), codeOf(400, 'DECISION_MODULE_OFF'));
    assert.throws(() => rule('capital', false, 5, 'Gerekçe var'), codeOf(400, 'DECISION_MODULE_OFF'));
    assert.deepEqual(rule('capital', false, null, 'Genel kurul kararı, 12 Ekim'), { kind: 'reason' });
  });

  it('işletme (operating): dayanak ZORUNLU DEĞİL; verilirse Fon ile AYNI kurallarla doğrulanır', () => {
    for (const moduleEnabled of [true, false]) {
      assert.deepEqual(rule('operating', moduleEnabled, null, null), { kind: 'none' });
    }
    assert.deepEqual(rule('operating', true, 5, null), { kind: 'decision' });
    assert.deepEqual(rule('operating', true, null, 'Not'), { kind: 'reason' });
    assert.deepEqual(rule('operating', false, null, 'Not'), { kind: 'reason' });
    assert.throws(() => rule('operating', false, 5, null), codeOf(400, 'DECISION_MODULE_OFF'));
  });
});

describe('parseRunDecisionInput: gövde biçimi', () => {
  it('yoksa null; sayı ya da rakam metni karar kimliği; boş metin "yok"', () => {
    assert.deepEqual(parseRunDecisionInput({}), { decisionId: null, decisionReason: null });
    assert.deepEqual(parseRunDecisionInput({ decision_id: null, decision_reason: null }), { decisionId: null, decisionReason: null });
    assert.deepEqual(parseRunDecisionInput({ decision_id: 12 }), { decisionId: 12, decisionReason: null });
    assert.deepEqual(parseRunDecisionInput({ decision_id: '12' }), { decisionId: 12, decisionReason: null });
    assert.deepEqual(parseRunDecisionInput({ decision_id: '', decision_reason: '   ' }), { decisionId: null, decisionReason: null });
  });

  it('geçersiz karar kimliği ve gerekçe 400 INVALID_BODY; gerekçe temizlenir (boşluklar tekil, kontrol karakterleri atılır), 3..300 karakter', () => {
    for (const bad of [0, -1, 1.5, 'abc', true, {}, [1]]) {
      assert.throws(() => parseRunDecisionInput({ decision_id: bad }), codeOf(400, 'INVALID_BODY'), JSON.stringify(bad));
    }
    assert.throws(() => parseRunDecisionInput({ decision_reason: 'ab' }), codeOf(400, 'INVALID_BODY'));
    assert.throws(() => parseRunDecisionInput({ decision_reason: 5 }), codeOf(400, 'INVALID_BODY'));
    assert.throws(() => parseRunDecisionInput({ decision_reason: 'x'.repeat(301) }), codeOf(400, 'INVALID_BODY'));
    assert.equal(parseRunDecisionInput({ decision_reason: 'x'.repeat(300) }).decisionReason.length, 300);
    assert.equal(parseRunDecisionInput({ decision_reason: '  Asansör \n\t yenileme   kararı ' }).decisionReason, 'Asansör yenileme kararı');
  });

  it('parseChargeInput dayanağı taşır; dayanaksız istek parmak izi ESKİSİYLE aynı, dayanaklı istek farklıdır (aynı anahtar + farklı karar = çakışma)', () => {
    const body = { name: 'Asansör', distribution: 'equal', amount_minor: 1000, target: { type: 'site' } };
    const plain = parseChargeInput(body, { requireExpected: false, now: NOW });
    assert.deepEqual([plain.decisionId, plain.decisionReason], [null, null]);
    const withDecision = parseChargeInput({ ...body, decision_id: 7 }, { requireExpected: false, now: NOW });
    const withOther = parseChargeInput({ ...body, decision_id: 8 }, { requireExpected: false, now: NOW });
    const withReason = parseChargeInput({ ...body, decision_reason: 'Kurul kararı' }, { requireExpected: false, now: NOW });
    const fingerprints = [plain, withDecision, withOther, withReason].map((input) => chargeRequestFingerprint(input));
    assert.equal(new Set(fingerprints).size, 4);
    assert.equal(chargeRequestFingerprint({ ...plain, decisionId: null, decisionReason: null }), fingerprints[0]);
    const post = postRequestFingerprint({ definitionId: 5, period: '2026-10-01', dueDate: null, skipMissing: false });
    assert.equal(postRequestFingerprint({ definitionId: 5, period: '2026-10-01', dueDate: null, skipMissing: false, decisionId: null, decisionReason: null }), post);
    assert.notEqual(postRequestFingerprint({ definitionId: 5, period: '2026-10-01', dueDate: null, skipMissing: false, decisionId: 7 }), post);
    assert.notEqual(postRequestFingerprint({ definitionId: 5, period: '2026-10-01', dueDate: null, skipMissing: false, decisionReason: 'Gerekçe' }), post);
  });

  it('denetim ayrıntısı yalnız karar kimliği ve "gerekçe verildi" bayrağını taşır; gerekçe METNİ asla', () => {
    assert.deepEqual(decisionAuditDetails({ decisionId: 7, decisionReason: 'GİZLİ METİN' }), { decision_id: 7, decision_reason_given: true });
    assert.deepEqual(decisionAuditDetails({ decisionId: null, decisionReason: 'GİZLİ METİN' }), { decision_reason_given: true });
    assert.deepEqual(decisionAuditDetails({ decisionId: null, decisionReason: null }), {});
    assert.equal(JSON.stringify(decisionAuditDetails({ decisionId: null, decisionReason: 'GİZLİ METİN' })).includes('GİZLİ'), false);
  });
});

// --------------------------------------------------------------------------------------------------------------------------------------------------
// Sahte veritabanı
// --------------------------------------------------------------------------------------------------------------------------------------------------

const apt = (id, responsible = 'owner') => ({
  id: String(id), unit_label: `Daire ${id}`, block_name: 'A Blok', block_sort: 1, apt_sort: id, responsible_party: responsible, category: null,
  gross_x100: null, net_x100: null, land_share_numerator: null, land_share_denominator: null, has_tenant: false,
});

const DECISIONS = {
  // kimlik -> board_decisions satırı (site 1)
  77: { id: '77', year: 2026, decision_no: 4, title: 'Asansör yenileme', visibility: 'sakinler', status: 'kesin', site_code: SITE },
  78: { id: '78', year: 2026, decision_no: null, title: 'Taslak karar', visibility: 'yonetim', status: 'taslak', site_code: SITE },
  90: { id: '90', year: 2026, decision_no: 1, title: 'Başka sitenin kararı', visibility: 'yonetim', status: 'kesin', site_code: OTHER_SITE },
};

let db;
let originalQuery;
let originalConnect;

function install({ decisionModuleEnabled = true, existingRun = null, definition = null } = {}) {
  db = {
    log: [],
    decisionModuleEnabled,
    existingRun,
    definition,
    runInsert: null,
    definitionInsert: null,
    ledgerInsert: null,
    auditDetails: [],
    nextRunId: 501,
  };
  const handlers = [
    [/^(BEGIN|COMMIT|ROLLBACK)$/, () => ok()],
    [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
    [/pg_advisory_xact_lock/, () => ok()],
    [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: SITE }])],
    [
      /^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/,
      (_sql, p) => ok([{ enabled: p[1] === 'decision_book' ? db.decisionModuleEnabled : true }]),
    ],
    [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
    // idempotans: aynı anahtarla yazılmış çalıştırma
    [/FROM fee_runs r INNER JOIN fee_definitions d ON d\.id = r\.definition_id LEFT JOIN board_decisions bd/, () => ok(db.existingRun ? [db.existingRun] : [])],
    [/^SELECT 1 FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE LIMIT 1$/, () => ok()],
    [/FROM fee_runs WHERE site_code = \$1 AND natural_key = \$2/, () => ok()],
    [/^SELECT 1 FROM fee_runs WHERE definition_id = \$1/, () => ok()],
    [
      /^SELECT id, year, decision_no, title, visibility, status FROM board_decisions WHERE site_code = \$1 AND id = \$2 FOR KEY SHARE$/,
      (_s, p) => {
        const row = DECISIONS[Number(p[1])];
        return ok(row && row.site_code === Number(p[0]) ? [row] : []);
      },
    ],
    [/FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.is_active = TRUE/, () => ok([apt(1), apt(2), apt(3)])],
    [
      /^INSERT INTO fee_definitions \(/,
      (_s, p) => {
        db.definitionInsert = p;
        return ok([{ id: '31' }]);
      },
    ],
    [
      /^INSERT INTO fee_runs \(/,
      (_s, p) => {
        db.runInsert = p;
        return ok([
          { id: String(db.nextRunId), definition_id: String(p[1]), period: p[2], total_minor: p[3], apartment_count: p[4], skipped_count: p[5], posted_at: new Date('2026-10-28T09:00:00Z') },
        ]);
      },
    ],
    [
      /^INSERT INTO ledger_entries \(/,
      (_s, p) => {
        db.ledgerInsert = p;
        return ok([], 3);
      },
    ],
    [
      /^INSERT INTO audit_log/,
      (_s, p) => {
        db.auditDetails.push(JSON.parse(p[7]));
        return ok();
      },
    ],
    [
      /FROM fee_definitions d LEFT JOIN users u ON u\.user_code = d\.created_by WHERE d\.id = \$1 AND d\.site_code = \$2/,
      (_s, p) =>
        ok([
          db.definition ?? {
            id: String(p[0]), name: 'Asansör yenileme', kind: 'one_time', distribution: 'fixed', area_basis: null, amount_minor: '1000', category_amounts: null, due_day: null,
            start_period: '2026-10-01', end_period: null, target_type: 'site', target_block_ids: [], target_apartment_ids: [], is_active: true,
            created_at: new Date('2026-10-28T09:00:00Z'), updated_at: new Date('2026-10-28T09:00:00Z'), charge_party: 'owner', created_by_name: 'Ayşe Yönetici', has_runs: false, last_posted_period: null,
          },
        ]),
    ],
  ];
  const query = async (text, params = []) => {
    const sql = norm(text);
    db.log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 220)}`);
  };
  originalQuery = pool.query;
  originalConnect = pool.connect;
  pool.query = query;
  pool.connect = async () => ({ query, release() {} });
  return query;
}

const wrote = () => db.log.filter((entry) => /^INSERT INTO (fee_definitions|fee_runs|ledger_entries)/.test(entry.sql));

const chargeBody = (extra = {}) => ({ name: 'Asansör yenileme', distribution: 'fixed', amount_minor: 1000, target: { type: 'site' }, ...extra });

async function confirmBody(extra = {}) {
  const body = chargeBody(extra);
  const preview = await previewCharge({ siteCode: SITE, body, now: NOW }, pool);
  return {
    ...body,
    expected_total_minor: preview.total_minor,
    expected_apartment_count: preview.apartment_count,
    expected_hash: preview.preview_hash,
    idempotency_key: 'ek-borc-anahtar-1',
  };
}

// --------------------------------------------------------------------------------------------------------------------------------------------------
// Ek borç (postCharge)
// --------------------------------------------------------------------------------------------------------------------------------------------------

describe('ek borç: Fon hesabı tahakkukunun dayanağı', () => {
  beforeEach(() => install());
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('Karar Defteri AÇIK + kararsız Fon tahakkuku -> 400 DECISION_REQUIRED; hiçbir şey yazılmaz, işlem geri alınır', async () => {
    const body = await confirmBody();
    db.log.length = 0;
    await assert.rejects(() => postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_REQUIRED'));
    assert.deepEqual(wrote(), []);
    assert.equal(db.log.at(-1).sql, 'ROLLBACK');
    assert.equal(db.log.some((entry) => entry.sql === 'COMMIT'), false);
  });

  it('Karar Defteri AÇIK + yalnız gerekçe -> yine 400 DECISION_REQUIRED (gerekçe kararın yerini tutmaz)', async () => {
    const body = await confirmBody({ decision_reason: 'Yönetim kurulunda konuşuldu' });
    await assert.rejects(() => postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_REQUIRED'));
    assert.deepEqual(wrote(), []);
  });

  it('Karar Defteri KAPALI + gerekçesiz Fon tahakkuku -> 400 DECISION_REASON_REQUIRED; boşluk-yalnız gerekçe de gerekçesizdir', async () => {
    db.decisionModuleEnabled = false;
    const body = await confirmBody();
    await assert.rejects(() => postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_REASON_REQUIRED'));
    await assert.rejects(() => postCharge({ siteCode: SITE, body: { ...body, decision_reason: '    ' }, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_REASON_REQUIRED'));
    assert.deepEqual(wrote(), []);
  });

  it('Karar Defteri KAPALI + karar kimliği gönderilirse 400 DECISION_MODULE_OFF (karar sessizce yok sayılmaz)', async () => {
    db.decisionModuleEnabled = false;
    const body = await confirmBody({ decision_id: 77 });
    await assert.rejects(() => postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_MODULE_OFF'));
    assert.deepEqual(wrote(), []);
  });

  it('başka sitenin / olmayan karar 404 DECISION_NOT_FOUND (aynı yanıt: IDOR yok); taslak karar 409 DECISION_NOT_FINAL', async () => {
    for (const id of [90, 12345]) {
      const body = await confirmBody({ decision_id: id });
      await assert.rejects(() => postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW }), codeOf(404, 'DECISION_NOT_FOUND'), String(id));
    }
    const draft = await confirmBody({ decision_id: 78 });
    await assert.rejects(() => postCharge({ siteCode: SITE, body: draft, actor: MANAGER, now: NOW }), codeOf(409, 'DECISION_NOT_FINAL'));
    assert.deepEqual(wrote(), []);
    // her sorguda site_code vardır
    const lookups = db.log.filter((entry) => /FROM board_decisions/.test(entry.sql));
    assert.ok(lookups.length >= 3);
    for (const lookup of lookups) assert.equal(lookup.params[0], SITE);
  });

  it('kesin karar seçilince yazılır: karar kimliği fee_runs INSERT\'ine gider, yanıttaki run.decision karar numarasını taşır; denetim kaydında gerekçe metni YOK', async () => {
    const body = await confirmBody({ decision_id: 77, decision_reason: 'Genel kurulun 12 Ekim kararı' });
    const result = await postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW });
    assert.equal(result.replayed, false);
    assert.equal(db.runInsert[10], '77');
    assert.equal(db.runInsert[11], 'Genel kurulun 12 Ekim kararı');
    assert.deepEqual(result.run.decision, { id: 77, number_label: '2026/4', title: 'Asansör yenileme', visibility: 'sakinler', reason: 'Genel kurulun 12 Ekim kararı' });
    assert.equal(db.ledgerInsert.at(-1), 'capital', 'Fon hesabı borcu kasası capital');
    const audit = db.auditDetails.find((details) => details.definition_id !== undefined && details.distribution !== undefined);
    assert.equal(audit.decision_id, 77);
    assert.equal(audit.decision_reason_given, true);
    assert.equal(JSON.stringify(db.auditDetails).includes('Genel kurulun'), false, 'gerekçe metni denetime yazılmaz');
    assert.equal(db.log.at(-1).sql, 'COMMIT');
    // karar satırı FOR KEY SHARE okunur, işlem içinde ve plan hesabından ÖNCE
    const lookupAt = db.log.findIndex((entry) => /FROM board_decisions/.test(entry.sql));
    const planAt = db.log.findIndex((entry) => /FROM apartments a INNER JOIN site_blocks/.test(entry.sql) && /FOR KEY SHARE OF a/.test(entry.sql));
    assert.ok(lookupAt > 0 && lookupAt < planAt);
  });

  it('Karar Defteri KAPALI + gerekçe: gerekçe saklanır, karar kimliği null; yanıtta yalnız gerekçe', async () => {
    db.decisionModuleEnabled = false;
    const body = await confirmBody({ decision_reason: 'Kâğıt defterde 14 Ekim tarihli karar, no 6' });
    const result = await postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW });
    assert.equal(db.runInsert[10], null);
    assert.equal(db.runInsert[11], 'Kâğıt defterde 14 Ekim tarihli karar, no 6');
    assert.deepEqual(result.run.decision, { id: null, number_label: null, title: null, visibility: null, reason: 'Kâğıt defterde 14 Ekim tarihli karar, no 6' });
    assert.equal(db.log.some((entry) => /FROM board_decisions/.test(entry.sql)), false, 'modül kapalıyken karar tablosu okunmaz');
  });

  it('işletme (Aidat) hesabı ek borcu dayanaksız yazılır; Karar Defteri sorgusu bile yapılmaz', async () => {
    const body = await confirmBody({ fund: 'operating' });
    const result = await postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW });
    assert.equal(db.runInsert[10], null);
    assert.equal(db.runInsert[11], null);
    assert.equal('decision' in result.run, false);
    assert.equal(db.ledgerInsert.at(-1), 'operating');
    assert.equal(db.log.some((entry) => /FROM board_decisions/.test(entry.sql)), false);
    assert.equal(db.log.filter((entry) => entry.params[1] === 'decision_book').length >= 1, true, 'yalnız önizleme modül durumunu okur');
    const audit = db.auditDetails.find((details) => details.distribution !== undefined);
    assert.equal('decision_id' in audit, false);
    assert.equal('decision_reason_given' in audit, false);
  });

  it('idempotans: aynı anahtar + aynı dayanak tekrarı AYNI kaydı dayanağıyla döndürür; aynı anahtar + farklı karar 409 IDEMPOTENCY_CONFLICT', async () => {
    const body = await confirmBody({ decision_id: 77 });
    await postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW });
    const fingerprint = db.runInsert[7];
    assert.match(fingerprint, /^[0-9a-f]{64}$/);
    // veritabanında bu anahtarla kayıt var: sahte DB onu döndürür
    db.existingRun = {
      id: '501', definition_id: '31', period: '2026-10-01', total_minor: '3000', apartment_count: 3, skipped_count: 0, posted_at: new Date('2026-10-28T09:00:00Z'),
      request_fingerprint: fingerprint, definition_kind: 'one_time', definition_distribution: 'fixed',
      run_decision_id: '77', run_decision_reason: null, run_decision_year: 2026, run_decision_no: 4, run_decision_title: 'Asansör yenileme', run_decision_visibility: 'sakinler',
    };
    db.log.length = 0;
    const again = await postCharge({ siteCode: SITE, body, actor: MANAGER, now: NOW });
    assert.equal(again.replayed, true);
    assert.equal(again.run.decision.number_label, '2026/4');
    assert.deepEqual(wrote(), []);
    // farklı karar, aynı anahtar
    await assert.rejects(() => postCharge({ siteCode: SITE, body: { ...body, decision_id: 78 }, actor: MANAGER, now: NOW }), codeOf(409, 'IDEMPOTENCY_CONFLICT'));
    // dayanaksız (eski istemci) istek aynı anahtarla: parmak izi farklı -> çakışma (dayanak sessizce düşmez)
    const { decision_id: _dropped, ...bare } = body;
    await assert.rejects(() => postCharge({ siteCode: SITE, body: bare, actor: MANAGER, now: NOW }), codeOf(409, 'IDEMPOTENCY_CONFLICT'));
  });

  it('önizleme yanıtı decision_requirement taşır: Fon + modül açık -> decision, kapalı -> reason, işletme -> none', async () => {
    const open = await previewCharge({ siteCode: SITE, body: chargeBody(), now: NOW }, pool);
    assert.deepEqual(open.decision_requirement, { required: true, mode: 'decision', module_enabled: true, reason_min: 3, reason_max: 300 });
    const operating = await previewCharge({ siteCode: SITE, body: chargeBody({ fund: 'operating' }), now: NOW }, pool);
    assert.deepEqual(operating.decision_requirement, { required: false, mode: 'none', module_enabled: true, reason_min: 3, reason_max: 300 });
    db.decisionModuleEnabled = false;
    const closed = await previewCharge({ siteCode: SITE, body: chargeBody(), now: NOW }, pool);
    assert.deepEqual(closed.decision_requirement, { required: true, mode: 'reason', module_enabled: false, reason_min: 3, reason_max: 300 });
    assert.deepEqual(wrote(), [], 'önizleme hiçbir şey yazmaz');
  });
});

// --------------------------------------------------------------------------------------------------------------------------------------------------
// Aylık borçlandırma (postDefinition)
// --------------------------------------------------------------------------------------------------------------------------------------------------

describe('aylık borçlandırma: Fon hesabı tahakkukunun dayanağı', () => {
  const definitionRow = (chargeParty) => ({
    id: '5', name: 'Dış cephe katkı payı', kind: 'recurring', distribution: 'fixed', area_basis: null, amount_minor: '1000', category_amounts: null, due_day: 5,
    start_period: '2026-01-01', end_period: null, target_type: 'site', target_block_ids: [], target_apartment_ids: [], is_active: true,
    created_at: new Date('2026-01-02T09:00:00Z'), updated_at: new Date('2026-01-02T09:00:00Z'), charge_party: chargeParty, created_by_name: 'Ayşe Yönetici', has_runs: false, last_posted_period: null,
  });
  const postBody = async (extra = {}) => {
    const preview = await previewDefinition({ siteCode: SITE, rawId: '5', body: { period: '2026-10' }, now: NOW }, pool);
    return { period: '2026-10', expected_total_minor: preview.total_minor, expected_apartment_count: preview.apartment_count, expected_hash: preview.preview_hash, ...extra };
  };

  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('Fon (malik öder) tanımı + modül AÇIK + kararsız -> 400 DECISION_REQUIRED; kapalı + gerekçesiz -> 400 DECISION_REASON_REQUIRED; hiçbir şey yazılmaz', async () => {
    install({ definition: definitionRow('owner') });
    const body = await postBody();
    await assert.rejects(() => postDefinition({ siteCode: SITE, rawId: '5', body, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_REQUIRED'));
    db.decisionModuleEnabled = false;
    await assert.rejects(() => postDefinition({ siteCode: SITE, rawId: '5', body, actor: MANAGER, now: NOW }), codeOf(400, 'DECISION_REASON_REQUIRED'));
    assert.deepEqual(wrote(), []);
  });

  it('Fon tanımı + kesin karar: çalıştırma karar kimliğiyle yazılır, yanıt run.decision karar numarasını taşır', async () => {
    install({ definition: definitionRow('owner') });
    const body = await postBody({ decision_id: 77 });
    const result = await postDefinition({ siteCode: SITE, rawId: '5', body, actor: MANAGER, now: NOW });
    assert.equal(db.runInsert[10], '77');
    assert.equal(db.runInsert[11], null);
    assert.equal(result.run.decision.number_label, '2026/4');
    assert.equal(db.ledgerInsert.at(-1), 'capital');
    assert.equal(db.auditDetails.at(-1).decision_id, 77);
  });

  it('Fon tanımı + modül KAPALI + gerekçe: gerekçe yazılır', async () => {
    install({ definition: definitionRow('owner'), decisionModuleEnabled: false });
    const body = await postBody({ decision_reason: 'Yönetim kurulu 3 Ekim toplantısı' });
    const result = await postDefinition({ siteCode: SITE, rawId: '5', body, actor: MANAGER, now: NOW });
    assert.equal(db.runInsert[10], null);
    assert.equal(db.runInsert[11], 'Yönetim kurulu 3 Ekim toplantısı');
    assert.equal(result.run.decision.reason, 'Yönetim kurulu 3 Ekim toplantısı');
  });

  it('aylık aidat (dairede oturan öder = işletme hesabı) dayanak İSTEMEZ; günlük aidat akışı değişmez', async () => {
    install({ definition: definitionRow('occupant') });
    const body = await postBody();
    const result = await postDefinition({ siteCode: SITE, rawId: '5', body, actor: MANAGER, now: NOW });
    assert.equal(db.runInsert[10], null);
    assert.equal(db.runInsert[11], null);
    assert.equal('decision' in result.run, false);
    assert.equal(db.ledgerInsert.at(-1), 'operating');
    const preview = await previewDefinition({ siteCode: SITE, rawId: '5', body: { period: '2026-10' }, now: NOW }, pool);
    assert.equal(preview.decision_requirement.mode, 'none');
  });
});

// --------------------------------------------------------------------------------------------------------------------------------------------------
// resolveRunDecision doğrudan
// --------------------------------------------------------------------------------------------------------------------------------------------------

describe('resolveRunDecision / describeDecisionRequirement', () => {
  beforeEach(() => install());
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('işletme + dayanaksız: hiçbir sorgu yapılmaz; Fon + kesin karar: etiket satırı karar numarasını verir', async () => {
    const client = { query: pool.query };
    const none = await resolveRunDecision(client, { siteCode: SITE, fund: 'operating' });
    assert.deepEqual(none, { decisionId: null, decisionReason: null, label: null });
    assert.equal(db.log.length, 0);
    const resolved = await resolveRunDecision(client, { siteCode: SITE, fund: 'capital', decisionId: 77 });
    assert.equal(resolved.label.run_decision_no, 4);
    assert.equal(resolved.label.run_decision_year, 2026);
    assert.equal(resolved.decisionId, 77);
  });

  it('kesin görünen ama numarasız satır (veri tutarsızlığı) taslak sayılır', async () => {
    DECISIONS[79] = { id: '79', year: 2026, decision_no: null, title: 'Tutarsız', visibility: 'yonetim', status: 'kesin', site_code: SITE };
    try {
      await assert.rejects(() => resolveRunDecision({ query: pool.query }, { siteCode: SITE, fund: 'capital', decisionId: 79 }), codeOf(409, 'DECISION_NOT_FINAL'));
    } finally {
      delete DECISIONS[79];
    }
  });

  it('describeDecisionRequirement: modül durumuna göre mod', async () => {
    assert.equal((await describeDecisionRequirement(pool, SITE, 'capital')).mode, 'decision');
    db.decisionModuleEnabled = false;
    assert.equal((await describeDecisionRequirement(pool, SITE, 'capital')).mode, 'reason');
    assert.equal((await describeDecisionRequirement(pool, SITE, 'operating')).mode, 'none');
  });
});
