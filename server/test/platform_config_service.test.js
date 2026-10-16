// Platform ayarları servisi (DB'siz): alan doğrulaması, kısmi güncelleme gövdesi, okuma varsayılanları, tek-transaction güncelleme
// (yalnız değişen anahtarlar yazılır, audit YALNIZ anahtar adları taşır, sürüm aralığı denetimi, boş dize siler).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  ALL_SETTING_KEYS,
  CONFIG_FIELDS,
  compareVersionArrays,
  configFromRows,
  normalizeConfigPatch,
  parseFlag,
  parseStrictVersion,
  readPlatformConfig,
  updatePlatformConfig,
  validateConfigValue,
} from '../src/modules/platform_config_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

const field = (group, name) => CONFIG_FIELDS[group][name];
const good = (group, name, value) => {
  const result = validateConfigValue(field(group, name), value);
  assert.ok(result.ok, `${group}.${name}=${JSON.stringify(value)} geçerli olmalıydı: ${result.message}`);
  return result.value;
};
const bad = (group, name, value) => {
  const result = validateConfigValue(field(group, name), value);
  assert.equal(result.ok, false, `${group}.${name}=${JSON.stringify(value)} reddedilmeliydi`);
  assert.ok(typeof result.message === 'string' && result.message.length > 0);
};

describe('sürüm yardımcıları', () => {
  it('parseStrictVersion: yalnız major.minor.patch', () => {
    assert.deepEqual(parseStrictVersion('1.2.3'), [1, 2, 3]);
    assert.deepEqual(parseStrictVersion('10.0.250'), [10, 0, 250]);
    for (const text of ['1.2', '1.2.3.4', '1.2.3+4', 'v1.2.3', '1.2.x', '', ' 1.2.3', '1.2.3-beta', null, 5]) {
      assert.equal(parseStrictVersion(text), null, String(text));
    }
  });

  it('compareVersionArrays sayısal karşılaştırır (1.10.0 > 1.9.0)', () => {
    assert.equal(compareVersionArrays([1, 10, 0], [1, 9, 0]), 1);
    assert.equal(compareVersionArrays([1, 9, 0], [1, 10, 0]), -1);
    assert.equal(compareVersionArrays([2, 0, 0], [2, 0, 0]), 0);
    assert.equal(compareVersionArrays([1, 0, 9], [1, 1, 0]), -1);
  });

  it('parseFlag: true / 1 / "on" / "true" / "1" / "yes" açık; gerisi kapalı', () => {
    for (const value of [true, 1, 'on', 'ON', ' true ', '1', 'yes']) assert.equal(parseFlag(value), true, String(value));
    for (const value of [false, 0, 'off', 'false', '0', 'no', '', null, undefined, 2, {}, []]) assert.equal(parseFlag(value), false, String(value));
  });
});

describe('alan doğrulaması', () => {
  it('sürümler ^\\d+\\.\\d+\\.\\d+$', () => {
    assert.equal(good('app', 'min_supported_version', ' 1.2.3 '), '1.2.3');
    for (const value of ['1.2', '1.2.3.4', 'v1.2.3', '1.2.3+4', 'a.b.c', '1.2.3 beta', '1.2.-3', '1234567890.0.0']) bad('app', 'latest_version', value);
    assert.equal(good('app', 'latest_version', ''), '');
    assert.equal(good('app', 'latest_version', null), '');
    assert.equal(good('app', 'latest_version', '   '), '');
    bad('app', 'latest_version', 120);
  });

  it('URL: yalnız https://, boşluk / tırnak / kimlik bilgisi yok, en çok 500 karakter', () => {
    assert.equal(good('app', 'update_url_android', 'https://play.google.com/store/apps/details?id=tr.x'), 'https://play.google.com/store/apps/details?id=tr.x');
    assert.equal(good('support', 'web_url', 'HTTPS://example.com/destek'), 'HTTPS://example.com/destek');
    for (const value of [
      'http://example.com',
      'javascript:alert(1)',
      'ftp://example.com',
      '//example.com',
      'example.com',
      'https://',
      'https://user:pw@example.com/',
      'https://exa mple.com',
      'https://example.com/"onclick="x',
      "https://example.com/'",
      'https://example.com/<x>',
      `https://example.com/${'a'.repeat(500)}`,
      'https://example.com/\nSet-Cookie: x',
      'data:text/html,<script>',
    ]) {
      bad('app', 'update_url_ios', value);
    }
  });

  it('e-posta biçimi; telefon biçimi (7-15 hane); MERSİS 16 hane (boşluk / tire atılır)', () => {
    assert.equal(good('support', 'email', 'destek@example.com'), 'destek@example.com');
    for (const value of ['destek', 'a@b', 'a b@example.com', '<a@example.com>', 'a@example.com,b@example.com', "a'b@example.com", 'a@exa mple.com', `${'x'.repeat(250)}@example.com`]) bad('support', 'email', value);
    bad('legal', 'kep_address', 'kep');
    assert.equal(good('legal', 'kep_address', 'firma@hs01.kep.tr'), 'firma@hs01.kep.tr');

    assert.equal(good('support', 'phone', '+90 (212) 000 00 00'), '+90 (212) 000 00 00');
    assert.equal(good('legal', 'contact_phone', '0850 000 00 00'), '0850 000 00 00');
    assert.equal(good('support', 'phone', ''), '');
    for (const value of ['abc', '12345', '+90 212 000 00 00 99 99 99', '<script>', '0212 000 00 00; DROP']) bad('support', 'phone', value);

    assert.equal(good('legal', 'mersis_no', '0123 4567 8901 2345'), '0123456789012345');
    assert.equal(good('legal', 'mersis_no', '0123-4567-8901-2345'), '0123456789012345');
    for (const value of ['123', '01234567890123456', '01234567890123AB', '0123456789012345 0']) bad('legal', 'mersis_no', value);
  });

  it('serbest metin: kontrol karakterleri / yeni satır boşluğa çevrilir ve sıkıştırılır; uzunluk sınırı', () => {
    assert.equal(good('support', 'hours', ' Hafta içi\n09:00 \t- 18:00\u0000 '), 'Hafta içi 09:00 - 18:00');
    assert.equal(good('app', 'maintenance_message', 'Bakımdayız <b>kısa süre</b> & dönüyoruz'), 'Bakımdayız <b>kısa süre</b> & dönüyoruz', 'düz metin gösterim alanı: işaret reddedilmez (istemci düz metin gösterir)');
    bad('support', 'hours', 'x'.repeat(201));
    bad('app', 'maintenance_message', 'x'.repeat(501));
    bad('support', 'hours', 5);
    bad('support', 'hours', {});
    bad('support', 'hours', ['a']);
  });

  it('yasal metin alanları (şirket adı / adres) Markdown + HTML ayırıcılarını REDDEDER; normal noktalama geçer', () => {
    assert.equal(good('legal', 'company_name', 'Güde Teknoloji (Ltd.) A.Ş. - "Site" & Co.'), 'Güde Teknoloji (Ltd.) A.Ş. - "Site" & Co.');
    assert.equal(good('legal', 'company_address', 'Atatürk Mah. 1. Sk. No:3/4 Çankaya / ANKARA'), 'Atatürk Mah. 1. Sk. No:3/4 Çankaya / ANKARA');
    for (const value of ['A [x](https://e.com)', 'A <b>', 'A `kod`', 'A \\ B', '**kalın**', '# Başlık', '- madde', '> alıntı', '+ x', '* x', 'x'.repeat(201)]) bad('legal', 'company_name', value);
    bad('legal', 'company_address', 'x'.repeat(501));
  });

  it('boolean alanlar: yalnız true / false (null = false); metin ve sayı reddedilir', () => {
    assert.equal(good('app', 'maintenance_active', true), true);
    assert.equal(good('legal', 'enforce_consents', false), false);
    assert.equal(good('legal', 'enforce_consents', null), false);
    for (const value of ['true', 'on', 1, 0, {}, []]) bad('legal', 'enforce_consents', value);
  });
});

describe('normalizeConfigPatch', () => {
  it('kısmi gövde: yalnız gönderilen anahtarlar; boş dize = ayarsız', () => {
    const { patch, errors } = normalizeConfigPatch({ app: { latest_version: '2.0.0', update_url_ios: '' }, legal: { enforce_consents: true } });
    assert.deepEqual(errors, {});
    assert.deepEqual(patch, { 'app.latest_version': '2.0.0', 'app.update_url_ios': '', 'legal.enforce_consents': true });
    assert.deepEqual(normalizeConfigPatch({}), { patch: {}, errors: {} });
    assert.deepEqual(normalizeConfigPatch({ app: {} }), { patch: {}, errors: {} });
  });

  it('bilinmeyen grup / alan, nesne olmayan grup ve gövde hata verir; tüm hatalar birlikte toplanır', () => {
    const { errors } = normalizeConfigPatch({
      app: { latest_version: 'x', yok_boyle: 1 },
      kapsam: { a: 1 },
      support: 'metin',
      legal: [],
    });
    assert.equal(errors['app.latest_version'], 'sürüm major.minor.patch biçiminde olmalıdır (örn. 1.2.0).');
    assert.equal(errors['app.yok_boyle'], 'bilinmeyen alan.');
    assert.equal(errors.kapsam, 'bilinmeyen grup.');
    assert.equal(errors.support, 'bir nesne olmalıdır.');
    assert.equal(errors.legal, 'bir nesne olmalıdır.');
    for (const body of [null, undefined, 'x', 5, []]) {
      assert.deepEqual(Object.keys(normalizeConfigPatch(body).errors), ['_body']);
    }
  });

  it('JSON.parse ile gelen "__proto__" anahtarı sessizce yutulmaz (hata olarak raporlanır) ve prototipi kirletmez', () => {
    const body = JSON.parse('{"__proto__": {"polluted": true}, "app": {"__proto__": 1, "constructor": 2, "hasOwnProperty": 3}}');
    const { patch, errors } = normalizeConfigPatch(body);
    assert.equal(Object.keys(errors).length, 4);
    assert.equal(errors.__proto__, 'bilinmeyen grup.');
    assert.equal(({}).polluted, undefined);
    assert.deepEqual({ ...patch }, {});
  });
});

describe('configFromRows / readPlatformConfig', () => {
  it('boş tablo: metinler "", boolean\'lar false; tüm alanlar sözleşmedeki şekilde', () => {
    const config = configFromRows([]);
    assert.deepEqual(config, {
      app: { min_supported_version: '', latest_version: '', update_url_android: '', update_url_ios: '', maintenance_active: false, maintenance_message: '' },
      support: { email: '', phone: '', hours: '', web_url: '' },
      legal: { company_name: '', company_address: '', mersis_no: '', kep_address: '', contact_email: '', contact_phone: '', enforce_consents: false },
    });
    assert.equal(ALL_SETTING_KEYS.length, 17);
    assert.ok(ALL_SETTING_KEYS.every((key) => /^(app|support|legal)\.[a-z_]+$/.test(key)));
  });

  it('metin olmayan saklı değer "" sayılır; boolean eski "on" metnini de okur; ilgisiz anahtarlar yok sayılır', () => {
    const config = configFromRows([
      { key: 'app.latest_version', value: 5 },
      { key: 'support.email', value: 'a@b.co' },
      { key: 'legal.enforce_consents', value: 'on' },
      { key: 'site_onboarding', value: { mode: 'approval' } },
    ]);
    assert.equal(config.app.latest_version, '');
    assert.equal(config.support.email, 'a@b.co');
    assert.equal(config.legal.enforce_consents, true);
    assert.equal(JSON.stringify(config).includes('site_onboarding'), false);
  });

  it('readPlatformConfig yalnız bilinen anahtarları ister (tek sorgu, ANY)', async () => {
    const seen = [];
    const config = await readPlatformConfig({
      async query(text, params) {
        seen.push({ sql: norm(text), params });
        return ok([{ key: 'support.hours', value: '7/24' }]);
      },
    });
    assert.equal(seen.length, 1);
    assert.match(seen[0].sql, /^SELECT key, value FROM platform_settings WHERE key = ANY\(\$1::text\[\]\)$/);
    assert.deepEqual(seen[0].params, [ALL_SETTING_KEYS]);
    assert.equal(config.support.hours, '7/24');
  });
});

describe('updatePlatformConfig', () => {
  const actor = { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Root Kişi', email: 'root@example.com' };
  let stored;
  let log;
  let failOn;
  let connects;

  function install() {
    const handle = async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (failOn && failOn.test(sql)) throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql)) return ok();
      if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
      if (/^SELECT key, value FROM platform_settings WHERE key = ANY/.test(sql)) {
        return ok(Object.entries(stored).map(([key, value]) => ({ key, value })));
      }
      if (/^INSERT INTO platform_settings/.test(sql)) {
        stored[params[0]] = JSON.parse(params[1]);
        return ok([], 1);
      }
      if (/^DELETE FROM platform_settings WHERE key = \$1$/.test(sql)) {
        delete stored[params[0]];
        return ok([], 1);
      }
      if (/^INSERT INTO audit_log/.test(sql)) return ok([], 1);
      throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    };
    pool.connect = async () => {
      connects += 1;
      return { query: handle, release() {} };
    };
  }

  beforeEach(() => {
    stored = {};
    log = [];
    failOn = null;
    connects = 0;
    mock.method(console, 'error', () => {});
    install();
  });

  afterEach(() => {
    delete pool.connect;
    mock.restoreAll();
  });

  const sqlOf = () => log.map((entry) => entry.sql);

  it('geçersiz gövde: 400 VALIDATION_FAILED { fields }; veritabanına HİÇ bağlanılmaz', async () => {
    await assert.rejects(
      updatePlatformConfig({ body: { app: { latest_version: 'x' }, support: { email: 'yanlis' } }, actor }),
      (error) => {
        assert.equal(error.statusCode, 400);
        assert.equal(error.code, 'VALIDATION_FAILED');
        assert.deepEqual(Object.keys(error.extra.fields).sort(), ['app.latest_version', 'support.email']);
        return true;
      },
    );
    assert.equal(connects, 0);
  });

  it('kısmi güncelleme: yalnız DEĞİŞEN anahtarlar yazılır; sıra BEGIN, kilit, okuma, yazma, audit, COMMIT', async () => {
    stored = { 'app.latest_version': '1.0.0', 'support.email': 'eski@example.com' };
    const { config, changed } = await updatePlatformConfig({
      body: { app: { latest_version: '1.1.0', min_supported_version: '1.0.0' }, support: { email: 'eski@example.com' } },
      actor,
    });
    assert.deepEqual([...changed].sort(), ['app.latest_version', 'app.min_supported_version']);
    assert.equal(config.app.latest_version, '1.1.0');
    assert.equal(config.app.min_supported_version, '1.0.0');
    assert.equal(config.support.email, 'eski@example.com');
    const sql = sqlOf();
    assert.equal(sql[0], 'BEGIN');
    assert.match(sql[1], /^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/);
    assert.match(sql[2], /^SELECT key, value FROM platform_settings/);
    assert.equal(sql.filter((s) => /^INSERT INTO platform_settings/.test(s)).length, 2);
    assert.equal(sql.filter((s) => /^DELETE FROM platform_settings/.test(s)).length, 0);
    assert.equal(sql.at(-1), 'COMMIT');
    assert.deepEqual(stored, { 'app.latest_version': '1.1.0', 'support.email': 'eski@example.com', 'app.min_supported_version': '1.0.0' });
    for (const entry of log.filter((e) => /^INSERT INTO platform_settings/.test(e.sql))) {
      assert.equal(entry.params[2], 1, 'updated_by = eylemi yapan kullanıcı');
    }
  });

  it('DENETİM: audit_log satırı YALNIZ değişen anahtar adlarını taşır; hiçbir değer (e-posta, telefon, adres, URL) yazılmaz', async () => {
    await updatePlatformConfig({
      body: {
        legal: { company_name: 'Çok Gizli Ünvan A.Ş.', company_address: 'Gizli Mah. 7. Sk.', contact_phone: '+90 555 111 22 33', enforce_consents: true },
        support: { email: 'ozel@example.com', web_url: 'https://gizli.example.com/yol' },
      },
      actor,
    });
    const audits = log.filter((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(audits.length, 1);
    const [, , , action, , targetType, , details] = audits[0].params;
    assert.equal(action, 'platform_config.updated');
    assert.equal(targetType, 'platform_config');
    assert.deepEqual(JSON.parse(details), {
      keys: ['legal.company_address', 'legal.company_name', 'legal.contact_phone', 'legal.enforce_consents', 'support.email', 'support.web_url'],
    });
    const everything = JSON.stringify(audits[0].params);
    for (const secret of ['Çok Gizli', 'Gizli Mah', '555 111', 'ozel@example.com', 'gizli.example.com']) {
      assert.equal(everything.includes(secret), false, secret);
    }
    assert.equal(audits[0].params[0], 1, 'eylemi yapan kullanıcı kodu');
  });

  it('değişiklik yoksa hiçbir yazma ve audit yok (yine de COMMIT)', async () => {
    stored = { 'app.latest_version': '1.5.0', 'legal.enforce_consents': true };
    const { changed } = await updatePlatformConfig({ body: { app: { latest_version: '1.5.0' }, legal: { enforce_consents: true }, support: { email: '' } }, actor });
    assert.deepEqual(changed, []);
    assert.equal(sqlOf().some((s) => /^(INSERT|DELETE)/.test(s)), false);
    assert.equal(sqlOf().at(-1), 'COMMIT');
  });

  it('boş dize / null anahtarı siler; boolean false açıkça yazılır (silinmez)', async () => {
    stored = { 'support.phone': '+90 212 000 00 00', 'legal.enforce_consents': true, 'app.maintenance_message': 'x' };
    const { config, changed } = await updatePlatformConfig({
      body: { support: { phone: '' }, legal: { enforce_consents: false }, app: { maintenance_message: null } },
      actor,
    });
    assert.deepEqual([...changed].sort(), ['app.maintenance_message', 'legal.enforce_consents', 'support.phone']);
    assert.deepEqual(stored, { 'legal.enforce_consents': false });
    assert.equal(config.support.phone, '');
    assert.equal(config.legal.enforce_consents, false);
    assert.equal(sqlOf().filter((s) => /^DELETE FROM platform_settings/.test(s)).length, 2);
  });

  it('BİRLEŞİK durumda en düşük sürüm en son sürümden büyük olamaz: 400 INVALID_VERSION_RANGE, ROLLBACK, yazma yok', async () => {
    stored = { 'app.latest_version': '1.4.0' };
    await assert.rejects(
      updatePlatformConfig({ body: { app: { min_supported_version: '2.0.0' } }, actor }),
      (error) => error.code === 'INVALID_VERSION_RANGE' && error.statusCode === 400 && 'app.min_supported_version' in error.extra.fields,
    );
    assert.equal(sqlOf().some((s) => /^INSERT INTO platform_settings/.test(s)), false);
    assert.equal(sqlOf().at(-1), 'ROLLBACK');
    assert.deepEqual(stored, { 'app.latest_version': '1.4.0' });
    // her ikisi birlikte tutarlı gönderilirse geçer; eşit sürüm de geçer
    await updatePlatformConfig({ body: { app: { min_supported_version: '2.0.0', latest_version: '2.0.0' } }, actor });
    assert.equal(stored['app.min_supported_version'], '2.0.0');
    // yalnız son sürümü düşürmek de aralığı bozarsa reddedilir
    await assert.rejects(updatePlatformConfig({ body: { app: { latest_version: '1.9.9' } }, actor }), (error) => error.code === 'INVALID_VERSION_RANGE');
    // min ayarsızsa aralık denetimi yok
    await updatePlatformConfig({ body: { app: { min_supported_version: '' } }, actor });
    await updatePlatformConfig({ body: { app: { latest_version: '1.0.0' } }, actor });
    assert.equal(stored['app.latest_version'], '1.0.0');
  });

  it('veritabanı hatası: ROLLBACK, hata yukarı gider, bağlantı iade edilir; yazma başarısızsa audit de yok', async () => {
    let released = 0;
    const installed = pool.connect;
    pool.connect = async () => {
      const client = await installed();
      return { query: client.query, release: () => { released += 1; } };
    };
    failOn = /^INSERT INTO platform_settings/;
    await assert.rejects(updatePlatformConfig({ body: { app: { latest_version: '3.0.0' } }, actor }), /SECRET_DB_DETAIL/);
    assert.equal(sqlOf().at(-1), 'ROLLBACK');
    assert.equal(released, 1);
    assert.equal(sqlOf().some((s) => /^INSERT INTO audit_log/.test(s)), false);
  });
});
