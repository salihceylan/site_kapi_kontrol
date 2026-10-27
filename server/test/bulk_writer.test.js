// Toplu yükleme (Faz 2b) yazıcısı (DB'siz, sahte istemci): işlem birleştirme, küme tabanlı parametreli ifadeler, audit içeriği (kişisel veri yok),
// parça boyutları ve yarış tespiti (satır sayısı tutmazsa / 23505 -> 409 PREVIEW_STALE). Gerçek PG: scripts/qa_platform_pg.mjs bölüm bulk_import.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import {
  AUDIT_CHUNK,
  ENTITY_CHUNK,
  LOGIN_NAME_BASE_MAX,
  RELATION_RANK,
  applyApartmentOps,
  applyPeopleOps,
  collectAccountPasswords,
  hashAccountPasswords,
  insertAudits,
  provisionImportedResidents,
  slugifyLoginName,
} from '../src/modules/bulk_import_writer.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

/** Sahte istemci: ifadeleri kaydeder; kimlik ve satır sayısı yanıtlarını üretir. */
function fakeClient({ failOn = null, shortUpdate = false } = {}) {
  const log = [];
  let nextId = 100;
  return {
    log,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      if (failOn && failOn.test(sql)) {
        throw Object.assign(new Error('enjekte'), { code: failOn.code ?? '23505' });
      }
      if (/^SELECT nextval/.test(sql)) {
        return { rows: Array.from({ length: Number(params[0]) }, () => ({ id: String((nextId += 1)) })), rowCount: Number(params[0]) };
      }
      if (/^INSERT INTO apartment_residencies/.test(sql)) {
        const rows = JSON.parse(params[0]).map((entry) => ({ id: String((nextId += 1)), apartment_id: String(entry.apartment_id), person_id: String(entry.person_id), relation: entry.relation }));
        return { rows, rowCount: rows.length };
      }
      if (/^INSERT INTO vehicles/.test(sql)) {
        const rows = JSON.parse(params[0]).map((entry) => ({ id: String((nextId += 1)), person_id: String(entry.person_id), plate: entry.plate }));
        return { rows, rowCount: rows.length };
      }
      if (/^(UPDATE|INSERT)/.test(sql)) {
        const count = /jsonb_to_recordset/.test(sql) ? JSON.parse(params[0]).length : 0;
        return { rows: [], rowCount: shortUpdate && /^UPDATE/.test(sql) ? Math.max(0, count - 1) : count };
      }
      return { rows: [], rowCount: 0 };
    },
  };
}

const jsonOf = (entry) => JSON.parse(entry.params[0]);
const stmts = (client, pattern) => client.log.filter((entry) => pattern.test(entry.sql));
const BASE = { siteCode: 1000000001, runId: 7, today: '2026-10-16', actorUserCode: 42 };

describe('applyPeopleOps: işlem birleştirme ve ifadeler', () => {
  const ops = [
    { t: 'pc', ref: 'new:2', name: 'Ahmet Yılmaz', phone: null, email: 'a@example.com', note: null },
    { t: 'pf', ref: 'new:2', field: 'phone', value: '+905551234567' },
    { t: 'ra', ref: 'new:2', aptId: 10, relation: 'resident', moveIn: null },
    { t: 'ru', ref: 'new:2', aptId: 10, residencyId: null, from: 'resident', to: 'owner' },
    { t: 'va', ref: 'new:2', plate: '34ABC123', display: '34 ABC 123', note: null },
    { t: 'pc', ref: 'new:3', name: 'Ayşe Demir', phone: null, email: null, note: 'n' },
    { t: 'ra', ref: 'new:3', aptId: 10, relation: 'tenant', moveIn: '2021-03-15' },
  ];

  it('yeni kişi: kimlikler nextval ile ayrılır; fill (pf) ve aynı dosyadaki yükseltme (ru) ekleme işlemine birleşir; tek INSERT', async () => {
    const client = fakeClient();
    const { audits } = await applyPeopleOps(client, { ...BASE, ops });
    const nextval = stmts(client, /^SELECT nextval/);
    assert.equal(nextval.length, 1);
    assert.equal(nextval[0].params[0], 2);
    assert.match(nextval[0].sql, /pg_get_serial_sequence\('site_people', 'id'\)/);
    const people = jsonOf(stmts(client, /^INSERT INTO site_people/)[0]);
    assert.equal(people.length, 2);
    assert.deepEqual(people.map((p) => p.id), [101, 102]);
    assert.equal(people[0].phone, '+905551234567', 'fill yeni kişinin INSERT değerine birleşti');
    assert.equal(stmts(client, /^INSERT INTO site_people/)[0].params[2], BASE.actorUserCode);
    const residencies = jsonOf(stmts(client, /^INSERT INTO apartment_residencies/)[0]);
    assert.deepEqual(residencies.map((r) => [r.person_id, r.relation, r.move_in_date]), [[101, 'owner', '2026-10-16'], [102, 'tenant', '2021-03-15']]);
    assert.match(stmts(client, /^INSERT INTO apartment_residencies/)[0].sql, /'manual'/);
    const vehicles = jsonOf(stmts(client, /^INSERT INTO vehicles/)[0]);
    assert.deepEqual(vehicles.map((v) => [v.person_id, v.plate, v.display]), [[101, '34ABC123', '34 ABC 123']]);
    assert.deepEqual(audits.map((a) => a.action), ['person.created', 'person.created', 'residency.added', 'residency.added', 'vehicle.added']);
    assert.ok(audits.every((a) => a.details.via === 'import' && a.details.run_id === 7));
  });

  it('TÜM değerler parametreli (SQL\'e metin birleştirilmez): ad / e-posta / telefon / plaka ifade metninde YOKTUR', async () => {
    const client = fakeClient();
    await applyPeopleOps(client, { ...BASE, ops });
    for (const entry of client.log) {
      assert.ok(!/Ahmet|Ayşe|a@example|5551234567|34ABC123/.test(entry.sql), entry.sql.slice(0, 120));
    }
  });

  it('audit: person.updated / created / residency.* satırlarında ad, e-posta, telefon, not YOK (yalnız alan adları); vehicle.added plaka taşır', async () => {
    const client = fakeClient();
    const { audits } = await applyPeopleOps(client, { ...BASE, ops });
    const text = JSON.stringify(audits.filter((a) => a.action !== 'vehicle.added'));
    assert.ok(!/Ahmet|Ayşe|a@example|5551234567/.test(text), text);
    assert.equal(audits.find((a) => a.action === 'vehicle.added').details.plate, '34ABC123');
    assert.equal(audits.find((a) => a.action === 'residency.added').details.relation, 'owner');
  });

  it('mevcut kişiler: aynı kişinin fill / yeniden etkinleştirme işlemleri TEK satırda toplanır; audit yalnız { field, changed } / is_active', async () => {
    const client = fakeClient();
    const { audits } = await applyPeopleOps(client, {
      ...BASE,
      ops: [
        { t: 'pr', ref: 'p5', name: 'Yeni Ad', phone: '+905321112233' },
        { t: 'pf', ref: 'p5', field: 'note', value: 'gizli not' },
        { t: 'pf', ref: 'p5', field: 'email', value: 'x@y.com' },
        { t: 'pf', ref: 'p6', field: 'phone', value: '+905441112233' },
        { t: 'ru', ref: 'p7', aptId: 11, residencyId: 55, from: 'resident', to: 'owner' },
      ],
    });
    const update = stmts(client, /^UPDATE site_people/)[0];
    const rows = jsonOf(update);
    assert.equal(rows.length, 2);
    assert.deepEqual(rows.find((r) => r.id === 5), { id: 5, reactivate: true, name: 'Yeni Ad', phone: '+905321112233', fill_phone: null, fill_email: 'x@y.com', fill_note: 'gizli not' });
    assert.match(update.sql, /sp\.user_code IS NULL/, 'hesaplı kişiye alan yazılmaz (SQL koruması)');
    assert.match(update.sql, /sp\.note IS NULL/);
    const upgrade = stmts(client, /^UPDATE apartment_residencies/)[0];
    assert.deepEqual(jsonOf(upgrade), [{ id: 55, relation: 'owner' }]);
    assert.match(upgrade.sql, /r\.relation = 'resident'/);
    const updated = audits.filter((a) => a.action === 'person.updated');
    assert.deepEqual(updated.map((a) => a.target_id), ['5', '6']);
    assert.deepEqual(updated[0].details.changes, [
      { field: 'is_active', from: false, to: true },
      { field: 'full_name', changed: true },
      { field: 'phone', changed: true },
      { field: 'email', changed: true },
      { field: 'note', changed: true },
    ]);
    assert.ok(!/Yeni Ad|gizli not|x@y\.com|5321112233|5441112233/.test(JSON.stringify(audits)));
    const residencyAudit = audits.find((a) => a.action === 'residency.updated');
    assert.deepEqual(residencyAudit.details.changes, [{ field: 'relation', from: 'resident', to: 'owner' }]);
    assert.equal(residencyAudit.target_id, '7');
  });

  it('yarış tespiti: beklenen satır sayısı tutmazsa ya da 23505/23503 olursa 409 PREVIEW_STALE', async () => {
    const stale = (error) => error.statusCode === 409 && error.code === 'PREVIEW_STALE';
    await assert.rejects(() => applyPeopleOps(fakeClient({ shortUpdate: true }), { ...BASE, ops: [{ t: 'pf', ref: 'p5', field: 'note', value: 'x' }] }), stale);
    await assert.rejects(() => applyPeopleOps(fakeClient({ shortUpdate: true }), { ...BASE, ops: [{ t: 'ru', ref: 'p5', aptId: 1, residencyId: 9, from: 'resident', to: 'owner' }] }), stale);
    const unique = Object.assign(/^INSERT INTO apartment_residencies/, { code: '23505' });
    await assert.rejects(() => applyPeopleOps(fakeClient({ failOn: unique }), { ...BASE, ops }), stale);
    const fk = Object.assign(/^INSERT INTO vehicles/, { code: '23503' });
    await assert.rejects(() => applyPeopleOps(fakeClient({ failOn: fk }), { ...BASE, ops }), stale);
    // beklenmeyen hata (ör. bağlantı kopması) olduğu gibi fırlar (500, errorId yolu)
    const other = Object.assign(/^INSERT INTO site_people/, { code: '08006' });
    await assert.rejects(() => applyPeopleOps(fakeClient({ failOn: other }), { ...BASE, ops }), (error) => error.code === '08006');
  });

  it('parça boyutu: 12.000 araç -> 3 INSERT (5000 + 5000 + 2000); sorgu sayısı satır sayısıyla ORANTILI DEĞİL, parça sayısıyla', async () => {
    const client = fakeClient();
    const vehicleOps = Array.from({ length: 12000 }, (_, i) => ({ t: 'va', ref: 'p1', plate: `34A${String(i).padStart(5, '0')}`, display: '', note: null }));
    await applyPeopleOps(client, { ...BASE, ops: vehicleOps });
    const inserts = stmts(client, /^INSERT INTO vehicles/);
    assert.deepEqual(inserts.map((entry) => jsonOf(entry).length), [ENTITY_CHUNK, ENTITY_CHUNK, 2000]);
    // 5000 satırlık dosyada: 5000 kişi + 5000 ilişki + 5000 araç = üç ifade, tek parça
    const small = fakeClient();
    await applyPeopleOps(small, {
      ...BASE,
      ops: Array.from({ length: 5000 }, (_, i) => [
        { t: 'pc', ref: `new:${i + 2}`, name: `Kişi ${i}`, phone: null, email: null, note: null },
        { t: 'ra', ref: `new:${i + 2}`, aptId: 1, relation: 'resident', moveIn: null },
        { t: 'va', ref: `new:${i + 2}`, plate: `34K${String(i).padStart(5, '0')}`, display: '', note: null },
      ]).flat(),
    });
    assert.equal(small.log.length, 5, 'nextval + kişi + ilişki + ilişki adli kaydı (tek kümesel ifade) + araç');
  });
});

describe('applyApartmentOps', () => {
  it('yalnız değişen sütunlar kümesi: set_* bayrakları, parametreli JSON; audit { changes: [{field, from, to}] }', async () => {
    const client = fakeClient();
    const audits = await applyApartmentOps(client, {
      siteCode: BASE.siteCode,
      runId: 7,
      ops: [
        { t: 'au', aptId: 10, set: { floor: 3, category: '3+1' }, changes: [{ field: 'floor', from: null, to: 3 }, { field: 'category', from: null, to: '3+1' }] },
        { t: 'au', aptId: 11, set: { land_share_numerator: 35, land_share_denominator: 1000 }, changes: [{ field: 'land_share_numerator', from: null, to: 35 }, { field: 'land_share_denominator', from: null, to: 1000 }] },
      ],
    });
    const update = stmts(client, /^UPDATE apartments/)[0];
    const rows = jsonOf(update);
    assert.deepEqual(rows[0], { id: 10, set_floor: true, floor: 3, set_category: true, category: '3+1', set_ln: false, ln: null, set_ld: false, ld: null, set_rp: false, rp: null });
    assert.equal(rows[1].set_ln && rows[1].set_ld && rows[1].ln === 35 && rows[1].ld === 1000, true, 'arsa payı çifti TEK ifadede birlikte yazılır (CHECK tutarlılığı)');
    assert.match(update.sql, /a\.site_code = \$2/, 'IDOR: yalnız o sitenin daireleri');
    assert.deepEqual(audits.map((a) => [a.action, a.target_type, a.target_id, a.details.via, a.details.run_id]), [
      ['apartment.updated', 'apartment', '10', 'import', 7],
      ['apartment.updated', 'apartment', '11', 'import', 7],
    ]);
    assert.deepEqual(audits[0].details.changes, [{ field: 'floor', from: null, to: 3 }, { field: 'category', from: null, to: '3+1' }]);
  });

  it('etkilenen satır sayısı tutmazsa (daire silinmiş / başka site) 409 PREVIEW_STALE', async () => {
    await assert.rejects(
      () => applyApartmentOps(fakeClient({ shortUpdate: true }), { siteCode: 1, runId: 1, ops: [{ t: 'au', aptId: 10, set: { floor: 1 }, changes: [] }] }),
      (error) => error.statusCode === 409 && error.code === 'PREVIEW_STALE',
    );
  });
});

describe('insertAudits', () => {
  it('toplu ve SAVEPOINT\'siz; 10.000\'lik parçalar; kullanıcı / site parametreleri', async () => {
    const client = fakeClient();
    const rows = Array.from({ length: 25000 }, (_, i) => ({ action: 'person.created', target_type: 'person', target_id: String(i), details: { via: 'import' } }));
    await insertAudits(client, { siteCode: 9, actor: { userCode: 42, name: 'Yönetici', role: 'site_manager' }, rows });
    const inserts = stmts(client, /^INSERT INTO audit_log/);
    assert.deepEqual(inserts.map((entry) => jsonOf(entry).length), [AUDIT_CHUNK, AUDIT_CHUNK, 5000]);
    assert.equal(client.log.some((entry) => /SAVEPOINT/i.test(entry.sql)), false);
    assert.deepEqual(inserts[0].params.slice(1), [42, 'Yönetici', 'site_manager', 9]);
    assert.equal(stmts(client, /^INSERT INTO audit_log/).length, 3);
  });
});

// ===============================================================================================================
// Hesap açma (provisionImportedResidents): kapsam sınırı, tek hesap, site bağı, SAVEPOINT, şifre/kullanıcı adı eşleşmesi
// ===============================================================================================================

describe('applyPeopleOps: hesap adayları ve ref -> kişi kimliği', () => {
  it('yalnız bu çalıştırmada daire ilişkisi EKLENEN kişiler aday olur; ref -> kimlik haritası döner; şifre/kullanıcı adı ref üzerinden taşınır', async () => {
    const client = fakeClient();
    const { idByRef, accountCandidates } = await applyPeopleOps(client, {
      ...BASE,
      ops: [
        { t: 'pc', ref: 'new:2', n: 2, name: 'Ali Aynı', phone: null, email: null, note: null, password: 'ali-sifre', loginName: 'ali.a' },
        { t: 'ra', ref: 'new:2', n: 2, aptId: 10, relation: 'resident', moveIn: null },
        { t: 'pc', ref: 'new:3', n: 3, name: 'Ali Aynı', phone: null, email: null, note: null, password: 'baska', loginName: null },
        { t: 'ra', ref: 'new:3', n: 3, aptId: 11, relation: 'tenant', moveIn: null },
        { t: 'pc', ref: 'new:4', n: 4, name: 'Dairesiz', phone: null, email: null, note: null, password: '1234', loginName: null },
        { t: 'pf', ref: 'p9', field: 'note', value: 'x' }, // mevcut kişi, yeni daire yok -> aday DEĞİL
        { t: 'ra', ref: 'p7', n: 5, aptId: 12, relation: 'owner', moveIn: null, password: 'mevcut', loginName: null },
        { t: 'ra', ref: 'p7', n: 6, aptId: 13, relation: 'owner', moveIn: null },
      ],
    });
    assert.deepEqual([...idByRef.entries()], [['new:2', 101], ['new:3', 102], ['new:4', 103], ['p9', 9], ['p7', 7]]);
    assert.deepEqual(accountCandidates.map((c) => [c.ref, c.personId, c.n, c.password, c.loginName]), [
      ['new:2', 101, 2, 'ali-sifre', 'ali.a'],
      ['new:3', 102, 3, 'baska', null],
      ['p7', 7, 5, 'mevcut', null],
    ]);
    assert.deepEqual(accountCandidates[2].apartments.map((a) => a.aptId), [12, 13], 'iki daire -> tek aday, iki ilişki');
    assert.equal(accountCandidates.some((c) => c.ref === 'new:4' || c.ref === 'p9'), false);
  });

  it('aynı dosyada kişiye eklenen ilişkinin yükseltmesi (ru) adayın ilişkisine yansır', async () => {
    const client = fakeClient();
    const { accountCandidates } = await applyPeopleOps(client, {
      ...BASE,
      ops: [
        { t: 'pc', ref: 'new:2', name: 'Ahmet Yılmaz', phone: null, email: 'a@example.com', note: null },
        { t: 'ra', ref: 'new:2', aptId: 10, relation: 'resident', moveIn: null },
        { t: 'ru', ref: 'new:2', aptId: 10, residencyId: null, from: 'resident', to: 'owner' },
        { t: 'pc', ref: 'new:3', name: 'Ayşe Demir', phone: null, email: null, note: 'n' },
        { t: 'ra', ref: 'new:3', aptId: 10, relation: 'tenant', moveIn: '2021-03-15' },
      ],
    });
    assert.deepEqual(accountCandidates.map((c) => [c.ref, c.apartments[0].relation]), [['new:2', 'owner'], ['new:3', 'tenant']]);
  });
});

/**
 * Hesap açma için sahte istemci: kilitli kişi okuması, daire bilgisi, e-posta/kullanıcı adı aramaları, kullanıcı INSERT'i, SAVEPOINT kaydı.
 * `people`: id -> { full_name, email, phone }; `emailUsers`: e-posta -> { user_code, login_name, linkable }; `taken`: kullanılmış kullanıcı adları.
 */
function accountClient({ people, emailUsers = {}, taken = [], failOnInsert = null, linkRowCount = 1 } = {}) {
  const log = [];
  const takenNames = new Set(taken);
  const inserted = [];
  let nextUser = 900;
  return {
    log,
    inserted,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT sp\.id, sp\.full_name/.test(sql)) {
        const ids = params[0];
        return { rows: ids.filter((id) => people[id]).map((id) => ({ id: String(id), ...people[id] })), rowCount: 0 };
      }
      if (/^SELECT a\.id, a\.unit_label, a\.sort_order, b\.block_name/.test(sql)) {
        return { rows: params[0].map((id) => ({ id: String(id), unit_label: `Daire ${id}`, sort_order: 1, block_name: 'A Blok' })), rowCount: params[0].length };
      }
      if (/FROM users u WHERE LOWER\(u\.email\) = \$1/.test(sql)) {
        const row = emailUsers[params[0]];
        return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
      }
      if (/^SELECT LOWER\(login_name\) AS name FROM users WHERE LOWER\(login_name\) = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
        // toplu denetim: aday adlardan veritabanında olanlar döner
        const hits = params[0].filter((name) => takenNames.has(String(name).toLowerCase()));
        return { rows: hits.map((name) => ({ name })), rowCount: hits.length };
      }
      if (/^INSERT INTO users/.test(sql)) {
        // failOnInsert: SQLSTATE metni ya da { code, constraint } (kullanıcı adı yarışı için constraint = idx_users_login_name_unique)
        const failure = failOnInsert ? failOnInsert(params, inserted.length) : null;
        if (failure) {
          const injected = typeof failure === 'string' ? { code: failure } : failure;
          throw Object.assign(new Error('enjekte'), injected);
        }
        nextUser += 1;
        takenNames.add(String(params[2]).toLowerCase());
        inserted.push({ user_code: nextUser, full_name: params[0], email: params[1], login_name: params[2], phone: params[3], password_hash: params[4] });
        return { rows: [{ user_code: nextUser }], rowCount: 1 };
      }
      if (/^UPDATE site_people sp SET user_code/.test(sql)) return { rows: [], rowCount: linkRowCount };
      return { rows: [], rowCount: 0 };
    },
  };
}

const candidate = (ref, personId, apartments, extra = {}) => ({ ref, personId, n: personId, password: '1234', loginName: null, apartments, ...extra });
const sqlOf = (client, pattern) => client.log.filter((entry) => pattern.test(entry.sql));

describe('provisionImportedResidents', () => {
  it('KAPSAM: yalnız adaylar kilitlenir ve işlenir; sitedeki diğer hesapsız sakinlere dokunulmaz (toplu "tüm sakinler" sorgusu YOK)', async () => {
    const client = accountClient({ people: { 101: { full_name: 'Ali Yılmaz', email: null, phone: '+905551112233' } } });
    const result = await provisionImportedResidents(client, { siteCode: 9, runId: 7, accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }])] });
    assert.deepEqual([result.created, result.linked, result.skipped], [1, 0, 0]);
    assert.equal(client.inserted.length, 1);
    const lock = sqlOf(client, /^SELECT sp\.id, sp\.full_name/)[0];
    assert.deepEqual(lock.params, [[101], 9]);
    assert.match(lock.sql, /sp\.user_code IS NULL/, 'kişi başına user_code IS NULL yeniden doğrulanır');
    assert.match(lock.sql, /FOR UPDATE OF sp/);
    // Kiracı her zaman daire admini: grantApartmentAccess kancası YALNIZ bu daire + bu kullanıcı için aday okur (kapsamlı; tüm sakinleri taramaz).
    const scans = client.log.filter((entry) => /FROM apartment_residencies/.test(entry.sql) && !/^SELECT 1 FROM \(SELECT a\.id AS apartment_id/.test(entry.sql));
    assert.equal(scans.length, 0, 'tüm güncel sakinleri tarayan sorgu yok');
    const hook = client.log.filter((entry) => /^SELECT 1 FROM \(SELECT a\.id AS apartment_id/.test(entry.sql));
    assert.equal(hook.length, 1);
    assert.deepEqual([hook[0].params[0], hook[0].params[1], hook[0].params[2]], [[10], 901, false], 'kanca: yalnız aday dairesi + yeni hesap, site yöneticisi devri KORUNUR');
    assert.deepEqual(result.items, [{ n: 101, login_name: 'ali.yilmaz', status: 'created' }]);
    assert.deepEqual(result.audits.map((a) => [a.action, a.target_id, a.details.status, a.details.run_id]), [['person.account_created', '101', 'created', 7]]);
    assert.ok(!/Ali|Yılmaz|5551112233/.test(JSON.stringify(result.audits)), 'audit kişisel veri taşımaz');
  });

  it('kilit altında artık hesaplı (user_code dolu) çıkan kişi sessizce atlanır: kullanıcı INSERT edilmez', async () => {
    const client = accountClient({ people: {} });
    const result = await provisionImportedResidents(client, { siteCode: 9, accountCandidates: [candidate('p7', 7, [{ aptId: 10, relation: 'resident' }])] });
    assert.deepEqual([result.created, result.linked, result.skipped], [0, 0, 0]);
    assert.equal(sqlOf(client, /^INSERT INTO users/).length, 0);
  });

  it('kişi başına TEK hesap: iki dairede eklenen kişi tek kullanıcı alır, her daire için üyelik kuralı (grantApartmentAccess) çalışır', async () => {
    const client = accountClient({ people: { 101: { full_name: 'Ayşe Demir', email: null, phone: null } } });
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [candidate('new:2', 101, [{ aptId: 12, relation: 'owner' }, { aptId: 10, relation: 'owner' }])],
    });
    assert.equal(client.inserted.length, 1);
    assert.equal(result.created, 1);
    const locks = sqlOf(client, /^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE/);
    assert.deepEqual(locks.map((entry) => entry.params[0]), [10, 12], 'daire kilitleri artan sırada');
    assert.equal(sqlOf(client, /INTO apartment_memberships/).length, 2);
    assert.equal(sqlOf(client, /INTO site_memberships/).length, 2);
    // sakin göstergesine yazılan yeni hesabın PIN bayrağı: yalnız yeni hesapta
    const pin = sqlOf(client, /SET resident_pin_issued = TRUE/)[0];
    assert.deepEqual(pin.params, [[10, 12], 9, 901]);
    assert.match(pin.sql, /resident_user_code = \$3/);
  });

  it('üyelik sırası: aynı dairede KİRACI maliklerden / sakinden önce işlenir (admin önceliği kiracı > malik > diğerleri; ilk gelen daire admini olur)', async () => {
    const client = accountClient({
      people: {
        101: { full_name: 'Sakin Kişi', email: null, phone: null },
        102: { full_name: 'Malik Kişi', email: null, phone: null },
        103: { full_name: 'Kiracı Kişi', email: null, phone: null },
      },
    });
    await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [
        candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }]),
        candidate('new:3', 102, [{ aptId: 10, relation: 'owner' }]),
        candidate('new:4', 103, [{ aptId: 10, relation: 'tenant' }]),
      ],
    });
    assert.deepEqual(client.inserted.map((u) => u.full_name), ['Kiracı Kişi', 'Malik Kişi', 'Sakin Kişi']);
    assert.deepEqual(Object.entries(RELATION_RANK).sort((a, b) => a[1] - b[1]).map(([name]) => name), ['tenant', 'owner', 'resident', 'family_member']);
  });

  it('ŞİFRE / KULLANICI ADI kişi kimliğiyle (ref) eşleşir: aynı adlı iki kişi birbirinin şifresini ALMAZ; nihai ad çakışmada _2 olur ve sonuçta döner', async () => {
    const client = accountClient({
      people: {
        101: { full_name: 'Ali Veli', email: null, phone: null },
        102: { full_name: 'Ali Veli', email: null, phone: null },
      },
    });
    const hashes = new Map([
      ['new:2', { password: 'birinci', hash: 'HASH-BIRINCI' }],
      ['new:3', { password: 'ikinci', hash: 'HASH-IKINCI' }],
    ]);
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      hashes,
      accountCandidates: [
        candidate('new:3', 102, [{ aptId: 11, relation: 'resident' }], { password: 'ikinci' }),
        candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }], { password: 'birinci' }),
      ],
    });
    const byName = Object.fromEntries(client.inserted.map((u) => [u.password_hash, u.login_name]));
    assert.deepEqual(Object.keys(byName).sort(), ['HASH-BIRINCI', 'HASH-IKINCI']);
    assert.deepEqual(result.items.map((i) => i.login_name).sort(), ['ali.veli', 'ali.veli_2']);
    assert.deepEqual(client.inserted.map((u) => u.password_hash), ['HASH-BIRINCI', 'HASH-IKINCI'], 'kişi kimliği sırasıyla; her kişinin KENDİ özeti');
    assert.deepEqual(result.items.map((i) => [i.n, i.login_name]), [[101, 'ali.veli'], [102, 'ali.veli_2']]);
  });

  it('yöneticinin seçtiği kullanıcı adı yazıldığı gibi (Türkçe harf sadeleşir, küçük harf, _ ve - korunur) kullanılır; boş şifre için varsayılan 1234 özeti yerinde hesaplanır (bcrypt doğrulanır)', async () => {
    const client = accountClient({ people: { 101: { full_name: 'Çağrı Öztürk', email: null, phone: null } } });
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }], { loginName: 'Özel Ad_1', password: '' })],
    });
    assert.equal(result.items[0].login_name, 'ozel.ad_1');
    assert.equal(await bcrypt.compare('1234', client.inserted[0].password_hash), true);
    assert.match(sqlOf(client, /^INSERT INTO users/)[0].sql, /must_change_password\) VALUES \(\$1, \$2, \$3, 'apartment_owner', TRUE, TRUE, 'approved', \$4, \$5, TRUE\)/);
  });

  it('ÖNİZLEMEDE GÖSTERİLEN ad (expected) boştaysa AYNEN kullanılır; sıra (kiracı önce) gösterilen adı değiştirmez; bildirim yok', async () => {
    const client = accountClient({
      people: {
        101: { full_name: 'Ali Veli', email: null, phone: null }, // malik, satır 1: önizlemede ali.veli
        102: { full_name: 'Ali Veli', email: null, phone: null }, // kiracı, satır 2: önizlemede ali.veli_2
      },
    });
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [
        candidate('new:2', 101, [{ aptId: 10, relation: 'owner' }]),
        candidate('new:3', 102, [{ aptId: 10, relation: 'tenant' }]),
      ],
      expected: new Map([
        ['new:2', { status: 'new', loginName: 'ali.veli', n: 101 }],
        ['new:3', { status: 'new', loginName: 'ali.veli_2', n: 102 }],
      ]),
    });
    // kiracı önce işlenir (admin önceliği) ama kendi gösterilen adını alır; malik önceden ayrılmış ali.veli'yi alır
    assert.deepEqual(result.items.map((i) => [i.n, i.login_name]).sort((a, b) => a[0] - b[0]), [[101, 'ali.veli'], [102, 'ali.veli_2']]);
    assert.equal(result.renamed, 0);
    assert.ok(result.items.every((i) => !('requested_login_name' in i)));
  });

  it('YARIŞ: gösterilen ad bu arada başkasına geçtiyse sıradaki boş ad seçilir, sonuçta requested_login_name ile bildirilir, kopya YAZILMAZ; başka satıra ayrılmış ad çalınmaz', async () => {
    const client = accountClient({
      people: {
        101: { full_name: 'Ali Veli', email: null, phone: null },
        102: { full_name: 'Ali Veli', email: null, phone: null },
      },
      taken: ['ali.veli'], // önizlemeden sonra başka bir sitede biri aldı
    });
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'owner' }]), candidate('new:3', 102, [{ aptId: 11, relation: 'owner' }])],
      // önizleme: birinciye ali.veli, ikinciye ali.veli_2 gösterilmişti
      expected: new Map([
        ['new:2', { status: 'new', loginName: 'ali.veli', n: 101 }],
        ['new:3', { status: 'new', loginName: 'ali.veli_2', n: 102 }],
      ]),
    });
    const byN = Object.fromEntries(result.items.map((i) => [i.n, i]));
    assert.equal(byN[102].login_name, 'ali.veli_2');
    assert.ok(!('requested_login_name' in byN[102]));
    // birinci kişi: ali.veli alınmış; ali.veli_2 ikinci kişiye AYRILMIŞ olduğundan çalınmaz -> ali.veli_3
    assert.equal(byN[101].login_name, 'ali.veli_3');
    assert.equal(byN[101].requested_login_name, 'ali.veli');
    assert.equal(result.renamed, 1);
    const names = client.inserted.map((u) => u.login_name.toLowerCase());
    assert.equal(new Set(names).size, names.length, 'kopya kullanıcı adı yazılmadı');
  });

  it('YARIŞ (23505): INSERT sırasında ad kapılırsa SAVEPOINT geri alınır, sıradaki boş adla yeniden denenir ve bildirilir (kişi atlanmaz)', async () => {
    let failed = false;
    const client = accountClient({
      people: { 101: { full_name: 'Veli Kaya', email: null, phone: null } },
      failOnInsert: (params) => {
        if (params[2] !== 'veli.kaya' || failed) return null;
        failed = true;
        return { code: '23505', constraint: 'idx_users_login_name_unique' };
      },
    });
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'owner' }])],
      expected: new Map([['new:2', { status: 'new', loginName: 'veli.kaya', n: 101 }]]),
    });
    assert.deepEqual([result.created, result.skipped, result.renamed], [1, 0, 1]);
    assert.deepEqual(result.items, [{ n: 101, login_name: 'veli.kaya_2', status: 'created', requested_login_name: 'veli.kaya' }]);
    assert.equal(client.log.filter((entry) => /^ROLLBACK TO SAVEPOINT import_account/.test(entry.sql)).length, 1, 'kişinin kendi SAVEPOINT noktasına dönüldü ve yeniden denendi');
    assert.equal(client.log.filter((entry) => /^INSERT INTO users/.test(entry.sql)).length, 2);
  });

  it('SİTE BAĞI: e-posta başka sitenin / yöneticinin hesabına aitse (bağ yok ya da yönetici) hesap AÇILMAZ ve kullanıcı bağlanmaz; uyarı döner', async () => {
    const client = accountClient({
      people: { 101: { full_name: 'Yabancı Kişi', email: 'yonetici@example.com', phone: null } },
      emailUsers: { 'yonetici@example.com': { user_code: 55, login_name: 'yonetici', linkable: false } },
    });
    const result = await provisionImportedResidents(client, { siteCode: 9, accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }])] });
    assert.deepEqual([result.created, result.linked, result.skipped], [0, 0, 1]);
    assert.equal(sqlOf(client, /^INSERT INTO users/).length, 0, 'aynı e-postayla ikinci hesap da açılmaz');
    assert.equal(sqlOf(client, /^UPDATE site_people sp SET user_code/).length, 0, 'kişi o kullanıcıya bağlanmaz');
    assert.deepEqual(result.skipped_items.map((i) => [i.n, i.code]), [[101, 'EMAIL_IN_USE']]);
    assert.match(result.skipped_items[0].message, /e-posta/);
    const lookup = sqlOf(client, /FROM users u WHERE LOWER\(u\.email\) = \$1/)[0];
    assert.match(lookup.sql, /u\.role NOT IN \('super_user', 'site_manager'\)/, 'süper kullanıcı / site yöneticisi asla bağlanmaz');
    assert.match(lookup.sql, /tie_u\.is_active = TRUE/, 'siteTiePredicate (aktif hesap + sitede bağ) kuralı');
    assert.match(lookup.sql, /apartment_memberships/);
  });

  it('SİTE BAĞI: sitede bağı olan kullanıcıya bağlanır (yeni hesap açılmaz, şifresi değişmez), üyelik kuralı çalışır', async () => {
    const client = accountClient({
      people: { 101: { full_name: 'Komşu Kişi', email: 'komsu@example.com', phone: null } },
      emailUsers: { 'komsu@example.com': { user_code: 77, login_name: 'komsu', linkable: true } },
    });
    const result = await provisionImportedResidents(client, { siteCode: 9, accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }])] });
    assert.deepEqual([result.created, result.linked, result.skipped], [0, 1, 0]);
    assert.equal(sqlOf(client, /^INSERT INTO users/).length, 0);
    const link = sqlOf(client, /^UPDATE site_people sp SET user_code/)[0];
    assert.deepEqual(link.params, [77, 101, 9]);
    assert.deepEqual(result.items, [{ n: 101, login_name: 'komsu', status: 'linked' }]);
    assert.equal(sqlOf(client, /SET resident_pin_issued = TRUE/).length, 0, 'mevcut hesabın PIN bayrağı değişmez');
    assert.equal(sqlOf(client, /INTO apartment_memberships/).length, 1);
  });

  it('bağlama satırı etkilenmezse (hesap sitede başka kişiye bağlı) kişi atlanır ve oluşan kullanıcı SAVEPOINT ile geri alınır', async () => {
    const client = accountClient({ people: { 101: { full_name: 'Çifte Kişi', email: null, phone: null } }, linkRowCount: 0 });
    const result = await provisionImportedResidents(client, { siteCode: 9, accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }])] });
    assert.deepEqual(result.skipped_items.map((i) => i.code), ['ACCOUNT_ALREADY_LINKED']);
    assert.ok(client.log.some((entry) => /^ROLLBACK TO SAVEPOINT import_account/.test(entry.sql)));
  });

  it('SAVEPOINT: bir kişide veri hatası (23505) yalnız o kişiyi geri alır, diğerleri hesaplanır; atlananlar sayılır; transaction bozulmaz', async () => {
    const client = accountClient({
      people: {
        101: { full_name: 'Birinci Kişi', email: null, phone: null },
        102: { full_name: 'İkinci Kişi', email: null, phone: null },
        103: { full_name: 'Üçüncü Kişi', email: null, phone: null },
      },
      failOnInsert: (params) => (params[2] === 'ikinci.kisi' ? '23505' : null),
    });
    const result = await provisionImportedResidents(client, {
      siteCode: 9,
      accountCandidates: [101, 102, 103].map((id) => candidate(`new:${id}`, id, [{ aptId: 10 + id, relation: 'resident' }])),
    });
    assert.deepEqual([result.created, result.skipped], [2, 1]);
    assert.deepEqual(result.skipped_items.map((i) => [i.n, i.code]), [[102, 'ACCOUNT_FAILED']]);
    assert.deepEqual(client.inserted.map((u) => u.login_name), ['birinci.kisi', 'ucuncu.kisi']);
    const order = client.log.map((entry) => entry.sql).filter((sql) => /SAVEPOINT/.test(sql));
    assert.equal(order.filter((sql) => /^SAVEPOINT/.test(sql)).length, 3, 'kişi başına SAVEPOINT');
    assert.equal(order.filter((sql) => /^ROLLBACK TO SAVEPOINT/.test(sql)).length, 1);
    assert.ok(order.filter((sql) => /^RELEASE SAVEPOINT/.test(sql)).length >= 3, 'her SAVEPOINT serbest bırakılır');
    assert.equal(order.length, 3 + 1 + 3, 'kullanıcı adı yarışı için EK savepoint açılmaz (hesap başına sorgu sayısı artmaz)');
  });

  it('kilitlenme (40P01) ve kilit zaman aşımı (55P03) YUTULMAZ: yukarı fırlar, kişi atlanmış sayılmaz', async () => {
    for (const code of ['40P01', '55P03']) {
      const client = accountClient({
        people: { 101: { full_name: 'Kilit Kişi', email: null, phone: null } },
        failOnInsert: () => code,
      });
      await assert.rejects(
        () => provisionImportedResidents(client, { siteCode: 9, accountCandidates: [candidate('new:2', 101, [{ aptId: 10, relation: 'resident' }])] }),
        (error) => error.code === code,
      );
      assert.equal(client.log.some((entry) => /^ROLLBACK TO SAVEPOINT/.test(entry.sql)), false);
    }
  });

  it('boş aday listesi: hiçbir sorgu çalışmaz', async () => {
    const client = accountClient({ people: {} });
    const result = await provisionImportedResidents(client, { siteCode: 9, accountCandidates: [] });
    assert.deepEqual([result.created, result.linked, result.skipped], [0, 0, 0]);
    assert.equal(client.log.length, 0);
  });
});

describe('hashAccountPasswords / collectAccountPasswords / slugifyLoginName', () => {
  it('collectAccountPasswords: yalnız daire ilişkisi eklenen kişiler; yeni kişide pc, mevcut kişide ilk ra; boş şifre -> 1234', () => {
    const passwords = collectAccountPasswords([
      { t: 'pc', ref: 'new:2', password: 'abc' },
      { t: 'ra', ref: 'new:2', aptId: 1 },
      { t: 'pc', ref: 'new:3', password: 'xyz' }, // dairesiz -> hesap yok
      { t: 'ra', ref: 'p7', aptId: 2, password: '  özel  ' },
      { t: 'ra', ref: 'p7', aptId: 3, password: 'ikinci' },
      { t: 'pc', ref: 'new:4', password: '' },
      { t: 'ra', ref: 'new:4', aptId: 4 },
    ]);
    assert.deepEqual([...passwords.entries()], [['new:2', 'abc'], ['p7', 'özel'], ['new:4', '1234']]);
  });

  it('hashAccountPasswords: varsayılan dahil her şifre kendi tuzuyla özetlenir (ortak özet yok); hepsi bcrypt ile doğrulanır', async () => {
    const hashes = await hashAccountPasswords(new Map([['a', '1234'], ['b', '1234'], ['c', 'özel-1'], ['d', 'özel-1']]), { concurrency: 2 });
    assert.notEqual(hashes.get('a').hash, hashes.get('b').hash, 'varsayılan şifrede de kişi başına ayrı tuz');
    assert.equal(await bcrypt.compare('1234', hashes.get('b').hash), true);
    assert.notEqual(hashes.get('c').hash, hashes.get('d').hash, 'özel şifreler kişi başına ayrı tuz');
    assert.equal(await bcrypt.compare('1234', hashes.get('a').hash), true);
    assert.equal(await bcrypt.compare('özel-1', hashes.get('d').hash), true);
    assert.equal(hashes.get('c').password, 'özel-1');
  });

  it('slugifyLoginName: Türkçe sadeleşir, [a-z0-9] dışı tek nokta, uçlardaki nokta atılır, en çok 36 karakter, boşsa yedek ad', () => {
    assert.equal(slugifyLoginName('Çağrı  Öztürk-Şahin'), 'cagri.ozturk.sahin');
    assert.equal(slugifyLoginName('  İsmail Iğdır '), 'ismail.igdir');
    assert.equal(slugifyLoginName('...'), 'kullanici');
    assert.equal(slugifyLoginName(null), 'kullanici');
    const long = slugifyLoginName('a'.repeat(30) + ' ' + 'b'.repeat(30));
    assert.ok(long.length <= LOGIN_NAME_BASE_MAX && !long.endsWith('.'), long);
  });
});
