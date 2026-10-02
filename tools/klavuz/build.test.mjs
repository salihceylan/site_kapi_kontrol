// Arıza klavuzu üreticisinin testleri:  node --test tools/klavuz
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  createIo,
  crossCheck,
  explainEntry,
  linkOf,
  loadAreas,
  main,
  parseArgs,
  renderMain,
  renderMessages,
  resolveArea,
  resolveRef,
  scanAppCalls,
  scanEnv,
  scanMessages,
  scanRoutes,
  scanTables,
} from './build.mjs';

/** Bellek içi sahte depo: { 'yol': 'satır1\nsatır2' } */
function fakeIo(files) {
  const lines = (rel) => (rel in files ? files[rel].split('\n') : null);
  return {
    exists: (rel) => rel in files,
    lines,
    list(dir, { exts = null, recursive = false } = {}) {
      const base = dir.replace(/\/$/, '');
      return Object.keys(files)
        .filter((f) => f.startsWith(`${base}/`))
        .filter((f) => recursive || !f.slice(base.length + 1).includes('/'))
        .filter((f) => !exts || exts.some((e) => f.endsWith(e)))
        .sort();
    },
  };
}

const sample = {
  'a/x.js': ['one', 'router.post("/p")', 'two', 'dup', 'dup', 'end marker'].join('\n'),
};

describe('resolveRef', () => {
  const io = fakeIo(sample);

  it('tek eşleşmeyi satır numarası ve satır metniyle çözer', () => {
    const r = resolveRef({ file: 'a/x.js', find: 'router.post(' }, io);
    assert.equal(r.ok, true);
    assert.equal(r.line, 2);
    assert.equal(r.text, 'router.post("/p")');
  });

  it('bulunamayan parça hata verir (kod değişmiş olabilir)', () => {
    const r = resolveRef({ file: 'a/x.js', find: 'yok boyle bir sey' }, io);
    assert.equal(r.ok, false);
    assert.match(r.error, /bulunamadı/);
  });

  it('birden fazla eşleşme BELİRSİZ sayılır; nth ve any ile çözülür', () => {
    const ambiguous = resolveRef({ file: 'a/x.js', find: 'dup' }, io);
    assert.equal(ambiguous.ok, false);
    assert.match(ambiguous.error, /BELİRSİZ.*4, 5/);
    assert.equal(resolveRef({ file: 'a/x.js', find: 'dup', nth: 2 }, io).line, 5);
    assert.equal(resolveRef({ file: 'a/x.js', find: 'dup', any: true }, io).line, 4);
    assert.equal(resolveRef({ file: 'a/x.js', find: 'dup', nth: 3 }, io).ok, false);
  });

  it('regex ve until (satır aralığı) desteklenir', () => {
    assert.equal(resolveRef({ file: 'a/x.js', find: { regex: '^router\\.post' } }, io).line, 2);
    const ranged = resolveRef({ file: 'a/x.js', find: 'router.post(', until: 'end marker' }, io);
    assert.deepEqual([ranged.line, ranged.endLine], [2, 6]);
    assert.equal(resolveRef({ file: 'a/x.js', find: 'router.post(', until: 'yok' }, io).ok, false);
    assert.equal(resolveRef({ file: 'a/x.js', find: { regex: '(' } }, io).ok, false);
  });

  it('geçersiz yol, yoksayılan klasör ve eksik dosya reddedilir', () => {
    for (const file of ['../etc/passwd', '/abs/yol', 'C:/x.js', 'node_modules/x.js', 'a/../x.js']) {
      assert.equal(resolveRef({ file, find: 'x' }, io).ok, false, file);
    }
    assert.match(resolveRef({ file: 'a/yok.js', find: 'x' }, io).error, /dosya yok/);
    assert.equal(resolveRef({ file: 'a/x.js' }, io).ok, false, 'find eksik');
  });
});

describe('resolveArea / crossCheck', () => {
  const io = fakeIo({ ...sample, 'a/t.test.js': 'x' });
  const area = (entries, extra = {}) => ({
    key: 'demo',
    title: 'Demo',
    intro: 'giriş',
    entries,
    ...extra,
  });
  const good = {
    id: 'demo-giris',
    symptom: 'Giriş yapılamıyor, 401 dönüyor',
    refs: [{ file: 'a/x.js', find: 'router.post(', note: 'uç nokta' }],
    tests: ['a/t.test.js'],
  };

  it('geçerli giriş hatasız çözülür', () => {
    const r = resolveArea(area([good]), io);
    assert.deepEqual(r.errors, []);
    assert.equal(r.entries[0].refs[0].line, 2);
  });

  it('eksik not, kısa belirti, kötü id, olmayan test ve olmayan dosya haritası hata verir', () => {
    const bad = {
      id: 'Kotu_Id',
      symptom: 'kısa',
      refs: [{ file: 'a/x.js', find: 'router.post(' }],
      tests: ['a/yok.test.js'],
    };
    const r = resolveArea(area([bad], { files: [{ file: 'a/yok.js', note: 'x' }] }), io);
    const joined = r.errors.join('\n');
    assert.match(joined, /kebab-case/);
    assert.match(joined, /symptom/);
    assert.match(joined, /ref\.note/);
    assert.match(joined, /test dosyası yok/);
    assert.match(joined, /dosya haritasında olmayan dosya/);
  });

  it('yinelenen id ve geçersiz related yakalanır', () => {
    const a = resolveArea(area([good]), io);
    const b = resolveArea(area([{ ...good, related: ['yok-id'] }], { key: 'demo2' }), io);
    const errors = crossCheck([a, b]);
    assert.ok(errors.some((e) => /yinelenen id/.test(e)));
    assert.ok(errors.some((e) => /related id yok/.test(e)));
  });
});

describe('otomatik taramalar', () => {
  it('scanRoutes: yöntem, yol ve ara katmanları okur; router olmayan nesneleri atlar', () => {
    const io = fakeIo({
      'server/src/routes/auth_routes.js': [
        "authRouter.post('/auth/login', loginRateLimiter, async (req, res) => {",
        "other.get('/yok', () => {})",
        "adminRouter.get('/admin/users', authRequired, requireRole('super_user'), async (req, res) => {",
      ].join('\n'),
      'server/src/server.js': "app.post('/api/x', limiter, express.json())",
    });
    const rows = scanRoutes(io);
    assert.deepEqual(
      rows.map((r) => `${r.method} ${r.route}`),
      ['POST /auth/login', 'GET /admin/users', 'POST /api/x'],
    );
    assert.equal(rows[0].middleware, 'loginRateLimiter');
    assert.match(rows[1].middleware, /authRequired, requireRole/);
    assert.equal(rows[0].line, 1);
  });

  it('scanAppCalls: en yakın metot adıyla eşler; iki yol biçimini tanır', () => {
    const io = fakeIo({
      'lib/services/auth_api.dart': [
        'class AuthApi {',
        '  Future<Map<String, dynamic>> registerIndividual({',
        "    final uri = Uri.parse('$baseUrl/auth/register-individual');",
        '  Future<UserSession> login({',
        "      path: '/auth/login',",
      ].join('\n'),
    });
    const rows = scanAppCalls(io);
    assert.deepEqual(
      rows.map((r) => [r.route, r.method]),
      [['/auth/register-individual', 'registerIndividual'], ['/auth/login', 'login']],
    );
  });

  it('scanEnv: değişken adı ve ilk kullanımlar; scanTables: db.js ve migration', () => {
    const io = fakeIo({
      'server/src/a.js': 'const a = process.env.SMTP_HOST;\nconst b = process.env.SMTP_HOST;',
      'server/src/b.js': 'x(process.env.SMTP_HOST, process.env.DB_NAME)',
      'server/src/db.js': 'CREATE TABLE IF NOT EXISTS users (\nCREATE TABLE IF NOT EXISTS sites (',
      'server/migrations/001_init.sql': 'CREATE TABLE IF NOT EXISTS users (\n);',
    });
    const env = scanEnv(io);
    assert.deepEqual(env.map((e) => e.name), ['DB_NAME', 'SMTP_HOST']);
    assert.equal(env.find((e) => e.name === 'SMTP_HOST').places.length, 2, 'dosya başına bir kez');
    const tables = scanTables(io);
    assert.deepEqual(tables.map((t) => t.name), ['sites', 'users']);
    assert.equal(tables.find((t) => t.name === 'users').migration.file, 'server/migrations/001_init.sql');
    assert.equal(tables.find((t) => t.name === 'sites').migration, null);
  });

  it('scanMessages: sunucu ve uygulama mesajlarını dosya:satır ile bulur; kod benzeri değerleri atlar', () => {
    const io = fakeIo({
      'server/src/x.js': [
        "res.status(401).json({ error: 'Giris bilgileri hatali.' });",
        "throw httpError(409, 'Bu e-posta zaten kayıtlı.');",
        "const o = { error: 'ECONN' };",
      ].join('\n'),
      'lib/services/s.dart': [
        "throw ApiException('Sunucuya ulaşılamadı lütfen tekrar deneyin');",
        "return 'Geçersiz kod, lütfen yeniden deneyiniz.';",
      ].join('\n'),
      'lib/ui/p.dart': "return 'Bu satır servis değil, atlanmalı normalde';",
    });
    const m = scanMessages(io);
    assert.deepEqual(m.server.map((r) => r.message).sort(), ['Bu e-posta zaten kayıtlı.', 'Giris bilgileri hatali.']);
    assert.equal(m.app.length, 2);
    assert.ok(m.app.every((r) => r.file === 'lib/services/s.dart'));
  });
});

describe('belge çıktısı', () => {
  it('linkOf: docs/ içinden köke göre bağlantı ve aralık', () => {
    assert.equal(linkOf('a/b.js', 12), '[a/b.js:12](../a/b.js#L12)');
    assert.equal(linkOf('a/b.js', 12, 20), '[a/b.js:12-20](../a/b.js#L12-L20)');
  });

  it('renderMain: deterministik; giriş çapası, hızlı yönlendirme ve ekler var', () => {
    const io = fakeIo(sample);
    const area = resolveArea(
      {
        key: 'demo',
        title: 'Demo Alanı',
        intro: 'Giriş metni',
        files: [{ file: 'a/x.js', note: 'örnek dosya' }],
        entries: [
          {
            id: 'demo-giris',
            symptom: 'Giriş yapılamıyor, 401 dönüyor',
            keywords: ['giriş', '401'],
            refs: [{ file: 'a/x.js', find: 'router.post(', note: 'uç nokta | borulu' }],
            causes: ['Yanlış parola'],
            commands: ['pm2 logs kapi-api'],
          },
        ],
      },
      io,
    );
    const scans = { routes: [], appCalls: [], env: [], tables: [] };
    const a = renderMain([area], scans);
    const b = renderMain([area], scans);
    assert.equal(a, b, 'aynı girdi aynı çıktı');
    assert.match(a, /<a id="demo-giris"><\/a>/);
    assert.match(a, /\| Giriş yapılamıyor, 401 dönüyor \| giriş, 401 \| Demo Alanı \| \[demo-giris\]\(#demo-giris\) \|/);
    assert.match(a, /\[a\/x\.js:2\]\(\.\.\/a\/x\.js#L2\)/);
    assert.match(a, /uç nokta \\\| borulu/, 'tablo hücresinde | kaçırılır');
    assert.match(a, /## Ek A — Sunucu uç noktaları/);
    assert.match(a, /## Ek D — Veritabanı tabloları/);
    assert.equal(a.includes('undefined'), false);
  });

  it('renderMessages: iki tablo ve sayılar', () => {
    const text = renderMessages({
      server: [{ message: 'Merhaba | dünya', file: 'server/src/a.js', line: 3 }],
      app: [],
    });
    assert.match(text, /## Sunucu mesajları \(1\)/);
    assert.match(text, /Merhaba \\\| dünya/);
    assert.match(text, /## Uygulama \(Flutter\) mesajları \(0\)/);
  });

  it('parseArgs: bayraklar ve bilinmeyen argüman', () => {
    assert.deepEqual(parseArgs(['--check', '--fresh', '--only', 'x']), {
      check: true, fresh: true, only: 'x', where: null, explain: null, help: false,
    });
    assert.equal(parseArgs(['--explain', 'abc']).explain, 'abc');
    assert.throws(() => parseArgs(['--bilinmeyen']), /bilinmeyen/);
  });

  it('explainEntry: bağlantının satırını ve çevresini işaretleyerek yazdırır', () => {
    const io = fakeIo(sample);
    const area = resolveArea(
      {
        key: 'demo',
        title: 'Demo',
        intro: 'x',
        entries: [
          {
            id: 'demo-giris',
            symptom: 'Giriş yapılamıyor, 401 dönüyor',
            refs: [{ file: 'a/x.js', find: 'router.post(', note: 'uç nokta' }],
            causes: ['Yanlış parola'],
          },
        ],
      },
      io,
    );
    const text = explainEntry(area.entries[0], io);
    assert.match(text, /^# demo-giris — Giriş yapılamıyor/);
    assert.match(text, /## a\/x\.js:2 — uç nokta/);
    assert.match(text, /> {4}2 \| router\.post\("\/p"\)/, 'hedef satır > ile işaretlenir');
    assert.match(text, /  {4}1 \| one/, 'önceki satır bağlam olarak gelir');
    assert.match(text, /Nedenler: Yanlış parola/);
  });
});

describe('gerçek depo: klavuz girişleri kodla uyumlu mu?', () => {
  it('createIo gerçek dosyaları okur', () => {
    const io = createIo();
    assert.ok(io.exists('AGENTS.md'));
    assert.ok(io.lines('server/src/server.js').length > 50);
  });

  it('tüm alan dosyaları çözülür ve çapraz kontrolden geçer (--check)', async () => {
    const original = console.log;
    const originalError = console.error;
    const logs = [];
    console.log = (...a) => logs.push(a.join(' '));
    console.error = (...a) => logs.push(a.join(' '));
    try {
      const code = await main(['--check']);
      assert.equal(code, 0, logs.join('\n'));
    } finally {
      console.log = original;
      console.error = originalError;
    }
  });

  it('alan dosyaları yüklenebilir (sözdizimi)', async () => {
    const areas = await loadAreas();
    for (const a of areas) assert.ok(a.key && a.title, `alan: ${a.key}`);
  });
});
