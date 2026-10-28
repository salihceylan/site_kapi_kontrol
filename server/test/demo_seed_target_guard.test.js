// Demo tohum araclarinin hedef korumasi (karsilastirma programi P1-19, 2026-10-28).
//
// tools/demo_seed/{seed,cleanup,restructure_families,add_vehicles}.mjs SAHTE veri yazar ve siler. Elle calistirilan bir arac yanlislikla canli
// (ya da baska) bir veritabanina yazmasin diye hedef, baglanmadan ONCE dogrulanir: yalniz yerel (geri donus sunucusu + izinli veritabani adi)
// ya da `--allow-target <veritabani adi>` ile AYNEN onaylanmis hedef. DB'ye baglanmaz: saf kosullar ve kaynak taramasi.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  LOCAL_DATABASE_NAMES,
  assertDemoTarget,
  checkDemoTarget,
  isLocalDatabaseName,
  isLoopbackHost,
  requireDemoTarget,
  targetRefusalMessage,
} from '../../tools/demo_seed/lib/target_guard.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (relative) => readFileSync(path.join(root, relative), 'utf8').replace(/\r\n/g, '\n');
const urlOf = (hostPart, database) => `postgres://postgres:gizli-parola@${hostPart}/${database}`;

test('yerel kip: geri donus sunucusu + izinli veritabani adi kabul edilir', () => {
  const accepted = [
    urlOf('127.0.0.1:55460', 'demo_seed_test'),
    urlOf('127.0.0.1:55460', 'demo_restr_test'),
    urlOf('127.0.0.1:55460', 'demo_veh_test'),
    urlOf('localhost:5432', 'site_kapi_yerel'),
    urlOf('LOCALHOST:5432', 'site_kapi_yerel_test'),
    urlOf('[::1]:5432', 'demo_veh_test'),
    urlOf('127.0.0.1', 'demo_seed_rehearsal_20261028_121212'),
    urlOf('127.0.0.1', 'demo_restr_rehearsal_20261028_121212'),
    urlOf('127.0.0.1', 'demo_veh_rehearsal_20261028_121212'),
  ];
  for (const url of accepted) {
    const check = checkDemoTarget(url, {});
    assert.equal(check.ok, true, url);
    assert.equal(check.mode, 'local', url);
    assert.equal(assertDemoTarget(url, {}).ok, true, url);
  }
});

test('bayraksiz: canli benzeri ad, uzak sunucu, kandirmaca adresler ve bozuk adres reddedilir', () => {
  const refused = [
    urlOf('127.0.0.1:5432', 'site_kapi_kontrol'),
    urlOf('127.0.0.1:5432', 'postgres'),
    urlOf('178.210.161.55:5432', 'demo_seed_test'),
    urlOf('178.210.161.55:5432', 'site_kapi_kontrol'),
    urlOf('127.0.0.1.evil.example:5432', 'demo_seed_test'),
    'postgres://127.0.0.1@evil.example:5432/demo_seed_test',
    'postgres:///demo_seed_test',
    urlOf('127.0.0.1', 'DEMO_SEED_TEST'),
    urlOf('127.0.0.1', 'Site_Kapi_Yerel'),
    urlOf('127.0.0.1', 'demo_seed_'),
    urlOf('127.0.0.1', 'demo_seed_test%20x'),
    urlOf('127.0.0.1', 'demo_other_test'),
    'bu bir adres degil',
  ];
  for (const url of refused) {
    const check = checkDemoTarget(url, {});
    assert.equal(check.ok, false, url);
    assert.ok(check.reason && check.reason.length > 0, `neden bos: ${url}`);
    assert.throws(() => assertDemoTarget(url, {}), (error) => error.code === 'DEMO_TARGET_REFUSED', url);
  }
});

test('ret mesaji hedefi ve cikis yolunu soyler; parolayi ASLA yazmaz', () => {
  const check = checkDemoTarget(urlOf('178.210.161.55:5432', 'site_kapi_kontrol'), {});
  const message = targetRefusalMessage(check);
  assert.match(message, /DURDURULDU/);
  assert.match(message, /postgres@178\.210\.161\.55:5432\/site_kapi_kontrol/);
  assert.match(message, /--allow-target <veritabani adi>/);
  for (const name of LOCAL_DATABASE_NAMES) assert.ok(message.includes(name), name);
  assert.equal(message.includes('gizli-parola'), false, 'parola mesaja sizdi');
});

test('acik izin: --allow-target adi AYNEN yazilirsa kabul; yanlis, adsiz, bos ya da buyuk/kucuk harf farkli ad reddedilir', () => {
  const remote = urlOf('178.210.161.55:5432', 'site_kapi_kontrol');
  const ok = checkDemoTarget(remote, { 'allow-target': 'site_kapi_kontrol' });
  assert.equal(ok.ok, true);
  assert.equal(ok.mode, 'explicit');

  for (const flag of ['baska_db', 'Site_Kapi_Kontrol', 'site_kapi_kontrol ', '', true]) {
    const check = checkDemoTarget(remote, { 'allow-target': flag });
    assert.equal(check.ok, false, JSON.stringify(flag));
  }
  assert.match(checkDemoTarget(remote, { 'allow-target': 'baska_db' }).reason, /ayni degil/);
  assert.match(checkDemoTarget(remote, { 'allow-target': true }).reason, /veritabani adini ister/);

  // Onay yalniz o veritabani icindir: baska bir ad icin verilen bayrak canliyi acmaz.
  assert.equal(checkDemoTarget(urlOf('127.0.0.1', 'site_kapi_kontrol'), { 'allow-target': 'demo_seed_test' }).ok, false);
  // Yerel izinli hedefte bayrak gerekmez (verilirse de yerel kip kazanir).
  assert.equal(checkDemoTarget(urlOf('127.0.0.1', 'demo_seed_test'), { 'allow-target': 'baska_db' }).mode, 'local');
});

test('requireDemoTarget: ret = mesaj + cikis kodu 2; acik izin = tek uyari satiri; yerel kip sessiz', () => {
  const capture = () => {
    const seen = { errors: [], warns: [], exit: null };
    return {
      seen,
      options: {
        out: { error: (m) => seen.errors.push(m), warn: (m) => seen.warns.push(m) },
        exit: (code) => {
          seen.exit = code;
          return code;
        },
      },
    };
  };

  const refused = capture();
  requireDemoTarget(urlOf('178.210.161.55:5432', 'site_kapi_kontrol'), {}, refused.options);
  assert.equal(refused.seen.exit, 2);
  assert.equal(refused.seen.errors.length, 1);
  assert.match(refused.seen.errors[0], /DURDURULDU/);

  const explicit = capture();
  const check = requireDemoTarget(urlOf('178.210.161.55:5432', 'site_kapi_kontrol'), { 'allow-target': 'site_kapi_kontrol' }, explicit.options);
  assert.equal(check.mode, 'explicit');
  assert.equal(explicit.seen.exit, null);
  assert.equal(explicit.seen.warns.length, 1);
  assert.match(explicit.seen.warns[0], /--allow-target/);
  assert.equal(explicit.seen.warns[0].includes('gizli-parola'), false);

  const local = capture();
  requireDemoTarget(urlOf('127.0.0.1:55460', 'demo_seed_test'), {}, local.options);
  assert.deepEqual(local.seen, { errors: [], warns: [], exit: null });
});

test('yardimcilar: loopback adlari ve yerel veritabani adi kurali', () => {
  for (const host of ['127.0.0.1', 'localhost', 'LocalHost', '::1', '[::1]']) assert.equal(isLoopbackHost(host), true, host);
  for (const host of ['', '0.0.0.0', '127.0.0.2', '10.0.0.5', 'db', 'localhost.evil.example', undefined]) assert.equal(isLoopbackHost(host), false, String(host));
  for (const name of [...LOCAL_DATABASE_NAMES, 'demo_seed_test', 'demo_restr_test', 'demo_veh_test', 'demo_seed_rehearsal_20261028_121212']) {
    assert.equal(isLocalDatabaseName(name), true, name);
  }
  for (const name of ['', 'site_kapi_kontrol', 'postgres', 'demo_seed', 'demo_seed_', 'demo-seed-test', 'Demo_Seed_Test', undefined]) {
    assert.equal(isLocalDatabaseName(name), false, String(name));
  }
});

test('dort arac hedefi baglanmadan ONCE dogrular (kaynak taramasi)', () => {
  for (const tool of ['seed.mjs', 'cleanup.mjs', 'restructure_families.mjs', 'add_vehicles.mjs']) {
    const text = read(`tools/demo_seed/${tool}`);
    assert.ok(text.includes("import { requireDemoTarget } from './lib/target_guard.mjs';"), `${tool}: koruma import edilmemis`);
    const guardAt = text.indexOf('requireDemoTarget(url, args);');
    assert.ok(guardAt > 0, `${tool}: requireDemoTarget(url, args) cagrisi yok`);
    const dbAt = Math.min(...['applyDbEnv(url)', 'newPgClient(serverRequire, url)'].map((needle) => text.indexOf(needle)).filter((index) => index >= 0));
    assert.ok(guardAt < dbAt, `${tool}: koruma baglantiya/ortam kurulumuna ONCE cagrilmali`);
    assert.ok(text.indexOf("if (!url) {") < guardAt, `${tool}: DATABASE_URL varlik denetiminden sonra`);
  }
});

test('run_remote*.sh her arac cagrisinda hedefi acikca onaylar (prova: gecici ad, canli: DB_NAME) ve geri alma notu bayragi tasir', () => {
  for (const script of ['run_remote.sh', 'run_remote_restructure.sh', 'run_remote_vehicles.sh']) {
    const lines = read(`tools/demo_seed/${script}`).split('\n');
    const calls = lines.filter((line) => /DATABASE_URL="\$(REH|PROD)_URL"\s+node\s+"\$SEED_DIR\//.test(line));
    assert.equal(calls.length, 3, `${script}: 2 prova + 1 canli arac cagrisi beklenir (bulunan ${calls.length})`);
    for (const line of calls) {
      const expected = line.includes('"$REH_URL"') ? '--allow-target "$RDB"' : '--allow-target "$DB_NAME"';
      assert.ok(line.includes(expected), `${script}: ${expected} eksik: ${line.trim().slice(0, 120)}`);
    }
    const rollback = lines.find((line) => line.includes('GERI ALMA:') && line.includes('cleanup.mjs'));
    assert.ok(rollback?.includes('--allow-target $DB_NAME'), `${script}: geri alma notu --allow-target icermiyor`);
  }
});

test('yerel testlerin ve prova betiklerinin veritabani adlari izin listesine uyar; README listeyi anlatir', () => {
  for (const file of ['local_test.mjs', 'local_restructure_test.mjs', 'local_vehicles_test.mjs']) {
    const match = /const dbName = '([a-z0-9_]+)';/.exec(read(`tools/demo_seed/test/${file}`));
    assert.ok(match, `${file}: dbName bulunamadi`);
    assert.equal(isLocalDatabaseName(match[1]), true, `${file}: ${match[1]} izin listesinde degil (yerel test korumaya takilir)`);
  }
  for (const script of ['run_remote.sh', 'run_remote_restructure.sh', 'run_remote_vehicles.sh']) {
    const match = /^RDB="([a-z0-9_]+)_\$STAMP"/m.exec(read(`tools/demo_seed/${script}`));
    assert.ok(match, `${script}: RDB bulunamadi`);
    assert.equal(isLocalDatabaseName(`${match[1]}_20261028_121212`), true, `${script}: prova adi ${match[1]}_<damga> izin listesinde degil`);
  }
  const readme = read('tools/demo_seed/README.md');
  assert.match(readme, /## Hedef korumasi/);
  assert.ok(readme.includes('--allow-target'));
  for (const name of LOCAL_DATABASE_NAMES) assert.ok(readme.includes(name), `README ${name} adini anlatmiyor`);
});
