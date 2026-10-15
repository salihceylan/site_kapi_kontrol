// Platform denetim kaydi servisi (DB'siz): recordAudit (basarisizlik ana islemi bozmaz, savepoint) ve listAuditLog.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  AUDIT_DEFAULT_LIMIT,
  AUDIT_MAX_LIMIT,
  actorFromAuthUser,
  clampAuditLimit,
  listAuditLog,
  recordAudit,
} from '../src/modules/audit_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function fakeDb({ failInsert = false, failSavepoint = false } = {}) {
  const log = [];
  return {
    log,
    async query(text, params) {
      const sql = norm(text);
      log.push({ sql, params });
      if (failSavepoint && sql.startsWith('SAVEPOINT')) {
        throw new Error('baglanti koptu');
      }
      if (failInsert && sql.startsWith('INSERT INTO audit_log')) {
        throw Object.assign(new Error('relation "audit_log" does not exist'), { code: '42P01' });
      }
      return { rows: [], rowCount: 0 };
    },
  };
}

const actor = { user_code: 20001, userCode: 20001, id: 20001, full_name: 'Ayşe Yönetici', role: 'site_manager' };

beforeEach(() => {
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  delete pool.query;
  mock.restoreAll();
});

describe('actorFromAuthUser', () => {
  it('authUser ve hazir actor nesnesinden ayni alanlari uretir', () => {
    assert.deepEqual(actorFromAuthUser(actor), { userCode: 20001, name: 'Ayşe Yönetici', role: 'site_manager' });
    assert.deepEqual(actorFromAuthUser({ userCode: 5, name: 'X', role: 'super_user' }), { userCode: 5, name: 'X', role: 'super_user' });
    assert.deepEqual(actorFromAuthUser(null), { userCode: null, name: null, role: null });
    assert.equal(actorFromAuthUser({ id: 'abc' }).userCode, null);
    assert.equal(actorFromAuthUser({ id: -3 }).userCode, null);
    assert.equal(actorFromAuthUser({ full_name: 'x'.repeat(500) }).name.length, 200);
  });
});

describe('recordAudit', () => {
  it('pool/istemci ile INSERT yapar; parametre sirasi ve JSON ayrintisi dogru', async () => {
    const db = fakeDb();
    const result = await recordAudit(db, {
      actor,
      action: 'module.disabled',
      siteCode: '1000000001',
      targetType: 'module',
      targetId: 'door_control',
      details: { enabled: false },
    });
    assert.equal(result, true);
    assert.equal(db.log.length, 1);
    assert.match(db.log[0].sql, /^INSERT INTO audit_log \( actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details \) VALUES \(\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8::jsonb\)$/);
    assert.deepEqual(db.log[0].params, [
      20001,
      'Ayşe Yönetici',
      'site_manager',
      'module.disabled',
      1000000001,
      'module',
      'door_control',
      '{"enabled":false}',
    ]);
  });

  it('eksik alanlar null; targetId sayi metne cevrilir; details yoksa {}', async () => {
    const db = fakeDb();
    await recordAudit(db, { action: 'staff_role.removed', targetId: 30001 });
    assert.deepEqual(db.log[0].params, [null, null, null, 'staff_role.removed', null, null, '30001', '{}']);
  });

  it('db verilmezse varsayilan havuz kullanilir: recordAudit(entry)', async () => {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ sql: norm(text), params });
      return { rows: [] };
    };
    assert.equal(await recordAudit({ actor, action: 'a.b' }), true);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].params[3], 'a.b');
  });

  it('action yoksa yazilmaz ve false doner (ana islem bozulmaz)', async () => {
    const db = fakeDb();
    assert.equal(await recordAudit(db, { actor, action: '   ' }), false);
    assert.equal(await recordAudit(db, undefined), false);
    assert.equal(db.log.length, 0);
  });

  it('INSERT basarisiz olursa hata YUTULUR, console\'a yazilir, false doner', async () => {
    const db = fakeDb({ failInsert: true });
    const result = await recordAudit(db, { actor, action: 'module.enabled' });
    assert.equal(result, false);
    assert.equal(console.error.mock.calls.length, 1);
    assert.match(String(console.error.mock.calls[0].arguments[0]), /\[audit\]/);
    assert.equal(db.log.length, 1);
  });

  it('inTransaction: SAVEPOINT -> INSERT -> RELEASE (basarida)', async () => {
    const db = fakeDb();
    assert.equal(await recordAudit(db, { actor, action: 'module.enabled' }, { inTransaction: true }), true);
    assert.deepEqual(
      db.log.map((e) => e.sql.split(' ').slice(0, 3).join(' ')),
      ['SAVEPOINT audit_insert', 'INSERT INTO audit_log', 'RELEASE SAVEPOINT audit_insert'],
    );
  });

  it('inTransaction + INSERT hatasi: ROLLBACK TO SAVEPOINT + RELEASE ile transaction korunur, false doner', async () => {
    const db = fakeDb({ failInsert: true });
    assert.equal(await recordAudit(db, { actor, action: 'module.enabled' }, { inTransaction: true }), false);
    assert.deepEqual(
      db.log.map((e) => e.sql),
      [
        'SAVEPOINT audit_insert',
        db.log[1].sql,
        'ROLLBACK TO SAVEPOINT audit_insert',
        'RELEASE SAVEPOINT audit_insert',
      ],
    );
    assert.match(db.log[1].sql, /^INSERT INTO audit_log/);
  });

  it('SAVEPOINT bile kurulamazsa (kopuk baglanti) sessizce false doner', async () => {
    const db = fakeDb({ failSavepoint: true });
    assert.equal(await recordAudit(db, { actor, action: 'module.enabled' }, { inTransaction: true }), false);
    assert.equal(db.log.length, 1);
  });
});

describe('clampAuditLimit', () => {
  it('1..200 araliginda sinirlar; bos/sayi olmayan varsayilan 50', () => {
    assert.equal(AUDIT_DEFAULT_LIMIT, 50);
    assert.equal(AUDIT_MAX_LIMIT, 200);
    const cases = [
      [undefined, 50], [null, 50], ['', 50], ['  ', 50], ['abc', 50], [NaN, 50], [Infinity, 50],
      [0, 1], [-5, 1], [1, 1], [25, 25], [200, 200], [201, 200], [99999, 200], ['30', 30], ['7.9', 7],
    ];
    for (const [input, expected] of cases) {
      assert.equal(clampAuditLimit(input), expected, String(input));
    }
  });
});

describe('listAuditLog', () => {
  function installRows(rows) {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ sql: norm(text), params });
      return { rows };
    };
    return calls;
  }

  const row = (id, extra = {}) => ({
    id: String(id),
    created_at: new Date('2026-10-15T07:00:00.000Z'),
    actor_user_code: 20001,
    actor_name: 'Ayşe',
    actor_role: 'site_manager',
    action: 'module.disabled',
    site_code: '1000000001',
    site_name: 'Gül Sitesi',
    target_type: 'module',
    target_id: 'door_control',
    details: { enabled: false },
    ...extra,
  });

  it('limit + 1 satir ister; fazlasi varsa sonraki sayfa isareti son ogenin id\'sidir', async () => {
    const calls = installRows([row(9), row(8), row(7)]);
    const page = await listAuditLog({ limit: 2 });
    assert.equal(calls[0].params[2], 3);
    assert.deepEqual(page.items.map((i) => i.id), [9, 8]);
    assert.equal(page.next_before_id, 8);
  });

  it('fazla satir yoksa next_before_id null; bos listede de null', async () => {
    installRows([row(3), row(2)]);
    assert.equal((await listAuditLog({ limit: 2 })).next_before_id, null);
    installRows([]);
    assert.deepEqual(await listAuditLog({}), { items: [], next_before_id: null });
  });

  it('suzgec parametreleri: siteCode ve beforeId sorguya gider; varsayilanlar null/50', async () => {
    const calls = installRows([]);
    await listAuditLog({ siteCode: 1000000001, beforeId: 77, limit: 10 });
    assert.deepEqual(calls[0].params, [1000000001, 77, 11, null]);
    await listAuditLog();
    assert.deepEqual(calls[1].params, [null, null, 51, null]);
    await listAuditLog({ action: 'module.disabled' });
    assert.deepEqual(calls[2].params, [null, null, 51, 'module.disabled']);
    assert.match(calls[0].sql, /ORDER BY a\.id DESC/);
    assert.match(calls[0].sql, /\$4::TEXT IS NULL OR a\.action = \$4::TEXT/);
  });

  it('satirlari sozlesme bicimine cevirir (sayi id/site_code, ISO tarih, details metinse ayristirilir)', async () => {
    installRows([row(5, { details: '{"role":"STAFF"}', site_code: null, site_name: null, actor_user_code: null })]);
    const { items } = await listAuditLog({});
    assert.deepEqual(items[0], {
      id: 5,
      created_at: '2026-10-15T07:00:00.000Z',
      actor_user_code: null,
      actor_name: 'Ayşe',
      actor_role: 'site_manager',
      action: 'module.disabled',
      site_code: null,
      site_name: null,
      target_type: 'module',
      target_id: 'door_control',
      details: { role: 'STAFF' },
    });
  });

  it('bozuk details metni {} olur (liste bozulmaz)', async () => {
    installRows([row(1, { details: '{bozuk' }), row(2, { details: null })]);
    const { items } = await listAuditLog({ limit: 5 });
    assert.deepEqual(items.map((i) => i.details), [{}, {}]);
  });
});
