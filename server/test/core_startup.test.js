import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const serverEntry = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src', 'server.js');

// Bos bir calisma dizini: dotenv gelistirici makinedeki gercek server/.env dosyasini YUKLEMESIN.
const emptyCwd = fs.mkdtempSync(path.join(os.tmpdir(), 'kapi-startup-test-'));

// Gercek sunucu girisini ayri surecte baslatir. DB her zaman ULASILAMAZ bir porta (127.0.0.1:1)
// yonlendirilir: gercek DB'ye dokunulmaz; surec en gec "Server startup failed" ile cikar.
function startServer(env) {
  const result = spawnSync(process.execPath, [serverEntry], {
    env: {
      PATH: process.env.PATH,
      SystemRoot: process.env.SystemRoot,
      DB_HOST: '127.0.0.1',
      DB_PORT: '1',
      ...env,
    },
    cwd: emptyCwd,
    encoding: 'utf8',
    timeout: 30000,
  });
  return { status: result.status, output: `${result.stdout || ''}\n${result.stderr || ''}` };
}

describe('sunucu baslangic dogrulamasi (C12)', () => {
  after(() => {
    fs.rmSync(emptyCwd, { recursive: true, force: true });
  });

  it('yer tutucu JWT_SECRET: baslatma REDDEDILIR (exit 1) ve DB e hic baglanilmaz', () => {
    const { status, output } = startServer({ JWT_SECRET: 'change_this_secret' });
    assert.equal(status, 1);
    assert.match(output, /\[ENV\] HATA: JWT_SECRET/);
    assert.equal(output.includes('Server startup failed'), false, 'env kontrolu DB den ONCE olmali');
  });

  it('bos JWT_SECRET: baslatma reddedilir', () => {
    const { status, output } = startServer({});
    assert.equal(status, 1);
    assert.match(output, /\[ENV\] HATA: JWT_SECRET/);
  });

  it('20 karakterlik (kisa) gercek secret: yalnizca UYARI; baslatma env nedeniyle KAPANMAZ (DB asamasina gecer)', () => {
    const { output } = startServer({ JWT_SECRET: 'q8Wr-test-short-20ch' });
    assert.match(output, /\[ENV\] UYARI: JWT_SECRET 20 karakter/);
    assert.equal(output.includes('[ENV] HATA'), false);
    assert.match(output, /Server startup failed/, 'env kontrolunu gecip DB baglantisini denemeli');
    assert.equal(output.includes('q8Wr-test-short-20ch'), false, 'secret asla loglanmamali');
  });
});
