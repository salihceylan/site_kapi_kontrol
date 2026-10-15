// Kisi ve Daire Kayitlari: daire silme anlik goruntusu (H6) ve gecmiste hassas alan degerlerinin saklanmamasi (H11) - DB'siz.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { recordApartmentDeletionSnapshot } from '../src/modules/apartment_deletion_audit.js';
import { scrubSensitiveChanges } from '../src/modules/people_history_service.js';
import { SENSITIVE_CHANGE_FIELDS } from '../src/modules/people_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = (relative) => readFileSync(path.join(here, '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

function scriptedClient({ apartment = null, residencies = [], vehicleCount = 0, failOn = null } = {}) {
  const log = [];
  return {
    log,
    async query(text, params) {
      const sql = norm(text);
      log.push({ sql, params });
      if (failOn && failOn.test(sql)) throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
      if (/^SAVEPOINT |^RELEASE SAVEPOINT |^ROLLBACK TO SAVEPOINT /.test(sql)) return ok();
      if (/^SELECT a\.id, a\.unit_label, a\.floor/.test(sql)) return apartment ? ok([apartment]) : ok();
      if (/FROM apartment_residencies r INNER JOIN site_people sp/.test(sql)) return ok(residencies);
      if (/COUNT\(DISTINCT v\.id\)/.test(sql)) return ok([{ vehicle_count: vehicleCount }]);
      if (/^INSERT INTO audit_log/.test(sql)) return ok();
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
}

const APARTMENT = {
  id: '9',
  unit_label: 'Daire 2',
  floor: 3,
  gross_area_m2: '120.50',
  net_area_m2: null,
  land_share_numerator: 35,
  land_share_denominator: 1000,
  category: '3+1',
  responsible_party: 'tenant',
  block_name: 'A Blok',
};

beforeEach(() => {
  mock.method(console, 'error', () => {});
});
afterEach(() => mock.restoreAll());

describe('H6: daire silinmeden once CRM kayitlarinin audit anlik goruntusu (apartment.deleted)', () => {
  it('iliski/arac/alan dolu daire: etiket, alanlar, iliskiler (ad, iliski, tarihler), arac sayisi; site_code dolu, hedef apartment', async () => {
    const client = scriptedClient({
      apartment: APARTMENT,
      residencies: [
        { person_name: 'Ali Veli', relation: 'owner', is_current: true, move_in_date: '2024-05-01', move_out_date: null },
        { person_name: 'Ayse Kaya', relation: 'tenant', is_current: false, move_in_date: '2022-01-01', move_out_date: '2024-04-30' },
      ],
      vehicleCount: 2,
    });
    const written = await recordApartmentDeletionSnapshot(client, { siteCode: 1000000001, apartmentId: 9, actor: { id: 20001, role: 'site_manager', full_name: 'Ayse Yonetici' } });
    assert.equal(written, true);
    const audit = client.log.find((q) => /^INSERT INTO audit_log/.test(q.sql));
    assert.equal(audit.params[3], 'apartment.deleted');
    assert.equal(audit.params[4], 1000000001, 'site_code dolu');
    assert.equal(audit.params[5], 'apartment');
    assert.equal(audit.params[6], '9');
    assert.equal(audit.params[0], 20001);
    assert.deepEqual(JSON.parse(audit.params[7]), {
      label: 'A Blok - Daire 2',
      floor: 3,
      gross_area_m2: 120.5,
      net_area_m2: null,
      land_share: { numerator: 35, denominator: 1000 },
      category: '3+1',
      responsible_party: 'tenant',
      residencies: [
        { name: 'Ali Veli', relation: 'owner', is_current: true, move_in_date: '2024-05-01', move_out_date: null },
        { name: 'Ayse Kaya', relation: 'tenant', is_current: false, move_in_date: '2022-01-01', move_out_date: '2024-04-30' },
      ],
      vehicle_count: 2,
    });
  });

  it('CRM kaydi OLMAYAN daire (bos alanlar, iliski/arac yok) icin audit yazilmaz', async () => {
    const client = scriptedClient({ apartment: { ...APARTMENT, floor: null, gross_area_m2: null, land_share_numerator: null, land_share_denominator: null, category: null, responsible_party: 'both' } });
    assert.equal(await recordApartmentDeletionSnapshot(client, { siteCode: 1000000001, apartmentId: 9 }), false);
    assert.equal(client.log.some((q) => /^INSERT INTO audit_log/.test(q.sql)), false);
  });

  it('yalniz iliskisi olan (alanlari bos) daire de kaydedilir; yalniz arac sayisi olan da', async () => {
    const bare = { ...APARTMENT, floor: null, gross_area_m2: null, land_share_numerator: null, land_share_denominator: null, category: null, responsible_party: 'both' };
    const withResidency = scriptedClient({ apartment: bare, residencies: [{ person_name: 'Ali', relation: 'resident', is_current: true, move_in_date: null, move_out_date: null }] });
    assert.equal(await recordApartmentDeletionSnapshot(withResidency, { siteCode: 1000000001, apartmentId: 9 }), true);
    const withVehicle = scriptedClient({ apartment: bare, vehicleCount: 1 });
    assert.equal(await recordApartmentDeletionSnapshot(withVehicle, { siteCode: 1000000001, apartmentId: 9 }), true);
  });

  it('GUVENLIK: sorgu hatasi daire azaltma islemini BOZMAZ (SAVEPOINT\'e doner, firlatmaz, false)', async () => {
    const client = scriptedClient({ apartment: APARTMENT, failOn: /COUNT\(DISTINCT v\.id\)/ });
    assert.equal(await recordApartmentDeletionSnapshot(client, { siteCode: 1000000001, apartmentId: 9 }), false);
    const sqls = client.log.map((q) => q.sql);
    assert.ok(sqls.some((s) => /^ROLLBACK TO SAVEPOINT/.test(s)));
    assert.ok(sqls.some((s) => /^RELEASE SAVEPOINT/.test(s)));
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('daire silme anlik goruntusu')));
  });

  it('SAVEPOINT kurulamazsa sessizce atlar (false)', async () => {
    const client = scriptedClient({ apartment: APARTMENT, failOn: /^SAVEPOINT/ });
    assert.equal(await recordApartmentDeletionSnapshot(client, { siteCode: 1000000001, apartmentId: 9 }), false);
  });

  it('site_service kancasi: silmeden ONCE cagrilir (engel koymaz), actor iletilir; cagiranlar actor verir', () => {
    const service = source('services/site_service.js');
    assert.match(service, /import \{ recordApartmentDeletionSnapshot \} from '\.\.\/modules\/apartment_deletion_audit\.js';/);
    const hook = service.indexOf('await recordApartmentDeletionSnapshot(client, { siteCode, apartmentId: Number(apartment.id), actor });');
    const del = service.indexOf('await client.query(`DELETE FROM apartments WHERE id = $1`');
    assert.ok(hook > 0 && del > hook, 'anlik goruntu DELETE\'ten once');
    // S10: goruntu ile DELETE arasi kilitsiz DEGIL - CRM yazmalariyla ayni site kilidi islemin basinda (BEGIN'den hemen sonra) alinir
    const siteLock = service.indexOf("await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);");
    const begin = service.indexOf("await client.query('BEGIN');", service.indexOf('export async function syncSiteStructureCounts'));
    assert.ok(begin > 0 && siteLock > begin && siteLock < hook, 'site kilidi BEGIN sonrasi ve anlik goruntuden once');
    assert.match(service, /import \{ peopleLockKey \} from '\.\.\/modules\/people_sync\.js';/);
    assert.match(service, /export async function syncSiteStructureCounts\(\{[\s\S]*?actor = null,\s*\}\) \{/);
    assert.match(source('routes/admin_routes.js'), /doorCount: doorCount \?\? Number\(existing\.door_count \?\? 1\),\s*actor: req\.authUser,/);
    assert.match(source('routes/manager_routes.js'), /doorCount: doorCount \?\? Number\(existing\.door_count \?\? 1\),\s*actor: req\.authUser,/);
  });
});

describe('H11: gecmiste telefon/e-posta/not degerleri saklanmaz ve donmez', () => {
  it('hassas alanlar: telefon, e-posta, not (yonetici ic notu)', () => {
    assert.deepEqual([...SENSITIVE_CHANGE_FIELDS].sort(), ['email', 'note', 'phone']);
  });

  it('scrubSensitiveChanges: eski surumlerden kalan satirlarda da from/to temizlenir; ad ve sayisal alanlar kalir', () => {
    const item = {
      id: 1,
      action: 'person.updated',
      details: {
        changes: [
          { field: 'full_name', from: 'Ali', to: 'Ali Veli' },
          { field: 'phone', from: '+905551112233', to: '+905321112233' },
          { field: 'email', from: 'a@example.com', to: 'b@example.com' },
          { field: 'note', from: 'gizli', to: 'yeni gizli' },
          { field: 'floor', from: 2, to: 3 },
        ],
      },
    };
    const scrubbed = scrubSensitiveChanges(item);
    assert.deepEqual(scrubbed.details.changes, [
      { field: 'full_name', from: 'Ali', to: 'Ali Veli' },
      { field: 'phone', changed: true },
      { field: 'email', changed: true },
      { field: 'note', changed: true },
      { field: 'floor', from: 2, to: 3 },
    ]);
    const serialized = JSON.stringify(scrubbed);
    for (const secret of ['5551112233', '5321112233', 'a@example.com', 'b@example.com', 'gizli']) {
      assert.equal(serialized.includes(secret), false, secret);
    }
    // girdi degismez; changes olmayan satirlar aynen doner
    assert.equal(item.details.changes[1].from, '+905551112233');
    const plain = { id: 2, action: 'person.created', details: { has_account: false } };
    assert.equal(scrubSensitiveChanges(plain), plain);
  });
});
