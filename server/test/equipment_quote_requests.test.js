// Firma teklif formu (113, P2-8): dis firma icin bagimsiz, tek kullanimlik form -> TASLAK teklif -> yonetici onayi.
// Kapsam (DB'siz, KATI sahte veritabani: tanimsiz SQL firlatir; gercek Express):
//  - sema <-> migration 113 birebir, yalniz yeni tablo (equipment_quotes'a / gider / sozlesmeye dokunmaz), db.js baglantisi, katalog kontrollu ensure,
//  - belirtec: DB'de YALNIZ SHA-256 ozeti, baglanti yalniz olusturma yanitinda, liste belirtec / ozet tasimaz,
//  - tek kullanim (ikinci gonderim 410), gecersiz alan belirteci tuketmez, suresi dolmus / iptal edilmis / modul kapali baglanti ayni 410,
//  - firma girisi TASLAK: teklif / gider / sozlesme OLUSMAZ; onay yalniz ACIK teklif uretir (kabul ayri karar), cift onay 409, ret / iptal,
//  - sayfa: nonce'lu kati CSP, sunucu degerleri kacisli, herkese acik rotalar kimlik katmaninin ARKASINDA DEGIL (hiz sinirli), yonetici rotalari yazma yetkili.
// Gercek SQL (CHECK / FK / es zamanli tek kullanim): migrations/113_equipment_quote_requests.sql (deploy provasinda gercek PostgreSQL).
import { describe, it, beforeEach, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { maskSensitiveUrl } from '../src/middlewares/request_logger.js';
import * as svc from '../src/modules/equipment_service.js';
import { equipmentPublicRouter } from '../src/modules/equipment_routes.js';
import { renderQuoteFormPage } from '../src/modules/equipment_quote_form_page.js';
import { QUOTE_REQUEST_STEPS, ensureQuoteRequestSchema, quoteRequestMigrationBody } from '../src/modules/equipment_quote_schema.js';
import { SITE_AUDIT_LABELS } from '../src/modules/site_audit_log_catalog.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => String(s).replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const read = (...parts) => readFileSync(path.join(here, '..', ...parts), 'utf8');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '113_equipment_quote_requests.sql'), 'utf8');
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

const SITE = 1000000001;
const actor = { user_code: 20001, userCode: 20001, id: 20001, role: 'site_manager', full_name: 'Yönetici' };
const access = { canWrite: true, userCode: 20001 };

let store;
const makeStore = () => ({ requests: [], quotes: [], audits: [], log: [], nextId: 100, moduleEnabled: true });

function quoteRow(over) {
  return {
    id: 0, site_code: SITE, topic: '', vendor_name: '', amount_kurus: 0, valid_until: null, document_note: null, equipment_id: null, status: 'open', accepted_as: null,
    expense_id: null, contract_id: null, decided_at: null, created_at: new Date('2026-10-29T08:00:00Z'), delivery_days: null, note: null, vat_included: null,
    revision_no: 1, previous_id: null, revision_reason: null, ...over,
  };
}

async function fakeQuery(text, params = []) {
  const sql = String(text).replace(/\s+/g, ' ').trim();
  store.log.push(sql);
  const ok = (rows = []) => ({ rows, rowCount: rows.length });
  const byId = (id, site) => store.requests.find((x) => x.id === Number(id) && x.site_code === Number(site));
  const byHash = (hash) => store.requests.find((x) => x.token_hash === hash);
  if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
  if (/^INSERT INTO audit_log/.test(sql)) {
    store.audits.push({ actor_name: params[1], action: params[3], site_code: params[4], target_id: params[6], details: JSON.parse(params[7]) });
    return ok();
  }
  if (/^SELECT enabled FROM site_modules/.test(sql)) return ok([{ enabled: store.moduleEnabled }]);
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM equipment_quote_requests/.test(sql)) {
    const now = Date.now();
    return ok([{ n: store.requests.filter((x) => x.site_code === Number(params[0]) && (x.status === 'draft' || (x.status === 'invited' && x.expires_at.getTime() > now))).length }]);
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM equipment_quotes/.test(sql)) return ok([{ n: store.quotes.length }]);
  if (/^INSERT INTO equipment_quote_requests/.test(sql)) {
    const [site, topic, equipmentId, hint, tokenHash, days, createdBy] = params;
    store.nextId += 1;
    const r = {
      id: store.nextId, site_code: site, topic, equipment_id: equipmentId, vendor_hint: hint, token_hash: tokenHash, status: 'invited',
      expires_at: new Date(Date.now() + days * 86400000), created_by: createdBy, created_at: new Date(), submitted_at: null, vendor_name: null, vendor_contact: null, vendor_phone: null,
      amount_kurus: null, valid_until: null, delivery_days: null, note: null, vat_included: null, decided_by: null, decided_at: null, quote_id: null,
    };
    store.requests.push(r);
    return ok([{ id: r.id }]);
  }
  if (/^SELECT r\.id, r\.topic, r\.equipment_id, r\.vendor_hint.* FROM equipment_quote_requests r WHERE r\.id = \$1 AND r\.site_code = \$2$/.test(sql)) {
    const r = byId(params[0], params[1]);
    return ok(r ? [{ ...r }] : []);
  }
  if (/^SELECT r\.id, r\.topic, r\.equipment_id, r\.vendor_hint.* FROM equipment_quote_requests r WHERE r\.site_code = \$1 AND \(\$2::TEXT IS NULL OR r\.status = \$2\) ORDER BY r\.id DESC LIMIT 200$/.test(sql)) {
    return ok(store.requests.filter((x) => x.site_code === Number(params[0]) && (params[1] === null || x.status === params[1])).map((x) => ({ ...x })).reverse());
  }
  const close = /^UPDATE equipment_quote_requests SET status = '(revoked|rejected)', decided_by = \$3, decided_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = '(invited|draft)' RETURNING id$/.exec(sql);
  if (close) {
    const r = byId(params[0], params[1]);
    if (!r || r.status !== close[2]) return ok();
    Object.assign(r, { status: close[1], decided_by: params[2], decided_at: new Date() });
    return ok([{ id: r.id }]);
  }
  if (/FROM equipment_quote_requests r WHERE r\.id = \$1 AND r\.site_code = \$2 FOR UPDATE$/.test(sql)) {
    const r = byId(params[0], params[1]);
    return ok(r ? [{ ...r }] : []);
  }
  if (/^INSERT INTO equipment_quotes/.test(sql)) {
    const [site, topic, vendor, amount, validUntil, docNote, equipmentId, createdBy, delivery, note, vat] = params;
    store.nextId += 1;
    store.quotes.push(quoteRow({ id: store.nextId, site_code: site, topic, vendor_name: vendor, amount_kurus: amount, valid_until: validUntil, document_note: docNote, equipment_id: equipmentId, created_by: createdBy, delivery_days: delivery, note, vat_included: vat }));
    return ok([{ id: store.nextId }]);
  }
  if (/^UPDATE equipment_quote_requests SET status = 'approved'/.test(sql)) {
    const r = byId(params[0], params[1]);
    Object.assign(r, { status: 'approved', decided_by: params[2], decided_at: new Date(), quote_id: params[3] });
    return ok();
  }
  if (/FROM equipment_quotes q WHERE q\.id = \$1 AND q\.site_code = \$2/.test(sql)) {
    const q = store.quotes.find((x) => x.id === Number(params[0]) && x.site_code === Number(params[1]));
    return ok(q ? [{ ...q }] : []);
  }
  if (/^SELECT r\.id, r\.site_code, r\.topic, r\.vendor_hint, r\.status, r\.expires_at, s\.name AS site_name FROM equipment_quote_requests r JOIN sites s/.test(sql)) {
    const r = byHash(params[0]);
    return ok(r ? [{ ...r, site_name: 'Gül Sitesi' }] : []);
  }
  if (/^UPDATE equipment_quote_requests SET status = 'draft', submitted_at = NOW\(\)/.test(sql)) {
    const r = byHash(params[0]);
    if (!r || r.status !== 'invited' || r.expires_at.getTime() <= Date.now()) return ok();
    const [, vendorName, contact, phone, amount, validUntil, delivery, note, vat] = params;
    Object.assign(r, { status: 'draft', submitted_at: new Date(), vendor_name: vendorName, vendor_contact: contact, vendor_phone: phone, amount_kurus: amount, valid_until: validUntil, delivery_days: delivery, note, vat_included: vat });
    return ok([{ id: r.id, site_code: r.site_code }]);
  }
  throw new Error(`Beklenmeyen SQL: ${sql.slice(0, 200)}`);
}

before(() => {
  pool.query = async (text, params) => fakeQuery(text, params);
  pool.connect = async () => ({ query: async (text, params) => fakeQuery(text, params), release() {} });
});
beforeEach(() => {
  store = makeStore();
});
after(() => {
  delete pool.query;
  delete pool.connect;
});

const failsWith = (fn, code) =>
  assert.rejects(fn, (error) => {
    assert.equal(error.code, code);
    return true;
  });

const create = async (over = {}) => svc.createQuoteRequest({ siteCode: SITE, actor, access, body: { topic: 'Asansör bakımı', vendor_hint: 'Yıldız Asansör', ...over } });
const tokenOf = (created) => created.link.path.split('/').pop();
const form = { vendor_name: 'Yıldız Asansör Ltd.', vendor_contact: 'Ali Usta', vendor_phone: '0555 000 00 00', amount_kurus: 1250050, vat_included: false, delivery_days: 14, note: 'Yıllık bakım, parça hariç' };

describe('113 şema', () => {
  it('migration, şema modülüyle birebir; yalnız YENİ tablo: equipment_quotes / gider / sözleşme tablolarına dokunmaz; belirteç alanı yalnız özet', () => {
    assert.equal(norm(MIGRATION), norm(quoteRequestMigrationBody()));
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    for (const step of QUOTE_REQUEST_STEPS) {
      assert.match(step.sql, /IF NOT EXISTS/, step.name);
      assert.doesNotMatch(step.sql, /\b(DROP|TRUNCATE|DELETE FROM|INSERT INTO|UPDATE)\b/i, step.name);
      assert.doesNotMatch(step.sql, /ALTER TABLE (?!equipment_quote_requests\b)/i, step.name);
    }
    const table = QUOTE_REQUEST_STEPS[0].sql;
    assert.match(table, /token_hash TEXT NOT NULL/);
    assert.match(table, /token_hash ~ '\^\[0-9a-f\]\{64\}\$'/);
    assert.doesNotMatch(table, /\btoken TEXT\b/);
    assert.deepEqual(QUOTE_REQUEST_STEPS.map((s) => s.kind), ['table', 'fk', 'fk', 'fk', 'fk', 'fk', 'index', 'index']);
    assert.match(QUOTE_REQUEST_STEPS.map((s) => s.sql).join('\n'), /CREATE UNIQUE INDEX IF NOT EXISTS uq_equipment_quote_requests_token ON equipment_quote_requests \(token_hash\)/);
  });

  it('db.js ensureQuoteSchema\'dan SONRA çağırır; her şey varsa tek katalog sorgusu, eksikse önce tablo sonra FK / indeks', async () => {
    const db = read('src', 'db.js');
    assert.match(db, /await ensureQuoteRequestSchema\(client\);/);
    assert.ok(db.indexOf('await ensureQuoteSchema(client)') < db.indexOf('await ensureQuoteRequestSchema(client)'));
    const mk = (present) => {
      const sent = [];
      return {
        sent,
        async query(sql) {
          const text = String(sql).replace(/\s+/g, ' ').trim();
          sent.push(text);
          if (/^SELECT to_regclass/.test(text)) {
            const all = QUOTE_REQUEST_STEPS;
            return {
              rows: [
                {
                  has_table: present,
                  fks: present ? all.filter((s) => s.kind === 'fk').map((s) => s.name) : [],
                  indexes: present ? all.filter((s) => s.kind === 'index').map((s) => s.name) : [],
                  parents: ['sites', 'users', 'equipment_items', 'equipment_quotes'],
                },
              ],
            };
          }
          return { rows: [] };
        },
      };
    };
    const full = mk(true);
    await ensureQuoteRequestSchema(full);
    assert.equal(full.sent.length, 1);
    const empty = mk(false);
    await ensureQuoteRequestSchema(empty);
    assert.match(empty.sent[1], /SET lock_timeout/);
    assert.match(empty.sent[2], /^CREATE TABLE IF NOT EXISTS equipment_quote_requests/);
    assert.equal(empty.sent.filter((s) => /^(CREATE|DO)/.test(s)).length, QUOTE_REQUEST_STEPS.length);
    assert.match(empty.sent.at(-1), /RESET lock_timeout/);
  });
});

describe('belirteç ve tek kullanım', () => {
  it('bağlantı yalnız oluşturma yanıtında döner; DB\'ye yalnız SHA-256 özeti yazılır; liste belirteç / özet taşımaz', async () => {
    const created = await create();
    const token = tokenOf(created);
    assert.match(token, /^[0-9a-f]{64}$/);
    assert.equal(created.link.path, `/firma-teklif/${token}`);
    assert.match(created.link.url, new RegExp(`/firma-teklif/${token}$`));
    assert.equal(store.requests.length, 1);
    assert.equal(store.requests[0].token_hash, sha256(token));
    assert.ok(!JSON.stringify(store.requests).includes(token), 'ham belirteç saklanmaz');
    const listed = await svc.listQuoteRequests(SITE, {});
    const dump = JSON.stringify([created.request, listed]);
    assert.ok(!dump.includes(token) && !dump.includes(sha256(token)), 'yanıt belirteç ya da özet taşımaz');
    assert.equal(listed.items[0].status, 'invited');
    assert.equal(created.request.expired, false);
    assert.deepEqual(store.audits.map((a) => a.action), ['quote.request_created']);
    assert.ok(!JSON.stringify(store.audits).includes(token));
  });

  it('firma girişi TASLAK düşer; teklif / gider / sözleşme oluşmaz; ikinci gönderim 410; geçersiz alan belirteci tüketmez', async () => {
    const token = tokenOf(await create());
    await failsWith(() => svc.submitPublicQuote(token, { ...form, amount_kurus: 0 }), 'INVALID_FIELD');
    await failsWith(() => svc.submitPublicQuote(token, { ...form, vendor_phone: '<script>' }), 'INVALID_FIELD');
    await failsWith(() => svc.submitPublicQuote(token, { ...form, valid_until: '2020-01-01' }), 'INVALID_FIELD');
    assert.equal(store.requests[0].status, 'invited', 'doğrulama hatası bağlantıyı tüketmez');
    const shown = await svc.getPublicQuoteForm(token);
    assert.deepEqual(Object.keys(shown).sort(), ['expires_at', 'site_name', 'topic', 'vendor_hint']);
    const done = await svc.submitPublicQuote(token, form);
    assert.deepEqual(done, { submitted: true, topic: 'Asansör bakımı' });
    assert.equal(store.requests[0].status, 'draft');
    assert.equal(store.requests[0].amount_kurus, 1250050);
    assert.equal(store.quotes.length, 0, 'taslak teklif equipment_quotes\'a yazmaz');
    assert.ok(!store.log.some((s) => /expenses|site_contracts|INSERT INTO equipment_quotes/.test(s)), 'gider / sözleşme / teklif yazılmaz');
    await failsWith(() => svc.submitPublicQuote(token, form), 'QUOTE_FORM_UNUSABLE');
    await failsWith(() => svc.getPublicQuoteForm(token), 'QUOTE_FORM_UNUSABLE');
    const submitted = store.audits.find((a) => a.action === 'quote.request_submitted');
    assert.equal(submitted.details && Object.keys(submitted.details).length, 0, 'dış giriş metni günlüğe yazılmaz');
    assert.match(submitted.actor_name, /Dış firma/);
  });

  it('bilinmeyen / biçimsiz / süresi dolmuş / iptal edilmiş bağlantı AYNI 410 (nedenler ayırt edilmez; ekipman modülü temel modül olduğundan kapalı durumu yok)', async () => {
    const created = await create();
    const token = tokenOf(created);
    await failsWith(() => svc.getPublicQuoteForm('x'.repeat(64)), 'QUOTE_FORM_UNUSABLE');
    await failsWith(() => svc.getPublicQuoteForm('kisa'), 'QUOTE_FORM_UNUSABLE');
    await failsWith(() => svc.submitPublicQuote('a'.repeat(64), form), 'QUOTE_FORM_UNUSABLE');
    store.requests[0].expires_at = new Date(Date.now() - 1000);
    await failsWith(() => svc.getPublicQuoteForm(token), 'QUOTE_FORM_UNUSABLE');
    await failsWith(() => svc.submitPublicQuote(token, form), 'QUOTE_FORM_UNUSABLE');
    assert.equal((await svc.listQuoteRequests(SITE, {})).items[0].expired, true);
    store.requests[0].expires_at = new Date(Date.now() + 86400000);
    const revoked = await svc.revokeQuoteRequest({ siteCode: SITE, rawId: String(store.requests[0].id), actor, access });
    assert.equal(revoked.request.status, 'revoked');
    await failsWith(() => svc.getPublicQuoteForm(token), 'QUOTE_FORM_UNUSABLE');
    await failsWith(() => svc.revokeQuoteRequest({ siteCode: SITE, rawId: String(store.requests[0].id), actor, access }), 'QUOTE_REQUEST_NOT_PENDING');
  });
});

describe('yönetici onayı', () => {
  it('onay yalnız AÇIK teklif üretir (gider / sözleşme yok); çift onay 409; ret teklif üretmez; başka siteden erişilemez', async () => {
    const approvedToken = tokenOf(await create());
    await svc.submitPublicQuote(approvedToken, form);
    const draftId = store.requests[0].id;
    await failsWith(() => svc.approveQuoteRequest({ siteCode: 999, rawId: String(draftId), actor, access }), 'NOT_FOUND');
    const out = await svc.approveQuoteRequest({ siteCode: SITE, rawId: String(draftId), actor, access });
    assert.equal(out.request.status, 'approved');
    assert.equal(out.request.quote_id, out.quote.id);
    assert.equal(out.quote.status, 'open');
    assert.equal(out.quote.expense_id, null);
    assert.equal(out.quote.contract_id, null);
    assert.equal(out.quote.accepted_as, null);
    assert.equal(out.quote.vendor_name, 'Yıldız Asansör Ltd.');
    assert.equal(out.quote.amount_kurus, 1250050);
    assert.equal(out.quote.vat_included, false);
    assert.match(out.quote.document_note, /^Firma formundan geldi \(irtibat: Ali Usta, 0555 000 00 00\)$/);
    assert.equal(store.quotes.length, 1);
    assert.ok(!store.log.some((s) => /INSERT INTO expenses|site_contracts/.test(s)), 'kabul (gider / sözleşme) ayrı karardır');
    await failsWith(() => svc.approveQuoteRequest({ siteCode: SITE, rawId: String(draftId), actor, access }), 'QUOTE_REQUEST_NOT_DRAFT');
    assert.equal(store.quotes.length, 1, 'çift onay ikinci teklif üretmez');

    const rejectedToken = tokenOf(await create({ topic: 'Kamera' }));
    await failsWith(() => svc.rejectQuoteRequest({ siteCode: SITE, rawId: String(store.requests[1].id), actor, access }), 'QUOTE_REQUEST_NOT_DRAFT');
    await svc.submitPublicQuote(rejectedToken, form);
    const rejected = await svc.rejectQuoteRequest({ siteCode: SITE, rawId: String(store.requests[1].id), actor, access });
    assert.equal(rejected.request.status, 'rejected');
    assert.equal(store.quotes.length, 1);
    assert.deepEqual(
      store.audits.map((a) => a.action),
      ['quote.request_created', 'quote.request_submitted', 'quote.request_approved', 'quote.request_created', 'quote.request_submitted', 'quote.request_rejected'],
    );
    for (const a of store.audits) assert.ok(SITE_AUDIT_LABELS[a.action], `denetim başlığı: ${a.action}`);
  });

  it('bekleyen sınırı: 100 bekleyen bağlantı / taslaktan sonra yenisi 409', async () => {
    for (let i = 0; i < 100; i += 1) await create({ topic: `Konu ${i}` });
    await failsWith(() => create({ topic: 'Fazla' }), 'LIMIT_REACHED');
    await failsWith(() => create({ topic: 'Süre', valid_days: 31 }), 'INVALID_FIELD');
  });
});

describe('sayfa ve rotalar', () => {
  it('sayfa: sunucu değerleri kaçışlı, betik yalnız nonce ile; kötü niyetli konu / site / firma betik çalıştıramaz', () => {
    const html = renderQuoteFormPage({
      nonce: 'NONCE123',
      token: 'a'.repeat(64),
      form: { topic: '<script>alert(1)</script>', site_name: '"><img src=x onerror=alert(1)>', vendor_hint: '" autofocus onfocus="alert(1)', expires_at: '2026-11-12T10:00:00Z' },
    });
    assert.ok(!html.includes('<script>alert(1)'));
    assert.ok(!html.includes('<img src=x'));
    assert.ok(html.includes('value="&quot; autofocus onfocus=&quot;alert(1)"'), 'beklenen firma tek bir kaçışlı nitelik değeri olarak yazılır');
    assert.match(html, /<script nonce="NONCE123">/);
    assert.match(html, /<style nonce="NONCE123">/);
    assert.equal((html.match(/<script/g) ?? []).length, 1, 'tek betik etiketi (nonce\'lu)');
    assert.ok(!html.includes('onfocus="') && !html.includes('onclick='), 'yerleşik olay işlevi yok');
    assert.match(html, /data-token="a{64}"/);
    assert.match(html, /12\.11\.2026/);
  });

  it('herkese açık rotalar: kimlik katmanı yok, hız sınırlı; sayfa 200 + kati CSP; gönderim 201, ikinci 410; yönetici rotaları yazma yetkili; belirteçli yollar günlükte maskelenir', async () => {
    const created = await create();
    const token = tokenOf(created);
    const app = express();
    app.use(express.json({ limit: '1mb' }));
    app.use(equipmentPublicRouter);
    const server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    try {
      const base = `http://127.0.0.1:${server.address().port}`;
      const page = await fetch(`${base}/firma-teklif/${token}`);
      assert.equal(page.status, 200);
      const csp = page.headers.get('content-security-policy');
      assert.match(csp, /default-src 'none'/);
      assert.match(csp, /form-action 'none'/);
      assert.match(csp, /frame-ancestors 'none'/);
      assert.match(csp, /script-src 'nonce-[A-Za-z0-9+/=]+'/);
      assert.equal(page.headers.get('cache-control'), 'no-store');
      assert.equal(page.headers.get('referrer-policy'), 'no-referrer');
      assert.match(await page.text(), /Yıldız Asansör/);
      const bad = await fetch(`${base}/public/quote-forms/${token}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...form, amount_kurus: 'çok' }) });
      assert.equal(bad.status, 400);
      const sent = await fetch(`${base}/public/quote-forms/${token}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form) });
      assert.equal(sent.status, 201);
      assert.deepEqual(await sent.json(), { submitted: true, topic: 'Asansör bakımı' });
      const again = await fetch(`${base}/public/quote-forms/${token}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form) });
      assert.equal(again.status, 410);
      assert.equal((await again.json()).code, 'QUOTE_FORM_UNUSABLE');
      const used = await fetch(`${base}/firma-teklif/${token}`);
      assert.equal(used.status, 410);
      assert.match(await used.text(), /Bağlantı kullanılamıyor/);
      const huge = await fetch(`${base}/public/quote-forms/${token}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ note: 'x'.repeat(20000) }) });
      assert.equal(huge.status, 413);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
    const routes = read('src', 'modules', 'equipment_routes.js');
    const publicPart = routes.slice(routes.indexOf('export const equipmentPublicRouter'));
    assert.doesNotMatch(publicPart, /authRequired/, 'belirteç yetkidir: kimlik katmanı yok');
    assert.match(publicPart, /equipmentPublicRouter\.get\(`\$\{svc\.QUOTE_FORM_PATH\}\/:token`, quoteFormPageLimiter/);
    assert.match(publicPart, /equipmentPublicRouter\.post\('\/public\/quote-forms\/:token', quoteFormSubmitLimiter/);
    for (const needle of [
      "read('/quote-requests'",
      "write('post', '/quote-requests'",
      "write('post', '/quote-requests/:id/revoke'",
      "write('post', '/quote-requests/:id/approve'",
      "write('post', '/quote-requests/:id/reject'",
    ]) {
      assert.ok(routes.includes(needle), needle);
    }
    assert.match(read('src', 'server.js'), /app\.use\(equipmentPublicRouter\);/);
    assert.ok(!maskSensitiveUrl(`/firma-teklif/${token}`).includes(token));
    assert.ok(!maskSensitiveUrl(`/public/quote-forms/${token}`).includes(token));
  });
});
