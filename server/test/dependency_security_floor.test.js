// Guvenlik yamali bagimlilik tabani (guvenlik denetimi secrets-config-5, `npm audit --omit=dev`):
//   body-parser >= 1.20.9  GHSA-27r3-jxmh-p828: sikistirilmis govdede sondaki baytlarla API surecini dusurme (express 4.x, ~1.20.5 araligi 1.20.9'u kapsar)
//   nodemailer  >= 10.1.4  GHSA-8c8m-p3m8-cjg8 / GHSA-m943-m63m-w62w / GHSA-85x2-q946-cp5h: addressparser baska bir aliciya teslim ettirebilir
// `npm ci` kilitteki surumleri kurar; bu test kilidin (ya da package.json taban araliginin) eski surume geri sarilmasini yakalar.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const readJson = (relative) => JSON.parse(readFileSync(new URL(relative, import.meta.url), 'utf8'));
const lock = readJson('../package-lock.json');
const manifest = readJson('../package.json');

const triple = (version) => {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(String(version).replace(/^[\s^~>=<v]+/, ''));
  assert.ok(match, `surum cozumlenemedi: ${version}`);
  return match.slice(1).map(Number);
};
const atLeast = (version, floor) => {
  const a = triple(version);
  const b = triple(floor);
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] > b[i];
  }
  return true;
};
const lockedCopies = (name) =>
  Object.entries(lock.packages)
    .filter(([path]) => path === `node_modules/${name}` || path.endsWith(`/node_modules/${name}`))
    .map(([path, entry]) => ({ path, version: entry.version }));

const FLOORS = [
  { name: 'body-parser', floor: '1.20.9', why: 'GHSA-27r3-jxmh-p828' },
  { name: 'nodemailer', floor: '10.1.4', why: 'addressparser GHSA-8c8m-p3m8-cjg8 / m943-m63m-w62w / 85x2-q946-cp5h' },
];

describe('guvenlik yamali bagimlilik tabani', () => {
  for (const { name, floor, why } of FLOORS) {
    it(`kilitteki her ${name} kopyasi >= ${floor} (${why})`, () => {
      const copies = lockedCopies(name);
      assert.ok(copies.length >= 1, `${name} kilit dosyasinda yok`);
      for (const copy of copies) assert.ok(atLeast(copy.version, floor), `${copy.path} ${copy.version} < ${floor}`);
    });
  }

  it('package.json nodemailer taban araligi yamali surumu kapsar', () => {
    assert.ok(atLeast(manifest.dependencies.nodemailer, '10.1.4'), `nodemailer araligi: ${manifest.dependencies.nodemailer}`);
  });

  it('surum karsilastirmasi (yardimci) dogru calisir', () => {
    assert.equal(atLeast('1.20.9', '1.20.9'), true);
    assert.equal(atLeast('1.20.8', '1.20.9'), false);
    assert.equal(atLeast('1.21.0', '1.20.9'), true);
    assert.equal(atLeast('2.0.0', '1.20.9'), true);
    assert.equal(atLeast('^10.2.1', '10.1.4'), true);
    assert.equal(atLeast('10.0.13', '10.1.4'), false);
  });
});
