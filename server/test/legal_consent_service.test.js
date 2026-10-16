// Yasal belge onay servisi (DB'siz, sahte veritabanı): accepted_documents doğrulaması, zorunluluk (legal.enforce_consents) açık / kapalı,
// bekleyen kayıt JSON'u, user_consents yazımı, pending hesabı, POST /me/consents hata kodları.
import { describe, it, beforeEach, afterEach, before, after, mock } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { clearLegalCache } from '../src/modules/legal_documents.js';
import {
  MAX_ACCEPTED_DOCUMENTS,
  acceptDocuments,
  computePending,
  getConsentState,
  normalizeAcceptedDocuments,
  pendingConsentsJson,
  recordConsents,
  resolveAcceptedDocuments,
  sanitizeStoredConsents,
  siteApplicationConsents,
} from '../src/modules/legal_consent_service.js';
import { isPlatformError } from '../src/modules/errors.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(here, 'fixtures', 'legal');

const FULL = {
  'legal.company_name': 'Örnek A.Ş.',
  'legal.company_address': 'Ankara',
  'legal.mersis_no': '0123456789012345',
  'legal.kep_address': 'ornek@hs01.kep.tr',
  'legal.contact_email': 'info@example.com',
  'legal.contact_phone': '+90 312 000 00 00',
};

// Sahte veritabanı: platform_settings okuma + user_consents yazma / okuma.
function fakeDb({ settings = {}, failSettings = false } = {}) {
  const log = [];
  const consents = [];
  return {
    log,
    consents,
    async query(text, params = []) {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      log.push({ sql, params });
      if (/FROM platform_settings WHERE key = ANY/.test(sql)) {
        if (failSettings) throw Object.assign(new Error('db kesildi'), { code: '57P01' });
        return { rows: Object.entries(settings).map(([key, value]) => ({ key, value })), rowCount: Object.keys(settings).length };
      }
      if (/^INSERT INTO user_consents/.test(sql)) {
        const [userCode, ids, versions, ats, source] = params;
        let added = 0;
        ids.forEach((id, index) => {
          if (!consents.some((c) => c.user_code === userCode && c.document_id === id && c.version === versions[index])) {
            consents.push({ user_code: userCode, document_id: id, version: versions[index], accepted_at: new Date(ats[index]), source });
            added += 1;
          }
        });
        return { rows: [], rowCount: added };
      }
      if (/^SELECT document_id, version, accepted_at FROM user_consents/.test(sql)) {
        const rows = consents.filter((c) => c.user_code === params[0]).sort((a, b) => b.accepted_at - a.accepted_at);
        return { rows, rowCount: rows.length };
      }
      throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    },
  };
}

before(() => {
  process.env.LEGAL_DIR = FIXTURES;
});
after(() => {
  delete process.env.LEGAL_DIR;
});
beforeEach(() => {
  clearLegalCache();
  mock.method(console, 'error', () => {});
});
afterEach(() => {
  mock.restoreAll();
});

const rejects = async (promise, code, statusCode) => {
  try {
    await promise;
  } catch (error) {
    assert.ok(isPlatformError(error), `PlatformError bekleniyordu: ${error?.stack}`);
    assert.equal(error.code, code);
    if (statusCode) assert.equal(error.statusCode, statusCode);
    return error;
  }
  throw new assert.AssertionError({ message: `${code} bekleniyordu, hata yok` });
};

describe('normalizeAcceptedDocuments', () => {
  it('yok / null -> []; geçerli öğeler kırpılır; aynı belgede ilk giriş geçerli', () => {
    assert.deepEqual(normalizeAcceptedDocuments(undefined), []);
    assert.deepEqual(normalizeAcceptedDocuments(null), []);
    assert.deepEqual(normalizeAcceptedDocuments([]), []);
    assert.deepEqual(
      normalizeAcceptedDocuments([{ id: ' terms ', version: ' 2026-10-01 ' }, { id: 'terms', version: 'x' }, { id: 'privacy', version: 'v1' }]),
      [{ id: 'terms', version: '2026-10-01' }, { id: 'privacy', version: 'v1' }],
    );
  });

  it('dizi değil, 20\'den uzun ya da biçimsiz öğe -> 400 INVALID_ACCEPTED_DOCUMENTS', async () => {
    for (const bad of ['terms', {}, 5, true]) {
      assert.throws(() => normalizeAcceptedDocuments(bad), (error) => error.code === 'INVALID_ACCEPTED_DOCUMENTS' && error.statusCode === 400);
    }
    const tooMany = Array.from({ length: MAX_ACCEPTED_DOCUMENTS + 1 }, (_, i) => ({ id: `doc_${i}`, version: 'v1' }));
    assert.throws(() => normalizeAcceptedDocuments(tooMany), (error) => error.code === 'INVALID_ACCEPTED_DOCUMENTS');
    for (const item of [null, 'terms', {}, { id: 'terms' }, { version: 'v1' }, { id: 5, version: 'v1' }, { id: 'terms', version: 5 }, { id: 'Terms!', version: 'v1' }, { id: 'terms', version: 'a b' }, { id: 'terms', version: 'x'.repeat(41) }, { id: "t'; DROP", version: 'v1' }]) {
      assert.throws(() => normalizeAcceptedDocuments([item]), (error) => error.code === 'INVALID_ACCEPTED_DOCUMENTS', JSON.stringify(item));
    }
  });
});

describe('resolveAcceptedDocuments: zorunluluk KAPALI (varsayılan)', () => {
  it('hiçbir şey gelmese de geçer; records boş', async () => {
    const db = fakeDb({ settings: FULL });
    const result = await resolveAcceptedDocuments({ raw: undefined, context: 'register', db });
    assert.deepEqual(result, { records: [], enforced: false });
  });

  it('yalnız bilinen, tamamlanmış, onay istenen belgelerin GÜNCEL sürümü kaydedilir; eski / bilinmeyen / bilgi amaçlı / eksik belge sessizce atlanır', async () => {
    const db = fakeDb({ settings: FULL });
    const result = await resolveAcceptedDocuments({
      raw: [
        { id: 'terms', version: '2026-10-01' },
        { id: 'privacy', version: 'ESKI' },
        { id: 'kvkk_notice', version: '2026-10-16' },
        { id: 'yok_boyle', version: 'v1' },
        { id: 'evil', version: 'x1' },
        { id: 'account_deletion', version: '2026-10-16' },
        { id: 'draft_notice', version: 'v1' },
      ],
      context: 'register',
      db,
    });
    assert.deepEqual(result.records, [
      { id: 'terms', version: '2026-10-01' },
      { id: 'kvkk_notice', version: '2026-10-16' },
    ]);
    assert.equal(result.enforced, false);
  });

  it('şirket bilgisi eksikse (belge complete:false) o belgenin onayı kaydedilmez', async () => {
    const db = fakeDb({ settings: {} });
    const result = await resolveAcceptedDocuments({ raw: [{ id: 'privacy', version: '2026-10-16' }, { id: 'dpa', version: '2026-10-05' }], context: 'register', db });
    assert.deepEqual(result.records, [{ id: 'dpa', version: '2026-10-05' }]);
  });

  it('biçimsiz accepted_documents her durumda 400', async () => {
    await rejects(resolveAcceptedDocuments({ raw: 'terms', context: 'register', db: fakeDb() }), 'INVALID_ACCEPTED_DOCUMENTS', 400);
  });

  it('ayar okunamazsa hata YUKARI gider (zorunluluk sessizce "kapalı" sayılmaz)', async () => {
    await assert.rejects(resolveAcceptedDocuments({ raw: [], context: 'register', db: fakeDb({ failSettings: true }) }), /db kesildi/);
  });
});

describe('resolveAcceptedDocuments: zorunluluk AÇIK', () => {
  const enforced = (extra = {}) => fakeDb({ settings: { ...FULL, 'legal.enforce_consents': true, ...extra } });

  it('register: eksik belgeler 400 CONSENT_REQUIRED { missing } (belge sırasıyla); tamamlanmamış belge istenmez', async () => {
    const error = await rejects(resolveAcceptedDocuments({ raw: [], context: 'register', db: enforced() }), 'CONSENT_REQUIRED', 400);
    assert.deepEqual(error.extra, { missing: ['terms', 'privacy', 'kvkk_notice'] });
    assert.ok(!error.extra.missing.includes('draft_notice'), 'taslak (complete:false) belge istenmez');
    assert.ok(!error.extra.missing.includes('dpa'), 'dpa yalnız site başvurusu için');
  });

  it('eski sürüm "eksik" sayılır; bir kısmı varsa yalnız kalanlar missing', async () => {
    const error = await rejects(
      resolveAcceptedDocuments({
        raw: [{ id: 'terms', version: 'ESKI' }, { id: 'privacy', version: '2026-10-16' }, { id: 'kvkk_notice', version: '2026-10-16' }],
        context: 'register',
        db: enforced(),
      }),
      'CONSENT_REQUIRED',
    );
    assert.deepEqual(error.extra.missing, ['terms']);
  });

  it('hepsi güncelse geçer ve kayıtlar döner', async () => {
    const result = await resolveAcceptedDocuments({
      raw: [{ id: 'terms', version: '2026-10-01' }, { id: 'privacy', version: '2026-10-16' }, { id: 'kvkk_notice', version: '2026-10-16' }],
      context: 'register',
      db: enforced(),
    });
    assert.equal(result.enforced, true);
    assert.equal(result.records.length, 3);
  });

  it('site_application bağlamı: terms + dpa istenir (register belgeleri değil)', async () => {
    const error = await rejects(resolveAcceptedDocuments({ raw: [], context: 'site_application', db: enforced() }), 'CONSENT_REQUIRED');
    assert.deepEqual(error.extra.missing, ['terms', 'dpa']);
    const ok = await resolveAcceptedDocuments({ raw: [{ id: 'terms', version: '2026-10-01' }, { id: 'dpa', version: '2026-10-05' }], context: 'site_application', db: enforced() });
    assert.equal(ok.records.length, 2);
  });

  it('belge tamamlanmamışsa zorunluluk AÇIK olsa da o belge istenmez (şirket bilgisi eksik)', async () => {
    const db = fakeDb({ settings: { 'legal.enforce_consents': true, 'legal.company_name': 'Örnek A.Ş.' } });
    const error = await rejects(resolveAcceptedDocuments({ raw: [], context: 'register', db }), 'CONSENT_REQUIRED');
    assert.deepEqual(error.extra.missing, ['kvkk_notice'], 'yer tutucusu dolu olmayan terms/privacy istenmez');
  });

  it('elle SQL ile yazılan "on" / "true" / 1 değerleri de açık sayılır; "off" / false kapalı', async () => {
    for (const value of ['on', 'true', '1', 'yes', 1, true]) {
      const db = fakeDb({ settings: { ...FULL, 'legal.enforce_consents': value } });
      await rejects(resolveAcceptedDocuments({ raw: [], context: 'register', db }), 'CONSENT_REQUIRED');
    }
    for (const value of ['off', 'false', '0', false, 0, null, 'açık']) {
      const db = fakeDb({ settings: { ...FULL, 'legal.enforce_consents': value } });
      assert.equal((await resolveAcceptedDocuments({ raw: [], context: 'register', db })).enforced, false, String(value));
    }
  });
});

describe('bekleyen kayıt JSON\'u', () => {
  it('kayıt yoksa null; varsa {id, version, accepted_at} dizisi', () => {
    assert.equal(pendingConsentsJson([]), null);
    assert.equal(pendingConsentsJson(null), null);
    const now = new Date('2026-10-16T10:00:00.000Z');
    assert.deepEqual(JSON.parse(pendingConsentsJson([{ id: 'terms', version: 'v1' }], now)), [{ id: 'terms', version: 'v1', accepted_at: '2026-10-16T10:00:00.000Z' }]);
  });

  it('sanitizeStoredConsents: bozuk girdiler atılır, mükerrer tek, geleceğe / çok eskiye ait zaman "şimdi" olur; metin JSON da okunur', () => {
    const now = new Date('2026-10-16T10:00:00.000Z');
    const stored = [
      { id: 'terms', version: 'v1', accepted_at: '2026-10-16T09:00:00.000Z' },
      { id: 'terms', version: 'v2', accepted_at: '2026-10-16T09:00:00.000Z' },
      { id: 'privacy', version: 'v1', accepted_at: '2099-01-01T00:00:00.000Z' },
      { id: 'dpa', version: 'v1', accepted_at: '2020-01-01T00:00:00.000Z' },
      { id: 'kvkk_notice', version: 'v1', accepted_at: 'zaman değil' },
      { id: 'BOZUK!', version: 'v1' },
      { id: 'x', version: 'v1' },
      null,
      'metin',
    ];
    const result = sanitizeStoredConsents(stored, now);
    assert.deepEqual(result.map((r) => r.id), ['terms', 'privacy', 'dpa', 'kvkk_notice']);
    assert.equal(result[0].accepted_at, '2026-10-16T09:00:00.000Z');
    assert.equal(result[1].accepted_at, now.toISOString());
    assert.equal(result[2].accepted_at, now.toISOString());
    assert.equal(result[3].accepted_at, now.toISOString());
    assert.deepEqual(sanitizeStoredConsents(JSON.stringify([stored[0]]), now).map((r) => r.id), ['terms']);
    for (const junk of [null, undefined, 'bozuk json {', 5, {}, '{}']) {
      assert.deepEqual(sanitizeStoredConsents(junk, now), []);
    }
  });
});

describe('recordConsents', () => {
  it('boş listede sorgu YOK; doluda tek INSERT ... unnest ... ON CONFLICT DO NOTHING; yeni satır sayısı döner', async () => {
    const db = fakeDb();
    assert.equal(await recordConsents(db, 5, [], 'register'), 0);
    assert.equal(db.log.length, 0);
    const added = await recordConsents(db, 5, [{ id: 'terms', version: 'v1', accepted_at: '2026-10-16T09:00:00.000Z' }, { id: 'privacy', version: 'v1' }], 'register');
    assert.equal(added, 2);
    assert.equal(db.log.length, 1);
    assert.match(db.log[0].sql, /^INSERT INTO user_consents \(user_code, document_id, version, accepted_at, source\) SELECT .* FROM unnest\(.*\) AS d\(document_id, version, accepted_at\) ON CONFLICT \(user_code, document_id, version\) DO NOTHING$/);
    assert.deepEqual(db.log[0].params.slice(0, 3), [5, ['terms', 'privacy'], ['v1', 'v1']]);
    assert.equal(db.log[0].params[4], 'register');
    assert.equal(db.log[0].params[3][0], '2026-10-16T09:00:00.000Z');
    // tekrar onay yinelenen satır üretmez
    assert.equal(await recordConsents(db, 5, [{ id: 'terms', version: 'v1' }], 'in_app'), 0);
    assert.equal(db.consents.length, 2);
  });
});

describe('computePending', () => {
  const docs = [
    { id: 'terms', title: 'Koşullar', version: 'v2', complete: true, required_for: ['register', 'site_application'] },
    { id: 'privacy', title: 'Gizlilik', version: 'v1', complete: true, required_for: ['register'] },
    { id: 'dpa', title: 'DPA', version: 'v3', complete: true, required_for: ['site_application'] },
    { id: 'draft', title: 'Taslak', version: 'v1', complete: false, required_for: ['register'] },
    { id: 'info', title: 'Bilgi', version: 'v1', complete: true, required_for: [] },
  ];

  it('hiç onay yoksa: yalnız tamamlanmış kayıt belgeleri (site başvurusu belgesi, taslak, bilgi sayfası değil)', () => {
    assert.deepEqual(computePending(docs, []), [
      { id: 'terms', title: 'Koşullar', version: 'v2' },
      { id: 'privacy', title: 'Gizlilik', version: 'v1' },
    ]);
  });

  it('güncel sürüm onaylıysa çıkar; eski sürüm onaylıysa yeniden bekler; site başvurusu belgesi daha önce onaylandıysa sürüm yenilenince bekler', () => {
    const consents = [
      { document_id: 'terms', version: 'v1', accepted_at: 'x' },
      { document_id: 'privacy', version: 'v1', accepted_at: 'x' },
      { document_id: 'dpa', version: 'v2', accepted_at: 'x' },
    ];
    assert.deepEqual(computePending(docs, consents).map((d) => d.id), ['terms', 'dpa']);
    assert.deepEqual(
      computePending(docs, [{ document_id: 'terms', version: 'v2' }, { document_id: 'privacy', version: 'v1' }, { document_id: 'dpa', version: 'v3' }]),
      [],
    );
  });
});

describe('acceptDocuments (POST /me/consents)', () => {
  const settings = { ...FULL };

  it('başarı: kayıt source=in_app ile yazılır; güncel { consents, pending } döner', async () => {
    const db = fakeDb({ settings });
    const result = await acceptDocuments({ userCode: 42, documents: [{ id: 'terms', version: '2026-10-01' }, { id: 'privacy', version: '2026-10-16' }], db });
    assert.deepEqual(result.consents.map((c) => c.document_id).sort(), ['privacy', 'terms']);
    assert.deepEqual(Object.keys(result.consents[0]).sort(), ['accepted_at', 'document_id', 'version']);
    assert.deepEqual(result.pending, [{ id: 'kvkk_notice', title: 'KVKK Aydınlatma Metni', version: '2026-10-16' }]);
    assert.ok(db.consents.every((c) => c.source === 'in_app' && c.user_code === 42));
    assert.ok(typeof result.consents[0].accepted_at === 'string' && result.consents[0].accepted_at.endsWith('Z'));
  });

  it('boş / dizi olmayan documents -> 400 INVALID_BODY; biçimsiz öğe -> 400 INVALID_ACCEPTED_DOCUMENTS', async () => {
    for (const bad of [undefined, [], 'terms', {}]) {
      await rejects(acceptDocuments({ userCode: 1, documents: bad, db: fakeDb({ settings }) }), 'INVALID_BODY', 400);
    }
    await rejects(acceptDocuments({ userCode: 1, documents: [{ id: 'terms' }], db: fakeDb({ settings }) }), 'INVALID_ACCEPTED_DOCUMENTS', 400);
  });

  it('bilinmeyen ve bilgi amaçlı (required_for boş) belge -> 400 DOCUMENT_NOT_ACCEPTABLE; hiçbir şey yazılmaz', async () => {
    for (const id of ['yok_boyle', 'account_deletion', 'evil']) {
      const db = fakeDb({ settings });
      const error = await rejects(acceptDocuments({ userCode: 1, documents: [{ id: 'terms', version: '2026-10-01' }, { id, version: 'x1' }], db }), 'DOCUMENT_NOT_ACCEPTABLE', 400);
      assert.equal(error.extra.document_id, id);
      assert.equal(db.consents.length, 0, 'hepsi ya da hiçbiri');
    }
  });

  it('tamamlanmamış belge -> 409 DOCUMENT_INCOMPLETE', async () => {
    const db = fakeDb({ settings: {} });
    const error = await rejects(acceptDocuments({ userCode: 1, documents: [{ id: 'privacy', version: '2026-10-16' }], db }), 'DOCUMENT_INCOMPLETE', 409);
    assert.equal(error.extra.document_id, 'privacy');
    assert.equal(db.consents.length, 0);
  });

  it('güncel olmayan sürüm -> 409 CONSENT_VERSION_STALE { stale: [{id, current_version}] }; hiçbir şey yazılmaz', async () => {
    const db = fakeDb({ settings });
    const error = await rejects(
      acceptDocuments({ userCode: 1, documents: [{ id: 'terms', version: '2026-10-01' }, { id: 'privacy', version: 'ESKI' }, { id: 'kvkk_notice', version: 'ESKI' }], db }),
      'CONSENT_VERSION_STALE',
      409,
    );
    assert.deepEqual(error.extra.stale, [{ id: 'privacy', current_version: '2026-10-16' }, { id: 'kvkk_notice', current_version: '2026-10-16' }]);
    assert.equal(db.consents.length, 0);
  });

  it('getConsentState: kullanıcının onayları + pending', async () => {
    const db = fakeDb({ settings });
    await acceptDocuments({ userCode: 7, documents: [{ id: 'terms', version: '2026-10-01' }], db });
    await acceptDocuments({ userCode: 8, documents: [{ id: 'privacy', version: '2026-10-16' }], db });
    const state = await getConsentState(7, { db });
    assert.deepEqual(state.consents.map((c) => c.document_id), ['terms']);
    assert.deepEqual(state.pending.map((d) => d.id), ['privacy', 'kvkk_notice']);
  });
});

describe('siteApplicationConsents kancası', () => {
  it('check: site_application bağlamı ve verilen client\'ı kullanır; record: source=site_application', async () => {
    const db = fakeDb({ settings: { ...FULL, 'legal.enforce_consents': 'on' } });
    await rejects(siteApplicationConsents.check(db, undefined), 'CONSENT_REQUIRED', 400);
    assert.ok(db.log.every((entry) => /platform_settings/.test(entry.sql)), 'yalnız verilen client kullanılır');
    const plan = await siteApplicationConsents.check(db, [{ id: 'terms', version: '2026-10-01' }, { id: 'dpa', version: '2026-10-05' }]);
    await siteApplicationConsents.record(db, 9, plan);
    assert.deepEqual(db.consents.map((c) => [c.document_id, c.source]).sort(), [['dpa', 'site_application'], ['terms', 'site_application']]);
  });
});
