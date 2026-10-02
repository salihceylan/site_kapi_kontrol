import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import {
  createCompanyAccess,
  hasValidCompanyKey,
  timingSafeEqualStrings,
} from '../src/middlewares/company_auth.js';
import {
  decodePngBase64,
  normalizeCompanyUid,
  normalizeQrFileName,
  resolveQrPath,
} from '../src/routes/company_routes.js';

const KEY = 'company-key-for-tests-0123456789abcdef'; // sahte test degeri

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

function runAccess(access, { headers = {}, ...rest } = {}) {
  const req = { headers, ip: '127.0.0.1', method: 'GET', originalUrl: '/api/company/labeled-devices', ...rest };
  const res = makeRes();
  let nextCalled = false;
  let nextArg;
  const result = access(req, res, (arg) => {
    nextCalled = true;
    nextArg = arg;
  });
  return Promise.resolve(result).then(() => ({ req, res, nextCalled, nextArg }));
}

describe('C9 sirket ucu yetkisi', () => {
  let savedKey;
  beforeEach(() => {
    savedKey = process.env.COMPANY_API_KEY;
    process.env.COMPANY_API_KEY = KEY;
  });
  afterEach(() => {
    if (savedKey === undefined) delete process.env.COMPANY_API_KEY;
    else process.env.COMPANY_API_KEY = savedKey;
  });

  // JWT yolunu DB gerektirmeden simule eden sahte middleware'ler
  const fakeAuthOk = (role) => (req, _res, next) => {
    req.authUser = { role, userCode: 5 };
    return next();
  };
  const fakeAuthFail = (_req, res) => res.status(401).json({ error: 'Gecersiz veya suresi dolmus token.' });
  const fakeRequireSuper = (req, res, next) =>
    req.authUser?.role === 'super_user' ? next() : res.status(403).json({ error: 'super user gerekir' });

  it('timingSafeEqualStrings: esit/esit degil, farkli uzunluk', () => {
    assert.equal(timingSafeEqualStrings('abc', 'abc'), true);
    assert.equal(timingSafeEqualStrings('abc', 'abd'), false);
    assert.equal(timingSafeEqualStrings('abc', 'abcd'), false);
    assert.equal(timingSafeEqualStrings('', ''), true);
  });

  it('hasValidCompanyKey: dogru anahtar kabul, yanlis/eksik/bos red', () => {
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': KEY } }), true);
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': `  ${KEY}  ` } }), true);
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': `${KEY}x` } }), false);
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': '' } }), false);
    assert.equal(hasValidCompanyKey({ headers: {} }), false);
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': 'a'.repeat(5000) } }), false);
  });

  it('COMPANY_API_KEY tanimsizsa baslik ne olursa olsun gecersiz (yalniz super_user JWT)', () => {
    delete process.env.COMPANY_API_KEY;
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': KEY } }), false);
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': '' } }), false);
    process.env.COMPANY_API_KEY = '   ';
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': '' } }), false);
    assert.equal(hasValidCompanyKey({ headers: { 'x-company-key': '   ' } }), false);
  });

  it('ne anahtar ne JWT -> 401, next cagrilmaz', async () => {
    const access = createCompanyAccess({ audit: () => {} });
    const { res, nextCalled } = await runAccess(access);
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  });

  it('yanlis anahtar + JWT yok -> 401', async () => {
    const access = createCompanyAccess({ audit: () => {} });
    const { res, nextCalled } = await runAccess(access, { headers: { 'x-company-key': 'yanlis-anahtar' } });
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  });

  it('dogru X-Company-Key -> next, actor=company_key', async () => {
    const access = createCompanyAccess({ audit: () => {} });
    const { req, nextCalled, nextArg } = await runAccess(access, { headers: { 'x-company-key': KEY } });
    assert.equal(nextCalled, true);
    assert.equal(nextArg, undefined);
    assert.equal(req.companyActor, 'company_key');
  });

  it('COMPANY_API_KEY tanimsizken baslik gonderilse bile 401', async () => {
    delete process.env.COMPANY_API_KEY;
    const access = createCompanyAccess({ audit: () => {} });
    const { res, nextCalled } = await runAccess(access, { headers: { 'x-company-key': KEY } });
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  });

  it('super_user JWT -> next, actor=super_user:<kod>; COMPANY_API_KEY olmasa da calisir', async () => {
    delete process.env.COMPANY_API_KEY;
    const access = createCompanyAccess({ authenticate: fakeAuthOk('super_user'), requireSuper: fakeRequireSuper, audit: () => {} });
    const { req, nextCalled } = await runAccess(access, { headers: { authorization: 'Bearer abc' } });
    assert.equal(nextCalled, true);
    assert.equal(req.companyActor, 'super_user:5');
  });

  it('super_user olmayan JWT -> 403', async () => {
    const access = createCompanyAccess({ authenticate: fakeAuthOk('site_manager'), requireSuper: fakeRequireSuper, audit: () => {} });
    const { res, nextCalled } = await runAccess(access, { headers: { authorization: 'Bearer abc' } });
    assert.equal(res.statusCode, 403);
    assert.equal(nextCalled, false);
  });

  it('gecersiz JWT -> 401 (authenticate yanitlar)', async () => {
    const access = createCompanyAccess({ authenticate: fakeAuthFail, requireSuper: fakeRequireSuper, audit: () => {} });
    const { res, nextCalled } = await runAccess(access, { headers: { authorization: 'Bearer abc' } });
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  });

  it('yanlis anahtar ama gecerli super_user JWT -> JWT yolu ile gecer', async () => {
    const access = createCompanyAccess({ authenticate: fakeAuthOk('super_user'), requireSuper: fakeRequireSuper, audit: () => {} });
    const { nextCalled } = await runAccess(access, { headers: { 'x-company-key': 'yanlis', authorization: 'Bearer abc' } });
    assert.equal(nextCalled, true);
  });

  it('reddedilen denemede audit kaydi yazilir (anahtar/token icermez)', async () => {
    const audits = [];
    const access = createCompanyAccess({ audit: (event, details) => audits.push({ event, details }) });
    await runAccess(access, { headers: { 'x-company-key': 'yanlis-anahtar-degeri' } });
    assert.equal(audits.length, 1);
    assert.equal(audits[0].event, 'company_access_denied');
    assert.equal(JSON.stringify(audits[0]).includes('yanlis-anahtar-degeri'), false);
  });
});

describe('company_routes yardimcilari', () => {
  it('normalizeCompanyUid: yalniz 12 hane buyuk harf hex', () => {
    assert.equal(normalizeCompanyUid('00861a0d5020'), '00861A0D5020');
    assert.equal(normalizeCompanyUid(' 00:86:1A:0D:50:20 '), '00861A0D5020');
    assert.equal(normalizeCompanyUid('00-86-1A-0D-50-20'), '00861A0D5020');
    for (const bad of ['', '123', '00861A0D50201', 'GGGGGGGGGGGG', '../../etc/passwd', '00861A0D5020.png', '00861A0D502\n0', null, undefined]) {
      assert.equal(normalizeCompanyUid(bad), null, String(bad));
    }
  });

  it('normalizeQrFileName: yalniz <12 hex>.png', () => {
    assert.equal(normalizeQrFileName('00861A0D5020.png'), '00861A0D5020.png');
    assert.equal(normalizeQrFileName('00861a0d5020.png'), '00861A0D5020.png');
    for (const bad of ['../00861A0D5020.png', '00861A0D5020.PNG.exe', '00861A0D5020', 'x.png', '..%2F..%2Fsecret.png', '00861A0D5020.png/../x', 'a'.repeat(300) + '.png']) {
      assert.equal(normalizeQrFileName(bad), null, bad);
    }
  });

  it('resolveQrPath: kok dizin disina cikamaz', () => {
    const root = path.resolve('/srv/app/public/qrcodes');
    const ok = resolveQrPath(root, '00861A0D5020.png');
    assert.equal(ok, path.join(root, '00861A0D5020.png'));
    assert.equal(resolveQrPath(root, '../../etc/passwd'), null);
    assert.equal(resolveQrPath(root, '..\\..\\secret.png'), null);
    assert.equal(resolveQrPath(root, '/etc/passwd'), null);
    assert.equal(resolveQrPath(root, 'abc.png'), null);
    assert.equal(resolveQrPath(root, '00861A0D5020.png/..'), null);
  });

  it('decodePngBase64: PNG imzasi ve boyut dogrulanir', () => {
    const pngHeader = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
    const b64 = pngHeader.toString('base64');
    assert.ok(decodePngBase64(b64));
    assert.ok(decodePngBase64(`data:image/png;base64,${b64}`));
    assert.equal(decodePngBase64(Buffer.from('<html>not a png</html>').toString('base64')), null);
    assert.equal(decodePngBase64('###not base64###'), null);
    assert.equal(decodePngBase64(''), null);
    const tooBig = Buffer.concat([pngHeader, Buffer.alloc(2 * 1024 * 1024)]).toString('base64');
    assert.equal(decodePngBase64(tooBig), null);
  });
});
