// Arıza klavuzu üreticisinin testleri:  node --test tools/klavuz
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import {
  createIo,
  crossCheck,
  explainEntry,
  lintCommand,
  lintEntries,
  linkOf,
  loadAreas,
  loadAreasTolerant,
  loadStatus,
  logPhraseFound,
  main,
  normalizeDartPath,
  parseArgs,
  renderAll,
  renderMessages,
  resolveArea,
  resolveRef,
  scanAppCalls,
  scanCoverage,
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

  it('crossCheck only: yalnız o alanın eksik related/yinelenen id hataları raporlanır; evren tüm alanlardır', () => {
    const a = resolveArea(
      area([{ ...good, id: 'a-bir', related: ['b-var', 'a-yok'] }], { key: 'a' }),
      io,
    );
    const b = resolveArea(
      area([{ ...good, id: 'b-var', related: ['b-yok'] }], { key: 'b' }),
      io,
    );
    // a alanı: b-var başka alanda VAR (hata değil), a-yok yok (hata). b alanının eksiği (b-yok) a için raporlanmaz.
    const onlyA = crossCheck([a, b], { only: 'a' });
    assert.deepEqual(onlyA, ['[a] a-bir: related id yok: a-yok']);
    const onlyB = crossCheck([a, b], { only: 'b' });
    assert.deepEqual(onlyB, ['[b] b-var: related id yok: b-yok']);
    assert.equal(crossCheck([a, b]).length, 2, 'only verilmezse hepsi');
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

  it('scanCoverage: girişe bağlı / yalnız haritada / hiç geçmeyen dosyaları ayırır; testleri saymaz', () => {
    const io = fakeIo({
      'server/src/a.js': 'x\ny\nz',
      'server/src/b.js': 'x',
      'server/src/c.js': 'x\ny',
      'lib/m.dart': 'x',
      'server/src/readme.md': 'sayılmaz',
      'tools/klavuz/build.test.mjs': 'sayılmaz',
    });
    const area = {
      key: 'k',
      files: [{ file: 'server/src/b.js', note: 'x' }],
      entries: [{ id: 'k-1', refs: [{ file: 'server/src/a.js', line: 1 }, { file: 'yok/dosya.js', line: 1 }] }],
    };
    const rows = scanCoverage(io, [area]);
    const byFile = Object.fromEntries(rows.map((r) => [r.file, r]));
    assert.deepEqual(Object.keys(byFile).sort(), ['lib/m.dart', 'server/src/a.js', 'server/src/b.js', 'server/src/c.js']);
    assert.deepEqual(byFile['server/src/a.js'].entries, ['k-1']);
    assert.equal(byFile['server/src/a.js'].lines, 3);
    assert.deepEqual(byFile['server/src/b.js'].mappedIn, ['k']);
    assert.equal(byFile['server/src/c.js'].entries.length + byFile['server/src/c.js'].mappedIn.length, 0);
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

describe('kaynaktan okunan metinlerin işlenmesi', () => {
  it('normalizeDartPath: ${...} ifadelerini $ad biçimine indirir, sorguyu atar', () => {
    assert.equal(
      normalizeDartPath('/admin/devices/${Uri.encodeComponent(deviceUid)}/connectivity-logs'),
      '/admin/devices/$deviceUid/connectivity-logs',
    );
    assert.equal(normalizeDartPath('/admin/users/${id}/activation'), '/admin/users/$id/activation');
    assert.equal(normalizeDartPath('/x/${a.b}/y'), '/x/$param/y');
    assert.equal(normalizeDartPath('/admin/users?page=1'), '/admin/users');
    assert.equal(normalizeDartPath('/auth/login'), '/auth/login');
  });

  it('scanAppCalls: Uri.encodeComponent içeren yol yarım kalmaz', () => {
    const io = fakeIo({
      'lib/services/auth_api.dart': [
        '  Future<List<Log>> getDeviceConnectivityLogs({',
        "    final uri = Uri.parse('$baseUrl/admin/devices/${Uri.encodeComponent(deviceUid)}/connectivity-logs')",
      ].join('\n'),
    });
    assert.deepEqual(scanAppCalls(io).map((r) => r.route), ['/admin/devices/$deviceUid/connectivity-logs']);
  });

  it("scanMessages: kaynaktaki kaçışlar çözülür (GPS\\'i -> GPS'i)", () => {
    const io = fakeIo({
      'server/src/x.js': "res.json({ error: 'GPS\\'i kontrol edip tekrar deneyin lütfen' });",
    });
    assert.equal(scanMessages(io).server[0].message, "GPS'i kontrol edip tekrar deneyin lütfen");
  });
});

describe('mekanik denetim (lint): günlük ifadeleri ve komutlar', () => {
  const corpus = [
    'console.error(`[ENV] UYARI: ${w}`);',
    "warnings.push('COMPANY_API_KEY tanimli degil; /api/company yalnizca super_user ile calisir.');",
    'recordBridgeError("db_error", `Device status DB yazilamadi: ${e.message}`);',
    "console.log('[MQTT bridge] baglandi');",
  ].join('\n');

  it('logPhraseFound: birebir, önek+mesaj parçalı ve bulunamayan', () => {
    assert.equal(logPhraseFound(corpus, '[MQTT bridge] baglandi'), true, 'birebir');
    assert.equal(logPhraseFound(corpus, '[ENV] UYARI: COMPANY_API_KEY tanimli degil'), true, 'önek + mesaj ayrı yerlerde');
    assert.equal(logPhraseFound(corpus, '[MQTT bridge] Device status DB yazilamadi'), true);
    assert.equal(logPhraseFound(corpus, 'tamamen uydurma bir günlük satırı'), false);
    assert.equal(logPhraseFound(corpus, '[ENV] UYARI: JWT_SECRET 20 karakter'), false, 'dinamik değer: ~ ile işaretlenmeli');
  });

  it('lintCommand: sır basanlar ASLA, değiştiriciler yalnızca "DEĞİŞTİRİR" etiketliyse', () => {
    for (const bad of ['pm2 env 0', 'pm2 jlist', 'pm2 describe kapi-api', 'cat server/.env', 'grep KEY server/.env', 'printenv', 'env | sort']) {
      assert.ok(lintCommand(bad).some((p) => /sır/.test(p)), `sır riski beklenirdi: ${bad}`);
    }
    for (const good of [
      'pm2 describe kapi-api | grep -E "status|restarts"',
      'cat server/.env.example',
      'curl -s https://api.gudeteknoloji.com.tr/health',
      'pm2 logs kapi-api --lines 100 --nostream | grep -a /auth/login',
      "docker exec site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c 'SELECT COUNT(*) FROM users'",
    ]) {
      assert.deepEqual(lintCommand(good), [], `temiz olmalı: ${good}`);
    }
    for (const mutating of ['rm -rf /tmp/x', 'pm2 restart kapi-api --update-env', "psql -c 'DELETE FROM users'", 'git reset --hard', 'docker stop x', "psql -c 'UPDATE users SET a=1'"]) {
      assert.ok(lintCommand(mutating).some((p) => /etiketsiz/.test(p)), `etiket beklenirdi: ${mutating}`);
      assert.deepEqual(lintCommand(`${mutating}   # DEĞİŞTİRİR: canlıyı etkiler`), [], `etiketli kabul edilmeli: ${mutating}`);
    }
  });

  it('lintEntries: kodda olmayan günlük ve riskli komutu girişe göre raporlar; ~ ve etiketliler geçer', () => {
    const areas = [
      {
        key: 'k',
        entries: [
          {
            id: 'k-bir',
            logs: ['[MQTT bridge] baglandi', '~[ENV] UYARI: JWT_SECRET 20 karakter', 'uydurma satır burada'],
            commands: ['pm2 jlist', 'pm2 restart kapi-api # DEĞİŞTİRİR: kısa kesinti', 'curl -s http://x/health'],
          },
        ],
      },
    ];
    const warnings = lintEntries(areas, fakeIo({}), corpus);
    assert.deepEqual(
      warnings.map((w) => `${w.id}|${w.kind}|${w.text}`),
      ['k-bir|günlük|uydurma satır burada', 'k-bir|komut|pm2 jlist'],
    );
  });
});

describe('belge çıktısı', () => {
  it('linkOf: docs/ içinden köke göre bağlantı ve aralık', () => {
    assert.equal(linkOf('a/b.js', 12), '[a/b.js:12](../a/b.js#L12)');
    assert.equal(linkOf('a/b.js', 12, 20), '[a/b.js:12-20](../a/b.js#L12-L20)');
  });

  describe('renderAll (belge seti)', () => {
    const io = fakeIo(sample);
    const makeArea = () =>
      resolveArea(
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
              refs: [
                { file: 'a/x.js', find: 'router.post(', note: 'uç nokta | borulu' },
                { file: 'a/x.js', find: 'end marker', note: 'son satır' },
              ],
              causes: ['Yanlış parola'],
              logs: ['~[API] dinamik 401', '[API] sabit'],
              commands: ['pm2 logs kapi-api'],
              related: ['demo-ikinci'],
            },
            {
              id: 'demo-ikinci',
              symptom: 'İkinci arıza belirtisi burada',
              refs: [{ file: 'a/x.js', find: 'two', note: 'iki' }],
            },
          ],
        },
        io,
      );
    const scans = { routes: [], appCalls: [], env: [], tables: [], coverage: [] };
    const build = (status) => renderAll([makeArea()], scans, { server: [], app: [] }, status);

    it('beklenen belge seti üretilir ve deterministiktir', () => {
      const a = build({ verified: [], note: 'Not metni.' });
      const b = build({ verified: [], note: 'Not metni.' });
      assert.deepEqual(
        [...a.keys()].sort(),
        [
          'docs/ARIZA_KLAVUZU.md',
          'docs/ARIZA_KLAVUZU_EKLER.md',
          'docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md',
          'docs/ARIZA_KLAVUZU_INDEKS.md',
          'docs/ariza-klavuzu/demo.md',
        ],
      );
      for (const [rel, content] of a) {
        assert.equal(content, b.get(rel), `${rel}: aynı girdi aynı çıktı`);
        assert.equal(content.includes('undefined'), false, `${rel}: "undefined" sızdı`);
      }
    });

    it('ana sayfa: kapsam sayıları, doğrulama durumu, not ve bölüm tablosu', () => {
      const landing = build({ verified: [], note: 'Not metni.' }).get('docs/ARIZA_KLAVUZU.md');
      assert.match(landing, /1 bölüm, \*\*2 arıza girişi\*\*, 3 kod bağlantısı/);
      assert.match(landing, /0\/1 bölüm geçti\. Not metni\./);
      assert.match(landing, /\| \[Demo Alanı\]\(ariza-klavuzu\/demo\.md\) \| 2 \| 3 \| ⚠ doğrulanmadı \|/);
    });

    it('indeks: belirti -> ilk bağlantı, ek bağlantı sayısı, anahtar sözcükler, giriş bağlantısı', () => {
      const index = build({ verified: [], note: '' }).get('docs/ARIZA_KLAVUZU_INDEKS.md');
      assert.match(
        index,
        /- \*\*Giriş yapılamıyor, 401 dönüyor\*\* → \[a\/x\.js:2\]\(\.\.\/a\/x\.js#L2\) \(\+1 bağlantı\) · `giriş, 401` · \[giriş\]\(ariza-klavuzu\/demo\.md#demo-giris\)/,
      );
      assert.match(index, /## Demo Alanı \(2\) — ⚠ doğrulanmadı/);
    });

    it('bölüm dosyası: çapa, ../../ kod bağlantısı, | kaçırma, ~ gösterilmez, aynı alan bkz. #id', () => {
      const doc = build({ verified: [], note: '' }).get('docs/ariza-klavuzu/demo.md');
      assert.match(doc, /<a id="demo-giris"><\/a>/);
      assert.match(doc, /\[a\/x\.js:2\]\(\.\.\/\.\.\/a\/x\.js#L2\)/);
      assert.match(doc, /uç nokta \\\| borulu/);
      assert.match(doc, /- `\[API\] dinamik 401`/, '"~" öneki belgede görünmez');
      assert.equal(doc.includes('`~'), false);
      assert.match(doc, /\*\*Bkz\.:\*\* \[demo-ikinci\]\(#demo-ikinci\)/);
      assert.match(doc, /⚠ \*\*Doğrulanmadı:\*\*/);
    });

    it('doğrulanmış bölüm ✓ ile işaretlenir', () => {
      const docs = build({ verified: ['demo'], note: '' });
      assert.match(docs.get('docs/ariza-klavuzu/demo.md'), /✓ \*\*Doğrulandı:\*\*/);
      assert.match(docs.get('docs/ARIZA_KLAVUZU_INDEKS.md'), /## Demo Alanı \(2\) — ✓/);
      assert.match(docs.get('docs/ARIZA_KLAVUZU.md'), /\| ✓ doğrulandı \|/);
    });
  });

  it('loadStatus: durum dosyasını okur; yok ya da bozuksa hiçbiri doğrulanmamış sayılır', () => {
    const ok = loadStatus(fakeIo({ 'tools/klavuz/durum.json': '{"dogrulananAlanlar":["a","b"],"not":"n"}' }));
    assert.deepEqual(ok, { verified: ['a', 'b'], note: 'n' });
    assert.deepEqual(loadStatus(fakeIo({})), { verified: [], note: '' });
    assert.deepEqual(loadStatus(fakeIo({ 'tools/klavuz/durum.json': '{bozuk' })), { verified: [], note: '' });
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
      check: true, fresh: true, only: 'x', where: null, explain: null, coverage: false, help: false,
    });
    assert.equal(parseArgs(['--coverage']).coverage, true);
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
    assert.match(text, /^> {5}2 \| router\.post\("\/p"\)/m, 'hedef satır > ile işaretlenir');
    assert.match(text, /^ {6}1 \| one/m, 'önceki satır bağlam olarak gelir');
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
      assert.equal(logs.some((l) => /UYARI/.test(l)), false, `mekanik denetim uyarısı var:\n${logs.join('\n')}`);
    } finally {
      console.log = original;
      console.error = originalError;
    }
  });

  it('alan dosyaları yüklenebilir (sözdizimi)', async () => {
    const areas = await loadAreas();
    for (const a of areas) assert.ok(a.key && a.title, `alan: ${a.key}`);
  });

  it('üretilen belgelerdeki TÜM bağlantılar gerçek: dosya var, satır dosyada mevcut, çapa var', async () => {
    const io = createIo();
    const { areas: loaded, failures } = await loadAreasTolerant();
    assert.deepEqual(failures, []);
    const areas = loaded
      .map((a) => resolveArea(a, io))
      .sort((a, b) => a.order - b.order || a.key.localeCompare(b.key));
    const docs = renderAll(
      areas,
      {
        routes: scanRoutes(io),
        appCalls: scanAppCalls(io),
        env: scanEnv(io),
        tables: scanTables(io),
        coverage: scanCoverage(io, areas),
      },
      scanMessages(io),
      loadStatus(io),
    );
    const anchors = new Map(
      [...docs].map(([rel, content]) => [rel, new Set([...content.matchAll(/<a id="([^"]+)"><\/a>/g)].map((m) => m[1]))]),
    );
    const problems = [];
    let checked = 0;
    for (const [rel, content] of docs) {
      const dir = path.posix.dirname(rel);
      for (const m of content.matchAll(/\]\(([^)\s]+)\)/g)) {
        const target = m[1];
        if (/^(https?:|mailto:)/.test(target)) continue;
        checked += 1;
        const [filePart, anchor] = target.split('#');
        const resolved = filePart ? path.posix.normalize(path.posix.join(dir, filePart)) : rel;
        if (docs.has(resolved)) {
          if (anchor && !/^L\d/.test(anchor) && !anchors.get(resolved).has(anchor)) problems.push(`${rel}: çapa yok → ${target}`);
          continue;
        }
        if (!io.exists(resolved)) {
          problems.push(`${rel}: hedef yok → ${target}`);
          continue;
        }
        const lineMatch = /^L(\d+)(?:-L(\d+))?$/.exec(anchor ?? '');
        if (lineMatch) {
          const count = io.lines(resolved)?.length ?? 0;
          if (Number(lineMatch[1]) > count || (lineMatch[2] && Number(lineMatch[2]) > count)) {
            problems.push(`${rel}: satır dosyada yok → ${target} (dosya ${count} satır)`);
          }
        }
      }
    }
    assert.ok(checked > 1000, `beklenenden az bağlantı denetlendi: ${checked}`);
    assert.deepEqual(problems.slice(0, 15), []);
  });
});
