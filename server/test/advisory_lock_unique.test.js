// PostgreSQL advisory kilit anahtarlarının TEKİLLİĞİ (kaynak düzeyi, DB'siz).
//
// İki-int anahtar (sınıf, iş) paylaşılan bir uzaydır: aynı sınıfta iki farklı arka plan işi AYNI iş numarasını kullanırsa biri çalışırken diğeri
// sessizce "kilitli" sayılıp atlanır (örn. finans hatırlatma kuyruğu ile push kuyruğu 4'ü paylaşsaydı acil duyuru push'u gecikirdi).
// Bu test: (1) ANNOUNCEMENT_LOCK_JOBS değerleri tekil; (2) kilit sınıfları kaynak genelinde tekil; (3) aynı sınıfın iş numaraları tekil;
// (4) src içinde SABİT SAYILI advisory çağrısı ve ANNC sınıfı / iş numarası sabiti kullanımı yok (yalnız announcement_lock.js sabitleri).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS } from '../src/modules/announcement_lock.js';

const here = dirname(fileURLToPath(import.meta.url));
const SRC = join(here, '..', 'src');

function listJs(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...listJs(full));
    else if (name.endsWith('.js')) out.push(full);
  }
  return out;
}
const stripComments = (text) => text.replace(/^\s*\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
const FILES = listJs(SRC).map((path) => ({ rel: relative(SRC, path).replace(/\\/g, '/'), code: stripComments(readFileSync(path, 'utf8')) }));
const numberOf = (token) => Number(token);

/** `const|export const NAME = <sayı>` tanımları (sınıf / iş sabitleri). */
function numericConstants(pattern) {
  const found = [];
  for (const file of FILES) {
    for (const match of file.code.matchAll(/(?:export\s+)?const\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F]+|\d+)\s*;/g)) {
      if (pattern.test(match[1])) found.push({ file: file.rel, name: match[1], value: numberOf(match[2]) });
    }
  }
  return found;
}

describe('ANNOUNCEMENT_LOCK_JOBS (ANNC sınıfı)', () => {
  it('iş numaraları pozitif, int4 aralığında ve TEKİL; finans hatırlatma ile push kuyruğu AYRI numaralar', () => {
    const values = Object.values(ANNOUNCEMENT_LOCK_JOBS);
    assert.equal(new Set(values).size, values.length, 'tekil');
    for (const value of values) assert.ok(Number.isInteger(value) && value > 0 && value < 2 ** 31, String(value));
    assert.equal(ANNOUNCEMENT_LOCK_JOBS.financeReminder, 4);
    assert.equal(ANNOUNCEMENT_LOCK_JOBS.pushQueue, 5);
    assert.notEqual(ANNOUNCEMENT_LOCK_JOBS.financeReminder, ANNOUNCEMENT_LOCK_JOBS.pushQueue);
    assert.deepEqual(Object.keys(ANNOUNCEMENT_LOCK_JOBS), ['scheduler', 'emailQueue', 'emailGlobal', 'financeReminder', 'pushQueue']);
    assert.throws(() => { ANNOUNCEMENT_LOCK_JOBS.financeReminder = 9; }, TypeError, 'dondurulmuş');
  });

  it('ANNC sınıfı ile çalışan her iş sabiti ANNOUNCEMENT_LOCK_JOBS üyesinden türer (sihirli sayı yok)', () => {
    const expected = {
      'announcement_email_queue.js': ['EMAIL_QUEUE_LOCK_JOB', 'emailQueue'],
      'announcement_scheduler.js': ['SCHEDULER_LOCK_JOB', 'scheduler'],
      'finance_reminder_queue.js': ['FINANCE_REMINDER_LOCK_JOB', 'financeReminder'],
      'push_worker.js': ['PUSH_QUEUE_LOCK_JOB', 'pushQueue'],
    };
    for (const [file, [constant, member]] of Object.entries(expected)) {
      const source = FILES.find((entry) => entry.rel === `modules/${file}`);
      assert.ok(source, `${file} bulunamadı`);
      assert.match(source.code, new RegExp(`export const ${constant} = ANNOUNCEMENT_LOCK_JOBS\\.${member};`), `${file}: ${constant}`);
    }
    // ANNC sınıfı kullanan HER (sınıf, iş) çiftinde iş ANNOUNCEMENT_LOCK_JOBS üyesi ya da onun türevi sabit olmalı
    const allowedJobExpressions = /^(?:ANNOUNCEMENT_LOCK_JOBS\.[A-Za-z]+|job|EMAIL_QUEUE_LOCK_JOB|SCHEDULER_LOCK_JOB|FINANCE_REMINDER_LOCK_JOB|PUSH_QUEUE_LOCK_JOB)$/;
    let pairs = 0;
    for (const file of FILES) {
      for (const match of file.code.matchAll(/\[\s*ANNOUNCEMENT_LOCK_CLASS\s*,\s*([^\]]+?)\s*\]/g)) {
        pairs += 1;
        assert.match(match[1], allowedJobExpressions, `${file.rel}: ANNC sınıfı ile izinsiz iş ifadesi: ${match[1]}`);
      }
    }
    assert.ok(pairs >= 4, `en az 4 (sınıf, iş) çifti bulundu: ${pairs}`);
  });

  it('acquireSessionLock yalnız ANNOUNCEMENT_LOCK_JOBS üyeleri / türev sabitlerle çağrılır (sayı literal yok)', () => {
    let calls = 0;
    for (const file of FILES) {
      for (const match of file.code.matchAll(/acquireSessionLock\(\s*([^)]*?)\s*\)/g)) {
        if (/^job$/.test(match[1]) || match[1] === '') continue; // tanım satırı
        calls += 1;
        assert.equal(/^\d/.test(match[1]), false, `${file.rel}: acquireSessionLock sayı literaliyle çağrılmış`);
        assert.match(match[1], /^(?:ANNOUNCEMENT_LOCK_JOBS\.[A-Za-z]+|[A-Z_]+_LOCK_JOB)$/, `${file.rel}: ${match[1]}`);
      }
    }
    assert.ok(calls >= 2, `çağrı bulundu: ${calls}`);
  });
});

describe('kilit sınıfları ve iş numaraları (tüm src)', () => {
  it('sınıf sabitleri (…_LOCK_CLASS, MAINTENANCE_LOCK[0]) kaynak genelinde birbirinden FARKLI; hepsi int4', () => {
    const classes = numericConstants(/_LOCK_CLASS$/);
    const maintenance = FILES.find((file) => file.rel === 'modules/document_maintenance.js');
    const maintenanceMatch = /MAINTENANCE_LOCK\s*=\s*Object\.freeze\(\[\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(\d+)\s*\]\)/.exec(maintenance.code);
    assert.ok(maintenanceMatch, 'MAINTENANCE_LOCK tanımı bulunamadı');
    const all = [...classes.map((entry) => ({ name: `${entry.file}:${entry.name}`, value: entry.value })), { name: 'document_maintenance.js:MAINTENANCE_LOCK', value: numberOf(maintenanceMatch[1]) }];
    assert.ok(all.length >= 5, `en az 5 sınıf: ${all.map((entry) => entry.name).join(', ')}`);
    for (const entry of all) assert.ok(Number.isInteger(entry.value) && entry.value > 0 && entry.value < 2 ** 31, entry.name);
    const byValue = new Map();
    for (const entry of all) byValue.set(entry.value, [...(byValue.get(entry.value) ?? []), entry.name]);
    for (const [value, names] of byValue) assert.equal(names.length, 1, `0x${value.toString(16)} birden çok sınıfta: ${names.join(', ')}`);
    assert.ok(byValue.has(ANNOUNCEMENT_LOCK_CLASS));
  });

  it('aynı sınıf içinde iş numaraları TEKİL: client_error (CLER) yazma/temizlik işleri farklı; tek-işli sınıflarda (CONFIG, DOCS) iş 1', () => {
    const jobs = numericConstants(/_LOCK_JOB$/).filter((entry) => !/^(EMAIL_QUEUE|SCHEDULER|FINANCE_REMINDER|PUSH_QUEUE)_LOCK_JOB$/.test(entry.name));
    const clientError = jobs.filter((entry) => entry.file === 'modules/client_error_service.js');
    assert.equal(clientError.length, 2);
    assert.notEqual(clientError[0].value, clientError[1].value, 'CLER: WRITE ve PURGE işleri aynı numarada');
    const config = jobs.filter((entry) => entry.file === 'modules/platform_config_service.js');
    assert.equal(config.length, 1);
    // aynı dosyada tanımlı sınıfların işleri başka dosyadaki sınıfla karışmaz: sınıf sabitleri tekil olduğundan (yukarıdaki test) çiftler tekildir
    const classOf = (file) => numericConstants(/_LOCK_CLASS$/).filter((entry) => entry.file === file).map((entry) => entry.value);
    assert.equal(classOf('modules/client_error_service.js').length, 1);
    assert.equal(classOf('modules/platform_config_service.js').length, 1);
  });

  it('src içinde SABİT SAYILI advisory kilit çağrısı YOK; ANNC sınıfı yalnız announcement_lock.js sabitiyle (0x414E4E43 başka dosyada literal olarak geçmez)', () => {
    for (const file of FILES) {
      for (const match of file.code.matchAll(/pg_(?:try_)?advisory_(?:xact_)?(?:un)?lock\(([^)]*)\)/g)) {
        const args = match[1];
        if (/hashtext\(/.test(args) || /\$\d/.test(args)) continue;
        assert.fail(`${file.rel}: sabit sayılı advisory çağrısı: ${match[0]}`);
      }
      if (file.rel !== 'modules/announcement_lock.js') {
        assert.equal(/0x414e4e43|1095650883/i.test(file.code), false, `${file.rel}: ANNC sınıfı literal olarak kullanılmış`);
      }
    }
  });

  it('iki-int çağrılarda (sınıf, iş) parametre dizisinin elemanları sayı literal DEĞİL', () => {
    let twoInt = 0;
    for (const file of FILES) {
      for (const match of file.code.matchAll(/pg_(?:try_)?advisory_(?:xact_)?(?:un)?lock\(\s*\$1::int\s*,\s*\$2::int\s*\)[^;]*?,\s*(?:\[([^\]]*)\]|(\.\.\.)?([A-Za-z_][A-Za-z0-9_]*))/g)) {
        twoInt += 1;
        const elements = match[1] !== undefined ? match[1].split(',').map((part) => part.trim()) : [];
        for (const element of elements) assert.equal(/^\d|^0x/i.test(element), false, `${file.rel}: literal parametre: ${element}`);
      }
    }
    assert.ok(twoInt >= 6, `iki-int çağrı sayısı: ${twoInt}`);
  });
});
