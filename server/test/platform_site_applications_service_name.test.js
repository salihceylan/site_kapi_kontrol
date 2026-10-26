// Site adı tekilliği (DB'siz, sahte bağlantı): site_name_key işleviyle ön denetim (Türkçe harf / boşluk farkına dayanıklı, reddedilmiş siteler hariç),
// yeniden adlandırma (updateSiteByCode) ve 23505 `error.constraint` eşlemesi; handleSiteMutationError'ın yanlış "site kodu çakışması" eşlemesi düzeldi;
// siteyi kalıcı silerken site teması (brand_themes) da silinir.
// Gerçek PostgreSQL davranışı (işlev + kısmi tekil indeksler): scripts/qa_platform_pg.mjs.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import {
  assertSiteNameAvailable,
  createSiteWithStructure as createCoreSite,
  siteNameConflictOrSame,
} from '../src/services/site_setup_core.js';
import { createSite, createSiteWithStructure, deleteSitePermanently, updateSiteByCode } from '../src/services/site_service.js';
import { handleSiteMutationError } from '../src/utils/validators.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => readFileSync(path.join(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const NAME_CHECK = /^SELECT site_code, name FROM sites WHERE site_name_key\(name\) = site_name_key\(\$1\) AND approval_status IS DISTINCT FROM 'rejected'/;

const dbError = (constraint) => Object.assign(new Error('duplicate key value violates unique constraint'), { code: '23505', constraint });

function scripted(handlers) {
  const log = [];
  return {
    log,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      for (const [pattern, handler] of handlers) {
        if (pattern.test(sql)) return typeof handler === 'function' ? handler(sql, params) : handler;
      }
      return ok();
    },
  };
}
const has = (log, regex) => log.some((q) => regex.test(q.sql));
const find = (log, regex) => log.find((q) => regex.test(q.sql));

describe('assertSiteNameAvailable / siteNameConflictOrSame', () => {
  it('site_name_key ile karşılaştırır, reddedilmiş siteleri saymaz; kendi site kodu hariç tutulabilir', async () => {
    const db = scripted([[NAME_CHECK, ok()]]);
    await assertSiteNameAvailable(db, '  Gül Sitesi ');
    assert.deepEqual(db.log[0].params, ['Gül Sitesi']);
    assert.equal(/site_code <> /.test(db.log[0].sql), false);
    await assertSiteNameAvailable(db, 'Gül Sitesi', { excludeSiteCode: 42 });
    assert.match(db.log[1].sql, /AND site_code <> \$2 LIMIT 1$/);
    assert.deepEqual(db.log[1].params, ['Gül Sitesi', 42]);
    assert.equal(/LOWER\(TRIM/.test(db.log[0].sql), false);
  });

  it('başka bir sitede kullanılıyorsa 409 SITE_NAME_EXISTS (istemciye güvenli düz Error)', async () => {
    const db = scripted([[NAME_CHECK, ok([{ site_code: 1, name: 'İpek Sitesi' }])]]);
    await assert.rejects(assertSiteNameAvailable(db, 'ipek sitesi'), (error) => {
      assert.equal(error.statusCode, 409);
      assert.equal(error.code, 'SITE_NAME_EXISTS');
      assert.match(error.message, /"ipek sitesi" adında bir site zaten mevcut/);
      return true;
    });
  });

  it('23505 yalnız ad indeksleri (yeni ve eski ad) için SITE_NAME_EXISTS olur; başka hata olduğu gibi döner', () => {
    for (const constraint of ['uq_sites_name_key', 'idx_sites_unique_name']) {
      const mapped = siteNameConflictOrSame(dbError(constraint), 'Gül');
      assert.equal(mapped.statusCode, 409);
      assert.equal(mapped.code, 'SITE_NAME_EXISTS');
    }
    const other = dbError('sites_mqtt_site_id_key');
    assert.equal(siteNameConflictOrSame(other, 'Gül'), other);
    const plain = new Error('x');
    assert.equal(siteNameConflictOrSame(plain, 'Gül'), plain);
  });
});

describe('site_setup_core.createSiteWithStructure (anlık kurulum + başvuru onayı ortak çekirdeği)', () => {
  const input = {
    siteName: 'Gül Sitesi', address: null, city: null, district: null,
    blocks: [{ name: 'A', apartmentCount: 2, sortOrder: 1 }], doors: [{ name: 'K', doorIndex: 1 }],
    totalBlockCount: 1, totalApartmentCount: 2, totalDoorCount: 1, blockApartmentCounts: [2],
  };
  const user = { id: 7, user_code: 48213, role: 'super_user' };

  it('ad başka sitede kullanılıyorsa INSERT\'ten ÖNCE 409 SITE_NAME_EXISTS', async () => {
    const client = scripted([[NAME_CHECK, ok([{ site_code: 5, name: 'gül sitesi' }])]]);
    await assert.rejects(createCoreSite(client, { user, input, managementType: 'apartment_site' }), (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS');
    assert.equal(has(client.log, /^INSERT INTO sites/), false);
  });

  it('ön denetimi geçen eşzamanlı çift istek: INSERT 23505 (ad indeksi) -> SITE_NAME_EXISTS; başka hata aynen yükselir', async () => {
    const client = scripted([[/^INSERT INTO sites/, () => { throw dbError('uq_sites_name_key'); }]]);
    await assert.rejects(createCoreSite(client, { user, input, managementType: 'apartment_site' }), (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS');
    const other = scripted([[/^INSERT INTO sites/, () => { throw Object.assign(new Error('boom'), { code: 'XX000' }); }]]);
    await assert.rejects(createCoreSite(other, { user, input, managementType: 'apartment_site' }), (e) => e.code === 'XX000');
  });
});

describe('site_service: oluşturma ve yeniden adlandırma', () => {
  let originalQuery;
  let originalConnect;
  beforeEach(() => {
    originalQuery = pool.query;
    originalConnect = pool.connect;
    mock.method(console, 'log', () => {});
  });
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    mock.restoreAll();
  });

  it('createSite: ad denetimi site_name_key; INSERT 23505 (ad indeksi) SITE_NAME_EXISTS', async () => {
    const db = scripted([[NAME_CHECK, ok()], [/^INSERT INTO sites/, () => { throw dbError('idx_sites_unique_name'); }]]);
    pool.query = db.query;
    await assert.rejects(createSite({ name: ' Gül Sitesi ', blockCount: 1, apartmentCount: 2 }), (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS');
    assert.deepEqual(find(db.log, NAME_CHECK).params, ['Gül Sitesi']);
    const taken = scripted([[NAME_CHECK, ok([{ site_code: 3, name: 'Gül Sitesi' }])]]);
    pool.query = taken.query;
    await assert.rejects(createSite({ name: 'Gül Sitesi', blockCount: 1, apartmentCount: 2 }), (e) => e.code === 'SITE_NAME_EXISTS');
    assert.equal(has(taken.log, /^INSERT INTO sites/), false);
  });

  it('createSiteWithStructure (admin / yönetici Site Ekle): aynı ad ROLLBACK ile 409; eşzamanlı çift istek 23505 de SITE_NAME_EXISTS', async () => {
    const taken = scripted([[NAME_CHECK, ok([{ site_code: 3, name: 'Gül' }])]]);
    pool.connect = async () => ({ query: taken.query, release() {} });
    await assert.rejects(
      createSiteWithStructure({ name: 'Gül', blockCount: 1, apartmentCount: 2, doorCount: 1 }),
      (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS',
    );
    assert.ok(has(taken.log, /^ROLLBACK$/));
    assert.equal(has(taken.log, /^INSERT INTO sites/), false);

    const race = scripted([[/^INSERT INTO sites/, () => { throw dbError('uq_sites_name_key'); }]]);
    pool.connect = async () => ({ query: race.query, release() {} });
    await assert.rejects(
      createSiteWithStructure({ name: 'Gül', blockCount: 1, apartmentCount: 2, doorCount: 1 }),
      (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS',
    );
    assert.ok(has(race.log, /^ROLLBACK$/));
  });

  it('updateSiteByCode: ad değişince AYNI denetim (kendi site kodu hariç) UPDATE\'ten önce; çakışma 409 ve UPDATE YOK', async () => {
    const taken = scripted([[NAME_CHECK, ok([{ site_code: 8, name: 'Başka' }])]]);
    pool.query = taken.query;
    await assert.rejects(updateSiteByCode({ siteCode: 42, name: 'Başka' }), (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS');
    assert.deepEqual(find(taken.log, NAME_CHECK).params, ['Başka', 42]);
    assert.equal(has(taken.log, /^UPDATE sites/), false);

    const free = scripted([[NAME_CHECK, ok()], [/^UPDATE sites SET name = \$1/, ok([{ id: 42, name: 'Yeni Ad' }])]]);
    pool.query = free.query;
    const updated = await updateSiteByCode({ siteCode: 42, name: 'Yeni Ad' });
    assert.equal(updated.name, 'Yeni Ad');
    assert.ok(free.log.findIndex((q) => NAME_CHECK.test(q.sql)) < free.log.findIndex((q) => /^UPDATE sites/.test(q.sql)));
  });

  it('updateSiteByCode: ad verilmezse ya da site reddedilmiş duruma alınıyorsa ad denetimi YOK; ön denetimi geçen eşzamanlı yeniden adlandırma 23505 -> 409', async () => {
    const noName = scripted([[/^UPDATE sites/, ok([{ id: 42 }])]]);
    pool.query = noName.query;
    await updateSiteByCode({ siteCode: 42, address: 'Cadde 1' });
    assert.equal(has(noName.log, NAME_CHECK), false);

    const rejected = scripted([[/^UPDATE sites/, ok([{ id: 42 }])]]);
    pool.query = rejected.query;
    await updateSiteByCode({ siteCode: 42, name: 'Başka', approvalStatus: 'rejected' });
    assert.equal(has(rejected.log, NAME_CHECK), false, 'reddedilmiş site tekillik dışı');

    const race = scripted([[NAME_CHECK, ok()], [/^UPDATE sites/, () => { throw dbError('uq_sites_name_key'); }]]);
    pool.query = race.query;
    await assert.rejects(updateSiteByCode({ siteCode: 42, name: 'Yarış' }), (e) => e.statusCode === 409 && e.code === 'SITE_NAME_EXISTS');
  });

  it('deleteSitePermanently: site teması (brand_themes, çok biçimli kapsam - FK/CASCADE yok) siteden ÖNCE ve aynı transaction\'da silinir', async () => {
    const client = scripted([
      [/^SELECT name FROM sites WHERE site_code = \$1 FOR UPDATE/, ok([{ name: 'Gül' }])],
      [/^DELETE FROM sites WHERE site_code = \$1/, ok([], 1)],
    ]);
    pool.connect = async () => ({ query: client.query, release() {} });
    pool.query = async () => ok();
    const result = await deleteSitePermanently(42, { id: 1, role: 'super_user' });
    assert.equal(result.deleted, true);
    const theme = client.log.findIndex((q) => /^DELETE FROM brand_themes WHERE scope_type = 'site' AND scope_id = \$1$/.test(q.sql));
    const site = client.log.findIndex((q) => /^DELETE FROM sites WHERE site_code = \$1/.test(q.sql));
    assert.ok(theme > 0 && theme < site && site < client.log.findIndex((q) => q.sql === 'COMMIT'));
    assert.deepEqual(client.log[theme].params, [42]);
  });
});

describe('handleSiteMutationError: 23505 eşlemesi', () => {
  const respond = (error) => {
    const res = { statusCode: 0, body: null, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    mock.method(console, 'error', () => {});
    try {
      handleSiteMutationError(error, res, 'Genel hata');
    } finally {
      mock.restoreAll();
    }
    return res;
  };

  it('site adı indeksleri (yeni / eski) "site kodu" çakışması DEĞİL, SITE_NAME_EXISTS olarak 409 döner', () => {
    for (const constraint of ['uq_sites_name_key', 'idx_sites_unique_name']) {
      const res = respond(dbError(constraint));
      assert.equal(res.statusCode, 409);
      assert.equal(res.body.code, 'SITE_NAME_EXISTS');
      assert.equal(/Site kodu/i.test(res.body.error), false);
      assert.match(res.body.error, /site zaten mevcut/);
    }
  });

  it('bekleyen başvuru adı indeksleri SITE_APPLICATION_NAME_PENDING; bilinmeyen kısıt eski genel mesajı korur', () => {
    for (const constraint of ['uq_site_applications_pending_name_key', 'idx_site_applications_pending_unique_name']) {
      const res = respond(dbError(constraint));
      assert.equal(res.statusCode, 409);
      assert.equal(res.body.code, 'SITE_APPLICATION_NAME_PENDING');
    }
    const other = respond(dbError('sites_mqtt_site_id_key'));
    assert.equal(other.statusCode, 409);
    assert.deepEqual(other.body, { error: 'Site kodu olusturulurken cakisma oldu.' });
    const email = respond(dbError('users_email_key'));
    assert.equal(email.statusCode, 409);
    assert.match(email.body.error, /e-postasi/);
  });
});

describe('kaynak: ad denetimi eski LOWER(TRIM(..)) karşılaştırmasını kullanmaz', () => {
  it('site_service / site_setup_core / site_application_service site_name_key kullanır', () => {
    for (const file of ['src/services/site_service.js', 'src/services/site_setup_core.js', 'src/modules/site_application_service.js']) {
      assert.equal(/LOWER\(TRIM\(/.test(read(file)), false, file);
    }
    assert.match(read('src/modules/site_application_service.js'), /site_name_key\(site_name\) = site_name_key\(\$1\)/);
    assert.match(read('src/services/site_setup_core.js'), /site_name_key\(name\) = site_name_key\(\$1\)/);
  });

  it('createSiteApplication: kullanıcının kendi bekleyen başvurusu ad denetimlerinden ÖNCE bakılır', () => {
    const source = read('src/modules/site_application_service.js');
    const start = source.indexOf('export async function createSiteApplication');
    const body = source.slice(start, source.indexOf('\n/**', start));
    const own = body.indexOf("a.applicant_user_code = $1 AND a.status = 'pending' LIMIT 1");
    const siteName = body.indexOf('FROM sites WHERE site_name_key');
    const appName = body.indexOf("FROM site_applications WHERE status = 'pending' AND site_name_key");
    assert.ok(own > 0 && own < siteName && siteName < appName);
  });
});
