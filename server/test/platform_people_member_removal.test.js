// S6 ("Daireden cikar" CRM'e yansir) ve S3 (yonetici devri yalniz gostergenin sahibi icin gosterge/PIN'e dokunur) - DB'siz, betikli sahte baglanti.
import { describe, it, afterEach, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { endResidenciesForMemberRemoval } from '../src/modules/people_records.js';
import {
  handOverApartmentResident,
  removeApartmentMember,
  toggleApartmentMemberStatus,
} from '../src/services/membership_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

function scripted(handlers, { strict = false } = {}) {
  const log = [];
  return {
    log,
    async query(text, params) {
      const sql = norm(text);
      log.push({ sql, params: params ?? [] });
      for (const [pattern, handler] of handlers) {
        if (pattern.test(sql)) return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
      }
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql) || /^INSERT INTO audit_log/.test(sql)) return ok();
      if (strict) throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
      return ok();
    },
  };
}

const has = (log, regex) => log.some((q) => regex.test(q.sql));
const find = (log, regex) => log.find((q) => regex.test(q.sql));
const indexOf = (log, regex) => log.findIndex((q) => regex.test(q.sql));

beforeEach(() => {
  mock.method(console, 'error', () => {});
});
afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

describe('S6: endResidenciesForMemberRemoval (people_records)', () => {
  const RESIDENCIES = /^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.apartment_id = \$1 AND sp\.user_code = \$2 AND r\.is_current = TRUE ORDER BY r\.id FOR UPDATE OF r$/;
  const END = /^UPDATE apartment_residencies SET is_current = FALSE, move_out_date = \$2, updated_at = NOW\(\) WHERE id = \$1$/;
  const REMAINING = /^SELECT 1 FROM apartment_residencies WHERE person_id = \$1 AND is_current = TRUE LIMIT 1$/;
  const SNAPSHOT = /^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.full_name/;
  const PERSON_OFF = /^UPDATE site_people SET is_active = FALSE, user_code = NULL/;
  const VEHICLES_OFF = /^UPDATE vehicles SET is_active = FALSE WHERE person_id = \$1 AND is_active = TRUE RETURNING id, plate$/;
  const manager = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };

  const snapshotRow = { id: '5', user_code: 30001, is_active: true, full_name: null, phone: null, email: null, account_name: 'Ali', account_phone: null, account_email: 'ali@example.com' };

  it('(kullanici, daire) icin guncel iliskiler (her iki origin) "Tasindi" gibi biter, audit yapan yonetici adina (reason member_removed); son iliski ise kisi pasif + hesaptan kopar + araclar pasif', async () => {
    const client = scripted(
      [
        [RESIDENCIES, ok([{ id: '31', site_code: '1000000001', person_id: '5', relation: 'owner' }])],
        [END, ok()],
        [REMAINING, ok()],
        [SNAPSHOT, ok([snapshotRow])],
        [PERSON_OFF, ok([{ id: '5' }])],
        [VEHICLES_OFF, ok([{ id: '4', plate: '34ABC123' }])],
      ],
      { strict: true },
    );
    const ended = await endResidenciesForMemberRemoval(client, { apartmentId: 9, userCode: 30001, actor: manager });
    assert.equal(ended, 1);
    assert.deepEqual(find(client.log, RESIDENCIES).params, [9, 30001], 'yalniz O daire ve O kullanici');
    assert.equal(find(client.log, END).params[0], '31');
    assert.match(find(client.log, END).params[1], /^\d{4}-\d{2}-\d{2}$/);
    const audits = client.log.filter((q) => /^INSERT INTO audit_log/.test(q.sql));
    assert.deepEqual(audits.map((q) => q.params[3]), ['residency.ended', 'person.deactivated', 'vehicle.removed']);
    assert.equal(audits[0].params[0], 20001, 'audit yapan yonetici adina');
    assert.equal(JSON.parse(audits[0].params[7]).reason, 'member_removed');
    assert.equal(JSON.parse(audits[0].params[7]).apartment_id, 9);
    assert.equal(client.log[0].sql, 'SAVEPOINT crm_member_removal');
    assert.equal(client.log[client.log.length - 1].sql, 'RELEASE SAVEPOINT crm_member_removal');
    assert.deepEqual([Number(find(client.log, PERSON_OFF).params[0]), ...find(client.log, PERSON_OFF).params.slice(1)], [5, 'Ali', null, 'ali@example.com']);
  });

  it('kisinin baska guncel iliskisi kaliyorsa kisi aktif kalir (kopmaz, araclar pasiflesmez)', async () => {
    const client = scripted(
      [
        [RESIDENCIES, ok([{ id: '31', site_code: '1000000001', person_id: '5', relation: 'resident' }])],
        [END, ok()],
        [REMAINING, ok([{ x: 1 }])],
      ],
      { strict: true },
    );
    assert.equal(await endResidenciesForMemberRemoval(client, { apartmentId: 9, userCode: 30001, actor: manager }), 1);
    assert.equal(has(client.log, PERSON_OFF) || has(client.log, VEHICLES_OFF), false);
  });

  it('CRM kaydi olmayan kullanici: hicbir sey yazilmaz (0)', async () => {
    const client = scripted([[RESIDENCIES, ok()]], { strict: true });
    assert.equal(await endResidenciesForMemberRemoval(client, { apartmentId: 9, userCode: 30001, actor: manager }), 0);
    assert.equal(has(client.log, END), false);
  });

  it('GUVENLIK: hata daireden cikarma islemini BOZMAZ (SAVEPOINT\'e doner, firlatmaz, 0, loglanir)', async () => {
    const client = scripted(
      [
        [
          RESIDENCIES,
          () => {
            throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
          },
        ],
      ],
      { strict: true },
    );
    assert.equal(await endResidenciesForMemberRemoval(client, { apartmentId: 9, userCode: 30001, actor: manager }), 0);
    assert.ok(has(client.log, /^ROLLBACK TO SAVEPOINT crm_member_removal$/));
    assert.ok(has(client.log, /^RELEASE SAVEPOINT crm_member_removal$/));
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('daireden cikarma CRM yansimasi')));
  });
});

describe('S6: removeApartmentMember CRM kancasini AYNI transaction\'da cagirir; toggleApartmentMemberStatus (gecici pasife alma) CAGIRMAZ', () => {
  const superUser = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' };
  const aptRow = (resident) => ({ id: 3, site_code: 101, block_id: 1, unit_label: 'Daire 3', resident_user_code: resident, resident_pin_code: null });

  function setup({ resident = null, role = 'FAMILY_MEMBER' } = {}) {
    const poolScript = scripted([[/^SELECT a\.id, a\.site_code, a\.block_id/, ok([aptRow(resident)])]]);
    const clientScript = scripted([
      [/^SELECT id, site_code, resident_user_code FROM apartments/, ok([aptRow(resident)])],
      [/^UPDATE apartment_memberships SET is_active/, ok([{ role }])],
      [/^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r/, ok([{ id: '31', site_code: '101', person_id: '5', relation: 'resident' }])],
      [/^SELECT 1 FROM apartment_residencies WHERE person_id/, ok([{ x: 1 }])],
    ]);
    pool.query = poolScript.query;
    pool.connect = async () => ({ query: clientScript.query, release() {} });
    return { clientLog: clientScript.log };
  }

  it('removeApartmentMember: izin temizligi sonrasi, COMMIT\'ten ONCE iliskiler biter (apartments -> CRM sirasi); audit yapan yonetici adina', async () => {
    const { clientLog } = setup();
    await removeApartmentMember({ apartmentId: 3, targetUserCode: 20000, authUser: superUser });
    const hook = indexOf(clientLog, /^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r/);
    assert.ok(hook > indexOf(clientLog, /^UPDATE apartment_memberships SET is_active/), 'uyelik pasiflestikten sonra');
    assert.ok(hook > indexOf(clientLog, /^DELETE FROM door_access_overrides/), 'kapi izinleri temizlendikten sonra');
    assert.ok(hook < indexOf(clientLog, /^COMMIT$/), 'ayni transaction icinde');
    assert.ok(has(clientLog, /^UPDATE apartment_residencies SET is_current = FALSE/));
    const audit = clientLog.find((q) => /^INSERT INTO audit_log/.test(q.sql));
    assert.equal(audit.params[3], 'residency.ended');
    assert.equal(audit.params[0], 1);
  });

  it('toggleApartmentMemberStatus (geçici pasife alma): CRM iliskilerine DOKUNMAZ', async () => {
    const { clientLog } = setup({ resident: 20000, role: 'APARTMENT_ADMIN' });
    await toggleApartmentMemberStatus({ apartmentId: 3, targetUserCode: 20000, isActive: false, authUser: superUser });
    assert.equal(has(clientLog, /apartment_residencies|site_people/), false);
  });
});

describe('S3: handOverApartmentResident - indicatorOwnedByRemoved', () => {
  const OTHER_ADMIN = /AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/;
  const REMAINING = /^SELECT user_code FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE ORDER BY/;

  it('varsayilan (true) eski davranis: gosterge baska admine devredilir / en eski uye admin+gosterge / kimse yoksa gosterge+PIN temizlenir', async () => {
    let client = scripted([[OTHER_ADMIN, ok([{ user_code: 20001 }])]]);
    await handOverApartmentResident(client, 3, 20000);
    assert.deepEqual(find(client.log, /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2$/).params, [20001, 3]);

    client = scripted([[REMAINING, ok([{ user_code: 20002 }])]]);
    await handOverApartmentResident(client, 3, 20000);
    assert.ok(has(client.log, /^UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN'/));
    assert.deepEqual(find(client.log, /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2$/).params, [20002, 3]);

    client = scripted([]);
    await handOverApartmentResident(client, 3, 20000);
    assert.match(find(client.log, /^UPDATE apartments SET resident_user_code = NULL/).sql, /resident_pin_code = NULL/);
  });

  it('indicatorOwnedByRemoved=false: gosterge ve PIN\'e HIC dokunulmaz (admin rolu yine devredilir)', async () => {
    let client = scripted([[OTHER_ADMIN, ok([{ user_code: 20001 }])]]);
    await handOverApartmentResident(client, 3, 20000, { indicatorOwnedByRemoved: false });
    assert.equal(has(client.log, /^UPDATE apartments/), false);

    client = scripted([[REMAINING, ok([{ user_code: 20002 }])]]);
    await handOverApartmentResident(client, 3, 20000, { indicatorOwnedByRemoved: false });
    assert.ok(has(client.log, /^UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN'/), 'rol devri korunur');
    assert.equal(has(client.log, /^UPDATE apartments/), false);

    client = scripted([]);
    await handOverApartmentResident(client, 3, 20000, { indicatorOwnedByRemoved: false });
    assert.equal(has(client.log, /^UPDATE apartments/), false, 'baskasinin gostergesi/PIN\'i silinmez');
  });

  it('removeApartmentMember: gosterge cikarilan kisiye ait degilse (legacy=false) gosterge/PIN korunur', async () => {
    const superUser = { id: 1, user_code: 1, role: 'super_user' };
    const aptRow = { id: 3, site_code: 101, block_id: 1, unit_label: 'Daire 3', resident_user_code: 40000, resident_pin_code: '4821' };
    const poolScript = scripted([[/^SELECT a\.id, a\.site_code, a\.block_id/, ok([aptRow])]]);
    const clientScript = scripted([
      [/^SELECT id, site_code, resident_user_code FROM apartments/, ok([aptRow])],
      [/^UPDATE apartment_memberships SET is_active/, ok([{ role: 'APARTMENT_ADMIN' }])],
      [/AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/, ok([{ user_code: 20001 }])],
    ]);
    pool.query = poolScript.query;
    pool.connect = async () => ({ query: clientScript.query, release() {} });
    await removeApartmentMember({ apartmentId: 3, targetUserCode: 20000, authUser: superUser });
    assert.equal(has(clientScript.log, /^UPDATE apartments SET resident_user_code/), false, 'I\'nin (40000) gostergesi korunur');
  });
});
