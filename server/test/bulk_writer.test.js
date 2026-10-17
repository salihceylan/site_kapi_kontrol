// Toplu yükleme (Faz 2b) yazıcısı (DB'siz, sahte istemci): işlem birleştirme, küme tabanlı parametreli ifadeler, audit içeriği (kişisel veri yok),
// parça boyutları ve yarış tespiti (satır sayısı tutmazsa / 23505 -> 409 PREVIEW_STALE). Gerçek PG: scripts/qa_platform_pg.mjs bölüm bulk_import.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { AUDIT_CHUNK, ENTITY_CHUNK, applyApartmentOps, applyPeopleOps, insertAudits } from '../src/modules/bulk_import_writer.js';

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
    const audits = await applyPeopleOps(client, { ...BASE, ops });
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
    const audits = await applyPeopleOps(client, { ...BASE, ops });
    const text = JSON.stringify(audits.filter((a) => a.action !== 'vehicle.added'));
    assert.ok(!/Ahmet|Ayşe|a@example|5551234567/.test(text), text);
    assert.equal(audits.find((a) => a.action === 'vehicle.added').details.plate, '34ABC123');
    assert.equal(audits.find((a) => a.action === 'residency.added').details.relation, 'owner');
  });

  it('mevcut kişiler: aynı kişinin fill / yeniden etkinleştirme işlemleri TEK satırda toplanır; audit yalnız { field, changed } / is_active', async () => {
    const client = fakeClient();
    const audits = await applyPeopleOps(client, {
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
    assert.equal(small.log.length, 4, 'nextval + kişi + ilişki + araç');
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
    assert.deepEqual(rows[0], { id: 10, set_floor: true, floor: 3, set_category: true, category: '3+1', set_gross: false, gross: null, set_net: false, net: null, set_ln: false, ln: null, set_ld: false, ld: null, set_rp: false, rp: null });
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
