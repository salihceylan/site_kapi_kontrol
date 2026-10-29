// scripts/trial_code.mjs: argüman ayrıştırma ve güvenlik kapıları (veritabanına HİÇ bağlanmadan): yazan komutlar --yes ister, kullanım çıkış kodları.
import { describe, it, afterEach, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { main, parseArgs } from '../scripts/trial_code.mjs';

describe('trial_code.mjs parseArgs', () => {
  it('komut, konumsal argümanlar ve bayraklar', () => {
    const { opts, errors } = parseArgs(['create', '--days', '7', '--note', 'Aday A', '--yes']);
    assert.deepEqual(errors, []);
    assert.equal(opts.command, 'create');
    assert.equal(opts.days, '7');
    assert.equal(opts.note, 'Aday A');
    assert.equal(opts.yes, true);
    const demo = parseArgs(['demo', '1234567890', '--off', '-y']);
    assert.equal(demo.opts.command, 'demo');
    assert.deepEqual(demo.opts.positional, ['1234567890']);
    assert.equal(demo.opts.off, true);
    assert.equal(demo.opts.yes, true);
  });

  it('bilinmeyen bayrak ve eksik değer hata verir', () => {
    assert.ok(parseArgs(['create', '--bilinmeyen']).errors.length > 0);
    assert.ok(parseArgs(['create', '--days']).errors.length > 0);
    assert.ok(parseArgs(['create', '--note']).errors.length > 0);
  });
});

describe('trial_code.mjs main: veritabanına gitmeden çıkış kodları', () => {
  beforeEach(() => {
    mock.method(console, 'log', () => {});
    mock.method(console, 'error', () => {});
  });
  afterEach(() => mock.restoreAll());

  it('argümansız çağrı yalnız kullanım basar (2); --help 0', async () => {
    assert.equal(await main([]), 2);
    assert.equal(await main(['--help']), 0);
  });

  it('bilinmeyen komut / bayrak 2', async () => {
    assert.equal(await main(['bilinmeyen']), 2);
    assert.equal(await main(['create', '--bilinmeyen']), 2);
  });

  it('veritabanına yazan HER komut --yes olmadan reddedilir (3) ve veritabanına bağlanılmaz', async () => {
    for (const argv of [['create'], ['create', '--days', '3'], ['demo', '1234567890'], ['demo', '1234567890', '--off'], ['revoke', '1']]) {
      assert.equal(await main(argv, {}), 3, argv.join(' '));
    }
  });
});
