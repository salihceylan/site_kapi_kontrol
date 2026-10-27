// Toplu yükleme: kullanıcı adı ataması (DB'siz). Şablonda «Kullanıcı Adı» sütunu yoktur; sistem Ad Soyad'dan üretir, sistemde (her site, her şehir) ya da aynı
// yüklemede alınmışsa varyasyon dener, yönetici tabloda değiştirebilir. Gerçek PostgreSQL: scripts/qa_bulk_import.mjs (login_names bölümü).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  LOGIN_NAME_BASE_MAX,
  MAX_LOGIN_ATTEMPTS,
  checkLoginName,
  claimLoginName,
  loginNameReason,
  loginNameVariant,
  normalizeTypedLoginName,
  resolveLoginNames,
  slugifyLoginName,
  takenLoginNames,
} from '../src/modules/bulk_import_login_names.js';
import { resolvePlanAccounts, collectOverrideLoginNames } from '../src/modules/bulk_import_accounts.js';
import { computePlan } from '../src/modules/bulk_import_plan.js';
import { validateImportBody } from '../src/modules/bulk_import_body.js';

/** Sahte veritabanı: `LOWER(login_name) = ANY($1)` sorgusu; sorgu sayısını tutar. */
function fakeDb({ taken = [], emailOwners = {} } = {}) {
  const names = new Set(taken.map((name) => name.toLowerCase()));
  const calls = [];
  return {
    names,
    calls,
    async query(text, params = []) {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      calls.push({ sql, params });
      if (/^SELECT LOWER\(login_name\) AS name FROM users WHERE LOWER\(login_name\) = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
        const hits = params[0].filter((name) => names.has(name));
        return { rows: hits.map((name) => ({ name })), rowCount: hits.length };
      }
      if (/FROM users u WHERE LOWER\(u\.email\) = ANY/.test(sql)) {
        const rows = params[0].filter((email) => emailOwners[email]).map((email) => ({ email, ...emailOwners[email] }));
        return { rows, rowCount: rows.length };
      }
      return { rows: [], rowCount: 0 };
    },
  };
}

describe('slugifyLoginName / normalizeTypedLoginName', () => {
  it('ad soyaddan taban: Türkçe sadeleşir, küçük harf, öbekler tek nokta, baş/son nokta atılır, en çok 36 karakter, boşsa yedek', () => {
    assert.equal(slugifyLoginName('Çağrı Öztürk'), 'cagri.ozturk');
    assert.equal(slugifyLoginName('  İSMAİL   ŞAHİN-ÜNAL  '), 'ismail.sahin.unal');
    assert.equal(slugifyLoginName('Ahmet_Yılmaz'), 'ahmet.yilmaz');
    assert.equal(slugifyLoginName('???'), 'kullanici');
    assert.equal(slugifyLoginName(null, 'x'), 'x');
    const long = slugifyLoginName('A'.repeat(50));
    assert.equal(long.length, LOGIN_NAME_BASE_MAX);
  });

  it('yöneticinin yazdığı ad: kırp, Türkçe sadeleşir, küçük harf, boşluk nokta olur; _ ve - KORUNUR; sistem kuralı (3-40, [a-z0-9._-]) uygulanır', () => {
    assert.deepEqual(normalizeTypedLoginName('  Ahmet Yılmaz_2 '), { value: 'ahmet.yilmaz_2', error: null });
    assert.deepEqual(normalizeTypedLoginName('ali-veli'), { value: 'ali-veli', error: null });
    assert.equal(normalizeTypedLoginName('ab').error, 'TOO_SHORT');
    assert.equal(normalizeTypedLoginName('a'.repeat(41)).error, 'TOO_LONG');
    assert.equal(normalizeTypedLoginName('a'.repeat(40)).error, null);
    assert.equal(normalizeTypedLoginName('ali@veli').error, 'CHARS');
    assert.equal(normalizeTypedLoginName('ali/veli').error, 'CHARS');
    assert.equal(normalizeTypedLoginName('   ').error, 'EMPTY');
    assert.equal(normalizeTypedLoginName(null).error, 'EMPTY');
    assert.equal(normalizeTypedLoginName(12345).error, 'CHARS');
    for (const code of ['EMPTY', 'TOO_SHORT', 'TOO_LONG', 'CHARS', 'TAKEN', 'IN_FILE']) {
      assert.ok(loginNameReason(code).length > 10 && !/undefined|null/.test(loginNameReason(code)), code);
    }
  });
});

describe('loginNameVariant', () => {
  it('1. deneme taban, sonrakiler taban_N; 40 karakteri aşmaz (taban kısalır); 3 karakterden kısa taban `_2` ile başlar', () => {
    assert.equal(loginNameVariant('ali.veli', 1), 'ali.veli');
    assert.equal(loginNameVariant('ali.veli', 2), 'ali.veli_2');
    assert.equal(loginNameVariant('ali.veli', 37), 'ali.veli_37');
    const base = 'a'.repeat(36);
    assert.equal(loginNameVariant(base, 999).length, 40);
    assert.ok(loginNameVariant(base, 1000).length <= 40);
    assert.ok(loginNameVariant('b'.repeat(40), 2).length <= 40);
    assert.equal(loginNameVariant('al', 1), null, '2 karakterlik ad geçersiz olurdu');
    assert.equal(loginNameVariant('al', 2), 'al_2');
    assert.equal(loginNameVariant('x', 2), 'x_2');
    // kesilen tabanın sonunda nokta kalmaz
    assert.equal(loginNameVariant(`${'a'.repeat(35)}.b`, 1000).includes('._'), false);
  });
});

describe('resolveLoginNames', () => {
  it('sistemde alınmış ad atlanır: ilk boş varyasyon (taban, _2, _3 ...)', async () => {
    const db = fakeDb({ taken: ['ali.veli', 'ali.veli_2', 'ali.veli_3'] });
    const out = await resolveLoginNames(db, [{ key: 'a', base: 'ali.veli' }]);
    assert.equal(out.get('a'), 'ali.veli_4');
  });

  it('aynı yüklemedeki satırlar birbirinin adını almaz (satır sırasıyla): 1. taban, 2. _2, 3. _3', async () => {
    const db = fakeDb();
    const out = await resolveLoginNames(db, ['a', 'b', 'c'].map((key) => ({ key, base: 'ali.veli' })));
    assert.deepEqual([...out.values()], ['ali.veli', 'ali.veli_2', 'ali.veli_3']);
  });

  it('küçük/büyük harf farkı çakışmadır (veritabanı LOWER üzerinden tekil)', async () => {
    const db = fakeDb({ taken: ['Ali.Veli'] });
    const out = await resolveLoginNames(db, [{ key: 'a', base: 'ali.veli' }]);
    assert.equal(out.get('a'), 'ali.veli_2');
  });

  it('yöneticinin seçtiği (fixed) ad ÖNCE ayrılır: önceki satırın üretilen adı onunla çakışmaz', async () => {
    const db = fakeDb();
    const out = await resolveLoginNames(db, [
      { key: 'a', base: 'ali.veli' },
      { key: 'b', base: 'ali.veli_2', fixed: true }, // 2. satırda yönetici _2'yi seçti
      { key: 'c', base: 'ali.veli' },
    ]);
    assert.equal(out.get('b'), 'ali.veli_2');
    assert.equal(out.get('a'), 'ali.veli');
    assert.equal(out.get('c'), 'ali.veli_3', '_2 yöneticinin seçimine ayrılı');
    assert.equal(new Set(out.values()).size, 3);
  });

  it('kısa taban (2 karakter) `_2` ile başlar; tabansız adlar için ayrı varyasyonlar', async () => {
    const out = await resolveLoginNames(fakeDb(), [{ key: 'a', base: 'al' }, { key: 'b', base: 'al' }]);
    assert.deepEqual([...out.values()], ['al_2', 'al_3']);
  });

  it('SORGU SAYISI satır sayısından bağımsız: 5000 farklı ad = en çok 6 sorgu; 5000 aynı ad = sınırlı (geç varyasyonlar toplu sorgulanır)', async () => {
    const distinct = fakeDb();
    const requests = Array.from({ length: 5000 }, (_, i) => ({ key: `r${i}`, base: `kisi.${i}` }));
    const out = await resolveLoginNames(distinct, requests);
    assert.equal(out.size, 5000);
    assert.ok(distinct.calls.length <= 8, `sorgu sayısı ${distinct.calls.length}`);
    assert.ok(distinct.calls.every((call) => call.params[0].length <= 5000), 'sorgu başına en çok 5000 ad');

    const same = fakeDb();
    const sameOut = await resolveLoginNames(same, Array.from({ length: 300 }, (_, i) => ({ key: `r${i}`, base: 'mehmet.yilmaz' })));
    assert.equal(new Set(sameOut.values()).size, 300);
    assert.equal(sameOut.get('r0'), 'mehmet.yilmaz');
    assert.equal(sameOut.get('r299'), 'mehmet.yilmaz_300');
    assert.ok(same.calls.length < 40, `geç varyasyonlar gruplanır: ${same.calls.length} sorgu`);
  });

  it('ÇOK YAYGIN ad: 1000 den fazla alınmış (Türkiye genelinde binlerce «mehmet.yilmaz») olsa da boş ad bulunur; sorgu sayısı yine küçük', async () => {
    const taken = ['mehmet.yilmaz'];
    for (let attempt = 2; attempt <= 2400; attempt += 1) taken.push(loginNameVariant('mehmet.yilmaz', attempt));
    const db = fakeDb({ taken });
    const out = await resolveLoginNames(db, [{ key: 'a', base: 'mehmet.yilmaz' }, { key: 'b', base: 'mehmet.yilmaz' }]);
    assert.equal(out.get('a'), 'mehmet.yilmaz_2401');
    assert.equal(out.get('b'), 'mehmet.yilmaz_2402');
    assert.ok(db.calls.length < 30, `${db.calls.length} sorgu`);
    const claimed = await claimLoginName(fakeDb({ taken }), 'mehmet.yilmaz');
    assert.equal(claimed, 'mehmet.yilmaz_2401');
  });

  it('başka yerden rezerve edilen adlar (reserved) üretilmez; MAX_LOGIN_ATTEMPTS tükenirse null', async () => {
    const out = await resolveLoginNames(fakeDb(), [{ key: 'a', base: 'ali.veli' }], { reserved: ['ali.veli', 'ALI.VELI_2'] });
    assert.equal(out.get('a'), 'ali.veli_3');
    const taken = ['ali.veli'];
    for (let attempt = 2; attempt <= MAX_LOGIN_ATTEMPTS; attempt += 1) taken.push(loginNameVariant('ali.veli', attempt));
    const none = await resolveLoginNames(fakeDb({ taken }), [{ key: 'a', base: 'ali.veli' }]);
    assert.equal(none.get('a'), null);
  });
});

describe('claimLoginName (yazım anı)', () => {
  it('önizlemede gösterilen ad boştaysa aynen verilir', async () => {
    const db = fakeDb({ taken: ['ali.veli'] });
    assert.equal(await claimLoginName(db, 'ali.veli', { preferred: 'ali.veli_2' }), 'ali.veli_2');
  });

  it('gösterilen ad bu arada alındıysa sıradaki boş ad; başka kişiye ayrılmış ad çalınmaz; kendi ayrılmışı serbesttir', async () => {
    const db = fakeDb({ taken: ['ali.veli', 'ali.veli_2'] });
    const reserved = new Map([['ali.veli_3', 'baska.kisi']]);
    assert.equal(await claimLoginName(db, 'ali.veli', { preferred: 'ali.veli_2', reserved, key: 'ben' }), 'ali.veli_4');
    assert.equal(await claimLoginName(fakeDb({ taken: ['ali.veli', 'ali.veli_2'] }), 'ali.veli', { reserved: new Map([['ali.veli_3', 'ben']]), key: 'ben' }), 'ali.veli_3');
  });

  it('skip: az önce 23505 ile reddedilen ad tekrar verilmez', async () => {
    const out = await claimLoginName(fakeDb(), 'ali.veli', { skip: new Set(['ali.veli']) });
    assert.equal(out, 'ali.veli_2');
  });
});

describe('checkLoginName (tablo düzenlemesi)', () => {
  it('biçim hatası -> neden; alınmış ad -> TAKEN + öneri; boştaki ad -> ok ve normalleştirilmiş ad', async () => {
    const db = fakeDb({ taken: ['ali.veli', 'ali.veli_2'] });
    assert.deepEqual(await checkLoginName(db, 'ab'), { ok: false, login_name: 'ab', code: 'TOO_SHORT', message: loginNameReason('TOO_SHORT'), suggestion: null });
    assert.equal((await checkLoginName(db, 'a b@')).code, 'CHARS');
    assert.deepEqual(await checkLoginName(db, 'ALİ Veli'), {
      ok: false, login_name: 'ali.veli', code: 'TAKEN', message: loginNameReason('TAKEN'), suggestion: 'ali.veli_3',
    });
    assert.deepEqual(await checkLoginName(db, 'Yeni Ad'), { ok: true, login_name: 'yeni.ad', code: 'OK', message: null, suggestion: null });
    assert.equal(db.calls.length, 3, 'biçim hatasında veritabanına gidilmez; TAKEN için 2 sorgu (denetim + öneri), boştaki ad için 1');
  });

  it('takenLoginNames: büyük/küçük harf duyarsız, tekilleştirir, parçalara böler', async () => {
    const db = fakeDb({ taken: ['a.b.c'] });
    const set = await takenLoginNames(db, ['A.B.C', 'a.b.c', 'x.y.z']);
    assert.deepEqual([...set], ['a.b.c']);
    assert.deepEqual(db.calls[0].params[0], ['a.b.c', 'x.y.z']);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Plan: hesap bölümü
// ---------------------------------------------------------------------------------------------------------------

function snapshotWith(extra = {}) {
  return {
    blocks: [{ id: 1, name: 'A Blok' }],
    apartments: [1, 2, 3].map((n) => ({ id: 100 + n, blockId: 1, label: `Daire ${n}`, floor: null, category: null, lsNum: null, lsDen: null, responsible: 'both', hasFinance: false })),
    people: [],
    residencies: [],
    vehicles: [],
    ...extra,
  };
}
const rowsOf = (kind, list) => validateImportBody({ spec_version: 1, rows: list.map((cells, index) => ({ n: index + 2, cells })) }, kind).rows;
const planOf = (kind, snapshot, list) => computePlan({ kind, rows: rowsOf(kind, list), snapshot, today: '2026-10-27', allowOverwrite: false });
const codes = (plan, n) => plan.view.issues.filter((issue) => issue.n === n).map((issue) => `${issue.severity[0]}:${issue.code}`);

describe('plan: kullanıcı adı seçimi (giris_adi) ve eski sütun', () => {
  const person = (over = {}) => ({ ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', iliski: 'Malik', ...over });

  it('seçilen ad ops\'a normalleşmiş haliyle taşınır; hesap bilgisi satır sonucunda adaydır', () => {
    const plan = planOf('people', snapshotWith(), [person({ giris_adi: ' Ali.VELİ_2 ' })]);
    assert.equal(plan.totals.error, 0);
    assert.equal(plan.ops.find((op) => op.t === 'pc').loginName, 'ali.veli_2');
    assert.deepEqual(plan.results[0].account, { type: 'candidate', ref: 'new:2', name: 'Ali Veli', email: null, loginName: 'ali.veli_2' });
  });

  it('geçersiz biçim LOGIN_NAME_INVALID, sistemde alınmış LOGIN_NAME_TAKEN, dosyada tekrar LOGIN_NAME_DUP_IN_FILE (satır hatası; diğer satırlar yazılır)', () => {
    const snapshot = snapshotWith({ takenLoginNames: new Set(['dolu.ad']) });
    const plan = planOf('people', snapshot, [
      person({ giris_adi: 'a@b' }),
      person({ daire_no: '2', ad_soyad: 'Veli Ali', giris_adi: 'dolu.ad' }),
      person({ daire_no: '3', ad_soyad: 'Can Demir', giris_adi: 'ortak.ad' }),
      person({ daire_no: '1', blok: 'A', ad_soyad: 'Ece Kaya', giris_adi: 'ORTAK.ad', iliski: 'Kiracı' }),
    ]);
    assert.deepEqual(codes(plan, 2), ['e:LOGIN_NAME_INVALID']);
    assert.deepEqual(codes(plan, 3), ['e:LOGIN_NAME_TAKEN']);
    assert.deepEqual(codes(plan, 4), []);
    assert.deepEqual(codes(plan, 5), ['e:LOGIN_NAME_DUP_IN_FILE']);
    assert.match(plan.view.issues.find((i) => i.n === 5).message, /satır 4/);
    assert.equal(plan.view.issues.find((i) => i.n === 3).field, 'giris_adi');
    assert.equal(plan.totals.ok, 1);
    assert.equal(plan.totals.error, 3);
  });

  it('hatalı satırın adı rezerve EDİLMEZ (aynı adı sonraki geçerli satır alabilir)', () => {
    const plan = planOf('people', snapshotWith(), [
      person({ giris_adi: 'ortak.ad', iliski: 'XYZ' }), // ilişki hatası
      person({ daire_no: '2', ad_soyad: 'Veli Ali', giris_adi: 'ortak.ad' }),
    ]);
    assert.deepEqual(codes(plan, 2), ['e:RELATION_INVALID']);
    assert.deepEqual(codes(plan, 3), []);
  });

  it('hesap açılmayacak satırda (daire yok) seçilmiş ad yok sayılır, hata vermez', () => {
    const plan = planOf('people', snapshotWith({ takenLoginNames: new Set(['dolu.ad']) }), [
      { ad_soyad: 'Dairesiz Kişi', e_posta: 'd@example.com', giris_adi: 'dolu.ad' },
    ]);
    assert.equal(plan.totals.error, 0);
    assert.equal(plan.results[0].account, undefined);
  });

  it('ESKİ «kullanici_adi» hücresi yok sayılır: ops\'a girmez, satır hatası yok; dosya başına TEK bilgi uyarısı (people ve hepsi bir arada)', () => {
    const people = planOf('people', snapshotWith(), [
      person({ kullanici_adi: 'benim.adim' }),
      person({ daire_no: '2', ad_soyad: 'Veli Ali', kullanici_adi: 'baska.ad' }),
    ]);
    assert.deepEqual(codes(people, 2), ['w:LOGIN_COLUMN_IGNORED']);
    assert.deepEqual(codes(people, 3), []);
    assert.equal(people.totals.error, 0);
    assert.ok(people.ops.filter((op) => op.t === 'pc').every((op) => op.loginName === null));
    assert.equal(people.view.issues[0].field, null);
    assert.match(people.view.issues[0].message, /Kullanıcı Adı sütunu artık kullanılmıyor/);

    const all = planOf('all_in_one', snapshotWith(), [
      { ...person(), kullanici_adi: 'eski.ad' },
      { ...person({ daire_no: '2', ad_soyad: 'Veli Ali' }), kullanici_adi: 'eski.ad2' },
    ]);
    assert.deepEqual(codes(all, 2), ['w:LOGIN_COLUMN_IGNORED']);
    assert.deepEqual(codes(all, 3), []);
    assert.equal(all.totals.error, 0);
  });

  it('«Hepsi bir arada»: seçilen ad aynı kurallarla işlenir', () => {
    const snapshot = snapshotWith({ takenLoginNames: new Set(['dolu.ad']) });
    const plan = planOf('all_in_one', snapshot, [person({ giris_adi: 'dolu.ad' }), person({ daire_no: '2', ad_soyad: 'Veli Ali', giris_adi: 'serbest.ad' })]);
    assert.deepEqual(codes(plan, 2), ['e:LOGIN_NAME_TAKEN']);
    assert.deepEqual(codes(plan, 3), []);
    assert.equal(plan.results[1].account.loginName, 'serbest.ad');
  });

  it('hesaplı mevcut kişi: hesap «existing» olarak kullanıcı adıyla (salt okunur) döner; yeni hesap adayı değil', () => {
    const snapshot = snapshotWith({
      people: [{ id: 7, userCode: 55, isActive: true, spName: null, spPhone: null, spEmail: null, note: null, uName: 'Ali Veli', uPhone: null, uEmail: 'ali@example.com', uLogin: 'mevcut.hesap' }],
      residencies: [{ id: 1, apartmentId: 101, personId: 7, relation: 'owner' }],
    });
    const plan = planOf('people', snapshot, [person({ e_posta: 'ali@example.com' })]);
    assert.deepEqual(plan.results[0].account, { type: 'existing', loginName: 'mevcut.hesap' });
  });

  it('collectOverrideLoginNames: yalnız geçerli biçimli, küçük harfli, tekil adlar', () => {
    const rows = rowsOf('people', [{ ad_soyad: 'A B', giris_adi: 'Ali.Veli' }, { ad_soyad: 'B C', giris_adi: 'ali.veli' }, { ad_soyad: 'C D', giris_adi: 'a@b' }, { ad_soyad: 'D E' }]);
    assert.deepEqual(collectOverrideLoginNames(rows), ['ali.veli']);
  });
});

describe('resolvePlanAccounts', () => {
  const person = (over = {}) => ({ ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', iliski: 'Malik', ...over });

  it('yeni hesaplar: sistemde alınmış adlar atlanır, aynı dosyadaki aynı adlar _2/_3 alır; dairesiz satır hesap listesinde yok', async () => {
    const plan = planOf('people', snapshotWith(), [
      person(),
      person({ daire_no: '2', iliski: 'Kiracı' }),
      person({ daire_no: '3', ad_soyad: 'Çağrı Öztürk' }),
      { ad_soyad: 'Dairesiz Kişi', e_posta: 'd@example.com' },
    ]);
    const db = fakeDb({ taken: ['ali.veli'] });
    const { items, expected } = await resolvePlanAccounts(db, { siteCode: 1, plan });
    assert.deepEqual(items.map((i) => [i.n, i.status, i.login_name, i.editable]), [
      [2, 'new', 'ali.veli_2', true],
      [3, 'new', 'ali.veli_3', true],
      [4, 'new', 'cagri.ozturk', true],
    ]);
    assert.equal(expected.get('new:2').loginName, 'ali.veli_2');
  });

  it('e-postası mevcut BAĞLANABİLİR hesaba ait kişi salt okunur «existing» (o hesabın kullanıcı adı); bağlanamaz hesap «email_in_use»', async () => {
    const plan = planOf('people', snapshotWith(), [
      person({ e_posta: 'komsu@example.com' }),
      person({ daire_no: '2', ad_soyad: 'Veli Ali', e_posta: 'yonetici@example.com' }),
      person({ daire_no: '3', ad_soyad: 'Can Demir', e_posta: 'yeni@example.com' }),
    ]);
    const db = fakeDb({
      emailOwners: {
        'komsu@example.com': { user_code: 77, login_name: 'komsu.hesabi', linkable: true },
        'yonetici@example.com': { user_code: 55, login_name: 'yonetici', linkable: false },
      },
    });
    const { items } = await resolvePlanAccounts(db, { siteCode: 1, plan });
    assert.deepEqual(items.map((i) => [i.n, i.status, i.login_name, i.editable]), [
      [2, 'existing', 'komsu.hesabi', false],
      [3, 'email_in_use', null, false],
      [4, 'new', 'can.demir', true],
    ]);
    assert.equal(db.calls.filter((c) => /u\.email/.test(c.sql)).length, 1, 'e-postalar tek sorguda');
  });

  it('seçilen ad olduğu gibi (custom: true), üretilen adlar ona çakışmaz; aynı kişi iki dairede tek ad (ikinci satır «shared»)', async () => {
    const plan = planOf('people', snapshotWith(), [
      person(),
      person({ daire_no: '2', ad_soyad: 'Veli Ali', giris_adi: 'ali.veli' }),
      person({ ad_soyad: 'Ali Veli', daire_no: '3', e_posta: 'ali@example.com' }),
      person({ ad_soyad: 'Ali Veli', daire_no: '2', e_posta: 'ali@example.com', iliski: 'Aile' }),
    ]);
    const { items } = await resolvePlanAccounts(fakeDb(), { siteCode: 1, plan });
    const byN = Object.fromEntries(items.map((i) => [i.n, i]));
    assert.deepEqual([byN[3].login_name, byN[3].custom], ['ali.veli', true]);
    assert.equal(byN[2].login_name, 'ali.veli_2', 'üretilen ad, seçilen adı çalmaz');
    assert.equal(byN[2].custom, false);
  });

  it('imza: adlar değişirse değişir; hesap yoksa boş (hash değişmez)', async () => {
    const plan = planOf('people', snapshotWith(), [person()]);
    const a = await resolvePlanAccounts(fakeDb(), { siteCode: 1, plan });
    const b = await resolvePlanAccounts(fakeDb({ taken: ['ali.veli'] }), { siteCode: 1, plan });
    assert.notEqual(a.signature, b.signature);
    const none = planOf('people', snapshotWith(), [{ ad_soyad: 'Dairesiz', e_posta: 'x@example.com' }]);
    assert.equal((await resolvePlanAccounts(fakeDb(), { siteCode: 1, plan: none })).signature, '');
  });
});
