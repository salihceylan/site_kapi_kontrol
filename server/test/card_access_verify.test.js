// Kartlı Geçiş cihaz yolu yardımcısı (DB'siz, sahte db): dört ret nedeni + kabul, UID normalizasyonu, modül kapalıyken kart sorgusu HİÇ gitmez, salt okunur (yazma yok).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { VERIFY_REASONS, decideCardVerification, verifyCardForDoor } from '../src/modules/card_access_verify.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const SITE = 1000000001;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function fakeDb({ moduleRow = null, cardRow = null } = {}) {
  const log = [];
  return {
    log,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
        assert.equal(params[1], 'card_access');
        return { rows: moduleRow ? [moduleRow] : [] };
      }
      if (/^SELECT c\.id, c\.person_id, c\.is_active, .* FROM access_cards c INNER JOIN site_people sp ON sp\.id = c\.person_id WHERE c\.site_code = \$1 AND c\.card_uid = \$2 ORDER BY c\.is_active DESC, c\.id DESC LIMIT 1$/.test(sql)) {
        return { rows: cardRow ? [cardRow] : [] };
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
}

describe('decideCardVerification (saf)', () => {
  it('dört ret nedeni sırayla: modül kapalı -> kart yok -> kart iptal -> kişi pasif; aksi halde ok + person_id sayısal', () => {
    assert.deepEqual([...VERIFY_REASONS], ['module_disabled', 'card_unknown', 'card_revoked', 'person_inactive']);
    assert.deepEqual(decideCardVerification({ moduleEnabled: false, card: { id: 1, person_id: 7, is_active: true }, personActive: true }), { ok: false, reason: 'module_disabled', person_id: null });
    assert.deepEqual(decideCardVerification({ moduleEnabled: true, card: null, personActive: true }), { ok: false, reason: 'card_unknown', person_id: null });
    assert.deepEqual(decideCardVerification({ moduleEnabled: true, card: { id: 1, person_id: '7', is_active: false }, personActive: true }), { ok: false, reason: 'card_revoked', person_id: 7 });
    assert.deepEqual(decideCardVerification({ moduleEnabled: true, card: { id: 1, person_id: '7', is_active: true }, personActive: false }), { ok: false, reason: 'person_inactive', person_id: 7 });
    assert.deepEqual(decideCardVerification({ moduleEnabled: true, card: { id: 1, person_id: '7', is_active: true }, personActive: true }), { ok: true, reason: null, person_id: 7 });
  });

  it('belirsiz girdiler güvenli tarafa düşer (undefined modül = kapalı, undefined kişi = pasif)', () => {
    assert.equal(decideCardVerification({ card: { id: 1, person_id: 7, is_active: true }, personActive: true }).reason, 'module_disabled');
    assert.equal(decideCardVerification({ moduleEnabled: true, card: { id: 1, person_id: 7, is_active: true } }).reason, 'person_inactive');
  });
});

describe('verifyCardForDoor (sahte db)', () => {
  it('modül satırı yok ya da kapalı: module_disabled ve kart sorgusu HİÇ gitmez', async () => {
    for (const moduleRow of [null, { enabled: false }]) {
      const db = fakeDb({ moduleRow });
      assert.deepEqual(await verifyCardForDoor({ siteCode: SITE, cardUid: '04A3B2C1', db }), { ok: false, reason: 'module_disabled', person_id: null });
      assert.equal(db.log.length, 1);
    }
  });

  it('modül açık: kart yok -> card_unknown; iptal -> card_revoked; kişi pasif -> person_inactive; aktif + güncel kişi -> ok', async () => {
    const open = { enabled: true };
    assert.deepEqual(await verifyCardForDoor({ siteCode: SITE, cardUid: '04A3B2C1', db: fakeDb({ moduleRow: open }) }), { ok: false, reason: 'card_unknown', person_id: null });
    assert.deepEqual(
      await verifyCardForDoor({ siteCode: SITE, cardUid: '04A3B2C1', db: fakeDb({ moduleRow: open, cardRow: { id: '3', person_id: '9', is_active: false, person_active: true } }) }),
      { ok: false, reason: 'card_revoked', person_id: 9 },
    );
    assert.deepEqual(
      await verifyCardForDoor({ siteCode: SITE, cardUid: '04A3B2C1', db: fakeDb({ moduleRow: open, cardRow: { id: '3', person_id: '9', is_active: true, person_active: false } }) }),
      { ok: false, reason: 'person_inactive', person_id: 9 },
    );
    assert.deepEqual(
      await verifyCardForDoor({ siteCode: SITE, cardUid: '04A3B2C1', db: fakeDb({ moduleRow: open, cardRow: { id: '3', person_id: '9', is_active: true, person_active: true } }) }),
      { ok: true, reason: null, person_id: 9 },
    );
  });

  it('UID okuyucu biçiminden kanonik biçime çevrilerek sorgulanır; geçersiz UID kart sorgusu atmadan card_unknown; geçersiz site module_disabled', async () => {
    const db = fakeDb({ moduleRow: { enabled: true }, cardRow: { id: '3', person_id: '9', is_active: true, person_active: true } });
    assert.equal((await verifyCardForDoor({ siteCode: String(SITE), cardUid: '04:a3:b2:c1', db })).ok, true);
    assert.deepEqual(db.log[1].params, [SITE, '04A3B2C1']);
    const bad = fakeDb({ moduleRow: { enabled: true } });
    assert.deepEqual(await verifyCardForDoor({ siteCode: SITE, cardUid: 'ab', db: bad }), { ok: false, reason: 'card_unknown', person_id: null });
    assert.equal(bad.log.length, 1);
    const noSite = fakeDb();
    assert.equal((await verifyCardForDoor({ siteCode: 'x', cardUid: '04A3B2C1', db: noSite })).reason, 'module_disabled');
    assert.equal(noSite.log.length, 0);
  });

  it('kaynak düzeyi: MQTT / door_access_policy içe aktarılmaz, yazan SQL yok (salt okunur)', () => {
    const source = readFileSync(path.join(here, '..', 'src', 'modules', 'card_access_verify.js'), 'utf8');
    assert.ok(!/from '[^']*(mqtt|door_access_policy)[^']*'/i.test(source), 'MQTT / door_access_policy içe aktarılmaz');
    assert.ok(!/\b(INSERT|UPDATE|DELETE|FOR UPDATE|FOR KEY SHARE)\b/.test(source));
  });
});
